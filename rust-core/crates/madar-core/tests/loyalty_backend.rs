//! Stamp tracks and the birthday gift: the REAL `MadarCore` against the REAL
//! backend (POS_MULTITRACK_DESIGN.md, BIRTHDAY_GIFT_DESIGN.md).
//!
//! Ignored by `cargo test`. Needs a backend and a throwaway database with a
//! sellable branch (an org on `paid`, `cash` / `card` methods), e.g. MadarRust's
//! `scripts/seed_fuzz.sql` with the methods named `cash` / `card`:
//!
//! ```sh
//! MADAR_OB_DB=postgres://…/db MADAR_OB_BRANCH=<branch> MADAR_OB_BASE=http://127.0.0.1:<port> \
//!   cargo test -p madar-core --features backend-tests --test loyalty_backend -- --include-ignored --test-threads 1
//! ```
//!
//! The suite configures the programme itself through the owner's API (a visits
//! card: track 1 earns per unit of a latte or an espresso and rewards a latte
//! at 5; "Sandwiches" size 3 per item; "Pastries" size 2 per sale; a cap of 2
//! rewards per order; the birthday gift as one free item) and joins members
//! through the public join. A birthday gift is granted by a nightly job, so the
//! suite writes the gift row the job would write. Every figure asserted was
//! worked out by hand in the comment beside it.
//!
//! `MADAR_E2E_CAPTURES=<dir>` also writes the server's answers (a three-track
//! lookup, a gift lookup, an award, a reprinted gift order) with a manifest, for
//! `tool/old_client_api_check` (`LOYALTY_DIR=<dir>`).

mod common;

use common::*;
use madar_core::checkout::{CheckoutInput, CheckoutRedemption};
use madar_core::loyalty::{self, RewardPick};
use madar_core::MadarCore;
use serde_json::{json, Value};
use std::sync::Arc;
use uuid::Uuid;

const LATTE: i64 = 5_000;
const ESPRESSO: i64 = 3_000;
const SANDWICH: i64 = 8_000;
const CROISSANT: i64 = 4_000;
const WATER: i64 = 1_000;

struct Shop {
    fx: Fixture,
    owner: String,
    org: Uuid,
    latte: String,
    espresso: String,
    sandwich: String,
    croissant: String,
    water: String,
}

fn http() -> reqwest::Client {
    // The core's reqwest has no crypto provider of its own (net.rs hands it
    // one); plain http here, but the builder still asks for a provider.
    let _ = rustls::crypto::ring::default_provider().install_default();
    reqwest::Client::new()
}

async fn call(base: &str, token: &str, method: reqwest::Method, path: &str, body: Option<Value>) -> (u16, Value) {
    let mut r = http().request(method, format!("{base}{path}")).bearer_auth(token);
    if let Some(b) = body {
        r = r.json(&b);
    }
    let res = r.send().await.expect("request");
    let status = res.status().as_u16();
    let text = res.text().await.unwrap_or_default();
    (status, serde_json::from_str(&text).unwrap_or(Value::String(text)))
}

async fn login(base: &str, body: Value) -> String {
    let (s, v) = call(base, "", reqwest::Method::POST, "/auth/login", Some(body)).await;
    assert_eq!(s, 200, "login: {v}");
    v["token"].as_str().unwrap().to_string()
}

async fn item(fx: &Fixture, org: Uuid, name: &str, price: i64) -> String {
    let cat: Uuid = fx
        .db
        .query_one("SELECT id FROM categories WHERE org_id = $1 ORDER BY created_at LIMIT 1", &[&org])
        .await
        .unwrap()
        .get(0);
    let price = price as i32;
    let row = fx
        .db
        .query_opt("SELECT id FROM menu_items WHERE org_id = $1 AND name = $2", &[&org, &name])
        .await
        .unwrap();
    let id: Uuid = match row {
        Some(r) => r.get(0),
        None => fx
            .db
            .query_one(
                "INSERT INTO menu_items (org_id, category_id, name, base_price) VALUES ($1, $2, $3, $4) RETURNING id",
                &[&org, &cat, &name, &price],
            )
            .await
            .unwrap()
            .get(0),
    };
    id.to_string()
}

