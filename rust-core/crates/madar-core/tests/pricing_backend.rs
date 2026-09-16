//! PRICING_TAX_AUDIT fixes, end to end: the REAL `MadarCore` against the REAL
//! backend (release build, a copy of a local database).
//!
//! Ignored by `cargo test`. Run it with the offline-B runner, which builds the
//! backend, copies the database, starts the server and tears it all down:
//!
//! ```sh
//! MADAR_OB_TEST=pricing_backend MADAR_OB_SOURCE_DB=madar_prodcopy_assets2 tool/offline_b_backend.sh
//! ```
//!
//! What it proves, at a branch charging 14% on top and a 10% taxed service charge:
//! * a table's bill with a discount picked at the till settles at the figure the
//!   core re-priced, split across two methods, and the server books exactly that;
//! * a counter sale carries no service charge and the server accepts its figure;
//! * removing the service charge follows the EFFECTIVE `orders:waive_service`
//!   grant — a teller without it and a manager with it revoked are refused (by
//!   the core, and by the server when asked directly); a teller granted it and a
//!   manager on the role default are honoured, and the order records who;
//! * a partial refund takes its share of tax and service charge off the till's
//!   report, on the server and on the device alike.

use std::sync::Arc;
use std::time::{Duration, Instant};

use madar_core::checkout::{CheckoutInput, CheckoutSplit};
use madar_core::session::{LoginMode, LoginRequest};
use madar_core::{MadarConfig, MadarCore};

fn env(k: &str) -> String {
    std::env::var(k).unwrap_or_else(|_| panic!("set {k} (see the module docs)"))
}

struct Fixture {
    base: String,
    branch: String,
    org: uuid::Uuid,
    db: tokio_postgres::Client,
}

async fn fixture() -> Fixture {
    let (db, conn) = tokio_postgres::connect(&env("MADAR_OB_DB"), tokio_postgres::NoTls)
        .await
        .expect("connect the throwaway DB");
    tokio::spawn(async move {
        let _ = conn.await;
    });
    let branch = env("MADAR_OB_BRANCH");
    let branch_uuid = uuid::Uuid::parse_str(&branch).unwrap();
    let org: uuid::Uuid = db
        .query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch_uuid])
        .await
        .expect("the branch exists")
        .get(0);
    // 14% on top, and a 10% service charge that is itself taxed.
    db.execute(
        "UPDATE branches SET tax_rate = 0.14, tax_inclusive = false, service_charge_rate = 0.10,
                             service_charge_taxable = true WHERE id = $1",
        &[&branch_uuid],
    )
    .await
    .expect("branch policy");
    // A card-like method at the branch, for the split.
    db.execute(
        "INSERT INTO branch_payment_methods (branch_id, payment_method_id, org_id)
         SELECT $1, m.id, m.org_id FROM org_payment_methods m
          WHERE m.org_id = $2 AND m.is_active AND NOT m.is_cash
            AND EXISTS (SELECT 1 FROM branch_payment_methods WHERE branch_id = $1)
            AND NOT EXISTS (SELECT 1 FROM branch_payment_methods b JOIN org_payment_methods o ON o.id = b.payment_method_id
                             WHERE b.branch_id = $1 AND NOT o.is_cash)
          ORDER BY m.created_at LIMIT 1",
        &[&branch_uuid, &org],
    )
    .await
    .expect("branch methods");
    Fixture { base: env("MADAR_OB_BASE"), branch, org, db }
}

