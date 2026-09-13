//! ONE changefeed pull for all POS data (TILLS_CONTRACT §10.3): `POST /sync/pull`
//! applied into `sync_rows` in one SQLite transaction per page, cursor included.
//!
//! This file carries the FRB-facing status types and the `MadarCore` sync verbs.

use std::sync::Mutex;

use crate::error::{CoreError, CoreResult};
use crate::store::Store;
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

// ── wire ────────────────────────────────────────────────────────────────────

/// Per-type count + checksum the server sends on a final page.
#[derive(serde::Deserialize, serde::Serialize, Clone, Debug, PartialEq, Eq, Default)]
pub(crate) struct TypeChecksum {
    #[serde(default)]
    pub count: i64,
    #[serde(default)]
    pub checksum: String,
}

#[derive(serde::Deserialize, serde::Serialize, Clone, Debug, PartialEq)]
pub(crate) struct ChangeWire {
    pub seq: i64,
    #[serde(rename = "type")]
    pub ty: String,
    pub id: String,
    pub op: String,
    #[serde(default)]
    pub data: Option<serde_json::Value>,
}

#[derive(serde::Deserialize, serde::Serialize, Clone, Debug, PartialEq)]
pub(crate) struct LedgerWindow {
    pub from: String,
}

/// Any `/sync/pull` response (incremental, full or resync).
#[derive(serde::Deserialize, serde::Serialize, Clone, Debug, PartialEq, Default)]
pub(crate) struct PullResponse {
    #[serde(default)]
    pub full: bool,
    #[serde(default)]
    pub resync_required: bool,
    #[serde(default)]
    pub since: Option<i64>,
    #[serde(default)]
    pub next: Option<i64>,
    #[serde(default)]
    pub has_more: bool,
    #[serde(default)]
    pub changes: Vec<ChangeWire>,
    #[serde(default)]
    pub types: Vec<String>,
    #[serde(default)]
    pub data: std::collections::BTreeMap<String, Vec<serde_json::Value>>,
    #[serde(default)]
    pub checksums: std::collections::BTreeMap<String, TypeChecksum>,
    #[serde(default)]
    pub ledger_window: Option<LedgerWindow>,
    #[serde(default)]
    pub asset_bundle: Option<serde_json::Value>,
}

/// Every type the POS syncs (§10.1).
pub(crate) const ALL_TYPES: &[&str] = &[
    "category", "menu_item", "bundle", "ingredient", "payment_method", "payment_availability",
    "discount", "branch_settings", "device", "teller", "floor_section", "floor_table",
    "table_occupancy", "table_transfer", "open_ticket", "kitchen_ticket", "delivery", "booking",
    "till", "cash_movement", "order", "refund",
];
/// Ledger types: never checksummed; replaced only inside the full snapshot's window.
pub(crate) const LEDGER_TYPES: &[&str] = &["till", "cash_movement", "order", "refund"];

fn is_ledger(ty: &str) -> bool {
    LEDGER_TYPES.contains(&ty)
}

// ── pure pieces ─────────────────────────────────────────────────────────────

/// First 16 hex of sha256 over sorted `"<id>:<seq>"` joined by `\n` (R-checksum).
pub(crate) fn checksum_of(rows: &[(String, i64)]) -> String {
    use sha2::{Digest, Sha256};
    let mut lines: Vec<String> = rows.iter().map(|(id, seq)| format!("{id}:{seq}")).collect();
    lines.sort();
    let digest = Sha256::digest(lines.join("\n").as_bytes());
    digest.iter().take(8).map(|b| format!("{b:02x}")).collect()
}

/// What to do after a response arrives.
#[allow(dead_code)]
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum PullNext {
    /// Cursor too old / ahead → fetch a full snapshot.
    FullFetch,
    /// Apply this page, then fetch more.
    MorePages,
    /// Final page applied; refetch these state types (self-heal) if non-empty.
    Done { refetch: Vec<String> },
}

/// Compare server checksums with local ones (state types only).
pub(crate) fn mismatched_types(
    server: &std::collections::BTreeMap<String, TypeChecksum>,
    local: &std::collections::BTreeMap<String, TypeChecksum>,
) -> Vec<String> {
    server
        .iter()
        .filter(|(ty, _)| !is_ledger(ty))
        .filter(|(ty, c)| local.get(*ty).map(|l| l != *c).unwrap_or(c.count != 0))
        .map(|(ty, _)| ty.clone())
        .collect()
}

