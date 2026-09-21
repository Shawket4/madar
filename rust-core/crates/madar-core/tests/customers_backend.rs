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

/// The customer a bill names on one till, as another till reads it after a pull.
async fn bill_customer_on(core: &madar_core::MadarCore, ticket: &str) -> Option<String> {
    let _ = core.sync_now().await;
    core.list_open_tickets()
        .await
        .expect("tickets")
        .into_iter()
        .find(|t| t.id == ticket)
        .and_then(|t| t.customer_id)
}

/// The customer a server row names (`sql` selects one nullable uuid by `$1`).
async fn one_customer(fx: &Fixture, sql: &str, key: uuid::Uuid) -> Option<uuid::Uuid> {
    fx.db.query_one(sql, &[&key]).await.expect("the row is on the server").get(0)
}

/// `set_ticket_customer` and `attach_customer` against the real backend:
/// * a customer picked on an open bill on till A is on the server's bill, and
///   till B shows it after its pull;
/// * changing it moves both;
/// * the settle carries the bill's customer onto the sale — once;
/// * a past sale that named nobody takes a customer afterwards.
#[tokio::test]
#[ignore]
async fn a_bills_customer_reaches_the_other_till_and_its_sale_once() {
    use std::time::{Duration, Instant};

    let fx = fixture(2).await;
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    let org: uuid::Uuid = fx
        .db
        .query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch])
        .await
        .unwrap()
        .get(0);
    let tag = &uuid::Uuid::new_v4().simple().to_string()[..6];
    let mut customers = Vec::new();
    for (n, lead) in [("first", "101"), ("second", "102")] {
        let digits = format!("{lead}{:07}", u32::from_str_radix(tag, 16).unwrap() % 10_000_000);
        let id: uuid::Uuid = fx
            .db
            .query_one(
                "INSERT INTO customers (org_id, name, phone, phone_key) VALUES ($1, $2, $3, $4) RETURNING id",
                &[&org, &format!("CUST-{n}-{tag}"), &format!("+20 {digits}"), &digits],
            )
            .await
            .expect("dashboard customer")
            .get(0);
        customers.push(id);
    }
    let (first, second) = (customers[0], customers[1]);

    let a = core_at(&fx.base, &temp_db("customers_a"), &fx.tellers[0].1, &fx.branch).await;
    let b = core_at(&fx.base, &temp_db("customers_b"), &fx.tellers[1].1, &fx.branch).await;
    let till = a.open_till(10_000, Some("customers e2e".into())).await.expect("open").till.expect("till").id;
    let cash = method(&a, true).expect("a cash method");

    // An open bill that names nobody, landed on the server.
    let item = a
        .list_menu_items()
        .expect("items")
        .into_iter()
        .find(|i| i.base_price_minor > 0)
        .expect("a priced menu item");
    a.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor).expect("add");
    let fired = a.fire_ticket(None, None, None, Some(1), None, None).await.expect("fire");
    settle(&a, 120).await;
    let key = uuid::Uuid::parse_str(&fired.ticket_id).unwrap();
    let ticket: uuid::Uuid = fx
        .db
        .query_one("SELECT id FROM open_tickets WHERE idempotency_key = $1 OR id = $1", &[&key])
        .await
        .expect("the fire landed")
        .get(0);
    let ticket_id = ticket;
    assert_eq!(one_customer(&fx, "SELECT customer_id FROM open_tickets WHERE id = $1", ticket_id).await, None);
    let ticket = ticket.to_string();
    assert_eq!(bill_customer_on(&b, &ticket).await, None, "till B sees the bill, for nobody yet");

    // Picked on A → on the server → on B after its pull. Then changed.
    for who in [first, second] {
        a.set_ticket_customer(ticket.clone(), Some(who.to_string())).expect("pick the customer");
        assert_eq!(
            a.list_open_tickets().await.unwrap().into_iter().find(|t| t.id == ticket).and_then(|t| t.customer_id),
            Some(who.to_string()),
            "the bill shows its customer at once on the till that picked it"
        );
        settle(&a, 90).await;
        assert_eq!(one_customer(&fx, "SELECT customer_id FROM open_tickets WHERE id = $1", ticket_id).await, Some(who), "the server's bill names the customer");
        let deadline = Instant::now() + Duration::from_secs(60);
        loop {
            if bill_customer_on(&b, &ticket).await == Some(who.to_string()) {
                break;
            }
            assert!(Instant::now() < deadline, "till B never saw the bill's customer {who}");
            tokio::time::sleep(Duration::from_secs(2)).await;
        }
    }

    // Settled with no customer argument: the bill's own rides onto the sale.
    a.settle_ticket(
        ticket.clone(),
        till.clone(),
        cash.clone(),
        Some(1_000_000),
        None,
        None,
        None,
        None,
        None,
        None,
        vec![],
        vec![],
        false,
        None,
        None,
    )
    .await
    .expect("settle");
    settle(&a, 120).await;
    let ticket_uuid = uuid::Uuid::parse_str(&ticket).unwrap();
    let sales = fx
        .db
        .query("SELECT customer_id FROM orders WHERE open_ticket_id = $1", &[&ticket_uuid])
        .await
        .unwrap();
    assert_eq!(sales.len(), 1, "one sale for the bill");
    assert_eq!(sales[0].get::<_, Option<uuid::Uuid>>(0), Some(second));
    let count = |who: uuid::Uuid| {
        let db = &fx.db;
        async move {
            db.query_one("SELECT count(*) FROM orders WHERE branch_id = $1 AND customer_id = $2", &[&branch, &who])
                .await
                .unwrap()
                .get::<_, i64>(0)
        }
    };
    assert_eq!(count(second).await, 1, "the customer has the sale once");
    assert_eq!(count(first).await, 0, "the customer taken off the bill has nothing");

    // A past sale that named nobody takes a customer afterwards.
    let past = sell(&a, 1, &cash, 1_000_000).await;
    settle(&a, 90).await;
    let past_key = uuid::Uuid::parse_str(&past).unwrap();
    assert_eq!(one_customer(&fx, "SELECT customer_id FROM orders WHERE idempotency_key = $1", past_key).await, None);
    a.attach_customer(past.clone(), Some(first.to_string())).expect("attach");
    settle(&a, 90).await;
    assert_eq!(one_customer(&fx, "SELECT customer_id FROM orders WHERE idempotency_key = $1", past_key).await, Some(first), "the past sale now names its customer");
    assert_eq!(count(first).await, 1);
    assert_eq!(count(second).await, 1);
}
