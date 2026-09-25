//! Combos and deals: the REAL `MadarCore` against the REAL backend
//! (COMBOS_CONTRACT §3, §4, §5).
//!
//! Ignored by `cargo test`. Run through the offline-B harness, on its own DB
//! copy (a POS 0.9.0 client: the server sells combos to `pos/>=0.9.0` only):
//!
//! ```sh
//! MADAR_OB_TESTS=combos_backend tool/offline_b_backend.sh
//! ```
//!
//! The catalogue is seeded once per copy with the contract's worked example:
//! a burger (120.00), fries (40.00) and a latte (Regular 50.00 / Large 60.00,
//! with an optional oat milk at 15.00) — the combo "CB Lunch" at P = 150.00
//! over three slots, the latte's "make it a meal" pointing at its drink slot,
//! and a deal "CB Two fries" (any 2 fries for 60.00).
//!
//! Every scenario asserts against the SERVER's rows after the sale drained
//! through `/sync/replay`:
//! 1. a meal with a Large latte and oat milk: the header (no money, P), the
//!    parts 8571 / 2858 / 3571 + 1000, the oat add-on 1500, the subtotal
//!    17500 — the till's figures equal the server's and nothing is flagged;
//! 2. "make it a meal" from a latte line: the defaults fill the other slots;
//! 3. a deal the teller applies: the fries line carries its cut, the order
//!    its deal row, and the till's discount equals the server's.

mod common;

use common::*;
use madar_core::cart::AddonSelection;
use madar_core::checkout::CheckoutInput;
use madar_core::combos::ComboPickInput;
use madar_core::{MadarConfig, MadarCore};
use std::sync::Arc;
use std::time::{Duration, Instant};
use uuid::Uuid;

const APP_VERSION: &str = "0.9.0";
const CAP_DEALS_APPLY: i16 = 252;
const P: i32 = 15000;
const BURGER: i32 = 12000;
const FRIES: i32 = 4000;
const LATTE_R: i32 = 5000;
const LATTE_L: i32 = 6000;
const OAT: i32 = 1500;
const TWO_FRIES: i32 = 6000;
const COMBO: &str = "CB Lunch";

struct Seed {
    combo: Uuid,
    burger: Uuid,
    fries: Uuid,
    latte: Uuid,
    oat: Uuid,
    main: Uuid,
    side: Uuid,
    drink: Uuid,
    deal: Uuid,
}

async fn one(fx: &Fixture, sql: &str, args: &[&(dyn tokio_postgres::types::ToSql + Sync)]) -> Uuid {
    fx.db
        .query_one(sql, args)
        .await
        .unwrap_or_else(|e| panic!("{sql}: {e}"))
        .get(0)
}

