//! The money ledger as local rows (OFFLINE_B_DESIGN §2 P1, §3, §5, §7): tills,
//! orders with their payment legs, cash movements and refunds.
//!
//! Every row has exactly ONE identity from the moment it exists on this device:
//! the client-minted id when there is one (order `idempotency_key`, movement and
//! refund `client_ref`, the till id), else the server id. So a sale rung offline,
//! sent, answered, lost and re-sent is still ONE row, and a till's drawer can be
//! computed from the rows without ever adding two lists together.
//!
//! Three writers, one set of rules:
//! * the changefeed applier ([`apply`]) — server state, by seq;
//! * the write path ([`local`]) — a local mutation, in the SAME transaction as
//!   its outbox op;
//! * ack folding ([`fold`]) — the server's answer to a sent op.
//!
//! A row with a live outbox op on it (pending, inflight or dead) is PROTECTED:
//! server data for it is remembered in `srv_raw` but does not replace what the
//! teller did, until the op resolves (acks, or is discarded).

pub(crate) mod apply;
pub(crate) mod fold;
pub(crate) mod local;
pub(crate) mod migrate;
pub(crate) mod report;
pub(crate) mod retention;
pub(crate) mod spot;
pub(crate) mod views;

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::Value;

use crate::error::CoreResult;

/// Changefeed wire types kept as ledger rows.
pub(crate) const T_TILL: &str = "till";
pub(crate) const T_ORDER: &str = "order";
pub(crate) const T_CASH: &str = "cash_movement";
pub(crate) const T_REFUND: &str = "refund";

pub(crate) fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

pub(crate) fn s<'a>(v: &'a Value, k: &str) -> Option<&'a str> {
    v.get(k).and_then(Value::as_str).filter(|x| !x.is_empty())
}
pub(crate) fn i(v: &Value, k: &str) -> i64 {
    v.get(k).and_then(Value::as_i64).unwrap_or(0)
}
pub(crate) fn b(v: &Value, k: &str) -> Option<bool> {
    v.get(k).and_then(Value::as_bool)
}

/// The local identity of a wire row of `ty` (see the module docs).
pub(crate) fn key_of(ty: &str, v: &Value) -> Option<String> {
    let client = match ty {
        T_ORDER => s(v, "idempotency_key"),
        T_CASH | T_REFUND => s(v, "client_ref"),
        _ => None,
    };
    client.or_else(|| s(v, "id")).map(str::to_string)
}

/// The ledger table + key column for a wire type.
pub(crate) fn table_of(ty: &str) -> Option<(&'static str, &'static str)> {
    Some(match ty {
        T_TILL => ("ledger_tills", "id"),
        T_ORDER => ("ledger_orders", "okey"),
        T_CASH => ("ledger_cash", "ckey"),
        T_REFUND => ("ledger_refunds", "rkey"),
        _ => return None,
    })
}

pub(crate) fn is_ledger_type(ty: &str) -> bool {
    table_of(ty).is_some()
}

/// A live outbox op (pending / inflight / dead) holds this row.
/// `execute` through the connection's statement cache: a snapshot applies tens
/// of thousands of rows through the same few statements.
fn exec<P: rusqlite::Params>(conn: &Connection, sql: &str, params: P) -> rusqlite::Result<usize> {
    conn.prepare_cached(sql)?.execute(params)
}

pub(crate) fn is_protected(conn: &Connection, ty: &str, key: &str) -> CoreResult<bool> {
    Ok(conn
        .prepare_cached(
            "SELECT 1 FROM outbox WHERE entity_type=?1 AND entity_id=?2 AND status IN ('pending','inflight','dead') LIMIT 1",
        )?
        .query_row(params![ty, key], |_| Ok(()))
        .optional()?
        .is_some())
}

/// What the store holds for one ledger row.
#[derive(Debug, Clone)]
pub(crate) struct Stored {
    pub raw: Value,
    pub srv_raw: Option<Value>,
    pub srv_seq: i64,
    pub origin: String,
    pub acked: bool,
}

