//! OFFLINE_B cross-repo integration: the REAL `MadarCore` against the REAL backend
//! (built from the backend worktree), through a proxy the test can cut to take
//! the device offline mid-session — the same core, the same store, no second
//! "dead-url" core standing in for the network going away.
//!
//! Ignored by `cargo test` (it needs a backend and a database). Run it with ONE
//! command, which builds the backend, copies a local database, starts the server,
//! runs these scenarios, and tears everything down:
//!
//! ```sh
//! tool/offline_b_backend.sh            # from the madar repo root
//! ```
//!
//! What it proves:
//! * an offline till day (sales, a void, a refund of a synced sale, a pay-in, the
//!   close) computes the SAME figures locally as the server's Z report, before and
//!   after the backlog lands;
//! * two devices at one branch converge: each holds the other's till with the
//!   server's figures, from the changefeed alone;
//! * a 1000+ sale offline backlog drains completely, exactly once, and the
//!   device's report equals the server's afterwards.

mod common;

use common::*;
use std::time::{Duration, Instant};
// ---------------------------------------------------------------------------

#[tokio::test]
#[ignore]
async fn an_offline_till_day_reports_what_the_server_reports() {
    let fx = fixture(1).await;
    let teller = fx.tellers[0].1.clone();
    let proxy = Proxy::start(&fx.base).await;
    let db = temp_db("day");
    let core = core_at(&proxy.base, &db, &teller, &fx.branch).await;

    let opened = core.open_till(10_000, Some("offline-b integration".into())).await.expect("open");
    let till_id = opened.till.expect("a till").id;
    let cash = method(&core, true).expect("a cash method");
    let card = method(&core, false);

    // Online: one sale that lands, so there is a synced sale to refund later.
    sell(&core, 2, &cash, 1_000_000).await;
    settle(&core, 120).await;
    let synced = core
        .list_till_orders()
        .await
        .expect("orders")
        .into_iter()
        .find(|o| !o.queued)
        .expect("the online sale is on the till");

    // Offline.
    proxy.offline();
    for _ in 0..3 {
        core.refresh_connectivity().await;
    }
    let voided = sell(&core, 1, &cash, 1_000_000).await;
    sell(&core, 3, &cash, 1_000_000).await;
    if let Some(card) = &card {
        sell(&core, 2, card, 0).await;
    }
    core.void_order(voided, "customer_changed_mind".into(), None, false).await.expect("void queues");
    core.refund_order(synced.id.clone(), synced.total_minor / 2, "cash".into(), "damaged".into(), None)
        .await
        .expect("refund queues");
    core.record_cash_movement(1_500, "float top-up".into(), Some("pay_in".into()), None)
        .await
        .expect("pay-in queues");
    let status = core.sync_status();
    assert!(!status.online, "the device knows it is offline: {status:?}");
    assert!(status.pending_outbox >= 5, "the day is queued: {status:?}");
    assert_eq!(status.dead_outbox, 0);
    let offline_open = figures(&core.till_report().await.expect("offline report"));
    let before_close = close_with_count(&core).await;
    assert_eq!(figures(&before_close), offline_open);

    // Back online: the backlog lands exactly once.
    proxy.online();
    core.refresh_connectivity().await;
    settle(&core, 120).await;
    let s = core.sync_status();
    assert_eq!((s.pending_outbox, s.dead_outbox), (0, 0), "{s:?}");

    let local = core.till_report_for(till_id.clone()).await.expect("local report");
    let server = server_report(&fx, &teller, &till_id).await;
    let mut want = figures(&server);
    eprintln!("DAY server figures: {want:?}");
    assert_eq!(figures(&local), want, "the device's closed-till report is the server's");
    // Before the close the drawer said what the server now says (bar the count).
    want.insert("closing_declared".into(), -1);
    assert_eq!(offline_open, want, "the offline figures were already right");
    assert!(!server.is_open);
    let expected_orders = if card.is_some() { 4 } else { 3 };
    assert_eq!(server_orders_on_till(&fx, &till_id).await, expected_orders, "no sale landed twice");
    let _ = std::fs::remove_file(&db);
}

