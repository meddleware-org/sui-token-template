#!/bin/bash
set -euo pipefail

# Upload an image to Walrus and retrieve the blob URL.
#
# Can be run standalone to get a blob URL for manual token generation,
# or called with --output-file to integrate into deploy_token.sh pipeline.
#
# Required env vars:
#   NETWORK                    "testnet" or "mainnet"
#   TOKEN_IMAGE_PATH           path to the image file
#
# Optional flag:
#   --output-file <path>       Write BLOB_ID, BLOB_OBJECT_ID, BLOB_URL to file for sourcing
#
# Usage (standalone):
#   NETWORK=mainnet TOKEN_IMAGE_PATH=assets/img/icon.png \
#   bash scripts/upload_image.sh
#
# Usage (with output file):
#   NETWORK=mainnet TOKEN_IMAGE_PATH=assets/img/icon.png \
#   bash scripts/upload_image.sh --output-file /tmp/walrus.env
#   source /tmp/walrus.env  # Now $BLOB_URL, $BLOB_ID, $BLOB_OBJECT_ID are available

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

# Validate required env vars
: "${NETWORK:?NETWORK must be set and non-empty}"
: "${TOKEN_IMAGE_PATH:?TOKEN_IMAGE_PATH must be set and non-empty}"

echo "=== Walrus Upload ==="
echo ""

# Set epoch count and aggregator URL based on network
if [[ "$NETWORK" == "testnet" ]]; then
    EPOCHS=50
    BLOB_AGGREGATOR_BASE="https://aggregator.walrus-testnet.walrus.space/v1/blobs"
elif [[ "$NETWORK" == "mainnet" ]]; then
    EPOCHS=200
    BLOB_AGGREGATOR_BASE="https://aggregator.walrus.space/v1/blobs"
else
    echo "ERROR: NETWORK must be 'testnet' or 'mainnet', got '$NETWORK'" >&2
    exit 1
fi

echo "Uploading image to Walrus ($NETWORK, $EPOCHS epochs)..."
echo ""

# Call walrus store and capture JSON output
# Tested with walrus 1.49.1-a00e390b4a1d — --context is a store-subcommand flag
# Normalize: walrus may return a bare object or a single-element array; unwrap if needed
WALRUS_RAW=$(walrus store --context "$NETWORK" --json --epochs "$EPOCHS" "$TOKEN_IMAGE_PATH")
WALRUS_JSON=$(echo "$WALRUS_RAW" | jq 'if type == "array" then .[0] else . end') || {
    echo "ERROR: walrus output is not valid JSON. Raw output:" >&2
    echo "$WALRUS_RAW" >&2
    exit 1
}

# Normalise: walrus 1.49.1+ wraps result under "blobStoreResult"; older builds use bare top-level keys
WALRUS_RESULT=$(echo "$WALRUS_JSON" | jq 'if has("blobStoreResult") then .blobStoreResult else . end')

# Parse blob ID
BLOB_ID=$(echo "$WALRUS_RESULT" | jq -r '
  if has("newlyCreated") then
    (.newlyCreated.blobObject.blobId // .newlyCreated.blobObject.blob_id // .newlyCreated.blobId)
  elif has("alreadyCertified") then
    (.alreadyCertified.blobId // .alreadyCertified.blob_id)
  else error("Unexpected walrus JSON — blobStoreResult keys: \(keys | join(", "))")
  end') || {
    echo "ERROR: Could not parse blob_id. Walrus JSON:" >&2
    echo "$WALRUS_JSON" >&2
    exit 1
}

# Parse object ID (1.49.1 uses flat "object" field; older used nested blobObject.id)
BLOB_OBJECT_ID=$(echo "$WALRUS_RESULT" | jq -r '
  if has("newlyCreated") then
    (.newlyCreated.object
      // (.newlyCreated.blobObject.id | if type == "object" then .id else . end))
  else "N/A"
  end')

BLOB_URL="${BLOB_AGGREGATOR_BASE}/${BLOB_ID}"

# Print warning if blob already existed
if echo "$WALRUS_RESULT" | jq -e 'has("alreadyCertified") or has("already_certified")' >/dev/null 2>&1; then
    echo "WARNING: This blob already exists on the Walrus network (alreadyCertified)."
    echo "         The script cannot verify that this blob contains your intended image."
    echo "         It may be a previous upload of a different version of the image."
    echo "         Blob object ID is unavailable for pre-existing blobs."
    echo ""
fi

echo "  Blob ID:        $BLOB_ID"
echo "  Blob object ID: $BLOB_OBJECT_ID"
echo "  Blob URL:       $BLOB_URL"
echo ""
echo "Please verify the icon resolves correctly before continuing."
echo "Open: $BLOB_URL"
echo ""
read -rp "Press Enter to continue, or Ctrl-C to abort: "
echo ""

# Write output file if requested
if [[ -n "$OUTPUT_FILE" ]]; then
    cat > "$OUTPUT_FILE" <<EOF
BLOB_ID='$BLOB_ID'
BLOB_OBJECT_ID='$BLOB_OBJECT_ID'
BLOB_URL='$BLOB_URL'
EOF
fi

echo "✓ Image uploaded and blob URL verified"
exit 0
