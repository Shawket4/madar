//! A POS on this Mac against a REAL kitchen tablet on the same Wi-Fi: the
//! manual check behind `lan_offline.rs`. Discovery is the real thing (the
//! core's mDNS here, the app's Bonjour on the tablet). One POS store is kept
//! in `MADAR_IPAD_DIR` across three runs, so the backend can be stopped and
//! started between them:
//!
//! ```sh
//! export MADAR_IPAD_DIR=/tmp/madar-ipad MADAR_BRANCH=TestBranch DATABASE_URL=…
//! T="cargo test -p madar_kitchen_ffi --features backend-tests --test lan_ipad -- --nocapture"
//! MADAR_IPAD_PHASE=setup $T   # backend up: activate + sign the waiter in
//! # stop the backend
//! MADAR_IPAD_PHASE=fire $T    # find the tablet, fire a round, wait for its bump
//! # start the backend
//! MADAR_IPAD_PHASE=sync $T    # drain, then read what the server holds
//! MADAR_IPAD_PHASE=order $T   # backend up: one online round (a closed screen gets a push)
//! ```

use std::time::Duration;

use madar_core::session::{LoginMode, LoginRequest};
use madar_core::{MadarConfig, MadarCore};

fn env(k: &str, default: &str) -> String {
    std::env::var(k).unwrap_or_else(|_| default.to_string())
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn pos_on_this_mac_with_a_real_kitchen_tablet() {
    let Ok(phase) = std::env::var("MADAR_IPAD_PHASE") else {
        eprintln!("MADAR_IPAD_PHASE not set: skipped");
        return;
    };
    let dir = std::path::PathBuf::from(std::env::var("MADAR_IPAD_DIR").expect("MADAR_IPAD_DIR"));
    std::fs::create_dir_all(&dir).unwrap();
    let pos = MadarCore::new(MadarConfig {
        base_url: env("MADAR_IT_BASE", "http://127.0.0.1:8082"),
        environment: "dev".into(),
        db_path: dir.join("pos.db").to_string_lossy().into(),
        locale: "en".into(),
        app_version: None,
    })
    .expect("pos core");
    let (db, conn) = tokio_postgres::connect(&env("DATABASE_URL", "postgres://madar@localhost:5432/madar"), tokio_postgres::NoTls)
        .await
        .expect("local Postgres (DATABASE_URL)");
    tokio::spawn(conn);
    let ticket_file = dir.join("ticket_id");

    match phase.as_str() {
        "setup" => {
            let branch = env("MADAR_BRANCH", "TestBranch");
            let branch_id: String = db
                .query_one("SELECT id::text FROM branches WHERE name = $1", &[&branch])
                .await
                .expect("the branch")
                .get(0);
            let code = format!("{:08}", uuid::Uuid::new_v4().as_u128() % 100_000_000);
            db.execute(
                "INSERT INTO device_activation_codes (org_id, branch_id, code, kind) \
                 SELECT org_id, id, $2, 'pos' FROM branches WHERE id = $1::text::uuid",
                &[&branch_id, &code],
            )
            .await
            .unwrap();
            pos.activate_device(code).await.expect("activate the POS");
            pos.login(LoginRequest {
                mode: LoginMode::Pin,
                name: Some(env("MADAR_IT_WAITER", "Waiter Karim")),
                pin: Some(env("MADAR_IT_WAITER_PIN", "112233")),
                branch_id: Some(branch_id),
                email: None,
                password: None,
                org_id: None,
            })
            .await
            .expect("waiter sign-in");
            pos.refresh_catalog().await.expect("catalog");
            pos.sync_now().await.expect("pull");
            eprintln!("SETUP OK: POS signed in, catalog and branch pulled");
        }
        "fire" => {
            pos.restore_session_cached().expect("a saved session (run setup first)");
            assert!(!pos.refresh_connectivity().await || !pos.refresh_connectivity().await, "the backend is still up: stop it first");
            pos.lan_start().await.expect("LAN (the key comes from setup)");
            eprintln!("LAN up on port {:?}; looking for the tablet…", pos.lan_status().tcp_port);
            let mut found = false;
            for _ in 0..120 {
                if pos.lan_peer_count() > 0 {
                    found = true;
                    break;
                }
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
            assert!(found, "no kitchen tablet of this branch found on the LAN in 2 minutes");
            eprintln!("PEER FOUND ({} on the LAN)", pos.lan_peer_count());

            let items = pos.list_menu_items().expect("menu");
            for it in &items[..2] {
                pos.cart_add(None, it.id.clone(), it.name.clone(), it.base_price_minor).unwrap();
            }
            let fired = pos.fire_ticket(None, None, Some("LAN check from the Mac".into()), None, None, None).await.expect("fire");
            assert!(fired.queued_offline, "the fire should be queued offline");
            std::fs::write(&ticket_file, &fired.ticket_id).unwrap();
            eprintln!("FIRED OFFLINE: {} + {} (note: LAN check from the Mac)", items[0].name, items[1].name);

            let before = pos.pending_outbox_count().unwrap();
            eprintln!("WAITING up to 5 min for a bump on the tablet…");
            for _ in 0..300 {
                if pos.pending_outbox_count().unwrap() > before {
                    eprintln!("BUMP RECEIVED over the LAN (the POS now holds a copy)");
                    pos.lan_stop();
                    return;
                }
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
            pos.lan_stop();
            panic!("no bump came back from the tablet in 5 minutes");
        }
        "order" => {
            // An ordinary online round, for a push to a kitchen screen that is closed.
            pos.restore_session_cached().expect("a saved session (run setup first)");
            assert!(pos.refresh_connectivity().await, "the backend is up");
            let items = pos.list_menu_items().expect("menu");
            for it in &items[..2] {
                pos.cart_add(None, it.id.clone(), it.name.clone(), it.base_price_minor).unwrap();
            }
            let fired = pos.fire_ticket(None, None, Some("Push check from the Mac".into()), None, None, None).await.expect("fire");
            pos.sync_now().await.ok();
            assert_eq!(pos.sync_status().pending_outbox, 0, "the round reached the server");
            eprintln!("FIRED ONLINE: {} + {} (ticket {})", items[0].name, items[1].name, fired.ticket_id);
        }
        "sync" => {
            pos.restore_session_cached().expect("a saved session");
            let ticket_id = uuid::Uuid::parse_str(std::fs::read_to_string(&ticket_file).expect("run fire first").trim()).unwrap();
            for _ in 0..60 {
                pos.refresh_connectivity().await;
                let _ = pos.sync_now().await;
                if pos.sync_status().pending_outbox == 0 {
                    break;
                }
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
            let s = pos.sync_status();
            eprintln!("POS outbox: pending {}, dead {}", s.pending_outbox, s.dead_outbox);
            let kts = db
                .query(
                    "SELECT kt.id FROM kitchen_tickets kt JOIN open_tickets ot ON ot.id = kt.source_id \
                     WHERE kt.source_type = 'open_ticket' AND ot.idempotency_key = $1",
                    &[&ticket_id],
                )
                .await
                .unwrap();
            eprintln!("SERVER: {} kitchen ticket(s) for the round", kts.len());
            for kt in &kts {
                let id: uuid::Uuid = kt.get(0);
                for r in db
                    .query(
                        "SELECT line->>'name', bumped_at IS NOT NULL FROM kitchen_ticket_items WHERE kitchen_ticket_id = $1 ORDER BY created_at",
                        &[&id],
                    )
                    .await
                    .unwrap()
                {
                    let (name, bumped): (Option<String>, bool) = (r.get(0), r.get(1));
                    eprintln!("  {} — {}", name.unwrap_or_default(), if bumped { "bumped" } else { "open" });
                }
            }
            assert_eq!(kts.len(), 1, "the round reached the server exactly once");
            assert_eq!(s.dead_outbox, 0);
        }
        other => panic!("unknown MADAR_IPAD_PHASE {other}"),
    }
}
