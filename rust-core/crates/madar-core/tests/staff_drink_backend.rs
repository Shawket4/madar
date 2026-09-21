//! A MARKED staff drink: the REAL `MadarCore` against the REAL backend
//! (`docs/staff-drink-comp-contract.md` in MadarRust).
//!
//! Ignored by `cargo test`. Run through the offline-B harness, on its own DB
//! copy:
//!
//! ```sh
//! MADAR_OB_TESTS=staff_drink_backend tool/offline_b_backend.sh
//! ```
//!
//! Every scenario asserts against the SERVER's rows after the sale drained
//! through `/sync/replay`:
//! 1. base configuration → a normal order, total 0, the comp on the line, the
//!    pool row attached, the cost still recorded;
//! 2. a bigger size + an optional add-on pay their difference, taxed on the
//!    charged part only, and the till's bill is the server's;
//! 3. a required group: the default pick is free, a pricier pick pays the
//!    difference;
//! 4. two units are two drinks and twice the comp;
//! 5. an overspend lands — flagged when only the server knew, quiet when the
//!    till knew too;
//! 6. a second device reads the drink and the same pool count;
//! 7. a till that states a WRONG comp lands, and the server keeps both figures
//!    and flags the difference;
//! 8. a teller without the act: a manager's approval rides the sale clean; an
//!    envelope without it is accepted and flagged;
//! 9. the record-only op (old tills) still works.
//!
//! The catalogue is seeded once in the DB copy from a real item that has a
//! costed recipe: its single size becomes `Regular`, a `Large` is added with
//! the same recipe, and a required single-choice group (`Classic` default /
//! `Premium`) is attached beside the item's existing optional add-ons.

mod common;

use common::*;
use madar_core::cart::AddonSelection;
use madar_core::checkout::CheckoutInput;
use madar_core::staff_drink::StaffDrinkInput;
use madar_core::MadarCore;
use uuid::Uuid;

const CAP: &str = "orders.staff_drink.record";
const CAP_ID: i16 = 223;
const GROUP: &str = "SD Syrup base";
const MANAGER: &str = "SD-approver";
const MANAGER_PIN: &str = "864223";
const LARGE_EXTRA: i32 = 3000;
const CLASSIC: i32 = 1000;
const PREMIUM: i32 = 2500;

struct Seed {
    org: Uuid,
    branch: Uuid,
    item: Uuid,
    regular: i32,
    classic: Uuid,
    premium: Uuid,
    addon: Uuid,
    addon_price: i32,
    has_cost: bool,
}

