//! Property-based convergence (OFFLINE_B_DESIGN §9 Phase 2 tests).
//!
//! A model server applies ops idempotently and keeps a changefeed. A device —
//! the real store, the real applier, write path and ack folding — rings sales,
//! voids and pays in/out on one till while the network delivers every outcome a
//! POS sees: acks, lost responses (applied on the server, answer lost), offline
//! blips, crashes between steps, remote writes from another device, and feed
//! pages that arrive twice or out of order. After quiescence (everything
//! re-sent, the feed caught up) the device's rows equal the server's, and at
//! EVERY step the device's drawer equals an independent statement of the cash:
//! the float, plus the cash of every sale the teller rang or the feed brought
//! and has not been voided, plus every movement — each exactly once.

use std::collections::BTreeMap;

use proptest::prelude::*;
use serde_json::{json, Value};

use super::apply::{self, PageCtx};
use super::{local, report, T_CASH, T_ORDER, T_TILL};
use crate::store::{NewOutboxOp, OutboxItem, Store};

const TILL: &str = "aaaaaaaa-0000-0000-0000-000000000001";
const BRANCH: &str = "bbbbbbbb-0000-0000-0000-000000000001";
const OPENING: i64 = 10_000;

#[derive(Clone, Debug)]
enum Step {
    /// Ring a sale on this device: amount, cash?
    Sell(i64, bool),
    /// Void the n-th sale this device knows about.
    Void(usize),
    /// Pay in (positive) / out (negative).
    Cash(i64),
    /// Send the oldest due op with an outcome.
    Send(Outcome),
    /// Another device rings a sale on the same till (a LAN-relayed backup of
    /// this till's own sale would dedup; a different sale is a remote write).
    Remote(i64, bool),
    /// Pull the feed: duplicate the page, or replay an older page afterwards.
    Pull { duplicate: bool, stale_replay: bool },
    /// A crash in the middle of a local write (the transaction rolls back).
    CrashedSell(i64),
    /// A list read of the till (`GET /orders?till_id`): every server sale, with
    /// or without its client key on the wire (an older server sends none).
    HistoryFetch(bool),
    /// A pre-B store's `cache:order:*` records migrated into rows (step 4),
    /// with or without the client key.
    Migrate(bool),
}

#[derive(Clone, Copy, Debug)]
enum Outcome {
    Ack,
    LostResponse,
    Offline,
    /// Applied and answered, but with no body to fold (the row keeps no server id).
    AckNoBody,
    /// The server refused it (dead-lettered); the teller later gives up on it.
    Dead,
}

fn step() -> impl Strategy<Value = Step> {
    prop_oneof![
        4 => (1i64..50, any::<bool>()).prop_map(|(a, c)| Step::Sell(a * 100, c)),
        1 => (0usize..6).prop_map(Step::Void),
        1 => (-20i64..20).prop_filter("non-zero", |a| *a != 0).prop_map(|a| Step::Cash(a * 50)),
        5 => prop_oneof![4 => Just(Outcome::Ack), 2 => Just(Outcome::AckNoBody), 2 => Just(Outcome::LostResponse), 2 => Just(Outcome::Offline), 1 => Just(Outcome::Dead)].prop_map(Step::Send),
        1 => any::<bool>().prop_map(Step::HistoryFetch),
        1 => any::<bool>().prop_map(Step::Migrate),
        1 => (1i64..30, any::<bool>()).prop_map(|(a, c)| Step::Remote(a * 100, c)),
        2 => (any::<bool>(), any::<bool>()).prop_map(|(d, s)| Step::Pull { duplicate: d, stale_replay: s }),
        1 => (1i64..10).prop_map(|a| Step::CrashedSell(a * 100)),
    ]
}

/// The model server: rows by server id in projection shape, and a compacted
/// changefeed (one seq per entity, moved on every change).
#[derive(Default)]
struct Server {
    seq: i64,
    orders: BTreeMap<String, Value>,
    cash: BTreeMap<String, Value>,
    feed: BTreeMap<(String, String), i64>,
}

impl Server {
    fn emit(&mut self, ty: &str, id: &str) {
        self.seq += 1;
        self.feed.insert((ty.to_string(), id.to_string()), self.seq);
    }

