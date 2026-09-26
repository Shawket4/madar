//! Combos and deals on the till, end to end through the real core
//! (COMBOS_CONTRACT §3–§6, §8 "POS (L3)"): the shared rule's vectors read
//! through this device's mirror, the worked example on the cart, merging and
//! editing combo lines, "make it a meal", availability on the branch's clock,
//! deal suggestions / application / dropping, the order on the wire (queued
//! and drained), the receipt and the kitchen, loyalty and staff drinks, and
//! the counted phrases in both languages.

use std::collections::BTreeSet;

use serde_json::{json, Value};

use crate::cart::{self, AddonSelection};
use crate::catalog_pricing::PricingMirror;
use crate::combos::{self, ComboPickInput};
use crate::store::Store;
use crate::testkit::{self, Stub, StubResponse};
use crate::{checkout, i18n, kds, menu, receipt, MadarCore};

const LUNCH: &str = "00000000-0000-0000-0000-00000000c001";
const S_MAIN: &str = "00000000-0000-0000-0000-00000000c0a1";
const S_SIDE: &str = "00000000-0000-0000-0000-00000000c0a2";
const S_DRINK: &str = "00000000-0000-0000-0000-00000000c0a3";
const BURGER: &str = "00000000-0000-0000-0000-00000000b001";
const FRIES: &str = "00000000-0000-0000-0000-00000000b002";
const LATTE: &str = "00000000-0000-0000-0000-00000000b003";
const CROISSANT: &str = "00000000-0000-0000-0000-00000000b004";
const COOKIE: &str = "00000000-0000-0000-0000-00000000b005";
const OAT: &str = "00000000-0000-0000-0000-00000000d001";
const CAT_MAINS: &str = "00000000-0000-0000-0000-00000000ca01";
const CAT_BITES: &str = "00000000-0000-0000-0000-00000000ca02";
const CAT_DRINKS: &str = "00000000-0000-0000-0000-00000000ca03";
const DEAL_BITES: &str = "00000000-0000-0000-0000-00000000de01";
const DEAL_B2G1: &str = "00000000-0000-0000-0000-00000000de02";
const DEAL_HALF: &str = "00000000-0000-0000-0000-00000000de03";
const CASH: &str = "00000000-0000-0000-0000-0000000000e1";
const OTHER_BRANCH: &str = "00000000-0000-0000-0000-000000000002";

// ── the menu ────────────────────────────────────────────────────────────────

fn item(id: &str, name: &str, base: i64, sizes: &[(&str, i64)], category: &str) -> Value {
    json!({
        "base_price": base, "created_at": "2026-06-19T10:00:00Z", "updated_at": "2026-06-19T10:00:00Z",
        "id": id, "org_id": testkit::ORG, "is_active": true, "name": name, "category_id": category,
        "name_translations": {}, "description_translations": {}, "addon_slots": [],
        "allowed_addon_ids": [], "optional_fields": [], "recipes": [], "kind": "item",
        "sizes": sizes.iter().map(|(label, price)| json!({
            "id": uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, format!("{id}:{label}").as_bytes()),
            "is_active": true, "label": label, "menu_item_id": id, "price_override": price })).collect::<Vec<_>>(),
    })
}

fn addon(id: &str, name: &str, kind: &str, price: i64) -> Value {
    json!({ "addon_type": kind, "created_at": "2026-06-19T10:00:00Z", "updated_at": "2026-06-19T10:00:00Z",
            "default_price": price, "id": id, "is_active": true, "name": name,
            "name_translations": { "ar": "حليب شوفان" }, "org_id": testkit::ORG, "ingredients": [] })
}

/// The worked example's combo (§4): P = 15000; Burger, Fries, and a Latte
/// that includes the Regular size.
fn lunch_row() -> Value {
    let mut row = item(LUNCH, "Lunch deal", 15000, &[], CAT_MAINS);
    row["kind"] = json!("combo");
    row["name_translations"] = json!({ "ar": "وجبة الغداء" });
    row["combo"] = json!({
        "is_fixed": true,
        "sell": { "pos": true, "qr": true, "online": true, "delivery": true },
        "windows": [],
        "slots": [
            { "id": S_MAIN, "name": "Main", "sort": 0, "min": 1, "max": 1, "default_item_id": BURGER,
              "choices": [{ "menu_item_id": BURGER }] },
            { "id": S_SIDE, "name": "Side", "sort": 1, "min": 1, "max": 1, "default_item_id": FRIES,
              "choices": [{ "menu_item_id": FRIES }] },
            { "id": S_DRINK, "name": "Drink", "sort": 2, "min": 1, "max": 1, "default_item_id": LATTE,
              "default_size_label": "Regular",
              "choices": [{ "menu_item_id": LATTE, "included_size_label": "Regular" }] },
        ],
    });
    row
}

fn deal_rows() -> Value {
    json!([
        { "id": DEAL_BITES, "name": "Any 2 bites for 90", "name_translations": { "ar": "أي قطعتين بـ 90" },
          "kind": "n_for_price", "qty": 2, "price": 9000, "sort": 0, "is_active": true,
          "pool": [{ "category_id": CAT_BITES }] },
        { "id": DEAL_B2G1, "name": "Buy 2 lattes get 1", "name_translations": {},
          "kind": "buy_get", "qty": 2, "get_qty": 1, "get_percent": 100, "sort": 0, "is_active": true,
          "pool": [{ "menu_item_id": LATTE }] },
    ])
}

/// The menu, with `tweak` applied to the combo row first.
fn seed_with(core: &MadarCore, tweak: impl FnOnce(&mut Value)) {
    let mut lunch = lunch_row();
    tweak(&mut lunch);
    let mut latte = item(
        LATTE,
        "Latte",
        4500,
        &[("Small", 4500), ("Regular", 5000), ("Large", 6000)],
        CAT_DRINKS,
    );
    latte["meal"] = json!({ "combo_id": LUNCH, "slot_id": S_DRINK });
    core.store
        .kv_put(
            menu::K_MENU_ITEMS,
            &json!([
                item(BURGER, "Burger", 12000, &[], CAT_MAINS),
                item(FRIES, "Fries", 4000, &[], CAT_MAINS),
                latte,
                item(CROISSANT, "Croissant", 5500, &[], CAT_BITES),
                item(COOKIE, "Cookie", 4000, &[], CAT_BITES),
                lunch,
            ])
            .to_string(),
        )
        .unwrap();
    core.store
        .kv_put(
            menu::K_ADDONS,
            &json!([addon(OAT, "Oat milk", "extra", 1500)]).to_string(),
        )
        .unwrap();
    core.store
        .kv_put(
            menu::K_PAYMENT_METHODS,
            r##"[{"id":"00000000-0000-0000-0000-0000000000e1","name":"Cash","is_cash":true,"is_active":true,"created_at":"2026-01-01T00:00:00Z"}]"##,
        )
        .unwrap();
    core.store
        .kv_put(menu::K_DEALS, &deal_rows().to_string())
        .unwrap();
    core.invalidate_catalog_cache();
    grant(core, true);
}

fn seed(core: &MadarCore) {
    seed_with(core, |_| {});
}

fn set_deals(core: &MadarCore, rows: Value) {
    core.store.kv_put(menu::K_DEALS, &rows.to_string()).unwrap();
    core.invalidate_catalog_cache();
}

fn grant(core: &MadarCore, deals: bool) {
    if let Some(sess) = core.session.write().unwrap().as_mut() {
        let mut caps: Vec<String> = ["orders.create", "payments.create", "till.open"]
            .map(String::from)
            .to_vec();
        if deals {
            caps.push(crate::deals::CAP_APPLY.to_string());
        }
        sess.authz = Some(crate::session::AuthzGrants {
            capabilities: caps,
            ..Default::default()
        });
    }
}

/// Put the till's clock at `date time` on the branch's wall clock, in `tz`.
fn clock_at(core: &MadarCore, tz: &str, date: &str, time: &str) {
    use chrono::TimeZone;
    core.store.kv_put(checkout::KEY_BRANCH_TZ, tz).unwrap();
    let zone: chrono_tz::Tz = tz.parse().unwrap();
    let naive =
        chrono::NaiveDateTime::parse_from_str(&format!("{date} {time}"), "%Y-%m-%d %H:%M").unwrap();
    // Half a minute in, so the seconds lost to rounding stay inside the minute.
    let target = zone
        .from_local_datetime(&naive)
        .single()
        .unwrap()
        .with_timezone(&chrono::Utc)
        + chrono::Duration::seconds(30);
    let skew = (target - chrono::Utc::now()).num_seconds();
    core.clock_skew_secs
        .store(skew, std::sync::atomic::Ordering::Relaxed);
    let now = core.branch_local_now();
    assert_eq!(
        (now.date.as_str(), &now.time[..5]),
        (date, time),
        "the clock is set"
    );
}

fn pick(slot: &str, item: &str, size: Option<&str>, addons: &[&str]) -> ComboPickInput {
    ComboPickInput {
        slot_id: slot.into(),
        item_id: item.into(),
        size_label: size.map(str::to_string),
        qty: 1,
        addons: addons
            .iter()
            .map(|a| AddonSelection {
                addon_item_id: (*a).into(),
                qty: 1,
            })
            .collect(),
        optional_field_ids: vec![],
        notes: None,
    }
}

/// Burger, Fries and a Latte at `size`, with oat milk or not.
fn lunch_picks(size: &str, oat: bool) -> Vec<ComboPickInput> {
    vec![
        pick(S_MAIN, BURGER, None, &[]),
        pick(S_SIDE, FRIES, None, &[]),
        pick(S_DRINK, LATTE, Some(size), if oat { &[OAT] } else { &[] }),
    ]
}

fn combo_line(lines: &[cart::CartLineView]) -> cart::CartLineView {
    lines
        .iter()
        .find(|l| l.kind == menu::KIND_COMBO)
        .cloned()
        .expect("a combo line")
}

fn line_of(lines: &[cart::CartLineView], item_id: &str) -> cart::CartLineView {
    lines
        .iter()
        .find(|l| l.item_id == item_id && l.kind == menu::KIND_ITEM)
        .cloned()
        .expect("the line")
}

