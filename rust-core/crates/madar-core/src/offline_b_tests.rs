//! Offline plan B scenario tests (OFFLINE_B_DESIGN), phase by phase. Each one
//! drives the real `MadarCore` against the `testkit` stub server.

use std::sync::atomic::Ordering;
use std::time::Duration;

use crate::testkit::{self, Stub, StubResponse};
use crate::{changes, menu, store};

// ── Phase 0: store foundations + the quick fixes ────────────────────────────

/// A payment-methods 403 and a discounts 500 during a catalog refresh leave
/// both mirrors exactly as they were; the rest of the catalog still commits.
#[tokio::test]
async fn a_partial_catalog_failure_never_wipes_payment_methods_or_discounts() {
    let stub = Stub::start(|r| {
        let p = r.path.as_str();
        if p.starts_with("/menu-items") || p.starts_with("/addon-items") || p.starts_with("/categories") {
            Some(StubResponse::text(200, "[]"))
        } else if p.starts_with("/bundles") {
            Some(StubResponse::text(200, r#"{"data":[],"page":1,"per_page":500,"total":0,"total_pages":0}"#))
        } else if p.starts_with("/payment-methods") {
            Some(StubResponse::text(403, r#"{"error":"forbidden"}"#))
        } else if p.starts_with("/discounts") {
            Some(StubResponse::text(500, r#"{"error":"boom"}"#))
        } else {
            None
        }
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    let methods = r#"[{"id":"00000000-0000-0000-0000-00000000c001","name":"cash","is_cash":true,"is_active":true}]"#;
    let discounts = r#"[{"id":"00000000-0000-0000-0000-00000000d001","name":"Staff","type":"percentage","value":10}]"#;
    core.store.kv_put(menu::K_PAYMENT_METHODS, methods).unwrap();
    core.store.kv_put(menu::K_DISCOUNTS, discounts).unwrap();
    core.store.kv_put(menu::K_MENU_ITEMS, r#"[{"stale":true}]"#).unwrap();

    core.refresh_catalog().await.expect("the required streams answered");

    assert_eq!(core.store.kv_get(menu::K_PAYMENT_METHODS).unwrap().as_deref(), Some(methods));
    assert_eq!(core.store.kv_get(menu::K_DISCOUNTS).unwrap().as_deref(), Some(discounts));
    assert_eq!(core.store.kv_get(menu::K_MENU_ITEMS).unwrap().as_deref(), Some("[]"), "the rest committed");
}

/// The catalog commit is one transaction: a failure on the last row rolls
/// back every row before it.
#[test]
fn catalog_kv_rows_commit_all_or_nothing() {
    let s = store::Store::open("").unwrap();
    s.kv_put("catalog:a", "old-a").unwrap();
    s.with_conn(|c| {
        c.execute_batch(
            "CREATE TRIGGER refuse_b BEFORE INSERT ON kv WHEN NEW.k = 'catalog:b'
             BEGIN SELECT RAISE(ABORT, 'disk full'); END;",
        )?;
        Ok(())
    })
    .unwrap();
    assert!(s.kv_put_many(&[("catalog:a", "new-a"), ("catalog:b", "new-b")]).is_err());
    assert_eq!(s.kv_get("catalog:a").unwrap().as_deref(), Some("old-a"), "rolled back");
    assert!(s.kv_get("catalog:b").unwrap().is_none());
}

/// The backlog must not mask a dead network: with every queued op inside its
/// backoff gate a drain sends nothing, so failed probes still count and the
/// banner goes offline after the confirm threshold.
#[tokio::test]
async fn a_gated_backlog_does_not_hold_the_online_flag_up() {
    let core = testkit::online_core("http://127.0.0.1:1", "").await;
    core.set_online(true);
    core.store
        .enqueue(&store::NewOutboxOp {
            id: "gated".into(),
            op_type: "cash_movement".into(),
            idempotency_key: "gated".into(),
            payload: "{}".into(),
            event_at: "2026-09-14T10:00:00Z".into(),
            user_id: Some(testkit::TELLER.into()),
            ..Default::default()
        })
        .unwrap();
    let seq = core.store.list_active().unwrap()[0].seq;
    core.store
        .mark_retry_no_count(seq, chrono::Utc::now().timestamp_millis() + 3_600_000)
        .unwrap();

    assert!(core.refresh_connectivity().await, "one blip is tolerated");
    assert!(!core.refresh_connectivity().await, "two blips with nothing sendable → offline");
    assert_eq!(core.sends_attempted.load(Ordering::Relaxed), 0, "nothing was sent");
}

/// A pull that fails for want of a network is connectivity evidence too.
#[tokio::test]
async fn failed_pulls_count_toward_offline_and_a_good_pull_restores_online() {
    let core = testkit::online_core("http://127.0.0.1:1", "").await;
    core.set_online(true);
    let _ = core.pull(false).await;
    assert!(core.current_session().unwrap().online, "one failure tolerated");
    let _ = core.pull(false).await;
    assert!(!core.current_session().unwrap().online);
    let status = core.sync_status();
    assert_eq!(status.freshness.state, "bootstrapping");
    assert_eq!(status.freshness.reason.as_deref(), Some("offline"));
}

#[test]
fn freshness_follows_the_stream_row() {
    use crate::sync_pull::{freshness, record_pull_outcome, K_LAST_FULL};
    let s = store::Store::open("").unwrap();
    let b = testkit::BRANCH;
    let now = 1_000_000_000i64;
    assert_eq!(freshness(&s, b, false, now).reason.as_deref(), Some("never_synced"));
    s.kv_put(&format!("{K_LAST_FULL}{b}"), "2026-09-14T10:00:00Z").unwrap();
    record_pull_outcome(&s, b, Ok(()), now);
    assert_eq!(freshness(&s, b, false, now + 1_000).state, "fresh");
    assert_eq!(freshness(&s, b, false, now + 61_000).state, "stale", "a quiet minute ages it");
    assert_eq!(freshness(&s, b, true, now + 600_000).state, "fresh", "a live stream keeps it fresh");
    let unauth = crate::error::CoreError::Unauthenticated { detail: "401".into() };
    record_pull_outcome(&s, b, Err(&unauth), now + 2_000);
    let f = freshness(&s, b, true, now + 2_000);
    assert_eq!((f.state.as_str(), f.reason.as_deref()), ("stale", Some("auth_expired")));
    let forbidden = crate::error::CoreError::Server { status: 403, code: "FORBIDDEN".into(), detail: String::new() };
    record_pull_outcome(&s, b, Err(&forbidden), now + 3_000);
    assert_eq!(freshness(&s, b, false, now + 3_000).reason.as_deref(), Some("forbidden"));
}

/// Realtime events nudge exactly one debounced pull; a dropped stream starts
/// the core's fallback poll.
#[tokio::test]
async fn realtime_events_nudge_one_debounced_pull_and_a_drop_starts_the_poll() {
    let stub = Stub::start(|r| {
        r.path.starts_with("/sync/pull").then(|| {
            StubResponse::text(
                200,
                r#"{"full":true,"next":5,"has_more":false,"server_time":"2026-09-14T10:00:00Z","types":[],"data":{}}"#,
            )
        })
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    struct Nop;
    impl crate::realtime::EventListener for Nop {
        fn on_event(&self, _: crate::realtime::RealtimeEvent) {}
        fn on_connection_changed(&self, _: bool) {}
    }
    let l = crate::scheduler::SyncNudgeListener {
        inner: std::sync::Arc::new(Nop),
        core: std::sync::Arc::downgrade(&core),
        connected: core.realtime_connected.clone(),
    };
    use crate::realtime::EventListener;
    for _ in 0..5 {
        l.on_event(crate::realtime::RealtimeEvent { event_type: "order.created".into(), data: "{}".into() });
    }
    tokio::time::sleep(crate::scheduler::NUDGE_DEBOUNCE + Duration::from_millis(400)).await;
    assert_eq!(stub.requests("/sync/pull").len(), 1, "five events, one pull");
    l.on_connection_changed(false);
    assert!(core.scheduler.poll_running.load(Ordering::SeqCst));
    assert!(!core.realtime_live());
}

#[tokio::test]
async fn enqueue_and_pull_outcomes_notify_subscribers() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    let mut sub = core.store.subscribe_changes();
    core.store
        .enqueue(&store::NewOutboxOp {
            id: "x".into(),
            op_type: "cash_movement".into(),
            idempotency_key: "x".into(),
            payload: "{}".into(),
            event_at: "t".into(),
            ..Default::default()
        })
        .unwrap();
    let got = sub.next(Duration::from_millis(5)).await.unwrap();
    assert!(got.contains(&changes::OUTBOX.to_string()) && got.contains(&changes::CASH_MOVEMENTS.to_string()));
}
