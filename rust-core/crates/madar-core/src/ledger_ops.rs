//! The money screens' reads on `MadarCore`, routed by the `ledger` read-path
//! flag (`readpath.rs`): `new` reads the ledger rows only; `shadow` serves the
//! legacy read and logs where the rows disagree; `legacy` is the pre-B read.
//!
//! The one network call left near a read is for data the device does not hold
//! at all — a past till from before this device's first snapshot, a sale's lines
//! never seen here. It fetches ONCE into rows, and the read is still local.

use madar_api::apis::{orders_api, tills_api};

use crate::error::CoreError;
use crate::ledger::views;
use crate::readpath::{self, ReadPathMode};
use crate::{changes, orders, till, MadarCore};

impl MadarCore {
    fn ledger_mode(&self) -> ReadPathMode {
        readpath::mode(&self.store, "ledger")
    }

    fn online(&self) -> bool {
        self.current_session().map(|s| s.online).unwrap_or(false)
    }

    /// Fill a till this device does not hold completely with the server's rows
    /// (online only; a no-op for a complete till). The read stays local.
    async fn ensure_till_rows(&self, till_id: &str) {
        if views::till_complete(&self.store, till_id) || !self.online() {
            return;
        }
        let Ok(branch) = self.session_branch_id() else { return };
        if let Some(list) = self.fetch_shift_order_models(&branch, till_id).await {
            let rows: Vec<serde_json::Value> = list
                .iter()
                .filter_map(|o| serde_json::to_value(o).ok())
                .map(|mut v| {
                    v["till_id"] = serde_json::json!(till_id);
                    v
                })
                .collect();
            let _ = views::store_fetched_orders(&self.store, &rows);
        }
    }

    /// The current till's sales — queued, failed and synced — newest first.
    pub async fn list_till_orders(&self) -> Result<Vec<orders::OrderSummaryView>, CoreError> {
        let mode = self.ledger_mode();
        if mode == ReadPathMode::Legacy {
            return self.legacy_list_till_orders().await;
        }
        let t = till::current(&self.store)?.ok_or_else(|| CoreError::Validation {
            field: "shift".into(),
            detail: "no shift".into(),
        })?;
        self.ensure_till_rows(&t.id).await;
        let new = views::till_orders(&self.store, &t.id)?;
        if mode == ReadPathMode::Shadow {
            let legacy = self.legacy_list_till_orders().await?;
            self.report_divergence(
                "ledger",
                readpath::diff_keyed("till orders", &readpath::orders_keyed(&legacy), &readpath::orders_keyed(&new)),
            );
            return Ok(legacy);
        }
        Ok(new)
    }

    /// A past till's sales (the history expansion).
    pub async fn list_orders_for_till(&self, till_id: String) -> Result<Vec<orders::OrderSummaryView>, CoreError> {
        let mode = self.ledger_mode();
        if mode == ReadPathMode::Legacy {
            return self.legacy_list_orders_for_till(till_id).await;
        }
        self.ensure_till_rows(&till_id).await;
        let new = views::till_orders(&self.store, &till_id)?;
        if mode == ReadPathMode::Shadow {
            let legacy = self.legacy_list_orders_for_till(till_id).await?;
            self.report_divergence(
                "ledger",
                readpath::diff_keyed("till orders", &readpath::orders_keyed(&legacy), &readpath::orders_keyed(&new)),
            );
            return Ok(legacy);
        }
        Ok(new)
    }

    /// A sale's full record: stored locally (every sale this device rang, every
    /// sale in the feed's window), else fetched once and stored.
    pub(crate) async fn order_full_for(&self, order_id: &str) -> Result<madar_api::models::OrderFull, CoreError> {
        if self.ledger_mode() != ReadPathMode::Legacy {
            if let Some(full) = views::order_full(&self.store, order_id)? {
                return Ok(full);
            }
            if self.online() {
                if let Ok(o) = orders_api::get_order(
                    &self.api.config(),
                    orders_api::GetOrderParams { order_id: order_id.to_string() },
                )
                .await
                {
                    crate::timefmt::remember_tz(&self.store, o.timezone.as_deref().unwrap_or(""));
                    if let Ok(v) = serde_json::to_value(&o) {
                        let _ = self.store.with_conn(|c| crate::ledger::fold::put_order_detail(c, order_id, &v));
                    }
                    return Ok(o);
                }
            }
        }
        self.get_order_or_cache(order_id).await
    }

