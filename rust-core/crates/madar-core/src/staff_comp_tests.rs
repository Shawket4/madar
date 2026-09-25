//! A cart line MARKED as a staff drink, end to end through the real core
//! (docs: MadarRust `docs/staff-drink-comp-contract.md`): the mark on the
//! stored line, the comp through the bill engine, the order line on the wire,
//! the pool entry written with the sale, the server's answer adopted, and the
//! fallback for a server that predates all of it.

use serde_json::{json, Value};

use crate::testkit::{self, Stub, StubResponse};
use crate::{cart, checkout, ledger, menu, MadarCore};

const LATTE: &str = "00000000-0000-0000-0000-0000000000a1";
const TEA: &str = "00000000-0000-0000-0000-0000000000a2";
const CAKE: &str = "00000000-0000-0000-0000-0000000000a3";
const SYRUP_VANILLA: &str = "00000000-0000-0000-0000-0000000000d1";
const SYRUP_CARAMEL: &str = "00000000-0000-0000-0000-0000000000d2";
const EXTRA_SHOT: &str = "00000000-0000-0000-0000-0000000000d3";
const OAT: &str = "00000000-0000-0000-0000-0000000000d4";
const G_SYRUP: &str = "00000000-0000-0000-0000-0000000000f1";
const G_EXTRAS: &str = "00000000-0000-0000-0000-0000000000f2";
const G_MILK: &str = "00000000-0000-0000-0000-0000000000f3";
const CASH: &str = "00000000-0000-0000-0000-0000000000e1";

fn item(id: &str, name: &str, base: i64, sizes: &[(&str, i64)]) -> Value {
    json!({
        "base_price": base, "created_at": "2026-06-19T10:00:00Z", "updated_at": "2026-06-19T10:00:00Z",
        "id": id, "org_id": testkit::ORG, "is_active": true, "name": name,
        "name_translations": {}, "description_translations": {}, "addon_slots": [],
        "allowed_addon_ids": [], "optional_fields": [], "recipes": [],
        "sizes": sizes.iter().enumerate().map(|(n, (label, price))| json!({
            "id": format!("00000000-0000-0000-0000-00000c{n:03}{}", &id[33..]), "is_active": true,
            "label": label, "menu_item_id": id, "price_override": price })).collect::<Vec<_>>(),
    })
}

fn addon(id: &str, name: &str, kind: &str, price: i64) -> Value {
    json!({ "addon_type": kind, "created_at": "2026-06-19T10:00:00Z", "updated_at": "2026-06-19T10:00:00Z",
            "default_price": price, "id": id, "is_active": true, "name": name, "name_translations": {},
            "org_id": testkit::ORG, "ingredients": [] })
}

/// Latte (S 6000 / L 9000) with a REQUIRED syrup group (default vanilla 500,
/// caramel 1200), an OPTIONAL extras group (shot 1500) and a milk SWAP group;
/// Tea 3000 with nothing; Cake not on the pool's list.
fn seed(core: &MadarCore, allowance: i32) {
    core.store
        .kv_put(
            menu::K_MENU_ITEMS,
            &json!([
                item(LATTE, "Latte", 6000, &[("Small", 6000), ("Large", 9000)]),
                item(TEA, "Tea", 3000, &[]),
                item(CAKE, "Cake", 4000, &[]),
            ])
            .to_string(),
        )
        .unwrap();
    core.store
        .kv_put(
            menu::K_ADDONS,
            &json!([
                addon(SYRUP_VANILLA, "Vanilla", "syrup", 500),
                addon(SYRUP_CARAMEL, "Caramel", "syrup", 1200),
                addon(EXTRA_SHOT, "Extra shot", "extra", 1500),
                addon(OAT, "Oat milk", "milk_type", 2000),
            ])
            .to_string(),
        )
        .unwrap();
    let opt = |id: &str, name: &str, price: i64, default: bool| json!({ "id": id, "name": name, "price": price, "is_available": true, "is_default": default });
    core.store
        .kv_put(
            menu::K_UNIFIED,
            &json!({ "catalog_revision": 1, "items": [{ "id": LATTE, "modifier_groups": [
                { "group_id": G_SYRUP, "name": "Syrup", "selection_type": "single", "min": 1, "max": 1,
                  "is_required": true, "effect": "adds",
                  "options": [opt(SYRUP_VANILLA, "Vanilla", 500, true), opt(SYRUP_CARAMEL, "Caramel", 1200, false)] },
                { "group_id": G_EXTRAS, "name": "Extras", "selection_type": "multi", "min": 0,
                  "is_required": false, "effect": "adds", "options": [opt(EXTRA_SHOT, "Extra shot", 1500, false)] },
                { "group_id": G_MILK, "name": "Milk", "selection_type": "single", "min": 1, "max": 1,
                  "is_required": true, "effect": "swaps", "legacy_addon_type": "milk_type",
                  "options": [opt(OAT, "Oat milk", 2000, true)] },
            ]}]})
            .to_string(),
        )
        .unwrap();
    core.store
        .kv_put(
            menu::K_PAYMENT_METHODS,
            r##"[{"id":"00000000-0000-0000-0000-0000000000e1","name":"Cash","is_cash":true,"is_active":true,"created_at":"2026-01-01T00:00:00Z"}]"##,
        )
        .unwrap();
    set_pool(core, true, allowance, &[LATTE, TEA]);
    core.invalidate_catalog_cache();
    grant(core);
}

