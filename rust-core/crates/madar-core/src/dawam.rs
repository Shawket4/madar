//! Dawam — the staff app's business logic (Dawam Target Spec).
//!
//! The Flutter app is only screens. Everything it shows comes from
//! [`MadarCore::dawam_snapshot`], built here from a local mirror of the server
//! (one SQLite table per server resource, `schema::step9_dawam`), and
//! everything it does goes through [`MadarCore::dawam_do`].
//!
//! Offline (APP-8, CL-10): clocking in and out, covers and the 15-minute pings
//! go into the core's outbox, the same durable queue the POS drains, and are
//! sent when the connection comes back. Each carries the last server time the
//! phone saw and the time since boot, so the server dates it (CL-11); the
//! phone's own clock is never used. Requests, approvals and payroll need a
//! connection and say so.
//!
//! The server decides every figure (AT-3): the snapshot passes the server's
//! numbers through and only derives what is a pure reading of them (who is
//! on now, what waits on me, which days are absent past their end).

use std::collections::{BTreeMap, HashMap, HashSet};

use chrono::{DateTime, Datelike, Duration, NaiveDate, NaiveTime, TimeZone, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::error::CoreError;
use crate::{i18n, store, MadarCore};

/// The mirror tables (`schema::step9_dawam`). Append only.
pub(crate) const TABLES: &[&str] = &[
    "dawam_branches",
    "dawam_people",
    "dawam_work_shifts",
    "dawam_roster",
    "dawam_open_shifts",
    "dawam_holidays",
    "dawam_attendance",
    "dawam_requests",
    "dawam_swaps",
    "dawam_advances",
    "dawam_flags",
    "dawam_adjustments",
    "dawam_expenses",
    "dawam_notifications",
    "dawam_preview",
    "dawam_payslips",
    "dawam_periods",
    "dawam_suggestions",
    "dawam_coverable",
];

/// Outbox op types (the drain sends them to `/staff/*`, not `/sync/replay`).
pub(crate) const OP_PREFIX: &str = "dawam_";
/// The last (server time, time since boot, wall time) the phone saw.
const K_ANCHOR: &str = "dawam:anchor";
const K_FIX: &str = "dawam:fix";
/// Sent within this long of being queued, a punch goes as live, not offline.
const LIVE_MS: i64 = 30_000;

// ── time since boot (CL-11) ───────────────────────────────────────────────

/// Milliseconds since the phone booted, counting deep sleep: `CLOCK_BOOTTIME`
/// on Android, `CLOCK_MONOTONIC` on Apple (which keeps counting asleep).
fn boot_ms() -> i64 {
    #[cfg(any(target_os = "linux", target_os = "android"))]
    const CLOCK: libc::clockid_t = libc::CLOCK_BOOTTIME;
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    const CLOCK: libc::clockid_t = libc::CLOCK_MONOTONIC;
    #[cfg(any(target_os = "linux", target_os = "android", target_os = "macos", target_os = "ios"))]
    {
        let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 };
        // SAFETY: `ts` is a valid out-pointer for the duration of the call.
        if unsafe { libc::clock_gettime(CLOCK, &mut ts) } == 0 {
            // 32-bit Android has a 32-bit `time_t`.
            #[allow(clippy::unnecessary_cast)]
            return ts.tv_sec as i64 * 1000 + ts.tv_nsec as i64 / 1_000_000;
        }
    }
    // ponytail: elsewhere (Windows desktop) process uptime; a restart reads as a reboot.
    static START: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
    START.get_or_init(std::time::Instant::now).elapsed().as_millis() as i64
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq)]
struct Anchor {
    server_ms: i64,
    boot_ms: i64,
    wall_ms: i64,
}

/// What the server needs to date an event recorded now (`OfflineStamp`).
fn stamp(anchor: Option<Anchor>, boot: i64, wall: i64, gps_time: Option<&str>) -> Value {
    let Some(a) = anchor else {
        // Never saw the server: only the satellites can date it.
        return json!({ "server_time": ms_rfc3339(wall), "elapsed_ms": 0, "rebooted": true, "gps_time": gps_time });
    };
    // A smaller uptime is a reboot; so is the boot moment moving (wall − uptime),
    // which also catches a restart that has since run longer than before.
    // ponytail: a wall-clock change also moves it, which only makes it "unverified".
    let rebooted = boot < a.boot_ms || ((wall - boot) - (a.wall_ms - a.boot_ms)).abs() > 10 * 60_000;
    json!({
        "server_time": ms_rfc3339(a.server_ms),
        "elapsed_ms": if rebooted { 0 } else { boot - a.boot_ms },
        "rebooted": rebooted,
        "gps_time": gps_time,
    })
}

fn ms_rfc3339(ms: i64) -> String {
    Utc.timestamp_millis_opt(ms).single().unwrap_or_else(Utc::now).to_rfc3339()
}

fn wall_ms() -> i64 {
    Utc::now().timestamp_millis()
}

// ── the phone's position ──────────────────────────────────────────────────

/// A GPS reading from the host (the one thing the core can't read itself).
#[derive(Deserialize, Serialize, Clone, Debug, Default)]
pub struct DawamFix {
    pub latitude: f64,
    pub longitude: f64,
    #[serde(default)]
    pub accuracy: Option<f64>,
    /// The OS's mock-location marker (CL-9).
    #[serde(default)]
    pub mock: bool,
    /// The fix's own satellite time, RFC 3339.
    #[serde(default)]
    pub gps_time: Option<String>,
    #[serde(default)]
    pub battery: Option<i64>,
}

fn haversine_m(a: (f64, f64), b: (f64, f64)) -> f64 {
    let (la1, lo1, la2, lo2) = (a.0.to_radians(), a.1.to_radians(), b.0.to_radians(), b.1.to_radians());
    let h = ((la2 - la1) / 2.0).sin().powi(2) + la1.cos() * la2.cos() * ((lo2 - lo1) / 2.0).sin().powi(2);
    2.0 * 6_371_000.0 * h.sqrt().asin()
}

// ── what the screens get ──────────────────────────────────────────────────

#[derive(Serialize, Debug, Default)]
pub struct Snapshot {
    pub me: String,
    pub role: String,
    pub org_name: String,
    /// The server's time now (the phone's clock corrected by the skew).
    pub now: String,
    pub online: bool,
    /// Punches and pings waiting for a connection.
    pub queued: u32,
    /// Queued actions the server refused, in its words.
    pub stuck: Vec<String>,
    pub can_manage: bool,
    pub can_payroll: bool,
    /// Which manager tabs show, from `caps` (PM-4).
    pub tabs: ManageTabs,
    pub caps: Vec<String>,
    pub my_branches: Vec<String>,
    /// When the mirror last heard from the server (epoch ms; 0 = never).
    pub fetched_at: i64,
    pub branches: Vec<BranchV>,
    pub templates: Vec<TplV>,
    pub people: Vec<PersonV>,
    pub shifts: Vec<ShiftV>,
    pub my_now: Vec<String>,
    pub active_shift: Option<String>,
    pub coverable: Vec<String>,
    pub flags: Vec<FlagV>,
    pub open_flags: Vec<String>,
    pub requests: Vec<ReqV>,
    pub inbox: Vec<String>,
    pub adjustments: Vec<AdjV>,
    pub adj_inbox: Vec<String>,
    pub advances: Vec<AdvanceV>,
    pub expenses: Vec<ExpenseV>,
    pub notices: Vec<NoticeV>,
    pub period: PeriodV,
    pub history: Vec<PeriodV>,
    pub slips: Vec<SlipV>,
    /// Per person: the cap on outstanding advances, and what is outstanding (AV-5).
    pub advance_cap: BTreeMap<String, i64>,
    pub outstanding: BTreeMap<String, i64>,
    pub suggestions: Vec<SuggestionV>,
    pub holidays: Vec<HolidayV>,
    /// Labour-limit warnings (RU-13): `user|week_start` → core i18n keys + args.
    pub warnings: BTreeMap<String, Vec<(String, Value)>>,
    pub settings: SettingsV,
    /// The org's modules (`pos`, `dawam`, PS-2).
    pub modules: Vec<String>,
    /// On shift with the battery at 15% or less: tell them to charge (CL-12).
    pub charge_phone: bool,
    /// Coverage needs per branch (SC-13): `source` grid|pos|pattern, `needs`, `derived`.
    pub coverage: BTreeMap<String, Value>,
    /// Inside the fence of the branch I work at now, from the last fix.
    pub inside: Option<bool>,
    pub distance_m: Option<f64>,
}

#[derive(Serialize, Debug, Default)]
pub struct SettingsV {
    pub overtime: String,
    pub ot_day: f64,
    pub ot_night: f64,
    pub holiday_mult: f64,
    pub advance_cap_pct: f64,
    pub absence_days: f64,
    pub period_start_day: i64,
    /// My ceiling on a bonus or deduction before it waits for the owner.
    pub adjustment_limit: Option<i64>,
    /// The owner saved the rules; until then nobody clocks in (RU-1, DSH-6).
    pub rules_saved: bool,
}

#[derive(Serialize, Debug)]
pub struct BranchV {
    pub id: String,
    pub name: String,
    pub radius: i64,
}

#[derive(Serialize, Debug)]
pub struct TplV {
    pub id: String,
    pub branch: String,
    pub name: String,
    pub start: i64,
    pub end: i64,
    pub grace: i64,
    pub window: i64,
}

#[derive(Serialize, Debug)]
pub struct PersonV {
    pub id: String,
    pub name: String,
    pub phone: String,
    pub role: String,
    pub branches: Vec<String>,
    pub salary: i64,
    pub gender: String,
    pub hired: String,
    pub pay: String,
    pub account: String,
    pub device: String,
    pub device_since: Option<String>,
    pub pref_time: Option<String>,
    /// ISO weekdays (Mon = 1 … Sun = 7).
    pub cant_work: Vec<i64>,
}

#[derive(Serialize, Debug, Clone, Default)]
pub struct ShiftV {
    pub id: String,
    pub emp: Option<String>,
    pub tpl: String,
    pub date: String,
    pub published: bool,
    pub changed: bool,
    pub cover_by: Option<String>,
    pub in_at: Option<String>,
    pub out_at: Option<String>,
    pub in_method: Option<String>,
    pub out_method: Option<String>,
    pub punch_reason: Option<String>,
    pub leave: Option<String>,
    pub half_leave: bool,
    pub mission: bool,
    pub late_until: Option<i64>,
    pub early_from: Option<i64>,
    pub excuse_min: i64,
    pub excuse_paid: bool,
    pub tracking_off: bool,
    pub time_unverified: bool,
    /// The server's lateness for this shift, in minutes.
    pub late_minutes: i64,
    pub absent: bool,
    /// A punch on it is still in the outbox.
    pub queued: bool,
}

#[derive(Serialize, Debug)]
pub struct FlagV {
    pub id: String,
    pub kind: String,
    pub emp: String,
    pub shift: Option<String>,
    pub at: String,
    pub minutes_away: i64,
    pub resolution: Option<String>,
    /// Time away at the person's minute rate, nearest 5 EGP (CL-7), from the server.
    pub suggested: i64,
}

#[derive(Serialize, Debug, Default, Clone)]
pub struct ReqV {
    pub id: String,
    pub kind: String,
    pub emp: String,
    pub created: String,
    pub status: String,
    pub from: Option<String>,
    pub to: Option<String>,
    pub half: bool,
    pub time: Option<i64>,
    pub time2: Option<i64>,
    pub note: String,
    pub amount: i64,
    pub paid: Option<bool>,
    pub shift: Option<String>,
    pub shift2: Option<String>,
    pub peer: Option<String>,
    pub installments: i64,
    pub minutes: i64,
    pub to_owner: bool,
    pub decided_by: Option<String>,
    pub decision_note: Option<String>,
}

#[derive(Serialize, Debug)]
pub struct AdjV {
    pub id: String,
    pub emp: String,
    pub bonus: bool,
    pub amount: i64,
    pub pct: Option<f64>,
    /// What it comes to: a % of salary resolved against the person's salary.
    pub value: i64,
    pub reason: String,
    pub by: String,
    pub at: String,
    pub period: String,
    pub recurring: bool,
    pub status: String,
}

#[derive(Serialize, Debug)]
pub struct AdvanceV {
    pub id: String,
    pub emp: String,
    pub amount: i64,
    pub installments: i64,
    pub date: String,
    pub by: String,
    pub collected: i64,
}

#[derive(Serialize, Debug)]
pub struct ExpenseV {
    pub id: String,
    pub emp: String,
    pub amount: i64,
    pub date: String,
    pub branch: String,
    pub purpose: String,
    pub by: String,
    pub via: String,
}

#[derive(Serialize, Debug)]
pub struct NoticeV {
    pub id: String,
    pub text: String,
    pub at: String,
    pub read: bool,
}

#[derive(Serialize, Debug, Default, Clone)]
pub struct PeriodV {
    pub id: Option<String>,
    pub start: String,
    pub end: String,
    /// `open` · `approved` · `paid`
    pub status: String,
    /// Who is marked paid, and how (PAY-7).
    pub paid_by: BTreeMap<String, String>,
}

#[derive(Serialize, Debug, Clone)]
pub struct LineV {
    pub key: String,
    pub en: String,
    pub ar: String,
    pub amount: i64,
    /// Rule-made: waivable, never deletable (AD-7).
    pub rule: bool,
    /// The adjustment behind a manual line: deletable until approval.
    pub manual: Option<String>,
    /// Waived: shown struck through, counted for nothing (AD-8).
    pub waived: bool,
}

#[derive(Serialize, Debug, Clone)]
pub struct SlipV {
    pub emp: String,
    pub start: String,
    pub end: String,
    pub lines: Vec<LineV>,
    pub net: i64,
    pub carry_out: i64,
    pub collected: BTreeMap<String, i64>,
    /// The frozen payslip, not the live estimate (PAY-9).
    pub frozen: bool,
}

#[derive(Serialize, Debug)]
pub struct SuggestionV {
    pub id: String,
    pub branch: String,
    pub date: String,
    pub text: String,
    pub confidence: i64,
    pub shift: Option<String>,
    pub emp: String,
    pub tpl: String,
    pub by_default: bool,
}

