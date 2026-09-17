//! Waste from the teller app: the REAL `MadarCore` against the REAL backend.
//!
//! Ignored by `cargo test`. Run through the offline-B harness:
//!
//! ```sh
//! MADAR_OB_TESTS=waste_backend tool/offline_b_backend.sh
//! ```
//!
//! What it proves:
//! * the ingredient catalog (with its cost) reaches the till through the feed,
//!   and a teller granted `inventory.waste.record` is offered the screen;
//! * OFFLINE, a waste within the teller's `max_value` limit records at once,
//!   and one over it needs a manager, who approves with their PIN on the device;
//! * reconnected, both drain through `/sync/replay`, `branch_stock.on_hand`
//!   moves by exactly what was wasted, the approval is on record, and nothing
//!   is flagged.

mod common;

use common::*;

#[tokio::test]
#[ignore]
async fn an_offline_waste_drains_and_moves_the_branch_stock() {
    let fx = fixture(1).await;
    let (teller_id, teller) = fx.tellers[0].clone();
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    let org: uuid::Uuid = fx
        .db
        .query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch])
        .await
        .unwrap()
        .get(0);
    let tag = &uuid::Uuid::new_v4().simple().to_string()[..6];

    // An ingredient at 2 piastres a gram, 1 kg on the shelf.
    let beans: uuid::Uuid = fx
        .db
        .query_one(
            "INSERT INTO org_ingredients (org_id, name, unit, category_id, cost_per_unit)
             VALUES ($1, $2, 'g', ingredient_category_id($1, 'general'), 2)
             RETURNING id",
            &[&org, &format!("WASTE-beans-{tag}")],
        )
        .await
        .expect("ingredient")
        .get(0);
    fx.db
        .execute(
            "INSERT INTO inventory_movements (branch_id, org_ingredient_id, type, quantity, source_type)
             VALUES ($1, $2, 'purchase_in', 1000, 'scenario')",
            &[&branch, &beans],
        )
        .await
        .expect("opening stock");

    // The owner lets this teller record waste up to 5.00; more needs a manager.
    fx.db
        .execute(
            "INSERT INTO user_overrides (org_id, user_id, capability_id, effect, limits, reason)
             VALUES ($1, $2, 49, 'allow', '{\"max_value\": 500}'::jsonb, 'scenario')",
            &[&org, &teller_id],
        )
        .await
        .expect("grant waste");

    // A manager with a PIN nobody else in the fixture shares.
    let manager_id = uuid::Uuid::new_v4();
    let manager = format!("WASTE-manager-{tag}");
    fx.db
        .execute(
            "INSERT INTO users (id, org_id, name, role, pin_hash)
             VALUES ($1, $2, $3, 'branch_manager'::public.user_role, crypt('864209', gen_salt('bf', 4)))",
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

    let proxy = Proxy::start(&fx.base).await;
    let db = temp_db("waste");
    {
        let core = signed_in_pin(&proxy.base, &db, &manager, &fx.branch, "864209").await;
        core.logout(false).ok();
    }
    let core = core_at(&proxy.base, &db, &teller, &fx.branch).await;
    assert!(core.can_record_waste(), "the teller is offered the waste screen");
    let found = core.waste_ingredients(format!("WASTE-beans-{tag}")).expect("ingredients");
    assert_eq!(found.len(), 1, "{found:?}");
    assert_eq!(found[0].units, vec!["g", "kg"]);

    // Offline.
    proxy.offline();
    for _ in 0..3 {
        core.refresh_connectivity().await;
    }
    let input = |qty: f64, unit: &str| madar_core::waste::WasteInput {
        subject_kind: "ingredient".into(),
        subject_id: beans.to_string(),
        size_label: None,
        quantity: qty,
        unit: unit.into(),
        reason: "spoiled".into(),
        note: Some("scenario".into()),
    };

    // 100 g = 2.00: within the limit.
    let small = core.preview_waste(input(100.0, "g")).expect("preview");
    assert_eq!(small.value_minor, Some(200));
    assert_eq!(small.decision.outcome, "allow", "{small:?}");
    core.record_waste(input(100.0, "g"), None).expect("records offline");

    // 0.5 kg = 10.00: over it. Refused without an approval, then approved.
    let big = core.preview_waste(input(0.5, "kg")).expect("preview");
    assert_eq!(big.value_minor, Some(1000));
    assert_eq!(big.decision.outcome, "needs_approval", "{big:?}");
    assert!(core.record_waste(input(0.5, "kg"), None).is_err(), "not without a manager");
    assert!(
        core.approve_waste("1234".into(), input(0.5, "kg")).is_err(),
        "the teller cannot approve their own waste"
    );
    let approval = core
        .approve_waste("864209".into(), input(0.5, "kg"))
        .expect("the manager approves offline");
    assert_eq!(approval.value_minor, Some(1000));
    core.record_waste(input(0.5, "kg"), Some(approval.clone())).expect("records with approval");
    assert_eq!(core.sync_status().pending_outbox, 2, "both wait in the queue");

    // Reconnect and drain.
    proxy.online();
    core.refresh_connectivity().await;
    settle(&core, 120).await;

    let on_hand: f64 = fx
        .db
        .query_one(
            "SELECT on_hand::float8 FROM branch_stock WHERE branch_id = $1 AND org_ingredient_id = $2",
            &[&branch, &beans],
        )
        .await
        .unwrap()
        .get(0);
    assert_eq!(on_hand, 400.0, "1000 g - 100 g - 500 g");

    let wastes = fx
        .db
        .query(
            "SELECT source, recorded_by, value_minor, approval_id, device_id IS NOT NULL
               FROM waste_events WHERE branch_id = $1 AND org_ingredient_id = $2 ORDER BY value_minor",
            &[&branch, &beans],
        )
        .await
        .unwrap();
    assert_eq!(wastes.len(), 2);
    for w in &wastes {
        assert_eq!(w.get::<_, String>(0), "pos");
        assert_eq!(w.get::<_, Option<uuid::Uuid>>(1), Some(teller_id));
        assert!(w.get::<_, bool>(4), "the device is on record");
    }
    assert_eq!(wastes[0].get::<_, Option<i64>>(2), Some(200));
    assert_eq!(wastes[0].get::<_, Option<uuid::Uuid>>(3), None);
    let approval_id = uuid::Uuid::parse_str(&approval.id).unwrap();
    assert_eq!(wastes[1].get::<_, Option<uuid::Uuid>>(3), Some(approval_id));

    let verified: bool = fx
        .db
        .query_one("SELECT verified FROM approvals WHERE id = $1", &[&approval_id])
        .await
        .expect("the approval is on record")
        .get(0);
    assert!(verified);
    let flagged: i64 = fx
        .db
        .query_one(
            "SELECT count(*) FROM authz_replay_flags WHERE author_id = $1 AND op = 'RecordWaste'",
            &[&teller_id],
        )
        .await
        .unwrap()
        .get(0);
    assert_eq!(flagged, 0, "within the limit, or approved: nothing to flag");
}
