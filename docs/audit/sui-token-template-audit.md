# Security Audit — `sui-token-template`

**Classification:** Internal security review (initial audit — awaiting external review)
**Project:** `repos/sui-token-template` — generic Sui coin template, generator and deployment pipeline (Sui Move + shell)
**Project type:** Move package
**Template:** AUDIT_TEMPLATE.md (2026-09-28) + AUDIT_TEMPLATE_SUI.md (2026-09-28)
**Package:** `sui_token_template` v1.0.0 (`Move.toml`; npm `@meddleware/sui-token-template` 1.0.4); edition 2024; framework rev floats (Move.lock git-ignored — F7)
**Deployment status:** never published itself (it is a template); every generated coin is an independent package; consumed by `@meddleware/token-deployer-ui` (bytecode + source templates, via npm 1.0.4)
**Review date:** 2026-09-28
**Reviewer:** Internal review (Move contract reviewer)
**Severity ceiling:** Medium — the template itself holds no funds and creates only the coin's own capabilities, but every coin generated from it inherits its capability model, and its deployment scripts decide supply, metadata and upgrade custody for real tokens.
**Status:** first-pass baseline

---

## Executive summary

The Move source is minimal and sound: `init` (one-time witness) registers the coin via
`coin_registry::new_currency_with_otw`, finalises the builder keeping a live `MetadataCap`, and
transfers **only** `TreasuryCap<T>` and `MetadataCap<T>` to the publisher. It has no fees, events,
abort codes or extra authority. The patch-point constants are deliberately distinct so the browser
deployer can patch bytecode safely. 4/4 tests pass.

The risk was in the **scripts that ship with every generated coin**, and it has been fixed inline:

- **F1 (Medium)** — the per-instance `scripts/publish.sh`:
  - never parsed its last argument, so `publish.sh testnet --confirm-immutable` silently ignored the
    flag;
  - its "already published" path used a JSON path the Sui 1.80 CLI no longer emits, so it
    **reported a live `UpgradeCap` as consumed ("package is immutable")**;
  - its post-burn check could never pass, exiting after an irreversible burn *before* saving any IDs;
  - it saved IDs only at the end, failed silently and could not publish to localnet.
  It has been rewritten and verified end to end on localnet.
- **F2 (Medium)** — `deploy_token.sh` never ran `coin_registry::finalize_registration`, leaving
  coins undiscoverable by wallets. It now does.
- **F3–F5** — documentation claimed the `MetadataCap` is deleted (it is not), that the UpgradeCap is
  always burned, and recommended broken verification commands. There was also no `SECURITY.md`.

Remaining items are decisions (**OQ1–OQ5**), plus one fix that belongs in `token-deployer-ui` (F6):
fixed-supply and frozen-metadata choices freeze the capabilities instead of using the registry's
`make_supply_fixed` / `delete_metadata_cap`, so the registry does not record them.

---

## Threat model / trust boundaries

| Authority / actor | Holds / proves | Can do | Bounded by |
| --- | --- | --- | --- |
| Coin publisher | `TreasuryCap<T>`, `MetadataCap<T>`, `UpgradeCap` (at publish) | mint/burn any amount; change description/icon; upgrade the coin package | custody choices at deploy time (B.3, OQ2) |
| Anyone | nothing | `finalize_registration` for any pending coin | framework (harmless: completes registration) |
| Generator (`03_create_token.sh`, token-deployer-ui) | template source/bytecode | substitute names/constants | `SAFE_TEXT`, length caps, parity tests (token-deployer-ui) |
| npm / template maintainer | publish rights for `@meddleware/sui-token-template` | change what every future coin is built from | OIDC publish from tagged commits; token-deployer-ui pins a version and parity-tests it |

**Primary trust anchor:** the one-time witness and the framework `coin_registry` — only the
capabilities `init` hands out exist.

### Capabilities & shared objects (Move lens)

| Object / type | Minted / created by | Holder / custodian | Authority it confers | Compromise / misuse impact | Immutability / rotation plan |
| --- | --- | --- | --- | --- | --- |
| `TreasuryCap<T>` | `init` | publisher → treasury (deploy_token.sh) or frozen (token-deployer "fixed") | unlimited mint / burn | inflation, supply collapse | `make_supply_fixed` / `make_supply_burn_only` (recommended, F6) or freeze; else custody by multisig |
| `MetadataCap<T>` | `init` (`builder.finalize`) | publisher (all paths unless frozen) | description + icon URL | phishing icon/description on a live token | `delete_metadata_cap` (recommended, F6) / freeze / multisig (OQ2) |
| `UpgradeCap` | publish | publisher → burned (deploy_token.sh always; publish.sh on confirm; token-deployer default) | replace coin package code | arbitrary logic change (e.g. new mint paths are impossible without the cap, but upgrades can add functions) | burn — verified by cap consumed (F1) |
| `Currency<T>` | `init` → pending at `0xc`; shared after `finalize_registration` | coin registry | registry record (metadata, supply state) | — | managed by the framework |
| `CoinRegistry` `0xc` (external) | system | shared | registration | — | n/a |