/// A PIN user at the fixture's branch. `waive` is a per-user override of
/// `orders:waive_service` (None = the role default).
async fn user(fx: &Fixture, role: &str, waive: Option<bool>) -> (uuid::Uuid, String) {
    let id = uuid::Uuid::new_v4();
    // A manager signs in at the till with email and password (PIN sign-in is
    // for tellers, waiters and the KDS); the name says which.
    let prefix = if role == "branch_manager" { "PRM" } else { "PR" };
    let name = format!("{prefix}-{}", &id.simple().to_string()[..8]);
    fx.db
        .execute(
            "INSERT INTO users (id, org_id, name, role, pin_hash, email, password_hash)
             VALUES ($1, $2, $3, $4::text::public.user_role, crypt('1234', gen_salt('bf', 4)),
                     lower($3) || '@pricing.test', crypt('secret-1234', gen_salt('bf', 4)))",
            &[&id, &fx.org, &name, &role],
        )
        .await
        .expect("insert user");
    if role == "branch_manager" {
        let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
        fx.db
            .execute(
                "INSERT INTO user_branch_assignments (user_id, branch_id) VALUES ($1, $2)",
                &[&id, &branch],
            )
            .await
            .expect("assign manager");
    }
    if let Some(granted) = waive {
        fx.db
            .execute(
                "INSERT INTO permissions (user_id, resource, action, granted)
                 VALUES ($1, 'orders', 'waive_service', $2)",
                &[&id, &granted],
            )
            .await
            .expect("override");
    }
    (id, name)
}

async fn signed_in(base: &str, db_path: &str, who: &str, branch: &str) -> Arc<MadarCore> {
    let core = MadarCore::new(MadarConfig {
        base_url: base.to_string(),
        environment: "dev".into(),
        db_path: db_path.to_string(),
        locale: "en".into(),
        app_version: None,
    })
    .expect("core");
    let deadline = Instant::now() + Duration::from_secs(120);
    let s = loop {
        let manager = who.starts_with("PRM-");
        match core
            .sign_in(LoginRequest {
                mode: if manager { LoginMode::Email } else { LoginMode::Pin },
                name: (!manager).then(|| who.to_string()),
                pin: (!manager).then(|| "1234".into()),
                branch_id: Some(branch.to_string()),
                email: manager.then(|| format!("{}@pricing.test", who.to_lowercase())),
                password: manager.then(|| "secret-1234".into()),
                org_id: None,
            })
            .await
        {
            Err(madar_core::error::CoreError::Server { status: 429, .. }) if Instant::now() < deadline => {
                tokio::time::sleep(Duration::from_secs(3)).await;
            }
            other => break other.expect("sign in"),
        }
    };
    assert!(s.online, "the sign-in reaches the backend");
    core
}

async fn core_for(fx: &Fixture, who: &str) -> Arc<MadarCore> {
    let db = std::env::temp_dir()
        .join(format!("madar_pricing_it_{}.sqlite", uuid::Uuid::new_v4().simple()))
        .to_string_lossy()
        .into_owned();
    let core = signed_in(&fx.base, &db, who, &fx.branch).await;
    core.refresh_connectivity().await;
    core.refresh_catalog().await.expect("catalog");
    core.sync_full().await.expect("first snapshot");
    core
}

fn method(core: &MadarCore, cash: bool) -> Option<String> {
    core.available_payment_methods()
        .expect("methods")
        .into_iter()
        .find(|p| p.is_cash == cash)
        .map(|p| p.id)
}

fn add_items(core: &MadarCore, qty: usize) {
    let item = core
        .list_menu_items()
        .expect("items")
        .into_iter()
        .find(|i| i.base_price_minor > 0)
        .expect("a priced menu item");
    for _ in 0..qty {
        core.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor).expect("add");
    }
}

async fn settle(core: &MadarCore, max_secs: u64) {
    let deadline = Instant::now() + Duration::from_secs(max_secs);
    let mut s = core.sync_now().await.expect("sync");
    let mut last_kick = Instant::now();
    loop {
        assert_eq!(s.dead_outbox, 0, "nothing dead-letters: {s:?}");
        if s.pending_outbox == 0 && s.freshness.state == "fresh" {
            return;
        }
        assert!(Instant::now() < deadline, "did not settle: {s:?}");
        tokio::time::sleep(Duration::from_millis(500)).await;
        if s.pending_outbox == 0 && last_kick.elapsed() > Duration::from_secs(5) {
            core.sync_now().await.expect("sync");
            last_kick = Instant::now();
        }
        s = core.sync_status();
    }
}

