#!/usr/bin/env bash
# Behaviour tests for the shell tooling (no network, no real Sui CLI):
#   - scripts/03_create_token.sh: validation, one-pass substitution, and that a failing run leaves a
#     pre-existing output directory byte-identical;
#   - the UpgradeCap burn reporting of the generated publish.sh and of scripts/deploy_token.sh, run against a
#     stub `sui` / `walrus` on PATH that answers "found", "not found" and "transient failure".
#   bash tests/generator.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$HERE/scripts/03_create_token.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
RESULTS="$WORK/results"; : > "$RESULTS"   # the cases run in subshells, so they report through a file

ok()   { echo ok >> "$RESULTS"; echo "ok    $1"; }
bad()  { echo FAIL >> "$RESULTS"; echo "FAIL  $1" >&2; if [[ -n "${2:-}" ]]; then echo "$2" | sed 's/^/        /' >&2; fi; }

base_env() {
  export TOKEN_PACKAGE_NAME="my_token" TOKEN_MODULE_NAME="mytoken" TOKEN_STRUCT_NAME="MYTOKEN"
  export TOKEN_SYMBOL="MTK" TOKEN_NAME="My Token" TOKEN_DESCRIPTION="A friendly token"
  export TOKEN_PACKAGE_DESCRIPTION="Official MTK token." TOKEN_PROJECT_NAME="My Project"
  export TOKEN_DECIMALS="9" TOKEN_ICON_URL="https://example.com/i.png"
  unset TOKEN_INITIAL_SUPPLY TOKEN_SUPPLY_POLICY TOKEN_METADATA_POLICY TOKEN_LICENSE TOKEN_LICENSE_TEXT_FILE TOKEN_LICENSE_NAME TOKEN_COPYRIGHT_HOLDER FORCE_OUTPUT_DIR
}

# run <dir> -> exit code in $RC, output in $OUT
run() { OUT="$(bash "$GEN" --output-dir "$1" 2>&1)"; RC=$?; }

tree_hash() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum); }

# ── a normal run ───────────────────────────────────────────────────────────────────
(
  base_env; run "$WORK/ok"
  [[ $RC -eq 0 ]] || { bad "default generation succeeds" "$OUT"; exit 1; }
  src="$WORK/ok/sources/mytoken.move"
  grep -q '^const SYMBOL: vector<u8> = b"MTK";$' "$src" && grep -q '^const NAME: vector<u8> = b"My Token";$' "$src" \
    && grep -q '^const DECIMALS: u8 = 9;$' "$src" && grep -q 'module my_token::mytoken;' "$src" \
    && ok "default generation writes the expected constants" || bad "constants" "$(grep -n '^const' "$src")"
  [[ -f "$WORK/ok/LICENSE" && -f "$WORK/ok/README.md" && -f "$WORK/ok/deployments.md" ]] && ok "writes LICENSE, README and deployments.md" || bad "files"
  echo "$OUT" | grep -q 'const SYMBOL' && ok "prints the generated constants" || bad "constants summary" "$OUT"
) || true

