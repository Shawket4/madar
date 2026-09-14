//! Changefeed rows → ledger rows, inside the page transaction (§4, §5).
//!
//! Per row, in order:
//! 1. an older seq than the row already holds is ignored (never regress);
//! 2. a PROTECTED row (a live outbox op holds it) keeps the teller's state; the
//!    server's version is remembered in `srv_raw` and the seq advances;
//! 3. otherwise the server row replaces the local one.
//!
//! A delete (a tombstone, or a full snapshot that no longer lists a row inside
//! its ledger window) never removes a protected row, nor a row the server just
//! acknowledged that the feed has not caught up with yet — that is the window in
//! which a sale used to vanish (OFFLINE_B_DESIGN §0, audit row 2).

use rusqlite::{params, Connection};
use serde_json::Value;

use super::{is_protected, key_of, stored_meta, write_row, Origin, T_CASH, T_ORDER, T_REFUND, T_TILL};
use crate::error::CoreResult;

/// A row acknowledged by the server but not yet seen in the feed is kept for at
/// least this long even when a snapshot does not list it (a pull that started
/// before the ack committed cannot know about it).
pub(crate) const ACK_GRACE_MS: i64 = 10 * 60 * 1000;

/// What the page being applied is.
#[derive(Debug, Clone)]
pub(crate) struct PageCtx {
    /// A full snapshot of the ledger types (`ledger_window.from` known).
    pub full: bool,
    /// The snapshot's ledger window start (RFC 3339), for full pages.
    pub window_from: Option<chrono::DateTime<chrono::Utc>>,
    /// The ledger window of the stream's last full snapshot — a till first seen
    /// in an incremental page is complete only if it opened inside it.
    pub stream_window_from: Option<chrono::DateTime<chrono::Utc>>,
    pub now_ms: i64,
    /// The page's feed horizon (`next`): every change at or below it is in
    /// what the device now holds. `None` when unknown (tests, backfills).
    pub horizon: Option<i64>,
}

fn ts(v: &str) -> Option<chrono::DateTime<chrono::Utc>> {
    chrono::DateTime::parse_from_rfc3339(v).ok().map(|d| d.with_timezone(&chrono::Utc))
}

/// Apply one upserted ledger row. Returns true when local data changed.
pub(crate) fn upsert(conn: &Connection, ty: &str, v: &Value, seq: i64, ctx: &PageCtx) -> CoreResult<bool> {
    let Some(key) = key_of(ty, v) else { return Ok(false) };
    // The row it IS, under whatever key it was first stored (§7).
    let key = super::resolve_key(conn, ty, v, &key)?;
    let prev = stored_meta(conn, ty, &key)?;
    if let Some(p) = &prev {
        if seq < p.srv_seq {
            return Ok(false);
        }
    }
    let protected = is_protected(conn, ty, &key)?;
    let mut changed = false;
    if protected && prev.is_some() {
        super::shadow(conn, ty, &key, v, seq)?;
    } else {
        write_row(conn, ty, &key, v, Origin::Feed(seq), None)?;
        changed = true;
        if protected {
            // The op's row was not on this device (a void of a sale this device
            // never held): put the teller's intent back over the server row.
            super::local::reapply_pending(conn, ty, &key)?;
        }
    }
    if ty == T_TILL {
        mark_till_complete(conn, &key, v, prev.is_none(), ctx)?;
    }
    Ok(changed)
}

/// A till's ledger is complete on this device when every row of it has reached
/// the device: it was open at the full snapshot (whose window carries an open
/// till's whole history), it opened inside the snapshot's window, or it first
/// appeared after the stream's snapshot and opened inside that window.
fn mark_till_complete(conn: &Connection, id: &str, v: &Value, first_seen: bool, ctx: &PageCtx) -> CoreResult<()> {
    let opened = super::s(v, "opened_at").and_then(ts);
    let open = super::s(v, "status") == Some("open");
    let complete = if ctx.full {
        open || matches!((opened, ctx.window_from), (Some(o), Some(w)) if o >= w)
    } else if first_seen {
        matches!((opened, ctx.stream_window_from), (Some(o), Some(w)) if o >= w)
    } else {
        false
    };
    if complete {
        conn.execute("UPDATE ledger_tills SET complete=1 WHERE id=?1", [id])?;
    }
    Ok(())
}

