# WALRUS.md — Blob Management and Icon Hosting

This document covers Walrus blob operations for coin icon hosting and lifetime management.

---

## Overview

Coin icons are permanently stored on Walrus (decentralized storage) and referenced immutably in coin metadata on-chain. Once deployed, the icon URL cannot change, so managing blob lifetime is critical.

---

## Blob Concepts

### Blob ID vs Object ID

**Blob ID** (`<base64-string>`):

- Content-addressable identifier derived from file hash.
- Example: `4BKcDC0Ih5RJ8R0tFMz3MZVNZV8b2goT6_JiEEwNHQo`
- Used to retrieve content via aggregator URLs.
- **Not** the Sui object ID.

**Blob Object ID** (`0x<hex>`):

- Sui on-chain object ID for the blob registration.
- Example: `0xabcd1234...`
- Used for lifetime management (extend, delete).
- Returned by `walrus store --json` in the `newlyCreated` case.
- Required for `walrus extend --blob-obj-id`.

**Aggregator URL** (derived from blob ID):

- **Testnet:** `https://aggregator.walrus-testnet.walrus.space/v1/blobs/<BLOB_ID>`
- **Mainnet:** `https://aggregator.walrus.space/v1/blobs/<BLOB_ID>`
- Publicly accessible; no authentication.
- Icon URL stored on-chain is this aggregator URL.

### Walrus Epochs

- One epoch ≈ 2 weeks.
- Blobs must be certified for a certain number of epochs to remain available.
- Default: 200 epochs (≈ 7.7 years) for mainnet long-term storage.
- Each blob has a certified expiry epoch.

---

## Uploading an Icon (`deploy_token.sh` Phase 2)

### Flow

1. **User provides** `TOKEN_IMAGE_PATH` (local PNG or SVG).
2. **Script runs** `walrus store --context $NETWORK --json --epochs $EPOCHS "$TOKEN_IMAGE_PATH"`.
   - Testnet: 50 epochs.
   - Mainnet: 200 epochs.
3. **Walrus CLI returns** JSON with `newlyCreated` or `alreadyCertified`.
4. **Script parses** blob ID and object ID.
5. **Script constructs** aggregator URL.
6. **Script prompts user** to verify the icon resolves by opening the URL.
7. **User types Enter** to confirm, or Ctrl-C to abort.
8. **Icon URL is used** in Phase 3 (generate) as `TOKEN_ICON_URL`.

### Output Structure

**If newly uploaded:**

```json
{
  "newlyCreated": {
    "blobId": "4BKcDC0Ih5RJ8R0tFMz3MZVNZV8b2goT6_JiEEwNHQo",
    "blobObject": {
      "id": "0x1234567890abcdef...",
      "certified_epoch": 42,
      ...
    }
  }
}
```

**If blob already exists** (same content uploaded before):

```json
{
  "alreadyCertified": {
    "blobId": "4BKcDC0Ih5RJ8R0tFMz3MZVNZV8b2goT6_JiEEwNHQo",
    ...
  }
}
```

In the `alreadyCertified` case:

- Blob ID is available (used for aggregator URL).
- **Blob object ID is NOT** in the response.
- User must run `walrus blob-status --blob-id <BLOB_ID> --context mainnet` to find the object ID (needed for lifetime extension).

---

## Verifying the Icon

**Manual check:**

```bash
curl -I https://aggregator.walrus.space/v1/blobs/<BLOB_ID>
# Should return 200 OK
```

**In browser:**

```text
https://aggregator.walrus.space/v1/blobs/<BLOB_ID>
# Should display the image
```

---

## Monitoring Blob Lifetime

### Check Remaining Epochs

```bash
walrus blob-status --blob-id <BLOB_ID> --context mainnet
```

Output includes current epoch and blob's certified expiry epoch. Calculate:

```text
remaining_epochs = certified_epoch - current_epoch
```

### Recommended Thresholds

- **Testnet:** Extend when < 10 epochs remain.
- **Mainnet:** Extend when < 50 epochs remain.

---

## Extending Blob Lifetime

### Command

```bash
walrus extend --blob-obj-id <BLOB_OBJECT_ID> --epochs-extended 200 --context mainnet
```

**Parameters:**

- `--blob-obj-id <BLOB_OBJECT_ID>` — Sui on-chain object ID (0x...), **not** blob ID.
- `--epochs-extended <N>` — Number of epochs to add (200 recommended for mainnet).
- `--context mainnet` or `--context testnet`.

### Example Workflow