/// Each part's own money on the whole line: share + surcharges + add-ons.
fn part_totals(l: &cart::CartLineView) -> Vec<i64> {
    l.parts
        .iter()
        .map(|p| {
            let extras: i64 = p
                .addons
                .iter()
                .map(|a| a.price_modifier_minor * a.qty)
                .sum::<i64>()
                + p.optionals.iter().map(|o| o.price_minor).sum::<i64>();
            l.qty * (p.share_minor + p.qty * (p.surcharge_minor + extras))
        })
        .collect()
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

fn en(key: &str) -> String {
    i18n::tr("en", key)
}

// ── 1. the shared rule's vectors, through this device's mirror ──────────────

/// A vector id as a UUID (the menu mirror keys everything by UUID).
fn vid(name: &str) -> String {
    uuid::Uuid::new_v5(
        &uuid::Uuid::NAMESPACE_OID,
        format!("combo-vector:{name}").as_bytes(),
    )
    .to_string()
}

/// `combo_vectors.json` with every id (items, options, slots, combos,
/// categories) rewritten as a UUID, consistently everywhere it appears.
fn combo_vectors() -> Value {
    let raw = madar_catalog::vectors::COMBO;
    let v: Value = serde_json::from_str(raw).unwrap();
    let mut ids: BTreeSet<String> = BTreeSet::new();
    let mut add = |s: &Value| {
        if let Some(s) = s.as_str() {
            ids.insert(s.to_string());
        }
    };
    for it in v["items"].as_object().unwrap().values() {
        add(&it["item"]["id"]);
        for o in it["options"].as_array().unwrap() {
            add(&o["id"]);
        }
    }
    for (id, c) in v["combos"].as_object().unwrap() {
        add(&json!(id));
        for s in c["slots"].as_array().unwrap() {
            add(&s["id"]);
            for ch in s["choices"].as_array().unwrap() {
                add(&ch["menu_item_id"]);
                add(&ch["category_id"]);
            }
        }
    }
    for c in v["cases"].as_array().unwrap() {
        for p in c["picks"].as_array().unwrap() {
            add(&p["slot_id"]);
            add(&p["category_id"]);
            for o in p["selection"]["options"].as_array().unwrap() {
                add(&o["id"]);
            }
        }
    }
    for c in v["availability"].as_array().unwrap() {
        for x in c["unavailable_items"]
            .as_array()
            .unwrap()
            .iter()
            .chain(c["empty_categories"].as_array().unwrap())
        {
            add(x);
        }
    }
    let mut text = raw.to_string();
    for id in &ids {
        text = text.replace(&format!("\"{id}\""), &format!("\"{}\"", vid(id)));
    }
    serde_json::from_str(&text).unwrap()
}

/// A vector item as the feed ships it: the legacy fields plus its `pricing`.
fn vector_item_row(fixture: &Value, name: &str, category: Option<&str>, active: bool) -> Value {
    json!({
        "id": fixture["item"]["id"], "org_id": testkit::ORG, "name": name, "name_translations": {},
        "description_translations": {}, "base_price": 0, "is_active": active, "category_id": category,
        "created_at": "2026-06-19T10:00:00Z", "updated_at": "2026-06-19T10:00:00Z", "kind": "item",
        "addon_slots": [], "allowed_addon_ids": [], "optional_fields": [], "recipes": [], "sizes": [],
        "pricing": fixture["item"],
    })
}

fn vector_combo_row(c: &Value) -> Value {
    json!({
        "id": c["id"], "org_id": testkit::ORG, "name": "combo", "name_translations": {},
        "description_translations": {}, "base_price": c["price"], "is_active": c["is_active"],
        "created_at": "2026-06-19T10:00:00Z", "updated_at": "2026-06-19T10:00:00Z", "kind": "combo",
        "addon_slots": [], "allowed_addon_ids": [], "optional_fields": [], "recipes": [], "sizes": [],
        "pricing": { "id": c["id"], "sizes": [{ "label": "one_size", "price": c["price"], "is_active": true }] },
        "combo": { "slots": c["slots"], "windows": c["windows"] },
    })
}

fn vector_addon_rows(options: &[Value]) -> Vec<Value> {
    options
        .iter()
        .map(|o| {
            json!({ "id": o["id"], "name": o["name"], "addon_type": o["kind"], "default_price": o["price"],
                    "is_active": true, "org_id": testkit::ORG, "name_translations": {}, "ingredients": [],
                    "created_at": "2026-06-19T10:00:00Z", "updated_at": "2026-06-19T10:00:00Z", "pricing": o })
        })
        .collect()
}

/// Every quote and refusal case of `combo_vectors.json`, priced by the
/// core's own path — the feed rows into the kv mirror, `menu::combos`,
/// `combo_view_for`, `combos::rule_inputs` (the till's selection
/// normalisation), then the rule; and the cart line built from it sums to
/// the quote. The one case the till answers differently on purpose is an
/// option the menu does not know: the till drops it (a stale cache must not
/// wedge a sale) and prices the rest, as it does for a plain line.
#[test]
fn the_combo_vectors_price_through_the_cores_mirror() {
    let v = combo_vectors();
    let mut priced = 0;
    for case in v["cases"].as_array().unwrap() {
        let name = case["name"].as_str().unwrap();
        let combo = &v["combos"][case["combo"].as_str().unwrap()];
        let mut rows: Vec<Value> = Vec::new();
        let mut options: Vec<Value> = Vec::new();
        let mut picks: Vec<ComboPickInput> = Vec::new();
        for p in case["picks"].as_array().unwrap() {
            let fixture = &v["items"][p["item"].as_str().unwrap()];
            let id = fixture["item"]["id"].as_str().unwrap();
            if !rows.iter().any(|r| r["id"] == id) {
                rows.push(vector_item_row(
                    fixture,
                    p["item"].as_str().unwrap(),
                    p["category_id"].as_str(),
                    true,
                ));
                for o in fixture["options"].as_array().unwrap() {
                    if !options.iter().any(|x| x["id"] == o["id"]) {
                        options.push(o.clone());
                    }
                }
            }
            let sel = &p["selection"];
            picks.push(ComboPickInput {
                slot_id: p["slot_id"].as_str().unwrap().into(),
                item_id: id.into(),
                size_label: sel["size_label"].as_str().map(str::to_string),
                qty: p["quantity"].as_i64().unwrap(),
                addons: sel["options"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|o| AddonSelection {
                        addon_item_id: o["id"].as_str().unwrap().into(),
                        qty: o["quantity"].as_i64().unwrap(),
                    })
                    .collect(),
                optional_field_ids: sel["optionals"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|o| o.as_str().unwrap().to_string())
                    .collect(),
                notes: None,
            });
        }
        rows.push(vector_combo_row(combo));
        let store = Store::open("").unwrap();
        store
            .kv_put(menu::K_MENU_ITEMS, &Value::Array(rows).to_string())
            .unwrap();
        store
            .kv_put(
                menu::K_ADDONS,
                &Value::Array(vector_addon_rows(&options)).to_string(),
            )
            .unwrap();
        let items = menu::menu_items(&store, "en").unwrap();
        let addons = menu::addons(&store, "en").unwrap();
        let pricing = PricingMirror::load(&store);
        let defs = menu::combos(&store, "en").unwrap();
        assert_eq!(defs.len(), 1, "{name}: the combo row parses");
        let def = &defs[0];
        let combo_item = items.iter().find(|i| i.id == def.id).unwrap();
        let n = case["n"].as_i64().unwrap();

        let got = combos::rule_inputs(def, combo_item, &items, &addons, &pricing, &picks)
            .and_then(|(view, ins)| madar_catalog::combo::quote(&view, &ins, n));
        let expected = &case["expected"];
        if name == "unknown_option" {
            // The till drops the option it does not know and prices the rest.
            let q = got.unwrap_or_else(|e| panic!("{name}: {e:?}"));
            assert!(
                q.parts.iter().all(|p| p.options.options.is_empty()),
                "{name}"
            );
            assert_eq!((q.unit_total, q.price), (15000, 15000), "{name}");
            continue;
        }
        match (&got, expected.get("quote"), expected.get("refusal")) {
            (Ok(q), Some(want), _) => {
                assert_eq!(&serde_json::to_value(q).unwrap(), want, "{name}");
                // The cart line from the same picks sums to the quote.
                let line = cart::resolve_combo_line(
                    def, combo_item, &items, &addons, &pricing, &picks, n, None,
                )
                .unwrap_or_else(|e| panic!("{name}: {e:?}"));
                let lines = cart::add_resolved(&store, None, line).unwrap();
                let l = combo_line(&lines);
                assert_eq!(l.line_total_minor, q.line_total(), "{name}");
                assert_eq!(l.unit_price_minor, q.price, "{name}");
                assert_eq!(l.qty, n, "{name}");
                let want_parts: Vec<(String, i64, i64)> = q
                    .parts
                    .iter()
                    .map(|p| (p.menu_item_id.clone(), p.share_unit, p.surcharge_unit))
                    .collect();
                let got_parts: Vec<(String, i64, i64)> = l
                    .parts
                    .iter()
                    .map(|p| (p.item_id.clone(), p.share_minor, p.surcharge_minor))
                    .collect();
                assert_eq!(got_parts, want_parts, "{name}");
                let bill: i64 = cart::bill_lines_of_view(&l)
                    .iter()
                    .map(|b| {
                        b.quantity * b.unit_price
                            + b.addons
                                .iter()
                                .map(|a| a.price_modifier * a.quantity * b.quantity)
                                .sum::<i64>()
                            + b.optionals
                                .iter()
                                .map(|o| o.price * b.quantity)
                                .sum::<i64>()
                    })
                    .sum();
                assert_eq!(
                    bill,
                    q.line_total(),
                    "{name}: the parts enter the bill as the line"
                );
                priced += 1;
            }
            (Err(r), _, Some(want)) => {
                assert_eq!(&serde_json::to_value(r).unwrap(), want, "{name}");
            }
            (other, _, _) => panic!("{name}: got {other:?}, expected {expected}"),
        }
        if let Some(fixed) = case.get("is_fixed").and_then(Value::as_bool) {
            let view = crate::catalog_pricing::combo_view_for(def, combo_item, &pricing);
            assert_eq!(
                madar_catalog::combo::is_fixed(&view),
                fixed,
                "{name}: is_fixed"
            );
        }
    }
    assert!(
        priced >= 14,
        "only {priced} quote cases priced through the core"
    );
}

/// The availability cases a till can meet (the POS channel, a combo the
/// branch has not switched off — a branch-disabled combo reaches the till
/// inactive): through `combos::availability` over the vector's menu, an
/// unavailable item mirrored as switched off and an empty category as one
/// whose items are off.
#[test]
fn the_combo_availability_vectors_through_the_cores_menu() {
    let v = combo_vectors();
    let mut checked = 0;
    for case in v["availability"].as_array().unwrap() {
        if case["channel"] != "pos" || case["branch_enabled"] != true {
            continue;
        }
        let name = case["name"].as_str().unwrap();
        let off: Vec<&str> = case["unavailable_items"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(Value::as_str)
            .collect();
        let empty: Vec<&str> = case["empty_categories"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(Value::as_str)
            .collect();
        let combo = &v["combos"][case["combo"].as_str().unwrap()];
        // The category a category choice names: its members are the vector
        // picks that name it (cola is in it; juice, the item choice, is not).
        let cold = vid("cat-cold");
        let mut rows: Vec<Value> = Vec::new();
        for (key, fixture) in v["items"].as_object().unwrap() {
            if key == "latte_at_branch" {
                continue;
            }
            let id = fixture["item"]["id"].as_str().unwrap();
            let category = (key == "cola").then_some(cold.as_str());
            let active = !off.contains(&id) && !category.is_some_and(|c| empty.contains(&c));
            rows.push(vector_item_row(fixture, key, category, active));
        }
        rows.push(vector_combo_row(combo));
        let store = Store::open("").unwrap();
        store
            .kv_put(menu::K_MENU_ITEMS, &Value::Array(rows).to_string())
            .unwrap();
        let items = menu::menu_items(&store, "en").unwrap();
        let pricing = PricingMirror::load(&store);
        let def = menu::combos(&store, "en").unwrap().remove(0);
        let combo_item = items.iter().find(|i| i.id == def.id).unwrap();
        let view = crate::catalog_pricing::combo_view_for(&def, combo_item, &pricing);
        let at = combos::At {
            sell: serde_json::from_value(case["sell"].clone()).unwrap(),
            branch_id: case["branch_id"].as_str().map(str::to_string),
            now: serde_json::from_value(case["now"].clone()).unwrap(),
        };
        let got = combos::availability(&view, &items, &at)
            .err()
            .map(|w| serde_json::to_value(w).unwrap());
        let want = Some(case["expected"].clone()).filter(|e| !e.is_null());
        assert_eq!(got, want, "{name}");
        checked += 1;
    }
    assert!(checked >= 8, "only {checked} availability cases");
}

/// The deal rules as the `deal_rule` feed rows carry them parse into the
/// rule's own views, names localized.
#[test]
fn the_deal_vectors_rules_parse_from_feed_rows() {
    let v: Value = serde_json::from_str(madar_catalog::vectors::DEAL).unwrap();
    let rows: Vec<Value> = v["deals"]
        .as_object()
        .unwrap()
        .values()
        .map(|d| {
            let mut row = d.clone();
            row["name_translations"] =
                json!({ "ar": format!("{} (ar)", d["name"].as_str().unwrap()) });
            row["seq"] = json!(7);
            row["sell"] = json!({ "pos": true });
            row
        })
        .collect();
    let store = Store::open("").unwrap();
    store
        .kv_put(menu::K_DEALS, &Value::Array(rows.clone()).to_string())
        .unwrap();
    let parsed = crate::deals::rules(&store, "en");
    assert_eq!(parsed.len(), rows.len());
    for d in v["deals"].as_object().unwrap().values() {
        let want: madar_catalog::deal::DealView = serde_json::from_value(d.clone()).unwrap();
        assert!(parsed.contains(&want), "{}", d["id"]);
    }
    let ar = crate::deals::rules(&store, "ar");
    assert!(
        ar.iter().all(|d| d.name.ends_with("(ar)")),
        "names localized"
    );
}

// ── the saving follows the quantity, like the total ─────────────────────────

#[tokio::test]
async fn the_quotes_saving_is_for_the_whole_line_like_its_total() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    // Two lunches: the sheet shows the line total for 2, so "You save" must be
    // the saving on 2 as well (T1 B7: it read 35.00 under a 540.00 line).
    let one = core.combo_quote(None, LUNCH.into(), lunch_picks("Large", true), 1).unwrap();
    let two = core.combo_quote(None, LUNCH.into(), lunch_picks("Large", true), 2).unwrap();
    assert_eq!(two.line_total_minor, 2 * one.line_total_minor);
    assert_eq!(two.saving_minor, 2 * one.saving_minor, "{two:?}");
    assert_eq!(one.saving_minor, 6000);
}

// ── the worked example on the cart ──────────────────────────────────────────

#[tokio::test]
async fn the_worked_example_prices_on_the_cart_as_the_contract_says() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);

    // The sheet's live figures (§4 `combo/lunch_large_latte`).
    let q = core
        .combo_quote(None, LUNCH.into(), lunch_picks("Large", true), 1)
        .unwrap();
    assert!(q.complete && q.refusal.is_none(), "{q:?}");
    assert_eq!(
        (
            q.price_minor,
            q.unit_total_minor,
            q.list_minor,
            q.saving_minor,
            q.surcharge_minor,
            q.extras_minor
        ),
        (15000, 17500, 23500, 6000, 1000, 1500)
    );

    let lines = core
        .cart_add_combo(None, LUNCH.into(), lunch_picks("Large", true), 1, None)
        .unwrap();
    let l = combo_line(&lines);
    assert_eq!(
        (l.name.as_str(), l.kind.as_str(), l.unit_price_minor, l.qty),
        ("Lunch deal", "combo", 15000, 1)
    );
    assert!(
        l.addons.is_empty() && l.optionals.is_empty(),
        "a combo line has no add-ons of its own"
    );
    let shares: Vec<i64> = l.parts.iter().map(|p| p.share_minor).collect();
    assert_eq!(shares, vec![8571, 2858, 3571]);
    let surcharges: Vec<i64> = l.parts.iter().map(|p| p.surcharge_minor).collect();
    assert_eq!(surcharges, vec![0, 0, 1000]);
    assert_eq!(part_totals(&l), vec![8571, 2858, 4571 + 1500]);
    let latte = &l.parts[2];
    assert_eq!(
        (latte.slot_name.as_str(), latte.item_name.as_str()),
        ("Drink", "Latte")
    );
    assert_eq!(latte.size_label.as_deref(), Some("Large"));
    assert_eq!(
        latte.unit_price_minor, 6000,
        "the part's normal price at its size"
    );
    assert_eq!(
        latte
            .addons
            .iter()
            .map(|a| (a.addon_item_id.as_str(), a.price_modifier_minor, a.qty))
            .collect::<Vec<_>>(),
        vec![(OAT, 1500, 1)]
    );
    assert_eq!(
        l.parts[0].size_label, None,
        "an item with no real size shows none"
    );
    assert_eq!(l.line_total_minor, 17500);
    assert_eq!(core.cart_totals(None).unwrap().subtotal_minor, 17500);

    // n = 2: every figure doubles (17142 / 5716 / 9142, add-ons 3000).
    let lines = core.cart_set_qty(None, l.key.clone(), 2).unwrap();
    let l = combo_line(&lines);
    assert_eq!(l.qty, 2);
    let bill = cart::bill_lines_of_view(&l);
    let parts: Vec<i64> = bill.iter().map(|b| b.quantity * b.unit_price).collect();
    assert_eq!(parts, vec![17142, 5716, 9142]);
    let addons: i64 = bill
        .iter()
        .flat_map(|b| {
            b.addons
                .iter()
                .map(move |a| a.price_modifier * a.quantity * b.quantity)
        })
        .sum();
    assert_eq!(addons, 3000);
    assert_eq!(l.line_total_minor, 35000);
    assert_eq!(core.cart_totals(None).unwrap().subtotal_minor, 35000);
}

