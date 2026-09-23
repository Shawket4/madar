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
    /// Ops of ANY type held behind a dead root (the sync center's "held up"
    /// count). Used to be create_order only, which hid a wedged drawer close.
    pub blocked: u32,
    /// A `close_till`/`close_shift` is among them: the drawer cannot finish
    /// until the root is retried or discarded, and the till-close screen says so
    /// instead of spinning.
    pub blocked_close: bool,
    /// How much the local data can be trusted right now (OFFLINE_B_DESIGN §6).
    /// The WORSE of the two streams below, so it can never read "fresh" while
    /// half the data the till sells from is behind.
    pub freshness: FreshnessView,
    /// The catalog refresh on its own — menu, prices, payment methods,
    /// discounts — so a screen can say WHICH half is behind.
    pub catalog_freshness: FreshnessView,
    /// What the checksum self-heal last rebuilt from the server, and when
    /// (RFC3339). Empty until a repair has happened. A repair is not a failure,
    /// but it is not nothing either: silently healing is how a device that
    /// keeps diverging goes on looking healthy.
    pub repaired_types: Vec<String>,
    pub repaired_at: Option<String>,
}

/// Typed freshness of the replicated store for the session branch.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct FreshnessView {
    /// `fresh` | `stale` | `bootstrapping`.
    pub state: String,
    /// When stale / bootstrapping: `offline` | `auth_expired` | `server_error` |
    /// `forbidden` | `decode` | `throttled` | `never_synced` | `newer_build`
    /// (the file was written by a newer app build: read-only until updated).
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
        ("stale", Some("newer_build")) => Some("sync.store_newer_build".into()),
        _ => None,
    }
}

