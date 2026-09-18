//! "N actions need a manager": everything this till did that the server would
//! not back on its own, and one manager PIN that clears the whole batch
//! (DEFERRED_FEATURES_STATUS stream 11, part 2; owner 2026-09-17).
//!
//! Two things land in the same list, because to the person at the till they are
//! the same problem — something they did is not settled:
//!
//! 1. **Refused** — a live route answered 403, so the op dead-lettered in the
//!    outbox carrying the capability it wanted (`refused_cap`). Nothing was
//!    lost; it is still queued. A manager's approval is written into its
//!    payload and it is re-sent.
//! 2. **Flagged** — the server ACCEPTED the act at replay because the money had
//!    already moved, and flagged it (`authz_replay_flags`). There is nothing to
//!    re-send: the flag is resolved through `POST /authz/flags/bulk-review`,
//!    recording the approval after the fact with the approver's id.
//!
//! The list itself is offline: refusals come from the local outbox and flags
//! from the last pull. Authorizing needs a connection (the flags half is the
//! server's record, and a re-send has to reach the server), and the view says
//! so rather than failing silently.
//!
//! Partial results are shown honestly: an item whose capability THIS approver
//! cannot approve stays in the list with the reason, and so does an id the
//! server would not resolve. Nothing is ever dropped quietly.

use madar_authz::Cap;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::approvals::{approval_wire, request, ApprovalView};
use crate::error::CoreError;
use crate::MadarCore;

/// kv key of the last pulled open flags for this device's branch.
const K_FLAGS: &str = "review:flags";

/// Prefixes that keep the two id spaces apart on the wire to the host.
const P_OP: &str = "op:";
const P_FLAG: &str = "flag:";

/// One flag as the server told us about it, kept locally so the list works
/// offline. A subset of the server's `ReplayFlag` — only what the till shows.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub(crate) struct CachedFlag {
    pub id: i64,
    #[serde(default)]
    pub branch_id: Option<String>,
    pub op: String,
    #[serde(default)]
    pub author_name: Option<String>,
    pub capability: String,
    pub reason: String,
    pub occurred_at: String,
}

/// One thing at this till that needs a manager.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct ManagerActionView {
    /// Opaque; pass back to [`MadarCore::authorize_manager_actions`].
    pub id: String,
    /// `refused` (still queued, will be re-sent) | `flagged` (already on the
    /// books, waiting to be approved after the fact).
    pub kind: String,
    /// What it was, in the till's language: "Void", "Refund", "Discount over
    /// the cap", "Waste", "Resumed someone else's held order".
    pub what: String,
    /// Why it was refused or flagged, in the till's language.
    pub why: String,
    /// The permission it needs (shown small, and what the PIN is checked for).
    pub capability: String,
    /// Who did it. Empty when the server did not name them.
    pub person_name: String,
    /// When it happened (RFC3339, the event time — not when it was flagged).
    pub occurred_at: String,
    /// The money it moved, when the act has an amount.
    pub amount_minor: Option<i64>,
}

/// The till-level indicator and its list.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct ManagerActionsView {
    pub count: u32,
    pub items: Vec<ManagerActionView>,
    /// One line for the indicator: "3 actions need a manager".
    pub headline: String,
    /// A connection is there, so the PIN can actually clear these.
    pub can_authorize: bool,
    /// Why not, when `can_authorize` is false. Empty otherwise.
    pub blocked_reason: String,
}

/// What one manager PIN managed to clear.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct BatchAuthorizeView {
    /// Ids that are settled now (re-sent with the approval, or resolved).
    pub authorized: Vec<String>,
    /// Everything this approver could not clear, each with its reason. Still
    /// in the list; never silently dropped.
    pub left: Vec<ManagerActionView>,
    /// A one-line summary for the till: "Cleared 3 of 5".
    pub summary: String,
}

