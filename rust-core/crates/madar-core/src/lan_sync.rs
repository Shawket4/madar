//! LAN catch-up (anti-entropy) — OFFLINE_B_DESIGN "LAN-only operation".
//!
//! Live LAN messages reach the peers that are listening at that moment. A device
//! that restarts, joins late or loses a frame would otherwise never see what it
//! missed until the cloud is back. Catch-up closes that gap with a digest /
//! have-want exchange between any two devices of a branch:
//!
//! * **Events** — every LAN event a device published or accepted is kept in
//!   `lan_log` under its identity (a write's op key `"<op>:<handle>"`, else the
//!   message id). A device's own still-queued ops are logged too (even ones rung
//!   before the relay started). A [`SyncBody::Digest`] carries 32 bucket hashes
//!   of those keys; a peer whose buckets differ answers [`SyncBody::Have`] with its
//!   keys in those buckets; each side then asks for ([`SyncBody::Want`]) and sends
//!   ([`SyncBody::Offer`]) exactly what the other lacks. An offered event is
//!   processed like a live one (board overlay, mirror backup into the outbox, the
//!   listener), once — `lan_log` makes that restart-proof. Transitive: a device
//!   re-offers what it received, so A's op reaches C through B after A is gone.
//! * **Synced rows** — a device's rows are complete through `complete_through`
//!   (its cloud cursor, or a range a peer delivered in full). A digest names it; a
//!   device behind asks [`SyncBody::RowsWant`] for `(since, until]` and receives
//!   [`SyncBody::Rows`] pages (rows by feed seq, plus delete tombstones). Peer rows
//!   are UNCONFIRMED: stored with seq 0 (every cloud write wins) and the seq the
//!   peer claimed; a cloud pull past that seq that did not confirm them removes
//!   them. Never over a row a local op holds.
//!
//! Everything is scoped to the frame's branch (the relay verifies the branch HMAC
//! and branch id before anything here runs) and bounded: the log by age and count,
//! tombstones by age, every frame by size and item count.

use std::collections::{BTreeMap, BTreeSet};

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest as _, Sha256};

use crate::error::CoreResult;
use crate::store::Store;

/// Gossip buckets in a digest.
pub(crate) const BUCKETS: usize = 32;
/// How long an event stays re-offerable.
pub(crate) const LOG_WINDOW_MS: i64 = 36 * 3600 * 1000;
/// Most events kept (newest win).
pub(crate) const LOG_CAP: i64 = 20_000;
/// Tombstones are kept this long.
pub(crate) const TOMBSTONE_WINDOW_MS: i64 = 48 * 3600 * 1000;
/// Keys per HAVE / WANT frame.
pub(crate) const KEYS_PER_FRAME: usize = 1_000;
/// Soft byte budget of an OFFER / ROWS frame (the relay caps a line at 256 KiB).
pub(crate) const FRAME_BUDGET: usize = 160_000;
/// Rows per ROWS page.
pub(crate) const ROWS_PER_PAGE: usize = 200;
/// Largest single event or row accepted from a peer.
pub(crate) const MAX_ITEM_BYTES: usize = 64_000;
/// Largest key accepted from a peer.
pub(crate) const MAX_KEY_BYTES: usize = 200;

/// One logged LAN event.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct LogEntry {
    pub key: String,
    pub topic: String,
    pub event_type: String,
    pub data: String,
    #[serde(default)]
    pub replay_op: Option<String>,
    /// The device that minted it.
    pub origin: String,
    pub sent_at_ms: i64,
}

/// One synced row as a peer holds it (sync type or ledger type).
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct PeerRow {
    #[serde(rename = "type")]
    pub ty: String,
    pub id: String,
    pub seq: i64,
    /// The row's JSON, as a string (verbatim from the feed).
    pub data: String,
}

/// A delete the feed applied.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Tombstone {
    #[serde(rename = "type")]
    pub ty: String,
    pub id: String,
    pub seq: i64,
}

/// The catch-up messages (inside a signed `SYNC` frame).
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum SyncBody {
    Digest {
        complete_through: i64,
        log_count: i64,
        /// `BUCKETS` hex digests.
        buckets: Vec<String>,
    },
    Have {
        buckets: Vec<u8>,
        /// `(key, version)` of every event in those buckets.
        keys: Vec<(String, i64)>,
    },
    Want {
        keys: Vec<String>,
    },
    Offer {
        entries: Vec<LogEntry>,
    },
    RowsWant {
        /// Where the asking device's complete range ended when it asked.
        from: i64,
        since: i64,
        until: i64,
    },
    Rows {
        from: i64,
        since: i64,
        until: i64,
        rows: Vec<PeerRow>,
        tombstones: Vec<Tombstone>,
        next_since: i64,
        done: bool,
    },
}

