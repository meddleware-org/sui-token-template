#!/bin/bash
set -euo pipefail

# Generator: creates a concrete coin package instance from the template.
#
# This script copies the template sources, substitutes all token-specific values,
# and produces a valid Move package ready for testing or deployment.
#
# Usage:
#   TOKEN_PACKAGE_NAME="my_token" \
#   TOKEN_MODULE_NAME="mytoken" \
#   TOKEN_STRUCT_NAME="MYTOKEN" \
#   TOKEN_SYMBOL="myTOKEN" \
#   TOKEN_NAME="My Token" \
#   TOKEN_DESCRIPTION="A custom token on the Sui blockchain" \
#   TOKEN_PACKAGE_DESCRIPTION="Official MYTOKEN share token." \
#   TOKEN_PROJECT_NAME="My Project" \
#   TOKEN_DECIMALS="9" \
#   TOKEN_ICON_URL="https://blob-url" \
#   bash scripts/03_create_token.sh --output-dir my_token
#
# Every value is validated with the same rules as @meddleware/sui-token-client's assertTokenConfig before
# anything is written (identifiers, safe text without quotes or backslashes, per-field limits, decimals
# 0-18, https:// or ipfs:// icons). Values are substituted by exact token or line in a single pass, so
# characters such as & | \ / cannot change what is written and inserted text is never rescanned.
#
# The package is generated in a temporary directory and installed into --output-dir only after every
# check passed; the script removes only that temporary directory. An existing --output-dir is updated in
# place (generated files overwritten, nothing else touched) and is left byte-identical by a failing run.
# It refuses "/", $HOME, "." and a git work-tree root unless FORCE_OUTPUT_DIR=1.
#
# Optional license controls (default: 0BSD):
#   TOKEN_LICENSE           SPDX identifier (e.g. "0BSD", "MIT", "Apache-2.0", "CC0-1.0")
#                           or "NONE" for a proprietary / all-rights-reserved package.
#   TOKEN_LICENSE_TEXT_FILE Path to the full license text to embed as the package
#                           LICENSE file. If omitted for a non-0BSD license, the text
#                           is fetched from the SPDX license-list-data archive.
#   TOKEN_LICENSE_NAME      Human-readable name shown in the generated README
#                           License section (defaults to the SPDX identifier).

# Validate required env vars using bash parameter expansion.
# This distinguishes unset variables (error) from empty strings (permitted).
# For TOKEN_ICON_URL, an explicitly set empty string "" is valid.
: "${TOKEN_PACKAGE_NAME?TOKEN_PACKAGE_NAME must be set}"
: "${TOKEN_MODULE_NAME?TOKEN_MODULE_NAME must be set}"
: "${TOKEN_STRUCT_NAME?TOKEN_STRUCT_NAME must be set}"
: "${TOKEN_SYMBOL?TOKEN_SYMBOL must be set}"
: "${TOKEN_NAME?TOKEN_NAME must be set}"
: "${TOKEN_DESCRIPTION?TOKEN_DESCRIPTION must be set}"
: "${TOKEN_PACKAGE_DESCRIPTION?TOKEN_PACKAGE_DESCRIPTION must be set}"
: "${TOKEN_PROJECT_NAME?TOKEN_PROJECT_NAME must be set}"
: "${TOKEN_DECIMALS?TOKEN_DECIMALS must be set}"
: "${TOKEN_ICON_URL?TOKEN_ICON_URL must be set}"

fail() { echo "ERROR: $*" >&2; exit 1; }

# Parse --output-dir flag
OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            OUTPUT_DIR="${2:-}"
            shift 2 || fail "--output-dir needs a value"
            ;;
        *)
            fail "Unknown option $1"
            ;;
    esac
done

[[ -n "$OUTPUT_DIR" ]] || fail "--output-dir flag is required"

