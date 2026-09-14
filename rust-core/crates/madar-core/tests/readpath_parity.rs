//! Read-path parity against the REAL backend: every screen read the core
//! serves, computed by the local rows and by a REFERENCE, after realistic days
//! (online, offline, reconnect, two devices, a drained backlog, voids, refunds,
//! cash movements, a close, a past till, a device before its first snapshot).
//!
//! Ignored by `cargo test`. Run with the backend harness:
//!
//! ```sh
//! MADAR_OB_TESTS=readpath_parity tool/offline_b_backend.sh
//! ```
//!
//! The reference is the legacy read of the same core (flag flipped per read),
//! so both see the same outbox and the same moment. Every difference is either
//! a bug in the local read (fixed) or an explained legacy fault, listed in
//! [`explained`] with the reason. Anything else fails the scenario.

mod common;

use std::collections::BTreeMap;
use std::fmt::Debug;
use std::time::Duration;

use common::*;
use madar_core::readpath::{ReadPathMode, AREAS};
use madar_core::MadarCore;

/// Turn every quoted RFC 3339 instant in a Debug dump into epoch millis, so
/// `+00:00` vs `Z` and sub-second spelling are not differences.
fn norm(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(i) = rest.find('"') {
        out.push_str(&rest[..=i]);
        rest = &rest[i + 1..];
        let Some(j) = rest.find('"') else { break };
        let inner = &rest[..j];
        match chrono::DateTime::parse_from_rfc3339(inner) {
            Ok(d) => out.push_str(&format!("@{}", d.timestamp_millis())),
            Err(_) => out.push_str(inner),
        }
        out.push('"');
        rest = &rest[j + 1..];
    }
    out.push_str(rest);
    out
}

fn dump<T: Debug>(v: &T) -> Vec<String> {
    norm(&format!("{v:#?}")).lines().map(|l| l.trim().to_string()).collect()
}

/// Line-level difference of two values: what only one side says.
fn diff_value<T: Debug>(what: &str, reference: &T, local: &T) -> Vec<String> {
    let (a, b) = (dump(reference), dump(local));
    if a == b {
        return Vec::new();
    }
    // Field lines only one side has (a multiset difference, so one changed
    // field reads as one line, not as every line after it).
    let count = |v: &[String]| {
        let mut m: BTreeMap<String, i64> = BTreeMap::new();
        for l in v {
            *m.entry(l.clone()).or_default() += 1;
        }
        m
    };
    let (ca, cb) = (count(&a), count(&b));
    let mut out = Vec::new();
    for (l, n) in &ca {
        if cb.get(l).copied().unwrap_or(0) < *n {
            out.push(format!("{what}: legacy `{l}`"));
        }
    }
    for (l, n) in &cb {
        if ca.get(l).copied().unwrap_or(0) < *n {
            out.push(format!("{what}: new `{l}`"));
        }
    }
    if out.is_empty() {
        out.push(format!("{what}: same fields in a different order"));
    }
    out.truncate(12);
    out
}

fn diff_keyed<T: Debug>(what: &str, reference: &[T], local: &[T], key: impl Fn(&T) -> String) -> Vec<String> {
    let a: BTreeMap<String, &T> = reference.iter().map(|x| (key(x), x)).collect();
    let b: BTreeMap<String, &T> = local.iter().map(|x| (key(x), x)).collect();
    let mut out = Vec::new();
    for (k, x) in &a {
        match b.get(k) {
            None => out.push(format!("{what}: {k} only in legacy")),
            Some(y) => out.extend(diff_value(&format!("{what}[{k}]"), x, y)),
        }
    }
    for k in b.keys().filter(|k| !a.contains_key(*k)) {
        out.push(format!("{what}: {k} only in new"));
    }
    // Same members in a different order is a difference too (screens list them).
    if out.is_empty() {
        let (ka, kb): (Vec<_>, Vec<_>) = (reference.iter().map(&key).collect(), local.iter().map(&key).collect());
        if ka != kb {
            out.push(format!("{what}: order legacy {ka:?} new {kb:?}"));
        }
    }
    out
}

fn set_all(core: &MadarCore, mode: ReadPathMode) {
    for a in AREAS {
        core.set_read_path_mode(a.to_string(), mode).unwrap();
    }
}

