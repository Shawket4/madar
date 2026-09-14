//! Sync center + diagnostics bindings: outbox visibility (list/discard/retry),
//! sync health, orphaned-order recovery, diagnostic logs, clock skew, and the
//! branch-timezone display formatter. One-line delegations only.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::timefmt::TimeStyle;
pub use madar_core::assets::AssetSyncView;
pub use madar_core::sync_pull::{FreshnessView, SyncStatusView, TillOpenSyncView};

use crate::frb_generated::StreamSink;
pub use madar_core::{DiagLogView, OutboxItemView};

/// A queued/failed outbox command, projected for the sync center.
#[frb(mirror(OutboxItemView))]
pub struct _OutboxItemView {
    pub id: String,
    /// `open_till` | `close_till` | `create_order` | …
    pub op_type: String,
    /// `pending` | `inflight` | `dead`.
    pub status: String,
    pub attempts: i64,
    pub last_error: Option<String>,
    pub event_at: String,
}

/// Sync health (§10.3).
#[frb(mirror(SyncStatusView))]
pub struct _SyncStatusView {
    /// `idle` | `draining` | `pulling` | `applying` | `done` | `offline` | `error`.
    pub phase: String,
    pub next_seq: Option<i64>,
    pub pending_outbox: u32,
    pub dead_outbox: u32,
    pub last_ok_at: Option<String>,
    pub last_full_at: Option<String>,
    /// `offline` | `checksum_mismatch` | `resync_failed` | `http_error`.
    pub stale_reason: Option<String>,
    pub last_error: Option<String>,
    pub assets: AssetSyncView,
    pub online: bool,
    pub auth_paused: bool,
    pub blocked: u32,
    /// How far the local data can be trusted (`fresh` / `stale` / `bootstrapping`).
    pub freshness: FreshnessView,
}

/// Freshness of the replicated store (OFFLINE_B_DESIGN §6).
#[frb(mirror(FreshnessView))]
pub struct _FreshnessView {
    /// `fresh` | `stale` | `bootstrapping`.
    pub state: String,
    /// `offline` | `auth_expired` | `server_error` | `forbidden` | `decode` | `never_synced`.
    pub reason: Option<String>,
    pub age_secs: Option<u64>,
    /// i18n key of the banner this state needs, if any.
    pub banner: Option<String>,
}

#[frb(mirror(AssetSyncView))]
pub struct _AssetSyncView {
    pub needed: u32,
    pub missing: u32,
    pub downloading: bool,
    pub bytes_done: u64,
    pub bytes_total: u64,
    pub last_error: Option<String>,
}

/// The Open-till screen's sync strip (decision 15).
#[frb(mirror(TillOpenSyncView))]
pub struct _TillOpenSyncView {
    /// `running` | `done` | `stale`.
    pub state: String,
    pub till_id: Option<String>,
    pub started_at: Option<String>,
    pub finished_at: Option<String>,
    pub stale_reason: Option<String>,
    pub changes_applied: u32,
    pub pending_outbox: u32,
}

/// One diagnostic log line.
#[frb(mirror(DiagLogView))]
pub struct _DiagLogView {
    pub at: String,
    pub level: String,
    pub message: String,
}

/// Display styles, mirroring Flutter's `formatting.dart` helpers + the receipt stamp.
#[frb(mirror(TimeStyle))]
pub enum _TimeStyle {
    /// `hh:mm a` — a clock time (Flutter `timeShort`). Order/cash rows.
    Time,
    /// `MMM d` — a short date (Flutter `dateShort`).
    DateShort,
    /// `MMM d, hh:mm a` — date + time (Flutter `dateTime`). Shift open/close.
    DateTime,
    /// `dd/MM/yyyy hh:mm a` — the receipt stamp.
    Receipt,
}

impl MadarBridge {
    // ── sync center (outbox visibility + retry/discard) ───────────────────

    /// Queued + failed commands for the sync center (acked rows hidden), oldest
    /// first. Always succeeds offline.
    pub fn list_outbox(&self) -> Result<Vec<OutboxItemView>, MadarError> {
        self.inner.list_outbox().map_err(MadarError::from)
    }

