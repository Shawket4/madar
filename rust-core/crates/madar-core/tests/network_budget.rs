//! The network budget against the REAL backend: reads never touch the network.
//!
//! Ignored by `cargo test`. Run with the backend harness:
//!
//! ```sh
//! MADAR_OB_TESTS=network_budget tool/offline_b_backend.sh
//! MADAR_NB_IDLE_SECS=600 MADAR_OB_TESTS=network_budget tool/offline_b_backend.sh   # the full 10 minutes
//! ```
//!
//! Every request the core makes goes through the counting proxy
//! (`common::take_requests`, by route). The rule (madar/CLAUDE.md "The network
//! rule"): the network is used only for the changefeed pull, the outbox replay,
//! the realtime stream, `/health`, asset downloads and sign-in. Everything a
//! screen shows comes from the local rows.
//!
//! * `an_idle_online_till_only_syncs` — a signed-in till with an open till, the
//!   realtime stream up, idle for `MADAR_NB_IDLE_SECS` (default 120) while every
//!   screen re-reads each 10 s (the table watcher's fallback beat, the worst
//!   case): only the allowed routes, and a bounded number of pulls.
//! * `walking_every_screen_reads_nothing_from_the_server` — every screen read
//!   and every screen-entry refresh the app makes, twice: zero requests beyond
//!   the allowed list.
//! * `an_offline_cold_start_reads_and_acts` — after the first snapshot the cable
//!   is pulled and the app restarts: every screen loads with data and every
//!   action (sell, void, refund, cash movement, fire, settle, close, open)
//!   succeeds and queues.

mod common;

use std::collections::BTreeMap;
use std::time::{Duration, Instant};

use common::*;
use madar_core::MadarCore;

/// Routes a device may use, by prefix of `METHOD /path` (ids normalised).
const ALLOWED: &[&str] = &[
    "POST /sync/pull",
    "POST /sync/replay",
    "GET /health",
    "GET /realtime",
    "GET /events",
    "GET /assets/",
    "GET /asset-bundles",
    "GET /files/",
    "POST /auth/login",
    "POST /auth/refresh",
    "GET /auth/permissions",
    "GET /orgs/:id/offline-auth-bundle",
    // Sign-in: which modules the org has on (the till hides Dawam when off).
    "GET /orgs/:id/modules",
];

fn allowed(route: &str) -> bool {
    ALLOWED.iter().any(|p| route.starts_with(p))
}

/// Background FILLS of what the feed cannot give (a past till this device does
/// not hold completely: its sales and its report; the past-till history backfill).
/// Allowed once per exact request per session — a repeat is a poll.
const FILL_ONCE: &[&str] = &["GET /orders", "GET /tills/:id/report", "GET /tills/branches/:id"];
/// Against a backend older than `sync_feed_branch_reads` the branch settings its
/// feed row lacks are filled the same way. Against a newer one they are not
/// allowed at all.
const LEGACY_SETTINGS_FILLS: &[&str] =
    &["GET /kitchen/routing-mode", "GET /kitchen/stations", "GET /delivery/settings", "GET /loyalty/settings"];

static LEGACY_FEED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Does the backend's feed lack the branch reads? (Its database has no
/// `loyalty_settings` emitter.) Decides whether the legacy fills are allowed.
async fn detect_feed(fx: &Fixture) {
    let has: bool = fx
        .db
        .query_one("SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'sync_emit_loyalty_settings')", &[])
        .await
        .unwrap()
        .get(0);
    LEGACY_FEED.store(!has, std::sync::atomic::Ordering::SeqCst);
    eprintln!("== backend feed: {}", if has { "carries the branch reads" } else { "older (branch reads filled once)" });
}

fn fill_route(route: &str) -> bool {
    FILL_ONCE.contains(&route)
        || (LEGACY_FEED.load(std::sync::atomic::Ordering::SeqCst) && LEGACY_SETTINGS_FILLS.contains(&route))
}

