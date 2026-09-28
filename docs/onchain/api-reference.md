---
title: Token template — on-chain API reference
---

# Token template — on-chain API reference

Module `sui_token_template::sui_token_template` (`sources/sui_token_template.move`), Move 2024. In a
generated package the module, struct and package names are replaced (e.g. `my_token::mytoken::MYTOKEN`).

## Types

| Type | Abilities | Notes |
| --- | --- | --- |
| `SUI_TOKEN_TEMPLATE` | `drop` | One-time witness; the coin type is `<PACKAGE_ID>::<module>::SUI_TOKEN_TEMPLATE` |

## Constants (patch points)

| Constant | Template value | Meaning |
| --- | --- | --- |
| `DECIMALS: u8` | `9` | Decimals (fixed forever after publish) |
| `SYMBOL` | `b"TEMPLATE_SYMBOL"` | Symbol (fixed forever) |
| `NAME` | `b"TEMPLATE_NAME"` | Name (fixed forever) |
| `DESCRIPTION` | `b"TEMPLATE_DESCRIPTION"` | Description (editable with `MetadataCap`) |
| `ICON_URL` | `b"TEMPLATE_ICON_URL"` | Icon URL (editable with `MetadataCap`) |

The values are deliberately distinct so each occupies its own constant-pool entry and can be patched
independently in compiled bytecode.

## Functions

| Function | Visibility | Behaviour |
| --- | --- | --- |
| `init(witness, ctx)` | module init (runs once at publish) | `coin_registry::new_currency_with_otw(witness, DECIMALS, SYMBOL, NAME, DESCRIPTION, ICON_URL)` → `builder.finalize(ctx)` (pending `Currency<T>` → `0xc`, returns `MetadataCap<T>`) → transfers `TreasuryCap<T>` and `MetadataCap<T>` to the sender |
| `test_init(ctx)` | `#[test_only]` | Calls `init` with the witness |

No other functions, no abort codes and no events are defined by the template. Supply, metadata and
registry operations use framework functions:

| Framework call | Requires | Effect |
| --- | --- | --- |
| `0x2::coin_registry::finalize_registration<T>(registry 0xc, Receiving<Currency<T>>)` | anyone | Pending `Currency<T>` → shared |
| `0x2::coin_registry::set_icon_url<T>` / `set_description<T>` | `MetadataCap<T>` | Update metadata |
| `0x2::coin::mint<T>` / `0x2::coin::burn<T>` | `TreasuryCap<T>` | Change supply |
| `0x2::package::make_immutable(UpgradeCap)` | `UpgradeCap` | Freeze package code |

## Objects created at publish

| Object | Owner after `init` |
| --- | --- |
| `TreasuryCap<T>` | publisher |
| `MetadataCap<T>` | publisher |
| `Currency<T>` (pending) | coin registry address `0xc` until `finalize_registration` |
| `UpgradeCap` | publisher (until burned) |

## Invariants

- `init` runs exactly once (one-time witness).
- No authority other than the two capabilities is created or retained by the package.
- Name, symbol and decimals are immutable in the registry.