// ── identities ──────────────────────────────────────────────────────────────

/// The identity of a replay envelope: `"<op>:<handle>"`, the SAME key the mirror
/// backup uses (`mirror_replay_op`), so a live copy and a catch-up copy collapse.
pub(crate) fn op_key(envelope: &Value) -> Option<String> {
    let op = envelope.get("op").and_then(Value::as_str)?;
    if op == "bump_kitchen_item" || op == "unbump_kitchen_item" {
        // A bump TOGGLES one line: one identity per line (the mirror's `kline:`
        // key), and the latest tap replaces an older one (see [`log_insert`]).
        let line = envelope.get("item_id").and_then(Value::as_str)?;
        return Some(format!("{LINE_KEY}{line}"));
    }
    let handle = envelope
        .get("request")
        .and_then(|r| r.get("idempotency_key").or_else(|| r.get("client_ref")))
        .and_then(Value::as_str)
        .or_else(|| envelope.get("item_id").and_then(Value::as_str))
        .or_else(|| envelope.get("order_id").and_then(Value::as_str))
        .or_else(|| envelope.get("ticket_id").and_then(Value::as_str))
        .unwrap_or(op);
    Some(format!("{op}:{handle}"))
}

/// The identity of a LAN message: its replay op's key, else its message id.
pub(crate) fn event_key(msg_id: &str, replay_op: Option<&str>) -> String {
    replay_op
        .and_then(|r| serde_json::from_str::<Value>(r).ok())
        .and_then(|v| op_key(&v))
        .unwrap_or_else(|| msg_id.to_string())
}

fn key_hash(key: &str) -> i64 {
    let d = Sha256::digest(key.as_bytes());
    let mut b = [0u8; 8];
    b.copy_from_slice(&d[..8]);
    (u64::from_be_bytes(b) >> 1) as i64
}

fn bucket_of(hash: i64) -> usize {
    (hash as u64 % BUCKETS as u64) as usize
}

/// An event's version: a line toggle's tap time, else 0 (immutable).
fn version_of(key: &str, sent_at_ms: i64) -> i64 {
    if key.starts_with(LINE_KEY) { sent_at_ms } else { 0 }
}

/// What an event contributes to its bucket's digest (key AND version).
fn digest_term(key_hash: i64, ver: i64) -> u64 {
    if ver == 0 {
        return key_hash as u64;
    }
    let d = Sha256::digest(format!("{key_hash}:{ver}").as_bytes());
    let mut b = [0u8; 8];
    b.copy_from_slice(&d[..8]);
    u64::from_be_bytes(b)
}

// ── the event log ───────────────────────────────────────────────────────────

/// A line-toggle identity (bump / unbump): the latest tap wins.
pub(crate) const LINE_KEY: &str = "kline:";

/// Record an event; `true` when it was not known (process it). A line toggle
/// replaces an OLDER tap of the same line (and is processed); an equal or older
/// one is not.
pub(crate) fn log_insert(conn: &Connection, branch: &str, e: &LogEntry, now_ms: i64) -> CoreResult<bool> {
    let conflict = if e.key.starts_with(LINE_KEY) {
        "ON CONFLICT(key) DO UPDATE SET topic=excluded.topic, event_type=excluded.event_type, data=excluded.data,
           replay_op=excluded.replay_op, origin=excluded.origin, sent_at_ms=excluded.sent_at_ms,
           received_at_ms=excluded.received_at_ms, ver=excluded.ver
         WHERE excluded.sent_at_ms > lan_log.sent_at_ms
            OR (excluded.sent_at_ms = lan_log.sent_at_ms AND excluded.origin > lan_log.origin)"
    } else {
        "ON CONFLICT(key) DO NOTHING"
    };
    let n = conn.execute(
        &format!(
            "INSERT INTO lan_log(key, branch_id, topic, event_type, data, replay_op, origin, sent_at_ms, received_at_ms, hash, ver)
             VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11) {conflict}"
        ),
        params![e.key, branch, e.topic, e.event_type, e.data, e.replay_op, e.origin, e.sent_at_ms, now_ms, key_hash(&e.key), version_of(&e.key, e.sent_at_ms)],
    )?;
    Ok(n > 0)
}

