//! Manager approval on the till (PERMISSIONS_ARCHITECTURE §4.2, phase 5).
//!
//! `decide_act` answers, for the signed-in person, whether an act is allowed,
//! needs a manager, or is refused — over their grants and limits, offline.
//! When it needs a manager, a manager types THEIR PIN on the same device
//! (the session is not switched): `approve_act` finds them by PIN in the
//! offline bundle, reads their grants from the verified signed snapshot (or the
//! feed's teller row), runs `can_approve`, and mints an approval the host
//! passes to the act. The act's queued op carries it; the server re-checks the
//! approver at replay and keeps the record.

use madar_authz::{can_approve, decide, Cap, CapSet, Decision, EffectiveSet, Request, Why};
use serde::{Deserialize, Serialize};

use crate::error::CoreError;
use crate::session::AuthzGrants;
use crate::MadarCore;

/// What the till may do about an act right now.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct ActDecisionView {
    /// `allow` | `needs_approval` | `deny`
    pub outcome: String,
    /// Localized reason for `needs_approval` / `deny`, empty for `allow`.
    pub reason: String,
}

/// A manager's approval, to pass to the act it was asked for.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ApprovalView {
    pub id: String,
    pub capability: String,
    pub approver_id: String,
    pub approver_name: String,
    pub amount_minor: Option<i64>,
    /// The value the approval covers (`max_value` limits, e.g. a waste).
    #[serde(default)]
    pub value_minor: Option<i64>,
    /// Basis points, for an act capped by a percentage (a discount).
    #[serde(default)]
    pub percent_bps: Option<i64>,
}

/// The wire form a queued op carries (`approval` on the replay envelope).
pub(crate) fn approval_wire(a: &ApprovalView) -> serde_json::Value {
    serde_json::json!({
        "id": a.id,
        "capability": a.capability,
        "approver_id": a.approver_id,
        "amount_minor": a.amount_minor,
        "value_minor": a.value_minor,
        "percent_bps": a.percent_bps,
    })
}

pub(crate) fn effective_from(g: &AuthzGrants) -> EffectiveSet {
    EffectiveSet {
        caps: CapSet::from_keys(g.capabilities.iter().map(String::as_str)),
        limits: g
            .limits
            .iter()
            .filter_map(|(k, l)| Cap::from_key(k).map(|c| (c.id(), *l)))
            .collect(),
        kinds: Default::default(),
        owner: g.owner,
        ask_manager: CapSet::from_keys(g.ask_manager.iter().map(String::as_str)),
    }
}

pub(crate) fn request(cap: Cap, amount_minor: Option<i64>, age_minutes: Option<i64>, own: Option<bool>) -> Request {
    let mut r = Request::of(cap);
    r.amount = amount_minor;
    r.age_minutes = age_minutes;
    r.own = own;
    r
}

fn why_key(w: &Why) -> &'static str {
    match w {
        Why::NotHeld => "approval.why_not_held",
        Why::NotYours => "approval.why_not_yours",
        Why::OverLimit { .. } => "approval.why_over_limit",
        Why::SamePerson => "approval.why_same_person",
        _ => "approval.why_not_held",
    }
}

pub(crate) fn decision_view(d: &Decision, locale: &str) -> ActDecisionView {
    match d {
        Decision::Allow => ActDecisionView { outcome: "allow".into(), reason: String::new() },
        Decision::NeedsApproval(w) => ActDecisionView {
            outcome: "needs_approval".into(),
            reason: crate::i18n::tr(locale, why_key(w)),
        },
        Decision::Deny(w) => ActDecisionView {
            outcome: "deny".into(),
            reason: crate::i18n::tr(locale, why_key(w)),
        },
    }
}

impl MadarCore {
    /// Whether the signed-in person may do `cap_key` with these figures:
    /// allowed, needs a manager, or refused. Offline; never the network.
    pub fn decide_act(
        &self,
        cap_key: String,
        amount_minor: Option<i64>,
        age_minutes: Option<i64>,
        own: Option<bool>,
    ) -> ActDecisionView {
        let Some(cap) = Cap::from_key(&cap_key) else {
            return decision_view(&Decision::Deny(Why::UnknownCapability), &self.current_locale());
        };
        self.decide_request(&request(cap, amount_minor, age_minutes, own))
    }

    /// [`Self::decide_act`] over a whole request (amount, percent, age, own).
    pub(crate) fn decide_request(&self, req: &Request) -> ActDecisionView {
        let locale = self.current_locale();
        decision_view(&self.decision_for(req), &locale)
    }

    /// The raw decision for the signed-in person. Unknown grants: the legacy
    /// grid (role defaults) decides, as `can` does; signed out is a refusal.
    pub(crate) fn decision_for(&self, req: &Request) -> Decision {
        let Some(cap) = Cap::from_id(req.cap) else {
            return Decision::Deny(Why::UnknownCapability);
        };
        let grants = self
            .session
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .and_then(|s| s.authz.clone());
        let Some(grants) = grants else {
            // Grants not known (an older backend): the legacy grid decides, as `can` does.
            return if self.can(cap.key().to_string()) {
                Decision::Allow
            } else {
                Decision::Deny(Why::NotHeld)
            };
        };
        decide(&effective_from(&grants), req)
    }

