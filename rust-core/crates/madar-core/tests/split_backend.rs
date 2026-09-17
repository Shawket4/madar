//! Split payments, end to end: the REAL `MadarCore` against the REAL backend.
//!
//! Ignored by `cargo test`. Run it with the offline-B runner:
//!
//! ```sh
//! MADAR_OB_TESTS=split_backend MADAR_OB_SOURCE_DB=madar_prodcopy_assets2 tool/offline_b_backend.sh
//! ```
//!
//! A split used to come out as zero: the printed receipt read "Cash 0.00", the
//! server stored a 0 tender, and the create answer carried no legs. At a branch
//! charging 14% tax on top and a 10% service charge, this rings up
//! * a takeaway in two legs (online) and in three legs (offline), both discounted;
//! * a table's bill in two legs (online) and three legs (offline), both
//!   discounted with the service charge waived;
//! and checks that the device's receipt and history, the device's Z report, the
//! server's Z report and the order the dashboard reads all state the same legs,
//! summing to each sale's total, with no 0.00 tender anywhere.

mod common;

use std::collections::BTreeMap;
use std::time::{Duration, Instant};

use common::*;
use madar_core::checkout::{CheckoutInput, CheckoutSplit};
use madar_core::MadarCore;

type Legs = Vec<(String, i64)>;

fn sorted(mut v: Legs) -> Legs {
    v.sort();
    v
}

async fn http(base: &str, method: &str, path: &str, token: Option<&str>, body: Option<&serde_json::Value>) -> (u16, String) {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let host = base.trim_start_matches("http://");
    let mut stream = tokio::net::TcpStream::connect(host).await.expect("connect");
    let payload = body.map(|b| b.to_string()).unwrap_or_default();
    let auth = token.map(|t| format!("Authorization: Bearer {t}\r\n")).unwrap_or_default();
    let req = format!(
        "{method} {path} HTTP/1.1\r\nHost: {host}\r\nContent-Type: application/json\r\n{auth}Content-Length: {}\r\nConnection: close\r\n\r\n{payload}",
        payload.len()
    );
    stream.write_all(req.as_bytes()).await.unwrap();
    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).await.unwrap();
    let text = String::from_utf8_lossy(&raw).to_string();
    let status = text.split(' ').nth(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    let (head, body) = text.split_once("\r\n\r\n").unwrap_or((&text, ""));
    // A chunked body: join its chunks.
    let body = if head.to_ascii_lowercase().contains("transfer-encoding: chunked") {
        let mut out = String::new();
        let mut rest = body;
        while let Some((size, tail)) = rest.split_once("\r\n") {
            let n = usize::from_str_radix(size.trim(), 16).unwrap_or(0);
            if n == 0 {
                break;
            }
            out.push_str(&tail[..n]);
            rest = &tail[n + 2..];
        }
        out
    } else {
        body.to_string()
    };
    (status, body)
}

/// The legs the server stored for an order, and its total.
async fn server_legs(fx: &Fixture, order: uuid::Uuid) -> (Legs, i64, Option<i32>) {
    let rows = fx
        .db
        .query("SELECT method, amount::int8 FROM order_payments WHERE order_id = $1", &[&order])
        .await
        .unwrap();
    let legs = rows.iter().map(|r| (r.get::<_, String>(0), r.get::<_, i64>(1))).collect();
    let o = fx
        .db
        .query_one("SELECT total_amount::int8, amount_tendered FROM orders WHERE id = $1", &[&order])
        .await
        .unwrap();
    (sorted(legs), o.get(0), o.get(1))
}

/// Method id → the raw name the server stores on a leg.
async fn names(fx: &Fixture) -> BTreeMap<String, String> {
    fx.db
        .query("SELECT id::text, name FROM org_payment_methods", &[])
        .await
        .unwrap()
        .iter()
        .map(|r| (r.get(0), r.get(1)))
        .collect()
}

fn add_items(core: &MadarCore, table: Option<String>, qty: usize) {
    let item = core
        .list_menu_items()
        .expect("items")
        .into_iter()
        .find(|i| i.base_price_minor > 0)
        .expect("a priced menu item");
    for _ in 0..qty {
        core.cart_add(table.clone(), item.id.clone(), item.name.clone(), item.base_price_minor).expect("add");
    }
}