#[derive(Serialize, Debug)]
pub struct HolidayV {
    pub date: String,
    pub en: String,
    pub ar: String,
    pub decision: Option<String>,
}

// ── what the screens do ───────────────────────────────────────────────────

/// Every action the app can take. The ids are the snapshot's.
#[derive(Deserialize, Debug)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum Act {
    ClockIn { shift: String, fix: Option<DawamFix>, #[serde(default)] tracking_off: bool },
    ClockOut { fix: Option<DawamFix> },
    Cover { shift: String, fix: Option<DawamFix> },
    PunchFor { shift: String, reason: String },
    File {
        kind: String,
        #[serde(default)] from: Option<String>,
        #[serde(default)] to: Option<String>,
        #[serde(default)] half: bool,
        #[serde(default)] time: Option<i64>,
        #[serde(default)] time2: Option<i64>,
        #[serde(default)] note: String,
        #[serde(default)] amount: i64,
        #[serde(default)] installments: Option<i64>,
        #[serde(default)] shift: Option<String>,
        #[serde(default)] shift2: Option<String>,
        #[serde(default)] peer: Option<String>,
    },
    PeerAnswer { req: String, yes: bool },
    Cancel { req: String },
    Decide {
        req: String,
        approve: bool,
        #[serde(default)] paid: Option<bool>,
        #[serde(default)] amount: Option<i64>,
        #[serde(default)] installments: Option<i64>,
        #[serde(default)] note: Option<String>,
    },
    /// `excuse_paid` · `excuse_unpaid` · `deduct` · `revoke` · `confirm` · `ignore`
    Resolve { flag: String, how: String, #[serde(default)] deduct: i64 },
    AddAdjustment {
        emp: String,
        bonus: bool,
        #[serde(default)] amount: i64,
        reason: String,
        #[serde(default)] pct: Option<f64>,
        #[serde(default)] recurring: bool,
    },
    DecideAdj { adj: String, yes: bool },
    DeleteAdj { adj: String },
    StopAdj { adj: String },
    Waive { key: String, reason: String },
    RecordAdvance { emp: String, amount: i64, installments: i64 },
    LogExpense { emp: String, amount: i64, purpose: String, via: String },
    SetDay { emp: String, date: String, tpl: Option<String> },
    MoveShift { shift: String, day: String, tpl: String },
    Assign { shift: String, emp: Option<String> },
    PostOpen { branch: String, date: String, tpl: String },
    Claim { shift: String },
    Publish { branch: String, week: String },
    AcceptSuggestion { id: String },
    RejectSuggestion { id: String },
    DecideHoliday { date: String, decision: String },
    SetPrefs { time: Option<String>, cant: Vec<i64> },
    /// The weekly coverage grid for a branch (SC-13): `[{day_of_week, band_start, band_end, staff}]`.
    SetCoverage { branch: String, needs: Value },
    ReadAll,
    /// Signing out: the server forgets this phone and its pushes (APP-6).
    SignOut,
    ApprovePayroll,
    ReopenPayroll,
    MarkPaid { emp: String, method: String },
}

impl Act {
    /// Works offline: queued and sent later (APP-8).
    fn queueable(&self) -> bool {
        matches!(self, Act::ClockIn { .. } | Act::ClockOut { .. } | Act::Cover { .. } | Act::PunchFor { .. })
    }
}

// ── JSON helpers ──────────────────────────────────────────────────────────

fn s(v: &Value, k: &str) -> String {
    v.get(k).and_then(Value::as_str).unwrap_or_default().to_string()
}
fn so(v: &Value, k: &str) -> Option<String> {
    v.get(k).and_then(Value::as_str).map(str::to_string)
}
fn i(v: &Value, k: &str) -> i64 {
    match v.get(k) {
        Some(Value::Number(n)) => n.as_f64().map_or(0, |f| f.round() as i64),
        Some(Value::String(x)) => x.parse::<f64>().map_or(0, |f| f.round() as i64),
        _ => 0,
    }
}
fn f(v: &Value, k: &str) -> f64 {
    match v.get(k) {
        Some(Value::Number(n)) => n.as_f64().unwrap_or(0.0),
        Some(Value::String(x)) => x.parse().unwrap_or(0.0),
        _ => 0.0,
    }
}
fn b(v: &Value, k: &str) -> bool {
    v.get(k).and_then(Value::as_bool).unwrap_or(false)
}
fn arr<'a>(v: &'a Value, k: &str) -> &'a [Value] {
    v.get(k).and_then(Value::as_array).map_or(&[], Vec::as_slice)
}
fn date(v: &Value, k: &str) -> Option<NaiveDate> {
    v.get(k).and_then(Value::as_str).and_then(|x| NaiveDate::parse_from_str(&x[..x.len().min(10)], "%Y-%m-%d").ok())
}
fn at(v: &Value, k: &str) -> Option<DateTime<Utc>> {
    v.get(k).and_then(Value::as_str).and_then(|x| DateTime::parse_from_rfc3339(x).ok()).map(|d| d.with_timezone(&Utc))
}
/// Every instant the screens get is written in the branch's zone (AT-1):
/// `2026-09-23T09:02:00+03:00`, never the server's `Z` or the phone's zone.
/// The app shows the wall-clock part as it is, so a phone set to another
/// zone still reads the branch's time. Plain dates are left alone.
pub(crate) fn in_branch_zone(v: &mut Value, tz: &chrono_tz::Tz) {
    match v {
        Value::String(x) if x.len() >= 20 && x.as_bytes().get(10) == Some(&b'T') => {
            if let Ok(d) = DateTime::parse_from_rfc3339(x) {
                *x = d.with_timezone(tz).to_rfc3339_opts(chrono::SecondsFormat::AutoSi, false);
            }
        }
        Value::Array(a) => a.iter_mut().for_each(|x| in_branch_zone(x, tz)),
        Value::Object(o) => o.values_mut().for_each(|x| in_branch_zone(x, tz)),
        _ => {}
    }
}

/// `HH:MM[:SS]` → minute of the day.
fn minute_of(x: &str) -> Option<i64> {
    let mut p = x.split(':');
    Some(p.next()?.parse::<i64>().ok()? * 60 + p.next()?.parse::<i64>().ok()?)
}
fn hhmm(m: i64) -> String {
    format!("{:02}:{:02}", m / 60, m % 60)
}
/// The Saturday a date's week starts on (the roster's week).
pub(crate) fn week_start(d: NaiveDate) -> NaiveDate {
    d - Duration::days((d.weekday().num_days_from_monday() as i64 + 2) % 7)
}
fn shift_id(user: &str, d: NaiveDate, tpl: &str) -> String {
    format!("{user}|{d}|{tpl}")
}
fn tail(id: &str) -> &str {
    id.rsplit('|').next().unwrap_or(id)
}
fn needs_connection(locale: &str) -> CoreError {
    CoreError::Offline { detail: i18n::tr(locale, "staff.needs_connection") }
}

/// The server's request kinds and the screens' names for them.
const KINDS: &[(&str, &str)] = &[
    ("leave", "leave"),
    ("late_arrival", "lateArrival"),
    ("early_departure", "earlyDeparture"),
    ("excuse", "excuse"),
    ("mission", "mission"),
    ("correction", "correction"),
];
fn kind_of_server(k: &str) -> Option<&'static str> {
    KINDS.iter().find(|(srv, _)| *srv == k).map(|(_, ui)| *ui)
}
fn kind_to_server(k: &str) -> Option<&'static str> {
    KINDS.iter().find(|(_, ui)| *ui == k).map(|(srv, _)| *srv)
}
fn status_of(x: &str) -> &'static str {
    match x {
        "awaiting_peer" => "awaitingPeer",
        "approved" | "filled" | "settled" => "approved",
        "rejected" => "rejected",
        "cancelled" => "cancelled",
        _ => "pending",
    }
}
fn method_of(m: &str) -> Option<String> {
    Some(
        match m {
            "mobile_gps" => "app",
            "manual" => "manager",
            "auto" | "offline" | "cover" | "till" | "kiosk" | "correction" => m,
            _ => return None,
        }
        .to_string(),
    )
}
fn role_of(r: &str) -> &'static str {
    match r {
        "owner" => "owner",
        "manager" => "manager",
        _ => "employee",
    }
}

// ── the mirror ────────────────────────────────────────────────────────────

/// One row of a mirror table.
struct Row {
    id: String,
    user_id: Option<String>,
    branch_id: Option<String>,
    on_date: Option<String>,
    status: Option<String>,
    data: Value,
}

impl Row {
    fn new(id: impl Into<String>, data: &Value) -> Self {
        Row { id: id.into(), user_id: so(data, "employee_id"), branch_id: so(data, "branch_id"), on_date: None, status: so(data, "status"), data: data.clone() }
    }
    fn date(mut self, d: Option<String>) -> Self {
        self.on_date = d;
        self
    }
}

/// Everything fetched in one refresh, by table.
#[derive(Default)]
struct Mirror {
    tables: HashMap<&'static str, Vec<Row>>,
    meta: Vec<(&'static str, Value)>,
}

impl Mirror {
    fn put(&mut self, t: &'static str, r: Row) {
        let rows = self.tables.entry(t).or_default();
        if !rows.iter().any(|x| x.id == r.id) {
            rows.push(r);
        }
    }
}

fn read_table(c: &rusqlite::Connection, t: &str) -> Result<Vec<Value>, CoreError> {
    let mut st = c.prepare(&format!("SELECT data FROM {t} ORDER BY rowid"))?;
    let rows = st.query_map([], |r| r.get::<_, String>(0))?;
    Ok(rows.filter_map(Result::ok).filter_map(|x| serde_json::from_str(&x).ok()).collect())
}

fn read_meta(c: &rusqlite::Connection, k: &str) -> Value {
    c.query_row("SELECT data FROM dawam_meta WHERE k = ?1", [k], |r| r.get::<_, String>(0))
        .ok()
        .and_then(|x| serde_json::from_str(&x).ok())
        .unwrap_or(Value::Null)
}

fn write_mirror(c: &rusqlite::Connection, m: &Mirror) -> Result<(), CoreError> {
    for t in TABLES {
        c.execute(&format!("DELETE FROM {t}"), [])?;
        for r in m.tables.get(t).map(Vec::as_slice).unwrap_or(&[]) {
            c.execute(
                &format!("INSERT OR REPLACE INTO {t} (id, user_id, branch_id, on_date, status, data) VALUES (?1, ?2, ?3, ?4, ?5, ?6)"),
                rusqlite::params![r.id, r.user_id, r.branch_id, r.on_date, r.status, r.data.to_string()],
            )?;
        }
    }
    let now = wall_ms();
    c.execute("DELETE FROM dawam_meta", [])?;
    for (k, v) in &m.meta {
        c.execute("INSERT INTO dawam_meta (k, data, fetched_at) VALUES (?1, ?2, ?3)", rusqlite::params![k, v.to_string(), now])?;
    }
    Ok(())
}

// ── MadarCore: the Dawam surface ──────────────────────────────────────────

impl MadarCore {
    /// One server call, remembering the server's time for offline punches.
    async fn dawam_srv(&self, method: &str, path: &str, body: Option<Value>) -> Result<Value, CoreError> {
        let m = reqwest::Method::from_bytes(method.as_bytes()).map_err(|_| CoreError::Internal { detail: "method".into() })?;
        match self.staff_send(m, path, body.as_ref()).await {
            Ok(text) => {
                self.note_connectivity(true);
                let a = Anchor { server_ms: self.corrected_now_ms(), boot_ms: boot_ms(), wall_ms: wall_ms() };
                if let Ok(j) = serde_json::to_string(&a) {
                    let _ = self.store.kv_put(K_ANCHOR, &j);
                }
                Ok(if text.trim().is_empty() { Value::Null } else { serde_json::from_str(&text).unwrap_or(Value::Null) })
            }
            Err(e) => {
                if matches!(e, CoreError::Offline { .. }) {
                    self.note_connectivity(false);
                }
                Err(e)
            }
        }
    }

    fn dawam_anchor(&self) -> Option<Anchor> {
        self.store.kv_get(K_ANCHOR).ok().flatten().and_then(|j| serde_json::from_str(&j).ok())
    }

    fn dawam_me(&self) -> Result<String, CoreError> {
        self.current_session()
            .map(|s| s.user_id)
            .filter(|u| !u.is_empty())
            .ok_or_else(|| CoreError::Unauthenticated { detail: "sign in again".into() })
    }

