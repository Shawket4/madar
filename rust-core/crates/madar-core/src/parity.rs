//! Money parity helpers (OFFLINE_B_DESIGN §7): field-by-field comparison of a
//! till's report as this device computes it and as the server states it, and
//! the divergence log (Settings → Diagnostics, Sentry with no customer data).
//!
//! The rollout's read-path modes (`legacy` / `shadow` / `new`) are gone: the
//! local rows are the only read path. What stays is the production guard that
//! checks the device's figures against the server's.

use std::collections::BTreeMap;

/// Compare two keyed listings: `(key → comparable value)`. Returns one line per
/// divergence (missing on either side, or a different value), capped.
pub(crate) fn diff_keyed<V: PartialEq + std::fmt::Debug>(
    what: &str,
    server: &BTreeMap<String, V>,
    local: &BTreeMap<String, V>,
) -> Vec<String> {
    let mut out = Vec::new();
    for (k, sv) in server {
        match local.get(k) {
            None => out.push(format!("{what}: {k} only on the server")),
            Some(lv) if lv != sv => out.push(format!("{what}: {k} server {sv:?} local {lv:?}")),
            _ => {}
        }
    }
    for k in local.keys().filter(|k| !server.contains_key(*k)) {
        out.push(format!("{what}: {k} only on this device"));
    }
    out.truncate(20);
    out
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

impl crate::MadarCore {
    /// Log money divergences (never blocks a read, never carries customer data).
    pub(crate) fn report_divergence(&self, area: &str, lines: Vec<String>) {
        if lines.is_empty() {
            return;
        }
        for l in &lines {
            self.push_diag("warn", format!("divergence [{area}] {l}"));
        }
        crate::obs::capture_bg_warning("parity.divergence", format!("{area}: {} divergence(s)", lines.len()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn diffs_name_what_is_missing_or_different() {
        let a: BTreeMap<String, i64> = [("x".to_string(), 1), ("y".to_string(), 2)].into();
        let b: BTreeMap<String, i64> = [("y".to_string(), 3), ("z".to_string(), 4)].into();
        let d = diff_keyed("orders", &a, &b);
        assert_eq!(d.len(), 3);
        assert!(d.iter().any(|l| l.contains("x only on the server")));
        assert!(d.iter().any(|l| l.contains("z only on this device")));
        assert!(d.iter().any(|l| l.contains("y server 2 local 3")));
        assert!(diff_keyed("orders", &a, &a).is_empty());
    }
}
