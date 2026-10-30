//! Teller pick ("Who's serving?") end to end: the REAL `MadarCore` against the
//! REAL backend, on a database seeded through the API (TELLER_PICK_SPEC_2026-10-30
//! §7, the walk).
//!
//! Ignored by `cargo test`. Seed the source database with the walk's seed script
//! (`~/work/tp-walk/seed.py`: a paid "Walk Cafe" with pos + dawam, an owner, a
//! branch manager, tellers Mona / Karim / Aya, waiter Omar, Mona and Karim linked
//! to Dawam employees, Aya not; and a Free "Free Kiosk" with one teller), then:
//!
//! ```sh
//! MADAR_TP_SEED=~/work/tp-walk/seed.json MADAR_OB_SOURCE_DB=tp_walk_src \
//!   MADAR_OB_BRANCH=<seed.json paid.branch_id> MADAR_OB_TESTS=teller_pick_backend \
//!   tool/offline_b_backend.sh
//! ```
//!
//! The paid walk is ONE test because each step stands on the one before (the
//! same device, the same till, the same clock-ins). Every check is recorded and
//! the walk goes on past a failed one, so one run reports every defect; the test
//! fails at the end with the list.
//!
//! 1. Switch on (owner PATCH), Mona and Karim punched in by the manager: the
//!    signed-in teller's picker is required + Focused, primary [Karim, Mona],
//!    more holds Aya, the manager and the owner; the waiter is nowhere.
//! 2. The gate: no `sold_by` is refused; `sold_by` = Mona lands with
//!    `sold_by_name` Mona and the signed-in teller as `teller_id`.
//! 3. Replay: a sale picked as Karim rung offline lands as Karim.
//! 4. A table's bill settled with `sold_by` = Karim lands as Karim.
//! 5. Mona punched out: primary [Karim], Mona under More.
//! 6. The till's local `by_person` is the server's (`GET /tills/{id}/report`).
//! 7. Switch off: not required, a sale without `sold_by` lands with it null.
//!
//! The Free org is its own test: switch on, its teller's picker is All and no
//! teller row carries a clock-in.

mod common;

use common::*;
use madar_core::checkout::{CheckoutInput, ReceiptView};
use madar_core::error::CoreError;
use madar_core::teller_pick::{PickMode, PickPerson, TellerPick, SOLD_BY_MISSING};
use madar_core::MadarCore;
use serde_json::{json, Value};
use std::sync::Arc;
use std::time::{Duration, Instant};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// The seed (seed.json from the walk's seed script).

struct Seed(Value);

impl Seed {
    fn load() -> Seed {
        let path = env("MADAR_TP_SEED");
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
        Seed(serde_json::from_str(&text).expect("seed.json"))
    }
    fn s(&self, ptr: &str) -> String {
        self.0
            .pointer(ptr)
            .and_then(Value::as_str)
            .unwrap_or_else(|| panic!("seed.json has no {ptr}"))
            .to_string()
    }
}

// ---------------------------------------------------------------------------
// The owner's / manager's API, as the dashboard calls it.

fn http() -> reqwest::Client {
    let _ = rustls::crypto::ring::default_provider().install_default();
    reqwest::Client::new()
}

async fn call(
    base: &str,
    token: &str,
    method: reqwest::Method,
    path: &str,
    body: Option<Value>,
) -> (u16, Value) {
    let mut r = http()
        .request(method, format!("{base}{path}"))
        .bearer_auth(token);
    if let Some(b) = body {
        r = r.json(&b);
    }
    let res = r.send().await.expect("request");
    let status = res.status().as_u16();
    let text = res.text().await.unwrap_or_default();
    (
        status,
        serde_json::from_str(&text).unwrap_or(Value::String(text)),
    )
}