# ── supply and metadata policy ─────────────────────────────────────────────────────
(
  base_env; run "$WORK/pol-default"
  src="$WORK/pol-default/sources/mytoken.move"
  grep -q '^const INITIAL_SUPPLY: u64 = 0;$' "$src" && grep -q '^const FIXED_SUPPLY: bool = false;$' "$src" \
    && grep -q '^const FROZEN_METADATA: bool = false;$' "$src" \
    && ok "defaults keep the old behaviour: no initial supply, mintable, updatable metadata" || bad "policy defaults" "$(grep -n '^const' "$src")"
  grep -q '^METADATA_POLICY="updatable"$' "$WORK/pol-default/scripts/publish.sh" \
    && ok "publish.sh carries the metadata policy" || bad "publish.sh policy"

  TOKEN_INITIAL_SUPPLY=1000 TOKEN_SUPPLY_POLICY=fixed TOKEN_METADATA_POLICY=frozen run "$WORK/pol-fixed"
  src="$WORK/pol-fixed/sources/mytoken.move"
  [[ $RC -eq 0 ]] && grep -q '^const INITIAL_SUPPLY: u64 = 1000000000000;$' "$src" && grep -q '^const FIXED_SUPPLY: bool = true;$' "$src" \
    && grep -q '^const FROZEN_METADATA: bool = true;$' "$src" \
    && ok "writes the raw supply (whole tokens x 10^decimals) and both policies" || bad "fixed policy" "rc=$RC $(grep -n '^const' "$src")"
  grep -q '^METADATA_POLICY="frozen"$' "$WORK/pol-fixed/scripts/publish.sh" && ok "publish.sh knows the metadata is frozen" || bad "publish.sh frozen"
  grep -qF '| Supply policy | `fixed` |' "$WORK/pol-fixed/README.md" && ok "README states the supply policy" || bad "README policy"

  TOKEN_SUPPLY_POLICY=fixed run "$WORK/pol-empty"
  [[ $RC -ne 0 && ! -e "$WORK/pol-empty" ]] && ok "rejects a fixed supply with nothing to mint" || bad "fixed without supply" "rc=$RC $OUT"
  TOKEN_INITIAL_SUPPLY=18446744073 TOKEN_DECIMALS=9 run "$WORK/pol-max"
  [[ $RC -eq 0 ]] && ok "accepts a raw supply at the u64 range (18446744073 x 10^9)" || bad "u64 boundary ok" "$OUT"
  TOKEN_INITIAL_SUPPLY=18446744074 TOKEN_DECIMALS=9 run "$WORK/pol-over"
  [[ $RC -ne 0 && ! -e "$WORK/pol-over" ]] && ok "rejects a raw supply above u64::MAX" || bad "u64 overflow" "rc=$RC $OUT"
  TOKEN_INITIAL_SUPPLY=99999999999999999999999 run "$WORK/pol-huge"; [[ $RC -ne 0 ]] && ok "rejects an oversized supply string" || bad "huge supply"
  TOKEN_INITIAL_SUPPLY='1; const X' run "$WORK/pol-inj"; [[ $RC -ne 0 ]] && ok "rejects a non-numeric supply" || bad "supply injection"
  TOKEN_SUPPLY_POLICY=burnable run "$WORK/pol-bad1"; [[ $RC -ne 0 ]] && ok "rejects an unknown supply policy" || bad "supply policy enum"
  TOKEN_METADATA_POLICY=locked run "$WORK/pol-bad2"; [[ $RC -ne 0 ]] && ok "rejects an unknown metadata policy" || bad "metadata policy enum"
  TOKEN_INITIAL_SUPPLY=0005 run "$WORK/pol-zeros"
  grep -q '^const INITIAL_SUPPLY: u64 = 5000000000;$' "$WORK/pol-zeros/sources/mytoken.move" && ok "leading zeros do not change the amount" || bad "leading zeros"
) || true

