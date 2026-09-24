#!/usr/bin/env bash
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ─ Utility functions (inlined; no external common.sh in standalone packages) ─

log() {
	echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

require_env() {
	local var_name=$1
	if [[ -z "${!var_name:-}" ]]; then
		log "ERROR: $var_name is not set"
		exit 1
	fi
}

load_env() {
	local network=$1
	local env_file="$PKG_DIR/.env.${network}"
	if [[ ! -f "$env_file" ]]; then
		mkdir -p "$(dirname "$env_file")"
		touch "$env_file"
		log "Created empty .env.${network}"
	fi
	if [[ -f "$env_file" ]]; then
		set +u
		source "$env_file"
		set -u
	fi
}

save_env() {
	local network=$1
	local key=$2
	local value=$3
	local env_file="$PKG_DIR/.env.${network}"
	mkdir -p "$(dirname "$env_file")"
	if grep -q "^${key}=" "$env_file" 2>/dev/null; then
		sed -i.bak "s|^${key}=.*|${key}=${value}|" "$env_file"
		rm -f "${env_file}.bak"
	else
		echo "${key}=${value}" >> "$env_file"
	fi
	log "Saved ${key}=${value} to .env.${network}"
}

get_published_at() {
	local json=$1
	echo "$json" | jq -r '.objectChanges[] | select(.type == "published") | .packageId'
}

get_created_object() {
	local json=$1
	local struct_substr=$2
	echo "$json" | jq -r --arg type "$struct_substr" \
		'.objectChanges[] | select(.type == "created" and (.objectType | contains($type))) | .objectId' | head -1
}

is_object_exists() {
	local obj_id=$1
	sui client object "$obj_id" --json 2>/dev/null | jq -e '.data != null' > /dev/null 2>&1
}

# ─────────────────────────────────────────────────────────────────────────────

NETWORK=${1:-testnet}
OUTPUT_ENV=false
CONFIRM_IMMUTABLE=false

while [[ $# -gt 1 ]]; do
	case "$1" in
		--output-env) OUTPUT_ENV=true; shift ;;
		--confirm-immutable) CONFIRM_IMMUTABLE=true; shift ;;
		*) shift ;;
	esac
done

load_env "$NETWORK"

# Idempotency check
if [[ -n "${SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID:-}" ]]; then
	log "XPACKAGENAMEX package already published: $SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID"

	# Non-fatal immutability warning if cap still exists
	if [[ -n "${SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID:-}" ]]; then
		if is_object_exists "$SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID"; then
			log "WARNING: UpgradeCap $SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID still exists — package is NOT yet immutable"
			log "To make it immutable, run: bash $0 $NETWORK --confirm-immutable"
		else
			log "UpgradeCap confirmed consumed — package is immutable"
		fi
	fi

	if [[ "$OUTPUT_ENV" == "true" ]]; then
		echo "SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID=$SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID"
		echo "SUI_TOKEN_TEMPLATE_TREASURY_CAP_ID=$SUI_TOKEN_TEMPLATE_TREASURY_CAP_ID"
		echo "SUI_TOKEN_TEMPLATE_METADATA_CAP_ID=$SUI_TOKEN_TEMPLATE_METADATA_CAP_ID"
		echo "SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID=$SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID"
	fi
	exit 0
fi

require_env "SUI_TOKEN_TEMPLATE_ICON_URL"

log "Publishing XPACKAGENAMEX package from $PKG_DIR..."

PUBLISH_OUTPUT=$(sui client publish "$PKG_DIR" --json 2>&1)

SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID=$(get_published_at "$PUBLISH_OUTPUT")
SUI_TOKEN_TEMPLATE_TREASURY_CAP_ID=$(get_created_object "$PUBLISH_OUTPUT" "TreasuryCap")
SUI_TOKEN_TEMPLATE_METADATA_CAP_ID=$(get_created_object "$PUBLISH_OUTPUT" "MetadataCap")
PENDING_CURRENCY_ID=$(get_created_object "$PUBLISH_OUTPUT" "Currency")
SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID=$(get_created_object "$PUBLISH_OUTPUT" "UpgradeCap")

if [[ -z "$SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID" ]] || [[ -z "$SUI_TOKEN_TEMPLATE_TREASURY_CAP_ID" ]] || [[ -z "$SUI_TOKEN_TEMPLATE_METADATA_CAP_ID" ]] || [[ -z "$PENDING_CURRENCY_ID" ]] || [[ -z "$SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID" ]]; then
	log "ERROR: Failed to extract object IDs from publish output"
	log "Output: $PUBLISH_OUTPUT"
	exit 1
fi

log "Published XPACKAGENAMEX package successfully"
log "  SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID=$SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID"
log "  SUI_TOKEN_TEMPLATE_TREASURY_CAP_ID=$SUI_TOKEN_TEMPLATE_TREASURY_CAP_ID"
log "  SUI_TOKEN_TEMPLATE_METADATA_CAP_ID=$SUI_TOKEN_TEMPLATE_METADATA_CAP_ID"
log "  PENDING_CURRENCY_ID=$PENDING_CURRENCY_ID (owned by registry address 0xc, pending finalize_registration)"
log "  SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID=$SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID (pending immutability confirmation)"

