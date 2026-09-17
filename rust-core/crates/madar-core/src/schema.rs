//! Versioned local-schema steps (`PRAGMA user_version`), OFFLINE_B_DESIGN §1.3.
//!
//! The ignore-error `ALTER TABLE ADD COLUMN` list in `store.rs` stays for the
//! stores that predate this file; it is fine for adding a column and nothing
//! else. Tables, backfills and data moves go here: each step runs in ONE
//! transaction together with the `user_version` bump, so a crash leaves the
//! store at exactly the previous version and the step simply runs again.
//!
//! A store written by a NEWER build (`user_version` above what this build knows)
//! is not migrated backwards and not written by the sync applier: the core
//! still opens (the outbox is the one irreplaceable thing and its shape is
//! stable), flags `future_schema`, and reports it.

use rusqlite::{Connection, Transaction};

use crate::error::CoreResult;

type Step = fn(&Transaction<'_>) -> CoreResult<()>;

/// The steps, in order. Step N brings the store from `user_version = N-1` to N.
/// Append only: a shipped step is never edited.
const STEPS: &[Step] = &[step1_sync_streams, step2_ledger, step3_order_details, step4_backfill_ledger, step5_drop_legacy_read_caches, step6_lan_authz_flags, step7_spot_checks];

/// The schema version this build writes.
pub(crate) fn latest() -> i64 {
    STEPS.len() as i64
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Migrated {
    pub from: i64,
    pub to: i64,
    /// The file was written by a newer build than this one.
    pub future_schema: bool,
}

pub(crate) fn user_version(conn: &Connection) -> CoreResult<i64> {
    Ok(conn.pragma_query_value(None, "user_version", |r| r.get(0))?)
}

/// Run every step the store has not seen yet, each in its own transaction.
pub(crate) fn migrate(conn: &mut Connection) -> CoreResult<Migrated> {
    migrate_with(conn, STEPS, &mut |_| Ok(()))
}

/// `after_step` runs inside each step's transaction after the DDL (tests use it
/// to kill a migration half way).
pub(crate) fn migrate_with(
    conn: &mut Connection,
    steps: &[Step],
    after_step: &mut dyn FnMut(i64) -> CoreResult<()>,
) -> CoreResult<Migrated> {
    let from = user_version(conn)?;
    let known = steps.len() as i64;
    if from > known {
        return Ok(Migrated { from, to: from, future_schema: true });
    }
    for (i, step) in steps.iter().enumerate().skip(from as usize) {
        let version = i as i64 + 1;
        let tx = conn.transaction()?;
        step(&tx)?;
        after_step(version)?;
        // `PRAGMA user_version` is transactional in SQLite: it rolls back with the step.
        tx.pragma_update(None, "user_version", version)?;
        tx.commit()?;
    }
    Ok(Migrated { from, to: known.max(from), future_schema: false })
}

/// Sync health per stream (the cursor itself stays in kv `sync:next:<branch>`,
/// written inside the page transaction as before — see the decision log).
fn step1_sync_streams(tx: &Transaction<'_>) -> CoreResult<()> {
    tx.execute_batch(
        "CREATE TABLE IF NOT EXISTS sync_streams (
           stream        TEXT PRIMARY KEY,          -- 'branch:<id>'
           scope_key     TEXT NOT NULL,             -- the branch id
           state         TEXT NOT NULL DEFAULT 'bootstrapping', -- bootstrapping|live|stale|error
           last_ok_at    INTEGER,                   -- epoch ms of the last completed pull
           last_attempt_at INTEGER,
           last_err      TEXT,
           last_err_kind TEXT,                      -- offline|auth|server|decode|forbidden
           window_from   TEXT                       -- ledger window of the last full snapshot
         );
         -- A row a LAN peer provided (OFFLINE_B_DESIGN §LAN catch-up): stored with
         -- seq 0 (every cloud write wins) and the seq the peer claimed here.
         ALTER TABLE sync_rows ADD COLUMN peer_seq INTEGER;
         -- Deletes the feed applied, by seq, so a peer that still holds the row
         -- can be told (bounded by age).
         CREATE TABLE IF NOT EXISTS sync_tombstones (
           branch_id   TEXT NOT NULL,
           type        TEXT NOT NULL,
           id          TEXT NOT NULL,
           seq         INTEGER NOT NULL,
           peer        INTEGER NOT NULL DEFAULT 0,
           recorded_at INTEGER NOT NULL,
           PRIMARY KEY (branch_id, type, id)
         );
         -- Every LAN event this device published or accepted, by identity (the op
         -- key of a write, else the message id): persistent dedup across restarts
         -- and what catch-up re-offers to a peer that lacks it.
         CREATE TABLE IF NOT EXISTS lan_log (
           key          TEXT PRIMARY KEY,
           branch_id    TEXT NOT NULL,
           topic        TEXT NOT NULL,
           event_type   TEXT NOT NULL,
           data         TEXT NOT NULL,
           replay_op    TEXT,
           origin       TEXT NOT NULL,
           sent_at_ms   INTEGER NOT NULL,
           received_at_ms INTEGER NOT NULL,
           hash         INTEGER NOT NULL,            -- 63-bit digest of the key (gossip bucket)
           ver          INTEGER NOT NULL DEFAULT 0   -- a line toggle's tap time (latest wins); 0 otherwise
         );
         CREATE INDEX IF NOT EXISTS lan_log_branch ON lan_log(branch_id, received_at_ms);",
    )?;
    Ok(())
}

/// The money ledger as rows (§2 P1): tills, orders + payment legs, cash
/// movements, refunds. `raw` keeps the wire JSON the projections read; the typed
/// columns exist for filters, joins and the till computation.
///
/// Keys: a row is keyed by the CLIENT-minted id when one exists (order
/// `idempotency_key`, movement/refund `client_ref`, the till id itself), else the
/// server id — so a sale is ONE row from the moment it is rung to long after it
/// has synced, and a lost response can never add it twice.
fn step2_ledger(tx: &Transaction<'_>) -> CoreResult<()> {
    tx.execute_batch(
        "CREATE TABLE IF NOT EXISTS ledger_tills (
           id            TEXT PRIMARY KEY,
           branch_id     TEXT NOT NULL,
           teller_id     TEXT NOT NULL,
           status        TEXT NOT NULL,
           opening_cash  INTEGER NOT NULL DEFAULT 0,
           closing_cash_system INTEGER,
           opened_at     TEXT NOT NULL,
           closed_at     TEXT,
           raw           TEXT NOT NULL,             -- TillRecord JSON
           srv_raw       TEXT,                      -- last server version while a local op holds the row
           srv_seq       INTEGER NOT NULL DEFAULT 0,
           origin        TEXT NOT NULL,             -- server|local
           acked         INTEGER NOT NULL DEFAULT 0, -- an op for it acked, the feed has not confirmed it yet
           ack_seq       INTEGER,                   -- the replay answer's X-Madar-Sync-Seq: the feed shows the op by here
           peer_seq      INTEGER,                   -- origin 'peer': the feed seq a LAN peer claimed (unconfirmed)
           complete      INTEGER NOT NULL DEFAULT 0, -- every ledger row of this till is local
           local_updated_at INTEGER NOT NULL
         );
         CREATE INDEX IF NOT EXISTS ledger_tills_branch ON ledger_tills(branch_id, opened_at DESC);

         CREATE TABLE IF NOT EXISTS ledger_orders (
           okey          TEXT PRIMARY KEY,
           server_id     TEXT UNIQUE,
           order_ref     TEXT,
           branch_id     TEXT NOT NULL,
           till_id       TEXT NOT NULL,
           status        TEXT NOT NULL,
           payment_method TEXT NOT NULL,
           total_amount  INTEGER NOT NULL DEFAULT 0,
           tip_amount    INTEGER NOT NULL DEFAULT 0,
           tip_is_cash   INTEGER,                   -- NULL: COALESCE(tip method,'cash') like the server
           tip_payment_method TEXT,
           created_at    TEXT NOT NULL,
           order_number  INTEGER,                   -- the Z report's device range (a JSON scan was most of a big report)
           device_code   TEXT,
           raw           TEXT NOT NULL,             -- projection / command JSON
           srv_raw       TEXT,
           srv_seq       INTEGER NOT NULL DEFAULT 0,
           origin        TEXT NOT NULL,
           acked         INTEGER NOT NULL DEFAULT 0, -- a local op for it acked, the feed has not confirmed it yet
           ack_seq       INTEGER,
           peer_seq      INTEGER,
           local_updated_at INTEGER NOT NULL
         );
         CREATE INDEX IF NOT EXISTS ledger_orders_till ON ledger_orders(till_id, created_at DESC);
         CREATE INDEX IF NOT EXISTS ledger_orders_branch ON ledger_orders(branch_id, created_at DESC);
         CREATE INDEX IF NOT EXISTS ledger_orders_ref ON ledger_orders(order_ref);

         CREATE TABLE IF NOT EXISTS ledger_payments (
           okey          TEXT NOT NULL REFERENCES ledger_orders(okey) ON DELETE CASCADE ON UPDATE CASCADE,
           idx           INTEGER NOT NULL,
           method        TEXT NOT NULL,
           amount        INTEGER NOT NULL,
           is_cash       INTEGER,                   -- NULL: method = 'cash' (server COALESCE)
           PRIMARY KEY (okey, idx)
         );

         CREATE TABLE IF NOT EXISTS ledger_cash (
           ckey          TEXT PRIMARY KEY,
           server_id     TEXT UNIQUE,
           till_id       TEXT NOT NULL,
           amount        INTEGER NOT NULL,
           kind          TEXT NOT NULL,
           corrects_id   TEXT,
           created_at    TEXT NOT NULL,
           raw           TEXT NOT NULL,
           srv_raw       TEXT,
           srv_seq       INTEGER NOT NULL DEFAULT 0,
           origin        TEXT NOT NULL,
           acked         INTEGER NOT NULL DEFAULT 0,
           ack_seq       INTEGER,
           peer_seq      INTEGER,
           local_updated_at INTEGER NOT NULL
         );
         CREATE INDEX IF NOT EXISTS ledger_cash_till ON ledger_cash(till_id, created_at);

         CREATE TABLE IF NOT EXISTS ledger_refunds (
           rkey          TEXT PRIMARY KEY,
           server_id     TEXT UNIQUE,
           order_id      TEXT NOT NULL,             -- the SERVER order id it refunds
           till_id       TEXT NOT NULL,
           amount        INTEGER NOT NULL,
           method        TEXT NOT NULL,
           is_cash       INTEGER NOT NULL,
           issued_at     TEXT NOT NULL,
           raw           TEXT NOT NULL,
           srv_raw       TEXT,
           srv_seq       INTEGER NOT NULL DEFAULT 0,
           origin        TEXT NOT NULL,
           acked         INTEGER NOT NULL DEFAULT 0,
           ack_seq       INTEGER,
           peer_seq      INTEGER,
           local_updated_at INTEGER NOT NULL
         );
         CREATE INDEX IF NOT EXISTS ledger_refunds_till ON ledger_refunds(till_id);
         CREATE INDEX IF NOT EXISTS ledger_refunds_order ON ledger_refunds(order_id);",
    )?;
    Ok(())
}

