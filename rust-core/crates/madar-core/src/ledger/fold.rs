//! Ack folding (OFFLINE_B_DESIGN §5): the server's answer to a sent op becomes
//! the row, in the same transaction that marks the op acked.
//!
//! `/sync/replay` answers with the live route's body — the created or changed
//! entity — so the device knows the server's version the moment the op lands,
//! without waiting for the next pull. The row is flagged `acked` until the feed
//! shows it (a snapshot that started before the ack cannot delete it).
//!
//! When there is no body (an idempotent 409/404 ack, an old server, a body this
//! build cannot read), the row simply stays as the device wrote it, flagged
//! `acked`, and the scheduler's post-ack pull brings the server version. The row
//! never disappears.

use rusqlite::{params, Connection};
use serde_json::{json, Value};

use super::report::Method;
use super::{s, stored, write_row, Origin, T_CASH, T_ORDER, T_REFUND, T_TILL};
use crate::error::CoreResult;
use crate::store::OutboxItem;

/// Flag a row acknowledged without changing its data.
fn mark_acked(conn: &Connection, ty: &str, key: &str) -> CoreResult<()> {
    if ty == T_TILL {
        return Ok(());
    }
    let (table, kcol) = super::table_of(ty).unwrap();
    conn.execute(
        &format!("UPDATE {table} SET acked=1, local_updated_at=?1 WHERE {kcol}=?2 AND srv_seq=0"),
        params![super::now_ms(), key],
    )?;
    Ok(())
}

fn is_cash_named(methods: &[Method], name: &str) -> bool {
    methods.iter().find(|m| m.name == name).map(|m| m.is_cash).unwrap_or(name == "cash")
}

/// The legs of `body` with `is_cash`: the server snapshots it but the order
/// response does not carry it, so take it from the device's own leg at the same
/// position (same method) — resolved from the catalogue at the sale — else from
/// the catalogue now.
fn legs_with_cash(body: &Value, local: Option<&Value>, methods: &[Method]) -> Value {
    let local_legs = local.and_then(|l| l.get("payment_legs")).and_then(Value::as_array).cloned().unwrap_or_default();
    let legs: Vec<Value> = body
        .get("payment_legs")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .enumerate()
        .map(|(n, mut leg)| {
            if leg.get("is_cash").map(Value::is_null).unwrap_or(true) {
                let method = s(&leg, "method").unwrap_or("").to_string();
                let cash = local_legs
                    .get(n)
                    .filter(|l| s(l, "method") == Some(method.as_str()))
                    .and_then(|l| l.get("is_cash").and_then(Value::as_bool))
                    .unwrap_or_else(|| is_cash_named(methods, &method));
                leg["is_cash"] = json!(cash);
            }
            leg
        })
        .collect();
    Value::Array(legs)
}

fn merged(base: Option<&Value>, body: &Value) -> Value {
    let mut out = base.cloned().unwrap_or_else(|| json!({}));
    if let (Value::Object(o), Value::Object(b)) = (&mut out, body) {
        for (k, v) in b {
            o.insert(k.clone(), v.clone());
        }
    }
    out
}

/// A sale's full record, kept for detail and reprint.
pub(crate) fn put_order_detail(conn: &Connection, order_id: &str, full: &Value) -> CoreResult<()> {
    conn.execute(
        "INSERT INTO order_details(order_id, raw, fetched_at) VALUES(?1, ?2, ?3)
         ON CONFLICT(order_id) DO UPDATE SET raw=excluded.raw, fetched_at=excluded.fetched_at",
        params![order_id, full.to_string(), super::now_ms()],
    )?;
    Ok(())
}

fn fold_order_body(conn: &Connection, key: &str, body: &Value, methods: &[Method]) -> CoreResult<()> {
    let prev = stored(conn, T_ORDER, key)?;
    let mut row = merged(prev.as_ref().map(|p| &p.raw), body);
    row["idempotency_key"] = json!(key);
    row["payment_legs"] = legs_with_cash(body, prev.as_ref().map(|p| &p.raw), methods);
    if row.get("tip_is_cash").map(Value::is_null).unwrap_or(true) && super::i(&row, "tip_amount") > 0 {
        let local_tip = prev.as_ref().and_then(|p| p.raw.get("tip_is_cash")).and_then(Value::as_bool);
        let method = s(&row, "tip_payment_method").or(s(&row, "payment_method")).unwrap_or("").to_string();
        row["tip_is_cash"] = json!(local_tip.unwrap_or_else(|| is_cash_named(methods, &method)));
    }
    // The create response's legs are written just after its row: an empty list
    // in the body is not "no tender" — keep the device's legs.
    if row["payment_legs"].as_array().map(Vec::is_empty).unwrap_or(true) {
        if let Some(l) = prev.as_ref().and_then(|p| p.raw.get("payment_legs")) {
            row["payment_legs"] = l.clone();
        }
    }
    if let Some(id) = s(body, "id") {
        if body.get("items").map(Value::is_array).unwrap_or(false) {
            put_order_detail(conn, id, body)?;
        }
    }
    write_row(conn, T_ORDER, key, &row, Origin::Ack, None)?;
    // Another op still holding the sale (a void queued behind its create) keeps
    // its effect on top of the server's answer.
    super::local::reapply_pending(conn, T_ORDER, key)?;
    Ok(())
}

