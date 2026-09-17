//! Ledger retention (OFFLINE_B_DESIGN §3 "Retention"): how much history the
//! device keeps, and the one rule no sweep may break — a row a live outbox op
//! holds, or a row the server has only just acknowledged, is never deleted.
//!
//! * every OPEN till, with all its rows;
//! * closed tills whose close (or open) is inside [`KEEP_DAYS`], capped at the
//!   newest [`MAX_CLOSED_TILLS`]; an evicted till takes its sales, movements and
//!   refunds with it — unless any of them is still held, which keeps the till;
//! * sales/movements/refunds of no till this device holds, older than the
//!   window (rows fetched for a past till that has since aged out);
//! * stored sale records and server Z reports, by age and count.
//!
//! Anything removed is re-fetchable while online (history is the server's).

use rusqlite::{params, Connection};

use crate::error::CoreResult;

pub(crate) const KEEP_DAYS: i64 = 30;
pub(crate) const MAX_CLOSED_TILLS: i64 = 400;
pub(crate) const MAX_ORDER_DETAILS: i64 = 2_000;
pub(crate) const MAX_TILL_REPORTS: i64 = 400;

/// Rows of `till_id` (or the till itself) a live op holds, or that are freshly
/// acked and not yet confirmed by the feed.
fn till_is_held(conn: &Connection, till_id: &str, now_ms: i64) -> CoreResult<bool> {
    let grace_from = now_ms - super::apply::ACK_GRACE_MS;
    let held: i64 = conn.query_row(
        "SELECT
           (SELECT COUNT(*) FROM outbox WHERE status IN ('pending','inflight','dead') AND (
               till_id = ?1
            OR (entity_type='till' AND entity_id=?1)
            OR (entity_type='order' AND entity_id IN (SELECT okey FROM ledger_orders WHERE till_id=?1))
            OR (entity_type='cash_movement' AND entity_id IN (SELECT ckey FROM ledger_cash WHERE till_id=?1))
            OR (entity_type='refund' AND entity_id IN (SELECT rkey FROM ledger_refunds WHERE till_id=?1))))
         + (SELECT COUNT(*) FROM ledger_orders WHERE till_id=?1 AND acked=1 AND srv_seq=0 AND (local_updated_at>=?2 OR ack_seq > ?3))
         + (SELECT COUNT(*) FROM ledger_cash WHERE till_id=?1 AND acked=1 AND srv_seq=0 AND (local_updated_at>=?2 OR ack_seq > ?3))
         + (SELECT COUNT(*) FROM ledger_refunds WHERE till_id=?1 AND acked=1 AND srv_seq=0 AND (local_updated_at>=?2 OR ack_seq > ?3))
         + (SELECT COUNT(*) FROM ledger_tills WHERE id=?1 AND acked=1 AND srv_seq=0 AND (local_updated_at>=?2 OR ack_seq > ?3))",
        params![till_id, grace_from, crate::ledger::cursor_of(conn, &conn.query_row("SELECT COALESCE((SELECT branch_id FROM ledger_tills WHERE id=?1), '')", [till_id], |r| r.get::<_, String>(0))?)?],
        |r| r.get(0),
    )?;
    Ok(held > 0)
}

fn cutoff(now_ms: i64) -> String {
    (chrono::DateTime::<chrono::Utc>::from_timestamp_millis(now_ms).unwrap_or_else(chrono::Utc::now)
        - chrono::Duration::days(KEEP_DAYS))
    .to_rfc3339()
}

fn is_older(ts: &str, cutoff: &chrono::DateTime<chrono::Utc>) -> bool {
    chrono::DateTime::parse_from_rfc3339(ts)
        .map(|d| d.with_timezone(&chrono::Utc) < *cutoff)
        .unwrap_or(false)
}

