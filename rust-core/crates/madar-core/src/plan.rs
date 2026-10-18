//! The organisation's plan at the till (FREEMIUM_SPEC_2026-10-11.md §5).
//!
//! What a plan allows is `madar-plan`'s (madar-shared), asked here and nowhere
//! else: the hosts show or hide a screen from [`MadarCore::entitlements`], the
//! stream is opened or not from the same table, and a server refusal
//! (`plan_feature`, `plan_device_limit`, …) is worded by the crate's own EN/AR
//! messages, so every app says the same thing.
//!
//! Where the plan comes from, freshest first: the branch settings row the sync
//! feed carries (`branch_settings.plan`, adopted with every pull), else what
//! sign-in and `/auth/me` last said (`plan:current`), else **Paid**: an unknown
//! plan, an older server, a device that has never heard, never locks a paying
//! shop out. The server enforces every limit regardless.
//!
//! A downgraded organisation keeps one till per branch selling; the others are
//! `plan_inactive` (the device row the feed carries) and show a blocker
//! instead of the sell screen ([`MadarCore::till_plan_inactive`]).

use madar_plan::{Code, Feature, Plan, Refusal};

use crate::{changes, sync_pull, MadarCore};

/// What sign-in and `/auth/me` last said (`free` | `paid`).
pub(crate) const K_PLAN: &str = "plan:current";

/// What the plan switches on, for a host to show or hide screens from.
/// `features` are the keys of `madar_plan::Feature` the plan HAS
/// (`inventory`, `loyalty`, `online`, `bookings`, `floor`, `kitchen`,
/// `dawam`, `branding`, `basira`); a limit of `None` is unlimited.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EntitlementsView {
    /// `free` | `paid`.
    pub plan: String,
    pub features: Vec<String>,
    /// May this till hold the realtime stream. Free tills poll instead.
    pub realtime: bool,
    pub max_branches: Option<u32>,
    pub max_pos_devices_per_branch: Option<u32>,
    pub max_kds_devices: Option<u32>,
    pub max_waiter_devices: Option<u32>,
    /// The plan switched THIS till off: it is not its branch's active one.
    /// The host shows the "This till isn't active" screen, not the sell screen.
    pub till_inactive: bool,
}

impl EntitlementsView {
    fn of(plan: Plan, till_inactive: bool) -> Self {
        let e = madar_plan::entitlements(plan);
        EntitlementsView {
            plan: plan.as_str().to_string(),
            features: e.features.iter().map(|f| f.as_str().to_string()).collect(),
            realtime: e.realtime,
            max_branches: e.limits.branches,
            max_pos_devices_per_branch: e.limits.pos_devices_per_branch,
            max_kds_devices: e.limits.kds_devices,
            max_waiter_devices: e.limits.waiter_devices,
            // Only Free switches a till off; the flag is the server's, and a
            // Paid org's rows never carry it, but a stale one must not block.
            till_inactive: till_inactive && plan == Plan::Free,
        }
    }
}

/// `plan_feature:kitchen`, `plan_device_limit`, … : the resource a plan refusal
/// travels under in `CoreError::Forbidden` (the code, then `:` and the feature
/// when the refusal is about one). `action` carries the English sentence.
pub(crate) fn refusal_resource(r: &Refusal) -> String {
    match r.feature {
        Some(f) => format!("{}:{}", r.code.as_str(), f.as_str()),
        None => r.code.as_str().to_string(),
    }
}

/// The refusal a `Forbidden` resource names, if it is a plan one.
pub(crate) fn refusal_of_resource(resource: &str) -> Option<Refusal> {
    let (code, feature) = match resource.split_once(':') {
        Some((c, f)) => (c, Some(f)),
        None => (resource, None),
    };
    let code = Code::parse(code)?;
    let feature = match feature {
        Some(f) => Some(Feature::parse(f)?),
        None => None,
    };
    Some(Refusal::new(code, feature))
}

/// A server answer's refusal: the body's `code` (and `feature`) when it is one
/// of the plan's. `None` for anything else.
pub(crate) fn refusal_of_body(body: &str) -> Option<Refusal> {
    let v: serde_json::Value = serde_json::from_str(body).ok()?;
    let code = Code::parse(v.get("code")?.as_str()?)?;
    // An unknown feature (a newer server) still refuses; it just says it
    // generically.
    let feature = v.get("feature").and_then(|f| f.as_str()).and_then(Feature::parse);
    Some(Refusal::new(code, feature))
}