# ─────────────────────────────────────────────────────────────────────────────
# Output directory safety: never operate on a place that is not an instance directory.
# ─────────────────────────────────────────────────────────────────────────────
OUT_ABS="$(realpath -m -- "$OUTPUT_DIR")"
if [[ "${FORCE_OUTPUT_DIR:-}" != "1" ]]; then
    if [[ "$OUT_ABS" == "/" || "$OUT_ABS" == "$(realpath -m -- "${HOME:-/nonexistent}")" || "$OUT_ABS" == "$(pwd -P)" ]]; then
        fail "refusing --output-dir '$OUTPUT_DIR' ($OUT_ABS): it is / , \$HOME or the current directory. Use a subdirectory, or FORCE_OUTPUT_DIR=1."
    fi
    if [[ -e "$OUT_ABS/.git" ]]; then
        fail "refusing --output-dir '$OUTPUT_DIR': it is a git work-tree root. Use a subdirectory, or FORCE_OUTPUT_DIR=1."
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Input validation (mirrors @meddleware/sui-token-client rules.ts: assertTokenConfig).
# ─────────────────────────────────────────────────────────────────────────────
MOVE_RESERVED=" abort acquires as break const continue copy else entry enum false for friend fun has if in invariant let loop macro match module move mut native package phantom public return script spec struct true type use while key store drop "

