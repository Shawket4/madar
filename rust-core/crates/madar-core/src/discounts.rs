//! Discounts at the till (PERMISSIONS phase 6): a preset, an amount typed by
//! hand, or a percentage typed by hand — order-level, capped per person.
//!
//! Every act goes through `decide`: allowed, needs a manager (over the
//! person's `max_amount` / `max_percent`, or asked-for), or refused. A manager
//! approves on this device with their PIN (`approvals.rs`); the approval is
//! kept with the cart, re-checked at checkout against the sale's real figures
//! and carried on the order's replay envelope, where the server re-checks it.

use madar_authz::{Cap, Decision, Request};
use madar_money::discount::decimal_of;

use crate::approvals::{decision_view, ActDecisionView, ApprovalView};
use crate::cart::{self, ManualDiscount};
use crate::error::CoreError;
use madar_api::models;
use crate::MadarCore;

// The discount act, its capability and its figures are madar-shared's
// (`madar_money::discount`), the rule the server judges a sale with — its
// rounding included (a `Decimal` rounded to even), so this till asks for a
// manager exactly when the server would.
pub use madar_money::discount::{KIND_MANUAL_AMOUNT, KIND_MANUAL_PERCENT, KIND_PRESET};

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

/// A rate (fraction) → basis points (madar-shared's `bps_of_rate`).
pub(crate) fn bps_of_rate(rate: f64) -> i64 {
    madar_money::discount::bps_of_rate(rate)
}

/// The request `decide` answers for a discount of `kind` with these figures.
/// `amount_minor` is what comes off; `percent_bps` the percentage, if any.
pub(crate) fn discount_request(kind: &str, amount_minor: Option<i64>, percent_bps: Option<i64>) -> Option<Request> {
    madar_money::discount::request_for(kind, amount_minor, percent_bps)
}

/// The figures a discount would have on a cart whose pre-discount subtotal is
/// `subtotal`: `(amount off, percent bps)` (madar-shared's `figures`).
pub(crate) fn figures(
    kind: &str,
    preset: Option<&models::Discount>,
    amount_minor: Option<i64>,
    percent_bps: Option<i64>,
    subtotal: i64,
) -> (Option<i64>, Option<i64>) {
    let preset = preset.map(|d| (d.dtype.as_str(), decimal_of(cart::discount_rate(d))));
    madar_money::discount::figures(kind, preset, amount_minor, percent_bps, subtotal)
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

/// The discount a SETTLE actually charges: the cashier's if they stated one,
/// the waiter's inherited from the ticket otherwise, none at all for the
/// literal `"none"`. The mirror of the server's `resolve_settle_discount` — a
/// bill's discount must be gated on what is CHARGED, not on what was typed.
pub(crate) fn resolve_settle_discount(
    cashier_id: Option<&str>,
    cashier_type: Option<&str>,
    cashier_value: Option<f64>,
    waiter: (Option<String>, Option<f64>),
    waiter_id: Option<String>,
) -> (Option<String>, Option<String>, Option<f64>) {
    let spoke = cashier_id.is_some_and(|s| !s.is_empty())
        || cashier_type.is_some_and(|s| !s.trim().is_empty())
        || cashier_value.is_some();
    if cashier_type == Some("none") {
        (None, None, None)
    } else if spoke {
        (
            cashier_id.filter(|s| !s.is_empty()).map(str::to_string),
            cashier_type.map(str::to_string),
            cashier_value,
        )
    } else {
        (waiter_id, waiter.0, waiter.1)
    }
}

/// Which discount ACT a resolved bill discount is, in the same vocabulary a
/// counter sale uses: a preset id means preset, an ad-hoc one is manual of its
/// type. Exactly the server's derivation in `discount_authz::ask_from`.
pub(crate) fn kind_of(preset_id: Option<&str>, dtype: Option<&str>) -> Option<&'static str> {
    match (preset_id, dtype) {
        (Some(_), _) => Some(KIND_PRESET),
        (None, Some("percentage")) => Some(KIND_MANUAL_PERCENT),
        (None, Some("fixed")) => Some(KIND_MANUAL_AMOUNT),
        _ => None,
    }
}

