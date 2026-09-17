//! Ledger read paths (OFFLINE_B_DESIGN §6): history rows, the drawer, the Z
//! report, past tills, refunds, order detail — local queries only. No network
//! call happens inside any of these, so a read is as fast offline as online and
//! never waits on a timeout.
//!
//! Sync state is read from the outbox, never stored on the row: a row a
//! pending/inflight op holds is `queued`, a row a dead op holds is `failed`.


use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};

use super::report::{self, Method, TillFigures};
use super::{i, s, T_ORDER, T_REFUND};
use crate::error::CoreResult;
use crate::orders::{OrderRefundsView, OrderSummaryView, RefundLineView, RefundView, TillRefundsView};
use crate::store::Store;
use crate::till::{self, CashMovementView, TillReportCashLine, TillReportPaymentLine, TillReportView, TillSummaryView};

/// The org payment methods as the till report needs them: the changefeed's
/// rows when the branch has them (they carry `created_at`), else the cached
/// catalogue.
pub(crate) fn payment_method_rows(store: &Store) -> Vec<Method> {
    let raw = store.kv_get(crate::menu::K_PAYMENT_METHODS).ok().flatten().unwrap_or_default();
    serde_json::from_str::<Vec<Value>>(&raw)
        .unwrap_or_default()
        .iter()
        .filter_map(Method::from_json)
        .collect()
}

/// `queued` / `failed` / `None` for the ops holding one row.
fn op_state(conn: &Connection, ty: &str, key: &str) -> CoreResult<Option<&'static str>> {
    let statuses: Vec<String> = {
        let mut st = conn.prepare(
            "SELECT status FROM outbox WHERE entity_type=?1 AND entity_id=?2 AND status IN ('pending','inflight','dead')",
        )?;
        let v = st.query_map(params![ty, key], |r| r.get(0))?.collect::<Result<Vec<_>, _>>()?;
        v
    };
    Ok(if statuses.iter().any(|s| s == "dead") {
        Some("failed")
    } else if statuses.is_empty() {
        None
    } else {
        Some("queued")
    })
}

/// Whether the row's own create is still unsent (a queued sale, not a synced
/// sale with a queued void).
fn create_state(conn: &Connection, key: &str) -> CoreResult<Option<&'static str>> {
    let status: Option<String> = conn
        .query_row(
            "SELECT status FROM outbox WHERE entity_type='order' AND entity_id=?1
               AND op_type IN ('create_order','settle_open_ticket') AND status IN ('pending','inflight','dead')
             ORDER BY seq DESC LIMIT 1",
            [key],
            |r| r.get(0),
        )
        .optional()?;
    Ok(status.map(|s| if s == "dead" { "failed" } else { "queued" }))
}

fn order_summary(conn: &Connection, okey: &str, server_id: Option<String>, v: &Value) -> CoreResult<OrderSummaryView> {
    let unsent = create_state(conn, okey)?;
    let status = s(v, "status").unwrap_or("completed");
    let order_number = v.get("order_number").and_then(Value::as_i64);
    Ok(OrderSummaryView {
        // A synced sale is named by its server id (void, refund and detail take
        // it); a queued one by its client key until the server answers.
        id: server_id.unwrap_or_else(|| okey.to_string()),
        order_number: if unsent.is_some() { None } else { order_number.map(|n| n as i32) },
        subtotal_minor: i(v, "subtotal"),
        tax_minor: i(v, "tax_amount"),
        total_minor: i(v, "total_amount"),
        payment_label: s(v, "payment_method").unwrap_or("").to_string(),
        status: match (unsent, status) {
            (_, "voided") => "voided".into(),
            (Some(word), _) => word.into(),
            (None, other) => other.to_string(),
        },
        created_at: s(v, "created_at").unwrap_or("").to_string(),
        queued: unsent.is_some(),
        teller_name: if unsent.is_some() { None } else { s(v, "teller_name").map(str::to_string) },
        order_type: s(v, "order_type").unwrap_or("takeaway").to_string(),
        customer_name: s(v, "customer_name").map(str::to_string),
        price_flagged: v.get("price_flagged").and_then(Value::as_bool).unwrap_or(false),
        order_ref: s(v, "order_ref").map(str::to_string),
        display_number: crate::checkout::server_display_number(
            s(v, "display_number"),
            s(v, "order_ref"),
            s(v, "device_code"),
            order_number.unwrap_or(0),
        ),
    })
}

