#!/usr/bin/env bash
# Publish the XPACKAGENAMEX coin package and finish its registration.
#
# Usage:
#   bash scripts/publish.sh [<network>] [--confirm-immutable] [--output-env]
#
#   <network>            Sui CLI environment alias (default: testnet). The ACTIVE env must match —
#                        the script never switches environments for you.
#   --confirm-immutable  Burn the UpgradeCap without prompting (IRREVERSIBLE).
#   --output-env         Also print the resulting IDs as KEY=VALUE lines on stdout.
#
# Steps (each is resumable — IDs are saved to .env.<network> as soon as they exist, so a re-run
# continues where a failed run stopped instead of publishing a second package):
#   1. publish                       → package, pending Currency, UpgradeCap, the initial-supply Coin (if any),
#                                      and whichever of TreasuryCap / MetadataCap the coin's policies keep
#                                      (a fixed supply has no TreasuryCap, frozen metadata no MetadataCap —
#                                      `init` applied both in this transaction)
#   2. coin_registry::finalize_registration → shared, wallet-discoverable Currency<SUI_TOKEN_TEMPLATE>
#   3. coin_registry::set_icon_url   → network-specific icon (needs SUI_TOKEN_TEMPLATE_ICON_URL);
#                                      skipped when the metadata policy is "frozen" (the icon is the
#                                      ICON_URL constant, for good)
#   4. package::make_immutable       → only with --confirm-immutable or an interactive CONFIRM;
#                                      verified by the UpgradeCap no longer existing (a definite
#                                      "not found"; a lookup that merely failed stops the run).
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ─ Utility functions (inlined; no external common.sh in standalone packages) ─

log() {
	echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >&2
}

require_env() {
	local var_name=$1
	if [[ -z "${!var_name:-}" ]]; then
		log "ERROR: $var_name is not set"
		exit 1
	fi
}

load_env() {
	local env_file="$PKG_DIR/.env.$1"
	[[ -f "$env_file" ]] || { touch "$env_file"; log "Created empty .env.$1"; }
	set +u
	# shellcheck source=/dev/null
	source "$env_file"
	set -u
}

save_env() {
	local network=$1 key=$2 value=$3
	local env_file="$PKG_DIR/.env.${network}"
	if grep -q "^${key}=" "$env_file" 2>/dev/null; then
		sed -i.bak "s|^${key}=.*|${key}=${value}|" "$env_file"
		rm -f "${env_file}.bak"
	else
		echo "${key}=${value}" >> "$env_file"
	fi
	log "Saved ${key}=${value} to .env.${network}"
}

get_published_at() {
	echo "$1" | jq -r '.objectChanges[] | select(.type == "published") | .packageId'
}

# get_created_object <json> <type suffix> — the single created object whose type ends with the suffix.
get_created_object() {
	echo "$1" | jq -r --arg t "$2" \
		'[.objectChanges[] | select(.type == "created" and (.objectType | endswith($t))) | .objectId]
		 | if length == 1 then .[0] else "" end'
}

# run_json <cmd…> — run a sui CLI command, return its JSON body; on failure log the output and exit.
run_json() {
	local out
	if ! out=$("$@" 2>&1); then
		log "ERROR: command failed: $*"
		log "$out"
		exit 1
	fi
	echo "$out" | awk '/^{/,0'
}