    /// The current till's Z report (drives the close count).
    pub async fn till_report(&self) -> Result<till::TillReportView, CoreError> {
        let mode = self.ledger_mode();
        if mode == ReadPathMode::Legacy {
            return self.legacy_till_report().await;
        }
        let t = till::current(&self.store)?.ok_or_else(|| CoreError::Validation {
            field: "till".into(),
            detail: "no till".into(),
        })?;
        let label = |m: &str| self.payment_method_label(m.to_string());
        let Some(new) = views::till_report(&self.store, &t.id, &label)? else {
            // Not held completely yet (the first snapshot has not landed): the
            // pre-B report, server figures plus the queue, is the best there is.
            return self.legacy_till_report().await;
        };
        let new = self.with_server_authority(&t.id, new);
        if mode == ReadPathMode::Shadow {
            let legacy = self.legacy_till_report().await?;
            self.report_divergence(
                "ledger",
                readpath::diff_keyed("till report", &readpath::report_keyed(&legacy), &readpath::report_keyed(&new)),
            );
            return Ok(legacy);
        }
        Ok(new)
    }

    /// Any till's Z report (the history reprint).
    pub async fn till_report_for(&self, till_id: String) -> Result<till::TillReportView, CoreError> {
        let mode = self.ledger_mode();
        if mode == ReadPathMode::Legacy {
            return self.legacy_till_report_for(till_id).await;
        }
        let label = |m: &str| self.payment_method_label(m.to_string());
        let new = match views::till_report(&self.store, &till_id, &label)? {
            Some(v) => v,
            None => {
                // A till the device does not hold completely: the server's report,
                // stored as a row for the next offline read.
                if self.online() {
                    if let Ok(report) = tills_api::get_till_report(
                        &self.api.config(),
                        tills_api::GetTillReportParams { till_id: till_id.clone() },
                    )
                    .await
                    {
                        crate::timefmt::remember_payload_tz(&self.store, &Some(report.timezone.clone()));
                        let _ = views::put_till_report(&self.store, &till_id, &report);
                    }
                }
                match views::stored_till_report(&self.store, &till_id) {
                    Some(report) => till::cached_report_view(&report, 0, Vec::new(), &label),
                    None => return self.legacy_till_report_for(till_id).await,
                }
            }
        };
        let new = if views::till_complete(&self.store, &till_id) { self.with_server_authority(&till_id, new) } else { new };
        if mode == ReadPathMode::Shadow {
            let legacy = self.legacy_till_report_for(till_id).await?;
            self.report_divergence(
                "ledger",
                readpath::diff_keyed("till report", &readpath::report_keyed(&legacy), &readpath::report_keyed(&new)),
            );
            return Ok(legacy);
        }
        Ok(new)
    }

    /// The current till's drawer movements.
    pub async fn list_cash_movements(&self) -> Result<Vec<till::CashMovementView>, CoreError> {
        let mode = self.ledger_mode();
        if mode == ReadPathMode::Legacy {
            return self.legacy_list_cash_movements().await;
        }
        let t = till::current(&self.store)?.ok_or_else(|| CoreError::Validation {
            field: "till".into(),
            detail: "no till".into(),
        })?;
        if !views::till_complete(&self.store, &t.id) {
            return self.legacy_list_cash_movements().await;
        }
        let new = views::cash_movements(&self.store, &t.id)?;
        if mode == ReadPathMode::Shadow {
            let legacy = self.legacy_list_cash_movements().await?;
            self.report_divergence(
                "ledger",
                readpath::diff_keyed("cash movements", &readpath::cash_keyed(&legacy), &readpath::cash_keyed(&new)),
            );
            return Ok(legacy);
        }
        Ok(new)
    }

