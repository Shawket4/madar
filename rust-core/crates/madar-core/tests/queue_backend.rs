//! Deferred feature 5, keep the previous teller's queue: the REAL `MadarCore`
//! against the REAL backend.
//!
//! Ignored by `cargo test`. Run through the offline-B harness:
//!
//! ```sh
//! MADAR_OB_TESTS=queue_backend tool/offline_b_backend.sh
//! ```
//!
//! What it proves, on one device:
//! * teller A parks an order and leaves another cart in hand; the device goes
//!   offline and A signs out; teller B unlocks with a PIN, offline;
//! * B sees both of A's orders, marked as A's, and an empty cart in hand;
//! * B, an ordinary teller holding nothing special, resumes A's parked order
//!   with NO prompt and NO manager PIN (owner decision 2026-09-19: a held
//!   order is shared state on the till), opens a till and settles it, all
//!   offline;
//! * back online, the replayed sale is B's (teller, drawer) and records A as
//!   the person who started it, and carries NO authorization flag — a resume
//!   is not an act that needs a grant.
//!
//! And, the other way round: a teller whose OWN order is still parked when a
//! manager uses the till in between resumes and settles it with no approval
//! asked for anywhere, and the sale records nobody but them.

mod common;

use common::*;
use madar_core::checkout::CheckoutInput;
use madar_core::session::{LoginMode, LoginRequest};

