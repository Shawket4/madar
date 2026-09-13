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
        let new = till::CloseTillPreviewView {
            till: t,
            expected_cash_minor: expected,
            methods,
            last_till_warning: warning,
            from_server: confirmed,
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
}