/// Email sign-in; the login limiter is per address, so a 429 waits and retries.
async fn login(base: &str, email: &str, password: &str) -> String {
    let deadline = Instant::now() + Duration::from_secs(120);
    loop {
        let (s, v) = call(
            base,
            "",
            reqwest::Method::POST,
            "/auth/login",
            Some(json!({ "email": email, "password": password })),
        )
        .await;
        if s == 429 && Instant::now() < deadline {
            tokio::time::sleep(Duration::from_secs(3)).await;
            continue;
        }
        assert_eq!(s, 200, "login {email}: {v}");
        return v["token"].as_str().unwrap().to_string();
    }
}

async fn set_switch(base: &str, owner: &str, branch: &str, on: bool) -> (u16, Value) {
    let r = call(
        base,
        owner,
        reqwest::Method::PATCH,
        &format!("/branches/{branch}"),
        Some(json!({ "pick_teller_at_checkout": on })),
    )
    .await;
    eprintln!(
        "PATCH /branches/{branch} pick_teller_at_checkout={on} -> {} {}",
        r.0,
        r.1.get("pick_teller_at_checkout").unwrap_or(&Value::Null)
    );
    r
}

/// A manager's punch for someone (in, or out when they are in).
async fn punch(base: &str, manager: &str, employee: &str, reason: &str) -> (u16, Value) {
    let r = call(
        base,
        manager,
        reqwest::Method::POST,
        "/staff/attendance/punch",
        Some(json!({ "employee_id": employee, "reason": reason })),
    )
    .await;
    eprintln!(
        "POST /staff/attendance/punch {employee} -> {} check_in={} check_out={} branch={}",
        r.0,
        r.1.get("check_in_at").unwrap_or(&Value::Null),
        r.1.get("check_out_at").unwrap_or(&Value::Null),
        r.1.get("branch_id").unwrap_or(&Value::Null)
    );
    r
}

// ---------------------------------------------------------------------------
// The device.

async fn device(base: &str, db: &str, name: &str, pin: &str, branch: &str) -> Arc<MadarCore> {
    let core = signed_in_pin(base, db, name, branch, pin).await;
    core.refresh_connectivity().await;
    core.refresh_catalog().await.expect("catalog");
    core.sync_full().await.expect("first snapshot");
    core
}

fn names(people: &[PickPerson]) -> Vec<String> {
    people.iter().map(|p| p.name.clone()).collect()
}

fn show(p: &TellerPick) -> String {
    format!(
        "required={} mode={:?} primary={:?} more={:?}",
        p.required,
        p.mode,
        p.primary
            .iter()
            .map(|x| (x.name.as_str(), x.on_shift_since.as_deref()))
            .collect::<Vec<_>>(),
        p.more
            .iter()
            .map(|x| (x.name.as_str(), x.on_shift_since.as_deref()))
            .collect::<Vec<_>>(),
    )
}

/// The device's own `teller` feed rows for its branch, as pulled.
fn teller_rows(db: &str, branch: &str) -> Vec<Value> {
    let c = rusqlite::Connection::open(db).expect("open the device db");
    let mut st = c
        .prepare("SELECT data FROM sync_rows WHERE type = 'teller' AND branch_id = ?1")
        .unwrap();
    let rows = st
        .query_map([branch], |r| r.get::<_, String>(0))
        .unwrap()
        .filter_map(Result::ok)
        .filter_map(|s| serde_json::from_str(&s).ok())
        .collect();
    rows
}

fn input(method: &str, tip: i64, sold_by: Option<&str>) -> CheckoutInput {
    CheckoutInput {
        sold_by: sold_by.map(str::to_string),
        payment_method_id: method.to_string(),
        amount_tendered_minor: 1_000_000,
        tip_minor: tip,
        tip_payment_method_id: None,
        customer_name: None,
        notes: None,
        splits: vec![],
        loyalty_customer_id: None,
        dine_in: false,
        customer_id: None,
        loyalty_redemptions: vec![],
    }
}

fn add_item(core: &MadarCore, table: Option<String>) {
    let item = core
        .list_menu_items()
        .expect("items")
        .into_iter()
        .find(|i| i.base_price_minor > 0)
        .expect("a priced menu item");
    core.cart_add(
        table,
        item.id.clone(),
        item.name.clone(),
        item.base_price_minor,
    )
    .expect("add");
}