#[allow(dead_code)]
pub(crate) fn decide_next(
    resp: &PullResponse,
    local: &std::collections::BTreeMap<String, TypeChecksum>,
) -> PullNext {
    if resp.resync_required {
        return PullNext::FullFetch;
    }
    if resp.has_more {
        return PullNext::MorePages;
    }
    PullNext::Done {
        refetch: mismatched_types(&resp.checksums, local),
    }
}

/// `(type, id)` pairs with an active outbox op (A3).
pub(crate) type Protected = std::collections::HashSet<(String, String)>;

pub(crate) fn protected_rows(store: &Store) -> Protected {
    store
        .list_active()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|i| Some((i.entity_type?, i.entity_id?)))
        .collect()
}

fn row_seq(tx: &rusqlite::Connection, branch: &str, ty: &str, id: &str) -> CoreResult<Option<i64>> {
    use rusqlite::OptionalExtension;
    Ok(tx
        .query_row(
            "SELECT seq FROM sync_rows WHERE branch_id=?1 AND type=?2 AND id=?3",
            rusqlite::params![branch, ty, id],
            |r| r.get(0),
        )
        .optional()?)
}

fn upsert_row(
    tx: &rusqlite::Connection,
    branch: &str,
    ty: &str,
    id: &str,
    seq: i64,
    data: &serde_json::Value,
    protected: bool,
) -> CoreResult<bool> {
    let cur = row_seq(tx, branch, ty, id)?;
    if let Some(c) = cur {
        if seq < c {
            return Ok(false); // A2
        }
    }
    if protected {
        // A3: keep local data, advance the seq only when a row exists.
        if cur.is_some() {
            tx.execute(
                "UPDATE sync_rows SET seq=?4 WHERE branch_id=?1 AND type=?2 AND id=?3",
                rusqlite::params![branch, ty, id, seq],
            )?;
        }
        return Ok(false);
    }
    tx.execute(
        "INSERT INTO sync_rows(type,id,branch_id,seq,data) VALUES(?1,?2,?3,?4,?5)
         ON CONFLICT(branch_id,type,id) DO UPDATE SET seq=excluded.seq, data=excluded.data",
        rusqlite::params![ty, id, branch, seq, data.to_string()],
    )?;
    Ok(true)
}

fn put_kv(tx: &rusqlite::Connection, k: &str, v: &str) -> CoreResult<()> {
    tx.execute(
        "INSERT INTO kv(k,v,updated_at) VALUES(?1,?2,?3)
         ON CONFLICT(k) DO UPDATE SET v=excluded.v, updated_at=excluded.updated_at",
        rusqlite::params![k, v, chrono::Utc::now().to_rfc3339()],
    )?;
    Ok(())
}

/// Apply one response page in ONE transaction, cursor included (A1–A4).
/// `move_cursor=false` for a self-heal refetch. Returns changes applied.
pub(crate) fn apply_page(
    store: &Store,
    branch: &str,
    resp: &PullResponse,
    protected: &Protected,
    move_cursor: bool,
) -> CoreResult<u32> {
    apply_page_with(store, branch, resp, protected, move_cursor, &mut |_| Ok(()))
}

