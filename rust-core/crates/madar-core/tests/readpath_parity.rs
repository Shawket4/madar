//! Read parity against the REAL backend: every screen read the core serves —
//! computed from the local rows, the only read path — against the server's own
//! figures, after realistic days (online, offline, reconnect, two devices, a
//! drained backlog, voids, refunds, cash movements, a close, a past till, a
//! device before its first snapshot).
//!
//! Ignored by `cargo test`. Run with the backend harness:
//!
//! ```sh
//! MADAR_OB_TESTS=readpath_parity tool/offline_b_backend.sh
//! ```
//!
//! The reference is the server: its database for lists and counts (orders,
//! refunds, drawer movements, tills, bills, kitchen tickets, deliveries,
//! bookings) and its own Z report (read by a probe device that holds none of
//! the till). Every difference fails the scenario. Until the local rows became
//! the only read path this suite compared them with the legacy reads instead;
//! the differences it found then are in `OFFLINE_B_DESIGN.md` (Implementation
//! status, read-path parity).

mod common;

use std::collections::{BTreeMap, BTreeSet};
use std::time::{Duration, Instant};

use common::*;
use madar_core::MadarCore;

const ACTIVE_DELIVERY: &str = "received,confirmed,preparing,ready,out_for_delivery";

fn uid(s: &str) -> uuid::Uuid {
    uuid::Uuid::parse_str(s).unwrap()
}

fn check<T: PartialEq + std::fmt::Debug>(out: &mut Vec<String>, what: &str, device: T, server: T) {
    if device != server {
        out.push(format!("{what}: device {device:?} server {server:?}"));
    }
}

