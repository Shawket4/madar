//! Boot integrity check (OFFLINE_B_DESIGN §8 "DB corruption").
//!
//! Everything in the store except the outbox (and held drafts) is re-derivable
//! from the server. So a damaged file is handled by protecting the outbox first:
//!
//! * a while after boot, a bounded `PRAGMA quick_check` runs off the caller's
//!   thread;
//! * on failure the live outbox rows are exported, as JSON, to a file next to the
//!   database (`<db>.outbox-<ms>.json`), the failure goes to Sentry and the
//!   diagnostics ring, and `store:integrity` in kv records it;
//! * the file is NOT renamed, recreated or re-bootstrapped automatically. That
//!   step can lose the very queue it is meant to save if the export itself was
//!   partial, so it stays an explicit support action (decision log, "Implementation
//!   status").

use std::time::Duration;

use rusqlite::Connection;

use crate::error::CoreResult;
use crate::store::Store;

/// How long after boot the check waits (the first screens load first).
pub(crate) const CHECK_DELAY: Duration = Duration::from_secs(20);
/// kv key holding the last outcome (`ok <at>` or `failed <at>: <first problem>`).
pub(crate) const K_INTEGRITY: &str = "store:integrity";

/// `PRAGMA quick_check`, capped at `max_errors` messages. Empty = healthy.
pub(crate) fn quick_check(conn: &Connection, max_errors: u32) -> CoreResult<Vec<String>> {
    let mut st = conn.prepare(&format!("PRAGMA quick_check({max_errors})"))?;
    let rows = st
        .query_map([], |r| r.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(if rows.len() == 1 && rows[0] == "ok" { Vec::new() } else { rows })
}

/// Every outbox row that still matters (not acked, not discarded), as JSON.
pub(crate) fn live_outbox_json(conn: &Connection) -> CoreResult<serde_json::Value> {
    let mut st = conn.prepare(
        "SELECT seq, id, op_type, idempotency_key, payload, event_at, status, attempts, last_error, depends_on_seq, till_id
           FROM outbox WHERE status IN ('pending','inflight','dead') ORDER BY seq",
    )?;
    let rows = st
        .query_map([], |r| {
            Ok(serde_json::json!({
                "seq": r.get::<_, i64>(0)?,
                "id": r.get::<_, String>(1)?,
                "op_type": r.get::<_, String>(2)?,
                "idempotency_key": r.get::<_, String>(3)?,
                "payload": r.get::<_, String>(4)?,
                "event_at": r.get::<_, String>(5)?,
                "status": r.get::<_, String>(6)?,
                "attempts": r.get::<_, i64>(7)?,
                "last_error": r.get::<_, Option<String>>(8)?,
                "depends_on_seq": r.get::<_, Option<i64>>(9)?,
                "till_id": r.get::<_, Option<String>>(10)?,
            }))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(serde_json::Value::Array(rows))
}

/// What one check found.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Outcome {
    Healthy,
    /// Damaged; `exported` is where the live outbox went (None if the export
    /// itself failed — the problems say why).
    Damaged { problems: Vec<String>, exported: Option<String> },
}

/// Run the check on `store` (file at `db_path`), exporting the outbox on damage.
pub(crate) fn run(store: &Store, db_path: &str, now_ms: i64) -> Outcome {
    let problems = match store.with_conn(|c| quick_check(c, 8)) {
        Ok(p) if p.is_empty() => {
            let _ = store.kv_put(K_INTEGRITY, &format!("ok {now_ms}"));
            return Outcome::Healthy;
        }
        Ok(p) => p,
        // A check that cannot even run on this file is itself the finding.
        Err(e) => vec![format!("quick_check failed to run: {e}")],
    };
    let mut problems = problems;
    let exported = match store.with_conn(live_outbox_json) {
        Ok(rows) => {
            let path = format!("{db_path}.outbox-{now_ms}.json");
            match std::fs::write(&path, serde_json::to_vec_pretty(&rows).unwrap_or_default()) {
                Ok(()) => Some(path),
                Err(e) => {
                    problems.push(format!("outbox export failed to write: {e}"));
                    None
                }
            }
        }
        Err(e) => {
            problems.push(format!("outbox export failed to read: {e}"));
            None
        }
    };
    let _ = store.kv_put(K_INTEGRITY, &format!("failed {now_ms}: {}", problems.first().cloned().unwrap_or_default()));
    Outcome::Damaged { problems, exported }
}

impl crate::MadarCore {
    /// Schedule the boot check (file-backed stores only).
    pub(crate) fn schedule_integrity_check(&self) {
        if self.config.db_path.is_empty() {
            return;
        }
        let weak = self.me.clone();
        let _ = std::thread::Builder::new().name("madar-integrity".into()).spawn(move || {
            std::thread::sleep(CHECK_DELAY);
            let Some(core) = weak.upgrade() else { return };
            let now = chrono::Utc::now().timestamp_millis();
            if let Outcome::Damaged { problems, exported } = run(&core.store, &core.config.db_path, now) {
                let msg = format!(
                    "local store failed its integrity check: {}; live outbox exported to {}",
                    problems.join("; "),
                    exported.as_deref().unwrap_or("(export failed)")
                );
                crate::obs::capture_bg_error("store.integrity", msg.clone());
                core.push_diag("error", msg);
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::NewOutboxOp;

    fn temp_path(tag: &str) -> String {
        std::env::temp_dir()
            .join(format!("madar_integrity_{tag}_{}.sqlite", uuid::Uuid::new_v4().simple()))
            .to_string_lossy()
            .into_owned()
    }

    fn queue(store: &Store, n: usize) {
        for i in 0..n {
            store
                .enqueue(&NewOutboxOp {
                    id: format!("op-{i}"),
                    op_type: "create_order".into(),
                    idempotency_key: format!("k-{i}"),
                    payload: format!("{{\"n\":{i},\"pad\":\"{}\"}}", "x".repeat(400)),
                    event_at: "2026-09-14T10:00:00Z".into(),
                    ..Default::default()
                })
                .unwrap();
        }
    }

    #[test]
    fn a_healthy_store_passes_and_records_it() {
        let path = temp_path("ok");
        let store = Store::open(&path).unwrap();
        queue(&store, 3);
        assert_eq!(run(&store, &path, 42), Outcome::Healthy);
        assert_eq!(store.kv_get(K_INTEGRITY).unwrap().as_deref(), Some("ok 42"));
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn the_live_outbox_exports_whole_and_in_order() {
        let store = Store::open("").unwrap();
        queue(&store, 5);
        let rows = store.with_conn(live_outbox_json).unwrap();
        let ids: Vec<&str> = rows.as_array().unwrap().iter().map(|r| r["id"].as_str().unwrap()).collect();
        assert_eq!(ids, vec!["op-0", "op-1", "op-2", "op-3", "op-4"]);
        assert!(rows[0]["payload"].as_str().unwrap().contains("\"n\":0"));
    }

    /// A file whose pages were overwritten fails the check, and whatever of the
    /// outbox can still be read lands beside it (or the failure to read it is
    /// named) — the file itself is left exactly where it was.
    #[test]
    fn a_damaged_file_is_reported_and_its_outbox_exported() {
        let path = temp_path("bad");
        {
            let store = Store::open(&path).unwrap();
            queue(&store, 400);
            // Filler in another table, so the damage below lands away from page 1.
            store
                .with_conn(|c| {
                    c.execute_batch("CREATE TABLE filler(x TEXT); WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<2000) INSERT INTO filler SELECT hex(randomblob(200)) FROM n;")?;
                    c.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")?;
                    Ok(())
                })
                .unwrap();
        }
        // Scribble over pages near the end of the file (the filler's b-tree).
        {
            use std::io::{Seek, SeekFrom, Write};
            let len = std::fs::metadata(&path).unwrap().len();
            let mut f = std::fs::OpenOptions::new().write(true).open(&path).unwrap();
            f.seek(SeekFrom::Start(len - 64 * 4096)).unwrap();
            f.write_all(&vec![0xA5u8; 16 * 4096]).unwrap();
        }
        let store = Store::open(&path).unwrap();
        match run(&store, &path, 7) {
            Outcome::Damaged { problems, exported } => {
                assert!(!problems.is_empty());
                if let Some(file) = exported {
                    let rows: serde_json::Value = serde_json::from_slice(&std::fs::read(&file).unwrap()).unwrap();
                    assert_eq!(rows.as_array().unwrap().len(), 400, "the whole queue was saved");
                    let _ = std::fs::remove_file(file);
                } else {
                    assert!(problems.iter().any(|p| p.contains("outbox export failed")));
                }
            }
            Outcome::Healthy => panic!("scribbled pages passed the check"),
        }
        assert!(store.kv_get(K_INTEGRITY).unwrap().unwrap().starts_with("failed 7"));
        assert!(std::path::Path::new(&path).exists(), "the damaged file is left in place");
        let _ = std::fs::remove_file(&path);
    }
}
