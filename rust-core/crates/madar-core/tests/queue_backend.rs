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
//! * B, a teller without `orders.held.resume_others`, resumes A's parked
//!   order with a branch manager's PIN approval on the till, opens a till and
//!   settles it, all offline;
//! * back online, the replayed sale is B's (teller, drawer) and records A as
//!   the person who started it, with the manager's approval verified and no
//!   authorization flag.

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
    assert_eq!(decision.outcome, "needs_approval", "{decision:?}");
    assert!(core.switch_to_draft(None, regular.clone(), None, None).is_err(), "not without a manager");
    let approval = core
        .approve_draft_act("5678".into(), "resume".into(), regular.clone())
        .expect("the manager approves offline");
    let resumed = core
        .switch_to_draft_approved(None, regular, None, None, Some(approval.clone()))
        .expect("resume");
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
    let approved = fx
        .db
        .query_one("SELECT verified, approver_user_id FROM approvals WHERE id = $1", &[&uuid::Uuid::parse_str(&approval.id).unwrap()])
        .await
        .expect("the approval is on record");
    assert!(approved.get::<_, bool>(0), "verified at replay");
    assert_eq!(approved.get::<_, uuid::Uuid>(1), mona_id);
    let flags: i64 = fx
        .db
        .query_one("SELECT count(*) FROM authz_replay_flags WHERE author_id = $1", &[&badr_id])
        .await
        .unwrap()
        .get(0);
    assert_eq!(flags, 0, "an approved resume is not flagged");

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
}
