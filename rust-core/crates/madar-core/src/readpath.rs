//! Read-path rollout flags and shadow comparison (OFFLINE_B_DESIGN §9).
//!
//! Each area has three modes, kept in kv `flags:local_first:<area>`:
//! * `legacy` — the pre-B read (server list + cache blob + outbox overlay);
//! * `shadow` — serve the legacy read, compute the local read too, and log every
//!   divergence (Settings → Diagnostics, and Sentry with no customer data);
//! * `new`    — the local read only.
//!
//! **Default: `shadow`** (design §9: a pilot soaks in shadow until it shows zero
//! unexplained diffs). To flip a device or an area to `new`:
//! * from the host: `setReadPathMode(area: 'ledger', mode: ReadPathMode.new_)`
//!   (FRB, `madar-frb/src/api/sync.rs`), once per area in [`AREAS`];
//! * or in the store: `kv['flags:local_first:<area>'] = 'new'`.
//! Setting `legacy` rolls an area back; absent means shadow.

use std::collections::BTreeMap;

use crate::store::Store;

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Enum))]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ReadPathMode {
    Legacy,
    Shadow,
    New,
}

/// The areas a read-path flag covers.
pub const AREAS: &[&str] = &["ledger", "tickets", "kitchen", "delivery", "bookings"];

fn key(area: &str) -> String {
    format!("flags:local_first:{area}")
}

pub(crate) fn mode(store: &Store, area: &str) -> ReadPathMode {
    match store.kv_get(&key(area)).ok().flatten().as_deref() {
        Some("legacy") => ReadPathMode::Legacy,
        Some("new") => ReadPathMode::New,
        _ => ReadPathMode::Shadow,
    }
}

pub(crate) fn set_mode(store: &Store, area: &str, mode: ReadPathMode) -> crate::error::CoreResult<()> {
    if !AREAS.contains(&area) {
        return Err(crate::error::CoreError::Validation {
            field: "area".into(),
            detail: format!("unknown read-path area {area}"),
        });
    }
    let word = match mode {
        ReadPathMode::Legacy => "legacy",
        ReadPathMode::Shadow => "shadow",
        ReadPathMode::New => "new",
    };
    store.kv_put(&key(area), word)
}

/// Compare two keyed listings: `(key → comparable value)`. Returns one line per
/// divergence (missing on either side, or a different value), capped.
pub(crate) fn diff_keyed<V: PartialEq + std::fmt::Debug>(
    what: &str,
    legacy: &BTreeMap<String, V>,
    new: &BTreeMap<String, V>,
) -> Vec<String> {
    let mut out = Vec::new();
    for (k, lv) in legacy {
        match new.get(k) {
            None => out.push(format!("{what}: {k} only in legacy")),
            Some(nv) if nv != lv => out.push(format!("{what}: {k} legacy {lv:?} new {nv:?}")),
            _ => {}
        }
    }
    for k in new.keys().filter(|k| !legacy.contains_key(*k)) {
        out.push(format!("{what}: {k} only in new"));
    }
    out.truncate(20);
    out
}

/// Keyed comparables of an order list (by client ref when present — the one
/// identity a queued and a synced copy share — else id).
pub(crate) fn orders_keyed(rows: &[crate::orders::OrderSummaryView]) -> BTreeMap<String, (i64, String)> {
    rows.iter()
        .map(|o| {
            let status = match o.status.as_str() {
                "queued" | "failed" => "unsent".to_string(),
                s => s.to_string(),
            };
            (o.order_ref.clone().unwrap_or_else(|| o.id.clone()), (o.total_minor, status))
        })
        .collect()
}

pub(crate) fn cash_keyed(rows: &[crate::till::CashMovementView]) -> BTreeMap<String, i64> {
    rows.iter().map(|m| (m.id.clone(), m.amount_minor)).collect()
}

pub(crate) fn tills_keyed(rows: &[crate::till::TillSummaryView]) -> BTreeMap<String, (String, i64)> {
    rows.iter().map(|t| (t.id.clone(), (t.status.clone(), t.opening_cash_minor))).collect()
}

