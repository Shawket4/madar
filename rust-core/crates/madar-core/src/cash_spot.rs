//! Cash spot: the full live till report and its print (owner design
//! 2026-09-16 evening item 5, corrected 2026-09-17).
//!
//! * With `till.cash_spot_check` the person opens the FULL live till report of
//!   their open till (expected cash, every payment method, all figures: the old
//!   X report) and may print it; the expected figures also show on the close
//!   screen before closing.
//! * Without it the person counts BLIND at close: the open till's figures are
//!   not given out, and the finished report is shown only after the close.
//! * A lesser account still gets the Cash spot button and the close figures
//!   action: someone holding the grant types their PIN (`approve_cash_spot`),
//!   which unlocks exactly ONE look. The signed-in person never changes.
//! * Nothing is counted in a spot. Every look is recorded (who, when, printed,
//!   whose PIN): a ledger row plus a `spot_report_view` outbox op, offline.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::approvals::{ActDecisionView, ApprovalView};
use crate::error::CoreError;
use crate::ledger::spot::{self, SpotRow, T_SPOT};
use crate::{store, till, MadarCore};

pub const CAP_CASH_SPOT: &str = "till.cash_spot_check";

/// kv prefix of approvals minted for a spot and not used yet.
const K_UNUSED: &str = "cash_spot:approval:";

/// One recorded look at the spot report.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SpotViewLineView {
    pub id: String,
    pub viewed_by_name: String,
    /// Whose PIN unlocked it (none when the viewer held the grant).
    pub approved_by_name: Option<String>,
    pub viewed_at: String,
    pub printed: bool,
    /// Still in the outbox.
    pub queued: bool,
}

pub(crate) fn line_view(r: &SpotRow) -> SpotViewLineView {
    SpotViewLineView {
        id: r.id.clone(),
        viewed_by_name: r.viewed_by_name.clone(),
        approved_by_name: r.approved_by_name.clone(),
        viewed_at: r.viewed_at.clone(),
        printed: r.printed,
        queued: r.queued,
    }
}

/// The live till report the spot shows.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CashSpotView {
    /// This look's id: pass it to [`MadarCore::record_cash_spot_print`].
    pub view_id: String,
    pub report: till::TillReportView,
    pub expected_cash_minor: i64,
    /// Every method used, cash first (cash carries the drawer).
    pub methods: Vec<till::CloseTillMethodView>,
    /// Every look at this till's spot report so far, this one included.
    pub views: Vec<SpotViewLineView>,
}

