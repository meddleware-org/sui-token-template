#!/usr/bin/env bash
# Build the template module and ship its bytecode (workspace decision D23), or check that the shipped
# bytecode matches a fresh build byte for byte.
#
#   bash scripts/build-bytecode.sh           # rebuild bytecode/ from sources/
#   bash scripts/build-bytecode.sh --check   # fail if bytecode/ differs from a fresh build (CI)
#
# Output:
#   bytecode/sui_token_template.mv   the compiled module (`sui move build`, never `sui move test`,
#                                    whose instrumented bytecode is not publishable)
#   bytecode/build-info.json         toolchainVersion, buildEnv, frameworkRev, sourceSha256,
#                                    moduleSha256 — so consumers can check the artefact without the CLI
#
# The build is reproducible because Move.lock (committed) pins the framework revision. To move to a
# newer framework: delete Move.lock, rebuild, review, commit both.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/bytecode"
CHECK=""
case "${1:-}" in
  "") ;;
  --check) CHECK=1 ;;
  *) echo "Usage: $0 [--check]" >&2; exit 2 ;;
esac

command -v sui >/dev/null || { echo "ERROR: the sui CLI is required" >&2; exit 1; }
cd "$ROOT"
rm -rf build
sui move build --build-env testnet >/dev/null
MV="build/sui_token_template/bytecode_modules/sui_token_template.mv"
[ "$(head -c 4 "$MV" | od -An -tx1 | tr -d ' \n')" = "a11ceb0b" ] \
  || { echo "ERROR: $MV is not publishable Move bytecode (magic)" >&2; exit 1; }

sha() { sha256sum "$1" | cut -d' ' -f1; }
FRAMEWORK_REV="$(awk -F'rev = "' '/^\[pinned\.testnet\.Sui\]/{f=1} f && /rev = /{split($2,a,"\""); print a[1]; exit}' Move.lock)"
INFO="$(printf '{\n  "toolchainVersion": "%s",\n  "buildEnv": "testnet",\n  "frameworkRev": "%s",\n  "sourceSha256": "%s",\n  "moduleSha256": "%s"\n}\n' \
  "$(sui --version | awk '{print $2}' | cut -d- -f1)" "$FRAMEWORK_REV" "$(sha sources/sui_token_template.move)" "$(sha "$MV")")"

if [ -n "$CHECK" ]; then
  cmp -s "$MV" "$OUT/sui_token_template.mv" \
    || { echo "ERROR: bytecode/sui_token_template.mv differs from a fresh build — run scripts/build-bytecode.sh and commit" >&2; exit 1; }
  [ "$INFO" = "$(cat "$OUT/build-info.json")" ] \
    || { echo "ERROR: bytecode/build-info.json is stale:" >&2; diff <(echo "$INFO") "$OUT/build-info.json" >&2 || true; exit 1; }
  echo "bytecode/ matches a fresh build ($(sha "$MV"))"
else
  mkdir -p "$OUT"
  cp "$MV" "$OUT/sui_token_template.mv"
  printf '%s\n' "$INFO" > "$OUT/build-info.json"
  echo "Wrote bytecode/ ($(sha "$MV"))"
fi
