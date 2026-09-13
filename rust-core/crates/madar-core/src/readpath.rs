//! Read-path rollout flags and shadow comparison (OFFLINE_B_DESIGN §9).
//!
//! Each area has three modes, kept in kv `flags:local_first:<area>`:
//! * `legacy` — the pre-B read (server list + cache blob + outbox overlay);
//! * `shadow` — serve the legacy read, compute the local read too, and log every
//!   divergence (Settings → Diagnostics, and Sentry with no customer data);
//! * `new`    — the local read only (the default once the parity tests pass).

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
        Some("shadow") => ReadPathMode::Shadow,
        _ => ReadPathMode::New,
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

/// The money comparables of a Z report.
pub(crate) fn report_keyed(r: &crate::till::TillReportView) -> BTreeMap<String, i64> {
    let mut m = BTreeMap::new();
    m.insert("expected_cash".into(), r.expected_cash_minor);
    m.insert("total_payments".into(), r.total_payments_minor);
    m.insert("voided".into(), r.voided_amount_minor);
    m.insert("refunds".into(), r.refunds_issued_minor);
    m.insert("cash_in".into(), r.cash_in_minor);
    m.insert("cash_out".into(), r.cash_out_minor);
    for p in &r.payment_lines {
        m.insert(format!("method:{}", p.method), p.total_minor);
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
    fn modes_default_to_new_and_round_trip() {
        let s = Store::open("").unwrap();
        assert_eq!(mode(&s, "ledger"), ReadPathMode::New);
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