## Severity scale

Critical / High / Medium / Low / Info / Positive.

## Scope

- **In scope:** `sources/sui_token_template.move`, `Move.toml`, `package.json`,
  `scripts/{01_preflight,02_upload_image,03_create_token,deploy_token}.sh`, `templates/*`
  (`publish.sh`, `CLAUDE.md`, `AGENTS.md`, `README.md`, `deployments.md`, `gitignore`), `README.md`,
  `CLAUDE.md`, `AGENTS.md`, `docs/*`; coupling with `token-deployer-ui` (read-only).
- **Out of scope:** `token-deployer-ui` implementation (own audit); already generated coins; Walrus.
- **Environment:** Sui CLI 1.80.0; `sui move test --build-env testnet` → 4/4; generated `publish.sh`
  exercised on a throwaway localnet (full run with the flag last, idempotent re-run, unknown-flag and
  wrong-env refusals); gRPC `getCoinMetadata` checked against the finalised localnet coin.

---

## Findings

### F1 — Per-instance `publish.sh` could misreport immutability and lose deployment state
**Severity:** Medium   **Disposition:** RESOLVED
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

### F2 — `deploy_token.sh` never finalised coin registration
**Severity:** Medium   **Disposition:** RESOLVED
**Where:** `scripts/deploy_token.sh` phase 6 → 6b.
**Impact:** CLI-deployed coins stayed pending at `0xc`; wallets and explorers could not resolve their
metadata.
**Remediation / evidence:** commit `6ea9bb0` — phase 6a calls `coin_registry::finalize_registration`
with type-exact extraction of the pending `Currency<T>`, with manual-recovery instructions; the
summary now reports the `MetadataCap` and `Currency` IDs. Not run live (the pipeline needs a Walrus
upload); the call and extraction are identical to the localnet-verified `publish.sh` step.

### F3 — Documentation misstated the capability model and verification
**Severity:** Low   **Disposition:** RESOLVED
**Issue:**
- `README.md` said the `MetadataCap` is deleted and that no one can ever change the icon.
- It said the UpgradeCap is "burned during initial deployment" by `scripts/publish.sh`.
- `CLAUDE.md` / `AGENTS.md` described a `scripts/publish.sh` that does not exist.
- The generated `CLAUDE.md` / `AGENTS.md` / `deployments.md` verified immutability with `.data.owner`.
- The docs recommended deprecated JSON-RPC `suix_getCoinMetadata`.
- The implementation guide claimed metadata lookups return null by design.
**Evidence:** commit `6ea9bb0` (plus the `templates/CLAUDE.md` icon-URL correction in the docs
commit). Verification is now "UpgradeCap no longer exists" and gRPC `getCoinMetadata`, which was
checked on localnet to return the registry `Currency`.

### F4 — No `SECURITY.md`
**Severity:** Low   **Disposition:** RESOLVED — commit `6ea9bb0` (S8); `package.json` `files`
now ships it.

### F5 — Source doc comments inaccurate
**Severity:** Info   **Disposition:** RESOLVED — commit `6ea9bb0`. The comments claimed `init` uses
an empty icon URL (it uses the `ICON_URL` constant) and that the UpgradeCap is always burned. The
bytecode is unchanged: only comments were edited.

### F6 — Fixed supply / frozen metadata are not recorded in the coin registry
**Severity:** Low   **Disposition:** DEFERRED (fix belongs in `token-deployer-ui`; OQ3)
**Where:** `token-deployer-ui/src/lib/buildPublishTx.ts` finalize PTB freezes the `TreasuryCap` /
`MetadataCap` with `transfer::public_freeze_object`.
**Issue:** freezing makes the caps unusable. The registry's `Currency<T>` nevertheless keeps
`SupplyState::Unknown` and a live `metadata_cap_id`, so wallets and indexers reading the registry
(`is_supply_fixed`, `is_metadata_cap_deleted`) do not see the guarantees the user chose.
**Remediation:** after `finalize_registration`, call
`coin_registry::make_supply_fixed<T>(&mut Currency<T>, TreasuryCap<T>)` (or `make_supply_burn_only`)
and `coin_registry::delete_metadata_cap<T>(&mut Currency<T>, MetadataCap<T>)`. These are
framework-documented and consume the caps.

