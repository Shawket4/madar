//! Discounts (phase 6): the REAL `MadarCore` against the REAL backend.
//!
//! ```sh
//! MADAR_OB_TESTS=discounts_backend tool/offline_b_backend.sh
//! ```
//!
//! A teller whose role caps a hand-typed discount at 5.00:
//! * within the cap the discount is allowed and the sale lands clean, attributed;
//! * over the cap the core asks for a manager; the teller cannot approve it; a
//!   manager's PIN approves it; the sale lands with the approval, verified, and
//!   the server raises no flag.

mod common;

use common::*;
use madar_core::checkout::CheckoutInput;

fn input(method_id: &str) -> CheckoutInput {
    CheckoutInput {
        payment_method_id: method_id.to_string(),
        amount_tendered_minor: 10_000_000,
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

async fn drained(core: &madar_core::MadarCore) {
    for _ in 0..30 {
        if core.sync_status().pending_outbox == 0 {
            break;
        }
        let _ = core.sync_now().await;
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    }
    let left = core.list_outbox().unwrap_or_default();
    assert!(left.is_empty(), "the sale landed: {left:?}");
}

#[tokio::test]
#[ignore]
async fn a_tellers_capped_discount_needs_a_manager_over_the_cap_and_lands_clean() {
    let fx = fixture(1).await;
    let (teller_id, teller) = fx.tellers[0].clone();
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    let org: uuid::Uuid = fx
        .db
        .query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch])
        .await
        .unwrap()
        .get(0);
    let manager_id = uuid::Uuid::new_v4();
    let manager = format!("DISC-approver-{}", &manager_id.simple().to_string()[..6]);
    fx.db
        .execute(
            "INSERT INTO users (id, org_id, name, role, pin_hash)
             VALUES ($1, $2, $3, 'branch_manager'::public.user_role, crypt('864210', gen_salt('bf', 4)))",
            &[&manager_id, &org, &manager],
        )
        .await
        .unwrap();
    fx.db
        .execute(
            "INSERT INTO user_branch_assignments (user_id, branch_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
            &[&manager_id, &branch],
        )
        .await
        .unwrap();
    // The teller may take up to 5.00 off by hand (an allow override's limits replace the role's).
    let manual_amount: i16 = 205;
    fx.db
        .execute(
            "INSERT INTO user_overrides (org_id, user_id, capability_id, effect, limits, reason)
             VALUES ($1, $2, $3, 'allow', '{\"max_amount\": 500}'::jsonb, 'scenario')",
            &[&org, &teller_id, &manual_amount],
        )
        .await
        .unwrap();

    let db = temp_db("discounts");
    {
        let core = signed_in_pin(&fx.base, &db, &manager, &fx.branch, "864210").await;
        core.logout(false).ok();
    }
    let core = core_at(&fx.base, &db, &teller, &fx.branch).await;
    core.open_till(10_000, None).await.expect("open");
    let cash = method(&core, true).expect("cash");
    let item = core
        .list_menu_items()
        .expect("items")
        .into_iter()
        .find(|i| i.base_price_minor > 1_000)
        .expect("an item over 10.00");
    let add = || core.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor).expect("add");

    // Within the cap: allowed, applied, attributed, clean.
    add();
    let d = core.decide_discount(None, "manual_amount".into(), None, Some(500), None);
    assert_eq!(d.outcome, "allow", "{d:?}");
    core.apply_discount(None, "manual_amount".into(), None, Some(500), None, None).expect("apply");
    let clean = core.checkout(None, input(&cash)).await.expect("checkout");
    drained(&core).await;

    // Over the cap: needs a manager; not the teller; the manager approves.
    add();
    let d = core.decide_discount(None, "manual_amount".into(), None, Some(800), None);
    assert_eq!(d.outcome, "needs_approval", "{d:?}");
    assert!(
        core.apply_discount(None, "manual_amount".into(), None, Some(800), None, None).is_err(),
        "no approval, no discount"
    );
    assert!(core
        .approve_discount("1234".into(), None, "manual_amount".into(), None, Some(800), None)
        .is_err());
    let approval = core
        .approve_discount("864210".into(), None, "manual_amount".into(), None, Some(800), None)
        .expect("the manager approves");
    core.apply_discount(None, "manual_amount".into(), None, Some(800), None, Some(approval.clone()))
        .expect("apply with approval");
    assert_eq!(core.cart_discount(None).unwrap().approved_by_name.as_deref(), Some(manager.as_str()));
    let approved = core.checkout(None, input(&cash)).await.expect("checkout");
    drained(&core).await;

    let rows = fx
        .db
        .query(
            "SELECT idempotency_key, discount_kind, discount_amount, discount_applied_by, discount_approval_id
               FROM orders WHERE idempotency_key = ANY($1)",
            &[&vec![
                uuid::Uuid::parse_str(&clean.local_order_id).unwrap(),
                uuid::Uuid::parse_str(&approved.local_order_id).unwrap(),
            ]],
        )
        .await
        .unwrap();
    assert_eq!(rows.len(), 2);
    for r in &rows {
        assert_eq!(r.get::<_, Option<String>>(1).as_deref(), Some("manual_amount"));
        assert_eq!(r.get::<_, Option<uuid::Uuid>>(3), Some(teller_id));
        let is_approved = r.get::<_, uuid::Uuid>(0).to_string() == approved.local_order_id;
        assert_eq!(r.get::<_, i32>(2), if is_approved { 800 } else { 500 });
        assert_eq!(
            r.get::<_, Option<uuid::Uuid>>(4),
            is_approved.then(|| uuid::Uuid::parse_str(&approval.id).unwrap())
        );
    }
    let verified: bool = fx
        .db
        .query_one("SELECT verified FROM approvals WHERE id = $1", &[&uuid::Uuid::parse_str(&approval.id).unwrap()])
        .await
        .expect("the approval is on record")
        .get(0);
    assert!(verified);
    let flags: i64 = fx
        .db
        .query_one("SELECT count(*) FROM authz_replay_flags WHERE author_id = $1", &[&teller_id])
        .await
        .unwrap()
        .get(0);
    assert_eq!(flags, 0, "neither sale is flagged");
}