/// Open a till, fire a two-item bill, and wait for the server to price it.
async fn priced_bill(fx: &Fixture, core: &MadarCore) -> (String, String) {
    let till = core.open_till(0, Some("pricing e2e".into())).await.expect("open").till.expect("till").id;
    add_items(core, 2);
    let fired = core.fire_ticket(None, None, None, Some(2), None).await.expect("fire");
    settle(core, 120).await;
    // The fire's id is the client's idempotency key; the server's ticket id is
    // what every later call names.
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
        let bill = core
            .list_open_tickets()
            .await
            .expect("tickets")
            .into_iter()
            .find(|t| t.id == server_id)
            .and_then(|t| t.bill);
        if bill.is_some() {
            return (till, server_id);
        }
        assert!(Instant::now() < deadline, "the server never priced the bill");
        tokio::time::sleep(Duration::from_secs(1)).await;
        let _ = core.sync_now().await;
    }
}

struct Booked {
    order_id: uuid::Uuid,
    total: i64,
    discount: i64,
    service: i64,
    tax: i64,
    legs: i64,
    waived_by: Option<uuid::Uuid>,
    waived_amount: i64,
}

async fn booked(fx: &Fixture, ticket: &str) -> Booked {
    let t = uuid::Uuid::parse_str(ticket).unwrap();
    let r = fx
        .db
        .query_one(
            "SELECT o.id, o.total_amount::int8, o.discount_amount::int8, o.service_charge_amount::int8,
                    o.tax_amount::int8, (SELECT COALESCE(SUM(amount), 0)::int8 FROM order_payments WHERE order_id = o.id),
                    o.service_charge_waived_by, o.service_charge_waived_amount::int8
               FROM orders o WHERE o.open_ticket_id = $1",
            &[&t],
        )
        .await
        .expect("the settle booked an order");
    Booked {
        order_id: r.get(0),
        total: r.get(1),
        discount: r.get(2),
        service: r.get(3),
        tax: r.get(4),
        legs: r.get(5),
        waived_by: r.get(6),
        waived_amount: r.get(7),
    }
}

#[allow(clippy::too_many_arguments)]
/// The server's report for a till: a fresh device that holds none of the
/// till, so its read serves the report its background fill fetched from the
/// server (`from_server`). A fresh probe per call: a device's fill of a till it
/// does not hold is refreshed by the feed, and a probe never pulls.
async fn server_report(fx: &Fixture, who: &str, till: &str) -> madar_core::till::TillReportView {
    let probe = signed_in(&fx.base, "", who, &fx.branch).await;
    let deadline = Instant::now() + Duration::from_secs(120);
    loop {
        match probe.till_report_for(till.to_string()).await {
            Ok(r) if r.from_server => return r,
            other => eprintln!("server report: not from the server yet ({:?})", other.map(|r| r.from_server)),
        }
        assert!(Instant::now() < deadline, "no server report for {till}");
        tokio::time::sleep(Duration::from_secs(3)).await;
    }
}

async fn settle_bill(
    core: &MadarCore,
    ticket: &str,
    till: &str,
    method_id: &str,
    discount: Option<(&str, f64)>,
    splits: Vec<CheckoutSplit>,
    waive: bool,
) -> Result<Option<String>, madar_core::error::CoreError> {
    core.settle_ticket(
        ticket.to_string(),
        till.to_string(),
        method_id.to_string(),
        None,
        None,
        None,
        None,
        discount.map(|d| d.0.to_string()),
        discount.map(|d| d.1),
        None,
        vec![],
        splits,
        waive,
    )
    .await
}

/// A bare HTTP/1.1 POST to the local backend: `(status, body)`.
async fn http_post(base: &str, path: &str, token: Option<&str>, body: &serde_json::Value) -> (u16, String) {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let host = base.trim_start_matches("http://");
    let mut stream = tokio::net::TcpStream::connect(host).await.expect("connect");
    let payload = body.to_string();
    let auth = token.map(|t| format!("Authorization: Bearer {t}\r\n")).unwrap_or_default();
    let req = format!(
        "POST {path} HTTP/1.1\r\nHost: {host}\r\nContent-Type: application/json\r\n{auth}Content-Length: {}\r\nConnection: close\r\n\r\n{payload}",
        payload.len()
    );
    stream.write_all(req.as_bytes()).await.unwrap();
    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).await.unwrap();
    let text = String::from_utf8_lossy(&raw).to_string();
    let status = text.split(' ').nth(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    let body = text.split_once("\r\n\r\n").map(|(_, b)| b.to_string()).unwrap_or_default();
    (status, body)
}