    /// Fetch everything this person can see into the mirror (one transaction).
    /// A view the server refuses them is simply left empty.
    async fn dawam_fetch(&self) -> Result<(), CoreError> {
        let me = self.dawam_me()?;
        let ctx = self.dawam_srv("GET", "/staff/me/context", None).await?;
        let role = role_of(&s(&ctx, "role"));
        let manager = manages(&ctx);
        let all: Vec<String> = arr(&ctx, "branches").iter().map(|b| s(b, "id")).collect();
        let mine: Vec<String> = if role == "owner" {
            all.clone()
        } else {
            arr(&ctx, "people")
                .iter()
                .find(|p| s(p, "employee_id") == me)
                .map(|p| arr(p, "branch_ids").iter().filter_map(Value::as_str).map(str::to_string).collect())
                .unwrap_or_default()
        };
        let today = self.dawam_today();
        let from = week_start(today) - Duration::days(28);
        let to = from + Duration::days(55);
        let range = format!("from={from}&to={to}");
        let weeks = [week_start(today), week_start(today) + Duration::days(7)];

        let mut paths: Vec<String> = vec![
            format!("/staff/me/roster?{range}"),
            "/staff/me/notifications".into(),
            "/staff/me/pay/estimate".into(),
            "/staff/me/payslips".into(),
            "/staff/me/coverable".into(),
        ];
        if manager {
            paths.extend(mine.iter().map(|b| format!("/staff/roster?branch_id={b}&{range}")));
            paths.extend(mine.iter().map(|b| format!("/staff/roster/coverage?branch_id={b}")));
            paths.extend([
                format!("/staff/attendance?{range}"),
                "/staff/requests".into(),
                "/staff/swaps".into(),
                "/staff/payroll/advances".into(),
                "/staff/flags".into(),
                "/staff/adjustments".into(),
                "/staff/expense-advances".into(),
                "/staff/payroll/current".into(),
            ]);
            for b in &mine {
                paths.extend(weeks.iter().map(|w| format!("/staff/roster/suggestions?branch_id={b}&week_start={w}")));
            }
        } else {
            paths.extend([
                format!("/staff/me/attendance?{range}"),
                "/staff/me/requests".into(),
                "/staff/me/advances".into(),
                "/staff/me/adjustments".into(),
                "/staff/me/expense-advances".into(),
            ]);
        }
        let got: HashMap<String, Value> = futures_util::future::join_all(paths.iter().map(|p| async move {
            (p.clone(), self.dawam_srv("GET", p, None).await)
        }))
        .await
        .into_iter()
        .filter_map(|(p, r)| match r {
            Ok(v) => Some(Ok((p, v))),
            // Transport gone mid-refresh: keep the old mirror whole.
            Err(e @ CoreError::Offline { .. }) => Some(Err(e)),
            Err(_) => None,
        })
        .collect::<Result<_, _>>()?;
        let g = |p: &str| got.get(p).cloned().unwrap_or(Value::Null);

        let mut m = Mirror::default();
        for b in arr(&ctx, "branches") {
            m.put("dawam_branches", Row::new(s(b, "id"), b));
        }
        for w in arr(&ctx, "work_shifts") {
            m.put("dawam_work_shifts", Row::new(s(w, "id"), w));
        }
        for p in arr(&ctx, "people") {
            m.put("dawam_people", Row::new(s(p, "employee_id"), p));
        }
        let mut published: Vec<String> = Vec::new();
        let mut warnings: Vec<Value> = Vec::new();
        let mut coverage: BTreeMap<String, Value> = BTreeMap::new();
        let roster = |m: &mut Mirror, rows: &[Value]| {
            for r in rows {
                if let Some(d) = date(r, "date") {
                    let id = shift_id(&s(r, "employee_id"), d, &s(r, "work_shift_id"));
                    m.put("dawam_roster", Row::new(id, r).date(Some(d.to_string())));
                }
            }
        };
        if manager {
            for b in &mine {
                let v = g(&format!("/staff/roster?branch_id={b}&{range}"));
                for w in arr(&v, "published_weeks").iter().filter_map(Value::as_str) {
                    published.push(format!("{b}|{w}"));
                }
                roster(&mut m, arr(&v, "shifts"));
                for o in arr(&v, "open_shifts") {
                    m.put("dawam_open_shifts", Row::new(s(o, "id"), o).date(so(o, "on_date")));
                }
                for h in arr(&v, "holidays") {
                    m.put("dawam_holidays", Row::new(s(h, "on_date"), h).date(so(h, "on_date")));
                }
                warnings.extend(arr(&v, "warnings").iter().cloned());
                coverage.insert(b.clone(), g(&format!("/staff/roster/coverage?branch_id={b}")));
            }
        }
        let mine_roster = g(&format!("/staff/me/roster?{range}"));
        roster(&mut m, arr(&mine_roster, "shifts"));
        roster(&mut m, arr(&mine_roster, "team"));
        for o in arr(&mine_roster, "open_shifts") {
            m.put("dawam_open_shifts", Row::new(s(o, "id"), o).date(so(o, "on_date")));
        }
        for w in arr(&mine_roster, "swaps") {
            m.put("dawam_swaps", Row::new(s(w, "id"), w));
        }
        if let Some(list) = g("/staff/swaps").as_array() {
            for w in list {
                m.put("dawam_swaps", Row::new(s(w, "id"), w));
            }
        }
        if !manager {
            let unpublished: HashSet<String> =
                arr(&mine_roster, "unpublished_weeks").iter().filter_map(Value::as_str).map(str::to_string).collect();
            let mut w = week_start(from);
            while w <= to {
                if !unpublished.contains(&w.to_string()) {
                    published.extend(mine.iter().map(|b| format!("{b}|{w}")));
                }
                w += Duration::days(7);
            }
        }
        let list = |p: &str| g(p).as_array().cloned().unwrap_or_default();
        let (att, reqs, adv, adj, exp) = if manager {
            (format!("/staff/attendance?{range}"), "/staff/requests", "/staff/payroll/advances", "/staff/adjustments", "/staff/expense-advances")
        } else {
            (format!("/staff/me/attendance?{range}"), "/staff/me/requests", "/staff/me/advances", "/staff/me/adjustments", "/staff/me/expense-advances")
        };
        for r in list(&att) {
            m.put("dawam_attendance", Row::new(s(&r, "id"), &r).date(so(&r, "business_date")));
        }
        for q in list(reqs) {
            m.put("dawam_requests", Row::new(s(&q, "id"), &q).date(so(&q, "on_date")));
        }
        for a in list(adv) {
            m.put("dawam_advances", Row::new(s(&a, "id"), &a));
        }
        for a in list(adj) {
            m.put("dawam_adjustments", Row::new(format!("{}|{}", s(&a, "kind"), s(&a, "id")), &a).date(so(&a, "effective_date")));
        }
        for x in list(exp) {
            m.put("dawam_expenses", Row::new(s(&x, "id"), &x).date(so(&x, "given_on")));
        }
        for fl in list("/staff/flags") {
            m.put("dawam_flags", Row::new(s(&fl, "id"), &fl));
        }
        for n in list("/staff/me/notifications") {
            m.put("dawam_notifications", Row::new(s(&n, "id"), &n));
        }
        for c in list("/staff/me/coverable") {
            if let Some(d) = date(&c, "business_date") {
                m.put("dawam_coverable", Row::new(shift_id(&s(&c, "employee_id"), d, &s(&c, "work_shift_id")), &c));
            }
        }
        for b in &mine {
            for w in &weeks {
                for sg in list(&format!("/staff/roster/suggestions?branch_id={b}&week_start={w}")) {
                    let mut sg = sg.clone();
                    sg["branch_id"] = json!(b);
                    m.put("dawam_suggestions", Row::new(s(&sg, "id"), &sg).date(so(&sg, "date")));
                }
            }
        }
        // Pay: the whole business for payroll rights, else my own estimate.
        let cur = g("/staff/payroll/current");
        if cur.is_object() {
            let p = &cur["period"];
            m.put("dawam_periods", Row::new(s(p, "id"), p).date(so(p, "start_date")));
            for c in arr(&cur, "preview") {
                m.put("dawam_preview", Row::new(s(c, "employee_id"), c));
            }
            for sl in arr(&cur, "payslips") {
                let mut sl = sl.clone();
                sl["period_start"] = p["start_date"].clone();
                sl["period_end"] = p["end_date"].clone();
                m.put("dawam_payslips", Row::new(format!("{}|{}", s(p, "start_date"), s(&sl, "employee_id")), &sl));
            }
            for h in arr(&cur, "history") {
                m.put("dawam_periods", Row::new(s(h, "id"), h).date(so(h, "start_date")));
                if let Ok(rows) = self.dawam_srv("GET", &format!("/staff/payroll/periods/{}/payslips", s(h, "id")), None).await {
                    for sl in rows.as_array().into_iter().flatten() {
                        let mut sl = sl.clone();
                        sl["period_start"] = h["start_date"].clone();
                        sl["period_end"] = h["end_date"].clone();
                        m.put("dawam_payslips", Row::new(format!("{}|{}", s(h, "start_date"), s(&sl, "employee_id")), &sl));
                    }
                }
            }
        }
        for sl in list("/staff/me/payslips") {
            m.put("dawam_payslips", Row::new(format!("{}|{}", s(&sl, "period_start"), s(&sl, "employee_id")), &sl));
        }
        m.meta = vec![
            ("context", ctx),
            ("published", json!(published)),
            ("estimate", g("/staff/me/pay/estimate")),
            ("current", cur),
            ("me_roster", json!({ "pref_time": mine_roster.get("pref_time") })),
            ("warnings", json!(warnings)),
            ("coverage", json!(coverage)),
        ];
        self.store.with_tx(|tx| write_mirror(tx, &m))?;
        Ok(())
    }

    /// Today in the branch's time zone (AT-1), from the server's clock.
    fn dawam_today(&self) -> NaiveDate {
        let tz = self.dawam_tz();
        Utc.timestamp_millis_opt(self.corrected_now_ms()).single().unwrap_or_else(Utc::now).with_timezone(&tz).date_naive()
    }

    fn dawam_tz(&self) -> chrono_tz::Tz {
        self.store
            .with_conn(|c| {
                Ok(c.query_row("SELECT data FROM dawam_branches ORDER BY rowid LIMIT 1", [], |r| r.get::<_, String>(0)).ok())
            })
            .ok()
            .flatten()
            .and_then(|d| serde_json::from_str::<Value>(&d).ok())
            .and_then(|v| so(&v, "timezone"))
            .and_then(|t| t.parse().ok())
            .unwrap_or(chrono_tz::Africa::Cairo)
    }

    /// The screens' whole picture. `refresh` asks the server first; offline,
    /// or when the server can't be reached, it is the last mirror plus what is
    /// queued.
    pub async fn dawam_snapshot(&self, refresh: bool) -> Result<String, CoreError> {
        if refresh {
            match self.dawam_fetch().await {
                Ok(()) | Err(CoreError::Offline { .. }) | Err(CoreError::Transient { .. }) => {}
                Err(e) => return Err(e),
            }
        }
        let snap = self.dawam_build()?;
        let mut v = serde_json::to_value(&snap).map_err(|e| CoreError::Internal { detail: format!("snapshot: {e}") })?;
        in_branch_zone(&mut v, &self.dawam_tz());
        serde_json::to_string(&v).map_err(|e| CoreError::Internal { detail: format!("snapshot: {e}") })
    }

    /// Drain queued punches and pings, then refresh (connection restored).
    pub async fn dawam_sync(&self) -> Result<String, CoreError> {
        if self.api.ping().await.is_ok() {
            self.note_connectivity(true);
            let _ = self.store.clear_network_backoff();
        }
        let _ = self.drain_outbox().await;
        self.dawam_snapshot(true).await
    }

    /// Record a 15-minute ping (CL-4). Queued like a punch, so a dead signal
    /// loses nothing (CL-10); sent at once when online. Off shift it is not
    /// recorded at all (CL-17). Returns the snapshot.
    pub async fn dawam_ping(&self, fix: DawamFix) -> Result<String, CoreError> {
        let _ = self.store.kv_put(K_FIX, &serde_json::to_string(&fix).unwrap_or_default());
        let on_shift = self.dawam_build()?.active_shift.is_some();
        if on_shift {
            let body = json!({
                "latitude": fix.latitude, "longitude": fix.longitude,
                "accuracy_meters": fix.accuracy, "is_mock": fix.mock, "battery_percent": fix.battery,
            });
            self.dawam_enqueue("dawam_ping", "/staff/me/pings", body, fix.gps_time.as_deref())?;
            let _ = self.drain_outbox().await;
        }
        self.dawam_snapshot(false).await
    }

    /// Hand the phone's push token to the server (APP-6).
    pub async fn dawam_set_push_token(&self, token: String, locale: String) -> Result<(), CoreError> {
        self.dawam_srv("PUT", "/staff/me/push-token", Some(json!({ "token": token, "locale": locale }))).await.map(|_| ())
    }

    fn dawam_enqueue(&self, op: &str, path: &str, body: Value, gps_time: Option<&str>) -> Result<(), CoreError> {
        let me = self.dawam_me()?;
        let id = uuid::Uuid::new_v4().to_string();
        let wall = wall_ms();
        let payload = json!({
            "path": path, "body": body,
            "offline": stamp(self.dawam_anchor(), boot_ms(), wall, gps_time),
            "queued_ms": wall,
        });
        self.store.enqueue(&store::NewOutboxOp {
            id: id.clone(),
            op_type: op.to_string(),
            idempotency_key: id,
            payload: payload.to_string(),
            event_at: ms_rfc3339(self.corrected_now_ms()),
            depends_on_seq: None,
            user_id: Some(me.clone()),
            clock_offset_ms: None,
            // One FIFO per person: a check-out never overtakes its check-in.
            till_id: Some(format!("dawam:{me}")),
            device_id: None,
            entity_type: None,
            entity_id: None,
        })?;
        Ok(())
    }

    /// The drain's send for a queued Dawam op: straight to its `/staff/*`
    /// endpoint. Queued moments ago it goes as a live punch; later, with its
    /// offline stamp so the server dates it (CL-11).
    pub(crate) async fn dawam_send(&self, item: &store::OutboxItem) -> Result<Value, CoreError> {
        let p: Value = serde_json::from_str(&item.payload).map_err(|e| CoreError::Validation { field: "payload".into(), detail: e.to_string() })?;
        let mut body = p["body"].clone();
        if wall_ms() - i(&p, "queued_ms") > LIVE_MS {
            body["offline"] = p["offline"].clone();
        }
        self.dawam_srv("POST", &s(&p, "path"), Some(body)).await
    }

    /// Do one thing. Clocking in and out, covers and punches queue offline;
    /// everything else needs the server and says so. Returns the snapshot.
    pub async fn dawam_do(&self, action: String) -> Result<String, CoreError> {
        let act: Act = serde_json::from_str(&action).map_err(|e| CoreError::Validation { field: "action".into(), detail: e.to_string() })?;
        let online = self.current_session().is_some_and(|s| s.online);
        if matches!(act, Act::SignOut) {
            // Best effort and brief: signing out never waits on the network.
            // The host signs the core out after this, whatever it answers.
            let call = self.dawam_srv("POST", "/staff/me/sign-out", None);
            return match tokio::time::timeout(std::time::Duration::from_secs(5), call).await {
                Ok(Ok(_)) => Ok("{}".into()),
                Ok(Err(e)) => Err(e),
                Err(_) => Err(CoreError::Transient { detail: "sign-out timed out".into() }),
            };
        }
        if act.queueable() {
            self.dawam_queue(act)?;
            let _ = self.drain_outbox().await;
            // Online, the server's answer (lateness, a refusal) shows at once.
            if online {
                let dead = self.dawam_dead_since()?;
                if let Some(err) = dead {
                    let _ = self.dawam_snapshot(true).await;
                    return Err(CoreError::Server { status: 409, code: "refused".into(), detail: err });
                }
            }
            return self.dawam_snapshot(online).await;
        }
        if !online {
            return Err(needs_connection(&self.current_locale()));
        }
        self.dawam_online(act).await?;
        self.dawam_snapshot(true).await
    }

