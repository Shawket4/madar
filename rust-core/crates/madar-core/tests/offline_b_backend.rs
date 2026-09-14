//! OFFLINE_B cross-repo integration: the REAL `MadarCore` against the REAL backend
//! (built from the backend worktree), through a proxy the test can cut to take
//! the device offline mid-session — the same core, the same store, no second
//! "dead-url" core standing in for the network going away.
//!
//! Ignored by default. Run against a THROWAWAY copy of a local DB (never the dev DB):
//!
//! ```sh
//! createdb -p 5432 -T madar_dash_tills madar_ob_it
//! DATABASE_URL=postgres://localhost:5432/madar_ob_it JWT_SECRET=it BIND_ADDR=127.0.0.1:8093 madar-rust &
//! MADAR_OB_BASE=http://127.0.0.1:8093 MADAR_OB_DB=postgres://localhost:5432/madar_ob_it \
//! MADAR_OB_BRANCH=<an active branch with a menu and a cash method> \
//!   cargo test -p madar-core --test offline_b_backend -- --ignored --nocapture --test-threads=1
//! ```
//!
//! What it proves:
//! * an offline till day (sales, a void, a refund of a synced sale, a pay-in, the
//!   close) computes the SAME figures locally as the server's Z report, before and
//!   after the backlog lands;
//! * two devices at one branch converge: each holds the other's till with the
//!   server's figures, from the changefeed alone;
//! * a 1000+ sale offline backlog drains completely, exactly once, and the
//!   device's report equals the server's afterwards.

use std::collections::BTreeMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use madar_core::checkout::CheckoutInput;
use madar_core::readpath::ReadPathMode;
use madar_core::session::{LoginMode, LoginRequest};
use madar_core::till::{ReconciliationInput, TillReportView};
use madar_core::{MadarConfig, MadarCore};
use tokio::io::AsyncWriteExt;
use tokio::sync::broadcast;

fn env(k: &str) -> String {
    std::env::var(k).unwrap_or_else(|_| panic!("set {k} (see the module docs)"))
}

// ---------------------------------------------------------------------------
// A TCP proxy with a network cable.

struct Proxy {
    base: String,
    online: Arc<AtomicBool>,
    cut: broadcast::Sender<()>,
}

impl Proxy {
    async fn start(upstream: &str) -> Proxy {
        let upstream = upstream.trim_start_matches("http://").to_string();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let online = Arc::new(AtomicBool::new(true));
        let (cut, _) = broadcast::channel::<()>(4);
        let (on, cut_tx) = (online.clone(), cut.clone());
        tokio::spawn(async move {
            loop {
                let Ok((mut client, _)) = listener.accept().await else { return };
                if !on.load(Ordering::SeqCst) {
                    let _ = client.shutdown().await;
                    continue;
                }
                let upstream = upstream.clone();
                let mut cut_rx = cut_tx.subscribe();
                tokio::spawn(async move {
                    let Ok(server) = tokio::net::TcpStream::connect(&upstream).await else { return };
                    let (mut cr, mut cw) = client.into_split();
                    let (mut sr, mut sw) = server.into_split();
                    let up = async move {
                        use tokio::io::AsyncReadExt;
                        let mut buf = vec![0u8; 65536];
                        loop {
                            let n = match cr.read(&mut buf).await {
                                Ok(0) | Err(_) => break,
                                Ok(n) => n,
                            };
                            if std::env::var("MADAR_OB_TRACE").is_ok() {
                                for line in String::from_utf8_lossy(&buf[..n]).lines() {
                                    if line.ends_with(" HTTP/1.1") {
                                        eprintln!("PROXY {line}");
                                    }
                                }
                            }
                            if sw.write_all(&buf[..n]).await.is_err() {
                                break;
                            }
                        }
                        let _ = sw.shutdown().await;
                    };
                    let down = async move {
                        let _ = tokio::io::copy(&mut sr, &mut cw).await;
                        let _ = cw.shutdown().await;
                    };
                    tokio::select! {
                        _ = async { tokio::join!(up, down) } => {}
                        _ = cut_rx.recv() => {}
                    }
                });
            }
        });
        Proxy { base, online, cut }
    }

    /// Pull the cable: new connections are refused and live ones (the SSE
    /// stream, a keep-alive socket) drop.
    fn offline(&self) {
        self.online.store(false, Ordering::SeqCst);
        let _ = self.cut.send(());
    }