```bash
# Check status
walrus blob-status --blob-id 4BKcDC0Ih5RJ8R0tFMz3MZVNZV8b2goT6_JiEEwNHQo --context mainnet

# If < 50 epochs remain, extend
walrus extend --blob-obj-id 0x1234567890abcdef --epochs-extended 200 --context mainnet

# Verify
walrus blob-status --blob-id 4BKcDC0Ih5RJ8R0tFMz3MZVNZV8b2goT6_JiEEwNHQo --context mainnet
```

### If You Lost the Object ID

If you have only the blob content ID and the blob was uploaded long ago:

1. **Blob is your own (single owner):**

   ```bash
   walrus blob-status --blob-id <BLOB_ID> --context mainnet
   ```

   Output includes the blob object ID.

2. **Blob is shared or pre-existing:**
   It may not return the object ID via `blob-status`. Contact the original uploader or check deployment records for the object ID.

---

## Handling `alreadyCertified` Blobs

If `walrus store` returns `alreadyCertified`, the blob content was previously uploaded.

**Why this happens:**

- Same file uploaded twice (same hash).
- File previously uploaded by someone else.

**Risks:**

- The script cannot verify the blob contains your intended image.
- Could be a hash collision or a different version of the file.
- Blob object ID is not in the `alreadyCertified` response.

**Recovery:**

1. Run `walrus blob-status --blob-id <BLOB_ID> --context mainnet` to get the object ID.
2. Check the blob's certified expiry to plan lifetime extension.
3. If the blob is not yours (owned by another address), you cannot extend it.

---

## Icon URL in Coin Metadata

Once deployed, the icon URL is **immutable on-chain**. It is stored as part of the coin's metadata:

```move
let (builder, treasury_cap) = coin_registry::new_currency_with_otw(
    witness,
    decimals,
    symbol,
    name,
    description,
    icon_url,  // ← updatable post-publish via set_icon_url (MetadataCap-gated)
    ctx,
);
let metadata_cap = builder.finalize(ctx);
// name/symbol/decimals are locked; description + icon URL stay governance-updatable
```

**Implications:**

- If the blob expires and is deleted, the on-chain metadata still references the (now-broken) URL.
- Wallets and aggregators won't display the icon.
- The coin type itself is still valid; only the icon display is broken.
- **Therefore, extend blob lifetime before expiry.**

---

## Troubleshooting

### "Blob object ID is unavailable"

This means the blob was already certified before your deployment (alreadyCertified case).

**Solution:**

```bash
walrus blob-status --blob-id <BLOB_ID> --context mainnet
```

Look for the object ID in the output.

### "walrus: command not found"

Walrus CLI is not installed or not in PATH.

**Solution:**

```bash
curl -fsSL https://get.walrus.xyz/install | sh
# Or consult https://docs.walrus.site for current installation instructions
```

### Icon doesn't load (404)

Blob may have expired or been deleted.

**Check:**

```bash
walrus blob-status --blob-id <BLOB_ID> --context mainnet
```

If certified expiry is in the past, the blob is expired.

**Recover:**

- If you have the original file and know the object ID, you could register a new blob.
- On-chain metadata still points to the old URL (cannot change).
- Best practice: extend blob lifetime before expiry to avoid this.

### Can't extend blob (permission denied)

Blob object is owned by a different address.

**Solution:**

- Only the owner can extend or manage the blob.
- Contact the original uploader if you need to extend.
- For future deployments, ensure you (or your deployment account) own the blob.

---

## Best Practices

1. **Upload early, before mainnet.**
   - Test the aggregator URL in your staging environment.
   - Verify the icon displays correctly in wallets and explorers.

2. **Set long default epochs.**
   - Mainnet: 200 epochs (≈ 7.7 years).
   - Testnet: 50 epochs (≈ 1.3 years).

3. **Monitor expiry.**
   - Set reminders for 50–100 epochs before mainnet expiry.
   - For testnet, 10 epochs is sufficient.

4. **Automate extension.**
   - If managing multiple blobs, script the blob-status check.
   - Extend in batches before threshold is breached.

5. **Document object IDs.**
   - Save the blob object ID in deployment records (scripts/DEPLOYED_ADDRESSES.md).
   - Include blob ID and aggregator URL for reference.

---

## References

- **Walrus Docs:** <https://docs.walrus.site>
- **Deploy Coin Guide:** See IMPLEMENTATION_GUIDE.md, "Mainnet Deployment Workflow," Phase 2.
- **Blob Lifetime Commands:** See README.md, "Blob Lifetime Monitoring" section.
