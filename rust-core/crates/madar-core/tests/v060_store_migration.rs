//! A REAL store written by POS v0.6.0 (commit 97c4a29, built from that tree and
//! driven through its own offline open/cash/close/open/cash flow) opened by the
//! tills-rework core. Fixture: tests/fixtures/store_v0_6_0.sqlite.

use madar_core::store::Store;
use madar_core::{MadarConfig, MadarCore};

fn copy_fixture(tag: &str) -> std::path::PathBuf {
    let src = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/store_v0_6_0.sqlite");
    let dst = std::env::temp_dir().join(format!("madar_v060_{tag}_{}.sqlite", std::process::id()));
    let _ = std::fs::remove_file(&dst);
    std::fs::copy(&src, &dst).unwrap();
    dst
}

fn raw_rows(path: &std::path::Path) -> Vec<(i64, String, String, String)> {
    let c = rusqlite::Connection::open(path).unwrap();
    let mut st = c.prepare("SELECT seq, id, op_type, payload FROM outbox ORDER BY seq").unwrap();
    st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap()
}

#[test]
fn v060_store_fixture_migrates_without_payload_loss() {
    let path = copy_fixture("migrate");
    let before = raw_rows(&path);
    assert_eq!(before.len(), 5, "fixture holds open, cash, close, open, cash");

    let store = Store::open(path.to_str().unwrap()).expect("v0.6.0 store opens");
    let after = store.list_active().unwrap();
    assert_eq!(after.len(), before.len(), "no row lost");
    for ((seq, id, old_type, payload), row) in before.iter().zip(after.iter()) {
        assert_eq!(row.seq, *seq);
        assert_eq!(&row.id, id);
        assert_eq!(&row.payload, payload, "payload bytes untouched");
        let want = match old_type.as_str() {
            "open_shift" => "open_till",
            "close_shift" => "close_till",
            other => other,
        };
        assert_eq!(row.op_type, want);
        assert!(row.till_id.is_some(), "till_id carried from shift_id");
    }
    // Per-till gating over migrated rows: the second till's ops do not wait on
    // the first till's queue.
    let second_open = after.iter().filter(|r| r.op_type == "open_till").nth(1).unwrap();
    assert!(!store.must_wait(second_open).unwrap());
    let first_close = after.iter().find(|r| r.op_type == "close_till").unwrap();
    assert!(store
        .has_live_till_writes(first_close.till_id.as_deref().unwrap(), first_close.seq)
        .unwrap(), "close still waits on its pending pay-in");
    drop(store);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn v060_store_fixture_boots_a_core_with_the_tellers_till() {
    let path = copy_fixture("boot");
    let core = MadarCore::new(MadarConfig {
        base_url: "http://127.0.0.1:1".into(),
        environment: "dev".into(),
        db_path: path.to_str().unwrap().into(),
        locale: "ar".into(),
        app_version: None,
    })
    .expect("core boots on a v0.6.0 store");
    assert_eq!(core.pending_outbox_count().unwrap(), 5);
    // The persisted v0.6 session restores; the legacy current shift becomes
    // Sara's till on this device.
    let snap = core.restore_session_cached().expect("v0.6 session restores");
    let till = core.current_till().unwrap().expect("legacy current_shift migrated");
    assert_eq!(till.teller_id, snap.user_id);
    assert!(till.is_open);
    assert_eq!(till.verification, "legacy");
    let outbox = core.list_outbox().unwrap();
    assert!(outbox.iter().all(|o| o.op_type != "open_shift" && o.op_type != "close_shift"));
    drop(core);
    let _ = std::fs::remove_file(&path);
}
