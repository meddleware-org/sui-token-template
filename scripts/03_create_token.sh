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
# Optional license controls (default: CC0-1.0, preserving historical behaviour):
#   TOKEN_LICENSE           SPDX identifier (e.g. "MIT", "Apache-2.0", "CC0-1.0")
#                           or "NONE" for a proprietary / all-rights-reserved package.
#   TOKEN_LICENSE_TEXT_FILE Path to the full license text to embed as the package
#                           LICENSE file. If omitted for a non-CC0 license, the text
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

# Parse --output-dir flag
OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown option $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$OUTPUT_DIR" ]]; then
    echo "ERROR: --output-dir flag is required" >&2
    exit 1
fi

# Locate template directory (script's parent directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/.."
TEMPLATE_MOVE="$TEMPLATE_DIR/sources/sui_token_template.move"
TEMPLATE_TOML="$TEMPLATE_DIR/Move.toml"

if [[ ! -f "$TEMPLATE_MOVE" ]]; then
    echo "ERROR: Template source not found at $TEMPLATE_MOVE" >&2
    exit 1
fi

if [[ ! -f "$TEMPLATE_TOML" ]]; then
    echo "ERROR: Template Move.toml not found at $TEMPLATE_TOML" >&2
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# License resolution (see the usage block above for the env vars involved).
# The default is CC0-1.0, which uses the bundled LICENSE text and therefore keeps
# the default generation path fully offline and byte-identical to prior output.
# ─────────────────────────────────────────────────────────────────────────────
TOKEN_LICENSE="${TOKEN_LICENSE:-CC0-1.0}"
TOKEN_LICENSE_TEXT_FILE="${TOKEN_LICENSE_TEXT_FILE:-}"
TOKEN_LICENSE_NAME="${TOKEN_LICENSE_NAME:-$TOKEN_LICENSE}"

_license_upper="$(printf '%s' "$TOKEN_LICENSE" | tr '[:lower:]' '[:upper:]')"
if [[ "$_license_upper" == "NONE" || "$_license_upper" == "UNLICENSED" || "$_license_upper" == "NOASSERTION" ]]; then
    LICENSE_PROPRIETARY=1
    SPDX_ID="UNLICENSED"
else
    LICENSE_PROPRIETARY=0
    SPDX_ID="$TOKEN_LICENSE"
fi

# Create output directories
mkdir -p "$OUTPUT_DIR/sources"
mkdir -p "$OUTPUT_DIR/scripts"

echo "=== Generating coin package from template ==="
echo "  Package: $TOKEN_PACKAGE_NAME"
echo "  Module: $TOKEN_MODULE_NAME"
echo "  Struct: $TOKEN_STRUCT_NAME"
echo "  Output: $OUTPUT_DIR"
echo ""

# Copy Move.toml and substitute package name
sed "s/sui_token_template/$TOKEN_PACKAGE_NAME/g" "$TEMPLATE_TOML" > "$OUTPUT_DIR/Move.toml"

# Substitute the license field (SPDX id, or "UNLICENSED" for proprietary)
sed -i "s|^license = .*|license = \"$SPDX_ID\"|" "$OUTPUT_DIR/Move.toml"

# Copy and substitute publish.sh
TEMPLATE_PUBLISH="$TEMPLATE_DIR/templates/publish.sh"
if [[ ! -f "$TEMPLATE_PUBLISH" ]]; then
    echo "ERROR: Template publish script not found at $TEMPLATE_PUBLISH" >&2
    exit 1
fi
cp "$TEMPLATE_PUBLISH" "$OUTPUT_DIR/scripts/publish.sh"
chmod +x "$OUTPUT_DIR/scripts/publish.sh"
# Substitute placeholders in publish.sh
sed -i "s/SUI_TOKEN_TEMPLATE/$TOKEN_STRUCT_NAME/g" "$OUTPUT_DIR/scripts/publish.sh"
sed -i "s|XMODULENAMEX|$TOKEN_MODULE_NAME|g" "$OUTPUT_DIR/scripts/publish.sh"
sed -i "s|XPACKAGENAMEX|$TOKEN_PACKAGE_NAME|g" "$OUTPUT_DIR/scripts/publish.sh"

# Validate template files for LICENSE, .gitignore, and README template
TEMPLATE_LICENSE="$TEMPLATE_DIR/LICENSE"
if [[ ! -f "$TEMPLATE_LICENSE" ]]; then
    echo "ERROR: Template LICENSE not found at $TEMPLATE_LICENSE" >&2
    exit 1
fi

TEMPLATE_GITIGNORE="$TEMPLATE_DIR/templates/gitignore"
if [[ ! -f "$TEMPLATE_GITIGNORE" ]]; then
    echo "ERROR: Template gitignore not found at $TEMPLATE_GITIGNORE" >&2
    exit 1
