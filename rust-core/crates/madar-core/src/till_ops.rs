//! The till lifecycle on `MadarCore` (TILLS_CONTRACT §4.5–§4.8): open with server /
//! LAN verification and an unverified fallback, cash, close with per-method
//! reconciliation, force-close, reports, lists, and the device identity.

use madar_api::apis::{devices_api, tills_api};
use madar_api::models;

use crate::error::CoreError;
use crate::till::{self, TillRecord, TillView};
use crate::{cash_i32, checkout, device, net, store, till_views, MadarCore};

struct SessionParts {
    branch_id: String,
    user_id: String,
    name: String,
    role: String,
    online: bool,
}

impl MadarCore {
    fn session_parts(&self) -> Result<SessionParts, CoreError> {
        let s = self.current_session().ok_or_else(|| CoreError::Unauthenticated {
            detail: "not signed in".into(),
        })?;
        let branch_id = s.branch_id.clone().ok_or_else(|| CoreError::Validation {
            field: "branch_id".into(),
            detail: "session has no branch".into(),
        })?;
        Ok(SessionParts {
            branch_id,
            user_id: s.user_id.clone(),
            name: s.display_name.clone(),
            role: s.role.clone(),
            online: s.online,
        })
    }

    fn method_label_fn(&self) -> impl Fn(&str) -> String + '_ {
        move |m: &str| self.payment_method_label(m.to_string())
    }

    /// Push this device's open tills (one per person) + code to the LAN beacon.
    pub(crate) fn lan_sync_open_tills(&self) {
        if let Some(relay) = self.lan.lock().unwrap_or_else(|e| e.into_inner()).clone() {
            let tills = till::open_on_device(&self.store)
                .into_iter()
                .map(|t| crate::lan::BeaconTill {
                    till_id: t.id,
                    person_id: t.teller_id,
                    person_name: t.teller_name,
                    opened_at: t.opened_at,
                })
                .collect();
            relay.set_open_tills(tills);
            relay.set_device_code(Some(checkout::device_code_or_default(&self.store)));
        }
    }

    fn lan_person_sighting(&self, person: &str) -> (Option<till::LanTillSighting>, bool) {
        match self.lan.lock().unwrap_or_else(|e| e.into_inner()).clone() {
            Some(relay) => (
                relay.person_open_till(person).map(|(p, t)| till::LanTillSighting {
                    till_id: t.till_id,
                    device_id: p.device_id,
                    device_code: p.device_code,
                    opened_at: t.opened_at,
                }),
                relay.has_live_teller_peer(),
            ),
            None => (None, false),
        }
    }

    /// `/tills/.../current` under the read timeout: the till screen and the
    /// open button wait on it, and a hanging link must not hold them.
    async fn fetch_prefill(&self, branch: &str) -> Result<models::TillPreFill, CoreError> {
        let config = self.api.config();
        crate::ledger_ops::within(tills_api::get_current_till(
            &config,
            tills_api::GetCurrentTillParams {
                branch_id: branch.to_string(),
                teller_id: None,
            },
        ))
        .await
    }

    /// The live server check: `/tills/.../current`, else — when that call fails
    /// moments after sign-in — what sign-in itself said.
    async fn server_prefill(&self, branch: &str, user_id: &str) -> Option<models::TillPreFill> {
        match self.fetch_prefill(branch).await {
            Ok(pf) => Some(pf),
            Err(_) => till::login_prefill(
                &self.store,
                user_id,
                &self.lan_device_id(),
                chrono::Utc::now(),
            ),
        }
    }

    // ── public surface ─────────────────────────────────────────────────────

    /// This install's device id (`lan_device_id`, the `X-Madar-Device` header).
    pub fn device_id(&self) -> String {
        self.lan_device_id()
    }

    /// Is this device walled to the open-till screen? The ONE answer the shell
    /// reads (owner decision 2026-09-19): a till device with no open drawer
    /// sells nothing, shows nothing but the open-till screen, Settings, sync,
    /// sign out and the manager-actions list.
    ///
    /// Sync and purely local — the device may be offline and must still know.
    /// The carve-out is the same one `open_till`/`refresh_till` make: waiters
    /// and kitchen devices hold no drawer, so they are never locked (locking
    /// them would stop table service and the kitchen).
    pub fn till_lock(&self) -> till::TillLockView {
        let locale = self.current_locale();
        let t = |k: &str| crate::i18n::tr(&locale, k);
        let unlocked = |holds_drawer: bool| till::TillLockView {
            locked: false,
            holds_drawer,
            ..Default::default()
        };
        // Signed out / unbound: login and device setup own those screens.
        let session = match self.current_session() {
            Some(s) => s,
            None => return unlocked(false),
        };
        if !device::load(&self.store).configured() {
            return unlocked(false);
        }
        let work_kind = self
            .session
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .map(|s| s.work_kind())
            .unwrap_or("teller");
        if work_kind == "waiter" || work_kind == "kitchen" {
            return unlocked(false);
        }
        // This person's OWN open till on THIS device is the only thing that
        // unlocks it — a stale till left by whoever worked here before does not.
        if let Ok(Some(cur)) = till::current(&self.store) {
            if cur.is_open && cur.teller_id == session.user_id {
                return unlocked(true);
            }
        }
        // "Not permitted" is only ever said when the permissions are actually
        // KNOWN. An offline bundle sign-in carries a role and no permission
        // rows yet; claiming the cashier may not open a drawer on that would
        // wall the shop on a blank. Unknown → show the form and let
        // `open_till`'s own refusal speak.
        let permissions_known = self
            .session
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .map(|s| s.authz.is_some() || !s.permissions.is_empty())
            .unwrap_or(false);
        let can_open = !permissions_known || self.can(madar_authz::Cap::TillOpen.key().to_string());
        if !can_open {
            return till::TillLockView {
                locked: true,
                reason: "not_permitted".into(),
                title: t("till.lock_not_permitted_title"),
                body: format!(
                    "{} {}",
                    t("till.lock_not_permitted_body"),
                    t("till.lock_switch_hint")
                ),
                can_open: false,
                holds_drawer: true,
                elsewhere: None,
            };
        }
        // Open somewhere else, as far as the last pull and this device's own
        // rows know. No network: the synced rows are already here.
        let elsewhere = session.branch_id.as_deref().and_then(|b| {
            till::elsewhere_from_rows(&till::branch_records(&self.store, b), &session.user_id, &self.lan_device_id())
        });
        if let Some(e) = elsewhere {
            return till::TillLockView {
                locked: true,
                reason: "open_elsewhere".into(),
                title: t("till.lock_elsewhere_title"),
                body: t("till.lock_elsewhere_body"),
                can_open: false,
                holds_drawer: true,
                elsewhere: Some(e),
            };
        }
        till::TillLockView {
            locked: true,
            reason: "no_till".into(),
            title: t("till.lock_title"),
            body: t("till.lock_body"),
            can_open: true,
            holds_drawer: true,
            elsewhere: None,
        }
    }

    pub fn current_till(&self) -> Result<Option<TillView>, CoreError> {
        till::current(&self.store)
    }

    pub fn suggested_opening_cash_minor(&self) -> Result<i64, CoreError> {
        till::suggested_opening_cash(&self.store)
    }

    /// Is the signed-in person's till open on ANOTHER device? The synced till
    /// rows, then live LAN peers; `None` when neither says so.
    pub async fn check_till_elsewhere(&self) -> Result<Option<till::TillElsewhereView>, CoreError> {
        let sp = self.session_parts()?;
        let dev = self.lan_device_id();
        // The synced rows first (the server's open tills as of the last pull),
        // then live LAN peers. No network: this is polled by the till screen.
        let rows = till::branch_records(&self.store, &sp.branch_id);
        if let Some(e) = till::elsewhere_from_rows(&rows, &sp.user_id, &dev) {
            return Ok(Some(e));
        }
        let (sighting, peers) = self.lan_person_sighting(&sp.user_id);
        Ok(match till::decide_open(None, &dev, sighting.as_ref(), peers) {
            till::OpenDecision::Blocked(e) => Some(e),
            _ => None,
        })
    }

    /// Open the signed-in person's till (contract §4.5). Blocked → no enqueue.
    pub async fn open_till(
        &self,
        opening_cash_minor: i64,
        opening_reason: Option<String>,
    ) -> Result<till::OpenTillOutcome, CoreError> {
        let sp = self.session_parts()?;
        if sp.role == "waiter" || sp.role == "kitchen" {
            return Err(CoreError::Forbidden {
                resource: "tills".into(),
                action: "waiters never open a till".into(),
            });
        }
        if let Some(cur) = till::current(&self.store)?.filter(|t| t.is_open) {
            return Ok(till::OpenTillOutcome {
                verification: cur.verification.clone(),
                till: Some(cur),
                open_elsewhere: None,
            });
        }
        let dev = self.lan_device_id();
        let server = if sp.online {
            self.server_prefill(&sp.branch_id, &sp.user_id).await
        } else {
            None
        };
        let (sighting, peers) = if server.is_some() {
            (None, false)
        } else {
            self.lan_person_sighting(&sp.user_id)
        };
        let verification = match till::decide_open(server.as_ref(), &dev, sighting.as_ref(), peers) {
            till::OpenDecision::Blocked(e) => {
                return Ok(till::OpenTillOutcome {
                    till: None,
                    verification: String::new(),
                    open_elsewhere: Some(e),
                })
            }
            till::OpenDecision::Resume(t) => {
                till::save(&self.store, &t)?;
                self.lan_sync_open_tills();
                // Resuming is this device opening the till for selling again:
                // the same background drain + pull (decision 15).
                self.spawn_till_open_sync(t.id.clone());
                let v = till::view_from(&t);
                return Ok(till::OpenTillOutcome {
                    verification: v.verification.clone(),
                    till: Some(v),
                    open_elsewhere: None,
                });
            }
            till::OpenDecision::Allow(v) => v,
        };

        let till_id = uuid::Uuid::new_v4();
        let opened_at = self.corrected_now().fixed_offset();
        let opening_cash = cash_i32(opening_cash_minor, "opening_cash")?;
        let reason = opening_reason.filter(|r| !r.trim().is_empty());
        let code = checkout::device_code_or_default(&self.store);
        let local = TillRecord {
            id: till_id.to_string(),
            branch_id: sp.branch_id.clone(),
            teller_id: sp.user_id.clone(),
            teller_name: sp.name.clone(),
            status: "open".into(),
            opening_cash: opening_cash as i64,
            opening_cash_was_edited: reason.is_some(),
            opening_cash_edit_reason: reason.clone(),
            opened_at: opened_at.to_rfc3339(),
            device_id: Some(dev.clone()),
            device_code: Some(code.clone()),
            verification: Some(verification.to_string()),
            ..Default::default()
        };
        let cmd = till::OpenTillCommand {
            branch_id: sp.branch_id.clone(),
            device_id: dev.clone(),
            device_code: code,
            verification: verification.to_string(),
            request: models::OpenTillRequest {
                id: Some(Some(till_id)),
                opening_cash,
                opening_cash_edited: Some(Some(reason.is_some())),
                edit_reason: reason.map(Some),
                opened_at: Some(Some(opened_at)),
                device_id: uuid::Uuid::parse_str(&dev).ok().map(Some),
                verification: Some(Some(till::verification_wire(verification))),
            },
        };
        let (user_id, clock_offset_ms) = self.outbox_meta();
        let op = store::NewOutboxOp {
            id: till_id.to_string(),
            op_type: "open_till".into(),
            idempotency_key: till_id.to_string(),
            payload: serde_json::to_string(&cmd)?,
            event_at: opened_at.to_rfc3339(),
            user_id,
            clock_offset_ms,
            till_id: Some(till_id.to_string()),
            device_id: Some(dev),
            entity_type: Some(crate::ledger::T_TILL.into()),
            entity_id: Some(till_id.to_string()),
            ..Default::default()
        };
        // The till's row, the person's device slot and the queued open commit
        // together: the till cannot exist without its open, nor the reverse.
        let record = serde_json::to_value(&local)?;
        self.store.with_tx_touch(|tx, touched| {
            crate::ledger::local::commit_open_till(tx, &op, &record)?;
            if !local.teller_id.is_empty() {
                tx.execute(
                    "INSERT INTO kv(k, v, updated_at) VALUES(?1, ?2, ?3)
                     ON CONFLICT(k) DO UPDATE SET v=excluded.v, updated_at=excluded.updated_at",
                    rusqlite::params![till::device_till_key(&local.teller_id), local.id, chrono::Utc::now().to_rfc3339()],
                )?;
            }
            touched.extend(crate::changes::tables_for_op("open_till"));
            Ok(())
        })?;
        self.lan_sync_open_tills();
        self.spawn_till_open_sync(till_id.to_string());
        Ok(till::OpenTillOutcome {
            till: Some(till::view_from(&local)),
            verification: verification.to_string(),
            open_elsewhere: None,
        })
    }

    /// Reconcile the person's till with the synced till rows (no network: the
    /// changefeed carries every open till at the branch, and this device's own
    /// writes are already rows). Before the branch's first snapshot the rows
    /// cannot say "no till", so the local state stands.
    pub async fn refresh_till(&self) -> Result<Option<TillView>, CoreError> {
        let sp = self.session_parts()?;
        // Who holds a drawer, framed the same way `open_till` frames it: waiters
        // and kitchen devices never do; EVERYONE else who may work a till does —
        // managers and owners included (architecture E put them on tills).
        //
        // This used to read `sp.role != "teller"`, so a signed-in manager or
        // owner got `None` here. The Till tab asks this whenever it is ONLINE
        // (`_deviceTill`), takes the answer as the truth, and so rendered the
        // open-till form for them forever: opening a till changed nothing on
        // screen even though the open had already landed on the server.
        if sp.role == "waiter" || sp.role == "kitchen" {
            return Ok(None);
        }
        let local = till::current(&self.store)?;
        if !crate::sync_pull::branch_snapshotted(&self.store, &sp.branch_id) {
            return Ok(local);
        }
        let rows = till::branch_records(&self.store, &sp.branch_id);
        if self.store.pending_count().map(|n| n == 0).unwrap_or(false) {
            // The DRAWER's carryover, not the person's: this device's own last
            // close where it has one, else the branch's. Cached unconditionally
            // — a genuine zero (the drawer emptied into the safe) has to clear
            // the last figure, and the old `if s > 0` guard left it standing.
            let dev = self.lan_device_id();
            let s = till::last_close_declared_rows(&rows, Some(dev.as_str()))
                .or_else(|| crate::sync_pull::standard_float(&self.store, &sp.branch_id))
                .unwrap_or(0);
            till::cache_suggested_opening_cash(&self.store, s)?;
        }
        let pending = |op: &[&str]| {
            local
                .as_ref()
                .map(|l| {
                    self.store
                        .list_active_for_till(&l.id)
                        .unwrap_or_default()
                        .iter()
                        .any(|i| i.status != "dead" && op.contains(&i.op_type.as_str()))
                })
                .unwrap_or(false)
        };
        let open_pending = pending(&["open_till", "open_shift"]);
        let close_pending = pending(&["close_till", "close_shift"]);
        let decision =
            till::reconcile_rows(&rows, &sp.user_id, &self.lan_device_id(), local.as_ref(), open_pending, close_pending);
        match decision {
            till::TillReconcile::Adopt(t) => {
                let moved = local.as_ref().map(|l| l.id != t.id || !l.is_open).unwrap_or(true);
                if moved {
                    till::save(&self.store, &t)?;
                    self.lan_sync_open_tills();
                }
                Ok(Some(till::view_from(&t)))
            }
            till::TillReconcile::KeepLocal => Ok(local),
            till::TillReconcile::Clear => {
                if local.is_some() {
                    till::clear(&self.store)?;
                    self.lan_sync_open_tills();
                }
                Ok(None)
            }
        }
    }

    /// Bills left open at the branch (`None` when zero).
    pub async fn open_bills_notice(&self) -> Result<Option<till::OpenBillsNoticeView>, CoreError> {
        let sp = self.session_parts()?;
        // Computed from the synced rows, like the close preview's: no network.
        let bills: Vec<till::LocalBill> = self
                .bill_source()
                .into_iter()
                .filter(|t| t.status == "open")
                .map(|t| till::LocalBill {
                    opened_at: t.opened_at.to_rfc3339(),
                    amount_minor: t.subtotal as i64,
                })
                .collect();
        let seated = self
            .floor_layout()
            .map(|l| l.tables.iter().filter(|t| t.status == "seated").count() as i64)
            .unwrap_or(0);
        let hours = crate::sync_pull::old_bill_hours(&self.store, &sp.branch_id);
        Ok(till::local_open_bills_notice(&bills, seated, hours, None, chrono::Utc::now()))
    }

    fn open_till_or_err(&self) -> Result<TillView, CoreError> {
        till::current(&self.store)?
            .filter(|t| t.is_open)
            .ok_or_else(|| CoreError::Validation {
                field: "till".into(),
                detail: "no open till".into(),
            })
    }

    pub async fn record_cash_movement(
        &self,
        amount_minor: i64,
        note: String,
        kind: Option<String>,
        corrects: Option<String>,
    ) -> Result<till::CashMovementView, CoreError> {
        let t = self.open_till_or_err()?;
        let note = note.trim().to_string();
        if amount_minor == 0 {
            return Err(CoreError::Validation {
                field: "amount".into(),
                detail: "amount cannot be zero".into(),
            });
        }
        if note.is_empty() {
            return Err(CoreError::Validation {
                field: "note".into(),
                detail: "a note is required for cash movements".into(),
            });
        }
        let client_ref = uuid::Uuid::new_v4();
        let created_at = self.corrected_now().fixed_offset();
        let mut request = madar_api::models::CashMovementRequest::new(
            cash_i32(amount_minor, "amount")?,
            note.clone(),
        );
        request.client_ref = Some(Some(client_ref));
        request.created_at = Some(Some(created_at));
        request.kind = kind.as_deref().map(crate::map_cash_kind).map(Some);
        if let Some(id) = corrects.as_deref().filter(|s| !s.trim().is_empty()) {
            let parsed = uuid::Uuid::parse_str(id).map_err(|_| CoreError::Validation {
                field: "corrects".into(),
                detail: "a correction names the movement it reverses".into(),
            })?;
            request.corrects_id = Some(Some(parsed));
        }
        let dev = self.lan_device_id();
        let cmd = till::CashMovementCommand {
            till_id: t.id.clone(),
            device_id: Some(dev.clone()),
            request,
        };
        let (user_id, clock_offset_ms) = self.outbox_meta();
        let teller_name = self.current_session().map(|s| s.display_name).unwrap_or_default();
        let wire_kind = cmd
            .request
            .kind
            .flatten()
            .map(|k| k.to_string())
            .unwrap_or_else(|| if amount_minor < 0 { "pay_out".into() } else { "pay_in".into() });
        let row = serde_json::json!({
            "id": client_ref.to_string(),
            "client_ref": client_ref.to_string(),
            "till_id": t.id,
            "amount": amount_minor,
            "kind": wire_kind,
            "corrects_id": cmd.request.corrects_id.flatten().map(|u| u.to_string()),
            "note": note,
            "moved_by_name": teller_name,
            "created_at": created_at.to_rfc3339(),
            "device_id": dev,
        });
        let op = store::NewOutboxOp {
            id: client_ref.to_string(),
            op_type: "cash_movement".into(),
            idempotency_key: client_ref.to_string(),
            payload: serde_json::to_string(&cmd)?,
            event_at: created_at.to_rfc3339(),
            depends_on_seq: self.store.live_seq_of(&t.id)?,
            user_id,
            clock_offset_ms,
            till_id: Some(t.id.clone()),
            device_id: Some(dev),
            entity_type: Some(crate::ledger::T_CASH.into()),
            entity_id: Some(client_ref.to_string()),
        };
        self.store.with_tx_touch(|tx, touched| {
            crate::ledger::local::commit_cash(tx, &op, &row)?;
            touched.extend(crate::changes::tables_for_op("cash_movement"));
            Ok(())
        })?;
        self.send_in_background(vec![client_ref.to_string()]);
        Ok(till::CashMovementView {
            id: client_ref.to_string(),
            kind: till_views::movement_kind(kind.as_deref(), amount_minor),
            amount_minor,
            note,
            moved_by_name: self.current_session().map(|s| s.display_name).unwrap_or_default(),
            created_at: created_at.to_rfc3339(),
        })
    }

    /// Close the person's till (never blocked). Queues `close_till` with the
    /// per-method reconciliation. Held orders are left open and recorded.
    pub async fn close_till(
        &self,
        closing_cash_minor: i64,
        cash_note: Option<String>,
        reconciliation: Vec<till::ReconciliationInput>,
    ) -> Result<till::CloseTillOutcomeView, CoreError> {
        self.close_till_confirmed(closing_cash_minor, cash_note, reconciliation, true).await
    }

    /// [`Self::close_till`] after the held-orders warning (`close_preflight`,
    /// queue.rs rule 8): `leave_held_open` false refuses while any are open.
    pub async fn close_till_confirmed(
        &self,
        closing_cash_minor: i64,
        cash_note: Option<String>,
        reconciliation: Vec<till::ReconciliationInput>,
        leave_held_open: bool,
    ) -> Result<till::CloseTillOutcomeView, CoreError> {
        // Queue step (self-contained): the held-orders check, before anything else.
        if !leave_held_open && self.close_preflight().held_count > 0 {
            return Err(CoreError::Validation {
                field: "held_orders".into(),
                detail: "held orders are still open".into(),
            });
        }
        let t = self.open_till_or_err()?;
        let preview = self.close_till_preview().await.ok();
        // A blind count: the person gave what they see; the core decides
        // whether it agrees with the system (a disagreement lands in the
        // owner's review queue after the close).
        let blind_note = crate::i18n::tr(&self.current_locale(), "spot.blind_count_note");
        let reconciliation = till::resolve_blind_counts(
            reconciliation,
            preview.as_ref().map(|p| p.methods.as_slice()).unwrap_or(&[]),
            &blind_note,
        );
        let inputs = till::reconciliation_wire(&reconciliation)?;
        // A close never predates its open. The corrected clock moves in whole
        // seconds as the server offset is re-estimated, so a till closed moments
        // after it opened could read earlier than its own open — which the server
        // refuses (400), dead-lettering the close. Found by the integration run.
        let closed_at = chrono::DateTime::parse_from_rfc3339(&t.opened_at)
            .ok()
            .map(|opened| opened.with_timezone(&chrono::Utc).max(self.corrected_now()))
            .unwrap_or_else(|| self.corrected_now())
            .fixed_offset();
        let dev = self.lan_device_id();
        let cash_note = cash_note.filter(|n| !n.trim().is_empty());
        let (held_left, held_left_total) = self.leave_queue_for_next_till();
        let request = models::CloseTillRequest {
            held_orders_left_open: Some(i32::try_from(held_left).ok()),
            held_orders_left_open_total: Some(i32::try_from(held_left_total).ok()),
            closing_cash_declared: cash_i32(closing_cash_minor, "closing_cash")?,
            cash_note: cash_note.clone().map(Some),
            closed_at: Some(Some(closed_at)),
            device_id: uuid::Uuid::parse_str(&dev).ok().map(Some),
            reconciliation: Some(Some(inputs.clone())),
        };
        // The carts were parked or emptied above (`leave_queue_for_next_till`).
        // What this drawer was just closed at IS the next opening's carryover,
        // whoever opens it next.
        till::cache_suggested_opening_cash(&self.store, closing_cash_minor)?;
        let cmd = till::CloseTillCommand {
            till_id: t.id.clone(),
            device_id: Some(dev.clone()),
            request,
        };
        let (user_id, clock_offset_ms) = self.outbox_meta();
        let close_id = format!("{}:close", t.id);
        let op = store::NewOutboxOp {
            id: close_id.clone(),
            op_type: "close_till".into(),
            idempotency_key: close_id.clone(),
            payload: serde_json::to_string(&cmd)?,
            event_at: closed_at.to_rfc3339(),
            depends_on_seq: self.store.live_seq_of(&t.id)?,
            user_id,
            clock_offset_ms,
            till_id: Some(t.id.clone()),
            device_id: Some(dev),
            entity_type: Some(crate::ledger::T_TILL.into()),
            entity_id: Some(t.id.clone()),
        };
        let at = closed_at.to_rfc3339();
        self.store.with_tx_touch(|tx, touched| {
            crate::ledger::local::commit_close_till(tx, &op, &at, closing_cash_minor)?;
            touched.extend(crate::changes::tables_for_op("close_till"));
            Ok(())
        })?;
        self.send_soon(Vec::new()).await;
        self.lan_sync_open_tills();
        let queued = self.store.live_seq_of(&close_id)?.is_some();
        let methods = preview.as_ref().map(|p| p.methods.clone()).unwrap_or_default();
        let label = self.method_label_fn();
        let reconciliation = match self
            .store
            .kv_get(&till::close_result_key(&t.id))?
            .and_then(|raw| serde_json::from_str::<models::CloseTillResponse>(&raw).ok())
        {
            Some(r) if !queued => till::reconciliation_lines_from_api(&r.reconciliation, &label),
            _ => till::local_reconciliation_lines(&methods, &inputs, closing_cash_minor, cash_note.as_deref()),
        };
        Ok(till::CloseTillOutcomeView {
            queued,
            reconciliation,
            last_till_warning: preview.and_then(|p| p.last_till_warning),
        })
    }

    /// A manager closes someone's till from this device (online only).
    pub async fn force_close_till(&self, till_id: String, reason: String) -> Result<(), CoreError> {
        let sp = self.session_parts()?;
        if !sp.online {
            return Err(CoreError::Offline {
                detail: "a forced close is the server's call to make".into(),
            });
        }
        let reason = reason.trim().to_string();
        if reason.is_empty() {
            return Err(CoreError::Validation {
                field: "reason".into(),
                detail: "say why the till was closed for someone else".into(),
            });
        }
        tills_api::force_close_till(
            &self.api.config(),
            tills_api::ForceCloseTillParams {
                till_id: till_id.clone(),
                force_close_request: models::ForceCloseRequest {
                    reason: Some(Some(reason)),
                    device_id: uuid::Uuid::parse_str(&self.lan_device_id()).ok().map(Some),
                },
            },
        )
        .await
        .map_err(net::map_api_error)?;
        if let Some(mut r) = till::record(&self.store, &till_id) {
            r.status = "force_closed".into();
            till::update_record(&self.store, &r)?;
        }
        till::clear_till(&self.store, &till_id)?;
        self.lan_sync_open_tills();
        Ok(())
    }

    /// Tills open at the branch: the synced rows ∪ LAN adverts ∪ this device.
    pub async fn branch_open_tills(&self) -> Result<Vec<till::BranchOpenTillView>, CoreError> {
        let sp = self.session_parts()?;
        let dev = self.lan_device_id();
        let mut out: Vec<till::BranchOpenTillView> = Vec::new();
        // The synced till rows: every till open at the branch as of the last pull.
        let mut rows: Vec<TillRecord> =
            till::branch_records(&self.store, &sp.branch_id).into_iter().filter(|t| t.status == "open").collect();
        rows.retain(|t| t.branch_id.is_empty() || t.branch_id == sp.branch_id);
        for t in rows {
            out.push(till::BranchOpenTillView {
                is_this_device: t.device_id.as_deref() == Some(dev.as_str()),
                till_id: t.id,
                teller_id: t.teller_id,
                teller_name: t.teller_name,
                device_code: t.device_code,
                device_label: t.device_label,
                opened_at: t.opened_at,
                source: "server".into(),
            });
        }
        let mut add = |till_id: String, teller_id: String, name: String, code: Option<String>, at: String, here: bool| {
            match out.iter_mut().find(|o| o.till_id == till_id) {
                Some(o) => {
                    if o.source == "server" {
                        o.source = "both".into();
                    }
                }
                None => out.push(till::BranchOpenTillView {
                    till_id,
                    teller_id,
                    teller_name: name,
                    device_code: code,
                    device_label: None,
                    opened_at: at,
                    is_this_device: here,
                    source: "lan".into(),
                }),
            }
        };
        if let Some(relay) = self.lan.lock().unwrap_or_else(|e| e.into_inner()).clone() {
            for (p, t) in relay.branch_open_tills() {
                add(t.till_id, t.person_id, t.person_name, p.device_code, t.opened_at, false);
            }
        }
        for t in till::open_on_device(&self.store) {
            add(t.id, t.teller_id, t.teller_name, t.device_code, t.opened_at, true);
        }
        out.sort_by(|a, b| b.opened_at.cmp(&a.opened_at));
        Ok(out)
    }

    /// Methods offered at Charge: branch ∩ this user ∩ this device (from the
    /// synced `payment_availability` rows; no rows = no restriction).
    pub fn available_payment_methods(&self) -> Result<Vec<crate::menu::PaymentMethodView>, CoreError> {
        let all = self.list_payment_methods()?;
        let ids: Vec<String> = all.iter().map(|m| m.id.clone()).collect();
        let branch = self.current_session().and_then(|s| s.branch_id).unwrap_or_default();
        let user = self.current_session().map(|s| s.user_id).unwrap_or_default();
        let dev = self.lan_device_id();
        let list = |scope: &str, owner: &str| crate::sync_pull::availability_list(&self.store, &branch, scope, owner);
        let (b, u, d) = (list("branch", &branch), list("user", &user), list("device", &dev));
        let keep = till::effective_method_ids(&ids, b.as_deref(), u.as_deref(), d.as_deref());
        Ok(all.into_iter().filter(|m| keep.contains(&m.id)).collect())
    }

    /// Refuse a method this branch / person / device may not take (decision 10)
    /// before a sale is queued: replay never re-checks availability, so this is
    /// the check that stops it. A method the catalogue does not know is left to
    /// the caller's own "unknown payment method".
    pub(crate) fn ensure_methods_available<'a>(
        &self,
        ids: impl IntoIterator<Item = &'a str>,
    ) -> Result<(), CoreError> {
        let active: std::collections::HashSet<String> =
            self.list_payment_methods()?.into_iter().map(|m| m.id).collect();
        let offered: std::collections::HashSet<String> =
            self.available_payment_methods()?.into_iter().map(|m| m.id).collect();
        match ids
            .into_iter()
            .filter(|id| !id.is_empty())
            .find(|id| active.contains(*id) && !offered.contains(*id))
        {
            Some(_) => Err(net::payment_method_unavailable()),
            None => Ok(()),
        }
    }

    /// Set the device code; also registers the device with the server when online.
    pub fn set_device_code(&self, code: String) {
        let clean: String = code
            .chars()
            .filter(|c| c.is_ascii_alphanumeric())
            .take(6)
            .collect::<String>()
            .to_uppercase();
        if clean.is_empty() {
            return;
        }
        let _ = self.store.kv_put(checkout::KEY_DEVICE_CODE, &clean);
        self.lan_sync_open_tills();
        let ids = (
            uuid::Uuid::parse_str(&self.lan_device_id()).ok(),
            self.session_parts()
                .ok()
                .filter(|sp| sp.online)
                .and_then(|sp| uuid::Uuid::parse_str(&sp.branch_id).ok()),
        );
        if self.scheduler.manual.load(std::sync::atomic::Ordering::SeqCst) {
            return;
        }
        if let (Ok(handle), (Some(id), Some(branch_id)), Some(me)) =
            (tokio::runtime::Handle::try_current(), ids, self.self_arc())
        {
            let mut request = models::RegisterDeviceRequest::new(branch_id, clean, id, models::DeviceKind::Pos);
            request.platform = Some(Some(std::env::consts::OS.to_string()));
            request.app_version = Some(Some(net::app_version(self.config.app_version.as_deref())));
            handle.spawn(async move {
                let _ = devices_api::register_device(
                    &me.api.config(),
                    devices_api::RegisterDeviceParams {
                        register_device_request: request,
                    },
                )
                .await;
            });
        }
    }

    /// Decision 15: after an open, drain then pull in the background.
    pub(crate) fn spawn_till_open_sync(&self, till_id: String) {
        {
            let mut st = self.sync_state.lock().unwrap_or_else(|e| e.into_inner());
            st.till_open = crate::sync_pull::TillOpenSyncView {
                state: "running".into(),
                till_id: Some(till_id),
                started_at: Some(chrono::Utc::now().to_rfc3339()),
                ..Default::default()
            };
        }
        if self.scheduler.manual.load(std::sync::atomic::Ordering::SeqCst) {
            // Manual scheduling: the harness decides when the drain and pull run.
            self.scheduler.nudges_wanted.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            return;
        }
        if let Some(me) = self.self_arc() {
            if let Ok(h) = tokio::runtime::Handle::try_current() {
                h.spawn(async move {
                    me.run_till_open_sync().await;
                });
                return;
            }
        }
        // no runtime/handle: finish synchronously as stale-offline
        let mut st = self.sync_state.lock().unwrap_or_else(|e| e.into_inner());
        st.till_open.state = "stale".into();
        st.till_open.stale_reason = Some("offline".into());
    }

    pub(crate) async fn run_till_open_sync(&self) {
        let _ = self.drain_outbox().await;
        let res = self.pull_incremental().await;
        let mut st = self.sync_state.lock().unwrap_or_else(|e| e.into_inner());
        st.till_open.finished_at = Some(chrono::Utc::now().to_rfc3339());
        match res {
            Ok(n) => {
                st.till_open.state = "done".into();
                st.till_open.changes_applied = n;
                st.till_open.stale_reason = None;
            }
            Err(e) => {
                st.till_open.state = "stale".into();
                st.till_open.stale_reason = Some(if net::is_connectivity_failure(&e) {
                    "offline".into()
                } else {
                    "http_error".into()
                });
            }
        }
    }

    /// Requeue one till's dead ops (G4) and try to send now.
    pub async fn retry_till_outbox(&self, till_id: String) -> Result<u32, CoreError> {
        let n = self.store.requeue_dead_for_till(&till_id)?;
        let _ = self.drain_outbox().await;
        Ok(n)
    }

    /// Translate a queued open (legacy `open_shift` or new) into the new command.
    pub(crate) fn translate_open_till(
        &self,
        item: &store::OutboxItem,
    ) -> Result<till::OpenTillCommand, serde_json::Error> {
        let mut cmd: till::OpenTillCommand = serde_json::from_str(&item.payload)?;
        if cmd.device_id.is_empty() {
            cmd.device_id = self.lan_device_id();
        }
        if cmd.device_code.is_empty() {
            cmd.device_code = checkout::device_code_or_default(&self.store);
        }
        if cmd.verification.is_empty() {
            cmd.verification = "unverified".into();
        }
        if cmd.request.device_id.flatten().is_none() {
            cmd.request.device_id = uuid::Uuid::parse_str(&cmd.device_id).ok().map(Some);
        }
        if cmd.request.verification.flatten().is_none() {
            cmd.request.verification = Some(Some(till::verification_wire(&cmd.verification)));
        }
        Ok(cmd)
    }
}
