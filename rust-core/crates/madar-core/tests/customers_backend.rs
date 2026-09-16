//! Manual customers: the REAL `MadarCore` against the REAL backend.
//!
//! Ignored by `cargo test`. Run through the offline-B harness:
//!
//! ```sh
//! MADAR_OB_TESTS=customers_backend tool/offline_b_backend.sh
//! ```
//!
//! What it proves:
//! * a customer the dashboard made reaches the till through `/sync/pull` and is
//!   found by name and by the last digits of the phone; merged and erased
//!   customers never reach it;
//! * a customer added on the till is usable at once, drains through the queue
//!   and lands on the server under the till's branch;
//! * a sale naming that customer is stored against it on the server;
//! * a teller holds `customers.attach` but never `customers.erase`.

mod common;

use common::*;

#[tokio::test]
#[ignore]
async fn a_till_finds_adds_and_attaches_customers() {
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
    let digits: String = format!("100{:07}", u32::from_str_radix(tag, 16).unwrap() % 10_000_000);
    let live = format!("CUST-live-{tag}");
    let live_id: uuid::Uuid = fx
        .db
        .query_one(
            "INSERT INTO customers (org_id, name, phone, phone_key) VALUES ($1, $2, $3, $4) RETURNING id",
            &[&org, &live, &format!("+20 {digits}"), &digits],
        )
        .await
        .expect("dashboard customer")
        .get(0);
    fx.db
        .execute(
            "INSERT INTO customers (org_id, name, merged_into, merged_at) VALUES ($1, $2, $3, now())",
            &[&org, &format!("CUST-merged-{tag}"), &live_id],
        )
        .await
        .unwrap();
    fx.db
        .execute(
            "INSERT INTO customers (org_id, name, erased_at) VALUES ($1, $2, now())",
            &[&org, &format!("CUST-erased-{tag}")],
        )
        .await
        .unwrap();

    let db = temp_db("customers");
    let core = core_at(&fx.base, &db, &teller, &fx.branch).await;
    assert!(core.can("customers.attach".into()), "a teller attaches customers");
    assert!(!core.can("customers.erase".into()), "a teller never erases");

    let found = core.search_customers(live.clone()).expect("search by name");
    assert_eq!(found.len(), 1, "{found:?}");
    assert_eq!(found[0].id, live_id.to_string());
    let last4 = &digits[digits.len() - 4..];
    assert!(
        core.search_customers(digits.clone())
            .expect("search by phone")
            .iter()
            .any(|c| c.id == live_id.to_string()),
        "found by the phone digits ({last4})"
    );
    assert!(
        core.search_customers(format!("CUST-merged-{tag}")).unwrap().is_empty(),
        "a merged customer is not in the feed"
    );
    assert!(
        core.search_customers(format!("CUST-erased-{tag}")).unwrap().is_empty(),
        "an erased customer is not in the feed"
    );

    // Added on the till: usable at once, then drained.
    let added = core
        .create_customer(format!("CUST-till-{tag}"), None)
        .expect("create on the till");
    assert_eq!(
        core.customer_by_id(added.id.clone()).unwrap().map(|c| c.name),
        Some(format!("CUST-till-{tag}"))
    );

    // A sale naming the dashboard customer.
    core.open_till(10_000, None).await.expect("open");
    let cash = method(&core, true).expect("a cash method");
    let item = core
        .list_menu_items()
        .expect("items")
        .into_iter()
        .find(|i| i.base_price_minor > 0)
        .expect("a priced menu item");
    core.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor)
        .expect("add");
    let sale = core
        .checkout(
            None,
            madar_core::checkout::CheckoutInput {
                payment_method_id: cash,
                amount_tendered_minor: item.base_price_minor,
                tip_minor: 0,
                tip_payment_method_id: None,
                customer_name: None,
                notes: None,
                splits: vec![],
                loyalty_customer_id: None,
                dine_in: false,
                customer_id: Some(live_id.to_string()),
                loyalty_redemptions: vec![],
            },
        )
        .await
        .expect("checkout");
    settle(&core, 90).await;

    let added_id = uuid::Uuid::parse_str(&added.id).unwrap();
    let row = fx
        .db
        .query_opt(
            "SELECT created_branch_id FROM customers WHERE id = $1 AND org_id = $2",
            &[&added_id, &org],
        )
        .await
        .unwrap()
        .expect("the till's customer reached the server");
    assert_eq!(row.get::<_, Option<uuid::Uuid>>(0), Some(branch));

    let attached: i64 = fx
        .db
        .query_one(
            "SELECT count(*) FROM orders WHERE branch_id = $1 AND customer_id = $2",
            &[&branch, &live_id],
        )
        .await
        .unwrap()
        .get(0);
    assert_eq!(attached, 1, "sale {} carries its customer", sale.local_order_id);
}