/// Seed the catalogue once per DB copy; later scenarios find it by name.
async fn seed(fx: &Fixture) -> Seed {
    let branch = Uuid::parse_str(&fx.branch).unwrap();
    let org: Uuid = one(fx, "SELECT org_id FROM branches WHERE id = $1", &[&branch]).await;
    // No tax, no service: the bill is the lines, so every figure below is the
    // contract's own.
    fx.db
        .execute(
            "UPDATE branches SET tax_rate = 0, tax_inclusive = false WHERE id = $1",
            &[&branch],
        )
        .await
        .expect("branch tax");
    let found = fx
        .db
        .query_opt(
            "SELECT id FROM menu_items WHERE org_id = $1 AND name = $2 AND kind = 'combo'",
            &[&org, &COMBO],
        )
        .await
        .unwrap();
    if found.is_none() {
        let cat = match fx
            .db
            .query_opt("SELECT id FROM categories WHERE org_id = $1 AND name = 'CB Combos'", &[&org])
            .await
            .unwrap()
        {
            Some(r) => r.get::<_, Uuid>(0),
            None => {
                one(
                    fx,
                    "INSERT INTO categories (org_id, name, display_order) VALUES ($1, 'CB Combos', 99) RETURNING id",
                    &[&org],
                )
                .await
            }
        };
        let item = |name: &'static str| {
            let db = &fx.db;
            async move {
                db.query_one(
                    "INSERT INTO menu_items (org_id, category_id, name, base_price) VALUES ($1, $2, $3, 0) RETURNING id",
                    &[&org, &cat, &name],
                )
                .await
                .expect("item")
                .get::<_, Uuid>(0)
            }
        };
        let (burger, fries, latte) = (
            item("CB Burger").await,
            item("CB Fries").await,
            item("CB Latte").await,
        );
        // Every new item gets its `one_size` row from a trigger: price it (and
        // make the latte's its Regular, beside a Large).
        for (id, label, price) in [
            (burger, "one_size", BURGER),
            (fries, "one_size", FRIES),
            (latte, "Regular", LATTE_R),
        ] {
            fx.db
                .execute(
                    "UPDATE menu_item_sizes SET label = $2, price = $3 WHERE menu_item_id = $1 AND label = 'one_size'",
                    &[&id, &label, &price],
                )
                .await
                .expect("size");
        }
        fx.db
            .execute(
                "INSERT INTO menu_item_sizes (menu_item_id, label, price, sort) VALUES ($1, 'Large', $2, 1)",
                &[&latte, &LATTE_L],
            )
            .await
            .expect("large");
        // Oat milk: an optional, priced pick on the latte.
        let group = one(
            fx,
            "INSERT INTO modifier_groups (org_id, name, selection_type, min_selections, max_selections,
                                          is_required, sort, legacy_addon_type, effect)
             VALUES ($1, 'CB Milk', 'single', 0, 1, false, 5, 'extra', 'adds') RETURNING id",
            &[&org],
        )
        .await;
        fx.db
            .execute(
                "INSERT INTO modifier_options (group_id, name, price, sort) VALUES ($1, 'CB Oat', $2, 0)",
                &[&group, &OAT],
            )
            .await
            .expect("oat");
        fx.db
            .execute(
                "INSERT INTO menu_item_modifier_groups (menu_item_id, group_id, sort) VALUES ($1, $2, 5)",
                &[&latte, &group],
            )
            .await
            .expect("attach milk");

        // The combo: a menu item of kind 'combo' whose price P is its one_size.
        let combo = one(
            fx,
            "INSERT INTO menu_items (org_id, category_id, name, kind) VALUES ($1, $2, $3, 'combo') RETURNING id",
            &[&org, &cat, &COMBO],
        )
        .await;
        fx.db
            .execute(
                "UPDATE menu_item_sizes SET price = $2 WHERE menu_item_id = $1 AND label = 'one_size'",
                &[&combo, &P],
            )
            .await
            .expect("combo price");
        fx.db
            .execute(
                "INSERT INTO menu_item_combos (menu_item_id, org_id) VALUES ($1, $2)",
                &[&combo, &org],
            )
            .await
            .expect("combo row");
        for (sort, name, item, included) in [
            (0, "Main", burger, None::<&str>),
            (1, "Side", fries, None),
            (2, "Drink", latte, Some("Regular")),
        ] {
            let slot = one(
                fx,
                "INSERT INTO combo_slots (org_id, combo_item_id, name, sort, min_picks, max_picks, default_item_id,
                                          default_size_label)
                 VALUES ($1, $2, $3, $4, 1, 1, $5, $6) RETURNING id",
                &[&org, &combo, &name, &sort, &item, &included],
            )
            .await;
            fx.db
                .execute(
                    "INSERT INTO combo_slot_choices (org_id, slot_id, menu_item_id, included_size_label)
                     VALUES ($1, $2, $3, $4)",
                    &[&org, &slot, &item, &included],
                )
                .await
                .expect("choice");
        }
        let drink: Uuid = one(
            fx,
            "SELECT id FROM combo_slots WHERE combo_item_id = $1 AND name = 'Drink'",
            &[&combo],
        )
        .await;
        fx.db
            .execute(
                "UPDATE menu_items SET meal_combo_id = $1, meal_slot_id = $2 WHERE id = $3",
                &[&combo, &drink, &latte],
            )
            .await
            .expect("make it a meal");
        let deal = one(
            fx,
            "INSERT INTO deal_rules (org_id, name, kind, qty, price) VALUES ($1, 'CB Two fries', 'n_for_price', 2, $2)
             RETURNING id",
            &[&org, &TWO_FRIES],
        )
        .await;
        fx.db
            .execute(
                "INSERT INTO deal_rule_items (org_id, deal_rule_id, role, menu_item_id) VALUES ($1, $2, 'pool', $3)",
                &[&org, &deal, &fries],
            )
            .await
            .expect("deal pool");
    }
    let id = |sql: &'static str| {
        let db = &fx.db;
        async move {
            db.query_one(sql, &[&org])
                .await
                .unwrap_or_else(|e| panic!("{sql}: {e}"))
                .get::<_, Uuid>(0)
        }
    };
    let combo = id("SELECT id FROM menu_items WHERE org_id = $1 AND name = 'CB Lunch'").await;
    let slot = |name: &'static str| {
        let db = &fx.db;
        async move {
            db.query_one(
                "SELECT id FROM combo_slots WHERE combo_item_id = $1 AND name = $2",
                &[&combo, &name],
            )
            .await
            .expect("slot")
            .get::<_, Uuid>(0)
        }
    };
    let s = Seed {
        combo,
        burger: id("SELECT id FROM menu_items WHERE org_id = $1 AND name = 'CB Burger'").await,
        fries: id("SELECT id FROM menu_items WHERE org_id = $1 AND name = 'CB Fries'").await,
        latte: id("SELECT id FROM menu_items WHERE org_id = $1 AND name = 'CB Latte'").await,
        oat: id(
            "SELECT o.id FROM modifier_options o JOIN modifier_groups g ON g.id = o.group_id
                  WHERE g.org_id = $1 AND o.name = 'CB Oat'",
        )
        .await,
        main: slot("Main").await,
        side: slot("Side").await,
        drink: slot("Drink").await,
        deal: id("SELECT id FROM deal_rules WHERE org_id = $1 AND name = 'CB Two fries'").await,
    };
    eprintln!("SEED combo {} deal {}", s.combo, s.deal);
    s
}