    /// What closing will check: every method used, the cash line carrying the
    /// drawer — computed from the rows, so it is the same figure offline.
    pub async fn close_till_preview(&self) -> Result<till::CloseTillPreviewView, CoreError> {
        let mode = self.ledger_mode();
        if mode == ReadPathMode::Legacy {
            return self.legacy_close_till_preview().await;
        }
        let t = till::current(&self.store)?.filter(|t| t.is_open).ok_or_else(|| CoreError::Validation {
            field: "till".into(),
            detail: "no open till".into(),
        })?;
        if !views::till_complete(&self.store, &t.id) {
            return self.legacy_close_till_preview().await;
        }
        let label = |m: &str| self.payment_method_label(m.to_string());
        let Some((expected, methods, confirmed)) = views::close_methods(&self.store, &t.id, &label)? else {
            return self.legacy_close_till_preview().await;
        };
        let lan_others = self
            .lan
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
            .map(|r| r.branch_open_tills().iter().filter(|(_, bt)| bt.till_id != t.id).count())
            .unwrap_or(0);
        let others = views::other_open_tills(&self.store, &t.branch_id, &t.id)? + lan_others;
        let notice = self.local_open_bills_notice(&t.branch_id);
        let warning = till::last_till_warning(
            others,
            notice.as_ref().map(|n| n.open_bills_count).unwrap_or(0),
            notice.as_ref().map(|n| n.open_bills_amount_minor).unwrap_or(0),
            notice.as_ref().map(|n| n.seated_tables_count).unwrap_or(0),
        );
        let authority = matches!(views::server_authority(&self.store, &t.id), Ok(Some(_)));
        let new = till::CloseTillPreviewView {
            till: t,
            expected_cash_minor: expected,
            methods,
            last_till_warning: warning,
            // The figures are this device's; they are the server's only when the
            // stored server report is the authority for the till.
            from_server: confirmed && authority,
        };
        if mode == ReadPathMode::Shadow {
            let legacy = self.legacy_close_till_preview().await?;
            let key = |p: &till::CloseTillPreviewView| {
                let mut m: std::collections::BTreeMap<String, i64> =
                    p.methods.iter().map(|x| (x.method.clone(), x.system_total_minor)).collect();
                m.insert("expected_cash".into(), p.expected_cash_minor);
                m
            };
            self.report_divergence("ledger", readpath::diff_keyed("close preview", &key(&legacy), &key(&new)));
            return Ok(legacy);
        }
        Ok(new)
    }

    /// Past tills at the branch, newest first.
    pub async fn list_tills(&self) -> Result<Vec<till::TillSummaryView>, CoreError> {
        let mode = self.ledger_mode();
        if mode == ReadPathMode::Legacy {
            return self.legacy_list_tills().await;
        }
        let branch = self.session_branch_id()?;
        let new = views::tills(&self.store, &branch)?;
        if mode == ReadPathMode::Shadow {
            let legacy = self.legacy_list_tills().await?;
            // The legacy list is the server's first page; compare what both hold.
            let l = readpath::tills_keyed(&legacy);
            let n: std::collections::BTreeMap<_, _> =
                readpath::tills_keyed(&new).into_iter().filter(|(k, _)| l.contains_key(k)).collect();
            self.report_divergence("ledger", readpath::diff_keyed("tills", &l, &n));
            return Ok(legacy);
        }
        Ok(new)
    }

    /// What has been given back against one sale.
    pub async fn list_order_refunds(&self, order_id: String) -> Result<orders::OrderRefundsView, CoreError> {
        let mode = self.ledger_mode();
        if mode == ReadPathMode::Legacy {
            return self.legacy_list_order_refunds(order_id).await;
        }
        let Some(new) = views::order_refunds(&self.store, &order_id)? else {
            return self.legacy_list_order_refunds(order_id).await;
        };
        if mode == ReadPathMode::Shadow {
            let legacy = self.legacy_list_order_refunds(order_id).await?;
            let key = |v: &orders::OrderRefundsView| {
                [("refunded".to_string(), v.refunded_minor), ("remaining".to_string(), v.refundable_remaining_minor)]
                    .into_iter()
                    .collect::<std::collections::BTreeMap<_, _>>()
            };
            self.report_divergence("ledger", readpath::diff_keyed("order refunds", &key(&legacy), &key(&new)));
            return Ok(legacy);
        }
        Ok(new)
    }