pub(crate) fn log_has(conn: &Connection, key: &str) -> CoreResult<bool> {
    Ok(conn.query_row("SELECT 1 FROM lan_log WHERE key=?1", [key], |_| Ok(())).optional()?.is_some())
}

/// Age and count bounds.
pub(crate) fn prune(conn: &Connection, now_ms: i64) -> CoreResult<u32> {
    let mut n = conn.execute("DELETE FROM lan_log WHERE received_at_ms < ?1", [now_ms - LOG_WINDOW_MS])? as u32;
    n += conn.execute(
        "DELETE FROM lan_log WHERE key NOT IN (SELECT key FROM lan_log ORDER BY received_at_ms DESC LIMIT ?1)",
        [LOG_CAP],
    )? as u32;
    n += conn.execute("DELETE FROM sync_tombstones WHERE recorded_at < ?1", [now_ms - TOMBSTONE_WINDOW_MS])? as u32;
    Ok(n)
}

/// This device's view for a digest.
pub(crate) fn digest(conn: &Connection, branch: &str) -> CoreResult<SyncBody> {
    let mut buckets = vec![0u64; BUCKETS];
    let mut count = 0i64;
    let mut st = conn.prepare_cached("SELECT hash, ver FROM lan_log WHERE branch_id=?1")?;
    for row in st.query_map([branch], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?)))? {
        let (h, ver) = row?;
        buckets[bucket_of(h)] ^= digest_term(h, ver);
        count += 1;
    }
    Ok(SyncBody::Digest {
        complete_through: complete_through(conn, branch)?,
        log_count: count,
        buckets: buckets.iter().map(|b| format!("{b:016x}")).collect(),
    })
}

fn my_buckets(conn: &Connection, branch: &str) -> CoreResult<Vec<String>> {
    match digest(conn, branch)? {
        SyncBody::Digest { buckets, .. } => Ok(buckets),
        _ => unreachable!(),
    }
}

fn keys_in_buckets(conn: &Connection, branch: &str, buckets: &BTreeSet<usize>) -> CoreResult<Vec<(String, i64)>> {
    let mut st = conn.prepare_cached("SELECT key, hash, ver FROM lan_log WHERE branch_id=?1 ORDER BY key")?;
    let rows = st.query_map([branch], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?)))?;
    let mut out = Vec::new();
    for row in rows {
        let (k, h, v) = row?;
        if buckets.contains(&bucket_of(h)) {
            out.push((k, v));
        }
    }
    Ok(out)
}

fn entries_for(conn: &Connection, branch: &str, keys: &[String]) -> CoreResult<Vec<LogEntry>> {
    let mut out = Vec::new();
    let mut st = conn.prepare_cached(
        "SELECT key, topic, event_type, data, replay_op, origin, sent_at_ms FROM lan_log WHERE branch_id=?1 AND key=?2",
    )?;
    for k in keys {
        if let Some(e) = st
            .query_row(params![branch, k], |r| {
                Ok(LogEntry {
                    key: r.get(0)?,
                    topic: r.get(1)?,
                    event_type: r.get(2)?,
                    data: r.get(3)?,
                    replay_op: r.get(4)?,
                    origin: r.get(5)?,
                    sent_at_ms: r.get(6)?,
                })
            })
            .optional()?
        {
            out.push(e);
        }
    }
    Ok(out)
}

/// Split offered entries into frames within the byte budget.
fn offer_frames(entries: Vec<LogEntry>) -> Vec<SyncBody> {
    let mut frames = Vec::new();
    let mut cur: Vec<LogEntry> = Vec::new();
    let mut bytes = 0usize;
    for e in entries {
        let size = e.data.len() + e.replay_op.as_ref().map(String::len).unwrap_or(0) + e.key.len() + 128;
        if size > MAX_ITEM_BYTES {
            continue;
        }
        if bytes + size > FRAME_BUDGET && !cur.is_empty() {
            frames.push(SyncBody::Offer { entries: std::mem::take(&mut cur) });
            bytes = 0;
        }
        bytes += size;
        cur.push(e);
    }
    if !cur.is_empty() {
        frames.push(SyncBody::Offer { entries: cur });
    }
    frames
}