pub(crate) fn stored(conn: &Connection, ty: &str, key: &str) -> CoreResult<Option<Stored>> {
    let (table, kcol) = table_of(ty).expect("ledger type");
    let acked = "acked";
    let row: Option<(String, Option<String>, i64, String, i64)> = conn
        .prepare_cached(&format!("SELECT raw, srv_raw, srv_seq, origin, {acked} FROM {table} WHERE {kcol}=?1"))?
        .query_row([key], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)))
        .optional()?;
    Ok(row.map(|(raw, srv_raw, srv_seq, origin, acked)| Stored {
        raw: serde_json::from_str(&raw).unwrap_or(Value::Null),
        srv_raw: srv_raw.and_then(|x| serde_json::from_str(&x).ok()),
        srv_seq,
        origin,
        acked: acked != 0,
    }))
}

/// A stored row's bookkeeping only (no JSON parsed): what the apply path checks.
#[derive(Debug, Clone)]
pub(crate) struct Meta {
    pub srv_seq: i64,
    pub origin: String,
    pub acked: bool,
    /// The feed horizon that includes the acked op (`X-Madar-Sync-Seq`).
    pub ack_seq: Option<i64>,
    /// origin `peer`: the seq the LAN peer claimed.
    pub peer_seq: Option<i64>,
}

pub(crate) fn stored_meta(conn: &Connection, ty: &str, key: &str) -> CoreResult<Option<Meta>> {
    let (table, kcol) = table_of(ty).expect("ledger type");
    Ok(conn
        .prepare_cached(&format!("SELECT srv_seq, origin, acked, ack_seq, peer_seq FROM {table} WHERE {kcol}=?1"))?
        .query_row([key], |r| {
            Ok(Meta {
                srv_seq: r.get(0)?,
                origin: r.get(1)?,
                acked: r.get::<_, i64>(2)? != 0,
                ack_seq: r.get(3)?,
                peer_seq: r.get(4)?,
            })
        })
        .optional()?)
}

/// The key of the order row a server order id (or a client key) names.
pub(crate) fn order_key_for(conn: &Connection, id_or_key: &str) -> CoreResult<Option<String>> {
    Ok(conn
        .query_row(
            "SELECT okey FROM ledger_orders WHERE okey=?1 OR server_id=?1 LIMIT 1",
            [id_or_key],
            |r| r.get(0),
        )
        .optional()?)
}

