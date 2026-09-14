//! Local store — embedded SQLite (PLAN §8). The source of truth the UI reads
//! from, online or offline:
//!   - `kv`          : read-through mirror (canonical wire JSON per key),
//!   - `outbox`      : the durable, append-only command queue (global FIFO `seq`),
//!   - `id_map`      : the client-temp-id ↔ server-id bridge for reconciliation,
//!   - `sync_cursors`: per-stream high-water mark for days-offline catch-up,
//!   - `sentry_outbox`: the durable crash/error-report queue (see `crate::obs`).
//!
//! A single writer behind a `Mutex` (FFI calls serialize here); WAL gives
//! snapshot-consistent reads. `db_path == ""` opens in-memory (tests / first boot).

use std::sync::Mutex;
use std::time::Duration;

use rusqlite::{params, Connection, OptionalExtension};

use crate::error::CoreResult;

const SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS kv (
  k          TEXT PRIMARY KEY,
  v          TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Binary cache (e.g. the org logo PNG for receipt printing). Separate from `kv`
-- because that column is TEXT; this one is a real BLOB.
CREATE TABLE IF NOT EXISTS blob (
  k          TEXT PRIMARY KEY,
  v          BLOB NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS id_map (
  entity_type    TEXT NOT NULL,
  client_temp_id TEXT NOT NULL,
  server_id      TEXT NOT NULL,
  PRIMARY KEY (entity_type, client_temp_id)
);

CREATE TABLE IF NOT EXISTS sync_cursors (
  stream          TEXT PRIMARY KEY,
  last_server_seq INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS outbox (
  seq             INTEGER PRIMARY KEY AUTOINCREMENT,  -- global FIFO order
  id              TEXT NOT NULL UNIQUE,               -- client-minted uuid (dedups enqueue)
  op_type         TEXT NOT NULL,                      -- create_order | void_order | open_till | ...
  idempotency_key TEXT NOT NULL,                      -- in-body exactly-once token (dedups on the server)
  payload         TEXT NOT NULL,                      -- canonical request JSON
  event_at        TEXT NOT NULL,                      -- client real-event time (RFC3339)
  enqueued_at     TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending',    -- pending|inflight|acked|dead
  attempts        INTEGER NOT NULL DEFAULT 0,
  last_error      TEXT,
  server_id       TEXT,                               -- set on ack
  depends_on_seq  INTEGER,                            -- gate dependents (e.g. order after its open_till)
  next_attempt_at INTEGER NOT NULL DEFAULT 0,         -- epoch ms backoff gate (0 = ready now)
  synced_at       INTEGER,                            -- epoch ms when acked (recovery-log retention)
  user_id         TEXT,                               -- teller who enqueued (drain scopes to JWT holder)
  clock_offset_ms INTEGER,                            -- device→server skew at enqueue (correct-at-sync)
  shift_id        TEXT                                -- LEGACY (<= v0.6): never written since the tills rework
);
CREATE INDEX IF NOT EXISTS outbox_status_seq ON outbox(status, seq);

-- The Sentry envelope queue. A POS terminal's NORMAL state is offline, and
-- sentry-rust has no persistence of its own: an in-memory transport would lose
-- every crash report a terminal produced between one uplink and the next (i.e.
-- exactly the reports we care about). So error reports get the same treatment as
-- money: written to disk first, drained later. Deliberately a SEPARATE table from
-- `outbox` — telemetry must never share a FIFO, a retry budget or a dependency
-- gate with sales commands, and must never be able to block them.
CREATE TABLE IF NOT EXISTS sentry_outbox (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,  -- FIFO (oldest = smallest)
  envelope        BLOB NOT NULL,                      -- the serialized Sentry envelope
  created_at      INTEGER NOT NULL,                   -- epoch ms (age cap)
  attempts        INTEGER NOT NULL DEFAULT 0,
  next_attempt_at INTEGER NOT NULL DEFAULT 0          -- epoch ms backoff gate
);
CREATE INDEX IF NOT EXISTS sentry_outbox_due ON sentry_outbox(next_attempt_at, id);
"#;

/// Idempotent column adds for stores created before the offline-orchestration
/// columns existed. `CREATE TABLE IF NOT EXISTS` won't alter an existing table,
/// so older DBs get the new columns here (errors on already-present columns are
/// expected and ignored).
const MIGRATIONS: &[&str] = &[
    "ALTER TABLE outbox ADD COLUMN next_attempt_at INTEGER NOT NULL DEFAULT 0",
    "ALTER TABLE outbox ADD COLUMN synced_at INTEGER",
    "ALTER TABLE outbox ADD COLUMN user_id TEXT",
    "ALTER TABLE outbox ADD COLUMN clock_offset_ms INTEGER",
    "ALTER TABLE outbox ADD COLUMN shift_id TEXT",
    // ── tills rework (TILLS_CONTRACT §4.3 / §10.3) ──
    "ALTER TABLE outbox ADD COLUMN till_id TEXT",
    "ALTER TABLE outbox ADD COLUMN device_id TEXT",
    "ALTER TABLE outbox ADD COLUMN entity_type TEXT",
    "ALTER TABLE outbox ADD COLUMN entity_id TEXT",
];

/// Tables + indexes created AFTER the column migrations (they reference them).
const POST_MIGRATION_SCHEMA: &str = r#"
CREATE INDEX IF NOT EXISTS outbox_till_seq ON outbox(till_id, status, seq);
CREATE INDEX IF NOT EXISTS outbox_entity ON outbox(entity_type, entity_id, status);
-- One changefeed mirror for every POS-synced type (`sync_pull.rs`).
CREATE TABLE IF NOT EXISTS sync_rows (
  type      TEXT NOT NULL,
  id        TEXT NOT NULL,
  branch_id TEXT NOT NULL,
  seq       INTEGER NOT NULL,
  data      TEXT NOT NULL,
  PRIMARY KEY (branch_id, type, id)
);
CREATE INDEX IF NOT EXISTS sync_rows_type ON sync_rows(branch_id, type);
-- Content-addressed asset files on disk (`assets.rs`).
CREATE TABLE IF NOT EXISTS asset_files (
  hash        TEXT PRIMARY KEY,
  ext         TEXT NOT NULL,
  bytes       INTEGER NOT NULL,
  verified_at TEXT NOT NULL
);
"#;

/// kv guard for the one-shot tills data migration.
pub(crate) const MIGR_TILLS_V1: &str = "migr:tills_v1";

/// An op to enqueue. `id` is the client uuid (re-enqueue with the same `id` is a
/// no-op, so retries/replays don't duplicate).
#[derive(Debug, Clone, Default)]
pub struct NewOutboxOp {
    pub id: String,
    pub op_type: String,
    pub idempotency_key: String,
    pub payload: String,
    pub event_at: String,
    /// Gate: this op won't send until the op at this seq is acked.
    pub depends_on_seq: Option<i64>,
    /// The teller who enqueued it (the drain only sends the JWT holder's ops).
    pub user_id: Option<String>,
    /// Device→server clock skew (ms) captured at enqueue, for correct-at-sync.
    pub clock_offset_ms: Option<i64>,
    /// The till this op belongs to (per-till FIFO + close gating; None = till-less).
    pub till_id: Option<String>,
    /// The device that queued it (sent on the replay envelope).
    pub device_id: Option<String>,
    /// The synced entity this op changes, so a pull never clobbers it (§10.3 A3).
    pub entity_type: Option<String>,
    pub entity_id: Option<String>,
}

/// A queued outbox row.
#[derive(Debug, Clone)]
pub struct OutboxItem {
    pub seq: i64,
    pub id: String,
    pub op_type: String,
    pub idempotency_key: String,
    pub payload: String,
    pub event_at: String,
    pub status: String,
    pub attempts: i64,
    pub last_error: Option<String>,
    pub server_id: Option<String>,
    pub depends_on_seq: Option<i64>,
    pub next_attempt_at: i64,
    pub user_id: Option<String>,
    pub clock_offset_ms: Option<i64>,
    pub till_id: Option<String>,
    pub device_id: Option<String>,
    pub entity_type: Option<String>,
    pub entity_id: Option<String>,
}

/// One queued Sentry envelope awaiting upload (see `crate::obs`).
#[derive(Debug, Clone)]
pub struct SentryEnvelopeRow {
    pub id: i64,
    /// Failed upload attempts so far — the exponent of the retry backoff.
    pub attempts: i64,
    /// The serialized envelope, uploaded verbatim.
    pub envelope: Vec<u8>,
}

pub struct Store {
    conn: Mutex<Connection>,
    /// Logical-table change notifications, sent after a write commits.
    changes: crate::changes::TableChanges,
    /// The file was written by a newer build: the connection is `query_only`
    /// (every write fails), and the sync applier does not run.
    future_schema: bool,
    /// Injected SQLite faults (the simulation harness and fault tests).
    faults: Mutex<FaultState>,
}

/// A real SQLite failure to inject.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FaultKind {
    /// The statement running ~`steps` VM step batches in is interrupted
    /// (`SQLITE_INTERRUPT`): a crash in the middle of a statement or transaction.
    Interrupt { steps: u32 },
    /// The database may not grow any more (`SQLITE_FULL`): disk full.
    DiskFull,
}

#[derive(Default)]
struct FaultState {
    /// Store accesses left before the fault arms.
    countdown: Option<u32>,
    kind: Option<FaultKind>,
    armed: bool,
    fired: bool,
}

impl Store {
    /// Open (or create) the store and run migrations. Empty path → in-memory.
    pub fn open(db_path: &str) -> CoreResult<Store> {
        let conn = if db_path.is_empty() {
            Connection::open_in_memory()?
        } else {
            Connection::open(db_path)?
        };
        // The apply path runs every snapshot row through a handful of cached
        // statements; room for them beside everything else the core prepares.
        conn.set_prepared_statement_cache_capacity(64);
        // Best-effort pragmas (in-memory ignores WAL).
        let _ = conn.pragma_update(None, "journal_mode", "WAL");
        let _ = conn.pragma_update(None, "synchronous", "NORMAL");
        let _ = conn.pragma_update(None, "foreign_keys", "ON");
        // Give freed pages back to the filesystem instead of holding the file at
        // its high-water mark forever. Without this, deleting a year of cached
        // shift history (or draining a huge offline backlog) frees space INSIDE
        // the file and the device never sees a byte of it back. INCREMENTAL
        // rather than FULL so the reclaim is a bounded step we run after the
        // retention sweep, not a stall on every commit.
        //
        // On a database that already has tables this pragma only takes effect
        // after a VACUUM, which `reclaim_free_pages` performs once.
        let _ = conn.pragma_update(None, "auto_vacuum", "INCREMENTAL");
        // Cap the WAL. It is truncated back to this on checkpoint, so one large
        // burst (a day of offline sales draining at once) cannot leave a
        // permanently inflated -wal sidecar next to the database.
        let _ = conn.pragma_update(None, "journal_size_limit", 4 * 1024 * 1024);
        conn.busy_timeout(Duration::from_secs(5))?;
        // A file written by a NEWER build (design §8 "App upgrade"): open it in
        // read-only safe mode. No DDL, no migration, no write of any kind — this
        // build does not know the shape it would be writing — so the queue a
        // newer build left stays exactly as that build wrote it, reads still
        // work, and the host is told (freshness reason `newer_build`).
        if crate::schema::user_version(&conn)? > crate::schema::latest() {
            conn.pragma_update(None, "query_only", "ON")?;
            return Ok(Store {
                conn: Mutex::new(conn),
                changes: crate::changes::TableChanges::new(),
                future_schema: true,
                faults: Mutex::new(FaultState::default()),
            });
        }
        conn.execute_batch(SCHEMA)?;
        // Bring older stores up to the current outbox shape (no-op on fresh DBs).
        // MUST run before any index that references the new columns — on an
        // upgraded DB the columns don't exist until these ALTERs add them.
        for stmt in MIGRATIONS {
            let _ = conn.execute(stmt, []); // "duplicate column" is expected + fine
        }
        // The backoff-gate index references `next_attempt_at`, so it's created
        // only AFTER the migrations guarantee that column exists.
        let _ = conn.execute(
            "CREATE INDEX IF NOT EXISTS outbox_due ON outbox(status, next_attempt_at, seq)",
            [],
        );
        conn.execute_batch(POST_MIGRATION_SCHEMA)?;
        migrate_tills_v1(&conn)?;
        let mut conn = conn;
        let migrated = crate::schema::migrate(&mut conn)?;
        Ok(Store {
            conn: Mutex::new(conn),
            changes: crate::changes::TableChanges::new(),
            future_schema: migrated.future_schema,
            faults: Mutex::new(FaultState::default()),
        })
    }

    /// Arm a real SQLite fault after `after` more store accesses (0: the next
    /// one). It stays in force until [`Self::clear_faults`].
    pub fn inject_fault(&self, after: u32, kind: FaultKind) {
        let mut f = self.faults.lock().unwrap_or_else(|e| e.into_inner());
        *f = FaultState { countdown: Some(after), kind: Some(kind), armed: false, fired: false };
    }

    /// Remove an injected fault (and undo its effect on the connection).
    pub fn clear_faults(&self) {
        let mut f = self.faults.lock().unwrap_or_else(|e| e.into_inner());
        let was = f.kind.filter(|_| f.armed);
        *f = FaultState::default();
        drop(f);
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        match was {
            Some(FaultKind::Interrupt { .. }) => {
                let _ = conn.progress_handler(0, None::<fn() -> bool>);
            }
            Some(FaultKind::DiskFull) => {
                let _ = conn.pragma_update(None, "max_page_count", 1_073_741_823i64);
            }
            None => {}
        }
    }

    /// Whether an injected fault has armed.
    pub fn fault_armed(&self) -> bool {
        self.faults.lock().unwrap_or_else(|e| e.into_inner()).armed
    }

    /// The store was written by a newer build than this one.
    pub fn future_schema(&self) -> bool {
        self.future_schema
    }

    /// Subscribe to logical-table change notifications (see `changes.rs`).
    pub fn subscribe_changes(&self) -> crate::changes::TableChangeSubscription {
        self.changes.subscribe()
    }

    /// Announce that `tables` changed (call AFTER the write committed).
    pub fn emit_changes<'a>(&self, tables: impl IntoIterator<Item = &'a str>) {
        self.changes.emit(tables);
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Connection> {
        // Poisoning only happens if a holder panicked mid-write; recover the
        // guard rather than cascading the panic across the FFI.
        let guard = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        self.maybe_arm_fault(&guard);
        guard
    }

    fn maybe_arm_fault(&self, conn: &Connection) {
        let mut f = self.faults.lock().unwrap_or_else(|e| e.into_inner());
        let Some(n) = f.countdown else { return };
        if f.armed {
            return;
        }
        if n > 0 {
            f.countdown = Some(n - 1);
            return;
        }
        f.armed = true;
        f.fired = true;
        match f.kind {
            Some(FaultKind::Interrupt { steps }) => {
                let calls = std::sync::atomic::AtomicU32::new(0);
                let _ = conn.progress_handler(64, Some(move || calls.fetch_add(1, std::sync::atomic::Ordering::Relaxed) >= steps));
            }
            Some(FaultKind::DiskFull) => {
                let pages: i64 = conn.pragma_query_value(None, "page_count", |r| r.get(0)).unwrap_or(1);
                let _ = conn.pragma_update(None, "max_page_count", pages);
            }
            None => {}
        }
    }

    // ── read-through mirror ─────────────────────────────────────
    pub fn kv_put(&self, key: &str, json: &str) -> CoreResult<()> {
        self.lock().execute(
            "INSERT INTO kv(k, v, updated_at) VALUES(?1, ?2, ?3)
             ON CONFLICT(k) DO UPDATE SET v=excluded.v, updated_at=excluded.updated_at",
            params![key, json, now_iso()],
        )?;
        Ok(())
    }
    /// Write several kv rows in ONE transaction: all land or none do (a crash
    /// can never leave half a catalog).
    pub fn kv_put_many(&self, rows: &[(&str, &str)]) -> CoreResult<()> {
        self.with_tx(|tx| {
            let now = now_iso();
            for (k, v) in rows {
                tx.execute(
                    "INSERT INTO kv(k, v, updated_at) VALUES(?1, ?2, ?3)
                     ON CONFLICT(k) DO UPDATE SET v=excluded.v, updated_at=excluded.updated_at",
                    params![k, v, now],
                )?;
            }
            Ok(())
        })
    }
    pub fn kv_delete(&self, key: &str) -> CoreResult<()> {
        self.lock().execute("DELETE FROM kv WHERE k=?1", [key])?;
        Ok(())
    }
    pub fn kv_get(&self, key: &str) -> CoreResult<Option<String>> {
        Ok(self
            .lock()
            .query_row("SELECT v FROM kv WHERE k=?1", [key], |r| {
                r.get::<_, String>(0)
            })
            .optional()?)
    }

    /// Upsert raw bytes (e.g. the org logo PNG) into the binary cache.
    pub fn blob_put(&self, key: &str, bytes: &[u8]) -> CoreResult<()> {
        self.lock().execute(
            "INSERT INTO blob(k, v, updated_at) VALUES(?1, ?2, ?3)
             ON CONFLICT(k) DO UPDATE SET v=excluded.v, updated_at=excluded.updated_at",
            params![key, bytes, now_iso()],
        )?;
        Ok(())
    }
    /// Delete a blob row (no-op when absent).
    pub fn blob_delete(&self, key: &str) -> CoreResult<()> {
        self.lock()
            .execute("DELETE FROM blob WHERE k = ?1", [key])?;
        Ok(())
    }

    pub fn blob_get(&self, key: &str) -> CoreResult<Option<Vec<u8>>> {
        Ok(self
            .lock()
            .query_row("SELECT v FROM blob WHERE k=?1", [key], |r| {
                r.get::<_, Vec<u8>>(0)
            })
            .optional()?)
    }

    // ── id_map (temp-id ↔ server-id) ────────────────────────────
    pub fn id_map_put(
        &self,
        entity: &str,
        client_temp_id: &str,
        server_id: &str,
    ) -> CoreResult<()> {
        self.lock().execute(
            "INSERT INTO id_map(entity_type, client_temp_id, server_id) VALUES(?1,?2,?3)
             ON CONFLICT(entity_type, client_temp_id) DO UPDATE SET server_id=excluded.server_id",
            params![entity, client_temp_id, server_id],
        )?;
        Ok(())
    }
    pub fn id_map_get(&self, entity: &str, client_temp_id: &str) -> CoreResult<Option<String>> {
        Ok(self
            .lock()
            .query_row(
                "SELECT server_id FROM id_map WHERE entity_type=?1 AND client_temp_id=?2",
                params![entity, client_temp_id],
                |r| r.get(0),
            )
            .optional()?)
    }

    // ── per-stream sync cursors ─────────────────────────────────
    pub fn cursor_get(&self, stream: &str) -> CoreResult<i64> {
        Ok(self
            .lock()
            .query_row(
                "SELECT last_server_seq FROM sync_cursors WHERE stream=?1",
                [stream],
                |r| r.get(0),
            )
            .optional()?
            .unwrap_or(0))
    }
    pub fn cursor_set(&self, stream: &str, seq: i64) -> CoreResult<()> {
        self.lock().execute(
            "INSERT INTO sync_cursors(stream, last_server_seq) VALUES(?1,?2)
             ON CONFLICT(stream) DO UPDATE SET last_server_seq=excluded.last_server_seq",
            params![stream, seq],
        )?;
        Ok(())
    }

    // ── durable outbox ──────────────────────────────────────────
    /// Enqueue an op. Idempotent on `id`: re-enqueuing the same id is a no-op
    /// and returns the existing `seq` (so a double-tap or a re-run never dups).
    pub fn enqueue(&self, op: &NewOutboxOp) -> CoreResult<i64> {
        let seq = enqueue_on(&self.lock(), op)?;
        self.changes.emit(crate::changes::tables_for_op(&op.op_type));
        Ok(seq)
    }

    /// Upsert a state-TOGGLING LAN-mirror backup (kitchen bump/unbump on one line),
    /// keyed line-scoped so the LATEST tap wins. Unlike [`Self::enqueue`] (keep-first),
    /// a repeated tap after an opposite one must OVERWRITE the queued backup — else
    /// the mirror replays a STALE direction if the originating device dies before its
    /// own primary op reaches the cloud. Only a still-re-sendable (pending/dead) row
    /// is replaced + re-armed; an in-flight send is left to finish (bump/unbump is
    /// idempotent server-side, so a momentary stale-in-flight is harmless).
    pub fn upsert_mirror(&self, op: &NewOutboxOp) -> CoreResult<()> {
        self.lock().execute(
            "INSERT INTO outbox(id, op_type, idempotency_key, payload, event_at, enqueued_at,
                                depends_on_seq, user_id, clock_offset_ms, till_id,
                                device_id, entity_type, entity_id)
             VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13)
             ON CONFLICT(id) DO UPDATE SET
                payload=excluded.payload, op_type=excluded.op_type,
                idempotency_key=excluded.idempotency_key, event_at=excluded.event_at,
                status='pending', attempts=0, next_attempt_at=0, last_error=NULL
             WHERE outbox.status IN ('pending','dead')",
            params![
                op.id,
                op.op_type,
                op.idempotency_key,
                op.payload,
                op.event_at,
                now_iso(),
                op.depends_on_seq,
                op.user_id,
                op.clock_offset_ms,
                op.till_id,
                op.device_id,
                op.entity_type,
                op.entity_id
            ],
        )?;
        Ok(())
    }

    /// Items ready to send NOW for the drain — `pending` AND past their backoff
    /// gate (`next_attempt_at <= now_ms`), in FIFO order. Scoped to `user_id`
    /// when given (a different teller's queued ops must sync under THEIR token,
    /// not the current holder's — legacy NULL-user rows are always included).
    pub fn due_for_sync(&self, now_ms: i64, user_id: Option<&str>) -> CoreResult<Vec<OutboxItem>> {
        let conn = self.lock();
        let (sql, mapper): (String, _) = if let Some(uid) = user_id {
            (
                format!(
                    "SELECT {COLS} FROM outbox WHERE status='pending' AND next_attempt_at<=?1 \
                         AND (user_id IS NULL OR user_id=?2) ORDER BY seq ASC"
                ),
                Some(uid),
            )
        } else {
            (
                format!("SELECT {COLS} FROM outbox WHERE status='pending' AND next_attempt_at<=?1 ORDER BY seq ASC"),
                None,
            )
        };
        let mut stmt = conn.prepare(&sql)?;
        let rows: Vec<OutboxItem> = match mapper {
            Some(uid) => stmt
                .query_map(params![now_ms, uid], map_item)?
                .collect::<Result<Vec<_>, _>>()?,
            None => stmt
                .query_map(params![now_ms], map_item)?
                .collect::<Result<Vec<_>, _>>()?,
        };
        Ok(rows)
    }

    /// Drainable items (pending/inflight) in FIFO order — counts + the
    /// queued-orders projection. (Not backoff-gated; that's `due_for_sync`.)
    pub fn pending(&self) -> CoreResult<Vec<OutboxItem>> {
        let conn = self.lock();
        let mut stmt = conn.prepare(&format!(
            "SELECT {COLS} FROM outbox WHERE status IN ('pending','inflight') ORDER BY seq ASC"
        ))?;
        let rows: Vec<OutboxItem> = stmt
            .query_map([], map_item)?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    pub fn pending_count(&self) -> CoreResult<u32> {
        let n: i64 = self.lock().query_row(
            "SELECT COUNT(*) FROM outbox WHERE status IN ('pending','inflight')",
            [],
            |r| r.get(0),
        )?;
        Ok(n as u32)
    }

    /// Count of dead (exhausted/rejected) outbox rows — the "needs attention"
    /// signal for the sync chip. Acked rows are gone, so this is only the stuck set.
    pub fn dead_count(&self) -> CoreResult<u32> {
        let n: i64 = self.lock().query_row(
            "SELECT COUNT(*) FROM outbox WHERE status = 'dead'",
            [],
            |r| r.get(0),
        )?;
        Ok(n as u32)
    }

    /// Every un-acked outbox row (pending/inflight/dead) in FIFO order — the
    /// sync-center read. Acked rows are hidden (nothing to act on).
    pub fn list_active(&self) -> CoreResult<Vec<OutboxItem>> {
        let conn = self.lock();
        let mut stmt = conn.prepare(
            &format!("SELECT {COLS} FROM outbox WHERE status IN ('pending','inflight','dead') ORDER BY seq ASC"))?;
        let rows: Vec<OutboxItem> = stmt
            .query_map([], map_item)?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// The same rows [`list_active`](Self::list_active) returns, narrowed to the
    /// given op types by SQL rather than by the caller.
    ///
    /// Every caller of `list_active` immediately discards all but one or two op
    /// types — but `payload` holds an entire cart for every queued sale, so on a
    /// till carrying a day of offline orders, looking for the handful of
    /// `cash_movement` or `void_order` rows was materializing every one of those
    /// carts into Rust strings and dropping them again. Pushing the predicate
    /// down means only the rows actually wanted are ever built.
    pub fn list_active_of_types(&self, op_types: &[&str]) -> CoreResult<Vec<OutboxItem>> {
        if op_types.is_empty() {
            return Ok(Vec::new());
        }
        let conn = self.lock();
        let placeholders = vec!["?"; op_types.len()].join(",");
        let mut stmt = conn.prepare(&format!(
            "SELECT {COLS} FROM outbox \
             WHERE status IN ('pending','inflight','dead') AND op_type IN ({placeholders}) \
             ORDER BY seq ASC"
        ))?;
        let rows: Vec<OutboxItem> = stmt
            .query_map(rusqlite::params_from_iter(op_types.iter()), map_item)?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// The status of one row by seq (`None` if discarded) — prerequisite gating.
    pub fn status_of_seq(&self, seq: i64) -> CoreResult<Option<String>> {
        Ok(self
            .lock()
            .query_row("SELECT status FROM outbox WHERE seq=?1", [seq], |r| {
                r.get(0)
            })
            .optional()?)
    }

    /// The seq of the live (non-acked) op with this client `id`, for wiring a
    /// dependency at enqueue (e.g. an order onto its still-queued open_till).
    /// `None` when no such row exists or it's already acked (no gate needed).
    pub fn live_seq_of(&self, id: &str) -> CoreResult<Option<i64>> {
        Ok(self
            .lock()
            .query_row(
                "SELECT seq FROM outbox WHERE id=?1 AND status IN ('pending','inflight','dead')",
                [id],
                |r| r.get(0),
            )
            .optional()?)
    }



    /// Reset every dead command back to `pending` (clearing its error + backoff)
    /// so the next drain retries it. Returns how many were requeued.
    pub fn requeue_dead(&self) -> CoreResult<u32> {
        let n = self.lock().execute(
            "UPDATE outbox SET status='pending', last_error=NULL, attempts=0, next_attempt_at=0 WHERE status='dead'", [])?;
        Ok(n as u32)
    }

    /// Discard a single DEAD command by client id (the teller gives up on it).
    /// Only dead rows can be discarded — a pending/inflight op might still land.
    pub fn discard_dead(&self, id: &str) -> CoreResult<bool> {
        let n = self.lock().execute(
            "DELETE FROM outbox WHERE id=?1 AND status='dead'",
            params![id],
        )?;
        Ok(n > 0)
    }



    /// Count create_order ops blocked because their `open_till` dependency
    /// DEAD-lettered — the "stuck sales" the sync center surfaces (and the auto-heal
    /// clears). They are neither sent (dependency dead) nor lost (still queued).
    pub fn count_orders_blocked_by_dead_dep(&self) -> CoreResult<u32> {
        let n: i64 = self.lock().query_row(
            "SELECT COUNT(*) FROM outbox o \
             WHERE o.op_type='create_order' AND o.status IN ('pending','inflight') \
               AND o.depends_on_seq IS NOT NULL \
               AND EXISTS (SELECT 1 FROM outbox d WHERE d.seq=o.depends_on_seq AND d.status='dead')",
            [],
            |r| r.get(0),
        )?;
        Ok(n as u32)
    }



    /// G3 (TILLS_CONTRACT §4.4): true while a LOWER-seq order/void/cash/refund/settle
    /// for `till_id` is still pending or inflight (excluding `exclude_seq`, the close
    /// itself). A `dead` op does NOT hold the close: it surfaces in the stuck list
    /// and a late replay onto the closed till is accepted server-side (the server
    /// recomputes cash and reconciliation), so closing never deadlocks on it.
    pub fn has_live_till_writes(&self, till_id: &str, exclude_seq: i64) -> CoreResult<bool> {
        let n: i64 = self.lock().query_row(
            "SELECT COUNT(*) FROM outbox \
             WHERE status IN ('pending','inflight') AND till_id=?1 AND seq<>?2 \
               AND (?2 < 0 OR seq < ?2) \
               AND op_type NOT IN ('open_till','open_shift','close_till','close_shift')",
            params![till_id, exclude_seq],
            |r| r.get(0),
        )?;
        Ok(n > 0)
    }

    /// Requeue (dead → pending, clearing error + backoff) every dead op for one
    /// till — the retry for a dead `open_till` and everything waiting on it.
    pub fn requeue_dead_for_till(&self, till_id: &str) -> CoreResult<u32> {
        let n = self.lock().execute(
            "UPDATE outbox SET status='pending', last_error=NULL, attempts=0, next_attempt_at=0 \
             WHERE status='dead' AND till_id=?1",
            params![till_id],
        )?;
        Ok(n as u32)
    }

    /// Every un-acked op of one till, FIFO.
    pub fn list_active_for_till(&self, till_id: &str) -> CoreResult<Vec<OutboxItem>> {
        let conn = self.lock();
        let mut stmt = conn.prepare(&format!(
            "SELECT {COLS} FROM outbox \
             WHERE status IN ('pending','inflight','dead') AND till_id=?1 ORDER BY seq ASC"
        ))?;
        let rows: Vec<OutboxItem> = stmt
            .query_map([till_id], map_item)?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// Dead-letter counts per till (till-less ops under `""`), for the sync center.
    pub fn dead_count_by_till(&self) -> CoreResult<Vec<(String, u32)>> {
        let conn = self.lock();
        let mut stmt = conn.prepare(
            "SELECT COALESCE(till_id,''), COUNT(*) FROM outbox WHERE status='dead' \
             GROUP BY COALESCE(till_id,'') ORDER BY 1",
        )?;
        let rows = stmt
            .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)? as u32)))?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// G1/G2 gating for one due op: `true` when it must wait this pass.
    /// - its explicit dependency is pending/inflight/dead (never cascades);
    /// - an EARLIER op of the same till is still pending/inflight (per-till FIFO;
    ///   a dead earlier op isolates itself and does not hold the till's queue,
    ///   except a dead `open_till`, which holds every op of its till);
    /// - it is a close and the till still has live writes (G3).
    pub fn must_wait(&self, item: &OutboxItem) -> CoreResult<bool> {
        if let Some(dep) = item.depends_on_seq {
            if matches!(
                self.status_of_seq(dep)?.as_deref(),
                Some("pending") | Some("inflight") | Some("dead")
            ) {
                return Ok(true);
            }
        }
        let Some(till) = item.till_id.as_deref() else {
            return Ok(false);
        };
        let conn = self.lock();
        let blocking: i64 = conn.query_row(
            "SELECT COUNT(*) FROM outbox WHERE till_id=?1 AND seq < ?2 AND ( \
                 status IN ('pending','inflight') \
                 OR (status='dead' AND op_type IN ('open_till','open_shift')) )",
            params![till, item.seq],
            |r| r.get(0),
        )?;
        Ok(blocking > 0)
    }

    /// Run `f` inside ONE SQLite transaction (commit on Ok, roll back on Err).
    pub(crate) fn with_tx<R>(
        &self,
        f: impl FnOnce(&rusqlite::Transaction<'_>) -> CoreResult<R>,
    ) -> CoreResult<R> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let out = f(&tx)?;
        tx.commit()?;
        Ok(out)
    }

    /// [`Self::with_tx`] that also broadcasts the logical tables `f` names in
    /// `touched` — after, and only after, the commit.
    pub(crate) fn with_tx_touch<R>(
        &self,
        f: impl FnOnce(&rusqlite::Transaction<'_>, &mut Vec<&'static str>) -> CoreResult<R>,
    ) -> CoreResult<R> {
        let mut touched: Vec<&'static str> = Vec::new();
        let out = self.with_tx(|tx| f(tx, &mut touched))?;
        self.changes.emit(touched.iter().copied());
        Ok(out)
    }

    /// Read-only access to the connection for multi-statement reads.
    pub(crate) fn with_conn<R>(&self, f: impl FnOnce(&Connection) -> CoreResult<R>) -> CoreResult<R> {
        let conn = self.lock();
        f(&conn)
    }

    /// Every kv row under `prefix` (literal prefix match), key order.
    pub fn kv_list_prefix(&self, prefix: &str) -> CoreResult<Vec<(String, String)>> {
        let conn = self.lock();
        let mut stmt = conn.prepare(
            "SELECT k, v FROM kv WHERE substr(k, 1, length(?1)) = ?1 ORDER BY k",
        )?;
        let rows = stmt
            .query_map([prefix], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// Mark an op inflight (about to hit the network). Crash recovery
    /// (`recover_inflight`) returns it to pending if we die before the ack.
    pub fn mark_inflight(&self, seq: i64) -> CoreResult<()> {
        self.lock().execute(
            "UPDATE outbox SET status='inflight' WHERE seq=?1",
            params![seq],
        )?;
        Ok(())
    }

    /// Crash recovery: any row stranded `inflight` (killed mid-request) goes back
    /// to `pending` so the drain retries it (idempotency makes the retry safe).
    pub fn recover_inflight(&self) -> CoreResult<u32> {
        let n = self.lock().execute(
            "UPDATE outbox SET status='pending' WHERE status='inflight'",
            [],
        )?;
        Ok(n as u32)
    }

    pub fn mark_acked(&self, seq: i64, server_id: Option<&str>) -> CoreResult<()> {
        self.lock().execute(
            "UPDATE outbox SET status='acked', server_id=?2, synced_at=?3 WHERE seq=?1",
            params![seq, server_id, now_ms()],
        )?;
        self.changes.emit([crate::changes::OUTBOX]);
        Ok(())
    }

    pub fn mark_dead(&self, seq: i64, error: &str) -> CoreResult<()> {
        self.lock().execute(
            "UPDATE outbox SET status='dead', last_error=?2 WHERE seq=?1",
            params![seq, error],
        )?;
        self.changes.emit([crate::changes::OUTBOX]);
        Ok(())
    }

    /// Counted retry: bump attempts, set the next backoff gate, record the error.
    pub fn mark_retry(&self, seq: i64, error: &str, next_attempt_at: i64) -> CoreResult<()> {
        self.lock().execute(
            "UPDATE outbox SET status='pending', attempts=attempts+1, last_error=?2, next_attempt_at=?3 WHERE seq=?1",
            params![seq, error, next_attempt_at])?;
        Ok(())
    }

    /// Uncounted reschedule: a connectivity blip or a 401-park must never push an
    /// op toward `dead`, so it sets the next gate WITHOUT bumping attempts.
    pub fn mark_retry_no_count(&self, seq: i64, next_attempt_at: i64) -> CoreResult<()> {
        self.lock().execute(
            "UPDATE outbox SET status='pending', next_attempt_at=?2 WHERE seq=?1",
            params![seq, next_attempt_at],
        )?;
        Ok(())
    }

    /// Clear the connectivity (no-count) backoff gate so a freshly-confirmed
    /// reconnect drains its backlog NOW instead of waiting out the ~15s network
    /// retry window. Only touches items rescheduled purely for connectivity
    /// (`attempts=0`, a positive gate) — a counted server-error backoff
    /// (`attempts>0`) keeps its exponential gate. Returns rows un-gated.
    pub fn clear_network_backoff(&self) -> CoreResult<u32> {
        let n = self.lock().execute(
            "UPDATE outbox SET next_attempt_at=0 \
             WHERE status='pending' AND attempts=0 AND next_attempt_at>0",
            [],
        )?;
        Ok(n as u32)
    }

    /// Drop acked recovery-log rows older than `cutoff_ms` (kept ~48h so a crash
    /// between server ack and local writes never loses the record).
    pub fn purge_acked_older_than(&self, cutoff_ms: i64) -> CoreResult<u32> {
        let n = self.lock().execute(
            "DELETE FROM outbox WHERE status='acked' AND synced_at IS NOT NULL AND synced_at < ?1",
            params![cutoff_ms],
        )?;
        Ok(n as u32)
    }

    /// Drop the dead rows left by the five held-order ops that could only ever
    /// dead-letter (a parked draft is device-local; the backend has no
    /// held-order endpoints). Returns how many went.
    ///
    /// A one-time sweep for anyone who has been running v0.2.0, where every
    /// park wrote a permanent stuck row into the sync screen's list. Scoped to
    /// exactly those five op types: dead rows of any other kind are real
    /// failures someone may still need to see.
    pub fn purge_dead_held_ops(&self) -> CoreResult<u32> {
        let n = self.lock().execute(
            "DELETE FROM outbox WHERE status='dead' AND op_type IN \
             ('park_held_order','claim_held_order','release_held_order', \
              'discard_held_order','complete_held_order')",
            [],
        )?;
        Ok(n as u32)
    }

    /// Return free pages to the filesystem after a delete-heavy pass.
    ///
    /// Deleting rows only frees pages INSIDE the database file; the file itself
    /// never shrinks on its own. This runs a bounded `incremental_vacuum`, and
    /// on a store created before `auto_vacuum` was set it first performs the
    /// one-time full `VACUUM` that switches the mode on (recorded in `kv`, so it
    /// happens once per device rather than on every launch).
    ///
    /// Best effort throughout: a busy database just keeps its free pages until
    /// the next sweep.
    pub fn reclaim_free_pages(&self) -> CoreResult<()> {
        const MIGRATED_KEY: &str = "store:auto_vacuum_migrated";
        let already = self.kv_get(MIGRATED_KEY)?.is_some();
        {
            let conn = self.lock();
            let mode: i64 = conn
                .pragma_query_value(None, "auto_vacuum", |r| r.get(0))
                .unwrap_or(0);
            // 0 = NONE: an existing file created before the pragma. VACUUM is the
            // only way to switch it, and it rewrites the whole database — so do
            // it once, ever.
            if mode == 0 && !already {
                let _ = conn.execute_batch("PRAGMA auto_vacuum=INCREMENTAL; VACUUM;");
            }
            // Bounded: reclaim up to 256 pages (~1 MB at the 4 KiB default) per
            // sweep so this never becomes a long stall on the drain path.
            let _ = conn.execute_batch("PRAGMA incremental_vacuum(256);");
        }
        if !already {
            self.kv_put(MIGRATED_KEY, "1")?;
        }
        Ok(())
    }

    /// Drop every queued command. Only for an explicit destructive sign-out —
    /// offline shifts are real sales, so the default logout preserves them.
    pub fn wipe_outbox(&self) -> CoreResult<()> {
        self.lock().execute("DELETE FROM outbox", [])?;
        Ok(())
    }

    // ── durable Sentry envelope queue (crate::obs) ──────────────
    //
    // Same shape as the command outbox above (FIFO id, attempts, `next_attempt_at`
    // backoff gate), deliberately in its own table. Telemetry is strictly
    // second-class: it is capped by BOTH count and age so a terminal that stays
    // offline for a week cannot grow the DB unbounded, and every method here is
    // fallible-but-ignorable — a failure to record an error report must never
    // surface to a teller or abort a sale.

    /// Persist one serialized envelope. Ready to send immediately.
    pub fn sentry_enqueue(&self, envelope: &[u8], now_ms: i64) -> CoreResult<i64> {
        let conn = self.lock();
        conn.execute(
            "INSERT INTO sentry_outbox(envelope, created_at) VALUES(?1, ?2)",
            params![envelope, now_ms],
        )?;
        Ok(conn.last_insert_rowid())
    }

    /// Envelopes ready to send NOW (past their backoff gate), oldest first, as
    /// `(id, attempts, envelope)` — `attempts` drives the per-row exponential
    /// backoff, exactly like the command outbox's.
    pub fn sentry_due(&self, now_ms: i64, limit: u32) -> CoreResult<Vec<SentryEnvelopeRow>> {
        let conn = self.lock();
        let mut stmt = conn.prepare(
            "SELECT id, attempts, envelope FROM sentry_outbox WHERE next_attempt_at <= ?1 \
             ORDER BY id ASC LIMIT ?2",
        )?;
        let rows = stmt
            .query_map(params![now_ms, limit], |r| {
                Ok(SentryEnvelopeRow {
                    id: r.get(0)?,
                    attempts: r.get(1)?,
                    envelope: r.get(2)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// Delete one envelope — it was accepted, or permanently rejected (a 4xx
    /// that will never succeed; retrying it forever would just burn battery).
    pub fn sentry_drop(&self, id: i64) -> CoreResult<()> {
        self.lock()
            .execute("DELETE FROM sentry_outbox WHERE id = ?1", params![id])?;
        Ok(())
    }

    /// Re-gate one envelope for a later attempt (network down, 5xx, rate limit).
    pub fn sentry_defer(&self, id: i64, next_attempt_at: i64) -> CoreResult<()> {
        self.lock().execute(
            "UPDATE sentry_outbox SET attempts = attempts + 1, next_attempt_at = ?2 \
             WHERE id = ?1",
            params![id, next_attempt_at],
        )?;
        Ok(())
    }

    /// Re-gate EVERY queued envelope (a 429 with a `Retry-After` applies to the
    /// whole project, not one report).
    pub fn sentry_defer_all(&self, next_attempt_at: i64) -> CoreResult<()> {
        self.lock().execute(
            "UPDATE sentry_outbox SET next_attempt_at = ?1 WHERE next_attempt_at < ?1",
            params![next_attempt_at],
        )?;
        Ok(())
    }

    /// Enforce the queue caps: drop anything older than `cutoff_ms`, then trim to
    /// the newest `max_rows`. Returns how many rows were discarded. This is the
    /// unbounded-growth guard — a terminal offline for days keeps only the most
    /// recent slice of its error history, which is the useful part anyway.
    pub fn sentry_prune(&self, cutoff_ms: i64, max_rows: u32) -> CoreResult<u32> {
        let conn = self.lock();
        let mut n = conn.execute(
            "DELETE FROM sentry_outbox WHERE created_at < ?1",
            params![cutoff_ms],
        )?;
        n += conn.execute(
            "DELETE FROM sentry_outbox WHERE id NOT IN \
             (SELECT id FROM sentry_outbox ORDER BY id DESC LIMIT ?1)",
            params![max_rows],
        )?;
        Ok(n as u32)
    }

    /// How many envelopes are still waiting to reach Sentry (drives `flush`).
    pub fn sentry_pending_count(&self) -> CoreResult<u32> {
        Ok(self
            .lock()
            .query_row("SELECT COUNT(*) FROM sentry_outbox", [], |r| {
                r.get::<_, i64>(0)
            })? as u32)
    }
}

/// Insert one outbox op on `conn` (a plain connection or an open transaction),
/// idempotent on `id`; returns the row's `seq`. The caller emits the change.
pub(crate) fn enqueue_on(conn: &Connection, op: &NewOutboxOp) -> CoreResult<i64> {
    conn.execute(
        "INSERT INTO outbox(id, op_type, idempotency_key, payload, event_at, enqueued_at,
                            depends_on_seq, user_id, clock_offset_ms, till_id,
                            device_id, entity_type, entity_id)
         VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13)
         ON CONFLICT(id) DO NOTHING",
        params![
            op.id,
            op.op_type,
            op.idempotency_key,
            op.payload,
            op.event_at,
            now_iso(),
            op.depends_on_seq,
            op.user_id,
            op.clock_offset_ms,
            op.till_id,
            op.device_id,
            op.entity_type,
            op.entity_id
        ],
    )?;
    Ok(conn.query_row("SELECT seq FROM outbox WHERE id=?1", [&op.id], |r| r.get(0))?)
}

/// Mark an op acked on `conn` (inside the fold transaction).
pub(crate) fn mark_acked_on(conn: &Connection, seq: i64, server_id: Option<&str>) -> CoreResult<()> {
    conn.execute(
        "UPDATE outbox SET status='acked', server_id=?2, synced_at=?3 WHERE seq=?1",
        params![seq, server_id, now_ms()],
    )?;
    Ok(())
}

/// The column list every `OutboxItem` SELECT shares (kept in sync with `map_item`).
const COLS: &str = "seq,id,op_type,idempotency_key,payload,event_at,status,attempts,last_error,\
                    server_id,depends_on_seq,next_attempt_at,user_id,clock_offset_ms,till_id,\
                    device_id,entity_type,entity_id";

pub(crate) const OUTBOX_COLS: &str = COLS;

/// [`map_item`] for other modules (the ledger backfill).
pub(crate) fn map_outbox_item(r: &rusqlite::Row<'_>) -> rusqlite::Result<OutboxItem> {
    map_item(r)
}

/// Map a row selected with `COLS` into an `OutboxItem`.
fn map_item(r: &rusqlite::Row<'_>) -> rusqlite::Result<OutboxItem> {
    Ok(OutboxItem {
        seq: r.get(0)?,
        id: r.get(1)?,
        op_type: r.get(2)?,
        idempotency_key: r.get(3)?,
        payload: r.get(4)?,
        event_at: r.get(5)?,
        status: r.get(6)?,
        attempts: r.get(7)?,
        last_error: r.get(8)?,
        server_id: r.get(9)?,
        depends_on_seq: r.get(10)?,
        next_attempt_at: r.get(11)?,
        user_id: r.get(12)?,
        clock_offset_ms: r.get(13)?,
        till_id: r.get(14)?,
        device_id: r.get(15)?,
        entity_type: r.get(16)?,
        entity_id: r.get(17)?,
    })
}

/// One-shot tills data migration (TILLS_CONTRACT §4.3), guarded by kv
/// `migr:tills_v1`. Carries every queued row over — nothing is deleted and no
/// payload is rewritten (legacy payloads decode through serde aliases at send):
/// `till_id` from the legacy `shift_id` column, and the legacy op names renamed.
/// Runs in one transaction so a crash leaves either the old or the new state.
fn migrate_tills_v1(conn: &Connection) -> CoreResult<()> {
    let done: Option<String> = conn
        .query_row("SELECT v FROM kv WHERE k=?1", [MIGR_TILLS_V1], |r| r.get(0))
        .optional()?;
    if done.as_deref() == Some("done") {
        return Ok(());
    }
    conn.execute_batch(
        "BEGIN IMMEDIATE;
         UPDATE outbox SET till_id = shift_id WHERE till_id IS NULL AND shift_id IS NOT NULL;
         -- v0.6 chained every open behind the previous shift's close (one drawer per
         -- branch). Tills are independent now: drop that cross-till gate only.
         UPDATE outbox SET depends_on_seq = NULL
          WHERE op_type = 'open_shift' AND status IN ('pending','inflight','dead')
            AND depends_on_seq IN (SELECT seq FROM outbox WHERE op_type = 'close_shift');
         UPDATE outbox SET op_type = 'open_till'  WHERE op_type = 'open_shift'  AND status IN ('pending','inflight','dead');
         UPDATE outbox SET op_type = 'close_till' WHERE op_type = 'close_shift' AND status IN ('pending','inflight','dead');",
    )?;
    let res = conn.execute(
        "INSERT INTO kv(k, v, updated_at) VALUES(?1, 'done', ?2)
         ON CONFLICT(k) DO UPDATE SET v='done', updated_at=excluded.updated_at",
        params![MIGR_TILLS_V1, now_iso()],
    );
    match res {
        Ok(_) => conn.execute_batch("COMMIT;")?,
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            return Err(e.into());
        }
    }
    Ok(())
}

fn now_iso() -> String {
    chrono::Utc::now().to_rfc3339()
}

/// Epoch milliseconds — the unit of `next_attempt_at` / `synced_at` (matches the
/// Flutter outbox so backoff/retention windows are identical).
fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

#[cfg(test)]
mod tests {
    use super::*;

    // ════════════════════════════════════════════════════════════════════════
    // tills rework: migrations, per-till gating, dead-letter isolation
    // ════════════════════════════════════════════════════════════════════════

    fn till_op(id: &str, op_type: &str, till: Option<&str>) -> NewOutboxOp {
        NewOutboxOp {
            id: id.into(),
            op_type: op_type.into(),
            idempotency_key: id.into(),
            payload: "{}".into(),
            event_at: "2026-09-13T10:00:00Z".into(),
            till_id: till.map(Into::into),
            ..Default::default()
        }
    }

    fn column_names(s: &Store) -> Vec<String> {
        s.with_conn(|c| {
            let mut st = c.prepare("PRAGMA table_info(outbox)")?;
            let names = st
                .query_map([], |r| r.get::<_, String>(1))?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(names)
        })
        .unwrap()
    }

    #[test]
    fn store_migrates_outbox_till_columns() {
        let path = temp_db("tills_cols");
        build_old_outbox(&path, &["till_id", "device_id", "entity_type", "entity_id"]);
        let s = Store::open(path.to_str().unwrap()).unwrap();
        let cols = column_names(&s);
        for c in ["shift_id", "till_id", "device_id", "entity_type", "entity_id"] {
            assert!(cols.iter().any(|x| x == c), "missing column {c}");
        }
        let idx: i64 = s
            .with_conn(|c| {
                Ok(c.query_row(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='outbox_till_seq'",
                    [],
                    |r| r.get(0),
                )?)
            })
            .unwrap();
        assert_eq!(idx, 1);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn store_migrates_legacy_op_types_once() {
        let path = temp_db("tills_ops");
        {
            // A v0.6-shaped store: legacy op names + the shift_id column, no till_id.
            let conn = Connection::open(&path).unwrap();
            conn.execute_batch(
                "CREATE TABLE kv (k TEXT PRIMARY KEY, v TEXT NOT NULL, updated_at TEXT NOT NULL);
                 CREATE TABLE outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
                   op_type TEXT NOT NULL, idempotency_key TEXT NOT NULL, payload TEXT NOT NULL,
                   event_at TEXT NOT NULL, enqueued_at TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
                   attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, server_id TEXT, depends_on_seq INTEGER,
                   next_attempt_at INTEGER NOT NULL DEFAULT 0, synced_at INTEGER, user_id TEXT,
                   clock_offset_ms INTEGER, shift_id TEXT);
                 INSERT INTO outbox(id,op_type,idempotency_key,payload,event_at,enqueued_at,status,shift_id)
                   VALUES ('S1','open_shift','S1','{\"branch_id\":\"B\",\"request\":{\"id\":\"S1\"}}','t','t','pending','S1'),
                          ('S1:close','close_shift','S1:close','{\"shift_id\":\"S1\",\"request\":{\"closing_cash_declared\":1}}','t','t','dead','S1'),
                          ('S0','open_shift','S0','{}','t','t','acked','S0'),
                          ('o1','create_order','o1','{\"request\":{\"shift_id\":\"S1\"}}','t','t','pending','S1');",
            )
            .unwrap();
        }
        let s = Store::open(path.to_str().unwrap()).unwrap();
        let rows = s.list_active().unwrap();
        assert_eq!(rows.len(), 3, "no row lost");
        let by_id = |id: &str| rows.iter().find(|r| r.id == id).unwrap().clone();
        assert_eq!(by_id("S1").op_type, "open_till");
        assert_eq!(by_id("S1:close").op_type, "close_till");
        assert_eq!(by_id("o1").till_id.as_deref(), Some("S1"));
        // Payloads are untouched (translated at send time).
        assert!(by_id("o1").payload.contains("shift_id"));
        // Acked history is not rewritten.
        let acked: String = s
            .with_conn(|c| {
                Ok(c.query_row("SELECT op_type FROM outbox WHERE id='S0'", [], |r| r.get(0))?)
            })
            .unwrap();
        assert_eq!(acked, "open_shift");
        assert_eq!(s.kv_get(MIGR_TILLS_V1).unwrap().as_deref(), Some("done"));
        // Once only: a legacy-named row written after the guard is left alone.
        s.enqueue(&till_op("late", "open_shift", Some("S9"))).unwrap();
        drop(s);
        let s = Store::open(path.to_str().unwrap()).unwrap();
        assert!(s
            .list_active()
            .unwrap()
            .iter()
            .any(|r| r.id == "late" && r.op_type == "open_shift"));
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn per_till_fifo_independent_tills() {
        let s = Store::open("").unwrap();
        let a1 = s.enqueue(&till_op("a1", "create_order", Some("A"))).unwrap();
        s.enqueue(&till_op("a2", "create_order", Some("A"))).unwrap();
        s.enqueue(&till_op("b1", "create_order", Some("B"))).unwrap();
        s.enqueue(&till_op("n1", "fire_open_ticket", None)).unwrap();
        let due = s.due_for_sync(now_ms() + 1, None).unwrap();
        let wait: Vec<(String, bool)> = due
            .iter()
            .map(|i| (i.id.clone(), s.must_wait(i).unwrap()))
            .collect();
        assert_eq!(
            wait,
            vec![
                ("a1".into(), false),
                ("a2".into(), true), // behind a1 in till A
                ("b1".into(), false), // till B does not wait on A
                ("n1".into(), false), // till-less never waits on a till
            ]
        );
        // A inflight still holds A's tail; acked releases it.
        s.mark_inflight(a1).unwrap();
        let a2 = s.due_for_sync(now_ms() + 1, None).unwrap().into_iter().find(|i| i.id == "a2").unwrap();
        assert!(s.must_wait(&a2).unwrap());
        s.mark_acked(a1, None).unwrap();
        assert!(!s.must_wait(&a2).unwrap());
    }

    #[test]
    fn dead_op_isolated_to_its_till() {
        let s = Store::open("").unwrap();
        let a1 = s.enqueue(&till_op("a1", "create_order", Some("A"))).unwrap();
        s.enqueue(&till_op("a2", "create_order", Some("A"))).unwrap();
        s.enqueue(&till_op("b1", "create_order", Some("B"))).unwrap();
        s.mark_dead(a1, "422").unwrap();
        let due = s.due_for_sync(now_ms() + 1, None).unwrap();
        for i in &due {
            assert!(!s.must_wait(i).unwrap(), "{} must not wait on a dead order", i.id);
        }
        // A dead OPEN holds only its own till.
        let t2 = Store::open("").unwrap();
        let open = t2.enqueue(&till_op("A", "open_till", Some("A"))).unwrap();
        t2.enqueue(&till_op("a1", "create_order", Some("A"))).unwrap();
        t2.enqueue(&till_op("b1", "create_order", Some("B"))).unwrap();
        t2.mark_dead(open, "transport").unwrap();
        let due = t2.due_for_sync(now_ms() + 1, None).unwrap();
        let a1 = due.iter().find(|i| i.id == "a1").unwrap();
        let b1 = due.iter().find(|i| i.id == "b1").unwrap();
        assert!(t2.must_wait(a1).unwrap());
        assert!(!t2.must_wait(b1).unwrap());
        assert_eq!(t2.dead_count_by_till().unwrap(), vec![("A".to_string(), 1)]);
        // Retry for the till revives the open and releases its queue.
        assert_eq!(t2.requeue_dead_for_till("A").unwrap(), 1);
        assert_eq!(t2.list_active_for_till("A").unwrap().len(), 2);
    }

    #[test]
    fn close_waits_on_pending_not_dead() {
        let s = Store::open("").unwrap();
        let o1 = s.enqueue(&till_op("o1", "create_order", Some("T"))).unwrap();
        let o2 = s.enqueue(&till_op("o2", "cash_movement", Some("T"))).unwrap();
        let close = s.enqueue(&till_op("T:close", "close_till", Some("T"))).unwrap();
        assert!(s.has_live_till_writes("T", close).unwrap());
        s.mark_acked(o1, None).unwrap();
        assert!(s.has_live_till_writes("T", close).unwrap(), "o2 still pending");
        s.mark_dead(o2, "boom").unwrap();
        assert!(
            !s.has_live_till_writes("T", close).unwrap(),
            "a dead write does not hold the close"
        );
        // A write queued AFTER the close (higher seq) never holds it.
        s.enqueue(&till_op("late", "create_order", Some("T"))).unwrap();
        assert!(!s.has_live_till_writes("T", close).unwrap());
        // Another till's writes never hold it.
        s.enqueue(&till_op("x", "create_order", Some("U"))).unwrap();
        assert!(!s.has_live_till_writes("T", close).unwrap());
    }

    #[test]
    fn kv_list_prefix_is_literal() {
        let s = Store::open("").unwrap();
        s.kv_put("device_till:u1", "t1").unwrap();
        s.kv_put("device_till:u2", "t2").unwrap();
        s.kv_put("device_tillXu3", "t3").unwrap();
        let rows = s.kv_list_prefix("device_till:").unwrap();
        assert_eq!(rows.len(), 2);
    }

    fn op(id: &str) -> NewOutboxOp {
        NewOutboxOp {
            id: id.into(),
            op_type: "create_order".into(),
            idempotency_key: id.into(),
            payload: r#"{"total":2280}"#.into(),
            event_at: "2026-06-19T10:00:00Z".into(),
            ..Default::default()
        }
    }

    #[test]
    fn kv_roundtrip_and_overwrite() {
        let s = Store::open("").unwrap();
        assert_eq!(s.kv_get("menu").unwrap(), None);
        s.kv_put("menu", "[1,2]").unwrap();
        assert_eq!(s.kv_get("menu").unwrap().as_deref(), Some("[1,2]"));
        s.kv_put("menu", "[3]").unwrap();
        assert_eq!(s.kv_get("menu").unwrap().as_deref(), Some("[3]"));
    }

    #[test]
    fn id_map_and_cursor_roundtrip() {
        let s = Store::open("").unwrap();
        s.id_map_put("order", "local-1", "srv-99").unwrap();
        assert_eq!(
            s.id_map_get("order", "local-1").unwrap().as_deref(),
            Some("srv-99")
        );
        assert_eq!(s.id_map_get("order", "missing").unwrap(), None);
        assert_eq!(s.cursor_get("orders").unwrap(), 0);
        s.cursor_set("orders", 42).unwrap();
        assert_eq!(s.cursor_get("orders").unwrap(), 42);
    }

    #[test]
    fn enqueue_is_idempotent_on_id() {
        let s = Store::open("").unwrap();
        let seq1 = s.enqueue(&op("o1")).unwrap();
        let seq2 = s.enqueue(&op("o1")).unwrap(); // same id → no dup
        assert_eq!(seq1, seq2);
        assert_eq!(s.pending_count().unwrap(), 1);
    }

    #[test]
    fn outbox_fifo_and_ack_dead() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        let b = s.enqueue(&op("b")).unwrap();
        assert!(a < b);
        let pend = s.pending().unwrap();
        assert_eq!(
            pend.iter().map(|i| i.id.as_str()).collect::<Vec<_>>(),
            vec!["a", "b"]
        );

        s.mark_acked(a, Some("server-a")).unwrap();
        assert_eq!(s.pending_count().unwrap(), 1);
        assert_eq!(s.pending().unwrap()[0].id, "b");

        s.mark_dead(b, "4xx rejected").unwrap();
        assert_eq!(s.pending_count().unwrap(), 0);
    }

    #[test]
    fn list_active_requeue_and_discard() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        s.enqueue(&op("b")).unwrap();
        s.mark_acked(a, Some("srv")).unwrap(); // acked → hidden from list_active

        // b still pending → shown; a (acked) hidden.
        let active = s.list_active().unwrap();
        assert_eq!(
            active.iter().map(|i| i.id.as_str()).collect::<Vec<_>>(),
            vec!["b"]
        );

        // Kill b, then it shows as dead and is requeue/discard-able.
        let b_seq = active[0].seq;
        s.mark_dead(b_seq, "boom").unwrap();
        assert_eq!(s.list_active().unwrap()[0].status, "dead");
        assert!(!s.discard_dead("a").unwrap()); // a is acked, not dead → no-op
        assert_eq!(s.requeue_dead().unwrap(), 1);
        assert_eq!(s.list_active().unwrap()[0].status, "pending");
        assert_eq!(s.pending_count().unwrap(), 1);

        // Kill again, then discard it.
        s.mark_dead(b_seq, "boom2").unwrap();
        assert!(s.discard_dead("b").unwrap());
        assert!(s.list_active().unwrap().is_empty());
    }

    fn op_with(
        id: &str,
        op_type: &str,
        till_id: Option<&str>,
        depends_on_seq: Option<i64>,
    ) -> NewOutboxOp {
        NewOutboxOp {
            id: id.into(),
            op_type: op_type.into(),
            idempotency_key: id.into(),
            payload: "{}".into(),
            event_at: "2026-06-19T10:00:00Z".into(),
            depends_on_seq,
            till_id: till_id.map(|s| s.into()),
            ..Default::default()
        }
    }




    #[test]
    fn open_upgrades_an_old_schema_db_without_erroring() {
        // Reproduces the startup crash: an app updated in place has a DB whose
        // `outbox` predates the offline-orchestration columns. Opening it MUST
        // migrate (not fail on the backoff index that references a new column).
        let path = std::env::temp_dir().join("madar_old_schema_upgrade_test.sqlite");
        let _ = std::fs::remove_file(&path);
        {
            let conn = Connection::open(&path).unwrap();
            conn.execute_batch(
                "CREATE TABLE outbox (
                   seq INTEGER PRIMARY KEY AUTOINCREMENT,
                   id TEXT NOT NULL UNIQUE, op_type TEXT NOT NULL,
                   idempotency_key TEXT NOT NULL, payload TEXT NOT NULL,
                   event_at TEXT NOT NULL, enqueued_at TEXT NOT NULL,
                   status TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
                   last_error TEXT, server_id TEXT, depends_on_seq INTEGER);
                 INSERT INTO outbox(id,op_type,idempotency_key,payload,event_at,enqueued_at)
                   VALUES('old-1','create_order','old-1','{}','t','t');",
            )
            .unwrap();
        }
        // Opening with the CURRENT schema must NOT error (the bug threw here).
        let s = Store::open(path.to_str().unwrap()).expect("open must migrate, not crash");
        // The pre-existing row survives and the new columns defaulted sanely.
        let due = s.due_for_sync(now_ms() + 1, None).unwrap();
        assert_eq!(due.len(), 1);
        assert_eq!(due[0].id, "old-1");
        assert_eq!(due[0].next_attempt_at, 0);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn due_for_sync_respects_backoff_gate() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        s.enqueue(&op("b")).unwrap();
        // Back 'a' off into the future; only 'b' is due now.
        s.mark_retry(a, "transient", 9_000_000_000_000).unwrap();
        let due: Vec<_> = s
            .due_for_sync(1_000, None)
            .unwrap()
            .into_iter()
            .map(|i| i.id)
            .collect();
        assert_eq!(due, vec!["b"]);
        // Past 'a's gate, both are due, FIFO.
        let due2: Vec<_> = s
            .due_for_sync(9_999_999_999_999, None)
            .unwrap()
            .into_iter()
            .map(|i| i.id)
            .collect();
        assert_eq!(due2, vec!["a", "b"]);
        // mark_retry bumped attempts; mark_retry_no_count must not.
        assert_eq!(
            s.due_for_sync(9_999_999_999_999, None).unwrap()[0].attempts,
            1
        );
    }

    #[test]
    fn user_scoping_excludes_other_tellers() {
        let s = Store::open("").unwrap();
        s.enqueue(&NewOutboxOp {
            user_id: Some("alice".into()),
            ..op("a")
        })
        .unwrap();
        s.enqueue(&NewOutboxOp {
            user_id: Some("bob".into()),
            ..op("b")
        })
        .unwrap();
        s.enqueue(&op("legacy")).unwrap(); // NULL user → always included
        let due: Vec<_> = s
            .due_for_sync(now_ms() + 1, Some("alice"))
            .unwrap()
            .into_iter()
            .map(|i| i.id)
            .collect();
        assert_eq!(due, vec!["a", "legacy"]);
    }

    #[test]
    fn gating_and_dependency_lookups() {
        let s = Store::open("").unwrap();
        let open = s
            .enqueue(&op_with("shiftX", "open_till", Some("shiftX"), None))
            .unwrap();
        let ord = s
            .enqueue(&op_with("o1", "create_order", Some("shiftX"), Some(open)))
            .unwrap();
        s.enqueue(&op_with(
            "shiftX:close",
            "close_till",
            Some("shiftX"),
            Some(open),
        ))
        .unwrap();

        assert_eq!(s.status_of_seq(open).unwrap().as_deref(), Some("pending"));
        assert_eq!(s.live_seq_of("shiftX").unwrap(), Some(open));
        // The close must wait — an order for the shift is still live.
        assert!(s
            .has_live_till_writes("shiftX", s.live_seq_of("shiftX:close").unwrap().unwrap())
            .unwrap());
        // Order acked → no live shift writes left → close may proceed.
        s.mark_acked(ord, Some("srv-o1")).unwrap();
        assert!(!s
            .has_live_till_writes("shiftX", s.live_seq_of("shiftX:close").unwrap().unwrap())
            .unwrap());
        // Acked op is no longer a live dependency target.
        assert_eq!(s.live_seq_of("o1").unwrap(), None);
    }

    #[test]
    fn list_active_of_types_matches_list_active_then_filter() {
        let s = Store::open("").unwrap();
        for (id, ty) in [
            ("o1", "create_order"),
            ("m1", "cash_movement"),
            ("o2", "create_order"),
            ("v1", "void_order"),
        ] {
            let mut it = op(id);
            it.op_type = ty.into();
            s.enqueue(&it).unwrap();
        }
        // A discarded/acked row must stay out of both, exactly as before.
        let seq = s.due_for_sync(now_ms() + 1, None).unwrap()[0].seq;
        s.mark_acked(seq, Some("srv")).unwrap();

        for types in [
            vec!["create_order"],
            vec!["cash_movement"],
            vec!["create_order", "cash_movement"],
            vec!["void_order"],
        ] {
            let narrowed: Vec<String> = s
                .list_active_of_types(&types)
                .unwrap()
                .into_iter()
                .map(|i| i.id)
                .collect();
            let by_hand: Vec<String> = s
                .list_active()
                .unwrap()
                .into_iter()
                .filter(|i| types.contains(&i.op_type.as_str()))
                .map(|i| i.id)
                .collect();
            assert_eq!(narrowed, by_hand, "types {types:?}");
        }
        // Empty selection asks for nothing rather than degenerating to "everything".
        assert!(s.list_active_of_types(&[]).unwrap().is_empty());
    }

    /// `LIKE` would read the `_` in `cache:till_orders:` as a wildcard and let
    /// the sweep reach keys it was never scoped to; the prefix match must be literal.
    #[test]
    fn reclaim_free_pages_is_idempotent_and_records_its_one_time_migration() {
        let s = Store::open("").unwrap();
        s.kv_put("cache:order:1", "{}").unwrap();
        s.reclaim_free_pages().unwrap();
        // The one-time auto_vacuum migration is recorded, so it never re-VACUUMs.
        assert_eq!(
            s.kv_get("store:auto_vacuum_migrated").unwrap().as_deref(),
            Some("1")
        );
        // Safe to run again, and it leaves real data alone.
        s.reclaim_free_pages().unwrap();
        assert!(s.kv_get("cache:order:1").unwrap().is_some());
    }

    #[test]
    fn inflight_recovery_and_purge() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        s.mark_inflight(a).unwrap();
        assert!(s.due_for_sync(now_ms() + 1, None).unwrap().is_empty()); // inflight isn't due
        assert_eq!(s.recover_inflight().unwrap(), 1);
        assert_eq!(s.due_for_sync(now_ms() + 1, None).unwrap()[0].id, "a"); // back to pending
                                                                            // Acked + purge.
        let seq = s.due_for_sync(now_ms() + 1, None).unwrap()[0].seq;
        s.mark_acked(seq, Some("srv")).unwrap();
        assert_eq!(s.purge_acked_older_than(now_ms() - 1000).unwrap(), 0); // too fresh
        assert_eq!(s.purge_acked_older_than(now_ms() + 1000).unwrap(), 1); // now purged
    }

    // ════════════════════════════════════════════════════════════════════════
    // UPGRADE / MIGRATION PATH
    //
    // An app updated in place inherits a DB whose `outbox` predates the
    // offline-orchestration columns. `Store::open` MUST migrate it (adding the
    // missing columns + the backoff-gate index) rather than crash on the index
    // that references a column that doesn't exist yet. One test per missing
    // column, a fully-old-schema variant, and a re-open idempotency check.
    // ════════════════════════════════════════════════════════════════════════

    /// Unique on-disk path per test (no shared-fixture collisions when the suite
    /// runs in parallel). Pre-removed so a leftover from a prior run can't taint.
    fn temp_db(tag: &str) -> std::path::PathBuf {
        let path = std::env::temp_dir().join(format!("madar_store_mig_{tag}.sqlite"));
        let _ = std::fs::remove_file(&path);
        // WAL/SHM siblings can linger and confuse a re-create; clear them too.
        let _ = std::fs::remove_file(path.with_extension("sqlite-wal"));
        let _ = std::fs::remove_file(path.with_extension("sqlite-shm"));
        path
    }

    /// Build an `outbox` table whose column set is the modern shape MINUS the
    /// columns named in `omit`, then insert one pending row. The omitted columns
    /// are exactly the ones the migrations are responsible for adding back. The
    /// `outbox_due` index is intentionally NOT created (old DBs lacked it).
    fn build_old_outbox(path: &std::path::Path, omit: &[&str]) {
        // The full post-migration column set, in DDL order, with type+constraints.
        let all: &[(&str, &str)] = &[
            ("next_attempt_at", "INTEGER NOT NULL DEFAULT 0"),
            ("synced_at", "INTEGER"),
            ("user_id", "TEXT"),
            ("clock_offset_ms", "INTEGER"),
            ("shift_id", "TEXT"),
            ("till_id", "TEXT"),
            ("device_id", "TEXT"),
            ("entity_type", "TEXT"),
            ("entity_id", "TEXT"),
        ];
        // Columns that always existed pre-orchestration (never omitted).
        let mut cols = vec![
            "seq INTEGER PRIMARY KEY AUTOINCREMENT".to_string(),
            "id TEXT NOT NULL UNIQUE".to_string(),
            "op_type TEXT NOT NULL".to_string(),
            "idempotency_key TEXT NOT NULL".to_string(),
            "payload TEXT NOT NULL".to_string(),
            "event_at TEXT NOT NULL".to_string(),
            "enqueued_at TEXT NOT NULL".to_string(),
            "status TEXT NOT NULL DEFAULT 'pending'".to_string(),
            "attempts INTEGER NOT NULL DEFAULT 0".to_string(),
            "last_error TEXT".to_string(),
            "server_id TEXT".to_string(),
            "depends_on_seq INTEGER".to_string(),
        ];
        for (name, decl) in all {
            if !omit.contains(name) {
                cols.push(format!("{name} {decl}"));
            }
        }
        let ddl = format!("CREATE TABLE outbox (\n  {}\n);", cols.join(",\n  "));
        let conn = Connection::open(path).unwrap();
        conn.execute_batch(&ddl).unwrap();
        // The other tables exist in old DBs too; create them so a real open is faithful.
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT NOT NULL, updated_at TEXT NOT NULL);
             CREATE TABLE IF NOT EXISTS id_map (entity_type TEXT NOT NULL, client_temp_id TEXT NOT NULL, server_id TEXT NOT NULL, PRIMARY KEY(entity_type, client_temp_id));
             CREATE TABLE IF NOT EXISTS sync_cursors (stream TEXT PRIMARY KEY, last_server_seq INTEGER NOT NULL DEFAULT 0);
             CREATE INDEX IF NOT EXISTS outbox_status_seq ON outbox(status, seq);",
        )
        .unwrap();
        conn.execute(
            "INSERT INTO outbox(id,op_type,idempotency_key,payload,event_at,enqueued_at)
             VALUES('old-1','create_order','old-1','{}','2026-06-19T10:00:00Z','2026-06-19T10:00:00Z')",
            [],
        )
        .unwrap();
        // Drop the connection (and its lock) before the Store re-opens the file.
        drop(conn);
    }

    /// After a migrating open, the single pre-existing 'old-1' row must survive,
    /// be readable through the `COLS` mapper (proving every new column exists and
    /// maps), and have sane defaults: ready-now backoff, NULL orchestration fields.
    fn assert_old_row_survives_with_defaults(s: &Store) {
        // due_for_sync exercises next_attempt_at + user scoping over the migrated row.
        let due = s.due_for_sync(now_ms() + 10_000, None).unwrap();
        assert_eq!(due.len(), 1, "the migrated row must be due");
        let row = &due[0];
        assert_eq!(row.id, "old-1");
        assert_eq!(row.status, "pending");
        assert_eq!(
            row.next_attempt_at, 0,
            "missing next_attempt_at defaults to 0 (ready now)"
        );
        assert_eq!(row.user_id, None, "legacy row has NULL user_id");
        assert_eq!(row.clock_offset_ms, None);
        assert_eq!(row.till_id, None);
        // pending() round-trips the same row through the full mapper independently.
        assert_eq!(s.pending().unwrap().len(), 1);
        // The backoff-gate index must now exist (open creates it post-migration).
        let cnt: i64 = s
            .lock()
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='outbox_due'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(cnt, 1, "outbox_due index must exist after open");
    }

    #[test]
    fn migrate_missing_next_attempt_at() {
        let path = temp_db("missing_naa");
        build_old_outbox(&path, &["next_attempt_at"]);
        let s = Store::open(path.to_str().unwrap()).expect("open must add next_attempt_at + index");
        assert_old_row_survives_with_defaults(&s);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn migrate_missing_synced_at() {
        let path = temp_db("missing_synced");
        build_old_outbox(&path, &["synced_at"]);
        let s = Store::open(path.to_str().unwrap()).expect("open must add synced_at");
        assert_old_row_survives_with_defaults(&s);
        // purge keys off synced_at; with the column freshly added the row is NULL,
        // so it must never be purged (and the query must not error on the new col).
        s.enqueue(&op("fresh")).unwrap();
        assert_eq!(s.purge_acked_older_than(now_ms() + 10_000).unwrap(), 0);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn migrate_missing_user_id() {
        let path = temp_db("missing_user");
        build_old_outbox(&path, &["user_id"]);
        let s = Store::open(path.to_str().unwrap()).expect("open must add user_id");
        assert_old_row_survives_with_defaults(&s);
        // The NULL-user legacy row is included under any teller's scope.
        let scoped: Vec<_> = s
            .due_for_sync(now_ms() + 10_000, Some("alice"))
            .unwrap()
            .into_iter()
            .map(|i| i.id)
            .collect();
        assert_eq!(scoped, vec!["old-1"]);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn migrate_missing_clock_offset_ms() {
        let path = temp_db("missing_clock");
        build_old_outbox(&path, &["clock_offset_ms"]);
        let s = Store::open(path.to_str().unwrap()).expect("open must add clock_offset_ms");
        assert_old_row_survives_with_defaults(&s);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn migrate_missing_shift_id() {
        let path = temp_db("missing_shift");
        build_old_outbox(&path, &["shift_id", "till_id", "device_id", "entity_type", "entity_id"]);
        let s = Store::open(path.to_str().unwrap()).expect("open must add till_id");
        assert_old_row_survives_with_defaults(&s);
        // shift gating queries the freshly-added column without erroring.
        assert!(!s.has_live_till_writes("any-shift", -1).unwrap());
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn migrate_fully_old_schema_all_columns_missing() {
        // The realistic upgrade: NONE of the orchestration columns nor the
        // outbox_due index exist. All five ALTERs + the index must run.
        let path = temp_db("all_missing");
        build_old_outbox(
            &path,
            &[
                "next_attempt_at",
                "synced_at",
                "user_id",
                "clock_offset_ms",
                "shift_id",
                "till_id",
                "device_id",
                "entity_type",
                "entity_id",
            ],
        );
        let s = Store::open(path.to_str().unwrap()).expect("open must fully migrate, not crash");
        assert_old_row_survives_with_defaults(&s);
        // The migrated store is fully functional end-to-end: enqueue + drain + ack.
        let seq = s.due_for_sync(now_ms() + 10_000, None).unwrap()[0].seq;
        s.mark_inflight(seq).unwrap();
        s.mark_acked(seq, Some("srv")).unwrap();
        assert_eq!(s.pending_count().unwrap(), 0);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn reopen_twice_is_idempotent() {
        // Re-running migrations on an already-current DB must be a no-op (the
        // ALTERs raise "duplicate column" which open swallows). Open three times.
        let path = temp_db("reopen_idem");
        build_old_outbox(
            &path,
            &[
                "next_attempt_at",
                "synced_at",
                "user_id",
                "clock_offset_ms",
                "shift_id",
                "till_id",
                "device_id",
                "entity_type",
                "entity_id",
            ],
        );
        {
            let s = Store::open(path.to_str().unwrap()).expect("first open migrates");
            s.enqueue(&op("after-migrate")).unwrap();
            assert_eq!(s.pending_count().unwrap(), 2); // old-1 + after-migrate
        }
        {
            let s = Store::open(path.to_str().unwrap()).expect("second open is a no-op migrate");
            assert_eq!(s.pending_count().unwrap(), 2);
            // old-1 still carries its migrated defaults (don't assert total count
            // here — there are now 2 pending rows).
            let old = s
                .due_for_sync(now_ms() + 10_000, None)
                .unwrap()
                .into_iter()
                .find(|i| i.id == "old-1")
                .expect("old-1 still present after re-open");
            assert_eq!(old.status, "pending");
            assert_eq!(old.next_attempt_at, 0);
            assert_eq!(old.user_id, None);
            assert_eq!(old.clock_offset_ms, None);
            assert_eq!(old.till_id, None);
        }
        {
            // Third open on the now-modern DB must also succeed unchanged.
            let s = Store::open(path.to_str().unwrap()).expect("third open still fine");
            assert_eq!(s.pending_count().unwrap(), 2);
        }
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn open_on_fresh_db_runs_migrations_as_noops() {
        // A brand-new DB already has every column via SCHEMA; the ALTERs all hit
        // "duplicate column" and are swallowed, and open still succeeds.
        let path = temp_db("fresh_noop");
        {
            let s = Store::open(path.to_str().unwrap()).expect("fresh open");
            s.enqueue(&op("x")).unwrap();
        }
        let s = Store::open(path.to_str().unwrap()).expect("re-open fresh DB");
        assert_eq!(s.pending_count().unwrap(), 1);
        let _ = std::fs::remove_file(&path);
    }

    // ════════════════════════════════════════════════════════════════════════
    // KV / id_map / cursors — boundary + overwrite coverage
    // ════════════════════════════════════════════════════════════════════════

    #[test]
    fn kv_empty_value_and_missing_key() {
        let s = Store::open("").unwrap();
        // Missing key → None.
        assert_eq!(s.kv_get("nope").unwrap(), None);
        // Empty-string value is a real stored value, distinct from absent.
        s.kv_put("blank", "").unwrap();
        assert_eq!(s.kv_get("blank").unwrap().as_deref(), Some(""));
        // Overwrite back to non-empty.
        s.kv_put("blank", "x").unwrap();
        assert_eq!(s.kv_get("blank").unwrap().as_deref(), Some("x"));
    }

    #[test]
    fn id_map_overwrite_updates_server_id() {
        let s = Store::open("").unwrap();
        s.id_map_put("order", "local-1", "srv-1").unwrap();
        // Re-put same (entity, temp) updates the server id in place.
        s.id_map_put("order", "local-1", "srv-2").unwrap();
        assert_eq!(
            s.id_map_get("order", "local-1").unwrap().as_deref(),
            Some("srv-2")
        );
        // Same temp id under a DIFFERENT entity type is a distinct row.
        s.id_map_put("shift", "local-1", "srv-shift").unwrap();
        assert_eq!(
            s.id_map_get("shift", "local-1").unwrap().as_deref(),
            Some("srv-shift")
        );
        assert_eq!(
            s.id_map_get("order", "local-1").unwrap().as_deref(),
            Some("srv-2")
        );
    }

    #[test]
    fn cursor_defaults_zero_and_overwrites() {
        let s = Store::open("").unwrap();
        assert_eq!(s.cursor_get("unknown").unwrap(), 0); // default for absent stream
        s.cursor_set("orders", 10).unwrap();
        s.cursor_set("orders", 5).unwrap(); // set is an unconditional overwrite (not max)
        assert_eq!(s.cursor_get("orders").unwrap(), 5);
        // Streams are independent.
        s.cursor_set("shifts", 99).unwrap();
        assert_eq!(s.cursor_get("orders").unwrap(), 5);
        assert_eq!(s.cursor_get("shifts").unwrap(), 99);
    }

    // ════════════════════════════════════════════════════════════════════════
    // due_for_sync — backoff boundary + FIFO + status filtering
    // ════════════════════════════════════════════════════════════════════════

    #[test]
    fn due_for_sync_gate_is_inclusive_boundary() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        // Gate the row exactly at t=1000.
        s.mark_retry(a, "x", 1000).unwrap();
        // now < gate → not due.
        assert!(s.due_for_sync(999, None).unwrap().is_empty());
        // now == gate → due (predicate is `next_attempt_at <= now_ms`).
        assert_eq!(s.due_for_sync(1000, None).unwrap().len(), 1);
        // now > gate → due.
        assert_eq!(s.due_for_sync(1001, None).unwrap().len(), 1);
    }

    #[test]
    fn due_for_sync_excludes_non_pending_statuses() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        let b = s.enqueue(&op("b")).unwrap();
        let c = s.enqueue(&op("c")).unwrap();
        s.mark_inflight(a).unwrap(); // inflight: excluded
        s.mark_acked(b, Some("srv")).unwrap(); // acked: excluded
                                               // dead c: excluded too.
        s.mark_dead(c, "boom").unwrap();
        assert!(s.due_for_sync(now_ms() + 10_000, None).unwrap().is_empty());
    }

    #[test]
    fn due_for_sync_is_fifo_by_seq() {
        let s = Store::open("").unwrap();
        // Enqueue out of "alphabetical" order to prove ordering is by seq, not id.
        s.enqueue(&op("zeta")).unwrap();
        s.enqueue(&op("alpha")).unwrap();
        s.enqueue(&op("mid")).unwrap();
        let ids: Vec<_> = s
            .due_for_sync(now_ms() + 10_000, None)
            .unwrap()
            .into_iter()
            .map(|i| i.id)
            .collect();
        assert_eq!(ids, vec!["zeta", "alpha", "mid"]);
    }

    #[test]
    fn due_for_sync_empty_queue_returns_empty() {
        let s = Store::open("").unwrap();
        assert!(s.due_for_sync(now_ms(), None).unwrap().is_empty());
        assert!(s.due_for_sync(now_ms(), Some("alice")).unwrap().is_empty());
    }

    #[test]
    fn clear_network_backoff_ungates_only_no_count_pending() {
        let s = Store::open("").unwrap();
        let net = s.enqueue(&op("net")).unwrap();
        let srv = s.enqueue(&op("srv")).unwrap();
        s.enqueue(&op("fresh")).unwrap(); // never attempted; gate already 0
                                          // A connectivity blip reschedules WITHOUT counting (attempts stays 0).
        s.mark_retry_no_count(net, now_ms() + 60_000).unwrap();
        // A server error backs off WITH a count bump (attempts=1).
        s.mark_retry(srv, "5xx", now_ms() + 60_000).unwrap();
        // Before: only "fresh" is due (net + srv gated into the future).
        let before: Vec<_> = s
            .due_for_sync(now_ms(), None)
            .unwrap()
            .into_iter()
            .map(|i| i.id)
            .collect();
        assert_eq!(before, vec!["fresh"]);
        // The reconnect path un-gates ONLY the no-count item.
        assert_eq!(s.clear_network_backoff().unwrap(), 1);
        let after: Vec<_> = s
            .due_for_sync(now_ms(), None)
            .unwrap()
            .into_iter()
            .map(|i| i.id)
            .collect();
        assert!(
            after.contains(&"net".to_string()),
            "the connectivity-gated item is now due"
        );
        assert!(
            !after.contains(&"srv".to_string()),
            "the counted server backoff stays gated"
        );
        assert!(after.contains(&"fresh".to_string()));
    }

    #[test]
    fn due_for_sync_scoped_excludes_pure_other_teller() {
        let s = Store::open("").unwrap();
        s.enqueue(&NewOutboxOp {
            user_id: Some("bob".into()),
            ..op("b")
        })
        .unwrap();
        // Alice's scope sees nothing (bob's op + no legacy NULL rows).
        assert!(s
            .due_for_sync(now_ms() + 10_000, Some("alice"))
            .unwrap()
            .is_empty());
        // Bob's scope sees his own op.
        let ids: Vec<_> = s
            .due_for_sync(now_ms() + 10_000, Some("bob"))
            .unwrap()
            .into_iter()
            .map(|i| i.id)
            .collect();
        assert_eq!(ids, vec!["b"]);
    }

    // ════════════════════════════════════════════════════════════════════════
    // status_of_seq / live_seq_of
    // ════════════════════════════════════════════════════════════════════════

    #[test]
    fn status_of_seq_tracks_transitions_and_unknown() {
        let s = Store::open("").unwrap();
        assert_eq!(s.status_of_seq(99999).unwrap(), None); // no such seq
        let a = s.enqueue(&op("a")).unwrap();
        assert_eq!(s.status_of_seq(a).unwrap().as_deref(), Some("pending"));
        s.mark_inflight(a).unwrap();
        assert_eq!(s.status_of_seq(a).unwrap().as_deref(), Some("inflight"));
        s.mark_dead(a, "boom").unwrap();
        assert_eq!(s.status_of_seq(a).unwrap().as_deref(), Some("dead"));
        s.requeue_dead().unwrap();
        assert_eq!(s.status_of_seq(a).unwrap().as_deref(), Some("pending"));
        s.mark_acked(a, None).unwrap();
        assert_eq!(s.status_of_seq(a).unwrap().as_deref(), Some("acked"));
    }

    #[test]
    fn live_seq_of_covers_live_states_and_acked_and_missing() {
        let s = Store::open("").unwrap();
        assert_eq!(s.live_seq_of("ghost").unwrap(), None); // never enqueued
        let a = s.enqueue(&op("a")).unwrap();
        assert_eq!(s.live_seq_of("a").unwrap(), Some(a)); // pending counts as live
        s.mark_inflight(a).unwrap();
        assert_eq!(s.live_seq_of("a").unwrap(), Some(a)); // inflight counts
        s.mark_dead(a, "x").unwrap();
        assert_eq!(s.live_seq_of("a").unwrap(), Some(a)); // dead counts (still a real row)
        s.mark_acked(a, Some("srv")).unwrap();
        assert_eq!(s.live_seq_of("a").unwrap(), None); // acked is NOT a live dep target
    }

    // ════════════════════════════════════════════════════════════════════════
    // has_live_till_writes — close-last gating
    // ════════════════════════════════════════════════════════════════════════

    #[test]
    fn has_live_shift_writes_excludes_self_seq() {
        let s = Store::open("").unwrap();
        // Only the close itself is live for the shift.
        let close = s
            .enqueue(&op_with("close", "close_till", Some("sh1"), None))
            .unwrap();
        // Excluding the close's own seq → no OTHER live writes → false.
        assert!(!s.has_live_till_writes("sh1", close).unwrap());
        // Without excluding it... close_till isn't a counted op_type anyway → still false.
        assert!(!s.has_live_till_writes("sh1", -1).unwrap());
    }

    #[test]
    fn has_live_shift_writes_counts_only_relevant_op_types() {
        let s = Store::open("").unwrap();
        // A non-write op for the shift (e.g. open_till) must NOT gate the close.
        s.enqueue(&op_with("open", "open_till", Some("sh1"), None))
            .unwrap();
        assert!(!s.has_live_till_writes("sh1", -1).unwrap());
        // A real write (create_order) DOES gate it.
        s.enqueue(&op_with("o1", "create_order", Some("sh1"), None))
            .unwrap();
        assert!(s.has_live_till_writes("sh1", -1).unwrap());
        // void_order and cash_movement gate too.
        let s2 = Store::open("").unwrap();
        s2.enqueue(&op_with("v", "void_order", Some("sh2"), None))
            .unwrap();
        assert!(s2.has_live_till_writes("sh2", -1).unwrap());
        let s3 = Store::open("").unwrap();
        s3.enqueue(&op_with("c", "cash_movement", Some("sh3"), None))
            .unwrap();
        assert!(s3.has_live_till_writes("sh3", -1).unwrap());
    }

    #[test]
    fn has_live_shift_writes_is_shift_scoped() {
        let s = Store::open("").unwrap();
        // A live order belongs to a DIFFERENT shift; sh1's close is unblocked.
        s.enqueue(&op_with("o-other", "create_order", Some("sh2"), None))
            .unwrap();
        assert!(!s.has_live_till_writes("sh1", -1).unwrap());
        assert!(s.has_live_till_writes("sh2", -1).unwrap());
    }


    // ════════════════════════════════════════════════════════════════════════
    // retry semantics — attempts bump vs no-count
    // ════════════════════════════════════════════════════════════════════════

    #[test]
    fn mark_retry_bumps_attempts_and_sets_gate_and_error() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        s.mark_inflight(a).unwrap();
        s.mark_retry(a, "503 transient", 5000).unwrap();
        let row = &s.due_for_sync(5000, None).unwrap()[0]; // back to pending, gate hit at 5000
        assert_eq!(row.status, "pending");
        assert_eq!(row.attempts, 1);
        assert_eq!(row.next_attempt_at, 5000);
        assert_eq!(row.last_error.as_deref(), Some("503 transient"));
        // A second counted retry bumps again.
        s.mark_retry(a, "503 again", 6000).unwrap();
        assert_eq!(s.due_for_sync(6000, None).unwrap()[0].attempts, 2);
    }

    #[test]
    fn mark_retry_no_count_reschedules_without_bumping_attempts() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        // First, a counted retry to push attempts to 1 and set an error.
        s.mark_retry(a, "real failure", 1000).unwrap();
        assert_eq!(s.due_for_sync(1000, None).unwrap()[0].attempts, 1);
        // A no-count reschedule moves the gate but leaves attempts AND last_error.
        s.mark_inflight(a).unwrap();
        s.mark_retry_no_count(a, 8000).unwrap();
        let row = &s.due_for_sync(8000, None).unwrap()[0];
        assert_eq!(row.status, "pending");
        assert_eq!(row.attempts, 1, "no-count must not bump attempts");
        assert_eq!(row.next_attempt_at, 8000);
        assert_eq!(
            row.last_error.as_deref(),
            Some("real failure"),
            "error preserved"
        );
        // It is gated until 8000.
        assert!(s.due_for_sync(7999, None).unwrap().is_empty());
    }

    // ════════════════════════════════════════════════════════════════════════
    // ack / dead / purge / requeue / discard — extra edges
    // ════════════════════════════════════════════════════════════════════════

    #[test]
    fn mark_acked_with_none_server_id_still_sets_synced_at() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        s.mark_acked(a, None).unwrap();
        assert_eq!(s.status_of_seq(a).unwrap().as_deref(), Some("acked"));
        // synced_at was set (now_ms), so a future-cutoff purge collects it.
        assert_eq!(s.purge_acked_older_than(now_ms() + 60_000).unwrap(), 1);
    }

    #[test]
    fn purge_only_touches_acked_rows() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        s.enqueue(&op("b")).unwrap(); // stays pending
        s.mark_acked(a, Some("srv")).unwrap();
        // Generous cutoff: only the acked 'a' is removed; pending 'b' survives.
        assert_eq!(s.purge_acked_older_than(now_ms() + 60_000).unwrap(), 1);
        assert_eq!(s.pending_count().unwrap(), 1);
        assert_eq!(s.pending().unwrap()[0].id, "b");
    }

    #[test]
    fn requeue_dead_resets_attempts_error_and_gate() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        let b = s.enqueue(&op("b")).unwrap();
        // Drive 'a' to dead with a bumped attempt + future gate + error.
        s.mark_retry(a, "boom", 9_000_000_000_000).unwrap();
        s.mark_dead(a, "exhausted").unwrap();
        s.mark_dead(b, "rejected").unwrap();
        assert_eq!(s.dead_count().unwrap(), 2);
        // Requeue clears status→pending, attempts→0, error→NULL, gate→0.
        assert_eq!(s.requeue_dead().unwrap(), 2);
        assert_eq!(s.dead_count().unwrap(), 0);
        let row = s
            .due_for_sync(0, None)
            .unwrap()
            .into_iter()
            .find(|i| i.id == "a")
            .unwrap();
        assert_eq!(row.attempts, 0);
        assert_eq!(row.next_attempt_at, 0);
        assert_eq!(row.last_error, None);
    }

    #[test]
    fn requeue_dead_on_empty_returns_zero() {
        let s = Store::open("").unwrap();
        assert_eq!(s.requeue_dead().unwrap(), 0);
        s.enqueue(&op("a")).unwrap(); // pending, not dead
        assert_eq!(s.requeue_dead().unwrap(), 0);
    }

    #[test]
    fn discard_dead_only_removes_dead_rows() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        // Pending → cannot discard.
        assert!(!s.discard_dead("a").unwrap());
        s.mark_inflight(a).unwrap();
        assert!(!s.discard_dead("a").unwrap()); // inflight → cannot discard
        s.mark_dead(a, "x").unwrap();
        assert!(s.discard_dead("a").unwrap()); // dead → removed
        assert!(!s.discard_dead("a").unwrap()); // gone → no-op
                                                // Unknown id → no-op.
        assert!(!s.discard_dead("ghost").unwrap());
    }

    #[test]
    fn recover_inflight_only_touches_inflight() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        let b = s.enqueue(&op("b")).unwrap();
        s.mark_inflight(a).unwrap(); // a inflight, b pending
        assert_eq!(s.recover_inflight().unwrap(), 1);
        assert_eq!(s.status_of_seq(a).unwrap().as_deref(), Some("pending"));
        assert_eq!(s.status_of_seq(b).unwrap().as_deref(), Some("pending"));
        // Nothing inflight now → no-op.
        assert_eq!(s.recover_inflight().unwrap(), 0);
    }

    #[test]
    fn wipe_outbox_clears_everything() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        s.enqueue(&op("b")).unwrap();
        s.mark_acked(a, Some("srv")).unwrap(); // mix of acked + pending
        s.wipe_outbox().unwrap();
        assert_eq!(s.pending_count().unwrap(), 0);
        assert_eq!(s.dead_count().unwrap(), 0);
        assert!(s.list_active().unwrap().is_empty());
        // The id is free again (the unique row is gone).
        let re = s.enqueue(&op("a")).unwrap();
        assert_eq!(s.status_of_seq(re).unwrap().as_deref(), Some("pending"));
    }

    #[test]
    fn enqueue_preserves_all_orchestration_fields() {
        let s = Store::open("").unwrap();
        let full = NewOutboxOp {
            id: "f1".into(),
            op_type: "create_order".into(),
            idempotency_key: "idem-f1".into(),
            payload: r#"{"total":1}"#.into(),
            event_at: "2026-06-19T10:00:00Z".into(),
            depends_on_seq: Some(7),
            user_id: Some("alice".into()),
            clock_offset_ms: Some(-250),
            till_id: Some("shift-7".into()),
            device_id: Some("dev-7".into()),
            entity_type: Some("order".into()),
            entity_id: Some("f1".into()),
        };
        s.enqueue(&full).unwrap();
        let row = s
            .pending()
            .unwrap()
            .into_iter()
            .find(|i| i.id == "f1")
            .unwrap();
        assert_eq!(row.op_type, "create_order");
        assert_eq!(row.idempotency_key, "idem-f1");
        assert_eq!(row.payload, r#"{"total":1}"#);
        assert_eq!(row.event_at, "2026-06-19T10:00:00Z");
        assert_eq!(row.depends_on_seq, Some(7));
        assert_eq!(row.user_id.as_deref(), Some("alice"));
        assert_eq!(row.clock_offset_ms, Some(-250));
        assert_eq!(row.till_id.as_deref(), Some("shift-7"));
        assert_eq!(row.attempts, 0);
        assert_eq!(row.next_attempt_at, 0);
        assert_eq!(row.last_error, None);
        assert_eq!(row.server_id, None);
    }

    #[test]
    fn enqueue_idempotent_keeps_original_fields() {
        let s = Store::open("").unwrap();
        let seq1 = s
            .enqueue(&NewOutboxOp {
                user_id: Some("alice".into()),
                ..op("dup")
            })
            .unwrap();
        // Re-enqueue same id with DIFFERENT fields → ignored, original kept.
        let seq2 = s
            .enqueue(&NewOutboxOp {
                user_id: Some("bob".into()),
                ..op("dup")
            })
            .unwrap();
        assert_eq!(seq1, seq2);
        let row = s
            .pending()
            .unwrap()
            .into_iter()
            .find(|i| i.id == "dup")
            .unwrap();
        assert_eq!(
            row.user_id.as_deref(),
            Some("alice"),
            "first enqueue wins (DO NOTHING)"
        );
        assert_eq!(s.pending_count().unwrap(), 1);
    }

    /// The durable outbox must survive a process restart — a queued order rung up
    /// offline cannot evaporate when the app is killed and reopened.
    #[test]
    fn outbox_survives_reopen() {
        let path = std::env::temp_dir().join(format!("madar_outbox_{}.db", std::process::id()));
        let p = path.to_str().unwrap();
        for ext in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{p}{ext}"));
        }
        {
            let s = Store::open(p).unwrap();
            s.enqueue(&op("a")).unwrap();
            s.enqueue(&op("b")).unwrap();
            assert_eq!(s.pending_count().unwrap(), 2);
        } // dropped → connection closed
        let s2 = Store::open(p).unwrap();
        assert_eq!(
            s2.pending_count().unwrap(),
            2,
            "queue must persist across reopen"
        );
        assert_eq!(
            s2.pending()
                .unwrap()
                .iter()
                .map(|i| i.id.clone())
                .collect::<Vec<_>>(),
            vec!["a", "b"],
            "FIFO order must persist too"
        );
        drop(s2);
        for ext in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{p}{ext}"));
        }
    }

    /// `due_for_sync` only surfaces ops past their backoff gate, scoped to the
    /// teller whose token will send them (a 503 backoff must hide an op until its
    /// gate; a different teller's ops must not ride the current holder's drain).
    #[test]
    fn due_for_sync_respects_backoff_and_user() {
        let s = Store::open("").unwrap();
        let mut a = op("a");
        a.user_id = Some("alice".into());
        let mut b = op("b");
        b.user_id = Some("bob".into());
        let sa = s.enqueue(&a).unwrap();
        s.enqueue(&b).unwrap();

        // Both ready now (next_attempt_at defaults to 0); alice-scoped → only a.
        let due_alice: Vec<String> = s
            .due_for_sync(1, Some("alice"))
            .unwrap()
            .iter()
            .map(|i| i.id.clone())
            .collect();
        assert_eq!(due_alice, vec!["a"]);

        // Back a off into the future → not due before its gate, due after.
        s.mark_retry(sa, "503", 10_000).unwrap();
        assert!(
            s.due_for_sync(5_000, Some("alice")).unwrap().is_empty(),
            "backed-off op leaks"
        );
        assert_eq!(s.due_for_sync(20_000, Some("alice")).unwrap().len(), 1);
        // An unscoped drain sees both tellers' due ops.
        assert_eq!(s.due_for_sync(20_000, None).unwrap().len(), 2);
    }

    /// A crash mid-send leaves ops `inflight`; recovery must return them to
    /// `pending` so the next drain re-sends (the server dedups on idempotency_key).
    #[test]
    fn recover_inflight_returns_ops_to_pending() {
        let s = Store::open("").unwrap();
        let a = s.enqueue(&op("a")).unwrap();
        s.mark_inflight(a).unwrap();
        assert_eq!(
            s.pending_count().unwrap(),
            1,
            "inflight still counts as un-synced work"
        );
        assert_eq!(s.recover_inflight().unwrap(), 1);
        assert_eq!(s.pending().unwrap()[0].status, "pending");
    }


    // ── Model-based stateful testing of the durable outbox ──────────────────────
    // The offline sync engine's correctness lives here: as queued work moves
    // pending→inflight→{acked,dead}→pending, nothing may be lost, double-counted,
    // or reordered. We drive RANDOM transition sequences against the real store and
    // an independent reference model, asserting counts, FIFO and conservation after
    // EVERY step — coverage no fixed example sequence can match.
    mod outbox_model {
        use super::*;
        use proptest::prelude::*;
        use std::collections::BTreeMap;

        #[derive(Clone, Copy, Debug, PartialEq, Eq)]
        enum St {
            Pending,
            Inflight,
            Dead,
        }

        #[derive(Clone, Debug)]
        enum Cmd {
            Enqueue,
            Inflight(usize),
            Ack(usize),
            Dead(usize),
            Retry(usize),
            RequeueDead,
            DiscardDead(usize),
            RecoverInflight,
        }

        fn arb_cmd() -> impl Strategy<Value = Cmd> {
            prop_oneof![
                3 => Just(Cmd::Enqueue),
                2 => (0usize..100).prop_map(Cmd::Ack),
                1 => (0usize..100).prop_map(Cmd::Inflight),
                1 => (0usize..100).prop_map(Cmd::Dead),
                1 => (0usize..100).prop_map(Cmd::Retry),
                1 => Just(Cmd::RequeueDead),
                1 => (0usize..100).prop_map(Cmd::DiscardDead),
                1 => Just(Cmd::RecoverInflight),
            ]
        }

        // The k-th seq (mod count) whose state is in `want`.
        fn pick(model: &BTreeMap<i64, (String, St)>, k: usize, want: &[St]) -> Option<i64> {
            let v: Vec<i64> = model
                .iter()
                .filter(|(_, (_, st))| want.contains(st))
                .map(|(&seq, _)| seq)
                .collect();
            (!v.is_empty()).then(|| v[k % v.len()])
        }

        proptest! {
            #[test]
            fn outbox_invariants(cmds in prop::collection::vec(arb_cmd(), 0..80)) {
                let s = Store::open("").unwrap();
                let mut model: BTreeMap<i64, (String, St)> = BTreeMap::new();
                let mut n = 0u32;

                for cmd in cmds {
                    match cmd {
                        Cmd::Enqueue => {
                            let id = format!("op{n}");
                            n += 1;
                            let seq = s.enqueue(&op(&id)).unwrap();
                            model.insert(seq, (id, St::Pending));
                        }
                        Cmd::Inflight(k) => {
                            if let Some(seq) = pick(&model, k, &[St::Pending]) {
                                s.mark_inflight(seq).unwrap();
                                model.get_mut(&seq).unwrap().1 = St::Inflight;
                            }
                        }
                        Cmd::Ack(k) => {
                            if let Some(seq) = pick(&model, k, &[St::Pending, St::Inflight]) {
                                s.mark_acked(seq, Some("srv")).unwrap();
                                model.remove(&seq);
                            }
                        }
                        Cmd::Dead(k) => {
                            if let Some(seq) = pick(&model, k, &[St::Pending, St::Inflight]) {
                                s.mark_dead(seq, "err").unwrap();
                                model.get_mut(&seq).unwrap().1 = St::Dead;
                            }
                        }
                        Cmd::Retry(k) => {
                            if let Some(seq) = pick(&model, k, &[St::Pending, St::Inflight]) {
                                s.mark_retry(seq, "err", 0).unwrap();
                                model.get_mut(&seq).unwrap().1 = St::Pending;
                            }
                        }
                        Cmd::RequeueDead => {
                            s.requeue_dead().unwrap();
                            for (_, st) in model.values_mut() {
                                if *st == St::Dead {
                                    *st = St::Pending;
                                }
                            }
                        }
                        Cmd::DiscardDead(k) => {
                            if let Some(seq) = pick(&model, k, &[St::Dead]) {
                                let id = model[&seq].0.clone();
                                prop_assert!(s.discard_dead(&id).unwrap(), "dead op should discard");
                                model.remove(&seq);
                            }
                        }
                        Cmd::RecoverInflight => {
                            s.recover_inflight().unwrap();
                            for (_, st) in model.values_mut() {
                                if *st == St::Inflight {
                                    *st = St::Pending;
                                }
                            }
                        }
                    }

                    // ── invariants after EVERY command ──
                    let exp_pending = model
                        .values()
                        .filter(|(_, st)| *st == St::Pending || *st == St::Inflight)
                        .count();
                    let exp_dead = model.values().filter(|(_, st)| *st == St::Dead).count();
                    prop_assert_eq!(s.pending_count().unwrap() as usize, exp_pending, "pending count");
                    prop_assert_eq!(s.dead_count().unwrap() as usize, exp_dead, "dead count");
                    prop_assert_eq!(s.list_active().unwrap().len(), exp_pending + exp_dead, "active count");

                    // FIFO: pending() seqs strictly ascending.
                    let pseqs: Vec<i64> = s.pending().unwrap().iter().map(|i| i.seq).collect();
                    prop_assert!(pseqs.windows(2).all(|w| w[0] < w[1]), "pending not FIFO");

                    // Conservation: the store's active seq-set equals the model's.
                    let mut store_seqs: Vec<i64> =
                        s.list_active().unwrap().iter().map(|i| i.seq).collect();
                    store_seqs.sort_unstable();
                    let mut model_seqs: Vec<i64> = model.keys().copied().collect();
                    model_seqs.sort_unstable();
                    prop_assert_eq!(store_seqs, model_seqs, "store/model seq-sets diverged");
                }
            }
        }
    }
}
