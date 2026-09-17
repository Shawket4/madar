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
//! * B resumes A's parked order (the core decides; B holds `orders.create`
//!   without an `own` limit, so no manager is needed), opens a till and
//!   settles it, all offline;
//! * back online, the replayed sale is B's (teller, drawer) and records A as
//!   the person who started it, read back through `GET /orders/{id}`.

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

    // Badr signs in online once on this device, so the offline bundle the
    // device fetches next carries his PIN verifier.
    {
        let core = core_at(&proxy.base, &db, &badr, &fx.branch).await;
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
    assert_eq!(decision.outcome, "allow", "{decision:?}");
    let resumed = core.switch_to_draft(None, regular, None, None).expect("resume");
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

    // The order as the API reads it names both people.
    let http = reqwest::Client::new();
    let login: serde_json::Value = http
        .post(format!("{}/auth/login", fx.base))
        .json(&serde_json::json!({ "name": badr, "pin": "1234", "branch_id": fx.branch }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let token = login["token"].as_str().expect("a token").to_string();
    let body: serde_json::Value = http
        .get(format!("{}/orders/{order_id}", fx.base))
        .bearer_auth(token)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(body["teller_name"], serde_json::json!(badr), "{body}");
    assert_eq!(body["started_by_name"], serde_json::json!(ali), "{body}");

    // Ali's second cart is still on the strip for whoever picks it up.
    assert_eq!(core.list_drafts().unwrap().len(), 1);
}