/// What a bill discount takes off a bill whose pre-discount subtotal is
/// `subtotal`: `(amount off, percent bps)`. A preset is read from the local
/// catalogue; an ad-hoc percentage is a FRACTION on the wire (0.10 = 10%),
/// matching `tax_rate` and the settle request.
pub(crate) fn bill_figures(
    kind: &str,
    preset: Option<&models::Discount>,
    dtype: Option<&str>,
    dvalue: Option<f64>,
    subtotal: i64,
) -> (Option<i64>, Option<i64>) {
    let _ = dtype;
    // A bill whose lines this device has not cached yet has NO known subtotal.
    // Clamping to it would clamp every amount to zero, and a zero discount is
    // under every cap — the gate would wave through exactly the bills it knows
    // least about. So an unknown subtotal clamps to nothing and the figure is
    // judged as typed.
    let ceiling = if subtotal > 0 { subtotal } else { i64::MAX };
    match kind {
        KIND_PRESET => figures(KIND_PRESET, preset, None, None, ceiling),
        KIND_MANUAL_PERCENT => {
            figures(KIND_MANUAL_PERCENT, None, None, Some(bps_of_rate(dvalue.unwrap_or(0.0))), ceiling)
        }
        _ => figures(
            KIND_MANUAL_AMOUNT,
            None,
            Some(madar_money::discount::fixed_minor(decimal_of(dvalue.unwrap_or(0.0)))),
            None,
            ceiling,
        ),
    }
}

/// A bill discount as the settle sheet and the gate both see it.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Default)]
pub struct BillDiscountView {
    /// `preset` | `manual_amount` | `manual_percent`, empty for none.
    pub kind: String,
    pub preset_id: Option<String>,
    /// What it takes off this bill right now, minor units.
    pub amount_minor: i64,
    /// Basis points, when it is a percentage.
    pub percent_bps: Option<i64>,
}

impl MadarCore {
    /// The discount act a settle of this ticket would perform, with its real
    /// figures against the bill's own subtotal. `None` when the bill carries no
    /// discount at all.
    pub(crate) fn bill_discount_act(
        &self,
        ticket_id: &str,
        discount_id: Option<&str>,
        discount_type: Option<&str>,
        discount_value: Option<f64>,
    ) -> Option<(BillDiscountView, Request)> {
        let cached = self.cached_ticket(ticket_id);
        let waiter = cached
            .as_ref()
            .and_then(|(raw, _)| raw.as_ref().map(crate::tickets::waiter_discount))
            .unwrap_or((None, None));
        let waiter_id = cached
            .as_ref()
            .and_then(|(raw, _)| raw.as_ref())
            .and_then(|v| v.discount_id.flatten())
            .map(|id| id.to_string());
        let (preset_id, dtype, dvalue) = resolve_settle_discount(
            discount_id,
            discount_type,
            discount_value,
            waiter,
            waiter_id,
        );
        let kind = kind_of(preset_id.as_deref(), dtype.as_deref())?;
        let preset = preset_id.as_deref().and_then(|id| self.preset_by_id(id));
        // The bill BEFORE its discount: what a percentage is a percentage OF.
        let subtotal = cached.as_ref().map(|(_, v)| v.subtotal_minor).unwrap_or(0);
        let (amount, bps) = bill_figures(kind, preset.as_ref(), dtype.as_deref(), dvalue, subtotal);
        let req = discount_request(kind, amount, bps)?;
        Some((
            BillDiscountView {
                kind: kind.to_string(),
                preset_id,
                amount_minor: amount.unwrap_or(0),
                percent_bps: bps,
            },
            req,
        ))
    }

    /// Whether the signed-in cashier may settle this bill with this discount:
    /// `allow`, `needs_approval` (a manager's PIN) or `deny`. Offline, and the
    /// same three capabilities and caps a counter sale answers to — a discount
    /// on a TABLE'S BILL used to be the one way round them.
    ///
    /// A bill with no discount is `allow`: there is no act to gate.
    pub fn decide_bill_discount(
        &self,
        ticket_id: String,
        discount_id: Option<String>,
        discount_type: Option<String>,
        discount_value: Option<f64>,
    ) -> ActDecisionView {
        match self.bill_discount_act(
            &ticket_id,
            discount_id.as_deref(),
            discount_type.as_deref(),
            discount_value,
        ) {
            Some((_, req)) => self.decide_request(&req),
            None => decision_view(&Decision::Allow, &self.current_locale()),
        }
    }