    fn apply(&mut self, op: &OutboxItem) -> Value {
        let p: Value = serde_json::from_str(&op.payload).unwrap();
        match op.op_type.as_str() {
            "create_order" => {
                let key = p["key"].as_str().unwrap().to_string();
                if let Some((id, v)) = self.orders.iter().find(|(_, v)| v["idempotency_key"] == key.as_str()) {
                    let _ = id;
                    return v.clone();
                }
                let id = uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, key.as_bytes()).to_string();
                let mut row = p["row"].clone();
                row["id"] = json!(id);
                self.orders.insert(id.clone(), row.clone());
                self.emit(T_ORDER, &id);
                row
            }
            "void_order" => {
                let target = p["order_id"].as_str().unwrap().to_string();
                let id = self
                    .orders
                    .iter()
                    .find(|(id, v)| **id == target || v["idempotency_key"] == target.as_str())
                    .map(|(id, _)| id.clone())
                    .expect("a void is gated behind its sale's create");
                let row = self.orders.get_mut(&id).unwrap();
                if row["status"] != "voided" {
                    row["status"] = json!("voided");
                    let r = row.clone();
                    self.emit(T_ORDER, &id);
                    return r;
                }
                row.clone()
            }
            "cash_movement" => {
                let key = p["row"]["client_ref"].as_str().unwrap().to_string();
                if let Some(v) = self.cash.values().find(|v| v["client_ref"] == key.as_str()) {
                    return v.clone();
                }
                let id = uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, format!("cash:{key}").as_bytes()).to_string();
                let mut row = p["row"].clone();
                row["id"] = json!(id);
                self.cash.insert(id.clone(), row.clone());
                self.emit(T_CASH, &id);
                row
            }
            other => panic!("unexpected op {other}"),
        }
    }

    fn page_since(&self, since: i64) -> Vec<(i64, String, Value)> {
        let mut v: Vec<(i64, String, Value)> = self
            .feed
            .iter()
            .filter(|(_, seq)| **seq > since)
            .map(|((ty, id), seq)| {
                let row = if ty == T_ORDER { self.orders[id].clone() } else { self.cash[id].clone() };
                let mut row = row;
                row["seq"] = json!(seq);
                (*seq, ty.clone(), row)
            })
            .collect();
        v.sort_by_key(|x| x.0);
        v
    }

    /// The server's own drawer statement for the till.
    fn drawer(&self) -> i64 {
        let sales: i64 = self
            .orders
            .values()
            .filter(|o| o["status"] != "voided")
            .flat_map(|o| o["payment_legs"].as_array().cloned().unwrap_or_default())
            .filter(|l| l["is_cash"] == true)
            .map(|l| l["amount"].as_i64().unwrap())
            .sum();
        let moves: i64 = self.cash.values().map(|m| m["amount"].as_i64().unwrap()).sum();
        OPENING + sales + moves
    }
}

struct Device {
    store: Store,
    cursor: i64,
    old_pages: Vec<Vec<(i64, String, Value)>>,
    known_sales: Vec<String>,
    n: u64,
}

fn ctx() -> PageCtx {
    PageCtx { full: false, window_from: None, stream_window_from: None, now_ms: super::now_ms(), horizon: None }
}

fn sale_row(key: &str, amount: i64, cash: bool) -> Value {
    json!({"id": key, "idempotency_key": key, "order_ref": format!("REF-{key}"), "branch_id": BRANCH, "till_id": TILL, "status": "completed",
           "payment_method": if cash { "Cash" } else { "Card" }, "total_amount": amount, "tip_amount": 0,
           "created_at": "2026-09-14T09:00:00Z",
           "payment_legs": [{"method": if cash { "Cash" } else { "Card" }, "amount": amount, "is_cash": cash}]})
}