# BEGIN object_state (the same block is in scripts/deploy_token.sh; tests/generator.test.sh compares them)
# object_state <id> — prints exactly one word: found | gone | unknown.
#   found    the CLI returned the object.
#   gone     the CLI said the object definitely does not exist: a "not found" for THIS object id (what a
#            consumed object gives), or a JSON "deleted" / "notExists" error.
#   unknown  anything else (RPC outage, timeout, wrong environment, unreadable output); the CLI output goes
#            to stderr. Only "gone" may be read as "the UpgradeCap was consumed".
object_state() {
	local want out rc=0 json
	want=$(printf '%s' "${1#0x}" | tr '[:upper:]' '[:lower:]' | sed 's/^0*//')
	out=$(sui client object "$1" --json 2>&1) || rc=$?
	json=$(printf '%s\n' "$out" | awk '/^{/,0')
	if [[ $rc -eq 0 ]]; then
		if jq -e '.objectId != null' <<<"$json" >/dev/null 2>&1; then echo found; return 0; fi
		if jq -e '(.error.code // "") | test("^(deleted|notExists)$")' <<<"$json" >/dev/null 2>&1; then echo gone; return 0; fi
	elif printf '%s\n' "$out" | tr '[:upper:]' '[:lower:]' | grep -Eq "object 0x0*${want} not found"; then
		echo gone; return 0
	fi
	printf 'sui client object %s: could not tell whether the object exists (exit %s):\n%s\n' "$1" "$rc" "$out" >&2
	echo unknown
}
# END object_state

# ─ Arguments ─────────────────────────────────────────────────────────────────

