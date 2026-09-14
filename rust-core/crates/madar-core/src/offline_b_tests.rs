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
    let paced = crate::error::CoreError::Server { status: 429, code: "Too Many Requests".into(), detail: String::new() };
    record_pull_outcome(&s, b, Err(&paced), now + 4_000);
    let f = freshness(&s, b, false, now + 4_000);
    assert_eq!((f.reason.as_deref(), f.banner), (Some("throttled"), None), "pacing shows no banner");
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

/// A 429 from the replay route paces the drain: the op stays queued with its
/// retry budget intact, the pass stops, and the core resumes by itself once the
/// pause is over (the 1000-sale integration run dead-lettered every op past the
/// limiter's burst before this).
#[tokio::test]
async fn a_paced_drain_never_dead_letters_and_resumes_by_itself() {
    use std::sync::atomic::AtomicUsize;
    use std::sync::Arc;
    let refused = Arc::new(AtomicUsize::new(0));
    let r2 = refused.clone();
    let stub = Stub::start(move |r| {
        if r.path.starts_with("/sync/replay") {
            let body = r.json();
            // The first three sends are paced.
            if r2.fetch_add(1, Ordering::SeqCst) < 3 {
                return Some(StubResponse::json(429, serde_json::json!({"error": "Too many requests just now."})));
            }
            return Some(match body["op"].as_str().unwrap_or("") {
                "open_till" => StubResponse::json(201, serde_json::json!({
                    "id": body["request"]["id"], "branch_id": testkit::BRANCH, "teller_id": testkit::TELLER,
                    "teller_name": "Sara", "status": "open", "opening_cash": body["request"]["opening_cash"],
                    "opened_at": body["request"]["opened_at"], "opening_cash_was_edited": false,
                    "verification": "unverified", "opened_while_another_open": false, "disagreement_count": 0})),
                _ => StubResponse::json(200, serde_json::json!({"id": uuid::Uuid::new_v4()})),
            });
        }
        if r.path.starts_with("/sync/pull") {
            return Some(StubResponse::text(200, r#"{"full":true,"next":5,"has_more":false,"server_time":"2026-09-14T10:00:00Z","types":[],"data":{}}"#));
        }
        None
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    seed_methods(&core);
    core.set_online(true);
    core.open_till(1_000, None).await.unwrap();
    core.drain_outbox().await.unwrap();
    let s = core.sync_status();
    assert_eq!((s.pending_outbox, s.dead_outbox), (1, 0), "paced, not rejected: {s:?}");
    let attempts: i64 = core.store.with_conn(|c| Ok(c.query_row("SELECT attempts FROM outbox", [], |r| r.get(0))?)).unwrap();
    assert_eq!(attempts, 0, "pacing burns no retry budget");
    assert!(core.current_session().unwrap().online, "a paced server is reachable, not offline");
    // Nobody calls sync: the core's own resume nudges drain it.
    for _ in 0..60 {
        if core.sync_status().pending_outbox == 0 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(250)).await;
    }
    let s = core.sync_status();
    assert_eq!((s.pending_outbox, s.dead_outbox), (0, 0), "{s:?}");
    let sends = stub.requests("/sync/replay");
    assert_eq!(sends.len(), 4, "three paced sends, one that landed");
    assert!(sends.iter().all(|r| r.method == "POST"));
}

// ── Phases 3–4: the floor-side boards from the synced rows ──────────────────

fn seed_rows(core: &crate::MadarCore, rows: &[(&str, serde_json::Value)]) {
    core.store
        .with_conn(|c| {
            for (ty, v) in rows {
                c.execute(
                    "INSERT OR REPLACE INTO sync_rows(type,id,branch_id,seq,data) VALUES(?1,?2,?3,1,?4)",
                    rusqlite::params![ty, v["id"].as_str().unwrap(), testkit::BRANCH, v.to_string()],
                )?;
            }
            Ok(())
        })
        .unwrap();
    core.store
        .kv_put(&format!("{}{}", crate::sync_pull::K_LAST_FULL, testkit::BRANCH), "2026-09-14T08:00:00Z")
        .unwrap();
}

fn uid(label: &str) -> String {
    uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, label.as_bytes()).to_string()
}

/// With the rows synced and NO network at all, every board reads — bills with
/// this device's queued work applied, the kitchen per station, the delivery
/// queue by status with the synced prep minutes, today's arrivals.
#[tokio::test]
async fn the_boards_read_offline_from_the_synced_rows() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    let now = chrono::Utc::now();
    let bill = madar_api::models::OpenTicketView {
        id: uuid::Uuid::parse_str(&uid("bill-1")).unwrap(),
        status: "open".into(),
        subtotal: 4_200,
        opened_at: now.fixed_offset(),
        ..Default::default()
    };
    let mut settled_here = bill.clone();
    settled_here.id = uuid::Uuid::parse_str(&uid("bill-2")).unwrap();

    let station = uuid::Uuid::parse_str(&uid("grill")).unwrap();
    let line = madar_api::models::KitchenTicketItemView {
        id: uuid::Uuid::parse_str(&uid("kt-1-line")).unwrap(),
        station_id: Some(Some(station)),
        qty: 1,
        ..Default::default()
    };
    let kt = madar_api::models::KitchenTicketView {
        id: uuid::Uuid::parse_str(&uid("kt-1")).unwrap(),
        status: "open".into(),
        created_at: now.fixed_offset(),
        items: vec![line],
        ..Default::default()
    };
    let mut closed_kt = kt.clone();
    closed_kt.id = uuid::Uuid::parse_str(&uid("kt-2")).unwrap();
    closed_kt.closed_at = Some(Some(now.fixed_offset()));

    let delivery = |label: &str, status: &str| {
        serde_json::json!({"id": uid(label), "branch_id": testkit::BRANCH, "status": status, "channel": "pickup",
            "cart": {"lines": []}, "customer_name": "C", "customer_phone": "0100", "created_at": now.to_rfc3339(),
            "delivery_fee": 0, "extra_prep_minutes": 0, "otp_verified": true, "subtotal": 1000, "total": 1000})
    };
    let booking = |label: &str, status: &str, starts: chrono::DateTime<chrono::Utc>| {
        serde_json::json!({"id": uid(label), "branch_id": testkit::BRANCH, "status": status, "party_size": 2,
            "starts_at": starts.to_rfc3339(), "ends_at": (starts + chrono::Duration::hours(1)).to_rfc3339(),
            "held_from": (starts - chrono::Duration::minutes(15)).to_rfc3339(), "guest_name": "G", "guest_phone": "0101",
            "created_at": now.to_rfc3339(), "updated_at": now.to_rfc3339(), "locale": "en", "needs_table": false,
            "phone_verified": true, "source": "host", "table_ids": [], "table_labels": []})
    };
    core.store.kv_put(crate::checkout::KEY_BRANCH_TZ, "UTC").unwrap();
    seed_rows(
        &core,
        &[
            ("open_ticket", serde_json::to_value(&bill).unwrap()),
            ("open_ticket", serde_json::to_value(&settled_here).unwrap()),
            ("kitchen_ticket", serde_json::to_value(&kt).unwrap()),
            ("kitchen_ticket", serde_json::to_value(&closed_kt).unwrap()),
            ("delivery", delivery("d-new", "received")),
            ("delivery", delivery("d-done", "delivered")),
            ("booking", booking("b-today", "confirmed", now + chrono::Duration::minutes(5))),
            ("booking", booking("b-no-show", "confirmed", now + chrono::Duration::minutes(10))),
            ("booking", booking("b-tomorrow", "confirmed", now + chrono::Duration::days(2))),
            ("branch_settings", serde_json::json!({"id": testkit::BRANCH, "delivery_prep_minutes": 35})),
        ],
    );
    // This device settled one bill and marked one booking a no-show, both queued.
    core.store
        .enqueue(&store::NewOutboxOp {
            id: format!("{}:settle", uid("bill-2")),
            op_type: "settle_open_ticket".into(),
            idempotency_key: "s".into(),
            payload: serde_json::json!({"ticket_id": uid("bill-2"), "request": {}}).to_string(),
            event_at: now.to_rfc3339(),
            user_id: Some(testkit::TELLER.into()),
            ..Default::default()
        })
        .unwrap();
    core.no_show_booking(uid("b-no-show")).unwrap();

    let bills = core.list_open_tickets().await.unwrap();
    assert_eq!(bills.iter().map(|b| b.id.clone()).collect::<Vec<_>>(), vec![uid("bill-1")]);
    assert_eq!(core.get_ticket(uid("bill-1")).await.unwrap().subtotal_minor, 4_200);

    let all = core.kds_list(None).await.unwrap();
    assert_eq!(all.len(), 1, "a closed kitchen ticket is off the board");
    assert_eq!(core.kds_list(Some(station.to_string())).await.unwrap().len(), 1);
    assert_eq!(core.kds_list(Some(uid("bar"))).await.unwrap().len(), 0, "nothing for another station");

    let queue = core.list_delivery_orders(Some("received,confirmed".into())).await.unwrap();
    assert_eq!(queue.len(), 1);
    assert_eq!(core.list_delivery_orders(None).await.unwrap().len(), 2);
    assert_eq!(core.prep_minutes(), 35, "prep minutes from the synced branch settings");

    let arrivals = core.list_arrivals().unwrap();
    assert_eq!(arrivals.iter().map(|b| b.id.clone()).collect::<Vec<_>>(), vec![uid("b-today")]);

    let notice = core.open_bills_notice().await.unwrap().expect("one bill open");
    assert_eq!((notice.open_bills_count, notice.open_bills_amount_minor), (2, 8_400), "the notice counts the rows");
}

/// The gaps the feed now carries reach the till: the person's grants, the
/// branch-effective addons (a disabled one is not offered) and the prep minutes
/// — and a server that does not send addons yet leaves the fetched list alone.
#[tokio::test]
async fn permissions_addons_and_prep_minutes_arrive_with_the_feed() {
    let with_addons = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let flag = with_addons.clone();
    let stub = Stub::start(move |r| {
        if !r.path.starts_with("/sync/pull") {
            return None;
        }
        let mut types: Vec<&str> = crate::sync_pull::REQUIRED_TYPES.to_vec();
        let mut data = serde_json::Map::new();
        for t in &types {
            data.insert(t.to_string(), serde_json::json!([]));
        }
        data.insert("teller".into(), serde_json::json!([{"id": testkit::TELLER, "user_id": testkit::TELLER, "name": "Sara",
            "role": "teller", "is_active": true, "permissions": ["orders:create", "tills:update"], "seq": 3}]));
        data.insert("branch_settings".into(), serde_json::json!([{"id": testkit::BRANCH, "delivery_prep_minutes": 25, "seq": 4}]));
        if flag.load(std::sync::atomic::Ordering::SeqCst) {
            types.push("addon_item");
            data.insert("addon_item".into(), serde_json::json!([
                {"id": uid("oat"), "name": "Oat", "addon_type": "milk", "default_price": 1500, "is_active": true, "is_available": true, "ingredients": [], "seq": 5},
                {"id": uid("soy"), "name": "Soy", "addon_type": "milk", "default_price": 1200, "is_active": true, "is_available": false, "ingredients": [], "seq": 6}]));
        }
        Some(StubResponse::json(200, serde_json::json!({"full": true, "next": 9, "has_more": false,
            "server_time": "2026-09-14T10:00:00Z", "types": types, "data": data,
            "ledger_window": {"from": "2026-09-12T10:00:00Z"}})))
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    core.store.kv_put(menu::K_ADDONS, r#"[{"id":"fetched"}]"#).unwrap();
    assert!(core.has_permission("anything".into(), "at_all".into()), "an offline unlock is optimistic");
    core.pull(true).await.unwrap();
    assert!(core.has_permission("orders".into(), "create".into()));
    assert!(!core.has_permission("orders".into(), "delete".into()), "the feed's grants replace the optimistic gate");
    assert_eq!(core.store.kv_get(crate::K_DELIVERY_PREP_MINUTES).unwrap().as_deref(), Some("25"));
    assert_eq!(core.store.kv_get(menu::K_ADDONS).unwrap().as_deref(), Some(r#"[{"id":"fetched"}]"#), "no addon type: untouched");

    with_addons.store(true, std::sync::atomic::Ordering::SeqCst);
    core.pull(true).await.unwrap();
    let addons: Vec<serde_json::Value> = serde_json::from_str(&core.store.kv_get(menu::K_ADDONS).unwrap().unwrap()).unwrap();
    assert_eq!(addons.len(), 1, "the branch-disabled addon is not offered");
    assert_eq!(addons[0]["name"], "Oat");
    assert!(addons[0].get("is_available").is_none() && addons[0].get("seq").is_none());
}

/// The production parity guard: a quiescent, complete till whose figures differ
/// from the server's report is logged.
#[tokio::test]
async fn the_money_parity_guard_logs_a_difference() {
    let till_id = std::sync::Arc::new(std::sync::Mutex::new(String::new()));
    let tid = till_id.clone();
    let stub = Stub::start(move |r| {
        if r.path.contains("/report") {
            let id = tid.lock().unwrap().clone();
            let mut rep = serde_json::to_value(madar_api::models::TillReportResponse::default()).unwrap();
            rep["till"]["id"] = serde_json::json!(id);
            rep["till"]["branch_id"] = serde_json::json!(testkit::BRANCH);
            rep["till"]["status"] = serde_json::json!("open");
            rep["till"]["opening_cash"] = serde_json::json!(1_000);
            rep["expected_cash"] = serde_json::json!(999_999);
            rep["as_of_seq"] = serde_json::json!(40);
            return Some(StubResponse::json(200, rep));
        }
        None
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    seed_methods(&core);
    let till = core.open_till(1_000, None).await.unwrap().till.unwrap();
    *till_id.lock().unwrap() = till.id.clone();
    core.store.with_conn(|c| Ok(c.execute("UPDATE outbox SET status='acked'", [])?)).unwrap();
    core.store.with_conn(|c| Ok(c.execute("UPDATE ledger_tills SET acked=0", [])?)).unwrap();
    // The device has pulled up to the report's horizon.
    core.store.kv_put(&format!("{}{}", crate::sync_pull::K_NEXT, testkit::BRANCH), "40").unwrap();
    core.set_online(true);

    // Before any server report: the report is the device's own, and says so.
    let local = core.till_report().await.unwrap();
    assert!(!local.from_server, "computed here, not the server's");
    assert_eq!(local.expected_cash_minor, 1_000);

    core.money_parity_check().await;
    assert!(stub.requests(&format!("/tills/{}/report", till.id)).len() >= 1);
    assert!(core.recent_logs().iter().any(|l| l.message.contains("money") && l.message.contains("expected_cash")));
    // The mismatch switches the till's report to the server's.
    let served = core.till_report().await.unwrap();
    assert!(served.from_server);
    assert_eq!(served.expected_cash_minor, 999_999, "the server is the authority");
    // Rate-limited: a second check right away does not ask again.
    let asked = stub.requests("/tills/").len();
    core.money_parity_check().await;
    assert_eq!(stub.requests("/tills/").len(), asked);
    // A sale rung here since: the device holds more than the report → local again.
    let sale = ring(&core, 500, CASH, 1_000).await;
    let after = core.till_report().await.unwrap();
    assert!(!after.from_server);
    assert_eq!(after.expected_cash_minor, 1_000 + sale.total_minor);
}

/// Every field of the report is compared (not just the money totals), and a
/// closed till awaiting reconciliation is checked too.
#[tokio::test]
async fn the_parity_guard_compares_every_field_and_closed_unreviewed_tills() {
    let mk = |v: &mut crate::till::TillReportView| {
        v.teller_name = "Sara".into();
        v.opened_at = "2026-09-14T08:00:00Z".into();
    };
    let mut a = crate::till::TillReportView {
        teller_name: String::new(), opened_at: String::new(), closed_at: None, printed_at: "x".into(), is_open: true,
        expected_cash_minor: 0, opening_cash_minor: 0, opening_cash_was_edited: false, opening_cash_original_minor: None,
        opening_cash_edit_reason: None, closing_cash_declared_minor: None, total_payments_minor: 0, net_payments_minor: 0,
        voided_amount_minor: 0, refunds_issued_minor: 0, refunds_issued_cash_minor: 0, refunds_issued_count: 0,
        cash_in_refunded_sales_minor: 0, total_tax_minor: 0, total_service_charge_minor: 0, service_charge_waived_count: 0, service_charge_waived_minor: 0, cash_movements_net_minor: 0, cash_in_minor: 0, cash_out_minor: 0,
        payment_lines: vec![], cash_movements: vec![], from_server: false, device_code: None, order_number_first: None,
        order_number_last: None, reconciliation: vec![], old_bills_count: None, open_bills_count: None,
        opened_while_another_open: false, verification: "server".into(),
    };
    mk(&mut a);
    let mut b = a.clone();
    b.printed_at = "y".into();
    b.from_server = true;
    b.opened_at = "2026-09-14T10:00:00+02:00".into();
    let keyed = |v: &crate::till::TillReportView| crate::parity::report_keyed(v);
    assert!(crate::parity::diff_keyed("r", &keyed(&a), &keyed(&b)).is_empty(), "print time, side and offset spelling are not differences");
    for change in [
        |v: &mut crate::till::TillReportView| v.order_number_last = Some(9),
        |v: &mut crate::till::TillReportView| v.device_code = Some("36B".into()),
        |v: &mut crate::till::TillReportView| v.opening_cash_edit_reason = Some("r".into()),
        |v: &mut crate::till::TillReportView| v.open_bills_count = Some(2),
        |v: &mut crate::till::TillReportView| v.verification = "lan".into(),
        |v: &mut crate::till::TillReportView| v.cash_movements.push(crate::till::TillReportCashLine { amount_minor: 5, note: "n".into(), moved_by_name: "m".into(), created_at: "2026-09-14T09:00:00Z".into() }),
        |v: &mut crate::till::TillReportView| v.reconciliation.push(crate::till::ReconciliationLineView { method: "card".into(), label: "Card".into(), is_cash: false, system_total_minor: 1, status: "disagreed".into(), declared_amount_minor: Some(0), note: None, changed_after_close: false }),
    ] {
        let mut c = a.clone();
        change(&mut c);
        assert!(!crate::parity::diff_keyed("r", &keyed(&a), &keyed(&c)).is_empty(), "{c:?}");
    }

    let store = store::Store::open("").unwrap();
    store
        .with_tx(|tx| {
            for (id, status, recon, closed) in [
                ("open", "open", None, None),
                ("closed-unreviewed", "closed", Some("unreviewed"), Some(chrono::Utc::now().to_rfc3339())),
                ("closed-disagreed", "closed", Some("disagreed"), Some(chrono::Utc::now().to_rfc3339())),
                ("closed-clean", "closed", Some("clean"), Some(chrono::Utc::now().to_rfc3339())),
                ("closed-old", "closed", Some("unreviewed"), Some((chrono::Utc::now() - chrono::Duration::days(5)).to_rfc3339())),
            ] {
                crate::ledger::write_row(tx, crate::ledger::T_TILL, id, &serde_json::json!({"id": id, "branch_id": "B", "status": status,
                    "opened_at": (chrono::Utc::now() - chrono::Duration::days(6)).to_rfc3339(), "closed_at": closed,
                    "reconciliation_status": recon}), crate::ledger::Origin::Feed(1), None)?;
            }
            tx.execute("UPDATE ledger_tills SET complete=1", [])?;
            Ok(())
        })
        .unwrap();
    let mut got = crate::ledger::views::tills_to_check(&store).unwrap();
    got.sort();
    assert_eq!(got, vec!["closed-disagreed".to_string(), "closed-unreviewed".into(), "open".into()]);
}

/// LAN: a waiter's fire mirrored from a peer tablet shows on this device's
/// bills while the cloud is unreachable; the peer's settle clears it; the
/// mirror's arrival notifies the boards.
#[tokio::test]
async fn a_peers_mirrored_fire_and_settle_overlay_the_bills() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed_rows(&core, &[]);
    let mut sub = core.store.subscribe_changes();
    let ticket = uid("peer-ticket");
    let req = madar_api::models::CreateOpenTicketRequest {
        branch_id: uuid::Uuid::parse_str(testkit::BRANCH).unwrap(),
        idempotency_key: Some(Some(uuid::Uuid::parse_str(&ticket).unwrap())),
        ..Default::default()
    };
    let fire = serde_json::json!({"op": "fire_open_ticket", "teller_id": testkit::TELLER, "request": req});
    crate::mirror_replay_op(&core.store, &fire.to_string());
    let got = sub.next(Duration::from_millis(5)).await.unwrap();
    assert!(got.contains(&changes::OPEN_TICKETS.to_string()));
    let bills = core.list_open_tickets().await.unwrap();
    assert_eq!(bills.len(), 1);
    assert_eq!((bills[0].id.as_str(), bills[0].status.as_str()), (ticket.as_str(), "queued"));
    let settle = serde_json::json!({"op": "settle_open_ticket", "teller_id": testkit::TELLER, "ticket_id": ticket, "request": {}});
    crate::mirror_replay_op(&core.store, &settle.to_string());
    assert!(core.list_open_tickets().await.unwrap().is_empty(), "the peer settled it");
}

/// Discarding a dead sale removes its row with the op, in one transaction.
#[tokio::test]
async fn discarding_a_dead_sale_takes_its_row_with_it() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed_methods(&core);
    core.open_till(0, None).await.unwrap();
    let r = ring(&core, 900, CASH, 900).await;
    assert_eq!(core.till_report().await.unwrap().expected_cash_minor, r.total_minor);
    core.store.with_conn(|c| Ok(c.execute("UPDATE outbox SET status='dead' WHERE op_type='create_order'", [])?)).unwrap();
    assert_eq!(core.list_till_orders().await.unwrap()[0].status, "failed");
    assert!(core.discard_outbox_item(r.local_order_id.clone()).unwrap());
    assert!(core.list_till_orders().await.unwrap().is_empty());
    assert_eq!(core.till_report().await.unwrap().expected_cash_minor, 0);
}

#[tokio::test]
async fn watch_tables_delivers_coalesced_batches() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    let got = std::sync::Arc::new(std::sync::Mutex::new(Vec::<Vec<String>>::new()));
    let sink = got.clone();
    core.watch_tables(20, move |b| {
        sink.lock().unwrap().push(b);
        true
    })
    .unwrap();
    seed_methods(&core);
    core.open_till(0, None).await.unwrap();
    tokio::time::sleep(Duration::from_millis(80)).await;
    let batches = got.lock().unwrap().clone();
    assert!(!batches.is_empty());
    assert!(batches.iter().flatten().any(|t| t == changes::TILLS));
}

/// A void or refund reason the server would 400 without a note never queues
/// note-less: an unknown host key keeps its wording, a bare `other` is refused
/// at the till (found by the backend integration run: both dead-lettered).
#[test]
fn an_other_reason_always_reaches_the_server_with_a_note() {
    use crate::note_for_reason;
    assert_eq!(note_for_reason("customer_changed_mind", true, None).unwrap().as_deref(), Some("customer_changed_mind"));
    assert_eq!(note_for_reason("damaged", true, Some("  ".into())).unwrap().as_deref(), Some("damaged"));
    assert_eq!(note_for_reason("other", true, Some("spilt".into())).unwrap().as_deref(), Some("spilt"));
    assert!(note_for_reason("other", true, None).is_err());
    assert!(note_for_reason("", true, None).is_err());
    assert_eq!(note_for_reason("wrong_order", false, None).unwrap(), None);
}

/// A close never predates its own open, whatever the corrected clock says (the
/// server refuses one that does, which dead-lettered a quick close).
#[tokio::test]
async fn a_close_never_predates_its_open() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed_methods(&core);
    let till = core.open_till(1_000, None).await.unwrap().till.unwrap();
    // The offset is re-estimated a minute slow.
    core.clock_skew_secs.store(-60, Ordering::Relaxed);
    core.close_till(1_000, None, vec![]).await.unwrap();
    let payload: String = core
        .store
        .with_conn(|c| Ok(c.query_row("SELECT payload FROM outbox WHERE op_type='close_till'", [], |r| r.get(0))?))
        .unwrap();
    let v: serde_json::Value = serde_json::from_str(&payload).unwrap();
    let closed = chrono::DateTime::parse_from_rfc3339(v["request"]["closed_at"].as_str().unwrap()).unwrap();
    let opened = chrono::DateTime::parse_from_rfc3339(&till.opened_at).unwrap();
    assert!(closed >= opened, "closed {closed} before opened {opened}");
}

/// A paged full snapshot: page one brings state and the first ledger rows, the
/// device asks for page two with the cursor, and only when the LAST page is in
/// does it sweep ledger rows the snapshot never listed and move the cursor. A
/// failure between pages leaves the store as it was (nothing swept, cursor
/// unmoved) and the next pull starts the snapshot again.
#[tokio::test]
async fn a_paged_snapshot_sweeps_and_moves_the_cursor_only_after_its_last_page() {
    use std::sync::atomic::AtomicUsize;
    use std::sync::Arc;
    let fail_page_two = Arc::new(AtomicUsize::new(1));
    let fail = fail_page_two.clone();
    let till = uid("paged-till");
    let (t1, t2) = (till.clone(), till.clone());
    let order = move |label: &str, seq: i64| {
        serde_json::json!({"id": uid(label), "idempotency_key": uid(&format!("k-{label}")), "order_ref": format!("REF-{label}"),
            "branch_id": testkit::BRANCH, "till_id": t1, "status": "completed", "payment_method": "cash", "total_amount": 100,
            "created_at": chrono::Utc::now().to_rfc3339(), "payment_legs": [], "seq": seq})
    };
    let o2 = order.clone();
    let window = (chrono::Utc::now() - chrono::Duration::hours(48)).to_rfc3339();
    let stub = Stub::start(move |r| {
        if !r.path.starts_with("/sync/pull") {
            return None;
        }
        let body = r.json();
        assert!(!r.path.contains("since="), "a full pull");
        assert_eq!(body["ledger_page_size"], serde_json::json!(crate::sync_pull::LEDGER_PAGE_SIZE));
        let window = window.clone();
        let cursor = serde_json::json!({"horizon": 90, "window_from": window, "started_at": "2026-09-14T10:00:00Z", "after_seq": 60});
        let mut types: Vec<&str> = crate::sync_pull::REQUIRED_TYPES.iter().copied().filter(|t| !crate::ledger::is_ledger_type(t)).collect();
        if body["snapshot_cursor"].is_null() {
            let mut data = serde_json::Map::new();
            for t in &types {
                data.insert(t.to_string(), serde_json::json!([]));
            }
            data.insert("till".into(), serde_json::json!([{"id": t2, "branch_id": testkit::BRANCH, "teller_id": "u", "status": "open",
                "opening_cash": 0, "opened_at": chrono::Utc::now().to_rfc3339(), "seq": 10}]));
            data.insert("order".into(), serde_json::json!([order("a", 60)]));
            for t in ["cash_movement", "refund"] {
                data.insert(t.into(), serde_json::json!([]));
            }
            types.extend(["till", "order", "cash_movement", "refund"]);
            return Some(StubResponse::json(200, serde_json::json!({"full": true, "next": 90, "has_more": true, "server_time": "2026-09-14T10:00:00Z",
                "types": types, "data": data, "checksums": {}, "ledger_window": {"from": window}, "asset_bundle": null, "snapshot_cursor": cursor})));
        }
        assert_eq!(body["snapshot_cursor"], cursor, "page two names page one's cursor");
        if fail.load(Ordering::SeqCst) > 0 {
            fail.fetch_sub(1, Ordering::SeqCst);
            return Some(StubResponse::text(503, r#"{"error":"busy"}"#));
        }
        Some(StubResponse::json(200, serde_json::json!({"full": true, "next": 90, "has_more": false, "server_time": "2026-09-14T10:00:00Z",
            "types": ["till", "order", "cash_movement", "refund"], "data": {"till": [], "order": [o2("b", 70)], "cash_movement": [], "refund": []},
            "ledger_window": {"from": window}})))
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    // A sale the device held from before that the snapshot no longer lists.
    core.store
        .with_tx(|tx| {
            crate::ledger::write_row(tx, crate::ledger::T_ORDER, "stale", &serde_json::json!({"id": "stale", "idempotency_key": "stale",
                "order_ref": "REF-stale", "branch_id": testkit::BRANCH, "till_id": till, "status": "completed", "payment_method": "cash",
                "total_amount": 100, "created_at": chrono::Utc::now().to_rfc3339(), "payment_legs": []}), crate::ledger::Origin::Feed(3), None)?;
            Ok(())
        })
        .unwrap();
    let keys = |core: &crate::MadarCore| -> Vec<String> {
        core.store
            .with_conn(|c| {
                let mut st = c.prepare("SELECT order_ref FROM ledger_orders ORDER BY order_ref")?;
                let v = st.query_map([], |r| r.get(0))?.collect::<Result<Vec<String>, _>>()?;
                Ok(v)
            })
            .unwrap()
    };
    let cursor = |core: &crate::MadarCore| core.store.kv_get(&format!("{}{}", crate::sync_pull::K_NEXT, testkit::BRANCH)).unwrap();

    assert!(core.pull(true).await.is_err(), "page two failed");
    assert_eq!(keys(&core), vec!["REF-a".to_string(), "REF-stale".into()], "page one applied, nothing swept yet");
    assert_eq!(cursor(&core), None, "the cursor waits for the whole snapshot");

    core.pull(true).await.expect("the snapshot, both pages");
    assert_eq!(keys(&core), vec!["REF-a".to_string(), "REF-b".into()], "swept against every page, once");
    assert_eq!(cursor(&core).as_deref(), Some("90"));
    assert_eq!(stub.requests("/sync/pull").len(), 4);
}

/// A store written by a newer build opens read-only: its queue and data read
/// back, every write is refused (nothing this build would write lands in a shape
/// it does not know), and the freshness says why.
#[test]
fn a_store_from_a_newer_build_opens_read_only() {
    let path = std::env::temp_dir().join(format!("madar_newer_{}.sqlite", uuid::Uuid::new_v4().simple()));
    let path = path.to_string_lossy().into_owned();
    {
        let s = store::Store::open(&path).unwrap();
        s.kv_put("kept", "yes").unwrap();
        s.enqueue(&store::NewOutboxOp {
            id: "op-from-newer".into(),
            op_type: "create_order".into(),
            idempotency_key: "k".into(),
            payload: "{}".into(),
            event_at: "2026-09-14T10:00:00Z".into(),
            ..Default::default()
        })
        .unwrap();
        s.with_conn(|c| Ok(c.pragma_update(None, "user_version", crate::schema::latest() + 7)?)).unwrap();
    }
    let s = store::Store::open(&path).unwrap();
    assert!(s.future_schema());
    assert_eq!(s.kv_get("kept").unwrap().as_deref(), Some("yes"), "reads work");
    assert_eq!(s.pending_count().unwrap(), 1, "the newer build's queue is intact");
    assert!(s.kv_put("x", "y").is_err(), "writes are refused");
    assert!(s.enqueue(&store::NewOutboxOp { id: "mine".into(), op_type: "create_order".into(), idempotency_key: "m".into(),
        payload: "{}".into(), event_at: "t".into(), ..Default::default() }).is_err());
    let user_version: i64 = s.with_conn(|c| Ok(c.pragma_query_value(None, "user_version", |r| r.get(0))?)).unwrap();
    assert_eq!(user_version, crate::schema::latest() + 7, "not migrated backwards");
    let f = crate::sync_pull::freshness(&s, testkit::BRANCH, false, 0);
    assert_eq!((f.state.as_str(), f.reason.as_deref(), f.banner.as_deref()), ("stale", Some("newer_build"), Some("sync.store_newer_build")));
    drop(s);
    let _ = std::fs::remove_file(&path);
}

/// The transfers waitlist comes from the feed once the branch holds a snapshot:
/// rebuilt from the `table_transfer` rows (waiting only), a transfer this device
/// queued keeps its local state, the cursor is the feed's seq, and the old
/// wall-clock `GET /floor/transfers?since=` pull is not made.
#[tokio::test]
async fn the_transfers_waitlist_rides_the_feed_cursor() {
    let stub = Stub::start(|r| {
        if r.path.starts_with("/sync/pull") {
            return Some(StubResponse::text(503, r#"{"error":"not in this test"}"#));
        }
        None
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    let transfer = |label: &str, status: &str| {
        serde_json::json!({"id": uid(label), "branch_id": testkit::BRANCH, "occupant_kind": "held_order", "occupant_id": uid(&format!("o-{label}")),
            "status": status, "created_at": "2026-09-14T10:00:00Z", "updated_at": "2026-09-14T10:00:00Z"})
    };
    seed_rows(&core, &[("table_transfer", transfer("waiting", "waiting")), ("table_transfer", transfer("done", "fulfilled"))]);
    core.store.kv_put(&format!("{}{}", crate::sync_pull::K_NEXT, testkit::BRANCH), "321").unwrap();
    // A transfer this device created and has not drained yet.
    let local = crate::held::TransferWire {
        id: uid("mine"), branch_id: testkit::BRANCH.into(), occupant_kind: "held_order".into(), occupant_id: uid("o-mine"),
        occupant_label: None, from_table_id: None, target_section_id: None, target_table_id: None, note: None,
        status: "waiting".into(), created_at: "2026-09-14T09:00:00Z".into(), updated_at: String::new(),
    };
    core.store.kv_put(crate::held::K_TRANSFERS, &serde_json::to_string(&vec![local]).unwrap()).unwrap();
    core.store
        .enqueue(&store::NewOutboxOp {
            id: "tr-op".into(),
            op_type: "create_table_transfer".into(),
            idempotency_key: "tr-op".into(),
            payload: serde_json::json!({"transfer_id": uid("mine"), "request": {}}).to_string(),
            event_at: "2026-09-14T09:00:00Z".into(),
            ..Default::default()
        })
        .unwrap();

    core.project_pull_mirrors(testkit::BRANCH);
    let mut ids: Vec<String> = crate::held::load_transfers(&core.store).unwrap().into_iter().map(|t| t.id).collect();
    ids.sort();
    let mut want = vec![uid("mine"), uid("waiting")];
    want.sort();
    assert_eq!(ids, want, "waiting feed rows plus the queued local one; the fulfilled one is not waiting");
    assert_eq!(core.store.kv_get(crate::held::K_TRANSFERS_CURSOR).unwrap().as_deref(), Some("seq:321"));

    core.refresh_floor_and_held().await;
    assert!(stub.requests("/floor/transfers").is_empty(), "no wall-clock transfers pull once the feed carries them");
}

/// LAN multi-till: what a peer rang offline — a sale, its void, a movement, a
/// refund — arrives here as the exact replay envelope its drain would send, and
/// becomes the rows it stands for on the peer's till, held by the backup op.
#[tokio::test]
async fn a_peers_money_ops_become_held_rows_here() {
    let a = testkit::offline_core("http://127.0.0.1:1", "").await;
    let b = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed_methods(&a);
    seed_methods(&b);
    let till = a.open_till(2_000, None).await.unwrap().till.unwrap();
    let sale = ring(&a, 1_000, CASH, 2_000).await;
    a.record_cash_movement(-300, "change run".into(), Some("pay_out".into()), None).await.unwrap();
    let relay = |from: &crate::MadarCore, to: &crate::MadarCore, op_type: &str| {
        for item in from.store.pending().unwrap().into_iter().filter(|i| i.op_type == op_type) {
            let (env, _) = from.replay_envelope(&item).map_err(|_| "envelope").unwrap();
            crate::mirror_replay_op(&to.store, &env.to_string());
        }
    };
    relay(&a, &b, "create_order");
    relay(&a, &b, "cash_movement");
    let one = |core: &crate::MadarCore, q: &str| -> i64 { core.store.with_conn(|c| Ok(c.query_row(q, [], |r| r.get(0))?)).unwrap() };
    assert_eq!(one(&b, &format!("SELECT total_amount FROM ledger_orders WHERE okey='{}' AND till_id='{}'", sale.local_order_id, till.id)), sale.total_minor);
    assert_eq!(one(&b, &format!("SELECT COUNT(*) FROM ledger_payments WHERE okey='{}' AND is_cash=1", sale.local_order_id)), 1);
    assert_eq!(one(&b, &format!("SELECT amount FROM ledger_cash WHERE till_id='{}'", till.id)), -300);
    assert!(b.store.with_conn(|c| crate::ledger::is_protected(c, crate::ledger::T_ORDER, &sale.local_order_id)).unwrap(),
        "held by the backup until it lands");
    // A second copy of the same envelope changes nothing.
    relay(&a, &b, "create_order");
    assert_eq!(one(&b, "SELECT COUNT(*) FROM ledger_orders"), 1);
    assert_eq!(one(&b, "SELECT COUNT(*) FROM outbox WHERE op_type='lan_mirror'"), 2);

    // The peer voids the sale and refunds another synced one: both follow.
    a.void_order(sale.local_order_id.clone(), "wrong_order".into(), None, false).await.unwrap();
    relay(&a, &b, "void_order");
    assert_eq!(one(&b, &format!("SELECT status = 'voided' FROM ledger_orders WHERE okey='{}'", sale.local_order_id)), 1);
    let refund = serde_json::json!({"op": "refund_order", "teller_id": testkit::TELLER, "request": {
        "client_ref": uid("refund-1"), "order_id": uid("synced-sale"), "till_id": till.id, "amount": 250, "method": "Cash",
        "reason": "wrong_order", "issued_at": "2026-09-14T11:00:00Z"}});
    crate::mirror_replay_op(&b.store, &refund.to_string());
    assert_eq!(one(&b, &format!("SELECT amount FROM ledger_refunds WHERE rkey='{}' AND is_cash=1", uid("refund-1"))), 250);

    // A dead backup that the teller discards takes its row with it.
    b.store.with_conn(|c| Ok(c.execute("UPDATE outbox SET status='dead' WHERE op_type='lan_mirror' AND entity_type='cash_movement'", [])?)).unwrap();
    let dead = b.store.list_active().unwrap().into_iter().find(|i| i.status == "dead").unwrap();
    b.discard_outbox_item(dead.id.clone()).unwrap();
    assert_eq!(one(&b, "SELECT COUNT(*) FROM ledger_cash"), 0);
}

/// A peer's queued round and line void show on the bill here, re-priced, and a
/// round the server already lists is not added twice; this device's own queued
/// round shows too.
#[tokio::test]
async fn a_peers_rounds_and_line_voids_overlay_the_bill() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    let item = uid("latte");
    core.store
        .kv_put(crate::menu::K_MENU_ITEMS, &serde_json::json!([{"id": item, "org_id": testkit::ORG, "name": "Latte", "base_price": 500,
            "is_active": true, "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z"}]).to_string())
        .unwrap();
    let ticket = uid("bill");
    let line = uid("line-1");
    let bill = serde_json::json!({"id": ticket, "branch_id": testkit::BRANCH, "status": "open", "subtotal": 800, "opened_at": "2026-09-13T09:00:00Z",
        "opened_by": testkit::TELLER, "items": [{"id": line, "line": {"name": "Tea", "qty": 1}, "line_total": 800, "round_number": 1,
        "round_fired_at": "2026-09-13T09:00:00Z", "voided": false}],
        "bill": {"subtotal": 800, "discount_amount": 0, "service_charge_amount": 0, "tax_amount": 0, "total": 800, "tax_rate": 0.0,
                 "service_charge_rate": 0.0, "tax_inclusive": false}});
    seed_rows(&core, &[("open_ticket", bill)]);
    let round = serde_json::json!({"op": "add_ticket_round", "teller_id": testkit::TELLER, "ticket_id": ticket,
        "request": {"idempotency_key": uid("round-2"), "items": [{"menu_item_id": item, "quantity": 2, "unit_price": 500}]}});
    crate::mirror_replay_op(&core.store, &round.to_string());
    let bills = core.list_open_tickets().await.unwrap();
    let b = bills.iter().find(|t| t.id == ticket).unwrap();
    assert_eq!(b.lines.len(), 2);
    let added = b.lines.iter().find(|l| l.round_number == 2).expect("the peer's round");
    assert_eq!((added.name.as_str(), added.qty, added.line_total_minor), ("Latte", 2, 1_000));
    assert_eq!(b.subtotal_minor, 1_800);
    assert_eq!(b.bill.as_ref().unwrap().total_minor, 1_800, "re-priced through the bill engine");
    assert!(b.queued_offline);

    let void_line = serde_json::json!({"op": "void_ticket_line", "teller_id": testkit::TELLER, "ticket_id": ticket, "item_id": line, "request": {}});
    crate::mirror_replay_op(&core.store, &void_line.to_string());
    let b = core.list_open_tickets().await.unwrap().into_iter().find(|t| t.id == ticket).unwrap();
    assert!(b.lines.iter().find(|l| l.id == line).unwrap().voided, "the peer's line void shows");
    assert_eq!(b.subtotal_minor, 1_000);

    // This device's own queued round shows the same way.
    let own = crate::tickets::AddRoundCommand {
        ticket_id: ticket.clone(),
        round_id: uid("round-3"),
        request: crate::tickets::build_round_request(
            vec![madar_api::models::OrderItemInput { menu_item_id: Some(Some(uuid::Uuid::parse_str(&item).unwrap())), unit_price: Some(Some(500)), ..madar_api::models::OrderItemInput::new(1) }],
            uuid::Uuid::parse_str(&uid("round-3")).unwrap(),
        ),
    };
    core.store
        .enqueue(&store::NewOutboxOp { id: uid("round-3"), op_type: "ticket_add_round".into(), idempotency_key: uid("round-3"),
            payload: serde_json::to_string(&own).unwrap(), event_at: chrono::Utc::now().to_rfc3339(), ..Default::default() })
        .unwrap();
    let b = core.list_open_tickets().await.unwrap().into_iter().find(|t| t.id == ticket).unwrap();
    assert_eq!(b.lines.len(), 3);
    assert_eq!(b.subtotal_minor, 1_500);
    core.store.with_conn(|c| Ok(c.execute("DELETE FROM outbox WHERE op_type='ticket_add_round'", [])?)).unwrap();

    // The feed then lists the round (a round fired after it was queued): not twice.
    let fed = serde_json::json!({"id": ticket, "branch_id": testkit::BRANCH, "status": "open", "subtotal": 1_800, "opened_at": "2026-09-13T09:00:00Z",
        "opened_by": testkit::TELLER, "items": [
            {"id": line, "line": {"name": "Tea", "qty": 1}, "line_total": 800, "round_number": 1, "round_fired_at": "2026-09-13T09:00:00Z", "voided": false},
            {"id": uid("line-2"), "line": {"name": "Latte", "qty": 2}, "line_total": 1_000, "round_number": 2,
             "round_fired_at": chrono::Utc::now().to_rfc3339(), "voided": false}]});
    seed_rows(&core, &[("open_ticket", fed)]);
    let b = core.list_open_tickets().await.unwrap().into_iter().find(|t| t.id == ticket).unwrap();
    assert_eq!(b.lines.len(), 2, "the listed round is not overlaid again");
}

/// A board read carries its trust: the stream's freshness and this device's
/// own queued / failed changes to THAT board (a queued movement is not a bill's).
#[tokio::test]
async fn board_reads_carry_their_freshness_and_own_queue() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed_methods(&core);
    seed_rows(&core, &[]);
    core.open_till(0, None).await.unwrap();
    ring(&core, 400, CASH, 400).await;
    core.record_cash_movement(100, "float".into(), Some("pay_in".into()), None).await.unwrap();
    core.store.with_conn(|c| Ok(c.execute("UPDATE outbox SET status='dead' WHERE op_type='cash_movement'", [])?)).unwrap();

    let bills = core.list_open_tickets_synced().await.unwrap();
    assert!(bills.data.is_empty());
    assert_eq!((bills.meta.pending, bills.meta.failed), (0, 0), "nothing of this device's touches the bills");
    assert_eq!(bills.meta.freshness, core.sync_status().freshness);

    let report = core.till_report_synced().await.unwrap();
    assert_eq!(report.meta.failed, 1, "the refused movement");
    assert_eq!(report.meta.pending, 2, "the open and the sale still queued");
    let orders = core.list_till_orders_synced().await.unwrap();
    assert_eq!(orders.data.len(), 1);
    assert_eq!((orders.meta.pending, orders.meta.failed), (1, 0));
}

/// Parity finding: the feed's till rows carry no branch name (the feed is one
/// branch), so the history list named no branch where the server's list did.
#[tokio::test]
async fn the_till_list_names_the_branch_from_the_synced_settings() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    seed_methods(&core);
    let till = core.open_till(0, None).await.unwrap().till.unwrap();
    seed_rows(&core, &[("branch_settings", serde_json::json!({"id": testkit::BRANCH, "name": "Centrada"}))]);
    let tills = core.list_tills().await.unwrap();
    let row = tills.iter().find(|t| t.id == till.id).expect("the open till is listed");
    assert_eq!(row.branch_name.as_deref(), Some("Centrada"));
}

/// Parity finding: a till's refunds list newest first and one sale's oldest
/// first, as the server lists them.
#[tokio::test]
async fn refunds_list_in_the_servers_order() {
    let core = testkit::offline_core("http://127.0.0.1:1", "").await;
    core.store
        .with_tx(|tx| {
            crate::ledger::write_row(tx, crate::ledger::T_ORDER, "o-1", &serde_json::json!({
                "id": "o-1", "idempotency_key": "o-1", "order_ref": "REF-o-1", "branch_id": testkit::BRANCH,
                "till_id": "t-1", "status": "completed", "payment_method": "Cash", "total_amount": 5000,
                "created_at": "2026-09-14T09:00:00Z", "payment_legs": []}), crate::ledger::Origin::Feed(1), None)?;
            for (id, at) in [("r-early", "2026-09-14T10:00:00+00:00"), ("r-late", "2026-09-14T11:00:00Z")] {
                crate::ledger::write_row(tx, crate::ledger::T_REFUND, id, &serde_json::json!({
                    "id": id, "order_id": "o-1", "till_id": "t-1", "amount": 100, "method": "Cash",
                    "is_cash": true, "issued_at": at}), crate::ledger::Origin::Feed(2), None)?;
            }
            Ok(())
        })
        .unwrap();
    let till: Vec<String> = crate::ledger::views::till_refunds(&core.store, "t-1").unwrap().refunds.into_iter().map(|r| r.id).collect();
    assert_eq!(till, vec!["r-late", "r-early"]);
    let order: Vec<String> =
        crate::ledger::views::order_refunds(&core.store, "o-1").unwrap().unwrap().refunds.into_iter().map(|r| r.id).collect();
    assert_eq!(order, vec!["r-early", "r-late"]);
}

/// A link that refuses at once until `hang` is set, then accepts and never
/// answers: a flaky link.
async fn hanging_server() -> (String, std::sync::Arc<std::sync::atomic::AtomicBool>) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let hang = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let h = hang.clone();
    tokio::spawn(async move {
        let mut held = Vec::new();
        while let Ok((sock, _)) = listener.accept().await {
            if h.load(Ordering::SeqCst) {
                held.push(sock);
            }
        }
    });
    (base, hang)
}

/// No read waits on the network. Online against a link that hangs, every
/// screen read of a till the device does not hold answers at once from the
/// rows (the background fill is what waits); a sale or bill never seen here is
/// refused after the short read timeout, never the client's 20 s.
#[tokio::test]
async fn reads_never_wait_on_a_hanging_link() {
    let (base, hang) = hanging_server().await;
    let core = testkit::online_core(&base, "").await;
    seed_methods(&core);
    core.open_till(0, None).await.unwrap();
    ring(&core, 400, CASH, 400).await;
    hang.store(true, Ordering::SeqCst);
    core.set_online(true);
    let past = "00000000-0000-0000-0000-00000000fa57".to_string();
    let t0 = std::time::Instant::now();
    assert_eq!(core.list_till_orders().await.unwrap().len(), 1);
    assert!(core.till_report().await.is_ok());
    assert!(core.list_cash_movements().await.is_ok());
    assert!(core.close_till_preview().await.is_ok());
    assert!(core.list_tills().await.is_ok());
    assert!(core.list_orders_for_till(past.clone()).await.unwrap().is_empty());
    assert!(core.list_till_refunds(past.clone()).await.unwrap().refunds.is_empty());
    assert!(core.till_report_for(past.clone()).await.is_err(), "no row for the till at all yet");
    assert!(core.list_open_tickets().await.is_ok());
    assert!(core.kds_list(None).await.is_ok());
    assert!(core.list_delivery_orders(None).await.is_ok());
    assert!(core.list_arrivals().is_ok());
    assert!(t0.elapsed() < Duration::from_millis(500), "the reads answered from the rows: {:?}", t0.elapsed());

    let t0 = std::time::Instant::now();
    assert!(core.order_detail("00000000-0000-0000-0000-00000000dead".into()).await.is_err());
    assert!(core.get_ticket("00000000-0000-0000-0000-00000000beef".into()).await.is_err());
    let waited = t0.elapsed();
    assert!(waited < crate::ledger_ops::FETCH_TIMEOUT * 2 + Duration::from_secs(1), "{waited:?}");
}

/// A till this device does not hold is filled in the background: the read
/// answers from the rows at once, the fill folds the server's sales and report
/// in, and a table change tells the screen to read again — which then serves
/// the server's report.
#[tokio::test]
async fn a_till_not_held_here_is_filled_in_the_background() {
    const PAST: &str = "00000000-0000-0000-0000-00000000fa57";
    let order = madar_api::models::Order {
        id: uuid::Uuid::parse_str("00000000-0000-0000-0000-0000000000e1").unwrap(),
        branch_id: uuid::Uuid::parse_str(testkit::BRANCH).unwrap(),
        total_amount: 900,
        status: "completed".into(),
        payment_method: "cash".into(),
        order_ref: Some(Some("REF-past-1".into())),
        ..Default::default()
    };
    let page = serde_json::to_value(madar_api::models::PaginatedOrders {
        data: vec![order],
        page: 1,
        per_page: 200,
        total: 1,
        total_pages: 1,
        ..Default::default()
    })
    .unwrap();
    let till = madar_api::models::Till {
        id: uuid::Uuid::parse_str(PAST).unwrap(),
        status: madar_api::models::TillStatus::Closed,
        ..Default::default()
    };
    let report = serde_json::to_value(madar_api::models::TillReportResponse {
        expected_cash: 1_900,
        till: Box::new(till),
        ..Default::default()
    })
    .unwrap();
    let stub = Stub::start(move |r| {
        if r.path.starts_with("/orders?") && r.path.contains(PAST) {
            Some(StubResponse::json(200, page.clone()))
        } else if r.path.starts_with(&format!("/tills/{PAST}/report")) {
            Some(StubResponse::json(200, report.clone()))
        } else {
            None
        }
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    core.set_online(true);
    let mut changes = core.store.subscribe_changes();

    assert!(core.list_orders_for_till(PAST.into()).await.unwrap().is_empty(), "nothing held yet, answered at once");
    let deadline = std::time::Instant::now() + Duration::from_secs(5);
    while core.list_orders_for_till(PAST.into()).await.unwrap().is_empty() {
        assert!(std::time::Instant::now() < deadline, "the fill never landed");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    assert!(changes.next(Duration::from_millis(50)).await.is_some(), "the screen is told to read again");
    let deadline = std::time::Instant::now() + Duration::from_secs(5);
    loop {
        if let Ok(r) = core.till_report_for(PAST.into()).await {
            assert!(r.from_server);
            assert_eq!(r.expected_cash_minor, 1_900);
            break;
        }
        assert!(std::time::Instant::now() < deadline, "the report never landed");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    assert_eq!(stub.requests("/orders").len(), 1, "one fill, not one per read");
}

/// The reads that are online by nature (a search across tills, a points
/// balance, a table's history) wait no longer than the read timeout on a
/// hanging link. Every screen read — the loyalty programme, the kitchen
/// stations, the routing mode, the delivery settings, the till reconcile, the
/// open-elsewhere check — answers at once from the rows, link or no link.
#[tokio::test]
async fn online_reads_are_bounded_and_remembered_reads_answer_at_once() {
    let (base, hang) = hanging_server().await;
    let core = testkit::online_core(&base, "").await;
    seed_rows(
        &core,
        &[(
            "branch_settings",
            serde_json::json!({"id": testkit::BRANCH, "kitchen_routing_effective": "kds", "kitchen_stations": [],
                "delivery": {"in_mall_enabled": true, "in_mall_override": "closed", "prep_time_minutes": 25},
                "loyalty": {"enabled": true, "mode": "visits", "program_name": "Club", "program_name_ar": null}}),
        )],
    );
    core.store.kv_put(&format!("{}{}", crate::sync_pull::K_LAST_FULL, testkit::BRANCH), "2026-09-14T10:00:00Z").unwrap();
    hang.store(true, Ordering::SeqCst);
    core.set_online(true);

    let t0 = std::time::Instant::now();
    let programme = core.loyalty_settings().await.unwrap();
    assert!(programme.enabled && programme.mode == "visits");
    assert!(core.kds_list_stations().await.unwrap().is_empty());
    assert_eq!(core.kitchen_routing_mode().await.unwrap().as_deref(), Some("kds"));
    let delivery = core.delivery_settings().await.unwrap();
    assert!(delivery.in_mall_enabled && delivery.in_mall_override == "closed" && delivery.prep_time_minutes == 25);
    assert!(core.refresh_till().await.is_ok(), "the reconcile reads the till rows");
    assert!(core.check_till_elsewhere().await.unwrap().is_none());
    assert!(core.branch_open_tills().await.is_ok());
    assert!(t0.elapsed() < Duration::from_millis(300), "screen reads: {:?}", t0.elapsed());

    let t0 = std::time::Instant::now();
    let (search, lookup, history) = tokio::join!(
        core.search_orders(None, None, None, None, None, 1),
        core.loyalty_lookup(Some("card".into()), None),
        core.table_history("00000000-0000-0000-0000-0000000000a1".into()),
    );
    let waited = t0.elapsed();
    assert!(search.is_err() && lookup.is_err() && history.is_err());
    assert!(waited < crate::ledger_ops::FETCH_TIMEOUT + Duration::from_secs(2), "{waited:?}");
}

/// A backend whose settings row lacks the branch reads (before
/// `sync_feed_branch_reads`): each is filled ONCE from its legacy endpoint, in
/// the background; every later read answers from the fill and asks nothing.
/// Once the row carries the field, the row wins and nothing is fetched.
#[tokio::test]
async fn an_older_feed_fills_each_branch_read_once_and_never_polls() {
    let stub = Stub::start(|r| {
        let p = r.path.as_str();
        if p.starts_with("/kitchen/routing-mode") {
            Some(StubResponse::text(200, r#"{"mode":null,"effective":"both"}"#))
        } else if p.starts_with("/kitchen/stations") {
            Some(StubResponse::text(200, "[]"))
        } else if p.starts_with("/delivery/settings") {
            let mut s = serde_json::to_value(madar_api::models::BranchDeliverySettings::default()).unwrap();
            s["prep_time_minutes"] = serde_json::json!(40);
            s["outside_enabled"] = serde_json::json!(true);
            Some(StubResponse::json(200, s))
        } else if p.starts_with("/loyalty/settings") {
            let mut s = serde_json::to_value(madar_api::models::LoyaltySettings::default()).unwrap();
            s["enabled"] = serde_json::json!(true);
            s["program_name"] = serde_json::json!("Legacy club");
            Some(StubResponse::json(200, s))
        } else {
            None
        }
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    seed_rows(&core, &[("branch_settings", serde_json::json!({"id": testkit::BRANCH, "name": "Old"}))]);
    core.set_online(true);

    let legacy = ["/kitchen/routing-mode", "/kitchen/stations", "/delivery/settings", "/loyalty/settings"];
    let asked = || legacy.iter().map(|p| stub.requests(p).len()).sum::<usize>();
    let read_all = || async {
        let _ = core.kitchen_routing_mode().await.unwrap();
        let _ = core.kds_list_stations().await.unwrap();
        let _ = core.delivery_settings().await.unwrap();
        let _ = core.loyalty_settings().await.unwrap();
    };
    read_all().await;
    let deadline = std::time::Instant::now() + Duration::from_secs(5);
    while core.kitchen_routing_mode().await.unwrap().is_none() || !core.loyalty_settings().await.unwrap().enabled {
        assert!(std::time::Instant::now() < deadline, "the fills never landed");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    tokio::time::sleep(Duration::from_millis(100)).await;
    for _ in 0..20 {
        read_all().await;
    }
    for p in legacy {
        assert_eq!(stub.requests(p).len(), 1, "{p}: one fill, never a poll");
    }
    assert_eq!(core.kitchen_routing_mode().await.unwrap().as_deref(), Some("both"));
    let d = core.delivery_settings().await.unwrap();
    assert!(d.outside_enabled && d.prep_time_minutes == 40);
    assert_eq!(core.loyalty_settings().await.unwrap().program_name, "Legacy club");

    // The new backend's row carries the fields: the row answers, nothing is asked.
    seed_rows(
        &core,
        &[("branch_settings", serde_json::json!({"id": testkit::BRANCH, "kitchen_routing_effective": "till",
            "kitchen_stations": [], "delivery": null, "loyalty": null}))],
    );
    let before = asked();
    read_all().await;
    assert_eq!(core.kitchen_routing_mode().await.unwrap().as_deref(), Some("till"));
    assert!(!core.loyalty_settings().await.unwrap().enabled, "no programme at the branch");
    assert_eq!(core.delivery_settings().await.unwrap().prep_time_minutes, 20, "the server's defaults");
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(asked(), before);
}

/// A rate changed in the dashboard reaches the till with the feed's settings
/// row, and neither a floor refresh nor a manual sync then asks anything but
/// the changefeed.
#[tokio::test]
async fn the_tax_policy_rides_the_feed_and_refreshes_ask_only_the_feed() {
    let stub = Stub::start(|r| {
        (r.path.starts_with("/sync/pull") || r.path.starts_with("/sync/replay")).then(|| {
            StubResponse::text(200, r#"{"full":false,"next":5,"has_more":false,"server_time":"2026-09-14T10:00:00Z","changes":[]}"#)
        })
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    seed_rows(
        &core,
        &[(
            "branch_settings",
            serde_json::json!({"id": testkit::BRANCH, "tax_policy": {"tax_rate": 0.05, "tax_inclusive": true,
                "service_charge_rate": 0.12, "service_charge_taxable": false}, "org_require_table_for_orders": true}),
        )],
    );
    core.set_online(true);
    core.project_pull_mirrors(testkit::BRANCH);
    let s = core.session.read().unwrap().as_ref().unwrap().snapshot.clone();
    assert_eq!((s.tax_rate, s.tax_inclusive, s.service_charge_rate, s.service_charge_taxable), (0.05, true, 0.12, false));
    assert!(s.require_table_for_orders);

    let reads = || -> Vec<String> {
        stub.seen
            .lock()
            .unwrap()
            .iter()
            .filter(|r| !r.path.starts_with("/sync/") && !r.path.starts_with("/health") && !r.path.starts_with("/auth/"))
            .map(|r| r.path.clone())
            .collect()
    };
    for _ in 0..3 {
        core.refresh_floor().await.unwrap();
        core.refresh_arrivals().await.unwrap();
        let _ = core.sync_now().await.unwrap();
    }
    tokio::time::sleep(Duration::from_millis(400)).await;
    let other = reads();
    // The one read allowed: the once-per-branch backfill of the past tills
    // older than the snapshot window (flagged, never repeated).
    assert!(
        other.len() <= 1 && other.iter().all(|p| p.starts_with(&format!("/tills/branches/{}", testkit::BRANCH))),
        "refreshes asked the server for reads: {other:?}"
    );
}

/// A connectivity check while already online only drains (an ack nudges its own
/// pull); the offline→online edge pulls once.
#[tokio::test]
async fn a_connectivity_check_pulls_only_on_reconnect() {
    let stub = Stub::start(|r| {
        if r.path.starts_with("/health") {
            Some(StubResponse::text(200, "{}"))
        } else {
            r.path.starts_with("/sync/pull").then(|| {
                StubResponse::text(200, r#"{"full":false,"next":5,"has_more":false,"server_time":"2026-09-14T10:00:00Z","changes":[]}"#)
            })
        }
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    core.store.kv_put(&format!("{}{}", crate::sync_pull::K_LAST_FULL, testkit::BRANCH), "2026-09-14T08:00:00Z").unwrap();
    core.set_manual_scheduling(true);
    core.set_online(false);
    assert!(core.refresh_connectivity().await);
    assert_eq!(stub.requests("/sync/pull").len(), 1, "the reconnect pulls");
    // Online with a live stream (the poll would otherwise stand in for it).
    core.realtime_connected.store(true, std::sync::atomic::Ordering::Relaxed);
    for _ in 0..5 {
        assert!(core.refresh_connectivity().await);
    }
    assert_eq!(stub.requests("/sync/pull").len(), 1, "checks while online only drain");
}

/// A bill fired and settled while offline: the server gives the fire its own
/// id (the device's id is the idempotency key), and the queued settle — and a
/// round or void — must name THAT id on replay, or the paid sale dead-letters.
#[tokio::test]
async fn a_bill_fired_and_settled_offline_replays_under_the_servers_id() {
    const SERVER_TICKET: &str = "00000000-0000-0000-0000-00000000f00d";
    let up = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let link = up.clone();
    let stub = Stub::start(move |r| {
        if !link.load(Ordering::SeqCst) {
            return Some(StubResponse::hangup());
        }
        if !r.path.starts_with("/sync/replay") {
            return None;
        }
        let env = r.json();
        Some(match env["op"].as_str().unwrap_or("") {
            "fire_open_ticket" => StubResponse::json(200, serde_json::json!({"id": SERVER_TICKET, "status": "open"})),
            "settle_open_ticket" | "add_ticket_round" | "void_open_ticket" | "void_ticket_line"
                if env["ticket_id"] != SERVER_TICKET =>
            {
                StubResponse::text(404, r#"{"error":"Not found: Open ticket not found"}"#)
            }
            "settle_open_ticket" => StubResponse::json(200, serde_json::json!({"id": "00000000-0000-0000-0000-00000000a11d"})),
            _ => StubResponse::json(200, serde_json::json!({"id": uuid::Uuid::new_v4().to_string()})),
        })
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    seed_methods(&core);
    let till = core.open_till(1_000, None).await.unwrap().till.unwrap();
    core.cart_add(None, uuid::Uuid::new_v4().to_string(), "Latte".into(), 500).unwrap();
    let fired = core.fire_ticket(None, Some("walk-in".into()), None, None, None).await.unwrap();
    let settle = core
        .settle_ticket(fired.ticket_id.clone(), till.id.clone(), CASH.into(), Some(1_000), None, None, None, None, None, None, vec![], vec![], false)
        .await;
    assert!(settle.is_ok(), "{settle:?}");

    up.store(true, Ordering::SeqCst);
    core.set_online(true);
    for _ in 0..8 {
        let _ = core.store.clear_network_backoff();
        let _ = core.drain_outbox().await;
    }
    let settles: Vec<_> = stub.requests("/sync/replay").into_iter().filter(|r| r.json()["op"] == "settle_open_ticket").collect();
    assert!(!settles.is_empty(), "the settle was sent");
    assert!(settles.iter().all(|r| r.json()["ticket_id"] == SERVER_TICKET), "under the server's id");
    assert_eq!(core.sync_status().dead_outbox, 0, "nothing dead-letters");
    assert_eq!(core.sync_status().pending_outbox, 0);
}

/// A till not held here is filled once; reading it again asks nothing until
/// the FEED moves the till (a refund or drawer movement against it arrives),
/// and then it is filled exactly once more.
#[tokio::test]
async fn a_filled_till_is_filled_again_only_when_the_feed_moves_it() {
    const PAST: &str = "00000000-0000-0000-0000-00000000fa58";
    let till = madar_api::models::Till {
        id: uuid::Uuid::parse_str(PAST).unwrap(),
        status: madar_api::models::TillStatus::Closed,
        ..Default::default()
    };
    let report = serde_json::to_value(madar_api::models::TillReportResponse {
        expected_cash: 1_000,
        till: Box::new(till),
        ..Default::default()
    })
    .unwrap();
    let empty = serde_json::to_value(madar_api::models::PaginatedOrders { page: 1, per_page: 200, ..Default::default() }).unwrap();
    let stub = Stub::start(move |r| {
        if r.path.starts_with("/orders?") {
            Some(StubResponse::json(200, empty.clone()))
        } else if r.path.starts_with(&format!("/tills/{PAST}/report")) {
            Some(StubResponse::json(200, report.clone()))
        } else {
            None
        }
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    core.set_online(true);
    let reports = |stub: &Stub| stub.requests(&format!("/tills/{PAST}/report")).len();
    async fn read_until(core: &crate::MadarCore, stub: &Stub, n: usize) {
        const PAST: &str = "00000000-0000-0000-0000-00000000fa58";
        let deadline = std::time::Instant::now() + Duration::from_secs(5);
        while stub.requests(&format!("/tills/{PAST}/report")).len() < n {
            let _ = core.till_report_for(PAST.into()).await;
            assert!(
                std::time::Instant::now() < deadline,
                "fill {n} never happened: {:?}",
                stub.seen.lock().unwrap().iter().map(|r| r.path.clone()).collect::<Vec<_>>()
            );
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    }
    read_until(&core, &stub, 1).await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    for _ in 0..20 {
        let _ = core.till_report_for(PAST.into()).await;
        let _ = core.list_orders_for_till(PAST.into()).await;
        let _ = core.list_till_refunds(PAST.into()).await;
    }
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert_eq!(reports(&stub), 1, "an unchanged till is never asked twice");

    // The feed brings a refund against the till: its rows moved.
    core.store
        .with_tx(|tx| {
            crate::ledger::write_row(
                tx,
                crate::ledger::T_REFUND,
                "rf-1",
                &serde_json::json!({"id": "00000000-0000-0000-0000-0000000000f9", "till_id": PAST, "order_id": "o", "amount": 100}),
                crate::ledger::Origin::Feed(77),
                None,
            )?;
            Ok(())
        })
        .unwrap();
    read_until(&core, &stub, 2).await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    for _ in 0..20 {
        let _ = core.till_report_for(PAST.into()).await;
    }
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert_eq!(reports(&stub), 2, "one more fill for the move, then quiet again");
}
