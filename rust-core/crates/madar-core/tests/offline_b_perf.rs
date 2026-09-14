//! OFFLINE_B performance probe against a real backend holding a large branch
//! (~30k sales inside the device's ledger window). Ignored by default.
//!
//! Only public API that exists before AND after offline plan B is used, so the
//! same file runs on the pre-B commit for the comparison.
//!
//! ```sh
//! MADAR_OB_BASE=http://127.0.0.1:8094 MADAR_OB_DB=postgres://localhost:5432/madar_ob_perf \
//! MADAR_OB_BRANCH=<branch> cargo test --release -p madar-core --test offline_b_perf -- --ignored --nocapture
//! ```
//!
//! Prints one `PERF` line: the cold first sync (sign-in to a complete store), the
//! warm start (a new core on the populated file, reopened session, first till
//! list and report), an incremental sync with nothing new, the store's size and
//! the process's peak resident memory.

use std::time::Instant;

use madar_core::session::{LoginMode, LoginRequest};
use madar_core::{MadarConfig, MadarCore};

fn env(k: &str) -> String {
    std::env::var(k).unwrap_or_else(|_| panic!("set {k}"))
}

/// This process's resident memory now, in MB (`ps`, so no extra dependency).
fn rss_mb() -> f64 {
    let out = std::process::Command::new("ps")
        .args(["-o", "rss=", "-p", &std::process::id().to_string()])
        .output()
        .expect("ps");
    String::from_utf8_lossy(&out.stdout).trim().parse::<f64>().unwrap_or(0.0) / 1024.0
}

fn core_at(base: &str, db: &str) -> std::sync::Arc<MadarCore> {
    MadarCore::new(MadarConfig {
        base_url: base.to_string(),
        environment: "dev".into(),
        db_path: db.to_string(),
        locale: "en".into(),
        app_version: None,
    })
    .expect("core")
}

#[tokio::test(flavor = "multi_thread")]
#[ignore]
async fn a_large_branch_syncs_and_starts_within_budget() {
    let (base, branch) = (env("MADAR_OB_BASE"), env("MADAR_OB_BRANCH"));
    let (dbc, conn) = tokio_postgres::connect(&env("MADAR_OB_DB"), tokio_postgres::NoTls).await.unwrap();
    tokio::spawn(async move {
        let _ = conn.await;
    });
    let branch_uuid = uuid::Uuid::parse_str(&branch).unwrap();
    let org: uuid::Uuid = dbc.query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch_uuid]).await.unwrap().get(0);
    let teller = format!("PERF-{}", &uuid::Uuid::new_v4().simple().to_string()[..8]);
    dbc.execute(
        "INSERT INTO users (org_id, name, role, pin_hash) VALUES ($1, $2, 'teller'::public.user_role, crypt('1234', gen_salt('bf', 4)))",
        &[&org, &teller],
    )
    .await
    .unwrap();
    let (big_till, orders): (uuid::Uuid, i64) = {
        let r = dbc
            .query_one(
                "SELECT t.id, COUNT(o.id) FROM tills t JOIN orders o ON o.till_id = t.id
                  WHERE t.branch_id = $1 AND t.status = 'open' GROUP BY t.id ORDER BY 2 DESC LIMIT 1",
                &[&branch_uuid],
            )
            .await
            .expect("an open till with sales");
        (r.get(0), r.get(1))
    };
    let big_till = big_till.to_string();

    let db = std::env::temp_dir().join(format!("madar_ob_perf_{}.sqlite", uuid::Uuid::new_v4().simple()));
    let db = db.to_string_lossy().into_owned();
    let login = || LoginRequest {
        mode: LoginMode::Pin,
        name: Some(teller.clone()),
        pin: Some("1234".into()),
        branch_id: Some(branch.clone()),
        email: None,
        password: None,
        org_id: None,
    };

    // Cold: an empty device signs in and syncs until the store is complete.
    let rss0 = rss_mb();
    let t0 = Instant::now();
    let core = core_at(&base, &db);
    core.sign_in(login()).await.expect("sign in");
    core.refresh_catalog().await.expect("catalog");
    let st = core.sync_full().await.expect("full sync");
    let cold = t0.elapsed();
    assert!(st.last_full_at.is_some(), "the full sync completed: {st:?}");
    let rss_sync = rss_mb();

    let t0 = Instant::now();
    core.sync_now().await.expect("incremental");
    let incremental = t0.elapsed();
    drop(core);

    // Warm start, online: a new core on the same file, session from the store,
    // then the history screens for the big till.
    let reads = |core: std::sync::Arc<MadarCore>, till: String| async move {
        let t = Instant::now();
        let tills = core.list_tills().await.map(|v| v.len().to_string()).unwrap_or_else(|e| format!("error {e}"));
        let list_tills = t.elapsed();
        let t = Instant::now();
        let rows = core.list_orders_for_till(till.clone()).await.map(|v| v.len().to_string()).unwrap_or_else(|e| format!("error {e}"));
        let list_orders = t.elapsed();
        let t = Instant::now();
        let report = core.till_report_for(till).await.map(|r| format!("{} from_server={}", r.total_payments_minor, r.from_server)).unwrap_or_else(|e| format!("error {e}"));
        let report_t = t.elapsed();
        format!(
            "list_tills_ms={} (n {tills}) list_orders_for_till_ms={} (n {rows}) till_report_for_ms={} (total {report})",
            list_tills.as_millis(),
            list_orders.as_millis(),
            report_t.as_millis()
        )
    };
    let t0 = Instant::now();
    let warm = core_at(&base, &db);
    warm.restore_session_cached().expect("cached session");
    let opened = t0.elapsed();
    // Online means the session knows it (a pre-B read asks the server only then).
    let t1 = Instant::now();
    warm.refresh_connectivity().await;
    let probe = t1.elapsed();
    let online_reads = reads(warm.clone(), big_till.clone()).await;
    drop(warm);

    // Warm start, offline: the same reads with no backend at all.
    let t0 = Instant::now();
    let off = core_at("http://127.0.0.1:1", &db);
    off.restore_session_cached().expect("cached session");
    let opened_off = t0.elapsed();
    let offline_reads = reads(off.clone(), big_till.clone()).await;
    let rss_end = rss_mb();
    drop(off);

    let bytes = std::fs::metadata(&db).map(|m| m.len()).unwrap_or(0)
        + std::fs::metadata(format!("{db}-wal")).map(|m| m.len()).unwrap_or(0);
    eprintln!(
        "PERF orders_on_big_till={orders} cold_first_sync_ms={} incremental_ms={} store_mb={:.1} rss_mb start={rss0:.0} after_sync={rss_sync:.0} end={rss_end:.0}",
        cold.as_millis(),
        incremental.as_millis(),
        bytes as f64 / 1_048_576.0,
    );
    eprintln!("PERF warm_online open_core_ms={} connectivity_ms={} {online_reads}", opened.as_millis(), probe.as_millis());
    eprintln!("PERF warm_offline open_core_ms={} {offline_reads}", opened_off.as_millis());
    let _ = std::fs::remove_file(&db);
}
