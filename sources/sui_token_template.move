// SPDX-License-Identifier: 0BSD
// Licensed under the 0BSD license; see the LICENSE file.

/// XPACKAGEDESCRIPTIONX
///
/// ## Overview
///
/// Defines the `SUI_TOKEN_TEMPLATE` type witness and initializes the token via the modern
/// `coin_registry::new_currency_with_otw` pattern (the framework's documented
/// replacement for deprecated `coin::create_currency`). Name, symbol, and decimals
/// are permanently immutable. Description and icon URL remain updatable via
/// governance entry points, using a `MetadataCap<SUI_TOKEN_TEMPLATE>` rather than the `TreasuryCap`.
///
/// ## Key Types
///
/// - `SUI_TOKEN_TEMPLATE` — the type witness (zero-field struct with `drop` ability) used for one-time-witness initialization
///
/// ## Deployment
///
/// `init()` is a two-step OTW flow, and it applies the deployer's supply and metadata policies
/// itself, in the same transaction that publishes the package (there is no later transaction in
/// which the caps exist unprotected):
/// 1. `coin_registry::new_currency_with_otw` builds the `Currency<SUI_TOKEN_TEMPLATE>` from the
///    constants below (the icon URL is the `ICON_URL` constant, which a deployer patches and
///    `scripts/publish.sh` may replace per network — see below) and mints
///    `TreasuryCap<SUI_TOKEN_TEMPLATE>`.
/// 2. `INITIAL_SUPPLY` (raw units, 0 = none) is minted to the sender.
/// 3. `FIXED_SUPPLY`: `make_supply_fixed` hands the `TreasuryCap` to the registry, so the supply
///    can never grow and `Currency.is_supply_fixed` / `total_supply` report it. Otherwise the
///    `TreasuryCap` goes to the sender.
/// 4. `FROZEN_METADATA`: `finalize_and_delete_metadata_cap` deletes the `MetadataCap`, so name,
///    symbol, description and icon can never change and `Currency.is_metadata_cap_deleted` reports
///    it. Otherwise `.finalize(ctx)` claims a live `MetadataCap` for the sender. Either way the
///    pending `Currency<SUI_TOKEN_TEMPLATE>` is transferred to the registry address `0xc`.
///
/// From there, `scripts/publish.sh` / the deployer client:
/// - call `coin_registry::finalize_registration` (required for OTW currencies —
///   promotes the pending `Currency<SUI_TOKEN_TEMPLATE>` into a real shared, RPC-discoverable
///   object),
/// - with `FROZEN_METADATA` off, `scripts/publish.sh` calls `coin_registry::set_icon_url` using the
///   freshly-held `MetadataCap` and a network-specific `SUI_TOKEN_TEMPLATE_ICON_URL` env var — this
///   is how the icon differs between testnet and mainnet without ever hardcoding a URL in this
///   source file. With `FROZEN_METADATA` on the icon is the `ICON_URL` constant, for good.
///
/// The minted coin and whichever caps remain should be transferred to their intended custodians
/// (e.g. treasury, governance multisig) according to your deployment runbook. Package
/// immutability is a separate, explicit step: the UpgradeCap is burned by `deploy_token.sh`, or by
/// `scripts/publish.sh` only with `--confirm-immutable` / an interactive CONFIRM. It is
/// independent of the supply and metadata policies.
module sui_token_template::sui_token_template;

use sui::coin::TreasuryCap;
#[test_only]
use sui::coin::Coin;
#[test_only]
use sui::coin_registry::{Currency, MetadataCap};
use sui::coin_registry;

/// Token parameters, declared as named constants rather than inline literals.
///
/// Each `const` becomes a distinct entry in the compiled module's constant pool,
/// which is what lets the browser-based deployer patch them client-side via
/// `@mysten/move-bytecode-template::update_constants` — no Move recompilation.
/// The generator (`scripts/03_create_token.sh`) substitutes these same values into
/// the downloadable source package, so the shipped bytecode and the generated
/// source stay in lock-step (the on-chain package is source-verifiable).
///
/// The default values are deliberately DISTINCT: identical constants are
/// deduplicated into a single pool entry by the Move compiler, which would make
/// them impossible to patch independently.
const DECIMALS: u8 = 9;
const SYMBOL: vector<u8> = b"TEMPLATE_SYMBOL";
const NAME: vector<u8> = b"TEMPLATE_NAME";
const DESCRIPTION: vector<u8> = b"TEMPLATE_DESCRIPTION";
const ICON_URL: vector<u8> = b"TEMPLATE_ICON_URL";

/// Supply and metadata policy, patched the same way. `INITIAL_SUPPLY` is in raw units (the whole-token
/// amount times 10^DECIMALS). The two booleans default to different values on purpose, for the same
/// reason as above: equal constants would share one pool entry.
const INITIAL_SUPPLY: u64 = 1_000_000_007;
/// `true` → `make_supply_fixed` (requires `INITIAL_SUPPLY > 0`; the framework aborts otherwise).
const FIXED_SUPPLY: bool = true;
/// `true` → `finalize_and_delete_metadata_cap`.
const FROZEN_METADATA: bool = false;