    /// Discard a single DEAD command (the teller gives up on it). Returns true
    /// if a dead command with that id was removed.
    pub fn discard_outbox_item(&self, id: String) -> Result<bool, MadarError> {
        self.inner.discard_outbox_item(id).map_err(MadarError::from)
    }

    /// Local table changes, as batches of logical table names (`orders`, `tills`,
    /// `open_tickets`, …, or `*` = re-read everything), coalesced over 50 ms.
    /// A board re-reads when a table it shows changes; the core decides what
    /// changed, Dart only listens.
    pub async fn watch_tables(&self, sink: StreamSink<Vec<String>>) -> Result<(), MadarError> {
        self.inner
            .watch_tables(50, move |batch| sink.add(batch).is_ok())
            .map_err(MadarError::from)
    }

    /// Sync health (one cheap local read; always succeeds offline).
    #[frb(sync)]
    pub fn sync_status(&self) -> SyncStatusView {
        self.inner.sync_status()
    }

    /// Incremental sync: drain the outbox, then pull.
    pub async fn sync_now(&self) -> Result<SyncStatusView, MadarError> {
        self.inner.sync_now().await.map_err(MadarError::from)
    }

    /// Long-press: download everything again (unsent sales are kept).
    pub async fn sync_full(&self) -> Result<SyncStatusView, MadarError> {
        self.inner.sync_full().await.map_err(MadarError::from)
    }

    /// The till-open sync strip state.
    #[frb(sync)]
    pub fn sync_on_till_open_status(&self) -> TillOpenSyncView {
        self.inner.sync_on_till_open_status()
    }

    /// Re-verify local asset files and fetch what is missing.
    pub async fn repair_assets(&self) -> Result<AssetSyncView, MadarError> {
        self.inner.repair_assets().await.map_err(MadarError::from)
    }

    /// Requeue every dead command and try to send now.
    pub async fn retry_outbox(&self) -> Result<(), MadarError> {
        self.inner.retry_outbox().await.map_err(MadarError::from)
    }

    /// Retry one till's dead commands (a dead `open_till` holds only its till).
    pub async fn retry_till_outbox(&self, till_id: String) -> Result<u32, MadarError> {
        self.inner.retry_till_outbox(till_id).await.map_err(MadarError::from)
    }

    // ── diagnostics ────────────────────────────────────────────────────────

    /// Recent diagnostic warnings (newest first) — the Settings → Diagnostics
    /// feed. Captures sync dead-letters, cascade failures, and auth parks.
    pub fn recent_logs(&self) -> Vec<DiagLogView> {
        self.inner.recent_logs()
    }

    /// Clear the diagnostics feed.
    pub fn clear_logs(&self) {
        self.inner.clear_logs();
    }

    /// Server-vs-device clock skew in MINUTES (server minus device, refreshed by
    /// `refresh_connectivity`). The host shows a banner past a threshold so the
    /// teller fixes the clock before offline work is mis-timestamped.
    #[frb(sync)]
    pub fn clock_skew_minutes(&self) -> i32 {
        self.inner.clock_skew_minutes()
    }

    // ── time formatting ────────────────────────────────────────────────────

    /// Format a stored RFC3339 timestamp for DISPLAY in the BRANCH's timezone
    /// (not the device's) — the single source of truth so every host renders
    /// order/shift/cash/receipt times identically.
    #[frb(sync)]
    pub fn format_time(&self, rfc3339: String, style: TimeStyle) -> String {
        self.inner.format_time(rfc3339, style)
    }

    /// THE money string in the current language — `display::format_money`.
    /// The design system's `MadarFormat.money` is the synchronous mirror.
    #[frb(sync)]
    pub fn format_money(&self, minor: i64, currency: String, signed: bool) -> String {
        self.inner.format_money(minor, currency, signed)
    }

    /// A row's stamp in the branch zone, 24-hour: `18:02` today,
    /// `Sep 12 · 18:02` otherwise (Arabic `12 سبتمبر · 18:02`).
    #[frb(sync)]
    pub fn format_stamp(&self, rfc3339: String) -> String {
        self.inner.format_stamp(rfc3339)
    }

    /// Elapsed since `rfc3339` by the corrected clock: `42m`, `1h 05m`.
    #[frb(sync)]
    pub fn format_elapsed_since(&self, rfc3339: String) -> String {
        self.inner.format_elapsed_since(rfc3339)
    }