/// A sale's full record (lines + modifiers) for detail and reprint, keyed by the
/// server order id — replaces the `cache:order:<id>` blobs — and the server's
/// Z report for a till whose ledger rows are NOT all on this device (a till from
/// before this device's first snapshot) — replaces `cache:till_report:<id>`.
fn step3_order_details(tx: &Transaction<'_>) -> CoreResult<()> {
    tx.execute_batch(
        "CREATE TABLE IF NOT EXISTS order_details (
           order_id      TEXT PRIMARY KEY,
           raw           TEXT NOT NULL,             -- OrderFull JSON
           fetched_at    INTEGER NOT NULL
         );
         CREATE TABLE IF NOT EXISTS till_reports (
           till_id       TEXT PRIMARY KEY,
           raw           TEXT NOT NULL,             -- TillReportResponse JSON
           fetched_at    INTEGER NOT NULL
         );",
    )?;
    Ok(())
}

/// One-time move of everything a pre-B store knows about the ledger into the
/// rows: the changefeed's ledger rows, the `cache:*` history blobs, the till
/// records, and — above all — every still-queued outbox op, so the new read
/// path sees the queue the moment the app updates.
fn step4_backfill_ledger(tx: &Transaction<'_>) -> CoreResult<()> {
    crate::ledger::migrate::backfill(tx)
}