# ── injection and special characters ───────────────────────────────────────────────
(
  base_env
  TOKEN_DESCRIPTION='x"; public fun inj(): u64 { 42 } const Z: vector<u8> = b"y' run "$WORK/inj"
  [[ $RC -ne 0 && ! -e "$WORK/inj" ]] && ok "rejects Move-code injection in a text field, creating nothing" || bad "injection" "rc=$RC $OUT"
  TOKEN_NAME='back\slash' run "$WORK/bs"; [[ $RC -ne 0 ]] && ok "rejects a backslash" || bad "backslash"
  TOKEN_DECIMALS='9; const X' run "$WORK/dec"; [[ $RC -ne 0 ]] && ok "rejects non-numeric decimals" || bad "decimals"
  TOKEN_DECIMALS='19' run "$WORK/dec2"; [[ $RC -ne 0 ]] && ok "rejects decimals above 18" || bad "decimals range"
  TOKEN_ICON_URL='http://example.com/i.png' run "$WORK/icon"; [[ $RC -ne 0 ]] && ok "rejects a non-https icon" || bad "icon scheme"
  TOKEN_SYMBOL=$'tab\there' run "$WORK/ctl"; [[ $RC -ne 0 ]] && ok "rejects control characters" || bad "control chars"
  TOKEN_MODULE_NAME='Bad-Name' TOKEN_STRUCT_NAME='BAD-NAME' run "$WORK/ident"; [[ $RC -ne 0 ]] && ok "rejects an invalid identifier" || bad "identifier"
  TOKEN_MODULE_NAME='move' TOKEN_STRUCT_NAME='MOVE' run "$WORK/kw"; [[ $RC -ne 0 ]] && ok "rejects a reserved word" || bad "reserved word"
  TOKEN_STRUCT_NAME='OTHER' run "$WORK/struct"; [[ $RC -ne 0 ]] && ok "rejects a struct name that is not the uppercased module" || bad "struct name"
) || true

(
  base_env
  TOKEN_NAME='Tom & Jerry | a/b' run "$WORK/amp"
  [[ $RC -eq 0 ]] && grep -q '^const NAME: vector<u8> = b"Tom & Jerry | a/b";$' "$WORK/amp/sources/mytoken.move" \
    && ok "& | / in a value are written literally" || bad "special characters" "rc=$RC $OUT"
  TOKEN_SYMBOL='TEMPLATE_NAME' TOKEN_NAME='My Coin' run "$WORK/coll"
  grep -q '^const SYMBOL: vector<u8> = b"TEMPLATE_NAME";$' "$WORK/coll/sources/mytoken.move" \
    && grep -q '^const NAME: vector<u8> = b"My Coin";$' "$WORK/coll/sources/mytoken.move" \
    && ok "a symbol that looks like a placeholder does not collide with the name" || bad "placeholder collision" "$OUT"
  TOKEN_SYMBOL='XNAMEX' run "$WORK/xname"
  grep -q 'XNAMEX' "$WORK/xname/README.md" && ! grep -q '(My Token) (My Token)' "$WORK/xname/README.md" \
    && ok "an X…X value is inserted once and not rescanned" || bad "rescan" "$(grep -n 'XNAMEX\|My Token' "$WORK/xname/README.md" | head -5)"
) || true

# ── a failing run leaves an existing directory byte-identical ─────────────────────────
(
  base_env
  mkdir -p "$WORK/keep/scripts"; echo "IMPORTANT" > "$WORK/keep/IMPORTANT.txt"; echo "ids" > "$WORK/keep/.env.testnet"
  before="$(tree_hash "$WORK/keep")"
  TOKEN_LICENSE=MIT TOKEN_LICENSE_TEXT_FILE=/nonexistent run "$WORK/keep"
  after="$(tree_hash "$WORK/keep")"
  [[ $RC -ne 0 && "$before" == "$after" ]] && ok "a failure (missing licence file) leaves the existing directory untouched" || bad "failure keeps directory" "rc=$RC"
  TOKEN_DESCRIPTION='bad"quote' run "$WORK/keep"
  [[ $RC -ne 0 && "$(tree_hash "$WORK/keep")" == "$before" ]] && ok "a validation failure leaves the existing directory untouched" || bad "validation keeps directory"
) || true

# ── re-running updates in place and keeps the operator's other files ──────────────────
(
  base_env
  mkdir -p "$WORK/upd"; echo "ids" > "$WORK/upd/.env.testnet"; echo "keep me" > "$WORK/upd/notes.txt"
  run "$WORK/upd"; TOKEN_ICON_URL='https://example.com/new.png' run "$WORK/upd"
  [[ $RC -eq 0 && -f "$WORK/upd/.env.testnet" && -f "$WORK/upd/notes.txt" ]] \
    && grep -q 'new.png' "$WORK/upd/sources/mytoken.move" && ok "re-running updates in place and keeps other files" || bad "in-place update" "$OUT"
) || true

