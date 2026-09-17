//! Cash spot checks as local rows (owner design 2026-09-16 item 5).
//!
//! A spot check is a FACT about a drawer at a moment: what was counted, what the
//! system expected then, and the difference. It never moves the drawer. One row
//! per check, keyed by its client-minted id, so the queued row and the one the
//! feed later brings inside the `till` projection (`spot_checks`) are the same
//! row. Nothing deletes a check except the till's own retention sweep.

use rusqlite::{params, Connection};
use serde_json::Value;

use super::{i, now_ms, s};
use crate::error::CoreResult;
use crate::store::{enqueue_on, NewOutboxOp};

/// Changefeed-less entity type the outbox op names its row with.
pub(crate) const T_SPOT: &str = "cash_spot_check";

fn upsert(conn: &Connection, v: &Value, origin: &str) -> CoreResult<()> {
    let (Some(id), Some(till)) = (s(v, "id"), s(v, "till_id")) else { return Ok(()) };
    conn.prepare_cached(
        "INSERT INTO ledger_spot_checks(id, till_id, checked_at, raw, origin, local_updated_at)
         VALUES(?1,?2,?3,?4,?5,?6)
         ON CONFLICT(id) DO UPDATE SET till_id=excluded.till_id, checked_at=excluded.checked_at,
           raw=excluded.raw, origin=excluded.origin, local_updated_at=excluded.local_updated_at",
    )?
    .execute(params![id, till, s(v, "checked_at").unwrap_or(""), v.to_string(), origin, now_ms()])?;
    Ok(())
}

/// Queue a spot check: its outbox op and its row, one transaction.
pub(crate) fn commit(tx: &Connection, op: &NewOutboxOp, row: &Value) -> CoreResult<i64> {
    let seq = enqueue_on(tx, op)?;
    upsert(tx, row, "local")?;
    Ok(seq)
}

/// The checks a server till row carries (`spot_checks`), as server rows.
pub(crate) fn from_till_row(conn: &Connection, till: &Value) -> CoreResult<()> {
    let Some(list) = till.get("spot_checks").and_then(Value::as_array) else { return Ok(()) };
    let till_id = s(till, "id").unwrap_or("");
    for c in list {
        let mut c = c.clone();
        if s(&c, "till_id").is_none() {
            if let Value::Object(m) = &mut c {
                m.insert("till_id".into(), Value::from(till_id));
            }
        }
        upsert(conn, &c, "server")?;
    }
    Ok(())
}

/// One check as the report and the views read it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SpotRow {
    pub id: String,
    pub counted_cash: i64,
    pub expected_cash: i64,
    pub cash_discrepancy: i64,
    pub checked_by_name: String,
    pub approved_by_name: Option<String>,
    pub checked_at: String,
    pub note: Option<String>,
    /// Per-method lines `[{method, is_cash, expected, counted, discrepancy}]`.
    pub methods: Value,
    /// Its op is still in the outbox.
    pub queued: bool,
}

/// A till's checks, oldest first (as instants; ties by id) — the server's
/// `ORDER BY checked_at, id`.
pub(crate) fn for_till(conn: &Connection, till_id: &str) -> CoreResult<Vec<SpotRow>> {
    let mut st = conn.prepare(
        "SELECT c.raw, EXISTS(SELECT 1 FROM outbox x WHERE x.entity_type=?2 AND x.entity_id=c.id
                                AND x.status IN ('pending','inflight','dead'))
           FROM ledger_spot_checks c WHERE c.till_id=?1",
    )?;
    let mut out: Vec<SpotRow> = st
        .query_map(params![till_id, T_SPOT], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))?
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .map(|(raw, queued)| {
            let v: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
            SpotRow {
                id: s(&v, "id").unwrap_or("").to_string(),
                counted_cash: i(&v, "counted_cash"),
                expected_cash: i(&v, "expected_cash"),
                cash_discrepancy: i(&v, "cash_discrepancy"),
                checked_by_name: s(&v, "checked_by_name").unwrap_or("").to_string(),
                approved_by_name: s(&v, "approved_by_name").map(str::to_string),
                checked_at: s(&v, "checked_at").unwrap_or("").to_string(),
                note: s(&v, "note").map(str::to_string),
                methods: v.get("methods").cloned().unwrap_or(Value::Array(Vec::new())),
                queued: queued != 0,
            }
        })
        .collect();
    out.sort_by(|a, b| {
        let ta = chrono::DateTime::parse_from_rfc3339(&a.checked_at).ok();
        let tb = chrono::DateTime::parse_from_rfc3339(&b.checked_at).ok();
        ta.cmp(&tb).then_with(|| a.id.cmp(&b.id))
    });
    Ok(out)
}