/// EVERY field of a Z report, keyed (timestamps compared as instants). Only
/// `printed_at` (the print time) and `from_server` (which side it came from)
/// are left out — they differ by definition.
pub(crate) fn report_keyed(r: &crate::till::TillReportView) -> BTreeMap<String, String> {
    fn instant(t: &str) -> String {
        chrono::DateTime::parse_from_rfc3339(t)
            .map(|d| d.timestamp_millis().to_string())
            .unwrap_or_else(|_| t.to_string())
    }
    let mut m = BTreeMap::new();
    let mut put = |k: &str, v: String| {
        m.insert(k.to_string(), v);
    };
    put("teller_name", r.teller_name.clone());
    put("opened_at", instant(&r.opened_at));
    put("closed_at", r.closed_at.as_deref().map(instant).unwrap_or_default());
    put("is_open", r.is_open.to_string());
    put("expected_cash", r.expected_cash_minor.to_string());
    put("opening_cash", r.opening_cash_minor.to_string());
    put("opening_cash_was_edited", r.opening_cash_was_edited.to_string());
    put("opening_cash_original", format!("{:?}", r.opening_cash_original_minor));
    put("opening_cash_edit_reason", format!("{:?}", r.opening_cash_edit_reason));
    put("closing_cash_declared", format!("{:?}", r.closing_cash_declared_minor));
    put("total_payments", r.total_payments_minor.to_string());
    put("net_payments", r.net_payments_minor.to_string());
    put("voided", r.voided_amount_minor.to_string());
    put("refunds", r.refunds_issued_minor.to_string());
    put("refunds_cash", r.refunds_issued_cash_minor.to_string());
    put("refunds_count", r.refunds_issued_count.to_string());
    put("cash_in_refunded_sales", r.cash_in_refunded_sales_minor.to_string());
    put("total_tax", r.total_tax_minor.to_string());
    put("total_service_charge", r.total_service_charge_minor.to_string());
    put("service_charge_waived", format!("{}/{}", r.service_charge_waived_count, r.service_charge_waived_minor));
    put("cash_movements_net", r.cash_movements_net_minor.to_string());
    put("cash_in", r.cash_in_minor.to_string());
    put("cash_out", r.cash_out_minor.to_string());
    put("device_code", format!("{:?}", r.device_code));
    put("order_number_first", format!("{:?}", r.order_number_first));
    put("order_number_last", format!("{:?}", r.order_number_last));
    put("old_bills_count", format!("{:?}", r.old_bills_count));
    put("open_bills_count", format!("{:?}", r.open_bills_count));
    put("opened_while_another_open", r.opened_while_another_open.to_string());
    put("verification", r.verification.clone());
    for p in &r.payment_lines {
        put(&format!("method:{}", p.method), format!("{} x{} cash={}", p.total_minor, p.order_count, p.is_cash));
    }
    let mut moves: Vec<String> = r
        .cash_movements
        .iter()
        .map(|c| format!("{}|{}|{}|{}", instant(&c.created_at), c.amount_minor, c.note, c.moved_by_name))
        .collect();
    moves.sort();
    put("cash_movements", moves.join(";"));
    for l in &r.reconciliation {
        put(
            &format!("reconciliation:{}", l.method),
            format!("{}|{}|{}|{:?}|{:?}|{}", l.is_cash, l.system_total_minor, l.status, l.declared_amount_minor, l.note, l.changed_after_close),
        );
    }
    m
}

pub(crate) fn tickets_keyed(rows: &[crate::tickets::TicketView]) -> BTreeMap<String, (String, i64)> {
    rows.iter().map(|t| (t.id.clone(), (t.status.clone(), t.subtotal_minor))).collect()
}

impl crate::MadarCore {
    /// Log shadow divergences (never blocks the read, never carries data).
    pub(crate) fn report_divergence(&self, area: &str, lines: Vec<String>) {
        if lines.is_empty() {
            return;
        }
        for l in &lines {
            self.push_diag("warn", format!("read-path divergence [{area}] {l}"));
        }
        crate::obs::capture_bg_warning(
            "readpath.divergence",
            format!("{area}: {} divergence(s)", lines.len()),
        );
    }

    /// The read-path mode of `area` (`legacy` / `shadow` / `new`).
    pub fn read_path_mode(&self, area: String) -> ReadPathMode {
        mode(&self.store, &area)
    }

    /// Switch one area's read path (a diagnostics toggle for QA and rollout).
    pub fn set_read_path_mode(&self, area: String, mode: ReadPathMode) -> Result<(), crate::error::CoreError> {
        set_mode(&self.store, &area, mode)?;
        self.store.emit_changes([crate::changes::ALL]);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn modes_default_to_shadow_and_round_trip() {
        let s = Store::open("").unwrap();
        for area in AREAS {
            assert_eq!(mode(&s, area), ReadPathMode::Shadow, "{area}");
        }
        set_mode(&s, "ledger", ReadPathMode::New).unwrap();
        assert_eq!(mode(&s, "ledger"), ReadPathMode::New);
        s.kv_put("flags:local_first:ledger", "garbage").unwrap();
        assert_eq!(mode(&s, "ledger"), ReadPathMode::Shadow, "an unknown word is the safe default");
        set_mode(&s, "ledger", ReadPathMode::Shadow).unwrap();
        assert_eq!(mode(&s, "ledger"), ReadPathMode::Shadow);
        set_mode(&s, "ledger", ReadPathMode::Legacy).unwrap();
        assert_eq!(mode(&s, "ledger"), ReadPathMode::Legacy);
        assert!(set_mode(&s, "nonsense", ReadPathMode::New).is_err());
    }

    #[test]
    fn diffs_name_what_is_missing_or_different() {
        let a: BTreeMap<String, i64> = [("x".to_string(), 1), ("y".to_string(), 2)].into();
        let b: BTreeMap<String, i64> = [("y".to_string(), 3), ("z".to_string(), 4)].into();
        let d = diff_keyed("orders", &a, &b);
        assert_eq!(d.len(), 3);
        assert!(d.iter().any(|l| l.contains("x only in legacy")));
        assert!(d.iter().any(|l| l.contains("z only in new")));
        assert!(d.iter().any(|l| l.contains("y legacy 2 new 3")));
        assert!(diff_keyed("orders", &a, &a).is_empty());
    }
}
