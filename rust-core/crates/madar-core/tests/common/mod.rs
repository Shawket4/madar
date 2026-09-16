//! Shared real-backend fixture for the ignored integration suites
//! (`offline_b_backend.rs`, `readpath_parity.rs`): a TCP proxy with a cable,
//! provisioned tellers, signed-in cores and the day's helpers.
#![allow(dead_code)]

use std::collections::BTreeMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use madar_core::checkout::CheckoutInput;
use madar_core::session::{LoginMode, LoginRequest};
use madar_core::till::{ReconciliationInput, TillReportView};
use madar_core::{MadarConfig, MadarCore};
use tokio::io::AsyncWriteExt;
use tokio::sync::broadcast;

pub fn env(k: &str) -> String {
    std::env::var(k).unwrap_or_else(|_| panic!("set {k} (see the module docs)"))
}

// ---------------------------------------------------------------------------
// Request counting: every request line any proxy forwards, by route.

static REQUESTS: std::sync::Mutex<BTreeMap<String, usize>> = std::sync::Mutex::new(BTreeMap::new());

/// `GET /tills/0b1e…/report?x=1 HTTP/1.1` → `GET /tills/:id/report`.
pub fn route_of(line: &str) -> String {
    let mut parts = line.split_whitespace();
    let method = parts.next().unwrap_or("");
    let path = parts.next().unwrap_or("").split('?').next().unwrap_or("");
    let path: Vec<String> = path
        .split('/')
        .map(|seg| {
            if uuid::Uuid::parse_str(seg).is_ok() || (!seg.is_empty() && seg.chars().all(|c| c.is_ascii_digit())) {
                ":id".to_string()
            } else {
                seg.to_string()
            }
        })
        .collect();
    format!("{method} {}", path.join("/"))
}

static RAW_REQUESTS: std::sync::Mutex<BTreeMap<String, usize>> = std::sync::Mutex::new(BTreeMap::new());

fn count_request(line: &str) {
    *REQUESTS.lock().unwrap().entry(route_of(line)).or_default() += 1;
    let mut parts = line.split_whitespace();
    let raw = format!("{} {}", parts.next().unwrap_or(""), parts.next().unwrap_or(""));
    *RAW_REQUESTS.lock().unwrap().entry(raw).or_default() += 1;
}

/// The exact requests (method, path and query) counted since the last call.
pub fn take_raw_requests() -> BTreeMap<String, usize> {
    std::mem::take(&mut *RAW_REQUESTS.lock().unwrap())
}

/// The requests counted since the last call, by route; the counter restarts.
pub fn take_requests() -> BTreeMap<String, usize> {
    std::mem::take(&mut *REQUESTS.lock().unwrap())
}

// ---------------------------------------------------------------------------
// A TCP proxy with a network cable.

pub struct Proxy {
    pub base: String,
    pub online: Arc<AtomicBool>,
    /// A flaky link: connections are accepted and never answered.
    pub hang: Arc<AtomicBool>,
    pub cut: broadcast::Sender<()>,
}

impl Proxy {
    pub async fn start(upstream: &str) -> Proxy {
        let upstream = upstream.trim_start_matches("http://").to_string();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let online = Arc::new(AtomicBool::new(true));
        let hang = Arc::new(AtomicBool::new(false));
        let (cut, _) = broadcast::channel::<()>(4);
        let (on, hung, cut_tx) = (online.clone(), hang.clone(), cut.clone());
        tokio::spawn(async move {
            let mut held = Vec::new();
            loop {
                let Ok((mut client, _)) = listener.accept().await else { return };
                if hung.load(Ordering::SeqCst) {
                    held.push(client);
                    continue;
                }
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
                            for line in String::from_utf8_lossy(&buf[..n]).lines() {
                                if line.ends_with(" HTTP/1.1") {
                                    count_request(line);
                                    if std::env::var("MADAR_OB_TRACE").is_ok() {
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
                        use tokio::io::AsyncReadExt;
                        let mut buf = vec![0u8; 65536];
                        loop {
                            let n = match sr.read(&mut buf).await {
                                Ok(0) | Err(_) => break,
                                Ok(n) => n,
                            };
                            if std::env::var("MADAR_OB_TRACE").is_ok() {
                                for line in String::from_utf8_lossy(&buf[..n]).lines() {
                                    if line.starts_with("HTTP/1.1 ") {
                                        eprintln!("PROXY <- {line}");
                                    }
                                }
                            }
                            if cw.write_all(&buf[..n]).await.is_err() {
                                break;
                            }
                        }
                        let _ = cw.shutdown().await;
                    };
                    tokio::select! {
                        _ = async { tokio::join!(up, down) } => {}
                        _ = cut_rx.recv() => {}
                    }
                });
            }
        });
        Proxy { base, online, hang, cut }
    }

    /// Pull the cable: new connections are refused and live ones (the SSE
    /// stream, a keep-alive socket) drop.
    pub fn offline(&self) {
        self.online.store(false, Ordering::SeqCst);
        let _ = self.cut.send(());
    }