/// The `FreshnessView.reason` an error class maps to.
fn reason_kind(k: &str) -> String {
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

/// The catalog refresh is a SECOND stream, recorded apart from `/sync/pull`.
/// It used to be recorded nowhere at all: a device whose pull was perfectly
/// healthy but whose catalog refresh kept failing read "fresh" while selling
/// from a menu, a price list and a payment-method list that were days old.
fn catalog_stream_key(branch: &str) -> String {
    format!("catalog:{branch}")
}

/// Record one catalog-refresh attempt for `branch`.
pub(crate) fn record_catalog_outcome(
    store: &Store,
    branch: &str,
    outcome: Result<(), &CoreError>,
    now_ms: i64,
) {
    record_stream_outcome(store, &catalog_stream_key(branch), branch, outcome, now_ms);
}

/// Record one pull attempt's outcome for `branch` (never fails the caller).
pub(crate) fn record_pull_outcome(store: &Store, branch: &str, outcome: Result<(), &CoreError>, now_ms: i64) {
    record_stream_outcome(store, &stream_key(branch), branch, outcome, now_ms);
}

/// The shared body of [`record_pull_outcome`] / [`record_catalog_outcome`].
fn record_stream_outcome(
    store: &Store,
    key: &str,
    branch: &str,
    outcome: Result<(), &CoreError>,
    now_ms: i64,
) {
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

/// Freshness for `branch`: the WORSE of its two streams, `/sync/pull` and the
/// catalog refresh. `realtime_live` = the SSE stream is connected, which keeps
/// a quiet branch fresh between pulls.
///
/// It used to read the pull stream alone, so a device whose pull was healthy
/// and whose catalog refresh had been failing for days reported "fresh" — and
/// sold from a stale menu, stale prices and a stale payment-method list with
/// nothing on screen suggesting otherwise. The catalog is half the data a till
/// sells from; a view of freshness that cannot see it is not a view of
/// freshness.
pub(crate) fn freshness(store: &Store, branch: &str, realtime_live: bool, now_ms: i64) -> FreshnessView {
    let complete = store
        .kv_get(&format!("{K_LAST_FULL}{branch}"))
        .ok()
        .flatten()
        .is_some();
    let pull = stream_freshness(store, &stream_key(branch), complete, realtime_live, now_ms);
    worse_of(pull, catalog_freshness(store, branch, now_ms))
}

/// Freshness of the CATALOG stream alone, for a UI that wants to say which half
/// is behind. A branch that has never run a catalog refresh is bootstrapping,
/// exactly like one that has never pulled.
pub(crate) fn catalog_freshness(store: &Store, branch: &str, _now_ms: i64) -> FreshnessView {
    // Deliberately NOT judged by age, unlike the pull stream. Nothing refreshes
    // the catalog on a beat — it happens when a till opens, when someone syncs,
    // or when the menu changes — so "older than a minute" is the normal, healthy
    // state of every device in the field and would mean permanent staleness.
    // What is worth reporting is a refresh that is FAILING, or one that has
    // never succeeded on a device that has tried: that is a till selling from a
    // menu, prices and a payment-method list that stopped moving.
    let (state, reason) = match stream_row(store, &catalog_stream_key(branch)) {
        // Never attempted. On a feed-complete branch the changefeed carries the
        // catalog and the refresh is a fallback, so this is not evidence of
        // anything; the pull stream speaks for the device.
        None => ("fresh", None),
        Some((_, Some(kind))) => ("stale", Some(reason_kind(&kind))),
        Some((Some(_), None)) => ("fresh", None),
        Some((None, None)) => ("bootstrapping", Some("never_synced".to_string())),
    };
    FreshnessView {
        banner: banner_for(state, reason.as_deref()),
        state: state.into(),
        reason,
        age_secs: None,
    }
}

/// `(last_ok_at, last_err_kind)` for one stream, or `None` when it has never
/// been attempted at all.
fn stream_row(store: &Store, key: &str) -> Option<(Option<i64>, Option<String>)> {
    use rusqlite::OptionalExtension;
    store
        .with_conn(|c| {
            Ok(c.query_row(
                "SELECT last_ok_at, last_err_kind FROM sync_streams WHERE stream=?1",
                [key],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?)
        })
        .ok()
        .flatten()
}

/// Rank: `fresh` < `stale` < `bootstrapping`. The worse view wins, so a UI can
/// never read "fresh" while half the data the till sells from is missing.
fn worse_of(a: FreshnessView, b: FreshnessView) -> FreshnessView {
    let rank = |v: &FreshnessView| match v.state.as_str() {
        "fresh" => 0,
        "stale" => 1,
        _ => 2,
    };
    if rank(&b) > rank(&a) { b } else { a }
}

fn stream_freshness(
    store: &Store,
    key: &str,
    complete: bool,
    realtime_live: bool,
    now_ms: i64,
) -> FreshnessView {
    let row = stream_row(store, key);
    let (last_ok, err_kind) = row.unwrap_or((None, None));
    let age_secs = last_ok.map(|t| ((now_ms - t).max(0) / 1000) as u64);
    let reason_of = reason_kind;
    let (state, reason) = if store.future_schema() {
        ("stale", Some("newer_build".to_string()))
    } else if !complete {
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
    /// Ops of this device held behind a dead root right now.
    pub blocked: u32,
    /// One of them is the drawer's own close.
    pub blocked_close: bool,
}

/// Mutable engine state kept on the core (phase, errors, the till-open strip).
#[derive(Default)]
pub(crate) struct SyncState {
    pub phase: String,
    pub stale_reason: Option<String>,
    pub last_error: Option<String>,
    pub till_open: TillOpenSyncView,
    /// Types the checksum self-heal last rebuilt from the server, and when.
    pub repaired_types: Vec<String>,
    pub repaired_at: Option<String>,
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

/// The branch's synced `branch_settings` row (`None` before the first pull).
pub(crate) fn branch_settings_row(store: &Store, branch_id: &str) -> Option<serde_json::Value> {
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
}

/// A field of the branch's settings row, when the server sends it (an older
/// backend's row lacks the newer fields: `None`, not a default).
pub(crate) fn branch_setting(store: &Store, branch_id: &str, field: &str) -> Option<serde_json::Value> {
    branch_settings_row(store, branch_id).and_then(|mut v| v.get_mut(field).map(serde_json::Value::take))
}

/// Set one field of the branch's settings row in place (a manager's write the
/// next pull confirms). `false` when the device holds no row.
pub(crate) fn patch_branch_setting(store: &Store, branch_id: &str, field: &str, value: &serde_json::Value) -> CoreResult<bool> {
    let Some(mut row) = branch_settings_row(store, branch_id) else { return Ok(false) };
    row[field] = value.clone();
    store.with_conn(|c| {
        c.execute(
            "UPDATE sync_rows SET data=?2 WHERE branch_id=?1 AND type='branch_settings' AND id=?1",
            rusqlite::params![branch_id, row.to_string()],
        )?;
        Ok(true)
    })
}

/// Has this branch completed a full snapshot? Until it has, the rows cannot
/// answer "there is none".
pub(crate) fn branch_snapshotted(store: &Store, branch_id: &str) -> bool {
    store.kv_get(&format!("{K_LAST_FULL}{branch_id}")).ok().flatten().is_some()
}

/// The branch's standard opening float from its settings row.
pub(crate) fn standard_float(store: &Store, branch_id: &str) -> Option<i64> {
    branch_setting(store, branch_id, "standard_float").and_then(|v| v.as_i64())
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

/// Every type the POS syncs (§10.1): what a LAN peer may hand over too. The
/// type lists, the ledger classification and the R-checksum are one copy with
/// the server, in madar-shared (`madar_sync`).
pub(crate) const SYNCED_TYPES: &[&str] = madar_sync::ALL_TYPES;
#[cfg(test)]
pub(crate) const ALL_TYPES: &[&str] = SYNCED_TYPES;
/// The types a snapshot must list to count as COMPLETE (and move the cursor):
/// the contract's original set. A type added later (`addon_item`, `customer`)
/// is applied when a server sends it, but a server that predates it still
/// completes — a till never waits on the customer list to open.
pub(crate) const REQUIRED_TYPES: &[&str] = madar_sync::REQUIRED_TYPES;
/// Ledger types: never checksummed; replaced only inside the full snapshot's window.
/// `staff_drink` included: it is sent inside the 48 h window and paged with the
/// other ledger rows, so a snapshot page missing a drink says nothing about it.
/// Unlike the other four it has no typed `ledger_*` table (`ledger::is_ledger_type`);
/// it lives in `sync_rows` plus its `ledger_staff_drinks` mirror, and a snapshot never
/// sweeps it — only an explicit delete in the changefeed removes a drink.
#[allow(dead_code)]
pub(crate) const LEDGER_TYPES: &[&str] = madar_sync::LEDGER_TYPES;

use madar_sync::is_ledger;

// ── pure pieces ─────────────────────────────────────────────────────────────

/// First 16 hex of sha256 over sorted `"<id>:<seq>"` joined by `\n` (R-checksum).
pub(crate) use madar_sync::checksum_of;

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
        .prepare_cached("SELECT seq FROM sync_rows WHERE branch_id=?1 AND type=?2 AND id=?3")?
        .query_row(rusqlite::params![branch, ty, id], |r| r.get(0))
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
    tx.prepare_cached(
        "INSERT INTO sync_rows(type,id,branch_id,seq,data) VALUES(?1,?2,?3,?4,?5)
         ON CONFLICT(branch_id,type,id) DO UPDATE SET seq=excluded.seq, data=excluded.data, peer_seq=NULL",
    )?
    .execute(rusqlite::params![ty, id, branch, seq, data.to_string()])?;
    mirror_local(tx, ty, id, Some(data))?;
    Ok(true)
}

/// A feed type that is ALSO kept in a typed local table gets written there in
/// the same transaction. Only the staff drinks so far: the pool count has to be
/// one query over `(branch, business_date)` whether the drink was rung here,
/// heard from a peer or brought by the cloud, and that is a column, not a scan
/// of every `sync_rows` blob.
fn mirror_local(
    tx: &rusqlite::Connection,
    ty: &str,
    id: &str,
    data: Option<&serde_json::Value>,
) -> CoreResult<()> {
    if ty != crate::ledger::staff_drinks::WIRE {
        return Ok(());
    }
    match data {
        Some(v) => crate::ledger::staff_drinks::from_feed(tx, v)?,
        None => {
            crate::ledger::staff_drinks::forget(tx, id)?;
        }
    }
    Ok(())
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
/// A snapshot's rows by type, as raw slices of the response body.
pub(crate) type RawRows<'a> = std::collections::HashMap<String, Vec<&'a serde_json::value::RawValue>>;

/// Decode a pull body: everything but `data` into the generated response, and
/// `data`'s rows left raw (parsed one at a time as they are applied).
pub(crate) fn decode_pull(body: &str) -> CoreResult<(PullResponse, Option<RawRows<'_>>)> {
    use serde_json::value::RawValue;
    let decode = |e: serde_json::Error| CoreError::Internal { detail: format!("decode: {e}") };
    let mut top: std::collections::HashMap<&str, &RawValue> = serde_json::from_str(body).map_err(decode)?;
    let raw: Option<RawRows<'_>> = match top.remove("data") {
        Some(d) if d.get() != "null" => Some(serde_json::from_str(d.get()).map_err(decode)?),
        _ => None,
    };
    let rest = serde_json::to_string(&top).map_err(decode)?;
    let resp: PullResponse = serde_json::from_str(&rest).map_err(decode)?;
    Ok((resp, raw))
}

/// Run `f` over each snapshot row of `ty`, from the raw rows when given, else
/// from the response's own `data` (tests build responses in memory).
fn each_row(
    resp: &PullResponse,
    raw: Option<&RawRows<'_>>,
    ty: &str,
    f: &mut dyn FnMut(&serde_json::Value) -> CoreResult<()>,
) -> CoreResult<()> {
    if let Some(raw) = raw {
        for r in raw.get(ty).map(Vec::as_slice).unwrap_or_default() {
            let v: serde_json::Value =
                serde_json::from_str(r.get()).map_err(|e| CoreError::Internal { detail: format!("decode: {e}") })?;
            f(&v)?;
        }
        return Ok(());
    }
    if let Some(rows) = resp.data.as_ref().and_then(|d| d.get(ty)).and_then(|v| v.as_array()) {
        for v in rows {
            f(v)?;
        }
    }
    Ok(())
}

pub(crate) fn apply_page(
    store: &Store,
    branch: &str,
    resp: &PullResponse,
    protected: &Protected,
    move_cursor: bool,
) -> CoreResult<u32> {
    apply_page_with(store, branch, resp, None, protected, move_cursor, None, &mut |_| Ok(()))
}

/// What a PAGED full snapshot has delivered so far (backend `snapshot_cursor`):
/// the ledger keys seen on every page (the absent-row sweep runs once, after the
/// last page) and every type the pages covered (the cursor moves only when the
/// whole snapshot is in).
#[derive(Default, Debug)]
pub(crate) struct SnapshotPaging {
    pub present: std::collections::HashMap<String, std::collections::HashSet<String>>,
    pub types: std::collections::BTreeSet<String>,
}

/// Ledger rows per page of a full snapshot (a ~34k-sale window is 7 pages).
pub(crate) const LEDGER_PAGE_SIZE: i64 = 5_000;

/// `hook` runs after each row write (tests inject a crash).
pub(crate) fn apply_page_with(
    store: &Store,
    branch: &str,
    resp: &PullResponse,
    raw: Option<&RawRows<'_>>,
    protected: &Protected,
    move_cursor: bool,
    mut paging: Option<&mut SnapshotPaging>,
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
                horizon: next,
            };
            // Tills first: a movement or refund is swept by its till's state.
            let mut ordered: Vec<&String> = types.iter().collect();
            ordered.sort_by_key(|t| if t.as_str() == crate::ledger::T_TILL { 0 } else { 1 });
            for ty in ordered {
                if crate::ledger::is_ledger_type(ty) {
                    let mut present = std::collections::HashSet::new();
                    let paged = paging.is_some();
                    each_row(resp, raw, ty, &mut |r| {
                        let seq = r.get("seq").and_then(|v| v.as_i64()).unwrap_or(0);
                        if let Some(key) = crate::ledger::key_of(ty, r) {
                            present.insert(key);
                        }
                        if crate::ledger::apply::upsert(tx, ty, r, seq, &ctx)? {
                            n += 1;
                        }
                        hook(n)
                    })?;
                    if paged {
                        let acc = paging.as_deref_mut().expect("paged");
                        acc.present.entry(ty.clone()).or_default().extend(present);
                        if !resp.has_more {
                            // The whole snapshot is in: sweep against every page.
                            let all = acc.present.get(ty.as_str()).cloned().unwrap_or_default();
                            n += crate::ledger::apply::sweep_absent(tx, branch, ty, &all, &ctx)?;
                        }
                    } else {
                        n += crate::ledger::apply::sweep_absent(tx, branch, ty, &present, &ctx)?;
                    }
                    touched.push(crate::changes::table_for_sync_type(ty));
                    continue;
                }
                let mut present = std::collections::HashSet::new();
                each_row(resp, raw, ty, &mut |r| {
                    let id = r.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string();
                    if id.is_empty() {
                        return Ok(());
                    }
                    let seq = r.get("seq").and_then(|v| v.as_i64()).unwrap_or(0);
                    if upsert_row(tx, branch, ty, &id, seq, r, is_prot(ty, &id))? {
                        n += 1;
                    }
                    present.insert(id);
                    hook(n)
                })?;
                // A windowed ledger type kept in `sync_rows` (`staff_drink`):
                // absence from a page or from the window is not a delete.
                if is_ledger(ty) {
                    touched.push(crate::changes::table_for_sync_type(ty));
                    continue;
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
                    mirror_local(tx, ty, &id, None)?;
                    // Gone as of this snapshot's horizon: a LAN peer still holding
                    // it at an older seq is told.
                    if let Some(h) = next {
                        crate::lan_sync::record_tombstone(tx, branch, ty, &id, h)?;
                    }
                    n += 1;
                }
                touched.push(crate::changes::table_for_sync_type(ty));
            }
            let covered: Vec<String> = match paging.as_deref_mut() {
                Some(acc) => {
                    acc.types.extend(types.iter().cloned());
                    acc.types.iter().cloned().collect()
                }
                None => types.clone(),
            };
            let all = REQUIRED_TYPES.iter().all(|t| covered.iter().any(|x| x == t));
            let last_page = paging.is_none() || !resp.has_more;
            if move_cursor && all && last_page {
                if let Some(next) = next {
                    put_kv(tx, &format!("{K_NEXT}{branch}"), &next.to_string())?;
                }
                put_kv(tx, &format!("{K_LAST_FULL}{branch}"), &chrono::Utc::now().to_rfc3339())?;
                put_kv(tx, &format!("{K_TYPES}{branch}"), &serde_json::to_string(&covered)?)?;
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
                horizon: next,
            };
            for c in resp.changes.as_deref().unwrap_or_default() {
                let id = c.id.to_string();
                if crate::ledger::is_ledger_type(&c.r#type) {
                    let changed = if c.op == "delete" || c.data.is_null() {
                        crate::lan_sync::record_tombstone(tx, branch, &c.r#type, &id, c.seq)?;
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
                    crate::lan_sync::record_tombstone(tx, branch, &c.r#type, &id, c.seq)?;
                    if !prot {
                        let k = tx.execute(
                            "DELETE FROM sync_rows WHERE branch_id=?1 AND type=?2 AND id=?3",
                            rusqlite::params![branch, c.r#type, id],
                        )? as u32;
                        mirror_local(tx, &c.r#type, &id, None)?;
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
        if touched.contains(&crate::changes::OPEN_TICKETS) {
            crate::customers::feed_settles_ticket_customers(tx, branch)?;
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
/// Architecture E capabilities from a feed teller row; `None` for an older
/// backend's row, which carries only the legacy grid.
/// A teller row's `limits` map. The server writes every key of a limit,
/// absent ones as `null` (`"own": null`), which `madar_authz::Limits` (a plain
/// `bool` for `own`) refuses — and one refusal used to drop the WHOLE map, so
/// every cap an owner set silently read as unlimited on the till. Read each
/// field on its own; null is unrestricted.
fn limits_from_row(v: Option<&serde_json::Value>) -> std::collections::BTreeMap<String, madar_authz::Limits> {
    let Some(serde_json::Value::Object(m)) = v else {
        return Default::default();
    };
    m.iter()
        .map(|(k, l)| {
            let n = |f: &str| l.get(f).and_then(|x| x.as_i64());
            (
                k.clone(),
                madar_authz::Limits {
                    max_amount: n("max_amount"),
                    max_percent: n("max_percent"),
                    max_value: n("max_value"),
                    max_age_minutes: n("max_age_minutes"),
                    own: l.get("own").and_then(|x| x.as_bool()).unwrap_or(false),
                },
            )
        })
        .collect()
}

pub(crate) fn grants_from_teller_row(row: &serde_json::Value) -> Option<crate::session::AuthzGrants> {
    let keys = |f: &str| -> Option<Vec<String>> {
        row.get(f)
            .and_then(|p| p.as_array())
            .map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect())
    };
    keys("capabilities").map(|capabilities| crate::session::AuthzGrants {
        capabilities,
        ask_manager: keys("ask_manager").unwrap_or_default(),
        limits: limits_from_row(row.get("limits")),
        owner: row.get("is_owner").and_then(|x| x.as_bool()).unwrap_or(false),
    })
}

#[cfg(test)]
mod limits_row_tests {
    #[test]
    fn a_teller_row_limit_with_null_fields_still_caps() {
        let row = serde_json::json!({
            "capabilities": ["orders.discount.manual_amount"],
            "limits": { "orders.discount.manual_amount":
                { "max_amount": 500, "max_percent": null, "max_value": null, "max_age_minutes": null, "own": null } }
        });
        let g = super::grants_from_teller_row(&row).unwrap();
        assert_eq!(g.limits["orders.discount.manual_amount"].max_amount, Some(500));
        assert!(!g.limits["orders.discount.manual_amount"].own);
    }
}

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

/// One pull at a time PER CORE; a caller arriving while one runs waits and then
/// takes that pull's result instead of pulling again (coalescing). Per core, not
/// per process: two cores in one process (tests, a device-switch) never answer
/// each other's pulls, and a coalesced caller sees the failure it waited on
/// rather than a made-up success (which reset the offline evidence).
#[derive(Default)]
pub(crate) struct PullFlight {
    /// `(the announcement generation the last COMPLETED pull covered, its
    /// outcome)`.
    done: tokio::sync::Mutex<(u64, Option<Result<u32, CoreError>>)>,
    /// Bumped by [`Self::announce`] every time something says there is new work
    /// to fetch — a realtime event, a `resync`, an acked op. A waiter may only
    /// take an in-flight pull's result if that pull's request went out at or
    /// after the announcement the waiter came for; otherwise the change was
    /// announced too late to be in the response, and coalescing swallows it.
    announced: std::sync::atomic::AtomicU64,
}

impl PullFlight {
    /// Something new is on the server. Anything already in flight predates it.
    pub(crate) fn announce(&self) {
        self.announced
            .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    }
}

pub(crate) async fn single_flight<F, Fut>(flight: &PullFlight, f: F) -> Result<u32, CoreError>
where
    F: FnOnce() -> Fut,
    Fut: std::future::Future<Output = Result<u32, CoreError>>,
{
    use std::sync::atomic::Ordering;
    // The announcement we came to fetch.
    let want = flight.announced.load(Ordering::SeqCst);
    // `try_lock` is how we tell "nobody is pulling" from "someone is pulling
    // and we are waiting behind them". Only the second case may be coalesced —
    // and only if that pull's request went out at or after `want`. The old code
    // compared against a counter of COMPLETED pulls, read BEFORE the lock, so
    // any pull that finished while we waited looked new enough to reuse,
    // including one whose request had already gone out before our change was
    // announced. That change was then never fetched, and the device sat on
    // stale rows until something else happened to nudge it.
    let mut done = match flight.done.try_lock() {
        Ok(g) => g,
        Err(_) => {
            let g = flight.done.lock().await;
            if g.0 >= want {
                // The pull we waited on went out at or after `want`, so our
                // change is in it: its outcome is ours.
                return g.1.clone().unwrap_or(Ok(0));
            }
            g
        }
    };
    // What this request covers is whatever had been announced when it went out.
    let covers = flight.announced.load(Ordering::SeqCst);
    let res = f().await;
    done.0 = covers;
    done.1 = Some(res.clone());
    res
}

impl MadarCore {
    fn set_phase(&self, phase: &str) {
        self.sync_state.lock().unwrap_or_else(|e| e.into_inner()).phase = phase.into();
    }

    /// POST /sync/pull and return the raw body (decoded by [`decode_pull`]).
    ///
    /// Not the generated client's `pull`: that decodes a full snapshot into one
    /// `serde_json::Value` tree — ~15x the body in memory, over a gigabyte for a
    /// branch with 34k sales in its window. The body is kept as text and the rows
    /// stay raw slices of it until each is applied (measured, "Implementation
    /// status"). Same request, headers and error mapping as the generated call.
    async fn post_pull(
        &self,
        since: Option<i64>,
        branch: &str,
        types: Option<Vec<String>>,
        page: Option<Option<madar_api::models::SnapshotCursor>>,
    ) -> Result<String, CoreError> {
        use madar_api::apis::{Error as ApiError, ResponseContent};
        let branch_id = uuid::Uuid::parse_str(branch).map_err(|_| CoreError::Validation {
            field: "branch_id".into(),
            detail: "session branch is not a UUID".into(),
        })?;
        let mut request = madar_api::models::PullRequest::new(branch_id);
        request.device_id = uuid::Uuid::parse_str(&self.lan_device_id()).ok().map(Some);
        request.types = types.map(Some);
        // A full snapshot of everything asks for paged ledger rows (an older
        // server ignores the fields and answers in one response).
        if let Some(cursor) = page {
            request.ledger_page_size = Some(Some(LEDGER_PAGE_SIZE));
            request.snapshot_cursor = cursor.map(|c| Some(Box::new(c)));
        }
        let config = self.api.config();
        let mut rb = config
            .client
            .request(reqwest::Method::POST, format!("{}/sync/pull", config.base_path));
        if let Some(since) = since {
            rb = rb.query(&[("since", since.to_string())]);
        }
        if let Some(ua) = &config.user_agent {
            rb = rb.header(reqwest::header::USER_AGENT, ua.clone());
        }
        if let Some(token) = &config.bearer_access_token {
            rb = rb.bearer_auth(token);
        }
        let resp = rb
            .json(&request)
            .send()
            .await
            .map_err(|e| crate::net::map_api_error::<()>(ApiError::Reqwest(e)))?;
        let status = resp.status();
        let content = resp
            .text()
            .await
            .map_err(|e| crate::net::map_api_error::<()>(ApiError::Reqwest(e)))?;
        if status.is_client_error() || status.is_server_error() {
            return Err(crate::net::map_api_error::<()>(ApiError::ResponseError(ResponseContent {
                status,
                content,
                entity: None,
            })));
        }
        Ok(content)
    }

    /// One pull (single-flight). `full` = snapshot; otherwise from `sync:next`.
    pub(crate) async fn pull(&self, full: bool) -> Result<u32, CoreError> {
        let res = single_flight(&self.scheduler.pull_flight, || self.pull_inner(full)).await;
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
        let mut paging: Option<SnapshotPaging> = None;
        let mut page_cursor: Option<madar_api::models::SnapshotCursor> = None;
        let mut first_checksums: Option<Checksums> = None;
        loop {
            self.set_phase("pulling");
            let page = since.is_none().then(|| page_cursor.clone());
            let body = self.post_pull(since, &branch, None, page).await?;
            let (resp, raw) = decode_pull(&body)?;
            if resp.resync_required.unwrap_or(false) {
                if since.is_none() {
                    // A full pull never asks for a resync; refuse to loop on one.
                    return Err(CoreError::Internal {
                        detail: "sync pull: resync_required on a full snapshot".into(),
                    });
                }
                since = None;
                paging = None;
                page_cursor = None;
                continue;
            }
            self.set_phase("applying");
            let protected = protected_rows(&self.store);
            let next_cursor = resp.snapshot_cursor.clone().flatten().map(|c| *c);
            if resp.full && (next_cursor.is_some() || paging.is_some()) && paging.is_none() {
                paging = Some(SnapshotPaging::default());
            }
            applied += apply_page_with(
                &self.store,
                &branch,
                &resp,
                raw.as_ref(),
                &protected,
                true,
                paging.as_mut(),
                &mut |_| Ok(()),
            )?;
            drop(raw);
            drop(body);
            if resp.full {
                if let Some(b) = resp.asset_bundle.clone().flatten() {
                    bundle = Some(*b);
                }
                if first_checksums.is_none() {
                    first_checksums = Some(server_checksums(&resp));
                }
            }
            if resp.has_more {
                if resp.full {
                    // The next page of the same snapshot.
                    match next_cursor {
                        Some(c) => page_cursor = Some(c),
                        None => {
                            return Err(CoreError::Internal { detail: "sync pull: a full page has more but no cursor".into() });
                        }
                    }
                } else {
                    since = resp.next.flatten();
                }
                continue;
            }
            // A paged snapshot states its checksums on its first page.
            let server = if resp.full { first_checksums.clone().unwrap_or_else(|| server_checksums(&resp)) } else { server_checksums(&resp) };
            let types: Vec<String> = server.keys().cloned().collect();
            let local = local_checksums(&self.store, &branch, &types);
            let mismatched = mismatched_types(&server, &local);
            let mut stale = None;
            if !mismatched.is_empty() {
                let fix_body = self.post_pull(None, &branch, Some(mismatched.clone()), None).await?;
                let (fix, fix_raw) = decode_pull(&fix_body)?;
                let protected = protected_rows(&self.store);
                applied += apply_page_with(&self.store, &branch, &fix, fix_raw.as_ref(), &protected, false, None, &mut |_| Ok(()))?;
                let local = local_checksums(&self.store, &branch, &mismatched);
                let healed = mismatched_types(&server_checksums(&fix), &local).is_empty();
                if !healed {
                    stale = Some("checksum_mismatch".to_string());
                }
                // A repair is news: silent self-healing is how a device that
                // keeps diverging looks healthy right up until it is not. The
                // status records what was rebuilt and when, so the sync screen
                // can say so and a pattern is visible instead of invisible.
                {
                    let mut st = self.sync_state.lock().unwrap_or_else(|e| e.into_inner());
                    st.repaired_types = mismatched.clone();
                    st.repaired_at = Some(chrono::Utc::now().to_rfc3339());
                }
                crate::obs::capture_bg_warning(
                    "sync.checksum_repair",
                    format!(
                        "rebuilt {} from the server ({}){}",
                        mismatched.len(),
                        mismatched.join(","),
                        if healed { "" } else { " — STILL mismatched" }
                    ),
                );
            }
            self.store
                .kv_put(&format!("{K_LAST_OK}{branch}"), &chrono::Utc::now().to_rfc3339())?;
            // Cloud wins: a LAN peer's row the feed should have confirmed by now
            // and did not is not the server's.
            let cursor = self.store.kv_get(&format!("{K_NEXT}{branch}"))?.and_then(|v| v.parse::<i64>().ok()).unwrap_or(0);
            let purged = self.store.with_tx_touch(|tx, touched| {
                let k = crate::lan_sync::purge_unconfirmed(tx, &branch, cursor)?;
                if k > 0 {
                    touched.push(crate::changes::ALL);
                }
                Ok(k)
            })?;
            applied += purged;
            self.project_pull_mirrors(&branch);
            // A grant change re-emits the person's teller row: keep the live
            // session's capabilities equal to the feed's (no-op when unchanged
            // or when the person has no row here).
            if applied > 0 {
                self.adopt_feed_permissions(&branch);
            }
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

        // Discounts, like every other mirror. The checksum self-heal validates
        // the FEED's discount rows, but every consumer reads this kv mirror
        // (cart.rs, discounts.rs, checkout.rs) — and nothing rebuilt it from
        // the feed, so a preset DELETED on the server kept being offered on the
        // till until a catalog refresh happened to succeed. The feed was right
        // and the till was wrong, and the self-heal could not tell.
        if feed_has_type(store, branch, "discount") {
            let discounts = rows_of_type(store, branch, "discount");
            if let Ok(raw) = serde_json::to_string(&discounts) {
                let _ = store.kv_put(crate::menu::K_DISCOUNTS, &raw);
                self.invalidate_catalog_cache();
            }
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

        // The "wants to move inside" waitlist, from the feed at its cursor.
        let transfers: Vec<crate::held::TransferWire> = rows_of_type(store, branch, "table_transfer")
            .into_iter()
            .filter_map(|v| serde_json::from_value(v).ok())
            .collect();
        let next = store.kv_get(&format!("{K_NEXT}{branch}")).ok().flatten().and_then(|v| v.parse().ok());
        let _ = crate::held::transfers_from_feed(store, transfers, &self.pending_held_ids(), next);

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
        self.adopt_feed_tax_policy(branch);
    }

    /// The branch's effective tax policy from its synced settings row (a rate
    /// changed in the dashboard reaches the till with the feed). A row without
    /// `tax_policy` (an older server) changes nothing.
    pub(crate) fn adopt_feed_tax_policy(&self, branch: &str) {
        let Some(row) = branch_settings_row(&self.store, branch) else { return };
        let Some(p) = row.get("tax_policy").filter(|p| p.is_object()) else { return };
        let (Some(rate), Some(incl), Some(sc), Some(sct)) = (
            p.get("tax_rate").and_then(serde_json::Value::as_f64),
            p.get("tax_inclusive").and_then(serde_json::Value::as_bool),
            p.get("service_charge_rate").and_then(serde_json::Value::as_f64),
            p.get("service_charge_taxable").and_then(serde_json::Value::as_bool),
        ) else {
            return;
        };
        let table = row.get("org_require_table_for_orders").and_then(serde_json::Value::as_bool).unwrap_or(false);
        self.adopt_tax_policy(rate, incl, sc, sct, table);
    }

    /// The signed-in person's effective grants from their synced teller row
    /// (a grant or a revocation reaches the till with the feed, offline sign-ins
    /// included). A row without `permissions` (an older server) changes nothing.
    pub(crate) fn adopt_feed_permissions(&self, branch: &str) {
        let Some(user) = self.current_session().map(|s| s.user_id) else { return };
        let row = rows_of_type(&self.store, branch, "teller")
            .into_iter()
            .find(|v| v.get("id").and_then(|x| x.as_str()) == Some(user.as_str()));
        let row_epoch = row
            .as_ref()
            .and_then(|r| r.get("authz_epoch"))
            .and_then(|x| x.as_i64())
            .unwrap_or(i64::MIN);
        if let Some(row) = row {
            self.adopt_teller_row(&user, &row);
        }
        // A verified server-signed snapshot (PERMISSIONS_ARCHITECTURE §4.4)
        // then replaces the capabilities when it is at least as new: the row
        // can be edited on the device, the signature cannot. The legacy grid
        // stays the row's (the snapshot carries capabilities only).
        if let Some(body) = self.verified_snapshot(branch) {
            if body.org_epoch >= row_epoch {
                if let Some(grants) = crate::authz_snapshot::grants_for(&body, &user) {
                    self.adopt_snapshot_grants(&user, grants);
                }
            }
        }
    }

    fn adopt_teller_row(&self, user: &str, row: &serde_json::Value) {
        let user = user.to_string();

        let Some(granted) = row.get("permissions").and_then(|p| p.as_array()).cloned() else {
            return;
        };
        // Architecture E rows also carry the resolved capabilities; an older
        // backend's row does not, and the legacy grid then answers `can`.
        let authz = grants_from_teller_row(row);
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
                    if authz.is_some() {
                        s.authz = authz;
                    }
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

    /// Install grants from the signed snapshot on the live session.
    fn adopt_snapshot_grants(&self, user: &str, grants: crate::session::AuthzGrants) {
        let blob = {
            let mut g = self.session.write().unwrap_or_else(|e| e.into_inner());
            match g.as_mut() {
                Some(s) if s.snapshot.user_id == user => {
                    s.authz = Some(grants);
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
        let blocked = self.store.blocked_by_dead_root().unwrap_or_default();
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
            blocked: blocked.len() as u32,
            blocked_close: blocked
                .iter()
                .any(|(_, op)| matches!(op.as_str(), "close_till" | "close_shift")),
            freshness: freshness(
                &self.store,
                &branch,
                self.realtime_live(),
                chrono::Utc::now().timestamp_millis(),
            ),
            repaired_types: st.repaired_types.clone(),
            repaired_at: st.repaired_at.clone(),
            catalog_freshness: catalog_freshness(
                &self.store,
                &branch,
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

    /// Long-press: download EVERYTHING again (unsent local work is kept).
    ///
    /// A full snapshot of the feed, then the catalog refresh with its revision
    /// gate off. It used to stop after the snapshot, so the "full" sync
    /// refreshed LESS of the menu than a plain tap (whose host also runs the
    /// catalog refresh): the option sheet's unified catalog, the branch context
    /// (logo, receipt footer), menu images outside the bundle and step
    /// animations were never re-fetched by it at all.
    pub async fn sync_full(&self) -> Result<SyncStatusView, CoreError> {
        let _ = self.push_and_refresh().await;
        // Both halves USED to be swallowed, so "download everything again"
        // answered Ok with a green tick whatever happened — a manager could
        // long-press Sync on a device that fetched nothing and be told it
        // worked. A full sync promises the whole store; if either half of it
        // did not happen, say so. The pull's error wins (it is the deeper
        // failure) and the catalog's is reported when the pull was fine.
        let pulled = self.pull(true).await;
        let catalog = self.refresh_catalog_with(true).await;
        if let Err(e) = pulled {
            return Err(e);
        }
        catalog?;
        Ok(self.sync_status())
    }

    pub fn sync_on_till_open_status(&self) -> TillOpenSyncView {
        let st = self.sync_state.lock().unwrap_or_else(|e| e.into_inner());
        let mut v = st.till_open.clone();
        v.pending_outbox = self.store.pending_count().unwrap_or(0);
        let blocked = self.store.blocked_by_dead_root().unwrap_or_default();
        v.blocked = blocked.len() as u32;
        v.blocked_close = blocked
            .iter()
            .any(|(_, op)| matches!(op.as_str(), "close_till" | "close_shift"));
        v
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::Store;

    /// `/sync/pull` healthy, catalog refresh failing: the device is NOT fresh.
    /// It reported fresh while it sold from a menu, a price list and a
    /// payment-method list that had stopped moving days before.
    #[test]
    fn a_failing_catalog_refresh_makes_the_device_stale_however_well_it_pulls() {
        let store = Store::open("").unwrap();
        let branch = "b1";
        let now = 1_700_000_000_000i64;
        store
            .kv_put(&format!("{K_LAST_FULL}{branch}"), "2026-09-19T10:00:00Z")
            .unwrap();

        // Both streams healthy, moments ago → fresh.
        record_pull_outcome(&store, branch, Ok(()), now);
        record_catalog_outcome(&store, branch, Ok(()), now);
        assert_eq!(freshness(&store, branch, false, now).state, "fresh");
        assert_eq!(catalog_freshness(&store, branch, now).state, "fresh");

        // The pull keeps working; the catalog refresh starts failing.
        let err = CoreError::Server {
            status: 500,
            detail: "boom".into(),
            code: String::new(),
        };
        record_catalog_outcome(&store, branch, Err(&err), now);
        record_pull_outcome(&store, branch, Ok(()), now);
        let f = freshness(&store, branch, false, now);
        assert_eq!(
            f.state, "stale",
            "a healthy pull cannot vouch for a catalog that is not arriving"
        );
        assert_eq!(f.reason.as_deref(), Some("server_error"));
        assert_eq!(catalog_freshness(&store, branch, now).state, "stale");

        // …and a live realtime stream does not paper over it either.
        assert_eq!(freshness(&store, branch, true, now).state, "stale");

        // But AGE alone must not: nothing refreshes the catalog on a beat — it
        // happens when a till opens, when someone syncs, or when the menu
        // changes — so "older than a minute" is the normal, healthy state of
        // every device in the field. Judging it by age made every device
        // permanently stale (it wedged the real-backend backlog scenario,
        // which waits for `fresh` after a drain).
        record_catalog_outcome(&store, branch, Ok(()), now);
        record_pull_outcome(&store, branch, Ok(()), now + 600_000);
        assert_eq!(
            freshness(&store, branch, false, now + 600_000).state,
            "fresh",
            "a catalog that succeeded ten minutes ago is not a problem"
        );

        // A branch that has never attempted one is not suspect either: the
        // changefeed carries the catalog and the refresh is the fallback.
        let fresh_store = Store::open("").unwrap();
        fresh_store
            .kv_put(&format!("{K_LAST_FULL}b2"), "2026-09-19T10:00:00Z")
            .unwrap();
        record_pull_outcome(&fresh_store, "b2", Ok(()), now);
        assert_eq!(freshness(&fresh_store, "b2", false, now).state, "fresh");
    }

    /// Coalescing must never swallow an announced change: a change announced
    /// AFTER the in-flight request went out cannot be in its response.
    #[tokio::test]
    async fn a_change_announced_after_the_request_went_out_is_not_coalesced_away() {
        use std::sync::Arc;
        use std::sync::atomic::{AtomicU32, Ordering};

        let flight = Arc::new(PullFlight::default());
        let pulls = Arc::new(AtomicU32::new(0));
        // Lets the test hold the first pull open while the second caller arrives.
        let gate = Arc::new(tokio::sync::Notify::new());

        let f1 = {
            let (flight, pulls, gate) = (flight.clone(), pulls.clone(), gate.clone());
            tokio::spawn(async move {
                single_flight(&flight, || async {
                    pulls.fetch_add(1, Ordering::SeqCst);
                    gate.notified().await;
                    Ok(0)
                })
                .await
            })
        };
        // Wait until the first pull is genuinely in flight.
        while pulls.load(Ordering::SeqCst) == 0 {
            tokio::task::yield_now().await;
        }

        // NOW the change is announced — too late for the request in flight.
        flight.announce();
        let f2 = {
            let (flight, pulls) = (flight.clone(), pulls.clone());
            tokio::spawn(async move {
                single_flight(&flight, || async {
                    pulls.fetch_add(1, Ordering::SeqCst);
                    Ok(0)
                })
                .await
            })
        };
        tokio::task::yield_now().await;
        gate.notify_one();
        f1.await.unwrap().unwrap();
        f2.await.unwrap().unwrap();

        assert_eq!(
            pulls.load(Ordering::SeqCst),
            2,
            "the second caller must pull for itself — the in-flight request was \
             already sent when it arrived, so its change could not be in it"
        );
    }

    /// The other half of the same rule: with NOTHING newly announced, a burst
    /// of callers still costs exactly one request.
    #[tokio::test]
    async fn callers_with_nothing_newer_to_fetch_still_share_one_request() {
        use std::sync::Arc;
        use std::sync::atomic::{AtomicU32, Ordering};

        let flight = Arc::new(PullFlight::default());
        let pulls = Arc::new(AtomicU32::new(0));
        let gate = Arc::new(tokio::sync::Notify::new());

        let mut tasks = Vec::new();
        for i in 0..4 {
            let (flight, pulls, gate) = (flight.clone(), pulls.clone(), gate.clone());
            tasks.push(tokio::spawn(async move {
                single_flight(&flight, || async {
                    pulls.fetch_add(1, Ordering::SeqCst);
                    if i == 0 {
                        gate.notified().await;
                    }
                    Ok(0)
                })
                .await
            }));
        }
        tokio::time::sleep(std::time::Duration::from_millis(30)).await;
        gate.notify_one();
        for t in tasks {
            t.await.unwrap().unwrap();
        }
        assert_eq!(
            pulls.load(Ordering::SeqCst),
            1,
            "a burst of nudges with nothing new announced is one request"
        );
    }

    #[test]
    fn a_teller_rows_limits_survive_the_servers_nulls() {
        let row = serde_json::json!({
            "capabilities": ["inventory.waste.record", "orders.void"],
            "limits": {
                "inventory.waste.record": {"max_amount": null, "max_percent": null, "max_value": 500, "max_age_minutes": null, "own": null},
                "orders.void": {"max_amount": null, "max_percent": null, "max_value": null, "max_age_minutes": 10, "own": true}
            }
        });
        let g = super::grants_from_teller_row(&row).expect("grants");
        assert_eq!(g.limits["inventory.waste.record"].max_value, Some(500));
        assert!(!g.limits["inventory.waste.record"].own);
        assert!(g.limits["orders.void"].own);
        assert_eq!(g.limits["orders.void"].max_age_minutes, Some(10));
    }

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
        let err = apply_page_with(&store, B, &page, None, &Protected::new(), true, None, &mut |n| {
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

    /// The lean decode (rows kept raw until applied) lands exactly what the
    /// in-memory response does: every table, the cursor, the window.
    #[test]
    fn a_raw_body_applies_exactly_like_the_decoded_response() {
        let till = serde_json::json!({"id": "t1", "branch_id": B, "teller_id": "u", "status": "open",
            "opened_at": "2026-09-14T08:00:00Z", "opening_cash": 1000});
        let order = serde_json::json!({"id": "o1", "idempotency_key": uid("k1"), "till_id": uid("t1"), "branch_id": B,
            "status": "completed", "payment_method": "cash", "total_amount": 700, "created_at": "2026-09-14T09:00:00Z",
            "payment_legs": [{"method": "cash", "amount": 700, "is_cash": true}], "items": [{"item_name": "Latte \"hot\" \u{e9} \\ tab\t"}]});
        let mut page = full(ALL_TYPES, vec![("till", till), ("order", order), ("discount", serde_json::json!({"id": "d1", "v": 1}))], 42);
        page.ledger_window = Some(Some(Box::new(madar_api::models::LedgerWindow::new("2026-09-12T00:00:00Z".into()))));
        let body = serde_json::to_string(&page).unwrap();

        let a = Store::open("").unwrap();
        apply_page(&a, B, &page, &Protected::new(), true).unwrap();
        let b = Store::open("").unwrap();
        let (resp, raw) = decode_pull(&body).unwrap();
        assert!(resp.data.is_none(), "rows are not decoded up front");
        assert_eq!(raw.as_ref().unwrap()["order"].len(), 1);
        apply_page_with(&b, B, &resp, raw.as_ref(), &Protected::new(), true, None, &mut |_| Ok(())).unwrap();

        let dump = |s: &Store| -> Vec<String> {
            s.with_conn(|c| {
                let mut out = Vec::new();
                for (table, order_by) in [("sync_rows", "type, id"), ("ledger_tills", "id"), ("ledger_orders", "okey"), ("ledger_payments", "okey, idx")] {
                    let mut st = c.prepare(&format!("SELECT * FROM {table} ORDER BY {order_by}"))?;
                    let cols = st.column_count();
                    let rows = st.query_map([], |r| {
                        let mut line = Vec::new();
                        for i in 0..cols {
                            let v: rusqlite::types::Value = r.get(i)?;
                            line.push(format!("{v:?}"));
                        }
                        Ok(line.join("|"))
                    })?;
                    for row in rows {
                        let row = row?;
                        // Local write stamps differ between the two runs.
                        out.push(format!("{table}:{}", row.split('|').filter(|x| !x.starts_with("Integer(17")).collect::<Vec<_>>().join("|")));
                    }
                }
                Ok(out)
            })
            .map(|mut out| {
                for k in [K_NEXT, K_TYPES] {
                    out.push(format!("{k}={:?}", s.kv_get(&format!("{k}{B}")).ok().flatten()));
                }
                out
            })
            .unwrap()
        };
        let (da, db) = (dump(&a), dump(&b));
        assert!(da.iter().any(|l| l.starts_with("ledger_orders:")), "the order landed: {da:?}");
        assert_eq!(da, db);
        let window = |s: &Store| s.with_conn(|c| stream_window(c, B)).unwrap();
        assert!(window(&a).is_some());
        assert_eq!(window(&a), window(&b));
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

    /// `staff_drink` is a LEDGER type on the server (48 h window, paged with the
    /// other ledger rows). As a state type here, every page of a paged snapshot
    /// deleted the local drinks it did not carry, and a drink older than the
    /// window was deleted by the first snapshot after it — the pool then
    /// over-granted. A snapshot page never deletes a drink.
    #[test]
    fn snapshot_pages_never_delete_staff_drinks() {
        let store = Store::open("").unwrap();
        let drink = |id: &str, day: &str, seq: i64| {
            serde_json::json!({"id": id, "seq": seq, "branch_id": B, "business_date": day, "quantity": 1,
                "recorded_at": format!("{day}T09:00:00Z")})
        };
        // A drink from three days ago, already on the device.
        apply_page(&store, B, &incr(1, vec![]), &Protected::new(), true).unwrap();
        store
            .with_tx(|tx| {
                let v = drink(&uid("old"), "2026-09-20", 1);
                upsert_row(tx, B, "staff_drink", &uid("old"), 1, &v, false)?;
                mirror_local(tx, "staff_drink", &uid("old"), Some(&v))?;
                Ok(())
            })
            .unwrap();
        // Page 1 carries drink A, page 2 (the last) carries only drink B.
        let mut p1 = full(&["staff_drink"], vec![("staff_drink", drink("a", "2026-09-23", 5))], 20);
        p1.has_more = true;
        let p2 = full(&["staff_drink"], vec![("staff_drink", drink("b", "2026-09-23", 6))], 20);
        let mut paging = SnapshotPaging::default();
        for page in [&p1, &p2] {
            apply_page_with(&store, B, page, None, &Protected::new(), true, Some(&mut paging), &mut |_| Ok(())).unwrap();
        }
        let local: Vec<String> = store
            .with_conn(|c| {
                let mut st = c.prepare("SELECT id FROM ledger_staff_drinks ORDER BY id")?;
                let v = st.query_map([], |r| r.get(0))?.collect::<Result<Vec<String>, _>>()?;
                Ok(v)
            })
            .unwrap();
        let mut want = vec![uid("a"), uid("b"), uid("old")];
        want.sort();
        assert_eq!(local, want, "a drink only on page 1, and one older than 48 h, both survive");
        for id in ["a", "b", "old"] {
            assert!(row(&store, "staff_drink", id).is_some(), "{id} kept in the feed rows too");
        }
        // Never checksummed: a ledger type has no state checksum to heal against.
        assert!(!local_checksums(&store, B, &["staff_drink".to_string()]).contains_key("staff_drink"));
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
        let flight = std::sync::Arc::new(PullFlight::default());
        let mk = |c: std::sync::Arc<std::sync::atomic::AtomicU32>| {
            let flight = flight.clone();
            async move {
            single_flight(&flight, || async move {
                c.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                tokio::time::sleep(std::time::Duration::from_millis(50)).await;
                Ok(1)
            })
            .await
            }
        };
        let (a, b, c) = tokio::join!(mk(calls.clone()), mk(calls.clone()), mk(calls.clone()));
        assert!(a.is_ok() && b.is_ok() && c.is_ok());
        assert_eq!(calls.load(std::sync::atomic::Ordering::SeqCst), 1);
    }

    /// A caller that waited on a FAILED pull gets the failure, and another
    /// core's flight is not this one's.
    #[tokio::test]
    async fn a_coalesced_pull_shares_the_real_outcome_and_flights_are_per_core() {
        let flight = std::sync::Arc::new(PullFlight::default());
        let other = PullFlight::default();
        let slow_fail = |f: std::sync::Arc<PullFlight>| async move {
            single_flight(&f, || async {
                tokio::time::sleep(std::time::Duration::from_millis(50)).await;
                Err(CoreError::Offline { detail: "down".into() })
            })
            .await
        };
        let (a, b) = tokio::join!(slow_fail(flight.clone()), slow_fail(flight.clone()));
        assert!(matches!(a, Err(CoreError::Offline { .. })));
        assert!(matches!(b, Err(CoreError::Offline { .. })), "the waiter saw the failure, not Ok(0)");
        // Another core pulls for itself even while this one is busy.
        let busy = flight.clone();
        let hold = tokio::spawn(async move {
            single_flight(&busy, || async {
                tokio::time::sleep(std::time::Duration::from_millis(80)).await;
                Ok(1)
            })
            .await
        });
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        let started = std::time::Instant::now();
        assert_eq!(single_flight(&other, || async { Ok(7) }).await.unwrap(), 7);
        assert!(started.elapsed() < std::time::Duration::from_millis(60));
        assert_eq!(hold.await.unwrap().unwrap(), 1);
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
}