/// Exact fill requests asked more than once.
fn repeated_fills(raw: &BTreeMap<String, usize>) -> Vec<String> {
    raw.iter()
        .filter(|(r, n)| **n > 1 && fill_route(&route_of(&format!("{r} HTTP/1.1"))))
        .map(|(r, n)| format!("{n} × {r}"))
        .collect()
}

fn report(label: &str, counts: &BTreeMap<String, usize>) {
    eprintln!("== requests: {label}");
    for (route, n) in counts {
        let tag = if allowed(route) {
            ""
        } else if fill_route(route) {
            "   (one-off fill)"
        } else {
            "   <-- NOT ALLOWED"
        };
        eprintln!("   {n:>6}  {route}{tag}");
    }
}

fn forbidden(counts: &BTreeMap<String, usize>) -> Vec<String> {
    counts.iter().filter(|(r, _)| !allowed(r) && !fill_route(r)).map(|(r, n)| format!("{n} × {r}")).collect()
}

struct Quiet;
impl madar_core::realtime::EventListener for Quiet {
    fn on_event(&self, _: madar_core::realtime::RealtimeEvent) {}
    fn on_connection_changed(&self, _: bool) {}
}
impl madar_core::realtime::RealtimePlayer for Quiet {
    fn play_ping(&self) {}
    fn post_notification(&self, _: String, _: String, _: String) {}
    fn haptic(&self) {}
}

/// Every screen read the app makes, with the refreshes its screens run on
/// entry and on a table change. Errors are tolerated (a screen that has nothing
/// to show); the network they cause is what is measured.
async fn walk_screens(core: &MadarCore) {
    // Sell / order screen entry.
    let _ = core.refresh_till().await;
    let _ = core.list_till_orders().await;
    let _ = core.list_open_tickets().await;
    let _ = core.floor_layout();
    let _ = core.refresh_floor().await;
    let _ = core.kitchen_routing_mode().await;
    let _ = core.loyalty_settings().await;
    // Bills / queue.
    let _ = core.list_open_tickets_synced().await;
    let _ = core.list_delivery_orders(None).await;
    let _ = core.list_delivery_orders_synced(None).await;
    let _ = core.delivery_settings().await;
    let _ = core.list_arrivals();
    // Till, report, close preview, drawer.
    let _ = core.check_till_elsewhere().await;
    let _ = core.branch_open_tills().await;
    let _ = core.till_report().await;
    let _ = core.list_cash_movements().await;
    let _ = core.close_till_preview().await;
    let _ = core.open_bills_notice().await;
    // History.
    if let Ok(tills) = core.list_tills().await {
        for t in tills.iter().take(3) {
            let _ = core.list_orders_for_till(t.id.clone()).await;
            let _ = core.till_report_for(t.id.clone()).await;
            let _ = core.list_till_refunds(t.id.clone()).await;
        }
    }
    if let Ok(orders) = core.list_till_orders().await {
        for o in orders.iter().take(3) {
            let _ = core.list_order_refunds(o.id.clone()).await;
        }
    }
    // KDS.
    let _ = core.kds_list_stations().await;
    let _ = core.kds_list(None).await;
    let _ = core.kds_list_synced(None).await;
    // Settings / sync chrome.
    let _ = core.sync_status();
}

