#!/bin/bash
set -euo pipefail

# Preflight validation for coin deployment.
#
# Checks tools, network, addresses, balances, and image file.
# Exits 0 if all checks pass, 1 on first failure.
#
# Required env vars (all must be set and non-empty):
#   TOKEN_PACKAGE_NAME          e.g. "my_token"
#   TOKEN_MODULE_NAME           e.g. "mytoken"
#   TOKEN_STRUCT_NAME           e.g. "MYTOKEN"
#   TOKEN_SYMBOL                e.g. "myTOKEN"
#   TOKEN_NAME                  e.g. "My Token"
#   TOKEN_DESCRIPTION           e.g. "A custom token on the Sui blockchain"
#   TOKEN_DECIMALS              e.g. "9"
#   TOKEN_IMAGE_PATH            path to the image file
#   OUTPUT_DIR                 where to write the generated package
#   TREASURY_ADDRESS           governance multisig address (0x + 64 hex chars)
#   NETWORK                    "testnet" or "mainnet"
#
# Optional flag:
#   --output-file <path>       Write TOKEN_DEPLOYER_ADDRESS to file for sourcing
#
# Usage (standalone):
#   TOKEN_PACKAGE_NAME=... TOKEN_MODULE_NAME=... ... NETWORK=mainnet \
#   bash scripts/preflight.sh
#
# Usage (with output file):
#   TOKEN_PACKAGE_NAME=... ... NETWORK=mainnet \
#   bash scripts/preflight.sh --output-file /tmp/preflight.env
#   source /tmp/preflight.env  # Now $TOKEN_DEPLOYER_ADDRESS is available

# Parse --output-file flag
OUTPUT_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown option $1" >&2
            exit 1
            ;;
    esac
done

# Validate required env vars (colon expansion: fails on unset AND empty)
: "${TOKEN_PACKAGE_NAME:?TOKEN_PACKAGE_NAME must be set and non-empty}"
: "${TOKEN_MODULE_NAME:?TOKEN_MODULE_NAME must be set and non-empty}"
: "${TOKEN_STRUCT_NAME:?TOKEN_STRUCT_NAME must be set and non-empty}"
: "${TOKEN_SYMBOL:?TOKEN_SYMBOL must be set and non-empty}"
: "${TOKEN_NAME:?TOKEN_NAME must be set and non-empty}"
: "${TOKEN_DESCRIPTION:?TOKEN_DESCRIPTION must be set and non-empty}"
: "${TOKEN_DECIMALS:?TOKEN_DECIMALS must be set and non-empty}"
: "${TOKEN_IMAGE_PATH:?TOKEN_IMAGE_PATH must be set and non-empty}"
: "${OUTPUT_DIR:?OUTPUT_DIR must be set and non-empty}"
: "${TREASURY_ADDRESS:?TREASURY_ADDRESS must be set and non-empty}"
: "${NETWORK:?NETWORK must be set and non-empty}"

echo "=== Preflight Checks ==="
echo ""

# Check required tools
for tool in walrus sui jq; do
    if ! command -v "$tool" &>/dev/null; then
        echo "ERROR: Required tool '$tool' not found in PATH" >&2
        exit 1
    fi
done

# Derive deployer address from active Sui client address
TOKEN_DEPLOYER_ADDRESS=$(sui client active-address)
if [[ -z "$TOKEN_DEPLOYER_ADDRESS" ]]; then
    echo "ERROR: Could not determine active Sui address" >&2
    exit 1
fi

# Validate NETWORK
if [[ "$NETWORK" != "testnet" && "$NETWORK" != "mainnet" ]]; then
    echo "ERROR: NETWORK must be 'testnet' or 'mainnet', got '$NETWORK'" >&2
    exit 1
fi

# Check active Sui environment matches NETWORK (warning only)
ACTIVE_ENV=$(sui client active-env 2>/dev/null || echo "unknown")
if [[ "$ACTIVE_ENV" != "$NETWORK" ]]; then
    echo "WARNING: Active Sui environment is '$ACTIVE_ENV' but NETWORK is '$NETWORK'." >&2
    echo "         Run: sui client switch --env $NETWORK" >&2
    echo "         Proceeding anyway — ensure this is intentional." >&2
    echo "" >&2
fi

# Check image file exists
if [[ ! -f "$TOKEN_IMAGE_PATH" ]]; then
    echo "ERROR: TOKEN_IMAGE_PATH '$TOKEN_IMAGE_PATH' does not exist or is not a file" >&2
    exit 1
fi

# Validate TREASURY_ADDRESS format (0x + 64 hex characters)
if [[ ! "$TREASURY_ADDRESS" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo "ERROR: TREASURY_ADDRESS '$TREASURY_ADDRESS' is not a valid Sui address (expected 0x + 64 hex chars)" >&2
    exit 1
fi

# SUI balance check (warn, do not abort)
# Use recursive descent to handle both array and object response shapes
BALANCE=$(sui client balance --json 2>/dev/null \
  | jq -r '[ .. | objects | select(.coinType? == "0x2::sui::SUI") | .totalBalance ] | first // empty' \
  2>/dev/null \
  || echo "0")
if [[ -z "$BALANCE" || "$BALANCE" == "null" ]]; then
    BALANCE="0"
fi
if (( BALANCE < 1000000000 )); then
    echo "WARNING: SUI balance is $BALANCE MIST (< 1 SUI). You may not have enough gas for deployment." >&2
fi

echo "Configuration:"
echo "  Deployer address:  $TOKEN_DEPLOYER_ADDRESS"
echo "  Treasury address:  $TREASURY_ADDRESS"
echo "  Network:           $NETWORK"
echo "  Image path:        $TOKEN_IMAGE_PATH"
echo "  Output directory:  $OUTPUT_DIR"
echo "  Package name:      $TOKEN_PACKAGE_NAME"
echo "  Module name:       $TOKEN_MODULE_NAME"
echo "  Struct name:       $TOKEN_STRUCT_NAME"
echo ""

# Write output file if requested
if [[ -n "$OUTPUT_FILE" ]]; then
    cat > "$OUTPUT_FILE" <<EOF
TOKEN_DEPLOYER_ADDRESS='$TOKEN_DEPLOYER_ADDRESS'
EOF
fi

echo "✓ All preflight checks passed"
exit 0
