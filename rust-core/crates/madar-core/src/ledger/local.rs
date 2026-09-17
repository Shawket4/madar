//! The write path's ledger half (OFFLINE_B_DESIGN §5): the local row a
//! mutation writes, in the SAME transaction as its outbox op. A crash between
//! "the sale is in the queue" and "the sale is on the screen" is therefore
//! impossible — both commit or neither does.
//!
//! Local rows are written in the changefeed's projection shape, so every read
//! (history, drawer, Z report) handles a queued sale and a synced one with the
//! same code.

use rusqlite::{params, Connection};
use serde_json::{json, Value};

use super::{s, stored, write_row, Origin, T_CASH, T_ORDER, T_REFUND, T_TILL};
use crate::checkout::CheckoutCommand;
use crate::error::CoreResult;
use super::report::Method;
use crate::store::{enqueue_on, NewOutboxOp};

/// The server's `is_cash_of`: the org method of that NAME decides; a name the
/// catalogue does not know is cash only when it is literally `cash`.
pub(crate) fn is_cash_of(methods: &[Method], name: &str) -> bool {
    methods
        .iter()
        .find(|m| m.name == name)
        .map(|m| m.is_cash)
        .unwrap_or(name == "cash")
}

fn flat<T: Clone>(o: &Option<Option<T>>) -> Option<T> {
    o.clone().flatten()
}

/// Who rang a sale, for its local row.
pub(crate) struct Ringer<'a> {
    pub teller_id: &'a str,
    pub teller_name: &'a str,
}

/// A queued sale as the changefeed will later project it. `is_cash` is resolved
/// NOW, from the catalogue at the moment of the sale, exactly as the server
/// snapshots it on insert — so the drawer never depends on a later catalogue.
pub(crate) fn order_json(cmd: &CheckoutCommand, okey: &str, who: &Ringer<'_>, methods: &[Method]) -> Value {
    let r = &cmd.request;
    let total = flat(&r.total_amount).unwrap_or(0) as i64;
    let legs: Vec<Value> = match flat(&r.payment_splits) {
        Some(splits) => splits
            .iter()
            .map(|l| json!({ "method": l.method, "amount": l.amount, "is_cash": is_cash_of(methods, &l.method) }))
            .collect(),
        None => vec![json!({ "method": r.payment_method, "amount": total, "is_cash": is_cash_of(methods, &r.payment_method) })],
    };
    let tip = flat(&r.tip_amount).unwrap_or(0) as i64;
    let tip_method = flat(&r.tip_payment_method);
    let tip_is_cash = (tip > 0).then(|| is_cash_of(methods, tip_method.as_deref().unwrap_or(&r.payment_method)));
    let (order_number, device_code, display) = match &cmd.device {
        Some(d) => (
            Some(d.order_number),
            Some(d.device_code.clone()),
            crate::checkout::display_number(&d.device_code, d.order_number),
        ),
        None => (flat(&r.order_number).map(i64::from), None, String::new()),
    };
    json!({
        "id": okey,
        "idempotency_key": okey,
        "branch_id": r.branch_id,
        "till_id": r.till_id,
        "shift_id": r.till_id,
        "teller_id": who.teller_id,
        "teller_name": who.teller_name,
        "order_number": order_number,
        "device_code": device_code,
        "display_number": display,
        "verification": cmd.device.as_ref().map(|d| d.verification.clone()),
        "order_ref": flat(&r.order_ref),
        // A counter sale (a dine-in bill settles through a ticket, a different op).
        "status": "completed",
        "order_type": "takeaway",
        "subtotal": flat(&r.subtotal).unwrap_or(0),
        "discount_type": flat(&r.discount_type),
        "discount_amount": flat(&r.discount_amount).unwrap_or(0),
        "discount_id": flat(&r.discount_id),
        "discount_kind": flat(&r.discount_kind),
        "discount_percent_bps": flat(&r.discount_percent_bps),
        "discount_applied_by": flat(&r.discount_applied_by),
        "discount_approval_id": flat(&r.discount_approval_id),
        "tax_amount": flat(&r.tax_amount).unwrap_or(0),
        "service_charge_amount": 0,
        "delivery_fee": 0,
        "total_amount": total,
        "amount_tendered": flat(&r.amount_tendered),
        "change_given": flat(&r.change_given),
        "tip_amount": tip,
        "tip_payment_method": tip_method,
        "tip_is_cash": tip_is_cash,
        "payment_method": r.payment_method,
        "payment_legs": legs,
        "customer_name": flat(&r.customer_name),
        "notes": flat(&r.notes),
        "price_flagged": false,
        "created_at": flat(&r.created_at).map(|d| d.to_rfc3339()),
        "items": [],
    })
}