# ── Move.lock: the framework pin is carried into the generated package (F7) ───────────
(
  base_env; run "$WORK/lock"
  lock="$WORK/lock/Move.lock"
  [[ $RC -eq 0 && -f "$lock" ]] && grep -q '^\[pinned.testnet.my_token\]$' "$lock" && ! grep -q 'sui_token_template' "$lock" \
    && ok "the generated package carries Move.lock with its own name as the root pin" || bad "lock carried" "rc=$RC $(cat "$lock" 2>/dev/null)"
  want="$(awk -F'rev = "' '/^\[pinned\.testnet\.Sui\]/{f=1} f && /rev = /{split($2,a,"\""); print a[1]; exit}' "$HERE/Move.lock")"
  have="$(awk -F'rev = "' '/^\[pinned\.testnet\.Sui\]/{f=1} f && /rev = /{split($2,a,"\""); print a[1]; exit}' "$lock")"
  [[ -n "$want" && "$want" == "$have" ]] && [[ "$want" == "$(jq -r .frameworkRev "$HERE/bytecode/build-info.json")" ]] \
    && ok "the carried pin is the framework revision recorded in build-info.json" || bad "lock rev" "$want vs $have"
  printf '# the instance own lock\n' > "$lock"; TOKEN_ICON_URL='https://example.com/new.png' run "$WORK/lock"
  [[ $RC -eq 0 && "$(cat "$lock")" == "# the instance own lock" ]] \
    && ok "re-running keeps the instance's own Move.lock" || bad "lock kept on re-run" "$(cat "$lock")"
) || true

# ── dangerous output directories ──────────────────────────────────────────────────────
(
  base_env
  ( cd "$WORK" && mkdir -p cwd && cd cwd && OUT="$(bash "$GEN" --output-dir . 2>&1)"; [[ $? -ne 0 ]] && echo "$OUT" | grep -q "refusing" ) \
    && ok "refuses the current directory" || bad "refuse ."
  HOME="$WORK/home" ; mkdir -p "$HOME"; export HOME
  run "$HOME"; [[ $RC -ne 0 ]] && ok "refuses \$HOME" || bad "refuse HOME"
  mkdir -p "$WORK/repo/.git"; run "$WORK/repo"; [[ $RC -ne 0 ]] && ok "refuses a git work-tree root" || bad "refuse git root"
  FORCE_OUTPUT_DIR=1 run "$WORK/repo"; [[ $RC -eq 0 ]] && ok "FORCE_OUTPUT_DIR=1 allows it" || bad "force" "$OUT"
) || true

# ── licences ──────────────────────────────────────────────────────────────────────────
(
  base_env
  TOKEN_LICENSE=NONE run "$WORK/prop"
  [[ $RC -eq 0 && ! -e "$WORK/prop/LICENSE" ]] && grep -q 'proprietary' "$WORK/prop/README.md" && ok "NONE writes no LICENSE and says so in the README" || bad "proprietary" "$OUT"
  printf 'MIT text\n' > "$WORK/mit.txt"; TOKEN_LICENSE=MIT TOKEN_LICENSE_TEXT_FILE="$WORK/mit.txt" TOKEN_LICENSE_NAME='MIT & friends' run "$WORK/mit"
  [[ $RC -eq 0 ]] && grep -q 'MIT & friends — see the LICENSE file.' "$WORK/mit/README.md" && ok "a licence name with & is written literally" || bad "licence name" "$OUT"
  TOKEN_LICENSE='Apache 2' run "$WORK/lic"; [[ $RC -ne 0 ]] && ok "rejects an invalid licence identifier" || bad "licence id"
) || true

