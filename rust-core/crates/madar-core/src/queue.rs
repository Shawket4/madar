//! The device's queue across a teller switch (deferred feature 5).
//!
//! The queue is the work in progress a till holds that is not yet a sale: the
//! cart in hand (per context: the counter and each table) and every held
//! (parked) order in `held:mirror`.
//!
//! # Rules
//!
//! 1. **A teller switch keeps the counter queue.** A switch is the
//!    person-level sign-out ([`MadarCore::logout`], the PIN pad's "Sign out")
//!    followed by another person's PIN sign-in or offline unlock on the same
//!    device. The counter's cart in hand is PARKED as a held order under its
//!    author before the session goes (a cart that cannot be parked is left in
//!    place, still stamped with its author), and every held order stays in the
//!    mirror. The next person starts with an empty counter cart and the whole
//!    queue on the strip. No network: the park is the local mirror. Held orders
//!    also carry over from till to till; a till close warns about them first.
//! 2. **Ownership.** A held order keeps the person who started it
//!    (`created_by`), across re-parks by anyone. A cart resumed from a held
//!    order carries that author (`cart:owner`) until it is sold or parked
//!    again. An order with no recorded author (parked before this existed)
//!    reads as nobody's in particular and resumes like one's own.
//! 3. **Viewing** the queue is open to whoever is signed in: the strip lists
//!    every held order, and marks the ones someone else started with their
//!    name.
//! 4. **Resuming someone else's order** (restoring it to continue or settle
//!    it) asks for [`RESUME_CAP`], `orders.held.resume_others` (owner and
//!    manager by default). Without it the act needs a manager's PIN approval
//!    (the same approval sheet, `approve_draft_act`): the capability accepts
//!    approval, so "not held" reads as "ask a manager" here. Resuming one's
//!    own order asks for nothing new.
//! 4a. **Tables are nobody's.** A table's order is shared state: the open
//!    ticket, server-authoritative online and relayed over the LAN offline.
//!    Anyone holding the normal floor and order capabilities adds to it or
//!    settles it; `orders.held.resume_others` never applies to a table (a held
//!    order parked on a table resumes like one's own). A switch leaves nothing
//!    person-scoped on a table: an unsent table cart is emptied exactly as it
//!    was before this feature (the shared ticket holds what was sent).
//! 5. **Settling** a resumed order records BOTH people: the order is rung by
//!    the person signed in (`teller_id`, as always) and carries `started_by`
//!    (the author) plus the manager's approval, when one was needed, on the
//!    replay envelope. Both are additive: an older backend ignores them and an
//!    older queued payload still parses.
//! 6. **Discarding someone else's held order** follows `orders.void`: its
//!    `own` limit and its `max_age_minutes` (the order's age since it was
//!    started), with a manager's approval where the grant asks for one.
//!    Discarding one's own stays as free as it always was (no money moved).
//! 7. **Kept clean-state behaviour.** Reconfiguring the device (the org or
//!    branch switch, `start_reconfigure`) still wipes everything, the queue
//!    included. The till's open drawer is device state and stays, as before;
//!    the realtime stream, the bearer and the session are still torn down on
//!    every sign-out.

use madar_authz::{Cap, Decision, Why};

use crate::approvals::{self, ActDecisionView, ApprovalView};
use crate::cart;
use crate::error::CoreError;
use crate::held;
use crate::MadarCore;

/// The capability resuming (continuing, then settling) a held order asks for.
pub(crate) const RESUME_CAP: Cap = Cap::OrdersHeldResumeOthers;
/// The capability discarding someone else's held order asks for.
pub(crate) const DISCARD_CAP: Cap = Cap::OrdersVoid;

/// `true` when a known author is not `me` (an unknown author is nobody's).
pub(crate) fn started_by_other(created_by: Option<&str>, me: &str) -> bool {
    matches!(created_by, Some(a) if !a.is_empty() && a != me)
}

/// What a queue act is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum DraftAct {
    Resume,
    Discard,
}