    /// Every refund issued from a till's drawer.
    pub async fn list_till_refunds(&self, till_id: String) -> Result<orders::TillRefundsView, CoreError> {
        let mode = self.ledger_mode();
        if mode == ReadPathMode::Legacy || !views::till_complete(&self.store, &till_id) {
            return self.legacy_list_till_refunds(till_id).await;
        }
        let new = views::till_refunds(&self.store, &till_id)?;
        if mode == ReadPathMode::Shadow {
            let legacy = self.legacy_list_till_refunds(till_id).await?;
            let key = |v: &orders::TillRefundsView| {
                [("count".to_string(), v.refund_count), ("refunded".to_string(), v.refunded_minor)]
                    .into_iter()
                    .collect::<std::collections::BTreeMap<_, _>>()
            };
            self.report_divergence("ledger", readpath::diff_keyed("till refunds", &key(&legacy), &key(&new)));
            return Ok(legacy);
        }
        Ok(new)
    }

    /// The open-bills notice from the synced rows only (no network).
    pub(crate) fn local_open_bills_notice(&self, branch: &str) -> Option<till::OpenBillsNoticeView> {
        let bills: Vec<till::LocalBill> = crate::sync_pull::rows_of_type(&self.store, branch, "open_ticket")
            .into_iter()
            .filter(|t| t.get("status").and_then(|s| s.as_str()) == Some("open"))
            .map(|t| till::LocalBill {
                opened_at: t.get("opened_at").and_then(|s| s.as_str()).unwrap_or("").to_string(),
                amount_minor: t.get("subtotal").and_then(|s| s.as_i64()).unwrap_or(0),
            })
            .collect();
        let seated = self
            .floor_layout()
            .map(|l| l.tables.iter().filter(|t| t.status == "seated").count() as i64)
            .unwrap_or(0);
        let hours = crate::sync_pull::old_bill_hours(&self.store, branch);
        till::local_open_bills_notice(&bills, seated, hours, None, chrono::Utc::now())
    }