async fn server_order_by(fx: &Fixture, sql: &str, key: &str) -> Option<Uuid> {
    fx.db
        .query_opt(sql, &[&key.to_string()])
        .await
        .unwrap()
        .map(|r| r.get(0))
}

// ---------------------------------------------------------------------------
// Recording checks: the walk goes on past a failure and reports them all.

#[derive(Default)]
struct Walk {
    fails: Vec<String>,
}

impl Walk {
    fn check(&mut self, scenario: &str, ok: bool, what: impl Into<String>) -> bool {
        let what = what.into();
        if ok {
            eprintln!("ok   [{scenario}] {what}");
        } else {
            eprintln!("FAIL [{scenario}] {what}");
            self.fails.push(format!("[{scenario}] {what}"));
        }
        ok
    }
    fn eq<T: PartialEq + std::fmt::Debug>(
        &mut self,
        scenario: &str,
        what: &str,
        got: T,
        want: T,
    ) -> bool {
        let ok = got == want;
        self.check(scenario, ok, format!("{what}: got {got:?}, want {want:?}"))
    }
}

/// The server's view of one order (`GET /orders/{id}`).
async fn order_json(base: &str, token: &str, id: Uuid) -> Value {
    let (s, v) = call(
        base,
        token,
        reqwest::Method::GET,
        &format!("/orders/{id}"),
        None,
    )
    .await;
    assert_eq!(s, 200, "GET /orders/{id}: {v}");
    v
}

fn person_lines_local(
    r: &madar_core::till::TillReportView,
) -> Vec<(Option<String>, String, i64, i64, i64)> {
    let mut v: Vec<_> = r
        .by_person
        .iter()
        .map(|p| {
            (
                p.person_id.clone(),
                p.name.clone(),
                p.order_count,
                p.total_minor,
                p.tips_minor,
            )
        })
        .collect();
    v.sort();
    v
}

fn person_lines_server(report: &Value) -> Vec<(Option<String>, String, i64, i64, i64)> {
    let mut v: Vec<_> = report["by_person"]
        .as_array()
        .map(|a| {
            a.iter()
                .map(|p| {
                    (
                        p["person_id"].as_str().map(str::to_string),
                        p["name"]
                            .as_str()
                            .unwrap_or(madar_core::till::UNKNOWN_PERSON)
                            .to_string(),
                        p["order_count"].as_i64().unwrap_or(-1),
                        p["total"].as_i64().unwrap_or(-1),
                        p["tips"].as_i64().unwrap_or(-1),
                    )
                })
                .collect()
        })
        .unwrap_or_default();
    v.sort();
    v
}

// ---------------------------------------------------------------------------

