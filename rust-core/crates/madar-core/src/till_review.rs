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
    pub author_id: Option<String>,
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
    /// Their user id — who the approval is FOR. A manager may not approve
    /// their own act, and that rule is checked against this person, not
    /// against whoever happens to be signed in while the backlog is cleared.
    pub person_id: String,
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
        "record_staff_drink" => "orders.staff_drink.record",
        "spot_report_view" => "till.cash_spot_check",
        // A counter sale or a settled table bill is only ever refused live for
        // its discount; the kind of discount decides which cap.
        "create_order" | "settle_open_ticket" => discount_cap(payload)?,
        _ => return None,
    })
}

/// Which discount capability a sale's payload is asking for.
///
/// Both payloads are `{"request": …}` with the request's FLAT `discount_*`
/// fields (`CheckoutCommand` → `CreateOrderRequest`, `SettleTicketCommand` →
/// `SettleOpenTicketRequest`). The rule is madar-shared's
/// `madar_money::discount::ask_from`, the one the server judges with: a sale
/// carries a discount when it names a preset, takes an amount off, or has a
/// percentage/fixed type with a value above zero; an explicit kind wins, else a preset id means preset, else a
/// percentage means manual percent, else manual amount.
fn discount_cap(payload: &str) -> Option<&'static str> {
    let v: Value = serde_json::from_str(payload).ok()?;
    let r = v.get("request").filter(|r| r.is_object()).unwrap_or(&v);
    let text = |k: &str| r.get(k).and_then(Value::as_str).filter(|s| !s.is_empty());
    let fields = madar_money::discount::DiscountFields {
        has_preset: text("discount_id").is_some(),
        discount_type: text("discount_type"),
        discount_value: r
            .get("discount_value")
            .and_then(Value::as_f64)
            .map(madar_money::discount::decimal_of),
        discount_amount: r
            .get("discount_amount")
            .and_then(Value::as_i64)
            .map(|a| a.clamp(i64::from(i32::MIN), i64::from(i32::MAX)) as i32),
        discount_kind: text("discount_kind"),
        discount_percent_bps: None,
    };
    madar_money::discount::ask_from(&fields, None).map(|a| a.cap.key())
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
                person_id: op.user_id.clone().unwrap_or_default(),
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
                person_id: f.author_id.unwrap_or_default(),
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
    ///
    /// A till signed in as a TELLER does not hold `approvals.review`, so the
    /// plain pull 403s for it; the batch flow calls
    /// [`Self::pull_flags`] with the manager approval it just minted instead
    /// (backend, 2026-09-18).
    pub async fn refresh_review_flags(&self) -> Result<u32, CoreError> {
        self.pull_flags(None).await
    }

    /// `GET /authz/flags`, optionally carrying a one-time manager approval.
    /// The server scopes an approval-opened pull to this session's own branch;
    /// the local filter below stays as the second belt.
    async fn pull_flags(&self, approval: Option<&ApprovalView>) -> Result<u32, CoreError> {
        let query: Vec<(&str, String)> = match approval {
            Some(a) => vec![("approval", approval_wire(a).to_string())],
            None => Vec::new(),
        };
        // Retried once on a dropped connection, exactly like [`Self::bulk_review`]:
        // an idle keep-alive socket the server closed must not read as "this
        // till may not see its flags".
        let body = match self.api.get_text("/authz/flags", &query).await {
            Err(e) if crate::net::is_connectivity_failure(&e) => {
                self.api.get_text("/authz/flags", &query).await?
            }
            other => other?,
        };
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

        // One approval for the flag half, minted from the SAME PIN: it is what
        // lets a till signed in as a teller both pull and clear its own flags.
        // `None` here is not an error — a manager signed in at the till holds
        // `approvals.review` outright (and cannot approve for themselves), so
        // the calls below simply go out plain, exactly as they used to.
        let review_approval = self
            .approve_request_for(
                approver_pin.clone(),
                &request(Cap::ApprovalsReview, None, None, Some(false)),
                None,
            )
            .ok();
        if let Some(a) = review_approval.as_ref() {
            // Best-effort: a stale cache must not block the batch, and the
            // server answers for its own branch scoping either way.
            let _ = self.pull_flags(Some(a)).await;
        }

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
            let actor = (!item.person_id.is_empty()).then(|| item.person_id.clone());
            let approval = match self.approve_request_for(approver_pin.clone(), &req, actor.as_deref())
            {
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
            let mut body = serde_json::json!({ "flag_ids": flag_ids, "note": note });
            if let (Some(a), Some(map)) = (review_approval.as_ref(), body.as_object_mut()) {
                map.insert("approval".into(), approval_wire(a));
            }
            // A failure here must not lose the refusals already re-queued: the
            // flags stay listed with the server's own words, and the re-sent
            // ops keep their approval. Since 2026-09-18 the endpoint also takes
            // the one-time approval above, so a till signed in as a TELLER gets
            // through; a 403 here now means the APPROVER does not hold
            // `approvals.review`, and the server's own words say so.
            let parsed: Value = match self.bulk_review(&body).await {
                Ok(resp) => serde_json::from_str(&resp).unwrap_or_default(),
                Err(e) => {
                    let why = server_words(&e);
                    for item in flag_items.drain(..) {
                        left.push(with_why(item, why.clone()));
                    }
                    Value::Null
                }
            };
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

    /// `POST /authz/flags/bulk-review`, retried once on a dropped connection.
    /// The endpoint is idempotent by design, so a second attempt can only ever
    /// resolve the same ids — and an idle keep-alive connection closed by the
    /// server must not read as "the manager could not clear these".
    async fn bulk_review(&self, body: &Value) -> Result<String, CoreError> {
        match self.api.post_json("/authz/flags/bulk-review", body).await {
            Err(e) if crate::net::is_connectivity_failure(&e) => {
                self.api.post_json("/authz/flags/bulk-review", body).await
            }
            other => other,
        }
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

/// The server's own words for a failed call, so the till repeats them rather
/// than inventing a reason of its own.
fn server_words(e: &CoreError) -> String {
    match e {
        CoreError::Forbidden { action, .. } => action.clone(),
        other => other.to_string(),
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