#[tokio::test]
#[ignore]
async fn a_held_order_started_by_one_teller_is_settled_by_the_next_and_names_both() {
    let fx = fixture(2).await;
    let (ali_id, ali) = fx.tellers[0].clone();
    let (badr_id, badr) = fx.tellers[1].clone();
    let proxy = Proxy::start(&fx.base).await;
    let db = temp_db("queue");

    // A branch manager with their own PIN (a shared PIN could not name one
    // person offline).
    let mona_id = uuid::Uuid::new_v4();
    let mona = format!("OB-mgr-{}", &mona_id.simple().to_string()[..6]);
    let branch_uuid = uuid::Uuid::parse_str(&fx.branch).unwrap();
    fx.db
        .execute(
            "INSERT INTO users (id, org_id, name, role, pin_hash)
             SELECT $1, org_id, $2, 'branch_manager'::public.user_role, crypt('5678', gen_salt('bf', 4))
               FROM branches WHERE id = $3",
            &[&mona_id, &mona, &branch_uuid],
        )
        .await
        .expect("insert manager");
    fx.db
        .execute(
            "INSERT INTO user_branch_assignments (user_id, branch_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
            &[&mona_id, &branch_uuid],
        )
        .await
        .expect("assign manager");

    // Badr and the manager sign in online once on this device, so the offline
    // bundle the device fetches next carries their PIN verifiers.
    {
        let core = core_at(&proxy.base, &db, &badr, &fx.branch).await;
        core.logout(false).ok();
    }
    {
        let core = signed_in_pin(&proxy.base, &db, &mona, &fx.branch, "5678").await;
        core.logout(false).ok();
    }

    // Ali: parks one order, leaves a second cart in hand.
    let core = core_at(&proxy.base, &db, &ali, &fx.branch).await;
    let item = core
        .list_menu_items()
        .expect("items")
        .into_iter()
        .find(|i| i.base_price_minor > 0)
        .expect("a priced item");
    core.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor)
        .unwrap();
    core.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor)
        .unwrap();
    core.hold_cart(None, "Ali's regular".into(), None, None).unwrap();
    core.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor)
        .unwrap();

    // The switch happens offline: nothing in it needs the server.
    proxy.offline();
    for _ in 0..3 {
        core.refresh_connectivity().await;
    }
    core.logout(false).unwrap();
    core.unlock_offline(badr.clone(), "1234".into(), fx.branch.clone())
        .expect("Badr unlocks offline");

    assert!(core.cart_lines(None).unwrap().is_empty(), "Badr starts empty-handed");
    let drafts = core.list_drafts().unwrap();
    assert_eq!(drafts.len(), 2, "nothing of Ali's was discarded: {drafts:?}");
    assert!(drafts.iter().all(|d| d.by_other && d.created_by_name.as_deref() == Some(ali.as_str())));
    let regular = drafts.iter().find(|d| d.name == "Ali's regular").expect("the parked order").id.clone();

    let decision = core.decide_draft_act("resume".into(), regular.clone());
    assert_eq!(decision.outcome, "allow", "someone else's order is not gated: {decision:?}");
    // And there is no approval to mint for it any more, even with the
    // manager's real PIN.
    assert!(
        core.approve_draft_act("5678".into(), "resume".into(), regular.clone()).is_err(),
        "a resume asks for no approval"
    );
    let resumed = core
        .switch_to_draft(None, regular.clone(), None, None)
        .expect("Badr resumes Ali's order with no manager anywhere near the till");
    assert_eq!(resumed.lines.iter().map(|l| l.qty).sum::<i64>(), 2);

    core.open_till(5_000, Some("queue scenario".into())).await.expect("open offline");
    let cash = method(&core, true).expect("a cash method");
    let receipt = core
        .checkout(
            None,
            CheckoutInput {
                payment_method_id: cash,
                amount_tendered_minor: 1_000_000,
                tip_minor: 0,
                tip_payment_method_id: None,
                customer_name: None,
                notes: None,
                splits: vec![],
                loyalty_customer_id: None,
                dine_in: false,
                customer_id: None,
                loyalty_redemptions: vec![],
            },
        )
        .await
        .expect("settle offline");
    assert!(receipt.queued_offline);
    // The host marks the resumed held order completed after the sale.
    core.complete_draft(regular, None).expect("complete the held order");

    // Back online; Badr signs in for real and the queue drains.
    proxy.online();
    core.refresh_connectivity().await;
    core.sign_in(LoginRequest {
        mode: LoginMode::Pin,
        name: Some(badr.clone()),
        pin: Some("1234".into()),
        branch_id: Some(fx.branch.clone()),
        email: None,
        password: None,
        org_id: None,
    })
    .await
    .expect("Badr signs in online");
    settle(&core, 180).await;

    let key = uuid::Uuid::parse_str(&receipt.local_order_id).unwrap();
    let row = fx
        .db
        .query_one("SELECT id, teller_id, started_by FROM orders WHERE idempotency_key = $1", &[&key])
        .await
        .expect("the sale replayed");
    let (order_id, teller, started): (uuid::Uuid, uuid::Uuid, Option<uuid::Uuid>) =
        (row.get(0), row.get(1), row.get(2));
    assert_eq!(teller, badr_id, "settled by Badr: his drawer");
    assert_eq!(started, Some(ali_id), "started by Ali");
    let flags: i64 = fx
        .db
        .query_one("SELECT count(*) FROM authz_replay_flags WHERE author_id = $1", &[&badr_id])
        .await
        .unwrap()
        .get(0);
    assert_eq!(flags, 0, "a resume is never flagged: it needs no grant");

    // Both names, as the order read joins them (GET /orders/{id} is
    // covered by the backend's replay test).
    let names = fx
        .db
        .query_one(
            "SELECT u.name, sb.name FROM orders o JOIN users u ON u.id = o.teller_id
               LEFT JOIN users sb ON sb.id = o.started_by WHERE o.id = $1",
            &[&order_id],
        )
        .await
        .unwrap();
    assert_eq!(names.get::<_, String>(0), badr);
    assert_eq!(names.get::<_, Option<String>>(1), Some(ali.clone()));

    // Ali's second cart is still on the strip for whoever picks it up.
    assert_eq!(core.list_drafts().unwrap().len(), 1);

    // Badr closes his till: the warning lists Ali's order; he closes anyway.
    let preflight = core.close_preflight();
    assert_eq!(preflight.held_count, 1, "{preflight:?}");
    assert_eq!(preflight.held[0].started_by_name.as_deref(), Some(ali.as_str()));
    assert!(core.close_till_confirmed(0, None, vec![], false).await.is_err(), "not without choosing");
    let till_id = core.current_till().unwrap().expect("open").id;
    core.close_till_confirmed(0, None, vec![], true).await.expect("close anyway");
    settle(&core, 180).await;
    assert_eq!(core.list_drafts().unwrap().len(), 1, "Ali's order survives the close");
    let row = fx
        .db
        .query_one(
            "SELECT status::text, held_orders_left_open, held_orders_left_open_total FROM tills WHERE id = $1",
            &[&uuid::Uuid::parse_str(&till_id).unwrap()],
        )
        .await
        .expect("the till");
    assert_eq!(row.get::<_, String>(0), "closed");
    assert_eq!(row.get::<_, Option<i32>>(1), Some(1), "the close shows 1 left open");
    assert_eq!(row.get::<_, Option<i32>>(2), Some(item.base_price_minor as i32));
}