#[tokio::test]
#[ignore]
async fn the_paid_branch_asks_whos_serving_end_to_end() {
    let seed = Seed::load();
    let fx = fixture(0).await;
    let base = fx.base.clone();
    let branch = fx.branch.clone();
    assert_eq!(
        branch,
        seed.s("/paid/branch_id"),
        "MADAR_OB_BRANCH is the seed's paid branch"
    );
    let mona = seed.s("/paid/tellers/Mona/id");
    let karim = seed.s("/paid/tellers/Karim/id");
    let aya = seed.s("/paid/tellers/Aya/id");
    let manager_name = seed.s("/paid/manager/name");
    let owner_name = seed.s("/paid/owner/name");
    let waiter_name = seed.s("/paid/waiter/name");
    let owner = login(
        &base,
        &seed.s("/paid/owner/email"),
        &seed.s("/paid/owner/password"),
    )
    .await;
    let manager = login(
        &base,
        &seed.s("/paid/manager/email"),
        &seed.s("/paid/manager/password"),
    )
    .await;
    let mut w = Walk::default();

    // ── 1. Switch on ─────────────────────────────────────────────────────
    let sc = "1 switch on";
    let (st, v) = set_switch(&base, &owner, &branch, true).await;
    w.check(
        sc,
        (200..300).contains(&st),
        format!("owner PATCH switch on -> {st}"),
    );
    w.eq(
        sc,
        "PATCH answer's pick_teller_at_checkout",
        v.get("pick_teller_at_checkout").cloned(),
        Some(json!(true)),
    );
    for who in ["Mona", "Karim"] {
        let (st, v) = punch(
            &base,
            &manager,
            &seed.s(&format!("/paid/employees/{who}")),
            "walk: clock in",
        )
        .await;
        w.check(
            sc,
            st == 200 && v["check_out_at"].is_null(),
            format!("manager punches {who} in -> {st} {v}"),
        );
    }
    let proxy = Proxy::start(&base).await;
    let db = temp_db("tp");
    let core = device(
        &proxy.base,
        &db,
        "Aya",
        &seed.s("/paid/tellers/Aya/pin"),
        &branch,
    )
    .await;
    let till_id = core
        .open_till(10_000, Some("teller pick walk".into()))
        .await
        .expect("open")
        .till
        .expect("a till")
        .id;
    let cash = method(&core, true).expect("a cash method");
    core.sync_now().await.expect("pull");
    let p = core.teller_pick();
    eprintln!("PICK after clock-ins: {}", show(&p));
    for r in teller_rows(&db, &branch) {
        eprintln!(
            "  teller row: {} on_shift_since={} caps.orders.create={}",
            r["name"],
            r.get("on_shift_since").unwrap_or(&Value::Null),
            r["capabilities"]
                .as_array()
                .is_some_and(|c| c.iter().any(|x| x == "orders.create"))
        );
    }
    w.check(sc, p.required, "required");
    w.eq(sc, "mode", p.mode, PickMode::Focused);
    w.eq(
        sc,
        "primary by name",
        names(&p.primary),
        vec!["Karim".to_string(), "Mona".to_string()],
    );
    let more = names(&p.more);
    for want in ["Aya".to_string(), manager_name.clone(), owner_name.clone()] {
        w.check(
            sc,
            more.contains(&want),
            format!("more holds {want}: {more:?}"),
        );
    }
    let everyone: Vec<String> = names(&p.primary).into_iter().chain(more.clone()).collect();
    w.check(
        sc,
        !everyone.contains(&waiter_name),
        format!("the waiter {waiter_name} is nowhere: {everyone:?}"),
    );
    let rows = teller_rows(&db, &branch);
    let since = |id: &str| {
        rows.iter()
            .find(|r| r["id"].as_str() == Some(id) || r["user_id"].as_str() == Some(id))
            .map(|r| r.get("on_shift_since").cloned().unwrap_or(Value::Null))
    };
    w.check(
        sc,
        since(&mona).is_some_and(|v| v.is_string()),
        format!("Mona's feed row has on_shift_since: {:?}", since(&mona)),
    );
    w.check(
        sc,
        since(&karim).is_some_and(|v| v.is_string()),
        format!("Karim's feed row has on_shift_since: {:?}", since(&karim)),
    );
    w.check(
        sc,
        since(&aya).is_some_and(|v| v.is_null()),
        format!("Aya's feed row has none: {:?}", since(&aya)),
    );

    // ── 2. The gate ──────────────────────────────────────────────────────
    let sc = "2 gate";
    add_item(&core, None);
    let refused = core.checkout(None, input(&cash, 0, None)).await;
    let gate_ok = matches!(&refused, Err(CoreError::Validation { field, detail }) if field == "sold_by" && detail == SOLD_BY_MISSING);
    w.check(
        sc,
        gate_ok,
        format!(
            "checkout without sold_by is refused (SOLD_BY_MISSING): {:?}",
            refused.as_ref().map(|r| &r.local_order_id)
        ),
    );
    let mona_sale: Option<ReceiptView> =
        match core.checkout(None, input(&cash, 500, Some(&mona))).await {
            Ok(r) => Some(r),
            Err(e) => {
                w.check(sc, false, format!("checkout with sold_by = Mona: {e:?}"));
                None
            }
        };
    settle(&core, 120).await;
    if let Some(sale) = &mona_sale {
        match server_order_by(
            &fx,
            "SELECT id FROM orders WHERE idempotency_key::text = $1",
            &sale.local_order_id,
        )
        .await
        {
            Some(id) => {
                let o = order_json(&base, &owner, id).await;
                eprintln!(
                    "ORDER (Mona's) {}",
                    json!({"id": o["id"], "teller_id": o["teller_id"], "teller_name": o["teller_name"], "sold_by": o["sold_by"], "sold_by_name": o["sold_by_name"]})
                );
                w.eq(
                    sc,
                    "server sold_by",
                    o["sold_by"].as_str().map(str::to_string),
                    Some(mona.clone()),
                );
                w.eq(
                    sc,
                    "server sold_by_name",
                    o["sold_by_name"].as_str().map(str::to_string),
                    Some("Mona".to_string()),
                );
                w.eq(
                    sc,
                    "server teller_id (the signed-in teller)",
                    o["teller_id"].as_str().map(str::to_string),
                    Some(aya.clone()),
                );
            }
            None => {
                w.check(sc, false, "Mona's sale reached the server");
            }
        }
    }

    // ── 3. Replay ────────────────────────────────────────────────────────
    let sc = "3 replay";
    proxy.offline();
    for _ in 0..3 {
        core.refresh_connectivity().await;
    }
    w.check(sc, !core.sync_status().online, "the device is offline");
    add_item(&core, None);
    add_item(&core, None);
    let karim_sale = core.checkout(None, input(&cash, 0, Some(&karim))).await;
    w.check(
        sc,
        karim_sale.as_ref().is_ok_and(|r| r.queued_offline),
        format!(
            "offline sale picked as Karim queues: {:?}",
            karim_sale.as_ref().map(|r| r.queued_offline)
        ),
    );
    proxy.online();
    core.refresh_connectivity().await;
    settle(&core, 120).await;
    if let Ok(sale) = &karim_sale {
        match server_order_by(
            &fx,
            "SELECT id FROM orders WHERE idempotency_key::text = $1",
            &sale.local_order_id,
        )
        .await
        {
            Some(id) => {
                let o = order_json(&base, &owner, id).await;
                eprintln!(
                    "ORDER (Karim's replay) {}",
                    json!({"teller_id": o["teller_id"], "sold_by": o["sold_by"], "sold_by_name": o["sold_by_name"]})
                );
                w.eq(
                    sc,
                    "replayed sold_by",
                    o["sold_by"].as_str().map(str::to_string),
                    Some(karim.clone()),
                );
                w.eq(
                    sc,
                    "replayed sold_by_name",
                    o["sold_by_name"].as_str().map(str::to_string),
                    Some("Karim".to_string()),
                );
                w.eq(
                    sc,
                    "replayed teller_id",
                    o["teller_id"].as_str().map(str::to_string),
                    Some(aya.clone()),
                );
            }
            None => {
                w.check(sc, false, "the replayed sale reached the server");
            }
        }
    }

    // ── 4. A table's bill, settled ───────────────────────────────────────
    let sc = "4 ticket settle";
    add_item(&core, None);
    match core
        .fire_ticket(None, Some("Walk table 7".into()), None, Some(2), None, None)
        .await
    {
        Err(e) => {
            w.check(sc, false, format!("fire a bill: {e:?}"));
        }
        Ok(_) => {
            settle(&core, 120).await;
            let bill = core
                .list_open_tickets()
                .await
                .expect("bills")
                .into_iter()
                .find(|t| t.customer_name.as_deref() == Some("Walk table 7"))
                .expect("the bill is on the board");
            let no_pick = core
                .settle_ticket(
                    bill.id.clone(),
                    till_id.clone(),
                    cash.clone(),
                    Some(1_000_000),
                    None,
                    None,
                    None,
                    None,
                    None,
                    None,
                    vec![],
                    vec![],
                    false,
                    None,
                    None,
                    None,
                )
                .await;
            let gated = matches!(&no_pick, Err(CoreError::Validation { field, detail }) if field == "sold_by" && detail == SOLD_BY_MISSING);
            w.check(
                sc,
                gated,
                format!(
                    "settle without sold_by is refused: {:?}",
                    no_pick.as_ref().err()
                ),
            );
            let settled = core
                .settle_ticket(
                    bill.id.clone(),
                    till_id.clone(),
                    cash.clone(),
                    Some(1_000_000),
                    Some(300),
                    None,
                    None,
                    None,
                    None,
                    None,
                    vec![],
                    vec![],
                    false,
                    None,
                    None,
                    Some(karim.clone()),
                )
                .await;
            w.check(
                sc,
                settled.is_ok(),
                format!("settle with sold_by = Karim: {:?}", settled.as_ref().err()),
            );
            settle(&core, 120).await;
            match server_order_by(
                &fx,
                "SELECT id FROM orders WHERE open_ticket_id::text = $1",
                &bill.id,
            )
            .await
            {
                Some(id) => {
                    let o = order_json(&base, &owner, id).await;
                    eprintln!(
                        "ORDER (bill) {}",
                        json!({"teller_id": o["teller_id"], "sold_by": o["sold_by"], "sold_by_name": o["sold_by_name"]})
                    );
                    w.eq(
                        sc,
                        "settled bill's sold_by",
                        o["sold_by"].as_str().map(str::to_string),
                        Some(karim.clone()),
                    );
                    w.eq(
                        sc,
                        "settled bill's teller_id",
                        o["teller_id"].as_str().map(str::to_string),
                        Some(aya.clone()),
                    );
                }
                None => {
                    w.check(
                        sc,
                        false,
                        format!("the settled bill {} is an order on the server", bill.id),
                    );
                }
            }
        }
    }

    // ── 5. Clock-out ─────────────────────────────────────────────────────
    let sc = "5 clock-out";
    let (st, v) = punch(
        &base,
        &manager,
        &seed.s("/paid/employees/Mona"),
        "walk: clock out",
    )
    .await;
    w.check(
        sc,
        st == 200 && v["check_out_at"].is_string(),
        format!(
            "manager punches Mona out -> {st} check_out_at={}",
            v["check_out_at"]
        ),
    );
    core.sync_now().await.expect("pull");
    let p = core.teller_pick();
    eprintln!("PICK after Mona's clock-out: {}", show(&p));
    w.eq(sc, "mode", p.mode, PickMode::Focused);
    w.eq(sc, "primary", names(&p.primary), vec!["Karim".to_string()]);
    w.check(
        sc,
        names(&p.more).contains(&"Mona".to_string()),
        format!("Mona is under More: {:?}", names(&p.more)),
    );

    // ── 6. Z report: by person ───────────────────────────────────────────
    let sc = "6 z report";
    let local = core.till_report().await.expect("local report");
    let (st, server) = call(
        &base,
        &owner,
        reqwest::Method::GET,
        &format!("/tills/{till_id}/report"),
        None,
    )
    .await;
    w.check(sc, st == 200, format!("GET /tills/{{id}}/report -> {st}"));
    w.check(
        sc,
        server.get("by_person").is_some_and(Value::is_array),
        format!(
            "the server sends by_person: {}",
            server.get("by_person").unwrap_or(&Value::Null)
        ),
    );
    let (l, s) = (person_lines_local(&local), person_lines_server(&server));
    eprintln!("BY PERSON local  {l:?}\nBY PERSON server {s:?}");
    w.eq(
        sc,
        "local by_person == server by_person",
        l.clone(),
        s.clone(),
    );
    let who: Vec<Option<String>> = l.iter().map(|x| x.0.clone()).collect();
    w.eq(sc, "people on the till", who, {
        let mut v = vec![Some(mona.clone()), Some(karim.clone())];
        v.sort();
        v
    });
    let summed: i64 = l.iter().map(|x| x.3).sum();
    w.check(
        sc,
        summed == local.total_payments_minor,
        format!(
            "by_person totals {summed} add up to the till's payments {}",
            local.total_payments_minor
        ),
    );

    // ── 7. Switch off ────────────────────────────────────────────────────
    let sc = "7 switch off";
    let (st, _) = set_switch(&base, &owner, &branch, false).await;
    w.check(
        sc,
        (200..300).contains(&st),
        format!("owner PATCH switch off -> {st}"),
    );
    core.sync_now().await.expect("pull");
    let p = core.teller_pick();
    eprintln!("PICK after switch off: {}", show(&p));
    w.check(sc, !p.required, "not required");
    add_item(&core, None);
    match core.checkout(None, input(&cash, 0, None)).await {
        Err(e) => {
            w.check(sc, false, format!("checkout without sold_by: {e:?}"));
        }
        Ok(sale) => {
            settle(&core, 120).await;
            match server_order_by(
                &fx,
                "SELECT id FROM orders WHERE idempotency_key::text = $1",
                &sale.local_order_id,
            )
            .await
            {
                Some(id) => {
                    let o = order_json(&base, &owner, id).await;
                    eprintln!(
                        "ORDER (switch off) {}",
                        json!({"teller_id": o["teller_id"], "sold_by": o["sold_by"], "sold_by_name": o["sold_by_name"]})
                    );
                    w.check(
                        sc,
                        o["sold_by"].is_null(),
                        format!("server sold_by is null: {}", o["sold_by"]),
                    );
                    w.eq(
                        sc,
                        "teller_id",
                        o["teller_id"].as_str().map(str::to_string),
                        Some(aya.clone()),
                    );
                }
                None => {
                    w.check(sc, false, "the unpicked sale reached the server");
                }
            }
        }
    }

    eprintln!("TILL {till_id}");
    let _ = std::fs::remove_file(&db);
    assert!(
        w.fails.is_empty(),
        "teller pick walk: {} failed check(s):\n{}",
        w.fails.len(),
        w.fails.join("\n")
    );
}