/// The one identity rule (OFFLINE_B_DESIGN §7), for EVERY writer: a wire row is
/// the stored row whose key is its client key (order `idempotency_key`, movement
/// and refund `client_ref`), else whose `server_id` is its `id`, else (orders)
/// whose `order_ref` is its `order_ref` or whose key is its `open_ticket_id`
/// (a settled bill's row is keyed by its ticket). A row first stored under its
/// server id (a history fetch, a pre-B cache, an ack with no body) is RE-KEYED
/// to the client key when that key becomes known, and rows that turn out to be
/// the same sale are merged — never a second row, and never a UNIQUE
/// `server_id` failure that rolls back a whole feed page.
///
/// Returns the key the row now lives under (`proposed` when nothing matches).
pub(crate) fn resolve_key(conn: &Connection, ty: &str, v: &Value, proposed: &str) -> CoreResult<String> {
    if ty == T_TILL {
        return Ok(proposed.to_string());
    }
    let Some((table, kcol)) = table_of(ty) else { return Ok(proposed.to_string()) };
    let client = match ty {
        T_ORDER => s(v, "idempotency_key"),
        _ => s(v, "client_ref"),
    }
    .map(str::to_string);
    let sid = s(v, "id").map(str::to_string);
    let mut found: Vec<String> = Vec::new();
    let add = |k: String, found: &mut Vec<String>| {
        if !found.contains(&k) {
            found.push(k);
        }
    };
    let by_key = format!("SELECT {kcol} FROM {table} WHERE {kcol}=?1");
    let mut probe_keys: Vec<&str> = vec![proposed];
    if let Some(c) = client.as_deref() {
        probe_keys.push(c);
    }
    if let Some(id) = sid.as_deref() {
        probe_keys.push(id);
    }
    let ticket = if ty == T_ORDER { s(v, "open_ticket_id") } else { None };
    if let Some(t) = ticket {
        probe_keys.push(t);
    }
    for k in probe_keys {
        if let Some(hit) = conn.prepare_cached(&by_key)?.query_row([k], |r| r.get::<_, String>(0)).optional()? {
            add(hit, &mut found);
        }
    }
    if let Some(id) = sid.as_deref() {
        let q = format!("SELECT {kcol} FROM {table} WHERE server_id=?1");
        if let Some(hit) = conn.prepare_cached(&q)?.query_row([id], |r| r.get::<_, String>(0)).optional()? {
            add(hit, &mut found);
        }
    }
    if ty == T_ORDER {
        if let Some(r) = s(v, "order_ref") {
            let hits: Vec<String> = conn
                .prepare_cached("SELECT okey FROM ledger_orders WHERE order_ref=?1")?
                .query_map([r], |row| row.get(0))?
                .collect::<Result<_, _>>()?;
            for h in hits {
                add(h, &mut found);
            }
        }
    }
    // The key it should live under: its client key when known; else the key it
    // already has (a client-keyed row before a server-keyed one).
    let canonical = client
        .clone()
        .or_else(|| found.iter().find(|k| k.as_str() == proposed).cloned())
        .or_else(|| found.iter().find(|k| Some(k.as_str()) != sid.as_deref()).cloned())
        .or_else(|| found.first().cloned())
        .unwrap_or_else(|| proposed.to_string());
    let others: Vec<String> = found.iter().filter(|k| **k != canonical).cloned().collect();
    if others.is_empty() {
        return Ok(canonical);
    }
    // Merge: every other row folds into the canonical one.
    let meta = |k: &str| -> CoreResult<(i64, i64, Option<String>)> {
        Ok(conn.query_row(
            &format!("SELECT srv_seq, acked, server_id FROM {table} WHERE {kcol}=?1"),
            [k],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )?)
    };
    let mut max_seq = 0i64;
    let mut any_acked = 0i64;
    let mut server_id: Option<String> = None;
    for k in &found {
        let (seq, acked, sid_col) = meta(k)?;
        max_seq = max_seq.max(seq);
        any_acked = any_acked.max(acked);
        if server_id.is_none() {
            server_id = sid_col;
        }
    }
    let canonical_exists = found.contains(&canonical);
    let mut to_delete = others.clone();
    if !canonical_exists {
        // Rename the most server-confirmed of them; the rest are deleted.
        let mut best = to_delete[0].clone();
        let mut best_seq = -1;
        for k in &to_delete {
            let (seq, _, _) = meta(k)?;
            if seq > best_seq {
                best_seq = seq;
                best = k.clone();
            }
        }
        to_delete.retain(|k| *k != best);
        for k in &to_delete {
            conn.execute(&format!("DELETE FROM {table} WHERE {kcol}=?1"), [k])?;
        }
        conn.execute(&format!("UPDATE {table} SET {kcol}=?1 WHERE {kcol}=?2"), params![canonical, best])?;
        conn.execute(
            "UPDATE outbox SET entity_id=?1 WHERE entity_type=?2 AND entity_id=?3",
            params![canonical, ty, best],
        )?;
    } else {
        for k in &to_delete {
            conn.execute(&format!("DELETE FROM {table} WHERE {kcol}=?1"), [k])?;
        }
    }
    for k in &to_delete {
        conn.execute(
            "UPDATE outbox SET entity_id=?1 WHERE entity_type=?2 AND entity_id=?3",
            params![canonical, ty, k],
        )?;
    }
    conn.execute(
        &format!(
            "UPDATE {table} SET srv_seq=MAX(srv_seq, ?1), acked=MAX(acked, ?2), server_id=COALESCE(server_id, ?3) WHERE {kcol}=?4"
        ),
        params![max_seq, any_acked, server_id, canonical],
    )?;
    Ok(canonical)
}

