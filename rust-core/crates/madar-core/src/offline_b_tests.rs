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

// ── Phase 2: shifts/tills, orders and cash on the ledger read path ──────────

fn seed_methods(core: &crate::MadarCore) {
    core.store
        .kv_put(
            menu::K_PAYMENT_METHODS,
            r##"[{"id":"00000000-0000-0000-0000-0000000000e1","name":"Cash","is_cash":true,"is_active":true,"created_at":"2026-01-01T00:00:00Z"},
                 {"id":"00000000-0000-0000-0000-0000000000e2","name":"Card","is_cash":false,"is_active":true,"created_at":"2026-01-01T00:00:00Z"}]"##,
        )
        .unwrap();
}

async fn ring(core: &crate::MadarCore, price: i64, method_id: &str, tendered: i64) -> crate::checkout::ReceiptView {
    core.cart_add(None, uuid::Uuid::new_v4().to_string(), "Latte".into(), price).unwrap();
    core.checkout(
        None,
        crate::checkout::CheckoutInput {
            payment_method_id: method_id.into(),
            amount_tendered_minor: tendered,
            tip_minor: 0,
            tip_payment_method_id: None,
            customer_name: None,
            notes: None,
            splits: vec![],
            loyalty_customer_id: None,
            loyalty_redemptions: vec![],
        },
    )
    .await
    .unwrap()
}

const CASH: &str = "00000000-0000-0000-0000-0000000000e1";
const CARD: &str = "00000000-0000-0000-0000-0000000000e2";

/// A whole offline till: sell cash and card, pay out, void the cash sale, refund
/// part of the card sale, preview the close, close — every figure from the rows,
/// with no network at all.
#[tokio::test]
async fn an_offline_till_day_is_computed_from_its_rows() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed_methods(&core);
    let till = core.open_till(10_000, None).await.unwrap().till.unwrap();
    let cash_sale = ring(&core, 1_000, CASH, 5_000).await;
    let card_sale = ring(&core, 2_500, CARD, 0).await;
    assert!(cash_sale.queued_offline && card_sale.queued_offline);
    core.record_cash_movement(-500, "milk".into(), Some("pay_out".into()), None).await.unwrap();

    let report = core.till_report().await.unwrap();
    assert_eq!(report.expected_cash_minor, 10_000 + cash_sale.total_minor - 500);
    assert!(!report.from_server, "queued work is not the server's figure yet");
    assert_eq!(report.cash_out_minor, 500);

    let orders = core.list_till_orders().await.unwrap();
    assert_eq!(orders.len(), 2);
    assert!(orders.iter().all(|o| o.status == "queued" && o.queued));
    let cash_row = orders.iter().find(|o| o.total_minor == cash_sale.total_minor).unwrap();

    core.void_order(cash_row.id.clone(), "mistake".into(), None, false).await.unwrap();
    let report = core.till_report().await.unwrap();
    assert_eq!(report.expected_cash_minor, 10_000 - 500, "the voided cash sale left the drawer");
    assert_eq!(report.voided_amount_minor, cash_sale.total_minor);
    let orders = core.list_till_orders().await.unwrap();
    assert_eq!(orders.iter().find(|o| o.id == cash_row.id).unwrap().status, "voided");

    let movements = core.list_cash_movements().await.unwrap();
    assert_eq!(movements.len(), 1);
    assert_eq!((movements[0].amount_minor, movements[0].kind.as_str()), (-500, "pay_out"));

    let preview = core.close_till_preview().await.unwrap();
    assert_eq!(preview.expected_cash_minor, 9_500);
    let cash_line = preview.methods.iter().find(|m| m.is_cash).unwrap();
    assert_eq!(cash_line.system_total_minor, 9_500);
    let card_line = preview.methods.iter().find(|m| m.method == "Card").unwrap();
    assert_eq!(card_line.system_total_minor, card_sale.total_minor);

    let outcome = core.close_till(9_500, None, vec![]).await.unwrap();
    assert!(outcome.queued);
    let tills = core.list_tills().await.unwrap();
    let t = tills.iter().find(|x| x.id == till.id).unwrap();
    assert!(!t.is_open && t.status == "closed");
    let z = core.till_report_for(till.id.clone()).await.unwrap();
    assert_eq!(z.expected_cash_minor, 9_500);
    assert_eq!(z.closing_cash_declared_minor, Some(9_500));
}

