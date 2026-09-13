use serde_json::{json, Value};

use super::apply::{self, PageCtx};
use super::report::{self, Method};
use super::*;
use crate::store::{enqueue_on, NewOutboxOp, Store};

fn ctx_full(window_from: &str) -> PageCtx {
    PageCtx {
        full: true,
        window_from: chrono::DateTime::parse_from_rfc3339(window_from).ok().map(|d| d.with_timezone(&chrono::Utc)),
        stream_window_from: None,
        now_ms: now_ms(),
    }
}

fn ctx_incr() -> PageCtx {
    PageCtx { full: false, window_from: None, stream_window_from: None, now_ms: now_ms() }
}

fn methods_of(rows: &[Value]) -> Vec<Method> {
    rows.iter().filter_map(Method::from_json).collect()
}

/// Shared vectors: the backend's own figures for rows exactly as the feed
/// delivers them (MadarRust `src/tills/report_vectors_tests.rs`).
#[test]
fn till_report_matches_the_backend_vectors() {
    let raw = include_str!("../../tests/fixtures/till_report_vectors.json");
    let doc: Value = serde_json::from_str(raw).unwrap();
    let scenarios = doc["scenarios"].as_array().unwrap();
    assert!(scenarios.len() >= 7);
    for sc in scenarios {
        let name = sc["name"].as_str().unwrap();
        let store = Store::open("").unwrap();
        let ctx = ctx_full("2020-01-01T00:00:00Z");
        store
            .with_tx(|tx| {
                for ty in [T_TILL, T_ORDER, T_CASH, T_REFUND] {
                    for (n, row) in sc["rows"][ty].as_array().unwrap().iter().enumerate() {
                        apply::upsert(tx, ty, row, 100 + n as i64, &ctx)?;
                    }
                }
                Ok(())
            })
            .unwrap();
        let methods = methods_of(sc["rows"]["payment_method"].as_array().unwrap());
        for (till_id, want) in sc["expected"].as_object().unwrap() {
            let got = store
                .with_conn(|c| report::compute(c, till_id, &methods))
                .unwrap()
                .unwrap_or_else(|| panic!("{name}: till {till_id} present"));
            let ctxs = format!("{name} / {till_id}");
            assert_eq!(got.system_cash, want["system_cash"].as_i64().unwrap(), "{ctxs}: system_cash");
            assert_eq!(got.expected_cash, want["expected_cash"].as_i64().unwrap(), "{ctxs}: expected_cash");
            for (field, v) in [
                ("total_payments", got.total_payments),
                ("voided_amount", got.voided_amount),
                ("net_payments", got.net_payments),
                ("total_tips", got.total_tips),
                ("cash_tips", got.cash_tips),
                ("non_cash_tips", got.non_cash_tips),
                ("cash_movements_in", got.cash_movements_in),
                ("cash_movements_out", got.cash_movements_out),
                ("safe_drops", got.safe_drops),
                ("cash_adjustments", got.cash_adjustments),
                ("cash_movements_net", got.cash_movements_net),
                ("refunds_issued_count", got.refunds_issued_count),
                ("refunds_issued_amount", got.refunds_issued_amount),
                ("refunds_issued_cash", got.refunds_issued_cash),
                ("cash_in_refunded_sales", got.cash_in_refunded_sales),
            ] {
                assert_eq!(v, want[field].as_i64().unwrap(), "{ctxs}: {field}");
            }
            let summary: Vec<Value> = got
                .payment_summary
                .iter()
                .map(|p| json!({"payment_method": p.payment_method, "is_cash": p.is_cash, "total": p.total, "order_count": p.order_count}))
                .collect();
            assert_eq!(Value::Array(summary), want["payment_summary"], "{ctxs}: payment_summary");
            let ids: Vec<String> = got.cash_movements.iter().map(|m| m.id.clone()).collect();
            assert_eq!(json!(ids), want["cash_movement_ids"], "{ctxs}: movement order");
            let close: Vec<Value> = got
                .close_methods
                .iter()
                .map(|m| json!({"method": m.method, "is_cash": m.is_cash, "system_total": m.system_total,
                                "order_count": m.order_count, "payment_method_id": m.payment_method_id}))
                .collect();
            assert_eq!(Value::Array(close), want["close_methods"], "{ctxs}: close methods");
            assert_eq!(got.unsynced, 0);
            assert!(got.complete, "{ctxs}: an open (or in-window) till is complete");
        }
    }
}

// ── the write path, protection, folding ────────────────────────────────────

