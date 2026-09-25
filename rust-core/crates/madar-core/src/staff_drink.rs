//! Recording a staff drink from the till (capability `orders.staff_drink.record`).
//!
//! [`crate::staff_pool`] holds the RULE and is the only place that decides
//! anything; this module is the vertical around it — where the settings come
//! from, where the count comes from, what is written, and what is sent.
//!
//! ## The count, and the three ways it converges
//!
//! The pool is a BRANCH's day, so the number a teller sees has to be the
//! branch's number, not this tablet's. It is taken from
//! [`crate::ledger::staff_drinks`] over `(branch_id, business_date)`, and that
//! table is filled from three directions:
//!
//! * this device rings one — the row and its outbox op commit together, so the
//!   count is right the instant the sheet closes, with or without a network;
//! * a peer on the counter rings one — the drink is published over the LAN and
//!   applied here at once, so two tills at one bar cannot both spend the last
//!   drink of the day;
//! * the cloud feed brings one — `/sync/pull`'s branch-scoped `staff_drink`
//!   type, which is how a till that was asleep, or on another network, catches
//!   up with everything it missed.
//!
//! All three write the SAME row under the client-minted id, so a drink that
//! arrives twice (LAN now, cloud later) is counted once.
//!
//! ## The reset is not a job
//!
//! Nothing resets the pool. The count is taken over the branch-local business
//! date, so when the branch turns the page the query simply finds no rows on
//! the new date. A tablet left on over the boundary is right the next time it
//! reads, and a tablet that was off is right when it wakes.
//!
//! ## Refusing, and not refusing
//!
//! The one refusal this path adds to the engine's is the same one the database
//! makes at the far end: a blank note is not a note. An OVERSPEND is never
//! refused here — the drink was made and the sale was rung — it is recorded
//! with its flag and the server re-counts and keeps its own verdict.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::approvals::{ActDecisionView, ApprovalView};
use crate::error::CoreError;
use crate::ledger::staff_drinks::{self, T_STAFF_DRINK};
use crate::staff_pool::{self, StaffDrinkDecision, StaffPoolDay, StaffPoolSettings};
use crate::{store, MadarCore};

pub const CAP_STAFF_DRINK: &str = "orders.staff_drink.record";

/// What the person has picked: the cart line, and their words.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq, Default)]
pub struct StaffDrinkInput {
    pub menu_item_id: String,
    pub size_label: Option<String>,
    /// How many of it. Below 1 is read as 1.
    pub quantity: i32,
    /// REQUIRED. Who it is for, in the teller's own words.
    pub note: String,
    /// The zero-priced sale it rang as, when there is one.
    pub order_id: Option<String>,
    /// The cart line being asked about, when it is ALREADY marked (the sheet
    /// reopened from its badge): its own units are then not counted twice.
    pub line_key: Option<String>,
}

/// The branch's pool as this device holds it today.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StaffPoolTodayView {
    /// The pool is usable at all: switched on AND with something on its list.
    pub on: bool,
    pub pool: StaffPoolDay,
    /// The items that count, so a cart line can be matched without a read.
    pub eligible_item_ids: Vec<String>,
    /// "3 left today" / "Nothing left today" / "2 over today's allowance",
    /// already in the till's language.
    pub pool_label: String,
    /// When the pool starts again, in the till's language.
    pub resets_label: String,
}

/// The verdict on a drink BEFORE it is committed, with everything the sheet
/// needs already worded — the UI decides nothing.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct StaffDrinkPreviewView {
    /// The action belongs on this line at all: the pool is on, the item is on
    /// its list, and this person may act or may ask a manager. A hidden action
    /// is hidden, not greyed — there is nothing to explain about a pool the
    /// branch never switched on.
    pub offered: bool,
    /// `allow` / `needs_approval` / `deny` for the signed-in person.
    pub access: ActDecisionView,
    pub decision: StaffDrinkDecision,
    /// The engine's refusal, translated. Empty when there is none.
    pub reason: String,
    /// The over-allowance copy, translated. Empty when inside the allowance.
    /// A drink carrying this is still recordable, deliberately.
    pub over_warning: String,
    pub pool_label: String,
}

/// What was written, for the toast and for the line's badge.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StaffDrinkRecordedView {
    pub id: String,
    pub item_name: String,
    pub quantity: i32,
    pub overspent: bool,
    /// The pool after it.
    pub pool: StaffPoolDay,
    /// The confirmation, translated.
    pub message: String,
}

/// The outbox payload.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct StaffDrinkCommand {
    pub request: Value,
    #[serde(default)]
    pub approval: Option<Value>,
}

/// The settings out of the branch's synced row, forgivingly: a backend that
/// has never heard of the pool, a null field and a half-written object all
/// mean the same safe thing — the pool is off.
pub fn settings_from_value(v: Option<&Value>) -> StaffPoolSettings {
    let Some(v) = v.filter(|v| v.is_object()) else { return StaffPoolSettings::default() };
    StaffPoolSettings {
        enabled: v.get("enabled").and_then(Value::as_bool).unwrap_or(false),
        daily_allowance: v.get("daily_allowance").and_then(Value::as_i64).unwrap_or(0).clamp(0, i32::MAX as i64) as i32,
        eligible_item_ids: v
            .get("eligible_item_ids")
            .and_then(Value::as_array)
            .map(|a| a.iter().filter_map(Value::as_str).map(str::to_string).collect())
            .unwrap_or_default(),
    }
}