/// Read once with the legacy path and once with the local one.
macro_rules! both {
    ($core:expr, $call:expr) => {{
        set_all($core, ReadPathMode::Legacy);
        let l = $call.await;
        set_all($core, ReadPathMode::New);
        let n = $call.await;
        (l, n)
    }};
}

fn res<T: Debug>(what: &str, pair: (Result<T, madar_core::error::CoreError>, Result<T, madar_core::error::CoreError>), f: impl Fn(&T, &T) -> Vec<String>) -> Vec<String> {
    match pair {
        (Ok(l), Ok(n)) => f(&l, &n),
        (Err(l), Err(n)) => {
            if std::mem::discriminant(&l) == std::mem::discriminant(&n) {
                Vec::new()
            } else {
                vec![format!("{what}: legacy error {l} new error {n}")]
            }
        }
        (Ok(_), Err(e)) => vec![format!("{what}: new failed ({e}) where legacy served")],
        (Err(e), Ok(_)) => vec![format!("{what}: legacy failed ({e}) where new served")],
    }
}

/// Every shadowed read, legacy vs new, for the tills and sales named.
async fn parity(core: &MadarCore, tills: &[String], orders: &[String], tickets: &[String]) -> Vec<String> {
    let mut d = Vec::new();
    let _ = core.refresh_arrivals().await;
    d.extend(res("list_till_orders", both!(core, core.list_till_orders()), |l, n| {
        diff_keyed("till orders", l, n, |o| o.order_ref.clone().unwrap_or(o.id.clone()))
    }));
    for t in tills {
        d.extend(res("list_orders_for_till", both!(core, core.list_orders_for_till(t.clone())), |l, n| {
            diff_keyed(&format!("orders for {t}"), l, n, |o| o.order_ref.clone().unwrap_or(o.id.clone()))
        }));
        d.extend(res("till_report_for", both!(core, core.till_report_for(t.clone())), |l, n| {
            diff_value(&format!("report for {t}"), l, n)
        }));
        d.extend(res("list_till_refunds", both!(core, core.list_till_refunds(t.clone())), |l, n| {
            diff_value(&format!("till refunds {t}"), l, n)
        }));
    }
    d.extend(res("till_report", both!(core, core.till_report()), |l, n| diff_value("till report", l, n)));
    d.extend(res("list_cash_movements", both!(core, core.list_cash_movements()), |l, n| {
        diff_keyed("cash", l, n, |m| m.id.clone())
    }));
    d.extend(res("close_till_preview", both!(core, core.close_till_preview()), |l, n| diff_value("close preview", l, n)));
    d.extend(res("list_tills", both!(core, core.list_tills()), |l, n| diff_keyed("tills", l, n, |t| t.id.clone())));
    for o in orders {
        d.extend(res("list_order_refunds", both!(core, core.list_order_refunds(o.clone())), |l, n| {
            diff_value(&format!("order refunds {o}"), l, n)
        }));
    }
    d.extend(res("list_open_tickets", both!(core, core.list_open_tickets()), |l, n| {
        diff_keyed("open tickets", l, n, |t| t.id.clone())
    }));
    // The bill detail as a screen opens it: by the id the list gave.
    set_all(core, ReadPathMode::New);
    let listed: Vec<String> = core.list_open_tickets().await.map(|v| v.into_iter().map(|t| t.id).collect()).unwrap_or_default();
    for t in tickets.iter().chain(listed.iter().rev().take(6)) {
        d.extend(res("get_ticket", both!(core, core.get_ticket(t.clone())), |l, n| diff_value(&format!("ticket {t}"), l, n)));
    }
    d.extend(res("kds_list", both!(core, core.kds_list(None)), |l, n| diff_keyed("kds", l, n, |t| t.id.clone())));
    // The queue screen's own filter (incoming_provider.dart kActiveDeliveryStatuses).
    let active = Some("received,confirmed,preparing,ready,out_for_delivery".to_string());
    d.extend(res("list_delivery_orders", both!(core, core.list_delivery_orders(active.clone())), |l, n| {
        diff_keyed("delivery(active)", l, n, |o| o.id.clone())
    }));
    d.extend(res("list_delivery_orders(all)", both!(core, core.list_delivery_orders(None)), |l, n| {
        diff_keyed("delivery(all)", l, n, |o| o.id.clone())
    }));
    set_all(core, ReadPathMode::Legacy);
    let la = core.list_arrivals();
    set_all(core, ReadPathMode::New);
    let na = core.list_arrivals();
    d.extend(res("list_arrivals", (la, na), |l, n| diff_keyed("arrivals", l, n, |b| b.id.clone())));
    d
}