const TILL: &str = "11111111-1111-1111-1111-111111111111";
const BRANCH: &str = "22222222-2222-2222-2222-222222222222";

fn open_till(store: &Store, opening: i64) {
    let rec = json!({"id": TILL, "branch_id": BRANCH, "teller_id": "t", "teller_name": "Sara", "status": "open",
                     "opening_cash": opening, "opened_at": "2026-09-14T08:00:00Z", "verification": "server"});
    store
        .with_tx(|tx| {
            local::commit_open_till(
                tx,
                &NewOutboxOp {
                    id: TILL.into(),
                    op_type: "open_till".into(),
                    idempotency_key: TILL.into(),
                    payload: "{}".into(),
                    event_at: "2026-09-14T08:00:00Z".into(),
                    till_id: Some(TILL.into()),
                    entity_type: Some(T_TILL.into()),
                    entity_id: Some(TILL.into()),
                    ..Default::default()
                },
                &rec,
            )
        })
        .unwrap();
}

fn cash_sale(key: &str, total: i64) -> Value {
    json!({"id": key, "idempotency_key": key, "branch_id": BRANCH, "till_id": TILL, "status": "completed",
           "payment_method": "Cash", "total_amount": total, "tip_amount": 0, "created_at": "2026-09-14T09:00:00Z",
           "payment_legs": [{"method": "Cash", "amount": total, "is_cash": true}]})
}

fn sell(store: &Store, key: &str, total: i64) -> i64 {
    store
        .with_tx(|tx| {
            local::commit_order(
                tx,
                &NewOutboxOp {
                    id: key.into(),
                    op_type: "create_order".into(),
                    idempotency_key: key.into(),
                    payload: "{}".into(),
                    event_at: "2026-09-14T09:00:00Z".into(),
                    till_id: Some(TILL.into()),
                    entity_type: Some(T_ORDER.into()),
                    entity_id: Some(key.into()),
                    ..Default::default()
                },
                &cash_sale(key, total),
            )
        })
        .unwrap()
}

fn expected(store: &Store) -> i64 {
    store.with_conn(|c| report::compute(c, TILL, &[])).unwrap().unwrap().expected_cash
}

fn order_rows(store: &Store) -> i64 {
    store.with_conn(|c| Ok(c.query_row("SELECT COUNT(*) FROM ledger_orders", [], |r| r.get(0))?)).unwrap()
}

fn outbox_item(store: &Store, id: &str) -> crate::store::OutboxItem {
    store.list_active().unwrap().into_iter().find(|i| i.id == id).unwrap()
}

fn ack(store: &Store, id: &str, body: Option<Value>) {
    let item = outbox_item(store, id);
    store
        .with_tx(|tx| {
            tx.execute("UPDATE outbox SET status='acked' WHERE seq=?1", [item.seq])?;
            fold::fold(tx, &item, body.as_ref(), &[])?;
            Ok(())
        })
        .unwrap();
}

/// The audit's double count: the server applied the sale, the response was lost
/// (the op goes back to pending), the feed shows the sale, and the op is re-sent
/// and acked. One row, counted once, at every step.
#[test]
fn a_lost_response_never_counts_a_sale_twice() {
    let store = Store::open("").unwrap();
    open_till(&store, 1000);
    ack(&store, TILL, None);
    sell(&store, "sale-1", 500);
    assert_eq!(expected(&store), 1500, "queued: counted");
    store.with_conn(|c| Ok(c.execute("UPDATE outbox SET status='inflight' WHERE id='sale-1'", [])?)).unwrap();
    assert_eq!(expected(&store), 1500, "inflight: still counted (the old report skipped it)");
    // the feed arrives with the sale while the op is still unresolved
    let server = json!({"id": "srv-1", "idempotency_key": "sale-1", "branch_id": BRANCH, "till_id": TILL,
        "status": "completed", "payment_method": "Cash", "total_amount": 500, "tip_amount": 0,
        "created_at": "2026-09-14T09:00:01Z", "payment_legs": [{"method": "Cash", "amount": 500, "is_cash": true}]});
    store.with_tx(|tx| apply::upsert(tx, T_ORDER, &server, 50, &ctx_incr())).unwrap();
    assert_eq!(order_rows(&store), 1);
    assert_eq!(expected(&store), 1500, "feed + queued copy: once");
    store.with_conn(|c| Ok(c.execute("UPDATE outbox SET status='pending' WHERE id='sale-1'", [])?)).unwrap();
    ack(&store, "sale-1", Some(server.clone()));
    assert_eq!(order_rows(&store), 1);
    assert_eq!(expected(&store), 1500, "acked: once");
}