/// The `/sync/replay` envelope for a queued drink, `recorded_at` re-based by
/// the fresh clock skew exactly as a queued sale's timestamp is: a till whose
/// clock is an hour fast must not file today's drink on tomorrow's pool.
pub(crate) fn replay_envelope(payload: &str, teller_id: &str, delta_ms: i64) -> Result<Value, String> {
    let mut p: Value = serde_json::from_str(payload).map_err(|e| e.to_string())?;
    let mut request = p.get_mut("request").map(Value::take).ok_or("no request")?;
    if delta_ms != 0 {
        if let Some(at) = request
            .get("recorded_at")
            .and_then(Value::as_str)
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
        {
            request["recorded_at"] = json!((at + chrono::Duration::milliseconds(delta_ms)).to_rfc3339());
        }
    }
    let mut env = json!({ "op": T_STAFF_DRINK, "teller_id": teller_id, "request": request });
    if let Some(a) = p.get("approval").filter(|a| !a.is_null()) {
        env["approval"] = a.clone();
    }
    Ok(env)
}

impl MadarCore {
    /// The branch's effective staff-pool settings, from the synced
    /// `branch_settings` row — the same place the loyalty programme, the
    /// routing mode and the tax policy come from. No network, ever: a pool the
    /// device has never heard of is a pool that is off, which errs towards
    /// offering nothing rather than a control that fails.
    pub fn staff_pool_settings(&self) -> Result<StaffPoolSettings, CoreError> {
        let src = self.branch_field::<Value>(crate::branch_reads::F_STAFF_POOL)?;
        Ok(settings_from_value(src.value().as_ref()))
    }

    /// The branch-local business date the pool is being spent on right now.
    fn staff_pool_date(&self) -> String {
        staff_pool::business_date_of(crate::timefmt::branch_tz(&self.store), self.corrected_now())
    }

    /// Drinks this branch has already recorded today, as this device knows it:
    /// its own, its LAN peers', and whatever the cloud feed has brought.
    fn staff_drinks_used(&self, branch: &str, date: &str) -> i32 {
        self.store.with_conn(|c| staff_drinks::used_on(c, branch, date)).unwrap_or(0)
    }

    fn pool_label(&self, pool: &StaffPoolDay) -> String {
        let locale = self.current_locale();
        let n = |k: &str, v: i32| crate::i18n::tr(&locale, k).replace("{count}", &v.to_string());
        if pool.over > 0 {
            n("staff_pool.over_today", pool.over)
        } else if pool.remaining == 0 {
            crate::i18n::tr(&locale, "staff_pool.none_left")
        } else {
            n("staff_pool.left_today", pool.remaining)
        }
    }

    /// The pool as it stands for the branch's business day. Purely local.
    pub fn staff_pool_today(&self) -> Result<StaffPoolTodayView, CoreError> {
        let branch = self.session_branch_id()?;
        let settings = self.staff_pool_settings()?;
        let date = self.staff_pool_date();
        let pool = staff_pool::pool_state(&date, settings.daily_allowance, self.staff_drinks_used(&branch, &date));
        Ok(StaffPoolTodayView {
            on: settings.enabled && !settings.eligible_item_ids.is_empty(),
            pool_label: self.pool_label(&pool),
            resets_label: crate::i18n::tr(&self.current_locale(), "staff_pool.resets"),
            pool,
            eligible_item_ids: settings.eligible_item_ids,
        })
    }

    /// Whether the person may put a drink on the pool, or may ask a manager to
    /// unlock it. `deny` hides the action; the capability carries
    /// `approval = true`, so a teller without the grant is never simply stuck.
    pub fn staff_drink_access(&self) -> ActDecisionView {
        self.decide_act(CAP_STAFF_DRINK.to_string(), None, None, None)
    }

    /// The action is offered on this line at all (the button's visibility).
    pub fn can_record_staff_drink(&self) -> bool {
        self.can(CAP_STAFF_DRINK.to_string()) || self.staff_drink_access().outcome != "deny"
    }

    /// The verdict on a drink before committing it — what the sheet shows: the
    /// refusal, or the over-allowance warning, with the pool either way.
    pub fn preview_staff_drink(&self, input: StaffDrinkInput) -> Result<StaffDrinkPreviewView, CoreError> {
        let branch = self.session_branch_id()?;
        let settings = self.staff_pool_settings()?;
        let date = self.staff_pool_date();
        // Drinks already MARKED in the counter's cart are as good as spent: two
        // marked lines in one cart must not both claim the last drink of the
        // day. The line being asked about is not counted against itself.
        let used = self.staff_drinks_used(&branch, &date)
            + self.staff_units_marked_in_cart(input.line_key.as_deref());
        let decision = staff_pool::decide(&settings, &date, &input.menu_item_id, &input.note, used);
        let access = self.staff_drink_access();
        let locale = self.current_locale();
        // Hidden only for the things that can never be fixed on this sheet: a
        // pool that is off, an item off the list, or no grant and no manager.
        // A missing note is not one of them — writing it is the whole point.
        let offered = access.outcome != "deny"
            && !matches!(
                decision.refusal,
                Some(staff_pool::StaffDrinkRefusal::PoolOff)
                    | Some(staff_pool::StaffDrinkRefusal::NoEligibleItems)
                    | Some(staff_pool::StaffDrinkRefusal::ItemNotEligible)
            );
        Ok(StaffDrinkPreviewView {
            offered,
            access,
            reason: decision.refusal.map(|r| crate::i18n::tr(&locale, r.key())).unwrap_or_default(),
            over_warning: if decision.overspent {
                crate::i18n::tr(&locale, "staff_pool.over_warning")
            } else {
                String::new()
            },
            pool_label: self.pool_label(&decision.pool),
            decision,
        })
    }