/// The programme, as an owner sets it up in the dashboard.
async fn configure(s: &Shop, any_item: bool) {
    let base = &s.fx.base;
    let (st, v) = call(
        base,
        &s.owner,
        reqwest::Method::PUT,
        "/loyalty/settings",
        Some(json!({
            "org_id": s.org, "enabled": true, "program_name": "E2E Rewards", "mode": "visits",
            "earn_piastres_per_point": 1000, "earn_on_discounted": true, "earn_include_tax": false,
            "default_reward_cost": 5, "require_otp": false, "stamp_per_line_item": true,
            "reward_any_item": any_item, "max_rewards_per_order": 2,
            "birthday_enabled": true, "birthday_gift": "item", "birthday_gift_days": 30
        })),
    )
    .await;
    assert_eq!(st, 200, "settings: {v}");
    let (st, v) = call(
        base,
        &s.owner,
        reqwest::Method::PUT,
        "/loyalty/reward-items",
        Some(json!({ "items": [{ "menu_item_id": s.latte, "cost_amount": 5, "cost_currency": "visits" }] })),
    )
    .await;
    assert_eq!(st, 200, "reward items: {v}");
    let (st, v) = call(
        base,
        &s.owner,
        reqwest::Method::PUT,
        "/loyalty/earning-items",
        Some(json!({ "menu_item_ids": [s.latte, s.espresso] })),
    )
    .await;
    assert_eq!(st, 200, "earning items: {v}");
    let (st, v) = call(
        base,
        &s.owner,
        reqwest::Method::PUT,
        "/loyalty/tracks",
        Some(json!({ "tracks": [
            { "position": 1 },
            { "position": 2, "name_en": "Sandwiches", "name_ar": "ساندويتشات", "size": 3,
              "items": [s.sandwich], "per_item": true, "colour": "#8D5524" },
            { "position": 3, "name_en": "Pastries", "name_ar": "مخبوزات", "size": 2,
              "items": [s.croissant], "per_item": false }
        ] })),
    )
    .await;
    assert_eq!(st, 200, "tracks: {v}");
}

async fn shop() -> Shop {
    let fx = fixture(1).await;
    let branch = Uuid::parse_str(&fx.branch).unwrap();
    let org: Uuid = fx
        .db
        .query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch])
        .await
        .unwrap()
        .get(0);
    // The owner signs in with an email and a password (the dashboard's way).
    fx.db
        .execute(
            "UPDATE users SET email = 'owner@e2e.test', password_hash = crypt('owner-pass-1', gen_salt('bf', 4))
              WHERE org_id = $1 AND role = 'org_admin'",
            &[&org],
        )
        .await
        .unwrap();
    let owner = login(&fx.base, json!({ "email": "owner@e2e.test", "password": "owner-pass-1" })).await;
    let latte = item(&fx, org, "E2E Latte", LATTE).await;
    let espresso = item(&fx, org, "E2E Espresso", ESPRESSO).await;
    let sandwich = item(&fx, org, "E2E Sandwich", SANDWICH).await;
    let croissant = item(&fx, org, "E2E Croissant", CROISSANT).await;
    let water = item(&fx, org, "E2E Water", WATER).await;
    let s = Shop { fx, owner, org, latte, espresso, sandwich, croissant, water };
    configure(&s, false).await;
    s
}

/// A phone no earlier run used (members persist in the database).
fn fresh_phone() -> String {
    let n = Uuid::new_v4().as_u128() % 100_000_000;
    format!("2010{n:08}")
}

/// A member through the public join (no OTP at this shop).
async fn join(s: &Shop, phone: &str) -> String {
    let (st, v) = call(
        &s.fx.base,
        "",
        reqwest::Method::POST,
        "/public/loyalty/join",
        Some(json!({ "branch_id": s.fx.branch, "name": format!("E2E {phone}"), "phone": phone })),
    )
    .await;
    assert!(st == 200 || st == 201, "join: {st} {v}");
    // The member, as the till's lookup finds them by phone.
    let (st, v) = call(
        &s.fx.base,
        &s.owner,
        reqwest::Method::POST,
        "/loyalty/lookup",
        Some(json!({ "branch_id": s.fx.branch, "phone": phone })),
    )
    .await;
    assert_eq!(st, 200, "lookup by phone: {v}");
    v["member"]["id"].as_str().unwrap().to_string()
}

