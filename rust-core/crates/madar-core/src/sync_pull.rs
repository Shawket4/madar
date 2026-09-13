//! ONE changefeed pull for all POS data (TILLS_CONTRACT §10.3): `POST /sync/pull`
//! applied into `sync_rows` in one SQLite transaction per page, cursor included.
//!
//! This file carries the FRB-facing status types and the `MadarCore` sync verbs.

use std::sync::Mutex;

use crate::error::CoreError;
use crate::MadarCore;

/// Sync health (§10.3). `online`/`auth_paused`/`blocked` are kept from the
/// pre-rework view so the offline banner and re-login prompt keep working.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SyncStatusView {
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
    pub assets: crate::assets::AssetSyncView,
    pub online: bool,
    pub auth_paused: bool,
    /// Ops waiting on a dead dependency (the sync center's "stuck" count).
    pub blocked: u32,
}

/// The one-line strip on the Open-till screen (decision 15).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct TillOpenSyncView {
    /// `running` | `done` | `stale` (empty before any till opened this session).
    pub state: String,
    pub till_id: Option<String>,
    pub started_at: Option<String>,
    pub finished_at: Option<String>,
    pub stale_reason: Option<String>,
    pub changes_applied: u32,
    pub pending_outbox: u32,
}

/// Mutable engine state kept on the core (phase, errors, the till-open strip).
#[derive(Default)]
pub(crate) struct SyncState {
    pub phase: String,
    pub stale_reason: Option<String>,
    pub last_error: Option<String>,
    pub till_open: TillOpenSyncView,
}

pub(crate) type SyncStateCell = Mutex<SyncState>;

pub(crate) const K_NEXT: &str = "sync:next:";
pub(crate) const K_LAST_OK: &str = "sync:last_ok_at:";
pub(crate) const K_LAST_FULL: &str = "sync:last_full_at:";

/// The allow-list for one availability owner from the synced
/// `payment_availability` rows (`None` = no rows = unrestricted).
pub(crate) fn availability_list(
    store: &crate::store::Store,
    branch_id: &str,
    scope: &str,
    owner_id: &str,
) -> Option<Vec<String>> {
    let raw = store
        .with_conn(|c| {
            use rusqlite::OptionalExtension;
            Ok(c.query_row(
                "SELECT data FROM sync_rows WHERE branch_id=?1 AND type='payment_availability' AND id=?2",
                rusqlite::params![branch_id, owner_id],
                |r| r.get::<_, String>(0),
            )
            .optional()?)
        })
        .ok()
        .flatten()?;
    let v: serde_json::Value = serde_json::from_str(&raw).ok()?;
    if v.get("scope").and_then(|s| s.as_str()).map(|s| s != scope).unwrap_or(false) {
        return None;
    }
    Some(
        v.get("payment_method_ids")?
            .as_array()?
            .iter()
            .filter_map(|x| x.as_str().map(str::to_string))
            .collect(),
    )
}

impl MadarCore {
    /// One incremental pull; returns the number of changes applied.
    pub(crate) async fn pull_incremental(&self) -> Result<u32, CoreError> {
        self.push_and_refresh().await?;
        Ok(0)
    }

    fn sync_branch(&self) -> Option<String> {
        self.current_session().and_then(|s| s.branch_id)
    }

    pub fn sync_status(&self) -> SyncStatusView {
        let st = self.sync_state.lock().unwrap_or_else(|e| e.into_inner());
        let online = self.current_session().map(|s| s.online).unwrap_or(false);
        let branch = self.sync_branch().unwrap_or_default();
        let kv = |k: &str| self.store.kv_get(&format!("{k}{branch}")).ok().flatten();
        SyncStatusView {
            phase: if st.phase.is_empty() {
                "idle".into()
            } else {
                st.phase.clone()
            },
            next_seq: kv(K_NEXT).and_then(|v| v.parse().ok()),
            pending_outbox: self.store.pending_count().unwrap_or(0),
            dead_outbox: self.store.dead_count().unwrap_or(0),
            last_ok_at: kv(K_LAST_OK),
            last_full_at: kv(K_LAST_FULL),
            stale_reason: st.stale_reason.clone(),
            last_error: st.last_error.clone(),
            assets: self.asset_sync_view(),
            online,
            auth_paused: self.auth_paused.load(std::sync::atomic::Ordering::Relaxed) && online,
            blocked: self.store.count_orders_blocked_by_dead_dep().unwrap_or(0),
        }
    }

    /// Incremental sync: drain the outbox, then pull.
    pub async fn sync_now(&self) -> Result<SyncStatusView, CoreError> {
        self.push_and_refresh().await?;
        Ok(self.sync_status())
    }

    /// Long-press: full snapshot (unsent local work is kept).
    pub async fn sync_full(&self) -> Result<SyncStatusView, CoreError> {
        self.push_and_refresh().await?;
        Ok(self.sync_status())
    }

    pub fn sync_on_till_open_status(&self) -> TillOpenSyncView {
        let st = self.sync_state.lock().unwrap_or_else(|e| e.into_inner());
        let mut v = st.till_open.clone();
        v.pending_outbox = self.store.pending_count().unwrap_or(0);
        v
    }
}
