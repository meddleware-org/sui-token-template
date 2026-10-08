#!/usr/bin/env bash
# Behaviour tests for scripts/03_create_token.sh (no network, no Sui CLI): validation, one-pass
# substitution, and that a failing run leaves a pre-existing output directory byte-identical.
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
  unset TOKEN_LICENSE TOKEN_LICENSE_TEXT_FILE TOKEN_LICENSE_NAME TOKEN_COPYRIGHT_HOLDER FORCE_OUTPUT_DIR
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

PASS=$(grep -c '^ok$' "$RESULTS" || true); FAILED=$(grep -c '^FAIL$' "$RESULTS" || true)
echo ""
echo "$PASS passed, $FAILED failed"
[[ "$FAILED" -eq 0 && "$PASS" -gt 0 ]]