/// `hook` runs after each row write (tests inject a crash).
pub(crate) fn apply_page_with(
    store: &Store,
    branch: &str,
    resp: &PullResponse,
    protected: &Protected,
    move_cursor: bool,
    hook: &mut dyn FnMut(u32) -> CoreResult<()>,
) -> CoreResult<u32> {
    store.with_tx(|tx| {
        let mut n = 0u32;
        let is_prot = |ty: &str, id: &str| protected.contains(&(ty.to_string(), id.to_string()));
        if resp.full {
            let window = resp.ledger_window.as_ref().map(|w| w.from.clone());
            for ty in &resp.types {
                let rows = resp.data.get(ty).cloned().unwrap_or_default();
                let mut present = std::collections::HashSet::new();
                for r in &rows {
                    let id = r.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string();
                    if id.is_empty() {
                        continue;
                    }
                    let seq = r.get("seq").and_then(|v| v.as_i64()).unwrap_or(0);
                    if upsert_row(tx, branch, ty, &id, seq, r, is_prot(ty, &id))? {
                        n += 1;
                    }
                    present.insert(id);
                    hook(n)?;
                }
                // delete server-origin rows absent from the snapshot (non-protected)
                let mut stmt = tx.prepare("SELECT id, data FROM sync_rows WHERE branch_id=?1 AND type=?2")?;
                let existing: Vec<(String, String)> = stmt
                    .query_map(rusqlite::params![branch, ty], |r| Ok((r.get(0)?, r.get(1)?)))?
                    .collect::<Result<_, _>>()?;
                drop(stmt);
                for (id, data) in existing {
                    if present.contains(&id) || is_prot(ty, &id) {
                        continue;
                    }
                    if is_ledger(ty) {
                        // only rows inside the window are replaced; older stay
                        let changed = serde_json::from_str::<serde_json::Value>(&data)
                            .ok()
                            .and_then(|v| {
                                ["updated_at", "closed_at", "created_at", "opened_at"]
                                    .iter()
                                    .find_map(|k| v.get(*k).and_then(|x| x.as_str()).map(str::to_string))
                            });
                        let inside = match (&window, changed) {
                            (Some(w), Some(c)) => c >= *w,
                            (None, _) => true,
                            _ => false,
                        };
                        if !inside {
                            continue;
                        }
                    }
                    tx.execute(
                        "DELETE FROM sync_rows WHERE branch_id=?1 AND type=?2 AND id=?3",
                        rusqlite::params![branch, ty, id],
                    )?;
                    n += 1;
                }
            }
            let all = ALL_TYPES.iter().all(|t| resp.types.iter().any(|x| x == t));
            if move_cursor && all {
                if let Some(next) = resp.next {
                    put_kv(tx, &format!("{K_NEXT}{branch}"), &next.to_string())?;
                }
                put_kv(tx, &format!("{K_LAST_FULL}{branch}"), &chrono::Utc::now().to_rfc3339())?;
            }
        } else {
            for c in &resp.changes {
                let prot = is_prot(&c.ty, &c.id);
                if c.op == "delete" {
                    if !prot {
                        n += tx.execute(
                            "DELETE FROM sync_rows WHERE branch_id=?1 AND type=?2 AND id=?3",
                            rusqlite::params![branch, c.ty, c.id],
                        )? as u32;
                    }
                } else if let Some(d) = &c.data {
                    if upsert_row(tx, branch, &c.ty, &c.id, c.seq, d, prot)? {
                        n += 1;
                    }
                }
                hook(n)?;
            }
            if move_cursor {
                if let Some(next) = resp.next {
                    put_kv(tx, &format!("{K_NEXT}{branch}"), &next.to_string())?;
                }
            }
        }
        Ok(n)
    })
}

/// Local per-type checksums (protected rows included with their seq).
pub(crate) fn local_checksums(
    store: &Store,
    branch: &str,
    types: &[String],
) -> std::collections::BTreeMap<String, TypeChecksum> {
    let mut out = std::collections::BTreeMap::new();
    for ty in types.iter().filter(|t| !is_ledger(t)) {
        let rows: Vec<(String, i64)> = store
            .with_conn(|c| {
                let mut st = c.prepare("SELECT id, seq FROM sync_rows WHERE branch_id=?1 AND type=?2")?;
                let v = st
                    .query_map(rusqlite::params![branch, ty], |r| Ok((r.get(0)?, r.get(1)?)))?
                    .collect::<Result<Vec<_>, _>>()?;
                Ok(v)
            })
            .unwrap_or_default();
        out.insert(
            ty.clone(),
            TypeChecksum {
                count: rows.len() as i64,
                checksum: checksum_of(&rows),
            },
        );
    }
    out
}

/// Every row of a type for the branch (mirror re-pointing reads these).
pub(crate) fn rows_of_type(store: &Store, branch: &str, ty: &str) -> Vec<serde_json::Value> {
    store
        .with_conn(|c| {
            let mut st = c.prepare("SELECT data FROM sync_rows WHERE branch_id=?1 AND type=?2 ORDER BY id")?;
            let v = st
                .query_map(rusqlite::params![branch, ty], |r| r.get::<_, String>(0))?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(v)
        })
        .unwrap_or_default()
        .into_iter()
        .filter_map(|s| serde_json::from_str(&s).ok())
        .collect()
}

// ── single-flight ───────────────────────────────────────────────────────────

/// One pull at a time across the process; a caller arriving while one runs
/// waits and then reuses its result instead of pulling again (coalescing).
static PULL_LOCK: tokio::sync::Mutex<u64> = tokio::sync::Mutex::const_new(0);
static PULL_GEN: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