    /// The last queued Dawam op the server refused in the pass just run, which
    /// the host shows once and then drops.
    fn dawam_dead_since(&self) -> Result<Option<String>, CoreError> {
        let rows = self.store.with_conn(|c| {
            let mut st = c.prepare("SELECT id, last_error FROM outbox WHERE status = 'dead' AND op_type LIKE 'dawam_%' ORDER BY seq DESC")?;
            let v = st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?)))?.filter_map(Result::ok).collect::<Vec<_>>();
            Ok(v)
        })?;
        for (id, _) in rows.iter().skip(1) {
            let _ = self.store.discard_dead(id);
        }
        Ok(rows.into_iter().next().map(|(id, e)| {
            let _ = self.store.discard_dead(&id);
            e.unwrap_or_default()
        }))
    }

    fn dawam_queue(&self, act: Act) -> Result<(), CoreError> {
        let snap = self.dawam_build()?;
        let branch_of = |shift: &str| {
            let tpl = shift.rsplit('|').next().unwrap_or_default();
            snap.templates.iter().find(|t| t.id == tpl).map(|t| t.branch.clone()).unwrap_or_default()
        };
        let fix_body = |fix: &Option<DawamFix>| json!({ "latitude": fix.as_ref().map(|f| f.latitude), "longitude": fix.as_ref().map(|f| f.longitude) });
        let gps = |fix: &Option<DawamFix>| fix.as_ref().and_then(|f| f.gps_time.clone());
        match act {
            Act::ClockIn { shift, fix, tracking_off } => {
                if snap.active_shift.is_some() {
                    return Err(CoreError::Validation { field: "shift".into(), detail: i18n::tr(&self.current_locale(), "staff.clock_out_first") });
                }
                let mut body = fix_body(&fix);
                body["branch_id"] = json!(branch_of(&shift));
                body["tracking_off"] = json!(tracking_off);
                body["shift"] = json!(shift);
                self.dawam_enqueue("dawam_check_in", "/staff/me/check-in", body, gps(&fix).as_deref())
            }
            Act::ClockOut { fix } => self.dawam_enqueue("dawam_check_out", "/staff/me/check-out", fix_body(&fix), gps(&fix).as_deref()),
            Act::Cover { shift, fix } => {
                let (user, _, tpl) = parts(&shift);
                let mut body = fix_body(&fix);
                body["employee_id"] = json!(user);
                body["work_shift_id"] = json!(tpl);
                body["shift"] = json!(shift);
                self.dawam_enqueue("dawam_cover", "/staff/me/cover", body, gps(&fix).as_deref())
            }
            Act::PunchFor { shift, reason } => {
                let (user, ..) = parts(&shift);
                self.dawam_enqueue("dawam_punch_for", "/staff/attendance/punch", json!({ "employee_id": user, "reason": reason, "shift": shift }), None)
            }
            _ => Ok(()),
        }
    }

    /// The online-only actions: one or two server calls each.
    async fn dawam_online(&self, act: Act) -> Result<(), CoreError> {
        let snap = self.dawam_build()?;
        let period_id = snap.period.id.clone().unwrap_or_default();
        let day = |emp: &str, d: &str, tpl: Option<&str>| {
            json!({ "employee_id": emp, "on_date": d, "work_shift_id": tpl })
        };
        match act {
            Act::File { kind, from, to, half, time, time2, note, amount, installments, shift, shift2, peer } => {
                let d = from.unwrap_or_else(|| self.dawam_today().to_string());
                match kind.as_str() {
                    "salaryAdvance" => {
                        self.dawam_srv("POST", "/staff/me/advances", Some(json!({
                            "amount_piastres": amount, "installments": installments.unwrap_or(1),
                            "reason": Some(note).filter(|n| !n.is_empty()),
                        }))).await?;
                    }
                    "swap" => {
                        let (_, my_date, my_tpl) = parts(shift.as_deref().unwrap_or_default());
                        let (peer_id, peer_date, peer_tpl) = parts(shift2.as_deref().unwrap_or_default());
                        self.dawam_srv("POST", "/staff/me/swaps", Some(json!({
                            "my_date": my_date, "my_shift_id": my_tpl,
                            "peer_id": peer.unwrap_or_else(|| peer_id.to_string()),
                            "peer_date": peer_date, "peer_shift_id": peer_tpl,
                        }))).await?;
                    }
                    "openShift" => {
                        self.dawam_srv("POST", &format!("/staff/open-shifts/{}/claim", tail(shift.as_deref().unwrap_or_default())), Some(json!({}))).await?;
                    }
                    k => {
                        let server = kind_to_server(k).ok_or_else(|| CoreError::Validation { field: "kind".into(), detail: k.into() })?;
                        let record = shift.as_deref().and_then(|sid| snap.shifts.iter().find(|x| x.id == sid)).and_then(|_| self.dawam_record_of(shift.as_deref()?));
                        let mut body = json!({ "kind": server, "on_date": d, "is_half_day": half });
                        if let Some(t) = to { body["end_date"] = json!(t); }
                        // A late arrival's one time is when they will ARRIVE: the
                        // server keeps that in `to_time` and refuses a `from_time`.
                        if server == "late_arrival" {
                            if let Some(t) = time { body["to_time"] = json!(hhmm(t)); }
                        } else {
                            if let Some(t) = time { body["from_time"] = json!(hhmm(t)); }
                            if let Some(t) = time2 { body["to_time"] = json!(hhmm(t)); }
                        }
                        if !note.is_empty() {
                            body["reason"] = json!(note);
                            if server == "mission" { body["title"] = json!(note); }
                        }
                        if let Some(r) = record { body["attendance_record_id"] = json!(r); }
                        self.dawam_srv("POST", "/staff/me/requests", Some(body)).await?;
                    }
                }
            }
            Act::PeerAnswer { req, yes } => {
                self.dawam_srv("PATCH", &format!("/staff/me/swaps/{}", tail(&req)), Some(json!({ "approve": yes }))).await?;
            }
            Act::Cancel { req } => {
                if !req.starts_with("q|") {
                    return Err(CoreError::Validation { field: "req".into(), detail: i18n::tr(&self.current_locale(), "staff.ask_manager_to_cancel") });
                }
                self.dawam_srv("PATCH", &format!("/staff/requests/{}/decision", tail(&req)), Some(json!({ "status": "cancelled" }))).await?;
            }
            Act::Decide { req, approve, paid, amount, installments, note } => {
                let id = tail(&req);
                let (path, body) = match req.split('|').next().unwrap_or_default() {
                    "q" => (format!("/staff/requests/{id}/decision"), json!({ "status": if approve { "approved" } else { "rejected" }, "is_paid": paid, "note": note })),
                    "v" => (format!("/staff/advances/{id}/review"), json!({ "approve": approve, "amount_piastres": amount, "installments": installments, "note": note })),
                    "w" => (format!("/staff/swaps/{id}/decision"), json!({ "approve": approve })),
                    "o" => (format!("/staff/open-shifts/{id}/decision"), json!({ "approve": approve })),
                    "c" => (format!("/staff/attendance/{id}/cover"), json!({ "approve": approve })),
                    "t" => (format!("/staff/attendance/{id}/overtime"), json!({ "approve": approve })),
                    other => return Err(CoreError::Validation { field: "req".into(), detail: other.into() }),
                };
                self.dawam_srv("PATCH", &path, Some(body)).await?;
            }
            Act::Resolve { flag, how, deduct } => {
                let mut body = json!({ "action": how });
                if deduct > 0 { body["amount_piastres"] = json!(deduct); }
                self.dawam_srv("PATCH", &format!("/staff/flags/{flag}"), Some(body)).await?;
            }
            Act::AddAdjustment { emp, bonus, amount, reason, pct, recurring } => {
                let mut body = json!({ "employee_id": emp, "kind": if bonus { "bonus" } else { "deduction" }, "reason": reason, "recurring": recurring });
                match pct {
                    Some(p) => body["percent_of_base"] = json!(p),
                    None => body["amount_piastres"] = json!(amount),
                }
                self.dawam_srv("POST", "/staff/adjustments", Some(body)).await?;
            }
            Act::DecideAdj { adj, yes } => {
                let (_, kind, id) = parts(&adj);
                self.dawam_srv("PATCH", &format!("/staff/adjustments/{kind}/{id}/decision"), Some(json!({ "approve": yes }))).await?;
            }
            Act::DeleteAdj { adj } => {
                let (_, kind, id) = parts(&adj);
                let table = if kind == "bonus" { "bonuses" } else { "deductions" };
                self.dawam_srv("DELETE", &format!("/staff/payroll/{table}/{id}"), None).await?;
            }
            Act::StopAdj { adj } => {
                let (_, kind, id) = parts(&adj);
                self.dawam_srv("POST", &format!("/staff/adjustments/{kind}/{id}/stop"), Some(json!({}))).await?;
            }
            Act::Waive { key, reason } => {
                if let Some(id) = key.strip_prefix("d|") {
                    self.dawam_srv("PATCH", &format!("/staff/payroll/deductions/{id}/waive"), Some(json!({ "reason": reason }))).await?;
                }
            }
            Act::RecordAdvance { emp, amount, installments } => {
                let a = self.dawam_srv("POST", "/staff/payroll/advances", Some(json!({ "employee_id": emp, "amount_piastres": amount, "installments": installments }))).await?;
                self.dawam_srv("PATCH", &format!("/staff/advances/{}/review", s(&a, "id")), Some(json!({ "approve": true }))).await?;
            }
            Act::LogExpense { emp, amount, purpose, via } => {
                self.dawam_srv("POST", "/staff/expense-advances", Some(json!({ "employee_id": emp, "amount_piastres": amount, "purpose": purpose, "via": via }))).await?;
            }
            Act::SetDay { emp, date: d, tpl } => {
                self.dawam_srv("PUT", "/staff/schedules/overrides", Some(day(&emp, &d, tpl.as_deref()))).await?;
            }
            Act::MoveShift { shift, day: to_day, tpl } => {
                let (emp, from_day, _) = parts(&shift);
                if emp != "open" {
                    if from_day != to_day {
                        self.dawam_srv("PUT", "/staff/schedules/overrides", Some(day(emp, from_day, None))).await?;
                    }
                    self.dawam_srv("PUT", "/staff/schedules/overrides", Some(day(emp, &to_day, Some(&tpl)))).await?;
                }
            }
            Act::Assign { shift, emp } => {
                let (owner, d, tpl) = parts(&shift);
                let branch = snap.templates.iter().find(|t| t.id == tpl).map(|t| t.branch.clone()).unwrap_or_default();
                if owner != "open" {
                    self.dawam_srv("PUT", "/staff/schedules/overrides", Some(day(owner, d, None))).await?;
                }
                match emp {
                    Some(e) => { self.dawam_srv("PUT", "/staff/schedules/overrides", Some(day(&e, d, Some(tpl)))).await?; }
                    None => { self.dawam_srv("POST", "/staff/open-shifts", Some(json!({ "branch_id": branch, "work_shift_id": tpl, "on_date": d }))).await?; }
                }
            }
            Act::PostOpen { branch, date: d, tpl } => {
                self.dawam_srv("POST", "/staff/open-shifts", Some(json!({ "branch_id": branch, "work_shift_id": tpl, "on_date": d }))).await?;
            }
            Act::Claim { shift } => {
                self.dawam_srv("POST", &format!("/staff/open-shifts/{}/claim", tail(&shift)), Some(json!({}))).await?;
            }
            Act::Publish { branch, week } => {
                self.dawam_srv("POST", "/staff/roster/publish", Some(json!({ "branch_id": branch, "week_start": week }))).await?;
            }
            Act::AcceptSuggestion { id } => self.dawam_suggestion(&snap, &id, true).await?,
            Act::RejectSuggestion { id } => self.dawam_suggestion(&snap, &id, false).await?,
            Act::DecideHoliday { date: d, decision } => {
                self.dawam_srv("PUT", &format!("/staff/holidays/{d}"), Some(json!({ "decision": decision }))).await?;
            }
            Act::SetCoverage { branch, needs } => {
                self.dawam_srv("PUT", "/staff/roster/coverage", Some(json!({ "branch_id": branch, "needs": needs }))).await?;
            }
            Act::SetPrefs { time, cant } => {
                let days: Vec<i64> = cant.iter().map(|d| d % 7).collect();
                self.dawam_srv("PUT", "/staff/me/preferences", Some(json!({ "pref_time": time, "cant_work_days": days }))).await?;
            }
            Act::ReadAll => {
                self.dawam_srv("POST", "/staff/me/notifications/read", Some(json!({ "ids": [] }))).await?;
            }
            Act::ApprovePayroll => {
                self.dawam_srv("POST", &format!("/staff/payroll/periods/{period_id}/generate"), Some(json!({}))).await?;
            }
            Act::ReopenPayroll => {
                self.dawam_srv("PATCH", &format!("/staff/payroll/periods/{period_id}/status"), Some(json!({ "status": "draft" }))).await?;
            }
            Act::MarkPaid { emp, method } => {
                self.dawam_srv("PATCH", &format!("/staff/payroll/periods/{period_id}/payslips/{emp}/paid"), Some(json!({ "method": method }))).await?;
            }
            Act::ClockIn { .. } | Act::ClockOut { .. } | Act::Cover { .. } | Act::PunchFor { .. } | Act::SignOut => {}
        }
        Ok(())
    }

    async fn dawam_suggestion(&self, snap: &Snapshot, id: &str, accept: bool) -> Result<(), CoreError> {
        let branch = snap.suggestions.iter().find(|g| g.id == id).map(|g| g.branch.clone()).unwrap_or_default();
        self.dawam_srv("POST", "/staff/roster/suggestions/decide", Some(json!({ "branch_id": branch, "id": id, "accept": accept }))).await.map(|_| ())
    }

    /// The attendance record behind a shift, for a correction (RQ-9).
    fn dawam_record_of(&self, shift: &str) -> Option<String> {
        let (user, d, tpl) = parts(shift);
        self.store
            .with_conn(|c| read_table(c, "dawam_attendance"))
            .ok()?
            .into_iter()
            .find(|r| (so(r, "covered_employee_id").unwrap_or_else(|| s(r, "employee_id"))) == user && s(r, "business_date") == d && s(r, "work_shift_id") == tpl)
            .map(|r| s(&r, "id"))
    }

    /// Queued Dawam ops (pending or in flight).
    fn dawam_queued(&self) -> Result<Vec<store::OutboxItem>, CoreError> {
        Ok(self.store.pending()?.into_iter().filter(|o| o.op_type.starts_with(OP_PREFIX)).collect())
    }

    /// Build the picture from the mirror plus the queue.
    fn dawam_build(&self) -> Result<Snapshot, CoreError> {
        let me = self.dawam_me()?;
        let locale = self.current_locale();
        let now = Utc.timestamp_millis_opt(self.corrected_now_ms()).single().unwrap_or_else(Utc::now);
        let tz = self.dawam_tz();
        let today = now.with_timezone(&tz).date_naive();
        let queued = self.dawam_queued()?;
        let (warn_rows, coverage) = self.store.with_conn(|c| Ok((read_meta(c, "warnings"), read_meta(c, "coverage"))))?;
        let (t, ctx, published, estimate, current, me_roster, fetched_at) = self.store.with_conn(|c| {
            let mut t = HashMap::new();
            for name in TABLES {
                t.insert(*name, read_table(c, name)?);
            }
            let fetched: i64 = c.query_row("SELECT COALESCE(MAX(fetched_at), 0) FROM dawam_meta", [], |r| r.get(0)).unwrap_or(0);
            Ok((t, read_meta(c, "context"), read_meta(c, "published"), read_meta(c, "estimate"), read_meta(c, "current"), read_meta(c, "me_roster"), fetched))
        })?;
        let rows = |n: &str| t.get(n).map(Vec::as_slice).unwrap_or(&[]);
        let stuck = self
            .store
            .with_conn(|c| {
                let mut st = c.prepare("SELECT COALESCE(last_error, '') FROM outbox WHERE status = 'dead' AND op_type LIKE 'dawam_%'")?;
                let v = st.query_map([], |r| r.get::<_, String>(0))?.filter_map(Result::ok).collect::<Vec<_>>();
                Ok(v)
            })
            .unwrap_or_default();
        let online = self.current_session().is_some_and(|s| s.online);
        let role = role_of(&s(&ctx, "role")).to_string();
        let caps: Vec<String> = arr(&ctx, "caps").iter().filter_map(Value::as_str).map(str::to_string).collect();
        let mut out = Snapshot {
            me: me.clone(),
            org_name: s(&ctx, "org_name"),
            now: now.to_rfc3339(),
            online,
            queued: queued.len() as u32,
            stuck,
            can_manage: manages(&ctx),
            can_payroll: manage_tabs(&caps).payroll,
            tabs: manage_tabs(&caps),
            caps,
            fetched_at,
            role,
            ..Default::default()
        };

        // Places, templates, people, settings.
        for br in rows("dawam_branches") {
            out.branches.push(BranchV { id: s(br, "id"), name: s(br, "name"), radius: br.get("geo_radius_meters").and_then(Value::as_i64).unwrap_or(200) });
        }
        let first_branch = out.branches.first().map(|x| x.id.clone()).unwrap_or_default();
        for w in rows("dawam_work_shifts") {
            out.templates.push(TplV {
                id: s(w, "id"),
                branch: so(w, "branch_id").unwrap_or_else(|| first_branch.clone()),
                name: s(w, "name"),
                start: minute_of(&s(w, "start_time")).unwrap_or(0),
                end: minute_of(&s(w, "end_time")).unwrap_or(0),
                grace: i(w, "grace_minutes"),
                window: w.get("checkin_window_minutes").and_then(Value::as_i64).unwrap_or(30),
            });
        }
        for p in rows("dawam_people") {
            out.people.push(PersonV {
                id: s(p, "employee_id"),
                name: s(p, "name"),
                phone: s(p, "phone"),
                role: role_of(&s(p, "role")).into(),
                branches: arr(p, "branch_ids").iter().filter_map(Value::as_str).map(str::to_string).collect(),
                salary: i(p, "base_salary_piastres"),
                gender: s(p, "gender"),
                hired: so(p, "hire_date").unwrap_or_else(|| "2000-01-01".into()),
                pay: so(p, "pay_method").unwrap_or_else(|| "cash".into()),
                account: s(p, "pay_account"),
                device: s(p, "device_model"),
                device_since: so(p, "device_since"),
                pref_time: so(p, "pref_time"),
                cant_work: arr(p, "cant_work_days").iter().filter_map(Value::as_i64).map(|d| if d == 0 { 7 } else { d }).collect(),
            });
        }
        // Actors (who decided, who handed over) are server users; a manager acts
        // through the employee linked to that user, so show them as that person.
        let linked: HashMap<String, String> =
            rows("dawam_people").iter().filter_map(|p| Some((so(p, "user_id")?, s(p, "employee_id")))).collect();
        let actor = |u: Option<String>| u.map(|u| linked.get(&u).cloned().unwrap_or(u));
        if let Some(p) = out.people.iter_mut().find(|p| p.id == me) {
            p.role = out.role.clone();
            if let Some(t) = so(&me_roster, "pref_time") {
                p.pref_time = Some(t);
            }
        }
        out.my_branches = if out.role == "owner" {
            out.branches.iter().map(|x| x.id.clone()).collect()
        } else {
            out.people.iter().find(|p| p.id == me).map(|p| p.branches.clone()).unwrap_or_default()
        };
        let st = &ctx["settings"];
        out.settings = SettingsV {
            overtime: match s(st, "overtime_mode").as_str() {
                "automatic" => "automatic",
                "approval" => "approval",
                _ => "off",
            }
            .into(),
            ot_day: f(st, "overtime_day_multiplier"),
            ot_night: f(st, "overtime_night_multiplier"),
            holiday_mult: f(st, "holiday_multiplier"),
            advance_cap_pct: f(st, "advance_cap_percent"),
            absence_days: f(st, "absence_deduction_days"),
            period_start_day: i(st, "period_start_day").clamp(1, 28),
            adjustment_limit: ctx.get("adjustment_limit_piastres").and_then(Value::as_i64),
            // Old servers don't say: assume saved rather than block the screens.
            rules_saved: st.get("rules_saved").and_then(Value::as_bool).unwrap_or(true),
        };
        out.modules = match ctx.get("modules").and_then(Value::as_array) {
            Some(m) => m.iter().filter_map(Value::as_str).map(str::to_string).collect(),
            None => vec!["pos".into(), "dawam".into()],
        };
        let tpl = |id: &str| out.templates.iter().find(|x| x.id == id);
        let published: HashSet<String> = published.as_array().into_iter().flatten().filter_map(Value::as_str).map(str::to_string).collect();

        // Shifts: the roster, open shifts, then what happened on them.
        let mut shifts: Vec<ShiftV> = Vec::new();
        let is_pub = |branch: &str, d: NaiveDate| published.contains(&format!("{branch}|{}", week_start(d)));
        for r in rows("dawam_roster") {
            let (Some(d), id) = (date(r, "date"), s(r, "work_shift_id")) else { continue };
            let Some(tp) = tpl(&id) else { continue };
            let sid = shift_id(&s(r, "employee_id"), d, &id);
            if shifts.iter().any(|x| x.id == sid) {
                continue;
            }
            shifts.push(ShiftV {
                id: sid,
                emp: so(r, "employee_id"),
                tpl: id,
                date: d.to_string(),
                published: is_pub(&tp.branch, d),
                changed: b(r, "changed"),
                leave: b(r, "on_leave").then(|| "paid".to_string()),
                ..Default::default()
            });
        }
        for o in rows("dawam_open_shifts") {
            let (Some(d), id) = (date(o, "on_date"), s(o, "work_shift_id")) else { continue };
            let Some(tp) = tpl(&id) else { continue };
            shifts.push(ShiftV { id: format!("open|{}", s(o, "id")), tpl: id, date: d.to_string(), published: is_pub(&tp.branch, d), ..Default::default() });
            if s(o, "status") == "claimed" {
                if let Some(by) = so(o, "claimed_by") {
                    out.requests.push(ReqV { id: format!("o|{}", s(o, "id")), kind: "openShift".into(), emp: by, created: now.to_rfc3339(), status: "pending".into(), from: Some(d.to_string()), shift: Some(format!("open|{}", s(o, "id"))), installments: 1, ..Default::default() });
                }
            }
        }
        let mut record_of: HashMap<String, String> = HashMap::new();
        for r in rows("dawam_attendance") {
            let Some(d) = date(r, "business_date") else { continue };
            let wid = s(r, "work_shift_id");
            let Some(tp) = tpl(&wid) else { continue };
            let user = s(r, "employee_id");
            let covered = so(r, "covered_employee_id");
            let owner = covered.clone().unwrap_or_else(|| user.clone());
            let sid = shift_id(&owner, d, &wid);
            let branch = tp.branch.clone();
            let idx = match shifts.iter().position(|x| x.id == sid) {
                Some(ix) => ix,
                None => {
                    // A worked shift is a fact, published or not.
                    shifts.push(ShiftV { id: sid.clone(), emp: Some(owner.clone()), tpl: wid.clone(), date: d.to_string(), published: true, ..Default::default() });
                    let _ = &branch;
                    shifts.len() - 1
                }
            };
            let sh = &mut shifts[idx];
            sh.in_at = at(r, "check_in_at").map(|x| x.to_rfc3339());
            sh.out_at = at(r, "check_out_at").map(|x| x.to_rfc3339());
            sh.in_method = method_of(&s(r, "check_in_method"));
            sh.out_method = method_of(&s(r, "check_out_method"));
            sh.punch_reason = so(r, "punch_reason");
            sh.tracking_off = b(r, "tracking_off");
            sh.late_minutes = i(r, "late_minutes");
            sh.absent = s(r, "status") == "absent" && covered.is_none();
            if covered.is_some() {
                sh.cover_by = Some(user.clone());
            }
            record_of.insert(sid.clone(), s(r, "id"));
            if covered.is_some() && s(r, "cover_status") == "pending" {
                out.requests.push(ReqV { id: format!("c|{}", s(r, "id")), kind: "cover".into(), emp: user.clone(), created: sh.in_at.clone().unwrap_or_else(|| now.to_rfc3339()), status: "pending".into(), from: Some(d.to_string()), shift: Some(sid.clone()), installments: 1, ..Default::default() });
            }
            if s(r, "overtime_status") == "pending" {
                out.requests.push(ReqV { id: format!("t|{}", s(r, "id")), kind: "overtime".into(), emp: user.clone(), created: sh.out_at.clone().unwrap_or_else(|| now.to_rfc3339()), status: "pending".into(), from: Some(d.to_string()), shift: Some(sid.clone()), minutes: i(r, "overtime_minutes"), installments: 1, ..Default::default() });
            }
        }

        // What is queued shows at once, marked queued (APP-8).
        let active_of = |shifts: &[ShiftV]| {
            shifts.iter().position(|x| x.in_at.is_some() && x.out_at.is_none() && ((x.emp.as_deref() == Some(&me) && x.cover_by.is_none()) || x.cover_by.as_deref() == Some(&me)))
        };
        for q in &queued {
            let p: Value = serde_json::from_str(&q.payload).unwrap_or_default();
            let when = q.event_at.clone();
            let method = if wall_ms() - i(&p, "queued_ms") > LIVE_MS { "offline" } else { "app" };
            match q.op_type.as_str() {
                "dawam_check_in" | "dawam_cover" => {
                    let sid = s(&p["body"], "shift");
                    if let Some(sh) = shifts.iter_mut().find(|x| x.id == sid) {
                        sh.in_at = Some(when);
                        sh.in_method = Some(if q.op_type == "dawam_cover" { "cover" } else { method }.into());
                        sh.queued = true;
                        if q.op_type == "dawam_cover" {
                            sh.cover_by = Some(me.clone());
                        }
                    }
                }
                "dawam_check_out" => {
                    if let Some(ix) = active_of(&shifts) {
                        shifts[ix].out_at = Some(when);
                        shifts[ix].out_method = Some(method.into());
                        shifts[ix].queued = true;
                    }
                }
                "dawam_punch_for" => {
                    let sid = s(&p["body"], "shift");
                    if let Some(sh) = shifts.iter_mut().find(|x| x.id == sid) {
                        if sh.in_at.is_none() {
                            sh.in_at = Some(when);
                            sh.in_method = Some("manager".into());
                        } else {
                            sh.out_at = Some(when);
                            sh.out_method = Some("manager".into());
                        }
                        sh.punch_reason = so(&p["body"], "reason");
                        sh.queued = true;
                    }
                }
                _ => {}
            }
        }

        // Requests, and what an approved one changes on the day.
        let manager_ids: HashSet<String> = out.people.iter().filter(|p| p.role == "manager").map(|p| p.id.clone()).collect();
        for q in rows("dawam_requests") {
            let Some(kind) = kind_of_server(&s(q, "kind")) else { continue };
            let user = s(q, "employee_id");
            let rec = so(q, "attendance_record_id");
            let r = ReqV {
                id: format!("q|{}", s(q, "id")),
                kind: kind.into(),
                emp: user.clone(),
                created: s(q, "created_at"),
                status: status_of(&s(q, "status")).into(),
                from: so(q, "on_date"),
                to: so(q, "end_date"),
                half: b(q, "is_half_day"),
                // `time` is the kind's own time: for a late arrival that is the
                // arrival, which the server keeps in `to_time`.
                time: if kind == "lateArrival" { so(q, "to_time") } else { so(q, "from_time") }.and_then(|x| minute_of(&x)),
                time2: if kind == "lateArrival" { None } else { so(q, "to_time") }.and_then(|x| minute_of(&x)),
                note: s(q, "reason"),
                paid: q.get("is_paid").and_then(Value::as_bool),
                shift: rec.and_then(|rid| record_of.iter().find(|(_, v)| **v == rid).map(|(k, _)| k.clone())),
                to_owner: manager_ids.contains(&user),
                decided_by: actor(so(q, "decided_by")),
                decision_note: so(q, "decision_note"),
                installments: 1,
                ..Default::default()
            };
            if r.status == "approved" {
                let (from, to) = (r.from.clone().unwrap_or_default(), r.to.clone().or(r.from.clone()).unwrap_or_default());
                for sh in shifts.iter_mut().filter(|x| x.emp.as_deref() == Some(&user) && x.date >= from && x.date <= to) {
                    match kind {
                        "leave" => {
                            sh.leave = Some(if r.paid.unwrap_or(true) { "paid" } else { "unpaid" }.into());
                            sh.half_leave = r.half;
                            sh.absent = false;
                        }
                        "mission" => {
                            sh.mission = true;
                            sh.absent = false;
                        }
                        "lateArrival" => sh.late_until = r.time,
                        "earlyDeparture" => sh.early_from = r.time,
                        "excuse" => {
                            if let (Some(a), Some(z)) = (r.time, r.time2) {
                                sh.excuse_min = z - a;
                                sh.excuse_paid = r.paid.unwrap_or(false);
                            }
                        }
                        _ => {}
                    }
                }
            }
            out.requests.push(r);
        }
        for w in rows("dawam_swaps") {
            let (Some(rd), Some(pd)) = (date(w, "requester_date"), date(w, "peer_date")) else { continue };
            out.requests.push(ReqV {
                id: format!("w|{}", s(w, "id")),
                kind: "swap".into(),
                emp: s(w, "requester_id"),
                created: s(w, "created_at"),
                status: status_of(&s(w, "status")).into(),
                from: Some(rd.to_string()),
                shift: Some(shift_id(&s(w, "requester_id"), rd, &s(w, "requester_shift_id"))),
                shift2: Some(shift_id(&s(w, "peer_id"), pd, &s(w, "peer_shift_id"))),
                peer: so(w, "peer_id"),
                installments: 1,
                ..Default::default()
            });
        }
        let mut advance_collected: HashMap<String, i64> = HashMap::new();
        for a in rows("dawam_advances") {
            let status = s(a, "status");
            let user = s(a, "employee_id");
            let amount = i(a, "amount_piastres");
            if matches!(status.as_str(), "pending" | "rejected" | "cancelled") {
                out.requests.push(ReqV {
                    id: format!("v|{}", s(a, "id")),
                    kind: "salaryAdvance".into(),
                    emp: user,
                    created: s(a, "created_at"),
                    status: status_of(&status).into(),
                    from: so(a, "created_at").map(|x| x.chars().take(10).collect()),
                    amount,
                    installments: i(a, "installments").max(1),
                    note: s(a, "reason"),
                    decision_note: so(a, "decision_note"),
                    ..Default::default()
                });
                continue;
            }
            let collected = amount - i(a, "remaining_piastres");
            advance_collected.insert(s(a, "id"), collected);
            *out.outstanding.entry(user.clone()).or_default() += amount - collected;
            out.advances.push(AdvanceV {
                id: s(a, "id"),
                emp: user,
                amount,
                installments: i(a, "installments").max(1),
                date: so(a, "decided_at").unwrap_or_else(|| s(a, "created_at")),
                by: actor(so(a, "decided_by")).unwrap_or_default(),
                collected,
            });
        }
        for p in &out.people {
            out.advance_cap.insert(p.id.clone(), (p.salary as f64 * out.settings.advance_cap_pct / 100.0).round() as i64);
        }

        // Absent past its end with nothing to excuse it (the sweep's rule,
        // read ahead of the sweep so the day shows at once).
        let holiday_days: HashSet<String> = rows("dawam_holidays").iter().filter(|h| s(h, "decision") == "holiday").map(|h| s(h, "on_date")).collect();
        for sh in shifts.iter_mut() {
            let Some(tp) = tpl(&sh.tpl) else { continue };
            let end = shift_end(&sh.date, tp, &tz);
            if sh.emp.is_some() && sh.published && sh.in_at.is_none() && sh.leave.is_none() && !sh.mission && !holiday_days.contains(&sh.date) && end.is_some_and(|e| e < now) {
                sh.absent = true;
            }
            if sh.cover_by.is_some() && sh.cover_by.as_deref() != sh.emp.as_deref() {
                sh.absent = sh.leave.is_none();
            }
        }

        // Me, now (SC-10: last night's shift still running counts).
        let today_s = today.to_string();
        for sh in &shifts {
            let Some(tp) = tpl(&sh.tpl) else { continue };
            let mine = (sh.emp.as_deref() == Some(&me) && sh.cover_by.is_none()) || sh.cover_by.as_deref() == Some(&me);
            let running = shift_start(&sh.date, tp, &tz).zip(shift_end(&sh.date, tp, &tz)).is_some_and(|(a, z)| a <= now && z > now);
            if sh.published && mine && (sh.date == today_s || (sh.in_at.is_some() && sh.out_at.is_none()) || running) {
                out.my_now.push(sh.id.clone());
            }
        }
        out.active_shift = active_of(&shifts).map(|ix| shifts[ix].id.clone());
        let coverable_ids: HashSet<String> = rows("dawam_coverable").iter().filter_map(|c| date(c, "business_date").map(|d| shift_id(&s(c, "employee_id"), d, &s(c, "work_shift_id")))).collect();
        if out.active_shift.is_none() {
            out.coverable = shifts.iter().filter(|x| coverable_ids.contains(&x.id) && x.in_at.is_none() && x.cover_by.is_none()).map(|x| x.id.clone()).collect();
        }

        // Flags.
        for fl in rows("dawam_flags") {
            let rec = so(fl, "attendance_record_id");
            let shift = rec.and_then(|rid| record_of.iter().find(|(_, v)| **v == rid).map(|(k, _)| k.clone()));
            if s(fl, "kind") == "time_unverified" {
                if let Some(sh) = shift.as_ref().and_then(|sid| shifts.iter_mut().find(|x| &x.id == sid)) {
                    sh.time_unverified = true;
                }
            }
            out.flags.push(FlagV {
                id: s(fl, "id"),
                kind: s(fl, "kind"),
                emp: s(fl, "employee_id"),
                shift,
                at: s(fl, "detected_at"),
                minutes_away: i(fl, "minutes_away"),
                resolution: so(fl, "resolution"),
                suggested: i(fl, "suggested_deduction_piastres"),
            });
        }
        out.open_flags = out.flags.iter().filter(|x| x.resolution.is_none() && x.emp != me).map(|x| x.id.clone()).collect();

        // Adjustments, expenses, the inbox.
        for a in rows("dawam_adjustments") {
            let status = match s(a, "status").as_str() {
                "pending" => "pendingOwner",
                "rejected" => "rejected",
                _ if a.get("ends_on").is_some_and(|x| !x.is_null()) => "stopped",
                _ => "active",
            };
            let pct = a.get("percent_of_base").filter(|x| !x.is_null()).map(|_| f(a, "percent_of_base"));
            let salary = out.people.iter().find(|p| p.id == s(a, "employee_id")).map_or(0, |p| p.salary);
            out.adjustments.push(AdjV {
                id: format!("a|{}|{}", s(a, "kind"), s(a, "id")),
                emp: s(a, "employee_id"),
                bonus: s(a, "kind") == "bonus",
                amount: i(a, "amount_piastres"),
                value: pct.map_or(i(a, "amount_piastres"), |p| (salary as f64 * p / 100.0).round() as i64),
                pct,
                reason: s(a, "reason"),
                by: actor(so(a, "created_by")).unwrap_or_default(),
                at: s(a, "created_at"),
                period: s(a, "effective_date"),
                recurring: b(a, "recurring"),
                status: status.into(),
            });
        }
        if out.role == "owner" {
            out.adj_inbox = out.adjustments.iter().filter(|a| a.status == "pendingOwner").map(|a| a.id.clone()).collect();
        }
        for x in rows("dawam_expenses") {
            out.expenses.push(ExpenseV {
                id: s(x, "id"),
                emp: s(x, "employee_id"),
                amount: i(x, "amount_piastres"),
                date: s(x, "given_on"),
                branch: so(x, "branch_id").unwrap_or_else(|| first_branch.clone()),
                purpose: s(x, "purpose"),
                by: actor(so(x, "handed_by")).unwrap_or_default(),
                via: s(x, "via"),
            });
        }
        let mut notices: Vec<NoticeV> = rows("dawam_notifications")
            .iter()
            .map(|n| NoticeV { id: s(n, "id"), text: notice_text(&locale, &s(n, "key"), &n["args"]), at: s(n, "created_at"), read: !n["read_at"].is_null() })
            .collect();
        notices.sort_by(|a, z| z.at.cmp(&a.at));
        out.notices = notices;
        if out.can_manage {
            let owner = out.role == "owner";
            let visible: HashSet<&str> = out.people.iter().map(|p| p.id.as_str()).collect();
            let mut inbox: Vec<&ReqV> = out
                .requests
                .iter()
                .filter(|r| r.status == "pending" && r.emp != me && visible.contains(r.emp.as_str()) && (!r.to_owner || owner))
                .collect();
            inbox.sort_by(|a, z| z.created.cmp(&a.created));
            out.inbox = inbox.into_iter().map(|r| r.id.clone()).collect();
        }

        // Pay: the period, its live preview or frozen slips, and history.
        let periods = rows("dawam_periods");
        let period_of = |p: &Value| PeriodV {
            id: so(p, "id"),
            start: s(p, "start_date"),
            end: s(p, "end_date"),
            status: match s(p, "status").as_str() {
                "generated" => "approved",
                "paid" | "closed" => "paid",
                _ => "open",
            }
            .into(),
            paid_by: BTreeMap::new(),
        };
        out.period = if current.is_object() {
            period_of(&current["period"])
        } else if estimate.is_object() {
            PeriodV { id: None, start: s(&estimate, "period_start"), end: s(&estimate, "period_end"), status: "open".into(), paid_by: BTreeMap::new() }
        } else {
            let (a, z) = period_around(today, out.settings.period_start_day);
            PeriodV { id: None, start: a.to_string(), end: z.to_string(), status: "open".into(), paid_by: BTreeMap::new() }
        };
        for p in periods.iter().filter(|p| s(p, "start_date") != out.period.start) {
            out.history.push(period_of(p));
        }
        for c in rows("dawam_preview") {
            out.slips.push(slip_of(c, &out.period, i(c, "base_piastres"), false));
        }
        if let Some(sl) = estimate.get("slip").filter(|x| x.is_object()) {
            if !out.slips.iter().any(|x| x.emp == s(sl, "employee_id")) {
                out.slips.push(slip_of(sl, &out.period, i(sl, "base_piastres"), false));
            }
        }
        for sl in rows("dawam_payslips") {
            let start = s(sl, "period_start");
            let base = i(sl, "net_piastres") - i(sl, "overtime_piastres") - i(sl, "bonuses_piastres") + i(sl, "deductions_piastres") + i(sl, "advance_installment_piastres");
            let user = s(sl, "employee_id");
            let method = so(sl, "paid_method");
            let target = if start == out.period.start {
                if !current.is_object() {
                    out.period.status = if method.is_some() { "paid".into() } else { "approved".into() };
                }
                &mut out.period
            } else {
                if !out.history.iter().any(|h| h.start == start) {
                    out.history.push(PeriodV { id: None, start: start.clone(), end: s(sl, "period_end"), status: "paid".into(), paid_by: BTreeMap::new() });
                }
                out.history.iter_mut().find(|h| h.start == start).unwrap()
            };
            if let Some(m) = method {
                target.paid_by.insert(user.clone(), m);
            }
            let p = target.clone();
            out.slips.retain(|x| !(x.emp == user && x.start == start));
            out.slips.push(slip_of(sl, &p, base, true));
        }
        out.history.sort_by(|a, z| z.start.cmp(&a.start));

        // Suggestions and holidays.
        for g in rows("dawam_suggestions") {
            let args: BTreeMap<String, String> = g["reason_args"].as_object().into_iter().flatten().map(|(k, v)| (k.clone(), v.as_str().map_or_else(|| v.to_string(), str::to_string))).collect();
            let why = fill(&i18n::tr(&locale, &s(g, "reason_key")), &args);
            let d = date(g, "date").unwrap_or(today);
            let from = so(g, "from_employee_id");
            let text = match &from {
                None => format!("{} → {} · {why}", s(g, "employee_name"), s(g, "shift_name")),
                Some(_) => format!("{} ↔ {} · {why}", s(g, "employee_name"), s(g, "from_employee_name")),
            };
            out.suggestions.push(SuggestionV {
                id: s(g, "id"),
                branch: s(g, "branch_id"),
                date: d.to_string(),
                text,
                confidence: i(g, "confidence"),
                shift: from.map(|u| shift_id(&u, d, &s(g, "work_shift_id"))),
                emp: s(g, "employee_id"),
                tpl: s(g, "work_shift_id"),
                by_default: b(g, "by_default"),
            });
        }
        for h in rows("dawam_holidays") {
            out.holidays.push(HolidayV { date: s(h, "on_date"), en: s(h, "name_en"), ar: s(h, "name_ar"), decision: so(h, "decision") });
        }

        // The server's labour warnings (RU-13): one rule, decided there.
        out.warnings = labour_warnings(warn_rows.as_array().map(Vec::as_slice).unwrap_or(&[]));
        out.coverage = coverage.as_object().into_iter().flatten().map(|(k, v)| (k.clone(), v.clone())).collect();

        // Inside the fence of where I work now, from the last reading.
        let fix: Option<DawamFix> = self.store.kv_get(K_FIX).ok().flatten().and_then(|j| serde_json::from_str(&j).ok());
        out.charge_phone = out.active_shift.is_some() && fix.as_ref().and_then(|x| x.battery).is_some_and(|b| b <= LOW_BATTERY);
        let here_branch = out.my_now.first().and_then(|sid| shifts.iter().find(|x| &x.id == sid)).and_then(|x| tpl(&x.tpl)).map(|t| t.branch.clone());
        if let (Some(fx), Some(bid)) = (fix, here_branch) {
            if let Some(br) = rows("dawam_branches").iter().find(|x| s(x, "id") == bid) {
                if let (Some(lat), Some(lng)) = (br.get("latitude").and_then(Value::as_f64), br.get("longitude").and_then(Value::as_f64)) {
                    let d = haversine_m((lat, lng), (fx.latitude, fx.longitude));
                    out.distance_m = Some(d.round());
                    out.inside = Some(d <= i(br, "geo_radius_meters").max(1) as f64 || br.get("geo_radius_meters").is_none_or(Value::is_null) && d <= 200.0);
                }
            }
        }

        shifts.sort_by(|a, z| (a.date.as_str(), a.id.as_str()).cmp(&(z.date.as_str(), z.id.as_str())));
        out.shifts = shifts;
        Ok(out)
    }
}