/// The capability a refused op wanted, from the op type and its payload.
/// `None` for an op no permission gates — such a refusal is a different
/// problem and does not belong in this list.
pub(crate) fn capability_for_op(op_type: &str, payload: &str) -> Option<&'static str> {
    Some(match op_type {
        "void_order" | "void_ticket" | "void_ticket_line" => "orders.void",
        "refund_order" => "refunds.create",
        "record_waste" => "inventory.waste.record",
        "spot_report_view" => "till.cash_spot_check",
        // A counter sale or a settled table bill is only ever refused live for
        // its discount; the kind of discount decides which cap.
        "create_order" | "settle_open_ticket" => discount_cap(payload)?,
        _ => return None,
    })
}

/// Which discount capability a sale's payload is asking for.
fn discount_cap(payload: &str) -> Option<&'static str> {
    let v: Value = serde_json::from_str(payload).ok()?;
    let d = find_discount(&v)?;
    let kind = d.get("kind").and_then(Value::as_str).unwrap_or("");
    Some(match kind {
        "preset" => "orders.discount.preset",
        "percent" | "manual_percent" => "orders.discount.manual_percent",
        _ => "orders.discount.manual_amount",
    })
}

/// The discount object anywhere in a sale payload (the wire shape nests it
/// under `request`, and table bills under `request.settle`).
fn find_discount(v: &Value) -> Option<&Value> {
    match v {
        Value::Object(m) => {
            if let Some(d) = m.get("discount").filter(|d| d.is_object()) {
                return Some(d);
            }
            m.values().find_map(find_discount)
        }
        _ => None,
    }
}

/// The money an op moved, for the approval's `max_amount` check.
fn amount_of(payload: &str) -> Option<i64> {
    let v: Value = serde_json::from_str(payload).ok()?;
    amount_in(&v)
}

fn amount_in(v: &Value) -> Option<i64> {
    match v {
        Value::Object(m) => {
            for k in ["amount_minor", "total_minor", "value_minor", "refund_amount_minor"] {
                if let Some(n) = m.get(k).and_then(Value::as_i64) {
                    return Some(n);
                }
            }
            m.values().find_map(amount_in)
        }
        _ => None,
    }
}

/// The i18n key naming the act, from the capability it needs. One vocabulary
/// for both halves of the list, so a refused void and a flagged void read the
/// same.
fn what_key(capability: &str, op: &str) -> &'static str {
    match capability {
        "orders.void" => "review.what_void",
        "refunds.create" => "review.what_refund",
        "inventory.waste.record" => "review.what_waste",
        "till.cash_spot_check" => "review.what_cash_spot",
        "orders.held.resume_others" => "review.what_resume_held",
        c if c.starts_with("orders.discount") => "review.what_discount",
        _ => match op {
            "cash_spot_check" => "review.what_cash_spot",
            _ => "review.what_other",
        },
    }
}

/// The i18n key for why the server would not back it.
fn why_key(kind: &str, reason: &str) -> &'static str {
    match (kind, reason) {
        (_, "stale_snapshot") => "review.why_stale",
        (_, "pin_wrong_branch") => "review.why_wrong_branch",
        ("flagged", _) => "review.why_flagged",
        _ => "review.why_refused",
    }
}

impl MadarCore {
    fn cached_flags(&self) -> Vec<CachedFlag> {
        self.store
            .kv_get(K_FLAGS)
            .ok()
            .flatten()
            .and_then(|s| serde_json::from_str::<Vec<CachedFlag>>(&s).ok())
            .unwrap_or_default()
    }

    fn put_flags(&self, flags: &[CachedFlag]) {
        if let Ok(s) = serde_json::to_string(flags) {
            let _ = self.store.kv_put(K_FLAGS, &s);
        }
    }

