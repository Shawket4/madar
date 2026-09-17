//! Discounts at the till (PERMISSIONS phase 6): a preset, an amount typed by
//! hand, or a percentage typed by hand — order-level, capped per person.
//!
//! Every act goes through `decide`: allowed, needs a manager (over the
//! person's `max_amount` / `max_percent`, or asked-for), or refused. A manager
//! approves on this device with their PIN (`approvals.rs`); the approval is
//! kept with the cart, re-checked at checkout against the sale's real figures
//! and carried on the order's replay envelope, where the server re-checks it.

use madar_authz::{Cap, Decision, Request};

use crate::approvals::{decision_view, ActDecisionView, ApprovalView};
use crate::cart::{self, ManualDiscount};
use crate::error::CoreError;
use madar_api::models;
use crate::MadarCore;

pub const KIND_PRESET: &str = "preset";
pub const KIND_MANUAL_AMOUNT: &str = "manual_amount";
pub const KIND_MANUAL_PERCENT: &str = "manual_percent";

/// The cart's discount as the tender screen shows it.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Default)]
pub struct CartDiscountView {
    /// `preset` | `manual_amount` | `manual_percent`, empty for none.
    pub kind: String,
    pub preset_id: Option<String>,
    /// The typed amount (manual_amount), minor units.
    pub amount_minor: Option<i64>,
    /// The typed or preset percentage, basis points.
    pub percent_bps: Option<i64>,
    /// What it takes off the cart right now.
    pub off_minor: i64,
    /// The manager who approved it, when one had to.
    pub approved_by_name: Option<String>,
}

/// The capability for a discount act.
pub(crate) fn cap_for(kind: &str) -> Option<Cap> {
    match kind {
        KIND_PRESET => Some(Cap::OrdersDiscountPreset),
        KIND_MANUAL_AMOUNT => Some(Cap::OrdersDiscountManualAmount),
        KIND_MANUAL_PERCENT => Some(Cap::OrdersDiscountManualPercent),
        _ => None,
    }
}

/// A rate (fraction) → basis points.
pub(crate) fn bps_of_rate(rate: f64) -> i64 {
    (rate * 10_000.0).round().clamp(0.0, 10_000.0) as i64
}

/// The request `decide` answers for a discount of `kind` with these figures.
/// `amount_minor` is what comes off; `percent_bps` the percentage, if any.
pub(crate) fn discount_request(kind: &str, amount_minor: Option<i64>, percent_bps: Option<i64>) -> Option<Request> {
    let cap = cap_for(kind)?;
    let mut r = Request::of(cap);
    match kind {
        KIND_MANUAL_AMOUNT => r.amount = Some(amount_minor.unwrap_or(0)),
        KIND_MANUAL_PERCENT => r.percent = Some(percent_bps.unwrap_or(0)),
        _ => {
            r.amount = amount_minor;
            r.percent = percent_bps;
        }
    }
    Some(r)
}

/// The figures a discount would have on a cart whose pre-discount subtotal is
/// `subtotal`: `(amount off, percent bps)`.
pub(crate) fn figures(
    kind: &str,
    preset: Option<&models::Discount>,
    amount_minor: Option<i64>,
    percent_bps: Option<i64>,
    subtotal: i64,
) -> (Option<i64>, Option<i64>) {
    let pct_off = |bps: i64| ((subtotal as f64) * (bps as f64) / 10_000.0).round() as i64;
    match kind {
        KIND_MANUAL_AMOUNT => (Some(amount_minor.unwrap_or(0).clamp(0, subtotal.max(0))), None),
        KIND_MANUAL_PERCENT => {
            let bps = percent_bps.unwrap_or(0).clamp(0, 10_000);
            (Some(pct_off(bps)), Some(bps))
        }
        _ => match preset {
            Some(d) if d.dtype == "percentage" => {
                let bps = bps_of_rate(cart::discount_rate(d));
                (Some(pct_off(bps)), Some(bps))
            }
            Some(d) => (
                Some((cart::discount_rate(d).round() as i64).clamp(0, subtotal.max(0))),
                None,
            ),
            None => (None, None),
        },
    }
}