/// `user|date|tpl` → its parts.
fn parts(id: &str) -> (&str, &str, &str) {
    let mut p = id.splitn(3, '|');
    (p.next().unwrap_or_default(), p.next().unwrap_or_default(), p.next().unwrap_or_default())
}

fn shift_start(d: &str, tp: &TplV, tz: &chrono_tz::Tz) -> Option<DateTime<Utc>> {
    let d = NaiveDate::parse_from_str(d, "%Y-%m-%d").ok()?;
    let t = NaiveTime::from_num_seconds_from_midnight_opt((tp.start * 60) as u32, 0)?;
    tz.from_local_datetime(&d.and_time(t)).earliest().map(|x| x.with_timezone(&Utc))
}

fn shift_end(d: &str, tp: &TplV, tz: &chrono_tz::Tz) -> Option<DateTime<Utc>> {
    let len = { let l = (tp.end - tp.start).rem_euclid(1440); if l == 0 { 1440 } else { l } };
    shift_start(d, tp, tz).map(|a| a + Duration::minutes(len))
}

/// The pay period `d` falls in, for a business starting on `start_day` (PAY-1).
fn period_around(d: NaiveDate, start_day: i64) -> (NaiveDate, NaiveDate) {
    let sd = start_day.clamp(1, 28) as u32;
    let this = NaiveDate::from_ymd_opt(d.year(), d.month(), sd).unwrap_or(d);
    let start = if d >= this { this } else { this - chrono::Months::new(1) };
    (start, start + chrono::Months::new(1) - Duration::days(1))
}