impl DraftAct {
    pub(crate) fn parse(s: &str) -> Result<Self, CoreError> {
        match s {
            "resume" => Ok(Self::Resume),
            "discard" => Ok(Self::Discard),
            _ => Err(CoreError::Validation {
                field: "act".into(),
                detail: "unknown queue act".into(),
            }),
        }
    }

    fn cap(self) -> Cap {
        match self {
            Self::Resume => RESUME_CAP,
            Self::Discard => DISCARD_CAP,
        }
    }

    fn key(self) -> &'static str {
        match self {
            Self::Resume => "resume",
            Self::Discard => "discard",
        }
    }
}


impl MadarCore {
    fn me(&self) -> (String, String) {
        self.current_session()
            .map(|s| (s.user_id, s.display_name))
            .unwrap_or_default()
    }

    /// `(own, age_minutes)` for a held order: whether the signed-in person
    /// started it (unknown author counts as own) and how long ago.
    fn draft_facts(&self, id: &str) -> Result<(bool, Option<i64>), CoreError> {
        let draft = held::get(&self.store, id)?.ok_or_else(|| CoreError::Validation {
            field: "draft".into(),
            detail: "held order not found".into(),
        })?;
        let (me, _) = self.me();
        let own = !started_by_other(draft.created_by.as_deref(), &me);
        let age = chrono::DateTime::parse_from_rfc3339(&draft.created_at)
            .ok()
            .map(|t| (self.corrected_now().timestamp() - t.timestamp()).max(0) / 60);
        Ok((own, age))
    }

    fn draft_on_table(&self, id: &str) -> bool {
        held::get(&self.store, id)
            .ok()
            .flatten()
            .is_some_and(|h| h.table_id.is_some_and(|t| !t.is_empty()))
    }

    /// May the signed-in person `act` (`"resume"` | `"discard"`) on held order
    /// `id`? Allowed, needs a manager, or refused. Offline.
    pub fn decide_draft_act(&self, act: String, id: String) -> ActDecisionView {
        let locale = self.current_locale();
        let Ok(a) = DraftAct::parse(&act) else {
            return approvals::decision_view(&Decision::Deny(Why::UnknownCapability), &locale);
        };
        let (own, age) = match self.draft_facts(&id) {
            Ok(f) => f,
            Err(_) => return approvals::decision_view(&Decision::Deny(Why::NotHeld), &locale),
        };
        if a == DraftAct::Resume && self.draft_on_table(&id) {
            // A table's order is shared, never gated per person (rule 4a).
            return approvals::decision_view(&Decision::Allow, &locale);
        }
        if own {
            // One's own parked cart: resuming or discarding it is as free as it was.
            return approvals::decision_view(&Decision::Allow, &locale);
        }
        match a {
            DraftAct::Discard => self.decide_act(a.cap().key().to_string(), None, age, Some(false)),
            DraftAct::Resume => {
                let view = self.decide_act(a.cap().key().to_string(), None, None, None);
                if view.outcome == "deny" {
                    // Not held: a manager may approve it (the capability takes approval).
                    approvals::decision_view(&Decision::NeedsApproval(Why::NotHeld), &locale)
                } else {
                    view
                }
            }
        }
    }

    /// A manager approves a queue act on held order `id` with their PIN.
    pub fn approve_draft_act(
        &self,
        approver_pin: String,
        act: String,
        id: String,
    ) -> Result<ApprovalView, CoreError> {
        let a = DraftAct::parse(&act)?;
        let (own, age) = self.draft_facts(&id)?;
        let (age, own) = match a {
            DraftAct::Discard => (age, Some(own)),
            DraftAct::Resume => (None, None),
        };
        self.approve_act(approver_pin, a.cap().key().to_string(), None, age, own)
    }

