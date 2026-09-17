//! The money screens' reads on `MadarCore`: the ledger rows, and nothing else.
//!
//! No read here waits on the network. A read returns what this device holds at
//! once; when the device does not hold a till completely (a past till from
//! before its first snapshot, a till opened on another device that has not been
//! pulled yet) the rows are filled IN THE BACKGROUND, under a short timeout, and
//! a table change re-reads the screen. The one exception is a sale this device
//! has never seen (its detail, its refunds): there is nothing local to show, so
//! it is fetched online under [`FETCH_TIMEOUT`] or refused offline.

use std::time::Duration;

use madar_api::apis::{orders_api, refunds_api, tills_api};

use crate::error::CoreError;
use crate::ledger::views;
use crate::{changes, net, orders, parity, till, MadarCore};

/// The longest a screen read's own network call may take: a sale never seen
/// here, and the reads that are online by nature (a points balance, a search
/// across tills). The HTTP client's own limit is 20 s; no screen waits that.
pub(crate) const FETCH_TIMEOUT: Duration = Duration::from_secs(5);

/// A screen read's network call under [`FETCH_TIMEOUT`]: the server's answer,
/// its error, or `Offline` when it did not answer in time.
pub(crate) async fn within<T, E>(
    call: impl std::future::Future<Output = Result<T, madar_api::apis::Error<E>>>,
) -> Result<T, CoreError> {
    match tokio::time::timeout(FETCH_TIMEOUT, call).await {
        Ok(r) => r.map_err(net::map_api_error),
        Err(_) => Err(CoreError::Offline { detail: "the server did not answer in time".into() }),
    }
}
/// The longest a background fill of a till may take before it is abandoned.
pub(crate) const FILL_TIMEOUT: Duration = Duration::from_secs(15);
/// How often one till may be filled in the background.
pub(crate) const FILL_EVERY_MS: i64 = 30_000;
const K_FILL_ASKED: &str = "ledger:fill_asked:";

impl MadarCore {
    fn online(&self) -> bool {
        self.current_session().map(|s| s.online).unwrap_or(false)
    }

    fn held_current_till(&self) -> Result<till::TillView, CoreError> {
        till::current(&self.store)?.ok_or_else(|| CoreError::Validation {
            field: "till".into(),
            detail: "no till".into(),
        })
    }

    /// Fill a till this device does not hold completely from the server — its
    /// sales and its report — in the background, abandoned after
    /// [`FILL_TIMEOUT`]. The screens re-read on the table change it emits. A
    /// no-op offline and for a complete till. A filled till is filled again only
    /// once the FEED has moved it since (a refund or a drawer movement against it
    /// arrived): an unchanged till is never asked twice. A failed fill may be
    /// tried again after [`FILL_EVERY_MS`], and only when a screen asks.
    pub(crate) fn fill_till_soon(&self, till_id: &str) {
        let newest = views::newest_seq(&self.store, till_id).unwrap_or(0);
        if views::till_complete(&self.store, till_id)
            || !self.online()
            || self.scheduler.manual.load(std::sync::atomic::Ordering::SeqCst)
            || self.branch_fills.till_filled(till_id, newest)
        {
            return;
        }
        let key = format!("{K_FILL_ASKED}{till_id}");
        let now = chrono::Utc::now().timestamp_millis();
        let last = self.store.kv_get(&key).ok().flatten().and_then(|v| v.parse::<i64>().ok()).unwrap_or(0);
        // The gate spaces RETRIES of a fill that failed; a till the feed moved
        // since its last good fill is filled again at once.
        if now - last < FILL_EVERY_MS && !self.branch_fills.till_ever_filled(till_id) {
            return;
        }
        let (Some(me), Ok(handle)) = (self.self_arc(), tokio::runtime::Handle::try_current()) else { return };
        if !self.branch_fills.begin_fill(till_id) {
            return;
        }
        let _ = self.store.kv_put(&key, &now.to_string());
        let till_id = till_id.to_string();
        handle.spawn(async move {
            // What the feed holds for the till as the fill starts: a move that
            // lands while it runs is newer, and asks for one more fill.
            let at = views::newest_seq(&me.store, &till_id).unwrap_or(0);
            if let Ok(true) = tokio::time::timeout(FILL_TIMEOUT, me.fill_till(&till_id)).await {
                me.branch_fills.mark_till_filled(&till_id, at);
            }
            me.branch_fills.end_fill(&till_id);
        });
    }

