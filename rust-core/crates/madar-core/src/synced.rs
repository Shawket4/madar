//! Typed freshness on the board reads (OFFLINE_B_DESIGN §6):
//! `Synced<T> { data, meta: { freshness, pending, failed } }`.
//!
//! A board read returns the rows AND how far they can be trusted: the branch
//! stream's freshness (fresh / stale + why / bootstrapping), how many of this
//! device's own changes to that board are still on their way, and how many
//! failed. The host shows it; it decides nothing.

use crate::changes;
use crate::error::CoreError;
use crate::sync_pull::FreshnessView;
use crate::MadarCore;

/// How far a board's rows can be trusted right now.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct SyncMeta {
    pub freshness: FreshnessView,
    /// This device's changes to the board still queued or sending.
    pub pending: u32,
    /// This device's changes to the board the server refused (the sync center).
    pub failed: u32,
}

/// A board read with its [`SyncMeta`].
#[derive(Clone, Debug, PartialEq)]
pub struct Synced<T> {
    pub data: T,
    pub meta: SyncMeta,
}

impl MadarCore {
    /// The meta for a board made of `tables` (logical names, `changes.rs`).
    pub fn sync_meta_for(&self, tables: &[&str]) -> SyncMeta {
        let freshness = self.sync_status().freshness;
        let (mut pending, mut failed) = (0u32, 0u32);
        for item in self.store.list_active().unwrap_or_default() {
            let moves = changes::tables_for_op(&item.op_type);
            if !moves.iter().any(|t| tables.contains(t)) {
                continue;
            }
            if item.status == "dead" {
                failed += 1;
            } else {
                pending += 1;
            }
        }
        SyncMeta { freshness, pending, failed }
    }

    pub async fn list_open_tickets_synced(&self) -> Result<Synced<Vec<crate::tickets::TicketView>>, CoreError> {
        let data = self.list_open_tickets().await?;
        Ok(Synced { data, meta: self.sync_meta_for(&[changes::OPEN_TICKETS]) })
    }

    pub async fn list_till_orders_synced(&self) -> Result<Synced<Vec<crate::orders::OrderSummaryView>>, CoreError> {
        let data = self.list_till_orders().await?;
        Ok(Synced { data, meta: self.sync_meta_for(&[changes::ORDERS]) })
    }

    /// [`Self::till_report_synced`] as the signed-in person may see it (blind
    /// count: refused while the till is open without the grant).
    pub async fn till_report_synced_checked(&self) -> Result<Synced<crate::till::TillReportView>, CoreError> {
        let s = self.till_report_synced().await?;
        self.require_figures_for(&s.data)?;
        Ok(s)
    }

    pub async fn till_report_synced(&self) -> Result<Synced<crate::till::TillReportView>, CoreError> {
        let data = self.till_report().await?;
        Ok(Synced {
            data,
            meta: self.sync_meta_for(&[changes::TILLS, changes::ORDERS, changes::CASH_MOVEMENTS, changes::REFUNDS]),
        })
    }

    pub async fn kds_list_synced(&self, station_id: Option<String>) -> Result<Synced<Vec<crate::kds::KdsTicketView>>, CoreError> {
        let data = self.kds_list(station_id).await?;
        Ok(Synced { data, meta: self.sync_meta_for(&[changes::KITCHEN]) })
    }

    pub async fn list_delivery_orders_synced(
        &self,
        status: Option<String>,
    ) -> Result<Synced<Vec<crate::delivery::DeliveryOrderView>>, CoreError> {
        let data = self.list_delivery_orders(status).await?;
        Ok(Synced { data, meta: self.sync_meta_for(&[changes::DELIVERY]) })
    }
}