    /// The figures a bill's discount really has — what the settle sheet shows
    /// beside the manager prompt, so nobody approves a number they cannot see.
    pub fn bill_discount(
        &self,
        ticket_id: String,
        discount_id: Option<String>,
        discount_type: Option<String>,
        discount_value: Option<f64>,
    ) -> BillDiscountView {
        self.bill_discount_act(
            &ticket_id,
            discount_id.as_deref(),
            discount_type.as_deref(),
            discount_value,
        )
        .map(|(v, _)| v)
        .unwrap_or_default()
    }

    /// A manager approves this bill's discount with their PIN on this device.
    pub fn approve_bill_discount(
        &self,
        approver_pin: String,
        ticket_id: String,
        discount_id: Option<String>,
        discount_type: Option<String>,
        discount_value: Option<f64>,
    ) -> Result<ApprovalView, CoreError> {
        let (_, req) = self
            .bill_discount_act(
                &ticket_id,
                discount_id.as_deref(),
                discount_type.as_deref(),
                discount_value,
            )
            .ok_or_else(|| CoreError::Validation {
                field: "discount".into(),
                detail: "this bill carries no discount".into(),
            })?;
        self.approve_request(approver_pin, &req)
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

#[cfg(test)]
mod bill_tests {
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

    fn teller() -> madar_authz::EffectiveSet {
        eff(
            &[
                "orders.discount.manual_amount",
                "orders.discount.manual_percent",
                "orders.discount.preset",
            ],
            &[
                ("orders.discount.manual_amount", Limits { max_amount: Some(1000), ..Default::default() }),
                ("orders.discount.manual_percent", Limits { max_percent: Some(1000), ..Default::default() }),
            ],
        )
    }

    /// The cashier said nothing, so the WAITER's discount is what the drawer
    /// charges — and that is the act that must be judged. This silence was the
    /// hole: the bill came off and nobody asked whose cap it was under.
    #[test]
    fn a_settle_in_silence_inherits_the_waiters_discount() {
        let waiter = (Some("fixed".to_string()), Some(2000.0));
        assert_eq!(
            resolve_settle_discount(None, None, None, waiter.clone(), None),
            (None, Some("fixed".into()), Some(2000.0))
        );
        // The cashier speaks: theirs replaces the waiter's OUTRIGHT, never a
        // field-by-field merge.
        assert_eq!(
            resolve_settle_discount(None, Some("percentage"), Some(0.10), waiter.clone(), None),
            (None, Some("percentage".into()), Some(0.10))
        );
        // `none` settles the bill with no discount at all.
        assert_eq!(
            resolve_settle_discount(None, Some("none"), None, waiter, None),
            (None, None, None)
        );
    }

    /// A bill's discount is derived into the SAME act vocabulary a counter
    /// sale's is, so the same capability and the same cap answer for it.
    #[test]
    fn a_bills_discount_is_the_same_act_as_a_counter_sales() {
        assert_eq!(kind_of(Some("d1"), None), Some(KIND_PRESET));
        assert_eq!(kind_of(Some("d1"), Some("percentage")), Some(KIND_PRESET));
        assert_eq!(kind_of(None, Some("percentage")), Some(KIND_MANUAL_PERCENT));
        assert_eq!(kind_of(None, Some("fixed")), Some(KIND_MANUAL_AMOUNT));
        assert_eq!(kind_of(None, None), None, "no discount is no act");
    }

    /// Over the cap, a bill needs a manager exactly as a cart does; at the cap
    /// it goes through. A percentage bill discount is a FRACTION on the wire.
    #[test]
    fn a_bill_discount_over_the_cap_needs_a_manager_and_at_the_cap_is_allowed() {
        let t = teller();
        // 10.00 off a 50.00 bill: at the cap.
        let (amt, bps) = bill_figures(KIND_MANUAL_AMOUNT, None, Some("fixed"), Some(1000.0), 5000);
        assert_eq!((amt, bps), (Some(1000), None));
        let at = discount_request(KIND_MANUAL_AMOUNT, amt, bps).unwrap();
        assert_eq!(decide(&t, &at), Decision::Allow);

        // 20.00 off: double it.
        let (amt, bps) = bill_figures(KIND_MANUAL_AMOUNT, None, Some("fixed"), Some(2000.0), 5000);
        let over = discount_request(KIND_MANUAL_AMOUNT, amt, bps).unwrap();
        assert!(matches!(decide(&t, &over), Decision::NeedsApproval(_)));

        // 12.5% on the wire is 0.125, which is 1250 bps — over a 10% cap.
        let (amt, bps) = bill_figures(KIND_MANUAL_PERCENT, None, Some("percentage"), Some(0.125), 2000);
        assert_eq!((amt, bps), (Some(250), Some(1250)));
        let pct = discount_request(KIND_MANUAL_PERCENT, amt, bps).unwrap();
        assert!(matches!(decide(&t, &pct), Decision::NeedsApproval(_)));

        // 10% exactly: allowed.
        let (amt, bps) = bill_figures(KIND_MANUAL_PERCENT, None, Some("percentage"), Some(0.10), 2000);
        assert_eq!((amt, bps), (Some(200), Some(1000)));
        let ok = discount_request(KIND_MANUAL_PERCENT, amt, bps).unwrap();
        assert_eq!(decide(&t, &ok), Decision::Allow);
    }

    /// A PARTIAL settle is a smaller bill, so the same percentage is a smaller
    /// amount and may pass a cap the whole bill fails. The figures are always
    /// taken against THIS settle's subtotal — the discount is per financial
    /// transaction, not per party.
    #[test]
    fn a_partial_settle_is_judged_on_its_own_subtotal() {
        let capped = eff(
            &["orders.discount.manual_percent"],
            &[("orders.discount.manual_percent", Limits { max_amount: Some(1000), ..Default::default() })],
        );
        let whole = bill_figures(KIND_MANUAL_PERCENT, None, Some("percentage"), Some(0.20), 10_000);
        assert_eq!(whole, (Some(2000), Some(2000)));
        let half = bill_figures(KIND_MANUAL_PERCENT, None, Some("percentage"), Some(0.20), 5_000);
        assert_eq!(half, (Some(1000), Some(2000)));
        let r = |f: (Option<i64>, Option<i64>)| {
            discount_request(KIND_MANUAL_PERCENT, f.0, f.1).unwrap()
        };
        // `manual_percent` is judged on its PERCENT, so a max_amount cap alone
        // does not bite — the split does not launder a percentage past a cap.
        assert_eq!(decide(&capped, &r(whole)), Decision::Allow);
        assert_eq!(decide(&capped, &r(half)), Decision::Allow);

        // An AMOUNT split in two, though, is two smaller acts — each answers
        // for itself, and each is under the cap.
        let t = teller();
        let full = bill_figures(KIND_MANUAL_AMOUNT, None, Some("fixed"), Some(1500.0), 10_000);
        assert!(matches!(
            decide(&t, &discount_request(KIND_MANUAL_AMOUNT, full.0, full.1).unwrap()),
            Decision::NeedsApproval(_)
        ));
        let leg = bill_figures(KIND_MANUAL_AMOUNT, None, Some("fixed"), Some(750.0), 5_000);
        assert_eq!(
            decide(&t, &discount_request(KIND_MANUAL_AMOUNT, leg.0, leg.1).unwrap()),
            Decision::Allow
        );
    }

    /// An UNKNOWN subtotal must not wave a discount through. Clamping to a
    /// subtotal of zero made every amount zero, and zero is under every cap —
    /// the gate would have been loosest on the bills it knew least about.
    #[test]
    fn an_unknown_subtotal_judges_the_figure_as_typed() {
        let t = teller();
        let (amt, bps) = bill_figures(KIND_MANUAL_AMOUNT, None, Some("fixed"), Some(2000.0), 0);
        assert_eq!((amt, bps), (Some(2000), None));
        assert!(matches!(
            decide(&t, &discount_request(KIND_MANUAL_AMOUNT, amt, bps).unwrap()),
            Decision::NeedsApproval(_)
        ));
    }

    /// A discount never takes more off than the bill is worth.
    #[test]
    fn a_bill_discount_clamps_to_the_bill() {
        assert_eq!(
            bill_figures(KIND_MANUAL_AMOUNT, None, Some("fixed"), Some(9999.0), 2000),
            (Some(2000), None)
        );
    }
}