/// Queue a sale: the outbox op and its local row, one transaction.
pub(crate) fn commit_order(tx: &Connection, op: &NewOutboxOp, row: &Value) -> CoreResult<i64> {
    let seq = enqueue_on(tx, op)?;
    let key = op.entity_id.as_deref().expect("create_order names its row");
    if stored(tx, T_ORDER, key)?.is_none() {
        write_row(tx, T_ORDER, key, row, Origin::Local, None)?;
    }
    Ok(seq)
}

/// Change a row in place for a local op, keeping its origin, seq and ack, and
/// remembering the server version it had (the first local change of a server
/// row copies it to `srv_raw`, so a discarded op can put it back).
pub(crate) fn modify(conn: &Connection, ty: &str, key: &str, f: impl FnOnce(&mut Value)) -> CoreResult<bool> {
    let Some(prev) = stored(conn, ty, key)? else { return Ok(false) };
    let mut raw = prev.raw.clone();
    f(&mut raw);
    let srv = match (&prev.srv_raw, prev.origin.as_str()) {
        (Some(s), _) => Some(s.clone()),
        (None, "server") => Some(prev.raw.clone()),
        (None, _) => None,
    };
    let origin = match prev.origin.as_str() {
        "local" => Origin::Local,
        "peer" => Origin::Peer(super::stored_meta(conn, ty, key)?.and_then(|m| m.peer_seq).unwrap_or(0)),
        _ => Origin::Fetch,
    };
    let key = write_row(conn, ty, key, &raw, origin, srv.as_ref())?;
    // write_row(Fetch) would not touch acked/seq; restore the exact ack flag.
    let (table, kcol) = super::table_of(ty).unwrap();
    conn.execute(
        &format!("UPDATE {table} SET acked=?1 WHERE {kcol}=?2"),
        params![prev.acked as i64, key],
    )?;
    Ok(true)
}

fn void_fields(v: &mut Value, voided_at: &str, reason: &str, note: Option<&str>) {
    if let Value::Object(m) = v {
        m.insert("status".into(), json!("voided"));
        m.insert("voided_at".into(), json!(voided_at));
        m.insert("void_reason".into(), json!(reason));
        m.insert("void_note".into(), json!(note));
    }
}

/// A settled bill as its paid order, before the server has priced it: the bill
/// the cashier saw (`total`), the tender, keyed by the TICKET id — the server
/// uses the ticket id as the order's idempotency key, so the feed's row lands on
/// this one.
#[allow(clippy::too_many_arguments)]
/// A settle row's bill from a cached ticket's server `bill` JSON (or nothing),
/// with `total` as the drawer collected it. For paths that only hold the raw
/// ticket — a migrated or mirrored queued settle; a live settle prices the bill
/// through `bill_with_rewards` instead.
pub(crate) fn bill_from_json(bill: Option<&Value>, total: i64) -> crate::tickets::TicketBillView {
    let n = |k: &str| bill.and_then(|b| b.get(k)).and_then(Value::as_i64).unwrap_or(0);
    let f = |k: &str| bill.and_then(|b| b.get(k)).and_then(Value::as_f64).unwrap_or(0.0);
    let same = bill.and_then(|b| b.get("total")).and_then(Value::as_i64) == Some(total);
    crate::tickets::TicketBillView {
        subtotal_minor: if bill.is_some() { n("subtotal") } else { total },
        // A different total (split legs that disagree, a discount picked at
        // settle) cannot be broken down honestly; its parts stay at zero.
        discount_minor: if same { n("discount_amount") } else { 0 },
        service_charge_minor: if same { n("service_charge_amount") } else { 0 },
        tax_minor: if same { n("tax_amount") } else { 0 },
        total_minor: total,
        tax_rate: f("tax_rate"),
        service_charge_rate: f("service_charge_rate"),
        tax_inclusive: bill.and_then(|b| b.get("tax_inclusive")).and_then(Value::as_bool).unwrap_or(false),
        service_charge_taxable: bill
            .and_then(|b| b.get("service_charge_taxable"))
            .and_then(Value::as_bool)
            .unwrap_or(true),
        service_charge_waived_minor: 0,
    }
}

