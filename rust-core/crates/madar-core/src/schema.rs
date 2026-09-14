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
const STEPS: &[Step] = &[step1_sync_streams, step2_ledger, step3_order_details, step4_backfill_ledger];

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
         );",
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
}
