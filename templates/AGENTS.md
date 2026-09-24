# AGENTS.md — XPACKAGENAMEX Package

## What This Package Is

The deployed XSYMBOLX coin type for XPROJECTNAMEX (Sui testnet/mainnet).

Coin type: `<PACKAGE_ID>::XMODULENAMEX::XSTRUCTNAMEX`

Generated from `sui-token-template`. Becomes immutable once `scripts/publish.sh` is run with `--confirm-immutable` (or the interactive CONFIRM prompt is accepted) — this burns the UpgradeCap via `0x2::package::make_immutable`. Verify with `sui client object <PACKAGE_ID> --json | jq -r .data.owner` → expect `"Immutable"`.

## Coin Registry Pattern

This coin uses `coin_registry::new_currency_with_otw` + `.finalize(ctx)` (the
framework's documented replacement for deprecated `coin::create_currency`) to
produce a `Currency<XSTRUCTNAMEX>` registry entry. Because OTW currencies require a
mandatory second transaction (`coin_registry::finalize_registration`) to become
shared and RPC-discoverable, `suix_getCoinMetadata` only returns non-null data
*after* that step has run — `scripts/publish.sh` performs it automatically.
Metadata fields:

- **Immutable**: Name, symbol, decimals
- **Mutable**: Description and icon URL — gated by `MetadataCap<XSTRUCTNAMEX>`. The
  *initial* per-network icon is set once directly by `scripts/publish.sh` via
  `coin_registry::set_icon_url`. Subsequent updates go through governance.

## Verification Commands

```bash
# Confirm package exists and is immutable
sui client object FILL_IN_AFTER_DEPLOY

# Confirm TreasuryCap at governance
sui client objects FILL_IN_AFTER_DEPLOY | grep -i treasurycap
```

## Key Files

| File | Purpose |
| --- | --- |
| `sources/XMODULENAMEX.move` | Generated coin source (do not edit manually) |
| `deployments.md` | Artefact IDs (package, TreasuryCap, MetadataCap, Currency object, blob) |
| `scripts/publish.sh` | Build + publish + finalize_registration + set initial icon URL |

For template-level guidance, see `sui-token-template/AGENTS.md`.