fn fill(s: &str, args: &BTreeMap<String, String>) -> String {
    args.iter().fold(s.to_string(), |acc, (k, v)| acc.replace(&format!("{{{k}}}"), v))
}

/// Money on screen: EGP with the sign (AT-2: piastres everywhere else).
fn egp(p: i64, ar: bool) -> String {
    let body = format!("{}.{:02}", group(p.abs() / 100), p.abs() % 100);
    let sign = if p < 0 { "-" } else { "" };
    if ar { format!("{sign}{body} ج.م") } else { format!("{sign}EGP {body}") }
}

fn group(n: i64) -> String {
    let s = n.to_string();
    let mut out = String::new();
    for (ix, c) in s.chars().enumerate() {
        if ix > 0 && (s.len() - ix).is_multiple_of(3) {
            out.push(',');
        }
        out.push(c);
    }
    out
}

/// An inbox line in the phone's language (the server sends a key and args).
/// The manager side opens on what the server lets them read (PM-4): a
/// manager's role with no `hr.*` read capability gets the employee's app.
/// The manager tabs this person sees, from the capabilities the server says
/// they hold (PM-4) — never from their role's name.
#[derive(Serialize, Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct ManageTabs {
    /// Who's in, flags, punch for someone.
    pub team: bool,
    /// Requests, advances, covers, overtime, swaps and claims to decide.
    pub approvals: bool,
    /// The roster board.
    pub schedule: bool,
    /// Run, approve and pay the month.
    pub payroll: bool,
}