    /// Everything at this till that needs a manager, refusals and flags in one
    /// list, newest last. Offline: nothing here touches the network.
    pub fn pending_manager_actions(&self) -> ManagerActionsView {
        let locale = self.current_locale();
        let tr = |k: &str| crate::i18n::tr(&locale, k);
        let mut items = Vec::new();

        for (op, cap) in self.store.refused_ops().unwrap_or_default() {
            items.push(ManagerActionView {
                id: format!("{P_OP}{}", op.seq),
                kind: "refused".into(),
                what: tr(what_key(&cap, &op.op_type)),
                why: tr(why_key("refused", "")),
                capability: cap,
                person_name: self.person_name(op.user_id.as_deref()),
                occurred_at: op.event_at.clone(),
                amount_minor: amount_of(&op.payload),
            });
        }
        for f in self.cached_flags() {
            items.push(ManagerActionView {
                id: format!("{P_FLAG}{}", f.id),
                kind: "flagged".into(),
                what: tr(what_key(&f.capability, &f.op)),
                why: tr(why_key("flagged", &f.reason)),
                capability: f.capability,
                person_name: f.author_name.unwrap_or_default(),
                occurred_at: f.occurred_at,
                amount_minor: None,
            });
        }
        items.sort_by(|a, b| a.occurred_at.cmp(&b.occurred_at));

        let online = self.current_session().map(|s| s.online).unwrap_or(false);
        ManagerActionsView {
            count: items.len() as u32,
            headline: format!("{} {}", items.len(), tr("review.needs_manager")),
            can_authorize: online && !items.is_empty(),
            blocked_reason: if online { String::new() } else { tr("review.needs_connection") },
            items,
        }
    }

    /// Whoever queued an op, by name, from the offline people bundle.
    fn person_name(&self, user_id: Option<&str>) -> String {
        let Some(id) = user_id else { return String::new() };
        if self.current_session().map(|s| s.user_id).as_deref() == Some(id) {
            return self.current_session().map(|s| s.display_name).unwrap_or_default();
        }
        crate::session::bundle_person_name(&self.store, id).unwrap_or_default()
    }

    /// Pull this branch's open flags so the list is current. Best-effort: the
    /// last pull stands when there is no connection.
    pub async fn refresh_review_flags(&self) -> Result<u32, CoreError> {
        let body = self.api.get_text("/authz/flags", &[]).await?;
        let all: Vec<CachedFlag> = serde_json::from_str(&body).unwrap_or_default();
        let branch = self.current_session().and_then(|s| s.branch_id);
        let mine: Vec<CachedFlag> = all
            .into_iter()
            .filter(|f| match (&branch, &f.branch_id) {
                (Some(b), Some(fb)) => b == fb,
                // A flag with no branch (a wrong-branch PIN) concerns everyone.
                (_, None) => true,
                _ => false,
            })
            .collect();
        self.put_flags(&mine);
        self.store.emit_changes([crate::changes::OUTBOX]);
        Ok(mine.len() as u32)
    }