// ── 2. the cart ─────────────────────────────────────────────────────────────

#[tokio::test]
async fn identical_combos_merge_different_ones_do_not_and_a_combo_line_edits() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    core.cart_add_combo(None, LUNCH.into(), lunch_picks("Large", true), 1, None)
        .unwrap();
    let lines = core
        .cart_add_combo(None, LUNCH.into(), lunch_picks("Large", true), 1, None)
        .unwrap();
    assert_eq!(lines.len(), 1, "the same picks merge");
    assert_eq!(lines[0].qty, 2);
    let large = lines[0].key.clone();
    assert!(large.starts_with(&format!("combo:{LUNCH}|")), "{large}");

    // Different picks (a Regular latte, no oat) are a line of their own.
    let lines = core
        .cart_add_combo(None, LUNCH.into(), lunch_picks("Regular", false), 1, None)
        .unwrap();
    assert_eq!(lines.len(), 2);
    let regular = lines.iter().find(|l| l.key != large).unwrap().clone();
    assert_eq!(
        regular.line_total_minor, 15000,
        "the included size costs nothing more"
    );
    assert_eq!(
        regular.parts[2].size_label.as_deref(),
        Some("Regular"),
        "the size is explicit on the part"
    );

    // The line as a draft to edit: the picks as charged.
    let draft = core.cart_combo_draft(None, regular.key.clone()).unwrap();
    assert_eq!(
        (
            draft.combo_id.as_str(),
            draft.qty,
            draft.line_key.as_deref()
        ),
        (LUNCH, 1, Some(regular.key.as_str()))
    );
    let drink = draft.picks.iter().find(|p| p.slot_id == S_DRINK).unwrap();
    assert_eq!(
        (drink.item_id.as_str(), drink.size_label.as_deref()),
        (LATTE, Some("Regular"))
    );

    // Edit it: oat milk on the Regular latte, three of them.
    let lines = core
        .cart_replace_combo(
            None,
            regular.key.clone(),
            LUNCH.into(),
            lunch_picks("Regular", true),
            3,
            Some("no ice".into()),
        )
        .unwrap();
    assert_eq!(lines.len(), 2);
    assert!(
        lines.iter().all(|l| l.key != regular.key),
        "the edited line has a new key"
    );
    let edited = lines.iter().find(|l| l.key != large).unwrap().clone();
    assert_eq!((edited.qty, edited.notes.as_deref()), (3, Some("no ice")));
    assert_eq!(edited.line_total_minor, 3 * 16500);
    assert_eq!(
        edited
            .parts
            .iter()
            .map(|p| p.share_minor)
            .collect::<Vec<_>>(),
        vec![8571, 2858, 3571]
    );

    // Editing it into the other line's picks merges the two.
    let lines = core
        .cart_replace_combo(
            None,
            edited.key.clone(),
            LUNCH.into(),
            lunch_picks("Large", true),
            1,
            None,
        )
        .unwrap();
    assert_eq!(lines.len(), 1);
    assert_eq!(lines[0].qty, 3);

    // Quantity and removal.
    let lines = core.cart_set_qty(None, large.clone(), 4).unwrap();
    assert_eq!(lines[0].line_total_minor, 4 * 17500);
    core.cart_add(None, COOKIE.into(), "Cookie".into(), 4000)
        .unwrap();
    // The subtotal is Σ the parts' totals and add-ons, plus the plain line.
    let lines = core.cart_lines(None).unwrap();
    let combo_total: i64 = part_totals(&combo_line(&lines)).iter().sum();
    assert_eq!(combo_total, 4 * 17500);
    assert_eq!(
        core.cart_totals(None).unwrap().subtotal_minor,
        combo_total + 4000
    );
    let lines = core.cart_remove(None, large).unwrap();
    assert_eq!(lines.len(), 1);
    assert_eq!(lines[0].item_id, COOKIE);
}

#[tokio::test]
async fn picks_the_slots_refuse_are_refused_in_the_tellers_words() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    // A slot short: the sheet shows the figures so far and why it can't add.
    let short = vec![
        pick(S_MAIN, BURGER, None, &[]),
        pick(S_SIDE, FRIES, None, &[]),
    ];
    let q = core
        .combo_quote(None, LUNCH.into(), short.clone(), 1)
        .unwrap();
    assert!(!q.complete);
    assert_eq!(q.refusal.as_deref(), Some("COMBO_SLOT_TOO_FEW"));
    assert_eq!(
        q.refusal_text.as_deref(),
        Some("Choose at least 1 for Drink.")
    );
    let err = core
        .cart_add_combo(None, LUNCH.into(), short, 1, None)
        .unwrap_err();
    assert!(
        matches!(&err, crate::CoreError::Validation { field, detail } if field.is_empty() && detail == "Choose at least 1 for Drink."),
        "{err:?}"
    );

    // An item the slot does not admit.
    let mut wrong = lunch_picks("Regular", false);
    wrong[2].item_id = COOKIE.into();
    let err = core
        .cart_add_combo(None, LUNCH.into(), wrong, 1, None)
        .unwrap_err();
    assert!(
        format!("{err:?}").contains(&en("combo.choice_not_allowed")),
        "{err:?}"
    );
    // A combo is never a pick (nor a plain item added as a combo).
    let mut nested = lunch_picks("Regular", false);
    nested[0].item_id = LUNCH.into();
    assert!(core
        .cart_add_combo(None, LUNCH.into(), nested, 1, None)
        .is_err());
    assert!(core
        .cart_add_combo(None, LATTE.into(), lunch_picks("Regular", false), 1, None)
        .is_err());
    assert!(
        core.cart_lines(None).unwrap().is_empty(),
        "nothing was added"
    );
}

#[tokio::test]
async fn the_combo_sheet_is_drawn_from_the_mirror() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    let d = core.combo_detail(LUNCH.into()).expect("a combo");
    assert_eq!(
        (
            d.price_minor,
            d.is_fixed,
            d.available_now,
            d.why_unavailable.as_deref()
        ),
        (15000, true, true, None)
    );
    assert_eq!(
        d.slots
            .iter()
            .map(|s| s.rule_label.as_str())
            .collect::<Vec<_>>(),
        vec!["Choose 1 item"; 3]
    );
    let drink = &d.slots[2].choices[0];
    assert_eq!(
        (
            drink.base_price_minor,
            drink.included_size_label.as_deref(),
            drink.is_default
        ),
        (5000, Some("Regular"), true)
    );
    let sizes: Vec<(&str, i64, i64, bool)> = drink
        .sizes
        .iter()
        .map(|s| {
            (
                s.label.as_str(),
                s.price_minor,
                s.extra_minor,
                s.is_included,
            )
        })
        .collect();
    assert_eq!(
        sizes,
        vec![
            ("Small", 4500, 0, false),
            ("Regular", 5000, 0, true),
            ("Large", 6000, 1000, false)
        ]
    );
    assert!(
        core.combo_detail(LATTE.into()).is_none(),
        "an item is not a combo"
    );
    let draft = core.combo_new_draft(LUNCH.into()).unwrap();
    assert_eq!(
        draft
            .picks
            .iter()
            .map(|p| (
                p.slot_id.as_str(),
                p.item_id.as_str(),
                p.size_label.as_deref()
            ))
            .collect::<Vec<_>>(),
        vec![
            (S_MAIN, BURGER, None),
            (S_SIDE, FRIES, None),
            (S_DRINK, LATTE, Some("Regular"))
        ]
    );
    // The grid shows the combo (with its kind) beside the items.
    let grid = core.list_menu_items().unwrap();
    assert_eq!(
        grid.iter().find(|i| i.id == LUNCH).map(|i| i.kind.as_str()),
        Some("combo")
    );
}

