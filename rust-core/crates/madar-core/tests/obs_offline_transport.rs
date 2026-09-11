//! The disk-backed Sentry transport, proven against a terminal that is OFFLINE —
//! which is a POS's normal state, and the whole reason `crate::obs` exists.
//!
//! Its own test BINARY on purpose: `obs::init` installs a process-global Sentry
//! client and reads a process-global env var, so it can be exercised exactly once
//! per process. (`obs_panic_capture.rs` is separate for the same reason.)
//!
//! Hermetic — the DSN points at a dead loopback port, so nothing leaves the
//! machine and every upload fails, which is precisely the path under test.

use std::sync::Arc;
use std::time::Duration;

/// A syntactically valid DSN aimed at a closed port: `init` succeeds and the
/// uploader always fails, isolating the durable-queue behaviour.
const DEAD_DSN: &str = "http://abc123def456abc123def456abc12345@127.0.0.1:9/2";

#[test]
fn captures_survive_on_disk_and_back_off_instead_of_being_lost() {
    std::env::set_var("MADAR_SENTRY_DSN", DEAD_DSN);
    let path = std::env::temp_dir().join(format!("madar_obs_it_{}.sqlite", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let db = path.to_string_lossy().to_string();

    let store = Arc::new(madar_core::store::Store::open(&db).unwrap());
    assert!(
        madar_core::obs::init(store.clone(), "test", &db),
        "init failed"
    );
    assert!(madar_core::obs::is_enabled());

    madar_core::obs::set_device_scope(Some("dev-1"), Some("branch-9"), Some("teller"));
    madar_core::obs::capture_bg_error("lan.accept", "tcp accept: too many open files");
    // The background tasks are infinite loops: a second identical report from the
    // same site inside the cooldown window must be suppressed, or one dead socket
    // would emit thousands of events a day.
    madar_core::obs::capture_bg_error("lan.accept", "tcp accept: too many open files");
    madar_core::obs::capture_bg_warning("realtime.stream_stopped", "403");

    // Offline by construction, so a flush must honestly report "not drained".
    assert!(!madar_core::obs::flush(Duration::from_secs(2)));

    // WAITED FOR, not asserted immediately — the same platform difference the
    // backoff loop below documents, biting one step earlier. A capture is
    // handed to Sentry's background worker, which reaches the disk queue by way
    // of an upload ATTEMPT, and how long that attempt takes depends on how the
    // host refuses a connection to a dead port: Linux and macOS send an instant
    // RST, Windows does not. So the 2s flush drained one report on Windows
    // while the second was still in the worker, and the assertion read 1 — red
    // on one platform about behaviour identical on all three.
    let pending = wait_for(&store, 2);
    assert_eq!(
        pending, 2,
        "expected the two non-deduped reports to be durably queued"
    );

    // A failed upload backs the row off; it is never dropped and never hot-looped.
    //
    // WAITED FOR, not slept past. How long a failed upload takes depends on how
    // the host refuses a connection to a dead port: Linux and macOS send an
    // instant RST, Windows does not, so a fixed sleep asserted the backoff
    // before the attempt that records it had finished — green on two platforms
    // and red on the third, about behaviour that is identical on all three.
    let deadline = std::time::Instant::now() + Duration::from_secs(30);
    let backed_off = loop {
        let due = store
            .sentry_due(chrono::Utc::now().timestamp_millis(), 10)
            .unwrap();
        if due.is_empty() {
            break true;
        }
        if std::time::Instant::now() >= deadline {
            break false;
        }
        std::thread::sleep(Duration::from_millis(100));
    };
    assert!(backed_off, "a failed upload must be backed off");
    assert_eq!(store.sentry_pending_count().unwrap(), 2, "nothing was lost");

    // What landed is a real envelope, carrying the device scope and the proof
    // that the PII scrubber ran.
    let all = store.sentry_due(i64::MAX, 10).unwrap();
    let body = String::from_utf8_lossy(&all[0].envelope);
    assert!(
        body.contains("pii.scrubbed"),
        "scrub marker missing: {body}"
    );
    assert!(body.contains("branch-9"), "device scope missing: {body}");
    assert!(body.contains("lan.accept"));

    let _ = std::fs::remove_file(&path);
}

/// Block until the durable queue holds `want` rows, or give up after 30s and
/// return whatever it holds so the assertion can report the real number.
///
/// Polling rather than sleeping a fixed span: the wait is for an upload attempt
/// against a dead port to finish, and that takes an instant on Linux and macOS
/// and rather longer on Windows. A sleep long enough for Windows would be dead
/// time on every other run, and a sleep short enough for Linux is the flake
/// this replaces.
fn wait_for(store: &madar_core::store::Store, want: u32) -> u32 {
    let deadline = std::time::Instant::now() + Duration::from_secs(30);
    loop {
        let n = store.sentry_pending_count().unwrap();
        if n >= want || std::time::Instant::now() >= deadline {
            return n;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}