/// Where a row came from, for [`write_row`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Origin {
    /// The changefeed at this seq.
    Feed(i64),
    /// A server read outside the feed (a paged history fetch): seq 0, so any
    /// feed row supersedes it.
    Fetch,
    /// The server's answer to one of this device's ops.
    Ack,
    /// This device, before the server has answered.
    Local,
    /// A LAN peer's copy of a feed row at the seq it claimed (OFFLINE_B_DESIGN
    /// "LAN catch-up"): unconfirmed — srv_seq stays 0 so every cloud write wins,
    /// and a pull past that seq that did not confirm it removes it.
    Peer(i64),
}

/// Write `v` as row `key` of `ty`, replacing what is there. The caller has
/// already decided it SHOULD replace (the protection and seq rules live in
/// `apply`, `local` and `fold`).
pub(crate) fn write_row(
    conn: &Connection,
    ty: &str,
    key: &str,
    v: &Value,
    origin: Origin,
    srv_raw: Option<&Value>,
) -> CoreResult<String> {
    let key_owned = resolve_key(conn, ty, v, key)?;
    let key = key_owned.as_str();
    let prev = stored_meta(conn, ty, key)?;
    let srv_seq = match origin {
        Origin::Feed(seq) => seq,
        Origin::Peer(_) => 0,
        _ => prev.as_ref().map(|p| p.srv_seq).unwrap_or(0),
    };
    let origin_word = match origin {
        Origin::Local => "local",
        Origin::Peer(_) => "peer",
        _ => "server",
    };
    // Acked = "the server has this, the feed has not confirmed it yet".
    let acked = match origin {
        Origin::Ack => true,
        Origin::Feed(_) | Origin::Peer(_) => false,
        _ => prev.as_ref().map(|p| p.acked).unwrap_or(false),
    };
    let raw = v.to_string();
    let srv = srv_raw.map(Value::to_string);
    let now = now_ms();
    match ty {
        T_TILL => {
            exec(conn, 
                "INSERT INTO ledger_tills(id, branch_id, teller_id, status, opening_cash, closing_cash_system, opened_at,
                                          closed_at, raw, srv_raw, srv_seq, origin, local_updated_at, acked)
                 VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14)
                 ON CONFLICT(id) DO UPDATE SET branch_id=excluded.branch_id, teller_id=excluded.teller_id,
                   status=excluded.status, opening_cash=excluded.opening_cash,
                   closing_cash_system=excluded.closing_cash_system, opened_at=excluded.opened_at,
                   closed_at=excluded.closed_at, raw=excluded.raw, srv_raw=excluded.srv_raw,
                   srv_seq=excluded.srv_seq, origin=excluded.origin, local_updated_at=excluded.local_updated_at,
                   acked=excluded.acked",
                params![
                    key,
                    s(v, "branch_id").unwrap_or(""),
                    s(v, "teller_id").unwrap_or(""),
                    s(v, "status").unwrap_or("open"),
                    i(v, "opening_cash"),
                    v.get("closing_cash_system").and_then(Value::as_i64),
                    s(v, "opened_at").unwrap_or(""),
                    s(v, "closed_at"),
                    raw,
                    srv,
                    srv_seq,
                    origin_word,
                    now,
                    acked as i64
                ],
            )?;
            // Who viewed the till's spot report rides its projection.
            if origin != Origin::Local {
                spot::from_till_row(conn, v)?;
            }
        }
        T_ORDER => {
            exec(conn, 
                "INSERT INTO ledger_orders(okey, server_id, order_ref, branch_id, till_id, status, payment_method,
                                           total_amount, tip_amount, tip_is_cash, tip_payment_method, created_at,
                                           raw, srv_raw, srv_seq, origin, acked, local_updated_at, order_number, device_code)
                 VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20)
                 ON CONFLICT(okey) DO UPDATE SET server_id=COALESCE(excluded.server_id, ledger_orders.server_id),
                   order_ref=excluded.order_ref, branch_id=excluded.branch_id, till_id=excluded.till_id,
                   status=excluded.status, payment_method=excluded.payment_method,
                   total_amount=excluded.total_amount, tip_amount=excluded.tip_amount,
                   tip_is_cash=excluded.tip_is_cash, tip_payment_method=excluded.tip_payment_method,
                   created_at=excluded.created_at, raw=excluded.raw, srv_raw=excluded.srv_raw,
                   srv_seq=excluded.srv_seq, origin=excluded.origin, acked=excluded.acked,
                   local_updated_at=excluded.local_updated_at, order_number=excluded.order_number,
                   device_code=excluded.device_code",
                params![
                    key,
                    server_id_of(ty, key, v, origin),
                    s(v, "order_ref"),
                    s(v, "branch_id").unwrap_or(""),
                    s(v, "till_id").unwrap_or(""),
                    s(v, "status").unwrap_or("completed"),
                    s(v, "payment_method").unwrap_or(""),
                    i(v, "total_amount"),
                    i(v, "tip_amount"),
                    b(v, "tip_is_cash"),
                    s(v, "tip_payment_method"),
                    s(v, "created_at").unwrap_or(""),
                    raw,
                    srv,
                    srv_seq,
                    origin_word,
                    acked as i64,
                    now,
                    // Numbers only / text only, like the server's MIN/MAX over typed columns.
                    v.get("order_number").filter(|n| n.is_i64() || n.is_u64()).and_then(Value::as_i64),
                    s(v, "device_code")
                ],
            )?;
            exec(conn, "DELETE FROM ledger_payments WHERE okey=?1", [key])?;
            if let Some(legs) = v.get("payment_legs").and_then(Value::as_array) {
                for (n, leg) in legs.iter().enumerate() {
                    exec(conn, 
                        "INSERT INTO ledger_payments(okey, idx, method, amount, is_cash) VALUES(?1,?2,?3,?4,?5)",
                        params![key, n as i64, s(leg, "method").unwrap_or(""), i(leg, "amount"), b(leg, "is_cash")],
                    )?;
                }
            }
        }
        T_CASH => {
            exec(conn, 
                "INSERT INTO ledger_cash(ckey, server_id, till_id, amount, kind, corrects_id, created_at, raw, srv_raw,
                                         srv_seq, origin, acked, local_updated_at)
                 VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13)
                 ON CONFLICT(ckey) DO UPDATE SET server_id=COALESCE(excluded.server_id, ledger_cash.server_id),
                   till_id=excluded.till_id, amount=excluded.amount, kind=excluded.kind,
                   corrects_id=excluded.corrects_id, created_at=excluded.created_at, raw=excluded.raw,
                   srv_raw=excluded.srv_raw, srv_seq=excluded.srv_seq, origin=excluded.origin,
                   acked=excluded.acked, local_updated_at=excluded.local_updated_at",
                params![
                    key,
                    server_id_of(ty, key, v, origin),
                    s(v, "till_id").unwrap_or(""),
                    i(v, "amount"),
                    s(v, "kind").unwrap_or(""),
                    s(v, "corrects_id"),
                    s(v, "created_at").unwrap_or(""),
                    raw,
                    srv,
                    srv_seq,
                    origin_word,
                    acked as i64,
                    now
                ],
            )?;
        }
        T_REFUND => {
            exec(conn, 
                "INSERT INTO ledger_refunds(rkey, server_id, order_id, till_id, amount, method, is_cash, issued_at, raw,
                                            srv_raw, srv_seq, origin, acked, local_updated_at)
                 VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14)
                 ON CONFLICT(rkey) DO UPDATE SET server_id=COALESCE(excluded.server_id, ledger_refunds.server_id),
                   order_id=excluded.order_id, till_id=excluded.till_id, amount=excluded.amount,
                   method=excluded.method, is_cash=excluded.is_cash, issued_at=excluded.issued_at,
                   raw=excluded.raw, srv_raw=excluded.srv_raw, srv_seq=excluded.srv_seq,
                   origin=excluded.origin, acked=excluded.acked, local_updated_at=excluded.local_updated_at",
                params![
                    key,
                    server_id_of(ty, key, v, origin),
                    s(v, "order_id").unwrap_or(""),
                    s(v, "till_id").unwrap_or(""),
                    i(v, "amount"),
                    s(v, "method").unwrap_or(""),
                    b(v, "is_cash").unwrap_or(false) as i64,
                    s(v, "issued_at").unwrap_or(""),
                    raw,
                    srv,
                    srv_seq,
                    origin_word,
                    acked as i64,
                    now
                ],
            )?;
        }
        _ => {}
    }
    match origin {
        Origin::Feed(_) => {
            let (table, kcol) = table_of(ty).expect("ledger type");
            exec(
                conn,
                &format!("UPDATE {table} SET ack_seq=NULL, peer_seq=NULL WHERE {kcol}=?1 AND (ack_seq IS NOT NULL OR peer_seq IS NOT NULL)"),
                [key],
            )?;
        }
        Origin::Peer(seq) => {
            let (table, kcol) = table_of(ty).expect("ledger type");
            exec(conn, &format!("UPDATE {table} SET peer_seq=?1 WHERE {kcol}=?2"), params![seq, key])?;
        }
        _ => {}
    }
    Ok(key_owned)
}