    /// The fill itself: every page of the till's sales into rows, and the
    /// server's report stored for it. `true` when both arrived.
    pub(crate) async fn fill_till(&self, till_id: &str) -> bool {
        let Ok(branch) = self.session_branch_id() else { return false };
        let mut done = true;
        if let Some(list) = self.fetch_shift_order_models(&branch, till_id).await {
            let rows: Vec<serde_json::Value> = list
                .iter()
                .filter_map(|o| serde_json::to_value(o).ok())
                .map(|mut v| {
                    v["till_id"] = serde_json::json!(till_id);
                    v
                })
                .collect();
            if views::store_fetched_orders(&self.store, &rows).is_ok() {
                self.store.emit_changes([changes::ORDERS]);
            }
        } else {
            done = false;
        }
        match tills_api::get_till_report(&self.api.config(), tills_api::GetTillReportParams { till_id: till_id.to_string() }).await
        {
            Ok(report) => {
                crate::timefmt::remember_payload_tz(&self.store, &Some(report.timezone.clone()));
                if views::put_till_report(&self.store, till_id, &report).is_ok() {
                    self.store.emit_changes([changes::TILLS]);
                }
            }
            Err(_) => done = false,
        }
        done
    }

    /// The current till's sales — queued, failed and synced — newest first.
    pub async fn list_till_orders(&self) -> Result<Vec<orders::OrderSummaryView>, CoreError> {
        let t = till::current(&self.store)?.ok_or_else(|| CoreError::Validation {
            field: "shift".into(),
            detail: "no shift".into(),
        })?;
        self.fill_till_soon(&t.id);
        views::till_orders(&self.store, &t.id)
    }

    /// A past till's sales (the history expansion).
    pub async fn list_orders_for_till(&self, till_id: String) -> Result<Vec<orders::OrderSummaryView>, CoreError> {
        self.fill_till_soon(&till_id);
        views::till_orders(&self.store, &till_id)
    }

    /// A sale's full record: stored locally (every sale this device rang, every
    /// sale in the feed's window, every sale opened here before), else fetched
    /// online under [`FETCH_TIMEOUT`] and stored. Offline, a sale never seen here
    /// has no record to show, and the error says so.
    pub(crate) async fn order_full_for(&self, order_id: &str) -> Result<madar_api::models::OrderFull, CoreError> {
        if let Some(full) = views::order_full(&self.store, order_id)? {
            return Ok(full);
        }
        let not_here = || CoreError::Offline {
            detail: "this sale is not on this device yet — open it once online".into(),
        };
        if !self.online() {
            return Err(not_here());
        }
        let config = self.api.config();
        let o = within(orders_api::get_order(&config, orders_api::GetOrderParams { order_id: order_id.to_string() })).await?;
        crate::timefmt::remember_tz(&self.store, o.timezone.as_deref().unwrap_or(""));
        if let Ok(v) = serde_json::to_value(&o) {
            let _ = self.store.with_conn(|c| crate::ledger::fold::put_order_detail(c, order_id, &v));
        }
        Ok(o)
    }

    /// The report a till's rows give, whether or not the device holds it all:
    /// the server's when it is the authority, the stored server report for a
    /// till not held completely, else what the rows add up to.
    fn report_now(&self, till_id: &str) -> Result<Option<till::TillReportView>, CoreError> {
        let label = |m: &str| self.payment_method_label(m.to_string());
        if views::till_complete(&self.store, till_id) {
            return Ok(views::till_report(&self.store, till_id, &label)?.map(|r| self.with_server_authority(till_id, r)));
        }
        self.fill_till_soon(till_id);
        if let Some(report) = views::stored_till_report(&self.store, till_id) {
            // The server's figures for a till not held here, plus what this
            // device has not sent yet (the server's copy cannot hold it). They
            // are the server's while online with nothing queued; otherwise they
            // are the last ones it gave.
            let queued_cash = crate::checkout::queued_cash_total_for(&self.store, till_id)?;
            let queued = self.queued_movement_lines(till_id)?;
            return Ok(Some(if self.online() && queued_cash == 0 && queued.is_empty() {
                till::report_view(&report, 0, &label)
            } else {
                till::cached_report_view(&report, queued_cash, queued, &label)
            }));
        }
        views::till_report_rows(&self.store, till_id, &label)
    }