    /// A manager unlocks this act for the signed-in person with their PIN.
    pub fn approve_staff_drink(&self, approver_pin: String) -> Result<ApprovalView, CoreError> {
        self.approve_act(approver_pin, CAP_STAFF_DRINK.to_string(), None, None, None)
    }

    /// Put the drink on the branch's pool. Offline: the row and its outbox op
    /// commit in ONE transaction, the LAN peers hear it, and the drain replays
    /// it whenever the network comes back.
    pub async fn record_staff_drink(
        &self,
        input: StaffDrinkInput,
        approval: Option<ApprovalView>,
    ) -> Result<StaffDrinkRecordedView, CoreError> {
        let locale = self.current_locale();
        let decision = self.staff_drink_access();
        let approval = match decision.outcome.as_str() {
            "allow" => None,
            "needs_approval" => match approval {
                Some(a) if a.capability == CAP_STAFF_DRINK => Some(a),
                _ => return Err(CoreError::Forbidden { resource: "approval".into(), action: decision.reason }),
            },
            _ => return Err(CoreError::Forbidden { resource: "staff_drink".into(), action: decision.reason }),
        };

        let branch = self.session_branch_id()?;
        let settings = self.staff_pool_settings()?;
        let date = self.staff_pool_date();
        let used = self.staff_drinks_used(&branch, &date);
        let quantity = input.quantity.max(1);
        let verdict = staff_pool::decide(&settings, &date, &input.menu_item_id, &input.note, used);
        if let Some(r) = verdict.refusal {
            // The blank note is the refusal the database itself makes at the far
            // end; the rest are the engine's, and every one of them is a thing
            // the teller can be told plainly.
            return Err(CoreError::Validation {
                field: if r == staff_pool::StaffDrinkRefusal::NoteRequired { "note".into() } else { "item".into() },
                detail: crate::i18n::tr(&locale, r.key()),
            });
        }

        let id = uuid::Uuid::new_v4().to_string();
        let now = self.corrected_now().to_rfc3339();
        let device_id = self.lan_device_id();
        let till_id = self.current_till().ok().flatten().filter(|t| t.is_open).map(|t| t.id);
        // Frozen here, so a rename or a retirement later never rewrites what
        // the teller actually gave away.
        let item_name = self
            .list_menu_items()
            .unwrap_or_default()
            .into_iter()
            .find(|m| m.id == input.menu_item_id)
            .map(|m| m.name)
            .unwrap_or_default();
        let note = input.note.trim().to_string();
        let request = json!({
            "id": id,
            "branch_id": branch,
            "till_id": till_id,
            "order_id": input.order_id,
            "menu_item_id": input.menu_item_id,
            "item_name": item_name,
            "size_label": input.size_label,
            "quantity": quantity,
            "note": note,
            "allowance_at_record": settings.daily_allowance,
            "used_before": used,
            "overspent": verdict.overspent,
            "device_id": device_id,
            "recorded_at": now,
        });
        // The local row is the request plus the one field only this side knows:
        // the business date the engine decided on. The server derives the same
        // date from `recorded_at` in the branch's timezone, so the row the feed
        // brings back lands on exactly the day this one is already counted on.
        let mut row = request.clone();
        row["business_date"] = json!(date);
        row["overspent_on_replay"] = json!(false);

        let cmd = StaffDrinkCommand {
            request: request.clone(),
            approval: approval.as_ref().map(crate::approvals::approval_wire),
        };
        let (user_id, clock_offset_ms) = self.outbox_meta();
        let op = store::NewOutboxOp {
            id: format!("staff_drink:{id}"),
            op_type: T_STAFF_DRINK.into(),
            idempotency_key: format!("staff_drink:{id}"),
            payload: serde_json::to_string(&cmd)?,
            event_at: now,
            depends_on_seq: None,
            user_id,
            clock_offset_ms,
            till_id,
            device_id: Some(device_id),
            entity_type: Some(T_STAFF_DRINK.into()),
            entity_id: Some(id.clone()),
        };
        self.store.with_tx_touch(|tx, touched| {
            staff_drinks::commit(tx, &op, &row)?;
            touched.extend(crate::changes::tables_for_op(T_STAFF_DRINK));
            Ok(())
        })?;
        // The counter's other till must not be able to spend the same drink,
        // so the peers hear it before the cloud does. Through `lan_publish`,
        // never the relay: only that writes `lan_log`, and without the log a
        // tablet that joins a minute later never catches up on this drink.
        let envelope = replay_envelope(&op.payload, user_id_of(&op), 0).unwrap_or(Value::Null);
        if !envelope.is_null() {
            self.lan_publish("orders", "staff_drink.recorded", row.to_string(), Some(envelope.to_string())).await;
        }
        self.send_in_background(Vec::new());

        Ok(StaffDrinkRecordedView {
            id,
            item_name,
            quantity,
            overspent: verdict.overspent,
            pool: verdict.pool,
            message: crate::i18n::tr(&locale, "staff_pool.recorded"),
        })
    }

    /// Today's drinks, newest last — the sheet's short list and the proof the
    /// count is not a guess.
    pub fn staff_drinks_today(&self) -> Result<Vec<StaffDrinkLineView>, CoreError> {
        let branch = self.session_branch_id()?;
        let date = self.staff_pool_date();
        Ok(self
            .store
            .with_conn(|c| staff_drinks::for_day(c, &branch, &date))?
            .into_iter()
            .map(|r| StaffDrinkLineView {
                id: r.id,
                item_name: r.item_name,
                size_label: r.size_label,
                quantity: r.quantity,
                note: r.note,
                overspent: r.overspent,
                recorded_at: r.recorded_at,
                queued: r.queued,
                comp_minor: r.comp_minor,
                extras_minor: r.extras_minor,
            })
            .collect())
    }
}

