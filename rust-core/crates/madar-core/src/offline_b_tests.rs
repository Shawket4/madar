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
    let mut bill = madar_api::models::OpenTicketView::default();
    bill.id = uuid::Uuid::parse_str(&uid("bill-1")).unwrap();
    bill.status = "open".into();
    bill.subtotal = 4_200;
    bill.opened_at = now.fixed_offset();
    let mut settled_here = bill.clone();
    settled_here.id = uuid::Uuid::parse_str(&uid("bill-2")).unwrap();

    let station = uuid::Uuid::parse_str(&uid("grill")).unwrap();
    let mut kt = madar_api::models::KitchenTicketView::default();
    kt.id = uuid::Uuid::parse_str(&uid("kt-1")).unwrap();
    kt.status = "open".into();
    kt.created_at = now.fixed_offset();
    let mut line = madar_api::models::KitchenTicketItemView::default();
    line.id = uuid::Uuid::parse_str(&uid("kt-1-line")).unwrap();
    line.station_id = Some(Some(station));
    line.qty = 1;
    kt.items = vec![line];
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
    let stub = Stub::start(|r| {
        if r.path.contains("/report") {
            let mut rep = serde_json::to_value(madar_api::models::TillReportResponse::default()).unwrap();
            rep["expected_cash"] = serde_json::json!(999_999);
            return Some(StubResponse::json(200, rep));
        }
        None
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    seed_methods(&core);
    let till = core.open_till(1_000, None).await.unwrap().till.unwrap();
    core.store.with_conn(|c| Ok(c.execute("UPDATE outbox SET status='acked'", [])?)).unwrap();
    core.store.with_conn(|c| Ok(c.execute("UPDATE ledger_tills SET acked=0", [])?)).unwrap();
    core.set_online(true);
    core.money_parity_check().await;
    assert!(stub.requests(&format!("/tills/{}/report", till.id)).len() == 1);
    assert!(core.recent_logs().iter().any(|l| l.message.contains("money") && l.message.contains("expected_cash")));
    // Rate-limited: a second check right away does not ask again.
    core.money_parity_check().await;
    assert_eq!(stub.requests("/tills/").len(), 1);
}