/// The server id a written row carries: a server-origin row's own `id` (a local
/// row's `id` is its client key, which is not a server id).
fn server_id_of(_ty: &str, key: &str, v: &Value, origin: Origin) -> Option<String> {
    if origin == Origin::Local {
        return None;
    }
    let id = s(v, "id")?;
    // A server row keyed by its own id, or a client-keyed row whose server id
    // differs from its key: both are real server ids.
    let _ = key;
    Some(id.to_string())
}

/// Record the feed horizon a replay answer named for the row an op acked. A
/// feed row arriving later clears the ack (and this with it) the usual way.
pub(crate) fn set_ack_seq(conn: &Connection, ty: &str, key: &str, seq: i64) -> CoreResult<()> {
    let Some((table, kcol)) = table_of(ty) else { return Ok(()) };
    conn.execute(
        &format!("UPDATE {table} SET ack_seq=MAX(COALESCE(ack_seq, 0), ?1) WHERE {kcol}=?2 AND acked=1 AND srv_seq=0"),
        params![seq, key],
    )?;
    Ok(())
}

/// The branch cursor (`sync:next:<branch>`), 0 when never pulled.
pub(crate) fn cursor_of(conn: &Connection, branch: &str) -> CoreResult<i64> {
    Ok(conn
        .query_row("SELECT v FROM kv WHERE k=?1", [format!("{}{branch}", crate::sync_pull::K_NEXT)], |r| r.get::<_, String>(0))
        .optional()?
        .and_then(|v| v.parse().ok())
        .unwrap_or(0))
}

/// Remember `data` as the server's version of a PROTECTED row, advancing its seq.
pub(crate) fn shadow(conn: &Connection, ty: &str, key: &str, data: &Value, seq: i64) -> CoreResult<()> {
    let (table, kcol) = table_of(ty).expect("ledger type");
    conn.execute(
        &format!("UPDATE {table} SET srv_raw=?1, srv_seq=MAX(srv_seq, ?2) WHERE {kcol}=?3"),
        params![data.to_string(), seq, key],
    )?;
    Ok(())
}

/// Delete one ledger row (its payment legs cascade).
pub(crate) fn delete_row(conn: &Connection, ty: &str, key: &str) -> CoreResult<u32> {
    let (table, kcol) = table_of(ty).expect("ledger type");
    Ok(conn.execute(&format!("DELETE FROM {table} WHERE {kcol}=?1"), [key])? as u32)
}

#[cfg(test)]
mod tests;
#[cfg(test)]
mod prop_tests;