// ── rows ────────────────────────────────────────────────────────────────────

/// Rows are complete through here: the cloud cursor, or a range a peer delivered.
pub(crate) fn complete_through(conn: &Connection, branch: &str) -> CoreResult<i64> {
    let cursor = crate::ledger::cursor_of(conn, branch)?;
    let peer: i64 = conn
        .query_row("SELECT v FROM kv WHERE k=?1", [format!("{K_COMPLETE}{branch}")], |r| r.get::<_, String>(0))
        .optional()?
        .and_then(|v| v.parse().ok())
        .unwrap_or(0);
    Ok(cursor.max(peer))
}

pub(crate) const K_COMPLETE: &str = "lan:complete_through:";

/// Rows (and tombstones) with an effective seq in `(since, until]`, one page.
pub(crate) fn rows_page(conn: &Connection, branch: &str, since: i64, until: i64) -> CoreResult<(Vec<PeerRow>, Vec<Tombstone>, i64, bool)> {
    let limit = ROWS_PER_PAGE as i64 + 1;
    // (seq, kind, type, id, data) — 0 row, 1 tombstone
    let mut items: Vec<(i64, u8, String, String, String)> = Vec::new();
    {
        let mut st = conn.prepare_cached(
            "SELECT CASE WHEN seq > 0 THEN seq ELSE peer_seq END AS e, type, id, data FROM sync_rows
              WHERE branch_id=?1 AND CASE WHEN seq > 0 THEN seq ELSE peer_seq END > ?2
                AND CASE WHEN seq > 0 THEN seq ELSE peer_seq END <= ?3
              ORDER BY e LIMIT ?4",
        )?;
        for r in st.query_map(params![branch, since, until, limit], |r| Ok((r.get(0)?, 0u8, r.get(1)?, r.get(2)?, r.get(3)?)))? {
            items.push(r?);
        }
    }
    for (table, kcol, ty, branch_filter) in [
        ("ledger_tills", "id", "till", "branch_id=?1"),
        ("ledger_orders", "okey", "order", "branch_id=?1"),
        ("ledger_cash", "ckey", "cash_movement", "till_id IN (SELECT id FROM ledger_tills WHERE branch_id=?1)"),
        ("ledger_refunds", "rkey", "refund", "till_id IN (SELECT id FROM ledger_tills WHERE branch_id=?1)"),
    ] {
        // The server's version of the row: `srv_raw` while a local op holds it.
        let sql = format!(
            "SELECT CASE WHEN srv_seq > 0 THEN srv_seq ELSE peer_seq END AS e, {kcol}, COALESCE(srv_raw, raw) FROM {table}
              WHERE {branch_filter} AND (origin <> 'local' OR srv_seq > 0)
                AND CASE WHEN srv_seq > 0 THEN srv_seq ELSE peer_seq END > ?2
                AND CASE WHEN srv_seq > 0 THEN srv_seq ELSE peer_seq END <= ?3
              ORDER BY e LIMIT ?4"
        );
        let mut st = conn.prepare_cached(&sql)?;
        for r in st.query_map(params![branch, since, until, limit], |r| {
            Ok((r.get::<_, i64>(0)?, 0u8, ty.to_string(), r.get::<_, String>(1)?, r.get::<_, String>(2)?))
        })? {
            items.push(r?);
        }
    }
    {
        let mut st = conn.prepare_cached(
            "SELECT seq, type, id FROM sync_tombstones WHERE branch_id=?1 AND seq > ?2 AND seq <= ?3 ORDER BY seq LIMIT ?4",
        )?;
        for r in st.query_map(params![branch, since, until, limit], |r| Ok((r.get(0)?, 1u8, r.get(1)?, r.get(2)?, String::new())))? {
            items.push(r?);
        }
    }
    items.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
    let done = items.len() <= ROWS_PER_PAGE;
    items.truncate(ROWS_PER_PAGE);
    let next_since = if done { until } else { items.last().map(|i| i.0).unwrap_or(until) };
    let mut rows = Vec::new();
    let mut tombs = Vec::new();
    for (seq, kind, ty, id, data) in items {
        if kind == 0 {
            // A ledger row's feed id is its server id, carried in the JSON.
            let id = if crate::ledger::is_ledger_type(&ty) {
                serde_json::from_str::<Value>(&data).ok().and_then(|v| v.get("id").and_then(Value::as_str).map(str::to_string)).unwrap_or(id)
            } else {
                id
            };
            rows.push(PeerRow { ty, id, seq, data });
        } else {
            tombs.push(Tombstone { ty, id, seq });
        }
    }
    // Keep a page inside the frame budget (rows are sorted; drop the tail and
    // say where to continue).
    let mut bytes = 0usize;
    let mut cut = rows.len();
    for (i, r) in rows.iter().enumerate() {
        bytes += r.data.len() + 96;
        if bytes > FRAME_BUDGET {
            cut = i;
            break;
        }
    }
    if cut < rows.len() {
        let resume = rows[cut].seq - 1;
        rows.truncate(cut);
        tombs.retain(|t| t.seq <= resume);
        return Ok((rows, tombs, resume.max(since), false));
    }
    Ok((rows, tombs, next_since, done))
}