fi

TEMPLATE_README="$TEMPLATE_DIR/templates/README.md"
if [[ ! -f "$TEMPLATE_README" ]]; then
    echo "ERROR: Template README not found at $TEMPLATE_README" >&2
    exit 1
fi

TEMPLATE_DEPLOYMENTS="$TEMPLATE_DIR/templates/deployments.md"
if [[ ! -f "$TEMPLATE_DEPLOYMENTS" ]]; then
    echo "ERROR: Template deployments.md not found at $TEMPLATE_DEPLOYMENTS" >&2
    exit 1
fi

TEMPLATE_CLAUDE="$TEMPLATE_DIR/templates/CLAUDE.md"
if [[ ! -f "$TEMPLATE_CLAUDE" ]]; then
    echo "ERROR: Template CLAUDE.md not found at $TEMPLATE_CLAUDE" >&2
    exit 1
fi

TEMPLATE_AGENTS="$TEMPLATE_DIR/templates/AGENTS.md"
if [[ ! -f "$TEMPLATE_AGENTS" ]]; then
    echo "ERROR: Template AGENTS.md not found at $TEMPLATE_AGENTS" >&2
    exit 1
fi

# Copy .gitignore verbatim
cp "$TEMPLATE_GITIGNORE" "$OUTPUT_DIR/.gitignore"

# Resolve and write the LICENSE file according to the selected license.
if [[ "$LICENSE_PROPRIETARY" == "1" ]]; then
    # Proprietary / all-rights-reserved: no LICENSE file is written.
    rm -f "$OUTPUT_DIR/LICENSE"
elif [[ -n "$TOKEN_LICENSE_TEXT_FILE" ]]; then
    if [[ ! -f "$TOKEN_LICENSE_TEXT_FILE" ]]; then
        echo "ERROR: TOKEN_LICENSE_TEXT_FILE not found at $TOKEN_LICENSE_TEXT_FILE" >&2
        rm -rf "$OUTPUT_DIR"; exit 1
    fi
    cp "$TOKEN_LICENSE_TEXT_FILE" "$OUTPUT_DIR/LICENSE"
elif [[ "$SPDX_ID" == "CC0-1.0" ]]; then
    # Offline default: bundled CC0 text (byte-identical to prior behaviour).
    cp "$TEMPLATE_LICENSE" "$OUTPUT_DIR/LICENSE"
else
    # Fetch the canonical text from the SPDX license-list-data archive.
    LICENSE_URL="https://raw.githubusercontent.com/spdx/license-list-data/main/text/${SPDX_ID}.txt"
    if ! curl -fsSL "$LICENSE_URL" -o "$OUTPUT_DIR/LICENSE"; then
        echo "ERROR: could not fetch license text for '$SPDX_ID' from $LICENSE_URL" >&2
        echo "       Pass TOKEN_LICENSE_TEXT_FILE=<path> to supply the text directly." >&2
        rm -rf "$OUTPUT_DIR"; exit 1
    fi
fi

# Copy and substitute README template
cp "$TEMPLATE_README" "$OUTPUT_DIR/README.md"
sed -i "s|XPACKAGENAMEX|$TOKEN_PACKAGE_NAME|g" "$OUTPUT_DIR/README.md"
sed -i "s|XMODULENAMEX|$TOKEN_MODULE_NAME|g" "$OUTPUT_DIR/README.md"
sed -i "s|XSTRUCTNAMEX|$TOKEN_STRUCT_NAME|g" "$OUTPUT_DIR/README.md"
sed -i "s|XSYMBOLX|$TOKEN_SYMBOL|g" "$OUTPUT_DIR/README.md"
sed -i "s|XNAMEX|$TOKEN_NAME|g" "$OUTPUT_DIR/README.md"
sed -i "s|XDESCRIPTIONX|$TOKEN_DESCRIPTION|g" "$OUTPUT_DIR/README.md"
sed -i "s|XDECIMALSX|$TOKEN_DECIMALS|g" "$OUTPUT_DIR/README.md"

# Substitute the README License section to match the selected license.
# CC0 retains the original public-domain wording for byte-identical default output.
if [[ "$LICENSE_PROPRIETARY" == "1" ]]; then
    sed -i "s|^CC0 1\.0 Universal.*|All rights reserved. This package is proprietary and not licensed for redistribution.|" "$OUTPUT_DIR/README.md"
elif [[ "$SPDX_ID" != "CC0-1.0" ]]; then
    sed -i "s|^CC0 1\.0 Universal.*|${TOKEN_LICENSE_NAME} — see the LICENSE file.|" "$OUTPUT_DIR/README.md"
fi

