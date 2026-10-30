//! "Who's serving?" — the person picked at checkout on a branch that asks
//! (`branch_settings.pick_teller_at_checkout`, TELLER_PICK_SPEC §3.3–3.6).
//!
//! The picked person rides the sale as `sold_by`: attribution only. The
//! signed-in person stays `teller_id` (the drawer, the money permissions,
//! replay). A branch that never turns the switch on sends nothing new.
//!
//! The list is read from the device's own rows, never the network: the
//! `teller` feed rows (with their capabilities AT THIS BRANCH and, from a
//! server that knows Dawam, `on_shift_since`) and the branch's settings row.
//! [`pick`] is the whole rule, pure over those inputs.

use chrono::{DateTime, Utc};
use serde_json::Value;

use crate::error::CoreError;
use crate::{sync_pull, MadarCore};

/// The branch setting (a missing key, an older server, means off).
pub(crate) const SETTING: &str = "pick_teller_at_checkout";

/// How old the last successful pull may be for the clock-ins to count.
pub const FRESH_FEED_MINUTES: i64 = 10;

/// A sale on a branch that asks, without a person picked.
pub const SOLD_BY_MISSING: &str = "pick who's serving before taking payment";
/// A sale naming someone who cannot ring sales at this branch.
pub const SOLD_BY_NOT_ELIGIBLE: &str = "the person picked can't ring sales here";

/// How the picker lays its people out.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PickMode {
    /// Clocked-in people first; the rest behind "More".
    Focused,
    /// Everyone at once (no Dawam, a stale feed, or nobody clocked in).
    All,
}

/// One person who can ring sales here.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PickPerson {
    pub user_id: String,
    pub name: String,
    /// Their Dawam clock-in at this branch (RFC 3339) while clocked in.
    pub on_shift_since: Option<String>,
}

/// What the Charge sheet shows above the tender.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TellerPick {
    /// The branch asks: no tender until someone is picked.
    pub required: bool,
    pub mode: PickMode,
    /// Focused: the people on shift; All: everyone.
    pub primary: Vec<PickPerson>,
    /// Focused: everyone else who can ring sales; All: empty.
    pub more: Vec<PickPerson>,
}

impl TellerPick {
    /// Not asked: no section, no gate.
    pub fn off() -> Self {
        TellerPick {
            required: false,
            mode: PickMode::All,
            primary: Vec::new(),
            more: Vec::new(),
        }
    }
}

/// The people who can ring sales here: active `teller` rows whose
/// capabilities at this branch include `orders.create` (owners and managers
/// included, waiters and kitchen not), by name then id.
pub fn eligible(rows: &[Value]) -> Vec<PickPerson> {
    let sells = madar_authz::Cap::OrdersCreate.key();
    let mut people: Vec<PickPerson> = rows
        .iter()
        .filter(|r| r.get("is_active").and_then(Value::as_bool).unwrap_or(true))
        .filter(|r| {
            r.get("capabilities")
                .and_then(Value::as_array)
                .is_some_and(|caps| caps.iter().any(|c| c.as_str() == Some(sells)))
        })
        .filter_map(|r| {
            let text = |k: &str| {
                r.get(k)
                    .and_then(Value::as_str)
                    .filter(|s| !s.trim().is_empty())
            };
            Some(PickPerson {
                user_id: text("user_id").or_else(|| text("id"))?.to_string(),
                name: text("name").unwrap_or_default().to_string(),
                on_shift_since: text("on_shift_since").map(str::to_string),
            })
        })
        .collect();
    people.sort_by(|a, b| {
        a.name
            .to_lowercase()
            .cmp(&b.name.to_lowercase())
            .then_with(|| a.user_id.cmp(&b.user_id))
    });
    people
}

/// The clock-ins are worth trusting: the stream is live, or the last
/// successful pull was under [`FRESH_FEED_MINUTES`] ago. Never pulled is stale.
pub fn feed_fresh(realtime_live: bool, last_ok: Option<DateTime<Utc>>, now: DateTime<Utc>) -> bool {
    realtime_live
        || last_ok.is_some_and(|at| now - at < chrono::Duration::minutes(FRESH_FEED_MINUTES))
}