/// Every combo / meal / deal refusal is one whole sentence in the till's
/// language, with no field name for the host to put in front of it.
#[tokio::test]
async fn the_refusals_are_whole_sentences_in_the_tills_language() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed_with(&core, |row| row["combo"]["sell"]["pos"] = json!(false));
    core.set_locale("ar".into());
    core.invalidate_catalog_cache();
    let said = |r: Result<Vec<cart::CartLineView>, crate::CoreError>| match r {
        Err(crate::CoreError::Validation { field, detail }) => {
            assert_eq!(field, "", "{detail}");
            detail
        }
        other => panic!("{other:?}"),
    };
    // Off on the till.
    let off = said(core.cart_add_combo(None, LUNCH.into(), lunch_picks("Regular", false), 1, None));
    assert_eq!(off, i18n::tr("ar", "combo.channel_off"));
    // Not a combo on this menu.
    let unknown =
        said(core.cart_add_combo(None, LATTE.into(), lunch_picks("Regular", false), 1, None));
    assert_eq!(unknown, "هذا الكومبو غير متاح الآن.");
    // A slot short.
    seed(&core);
    core.set_locale("ar".into());
    core.invalidate_catalog_cache();
    let short = said(core.cart_add_combo(
        None,
        LUNCH.into(),
        lunch_picks("Regular", false)[..2].to_vec(),
        1,
        None,
    ));
    assert_eq!(
        short,
        i18n::tr("ar", "combo.slot_too_few")
            .replace("{min}", "1")
            .replace("{slot}", "Drink")
    );
    // No meal for this item.
    match core.item_meal_draft(BURGER.into(), None, vec![], vec![], 1, None) {
        Err(crate::CoreError::Validation { field, detail }) => {
            assert_eq!(
                (field.as_str(), detail.as_str()),
                ("", "لا توجد خانة لهذا الصنف في الكومبو.")
            )
        }
        other => panic!("{other:?}"),
    }
    // A deal the cart does not qualify for.
    let not = said(core.cart_apply_deal(None, DEAL_BITES.into()));
    assert_eq!(not, "هذا العرض لم يعد ينطبق على السلة.");
    // The slot rule on the sheet, in Arabic's forms.
    let d = core.combo_detail(LUNCH.into()).unwrap();
    assert_eq!(d.slots[0].rule_label, "اختر صنفًا واحدًا");
}

const CLUB: &str = "00000000-0000-0000-0000-00000000b006";
const S_BREAD: &str = "00000000-0000-0000-0000-00000000c0b1";
const WHITE: &str = "00000000-0000-0000-0000-00000000d002";
const BROWN: &str = "00000000-0000-0000-0000-00000000d003";

/// The menu, with a Club sandwich the Main slot also admits: its Bread is
/// required and has no default (White or Brown, nothing preselected).
fn seed_club(core: &MadarCore) {
    seed_with(core, |row| {
        row["combo"]["slots"][0]["choices"]
            .as_array_mut()
            .unwrap()
            .push(json!({ "menu_item_id": CLUB }));
    });
    let mut club = item(CLUB, "Club sandwich", 11000, &[], CAT_MAINS);
    club["addon_slots"] = json!([{
        "id": S_BREAD, "label": "Bread", "label_translations": { "ar": "الخبز" },
        "addon_type": "bread", "is_required": true, "min_selections": 1, "max_selections": 1,
    }]);
    let mut items: Vec<Value> =
        serde_json::from_str(&core.store.kv_get(menu::K_MENU_ITEMS).unwrap().unwrap()).unwrap();
    items.push(club);
    core.store
        .kv_put(menu::K_MENU_ITEMS, &Value::from(items).to_string())
        .unwrap();
    core.store
        .kv_put(
            menu::K_ADDONS,
            &json!([
                addon(OAT, "Oat milk", "extra", 1500),
                addon(WHITE, "White", "bread", 0),
                addon(BROWN, "Brown", "bread", 0),
            ])
            .to_string(),
        )
        .unwrap();
    core.invalidate_catalog_cache();
}

/// A pick whose item has a required choice with no default (a sandwich's
/// bread) keeps the combo out of the cart until the choice is made: the
/// sheet knows to open Customise on it, the quote says what is missing and
/// where, and the cart refuses it — added, edited or made a meal — with a
/// coded refusal in the till's language.
#[tokio::test]
async fn a_pick_with_a_required_choice_and_no_default_is_refused_until_made() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed_club(&core);

    // Picking the club opens Customise at once; the burger (nothing to
    // choose) and the latte (its choices are optional) never do.
    let d = core.combo_detail(LUNCH.into()).unwrap();
    let must = |slot: usize, id: &str| {
        d.slots[slot]
            .choices
            .iter()
            .find(|c| c.item_id == id)
            .map(|c| c.must_customise)
            .expect("the choice")
    };
    assert!(must(0, CLUB));
    assert!(!must(0, BURGER));
    assert!(!must(2, LATTE));

    let mut no_bread = lunch_picks("Regular", false);
    no_bread[0] = pick(S_MAIN, CLUB, None, &[]);
    let q = core
        .combo_quote(None, LUNCH.into(), no_bread.clone(), 1)
        .unwrap();
    assert!(!q.complete);
    assert_eq!(
        q.refusal.as_deref(),
        Some(combos::COMBO_PICK_CHOICE_REQUIRED)
    );
    assert_eq!(
        q.refusal_text.as_deref(),
        Some("Choose Bread for Club sandwich.")
    );
    assert_eq!(
        q.pick_needs,
        vec![combos::ComboPickNeed {
            slot_id: S_MAIN.into(),
            item_id: CLUB.into(),
            group_name: "Bread".into(),
            text: "Choose Bread".into(),
        }]
    );
    // The figures so far still show.
    assert_eq!(q.unit_total_minor, 15000);

    // The cart refuses it, whole sentence, no field.
    let said = |r: Result<Vec<cart::CartLineView>, crate::CoreError>| match r {
        Err(crate::CoreError::Validation { field, detail }) if field.is_empty() => detail,
        other => panic!("expected a refusal, got {other:?}"),
    };
    assert_eq!(
        said(core.cart_add_combo(None, LUNCH.into(), no_bread.clone(), 1, None)),
        "Choose Bread for Club sandwich."
    );
    assert!(
        core.cart_lines(None).unwrap().is_empty(),
        "nothing was added"
    );

    // Bread chosen: complete, and it goes in.
    let mut with_bread = no_bread.clone();
    with_bread[0] = pick(S_MAIN, CLUB, None, &[BROWN]);
    let q = core
        .combo_quote(None, LUNCH.into(), with_bread.clone(), 1)
        .unwrap();
    assert!(q.complete, "{q:?}");
    assert!(q.pick_needs.is_empty());
    let lines = core
        .cart_add_combo(None, LUNCH.into(), with_bread, 1, None)
        .unwrap();
    let line = combo_line(&lines);
    assert_eq!(line.parts[0].item_id, CLUB);
    assert_eq!(line.parts[0].addons[0].addon_item_id, BROWN);

    // Editing the line (or making a meal onto it) can't drop the bread.
    assert_eq!(
        said(core.cart_replace_combo(
            None,
            line.key.clone(),
            LUNCH.into(),
            no_bread.clone(),
            1,
            None
        )),
        "Choose Bread for Club sandwich."
    );
    assert_eq!(
        combo_line(&core.cart_lines(None).unwrap()).parts[0].addons[0].addon_item_id,
        BROWN,
        "the line is as it was"
    );

    // In Arabic, the refusal and the slot's hint.
    core.set_locale("ar".into());
    core.invalidate_catalog_cache();
    let q = core
        .combo_quote(None, LUNCH.into(), no_bread.clone(), 1)
        .unwrap();
    assert_eq!(q.pick_needs[0].text, "اختر الخبز");
    assert_eq!(
        said(core.cart_add_combo(None, LUNCH.into(), no_bread, 1, None)),
        "اختر الخبز لصنف Club sandwich."
    );
    assert_eq!(
        i18n::tr("ar", "combo.pick_choice_required"),
        "اختر {group} لصنف {item}."
    );
}

// ── 3. make it a meal ───────────────────────────────────────────────────────

#[tokio::test]
async fn make_it_a_meal_offers_the_difference_and_turns_the_line_into_the_combo() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    // "+X": the combo with the latte (at the size it includes) and the
    // defaults elsewhere, 15000, minus the latte alone at that size, 5000.
    let offer = core.meal_offer(LATTE.into()).expect("the latte has a meal");
    assert_eq!(
        (
            offer.combo_id.as_str(),
            offer.slot_id.as_str(),
            offer.name.as_str()
        ),
        (LUNCH, S_DRINK, "Lunch deal")
    );
    assert_eq!(offer.delta_minor, 10000);
    assert!(
        core.meal_offer(BURGER.into()).is_none(),
        "no meal on the burger"
    );

    // A Large oat latte ×2 in the cart becomes two lunches.
    let lines = core
        .cart_add_configured(
            None,
            LATTE.into(),
            Some("Large".into()),
            vec![AddonSelection {
                addon_item_id: OAT.into(),
                qty: 1,
            }],
            vec![],
            2,
            None,
        )
        .unwrap();
    let key = line_of(&lines, LATTE).key;
    let draft = core.cart_make_it_a_meal(None, key.clone()).unwrap();
    assert_eq!(
        (
            draft.combo_id.as_str(),
            draft.qty,
            draft.line_key.as_deref()
        ),
        (LUNCH, 2, Some(key.as_str()))
    );
    let drink = draft
        .picks
        .iter()
        .find(|p| p.slot_id == S_DRINK)
        .expect("the latte in its slot");
    assert_eq!(
        (drink.item_id.as_str(), drink.size_label.as_deref()),
        (LATTE, Some("Large"))
    );
    assert_eq!(
        drink.addons,
        vec![AddonSelection {
            addon_item_id: OAT.into(),
            qty: 1
        }]
    );
    let mut others: Vec<(&str, &str)> = draft
        .picks
        .iter()
        .filter(|p| p.slot_id != S_DRINK)
        .map(|p| (p.slot_id.as_str(), p.item_id.as_str()))
        .collect();
    others.sort();
    assert_eq!(
        others,
        vec![(S_MAIN, BURGER), (S_SIDE, FRIES)],
        "the defaults elsewhere"
    );

    let lines = core
        .cart_replace_combo(
            None,
            key,
            draft.combo_id.clone(),
            draft.picks.clone(),
            draft.qty,
            draft.notes.clone(),
        )
        .unwrap();
    assert_eq!(lines.len(), 1, "the latte line became the combo");
    let l = combo_line(&lines);
    assert_eq!((l.qty, l.line_total_minor), (2, 35000));
    assert_eq!(part_totals(&l), vec![17142, 5716, 9142 + 3000]);

    // The item sheet's own "make it a meal", before the item is in the cart.
    let d = core
        .item_meal_draft(LATTE.into(), Some("Small".into()), vec![], vec![], 1, None)
        .unwrap();
    assert_eq!(d.line_key, None);
    // An item with no meal is refused in words.
    let err = core
        .item_meal_draft(BURGER.into(), None, vec![], vec![], 1, None)
        .unwrap_err();
    assert!(
        format!("{err:?}").contains(&en("meal.target_invalid")),
        "{err:?}"
    );
}

// ── 4. availability ─────────────────────────────────────────────────────────

fn hidden(core: &MadarCore) -> bool {
    !core
        .list_menu_items()
        .unwrap()
        .iter()
        .any(|i| i.id == LUNCH)
}

fn refusal(core: &MadarCore) -> String {
    match core.cart_add_combo(None, LUNCH.into(), lunch_picks("Regular", false), 1, None) {
        // The whole sentence is the detail; no field name to prefix it.
        Err(crate::CoreError::Validation { field, detail }) if field.is_empty() => detail,
        other => panic!("expected a refusal, got {other:?}"),
    }
}

