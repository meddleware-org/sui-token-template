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
| Initial supply | `XINITIALSUPPLYX` whole tokens, minted at publish |
| Supply policy | `XSUPPLYPOLICYX` |
| Metadata policy | `XMETADATAPOLICYX` |

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

This token package was generated from [token-issuance-template-sui](https://github.com/MeddleWare-Org/token-issuance-template-sui) and is intentionally minimal:

- **No minting/burning logic of its own** — `init` mints the initial supply once. Supply policy `fixed` then hands the `TreasuryCap` to the coin registry (`make_supply_fixed`), so the supply can never grow and `is_supply_fixed` / `total_supply` report it; `mintable` sends the `TreasuryCap` to the publisher, who can mint more (governed by the downstream packages that consume the coin type).
- **Metadata policy** — Name, symbol, and decimals are always permanently fixed. `updatable`: description and icon URL stay updatable via `MetadataCap<XSTRUCTNAMEX>` (governance-gated). `frozen`: `init` deletes the `MetadataCap` (`finalize_and_delete_metadata_cap`), so nothing can change and `is_metadata_cap_deleted` reports it; the icon is then the `ICON_URL` constant. Both policies are applied by `init` in the publish transaction, so there is no later moment at which a cap exists unprotected. The policy values are the generated constants `INITIAL_SUPPLY`, `FIXED_SUPPLY` and `FROZEN_METADATA` in `sources/XMODULENAMEX.move`.
- **Package can be made frozen** — `scripts/publish.sh` extracts the UpgradeCap after publish and offers to call `0x2::package::make_immutable` on it (interactive confirmation, or pass `--confirm-immutable` for non-interactive use). This action is irreversible. Until confirmed, the package remains upgradeable. Metadata mutability is independent of this — it's controlled by the `MetadataCap`, not package upgradeability.

## Tests

Run the inline unit tests:

```bash
sui move test
```

The tests cover every combination of the supply and metadata policies: the initial supply is minted to the publisher, a fixed supply leaves no `TreasuryCap` and is recorded in the registry, a mintable supply keeps the `TreasuryCap` (with its supply already counting the mint), frozen metadata leaves no `MetadataCap` and is recorded as deleted, and a fixed supply with nothing minted aborts. The pending `Currency<XSTRUCTNAMEX>` is held by the registry address until `finalize_registration`.

## License

BSD Zero Clause License (0BSD) — see the LICENSE file.