# Copy and substitute deployments.md template
cp "$TEMPLATE_DEPLOYMENTS" "$OUTPUT_DIR/deployments.md"
sed -i "s|XSYMBOLX|$TOKEN_SYMBOL|g" "$OUTPUT_DIR/deployments.md"
sed -i "s|XMODULENAMEX|$TOKEN_MODULE_NAME|g" "$OUTPUT_DIR/deployments.md"

# Copy and substitute CLAUDE.md template
cp "$TEMPLATE_CLAUDE" "$OUTPUT_DIR/CLAUDE.md"
sed -i "s|XPACKAGENAMEX|$TOKEN_PACKAGE_NAME|g" "$OUTPUT_DIR/CLAUDE.md"
sed -i "s|XMODULENAMEX|$TOKEN_MODULE_NAME|g" "$OUTPUT_DIR/CLAUDE.md"
sed -i "s|XSTRUCTNAMEX|$TOKEN_STRUCT_NAME|g" "$OUTPUT_DIR/CLAUDE.md"
sed -i "s|XSYMBOLX|$TOKEN_SYMBOL|g" "$OUTPUT_DIR/CLAUDE.md"
sed -i "s|XPROJECTNAMEX|$TOKEN_PROJECT_NAME|g" "$OUTPUT_DIR/CLAUDE.md"

# Copy and substitute AGENTS.md template
cp "$TEMPLATE_AGENTS" "$OUTPUT_DIR/AGENTS.md"
sed -i "s|XPACKAGENAMEX|$TOKEN_PACKAGE_NAME|g" "$OUTPUT_DIR/AGENTS.md"
sed -i "s|XMODULENAMEX|$TOKEN_MODULE_NAME|g" "$OUTPUT_DIR/AGENTS.md"
sed -i "s|XSTRUCTNAMEX|$TOKEN_STRUCT_NAME|g" "$OUTPUT_DIR/AGENTS.md"
sed -i "s|XSYMBOLX|$TOKEN_SYMBOL|g" "$OUTPUT_DIR/AGENTS.md"
sed -i "s|XPROJECTNAMEX|$TOKEN_PROJECT_NAME|g" "$OUTPUT_DIR/AGENTS.md"

# Copy template source with all substitutions
# Substitutions:
# 1. Module path: sui_token_template::sui_token_template → TOKEN_PACKAGE_NAME::TOKEN_MODULE_NAME
# 2. Struct name: SUI_TOKEN_TEMPLATE → TOKEN_STRUCT_NAME
# 3. Named constants: DECIMALS (9), and the distinct b"TEMPLATE_*" defaults → actual values

# Start with the template
cp "$TEMPLATE_MOVE" "$OUTPUT_DIR/sources/sui_token_template.move"

# License header substitution (lines 1-2 of the template source). CC0 keeps the
# original public-domain dedication; other licenses adjust the SPDX tag + comment.
if [[ "$LICENSE_PROPRIETARY" == "1" ]]; then
    sed -i '1s|^// SPDX-License-Identifier:.*|// SPDX-License-Identifier: UNLICENSED|' "$OUTPUT_DIR/sources/sui_token_template.move"
    sed -i '2s|^// This work is dedicated.*|// All rights reserved. Proprietary and not licensed for redistribution.|' "$OUTPUT_DIR/sources/sui_token_template.move"
elif [[ "$SPDX_ID" != "CC0-1.0" ]]; then
    sed -i "1s|^// SPDX-License-Identifier:.*|// SPDX-License-Identifier: $SPDX_ID|" "$OUTPUT_DIR/sources/sui_token_template.move"
    sed -i "2s|^// This work is dedicated.*|// Licensed under the $SPDX_ID license; see the LICENSE file.|" "$OUTPUT_DIR/sources/sui_token_template.move"
fi

# Module path substitution (must be done as a pair to avoid partial replacements)
sed -i "s/module sui_token_template::sui_token_template;/module $TOKEN_PACKAGE_NAME::$TOKEN_MODULE_NAME;/g" \
    "$OUTPUT_DIR/sources/sui_token_template.move"

# Struct name substitution
sed -i "s/SUI_TOKEN_TEMPLATE/$TOKEN_STRUCT_NAME/g" "$OUTPUT_DIR/sources/sui_token_template.move"

# Package description and module name placeholders in doc comments
sed -i "s|XPACKAGEDESCRIPTIONX|$TOKEN_PACKAGE_DESCRIPTION|g" "$OUTPUT_DIR/sources/sui_token_template.move"
sed -i "s|XMODULENAMEX|$TOKEN_MODULE_NAME|g" "$OUTPUT_DIR/sources/sui_token_template.move"

