//! The Metrics screen against the REAL backend: what this device computes from
//! its own rows equals what `GET /reports/branches/{id}/pos-metrics` says for
//! the same day, online, offline and after the backlog drains; and the screen
//! is refused to someone without `reports.pos_metrics`.
//!
//! Ignored by `cargo test`. Run with the backend harness:
//!
//! ```sh
//! MADAR_OB_TESTS=metrics_backend tool/offline_b_backend.sh
//! ```

mod common;

use common::*;
use madar_core::metrics::PosMetricsView;
use madar_core::MadarCore;

async fn manager(fx: &Fixture) -> String {
    let id = uuid::Uuid::new_v4();
    let name = format!("MET-{}", &id.simple().to_string()[..6]);
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    let org: uuid::Uuid = fx.db.query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch]).await.unwrap().get(0);
    fx.db
        .execute(
            "INSERT INTO users (id, org_id, name, role, pin_hash)
             VALUES ($1, $2, $3, 'branch_manager'::public.user_role, crypt('1234', gen_salt('bf', 4)))",
            &[&id, &org, &name],
        )
        .await
        .expect("insert manager");
    fx.db
        .execute("INSERT INTO user_branch_assignments (user_id, branch_id) VALUES ($1, $2)", &[&id, &branch])
        .await
        .expect("assign");
    name
}

/// The figures only: which side answered and its notes are not figures.
fn figures(v: &PosMetricsView) -> PosMetricsView {
    let mut v = v.clone();
    v.source = String::new();
    v.offline_note = None;
    v.items_note = None;
    v
}

async fn server_and_device(core: &MadarCore) -> (PosMetricsView, PosMetricsView) {
    let server = core.pos_metrics("today".into(), None, None).await.expect("server metrics");
    let device = core.pos_metrics_on_device("today".into(), None, None).expect("device metrics");
    (server, device)
}

#[tokio::test]
#[ignore]
async fn device_figures_equal_the_servers_online_offline_and_drained() {
    let fx = fixture(1).await;
    let teller = fx.tellers[0].1.clone();
    let name = manager(&fx).await;
    let proxy = Proxy::start(&fx.base).await;

    // A teller does not hold the capability: the screen is refused, locally.
    {
        let db = temp_db("metrics-teller");
        let t = signed_in(&fx.base, &db, &teller, &fx.branch).await;
        assert!(!t.can("reports.pos_metrics".into()));
        let r = t.pos_metrics("today".into(), None, None).await;
        assert!(matches!(r, Err(madar_core::error::CoreError::Forbidden { .. })), "{r:?}");
        t.logout(false).ok();
        let _ = std::fs::remove_file(&db);
    }

    let db = temp_db("metrics");
    let core = core_at(&proxy.base, &db, &name, &fx.branch).await;
    assert!(core.can("reports.pos_metrics".into()));
    core.open_till(10_000, Some("metrics".into())).await.expect("open till");
    let cash = method(&core, true).unwrap();
    let card = method(&core, false);
    sell(&core, 2, &cash, 1_000_000).await;
    sell(&core, 3, &cash, 1_000_000).await;
    if let Some(card) = &card {
        sell(&core, 1, card, 0).await;
    }
    let voided = sell(&core, 1, &cash, 1_000_000).await;
    settle(&core, 300).await;
    core.void_order(voided, "customer_changed_mind".into(), None, false).await.expect("void");
    let synced: Vec<_> = core.list_till_orders().await.unwrap().into_iter().filter(|o| !o.queued && o.status == "completed").collect();
    core.refund_order(synced[0].id.clone(), synced[0].total_minor / 2, "cash".into(), "damaged".into(), None)
        .await
        .expect("refund");
    settle(&core, 300).await;

    // Online: the server answers, and the rows say the same.
    let (server, device) = server_and_device(&core).await;
    eprintln!("METRICS online server: {server:?}");
    assert_eq!(server.source, "server");
    assert_eq!(device.source, "device");
    assert!(server.order_count >= 3 && server.voided_count >= 1 && server.refunds_issued_count >= 1, "not vacuous");
    assert!(!server.top_items.is_empty());
    assert_eq!(figures(&device), figures(&server), "device rows vs the endpoint, online");

    // Offline: the screen still answers, from the rows, and says so.
    proxy.offline();
    for _ in 0..3 {
        core.refresh_connectivity().await;
    }
    assert!(!core.sync_status().online);
    let offline = core.pos_metrics("today".into(), None, None).await.expect("offline metrics");
    assert_eq!(offline.source, "device");
    let note = offline.offline_note.clone().expect("the offline note");
    assert!(note.starts_with("Offline: showing the last"), "{note}");
    assert_eq!(figures(&offline), figures(&server), "nothing moved while offline");
    sell(&core, 2, &cash, 1_000_000).await;
    let queued = core.pos_metrics("today".into(), None, None).await.unwrap();
    assert_eq!(queued.order_count, server.order_count + 1, "the queued sale counts");
    assert!(queued.items_note.is_some(), "its lines are not here yet, and the screen says so");

    // Reconnected and drained: the two agree again, with the new sale in both.
    proxy.online();
    core.refresh_connectivity().await;
    settle(&core, 300).await;
    settle(&core, 300).await;
    let (server, device) = server_and_device(&core).await;
    assert_eq!(server.source, "server");
    assert_eq!(server.order_count, queued.order_count);
    assert_eq!(figures(&device), figures(&server), "device rows vs the endpoint, drained");
    let _ = std::fs::remove_file(&db);
}