/// The picker for a branch (`required`), from the teller rows, whether Dawam
/// is on and whether the feed is fresh (TELLER_PICK_SPEC §3.5).
pub fn pick(required: bool, dawam_on: bool, fresh: bool, rows: &[Value]) -> TellerPick {
    if !required {
        return TellerPick::off();
    }
    let people = eligible(rows);
    let (on_shift, rest): (Vec<_>, Vec<_>) = people
        .iter()
        .cloned()
        .partition(|p| p.on_shift_since.is_some());
    if dawam_on && fresh && !on_shift.is_empty() {
        TellerPick {
            required,
            mode: PickMode::Focused,
            primary: on_shift,
            more: rest,
        }
    } else {
        TellerPick {
            required,
            mode: PickMode::All,
            primary: people,
            more: Vec::new(),
        }
    }
}

/// The person a sale names, once the gate has let it through.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Picked {
    pub id: uuid::Uuid,
    /// From the device's teller rows; `None` for someone it holds no row for.
    pub name: Option<String>,
}

impl Picked {
    pub(crate) fn id_string(&self) -> String {
        self.id.to_string()
    }
}

/// A person's name from the synced teller rows (any branch: a teller row's id
/// is the user's), for a sale this device did not ring itself.
pub(crate) fn name_from_rows(conn: &rusqlite::Connection, user_id: &str) -> Option<String> {
    use rusqlite::OptionalExtension;
    conn.query_row(
        "SELECT data FROM sync_rows WHERE type='teller' AND id=?1 LIMIT 1",
        [user_id],
        |r| r.get::<_, String>(0),
    )
    .optional()
    .ok()
    .flatten()
    .and_then(|raw| serde_json::from_str::<Value>(&raw).ok())
    .and_then(|v| {
        v.get("name")
            .and_then(Value::as_str)
            .filter(|n| !n.trim().is_empty())
            .map(str::to_string)
    })
}

impl MadarCore {
    /// Does this branch ask who's serving at checkout? Off until its synced
    /// settings row says so (an older server never does).
    pub(crate) fn pick_teller_required(&self) -> bool {
        self.session_branch_id()
            .ok()
            .and_then(|b| sync_pull::branch_setting(&self.store, &b, SETTING))
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
    }

    /// The stream is live, or the last successful pull of this branch was
    /// recent ([`feed_fresh`]).
    pub(crate) fn pick_feed_fresh(&self) -> bool {
        let last_ok = self
            .session_branch_id()
            .ok()
            .and_then(|b| {
                self.store
                    .kv_get(&format!("{}{b}", sync_pull::K_LAST_OK))
                    .ok()
                    .flatten()
            })
            .and_then(|t| DateTime::parse_from_rfc3339(&t).ok())
            .map(|t| t.with_timezone(&Utc));
        feed_fresh(self.realtime_live(), last_ok, Utc::now())
    }

    fn teller_rows(&self) -> Vec<Value> {
        self.session_branch_id()
            .map(|b| sync_pull::rows_of_type(&self.store, &b, "teller"))
            .unwrap_or_default()
    }

    /// "Who's serving?" for the Charge sheet: whether the branch asks and who
    /// to offer, clocked-in people first when Dawam's data is good enough.
    /// Local rows only; never the network.
    pub fn teller_pick(&self) -> TellerPick {
        let required = self.pick_teller_required();
        if !required {
            return TellerPick::off();
        }
        pick(
            required,
            self.till_dawam_on(),
            self.pick_feed_fresh(),
            &self.teller_rows(),
        )
    }