// ---------------------------------------------------------------------------

#[tokio::test]
#[ignore]
async fn a_table_bill_with_a_discount_settles_at_the_due_and_a_partial_refund_moves_the_report() {
    let fx = fixture().await;
    let (_, teller) = user(&fx, "teller", None).await;
    let core = core_for(&fx, &teller).await;
    let cash = method(&core, true).expect("a cash method");
    let card = method(&core, false).expect("a card method");
    let (till, ticket) = priced_bill(&fx, &core).await;

    let before = core.bill_with_rewards(ticket.clone(), vec![], None, None, false).unwrap().expect("bill");
    let due = core
        .bill_with_rewards(ticket.clone(), vec![], Some("percentage".into()), Some(0.10), false)
        .unwrap()
        .expect("re-priced bill");
    assert!(due.total_minor < before.total_minor, "the discount moves the due: {before:?} -> {due:?}");
    assert!(due.service_charge_minor > 0 && due.discount_minor > 0);

    let half = due.total_minor / 2;
    settle_bill(
        &core,
        &ticket,
        &till,
        &cash,
        Some(("percentage", 0.10)),
        vec![
            CheckoutSplit { payment_method_id: cash.clone(), amount_minor: half },
            CheckoutSplit { payment_method_id: card.clone(), amount_minor: due.total_minor - half },
        ],
        false,
    )
    .await
    .expect("settle");
    settle(&core, 180).await;
    let b = booked(&fx, &ticket).await;
    assert_eq!(
        (b.total, b.discount, b.service, b.tax, b.legs),
        (due.total_minor, due.discount_minor, due.service_charge_minor, due.tax_minor, due.total_minor),
        "the server booked the till's figure and the legs add up to it"
    );

    // A partial refund: a fifth of the bill, in cash.
    // The server's own report, read by a device that holds none of the till
    // (a fresh probe per read, waiting for its background fill).
    let srv_before = server_report(&fx, &teller, &till).await;
    assert_eq!(
        (srv_before.total_tax_minor, srv_before.total_service_charge_minor),
        (b.tax, b.service),
        "the report carries the bill's tax and service charge"
    );
    let amount = b.total / 5;
    core.refund_order(b.order_id.to_string(), amount, "cash".into(), "quality_issue".into(), None)
        .await
        .expect("refund");
    settle(&core, 120).await;
    let (tax_back, sc_back) = madar_core::tax::refund_split(b.total, b.tax, b.service, 0, amount);
    assert!(tax_back > 0 && sc_back > 0);
    let srv_after = server_report(&fx, &teller, &till).await;
    assert_eq!(
        (srv_after.total_tax_minor, srv_after.total_service_charge_minor),
        (b.tax - tax_back, b.service - sc_back),
        "the server's report takes the refund's share of tax and service off"
    );
    let local = core.till_report_for(till.clone()).await.expect("local report");
    assert_eq!(
        (local.total_tax_minor, local.total_service_charge_minor),
        (srv_after.total_tax_minor, srv_after.total_service_charge_minor),
        "the device's report agrees"
    );
}

#[tokio::test]
#[ignore]
async fn a_takeaway_carries_no_service_charge_and_the_server_accepts_it() {
    let fx = fixture().await;
    let (_, teller) = user(&fx, "teller", None).await;
    let core = core_for(&fx, &teller).await;
    let cash = method(&core, true).expect("a cash method");
    core.open_till(0, Some("pricing e2e".into())).await.expect("open");
    add_items(&core, 3);
    let totals = core.cart_totals(None).expect("totals");
    assert_eq!(totals.service_charge_minor, 0, "a counter cart carries no service charge");
    assert!(totals.tax_minor > 0);
    let receipt = core
        .checkout(
            None,
            CheckoutInput {
                payment_method_id: cash,
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
            },
        )
        .await
        .expect("checkout");
    settle(&core, 120).await; // asserts nothing dead-letters: no price mismatch
    let key = uuid::Uuid::parse_str(&receipt.local_order_id).unwrap();
    let r = fx
        .db
        .query_one(
            "SELECT total_amount::int8, service_charge_amount::int8, order_type FROM orders WHERE idempotency_key = $1",
            &[&key],
        )
        .await
        .expect("the sale landed");
    let (total, service, kind): (i64, i64, String) = (r.get(0), r.get(1), r.get(2));
    assert_eq!((total, service, kind.as_str()), (receipt.total_minor, 0, "takeaway"));
}