# Token-parameter constant substitutions. The template declares these as named
# constants with DISTINCT default values (so the browser deployer can patch them
# in the compiled bytecode); here we substitute each one unambiguously.
# Using | as delimiter to avoid issues with / in values like "mySUI/SUI".
sed -i "s|const DECIMALS: u8 = 9;|const DECIMALS: u8 = $TOKEN_DECIMALS;|" "$OUTPUT_DIR/sources/sui_token_template.move"
sed -i "s|b\"TEMPLATE_SYMBOL\"|b\"$TOKEN_SYMBOL\"|" "$OUTPUT_DIR/sources/sui_token_template.move"
sed -i "s|b\"TEMPLATE_NAME\"|b\"$TOKEN_NAME\"|" "$OUTPUT_DIR/sources/sui_token_template.move"
sed -i "s|b\"TEMPLATE_DESCRIPTION\"|b\"$TOKEN_DESCRIPTION\"|" "$OUTPUT_DIR/sources/sui_token_template.move"
sed -i "s|b\"TEMPLATE_ICON_URL\"|b\"$TOKEN_ICON_URL\"|" "$OUTPUT_DIR/sources/sui_token_template.move"

# Rename source file from sui_token_template.move to $TOKEN_MODULE_NAME.move
mv "$OUTPUT_DIR/sources/sui_token_template.move" "$OUTPUT_DIR/sources/$TOKEN_MODULE_NAME.move"

# Validation: ensure sui_token_template identifier was fully replaced
if grep -q "sui_token_template" "$OUTPUT_DIR/sources/$TOKEN_MODULE_NAME.move"; then
    echo "ERROR: Template identifier 'sui_token_template' still present in generated source. Substitution failed." >&2
    rm -rf "$OUTPUT_DIR"
    exit 1
fi

if grep -q "sui_token_template" "$OUTPUT_DIR/Move.toml"; then
    echo "ERROR: Template identifier 'sui_token_template' still present in Move.toml. Substitution failed." >&2
    rm -rf "$OUTPUT_DIR"
    exit 1
fi

# Check for remaining TEMPLATE placeholders (should not exist after all substitutions)
if grep -q "TEMPLATE" "$OUTPUT_DIR/sources/$TOKEN_MODULE_NAME.move"; then
    echo "ERROR: Placeholder 'TEMPLATE' still present in generated source. Substitution incomplete." >&2
    rm -rf "$OUTPUT_DIR"
    exit 1
fi

# Check for remaining X...X placeholders in generated Move source
if grep -qE 'X[A-Z_]+X' "$OUTPUT_DIR/sources/$TOKEN_MODULE_NAME.move"; then
    echo "ERROR: Unreplaced X...X placeholder in generated Move source. Substitution incomplete." >&2
    rm -rf "$OUTPUT_DIR"
    exit 1
fi

# Validate generated publish.sh: no template identifiers should remain
if grep -q "SUI_TOKEN_TEMPLATE" "$OUTPUT_DIR/scripts/publish.sh"; then
    echo "ERROR: Template identifier 'SUI_TOKEN_TEMPLATE' still present in generated publish.sh. Substitution failed." >&2
    rm -rf "$OUTPUT_DIR"
    exit 1
fi

if grep -qE 'X[A-Z_]+X' "$OUTPUT_DIR/scripts/publish.sh"; then
    echo "ERROR: Unreplaced X...X placeholder in generated publish.sh. Substitution incomplete." >&2
    rm -rf "$OUTPUT_DIR"
    exit 1
fi

# Check for remaining X...X placeholders in README.md
if grep -qE 'X[A-Z_]+X' "$OUTPUT_DIR/README.md"; then
    echo "ERROR: Unreplaced placeholder in README.md. Substitution incomplete." >&2
    rm -rf "$OUTPUT_DIR"
    exit 1
fi

# Check for remaining X...X placeholders in deployments.md
if grep -qE 'X[A-Z_]+X' "$OUTPUT_DIR/deployments.md"; then
    echo "ERROR: Unreplaced placeholder in deployments.md. Substitution incomplete." >&2
    rm -rf "$OUTPUT_DIR"
    exit 1
fi

# Check for remaining X...X placeholders in CLAUDE.md
if grep -qE 'X[A-Z_]+X' "$OUTPUT_DIR/CLAUDE.md"; then
    echo "ERROR: Unreplaced placeholder in CLAUDE.md. Substitution incomplete." >&2
    rm -rf "$OUTPUT_DIR"
    exit 1
fi

# Check for remaining X...X placeholders in AGENTS.md
if grep -qE 'X[A-Z_]+X' "$OUTPUT_DIR/AGENTS.md"; then
    echo "ERROR: Unreplaced placeholder in AGENTS.md. Substitution incomplete." >&2
    rm -rf "$OUTPUT_DIR"
    exit 1
fi

echo "✓ Package generated successfully"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff $OUTPUT_DIR"
echo "  2. Commit: git add $OUTPUT_DIR && git commit"
echo "  3. Publish: bash $OUTPUT_DIR/scripts/publish.sh"