    fn online(&self) {
        self.online.store(true, Ordering::SeqCst);
    }
}

// ---------------------------------------------------------------------------
// Fixture: tellers provisioned in the throwaway DB.

struct Fixture {
    base: String,
    branch: String,
    db: tokio_postgres::Client,
    tellers: Vec<(uuid::Uuid, String)>,
}

async fn fixture(tellers: usize) -> Fixture {
    let (db, conn) = tokio_postgres::connect(&env("MADAR_OB_DB"), tokio_postgres::NoTls)
        .await
        .expect("connect the throwaway DB");
    tokio::spawn(async move {
        let _ = conn.await;
    });
    let branch = env("MADAR_OB_BRANCH");
    let branch_uuid = uuid::Uuid::parse_str(&branch).unwrap();
    let org: uuid::Uuid = db
        .query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch_uuid])
        .await
        .expect("the branch exists")
        .get(0);
    // A branch that restricts its methods gets the org's first card-like method
    // too, so a day mixes a cash and a non-cash line.
    db.execute(
        "INSERT INTO branch_payment_methods (branch_id, payment_method_id, org_id)
         SELECT $1, m.id, m.org_id FROM org_payment_methods m
          WHERE m.org_id = $2 AND m.is_active AND NOT m.is_cash
            AND EXISTS (SELECT 1 FROM branch_payment_methods WHERE branch_id = $1)
            AND NOT EXISTS (SELECT 1 FROM branch_payment_methods b JOIN org_payment_methods o ON o.id = b.payment_method_id
                             WHERE b.branch_id = $1 AND NOT o.is_cash)
          ORDER BY m.created_at LIMIT 1",
        &[&branch_uuid, &org],
    )
    .await
    .expect("branch methods");
    let mut out = Vec::new();
    for _ in 0..tellers {
        let id = uuid::Uuid::new_v4();
        let name = format!("OB-{}", &id.simple().to_string()[..8]);
        db.execute(
            "INSERT INTO users (id, org_id, name, role, pin_hash)
             VALUES ($1, $2, $3, 'teller'::public.user_role, crypt('1234', gen_salt('bf', 4)))",
            &[&id, &org, &name],
        )
        .await
        .expect("insert teller");
        out.push((id, name));
    }
    Fixture { base: env("MADAR_OB_BASE"), branch, db, tellers: out }
}

async fn core_at(base: &str, db_path: &str, teller: &str, branch: &str) -> Arc<MadarCore> {
    let core = MadarCore::new(MadarConfig {
        base_url: base.to_string(),
        environment: "dev".into(),
        db_path: db_path.to_string(),
        locale: "en".into(),
        app_version: None,
    })
    .expect("core");
    // Sign-in is keyed on the address by the server's limiter, which every
    // core in this process shares (and asset downloads spend): a paced sign-in
    // is retried the way a teller would, after a moment.
    let deadline = Instant::now() + Duration::from_secs(120);
    let s = loop {
        match core
            .sign_in(LoginRequest {
                mode: LoginMode::Pin,
                name: Some(teller.to_string()),
                pin: Some("1234".into()),
                branch_id: Some(branch.to_string()),
                email: None,
                password: None,
                org_id: None,
            })
            .await
        {
            Err(madar_core::error::CoreError::Server { status: 429, .. }) if Instant::now() < deadline => {
                tokio::time::sleep(Duration::from_secs(3)).await;
            }
            other => break other.expect("sign in"),
        }
    };
    assert!(s.online, "the first sign-in reaches the backend");
    core.refresh_connectivity().await;
    core.refresh_catalog().await.expect("catalog");
    core.sync_full().await.expect("first snapshot");
    core
}

fn temp_db(tag: &str) -> String {
    std::env::temp_dir()
        .join(format!("madar_ob_it_{tag}_{}.sqlite", uuid::Uuid::new_v4().simple()))
        .to_string_lossy()
        .into_owned()
}

fn method(core: &MadarCore, cash: bool) -> Option<String> {
    core.available_payment_methods()
        .expect("methods")
        .into_iter()
        .find(|p| p.is_cash == cash)
        .map(|p| p.id)
}