fn set_pool(core: &MadarCore, enabled: bool, allowance: i32, items: &[&str]) {
    core.store
        .kv_put(
            crate::branch_reads::F_STAFF_POOL.1,
            &json!({ "enabled": enabled, "daily_allowance": allowance, "eligible_item_ids": items }).to_string(),
        )
        .unwrap();
}

fn grant(core: &MadarCore) {
    if let Some(sess) = core.session.write().unwrap().as_mut() {
        let caps = ["orders.create", "payments.create", "till.open", crate::staff_drink::CAP_STAFF_DRINK]
            .map(String::from)
            .to_vec();
        sess.authz = Some(crate::session::AuthzGrants { capabilities: caps, ..Default::default() });
    }
}

fn sel(id: &str) -> cart::AddonSelection {
    cart::AddonSelection { addon_item_id: id.into(), qty: 1 }
}

fn add_latte(core: &MadarCore, size: &str, addons: &[&str], qty: i64) -> String {
    let before: Vec<String> = core.cart_lines(None).unwrap().into_iter().map(|l| l.key).collect();
    let lines = core
        .cart_add_configured(None, LATTE.into(), Some(size.into()), addons.iter().map(|a| sel(a)).collect(), vec![], qty, None)
        .unwrap();
    lines.into_iter().map(|l| l.key).find(|k| !before.contains(k)).expect("a new line")
}

fn marked(core: &MadarCore) -> Vec<cart::CartLineView> {
    core.cart_lines(None).unwrap().into_iter().filter(|l| l.staff_drink.is_some()).collect()
}

fn pay(amount: i64) -> checkout::CheckoutInput {
    checkout::CheckoutInput {
        payment_method_id: CASH.into(),
        amount_tendered_minor: amount,
        tip_minor: 0,
        tip_payment_method_id: None,
        customer_name: None,
        notes: None,
        splits: vec![],
        loyalty_customer_id: None,
        dine_in: false,
        customer_id: None,
        loyalty_redemptions: vec![],
    }
}

fn order_request(core: &MadarCore) -> Value {
    let op = core.store.pending().unwrap().into_iter().find(|i| i.op_type == "create_order").expect("a queued sale");
    let (env, _) = core.replay_envelope(&op).map_err(|_| "envelope").unwrap();
    env["request"].clone()
}

// ── the mark ────────────────────────────────────────────────────────────────

#[tokio::test]
async fn marking_a_line_prices_it_by_the_rule_and_spends_nothing() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core, 5);
    // Large + the default syrup + an optional shot: the SMALL size and the
    // default syrup are free; the size difference and the shot are paid.
    let key = add_latte(&core, "Large", &[SYRUP_VANILLA, EXTRA_SHOT], 1);
    let lines = core.mark_staff_drink(None, key.clone(), " for Sara ".into(), None).unwrap();
    let l = lines.iter().find(|l| l.staff_drink.is_some()).expect("marked");
    let m = l.staff_drink.as_ref().unwrap();
    assert_ne!(l.key, key, "a marked line is its own line");
    assert_eq!(m.note, "for Sara");
    assert_eq!(l.line_total_minor, 9000 + 500 + 1500, "the line still shows its NORMAL price");
    assert_eq!(m.comp_minor, 6000 + 500);
    assert_eq!(m.charged_minor, 3000 + 1500);
    assert!(uuid::Uuid::parse_str(&m.id).is_ok(), "a client-minted drink id");

    // Nothing is spent until the order is charged.
    assert_eq!(core.staff_pool_today().unwrap().pool.used, 0);
    assert!(core.staff_drinks_today().unwrap().is_empty());
    assert!(core.store.pending().unwrap().iter().all(|i| i.op_type != "record_staff_drink"));
}

#[tokio::test]
async fn a_blank_note_an_ineligible_item_and_a_table_cart_are_refused() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core, 5);
    let key = add_latte(&core, "Small", &[SYRUP_VANILLA], 1);
    assert!(matches!(
        core.mark_staff_drink(None, key.clone(), "   ".into(), None),
        Err(crate::CoreError::Validation { field, .. }) if field == "note"
    ));
    assert!(matches!(
        core.mark_staff_drink(Some("table-1".into()), key.clone(), "x".into(), None),
        Err(crate::CoreError::Validation { field, .. }) if field == "table"
    ));
    core.cart_add(None, CAKE.into(), "Cake".into(), 4000).unwrap();
    assert!(matches!(
        core.mark_staff_drink(None, CAKE.into(), "x".into(), None),
        Err(crate::CoreError::Validation { field, .. }) if field == "item"
    ));
    assert!(marked(&core).is_empty());
}