/// Why a peer row was refused (tests read it).
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub(crate) enum Refused {
    UnknownType,
    Malformed,
    ForeignBranch,
    Protected,
    NotNewer,
}

/// Apply one peer row. `Ok(Err(reason))` when refused.
pub(crate) fn apply_peer_row(conn: &Connection, branch: &str, row: &PeerRow) -> CoreResult<Result<(), Refused>> {
    if !crate::sync_pull::SYNCED_TYPES.contains(&row.ty.as_str()) {
        return Ok(Err(Refused::UnknownType));
    }
    if row.seq <= 0 || row.id.is_empty() || row.id.len() > MAX_KEY_BYTES || row.data.len() > MAX_ITEM_BYTES {
        return Ok(Err(Refused::Malformed));
    }
    let Ok(v) = serde_json::from_str::<Value>(&row.data) else { return Ok(Err(Refused::Malformed)) };
    if !v.is_object() || v.get("id").and_then(Value::as_str) != Some(row.id.as_str()) {
        return Ok(Err(Refused::Malformed));
    }
    // A row that names a branch must name this one (an org's other branch, or
    // another org entirely, never lands here).
    if let Some(b) = v.get("branch_id").and_then(Value::as_str) {
        if b != branch {
            return Ok(Err(Refused::ForeignBranch));
        }
    }
    if crate::ledger::is_ledger_type(&row.ty) {
        if let Some(till) = v.get("till_id").and_then(Value::as_str) {
            let till_branch: Option<String> =
                conn.query_row("SELECT branch_id FROM ledger_tills WHERE id=?1", [till], |r| r.get(0)).optional()?;
            if till_branch.is_some_and(|b| b != branch) {
                return Ok(Err(Refused::ForeignBranch));
            }
        }
        let Some(key) = crate::ledger::key_of(&row.ty, &v) else { return Ok(Err(Refused::Malformed)) };
        let key = crate::ledger::resolve_key(conn, &row.ty, &v, &key)?;
        if crate::ledger::is_protected(conn, &row.ty, &key)? {
            return Ok(Err(Refused::Protected));
        }
        if let Some(m) = crate::ledger::stored_meta(conn, &row.ty, &key)? {
            if m.origin == "local" && m.srv_seq == 0 {
                return Ok(Err(Refused::Protected));
            }
            let effective = if m.srv_seq > 0 { m.srv_seq } else { m.peer_seq.unwrap_or(0) };
            if row.seq <= effective {
                return Ok(Err(Refused::NotNewer));
            }
        }
        crate::ledger::write_row(conn, &row.ty, &key, &v, crate::ledger::Origin::Peer(row.seq), None)?;
        return Ok(Ok(()));
    }
    let protected = conn
        .query_row(
            "SELECT 1 FROM outbox WHERE entity_type=?1 AND entity_id=?2 AND status IN ('pending','inflight','dead') LIMIT 1",
            params![row.ty, row.id],
            |_| Ok(()),
        )
        .optional()?
        .is_some();
    if protected {
        return Ok(Err(Refused::Protected));
    }
    let local: Option<(i64, Option<i64>)> = conn
        .query_row(
            "SELECT seq, peer_seq FROM sync_rows WHERE branch_id=?1 AND type=?2 AND id=?3",
            params![branch, row.ty, row.id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()?;
    if let Some((seq, peer_seq)) = local {
        let effective = if seq > 0 { seq } else { peer_seq.unwrap_or(0) };
        if row.seq <= effective {
            return Ok(Err(Refused::NotNewer));
        }
    }
    let tomb: Option<i64> = conn
        .query_row("SELECT seq FROM sync_tombstones WHERE branch_id=?1 AND type=?2 AND id=?3", params![branch, row.ty, row.id], |r| r.get(0))
        .optional()?;
    if tomb.is_some_and(|t| t >= row.seq) {
        return Ok(Err(Refused::NotNewer));
    }
    conn.execute(
        "INSERT INTO sync_rows(type, id, branch_id, seq, data, peer_seq) VALUES(?1,?2,?3,0,?4,?5)
         ON CONFLICT(branch_id,type,id) DO UPDATE SET seq=0, data=excluded.data, peer_seq=excluded.peer_seq",
        params![row.ty, row.id, branch, row.data, row.seq],
    )?;
    Ok(Ok(()))
}

/// Apply one peer tombstone (never over a newer or held row).
pub(crate) fn apply_peer_tombstone(conn: &Connection, branch: &str, t: &Tombstone) -> CoreResult<bool> {
    if !crate::sync_pull::SYNCED_TYPES.contains(&t.ty.as_str()) || t.seq <= 0 || t.id.len() > MAX_KEY_BYTES {
        return Ok(false);
    }
    let held = conn
        .query_row(
            "SELECT 1 FROM outbox WHERE entity_type=?1 AND entity_id=?2 AND status IN ('pending','inflight','dead') LIMIT 1",
            params![t.ty, t.id],
            |_| Ok(()),
        )
        .optional()?
        .is_some();
    if held {
        return Ok(false);
    }
    let mut changed = false;
    if crate::ledger::is_ledger_type(&t.ty) {
        let (table, kcol) = crate::ledger::table_of(&t.ty).unwrap();
        let key: Option<(String, i64, Option<i64>, String)> = conn
            .query_row(
                &format!("SELECT {kcol}, srv_seq, peer_seq, origin FROM {table} WHERE server_id=?1 OR {kcol}=?1 LIMIT 1"),
                [&t.id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
            )
            .optional()?;
        if let Some((key, srv, peer, origin)) = key {
            let effective = if srv > 0 { srv } else { peer.unwrap_or(0) };
            if origin != "local" && effective < t.seq && !crate::ledger::is_protected(conn, &t.ty, &key)? {
                changed = crate::ledger::delete_row(conn, &t.ty, &key)? > 0;
            }
        }
    } else {
        let local: Option<(i64, Option<i64>)> = conn
            .query_row(
                "SELECT seq, peer_seq FROM sync_rows WHERE branch_id=?1 AND type=?2 AND id=?3",
                params![branch, t.ty, t.id],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?;
        if let Some((seq, peer)) = local {
            let effective = if seq > 0 { seq } else { peer.unwrap_or(0) };
            if effective < t.seq {
                changed = conn.execute("DELETE FROM sync_rows WHERE branch_id=?1 AND type=?2 AND id=?3", params![branch, t.ty, t.id])? > 0;
            }
        }
    }
    conn.execute(
        "INSERT INTO sync_tombstones(branch_id, type, id, seq, peer, recorded_at) VALUES(?1,?2,?3,?4,1,?5)
         ON CONFLICT(branch_id,type,id) DO UPDATE SET seq=MAX(seq, excluded.seq)",
        params![branch, t.ty, t.id, t.seq, crate::ledger::now_ms()],
    )?;
    Ok(changed)
}

/// A delete the CLOUD feed applied (kept for peers).
pub(crate) fn record_tombstone(conn: &Connection, branch: &str, ty: &str, id: &str, seq: i64) -> CoreResult<()> {
    conn.execute(
        "INSERT INTO sync_tombstones(branch_id, type, id, seq, peer, recorded_at) VALUES(?1,?2,?3,?4,0,?5)
         ON CONFLICT(branch_id,type,id) DO UPDATE SET seq=MAX(seq, excluded.seq), peer=0, recorded_at=excluded.recorded_at",
        params![branch, ty, id, seq, crate::ledger::now_ms()],
    )?;
    Ok(())
}

/// After a cloud pull that brought the device through `cursor`: every peer row
/// the cloud should have confirmed by now and did not is not the server's —
/// remove it (cloud wins). Rows a local op holds stay.
pub(crate) fn purge_unconfirmed(conn: &Connection, branch: &str, cursor: i64) -> CoreResult<u32> {
    let mut n = conn.execute(
        "DELETE FROM sync_rows WHERE branch_id=?1 AND seq=0 AND peer_seq IS NOT NULL AND peer_seq <= ?2
           AND NOT EXISTS (SELECT 1 FROM outbox x WHERE x.entity_type=sync_rows.type AND x.entity_id=sync_rows.id
                             AND x.status IN ('pending','inflight','dead'))",
        params![branch, cursor],
    )? as u32;
    for (table, kcol, ty, branch_filter) in [
        ("ledger_orders", "okey", "order", "branch_id=?1"),
        ("ledger_cash", "ckey", "cash_movement", "till_id IN (SELECT id FROM ledger_tills WHERE branch_id=?1)"),
        ("ledger_refunds", "rkey", "refund", "till_id IN (SELECT id FROM ledger_tills WHERE branch_id=?1)"),
        ("ledger_tills", "id", "till", "branch_id=?1"),
    ] {
        n += conn.execute(
            &format!(
                "DELETE FROM {table} WHERE {branch_filter} AND origin='peer' AND srv_seq=0 AND peer_seq <= ?2
                   AND NOT EXISTS (SELECT 1 FROM outbox x WHERE x.entity_type='{ty}' AND x.entity_id={table}.{kcol}
                                     AND x.status IN ('pending','inflight','dead'))"
            ),
            params![branch, cursor],
        )? as u32;
    }
    Ok(n)
}

// ── the exchange ────────────────────────────────────────────────────────────

/// What handling one catch-up message produced.
#[derive(Default, Debug)]
pub(crate) struct Outcome {
    /// Frames to send back to the sender.
    pub replies: Vec<SyncBody>,
    /// Events newly accepted (the caller processes them like live messages).
    pub accepted: Vec<LogEntry>,
    /// Rows / tombstones applied.
    pub rows_applied: u32,
    /// Items refused (malformed, foreign, held, not newer).
    pub refused: u32,
}

/// Handle one catch-up message from a peer, in one transaction. Accepted events
/// are logged here; the caller runs their side effects (overlay, mirror backup,
/// listener) — exactly once, because only newly logged events are returned.
pub(crate) fn handle(store: &Store, branch: &str, body: &SyncBody, now_ms: i64) -> CoreResult<Outcome> {
    store.with_tx_touch(|tx, touched| {
        let mut out = Outcome::default();
        match body {
            SyncBody::Digest { complete_through: theirs, buckets, .. } => {
                let mine = my_buckets(tx, branch)?;
                let differ: BTreeSet<usize> = (0..BUCKETS)
                    .filter(|i| buckets.get(*i).map(String::as_str) != mine.get(*i).map(String::as_str))
                    .collect();
                if !differ.is_empty() {
                    let keys = keys_in_buckets(tx, branch, &differ)?;
                    let ids: Vec<u8> = differ.iter().map(|b| *b as u8).collect();
                    if keys.is_empty() {
                        out.replies.push(SyncBody::Have { buckets: ids.clone(), keys: Vec::new() });
                    }
                    for chunk in keys.chunks(KEYS_PER_FRAME) {
                        out.replies.push(SyncBody::Have { buckets: ids.clone(), keys: chunk.to_vec() });
                    }
                }
                let ours = complete_through(tx, branch)?;
                if *theirs > ours {
                    out.replies.push(SyncBody::RowsWant { from: ours, since: ours, until: *theirs });
                }
            }
            SyncBody::Have { buckets, keys } => {
                let scope: BTreeSet<usize> = buckets.iter().map(|b| *b as usize % BUCKETS).collect();
                let theirs: BTreeMap<&str, i64> = keys.iter().map(|(k, v)| (k.as_str(), *v)).collect();
                let mine = keys_in_buckets(tx, branch, &scope)?;
                let mine_map: BTreeMap<&str, i64> = mine.iter().map(|(k, v)| (k.as_str(), *v)).collect();
                // What they have and we lack (or hold an older tap of).
                let want: Vec<String> = keys
                    .iter()
                    .filter(|(k, v)| k.len() <= MAX_KEY_BYTES && mine_map.get(k.as_str()).is_none_or(|mv| mv < v))
                    .map(|(k, _)| k.clone())
                    .collect();
                for chunk in want.chunks(KEYS_PER_FRAME) {
                    out.replies.push(SyncBody::Want { keys: chunk.to_vec() });
                }
                // What we have in those buckets and they lack (or hold older).
                // A HAVE split over frames can make us offer something they list
                // in a later frame; the receiver dedups it.
                let give: Vec<String> = mine
                    .iter()
                    .filter(|(k, v)| theirs.get(k.as_str()).is_none_or(|tv| tv < v))
                    .map(|(k, _)| k.clone())
                    .collect();
                out.replies.extend(offer_frames(entries_for(tx, branch, &give)?));
            }
            SyncBody::Want { keys } => {
                let keys: Vec<String> = keys.iter().take(KEYS_PER_FRAME).cloned().collect();
                out.replies.extend(offer_frames(entries_for(tx, branch, &keys)?));
            }
            SyncBody::Offer { entries } => {
                for e in entries {
                    if !valid_entry(e) {
                        out.refused += 1;
                        continue;
                    }
                    if log_insert(tx, branch, e, now_ms)? {
                        out.accepted.push(e.clone());
                    }
                }
            }
            SyncBody::RowsWant { from, since, until } => {
                let ours = complete_through(tx, branch)?;
                // Only what we hold completely, never past it.
                let until = (*until).min(ours);
                if until > *since {
                    let (rows, tombstones, next_since, done) = rows_page(tx, branch, *since, until)?;
                    out.replies.push(SyncBody::Rows { from: *from, since: *since, until, rows, tombstones, next_since, done });
                }
            }
            SyncBody::Rows { from, since, until, rows, tombstones, next_since, done } => {
                let mut seen_tables = BTreeSet::new();
                // Tills first, so a movement or refund can find its till's branch.
                let mut ordered: Vec<&PeerRow> = rows.iter().collect();
                ordered.sort_by_key(|r| if r.ty == "till" { 0 } else { 1 });
                for r in ordered {
                    if r.seq <= *since || r.seq > *until {
                        out.refused += 1;
                        continue;
                    }
                    match apply_peer_row(tx, branch, r)? {
                        Ok(()) => {
                            out.rows_applied += 1;
                            seen_tables.insert(crate::changes::table_for_sync_type(&r.ty));
                        }
                        Err(_) => out.refused += 1,
                    }
                }
                for t in tombstones {
                    if t.seq <= *since || t.seq > *until {
                        out.refused += 1;
                        continue;
                    }
                    if apply_peer_tombstone(tx, branch, t)? {
                        out.rows_applied += 1;
                        seen_tables.insert(crate::changes::table_for_sync_type(&t.ty));
                    }
                }
                touched.extend(seen_tables);
                if *done {
                    // A range delivered in full, starting inside what we already
                    // held completely, extends it.
                    let ours = complete_through(tx, branch)?;
                    if *from <= ours && *until > ours {
                        tx.execute(
                            "INSERT INTO kv(k, v, updated_at) VALUES(?1, ?2, ?3)
                             ON CONFLICT(k) DO UPDATE SET v=excluded.v, updated_at=excluded.updated_at",
                            params![format!("{K_COMPLETE}{branch}"), until.to_string(), chrono::Utc::now().to_rfc3339()],
                        )?;
                    }
                } else if *next_since > *since && *next_since < *until {
                    out.replies.push(SyncBody::RowsWant { from: *from, since: *next_since, until: *until });
                }
            }
        }
        Ok(out)
    })
}

fn valid_entry(e: &LogEntry) -> bool {
    if e.key.is_empty() || e.key.len() > MAX_KEY_BYTES || e.data.len() > MAX_ITEM_BYTES {
        return false;
    }
    if e.replay_op.as_ref().is_some_and(|r| r.len() > MAX_ITEM_BYTES) {
        return false;
    }
    // A write's identity is DERIVED from its envelope: a peer cannot file an op
    // under another op's key (which would suppress the real one here).
    match &e.replay_op {
        Some(r) => serde_json::from_str::<Value>(r).ok().and_then(|v| op_key(&v)).as_deref() == Some(e.key.as_str()),
        None => true,
    }
}

/// Group helper for tests and diagnostics: keys by bucket.
#[allow(dead_code)]
pub(crate) fn bucket_counts(conn: &Connection, branch: &str) -> CoreResult<BTreeMap<usize, usize>> {
    let mut out = BTreeMap::new();
    let mut st = conn.prepare("SELECT hash FROM lan_log WHERE branch_id=?1")?;
    for h in st.query_map([branch], |r| r.get::<_, i64>(0))? {
        *out.entry(bucket_of(h?)).or_insert(0) += 1;
    }
    Ok(out)
}