async fn balances(s: &Shop, member: &str) -> (i32, i32, i32) {
    let id = Uuid::parse_str(member).unwrap();
    let one: i32 = s
        .fx
        .db
        .query_one("SELECT visits_balance FROM loyalty_memberships WHERE id = $1", &[&id])
        .await
        .unwrap()
        .get(0);
    let track = |pos: i16| {
        let db = &s.fx.db;
        async move {
            db.query_opt(
                "SELECT balance FROM loyalty_track_balances WHERE customer_id = $1 AND position = $2",
                &[&id, &pos],
            )
            .await
            .unwrap()
            .map_or(0, |r| r.get::<_, i32>(0))
        }
    };
    (one, track(2).await, track(3).await)
}

async fn adjust(s: &Shop, member: &str, track: Option<i32>, points: i32) {
    let (st, v) = call(
        &s.fx.base,
        &s.owner,
        reqwest::Method::POST,
        "/loyalty/adjust",
        Some(json!({ "branch_id": s.fx.branch, "customer_id": member, "points": points, "track": track, "note": "e2e" })),
    )
    .await;
    assert_eq!(st, 200, "adjust: {v}");
}

async fn till(s: &Shop, tag: &str) -> Arc<MadarCore> {
    let teller = s.fx.tellers[0].1.clone();
    let core = core_at(&s.fx.base, &temp_db(tag), &teller, &s.fx.branch).await;
    if core.own_open_till().is_none() {
        core.open_till(20_000, Some(tag.into())).await.expect("open till");
    }
    core
}

fn add(core: &MadarCore, id: &str, name: &str, price: i64, qty: usize) {
    for _ in 0..qty {
        core.cart_add(None, id.to_string(), name.to_string(), price).expect("add");
    }
}

fn input(core: &MadarCore, member: Option<&str>, redemptions: Vec<CheckoutRedemption>) -> CheckoutInput {
    CheckoutInput {
        payment_method_id: method(core, true).unwrap(),
        amount_tendered_minor: 1_000_000,
        tip_minor: 0,
        tip_payment_method_id: None,
        customer_name: None,
        notes: None,
        splits: vec![],
        loyalty_customer_id: member.map(str::to_string),
        dine_in: false,
        customer_id: None,
        loyalty_redemptions: redemptions,
    }
}

/// The server's id for a sale this till rang.
async fn server_order(s: &Shop, local: &str) -> Uuid {
    s.fx
        .db
        .query_one("SELECT id FROM orders WHERE idempotency_key::text = $1", &[&local.to_string()])
        .await
        .expect("the sale reached the server")
        .get(0)
}

/// "Add points" on a sale's receipt, as the Done card presses it (the
/// receipt's own `created_at`).
async fn award(core: &MadarCore, sale: &madar_core::checkout::ReceiptView, member: &str) -> loyalty::LoyaltyAwardOutcome {
    core.loyalty_award(
        None,
        Some(sale.local_order_id.clone()),
        sale.created_at.clone(),
        None,
        None,
        Some(member.to_string()),
    )
    .await
    .expect("award")
}

fn capture(name: &str, v: &Value) {
    if let Ok(dir) = std::env::var("MADAR_E2E_CAPTURES") {
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(format!("{dir}/{name}"), serde_json::to_string_pretty(v).unwrap()).unwrap();
    }
}

async fn lookup_raw(s: &Shop, teller_token: &str, member: &str) -> Value {
    let (st, v) = call(
        &s.fx.base,
        teller_token,
        reqwest::Method::POST,
        "/loyalty/lookup",
        Some(json!({ "branch_id": s.fx.branch, "customer_id": member })),
    )
    .await;
    assert_eq!(st, 200, "lookup: {v}");
    v
}

