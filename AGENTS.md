# AGENTS.md — sui_token_template Package

This package is a **generic Sui coin template and deployment system** for generating immutable, production-grade fungible coin packages.

---

## What This Package Does

**Generates concrete coin packages** from a reusable template, with all token-specific values (name, symbol, decimals, icon) provided as environment variables.

**Deploys coins end-to-end:**

1. Uploads icon to Walrus.
2. Generates the Move package.
3. Tests and builds locally.
4. Publishes on-chain (testnet or mainnet).
5. Burns the UpgradeCap (makes the package immutable).
6. Transfers TreasuryCap to governance.

**Immutability profile:**

- Symbol, name, and decimals are set once and cannot change.
- Description and icon URL remain updatable via the `MetadataCap` (governance-gated).
- UpgradeCap is burned immediately; the package code is permanently frozen.
- This is intentional: the coin is a trust commitment.

---

## Repository Role

**In a consuming project:**

- `sui_token_template/` is a **template system**, not a coin package itself.
- A generated package (e.g. `my_token/`) is a **concrete instance** committed to the consuming project.
- Any number of coins can be generated the same way, one package per coin type.

**Coupling:**

- A downstream package imports the generated type, e.g. `my_token::mytoken::MYTOKEN` — a hardcoded type dependency.
- The type path is determined at generation time and is permanent after deployment.
- Downstream packages reference the coin type via package ID and must be updated after deployment.

**No business logic here:**

- This package defines the type and initializes metadata only.
- All minting, burning, and accounting logic lives in the downstream packages that consume the coin type.

---

## Key Files and Responsibilities

