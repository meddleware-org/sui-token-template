# SUI Token Template — Generic Sui Token Package Generator

This folder contains a **generic Sui token package template** and a suite of scripts to generate concrete token instances for deployment.

The template itself is never deployed directly. Instead, you use the generator scripts to create production-ready token packages with token-specific values (symbol, name, decimals, icon URL) embedded in the source code.

---

## Quick Start

### 1. Generate a Token Package

Use `scripts/03_create_token.sh` to generate a concrete token package from the template:

```bash
TOKEN_PACKAGE_NAME=my_token \
TOKEN_MODULE_NAME=mytoken \
TOKEN_STRUCT_NAME=MYTOKEN \
TOKEN_SYMBOL="myTOKEN" \
TOKEN_NAME="myTOKEN" \
TOKEN_DESCRIPTION="Example token for the myTOKEN project" \
TOKEN_DECIMALS="9" \
TOKEN_ICON_URL="https://aggregator.walrus.space/v1/blobs/<blob-id>" \
bash scripts/03_create_token.sh --output-dir my_token
```

This creates `my_token/` with a ready-to-build Move package.

### 2. Full Deployment (with Walrus Upload)

Use `scripts/deploy_token.sh` for a complete, interactive deployment pipeline:

```bash
TOKEN_PACKAGE_NAME=my_token \
TOKEN_MODULE_NAME=mytoken \
TOKEN_STRUCT_NAME=MYTOKEN \
TOKEN_SYMBOL="myTOKEN" \
TOKEN_NAME="myTOKEN" \
TOKEN_DESCRIPTION="Example token for the myTOKEN project" \
TOKEN_DECIMALS="9" \
TOKEN_IMAGE_PATH="assets/img/mytoken.png" \
OUTPUT_DIR="my_token" \
TREASURY_ADDRESS="0xd1b80100f67d6ef4e696bb2bef234a89e89e2b4789eb91e8d5493712fd15197e" \
NETWORK="mainnet" \
bash scripts/deploy_token.sh
```

This automatically:

- Uploads your image to Walrus
- Generates the token package with the Walrus icon URL
- Tests and builds locally
- Publishes to mainnet
- Transfers the `TreasuryCap` to your governance multisig

---

## Architecture

```text

├── Move.toml                  # Template manifest
├── sources/
│   └── sui_token_template.move     # Template source with inline tests and placeholders
├── scripts/
│   ├── 03_create_token.sh         # Generator: template → concrete instance
│   ├── deploy_token.sh         # Full deployment pipeline
│   └── publish.sh             # Simple build + publish wrapper
└── README.md                  # This file
```

### Design Philosophy

The template uses **placeholder values** (buildable, not sentinels):

- `sui_token_template` — generic module/package name (valid Move identifier)
- `SUI_TOKEN_TEMPLATE` — generic struct name
- `0u8` — decimals placeholder
- `b"TEMPLATE"` — string placeholders (symbol, name, description, icon URL)

All placeholder values are **valid, compilable code**. The template can be built and tested as-is without requiring substitution. This ensures:

1. The template is always in a working state.
2. The generator's substitution logic is simple and auditable.
3. Concrete instances inherit the template's test coverage.

---

## Generated Token Instances

When you run `03_create_token.sh` or `deploy_token.sh`, a concrete token instance is created in the output directory. Example: `my_token/`.

### Structure of a Concrete Instance

```text
my_token/
├── Move.toml
├── sources/
│   └── mytoken.move                # Concrete: all placeholders substituted
├── scripts/
│   └── publish.sh                 # Simple build + publish wrapper
└── build/                         # Compiled bytecode
```

### Key Differences from Template

| Aspect | Template | Concrete Instance |
| --- | --- | --- |
| Module name | `sui_token_template::sui_token_template` | `<TOKEN_PACKAGE_NAME>::<TOKEN_MODULE_NAME>` |
| Struct name | `SUI_TOKEN_TEMPLATE` | `<TOKEN_STRUCT_NAME>` |
| Decimals | `0u8` | Actual value (e.g., `9`) |
| Symbol | `b"TEMPLATE"` | Actual value (e.g., `b"myTOKEN"`) |
| Icon URL | `b"TEMPLATE"` | Actual Walrus blob URL |
| Committed | ❌ Never deployed | ✅ Committed to git |
| Modified by user | ❌ Template unchanged | ✅ May be manually edited |