/// The audit's vanished sale: acked, and the next pull is a snapshot taken a
/// moment before the ack committed — the sale must not disappear.
#[test]
fn an_acked_sale_survives_a_snapshot_that_does_not_list_it_yet() {
    let store = Store::open("").unwrap();
    open_till(&store, 0);
    ack(&store, TILL, None);
    sell(&store, "sale-2", 700);
    ack(&store, "sale-2", Some(cash_sale("srv-2", 700).as_object().cloned().map(|mut m| {
        m.insert("idempotency_key".into(), json!("sale-2"));
        Value::Object(m)
    }).unwrap()));
    store
        .with_tx(|tx| apply::sweep_absent(tx, BRANCH, T_ORDER, &Default::default(), &ctx_full("2026-09-13T00:00:00Z")))
        .unwrap();
    assert_eq!(order_rows(&store), 1, "inside the ack grace: kept");
    assert_eq!(expected(&store), 700);
    // Long after the ack, a snapshot that still does not list it is the truth.
    store.with_conn(|c| Ok(c.execute("UPDATE ledger_orders SET local_updated_at = local_updated_at - 3600000", [])?)).unwrap();
    store
        .with_tx(|tx| apply::sweep_absent(tx, BRANCH, T_ORDER, &Default::default(), &ctx_full("2026-09-13T00:00:00Z")))
        .unwrap();
    assert_eq!(order_rows(&store), 0);
}

#[test]
fn a_queued_sale_is_never_deleted_by_a_snapshot_or_a_tombstone() {
    let store = Store::open("").unwrap();
    open_till(&store, 0);
    sell(&store, "sale-3", 100);
    store
        .with_tx(|tx| {
            apply::sweep_absent(tx, BRANCH, T_ORDER, &Default::default(), &ctx_full("2026-01-01T00:00:00Z"))?;
            apply::delete(tx, T_ORDER, "sale-3", &ctx_incr())?;
            apply::sweep_absent(tx, BRANCH, T_TILL, &Default::default(), &ctx_full("2026-01-01T00:00:00Z"))
        })
        .unwrap();
    assert_eq!(order_rows(&store), 1);
    assert_eq!(expected(&store), 100);
}

/// A void queued behind its sale keeps the sale voided when the sale's create
/// acks with the server's (not yet voided) body, and when the feed brings it.
#[test]
fn a_void_queued_behind_its_sale_survives_the_sales_ack_and_the_feed() {
    let store = Store::open("").unwrap();
    open_till(&store, 0);
    sell(&store, "sale-4", 900);
    store
        .with_tx(|tx| {
            local::commit_void(
                tx,
                &NewOutboxOp {
                    id: "sale-4:void".into(),
                    op_type: "void_order".into(),
                    idempotency_key: "sale-4:void".into(),
                    payload: json!({"order_id": "sale-4", "request": {"reason": "wrong_order", "voided_at": "2026-09-14T09:30:00Z"}}).to_string(),
                    event_at: "2026-09-14T09:30:00Z".into(),
                    till_id: Some(TILL.into()),
                    entity_type: Some(T_ORDER.into()),
                    entity_id: Some("sale-4".into()),
                    ..Default::default()
                },
                "2026-09-14T09:30:00Z",
                "wrong_order",
                None,
            )
        })
        .unwrap();
    assert_eq!(expected(&store), 0, "voided locally");
    let mut body = cash_sale("srv-4", 900);
    body["idempotency_key"] = json!("sale-4");
    ack(&store, "sale-4", Some(body.clone()));
    assert_eq!(expected(&store), 0, "the create's ack does not un-void");
    store.with_tx(|tx| apply::upsert(tx, T_ORDER, &body, 80, &ctx_incr())).unwrap();
    assert_eq!(expected(&store), 0, "nor does the feed while the void is queued");
    let mut voided = body.clone();
    voided["status"] = json!("voided");
    ack(&store, "sale-4:void", Some(voided));
    assert_eq!(expected(&store), 0);
    let status: String =
        store.with_conn(|c| Ok(c.query_row("SELECT status FROM ledger_orders WHERE okey='sale-4'", [], |r| r.get(0))?)).unwrap();
    assert_eq!(status, "voided");
}