#[tokio::test]
#[ignore]
async fn two_devices_converge_on_each_others_tills() {
    let fx = fixture(2).await;
    let (ta, tb) = (fx.tellers[0].1.clone(), fx.tellers[1].1.clone());
    let (pa, pb) = (Proxy::start(&fx.base).await, Proxy::start(&fx.base).await);
    let (da, dbp) = (temp_db("a"), temp_db("b"));
    let a = core_at(&pa.base, &da, &ta, &fx.branch).await;
    let b = core_at(&pb.base, &dbp, &tb, &fx.branch).await;

    let till_a = a.open_till(5_000, Some("device A".into())).await.unwrap().till.unwrap().id;
    let till_b = b.open_till(7_000, Some("device B".into())).await.unwrap().till.unwrap().id;
    let cash = method(&a, true).unwrap();

    // Both go offline and trade; A also pays out.
    pa.offline();
    pb.offline();
    for _ in 0..3 {
        a.refresh_connectivity().await;
        b.refresh_connectivity().await;
    }
    for _ in 0..4 {
        sell(&a, 1, &cash, 1_000_000).await;
    }
    for _ in 0..6 {
        sell(&b, 2, &cash, 1_000_000).await;
    }
    a.record_cash_movement(-800, "change run".into(), Some("pay_out".into()), None).await.unwrap();

    // Each device's own drawer is right before anyone reconnects.
    let a_offline = figures(&a.till_report().await.unwrap());
    let b_offline = figures(&b.till_report().await.unwrap());

    // B comes back first, then A; then each pulls again to see the other.
    pb.online();
    b.refresh_connectivity().await;
    settle(&b, 120).await;
    pa.online();
    a.refresh_connectivity().await;
    settle(&a, 120).await;
    settle(&b, 120).await;

    let srv_a = figures(&server_report(&fx, &ta, &till_a).await);
    let srv_b = figures(&server_report(&fx, &tb, &till_b).await);
    assert_eq!(a_offline, srv_a, "A's offline drawer");
    assert_eq!(b_offline, srv_b, "B's offline drawer");
    assert_eq!(figures(&a.till_report_for(till_b.clone()).await.unwrap()), srv_b, "A holds B's till");
    assert_eq!(figures(&b.till_report_for(till_a.clone()).await.unwrap()), srv_a, "B holds A's till");
    let a_tills: Vec<String> = a.list_tills().await.unwrap().into_iter().map(|t| t.id).collect();
    assert!(a_tills.contains(&till_b), "B's till is in A's list");

    // Close both; the closes cross over too.
    close_with_count(&a).await;
    close_with_count(&b).await;
    settle(&a, 120).await;
    settle(&b, 120).await;
    settle(&a, 120).await;
    let srv_b = figures(&server_report(&fx, &tb, &till_b).await);
    assert_eq!(figures(&a.till_report_for(till_b).await.unwrap()), srv_b, "A holds B's closed till");
    let _ = std::fs::remove_file(&da);
    let _ = std::fs::remove_file(&dbp);
}

#[tokio::test]
#[ignore]
async fn a_thousand_sale_backlog_drains_exactly_once() {
    const N: usize = 1_000;
    let fx = fixture(1).await;
    let teller = fx.tellers[0].1.clone();
    let proxy = Proxy::start(&fx.base).await;
    let db = temp_db("backlog");
    let core = core_at(&proxy.base, &db, &teller, &fx.branch).await;
    let till_id = core.open_till(20_000, Some("backlog".into())).await.unwrap().till.unwrap().id;
    let cash = method(&core, true).unwrap();

    proxy.offline();
    for _ in 0..3 {
        core.refresh_connectivity().await;
    }
    let t0 = Instant::now();
    for _ in 0..N {
        sell(&core, 1, &cash, 1_000_000).await;
    }
    let ring = t0.elapsed();
    core.record_cash_movement(2_500, "mid-day float".into(), Some("pay_in".into()), None).await.unwrap();
    let s = core.sync_status();
    assert!(!s.online);
    assert!(s.pending_outbox as usize > N, "{s:?}");
    let t0 = Instant::now();
    let offline_report = figures(&core.till_report().await.unwrap());
    let report_ms = t0.elapsed();

    proxy.online();
    core.refresh_connectivity().await;
    let t0 = Instant::now();
    settle(&core, 900).await;
    let drain = t0.elapsed();
    let s = core.sync_status();
    assert_eq!((s.pending_outbox, s.dead_outbox), (0, 0), "{s:?}");
    assert!(s.freshness.state == "fresh", "{s:?}");

    assert_eq!(server_orders_on_till(&fx, &till_id).await, N as i64, "every sale exactly once");
    let server = figures(&server_report(&fx, &teller, &till_id).await);
    assert_eq!(offline_report, server, "the offline drawer with 1000 queued sales was the server's");
    assert_eq!(figures(&core.till_report().await.unwrap()), server, "and still is after the drain");
    eprintln!(
        "BACKLOG N={N}: ring {:.1}s ({:.1} ms/sale), offline report {} ms, drain+confirm {:.1}s",
        ring.as_secs_f64(),
        ring.as_secs_f64() * 1000.0 / N as f64,
        report_ms.as_millis(),
        drain.as_secs_f64()
    );
    let _ = tokio::time::timeout(Duration::from_secs(1), close_with_count(&core)).await;
    let _ = std::fs::remove_file(&db);
}