| File | Purpose | Maintainer Notes |
| --- | --- | --- |
| `sources/sui_token_template.move` | Template source; uses buildable placeholder values | Keep minimal. Changes affect all future generated instances. Tests are inline. |
| `scripts/03_create_token.sh` | Generator: template → concrete instance | Idempotent. Safe to run multiple times (overwrites). Validates substitutions. |
| `scripts/deploy_token.sh` | Full pipeline: Walrus → generate → build → publish → transfer | Error recovery instructions included. Print recovery commands if phases 7–8 fail post-publish. |
| `scripts/publish.sh` | Simple build + publish for existing instances | Copied to all generated instances. No regeneration logic. |
| `Move.toml` | Package manifest (template version) | Minimal; copy during generation with package name substitution. |
| `README.md` | User-facing feature overview | Keep synchronized with actual script behavior. |
| `IMPLEMENTATION_GUIDE.md` | Practical deployment workflows | Workflows and checklists. Update if env vars, phases, or steps change. |
| `CLAUDE.md` | Claude-specific guidance (this repo's instruction layer) | Design philosophy, working rules, integration points. |

---

## Working Rules

### Scope-Specific Changes

**Template source changes** (`sources/sui_token_template.move`):

- Affects only future generated instances; existing coins are not retroactively updated.
- Must maintain compilability and test coverage.
- Do not add business logic, dependencies, or complexity.

**Script changes** (`03_create_token.sh`, `deploy_token.sh`, `publish.sh`):

- `03_create_token.sh` and `deploy_token.sh` affect only future generations/deployments.
- `publish.sh` is copied to generated instances; changes after generation don't affect already-generated instances.
- All scripts use `set -euo pipefail`. No partial state on failure.

**Documentation changes** (`README.md`, `IMPLEMENTATION_GUIDE.md`):

- Keep in sync with actual script behavior.
- Both apply to all users of the system (template itself and all generated instances).

### When to Change This Package

**Do make changes when:**

- The template needs new functionality (e.g., new test coverage, new fields).
- Script logic needs updating (new phases, new validation, error handling improvements).
- Documentation drifts from reality.
- Deployment workflows change (Walrus API updates, Sui CLI changes, phase ordering).

**Do not:**

- Add business logic to the coin template. All minting/burning goes in downstream consumer packages.
- Add Move dependencies. The template should import only Sui framework modules.
- Assume backwards compatibility. Generated instances are committed artifacts; changes to the template don't affect them retroactively.

### Error Handling and Recovery

All scripts provide recovery paths:

- **03_create_token.sh:** Validates substitutions; aborts cleanly if template not found or substitution fails.
- **deploy_token.sh:** Each phase prints clear error messages. Phases 7 and 8 (burn UpgradeCap, transfer TreasuryCap) print manual recovery commands if they fail post-publish.
- **publish.sh:** Simple wrapper; inherits error handling from `sui move` and `sui client`.

If a deployment fails after Phase 6 (publish) but before Phase 8 (transfer):

- Package is on-chain with a published package ID.
- UpgradeCap may or may not be burned (check Phase 7 output).
- TreasuryCap is still with the deployer.
- Recovery instructions are printed; the user runs them manually.

---

## Integration Patterns

### Generating a New Coin

```bash
TOKEN_PACKAGE_NAME=mycoin_coin \
TOKEN_MODULE_NAME=mycoin \
TOKEN_STRUCT_NAME=MYCOIN \
TOKEN_SYMBOL="MYCOIN" \
TOKEN_NAME="My Coin" \
TOKEN_DESCRIPTION="..." \
TOKEN_DECIMALS="9" \
TOKEN_ICON_URL="https://..." \
bash scripts/deploy_token.sh
```

Or, for just generation (if icon is already on Walrus):

```bash
... same vars ... \
bash scripts/03_create_token.sh --output-dir mycoin_coin
```

### Downstream Move Integration

After deployment, update downstream packages:

```toml
[addresses]
mycoin = "0x<DEPLOYED_PACKAGE_ID>"

[dependencies]
MyCoin = { local = "../mycoin_coin" }
```

Then import:

```move
use mycoin::mycoin::MYCOIN;
```

### Walrus Blob Lifetime

The icon URL is immutable on-chain. Manage blob lifetime separately:

```bash
# Check remaining epochs
walrus blob-status --blob-id <BLOB_ID> --context mainnet

# Extend before expiry (testnet: < 10 epochs, mainnet: < 50 epochs)
walrus extend --blob-obj-id <BLOB_OBJECT_ID> --epochs-extended 200 --context mainnet
```

---

## Testing and Verification

**Unit tests (template):**

```bash
sui move test --build-env testnet
```

**Generated instance tests:**

```bash
sui move test --path my_token --build-env testnet
```

Tests are inherited from the template via substitution. Four tests:

1. TreasuryCap is transferred to the deployer.
2. TreasuryCap is present after init.
3. MetadataCap is present after init (metadata stays governance-updatable).
4. Currency is transferred to the registry address, pending `finalize_registration`.

**Integration verification:**

1. Run `deploy_token.sh` → Phases 4–5 run `sui move test` and `sui move build`.
2. Verify on-chain: `sui client object <PACKAGE_ID>` and `sui client objects --address <TREASURY_ADDRESS>`.
3. Verify icon: `curl -I <BLOB_URL>` returns 200.

---

## Safe Defaults

If a design choice is ambiguous:

1. **Immutability over flexibility.** Lock it down once; don't change it later.
2. **Minimal scope.** Keep the coin package simple. Downstream packages handle complexity.
3. **Explicit error handling.** Print recovery commands, not just error messages.
4. **Offline validation.** Require confirmation (type `CONFIRM`) before on-chain actions.

---

## Documentation Rules

- `README.md` is the authoritative feature overview and reference.
- `deployments.md` is the template for recording post-deployment artefact IDs.
- `IMPLEMENTATION_GUIDE.md` is the authoritative deployment playbook.
- `CLAUDE.md` is Claude-specific guidance (design philosophy, integration points, working rules).
- If a folder has its own guidance documents, follow the nearest one first.
- Keep all documentation in sync with actual behavior.

---

## MCP and References

Use **Sui Knowledge Docs MCP** to validate:

- Sui Move syntax and semantics.
- Coin registry APIs and patterns.
- Current best practices for package structure.

**Local references:**

- Sui framework docs in `node_modules/@mysten/sui/docs/`.
- Official Sui documentation for Move 2024 features.

---

## Common Tasks

**Generate a coin:**
→ Use `deploy_token.sh` (full pipeline) or `03_create_token.sh` + manual publish.

**Update icon URL (before mainnet):**
→ Regenerate with `03_create_token.sh`, review diff, commit, then deploy.

**Publish existing instance to different network:**
→ Use `publish.sh` (simple build + publish).

**Check deployment status:**
→ `sui client object <PACKAGE_ID>` and `sui client objects --address <TREASURY_ADDRESS>`. Record results in `deployments.md`.

**Extend blob lifetime:**
→ `walrus extend --blob-obj-id <BLOB_OBJECT_ID> --epochs-extended 200 --context mainnet`.

**Debug a failed deployment:**
→ Check Phase 6–8 output for recovery commands. Print TreasuryCap object ID and manual transfer command.
