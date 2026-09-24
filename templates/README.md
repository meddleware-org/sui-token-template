# XNAMEX (XSYMBOLX)

XDESCRIPTIONX

## Token Details

| Field | Value |
| --- | --- |
| Package Name | `XPACKAGENAMEX` |
| Module | `XMODULENAMEX` |
| Struct | `XSTRUCTNAMEX` |
| Symbol | `XSYMBOLX` |
| Decimals | `XDECIMALSX` |

## Deploy

To publish this token to testnet or mainnet:

```bash
XSTRUCTNAMEX_ICON_URL=https://... bash scripts/publish.sh
```

`XSTRUCTNAMEX_ICON_URL` is required and network-specific (testnet/mainnet typically point
at different uploaded images) — the icon is never hardcoded in `sources/XMODULENAMEX.move`.
`publish.sh` also calls `coin_registry::finalize_registration`, a mandatory second
step for OTW-created currencies that promotes the pending `Currency<XSTRUCTNAMEX>` into a
real shared, RPC-discoverable object.

## Token Type (After Deployment)

Once published, the token type will be:

```text
<PACKAGE_ID>::XMODULENAMEX::XSTRUCTNAMEX
```

## Design Philosophy

This token package was generated from [sui-token-template](https://github.com/MeddleWare-Org/sui-token-template) and is intentionally minimal:

- **No minting/burning logic** — Controlled by the downstream packages that consume the coin type
- **Partially mutable metadata** — Name, symbol, and decimals are permanently fixed. Description and icon URL are updatable via `MetadataCap<XSTRUCTNAMEX>` (governance-gated), using `coin_registry::new_currency_with_otw` + `finalize()` (deliberately *not* `finalize_and_delete_metadata_cap()`, which would lock metadata forever)
- **Package can be made frozen** — `scripts/publish.sh` extracts the UpgradeCap after publish and offers to call `0x2::package::make_immutable` on it (interactive confirmation, or pass `--confirm-immutable` for non-interactive use). This action is irreversible. Until confirmed, the package remains upgradeable. Metadata mutability is independent of this — it's controlled by the `MetadataCap`, not package upgradeability.

## Tests

Run the inline unit tests:

```bash
sui move test
```

Four tests verify:

1. `test_treasury_cap_transferred_to_sender` — TreasuryCap is transferred to deployer
2. `test_treasury_cap_present_in_sender` — TreasuryCap is present after init
3. `test_metadata_cap_present_in_sender` — `MetadataCap<XSTRUCTNAMEX>` is present after init
4. `test_currency_transferred_to_registry_after_init` — `Currency<XSTRUCTNAMEX>` is transferred to the registry address, pending `finalize_registration`

## License

CC0 1.0 Universal — public domain.