#[tokio::test]
async fn a_combo_off_on_the_till_is_hidden_and_refused() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    // The POS switch off at this branch (org-wide, resolved onto the row).
    seed_with(&core, |row| row["combo"]["sell"]["pos"] = json!(false));
    assert!(hidden(&core));
    assert_eq!(refusal(&core), en("combo.channel_off"));
    let d = core.combo_detail(LUNCH.into()).unwrap();
    assert!(!d.available_now);
    assert_eq!(
        d.why_unavailable.as_deref(),
        Some(en("combo.channel_off").as_str())
    );
    assert!(
        core.meal_offer(LATTE.into()).is_none(),
        "no meal while the combo is off"
    );

    // Another channel off does not matter to the till.
    seed_with(&core, |row| row["combo"]["sell"]["qr"] = json!(false));
    assert!(!hidden(&core));

    // Switched off (inactive) at the branch.
    seed_with(&core, |row| row["is_active"] = json!(false));
    assert!(hidden(&core));
    assert_eq!(refusal(&core), en("combo.unavailable"));

    // A required slot with nothing left to pick.
    seed(&core);
    let mut rows: Vec<Value> =
        serde_json::from_str(&core.store.kv_get(menu::K_MENU_ITEMS).unwrap().unwrap()).unwrap();
    rows.iter_mut().find(|r| r["id"] == LATTE).unwrap()["is_active"] = json!(false);
    core.store
        .kv_put(menu::K_MENU_ITEMS, &Value::Array(rows).to_string())
        .unwrap();
    core.invalidate_catalog_cache();
    assert!(hidden(&core));
    assert_eq!(refusal(&core), en("combo.unavailable"));
}

#[tokio::test]
async fn a_combo_outside_its_window_is_hidden_on_the_branchs_clock() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    let windows = |w: Value| move |row: &mut Value| row["combo"]["windows"] = w;
    // Weekdays (Mon–Fri = 62), 12:00–16:00, every branch.
    seed_with(
        &core,
        windows(json!([{ "weekdays": 62, "starts_at": "12:00", "ends_at": "16:00" }])),
    );
    clock_at(&core, "Africa/Cairo", "2026-10-01", "13:00"); // a Thursday
    assert!(!hidden(&core));
    core.cart_add_combo(None, LUNCH.into(), lunch_picks("Regular", false), 1, None)
        .unwrap();
    clock_at(&core, "Africa/Cairo", "2026-10-01", "16:00"); // the end is open
    assert!(hidden(&core));
    assert_eq!(refusal(&core), en("combo.unavailable"));
    clock_at(&core, "Africa/Cairo", "2026-10-03", "13:00"); // a Saturday
    assert!(hidden(&core));

    // Judged in the BRANCH's zone: 13:00 in Cairo is 19:00 in Tokyo.
    clock_at(&core, "Africa/Cairo", "2026-10-01", "13:00");
    core.store
        .kv_put(checkout::KEY_BRANCH_TZ, "Asia/Tokyo")
        .unwrap();
    assert!(hidden(&core), "the Tokyo branch's lunch window is over");
    core.store
        .kv_put(checkout::KEY_BRANCH_TZ, "Africa/Cairo")
        .unwrap();

    // A date range (Ramadan menus): valid_from / valid_to, inclusive.
    seed_with(
        &core,
        windows(json!([{ "valid_from": "2026-10-02", "valid_to": "2026-10-05" }])),
    );
    assert!(hidden(&core), "not yet");
    clock_at(&core, "Africa/Cairo", "2026-10-05", "23:59");
    assert!(!hidden(&core), "the last day counts");
    clock_at(&core, "Africa/Cairo", "2026-10-06", "00:00");
    assert!(hidden(&core), "over");

    // Past midnight: a Thursday-only 22:00–02:00 window still covers 01:00
    // on Friday (the day it started), and not 01:00 on Thursday.
    seed_with(
        &core,
        windows(json!([{ "weekdays": 16, "starts_at": "22:00", "ends_at": "02:00" }])),
    );
    clock_at(&core, "Africa/Cairo", "2026-10-02", "01:00");
    assert!(!hidden(&core));
    clock_at(&core, "Africa/Cairo", "2026-10-01", "01:00");
    assert!(hidden(&core));
    clock_at(&core, "Africa/Cairo", "2026-10-01", "23:00");
    assert!(!hidden(&core));

    // A window for another branch does not apply here; one for this branch does.
    seed_with(
        &core,
        windows(json!([{ "branch_id": OTHER_BRANCH, "starts_at": "06:00", "ends_at": "07:00" }])),
    );
    assert!(
        !hidden(&core),
        "no window applies to this branch: always on sale"
    );
    seed_with(
        &core,
        windows(
            json!([{ "branch_id": testkit::BRANCH, "starts_at": "06:00", "ends_at": "07:00" }]),
        ),
    );
    assert!(hidden(&core));
}

// ── 5. deals ────────────────────────────────────────────────────────────────

fn two_croissants_and_a_cookie(core: &MadarCore) -> (String, String) {
    core.cart_add(None, CROISSANT.into(), "Croissant".into(), 5500)
        .unwrap();
    core.cart_add(None, CROISSANT.into(), "Croissant".into(), 5500)
        .unwrap();
    let lines = core
        .cart_add(None, COOKIE.into(), "Cookie".into(), 4000)
        .unwrap();
    (line_of(&lines, CROISSANT).key, line_of(&lines, COOKIE).key)
}

#[tokio::test]
async fn two_bites_is_suggested_applied_with_permission_and_dropped_when_broken() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    let (croissant, cookie) = two_croissants_and_a_cookie(&core);

    // §5 `deal/two_bites`: the {5500, 5500} chunk saves 2000.
    let s = core.cart_deal_suggestions(None);
    assert_eq!(s.len(), 1, "{s:?}");
    assert_eq!(
        (s[0].deal_id.as_str(), s[0].times, s[0].saving_minor),
        (DEAL_BITES, 1, 2000)
    );
    assert_eq!(s[0].line_keys, vec![croissant.clone()]);
    assert_eq!(s[0].times_label, "Applies once");
    assert!(
        core.cart_lines(None)
            .unwrap()
            .iter()
            .all(|l| l.deal_cut_minor == 0),
        "never applied by itself (C8)"
    );

    // Applying needs orders.deals.apply.
    grant(&core, false);
    assert!(!core.can_apply_deals());
    match core.cart_apply_deal(None, DEAL_BITES.into()) {
        Err(crate::CoreError::Forbidden { action, .. }) => {
            assert_eq!(action, en("deal.not_allowed"))
        }
        other => panic!("{other:?}"),
    }
    grant(&core, true);
    assert!(core.can_apply_deals());
    let lines = core.cart_apply_deal(None, DEAL_BITES.into()).unwrap();
    let c = line_of(&lines, CROISSANT);
    assert_eq!(
        (c.deal_cut_minor, c.deal_name.as_deref()),
        (2000, Some("Any 2 bites for 90"))
    );
    assert_eq!(
        c.line_total_minor, 11000,
        "the line shows its normal price; the cut is its own figure"
    );
    assert_eq!(line_of(&lines, COOKIE).deal_cut_minor, 0);
    assert_eq!(
        core.cart_totals(None).unwrap().subtotal_minor,
        9000 + 4000,
        "the croissants now ring at 9000"
    );
    let applied = core.cart_applied_deals(None);
    assert_eq!(applied.len(), 1);
    assert_eq!(
        (applied[0].discount_minor, applied[0].line_keys.clone()),
        (2000, vec![croissant.clone()])
    );
    // Its units are consumed: the cookie alone qualifies for nothing.
    assert!(core.cart_deal_suggestions(None).is_empty());
    assert!(
        core.take_deal_notices(None).is_empty(),
        "nothing to say while it stands"
    );

    // One more cookie changes nothing it claimed.
    core.cart_set_qty(None, cookie.clone(), 2).unwrap();
    assert_eq!(core.cart_applied_deals(None).len(), 1);

    // One croissant fewer breaks it: dropped, and the host is told once.
    let lines = core.cart_set_qty(None, croissant.clone(), 1).unwrap();
    assert!(lines.iter().all(|l| l.deal_cut_minor == 0));
    assert!(core.cart_applied_deals(None).is_empty());
    let said = core.take_deal_notices(None);
    assert_eq!(
        said,
        vec![en("deal.dropped").replace("{deal}", "Any 2 bites for 90")]
    );
    assert!(core.take_deal_notices(None).is_empty(), "said once");
    assert_eq!(core.cart_totals(None).unwrap().subtotal_minor, 5500 + 8000);

    // Removing a line in a deal drops it too.
    core.cart_set_qty(None, croissant.clone(), 2).unwrap();
    core.cart_apply_deal(None, DEAL_BITES.into()).unwrap();
    core.cart_remove(None, croissant).unwrap();
    assert!(core.cart_applied_deals(None).is_empty());
    assert_eq!(core.take_deal_notices(None).len(), 1);

    // A deal the cart no longer qualifies for is refused in words.
    let err = core.cart_apply_deal(None, DEAL_BITES.into()).unwrap_err();
    assert!(
        format!("{err:?}").contains(&en("deal.not_eligible")),
        "{err:?}"
    );
}

/// The `deal_rule` feed rows become the till's deal mirror once the server
/// sends the type; the suggestions read them from there.
#[tokio::test]
async fn deal_rule_feed_rows_project_into_the_deal_mirror() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    set_deals(&core, json!([]));
    core.store
        .with_conn(|c| {
            for d in deal_rows().as_array().unwrap() {
                let mut row = d.clone();
                row["seq"] = json!(4);
                c.execute(
                    "INSERT OR REPLACE INTO sync_rows(type,id,branch_id,seq,data) VALUES('deal_rule',?1,?2,4,?3)",
                    rusqlite::params![d["id"].as_str().unwrap(), testkit::BRANCH, row.to_string()],
                )?;
            }
            Ok(())
        })
        .unwrap();
    let kv = |k: &str, v: &str| {
        core.store
            .kv_put(&format!("{k}{}", testkit::BRANCH), v)
            .unwrap()
    };
    kv(crate::sync_pull::K_LAST_FULL, "2026-09-25T08:00:00Z");
    kv(crate::sync_pull::K_TYPES, r#"["deal_rule"]"#);
    core.project_pull_mirrors(testkit::BRANCH);
    let mirrored: Vec<Value> =
        serde_json::from_str(&core.store.kv_get(menu::K_DEALS).unwrap().unwrap()).unwrap();
    assert_eq!(mirrored.len(), 2);
    assert!(
        mirrored.iter().all(|d| d.get("seq").is_none()),
        "the feed's own fields stay behind"
    );
    two_croissants_and_a_cookie(&core);
    assert_eq!(
        core.cart_deal_suggestions(None)
            .first()
            .map(|s| s.deal_id.as_str()),
        Some(DEAL_BITES)
    );
}

/// A parked cart keeps its combo lines and its applied deals, and comes
/// back priced the same.
#[tokio::test]
async fn a_parked_cart_keeps_its_combos_and_its_deals() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    core.cart_add_combo(None, LUNCH.into(), lunch_picks("Large", true), 2, None)
        .unwrap();
    two_croissants_and_a_cookie(&core);
    core.cart_apply_deal(None, DEAL_BITES.into()).unwrap();
    let before = core.cart_lines(None).unwrap();
    let totals = core.cart_totals(None).unwrap();
    let payload = cart::cart_payload(&core.store, None).unwrap();
    core.cart_clear(None).unwrap();
    crate::deals::clear(&core.store, None).unwrap();
    assert!(core.cart_lines(None).unwrap().is_empty());
    cart::set_cart_payload(&core.store, None, &payload).unwrap();
    assert!(
        core.take_deal_notices(None).is_empty(),
        "the deal still stands"
    );
    assert_eq!(core.cart_lines(None).unwrap(), before);
    assert_eq!(core.cart_totals(None).unwrap(), totals);
    assert_eq!(core.cart_applied_deals(None).len(), 1);
}

#[tokio::test]
async fn buy_two_lattes_get_one_splits_the_free_one_by_price() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    let add = |size: &str, qty: i64| {
        core.cart_add_configured(
            None,
            LATTE.into(),
            Some(size.into()),
            vec![],
            vec![],
            qty,
            None,
        )
        .unwrap()
    };
    add("Large", 1);
    add("Regular", 2);
    let lines = add("Small", 1);
    let key = |size: &str| {
        lines
            .iter()
            .find(|l| l.size_label.as_deref() == Some(size))
            .unwrap()
            .key
            .clone()
    };
    let s = core.cart_deal_suggestions(None);
    assert_eq!(s.len(), 1);
    assert_eq!(
        (s[0].deal_id.as_str(), s[0].saving_minor),
        (DEAL_B2G1, 5000)
    );
    let lines = core.cart_apply_deal(None, DEAL_B2G1.into()).unwrap();
    let cut = |size: &str| {
        lines
            .iter()
            .find(|l| l.key == key(size))
            .unwrap()
            .deal_cut_minor
    };
    // §5 `deal/b2g1`: 5000 over 6000/5000/5000 = 1875 / 1563 / 1562.
    assert_eq!(
        (cut("Large"), cut("Regular"), cut("Small")),
        (1875, 1563 + 1562, 0)
    );
    assert_eq!(
        core.cart_totals(None).unwrap().subtotal_minor,
        6000 + 10000 + 4500 - 5000
    );
}