async fn teller_token(s: &Shop) -> String {
    login(&s.fx.base, json!({ "name": s.fx.tellers[0].1, "pin": "1234", "branch_id": s.fx.branch })).await
}

/// One sale earns on every track it qualifies for with the single "Add
/// points" press; a ready track's reward covers a line of its own items; the
/// shared cap trims a third; a void puts every track back.
#[tokio::test]
#[ignore]
async fn three_tracks_earn_redeem_and_void_per_track() {
    let s = shop().await;
    let phone_1 = fresh_phone();
    let member = join(&s, &phone_1).await;
    let core = till(&s, "tracks").await;

    // Sale A: 2 lattes + 1 espresso (track 1 per unit: 3), 2 sandwiches
    // (Sandwiches per unit: 2), 3 croissants (Pastries per SALE: 1), a water
    // (no track).
    add(&core, &s.latte, "E2E Latte", LATTE, 2);
    add(&core, &s.espresso, "E2E Espresso", ESPRESSO, 1);
    add(&core, &s.sandwich, "E2E Sandwich", SANDWICH, 2);
    add(&core, &s.croissant, "E2E Croissant", CROISSANT, 3);
    add(&core, &s.water, "E2E Water", WATER, 1);
    let sale_a = core.checkout(None, input(&core, None, vec![])).await.expect("sale A");
    let a = sale_a.local_order_id.clone();
    settle(&core, 60).await;
    let out = award(&core, &sale_a, &member).await;
    assert_eq!(out.points_awarded, 3, "track 1: 2 lattes + 1 espresso");
    let earned: Vec<_> = out.tracks.iter().map(|t| (t.position, t.awarded, t.balance)).collect();
    assert_eq!(earned, [(1, 3, 3), (2, 2, 2), (3, 1, 1)]);
    assert_eq!(balances(&s, &member).await, (3, 2, 1));
    // A second press: already collected, nothing moves on any track.
    let again = award(&core, &sale_a, &member).await;
    assert!(again.already_collected);
    assert_eq!(balances(&s, &member).await, (3, 2, 1));
    let tt = teller_token(&s).await;
    capture("award_result.json", &{
        let (_, v) = call(
            &s.fx.base,
            &tt,
            reqwest::Method::POST,
            "/loyalty/award",
            Some(json!({ "branch_id": s.fx.branch, "customer_id": member, "order_key": a })),
        )
        .await;
        v
    });

    // Every track ready: 3+2 = 5 (size 5), 2+1 = 3 (size 3), 1+1 = 2 (size 2).
    adjust(&s, &member, None, 2).await;
    adjust(&s, &member, Some(2), 1).await;
    adjust(&s, &member, Some(3), 1).await;
    assert_eq!(balances(&s, &member).await, (5, 3, 2));
    let scan = core.loyalty_lookup(None, Some(phone_1.clone())).await.expect("lookup");
    capture("scan_result.json", &lookup_raw(&s, &tt, &member).await);
    let tracks: Vec<_> = scan.member.tracks.iter().map(|t| (t.position, t.balance, t.size, t.rewards_ready)).collect();
    assert_eq!(tracks, [(1, 5, 5, 1), (2, 3, 3, 1), (3, 2, 2, 1)]);
    assert_eq!(scan.member.tracks[1].name, "Sandwiches");
    let offered: Vec<_> = scan.track_rewards.iter().map(|t| (t.position, t.rewards[0].cost_amount)).collect();
    assert_eq!(offered, [(2, 3), (3, 2)]);
    assert_eq!(scan.rewards.len(), 1, "rewards stays track 1's: the latte");

    // Sale B: a latte, a sandwich, a croissant, an espresso; the teller asks a
    // reward on each of the first three. The cap (2) trims the croissant.
    add(&core, &s.latte, "E2E Latte", LATTE, 1);
    add(&core, &s.sandwich, "E2E Sandwich", SANDWICH, 1);
    add(&core, &s.croissant, "E2E Croissant", CROISSANT, 1);
    add(&core, &s.espresso, "E2E Espresso", ESPRESSO, 1);
    let lines = core.cart_reward_lines(None).unwrap();
    let asked = [
        RewardPick { line: 0, units: 1, track: 1 },
        RewardPick { line: 1, units: 1, track: 2 },
        RewardPick { line: 2, units: 1, track: 3 },
    ];
    let board = loyalty::reward_board(&lines, &scan, &asked, "en");
    assert_eq!(board.picks, asked[..2].to_vec(), "one cap across tracks");
    assert_eq!(board.adjusted_reason.as_deref(), Some("Up to 2 rewards per order here"));
    assert_eq!(board.covered_minor, LATTE + SANDWICH);
    let red = loyalty::redemptions_from_picks(&lines, &board.picks);
    let sale_b = core.checkout(None, input(&core, Some(&member), red)).await.expect("sale B");
    let b = sale_b.local_order_id.clone();
    settle(&core, 60).await;
    let b_id = server_order(&s, &b).await;
    let covered: Vec<(String, bool, Option<i16>)> = s
        .fx
        .db
        .query(
            "SELECT item_name, COALESCE(is_reward, false), reward_track FROM order_items
              WHERE order_id = $1 ORDER BY item_name",
            &[&b_id],
        )
        .await
        .unwrap()
        .iter()
        .map(|r| (r.get(0), r.get(1), r.get(2)))
        .collect();
    assert_eq!(
        covered,
        [
            ("E2E Croissant".into(), false, None),
            ("E2E Espresso".into(), false, None),
            ("E2E Latte".into(), true, None),
            ("E2E Sandwich".into(), true, Some(2)),
        ]
    );
    // Track 1 spent 5, Sandwiches 3, Pastries nothing.
    assert_eq!(balances(&s, &member).await, (0, 0, 2));
    let refused: Option<String> = s
        .fx
        .db
        .query_one("SELECT loyalty_redemption_refused FROM orders WHERE id = $1", &[&b_id])
        .await
        .unwrap()
        .get(0);
    assert_eq!(refused, None, "the server took the till's plan as it was");
    // Award B: the covered latte and sandwich earn nothing; the espresso 1 on
    // track 1, the croissant 1 on Pastries (a sale holding one).
    let out = award(&core, &sale_b, &member).await;
    let earned: Vec<_> = out.tracks.iter().map(|t| (t.position, t.awarded)).collect();
    assert_eq!(earned, [(1, 1), (2, 0), (3, 1)]);
    assert_eq!(balances(&s, &member).await, (1, 0, 3));

    // The reprint names the track's reward.
    core.sync_now().await.unwrap();
    let r = core.order_receipt_view(b_id.to_string()).await.expect("reprint");
    let labels: Vec<_> = r.lines.iter().filter_map(|l| l.reward_label.clone()).collect();
    assert!(labels.contains(&"Reward".to_string()), "{labels:?}");
    assert!(labels.contains(&"Reward · Sandwiches".to_string()), "{labels:?}");

    // Void B: each track gets back what it spent and loses what it earned:
    // track 1 1 + 5 - 1 = 5, Sandwiches 0 + 3 = 3, Pastries 3 - 1 = 2.
    core.void_order(b.clone(), "customer_changed_mind".into(), None, false).await.expect("void");
    settle(&core, 60).await;
    assert_eq!(balances(&s, &member).await, (5, 3, 2));
}

