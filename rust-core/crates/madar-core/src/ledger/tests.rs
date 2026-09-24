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
        horizon: None,
    }
}

fn ctx_incr() -> PageCtx {
    PageCtx { full: false, window_from: None, stream_window_from: None, now_ms: now_ms(), horizon: None }
}

fn methods_of(rows: &[Value]) -> Vec<Method> {
    rows.iter().filter_map(Method::from_json).collect()
}

/// Shared vectors: the backend's own figures for rows exactly as the feed
/// delivers them (MadarRust `tests/tills_report_vectors_tests.rs`), in
/// madar-shared (`madar_till::vectors`), through this device's ledger.
#[test]
fn till_report_matches_the_backend_vectors() {
    check_till_vectors(madar_till::vectors::TILL_REPORT, 8);
}

/// The edges the fold takes the server's reading of (a method named with a
/// tab is a method; the fallback cash method's order).
#[test]
fn till_report_matches_the_backend_edge_vectors() {
    check_till_vectors(madar_till::vectors::TILL_EDGE, 3);
}

fn check_till_vectors(raw: &str, at_least: usize) {
    let doc: Value = serde_json::from_str(raw).unwrap();
    let scenarios = doc["scenarios"].as_array().unwrap();
    assert!(scenarios.len() >= at_least);
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
                ("total_tax", got.total_tax),
                ("total_service_charge", got.total_service_charge),
                ("refunds_issued_tax", got.refunds_issued_tax),
                ("refunds_issued_service_charge", got.refunds_issued_service_charge),
                ("service_charge_waived_count", got.service_charge_waived_count),
                ("service_charge_waived_amount", got.service_charge_waived_amount),
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
            let views: Vec<Value> = got
                .spot_views
                .iter()
                .map(|v| {
                    let at = chrono::DateTime::parse_from_rfc3339(&v.viewed_at).unwrap().with_timezone(&chrono::Utc);
                    json!({"id": v.id, "printed": v.printed, "viewed_by_name": v.viewed_by_name,
                           "approved_by_name": v.approved_by_name, "viewed_at": at})
                })
                .collect();
            assert_eq!(Value::Array(views), want["spot_views"], "{ctxs}: spot views");
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
    json!({"id": key, "idempotency_key": key, "order_ref": format!("REF-{key}"), "branch_id": BRANCH, "till_id": TILL, "status": "completed",
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

// ── store step 4: a pre-B device keeps every queued op, now as rows ────────

fn copy_fixture(tag: &str) -> std::path::PathBuf {
    let src = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/store_v0_6_0.sqlite");
    let dst = std::env::temp_dir().join(format!("madar_ledger_bf_{tag}_{}.sqlite", std::process::id()));
    let _ = std::fs::remove_file(&dst);
    std::fs::copy(&src, &dst).unwrap();
    dst
}

/// The real v0.6.0 store (offline open, pay-in, close, open, pay-out, all
/// queued with `open_shift` / `shift_id`) opens as ledger rows: both tills, both
/// movements, the first till closed, every op naming its row — and the drawer
/// figures the teller reconciled against are the same numbers.
#[test]
fn a_v060_store_backfills_every_queued_op_as_a_row() {
    let path = copy_fixture("v060");
    let before: i64 = rusqlite::Connection::open(&path)
        .unwrap()
        .query_row("SELECT COUNT(*) FROM outbox", [], |r| r.get(0))
        .unwrap();
    let store = Store::open(path.to_str().unwrap()).unwrap();
    let ops = store.list_active().unwrap();
    assert_eq!(ops.len() as i64, before, "no op lost");
    for op in &ops {
        assert!(op.entity_type.is_some() && op.entity_id.is_some(), "{} names its row", op.op_type);
    }
    let tills: Vec<(String, String, i64, i64)> = store
        .with_conn(|c| {
            let mut st = c.prepare("SELECT id, status, opening_cash, complete FROM ledger_tills ORDER BY opened_at")?;
            let v = st
                .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(v)
        })
        .unwrap();
    assert_eq!(tills.len(), 2);
    assert_eq!((tills[0].1.as_str(), tills[0].2, tills[0].3), ("closed", 50000, 1), "closed by its queued close");
    assert_eq!((tills[1].1.as_str(), tills[1].2, tills[1].3), ("open", 52000, 1));
    let first = store.with_conn(|c| report::compute(c, &tills[0].0, &[])).unwrap().unwrap();
    assert_eq!(first.expected_cash, 52000, "50000 float + 2000 pay-in");
    let second = store.with_conn(|c| report::compute(c, &tills[1].0, &[])).unwrap().unwrap();
    assert_eq!(second.expected_cash, 50500, "52000 float − 1500 pay-out");
    assert_eq!(second.cash_movements_out, 1500);
    // Idempotent: opening again changes nothing.
    drop(store);
    let again = Store::open(path.to_str().unwrap()).unwrap();
    let n: i64 = again.with_conn(|c| Ok(c.query_row("SELECT COUNT(*) FROM ledger_cash", [], |r| r.get(0))?)).unwrap();
    assert_eq!(n, 2);
    drop(again);
    let _ = std::fs::remove_file(&path);
}

/// A pre-B store with the changefeed's ledger rows in `sync_rows`, a history
/// cache, a queued sale with a pre-rework `shift_id` payload and a queued void
/// of a synced sale.
#[test]
fn a_tills_era_store_moves_its_feed_rows_caches_and_queue() {
    let path = std::env::temp_dir().join(format!("madar_ledger_bf_tills_{}.sqlite", std::process::id()));
    let _ = std::fs::remove_file(&path);
    {
        // Build it with the store as it was before step 2 (user_version 1).
        let s = Store::open(path.to_str().unwrap()).unwrap();
        s.with_conn(|c| {
            c.execute_batch(
                "DROP TABLE ledger_payments; DROP TABLE ledger_orders; DROP TABLE ledger_tills; DROP TABLE ledger_cash;
                 DROP TABLE ledger_refunds; DROP TABLE order_details; DROP TABLE till_reports; PRAGMA user_version = 1;",
            )?;
            Ok(())
        })
        .unwrap();
    }
    {
        let c = rusqlite::Connection::open(&path).unwrap();
        let till = json!({"id": TILL, "branch_id": BRANCH, "teller_id": "t", "status": "open", "opening_cash": 100, "opened_at": "2026-09-14T08:00:00Z"});
        let synced = json!({"id": "srv-9", "idempotency_key": "k9", "branch_id": BRANCH, "till_id": TILL, "status": "completed",
            "payment_method": "Cash", "total_amount": 1000, "created_at": "2026-09-14T09:00:00Z",
            "payment_legs": [{"method": "Cash", "amount": 1000, "is_cash": true}]});
        c.execute("INSERT INTO sync_rows(type,id,branch_id,seq,data) VALUES('till',?1,?2,5,?3)", params![TILL, BRANCH, till.to_string()]).unwrap();
        c.execute("INSERT INTO sync_rows(type,id,branch_id,seq,data) VALUES('order','srv-9',?1,6,?2)", params![BRANCH, synced.to_string()]).unwrap();
        c.execute("INSERT INTO sync_rows(type,id,branch_id,seq,data) VALUES('category','c1',?1,7,'{\"id\":\"c1\"}')", params![BRANCH]).unwrap();
        c.execute(
            "INSERT INTO kv(k,v,updated_at) VALUES('cache:cash:' || ?1, ?2, 't')",
            params![TILL, json!([{"id": "m-old", "kind": "pay_in", "amount_minor": 300, "note": "float", "moved_by_name": "Sara", "created_at": "2026-09-14T08:05:00Z"}]).to_string()],
        )
        .unwrap();
        c.execute(
            "INSERT INTO kv(k,v,updated_at) VALUES('catalog:payment_methods', ?1, 't')",
            [json!([{"id": "00000000-0000-0000-0000-00000000c001", "name": "Cash", "is_cash": true}]).to_string()],
        )
        .unwrap();
        let queued = json!({"request": {"branch_id": BRANCH, "shift_id": TILL, "items": [], "payment_method": "Cash",
            "total_amount": 250, "idempotency_key": "00000000-0000-0000-0000-0000000000f1", "created_at": "2026-09-14T09:30:00Z"}});
        c.execute(
            "INSERT INTO outbox(id,op_type,idempotency_key,payload,event_at,enqueued_at,status,user_id,till_id)
             VALUES('00000000-0000-0000-0000-0000000000f1','create_order','x',?1,'2026-09-14T09:30:00Z','t','pending','t',?2)",
            params![queued.to_string(), TILL],
        )
        .unwrap();
        let void = json!({"order_id": "srv-9", "request": {"reason": "wrong_order", "voided_at": "2026-09-14T09:40:00Z"}});
        c.execute(
            "INSERT INTO outbox(id,op_type,idempotency_key,payload,event_at,enqueued_at,status,user_id,till_id)
             VALUES('srv-9:void','void_order','srv-9:void',?1,'2026-09-14T09:40:00Z','t','dead','t',?2)",
            params![void.to_string(), TILL],
        )
        .unwrap();
    }
    let store = Store::open(path.to_str().unwrap()).unwrap();
    let r = store.with_conn(|c| report::compute(c, TILL, &[])).unwrap().unwrap();
    // 100 float + 300 cached pay-in + 250 queued cash sale; the synced 1000 sale
    // is voided by the (dead, not discarded) queued void.
    assert_eq!(r.expected_cash, 650);
    assert_eq!(r.voided_amount, 1000);
    let left: i64 = store
        .with_conn(|c| Ok(c.query_row("SELECT COUNT(*) FROM sync_rows WHERE type IN ('till','order','cash_movement','refund')", [], |r| r.get(0))?))
        .unwrap();
    assert_eq!(left, 0, "ledger types left sync_rows");
    let cats: i64 = store.with_conn(|c| Ok(c.query_row("SELECT COUNT(*) FROM sync_rows WHERE type='category'", [], |r| r.get(0))?)).unwrap();
    assert_eq!(cats, 1, "state types stay");
    drop(store);
    let _ = std::fs::remove_file(&path);
}

/// The Z report's device order-number range: numbers only, the byte-wise
/// greatest device code, sales with neither ignored (the server's MIN/MAX).
#[test]
fn the_order_number_range_reads_numbers_and_the_greatest_code() {
    let store = Store::open("").unwrap();
    let ctx = ctx_full("2020-01-01T00:00:00Z");
    store
        .with_tx(|tx| {
            apply::upsert(tx, T_TILL, &json!({"id": "T", "branch_id": "B", "teller_id": "u", "status": "open",
                "opened_at": "2026-09-14T08:00:00Z", "opening_cash": 0}), 1, &ctx)?;
            for (n, (num, code)) in [(json!(12), json!("36B")), (json!(3), json!("36A")), (json!("7"), json!(null)),
                                     (json!(null), json!("36b")), (json!(40), json!(5))].iter().enumerate() {
                apply::upsert(tx, T_ORDER, &json!({"id": format!("o{n}"), "till_id": "T", "branch_id": "B", "status": "completed",
                    "payment_method": "cash", "total_amount": 100, "created_at": "2026-09-14T09:00:00Z",
                    "order_number": num, "device_code": code, "payment_legs": []}), 10 + n as i64, &ctx)?;
            }
            Ok(())
        })
        .unwrap();
    let r = views::till_report(&store, "T", &|m: &str| m.to_string()).unwrap().expect("a complete till");
    assert_eq!((r.order_number_first, r.order_number_last), (Some(3), Some(40)));
    assert_eq!(r.device_code.as_deref(), Some("36b"), "lowercase sorts after uppercase, as in C collation");
}

/// Timing probe for a very large till (run with --release --ignored).
#[test]
#[ignore]
fn probe_report_on_34k_sales() {
    let store = Store::open("").unwrap();
    let ctx = ctx_full("2020-01-01T00:00:00Z");
    store
        .with_tx(|tx| {
            apply::upsert(tx, T_TILL, &json!({"id": "T", "branch_id": "B", "teller_id": "u", "status": "open",
                "opened_at": "2026-09-14T08:00:00Z", "opening_cash": 0}), 1, &ctx)?;
            for n in 0..34_000 {
                let m = if n % 3 == 0 { "card" } else { "cash" };
                apply::upsert(tx, T_ORDER, &json!({"id": format!("order-{n:08}-0000-0000-000000000000"), "till_id": "T", "branch_id": "B",
                    "status": if n % 50 == 0 { "voided" } else { "completed" }, "payment_method": m, "total_amount": 1000 + n % 7,
                    "tip_amount": n % 5, "created_at": "2026-09-14T09:00:00Z", "order_number": n, "device_code": "36B",
                    "payment_legs": [{"method": m, "amount": 1000 + n % 7, "is_cash": m == "cash"}]}), 10 + n as i64, &ctx)?;
            }
            Ok(())
        })
        .unwrap();
    for _ in 0..3 {
        let t = std::time::Instant::now();
        let f = store.with_conn(|c| report::compute(c, "T", &[])).unwrap().unwrap();
        let compute = t.elapsed();
        let t = std::time::Instant::now();
        let r = views::till_report(&store, "T", &|m: &str| m.to_string()).unwrap().unwrap();
        eprintln!("PROBE compute={compute:?} till_report={:?} total={} {}", t.elapsed(), f.total_payments, r.total_payments_minor);
    }
}


// ── Audit HIGH 1 + 2: one identity whatever order the writers arrive in ────

fn feed_full(store: &Store, rows: &[(&str, Value, i64)]) -> crate::error::CoreResult<()> {
    let ctx = ctx_full("2020-01-01T00:00:00Z");
    store.with_tx(|tx| {
        for (ty, row, seq) in rows {
            apply::upsert(tx, ty, row, *seq, &ctx)?;
        }
        Ok(())
    })
}

fn server_order(id: &str, key: Option<&str>, total: i64) -> Value {
    let mut v = json!({"id": id, "order_ref": format!("REF-{}", key.unwrap_or(id)), "branch_id": BRANCH, "till_id": TILL,
        "status": "completed", "payment_method": "Cash", "total_amount": total, "tip_amount": 0,
        "created_at": "2026-09-14T09:00:00Z", "payment_legs": [{"method": "Cash", "amount": total, "is_cash": true}]});
    if let Some(k) = key {
        v["idempotency_key"] = json!(k);
    }
    v
}

/// Probe 1: a history fetch (and a pre-B cache) stored the sale under its SERVER
/// id; the feed then sends it under its client key. It used to insert a second
/// row, fail UNIQUE(server_id), roll the page back and stick sync forever.
#[test]
fn a_row_stored_by_server_id_is_rekeyed_when_the_feed_brings_its_client_key() {
    let store = Store::open("").unwrap();
    open_till(&store, 0);
    // A list read of an incomplete till: no client key on the wire.
    let listed = server_order("srv-1", None, 700);
    let mut listed = listed;
    listed["order_ref"] = json!("REF-k1");
    views::store_fetched_orders(&store, &[listed]).unwrap();
    // A pre-B OrderFull cache of another sale, migrated under its server id.
    store.kv_put("cache:order:srv-2", &json!([server_order("srv-2", None, 300)]).to_string()).unwrap();
    store.with_tx(|tx| migrate::backfill(tx)).unwrap();
    assert_eq!(order_rows(&store), 2);

    feed_full(&store, &[(T_ORDER, server_order("srv-1", Some("k1"), 700), 50), (T_ORDER, {
        let mut v = server_order("srv-2", Some("k2"), 300);
        v["order_ref"] = json!("REF-srv-2");
        v
    }, 51)])
    .expect("the page applies: no UNIQUE(server_id) failure");
    assert_eq!(order_rows(&store), 2, "re-keyed, not duplicated");
    let keys: Vec<(String, Option<String>, i64)> = store
        .with_conn(|c| {
            let mut st = c.prepare("SELECT okey, server_id, srv_seq FROM ledger_orders ORDER BY okey")?;
            let v = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?.collect::<Result<Vec<_>, _>>()?;
            Ok(v)
        })
        .unwrap();
    assert_eq!(keys, vec![("k1".into(), Some("srv-1".into()), 50), ("k2".into(), Some("srv-2".into()), 51)]);
    assert_eq!(expected(&store), 1_000);
    // And the next page (and a repeat of it) still applies.
    feed_full(&store, &[(T_ORDER, server_order("srv-1", Some("k1"), 700), 60)]).unwrap();
    feed_full(&store, &[(T_ORDER, server_order("srv-1", Some("k1"), 700), 60)]).unwrap();
    assert_eq!(order_rows(&store), 2);
}

/// A void queued against a sale this device held under its server id follows
/// the row when it is re-keyed.
#[test]
fn a_rekey_carries_the_live_ops_that_hold_the_row() {
    let store = Store::open("").unwrap();
    open_till(&store, 0);
    views::store_fetched_orders(&store, &[server_order("srv-9", None, 500)]).unwrap();
    store
        .with_tx(|tx| {
            local::commit_void(
                tx,
                &NewOutboxOp {
                    id: "srv-9:void".into(),
                    op_type: "void_order".into(),
                    idempotency_key: "srv-9:void".into(),
                    payload: "{}".into(),
                    event_at: "2026-09-14T09:30:00Z".into(),
                    till_id: Some(TILL.into()),
                    entity_type: Some(T_ORDER.into()),
                    entity_id: Some("srv-9".into()),
                    ..Default::default()
                },
                "2026-09-14T09:30:00Z",
                "other",
                Some("x"),
            )
            .map(|_| ())
        })
        .unwrap();
    let mut fed = server_order("srv-9", Some("k9"), 500);
    fed["order_ref"] = json!("REF-srv-9");
    feed_full(&store, &[(T_ORDER, fed, 70)]).unwrap();
    assert_eq!(order_rows(&store), 1);
    let (entity, status): (String, String) = store
        .with_conn(|c| {
            Ok(c.query_row(
                "SELECT x.entity_id, o.status FROM outbox x JOIN ledger_orders o ON o.okey = x.entity_id WHERE x.id='srv-9:void'",
                [],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )?)
        })
        .unwrap();
    assert_eq!((entity.as_str(), status.as_str()), ("k9", "voided"), "the queued void still holds (and shows on) the row");
}

/// Probe 2: an ack with no body leaves the row without a server id; a list read
/// of the till then brought the same sale as a second row and the drawer read
/// 1400 for a 700 sale. Matched by client key (the list now carries it) and, for
/// a server that does not send it, by order_ref.
#[test]
fn an_ack_without_a_body_and_a_list_read_count_the_sale_once() {
    for with_key in [true, false] {
        let store = Store::open("").unwrap();
        open_till(&store, 0);
        sell(&store, "k1", 700);
        ack(&store, "k1", None);
        assert_eq!(expected(&store), 700);
        let mut listed = server_order("srv-1", with_key.then_some("k1"), 700);
        // The sale's own reference, minted at the till (the one a list row
        // shares with the row rung here even when no client key is sent).
        listed["order_ref"] = json!("REF-k1");
        views::store_fetched_orders(&store, &[listed]).unwrap();
        assert_eq!(order_rows(&store), 1, "with_key={with_key}");
        let f = store.with_conn(|c| report::compute(c, TILL, &[])).unwrap().unwrap();
        assert_eq!((f.system_cash, f.expected_cash), (700, 700), "with_key={with_key}");
        // The feed then confirms it under its client key: still one row.
        feed_full(&store, &[(T_ORDER, server_order("srv-1", Some("k1"), 700), 80)]).unwrap();
        assert_eq!(order_rows(&store), 1);
        assert_eq!(expected(&store), 700);
    }
}

/// Movements and refunds: a server-id row meets its client_ref.
#[test]
fn movements_and_refunds_rekey_on_client_ref() {
    let store = Store::open("").unwrap();
    open_till(&store, 1_000);
    store
        .with_tx(|tx| {
            write_row(tx, T_CASH, "srv-c", &json!({"id": "srv-c", "till_id": TILL, "amount": 250, "kind": "pay_in",
                "created_at": "2026-09-14T09:00:00Z"}), Origin::Fetch, None)?;
            write_row(tx, T_REFUND, "srv-r", &json!({"id": "srv-r", "order_id": "o", "till_id": TILL, "amount": 100,
                "method": "Cash", "is_cash": true, "issued_at": "2026-09-14T09:00:00Z"}), Origin::Fetch, None)?;
            Ok(())
        })
        .unwrap();
    feed_full(
        &store,
        &[
            (T_CASH, json!({"id": "srv-c", "client_ref": "c1", "till_id": TILL, "amount": 250, "kind": "pay_in",
                "created_at": "2026-09-14T09:00:00Z"}), 90),
            (T_REFUND, json!({"id": "srv-r", "client_ref": "r1", "order_id": "o", "till_id": TILL, "amount": 100,
                "method": "Cash", "is_cash": true, "issued_at": "2026-09-14T09:00:00Z"}), 91),
        ],
    )
    .unwrap();
    let n = |q: &str| -> i64 { store.with_conn(|c| Ok(c.query_row(q, [], |r| r.get(0))?)).unwrap() };
    assert_eq!(n("SELECT COUNT(*) FROM ledger_cash WHERE ckey='c1' AND server_id='srv-c'"), 1);
    assert_eq!(n("SELECT COUNT(*) FROM ledger_cash"), 1);
    assert_eq!(n("SELECT COUNT(*) FROM ledger_refunds WHERE rkey='r1' AND server_id='srv-r'"), 1);
    assert_eq!(expected(&store), 1_000 + 250 - 100);
}

/// With the replay answer's feed horizon on the ack, the snapshot decides by
/// seq: a page below the horizon cannot remove the row (however long ago the
/// ack was), a page at or past it that still lacks the row can (however recent).
/// And the report counts the row unconfirmed only while the cursor is below it.
#[test]
fn an_acks_feed_horizon_decides_when_an_unseen_row_is_gone() {
    let store = Store::open("").unwrap();
    open_till(&store, 0);
    ack(&store, TILL, None);
    store.with_tx(|tx| tx.execute("UPDATE ledger_tills SET srv_seq=5, acked=0", []).map_err(Into::into)).unwrap();
    sell(&store, "sale-h", 700);
    ack(&store, "sale-h", Some(cash_sale("srv-h", 700).as_object().cloned().map(|mut m| {
        m.insert("idempotency_key".into(), json!("sale-h"));
        Value::Object(m)
    }).unwrap()));
    store.with_tx(|tx| set_ack_seq(tx, T_ORDER, "sale-h", 50)).unwrap();
    let f = |cursor: &str| {
        store.kv_put(&format!("{}{BRANCH}", crate::sync_pull::K_NEXT), cursor).unwrap();
        store.with_conn(|c| report::compute(c, TILL, &[])).unwrap().unwrap()
    };
    assert_eq!(f("40").unconfirmed, 1, "the feed has not reached the op yet");
    assert_eq!(f("50").unconfirmed, 0, "past the op's horizon it is not waiting for confirmation");

    let page = |horizon| {
        let mut c = ctx_full("2026-09-13T00:00:00Z");
        c.horizon = Some(horizon);
        c
    };
    // Old ack, but the page is below the horizon: kept.
    store.with_conn(|c| Ok(c.execute("UPDATE ledger_orders SET local_updated_at = local_updated_at - 3600000", [])?)).unwrap();
    store.with_tx(|tx| apply::sweep_absent(tx, BRANCH, T_ORDER, &Default::default(), &page(49))).unwrap();
    assert_eq!(order_rows(&store), 1, "a page below the op's horizon says nothing about it");
    // Fresh ack, page past the horizon, row absent: gone.
    store.with_conn(|c| Ok(c.execute("UPDATE ledger_orders SET local_updated_at = ?1", [now_ms()])?)).unwrap();
    store.with_tx(|tx| apply::sweep_absent(tx, BRANCH, T_ORDER, &Default::default(), &page(50))).unwrap();
    assert_eq!(order_rows(&store), 0, "the snapshot includes the op and does not list the row");
}

/// A partial refund queued on this device (no server split yet) takes its
/// pro-rata tax and service charge off the till's figures, split by the shared
/// engine exactly as the server's trigger will; a synced refund's own split is
/// used as delivered.
#[test]
fn a_queued_partial_refund_takes_its_share_of_tax_and_service_off_the_z() {
    let store = Store::open("").unwrap();
    open_till(&store, 0);
    store
        .with_tx(|tx| {
            let mut sale = cash_sale("srv-t", 12540);
            let m = sale.as_object_mut().unwrap();
            m.insert("subtotal".into(), json!(10000));
            m.insert("service_charge_amount".into(), json!(1000));
            m.insert("tax_amount".into(), json!(1540));
            m.insert("order_type".into(), json!("dine_in"));
            write_row(tx, T_ORDER, "srv-t", &sale, Origin::Fetch, None)?;
            // Synced, with the server's split.
            write_row(tx, T_REFUND, "srv-r1", &json!({"id": "srv-r1", "order_id": "srv-t", "till_id": TILL, "amount": 2508,
                "method": "Cash", "is_cash": true, "issued_at": "2026-09-14T10:00:00Z",
                "tax_amount": 308, "service_charge_amount": 200}), Origin::Fetch, None)?;
            // Queued here: no split on the row.
            write_row(tx, T_REFUND, "r-local", &json!({"id": "r-local", "order_id": "srv-t", "till_id": TILL, "amount": 1001,
                "method": "Cash", "is_cash": true, "issued_at": "2026-09-14T10:30:00Z"}), Origin::Local, None)?;
            Ok(())
        })
        .unwrap();
    let f = store.with_conn(|c| report::compute(c, TILL, &[])).unwrap().unwrap();
    // The server's vector for the same bill: 1540 − 431, 1000 − 280.
    assert_eq!((f.total_tax, f.total_service_charge), (1109, 720));
    assert_eq!((f.refunds_issued_tax, f.refunds_issued_service_charge), (431, 280));
}

// ── A receipt must be previewable offline (owner bug 2) ────────────────────
//
// The failing case: a sale rung with no network has no server record and its
// local row carries `"items": []` (the command names no item NAMES), so
// `order_full` could not rebuild it and the preview fell through to the network
// and refused. The receipt the printer was handed now rides on the row.

fn arabic_receipt(order_id: &str) -> crate::checkout::ReceiptView {
    crate::checkout::ReceiptView {
        local_order_id: order_id.into(),
        display_number: "36B-12".into(),
        lines: vec![crate::checkout::ReceiptLineView {
            name: "شاورما".into(),
            qty: 2,
            line_total_minor: 9000,
            ..Default::default()
        }],
        payment_label: "نقدي".into(),
        subtotal_minor: 9000,
        // The bill's OWN frozen rate — a reprint must show what applied to it.
        tax_rate: 0.14,
        tax_minor: 1260,
        tax_inclusive: true,
        total_minor: 10260,
        is_cash: true,
        teller_name: Some("سارة".into()),
        ..Default::default()
    }
}

/// A sale rung OFFLINE previews before it syncs, from the device's own row,
/// with its Arabic lines and its frozen VAT rate intact.
#[test]
fn a_queued_sale_previews_from_its_own_row_before_it_syncs() {
    let store = Store::open("").unwrap();
    let key = "11111111-1111-1111-1111-111111111111";
    let printed = arabic_receipt(key);

    let mut row = cash_sale(key, 10260);
    local::stash_receipt(&mut row, &printed);
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
                &row,
            )
        })
        .unwrap();

    // The row alone cannot rebuild the sale — that is the bug's shape.
    assert!(
        views::order_full(&store, key).unwrap().is_none(),
        "a queued sale has no items to project; the stash is the only record"
    );

    // ...but the receipt it printed is right there, unchanged.
    let back = local::queued_receipt(&store, key).unwrap().expect("queued receipt");
    assert_eq!(back, printed, "the preview is what came out of the printer");
    assert_eq!(back.lines[0].name, "شاورما", "Arabic survives the round trip");
    assert_eq!(back.tax_rate, 0.14, "the bill's frozen VAT rate is kept");
    assert!(back.tax_inclusive);
    assert_eq!(back.total_minor, 10260);
    assert!(!back.is_voided);
}

/// Voiding a queued sale must move its preview too: the stash is frozen at the
/// moment of printing, the ROW keeps moving, and the two must not disagree.
#[test]
fn voiding_a_queued_sale_stamps_its_offline_preview() {
    let store = Store::open("").unwrap();
    let key = "22222222-2222-2222-2222-222222222222";
    let mut row = cash_sale(key, 10260);
    local::stash_receipt(&mut row, &arabic_receipt(key));
    row["status"] = json!("voided");
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
                &row,
            )
        })
        .unwrap();
    let back = local::queued_receipt(&store, key).unwrap().expect("queued receipt");
    assert!(back.is_voided, "a voided sale previews with its VOIDED stamp");
}

/// A sale with no stash (one this device never rang) returns None rather than
/// an empty receipt — the caller then goes to the server, and says so offline.
#[test]
fn a_sale_this_device_never_rang_has_no_stashed_receipt() {
    let store = Store::open("").unwrap();
    let key = "33333333-3333-3333-3333-333333333333";
    sell(&store, key, 5000);
    assert!(local::queued_receipt(&store, key).unwrap().is_none());
    assert!(local::queued_receipt(&store, "nobody").unwrap().is_none());
}