/// Every screen read of `core`, against the server, for the tills named.
async fn server_parity(fx: &Fixture, core: &MadarCore, tills: &[(String, String)]) -> Vec<String> {
    let mut d = Vec::new();
    let branch = uid(&fx.branch);
    for (t, teller) in tills {
        let till = uid(t);
        // The sales.
        let device: BTreeMap<String, (i64, String)> = core
            .list_orders_for_till(t.clone())
            .await
            .unwrap()
            .into_iter()
            .map(|o| (o.order_ref.clone().unwrap_or(o.id.clone()), (o.total_minor, o.status)))
            .collect();
        let server: BTreeMap<String, (i64, String)> = fx
            .db
            .query("SELECT order_ref, total_amount, status::text FROM orders WHERE till_id = $1", &[&till])
            .await
            .unwrap()
            .iter()
            .map(|r| (r.get::<_, String>(0), (r.get::<_, i32>(1) as i64, r.get::<_, String>(2))))
            .collect();
        check(&mut d, &format!("orders of {t}"), device, server);
        // The refunds from its drawer.
        let refunds = core.list_till_refunds(t.clone()).await.unwrap();
        let row = fx
            .db
            .query_one("SELECT COUNT(*), COALESCE(SUM(amount), 0)::bigint FROM order_refunds WHERE till_id = $1", &[&till])
            .await
            .unwrap();
        check(&mut d, &format!("refunds of {t}"), (refunds.refund_count, refunds.refunded_minor), (row.get::<_, i64>(0), row.get::<_, i64>(1)));
        // Its Z report, every figure, against the server's own report.
        let device = figures(&core.till_report_for(t.clone()).await.unwrap());
        let server = figures(&server_report(fx, teller, t).await);
        check(&mut d, &format!("report of {t}"), device, server);
    }
    // The current till's drawer and close preview.
    if let Ok(Some(cur)) = core.current_till() {
        let till = uid(&cur.id);
        let moves = core.list_cash_movements().await.unwrap();
        let row = fx
            .db
            .query_one("SELECT COUNT(*), COALESCE(SUM(amount), 0)::bigint FROM till_cash_movements WHERE till_id = $1", &[&till])
            .await
            .unwrap();
        check(
            &mut d,
            "cash movements",
            (moves.len() as i64, moves.iter().map(|m| m.amount_minor).sum::<i64>()),
            (row.get::<_, i64>(0), row.get::<_, i64>(1)),
        );
        if cur.is_open {
            let preview = core.close_till_preview().await.unwrap();
            let teller = tills.iter().find(|(t, _)| *t == cur.id).map(|(_, n)| n.clone()).expect("the current till is named");
            let server = server_report(fx, &teller, &cur.id).await;
            check(&mut d, "close preview expected cash", preview.expected_cash_minor, server.expected_cash_minor);
            check(&mut d, "till report", figures(&core.till_report().await.unwrap()), figures(&server));
        }
    }
    // The branch's tills of the last day, with their status.
    let device: BTreeMap<String, String> = core.list_tills().await.unwrap().into_iter().map(|t| (t.id, t.status)).collect();
    for r in fx
        .db
        .query("SELECT id, status::text FROM tills WHERE branch_id = $1 AND opened_at > now() - interval '1 day'", &[&branch])
        .await
        .unwrap()
    {
        let id = r.get::<_, uuid::Uuid>(0).to_string();
        check(&mut d, &format!("till {id} in the list"), device.get(&id).cloned(), Some(r.get::<_, String>(1)));
    }
    // Open bills, and each bill's detail.
    let bills = core.list_open_tickets().await.unwrap();
    let server: BTreeMap<String, i64> = fx
        .db
        .query("SELECT id, subtotal FROM open_tickets WHERE branch_id = $1 AND status = 'open'", &[&branch])
        .await
        .unwrap()
        .iter()
        .map(|r| (r.get::<_, uuid::Uuid>(0).to_string(), r.get::<_, i32>(1) as i64))
        .collect();
    check(&mut d, "open bills", bills.iter().map(|b| b.id.clone()).collect::<BTreeSet<_>>(), server.keys().cloned().collect());
    for (id, subtotal) in &server {
        match core.get_ticket(id.clone()).await {
            Ok(v) => check(&mut d, &format!("bill {id} subtotal"), v.subtotal_minor, *subtotal),
            Err(e) => d.push(format!("bill {id}: {e}")),
        }
    }
    // The kitchen board.
    let kds: BTreeSet<String> = core.kds_list(None).await.unwrap().into_iter().map(|t| t.id).collect();
    let server: BTreeSet<String> = fx
        .db
        .query(
            "SELECT id FROM kitchen_tickets WHERE branch_id = $1 AND closed_at IS NULL AND status::text <> 'voided'",
            &[&branch],
        )
        .await
        .unwrap()
        .iter()
        .map(|r| r.get::<_, uuid::Uuid>(0).to_string())
        .collect();
    check(&mut d, "kitchen board", kds, server);
    // The delivery queue as the screen asks for it.
    let queue: BTreeSet<String> =
        core.list_delivery_orders(Some(ACTIVE_DELIVERY.into())).await.unwrap().into_iter().map(|o| o.id).collect();
    let server: BTreeSet<String> = fx
        .db
        .query("SELECT id FROM delivery_orders WHERE branch_id = $1 AND status::text = ANY(string_to_array($2, ','))", &[&branch, &ACTIVE_DELIVERY])
        .await
        .unwrap()
        .iter()
        .map(|r| r.get::<_, uuid::Uuid>(0).to_string())
        .collect();
    check(&mut d, "delivery queue", queue, server);
    // Today's arrivals, in the branch's own day.
    let arrivals: BTreeSet<String> = core.list_arrivals().unwrap().into_iter().map(|b| b.id).collect();
    let server: BTreeSet<String> = fx
        .db
        .query(
            "WITH z AS (SELECT effective_timezone($1) AS tz),
                  day AS (SELECT (date_trunc('day', now() AT TIME ZONE z.tz)) AT TIME ZONE z.tz AS from_, \
                                 (date_trunc('day', now() AT TIME ZONE z.tz) + interval '1 day') AT TIME ZONE z.tz AS to_ FROM z)
             SELECT b.id FROM bookings b, day
              WHERE b.branch_id = $1 AND b.status::text IN ('confirmed', 'seated')
                AND b.starts_at < day.to_ AND b.ends_at > day.from_",
            &[&branch],
        )
        .await
        .unwrap()
        .iter()
        .map(|r| r.get::<_, uuid::Uuid>(0).to_string())
        .collect();
    check(&mut d, "arrivals", arrivals, server);
    d
}

