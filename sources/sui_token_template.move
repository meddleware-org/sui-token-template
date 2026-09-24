// SPDX-License-Identifier: CC0-1.0
// This work is dedicated to the public domain under CC0.

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
/// `init()` is a two-step OTW flow:
/// 1. `coin_registry::new_currency_with_otw` builds the `Currency<SUI_TOKEN_TEMPLATE>` with an
///    empty icon URL (network-specific values are set post-publish, not hardcoded
///    here — see below) and mints `TreasuryCap<SUI_TOKEN_TEMPLATE>`.
/// 2. `.finalize(ctx)` claims a live `MetadataCap<SUI_TOKEN_TEMPLATE>` (NOT
///    `finalize_and_delete_metadata_cap`, which would permanently lock metadata)
///    and transfers the pending `Currency<SUI_TOKEN_TEMPLATE>` to the registry address `0xc`.
///
/// Both `TreasuryCap<SUI_TOKEN_TEMPLATE>` and `MetadataCap<SUI_TOKEN_TEMPLATE>` are transferred to the
/// transaction sender (the deployer). From there, `scripts/publish.sh`:
/// - calls `coin_registry::finalize_registration` (required for OTW currencies —
///   promotes the pending `Currency<SUI_TOKEN_TEMPLATE>` into a real shared, RPC-discoverable
///   object),
/// - calls `coin_registry::set_icon_url` using the freshly-held `MetadataCap` and a
///   network-specific `SUI_TOKEN_TEMPLATE_ICON_URL` env var — this is how the icon differs
///   between testnet and mainnet without ever hardcoding a URL in this source file.
///
/// Both caps should be transferred to their intended custodians (e.g. treasury,
/// governance multisig) according to your deployment runbook. The package itself is
/// published with immutability constraints (UpgradeCap burned) to prevent future
/// code modifications; this is independent of metadata mutability, which remains
/// governance-controlled via the `MetadataCap`.
module sui_token_template::sui_token_template;

use sui::coin::TreasuryCap;
use sui::coin_registry::{Self, Currency, MetadataCap};

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

/// SUI_TOKEN_TEMPLATE is the type witness — a zero-sized struct that encodes type identity.
/// The struct has no fields and only the `drop` ability (consumed once in `init()`).
/// Paired with `coin_registry::new_currency_with_otw()`, it creates a
/// `TreasuryCap<SUI_TOKEN_TEMPLATE>` and a `Currency<SUI_TOKEN_TEMPLATE>` registry entry. The token type
/// becomes `<PACKAGE_ID>::XMODULENAMEX::SUI_TOKEN_TEMPLATE` globally.
public struct SUI_TOKEN_TEMPLATE has drop {}

/// `init()` is called exactly once when the package is published. It initializes the token:
/// 1. Builds the `Currency<SUI_TOKEN_TEMPLATE>` and `TreasuryCap<SUI_TOKEN_TEMPLATE>` via `coin_registry::new_currency_with_otw`.
/// 2. Finalizes (without deleting the `MetadataCap`), transferring the pending
///    `Currency<SUI_TOKEN_TEMPLATE>` to the registry address.
/// 3. Transfers `TreasuryCap<SUI_TOKEN_TEMPLATE>` and `MetadataCap<SUI_TOKEN_TEMPLATE>` to the transaction sender.
fun init(witness: SUI_TOKEN_TEMPLATE, ctx: &mut TxContext) {
    let (builder, treasury_cap) = coin_registry::new_currency_with_otw(
        witness,
        DECIMALS,
        SYMBOL.to_string(),
        NAME.to_string(),
        DESCRIPTION.to_string(),
        ICON_URL.to_string(), // may be updated per-network by scripts/publish.sh after finalize_registration
        ctx,
    );

    let metadata_cap = builder.finalize(ctx);

    transfer::public_transfer(treasury_cap, ctx.sender());
    transfer::public_transfer(metadata_cap, ctx.sender());
}

#[test_only]
/// Test-only wrapper around the real `init()`, constructing the `SUI_TOKEN_TEMPLATE` witness
/// on the caller's behalf (struct literals are restricted to their defining
/// module, so external test modules cannot do
/// this themselves). Mirrors production behavior exactly: `TreasuryCap<SUI_TOKEN_TEMPLATE>`
/// and `MetadataCap<SUI_TOKEN_TEMPLATE>` go to the sender; `Currency<SUI_TOKEN_TEMPLATE>` is transferred to
/// the registry address `@0xc` (retrievable via `take_from_address`/
/// `return_to_address` in a later transaction — `Currency<T>` has only `key`,
/// not `store`, so it cannot be shared or transferred from outside `coin_registry`
/// by any other means).
public fun test_init(ctx: &mut TxContext) {
    init(SUI_TOKEN_TEMPLATE {}, ctx);
}

#[test]
fun test_treasury_cap_transferred_to_sender() {
    use sui::test_scenario;

    let admin = @0xAD;
    let mut s = test_scenario::begin(admin);
    test_init(s.ctx());
    s.next_tx(admin);
    let cap = s.take_from_sender<TreasuryCap<SUI_TOKEN_TEMPLATE>>();
    s.return_to_sender(cap);
    s.end();
}

#[test]
fun test_treasury_cap_present_in_sender() {
    use sui::test_scenario;

    let admin = @0xAD;
    let mut s = test_scenario::begin(admin);
    test_init(s.ctx());
    s.next_tx(admin);
    assert!(s.has_most_recent_for_sender<TreasuryCap<SUI_TOKEN_TEMPLATE>>(), 0);
    s.end();
}

#[test]
fun test_metadata_cap_present_in_sender() {
    use sui::test_scenario;

    let admin = @0xAD;
    let mut s = test_scenario::begin(admin);
    test_init(s.ctx());
    s.next_tx(admin);
    assert!(s.has_most_recent_for_sender<MetadataCap<SUI_TOKEN_TEMPLATE>>(), 0);
    s.end();
}

#[test]
fun test_currency_transferred_to_registry_after_init() {
    use sui::test_scenario;

    // Sui's CoinRegistry shared object lives at the well-known address 0xc; OTW
    // currencies are transferred there pending `coin_registry::finalize_registration`.
    let registry_address = @0xc;
    let admin = @0xAD;
    let mut s = test_scenario::begin(admin);
    test_init(s.ctx());
    s.next_tx(admin);
    let currency = s.take_from_address<Currency<SUI_TOKEN_TEMPLATE>>(registry_address);
    test_scenario::return_to_address(registry_address, currency);
    s.end();
}