---

## Scripts Overview

### `scripts/03_create_token.sh` — Generator

**Purpose:** Transform the template into a concrete token package with token-specific values.

**Required env vars (all must be non-empty):**

```bash
TOKEN_PACKAGE_NAME         # Sui package name, e.g. "my_token"
TOKEN_MODULE_NAME          # Move module name, e.g. "mytoken"
TOKEN_STRUCT_NAME          # Type witness struct name, e.g. "MYTOKEN"
TOKEN_SYMBOL               # Ticker symbol, e.g. "myTOKEN"
TOKEN_NAME                 # Full token name, e.g. "myTOKEN"
TOKEN_DESCRIPTION          # Human-readable description
TOKEN_DECIMALS             # Precision: usually 9 (nanoSUI scale) or 6 (USDC scale)
TOKEN_ICON_URL             # Walrus blob URL or empty string (can be set later)
```

**Required flag:**

```bash
--output-dir <path>       # Where to write the generated package
```

**Behavior:**

1. Validates all 8 env vars are set and non-empty (using bash `${VAR:?msg}` expansion).
2. Creates output directory and subdirectories.
3. Copies template `Move.toml` and `sources/sui_token_template.move` to output.
4. Performs sed-based substitutions (template unchanged):
   - Module path: `sui_token_template::sui_token_template` → `$TOKEN_PACKAGE_NAME::$TOKEN_MODULE_NAME`
   - Struct: `SUI_TOKEN_TEMPLATE` → `$TOKEN_STRUCT_NAME`
   - Decimals: `0u8` → `$TOKEN_DECIMALS`
   - Strings: `b"TEMPLATE"` → `b"$TOKEN_SYMBOL"`, etc. (4 occurrences in order)
5. Renames `sui_token_template.move` → `$TOKEN_MODULE_NAME.move`.
6. Validates no `sui_token_template` identifier remains (catches incomplete substitution).
7. Prints summary and ready-to-publish reminder.

**Exit codes:**

- `0` — Success
- `1` — Missing env var, missing template file, or substitution validation failed

**Example:**

```bash
TOKEN_PACKAGE_NAME=my_token \
TOKEN_MODULE_NAME=mytoken \
TOKEN_STRUCT_NAME=MYTOKEN \
TOKEN_SYMBOL="myTOKEN" \
TOKEN_NAME="myTOKEN" \
TOKEN_DESCRIPTION="Example token for the myTOKEN project" \
TOKEN_DECIMALS="9" \
TOKEN_ICON_URL="" \
bash scripts/03_create_token.sh \
  --output-dir my_token
```

**Idempotency:** Running the script multiple times with the same output directory overwrites the previous instance. This is the intended workflow for updating a token instance (e.g., to set the icon URL before mainnet deployment).

---

### `scripts/deploy_token.sh` — Full Deployment Pipeline

**Purpose:** Complete end-to-end deployment: upload image to Walrus, generate package, build, publish, and transfer TreasuryCap to governance.

**Required env vars (all must be non-empty):**

```bash
# Same as 03_create_token.sh:
TOKEN_PACKAGE_NAME
TOKEN_MODULE_NAME
TOKEN_STRUCT_NAME
TOKEN_SYMBOL
TOKEN_NAME
TOKEN_DESCRIPTION
TOKEN_DECIMALS

# Additional (deploy-specific):
TOKEN_IMAGE_PATH           # Local path to image (e.g., "assets/img/mytoken.png")
OUTPUT_DIR                # Where to generate the package
TREASURY_ADDRESS          # Governance multisig (0x + 64 hex chars)
NETWORK                   # "testnet" or "mainnet"
```

**Behavior:**

The script runs 8 phases, each with clear output and error handling:

#### Phase 1: Preflight