/// The owner's report: "when a teller signs in after a manager they shouldn't
/// need to enter their password to finish their held order."
///
/// A teller parks an order, a BRANCH MANAGER signs in on the same till and
/// out again, and the teller comes back. Their own order must resume and
/// settle with no approval asked for anywhere — and the replayed sale carries
/// no `started_by` and no approval, because there was only ever one person.
#[tokio::test]
#[ignore]
async fn a_teller_resumes_their_own_held_order_after_a_manager_used_the_till() {
    let fx = fixture(1).await;
    let (ali_id, ali) = fx.tellers[0].clone();
    let proxy = Proxy::start(&fx.base).await;
    let db = temp_db("queue_own");

    // A branch manager with their own PIN, who will use the till in between.
    let mona_id = uuid::Uuid::new_v4();
    let mona = format!("OB-mgr-{}", &mona_id.simple().to_string()[..6]);
    let branch_uuid = uuid::Uuid::parse_str(&fx.branch).unwrap();
    fx.db
        .execute(
            "INSERT INTO users (id, org_id, name, role, pin_hash)
             SELECT $1, org_id, $2, 'branch_manager'::public.user_role, crypt('5678', gen_salt('bf', 4))
               FROM branches WHERE id = $3",
            &[&mona_id, &mona, &branch_uuid],
        )
        .await
        .expect("insert manager");
    fx.db
        .execute(
            "INSERT INTO user_branch_assignments (user_id, branch_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
            &[&mona_id, &branch_uuid],
        )
        .await
        .expect("assign manager");

    // Ali parks an order.
    let core = core_at(&proxy.base, &db, &ali, &fx.branch).await;
    let item = core
        .list_menu_items()
        .expect("items")
        .into_iter()
        .find(|i| i.base_price_minor > 0)
        .expect("a priced item");
    core.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor)
        .unwrap();
    core.hold_cart(None, "Ali's tab".into(), None, None).unwrap();
    core.logout(false).unwrap();

    // The manager takes the till, then leaves it.
    core.sign_in(LoginRequest {
        mode: LoginMode::Pin,
        name: Some(mona.clone()),
        pin: Some("5678".into()),
        branch_id: Some(fx.branch.clone()),
        email: None,
        password: None,
        org_id: None,
    })
    .await
    .expect("the manager signs in on the till");
    core.logout(false).unwrap();

    // Ali comes back to finish his order.
    core.sign_in(LoginRequest {
        mode: LoginMode::Pin,
        name: Some(ali.clone()),
        pin: Some("1234".into()),
        branch_id: Some(fx.branch.clone()),
        email: None,
        password: None,
        org_id: None,
    })
    .await
    .expect("Ali signs back in");

    let drafts = core.list_drafts().unwrap();
    assert_eq!(drafts.len(), 1, "his order is still on the strip: {drafts:?}");
    assert!(!drafts[0].by_other, "his own chip wears no lock: {drafts:?}");
    assert_eq!(drafts[0].created_by_name.as_deref(), Some(ali.as_str()));
    let tab = drafts[0].id.clone();

    let decision = core.decide_draft_act("resume".into(), tab.clone());
    assert_eq!(decision.outcome, "allow", "no prompt on his own order: {decision:?}");
    let resumed = core
        .switch_to_draft(None, tab.clone(), None, None)
        .expect("resumes with no approval at all");
    assert_eq!(resumed.lines.iter().map(|l| l.qty).sum::<i64>(), 1);

    core.open_till(5_000, Some("own held order scenario".into()))
        .await
        .expect("open");
    let cash = method(&core, true).expect("a cash method");
    let receipt = core
        .checkout(
            None,
            CheckoutInput {
                payment_method_id: cash,
                amount_tendered_minor: 1_000_000,
                tip_minor: 0,
                tip_payment_method_id: None,
                customer_name: None,
                notes: None,
                splits: vec![],
                loyalty_customer_id: None,
                dine_in: false,
                customer_id: None,
                loyalty_redemptions: vec![],
            },
        )
        .await
        .expect("settle");
    core.complete_draft(tab, None).expect("complete the held order");
    settle(&core, 180).await;

    let key = uuid::Uuid::parse_str(&receipt.local_order_id).unwrap();
    let row = fx
        .db
        .query_one(
            "SELECT id, teller_id, started_by FROM orders WHERE idempotency_key = $1",
            &[&key],
        )
        .await
        .expect("the sale replayed");
    let (order_id, teller, started): (uuid::Uuid, uuid::Uuid, Option<uuid::Uuid>) =
        (row.get(0), row.get(1), row.get(2));
    assert_eq!(teller, ali_id, "Ali's sale");
    assert_eq!(started, None, "one person: nothing extra recorded on the sale");
    let approvals: i64 = fx
        .db
        .query_one(
            "SELECT count(*) FROM approvals WHERE order_id = $1",
            &[&order_id],
        )
        .await
        .map(|r| r.get(0))
        .unwrap_or(0);
    assert_eq!(approvals, 0, "no manager was ever asked");
    let flags: i64 = fx
        .db
        .query_one(
            "SELECT count(*) FROM authz_replay_flags WHERE author_id = $1",
            &[&ali_id],
        )
        .await
        .unwrap()
        .get(0);
    assert_eq!(flags, 0, "his own order is not flagged at replay");

    assert!(core.list_drafts().unwrap().is_empty(), "the strip is clear");
}