async fn sell(core: &MadarCore, qty: usize, method_id: &str, tendered: i64) -> String {
    let item = core
        .list_menu_items()
        .expect("items")
        .into_iter()
        .find(|i| i.base_price_minor > 0)
        .expect("a priced menu item");
    for _ in 0..qty {
        core.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor).expect("add");
    }
    let r = core
        .checkout(
            None,
            CheckoutInput {
                payment_method_id: method_id.to_string(),
                amount_tendered_minor: tendered,
                tip_minor: 0,
                tip_payment_method_id: None,
                customer_name: None,
                notes: None,
                splits: vec![],
                loyalty_customer_id: None,
                loyalty_redemptions: vec![],
            },
        )
        .await
        .expect("checkout");
    r.local_order_id
}

/// Drain + pull until the queue is empty, within `max_secs`. The server paces a
/// client (429) past its burst; the core waits that out by itself, so this
/// only polls — slowly, so the polling is not what gets paced.
async fn settle(core: &MadarCore, max_secs: u64) {
    let deadline = Instant::now() + Duration::from_secs(max_secs);
    loop {
        let s = core.sync_now().await.expect("sync");
        assert_eq!(s.dead_outbox, 0, "nothing dead-letters: {s:?}");
        if s.pending_outbox == 0 {
            // Pull until the feed confirms what the drain landed (a pull may be
            // paced too).
            for _ in 0..20 {
                let s = core.sync_now().await.expect("sync");
                if s.freshness.state == "fresh" {
                    return;
                }
                tokio::time::sleep(Duration::from_millis(1_500)).await;
            }
            panic!("the feed never confirmed: {:?}", core.sync_status());
        }
        assert!(Instant::now() < deadline, "the queue did not drain: {s:?}");
        tokio::time::sleep(Duration::from_millis(1_000)).await;
    }
}

/// The figures a Z report states, keyed.
fn figures(r: &TillReportView) -> BTreeMap<String, i64> {
    let mut m = BTreeMap::new();
    for (k, v) in [
        ("expected_cash", r.expected_cash_minor),
        ("opening_cash", r.opening_cash_minor),
        ("total_payments", r.total_payments_minor),
        ("net_payments", r.net_payments_minor),
        ("voided", r.voided_amount_minor),
        ("refunds_issued", r.refunds_issued_minor),
        ("refunds_issued_cash", r.refunds_issued_cash_minor),
        ("refunds_issued_count", r.refunds_issued_count),
        ("cash_in_refunded_sales", r.cash_in_refunded_sales_minor),
        ("cash_movements_net", r.cash_movements_net_minor),
        ("cash_in", r.cash_in_minor),
        ("cash_out", r.cash_out_minor),
        ("closing_declared", r.closing_cash_declared_minor.unwrap_or(-1)),
    ] {
        m.insert(k.to_string(), v);
    }
    for l in &r.payment_lines {
        m.insert(format!("line:{}:total", l.method), l.total_minor);
        m.insert(format!("line:{}:count", l.method), l.order_count);
    }
    m
}

/// The server's report for a till: a fresh device on the legacy read path
/// (which asks the server) — independent of anything the device under test holds.
async fn server_report(fx: &Fixture, teller: &str, till_id: &str) -> TillReportView {
    let probe = core_at(&fx.base, "", teller, &fx.branch).await;
    probe.set_read_path_mode("ledger".into(), ReadPathMode::Legacy).unwrap();
    // The probe shares the teller's pacing bucket with the device under test;
    // a paced read falls back to a local figure, so ask again after a moment.
    for attempt in 0..40 {
        let r = probe.till_report_for(till_id.to_string()).await.expect("server report");
        if r.from_server {
            return r;
        }
        eprintln!("server report attempt {attempt}: not from the server yet");
        tokio::time::sleep(Duration::from_secs(3)).await;
    }
    panic!("the probe never read the server's report for {till_id}");
}

async fn server_orders_on_till(fx: &Fixture, till_id: &str) -> i64 {
    fx.db
        .query_one(
            "SELECT COUNT(*) FROM orders WHERE till_id = $1",
            &[&uuid::Uuid::parse_str(till_id).unwrap()],
        )
        .await
        .unwrap()
        .get(0)
}

async fn close_with_count(core: &MadarCore) -> TillReportView {
    let preview = core.close_till_preview().await.expect("preview");
    let recon = preview
        .methods
        .iter()
        .filter(|m| !m.is_cash)
        .map(|m| ReconciliationInput {
            method: m.method.clone(),
            status: "checked".into(),
            declared_amount_minor: Some(m.system_total_minor),
            note: None,
        })
        .collect();
    let before = core.till_report().await.expect("report before close");
    core.close_till(preview.expected_cash_minor, None, recon).await.expect("close");
    before
}