pub(crate) async fn single_flight<F, Fut>(f: F) -> Result<u32, CoreError>
where
    F: FnOnce() -> Fut,
    Fut: std::future::Future<Output = Result<u32, CoreError>>,
{
    use std::sync::atomic::Ordering;
    let seen = PULL_GEN.load(Ordering::SeqCst);
    let mut done = PULL_LOCK.lock().await;
    if *done > seen {
        return Ok(0); // a pull finished while we waited: coalesced
    }
    let res = f().await;
    *done = PULL_GEN.fetch_add(1, Ordering::SeqCst) + 1;
    res
}

impl MadarCore {
    fn set_phase(&self, phase: &str) {
        self.sync_state.lock().unwrap_or_else(|e| e.into_inner()).phase = phase.into();
    }

    async fn post_pull(&self, since: Option<i64>, body: &serde_json::Value) -> Result<PullResponse, CoreError> {
        let path = match since {
            Some(s) => format!("/sync/pull?since={s}"),
            None => "/sync/pull".to_string(),
        };
        let text = self.api.post_json(&path, body).await?;
        serde_json::from_str(&text).map_err(|e| CoreError::Internal {
            detail: format!("decode /sync/pull: {e}"),
        })
    }

    /// One pull (single-flight). `full` = snapshot; otherwise from `sync:next`.
    pub(crate) async fn pull(&self, full: bool) -> Result<u32, CoreError> {
        let res = single_flight(|| self.pull_inner(full)).await;
        let mut st = self.sync_state.lock().unwrap_or_else(|e| e.into_inner());
        match &res {
            Ok(_) => {
                st.phase = "done".into();
                st.last_error = None;
            }
            Err(e) => {
                let offline = crate::net::is_connectivity_failure(e);
                st.phase = if offline { "offline" } else { "error" }.into();
                st.stale_reason = Some(if offline { "offline" } else { "http_error" }.into());
                st.last_error = Some(e.to_string());
            }
        }
        res
    }

    async fn pull_inner(&self, full: bool) -> Result<u32, CoreError> {
        let branch = self.sync_branch().ok_or_else(|| CoreError::Unauthenticated {
            detail: "not signed in".into(),
        })?;
        let device_id = self.lan_device_id();
        let mut since: Option<i64> = if full {
            None
        } else {
            self.store
                .kv_get(&format!("{K_NEXT}{branch}"))?
                .and_then(|v| v.parse().ok())
        };
        let mut applied = 0u32;
        loop {
            self.set_phase("pulling");
            let body = serde_json::json!({ "branch_id": branch, "device_id": device_id });
            let resp = self.post_pull(since, &body).await?;
            if resp.resync_required {
                since = None;
                continue;
            }
            self.set_phase("applying");
            let protected = protected_rows(&self.store);
            applied += apply_page(&self.store, &branch, &resp, &protected, true)?;
            if resp.full {
                since = resp.next;
                if resp.has_more {
                    continue;
                }
            } else if resp.has_more {
                since = resp.next;
                continue;
            }
            let types: Vec<String> = resp.checksums.keys().cloned().collect();
            let local = local_checksums(&self.store, &branch, &types);
            let mismatched = mismatched_types(&resp.checksums, &local);
            let mut stale = None;
            if !mismatched.is_empty() {
                {
                    let body = serde_json::json!({ "branch_id": branch, "device_id": device_id, "types": mismatched });
                    let fix = self.post_pull(None, &body).await?;
                    let protected = protected_rows(&self.store);
                    applied += apply_page(&self.store, &branch, &fix, &protected, false)?;
                    let local = local_checksums(&self.store, &branch, &mismatched);
                    if !mismatched_types(&fix.checksums, &local).is_empty() {
                        stale = Some("checksum_mismatch".to_string());
                    }
                }
            }
            self.store
                .kv_put(&format!("{K_LAST_OK}{branch}"), &chrono::Utc::now().to_rfc3339())?;
            self.sync_state.lock().unwrap_or_else(|e| e.into_inner()).stale_reason = stale;
            return Ok(applied);
        }
    }