/// May a delete remove row `key`? Never a protected row, a row still local, or
/// an acknowledged row the feed has not shown yet. When the ack named its feed
/// horizon (`X-Madar-Sync-Seq`) that is decided by seq — a page whose horizon
/// has reached it and still lacks the row means the row is gone; otherwise by a
/// grace period after the ack.
pub(crate) fn deletable(conn: &Connection, ty: &str, key: &str, now_ms: i64, horizon: Option<i64>) -> CoreResult<bool> {
    if is_protected(conn, ty, key)? {
        return Ok(false);
    }
    let Some(p) = stored_meta(conn, ty, key)? else { return Ok(false) };
    if p.origin == "local" && p.srv_seq == 0 && !p.acked {
        // A local row with no op and no ack: its op was discarded but the row
        // was not (should not happen); leave it to the discard path.
        return Ok(false);
    }
    if p.acked && p.srv_seq == 0 {
        if let (Some(ack), Some(h)) = (p.ack_seq, horizon) {
            return Ok(h >= ack);
        }
        let (table, kcol) = super::table_of(ty).unwrap();
        let updated: i64 = conn.query_row(
            &format!("SELECT local_updated_at FROM {table} WHERE {kcol}=?1"),
            [key],
            |r| r.get(0),
        )?;
        if now_ms - updated < ACK_GRACE_MS {
            return Ok(false);
        }
    }
    Ok(true)
}

/// A tombstone for a ledger entity (server id).
pub(crate) fn delete(conn: &Connection, ty: &str, server_id: &str, ctx: &PageCtx) -> CoreResult<bool> {
    let Some(key) = key_for_server_id(conn, ty, server_id)? else { return Ok(false) };
    if !deletable(conn, ty, &key, ctx.now_ms, ctx.horizon)? {
        return Ok(false);
    }
    Ok(super::delete_row(conn, ty, &key)? > 0)
}

fn key_for_server_id(conn: &Connection, ty: &str, server_id: &str) -> CoreResult<Option<String>> {
    use rusqlite::OptionalExtension;
    let (table, kcol) = super::table_of(ty).unwrap();
    let sql = if ty == T_TILL {
        format!("SELECT {kcol} FROM {table} WHERE id=?1")
    } else {
        format!("SELECT {kcol} FROM {table} WHERE server_id=?1 OR {kcol}=?1 LIMIT 1")
    };
    Ok(conn.query_row(&sql, [server_id], |r| r.get(0)).optional()?)
}

/// After a full snapshot of `ty`: remove server rows inside the ledger window
/// that the snapshot no longer lists. Rows older than the window stay until
/// retention prunes them (the snapshot says nothing about them).
pub(crate) fn sweep_absent(
    conn: &Connection,
    branch: &str,
    ty: &str,
    present_keys: &std::collections::HashSet<String>,
    ctx: &PageCtx,
) -> CoreResult<u32> {
    let (table, kcol) = super::table_of(ty).unwrap();
    // The instant that places a row in or out of the window, per type (the
    // server windows by change time; a row's own latest business time is the
    // closest the device has).
    let time_cols = match ty {
        T_TILL => "COALESCE(closed_at, opened_at)",
        T_ORDER => "created_at",
        T_CASH => "created_at",
        T_REFUND => "issued_at",
        _ => return Ok(0),
    };
    let branch_filter = match ty {
        T_TILL => "branch_id=?1",
        T_ORDER => "branch_id=?1",
        // Movements and refunds belong to the branch through their till.
        T_CASH | T_REFUND => "till_id IN (SELECT id FROM ledger_tills WHERE branch_id=?1)",
        _ => unreachable!(),
    };
    let rows: Vec<(String, String, Option<String>)> = {
        let mut st = conn.prepare(&format!(
            "SELECT {kcol}, {time_cols}, raw FROM {table} WHERE {branch_filter}"
        ))?;
        let v = st
            .query_map(params![branch], |r| Ok((r.get(0)?, r.get::<_, String>(1)?, r.get(2)?)))?
            .collect::<Result<Vec<_>, _>>()?;
        v
    };
    let mut n = 0;
    for (key, at, raw) in rows {
        if present_keys.contains(&key) {
            continue;
        }
        let inside = match (ctx.window_from, ts(&at)) {
            (Some(w), Some(t)) => t >= w,
            (None, _) => true,
            _ => false,
        };
        // A row of a till that is open is inside the window whatever its age:
        // the snapshot carries an open till's whole history.
        let of_open_till = ty != T_TILL
            && raw
                .as_deref()
                .and_then(|r| serde_json::from_str::<Value>(r).ok())
                .and_then(|v| super::s(&v, "till_id").map(str::to_string))
                .map(|t| {
                    conn.query_row("SELECT status FROM ledger_tills WHERE id=?1", [t], |r| r.get::<_, String>(0))
                        .map(|s| s == "open")
                        .unwrap_or(false)
                })
                .unwrap_or(false);
        if !(inside || of_open_till) {
            continue;
        }
        if deletable(conn, ty, &key, ctx.now_ms, ctx.horizon)? {
            n += super::delete_row(conn, ty, &key)?;
        }
    }
    Ok(n)
}