### F7 — Framework revision not pinned
**Severity:** Info   **Disposition:** ACCEPTED-RISK (OQ4)
`Move.lock` is git-ignored and not shipped in the npm package, so `regen:template` in
`token-deployer-ui` compiles against whatever framework the resolver picks. This is mitigated by
`verify:template` / parity tests and the magic-byte check.

### F8 — Version drift
**Severity:** Info   **Disposition:** DEFERRED (OQ5) — `Move.toml` 1.0.0 vs npm 1.0.4 (tags
v1.0.0–v1.0.2, v1.0.4). Versions deliberately not changed in this pass.

### F9 — Coupling with `token-deployer-ui` must be re-synced after the next template release
**Severity:** Info   **Disposition:** DEFERRED (tracked) — `token-deployer-ui` embeds npm 1.0.4's
bytecode and source files (`src/move-template/*`, `src/template-src/files.json`). After publishing
this pass's changes, bump the dependency there, then run `regen:template`, `sync:template` and
`verify:template`. The Move bytecode is unchanged; the shipped `templates/publish.sh` and docs are
not.

### F10 — `init` creates no authority beyond the two capabilities
**Severity:** Positive — tests `test_treasury_cap_transferred_to_sender`,
`test_metadata_cap_present_in_sender`, `test_currency_transferred_to_registry_after_init`.

### F11 — Patch-point constants are safe to patch independently
**Severity:** Positive — distinct values (no constant-pool deduplication); `token-deployer-ui`
enforces `SAFE_TEXT`, 512-char caps and decimals 0–255 before patching.