check_identifier() { # <label> <value>
    local label="$1" v="$2"
    [[ ${#v} -ge 1 && ${#v} -le 64 ]] || fail "Invalid $label: 1-64 characters."
    [[ "$v" =~ ^[a-z][a-z0-9_]*$ ]] || fail "Invalid $label '$v': lowercase letters, digits and underscores, starting with a letter."
    [[ "$MOVE_RESERVED" != *" $v "* ]] || fail "Invalid $label '$v': a Move reserved word."
}

# Printable ASCII only, without the double quote and backslash (safe inside a Move b"..." literal).
check_text() { # <label> <value> <max> <required 0|1>
    local label="$1" v="$2" max="$3" required="$4"
    if [[ "$required" == "1" && -z "${v//[[:space:]]/}" ]]; then fail "Invalid $label: required."; fi
    [[ ${#v} -le $max ]] || fail "Invalid $label: $max characters maximum."
    [[ "$v" != *\"*  && "$v" != *\\* ]] || fail "Invalid $label: contains quotes or backslashes."
    ( LC_ALL=C; [[ "$v" =~ ^[[:print:]]*$ ]] ) || fail "Invalid $label: contains control or non-ASCII characters."
}

check_identifier "package name" "$TOKEN_PACKAGE_NAME"
check_identifier "module name" "$TOKEN_MODULE_NAME"
EXPECTED_STRUCT="$(printf '%s' "$TOKEN_MODULE_NAME" | tr '[:lower:]' '[:upper:]')"
[[ "$TOKEN_STRUCT_NAME" == "$EXPECTED_STRUCT" ]] || fail "Invalid struct name '$TOKEN_STRUCT_NAME': must be the module name uppercased ($EXPECTED_STRUCT)."
check_text "symbol" "$TOKEN_SYMBOL" 32 1
check_text "name" "$TOKEN_NAME" 64 1
check_text "description" "$TOKEN_DESCRIPTION" 256 0
check_text "icon URL" "$TOKEN_ICON_URL" 512 0
check_text "package description" "$TOKEN_PACKAGE_DESCRIPTION" 256 0
check_text "project name" "$TOKEN_PROJECT_NAME" 64 0
if [[ -n "$TOKEN_ICON_URL" ]]; then
    icon_lc="$(printf '%s' "$TOKEN_ICON_URL" | tr '[:upper:]' '[:lower:]')"
    [[ "$icon_lc" == https://* || "$icon_lc" == ipfs://* ]] || fail "Invalid icon URL: only https:// or ipfs:// URLs are allowed."
fi
[[ "$TOKEN_DECIMALS" =~ ^[0-9]+$ && "$TOKEN_DECIMALS" -ge 0 && "$TOKEN_DECIMALS" -le 18 && ${#TOKEN_DECIMALS} -le 2 ]] \
    || fail "Invalid decimals '$TOKEN_DECIMALS': a whole number between 0 and 18."
TOKEN_DECIMALS=$((10#$TOKEN_DECIMALS))

# Locate template directory (script's parent directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/.."
TEMPLATE_MOVE="$TEMPLATE_DIR/sources/sui_token_template.move"
TEMPLATE_TOML="$TEMPLATE_DIR/Move.toml"

[[ -f "$TEMPLATE_MOVE" ]] || fail "Template source not found at $TEMPLATE_MOVE"
[[ -f "$TEMPLATE_TOML" ]] || fail "Template Move.toml not found at $TEMPLATE_TOML"

# ─────────────────────────────────────────────────────────────────────────────
# License resolution (see the usage block above for the env vars involved).
# The default is 0BSD, which uses the bundled templates/LICENSE-0BSD text (year + copyright holder
# substituted) and therefore keeps the default generation path fully offline.
# ─────────────────────────────────────────────────────────────────────────────
TOKEN_LICENSE="${TOKEN_LICENSE:-0BSD}"
TOKEN_COPYRIGHT_HOLDER="${TOKEN_COPYRIGHT_HOLDER:-${TOKEN_PROJECT_NAME:-$TOKEN_NAME}}"
TOKEN_LICENSE_TEXT_FILE="${TOKEN_LICENSE_TEXT_FILE:-}"
TOKEN_LICENSE_NAME="${TOKEN_LICENSE_NAME:-$TOKEN_LICENSE}"
[[ "$TOKEN_LICENSE" =~ ^[A-Za-z0-9.+-]+$ ]] || fail "Invalid license identifier '$TOKEN_LICENSE'."
check_text "license name" "$TOKEN_LICENSE_NAME" 64 0
check_text "copyright holder" "$TOKEN_COPYRIGHT_HOLDER" 64 0

_license_upper="$(printf '%s' "$TOKEN_LICENSE" | tr '[:lower:]' '[:upper:]')"
if [[ "$_license_upper" == "NONE" || "$_license_upper" == "UNLICENSED" || "$_license_upper" == "NOASSERTION" ]]; then
    LICENSE_PROPRIETARY=1
    SPDX_ID="UNLICENSED"
else
    LICENSE_PROPRIETARY=0
    SPDX_ID="$TOKEN_LICENSE"
fi

# All template files must exist before anything is generated.
TEMPLATE_PUBLISH="$TEMPLATE_DIR/templates/publish.sh"
TEMPLATE_LICENSE="$TEMPLATE_DIR/templates/LICENSE-0BSD"
TEMPLATE_GITIGNORE="$TEMPLATE_DIR/templates/gitignore"
TEMPLATE_README="$TEMPLATE_DIR/templates/README.md"
TEMPLATE_DEPLOYMENTS="$TEMPLATE_DIR/templates/deployments.md"
TEMPLATE_CLAUDE="$TEMPLATE_DIR/templates/CLAUDE.md"
TEMPLATE_AGENTS="$TEMPLATE_DIR/templates/AGENTS.md"
for f in "$TEMPLATE_PUBLISH" "$TEMPLATE_LICENSE" "$TEMPLATE_GITIGNORE" "$TEMPLATE_README" "$TEMPLATE_DEPLOYMENTS" "$TEMPLATE_CLAUDE" "$TEMPLATE_AGENTS"; do
    [[ -f "$f" ]] || fail "Template file not found at $f"
done

# ─────────────────────────────────────────────────────────────────────────────
# Generate into a staging directory that this run created (and is the only thing it ever removes).
# ─────────────────────────────────────────────────────────────────────────────
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/create-token.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
mkdir -p "$STAGE/sources" "$STAGE/scripts"

echo "=== Generating coin package from template ==="
echo "  Package: $TOKEN_PACKAGE_NAME"
echo "  Module: $TOKEN_MODULE_NAME"
echo "  Struct: $TOKEN_STRUCT_NAME"
echo "  Output: $OUTPUT_DIR"
echo ""

# subst_tokens <file> NAME=VALUE ... — replace every X<NAME>X token in ONE pass. The inserted value is
# taken literally (no &, | or \ handling) and is never rescanned, so a value that looks like another token
# cannot be substituted twice. Tokens without a mapping are left for the leftover check below.
subst_tokens() {
    local file="$1"; shift
    local tmp pairs="" kv
    tmp="$(mktemp "$STAGE/.subst.XXXXXX")"
    for kv in "$@"; do pairs+="${kv}"$'\001'; done
    SUBST_PAIRS="$pairs" awk '
        BEGIN {
            n = split(ENVIRON["SUBST_PAIRS"], parts, "\001")
            for (i = 1; i <= n; i++) {
                if (parts[i] == "") continue
                eq = index(parts[i], "=")
                map[substr(parts[i], 1, eq - 1)] = substr(parts[i], eq + 1)
            }
        }
        {
            line = $0; out = ""
            while (match(line, /X[A-Z]+X/)) {
                name = substr(line, RSTART + 1, RLENGTH - 2)
                out = out substr(line, 1, RSTART - 1)
                if (name in map) out = out map[name]
                else { out = out substr(line, RSTART, RLENGTH); unmapped[name] = 1 }
                line = substr(line, RSTART + RLENGTH)
            }
            print out line
        }
        END { for (t in unmapped) { printf "unreplaced placeholder X%sX\n", t > "/dev/stderr"; bad = 1 }; exit bad ? 4 : 0 }
    ' "$file" > "$tmp" || { rm -f "$tmp"; fail "a template placeholder in $(basename "$file") has no value (substitution incomplete)."; }
    mv "$tmp" "$file"
}

# set_line <file> <exact old line> <new line> — replace exactly one whole line, or fail (template drift).
set_line() {
    local file="$1" old="$2" new="$3" tmp
    tmp="$(mktemp "$STAGE/.line.XXXXXX")"
    OLD_LINE="$old" NEW_LINE="$new" awk '
        BEGIN { old = ENVIRON["OLD_LINE"]; new = ENVIRON["NEW_LINE"]; hits = 0 }
        $0 == old { print new; hits++; next }
        { print }
        END { exit hits == 1 ? 0 : 3 }
    ' "$file" > "$tmp" || { rm -f "$tmp"; fail "template drift: expected exactly one line '$old' in $(basename "$file")"; }
    mv "$tmp" "$file"
}

# Copy Move.toml and substitute package name (an identifier, validated above) and licence id
sed "s/sui_token_template/$TOKEN_PACKAGE_NAME/g" "$TEMPLATE_TOML" > "$STAGE/Move.toml"
sed -i "s|^license = .*|license = \"$SPDX_ID\"|" "$STAGE/Move.toml"

# publish.sh (identifiers only)
cp "$TEMPLATE_PUBLISH" "$STAGE/scripts/publish.sh"
chmod +x "$STAGE/scripts/publish.sh"
sed -i "s/SUI_TOKEN_TEMPLATE/$TOKEN_STRUCT_NAME/g" "$STAGE/scripts/publish.sh"
sed -i "s|XMODULENAMEX|$TOKEN_MODULE_NAME|g" "$STAGE/scripts/publish.sh"
sed -i "s|XPACKAGENAMEX|$TOKEN_PACKAGE_NAME|g" "$STAGE/scripts/publish.sh"

# Copy .gitignore verbatim
cp "$TEMPLATE_GITIGNORE" "$STAGE/.gitignore"

# Resolve and write the LICENSE file according to the selected license.
if [[ "$LICENSE_PROPRIETARY" == "1" ]]; then
    : # Proprietary / all-rights-reserved: no LICENSE file is written.
elif [[ -n "$TOKEN_LICENSE_TEXT_FILE" ]]; then
    [[ -f "$TOKEN_LICENSE_TEXT_FILE" ]] || fail "TOKEN_LICENSE_TEXT_FILE not found at $TOKEN_LICENSE_TEXT_FILE"
    cp "$TOKEN_LICENSE_TEXT_FILE" "$STAGE/LICENSE"
elif [[ "$SPDX_ID" == "0BSD" ]]; then
    # Offline default: bundled 0BSD text with the year and copyright holder filled in.
    cp "$TEMPLATE_LICENSE" "$STAGE/LICENSE"
    subst_tokens "$STAGE/LICENSE" "YEAR=$(date -u +%Y)" "COPYRIGHT=${TOKEN_COPYRIGHT_HOLDER}"
else
    # Fetch the canonical text from the SPDX license-list-data archive.
    LICENSE_URL="https://raw.githubusercontent.com/spdx/license-list-data/main/text/${SPDX_ID}.txt"
    if ! curl -fsSL "$LICENSE_URL" -o "$STAGE/LICENSE"; then
        echo "       Pass TOKEN_LICENSE_TEXT_FILE=<path> to supply the text directly." >&2
        fail "could not fetch license text for '$SPDX_ID' from $LICENSE_URL (nothing was changed in $OUTPUT_DIR)"
    fi
fi

# README
cp "$TEMPLATE_README" "$STAGE/README.md"
subst_tokens "$STAGE/README.md" "PACKAGENAME=$TOKEN_PACKAGE_NAME" "MODULENAME=$TOKEN_MODULE_NAME" \
    "STRUCTNAME=$TOKEN_STRUCT_NAME" "SYMBOL=$TOKEN_SYMBOL" "NAME=$TOKEN_NAME" \
    "DESCRIPTION=$TOKEN_DESCRIPTION" "DECIMALS=$TOKEN_DECIMALS"

# The README License section matches the selected license. The template's licence line is matched
# whatever licence the template itself ships with; the new line replaces it whole.
if [[ "$LICENSE_PROPRIETARY" == "1" ]]; then
    LICENSE_LINE="All rights reserved. This package is proprietary and not licensed for redistribution."
else
    LICENSE_LINE="${TOKEN_LICENSE_NAME} — see the LICENSE file."
fi
tmp="$(mktemp "$STAGE/.readme.XXXXXX")"
LICENSE_LINE="$LICENSE_LINE" awk '/^(CC0 1\.0 Universal|BSD Zero Clause License)/ { print ENVIRON["LICENSE_LINE"]; next } { print }' \
    "$STAGE/README.md" > "$tmp" && mv "$tmp" "$STAGE/README.md"

# deployments.md, CLAUDE.md, AGENTS.md
cp "$TEMPLATE_DEPLOYMENTS" "$STAGE/deployments.md"
subst_tokens "$STAGE/deployments.md" "SYMBOL=$TOKEN_SYMBOL" "MODULENAME=$TOKEN_MODULE_NAME"
cp "$TEMPLATE_CLAUDE" "$STAGE/CLAUDE.md"
subst_tokens "$STAGE/CLAUDE.md" "PACKAGENAME=$TOKEN_PACKAGE_NAME" "MODULENAME=$TOKEN_MODULE_NAME" \
    "STRUCTNAME=$TOKEN_STRUCT_NAME" "SYMBOL=$TOKEN_SYMBOL" "PROJECTNAME=$TOKEN_PROJECT_NAME"
cp "$TEMPLATE_AGENTS" "$STAGE/AGENTS.md"
subst_tokens "$STAGE/AGENTS.md" "PACKAGENAME=$TOKEN_PACKAGE_NAME" "MODULENAME=$TOKEN_MODULE_NAME" \
    "STRUCTNAME=$TOKEN_STRUCT_NAME" "SYMBOL=$TOKEN_SYMBOL" "PROJECTNAME=$TOKEN_PROJECT_NAME"

# Template source. The token-parameter constants have DISTINCT default lines (so the browser deployer can
# patch them in the compiled bytecode); each is replaced as a whole line, so no value can collide with
# another placeholder or be reinterpreted by a regex.
SRC="$STAGE/sources/$TOKEN_MODULE_NAME.move"
cp "$TEMPLATE_MOVE" "$SRC"
if [[ "$LICENSE_PROPRIETARY" == "1" ]]; then
    sed -i '1s|^// SPDX-License-Identifier:.*|// SPDX-License-Identifier: UNLICENSED|' "$SRC"
    sed -i '2s|^//.*|// All rights reserved. Proprietary and not licensed for redistribution.|' "$SRC"
else
    sed -i "1s|^// SPDX-License-Identifier:.*|// SPDX-License-Identifier: $SPDX_ID|" "$SRC"
    sed -i "2s|^//.*|// Licensed under the $SPDX_ID license; see the LICENSE file.|" "$SRC"
fi
sed -i "s/module sui_token_template::sui_token_template;/module $TOKEN_PACKAGE_NAME::$TOKEN_MODULE_NAME;/g" "$SRC"
sed -i "s/SUI_TOKEN_TEMPLATE/$TOKEN_STRUCT_NAME/g" "$SRC"
subst_tokens "$SRC" "PACKAGEDESCRIPTION=$TOKEN_PACKAGE_DESCRIPTION" "MODULENAME=$TOKEN_MODULE_NAME"
set_line "$SRC" 'const DECIMALS: u8 = 9;' "const DECIMALS: u8 = ${TOKEN_DECIMALS};"
set_line "$SRC" 'const SYMBOL: vector<u8> = b"TEMPLATE_SYMBOL";' "const SYMBOL: vector<u8> = b\"${TOKEN_SYMBOL}\";"
set_line "$SRC" 'const NAME: vector<u8> = b"TEMPLATE_NAME";' "const NAME: vector<u8> = b\"${TOKEN_NAME}\";"
set_line "$SRC" 'const DESCRIPTION: vector<u8> = b"TEMPLATE_DESCRIPTION";' "const DESCRIPTION: vector<u8> = b\"${TOKEN_DESCRIPTION}\";"
set_line "$SRC" 'const ICON_URL: vector<u8> = b"TEMPLATE_ICON_URL";' "const ICON_URL: vector<u8> = b\"${TOKEN_ICON_URL}\";"

# ─────────────────────────────────────────────────────────────────────────────
# Post-generation checks, all on the staging copy. A failure here leaves OUTPUT_DIR untouched.
# ─────────────────────────────────────────────────────────────────────────────
! grep -q "sui_token_template" "$SRC" || fail "Template identifier 'sui_token_template' still present in generated source. Substitution failed."
! grep -q "sui_token_template" "$STAGE/Move.toml" || fail "Template identifier 'sui_token_template' still present in Move.toml. Substitution failed."
! grep -q "SUI_TOKEN_TEMPLATE" "$STAGE/scripts/publish.sh" || fail "Template identifier 'SUI_TOKEN_TEMPLATE' still present in generated publish.sh. Substitution failed."
! grep -qE 'X[A-Z_]+X' "$STAGE/scripts/publish.sh" || fail "Unreplaced X...X placeholder in generated publish.sh. Substitution incomplete."
# README, deployments.md, CLAUDE.md, AGENTS.md, LICENSE, and the doc tokens of the source were checked for
# unmapped template placeholders by subst_tokens itself (a user value that looks like a token is fine: it
# was inserted literally and is not rescanned).

# ─────────────────────────────────────────────────────────────────────────────
# Install: copy the generated files over the output directory. Nothing else in it is touched.
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p "$OUT_ABS"
# Hidden staging helpers are never part of the package.
rm -f "$STAGE"/.subst.* "$STAGE"/.line.* "$STAGE"/.readme.* 2>/dev/null || true
cp -a "$STAGE"/. "$OUT_ABS"/
if [[ "$LICENSE_PROPRIETARY" == "1" ]]; then
    # Switching an existing instance to proprietary removes the LICENSE this generator wrote earlier.
    rm -f -- "$OUT_ABS/LICENSE"
fi

echo "✓ Package generated successfully"
echo ""
echo "Generated constants (check these before publishing; they are permanent on-chain):"
grep -E '^const (DECIMALS|SYMBOL|NAME|DESCRIPTION|ICON_URL):' "$OUT_ABS/sources/$TOKEN_MODULE_NAME.move" | sed 's/^/  /'
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff $OUTPUT_DIR"
echo "  2. Commit: git add $OUTPUT_DIR && git commit"
echo "  3. Publish: bash $OUTPUT_DIR/scripts/publish.sh"