/// What decides each tab: any one capability of its list.
const TAB_CAPS: [(&str, &[&str]); 4] = [
    ("team", &["hr.attendance.read"]),
    (
        "approvals",
        &["hr.leave.edit", "hr.advances.decide", "hr.shift_cover.confirm", "hr.overtime.approve", "hr.schedule.edit", "hr.payroll.run"],
    ),
    ("schedule", &["hr.schedule.read"]),
    ("payroll", &["hr.payroll.run"]),
];

pub(crate) fn manage_tabs(caps: &[String]) -> ManageTabs {
    let held = |tab: &str| {
        TAB_CAPS.iter().find(|(t, _)| *t == tab).is_some_and(|(_, need)| need.iter().any(|n| caps.iter().any(|c| c == n)))
    };
    ManageTabs { team: held("team"), approvals: held("approvals"), schedule: held("schedule"), payroll: held("payroll") }
}

fn manages(ctx: &Value) -> bool {
    let caps: Vec<String> = arr(ctx, "caps").iter().filter_map(Value::as_str).map(str::to_string).collect();
    let t = manage_tabs(&caps);
    t.team || t.approvals || t.schedule || t.payroll
}

fn notice_text(locale: &str, key: &str, args: &Value) -> String {
    let ar = i18n::is_arabic(locale);
    let mut filled = BTreeMap::new();
    for (k, v) in args.as_object().into_iter().flatten() {
        let text = match (k.as_str(), v) {
            (k, Value::Number(n)) if k.contains("amount") => egp(n.as_i64().unwrap_or(0), ar),
            ("kind", Value::String(x)) => {
                let w = i18n::tr(locale, &format!("staff.kind_{x}"));
                if w.starts_with("staff.") { x.clone() } else { w }
            }
            ("date", Value::String(x)) => NaiveDate::parse_from_str(&x[..x.len().min(10)], "%Y-%m-%d")
                .map(|d| format!("{} {}", d.day(), i18n::tr(locale, &format!("staff.month_{}", d.month()))))
                .unwrap_or_else(|_| x.clone()),
            (_, Value::String(x)) => x.clone(),
            (_, x) => x.to_string(),
        };
        filled.insert(k.clone(), text);
    }
    fill(&i18n::tr(locale, key), &filled)
}

/// A payslip's lines from the server's figures and breakdown (PAY-2: the
/// preview and the frozen slip read the same shape).
fn slip_of(s_: &Value, p: &PeriodV, base: i64, frozen: bool) -> SlipV {
    let bd = &s_["breakdown"];
    let mut lines = Vec::new();
    let (paid, window) = (i(bd, "paid_days"), i(bd, "window_days"));
    let partial = paid > 0 && paid < window;
    lines.push(LineV {
        key: "salary".into(),
        en: if partial { format!("Salary ({paid} of {window} days)") } else { "Salary".into() },
        ar: if partial { format!("المرتب ({paid} من {window} يوم)") } else { "المرتب".into() },
        amount: base,
        rule: false,
        manual: None,
        waived: false,
    });
    let ot = i(s_, "overtime_piastres");
    if ot > 0 {
        let m = i(s_, "overtime_minutes");
        lines.push(LineV { key: "ot".into(), en: format!("Overtime ({m} min)"), ar: format!("وقت إضافي ({m} د)"), amount: ot, rule: false, manual: None, waived: false });
    }
    for l in arr(bd, "bonuses") {
        let (en, ar) = match (s(l, "kind").as_str(), s(l, "reason")) {
            ("cover", _) => ("Cover shifts".to_string(), "ورديات تغطية".to_string()),
            ("holiday", _) => ("Public holiday worked".to_string(), "شغل في إجازة رسمية".to_string()),
            (_, r) => (r.clone(), r),
        };
        let id = so(l, "id");
        lines.push(LineV { key: format!("b|{}", id.clone().unwrap_or_default()), en, ar, amount: i(l, "piastres"), rule: false, manual: id.map(|x| format!("a|bonus|{x}")), waived: false });
    }
    for l in arr(bd, "deductions") {
        let carry = s(l, "kind") == "carry";
        let manual = s(l, "source") == "manual";
        let id = s(l, "id");
        lines.push(LineV {
            key: if carry { "carry".into() } else { format!("d|{id}") },
            en: if carry { "Carried from the last payslip".into() } else { s(l, "reason") },
            ar: if carry { "مُرحّل من القسيمة اللي فاتت".into() } else { s(l, "reason") },
            amount: -i(l, "piastres"),
            rule: !carry && !manual,
            manual: manual.then(|| format!("a|deduction|{id}")),
            waived: b(l, "waived"),
        });
    }
    let mut collected = BTreeMap::new();
    for a in arr(bd, "advances") {
        let take = i(a, "applied_piastres");
        if take == 0 {
            continue;
        }
        collected.insert(s(a, "id"), take);
        lines.push(LineV { key: format!("adv|{}", s(a, "id")), en: "Advance installment".into(), ar: "قسط سلفة".into(), amount: -take, rule: false, manual: None, waived: false });
    }
    SlipV { emp: s(s_, "employee_id"), start: p.start.clone(), end: p.end.clone(), lines, net: i(s_, "net_piastres"), carry_out: i(s_, "carry_out_piastres"), collected, frozen }
}

/// At or under this on shift, the phone says charge (CL-12, the server's figure).
const LOW_BATTERY: i64 = 15;