- Validates all env vars (non-empty).
- Checks required tools: `walrus`, `sui`, `jq`.
- Derives deployer address from `sui client active-address`.
- Validates NETWORK is exactly "testnet" or "mainnet".
- Verifies image file exists.
- Validates TREASURY_ADDRESS format (0x + 64 hex chars).
- Checks SUI balance; warns (does not abort) if < 1 SUI.
- Prints configuration summary.

#### Phase 2: Walrus Upload

- Sets epoch count: 50 (testnet), 200 (mainnet).
- Runs `walrus --context $NETWORK store --json --epochs $EPOCHS $TOKEN_IMAGE_PATH`.
- Parses blob ID and object ID from JSON.
- **Special handling for `alreadyCertified`:** Warns user that blob already existed (unknown content), prompts for re-confirmation before continuing.
- Prints blob URL; user must verify it resolves before proceeding.
- Interactive gate: `read -rp "Press Enter to continue, or Ctrl-C to abort: "`.

#### Phase 3: Generate Package

- Calls `03_create_token.sh` with derived WALRUS blob URL as `TOKEN_ICON_URL`.
- Aborts if generation fails.

#### Phase 4: Build and Test

- Runs `sui move test --path "$OUTPUT_DIR"`.
- Runs `sui move build --path "$OUTPUT_DIR"`.
- Aborts on any failure.

#### Phase 5: Pre-Publish Confirmation

- Prints full deployment summary (network, package name, symbol, description, decimals, icon URL, addresses).
- Requires user type `CONFIRM` exactly.
- Aborts if anything else is typed.

#### Phase 6: Publish

- Runs `sui client publish "$OUTPUT_DIR" --gas-budget 100000000 --json`.
- Parses package ID and TreasuryCap object ID from JSON output.
- Aborts if either cannot be parsed.

#### Phase 7: Transfer TreasuryCap

- Runs `sui client transfer --object-id $TREASURY_CAP_ID --to $TREASURY_ADDRESS --gas-budget 10000000`.
- **Critical error handling:** If transfer fails after successful publish, prints:
  - Error message
  - TreasuryCap object ID
  - Exact manual recovery command
  - User can run the command themselves without re-publishing

#### Phase 8: Summary

- Prints all key values: package ID, TreasuryCap ID, blob ID, blob URL, addresses.
- Prints next steps:
  1. **Record the artefact IDs** in `deployments.md`
  2. Update downstream Move.toml [addresses] entries
  3. Verify metadata on Sui explorer
  4. Set up blob lifetime monitoring
- **Special note for `alreadyCertified` blobs:** Provides `walrus blob-status` command to retrieve object ID manually.
- Prints epoch extension thresholds (10 epochs testnet, 50 epochs mainnet).

**Exit codes:**

- `0` — Success
- `1` — Any phase fails (with recovery instructions if post-publish)

**Example:**

```bash
TOKEN_PACKAGE_NAME=my_token \
TOKEN_MODULE_NAME=mytoken \
TOKEN_STRUCT_NAME=MYTOKEN \
TOKEN_SYMBOL="myTOKEN" \
TOKEN_NAME="myTOKEN" \
TOKEN_DESCRIPTION="Example token for the myTOKEN project" \
TOKEN_DECIMALS="9" \
TOKEN_IMAGE_PATH="assets/img/mytoken.png" \
OUTPUT_DIR="my_token" \
TREASURY_ADDRESS="0xd1b80100f67d6ef4e696bb2bef234a89e89e2b4789eb91e8d5493712fd15197e" \
NETWORK="mainnet" \
bash scripts/deploy_token.sh
```

---

## Template Source (`sources/sui_token_template.move`)

### Structure

The template uses the **one-time-witness (OTW) pattern** for type identity and the Sui coin registry for immutable metadata:

```move
module sui_token_template::sui_token_template;

use sui::coin::TreasuryCap;
use sui::coin_registry::{Self, Currency, MetadataCap};

// Type witness: zero-sized struct with drop ability only.
// Consumed once in init(); burned by the coin registry.
public struct SUI_TOKEN_TEMPLATE has drop {}

fun init(witness: SUI_TOKEN_TEMPLATE, ctx: &mut TxContext) {
    // Register token with the coin registry; returns a Currency builder and TreasuryCap.
    let (builder, treasury_cap) = coin_registry::new_currency_with_otw(
        witness,
        0u8,                           // decimals placeholder
        b"TEMPLATE".to_string(),       // symbol placeholder
        b"TEMPLATE".to_string(),       // name placeholder
        b"TEMPLATE".to_string(),       // description placeholder
        b"TEMPLATE".to_string(),       // icon URL placeholder
        ctx,
    );

    // finalize() (NOT finalize_and_delete_metadata_cap): name/symbol/decimals stay
    // immutable, but description + icon remain governance-updatable via the MetadataCap.
    let metadata_cap = builder.finalize(ctx);

    // Transfer both the TreasuryCap and the MetadataCap to the deployer.
    transfer::public_transfer(treasury_cap, ctx.sender());
    transfer::public_transfer(metadata_cap, ctx.sender());
}

// Test helpers...
```

### Key Design Decisions

#### 1. Immutable Metadata by Design

After `init()` completes, the `MetadataCap` is deleted. **No one can ever change the token's name, symbol, decimals, or icon URL on-chain.** This is intentional:

- The token is a trust anchor for the project that uses it.
- Upgradable metadata creates governance overhead and audit risk.
- Off-chain systems (UI, data aggregators) manage icon/metadata display.

#### 2. One-Time Witness Pattern

The `SUI_TOKEN_TEMPLATE` struct is a **type witness** — a zero-sized struct that encodes type identity at compile time. It:

- Can only be instantiated when the package is published (`init()`).
- Can only be used once (has `drop` ability only).
- Binds the token type to this specific package ID.
- Prevents unauthorized minting (no other package can create `SUI_TOKEN_TEMPLATE`).

#### 3. Placeholder Values

All metadata fields use buildable, compilable placeholder values:

- **Decimals:** `0u8` (valid integer literal)
- **Symbol, name, description, icon:** `b"TEMPLATE"` (valid byte string)

This ensures:

- The template compiles and passes tests as-is.
- Substitution is simple string replacement, not parsing or macro expansion.
- Each concrete instance inherits the template's test coverage.

#### 4. No Business Logic

The package contains only the token type definition and initialization. All financial logic (minting, burning, transfers, accounting) belongs in the downstream packages that consume the coin type. This keeps the token type minimal, auditable, and stable.

---

## Example Deployment (Case Study)

A worked example of generating and deploying a `my_token` instance from this template.

### Deployment History

1. **Initial generation (testnet):**

   ```bash
   TOKEN_PACKAGE_NAME=my_token TOKEN_MODULE_NAME=mytoken TOKEN_STRUCT_NAME=MYTOKEN \
   TOKEN_SYMBOL="MYTOKEN" TOKEN_NAME="MYTOKEN" \
   TOKEN_DESCRIPTION="Example token for the myTOKEN project" \
   TOKEN_DECIMALS="9" TOKEN_ICON_URL="" \
   bash scripts/03_create_token.sh --output-dir my_token
   ```

2. **Committed to git:** `my_token/` is a committed, immutable artifact.

3. **Icon URL update (before mainnet):**

   ```bash
   TOKEN_ICON_URL="https://aggregator.walrus.space/v1/blobs/<blob-id>" \
   ... bash scripts/03_create_token.sh --output-dir my_token
   git diff my_token  # Review changes
   git add my_token && git commit
   ```

4. **Mainnet publication:** Simple publish via `scripts/publish.sh` or `deploy_token.sh`.

---

## Workflow: Creating a New Token

### Scenario: You need to deploy a new ERC-20-like token (8 decimals, custom symbol)

#### Step 1: Create the image asset

Place your token icon at `assets/img/mytoken.png`.

#### Step 2: Prepare env vars