#[tokio::test]
async fn the_mark_survives_a_restart_and_its_note_can_be_edited_or_the_mark_removed() {
    let db = std::env::temp_dir()
        .join(format!("madar_staff_mark_{}.sqlite", uuid::Uuid::new_v4().simple()))
        .to_string_lossy()
        .to_string();
    let id;
    {
        let core = testkit::offline_core("http://127.0.0.1:1", &db).await;
        seed(&core, 5);
        let key = add_latte(&core, "Large", &[SYRUP_VANILLA], 1);
        core.mark_staff_drink(None, key, "for Sara".into(), None).unwrap();
        id = marked(&core)[0].staff_drink.as_ref().unwrap().id.clone();
    }
    let core = testkit::offline_core("http://127.0.0.1:1", &db).await;
    grant(&core);
    let l = marked(&core).pop().expect("the mark is on the stored line");
    let m = l.staff_drink.clone().unwrap();
    assert_eq!((m.id.as_str(), m.note.as_str(), m.comp_minor, m.charged_minor), (id.as_str(), "for Sara", 6500, 3000));

    // Edit the note: same drink, same key.
    let lines = core.edit_staff_drink_note(None, l.key.clone(), "for Omar, closing".into()).unwrap();
    let again = lines.iter().find(|x| x.key == l.key).unwrap().staff_drink.clone().unwrap();
    assert_eq!((again.id.as_str(), again.note.as_str()), (id.as_str(), "for Omar, closing"));
    assert!(core.edit_staff_drink_note(None, l.key.clone(), "  ".into()).is_err(), "a note is still required");

    // Remove the mark: back to the normal price.
    let before = core.cart_totals(None).unwrap();
    let lines = core.unmark_staff_drink(None, l.key.clone()).unwrap();
    assert!(lines.iter().all(|x| x.staff_drink.is_none()));
    let after = core.cart_totals(None).unwrap();
    assert_eq!(after.subtotal_minor, before.subtotal_minor + 6500);
}

#[tokio::test]
async fn changing_the_size_the_addons_or_the_quantity_recomputes_the_comp() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core, 9);
    let key = add_latte(&core, "Small", &[SYRUP_VANILLA], 1);
    core.mark_staff_drink(None, key, "n".into(), None).unwrap();
    let l = marked(&core).pop().unwrap();
    assert_eq!(l.staff_drink.as_ref().unwrap().charged_minor, 0, "the base configuration is wholly free");

    // Quantity: n units are n times the per-unit comp.
    let lines = core.cart_set_qty(None, l.key.clone(), 3).unwrap();
    let m = lines.iter().find_map(|x| x.staff_drink.clone()).unwrap();
    assert_eq!((m.comp_minor, m.charged_minor), (3 * 6500, 0));

    // A pricier pick in the required group pays its difference; a bigger size
    // pays its difference; an optional add-on pays in full. The mark follows
    // the edited line and keeps its drink id.
    let lines = core
        .cart_replace_configured(None, l.key.clone(), LATTE.into(), Some("Large".into()),
            vec![sel(SYRUP_CARAMEL), sel(EXTRA_SHOT)], vec![], 2, None)
        .unwrap();
    let edited = lines.iter().find(|x| x.staff_drink.is_some()).expect("still a staff drink");
    let m2 = edited.staff_drink.clone().unwrap();
    assert_eq!(m2.id, m.id);
    assert_eq!(edited.line_total_minor, 2 * (9000 + 1200 + 1500));
    assert_eq!(m2.comp_minor, 2 * (6000 + 500));
    assert_eq!(m2.charged_minor, 2 * (3000 + 700 + 1500));
}

#[tokio::test]
async fn a_swap_group_is_never_a_comp_group() {
    // Oat milk rings as its difference over the recipe's milk (here the full
    // 2000: no base milk is modelled) and STAYS charged, although the milk
    // group is "required" with oat as its default.
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core, 5);
    let key = add_latte(&core, "Small", &[SYRUP_VANILLA, OAT], 1);
    let lines = core.mark_staff_drink(None, key, "n".into(), None).unwrap();
    let m = lines.iter().find_map(|x| x.staff_drink.clone()).unwrap();
    assert_eq!((m.comp_minor, m.charged_minor), (6500, 2000));
}

#[tokio::test]
async fn a_mark_is_dropped_with_a_reason_when_the_line_stops_being_eligible() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core, 5);
    let key = add_latte(&core, "Small", &[SYRUP_VANILLA], 1);
    core.mark_staff_drink(None, key, "n".into(), None).unwrap();
    assert!(core.take_staff_drink_notices(None).is_empty(), "nothing to say while it stands");

    // A settings sync takes the item off the pool's list.
    set_pool(&core, true, 5, &[TEA]);
    let said = core.take_staff_drink_notices(None);
    assert_eq!(said.len(), 1);
    assert!(said[0].contains("Latte") && said[0].contains("staff pool list"), "{said:?}");
    assert!(marked(&core).is_empty());
    assert_eq!(core.cart_totals(None).unwrap().subtotal_minor, 6500, "back to the normal price");
    assert!(core.take_staff_drink_notices(None).is_empty(), "a reason is said once");
}

#[tokio::test]
async fn a_marked_counter_cart_turned_into_a_table_bill_loses_its_marks() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core, 5);
    let key = add_latte(&core, "Small", &[SYRUP_VANILLA], 1);
    core.mark_staff_drink(None, key, "n".into(), None).unwrap();

    // Parked onto a table: the parked payload carries no mark.
    core.hold_cart_on_table(None, "Table 4".into(), None, None, Some("00000000-0000-0000-0000-00000000aa04".into())).unwrap();
    let said = core.take_staff_drink_notices(None);
    assert!(said.iter().any(|s| s.contains("table")), "{said:?}");
    let drafts = core.store.kv_get("held:mirror").unwrap().unwrap_or_default();
    assert!(!drafts.contains("staff_drink"), "no mark rides a table's parked cart: {drafts}");

    // Aimed at a bill / fired: the host asks the core to drop them.
    let key = add_latte(&core, "Small", &[SYRUP_VANILLA], 1);
    core.mark_staff_drink(None, key, "n".into(), None).unwrap();
    let said = core.drop_staff_marks_for_bill(None);
    assert_eq!(said.len(), 1);
    assert!(marked(&core).is_empty());
    assert_eq!(core.cart_totals(None).unwrap().subtotal_minor, 6500);
}