impl MadarCore {
    /// The organisation's plan: the feed's, else sign-in's, else Paid.
    /// Local; no network.
    pub fn current_plan(&self) -> Plan {
        if let Some(branch) = self.plan_branch() {
            if let Some(p) = sync_pull::branch_setting(&self.store, &branch, "plan").and_then(|v| v.as_str().map(Plan::parse)) {
                return p;
            }
        }
        self.store.kv_get(K_PLAN).ok().flatten().map(|p| Plan::parse(&p)).unwrap_or_default()
    }

    /// Ask the server for the plan now (`/auth/me`) and keep it. For a host
    /// with no sync feed (the dashboard app) that wants a plan change, an
    /// upgrade say, to show without a fresh sign-in. Best-effort: a failed
    /// read keeps the last answer. Returns the plan after the read.
    pub async fn refresh_plan(&self) -> Plan {
        use madar_api::apis::auth_api;
        let has_token = {
            let g = self.session.read().unwrap_or_else(|e| e.into_inner());
            g.as_ref().map(|s| s.token.is_some()).unwrap_or(false)
        };
        if has_token {
            if let Ok(me) = auth_api::me(&self.api.config()).await {
                self.remember_plan(me.plan.as_deref());
            }
        }
        self.current_plan()
    }

    /// The branch whose feed row to read: the session's, else the device's.
    fn plan_branch(&self) -> Option<String> {
        self.current_session()
            .and_then(|s| s.branch_id)
            // The stored config, not `device_config()`: that view asks the plan.
            .or_else(|| crate::device::load(&self.store).branch_id)
            .filter(|b| !b.is_empty())
    }

    /// What the plan switches on, and whether this till is switched off.
    /// Local; no network.
    pub fn entitlements(&self) -> EntitlementsView {
        EntitlementsView::of(self.current_plan(), self.till_plan_inactive_flag())
    }

    /// The plan switched this till off (a downgraded organisation keeps one
    /// till per branch selling). The sale/till-open screens show a blocker
    /// instead; the server refuses a new sale or till open from it too
    /// (`plan_till_inactive`). Always `false` on Paid. Local; no network.
    pub fn till_plan_inactive(&self) -> bool {
        self.entitlements().till_inactive
    }

    /// The device row's `plan_inactive`, whatever the plan says.
    fn till_plan_inactive_flag(&self) -> bool {
        let Some(branch) = self.plan_branch() else { return false };
        let me = self.lan_device_id();
        sync_pull::rows_of_type(&self.store, &branch, "device")
            .iter()
            .any(|r| r.get("id").and_then(|v| v.as_str()) == Some(me.as_str()) && r.get("plan_inactive").and_then(|v| v.as_bool()) == Some(true))
    }

    /// Does the plan have `feature`? A key this build does not know is
    /// allowed (a newer server's feature never hides an old build's screen).
    pub fn has_plan_feature(&self, feature: &str) -> bool {
        match Feature::parse(feature) {
            Some(f) => madar_plan::has_feature(self.current_plan(), f),
            None => true,
        }
    }

    /// Keep what sign-in or `/auth/me` said about the plan (`None`: it said
    /// nothing, which is Paid). Announces a change so screens re-read.
    pub(crate) fn remember_plan(&self, plan: Option<&str>) {
        let new = plan.map(Plan::parse).unwrap_or_default();
        let old = self.store.kv_get(K_PLAN).ok().flatten();
        if old.as_deref() == Some(new.as_str()) {
            return;
        }
        let _ = self.store.kv_put(K_PLAN, new.as_str());
        self.store.emit_changes([changes::SYNC, changes::CATALOG]);
    }

    /// A refusal's words in the till's language: `resource` is the
    /// `Forbidden` resource it travels under. `None` when it is not a plan
    /// refusal (the host words it as before).
    pub fn plan_refusal_words(&self, resource: &str) -> Option<String> {
        refusal_of_resource(resource).map(|r| r.message(&self.current_locale()).to_string())
    }