```bash
export TOKEN_PACKAGE_NAME="mytoken_token"
export TOKEN_MODULE_NAME="mytoken"
export TOKEN_STRUCT_NAME="MYTOKEN"
export TOKEN_SYMBOL="MYTOKEN"
export TOKEN_NAME="My Token"
export TOKEN_DESCRIPTION="A custom ERC-20 equivalent on Sui"
export TOKEN_DECIMALS="8"
export TOKEN_IMAGE_PATH="assets/img/mytoken.png"
export OUTPUT_DIR="blockchain/sui/mytoken_token"
export TREASURY_ADDRESS="0x<governance-multisig>"
export NETWORK="mainnet"  # or "testnet" for testing
```

#### Step 3: Full deployment

```bash
bash scripts/deploy_token.sh
```

The script will:

1. Upload your image to Walrus (either testnet or mainnet, depending on NETWORK).
2. Generate the token package with the Walrus blob URL.
3. Test and build.
4. Publish to the active Sui network.
5. Transfer the TreasuryCap to your governance multisig.

#### Step 4: Record the package ID

The summary at the end prints the package ID. Store it in `scripts/DEPLOYED_ADDRESSES.md` and any frontend `.env.testnet` / `.env.mainnet` files that reference this token.

#### Step 5: Verify on-chain