#[tokio::test]
async fn a_fired_round_never_carries_a_staff_drink() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core, 5);
    let key = add_latte(&core, "Small", &[SYRUP_VANILLA], 1);
    core.mark_staff_drink(None, key, "n".into(), None).unwrap();
    core.fire_ticket(None, None, None, None, None, None).await.unwrap();
    let op = core.store.pending().unwrap().into_iter().find(|i| i.op_type == "open_ticket").unwrap();
    assert!(!op.payload.contains("staff_drink"), "{}", op.payload);
    assert_eq!(core.staff_pool_today().unwrap().pool.used, 0, "and nothing came off the pool");
}

#[tokio::test]
async fn two_marked_lines_cannot_both_claim_the_last_drink_of_the_day() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core, 1);
    let first = add_latte(&core, "Small", &[SYRUP_VANILLA], 1);
    core.cart_add(None, TEA.into(), "Tea".into(), 3000).unwrap();

    let ask = |line_key: Option<String>, item: &str| {
        core.preview_staff_drink(crate::staff_drink::StaffDrinkInput {
            menu_item_id: item.into(),
            note: "n".into(),
            quantity: 1,
            line_key,
            ..Default::default()
        })
        .unwrap()
    };
    assert!(!ask(None, LATTE).decision.overspent, "the last drink of the day is still there");
    core.mark_staff_drink(None, first, "n".into(), None).unwrap();

    // The tea is asked about with the latte already marked: it would go over.
    let tea = ask(None, TEA);
    assert!(tea.decision.allowed && tea.decision.overspent, "marked-but-uncharged drinks count");
    assert!(!tea.over_warning.is_empty());
    // The marked latte, reopened from its badge, does not count itself.
    let latte_key = marked(&core)[0].key.clone();
    assert!(!ask(Some(latte_key), LATTE).decision.overspent);

    // Both marked and charged: the first is inside the allowance, the second over.
    core.mark_staff_drink(None, TEA.into(), "n".into(), None).unwrap();
    core.open_till(0, None).await.unwrap();
    let receipt = core.checkout(None, pay(0)).await.unwrap();
    let req = order_request(&core);
    let flags: Vec<bool> = req["items"].as_array().unwrap().iter().map(|i| i["staff_drink"]["overspent"].as_bool().unwrap()).collect();
    assert_eq!(flags, vec![false, true]);
    assert_eq!(core.staff_pool_today().unwrap().pool.over, 1);
    assert_eq!(receipt.staff_notice.as_deref(), Some("Staff drinks: 1 over today's allowance"));
}

// ── reward × staff drink ────────────────────────────────────────────────────

#[tokio::test]
async fn a_staff_drink_is_never_a_reward_and_a_reward_never_a_staff_drink() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core, 5);
    let key = add_latte(&core, "Small", &[SYRUP_VANILLA], 1);
    core.mark_staff_drink(None, key, "n".into(), None).unwrap();
    let rl = core.cart_reward_lines(None).unwrap();
    assert!(rl[0].is_staff_drink, "the reward board is told, and offers nothing on it");

    // Priced: a reward asked for on the marked line covers nothing.
    let with = core
        .cart_totals_with_rewards(None, vec![checkout::CheckoutRedemption { item_index: 0, ticket_line_id: None, units: 1 }])
        .unwrap();
    assert_eq!(with, core.cart_totals(None).unwrap());

    // Charged: refused before anything is queued.
    core.open_till(0, None).await.unwrap();
    let mut input = pay(0);
    input.loyalty_redemptions = vec![checkout::CheckoutRedemption { item_index: 0, ticket_line_id: None, units: 1 }];
    let lines = core.cart_lines(None).unwrap();
    let err = checkout::reward_units_by_line(&lines, &input.loyalty_redemptions).unwrap_err();
    assert!(format!("{err:?}").contains(checkout::STAFF_DRINK_NOT_A_REWARD));
}

// ── the bill ────────────────────────────────────────────────────────────────