/// A 0.9.0 till, signed in, its catalogue and first snapshot in.
async fn core_090(base: &str, db_path: &str, teller: &str, branch: &str) -> Arc<MadarCore> {
    let core = MadarCore::new(MadarConfig {
        base_url: base.to_string(),
        environment: "dev".into(),
        db_path: db_path.to_string(),
        locale: "en".into(),
        app_version: Some(APP_VERSION.into()),
    })
    .expect("core");
    let deadline = Instant::now() + Duration::from_secs(120);
    loop {
        match core
            .sign_in(madar_core::session::LoginRequest {
                mode: madar_core::session::LoginMode::Pin,
                name: Some(teller.to_string()),
                pin: Some("1234".into()),
                branch_id: Some(branch.to_string()),
                email: None,
                password: None,
                org_id: None,
            })
            .await
        {
            Err(madar_core::error::CoreError::Server { status: 429, .. })
                if Instant::now() < deadline =>
            {
                tokio::time::sleep(Duration::from_secs(3)).await;
            }
            other => {
                other.expect("sign in");
                break;
            }
        }
    }
    core.refresh_connectivity().await;
    core.refresh_catalog().await.expect("catalog");
    core.sync_full().await.expect("first snapshot");
    core
}

struct Till {
    fx: Fixture,
    s: Seed,
    core: Arc<MadarCore>,
}

