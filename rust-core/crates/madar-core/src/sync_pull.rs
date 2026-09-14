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
    /// How much the local data can be trusted right now (OFFLINE_B_DESIGN §6).
    pub freshness: FreshnessView,
}

/// Typed freshness of the replicated store for the session branch.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct FreshnessView {
    /// `fresh` | `stale` | `bootstrapping`.
    pub state: String,
    /// When stale / bootstrapping: `offline` | `auth_expired` | `server_error` |
    /// `forbidden` | `decode` | `throttled` | `never_synced`.
    pub reason: Option<String>,
    /// Seconds since the last completed pull (`None` = never).
    pub age_secs: Option<u64>,
    /// The i18n key of the banner to show, when this state needs one (the
    /// offline pill and the re-login banner already cover `offline` and
    /// `auth_expired`).
    pub banner: Option<String>,
}

fn banner_for(state: &str, reason: Option<&str>) -> Option<String> {
    match (state, reason) {
        ("bootstrapping", _) => Some("sync.freshness_never_synced".into()),
        ("stale", Some("forbidden" | "decode" | "server_error")) => Some("sync.freshness_stale".into()),
        _ => None,
    }
}

/// A pull older than this is stale even with no error since (§6).
pub(crate) const FRESH_FOR_MS: i64 = 60_000;

/// The error class a failed pull records (`sync_streams.last_err_kind`).
pub(crate) fn error_kind(e: &CoreError) -> &'static str {
    match e {
        CoreError::Unauthenticated { .. } => "auth",
        CoreError::Forbidden { .. } => "forbidden",
        CoreError::Server { status: 401, .. } => "auth",
        CoreError::Server { status: 403, .. } => "forbidden",
        CoreError::Server { status: 429, .. } => "throttled",
        CoreError::Internal { detail } if detail.starts_with("decode:") => "decode",
        e if crate::net::is_connectivity_failure(e) => "offline",
        _ => "server",
    }
}

fn stream_key(branch: &str) -> String {
    format!("branch:{branch}")
}

/// Record one pull attempt's outcome for `branch` (never fails the caller).
pub(crate) fn record_pull_outcome(store: &Store, branch: &str, outcome: Result<(), &CoreError>, now_ms: i64) {
    let key = stream_key(branch);
    let _ = store.with_conn(|c| {
        match outcome {
            Ok(()) => c.execute(
                "INSERT INTO sync_streams(stream, scope_key, state, last_ok_at, last_attempt_at, last_err, last_err_kind)
                 VALUES(?1, ?2, 'live', ?3, ?3, NULL, NULL)
                 ON CONFLICT(stream) DO UPDATE SET state='live', last_ok_at=?3, last_attempt_at=?3,
                   last_err=NULL, last_err_kind=NULL",
                rusqlite::params![key, branch, now_ms],
            )?,
            Err(e) => c.execute(
                "INSERT INTO sync_streams(stream, scope_key, state, last_attempt_at, last_err, last_err_kind)
                 VALUES(?1, ?2, 'stale', ?3, ?4, ?5)
                 ON CONFLICT(stream) DO UPDATE SET
                   state=CASE WHEN sync_streams.last_ok_at IS NULL THEN 'bootstrapping' ELSE 'stale' END,
                   last_attempt_at=?3, last_err=?4, last_err_kind=?5",
                rusqlite::params![key, branch, now_ms, e.to_string(), error_kind(e)],
            )?,
        };
        Ok(())
    });
    store.emit_changes([crate::changes::SYNC]);
}

