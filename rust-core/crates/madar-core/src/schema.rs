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
const STEPS: &[Step] = &[step1_sync_streams];

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
