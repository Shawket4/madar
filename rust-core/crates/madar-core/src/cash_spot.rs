//! Cash spot check and the live drawer figures (owner design 2026-09-16
//! evening, item 5).
//!
//! * With `till.cash_spot_check` the person sees the FULL live view (expected
//!   cash, tenders by method, the checks so far) and the expected figures on
//!   the close screen before closing. It replaces the old X / Z previews.
//! * Without it the person counts BLIND: the open till's figures are not
//!   given out, and the finished report is shown only after the close.
//! * A lesser account still gets the Cash spot button and the close figures
//!   action: someone holding the grant types their PIN (`approve_cash_spot`),
//!   which unlocks exactly ONE action (a view + its count, or the close
//!   figures). The signed-in person never changes.
//! * A spot check is recorded: a ledger row plus a `cash_spot_check` outbox op
//!   (with the approval on its envelope), offline-capable.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::approvals::{ActDecisionView, ApprovalView};
use crate::error::CoreError;
use crate::ledger::spot::{self, SpotRow, T_SPOT};
use crate::{store, till, MadarCore};

pub const CAP_CASH_SPOT: &str = "till.cash_spot_check";

/// kv prefix of approvals minted for a spot check and not used yet.
const K_UNUSED: &str = "cash_spot:approval:";

/// One recorded spot check.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SpotCheckLineView {
    pub id: String,
    pub counted_cash_minor: i64,
    pub expected_cash_minor: i64,
    /// counted − expected.
    pub discrepancy_minor: i64,
    pub checked_by_name: String,
    pub approved_by_name: Option<String>,
    pub checked_at: String,
    pub note: Option<String>,
    /// Still in the outbox.
    pub queued: bool,
}

pub(crate) fn line_view(r: &SpotRow) -> SpotCheckLineView {
    SpotCheckLineView {
        id: r.id.clone(),
        counted_cash_minor: r.counted_cash,
        expected_cash_minor: r.expected_cash,
        discrepancy_minor: r.cash_discrepancy,
        checked_by_name: r.checked_by_name.clone(),
        approved_by_name: r.approved_by_name.clone(),
        checked_at: r.checked_at.clone(),
        note: r.note.clone(),
        queued: r.queued,
    }
}

/// The live drawer view.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CashSpotView {
    pub report: till::TillReportView,
    pub expected_cash_minor: i64,
    /// Every method used, cash first (cash carries the drawer).
    pub methods: Vec<till::CloseTillMethodView>,
    pub checks: Vec<SpotCheckLineView>,
    /// The approval that opened this view (pass it to the count), if any.
    pub approval_id: Option<String>,
}

/// A counted figure for a non-cash method.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SpotCountInput {
    pub method: String,
    pub counted_minor: Option<i64>,
}

/// One method's line on a finished check.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SpotMethodResultView {
    pub method: String,
    pub label: String,
    pub is_cash: bool,
    pub expected_minor: i64,
    pub counted_minor: Option<i64>,
    pub discrepancy_minor: Option<i64>,
}

/// A finished check: what was recorded, per method, and the verdict.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SpotCheckResultView {
    pub check: SpotCheckLineView,
    pub methods: Vec<SpotMethodResultView>,
    /// `matches` | `over` | `short`.
    pub verdict: String,
}

/// The outbox payload.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct CashSpotCheckCommand {
    pub till_id: String,
    #[serde(default)]
    pub device_id: Option<String>,
    pub request: Value,
    #[serde(default)]
    pub approval: Option<Value>,
}

/// The method lines a check stores: cash first with the counted cash, every
/// other method with what was counted (or not).
pub(crate) fn plan_lines(
    expected_cash: i64,
    counted_cash: i64,
    methods: &[till::CloseTillMethodView],
    counts: &[SpotCountInput],
) -> Vec<SpotMethodResultView> {
    let mut out = Vec::new();
    let cash = methods.iter().find(|m| m.is_cash);
    out.push(SpotMethodResultView {
        method: cash.map(|c| c.method.clone()).unwrap_or_else(|| "cash".into()),
        label: cash.map(|c| c.label.clone()).unwrap_or_else(|| "cash".into()),
        is_cash: true,
        expected_minor: expected_cash,
        counted_minor: Some(counted_cash),
        discrepancy_minor: Some(counted_cash - expected_cash),
    });
    for m in methods.iter().filter(|m| !m.is_cash) {
        let counted = counts.iter().find(|c| c.method == m.method).and_then(|c| c.counted_minor);
        out.push(SpotMethodResultView {
            method: m.method.clone(),
            label: m.label.clone(),
            is_cash: false,
            expected_minor: m.system_total_minor,
            counted_minor: counted,
            discrepancy_minor: counted.map(|c| c - m.system_total_minor),
        });
    }
    out
}

pub(crate) fn verdict(discrepancy: i64) -> &'static str {
    match discrepancy {
        0 => "matches",
        d if d > 0 => "over",
        _ => "short",
    }
}