    /// One incremental pull; returns the number of changes applied.
    pub(crate) async fn pull_incremental(&self) -> Result<u32, CoreError> {
        self.set_phase("draining");
        let _ = self.drain_outbox().await;
        self.pull(false).await
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

    /// Incremental sync: drain the outbox (and legacy refreshes), then pull.
    /// Offline is not an error: the status says `offline`.
    pub async fn sync_now(&self) -> Result<SyncStatusView, CoreError> {
        let _ = self.push_and_refresh().await;
        let _ = self.pull(false).await;
        Ok(self.sync_status())
    }

    /// Long-press: full snapshot (unsent local work is kept).
    pub async fn sync_full(&self) -> Result<SyncStatusView, CoreError> {
        let _ = self.push_and_refresh().await;
        let _ = self.pull(true).await;
        Ok(self.sync_status())
    }

    pub fn sync_on_till_open_status(&self) -> TillOpenSyncView {
        let st = self.sync_state.lock().unwrap_or_else(|e| e.into_inner());
        let mut v = st.till_open.clone();
        v.pending_outbox = self.store.pending_count().unwrap_or(0);
        v
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const B: &str = "B1";

    fn change(seq: i64, ty: &str, id: &str, op: &str, v: i64) -> ChangeWire {
        ChangeWire {
            seq,
            ty: ty.into(),
            id: id.into(),
            op: op.into(),
            data: (op == "upsert").then(|| serde_json::json!({ "id": id, "v": v })),
        }
    }

    fn incr(next: i64, changes: Vec<ChangeWire>) -> PullResponse {
        PullResponse {
            next: Some(next),
            changes,
            ..Default::default()
        }
    }

    fn row(store: &Store, ty: &str, id: &str) -> Option<(i64, serde_json::Value)> {
        store
            .with_conn(|c| {
                use rusqlite::OptionalExtension;
                Ok(c.query_row(
                    "SELECT seq, data FROM sync_rows WHERE branch_id=?1 AND type=?2 AND id=?3",
                    rusqlite::params![B, ty, id],
                    |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)),
                )
                .optional()?)
            })
            .unwrap()
            .map(|(s, d)| (s, serde_json::from_str(&d).unwrap()))
    }

    fn cursor(store: &Store) -> Option<String> {
        store.kv_get(&format!("{K_NEXT}{B}")).unwrap()
    }

    #[test]
    fn pull_applies_page_and_cursor_in_one_tx() {
        let store = Store::open("").unwrap();
        apply_page(&store, B, &incr(5, vec![change(5, "menu_item", "a", "upsert", 1)]), &Protected::new(), true).unwrap();
        let page = incr(9, vec![change(7, "menu_item", "a", "upsert", 2), change(9, "menu_item", "b", "upsert", 3)]);
        // crash after the first row write
        let err = apply_page_with(&store, B, &page, &Protected::new(), true, &mut |n| {
            if n >= 1 {
                Err(CoreError::Internal { detail: "killed".into() })
            } else {
                Ok(())
            }
        });
        assert!(err.is_err());
        assert_eq!(cursor(&store).as_deref(), Some("5"), "cursor unchanged");
        assert_eq!(row(&store, "menu_item", "a").unwrap().0, 5, "row unchanged");
        assert!(row(&store, "menu_item", "b").is_none());
        apply_page(&store, B, &page, &Protected::new(), true).unwrap();
        assert_eq!(cursor(&store).as_deref(), Some("9"));
    }

    #[test]
    fn upsert_older_seq_ignored() {
        let store = Store::open("").unwrap();
        apply_page(&store, B, &incr(10, vec![change(10, "discount", "d", "upsert", 2)]), &Protected::new(), true).unwrap();
        apply_page(&store, B, &incr(10, vec![change(4, "discount", "d", "upsert", 1)]), &Protected::new(), true).unwrap();
        let (seq, data) = row(&store, "discount", "d").unwrap();
        assert_eq!(seq, 10);
        assert_eq!(data["v"], 2);
        // delete applies at any seq
        apply_page(&store, B, &incr(11, vec![change(1, "discount", "d", "delete", 0)]), &Protected::new(), true).unwrap();
        assert!(row(&store, "discount", "d").is_none());
    }

    fn full(types: &[&str], rows: Vec<(&str, serde_json::Value)>, next: i64) -> PullResponse {
        let mut data = std::collections::BTreeMap::new();
        for (ty, r) in rows {
            data.entry(ty.to_string()).or_insert_with(Vec::new).push(r);
        }
        PullResponse {
            full: true,
            next: Some(next),
            types: types.iter().map(|s| s.to_string()).collect(),
            data,
            ..Default::default()
        }
    }