    /// The refusal in EN or AR by the crate's own text, for a code and feature
    /// a host holds (a kitchen screen's activation, say).
    pub fn plan_refusal_message(&self, code: &str, feature: Option<&str>) -> Option<String> {
        let code = Code::parse(code)?;
        let feature = feature.filter(|f| !f.is_empty()).and_then(Feature::parse);
        Some(Refusal::new(code, feature).message(&self.current_locale()).to_string())
    }

    // ── The realtime stream follows the plan ───────────────────────────────

    /// Record the plan the stream was decided for.
    pub(crate) fn note_realtime_plan(&self, plan: Plan) {
        *self.realtime_plan.lock().unwrap_or_else(|e| e.into_inner()) = Some(plan);
    }

    /// The plan holds no stream: make sure none is open, and poll instead.
    /// The poll is the core's own fallback (`ensure_fallback_poll`): a pull
    /// after each acked op (`nudge_sync`) plus a beat from once a minute (busy)
    /// to once every five minutes (idle): `scheduler::FREE_POLL_IDLE_MAX`.
    pub(crate) fn go_without_stream(&self) {
        if let Some(old) = self.realtime.lock().unwrap_or_else(|e| e.into_inner()).take() {
            old.stop();
        }
        self.realtime_connected.store(false, std::sync::atomic::Ordering::Relaxed);
        self.store.emit_changes([changes::SYNC]);
        self.ensure_fallback_poll();
    }

