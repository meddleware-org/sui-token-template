# CLAUDE.md — sui_token_template Package

This package is a **generic Sui coin template and deployment system**. It is not itself deployed; instead, it generates concrete, immutable coin packages for production use.

---

## Purpose and Scope

**What it is:**

- A reusable template for generating Sui coin packages with immutable on-chain metadata.
- A complete deployment pipeline (Walrus upload → generation → build → test → publish → governance transfer).
- A foundation for any coin type an application needs (e.g. a share token, governance token, or stablecoin).

**What it is not:**

- A standalone coin system. All minting/burning logic lives in the downstream packages that consume the coin type.
- Upgradable. The template itself is never deployed. Generated coins have their UpgradeCap burned immediately after publication.
- Flexible. Coin metadata (name, symbol, decimals, icon) is immutable after deployment by design.

---

## Design Philosophy

### Immutability First

The entire coin system is designed around immutability as a feature, not a limitation:

- **On-chain metadata is permanent.** Symbol, name, decimals, and icon are set once at deployment and cannot change. This is intentional.
- **Package code is frozen.** The UpgradeCap is burned immediately after publication, making the package code permanently immutable.
- **Type identity is stable.** The coin type (`<PACKAGE_ID>::<MODULE_NAME>::<STRUCT_NAME>`) is a global, permanent anchor that downstream systems and users depend on.

This design ensures the coin type is a trust commitment that cannot be altered unilaterally.

### Separation of Concerns

- **This package:** Type definition, initialization, metadata commitment. Nothing else.
- **Downstream consumer packages:** Minting, burning, accounting, application logic.
- **`@meddleware/sui-walrus`:** Off-chain asset metadata (icons, extended descriptions).

This separation keeps the coin primitive minimal and auditable.

### Buildable Placeholders

The template uses valid, compilable placeholder values:

- `sui_token_template::sui_token_template` (valid module identifier)
- `SUI_TOKEN_TEMPLATE` (valid struct identifier)
- `0u8` (valid decimals literal)
- `b"TEMPLATE"` (valid byte string literals)

This ensures:

1. The template always compiles and passes tests as-is.
2. The generator's substitution logic is simple (sed-based, auditable).
3. Concrete instances inherit the template's test coverage.

---

## Structure and Files

```text
.
├── Move.toml                    # Template package manifest
├── sources/
│   └── sui_token_template.move       # Template source with inline tests
├── scripts/
│   ├── 03_create_token.sh       # Generator: template → concrete instance
│   ├── deploy_token.sh          # Full deployment pipeline
│   └── publish.sh               # Simple build + publish wrapper
├── templates/
│   ├── .gitignore               # Copied verbatim into generated packages (no Move.lock entry)
│   ├── publish.sh               # Copied verbatim into generated packages
│   ├── README.md                # Substituted into generated packages
│   └── deployments.md           # Substituted into generated packages
├── README.md                    # User-facing reference and feature overview
├── IMPLEMENTATION_GUIDE.md      # Practical deployment workflows
└── CLAUDE.md                    # This file

my_token/         # Example: a generated concrete instance
├── Move.toml
├── sources/
│   └── mytoken.move            # Concrete: all placeholders substituted
├── scripts/
│   └── publish.sh              # Inherits from template
├── deployments.md               # Post-deployment artefact IDs (filled in after each deploy)
└── build/
```

---

## Files and Responsibilities

### `Move.toml` — Package Manifest

- Minimal: no dependencies beyond Sui framework.
- Package name and address alias: `sui_token_template`.
- Generated instances have concrete names (e.g., `my_token`).

### `sources/sui_token_template.move` — Template Source

- **Exports:** Nothing public. All functionality is used via the coin registry system.
- **Defines:** `SUI_TOKEN_TEMPLATE` (type witness), `init()` (one-time-use initialization).
- **Tests:** Four inline unit tests verify TreasuryCap transfer/presence, MetadataCap presence, and Currency transfer to the registry.
- **Constraints:**
  - Uses `coin_registry::new_currency_with_otw()` to bind the coin type to this package.
  - Calls `builder.finalize(ctx)` — which **claims a live `MetadataCap`** (name/symbol/decimals stay immutable, but description and icon remain updatable via governance). It does NOT delete the cap.
  - Transfers both the `TreasuryCap` and the `MetadataCap` to the deployer (transaction sender).

**Key decision:** Tests are inline (`#[test]` attributes in the same file) rather than in a separate `tests/` directory. This keeps the package minimal and allows test coverage to be inherited by generated instances.