/// A refund claws each track's earn back (the whole sale refunded: all of it).
#[tokio::test]
#[ignore]
async fn a_refund_claws_back_each_track() {
    let s = shop().await;
    let phone_2 = fresh_phone();
    let member = join(&s, &phone_2).await;
    let core = till(&s, "refund").await;
    // 2 sandwiches (Sandwiches +2), 1 croissant (Pastries +1); nothing on track 1.
    add(&core, &s.sandwich, "E2E Sandwich", SANDWICH, 2);
    add(&core, &s.croissant, "E2E Croissant", CROISSANT, 1);
    let receipt = core.checkout(None, input(&core, None, vec![])).await.expect("sale");
    settle(&core, 60).await;
    let out = award(&core, &receipt, &member).await;
    assert_eq!(out.points_awarded, 0);
    assert_eq!(balances(&s, &member).await, (0, 2, 1));
    let id = server_order(&s, &receipt.local_order_id).await;
    core.sync_now().await.unwrap();
    core.refund_order(id.to_string(), receipt.total_minor, "cash".into(), "damaged".into(), None)
        .await
        .expect("refund");
    settle(&core, 60).await;
    assert_eq!(balances(&s, &member).await, (0, 0, 0), "floor(earned × all / all) per track");
}

async fn grant_gift(s: &Shop, member: &str, days_left: i64) {
    let id = Uuid::parse_str(member).unwrap();
    // What the birthday job writes (loyalty::birthdays) on the member's birthday.
    s.fx.db
        .execute(
            "INSERT INTO loyalty_gifts (org_id, customer_id, kind, year, valid_from, valid_until)
             VALUES ($1, $2, 'birthday', extract(year from now())::int, now() - interval '40 days',
                     now() + ($3::bigint * interval '1 day'))
             ON CONFLICT (customer_id, kind, year) DO UPDATE
                SET status = 'open', claimed_at = NULL, claimed_source = NULL, claimed_order_id = NULL,
                    claimed_order_item_id = NULL, claimed_line_index = NULL, claimed_menu_item_id = NULL,
                    claim_key = NULL, valid_until = EXCLUDED.valid_until",
            &[&s.org, &id, &days_left],
        )
        .await
        .expect("grant the gift");
}

