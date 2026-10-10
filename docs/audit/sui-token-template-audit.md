# Security Audit — `sui-token-template`

**Classification:** Internal security review (initial audit — awaiting external review)
**Project:** `sui-token-template` — a generic Sui coin template, its shipped bytecode artefact, the
shell generator and the deployment pipeline (Sui Move + shell).
**Project type:** Move package
**Template:**

- AUDIT_TEMPLATE.md (2026-10-08)
- AUDIT_TEMPLATE_SUI.md (2026-09-28)
- AUDIT_TEMPLATE_OPS.md (2026-10-08) — applied since 2026-10-03: `scripts/` and `templates/publish.sh`
  sign on testnet and mainnet and perform irreversible steps
- AUDIT_TEMPLATE_TS.md (2026-10-08) — npm-package rows only (B.TS-1/2/3, TS-M7/M8): the package is
  published to npm but ships no TypeScript (applied 2026-10-09; the README applicability matrix lists
  it as partial)

The first pass (2026-09-28) used the base template and the SUI lens only. Not triggered: SUI_CLIENT (no
TypeScript client here; the client is `sui-token-client`, and the shell scripts only call the `sui`
CLI and match created objects by exact type, which OPS-M4 covers), VUE, SEAL, WALRUS (the icon upload
uses the `walrus` CLI; noted under OPS), AUTH, IMG (no image), SITE.

**Package:**

- `sui_token_template` — `Move.toml` `version = "1.0.0"`, npm `@meddleware/sui-token-template`
  **1.0.8** (tag `v1.0.8` = `5451c0e` = HEAD of `main`, 2026-10-09; SLSA v1 provenance, registry
  `latest`).
- Edition 2024.
- Framework pinned by the committed `Move.lock` (rev `83f11dc8…b059`, unchanged since 1.0.6).
- Shipped bytecode `bytecode/sui_token_template.mv` (`moduleSha256 96298cca…9630`, 931 bytes,
  toolchain 1.81.0; 1.0.6 and 1.0.7 shipped `41511ed4…e9b7`).

**OPS front matter:**

| Field | Value |
| --- | --- |
| CLI tools | `sui` — CI pins `testnet-v1.81.0` via a sha256-verified `suiup` v0.0.14 and a sha256 check of the binary; `build-info.json` records 1.81.0; preflight reads its expected major.minor from `build-info.json` (one source, F16). `walrus` — unpinned (operator). `jq`, `curl` |
| Networks targetable | `deploy_token.sh`: testnet and mainnet (mainnet behind `MAINNET_CONFIRM=1`). Generated `publish.sh`: localnet, testnet, mainnet. `02_upload_image.sh`: testnet and mainnet |
| Key material | the operator's active `sui` keystore and `walrus` wallet; no keys in CI (CI runs build, tests, shellcheck and the generator tests only) |

**Deployment status:**

- Never published itself (it is a template); every generated coin is an independent package.
- npm `@meddleware/sui-token-template` **1.0.8** (published 2026-10-09T15:37Z, SLSA v1 provenance,
  `latest`); 1.0.7 was published 2026-10-09T12:49Z.
- Consumers:
  - `@meddleware/sui-token-client` 0.0.10 pins `1.0.8` **exactly** (devDependency) and generates its
    patcher artefact from it. token-deployer-ui (`^0.0.10`) consumes the client, not this package.
  - The docs and dev sites depend on `^1.0.7` for the on-chain docs; both lockfiles resolve 1.0.8.
- No testnet or mainnet coin is recorded here: coins generated from this template belong to their
  deployers.

**Review date:** 2026-10-03 (third pass; previous passes 2026-09-28) · re-verified 2026-10-09
**Reviewer:** Internal review
**Severity ceiling:** Medium.

- The template holds no funds and creates only the coin's own capabilities.
- But every coin generated from it inherits its capability model, and its scripts decide supply,
  metadata and upgrade custody for real tokens. They also write into operator directories.
- Realised ceiling at this pass: **Low** (F21 and F22; F14, the 2026-10-03 Medium, is RESOLVED).

**Status:** re-verified 2026-10-09 at `5451c0e` (tag `v1.0.8`).

- Two releases have landed since the third pass: 1.0.7 (`7d9c04b`: generator validates and stages,
  deploy pipeline records and verifies, one toolchain source, CI parity) and 1.0.8 (`5451c0e`: the
  supply and metadata policies are applied in `init`).
- Every finding was re-checked against the code, the tests and a localnet run of the generated
  `publish.sh`.
- **Corpus IDs F1–F20 are preserved.** New findings start at F21.

---

## Executive summary

**The Move source is sound, and since 1.0.8 it records the user's supply and metadata choices in the
registry.** Every finding from the third pass is closed except two residual Infos and the decisions.

- `init` (one-time witness) registers the coin via `coin_registry::new_currency_with_otw` and applies
  the deployer's policies itself, in the publish transaction (F6 RESOLVED, 1.0.8):
  - `INITIAL_SUPPLY` is minted to the publisher.
  - `FIXED_SUPPLY` hands the `TreasuryCap` to the registry (`make_supply_fixed`); otherwise it goes to
    the publisher.
  - `FROZEN_METADATA` deletes the `MetadataCap` (`finalize_and_delete_metadata_cap`); otherwise
    `finalize` claims a live one for the publisher.
- 6/6 Move tests pass with Sui 1.81.0, covering every policy combination and the framework's
  `EEmptySupply` abort. The coin's own constants are checked against the registry's `Currency`
  (`is_supply_fixed`, `is_metadata_cap_deleted`, `total_supply`), so generated instances inherit a
  test that stays true after patching.
- A generated fixed-supply, frozen-metadata coin published with `publish.sh` on a throwaway localnet
  (2026-10-09) shows `supply = Fixed(1000000000)` and `metadata_cap_id = Deleted` in its `Currency`.
- The package ships **reproducible bytecode**: `scripts/build-bytecode.sh --check` reproduced
  `bytecode/sui_token_template.mv` byte for byte (`96298cca…`) with `Move.lock` committed. CI now also
  asserts that the CLI line the scripts demand is the one in `build-info.json`.
- `sui-token-client` 0.0.10 pins 1.0.8 exactly and checks the artefact in CI (F9); the docs and dev
  sites resolve 1.0.8 (F12).

**The three 2026-10-03 shell findings are RESOLVED in 1.0.7** (`7d9c04b`), pinned by the 38-case
`tests/generator.test.sh`, which now runs in CI:

- **F14 (was Medium) — the generator deleted the operator's directory.** It now generates in a
  `mktemp -d` staging directory, installs only after every check passed, removes only the staging
  directory, and refuses `/`, `$HOME`, `.` and a git work-tree root unless `FORCE_OUTPUT_DIR=1`.
- **F15 (was Low) — the CLI generator validated nothing.** It now applies the rules of
  sui-token-client's `assertTokenConfig` (ported to shell, OQ6) and substitutes by exact token or whole
  line in one pass: the injection probe, the symbol/name collision and `&` all fail or are written
  literally.
- **F16 (was Low) — the CLI pins conflicted.** Preflight, CI and the artefact now share
  `build-info.json`.
- **F17 (was Low) — the deploy pipeline's OPS gaps.** The `TreasuryCap` and initial-supply transfer
  has its own typed confirmation (`TRANSFER`; the address prefix on mainnet) and is re-read on-chain,
  the burn is verified by the `UpgradeCap` no longer existing, and every ID goes to
  `.env.<network>` as it appears (a second run refuses to publish a second coin).

**What remains (all Low or Info):**

- **F21 (Low)** — the `deploy_token.sh` summary says the `UpgradeCap` was burned and the package is
  immutable even when the operator declined `BURN`.
- **F22 (Low)** — the burn checks (`deploy_token.sh` phase 6b, `publish.sh`) treat any CLI failure as
  "the object is gone", not only a not-found error.
- **F23 (Info)** — two documentation leftovers (a stale test list in `CLAUDE.md`; the `exports`
  layout contract is not written down).
- **F24 (Info)** — no `npm audit` step; the dependency tree is empty (ACCEPTED-RISK).
- Deferred by decision: F7's residual (`Move.lock` is not shipped in npm or into generated packages)
  and F8 (`Move.toml` version vs npm, OQ5); F18 is RESOLVED (the unused alias went with the 1.0.8
  rewrite).
- Not run: `deploy_token.sh` end to end on testnet (needs a funded keystore and WAL; S1).

---

## Threat model / trust boundaries

| Authority / actor | Holds / proves | Can do | Bounded by |
| --- | --- | --- | --- |
| Coin publisher | the initial-supply `Coin<T>`; `TreasuryCap<T>` unless the supply is fixed; `MetadataCap<T>` unless the metadata is frozen; `UpgradeCap` (at publish) | mint or burn any amount (mintable only); change description and icon (updatable only); upgrade the coin package | the supply and metadata policy compiled into `init` and recorded in the registry (F6); custody choices at deploy time (B.3, OQ2) |
| Anyone | nothing | `finalize_registration` for any pending coin | framework (harmless: completes registration) |
| Shell generator caller (`03_create_token.sh`, `deploy_token.sh` env) | every `TOKEN_*` value; `--output-dir` | write constants and identifiers into Move source; write files under the output directory | ported `assertTokenConfig` rules and one-pass exact substitution (F15); staging directory, dangerous-directory refusal (F14) |
| Browser generator (`@meddleware/sui-token-client`) | the user's form values | patch bytecode and render source | `assertTokenConfig` (SAFE_TEXT, identifier rules, limits); pristine-pool patcher with a post-check (sui-token-client) |
| npm / template maintainer | publish rights for `@meddleware/sui-token-template` | change what every future coin is built from | OIDC publish from tagged commits (verify job = the full CI workflow: `sui move test`, bytecode `--check`, shellcheck, generator tests); sui-token-client pins exactly and checks hashes |

**Primary trust anchor:** the one-time witness and the framework `coin_registry`. Only the
capabilities `init` hands out exist.

### Capabilities & shared objects (Move lens)