/// SUI_TOKEN_TEMPLATE is the type witness — a zero-sized struct that encodes type identity.
/// The struct has no fields and only the `drop` ability (consumed once in `init()`).
/// Paired with `coin_registry::new_currency_with_otw()`, it creates a
/// `TreasuryCap<SUI_TOKEN_TEMPLATE>` and a `Currency<SUI_TOKEN_TEMPLATE>` registry entry. The token type
/// becomes `<PACKAGE_ID>::XMODULENAMEX::SUI_TOKEN_TEMPLATE` globally.
public struct SUI_TOKEN_TEMPLATE has drop {}

/// `init()` is called exactly once when the package is published. It initializes the token:
/// 1. Builds the `Currency<SUI_TOKEN_TEMPLATE>` and `TreasuryCap<SUI_TOKEN_TEMPLATE>` via `coin_registry::new_currency_with_otw`.
/// 2. Mints `INITIAL_SUPPLY` to the sender, and either records the supply as fixed in the registry
///    (`FIXED_SUPPLY`) or hands the `TreasuryCap` to the sender.
/// 3. Either deletes the `MetadataCap` (`FROZEN_METADATA`) or hands it to the sender, and transfers
///    the pending `Currency<SUI_TOKEN_TEMPLATE>` to the registry address.
fun init(witness: SUI_TOKEN_TEMPLATE, ctx: &mut TxContext) {
    init_with(witness, INITIAL_SUPPLY, FIXED_SUPPLY, FROZEN_METADATA, ctx);
}

/// The whole of `init`, with the policy as arguments so each combination can be tested (a constant
/// is fixed at compile time). `init` is its only production caller, so the transfers to the sender
/// are init's own (the lint exempts `init` itself, not the function it delegates to).
#[allow(lint(self_transfer))]
fun init_with(
    witness: SUI_TOKEN_TEMPLATE,
    initial_supply: u64,
    fixed_supply: bool,
    frozen_metadata: bool,
    ctx: &mut TxContext,
) {
    let (mut builder, mut treasury_cap) = coin_registry::new_currency_with_otw(
        witness,
        DECIMALS,
        SYMBOL.to_string(),
        NAME.to_string(),
        DESCRIPTION.to_string(),
        ICON_URL.to_string(), // may be updated per-network by scripts/publish.sh after finalize_registration
        ctx,
    );

    if (initial_supply > 0) {
        transfer::public_transfer(treasury_cap.mint(initial_supply, ctx), ctx.sender());
    };

    // Fixed supply: the registry takes the cap (aborts if nothing was minted).
    if (fixed_supply) {
        builder.make_supply_fixed(treasury_cap);
    } else {
        transfer::public_transfer(treasury_cap, ctx.sender());
    };

    if (frozen_metadata) {
        builder.finalize_and_delete_metadata_cap(ctx);
    } else {
        let metadata_cap = builder.finalize(ctx);
        transfer::public_transfer(metadata_cap, ctx.sender());
    };
}

#[test_only]
/// Test-only wrapper around the real `init()`, constructing the `SUI_TOKEN_TEMPLATE` witness
/// on the caller's behalf (struct literals are restricted to their defining
/// module, so external test modules cannot do
/// this themselves). Mirrors production behavior exactly with the default constants.
/// `Currency<SUI_TOKEN_TEMPLATE>` is transferred to
/// the registry address `@0xc` (retrievable via `take_from_address`/
/// `return_to_address` in a later transaction — `Currency<T>` has only `key`,
/// not `store`, so it cannot be shared or transferred from outside `coin_registry`
/// by any other means).
public fun test_init(ctx: &mut TxContext) {
    init(SUI_TOKEN_TEMPLATE {}, ctx);
}

#[test_only]
fun test_init_with(initial_supply: u64, fixed_supply: bool, frozen_metadata: bool, ctx: &mut TxContext) {
    init_with(SUI_TOKEN_TEMPLATE {}, initial_supply, fixed_supply, frozen_metadata, ctx);
}

#[test_only]
const ADMIN: address = @0xAD;
#[test_only]
const REGISTRY: address = @0xc;