/// Seed the catalogue once per DB copy; later scenarios find it by the group.
async fn seed(fx: &Fixture) -> Seed {
    let branch = Uuid::parse_str(&fx.branch).unwrap();
    let org: Uuid = fx.db.query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch]).await.unwrap().get(0);
    fx.db
        .execute(
            "UPDATE branches SET tax_rate = 0.14, tax_inclusive = false WHERE id = $1",
            &[&branch],
        )
        .await
        .expect("branch tax");

    let existing = fx
        .db
        .query_opt(
            "SELECT a.menu_item_id, g.id FROM modifier_groups g
               JOIN menu_item_modifier_groups a ON a.group_id = g.id
              WHERE g.org_id = $1 AND g.name = $2",
            &[&org, &GROUP],
        )
        .await
        .unwrap();
    let (item, group): (Uuid, Uuid) = match existing {
        Some(r) => (r.get(0), r.get(1)),
        None => {
            // A real drink: one size, a recipe (costed when the copy has one),
            // and an optional, priced, non-swap add-on group already attached.
            let r = fx
                .db
                .query_one(
                    "SELECT i.id, z.id, z.price
                       FROM menu_items i
                       JOIN menu_item_sizes z ON z.menu_item_id = i.id AND z.is_active
                      WHERE i.org_id = $1 AND i.is_active AND i.deleted_at IS NULL AND z.price > 0
                        AND (SELECT count(*) FROM menu_item_sizes x WHERE x.menu_item_id = i.id) = 1
                        AND EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.owner_type = 'item_size' AND rl.owner_id = z.id)
                        AND EXISTS (SELECT 1 FROM menu_item_modifier_groups a
                                      JOIN modifier_groups g ON g.id = a.group_id AND g.is_active AND g.effect = 'adds'
                                           AND COALESCE(g.legacy_addon_type, '') NOT IN ('milk_type', 'coffee_type')
                                           AND COALESCE(a.min_override, g.min_selections) = 0 AND NOT g.is_required
                                      JOIN modifier_options o ON o.group_id = g.id AND o.is_active AND o.price > 0
                                           AND o.legacy_source = 'addon' AND o.id = ANY(a.included_option_ids)
                                     WHERE a.menu_item_id = i.id)
                      ORDER BY (SELECT count(*) FROM order_items oi WHERE oi.menu_item_id = i.id AND oi.line_cost > 0) DESC, i.name
                      LIMIT 1",
                    &[&org],
                )
                .await
                .expect("an item with one size, a recipe and optional add-ons");
            let (item, size, price): (Uuid, Uuid, i32) = (r.get(0), r.get(1), r.get(2));
            let (large, group) = (Uuid::new_v4(), Uuid::new_v4());
            fx.db.execute("UPDATE menu_item_sizes SET label = 'Regular' WHERE id = $1", &[&size]).await.expect("regular");
            fx.db
                .execute(
                    "INSERT INTO menu_item_sizes (id, menu_item_id, label, price, sort) VALUES ($1, $2, 'Large', $3, 1)",
                    &[&large, &item, &(price + LARGE_EXTRA)],
                )
                .await
                .expect("large");
            fx.db
                .execute(
                    "INSERT INTO recipe_lines (owner_type, owner_id, ingredient_id, quantity, unit, source, size_label)
                     SELECT owner_type, $1, ingredient_id, quantity, unit, source, size_label
                       FROM recipe_lines WHERE owner_type = 'item_size' AND owner_id = $2",
                    &[&large, &size],
                )
                .await
                .expect("large recipe");
            fx.db
                .execute(
                    "INSERT INTO modifier_groups (id, org_id, name, selection_type, min_selections, max_selections,
                                                  is_required, sort, legacy_addon_type, effect)
                     VALUES ($1, $2, $3, 'single', 1, 1, true, 9, 'syrup_base', 'adds')",
                    &[&group, &org, &GROUP],
                )
                .await
                .expect("group");
            fx.db
                .execute(
                    "INSERT INTO modifier_options (group_id, name, price, sort, is_default)
                     VALUES ($1, 'Classic', $2, 0, true), ($1, 'Premium', $3, 1, false)",
                    &[&group, &CLASSIC, &PREMIUM],
                )
                .await
                .expect("options");
            // Each pick is made of something that has a cost (the backend reads
            // an additive pick with no ingredient rows as "cost missing").
            fx.db
                .execute(
                    "INSERT INTO recipe_lines (owner_type, owner_id, ingredient_id, quantity, unit)
                     SELECT 'modifier_option', o.id, x.ingredient_id, 10, x.unit
                       FROM modifier_options o,
                            LATERAL (SELECT rl.ingredient_id, rl.unit FROM recipe_lines rl
                                       JOIN org_ingredients i ON i.id = rl.ingredient_id AND i.cost_per_unit > 0
                                      WHERE rl.owner_type = 'item_size' AND rl.owner_id = $2
                                      ORDER BY i.name LIMIT 1) x
                      WHERE o.group_id = $1",
                    &[&group, &size],
                )
                .await
                .expect("option recipes");
            fx.db
                .execute(
                    "INSERT INTO menu_item_modifier_groups (menu_item_id, group_id, sort) VALUES ($1, $2, 9)",
                    &[&item, &group],
                )
                .await
                .expect("attach");
            // A manager nobody else shares a PIN with, for the approval.
            let manager = Uuid::new_v4();
            fx.db
                .execute(
                    "INSERT INTO users (id, org_id, name, role, pin_hash)
                     VALUES ($1, $2, $3, 'branch_manager'::public.user_role, crypt($4, gen_salt('bf', 4)))",
                    &[&manager, &org, &MANAGER, &MANAGER_PIN],
                )
                .await
                .expect("manager");
            fx.db
                .execute(
                    "INSERT INTO user_branch_assignments (user_id, branch_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                    &[&manager, &branch],
                )
                .await
                .unwrap();
            (item, group)
        }
    };
    let regular: i32 = fx
        .db
        .query_one("SELECT price FROM menu_item_sizes WHERE menu_item_id = $1 AND label = 'Regular'", &[&item])
        .await
        .unwrap()
        .get(0);
    let opt = |name: &'static str| {
        let db = &fx.db;
        async move {
            db.query_one("SELECT id FROM modifier_options WHERE group_id = $1 AND name = $2", &[&group, &name])
                .await
                .unwrap()
                .get::<_, Uuid>(0)
        }
    };
    let a = fx
        .db
        .query_one(
            "SELECT o.id, COALESCE(bao.price_override, o.price)
               FROM menu_item_modifier_groups a
               JOIN modifier_groups g ON g.id = a.group_id AND g.is_active AND g.effect = 'adds' AND g.id <> $2
                    AND COALESCE(g.legacy_addon_type, '') NOT IN ('milk_type', 'coffee_type')
                    AND COALESCE(a.min_override, g.min_selections) = 0 AND NOT g.is_required
               JOIN modifier_options o ON o.group_id = g.id AND o.is_active AND o.price > 0
                    AND o.legacy_source = 'addon' AND o.id = ANY(a.included_option_ids)
               LEFT JOIN branch_addon_overrides bao ON bao.addon_item_id = o.id AND bao.branch_id = $3
              WHERE a.menu_item_id = $1 AND COALESCE(bao.is_available, true)
              ORDER BY (EXISTS (SELECT 1 FROM recipe_lines rl WHERE rl.owner_type = 'modifier_option' AND rl.owner_id = o.id)
                        AND NOT EXISTS (SELECT 1 FROM recipe_lines rl JOIN org_ingredients i ON i.id = rl.ingredient_id
                                         WHERE rl.owner_type = 'modifier_option' AND rl.owner_id = o.id
                                           AND i.cost_per_unit IS NULL)) DESC,
                       o.sort, o.name LIMIT 1",
            &[&item, &group, &branch],
        )
        .await
        .expect("an optional add-on");
    let has_cost: bool = fx
        .db
        .query_one(
            "SELECT EXISTS (SELECT 1 FROM order_items WHERE menu_item_id = $1 AND line_cost > 0)",
            &[&item],
        )
        .await
        .unwrap()
        .get(0);
    let s = Seed {
        org,
        branch,
        item,
        regular,
        classic: opt("Classic").await,
        premium: opt("Premium").await,
        addon: a.get(0),
        addon_price: a.get(1),
        has_cost,
    };
    eprintln!(
        "SEED item {item} Regular {} / Large {}, Classic {CLASSIC} (default) / Premium {PREMIUM}, add-on {} @ {}, costed before: {has_cost}",
        s.regular,
        s.regular + LARGE_EXTRA,
        s.addon,
        s.addon_price
    );
    s
}