#[tokio::test]
async fn tax_and_the_order_discount_see_the_charged_part_only() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await; // 14% exclusive
    seed(&core, 5);
    core.store
        .kv_put(menu::K_DISCOUNTS, r#"[{"created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z","dtype":"percentage","id":"00000000-0000-0000-0000-00000000d001","is_active":true,"name":"10% off","name_translations":{},"org_id":"00000000-0000-0000-0000-0000000000ff","value":10,"value_rate":0.10}]"#)
        .unwrap();
    let key = add_latte(&core, "Large", &[SYRUP_VANILLA, EXTRA_SHOT], 1); // rings 11000
    core.cart_add(None, CAKE.into(), "Cake".into(), 4000).unwrap();
    let full = core.cart_totals(None).unwrap();
    assert_eq!((full.subtotal_minor, full.tax_minor, full.total_minor), (15000, 2100, 17100));

    core.mark_staff_drink(None, key, "n".into(), None).unwrap(); // comp 6500, charged 4500
    let t = core.cart_totals(None).unwrap();
    assert_eq!(t.subtotal_minor, 4500 + 4000, "the comp leaves before the subtotal is formed");
    assert_eq!(t.tax_minor, 1190, "14% of the charged part");
    assert_eq!(t.total_minor, 9690);

    // An order-level discount applies AFTER the comp, to what remains.
    core.cart_set_discount(None, "00000000-0000-0000-0000-00000000d001".into()).unwrap();
    let d = core.cart_totals(None).unwrap();
    assert_eq!(d.discount_minor, 850);
    assert_eq!(d.tax_minor, 1071);
    assert_eq!(d.total_minor, 8500 - 850 + 1071);

    // The same figures through the engine directly: a wholly free line.
    let b = crate::pricing::price_cart(crate::pricing::PriceCartInput {
        lines: vec![crate::pricing::CartLine {
            quantity: 2, unit_price: 3000, reward_units: 0, staff_comp_minor: 99_999,
            addons: vec![], optionals: vec![],
        }],
        discount_kind: crate::pricing::DiscountKind::None, discount_value: 0.0, tax_rate: 0.14, tax_inclusive: false,
        service_charge_rate: 0.0, service_charge_taxable: false, amount_tendered: None, cash_tip: 0,
    });
    assert_eq!((b.staff_comp_minor, b.subtotal_minor, b.tax_minor, b.total_minor), (6000, 0, 0, 0), "capped at what rang");
}

// ── the wire ────────────────────────────────────────────────────────────────

#[tokio::test]
async fn the_order_line_carries_exactly_what_the_contract_says() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core, 5);
    let key = add_latte(&core, "Large", &[SYRUP_CARAMEL, EXTRA_SHOT], 2);
    core.cart_add(None, CAKE.into(), "Cake".into(), 4000).unwrap();
    core.mark_staff_drink(None, key, "  for Sara ".into(), None).unwrap();
    let id = marked(&core)[0].staff_drink.as_ref().unwrap().id.clone();
    core.open_till(0, None).await.unwrap();
    core.checkout(None, pay(100_000)).await.unwrap();

    let req = order_request(&core);
    let line = &req["items"][0];
    // Byte-for-field: `staff_drink { id, note, comp_minor, overspent }`.
    assert_eq!(line["staff_drink"], json!({ "id": id, "note": "for Sara", "comp_minor": 13000, "overspent": false }));
    assert_eq!(
        line["staff_drink"].as_object().unwrap().keys().cloned().collect::<Vec<_>>(),
        vec!["comp_minor", "id", "note", "overspent"]
    );
    // Normal prices on the line and its picks.
    assert_eq!(line["unit_price"], 9000);
    assert_eq!(line["quantity"], 2);
    let picks: Vec<i64> = line["addons"].as_array().unwrap().iter().map(|a| a["unit_price"].as_i64().unwrap()).collect();
    assert_eq!(picks, vec![1200, 1500]);
    // A paid line never grows the field.
    assert!(req["items"][1].get("staff_drink").is_none());
    // The order's money is NET of the comp: 2×(9000+1200+1500) − 13000 + 4000.
    assert_eq!(req["subtotal"], 14400);
    assert_eq!(req["tax_amount"], 2016);
    assert_eq!(req["total_amount"], 16416);
    // And no separate record-only op was queued for the drink.
    assert!(core.store.pending().unwrap().iter().all(|i| i.op_type != "record_staff_drink"));
}

// ── charge: the pool entry, offline, the LAN, the receipt ───────────────────

#[tokio::test]
async fn charging_offline_writes_the_pool_entry_with_the_sale_and_tells_the_lan() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core, 3);
    let key = add_latte(&core, "Large", &[SYRUP_VANILLA], 2);
    core.mark_staff_drink(None, key, "for the closers".into(), None).unwrap();
    let id = marked(&core)[0].staff_drink.as_ref().unwrap().id.clone();
    core.open_till(0, None).await.unwrap();
    let receipt = core.checkout(None, pay(10_000)).await.unwrap();
    assert!(receipt.queued_offline);
    assert_eq!(receipt.staff_notice.as_deref(), Some("Staff drinks: 1 left today"));

    // The drink is counted the instant the sale is rung — 2 units.
    assert_eq!(core.staff_pool_today().unwrap().pool.used, 2);
    let drinks = core.staff_drinks_today().unwrap();
    assert_eq!(drinks.len(), 1);
    assert_eq!((drinks[0].id.as_str(), drinks[0].quantity, drinks[0].note.as_str()), (id.as_str(), 2, "for the closers"));
    assert_eq!((drinks[0].comp_minor, drinks[0].extras_minor), (Some(13000), Some(6000)));
    assert!(drinks[0].queued, "it rides the queued sale");
    let row = core.store.with_conn(|c| ledger::staff_drinks::raw(c, &id)).unwrap().unwrap();
    assert_eq!(row["order_id"], receipt.local_order_id);

    // Published over the LAN as a drink, so the counter's other till counts it.
    let logged: i64 = core
        .store
        .with_conn(|c| Ok(c.query_row(
            "SELECT COUNT(*) FROM lan_log WHERE event_type='staff_drink.recorded' AND data LIKE ?1",
            [format!("%{id}%")], |r| r.get(0))?))
        .unwrap();
    assert_eq!(logged, 1);
    // A peer applies exactly that payload and counts the same drink once.
    let peer = testkit::offline_core("http://127.0.0.1:1", "").await;
    crate::staff_drink::apply_lan(&peer.store, &row.to_string());
    crate::staff_drink::apply_lan(&peer.store, &row.to_string());
    assert_eq!(peer.staff_pool_today().unwrap().pool.used, 2);

    // The cart is spent; an abandoned cart would have burned nothing.
    assert!(core.cart_lines(None).unwrap().is_empty());

    // Giving up on the sale gives the drinks back.
    let sale = receipt.local_order_id.clone();
    core.store.with_conn(|c| Ok(c.execute("UPDATE outbox SET status='dead' WHERE id=?1", [&sale])?)).unwrap();
    assert!(core.discard_outbox_item(sale).unwrap());
    assert_eq!(core.staff_pool_today().unwrap().pool.used, 0);
}