NETWORK=testnet
OUTPUT_ENV=false
CONFIRM_IMMUTABLE=false
if [[ $# -gt 0 && "$1" != --* ]]; then
	NETWORK=$1
	shift
fi
while [[ $# -gt 0 ]]; do
	case "$1" in
		--output-env) OUTPUT_ENV=true ;;
		--confirm-immutable) CONFIRM_IMMUTABLE=true ;;
		*) log "ERROR: unknown argument '$1' (expected [<network>] [--confirm-immutable] [--output-env])"; exit 1 ;;
	esac
	shift
done

ACTIVE_ENV="$(sui client active-env 2>/dev/null || true)"
if [[ "$ACTIVE_ENV" != "$NETWORK" ]]; then
	log "ERROR: active Sui env is '${ACTIVE_ENV}', but this run targets '${NETWORK}'."
	log "       Switch first: sui client switch --env ${NETWORK}"
	exit 1
fi

load_env "$NETWORK"
COIN_TYPE_SUFFIX="::XMODULENAMEX::SUI_TOKEN_TEMPLATE"
# Fixed when the package was generated; "frozen" means init deleted the MetadataCap.
METADATA_POLICY="XMETADATAPOLICYX"

# ─ 1. Publish ────────────────────────────────────────────────────────────────

if [[ -n "${SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID:-}" ]]; then
	log "XPACKAGENAMEX already published: $SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID (resuming)"
else
	[[ "$METADATA_POLICY" == "frozen" ]] || require_env "SUI_TOKEN_TEMPLATE_ICON_URL"
	log "Publishing XPACKAGENAMEX package from $PKG_DIR..."
	if [[ "$NETWORK" == "localnet" ]]; then
		# Sui >= 1.80 only publishes to environments declared in Move.toml; localnet uses an
		# ephemeral test-publish (its pubfile is discarded — localnet state is throwaway anyway).
		PUBLISH_OUTPUT=$(run_json sui client test-publish "$PKG_DIR" --json --build-env testnet \
			--pubfile-path "${TMPDIR:-/tmp}/pub-localnet-$$-${RANDOM}.toml")
	else
		PUBLISH_OUTPUT=$(run_json sui client publish "$PKG_DIR" --json)
	fi

	SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID=$(get_published_at "$PUBLISH_OUTPUT")
	SUI_TOKEN_TEMPLATE_TREASURY_CAP_ID=$(get_created_object "$PUBLISH_OUTPUT" "::coin::TreasuryCap<${SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID}${COIN_TYPE_SUFFIX}>")
	SUI_TOKEN_TEMPLATE_METADATA_CAP_ID=$(get_created_object "$PUBLISH_OUTPUT" "::coin_registry::MetadataCap<${SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID}${COIN_TYPE_SUFFIX}>")
	SUI_TOKEN_TEMPLATE_PENDING_CURRENCY_ID=$(get_created_object "$PUBLISH_OUTPUT" "::coin_registry::Currency<${SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID}${COIN_TYPE_SUFFIX}>")
	SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID=$(get_created_object "$PUBLISH_OUTPUT" "::package::UpgradeCap")
	# The minted initial supply (absent when the supply is 0). Exact type: `Coin<…>` also ends the type of
	# no other object created here.
	SUI_TOKEN_TEMPLATE_INITIAL_COIN_ID=$(get_created_object "$PUBLISH_OUTPUT" "::coin::Coin<${SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID}${COIN_TYPE_SUFFIX}>")

	# Always present.
	for v in SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID SUI_TOKEN_TEMPLATE_PENDING_CURRENCY_ID SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID; do
		if [[ -z "${!v}" || "${!v}" == "null" ]]; then
			log "ERROR: could not extract $v from publish output"
			log "Output: $PUBLISH_OUTPUT"
			exit 1
		fi
	done
	# Present only if the coin's policies keep them. A MetadataCap is required unless the metadata is frozen;
	# a missing TreasuryCap means a fixed supply, which the registry records.
	if [[ "$METADATA_POLICY" != "frozen" && -z "$SUI_TOKEN_TEMPLATE_METADATA_CAP_ID" ]]; then
		log "ERROR: could not extract the MetadataCap from publish output (metadata policy: $METADATA_POLICY)"
		log "Output: $PUBLISH_OUTPUT"
		exit 1
	fi
	for v in SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID SUI_TOKEN_TEMPLATE_PENDING_CURRENCY_ID SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID \
		SUI_TOKEN_TEMPLATE_TREASURY_CAP_ID SUI_TOKEN_TEMPLATE_METADATA_CAP_ID SUI_TOKEN_TEMPLATE_INITIAL_COIN_ID; do
		[[ -z "${!v}" ]] || save_env "$NETWORK" "$v" "${!v}"
	done
	log "Published XPACKAGENAMEX package successfully"
fi
COIN_TYPE="${SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID}${COIN_TYPE_SUFFIX}"

# ─ 2. finalize_registration ──────────────────────────────────────────────────
# OTW currencies need this second step to become a real, shared, RPC-discoverable
# Currency<SUI_TOKEN_TEMPLATE>. Anyone may perform it; doing it here keeps deploys self-contained.

if [[ -n "${SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID:-}" ]]; then
	log "Currency already registered: $SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID"
else
	require_env "SUI_TOKEN_TEMPLATE_PENDING_CURRENCY_ID"
	log "Promoting Currency<SUI_TOKEN_TEMPLATE> via coin_registry::finalize_registration..."
	FINALIZE_REG_OUTPUT=$(run_json sui client call \
		--package 0x2 \
		--module coin_registry \
		--function finalize_registration \
		--type-args "$COIN_TYPE" \
		--args 0xc "$SUI_TOKEN_TEMPLATE_PENDING_CURRENCY_ID" \
		--gas-budget 100000000 \
		--json)
	SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID=$(get_created_object "$FINALIZE_REG_OUTPUT" "::coin_registry::Currency<${COIN_TYPE}>")
	if [[ -z "$SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID" ]]; then
		log "ERROR: could not extract the shared Currency<SUI_TOKEN_TEMPLATE> ID from finalize_registration output"
		log "Output: $FINALIZE_REG_OUTPUT"
		exit 1
	fi
	save_env "$NETWORK" "SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID" "$SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID"
fi

# ─ 3. Network-specific icon URL (while the sender still holds MetadataCap) ──

if [[ -z "${SUI_TOKEN_TEMPLATE_METADATA_CAP_ID:-}" ]]; then
	log "Metadata is frozen (no MetadataCap): the icon stays the ICON_URL constant compiled into the package"
elif [[ "${SUI_TOKEN_TEMPLATE_ICON_URL_SET:-}" == "${SUI_TOKEN_TEMPLATE_ICON_URL:-}" && -n "${SUI_TOKEN_TEMPLATE_ICON_URL:-}" ]]; then
	log "Icon URL already set: $SUI_TOKEN_TEMPLATE_ICON_URL"
else
	require_env "SUI_TOKEN_TEMPLATE_ICON_URL"
	log "Setting icon URL via coin_registry::set_icon_url..."
	run_json sui client call \
		--package 0x2 \
		--module coin_registry \
		--function set_icon_url \
		--type-args "$COIN_TYPE" \
		--args "$SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID" "$SUI_TOKEN_TEMPLATE_METADATA_CAP_ID" "$SUI_TOKEN_TEMPLATE_ICON_URL" \
		--gas-budget 100000000 \
		--json > /dev/null
	save_env "$NETWORK" "SUI_TOKEN_TEMPLATE_ICON_URL_SET" "$SUI_TOKEN_TEMPLATE_ICON_URL"
fi

# ─ 4. Irreversible: burn the UpgradeCap to make the package immutable ───────

# read_cap_state — sets CAP_STATE (found | gone) from the UpgradeCap lookup. A lookup that cannot answer
# definitely stops the run instead of being read as "consumed" (an unverifiable lookup is never a claim of
# immutability). Call it directly, not inside $(...): the exit must end the script.
read_cap_state() {
	CAP_STATE=$(object_state "$SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID")
	if [[ "$CAP_STATE" == "unknown" ]]; then
		log "ERROR: cannot tell whether UpgradeCap $SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID still exists (see the CLI output above)."
		log "       Nothing is claimed about immutability. Re-run when the node answers, or check: sui client object $SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID"
		exit 1
	fi
}

burn_upgrade_cap() {
	log "Making XPACKAGENAMEX package immutable (this is IRREVERSIBLE)..."
	run_json sui client call \
		--package 0x2 \
		--module package \
		--function make_immutable \
		--args "$SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID" \
		--gas-budget 100000000 \
		--json > /dev/null
	# A package object is always "Immutable"-owned, so the only proof of immutability is that the
	# UpgradeCap was consumed: a definite "not found", not merely a failed lookup.
	read_cap_state
	if [[ "$CAP_STATE" != "gone" ]]; then
		log "ERROR: UpgradeCap $SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID still exists after make_immutable"
		exit 1
	fi
	log "✓ Package $SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID is now permanently immutable (UpgradeCap consumed)"
}

if [[ -z "${SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID:-}" ]]; then
	log "ERROR: no UpgradeCap ID is recorded in .env.$NETWORK, so immutability cannot be verified."
	exit 1
fi
read_cap_state
if [[ "$CAP_STATE" == "gone" ]]; then
	log "UpgradeCap already consumed — package is immutable"
elif [[ "$CONFIRM_IMMUTABLE" == "true" ]]; then
	burn_upgrade_cap
else
	log ""
	log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	log "UpgradeCap $SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID NOT burned — the package remains upgradeable."
	log "Burn it now, or later with: bash $0 $NETWORK --confirm-immutable"
	read -r -p "Type CONFIRM to burn the UpgradeCap and make the package immutable: " ANSWER
	if [[ "$ANSWER" == "CONFIRM" ]]; then
		burn_upgrade_cap
	else
		log "Skipped immutability step. UpgradeCap $SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID is retained."
	fi
	log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

if [[ "$OUTPUT_ENV" == "true" ]]; then
	echo "SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID=$SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID"
	echo "SUI_TOKEN_TEMPLATE_TREASURY_CAP_ID=${SUI_TOKEN_TEMPLATE_TREASURY_CAP_ID:-}"
	echo "SUI_TOKEN_TEMPLATE_METADATA_CAP_ID=${SUI_TOKEN_TEMPLATE_METADATA_CAP_ID:-}"
	echo "SUI_TOKEN_TEMPLATE_INITIAL_COIN_ID=${SUI_TOKEN_TEMPLATE_INITIAL_COIN_ID:-}"
	echo "SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID=$SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID"
	echo "SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID=$SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID"
fi