impl Device {
    fn new() -> Self {
        let store = Store::open("").unwrap();
        store
            .with_tx(|tx| {
                super::write_row(
                    tx,
                    T_TILL,
                    TILL,
                    &json!({"id": TILL, "branch_id": BRANCH, "teller_id": "t", "status": "open", "opening_cash": OPENING,
                            "opened_at": "2026-09-14T08:00:00Z"}),
                    super::Origin::Feed(0),
                    None,
                )?;
                tx.execute("UPDATE ledger_tills SET complete=1", [])?;
                Ok(())
            })
            .unwrap();
        Device { store, cursor: 0, old_pages: Vec::new(), known_sales: Vec::new(), n: 0 }
    }

    fn next_id(&mut self, tag: &str) -> String {
        self.n += 1;
        uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, format!("{tag}:{}", self.n).as_bytes()).to_string()
    }

    fn op(&self, id: &str, op_type: &str, entity_type: &str, entity_id: &str, payload: Value) -> NewOutboxOp {
        NewOutboxOp {
            id: id.into(),
            op_type: op_type.into(),
            idempotency_key: id.into(),
            payload: payload.to_string(),
            event_at: "2026-09-14T09:00:00Z".into(),
            till_id: Some(TILL.into()),
            entity_type: Some(entity_type.into()),
            entity_id: Some(entity_id.into()),
            depends_on_seq: None,
            ..Default::default()
        }
    }

    fn sell(&mut self, amount: i64, cash: bool, crash: bool) {
        let key = self.next_id("sale");
        let row = sale_row(&key, amount, cash);
        let op = self.op(&key, "create_order", T_ORDER, &key, json!({"key": key, "row": row}));
        let res = self.store.with_tx(|tx| {
            local::commit_order(tx, &op, &row)?;
            if crash {
                return Err(crate::error::CoreError::Internal { detail: "killed mid-transaction".into() });
            }
            Ok(())
        });
        if res.is_ok() {
            self.known_sales.push(key);
        }
    }

    fn void(&mut self, n: usize) {
        let Some(key) = self.known_sales.get(n).cloned() else { return };
        let id = format!("{key}:void");
        if self.store.list_active().unwrap().iter().any(|i| i.id == id) {
            return;
        }
        // The gate: a void waits behind its sale's still-queued create.
        let dep = self.store.live_seq_of(&key).unwrap();
        let mut op = self.op(&id, "void_order", T_ORDER, &key, json!({"order_id": key}));
        op.depends_on_seq = dep;
        self.store
            .with_tx(|tx| local::commit_void(tx, &op, "2026-09-14T09:30:00Z", "other", None).map(|_| ()))
            .unwrap();
    }

    fn cash(&mut self, amount: i64) {
        let key = self.next_id("cash");
        let row = json!({"id": key, "client_ref": key, "till_id": TILL, "amount": amount,
                         "kind": if amount < 0 { "pay_out" } else { "pay_in" }, "created_at": "2026-09-14T09:10:00Z"});
        let op = self.op(&key, "cash_movement", T_CASH, &key, json!({"row": row}));
        self.store.with_tx(|tx| local::commit_cash(tx, &op, &row).map(|_| ())).unwrap();
    }

    /// The oldest op that may go (FIFO; a dependency must have acked).
    fn due(&self) -> Option<OutboxItem> {
        self.store.list_active().unwrap().into_iter().find(|i| {
            i.status == "pending"
                && i.depends_on_seq
                    .map(|d| !matches!(self.store.status_of_seq(d).unwrap().as_deref(), Some("pending" | "inflight" | "dead")))
                    .unwrap_or(true)
        })
    }

    fn send(&mut self, server: &mut Server, outcome: Outcome) {
        let Some(item) = self.due() else { return };
        self.store.mark_inflight(item.seq).unwrap();
        match outcome {
            Outcome::Offline => self.store.mark_retry_no_count(item.seq, 0).unwrap(),
            Outcome::Dead => self.store.mark_dead(item.seq, "refused").unwrap(),
            Outcome::LostResponse => {
                server.apply(&item);
                // The response never arrived: the op goes back to pending.
                self.store.mark_retry_no_count(item.seq, 0).unwrap();
            }
            Outcome::AckNoBody => {
                server.apply(&item);
                self.store
                    .with_tx(|tx| {
                        crate::store::mark_acked_on(tx, item.seq, None)?;
                        super::fold::fold(tx, &item, None, &[])?;
                        Ok(())
                    })
                    .unwrap();
            }
            Outcome::Ack => {
                let body = server.apply(&item);
                self.store
                    .with_tx(|tx| {
                        crate::store::mark_acked_on(tx, item.seq, body["id"].as_str())?;
                        super::fold::fold(tx, &item, Some(&body), &[])?;
                        Ok(())
                    })
                    .unwrap();
            }
        }
    }

    fn pull(&mut self, server: &Server, duplicate: bool, stale_replay: bool) {
        let page = server.page_since(self.cursor);
        let next = page.last().map(|p| p.0).unwrap_or(self.cursor);
        let apply = |store: &Store, page: &[(i64, String, Value)]| {
            store
                .with_tx(|tx| {
                    for (seq, ty, row) in page {
                        apply::upsert(tx, ty, row, *seq, &ctx())?;
                    }
                    Ok(())
                })
                .unwrap();
        };
        apply(&self.store, &page);
        if duplicate {
            apply(&self.store, &page);
        }
        if stale_replay {
            if let Some(old) = self.old_pages.first().cloned() {
                apply(&self.store, &old);
            }
        }
        self.old_pages.push(page);
        self.cursor = next;
    }

    fn drawer(&self) -> i64 {
        self.store.with_conn(|c| report::compute(c, TILL, &[])).unwrap().unwrap().expected_cash
    }

    /// The server's sales as a list read returns them.
    fn listed(server: &Server, with_key: bool) -> Vec<Value> {
        server
            .orders
            .values()
            .map(|o| {
                let mut v = o.clone();
                if !with_key {
                    v.as_object_mut().unwrap().remove("idempotency_key");
                }
                v
            })
            .collect()
    }

    fn history_fetch(&self, server: &Server, with_key: bool) {
        super::views::store_fetched_orders(&self.store, &Self::listed(server, with_key)).unwrap();
    }

    fn migrate(&self, server: &Server, with_key: bool) {
        for v in Self::listed(server, with_key) {
            self.store.kv_put(&format!("cache:order:{}", v["id"].as_str().unwrap()), &json!([v]).to_string()).unwrap();
        }
        self.store.with_tx(|tx| super::migrate::backfill(tx)).unwrap();
    }

    /// Exactly one row per sale: no two rows share a sale's order_ref, and none lacks it.
    fn duplicate_sales(&self) -> i64 {
        self.store
            .with_conn(|c| {
                Ok(c.query_row(
                    "SELECT (SELECT COUNT(*) FROM (SELECT order_ref FROM ledger_orders GROUP BY order_ref HAVING COUNT(*) > 1))
                          + (SELECT COUNT(*) FROM ledger_orders WHERE order_ref IS NULL)",
                    [],
                    |r| r.get(0),
                )?)
            })
            .unwrap()
    }

    /// The device's independent statement: every sale row not voided + every movement row.
    fn statement(&self) -> i64 {
        self.store
            .with_conn(|c| {
                let sales: i64 = c.query_row(
                    "SELECT COALESCE(SUM(p.amount),0) FROM ledger_payments p JOIN ledger_orders o ON o.okey=p.okey
                      WHERE o.status<>'voided' AND p.is_cash=1",
                    [],
                    |r| r.get(0),
                )?;
                let moves: i64 = c.query_row("SELECT COALESCE(SUM(amount),0) FROM ledger_cash", [], |r| r.get(0))?;
                Ok(OPENING + sales + moves)
            })
            .unwrap()
    }

    fn rows(&self) -> BTreeMap<String, (String, i64)> {
        self.store
            .with_conn(|c| {
                let mut out = BTreeMap::new();
                let mut st = c.prepare("SELECT raw FROM ledger_orders")?;
                for raw in st.query_map([], |r| r.get::<_, String>(0))? {
                    let v: Value = serde_json::from_str(&raw?).unwrap();
                    out.insert(
                        v["idempotency_key"].as_str().unwrap().to_string(),
                        (v["status"].as_str().unwrap().to_string(), v["total_amount"].as_i64().unwrap()),
                    );
                }
                let mut st = c.prepare("SELECT raw FROM ledger_cash")?;
                for raw in st.query_map([], |r| r.get::<_, String>(0))? {
                    let v: Value = serde_json::from_str(&raw?).unwrap();
                    out.insert(v["client_ref"].as_str().unwrap().to_string(), ("cash".into(), v["amount"].as_i64().unwrap()));
                }
                Ok(out)
            })
            .unwrap()
    }
}