#[tokio::test]
async fn the_receipt_prints_the_normal_price_then_the_comp_as_a_line_discount() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core, 3);
    let key = add_latte(&core, "Large", &[SYRUP_VANILLA, EXTRA_SHOT], 1);
    core.mark_staff_drink(None, key, "n".into(), None).unwrap();
    core.open_till(0, None).await.unwrap();
    let r = core.checkout(None, pay(10_000)).await.unwrap();
    let l = &r.lines[0];
    assert_eq!(l.line_total_minor, 11000, "normal price");
    assert_eq!((l.staff_label.as_deref(), l.staff_comp_minor), (Some("Staff drink"), 6500));
    assert_eq!(r.subtotal_minor, 4500, "the comp is already off the subtotal");

    // The stored order projects the same way (the server's figures are NET:
    // the size part is off `line_total`, the syrup's part off the pick).
    let full: madar_api::models::OrderFull = serde_json::from_value(server_order(&json!({
        "idempotency_key": r.local_order_id, "branch_id": testkit::BRANCH, "till_id": uuid::Uuid::new_v4(),
        "payment_method": "Cash", "subtotal": 4500, "tax_amount": 630, "total_amount": 5130,
        "created_at": "2026-09-21T10:00:00Z",
        "items": [{ "menu_item_id": LATTE, "quantity": 1, "unit_price": 9000, "size_label": "Large",
            "addons": [{ "addon_item_id": SYRUP_VANILLA, "unit_price": 500, "quantity": 1 },
                       { "addon_item_id": EXTRA_SHOT, "unit_price": 1500, "quantity": 1 }],
            "staff_drink": { "id": uuid::Uuid::new_v4(), "note": "n", "comp_minor": 6500 } }]
    }), true))
    .expect("the server's order decodes");
    let again = crate::orders::order_to_receipt(&full, "en");
    assert_eq!(again.lines[0].line_total_minor, 9000, "the size part goes back on: normal price");
    // (the stub server comps 500 less than the till said: ITS figure prints)
    assert_eq!((again.lines[0].staff_label.as_deref(), again.lines[0].staff_comp_minor), (Some("Staff drink"), 6000));
    assert_eq!(again.subtotal_minor, 5000);
}

// ── the server's answer ─────────────────────────────────────────────────────

/// The order a server answers a replayed `create_order` with. `speaks` = it
/// implements the staff-drink contract (names the pooled line and its comp,
/// here deliberately 500 LESS than the till said, so adoption is visible).
fn server_order(req: &Value, speaks: bool) -> Value {
    let order_id = uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, req["idempotency_key"].to_string().as_bytes());
    let mut short = 0i64;
    let items: Vec<Value> = req["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|it| {
            let unit = it["unit_price"].as_i64().unwrap_or(0);
            let qty = it["quantity"].as_i64().unwrap_or(1);
            let sd = it.get("staff_drink").filter(|s| !s.is_null());
            let comp = sd.filter(|_| speaks).map(|s| (s["comp_minor"].as_i64().unwrap_or(0) - 500).max(0)).unwrap_or(0);
            if sd.is_some() && speaks {
                short += 500;
            }
            let addons: Vec<Value> = it["addons"].as_array().cloned().unwrap_or_default().iter().enumerate().map(|(n, a)| {
                let mut row = json!({ "id": uuid::Uuid::new_v4(), "order_item_id": uuid::Uuid::new_v4(), "addon_item_id": a["addon_item_id"],
                    "addon_name": format!("pick {n}"), "unit_price": a["unit_price"], "quantity": a["quantity"],
                    "line_total": a["unit_price"].as_i64().unwrap_or(0) * a["quantity"].as_i64().unwrap_or(1) * qty,
                    "name_translations": {} });
                if speaks { row["staff_comp_minor"] = json!(if n == 0 && comp >= 500 { 500 } else { 0 }); }
                row
            }).collect();
            let on_picks: i64 = addons.iter().map(|a| a.get("staff_comp_minor").and_then(Value::as_i64).unwrap_or(0)).sum();
            let mut row = json!({ "id": uuid::Uuid::new_v4(), "order_id": order_id, "menu_item_id": it["menu_item_id"],
                "item_name": "Latte", "name_translations": {}, "size_label": it["size_label"], "unit_price": unit,
                "quantity": qty, "line_total": unit * qty - (comp - on_picks).max(0), "addons": addons, "optionals": [],
                "deductions_snapshot": [], "cost_missing": false });
            if speaks {
                row["staff_comp_minor"] = json!(comp);
                row["staff_drink_id"] = sd.map(|s| s["id"].clone()).unwrap_or(Value::Null);
            }
            row
        })
        .collect();
    // A contract server that comps 500 less charges 500 more (+14%).
    let subtotal = req["subtotal"].as_i64().unwrap() + short;
    let tax = (subtotal * 14 + 50) / 100;
    json!({
        "id": order_id, "branch_id": req["branch_id"], "till_id": req["till_id"], "shift_id": req["till_id"],
        "teller_id": testkit::TELLER, "teller_name": "Sara", "order_number": 7, "order_ref": req["order_ref"],
        "status": "completed", "order_type": "takeaway", "payment_method": req["payment_method"],
        "payment_legs": [], "subtotal": subtotal, "tax_amount": tax, "total_amount": subtotal + tax,
        "discount_amount": 0, "discount_value": 0, "delivery_fee": 0, "created_at": req["created_at"], "items": items,
    })
}