/// Split `total` across `methods`: equal shares, the rest on the last leg.
fn legs_for(methods: &[String], total: i64) -> Vec<CheckoutSplit> {
    let share = total / methods.len() as i64;
    methods
        .iter()
        .enumerate()
        .map(|(i, m)| CheckoutSplit {
            payment_method_id: m.clone(),
            amount_minor: if i + 1 == methods.len() { total - share * (methods.len() as i64 - 1) } else { share },
        })
        .collect()
}

async fn takeaway(core: &MadarCore, n: &BTreeMap<String, String>, discount: &str, methods: &[String]) -> (String, i64, Legs, Vec<(String, i64)>) {
    add_items(core, None, 3);
    core.cart_set_discount(None, discount.to_string()).expect("discount");
    let totals = core.cart_totals(None).expect("totals");
    assert!(totals.discount_minor > 0, "the discount applies: {totals:?}");
    let splits = legs_for(methods, totals.total_minor);
    let receipt = core
        .checkout(
            None,
            CheckoutInput {
                payment_method_id: splits[0].payment_method_id.clone(),
                amount_tendered_minor: 0,
                tip_minor: 0,
                tip_payment_method_id: None,
                customer_name: None,
                notes: None,
                splits: splits.clone(),
                loyalty_customer_id: None,
                dine_in: false,
                customer_id: None,
                loyalty_redemptions: vec![],
            },
        )
        .await
        .expect("checkout");
    assert_eq!(receipt.total_minor, totals.total_minor);
    assert_eq!(receipt.amount_tendered_minor, 0);
    let printed: Vec<(String, i64)> = receipt.payments.iter().map(|p| (p.label.clone(), p.amount_minor)).collect();
    assert_eq!(printed.len(), methods.len(), "the receipt lists every leg");
    assert_eq!(printed.iter().map(|p| p.1).sum::<i64>(), receipt.total_minor);
    let wire = splits.iter().map(|s| (n[&s.payment_method_id].clone(), s.amount_minor)).collect();
    (receipt.local_order_id, receipt.total_minor, sorted(wire), printed)
}

async fn priced_bill(fx: &Fixture, core: &MadarCore) -> String {
    add_items(core, None, 2);
    let fired = core.fire_ticket(None, None, None, Some(2), None).await.expect("fire");
    settle(core, 120).await;
    let key = uuid::Uuid::parse_str(&fired.ticket_id).unwrap();
    let server_id: uuid::Uuid = fx
        .db
        .query_one("SELECT id FROM open_tickets WHERE idempotency_key = $1 OR id = $1", &[&key])
        .await
        .expect("the fire landed")
        .get(0);
    let server_id = server_id.to_string();
    let deadline = Instant::now() + Duration::from_secs(60);
    loop {
        let priced = core
            .list_open_tickets()
            .await
            .expect("tickets")
            .into_iter()
            .any(|t| t.id == server_id && t.bill.is_some());
        if priced {
            return server_id;
        }
        assert!(Instant::now() < deadline, "the server never priced the bill");
        tokio::time::sleep(Duration::from_secs(1)).await;
        let _ = core.sync_now().await;
    }
}

async fn settle_split(core: &MadarCore, n: &BTreeMap<String, String>, ticket: &str, till: &str, methods: &[String]) -> (i64, Legs) {
    let full = core.bill_with_rewards(ticket.to_string(), vec![], None, None, false).unwrap().expect("bill");
    let due = core
        .bill_with_rewards(ticket.to_string(), vec![], Some("percentage".into()), Some(0.10), true)
        .unwrap()
        .expect("re-priced bill");
    assert!(full.service_charge_minor > 0 && due.service_charge_minor == 0 && due.discount_minor > 0, "{due:?}");
    let splits = legs_for(methods, due.total_minor);
    // Legs that miss the due are refused at the till.
    let mut short = splits.clone();
    short[0].amount_minor -= 1;
    assert!(core
        .settle_ticket(ticket.into(), till.into(), methods[0].clone(), None, None, None, None,
            Some("percentage".into()), Some(0.10), None, vec![], short, true, None)
        .await
        .is_err());
    core.settle_ticket(
        ticket.to_string(),
        till.to_string(),
        methods[0].clone(),
        None,
        None,
        None,
        None,
        Some("percentage".into()),
        Some(0.10),
        None,
        vec![],
        splits.clone(),
        true,
        None,
    )
    .await
    .expect("settle");
    (due.total_minor, sorted(splits.iter().map(|s| (n[&s.payment_method_id].clone(), s.amount_minor)).collect()))
}