#[tokio::test]
async fn applying_one_deal_consumes_its_units_and_the_suggestions_rerun() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    let mut rows = deal_rows();
    rows.as_array_mut().unwrap().push(json!({
        "id": DEAL_HALF, "name": "Second bite half off", "kind": "buy_get", "qty": 1, "get_qty": 1,
        "get_percent": 50, "sort": 1, "is_active": true, "pool": [{ "category_id": CAT_BITES }] }));
    set_deals(&core, rows);
    two_croissants_and_a_cookie(&core);
    // Best first: half off saves 2750 on the croissants, two bites 2000.
    let s = core.cart_deal_suggestions(None);
    assert_eq!(
        s.iter()
            .map(|x| (x.deal_id.as_str(), x.saving_minor))
            .collect::<Vec<_>>(),
        vec![(DEAL_HALF, 2750), (DEAL_BITES, 2000)]
    );
    core.cart_apply_deal(None, DEAL_HALF.into()).unwrap();
    // The croissants are taken; the cookie alone is no chunk for either.
    assert!(core.cart_deal_suggestions(None).is_empty());
    // Two more cookies make a chunk again: half off saves 2000 on two of
    // them (two bites would cost more than the cookies do).
    let lines = core.cart_lines(None).unwrap();
    core.cart_set_qty(None, line_of(&lines, COOKIE).key, 3)
        .unwrap();
    let s = core.cart_deal_suggestions(None);
    assert_eq!(
        s.iter()
            .map(|x| (x.deal_id.as_str(), x.times, x.saving_minor))
            .collect::<Vec<_>>(),
        vec![(DEAL_HALF, 1, 2000)]
    );
    assert!(
        s.iter()
            .all(|x| x.line_keys == vec![line_of(&core.cart_lines(None).unwrap(), COOKIE).key]),
        "only the cookies are free"
    );
    // Taking the applied deal off frees the croissants again.
    let app = core.cart_applied_deals(None).remove(0);
    let lines = core.cart_remove_deal(None, app.id).unwrap();
    assert!(lines.iter().all(|l| l.deal_cut_minor == 0));
}

#[tokio::test]
async fn a_combo_never_enters_a_deal_and_a_deal_rides_the_counter_only() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    // A lunch holds a latte, and two lattes sit beside it: buy-2-get-1 needs 3.
    core.cart_add_combo(None, LUNCH.into(), lunch_picks("Regular", false), 1, None)
        .unwrap();
    core.cart_add_configured(
        None,
        LATTE.into(),
        Some("Regular".into()),
        vec![],
        vec![],
        2,
        None,
    )
    .unwrap();
    assert!(
        core.cart_deal_suggestions(None).is_empty(),
        "the combo's latte is not a deal unit"
    );
    core.cart_add_configured(
        None,
        LATTE.into(),
        Some("Regular".into()),
        vec![],
        vec![],
        1,
        None,
    )
    .unwrap();
    let lines = core.cart_apply_deal(None, DEAL_B2G1.into()).unwrap();
    assert_eq!(combo_line(&lines).deal_cut_minor, 0);
    assert_eq!(combo_line(&lines).line_total_minor, 15000);

    // A table's cart becomes a ticket's round: no deal there.
    let table = Some("00000000-0000-0000-0000-00000000aa04".to_string());
    core.cart_add(table.clone(), CROISSANT.into(), "Croissant".into(), 5500)
        .unwrap();
    core.cart_add(table.clone(), CROISSANT.into(), "Croissant".into(), 5500)
        .unwrap();
    assert!(core.cart_deal_suggestions(table.clone()).is_empty());
    assert!(core.cart_apply_deal(table, DEAL_BITES.into()).is_err());

    // The POS switch off: no deal is suggested on the till (§11).
    let mut rows = deal_rows();
    for r in rows.as_array_mut().unwrap() {
        r["sell"] = json!({ "pos": false, "qr": true, "online": true, "delivery": true });
    }
    set_deals(&core, rows);
    core.cart_clear(None).unwrap();
    two_croissants_and_a_cookie(&core);
    assert!(core.cart_deal_suggestions(None).is_empty());
}

#[tokio::test]
async fn a_deal_outside_its_window_is_not_suggested_on_the_branchs_clock() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    let mut rows = deal_rows();
    rows[0]["windows"] = json!([{ "weekdays": 62, "starts_at": "12:00", "ends_at": "16:00" }]);
    set_deals(&core, rows);
    two_croissants_and_a_cookie(&core);
    clock_at(&core, "Africa/Cairo", "2026-10-01", "13:00");
    assert_eq!(core.cart_deal_suggestions(None).len(), 1);
    core.cart_apply_deal(None, DEAL_BITES.into()).unwrap();
    // The window closes: the applied deal comes off at the next cart read.
    clock_at(&core, "Africa/Cairo", "2026-10-01", "17:00");
    assert!(core.cart_deal_suggestions(None).is_empty());
    assert_eq!(core.take_deal_notices(None).len(), 1);
    assert!(core
        .cart_lines(None)
        .unwrap()
        .iter()
        .all(|l| l.deal_cut_minor == 0));
}

// ── 6 + 7. the order on the wire, the receipt, the kitchen ──────────────────

/// A lunch ×2 (Large oat latte), two croissants and a cookie with two bites
/// applied, rung and queued. Returns the receipt and the queued request.
async fn ring_the_sale(core: &MadarCore) -> (checkout::ReceiptView, Value) {
    seed(core);
    core.cart_add_combo(None, LUNCH.into(), lunch_picks("Large", true), 2, None)
        .unwrap();
    two_croissants_and_a_cookie(core);
    core.cart_apply_deal(None, DEAL_BITES.into()).unwrap();
    core.open_till(0, None).await.unwrap();
    let receipt = core.checkout(None, pay(100_000)).await.unwrap();
    let op = core
        .store
        .pending()
        .unwrap()
        .into_iter()
        .find(|i| i.op_type == "create_order")
        .expect("a queued sale");
    let (env, _) = core.replay_envelope(&op).map_err(|_| "envelope").unwrap();
    (receipt, env["request"].clone())
}

fn assert_the_wire(req: &Value) {
    let items = req["items"].as_array().unwrap();
    assert_eq!(items.len(), 3, "one combo line, two plain lines: {req}");
    let c = &items[0];
    assert_eq!(
        (
            c["menu_item_id"].as_str(),
            c["quantity"].as_i64(),
            c["unit_price"].as_i64()
        ),
        (Some(LUNCH), Some(2), Some(15000))
    );
    let picks = c["combo"]["picks"].as_array().unwrap();
    let got: Vec<(&str, &str, i64, i64, i64)> = picks
        .iter()
        .map(|p| {
            (
                p["slot_id"].as_str().unwrap(),
                p["menu_item_id"].as_str().unwrap(),
                p["quantity"].as_i64().unwrap(),
                p["share"].as_i64().unwrap(),
                p["surcharge"].as_i64().unwrap(),
            )
        })
        .collect();
    // Per combo unit, as the till charged (§3.1).
    assert_eq!(
        got,
        vec![
            (S_MAIN, BURGER, 1, 8571, 0),
            (S_SIDE, FRIES, 1, 2858, 0),
            (S_DRINK, LATTE, 1, 3571, 1000)
        ]
    );
    assert_eq!(picks[2]["size_label"], "Large", "the size is explicit");
    assert_eq!(
        picks[2]["addons"],
        json!([{ "addon_item_id": OAT, "quantity": 1, "unit_price": 1500 }])
    );
    assert!(
        c.get("addons")
            .is_none_or(|a| a.as_array().is_none_or(Vec::is_empty)),
        "the header carries no add-ons"
    );
    assert_eq!(
        (
            items[1]["menu_item_id"].as_str(),
            items[1]["quantity"].as_i64(),
            items[1]["unit_price"].as_i64()
        ),
        (Some(CROISSANT), Some(2), Some(5500))
    );
    let deals = req["deals"].as_array().expect("the order's deals");
    assert_eq!(deals.len(), 1);
    assert_eq!(deals[0]["deal_rule_id"], DEAL_BITES);
    assert_eq!(deals[0]["times"], 1);
    assert_eq!(deals[0]["lines"], json!([{ "line_index": 1, "units": 2 }]));
    assert_eq!(deals[0]["discount"], 2000);
    assert_eq!(req["subtotal"], 35000 + 11000 + 4000 - 2000);
}

#[tokio::test]
async fn the_queued_order_carries_the_combo_and_the_deal_as_charged() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    let (receipt, req) = ring_the_sale(&core).await;
    assert_the_wire(&req);

    // The receipt the till printed (C12): the header `2× Lunch deal … 300`,
    // its parts for the whole line, the deal under the subtotal.
    assert_eq!(receipt.subtotal_minor, 48000);
    assert_eq!(receipt.gross_subtotal_minor(), 50000);
    assert_eq!(
        receipt.deals,
        vec![checkout::ReceiptDealView {
            name: "Any 2 bites for 90".into(),
            discount_minor: 2000
        }]
    );
    let l = &receipt.lines[0];
    assert_eq!(
        (
            l.kind.as_str(),
            l.qty,
            l.unit_price_minor,
            l.line_total_minor
        ),
        ("combo", 2, 15000, 35000)
    );
    let parts: Vec<(&str, i64, Option<&str>, Option<&str>, i64)> = l
        .parts
        .iter()
        .map(|p| {
            (
                p.name.as_str(),
                p.qty,
                p.size_label.as_deref(),
                p.slot_name.as_deref(),
                p.surcharge_minor,
            )
        })
        .collect();
    assert_eq!(
        parts,
        vec![
            ("Burger", 2, None, Some("Main"), 0),
            ("Fries", 2, None, Some("Side"), 0),
            ("Latte", 2, Some("Large"), Some("Drink"), 2000)
        ]
    );
    assert_eq!(
        l.parts[2].addons,
        vec![checkout::ReceiptModifierView {
            name: "Oat milk".into(),
            price_minor: 3000
        }]
    );
    let c = &receipt.lines[1];
    assert_eq!((c.line_total_minor, c.deal_minor), (11000, 2000));

    let text: Vec<String> = receipt::layout(&receipt, &escpos_ctx(&core))
        .into_iter()
        .map(|l| l.text)
        .collect();
    let at = |needle: &str| {
        text.iter()
            .position(|t| t.contains(needle))
            .unwrap_or_else(|| panic!("{needle} in {text:#?}"))
    };
    let head = at("2x Lunch deal");
    assert!(text[head].trim_end().ends_with("300.00"), "{}", text[head]);
    assert!(
        text[head + 1].starts_with("  2x Burger"),
        "{}",
        text[head + 1]
    );
    assert!(text[head + 2].starts_with("  2x Fries"));
    assert!(
        text[head + 3].starts_with("  2x Latte (Large)")
            && text[head + 3].trim_end().ends_with("+20.00"),
        "{}",
        text[head + 3]
    );
    assert!(
        text[head + 4].starts_with("    + Oat milk")
            && text[head + 4].trim_end().ends_with("30.00"),
        "{}",
        text[head + 4]
    );
    let sub = at("Subtotal");
    assert!(
        text[sub].trim_end().ends_with("500.00"),
        "the lines at their normal prices: {}",
        text[sub]
    );
    assert!(
        text[sub + 1].starts_with("Any 2 bites for 90")
            && text[sub + 1].trim_end().ends_with("-20.00"),
        "{}",
        text[sub + 1]
    );
}