/// The server's labour-limit warnings (RU-13) as core i18n keys, keyed
/// `user|week_start`. They warn and never block.
fn labour_warnings(rows: &[Value]) -> BTreeMap<String, Vec<(String, Value)>> {
    let mut out: BTreeMap<String, Vec<(String, Value)>> = BTreeMap::new();
    for w in rows {
        let Some(d) = date(w, "date") else { continue };
        let hours = |m: i64| {
            let h = m as f64 / 60.0;
            if h.fract() == 0.0 { format!("{h:.0}") } else { format!("{h:.1}") }
        };
        let key = format!("staff.warn_{}", s(w, "kind"));
        let args = json!({ "date": d.to_string(), "hours": hours(i(w, "limit_minutes")), "worked": hours(i(w, "minutes")) });
        let entry = out.entry(format!("{}|{}", s(w, "employee_id"), week_start(d))).or_default();
        if !entry.iter().any(|(k, a)| *k == key && *a == args) {
            entry.push((key, args));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Timelike;

    #[test]
    fn weeks_start_on_saturday_and_periods_on_the_start_day() {
        let d = NaiveDate::from_ymd_opt(2026, 9, 22).unwrap(); // a Tuesday
        assert_eq!(week_start(d), NaiveDate::from_ymd_opt(2026, 9, 19).unwrap());
        assert_eq!(week_start(NaiveDate::from_ymd_opt(2026, 9, 19).unwrap()), NaiveDate::from_ymd_opt(2026, 9, 19).unwrap());
        let (a, z) = period_around(d, 26);
        assert_eq!((a.to_string(), z.to_string()), ("2026-08-26".into(), "2026-09-25".into()));
        let (a, _) = period_around(NaiveDate::from_ymd_opt(2026, 9, 26).unwrap(), 26);
        assert_eq!(a.to_string(), "2026-09-26");
    }

    #[test]
    fn an_offline_stamp_counts_uptime_and_notices_a_reboot() {
        let a = Anchor { server_ms: 1_000_000, boot_ms: 50_000, wall_ms: 2_000_000 };
        let s = stamp(Some(a), 110_000, 2_060_000, None);
        assert_eq!(s["elapsed_ms"], 60_000);
        assert_eq!(s["rebooted"], false);
        // Uptime went backwards: the phone restarted.
        let s = stamp(Some(a), 5_000, 2_060_000, Some("2026-09-22T08:00:00Z"));
        assert_eq!(s["rebooted"], true);
        assert_eq!(s["gps_time"], "2026-09-22T08:00:00Z");
        // Restarted and has since run longer than before: the boot moment moved.
        let s = stamp(Some(a), 60_000_000, 2_000_000 + 3_600_000 * 20, None);
        assert_eq!(s["rebooted"], true);
    }

    /// AT-1: every instant the app reads is in the branch's zone, so a phone
    /// set to another zone still shows the branch's wall-clock time.
    #[test]
    fn instants_are_written_in_the_branch_zone_and_dates_are_left_alone() {
        let mut v = json!({
            "now": "2026-09-23T06:02:00Z",
            "shifts": [{ "in_at": "2026-09-23T06:02:00.123456+00:00", "date": "2026-09-23" }],
            "notices": [{ "at": "2026-01-15T22:30:00Z", "text": "not a time: 2026-09-23T06:02:00Z" }],
            "odd": "2026-09-23T25:99:00Z",
        });
        in_branch_zone(&mut v, &chrono_tz::Africa::Cairo);
        assert_eq!(v["now"], "2026-09-23T09:02:00+03:00", "summer time in Cairo");
        assert_eq!(v["shifts"][0]["in_at"], "2026-09-23T09:02:00.123456+03:00");
        assert_eq!(v["shifts"][0]["date"], "2026-09-23");
        assert_eq!(v["notices"][0]["at"], "2026-01-16T00:30:00+02:00", "winter time, and the next day");
        assert_eq!(v["notices"][0]["text"], "not a time: 2026-09-23T06:02:00Z");
        assert_eq!(v["odd"], "2026-09-23T25:99:00Z", "unparseable text stays as it came");
        // Another zone moves the wall clock, never the instant.
        let mut w = json!("2026-09-23T06:02:00Z");
        in_branch_zone(&mut w, &chrono_tz::Asia::Dubai);
        assert_eq!(w, "2026-09-23T10:02:00+04:00");
    }

    /// PM-4: the manager tabs follow capabilities, not the role's name — a
    /// "manager" with no rights sees none, an employee granted one sees it.
    #[test]
    fn manager_tabs_come_from_capabilities_not_the_role() {
        let caps = |c: &[&str]| c.iter().map(|x| x.to_string()).collect::<Vec<_>>();
        assert_eq!(manage_tabs(&caps(&[])), ManageTabs::default());
        assert_eq!(manage_tabs(&caps(&["hr.staff.read"])), ManageTabs::default(), "reading staff opens no tab");
        let t = manage_tabs(&caps(&["hr.schedule.read"]));
        assert!(t.schedule && !t.team && !t.approvals && !t.payroll);
        let t = manage_tabs(&caps(&["hr.overtime.approve"]));
        assert!(t.approvals && !t.schedule);
        let t = manage_tabs(&caps(&["hr.payroll.run"]));
        assert!(t.payroll && t.approvals, "the payroll runner decides pay lines over the limit");
        assert!(!manages(&json!({ "role": "manager", "caps": [] })), "a manager role without rights manages nothing");
        assert!(manages(&json!({ "role": "employee", "caps": ["hr.attendance.read"] })), "an employee granted a right manages");
    }

    #[test]
    fn labour_warnings_come_from_the_server_keyed_by_week() {
        let rows = vec![
            json!({ "employee_id": "u", "date": "2026-09-20", "kind": "rest", "minutes": 480, "limit_minutes": 720 }),
            json!({ "employee_id": "u", "date": "2026-09-19", "kind": "week_hours", "minutes": 3000, "limit_minutes": 2880 }),
            json!({ "employee_id": "u", "date": "2026-09-21", "kind": "day_hours", "minutes": 540, "limit_minutes": 450 }),
        ];
        let w = labour_warnings(&rows);
        let week = &w["u|2026-09-19"];
        assert_eq!(week[0], ("staff.warn_rest".to_string(), json!({ "date": "2026-09-20", "hours": "12", "worked": "8" })));
        assert_eq!(week[1].0, "staff.warn_week_hours");
        assert_eq!(week[2].1["hours"], "7.5");
    }

    #[test]
    fn a_payslip_reads_the_servers_lines() {
        let p = PeriodV { start: "2026-08-26".into(), end: "2026-09-25".into(), status: "open".into(), ..Default::default() };
        let c = json!({
            "employee_id": "u", "net_piastres": 842_000, "carry_out_piastres": 0,
            "overtime_piastres": 0, "overtime_minutes": 0,
            "breakdown": {
                "paid_days": 31, "window_days": 31,
                "bonuses": [{ "id": null, "kind": "cover", "reason": "cover", "piastres": 12_000 }],
                "deductions": [
                    { "id": "d1", "reason": "Late", "piastres": 5_000, "source": "late_penalty" },
                    { "id": "d2", "reason": "Broke a glass", "piastres": 15_000, "source": "manual" }
                ],
                "advances": [{ "id": "v1", "applied_piastres": 50_000 }]
            }
        });
        let sl = slip_of(&c, &p, 900_000, false);
        assert_eq!(sl.lines.iter().map(|l| l.amount).sum::<i64>(), 842_000, "the lines add up to the net");
        assert!(sl.lines.iter().any(|l| l.key == "d|d1" && l.rule), "a rule line is waivable, not deletable");
        assert!(sl.lines.iter().any(|l| l.manual.as_deref() == Some("a|deduction|d2")));
        assert_eq!(sl.collected["v1"], 50_000);
    }


    /// The whole offline path (APP-8, CL-10, CL-11): clock in and ping with the
    /// server gone, see both on screen at once, then watch them reach the
    /// server in order with the time the server needs to date them.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_punch_and_a_ping_wait_offline_then_reach_the_server_in_order() {
        use crate::testkit::{online_core, Stub, StubResponse, BRANCH, TELLER};
        use std::sync::atomic::{AtomicBool, Ordering};
        use std::sync::Arc;

        let up = Arc::new(AtomicBool::new(true));
        let flag = up.clone();
        let cairo = Utc::now().with_timezone(&chrono_tz::Africa::Cairo);
        let today = cairo.date_naive().to_string();
        let hms = |t: NaiveTime| format!("{}:00", hhmm((t.hour() * 60 + t.minute()) as i64));
        let (start, end) = (hms(cairo.time() - Duration::hours(1)), hms(cairo.time() + Duration::hours(3)));
        let stub = Stub::start(move |r| {
            if !flag.load(Ordering::SeqCst) {
                return Some(StubResponse::hangup());
            }
            let path = r.path.split('?').next().unwrap_or_default();
            Some(match path {
                "/staff/me/context" => StubResponse::json(200, json!({
                    "role": "employee", "org_name": "Nile Café", "caps": [],
                    "branches": [{ "id": BRANCH, "name": "Zamalek", "geo_radius_meters": 200,
                                   "latitude": 30.0609, "longitude": 31.2197, "timezone": "Africa/Cairo" }],
                    "work_shifts": [{ "id": "w1", "name": "Morning", "branch_id": BRANCH,
                                      "start_time": start, "end_time": end, "grace_minutes": 10 }],
                    "people": [{ "employee_id": TELLER, "name": "Sara", "role": "employee", "branch_ids": [BRANCH],
                                 "base_salary_piastres": 900000, "pay_method": "cash", "cant_work_days": [] }],
                    "settings": { "period_start_day": 26, "advance_cap_percent": "50" },
                })),
                "/staff/me/roster" => StubResponse::json(200, json!({
                    "shifts": [{ "employee_id": TELLER, "date": today, "work_shift_id": "w1" }],
                    "team": [], "open_shifts": [], "swaps": [], "unpublished_weeks": [],
                })),
                "/staff/me/check-in" => StubResponse::json(201, json!({ "id": "r1" })),
                "/staff/me/pings" => StubResponse::json(200, json!({ "inside": true })),
                "/health" => StubResponse::text(200, "ok"),
                p if p.ends_with("estimate") || p.ends_with("context") => StubResponse::json(200, json!({})),
                _ => StubResponse::json(200, json!([])),
            })
        })
        .await;
        let core = online_core(&stub.base, "").await;
        core.set_online(true);
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        let shift = snap["my_now"][0].as_str().expect("today's shift is mine").to_string();

        // The connection drops.
        up.store(false, Ordering::SeqCst);
        let fix = DawamFix { latitude: 30.0609, longitude: 31.2197, accuracy: Some(8.0), ..Default::default() };
        let act = json!({ "action": "clock_in", "shift": shift, "fix": fix }).to_string();
        let snap: Value = serde_json::from_str(&core.dawam_do(act).await.unwrap()).unwrap();
        assert_eq!(snap["active_shift"], json!(shift), "the queued punch shows at once");
        assert_eq!(snap["queued"], 1);
        let sh = snap["shifts"].as_array().unwrap().iter().find(|x| x["id"] == json!(shift)).unwrap();
        assert!(sh["queued"].as_bool().unwrap() && sh["in_at"].is_string());
        // AT-1: the queued punch and the clock read in the branch's zone.
        let off = cairo.format("%:z").to_string();
        assert!(sh["in_at"].as_str().unwrap().ends_with(&off), "{} in {off}", sh["in_at"]);
        assert!(snap["now"].as_str().unwrap().ends_with(&off), "{} in {off}", snap["now"]);
        let snap: Value = serde_json::from_str(&core.dawam_ping(fix).await.unwrap()).unwrap();
        assert_eq!(snap["queued"], 2, "the ping waits too");
        assert_eq!(snap["inside"], true);

        // Minutes later the connection is back: both go, in order, dated.
        core.store.with_conn(|c| Ok(c.execute("UPDATE outbox SET payload = json_set(payload, '$.queued_ms', 0)", [])?)).unwrap();
        stub.seen.lock().unwrap().clear(); // it logs the attempts it hung up on
        up.store(true, Ordering::SeqCst);
        let snap: Value = serde_json::from_str(&core.dawam_sync().await.unwrap()).unwrap();
        assert_eq!(snap["queued"], 0);
        let seen: Vec<_> = stub.seen.lock().unwrap().iter().filter(|r| r.method == "POST").cloned().collect();
        assert_eq!(seen.iter().map(|r| r.path.as_str()).collect::<Vec<_>>(), ["/staff/me/check-in", "/staff/me/pings"]);
        let body = seen[0].json();
        assert_eq!(body["branch_id"], BRANCH);
        assert_eq!(body["offline"]["rebooted"], false);
        assert!(body["offline"]["server_time"].is_string() && body["offline"]["elapsed_ms"].as_i64().unwrap() >= 0);
        assert!(seen[1].json()["offline"].is_object());
    }

    /// A punch queued while the staff token lapsed is sent after a refresh,
    /// not parked waiting for a sign-in that never comes.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_queued_punch_refreshes_the_token_and_replays_rather_than_parks() {
        use crate::staff::session_tests::{later, session, signed_in, EMP, ORG};
        use crate::testkit::{Stub, StubResponse};

        let exp = later();
        let stub = Stub::start(move |r| {
            let bearer = r.header("authorization").unwrap_or_default();
            let path = r.path.split('?').next().unwrap_or_default();
            Some(match path {
                "/auth/staff/otp/verify" => StubResponse::json(200, session(&exp)),
                "/auth/staff/refresh" => StubResponse::json(200, json!({ "token": "t2", "expires_at": later(), "employee_id": EMP, "org_id": ORG })),
                "/health" => StubResponse::text(200, "ok"),
                _ if bearer == "Bearer t1" => StubResponse::json(401, json!({ "error": "expired", "code": "TOKEN_EXPIRED" })),
                "/staff/me/context" => StubResponse::json(200, json!({
                    "employee_id": EMP, "name": "Sara", "role": "employee", "org_name": "Nile", "caps": [],
                    "branches": [], "work_shifts": [], "settings": {},
                    "people": [{ "employee_id": EMP, "name": "Sara", "role": "employee", "branch_ids": [] }],
                })),
                "/staff/me/pings" => StubResponse::json(200, json!({ "inside": true })),
                p if p.ends_with("estimate") => StubResponse::json(200, json!({})),
                _ => StubResponse::json(200, json!([])),
            })
        })
        .await;
        let core = signed_in(&stub).await;
        core.dawam_enqueue("dawam_ping", "/staff/me/pings", json!({ "latitude": 30.0, "longitude": 31.0 }), None).unwrap();
        let snap: Value = serde_json::from_str(&core.dawam_sync().await.unwrap()).unwrap();
        assert_eq!(snap["queued"], 0, "sent, not parked");
        assert_eq!(snap["me"], EMP, "me is the employee");
        assert!(!core.sync_status().auth_paused);
        let pings: Vec<_> = stub.requests("/staff/me/pings").iter().map(|r| r.header("authorization")).collect();
        assert_eq!(pings, [Some("Bearer t1".into()), Some("Bearer t2".into())], "refused, refreshed, replayed");
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn a_late_arrival_keeps_its_time_in_to_time_both_ways() {
        use crate::testkit::{online_core, Stub, StubResponse, BRANCH, TELLER};

        let today = Utc::now().with_timezone(&chrono_tz::Africa::Cairo).date_naive().to_string();
        let day = today.clone();
        let stub = Stub::start(move |r| {
            let path = r.path.split('?').next().unwrap_or_default();
            Some(match (r.method.as_str(), path) {
                (_, "/staff/me/context") => StubResponse::json(200, json!({
                    "role": "employee", "org_name": "Nile Café", "caps": [],
                    "branches": [{ "id": BRANCH, "name": "Zamalek", "timezone": "Africa/Cairo" }],
                    "work_shifts": [], "settings": { "period_start_day": 26 },
                    "people": [{ "employee_id": TELLER, "name": "Sara", "role": "employee", "branch_ids": [BRANCH] }],
                })),
                // As the server stores it: the arrival in `to_time`, no `from_time`.
                ("GET", "/staff/me/requests") => StubResponse::json(200, json!([{
                    "id": "q1", "kind": "late_arrival", "employee_id": TELLER, "status": "pending",
                    "on_date": day, "from_time": null, "to_time": "09:30:00", "is_half_day": false,
                    "reason": "Exam", "created_at": "2026-09-22T08:00:00Z",
                }])),
                ("POST", "/staff/me/requests") => StubResponse::json(201, json!({ "id": "q2" })),
                (_, "/health") => StubResponse::text(200, "ok"),
                (_, p) if p.ends_with("estimate") => StubResponse::json(200, json!({})),
                _ => StubResponse::json(200, json!([])),
            })
        })
        .await;
        let core = online_core(&stub.base, "").await;
        core.set_online(true);

        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        let q = snap["requests"].as_array().unwrap().iter().find(|q| q["kind"] == "lateArrival").expect("the late arrival");
        assert_eq!(q["time"], 570, "09:30 read from to_time");

        let act = json!({ "action": "file", "kind": "lateArrival", "from": today, "time": 600 }).to_string();
        core.dawam_do(act).await.unwrap();
        let seen = stub.seen.lock().unwrap();
        let post = seen.iter().find(|r| r.method == "POST" && r.path == "/staff/me/requests").expect("filed");
        let body = post.json();
        assert_eq!(body["to_time"], "10:00");
        assert!(body.get("from_time").is_none(), "the server refuses a from_time on a late arrival");
    }

    /// APP-6 / 06 B3: signing out tells the server first (it forgets the
    /// phone and its pushes), and a server that can't be reached never
    /// holds the sign-out up.
    #[tokio::test(flavor = "multi_thread")]
    async fn signing_out_unregisters_this_phone_on_the_server() {
        use crate::testkit::{online_core, Stub, StubResponse};
        let stub = Stub::start(|r| {
            Some(match (r.method.as_str(), r.path.as_str()) {
                ("POST", "/staff/me/sign-out") => StubResponse::json(204, json!(null)),
                _ => StubResponse::json(200, json!({})),
            })
        })
        .await;
        let core = online_core(&stub.base, "").await;
        core.set_online(true);
        let out = core.dawam_do(json!({ "action": "sign_out" }).to_string()).await.unwrap();
        assert_eq!(out, "{}");
        assert_eq!(stub.requests("/staff/me/sign-out").len(), 1);

        let down = Stub::start(|_| Some(StubResponse::hangup())).await;
        let core = online_core(&down.base, "").await;
        core.set_online(false);
        assert!(core.dawam_do(json!({ "action": "sign_out" }).to_string()).await.is_err(), "the host still signs out");
    }

    #[test]
    fn an_action_reads_from_json() {
        let a: Act = serde_json::from_str(r#"{"action":"clock_in","shift":"u|2026-09-22|w","fix":{"latitude":30,"longitude":31}}"#).unwrap();
        assert!(a.queueable());
        let a: Act = serde_json::from_str(r#"{"action":"file","kind":"lateArrival","from":"2026-09-22","time":570}"#).unwrap();
        assert!(!a.queueable());
        assert!(serde_json::from_str::<Act>(r#"{"action":"read_all"}"#).is_ok());
    }
}
