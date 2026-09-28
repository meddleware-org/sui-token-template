---
title: Token template — on-chain overview
---

# Token template — on-chain overview

`sui_token_template` is the Move source every Meddleware-generated **Sui coin** is built from. The
Token Deployer (browser) and the `deploy_token.sh` pipeline (CLI) turn it into a concrete, standalone
coin package: one package per coin, with its own coin type `<PACKAGE_ID>::<module>::<STRUCT>`.

## What a generated coin package does on-chain

It contains exactly one function that ever runs on its own — `init`, once, at publish:

1. Registers the coin with the Sui **coin registry** (`coin_registry::new_currency_with_otw`), fixing
   its **decimals, symbol and name forever**, and setting its description and icon URL.
2. Mints the **`TreasuryCap<T>`** (authority to mint and burn) and the **`MetadataCap<T>`**
   (authority to change description and icon) and sends **both** to the publisher.
3. Leaves the coin's `Currency<T>` record pending in the registry; a follow-up call,
   `coin_registry::finalize_registration`, makes it a shared, discoverable object.

There is no fee, commission, treasury split, mint limit or admin logic in the Move code. Everything
beyond `init` is done with the Sui framework's own functions by whoever holds the capabilities.

## Capabilities and who holds them

| Object | Authority | Typical custody |
| --- | --- | --- |
| `TreasuryCap<T>` | mint and burn any amount | the project treasury — or **frozen** for a fixed supply |
| `MetadataCap<T>` | change description and icon URL | the project — or **deleted/frozen** to lock metadata |
| `UpgradeCap` | replace the package code | **burned** (package made immutable) |
| `Currency<T>` | the registry record (shared) | the coin registry |

## Deployment paths

| Path | Registration | Supply / metadata policy | UpgradeCap |
| --- | --- | --- | --- |
| Token Deployer (browser) | finalized in a second transaction | fixed supply = TreasuryCap frozen after the initial mint; frozen metadata = MetadataCap frozen | burned (default) or kept, per your choice |
| `deploy_token.sh` (CLI) | finalized | TreasuryCap transferred to `TREASURY_ADDRESS`; MetadataCap kept by the deployer | always burned |
| generated `scripts/publish.sh` | finalized; icon set per network | caps stay with the deployer | burned only with `--confirm-immutable` / `CONFIRM` |

The operator fee charged by the Token Deployer is part of that app's publish transaction, not of the
coin package.