    /// After a pull: if the plan CHANGED since the stream was decided, follow
    /// it. Free → Paid opens the stream the till never had; Paid → Free stops
    /// the one it held (the server would refuse its next reconnect anyway).
    /// Acts only on a change, never on a stream that stopped for another
    /// reason (a 401/403 stays parked until the host re-subscribes).
    pub(crate) fn reconcile_realtime(&self) {
        let plan = self.current_plan();
        {
            let mut seen = self.realtime_plan.lock().unwrap_or_else(|e| e.into_inner());
            match *seen {
                // Not decided yet: the host's `start_realtime` decides first.
                None => return,
                Some(p) if p == plan => return,
                Some(_) => *seen = Some(plan),
            }
        }
        let kind = self.work_kind();
        let topics = crate::realtime::topics_for_role(plan, &kind);
        if topics.is_empty() {
            self.go_without_stream();
            return;
        }
        // Upgraded: open the stream with the listener chain the host installed.
        let listener = self.unified_listener.lock().unwrap_or_else(|e| e.into_inner()).clone();
        let (Some(listener), Ok(branch)) = (listener, self.session_branch_id()) else { return };
        self.open_stream(branch, topics, listener);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testkit::{self, Stub, StubResponse};
    use serde_json::json;

    #[test]
    fn a_refusal_travels_as_its_resource_and_back() {
        let r = Refusal::feature(Feature::Kitchen);
        assert_eq!(refusal_resource(&r), "plan_feature:kitchen");
        assert_eq!(refusal_of_resource("plan_feature:kitchen"), Some(r));
        let l = Refusal::new(Code::DeviceLimit, None);
        assert_eq!(refusal_resource(&l), "plan_device_limit");
        assert_eq!(refusal_of_resource("plan_device_limit"), Some(l));
        assert_eq!(refusal_of_resource("api"), None);
        assert_eq!(refusal_of_resource("ORG_SUSPENDED"), None);
        assert_eq!(refusal_of_resource("plan_feature:nope"), None);
    }

    #[test]
    fn a_server_body_names_its_refusal() {
        let body = json!({"error": "x", "error_ar": "y", "code": "plan_feature", "feature": "kitchen"}).to_string();
        assert_eq!(refusal_of_body(&body), Some(Refusal::feature(Feature::Kitchen)));
        let body = json!({"error": "x", "code": "plan_till_inactive"}).to_string();
        assert_eq!(refusal_of_body(&body), Some(Refusal::new(Code::TillInactive, None)));
        // A feature this build does not know: still a plan refusal, worded generically.
        let body = json!({"error": "x", "code": "plan_feature", "feature": "from_the_future"}).to_string();
        assert_eq!(refusal_of_body(&body), Some(Refusal::new(Code::Feature, None)));
        assert_eq!(refusal_of_body(&json!({"error": "x", "code": "PERIOD_CLOSED"}).to_string()), None);
        assert_eq!(refusal_of_body("<html>"), None);
    }

    #[tokio::test]
    async fn the_plan_is_paid_until_something_says_otherwise() {
        let stub = Stub::start(|_| None::<StubResponse>).await;
        let core = testkit::online_core(&stub.base, "").await;
        assert_eq!(core.current_plan(), Plan::Paid, "nothing known: a paying shop is never locked out");
        let e = core.entitlements();
        assert_eq!(e.plan, "paid");
        assert!(e.realtime && !e.till_inactive);
        for f in ["inventory", "loyalty", "online", "bookings", "floor", "kitchen", "dawam", "branding", "basira"] {
            assert!(e.features.iter().any(|x| x == f), "{f}");
            assert!(core.has_plan_feature(f));
        }
        assert!(core.has_plan_feature("from_the_future"), "an unknown feature never hides a screen");

        core.remember_plan(Some("free"));
        let e = core.entitlements();
        assert_eq!((e.plan.as_str(), e.realtime), ("free", false));
        assert_eq!(e.features, vec!["floor".to_string()]);
        assert_eq!((e.max_branches, e.max_pos_devices_per_branch, e.max_kds_devices), (Some(1), Some(1), Some(0)));
        assert!(core.has_plan_feature("floor"));
        assert!(!core.has_plan_feature("kitchen"));

        // Sign-in saying nothing is Paid; an unknown plan is Paid.
        core.remember_plan(None);
        assert_eq!(core.current_plan(), Plan::Paid);
        core.remember_plan(Some("platinum"));
        assert_eq!(core.current_plan(), Plan::Paid);
    }

    #[tokio::test]
    async fn the_feed_outranks_what_sign_in_said() {
        let stub = Stub::start(|_| None::<StubResponse>).await;
        let core = testkit::online_core(&stub.base, "").await;
        core.remember_plan(Some("paid"));
        let branch = core.sync_branch().expect("a branch");
        let put = |plan: serde_json::Value| {
            core.store
                .with_conn(|c| {
                    c.execute(
                        "INSERT OR REPLACE INTO sync_rows(type,id,branch_id,seq,data) VALUES('branch_settings',?1,?1,1,?2)",
                        rusqlite::params![branch, json!({ "id": branch, "plan": plan }).to_string()],
                    )?;
                    Ok(())
                })
                .unwrap();
        };
        put(json!("free"));
        assert_eq!(core.current_plan(), Plan::Free, "the feed says Free over a Paid sign-in");
        put(json!("paid"));
        assert_eq!(core.current_plan(), Plan::Paid);
        // A row without the field (an older server) leaves sign-in's answer standing.
        put(serde_json::Value::Null);
        core.remember_plan(Some("free"));
        assert_eq!(core.current_plan(), Plan::Free, "no plan in the feed: what sign-in said");
        core.remember_plan(None);
        assert_eq!(core.current_plan(), Plan::Paid, "and no answer anywhere is Paid, never a lock");
    }

    #[tokio::test]
    async fn only_a_free_till_the_plan_switched_off_is_inactive() {
        let stub = Stub::start(|_| None::<StubResponse>).await;
        let core = testkit::online_core(&stub.base, "").await;
        let branch = core.sync_branch().expect("a branch");
        let me = core.lan_device_id();
        let device = |id: &str, inactive: bool| {
            core.store
                .with_conn(|c| {
                    c.execute(
                        "INSERT OR REPLACE INTO sync_rows(type,id,branch_id,seq,data) VALUES('device',?1,?2,1,?3)",
                        rusqlite::params![id, branch, json!({ "id": id, "code": "T1", "kind": "pos", "plan_inactive": inactive }).to_string()],
                    )?;
                    Ok(())
                })
                .unwrap();
        };
        device("someone-else", true);
        core.remember_plan(Some("free"));
        assert!(!core.till_plan_inactive(), "another till being switched off says nothing about this one");
        device(&me, true);
        assert!(core.till_plan_inactive());
        assert!(core.entitlements().till_inactive);
        // A stale flag on a Paid organisation never blocks selling.
        core.remember_plan(Some("paid"));
        assert!(!core.till_plan_inactive());
        core.remember_plan(Some("free"));
        device(&me, false);
        assert!(!core.till_plan_inactive());
    }

    #[tokio::test]
    async fn refusals_are_worded_in_the_tills_language() {
        let stub = Stub::start(|_| None::<StubResponse>).await;
        let core = testkit::online_core(&stub.base, "").await;
        core.set_locale("en".into());
        assert_eq!(core.plan_refusal_words("plan_feature:kitchen").as_deref(), Some("Kitchen screens are on the paid plan."));
        assert_eq!(core.plan_refusal_words("ORG_SUSPENDED"), None);
        core.set_locale("ar".into());
        assert_eq!(core.plan_refusal_words("plan_feature:kitchen").as_deref(), Some("شاشات المطبخ متاحة في الخطة المدفوعة."));
        assert_eq!(
            core.plan_refusal_message("plan_till_inactive", None).as_deref(),
            Some(Refusal::new(Code::TillInactive, None).ar())
        );
        assert_eq!(core.plan_refusal_message("nope", None), None);
    }

    // ── The stream follows the plan ────────────────────────────────────────

    #[derive(Default)]
    struct Quiet;
    impl crate::realtime::EventListener for Quiet {
        fn on_event(&self, _: crate::realtime::RealtimeEvent) {}
        fn on_connection_changed(&self, _: bool) {}
    }
    impl crate::realtime::RealtimePlayer for Quiet {
        fn play_ping(&self) {}
        fn post_notification(&self, _: String, _: String, _: String) {}
        fn haptic(&self) {}
    }

    async fn waited(stub: &Stub, ms: u64) -> usize {
        tokio::time::sleep(std::time::Duration::from_millis(ms)).await;
        stub.requests("/realtime/stream").len()
    }

    #[tokio::test]
    async fn a_free_till_opens_no_stream_and_polls_instead() {
        let stub = Stub::start(|r| r.path.starts_with("/realtime/stream").then(|| StubResponse::text(200, ""))).await;
        let core = testkit::online_core(&stub.base, "").await;
        core.set_manual_scheduling(true);
        core.remember_plan(Some("free"));
        core.start_realtime(Box::new(Quiet), Box::new(Quiet)).await.unwrap();
        assert_eq!(waited(&stub, 300).await, 0, "Free holds no stream: nothing is even asked for");
        assert!(!core.realtime_live());
        assert!(core.take_poll_wanted(), "the idle poll is what keeps a stream-less till fresh");
        // The pull after an acked op is the same nudge a paid till uses.
        core.nudge_sync();
        assert_eq!(core.take_nudges(), 1);
    }

    #[tokio::test]
    async fn a_paid_till_still_opens_its_stream() {
        let stub = Stub::start(|r| r.path.starts_with("/realtime/stream").then(|| StubResponse::text(200, ""))).await;
        let core = testkit::online_core(&stub.base, "").await;
        core.remember_plan(Some("paid"));
        core.start_realtime(Box::new(Quiet), Box::new(Quiet)).await.unwrap();
        assert!(waited(&stub, 400).await >= 1, "Paid opens the stream exactly as before");
    }

    #[tokio::test]
    async fn an_upgrade_opens_the_stream_and_a_downgrade_closes_it() {
        let stub = Stub::start(|r| r.path.starts_with("/realtime/stream").then(|| StubResponse::text(200, ""))).await;
        let core = testkit::online_core(&stub.base, "").await;
        core.set_manual_scheduling(true);
        core.remember_plan(Some("free"));
        core.start_realtime(Box::new(Quiet), Box::new(Quiet)).await.unwrap();
        assert_eq!(waited(&stub, 200).await, 0);

        // The owner upgrades; the next pull brings the plan.
        core.remember_plan(Some("paid"));
        core.reconcile_realtime();
        assert!(waited(&stub, 400).await >= 1, "an upgraded till opens the stream without a restart");

        // Nothing changed: a pull does not reopen or restart anything.
        let n = stub.requests("/realtime/stream").len();
        core.reconcile_realtime();
        core.reconcile_realtime();
        assert!(waited(&stub, 100).await <= n + 1, "no change, no new stream");

        // Downgraded: the stream stops, the poll takes over.
        core.take_poll_wanted();
        core.remember_plan(Some("free"));
        core.reconcile_realtime();
        assert!(core.take_poll_wanted());
        assert!(core.realtime.lock().unwrap().is_none(), "the stream is gone");
    }
}