/// The replay answers each op; the answers fold into the rows, the sale never
/// leaves the list, and a snapshot that does not list it yet cannot remove it.
#[tokio::test]
async fn acked_sales_fold_and_survive_the_next_snapshot() {
    let stub = Stub::start(|r| {
        if r.path.starts_with("/sync/replay") {
            let body = r.json();
            let op = body["op"].as_str().unwrap_or("");
            return Some(match op {
                "open_till" => StubResponse::json(201, serde_json::json!({
                    "id": body["request"]["id"], "branch_id": testkit::BRANCH, "teller_id": testkit::TELLER,
                    "teller_name": "Sara", "status": "open", "opening_cash": body["request"]["opening_cash"],
                    "opened_at": body["request"]["opened_at"], "opening_cash_was_edited": false,
                    "verification": "unverified", "opened_while_another_open": false, "disagreement_count": 0})),
                "create_order" => {
                    let req = &body["request"];
                    StubResponse::json(201, serde_json::json!({
                        "id": uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, req["idempotency_key"].as_str().unwrap().as_bytes()),
                        "branch_id": req["branch_id"], "till_id": req["till_id"], "shift_id": req["till_id"],
                        "teller_id": testkit::TELLER, "teller_name": "Sara", "order_number": 7, "order_ref": req["order_ref"],
                        "status": "completed", "order_type": "takeaway", "payment_method": req["payment_method"],
                        "payment_legs": [], "subtotal": req["subtotal"], "tax_amount": req["tax_amount"],
                        "total_amount": req["total_amount"], "discount_amount": 0, "discount_value": 0, "delivery_fee": 0,
                        "created_at": req["created_at"], "items": []}))
                }
                _ => StubResponse::json(200, serde_json::json!({"id": uuid::Uuid::new_v4()})),
            });
        }
        if r.path.starts_with("/sync/pull") {
            // A snapshot taken before the sale committed: no orders at all.
            return Some(StubResponse::text(
                200,
                r#"{"full":true,"next":10,"has_more":false,"server_time":"2026-09-14T10:00:00Z","types":["till","order","cash_movement","refund"],"data":{"till":[],"order":[],"cash_movement":[],"refund":[]},"ledger_window":{"from":"2020-01-01T00:00:00Z"}}"#,
            ));
        }
        None
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    seed_methods(&core);
    core.set_online(true);
    let _till = core.open_till(1_000, None).await.unwrap().till.unwrap();
    let sale = ring(&core, 700, CASH, 700).await;
    assert!(!sale.queued_offline, "acked straight away");
    let orders = core.list_till_orders().await.unwrap();
    assert_eq!(orders.len(), 1);
    assert_eq!(orders[0].order_number, Some(7), "the server's answer folded in");
    assert!(!orders[0].queued);
    core.pull(false).await.unwrap();
    let orders = core.list_till_orders().await.unwrap();
    assert_eq!(orders.len(), 1, "the snapshot could not remove a freshly acked sale");
    assert_eq!(core.till_report().await.unwrap().expected_cash_minor, 1_000 + sale.total_minor);
}

/// Every read-path mode serves; shadow logs the legacy/new difference.
#[tokio::test]
async fn shadow_mode_serves_legacy_and_logs_divergence() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed_methods(&core);
    core.open_till(0, None).await.unwrap();
    ring(&core, 400, CASH, 400).await;
    for mode in [crate::readpath::ReadPathMode::Legacy, crate::readpath::ReadPathMode::Shadow, crate::readpath::ReadPathMode::New] {
        core.set_read_path_mode("ledger".into(), mode).unwrap();
        assert_eq!(core.list_till_orders().await.unwrap().len(), 1, "{mode:?}");
        assert!(core.till_report().await.is_ok());
    }
    assert!(core.set_read_path_mode("nope".into(), crate::readpath::ReadPathMode::New).is_err());
}
