#!/bin/bash
set -euo pipefail

# Deploy a token package end-to-end: upload image to Walrus, generate token package,
# build, test, publish on-chain, and transfer TreasuryCap to governance.
#
# Required env vars (all must be set and non-empty):
#   TOKEN_PACKAGE_NAME         e.g. "my_token"
#   TOKEN_MODULE_NAME          e.g. "mytoken"
#   TOKEN_STRUCT_NAME          e.g. "MYTOKEN"
#   TOKEN_SYMBOL               e.g. "myTOKEN"
#   TOKEN_NAME                 e.g. "My Token"
#   TOKEN_DESCRIPTION          e.g. "A custom token on the Sui blockchain"
#   TOKEN_PACKAGE_DESCRIPTION  e.g. "Official MYTOKEN share token."
#   TOKEN_PROJECT_NAME         e.g. "My Project"
#   TOKEN_DECIMALS             e.g. "9"
#   TOKEN_IMAGE_PATH           path to the image file
#   OUTPUT_DIR                 where to write the generated package
#   TREASURY_ADDRESS           governance multisig address (0x + 64 hex chars)
#   NETWORK                    "testnet" or "mainnet"
#
# Usage:
#   TOKEN_PACKAGE_NAME=my_token TOKEN_MODULE_NAME=mytoken TOKEN_STRUCT_NAME=MYTOKEN \
#   TOKEN_SYMBOL="myTOKEN" TOKEN_NAME="My Token" \
#   TOKEN_DESCRIPTION="A custom token on the Sui blockchain" \
#   TOKEN_DECIMALS="9" TOKEN_IMAGE_PATH="assets/img/mytoken.png" \
#   OUTPUT_DIR="my_token" \
#   TREASURY_ADDRESS="0xd1b80100f67d6ef4e696bb2bef234a89e89e2b4789eb91e8d5493712fd15197e" \
#   NETWORK="mainnet" \
#   bash scripts/deploy_token.sh

# Validate required env vars (colon expansion: fails on unset AND empty)
: "${TOKEN_PACKAGE_NAME:?TOKEN_PACKAGE_NAME must be set and non-empty}"
: "${TOKEN_MODULE_NAME:?TOKEN_MODULE_NAME must be set and non-empty}"
: "${TOKEN_STRUCT_NAME:?TOKEN_STRUCT_NAME must be set and non-empty}"
: "${TOKEN_SYMBOL:?TOKEN_SYMBOL must be set and non-empty}"
: "${TOKEN_NAME:?TOKEN_NAME must be set and non-empty}"
: "${TOKEN_DESCRIPTION:?TOKEN_DESCRIPTION must be set and non-empty}"
: "${TOKEN_PACKAGE_DESCRIPTION:?TOKEN_PACKAGE_DESCRIPTION must be set and non-empty}"
: "${TOKEN_PROJECT_NAME:?TOKEN_PROJECT_NAME must be set and non-empty}"
: "${TOKEN_DECIMALS:?TOKEN_DECIMALS must be set and non-empty}"
: "${TOKEN_IMAGE_PATH:?TOKEN_IMAGE_PATH must be set and non-empty}"
: "${OUTPUT_DIR:?OUTPUT_DIR must be set and non-empty}"
: "${TREASURY_ADDRESS:?TREASURY_ADDRESS must be set and non-empty}"
: "${NETWORK:?NETWORK must be set and non-empty}"

# Locate script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Phase 1: Preflight
# ============================================================================

echo "=== Phase 1: Preflight ==="
echo ""

PREFLIGHT_OUTPUT=$(mktemp)
bash "$SCRIPT_DIR/01_preflight.sh" --output-file "$PREFLIGHT_OUTPUT"
# shellcheck source=/dev/null
source "$PREFLIGHT_OUTPUT"
rm -f "$PREFLIGHT_OUTPUT"

echo ""

# ============================================================================
# Phase 2: Walrus Upload
# ============================================================================