| Object / type | Minted / created by | Holder / custodian | Authority it confers | Compromise / misuse impact | Immutability / rotation plan |
| --- | --- | --- | --- | --- | --- |
| `TreasuryCap<T>` | `init`, unless `FIXED_SUPPLY` | publisher → treasury (`deploy_token.sh` phase 7, own typed confirmation — F17); with `FIXED_SUPPLY` the registry holds it (`make_supply_fixed`) and nobody can mint | unlimited mint / burn | inflation, supply collapse | fixed supply recorded in the registry (F6); else multisig custody (OQ2) |
| Initial-supply `Coin<T>` | `init`, when `INITIAL_SUPPLY` > 0 | publisher → treasury (`deploy_token.sh` phase 7) | the minted supply | loss or theft of the supply | ordinary coin custody |
| `MetadataCap<T>` | `init` (`builder.finalize`), unless `FROZEN_METADATA` | publisher (all CLI paths); with `FROZEN_METADATA` it is deleted and the registry says so | description + icon URL | phishing icon or description on a live token | `finalize_and_delete_metadata_cap` (F6) or multisig (OQ2) |
| `UpgradeCap` | publish | publisher → burned on `BURN` (`deploy_token.sh`), on `--confirm-immutable`/`CONFIRM` (`publish.sh`), or by policy (sui-token-client) | replace the coin package code | upgrades can add functions | burn — both scripts verify consumption (F1, F17; but see F21 and F22) |
| `Currency<T>` | `init` → pending at `0xc`; shared after `finalize_registration` | coin registry | registry record (metadata, supply state: `Fixed` or `Unknown`, `metadata_cap_id`: `Claimed` or `Deleted`) | — | managed by the framework |
| `CoinRegistry` `0xc` (external) | system | shared | registration | — | n/a |

### Operations matrix (OPS lens)

| Actor / asset | Power | Bounded by |
| --- | --- | --- |
| Operator keystore (active `sui` address) | signs publish, finalize, burn, transfer | preflight: env, chain id and CLI checks; `CONFIRM`/`BURN`; `MAINNET_CONFIRM=1` |
| Env files (`scripts/*.env.sh`) | every parameter, including the treasury address | git-ignored since `dad4208`; examples only committed |
| CLI binaries | what executes | CI: sha256-pinned `suiup`, `sui@testnet-v1.81.0` and a sha256 check of the installed binary; operator: preflight major.minor check against `build-info.json` (F16) |
| Operator's global CLI state | which env and signer | scripts require (never switch) the env; `chain-identifier` caching documented |
| Operator filesystem (`--output-dir`) | the generated package and records | staging directory; refuses `/`, `$HOME`, `.` and a git work-tree root; a failing run changes nothing (F14) |
| Downstream records | `deployments.md`, `.env.<network>` | both `publish.sh` and `deploy_token.sh` persist IDs per step (F17); `deployments.md` is still filled by hand |

### Script inventory (OPS lens)

| Script / job | Signs? | Objects touched | Irreversible? | Dry-run default | Confirmation | Network guard | Writes IDs to |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `01_preflight.sh` | no | — | no | n/a | n/a | env + chain id + CLI (hard fail) | optional `--output-file` (deployer address) |
| `02_upload_image.sh` | yes (`walrus store`, WAL/SUI) | Walrus blob | spends WAL | no | Enter to continue | `--context $NETWORK` | stdout |
| `03_create_token.sh` | no | the filesystem | no (writes into `--output-dir` only after validation; removes only its own staging directory) | n/a | none | refuses dangerous directories (F14) | generated files |
| `deploy_token.sh` | yes (publish, finalize, burn, transfer) | package, `Currency`, `UpgradeCap`, `TreasuryCap` (unless fixed), initial `Coin<T>` | publish, burn, transfer | no dry-run mode; the burn and the transfer default to "keep" | `CONFIRM` (publish), `BURN` (burn), `TRANSFER` or the address prefix on mainnet (transfer) | preflight + `MAINNET_CONFIRM=1` (exit 78) | `$OUTPUT_DIR/.env.<network>` per step (F17) |
| generated `scripts/publish.sh` | yes | package, `Currency`, icon, `UpgradeCap` | publish, burn | burn off unless confirmed | `--confirm-immutable` or `CONFIRM` | active env must equal `NETWORK` | `.env.<network>` per step |
| `build-bytecode.sh` | no | `bytecode/` | no | `--check` in CI | n/a | testnet build env | `bytecode/` |
| CI `move-ci.yml`, `npm-publish.yml` | no chain signing | — | npm publish (tag) | — | tag = version | — | npm |

## Severity scale

Critical / High / Medium / Low / Info / Positive.

## Scope

- **In scope (`5451c0e`, tag `v1.0.8`):**
  - `sources/sui_token_template.move`, `Move.toml`, `Move.lock`, `bytecode/*`, `package.json`
  - `scripts/{01_preflight,02_upload_image,03_create_token,deploy_token,build-bytecode}.sh` and the
    `*.env.sh.example` files
  - `templates/*` (`publish.sh`, `CLAUDE.md`, `AGENTS.md`, `README.md`, `deployments.md`,
    `gitignore`, `LICENSE-0BSD`)
  - `tests/generator.test.sh`
  - `.github/workflows/{move-ci,npm-publish}.yml`, `.github/dependabot.yml`
  - `README.md`, `CLAUDE.md`, `AGENTS.md`, `SECURITY.md`, `docs/*`
  - coupling with `sui-token-client`, the docs and dev sites (read-only)
- **Out of scope:** `sui-token-client` and token-deployer-ui implementations (their own audits);
  coins already generated; Walrus.
- **Environment (2026-10-09, `5451c0e`; the 2026-10-03 pass used `ca0e2d7`):**

| Command | Result |
| --- | --- |
| Sui CLI | `sui 1.81.0-bf0c491c17b8` (the CI-pinned line) |
| `sui move test --build-env testnet` | **6/6 pass** (1.0.6: 4/4). `sui move build` is clean: the unused-alias warning of F18 is gone |
| `bash scripts/build-bytecode.sh --check` | **"bytecode/ matches a fresh build (96298cca…)"** |
| `bash tests/generator.test.sh` | **38 passed, 0 failed** (validation, injection, one-pass substitution, policies, dangerous directories, licences, failing runs leave an existing directory byte-identical) |
| `npm pack --dry-run` | 33 files, 58.1 kB; ships `bytecode/`, `docs/onchain/`, `docs/IMPLEMENTATION_GUIDE.md`, `docs/WALRUS.md`, `scripts/`, `templates/`, `sources/`. **No `docs/audit`** (F19) and **no `Move.lock`** (F7) |
| `npm view @meddleware/sui-token-template` | `latest` = 1.0.8, published 2026-10-09T15:37Z, SLSA v1 provenance attestation; 1.0.7 published 2026-10-09T12:49Z |
| `npm audit --audit-level=high` | 0 vulnerabilities (the lockfile holds only the root package; F24) |
| CI (`gh run list`) | Move CI on `5451c0e` and the `v1.0.7` / `v1.0.8` Publish (npm) runs: success |
| Localnet run of the generated `publish.sh` (throwaway `sui start --force-regenesis`, scratch output dirs) | two packages generated by `03_create_token.sh`: (1) `TOKEN_SUPPLY_POLICY=fixed`, `TOKEN_METADATA_POLICY=frozen`, supply 1000: `publish.sh localnet --confirm-immutable` published, finalised, skipped the icon step ("metadata is frozen"), burned and verified the `UpgradeCap`; the registry `Currency` reads `supply = Fixed(1000000000)`, `metadata_cap_id = Deleted`, and the deployer holds the minted `Coin`. (2) mintable and updatable, supply 5: the `TreasuryCap` and `MetadataCap` reached the publisher, `set_icon_url` ran, `supply = Unknown`, `metadata_cap_id = Claimed`; a second run resumed from `.env.localnet` and burned the cap. `sui client object` on a consumed `UpgradeCap` exits non-zero with "not found" (F22) |
| shellcheck | not installed here (runs in CI, green) |
| `deploy_token.sh` live run | **not run** (needs a funded testnet keystore and WAL for the Walrus upload; S1). Its policy-dependent parsing is read, not executed |

  The localnet was stopped and the Sui CLI's active environment restored to `testnet` afterwards; the
  scratch packages live outside the repository.

---

## Findings

### F1 — Per-instance `publish.sh` could misreport immutability and lose deployment state

**Severity:** Medium   **Disposition:** RESOLVED (re-verified 2026-10-09: `templates/publish.sh`
changed since `6ea9bb0` only in `5451c0e`, to carry the supply and metadata policies; the fixes below
are intact and were exercised on localnet)
**Where:** `templates/publish.sh` (copied into every generated package as `scripts/publish.sh`).
**Issue:**

- (a) `while [[ $# -gt 1 ]]` started at the network argument, so the **last** argument was never
  parsed: `publish.sh testnet --confirm-immutable` ignored the flag.
- (b) `is_object_exists` tested `.data != null`, which Sui CLI 1.80 no longer returns. The idempotent
  path therefore printed "UpgradeCap confirmed consumed — package is immutable" **while the cap was
  live**.
- (c) The post-burn check read `.data.owner`, which is always absent (and a package is always
  `Immutable`-owned anyway). It exited 1 after the irreversible burn, before saving IDs.
- (d) IDs were saved only at the end, so a mid-run failure (finalize or icon) lost them and a re-run
  republished.
- (e) Failures inside `$(… | awk)` exited silently.
- (f) localnet publishing always failed (Sui ≥ 1.80 needs `test-publish`).
- (g) Unknown flags were accepted, and the active env was never checked.
**Impact:** a deployer could believe a token package was immutable when it was not, or lose the IDs of
freshly minted `TreasuryCap` / `MetadataCap`.
**Remediation / evidence:** commit `6ea9bb0`. The rewrite:
- parses arguments strictly and fails closed when the active env differs from `NETWORK`;
- runs each step resumably, saving IDs as soon as they exist;
- matches types exactly (`endswith`);
- makes every CLI call surface its output on failure;
- publishes to localnet with `test-publish`;
- proves immutability only by the `UpgradeCap` being consumed.
It was verified on localnet with `--confirm-immutable` last (burned and verified), an idempotent
re-run (resumed, no second publish), and both refusal cases.
**Re-verified 2026-10-09 (`5451c0e`):** the strict argument parse, the active-env check, per-step
`.env.<network>` saves, exact-type matching (`get_created_object` accepts exactly one match) and the
consumption check all remain. On a throwaway localnet a fixed-supply/frozen-metadata coin and a
mintable/updatable coin were published with the generated script; the second was resumed from
`.env.localnet` and burned with `--confirm-immutable`. The policy-aware parts are new in 1.0.8: a
missing `TreasuryCap` or `MetadataCap` is accepted only when the policy says so, and the initial `Coin`
ID is saved. A weakness in the consumption check itself (any CLI failure reads as "consumed") is
recorded as F22.

### F2 — `deploy_token.sh` never finalised coin registration

