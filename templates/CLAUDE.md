# CLAUDE.md — XPACKAGENAMEX Package

> **coin_registry OTW pattern — read before verifying deployment**
>
> This package uses `coin_registry::new_currency_with_otw`. `init` applies the supply policy
> (`XSUPPLYPOLICYX`, initial supply `XINITIALSUPPLYX` whole tokens) and the metadata policy
> (`XMETADATAPOLICYX`) in the publish transaction: the minted coin, the `TreasuryCap` (unless the
> supply is fixed) and the `MetadataCap` (unless the metadata is frozen) go to the deployer.
> Run `coin_registry::finalize_registration` immediately after publish to promote the
> pending `Currency` to a real shared object (required for wallets and the gRPC/GraphQL
> coin-metadata APIs to resolve it). `scripts/publish.sh` does this automatically.

## What This Package Is

This is the concrete XSYMBOLX coin type for XPROJECTNAMEX. It was generated from the
`token-issuance-template-sui` and deployed to Sui testnet/mainnet.

Coin type: `<PACKAGE_ID>::XMODULENAMEX::XSTRUCTNAMEX`

## coin_registry Pattern

The coin was initialized using:

```move
let (mut builder, mut treasury_cap) = coin_registry::new_currency_with_otw(witness, ...);
// INITIAL_SUPPLY > 0: mint it to the sender.
if (FIXED_SUPPLY) { builder.make_supply_fixed(treasury_cap) } else { /* TreasuryCap to the sender */ };
if (FROZEN_METADATA) { builder.finalize_and_delete_metadata_cap(ctx) } else { /* MetadataCap to the sender */ };
```

`init()` registers the icon URL from the `ICON_URL` constant chosen at generation time. With
updatable metadata, `scripts/publish.sh` then sets the network-specific value from
`XSTRUCTNAMEX_ICON_URL` via `coin_registry::set_icon_url` (while the deployer still holds the
`MetadataCap`); with frozen metadata the constant is final.

| Aspect | Behavior |
| --- | --- |
| `Currency<XSTRUCTNAMEX>` registry object | Yes — created pending, promoted to shared via `coin_registry::finalize_registration` |
| Coin metadata (gRPC `getCoinMetadata`) | Returns the registry `Currency` once `finalize_registration` has run |
| Supply policy | `XSUPPLYPOLICYX` — a fixed supply is recorded in the registry (`is_supply_fixed`) and has no `TreasuryCap` |
| Metadata policy | `XMETADATAPOLICYX` — frozen metadata is recorded in the registry (`is_metadata_cap_deleted`) and has no `MetadataCap` |
| **Immutable fields** | Name, symbol, decimals (and description and icon URL when the metadata is frozen) |
| **Mutable fields** | Description, icon URL (only while a `MetadataCap` exists) |

## Verification

```bash
# Package immutability: the UpgradeCap must no longer exist (a package object is always
# "Immutable"-owned, so its owner field proves nothing).
sui client object <UPGRADE_CAP_ID> --json   # → error "object deleted / not found" once burned

# TreasuryCap at governance address (a fixed supply has none: the registry holds the supply)
sui client objects FILL_IN_AFTER_DEPLOY | grep -i treasurycap

# Currency<XSTRUCTNAMEX> is discoverable (post finalize_registration): shared object
sui client object <CURRENCY_OBJECT_ID> --json | jq '.owner'   # → { "Shared": … }
```

## Deployment Artefacts

See [deployments.md](deployments.md) for all IDs (package, TreasuryCap, MetadataCap,
Currency object, Walrus blob).

## Working Rules

- Do not manually edit `sources/XMODULENAMEX.move`. If regeneration is needed, use `create_token.sh`
  from the `token-issuance-template-sui` scripts. The icon URL is never hardcoded here — it is
  supplied per-network via the `XSTRUCTNAMEX_ICON_URL` env var consumed by `scripts/publish.sh`.
- With the `updatable` metadata policy, description and icon URL may be updated post-deploy via
  `MetadataCap` (governance-gated). Name, symbol, and decimals are permanently fixed.
- Refer to `token-issuance-template-sui/CLAUDE.md` for template-level guidance.
