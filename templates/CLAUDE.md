# CLAUDE.md — XPACKAGENAMEX Package

> **coin_registry OTW pattern — read before verifying deployment**
>
> This package uses `coin_registry::new_currency_with_otw` + `builder.finalize(ctx)`.
> `TreasuryCap` and `MetadataCap` are both transferred to the deployer at publish time.
> Run `coin_registry::finalize_registration` immediately after publish to promote the
> pending `Currency` to a real shared object (required for `suix_getCoinMetadata` to work).

## What This Package Is

This is the concrete XSYMBOLX coin type for XPROJECTNAMEX. It was generated from the
`sui-token-template` and deployed to Sui testnet/mainnet.

Coin type: `<PACKAGE_ID>::XMODULENAMEX::XSTRUCTNAMEX`

## coin_registry Pattern

The coin was initialized using:

```move
let (builder, treasury_cap) = coin_registry::new_currency_with_otw(witness, ...);
let metadata_cap = builder.finalize(ctx);
transfer::public_transfer(treasury_cap, ctx.sender());
transfer::public_transfer(metadata_cap, ctx.sender());
```

`init()` builds with an empty icon URL — the real, network-specific value is set
immediately post-publish by `scripts/publish.sh` (see below), never hardcoded in source.

| Aspect | Behavior |
| --- | --- |
| `Currency<XSTRUCTNAMEX>` registry object | Yes — created pending, promoted to shared via `coin_registry::finalize_registration` |
| `suix_getCoinMetadata` | Should return non-null data once `finalize_registration` has run — verify post-redeploy |
| **Immutable fields** | Name, symbol, decimals |
| **Mutable fields** | Description, icon URL |

## Verification

```bash
# Package on-chain; check immutability via owner field
sui client object FILL_IN_AFTER_DEPLOY --json | jq -r '.data.owner'
# → "Immutable" once make_immutable has been confirmed during publish

# TreasuryCap at governance address
sui client objects FILL_IN_AFTER_DEPLOY | grep -i treasurycap

# Currency<XSTRUCTNAMEX> is discoverable (post finalize_registration)
suix_getCoinMetadata "<PACKAGE_ID>::XMODULENAMEX::XSTRUCTNAMEX"
```

## Deployment Artefacts

See [deployments.md](deployments.md) for all IDs (package, TreasuryCap, MetadataCap,
Currency object, Walrus blob).

## Working Rules

- Do not manually edit `sources/XMODULENAMEX.move`. If regeneration is needed, use `create_token.sh`
  from the `sui-token-template` scripts. The icon URL is never hardcoded here — it is
  supplied per-network via the `XSTRUCTNAMEX_ICON_URL` env var consumed by `scripts/publish.sh`.
- Description and icon URL may be updated post-deploy via `MetadataCap` (governance-gated).
  Name, symbol, and decimals are permanently fixed.
- Refer to `sui-token-template/CLAUDE.md` for template-level guidance.