# ─ OTW currencies require a mandatory second step to become a real, shared, ─
# ─ RPC-discoverable Currency<SUI_TOKEN_TEMPLATE> object. "Can be performed by anyone" ─
# ─ per the framework docs, but doing it here keeps the deploy pipeline self-contained. ─

log "Promoting Currency<SUI_TOKEN_TEMPLATE> via coin_registry::finalize_registration..."

FINALIZE_REG_OUTPUT=$(sui client call \
	--package 0x2 \
	--module coin_registry \
	--function finalize_registration \
	--type-args "${SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID}::XMODULENAMEX::SUI_TOKEN_TEMPLATE" \
	--args 0xc "$PENDING_CURRENCY_ID" \
	--gas-budget 100000000 \
	--json 2>&1)

SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID=$(echo "$FINALIZE_REG_OUTPUT" | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("Currency"))) | .objectId' | head -1)

if [[ -z "$SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID" ]]; then
	log "ERROR: Failed to extract the shared Currency<SUI_TOKEN_TEMPLATE> object ID from finalize_registration output"
	log "Output: $FINALIZE_REG_OUTPUT"
	exit 1
fi

log "  SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID=$SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID (shared Currency<SUI_TOKEN_TEMPLATE>)"

# ─ Set the network-specific icon URL while we still hold MetadataCap as sender ─
# ─ (this is what makes the icon configurable per network instead of hardcoded) ─

log "Setting icon URL via coin_registry::set_icon_url..."

sui client call \
	--package 0x2 \
	--module coin_registry \
	--function set_icon_url \
	--type-args "${SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID}::XMODULENAMEX::SUI_TOKEN_TEMPLATE" \
	--args "$SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID" "$SUI_TOKEN_TEMPLATE_METADATA_CAP_ID" "$SUI_TOKEN_TEMPLATE_ICON_URL" \
	--gas-budget 100000000 \
	--json > /dev/null

log "  Icon URL set to: $SUI_TOKEN_TEMPLATE_ICON_URL"

# ─ Irreversible step: burn UpgradeCap to make the package immutable ─

if [[ "$CONFIRM_IMMUTABLE" == "true" ]]; then
	log "Making XPACKAGENAMEX package immutable (this is IRREVERSIBLE)..."
	sui client call \
		--package 0x2 \
		--module package \
		--function make_immutable \
		--args "$SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID" \
		--gas-budget 100000000 \
		--json > /dev/null

	# Verify immutability
	OWNER=$(sui client object "$SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID" --json 2>/dev/null | jq -r '.data.owner')
	if [[ "$OWNER" != "Immutable" ]]; then
		log "ERROR: Expected package owner to be Immutable, got: $OWNER"
		exit 1
	fi

	log "✓ Package $SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID is now permanently immutable"
else
	log ""
	log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	log "UpgradeCap NOT burned — package remains upgradeable."
	log ""
	log "To burn the UpgradeCap and make the package permanently immutable,"
	log "either:"
	log "  1. Re-run with --confirm-immutable flag:"
	log "     bash $0 $NETWORK --confirm-immutable"
	log "  2. Or confirm interactively now:"
	log ""
	read -r -p "Type CONFIRM to burn the UpgradeCap and make the package immutable: " ANSWER
	if [[ "$ANSWER" == "CONFIRM" ]]; then
		log "Burning UpgradeCap..."
		sui client call \
			--package 0x2 \
			--module package \
			--function make_immutable \
			--args "$SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID" \
			--gas-budget 100000000 \
			--json > /dev/null

		# Verify immutability
		OWNER=$(sui client object "$SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID" --json 2>/dev/null | jq -r '.data.owner')
		if [[ "$OWNER" != "Immutable" ]]; then
			log "ERROR: Expected package owner to be Immutable, got: $OWNER"
			exit 1
		fi

		log "✓ Package $SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID is now permanently immutable"
	else
		log "Skipped immutability step. UpgradeCap $SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID is retained."
	fi
	log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	log ""
fi

if [[ "$OUTPUT_ENV" == "true" ]]; then
	echo "SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID=$SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID"
	echo "SUI_TOKEN_TEMPLATE_TREASURY_CAP_ID=$SUI_TOKEN_TEMPLATE_TREASURY_CAP_ID"
	echo "SUI_TOKEN_TEMPLATE_METADATA_CAP_ID=$SUI_TOKEN_TEMPLATE_METADATA_CAP_ID"
	echo "SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID=$SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID"
	echo "SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID=$SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID"
else
	save_env "$NETWORK" "SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID" "$SUI_TOKEN_TEMPLATE_TOKEN_PACKAGE_ID"
	save_env "$NETWORK" "SUI_TOKEN_TEMPLATE_TREASURY_CAP_ID" "$SUI_TOKEN_TEMPLATE_TREASURY_CAP_ID"
	save_env "$NETWORK" "SUI_TOKEN_TEMPLATE_METADATA_CAP_ID" "$SUI_TOKEN_TEMPLATE_METADATA_CAP_ID"
	save_env "$NETWORK" "SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID" "$SUI_TOKEN_TEMPLATE_METADATA_OBJECT_ID"
	save_env "$NETWORK" "SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID" "$SUI_TOKEN_TEMPLATE_UPGRADE_CAP_ID"
fi