/// The blob caches the pre-B read paths kept (server lists written through to
/// kv so a screen survived offline). Step 4 moved what they knew into the rows;
/// the local rows are now the only read path, so nothing reads these again.
/// `cache:kds:lan` (the LAN relay's projection) is live state and stays.
pub(crate) const LEGACY_READ_CACHES: &[&str] = &[
    "cache:till_orders:",
    "cache:shift_orders:",
    "cache:till_report:",
    "cache:shift_report:",
    "cache:cash:",
    "cache:refunds:",
    "cache:order:",
    "cache:tills",
    "cache:open_tickets",
    "cache:delivery:",
    "cache:bookings:arrivals",
];

/// Delete the legacy read caches. A server Z report cached under the pre-rework
/// shape is first normalised into `till_reports` (step 4 copied it raw), so a
/// device updated mid-till keeps its figures. The outbox is not touched.
/// Peer rows whose author did not hold the act by this device's grants
/// (PERMISSIONS_ARCHITECTURE §4.4.4): the money fact is kept — it happened on
/// the other till — and recorded here for the owner's review.
fn step6_lan_authz_flags(tx: &Transaction<'_>) -> CoreResult<()> {
    tx.execute_batch(
        "CREATE TABLE IF NOT EXISTS lan_authz_flags (
           branch_id   TEXT NOT NULL,
           type        TEXT NOT NULL,
           id          TEXT NOT NULL,
           author      TEXT NOT NULL,
           cell        TEXT NOT NULL,
           reason      TEXT NOT NULL,
           recorded_at INTEGER NOT NULL,
           PRIMARY KEY (branch_id, type, id, cell)
         );",
    )?;
    Ok(())
}