fn escpos_ctx(_core: &MadarCore) -> receipt::EscPosCtx {
    let l = |s: &str| s.to_string();
    receipt::EscPosCtx {
        store_name: l("MADAR CAFE"),
        currency: String::new(),
        width: 48,
        labels: receipt::ReceiptLabels {
            order: l("Order"),
            reference: l("Ref:"),
            voided: l("VOIDED"),
            delivery: l("DELIVERY"),
            channel_in_mall: l("In-Mall"),
            channel_outside: l("Outside"),
            customer: l("Customer"),
            phone: l("Phone"),
            address: l("Address:"),
            zone: l("Zone"),
            delivery_ref: l("Delivery Ref"),
            payment_hint: l("Payment (hint)"),
            notes: l("Notes:"),
            subtotal: l("Subtotal"),
            discount: l("Discount"),
            service_charge: l("Service"),
            tax: l("VAT (14%)"),
            vat_included: l("VAT (14%)"),
            prices_include_vat: l("Prices include VAT (14%)"),
            service_waived: l("Service charge removed"),
            delivery_fee: l("Delivery Fee"),
            total: l("Total"),
            tip: l("Tip"),
            cash: l("Cash"),
            change: l("Change"),
            payment: l("Payment"),
            teller: l("Teller"),
            served_by: l("Served by"),
            queued: l("Saved - will sync"),
            thank_you: l("Thank you!"),
            locale: l("en"),
            tz: chrono_tz::UTC,
        },
    }
}

/// What a server answers a replayed sale with: the combo header and its
/// parts (§3.2), the plain lines net of their deal cut, and the order's deals.
fn server_order(req: &Value) -> Value {
    let order_id = uuid::Uuid::new_v5(
        &uuid::Uuid::NAMESPACE_OID,
        req["idempotency_key"].to_string().as_bytes(),
    );
    let names = |id: &str| match id {
        x if x == LUNCH => "Lunch deal",
        x if x == BURGER => "Burger",
        x if x == FRIES => "Fries",
        x if x == LATTE => "Latte",
        x if x == CROISSANT => "Croissant",
        _ => "Cookie",
    };
    let row = |id: uuid::Uuid, menu: &str, unit: i64, qty: i64, total: i64| {
        json!({ "id": id, "order_id": order_id, "menu_item_id": menu, "item_name": names(menu), "name_translations": {},
                "unit_price": unit, "quantity": qty, "line_total": total, "addons": [], "optionals": [],
                "deductions_snapshot": [], "cost_missing": false, "line_kind": "item" })
    };
    let deals: Vec<Value> = req["deals"].as_array().cloned().unwrap_or_default();
    let mut items: Vec<Value> = Vec::new();
    let mut ids: Vec<uuid::Uuid> = Vec::new();
    for (li, it) in req["items"].as_array().unwrap().iter().enumerate() {
        let qty = it["quantity"].as_i64().unwrap();
        let menu = it["menu_item_id"].as_str().unwrap();
        let id = uuid::Uuid::new_v4();
        ids.push(id);
        if let Some(picks) = it["combo"]["picks"].as_array() {
            let mut h = row(id, menu, 0, qty, 0);
            h["line_kind"] = json!("combo");
            h["combo_unit_price"] = it["unit_price"].clone();
            h["combo_share"] = json!(0);
            h["combo_surcharge"] = json!(0);
            items.push(h);
            for p in picks {
                let pq = p["quantity"].as_i64().unwrap() * qty;
                let share = p["share"].as_i64().unwrap() * qty;
                let sur = p["surcharge"].as_i64().unwrap() * pq;
                let mut part = row(
                    uuid::Uuid::new_v4(),
                    p["menu_item_id"].as_str().unwrap(),
                    0,
                    pq,
                    share + sur,
                );
                part["line_kind"] = json!("combo_part");
                part["combo_line_id"] = json!(id);
                part["combo_slot_id"] = p["slot_id"].clone();
                part["combo_slot_name"] = json!(match p["slot_id"].as_str().unwrap() {
                    x if x == S_MAIN => "Main",
                    x if x == S_SIDE => "Side",
                    _ => "Drink",
                });
                part["combo_share"] = json!(share);
                part["combo_surcharge"] = json!(sur);
                // As the real server stores it: a single-size part says
                // "one_size" where a plain line says null.
                part["size_label"] = match &p["size_label"] {
                    Value::Null => json!("one_size"),
                    v => v.clone(),
                };
                part["addons"] = json!(p["addons"].as_array().cloned().unwrap_or_default().iter().map(|a| json!({
                    "id": uuid::Uuid::new_v4(), "order_item_id": uuid::Uuid::new_v4(), "addon_item_id": a["addon_item_id"],
                    "addon_name": "Oat milk", "unit_price": a["unit_price"], "quantity": a["quantity"],
                    "line_total": a["unit_price"].as_i64().unwrap() * a["quantity"].as_i64().unwrap() * pq,
                    "name_translations": {} })).collect::<Vec<_>>());
                items.push(part);
            }
            continue;
        }
        let unit = it["unit_price"].as_i64().unwrap();
        let cut: i64 = deals
            .iter()
            .filter(|d| {
                d["lines"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|l| l["line_index"] == li)
            })
            .map(|d| d["discount"].as_i64().unwrap())
            .sum();
        let mut r = row(id, menu, unit, qty, unit * qty - cut);
        r["deal_minor"] = json!(cut);
        items.push(r);
    }
    let deals: Vec<Value> = deals
        .iter()
        .map(|d| {
            json!({ "id": uuid::Uuid::new_v4(), "deal_rule_id": d["deal_rule_id"], "name": "Any 2 bites for 90",
                "name_translations": { "ar": "أي قطعتين بـ 90" }, "times": d["times"], "discount": d["discount"],
                "lines": d["lines"].as_array().unwrap().iter().map(|l| json!({
                    "order_item_id": ids[l["line_index"].as_u64().unwrap() as usize], "units": l["units"], "discount": d["discount"] })).collect::<Vec<_>>() })
        })
        .collect();
    let subtotal = req["subtotal"].as_i64().unwrap();
    let tax = req["tax_amount"].as_i64().unwrap_or(0);
    json!({
        "id": order_id, "branch_id": req["branch_id"], "till_id": req["till_id"], "shift_id": req["till_id"],
        "teller_id": testkit::TELLER, "teller_name": "Sara", "order_number": 7, "order_ref": req["order_ref"],
        "status": "completed", "order_type": "takeaway", "payment_method": req["payment_method"],
        "payment_legs": [], "subtotal": subtotal, "tax_amount": tax, "total_amount": subtotal + tax,
        "discount_amount": 0, "discount_value": 0, "delivery_fee": 0, "created_at": req["created_at"],
        "items": items, "deals": deals,
    })
}