async fn till(tag: &str) -> Till {
    let fx = fixture(1).await;
    let s = seed(&fx).await;
    let org: Uuid = fx
        .db
        .query_one(
            "SELECT org_id FROM branches WHERE id = $1",
            &[&Uuid::parse_str(&fx.branch).unwrap()],
        )
        .await
        .unwrap()
        .get(0);
    fx.db
        .execute(
            "INSERT INTO user_overrides (org_id, user_id, capability_id, effect, reason)
             VALUES ($1, $2, $3, 'allow', 'combos scenario')",
            &[&org, &fx.tellers[0].0, &CAP_DEALS_APPLY],
        )
        .await
        .expect("deal grant");
    let core = core_090(&fx.base, &temp_db(tag), &fx.tellers[0].1, &fx.branch).await;
    core.open_till(10_000, Some(format!("combos {tag}")))
        .await
        .expect("open");
    let items = core.list_menu_items().expect("items");
    assert!(
        items
            .iter()
            .any(|i| i.id == s.combo.to_string() && i.kind == "combo"),
        "the combo reached a 0.9.0 till's menu"
    );
    Till { fx, s, core }
}

fn cash(core: &MadarCore, total: i64) -> CheckoutInput {
    CheckoutInput {
        payment_method_id: method(core, true).expect("cash"),
        amount_tendered_minor: total,
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

fn pick(slot: Uuid, item: Uuid, size: Option<&str>, addons: Vec<AddonSelection>) -> ComboPickInput {
    ComboPickInput {
        slot_id: slot.to_string(),
        item_id: item.to_string(),
        size_label: size.map(str::to_string),
        qty: 1,
        addons,
        optional_field_ids: vec![],
        notes: None,
    }
}

/// Charge the cart in cash and wait for the server to hold it.
async fn charge(core: &MadarCore) -> (Uuid, i64) {
    let totals = core.cart_totals(None).expect("totals");
    let sale = core
        .checkout(None, cash(core, totals.total_minor))
        .await
        .expect("checkout");
    assert_eq!(sale.total_minor, totals.total_minor);
    settle(core, 90).await;
    (
        Uuid::parse_str(&sale.local_order_id).unwrap(),
        totals.subtotal_minor,
    )
}

#[derive(Debug, PartialEq)]
struct Line {
    kind: String,
    item: Uuid,
    size: Option<String>,
    qty: i32,
    unit: i32,
    total: i32,
    share: i32,
    surcharge: i32,
    combo_unit: Option<i32>,
    deal: i32,
    flagged: bool,
    header: Option<Uuid>,
    addons: Vec<(String, i32)>,
}

struct ServerSale {
    order: Uuid,
    subtotal: i32,
    lines: Vec<Line>,
    header_id: Option<Uuid>,
    deals: Vec<(Uuid, i32, Option<i32>, i16)>,
    flags: Vec<String>,
}

async fn server_sale(fx: &Fixture, key: Uuid) -> ServerSale {
    let o = fx
        .db
        .query_one(
            "SELECT id, subtotal FROM orders WHERE idempotency_key = $1",
            &[&key],
        )
        .await
        .expect("the sale is on the server");
    let order: Uuid = o.get(0);
    let rows = fx
        .db
        .query(
            "SELECT id, line_kind, menu_item_id, size_label, quantity, unit_price, line_total, combo_share,
                    combo_surcharge, combo_unit_price, deal_minor, price_flagged, combo_line_id
               FROM order_items WHERE order_id = $1
              ORDER BY COALESCE(combo_line_id, id), combo_line_id IS NOT NULL, id",
            &[&order],
        )
        .await
        .expect("lines");
    let mut lines = Vec::new();
    let mut header_id = None;
    for r in &rows {
        let id: Uuid = r.get(0);
        let addons = fx
            .db
            .query("SELECT addon_name, line_total FROM order_item_addons WHERE order_item_id = $1 ORDER BY addon_name", &[&id])
            .await
            .unwrap()
            .iter()
            .map(|a| (a.get(0), a.get(1)))
            .collect();
        let kind: String = r.get(1);
        if kind == "combo" {
            header_id = Some(id);
        }
        lines.push(Line {
            kind,
            item: r.get(2),
            size: r.get(3),
            qty: r.get(4),
            unit: r.get(5),
            total: r.get(6),
            share: r.get(7),
            surcharge: r.get(8),
            combo_unit: r.get(9),
            deal: r.get(10),
            flagged: r.get(11),
            header: r.get(12),
            addons,
        });
    }
    let deals = fx
        .db
        .query("SELECT deal_rule_id, discount, discount_server, times FROM order_deals WHERE order_id = $1", &[&order])
        .await
        .unwrap()
        .iter()
        .map(|r| (r.get(0), r.get(1), r.get(2), r.get(3)))
        .collect();
    let flags = fx
        .db
        .query(
            "SELECT capability FROM authz_replay_flags WHERE subject_id = $1 ORDER BY capability",
            &[&order],
        )
        .await
        .unwrap()
        .iter()
        .map(|r| r.get(0))
        .collect();
    let s = ServerSale {
        order,
        subtotal: o.get(1),
        lines,
        header_id,
        deals,
        flags,
    };
    eprintln!(
        "SERVER order {} subtotal {} flags {:?} deals {:?}",
        s.order, s.subtotal, s.flags, s.deals
    );
    for l in &s.lines {
        eprintln!("  {l:?}");
    }
    s
}

fn part<'a>(sv: &'a ServerSale, item: Uuid) -> &'a Line {
    sv.lines
        .iter()
        .find(|l| l.kind == "combo_part" && l.item == item)
        .expect("the part")
}