    /// A duration in seconds: `42m`, `1h 05m`, `2d 03h` (Arabic `42 د`…).
    #[frb(sync)]
    pub fn format_elapsed(&self, secs: i64) -> String {
        self.inner.format_elapsed(secs)
    }

    /// The currency label in the current language (`EGP` / `ج.م`).
    #[frb(sync)]
    pub fn currency_label(&self, code: String) -> String {
        self.inner.currency_label(code)
    }

    /// The branch's IANA timezone name (cached at login, or the Cairo fallback) —
    /// for any host that needs the raw zone (e.g. a platform date picker).
    #[frb(sync)]
    pub fn branch_timezone(&self) -> String {
        self.inner.branch_timezone()
    }

    // ── config / about ─────────────────────────────────────────────────────

    /// API base URL the core will talk to (from `.env`).
    #[frb(sync)]
    pub fn base_url(&self) -> String {
        self.inner.base_url()
    }

    /// Environment name (`prod` | `staging` | `dev`).
    #[frb(sync)]
    pub fn environment(&self) -> String {
        self.inner.environment()
    }

    /// SQLite path the host handed us (empty => in-memory).
    #[frb(sync)]
    pub fn db_path(&self) -> String {
        self.inner.db_path()
    }

    /// Core crate version.
    #[frb(sync)]
    pub fn version(&self) -> String {
        self.inner.version()
    }
}

// ── Board reads with their trust (OFFLINE_B_DESIGN §6 `Synced<T>`) ─────────

pub use madar_core::synced::SyncMeta;

/// How far a board's rows can be trusted.
#[frb(mirror(SyncMeta))]
pub struct _SyncMeta {
    pub freshness: FreshnessView,
    /// This device's changes to the board still queued or sending.
    pub pending: u32,
    /// This device's changes to the board the server refused.
    pub failed: u32,
}

pub struct SyncedTickets {
    pub data: Vec<crate::api::tickets::TicketView>,
    pub meta: SyncMeta,
}

pub struct SyncedOrders {
    pub data: Vec<crate::api::orders::OrderSummaryView>,
    pub meta: SyncMeta,
}

pub struct SyncedTillReport {
    pub data: crate::api::till::TillReportView,
    pub meta: SyncMeta,
}

pub struct SyncedKitchen {
    pub data: Vec<crate::api::kds::KdsTicketView>,
    pub meta: SyncMeta,
}

pub struct SyncedDeliveries {
    pub data: Vec<crate::api::delivery::DeliveryOrderView>,
    pub meta: SyncMeta,
}

impl MadarBridge {
    /// The open bills with their freshness and this device's queue for them.
    pub async fn list_open_tickets_synced(&self) -> Result<SyncedTickets, MadarError> {
        let s = self.inner.list_open_tickets_synced().await.map_err(MadarError::from)?;
        Ok(SyncedTickets { data: s.data, meta: s.meta })
    }

    /// The current till's sales with their freshness and queue.
    pub async fn list_till_orders_synced(&self) -> Result<SyncedOrders, MadarError> {
        let s = self.inner.list_till_orders_synced().await.map_err(MadarError::from)?;
        Ok(SyncedOrders { data: s.data, meta: s.meta })
    }

    /// The current till's Z report with its freshness and queue.
    pub async fn till_report_synced(&self) -> Result<SyncedTillReport, MadarError> {
        let s = self.inner.till_report_synced().await.map_err(MadarError::from)?;
        Ok(SyncedTillReport { data: s.data, meta: s.meta })
    }

    /// The kitchen board with its freshness and queue.
    pub async fn kds_list_synced(&self, station_id: Option<String>) -> Result<SyncedKitchen, MadarError> {
        let s = self.inner.kds_list_synced(station_id).await.map_err(MadarError::from)?;
        Ok(SyncedKitchen { data: s.data, meta: s.meta })
    }

    /// The delivery queue with its freshness and queue.
    pub async fn list_delivery_orders_synced(&self, status: Option<String>) -> Result<SyncedDeliveries, MadarError> {
        let s = self.inner.list_delivery_orders_synced(status).await.map_err(MadarError::from)?;
        Ok(SyncedDeliveries { data: s.data, meta: s.meta })
    }
}