    /// Drawer movements of a till still in the outbox, as report lines.
    fn queued_movement_lines(&self, till_id: &str) -> Result<Vec<till::TillReportCashLine>, CoreError> {
        let teller = self.current_session().map(|s| s.display_name).unwrap_or_default();
        Ok(self
            .store
            .list_active_for_till(till_id)?
            .into_iter()
            .filter(|i| i.op_type == "cash_movement" && i.status != "dead")
            .filter_map(|i| {
                serde_json::from_str::<till::CashMovementCommand>(&i.payload).ok().map(|cmd| till::TillReportCashLine {
                    amount_minor: cmd.request.amount as i64,
                    note: cmd.request.note,
                    moved_by_name: teller.clone(),
                    created_at: i.event_at.clone(),
                })
            })
            .collect())
    }

    /// The current till's Z report (drives the close count).
    pub async fn till_report(&self) -> Result<till::TillReportView, CoreError> {
        let t = self.held_current_till()?;
        self.report_now(&t.id)?.ok_or_else(|| CoreError::Validation {
            field: "till".into(),
            detail: "this till is not on this device yet".into(),
        })
    }

    /// Any till's Z report (the history reprint).
    pub async fn till_report_for(&self, till_id: String) -> Result<till::TillReportView, CoreError> {
        self.report_now(&till_id)?.ok_or_else(|| CoreError::Validation {
            field: "till".into(),
            detail: "this till is not on this device yet".into(),
        })
    }

    /// The current till's drawer movements.
    pub async fn list_cash_movements(&self) -> Result<Vec<till::CashMovementView>, CoreError> {
        let t = self.held_current_till()?;
        self.fill_till_soon(&t.id);
        views::cash_movements(&self.store, &t.id)
    }

