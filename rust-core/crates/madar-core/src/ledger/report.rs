//! A till's drawer and Z report computed on the device (OFFLINE_B_DESIGN §7).
//!
//! The fold is madar-shared's (`madar_till::report`), the one the backend's
//! SQL (`compute_system_cash`, `report_figures`, `system_totals_by_method`) is
//! pinned to by `madar_till::vectors::TILL_REPORT` — the backend's own
//! scenarios, asserted here field by field through this module's SQLite
//! loads. This module only reads the ledger rows into the fold's inputs.
//!
//! Every sale is ONE row whatever its sync state, so there is nothing to add
//! together and nothing to subtract: a queued sale, a sale whose response was
//! lost, a dead-lettered sale the teller has not given up on and a synced sale
//! each count exactly once, as the drawer holds them.

use std::collections::HashMap;

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::Value;

use super::{i, s};
use crate::error::CoreResult;

/// One org payment method as the close preview needs it.
#[derive(Debug, Clone, Default)]
pub(crate) struct Method {
    pub id: String,
    pub name: String,
    pub is_cash: bool,
    pub is_active: bool,
    pub created_at: Option<String>,
}

impl Method {
    /// From a `payment_method` wire row or a cached catalogue entry (lenient).
    pub(crate) fn from_json(v: &Value) -> Option<Self> {
        Some(Method {
            id: s(v, "id")?.to_string(),
            name: s(v, "name")?.to_string(),
            is_cash: v.get("is_cash").and_then(Value::as_bool).unwrap_or(false),
            is_active: v.get("is_active").and_then(Value::as_bool).unwrap_or(true),
            created_at: s(v, "created_at").map(str::to_string),
        })
    }
}

// The report's row types are the fold's own.
pub(crate) use madar_till::report::{MethodTotal, Movement, PaymentLine};

impl From<&Method> for madar_till::report::Method {
    fn from(m: &Method) -> Self {
        madar_till::report::Method {
            id: m.id.clone(),
            name: m.name.clone(),
            is_cash: m.is_cash,
            is_active: m.is_active,
            created_at: m.created_at.clone(),
        }
    }
}

/// Everything the backend's report says about a till, computed locally.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct TillFigures {
    pub till: Value,
    pub system_cash: i64,
    pub expected_cash: i64,
    pub payment_summary: Vec<PaymentLine>,
    pub total_payments: i64,
    pub voided_amount: i64,
    pub net_payments: i64,
    pub total_tips: i64,
    pub cash_tips: i64,
    pub non_cash_tips: i64,
    pub cash_movements: Vec<Movement>,
    pub cash_movements_in: i64,
    pub cash_movements_out: i64,
    pub safe_drops: i64,
    pub cash_adjustments: i64,
    pub cash_movements_net: i64,
    pub refunds_issued_count: i64,
    pub refunds_issued_amount: i64,
    pub refunds_issued_cash: i64,
    pub cash_in_refunded_sales: i64,
    /// Tax / service charge on this till's sold sales, less what their refunds
    /// took back (`report_figures`' `total_tax` / `total_service_charge`).
    pub total_tax: i64,
    pub total_service_charge: i64,
    /// The tax and service charge inside the refunds issued from this drawer.
    pub refunds_issued_tax: i64,
    pub refunds_issued_service_charge: i64,
    /// Table bills whose service charge was waived, and what it came to.
    pub service_charge_waived_count: i64,
    pub service_charge_waived_amount: i64,
    pub close_methods: Vec<MethodTotal>,
    /// Who viewed / printed the spot report, oldest first (`report_figures`' `spot_views`).
    pub spot_views: Vec<super::spot::SpotRow>,
    /// Rows of this till a live outbox op still holds (queued / sending / failed).
    pub unsynced: u32,
    /// Rows the server acknowledged that the feed has not confirmed yet.
    pub unconfirmed: u32,
    /// Every ledger row of this till is on this device.
    pub complete: bool,
}

use madar_till::report::{Leg, Refund, Sale};

