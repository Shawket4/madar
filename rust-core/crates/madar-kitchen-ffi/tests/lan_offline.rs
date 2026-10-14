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
//! `apps/kitchen/scripts/dev-kitchen-demo.py` (its sections, waiter and
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

/// What the POS app would show: every notification the core posts.
#[derive(Clone, Default)]
struct Shown(Arc<Mutex<Vec<(String, String)>>>);

impl madar_core::realtime::RealtimePlayer for Shown {
    fn play_ping(&self) {}
    fn post_notification(&self, title: String, body: String, _tag: String) {
        self.0.lock().unwrap().push((title, body));
    }
    fn haptic(&self) {}
}

struct Board;
impl madar_core::realtime::EventListener for Board {
    fn on_event(&self, _: madar_core::realtime::RealtimeEvent) {}
    fn on_connection_changed(&self, _: bool) {}
}

impl Shown {
    fn ready(&self) -> Vec<String> {
        self.0.lock().unwrap().iter().filter(|(t, _)| t == "Order ready").map(|(_, b)| b.clone()).collect()
    }
}

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
    // One uplink each, so the kitchen can come back before the POS.
    let (api, net) = switchable_proxy(upstream.clone()).await;
    let (pos_api, pos_net) = switchable_proxy(upstream).await;

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
    let branch_id: String = db
        .query_opt(
            "SELECT id::text FROM branches WHERE name = $1",
            &[&branch_name],
        )
        .await
        .unwrap()
        .unwrap_or_else(|| panic!("no branch named {branch_name} (run dev-kitchen-demo.py)"))
        .get(0);
    // Each device is set up the way the shop does it: an activation code from
    // the dashboard's branch plan. The kitchen has no account: the code is
    // its only sign-in.
    let mint = |kind: &'static str| {
        let (db, branch_id) = (&db, branch_id.clone());
        async move {
            let code = format!("{:08}", uuid::Uuid::new_v4().as_u128() % 100_000_000);
            db.execute(
                "INSERT INTO device_activation_codes (org_id, branch_id, code, kind) \
                 SELECT org_id, id, $2, $3 FROM branches WHERE id = $1::text::uuid",
                &[&branch_id, &code, &kind],
            )
            .await
            .expect("mint an activation code");
            code
        }
    };
    kitchen.activate(mint("kds").await).await.expect("activate the kitchen screen");
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
        base_url: pos_api,
        environment: "dev".into(),
        db_path: dir.join("pos.db").to_string_lossy().into(),
        locale: "en".into(),
        app_version: None,
    })
    .expect("pos core");
    pos.activate_device(mint("pos").await).await.expect("activate the POS");
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
    // The POS listens the way the app does: what it would notify lands in `shown`.
    let shown = Shown::default();
    pos.start_realtime(Box::new(Board), Box::new(shown.clone())).await.expect("listen");
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
    pos_net.cut();
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
    assert!(!shown.ready().contains(&format!("#{}", &ticket.id[ticket.id.len() - 4..].to_uppercase())), "one line still cooking: this order is not ready: {:?}", shown.0.lock().unwrap());

    // The bump that finishes the order tells the POS over the LAN, with no
    // internet: one local "Order ready", named like the kitchen's card.
    kitchen.bump(line_ids[1].clone()).await.expect("bump the last line offline");
    // No ref yet offline: the id's tail, as the kitchen's card shows it.
    let ours = format!("#{}", &ticket.id[ticket.id.len() - 4..].to_uppercase());
    within(15, "the POS hears this order is ready over the LAN", || async {
        shown.ready().contains(&ours).then_some(())
    })
    .await;

    // ── 4. Online again, one device after the other (`MADAR_FIRST`, default
    // the kitchen). Whatever the order, bumped lines never come back unbumped.
    let kitchen_first = env("MADAR_FIRST", "kitchen") == "kitchen";
    let still_bumped = || async {
        let board = kitchen.tickets(None).await.unwrap();
        for t in board.iter().filter(|t| t.items.iter().any(|l| line_ids.contains(&l.id))) {
            assert!(t.items.iter().all(|l| l.bumped), "a bumped line came back: {:?}", t.items.iter().map(|l| (&l.id, l.bumped)).collect::<Vec<_>>());
        }
    };
    if kitchen_first { net.restore() } else { pos_net.restore(); pos.refresh_connectivity().await; }
    for _ in 0..8 {
        if kitchen_first { let _ = kitchen.sync_now().await; } else { let _ = pos.sync_now().await; }
        still_bumped().await;
        tokio::time::sleep(Duration::from_millis(500)).await;
        still_bumped().await;
    }
    let ops: Vec<(String, String)> = rusqlite::Connection::open(dir.join("kitchen").join("madar.db"))
        .unwrap()
        .prepare("SELECT op_type, status FROM outbox ORDER BY seq")
        .unwrap()
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
        .unwrap()
        .map(Result::unwrap)
        .collect();
    eprintln!("KITCHEN OUTBOX: {ops:?}");
    assert!(ops.iter().all(|(_, st)| st != "dead"), "nothing of the kitchen's dead-lettered");
    net.restore();
    pos_net.restore();
    pos.refresh_connectivity().await;
    within(60, "both outboxes drain", || async {
        let _ = pos.sync_now().await;
        let _ = kitchen.sync_now().await;
        let pos_status = pos.sync_status();
        // Only the POS's OWN writes count. A `lan_mirror` is its backup of
        // another device's write: on a shop Wi-Fi with real devices of the same
        // branch (a dev database copied from production shares their branch and
        // LAN key) those belong to people this backend doesn't know.
        let own_dead: i64 = rusqlite::Connection::open(dir.join("pos.db"))
            .and_then(|c| c.query_row("SELECT count(*) FROM outbox WHERE status = 'dead' AND op_type <> 'lan_mirror'", [], |r| r.get(0)))
            .unwrap_or(-1);
        assert_eq!(own_dead, 0, "nothing of the POS's own dead-lettered: {pos_status:?}");
        still_bumped().await;
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
    let mut expected = vec![(line_ids[0].clone(), true), (line_ids[1].clone(), true)];
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

    // A finished round is closed by the server: it leaves the board, and its
    // LAN copy never comes back as a ghost with its lines unbumped.
    let _ = kitchen.sync_now().await;
    let board = kitchen.tickets(None).await.unwrap();
    let showing: Vec<_> = board.iter().filter(|t| t.items.iter().any(|l| line_ids.contains(&l.id))).collect();
    assert!(showing.is_empty(), "the finished round is gone, never a ghost: {} shown", showing.len());
    // The server's own kitchen.ticket_ready for the replayed bump is the same
    // alert as the LAN's: still one notification.
    tokio::time::sleep(Duration::from_secs(3)).await;
    assert_eq!(
        shown.ready().iter().filter(|b| **b == ours).count(),
        1,
        "one Order ready for this order, LAN and server together: {:?}",
        shown.ready()
    );

    pos.lan_stop();
    kitchen.lan_stop();
    let _ = std::fs::remove_dir_all(&dir);
}
