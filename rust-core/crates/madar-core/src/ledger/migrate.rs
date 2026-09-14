//! One-time move of a pre-B store into the ledger rows (store step 4, one
//! transaction). Nothing is deleted: the `cache:*` blobs and `till:rec:*` rows
//! stay where they were (the legacy read path still reads them while the
//! read-path flag allows it), and no outbox row or payload is changed except to
//! name the ledger row it holds (`entity_type` / `entity_id`).
//!
//! Order matters, from most to least authoritative:
//! 1. the changefeed's own ledger rows (`sync_rows`), with their seqs;
//! 2. the till records;
//! 3. the history caches (server lists the device read while online) — only
//!    where no row exists yet, and never marking a till complete;
//! 4. every still-live outbox op, as the local row it stands for, including the
//!    ops an older build queued with `open_shift` / `shift_id`.

use std::collections::HashMap;

use rusqlite::{params, Connection, OptionalExtension, Transaction};
use serde_json::{json, Value};

use super::report::Method;
use super::{key_of, s, stored, write_row, Origin, T_CASH, T_ORDER, T_REFUND, T_TILL};
use crate::error::CoreResult;

fn kv(tx: &Connection, k: &str) -> CoreResult<Option<String>> {
    Ok(tx.query_row("SELECT v FROM kv WHERE k=?1", [k], |r| r.get(0)).optional()?)
}