// ---------------------------------------------------------------------------

#[tokio::test]
#[ignore]
async fn an_offline_till_day_reports_what_the_server_reports() {
    let fx = fixture(1).await;
    let teller = fx.tellers[0].1.clone();
    let proxy = Proxy::start(&fx.base).await;
    let db = temp_db("day");
    let core = core_at(&proxy.base, &db, &teller, &fx.branch).await;

    let opened = core.open_till(10_000, Some("offline-b integration".into())).await.expect("open");
    let till_id = opened.till.expect("a till").id;
    let cash = method(&core, true).expect("a cash method");
    let card = method(&core, false);

    // Online: one sale that lands, so there is a synced sale to refund later.
    sell(&core, 2, &cash, 1_000_000).await;
    settle(&core, 120).await;
    let synced = core
        .list_till_orders()
        .await
        .expect("orders")
        .into_iter()
        .find(|o| !o.queued)
        .expect("the online sale is on the till");

    // Offline.
    proxy.offline();
    for _ in 0..3 {
        core.refresh_connectivity().await;
    }
    let voided = sell(&core, 1, &cash, 1_000_000).await;
    sell(&core, 3, &cash, 1_000_000).await;
    if let Some(card) = &card {
        sell(&core, 2, card, 0).await;
    }
    core.void_order(voided, "customer_changed_mind".into(), None, false).await.expect("void queues");
    core.refund_order(synced.id.clone(), synced.total_minor / 2, "cash".into(), "damaged".into(), None)
        .await
        .expect("refund queues");
    core.record_cash_movement(1_500, "float top-up".into(), Some("pay_in".into()), None)
        .await
        .expect("pay-in queues");
    let status = core.sync_status();
    assert!(!status.online, "the device knows it is offline: {status:?}");
    assert!(status.pending_outbox >= 5, "the day is queued: {status:?}");
    assert_eq!(status.dead_outbox, 0);
    let offline_open = figures(&core.till_report().await.expect("offline report"));
    let before_close = close_with_count(&core).await;
    assert_eq!(figures(&before_close), offline_open);

    // Back online: the backlog lands exactly once.
    proxy.online();
    core.refresh_connectivity().await;
    settle(&core, 120).await;
    let s = core.sync_status();
    assert_eq!((s.pending_outbox, s.dead_outbox), (0, 0), "{s:?}");

    let local = core.till_report_for(till_id.clone()).await.expect("local report");
    let server = server_report(&fx, &teller, &till_id).await;
    let mut want = figures(&server);
    eprintln!("DAY server figures: {want:?}");
    assert_eq!(figures(&local), want, "the device's closed-till report is the server's");
    // Before the close the drawer said what the server now says (bar the count).
    want.insert("closing_declared".into(), -1);
    assert_eq!(offline_open, want, "the offline figures were already right");
    assert!(!server.is_open);
    let expected_orders = if card.is_some() { 4 } else { 3 };
    assert_eq!(server_orders_on_till(&fx, &till_id).await, expected_orders, "no sale landed twice");
    let _ = std::fs::remove_file(&db);
}

