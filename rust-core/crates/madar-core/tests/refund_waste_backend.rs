//! Voids and refunds move stock differently: the REAL `MadarCore` against the
//! REAL backend, through an offline backlog.
//!
//! Ignored by `cargo test`. Run through the offline-B harness:
//!
//! ```sh
//! MADAR_OB_TESTS=refund_waste_backend tool/offline_b_backend.sh
//! ```
//!
//! What it proves, after the queue drains through `/sync/replay`:
//! * a VOID always restores the sale's stock — even sent the way a 0.7.8 till
//!   sends it (`restore_inventory: false`) — and logs no waste;
//! * a REFUND never restores stock: the deduction stands and the refunded
//!   share (one of two units) is logged as waste with reason `refund`, linked
//!   to the refund;
//! * a money-only partial refund moves no stock at all.

mod common;

use common::*;

#[tokio::test]
#[ignore]
async fn after_replay_a_void_restocks_and_a_refund_is_waste() {
    let fx = fixture(1).await;
    let teller = fx.tellers[0].1.clone();
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    let org: uuid::Uuid = fx
        .db
        .query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch])
        .await
        .unwrap()
        .get(0);
    let tag = &uuid::Uuid::new_v4().simple().to_string()[..6];
    let proxy = Proxy::start(&fx.base).await;
    let db = temp_db("refund_waste");
    let core = core_at(&proxy.base, &db, &teller, &fx.branch).await;

    // The item `sell` rings gets 10 g of a fresh ingredient per unit, on every
    // size it could resolve to; 1 kg on the shelf.
    let item = core
        .list_menu_items()
        .expect("items")
        .into_iter()
        .find(|i| i.base_price_minor > 0)
        .expect("a priced item");
    let item_id = uuid::Uuid::parse_str(&item.id).unwrap();
    let rice: uuid::Uuid = fx
        .db
        .query_one(
            "INSERT INTO org_ingredients (org_id, name, unit, category_id, cost_per_unit)
             VALUES ($1, $2, 'g', ingredient_category_id($1, 'general'), 1)
             RETURNING id",
            &[&org, &format!("RW-rice-{tag}")],
        )
        .await
        .expect("ingredient")
        .get(0);
    fx.db
        .execute(
            "INSERT INTO menu_item_recipes (menu_item_id, org_ingredient_id, quantity_used, size_label, ingredient_name, ingredient_unit)
             SELECT $1, $2, 10, l, 'RW rice', 'g' FROM (
               SELECT size_label AS l FROM menu_item_recipes WHERE menu_item_id = $1
               UNION SELECT label FROM menu_item_sizes WHERE menu_item_id = $1
               UNION SELECT 'one_size') s",
            &[&item_id, &rice],
        )
        .await
        .expect("recipe");
    fx.db
        .execute(
            "INSERT INTO inventory_movements (branch_id, org_ingredient_id, type, quantity, source_type)
             VALUES ($1, $2, 'purchase_in', 1000, 'scenario')",
            &[&branch, &rice],
        )
        .await
        .expect("opening stock");
    let on_hand = || async {
        fx.db
            .query_one(
                "SELECT on_hand::float8 FROM branch_stock WHERE branch_id = $1 AND org_ingredient_id = $2",
                &[&branch, &rice],
            )
            .await
            .unwrap()
            .get::<_, f64>(0)
    };

    core.open_till(10_000, Some("refund waste".into())).await.expect("open");
    let cash = method(&core, true).expect("a cash method");
    // Three sales of 2 units each, online: 60 g deducted.
    for _ in 0..3 {
        sell(&core, 2, &cash, 1_000_000).await;
    }
    settle(&core, 120).await;
    assert_eq!(on_hand().await, 940.0, "three sales of two took 60 g");
    let synced: Vec<_> = core
        .list_till_orders()
        .await
        .expect("orders")
        .into_iter()
        .filter(|o| !o.queued)
        .collect();
    assert!(synced.len() >= 3);
    let (voided, refunded, money_only) = (&synced[0], &synced[1], &synced[2]);
    // The refund sheet reads the lines while online (cached for offline).
    let lines = core.refundable_lines(refunded.id.clone()).await.expect("lines");
    let line = lines.iter().find(|l| l.sold_qty == 2).expect("the two-unit line");
    let _ = core.refundable_lines(money_only.id.clone()).await;

    // Offline: void one sale the way an old till does, refund one unit of
    // another, and give some money back on a third with no items.
    proxy.offline();
    for _ in 0..3 {
        core.refresh_connectivity().await;
    }
    core.void_order(voided.id.clone(), "customer_changed_mind".into(), None, false)
        .await
        .expect("void queues");
    core.refund_order_lines_approved(
        refunded.id.clone(),
        line.unit_share_minor,
        "cash".into(),
        "quality".into(),
        None,
        vec![madar_core::orders::RefundLinePick { order_item_id: line.order_item_id.clone(), qty: 1 }],
        None,
    )
    .await
    .expect("line refund queues");
    core.refund_order(money_only.id.clone(), 1, "cash".into(), "overcharged".into(), None)
        .await
        .expect("money refund queues");

    proxy.online();
    core.refresh_connectivity().await;
    settle(&core, 120).await;

    // The void put its 20 g back; the refunds put nothing back.
    assert_eq!(on_hand().await, 960.0, "void restored, refunds did not");
    let void_waste: i64 = fx
        .db
        .query_one(
            "SELECT count(*) FROM inventory_movements WHERE source_id = $1::text::uuid AND type = 'waste'",
            &[&voided.id],
        )
        .await
        .unwrap()
        .get(0);
    assert_eq!(void_waste, 0, "a void logs no waste");
    let refund_waste: Vec<(f64, String)> = fx
        .db
        .query(
            "SELECT m.quantity::float8, r.order_id::text FROM inventory_movements m
               JOIN order_refunds r ON r.id = m.source_id
              WHERE m.source_type = 'refund' AND m.type = 'waste' AND m.reason = 'refund'
                AND m.org_ingredient_id = $1",
            &[&rice],
        )
        .await
        .unwrap()
        .into_iter()
        .map(|r| (r.get(0), r.get(1)))
        .collect();
    assert_eq!(
        refund_waste,
        vec![(-10.0, refunded.id.clone())],
        "one refunded unit is 10 g of waste, linked to its refund; the money-only refund wastes nothing"
    );
    let _ = std::fs::remove_file(&db);
}