Visit [Sui Explorer](https://explorer.sui.io) and search for your package ID. Confirm:

- Token type: `<PACKAGE_ID>::mytoken::MYTOKEN`
- Name, symbol, decimals are correct
- Icon URL resolves

---

## Wallet-Level Integration

### Adding the Token to a Wallet

Once deployed, wallets can recognize your token type using:

```text
<PACKAGE_ID>::<MODULE_NAME>::<STRUCT_NAME>

Example: 0xABC123::mytoken::MYTOKEN
```

Wallets fetch on-chain metadata from `sui::coin::CoinMetadata<T>`:

- Symbol
- Name
- Decimals
- (Icon URL, if set)

### Icon/Off-Chain Metadata

The icon URL is **immutable on-chain**, so choose it carefully before mainnet deployment:

- **Walrus blob URL** (recommended): Points to a permanent, decentralized blob.
  - Format: `https://aggregator.walrus.space/v1/blobs/<blob-id>` (mainnet)
  - Format: `https://aggregator.walrus-testnet.walrus.space/v1/blobs/<blob-id>` (testnet)
- **Empty string** (default): Icon is managed off-chain (e.g., by the frontend or a data aggregator).

**Best practice:** Use `deploy_token.sh` to upload the image to Walrus automatically, ensuring you get the canonical URL before publishing.

---

## Testing

### Unit Tests (Included)

The template includes four test functions that verify:

1. `test_treasury_cap_transferred_to_sender` — TreasuryCap is owned by the deployer after `init()`.
2. `test_treasury_cap_present_in_sender` — TreasuryCap is present after `init()`.
3. `test_metadata_cap_present_in_sender` — MetadataCap is present after `init()` (metadata stays governance-updatable).
4. `test_currency_transferred_to_registry_after_init` — Currency is transferred to the registry address, pending `finalize_registration`.

**Run template tests:**

```bash
sui move test --path $OUTPUT_DIR
```

**Run concrete instance tests:**

```bash
sui move test --path my_token
```

### Integration Testing

The `deploy_token.sh` script includes `sui move test` as Phase 4, so generated instances are tested before publishing.

### Manual Verification

After deployment, verify on-chain:

1. **Package exists:**

   ```bash
   sui client object <PACKAGE_ID>
   ```

2. **Token metadata is correct:**

   ```bash
   sui client call \
     --package 0x2 \
     --module coin \
     --function coin_metadata \
     --args 0xc3d92b63efdcb7e44c7798bfc3f2f1aacf9a6e4d5c8b8e9a2d3f4e5c6b7a8d9  # Example CoinMetadata object ID
   ```

3. **TreasuryCap is at treasury address:**

   ```bash
   sui client objects --address <TREASURY_ADDRESS>
   ```

4. **Icon URL resolves:**
   Open the blob URL in a browser to confirm it displays correctly.

---

## Troubleshooting

### "TOKEN_IMAGE_PATH does not exist"

**Problem:** `deploy_token.sh` can't find your image.

**Solution:** Verify the file exists and path is correct (relative to your working directory, usually the repo root):

```bash
ls -l assets/img/mytoken.png
```

### "walrus: command not found"

**Problem:** Walrus CLI is not installed or not in PATH.

**Solution:** Install walrus:

```bash
# See https://github.com/MystenLabs/walrus-docs for current instructions
# Typically: curl -fsSL https://...walrus-install.sh | sh
```

### "TREASURY_ADDRESS ... is not a valid Sui address"

**Problem:** Address format is invalid.

**Solution:** Ensure it's exactly 66 characters (`0x` + 64 hex chars):

```bash
echo "${#TREASURY_ADDRESS}"  # Should print 66
```

### "Package was published. TreasuryCap has NOT been transferred."

**Problem:** Phase 6 (publish) succeeded, but Phase 7 (transfer) failed.

**Solution:** The script prints the recovery command. Run it manually:

```bash
sui client transfer --object-id <TreasuryCap_ID> \
  --to <TREASURY_ADDRESS> --gas-budget 10000000
```

### "sui move build" fails after generation

**Problem:** Generated package doesn't compile.

**Causes:**

- Invalid env var values (e.g., TOKEN_DECIMALS is not a number).
- A downstream package references the wrong module path.

**Solution:**

1. Check env var types match expected formats.
2. Ensure the generated module name (`TOKEN_MODULE_NAME`) matches what the downstream package imports.

### Blob object ID is "N/A" (alreadyCertified)

**Problem:** Your image was already uploaded to Walrus (blob already exists).

**Solution:** Look up the blob object ID manually:

```bash
walrus blob-status --blob-id <BLOB_ID> --context mainnet
```

The returned object ID is needed for lifetime monitoring. Update your deployment records accordingly.

---

## Maintenance & Governance

### Can I Update Token Metadata After Deployment?

**No.** The `MetadataCap` is deleted during `init()`, making all metadata immutable on-chain. This is intentional and cannot be changed.

**If you need to update metadata (name, symbol, decimals, icon):**

1. Deploy a new token package (new package ID).
2. Migrate downstream packages to use the new token type.
3. This requires coordination with governance and users.

### Blob Lifetime Monitoring

Walrus blobs have expiry epochs. The script recommends extending before:

- **Testnet:** Fewer than 10 epochs remain
- **Mainnet:** Fewer than 50 epochs remain

To extend a blob's lifetime (requires the **blob object ID** from Phase 2 output, not the blob content ID):

```bash
walrus extend --blob-obj-id <blob-object-id> --epochs-extended 200 --context mainnet
```

If you have only the blob content ID, look up the object ID first:

```bash
walrus blob-status --blob-id <blob-id> --context mainnet
```

### Package Immutability (UpgradeCap)

The token package's UpgradeCap is **burned during initial deployment** (see `scripts/publish.sh`). This ensures:

- No one can upgrade the token package.
- The package code is permanently frozen.
- The token type is a stable anchor for the entire system.

---

## Advanced: Extending the Template

### Scenario: You want to add custom logic to the token

**Don't.** The template is intentionally minimal. All token behavior (minting, burning, transfers) should happen in downstream packages that consume the coin type.

**If you need custom fields or functions:**

1. Create a companion package that imports `sui_token_template::...::SUI_TOKEN_TEMPLATE`.
2. Keep the token package pristine.

### Scenario: You want to support multiple token types

**Create multiple instances** (one package per token type):

```text
[parent_directory]/
├── sui_token_template/              # Generic template (never deployed)
├── my_token/                # Concrete instance #1
├── myusdc_token/                # Concrete instance #2
└── ...
```

Each instance is independent, immutable, and deployed once.

---

## References

- **Sui Move Documentation:** <https://docs.sui.io/concepts/standards/coin>
- **Coin Registry API:** <https://docs.sui.io/references/framework/sui-framework/coin_registry>
- **Walrus Documentation:** <https://docs.walrus.site>

---

## License

This template is CC0 (public domain). Use it freely in your own projects.