    /// Once per branch, after its first complete snapshot: bring the past tills
    /// the snapshot window does not reach into rows (the history list and its
    /// reprints then work offline). Online, best-effort, never blocks.
    pub(crate) async fn backfill_till_history(&self, branch: &str) {
        let flag = format!("ledger:history_backfilled:{branch}");
        if self.store.kv_get(&flag).ok().flatten().is_some() {
            return;
        }
        let Ok(page) = tills_api::list_tills(
            &self.api.config(),
            tills_api::ListTillsParams {
                branch_id: branch.to_string(),
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
        else {
            return;
        };
        let _ = self.store.with_tx_touch(|tx, touched| {
            use crate::ledger::{self as l, T_TILL};
            for t in &page.data {
                let id = t.id.to_string();
                if l::stored(tx, T_TILL, &id)?.is_some() {
                    continue;
                }
                let v = serde_json::to_value(till::TillRecord::from_api(t))?;
                l::write_row(tx, T_TILL, &id, &v, l::Origin::Fetch, None)?;
            }
            touched.push(changes::TILLS);
            Ok(())
        });
        let _ = self.store.kv_put(&flag, &chrono::Utc::now().to_rfc3339());
    }

    /// Production money parity (OFFLINE_B_DESIGN §7): when the current till is
    /// held completely and nothing of it is on its way, the device's figures must
    /// be the server's. At most once every [`PARITY_EVERY_MS`], online, after a
    /// pull; a difference is logged (diagnostics + Sentry, amounts only) and the
    /// server's report is stored for the till.
    /// Serve the server's report when it is the authority for this till
    /// (`views::server_authority`), logging every field where the device's own
    /// figures differ; otherwise the local report, and ask for a fresh server
    /// report in the background so the authority can be established.
    pub(crate) fn with_server_authority(&self, till_id: &str, local: till::TillReportView) -> till::TillReportView {
        let label = |m: &str| self.payment_method_label(m.to_string());
        match views::server_authority(&self.store, till_id) {
            Ok(Some(report)) => {
                let server = till::report_view(&report, 0, &label);
                self.report_divergence(
                    "money",
                    readpath::diff_keyed(
                        &format!("till {till_id} server vs local"),
                        &readpath::report_keyed(&server),
                        &readpath::report_keyed(&local),
                    ),
                );
                server
            }
            _ => {
                self.refresh_server_report_soon(till_id);
                local
            }
        }
    }

    /// Fetch and store the server's report for a till in the background (online,
    /// at most every [`SERVER_REPORT_EVERY_MS`] per till); a new one re-reads the
    /// till screens.
    fn refresh_server_report_soon(&self, till_id: &str) {
        if !self.online() || self.scheduler.manual.load(std::sync::atomic::Ordering::SeqCst) {
            return;
        }
        let key = format!("{K_REPORT_ASKED}{till_id}");
        let now = chrono::Utc::now().timestamp_millis();
        let last = self.store.kv_get(&key).ok().flatten().and_then(|v| v.parse::<i64>().ok()).unwrap_or(0);
        if now - last < SERVER_REPORT_EVERY_MS {
            return;
        }
        let _ = self.store.kv_put(&key, &now.to_string());
        let (Some(me), Ok(handle)) = (self.self_arc(), tokio::runtime::Handle::try_current()) else { return };
        let till_id = till_id.to_string();
        handle.spawn(async move {
            if let Ok(report) =
                tills_api::get_till_report(&me.api.config(), tills_api::GetTillReportParams { till_id: till_id.clone() }).await
            {
                if views::put_till_report(&me.store, &till_id, &report).is_ok() {
                    me.store.emit_changes([changes::TILLS]);
                }
            }
        });
    }

    pub(crate) async fn money_parity_check(&self) {
        let now = chrono::Utc::now().timestamp_millis();
        let last = self
            .store
            .kv_get(K_PARITY_AT)
            .ok()
            .flatten()
            .and_then(|v| v.parse::<i64>().ok())
            .unwrap_or(0);
        if now - last < PARITY_EVERY_MS || !self.online() {
            return;
        }
        let _ = self.store.kv_put(K_PARITY_AT, &now.to_string());
        for till_id in views::tills_to_check(&self.store).unwrap_or_default() {
            self.parity_check_till(&till_id).await;
        }
    }

    /// Compare one till's report field by field with the server's, storing the
    /// server's (so `with_server_authority` serves it whenever it is the
    /// authority). Returns the divergence lines (tests read them).
    pub(crate) async fn parity_check_till(&self, till_id: &str) -> Vec<String> {
        let label = |m: &str| self.payment_method_label(m.to_string());
        let ready = |store: &crate::store::Store| {
            views::figures(store, till_id).ok().flatten().is_some_and(|f| f.complete && f.unsynced == 0 && f.unconfirmed == 0)
        };
        if !ready(&self.store) {
            return Vec::new();
        }
        let Ok(report) =
            tills_api::get_till_report(&self.api.config(), tills_api::GetTillReportParams { till_id: till_id.to_string() }).await
        else {
            return Vec::new();
        };
        let _ = views::put_till_report(&self.store, till_id, &report);
        // The feed may have moved while the report was computed: compare only
        // when the report is the authority for what the device now holds.
        if !matches!(views::server_authority(&self.store, till_id), Ok(Some(_))) {
            return Vec::new();
        }
        let Ok(Some(local)) = views::till_report(&self.store, till_id, &label) else { return Vec::new() };
        let server = till::report_view(&report, 0, &label);
        let lines = readpath::diff_keyed(
            &format!("till {till_id} server vs local"),
            &readpath::report_keyed(&server),
            &readpath::report_keyed(&local),
        );
        self.report_divergence("money", lines.clone());
        if !lines.is_empty() {
            self.store.emit_changes([changes::TILLS]);
        }
        lines
    }
}

const K_PARITY_AT: &str = "ledger:parity_checked_at";
const K_REPORT_ASKED: &str = "ledger:report_asked:";
/// How often a till screen may ask the server for a fresh report.
pub(crate) const SERVER_REPORT_EVERY_MS: i64 = 30_000;
/// How often the production parity guard asks the server.
pub(crate) const PARITY_EVERY_MS: i64 = 10 * 60 * 1000;
