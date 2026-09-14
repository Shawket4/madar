//! The till lifecycle on `MadarCore` (TILLS_CONTRACT §4.5–§4.8): open with server /
//! LAN verification and an unverified fallback, cash, close with per-method
//! reconciliation, force-close, reports, lists, and the device identity.

use madar_api::apis::{devices_api, tills_api};
use madar_api::models;

use crate::error::CoreError;
use crate::till::{self, TillRecord, TillView};
use crate::{cached_views, cache_views, cash_i32, checkout, net, store, till_views, MadarCore};

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

    async fn fetch_prefill(&self, branch: &str) -> Result<models::TillPreFill, CoreError> {
        tills_api::get_current_till(
            &self.api.config(),
            tills_api::GetCurrentTillParams {
                branch_id: branch.to_string(),
                teller_id: None,
            },
        )
        .await
        .map_err(net::map_api_error)
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

    pub fn current_till(&self) -> Result<Option<TillView>, CoreError> {
        till::current(&self.store)
    }

    pub fn suggested_opening_cash_minor(&self) -> Result<i64, CoreError> {
        till::suggested_opening_cash(&self.store)
    }

    /// Is the signed-in person's till open on ANOTHER device? Server when online,
    /// else live LAN peers; `None` when neither can tell or it is not.
    pub async fn check_till_elsewhere(&self) -> Result<Option<till::TillElsewhereView>, CoreError> {
        let sp = self.session_parts()?;
        let dev = self.lan_device_id();
        let server = if sp.online {
            self.server_prefill(&sp.branch_id, &sp.user_id).await
        } else {
            None
        };
        let (sighting, peers) = self.lan_person_sighting(&sp.user_id);
        Ok(match till::decide_open(server.as_ref(), &dev, sighting.as_ref(), peers) {
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

    /// Reconcile the person's till with `/tills/.../current` (online).
    pub async fn refresh_till(&self) -> Result<Option<TillView>, CoreError> {
        let sp = self.session_parts()?;
        if sp.role != "teller" {
            return Ok(None);
        }
        let pf = self.fetch_prefill(&sp.branch_id).await?;
        if self.store.pending_count().map(|n| n == 0).unwrap_or(false) {
            let s = pf
                .last_close_declared
                .flatten()
                .unwrap_or(pf.suggested_opening_cash) as i64;
            if s > 0 {
                till::cache_suggested_opening_cash(&self.store, s)?;
            }
        }
        let local = till::current(&self.store)?;
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
        match till::reconcile(&pf, &self.lan_device_id(), local.as_ref(), open_pending, close_pending) {
            till::TillReconcile::Adopt(t) => {
                till::save(&self.store, &t)?;
                self.lan_sync_open_tills();
                Ok(Some(till::view_from(&t)))
            }
            till::TillReconcile::KeepLocal => Ok(local),
            till::TillReconcile::Clear => {
                till::clear(&self.store)?;
                self.lan_sync_open_tills();
                Ok(None)
            }
        }
    }

    /// Bills left open at the branch (`None` when zero).
    pub async fn open_bills_notice(&self) -> Result<Option<till::OpenBillsNoticeView>, CoreError> {
        let sp = self.session_parts()?;
        // With the bills in the synced rows the notice is computed here, like the
        // close preview's; the server is asked only before the first snapshot.
        let from_rows = crate::readpath::mode(&self.store, "tickets") != crate::readpath::ReadPathMode::Legacy
            && self.pull_feed_complete(&sp.branch_id);
        if sp.online && !from_rows {
            if let Ok(w) = tills_api::get_open_bills_notice(
                &self.api.config(),
                tills_api::GetOpenBillsNoticeParams {
                    branch_id: sp.branch_id.clone(),
                },
            )
            .await
            {
                return Ok(till::open_bills_notice_view(&w));
            }
        }
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
        let _ = self.drain_outbox().await;
        Ok(till::CashMovementView {
            id: client_ref.to_string(),
            kind: till_views::movement_kind(kind.as_deref(), amount_minor),
            amount_minor,
            note,
            moved_by_name: self.current_session().map(|s| s.display_name).unwrap_or_default(),
            created_at: created_at.to_rfc3339(),
        })
    }

    pub(crate) async fn legacy_list_cash_movements(&self) -> Result<Vec<till::CashMovementView>, CoreError> {
        let t = till::current(&self.store)?.ok_or_else(|| CoreError::Validation {
            field: "till".into(),
            detail: "no till".into(),
        })?;
        let teller = self.current_session().map(|s| s.display_name).unwrap_or_default();
        let queued: Vec<till::CashMovementView> = self
            .store
            .list_active_for_till(&t.id)?
            .into_iter()
            .filter(|i| i.op_type == "cash_movement")
            .filter_map(|i| {
                serde_json::from_str::<till::CashMovementCommand>(&i.payload)
                    .ok()
                    .map(|cmd| till::CashMovementView {
                        id: i.id.clone(),
                        kind: till_views::movement_kind(
                            cmd.request.kind.flatten().map(|k| k.to_string()).as_deref(),
                            cmd.request.amount as i64,
                        ),
                        amount_minor: cmd.request.amount as i64,
                        note: cmd.request.note,
                        moved_by_name: teller.clone(),
                        created_at: i.event_at.clone(),
                    })
            })
            .collect();
        let key = format!("cache:cash:{}", t.id);
        let online = self.current_session().map(|s| s.online).unwrap_or(false);
        let server: Vec<till::CashMovementView> = if online {
            match tills_api::list_cash_movements(
                &self.api.config(),
                tills_api::ListCashMovementsParams { till_id: t.id.clone() },
            )
            .await
            {
                Ok(list) => {
                    let v: Vec<_> = list.iter().map(till::cash_movement_view).collect();
                    cache_views(&self.store, &key, &v);
                    v
                }
                Err(_) => cached_views(&self.store, &key),
            }
        } else {
            cached_views(&self.store, &key)
        };
        Ok(till::merge_cash_for_view(server, queued))
    }

    /// Queued (not yet synced) sales of a till, per method: (method, is_cash, total, count).
    fn queued_by_method(&self, till_id: &str) -> Vec<(String, bool, i64, i64)> {
        let methods = crate::menu::cached_payment_methods(&self.store).unwrap_or_default();
        let is_cash = |name: &str| methods.iter().any(|m| m.name == name && m.is_cash);
        let mut out: Vec<(String, bool, i64, i64)> = Vec::new();
        let mut add = |m: String, t: i64| {
            let c = is_cash(&m);
            match out.iter_mut().find(|r| r.0 == m) {
                Some(r) => {
                    r.2 += t;
                    r.3 += 1;
                }
                None => out.push((m, c, t, 1)),
            }
        };
        for i in self.store.list_active_for_till(till_id).unwrap_or_default() {
            if i.op_type != "create_order" || i.status == "dead" {
                continue;
            }
            let Ok(cmd) = serde_json::from_str::<checkout::CheckoutCommand>(&i.payload) else {
                continue;
            };
            let total = cmd.request.total_amount.flatten().unwrap_or(0) as i64;
            match cmd.request.payment_splits.clone().flatten() {
                Some(legs) if !legs.is_empty() => {
                    for l in legs {
                        add(l.method.clone(), l.amount as i64);
                    }
                }
                _ => add(cmd.request.payment_method.clone(), total),
            }
        }
        out
    }

    /// What closing will check (online: server; offline: local computation).
    pub(crate) async fn legacy_close_till_preview(&self) -> Result<till::CloseTillPreviewView, CoreError> {
        let t = self.open_till_or_err()?;
        let label = self.method_label_fn();
        if self.current_session().map(|s| s.online).unwrap_or(false) {
            if let Ok(p) = tills_api::close_preview(
                &self.api.config(),
                tills_api::ClosePreviewParams { till_id: t.id.clone() },
            )
            .await
            {
                let mut methods = till::preview_methods_from_api(&p.methods, &label);
                // add still-queued sales the server has not seen
                for (m, c, tot, n) in self.queued_by_method(&t.id) {
                    match methods.iter_mut().find(|r| r.method == m) {
                        Some(r) => {
                            r.system_total_minor += tot;
                            r.order_count += n;
                        }
                        None => methods.push(till::CloseTillMethodView {
                            label: label(&m),
                            method: m,
                            is_cash: c,
                            system_total_minor: tot,
                            order_count: n,
                        }),
                    }
                }
                let queued_cash = checkout::queued_cash_total_for(&self.store, &t.id).unwrap_or(0);
                let expected = p.expected_cash + queued_cash;
                if let Some(c) = methods.iter_mut().find(|m| m.is_cash) {
                    c.system_total_minor = expected;
                }
                return Ok(till::CloseTillPreviewView {
                    till: t,
                    expected_cash_minor: expected,
                    methods,
                    last_till_warning: p
                        .last_till_warning
                        .as_ref()
                        .and_then(|w| w.as_deref())
                        .and_then(till::last_till_warning_from_api),
                    from_server: true,
                });
            }
        }
        let report = self.legacy_till_report().await?;
        let methods = till::offline_preview_methods(&report, &self.queued_by_method(&t.id), &label);
        let others = self
            .lan
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
            .map(|r| r.branch_open_tills().len())
            .unwrap_or(1)
            + till::open_on_device(&self.store)
                .iter()
                .filter(|o| o.id != t.id)
                .count();
        let notice = self.open_bills_notice().await.ok().flatten();
        let warning = till::last_till_warning(
            others,
            notice.as_ref().map(|n| n.open_bills_count).unwrap_or(0),
            notice.as_ref().map(|n| n.open_bills_amount_minor).unwrap_or(0),
            notice.as_ref().map(|n| n.seated_tables_count).unwrap_or(0),
        );
        Ok(till::CloseTillPreviewView {
            expected_cash_minor: report.expected_cash_minor,
            till: t,
            methods,
            last_till_warning: warning,
            from_server: false,
        })
    }

    /// Close the person's till (never blocked). Queues `close_till` with the
    /// per-method reconciliation.
    pub async fn close_till(
        &self,
        closing_cash_minor: i64,
        cash_note: Option<String>,
        reconciliation: Vec<till::ReconciliationInput>,
    ) -> Result<till::CloseTillOutcomeView, CoreError> {
        let t = self.open_till_or_err()?;
        let inputs = till::reconciliation_wire(&reconciliation)?;
        let preview = self.close_till_preview().await.ok();
        let closed_at = self.corrected_now().fixed_offset();
        let dev = self.lan_device_id();
        let cash_note = cash_note.filter(|n| !n.trim().is_empty());
        let request = models::CloseTillRequest {
            closing_cash_declared: cash_i32(closing_cash_minor, "closing_cash")?,
            cash_note: cash_note.clone().map(Some),
            closed_at: Some(Some(closed_at)),
            device_id: uuid::Uuid::parse_str(&dev).ok().map(Some),
            reconciliation: Some(Some(inputs.clone())),
        };
        crate::cart::clear_all(&self.store)?;
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
        let _ = self.drain_outbox().await;
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

    /// The current till's report (drives the close count).
    pub(crate) async fn legacy_till_report(&self) -> Result<till::TillReportView, CoreError> {
        let t = till::current(&self.store)?.ok_or_else(|| CoreError::Validation {
            field: "till".into(),
            detail: "no till".into(),
        })?;
        let queued_cash = checkout::queued_cash_total_for(&self.store, &t.id)?;
        let label = self.method_label_fn();
        if self.current_session().map(|s| s.online).unwrap_or(false) {
            if let Ok(report) = tills_api::get_till_report(
                &self.api.config(),
                tills_api::GetTillReportParams { till_id: t.id.clone() },
            )
            .await
            {
                crate::timefmt::remember_payload_tz(&self.store, &Some(report.timezone.clone()));
                till::cache_report(&self.store, &t.id, &report);
                return Ok(till::report_view(&report, queued_cash, &label));
            }
        }
        let teller = self.current_session().map(|s| s.display_name).unwrap_or_default();
        let movements: Vec<till::TillReportCashLine> = self
            .store
            .list_active_for_till(&t.id)?
            .into_iter()
            .filter(|i| i.op_type == "cash_movement")
            .filter_map(|i| {
                serde_json::from_str::<till::CashMovementCommand>(&i.payload)
                    .ok()
                    .map(|cmd| till::TillReportCashLine {
                        amount_minor: cmd.request.amount as i64,
                        note: cmd.request.note,
                        moved_by_name: teller.clone(),
                        created_at: i.event_at.clone(),
                    })
            })
            .collect();
        let mut v = match till::cached_report(&self.store, &t.id) {
            Some(report) => till::cached_report_view(&report, queued_cash, movements, &label),
            None => till::offline_report_view(
                t.opening_cash_minor,
                queued_cash,
                movements,
                t.teller_name.clone(),
                t.opened_at.clone(),
                chrono::Utc::now().to_rfc3339(),
            ),
        };
        v.device_code = v.device_code.or(t.device_code.clone());
        v.verification = t.verification.clone();
        v.opened_while_another_open = t.opened_while_another_open;
        Ok(v)
    }

    /// Past tills for this branch, newest first.
    pub(crate) async fn legacy_list_tills(&self) -> Result<Vec<till::TillSummaryView>, CoreError> {
        let sp = self.session_parts()?;
        const KEY: &str = "cache:tills";
        let mut views: Vec<till::TillSummaryView> = if sp.online {
            match tills_api::list_tills(
                &self.api.config(),
                tills_api::ListTillsParams {
                    branch_id: sp.branch_id.clone(),
                    status: None,
                    teller_id: None,
                    device_id: None,
                    flagged: None,
                    from: None,
                    to: None,
                    page: None,
                    per_page: None,
                },
            )
            .await
            {
                Ok(page) => {
                    let out: Vec<_> = page
                        .data
                        .iter()
                        .map(|t| till::till_summary_view(&TillRecord::from_api(t)))
                        .collect();
                    cache_views(&self.store, KEY, &out);
                    out
                }
                Err(_) => cached_views(&self.store, KEY),
            }
        } else {
            cached_views(&self.store, KEY)
        };
        let overlay = till::queued_close_overlay(&self.store);
        for v in views.iter_mut() {
            if let Some((closed_at, declared)) = overlay.get(&v.id) {
                v.is_open = false;
                v.status = "closed".into();
                v.closed_at = v.closed_at.clone().or(closed_at.clone());
                v.closing_declared_minor = v.closing_declared_minor.or(Some(*declared));
            }
        }
        let ids: std::collections::HashSet<String> = views.iter().map(|v| v.id.clone()).collect();
        for l in till::local_tills(&self.store) {
            if !ids.contains(&l.id) {
                views.push(l);
            }
        }
        views.sort_by(|a, b| b.opened_at.cmp(&a.opened_at));
        Ok(views)
    }

    /// Tills open at the branch: server list ∪ LAN adverts ∪ this device.
    pub async fn branch_open_tills(&self) -> Result<Vec<till::BranchOpenTillView>, CoreError> {
        let sp = self.session_parts()?;
        let dev = self.lan_device_id();
        let mut out: Vec<till::BranchOpenTillView> = Vec::new();
        if sp.online {
            if let Ok(list) = tills_api::list_open_tills(
                &self.api.config(),
                tills_api::ListOpenTillsParams {
                    branch_id: sp.branch_id.clone(),
                },
            )
            .await
            {
                for t in list.iter().map(TillRecord::from_api) {
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
            }
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