pub(crate) fn settle_json(
    ticket_id: &str,
    branch_id: &str,
    till_id: &str,
    who: &Ringer<'_>,
    payment_method: &str,
    splits: &[(String, i64)],
    bill: &crate::tickets::TicketBillView,
    waived_by: Option<&str>,
    tip: i64,
    tip_method: Option<&str>,
    at: &str,
    methods: &[Method],
) -> Value {
    let total = bill.total_minor;
    let legs: Vec<Value> = if splits.is_empty() {
        vec![json!({ "method": payment_method, "amount": total, "is_cash": is_cash_of(methods, payment_method) })]
    } else {
        splits.iter().map(|(m, a)| json!({ "method": m, "amount": a, "is_cash": is_cash_of(methods, m) })).collect()
    };
    json!({
        "id": ticket_id,
        "idempotency_key": ticket_id,
        "open_ticket_id": ticket_id,
        "branch_id": branch_id,
        "till_id": till_id,
        "shift_id": till_id,
        "teller_id": who.teller_id,
        "teller_name": who.teller_name,
        "status": "completed",
        "order_type": "dine_in",
        // The bill as the drawer collected it — tax and service charge
        // included — so the local Z has the same figures the server will book.
        "subtotal": bill.subtotal_minor,
        "discount_amount": bill.discount_minor,
        "service_charge_amount": bill.service_charge_minor,
        "tax_amount": bill.tax_minor,
        "tax_inclusive": bill.tax_inclusive,
        "tax_rate_applied": bill.tax_rate,
        "service_charge_rate_applied": if waived_by.is_some() { 0.0 } else { bill.service_charge_rate },
        "service_charge_taxable_applied": bill.service_charge_taxable,
        "service_charge_waived_by": waived_by,
        "service_charge_waived_at": waived_by.map(|_| at),
        "service_charge_waived_amount": bill.service_charge_waived_minor,
        "total_amount": total,
        "tip_amount": tip,
        "tip_payment_method": tip_method,
        "tip_is_cash": (tip > 0).then(|| is_cash_of(methods, tip_method.unwrap_or(payment_method))),
        "payment_method": payment_method,
        "payment_legs": legs,
        "price_flagged": false,
        "created_at": at,
        "items": [],
    })
}

/// Queue a void: the op, and the order row reading `voided` (when this device
/// holds the order).
pub(crate) fn commit_void(
    tx: &Connection,
    op: &NewOutboxOp,
    voided_at: &str,
    reason: &str,
    note: Option<&str>,
) -> CoreResult<i64> {
    let seq = enqueue_on(tx, op)?;
    if let Some(key) = op.entity_id.as_deref() {
        modify(tx, T_ORDER, key, |v| void_fields(v, voided_at, reason, note))?;
    }
    Ok(seq)
}

/// Queue a cash movement and its row.
pub(crate) fn commit_cash(tx: &Connection, op: &NewOutboxOp, row: &Value) -> CoreResult<i64> {
    let seq = enqueue_on(tx, op)?;
    let key = op.entity_id.as_deref().expect("cash_movement names its row");
    if stored(tx, T_CASH, key)?.is_none() {
        write_row(tx, T_CASH, key, row, Origin::Local, None)?;
    }
    Ok(seq)
}

/// Queue a refund and its row.
pub(crate) fn commit_refund(tx: &Connection, op: &NewOutboxOp, row: &Value) -> CoreResult<i64> {
    let seq = enqueue_on(tx, op)?;
    let key = op.entity_id.as_deref().expect("refund_order names its row");
    if stored(tx, T_REFUND, key)?.is_none() {
        write_row(tx, T_REFUND, key, row, Origin::Local, None)?;
    }
    Ok(seq)
}