    #[test]
    fn protected_row_survives_full_replace() {
        let store = Store::open("").unwrap();
        apply_page(&store, B, &incr(3, vec![change(3, "open_ticket", "t1", "upsert", 1)]), &Protected::new(), true).unwrap();
        let mut prot = Protected::new();
        prot.insert(("open_ticket".into(), "t1".into()));
        // snapshot lacks t1 → would delete, but it is protected
        apply_page(&store, B, &full(&["open_ticket"], vec![], 20), &prot, true).unwrap();
        assert!(row(&store, "open_ticket", "t1").is_some());
        // newer upsert of a protected row: data kept, seq advanced
        apply_page(&store, B, &incr(21, vec![change(21, "open_ticket", "t1", "upsert", 9)]), &prot, true).unwrap();
        let (seq, data) = row(&store, "open_ticket", "t1").unwrap();
        assert_eq!((seq, data["v"].as_i64()), (21, Some(1)));
    }

    #[test]
    fn full_replace_deletes_server_rows_missing_from_snapshot() {
        let store = Store::open("").unwrap();
        apply_page(&store, B, &incr(3, vec![change(2, "category", "gone", "upsert", 1), change(3, "category", "kept", "upsert", 1)]), &Protected::new(), true).unwrap();
        let snap = full(&["category"], vec![("category", serde_json::json!({"id":"kept","seq":3,"v":5}))], 30);
        apply_page(&store, B, &snap, &Protected::new(), true).unwrap();
        assert!(row(&store, "category", "gone").is_none());
        assert_eq!(row(&store, "category", "kept").unwrap().1["v"], 5);
        // subset snapshot never moves the cursor
        assert_eq!(cursor(&store).as_deref(), Some("3"));
        let all = full(ALL_TYPES, vec![], 40);
        apply_page(&store, B, &all, &Protected::new(), true).unwrap();
        assert_eq!(cursor(&store).as_deref(), Some("40"));
    }

    #[test]
    fn checksum_mismatch_triggers_type_refetch_without_moving_cursor() {
        let store = Store::open("").unwrap();
        apply_page(&store, B, &incr(7, vec![change(7, "menu_item", "a", "upsert", 1)]), &Protected::new(), true).unwrap();
        let local = local_checksums(&store, B, &["menu_item".to_string(), "category".to_string()]);
        let mut resp = incr(7, vec![]);
        resp.checksums.insert("menu_item".into(), TypeChecksum { count: 2, checksum: "ffff".into() });
        resp.checksums.insert("category".into(), local["category"].clone());
        resp.checksums.insert("order".into(), TypeChecksum { count: 99, checksum: "x".into() });
        assert_eq!(decide_next(&resp, &local), PullNext::Done { refetch: vec!["menu_item".into()] });
        // the self-heal apply (subset full, move_cursor=false) leaves the cursor
        let fix = full(&["menu_item"], vec![("menu_item", serde_json::json!({"id":"b","seq":8}))], 99);
        apply_page(&store, B, &fix, &Protected::new(), false).unwrap();
        assert_eq!(cursor(&store).as_deref(), Some("7"));
        assert!(row(&store, "menu_item", "a").is_none() && row(&store, "menu_item", "b").is_some());
    }

    #[test]
    fn resync_required_triggers_full() {
        let resp = PullResponse { resync_required: true, ..Default::default() };
        assert_eq!(decide_next(&resp, &Default::default()), PullNext::FullFetch);
        let more = PullResponse { has_more: true, ..Default::default() };
        assert_eq!(decide_next(&more, &Default::default()), PullNext::MorePages);
    }

    #[tokio::test]
    async fn pull_single_flight_coalesces() {
        let calls = std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0));
        let mk = |c: std::sync::Arc<std::sync::atomic::AtomicU32>| async move {
            single_flight(|| async move {
                c.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                tokio::time::sleep(std::time::Duration::from_millis(50)).await;
                Ok(1)
            })
            .await
        };
        let (a, b, c) = tokio::join!(mk(calls.clone()), mk(calls.clone()), mk(calls.clone()));
        assert!(a.is_ok() && b.is_ok() && c.is_ok());
        assert_eq!(calls.load(std::sync::atomic::Ordering::SeqCst), 1);
    }

    #[test]
    fn checksum_formula_matches_backend_vector() {
        let raw = include_str!("../tests/fixtures/sync_checksum_vector.json");
        let v: serde_json::Value = serde_json::from_str(raw).unwrap();
        let rows: Vec<(String, i64)> = v["rows"]
            .as_array()
            .unwrap()
            .iter()
            .map(|r| (r["id"].as_str().unwrap().to_string(), r["seq"].as_i64().unwrap()))
            .collect();
        assert_eq!(checksum_of(&rows), v["checksum"].as_str().unwrap());
    }
}