    /// Whose sale `order_id` is and how old, from the local ledger: the
    /// figures an `own` / `max_age_minutes` limit is checked against.
    /// `(None, None)` when the sale is not held here.
    pub(crate) fn order_facts(&self, order_id: &str) -> (Option<bool>, Option<i64>) {
        let me = self.current_session().map(|s| s.user_id).unwrap_or_default();
        let row: Option<(String, String)> = self
            .store
            .with_conn(|c| {
                use rusqlite::OptionalExtension;
                Ok(c.query_row(
                    "SELECT o.created_at, t.teller_id FROM ledger_orders o
                       JOIN ledger_tills t ON t.id = o.till_id
                      WHERE o.okey = ?1 OR o.server_id = ?1",
                    [order_id],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )
                .optional()?)
            })
            .ok()
            .flatten();
        let Some((created, teller)) = row else { return (None, None) };
        let age = chrono::DateTime::parse_from_rfc3339(&created)
            .ok()
            .map(|t| (self.corrected_now().timestamp() - t.timestamp()).max(0) / 60);
        (Some(teller == me), age)
    }

    /// [`Self::decide_act`] for an act on one sale (void, refund): whose sale
    /// it is and its age come from the ledger, never from the screen.
    pub fn decide_order_act(
        &self,
        cap_key: String,
        order_id: String,
        amount_minor: Option<i64>,
    ) -> ActDecisionView {
        let (own, age) = self.order_facts(&order_id);
        self.decide_act(cap_key, amount_minor, age, own)
    }

    /// [`Self::approve_act`] for an act on one sale.
    pub fn approve_order_act(
        &self,
        approver_pin: String,
        cap_key: String,
        order_id: String,
        amount_minor: Option<i64>,
    ) -> Result<ApprovalView, CoreError> {
        let (own, age) = self.order_facts(&order_id);
        self.approve_act(approver_pin, cap_key, amount_minor, age, own)
    }

    /// A manager approves `cap_key` for the signed-in person by typing their
    /// own PIN on this device. Offline-capable. The approval is returned for
    /// the host to pass to the act; nothing is queued by approving alone.
    pub fn approve_act(
        &self,
        approver_pin: String,
        cap_key: String,
        amount_minor: Option<i64>,
        age_minutes: Option<i64>,
        own: Option<bool>,
    ) -> Result<ApprovalView, CoreError> {
        let cap = Cap::from_key(&cap_key).ok_or_else(|| CoreError::Validation {
            field: "capability".into(),
            detail: "unknown capability".into(),
        })?;
        self.approve_request(approver_pin, &request(cap, amount_minor, age_minutes, own))
    }

    /// A manager approves a whole request with their PIN (see [`Self::approve_act`]).
    pub(crate) fn approve_request(
        &self,
        approver_pin: String,
        req: &Request,
    ) -> Result<ApprovalView, CoreError> {
        let cap = Cap::from_id(req.cap).ok_or_else(|| CoreError::Validation {
            field: "capability".into(),
            detail: "unknown capability".into(),
        })?;
        let (subject, branch) = {
            let g = self.session.read().unwrap_or_else(|e| e.into_inner());
            let s = g.as_ref().ok_or_else(|| CoreError::Unauthenticated {
                detail: "not signed in".into(),
            })?;
            (s.snapshot.user_id.clone(), s.snapshot.branch_id.clone().unwrap_or_default())
        };
        let (approver_id, approver_name) =
            crate::session::bundle_person_by_pin(&self.store, approver_pin.trim())?;
        let grants = self
            .verified_snapshot(&branch)
            .and_then(|b| crate::authz_snapshot::grants_for(&b, &approver_id))
            .or_else(|| {
                crate::sync_pull::rows_of_type(&self.store, &branch, "teller")
                    .into_iter()
                    .find(|v| v.get("id").and_then(|x| x.as_str()) == Some(approver_id.as_str()))
                    .and_then(|row| crate::sync_pull::grants_from_teller_row(&row))
            })
            .ok_or_else(|| CoreError::Forbidden {
                resource: "approval".into(),
                action: crate::i18n::tr(&self.current_locale(), "approval.why_not_held"),
            })?;
        can_approve(
            &effective_from(&grants),
            &approver_id,
            &subject,
            req,
        )
        .map_err(|w| CoreError::Forbidden {
            resource: "approval".into(),
            action: crate::i18n::tr(&self.current_locale(), why_key(&w)),
        })?;
        Ok(ApprovalView {
            id: uuid::Uuid::new_v4().to_string(),
            capability: cap.key().to_string(),
            approver_id,
            approver_name,
            amount_minor: req.amount,
            value_minor: req.value,
            percent_bps: req.percent,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use madar_authz::Limits;

    fn grants(caps: &[&str], limits: &[(&str, Limits)], ask: &[&str]) -> AuthzGrants {
        AuthzGrants {
            capabilities: caps.iter().map(|s| s.to_string()).collect(),
            ask_manager: ask.iter().map(|s| s.to_string()).collect(),
            limits: limits.iter().map(|(k, l)| (k.to_string(), *l)).collect(),
            owner: false,
        }
    }

    #[test]
    fn a_teller_over_their_limit_needs_a_manager_who_holds_it() {
        let teller = effective_from(&grants(
            &["orders.void"],
            &[("orders.void", Limits { own: true, max_age_minutes: Some(10), ..Default::default() })],
            &[],
        ));
        let mine_recent = request(Cap::OrdersVoid, None, Some(3), Some(true));
        assert_eq!(decide(&teller, &mine_recent), Decision::Allow);
        let not_mine = request(Cap::OrdersVoid, None, Some(3), Some(false));
        assert!(matches!(decide(&teller, &not_mine), Decision::NeedsApproval(Why::NotYours)));

        let manager = effective_from(&grants(&["orders.void"], &[], &[]));
        assert!(can_approve(&manager, "m", "t", &not_mine).is_ok());
        assert_eq!(can_approve(&manager, "t", "t", &not_mine), Err(Why::SamePerson));
        let other_teller = teller.clone();
        assert!(can_approve(&other_teller, "t2", "t", &not_mine).is_err());
    }
}