/// Tables are nobody's (queue rule 4a): a waiter fires a table's bill on one
/// device, a teller on ANOTHER device adds a round and settles it, with no
/// per-person gate, and a switch on the waiter's device leaves nothing
/// person-scoped behind. Online; the LAN relay is not part of this harness.
#[tokio::test]
#[ignore]
async fn a_table_bill_is_shared_between_devices_and_people() {
    let fx = fixture(1).await;
    let (_, teller) = fx.tellers[0].clone();
    let branch_uuid = uuid::Uuid::parse_str(&fx.branch).unwrap();
    let mut waiters = Vec::new();
    for pin in ["3456", "4567"] {
        let id = uuid::Uuid::new_v4();
        let name = format!("OB-w-{}", &id.simple().to_string()[..6]);
        fx.db
            .execute(
                "INSERT INTO users (id, org_id, name, role, pin_hash)
                 SELECT $1, org_id, $2, 'waiter'::public.user_role, crypt($3, gen_salt('bf', 4)) FROM branches WHERE id = $4",
                &[&id, &name, &pin, &branch_uuid],
            )
            .await
            .expect("insert waiter");
        fx.db
            .execute("INSERT INTO user_branch_assignments (user_id, branch_id) VALUES ($1, $2) ON CONFLICT DO NOTHING", &[&id, &branch_uuid])
            .await
            .unwrap();
        waiters.push((name, pin));
    }
    let (pa, pb) = (Proxy::start(&fx.base).await, Proxy::start(&fx.base).await);
    let (da, dbp) = (temp_db("tbl-a"), temp_db("tbl-b"));

    // Device A: waiter 1 fires the table's bill, then starts another round
    // and signs out without sending it.
    let a = signed_in_pin(&pa.base, &da, &waiters[0].0, &fx.branch, waiters[0].1).await;
    a.refresh_connectivity().await;
    a.refresh_catalog().await.expect("catalog");
    a.sync_full().await.expect("snapshot");
    let item = a.list_menu_items().unwrap().into_iter().find(|i| i.base_price_minor > 0).unwrap();
    a.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor).unwrap();
    let ticket = a.fire_ticket(None, Some("Table 4".into()), None, Some(2), None).await.expect("fire").ticket_id;
    settle(&a, 120).await;
    a.cart_add(Some("t4-local".into()), item.id.clone(), item.name.clone(), item.base_price_minor).unwrap();
    a.logout(false).unwrap();
    assert!(a.list_drafts().unwrap_or_default().is_empty(), "no person-scoped copy of the table");
    assert!(a.cart_lines(Some("t4-local".into())).unwrap().is_empty());

    // Device A, waiter 2: sees the shared bill.
    let a2 = signed_in_pin(&pa.base, &da, &waiters[1].0, &fx.branch, waiters[1].1).await;
    a2.sync_full().await.expect("snapshot");
    assert!(a2.list_open_tickets().await.unwrap().iter().any(|t| t.id == ticket || t.customer_name.as_deref() == Some("Table 4")));

    // Device B, a teller: adds a round to the same bill and settles it.
    let b = core_at(&pb.base, &dbp, &teller, &fx.branch).await;
    let till = b.open_till(0, Some("tables".into())).await.unwrap().till.unwrap().id;
    let bill = b
        .list_open_tickets()
        .await
        .unwrap()
        .into_iter()
        .find(|t| t.customer_name.as_deref() == Some("Table 4"))
        .expect("the bill is on the teller's device");
    b.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor).unwrap();
    b.add_ticket_round(None, bill.id.clone()).await.expect("a round on someone else's table");
    settle(&b, 120).await;
    let cash = method(&b, true).expect("cash");
    b.settle_ticket(bill.id.clone(), till, cash, Some(1_000_000), None, None, None, None, None, None, vec![], vec![], false, None)
        .await
        .expect("settle someone else's table");
    settle(&b, 180).await;
    let status: String = fx
        .db
        .query_one("SELECT status::text FROM open_tickets WHERE id = $1", &[&uuid::Uuid::parse_str(&bill.id).unwrap()])
        .await
        .expect("the bill")
        .get(0);
    assert_eq!(status, "settled");
}