async fn day_start(fx: &Fixture, proxy: &Proxy, tag: &str) -> (std::sync::Arc<MadarCore>, String) {
    let db = temp_db(tag);
    let core = core_at(&proxy.base, &db, &fx.tellers[0].1, &fx.branch).await;
    core.open_till(10_000, Some("network budget".into())).await.expect("open");
    let cash = method(&core, true).expect("a cash method");
    for _ in 0..3 {
        sell(&core, 1, &cash, 100_000).await;
    }
    settle(&core, 60).await;
    (core, db)
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore]
async fn walking_every_screen_reads_nothing_from_the_server() {
    let fx = fixture(1).await;
    detect_feed(&fx).await;
    let proxy = Proxy::start(&fx.base).await;
    let (core, _db) = day_start(&fx, &proxy, "nb_walk").await;
    // Let the first snapshot's one-off follow-ups (history backfill, the
    // asset bundle) finish before counting.
    tokio::time::sleep(Duration::from_secs(5)).await;
    take_requests();
    take_raw_requests();
    walk_screens(&core).await;
    tokio::time::sleep(Duration::from_secs(3)).await;
    walk_screens(&core).await;
    tokio::time::sleep(Duration::from_secs(5)).await;
    let counts = take_requests();
    report("walking every screen twice", &counts);
    let bad = forbidden(&counts);
    assert!(bad.is_empty(), "screen reads reached the server: {bad:?}");
    let again = repeated_fills(&take_raw_requests());
    assert!(again.is_empty(), "a background fill repeated: {again:?}");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore]
