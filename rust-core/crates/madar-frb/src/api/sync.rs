//! Sync center + diagnostics bindings: outbox visibility (list/discard/retry),
//! sync health, orphaned-order recovery, diagnostic logs, clock skew, and the
//! branch-timezone display formatter. One-line delegations only.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::timefmt::TimeStyle;
pub use madar_core::{DiagLogView, OutboxItemView, SyncStatusView};

/// A queued/failed outbox command, projected for the sync center.
#[frb(mirror(OutboxItemView))]
pub struct _OutboxItemView {
    pub id: String,
    /// `open_shift` | `close_shift` | `create_order` | …
    pub op_type: String,
    /// `pending` | `inflight` | `dead`.
    pub status: String,
    pub attempts: i64,
    pub last_error: Option<String>,
    pub event_at: String,
}

/// One-shot sync health for the action-bar chip + offline banner. `pending` is
/// the in-flight/queued set, `failed` the stuck (dead) set, `online` the
/// session's connectivity. The host maps these to the chip label/tone.
#[frb(mirror(SyncStatusView))]
pub struct _SyncStatusView {
    pub pending: u32,
    pub failed: u32,
    /// Orders STRANDED by a dead `open_shift` (waiting on a dependency that will
    /// never ack). When >0 with no open shift, the host can offer
    /// `recover_orphaned_orders()`.
    pub blocked: u32,
    pub online: bool,
    /// `true` when the outbox is parked on a 401 — the host prompts a re-login
    /// to resume syncing (nothing drains until then).
    pub auth_paused: bool,
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

    /// Sync health for the action-bar chip + offline banner (counts + online),
    /// in one cheap local read. Always succeeds offline.
    pub fn sync_status(&self) -> Result<SyncStatusView, MadarError> {
        self.inner.sync_status().map_err(MadarError::from)
    }

    /// Force a sync now — drains the outbox. Cancellable/idempotent.
    pub async fn sync_now(&self) -> Result<(), MadarError> {
        self.inner.sync_now().await.map_err(MadarError::from)
    }

    /// Requeue every dead command (clearing its error) and try to send now.
    /// Best-effort — offline just leaves them pending again.
    pub async fn retry_outbox(&self) -> Result<(), MadarError> {
        self.inner.retry_outbox().await.map_err(MadarError::from)
    }

    /// FALLBACK recovery for the sync center: re-point every order STRANDED by a
    /// dead `open_shift` onto the CURRENT open shift and sync. Returns the number
    /// of outbox rows recovered.
    pub async fn recover_orphaned_orders(&self) -> Result<u32, MadarError> {
        self.inner
            .recover_orphaned_orders()
            .await
            .map_err(MadarError::from)
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