impl MadarCore {
    fn preset_by_id(&self, id: &str) -> Option<models::Discount> {
        let raw: Vec<models::Discount> = self
            .store
            .kv_get(crate::menu::K_DISCOUNTS)
            .ok()
            .flatten()
            .and_then(|j| serde_json::from_str(&j).ok())
            .unwrap_or_default();
        raw.into_iter().find(|d| d.id.to_string() == id && d.is_active)
    }

    /// The cart's subtotal before any discount, under the session's policy.
    fn undiscounted_subtotal(&self, table_id: Option<&str>) -> i64 {
        cart::lines(&self.store, table_id)
            .map(|lines| lines.iter().map(|l| l.line_total_minor).sum())
            .unwrap_or(0)
    }

    fn discount_ask(
        &self,
        table_id: Option<&str>,
        kind: &str,
        preset_id: Option<&str>,
        amount_minor: Option<i64>,
        percent_bps: Option<i64>,
    ) -> Result<Request, CoreError> {
        let preset = match kind {
            KIND_PRESET => Some(
                preset_id
                    .and_then(|id| self.preset_by_id(id))
                    .ok_or_else(|| CoreError::Validation {
                        field: "discount_id".into(),
                        detail: "unknown discount".into(),
                    })?,
            ),
            _ => None,
        };
        let (amount, bps) = figures(
            kind,
            preset.as_ref(),
            amount_minor,
            percent_bps,
            self.undiscounted_subtotal(table_id),
        );
        discount_request(kind, amount, bps).ok_or_else(|| CoreError::Validation {
            field: "kind".into(),
            detail: "unknown discount kind".into(),
        })
    }

    /// Whether the signed-in person may put this discount on the cart:
    /// `allow`, `needs_approval` (a manager's PIN) or `deny`. Offline.
    pub fn decide_discount(
        &self,
        table_id: Option<String>,
        kind: String,
        preset_id: Option<String>,
        amount_minor: Option<i64>,
        percent_bps: Option<i64>,
    ) -> ActDecisionView {
        match self.discount_ask(table_id.as_deref(), &kind, preset_id.as_deref(), amount_minor, percent_bps) {
            Ok(req) => self.decide_request(&req),
            Err(_) => decision_view(
                &Decision::Deny(madar_authz::Why::UnknownCapability),
                &self.current_locale(),
            ),
        }
    }

    /// A manager approves this discount with their PIN on this device.
    pub fn approve_discount(
        &self,
        approver_pin: String,
        table_id: Option<String>,
        kind: String,
        preset_id: Option<String>,
        amount_minor: Option<i64>,
        percent_bps: Option<i64>,
    ) -> Result<ApprovalView, CoreError> {
        let req = self.discount_ask(table_id.as_deref(), &kind, preset_id.as_deref(), amount_minor, percent_bps)?;
        self.approve_request(approver_pin, &req)
    }

    /// Put a discount on the cart. Refused unless `decide` allows it or
    /// `approval` is a manager's approval for this act.
    pub fn apply_discount(
        &self,
        table_id: Option<String>,
        kind: String,
        preset_id: Option<String>,
        amount_minor: Option<i64>,
        percent_bps: Option<i64>,
        approval: Option<ApprovalView>,
    ) -> Result<(), CoreError> {
        let t = table_id.as_deref();
        let req = self.discount_ask(t, &kind, preset_id.as_deref(), amount_minor, percent_bps)?;
        let approval = self.discount_authority(&req, approval)?;
        match kind.as_str() {
            KIND_PRESET => cart::set_discount(&self.store, t, preset_id.as_deref().unwrap_or(""))?,
            _ => cart::set_manual_discount(
                &self.store,
                t,
                &ManualDiscount { kind: kind.clone(), amount_minor, percent_bps },
            )?,
        }
        cart::set_discount_approval(&self.store, t, approval.as_ref())
    }