**Severity:** Medium   **Disposition:** RESOLVED (re-verified 2026-10-09: phase 6a
`finalize_registration` with `Currency` extraction by type and the manual-recovery message is present
at `deploy_token.sh:260-290`)
**Where:** `scripts/deploy_token.sh` phase 6 → 6b.
**Impact:** CLI-deployed coins stayed pending at `0xc`; wallets and explorers could not resolve their
metadata.
**Remediation / evidence:** commit `6ea9bb0` — phase 6a calls `coin_registry::finalize_registration`
with type-exact extraction of the pending `Currency<T>`, with manual-recovery instructions; the
summary reports the `MetadataCap` and `Currency` IDs. Not run live (the pipeline needs a Walrus
upload); the call and extraction are identical to the localnet-verified `publish.sh` step (S1).
Since 1.0.7 the pending-`Currency` ID is also recorded in `.env.<network>` before the call, so a
failed finalise leaves what the printed recovery command needs.

### F3 — Documentation misstated the capability model and verification

**Severity:** Low   **Disposition:** RESOLVED (re-verified 2026-10-09; later drift was recorded in
F16 and F19, both now resolved, and F23)
**Issue:**

- `README.md` said the `MetadataCap` is deleted and that no one can ever change the icon.
- It said the UpgradeCap is "burned during initial deployment" by `scripts/publish.sh`.
- `CLAUDE.md` / `AGENTS.md` described a `scripts/publish.sh` that does not exist.
- The generated `CLAUDE.md` / `AGENTS.md` / `deployments.md` verified immutability with `.data.owner`.
- The docs recommended deprecated JSON-RPC `suix_getCoinMetadata`.
- The implementation guide claimed metadata lookups return null by design.
**Evidence:** commit `6ea9bb0` (plus the `templates/CLAUDE.md` icon-URL correction in the docs
commit). Verification is "UpgradeCap no longer exists" and gRPC `getCoinMetadata`, which was checked
on localnet to return the registry `Currency`.

### F4 — No `SECURITY.md`

**Severity:** Low   **Disposition:** RESOLVED — commit `6ea9bb0` (S8). Re-verified 2026-10-09: it ships
in the 1.0.8 tarball, and `5451c0e` updated it for the in-`init` policies.

### F5 — Source doc comments inaccurate

**Severity:** Info   **Disposition:** RESOLVED — commit `6ea9bb0`. The comments claimed `init` uses
an empty icon URL (it uses the `ICON_URL` constant) and that the UpgradeCap is always burned. The
bytecode is unchanged: only comments were edited. Re-verified 2026-10-09: the module and `init` doc
comments were rewritten in `5451c0e` for the policies and match the code (`init_with`, the constants and
the `publish.sh` steps they describe).

### F6 — Fixed supply / frozen metadata are not recorded in the coin registry

**Severity:** Low   **Disposition:** RESOLVED — 1.0.8, commit `5451c0e` (decided as the
template-level `init` change; OQ3 decided). The text below is the 2026-10-03 finding, kept as written.
**Where:** (updated) `sui-token-client/src/transactions.ts` `buildFinalizeTransaction` freezes the
`TreasuryCap` / `MetadataCap` with `transfer::public_freeze_object`. The logic moved there from
token-deployer-ui (workspace B7).
**Issue:** freezing makes the caps unusable. The registry's `Currency<T>` nevertheless keeps
`SupplyState::Unknown` and a live `metadata_cap_id`, so wallets and indexers reading the registry
(`is_supply_fixed`, `is_metadata_cap_deleted`) do not see the guarantees the user chose.
**Remediation:**

- After `finalize_registration`, call `coin_registry::make_supply_fixed<T>(&mut Currency<T>,
  TreasuryCap<T>)` (or `make_supply_burn_only`) and `coin_registry::delete_metadata_cap<T>(&mut
  Currency<T>, MetadataCap<T>)`. These are framework-documented and consume the caps.
- As sui-token-client F4 notes, a freshly shared `Currency` cannot be borrowed `&mut` in the same
  PTB that shares it. That needs a third transaction, or a template change (`make_supply_fixed_init`
  / `finalize_and_delete_metadata_cap` in `init`), which belongs to this repo.

**Remediation / evidence (re-verified 2026-10-09, `5451c0e`, tag `v1.0.8`):** the template-level option
was taken. A policy applied in a later transaction leaves a window in which the cap exists, and a
freshly shared `Currency` cannot be borrowed `&mut` in the PTB that shares it, so `init` applies the
policy itself, in the publish transaction.

- `sources/sui_token_template.move::init_with` mints `INITIAL_SUPPLY` to the sender. With
  `FIXED_SUPPLY` it calls `builder.make_supply_fixed(treasury_cap)`; otherwise the `TreasuryCap` goes to
  the sender. With `FROZEN_METADATA` it calls `builder.finalize_and_delete_metadata_cap`; otherwise
  `finalize` hands a live `MetadataCap` to the sender.
- The three policy constants are patch points. The two booleans keep different defaults (`true` /
  `false`) so they stay separate constant-pool entries; sui-token-client's patcher also dedupes the
  pool (the verifier rejects duplicates).
- 6/6 Move tests pass (1.81.0): `constants_are_applied` checks whatever constants the package was
  generated with against the registry (`is_supply_fixed`, `is_metadata_cap_deleted`, `total_supply`),
  so generated instances inherit a test that stays true; `fixed_supply_requires_an_initial_mint` pins
  the framework's `EEmptySupply` abort; the others cover the remaining combinations.
- A generated fixed-supply, frozen-metadata coin published on a throwaway localnet reads
  `supply = Fixed(1000000000)` and `metadata_cap_id = Deleted` (2026-10-09). sui-token-client 0.0.9
  and 0.0.10 consume it (its `e2e:localnet` run records `Fixed` and a deleted `MetadataCap`;
  sui-token-client F4 and OQ2 are closed with it).
- The generators, `publish.sh` and `deploy_token.sh` follow the policy: a `TreasuryCap` or
  `MetadataCap` is expected only when the policy says it exists. Coins published before 1.0.8 stay as
  deployed.

### F7 — Framework revision not pinned

**Severity:** Info   **Disposition:** DEFERRED (residual only; OQ4 decided) — gate: pre-mainnet,
before the first mainnet coin is generated from a release (Section D); the shipped artefact itself is
pinned and reproducible
**Re-verification 2026-10-03:**

- **Resolved for the shipped artefact (`ca0e2d7`).** `Move.lock` is committed and pins
  `83f11dc8…b059`. `build-bytecode.sh` records it in `bytecode/build-info.json`, and CI checks the
  shipped `.mv` byte for byte (reproduced here).
- **Residual.** `Move.lock` is **not in `package.json` `files`**, so npm consumers do not receive it.
  Packages generated from this release (the `03_create_token.sh` output, or sui-token-client's
  downloadable source) build against whatever framework the resolver picks. Their source can then
  fail to reproduce the published bytecode for source verification.
- **Remediation:**
  - Ship `Move.lock` (add it to `files`).
  - Copy it into generated packages, renaming the root `sui_token_template` entry, or have
    generators emit a `Move.lock` pinned to `frameworkRev`.

**Re-verified 2026-10-09 (`5451c0e`):** unchanged and still accurate. `git log -- Move.lock` shows
only `ca0e2d7` (1.0.6); the lock is identical in 1.0.7 and 1.0.8 (`83f11dc8…b059`, also in
`build-info.json`), `npm pack --dry-run` lists 33 files with no `Move.lock`, and neither generator
copies one. The shipped bytecode is still checked byte for byte in CI (`--check`), so the residual
concerns only source verification of coins generated from the source package. It stays a pre-mainnet
gate item (Section D) rather than a defect of the artefact.

### F8 — Version drift

**Severity:** Info   **Disposition:** DEFERRED (OQ5; gate: decide before the mainnet 0.2.0 / 2.0.0
re-versioning, which resets every version anyway) — re-verified 2026-10-09: `Move.toml`
`version = "1.0.0"` vs npm **1.0.8** (tags v1.0.0–v1.0.8). The template is never deployed, a
generated coin's on-chain version is the package's own version counter (not the `Move.toml` string),
and the generator copies `version = "1.0.0"` into every manifest; nothing consumes the value.

### F9 — Coupling with `token-deployer-ui` must be re-synced after the next template release

**Severity:** Info   **Disposition:** RESOLVED (re-verified 2026-10-03; re-verified 2026-10-09 against
1.0.8).

- token-deployer-ui no longer embeds template files.
- The template is consumed by `@meddleware/sui-token-client`, which pins
  `@meddleware/sui-token-template` **exactly**: 1.0.6 on 2026-10-03, **1.0.8** now
  (`sui-token-client/package.json`). Its `gen-template.mjs` / `check:template` verifies
  `moduleSha256`, `sourceSha256`, the round trip and the defaults against `build-info.json`, in CI and
  in publish (sui-token-client audit F13).
- token-deployer-ui depends on `@meddleware/sui-token-client ^0.0.10` (client 0.0.9 re-pinned to
  1.0.8; 0.0.10 lists capability-less coins).
- The 1.0.8 release changed the patch points (three policy constants, `bytecode/` 683 → 931 bytes); the
  client's artefact was regenerated and its `e2e:localnet` run passed against it (2026-10-09).

### F10 — `init` creates no authority beyond the two capabilities

**Severity:** Positive — re-verified 2026-10-09 on 1.0.8 (Sui 1.81.0, 6/6). The four tests of 1.0.6 were
replaced by six that exercise `init_with`: `constants_are_applied` (whatever constants the package was
generated with), `mintable_supply_keeps_the_treasury_cap`, `mintable_without_initial_supply_mints_nothing`,
`frozen_metadata_deletes_the_metadata_cap`, `mintable_and_updatable_hands_both_caps_to_the_sender` and
`fixed_supply_requires_an_initial_mint`. `init` still creates only the coin's own capabilities: the
`TreasuryCap` (or the registry holds it when the supply is fixed), the `MetadataCap` (or none when frozen),
the minted `Coin`, and the pending `Currency` sent to `0xc`.

### F11 — Patch-point constants are safe to patch independently

**Severity:** Positive (the 2026-10-03 scope caveat is lifted — see F15)

- The patch-point constants (`DECIMALS`, `SYMBOL`, `NAME`, `DESCRIPTION`, `ICON_URL`, and since 1.0.8
  `INITIAL_SUPPLY`, `FIXED_SUPPLY`, `FROZEN_METADATA`) have distinct values, so the compiler emits no
  shared pool entry; the two booleans deliberately default to different values (`true` / `false`).
  Re-verified 2026-10-09: the shipped module carries each default once, sui-token-client's generator
  checks it, and its patcher also dedupes the constant pool after patching (the verifier rejects a
  module with duplicate entries when two patched values become equal).
- Input validation lives in `@meddleware/sui-token-client` `assertTokenConfig`: `SAFE_TEXT`; symbol
  ≤ 32, name ≤ 64, description ≤ 256, icon ≤ 512 characters; decimals 0–18; the identifier and
  reserved-word rules. Since 1.0.7 `03_create_token.sh` applies the same rules (F15), so the positive now
  covers the **CLI path** too.