### `scripts/03_create_token.sh` — Generator

**Purpose:** Transform the template into a concrete coin package.

**Input:** 8 required environment variables (all non-empty):

- `TOKEN_PACKAGE_NAME`, `TOKEN_MODULE_NAME`, `TOKEN_STRUCT_NAME`
- `TOKEN_SYMBOL`, `TOKEN_NAME`, `TOKEN_DESCRIPTION`
- `TOKEN_DECIMALS`, `TOKEN_ICON_URL`
- `--output-dir` flag

**Output:** A complete, ready-to-build Move package in the output directory.

**Mechanism:**

1. Validates all env vars are set (colon expansion: fails on unset AND empty).
2. Creates output directory with `sources/` and `scripts/` subdirectories.
3. Copies and substitutes `Move.toml` (package name only).
4. Copies `publish.sh` (generic, no substitution).
5. Copies and substitutes `sui_token_template.move` with all 8 replacements:
   - Module path: `sui_token_template::sui_token_template` → `$TOKEN_PACKAGE_NAME::$TOKEN_MODULE_NAME`
   - Struct: `SUI_TOKEN_TEMPLATE` → `$TOKEN_STRUCT_NAME`
   - Decimals: `0u8` → `$TOKEN_DECIMALS`
   - Strings (4 occurrences, in order): `b"TEMPLATE"` → actual values
6. Renames source file: `sui_token_template.move` → `$TOKEN_MODULE_NAME.move`.
7. Validates no `sui_token_template` identifier remains (catches incomplete substitution).

**Idempotency:** Running again with the same output directory overwrites the instance. This is the intended workflow for updating (e.g., setting icon URL before mainnet).

### `scripts/deploy_token.sh` — Full Deployment Pipeline

**Purpose:** Complete end-to-end deployment with no manual steps between Walrus and TreasuryCap transfer.

**Phases:**

1. **Preflight** — Validate env vars, tools, network, image, address formats. Check SUI balance (warning only).
2. **Walrus Upload** — Upload image to Walrus (50 epochs testnet, 200 mainnet). Parse blob ID and object ID. Prompt user to verify URL.
3. **Generate** — Call `03_create_token.sh` with derived icon URL.
4. **Build & Test** — Run `sui move test` and `sui move build`.
5. **Confirmation** — Print summary, require user type `CONFIRM`.
6. **Publish** — Run `sui client publish --gas-budget 100000000`. Parse package ID and TreasuryCap ID.
7. **Burn UpgradeCap** — Call `sui client call --package 0x2 --module package --function make_immutable` with UpgradeCap ID. Package becomes immutable.
8. **Transfer TreasuryCap** — Transfer to governance multisig. Includes recovery instructions if transfer fails (print object ID and manual command).
9. **Summary** — Print all IDs, blob URLs, addresses, and next steps.

**Error Handling:**

- All phases use `set -euo pipefail`.
- Phases 1–6 abort cleanly on first error (no partial state).
- Phase 7 (burn) uses `if !` to print recovery instructions if it fails post-publish.
- Phase 8 (transfer) uses `if !` similarly.
- Phase 5 (confirmation) exits cleanly if user doesn't type exact string.

**Flags and Env Vars:**

- Uses `walrus store --context $NETWORK --json` (tested with walrus 1.49.1).
- Uses `jq` recursive descent for balance parsing (works across Sui CLI versions).
- Checks active Sui environment vs NETWORK and warns if mismatch.

### `scripts/publish.sh` — Simple Build + Publish

**Purpose:** Publish an already-generated coin instance without re-running the full pipeline.

**Use case:**

- Deploying a committed coin package to a different network.
- Manual iteration during development (edit, build, publish directly).

**Behavior:** Runs `sui move build` then `sui client publish --gas-budget 50000000`. No generation, no Walrus, no UpgradeCap burn (assumes already burned by deploy_token.sh on first deployment).

---

## Working Rules

### When Using This Package

**Do:**

- Use `deploy_token.sh` for all first-time coin deployments (handles everything end-to-end).
- Use `03_create_token.sh` alone if you already have a Walrus blob URL.
- Test on testnet before mainnet. The package ID will differ, but the process is identical.
- Commit generated token instances (e.g., `my_token/`) to git. They are immutable artifacts.
- Review the diff after regeneration (e.g., icon URL updates) before committing.

**Don't:**