echo "=== Phase 2: Walrus Upload ==="
echo ""

WALRUS_OUTPUT=$(mktemp)
NETWORK="$NETWORK" TOKEN_IMAGE_PATH="$TOKEN_IMAGE_PATH" \
    bash "$SCRIPT_DIR/02_upload_image.sh" --output-file "$WALRUS_OUTPUT"
# shellcheck source=/dev/null
source "$WALRUS_OUTPUT"
rm -f "$WALRUS_OUTPUT"

echo ""

# ============================================================================
# Phase 3: Generate Package
# ============================================================================

echo "=== Phase 3: Generate Package ==="
echo ""

TOKEN_ICON_URL="$BLOB_URL" \
TOKEN_PACKAGE_NAME="$TOKEN_PACKAGE_NAME" \
TOKEN_MODULE_NAME="$TOKEN_MODULE_NAME" \
TOKEN_STRUCT_NAME="$TOKEN_STRUCT_NAME" \
TOKEN_SYMBOL="$TOKEN_SYMBOL" \
TOKEN_NAME="$TOKEN_NAME" \
TOKEN_DESCRIPTION="$TOKEN_DESCRIPTION" \
TOKEN_PACKAGE_DESCRIPTION="$TOKEN_PACKAGE_DESCRIPTION" \
TOKEN_PROJECT_NAME="$TOKEN_PROJECT_NAME" \
TOKEN_DECIMALS="$TOKEN_DECIMALS" \
bash "$SCRIPT_DIR/03_create_token.sh" --output-dir "$OUTPUT_DIR"

echo ""

# ============================================================================
# Phase 4: Build and Test
# ============================================================================

echo "=== Phase 4: Build and Test ==="
echo ""

echo "Running tests..."
sui move test --path "$OUTPUT_DIR"

echo ""
echo "Building package..."
sui move build --path "$OUTPUT_DIR"

echo ""

# ============================================================================
# Phase 5: Pre-Publish Confirmation
# ============================================================================

echo "=== Phase 5: Pre-Publish Confirmation ==="
echo ""

cat <<EOF
Please review the deployment configuration:

  Network:            $NETWORK
  Package name:       $TOKEN_PACKAGE_NAME
  Module name:        $TOKEN_MODULE_NAME
  Struct name:        $TOKEN_STRUCT_NAME
  Symbol:             $TOKEN_SYMBOL
  Name:               $TOKEN_NAME
  Description:        $TOKEN_DESCRIPTION
  Decimals:           $TOKEN_DECIMALS
  Icon URL:           $BLOB_URL
  Deployer address:   $TOKEN_DEPLOYER_ADDRESS
  Treasury address:   $TREASURY_ADDRESS

EOF

read -rp "Type CONFIRM to proceed with on-chain publish: " CONFIRMATION
if [[ "$CONFIRMATION" != "CONFIRM" ]]; then
    echo "Aborted." >&2
    exit 1
fi
echo ""

# ============================================================================
# Phase 6: Publish
# ============================================================================

echo "=== Phase 6: Publish ==="
echo ""

PUBLISH_OUTPUT=$(sui client publish "$OUTPUT_DIR" --gas-budget 100000000 --json)
echo "$PUBLISH_OUTPUT"

# Parse package ID and TreasuryCap object ID
PACKAGE_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.type == "published") | .packageId')
TREASURY_CAP_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.objectType? | strings | test("TreasuryCap")) | .objectId')

if [[ -z "$PACKAGE_ID" || "$PACKAGE_ID" == "null" ]]; then
    echo "ERROR: Could not parse package ID from publish output" >&2
    exit 1
fi

if [[ -z "$TREASURY_CAP_ID" || "$TREASURY_CAP_ID" == "null" ]]; then
    echo "ERROR: Could not parse TreasuryCap object ID from publish output" >&2
    exit 1
fi