fn sort_newest_first(rows: &mut [OrderSummaryView]) {
    rows.sort_by(|a, b| {
        let ta = chrono::DateTime::parse_from_rfc3339(&a.created_at).ok();
        let tb = chrono::DateTime::parse_from_rfc3339(&b.created_at).ok();
        tb.cmp(&ta).then_with(|| b.id.cmp(&a.id))
    });
}

/// A till's sales, newest first — queued, failed and synced alike.
pub(crate) fn till_orders(store: &Store, till_id: &str) -> CoreResult<Vec<OrderSummaryView>> {
    store.with_conn(|c| {
        let rows: Vec<(String, Option<String>, String)> = {
            let mut st = c.prepare("SELECT okey, server_id, raw FROM ledger_orders WHERE till_id=?1")?;
            let v = st
                .query_map([till_id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
                .collect::<Result<Vec<_>, _>>()?;
            v
        };
        let mut out = Vec::with_capacity(rows.len());
        for (okey, sid, raw) in rows {
            let v: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
            out.push(order_summary(c, &okey, sid, &v)?);
        }
        sort_newest_first(&mut out);
        Ok(out)
    })
}

/// Every sale still on its way to the server, any till (the search screen shows
/// them on its first page).
pub(crate) fn unsent_orders(store: &Store) -> CoreResult<Vec<OrderSummaryView>> {
    store.with_conn(|c| {
        let rows: Vec<(String, Option<String>, String)> = {
            let mut st = c.prepare(
                "SELECT o.okey, o.server_id, o.raw FROM ledger_orders o
                  WHERE EXISTS (SELECT 1 FROM outbox x WHERE x.entity_type='order' AND x.entity_id=o.okey
                                  AND x.op_type IN ('create_order','settle_open_ticket')
                                  AND x.status IN ('pending','inflight','dead'))",
            )?;
            let v = st
                .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
                .collect::<Result<Vec<_>, _>>()?;
            v
        };
        let mut out = Vec::new();
        for (okey, sid, raw) in rows {
            let v: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
            out.push(order_summary(c, &okey, sid, &v)?);
        }
        sort_newest_first(&mut out);
        Ok(out)
    })
}

/// A till's drawer movements, oldest first (the order the report prints).
pub(crate) fn cash_movements(store: &Store, till_id: &str) -> CoreResult<Vec<CashMovementView>> {
    store.with_conn(|c| {
        let mut st = c.prepare("SELECT ckey, raw FROM ledger_cash WHERE till_id=?1")?;
        let rows: Vec<(String, String)> =
            st.query_map([till_id], |r| Ok((r.get(0)?, r.get(1)?)))?.collect::<Result<Vec<_>, _>>()?;
        let mut out: Vec<CashMovementView> = rows
            .into_iter()
            .map(|(ckey, raw)| {
                let v: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
                let amount = i(&v, "amount");
                CashMovementView {
                    // The client_ref (the key) is the movement's identity across
                    // the boundary, as `till::cash_movement_view` has it.
                    id: ckey,
                    kind: crate::till_views::movement_kind(s(&v, "kind"), amount),
                    amount_minor: amount,
                    note: s(&v, "note").unwrap_or("").to_string(),
                    moved_by_name: s(&v, "moved_by_name").unwrap_or("").to_string(),
                    created_at: s(&v, "created_at").unwrap_or("").to_string(),
                }
            })
            .collect();
        out.sort_by(|a, b| {
            let ta = chrono::DateTime::parse_from_rfc3339(&a.created_at).ok();
            let tb = chrono::DateTime::parse_from_rfc3339(&b.created_at).ok();
            ta.cmp(&tb).then_with(|| a.id.cmp(&b.id))
        });
        Ok(out)
    })
}

/// Is every ledger row of `till_id` on this device?
pub(crate) fn till_complete(store: &Store, till_id: &str) -> bool {
    store
        .with_conn(|c| {
            Ok(c.query_row("SELECT complete FROM ledger_tills WHERE id=?1", [till_id], |r| r.get::<_, i64>(0))
                .optional()?)
        })
        .ok()
        .flatten()
        .map(|x| x != 0)
        .unwrap_or(false)
}

pub(crate) fn figures(store: &Store, till_id: &str) -> CoreResult<Option<TillFigures>> {
    let methods = payment_method_rows(store);
    store.with_conn(|c| report::compute(c, till_id, &methods))
}

fn reconciliation_of(v: &Value, label: &dyn Fn(&str) -> String) -> Vec<till::ReconciliationLineView> {
    v.get("reconciliation")
        .and_then(|l| serde_json::from_value::<Vec<madar_api::models::TillReconciliationLine>>(l.clone()).ok())
        .map(|lines| till::reconciliation_lines_from_api(&lines, label))
        .unwrap_or_default()
}

fn order_number_range(store: &Store, till_id: &str) -> CoreResult<(Option<i64>, Option<i64>, Option<String>)> {
    // Columns kept by `write_row`: parsing every sale's JSON here was most of a
    // 34k-sale report. `MAX(device_code)` compares bytes, as the server's C collation.
    store.with_conn(|c| {
        Ok(c.query_row(
            "SELECT MIN(order_number), MAX(order_number), MAX(device_code) FROM ledger_orders WHERE till_id=?1",
            [till_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )?)
    })
}

/// The Z report for a till whose ledger is complete on this device, computed
/// here. `None` for a till the device does not hold completely (the caller
/// uses the server's report for those).
pub(crate) fn till_report(store: &Store, till_id: &str, label: &dyn Fn(&str) -> String) -> CoreResult<Option<TillReportView>> {
    if !till_complete(store, till_id) {
        return Ok(None);
    }
    till_report_rows(store, till_id, label)
}

/// What a till's rows on this device add up to, held completely or not
/// (`None` when the device has no row for the till at all). For a till not
/// held completely this is what is known so far, never the server's figure.
pub(crate) fn till_report_rows(store: &Store, till_id: &str, label: &dyn Fn(&str) -> String) -> CoreResult<Option<TillReportView>> {
    let Some(f) = figures(store, till_id)? else { return Ok(None) };
    let t = &f.till;
    let (first, last, range_code) = order_number_range(store, till_id)?;
    let mut reconciliation = reconciliation_of(t, label);
    if reconciliation.is_empty() {
        if let Some(r) = store
            .kv_get(&till::close_result_key(till_id))?
            .and_then(|raw| serde_json::from_str::<madar_api::models::CloseTillResponse>(&raw).ok())
        {
            reconciliation = till::reconciliation_lines_from_api(&r.reconciliation, label);
        }
    }
    let flag = |k: &str| t.get(k).and_then(Value::as_bool).unwrap_or(false);
    let opt_i = |k: &str| t.get(k).and_then(Value::as_i64);
    Ok(Some(TillReportView {
        teller_name: s(t, "teller_name").unwrap_or("").to_string(),
        opened_at: s(t, "opened_at").unwrap_or("").to_string(),
        closed_at: s(t, "closed_at").map(str::to_string),
        printed_at: chrono::Utc::now().to_rfc3339(),
        is_open: s(t, "status") == Some("open"),
        expected_cash_minor: f.expected_cash,
        opening_cash_minor: i(t, "opening_cash"),
        opening_cash_was_edited: flag("opening_cash_was_edited"),
        opening_cash_original_minor: opt_i("opening_cash_original"),
        opening_cash_edit_reason: s(t, "opening_cash_edit_reason").map(str::to_string),
        closing_cash_declared_minor: opt_i("closing_cash_declared"),
        total_payments_minor: f.total_payments,
        net_payments_minor: f.net_payments,
        voided_amount_minor: f.voided_amount,
        refunds_issued_minor: f.refunds_issued_amount,
        refunds_issued_cash_minor: f.refunds_issued_cash,
        refunds_issued_count: f.refunds_issued_count,
        cash_in_refunded_sales_minor: f.cash_in_refunded_sales,
        total_tax_minor: f.total_tax,
        total_service_charge_minor: f.total_service_charge,
        service_charge_waived_count: f.service_charge_waived_count,
        service_charge_waived_minor: f.service_charge_waived_amount,
        cash_movements_net_minor: f.cash_movements_net,
        cash_in_minor: f.cash_movements_in,
        cash_out_minor: f.cash_movements_out,
        payment_lines: f
            .payment_summary
            .iter()
            .map(|p| TillReportPaymentLine {
                method: p.payment_method.clone(),
                is_cash: p.is_cash,
                order_count: p.order_count,
                total_minor: p.total,
            })
            .collect(),
        cash_movements: f
            .cash_movements
            .iter()
            .map(|m| TillReportCashLine {
                amount_minor: m.amount,
                note: m.note.clone(),
                moved_by_name: m.moved_by_name.clone(),
                created_at: m.created_at.clone(),
            })
            .collect(),
        // Computed HERE, from the rows: never the server's figures. A report the
        // server produced is served by the caller instead (`server_authority`).
        from_server: false,
        device_code: s(t, "device_code").map(str::to_string).or(range_code),
        order_number_first: first,
        order_number_last: last,
        reconciliation,
        old_bills_count: opt_i("old_bills_at_close"),
        open_bills_count: opt_i("open_bills_at_close"),
        held_orders_left_open: opt_i("held_orders_left_open"),
        held_orders_left_open_total_minor: opt_i("held_orders_left_open_total"),
        opened_while_another_open: flag("opened_while_another_open"),
        verification: s(t, "verification").unwrap_or("legacy").to_string(),
        spot_views: f.spot_views.iter().map(crate::cash_spot::line_view).collect(),
    }))
}

/// The close screen's per-method lines (the cash line carries the drawer).
pub(crate) fn close_methods(store: &Store, till_id: &str, label: &dyn Fn(&str) -> String) -> CoreResult<Option<(i64, Vec<till::CloseTillMethodView>, bool)>> {
    let Some(f) = figures(store, till_id)? else { return Ok(None) };
    let methods = f
        .close_methods
        .iter()
        .map(|m| till::CloseTillMethodView {
            method: m.method.clone(),
            label: label(&m.method),
            is_cash: m.is_cash,
            system_total_minor: m.system_total,
            order_count: m.order_count,
        })
        .collect();
    Ok(Some((f.expected_cash, methods, f.unsynced == 0 && f.unconfirmed == 0)))
}

/// Tills OTHER than `till_id` open at `branch` according to this device's rows.
pub(crate) fn other_open_tills(store: &Store, branch: &str, till_id: &str) -> CoreResult<usize> {
    store.with_conn(|c| {
        Ok(c.query_row(
            "SELECT COUNT(*) FROM ledger_tills WHERE branch_id=?1 AND status='open' AND id<>?2",
            params![branch, till_id],
            |r| r.get::<_, i64>(0),
        )? as usize)
    })
}

/// Past tills at `branch`, newest first.
pub(crate) fn tills(store: &Store, branch: &str) -> CoreResult<Vec<TillSummaryView>> {
    store.with_conn(|c| {
        let mut st = c.prepare("SELECT raw FROM ledger_tills WHERE branch_id=?1 OR branch_id=''")?;
        let rows: Vec<String> = st.query_map([branch], |r| r.get(0))?.collect::<Result<Vec<_>, _>>()?;
        let mut out: Vec<TillSummaryView> = rows
            .iter()
            .filter_map(|raw| serde_json::from_str::<till::TillRecord>(raw).ok())
            .map(|t| till::till_summary_view(&t))
            .collect();
        out.sort_by(|a, b| {
            let ta = chrono::DateTime::parse_from_rfc3339(&a.opened_at).ok();
            let tb = chrono::DateTime::parse_from_rfc3339(&b.opened_at).ok();
            tb.cmp(&ta).then_with(|| b.id.cmp(&a.id))
        });
        Ok(out)
    })
}

fn refund_view(conn: &Connection, rkey: &str, server_id: Option<String>, v: &Value) -> CoreResult<RefundView> {
    Ok(RefundView {
        id: server_id.unwrap_or_else(|| rkey.to_string()),
        order_id: s(v, "order_id").unwrap_or("").to_string(),
        amount_minor: i(v, "amount"),
        method: s(v, "method").unwrap_or("").to_string(),
        is_cash: v.get("is_cash").and_then(Value::as_bool).unwrap_or(false),
        reason: s(v, "reason").unwrap_or("").to_string(),
        note: s(v, "note").map(str::to_string).filter(|n| !n.trim().is_empty()),
        issued_at: s(v, "issued_at").unwrap_or("").to_string(),
        issued_by_name: s(v, "issued_by_name").unwrap_or("").to_string(),
        lines: v
            .get("lines")
            .and_then(Value::as_array)
            .map(|ls| {
                ls.iter()
                    .map(|l| RefundLineView {
                        order_item_id: s(l, "order_item_id").unwrap_or("").to_string(),
                        item_name: s(l, "item_name").unwrap_or("").to_string(),
                        qty: i(l, "quantity") as i32,
                        amount_minor: i(l, "amount"),
                        restocked: l.get("restock").and_then(Value::as_bool).unwrap_or(false),
                    })
                    .collect()
            })
            .unwrap_or_default(),
        queued: op_state(conn, T_REFUND, rkey)?.is_some(),
    })
}

fn refunds_where(conn: &Connection, clause: &str, arg: &str) -> CoreResult<Vec<RefundView>> {
    let rows: Vec<(String, Option<String>, String)> = {
        let mut st = conn.prepare(&format!("SELECT rkey, server_id, raw FROM ledger_refunds WHERE {clause}"))?;
        let v = st.query_map([arg], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?.collect::<Result<Vec<_>, _>>()?;
        v
    };
    let mut out = Vec::new();
    for (rkey, sid, raw) in rows {
        let v: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
        out.push(refund_view(conn, &rkey, sid, &v)?);
    }
    out.sort_by(|a, b| a.issued_at.cmp(&b.issued_at));
    Ok(out)
}

/// Everything given back from a till's drawer.
fn issued_instant(r: &RefundView) -> i64 {
    chrono::DateTime::parse_from_rfc3339(&r.issued_at).map(|d| d.timestamp_micros()).unwrap_or(i64::MIN)
}

pub(crate) fn till_refunds(store: &Store, till_id: &str) -> CoreResult<TillRefundsView> {
    store.with_conn(|c| {
        let mut refunds = refunds_where(c, "till_id=?1", till_id)?;
        // Newest first, as the server lists a till's refunds.
        refunds.sort_by_key(|r| std::cmp::Reverse(issued_instant(r)));
        Ok(TillRefundsView {
            till_id: till_id.to_string(),
            refund_count: refunds.len() as i64,
            refunded_minor: refunds.iter().map(|r| r.amount_minor).sum(),
            refunded_cash_minor: refunds.iter().filter(|r| r.is_cash).map(|r| r.amount_minor).sum(),
            refunds,
        })
    })
}

/// Everything given back against one sale, and what is still refundable —
/// `None` when this device does not hold the sale.
pub(crate) fn order_refunds(store: &Store, order_id: &str) -> CoreResult<Option<OrderRefundsView>> {
    store.with_conn(|c| {
        let row: Option<(String, Option<String>, String)> = c
            .query_row(
                "SELECT okey, server_id, raw FROM ledger_orders WHERE server_id=?1 OR okey=?1 LIMIT 1",
                [order_id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()?;
        let Some((okey, sid, raw)) = row else { return Ok(None) };
        let v: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
        let server = sid.clone().unwrap_or_else(|| okey.clone());
        let mut refunds = refunds_where(c, "order_id=?1", &server)?;
        if server != okey {
            refunds.extend(refunds_where(c, "order_id=?1", &okey)?);
        }
        // Oldest first, as the server lists one sale's refunds.
        refunds.sort_by_key(issued_instant);
        let refunded: i64 = refunds.iter().map(|r| r.amount_minor).sum();
        let total = i(&v, "total_amount");
        Ok(Some(OrderRefundsView {
            order_id: server,
            order_status: s(&v, "status").unwrap_or("completed").to_string(),
            total_minor: total,
            refunded_minor: refunded,
            refunded_cash_minor: refunds.iter().filter(|r| r.is_cash).map(|r| r.amount_minor).sum(),
            refundable_remaining_minor: (total - refunded).max(0),
            refunds,
        }))
    })
}

/// A sale's full record for detail and reprint: the stored server record, or
/// the ledger row when it carries its lines.
pub(crate) fn order_full(store: &Store, order_id: &str) -> CoreResult<Option<madar_api::models::OrderFull>> {
    let (detail, row): (Option<String>, Option<(Option<String>, String)>) = store.with_conn(|c| {
        let detail = c
            .query_row("SELECT raw FROM order_details WHERE order_id=?1", [order_id], |r| r.get(0))
            .optional()?;
        let row = c
            .query_row(
                "SELECT server_id, raw FROM ledger_orders WHERE server_id=?1 OR okey=?1 LIMIT 1",
                [order_id],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?;
        Ok((detail, row))
    })?;
    if let Some(raw) = detail {
        if let Some(full) = decode_order_full(&serde_json::from_str(&raw).unwrap_or(Value::Null)) {
            return Ok(Some(full));
        }
    }
    if let Some((Some(_server_id), raw)) = row {
        let v: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
        if v.get("items").and_then(Value::as_array).map(|a| !a.is_empty()).unwrap_or(false) {
            return Ok(decode_order_full(&v));
        }
    }
    Ok(None)
}

/// An `OrderFull` from a feed row or a stored response: the feed omits the cost
/// fields the generated model requires, which read as unknown.
pub(crate) fn decode_order_full(v: &Value) -> Option<madar_api::models::OrderFull> {
    let mut v = v.clone();
    if let Some(items) = v.get_mut("items").and_then(Value::as_array_mut) {
        for it in items.iter_mut() {
            if it.get("cost_missing").is_none() {
                it["cost_missing"] = json!(true);
            }
            for group in ["addons", "optionals"] {
                if it.get(group).is_none() {
                    it[group] = json!([]);
                }
            }
            if it.get("name_translations").is_none() {
                it["name_translations"] = json!({});
            }
        }
    }
    for (k, d) in [("delivery_fee", json!(0)), ("discount_amount", json!(0)), ("discount_value", json!(0)),
                   ("order_type", json!("takeaway")), ("payment_legs", json!([])), ("items", json!([]))] {
        if v.get(k).map(Value::is_null).unwrap_or(true) {
            v[k] = d;
        }
    }
    if v.get("shift_id").map(Value::is_null).unwrap_or(true) {
        if let Some(t) = v.get("till_id").cloned() {
            v["shift_id"] = t;
        }
    }
    serde_json::from_value(v).ok()
}

/// Server orders fetched outside the feed (a past till this device never held
/// completely), stored as rows a feed row supersedes.
pub(crate) fn store_fetched_orders(store: &Store, rows: &[Value]) -> CoreResult<()> {
    store.with_tx_touch(|tx, touched| {
        for v in rows {
            let Some(key) = super::key_of(T_ORDER, v) else { continue };
            // The sale this list row IS — rung here and acked, fed, or fetched
            // before — under whatever key it lives (§7).
            let key = super::resolve_key(tx, T_ORDER, v, &key)?;
            if super::is_protected(tx, T_ORDER, &key)? {
                continue;
            }
            if let Some(p) = super::stored_meta(tx, T_ORDER, &key)? {
                // The feed's version, a row rung here or an ack's answer all know
                // more than a list read (a list row has no cash flag on its legs).
                if p.srv_seq > 0 || p.origin == "local" || p.acked {
                    continue;
                }
            }
            super::write_row(tx, T_ORDER, &key, v, super::Origin::Fetch, None)?;
        }
        touched.push(crate::changes::ORDERS);
        Ok(())
    })
}

/// The tills the parity guard compares: every open till held here, and every
/// closed till of the last two days whose reconciliation is not clean (awaiting
/// review or disagreed) — newest first, at most 20.
pub(crate) fn tills_to_check(store: &Store) -> CoreResult<Vec<String>> {
    let since = (chrono::Utc::now() - chrono::Duration::hours(48)).to_rfc3339();
    store.with_conn(|c| {
        let mut st = c.prepare(
            "SELECT id FROM ledger_tills
              WHERE complete=1 AND (status='open'
                 OR (datetime(COALESCE(closed_at, opened_at)) >= datetime(?1)
                     AND COALESCE(json_extract(raw, '$.reconciliation_status'), 'unreviewed') <> 'clean'))
              ORDER BY COALESCE(closed_at, opened_at) DESC LIMIT 20",
        )?;
        let v = st.query_map([since], |r| r.get(0))?.collect::<Result<Vec<String>, _>>()?;
        Ok(v)
    })
}

/// The newest server seq any row of a till carries (the till, its sales, its
/// drawer movements, its refunds).
pub(crate) fn newest_seq(store: &Store, till_id: &str) -> CoreResult<i64> {
    store.with_conn(|c| {
        Ok(c.query_row(
            "SELECT MAX(m) FROM (
                SELECT COALESCE(MAX(srv_seq),0) m FROM ledger_tills WHERE id=?1
                UNION ALL SELECT COALESCE(MAX(srv_seq),0) FROM ledger_orders WHERE till_id=?1
                UNION ALL SELECT COALESCE(MAX(srv_seq),0) FROM ledger_cash WHERE till_id=?1
                UNION ALL SELECT COALESCE(MAX(srv_seq),0) FROM ledger_refunds WHERE till_id=?1)",
            [till_id],
            |r| r.get(0),
        )?)
    })
}

/// The stored server report, when it may be served AS the report (design §7
/// "authority selection"): the device has everything the report includes
/// (`as_of_seq <= cursor`), the report includes everything the device holds of
/// this till (no row of it newer than `as_of_seq`), and nothing of the till is
/// still on its way or unconfirmed. Then the two can only differ by a bug in one
/// of them — and the server is the authority.
pub(crate) fn server_authority(store: &Store, till_id: &str) -> CoreResult<Option<madar_api::models::TillReportResponse>> {
    let Some(report) = stored_till_report(store, till_id) else { return Ok(None) };
    let as_of = report.as_of_seq.unwrap_or(0);
    if as_of <= 0 {
        return Ok(None);
    }
    let Some(f) = figures(store, till_id)? else { return Ok(None) };
    if f.unsynced > 0 || f.unconfirmed > 0 {
        return Ok(None);
    }
    let branch = s(&f.till, "branch_id").unwrap_or("").to_string();
    let (cursor, newest) = store.with_conn(|c| {
        let cursor = super::cursor_of(c, &branch)?;
        let newest: i64 = c.query_row(
            "SELECT MAX(m) FROM (
                SELECT COALESCE(MAX(srv_seq),0) m FROM ledger_tills WHERE id=?1
                UNION ALL SELECT COALESCE(MAX(srv_seq),0) FROM ledger_orders WHERE till_id=?1
                UNION ALL SELECT COALESCE(MAX(srv_seq),0) FROM ledger_cash WHERE till_id=?1
                UNION ALL SELECT COALESCE(MAX(srv_seq),0) FROM ledger_refunds WHERE till_id=?1)",
            [till_id],
            |r| r.get(0),
        )?;
        Ok((cursor, newest))
    })?;
    Ok((as_of <= cursor && newest <= as_of).then_some(report))
}

/// The server's Z report for a till the device does not hold completely.
pub(crate) fn put_till_report(store: &Store, till_id: &str, report: &madar_api::models::TillReportResponse) -> CoreResult<()> {
    let raw = serde_json::to_string(report)?;
    store.with_conn(|c| {
        c.execute(
            "INSERT INTO till_reports(till_id, raw, fetched_at) VALUES(?1, ?2, ?3)
             ON CONFLICT(till_id) DO UPDATE SET raw=excluded.raw, fetched_at=excluded.fetched_at",
            params![till_id, raw, super::now_ms()],
        )?;
        Ok(())
    })
}

pub(crate) fn stored_till_report(store: &Store, till_id: &str) -> Option<madar_api::models::TillReportResponse> {
    let raw: Option<String> = store
        .with_conn(|c| Ok(c.query_row("SELECT raw FROM till_reports WHERE till_id=?1", [till_id], |r| r.get(0)).optional()?))
        .ok()
        .flatten();
    raw.and_then(|r| serde_json::from_str(&r).ok())
}