### F12 — docs./dev. sites import the canonical on-chain docs only after npm publication
**Severity:** Info   **Disposition:** DEFERRED (exact remediation below)
**Where:** `repos/docs` and `repos/dev` — `scripts/gen-onchain.mjs` resolves `@meddleware/sui-token-template` from
`node_modules`.
**Issue:** the canonical `docs/onchain/*` pages ship in `@meddleware/sui-token-template` from the next release after 1.0.4 (1.0.4, installed today, predates them; the version bump is the maintainer's call — OQ5). Until
that version is on npm and installed in both sites, their builds render placeholder pages for this
package (by design — builds never fail). Verified locally with `ONCHAIN_DOCS_ROOT=..` (all pages
imported, no dead links, lint/type-check green).
**Remediation:** publish the next `@meddleware/sui-token-template` release (push the release tag; `npm-publish.yml`), then in both
`repos/docs` and `repos/dev`: `npm install -D @meddleware/sui-token-template@<next>` → commit `package.json` +
`package-lock.json` → `npm run build` and confirm the `[gen:onchain]` log shows imported pages
(no placeholder) → release the site images.

### F13 — Licence: CC0-1.0 replaced by 0BSD
**Severity:** Info   **Disposition:** RESOLVED (owner decision: CC0 usages become 0BSD) — commit
`506c89a`. `LICENSE`, `Move.toml`, `package.json`, the source SPDX header, README and
IMPLEMENTATION_GUIDE are 0BSD. `scripts/03_create_token.sh` defaults `TOKEN_LICENSE=0BSD`, renders
`templates/LICENSE-0BSD` with the year and `TOKEN_COPYRIGHT_HOLDER` (default: project or token
name), and always rewrites the header for the chosen licence (verified for 0BSD, MIT and NONE; the
0BSD package builds). `token-deployer-ui` defaults its licence picker to 0BSD (`0871b74`); CC0-1.0
stays selectable there. The Move bytecode is unchanged (comments and manifest only). Its embedded
`src/template-src/files.json` still carries the CC0 text until the F9 re-sync (generated packages
already get the chosen licence, because the generator rewrites header and manifest).

---

## Section A — Invariant verification matrix

| # | Invariant | Enforced / asserted at | Proven by | Status |
| --- | --- | --- | --- | --- |
| I1 | **Ownership / capability provenance:** only `TreasuryCap` + `MetadataCap` are created, both to the publisher | `sui_token_template.move::init` | `test_treasury_cap_*`, `test_metadata_cap_present_in_sender` | HOLDS |
| I2 | Pending `Currency<T>` goes to the registry `0xc` | `builder.finalize` | `test_currency_transferred_to_registry_after_init` | HOLDS |
| I3 | Name, symbol, decimals immutable after publish | framework `coin_registry` | framework guarantee | HOLDS (framework) |
| I4 | Registration completed on every supported deploy path | `templates/publish.sh`, `deploy_token.sh` | localnet run (publish.sh); code review (deploy_token.sh) | HOLDS (publish.sh live-verified; deploy_token.sh code-only) |
| I5 | Immutability claimed only when the UpgradeCap is consumed | `templates/publish.sh::burn_upgrade_cap` | localnet run | HOLDS |
| I6 | Supply / metadata policy visible in the registry | — (token-deployer freezes caps) | — | GAP (F6) |
| I7 | **Abilities:** OTW has only `drop`; caps per framework | type definitions | compiler | HOLDS |
| I8 | **Arithmetic / funds / abort codes / events / side-effect-freedom / identity layout** | — | template defines none | N/A |

---

## Section B — Supply-chain, publish-authority & capability matrix

### B.1 Dependency, liveness & coupling

| Dependency | Exact object ID / rev | Fails open or closed if unavailable? | Paths it can block | Notes |
| --- | --- | --- | --- | --- |
| Sui framework (`coin_registry`) | unpinned (F7) | n/a | build | framework-only dependency |
| `CoinRegistry` `0xc` | `0xc` | closed (registration fails; retryable by anyone) | wallet discovery | system object |
| Walrus (icon hosting, `02_upload_image.sh`) | aggregator URL | open (coin works; icon breaks) | icon display | blob lifetime must be maintained |

**Format coupling**

| Format | Layout | This repo | Consumer | Conformance |
| --- | --- | --- | --- | --- |
| Patch-point constants + identifiers | `DECIMALS=9`, `TEMPLATE_SYMBOL/NAME/DESCRIPTION/ICON_URL`, `sui_token_template` / `SUI_TOKEN_TEMPLATE` | `sources/*.move` | `token-deployer-ui` `TEMPLATE_DEFAULTS` / `TEMPLATE_IDENTIFIERS`, `03_create_token.sh` | `verify:template`, `tests/templateArtifact.test.ts`, `tests/templateParity.test.ts` (token-deployer-ui) |
| Placeholders in shipped templates | `SUI_TOKEN_TEMPLATE`, `XMODULENAMEX`, `XPACKAGENAMEX` (+ `XSTRUCTNAMEX` etc. in docs) | `templates/*` | both generators | parity test (token-deployer-ui) |

### B.2 Publish authority, capabilities & secret custody

| Authority | Where | Custody | Gates | Plan |
| --- | --- | --- | --- | --- |
| npm publish | CI `npm-publish.yml` (OIDC, verify job runs `sui move test`) | GitHub OIDC → npm | every future coin's template | tag-triggered; idempotent |
| Walrus/Sui keys for `deploy_token.sh` | operator env | operator | real token deployments | never in source |

### B.3 `UpgradeCap` custody & immutability policy (generated coins)

| Deploy path | Default | Confirmation | Verification |
| --- | --- | --- | --- |
| `deploy_token.sh` | always burn (phase 6b) | `CONFIRM` before publish | CLI success (suggestion S2: add consumed-cap check) |
| generated `scripts/publish.sh` | keep unless confirmed | `--confirm-immutable` or `CONFIRM` | cap must no longer exist (F1) |
| token-deployer-ui | `packagePolicy: 'immutable'` (burn in the publish PTB) | user choice in UI | tx effects |

Each generated coin is a new package ID; there is no migration between coins.

### B.4 Permissionless & griefing surfaces

| Function | Attacker controls | Impact | Mitigation |
| --- | --- | --- | --- |
| `finalize_registration` on someone's pending coin | timing only | none (completes registration) | — |
| Look-alike coins generated by anyone | name/symbol/icon | phishing on the social layer | wallets/UIs should key on the full coin type, not symbol |

### B.5 Replay protection & event semantics

N/A — no consume/grant flows and no events defined by the template (framework registry events apply).

---

## Section C — Test-coverage & hermetic/live split

### C.1 Coverage grade — B (4/4)

| Dimension | Assessment |
| --- | --- |
| Happy-path | A — `init` outputs and destinations |
| Error-path / abort codes | N/A — no abort codes |
| Boundary / edge | B — decimals/strings are validated by the generators, not the template |
| Security-relevant | B — capability provenance tested; registration and immutability verified live (not hermetic) |

### C.2 Hermetic vs. live paths

| Path | Hermetic unit test? | Deferred to | Tracking |
| --- | --- | --- | --- |
| `init` outputs | yes | — | inline tests |
| `finalize_registration`, `set_icon_url`, `make_immutable` | no (needs the system registry `0xc`) | localnet | verified 2026-09-28 via generated `publish.sh` |
| `deploy_token.sh` end-to-end | no | testnet with Walrus | S1 |
| Bytecode/source parity | in token-deployer-ui | — | F9 |

---

## Section D — Deployment-readiness gates

### pre-localnet

- [x] compiles; 4/4 tests green — CI `move-ci.yml` and the npm `verify` job
- [x] no arithmetic, no custom caps; `SECURITY.md` present

### pre-testnet

- [ ] docs./dev. sites install the published `@meddleware/sui-token-template` and import its on-chain docs — F12
- [x] generated `publish.sh` verified on localnet (F1)
- [ ] `deploy_token.sh` exercised end-to-end on testnet (S1)
- [ ] token-deployer-ui re-synced to the next template release (F9)

### pre-mainnet (for tokens generated from it)

- [ ] registry-recorded supply / metadata policy (F6)
- [ ] documented custody for `TreasuryCap` / `MetadataCap` per token (OQ2)
- [ ] external audit of the template + generators

---

## Cross-project themes

- **Supply chain:** OIDC npm publish gated by `sui move test`; framework rev unpinned (F7).
- **Wire-format coupling:** patch points and placeholders shared with `token-deployer-ui` (B.1).
- **On-chain-truth boundary:** supply and metadata guarantees must live in the registry (F6), not
  only in UI state.
- **Deployment readiness:** Section D.

## Normative requirements (MUST)

1. `init` MUST create no authority other than `TreasuryCap<T>` and `MetadataCap<T>` to the
   publisher — holds (I1).
2. Every deploy path MUST run `finalize_registration` — holds (I4).
3. Immutability MUST be reported only when the `UpgradeCap` is consumed — holds (I5).
4. Deploy scripts MUST persist capability IDs before any step that can fail — holds for
   `publish.sh` (F1).
5. The patch-point constants and identifiers MUST stay distinct and unchanged unless both generators
   and their parity tests change together — holds.
6. Supply and metadata guarantees offered to users MUST be recorded in the registry — **not yet**
   (F6).

## Implementation suggestions (SHOULD / MAY)

- **S1** SHOULD run `deploy_token.sh` end to end on testnet before each template release.
- **S2** SHOULD verify in `deploy_token.sh` that the UpgradeCap is consumed after phase 6b, as
  `publish.sh` does.
- **S3** MAY add `make_supply_burn_only` as a third supply option (deflationary tokens).
- **S4** MAY ship `Move.lock` in the npm package to pin the framework used by `regen:template`.

## Open questions (`OQ#`)

1. **OQ1** Should `deploy_token.sh` keep burning the UpgradeCap unconditionally, or offer the same
   explicit choice as the other paths?
2. **OQ2** What is the default custody for `MetadataCap` in `deploy_token.sh` — keep with the
   deployer (today), transfer with the `TreasuryCap`, or delete?
3. **OQ3** Should token-deployer-ui switch "fixed supply" / "frozen metadata" to
   `make_supply_fixed` / `delete_metadata_cap` (F6)? Existing tokens would remain as deployed.
4. **OQ4** Pin the framework revision for template builds (commit/ship `Move.lock`)?
5. **OQ5** Should `Move.toml` `version` track the npm version?

## Risks (residual)

- **Capability custody** of every generated token rests with its deployer; the template cannot
  enforce good custody.
- **Icon hosting liveness:** icons on Walrus expire unless renewed.
- **Social-layer phishing:** anyone can generate look-alike tokens.
- **Generator coupling:** bytecode patching depends on constant-pool layout; a compiler change could
  alter it (caught by `verify:template`, not prevented).

---

## Re-verification log

- 2026-09-28 — first-pass baseline under AUDIT_TEMPLATE.md + AUDIT_TEMPLATE_SUI.md. F1–F5 RESOLVED in
  `6ea9bb0` (generated `publish.sh` verified on localnet); F6–F9 recorded.
- 2026-09-28 (second pass) — F13 (licence → 0BSD) RESOLVED in `506c89a`; re-sync of
  `token-deployer-ui`'s `files.json` against this checkout verified locally (111 tests +
  `verify:template` green with `SUI_TOKEN_TEMPLATE_DIR`), deferred with F9 until the next npm release.