async fn gift_status(s: &Shop, member: &str) -> String {
    let id = Uuid::parse_str(member).unwrap();
    s.fx.db
        .query_one("SELECT status FROM loyalty_gifts WHERE customer_id = $1", &[&id])
        .await
        .unwrap()
        .get(0)
}

/// The birthday gift at the till: the lookup's whole catalogue decides the
/// lines, one line goes free with no balance spent, a used gift is refused,
/// a void re-opens it, "any item" widens it.
#[tokio::test]
#[ignore]
async fn the_birthday_gift_at_the_till() {
    let s = shop().await;
    configure(&s, false).await;
    let phone_3 = fresh_phone();
    let member = join(&s, &phone_3).await;
    grant_gift(&s, &member, 10).await;
    let core = till(&s, "gift").await;
    let tt = teller_token(&s).await;

    // Balance 0: the latte is not affordable as a reward, yet it can be the
    // gift (the lookup sends the whole catalogue with the gift).
    let scan = core.loyalty_lookup(None, Some(phone_3.clone())).await.expect("lookup");
    capture("gift_scan_result.json", &lookup_raw(&s, &tt, &member).await);
    assert!(scan.rewards.is_empty(), "nothing affordable at 0");
    let g = scan.birthday_gift.clone().expect("a gift");
    assert!(g.open);
    assert_eq!(g.reward_item_ids.as_deref(), Some(&[s.latte.clone()][..]));
    assert_eq!(g.any_item, Some(false));
    add(&core, &s.latte, "E2E Latte", LATTE, 1);
    add(&core, &s.water, "E2E Water", WATER, 1);
    let lines = core.cart_reward_lines(None).unwrap();
    let gb = loyalty::gift_board(&lines, &scan, &[], None, "en");
    assert_eq!(gb.eligible, vec![0], "the latte, not the water");
    assert_eq!(gb.line, None, "never picked for the teller");
    let gift = loyalty::gift_redemption(&lines, 0).unwrap();
    let sale = core.checkout(None, input(&core, Some(&member), vec![gift])).await.expect("gift sale");
    settle(&core, 60).await;
    let id = server_order(&s, &sale.local_order_id).await;
    assert_eq!(gift_status(&s, &member).await, "claimed");
    assert_eq!(balances(&s, &member).await.0, 0, "no balance moved");
    let (is_reward, units): (bool, i32) = {
        let r = s
            .fx
            .db
            .query_one(
                "SELECT COALESCE(is_reward, false), COALESCE(reward_units, 0) FROM order_items
                  WHERE order_id = $1 AND item_name = 'E2E Latte'",
                &[&id],
            )
            .await
            .unwrap();
        (r.get(0), r.get(1))
    };
    assert_eq!((is_reward, units), (true, 1));
    // The reprint (the feed's order row) says it was the gift.
    core.sync_now().await.unwrap();
    let r = core.order_receipt_view(id.to_string()).await.expect("reprint");
    let labels: Vec<_> = r.lines.iter().map(|l| l.reward_label.clone()).collect();
    assert!(labels.contains(&Some("Birthday gift".into())), "{labels:?}");
    let (_, full) = call(&s.fx.base, &tt, reqwest::Method::GET, &format!("/orders/{id}"), None).await;
    capture("order_full.json", &full);

    // Used: the next lookup shows it claimed, and the till refuses a second.
    let used = core.loyalty_lookup(None, Some(phone_3.clone())).await.unwrap();
    assert!(!used.birthday_gift.as_ref().is_some_and(|g| g.open));
    add(&core, &s.latte, "E2E Latte", LATTE, 1);
    let lines = core.cart_reward_lines(None).unwrap();
    let again = loyalty::gift_redemption(&lines, 0).unwrap();
    let err = core.checkout(None, input(&core, Some(&member), vec![again])).await.unwrap_err();
    assert!(format!("{err:?}").contains("already been used"), "{err:?}");

    // A void re-opens it (still inside its window).
    core.void_order(sale.local_order_id.clone(), "customer_changed_mind".into(), None, false)
        .await
        .expect("void");
    settle(&core, 60).await;
    assert_eq!(gift_status(&s, &member).await, "open");

    // "Any item": the water may be the gift too.
    configure(&s, true).await;
    let any = core.loyalty_lookup(None, Some(phone_3.clone())).await.unwrap();
    assert_eq!(any.birthday_gift.as_ref().and_then(|g| g.any_item), Some(true));
    core.cart_clear(None).ok();
    add(&core, &s.latte, "E2E Latte", LATTE, 1);
    add(&core, &s.water, "E2E Water", WATER, 1);
    let lines = core.cart_reward_lines(None).unwrap();
    assert_eq!(loyalty::gift_board(&lines, &any, &[], None, "en").eligible, vec![0, 1]);
    let water = loyalty::gift_redemption(&lines, 1).unwrap();
    core.checkout(None, input(&core, Some(&member), vec![water])).await.expect("water as the gift");
    settle(&core, 60).await;
    assert_eq!(gift_status(&s, &member).await, "claimed");
    configure(&s, false).await;
}