#[tokio::test]
#[ignore]
async fn c1_a_meal_with_a_large_latte_and_oat_splits_as_the_contract_says() {
    let t = till("cb1").await;
    let s = &t.s;
    let picks = vec![
        pick(s.main, s.burger, None, vec![]),
        pick(s.side, s.fries, None, vec![]),
        pick(
            s.drink,
            s.latte,
            Some("Large"),
            vec![AddonSelection {
                addon_item_id: s.oat.to_string(),
                qty: 1,
            }],
        ),
    ];
    let q = t
        .core
        .combo_quote(None, s.combo.to_string(), picks.clone(), 1)
        .expect("quote");
    assert_eq!(
        (q.unit_total_minor, q.saving_minor),
        (17500, 6000),
        "the till's quote: {q:?}"
    );
    t.core
        .cart_add_combo(None, s.combo.to_string(), picks, 1, None)
        .expect("add the meal");
    let (key, subtotal) = charge(&t.core).await;
    assert_eq!(subtotal, 17500);

    let sv = server_sale(&t.fx, key).await;
    assert_eq!(sv.subtotal, 17500, "the server's subtotal is the till's");
    let h = sv
        .lines
        .iter()
        .find(|l| l.kind == "combo")
        .expect("a header");
    assert_eq!(
        (h.item, h.qty, h.unit, h.total, h.combo_unit),
        (s.combo, 1, 0, 0, Some(P)),
        "the header: {h:?}"
    );
    let (b, f, l) = (part(&sv, s.burger), part(&sv, s.fries), part(&sv, s.latte));
    for p in [b, f, l] {
        assert_eq!(p.header, sv.header_id, "every part points at its header");
        assert!(!p.flagged, "nothing flagged: {p:?}");
    }
    assert_eq!((b.share, b.surcharge, b.total), (8571, 0, 8571));
    assert_eq!((f.share, f.surcharge, f.total), (2858, 0, 2858));
    assert_eq!((l.share, l.surcharge, l.total), (3571, 1000, 4571));
    assert_eq!(
        (l.size.as_deref(), l.unit),
        (Some("Large"), LATTE_L),
        "the latte at its normal Large price"
    );
    assert_eq!(
        l.addons,
        vec![("CB Oat".to_string(), OAT)],
        "the oat add-on at its normal price"
    );
    assert_eq!(b.share + f.share + l.share, P, "the shares sum to P");
    assert!(sv.flags.is_empty(), "no replay flags: {:?}", sv.flags);
}