/// Cash spot checks (owner design 2026-09-16 item 5): a count of an open
/// till's drawer against the expected figures, one row per check keyed by its
/// client-minted id. Written locally with its outbox op, and from the `till`
/// projection's `spot_checks` when the feed brings the till.
fn step7_spot_checks(tx: &Transaction<'_>) -> CoreResult<()> {
    tx.execute_batch(
        "CREATE TABLE IF NOT EXISTS ledger_spot_checks (
           id            TEXT PRIMARY KEY,
           till_id       TEXT NOT NULL,
           checked_at    TEXT NOT NULL,
           raw           TEXT NOT NULL,
           origin        TEXT NOT NULL,
           local_updated_at INTEGER NOT NULL
         );
         CREATE INDEX IF NOT EXISTS ledger_spot_checks_till ON ledger_spot_checks(till_id, checked_at);",
    )?;
    Ok(())
}

fn step5_drop_legacy_read_caches(tx: &Transaction<'_>) -> CoreResult<()> {
    let mut ids: Vec<String> = {
        let mut st = tx.prepare(
            "SELECT k FROM kv WHERE substr(k, 1, 18) = 'cache:till_report:' OR substr(k, 1, 19) = 'cache:shift_report:'",
        )?;
        let v = st.query_map([], |r| r.get::<_, String>(0))?.collect::<Result<Vec<_>, _>>()?;
        v.into_iter()
            .filter_map(|k| {
                k.strip_prefix("cache:till_report:").or_else(|| k.strip_prefix("cache:shift_report:")).map(str::to_string)
            })
            .collect()
    };
    ids.sort();
    ids.dedup();
    for id in ids {
        let raws: Vec<String> = {
            let mut st = tx.prepare("SELECT v FROM kv WHERE k IN (?1, ?2) ORDER BY k DESC")?;
            let v = st
                .query_map([format!("cache:till_report:{id}"), format!("cache:shift_report:{id}")], |r| r.get(0))?
                .collect::<Result<Vec<_>, _>>()?;
            v
        };
        if let Some(report) = raws.iter().find_map(|raw| crate::till::parse_cached_report(raw)) {
            tx.execute(
                "INSERT INTO till_reports(till_id, raw, fetched_at) VALUES(?1, ?2, ?3)
                 ON CONFLICT(till_id) DO UPDATE SET raw=excluded.raw",
                rusqlite::params![id, serde_json::to_string(&report)?, chrono::Utc::now().timestamp_millis()],
            )?;
        }
    }
    for prefix in LEGACY_READ_CACHES {
        tx.execute(
            "DELETE FROM kv WHERE substr(k, 1, length(?1)) = ?1 AND k <> 'cache:kds:lan'",
            [prefix],
        )?;
    }
    // Every per-station KDS board cache (`cache:kds:<station>`, `cache:kds:all`).
    tx.execute("DELETE FROM kv WHERE substr(k, 1, 10) = 'cache:kds:' AND k <> 'cache:kds:lan'", [])?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn noop(_: &Transaction<'_>) -> CoreResult<()> {
        Ok(())
    }
    fn make_t(tx: &Transaction<'_>) -> CoreResult<()> {
        tx.execute_batch("CREATE TABLE t (x INTEGER)")?;
        Ok(())
    }
    fn fill_t(tx: &Transaction<'_>) -> CoreResult<()> {
        tx.execute_batch("INSERT INTO t VALUES (1)")?;
        Ok(())
    }

    #[test]
    fn steps_run_once_in_order_and_bump_the_version() {
        let mut c = Connection::open_in_memory().unwrap();
        let steps: &[Step] = &[make_t, fill_t];
        let m = migrate_with(&mut c, steps, &mut |_| Ok(())).unwrap();
        assert_eq!((m.from, m.to, m.future_schema), (0, 2, false));
        let again = migrate_with(&mut c, steps, &mut |_| Ok(())).unwrap();
        assert_eq!((again.from, again.to), (2, 2));
        let n: i64 = c.query_row("SELECT COUNT(*) FROM t", [], |r| r.get(0)).unwrap();
        assert_eq!(n, 1, "the data step did not run twice");
    }

    #[test]
    fn a_step_killed_half_way_leaves_the_previous_version_and_reruns() {
        let path = std::env::temp_dir().join(format!("madar_schema_kill_{}.sqlite", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let steps: &[Step] = &[make_t, fill_t];
        {
            let mut c = Connection::open(&path).unwrap();
            let err = migrate_with(&mut c, steps, &mut |v| {
                if v == 2 {
                    Err(crate::error::CoreError::Internal { detail: "killed".into() })
                } else {
                    Ok(())
                }
            });
            assert!(err.is_err());
            assert_eq!(user_version(&c).unwrap(), 1, "step 1 committed, step 2 rolled back");
            let n: i64 = c.query_row("SELECT COUNT(*) FROM t", [], |r| r.get(0)).unwrap();
            assert_eq!(n, 0);
        }
        let mut c = Connection::open(&path).unwrap();
        migrate_with(&mut c, steps, &mut |_| Ok(())).unwrap();
        assert_eq!(user_version(&c).unwrap(), 2);
        let n: i64 = c.query_row("SELECT COUNT(*) FROM t", [], |r| r.get(0)).unwrap();
        assert_eq!(n, 1);
        drop(c);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn a_store_from_a_newer_build_is_flagged_not_migrated() {
        let mut c = Connection::open_in_memory().unwrap();
        c.pragma_update(None, "user_version", 99).unwrap();
        let m = migrate_with(&mut c, &[noop], &mut |_| Ok(())).unwrap();
        assert!(m.future_schema);
        assert_eq!(user_version(&c).unwrap(), 99);
    }

    /// The legacy read caches go; a pre-rework server report is kept as a row;
    /// the outbox and the live kv state are untouched.
    #[test]
    fn step5_drops_the_legacy_read_caches_and_keeps_the_rest() {
        let store = crate::store::Store::open("").unwrap();
        let legacy = r#"[{"shift":{"id":"00000000-0000-0000-0000-0000000000a1","branch_id":"00000000-0000-0000-0000-0000000000b1",
            "teller_id":"00000000-0000-0000-0000-0000000000c1","teller_name":"Sara","status":"open","opening_cash":500,
            "opened_at":"2026-09-01T09:00:00Z","opening_cash_was_edited":false},
            "cash_movements":[],"cash_movements_in":0,"cash_movements_net":0,"cash_movements_out":0,"cash_tips":0,
            "expected_cash":900,"net_payments":0,"non_cash_tips":0,"payment_summary":[],"printed_at":"2026-09-01T18:00:00Z",
            "total_payments":0,"total_tips":0,"voided_amount":0,"cash_adjustments":0,"safe_drops":0}]"#;
        let gone = [
            "cache:till_orders:T1", "cache:shift_orders:T0", "cache:shift_report:T1", "cache:cash:T1",
            "cache:refunds:shift:T1", "cache:refunds:order:O1", "cache:order:O1", "cache:tills",
            "cache:open_tickets", "cache:open_tickets:stale", "cache:kds:all", "cache:kds:st-1",
            "cache:delivery:all", "cache:delivery:received", "cache:bookings:arrivals",
        ];
        for k in gone {
            store.kv_put(k, if k == "cache:shift_report:T1" { legacy } else { "[]" }).unwrap();
        }
        let kept = ["cache:kds:lan", "cache:kds_stations", "cache:loyalty_settings", "floor:tables", "held:mirror"];
        for k in kept {
            store.kv_put(k, "[]").unwrap();
        }
        store
            .enqueue(&crate::store::NewOutboxOp {
                id: "op-1".into(),
                op_type: "create_order".into(),
                idempotency_key: "op-1".into(),
                payload: "{}".into(),
                event_at: "2026-09-01T10:00:00Z".into(),
                ..Default::default()
            })
            .unwrap();
        store.with_tx(step5_drop_legacy_read_caches).unwrap();
        for k in gone {
            assert!(store.kv_get(k).unwrap().is_none(), "{k} is gone");
        }
        for k in kept {
            assert!(store.kv_get(k).unwrap().is_some(), "{k} stays");
        }
        assert_eq!(store.pending().unwrap().len(), 1, "the outbox is intact");
        let report = crate::ledger::views::stored_till_report(&store, "T1").expect("the report is a row now");
        assert_eq!(report.expected_cash, 900);
    }
}