/// A DISCOUNT ON A TABLE'S BILL, and a preset switched off mid-service —
/// the REAL core against the REAL backend.
///
/// ```sh
/// MADAR_OB_TESTS=discounts_backend tool/offline_b_backend.sh
/// ```
///
/// A bill was the one way round the discount gate: the settle route applied a
/// discount with no capability check and no cap. Here a teller capped at 5.00:
/// * a bill discount over the cap needs a manager, and the core refuses to
///   queue the settle without one;
/// * with the manager's PIN the bill lands, attributed, with the approval
///   verified on the order and no flag raised;
/// * a queued sale whose PRESET was switched off while the till was offline
///   lands anyway, with the amount AS RUNG, flagged for the owner.
#[tokio::test]
#[ignore]
async fn a_table_bill_needs_a_manager_over_the_cap_and_a_dead_preset_still_lands() {
    let fx = fixture(1).await;
    let (teller_id, teller) = fx.tellers[0].clone();
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    let org: uuid::Uuid = fx
        .db
        .query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch])
        .await
        .unwrap()
        .get(0);
    let manager_id = uuid::Uuid::new_v4();
    let manager = format!("BILL-approver-{}", &manager_id.simple().to_string()[..6]);
    fx.db
        .execute(
            "INSERT INTO users (id, org_id, name, role, pin_hash)
             VALUES ($1, $2, $3, 'branch_manager'::public.user_role, crypt('975310', gen_salt('bf', 4)))",
            &[&manager_id, &org, &manager],
        )
        .await
        .unwrap();
    fx.db
        .execute(
            "INSERT INTO user_branch_assignments (user_id, branch_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
            &[&manager_id, &branch],
        )
        .await
        .unwrap();
    // 5.00 off by hand is this teller's ceiling — bills included, now.
    let manual_amount: i16 = 205;
    fx.db
        .execute(
            "INSERT INTO user_overrides (org_id, user_id, capability_id, effect, limits, reason)
             VALUES ($1, $2, $3, 'allow', '{\"max_amount\": 500}'::jsonb, 'scenario')",
            &[&org, &teller_id, &manual_amount],
        )
        .await
        .unwrap();

    // Through a proxy, so the till can really be taken offline for the queued
    // sale whose preset is switched off underneath it.
    let proxy = Proxy::start(&fx.base).await;
    let db = temp_db("billdisc");
    {
        let core = signed_in_pin(&proxy.base, &db, &manager, &fx.branch, "975310").await;
        core.logout(false).ok();
    }
    let core = core_at(&proxy.base, &db, &teller, &fx.branch).await;
    core.open_till(10_000, None).await.expect("open");
    let cash = method(&core, true).expect("cash");
    let item = core
        .list_menu_items()
        .expect("items")
        .into_iter()
        .find(|i| i.base_price_minor > 1_000)
        .expect("an item over 10.00");

    // ── A table's bill, discounted over the cap ──────────────────────────
    core.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor)
        .expect("add");
    let fired = core
        .fire_ticket(None, Some("table 9".into()), None, None, None)
        .await
        .expect("fire");
    settle(&core, 60).await;
    // The board again, so the bill's own subtotal is on this device.
    let _ = core.list_open_tickets().await;

    let over = || {
        core.decide_bill_discount(
            fired.ticket_id.clone(),
            None,
            Some("fixed".into()),
            Some(800.0),
        )
    };
    assert_eq!(over().outcome, "needs_approval", "{:?}", over());
    // The core will not queue a settle whose discount nobody approved.
    let refused = core
        .settle_ticket(
            fired.ticket_id.clone(), core.current_till().unwrap().unwrap().id,
            cash.clone(), Some(10_000_000), None, None,
            None, Some("fixed".into()), Some(800.0),
            None, vec![], vec![], false, None,
        )
        .await;
    assert!(refused.is_err(), "over the cap, no approval, no settle");
    // The teller cannot approve their own act.
    assert!(core
        .approve_bill_discount("1234".into(), fired.ticket_id.clone(), None, Some("fixed".into()), Some(800.0))
        .is_err());
    let approval = core
        .approve_bill_discount("975310".into(), fired.ticket_id.clone(), None, Some("fixed".into()), Some(800.0))
        .expect("the manager approves");
    core.settle_ticket(
        fired.ticket_id.clone(), core.current_till().unwrap().unwrap().id,
        cash.clone(), Some(10_000_000), None, None,
        None, Some("fixed".into()), Some(800.0),
        None, vec![], vec![], false, Some(approval.clone()),
    )
    .await
    .expect("the approved bill settles");
    drained(&core).await;

    // The bill's local id was remapped to the server's at replay, so the paid
    // order is found by its author — and it MUST be a bill, not a counter sale.
    let row = fx
        .db
        .query_one(
            "SELECT discount_kind, discount_amount, discount_applied_by, discount_approval_id
               FROM orders
              WHERE discount_applied_by = $1 AND open_ticket_id IS NOT NULL
              ORDER BY created_at DESC LIMIT 1",
            &[&teller_id],
        )
        .await
        .expect("the bill became a paid order");
    assert_eq!(row.get::<_, Option<String>>(0).as_deref(), Some("manual_amount"));
    assert_eq!(row.get::<_, i32>(1), 800, "the money as the drawer took it");
    assert_eq!(row.get::<_, Option<uuid::Uuid>>(2), Some(teller_id));
    assert_eq!(
        row.get::<_, Option<uuid::Uuid>>(3),
        Some(uuid::Uuid::parse_str(&approval.id).unwrap()),
        "the approval rides onto the settled order"
    );
    let verified: bool = fx
        .db
        .query_one(
            "SELECT verified FROM approvals WHERE id = $1",
            &[&uuid::Uuid::parse_str(&approval.id).unwrap()],
        )
        .await
        .expect("on record")
        .get(0);
    assert!(verified);
    let flags: i64 = fx
        .db
        .query_one("SELECT count(*) FROM authz_replay_flags WHERE author_id = $1", &[&teller_id])
        .await
        .unwrap()
        .get(0);
    assert_eq!(flags, 0, "an approved bill is clean");

    // ── A preset switched off while the till was offline ─────────────────
    let preset = uuid::Uuid::new_v4();
    fx.db
        .execute(
            "INSERT INTO discounts (id, org_id, name, type, value, is_active)
             VALUES ($1, $2, 'Scenario staff', 'percentage', 0.25, true)",
            &[&preset, &org],
        )
        .await
        .unwrap();
    // The till learns about it, then goes OFFLINE and rings a sale under it.
    core.refresh_catalog().await.expect("the preset reaches the till");
    assert!(
        core.list_discounts().unwrap().iter().any(|d| d.id == preset.to_string()),
        "the till knows the rule it is about to ring under"
    );
    proxy.offline();
    for _ in 0..3 {
        core.refresh_connectivity().await;
    }
    core.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor)
        .expect("add");
    core.apply_discount(None, "preset".into(), Some(preset.to_string()), None, None, None)
        .expect("the preset applies");
    let rung = core.cart_discount(None).expect("discount").off_minor;
    assert!(rung > 0, "the preset really took something off");
    let sale = core.checkout(None, input(&cash)).await.expect("checkout");

    // The owner switches the rule off while the sale is still in the outbox.
    fx.db
        .execute("UPDATE discounts SET is_active = false WHERE id = $1", &[&preset])
        .await
        .unwrap();
    proxy.online();
    for _ in 0..3 {
        core.refresh_connectivity().await;
    }
    drained(&core).await;

    let key = uuid::Uuid::parse_str(&sale.local_order_id).unwrap();
    let landed = fx
        .db
        .query_one(
            "SELECT discount_amount FROM orders WHERE idempotency_key = $1",
            &[&key],
        )
        .await
        .expect("the sale landed — a dead rule never loses a sale that happened");
    assert_eq!(
        landed.get::<_, i32>(0) as i64,
        rung,
        "the amount AS RUNG, not recomputed from a rule that is gone"
    );
    let dead: i64 = fx
        .db
        .query_one(
            "SELECT count(*) FROM authz_replay_flags
              WHERE author_id = $1 AND capability = 'orders.discount.preset:inactive'",
            &[&teller_id],
        )
        .await
        .unwrap()
        .get(0);
    assert_eq!(dead, 1, "the owner is told which rule is dead");
}