async fn an_idle_online_till_only_syncs() {
    let idle: u64 = std::env::var("MADAR_NB_IDLE_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(120);
    let fx = fixture(1).await;
    detect_feed(&fx).await;
    let proxy = Proxy::start(&fx.base).await;
    let (core, _db) = day_start(&fx, &proxy, "nb_idle").await;
    core.start_realtime(Box::new(Quiet), Box::new(Quiet)).await.expect("realtime");
    tokio::time::sleep(Duration::from_secs(5)).await;
    take_requests();
    take_raw_requests();
    let end = Instant::now() + Duration::from_secs(idle);
    while Instant::now() < end {
        // The table watcher's fallback beat: every board re-reads.
        walk_screens(&core).await;
        tokio::time::sleep(Duration::from_secs(10)).await;
    }
    let counts = take_requests();
    let raw = take_raw_requests();
    report(&format!("idle online for {idle} s"), &counts);
    let bad = forbidden(&counts);
    assert!(bad.is_empty(), "an idle till reached the server beyond sync: {bad:?}");
    let again = repeated_fills(&raw);
    assert!(again.is_empty(), "a background fill repeated: {again:?}");
    // The history walk opens three past tills: at most one sales fill and one
    // report fill each, over the whole idle period.
    for fill in ["GET /orders", "GET /tills/:id/report"] {
        assert!(counts.get(fill).copied().unwrap_or(0) <= 3, "{fill}: {counts:?}");
    }
    // A live stream with nothing changing: no fallback poll. Allow the stream's
    // own reconnect nudges, one a minute at most.
    let pulls = counts.get("POST /sync/pull").copied().unwrap_or(0);
    assert!(pulls as u64 <= 2 + idle / 60, "{pulls} pulls in {idle} s idle");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore]
async fn an_offline_cold_start_reads_and_acts() {
    let fx = fixture(1).await;
    detect_feed(&fx).await;
    let proxy = Proxy::start(&fx.base).await;
    let teller = fx.tellers[0].1.clone();
    let (core, db) = day_start(&fx, &proxy, "nb_cold").await;
    let paid = core.list_till_orders().await.expect("orders");
    assert!(paid.len() >= 3, "the day's sales are held");
    core.set_manual_scheduling(true);
    drop(core);

    proxy.offline();
    take_requests();
    let core = MadarCore::new(madar_core::MadarConfig {
        base_url: proxy.base.clone(),
        environment: "dev".into(),
        db_path: db.clone(),
        locale: "en".into(),
        app_version: None,
    })
    .expect("core");
    let s = core
        .sign_in(madar_core::session::LoginRequest {
            mode: madar_core::session::LoginMode::Pin,
            name: Some(teller.clone()),
            pin: Some("1234".into()),
            branch_id: Some(fx.branch.clone()),
            email: None,
            password: None,
            org_id: None,
        })
        .await
        .expect("offline sign-in");
    assert!(!s.online);

    // Every screen loads with data, at once.
    let t0 = Instant::now();
    walk_screens(&core).await;
    assert!(t0.elapsed() < Duration::from_secs(10), "screens waited on the network: {:?}", t0.elapsed());
    let till = core.current_till().expect("till").expect("the open till is held");
    assert!(till.is_open);
    assert!(core.list_till_orders().await.expect("orders").len() >= 3);
    assert!(!core.list_menu_items().expect("menu").is_empty());
    core.till_report().await.expect("report");
    core.close_till_preview().await.expect("close preview");
    assert!(!core.list_tills().await.expect("tills").is_empty());
    core.kitchen_routing_mode().await.expect("routing mode");
    core.kds_list(None).await.expect("kds");
    core.list_delivery_orders(None).await.expect("delivery");
    core.loyalty_settings().await.expect("loyalty settings");

    // Every action works and queues.
    let cash = method(&core, true).expect("cash");
    let sold = sell(&core, 2, &cash, 100_000).await;
    let orders = core.list_till_orders().await.unwrap();
    let voided = sell(&core, 1, &cash, 100_000).await;
    core.void_order(voided, "customer_changed_mind".into(), None, false).await.expect("void queues");
    let refundable = orders.iter().find(|o| o.id != sold && o.total_minor > 0).expect("a sale to refund");
    core.refund_order(refundable.id.clone(), refundable.total_minor / 2, "cash".into(), "damaged".into(), None)
        .await
        .expect("refund queues");
    core.record_cash_movement(1_500, "float".into(), Some("pay_in".into()), None).await.expect("cash movement");
    let item = core.list_menu_items().unwrap().into_iter().find(|i| i.base_price_minor > 0).unwrap();
    core.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor).unwrap();
    let fired = core.fire_ticket(None, Some("walk-in".into()), None, None, None, None).await.expect("fire queues");
    let settled = core
        .settle_ticket(
            fired.ticket_id.clone(),
            till.id.clone(),
            cash.clone(),
            Some(100_000),
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
        .await;
    settled.expect("settle queues");
    let queued = core.sync_status().pending_outbox;
    assert!(queued >= 5, "the actions queued: {queued}");
    close_with_count(&core).await;
    assert!(core.current_till().unwrap().map(|t| !t.is_open).unwrap_or(true));
    core.open_till(5_000, Some("reopen offline".into())).await.expect("open queues");
    walk_screens(&core).await;
    let counts = take_requests();
    report("offline cold start (refused connections)", &counts);

    // The offline cold start asked nothing of the network (the cable was out:
    // anything it tried is a refused connection, and screens must not wait on it).
    let bad = forbidden(&counts);
    assert!(bad.is_empty(), "the offline screens tried the server: {bad:?}");

    for item in core.list_outbox().unwrap_or_default() {
        eprintln!("QUEUED {} {} {}", item.op_type, item.id, item.status);
    }
    // Back online: the teller signs in again (an offline unlock holds no token),
    // everything drains and nothing dead-letters.
    proxy.online();
    let deadline = Instant::now() + Duration::from_secs(120);
    loop {
        match core
            .sign_in(madar_core::session::LoginRequest {
                mode: madar_core::session::LoginMode::Pin,
                name: Some(teller.clone()),
                pin: Some("1234".into()),
                branch_id: Some(fx.branch.clone()),
                email: None,
                password: None,
                org_id: None,
            })
            .await
        {
            Ok(s) if s.online => break,
            other => {
                assert!(Instant::now() < deadline, "online sign-in: {other:?}");
                tokio::time::sleep(Duration::from_secs(3)).await;
            }
        }
    }
    // Anything the server refuses is named before `settle` fails on it.
    let _ = core.sync_now().await;
    tokio::time::sleep(Duration::from_secs(5)).await;
    for item in core.list_outbox().unwrap_or_default().iter().filter(|i| i.status == "dead") {
        eprintln!("DEAD {item:?}");
    }
    settle(&core, 180).await;
}