    /// Refuse a queue act the signed-in person may not do now. An approval
    /// passes a `needs_approval` only when it is for this act's capability
    /// and from someone else. `Ok(true)` when the approval was what let it through.
    pub(crate) fn gate_draft_act(
        &self,
        act: DraftAct,
        id: &str,
        approval: Option<&ApprovalView>,
    ) -> Result<bool, CoreError> {
        // A missing order refuses as missing, not as a permission.
        self.draft_facts(id)?;
        let key = act.cap().key();
        let view = self.decide_draft_act(act.key().to_string(), id.to_string());
        let (me, _) = self.me();
        match (view.outcome.as_str(), approval) {
            ("allow", _) => Ok(false),
            ("needs_approval", Some(a)) if a.capability == key && a.approver_id != me => Ok(true),
            _ => Err(CoreError::Forbidden { resource: "held_order".into(), action: view.reason }),
        }
    }

    /// After a resume: the context's cart belongs to the held order's author,
    /// with the approval that let this person take it.
    pub(crate) fn adopt_draft_owner(
        &self,
        ctx: cart::Ctx<'_>,
        draft: &held::HeldWire,
        approval: Option<ApprovalView>,
    ) -> Result<(), CoreError> {
        let owner = draft.created_by.as_ref().map(|u| cart::CartOwner {
            user_id: u.clone(),
            name: draft.created_by_name.clone().unwrap_or_default(),
            approval,
        });
        cart::set_owner(&self.store, ctx, owner.as_ref())
    }

    /// Who a context's cart belongs to: its recorded owner, else the person
    /// signed in now. `(user_id, name)`.
    pub(crate) fn cart_author(&self, ctx: cart::Ctx<'_>) -> (String, String) {
        cart::owner(&self.store, ctx)
            .ok()
            .flatten()
            .map(|o| (o.user_id, o.name))
            .unwrap_or_else(|| self.me())
    }

    /// For a sale: `(started_by, approval)` when the cart in `ctx` was started
    /// by someone other than the person ringing it.
    pub(crate) fn sale_started_by(
        &self,
        ctx: cart::Ctx<'_>,
    ) -> (Option<String>, Option<serde_json::Value>) {
        let (me, _) = self.me();
        match cart::owner(&self.store, ctx).ok().flatten() {
            Some(o) if o.user_id != me => {
                (Some(o.user_id), o.approval.as_ref().map(approvals::approval_wire))
            }
            _ => (None, None),
        }
    }

