//! Cash spot report views as local rows (owner design 2026-09-16 item 5,
//! corrected 2026-09-17).
//!
//! The cash spot is the live till report; nothing is counted. What is kept is
//! the audit trail: who viewed the spot report, when, whether it was printed,
//! and whose PIN unlocked it. One row per view, keyed by its client-minted id,
//! so the queued row, its print, and the one the feed later brings inside the
//! `till` projection (`spot_views`) are the same row.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::Value;

use super::{now_ms, s};
use crate::error::CoreResult;
use crate::store::{enqueue_on, NewOutboxOp};

/// The outbox op (and the entity type it names its row with).
pub(crate) const T_SPOT: &str = "spot_report_view";

fn upsert(conn: &Connection, v: &Value, origin: &str) -> CoreResult<()> {
    let (Some(id), Some(till)) = (s(v, "id"), s(v, "till_id")) else { return Ok(()) };
    conn.prepare_cached(
        "INSERT INTO ledger_spot_views(id, till_id, viewed_at, raw, origin, local_updated_at)
         VALUES(?1,?2,?3,?4,?5,?6)
         ON CONFLICT(id) DO UPDATE SET till_id=excluded.till_id, viewed_at=excluded.viewed_at,
           raw=excluded.raw, origin=excluded.origin, local_updated_at=excluded.local_updated_at",
    )?
    .execute(params![id, till, s(v, "viewed_at").unwrap_or(""), v.to_string(), origin, now_ms()])?;
    Ok(())
}

/// Queue a view (or its print): the outbox op and the row, one transaction.
pub(crate) fn commit(tx: &Connection, op: &NewOutboxOp, row: &Value) -> CoreResult<i64> {
    let seq = enqueue_on(tx, op)?;
    upsert(tx, row, "local")?;
    Ok(seq)
}

/// A stored row's raw JSON.
pub(crate) fn raw(conn: &Connection, id: &str) -> CoreResult<Option<Value>> {
    Ok(conn
        .query_row("SELECT raw FROM ledger_spot_views WHERE id=?1", [id], |r| r.get::<_, String>(0))
        .optional()?
        .and_then(|r| serde_json::from_str(&r).ok()))
}

/// The views a server till row carries (`spot_views`), as server rows. A row
/// this device still has a live op on keeps its local version.
pub(crate) fn from_till_row(conn: &Connection, till: &Value) -> CoreResult<()> {
    let Some(list) = till.get("spot_views").and_then(Value::as_array) else { return Ok(()) };
    let till_id = s(till, "id").unwrap_or("");
    for v in list {
        let mut v = v.clone();
        if s(&v, "till_id").is_none() {
            if let Value::Object(m) = &mut v {
                m.insert("till_id".into(), Value::from(till_id));
            }
        }
        let held = s(&v, "id").is_some_and(|id| {
            super::is_protected(conn, T_SPOT, id).unwrap_or(false)
        });
        if !held {
            upsert(conn, &v, "server")?;
        }
    }
    Ok(())
}

/// One view as the report and the screens read it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SpotRow {
    pub id: String,
    pub viewed_by_name: String,
    pub approved_by_name: Option<String>,
    pub viewed_at: String,
    pub printed: bool,
    /// Its op is still in the outbox.
    pub queued: bool,
}

/// A till's views, oldest first (as instants; ties by id) — the server's
/// `ORDER BY viewed_at, id`.
pub(crate) fn for_till(conn: &Connection, till_id: &str) -> CoreResult<Vec<SpotRow>> {
    let mut st = conn.prepare(
        "SELECT c.raw, EXISTS(SELECT 1 FROM outbox x WHERE x.entity_type=?2 AND x.entity_id=c.id
                                AND x.status IN ('pending','inflight','dead'))
           FROM ledger_spot_views c WHERE c.till_id=?1",
    )?;
    let mut out: Vec<SpotRow> = st
        .query_map(params![till_id, T_SPOT], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))?
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .map(|(raw, queued)| {
            let v: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
            SpotRow {
                id: s(&v, "id").unwrap_or("").to_string(),
                viewed_by_name: s(&v, "viewed_by_name").unwrap_or("").to_string(),
                approved_by_name: s(&v, "approved_by_name").map(str::to_string),
                viewed_at: s(&v, "viewed_at").unwrap_or("").to_string(),
                printed: v.get("printed").and_then(Value::as_bool).unwrap_or(false),
                queued: queued != 0,
            }
        })
        .collect();
    out.sort_by(|a, b| {
        let ta = chrono::DateTime::parse_from_rfc3339(&a.viewed_at).ok();
        let tb = chrono::DateTime::parse_from_rfc3339(&b.viewed_at).ok();
        ta.cmp(&tb).then_with(|| a.id.cmp(&b.id))
    });
    Ok(out)
}