fn kv_prefix(tx: &Connection, prefix: &str) -> CoreResult<Vec<(String, String)>> {
    let mut st = tx.prepare("SELECT k, v FROM kv WHERE substr(k, 1, length(?1)) = ?1 ORDER BY k")?;
    let v = st
        .query_map([prefix], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(v)
}

fn parse(raw: &str) -> Value {
    serde_json::from_str(raw).unwrap_or(Value::Null)
}

/// A cache blob written by `cache_views`: a list (or, for single records, a
/// one-element list; an older build wrote a bare object).
fn list_of(raw: &str) -> Vec<Value> {
    match parse(raw) {
        Value::Array(a) => a,
        Value::Null => Vec::new(),
        other => vec![other],
    }
}

pub(crate) fn backfill(tx: &Transaction<'_>) -> CoreResult<()> {
    let device_branch = kv(tx, "device_config")?
        .map(|r| parse(&r))
        .and_then(|v| s(&v, "branch_id").map(str::to_string))
        .unwrap_or_default();
    let methods: Vec<Method> = kv(tx, crate::menu::K_PAYMENT_METHODS)?
        .map(|r| list_of(&r))
        .unwrap_or_default()
        .iter()
        .filter_map(Method::from_json)
        .collect();
    let names = teller_names(tx)?;

    from_sync_rows(tx)?;
    till_records(tx)?;
    history_caches(tx, &device_branch)?;
    outbox_ops(tx, &device_branch, &methods, &names)?;
    Ok(())
}

fn teller_names(tx: &Connection) -> CoreResult<HashMap<String, String>> {
    let mut out = HashMap::new();
    if let Some(raw) = kv(tx, crate::session::BUNDLE_KEY)? {
        for t in parse(&raw).get("tellers").and_then(Value::as_array).cloned().unwrap_or_default() {
            if let (Some(id), Some(name)) = (s(&t, "user_id"), s(&t, "name")) {
                out.insert(id.to_string(), name.to_string());
            }
        }
    }
    Ok(out)
}

/// 1. The feed's ledger rows move out of `sync_rows`.
fn from_sync_rows(tx: &Connection) -> CoreResult<()> {
    // The last complete snapshot's window, approximated from when it ran (the
    // server windows 48 h back from its own clock).
    let mut windows: HashMap<String, chrono::DateTime<chrono::Utc>> = HashMap::new();
    for (k, v) in kv_prefix(tx, crate::sync_pull::K_LAST_FULL)? {
        let branch = k.trim_start_matches(crate::sync_pull::K_LAST_FULL).to_string();
        if let Ok(at) = chrono::DateTime::parse_from_rfc3339(&v) {
            let from = at.with_timezone(&chrono::Utc) - chrono::Duration::hours(48);
            tx.execute(
                "INSERT INTO sync_streams(stream, scope_key, window_from) VALUES(?1, ?2, ?3)
                 ON CONFLICT(stream) DO UPDATE SET window_from=excluded.window_from",
                params![format!("branch:{branch}"), branch, from.to_rfc3339()],
            )?;
            windows.insert(branch, from);
        }
    }
    for ty in [T_TILL, T_ORDER, T_CASH, T_REFUND] {
        let rows: Vec<(String, i64, String)> = {
            let mut st = tx.prepare("SELECT branch_id, seq, data FROM sync_rows WHERE type=?1 ORDER BY seq")?;
            let v = st
                .query_map([ty], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
                .collect::<Result<Vec<_>, _>>()?;
            v
        };
        for (branch, seq, data) in rows {
            let v = parse(&data);
            let Some(key) = key_of(ty, &v) else { continue };
            write_row(tx, ty, &key, &v, Origin::Feed(seq), None)?;
            if ty == T_TILL {
                let open = s(&v, "status") == Some("open");
                let opened = s(&v, "opened_at")
                    .and_then(|t| chrono::DateTime::parse_from_rfc3339(t).ok())
                    .map(|d| d.with_timezone(&chrono::Utc));
                let inside = matches!((opened, windows.get(&branch)), (Some(o), Some(w)) if o >= *w);
                if open || inside {
                    tx.execute("UPDATE ledger_tills SET complete=1 WHERE id=?1", [&key])?;
                }
            }
        }
        tx.execute("DELETE FROM sync_rows WHERE type=?1", [ty])?;
    }
    Ok(())
}

/// 2. Till records (`till:rec:<id>`): a till this device holds.
fn till_records(tx: &Connection) -> CoreResult<()> {
    for (k, raw) in kv_prefix(tx, "till:rec:")? {
        let id = k.trim_start_matches("till:rec:");
        let v = parse(&raw);
        if v.is_null() || stored(tx, T_TILL, id)?.is_some() {
            continue;
        }
        let queued_open = tx
            .query_row(
                "SELECT 1 FROM outbox WHERE id=?1 AND op_type IN ('open_till','open_shift') AND status IN ('pending','inflight','dead')",
                [id],
                |_| Ok(()),
            )
            .optional()?
            .is_some();
        write_row(tx, T_TILL, id, &v, if queued_open { Origin::Local } else { Origin::Fetch }, None)?;
        if queued_open {
            tx.execute("UPDATE ledger_tills SET complete=1 WHERE id=?1", [id])?;
        }
    }
    Ok(())
}

/// 3. What the device cached from the server's lists while online.
fn history_caches(tx: &Connection, device_branch: &str) -> CoreResult<()> {
    let branch_of_till = |tx: &Connection, till: &str| -> CoreResult<String> {
        Ok(tx
            .query_row("SELECT branch_id FROM ledger_tills WHERE id=?1", [till], |r| r.get::<_, String>(0))
            .optional()?
            .filter(|b| !b.is_empty())
            .unwrap_or_else(|| device_branch.to_string()))
    };

    // Past tills (`cache:tills`, TillSummaryView).
    if let Some(raw) = kv(tx, "cache:tills")? {
        for t in list_of(&raw) {
            let Some(id) = s(&t, "id") else { continue };
            if stored(tx, T_TILL, id)?.is_some() {
                continue;
            }
            let row = json!({
                "id": id, "branch_id": device_branch, "teller_id": "", "teller_name": t.get("teller_name"),
                "status": t.get("status"), "opening_cash": t.get("opening_cash_minor"),
                "closing_cash_declared": t.get("closing_declared_minor"),
                "closing_cash_system": t.get("closing_system_minor"),
                "cash_discrepancy": t.get("discrepancy_minor"), "opened_at": t.get("opened_at"),
                "closed_at": t.get("closed_at"), "device_code": t.get("device_code"),
                "verification": t.get("verification"), "opened_while_another_open": t.get("opened_while_another_open"),
                "reconciliation_status": t.get("reconciliation_status"),
            });
            write_row(tx, T_TILL, id, &row, Origin::Fetch, None)?;
        }
    }

    // A till's orders (`cache:till_orders:<till>` / legacy `cache:shift_orders:`).
    for prefix in ["cache:till_orders:", "cache:shift_orders:"] {
        for (k, raw) in kv_prefix(tx, prefix)? {
            let till = k.trim_start_matches(prefix).to_string();
            if till.is_empty() || till == "fresh" || till == "old" {
                continue;
            }
            let branch = branch_of_till(tx, &till)?;
            for o in list_of(&raw) {
                let Some(id) = s(&o, "id") else { continue };
                let probe = json!({"id": id, "order_ref": o.get("order_ref")});
                let k = super::resolve_key(tx, T_ORDER, &probe, id)?;
                if stored(tx, T_ORDER, &k)?.is_some() {
                    continue;
                }
                let row = json!({
                    "id": id, "branch_id": branch, "till_id": till, "order_number": o.get("order_number"),
                    "subtotal": o.get("subtotal_minor"), "tax_amount": o.get("tax_minor"),
                    "total_amount": o.get("total_minor"), "payment_method": o.get("payment_label"),
                    "status": o.get("status"), "created_at": o.get("created_at"), "teller_name": o.get("teller_name"),
                    "order_type": o.get("order_type"), "customer_name": o.get("customer_name"),
                    "price_flagged": o.get("price_flagged"), "order_ref": o.get("order_ref"),
                    "display_number": o.get("display_number"), "payment_legs": [], "items": [],
                });
                write_row(tx, T_ORDER, id, &row, Origin::Fetch, None)?;
            }
        }
    }

    // A till's drawer movements (`cache:cash:<till>`, CashMovementView).
    for (k, raw) in kv_prefix(tx, "cache:cash:")? {
        let till = k.trim_start_matches("cache:cash:").to_string();
        for m in list_of(&raw) {
            let Some(id) = s(&m, "id") else { continue };
            let probe = json!({"id": id, "client_ref": m.get("client_ref")});
            if stored(tx, T_CASH, &super::resolve_key(tx, T_CASH, &probe, id)?)?.is_some() {
                continue;
            }
            let row = json!({
                "id": id, "client_ref": m.get("client_ref"), "till_id": till, "amount": m.get("amount_minor"),
                "kind": m.get("kind"), "note": m.get("note"), "moved_by_name": m.get("moved_by_name"),
                "created_at": m.get("created_at"),
            });
            write_row(tx, T_CASH, id, &row, Origin::Fetch, None)?;
        }
    }

    // Full order records (`cache:order:<id>`, OrderFull) → detail + row.
    for (k, raw) in kv_prefix(tx, "cache:order:")? {
        let id = k.trim_start_matches("cache:order:").to_string();
        let Some(full) = list_of(&raw).into_iter().next() else { continue };
        tx.execute(
            "INSERT INTO order_details(order_id, raw, fetched_at) VALUES(?1, ?2, ?3) ON CONFLICT(order_id) DO NOTHING",
            params![id, full.to_string(), super::now_ms()],
        )?;
        let k = super::resolve_key(tx, T_ORDER, &full, &id)?;
        if stored(tx, T_ORDER, &k)?.is_none() {
            write_row(tx, T_ORDER, &k, &full, Origin::Fetch, None)?;
        }
    }

    // Server Z reports (`cache:till_report:<id>`, legacy `cache:shift_report:<id>`).
    for prefix in ["cache:till_report:", "cache:shift_report:"] {
        for (k, raw) in kv_prefix(tx, prefix)? {
            let id = k.trim_start_matches(prefix).to_string();
            if let Some(report) = list_of(&raw).into_iter().next() {
                tx.execute(
                    "INSERT INTO till_reports(till_id, raw, fetched_at) VALUES(?1, ?2, ?3) ON CONFLICT(till_id) DO NOTHING",
                    params![id, report.to_string(), super::now_ms()],
                )?;
            }
        }
    }

    // Refunds (`cache:refunds:shift:<till>` TillRefundsView, `cache:refunds:order:<id>` OrderRefundsView).
    for (k, raw) in kv_prefix(tx, "cache:refunds:")? {
        let till_hint = k.strip_prefix("cache:refunds:shift:").map(str::to_string);
        for view in list_of(&raw) {
            for r in view.get("refunds").and_then(Value::as_array).cloned().unwrap_or_default() {
                let Some(id) = s(&r, "id") else { continue };
                let probe = json!({"id": id, "client_ref": r.get("client_ref")});
                if r.get("queued").and_then(Value::as_bool) == Some(true)
                    || stored(tx, T_REFUND, &super::resolve_key(tx, T_REFUND, &probe, id)?)?.is_some()
                {
                    continue;
                }
                let Some(till) = till_hint.clone() else { continue };
                let row = json!({
                    "id": id, "client_ref": r.get("client_ref"), "order_id": r.get("order_id"), "till_id": till, "amount": r.get("amount_minor"),
                    "method": r.get("method"), "is_cash": r.get("is_cash"), "reason": r.get("reason"),
                    "note": r.get("note"), "issued_at": r.get("issued_at"), "issued_by_name": r.get("issued_by_name"),
                    "lines": r.get("lines").cloned().unwrap_or(json!([])).as_array().map(|ls| ls.iter().map(|l| json!({
                        "item_name": l.get("item_name"), "quantity": l.get("qty"), "amount": l.get("amount_minor"),
                        "restock": l.get("restocked"),
                    })).collect::<Vec<_>>()),
                });
                write_row(tx, T_REFUND, id, &row, Origin::Fetch, None)?;
            }
        }
    }
    Ok(())
}

/// 4. Every live outbox op as the row it stands for.
fn outbox_ops(tx: &Connection, device_branch: &str, methods: &[Method], names: &HashMap<String, String>) -> CoreResult<()> {
    let ops: Vec<crate::store::OutboxItem> = {
        let mut st = tx.prepare(&format!(
            "SELECT {} FROM outbox WHERE status IN ('pending','inflight','dead') ORDER BY seq",
            crate::store::OUTBOX_COLS
        ))?;
        let v = st.query_map([], crate::store::map_outbox_item)?.collect::<Result<Vec<_>, _>>()?;
        v
    };
    let name_of = |uid: &Option<String>| uid.as_deref().and_then(|u| names.get(u).cloned()).unwrap_or_default();
    for op in ops {
        let payload = parse(&op.payload);
        let (ty, key): (Option<&str>, Option<String>) = match op.op_type.as_str() {
            "open_till" | "open_shift" => {
                let req = &payload["request"];
                let id = s(req, "id").map(str::to_string).unwrap_or_else(|| op.id.clone());
                if stored(tx, T_TILL, &id)?.is_none() {
                    let reason = s(req, "edit_reason").map(str::to_string);
                    let verification = s(&payload, "verification").map(str::to_string);
                    let row = json!({
                        "id": id, "branch_id": s(&payload, "branch_id").unwrap_or(device_branch),
                        "teller_id": op.user_id.clone().unwrap_or_default(), "teller_name": name_of(&op.user_id),
                        "status": "open", "opening_cash": req.get("opening_cash").cloned().unwrap_or(json!(0)),
                        "opening_cash_was_edited": reason.is_some(), "opening_cash_edit_reason": reason,
                        "opened_at": s(req, "opened_at").unwrap_or(&op.event_at),
                        "device_id": s(&payload, "device_id"), "device_code": s(&payload, "device_code"),
                        "verification": verification,
                    });
                    write_row(tx, T_TILL, &id, &row, Origin::Local, None)?;
                }
                tx.execute("UPDATE ledger_tills SET complete=1 WHERE id=?1", [&id])?;
                (Some(T_TILL), Some(id))
            }
            "close_till" | "close_shift" => {
                let id = s(&payload, "till_id").or(s(&payload, "shift_id")).map(str::to_string).or(op.till_id.clone());
                (Some(T_TILL), id)
            }
            "create_order" => {
                let key = op.id.clone();
                if super::order_key_for(tx, &key)?.is_none() {
                    if let Ok(cmd) = serde_json::from_str::<crate::checkout::CheckoutCommand>(&op.payload) {
                        let row = super::local::order_json(
                            &cmd,
                            &key,
                            &super::local::Ringer {
                                teller_id: op.user_id.as_deref().unwrap_or(""),
                                teller_name: &name_of(&op.user_id),
                            },
                            methods,
                        );
                        write_row(tx, T_ORDER, &key, &row, Origin::Local, None)?;
                    }
                }
                (Some(T_ORDER), Some(key))
            }
            "void_order" => {
                let target = s(&payload, "order_id").unwrap_or("").to_string();
                let key = super::order_key_for(tx, &target)?.unwrap_or(target);
                (Some(T_ORDER), Some(key))
            }
            "settle_open_ticket" => {
                let ticket = s(&payload, "ticket_id").map(str::to_string);
                if let Some(t) = ticket.as_deref() {
                    if super::order_key_for(tx, t)?.is_none() {
                        // The bill the cashier settled, as the device last saw it.
                        let bill_total = kv(tx, "cache:open_tickets")?
                            .map(|r| list_of(&r))
                            .unwrap_or_default()
                            .into_iter()
                            .find(|v| s(v, "id") == Some(t))
                            .map(|v| {
                                let total = v
                                    .get("bill")
                                    .and_then(|b| b.get("total"))
                                    .and_then(Value::as_i64)
                                    .unwrap_or_else(|| super::i(&v, "subtotal"));
                                super::local::bill_from_json(v.get("bill"), total)
                            })
                            .unwrap_or_else(|| super::local::bill_from_json(None, 0));
                        let req = &payload["request"];
                        let legs: Vec<(String, i64)> = req
                            .get("payment_splits")
                            .and_then(Value::as_array)
                            .map(|a| a.iter().map(|l| (s(l, "method").unwrap_or("").to_string(), super::i(l, "amount"))).collect())
                            .unwrap_or_default();
                        let row = super::local::settle_json(
                            t,
                            device_branch,
                            s(req, "till_id").or(s(req, "shift_id")).or(op.till_id.as_deref()).unwrap_or(""),
                            &super::local::Ringer { teller_id: op.user_id.as_deref().unwrap_or(""), teller_name: &name_of(&op.user_id) },
                            s(req, "payment_method").unwrap_or(""),
                            &legs,
                            &bill_total,
                            None,
                            super::i(req, "tip_amount"),
                            s(req, "tip_payment_method"),
                            &op.event_at,
                            methods,
                        );
                        write_row(tx, T_ORDER, t, &row, Origin::Local, None)?;
                    }
                }
                (Some(T_ORDER), ticket)
            }
            "refund_order" => {
                let req = &payload["request"];
                let key = s(req, "client_ref").map(str::to_string).unwrap_or_else(|| op.idempotency_key.clone());
                if stored(tx, T_REFUND, &key)?.is_none() {
                    let method = s(req, "method").unwrap_or("").to_string();
                    let row = json!({
                        "id": key, "client_ref": key, "order_id": s(req, "order_id"),
                        "till_id": s(req, "till_id").or(s(req, "shift_id")).map(str::to_string).or(op.till_id.clone()),
                        "amount": req.get("amount").cloned().unwrap_or(json!(0)), "method": method,
                        "is_cash": super::local::is_cash_of(methods, &method), "reason": s(req, "reason"),
                        "note": s(req, "note"), "issued_by_name": name_of(&op.user_id),
                        "issued_at": s(req, "issued_at").unwrap_or(&op.event_at), "lines": [],
                    });
                    write_row(tx, T_REFUND, &key, &row, Origin::Local, None)?;
                }
                (Some(T_REFUND), Some(key))
            }
            "cash_movement" => {
                let req = &payload["request"];
                let key = s(req, "client_ref").map(str::to_string).unwrap_or_else(|| op.id.clone());
                if stored(tx, T_CASH, &key)?.is_none() {
                    let amount = req.get("amount").and_then(Value::as_i64).unwrap_or(0);
                    let row = json!({
                        "id": key, "client_ref": key,
                        "till_id": s(&payload, "till_id").or(s(&payload, "shift_id")).map(str::to_string).or(op.till_id.clone()),
                        "amount": amount,
                        "kind": s(req, "kind").map(str::to_string).unwrap_or_else(|| if amount < 0 { "pay_out".into() } else { "pay_in".into() }),
                        "corrects_id": s(req, "corrects_id"), "note": s(req, "note"),
                        "moved_by_name": name_of(&op.user_id), "created_at": s(req, "created_at").unwrap_or(&op.event_at),
                    });
                    write_row(tx, T_CASH, &key, &row, Origin::Local, None)?;
                }
                (Some(T_CASH), Some(key))
            }
            _ => (None, None),
        };
        if let (Some(ty), Some(key)) = (ty, key) {
            tx.execute(
                "UPDATE outbox SET entity_type=?1, entity_id=?2 WHERE seq=?3",
                params![ty, key, op.seq],
            )?;
            // The op's effect on a row that existed before it (a void, a close).
            super::local::reapply_pending(tx, ty, &key)?;
        }
    }
    Ok(())
}