    /// Allowed outright (`None`), covered by a manager's approval for this
    /// capability (`Some`), or refused with the reason.
    pub(crate) fn discount_authority(
        &self,
        req: &Request,
        approval: Option<ApprovalView>,
    ) -> Result<Option<ApprovalView>, CoreError> {
        let cap = Cap::from_id(req.cap).map(|c| c.key()).unwrap_or_default();
        match self.decision_for(req) {
            Decision::Allow => Ok(None),
            Decision::NeedsApproval(_) if approval.as_ref().is_some_and(|a| a.capability == cap) => {
                Ok(approval)
            }
            d => Err(CoreError::Forbidden {
                resource: "discount".into(),
                action: decision_view(&d, &self.current_locale()).reason,
            }),
        }
    }

    /// The cart's discount: kind, figures, what it takes off, who approved it.
    pub fn cart_discount(&self, table_id: Option<String>) -> Result<CartDiscountView, CoreError> {
        let t = table_id.as_deref();
        let Some(kind) = cart::discount_act(&self.store, t)? else {
            return Ok(CartDiscountView::default());
        };
        let off = self.cart_totals(table_id.clone())?.discount_minor;
        let approved_by_name = cart::discount_approval(&self.store, t)?.map(|a| a.approver_name);
        Ok(match cart::manual_discount(&self.store, t)? {
            Some(m) => CartDiscountView {
                kind,
                preset_id: None,
                amount_minor: m.amount_minor,
                percent_bps: m.percent_bps,
                off_minor: off,
                approved_by_name,
            },
            None => {
                let id = cart::discount_id(&self.store, t)?;
                let bps = id
                    .as_deref()
                    .and_then(|i| self.preset_by_id(i))
                    .filter(|d| d.dtype == "percentage")
                    .map(|d| bps_of_rate(cart::discount_rate(&d)));
                CartDiscountView {
                    kind,
                    preset_id: id,
                    amount_minor: None,
                    percent_bps: bps,
                    off_minor: off,
                    approved_by_name,
                }
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use madar_authz::{decide, Limits};

    fn eff(caps: &[&str], limits: &[(&str, Limits)]) -> madar_authz::EffectiveSet {
        crate::approvals::effective_from(&crate::session::AuthzGrants {
            capabilities: caps.iter().map(|s| s.to_string()).collect(),
            ask_manager: vec![],
            limits: limits.iter().map(|(k, l)| (k.to_string(), *l)).collect(),
            owner: false,
        })
    }

    #[test]
    fn a_manual_amount_over_the_cap_needs_a_manager_and_at_the_cap_is_allowed() {
        let teller = eff(
            &["orders.discount.manual_amount"],
            &[("orders.discount.manual_amount", Limits { max_amount: Some(1000), ..Default::default() })],
        );
        let at = discount_request(KIND_MANUAL_AMOUNT, Some(1000), None).unwrap();
        assert_eq!(decide(&teller, &at), Decision::Allow);
        let over = discount_request(KIND_MANUAL_AMOUNT, Some(1001), None).unwrap();
        assert!(matches!(decide(&teller, &over), Decision::NeedsApproval(_)));
    }

    #[test]
    fn a_percent_cap_is_basis_points_and_unknown_grants_hold_nothing() {
        let teller = eff(
            &["orders.discount.manual_percent"],
            &[("orders.discount.manual_percent", Limits { max_percent: Some(1000), ..Default::default() })],
        );
        let (_, bps) = figures(KIND_MANUAL_PERCENT, None, None, Some(1250), 2000);
        let r = discount_request(KIND_MANUAL_PERCENT, None, bps).unwrap();
        assert!(matches!(decide(&teller, &r), Decision::NeedsApproval(_)));
        assert!(matches!(decide(&eff(&[], &[]), &r), Decision::Deny(_)), "not held: no");
    }

    #[test]
    fn figures_clamp_to_the_bill_and_round_percentages() {
        assert_eq!(figures(KIND_MANUAL_AMOUNT, None, Some(5000), None, 2000), (Some(2000), None));
        assert_eq!(figures(KIND_MANUAL_PERCENT, None, None, Some(1250), 2010), (Some(251), Some(1250)));
        assert_eq!(figures(KIND_MANUAL_PERCENT, None, None, Some(20_000), 100), (Some(100), Some(10_000)));
    }
}