// ── a cart line MARKED as a staff drink (owner rule 2026-09-21) ──────────────
//
// Saving the sheet no longer spends anything: it MARKS the cart line. The mark
// (a client-minted drink id, the note, the approval if one was needed) rides
// the stored line, so it survives a restart; the line is priced by the comp
// rule (`staff_comp.rs`) through the bill engine at once; and the pool entry is
// written when the order is CHARGED, in the sale's own transaction — an
// abandoned cart never burns the allowance.
//
// Only the COUNTER's cart carries marks. A table's bill is priced when a round
// is fired and settled hours later; the backend refuses a pooled line on a
// ticket (`staff_drink_not_on_ticket`), so a cart in a table's context is never
// offered the action and a marked cart that becomes a table's loses its marks.

/// kv key — reasons marks were dropped by themselves, waiting for the host to
/// toast them (JSON array of translated strings).
const K_STAFF_NOTICES: &str = "cart:staff_notices";

fn old_server_key(order: &str) -> String {
    format!("staff_old_server:{order}")
}

impl MadarCore {
    /// Units already marked in the counter's cart, not counting `except`.
    fn staff_units_marked_in_cart(&self, except: Option<&str>) -> i32 {
        crate::cart::staff_marked(&self.store, None)
            .unwrap_or_default()
            .iter()
            .filter(|m| Some(m.key.as_str()) != except)
            .map(|m| m.qty.clamp(0, i32::MAX as i64) as i32)
            .sum()
    }

    /// Re-decide every mark of a cart: recompute each comp from the catalogue
    /// as it stands now, and DROP a mark whose line stopped being eligible (an
    /// item a settings sync took off the list, a pool switched off, a cart
    /// that belongs to a table). Dropped marks are remembered for
    /// [`Self::take_staff_drink_notices`]. Cheap when nothing is marked.
    pub(crate) fn refresh_staff_marks(&self, ctx: crate::cart::Ctx<'_>) -> Vec<String> {
        use crate::cart::StaffMarkDrop;
        if crate::cart::staff_marked(&self.store, ctx).map(|m| m.is_empty()).unwrap_or(true) {
            return Vec::new();
        }
        let dropped = if ctx.is_some() {
            crate::cart::strip_staff_marks(&self.store, ctx, StaffMarkDrop::TableBill)
        } else {
            let settings = self.staff_pool_settings().unwrap_or_default();
            let on = settings.enabled && !settings.eligible_item_ids.is_empty();
            let catalog = self.catalog().ok();
            crate::cart::set_staff_comps(&self.store, ctx, |line| {
                if !on || !settings.eligible_item_ids.iter().any(|i| i == line.item_id()) {
                    return Err(StaffMarkDrop::NotEligible);
                }
                let catalog = catalog.as_ref().ok_or(StaffMarkDrop::NotEligible)?;
                let item = catalog
                    .items
                    .iter()
                    .find(|i| i.id == line.item_id())
                    .ok_or(StaffMarkDrop::NotEligible)?;
                let unified = catalog
                    .unified
                    .as_ref()
                    .and_then(|doc| doc.groups_for(line.item_id()));
                let input = line.comp_input(
                    item,
                    &catalog.addons,
                    &catalog.pricing,
                    unified.as_deref(),
                    true,
                );
                Ok(crate::staff_comp::comp(&input).free_per_unit as i64)
            })
        }
        .unwrap_or_default();
        self.note_staff_drops(ctx, dropped)
    }

    /// Word the dropped marks and keep them for the host's toast.
    pub(crate) fn note_staff_drops(
        &self,
        _ctx: crate::cart::Ctx<'_>,
        dropped: Vec<(String, crate::cart::StaffMarkDrop)>,
    ) -> Vec<String> {
        if dropped.is_empty() {
            return Vec::new();
        }
        let locale = self.current_locale();
        let said: Vec<String> = dropped
            .iter()
            .map(|(name, why)| crate::i18n::tr(&locale, why.key()).replace("{item}", name))
            .collect();
        let mut kept: Vec<String> = self
            .store
            .kv_get(K_STAFF_NOTICES)
            .ok()
            .flatten()
            .and_then(|j| serde_json::from_str(&j).ok())
            .unwrap_or_default();
        kept.extend(said.iter().cloned());
        let _ = self.store.kv_put(K_STAFF_NOTICES, &serde_json::to_string(&kept).unwrap_or_default());
        said
    }

    /// Why marks left their lines since the host last asked — each already a
    /// sentence in the till's language. Re-checks the cart first, so a settings
    /// sync that took an item off the list is caught the next time the cart is
    /// looked at. Draining: a reason is handed over once.
    pub fn take_staff_drink_notices(&self, table_id: Option<String>) -> Vec<String> {
        let _ = self.refresh_staff_marks(table_id.as_deref());
        let kept: Vec<String> = self
            .store
            .kv_get(K_STAFF_NOTICES)
            .ok()
            .flatten()
            .and_then(|j| serde_json::from_str(&j).ok())
            .unwrap_or_default();
        if !kept.is_empty() {
            let _ = self.store.kv_put(K_STAFF_NOTICES, "[]");
        }
        kept
    }