/// Retry a parity pass while the device is still filling (a background fill
/// or a confirming pull lands a moment after convergence): the LAST pass is
/// the verdict, and every earlier difference is printed.
async fn verdict(label: &str, fx: &Fixture, core: &MadarCore, tills: &[(String, String)]) -> Vec<String> {
    let deadline = Instant::now() + Duration::from_secs(60);
    loop {
        let lines = server_parity(fx, core, tills).await;
        if lines.is_empty() || Instant::now() > deadline {
            for l in &lines {
                eprintln!("PARITY {label} DIFF: {l}");
            }
            eprintln!("PARITY {label}: {} differences", lines.len());
            return lines;
        }
        eprintln!("PARITY {label}: {} differences, reading again", lines.len());
        tokio::time::sleep(Duration::from_secs(3)).await;
    }
}

/// Every screen read once, timed: (read, milliseconds, served).
async fn read_latencies(core: &MadarCore, till: &str) -> Vec<(&'static str, f64, bool)> {
    let mut out = Vec::new();
    macro_rules! time {
        ($name:expr, $e:expr) => {{
            let t0 = Instant::now();
            let ok = $e.is_ok();
            out.push(($name, t0.elapsed().as_secs_f64() * 1e3, ok));
        }};
    }
    time!("list_till_orders", core.list_till_orders().await);
    time!("list_orders_for_till", core.list_orders_for_till(till.to_string()).await);
    time!("till_report", core.till_report().await);
    time!("till_report_for", core.till_report_for(till.to_string()).await);
    time!("list_cash_movements", core.list_cash_movements().await);
    time!("close_till_preview", core.close_till_preview().await);
    time!("list_tills", core.list_tills().await);
    time!("list_till_refunds", core.list_till_refunds(till.to_string()).await);
    time!("list_open_tickets", core.list_open_tickets().await);
    time!("kds_list", core.kds_list(None).await);
    time!("list_delivery_orders", core.list_delivery_orders(Some(ACTIVE_DELIVERY.into())).await);
    time!("list_arrivals", core.list_arrivals());
    time!("floor_layout", core.floor_layout());
    time!("list_menu_items", core.list_menu_items());
    time!("sync_status", Ok::<_, ()>(core.sync_status()));
    out
}

async fn seed_delivery_and_booking(fx: &Fixture) {
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    // A delivery order on this branch, copied from any existing one (fresh id).
    fx.db
        .execute(
            "INSERT INTO delivery_orders SELECT (jsonb_populate_record(NULL::delivery_orders, to_jsonb(d) || jsonb_build_object(
                'id', gen_random_uuid(), 'branch_id', $1::uuid, 'org_id', (SELECT org_id FROM branches WHERE id = $1),
                'status', 'received', 'order_id', NULL, 'idempotency_key', NULL, 'delivery_zone_id', NULL,
                'delivery_ref', 'PAR-' || substr(md5(random()::text), 1, 6), 'discount_id', NULL,
                'confirmed_at', NULL, 'preparing_at', NULL, 'ready_at', NULL, 'out_for_delivery_at', NULL,
                'delivered_at', NULL, 'cancelled_at', NULL, 'rejected_at', NULL, 'cancelled_by', NULL,
                'created_at', now(), 'updated_at', now()))).*
             FROM delivery_orders d ORDER BY d.created_at DESC LIMIT 1",
            &[&branch],
        )
        .await
        .expect("seed a delivery");
    fx.db
        .execute(
            "INSERT INTO bookings (org_id, branch_id, party_size, starts_at, ends_at, guest_name, guest_phone)
             SELECT org_id, id, 4, now() + interval '2 hours', now() + interval '4 hours', 'Parity Guest', '+201000000000'
               FROM branches WHERE id = $1",
            &[&branch],
        )
        .await
        .expect("seed a booking");
}

async fn fire(core: &MadarCore, qty: usize) -> String {
    let item = core.list_menu_items().unwrap().into_iter().find(|i| i.base_price_minor > 0).unwrap();
    for _ in 0..qty {
        core.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor).unwrap();
    }
    core.fire_ticket(None, Some("parity".into()), None, Some(2), None).await.expect("fire").ticket_id
}