/// The branch's pool: on, this item, `allowance` drinks a day.
async fn set_pool(fx: &Fixture, s: &Seed, allowance: i32) {
    fx.db.execute("DELETE FROM staff_pool_settings WHERE org_id = $1 AND branch_id = $2", &[&s.org, &s.branch]).await.unwrap();
    fx.db
        .execute(
            "INSERT INTO staff_pool_settings (org_id, branch_id, enabled, daily_allowance, eligible_item_ids)
             VALUES ($1, $2, true, $3, ARRAY[$4]::uuid[])",
            &[&s.org, &s.branch, &allowance, &s.item],
        )
        .await
        .expect("pool settings");
}

/// Drinks the SERVER has on this branch (the copy starts with none).
async fn used(fx: &Fixture, s: &Seed) -> i64 {
    fx.db
        .query_one("SELECT COALESCE(sum(quantity), 0)::bigint FROM staff_drinks WHERE branch_id = $1", &[&s.branch])
        .await
        .unwrap()
        .get(0)
}

async fn grant(fx: &Fixture, s: &Seed, teller: Uuid, effect: &str) {
    fx.db
        .execute(
            "INSERT INTO user_overrides (org_id, user_id, capability_id, effect, reason) VALUES ($1, $2, $3, $4, 'scenario')",
            &[&s.org, &teller, &CAP_ID, &effect],
        )
        .await
        .expect("override");
}