#[test]
/// Whatever the constants are (the shipped defaults, or the values a generator patched in): `init`
/// applies them. The initial supply is minted to the sender, the TreasuryCap reaches the sender
/// exactly when the supply is not fixed, the MetadataCap exactly when the metadata is not frozen,
/// and the registry's `Currency` records both policies.
fun constants_are_applied() {
    use sui::test_scenario;

    let mut s = test_scenario::begin(ADMIN);
    test_init(s.ctx());
    s.next_tx(ADMIN);
    assert!(test_scenario::has_most_recent_for_sender<TreasuryCap<SUI_TOKEN_TEMPLATE>>(&s) == !FIXED_SUPPLY);
    assert!(test_scenario::has_most_recent_for_sender<MetadataCap<SUI_TOKEN_TEMPLATE>>(&s) == !FROZEN_METADATA);
    assert!(test_scenario::has_most_recent_for_sender<Coin<SUI_TOKEN_TEMPLATE>>(&s) == (INITIAL_SUPPLY > 0));
    if (INITIAL_SUPPLY > 0) {
        let coin = s.take_from_sender<Coin<SUI_TOKEN_TEMPLATE>>();
        assert!(coin.value() == INITIAL_SUPPLY);
        s.return_to_sender(coin);
    };
    let currency = s.take_from_address<Currency<SUI_TOKEN_TEMPLATE>>(REGISTRY);
    assert!(currency.is_supply_fixed() == FIXED_SUPPLY);
    assert!(currency.is_metadata_cap_deleted() == FROZEN_METADATA);
    if (FIXED_SUPPLY) assert!(currency.total_supply() == option::some(INITIAL_SUPPLY));
    test_scenario::return_to_address(REGISTRY, currency);
    s.end();
}

#[test]
/// Mintable supply with an initial mint: the TreasuryCap goes to the sender and its supply already
/// counts the minted coin; the registry does not claim the supply is fixed.
fun mintable_supply_keeps_the_treasury_cap() {
    use sui::test_scenario;

    let mut s = test_scenario::begin(ADMIN);
    test_init_with(500, false, false, s.ctx());
    s.next_tx(ADMIN);
    let treasury = s.take_from_sender<TreasuryCap<SUI_TOKEN_TEMPLATE>>();
    assert!(treasury.total_supply() == 500);
    s.return_to_sender(treasury);
    let coin = s.take_from_sender<Coin<SUI_TOKEN_TEMPLATE>>();
    assert!(coin.value() == 500);
    s.return_to_sender(coin);
    let currency = s.take_from_address<Currency<SUI_TOKEN_TEMPLATE>>(REGISTRY);
    assert!(!currency.is_supply_fixed());
    test_scenario::return_to_address(REGISTRY, currency);
    s.end();
}

#[test]
/// Mintable with no initial supply: only the TreasuryCap (no coin) reaches the sender.
fun mintable_without_initial_supply_mints_nothing() {
    use sui::test_scenario;

    let mut s = test_scenario::begin(ADMIN);
    test_init_with(0, false, false, s.ctx());
    s.next_tx(ADMIN);
    let treasury = s.take_from_sender<TreasuryCap<SUI_TOKEN_TEMPLATE>>();
    assert!(treasury.total_supply() == 0);
    s.return_to_sender(treasury);
    assert!(!test_scenario::has_most_recent_for_sender<Coin<SUI_TOKEN_TEMPLATE>>(&s));
    s.end();
}

#[test]
/// Frozen metadata: the registry records the deleted cap, and no MetadataCap exists for anyone.
fun frozen_metadata_deletes_the_metadata_cap() {
    use sui::test_scenario;

    let mut s = test_scenario::begin(ADMIN);
    test_init_with(1, true, true, s.ctx());
    s.next_tx(ADMIN);
    assert!(!test_scenario::has_most_recent_for_sender<MetadataCap<SUI_TOKEN_TEMPLATE>>(&s));
    let currency = s.take_from_address<Currency<SUI_TOKEN_TEMPLATE>>(REGISTRY);
    assert!(currency.is_metadata_cap_deleted());
    assert!(currency.is_supply_fixed());
    test_scenario::return_to_address(REGISTRY, currency);
    s.end();
}

#[test]
/// Updatable metadata with a mintable supply is the old behaviour: both caps with the sender.
fun mintable_and_updatable_hands_both_caps_to_the_sender() {
    use sui::test_scenario;

    let mut s = test_scenario::begin(ADMIN);
    test_init_with(0, false, false, s.ctx());
    s.next_tx(ADMIN);
    let treasury = s.take_from_sender<TreasuryCap<SUI_TOKEN_TEMPLATE>>();
    s.return_to_sender(treasury);
    let metadata = s.take_from_sender<MetadataCap<SUI_TOKEN_TEMPLATE>>();
    s.return_to_sender(metadata);
    let currency = s.take_from_address<Currency<SUI_TOKEN_TEMPLATE>>(REGISTRY);
    assert!(!currency.is_supply_fixed());
    assert!(!currency.is_metadata_cap_deleted());
    test_scenario::return_to_address(REGISTRY, currency);
    s.end();
}

#[test, expected_failure(abort_code = coin_registry::EEmptySupply, location = coin_registry)]
/// A fixed supply with nothing minted can never be unfixed or minted, so the framework refuses it.
fun fixed_supply_requires_an_initial_mint() {
    use sui::test_scenario;

    let mut s = test_scenario::begin(ADMIN);
    test_init_with(0, true, false, s.ctx());
    s.end();
}