#[tokio::test]
#[ignore]
async fn removing_the_service_charge_follows_the_effective_permission() {
    let fx = fixture().await;
    let (_, plain_teller) = user(&fx, "teller", None).await;
    let (granted_id, granted_teller) = user(&fx, "teller", Some(true)).await;
    let (manager_id, manager) = user(&fx, "branch_manager", None).await;
    let (_, revoked_manager) = user(&fx, "branch_manager", Some(false)).await;

    // Refused: a teller on the role default, a manager with it revoked. The core
    // does not offer it and refuses the settle; the server refuses it too.
    for who in [&plain_teller, &revoked_manager] {
        let core = core_for(&fx, who).await;
        assert!(!core.can_waive_service_charge(), "{who} may not remove the service charge");
        let cash = method(&core, true).expect("cash");
        let (till, ticket) = priced_bill(&fx, &core).await;
        let err = settle_bill(&core, &ticket, &till, &cash, None, vec![], true).await;
        assert!(err.is_err(), "the core refuses {who}'s waiver");

        // Straight to the server, as an old or tampered till would.
        let (status, body) = http_post(
            &fx.base,
            "/auth/login",
            None,
            &if who.starts_with("PRM-") {
                serde_json::json!({ "email": format!("{}@pricing.test", who.to_lowercase()), "password": "secret-1234", "branch_id": fx.branch })
            } else {
                serde_json::json!({ "name": who, "pin": "1234", "branch_id": fx.branch })
            },
        )
        .await;
        assert_eq!(status, 200, "{who} login: {body}");
        let token = serde_json::from_str::<serde_json::Value>(&body).unwrap()["token"].as_str().unwrap().to_string();
        let cash_name: String = fx
            .db
            .query_one(
                "SELECT name FROM org_payment_methods WHERE id = $1",
                &[&uuid::Uuid::parse_str(&cash).unwrap()],
            )
            .await
            .unwrap()
            .get(0);
        let (status, body) = http_post(
            &fx.base,
            &format!("/open-tickets/{ticket}/settle"),
            Some(&token),
            &serde_json::json!({ "till_id": till, "payment_method": cash_name, "waive_service_charge": true }),
        )
        .await;
        assert_eq!(status, 403, "{who}: the server must refuse the waiver: {body}");
        assert!(body.contains("Waive service charge"), "{who}: {body}");
    }

    // Honoured: a teller granted it per user, a manager on the role default.
    for (id, who) in [(granted_id, &granted_teller), (manager_id, &manager)] {
        let core = core_for(&fx, who).await;
        assert!(core.can_waive_service_charge(), "{who} may remove the service charge");
        let cash = method(&core, true).expect("cash");
        let (till, ticket) = priced_bill(&fx, &core).await;
        let full = core.bill_with_rewards(ticket.clone(), vec![], None, None, false).unwrap().unwrap();
        let waived = core.bill_with_rewards(ticket.clone(), vec![], None, None, true).unwrap().unwrap();
        assert!(full.service_charge_minor > 0);
        assert_eq!(waived.service_charge_minor, 0);
        assert_eq!(waived.service_charge_waived_minor, full.service_charge_minor);
        settle_bill(&core, &ticket, &till, &cash, None, vec![], true).await.expect("settle");
        settle(&core, 180).await;
        let b = booked(&fx, &ticket).await;
        assert_eq!(
            (b.total, b.service, b.waived_by, b.waived_amount),
            (waived.total_minor, 0, Some(id), full.service_charge_minor),
            "{who}: the order records the waiver"
        );
        let receipt = core.order_receipt_view(b.order_id.to_string()).await.expect("receipt");
        assert_eq!(receipt.service_charge_waived_minor, full.service_charge_minor);
        assert_eq!(receipt.service_charge_waived_by_name.as_deref(), Some(who.as_str()));
    }
}