async fn converge(core: &MadarCore) {
    settle(core, 300).await;
    // A second pass so realtime nudges and the confirming pull have landed.
    tokio::time::sleep(Duration::from_secs(1)).await;
    settle(core, 300).await;
}

async fn offline(core: &MadarCore, proxy: &Proxy) {
    proxy.offline();
    for _ in 0..3 {
        core.refresh_connectivity().await;
    }
    assert!(!core.sync_status().online);
}

#[tokio::test]
#[ignore]
async fn parity_one_device_online_offline_reconnect_close() {
    let fx = fixture(1).await;
    let teller = fx.tellers[0].1.clone();
    let proxy = Proxy::start(&fx.base).await;
    let db = temp_db("parity1");
    let core = core_at(&proxy.base, &db, &teller, &fx.branch).await;
    seed_delivery_and_booking(&fx).await;
    let till = core.open_till(10_000, Some("parity".into())).await.unwrap().till.unwrap().id;
    let cash = method(&core, true).unwrap();
    let card = method(&core, false);
    // Online day.
    sell(&core, 2, &cash, 1_000_000).await;
    if let Some(card) = &card {
        sell(&core, 1, card, 0).await;
    }
    core.record_cash_movement(2_000, "float".into(), Some("pay_in".into()), None).await.unwrap();
    fire(&core, 2).await;
    let t_void = fire(&core, 1).await;
    converge(&core).await;
    core.void_ticket(t_void.clone(), Some("customer_changed_mind".into())).await.unwrap();
    let synced: Vec<_> = core.list_till_orders().await.unwrap().into_iter().filter(|o| !o.queued).collect();
    core.refund_order(synced[0].id.clone(), synced[0].total_minor / 2, "cash".into(), "damaged".into(), None).await.unwrap();
    converge(&core).await;
    let named = vec![(till.clone(), teller.clone())];
    let mut bad = verdict("online", &fx, &core, &named).await;
    // The comparison is not vacuous: every board has something on it.
    let bills = core.list_open_tickets().await.unwrap().len();
    let kds = core.kds_list(None).await.unwrap().len();
    let deliveries = core.list_delivery_orders(Some("received".into())).await.unwrap().len();
    let arrivals = core.list_arrivals().unwrap().len();
    let refunds = core.list_till_refunds(till.clone()).await.unwrap().refund_count;
    eprintln!("PARITY coverage: bills {bills} kds {kds} deliveries {deliveries} arrivals {arrivals} refunds {refunds}");
    let newest = core.list_open_tickets().await.unwrap().last().map(|t| t.id.clone()).unwrap();
    let detail = core.get_ticket(newest).await;
    assert!(detail.is_ok(), "the bill detail read serves: {detail:?}");
    assert!(bills >= 1 && kds >= 1 && deliveries >= 1 && arrivals >= 1 && refunds >= 1, "every board is covered");

    // Offline: sales, a void, a refund, a pay-out, a fire.
    offline(&core, &proxy).await;
    let v = sell(&core, 1, &cash, 1_000_000).await;
    sell(&core, 3, &cash, 1_000_000).await;
    core.void_order(v, "customer_changed_mind".into(), None, false).await.unwrap();
    core.refund_order(synced[1 % synced.len()].id.clone(), 100, "cash".into(), "damaged".into(), None).await.unwrap();
    core.record_cash_movement(-700, "change run".into(), Some("pay_out".into()), None).await.unwrap();
    fire(&core, 1).await;
    // Offline every read answers at once from the rows, with the queue in it.
    let offline_orders = core.list_till_orders().await.unwrap();
    assert!(offline_orders.iter().filter(|o| o.queued).count() >= 2, "the queued sales are listed offline");
    for (read, ms, ok) in read_latencies(&core, &till).await {
        eprintln!("PARITY offline read {read}: {ms:.1} ms ok={ok}");
        assert!(ok, "{read} serves offline");
        assert!(ms < 1_000.0, "{read} waited on the network offline ({ms} ms)");
    }

    // Reconnect and drain.
    proxy.online();
    core.refresh_connectivity().await;
    converge(&core).await;
    bad.extend(verdict("reconnected", &fx, &core, &named).await);

    // Close, then the past till.
    close_with_count(&core).await;
    converge(&core).await;
    bad.extend(verdict("closed", &fx, &core, &named).await);
    let _ = std::fs::remove_file(&db);
    assert!(bad.is_empty(), "unexplained differences: {bad:#?}");
}