async fn replaying_server() -> Stub {
    Stub::start(move |r| {
        if r.path.starts_with("/sync/replay") {
            let body = r.json();
            return Some(match body["op"].as_str().unwrap_or("") {
                "open_till" => StubResponse::json(201, json!({
                    "id": body["request"]["id"], "branch_id": testkit::BRANCH, "teller_id": testkit::TELLER,
                    "teller_name": "Sara", "status": "open", "opening_cash": body["request"]["opening_cash"],
                    "opened_at": body["request"]["opened_at"], "opening_cash_was_edited": false,
                    "verification": "unverified", "opened_while_another_open": false, "disagreement_count": 0})),
                "create_order" => StubResponse::json(201, server_order(&body["request"])),
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

#[tokio::test]
async fn the_drained_order_is_the_queued_one_and_the_reprint_rebuilds_the_combo() {
    let stub = replaying_server().await;
    let core = testkit::online_core(&stub.base, "").await;
    core.set_online(false);
    let (receipt, queued) = ring_the_sale(&core).await;
    core.set_online(true);
    core.push_and_refresh().await.ok();
    let sent: Vec<Value> = stub
        .requests("/sync/replay")
        .iter()
        .map(|r| r.json())
        .filter(|b| b["op"] == "create_order")
        .collect();
    assert_eq!(sent.len(), 1, "the sale went out once");
    let live = &sent[0]["request"];
    assert_the_wire(live);
    assert_eq!(live["items"], queued["items"], "the same lines as queued");
    assert_eq!(live["deals"], queued["deals"], "the same deals as queued");
    assert_eq!(core.store.dead_count().unwrap(), 0);

    // The reprint from the server's record: the header with its parts under
    // it (by `combo_line_id`), the deal row, the lines at their normal price.
    let again = core
        .order_receipt_view(receipt.local_order_id.clone())
        .await
        .unwrap();
    assert_eq!(again.lines.len(), 3, "{:#?}", again.lines);
    let l = &again.lines[0];
    assert_eq!(
        (
            l.kind.as_str(),
            l.qty,
            l.unit_price_minor,
            l.line_total_minor
        ),
        ("combo", 2, 15000, 35000)
    );
    assert_eq!(
        l.parts
            .iter()
            .map(|p| (
                p.name.as_str(),
                p.qty,
                p.surcharge_minor,
                p.slot_name.as_deref()
            ))
            .collect::<Vec<_>>(),
        vec![
            ("Burger", 2, 0, Some("Main")),
            ("Fries", 2, 0, Some("Side")),
            ("Latte", 2, 2000, Some("Drink"))
        ]
    );
    assert_eq!(l.parts[2].size_label.as_deref(), Some("Large"));
    // The server's "one_size" on a single-size part is no size: never on the
    // reprint's view, nor on its paper.
    assert_eq!((l.parts[0].size_label.as_deref(), l.parts[1].size_label.as_deref()), (None, None));
    let paper: Vec<String> = receipt::layout(&again, &escpos_ctx(&core)).into_iter().map(|l| l.text).collect();
    assert!(!paper.iter().any(|t| t.contains("one_size")), "{paper:#?}");
    assert!(paper.iter().any(|t| t.starts_with("  2x Burger") && !t.contains('(')), "{paper:#?}");
    assert_eq!(
        l.parts[2].addons,
        vec![checkout::ReceiptModifierView {
            name: "Oat milk".into(),
            price_minor: 3000
        }]
    );
    assert_eq!(
        (again.lines[1].line_total_minor, again.lines[1].deal_minor),
        (11000, 2000)
    );
    assert_eq!(
        again.deals,
        vec![checkout::ReceiptDealView {
            name: "Any 2 bites for 90".into(),
            discount_minor: 2000
        }]
    );
    assert_eq!(
        (again.subtotal_minor, again.gross_subtotal_minor()),
        (48000, 50000)
    );
}

#[tokio::test]
async fn the_kitchen_gets_one_dish_per_part_tagged_with_its_combo() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    let lines = core
        .cart_add_combo(
            None,
            LUNCH.into(),
            lunch_picks("Large", true),
            2,
            Some("no salt".into()),
        )
        .unwrap();
    let l = combo_line(&lines);

    let slip = receipt::slip_items_for_cart_line(&l, "en");
    let got: Vec<(&str, i64, Option<&str>, Option<&str>)> = slip
        .iter()
        .map(|s| {
            (
                s.item.as_str(),
                s.qty,
                s.size_label.as_deref(),
                s.combo.as_deref(),
            )
        })
        .collect();
    assert_eq!(
        got,
        vec![
            ("Burger", 2, None, Some("In Lunch deal")),
            ("Fries", 2, None, Some("In Lunch deal")),
            ("Latte", 2, Some("Large"), Some("In Lunch deal")),
        ]
    );
    assert_eq!(slip[2].modifiers, vec!["Oat milk".to_string()]);
    assert!(
        slip.iter().all(|s| s.note.as_deref() == Some("no salt")),
        "the combo's note rides every dish"
    );
    let ar = receipt::slip_items_for_cart_line(&l, "ar");
    assert_eq!(ar[0].combo.as_deref(), Some("ضمن Lunch deal"));

    let chits = core.kitchen_chits_for_line(l.clone(), Some("4".into()), None);
    assert_eq!(chits.len(), 3);
    let labels = receipt::KitchenChitLabels {
        heading: "KITCHEN".into(),
        table: "Table".into(),
        note: "Note:".into(),
    };
    let printed: Vec<String> = receipt::kitchen_chit_layout(&chits[2], &labels, 32)
        .into_iter()
        .map(|x| x.text)
        .collect();
    assert!(
        printed.iter().any(|t| t.contains("2x Latte (Large)")),
        "{printed:#?}"
    );
    assert!(
        printed.iter().any(|t| t.contains("In Lunch deal")),
        "{printed:#?}"
    );

    // The KDS: the header is never fired; each part is a kitchen line
    // tagged with its combo, and the plain line beside it is not.
    core.cart_add(None, COOKIE.into(), "Cookie".into(), 4000)
        .unwrap();
    let lines = core.cart_lines(None).unwrap();
    let round = uuid::Uuid::new_v4().to_string();
    let t = kds::build_fire_projection(&round, &lines, None, 1, "now".into()).unwrap();
    let got: Vec<(&str, i32, Option<String>)> = t
        .items
        .iter()
        .map(|i| {
            (
                i.name.as_str(),
                i.qty,
                i.combo.as_ref().map(|c| c.name.clone()),
            )
        })
        .collect();
    assert_eq!(
        got,
        vec![
            ("Burger", 2, Some("Lunch deal".into())),
            ("Fries", 2, Some("Lunch deal".into())),
            ("Latte", 2, Some("Lunch deal".into())),
            ("Cookie", 1, None),
        ]
    );
    let tags: BTreeSet<String> = t
        .items
        .iter()
        .filter_map(|i| i.combo.as_ref().map(|c| c.line_id.clone()))
        .collect();
    assert_eq!(tags.len(), 1, "every part of one combo shares its line id");
}

#[tokio::test]
async fn a_fired_round_projects_the_same_combo_live_and_from_its_envelope() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    let table = Some("00000000-0000-0000-0000-00000000aa04".to_string());
    core.cart_add(table.clone(), COOKIE.into(), "Cookie".into(), 4000)
        .unwrap();
    core.cart_add_combo(
        table.clone(),
        LUNCH.into(),
        lunch_picks("Large", true),
        1,
        None,
    )
    .unwrap();
    let lines = core.cart_lines(table.clone()).unwrap();
    core.fire_ticket(table, None, None, None, None, None)
        .await
        .unwrap();
    let op = core
        .store
        .pending()
        .unwrap()
        .into_iter()
        .find(|i| i.op_type == "open_ticket")
        .expect("a queued fire");
    let (env, _) = core.replay_envelope(&op).map_err(|_| "envelope").unwrap();
    let req = &env["request"];
    let pick = &req["items"][1]["combo"]["picks"][2];
    assert_eq!(
        (pick["share"].as_i64(), pick["surcharge"].as_i64()),
        (Some(3571), Some(1000)),
        "a ticket's round carries the figures too"
    );
    assert!(
        req.get("deals").is_none_or(Value::is_null),
        "a ticket carries no deal"
    );

    let names: std::collections::HashMap<String, String> = [
        (LUNCH, "Lunch deal"),
        (BURGER, "Burger"),
        (FRIES, "Fries"),
        (LATTE, "Latte"),
        (COOKIE, "Cookie"),
    ]
    .into_iter()
    .map(|(k, v)| (k.to_string(), v.to_string()))
    .collect();
    let from_env = kds::projection_from_envelope(&env, &names, "now").expect("a projection");
    let round = req["round_idempotency_key"]
        .as_str()
        .or(req["idempotency_key"].as_str())
        .unwrap();
    let live = kds::build_fire_projection(round, &lines, None, 1, "now".into()).unwrap();
    let shape =
        |t: &kds::KdsTicketView| -> Vec<(String, String, i32, Option<crate::kds::KdsComboTag>)> {
            t.items
                .iter()
                .map(|i| (i.id.clone(), i.name.clone(), i.qty, i.combo.clone()))
                .collect()
        };
    assert_eq!(
        shape(&live),
        shape(&from_env),
        "the LAN copy and the catch-up agree"
    );

    // The bill shown before the fire syncs: the combo at what it was charged
    // (P + the Large surcharge + oat), not P alone; and closed to a reward.
    let bills = core.list_open_tickets().await.unwrap();
    let bill = bills
        .iter()
        .find(|b| b.status == "queued")
        .expect("the queued bill");
    let totals: Vec<(&str, i64, bool)> = bill
        .lines
        .iter()
        .map(|l| (l.name.as_str(), l.line_total_minor, l.is_combo))
        .collect();
    assert_eq!(
        totals,
        vec![("Cookie", 4000, false), ("Lunch deal", 17500, true)]
    );
    assert_eq!(bill.subtotal_minor, 21500);
}

// ── 8. loyalty and staff drinks ─────────────────────────────────────────────

#[tokio::test]
async fn no_reward_and_no_staff_drink_inside_a_combo_or_a_deal() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed(&core);
    core.cart_add_combo(None, LUNCH.into(), lunch_picks("Regular", false), 1, None)
        .unwrap();
    two_croissants_and_a_cookie(&core);
    core.cart_apply_deal(None, DEAL_BITES.into()).unwrap();
    let lines = core.cart_lines(None).unwrap();

    // The reward board is told which lines are closed to a reward.
    let rl = core.cart_reward_lines(None).unwrap();
    assert_eq!(
        rl.iter()
            .map(|l| (l.in_combo, l.in_deal))
            .collect::<Vec<_>>(),
        vec![(true, false), (false, true), (false, false)]
    );
    // Charged: refused before anything is queued.
    let ask = |i: u32| {
        vec![checkout::CheckoutRedemption {
            item_index: i,
            ticket_line_id: None,
            units: 1,
        }]
    };
    let err = checkout::reward_units_by_line(&lines, &ask(0)).unwrap_err();
    assert!(format!("{err:?}").contains(checkout::REWARD_IN_COMBO));
    let err = checkout::reward_units_by_line(&lines, &ask(1)).unwrap_err();
    assert!(format!("{err:?}").contains(checkout::REWARD_IN_DEAL));
    assert!(checkout::reward_units_by_line(&lines, &ask(2)).is_ok());
    // Priced: a reward asked for on the combo covers nothing.
    assert_eq!(
        core.cart_totals_with_rewards(None, ask(0)).unwrap(),
        core.cart_totals(None).unwrap()
    );

    // A staff drink is never a combo (C15), in the teller's words.
    core.store
        .kv_put(
            crate::branch_reads::F_STAFF_POOL.1,
            &json!({ "enabled": true, "daily_allowance": 5, "eligible_item_ids": [LUNCH, CROISSANT, LATTE] }).to_string(),
        )
        .unwrap();
    if let Some(sess) = core.session.write().unwrap().as_mut() {
        sess.authz
            .as_mut()
            .unwrap()
            .capabilities
            .push(crate::staff_drink::CAP_STAFF_DRINK.to_string());
    }
    let combo_key = combo_line(&lines).key;
    match core.mark_staff_drink(None, combo_key, "for Sara".into(), None) {
        Err(crate::CoreError::Validation { detail, .. }) => {
            assert_eq!(detail, en("combo.staff_drink"))
        }
        other => panic!("{other:?}"),
    }
    match core.mark_staff_drink(
        None,
        line_of(&lines, CROISSANT).key,
        "for Sara".into(),
        None,
    ) {
        Err(crate::CoreError::Validation { detail, .. }) => {
            assert_eq!(detail, en("deal.staff_drink"))
        }
        other => panic!("{other:?}"),
    }
    assert!(core
        .cart_lines(None)
        .unwrap()
        .iter()
        .all(|l| l.staff_drink.is_none()));
}

/// The core refuses with English sentences the host maps to its keys
/// (`failure.dart`); each must be word for word the key's English.
#[test]
fn the_refusal_sentences_are_their_keys_english() {
    assert_eq!(checkout::REWARD_IN_COMBO, en("combo.reward"));
    assert_eq!(checkout::REWARD_IN_DEAL, en("deal.reward"));
    assert_eq!(cart::STAFF_DRINK_IN_COMBO, en("combo.staff_drink"));
    assert_eq!(cart::STAFF_DRINK_IN_DEAL, en("deal.staff_drink"));
}

// ── 10. the words ───────────────────────────────────────────────────────────

#[test]
fn the_counted_combo_and_deal_phrases_read_in_each_count_s_form() {
    let fill = |loc: &str, key: &str, n: i64| {
        i18n::tr_count(loc, key, n).replace("{count}", &n.to_string())
    };
    assert_eq!(fill("en", "combo.pick_n", 1), "Choose 1 item");
    assert_eq!(fill("en", "combo.pick_n", 2), "Choose 2 items");
    assert_eq!(fill("en", "combo.pick_up_to", 1), "Choose up to 1 item");
    assert_eq!(fill("en", "combo.pick_up_to", 3), "Choose up to 3 items");
    assert_eq!(fill("en", "deal.applies_times", 1), "Applies once");
    assert_eq!(fill("en", "deal.applies_times", 2), "Applies 2 times");
    // Arabic: one, two, a few (3–10), many (11–99), and a hundred.
    for key in ["combo.pick_n", "combo.pick_up_to", "deal.applies_times"] {
        let forms: Vec<String> = [1, 2, 3, 11, 100]
            .iter()
            .map(|n| fill("ar", key, *n))
            .collect();
        let distinct: BTreeSet<&String> = forms.iter().collect();
        assert_eq!(distinct.len(), 5, "{key}: {forms:?}");
        for f in &forms {
            assert!(
                !f.contains('{') && f.chars().any(|c| ('\u{0600}'..='\u{06FF}').contains(&c)),
                "{key}: {f}"
            );
        }
    }
    assert_eq!(fill("ar", "combo.pick_n", 1), "اختر صنفًا واحدًا");
    assert_eq!(fill("ar", "combo.pick_n", 2), "اختر صنفين");
    assert_eq!(fill("ar", "combo.pick_n", 3), "اختر 3 أصناف");
    assert_eq!(fill("ar", "deal.applies_times", 2), "يُطبَّق مرتين");
    // Every coded refusal (§2.7) the till words, in both languages.
    for key in [
        "combo.unavailable",
        "combo.picks_required",
        "combo.slot_too_few",
        "combo.slot_too_many",
        "combo.choice_not_allowed",
        "combo.item_unavailable",
        "combo.whole_only",
        "combo.staff_drink",
        "combo.reward",
        "combo.nested",
        "combo.slot_invalid",
        "combo.slots_required",
        "combo.no_recipe",
        "combo.kind_locked",
        "meal.target_invalid",
        "deal.not_eligible",
        "deal.invalid",
        "deal.units_overlap",
        "deal.not_allowed",
        "deal.dropped",
        "combo.in_combo",
        "combo.channel_off",
    ] {
        assert_ne!(i18n::tr("en", key), key, "{key} (en)");
        assert_ne!(i18n::tr("ar", key), key, "{key} (ar)");
        assert_ne!(
            i18n::tr("ar", key),
            i18n::tr("en", key),
            "{key}: translated"
        );
    }
    assert_eq!(
        en("combo.slot_too_few"),
        "Choose at least {min} for {slot}."
    );
    assert_eq!(
        i18n::tr("ar", "combo.whole_only"),
        "يُسترد الكومبو أو يُلغى بالكامل فقط."
    );
}

/// The server stores "one_size" on a combo's single-size parts; no view, slip
/// or chit ever shows it (the KDS, the bill, the order detail read through it).
#[test]
fn one_size_is_never_a_size_a_person_reads() {
    assert_eq!(cart::real_size(Some("one_size".into())), None);
    assert_eq!(cart::real_size(Some(" One_Size ".into())), None);
    assert_eq!(cart::real_size(Some(String::new())), None);
    assert_eq!(cart::real_size(Some("Large".into())), Some("Large".into()));
    let chit = receipt::KitchenChit {
        item: "Burger".into(),
        qty: 1,
        size_label: Some("one_size".into()),
        modifiers: vec![],
        note: None,
        table_label: None,
        ticket_ref: None,
        at: "13:05".into(),
        teller: None,
        combo: Some("In Lunch deal".into()),
    };
    let labels = receipt::KitchenChitLabels {
        heading: "KITCHEN".into(),
        table: "Table".into(),
        note: "Note:".into(),
    };
    let printed: Vec<String> = receipt::kitchen_chit_layout(&chit, &labels, 32).into_iter().map(|l| l.text).collect();
    assert!(!printed.iter().any(|t| t.contains("one_size")), "{printed:#?}");
}