fn pay(method: &str, tendered: i64) -> CheckoutInput {
    CheckoutInput {
        payment_method_id: method.to_string(),
        amount_tendered_minor: tendered,
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

fn pick(id: Uuid) -> AddonSelection {
    AddonSelection { addon_item_id: id.to_string(), qty: 1 }
}

/// What the till stated for a marked sale, before it was charged.
#[derive(Debug)]
struct Rung {
    key: Uuid,
    drink: Uuid,
    comp: i64,
    charged: i64,
    subtotal: i64,
    tax: i64,
    total: i64,
}

/// Add one configured line, mark it, and charge it in cash.
async fn ring(
    core: &MadarCore,
    s: &Seed,
    size: &str,
    picks: Vec<AddonSelection>,
    qty: i64,
    note: &str,
    approval: Option<madar_core::approvals::ApprovalView>,
) -> Rung {
    let lines = core
        .cart_add_configured(None, s.item.to_string(), Some(size.into()), picks, vec![], qty, None)
        .expect("add");
    let key = lines.last().expect("a line").key.clone();
    let lines = core.mark_staff_drink(None, key, note.into(), approval).expect("mark");
    let mark = lines.iter().find_map(|l| l.staff_drink.clone()).expect("the line is marked");
    let totals = core.cart_totals(None).expect("totals");
    let cash = method(core, true).expect("cash");
    let sale = core.checkout(None, pay(&cash, totals.total_minor)).await.expect("checkout");
    assert_eq!(sale.total_minor, totals.total_minor, "the receipt states the cart's total");
    Rung {
        key: Uuid::parse_str(&sale.local_order_id).unwrap(),
        drink: Uuid::parse_str(&mark.id).unwrap(),
        comp: mark.comp_minor,
        charged: mark.charged_minor,
        subtotal: totals.subtotal_minor,
        tax: totals.tax_minor,
        total: totals.total_minor,
    }
}

struct ServerSale {
    order: Uuid,
    number: i32,
    subtotal: i32,
    tax: i32,
    total: i32,
    line_unit: i32,
    line_qty: i32,
    line_total: i32,
    line_comp: i32,
    line_drink: Option<Uuid>,
    line_cost: Option<i64>,
    cost_missing: Option<bool>,
    addons: Vec<(String, i32, i32, i32)>,
    paid: i64,
    flags: Vec<String>,
}

async fn server_sale(fx: &Fixture, key: Uuid) -> ServerSale {
    let o = fx
        .db
        .query_one(
            "SELECT id, order_number, subtotal, tax_amount, total_amount FROM orders WHERE idempotency_key = $1",
            &[&key],
        )
        .await
        .expect("the sale is on the server");
    let order: Uuid = o.get(0);
    let l = fx
        .db
        .query_one(
            "SELECT id, unit_price, quantity, line_total, staff_comp_minor, staff_drink_id, line_cost, cost_missing
               FROM order_items WHERE order_id = $1",
            &[&order],
        )
        .await
        .expect("one line");
    let line: Uuid = l.get(0);
    let addons = fx
        .db
        .query(
            "SELECT addon_name, unit_price, line_total, staff_comp_minor FROM order_item_addons
              WHERE order_item_id = $1 ORDER BY addon_name",
            &[&line],
        )
        .await
        .unwrap()
        .iter()
        .map(|r| (r.get(0), r.get(1), r.get(2), r.get(3)))
        .collect();
    let paid: i64 = fx
        .db
        .query_one("SELECT COALESCE(sum(amount), 0)::bigint FROM order_payments WHERE order_id = $1", &[&order])
        .await
        .unwrap()
        .get(0);
    let flags = fx
        .db
        .query("SELECT capability FROM authz_replay_flags WHERE subject_id = $1 ORDER BY capability", &[&order])
        .await
        .unwrap()
        .iter()
        .map(|r| r.get(0))
        .collect();
    let s = ServerSale {
        order,
        number: o.get(1),
        subtotal: o.get(2),
        tax: o.get(3),
        total: o.get(4),
        line_unit: l.get(1),
        line_qty: l.get(2),
        line_total: l.get(3),
        line_comp: l.get(4),
        line_drink: l.get(5),
        line_cost: l.get(6),
        cost_missing: l.get(7),
        addons,
        paid,
        flags,
    };
    eprintln!(
        "SERVER order #{} subtotal {} tax {} total {} paid {} | line {}x{} line_total {} staff_comp {} cost {:?} (missing {:?}) | addons {:?} | flags {:?}",
        s.number, s.subtotal, s.tax, s.total, s.paid, s.line_unit, s.line_qty, s.line_total, s.line_comp,
        s.line_cost, s.cost_missing, s.addons, s.flags
    );
    s
}

struct ServerDrink {
    order: Option<Uuid>,
    quantity: i32,
    comp: Option<i32>,
    extras: Option<i32>,
    reported: Option<i32>,
    overspent: bool,
    overspent_on_replay: bool,
    cost: Option<i32>,
}

async fn server_drink(fx: &Fixture, id: Uuid) -> ServerDrink {
    let r = fx
        .db
        .query_one(
            "SELECT order_id, quantity, comp_minor, extras_minor, comp_minor_reported, overspent,
                    overspent_on_replay, cost_minor, note FROM staff_drinks WHERE id = $1",
            &[&id],
        )
        .await
        .expect("the pool row is on the server");
    let d = ServerDrink {
        order: r.get(0),
        quantity: r.get(1),
        comp: r.get(2),
        extras: r.get(3),
        reported: r.get(4),
        overspent: r.get(5),
        overspent_on_replay: r.get(6),
        cost: r.get(7),
    };
    eprintln!(
        "SERVER drink qty {} comp {:?} extras {:?} reported {:?} overspent {} (on replay {}) cost {:?} note {:?}",
        d.quantity, d.comp, d.extras, d.reported, d.overspent, d.overspent_on_replay, d.cost, r.get::<_, String>(8)
    );
    d
}

/// The till's bill is the server's, to the piastre, and nothing was flagged.
fn assert_same_bill(r: &Rung, sv: &ServerSale) {
    assert_eq!((sv.subtotal as i64, sv.tax as i64, sv.total as i64), (r.subtotal, r.tax, r.total), "till vs server bill");
    assert_eq!(sv.paid, r.total, "what was paid is the total");
    assert_eq!(sv.line_comp as i64, r.comp, "till vs server comp");
    assert!(sv.flags.is_empty(), "nothing flagged: {:?}", sv.flags);
}

struct Till {
    fx: Fixture,
    s: Seed,
    core: std::sync::Arc<MadarCore>,
    proxy: Proxy,
    db_path: String,
}

/// A granted teller on an open till, with `headroom` drinks left on the pool.
async fn till(tag: &str, headroom: i32) -> Till {
    let fx = fixture(2).await;
    let s = seed(&fx).await;
    let before = used(&fx, &s).await as i32;
    set_pool(&fx, &s, before + headroom).await;
    grant(&fx, &s, fx.tellers[0].0, "allow").await;
    grant(&fx, &s, fx.tellers[1].0, "allow").await;
    let proxy = Proxy::start(&fx.base).await;
    let db_path = temp_db(tag);
    let core = core_at(&proxy.base, &db_path, &fx.tellers[0].1, &fx.branch).await;
    core.open_till(10_000, Some(format!("staff drink {tag}"))).await.expect("open");
    assert!(core.can(CAP.into()), "the granted teller holds the act");
    let today = core.staff_pool_today().expect("pool");
    assert!(today.on, "the pool reached the till: {today:?}");
    assert_eq!(today.pool.allowance, before + headroom);
    Till { fx, s, core, proxy, db_path }
}

/// Rewrite the queued sale's payload while the cable is out.
fn tamper(db_path: &str, edit: impl FnOnce(&mut serde_json::Value)) {
    let conn = rusqlite::Connection::open(db_path).expect("open core db");
    let (seq, payload): (i64, String) = conn
        .query_row(
            "SELECT seq, payload FROM outbox WHERE op_type = 'create_order' AND status <> 'acked' ORDER BY seq DESC LIMIT 1",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .expect("a queued sale");
    let mut v: serde_json::Value = serde_json::from_str(&payload).unwrap();
    edit(&mut v);
    conn.execute("UPDATE outbox SET payload = ?1 WHERE seq = ?2", rusqlite::params![v.to_string(), seq]).unwrap();
}

/// [`settle`] for the scenario that leaves the link idle while a manager types
/// a PIN: the harness proxy half-closes a keep-alive socket the backend timed
/// out, the next send dies on it, and the core backs a transport blip off for
/// up to a minute WITHOUT counting an attempt (by design). So this waits that
/// gate out, asking again the way a teller's sync button would, and says what
/// is stuck when a queue really does not drain.
async fn drain(core: &MadarCore, max_secs: u64) {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(max_secs);
    loop {
        let st = core.sync_now().await.expect("sync");
        assert_eq!(st.dead_outbox, 0, "nothing dead-letters: {:?}", core.list_outbox());
        if st.pending_outbox == 0 {
            return;
        }
        assert!(std::time::Instant::now() < deadline, "did not drain: {:?}\n{st:?}", core.list_outbox());
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    }
}

#[tokio::test]
#[ignore]
async fn s1_base_configuration_is_free_and_still_a_normal_costed_sale() {
    let t = till("sd1", 10).await;
    let before = used(&t.fx, &t.s).await;
    let normal = (t.s.regular + CLASSIC) as i64;
    let r = ring(&t.core, &t.s, "Regular", vec![pick(t.s.classic)], 1, "for Sara", None).await;
    assert_eq!((r.comp, r.charged, r.subtotal, r.tax, r.total), (normal, 0, 0, 0, 0), "{r:?}");
    settle(&t.core, 90).await;

    let sv = server_sale(&t.fx, r.key).await;
    assert!(sv.number > 0, "a normal order number");
    assert_eq!(sv.line_unit, t.s.regular, "the line keeps its normal price");
    assert_eq!(sv.line_comp as i64, normal, "the comp is the full normal price");
    assert_eq!(sv.line_total, 0);
    assert_eq!(sv.addons, vec![("Classic".to_string(), CLASSIC, 0, CLASSIC)], "the default pick is comped");
    assert_eq!(sv.line_drink, Some(r.drink));
    assert_same_bill(&r, &sv);
    assert_eq!(sv.total, 0);

    let d = server_drink(&t.fx, r.drink).await;
    assert_eq!(d.order, Some(sv.order));
    assert_eq!((d.comp, d.extras, d.reported), (Some(normal as i32), Some(0), Some(normal as i32)));
    assert!(!d.overspent && !d.overspent_on_replay);
    assert_eq!(used(&t.fx, &t.s).await, before + 1, "one off the allowance");

    // The drink was made: its cost is on the line and on the pool row.
    if sv.cost_missing == Some(false) || t.s.has_cost {
        assert!(sv.line_cost.unwrap_or(0) > 0, "the line's cost is recorded");
        assert!(d.cost.unwrap_or(0) > 0, "the pool row's cost is recorded");
    } else {
        eprintln!("NOTE: this copy cannot cost the item (cost_missing {:?}); cost asserts skipped", sv.cost_missing);
    }
    // The till adopted the server's figures for its own row.
    let mine = t.core.staff_drinks_today().unwrap().into_iter().find(|x| x.id == r.drink.to_string()).expect("local row");
    assert_eq!((mine.comp_minor, mine.extras_minor, mine.queued), (Some(normal), Some(0), false));
}

#[tokio::test]
#[ignore]
async fn s2_a_bigger_size_and_an_addon_pay_and_only_they_are_taxed() {
    let t = till("sd2", 10).await;
    let before = used(&t.fx, &t.s).await;
    let comp = (t.s.regular + CLASSIC) as i64;
    let charged = (LARGE_EXTRA + t.s.addon_price) as i64;
    let tax = (charged * 14 + 50) / 100;
    let r = ring(&t.core, &t.s, "Large", vec![pick(t.s.classic), pick(t.s.addon)], 1, "for Omar", None).await;
    assert_eq!((r.comp, r.charged, r.subtotal, r.tax, r.total), (comp, charged, charged, tax, charged + tax), "{r:?}");
    settle(&t.core, 90).await;

    let sv = server_sale(&t.fx, r.key).await;
    assert_eq!(sv.line_unit, t.s.regular + LARGE_EXTRA);
    assert_eq!(sv.line_total, LARGE_EXTRA, "the size pays its difference");
    assert_eq!(sv.line_comp as i64, comp);
    let addon = sv.addons.iter().find(|a| a.0 != "Classic").expect("the add-on row");
    assert_eq!((addon.1, addon.2, addon.3), (t.s.addon_price, t.s.addon_price, 0), "an optional add-on is never free");
    assert_same_bill(&r, &sv);
    assert!(!sv.flags.iter().any(|f| f.ends_with(":comp_mismatch")));

    let d = server_drink(&t.fx, r.drink).await;
    assert_eq!((d.comp, d.extras, d.reported), (Some(comp as i32), Some(charged as i32), Some(comp as i32)));
    assert_eq!(used(&t.fx, &t.s).await, before + 1);
}

#[tokio::test]
#[ignore]
async fn s3_a_required_groups_default_is_free_and_a_pricier_pick_pays_the_difference() {
    let t = till("sd3", 10).await;
    let comp = (t.s.regular + CLASSIC) as i64;
    let charged = (PREMIUM - CLASSIC) as i64;
    let tax = (charged * 14 + 50) / 100;
    let r = ring(&t.core, &t.s, "Regular", vec![pick(t.s.premium)], 1, "for Laila", None).await;
    assert_eq!((r.comp, r.charged, r.total), (comp, charged, charged + tax), "{r:?}");
    settle(&t.core, 90).await;

    let sv = server_sale(&t.fx, r.key).await;
    assert_eq!(sv.line_total, 0, "the cheapest size is free");
    assert_eq!(
        sv.addons,
        vec![("Premium".to_string(), PREMIUM, PREMIUM - CLASSIC, CLASSIC)],
        "the pricier pick pays its difference over the default"
    );
    assert_same_bill(&r, &sv);
    let d = server_drink(&t.fx, r.drink).await;
    assert_eq!((d.comp, d.extras), (Some(comp as i32), Some(charged as i32)));
}

#[tokio::test]
#[ignore]
async fn s4_two_units_are_two_drinks_and_twice_the_comp() {
    let t = till("sd4", 10).await;
    let before = used(&t.fx, &t.s).await;
    let comp = 2 * (t.s.regular + CLASSIC) as i64;
    let r = ring(&t.core, &t.s, "Regular", vec![pick(t.s.classic)], 2, "for the openers", None).await;
    assert_eq!((r.comp, r.charged, r.total), (comp, 0, 0), "{r:?}");
    settle(&t.core, 90).await;

    let sv = server_sale(&t.fx, r.key).await;
    assert_eq!((sv.line_qty, sv.line_comp as i64, sv.total), (2, comp, 0));
    assert_same_bill(&r, &sv);
    let d = server_drink(&t.fx, r.drink).await;
    assert_eq!((d.quantity, d.comp, d.extras), (2, Some(comp as i32), Some(0)));
    assert_eq!(used(&t.fx, &t.s).await, before + 2, "two off the allowance");
    assert_eq!(t.core.staff_pool_today().unwrap().pool.used as i64, before + 2, "the till counts two as well");
}

#[tokio::test]
#[ignore]
async fn s5_an_overspend_lands_flagged_when_only_the_server_knew() {
    let t = till("sd5", 2).await;
    let comp = (t.s.regular + CLASSIC) as i64;
    let first = ring(&t.core, &t.s, "Regular", vec![pick(t.s.classic)], 1, "inside the allowance", None).await;
    settle(&t.core, 90).await;
    assert!(!server_drink(&t.fx, first.drink).await.overspent);

    // The cable is out, and another till spends the last drink of the day.
    t.proxy.offline();
    t.fx.db
        .execute(
            "INSERT INTO staff_drinks (id, org_id, branch_id, menu_item_id, item_name, quantity, note, business_date, recorded_at)
             SELECT gen_random_uuid(), org_id, branch_id, menu_item_id, item_name, 1, 'the other till', business_date, now()
               FROM staff_drinks WHERE id = $1",
            &[&first.drink],
        )
        .await
        .expect("the other till's drink");
    let surprise = ring(&t.core, &t.s, "Regular", vec![pick(t.s.classic)], 1, "the till thinks one is left", None).await;
    t.proxy.online();
    t.core.refresh_connectivity().await;
    settle(&t.core, 120).await;
    let sv = server_sale(&t.fx, surprise.key).await;
    assert_eq!((sv.total, sv.line_comp as i64), (0, comp), "the sale landed, comped");
    let d = server_drink(&t.fx, surprise.drink).await;
    assert!(d.overspent && d.overspent_on_replay, "the server's count made it an overspend");
    assert_eq!(sv.flags, vec![format!("{CAP}:overspent")]);

    // Now the till knows too (its pull brought the other till's drink): it says
    // so itself, the sale still lands, and there is nothing to be surprised by.
    let pool = t.core.staff_pool_today().unwrap().pool;
    assert_eq!(pool.used as i64, used(&t.fx, &t.s).await, "the till's count is the server's");
    assert_eq!((pool.remaining, pool.over), (0, 1), "{pool:?}");
    let known = ring(&t.core, &t.s, "Regular", vec![pick(t.s.classic)], 1, "over, and the till said so", None).await;
    settle(&t.core, 90).await;
    let sv = server_sale(&t.fx, known.key).await;
    assert_eq!((sv.total, sv.line_comp as i64), (0, comp), "an overspend is never refused");
    let d = server_drink(&t.fx, known.drink).await;
    assert!(d.overspent && !d.overspent_on_replay);
    assert!(sv.flags.is_empty(), "both sides agree it is over: {:?}", sv.flags);
}

#[tokio::test]
#[ignore]
async fn s6_a_second_device_reads_the_drink_and_the_same_count() {
    let t = till("sd6", 10).await;
    let comp = (t.s.regular + CLASSIC) as i64;
    let charged = t.s.addon_price as i64;
    let r = ring(&t.core, &t.s, "Regular", vec![pick(t.s.classic), pick(t.s.addon)], 1, "for the other till to see", None).await;
    settle(&t.core, 90).await;
    server_sale(&t.fx, r.key).await;

    let b = core_at(&t.fx.base, &temp_db("sd6_b"), &t.fx.tellers[1].1, &t.fx.branch).await;
    settle(&b, 90).await;
    let seen = b.staff_drinks_today().unwrap().into_iter().find(|x| x.id == r.drink.to_string()).expect("device B has the drink");
    eprintln!("DEVICE B {seen:?}");
    assert_eq!((seen.comp_minor, seen.extras_minor, seen.quantity), (Some(comp), Some(charged), 1));
    let server = used(&t.fx, &t.s).await;
    assert_eq!(b.staff_pool_today().unwrap().pool.used as i64, server, "device B's count");
    assert_eq!(t.core.staff_pool_today().unwrap().pool.used as i64, server, "device A's count");
}

#[tokio::test]
#[ignore]
async fn s7_a_wrong_comp_from_the_till_lands_and_the_server_keeps_both_figures() {
    let t = till("sd7", 10).await;
    let comp = (t.s.regular + CLASSIC) as i64;
    settle(&t.core, 90).await;
    t.proxy.offline();
    let r = ring(&t.core, &t.s, "Regular", vec![pick(t.s.classic)], 1, "a till with a wrong rule", None).await;
    assert_eq!(r.comp, comp);
    // The till states it comped 6000 less than the rule gives, and charged it:
    // a coherent bill (subtotal, 14% tax, total, the cash line), a wrong comp.
    let (wrong, sub) = (comp - 6000, 6000i64);
    let (tax, total) = (840i64, 6840i64);
    tamper(&t.db_path, |p| {
        let req = &mut p["request"];
        assert_eq!(req["items"][0]["staff_drink"]["comp_minor"], serde_json::json!(comp), "{req}");
        req["items"][0]["staff_drink"]["comp_minor"] = wrong.into();
        req["subtotal"] = sub.into();
        req["tax_amount"] = tax.into();
        req["total_amount"] = total.into();
        req["amount_tendered"] = total.into();
        if let Some(splits) = req["payment_splits"].as_array_mut() {
            for s in splits.iter_mut() {
                s["amount"] = total.into();
            }
        }
        eprintln!("TAMPERED request {req}");
    });
    t.proxy.online();
    t.core.refresh_connectivity().await;
    settle(&t.core, 120).await;

    let sv = server_sale(&t.fx, r.key).await;
    let d = server_drink(&t.fx, r.drink).await;
    assert_eq!(d.comp, Some(comp as i32), "the server's own verdict");
    assert_eq!(d.reported, Some(wrong as i32), "the till's figure, beside it");
    assert!(sv.flags.contains(&format!("{CAP}:comp_mismatch")), "{:?}", sv.flags);
    assert_eq!(sv.total as i64, total, "the sale happened: the till's money stands");
    assert_eq!(sv.line_comp as i64, wrong, "what came off the stored money is the till's comp");
}

#[tokio::test]
#[ignore]
async fn s8_without_the_act_an_approval_rides_clean_and_its_absence_is_flagged() {
    let fx = fixture(1).await;
    let s = seed(&fx).await;
    let before = used(&fx, &s).await as i32;
    set_pool(&fx, &s, before + 10).await;
    let (teller_id, teller) = fx.tellers[0].clone();
    grant(&fx, &s, teller_id, "deny").await;
    fx.db
        .execute(
            "INSERT INTO org_capability_policy (org_id, capability_id, ask_manager) VALUES ($1, $2, true)
             ON CONFLICT (org_id, capability_id) DO UPDATE SET ask_manager = true",
            &[&s.org, &CAP_ID],
        )
        .await
        .unwrap();
    let proxy = Proxy::start(&fx.base).await;
    let db_path = temp_db("sd8");
    {
        let m = signed_in_pin(&proxy.base, &db_path, MANAGER, &fx.branch, MANAGER_PIN).await;
        m.logout(false).ok();
    }
    let core = core_at(&proxy.base, &db_path, &teller, &fx.branch).await;
    core.open_till(10_000, Some("staff drink sd8".into())).await.expect("open");
    assert!(!core.can(CAP.into()));
    assert_eq!(core.staff_drink_access().outcome, "needs_approval");

    // Unapproved, the till itself refuses the mark.
    let lines = core
        .cart_add_configured(None, s.item.to_string(), Some("Regular".into()), vec![pick(s.classic)], vec![], 1, None)
        .unwrap();
    assert!(core.mark_staff_drink(None, lines[0].key.clone(), "no approval".into(), None).is_err());
    core.cart_clear(None).unwrap();

    // Approved: the approval rides the sale, is verified, nothing is flagged.
    let approval = core.approve_staff_drink(MANAGER_PIN.into()).expect("the manager approves");
    let ok = ring(&core, &s, "Regular", vec![pick(s.classic)], 1, "approved by the manager", Some(approval.clone())).await;
    drain(&core, 150).await;
    let sv = server_sale(&fx, ok.key).await;
    assert!(sv.flags.is_empty(), "an approved staff drink is clean: {:?}", sv.flags);
    let row = fx
        .db
        .query_one("SELECT verified, capability FROM approvals WHERE id = $1", &[&Uuid::parse_str(&approval.id).unwrap()])
        .await
        .expect("the approval is on record");
    assert!(row.get::<_, bool>(0));
    assert_eq!(row.get::<_, String>(1), CAP);

    // The same sale with the approval cut out of the envelope: accepted, flagged.
    let approval = core.approve_staff_drink(MANAGER_PIN.into()).expect("the manager approves again");
    drain(&core, 150).await;
    proxy.offline();
    let bare = ring(&core, &s, "Regular", vec![pick(s.classic)], 1, "the approval never arrives", Some(approval)).await;
    tamper(&db_path, |p| {
        assert!(p.get("approval").is_some_and(|a| !a.is_null()), "the queued sale carries its approval: {p}");
        p.as_object_mut().unwrap().remove("approval");
    });
    proxy.online();
    core.refresh_connectivity().await;
    drain(&core, 150).await;
    let sv = server_sale(&fx, bare.key).await;
    assert_eq!(sv.total, 0, "the sale landed all the same");
    assert!(sv.flags.contains(&CAP.to_string()), "no act and no approval is flagged: {:?}", sv.flags);
    assert_eq!(server_drink(&fx, bare.drink).await.order, Some(sv.order));
}

#[tokio::test]
#[ignore]
async fn s9_the_record_only_op_of_an_old_till_still_works() {
    let t = till("sd9", 10).await;
    let before = used(&t.fx, &t.s).await;
    let rec = t
        .core
        .record_staff_drink(
            StaffDrinkInput {
                menu_item_id: t.s.item.to_string(),
                size_label: Some("Regular".into()),
                quantity: 1,
                note: "recorded the old way".into(),
                order_id: None,
                line_key: None,
            },
            None,
        )
        .await
        .expect("record");
    settle(&t.core, 90).await;
    let d = server_drink(&t.fx, Uuid::parse_str(&rec.id).unwrap()).await;
    assert_eq!((d.order, d.comp, d.extras, d.reported), (None, None, None, None), "a record-only drink carries no money");
    assert_eq!(used(&t.fx, &t.s).await, before + 1);
    let flags: i64 = t
        .fx
        .db
        .query_one("SELECT count(*) FROM authz_replay_flags WHERE subject_id = $1", &[&Uuid::parse_str(&rec.id).unwrap()])
        .await
        .unwrap()
        .get(0);
    assert_eq!(flags, 0);
}