    /// MARK a cart line as a staff drink. The note is REQUIRED; the pool must
    /// allow the item; the person must hold the act or bring a manager's
    /// approval; the cart must be the counter's. Nothing is spent — the pool
    /// entry is written when the order is charged. Returns the cart's lines
    /// (the marked line has a new key).
    pub fn mark_staff_drink(
        &self,
        table_id: Option<String>,
        line_key: String,
        note: String,
        approval: Option<ApprovalView>,
    ) -> Result<Vec<crate::cart::CartLineView>, CoreError> {
        let locale = self.current_locale();
        if table_id.is_some() {
            return Err(CoreError::Validation {
                field: "table".into(),
                detail: crate::i18n::tr(&locale, "staff_pool.refused.table"),
            });
        }
        let access = self.staff_drink_access();
        let approval = match access.outcome.as_str() {
            "allow" => None,
            "needs_approval" => match approval {
                Some(a) if a.capability == CAP_STAFF_DRINK => Some(a),
                _ => return Err(CoreError::Forbidden { resource: "approval".into(), action: access.reason }),
            },
            _ => return Err(CoreError::Forbidden { resource: "staff_drink".into(), action: access.reason }),
        };
        let lines = crate::cart::lines(&self.store, None)?;
        let line = lines.iter().find(|l| l.key == line_key).ok_or_else(|| CoreError::Validation {
            field: "line".into(),
            detail: "that line is no longer in the cart".into(),
        })?;
        // C15: never a combo, never a line in a deal — said as such, before
        // the pool's list is asked about an item that could never be on it.
        let closed = if line.kind == crate::menu::KIND_COMBO {
            Some("combo.staff_drink")
        } else if line.deal_cut_minor > 0 {
            Some("deal.staff_drink")
        } else {
            None
        };
        if let Some(key) = closed {
            return Err(CoreError::Validation {
                field: String::new(),
                detail: crate::i18n::tr(&locale, key),
            });
        }
        let branch = self.session_branch_id()?;
        let settings = self.staff_pool_settings()?;
        let date = self.staff_pool_date();
        let used = self.staff_drinks_used(&branch, &date) + self.staff_units_marked_in_cart(Some(&line_key));
        let verdict = staff_pool::decide(&settings, &date, &line.item_id, &note, used);
        if let Some(r) = verdict.refusal {
            return Err(CoreError::Validation {
                field: if r == staff_pool::StaffDrinkRefusal::NoteRequired { "note".into() } else { "item".into() },
                detail: crate::i18n::tr(&locale, r.key()),
            });
        }
        // Re-marking a marked line keeps its drink id (it is one drink).
        let id = line.staff_drink.as_ref().map(|m| m.id.clone()).unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
        let _guard = self.cart_ops.lock().unwrap_or_else(|e| e.into_inner());
        crate::cart::mark_staff(
            &self.store,
            None,
            &line_key,
            crate::cart::StoredStaffMark { id, note: note.trim().to_string(), approval, free_per_unit_minor: 0 },
        )?;
        drop(_guard);
        // Priced at once, by the rule, from the catalogue.
        self.refresh_staff_marks(None);
        crate::cart::lines(&self.store, None)
    }

    /// Change a marked line's note. A blank note is refused: the note is the
    /// only record of who drank it.
    pub fn edit_staff_drink_note(
        &self,
        table_id: Option<String>,
        line_key: String,
        note: String,
    ) -> Result<Vec<crate::cart::CartLineView>, CoreError> {
        if !staff_pool::note_is_given(&note) {
            return Err(CoreError::Validation {
                field: "note".into(),
                detail: crate::i18n::tr(&self.current_locale(), staff_pool::StaffDrinkRefusal::NoteRequired.key()),
            });
        }
        let _guard = self.cart_ops.lock().unwrap_or_else(|e| e.into_inner());
        crate::cart::set_staff_note(&self.store, table_id.as_deref(), &line_key, &note)?;
        crate::cart::lines(&self.store, table_id.as_deref())
    }

    /// Take the mark off: the line rings at its normal price again.
    pub fn unmark_staff_drink(
        &self,
        table_id: Option<String>,
        line_key: String,
    ) -> Result<Vec<crate::cart::CartLineView>, CoreError> {
        let _guard = self.cart_ops.lock().unwrap_or_else(|e| e.into_inner());
        crate::cart::unmark_staff(&self.store, table_id.as_deref(), &line_key)
    }

    /// The cart is about to become (part of) a table's BILL — a round is being
    /// fired, or the host aimed it at a table or an open ticket. Every mark
    /// goes, and the reasons come back already worded (they are also kept for
    /// [`Self::take_staff_drink_notices`]).
    pub fn drop_staff_marks_for_bill(&self, table_id: Option<String>) -> Vec<String> {
        let ctx = table_id.as_deref();
        let dropped = crate::cart::strip_staff_marks(&self.store, ctx, crate::cart::StaffMarkDrop::TableBill)
            .unwrap_or_default();
        self.note_staff_drops(ctx, dropped)
    }

    /// The cart's staff drinks as the Charge sheet states them: the comp as a
    /// discount, and what those lines still pay. `None` without one. Local.
    pub fn cart_staff_summary(&self, table_id: Option<String>) -> Option<crate::cart::CartStaffSummary> {
        crate::cart::staff_summary(&self.store, table_id.as_deref()).ok().flatten()
    }