impl MadarCore {
    /// The signed-in person holds `till.cash_spot_check`: the open till's
    /// figures are theirs to see.
    pub fn till_figures_visible(&self) -> bool {
        self.can(CAP_CASH_SPOT.to_string())
    }

    /// The Cash spot button / the close figures action: `allow`, or
    /// `needs_approval` (someone holding the grant types their PIN). Never
    /// `deny` for a signed-in person: the owner's design always offers the PIN.
    pub fn cash_spot_access(&self) -> ActDecisionView {
        let d = self.decide_act(CAP_CASH_SPOT.to_string(), None, None, None);
        if d.outcome == "deny" && self.current_session().is_some() {
            return ActDecisionView { outcome: "needs_approval".into(), reason: d.reason };
        }
        d
    }

    /// Someone holding the grant unlocks ONE spot check / close figures action
    /// with their PIN on this device.
    pub fn approve_cash_spot(&self, approver_pin: String) -> Result<ApprovalView, CoreError> {
        let a = self.approve_act(approver_pin, CAP_CASH_SPOT.to_string(), None, None, None)?;
        self.store.kv_put(&format!("{K_UNUSED}{}", a.id), &serde_json::to_string(&a)?)?;
        Ok(a)
    }

    /// Allowed outright, or by an unused approval minted here (consumed when
    /// `consume`).
    fn spot_unlocked(&self, approval: Option<&ApprovalView>, consume: bool) -> Result<(), CoreError> {
        if self.till_figures_visible() {
            return Ok(());
        }
        let denied = || CoreError::Forbidden {
            resource: "till".into(),
            action: crate::i18n::tr(&self.current_locale(), "spot.needs_pin"),
        };
        let a = approval.ok_or_else(denied)?;
        let key = format!("{K_UNUSED}{}", a.id);
        let stored = self.store.kv_get(&key)?.and_then(|r| serde_json::from_str::<ApprovalView>(&r).ok());
        match stored {
            Some(s) if s.capability == CAP_CASH_SPOT && s.approver_id == a.approver_id => {
                if consume {
                    self.store.kv_delete(&key)?;
                }
                Ok(())
            }
            _ => Err(denied()),
        }
    }

    /// Guard for the open till's report: blind unless visible.
    pub(crate) fn require_figures_for(&self, report: &till::TillReportView) -> Result<(), CoreError> {
        if report.is_open && !self.till_figures_visible() {
            return Err(CoreError::Forbidden {
                resource: "till".into(),
                action: crate::i18n::tr(&self.current_locale(), "spot.blind"),
            });
        }
        Ok(())
    }

    /// The open till's report as the signed-in person may see it: refused
    /// while the till is open unless they hold the grant (blind count); a
    /// closed till's finished report always.
    pub async fn till_report_checked(&self) -> Result<till::TillReportView, CoreError> {
        let r = self.till_report().await?;
        self.require_figures_for(&r)?;
        Ok(r)
    }

    /// [`Self::till_report_checked`] for any till.
    pub async fn till_report_for_checked(&self, till_id: String) -> Result<till::TillReportView, CoreError> {
        let r = self.till_report_for(till_id).await?;
        self.require_figures_for(&r)?;
        Ok(r)
    }

    /// The close screen as the signed-in person may see it: without the grant
    /// the methods to count are listed but every expected figure is hidden
    /// (`figures_hidden`, amounts zero).
    pub async fn close_till_preview_checked(&self) -> Result<till::CloseTillPreviewView, CoreError> {
        let mut p = self.close_till_preview().await?;
        if !self.till_figures_visible() {
            p.figures_hidden = true;
            p.expected_cash_minor = 0;
            for m in p.methods.iter_mut() {
                m.system_total_minor = 0;
            }
        }
        Ok(p)
    }

    /// The full live drawer view of the open till.
    pub async fn cash_spot_view(&self, approval: Option<ApprovalView>) -> Result<CashSpotView, CoreError> {
        self.spot_unlocked(approval.as_ref(), false)?;
        let preview = self.close_till_preview().await?;
        let report = self.till_report().await?;
        let checks = self
            .store
            .with_conn(|c| spot::for_till(c, &preview.till.id))?
            .iter()
            .map(line_view)
            .collect();
        Ok(CashSpotView {
            expected_cash_minor: preview.expected_cash_minor,
            methods: preview.methods,
            report,
            checks,
            approval_id: approval.map(|a| a.id),
        })
    }

    /// The close screen's expected figures, before closing. With the grant
    /// always; otherwise with an approval, which this consumes.
    pub async fn close_figures(&self, approval: Option<ApprovalView>) -> Result<till::CloseTillPreviewView, CoreError> {
        self.spot_unlocked(approval.as_ref(), true)?;
        self.close_till_preview().await
    }