# ── burn reporting: the stub CLI ───────────────────────────────────────────────────────
# A stand-in for `sui` (and `walrus`) on PATH. It answers the calls the scripts make and keeps one bit of state:
# whether make_immutable was called. The lookup of the UpgradeCap then follows STUB_AFTER_BURN, or
# STUB_CAP_LOOKUP when that is set (a re-run of publish.sh starts with the cap already burned or unreachable):
#   found      the object (exit 0)                 gone       the real CLI's not-found error (exit 1)
#   transient  a connection error (exit 1)         gone-other a not-found error for ANOTHER object (exit 1)
#   empty      exit 0 with no objectId in the output
STUB_BIN="$WORK/bin"; mkdir -p "$STUB_BIN"
hex64() { head -c 64 /dev/zero | tr '\0' "$1"; }   # 64 copies of one hex digit
STUB_PKG="0x$(hex64 a)"; STUB_CAP="0x$(hex64 c)"; STUB_TREASURY="0x$(hex64 1)"
cat > "$STUB_BIN/sui" <<'STUB'
#!/usr/bin/env bash
state="${STUB_STATE:?}"; echo "$*" >> "$state/calls"
case "$1 ${2:-}" in
  "--version "*) echo "sui 1.81.0-stub"; exit 0 ;;
  "client active-env") echo "${STUB_ENV:-testnet}"; exit 0 ;;
  "client active-address") echo "$STUB_TREASURY"; exit 0 ;;
  "client chain-identifier") echo "4c78adac"; exit 0 ;;
  "client balance") echo '[]'; exit 0 ;;
  "move test"|"move build") exit 0 ;;
  "client transfer") exit 0 ;;
esac
fn=""; prev=""; for a in "$@"; do [[ "$prev" == "--function" ]] && fn="$a"; prev="$a"; done
case "$1 ${2:-}" in
  "client publish")
    ty="${STUB_PKG}::${STUB_MODULE}::${STUB_STRUCT}"
    cat <<JSON
{ "objectChanges": [
  { "type": "published", "packageId": "$STUB_PKG" },
  { "type": "created", "objectId": "0x$(printf 'd%.0s' $(seq 64))", "objectType": "0x2::coin::TreasuryCap<$ty>" },
  { "type": "created", "objectId": "0x$(printf 'e%.0s' $(seq 64))", "objectType": "0x2::coin_registry::MetadataCap<$ty>" },
  { "type": "created", "objectId": "0x$(printf 'f%.0s' $(seq 64))", "objectType": "0x2::coin_registry::Currency<$ty>" },
  { "type": "created", "objectId": "$STUB_CAP", "objectType": "0x2::package::UpgradeCap" } ] }
JSON
    exit 0 ;;
  "client call")
    case "$fn" in
      finalize_registration)
        printf '{ "objectChanges": [ { "type": "created", "objectId": "0x%s", "objectType": "0x2::coin_registry::Currency<%s::%s::%s>" } ] }\n' \
          "$(printf '9%.0s' $(seq 64))" "$STUB_PKG" "$STUB_MODULE" "$STUB_STRUCT"; exit 0 ;;
      make_immutable) touch "$state/burned"; echo '{ "objectChanges": [] }'; exit 0 ;;
      *) echo '{ "objectChanges": [] }'; exit 0 ;;
    esac ;;
  "client object")
    if [[ "$3" != "$STUB_CAP" ]]; then   # any other object: owned by the treasury (the transfer re-read)
      printf '{ "objectId": "%s", "owner": { "AddressOwner": "%s" } }\n' "$3" "$STUB_TREASURY"; exit 0
    fi
    mode="${STUB_CAP_LOOKUP:-}"
    if [[ -z "$mode" ]]; then if [[ -e "$state/burned" ]]; then mode="${STUB_AFTER_BURN:-gone}"; else mode=found; fi; fi
    case "$mode" in
      found) printf '{ "objectId": "%s", "version": 1 }\n' "$STUB_CAP"; exit 0 ;;
      gone) echo "code: 'Some requested entity was not found', message: \"Object $STUB_CAP not found\"" >&2; exit 1 ;;
      gone-other) echo "code: 'Some requested entity was not found', message: \"Object 0x$(printf '7%.0s' $(seq 64)) not found\"" >&2; exit 1 ;;
      transient) echo "code: 'The service is currently unavailable', message: \"error trying to connect: tcp connect error\"" >&2; exit 1 ;;
      empty) echo '{}'; exit 0 ;;
    esac ;;