    /// Decide each staff line of a prepared sale against the pool, in cart
    /// order (each one counts the ones before it), stamp `overspent` on the
    /// wire, and build the ledger rows the sale commits with. Returns the rows
    /// and the pool as it stands after the last one.
    pub(crate) fn settle_staff_lines(
        &self,
        prepared: &mut crate::checkout::Prepared,
        till_id: &str,
    ) -> Result<(Vec<Value>, Option<StaffPoolDay>), CoreError> {
        if prepared.staff_lines.is_empty() {
            return Ok((Vec::new(), None));
        }
        let branch = self.session_branch_id()?;
        let settings = self.staff_pool_settings()?;
        let date = self.staff_pool_date();
        let mut used = self.staff_drinks_used(&branch, &date);
        let device_id = self.lan_device_id();
        let mut rows = Vec::new();
        let mut pool = None;
        for s in &prepared.staff_lines {
            let verdict = staff_pool::decide(&settings, &date, &s.menu_item_id, &s.note, used);
            let quantity = s.quantity.clamp(1, i32::MAX as i64) as i32;
            if let Some(Some(sd)) = prepared
                .command
                .request
                .items
                .get_mut(s.item_index)
                .map(|i| i.staff_drink.as_mut().and_then(|o| o.as_mut()))
            {
                sd.overspent = Some(Some(verdict.overspent));
            }
            rows.push(json!({
                "id": s.id,
                "branch_id": branch,
                "till_id": till_id,
                "order_id": prepared.order_id.to_string(),
                "menu_item_id": s.menu_item_id,
                "item_name": s.item_name,
                "size_label": s.size_label,
                "quantity": quantity,
                "note": s.note.trim(),
                "allowance_at_record": settings.daily_allowance,
                "used_before": used,
                "overspent": verdict.overspent,
                "overspent_on_replay": false,
                "comp_minor": s.comp_minor,
                "extras_minor": s.extras_minor,
                "device_id": device_id,
                "recorded_at": prepared.event_at,
                "business_date": date,
            }));
            used += quantity;
            pool = Some(staff_pool::pool_state(&date, settings.daily_allowance, used));
        }
        Ok((rows, pool))
    }

    /// "Staff drinks: 3 left today" / "… 2 over today's allowance" — the done
    /// card's line after a sale that carried one.
    pub(crate) fn staff_done_label(&self, pool: &StaffPoolDay) -> String {
        let locale = self.current_locale();
        let n = |k: &str, v: i32| crate::i18n::tr(&locale, k).replace("{count}", &v.to_string());
        if pool.over > 0 {
            n("staff_pool.done_over", pool.over)
        } else if pool.remaining == 0 {
            crate::i18n::tr(&locale, "staff_pool.done_none_left")
        } else {
            n("staff_pool.done_left", pool.remaining)
        }
    }

    /// The server answered a sale that carried staff drinks.
    ///
    /// * A server that speaks the contract names each pooled line
    ///   (`staff_drink_id`) with the comp IT stored (`staff_comp_minor`): the
    ///   drink's local row adopts those figures, so the till and the server
    ///   never disagree on a synced sale. (The sale's own row adopts the
    ///   server's totals through the ordinary ack fold.)
    /// * A server that PREDATES the contract ignores the line field: no line
    ///   of its answer carries `staff_comp_minor`. The sale is kept exactly as
    ///   that server priced it, each drink is recorded on the pool through the
    ///   record-only op it does understand (same id, so nothing is counted
    ///   twice later), and the teller is told plainly.
    pub(crate) fn staff_drinks_acked(&self, item: &store::OutboxItem, ack: &Value) {
        let Ok(cmd) = serde_json::from_str::<crate::checkout::CheckoutCommand>(&item.payload) else { return };
        let drinks: Vec<(usize, String)> = cmd
            .request
            .items
            .iter()
            .enumerate()
            .filter_map(|(i, it)| Some((i, it.staff_drink.clone().flatten()?.id.to_string())))
            .collect();
        if drinks.is_empty() {
            return;
        }
        let Some(lines) = ack.get("items").and_then(Value::as_array).filter(|l| !l.is_empty()) else {
            // No body to read (an idempotent ack): the feed reconciles it.
            return;
        };
        let server_order = ack.get("id").and_then(Value::as_str).unwrap_or(&item.id).to_string();
        let speaks_contract = lines.iter().any(|l| l.get("staff_comp_minor").is_some());
        if speaks_contract {
            for (_, id) in &drinks {
                let Some(line) = lines.iter().find(|l| l.get("staff_drink_id").and_then(Value::as_str) == Some(id)) else {
                    continue;
                };
                let comp = line.get("staff_comp_minor").and_then(Value::as_i64).unwrap_or(0);
                let _ = self.store.with_tx_touch(|tx, touched| {
                    if let Some(mut row) = staff_drinks::raw(tx, id)? {
                        let rang = row.get("comp_minor").and_then(Value::as_i64).unwrap_or(0)
                            + row.get("extras_minor").and_then(Value::as_i64).unwrap_or(0);
                        row["comp_minor"] = json!(comp);
                        row["extras_minor"] = json!((rang - comp).max(0));
                        row["order_id"] = json!(server_order);
                        staff_drinks::upsert(tx, &row, "local")?;
                        touched.extend(crate::changes::tables_for_op(T_STAFF_DRINK));
                    }
                    Ok(())
                });
            }
            return;
        }
        // OLD SERVER. Never lose the sale, never lose the drink.
        for (_, id) in &drinks {
            let Ok(Some(mut row)) = self.store.with_conn(|c| staff_drinks::raw(c, id)) else { continue };
            row["order_id"] = json!(server_order);
            // That server comped nothing it knows of; the record-only drink
            // carries no money (`comp_minor = null`, contract §2 "Unchanged").
            let mut request = row.clone();
            if let Some(o) = request.as_object_mut() {
                for k in ["business_date", "overspent_on_replay", "comp_minor", "extras_minor"] {
                    o.remove(k);
                }
            }
            let payload = serde_json::to_string(&StaffDrinkCommand {
                request,
                approval: cmd.approval.clone().filter(|a| {
                    a.get("capability").and_then(Value::as_str) == Some(CAP_STAFF_DRINK)
                }),
            })
            .unwrap_or_default();
            let op = store::NewOutboxOp {
                id: format!("staff_drink:{id}"),
                op_type: T_STAFF_DRINK.into(),
                idempotency_key: format!("staff_drink:{id}"),
                payload,
                event_at: row.get("recorded_at").and_then(Value::as_str).unwrap_or(&item.event_at).to_string(),
                depends_on_seq: None,
                user_id: item.user_id.clone(),
                clock_offset_ms: item.clock_offset_ms,
                till_id: item.till_id.clone(),
                device_id: Some(self.lan_device_id()),
                entity_type: Some(T_STAFF_DRINK.into()),
                entity_id: Some(id.clone()),
            };
            let _ = self.store.with_tx_touch(|tx, touched| {
                staff_drinks::commit(tx, &op, &row)?;
                touched.extend(crate::changes::tables_for_op(T_STAFF_DRINK));
                Ok(())
            });
        }
        let _ = self.store.kv_put(&old_server_key(&item.id), "1");
        let _ = self.store.kv_put(&old_server_key(&server_order), "1");
        self.push_diag("warn", "this server does not price staff drinks: recorded on the pool the old way");
    }

