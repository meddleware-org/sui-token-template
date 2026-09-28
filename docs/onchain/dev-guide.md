---
title: Token template — developer integration
---

# Token template — developer integration

How the template is consumed by generators, how to deploy a generated coin correctly, and how to
integrate with the resulting coin. See the [API reference](api-reference.md) for the full surface.

## Normative requirements

1. **`finalize_registration` MUST run after publish.** Until it does, `Currency<T>` is pending
   (owned by `0xc`) and wallets/indexers cannot resolve the coin. Anyone may call it:
   `0x2::coin_registry::finalize_registration<T>(0xc registry, pending Currency)`.
2. **Capability custody MUST be decided explicitly at deploy time** — `TreasuryCap` (supply) and
   `MetadataCap` (description/icon) both land with the publisher.
3. **Immutability MUST be verified by the UpgradeCap being consumed**, not by the package object's
   owner (a package is always `Immutable`-owned).
4. **Generators MUST patch only the designated constants.** The distinct placeholder constants
   (`TEMPLATE_SYMBOL`, `TEMPLATE_NAME`, `TEMPLATE_DESCRIPTION`, `TEMPLATE_ICON_URL`, `DECIMALS = 9`)
   and the identifiers `sui_token_template` / `SUI_TOKEN_TEMPLATE` are the contract with
   `@meddleware/token-deployer-ui` (bytecode patching via `@mysten/move-bytecode-template`) and
   `scripts/03_create_token.sh` (source generation). Renaming or merging them breaks both.

## Coupling with `token-deployer-ui`

| Artefact in token-deployer-ui | Derived from | Kept in sync by |
| --- | --- | --- |
| `src/move-template/sui_token_template.mv` + base64 in `template.ts` | compiled template bytecode | `npm run regen:template` (builds from `node_modules/@meddleware/sui-token-template`) |
| `src/template-src/files.json` (downloadable source package) | `Move.toml`, source, `templates/*` | `npm run sync:template`; asserted by `tests/templateParity.test.ts` |
| `TEMPLATE_DEFAULTS` / `TEMPLATE_IDENTIFIERS` | the constants above | `npm run verify:template` |

After publishing a new template version: bump the dependency in token-deployer-ui, then run
`regen:template`, `sync:template` and `verify:template`.

## Deploying a generated package

```bash
# generated package, active env must equal the target network
MYTOKEN_ICON_URL=https://… bash scripts/publish.sh testnet            # prompts before burning
MYTOKEN_ICON_URL=https://… bash scripts/publish.sh testnet --confirm-immutable
```

Each step saves IDs to `.env.<network>`; re-running resumes (no second publish).

## Integrating with a generated coin

- Balances and transfers use the standard `Coin<T>` / address-balance APIs — nothing custom.
- Metadata: `client.getCoinMetadata({ coinType })` (gRPC) returns the registry `Currency`.
- Minting (`0x2::coin::mint`) and burning (`0x2::coin::burn`) require the `TreasuryCap`; a frozen
  `TreasuryCap` means supply is permanently fixed.