#[tokio::test]
#[ignore]
async fn the_free_org_always_lists_everyone() {
    let seed = Seed::load();
    let fx = fixture(0).await;
    let base = fx.base.clone();
    let branch = seed.s("/free/branch_id");
    let owner = login(
        &base,
        &seed.s("/free/owner/email"),
        &seed.s("/free/owner/password"),
    )
    .await;
    let mut w = Walk::default();
    let sc = "8 free org";
    let (st, v) = set_switch(&base, &owner, &branch, true).await;
    w.check(
        sc,
        (200..300).contains(&st),
        format!("Free owner PATCH switch on -> {st} {v}"),
    );
    let db = temp_db("tp-free");
    let core = device(
        &base,
        &db,
        &seed.s("/free/teller/name"),
        &seed.s("/free/teller/pin"),
        &branch,
    )
    .await;
    core.sync_now().await.expect("pull");
    let p = core.teller_pick();
    eprintln!("PICK (Free): {}", show(&p));
    w.check(sc, p.required, "required (the switch is not plan-gated)");
    w.eq(sc, "mode", p.mode, PickMode::All);
    w.check(sc, p.more.is_empty(), "nothing behind More");
    w.check(
        sc,
        names(&p.primary).contains(&seed.s("/free/teller/name")),
        format!("the teller is listed: {:?}", names(&p.primary)),
    );
    let rows = teller_rows(&db, &branch);
    w.check(sc, !rows.is_empty(), format!("{} teller rows", rows.len()));
    for r in &rows {
        let since = r.get("on_shift_since").cloned().unwrap_or(Value::Null);
        w.check(
            sc,
            since.is_null(),
            format!("{} on_shift_since absent or null: {since}", r["name"]),
        );
    }
    let _ = std::fs::remove_file(&db);
    assert!(
        w.fails.is_empty(),
        "free org: {} failed check(s):\n{}",
        w.fails.len(),
        w.fails.join("\n")
    );
}