/// Fold one acknowledged op. `body` is the replay response when there was one.
pub(crate) fn fold(conn: &Connection, item: &OutboxItem, body: Option<&Value>, methods: &[Method]) -> CoreResult<Vec<&'static str>> {
    use crate::changes as c;
    let ty = item.entity_type.as_deref().unwrap_or("");
    let key = item.entity_id.clone();
    let mut touched = vec![c::OUTBOX];
    match (item.op_type.as_str(), body) {
        ("create_order", Some(b)) if s(b, "id").is_some() => {
            let key = key.unwrap_or_else(|| item.id.clone());
            fold_order_body(conn, &key, b, methods)?;
            touched.extend([c::ORDERS, c::TILLS]);
        }
        ("settle_open_ticket", Some(b)) if s(b, "id").is_some() => {
            // The paid order the settle produced, keyed by its ticket (the
            // server's idempotency key for it), on the till at once.
            let key = key
                .or_else(|| s(b, "open_ticket_id").map(str::to_string))
                .unwrap_or_else(|| s(b, "id").unwrap().to_string());
            fold_order_body(conn, &key, b, methods)?;
            touched.extend([c::ORDERS, c::TILLS, c::OPEN_TICKETS]);
        }
        ("void_order", Some(b)) if s(b, "id").is_some() => {
            if let Some(key) = key.or_else(|| super::order_key_for(conn, s(b, "id").unwrap()).ok().flatten()) {
                fold_order_body(conn, &key, b, methods)?;
            }
            touched.extend([c::ORDERS, c::TILLS]);
        }
        ("refund_order", Some(b)) if s(b, "id").is_some() => {
            let key = key.or_else(|| super::key_of(T_REFUND, b)).unwrap_or_default();
            let prev = stored(conn, T_REFUND, &key)?;
            let row = merged(prev.as_ref().map(|p| &p.raw), b);
            write_row(conn, T_REFUND, &key, &row, Origin::Ack, None)?;
            // Where the sale now stands (`refunded` once fully returned).
            if let (Some(status), Some(order_id)) = (s(b, "order_status"), s(b, "order_id")) {
                if let Some(okey) = super::order_key_for(conn, order_id)? {
                    if !super::is_protected(conn, T_ORDER, &okey)? {
                        if let Some(p) = stored(conn, T_ORDER, &okey)? {
                            let mut raw = p.raw.clone();
                            raw["status"] = json!(status);
                            write_row(conn, T_ORDER, &okey, &raw, Origin::Ack, None)?;
                        }
                    }
                }
            }
            touched.extend([c::REFUNDS, c::ORDERS, c::TILLS]);
        }
        ("cash_movement", Some(b)) if s(b, "id").is_some() => {
            let key = key.or_else(|| super::key_of(T_CASH, b)).unwrap_or_default();
            let prev = stored(conn, T_CASH, &key)?;
            let row = merged(prev.as_ref().map(|p| &p.raw), b);
            write_row(conn, T_CASH, &key, &row, Origin::Ack, None)?;
            touched.extend([c::CASH_MOVEMENTS, c::TILLS]);
        }
        ("open_till" | "open_shift", Some(b)) if s(b, "id").is_some() => {
            let id = s(b, "id").unwrap().to_string();
            let prev = stored(conn, T_TILL, &id)?;
            let mut row = merged(prev.as_ref().map(|p| &p.raw), b);
            // An old server answers `open_shift` with the legacy shape.
            if row.get("verification").map(Value::is_null).unwrap_or(true) {
                if let Some(v) = prev.as_ref().and_then(|p| p.raw.get("verification")).cloned() {
                    row["verification"] = v;
                }
            }
            write_row(conn, T_TILL, &id, &row, Origin::Ack, None)?;
            // A close queued behind this open keeps the till closed here.
            super::local::reapply_pending(conn, T_TILL, &id)?;
            touched.push(c::TILLS);
        }
        ("close_till" | "close_shift", Some(b)) => {
            let till = b.get("till").or_else(|| b.get("shift")).cloned();
            if let Some(t) = till.filter(|t| s(t, "id").is_some()) {
                let id = s(&t, "id").unwrap().to_string();
                let prev = stored(conn, T_TILL, &id)?;
                let row = merged(prev.as_ref().map(|p| &p.raw), &t);
                write_row(conn, T_TILL, &id, &row, Origin::Ack, None)?;
            }
            touched.push(c::TILLS);
        }
        (_, _) => {
            if let Some(key) = key.as_deref() {
                if !ty.is_empty() && super::is_ledger_type(ty) {
                    mark_acked(conn, ty, key)?;
                    touched.extend(crate::changes::tables_for_op(&item.op_type));
                }
            }
        }
    }
    Ok(touched)
}