/// The server's own refusals of a gift on a live sale (`POST /orders`), and the
/// counter's claim (Rewards by Madar shops).
#[tokio::test]
#[ignore]
async fn the_gift_refusals_and_the_counter() {
    let s = shop().await;
    configure(&s, false).await;
    let phone_4 = fresh_phone();
    let member = join(&s, &phone_4).await;
    grant_gift(&s, &member, 10).await;
    let core = till(&s, "refusals").await;
    let till_id = core.own_open_till().expect("a till").id;
    let tt = teller_token(&s).await;
    let order = |gift: Value| {
        json!({
            "branch_id": s.fx.branch, "till_id": till_id, "payment_method": "cash",
            "amount_tendered": 100000, "idempotency_key": Uuid::new_v4().to_string(),
            "items": [
                { "menu_item_id": s.latte, "quantity": 1 },
                { "menu_item_id": s.water, "quantity": 1 }
            ],
            "loyalty_customer_id": member, "loyalty_birthday_gift": gift
        })
    };
    let code = |v: &Value| v["code"].as_str().unwrap_or_default().to_string();
    let (st, v) = call(&s.fx.base, &tt, reqwest::Method::POST, "/orders", Some(order(json!({ "item_index": 1 })))).await;
    assert_eq!((st, code(&v)), (409, "LOYALTY_GIFT_NOT_A_REWARD".into()), "water, any-item off: {v}");
    let (st, v) = call(&s.fx.base, &tt, reqwest::Method::POST, "/orders", Some(order(json!({ "item_index": 5 })))).await;
    assert_eq!((st, code(&v)), (409, "LOYALTY_GIFT_LINE".into()), "no such line: {v}");
    assert_eq!(gift_status(&s, &member).await, "open", "a refusal claims nothing");
    // Expired: the window passed.
    let id = Uuid::parse_str(&member).unwrap();
    s.fx.db
        .execute("UPDATE loyalty_gifts SET valid_until = now() - interval '1 minute' WHERE customer_id = $1", &[&id])
        .await
        .unwrap();
    let (st, v) = call(&s.fx.base, &tt, reqwest::Method::POST, "/orders", Some(order(json!({ "item_index": 0 })))).await;
    assert_eq!((st, code(&v)), (409, "LOYALTY_GIFT_NONE".into()), "expired: {v}");
    // Open again; a live sale claims it; a second is refused.
    grant_gift(&s, &member, 10).await;
    let (st, v) = call(&s.fx.base, &tt, reqwest::Method::POST, "/orders", Some(order(json!({ "item_index": 0 })))).await;
    assert!(st == 200 || st == 201, "claimed live: {st} {v}");
    let (st, v) = call(&s.fx.base, &tt, reqwest::Method::POST, "/orders", Some(order(json!({ "item_index": 0 })))).await;
    assert_eq!((st, code(&v)), (409, "LOYALTY_GIFT_NONE".into()), "already claimed: {v}");
    // The refusal's words on the till.
    let words = madar_core::i18n::tr("en", "sync.err_loyalty_gift_none");
    assert!(!words.starts_with("sync."));

    // The counter: claim with a key; the same key answers the same; a new one
    // finds nothing open.
    let phone_5 = fresh_phone();
    let other = join(&s, &phone_5).await;
    grant_gift(&s, &other, 10).await;
    let key = Uuid::new_v4().to_string();
    let claim = |k: String| json!({ "branch_id": s.fx.branch, "customer_id": other, "idempotency_key": k });
    let (st, v) = call(&s.fx.base, &tt, reqwest::Method::POST, "/loyalty/counter/birthday-gift", Some(claim(key.clone()))).await;
    assert_eq!(st, 200, "counter claim: {v}");
    assert_eq!(v["already"], false);
    assert_eq!(v["birthday_gift"]["status"], "claimed");
    let (st, v) = call(&s.fx.base, &tt, reqwest::Method::POST, "/loyalty/counter/birthday-gift", Some(claim(key))).await;
    assert_eq!((st, v["already"].clone()), (200, json!(true)));
    let (st, v) = call(
        &s.fx.base,
        &tt,
        reqwest::Method::POST,
        "/loyalty/counter/birthday-gift",
        Some(claim(Uuid::new_v4().to_string())),
    )
    .await;
    assert_eq!((st, code(&v)), (409, "LOYALTY_GIFT_NONE".into()), "{v}");

    // Counter stamps on a track: Pastries counts one per visit (per_item off),
    // Sandwiches per item; a card that is not full is not completed.
    let stamp = |track: i32, items: i32| {
        json!({ "branch_id": s.fx.branch, "customer_id": other, "items": items, "track": track,
                "idempotency_key": Uuid::new_v4().to_string() })
    };
    let (st, v) = call(&s.fx.base, &tt, reqwest::Method::POST, "/loyalty/counter/stamp", Some(stamp(3, 4))).await;
    assert_eq!(st, 200, "stamp: {v}");
    let (st, v) = call(&s.fx.base, &tt, reqwest::Method::POST, "/loyalty/counter/stamp", Some(stamp(2, 2))).await;
    assert_eq!(st, 200, "stamp: {v}");
    assert_eq!(balances(&s, &other).await, (0, 2, 1));
    let (st, v) = call(
        &s.fx.base,
        &tt,
        reqwest::Method::POST,
        "/loyalty/counter/redeem",
        Some(json!({ "branch_id": s.fx.branch, "customer_id": other, "track": 2, "idempotency_key": Uuid::new_v4().to_string() })),
    )
    .await;
    assert_eq!((st, code(&v)), (409, "LOYALTY_CARD_NOT_FULL".into()), "2 of 3: {v}");
}