    /// The teller-facing sentence when `order` (client key or server id) was
    /// answered by a server that does not support free staff drinks.
    pub fn staff_old_server_notice(&self, order: String) -> Option<String> {
        self.store
            .kv_get(&old_server_key(&order))
            .ok()
            .flatten()
            .filter(|s| !s.is_empty())
            .map(|_| crate::i18n::tr(&self.current_locale(), "staff_pool.old_server"))
    }
}

/// One drink on today's list.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StaffDrinkLineView {
    pub id: String,
    pub item_name: String,
    pub size_label: Option<String>,
    pub quantity: i32,
    pub note: String,
    pub overspent: bool,
    pub recorded_at: String,
    /// Still in the outbox — the server has not counted it yet.
    pub queued: bool,
    /// What the pool comped on its line / what the line still paid. `None` on
    /// a record-only drink.
    pub comp_minor: Option<i64>,
    pub extras_minor: Option<i64>,
}

fn user_id_of(op: &store::NewOutboxOp) -> &str {
    op.user_id.as_deref().unwrap_or("")
}

/// Apply a drink a LAN peer published (its display payload IS the row).
pub(crate) fn apply_lan(store: &store::Store, data: &str) {
    let Ok(v) = serde_json::from_str::<Value>(data) else { return };
    let _ = store.with_tx_touch(|tx, touched| {
        staff_drinks::upsert(tx, &v, "peer")?;
        touched.extend(crate::changes::tables_for_op(T_STAFF_DRINK));
        Ok(())
    });
}

#[cfg(test)]
mod staff_pool_tests {
    use super::*;
    use crate::ledger::staff_drinks as rows;
    use crate::store::{NewOutboxOp, Store};

    const B: &str = "branch-1";
    const D: &str = "2026-09-19";

    fn drink(id: &str, day: &str, qty: i64) -> Value {
        json!({
            "id": id, "branch_id": B, "business_date": day, "quantity": qty,
            "item_name": "Latte", "note": "for Sara", "overspent": false,
            "recorded_at": format!("{day}T09:0{}:00Z", id.len() % 10),
        })
    }

    fn op(id: &str) -> NewOutboxOp {
        NewOutboxOp {
            id: format!("staff_drink:{id}"),
            op_type: T_STAFF_DRINK.into(),
            idempotency_key: format!("staff_drink:{id}"),
            payload: "{}".into(),
            event_at: "2026-09-19T09:00:00Z".into(),
            entity_type: Some(T_STAFF_DRINK.into()),
            entity_id: Some(id.to_string()),
            ..Default::default()
        }
    }