#[tokio::test]
#[ignore]
async fn parity_two_devices_and_a_backlog() {
    let fx = fixture(2).await;
    let (ta, tb) = (fx.tellers[0].1.clone(), fx.tellers[1].1.clone());
    let (pa, pb) = (Proxy::start(&fx.base).await, Proxy::start(&fx.base).await);
    let (da, dbp) = (temp_db("pa"), temp_db("pb"));
    let a = core_at(&pa.base, &da, &ta, &fx.branch).await;
    let b = core_at(&pb.base, &dbp, &tb, &fx.branch).await;
    let till_a = a.open_till(5_000, None).await.unwrap().till.unwrap().id;
    let till_b = b.open_till(7_000, None).await.unwrap().till.unwrap().id;
    let cash = method(&a, true).unwrap();
    sell(&a, 1, &cash, 1_000_000).await;
    offline(&b, &pb).await;
    for _ in 0..150 {
        sell(&b, 1, &cash, 1_000_000).await;
    }
    b.record_cash_movement(-500, "backlog pay-out".into(), Some("pay_out".into()), None).await.unwrap();
    fire(&a, 1).await;
    pb.online();
    b.refresh_connectivity().await;
    converge(&b).await;
    converge(&a).await;
    converge(&b).await;
    let tills = vec![(till_a.clone(), ta.clone()), (till_b.clone(), tb.clone())];
    let mut bad = verdict("device A", &fx, &a, &tills).await;
    bad.extend(verdict("device B", &fx, &b, &tills).await);
    close_with_count(&b).await;
    converge(&b).await;
    converge(&a).await;
    bad.extend(verdict("A after B closed", &fx, &a, &tills).await);
    let _ = std::fs::remove_file(&da);
    let _ = std::fs::remove_file(&dbp);
    assert!(bad.is_empty(), "unexplained differences: {bad:#?}");
}

#[tokio::test]
#[ignore]
async fn parity_fresh_device_past_till_before_and_after_first_snapshot() {
    let fx = fixture(1).await;
    let teller = fx.tellers[0].1.clone();
    // The newest closed till the copied branch already has (before this device existed).
    let past: Option<uuid::Uuid> = fx
        .db
        .query_opt(
            "SELECT id FROM tills WHERE branch_id = $1 AND status <> 'open' ORDER BY opened_at DESC LIMIT 1",
            &[&uuid::Uuid::parse_str(&fx.branch).unwrap()],
        )
        .await
        .unwrap()
        .map(|r| r.get(0));
    let past: Vec<(String, String)> = past.into_iter().map(|u| (u.to_string(), teller.clone())).collect();
    let db = temp_db("fresh");
    let core = signed_in(&fx.base, &db, &teller, &fx.branch).await;
    core.refresh_connectivity().await;
    core.refresh_catalog().await.unwrap();
    // Before the first snapshot every board answers at once with what exists
    // (nothing yet), and the sync status says the branch is still coming.
    let t0 = Instant::now();
    assert!(core.list_open_tickets().await.is_ok() && core.kds_list(None).await.is_ok() && core.list_arrivals().is_ok());
    assert!(core.list_delivery_orders(Some(ACTIVE_DELIVERY.into())).await.is_ok() && core.list_tills().await.is_ok());
    eprintln!("PARITY before first snapshot: boards in {:.1} ms, freshness {:?}", t0.elapsed().as_secs_f64() * 1e3, core.sync_status().freshness.state);
    assert!(t0.elapsed() < Duration::from_secs(1), "no board waits for the snapshot");
    core.sync_full().await.unwrap();
    converge(&core).await;
    let bad = verdict("after first snapshot", &fx, &core, &past).await;
    let _ = std::fs::remove_file(&db);
    assert!(bad.is_empty(), "unexplained differences: {bad:#?}");
}
