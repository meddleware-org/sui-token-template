# Coin Template — Implementation Guide

This guide covers the optimal way to use the coin template system for deploying new coins. It emphasizes best practices, decision points, and workflows.

---

## When to Use This Template

### ✅ Use the Template When

1. **You need a new fungible coin type** with immutable on-chain metadata.
   - Example: share token, governance token, stablecoin.

2. **You require permanent, auditable metadata** (name, symbol, decimals, icon).
   - Example: mission-critical financial instruments.

3. **You want to separate coin definition from business logic.**
   - The coin package is minimal and stable.
   - All minting/burning logic lives in the downstream packages that consume the coin type.
   - Easy to audit and reason about.

4. **You plan to delegate coin management to governance.**
   - TreasuryCap can be transferred to a multisig after deployment.
   - Package is locked (`UpgradeCap` burned).
   - No single individual can upgrade or modify the coin.

### ❌ Don't Use the Template When

1. **You need a wrapped/bridge asset** with mutable metadata.
   - Use a dedicated bridge or wrapped asset system instead.

2. **You need multiple coins in a single package.**
   - Create separate package instances, one per coin type.
   - Reason: Type identity binds to package ID; co-locating coins creates coupling.

3. **You need coin-specific business logic in the Move package.**
   - Keep business logic in downstream packages.
   - The template is intentionally minimal.

4. **Your token is temporary or experimental.**
   - The coin is immutable after deployment; changing it requires a new package.
   - Ensure you're committed to the parameters before deploying.

---

## Pre-Deployment Checklist

Before running `deploy_token.sh`, complete this checklist:

### ☐ Parameters Finalized

- [ ] **TOKEN_SYMBOL** — Ticker symbol (typically 3–6 chars, e.g., `"MYTOKEN"`).
  - Cannot change after mainnet deployment.
  - Appears in wallets and exchanges.

- [ ] **TOKEN_NAME** — Full display name (e.g., `"MYTOKEN"`).
  - Cannot change after mainnet deployment.
  - Often the same as symbol, but can be longer.

- [ ] **TOKEN_DESCRIPTION** — Human-readable description (e.g., `"Example token for the myTOKEN project"`).
  - Cannot change after mainnet deployment.
  - Visible in explorers and wallets.

- [ ] **TOKEN_DECIMALS** — Precision (typically 6, 8, or 9).
  - Cannot change after mainnet deployment.
  - Example: 9 (nanoSUI scale, matching native SUI), 6 (USDC scale).
  - Formula: 1 coin = 10^(-DECIMALS) base units.
  - **Most common:** 9 (for Sui-native assets), 6 (for traditional assets).

- [ ] **TOKEN_IMAGE_PATH** — Path to a PNG or SVG icon.
  - Recommended size: 100×100 or 256×256 pixels.
  - Keep file size small (< 1 MB).
  - Will be uploaded to Walrus and immutable thereafter.

### ☐ Governance & Keys

