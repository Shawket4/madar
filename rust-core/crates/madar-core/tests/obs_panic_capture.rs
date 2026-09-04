//! A panic inside a spawned background task must reach Sentry.
//!
//! This is the gap `crate::obs` was built to close: tokio catches the unwind and
//! the `JoinError` is dropped on the floor, so a panic in any of the core's 8
//! background tasks (7 in `lan.rs`, 1 in `realtime.rs`) is invisible to the Dart
//! layer above the FFI. The panic HOOK runs before that, which is what makes the
//! report possible.
//!
//! Own test binary — `obs::init` installs a process-global client (see
//! `obs_offline_transport.rs`). Hermetic: the DSN points at a dead loopback port.

use std::sync::Arc;
use std::time::Duration;

const DEAD_DSN: &str = "http://abc123def456abc123def456abc12345@127.0.0.1:9/2";

#[test]
fn a_panic_in_a_spawned_task_is_reported_and_scrubbed() {
    std::env::set_var("MADAR_SENTRY_DSN", DEAD_DSN);
    let path = std::env::temp_dir().join(format!("madar_obs_panic_{}.sqlite", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let db = path.to_string_lossy().to_string();
    let store = Arc::new(madar_core::store::Store::open(&db).unwrap());
    assert!(madar_core::obs::init(store.clone(), "test", &db));

    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(async {
        // Exactly the shape of the relay/SSE tasks: nobody ever reads this result.
        let handle = tokio::spawn(async {
            panic!("beacon loop exploded: customer 01001234567 note");
        });
        let _ = handle.await;
    });

    std::thread::sleep(Duration::from_millis(500));
    let rows = store.sentry_due(i64::MAX, 10).unwrap();
    assert_eq!(rows.len(), 1, "the panic was not captured");
    let body = String::from_utf8_lossy(&rows[0].envelope);
    assert!(body.contains("beacon loop exploded"), "{body}");
    // A panic payload can interpolate anything the panicking code held — the
    // scrubber is the control that keeps it out of the report.
    assert!(
        !body.contains("01001234567"),
        "PII leaked through a panic payload: {body}"
    );
    assert!(body.contains("pii.scrubbed"));

    let _ = std::fs::remove_file(&path);
}