async fn replaying_server(speaks: bool) -> Stub {
    Stub::start(move |r| {
        if r.path.starts_with("/sync/replay") {
            let body = r.json();
            return Some(match body["op"].as_str().unwrap_or("") {
                "open_till" => StubResponse::json(201, json!({
                    "id": body["request"]["id"], "branch_id": testkit::BRANCH, "teller_id": testkit::TELLER,
                    "teller_name": "Sara", "status": "open", "opening_cash": body["request"]["opening_cash"],
                    "opened_at": body["request"]["opened_at"], "opening_cash_was_edited": false,
                    "verification": "unverified", "opened_while_another_open": false, "disagreement_count": 0})),
                "create_order" => StubResponse::json(201, server_order(&body["request"], speaks)),
                "record_staff_drink" => StubResponse::json(201, body["request"].clone()),
                _ => StubResponse::json(200, json!({ "id": uuid::Uuid::new_v4() })),
            });
        }
        if r.path.starts_with("/sync/pull") {
            return Some(StubResponse::text(200, r#"{"full":false,"next":1,"has_more":false,"server_time":"2026-09-21T10:00:00Z","types":[],"data":{}}"#));
        }
        None
    })
    .await
}

async fn ring_a_staff_latte(core: &MadarCore) -> (String, checkout::ReceiptView) {
    seed(core, 5);
    core.set_online(true);
    let key = add_latte(core, "Large", &[SYRUP_VANILLA], 1);
    core.mark_staff_drink(None, key, "for Sara".into(), None).unwrap();
    let id = marked(core)[0].staff_drink.as_ref().unwrap().id.clone();
    core.open_till(0, None).await.unwrap();
    let receipt = core.checkout(None, pay(10_000)).await.unwrap();
    core.push_and_refresh().await.ok();
    (id, receipt)
}

#[tokio::test]
async fn the_servers_figures_are_adopted_into_the_sale_and_the_drink() {
    let stub = replaying_server(true).await;
    let core = testkit::online_core(&stub.base, "").await;
    let (id, receipt) = ring_a_staff_latte(&core).await;
    assert_eq!(receipt.subtotal_minor, 3000, "the till: 9500 − 6500");

    // The sale's row now says what the SERVER stored.
    let row: Value = core
        .store
        .with_conn(|c| Ok(c.query_row("SELECT raw FROM ledger_orders WHERE okey=?1", [&receipt.local_order_id], |r| r.get::<_, String>(0))?))
        .map(|raw| serde_json::from_str(&raw).unwrap())
        .unwrap();
    assert_eq!((row["subtotal"].as_i64(), row["total_amount"].as_i64()), (Some(3500), Some(3990)));
    // …and so does the drink: the server's comp, the rest as extras, linked to
    // the server's order.
    let drink = core.store.with_conn(|c| ledger::staff_drinks::raw(c, &id)).unwrap().unwrap();
    assert_eq!((drink["comp_minor"].as_i64(), drink["extras_minor"].as_i64()), (Some(6000), Some(3500)));
    assert_eq!(drink["order_id"], row["id"]);
    // No fallback: the contract server owns the drink's row.
    assert!(stub.requests("/sync/replay").iter().all(|r| r.json()["op"] != "record_staff_drink"));
    assert_eq!(core.staff_old_server_notice(receipt.local_order_id.clone()), None);
    // The reprint shows the server's comp as the line discount.
    let again = core.order_receipt_view(receipt.local_order_id).await.unwrap();
    assert_eq!((again.lines[0].staff_comp_minor, again.lines[0].line_total_minor, again.subtotal_minor), (6000, 9000, 3500));
    assert_eq!(core.staff_pool_today().unwrap().pool.used, 1, "counted once");
}

#[tokio::test]
async fn an_old_server_keeps_the_sale_records_the_drink_the_old_way_and_says_so() {
    let stub = replaying_server(false).await;
    let core = testkit::online_core(&stub.base, "").await;
    let (id, receipt) = ring_a_staff_latte(&core).await;
    core.push_and_refresh().await.ok(); // the fallback op drains too

    // The sale is there, exactly as that server priced it. Nothing was lost.
    let row: Value = core
        .store
        .with_conn(|c| Ok(c.query_row("SELECT raw FROM ledger_orders WHERE okey=?1", [&receipt.local_order_id], |r| r.get::<_, String>(0))?))
        .map(|raw| serde_json::from_str(&raw).unwrap())
        .unwrap();
    assert_eq!(row["status"], "completed");
    assert_eq!(row["total_amount"].as_i64(), Some(3420));
    assert_eq!(core.store.dead_count().unwrap(), 0);

    // The pool entry went through the record-only op, under the SAME id.
    let sent: Vec<Value> = stub.requests("/sync/replay").iter().map(|r| r.json()).filter(|b| b["op"] == "record_staff_drink").collect();
    assert_eq!(sent.len(), 1, "exactly one fallback record");
    let req = &sent[0]["request"];
    assert_eq!(req["id"], id);
    assert_eq!(req["note"], "for Sara");
    assert_eq!(req["menu_item_id"], LATTE);
    assert_eq!(req["order_id"], row["id"], "linked to the server's order");
    assert!(req.get("comp_minor").is_none() && req.get("business_date").is_none(), "the old body, unchanged");
    assert_eq!(core.staff_pool_today().unwrap().pool.used, 1, "one drink, not two");

    // And the teller is told plainly — on the done card's re-read and by key.
    let said = core.staff_old_server_notice(receipt.local_order_id.clone()).expect("a notice");
    assert!(said.contains("doesn't support free staff drinks"), "{said}");
    let again = core.order_receipt_view(receipt.local_order_id).await.unwrap();
    assert_eq!(again.staff_notice.as_deref(), Some(said.as_str()));
}

#[test]
fn a_feed_row_with_or_without_the_comp_fields_reads_the_same_drink() {
    // new server ↔ this core, and old server ↔ this core: both rows land.
    let s = crate::store::Store::open("").unwrap();
    s.with_conn(|c| {
        let mut row = json!({ "id": "a", "branch_id": "b", "business_date": "2026-09-21", "quantity": 1,
            "item_name": "Latte", "note": "n", "overspent": false, "recorded_at": "2026-09-21T09:00:00Z" });
        ledger::staff_drinks::from_feed(c, &row)?;
        let d = &ledger::staff_drinks::for_day(c, "b", "2026-09-21")?[0];
        assert_eq!((d.comp_minor, d.extras_minor), (None, None));
        row["comp_minor"] = json!(6500);
        row["extras_minor"] = json!(3000);
        row["comp_minor_reported"] = json!(6000);
        ledger::staff_drinks::from_feed(c, &row)?;
        let d = &ledger::staff_drinks::for_day(c, "b", "2026-09-21")?[0];
        assert_eq!((d.comp_minor, d.extras_minor), (Some(6500), Some(3000)));
        assert_eq!(ledger::staff_drinks::used_on(c, "b", "2026-09-21")?, 1);
        Ok(())
    })
    .unwrap();
}

// ── the manager's approval ──────────────────────────────────────────────────

#[tokio::test]
async fn a_teller_without_the_act_marks_with_a_managers_approval_and_it_rides_the_sale() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core, 5);
    // Grants loaded, the staff-drink act not among them — but it is one this
    // person may ask a manager for (the capability carries `approval = true`).
    if let Some(sess) = core.session.write().unwrap().as_mut() {
        let caps = ["orders.create", "payments.create", "till.open"].map(String::from).to_vec();
        sess.authz = Some(crate::session::AuthzGrants {
            capabilities: caps,
            ask_manager: vec![crate::staff_drink::CAP_STAFF_DRINK.into()],
            ..Default::default()
        });
    }
    assert_eq!(core.staff_drink_access().outcome, "needs_approval", "never a wall: a manager can unlock it");
    let key = add_latte(&core, "Small", &[SYRUP_VANILLA], 1);
    assert!(matches!(
        core.mark_staff_drink(None, key.clone(), "for Sara".into(), None),
        Err(crate::CoreError::Forbidden { .. })
    ));
    let wrong = crate::approvals::ApprovalView {
        id: "00000000-0000-0000-0000-00000000ab01".into(),
        capability: "orders.void".into(),
        approver_id: "00000000-0000-0000-0000-0000000000cc".into(),
        approver_name: "Mona".into(),
        amount_minor: None,
        value_minor: None,
        percent_bps: None,
    };
    assert!(core.mark_staff_drink(None, key.clone(), "for Sara".into(), Some(wrong.clone())).is_err(), "an approval for another act unlocks nothing");
    assert!(marked(&core).is_empty());

    let ok = crate::approvals::ApprovalView { capability: crate::staff_drink::CAP_STAFF_DRINK.into(), ..wrong };
    core.mark_staff_drink(None, key, "for Sara".into(), Some(ok.clone())).unwrap();
    assert_eq!(marked(&core).len(), 1);

    // The approval is kept WITH the line and rides the sale's envelope.
    core.open_till(0, None).await.unwrap();
    core.checkout(None, pay(0)).await.unwrap();
    let op = core.store.pending().unwrap().into_iter().find(|i| i.op_type == "create_order").unwrap();
    let (env, _) = core.replay_envelope(&op).map_err(|_| "envelope").unwrap();
    assert_eq!(env["approval"]["id"], ok.id);
    assert_eq!(env["approval"]["capability"], crate::staff_drink::CAP_STAFF_DRINK);
}