    /// Record a spot check of the open till. The expected snapshot is this
    /// device's figure right now; an approval, when used, is consumed and rides
    /// the queued op.
    pub async fn record_cash_spot_check(
        &self,
        counted_cash_minor: i64,
        counts: Vec<SpotCountInput>,
        note: Option<String>,
        approval: Option<ApprovalView>,
    ) -> Result<SpotCheckResultView, CoreError> {
        if counted_cash_minor < 0 {
            return Err(CoreError::Validation {
                field: "counted_cash".into(),
                detail: "counted cash cannot be negative".into(),
            });
        }
        self.spot_unlocked(approval.as_ref(), false)?;
        let preview = self.close_till_preview().await?;
        let t = preview.till.clone();
        let lines = plan_lines(preview.expected_cash_minor, counted_cash_minor, &preview.methods, &counts);
        let id = uuid::Uuid::new_v4().to_string();
        let checked_at = self.corrected_now().to_rfc3339();
        let note = note.map(|n| n.trim().to_string()).filter(|n| !n.is_empty());
        let session = self.current_session();
        let dev = self.lan_device_id();
        let discrepancy = counted_cash_minor - preview.expected_cash_minor;
        let wire_methods: Vec<Value> = lines
            .iter()
            .map(|l| json!({ "method": l.method, "is_cash": l.is_cash, "expected": l.expected_minor, "counted": l.counted_minor }))
            .collect();
        let request = json!({
            "id": id, "counted_cash": counted_cash_minor, "expected_cash": preview.expected_cash_minor,
            "methods": wire_methods, "note": note, "checked_at": checked_at, "device_id": dev,
        });
        let row = json!({
            "id": id, "till_id": t.id, "branch_id": t.branch_id,
            "counted_cash": counted_cash_minor, "expected_cash": preview.expected_cash_minor,
            "cash_discrepancy": discrepancy,
            "methods": lines.iter().map(|l| json!({ "method": l.method, "is_cash": l.is_cash,
                "expected": l.expected_minor, "counted": l.counted_minor, "discrepancy": l.discrepancy_minor })).collect::<Vec<_>>(),
            "note": note,
            "checked_by": session.as_ref().map(|s| s.user_id.clone()),
            "checked_by_name": session.as_ref().map(|s| s.display_name.clone()).unwrap_or_default(),
            "approved_by": approval.as_ref().map(|a| a.approver_id.clone()),
            "approved_by_name": approval.as_ref().map(|a| a.approver_name.clone()),
            "approval_id": approval.as_ref().map(|a| a.id.clone()),
            "checked_at": checked_at, "device_id": dev,
        });
        let cmd = CashSpotCheckCommand {
            till_id: t.id.clone(),
            device_id: Some(dev.clone()),
            request,
            approval: approval.as_ref().map(crate::approvals::approval_wire),
        };
        let (user_id, clock_offset_ms) = self.outbox_meta();
        let op = store::NewOutboxOp {
            id: id.clone(),
            op_type: T_SPOT.into(),
            idempotency_key: id.clone(),
            payload: serde_json::to_string(&cmd)?,
            event_at: checked_at.clone(),
            depends_on_seq: self.store.live_seq_of(&t.id)?,
            user_id,
            clock_offset_ms,
            till_id: Some(t.id.clone()),
            device_id: Some(dev),
            entity_type: Some(T_SPOT.into()),
            entity_id: Some(id.clone()),
        };
        self.store.with_tx_touch(|tx, touched| {
            spot::commit(tx, &op, &row)?;
            touched.extend(crate::changes::tables_for_op(T_SPOT));
            Ok(())
        })?;
        if approval.is_some() {
            self.spot_unlocked(approval.as_ref(), true)?;
        }
        self.send_in_background(Vec::new());
        Ok(SpotCheckResultView {
            check: SpotCheckLineView {
                id,
                counted_cash_minor,
                expected_cash_minor: preview.expected_cash_minor,
                discrepancy_minor: discrepancy,
                checked_by_name: session.map(|s| s.display_name).unwrap_or_default(),
                approved_by_name: approval.map(|a| a.approver_name),
                checked_at,
                note,
                queued: true,
            },
            methods: lines,
            verdict: verdict(discrepancy).into(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn m(method: &str, cash: bool, total: i64) -> till::CloseTillMethodView {
        till::CloseTillMethodView {
            method: method.into(),
            label: method.into(),
            is_cash: cash,
            system_total_minor: total,
            order_count: 1,
        }
    }

    #[test]
    fn a_spot_check_puts_cash_first_and_names_each_difference() {
        let methods = vec![m("card", false, 5000), m("cash", true, 6000)];
        let lines = plan_lines(6000, 5800, &methods, &[SpotCountInput { method: "card".into(), counted_minor: Some(5100) }]);
        assert_eq!(lines.len(), 2);
        assert!(lines[0].is_cash);
        assert_eq!(lines[0].discrepancy_minor, Some(-200));
        assert_eq!(lines[1].discrepancy_minor, Some(100));
        let lines = plan_lines(6000, 6000, &methods, &[]);
        assert_eq!(lines[1].counted_minor, None);
        assert_eq!(verdict(0), "matches");
        assert_eq!(verdict(-1), "short");
        assert_eq!(verdict(3), "over");
    }
}
