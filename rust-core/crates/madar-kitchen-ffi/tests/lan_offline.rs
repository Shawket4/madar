//! Offline-first ordering between the POS and Madar Kitchen, over the real LAN
//! relay (loopback TCP) and a real backend that drops off the network.
//!
//! Two devices: a POS (`MadarCore`, a waiter) and a kitchen (`KitchenCore`,
//! exactly what the app calls). Both reach the backend through a switchable
//! proxy, so "the internet goes down" is a flag, not a stopped server:
//!
//!   1. online: both sign in (the LAN key comes with the online sign-in)
//!   2. offline: the POS fires a round → it reaches the kitchen board by LAN
//!   3. offline: the kitchen bumps one line → the POS mirrors the bump
//!   4. online again: both drain → the server holds the ticket once, its
//!      lines once, the bump on the right line, and the board shows it once
//!
//! Needs a local backend and the test kitchen from
//! `apps/kitchen/scripts/dev-kitchen-demo.py` (its sections, cook, waiter and
//! open shift), with that script's environment:
//!
//! ```sh
//! MADAR_BRANCH=TestBranch \
//! cargo test -p madar_kitchen_ffi --features backend-tests --test lan_offline -- --nocapture
//! ```

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use madar_core::session::{LoginMode, LoginRequest};
use madar_core::{MadarConfig, MadarCore};
use madar_kitchen_ffi::KitchenCore;
use tokio::net::{TcpListener, TcpStream};

fn env(k: &str, default: &str) -> String {
    std::env::var(k).unwrap_or_else(|_| default.to_string())
}

/// A TCP proxy to the backend that can be cut: while down, every connection is
/// dropped on accept and every open tunnel is closed, which the core reads as
/// no network (the same as a router losing its uplink).
#[derive(Clone)]
struct Net {
    up: Arc<AtomicBool>,
    tunnels: Arc<Mutex<Vec<tokio::task::AbortHandle>>>,
}

impl Net {
    fn cut(&self) {
        self.up.store(false, Ordering::SeqCst);
        self.tunnels
            .lock()
            .unwrap()
            .drain(..)
            .for_each(|t| t.abort());
    }
    fn restore(&self) {
        self.up.store(true, Ordering::SeqCst);
    }
}

async fn switchable_proxy(upstream: String) -> (String, Net) {
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind proxy");
    let url = format!("http://{}", listener.local_addr().unwrap());
    let net = Net {
        up: Arc::new(AtomicBool::new(true)),
        tunnels: Arc::default(),
    };
    let n = net.clone();
    tokio::spawn(async move {
        while let Ok((mut client, _)) = listener.accept().await {
            if !n.up.load(Ordering::SeqCst) {
                continue; // dropped: connection closed with no answer
            }
            let upstream = upstream.clone();
            let tunnel = tokio::spawn(async move {
                if let Ok(mut server) = TcpStream::connect(&upstream).await {
                    let _ = tokio::io::copy_bidirectional(&mut client, &mut server).await;
                }
            });
            n.tunnels.lock().unwrap().push(tunnel.abort_handle());
        }
    });
    (url, net)
}