- The 2026-09-28 text ("512-char caps and decimals 0–255", in token-deployer-ui) is superseded.
- The patcher's ordering defect noted on 2026-10-03 (sui-token-client F1) is that audit's finding.

### F12 — docs./dev. sites import the canonical on-chain docs only after npm publication

**Severity:** Info   **Disposition:** RESOLVED (re-verified 2026-10-03; re-verified 2026-10-09).

- Both `docs/package.json` and `dev/package.json` depend on `@meddleware/sui-token-template`
  `^1.0.7` (was `^1.0.6`); both lockfiles resolve **1.0.8**.
- The package ships `docs/onchain/{overview,user-guide,dev-guide,api-reference}.md` and
  `manifest.json` (`npm pack --dry-run`, 33 files); `5451c0e` updated the four pages for the in-`init`
  policies.
- Not rebuilt here (the sites' builds are out of scope).

### F13 — Licence: CC0-1.0 replaced by 0BSD

**Severity:** Info   **Disposition:** RESOLVED (owner decision: CC0 usages become 0BSD) — commit
`506c89a`.

- `LICENSE`, `Move.toml`, `package.json`, the source SPDX header, README and IMPLEMENTATION_GUIDE are
  0BSD.
- `scripts/03_create_token.sh` defaults `TOKEN_LICENSE=0BSD`, renders `templates/LICENSE-0BSD` with
  the year and `TOKEN_COPYRIGHT_HOLDER` (default: project or token name), and always rewrites the
  header for the chosen licence (verified for 0BSD, MIT and NONE; the 0BSD package builds).
- token-deployer-ui (now through sui-token-client) defaults to 0BSD; CC0-1.0 stays selectable.
- The Move bytecode is unchanged (comments and manifest only).
- Re-verified 2026-10-03: the F9 re-sync point is moot, because sui-token-client generates from the
  pinned template directly.
- Re-verified 2026-10-09: 0BSD is the default and the licence path is unchanged. The non-0BSD path (the
  main trigger of F14) now fails before anything is installed: the generator test "a failure (missing
  licence file) leaves the existing directory untouched" pins it, and a licence name containing `&` is
  written literally. A non-0BSD text is still fetched from the SPDX `main` branch (B.1; F14).

### F14 — `03_create_token.sh` deletes the operator's existing output directory on any failure

**Severity:** Medium (destroys local deployment records in the documented workflow)
**Disposition:** RESOLVED — 1.0.7, commit `7d9c04b`. The text below is the 2026-10-03 finding, kept as
written; its line references are to `ca0e2d7`.
**Where:** `scripts/03_create_token.sh:177, 190` (licence-text failures) and `:280-341` (ten
post-generation checks): `rm -rf "$OUTPUT_DIR"`. CLAUDE.md:139 / README.md:178: "Running again with
the same output directory overwrites the instance. This is the intended workflow for updating."
CLAUDE.md:203: "Commit generated token instances (e.g., `my_token/`) to git."

**Issue (probe-verified):**

- **The probe.** An existing directory containing `IMPORTANT.txt` was used as `--output-dir`, with
  `TOKEN_LICENSE=MIT TOKEN_LICENSE_TEXT_FILE=/nonexistent`. The run exited 1 with "ERROR:
  TOKEN_LICENSE_TEXT_FILE not found", and **the directory and `IMPORTANT.txt` no longer existed**.
- **Twelve sites.** The script deletes `$OUTPUT_DIR` wholesale at 12 sites, whether or not this run
  created it.
- **Easy triggers.**
  - A non-0BSD licence whose SPDX text cannot be fetched: a typo such as `Apache2.0` 404s, or the
    network is down.
  - A missing `TOKEN_LICENSE_TEXT_FILE`.
  - Any token value that trips the placeholder checks: a name containing `&` (probe), the substring
    `TEMPLATE`, or an `X…X` token.
- **What is lost.** Re-running into an instance directory is the documented update path, so a
  failure wipes:
  - its committed `deployments.md`;
  - `scripts/` and `.env.<network>` (the IDs `publish.sh` saved: package, TreasuryCap, MetadataCap,
    UpgradeCap, Currency);
  - any other files the operator keeps there;
  - and, if the instance directory is a repository root, its `.git`.

**Impact:**

- Loss of local deployment records and possibly unpushed history.
- On-chain state is intact, and the IDs are recoverable from the chain with effort.
- For a mainnet token whose `TreasuryCap` ID was only recorded locally, recovery means searching the
  deployer's transactions.

**Remediation / evidence:**

- Generate into a fresh temporary directory (`mktemp -d`), validate there, then move the generated
  files into place (or `rsync` without `--delete`), and remove only the temporary directory on
  failure.
- Never `rm -rf` a path the run did not create.
- Refuse an `--output-dir` that is `/`, `$HOME`, `.` or a git work-tree root unless forced.
- Add a test that a failing run leaves a pre-existing directory byte-identical.

**Resolved (re-verified 2026-10-09, `5451c0e`):** `scripts/03_create_token.sh` generates into
`STAGE="$(mktemp -d …)"` with `trap 'rm -rf -- "$STAGE"' EXIT`, so the only path it ever removes is its
own staging directory, and installs into `--output-dir` only after every check passed. Lines 87-92 refuse
`/`, `$HOME`, `.` and a git work-tree root unless `FORCE_OUTPUT_DIR=1`. A licence-text failure now
reports "nothing was changed in $OUTPUT_DIR". `tests/generator.test.sh` pins it ("a failure (missing
licence file) leaves the existing directory untouched", "a validation failure leaves the existing
directory untouched", "re-running updates in place and keeps other files", and one case each for the
refused directories and the override); 38/38 pass, and the suite runs in CI (`generator` job). The old
probe (an existing directory with `IMPORTANT.txt` and a missing licence file) no longer deletes it.

### F15 — The shell generator validates nothing: Move-code injection, placeholder collisions, sed breakage

**Severity:** Low (operator-supplied values; the browser path is validated)
**Disposition:** RESOLVED — 1.0.7, commit `7d9c04b` (OQ6 decided: the rules are ported to shell, with the
same tests as the client). The text below is the 2026-10-03 finding, kept as written.
**Where:** `scripts/03_create_token.sh:34-43` (presence checks only), `:254-272` (`sed -i
"s|b\"TEMPLATE_X\"|b\"$TOKEN_X\"|"` per field), `:278-341` (leftover-placeholder greps);
`scripts/01_preflight.sh` (validates only `TREASURY_ADDRESS`).

**Issue (probe-verified):**

| Input | Result |
| --- | --- |
| `TOKEN_DESCRIPTION='x"; public fun inj(): u64 { 42 } const Z: vector<u8> = b"y'` | exit 0; the generated line is `const DESCRIPTION: vector<u8> = b"x"; public fun inj(): u64 { 42 } const Z: vector<u8> = b"y";`. **`sui move build` succeeds** (warning: unused constant `Z`), so the injected public function would be published |
| `TOKEN_SYMBOL=TEMPLATE_NAME TOKEN_NAME="My Coin"` | exit 0; **`const SYMBOL … = b"My Coin"`** (symbol silently equals the name), because sequential first-match `sed` substitutions collide. This is the same class as sui-token-client F1 |
| `TOKEN_NAME="Tom & Jerry"` | `&` expands to the matched text, leaving `TEMPLATE` in the source. The check aborts with exit 1 and **deletes the output directory** (F14) |

Also unvalidated:

- `TOKEN_DECIMALS` (e.g. `9; const X…`, or values > 18);
- the identifiers (package, module and struct names flow into file paths such as
  `$OUTPUT_DIR/sources/$TOKEN_MODULE_NAME.move` and into `sed` with `/` delimiters);
- `|` and `\` in any value;
- the icon URL scheme.

`deploy_token.sh`'s `CONFIRM` summary shows the input values, not the generated source, so an
injected function is not visible at confirmation.

**Impact:**

- A CLI-deployed coin can carry code or metadata the operator did not intend, including permanent
  symbol and name errors.
- In a white-label or "deploy for a customer" flow where the values come from someone else, a
  crafted description adds arbitrary public functions to the published package.
- The validated browser path and the unvalidated CLI path can produce different coins from the same
  input.

**Remediation / evidence:**

- Validate in `03_create_token.sh` with the same rules as sui-token-client's `assertTokenConfig`.
  Ideally call the client's validator (`node -e`), or port its regexes: identifiers, `SAFE_TEXT`
  (no `"` or `\`), the per-field limits, decimals 0–18 and `https:`/`ipfs:` icons.
- Substitute by line (e.g. `const SYMBOL: vector<u8> = b"…";` keyed on the constant name) in one
  pass, not by sequential placeholder matches.
- Print the generated constants block in the confirmation summary.
- Add negative tests (bats or a shell harness in CI).

