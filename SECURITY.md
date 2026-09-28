# Security Policy

## Scope

This policy covers security issues in:

- The Move template (`sources/sui_token_template.move`) — the coin `init` that every generated token
  package runs: capability issuance (`TreasuryCap`, `MetadataCap`), coin-registry registration, and
  the fixed metadata constants that downstream tools patch in bytecode.
- The generator and deployment scripts (`scripts/03_create_token.sh`, `scripts/deploy_token.sh`) and
  the per-instance publish script shipped to every generated package (`templates/publish.sh`) — as
  they affect capability custody, `UpgradeCap` handling and correct registry finalisation.
- The npm package `@meddleware/sui-token-template`, as consumed by `@meddleware/token-deployer-ui`
  (template source + precompiled bytecode parity).

It does not cover:

- The Sui framework, Move standard library, or the `coin_registry` system module (report to the
  [Sui project](https://github.com/MystenLabs/sui/security)).
- Tokens that have already been generated and published — each is an independent package; their
  capability custody is the deployer's responsibility.
- The operator fee charged by `token-deployer-ui` (implemented in that app's transaction, not here).

## Security model (invariants)

1. **One coin type per package, created once.** The one-time witness guarantees `init` runs exactly
   once; the template defines no mint/burn wrappers — supply is controlled solely by whoever holds
   the `TreasuryCap`.
2. **Both capabilities go to the publisher.** `init` transfers `TreasuryCap<T>` and `MetadataCap<T>`
   to the transaction sender and nothing else; there is no hidden or retained authority.
3. **Name, symbol and decimals are fixed forever** by the coin registry. Description and icon URL are
   editable only by the `MetadataCap` holder (until it is deleted or frozen).
4. **Immutability is explicit.** A generated package is immutable only once its `UpgradeCap` has been
   burned (`0x2::package::make_immutable`) — `deploy_token.sh` always burns it; the per-instance
   `scripts/publish.sh` burns it only with `--confirm-immutable` or an interactive `CONFIRM`, and
   verifies the cap was consumed.
5. **Registration is completed.** `coin_registry::finalize_registration` promotes the pending
   `Currency<T>` to a shared, discoverable object; both deployment paths run it.

## Supported versions

Only the latest published npm version (and the matching git tag) receives fixes. Generated packages
are immutable snapshots and are not patched in place.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Report vulnerabilities by emailing **<security@meddleware.co.uk>**. Include:

- A description of the vulnerability and its impact
- Steps to reproduce or a proof-of-concept (if available)
- The template version / commit SHA you tested against

You will receive an acknowledgement within **3 business days** and a resolution plan within
**14 days** for confirmed issues.

## Disclosure

Once a fix is released, a security advisory will be published on the GitHub repository. Reporters
may be credited by name unless they prefer to remain anonymous.