    /// One manager PIN for the whole batch. The signed-in person does NOT
    /// change: the manager types their PIN, each item is checked against what
    /// THEY may approve, and everything they cover is settled at once.
    pub async fn authorize_manager_actions(
        &self,
        approver_pin: String,
        ids: Vec<String>,
    ) -> Result<BatchAuthorizeView, CoreError> {
        let locale = self.current_locale();
        let tr = |k: &str| crate::i18n::tr(&locale, k);
        if !self.current_session().map(|s| s.online).unwrap_or(false) {
            return Err(CoreError::Offline {
                detail: tr("review.needs_connection"),
            });
        }
        // A wrong PIN is one error for the batch, not a per-item refusal.
        let (approver_id, approver_name) =
            crate::session::bundle_person_by_pin(&self.store, approver_pin.trim())?;

        let all = self.pending_manager_actions().items;
        let wanted: Vec<ManagerActionView> = if ids.is_empty() {
            all
        } else {
            all.into_iter().filter(|i| ids.contains(&i.id)).collect()
        };

        let mut authorized = Vec::new();
        let mut left: Vec<ManagerActionView> = Vec::new();
        let mut flag_ids: Vec<i64> = Vec::new();
        let mut flag_items: Vec<ManagerActionView> = Vec::new();

        for item in wanted {
            let Some(cap) = Cap::from_key(&item.capability) else {
                left.push(with_why(item, tr("review.unknown_capability")));
                continue;
            };
            // `own` is false: by construction this is someone else's act being
            // approved, which is exactly what an `own` limit must not cover.
            let req = request(cap, item.amount_minor, None, Some(false));
            let approval = match self.approve_request(approver_pin.clone(), &req) {
                Ok(a) => a,
                Err(CoreError::Forbidden { action, .. }) => {
                    left.push(with_why(item, action));
                    continue;
                }
                Err(e) => return Err(e),
            };
            if let Some(seq) = item.id.strip_prefix(P_OP).and_then(|s| s.parse::<i64>().ok()) {
                match self.attach_approval(seq, &approval) {
                    Ok(()) => authorized.push(item.id.clone()),
                    Err(e) => left.push(with_why(item, e.to_string())),
                }
            } else if let Some(id) = item.id.strip_prefix(P_FLAG).and_then(|s| s.parse::<i64>().ok())
            {
                flag_ids.push(id);
                flag_items.push(item);
            }
        }

        if !flag_ids.is_empty() {
            // The flags half: one call, the approver named in the note so the
            // dashboard's queue shows who cleared it and from where.
            let note = format!("{} {approver_name} ({approver_id})", tr("review.note_prefix"));
            let body = serde_json::json!({ "flag_ids": flag_ids, "note": note });
            let resp = self.api.post_json("/authz/flags/bulk-review", &body).await?;
            let parsed: Value = serde_json::from_str(&resp).unwrap_or_default();
            let done: Vec<i64> = parsed
                .get("resolved")
                .and_then(Value::as_array)
                .map(|a| a.iter().filter_map(Value::as_i64).collect())
                .unwrap_or_default();
            for item in flag_items {
                let id = item.id.strip_prefix(P_FLAG).and_then(|s| s.parse::<i64>().ok());
                match id {
                    Some(i) if done.contains(&i) => authorized.push(item.id.clone()),
                    _ => {
                        let why = id
                            .and_then(|i| pending_reason(&parsed, i))
                            .unwrap_or_else(|| tr("review.server_left_it"));
                        left.push(with_why(item, why));
                    }
                }
            }
            // Drop what is settled from the local cache so the indicator falls
            // straight away, offline, without waiting for the next pull.
            let kept: Vec<CachedFlag> =
                self.cached_flags().into_iter().filter(|f| !done.contains(&f.id)).collect();
            self.put_flags(&kept);
        }

        // Send the re-queued refusals now rather than at the next tick.
        self.send_in_background(Vec::new());
        self.store.emit_changes([crate::changes::OUTBOX]);
        Ok(BatchAuthorizeView {
            summary: format!(
                "{} {} {}",
                authorized.len(),
                tr("review.of"),
                authorized.len() + left.len()
            ),
            authorized,
            left,
        })
    }

    /// Write the approval into a refused op's payload and put it back in the
    /// queue. The op never left the outbox, so nothing is re-created here.
    fn attach_approval(&self, seq: i64, approval: &ApprovalView) -> Result<(), CoreError> {
        let item = self
            .store
            .refused_ops()?
            .into_iter()
            .find(|(o, _)| o.seq == seq)
            .map(|(o, _)| o)
            .ok_or_else(|| CoreError::Validation {
                field: "action".into(),
                detail: "no longer refused".into(),
            })?;
        let mut payload: Value = serde_json::from_str(&item.payload)?;
        let Some(map) = payload.as_object_mut() else {
            return Err(CoreError::Validation {
                field: "payload".into(),
                detail: "unexpected shape".into(),
            });
        };
        map.insert("approval".into(), approval_wire(approval));
        self.store.requeue_refused(seq, &payload.to_string())?;
        Ok(())
    }
}

fn pending_reason(parsed: &Value, id: i64) -> Option<String> {
    parsed
        .get("pending")?
        .as_array()?
        .iter()
        .find(|p| p.get("id").and_then(Value::as_i64) == Some(id))
        .and_then(|p| p.get("reason").and_then(Value::as_str))
        .map(str::to_string)
}

fn with_why(mut item: ManagerActionView, why: impl Into<String>) -> ManagerActionView {
    item.why = why.into();
    item
}

#[cfg(test)]
#[path = "till_review/tests.rs"]
mod tests;