    /// What closing will check: every method used, the cash line carrying the
    /// drawer — computed from the rows, so it is the same figure offline.
    pub async fn close_till_preview(&self) -> Result<till::CloseTillPreviewView, CoreError> {
        let t = till::current(&self.store)?.filter(|t| t.is_open).ok_or_else(|| CoreError::Validation {
            field: "till".into(),
            detail: "no open till".into(),
        })?;
        self.fill_till_soon(&t.id);
        let label = |m: &str| self.payment_method_label(m.to_string());
        let Some((expected, methods, confirmed)) = views::close_methods(&self.store, &t.id, &label)? else {
            return Err(CoreError::Validation {
                field: "till".into(),
                detail: "this till is not on this device yet".into(),
            });
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
        let authority = views::till_complete(&self.store, &t.id)
            && matches!(views::server_authority(&self.store, &t.id), Ok(Some(_)));
        Ok(till::CloseTillPreviewView {
            till: t,
            expected_cash_minor: expected,
            methods,
            last_till_warning: warning,
            // The figures are this device's; they are the server's only when the
            // stored server report is the authority for the till.
            from_server: confirmed && authority,
            figures_hidden: false,
        })
    }

    /// Past tills at the branch, newest first.
    pub async fn list_tills(&self) -> Result<Vec<till::TillSummaryView>, CoreError> {
        let branch = self.session_branch_id()?;
        let mut list = views::tills(&self.store, &branch)?;
        // The feed's till rows leave the branch name out (the feed IS one
        // branch); every till listed here is this branch's.
        if let Some(name) = self.branch_name_local(&branch) {
            for t in list.iter_mut().filter(|t| t.branch_name.is_none()) {
                t.branch_name = Some(name.clone());
            }
        }
        Ok(list)
    }

    /// What has been given back against one sale. A sale held here is read from
    /// the rows. A sale this device has never seen (a search result from
    /// another till) is asked of the server under [`FETCH_TIMEOUT`], with this
    /// device's queued refunds taken off; offline it cannot be answered.
    pub async fn list_order_refunds(&self, order_id: String) -> Result<orders::OrderRefundsView, CoreError> {
        if let Some(v) = views::order_refunds(&self.store, &order_id)? {
            return Ok(v);
        }
        if !self.online() {
            return Err(CoreError::Offline {
                detail: "this sale is not on this device yet — its refunds need a connection".into(),
            });
        }
        let config = self.api.config();
        let r = within(refunds_api::list_order_refunds(&config, refunds_api::ListOrderRefundsParams { order_id })).await?;
        Ok(self.with_pending_refunds(orders::order_refunds_view(&r)))
    }

    /// Every refund issued from a till's drawer.
    pub async fn list_till_refunds(&self, till_id: String) -> Result<orders::TillRefundsView, CoreError> {
        self.fill_till_soon(&till_id);
        views::till_refunds(&self.store, &till_id)
    }

    /// The branch's name as this device holds it: the synced branch settings,
    /// else the name the device was bound with.
    pub(crate) fn branch_name_local(&self, branch: &str) -> Option<String> {
        crate::sync_pull::rows_of_type(&self.store, branch, "branch_settings")
            .into_iter()
            .find(|v| v.get("id").and_then(serde_json::Value::as_str) == Some(branch))
            .and_then(|v| v.get("name").and_then(serde_json::Value::as_str).map(str::to_string))
            .or_else(|| crate::device::load(&self.store).branch_name)
            .filter(|n| !n.trim().is_empty())
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
        // One attempt per session: a failed backfill waits for the next launch
        // rather than riding every pull.
        if !self.branch_fills.first_attempt(&flag) {
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
    /// be the server's. At most once every [`PARITY_EVERY_MS`], online, only for a
    /// till whose rows changed since its last check, after a
    /// pull; a difference is logged (diagnostics + Sentry, amounts only) and the
    /// server's report is stored for the till.
    /// Serve the server's report when it is the authority for this till
    /// (`views::server_authority`), logging every field where the device's own
    /// figures differ; otherwise the local report. No network.
    pub(crate) fn with_server_authority(&self, till_id: &str, local: till::TillReportView) -> till::TillReportView {
        let label = |m: &str| self.payment_method_label(m.to_string());
        match views::server_authority(&self.store, till_id) {
            Ok(Some(report)) => {
                let server = till::report_view(&report, 0, &label);
                self.report_divergence(
                    "money",
                    parity::diff_keyed(
                        &format!("till {till_id} server vs local"),
                        &parity::report_keyed(&server),
                        &parity::report_keyed(&local),
                    ),
                );
                server
            }
            // The rows' own figures. The server's report arrives only with a
            // fill (a till not held here) or the parity guard, never per read.
            _ => local,
        }
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
            // A till whose rows have not moved since its last check has nothing
            // new to compare: an idle till asks the server nothing.
            let newest = views::newest_seq(&self.store, &till_id).unwrap_or(0);
            let key = format!("{K_PARITY_SEQ}{till_id}");
            let checked = self.store.kv_get(&key).ok().flatten().and_then(|v| v.parse::<i64>().ok());
            if checked == Some(newest) {
                continue;
            }
            self.parity_check_till(&till_id).await;
            let _ = self.store.kv_put(&key, &newest.to_string());
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
        let lines = parity::diff_keyed(
            &format!("till {till_id} server vs local"),
            &parity::report_keyed(&server),
            &parity::report_keyed(&local),
        );
        self.report_divergence("money", lines.clone());
        if !lines.is_empty() {
            self.store.emit_changes([changes::TILLS]);
        }
        lines
    }
}

const K_PARITY_AT: &str = "ledger:parity_checked_at";
/// The newest row seq of a till when the parity guard last compared it.
const K_PARITY_SEQ: &str = "ledger:parity_seq:";
/// How often the production parity guard may ask the server (and only for a
/// till whose rows moved since it last did).
pub(crate) const PARITY_EVERY_MS: i64 = 10 * 60 * 1000;