/// One sweep. Returns how many rows went.
pub(crate) fn sweep(conn: &Connection, now_ms: i64) -> CoreResult<u32> {
    let cutoff_s = cutoff(now_ms);
    let cutoff_t = chrono::DateTime::parse_from_rfc3339(&cutoff_s).unwrap().with_timezone(&chrono::Utc);
    let mut n = 0u32;

    // Closed tills, newest first by their close (or open) instant.
    let closed: Vec<(String, String)> = {
        let mut st = conn.prepare(
            "SELECT id, COALESCE(closed_at, opened_at) FROM ledger_tills WHERE status <> 'open'",
        )?;
        let mut v = st
            .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
            .collect::<Result<Vec<_>, _>>()?;
        v.sort_by(|a, b| {
            let ta = chrono::DateTime::parse_from_rfc3339(&a.1).ok();
            let tb = chrono::DateTime::parse_from_rfc3339(&b.1).ok();
            tb.cmp(&ta)
        });
        v
    };
    for (rank, (id, at)) in closed.iter().enumerate() {
        let evict = is_older(at, &cutoff_t) || rank as i64 >= MAX_CLOSED_TILLS;
        if !evict || till_is_held(conn, id, now_ms)? {
            continue;
        }
        n += conn.execute("DELETE FROM ledger_orders WHERE till_id=?1", [id])? as u32;
        n += conn.execute("DELETE FROM ledger_cash WHERE till_id=?1", [id])? as u32;
        n += conn.execute("DELETE FROM ledger_refunds WHERE till_id=?1", [id])? as u32;
        n += conn.execute("DELETE FROM ledger_spot_checks WHERE till_id=?1", [id])? as u32;
        n += conn.execute("DELETE FROM ledger_tills WHERE id=?1", [id])? as u32;
        conn.execute("DELETE FROM till_reports WHERE till_id=?1", [id])?;
    }

    // Orphans: rows of no till held here, older than the window, not held.
    for (table, kcol, ty, at) in [
        ("ledger_orders", "okey", "order", "created_at"),
        ("ledger_cash", "ckey", "cash_movement", "created_at"),
        ("ledger_refunds", "rkey", "refund", "issued_at"),
    ] {
        let rows: Vec<(String, String)> = {
            let mut st = conn.prepare(&format!(
                "SELECT {kcol}, {at} FROM {table} WHERE till_id NOT IN (SELECT id FROM ledger_tills)"
            ))?;
            let v = st
                .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
                .collect::<Result<Vec<_>, _>>()?;
            v
        };
        for (key, ts) in rows {
            if is_older(&ts, &cutoff_t) && super::apply::deletable(conn, ty, &key, now_ms, None)? {
                n += super::delete_row(conn, ty, &key)?;
            }
        }
    }

    // Stored sale records and server reports: by age, then by count.
    let age_cut = now_ms - KEEP_DAYS * 24 * 3600 * 1000;
    n += conn.execute("DELETE FROM order_details WHERE fetched_at < ?1", [age_cut])? as u32;
    n += conn.execute(
        "DELETE FROM order_details WHERE order_id NOT IN (SELECT order_id FROM order_details ORDER BY fetched_at DESC LIMIT ?1)",
        [MAX_ORDER_DETAILS],
    )? as u32;
    n += conn.execute("DELETE FROM till_reports WHERE fetched_at < ?1", [age_cut])? as u32;
    n += conn.execute(
        "DELETE FROM till_reports WHERE till_id NOT IN (SELECT till_id FROM till_reports ORDER BY fetched_at DESC LIMIT ?1)",
        [MAX_TILL_REPORTS],
    )? as u32;
    Ok(n)
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;
    use serde_json::json;

    use super::*;
    use crate::ledger::{write_row, Origin, T_CASH, T_ORDER, T_TILL};
    use crate::store::{enqueue_on, NewOutboxOp, Store};

    const NOW: i64 = 1_789_000_000_000; // 2026-09-10

    fn at(days_ago: i64) -> String {
        (chrono::DateTime::<chrono::Utc>::from_timestamp_millis(NOW).unwrap() - chrono::Duration::days(days_ago)).to_rfc3339()
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(64))]
        /// Whatever the ages, statuses and queue, a sweep never removes a row a
        /// live op holds (nor its till), and always removes old unheld closed tills.
        #[test]
        fn a_sweep_never_deletes_a_held_row(
            tills in prop::collection::vec((0i64..90, prop::bool::ANY, prop::bool::ANY, 0usize..3), 1..12)
        ) {
            let store = Store::open("").unwrap();
            let mut held_orders = Vec::new();
            let mut expect_gone = Vec::new();
            store.with_tx(|tx| {
                for (n, (age, open, hold_sale, sales)) in tills.iter().enumerate() {
                    let id = format!("T{n}");
                    write_row(tx, T_TILL, &id, &json!({"id": id, "branch_id": "B", "teller_id": "t",
                        "status": if *open { "open" } else { "closed" }, "opened_at": at(age + 1),
                        "closed_at": if *open { serde_json::Value::Null } else { json!(at(*age)) }}), Origin::Feed(1), None)?;
                    for s in 0..*sales {
                        let key = format!("{id}-o{s}");
                        write_row(tx, T_ORDER, &key, &json!({"id": key, "till_id": id, "branch_id": "B", "status": "completed",
                            "payment_method": "Cash", "created_at": at(*age)}), Origin::Feed(1), None)?;
                        if *hold_sale && s == 0 {
                            enqueue_on(tx, &NewOutboxOp { id: format!("op-{key}"), op_type: "void_order".into(),
                                idempotency_key: key.clone(), payload: "{}".into(), event_at: "t".into(),
                                entity_type: Some(T_ORDER.into()), entity_id: Some(key.clone()), ..Default::default() })?;
                            held_orders.push(key.clone());
                        }
                    }
                    let unheld = !*hold_sale || *sales == 0;
                    if !*open && *age > KEEP_DAYS && unheld {
                        expect_gone.push(id.clone());
                    }
                }
                write_row(tx, T_CASH, "m-held", &json!({"id": "m-held", "till_id": "gone", "amount": 5, "kind": "pay_in",
                    "created_at": at(365)}), Origin::Local, None)?;
                enqueue_on(tx, &NewOutboxOp { id: "op-m".into(), op_type: "cash_movement".into(), idempotency_key: "m".into(),
                    payload: "{}".into(), event_at: "t".into(), entity_type: Some(T_CASH.into()),
                    entity_id: Some("m-held".into()), ..Default::default() })?;
                Ok(())
            }).unwrap();
            store.with_tx(|tx| sweep(tx, NOW)).unwrap();
            let count = |sql: &str, arg: &str| -> i64 {
                store.with_conn(|c| Ok(c.query_row(sql, [arg], |r| r.get(0))?)).unwrap()
            };
            for key in &held_orders {
                prop_assert_eq!(count("SELECT COUNT(*) FROM ledger_orders WHERE okey=?1", key), 1, "held sale {} kept", key);
                let till = key.split('-').next().unwrap();
                prop_assert_eq!(count("SELECT COUNT(*) FROM ledger_tills WHERE id=?1", till), 1, "its till {} kept", till);
            }
            for id in &expect_gone {
                prop_assert_eq!(count("SELECT COUNT(*) FROM ledger_tills WHERE id=?1", id), 0, "old unheld closed till {} evicted", id);
            }
            prop_assert_eq!(count("SELECT COUNT(*) FROM ledger_cash WHERE ckey=?1", "m-held"), 1, "a queued movement is never an orphan to sweep");
        }
    }

    #[test]
    fn open_tills_and_recent_closed_tills_stay() {
        let store = Store::open("").unwrap();
        store
            .with_tx(|tx| {
                write_row(tx, T_TILL, "open-old", &json!({"id": "open-old", "status": "open", "opened_at": at(200)}), Origin::Feed(1), None)?;
                write_row(tx, T_TILL, "closed-new", &json!({"id": "closed-new", "status": "closed", "opened_at": at(3), "closed_at": at(2)}), Origin::Feed(1), None)?;
                write_row(tx, T_TILL, "closed-old", &json!({"id": "closed-old", "status": "closed", "opened_at": at(41), "closed_at": at(40)}), Origin::Feed(1), None)?;
                Ok(())
            })
            .unwrap();
        store.with_tx(|tx| sweep(tx, NOW)).unwrap();
        let ids: Vec<String> = store
            .with_conn(|c| {
                let mut st = c.prepare("SELECT id FROM ledger_tills ORDER BY id")?;
                let v = st.query_map([], |r| r.get(0))?.collect::<Result<Vec<_>, _>>()?;
                Ok(v)
            })
            .unwrap();
        assert_eq!(ids, vec!["closed-new".to_string(), "open-old".to_string()]);
    }
}