fn server_rows(server: &Server) -> BTreeMap<String, (String, i64)> {
    let mut out = BTreeMap::new();
    for v in server.orders.values() {
        out.insert(
            v["idempotency_key"].as_str().unwrap().to_string(),
            (v["status"].as_str().unwrap().to_string(), v["total_amount"].as_i64().unwrap()),
        );
    }
    for v in server.cash.values() {
        out.insert(v["client_ref"].as_str().unwrap().to_string(), ("cash".into(), v["amount"].as_i64().unwrap()));
    }
    out
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(160))]

    #[test]
    fn the_device_converges_on_the_server_and_counts_every_sale_once(steps in prop::collection::vec(step(), 1..60)) {
        let mut server = Server::default();
        let mut device = Device::new();
        let mut remote_n = 0u64;
        for s in &steps {
            match s.clone() {
                Step::Sell(a, c) => device.sell(a, c, false),
                Step::CrashedSell(a) => device.sell(a, true, true),
                Step::Void(n) => device.void(n),
                Step::Cash(a) => device.cash(a),
                Step::Send(o) => device.send(&mut server, o),
                Step::Remote(a, c) => {
                    remote_n += 1;
                    let key = uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_OID, format!("remote:{remote_n}").as_bytes()).to_string();
                    let id = format!("srv-{key}");
                    server.orders.insert(id.clone(), sale_row(&key, a, c));
                    // A remote sale's client key is not its server id.
                    server.orders.get_mut(&id).unwrap()["id"] = json!(id);
                    server.emit(T_ORDER, &id);
                }
                Step::Pull { duplicate, stale_replay } => device.pull(&server, duplicate, stale_replay),
                Step::HistoryFetch(k) => device.history_fetch(&server, k),
                Step::Migrate(k) => device.migrate(&server, k),
            }
            // At EVERY step: one row per sale, and the drawer is the independent
            // statement over those rows (so no sale is counted twice).
            prop_assert_eq!(device.duplicate_sales(), 0, "one row per sale after {:?}", s);
            prop_assert_eq!(device.drawer(), device.statement());
        }
        // Quiescence: the teller gives up on every dead op (the row it created
        // goes, a row it changed returns to the server's version); everything
        // else is re-sent until acked, and the feed catches up.
        for dead in device.store.list_active().unwrap().into_iter().filter(|i| i.status == "dead") {
            device
                .store
                .with_tx(|tx| {
                    tx.execute("DELETE FROM outbox WHERE seq=?1", [dead.seq])?;
                    local::discard(tx, dead.entity_type.as_deref().unwrap(), dead.entity_id.as_deref().unwrap())
                })
                .unwrap();
            // Ops waiting on a discarded create cannot land either.
            prop_assert_eq!(device.drawer(), device.statement());
        }
        for dependent in device.store.list_active().unwrap() {
            if let Some(dep) = dependent.depends_on_seq {
                if device.store.status_of_seq(dep).unwrap().is_none() {
                    device
                        .store
                        .with_tx(|tx| {
                            tx.execute("DELETE FROM outbox WHERE seq=?1", [dependent.seq])?;
                            local::discard(tx, dependent.entity_type.as_deref().unwrap(), dependent.entity_id.as_deref().unwrap())
                        })
                        .unwrap();
                }
            }
        }
        for _ in 0..500 {
            if device.due().is_none() { break; }
            device.send(&mut server, Outcome::Ack);
        }
        prop_assert!(device.store.list_active().unwrap().is_empty(), "the queue drains");
        device.pull(&server, false, false);
        prop_assert_eq!(device.rows(), server_rows(&server), "rows converge");
        prop_assert_eq!(device.drawer(), server.drawer(), "the drawer equals the server's");
    }
}