# Parse UpgradeCap object ID
UPGRADE_CAP_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.objectType? | strings | test("UpgradeCap")) | .objectId')

if [[ -z "$UPGRADE_CAP_ID" || "$UPGRADE_CAP_ID" == "null" ]]; then
    echo "ERROR: Could not parse UpgradeCap object ID from publish output" >&2
    exit 1
fi

echo ""
echo "  Package ID:      $PACKAGE_ID"
echo "  TreasuryCap ID:  $TREASURY_CAP_ID"
echo "  UpgradeCap ID:   $UPGRADE_CAP_ID"
echo ""

# ============================================================================
# Phase 6b: Burn UpgradeCap
# ============================================================================

echo "=== Phase 6b: Burn UpgradeCap ==="
echo ""
echo "  UpgradeCap ID: $UPGRADE_CAP_ID"
echo ""

if ! sui client call \
    --package 0x2 \
    --module package \
    --function make_immutable \
    --args "$UPGRADE_CAP_ID" \
    --gas-budget 10000000; then
    echo "ERROR: UpgradeCap burn FAILED." >&2
    echo "Package was published but is NOT yet immutable." >&2
    echo "Manual recovery:" >&2
    echo "  sui client call --package 0x2 --module package --function make_immutable \\" >&2
    echo "    --args $UPGRADE_CAP_ID --gas-budget 10000000" >&2
    exit 1
fi

echo "UpgradeCap burned. Package is now immutable."
echo ""

# ============================================================================
# Phase 7: Transfer TreasuryCap
# ============================================================================

echo "=== Phase 7: Transfer TreasuryCap ==="
echo ""

if ! sui client transfer --object-id "$TREASURY_CAP_ID" \
       --to "$TREASURY_ADDRESS" --gas-budget 10000000; then
    echo "ERROR: TreasuryCap transfer FAILED." >&2
    echo "Package was published. TreasuryCap has NOT been transferred." >&2
    echo "TreasuryCap object ID: $TREASURY_CAP_ID" >&2
    echo "Manual recovery:" >&2
    echo "  sui client transfer --object-id $TREASURY_CAP_ID \\" >&2
    echo "    --to $TREASURY_ADDRESS --gas-budget 10000000" >&2
    exit 1
fi

echo "TreasuryCap successfully transferred to $TREASURY_ADDRESS"
echo ""

# ============================================================================
# Phase 8: Summary
# ============================================================================

echo "=== Phase 8: Deployment Summary ==="
echo ""

cat <<EOF
Deployment complete!

Network:            $NETWORK
Package ID:         $PACKAGE_ID
TreasuryCap ID:     $TREASURY_CAP_ID
UpgradeCap ID:      $UPGRADE_CAP_ID (burned — package is immutable)
Blob ID:            $BLOB_ID
Blob object ID:     $BLOB_OBJECT_ID
Blob URL:           $BLOB_URL
Treasury address:   $TREASURY_ADDRESS
Deployer address:   $TOKEN_DEPLOYER_ADDRESS

Next steps:
  1. Record the package ID: $PACKAGE_ID
  2. Update downstream Move.toml [addresses] entries
  3. Verify metadata on Sui explorer
  4. Set up blob lifetime monitoring for blob object ID

EOF

if [[ "$BLOB_OBJECT_ID" == "N/A" ]]; then
    cat <<EOF
NOTE: Blob object ID is unavailable for pre-existing blobs.
      Look it up manually:
        walrus blob-status --blob-id $BLOB_ID --context $NETWORK
      The returned object ID is required for lifetime extension.

EOF
fi

cat <<EOF
Epoch reminders (not enforced):
  testnet:  extend before fewer than 10 epochs remain
  mainnet:  extend before fewer than 50 epochs remain

  To extend (requires blob object ID, not blob content ID):
    walrus extend --blob-obj-id <BLOB_OBJECT_ID> --epochs-extended 200 --context $NETWORK

EOF