esac
echo "stub sui: unhandled: $*" >&2; exit 99
STUB
cat > "$STUB_BIN/walrus" <<'STUB'
#!/usr/bin/env bash
echo '{"newlyCreated":{"blobObject":{"blobId":"BLOBID1"},"object":"0xb10b"}}'
STUB
chmod +x "$STUB_BIN/sui" "$STUB_BIN/walrus"

# stub_env <case> — a fresh stub state directory and the variables the stub reads
stub_env() {
  export STUB_STATE="$WORK/state-$1"; rm -rf "$STUB_STATE"; mkdir -p "$STUB_STATE"
  export STUB_PKG STUB_CAP STUB_TREASURY STUB_MODULE=mytoken STUB_STRUCT=MYTOKEN
  unset STUB_CAP_LOOKUP STUB_AFTER_BURN STUB_ENV
  export PATH="$STUB_BIN:$PATH"
}

# ── the not-found rule (object_state) ───────────────────────────────────────────────────
# Both scripts carry the same block; extract it from each and run it against the stub.
extract_state_fn() { sed -n '/^# BEGIN object_state/,/^# END object_state/p' "$1"; }
norm() { sed 's/^[[:space:]]*//' | grep -v '^# BEGIN object_state'; }   # the BEGIN lines name the other file
if [[ "$(extract_state_fn "$HERE/scripts/deploy_token.sh" | norm)" == "$(extract_state_fn "$HERE/templates/publish.sh" | norm)" \
      && -n "$(extract_state_fn "$HERE/templates/publish.sh")" ]]; then
  ok "deploy_token.sh and publish.sh carry the same object_state block"
else
  bad "object_state blocks differ or are missing"
fi
(
  stub_env state; command -v jq >/dev/null || { bad "jq is needed for the object_state cases"; exit 0; }
  for src in "$HERE/scripts/deploy_token.sh" "$HERE/templates/publish.sh"; do
    name="$(basename "$src")"
    # shellcheck disable=SC1090
    source <(extract_state_fn "$src")
    check() { # <mode> <expected> <label>
      export STUB_CAP_LOOKUP="$1"; got="$(object_state "$STUB_CAP" 2>/dev/null)"
      [[ "$got" == "$2" ]] && ok "$name: $3 -> $2" || bad "$name: $3" "expected $2, got '$got'"
    }
    check found found "the object exists"
    check gone gone "the CLI reports THIS object as not found"
    check transient unknown "a connection error is not a consumed object"
    check gone-other unknown "a not-found for another object is not a consumed object"
    check empty unknown "exit 0 without an objectId is not a consumed object"
    STUB_CAP_LOOKUP=transient object_state "$STUB_CAP" 2>&1 >/dev/null | grep -q 'tcp connect error' \
      && ok "$name: the CLI output of an unknown lookup reaches stderr" || bad "$name: unknown prints the CLI output"
  done
) || true