#[tokio::test]
#[ignore]
async fn two_devices_converge_on_each_others_tills() {
    let fx = fixture(2).await;
    let (ta, tb) = (fx.tellers[0].1.clone(), fx.tellers[1].1.clone());
    let (pa, pb) = (Proxy::start(&fx.base).await, Proxy::start(&fx.base).await);
    let (da, dbp) = (temp_db("a"), temp_db("b"));
    let a = core_at(&pa.base, &da, &ta, &fx.branch).await;
    let b = core_at(&pb.base, &dbp, &tb, &fx.branch).await;

    let till_a = a.open_till(5_000, Some("device A".into())).await.unwrap().till.unwrap().id;
    let till_b = b.open_till(7_000, Some("device B".into())).await.unwrap().till.unwrap().id;
    let cash = method(&a, true).unwrap();

    // Both go offline and trade; A also pays out.
    pa.offline();
    pb.offline();
    for _ in 0..3 {
        a.refresh_connectivity().await;
        b.refresh_connectivity().await;
    }
    for _ in 0..4 {
        sell(&a, 1, &cash, 1_000_000).await;
    }
    for _ in 0..6 {
        sell(&b, 2, &cash, 1_000_000).await;
    }
    a.record_cash_movement(-800, "change run".into(), Some("pay_out".into()), None).await.unwrap();

    // Each device's own drawer is right before anyone reconnects.
    let a_offline = figures(&a.till_report().await.unwrap());
    let b_offline = figures(&b.till_report().await.unwrap());

    // B comes back first, then A; then each pulls again to see the other.
    pb.online();
    b.refresh_connectivity().await;
    settle(&b, 120).await;
    pa.online();
    a.refresh_connectivity().await;
    settle(&a, 120).await;
    settle(&b, 120).await;

    let srv_a = figures(&server_report(&fx, &ta, &till_a).await);
    let srv_b = figures(&server_report(&fx, &tb, &till_b).await);
    assert_eq!(a_offline, srv_a, "A's offline drawer");
    assert_eq!(b_offline, srv_b, "B's offline drawer");
    assert_eq!(figures(&a.till_report_for(till_b.clone()).await.unwrap()), srv_b, "A holds B's till");
    assert_eq!(figures(&b.till_report_for(till_a.clone()).await.unwrap()), srv_a, "B holds A's till");
    let a_tills: Vec<String> = a.list_tills().await.unwrap().into_iter().map(|t| t.id).collect();
    assert!(a_tills.contains(&till_b), "B's till is in A's list");

    // Close both; the closes cross over too.
    close_with_count(&a).await;
    close_with_count(&b).await;
    settle(&a, 120).await;
    settle(&b, 120).await;
    settle(&a, 120).await;
    let srv_b = figures(&server_report(&fx, &tb, &till_b).await);
    assert_eq!(figures(&a.till_report_for(till_b).await.unwrap()), srv_b, "A holds B's closed till");
    let _ = std::fs::remove_file(&da);
    let _ = std::fs::remove_file(&dbp);
}

#[tokio::test]
#[ignore]
async fn a_thousand_sale_backlog_drains_exactly_once() {
    const N: usize = 1_000;
    let fx = fixture(1).await;
    let teller = fx.tellers[0].1.clone();
    let proxy = Proxy::start(&fx.base).await;
    let db = temp_db("backlog");
    let core = core_at(&proxy.base, &db, &teller, &fx.branch).await;
    let till_id = core.open_till(20_000, Some("backlog".into())).await.unwrap().till.unwrap().id;
    let cash = method(&core, true).unwrap();

    proxy.offline();
    for _ in 0..3 {
        core.refresh_connectivity().await;
    }
    let t0 = Instant::now();
    for _ in 0..N {
        sell(&core, 1, &cash, 1_000_000).await;
    }
    let ring = t0.elapsed();
    core.record_cash_movement(2_500, "mid-day float".into(), Some("pay_in".into()), None).await.unwrap();
    let s = core.sync_status();
    assert!(!s.online);
    assert!(s.pending_outbox as usize > N, "{s:?}");
    let t0 = Instant::now();
    let offline_report = figures(&core.till_report().await.unwrap());
    let report_ms = t0.elapsed();

    proxy.online();
    core.refresh_connectivity().await;
    let t0 = Instant::now();
    settle(&core, 900).await;
    let drain = t0.elapsed();
    let s = core.sync_status();
    assert_eq!((s.pending_outbox, s.dead_outbox), (0, 0), "{s:?}");
    assert!(s.freshness.state == "fresh", "{s:?}");

    assert_eq!(server_orders_on_till(&fx, &till_id).await, N as i64, "every sale exactly once");
    let server = figures(&server_report(&fx, &teller, &till_id).await);
    assert_eq!(offline_report, server, "the offline drawer with 1000 queued sales was the server's");
    assert_eq!(figures(&core.till_report().await.unwrap()), server, "and still is after the drain");
    eprintln!(
        "BACKLOG N={N}: ring {:.1}s ({:.1} ms/sale), offline report {} ms, drain+confirm {:.1}s",
        ring.as_secs_f64(),
        ring.as_secs_f64() * 1000.0 / N as f64,
        report_ms.as_millis(),
        drain.as_secs_f64()
    );
    let _ = tokio::time::timeout(Duration::from_secs(1), close_with_count(&core)).await;
    let _ = std::fs::remove_file(&db);
}