    /// Rule 1: park every context's non-empty cart under its author before the
    /// session goes. Best-effort per context; a cart that cannot be parked
    /// keeps its lines and is stamped with its author instead.
    pub(crate) fn park_queue_for_switch(&self) {
        let _guard = self.cart_ops.lock().unwrap_or_else(|e| e.into_inner());
        // Tables first (rule 4a): nothing person-scoped survives on a table.
        for t in cart::table_contexts_with_lines(&self.store).unwrap_or_default() {
            let _ = cart::clear(&self.store, Some(&t));
        }
        if cart::lines(&self.store, None).map(|l| l.is_empty()).unwrap_or(true) {
            return;
        }
        let meta = cart::meta(&self.store, None).unwrap_or_default();
        let parked = self.hold_cart_on_table_locked(
            None,
            meta.name.clone(),
            meta.draft_id.clone(),
            meta.started_at.clone(),
            None,
        );
        if parked.is_err() && cart::owner(&self.store, None).ok().flatten().is_none() {
            let (user_id, name) = self.me();
            let _ = cart::set_owner(&self.store, None, Some(&cart::CartOwner { user_id, name, approval: None }));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session::{AuthzGrants, PermissionEntry, SessionSnapshot, SessionState};
    use crate::{MadarConfig, MadarCore};
    use madar_authz::Limits;
    use std::sync::Arc;

    const BRANCH: &str = "00000000-0000-0000-0000-000000000001";
    const ALI: &str = "00000000-0000-0000-0000-0000000000a1";
    const BADR: &str = "00000000-0000-0000-0000-0000000000b2";
    const MONA: &str = "00000000-0000-0000-0000-0000000000c3";

    fn hash(pin: &str) -> String {
        use argon2::password_hash::SaltString;
        use argon2::{Argon2, PasswordHasher};
        let salt = SaltString::encode_b64(b"madar-test-salt").unwrap();
        Argon2::default().hash_password(pin.as_bytes(), &salt).unwrap().to_string()
    }

    /// A device with three people in its bundle: two tellers and a manager
    /// (PIN 9999) whose grants the feed carries.
    fn device() -> Arc<MadarCore> {
        let core = MadarCore::new(MadarConfig {
            base_url: "http://127.0.0.1:1".into(),
            environment: "dev".into(),
            db_path: String::new(),
            locale: "en".into(),
            app_version: None,
        })
        .unwrap();
        let person = |id: &str, name: &str, pin: &str| {
            serde_json::json!({ "user_id": id, "name": name, "role": "teller",
                "is_active": true, "offline_pin_hash": hash(pin) })
        };
        core.store
            .kv_put(
                crate::session::BUNDLE_KEY,
                &serde_json::json!({
                    "org_id": "00000000-0000-0000-0000-0000000000aa",
                    "generated_at": "2026-06-19T10:00:00Z",
                    "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
                    "tellers": [person(ALI, "Ali", "1111"), person(BADR, "Badr", "2222"),
                                person(MONA, "Mona", "9999")]
                })
                .to_string(),
            )
            .unwrap();
        let manager = serde_json::json!({"id": MONA, "user_id": MONA, "name": "Mona",
            "role": "branch_manager", "is_active": true,
            "capabilities": ["orders.create", "orders.void", "orders.held.resume_others", "pos.sign_in"], "is_owner": false});
        core.store
            .with_conn(|c| {
                c.execute(
                    "INSERT INTO sync_rows (branch_id, type, id, seq, data) VALUES (?1, 'teller', ?2, 1, ?3)",
                    rusqlite::params![BRANCH, MONA, manager.to_string()],
                )?;
                Ok(())
            })
            .unwrap();
        core
    }

    /// The person on the till: `own`-limited on `limited` when given; a key
    /// in `limited` that is `orders.held.resume_others` GRANTS it instead.
    fn sign_in(core: &MadarCore, id: &str, name: &str, limited: &[&str]) {
        let mut caps = vec!["orders.create".to_string(), "orders.void".to_string()];
        if limited.contains(&RESUME_CAP.key()) {
            caps.push(RESUME_CAP.key().into());
        }
        let limited: Vec<&str> = limited.iter().copied().filter(|k| *k != RESUME_CAP.key()).collect();
        let limits = limited
            .iter()
            .map(|k| (k.to_string(), Limits { own: true, ..Default::default() }))
            .collect();
        core.persist_and_set(SessionState {
            snapshot: SessionSnapshot {
                user_id: id.into(),
                display_name: name.into(),
                role: "teller".into(),
                org_id: Some("00000000-0000-0000-0000-0000000000aa".into()),
                branch_id: Some(BRANCH.into()),
                currency_code: "EGP".into(),
                tax_rate: 0.14,
                tax_inclusive: false,
                service_charge_rate: 0.0,
                service_charge_taxable: true,
                require_table_for_orders: false,
                online: false,
                permissions_loaded: true,
            },
            permissions: vec![PermissionEntry {
                resource: "orders".into(),
                action: "create".into(),
                granted: true,
            }],
            token: None,
            authz: Some(AuthzGrants {
                capabilities: caps,
                ask_manager: vec![],
                limits,
                owner: false,
            }),
        });
    }

    fn put_line(core: &MadarCore, ctx: Option<&str>, name: &str) {
        cart::set_cart_payload(
            &core.store,
            ctx,
            &serde_json::json!({ "lines": [{ "item_id": format!("item-{name}"), "name": name,
                "unit_price_minor": 5000, "qty": 1, "addons": [], "optionals": [] }] }),
        )
        .unwrap();
    }

    fn park(core: &MadarCore, name: &str) -> String {
        put_line(core, None, name);
        core.hold_cart(None, name.into(), None, None).unwrap();
        core.list_drafts().unwrap().into_iter().find(|d| d.name == name).unwrap().id
    }

    #[test]
    fn a_teller_switch_keeps_the_cart_in_hand_and_every_held_order() {
        let core = device();
        sign_in(&core, ALI, "Ali", &[]);
        park(&core, "Parked");
        put_line(&core, None, "InHand");

        core.logout(false).unwrap();
        sign_in(&core, BADR, "Badr", &[]);

        assert!(core.cart_lines(None).unwrap().is_empty(), "Badr starts with an empty cart");
        let drafts = core.list_drafts().unwrap();
        assert_eq!(drafts.len(), 2, "nothing discarded: {drafts:?}");
        for d in &drafts {
            assert!(d.by_other, "{} is Ali's", d.name);
            assert_eq!(d.created_by_name.as_deref(), Some("Ali"));
        }
        // Back to Ali: his own again.
        core.logout(false).unwrap();
        sign_in(&core, ALI, "Ali", &[]);
        assert!(core.list_drafts().unwrap().iter().all(|d| !d.by_other));
    }

    #[test]
    fn a_switch_leaves_nothing_person_scoped_on_a_table() {
        let core = device();
        sign_in(&core, ALI, "Ali", &[]);
        put_line(&core, Some("t-1"), "Soup");
        core.logout(false).unwrap();
        sign_in(&core, BADR, "Badr", &[]);
        assert!(core.list_drafts().unwrap().is_empty(), "no parked copy of the table");
        assert!(core.cart_lines(Some("t-1".into())).unwrap().is_empty());
        assert!(cart::owner(&core.store, Some("t-1")).unwrap().is_none());
        assert!(cart::table_contexts_with_lines(&core.store).unwrap().is_empty());
    }

    #[test]
    fn resuming_an_order_parked_on_a_table_is_never_gated_per_person() {
        let core = device();
        sign_in(&core, ALI, "Ali", &[]);
        put_line(&core, None, "Soup");
        core.hold_cart(None, "Table".into(), None, None).unwrap();
        let id = core.list_drafts().unwrap()[0].id.clone();
        let mut list = held::load_held(&core.store).unwrap();
        list[0].table_id = Some("t-4".into());
        core.store.kv_put(held::K_HELD_MIRROR, &serde_json::to_string(&list).unwrap()).unwrap();
        core.logout(false).unwrap();
        sign_in(&core, BADR, "Badr", &[]);
        assert_eq!(core.decide_draft_act("resume".into(), id.clone()).outcome, "allow");
        core.switch_to_draft(None, id, None, None).expect("a table resumes without a manager");
    }

    #[test]
    fn resuming_your_own_order_is_allowed() {
        let core = device();
        sign_in(&core, ALI, "Ali", &[]);
        let id = park(&core, "Mine");
        assert_eq!(core.decide_draft_act("resume".into(), id.clone()).outcome, "allow");
        let view = core.switch_to_draft(None, id, None, None).unwrap();
        assert_eq!(view.lines.len(), 1);
        assert_eq!(core.sale_started_by(None), (None, None), "one person: nothing extra on the sale");
    }

    #[test]
    fn someone_holding_resume_others_resumes_without_a_manager_and_names_the_author() {
        let core = device();
        sign_in(&core, ALI, "Ali", &[]);
        let id = park(&core, "Ali's");
        core.logout(false).unwrap();
        sign_in(&core, BADR, "Badr", &[RESUME_CAP.key()]);
        assert_eq!(core.decide_draft_act("resume".into(), id.clone()).outcome, "allow");
        core.switch_to_draft(None, id, None, None).unwrap();
        assert_eq!(core.sale_started_by(None), (Some(ALI.to_string()), None));
    }

    #[test]
    fn resuming_someone_elses_order_without_the_capability_needs_a_manager_and_carries_the_approval() {
        let core = device();
        sign_in(&core, ALI, "Ali", &[]);
        let id = park(&core, "Ali's");
        core.logout(false).unwrap();
        sign_in(&core, BADR, "Badr", &[]);

        let d = core.decide_draft_act("resume".into(), id.clone());
        assert_eq!(d.outcome, "needs_approval");
        assert!(!d.reason.is_empty());
        let refused = core.switch_to_draft(None, id.clone(), None, None);
        assert!(matches!(refused, Err(CoreError::Forbidden { .. })), "{refused:?}");
        assert_eq!(core.list_drafts().unwrap().len(), 1, "a refusal moves nothing");

        assert!(core.approve_draft_act("2222".into(), "resume".into(), id.clone()).is_err(), "not himself");
        let approval = core.approve_draft_act("9999".into(), "resume".into(), id.clone()).unwrap();
        assert_eq!(approval.approver_id, MONA);
        assert_eq!(approval.capability, "orders.held.resume_others");
        core.switch_to_draft_approved(None, id, None, None, Some(approval.clone())).unwrap();

        let (by, wire) = core.sale_started_by(None);
        assert_eq!(by.as_deref(), Some(ALI));
        let wire = wire.expect("the approval rides the sale");
        assert_eq!(wire["approver_id"], MONA);
        assert_eq!(wire["capability"], "orders.held.resume_others");

        // Parked again by Badr: still Ali's.
        core.hold_cart(None, "again".into(), None, None).unwrap();
        assert_eq!(core.list_drafts().unwrap()[0].created_by_name.as_deref(), Some("Ali"));
    }

    #[test]
    fn the_sale_envelope_carries_both_people_and_old_payloads_still_parse() {
        let mut cmd = crate::checkout::CheckoutCommand {
            request: madar_api::models::CreateOrderRequest::new(
                uuid::Uuid::new_v4(),
                vec![],
                "Cash".into(),
                uuid::Uuid::new_v4(),
            ),
            device: None,
            started_by: Some(ALI.into()),
            approval: Some(serde_json::json!({"id": "a", "capability": "orders.create", "approver_id": MONA})),
        };
        let env = crate::checkout::order_envelope(&cmd, BADR, "dev");
        assert_eq!(env["teller_id"], BADR);
        assert_eq!(env["request"]["started_by"], ALI);
        assert_eq!(env["approval"]["approver_id"], MONA);

        cmd.started_by = None;
        cmd.approval = None;
        let old = serde_json::to_string(&cmd).unwrap();
        assert!(!old.contains("started_by") && !old.contains("approval"));
        let back: crate::checkout::CheckoutCommand = serde_json::from_str(&old).unwrap();
        assert!(back.started_by.is_none());
        let env = crate::checkout::order_envelope(&back, BADR, "dev");
        assert!(env["request"].get("started_by").is_none());
        assert!(env.get("approval").is_none());
    }

    #[test]
    fn discarding_someone_elses_order_follows_the_void_rules() {
        let core = device();
        sign_in(&core, ALI, "Ali", &["orders.void"]);
        let mine = park(&core, "Mine");
        assert_eq!(core.decide_draft_act("discard".into(), mine.clone()).outcome, "allow");
        let theirs = park(&core, "Also mine");
        core.discard_draft(mine).unwrap();

        core.logout(false).unwrap();
        sign_in(&core, BADR, "Badr", &["orders.void"]);
        assert_eq!(core.decide_draft_act("discard".into(), theirs.clone()).outcome, "needs_approval");
        assert!(matches!(core.discard_draft(theirs.clone()), Err(CoreError::Forbidden { .. })));
        let approval = core.approve_draft_act("9999".into(), "discard".into(), theirs.clone()).unwrap();
        core.discard_draft_approved(theirs, Some(approval)).unwrap();
        assert!(core.list_drafts().unwrap().is_empty());
    }

    #[test]
    fn an_old_held_order_with_no_author_is_nobodys() {
        let core = device();
        sign_in(&core, ALI, "Ali", &[]);
        let id = park(&core, "Old");
        let mut list = held::load_held(&core.store).unwrap();
        list[0].created_by = None;
        list[0].created_by_name = None;
        core.store.kv_put(held::K_HELD_MIRROR, &serde_json::to_string(&list).unwrap()).unwrap();
        // An entry written before the fields existed still parses.
        let raw = core.store.kv_get(held::K_HELD_MIRROR).unwrap().unwrap();
        assert!(!raw.contains("created_by"));
        core.logout(false).unwrap();
        sign_in(&core, BADR, "Badr", &["orders.void"]);
        assert!(!core.list_drafts().unwrap()[0].by_other);
        assert_eq!(core.decide_draft_act("discard".into(), id).outcome, "allow");
    }
}