# ── generated publish.sh: the immutability claim ────────────────────────────────────────
# gen_pkg <dir> — a generated package with a recorded publish (an .env file as a first run would leave it)
gen_pkg() {
  base_env; bash "$GEN" --output-dir "$1" >/dev/null 2>&1
  cat > "$1/.env.testnet" <<ENV
MYTOKEN_TOKEN_PACKAGE_ID=$STUB_PKG
MYTOKEN_UPGRADE_CAP_ID=$STUB_CAP
MYTOKEN_PENDING_CURRENCY_ID=0x$(hex64 9)
MYTOKEN_METADATA_OBJECT_ID=0x$(hex64 9)
MYTOKEN_ICON_URL=https://example.com/i.png
MYTOKEN_ICON_URL_SET=https://example.com/i.png
ENV
}
pub() { # <dir> <args…> — run the generated publish.sh, answering the interactive prompt with PUB_ANSWER; OUT/RC
  local d=$1; shift; OUT="$(printf '%s\n' "${PUB_ANSWER:-no}" | bash "$d/scripts/publish.sh" testnet "$@" 2>&1)"; RC=$?
}
(
  stub_env pub1; gen_pkg "$WORK/p1"
  STUB_CAP_LOOKUP=gone pub "$WORK/p1"
  [[ $RC -eq 0 ]] && echo "$OUT" | grep -q 'already consumed — package is immutable' \
    && ok "publish.sh: a definite not-found on re-run reports the package immutable" || bad "publish.sh re-run, consumed" "rc=$RC $OUT"

  STUB_CAP_LOOKUP=transient pub "$WORK/p1"
  [[ $RC -ne 0 ]] && ! echo "$OUT" | grep -qi 'immutable —\|permanently immutable\|already consumed' && echo "$OUT" | grep -q 'cannot tell whether UpgradeCap' \
    && ok "publish.sh: a transient lookup failure on re-run stops without an immutability claim" || bad "publish.sh re-run, transient" "rc=$RC $OUT"

  STUB_CAP_LOOKUP=gone-other pub "$WORK/p1"
  [[ $RC -ne 0 ]] && ! echo "$OUT" | grep -q 'already consumed' \
    && ok "publish.sh: a not-found for another object is not read as consumed" || bad "publish.sh re-run, other object" "rc=$RC $OUT"
) || true
(
  stub_env pub2; gen_pkg "$WORK/p2"
  pub "$WORK/p2" --confirm-immutable
  [[ $RC -eq 0 ]] && echo "$OUT" | grep -q 'permanently immutable (UpgradeCap consumed)' && grep -q 'make_immutable' "$STUB_STATE/calls" \
    && ok "publish.sh: --confirm-immutable burns and verifies a definite not-found" || bad "publish.sh burn" "rc=$RC $OUT"

  stub_env pub3; gen_pkg "$WORK/p3"; STUB_AFTER_BURN=transient pub "$WORK/p3" --confirm-immutable
  [[ $RC -ne 0 ]] && grep -q 'make_immutable' "$STUB_STATE/calls" && ! echo "$OUT" | grep -q 'permanently immutable' \
    && ok "publish.sh: the burn is not reported when the check cannot read the UpgradeCap" || bad "publish.sh burn, transient" "rc=$RC $OUT"

  stub_env pub4; gen_pkg "$WORK/p4"; STUB_AFTER_BURN=found pub "$WORK/p4" --confirm-immutable
  [[ $RC -ne 0 ]] && echo "$OUT" | grep -q 'still exists after make_immutable' \
    && ok "publish.sh: an UpgradeCap that survives the burn is an error" || bad "publish.sh burn, survives" "rc=$RC $OUT"

  stub_env pub5; gen_pkg "$WORK/p5"; pub "$WORK/p5"   # no flag: the interactive prompt is answered "no"
  [[ $RC -eq 0 ]] && echo "$OUT" | grep -q 'NOT burned' && echo "$OUT" | grep -q 'Skipped immutability step' && ! grep -q 'make_immutable' "$STUB_STATE/calls" \
    && ok "publish.sh: declining keeps the UpgradeCap and says so" || bad "publish.sh decline" "rc=$RC $OUT"

  stub_env pub6; gen_pkg "$WORK/p6"; sed -i '/UPGRADE_CAP_ID/d' "$WORK/p6/.env.testnet"; pub "$WORK/p6"
  [[ $RC -ne 0 ]] && ! echo "$OUT" | grep -q 'already consumed' \
    && ok "publish.sh: no recorded UpgradeCap ID is not read as consumed" || bad "publish.sh no cap id" "rc=$RC $OUT"
) || true