    #[test]
    fn staff_pool_counts_quantities_not_rows() {
        // The server counts `sum(quantity)`; a till that counted rows would
        // hand back a pool that is wrong the moment anyone rings two at once.
        let s = Store::open("").unwrap();
        s.with_conn(|c| {
            rows::upsert(c, &drink("a", D, 2), "local")?;
            rows::upsert(c, &drink("b", D, 1), "local")?;
            assert_eq!(rows::used_on(c, B, D)?, 3);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn staff_pool_resets_by_itself_at_the_next_business_date() {
        // Nothing runs at midnight. The count is taken over the date, so a new
        // business day simply has no rows on it — and yesterday's are still
        // there, which is what the owner's report reads.
        let s = Store::open("").unwrap();
        s.with_conn(|c| {
            for id in ["a", "b", "c"] {
                rows::upsert(c, &drink(id, D, 1), "local")?;
            }
            assert_eq!(rows::used_on(c, B, D)?, 3);
            assert_eq!(rows::used_on(c, B, "2026-09-20")?, 0, "the pool starts again");
            rows::upsert(c, &drink("d", "2026-09-20", 1), "local")?;
            assert_eq!(rows::used_on(c, B, "2026-09-20")?, 1);
            assert_eq!(rows::used_on(c, B, D)?, 3, "yesterday is not rewritten");
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn staff_pool_never_counts_another_branch() {
        let s = Store::open("").unwrap();
        s.with_conn(|c| {
            rows::upsert(c, &drink("a", D, 1), "local")?;
            let mut other = drink("z", D, 5);
            other["branch_id"] = json!("branch-2");
            rows::upsert(c, &other, "server")?;
            assert_eq!(rows::used_on(c, B, D)?, 1);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn staff_pool_counts_a_queued_drink_and_says_it_is_queued() {
        // The whole point of the local row: the count is right offline, before
        // the server has ever heard of the drink.
        let s = Store::open("").unwrap();
        s.with_tx_touch(|tx, _| {
            rows::commit(tx, &op("a"), &drink("a", D, 1))?;
            Ok(())
        })
        .unwrap();
        s.with_conn(|c| {
            assert_eq!(rows::used_on(c, B, D)?, 1);
            let list = rows::for_day(c, B, D)?;
            assert_eq!(list.len(), 1);
            assert!(list[0].queued, "still in the outbox");
            assert_eq!(list[0].note, "for Sara");
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn the_same_drink_from_lan_and_from_the_cloud_is_counted_once() {
        // A peer publishes it now and the feed brings it back an hour later.
        // One client-minted id, one row, one drink off the allowance.
        let s = Store::open("").unwrap();
        s.with_conn(|c| {
            rows::upsert(c, &drink("a", D, 1), "peer")?;
            rows::from_feed(c, &drink("a", D, 1))?;
            assert_eq!(rows::used_on(c, B, D)?, 1);
            assert_eq!(rows::for_day(c, B, D)?.len(), 1);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn a_queued_drink_is_not_overwritten_or_swept_by_the_feed() {
        // The row is PROTECTED while its op is live, exactly as a queued sale
        // is: the server has not seen this drink yet, and a snapshot that does
        // not list it must not make the till forget it spent one.
        let s = Store::open("").unwrap();
        s.with_tx_touch(|tx, _| {
            rows::commit(tx, &op("a"), &drink("a", D, 1))?;
            Ok(())
        })
        .unwrap();
        s.with_conn(|c| {
            let mut server = drink("a", D, 9);
            server["note"] = json!("rewritten by the server");
            rows::from_feed(c, &server)?;
            assert_eq!(rows::used_on(c, B, D)?, 1, "the teller's row stands");
            assert_eq!(rows::forget(c, "a")?, 0, "a live op holds it");
            assert_eq!(rows::used_on(c, B, D)?, 1);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn the_servers_version_lands_once_nothing_holds_the_row() {
        let s = Store::open("").unwrap();
        s.with_conn(|c| {
            rows::upsert(c, &drink("a", D, 1), "local")?;
            let mut server = drink("a", D, 2);
            server["overspent"] = json!(true);
            rows::from_feed(c, &server)?;
            assert_eq!(rows::used_on(c, B, D)?, 2, "the server recounted");
            assert!(rows::for_day(c, B, D)?[0].overspent);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn a_server_date_that_arrives_as_an_instant_still_names_one_day() {
        let s = Store::open("").unwrap();
        s.with_conn(|c| {
            let mut v = drink("a", D, 1);
            v["business_date"] = json!("2026-09-19T00:00:00Z");
            rows::upsert(c, &v, "server")?;
            assert_eq!(rows::used_on(c, B, D)?, 1);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn staff_pool_settings_read_forgivingly_and_default_to_off() {
        // A backend that has never heard of the pool, a null field and a
        // half-written object all mean the same safe thing.
        assert_eq!(settings_from_value(None), StaffPoolSettings::default());
        assert_eq!(settings_from_value(Some(&Value::Null)), StaffPoolSettings::default());
        assert_eq!(settings_from_value(Some(&json!({}))), StaffPoolSettings::default());
        let s = settings_from_value(Some(&json!({
            "enabled": true, "daily_allowance": 5, "eligible_item_ids": ["latte", "tea"]
        })));
        assert!(s.enabled);
        assert_eq!(s.daily_allowance, 5);
        assert_eq!(s.eligible_item_ids, vec!["latte".to_string(), "tea".to_string()]);
    }

    #[test]
    fn the_staff_pool_replay_envelope_is_the_op_the_server_expects() {
        let payload = json!({
            "request": { "id": "d1", "branch_id": B, "menu_item_id": "latte", "note": "n",
                         "recorded_at": "2026-09-19T09:00:00+00:00" },
            "approval": null
        })
        .to_string();
        let env = replay_envelope(&payload, "teller-7", 0).unwrap();
        assert_eq!(env["op"], "record_staff_drink");
        assert_eq!(env["teller_id"], "teller-7");
        assert_eq!(env["request"]["id"], "d1");
        assert!(env.get("approval").is_none(), "no approval, no key");
        assert_eq!(crate::lan_sync::op_key(&env).unwrap(), "record_staff_drink:d1");
    }

    #[test]
    fn a_skewed_clock_cannot_file_the_drink_on_the_wrong_day() {
        // The till's clock is an hour behind; the drain re-bases the stamp, and
        // the server derives the business day from THAT.
        let payload = json!({
            "request": { "id": "d1", "recorded_at": "2026-09-19T23:30:00+00:00" }
        })
        .to_string();
        let env = replay_envelope(&payload, "t", 3_600_000).unwrap();
        let at = env["request"]["recorded_at"].as_str().unwrap();
        assert!(at.starts_with("2026-09-20T00:30:00"), "got {at}");
    }
}