#[test]
fn discarding_a_dead_op_removes_its_local_row_or_restores_the_server_version() {
    let store = Store::open("").unwrap();
    open_till(&store, 0);
    ack(&store, TILL, None);
    sell(&store, "sale-5", 400);
    store
        .with_tx(|tx| {
            tx.execute("UPDATE outbox SET status='dead' WHERE id='sale-5'", [])?;
            tx.execute("DELETE FROM outbox WHERE id='sale-5'", [])?;
            local::discard(tx, T_ORDER, "sale-5")
        })
        .unwrap();
    assert_eq!(order_rows(&store), 0, "a rejected sale that never reached the server is gone");

    // A server sale voided locally, the void rejected and discarded: back to sold.
    let server = cash_sale("srv-6", 300);
    store.with_tx(|tx| apply::upsert(tx, T_ORDER, &server, 10, &ctx_incr())).unwrap();
    store
        .with_tx(|tx| {
            local::commit_void(
                tx,
                &NewOutboxOp {
                    id: "srv-6:void".into(),
                    op_type: "void_order".into(),
                    idempotency_key: "srv-6:void".into(),
                    payload: "{}".into(),
                    event_at: "t".into(),
                    entity_type: Some(T_ORDER.into()),
                    entity_id: Some("srv-6".into()),
                    ..Default::default()
                },
                "2026-09-14T10:00:00Z",
                "other",
                Some("x"),
            )
        })
        .unwrap();
    assert_eq!(expected(&store), 0);
    store
        .with_tx(|tx| {
            tx.execute("DELETE FROM outbox WHERE id='srv-6:void'", [])?;
            local::discard(tx, T_ORDER, "srv-6")
        })
        .unwrap();
    assert_eq!(expected(&store), 300, "the server's sold version is back");
}

/// A closed till keeps its frozen drawer figure, plus the sales still on their
/// way (the server recomputes the snapshot when they land late) — and nothing
/// else.
#[test]
fn a_closed_till_is_its_snapshot_plus_sales_still_on_their_way() {
    let store = Store::open("").unwrap();
    let till = json!({"id": TILL, "branch_id": BRANCH, "teller_id": "t", "status": "closed", "opening_cash": 0,
                      "closing_cash_system": 5000, "opened_at": "2026-09-14T08:00:00Z", "closed_at": "2026-09-14T12:00:00Z"});
    store.with_tx(|tx| apply::upsert(tx, T_TILL, &till, 10, &ctx_incr())).unwrap();
    store.with_tx(|tx| apply::upsert(tx, T_ORDER, &cash_sale("srv-7", 5000), 9, &ctx_incr())).unwrap();
    assert_eq!(expected(&store), 5000);
    sell(&store, "late", 250);
    assert_eq!(expected(&store), 5250, "a dead-then-retried sale for the closed till is added");
    store.with_conn(|c| Ok(c.execute("UPDATE outbox SET status='acked'", [])?)).unwrap();
    store.with_conn(|c| Ok(c.execute("UPDATE ledger_orders SET acked=1 WHERE okey='late'", [])?)).unwrap();
    let r = store.with_conn(|c| report::compute(c, TILL, &[])).unwrap().unwrap();
    assert_eq!(r.expected_cash, 5000, "acked: the server's snapshot is the figure");
    assert_eq!(r.unconfirmed, 1, "…until the feed confirms it, which the report says");
}

#[test]
fn an_older_feed_row_never_regresses_a_newer_one() {
    let store = Store::open("").unwrap();
    let mut v = cash_sale("srv-8", 100);
    store.with_tx(|tx| apply::upsert(tx, T_ORDER, &v, 20, &ctx_incr())).unwrap();
    v["total_amount"] = json!(999);
    assert!(!store.with_tx(|tx| apply::upsert(tx, T_ORDER, &v, 19, &ctx_incr())).unwrap());
    let total: i64 = store
        .with_conn(|c| Ok(c.query_row("SELECT total_amount FROM ledger_orders WHERE okey='srv-8'", [], |r| r.get(0))?))
        .unwrap();
    assert_eq!(total, 100);
}

#[test]
fn a_crash_between_enqueue_and_row_cannot_split_them() {
    let store = Store::open("").unwrap();
    let res: crate::error::CoreResult<()> = store.with_tx(|tx| {
        enqueue_on(
            tx,
            &NewOutboxOp {
                id: "crash".into(),
                op_type: "create_order".into(),
                idempotency_key: "crash".into(),
                payload: "{}".into(),
                event_at: "t".into(),
                entity_type: Some(T_ORDER.into()),
                entity_id: Some("crash".into()),
                ..Default::default()
            },
        )?;
        Err(crate::error::CoreError::Internal { detail: "killed before the row".into() })
    });
    assert!(res.is_err());
    assert!(store.list_active().unwrap().is_empty(), "the op rolled back with the row");
    assert_eq!(order_rows(&store), 0);
}