/// Freshness for `branch` from its stream row. `realtime_live` = the SSE stream
/// is connected, which keeps a quiet branch fresh between pulls.
pub(crate) fn freshness(store: &Store, branch: &str, realtime_live: bool, now_ms: i64) -> FreshnessView {
    use rusqlite::OptionalExtension;
    let row: Option<(Option<i64>, Option<String>)> = store
        .with_conn(|c| {
            Ok(c.query_row(
                "SELECT last_ok_at, last_err_kind FROM sync_streams WHERE stream=?1",
                [stream_key(branch)],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?)
        })
        .ok()
        .flatten();
    let complete = store
        .kv_get(&format!("{K_LAST_FULL}{branch}"))
        .ok()
        .flatten()
        .is_some();
    let (last_ok, err_kind) = row.unwrap_or((None, None));
    let age_secs = last_ok.map(|t| ((now_ms - t).max(0) / 1000) as u64);
    let reason_of = |k: &str| {
        match k {
            "auth" => "auth_expired",
            "forbidden" => "forbidden",
            "decode" => "decode",
            "offline" => "offline",
            // Paced by the server (429): the next pass resumes in seconds, no banner.
            "throttled" => "throttled",
            _ => "server_error",
        }
        .to_string()
    };
    let (state, reason) = if !complete {
        ("bootstrapping", Some(err_kind.as_deref().map(reason_of).unwrap_or_else(|| "never_synced".into())))
    } else if let Some(k) = err_kind.as_deref() {
        ("stale", Some(reason_of(k)))
    } else if last_ok.map(|t| now_ms - t <= FRESH_FOR_MS).unwrap_or(false) || (realtime_live && last_ok.is_some()) {
        ("fresh", None)
    } else {
        ("stale", Some(if last_ok.is_some() { "offline" } else { "never_synced" }.to_string()))
    };
    FreshnessView {
        banner: banner_for(state, reason.as_deref()),
        state: state.into(),
        reason,
        age_secs,
    }
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
/// The types the branch's last complete snapshot listed (a mirror built from a
/// type the server does not send yet must not overwrite the legacy fetch).
pub(crate) const K_TYPES: &str = "sync:types:";

/// Did the branch's last complete snapshot list `ty`?
pub(crate) fn feed_has_type(store: &Store, branch: &str, ty: &str) -> bool {
    store
        .kv_get(&format!("{K_TYPES}{branch}"))
        .ok()
        .flatten()
        .and_then(|raw| serde_json::from_str::<Vec<String>>(&raw).ok())
        .map(|t| t.iter().any(|x| x == ty))
        .unwrap_or(false)
}

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

/// The branch's `old_bill_hours` (1..168) from the synced `branch_settings`
/// row; `3` (the backend default) until one has synced.
pub(crate) fn old_bill_hours(store: &Store, branch_id: &str) -> i64 {
    store
        .with_conn(|c| {
            use rusqlite::OptionalExtension;
            Ok(c.query_row(
                "SELECT data FROM sync_rows WHERE branch_id=?1 AND type='branch_settings' AND id=?1",
                rusqlite::params![branch_id],
                |r| r.get::<_, String>(0),
            )
            .optional()?)
        })
        .ok()
        .flatten()
        .and_then(|raw| serde_json::from_str::<serde_json::Value>(&raw).ok())
        .and_then(|v| v.get("old_bill_hours").and_then(|h| h.as_i64()))
        .filter(|h| (1..=168).contains(h))
        .unwrap_or(3)
}

// ── wire ────────────────────────────────────────────────────────────────────
//
// The response is the generated `madar_api::models::PullResponse` (one shape for
// incremental, full and resync pages). Row `data` stays lean JSON: the backend
// projects each of the 22 types itself and the device stores it verbatim.

use madar_api::models::{PullResponse, TypeChecksum};

type Checksums = std::collections::BTreeMap<String, TypeChecksum>;

/// The server's per-type checksums (final page only).
fn server_checksums(resp: &PullResponse) -> Checksums {
    resp.checksums
        .clone()
        .unwrap_or_default()
        .into_iter()
        .collect()
}

/// Every type the POS syncs (§10.1). The pull asks for everything and applies
/// what comes, so only the tests enumerate it.
#[cfg(test)]
pub(crate) const ALL_TYPES: &[&str] = &[
    "category", "menu_item", "bundle", "ingredient", "payment_method", "payment_availability",
    "discount", "branch_settings", "device", "teller", "floor_section", "floor_table",
    "table_occupancy", "table_transfer", "open_ticket", "kitchen_ticket", "delivery", "booking",
    "till", "cash_movement", "order", "refund", "addon_item",
];
/// The types a snapshot must list to count as COMPLETE (and move the cursor):
/// the contract's original set. A type added later (`addon_item`) is applied
/// when a server sends it, but a server that predates it still completes.
pub(crate) const REQUIRED_TYPES: &[&str] = &[
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
pub(crate) fn mismatched_types(server: &Checksums, local: &Checksums) -> Vec<String> {
    server
        .iter()
        .filter(|(ty, _)| !is_ledger(ty))
        .filter(|(ty, c)| local.get(*ty).map(|l| l != *c).unwrap_or(c.count != 0))
        .map(|(ty, _)| ty.clone())
        .collect()
}

#[allow(dead_code)]
pub(crate) fn decide_next(resp: &PullResponse, local: &Checksums) -> PullNext {
    if resp.resync_required.unwrap_or(false) {
        return PullNext::FullFetch;
    }
    if resp.has_more {
        return PullNext::MorePages;
    }
    PullNext::Done {
        refetch: mismatched_types(&server_checksums(resp), local),
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
    if store.future_schema() {
        return Err(CoreError::Internal {
            detail: "local store was written by a newer build; sync apply is off".into(),
        });
    }
    let now_ms = chrono::Utc::now().timestamp_millis();
    store.with_tx_touch(|tx, touched| {
        let mut n = 0u32;
        let is_prot = |ty: &str, id: &str| protected.contains(&(ty.to_string(), id.to_string()));
        let next = resp.next.flatten();
        let types = resp.types.clone().unwrap_or_default();
        let stream_window_from = stream_window(tx, branch)?;
        if resp.full {
            let window = resp
                .ledger_window
                .clone()
                .flatten()
                .and_then(|w| parse_ts(&w.from));
            let ctx = crate::ledger::apply::PageCtx {
                full: true,
                window_from: window,
                stream_window_from,
                now_ms,
            };
            // Tills first: a movement or refund is swept by its till's state.
            let mut ordered: Vec<&String> = types.iter().collect();
            ordered.sort_by_key(|t| if t.as_str() == crate::ledger::T_TILL { 0 } else { 1 });
            for ty in ordered {
                let rows: Vec<serde_json::Value> = resp
                    .data
                    .as_ref()
                    .and_then(|d| d.get(ty))
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                if crate::ledger::is_ledger_type(ty) {
                    let mut present = std::collections::HashSet::new();
                    for r in &rows {
                        let seq = r.get("seq").and_then(|v| v.as_i64()).unwrap_or(0);
                        if let Some(key) = crate::ledger::key_of(ty, r) {
                            present.insert(key);
                        }
                        if crate::ledger::apply::upsert(tx, ty, r, seq, &ctx)? {
                            n += 1;
                        }
                        hook(n)?;
                    }
                    n += crate::ledger::apply::sweep_absent(tx, branch, ty, &present, &ctx)?;
                    touched.push(crate::changes::table_for_sync_type(ty));
                    continue;
                }
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
                let mut stmt = tx.prepare("SELECT id FROM sync_rows WHERE branch_id=?1 AND type=?2")?;
                let existing: Vec<String> = stmt
                    .query_map(rusqlite::params![branch, ty], |r| r.get(0))?
                    .collect::<Result<_, _>>()?;
                drop(stmt);
                for id in existing {
                    if present.contains(&id) || is_prot(ty, &id) {
                        continue;
                    }
                    tx.execute(
                        "DELETE FROM sync_rows WHERE branch_id=?1 AND type=?2 AND id=?3",
                        rusqlite::params![branch, ty, id],
                    )?;
                    n += 1;
                }
                touched.push(crate::changes::table_for_sync_type(ty));
            }
            let all = REQUIRED_TYPES.iter().all(|t| types.iter().any(|x| x == t));
            if move_cursor && all {
                if let Some(next) = next {
                    put_kv(tx, &format!("{K_NEXT}{branch}"), &next.to_string())?;
                }
                put_kv(tx, &format!("{K_LAST_FULL}{branch}"), &chrono::Utc::now().to_rfc3339())?;
                put_kv(tx, &format!("{K_TYPES}{branch}"), &serde_json::to_string(&types)?)?;
                if let Some(w) = window {
                    set_stream_window(tx, branch, &w)?;
                }
                touched.push(crate::changes::SYNC);
            }
        } else {
            let ctx = crate::ledger::apply::PageCtx {
                full: false,
                window_from: None,
                stream_window_from,
                now_ms,
            };
            for c in resp.changes.as_deref().unwrap_or_default() {
                let id = c.id.to_string();
                if crate::ledger::is_ledger_type(&c.r#type) {
                    let changed = if c.op == "delete" || c.data.is_null() {
                        crate::ledger::apply::delete(tx, &c.r#type, &id, &ctx)?
                    } else {
                        crate::ledger::apply::upsert(tx, &c.r#type, &c.data, c.seq, &ctx)?
                    };
                    if changed {
                        n += 1;
                        touched.push(crate::changes::table_for_sync_type(&c.r#type));
                    }
                    hook(n)?;
                    continue;
                }
                let prot = is_prot(&c.r#type, &id);
                if c.op == "delete" || c.data.is_null() {
                    if !prot {
                        let k = tx.execute(
                            "DELETE FROM sync_rows WHERE branch_id=?1 AND type=?2 AND id=?3",
                            rusqlite::params![branch, c.r#type, id],
                        )? as u32;
                        if k > 0 {
                            touched.push(crate::changes::table_for_sync_type(&c.r#type));
                        }
                        n += k;
                    }
                } else if upsert_row(tx, branch, &c.r#type, &id, c.seq, &c.data, prot)? {
                    n += 1;
                    touched.push(crate::changes::table_for_sync_type(&c.r#type));
                }
                hook(n)?;
            }
            if move_cursor {
                if let Some(next) = next {
                    put_kv(tx, &format!("{K_NEXT}{branch}"), &next.to_string())?;
                }
            }
        }
        Ok(n)
    })
}

/// The ledger window of the stream's last complete snapshot.
fn stream_window(tx: &rusqlite::Connection, branch: &str) -> CoreResult<Option<chrono::DateTime<chrono::Utc>>> {
    use rusqlite::OptionalExtension;
    let w: Option<Option<String>> = tx
        .query_row(
            "SELECT window_from FROM sync_streams WHERE stream=?1",
            [format!("branch:{branch}")],
            |r| r.get(0),
        )
        .optional()?;
    Ok(w.flatten().as_deref().and_then(parse_ts))
}

fn set_stream_window(tx: &rusqlite::Connection, branch: &str, w: &chrono::DateTime<chrono::Utc>) -> CoreResult<()> {
    tx.execute(
        "INSERT INTO sync_streams(stream, scope_key, window_from) VALUES(?1, ?2, ?3)
         ON CONFLICT(stream) DO UPDATE SET window_from=excluded.window_from",
        rusqlite::params![format!("branch:{branch}"), branch, w.to_rfc3339()],
    )?;
    Ok(())
}

/// An RFC 3339 instant (row timestamps and the ledger window compare as times,
/// never as strings — Postgres and chrono spell the same instant differently).
fn parse_ts(s: &str) -> Option<chrono::DateTime<chrono::Utc>> {
    chrono::DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|d| d.with_timezone(&chrono::Utc))
}

/// Local per-type checksums (protected rows included with their seq).
pub(crate) fn local_checksums(store: &Store, branch: &str, types: &[String]) -> Checksums {
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

    async fn post_pull(
        &self,
        since: Option<i64>,
        branch: &str,
        types: Option<Vec<String>>,
    ) -> Result<PullResponse, CoreError> {
        let branch_id = uuid::Uuid::parse_str(branch).map_err(|_| CoreError::Validation {
            field: "branch_id".into(),
            detail: "session branch is not a UUID".into(),
        })?;
        let mut request = madar_api::models::PullRequest::new(branch_id);
        request.device_id = uuid::Uuid::parse_str(&self.lan_device_id()).ok().map(Some);
        request.types = types.map(Some);
        madar_api::apis::sync_api::pull(
            &self.api.config(),
            madar_api::apis::sync_api::PullParams {
                pull_request: request,
                since,
            },
        )
        .await
        .map_err(crate::net::map_api_error)
    }

    /// One pull (single-flight). `full` = snapshot; otherwise from `sync:next`.
    pub(crate) async fn pull(&self, full: bool) -> Result<u32, CoreError> {
        let res = single_flight(|| self.pull_inner(full)).await;
        if let Some(branch) = self.sync_branch() {
            record_pull_outcome(&self.store, &branch, res.as_ref().map(|_| ()), chrono::Utc::now().timestamp_millis());
        }
        // A pull is a real network round trip: its outcome is connectivity
        // evidence exactly like an outbox send (the backlog must not mask it).
        match &res {
            Ok(_) => self.note_connectivity(true),
            Err(e) if crate::net::is_connectivity_failure(e) => self.note_connectivity(false),
            Err(_) => {}
        }
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
        let mut since: Option<i64> = if full {
            None
        } else {
            self.store
                .kv_get(&format!("{K_NEXT}{branch}"))?
                .and_then(|v| v.parse().ok())
        };
        let mut applied = 0u32;
        let mut bundle: Option<madar_api::models::AssetBundleRef> = None;
        loop {
            self.set_phase("pulling");
            let resp = self.post_pull(since, &branch, None).await?;
            if resp.resync_required.unwrap_or(false) {
                if since.is_none() {
                    // A full pull never asks for a resync; refuse to loop on one.
                    return Err(CoreError::Internal {
                        detail: "sync pull: resync_required on a full snapshot".into(),
                    });
                }
                since = None;
                continue;
            }
            self.set_phase("applying");
            let protected = protected_rows(&self.store);
            applied += apply_page(&self.store, &branch, &resp, &protected, true)?;
            if resp.full {
                if let Some(b) = resp.asset_bundle.clone().flatten() {
                    bundle = Some(*b);
                }
            }
            if resp.has_more {
                since = resp.next.flatten();
                continue;
            }
            let server = server_checksums(&resp);
            let types: Vec<String> = server.keys().cloned().collect();
            let local = local_checksums(&self.store, &branch, &types);
            let mismatched = mismatched_types(&server, &local);
            let mut stale = None;
            if !mismatched.is_empty() {
                let fix = self.post_pull(None, &branch, Some(mismatched.clone())).await?;
                let protected = protected_rows(&self.store);
                applied += apply_page(&self.store, &branch, &fix, &protected, false)?;
                let local = local_checksums(&self.store, &branch, &mismatched);
                if !mismatched_types(&server_checksums(&fix), &local).is_empty() {
                    stale = Some("checksum_mismatch".to_string());
                }
            }
            self.store
                .kv_put(&format!("{K_LAST_OK}{branch}"), &chrono::Utc::now().to_rfc3339())?;
            self.project_pull_mirrors(&branch);
            self.sync_state.lock().unwrap_or_else(|e| e.into_inner()).stale_reason = stale;
            // §11.7: after rows land, fetch the files they reference (non-fatal).
            let b = bundle
                .as_ref()
                .map(|v| (v.url.clone(), v.seq, v.bytes.max(0) as u64, v.sha256.clone()));
            let _ = self.sync_assets_after_pull(b).await;
            // Once per branch: the past tills older than the snapshot window.
            self.backfill_till_history(&branch).await;
            // The production parity guard for the drawer (rate-limited).
            self.money_parity_check().await;
            return Ok(applied);
        }
    }

    /// Has this branch completed a full snapshot? Only then are the synced rows
    /// the whole picture, and the mirrors may be rebuilt from them.
    pub(crate) fn pull_feed_complete(&self, branch: &str) -> bool {
        self.store
            .kv_get(&format!("{K_LAST_FULL}{branch}"))
            .ok()
            .flatten()
            .is_some()
    }

    /// A6: rebuild the mirrors the floor, the bills and Charge read from the
    /// synced rows, in the shapes their readers already take (the backend
    /// projects `floor_table` / `open_ticket` with the same views its list
    /// routes return). Skipped until the branch holds a full snapshot.
    pub(crate) fn project_pull_mirrors(&self, branch: &str) {
        if !self.pull_feed_complete(branch) {
            return;
        }
        let store = &self.store;
        let methods = rows_of_type(store, branch, "payment_method");
        if let Ok(raw) = serde_json::to_string(&methods) {
            let _ = store.kv_put(crate::menu::K_PAYMENT_METHODS, &raw);
            self.invalidate_catalog_cache();
        }

        let sections = rows_of_type(store, branch, "floor_section");
        let mut tables = rows_of_type(store, branch, "floor_table");
        let label = |v: &serde_json::Value| {
            v.get("label").and_then(|l| l.as_str()).unwrap_or("").to_lowercase()
        };
        tables.sort_by_key(label);
        if let (Ok(s), Ok(t)) = (serde_json::to_string(&sections), serde_json::to_string(&tables)) {
            if crate::held::save_floor(store, &s, &t).is_ok() {
                self.reapply_pending_floor_ops();
            }
        }

        let mut bills: Vec<madar_api::models::OpenTicketView> = rows_of_type(store, branch, "open_ticket")
            .into_iter()
            .filter_map(|v| serde_json::from_value(v).ok())
            .filter(|t: &madar_api::models::OpenTicketView| t.status == "open")
            .collect();
        bills.sort_by_key(|t| t.opened_at);
        if let Some(t) = bills.first() {
            crate::timefmt::remember_payload_tz(store, &t.timezone);
        }
        crate::cache_views(store, crate::K_OPEN_TICKETS_CACHE, &bills);
        let _ = store.kv_put(crate::K_OPEN_TICKETS_STALE, "");

        // Addons, in the `/addon-items` shape the catalogue reads (a branch-
        // disabled addon is not offered), once the server sends the type.
        if feed_has_type(store, branch, "addon_item") {
            let addons: Vec<serde_json::Value> = rows_of_type(store, branch, "addon_item")
                .into_iter()
                .filter(|a| a.get("is_available").and_then(|v| v.as_bool()) != Some(false))
                .map(|mut a| {
                    if let Some(m) = a.as_object_mut() {
                        m.remove("is_available");
                        m.remove("seq");
                    }
                    a
                })
                .collect();
            if let Ok(raw) = serde_json::to_string(&addons) {
                let _ = store.kv_put(crate::menu::K_ADDONS, &raw);
                self.invalidate_catalog_cache();
            }
        }
        // The branch's delivery prep minutes.
        if let Some(prep) = rows_of_type(store, branch, "branch_settings")
            .into_iter()
            .find(|v| v.get("id").and_then(|x| x.as_str()) == Some(branch))
            .and_then(|v| v.get("delivery_prep_minutes").and_then(|m| m.as_i64()))
        {
            let _ = store.kv_put(crate::K_DELIVERY_PREP_MINUTES, &prep.to_string());
        }
        self.adopt_feed_permissions(branch);
    }

    /// The signed-in person's effective grants from their synced teller row
    /// (a grant or a revocation reaches the till with the feed, offline sign-ins
    /// included). A row without `permissions` (an older server) changes nothing.
    pub(crate) fn adopt_feed_permissions(&self, branch: &str) {
        let Some(user) = self.current_session().map(|s| s.user_id) else { return };
        let Some(granted) = rows_of_type(&self.store, branch, "teller")
            .into_iter()
            .find(|v| v.get("id").and_then(|x| x.as_str()) == Some(user.as_str()))
            .and_then(|v| v.get("permissions").and_then(|p| p.as_array()).cloned())
        else {
            return;
        };
        let entries: Vec<crate::session::PermissionEntry> = granted
            .iter()
            .filter_map(|p| p.as_str())
            .filter_map(|p| p.split_once(':'))
            .map(|(r, a)| crate::session::PermissionEntry { resource: r.to_string(), action: a.to_string(), granted: true })
            .collect();
        let blob = {
            let mut g = self.session.write().unwrap_or_else(|e| e.into_inner());
            match g.as_mut() {
                Some(s) if s.snapshot.user_id == user => {
                    s.permissions = entries;
                    s.snapshot.permissions_loaded = true;
                    Some(s.to_blob())
                }
                _ => None,
            }
        };
        if let Some(blob) = blob {
            let _ = self.store.blob_put(crate::session::K_SESSION_BLOB, &blob);
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
            freshness: freshness(
                &self.store,
                &branch,
                self.realtime_live(),
                chrono::Utc::now().timestamp_millis(),
            ),
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

    /// Stable UUID for a readable test label (the wire id is a UUID).
    fn uid(label: &str) -> String {
        uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, label.as_bytes()).to_string()
    }

    fn change(seq: i64, ty: &str, id: &str, op: &str, v: i64) -> madar_api::models::PullChange {
        madar_api::models::PullChange {
            seq,
            r#type: ty.into(),
            id: uuid::Uuid::parse_str(&uid(id)).unwrap(),
            op: op.into(),
            data: if op == "upsert" {
                serde_json::json!({ "id": uid(id), "v": v })
            } else {
                serde_json::Value::Null
            },
        }
    }

    fn incr(next: i64, changes: Vec<madar_api::models::PullChange>) -> PullResponse {
        PullResponse {
            next: Some(Some(next)),
            changes: Some(changes),
            ..Default::default()
        }
    }

    fn row(store: &Store, ty: &str, id: &str) -> Option<(i64, serde_json::Value)> {
        store
            .with_conn(|c| {
                use rusqlite::OptionalExtension;
                Ok(c.query_row(
                    "SELECT seq, data FROM sync_rows WHERE branch_id=?1 AND type=?2 AND id=?3",
                    rusqlite::params![B, ty, uid(id)],
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
        let mut data = serde_json::Map::new();
        for ty in types {
            data.insert(ty.to_string(), serde_json::json!([]));
        }
        for (ty, mut r) in rows {
            let label = r["id"].as_str().unwrap().to_string();
            r["id"] = uid(&label).into();
            data.get_mut(ty).unwrap().as_array_mut().unwrap().push(r);
        }
        PullResponse {
            full: true,
            next: Some(Some(next)),
            types: Some(types.iter().map(|s| s.to_string()).collect()),
            data: Some(serde_json::Value::Object(data)),
            ..Default::default()
        }
    }

    #[test]
    fn protected_row_survives_full_replace() {
        let store = Store::open("").unwrap();
        apply_page(&store, B, &incr(3, vec![change(3, "open_ticket", "t1", "upsert", 1)]), &Protected::new(), true).unwrap();
        let mut prot = Protected::new();
        prot.insert(("open_ticket".into(), uid("t1")));
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
        let mut sums = std::collections::HashMap::new();
        sums.insert("menu_item".to_string(), TypeChecksum { count: 2, checksum: "ffff".into() });
        sums.insert("category".to_string(), local["category"].clone());
        sums.insert("order".to_string(), TypeChecksum { count: 99, checksum: "x".into() });
        resp.checksums = Some(sums);
        assert_eq!(decide_next(&resp, &local), PullNext::Done { refetch: vec!["menu_item".into()] });
        // the self-heal apply (subset full, move_cursor=false) leaves the cursor
        let fix = full(&["menu_item"], vec![("menu_item", serde_json::json!({"id":"b","seq":8}))], 99);
        apply_page(&store, B, &fix, &Protected::new(), false).unwrap();
        assert_eq!(cursor(&store).as_deref(), Some("7"));
        assert!(row(&store, "menu_item", "a").is_none() && row(&store, "menu_item", "b").is_some());
    }

    #[test]
    fn resync_required_triggers_full() {
        let resp = PullResponse { resync_required: Some(true), ..Default::default() };
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

    /// The three bodies exactly as `MadarRust/src/sync/pull/mod.rs` serializes them
    /// (skipped empties, `data: null` on a delete, `asset_bundle: null` on a full
    /// page with no bundle built) decode and apply.
    #[test]
    fn backend_pull_bodies_decode_and_apply() {
        let resync: PullResponse = serde_json::from_str(
            r#"{"full":false,"resync_required":true,"since":1200,"has_more":false,"server_time":"2026-09-13T10:00:00+00:00"}"#,
        )
        .unwrap();
        assert_eq!(decide_next(&resync, &Default::default()), PullNext::FullFetch);

        let a = uid("a");
        let incr: PullResponse = serde_json::from_str(&format!(
            r#"{{"full":false,"since":1200,"next":1203,"has_more":false,"server_time":"2026-09-13T10:00:00+00:00",
               "changes":[{{"seq":1201,"type":"open_ticket","id":"{a}","op":"upsert","data":{{"id":"{a}","status":"open"}}}},
                          {{"seq":1203,"type":"table_occupancy","id":"{a}","op":"delete","data":null}}],
               "checksums":{{"open_ticket":{{"count":1,"checksum":"0123456789abcdef"}}}}}}"#
        ))
        .unwrap();
        let store = Store::open("").unwrap();
        assert_eq!(apply_page(&store, B, &incr, &Protected::new(), true).unwrap(), 1);
        assert_eq!(cursor(&store).as_deref(), Some("1203"));
        assert_eq!(row(&store, "open_ticket", "a").unwrap().0, 1201);

        let full: PullResponse = serde_json::from_str(
            r#"{"full":true,"next":1350,"has_more":false,"server_time":"2026-09-13T10:00:00+00:00",
               "types":["open_ticket"],"data":{"open_ticket":[]},
               "checksums":{"open_ticket":{"count":0,"checksum":"e3b0c44298fc1c14"}},
               "ledger_window":{"from":"2026-09-11T10:00:00.123456+00:00"},"asset_bundle":null}"#,
        )
        .unwrap();
        assert!(full.asset_bundle.clone().flatten().is_none());
        apply_page(&store, B, &full, &Protected::new(), true).unwrap();
        assert!(row(&store, "open_ticket", "a").is_none(), "absent from the snapshot");
        assert_eq!(cursor(&store).as_deref(), Some("1203"), "a subset snapshot keeps the cursor");
        let local = local_checksums(&store, B, &["open_ticket".to_string()]);
        assert_eq!(local["open_ticket"].checksum, "e3b0c44298fc1c14", "empty set hashes like the backend");
    }

    #[test]
    fn ledger_rows_compare_the_window_as_instants() {
        let store = Store::open("").unwrap();
        // Same instant spelled two ways: Postgres `+00:00` with micros vs `Z`.
        // Ledger types are rows in the ledger tables (offline plan B), written
        // there as the feed would have.
        let inside = serde_json::json!({"id": uid("o1"), "branch_id": B, "till_id": "T", "status": "completed",
            "payment_method": "Cash", "created_at": "2026-09-11T10:00:00.5+00:00"});
        let older = serde_json::json!({"id": uid("o2"), "branch_id": B, "till_id": "T", "status": "completed",
            "payment_method": "Cash", "created_at": "2026-09-11T09:59:59Z"});
        store
            .with_tx(|tx| {
                for d in [&inside, &older] {
                    let key = crate::ledger::key_of("order", d).unwrap();
                    crate::ledger::write_row(tx, "order", &key, d, crate::ledger::Origin::Feed(1), None)?;
                }
                Ok(())
            })
            .unwrap();
        let ledger_row = |id: &str| -> bool {
            store
                .with_conn(|c| {
                    Ok(c.query_row("SELECT COUNT(*) FROM ledger_orders WHERE okey=?1", [uid(id)], |r| r.get::<_, i64>(0))?)
                })
                .unwrap()
                > 0
        };
        let mut snap = full(&["order"], vec![], 9);
        snap.ledger_window = Some(Some(Box::new(madar_api::models::LedgerWindow {
            from: "2026-09-11T10:00:00Z".into(),
        })));
        apply_page(&store, B, &snap, &Protected::new(), true).unwrap();
        assert!(!ledger_row("o1"), "inside the window and absent: replaced");
        assert!(ledger_row("o2"), "older than the window: kept until pruning");
    }

    #[test]
    fn old_bill_hours_reads_the_branch_setting() {
        let store = Store::open("").unwrap();
        assert_eq!(old_bill_hours(&store, B), 3, "backend default before any sync");
        let settings = serde_json::json!({"id": B, "old_bill_hours": 5});
        store
            .with_conn(|c| {
                c.execute(
                    "INSERT INTO sync_rows(type,id,branch_id,seq,data) VALUES('branch_settings',?1,?1,1,?2)",
                    rusqlite::params![B, settings.to_string()],
                )?;
                Ok(())
            })
            .unwrap();
        assert_eq!(old_bill_hours(&store, B), 5);
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
