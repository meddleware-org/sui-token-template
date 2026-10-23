---
title: Token template — on-chain overview
---

# Token template — on-chain overview

`sui_token_template` is the Move source every Meddleware-generated **Sui coin** is built from. The
Token Issuance (browser) and the `deploy_token.sh` pipeline (CLI) turn it into a concrete, standalone
coin package: one package per coin, with its own coin type `<PACKAGE_ID>::<module>::<STRUCT>`.

## What a generated coin package does on-chain

It contains exactly one function that ever runs on its own — `init`, once, at publish:

1. Registers the coin with the Sui **coin registry** (`coin_registry::new_currency_with_otw`), fixing
   its **decimals, symbol and name forever**, and setting its description and icon URL.
2. Mints the **initial supply** (`INITIAL_SUPPLY`, possibly 0) to the publisher and applies the
   **supply policy**: a *fixed* supply is handed to the registry (`make_supply_fixed`), so no
   `TreasuryCap` exists and the registry reports the supply as fixed; a *mintable* supply sends the
   **`TreasuryCap<T>`** (authority to mint and burn) to the publisher.
3. Applies the **metadata policy**: *frozen* metadata deletes the **`MetadataCap<T>`**
   (`finalize_and_delete_metadata_cap`) and the registry reports it as deleted; *updatable*
   metadata sends the `MetadataCap<T>` (authority to change description and icon) to the publisher.
4. Leaves the coin's `Currency<T>` record pending in the registry; a follow-up call,
   `coin_registry::finalize_registration`, makes it a shared, discoverable object. The policies
   survive that call (they live in the `Currency` record).

Both policies are applied in the same transaction that publishes the package, so there is no moment
at which a cap exists that the deployer meant to give up.

There is no fee, commission, treasury split, mint limit or admin logic in the Move code. Everything
beyond `init` is done with the Sui framework's own functions by whoever holds the capabilities.

## Capabilities and who holds them

| Object | Authority | Typical custody |
| --- | --- | --- |
| `TreasuryCap<T>` | mint and burn any amount | the project treasury — or **never created** (fixed supply: held by the registry) |
| `MetadataCap<T>` | change description and icon URL | the project — or **never created** (frozen metadata: deleted in `init`) |
| `UpgradeCap` | replace the package code | **burned** (package made immutable) |
| `Currency<T>` | the registry record (shared) | the coin registry |

## Deployment paths

| Path | Registration | Supply / metadata policy | UpgradeCap |
| --- | --- | --- | --- |
| Token Issuance (browser) | finalized in a second transaction | applied by `init` at publish (`INITIAL_SUPPLY`, `FIXED_SUPPLY`, `FROZEN_METADATA`); the second transaction only registers the currency and moves what remains to the recipient | burned (default) or kept, per your choice |
| `deploy_token.sh` (CLI) | finalized | same constants (`TOKEN_INITIAL_SUPPLY`, `TOKEN_SUPPLY_POLICY`, `TOKEN_METADATA_POLICY`); the TreasuryCap (if any) and the initial supply go to `TREASURY_ADDRESS`; the MetadataCap (if any) stays with the deployer | always burned |
| generated `scripts/publish.sh` | finalized; icon set per network unless the metadata is frozen | what remains stays with the deployer | burned only with `--confirm-immutable` / `CONFIRM` |

The operator fee charged by the Token Issuance is part of that app's publish transaction, not of the
coin package.