/// Queue a till open and the till's row.
pub(crate) fn commit_open_till(tx: &Connection, op: &NewOutboxOp, record: &Value) -> CoreResult<i64> {
    let seq = enqueue_on(tx, op)?;
    let key = op.entity_id.as_deref().expect("open_till names its till");
    write_row(tx, T_TILL, key, record, Origin::Local, None)?;
    // A till opened on this device is complete by construction: every row of
    // it is written here or reaches here through the feed.
    tx.execute("UPDATE ledger_tills SET complete=1 WHERE id=?1", [key])?;
    Ok(seq)
}

/// Queue a till close and mark the row closed.
pub(crate) fn commit_close_till(tx: &Connection, op: &NewOutboxOp, closed_at: &str, declared: i64) -> CoreResult<i64> {
    let seq = enqueue_on(tx, op)?;
    if let Some(key) = op.entity_id.as_deref() {
        modify(tx, T_TILL, key, |v| close_fields(v, closed_at, declared))?;
    }
    Ok(seq)
}

fn close_fields(v: &mut Value, closed_at: &str, declared: i64) {
    if let Value::Object(m) = v {
        m.insert("status".into(), json!("closed"));
        if m.get("closed_at").map(Value::is_null).unwrap_or(true) {
            m.insert("closed_at".into(), json!(closed_at));
        }
        m.insert("closing_cash_declared".into(), json!(declared));
    }
}

/// A server row was written over a row a live op still holds and that this
/// device did not have: put the op's effect back on it.
pub(crate) fn reapply_pending(conn: &Connection, ty: &str, key: &str) -> CoreResult<()> {
    let ops: Vec<(String, String, String)> = {
        let mut st = conn.prepare(
            "SELECT op_type, payload, event_at FROM outbox
              WHERE entity_type=?1 AND entity_id=?2 AND status IN ('pending','inflight','dead') ORDER BY seq",
        )?;
        let v = st
            .query_map(params![ty, key], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
            .collect::<Result<Vec<_>, _>>()?;
        v
    };
    for (op_type, payload, event_at) in ops {
        match (ty, op_type.as_str()) {
            (T_ORDER, "void_order") => {
                let p: Value = serde_json::from_str(&payload).unwrap_or(Value::Null);
                let req = &p["request"];
                let at = s(req, "voided_at").unwrap_or(&event_at).to_string();
                let reason = s(req, "reason").unwrap_or("other").to_string();
                let note = s(req, "note").map(str::to_string);
                modify(conn, ty, key, |v| void_fields(v, &at, &reason, note.as_deref()))?;
            }
            (T_TILL, "close_till" | "close_shift") => {
                let p: Value = serde_json::from_str(&payload).unwrap_or(Value::Null);
                let req = &p["request"];
                let at = s(req, "closed_at").unwrap_or(&event_at).to_string();
                let declared = req.get("closing_cash_declared").and_then(Value::as_i64).unwrap_or(0);
                modify(conn, ty, key, |v| close_fields(v, &at, declared))?;
            }
            _ => {}
        }
    }
    Ok(())
}

/// The teller gave up on a dead op: drop the local row it created (nothing of
/// it is on the server), or put the server's version back on a row it changed.
/// Runs in the same transaction as the outbox delete.
pub(crate) fn discard(conn: &Connection, ty: &str, key: &str) -> CoreResult<()> {
    if super::is_protected(conn, ty, key)? {
        return Ok(()); // another live op still holds the row
    }
    let Some(p) = stored(conn, ty, key)? else { return Ok(()) };
    match (&p.srv_raw, p.origin.as_str()) {
        (Some(server), _) => {
            write_row(conn, ty, key, server, Origin::Feed(p.srv_seq), None)?;
        }
        (None, "local") if !p.acked && p.srv_seq == 0 => {
            super::delete_row(conn, ty, key)?;
        }
        _ => {}
    }
    Ok(())
}