    /// The gate every money path runs before it commits (checkout, a bill's
    /// settle, an online order's finalize). On a branch that asks, the sale
    /// must name someone who can ring sales here; elsewhere a named person
    /// passes through unchecked (the server judges it) and none is fine.
    pub(crate) fn resolve_sold_by(
        &self,
        sold_by: Option<&str>,
    ) -> Result<Option<Picked>, CoreError> {
        let required = self.pick_teller_required();
        let refuse = |detail: &str| CoreError::Validation {
            field: "sold_by".into(),
            detail: detail.into(),
        };
        let Some(raw) = sold_by.map(str::trim).filter(|s| !s.is_empty()) else {
            return if required {
                Err(refuse(SOLD_BY_MISSING))
            } else {
                Ok(None)
            };
        };
        let Ok(id) = uuid::Uuid::parse_str(raw) else {
            return Err(refuse(SOLD_BY_NOT_ELIGIBLE));
        };
        let wanted = id.to_string();
        if required {
            let person = eligible(&self.teller_rows())
                .into_iter()
                .find(|p| uuid::Uuid::parse_str(&p.user_id).is_ok_and(|u| u == id))
                .ok_or_else(|| refuse(SOLD_BY_NOT_ELIGIBLE))?;
            return Ok(Some(Picked {
                id,
                name: Some(person.name).filter(|n| !n.trim().is_empty()),
            }));
        }
        let name = self
            .store
            .with_conn(|c| Ok(name_from_rows(c, &wanted)))
            .ok()
            .flatten();
        Ok(Some(Picked { id, name }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Duration;
    use serde_json::json;

    fn person(id: &str, name: &str, caps: &[&str], on_shift: Option<&str>) -> Value {
        json!({"id": id, "user_id": id, "name": name, "role": "teller", "is_active": true,
               "permissions": [], "capabilities": caps, "is_owner": false, "on_shift_since": on_shift})
    }

    const SELL: &[&str] = &["orders.create", "payments.take", "till.open"];

    /// Mona and Karim clocked in; Aya not; a waiter and the kitchen never count.
    fn shop() -> Vec<Value> {
        vec![
            person("u-mona", "Mona", SELL, Some("2026-10-30T07:58:00Z")),
            person("u-aya", "Aya", SELL, None),
            person("u-karim", "Karim", SELL, Some("2026-10-30T08:02:00Z")),
            person(
                "u-wael",
                "Wael",
                &["tickets.open", "orders.create.ticket"],
                Some("2026-10-30T08:00:00Z"),
            ),
            person(
                "u-kitchen",
                "Kitchen",
                &["kitchen.display.read"],
                Some("2026-10-30T08:00:00Z"),
            ),
        ]
    }

    fn ids(people: &[PickPerson]) -> Vec<&str> {
        people.iter().map(|p| p.user_id.as_str()).collect()
    }

    #[test]
    fn off_means_no_gate_and_no_list() {
        assert_eq!(pick(false, true, true, &shop()), TellerPick::off());
    }

    #[test]
    fn focused_puts_the_people_on_shift_first_and_the_rest_behind_more() {
        let p = pick(true, true, true, &shop());
        assert!(p.required);
        assert_eq!(p.mode, PickMode::Focused);
        assert_eq!(ids(&p.primary), ["u-karim", "u-mona"]);
        assert_eq!(ids(&p.more), ["u-aya"]);
    }

    #[test]
    fn each_of_the_three_conditions_flips_the_mode_to_all() {
        let all = ["u-aya", "u-karim", "u-mona"];
        // Dawam off (Free, or the org's module is off).
        let p = pick(true, false, true, &shop());
        assert_eq!(
            (p.mode, ids(&p.primary), p.more.len()),
            (PickMode::All, all.to_vec(), 0)
        );
        // A stale feed: the clock-ins may be hours old.
        let p = pick(true, true, false, &shop());
        assert_eq!(
            (p.mode, ids(&p.primary), p.more.len()),
            (PickMode::All, all.to_vec(), 0)
        );
        // Nobody who can ring sales is clocked in (the waiter is, and does not count).
        let nobody: Vec<Value> = shop()
            .into_iter()
            .map(|mut r| {
                if r["capabilities"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|c| c == "orders.create")
                {
                    r["on_shift_since"] = Value::Null;
                }
                r
            })
            .collect();
        let p = pick(true, true, true, &nobody);
        assert_eq!(
            (p.mode, ids(&p.primary), p.more.len()),
            (PickMode::All, all.to_vec(), 0)
        );
        assert!(p.required, "All still asks");
    }

    #[test]
    fn only_active_people_who_can_ring_sales_are_listed() {
        let mut rows = shop();
        let mut owner = person(
            "u-owner",
            "Owner",
            &["orders.create", "orders.void", "reports.read"],
            None,
        );
        owner["is_owner"] = json!(true);
        owner["role"] = json!("org_admin");
        let mut manager = person("u-manager", "Hany", &["orders.create", "orders.void"], None);
        manager["role"] = json!("branch_manager");
        let mut gone = person("u-gone", "Gone", SELL, Some("2026-10-30T08:00:00Z"));
        gone["is_active"] = json!(false);
        // A row from before capabilities rode the feed: unknown means no.
        let legacy = json!({"id": "u-old", "user_id": "u-old", "name": "Old", "role": "teller", "is_active": true,
                            "permissions": ["orders:create"]});
        // Called a teller, but holds no sale grant here: the role name never decides.
        let renamed = person("u-renamed", "Renamed", &["tickets.open"], None);
        rows.extend([owner, manager, gone, legacy, renamed]);
        assert_eq!(
            ids(&eligible(&rows)),
            ["u-aya", "u-manager", "u-karim", "u-mona", "u-owner"]
        );
    }

    #[test]
    fn people_sort_by_name_ignoring_case_then_by_id() {
        let rows = vec![
            person("u-3", "sara", SELL, None),
            person("u-2", "Ahmed", SELL, None),
            person("u-1", "Sara", SELL, None),
            person("u-0", "ahmed", SELL, None),
            person("u-9", "منى", SELL, None),
        ];
        assert_eq!(ids(&eligible(&rows)), ["u-0", "u-2", "u-1", "u-3", "u-9"]);
    }

    #[test]
    fn a_missing_or_empty_clock_in_reads_as_not_on_shift() {
        let mut missing = person("u-a", "A", SELL, None);
        missing.as_object_mut().unwrap().remove("on_shift_since");
        let empty = {
            let mut r = person("u-b", "B", SELL, None);
            r["on_shift_since"] = json!("");
            r
        };
        let null = person("u-c", "C", SELL, None);
        let on = person("u-d", "D", SELL, Some("2026-10-30T08:00:00+02:00"));
        let got = eligible(&[missing, empty, null, on]);
        let shifts: Vec<Option<&str>> = got.iter().map(|p| p.on_shift_since.as_deref()).collect();
        assert_eq!(
            shifts,
            [None, None, None, Some("2026-10-30T08:00:00+02:00")]
        );
        // A row from a server that has no `on_shift_since` at all: never Focused.
        let mut old = shop();
        for r in &mut old {
            r.as_object_mut().unwrap().remove("on_shift_since");
        }
        assert_eq!(pick(true, true, true, &old).mode, PickMode::All);
    }

    #[test]
    fn the_feed_is_fresh_while_the_stream_is_live_or_a_pull_landed_under_ten_minutes_ago() {
        let now = Utc::now();
        assert!(
            feed_fresh(true, None, now),
            "the stream hears every clock-in"
        );
        assert!(!feed_fresh(false, None, now), "never pulled is stale");
        assert!(feed_fresh(false, Some(now - Duration::minutes(9)), now));
        assert!(feed_fresh(false, Some(now - Duration::seconds(599)), now));
        assert!(!feed_fresh(false, Some(now - Duration::minutes(10)), now));
        assert!(!feed_fresh(false, Some(now - Duration::hours(3)), now));
        assert!(feed_fresh(true, Some(now - Duration::hours(3)), now));
    }
}

/// The picker and the gate on a real core: the device's own rows in, the
/// sale's envelope, ledger row and receipt out.
#[cfg(test)]
mod core_tests {
    use super::*;
    use crate::checkout::{CheckoutCommand, CheckoutInput};
    use crate::testkit::{self, Stub, StubResponse, BRANCH, TELLER};
    use serde_json::json;

    const MONA: &str = "00000000-0000-0000-0000-00000000a001";
    const KARIM: &str = "00000000-0000-0000-0000-00000000a002";
    const WAEL: &str = "00000000-0000-0000-0000-00000000a003";
    const CASH: &str = "00000000-0000-0000-0000-0000000000e1";

    fn seed_row(core: &MadarCore, ty: &str, id: &str, data: Value) {
        core.store
            .with_conn(|c| {
                c.execute(
                    "INSERT OR REPLACE INTO sync_rows (branch_id, type, id, seq, data) VALUES (?1, ?2, ?3, 1, ?4)",
                    rusqlite::params![BRANCH, ty, id, data.to_string()],
                )?;
                Ok(())
            })
            .unwrap();
    }

    fn teller(id: &str, name: &str, caps: &[&str], on_shift: Option<&str>) -> Value {
        json!({"id": id, "user_id": id, "name": name, "role": "teller", "is_active": true, "permissions": [],
               "capabilities": caps, "is_owner": false, "on_shift_since": on_shift})
    }

    /// Mona is clocked in; Karim and Sara (signed in) are not; Wael waits tables.
    fn seed_people(core: &MadarCore) {
        let sell = ["orders.create", "payments.take", "till.open"];
        seed_row(
            core,
            "teller",
            MONA,
            teller(MONA, "Mona", &sell, Some("2026-10-30T07:58:00Z")),
        );
        seed_row(core, "teller", KARIM, teller(KARIM, "Karim", &sell, None));
        seed_row(core, "teller", TELLER, teller(TELLER, "Sara", &sell, None));
        seed_row(
            core,
            "teller",
            WAEL,
            teller(
                WAEL,
                "Wael",
                &["tickets.open"],
                Some("2026-10-30T08:00:00Z"),
            ),
        );
    }

    fn ask(core: &MadarCore, on: bool) {
        seed_row(
            core,
            "branch_settings",
            BRANCH,
            json!({"id": BRANCH, SETTING: on}),
        );
    }

    async fn shop(asks: Option<bool>) -> std::sync::Arc<MadarCore> {
        shop_at("http://127.0.0.1:1", asks).await
    }

    async fn shop_at(base: &str, asks: Option<bool>) -> std::sync::Arc<MadarCore> {
        let core = testkit::offline_core(base, "").await;
        core.store
            .kv_put(
                crate::menu::K_PAYMENT_METHODS,
                &format!(r#"[{{"id":"{CASH}","name":"Cash","is_cash":true,"is_active":true,"created_at":"2026-01-01T00:00:00Z"}}]"#),
            )
            .unwrap();
        seed_people(&core);
        if let Some(on) = asks {
            ask(&core, on);
        }
        core.open_till(0, None).await.unwrap();
        core
    }

    fn input(sold_by: Option<&str>) -> CheckoutInput {
        CheckoutInput {
            payment_method_id: CASH.into(),
            amount_tendered_minor: 10_000,
            tip_minor: 0,
            tip_payment_method_id: None,
            customer_name: None,
            notes: None,
            splits: vec![],
            loyalty_customer_id: None,
            dine_in: false,
            customer_id: None,
            loyalty_redemptions: vec![],
            sold_by: sold_by.map(str::to_string),
        }
    }

    async fn ring(
        core: &MadarCore,
        price: i64,
        sold_by: Option<&str>,
    ) -> Result<crate::checkout::ReceiptView, CoreError> {
        core.cart_add(
            None,
            uuid::Uuid::new_v4().to_string(),
            "Latte".into(),
            price,
        )
        .unwrap();
        core.checkout(None, input(sold_by)).await
    }

    /// The queued sale's command and its ledger row.
    fn sale(core: &MadarCore, okey: &str) -> (CheckoutCommand, Value) {
        let op = core
            .store
            .pending()
            .unwrap()
            .into_iter()
            .find(|o| o.id == okey)
            .expect("queued");
        let cmd: CheckoutCommand = serde_json::from_str(&op.payload).unwrap();
        let raw: String = core
            .store
            .with_conn(|c| {
                Ok(
                    c.query_row("SELECT raw FROM ledger_orders WHERE okey=?1", [okey], |r| {
                        r.get(0)
                    })?,
                )
            })
            .unwrap();
        (cmd, serde_json::from_str(&raw).unwrap())
    }

    fn refused(err: CoreError, why: &str) {
        match err {
            CoreError::Validation { field, detail } => {
                assert_eq!((field.as_str(), detail.as_str()), ("sold_by", why));
            }
            other => panic!("expected the sold_by refusal ({why}), got {other:?}"),
        }
    }

    #[tokio::test]
    async fn the_picker_is_read_from_the_device_rows_alone() {
        let core = shop(None).await;
        assert_eq!(
            core.teller_pick(),
            TellerPick::off(),
            "a branch that never said: off"
        );
        ask(&core, false);
        assert_eq!(core.teller_pick(), TellerPick::off());

        ask(&core, true);
        let names = |p: &[PickPerson]| p.iter().map(|x| x.name.clone()).collect::<Vec<_>>();
        // No Dawam: everyone at once.
        let p = core.teller_pick();
        assert_eq!(
            (p.required, p.mode, names(&p.primary), p.more.len()),
            (
                true,
                PickMode::All,
                vec!["Karim".into(), "Mona".into(), "Sara".into()],
                0
            )
        );
        // Dawam on, but this till has never pulled: the clock-ins are not trusted.
        core.store
            .kv_put(crate::till_dawam::K_ORG_MODULES, r#"["dawam"]"#)
            .unwrap();
        assert_eq!(core.teller_pick().mode, PickMode::All);
        // A pull a minute ago: Mona first, the rest behind More.
        let last_ok = format!("{}{BRANCH}", sync_pull::K_LAST_OK);
        core.store
            .kv_put(
                &last_ok,
                &(Utc::now() - chrono::Duration::minutes(1)).to_rfc3339(),
            )
            .unwrap();
        let p = core.teller_pick();
        assert_eq!(
            (p.mode, names(&p.primary), names(&p.more)),
            (
                PickMode::Focused,
                vec!["Mona".into()],
                vec!["Karim".into(), "Sara".into()]
            )
        );
        assert_eq!(
            p.primary[0].on_shift_since.as_deref(),
            Some("2026-10-30T07:58:00Z")
        );
        // Eleven minutes without a pull: stale again, unless the stream is live.
        core.store
            .kv_put(
                &last_ok,
                &(Utc::now() - chrono::Duration::minutes(11)).to_rfc3339(),
            )
            .unwrap();
        assert_eq!(core.teller_pick().mode, PickMode::All);
        core.realtime_connected
            .store(true, std::sync::atomic::Ordering::Relaxed);
        assert_eq!(core.teller_pick().mode, PickMode::Focused);
    }

    /// The picker is a read: it answers from the device's rows and never
    /// asks the server, online or not (the network rule).
    #[tokio::test]
    async fn the_picker_never_touches_the_network() {
        let stub = Stub::start(|_| Some(StubResponse::json(500, json!({"error": "stub"})))).await;
        let core = testkit::online_core(&stub.base, "").await;
        seed_people(&core);
        ask(&core, true);
        core.store
            .kv_put(crate::till_dawam::K_ORG_MODULES, r#"["dawam"]"#)
            .unwrap();
        let before = stub.requests("").len();
        for _ in 0..5 {
            assert!(core.teller_pick().required);
        }
        assert!(core.resolve_sold_by(Some(MONA)).unwrap().is_some());
        assert_eq!(stub.requests("").len(), before, "no request for the picker");
    }

    #[tokio::test]
    async fn a_branch_that_does_not_ask_sells_exactly_as_before() {
        for asks in [None, Some(false)] {
            let core = shop(asks).await;
            let r = ring(&core, 300, None).await.expect("no person needed");
            assert_eq!(r.served_by_name, None);
            let (cmd, row) = sale(&core, &r.local_order_id);
            let env = crate::checkout::order_envelope(&cmd, TELLER, "dev");
            assert!(
                env["request"].get("sold_by").is_none(),
                "the envelope is byte-for-byte what it was: {env}"
            );
            assert!(
                !serde_json::to_string(&cmd).unwrap().contains("sold_by"),
                "nor the queued payload"
            );
            assert!(row.get("sold_by").is_none_or(Value::is_null), "{row}");
            // Someone named anyway rides along, unchecked (the server judges it).
            let r = ring(&core, 300, Some(WAEL))
                .await
                .expect("not checked when the branch does not ask");
            let (cmd, _) = sale(&core, &r.local_order_id);
            assert_eq!(
                crate::checkout::order_envelope(&cmd, TELLER, "dev")["request"]["sold_by"],
                WAEL
            );
        }
    }

    #[tokio::test]
    async fn a_branch_that_asks_refuses_a_sale_without_someone_who_can_ring_sales() {
        let core = shop(Some(true)).await;
        refused(ring(&core, 300, None).await.unwrap_err(), SOLD_BY_MISSING);
        refused(
            core.checkout(None, input(Some(""))).await.unwrap_err(),
            SOLD_BY_MISSING,
        );
        refused(
            core.checkout(None, input(Some(WAEL))).await.unwrap_err(),
            SOLD_BY_NOT_ELIGIBLE,
        );
        refused(
            core.checkout(None, input(Some("not-a-person")))
                .await
                .unwrap_err(),
            SOLD_BY_NOT_ELIGIBLE,
        );
        refused(
            core.checkout(None, input(Some("00000000-0000-0000-0000-00000000dead")))
                .await
                .unwrap_err(),
            SOLD_BY_NOT_ELIGIBLE,
        );
        assert!(
            core.store
                .pending()
                .unwrap()
                .iter()
                .all(|o| o.op_type != "create_order"),
            "nothing was queued"
        );
        assert_eq!(
            core.cart_lines(None).unwrap().len(),
            1,
            "the cart is still in hand"
        );

        // A table's bill and an online order are money too.
        let till = crate::till::current(&core.store).unwrap().unwrap().id;
        let settle = |sold_by: Option<&str>| {
            core.settle_ticket(
                "00000000-0000-0000-0000-0000000000f1".into(),
                till.clone(),
                CASH.into(),
                Some(1_000),
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
                sold_by.map(str::to_string),
            )
        };
        refused(settle(None).await.unwrap_err(), SOLD_BY_MISSING);
        refused(settle(Some(WAEL)).await.unwrap_err(), SOLD_BY_NOT_ELIGIBLE);
        refused(
            core.delivery_finalize("d-1".into(), CASH.into(), None)
                .await
                .unwrap_err(),
            SOLD_BY_MISSING,
        );
        refused(
            core.delivery_finalize("d-1".into(), CASH.into(), Some(WAEL.into()))
                .await
                .unwrap_err(),
            SOLD_BY_NOT_ELIGIBLE,
        );
    }

    #[tokio::test]
    async fn the_picked_person_rides_the_sale_its_row_and_its_receipt() {
        let core = shop(Some(true)).await;
        let r = ring(&core, 300, Some(MONA))
            .await
            .expect("Mona can ring sales");
        assert_eq!(r.served_by_name.as_deref(), Some("Mona"));
        assert_eq!(
            r.teller_name.as_deref(),
            Some("Sara"),
            "the signed-in person is still the teller"
        );
        let (cmd, row) = sale(&core, &r.local_order_id);
        let env = crate::checkout::order_envelope(&cmd, TELLER, "dev");
        assert_eq!(
            env["teller_id"], TELLER,
            "the drawer and the permissions stay Sara's"
        );
        assert_eq!(
            env["request"]["sold_by"], MONA,
            "inside the replay request, as the server reads it"
        );
        assert_eq!(
            (row["sold_by"].as_str(), row["sold_by_name"].as_str()),
            (Some(MONA), Some("Mona"))
        );
        assert_eq!(row["teller_id"], TELLER);
        // A sale queued by an older build (no `sold_by` anywhere) still parses.
        let mut old = serde_json::to_value(&cmd).unwrap();
        old["request"].as_object_mut().unwrap().remove("sold_by");
        let back: CheckoutCommand = serde_json::from_value(old).unwrap();
        assert_eq!(back.request.sold_by, None);
        // The history row names the picked person, queued or not.
        let listed = core.list_till_orders().await.unwrap();
        let mine = listed.iter().find(|o| o.id == r.local_order_id).unwrap();
        assert_eq!(mine.sold_by_name.as_deref(), Some("Mona"));
    }

    #[tokio::test]
    async fn a_settled_bill_carries_the_picked_person() {
        let core = shop(Some(true)).await;
        let till = crate::till::current(&core.store).unwrap().unwrap().id;
        core.cart_add(None, uuid::Uuid::new_v4().to_string(), "Latte".into(), 500)
            .unwrap();
        let fired = core
            .fire_ticket(None, None, None, None, None, None)
            .await
            .unwrap();
        core.settle_ticket(
            fired.ticket_id.clone(),
            till,
            CASH.into(),
            Some(1_000),
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
            Some(KARIM.into()),
        )
        .await
        .expect("Karim can ring sales");
        let op = core
            .store
            .pending()
            .unwrap()
            .into_iter()
            .find(|o| o.op_type == "settle_open_ticket")
            .unwrap();
        let cmd: Value = serde_json::from_str(&op.payload).unwrap();
        assert_eq!(cmd["request"]["sold_by"], KARIM);
        let raw: String = core
            .store
            .with_conn(|c| {
                Ok(c.query_row(
                    "SELECT raw FROM ledger_orders WHERE okey=?1",
                    [&fired.ticket_id],
                    |r| r.get(0),
                )?)
            })
            .unwrap();
        let row: Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(
            (row["sold_by"].as_str(), row["sold_by_name"].as_str()),
            (Some(KARIM), Some("Karim"))
        );
    }

    #[tokio::test]
    async fn an_online_order_charged_here_sends_the_picked_person() {
        let stub = Stub::start(|r| {
            r.path
                .contains("/finalize")
                .then(|| StubResponse::json(500, json!({"error": "stub"})))
        })
        .await;
        let core = shop_at(&stub.base, Some(true)).await;
        let _ = core
            .delivery_finalize(
                "00000000-0000-0000-0000-0000000000d1".into(),
                CASH.into(),
                Some(MONA.into()),
            )
            .await;
        let sent = stub.requests("/delivery");
        let body = sent
            .iter()
            .find(|r| r.path.contains("/finalize"))
            .expect("the finalize went out")
            .json();
        assert_eq!(body["sold_by"], MONA);
        assert_eq!(body["payment_method"], "Cash");
    }

    #[tokio::test]
    async fn a_peers_sale_and_settle_carry_the_picked_person_onto_this_till() {
        let core = shop(Some(true)).await;
        let till = crate::till::current(&core.store).unwrap().unwrap().id;
        let okey = uuid::Uuid::new_v4();
        let mut request = madar_api::models::CreateOrderRequest::new(
            uuid::Uuid::parse_str(BRANCH).unwrap(),
            vec![],
            "Cash".into(),
            uuid::Uuid::parse_str(&till).unwrap(),
        );
        request.idempotency_key = Some(Some(okey));
        request.total_amount = Some(Some(700));
        request.sold_by = Some(Some(uuid::Uuid::parse_str(MONA).unwrap()));
        let cmd = CheckoutCommand {
            request,
            device: None,
            started_by: None,
            approval: None,
        };
        // The peer's device id is a uuid on the wire (the request types it).
        let env =
            crate::checkout::order_envelope(&cmd, KARIM, "00000000-0000-0000-0000-0000000000b2");
        crate::mirror_replay_op(&core.store, &env.to_string());
        let raw: String = core
            .store
            .with_conn(|c| {
                Ok(c.query_row(
                    "SELECT raw FROM ledger_orders WHERE okey=?1",
                    [okey.to_string()],
                    |r| r.get(0),
                )?)
            })
            .unwrap();
        let row: Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(
            (row["sold_by"].as_str(), row["sold_by_name"].as_str()),
            (Some(MONA), Some("Mona"))
        );
        assert_eq!(row["teller_id"], KARIM);

        let ticket = "00000000-0000-0000-0000-0000000000f7";
        let settle = json!({"op": "settle_open_ticket", "ticket_id": ticket, "teller_id": KARIM, "device_id": "peer",
            "request": {"till_id": till, "payment_method": "Cash", "total_amount": 900, "sold_by": KARIM}});
        crate::mirror_replay_op(&core.store, &settle.to_string());
        let raw: String = core
            .store
            .with_conn(|c| {
                Ok(c.query_row(
                    "SELECT raw FROM ledger_orders WHERE okey=?1",
                    [ticket],
                    |r| r.get(0),
                )?)
            })
            .unwrap();
        let row: Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(
            (row["sold_by"].as_str(), row["sold_by_name"].as_str()),
            (Some(KARIM), Some("Karim"))
        );
    }

    #[tokio::test]
    async fn the_counter_chit_names_the_picked_person() {
        let core = shop(Some(true)).await;
        core.cart_add(None, uuid::Uuid::new_v4().to_string(), "Latte".into(), 500)
            .unwrap();
        let brand = crate::receipt::PrinterBrand::Epson;
        let key = core.cart_lines(None).unwrap()[0].key.clone();
        let picked = core
            .cart_kitchen_chit(None, None, None, false, 32, brand, Some(MONA.into()))
            .unwrap();
        assert_eq!(picked.slip.teller.as_deref(), Some("Mona"));
        let line = core
            .cart_line_chit(
                None,
                key.clone(),
                None,
                None,
                false,
                32,
                brand,
                Some(MONA.into()),
            )
            .unwrap();
        assert_eq!(line.chit.teller.as_deref(), Some("Mona"));
        // Nobody picked: the signed-in person, as always.
        let plain = core
            .cart_kitchen_chit(None, None, None, false, 32, brand, None)
            .unwrap();
        assert_eq!(plain.slip.teller.as_deref(), Some("Sara"));
        let line = core
            .cart_line_chit(None, key, None, None, false, 32, brand, None)
            .unwrap();
        assert_eq!(line.chit.teller.as_deref(), Some("Sara"));
    }

    #[tokio::test]
    async fn the_local_z_report_splits_the_sales_by_person() {
        let core = shop(Some(true)).await;
        ring(&core, 1_000, Some(MONA)).await.unwrap();
        ring(&core, 400, Some(MONA)).await.unwrap();
        ring(&core, 700, Some(KARIM)).await.unwrap();
        // Someone the device has no row for (removed since): named "—".
        seed_row(
            &core,
            "teller",
            "00000000-0000-0000-0000-00000000a009",
            teller(
                "00000000-0000-0000-0000-00000000a009",
                "Gone",
                &["orders.create"],
                None,
            ),
        );
        ring(&core, 200, Some("00000000-0000-0000-0000-00000000a009"))
            .await
            .unwrap();
        core.store
            .with_conn(|c| Ok(c.execute("DELETE FROM sync_rows WHERE type='teller' AND id='00000000-0000-0000-0000-00000000a009'", [])?))
            .unwrap();
        let report = core.till_report().await.unwrap();
        let lines: Vec<(Option<&str>, &str, i64, i64)> = report
            .by_person
            .iter()
            .map(|p| {
                (
                    p.person_id.as_deref(),
                    p.name.as_str(),
                    p.order_count,
                    p.total_minor,
                )
            })
            .collect();
        assert_eq!(
            lines,
            vec![
                // The tenders, 14% VAT on top (the session's policy).
                (Some(MONA), "Mona", 2, 1_596),
                (Some(KARIM), "Karim", 1, 798),
                (Some("00000000-0000-0000-0000-00000000a009"), "—", 1, 228),
            ]
        );
        assert_eq!(
            report.by_person.iter().map(|p| p.total_minor).sum::<i64>(),
            report.total_payments_minor
        );

        // A till where nobody was picked: no section at all.
        let core = shop(None).await;
        ring(&core, 1_000, None).await.unwrap();
        assert!(core.till_report().await.unwrap().by_person.is_empty());
    }
}