/// The outbox payload.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct SpotViewCommand {
    pub till_id: String,
    #[serde(default)]
    pub device_id: Option<String>,
    pub request: Value,
    #[serde(default)]
    pub approval: Option<Value>,
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

    /// Someone holding the grant unlocks ONE look with their PIN on this device.
    pub fn approve_cash_spot(&self, approver_pin: String) -> Result<ApprovalView, CoreError> {
        let a = self.approve_act(approver_pin, CAP_CASH_SPOT.to_string(), None, None, None)?;
        self.store.kv_put(&format!("{K_UNUSED}{}", a.id), &serde_json::to_string(&a)?)?;
        Ok(a)
    }

    fn spot_denied(&self) -> CoreError {
        CoreError::Forbidden {
            resource: "till".into(),
            action: crate::i18n::tr(&self.current_locale(), "spot.needs_pin"),
        }
    }

    /// Allowed outright, or by an unused approval minted here (then used up).
    fn spot_unlock(&self, approval: Option<&ApprovalView>) -> Result<(), CoreError> {
        if self.till_figures_visible() {
            return Ok(());
        }
        let a = approval.ok_or_else(|| self.spot_denied())?;
        let key = format!("{K_UNUSED}{}", a.id);
        let stored = self.store.kv_get(&key)?.and_then(|r| serde_json::from_str::<ApprovalView>(&r).ok());
        match stored {
            Some(s) if s.capability == CAP_CASH_SPOT && s.approver_id == a.approver_id => {
                self.store.kv_delete(&key)?;
                Ok(())
            }
            _ => Err(self.spot_denied()),
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

    /// Open the cash spot: the full live report of the open till. Records the
    /// look (queued, offline-capable); an approval, when needed, is used up.
    pub async fn cash_spot_view(&self, approval: Option<ApprovalView>) -> Result<CashSpotView, CoreError> {
        let preview = self.close_till_preview().await?;
        let report = self.till_report().await?;
        self.spot_unlock(approval.as_ref())?;
        let t = preview.till.clone();
        let view_id = uuid::Uuid::new_v4().to_string();
        let viewed_at = self.corrected_now().to_rfc3339();
        let session = self.current_session();
        let dev = self.lan_device_id();
        let row = json!({
            "id": view_id, "till_id": t.id, "branch_id": t.branch_id,
            "viewed_by": session.as_ref().map(|s| s.user_id.clone()),
            "viewed_by_name": session.as_ref().map(|s| s.display_name.clone()).unwrap_or_default(),
            "printed": false,
            "approved_by": approval.as_ref().map(|a| a.approver_id.clone()),
            "approved_by_name": approval.as_ref().map(|a| a.approver_name.clone()),
            "approval_id": approval.as_ref().map(|a| a.id.clone()),
            "viewed_at": viewed_at, "device_id": dev,
            // Local only: the print of this look carries the same unlock.
            "approval_wire": approval.as_ref().map(crate::approvals::approval_wire),
        });
        let request = json!({ "id": view_id, "printed": false, "viewed_at": viewed_at, "device_id": dev });
        self.queue_spot_op(&t.id, &view_id, &view_id, request, &row, approval.as_ref().map(crate::approvals::approval_wire))?;
        let views = self.store.with_conn(|c| spot::for_till(c, &t.id))?.iter().map(line_view).collect();
        Ok(CashSpotView {
            view_id,
            expected_cash_minor: preview.expected_cash_minor,
            methods: preview.methods,
            report,
            views,
        })
    }

    /// The spot report of look `view_id` was printed: marks that look printed.
    pub async fn record_cash_spot_print(&self, view_id: String) -> Result<SpotViewLineView, CoreError> {
        let mut row = self
            .store
            .with_conn(|c| spot::raw(c, &view_id))?
            .ok_or_else(|| CoreError::Validation { field: "view_id".into(), detail: "no such spot view".into() })?;
        let me = self.current_session().map(|s| s.user_id).unwrap_or_default();
        let unlocked = row.get("approved_by").and_then(Value::as_str).is_some();
        if row.get("viewed_by").and_then(Value::as_str) != Some(me.as_str()) || (!unlocked && !self.till_figures_visible()) {
            return Err(self.spot_denied());
        }
        let till_id = row.get("till_id").and_then(Value::as_str).unwrap_or("").to_string();
        let printed_at = self.corrected_now().to_rfc3339();
        if let Value::Object(m) = &mut row {
            m.insert("printed".into(), json!(true));
            m.insert("printed_at".into(), json!(printed_at));
        }
        let request = json!({
            "id": view_id, "printed": true, "printed_at": printed_at,
            "viewed_at": row.get("viewed_at").cloned().unwrap_or(Value::Null),
            "device_id": row.get("device_id").cloned().unwrap_or(Value::Null),
        });
        let approval = row.get("approval_wire").cloned().filter(|v| !v.is_null());
        self.queue_spot_op(&till_id, &format!("{view_id}:print"), &view_id, request, &row, approval)?;
        let views = self.store.with_conn(|c| spot::for_till(c, &till_id))?;
        views
            .iter()
            .find(|v| v.id == view_id)
            .map(line_view)
            .ok_or_else(|| CoreError::Internal { detail: "spot view vanished".into() })
    }

    fn queue_spot_op(
        &self,
        till_id: &str,
        op_id: &str,
        view_id: &str,
        request: Value,
        row: &Value,
        approval: Option<Value>,
    ) -> Result<(), CoreError> {
        let dev = self.lan_device_id();
        let cmd = SpotViewCommand { till_id: till_id.to_string(), device_id: Some(dev.clone()), request, approval };
        let (user_id, clock_offset_ms) = self.outbox_meta();
        let op = store::NewOutboxOp {
            id: op_id.to_string(),
            op_type: T_SPOT.into(),
            idempotency_key: op_id.to_string(),
            payload: serde_json::to_string(&cmd)?,
            event_at: self.corrected_now().to_rfc3339(),
            depends_on_seq: self.store.live_seq_of(till_id)?,
            user_id,
            clock_offset_ms,
            till_id: Some(till_id.to_string()),
            device_id: Some(dev),
            entity_type: Some(T_SPOT.into()),
            entity_id: Some(view_id.to_string()),
        };
        self.store.with_tx_touch(|tx, touched| {
            spot::commit(tx, &op, row)?;
            touched.extend(crate::changes::tables_for_op(T_SPOT));
            Ok(())
        })?;
        self.send_in_background(Vec::new());
        Ok(())
    }

    /// The close screen's expected figures, before closing. With the grant
    /// always; otherwise with an approval, which this uses up.
    pub async fn close_figures(&self, approval: Option<ApprovalView>) -> Result<till::CloseTillPreviewView, CoreError> {
        self.spot_unlock(approval.as_ref())?;
        self.close_till_preview().await
    }
}