**Resolved (re-verified 2026-10-09, `5451c0e`):** `03_create_token.sh` validates every value with the
rules of sui-token-client's `assertTokenConfig` (SAFE_TEXT without `"` or `\`, control characters
refused, per-field limits, decimals 0-18, `https:` icons, identifier and reserved-word rules, a struct name
equal to the uppercased module) before writing, and since 1.0.8 also the supply and metadata policies
(whole-token supply in `u64` range after `x 10^decimals`, fixed supply needs a non-zero mint). It
substitutes by exact token or whole line in one pass, so `&`, `|` and `/` are written literally and an
`X...X` value is not rescanned. It prints the generated constants. The three probe inputs of the table
(Move injection, `TEMPLATE_NAME` symbol, `&` in the name) are cases in `tests/generator.test.sh`
("rejects Move-code injection in a text field, creating nothing", "a symbol that looks like a
placeholder does not collide with the name", "& | / in a value are written literally"); 38/38 pass in CI.
`deploy_token.sh` runs the generator (phase 3) before its `CONFIRM`, so the printed constants block is on screen at confirmation.

### F16 — CLI version pins conflict: preflight demands 1.80; CI and the shipped bytecode use 1.81

**Severity:** Low   **Disposition:** RESOLVED — 1.0.7, commit `7d9c04b`. The text below is the
2026-10-03 finding, kept as written.
**Where:**

- `scripts/01_preflight.sh:100-107` (`${TEMPLATE_SUI_VERSION:-1.80}`, comment "sui testnet-v1.80.x");
- CLAUDE.md:147 ("CLI major.minor (1.80) must match");
- `.github/workflows/move-ci.yml:29-30` and `npm-publish.yml:41-42` (`sui@testnet-v1.81.0`);
- `bytecode/build-info.json` (`"toolchainVersion": "1.81.0"`).

**Issue:**

- `ca0e2d7` moved CI and the shipped artefact to 1.81.0, but preflight and CLAUDE.md still pin 1.80.
- An operator with the CI-tested CLI (1.81.x) is **refused** by `deploy_token.sh` unless they set
  `TEMPLATE_SUI_VERSION=1.81`.
- An operator on 1.80 is accepted but builds the generated source with a toolchain CI no longer
  tests.

**Impact:**

- The OPS-M1 intent ("the CLI version matches the recorded toolchain version") is inverted.
- Operators learn to override the guard, which weakens it for the next real mismatch.

**Remediation / evidence:**

- Read the expected major.minor from `bytecode/build-info.json` (`toolchainVersion`) instead of a
  literal, so CI, the artefact and preflight share one source.
- Update CLAUDE.md, and the "Sui ≥ 1.80" wording in `templates/publish.sh` where it means the pinned
  line.
- Add a CI assertion that preflight's expected version equals `build-info.json`'s.

**Resolved (re-verified 2026-10-09, `5451c0e`):** `01_preflight.sh` reads `toolchainVersion` from
`bytecode/build-info.json` (`1.81.0`) and demands that major.minor (`TEMPLATE_SUI_VERSION` still
overrides deliberately; an unreadable record is a hard failure). CI (`move-ci.yml`, step "The CLI line the
scripts demand is the one the bytecode was built with") fails if `build-info.json` and the installed CLI
disagree, and the workflow pins `sui@testnet-v1.81.0` with a binary sha256. `CLAUDE.md` now names
`build-info.json` as the source. The remaining "Sui >= 1.80" in `templates/publish.sh:128` is a
statement about the CLI behaviour that requires `test-publish`, not a pin.

### F17 — `deploy_token.sh` OPS gaps: unconfirmed TreasuryCap transfer, unverified burn, IDs not persisted

**Severity:** Low   **Disposition:** RESOLVED — 1.0.7, commit `7d9c04b` (policy-aware since 1.0.8,
`5451c0e`); two weaknesses that remain are F21 and F22. The text below is the 2026-10-03 finding, kept as
written.
**Where:** `scripts/deploy_token.sh:269-288` (phase 7 `sui client transfer` of the `TreasuryCap`),
`:238-266` (phase 6b), `:157-210` (IDs parsed into variables only), `:290+` (summary to stdout).

**Issue / Impact:**

- **Transfer without its own confirmation.** Phase 7 irreversibly transfers mint authority to
  `TREASURY_ADDRESS` without a confirmation of its own. OPS lens: "one confirmation must not silently
  cover a later irreversible step". The address is format-checked by preflight and shown before
  `CONFIRM`, which narrows but does not close this.
- **Burn not verified.** After `BURN`, success is inferred from the CLI exit code. The script does not
  check that the `UpgradeCap` no longer exists, unlike `publish.sh` (baseline S2 still open).
- **IDs not persisted.**
  - Package, TreasuryCap, MetadataCap, UpgradeCap and Currency IDs live only in shell variables and
    stdout.
  - A terminal crash after publish leaves the operator to recover them from the chain.
  - A re-run publishes a **second** coin: no resume, unlike `publish.sh`.
  - Recovery commands are printed per failure (good), but `deployments.md` is not filled in.
- **Substring type matching.** `TREASURY_CAP_ID` and `UPGRADE_CAP_ID` are selected with
  `test("TreasuryCap")` / `test("UpgradeCap")` (substring), not exact types as in `publish.sh`.
  Harmless for a single-module publish.

**Remediation / evidence:**

- Add a typed confirmation that names the treasury address before phase 7 (and a mainnet double
  guard).
- Verify the burn by object non-existence.
- Write IDs to `$OUTPUT_DIR/.env.<network>` after each step (reuse `publish.sh`'s helpers), and fill
  in `deployments.md`.
- Use exact type matching.

**Resolved (re-verified 2026-10-09, `5451c0e`):**

- **Transfer.** Phase 7 has its own typed confirmation (`TRANSFER`; on mainnet the first 10 characters of
  the treasury address), declining leaves everything with the deployer, and the new owner is re-read
  on-chain (`deploy_token.sh:349-367`). With a fixed supply there is no `TreasuryCap` to hand over.
- **Burn.** Phase 6b asks for `BURN` separately and, after the call, requires that the `UpgradeCap` no
  longer exists (`:317-323`; the weakness of that check is F22).
- **IDs.** Every ID is written to `$OUTPUT_DIR/.env.<network>` as it appears (`record`), and a second run
  against a recorded package refuses to publish a second coin (`:177-190`). `deployments.md` is still
  filled in by hand; the record file is the machine copy (as for `publish.sh`).
- **Types.** The capabilities and `Currency` are selected with `endswith($t)` on the exact type, as in
  `publish.sh`.
- **Not run:** the pipeline end to end on testnet (needs a funded keystore and WAL; S1). The CLI behaviour
  its parsing relies on was exercised through the localnet runs of the generated `publish.sh`.

### F18 — Source hygiene: an unused alias in the non-test build

**Severity:** Info   **Disposition:** RESOLVED — 1.0.8, commit `5451c0e` (the module's imports were
rewritten with the policy change). The text below is the 2026-10-03 finding, kept as written.
**Where:** `sources/sui_token_template.move:46` (`use sui::coin_registry::{Self, Currency,
MetadataCap};`).

`MetadataCap` is used only by test code, so `sui move build` warns (`Unused 'use' of alias
'MetadataCap'`), and every generated coin inherits the warning. Changing it would change
`sourceSha256` (and, if the import set changes, possibly the bytecode). Fold it into the next
deliberate template release, together with F6's template-level option if adopted.

**Resolved (re-verified 2026-10-09):** F6's template-level option was adopted in 1.0.8. The non-test
imports are now `use sui::coin::TreasuryCap;` and `use sui::coin_registry;`; `Coin`, `Currency` and
`MetadataCap` are `#[test_only]` imports. `sui move build` is clean of the alias warning. The bytecode and
`sourceSha256` changed with the release as expected (`build-info.json`).

### F19 — Documentation and packaging drift since the baseline

**Severity:** Info   **Disposition:** RESOLVED — 1.0.7 (`7d9c04b`) and 1.0.8 (`5451c0e`); the last bullet
(the `exports` layout contract) is carried to F23. The text below is the 2026-10-03 finding, kept as
written.

- CLAUDE.md:147 pins 1.80 (F16).
- The `npm-publish.yml` header says "type-check + test + build". There is no type-check or build
  script (`--if-present` skips them), while the real gates (`sui move test`, bytecode `--check`) are
  not named.
- **The previous `docs/audit/sui-token-template-audit.md` (2026-09-28) is shipped in npm 1.0.6.** It
  describes a 1.0.4 package, a floating framework and token-deployer-ui embedding, all of which are
  now false. This file replaces it; the next release ships the refreshed version.
- CLAUDE.md "Idempotency … overwrites the instance" does not mention that a failure deletes it
  (F14).
- `package.json` `exports` exposes only `bytecode/*` and `package.json`. Consumers reading
  `sources/` and `templates/` by path rely on the package directory layout rather than on exports.
  sui-token-client does this deliberately; record it as a supported contract.

**Resolved (re-verified 2026-10-09):**

- `CLAUDE.md` no longer pins 1.80: preflight reads `build-info.json` (F16).
- The `npm-publish.yml` header was rewritten in 1.0.7 and the workflow's `verify` job now *is* the Move
  CI workflow (`uses: ./.github/workflows/move-ci.yml`): `sui move test`, the bytecode `--check`,
  shellcheck and the generator tests. The misleading "type-check + test + build" is gone.
- `package.json` `files` no longer includes `docs/` as a whole (changed in 1.0.7): it lists
  `docs/onchain/`, `docs/IMPLEMENTATION_GUIDE.md` and `docs/WALRUS.md`. `npm pack --dry-run` on 1.0.8
  lists no `docs/audit/`, so a stale audit can no longer ship; the 1.0.6 tarball keeps the old file.
- `CLAUDE.md` "Idempotency" now states that a failing run leaves an existing directory byte-identical
  (F14).
- The `exports` layout contract is not written down yet: F23.

### F20 — Positive: a reproducible, attested template artefact and hardened preflight

**Severity:** Positive

- **Reproducible bytecode (D23).**
  - `build-bytecode.sh` builds with `sui move build` (never the instrumented test build) and checks
    the `a11ceb0b` magic.
  - It records the toolchain, build env, framework revision, source hash and module hash.
  - `--check` runs in Move CI and in npm `verify`, and reproduced the shipped bytes at this review
    (re-verified 2026-10-09: `96298cca…`, 931 bytes, toolchain 1.81.0, `Move.lock` unchanged).
- **Pinned toolchain in CI.** The `suiup` installer is pinned by URL and **sha256**, and the CLI by
  exact version (`testnet-v1.81.0`); no piped installers.
- **Preflight (OPS-M1).** Hard failures on an active-env mismatch, a **chain-identifier** mismatch
  (`4c78adac` / `35834a8a`) and a CLI major.minor mismatch, read from `build-info.json` (F16).
- **Irreversible steps (OPS-M3).** A mainnet double guard (`MAINNET_CONFIRM=1`, exit 78 when
  skipped); `CONFIRM` before publish; a **separate `BURN`** confirmation, where declining keeps the
  cap and prints the later command.
- **Hygiene (OPS-M2, OPS-M5).** `scripts/*.env.sh` git-ignored (`dad4208`); generated packages ignore
  `.env*`; `set -euo pipefail`; shellcheck in CI; recovery commands printed after each failing
  signing step.
- **Release.** npm OIDC trusted publishing with provenance (1.0.6 verified; 1.0.7 and 1.0.8 published
  the same way on 2026-10-09 with SLSA v1 attestations); tag = version; idempotent publish; SHA-pinned
  actions; `verify` is the full CI workflow (reusable); Dependabot groups npm and Actions weekly
  (`3abc600`).
- **Generator (new 2026-10-09).** The CLI generator validates, stages and installs atomically (F14,
  F15), pinned by 38 shell tests that run in CI.

### F21 — `deploy_token.sh` summary says the `UpgradeCap` was burned even when the operator declined `BURN`

**Severity:** Low   **Disposition:** DEFERRED (next template release, 1.0.9; gate: pre-mainnet,
Section D — the shell pipeline's future is OQ7)
**Where:** `scripts/deploy_token.sh:299-304` (the declined branch) and `:396` (the summary heredoc).
**Issue:** declining `BURN` keeps the `UpgradeCap` and prints the manual burn command, but the run
continues to phase 8, whose summary hard-codes `UpgradeCap ID: … (burned — package is immutable)`. The
`TOKEN_UPGRADE_CAP_BURNED=yes` record is correctly written only after a verified burn (`:322`), so the
state file is right and the printed summary is wrong.
**Impact:** an operator who declined the burn can read the final summary as proof the package is
immutable while the deployer still holds the `UpgradeCap`. This is the misreport class of F1; it is an
output defect, not a missing control (the typed `BURN` and the verification both work).
**Remediation / evidence:** print the line from the recorded state (`burned — package is immutable`
only when `TOKEN_UPGRADE_CAP_BURNED=yes`, otherwise `kept by the deployer — still upgradeable`), and add
a harness case. Not fixed in this pass (audit only). Found while re-verifying F17 on 2026-10-09 by
reading the script; not exercised live (S1).

### F22 — The burn checks treat any CLI failure as "the object is gone"

**Severity:** Low   **Disposition:** DEFERRED (next template release, 1.0.9; gate: pre-mainnet,
Section D)
**Where:** `templates/publish.sh:86-88` (`is_object_exists`, used at `:227` and `:234`) and
`scripts/deploy_token.sh:317-318`.
**Issue:** both checks read the result of `sui client object <UpgradeCap> --json` as "exists" or
"consumed" from the exit code alone (`publish.sh` discards stderr). A consumed object makes the CLI exit
non-zero with "not found" (observed on localnet, 2026-10-09), but so does an RPC outage, a timeout or a
wrong active environment (the latter is excluded by the env check). In `publish.sh` a failing lookup on a
re-run reaches `UpgradeCap already consumed — package is immutable` (`:234-235`) for a cap that still
exists; in `deploy_token.sh` it reads as "burned and verified gone".
**Impact:** a transient failure can produce a false "immutable" claim, which is what the check exists to
prevent. The burn call itself is correct; the exposure is a reassuring message after an unverifiable
lookup, so the severity stays Low.
**Remediation / evidence:** treat only a not-found response (match the CLI's error text or the gRPC
`NOT_FOUND` status) as consumed, and fail with the CLI output on any other error. Add a stubbed-CLI case
to `tests/generator.test.sh`. Not fixed in this pass.

### F23 — Two documentation leftovers: a stale `CLAUDE.md` and an unwritten `exports` contract

**Severity:** Info   **Disposition:** DEFERRED (next template release, 1.0.9; gate: pre-mainnet, Section D —
documentation matches the code)
**Where:** `CLAUDE.md:70` and `:283` (and the file tree around them); `package.json` `exports`.
**Issue:**

- The file tree lists a `scripts/publish.sh` that does not exist (the per-instance script is
  `templates/publish.sh`), and the "Unit Tests" section still says "Four tests" and lists the four
  names of 1.0.6. The six current tests are described correctly in the "Template Source" section of
  the same file.
- `package.json` `exports` exposes only `bytecode/*` and `package.json`; consumers (sui-token-client)
  read `sources/` and `templates/` by path, which relies on the package directory layout. That was
  asked for as a supported contract in the 2026-10-03 pass (F19) and is not written in `README.md` or
  `SECURITY.md` yet.
**Impact:** a maintainer or a contributor agent is told something false about the tests; a layout change
could break the client's generation, though the client's `check:template` would fail first.
**Remediation / evidence:** correct the file tree and the test list, and state the layout contract (which
paths consumers may read) in the README. No code change.

### F24 — No `npm audit` step in CI or in the publish workflow

**Severity:** Info   **Disposition:** ACCEPTED-RISK (the package has no dependencies; revisit if one is
ever added)
**Where:** `.github/workflows/move-ci.yml`, `npm-publish.yml`; `package-lock.json`.
**Issue:** `AUDIT_TEMPLATE_TS.md` B.TS-3 / TS-M8 require `npm audit --audit-level=high` in CI and in
the publish workflow. Neither workflow runs it (the earlier text of B.2 that said `verify` runs `npm
audit` was wrong).
**Impact:** none today: `package.json` has no `dependencies` or `devDependencies`, the lockfile holds
only the root package, and `npm audit --audit-level=high` reports 0 vulnerabilities (2026-10-09). There
is also no install-time code (no lifecycle script, `overrides` or `allowScripts`; B.TS-2).
**Remediation / evidence:** add the step to the shared workflow if a dependency ever appears; Dependabot
(npm and Actions, grouped weekly) already watches the manifest. Everything else in B.TS-3 holds: lockfile
committed, `npm ci` in the publish job, npm pinned to `11.20.0`, OIDC with provenance.

---

## Section A — Invariant verification matrix

| # | Invariant | Enforced / asserted at | Proven by | Status |
| --- | --- | --- | --- | --- |
| I1 | **Ownership / capability provenance:** `init` creates only the coin's own capabilities (`TreasuryCap` unless the supply is fixed, `MetadataCap` unless the metadata is frozen), all to the publisher | `sui_token_template.move::init_with` | `constants_are_applied`, `mintable_supply_keeps_the_treasury_cap`, `mintable_and_updatable_hands_both_caps_to_the_sender` (1.81.0, 6/6) | HOLDS |
| I2 | Pending `Currency<T>` goes to the registry `0xc` | `builder.finalize` / `finalize_and_delete_metadata_cap` | every test takes the `Currency` from `@0xc` | HOLDS |
| I3 | Name, symbol, decimals immutable after publish | framework `coin_registry` | framework guarantee | HOLDS (framework) |
| I4 | Registration completed on every supported deploy path | `templates/publish.sh`, `deploy_token.sh` phase 6a, sui-token-client finalize | localnet (`publish.sh`, 2026-10-09); `e2e:localnet` and `e2e:testnet` of sui-token-client / token-deployer-ui | HOLDS |
| I5 | Immutability claimed only when the UpgradeCap is consumed | `templates/publish.sh::burn_upgrade_cap`; `deploy_token.sh` phase 6b | localnet run; both verify consumption, but read any CLI failure as "gone" (F22) and the `deploy_token.sh` summary can contradict a declined burn (F21) | HOLDS for the burn; **GAP** in the reporting (F21, F22) |
| I6 | Supply / metadata policy visible in the registry | `init_with` (`make_supply_fixed`, `finalize_and_delete_metadata_cap`) | `constants_are_applied`, `frozen_metadata_deletes_the_metadata_cap`, `fixed_supply_requires_an_initial_mint`; localnet `Currency` read (`Fixed(1000000000)`, `Deleted`) | HOLDS (F6) |
| I7 | **Abilities:** OTW has only `drop`; caps per framework | type definitions | compiler | HOLDS |
| I8 | **Arithmetic / funds / abort codes / events / side-effect-freedom / identity layout** | — | template defines none (the only abort is the framework's `EEmptySupply`, pinned by `fixed_supply_requires_an_initial_mint`) | N/A |
| I9 | Shipped bytecode is reproducible from source + `Move.lock` | `build-bytecode.sh --check` | CI; reproduced 2026-10-09 (`96298cca…`) | HOLDS (npm lacks `Move.lock` — F7) |
| I10 | **Generator inputs validated before reaching Move source** | browser: sui-token-client; CLI: `03_create_token.sh` (ported rules) | `tests/generator.test.sh` (38 cases, in CI) | HOLDS (F15) |
| I11 | **Tooling never destroys data it did not create** | `03_create_token.sh` staging directory, dangerous-directory refusal | `tests/generator.test.sh` failing-run and refusal cases | HOLDS (F14) |
| I12 | CLI version checked against the recorded toolchain | `01_preflight.sh` reads `build-info.json`; CI asserts it matches the installed CLI | inspection; CI step | HOLDS (F16) |
| I13 | **Patch points stay independent:** the constants have distinct defaults, so each is a separate pool entry | `sources/*.move` constants; sui-token-client `gen-template.mjs --check` | CI `check:template`; module carries each default once | HOLDS (F11) |
| I14 | The deployment summary reports the real state of the `UpgradeCap` | `deploy_token.sh` phase 8 | — | **GAP** (F21) |

---

## Section B — Supply-chain, publish-authority & capability matrix

### B.1 Dependency, liveness & coupling

| Dependency | Exact object ID / rev | Fails open or closed if unavailable? | Paths it can block | Notes |
| --- | --- | --- | --- | --- |
| Sui framework (`coin_registry`) | **pinned** `83f11dc8…b059` (`Move.lock`, committed; unchanged since 1.0.6) | n/a | build | not shipped to npm (F7 residual) |
| `CoinRegistry` `0xc` | `0xc` | closed (registration fails; retryable by anyone) | wallet discovery | system object |
| Walrus (icon hosting, `02_upload_image.sh`) | aggregator URL | open (the coin works; the icon breaks) | icon display | blob lifetime must be maintained |
| SPDX licence texts (`raw.githubusercontent.com`) | `main` branch | closed, harmless since 1.0.7 (the generator fails with "nothing was changed", F14) | generation with non-0BSD licences | unpinned remote content; 0BSD is rendered from `templates/LICENSE-0BSD` |
| Sui CLI | CI `testnet-v1.81.0` (sha256-pinned installer and binary); preflight demands the `build-info.json` line | — | build, tests | one source (F16) |
| npm dependencies | none (`package.json` has no dependency; the lockfile holds only the root) | n/a | — | F24 |

#### Format coupling

| Format | Layout | This repo | Consumer | Conformance |
| --- | --- | --- | --- | --- |
| Patch-point constants + identifiers | `DECIMALS=9`, `TEMPLATE_SYMBOL/NAME/DESCRIPTION/ICON_URL`, `INITIAL_SUPPLY=1_000_000_007`, `FIXED_SUPPLY=true`, `FROZEN_METADATA=false`, `sui_token_template` / `SUI_TOKEN_TEMPLATE` | `sources/*.move`, `bytecode/*` | `sui-token-client` `src/template/artifact.ts`, `TEMPLATE_IMPORTED_IDENTIFIERS`; `03_create_token.sh` | sui-token-client `gen-template.mjs --check` (hashes, round trip, unique defaults) |
| Placeholders in shipped templates | `SUI_TOKEN_TEMPLATE`, `XMODULENAMEX`, `XPACKAGENAMEX` (+ `XSTRUCTNAMEX` etc. in docs) | `templates/*` | both generators | sui-token-client `files.ts` generated from this release |
| `bytecode/build-info.json` | `toolchainVersion`, `buildEnv`, `frameworkRev`, `sourceSha256`, `moduleSha256` | `build-bytecode.sh` | sui-token-client; `01_preflight.sh` (toolchain) | checked in the client's CI; read by preflight; CI asserts it matches the CLI |

### B.2 Publish authority, capabilities & secret custody

| Authority | Where | Custody | Gates | Plan |
| --- | --- | --- | --- | --- |
| npm publish | CI `npm-publish.yml` (OIDC; `verify` = the reusable Move CI workflow: `sui move test`, bytecode `--check`, shellcheck, generator tests; then `npm ci`) | GitHub OIDC → npm | every future coin's template | tag-triggered, tag must equal the `package.json` version; idempotent; provenance (1.0.6, 1.0.7, 1.0.8 verified); `npm@11.20.0` pinned |
| Walrus/Sui keys for `deploy_token.sh` | operator keystore | operator | real token deployments | never in source; no CI keys |

CI & release integrity (re-verified 2026-10-09): actions pinned by full SHA (`checkout` v7.0.1,
`setup-node` v7.0.0) · `permissions: contents: read`, `id-token: write` only on the publish job · OIDC
trusted publishing with provenance · tag-gated, idempotent publish · release gate equals CI · Dependabot
(npm, github-actions; grouped, weekly) · no secrets in the workflows · no real-chain job · no test-only
build mode. All hold.

#### B.TS-1 to B.TS-3 (npm packaging rows of `AUDIT_TEMPLATE_TS.md`)

The package publishes no TypeScript; only these rows apply.

| Row | State |
| --- | --- |
| B.TS-1 `files` / `exports` | explicit whitelist (`Move.toml`, `sources/`, `templates/`, `scripts/`, `docs/onchain/`, two guides, `README.md`, `CLAUDE.md`, `AGENTS.md`, `LICENSE`, `SECURITY.md`, `bytecode/`). `npm pack --dry-run`: 33 files, 58.1 kB, no tests, `.env*`, keys, local config or `docs/audit/` (F19). `exports`: `package.json` and the two `bytecode/` files; the `sources/` and `templates/` layout contract is unwritten (F23). No `sideEffects` (nothing is imported) |
| B.TS-2 install-time code | none: no `preinstall`/`install`/`postinstall`/`prepare`/`prepublishOnly`, no `overrides`, no `allowScripts`. The two scripts are `build:bytecode` and `check:bytecode` (manual and CI). `bytecode/` is built with the pinned CLI only by `build-bytecode.sh` |
| B.TS-3 supply-chain gates | lockfile committed; publish job uses `npm ci` and a pinned npm; **no `npm audit` step** (F24, ACCEPTED-RISK: the tree is empty; 0 vulnerabilities); engines `^22.18.0 \|\| >=24.12.0` |

### B.3 `UpgradeCap` custody & immutability policy (generated coins)

| Deploy path | Default | Confirmation | Verification |
| --- | --- | --- | --- |
| `deploy_token.sh` | **burn only on `BURN`** (since `dad4208`; OQ1 decided) | `CONFIRM` (publish) + `BURN` + `TRANSFER` (treasury hand-over) + mainnet `MAINNET_CONFIRM=1` | the cap must no longer exist (since 1.0.7; but see F22, and the summary F21) |
| generated `scripts/publish.sh` | keep unless confirmed | `--confirm-immutable` or `CONFIRM` | the cap must no longer exist (F1; but see F22) |
| sui-token-client (token-deployer-ui) | `packagePolicy: 'immutable'` (burn in the publish PTB) | the user's choice in the UI | transaction effects; the UpgradeCap goes to the sender when upgradeable (sui-token-client F2) |

Each generated coin is a new package ID; there is no migration between coins. Supply and metadata
authority is now a deploy-time choice recorded by `init` (F6): a fixed supply leaves no `TreasuryCap`
anywhere; frozen metadata leaves no `MetadataCap`; the remaining caps' custody is OQ2.

### B.4 Permissionless & griefing surfaces

| Function | Attacker controls | Impact | Mitigation |
| --- | --- | --- | --- |
| `finalize_registration` on someone's pending coin | timing only | none (completes registration) | — |
| Look-alike coins generated by anyone | name, symbol, icon | phishing on the social layer | wallets and UIs should key on the full coin type, not the symbol |
| Values fed to the CLI generator by a third party (white-label) | Move source | injected functions; wrong permanent metadata | validated with the client's rules, written literally (F15) |

### B.5 Replay protection & event semantics

N/A — no consume or grant flows, and no events defined by the template (framework registry events
apply).

### B.OPS-1 Runbook linkage

The deploy runbook lives in README / `docs/IMPLEMENTATION_GUIDE.md` (`deploy_token.sh` phases;
`publish.sh` per instance). Both paths write `.env.<network>` per step (F17); `deployments.md` is the
by-hand human record. No chain-signing job runs in CI.

---

## Section C — Test-coverage & hermetic/live split

### C.1 Coverage grade — B+ (6/6 Move; 38/38 shell; bytecode reproducibility checked; `deploy_token.sh` and live paths not hermetic)

| Dimension | Assessment |
| --- | --- |
| Happy path | A — `init` outputs and destinations for every policy combination; reproducible bytecode |
| Error path / abort codes | A — the only abort is the framework's `EEmptySupply` (fixed supply with nothing minted), pinned by `fixed_supply_requires_an_initial_mint`; 16 generator rejection cases |
| Boundary / edge | B+ — `u64` supply boundary, zero supply, leading zeros, injection, collisions and failing-run cases are tested (38); `is_object_exists` / burn-check failure modes are not (F22) |
| Security-relevant | B+ — capability provenance and registry-recorded policy tested; registration and immutability verified on localnet (not hermetic); the generator's validation and non-destruction are pinned in CI |

Counts at 2026-10-09 (`5451c0e`): `sui move test --build-env testnet` **6 passed**; `bash
tests/generator.test.sh` **38 passed, 0 failed**; `build-bytecode.sh --check` matches; shellcheck runs in CI
only.

### C.2 Hermetic vs. live paths

| Path | Hermetic unit test? | Deferred to | Tracking |
| --- | --- | --- | --- |
| `init` outputs and policies | yes | — | inline tests (6) |
| Shipped bytecode = fresh build | yes (`--check`) | — | I9 |
| `03_create_token.sh` validation and failure behaviour | yes (shell harness, CI) | — | F14, F15 |
| `finalize_registration`, `set_icon_url`, `make_immutable` | no (needs the system registry `0xc`) | localnet | verified 2026-10-09 with generated `publish.sh` (fixed/frozen and mintable/updatable coins) |
| Registry records of a patched coin | no | localnet / testnet | sui-token-client `e2e:localnet` and token-deployer-ui `e2e:testnet` (both PASS 2026-10-09) |
| `deploy_token.sh` end to end | no | testnet with Walrus | S1 (maintainer; funded keystore and WAL) |

---

## Section D — Deployment-readiness gates

### pre-localnet

- [x] compiles; 6/6 tests green; bytecode reproducible — CI `move-ci.yml` and the npm `verify` job
- [x] no arithmetic, no custom caps; `SECURITY.md` present (shipped in the tarball)
- [x] the generator never deletes pre-existing data — F14 (RESOLVED 1.0.7; `tests/generator.test.sh`)
- [x] the generator validates its inputs (same rules as sui-token-client) — F15 (RESOLVED 1.0.7)

### pre-testnet

- [x] the docs and dev sites install a release carrying the on-chain docs — F12
- [x] generated `publish.sh` verified on localnet (F1; re-run 2026-10-09)
- [x] the sui-token-client coupling pinned and checked — F9
- [x] preflight CLI pin derived from `build-info.json` — F16 (RESOLVED 1.0.7)
- [ ] `deploy_token.sh` exercised end to end on testnet (S1) — maintainer-only: needs a funded testnet
  keystore and WAL for the Walrus upload

### pre-mainnet (for tokens generated from it)

- [x] TreasuryCap transfer separately confirmed; burn verified; IDs persisted — F17 (RESOLVED 1.0.7)
- [x] registry-recorded supply and metadata policy — F6 (RESOLVED 1.0.8)
- [ ] `deploy_token.sh` reports the `UpgradeCap` state truthfully and treats only "not found" as consumed
  — F21, F22 (DEFERRED to 1.0.9)
- [ ] `CLAUDE.md` and the README match the code, including the `exports` layout contract — F23 (DEFERRED to
  1.0.9)
- [ ] documented custody for `TreasuryCap` / `MetadataCap` per token (OQ2) — maintainer decision
- [ ] `Move.lock` shipped and carried into generated packages — F7 (DEFERRED; before the first mainnet
  coin from a release)
- [ ] external audit of the template and generators — maintainer item (mainnet)

---

## Cross-project themes

- **Two generators, one rule set.**
  - Both paths validate with the same rules (`assertTokenConfig` in sui-token-client; the shell port in
    `03_create_token.sh`, F15) and substitute by exact token or whole line, so the sequential-placeholder
    collision class is closed in the CLI. Whether to keep two implementations at all is OQ6/OQ7.
- **Supply chain.**
  - Strong: a pinned framework, reproducible bytecode, hash-checked consumption in sui-token-client,
    provenance on every release, a pinned and sha256-checked CLI in CI, and an empty dependency tree.
  - Residual: `Move.lock` absent from npm (F7); no `npm audit` step (F24, empty tree).
- **On-chain-truth boundary.** Supply and metadata guarantees now live in the registry (F6), recorded by
  the coin's `init` in the publish transaction, and the client and scripts only read or follow them.
- **Destructive tooling.** F14 (the only Medium of the 2026-10-03 pass) is RESOLVED; the generator
  removes only its own staging directory. Every repo's scripts should still be checked for `rm -rf` of
  operator-supplied paths.
- **Wire-format coupling.** The patch-point layout and `build-info.json` are the contract with
  sui-token-client; its `check:template` and the 1.0.8 `e2e:localnet` run are the drift detectors (B.1).
- **Chain-access layering / IDs.** The template holds no package IDs (each coin is a new package); the
  client and apps hold none for this repo either.
- **Versioning policy:** pre-v0.2, patch-only bumps: 1.0.7 and 1.0.8 shipped on 2026-10-09 and
  sui-token-client re-pinned each (`check:template`); the next release is 1.0.9, and the docs and dev sites
  take it through their caret. Mainnet re-versioning (2.0.0) is the F8 decision.

## Normative requirements (MUST)

1. `init` MUST create no authority other than the coin's own capabilities (`TreasuryCap<T>` unless the
   supply is fixed, `MetadataCap<T>` unless the metadata is frozen) to the publisher — holds (I1).
2. Every deploy path MUST run `finalize_registration` — holds (I4).
3. Immutability MUST be reported only when the `UpgradeCap` is consumed — holds for the burn on both
   paths; the `deploy_token.sh` summary can contradict a declined burn (I5, I14, F21) and a failed
   lookup reads as "consumed" (F22), so **not yet** in full.
4. Deploy scripts MUST persist capability IDs before any step that can fail — holds for `publish.sh` and,
   since 1.0.7, for `deploy_token.sh` (F17).
5. The patch-point constants and identifiers MUST stay distinct and unchanged unless both generators and
   their checks change together — holds (I13).
6. Supply and metadata guarantees offered to users MUST be recorded in the registry — holds since 1.0.8
   (I6, F6).
7. Tooling MUST NOT delete files or directories it did not create — holds (I11, F14).
8. Every generator MUST validate token values with the published rule set before they reach Move source —
   holds for both (I10, F15).
9. The preflight CLI pin MUST equal the toolchain that built and tested the shipped artefact — holds
   (I12, F16).
10. **(new 2026-10-09)** The supply and metadata policy MUST be applied in the publish transaction itself,
    never in a later one — holds (`init_with`; F6).
11. **(new)** Release MUST be gated on the same checks as CI, and the shipped bytecode MUST equal a fresh
    build — holds (`verify` = reusable Move CI; `--check`).
12. **(new, TS-M7/M8)** The package MUST publish only whitelisted files, carry no install-time code, and
    gate on `npm audit` — files and install-time code hold (B.TS-1/2); the audit gate is absent with an
    empty tree (F24, ACCEPTED-RISK).

**OPS lens baseline:**

| ID | Holds? | Evidence |
| --- | --- | --- |
| OPS-M1 | yes (env, chain id and CLI checked; the CLI pin comes from `build-info.json`) | F16, F20 |
| OPS-M2 | yes (`set -euo pipefail`; shellcheck in CI; env files git-ignored) | F20 |
| OPS-M3 | partial (no dry-run mode; separate `CONFIRM`, `BURN`, `TRANSFER` and the mainnet guard; the burn and the transfer default to "keep"; the summary after a declined burn is wrong — F21) | F17, F21 |
| OPS-M4 | yes (`--json` + `jq`; exact `endswith` type matching in both scripts; aborts on a missing ID) | F17 |
| OPS-M5 | yes (recovery printed; every ID persisted per step in both paths) | F17 |
| OPS-M6 | N/A for the template (each coin is new); both scripts record per instance in `.env.<network>` | — |
| OPS-M7 | yes (no keys in CI) | — |
| OPS-M8 | yes (no real-chain CI jobs) | — |
| OPS-M9 | yes (scripts require the env, never switch it; `chain-identifier` caching documented) | — |

## Implementation suggestions (SHOULD / MAY)

- **S1** SHOULD run `deploy_token.sh` end to end on testnet before each template release (needs a funded
  keystore and WAL; **not run**).
- **S2** SHOULD verify in `deploy_token.sh` that the UpgradeCap is consumed after phase 6b, as
  `publish.sh` does. **Done in 1.0.7** (F17); making the check specific to a not-found response is F22.
- **S3** MAY add `make_supply_burn_only` as a third supply option (deflationary tokens). Not done.
- **S4** MAY ship `Move.lock` in the npm package to pin the framework used by consumers. **Partly done**
  (committed in `ca0e2d7`; not in `files` — F7).
- **S5** SHOULD generate into a temporary directory and move into place (F14). **Done in 1.0.7.**
- **S6** SHOULD add a shell test harness in CI for `03_create_token.sh`. **Done in 1.0.7**
  (`tests/generator.test.sh`, 38 cases, CI job `generator`).
- **S7** SHOULD source the preflight CLI pin from `bytecode/build-info.json` (F16). **Done in 1.0.7.**
- **S8** (new) SHOULD add a stubbed-CLI case for the burn checks and a summary-state case for a declined
  burn (F21, F22), and a README paragraph on the `sources/` / `templates/` layout contract (F23).

## Open questions (`OQ#`)

1. **OQ1** Should `deploy_token.sh` keep burning the UpgradeCap unconditionally, or offer the same
   explicit choice as the other paths? — **(Decided 2026-09-30, `dad4208`: explicit `BURN`
   confirmation; declining keeps the cap and prints the burn command.)**
2. **OQ2** What is the default custody for `MetadataCap` in `deploy_token.sh` — keep with the
   deployer (today), transfer with the `TreasuryCap`, or delete? With `FROZEN_METADATA` the cap is
   deleted (1.0.8); the question concerns the updatable case.
3. **OQ3** Should "fixed supply" / "frozen metadata" switch to `make_supply_fixed` /
   `delete_metadata_cap` (F6)? — **(Decided 2026-10-09, `5451c0e`: yes, applied inside `init`
   (`make_supply_fixed`, `finalize_and_delete_metadata_cap`) so the registry records them in the publish
   transaction — see F6; coins published before 1.0.8 stay as deployed.)**
4. **OQ4** Pin the framework revision for template builds (commit/ship `Move.lock`)? — **(Decided
   2026-10-02, `ca0e2d7`: committed and recorded in `build-info.json`; shipping it to npm is the F7
   residual.)**
5. **OQ5** Should `Move.toml` `version` track the npm version? (Open; F8. The mainnet re-versioning —
   everything 0.2.0, this package 2.0.0 — is the natural point to decide.)
6. **OQ6** (new) Should the CLI generator call sui-token-client's validator and renderer (one rule
   set, one substitution algorithm), or keep a shell implementation with ported rules (F15)? —
   **(Decided 2026-10-08, `7d9c04b`: a shell implementation with the ported rules, pinned by
   `tests/generator.test.sh`.)**
7. **OQ7** (new) Is the shell pipeline (`deploy_token.sh`) still a supported path now that
   sui-token-client exists, or should it be reduced to the per-instance `publish.sh`? (Open; it is kept
   and maintained in 1.0.7 and 1.0.8. F21 and F22 are only worth fixing if it stays.)

## Risks (residual)

- **Capability custody** of every generated token rests with its deployer; the template cannot
  enforce good custody. A fixed supply and frozen metadata remove the authority instead of guarding it.
- **Icon hosting liveness:** icons on Walrus expire unless renewed (a frozen icon cannot be repointed).
- **Social-layer phishing:** anyone can generate look-alike tokens.
- **Generator coupling:** bytecode patching depends on constant-pool layout. A compiler change could
  alter it; this is caught by `build-bytecode.sh --check` and sui-token-client's `check:template`,
  not prevented.
- **Unverified live pipeline:** `deploy_token.sh` has not been run end to end on testnet this pass (S1);
  its confirmations and parsing are read and exercised through `publish.sh` on localnet only.
- **Misleading output on the shell path:** F21 and F22 can make a package look immutable when it is not.
- **Unpinned licence text:** non-0BSD texts come from the SPDX `main` branch (fails harmlessly since
  1.0.7).

---

## Re-verification log

- 2026-09-28 — first-pass baseline under AUDIT_TEMPLATE.md + AUDIT_TEMPLATE_SUI.md. F1–F5 RESOLVED in
  `6ea9bb0` (generated `publish.sh` verified on localnet); F6–F9 recorded.
- 2026-09-28 (second pass) — F13 (licence → 0BSD) RESOLVED in `506c89a`. The re-sync of
  token-deployer-ui's `files.json` against this checkout was verified locally (111 tests +
  `verify:template` green with `SUI_TOKEN_TEMPLATE_DIR`) and deferred with F9 until the next npm
  release.
- 2026-10-03 (third pass) — re-verified at `ca0e2d7` (tag `v1.0.6`, npm 1.0.6 with provenance).
  - **Lenses:** AUDIT_TEMPLATE.md (2026-10-02) + SUI (2026-09-28) + **OPS (2026-09-30, first
    application)**.
  - **Measured:** Sui 1.81.0: 4/4 tests; `build-bytecode.sh --check` reproduced
    `41511ed4…`; `npm pack` 34 files (no `Move.lock`).
  - **Re-checked:**
    - F1–F5 hold (`publish.sh` unchanged; `deploy_token.sh` finalize present);
    - F9 and F12 → RESOLVED (sui-token-client exact pin and `check:template`; sites on `^1.0.6`);
    - F7 → largely resolved (`Move.lock` committed), residual npm shipping;
    - F6 re-pointed to sui-token-client;
    - F8 still drifts (1.0.0 vs 1.0.6);
    - F11 updated (validation moved to sui-token-client; CLI path excluded).
  - **Decided:** OQ1 (`dad4208`) and OQ4 (`ca0e2d7`).
  - **Probes** on scratch directories (deleted afterwards) confirmed:
    - F14: a pre-existing directory and its sentinel file deleted on a licence error;
    - F15: Move injection compiles with `sui move build`; symbol/name collision; `&` breakage.
  - **New:** F14–F20; OQ6–OQ7; S5–S7.
  - **No findings resolved:** by maintainer instruction this pass only records findings. Remediation,
    including single-solution fixes under the resolve-inline rule, is to be applied separately, with
    each disposition moved to RESOLVED and the diff cited.
  - **Not run:** testnet `deploy_token.sh` (egress) and shellcheck (not installed; runs in CI).
- 2026-10-09 (re-verification) — re-verified at `5451c0e` (tag `v1.0.8`, npm 1.0.8, SLSA v1
  provenance; 1.0.7 and 1.0.8 both published 2026-10-09).
  - **Lenses:** AUDIT_TEMPLATE.md (2026-10-08) + SUI (2026-09-28) + OPS (2026-10-08) + the TS lens's npm
    packaging rows (2026-10-08; B.TS-1/2/3, TS-M7/M8). The VUE, SUI_CLIENT, IMG and other lenses do not
    apply (no TypeScript, no client code, no image).
  - **Measured:** Sui 1.81.0: 6/6 Move tests; `build-bytecode.sh --check` reproduced `96298cca…`
    (931 bytes); `tests/generator.test.sh` 38/38; `npm pack --dry-run` 33 files, no `Move.lock`, no
    `docs/audit`; `npm audit --audit-level=high` 0 vulnerabilities; the generated `publish.sh` run on a
    throwaway localnet for a fixed/frozen coin and a mintable/updatable coin (registry `Currency` reads
    `Fixed(1000000000)` / `Deleted`, and `Unknown` / `Claimed`).
  - **Resolved:** F6 (supply and metadata policies applied in `init`, 1.0.8 `5451c0e`), F14, F15, F16, F17
    (1.0.7 `7d9c04b`), F18 (went with the 1.0.8 rewrite), F19 (carried to F23); F9 and F12 re-checked
    against the 1.0.8 pins and lockfiles.
  - **Still deferred:** F7 residual (`Move.lock` not in npm; pre-mainnet), F8 (OQ5; mainnet
    re-versioning).
  - **New:** F21 (summary misreports a declined burn), F22 (any CLI failure reads as "consumed"), F23
    (stale `CLAUDE.md` test list; unwritten `exports` layout contract), F24 (no `npm audit` step;
    ACCEPTED-RISK, empty tree); S8; B.TS-1/2/3 rows; invariants I13/I14.
  - **Decided:** OQ3 (apply in `init`), OQ6 (shell port of the rules). OQ2, OQ5, OQ7 remain open.
  - **Not run:** `deploy_token.sh` on testnet (funded keystore and WAL; S1) and shellcheck (not installed
    here; green in CI).
