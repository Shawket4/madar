//! Staff drinks as local rows (owner design 2026-09-19).
//!
//! The pool count MUST work with no network and MUST survive a restart, so the
//! drinks this branch recorded live here, one row per drink, keyed by the
//! client-minted id the outbox op carries. That one identity is what makes the
//! three ways a drink reaches this device the SAME row:
//!
//! * rung here — written with its outbox op in one transaction (`commit`);
//! * heard over the LAN — a peer's drink, applied at once so two tills at one
//!   counter never both spend the last drink of the day;
//! * brought by the cloud feed — the `staff_drink` type of `/sync/pull`.
//!
//! The row is stored under its BRANCH and its BUSINESS DATE (the branch-local
//! day the engine decided it on, never the device's calendar), because that
//! pair is the only thing the count is ever taken over — and a date column is
//! exactly why the pool resets by itself at the end of the business day with
//! nothing to run.
//!
//! A row this device still has a live op on is protected, as everywhere else:
//! the feed remembers what the server says but does not overwrite the teller.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::Value;

use super::{now_ms, s};
use crate::error::CoreResult;
use crate::store::{enqueue_on, NewOutboxOp};

/// The outbox op (and the entity type it names its row with).
pub(crate) const T_STAFF_DRINK: &str = "record_staff_drink";

/// The changefeed wire type the server sends these under.
pub(crate) const WIRE: &str = "staff_drink";

/// Write one drink, from wherever it came.
pub(crate) fn upsert(conn: &Connection, v: &Value, origin: &str) -> CoreResult<()> {
    let (Some(id), Some(branch), Some(day)) = (s(v, "id"), s(v, "branch_id"), s(v, "business_date")) else {
        return Ok(());
    };
    // A date the server sends as a full instant still names one day.
    let day = day.get(..10).unwrap_or(day);
    let qty = v.get("quantity").and_then(Value::as_i64).unwrap_or(1).max(0);
    conn.prepare_cached(
        "INSERT INTO ledger_staff_drinks(id, branch_id, business_date, quantity, recorded_at, raw, origin, local_updated_at)
         VALUES(?1,?2,?3,?4,?5,?6,?7,?8)
         ON CONFLICT(id) DO UPDATE SET branch_id=excluded.branch_id, business_date=excluded.business_date,
           quantity=excluded.quantity, recorded_at=excluded.recorded_at, raw=excluded.raw,
           origin=excluded.origin, local_updated_at=excluded.local_updated_at",
    )?
    .execute(params![id, branch, day, qty, s(v, "recorded_at").unwrap_or(""), v.to_string(), origin, now_ms()])?;
    Ok(())
}

/// A server row, unless a live local op holds it (A3, as everywhere else).
pub(crate) fn from_feed(conn: &Connection, v: &Value) -> CoreResult<()> {
    let Some(id) = s(v, "id") else { return Ok(()) };
    if super::is_protected(conn, T_STAFF_DRINK, id)? {
        return Ok(());
    }
    upsert(conn, v, "server")
}

/// The server says this drink is gone (a snapshot swept it, or a delete).
pub(crate) fn forget(conn: &Connection, id: &str) -> CoreResult<usize> {
    if super::is_protected(conn, T_STAFF_DRINK, id)? {
        return Ok(0);
    }
    Ok(conn.execute("DELETE FROM ledger_staff_drinks WHERE id=?1 AND origin<>'local'", [id])?)
}

/// Queue a drink: the outbox op and the row, ONE transaction.
pub(crate) fn commit(tx: &Connection, op: &NewOutboxOp, row: &Value) -> CoreResult<i64> {
    let seq = enqueue_on(tx, op)?;
    upsert(tx, row, "local")?;
    Ok(seq)
}

/// A stored row's raw JSON.
pub(crate) fn raw(conn: &Connection, id: &str) -> CoreResult<Option<Value>> {
    Ok(conn
        .query_row("SELECT raw FROM ledger_staff_drinks WHERE id=?1", [id], |r| r.get::<_, String>(0))
        .optional()?
        .and_then(|r| serde_json::from_str(&r).ok()))
}

/// How many drinks a branch has spent on `business_date`, as this device knows
/// it — the SUM of the quantities, exactly what the server counts
/// (`staff_pool::record::used_on`), not the number of rows.
pub(crate) fn used_on(conn: &Connection, branch_id: &str, business_date: &str) -> CoreResult<i32> {
    let n: i64 = conn
        .prepare_cached(
            "SELECT COALESCE(SUM(quantity),0) FROM ledger_staff_drinks WHERE branch_id=?1 AND business_date=?2",
        )?
        .query_row(params![branch_id, business_date], |r| r.get(0))?;
    Ok(n.clamp(0, i32::MAX as i64) as i32)
}

/// One recorded drink as the screens read it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct StaffDrinkRow {
    pub id: String,
    pub item_name: String,
    pub size_label: Option<String>,
    pub quantity: i32,
    pub note: String,
    pub overspent: bool,
    pub recorded_at: String,
    /// Its op is still in the outbox.
    pub queued: bool,
}

/// A branch's drinks on one business date, oldest first (ties by id) — the
/// server's `ORDER BY recorded_at, id`.
pub(crate) fn for_day(conn: &Connection, branch_id: &str, business_date: &str) -> CoreResult<Vec<StaffDrinkRow>> {
    let mut st = conn.prepare(
        "SELECT d.raw, EXISTS(SELECT 1 FROM outbox x WHERE x.entity_type=?3 AND x.entity_id=d.id
                                AND x.status IN ('pending','inflight','dead'))
           FROM ledger_staff_drinks d WHERE d.branch_id=?1 AND d.business_date=?2",
    )?;
    let mut out: Vec<StaffDrinkRow> = st
        .query_map(params![branch_id, business_date, T_STAFF_DRINK], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))
        })?
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .map(|(raw, queued)| {
            let v: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
            StaffDrinkRow {
                id: s(&v, "id").unwrap_or("").to_string(),
                item_name: s(&v, "item_name").unwrap_or("").to_string(),
                size_label: s(&v, "size_label").map(str::to_string),
                quantity: v.get("quantity").and_then(Value::as_i64).unwrap_or(1) as i32,
                note: s(&v, "note").unwrap_or("").to_string(),
                overspent: v.get("overspent").and_then(Value::as_bool).unwrap_or(false),
                recorded_at: s(&v, "recorded_at").unwrap_or("").to_string(),
                queued: queued != 0,
            }
        })
        .collect();
    out.sort_by(|a, b| {
        let ta = chrono::DateTime::parse_from_rfc3339(&a.recorded_at).ok();
        let tb = chrono::DateTime::parse_from_rfc3339(&b.recorded_at).ok();
        ta.cmp(&tb).then_with(|| a.id.cmp(&b.id))
    });
    Ok(out)
}