/// A sale and the server's id for it, once it has one (what a refund names).
struct Loaded {
    server_id: Option<String>,
    sale: Sale,
}

/// `okey, status, payment_method, total, tip, tip_method, tip_is_cash, srv_seq, acked, live_create, server_id, raw`.
type SaleRow = (
    String,
    String,
    String,
    i64,
    i64,
    Option<String>,
    Option<i64>,
    i64,
    i64,
    i64,
    Option<String>,
    String,
);
/// `ckey, server_id, amount, kind, corrects_id, created_at, raw`.
type MovementRow = (
    String,
    Option<String>,
    i64,
    String,
    Option<String>,
    String,
    String,
);

fn sales(conn: &Connection, till_id: &str) -> CoreResult<Vec<Loaded>> {
    let rows: Vec<SaleRow> = {
        let mut st = conn.prepare(
            "SELECT o.okey, o.status, o.payment_method, o.total_amount, o.tip_amount, o.tip_payment_method, o.tip_is_cash,
                    o.srv_seq, o.acked,
                    EXISTS(SELECT 1 FROM outbox x WHERE x.entity_type='order' AND x.entity_id=o.okey
                             AND x.op_type='create_order' AND x.status IN ('pending','inflight','dead')),
                    o.server_id, o.raw
               FROM ledger_orders o WHERE o.till_id=?1 ORDER BY o.okey",
        )?;
        let v = st
            .query_map([till_id], |r| {
                Ok((
                    r.get(0)?,
                    r.get(1)?,
                    r.get(2)?,
                    r.get(3)?,
                    r.get(4)?,
                    r.get(5)?,
                    r.get(6)?,
                    r.get(7)?,
                    r.get(8)?,
                    r.get(9)?,
                    r.get(10)?,
                    r.get(11)?,
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        v
    };
    let mut legs: HashMap<String, Vec<Leg>> = HashMap::new();
    {
        let mut st = conn.prepare(
            "SELECT p.okey, p.method, p.amount, p.is_cash FROM ledger_payments p
               JOIN ledger_orders o ON o.okey = p.okey WHERE o.till_id=?1 ORDER BY p.okey, p.idx",
        )?;
        let it = st.query_map([till_id], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, i64>(2)?,
                r.get::<_, Option<i64>>(3)?,
            ))
        })?;
        for row in it {
            let (okey, method, amount, is_cash) = row?;
            let is_cash = is_cash.map(|x| x != 0).unwrap_or(method == "cash");
            legs.entry(okey).or_default().push(Leg {
                method,
                amount,
                is_cash,
            });
        }
    }
    Ok(rows
        .into_iter()
        .map(
            |(
                key,
                status,
                payment_method,
                total,
                tip,
                tip_method,
                tip_is_cash,
                srv_seq,
                acked,
                live_create,
                server_id,
                raw,
            )| {
                let v: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
                Loaded {
                    server_id,
                    sale: Sale {
                        tax: i(&v, "tax_amount"),
                        service_charge: i(&v, "service_charge_amount"),
                        waived: s(&v, "service_charge_waived_by").is_some(),
                        waived_amount: i(&v, "service_charge_waived_amount"),
                        unsent: live_create != 0 && srv_seq == 0 && acked == 0,
                        legs: legs.remove(&key).unwrap_or_default(),
                        key,
                        status,
                        payment_method,
                        total,
                        tip,
                        tip_method,
                        tip_is_cash: tip_is_cash.map(|x| x != 0),
                        // Filled in by `compute`, from the refunds of this sale.
                        refunded_tax: 0,
                        refunded_service_charge: 0,
                    },
                }
            },
        )
        .collect())
}

fn movements(conn: &Connection, till_id: &str) -> CoreResult<Vec<Movement>> {
    let rows: Vec<MovementRow> = {
        let mut st = conn.prepare(
            "SELECT ckey, server_id, amount, kind, corrects_id, created_at, raw FROM ledger_cash WHERE till_id=?1",
        )?;
        let v = st
            .query_map([till_id], |r| {
                Ok((
                    r.get(0)?,
                    r.get(1)?,
                    r.get(2)?,
                    r.get(3)?,
                    r.get(4)?,
                    r.get(5)?,
                    r.get(6)?,
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        v
    };
    // A correction names the movement it reverses by its server id (or, queued
    // before that movement synced, by its client key); the fold resolves it
    // and sorts as the report lists them.
    Ok(madar_till::report::movements(
        rows.into_iter()
            .map(|(ckey, sid, amount, kind, corrects_id, created_at, raw)| {
                let v: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
                madar_till::report::MovementRow {
                    key: ckey,
                    server_id: sid,
                    amount,
                    kind,
                    corrects_id,
                    created_at,
                    note: s(&v, "note").unwrap_or("").to_string(),
                    moved_by_name: s(&v, "moved_by_name").unwrap_or("").to_string(),
                }
            })
            .collect(),
    ))
}

fn refunds(conn: &Connection, till_id: &str) -> CoreResult<Vec<Refund>> {
    let mut st = conn.prepare(
        "SELECT rkey, amount, method, is_cash, order_id FROM ledger_refunds WHERE till_id=?1",
    )?;
    let rows = st
        .query_map([till_id], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, i64>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, i64>(3)? != 0,
                r.get::<_, String>(4)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    let mut out = Vec::with_capacity(rows.len());
    for (rkey, amount, method, is_cash, order_id) in rows {
        let (tax, service_charge) = refund_splits(conn, &order_id)?
            .remove(&rkey)
            .unwrap_or((0, 0));
        out.push(Refund {
            amount,
            method,
            is_cash,
            tax,
            service_charge,
        });
    }
    Ok(out)
}

/// The tax and service charge each refund of `order_id` took back, by refund
/// key. A refund the server has seen carries its split (the database fills
/// it); one still queued on this device is split here with the shared engine's
/// `refund_split`, over the refunds before it in issue order — the same
/// cumulative arithmetic, so the two agree to the piastre.
fn refund_splits(conn: &Connection, order_id: &str) -> CoreResult<HashMap<String, (i64, i64)>> {
    let order: Option<String> = conn
        .query_row(
            "SELECT raw FROM ledger_orders WHERE server_id=?1 OR okey=?1 LIMIT 1",
            [order_id],
            |r| r.get(0),
        )
        .optional()?;
    let order: Value = order
        .and_then(|r| serde_json::from_str(&r).ok())
        .unwrap_or(Value::Null);
    let (total, tax, sc) = (
        i(&order, "total_amount"),
        i(&order, "tax_amount"),
        i(&order, "service_charge_amount"),
    );
    let mut st = conn.prepare(
        "SELECT rkey, amount, raw FROM ledger_refunds WHERE order_id=?1 ORDER BY issued_at, rkey",
    )?;
    let rows = st
        .query_map([order_id], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, i64>(1)?,
                r.get::<_, String>(2)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    let queued: Vec<madar_till::report::OrderRefund> = rows
        .into_iter()
        .map(|(rkey, amount, raw)| {
            let v: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
            madar_till::report::OrderRefund {
                key: rkey,
                amount,
                known: match (
                    v.get("tax_amount").and_then(Value::as_i64),
                    v.get("service_charge_amount").and_then(Value::as_i64),
                ) {
                    (Some(t), Some(c)) => Some((t, c)),
                    _ => None,
                },
            }
        })
        .collect();
    Ok(madar_till::report::refund_splits(total, tax, sc, &queued)
        .into_iter()
        .collect())
}

/// The report for `till_id`, or `None` when the device holds no such till.
pub(crate) fn compute(
    conn: &Connection,
    till_id: &str,
    methods: &[Method],
) -> CoreResult<Option<TillFigures>> {
    let row: Option<(String, i64, i64)> = conn
        .query_row(
            "SELECT raw, complete, srv_seq FROM ledger_tills WHERE id=?1",
            [till_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .optional()?;
    let Some((raw, complete, _till_seq)) = row else {
        return Ok(None);
    };
    let till: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
    let opening = i(&till, "opening_cash");
    let sales = sales(conn, till_id)?;
    let moves = movements(conn, till_id)?;
    let refunds = refunds(conn, till_id)?;

    // Tax and service charge each sold sale's refunds took back (wherever
    // those refunds were issued): by the server's id, else the client key.
    let mut sales = sales;
    for o in sales.iter_mut().filter(|o| o.sale.sold()) {
        let mut taken = (0i64, 0i64);
        for id in o.server_id.iter().chain(std::iter::once(&o.sale.key)) {
            for (t, c) in refund_splits(conn, id)?.into_values() {
                taken.0 += t;
                taken.1 += c;
            }
            if taken != (0, 0) {
                break;
            }
        }
        o.sale.refunded_tax = taken.0;
        o.sale.refunded_service_charge = taken.1;
    }
    let sales: Vec<Sale> = sales.into_iter().map(|o| o.sale).collect();
    let methods: Vec<madar_till::report::Method> = methods.iter().map(Into::into).collect();
    let snapshot = till.get("closing_cash_system").and_then(Value::as_i64);
    let f = madar_till::report::fold(opening, snapshot, &sales, &moves, &refunds, &methods);

    let unsynced: i64 = conn.query_row(
        "SELECT (SELECT COUNT(*) FROM outbox WHERE till_id=?1 AND status IN ('pending','inflight','dead')
                   AND op_type IN ('create_order','void_order','refund_order','cash_movement','spot_report_view','settle_open_ticket','close_till','close_shift'))",
        params![till_id],
        |r| r.get(0),
    )?;
    // Acked rows the feed has not shown — while the cursor is still below the
    // horizon their ack named (or no horizon was named).
    let cursor = super::cursor_of(
        conn,
        till.get("branch_id").and_then(Value::as_str).unwrap_or(""),
    )?;
    let unconfirmed: i64 = conn.query_row(
        "SELECT (SELECT COUNT(*) FROM ledger_orders WHERE till_id=?1 AND acked=1 AND srv_seq=0 AND (ack_seq IS NULL OR ack_seq > ?2))
              + (SELECT COUNT(*) FROM ledger_cash WHERE till_id=?1 AND acked=1 AND srv_seq=0 AND (ack_seq IS NULL OR ack_seq > ?2))
              + (SELECT COUNT(*) FROM ledger_refunds WHERE till_id=?1 AND acked=1 AND srv_seq=0 AND (ack_seq IS NULL OR ack_seq > ?2))",
        params![till_id, cursor],
        |r| r.get(0),
    )?;

    Ok(Some(TillFigures {
        till,
        system_cash: f.system_cash,
        expected_cash: f.expected_cash,
        net_payments: f.net_payments,
        total_payments: f.total_payments,
        voided_amount: f.voided_amount,
        total_tips: f.total_tips,
        cash_tips: f.cash_tips,
        non_cash_tips: f.non_cash_tips,
        cash_movements_in: f.cash_movements_in,
        cash_movements_out: f.cash_movements_out,
        safe_drops: f.safe_drops,
        cash_adjustments: f.cash_adjustments,
        cash_movements_net: f.cash_movements_net,
        cash_movements: moves,
        refunds_issued_count: f.refunds_issued_count,
        refunds_issued_amount: f.refunds_issued_amount,
        refunds_issued_cash: f.refunds_issued_cash,
        cash_in_refunded_sales: f.cash_in_refunded_sales,
        total_tax: f.total_tax,
        total_service_charge: f.total_service_charge,
        refunds_issued_tax: f.refunds_issued_tax,
        refunds_issued_service_charge: f.refunds_issued_service_charge,
        service_charge_waived_count: f.service_charge_waived_count,
        service_charge_waived_amount: f.service_charge_waived_amount,
        payment_summary: f.payment_summary,
        close_methods: f.close_methods,
        spot_views: super::spot::for_till(conn, till_id)?,
        unsynced: unsynced as u32,
        unconfirmed: unconfirmed as u32,
        complete: complete != 0,
    }))
}