/// Differences with a known cause in the LEGACY read (the reference is wrong,
/// the local read is right). Each entry: a pattern and why.
fn explained(line: &str) -> Option<&'static str> {
    if line.contains("printed_at:") {
        return Some("the print time: each read stamps its own");
    }
    if line.starts_with("delivery(all): ") && line.ends_with("only in legacy") {
        return Some(
            "an unfiltered list: legacy pages the server's last 200 of any age; the feed keeps terminal \
             deliveries 48 h (sync_live_delivery). No screen reads it unfiltered",
        );
    }
    None
}

fn verdict(label: &str, lines: Vec<String>) -> Vec<String> {
    let mut unexplained = Vec::new();
    for l in lines {
        match explained(&l) {
            Some(why) => eprintln!("PARITY {label} explained: {l}  -- {why}"),
            None => {
                eprintln!("PARITY {label} DIFF: {l}");
                unexplained.push(l);
            }
        }
    }
    eprintln!("PARITY {label}: {} unexplained", unexplained.len());
    unexplained
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
    let t_open = fire(&core, 2).await;
    let t_void = fire(&core, 1).await;
    converge(&core).await;
    core.void_ticket(t_void.clone(), Some("customer_changed_mind".into())).await.unwrap();
    let synced: Vec<_> = core.list_till_orders().await.unwrap().into_iter().filter(|o| !o.queued).collect();
    let refunded = synced[0].id.clone();
    core.refund_order(refunded.clone(), synced[0].total_minor / 2, "cash".into(), "damaged".into(), None).await.unwrap();
    converge(&core).await;
    let orders: Vec<String> = synced.iter().map(|o| o.id.clone()).collect();
    let tickets = vec![t_open.clone(), t_void.clone()];
    let mut bad = verdict("online", parity(&core, &[till.clone()], &orders, &tickets).await);
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
    let t_off = fire(&core, 1).await;
    // Offline differences are reported, not gated: the legacy read serves a
    // cache that is stale by design while the local rows carry the queue.
    let _ = verdict("offline (informational)", parity(&core, &[till.clone()], &orders, &tickets).await);

    // Reconnect and drain.
    proxy.online();
    core.refresh_connectivity().await;
    converge(&core).await;
    let orders: Vec<String> = core.list_till_orders().await.unwrap().into_iter().map(|o| o.id).collect();
    let tickets = vec![t_open, t_void, t_off];
    bad.extend(verdict("reconnected", parity(&core, &[till.clone()], &orders, &tickets).await));

    // Close, then the past till.
    close_with_count(&core).await;
    converge(&core).await;
    bad.extend(verdict("closed", parity(&core, &[till.clone()], &orders, &tickets).await));
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
    let t = fire(&a, 1).await;
    pb.online();
    b.refresh_connectivity().await;
    converge(&b).await;
    converge(&a).await;
    converge(&b).await;
    let tills = vec![till_a.clone(), till_b.clone()];
    let mut bad = verdict("device A", parity(&a, &tills, &[], &[t.clone()]).await);
    bad.extend(verdict("device B", parity(&b, &tills, &[], &[t]).await));
    close_with_count(&b).await;
    converge(&b).await;
    converge(&a).await;
    bad.extend(verdict("A after B closed", parity(&a, &tills, &[], &[]).await));
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
    let past: Vec<String> = past.into_iter().map(|u| u.to_string()).collect();
    let db = temp_db("fresh");
    let core = signed_in(&fx.base, &db, &teller, &fx.branch).await;
    core.refresh_connectivity().await;
    core.refresh_catalog().await.unwrap();
    let mut bad = verdict("before first snapshot", parity(&core, &past, &[], &[]).await);
    core.sync_full().await.unwrap();
    converge(&core).await;
    bad.extend(verdict("after first snapshot", parity(&core, &past, &[], &[]).await));
    let _ = std::fs::remove_file(&db);
    assert!(bad.is_empty(), "unexplained differences: {bad:#?}");
}