- Manually edit generated coin source code. Regenerate using `03_create_token.sh` instead.
- Deploy the template itself (it's not a coin, just a mold).
- Assume metadata can be changed later. It is locked forever after deployment.
- Change TOKEN_DECIMALS or TOKEN_SYMBOL without understanding the downstream impact (wallets, exchanges, integrations all depend on these being stable).

### Scope-Specific Guidance

**For Sui Move changes:**

- Any change to `sui_token_template.move` affects all future generated instances.
- Existing deployed instances do not change; they are committed artifacts.
- Changes must maintain the template's compilability and test coverage.
- Do not add dependencies or business logic. Keep the template minimal.

**For script changes:**

- Changes to `03_create_token.sh` affect only future generations.
- Changes to `deploy_token.sh` affect only future deployments.
- Both scripts are part of the template system; they are not generated (they exist only in sui_token_template/).

**For documentation changes:**

- `README.md` and `IMPLEMENTATION_GUIDE.md` describe the system as a whole.
- They apply to all generated instances and the template itself.
- Keep them in sync with actual script behavior.

---

## Integration Points

### Downstream Move Packages

Generated coins are referenced in Move code via:

```move
use <PACKAGE_ID>::<TOKEN_MODULE_NAME>::<TOKEN_STRUCT_NAME>;
```

Example downstream import:

```move
use my_token::mytoken::MYTOKEN;
```

**Key:** The package ID, module name, and struct name are all determined at generation time. They do not change after deployment.

### Frontend

The generated coin type is typically configured in a frontend's environment files:

```env
VITE_COIN_TYPE=0x<PACKAGE_ID>::<MODULE_NAME>::<STRUCT_NAME>
```

Update after deployment to ensure the frontend uses the correct coin type.

### Walrus Blob Lifetime (`@meddleware/sui-walrus`)

The icon URL (from Phase 2 of deploy_token.sh) is immutable on-chain. Off-chain lifetime management:

- Blob object ID is printed in Phase 2 and Phase 8 summaries.
- Before expiry, call `walrus extend --blob-obj-id <BLOB_OBJECT_ID> --epochs-extended 200 --context mainnet`.
- For testnet: extend before < 10 epochs remain; for mainnet: before < 50 epochs remain.

---

## Testing and Verification

### Unit Tests (Inline in template)

```bash
sui move test --build-env testnet --path .
```

Four tests:

1. `test_treasury_cap_transferred_to_sender` — Verifies the TreasuryCap is owned by the deployer.
2. `test_treasury_cap_present_in_sender` — Verifies the TreasuryCap is present after init.
3. `test_metadata_cap_present_in_sender` — Verifies the MetadataCap is present after init (metadata stays governance-updatable).
4. `test_currency_transferred_to_registry_after_init` — Verifies the Currency is transferred to the registry address (`@0xc`), pending `finalize_registration`.

All generated instances inherit these tests via substitution.

### Integration Testing

The `deploy_token.sh` pipeline includes `sui move test` and `sui move build` as Phases 4–5. These verify the generated instance:

1. Compiles without errors.
2. All tests pass.
3. Tests include the inherited unit tests from the template.

### Manual Verification

After on-chain deployment:

```bash
# Check package on-chain
sui client object <PACKAGE_ID>

# Verify metadata (symbol, name, decimals, icon)
sui client object <METADATA_OBJECT_ID>

# Check TreasuryCap at treasury address
sui client objects --address <TREASURY_ADDRESS> | grep TreasuryCap

# Check icon URL resolves
curl -I <BLOB_URL>  # Should return 200
```

**Record all artefact IDs in `deployments.md`** at the generated token package root for future reference and blob lifetime monitoring.

---

## Safe Defaults

If a design choice is ambiguous:

1. **Prefer immutability.** When in doubt, lock it down.
2. **Prefer minimal scope.** Keep the coin package simple. All business logic goes downstream.
3. **Prefer explicit error handling.** Recovery instructions (UpgradeCap burn, TreasuryCap transfer) print exact commands for manual recovery.
4. **Prefer offline validation.** `deploy_token.sh` requires explicit confirmation (type `CONFIRM`) before publishing.

---

## References

- **README.md** — Feature overview, quick start, architecture, troubleshooting.
- **deployments.md** — Post-deployment artefact recording and blob lifetime tracking. Lives in each generated token package root (e.g., `my_token/deployments.md`); sourced from `templates/deployments.md`.
- **IMPLEMENTATION_GUIDE.md** — Deployment workflows (testnet, mainnet), decision tree, common mistakes, best practices.
- **Sui Move Docs** — Official Sui documentation for coin registry and framework APIs.