#[tokio::test]
#[ignore]
async fn c2_make_it_a_meal_from_a_latte_line() {
    let t = till("cb2").await;
    let s = &t.s;
    let offer = t
        .core
        .meal_offer(s.latte.to_string())
        .expect("the latte offers its meal");
    // The meal at the latte's own Regular with the defaults elsewhere
    // (150.00), minus the latte alone (50.00).
    assert_eq!(offer.delta_minor, (P - LATTE_R) as i64);
    let lines = t
        .core
        .cart_add_configured(
            None,
            s.latte.to_string(),
            Some("Regular".into()),
            vec![AddonSelection {
                addon_item_id: s.oat.to_string(),
                qty: 1,
            }],
            vec![],
            1,
            None,
        )
        .expect("a latte with oat");
    let key = lines.last().unwrap().key.clone();
    let draft = t
        .core
        .cart_make_it_a_meal(None, key.clone())
        .expect("the meal draft");
    assert_eq!(draft.line_key.as_deref(), Some(key.as_str()));
    let lines = t
        .core
        .cart_replace_combo(None, key, draft.combo_id, draft.picks, draft.qty, None)
        .expect("the line becomes the meal");
    assert_eq!(lines.len(), 1);
    assert_eq!(lines[0].kind, "combo");
    let (order_key, subtotal) = charge(&t.core).await;
    assert_eq!(subtotal, (P + OAT) as i64);

    let sv = server_sale(&t.fx, order_key).await;
    assert_eq!(sv.subtotal, P + OAT);
    let l = part(&sv, s.latte);
    assert_eq!(
        (l.share, l.surcharge, l.total, l.size.as_deref()),
        (3571, 0, 3571, Some("Regular"))
    );
    assert_eq!(
        l.addons,
        vec![("CB Oat".to_string(), OAT)],
        "the line's oat went with it into the meal"
    );
    assert_eq!(
        (part(&sv, s.burger).total, part(&sv, s.fries).total),
        (8571, 2858),
        "defaults elsewhere"
    );
    assert!(sv.flags.is_empty(), "no replay flags: {:?}", sv.flags);
}

#[tokio::test]
#[ignore]
async fn c3_a_deal_the_teller_applies() {
    let t = till("cb3").await;
    let s = &t.s;
    t.core
        .cart_add_configured(None, s.fries.to_string(), None, vec![], vec![], 2, None)
        .expect("two fries");
    t.core
        .cart_add_configured(None, s.burger.to_string(), None, vec![], vec![], 1, None)
        .expect("a burger");
    let sug = t.core.cart_deal_suggestions(None);
    let d = sug
        .iter()
        .find(|d| d.deal_id == s.deal.to_string())
        .expect("the cart qualifies");
    assert_eq!(d.saving_minor, (2 * FRIES - TWO_FRIES) as i64);
    assert!(
        t.core.cart_applied_deals(None).is_empty(),
        "suggested, never applied by itself"
    );
    let lines = t
        .core
        .cart_apply_deal(None, s.deal.to_string())
        .expect("the teller applies it");
    let fries = lines
        .iter()
        .find(|l| l.item_id == s.fries.to_string())
        .expect("the fries line");
    assert_eq!(fries.deal_cut_minor, 2000);
    let (key, subtotal) = charge(&t.core).await;
    assert_eq!(subtotal, (2 * FRIES + BURGER - 2000) as i64);

    let sv = server_sale(&t.fx, key).await;
    assert_eq!(
        sv.subtotal as i64, subtotal,
        "the server's subtotal is the till's"
    );
    let f = sv
        .lines
        .iter()
        .find(|l| l.item == s.fries)
        .expect("fries on the server");
    assert_eq!(
        (f.kind.as_str(), f.qty, f.unit, f.deal, f.total),
        ("item", 2, FRIES, 2000, 6000)
    );
    let b = sv
        .lines
        .iter()
        .find(|l| l.item == s.burger)
        .expect("burger on the server");
    assert_eq!(
        (b.deal, b.total),
        (0, BURGER),
        "the burger is not in the deal"
    );
    assert_eq!(sv.deals.len(), 1, "one deal row: {:?}", sv.deals);
    let (rule, discount, server, times) = sv.deals[0];
    assert_eq!((rule, discount, times), (s.deal, 2000, 1));
    assert_eq!(
        server,
        Some(2000),
        "the server agrees with the till's discount"
    );
    assert!(sv.flags.is_empty(), "no replay flags: {:?}", sv.flags);
}