#[tokio::test]
#[ignore]
async fn split_sales_show_the_same_legs_everywhere() {
    let fx = fixture(1).await;
    let (teller_id, teller) = fx.tellers[0].clone();
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    let org: uuid::Uuid = fx.db.query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch]).await.unwrap().get(0);
    fx.db
        .batch_execute(&format!(
            "UPDATE branches SET tax_rate = 0.14, tax_inclusive = false, service_charge_rate = 0.10,
                                 service_charge_taxable = true WHERE id = '{branch}';
             INSERT INTO org_payment_methods (org_id, name, color, icon, is_cash)
                  VALUES ('{org}', 'SplitWallet', '#000000', 'wallet', false) ON CONFLICT DO NOTHING;
             INSERT INTO branch_payment_methods (branch_id, payment_method_id, org_id)
                  SELECT '{branch}', m.id, m.org_id FROM org_payment_methods m
                   WHERE m.org_id = '{org}' AND m.name = 'SplitWallet'
                     AND EXISTS (SELECT 1 FROM branch_payment_methods WHERE branch_id = '{branch}');
             INSERT INTO permissions (user_id, resource, action, granted) VALUES ('{teller_id}', 'orders', 'waive_service', true);"
        ))
        .await
        .expect("branch setup");
    let discount: uuid::Uuid = fx
        .db
        .query_one(
            "INSERT INTO discounts (org_id, name, type, value) VALUES ($1, 'Split 10%', 'percentage', 0.10) RETURNING id",
            &[&org],
        )
        .await
        .unwrap()
        .get(0);

    let proxy = Proxy::start(&fx.base).await;
    let core = core_at(&proxy.base, &temp_db("split"), &teller, &fx.branch).await;
    core.refresh_catalog().await.expect("catalog");
    assert!(core.can_waive_service_charge());
    let till = core.open_till(0, Some("split e2e".into())).await.expect("open").till.expect("till").id;
    let methods = core.available_payment_methods().unwrap();
    let cash = methods.iter().find(|m| m.is_cash).expect("cash").id.clone();
    let cards: Vec<String> = methods.iter().filter(|m| !m.is_cash).map(|m| m.id.clone()).collect();
    assert!(cards.len() >= 2, "two non-cash methods for a three-leg split: {methods:?}");
    let n = names(&fx).await;
    let two = vec![cash.clone(), cards[0].clone()];
    let three = vec![cash.clone(), cards[0].clone(), cards[1].clone()];

    // Online: a takeaway in two legs, a table in two legs.
    let (t1_key, t1_total, t1_legs, _) = takeaway(&core, &n, &discount.to_string(), &two).await;
    settle(&core, 120).await;
    let bill1 = priced_bill(&fx, &core).await;
    let (b1_total, b1_legs) = settle_split(&core, &n, &bill1, &till, &two).await;
    settle(&core, 120).await;

    // Offline: a table priced while online, then a takeaway and the table in three legs.
    let bill2 = priced_bill(&fx, &core).await;
    proxy.offline();
    for _ in 0..3 {
        core.refresh_connectivity().await;
    }
    let (t2_key, t2_total, t2_legs, _) = takeaway(&core, &n, &discount.to_string(), &three).await;
    let (b2_total, b2_legs) = settle_split(&core, &n, &bill2, &till, &three).await;
    assert!(!core.sync_status().online);
    let offline_z = core.till_report_for(till.clone()).await.expect("offline report");
    proxy.online();
    core.refresh_connectivity().await;
    settle(&core, 180).await;

    // Every sale, on the server.
    let by_key = |k: &str| uuid::Uuid::parse_str(k).unwrap();
    let mut sales = Vec::new();
    for (key, total, legs) in [(t1_key, t1_total, t1_legs), (t2_key, t2_total, t2_legs)] {
        let id: uuid::Uuid = fx.db.query_one("SELECT id FROM orders WHERE idempotency_key = $1", &[&by_key(&key)]).await.unwrap().get(0);
        sales.push((id, total, legs));
    }
    for (ticket, total, legs) in [(bill1, b1_total, b1_legs), (bill2, b2_total, b2_legs)] {
        let id: uuid::Uuid = fx.db.query_one("SELECT id FROM orders WHERE open_ticket_id = $1", &[&by_key(&ticket)]).await.unwrap().get(0);
        sales.push((id, total, legs));
    }

    // The dashboard reads orders with a manager's token; the teller's shows the same rows.
    let (status, body) = http(
        &fx.base,
        "POST",
        "/auth/login",
        None,
        Some(&serde_json::json!({ "name": teller, "pin": "1234", "branch_id": fx.branch })),
    )
    .await;
    assert_eq!(status, 200, "login: {body}");
    let token = serde_json::from_str::<serde_json::Value>(&body).unwrap()["token"].as_str().unwrap().to_string();

    let mut want_lines: BTreeMap<String, i64> = BTreeMap::new();
    let history = core.list_till_orders().await.expect("history");
    for (id, total, legs) in &sales {
        let (stored, stored_total, tendered) = server_legs(&fx, *id).await;
        assert_eq!(stored_total, *total, "the server booked the till's total");
        assert_eq!(&stored, legs, "the server stored the legs the till took");
        assert_eq!(stored.iter().map(|l| l.1).sum::<i64>(), *total, "legs sum to the total");
        assert_eq!(tendered, None, "no 0.00 tender on a split");
        for (m, a) in legs {
            *want_lines.entry(m.clone()).or_default() += a;
        }

        // The device: history lists the sale, its receipt lists the legs.
        assert!(history.iter().any(|o| o.total_minor == *total), "history holds {id}");
        let receipt = core.order_receipt_view(id.to_string()).await.expect("receipt");
        assert_eq!(receipt.total_minor, *total);
        let printed = sorted(receipt.payments.iter().map(|p| (p.label.clone(), p.amount_minor)).collect());
        assert_eq!(printed.iter().map(|p| p.1).sum::<i64>(), *total, "the receipt's legs: {printed:?}");
        assert_eq!(printed.len(), legs.len());
        assert_eq!((receipt.amount_tendered_minor, receipt.change_minor), (0, 0));

        // What the dashboard's order sheet reads.
        let (status, body) = http(&fx.base, "GET", &format!("/orders/{id}"), Some(&token), None).await;
        assert_eq!(status, 200, "GET /orders/{id}: {body}");
        let v: serde_json::Value = serde_json::from_str(&body).unwrap();
        let api = sorted(
            v["payment_legs"]
                .as_array()
                .expect("payment_legs")
                .iter()
                .map(|l| (l["method"].as_str().unwrap().to_string(), l["amount"].as_i64().unwrap()))
                .collect(),
        );
        assert_eq!(&api, legs, "the dashboard reads the same legs");
        assert_eq!(v["payment_method"], "mixed");
    }

    // The Z report: the device (offline and synced) and the server agree, per method.
    let lines = |r: &madar_core::till::TillReportView| -> BTreeMap<String, i64> {
        r.payment_lines.iter().map(|l| (l.method.clone(), l.total_minor)).collect()
    };
    let srv = server_report(&fx, &teller, &till).await;
    let local = core.till_report_for(till.clone()).await.expect("local report");
    let srv_lines = lines(&srv);
    for (m, a) in &want_lines {
        assert_eq!(srv_lines.get(m), Some(a), "server Z line {m}: {srv_lines:?}");
    }
    assert_eq!(figures(&local), figures(&srv), "the device's Z matches the server's");
    assert_eq!(lines(&offline_z), srv_lines, "the offline Z already had the legs");
    let cash_name = n[&cash].clone();
    assert_eq!(srv.expected_cash_minor, want_lines[&cash_name], "the drawer holds only the cash legs");
}