/// Poll `f` until it returns `Some`, or fail with `what`.
async fn within<T, F, Fut>(secs: u64, what: &str, mut f: F) -> T
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Option<T>>,
{
    let deadline = tokio::time::Instant::now() + Duration::from_secs(secs);
    loop {
        if let Some(v) = f().await {
            return v;
        }
        assert!(tokio::time::Instant::now() < deadline, "timed out: {what}");
        tokio::time::sleep(Duration::from_millis(300)).await;
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn pos_fires_offline_kitchen_bumps_offline_server_gets_both_once() {
    let backend = env("MADAR_IT_BASE", "http://127.0.0.1:8082");
    let branch_name = env("MADAR_BRANCH", "TestBranch");
    let (waiter, waiter_pin) = (
        env("MADAR_IT_WAITER", "Waiter Karim"),
        env("MADAR_IT_WAITER_PIN", "112233"),
    );
    let (cook, cook_pin) = (
        env("MADAR_IT_COOK", "Chef Mona"),
        env("MADAR_IT_COOK_PIN", "357913"),
    );

    let (db, conn) = tokio_postgres::connect(
        &env("DATABASE_URL", "postgres://madar@localhost:5432/madar"),
        tokio_postgres::NoTls,
    )
    .await
    .expect("local Postgres (DATABASE_URL)");
    tokio::spawn(conn);

    let upstream = backend
        .trim_start_matches("http://")
        .trim_end_matches('/')
        .to_string();
    let (api, net) = switchable_proxy(upstream).await;

    let dir = std::env::temp_dir().join(format!("madar_lan_offline_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);

    // ── 1. Online: set both devices up ───────────────────────────────────────
    let kitchen = KitchenCore::new(
        dir.join("kitchen").to_string_lossy().into(),
        api.clone(),
        "dev".into(),
        "en".into(),
    )
    .expect("kitchen core");
    // The manager's sign-in only lists branches to pick from; bind the branch directly.
    let branch_id: String = db
        .query_opt(
            "SELECT id::text FROM branches WHERE name = $1",
            &[&branch_name],
        )
        .await
        .unwrap()
        .unwrap_or_else(|| panic!("no branch named {branch_name} (run dev-kitchen-demo.py)"))
        .get(0);
    kitchen
        .choose_branch(branch_id.clone(), branch_name.clone())
        .expect("bind branch");
    kitchen.sign_in(cook, cook_pin).await.expect("cook sign-in");
    let sections: Vec<String> = kitchen
        .stations()
        .await
        .expect("sections")
        .into_iter()
        .map(|s| s.id)
        .collect();
    assert!(!sections.is_empty(), "the branch has kitchen sections");
    kitchen
        .set_sections("sections".into(), sections)
        .expect("sections");
    kitchen.sync_now().await.expect("kitchen pull");
    assert_eq!(kitchen.state().route, "board");

    let pos = MadarCore::new(MadarConfig {
        base_url: api.clone(),
        environment: "dev".into(),
        db_path: dir.join("pos.db").to_string_lossy().into(),
        locale: "en".into(),
        app_version: None,
    })
    .expect("pos core");
    // A POS is set up the way the shop does it: an activation code minted in
    // the dashboard, which makes it a registered device of the branch.
    let code = format!("{:08}", uuid::Uuid::new_v4().as_u128() % 100_000_000);
    db.execute(
        "INSERT INTO device_activation_codes (org_id, branch_id, code, kind) \
         SELECT org_id, id, $2, 'pos' FROM branches WHERE id = $1::text::uuid",
        &[&branch_id, &code],
    )
    .await
    .expect("mint an activation code");
    pos.activate_device(code).await.expect("activate the POS");
    pos.login(LoginRequest {
        mode: LoginMode::Pin,
        name: Some(waiter),
        pin: Some(waiter_pin),
        branch_id: Some(branch_id.clone()),
        email: None,
        password: None,
        org_id: None,
    })
    .await
    .expect("waiter sign-in");
    pos.refresh_connectivity().await;
    pos.refresh_catalog().await.expect("catalog");
    pos.sync_now().await.expect("pos pull");

    // The LAN: real sockets on loopback. Bonjour is the host's job on a tablet;
    // here each side is told where the other listens, and re-told inside the TTL.
    kitchen.lan_start().await.expect("kitchen LAN");
    pos.lan_start().await.expect("pos LAN");
    let (k_ad, p_ad) = (
        kitchen.lan_advert().expect("kitchen advert"),
        pos.lan_advert().expect("pos advert"),
    );
    let (k2, p2) = (kitchen.clone(), pos.clone());
    let introduce = tokio::spawn(async move {
        loop {
            k2.lan_note_peer(
                p_ad.device_id.clone(),
                p_ad.branch_id.clone(),
                "127.0.0.1".into(),
                p_ad.tcp_port,
                p_ad.role.clone(),
                p_ad.station_id.clone(),
                p_ad.device_code.clone(),
            );
            p2.lan_note_peer(
                k_ad.device_id.clone(),
                k_ad.branch_id.clone(),
                "127.0.0.1".into(),
                k_ad.tcp_port,
                k_ad.role.clone(),
                k_ad.station_id.clone(),
                k_ad.device_code.clone(),
            );
            tokio::time::sleep(Duration::from_secs(3)).await;
        }
    });
    within(10, "the devices see each other", || async {
        (kitchen.lan_status().peer_count > 0 && pos.lan_peer_count() > 0).then_some(())
    })
    .await;

    // ── 2. Offline: the POS fires; the kitchen gets it by LAN ────────────────
    net.cut();
    // One failed probe could be a blip; the core takes two to call it offline.
    within(10, "the POS sees it is offline", || async {
        (!pos.refresh_connectivity().await).then_some(())
    })
    .await;

    let items = pos.list_menu_items().expect("menu");
    assert!(items.len() >= 2, "the menu has at least two items");
    for it in &items[..2] {
        pos.cart_add(None, it.id.clone(), it.name.clone(), it.base_price_minor)
            .expect("add to cart");
    }
    let before: Vec<String> = kitchen
        .tickets(None)
        .await
        .unwrap()
        .into_iter()
        .map(|t| t.id)
        .collect();
    let fired = pos
        .fire_ticket(
            None,
            None,
            Some("lan offline test".into()),
            None,
            None,
            None,
        )
        .await
        .expect("fire offline");
    assert!(fired.queued_offline, "the fire was queued, not sent");

    let ticket = within(15, "the round reaches the kitchen over the LAN", || async {
        kitchen
            .tickets(None)
            .await
            .ok()?
            .into_iter()
            .find(|t| !before.contains(&t.id))
    })
    .await;
    assert_eq!(ticket.items.len(), 2, "both lines arrived");
    let line_ids: Vec<String> = ticket.items.iter().map(|l| l.id.clone()).collect();

    // ── 3. Offline: the kitchen bumps one line; the POS mirrors it ──────────
    let pos_pending_before = pos.pending_outbox_count().unwrap();
    kitchen
        .bump(line_ids[0].clone())
        .await
        .expect("bump offline");
    assert!(
        kitchen.state().pending >= 1,
        "the bump waits in the kitchen's outbox"
    );
    let board = kitchen.tickets(None).await.unwrap();
    let t = board
        .iter()
        .find(|t| t.id == ticket.id)
        .expect("still on the board");
    assert!(
        t.items.iter().find(|l| l.id == line_ids[0]).unwrap().bumped,
        "the bumped line greys at once"
    );
    within(15, "the POS holds a copy of the kitchen's bump", || async {
        (pos.pending_outbox_count().unwrap() > pos_pending_before).then_some(())
    })
    .await;

    // ── 4. Online again: both drain, the server has everything once ─────────
    net.restore();
    pos.refresh_connectivity().await;
    within(60, "both outboxes drain", || async {
        let _ = pos.sync_now().await;
        let _ = kitchen.sync_now().await;
        let pos_status = pos.sync_status();
        assert_eq!(
            pos_status.dead_outbox, 0,
            "nothing dead-lettered on the POS: {pos_status:?}"
        );
        (pos_status.pending_outbox == 0 && kitchen.state().pending == 0).then_some(())
    })
    .await;
    introduce.abort();

    let ticket_uuid = uuid::Uuid::parse_str(&fired.ticket_id).unwrap();
    let kts = db
        .query(
            "SELECT kt.id FROM kitchen_tickets kt JOIN open_tickets ot ON ot.id = kt.source_id \
             WHERE kt.source_type = 'open_ticket' AND ot.idempotency_key = $1",
            &[&ticket_uuid],
        )
        .await
        .unwrap();
    assert_eq!(kts.len(), 1, "one kitchen ticket for the round");
    let kt: uuid::Uuid = kts[0].get(0);
    let rows = db
        .query("SELECT id::text, bumped_at IS NOT NULL FROM kitchen_ticket_items WHERE kitchen_ticket_id = $1", &[&kt])
        .await
        .unwrap();
    let mut server: Vec<(String, bool)> = rows.iter().map(|r| (r.get(0), r.get(1))).collect();
    server.sort();
    let mut expected = vec![(line_ids[0].clone(), true), (line_ids[1].clone(), false)];
    expected.sort();
    assert_eq!(
        server, expected,
        "the server's lines are the ones the kitchen saw, bumped where it bumped"
    );
    assert_eq!(
        kt.to_string(),
        ticket.id,
        "the LAN ticket and the server's are one ticket"
    );

    let board = kitchen.tickets(None).await.unwrap();
    let showing: Vec<_> = board
        .iter()
        .filter(|t| t.items.iter().any(|l| line_ids.contains(&l.id)))
        .collect();
    assert_eq!(
        showing.len(),
        1,
        "the board shows the round once after the sync"
    );
    assert!(
        showing[0]
            .items
            .iter()
            .find(|l| l.id == line_ids[0])
            .unwrap()
            .bumped
    );

    pos.lan_stop();
    kitchen.lan_stop();
    let _ = std::fs::remove_dir_all(&dir);
}