    pub fn online(&self) {
        self.online.store(true, Ordering::SeqCst);
        self.hang.store(false, Ordering::SeqCst);
    }

    /// A link that hangs: live sockets drop, new ones are accepted and held
    /// without a byte in either direction.
    pub fn hanging(&self) {
        self.hang.store(true, Ordering::SeqCst);
        let _ = self.cut.send(());
    }
}

// ---------------------------------------------------------------------------
// Fixture: tellers provisioned in the throwaway DB.

pub struct Fixture {
    pub base: String,
    pub branch: String,
    pub db: tokio_postgres::Client,
    pub tellers: Vec<(uuid::Uuid, String)>,
}

pub async fn fixture(tellers: usize) -> Fixture {
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

pub async fn signed_in(base: &str, db_path: &str, teller: &str, branch: &str) -> Arc<MadarCore> {
    signed_in_pin(base, db_path, teller, branch, "1234").await
}

/// [`signed_in`] with a PIN other than the fixture's shared "1234".
pub async fn signed_in_pin(base: &str, db_path: &str, teller: &str, branch: &str, pin: &str) -> Arc<MadarCore> {
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
                pin: Some(pin.into()),
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
    assert!(s.online, "the first sign-in reaches the backend: {s:?}");
    core
}

pub async fn core_at(base: &str, db_path: &str, teller: &str, branch: &str) -> Arc<MadarCore> {
    let core = signed_in(base, db_path, teller, branch).await;
    core.refresh_connectivity().await;
    core.refresh_catalog().await.expect("catalog");
    core.sync_full().await.expect("first snapshot");
    core
}

pub fn temp_db(tag: &str) -> String {
    std::env::temp_dir()
        .join(format!("madar_ob_it_{tag}_{}.sqlite", uuid::Uuid::new_v4().simple()))
        .to_string_lossy()
        .into_owned()
}

pub fn method(core: &MadarCore, cash: bool) -> Option<String> {
    core.available_payment_methods()
        .expect("methods")
        .into_iter()
        .find(|p| p.is_cash == cash)
        .map(|p| p.id)
}

pub async fn sell(core: &MadarCore, qty: usize, method_id: &str, tendered: i64) -> String {
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
                dine_in: false,
                customer_id: None,
                loyalty_redemptions: vec![],
            },
        )
        .await
        .expect("checkout");
    r.local_order_id
}

/// Reconnected: let the core drain and confirm, within `max_secs`. One sync
/// starts it; after that the core's own scheduler drives (an ack nudges the next
/// pass, a 429 schedules its own resume) and the test only READS the local
/// status — polling the network here would spend the very allowance the server
/// paces the drain with.
pub async fn settle(core: &MadarCore, max_secs: u64) {
    let deadline = Instant::now() + Duration::from_secs(max_secs);
    let mut s = core.sync_now().await.expect("sync");
    let mut last_kick = Instant::now();
    loop {
        assert_eq!(s.dead_outbox, 0, "nothing dead-letters: {s:?}");
        if s.pending_outbox == 0 && s.freshness.state == "fresh" {
            return;
        }
        assert!(Instant::now() < deadline, "did not settle: {s:?}");
        tokio::time::sleep(Duration::from_millis(500)).await;
        // A settled queue whose confirming pull was paced gets one more pull,
        // no more often than a teller's sync button would.
        if s.pending_outbox == 0 && last_kick.elapsed() > Duration::from_secs(5) {
            core.sync_now().await.expect("sync");
            last_kick = Instant::now();
        }
        s = core.sync_status();
    }
}

/// The figures a Z report states, keyed.
pub fn figures(r: &TillReportView) -> BTreeMap<String, i64> {
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

/// The server's report for a till: a fresh device that holds none of the
/// till's rows, so its read serves the report its background fill fetched from
/// the server (`from_server`) — independent of anything the device under test
/// holds.
pub async fn server_report(fx: &Fixture, teller: &str, till_id: &str) -> TillReportView {
    let probe = signed_in(&fx.base, "", teller, &fx.branch).await;
    // The probe shares the teller's pacing bucket with the device under test;
    // a paced fill leaves nothing to serve yet, so ask again after a moment.
    for attempt in 0..60 {
        match probe.till_report_for(till_id.to_string()).await {
            Ok(r) if r.from_server => return r,
            other => eprintln!("server report attempt {attempt}: not from the server yet ({:?})", other.map(|r| r.from_server)),
        }
        tokio::time::sleep(Duration::from_secs(3)).await;
    }
    panic!("the probe never read the server's report for {till_id}");
}

pub async fn server_orders_on_till(fx: &Fixture, till_id: &str) -> i64 {
    fx.db
        .query_one(
            "SELECT COUNT(*) FROM orders WHERE till_id = $1",
            &[&uuid::Uuid::parse_str(till_id).unwrap()],
        )
        .await
        .unwrap()
        .get(0)
}

pub async fn close_with_count(core: &MadarCore) -> TillReportView {
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