- [ ] **TREASURY_ADDRESS** — Governance multisig address.
  - TreasuryCap will be transferred here after deployment.
  - Should be a multisig, not a single keypair.
  - Cannot change after deployment (would require a new coin).
  - Format check: `0x` + 64 hex characters (use the script's format check).

- [ ] **Active Sui Address** has sufficient balance.
  - Mainnet: ~2–5 SUI (for all deployment transactions).
  - Testnet: ~1 SUI (lower gas).
  - Check: `sui client balance --json | jq '.[] | select(.coinType == "0x2::sui::SUI") | .totalBalance'`.

- [ ] **Active Sui Address** is the deployment account.
  - Confirm: `sui client active-address`.
  - This address will initially own the TreasuryCap (transferred in Phase 7).

### ☐ Network Decision

- [ ] **NETWORK** is set correctly.
  - `"testnet"` — For trial deployments (lower gas, can republish with new package ID).
  - `"mainnet"` — For production (higher gas, package is permanent).
  - **Best practice:** Test on testnet first, even if you plan mainnet deployment.

### ☐ Downstream Integration

- [ ] **Downstream packages** that consume the coin type are aware of it.
  - They should reference: `<PACKAGE_ID>::<TOKEN_MODULE_NAME>::<TOKEN_STRUCT_NAME>`.
  - After deployment, update their `Move.toml` [addresses] with the published package ID.

- [ ] **Frontend environment files** (.env.mainnet, .env.testnet) are prepared.
  - Will be updated with the coin type (e.g. `VITE_COIN_TYPE`) after deployment.

---

## Workflow: Testnet Trial Run

**Goal:** Deploy on testnet first to verify parameters and tooling. No cost to republish if issues arise.

### Step 1: Prepare Parameters

```bash
# Set env vars (example values)
export TOKEN_PACKAGE_NAME="my_token"
export TOKEN_MODULE_NAME="mytoken"
export TOKEN_STRUCT_NAME="MYTOKEN"
export TOKEN_SYMBOL="MYTOKEN"
export TOKEN_NAME="MYTOKEN"
export TOKEN_DESCRIPTION="Example token for the myTOKEN project"
export TOKEN_DECIMALS="9"
export TOKEN_IMAGE_PATH="assets/img/mytoken.png"
export OUTPUT_DIR="my_token"
export TREASURY_ADDRESS="0x<your-testnet-multisig>"
export NETWORK="testnet"
```

### Step 2: Verify Tooling

```bash
# Check all required tools are available
walrus --version
sui --version
jq --version

# Verify Sui is configured for testnet
sui client active-env  # Should show "testnet"
sui client active-address  # Should show a testnet address
sui client balance  # Should show SUI balance (need ~1 SUI)
```

### Step 3: Run Deployment

```bash
bash scripts/deploy_token.sh
```

The script will guide you through each phase. Read the output carefully:

- **Phase 1 (Preflight):** Validates parameters and balance.
- **Phase 2 (Walrus):** Uploads image; prompts for confirmation.
- **Phase 3 (Generate):** Creates coin package.
- **Phase 4 (Build & Test):** Compiles and runs tests.
- **Phase 5 (Confirmation):** Prints summary; requires `CONFIRM`.
- **Phase 6 (Publish):** Publishes to testnet; captures package ID.
- **Phase 7 (Transfer):** Transfers TreasuryCap to treasury address.
- **Phase 8 (Summary):** Prints all IDs and next steps.

### Step 4: Record Testnet IDs

At the end, save the output:

```bash
# From Phase 8 output, record:
TESTNET_PACKAGE_ID="0x..."
TESTNET_TREASURY_CAP_ID="0x..."
TESTNET_BLOB_ID="..."
TESTNET_BLOB_URL="https://aggregator.walrus-testnet.walrus.space/v1/blobs/..."
```

### Step 5: Verify On-Chain

```bash
# Check package exists
sui client object $TESTNET_PACKAGE_ID

# Check TreasuryCap ownership
sui client objects $TREASURY_ADDRESS | grep -i treasurycap

# Check icon URL resolves
curl -I $TESTNET_BLOB_URL  # Should return 200
```

> **Note — `suix_getCoinMetadata` returns null for coin_registry coins.**
>
> Coins generated from this template use `coin_registry::new_currency_with_otw` +
> `finalize` (retaining a `MetadataCap`). This pattern stores metadata inside the Sui coin
> registry's internal system object, NOT as a standalone `CoinMetadata` object. As a
> result, `suix_getCoinMetadata` correctly returns null — this is expected and intentional.
>
> Wallets and explorers that support the Sui coin registry resolve the metadata (symbol,
> name, decimals, icon) directly from that system state without requiring a `CoinMetadata`
> object. The `sui client object <PACKAGE_ID>` command above is the correct way to confirm
> the package is on-chain and immutable.

### Step 6: Test Integration

Update any downstream packages or frontend to use the testnet package ID, and run your integration tests:

```bash
# Example: update a downstream package to use the new coin
# ... edit its Move.toml [addresses] ...
# ... run integration tests ...
```

### Step 7: Iterate or Move to Mainnet

- **Issues found?** Fix parameters, run `deploy_token.sh` again (new package ID).
- **All good?** Proceed to mainnet deployment below.

---

## Workflow: Mainnet Deployment

**Goal:** Deploy to mainnet with parameters finalized, tested, and approved.

### Prerequisite: Testnet Success

Complete the testnet trial run above. Ensure:

- All parameters are correct.
- Integration tests pass.
- Icon displays correctly.
- Governance multisig is ready to receive TreasuryCap.

### Step 1: Prepare Mainnet Parameters

```bash
export TOKEN_PACKAGE_NAME="my_token"
export TOKEN_MODULE_NAME="mytoken"
export TOKEN_STRUCT_NAME="MYTOKEN"
export TOKEN_SYMBOL="MYTOKEN"
export TOKEN_NAME="MYTOKEN"
export TOKEN_DESCRIPTION="Example token for the myTOKEN project"
export TOKEN_DECIMALS="9"
export TOKEN_IMAGE_PATH="assets/img/mytoken.png"
export OUTPUT_DIR="my_token"
export TREASURY_ADDRESS="0x<mainnet-governance-multisig>"  # ← MAINNET address
export NETWORK="mainnet"  # ← MAINNET
```

### Step 2: Verify Mainnet Readiness

```bash
# Switch to mainnet
sui client switch --env mainnet
sui client active-env  # Should show "mainnet"

# Verify balance (need ~5 SUI for deployment)
sui client balance

# Verify governance multisig exists on mainnet
sui client addresses | grep <TREASURY_ADDRESS>
```

### Step 3: Run Mainnet Deployment

```bash
bash scripts/deploy_token.sh
```

**⚠️ Critical:** This transaction is irreversible. The script will:

- Ask for `CONFIRM` before publishing.
- Publish once and only once per run.
- Transfer TreasuryCap to governance.

Read all prompts carefully and confirm you understand the parameters before typing `CONFIRM`.

### Step 4: Record Deployment Artefacts

From Phase 8 output, record all values in `deployments.md` at the repository root:

- Package ID
- TreasuryCap ID
- Blob ID
- Blob Object ID
- Blob URL
- Deployer Address
- Treasury Address
- Deployment timestamp

See `deployments.md` for the template and instructions.

### Step 5: Update Downstream Packages

#### Move Packages

Update the downstream package's `Move.toml`:

```toml
[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", ... }
CoinTemplate = { local = "../my_token" }  # Or reference by package ID if separate

[addresses]
mytoken = "0x<MAINNET_PACKAGE_ID>"  # The deployed package ID
```

#### Frontend

Update your frontend's `.env.mainnet`:

```env
VITE_COIN_TYPE=0x<MAINNET_PACKAGE_ID>::mytoken::MYTOKEN
```

### Step 6: Deploy & Verify

Deploy any downstream packages and frontend that consume the coin type:

```bash
cd <downstream_package> && sui move build && sui client publish --gas-budget 500000000
cd <your-frontend> && yarn build
```

After deployment, verify on-chain:

```bash
# Sui Explorer: https://explorer.sui.io/object/<MAINNET_PACKAGE_ID>
# Coin metadata should show: symbol, name, description, icon URL

# Verify TreasuryCap at governance address
sui client objects --address 0x<TREASURY_ADDRESS> | grep TreasuryCap
```

---

## Scenario: Updating Icon URL Before Mainnet

If you want to deploy to mainnet but need to update the icon URL first, regenerate the coin package:

### Step 1: Upload New Image to Walrus

Use `deploy_token.sh` to upload, or manually:

```bash
walrus --context mainnet store --json --epochs 200 "assets/img/new_icon.png"
# Extract BLOB_ID from output
BLOB_ID="..."
BLOB_URL="https://aggregator.walrus.space/v1/blobs/$BLOB_ID"
```

### Step 2: Regenerate Package with New Icon

```bash
TOKEN_ICON_URL="$BLOB_URL" \
TOKEN_PACKAGE_NAME="my_token" \
... (other vars) \
bash scripts/03_create_token.sh --output-dir my_token
```

### Step 3: Review & Commit

```bash
git diff my_token
git add my_token && git commit -m "Update my_token icon URL before mainnet publish"
```

### Step 4: Proceed with Mainnet Deployment

The generated package now has the new icon URL. Deploy as above.

---

## Decision Tree: Testnet vs Mainnet

```text
Do you have finalized parameters and tested integration?
├─ NO  → Use testnet (try, iterate, scrap, retry)
│        (Package ID will change each time; no cost to redeploy)
│        
└─ YES → Ready for mainnet
         Do you have governance multisig approval?
         ├─ NO  → Wait. Coin parameters are immutable after deploy.
         │        
         └─ YES → Deploy to mainnet
                  Record package ID, update downstream, verify on-chain
```

---

## Common Mistakes & Prevention

### Mistake 1: Deploying Without Testnet Trial

**Problem:** Parameters are wrong; coin is now immutable on mainnet.

**Prevention:**

- Always deploy to testnet first.
- Verify all on-chain metadata.
- Run integration tests.

### Mistake 2: Wrong Treasury Address

**Problem:** TreasuryCap goes to the wrong multisig; governance can't use it.

**Prevention:**

- Verify TREASURY_ADDRESS format before running the script (0x + 64 hex).
- Double-check the multisig address with the governance team.
- The script prints it before requiring CONFIRM.

### Mistake 3: Insufficient Gas Balance

**Problem:** Deployment fails midway through publish.

**Prevention:**

- Check balance before starting: `sui client balance`.
- Mainnet: ensure ≥ 5 SUI.
- Testnet: ensure ≥ 1 SUI.

### Mistake 4: Image Too Large or Unsupported Format

**Problem:** Walrus upload fails.

**Prevention:**

- Use PNG or SVG (standard formats).
- Keep file size < 1 MB (< 100 KB preferred).
- Test: `file assets/img/mytoken.png`.

### Mistake 5: Network Mismatch

**Problem:** Parameters are for testnet, but NETWORK=mainnet (or vice versa).

**Prevention:**

- Verify `sui client active-env` matches NETWORK.
- Verify TREASURY_ADDRESS is correct for the network.
- The script prints configuration before CONFIRM.

### Mistake 6: Forgetting to Update Downstream Packages

**Problem:** a downstream package still references the old package ID; build fails.

**Prevention:**

- After mainnet deployment, immediately update `Move.toml` and `.env.mainnet`.
- Run `sui move build` to verify dependencies resolve.
- Check git diff to ensure all references updated.

### Mistake 7: Expecting `suix_getCoinMetadata` to return data for coin_registry coins

**Problem:** After deployment, `suix_getCoinMetadata` returns null, causing false alarm
that the deployment failed or metadata is missing.

**Root cause:** This template uses `coin_registry::new_currency_with_otw`, not
`coin::create_currency`. The coin registry pattern does not produce a standalone
`CoinMetadata` object. Metadata is stored inside the Sui coin registry's internal system
object. `suix_getCoinMetadata` relies on a `CoinMetadata` object existing, so it always
returns null for coins generated by this template.

**This is correct behaviour.** The coin is deployed correctly. Wallets and the Sui coin
registry resolve metadata without a `CoinMetadata` object.

**Prevention:**

- Verify deployment using `sui client object <PACKAGE_ID>` (package on-chain and immutable)
  and `sui client objects <TREASURY_ADDRESS> | grep -i treasurycap` (TreasuryCap at governance).
- Do not use `suix_getCoinMetadata` as a verification step for coins from this template.

---

## Best Practices

### 1. Use `deploy_token.sh` for Full Deployments

It automates Walrus upload, package generation, testing, publishing, and TreasuryCap transfer. Less error-prone than manual steps.

**Only use `03_create_token.sh` if:**

- You already have a Walrus blob URL.
- You're regenerating a package for manual publishing.

### 2. Version Your Deployed Coins

Keep a record in `scripts/DEPLOYED_ADDRESSES.md`:

```markdown
| Component | Testnet | Mainnet |
|---|---|---|
| my_token | 0x... (date) | 0x... (date) |
| downstream_package | 0x... | 0x... |
```

### 3. Never Change Generated Instances Manually

The concrete packages (e.g., `my_token/`) are generated artifacts. Regenerate them with `03_create_token.sh` or `deploy_token.sh` rather than editing by hand.

**Exception:** Small comments or documentation. Never change code (module declarations, struct names, placeholders).

### 4. Test Blob Lifetime Before Mainnet Expiry

Walrus blobs have expiry epochs. Monitor and extend (requires blob object ID, not content ID):

```bash
# Look up blob object ID if needed (from Phase 2 or blob status):
walrus blob-status --blob-id <blob-id> --context mainnet

# If fewer than 50 epochs remain, extend:
walrus extend --blob-obj-id <blob-object-id> --epochs-extended 200 --context mainnet
```

### 5. Document the Coin for Future Maintainers

In your project or app README, note:

- **Package ID:** Where to find it.
- **Type:** Full path (`0x...::module::Struct`).
- **Icon source:** Walrus blob ID (for lifetime monitoring).
- **Governance:** Who owns the TreasuryCap, how to update if needed.

Example:

```markdown
## MYTOKEN Coin

- **Package ID:** 0xABC123... (mainnet)
- **Type:** 0xABC123::mytoken::MYTOKEN
- **Icon (Walrus):** 4BKcDC0Ih5RJ8R0tFMz3MZVNZV8b2goT6_JiEEwNHQo
- **Icon Extension:** Monitor epochs via `walrus blob-status`; extend when < 50 epochs remain.
- **Governance:** TreasuryCap owned by `0xd1b80...` (governance multisig)
```

---

## Recovery Scenarios

### Scenario: TreasuryCap Transfer Failed After Publish

**Symptom:** Phase 6 (publish) succeeded; Phase 7 (transfer) failed with error.

**Script Output:**

```text
ERROR: TreasuryCap transfer FAILED.
TreasuryCap object ID: 0x<ID>
Manual recovery:
  sui client transfer --object-id 0x<ID> \
    --to 0x<TREASURY_ADDRESS> --gas-budget 10000000
```

**Action:**

1. Copy and run the manual recovery command.
2. Verify transfer succeeded: `sui client objects --address 0x<TREASURY_ADDRESS>`.
3. Record the deployment artefacts in `deployments.md` with the package ID from Phase 6 output.

### Scenario: Package ID Parse Error

**Symptom:** Phase 6 (publish) appeared to succeed, but script couldn't parse package ID.

**Root cause:** Unusual publish output format (rare).

**Action:**

1. Check `sui client recent-transactions --limit 1` for the transaction digest.
2. Look up the transaction on Sui Explorer to find the package ID manually.
3. Retry TreasuryCap transfer (see above).

### Scenario: Walrus Upload Failed

**Symptom:** Phase 2 exits with walrus CLI error.

**Common causes:**

- Walrus CLI not installed or not in PATH.
- Image file is corrupted or too large.
- Network connectivity issue.

**Action:**

1. Fix the underlying cause (install walrus, check image, verify network).
2. Rerun `deploy_token.sh` from the beginning (Phase 1 preflight).
3. Script is idempotent: later phases will republish if earlier phases' artifacts are missing.

---

## Related Files

- **README.md** — Feature overview and detailed reference.
- **deployments.md** — Post-deployment artefact recording template.
- **sources/sui_token_template.move** — Template source code.
- **scripts/03_create_token.sh** — Generator script (called by deploy_token.sh).
- **scripts/deploy_token.sh** — Full deployment pipeline.

---

## Questions & Support

### "Can I change parameters after deployment?"

No. The coin's metadata is immutable on-chain by design. If you need different parameters, deploy a new coin package (new package ID, start from scratch).

### "What if I make a typo in the symbol?"

Unfortunately, that typo is permanent. The symbol is immutable on-chain. This is why the checklist and testnet trial are important.

### "Can I reuse the same icon URL for two different coins?"

Yes. Multiple coins can reference the same Walrus blob. But blob lifetime is shared—if you extend one, both benefit.

### "What happens if the blob expires?"

The blob is no longer retrievable. The coin's metadata still references the URL (unchanged), but the icon won't display. Extend the blob before expiry to prevent this.

### "Do I need to update the downstream packages?"

Only if a downstream package needs to know about the new coin type. Reference the coin type via its package ID in the Move.toml and downstream code.

---

## License

This guide is CC0 (public domain). Adapt and share freely.