# ── deploy_token.sh: the summary and the burn check ─────────────────────────────────────
# deploy <case> <answers> [after-burn mode] — the whole pipeline against the stub: Walrus upload (Enter), CONFIRM, <answers>
deploy() {
  stub_env "dep-$1"; [[ -z "${3:-}" ]] || export STUB_AFTER_BURN="$3"
  base_env; export TOKEN_IMAGE_PATH="$WORK/icon.png" OUTPUT_DIR="$WORK/dep-$1" NETWORK=testnet TREASURY_ADDRESS="$STUB_TREASURY"
  printf 'png' > "$TOKEN_IMAGE_PATH"
  OUT="$(printf '\nCONFIRM\n%b' "$2" | bash "$HERE/scripts/deploy_token.sh" 2>&1)"; RC=$?
}
(
  deploy decline 'no\nTRANSFER\n'
  [[ $RC -eq 0 ]] && echo "$OUT" | grep -q "UpgradeCap kept" \
    && echo "$OUT" | grep -q "UpgradeCap ID:      $STUB_CAP (NOT burned — kept by the deployer; the package is still upgradeable)" \
    && ! echo "$OUT" | grep -q 'burned — package is immutable' && ! echo "$OUT" | grep -q 'Package is now immutable' \
    && echo "$OUT" | grep -q 'WARNING: the UpgradeCap was NOT burned' \
    && ! grep -q 'TOKEN_UPGRADE_CAP_BURNED' "$WORK/dep-decline/.env.testnet" && ! grep -q 'make_immutable' "$STUB_STATE/calls" \
    && ok "deploy_token.sh: declining BURN leaves a summary that says the UpgradeCap is kept" || bad "deploy decline" "rc=$RC $OUT"
) || true
(
  deploy burn 'BURN\nTRANSFER\n'
  [[ $RC -eq 0 ]] && echo "$OUT" | grep -q "UpgradeCap ID:      $STUB_CAP (burned — package is immutable)" \
    && grep -q '^TOKEN_UPGRADE_CAP_BURNED=yes$' "$WORK/dep-burn/.env.testnet" && ! echo "$OUT" | grep -q 'WARNING: the UpgradeCap was NOT burned' \
    && ok "deploy_token.sh: a verified burn is recorded and summarised as immutable" || bad "deploy burn" "rc=$RC $OUT"
) || true
(
  deploy transient 'BURN\nTRANSFER\n' transient
  [[ $RC -ne 0 ]] && grep -q 'make_immutable' "$STUB_STATE/calls" && echo "$OUT" | grep -q 'Immutability is NOT confirmed' \
    && ! echo "$OUT" | grep -q 'verified gone' && ! grep -q 'TOKEN_UPGRADE_CAP_BURNED' "$WORK/dep-transient/.env.testnet" \
    && ok "deploy_token.sh: a failed lookup after the burn is not recorded as burned" || bad "deploy burn, transient" "rc=$RC $OUT"
) || true
(
  deploy survives 'BURN\nTRANSFER\n' found
  [[ $RC -ne 0 ]] && echo "$OUT" | grep -q 'still exists. The package is NOT immutable' && ! grep -q 'TOKEN_UPGRADE_CAP_BURNED' "$WORK/dep-survives/.env.testnet" \
    && ok "deploy_token.sh: an UpgradeCap that survives the burn is an error" || bad "deploy burn, survives" "rc=$RC $OUT"
) || true
(
  deploy other 'BURN\nTRANSFER\n' gone-other
  [[ $RC -ne 0 ]] && ! grep -q 'TOKEN_UPGRADE_CAP_BURNED' "$WORK/dep-other/.env.testnet" \
    && ok "deploy_token.sh: a not-found for another object is not read as consumed" || bad "deploy burn, other object" "rc=$RC $OUT"
) || true

PASS=$(grep -c '^ok$' "$RESULTS" || true); FAILED=$(grep -c '^FAIL$' "$RESULTS" || true)
echo ""
echo "$PASS passed, $FAILED failed"
[[ "$FAILED" -eq 0 && "$PASS" -gt 0 ]]
