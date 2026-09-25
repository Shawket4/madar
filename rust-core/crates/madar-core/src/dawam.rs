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

use chrono::{DateTime, Datelike, Duration, NaiveDate, NaiveDateTime, NaiveTime, TimeZone, Timelike, Utc};
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

/// The server's refusal of a location before this phone accepted the notice.
pub(crate) const PRIVACY_NOT_ACCEPTED: &str = "PRIVACY_NOT_ACCEPTED";

/// Outbox op types (the drain sends them to `/staff/*`, not `/sync/replay`).
pub(crate) const OP_PREFIX: &str = "dawam_";
/// The last (server time, time since boot, wall time) the phone saw.
const K_ANCHOR: &str = "dawam:anchor";
const K_FIX: &str = "dawam:fix";
/// A reading older than this says nothing about where the person is now: the
/// fence line reads "unknown", never "inside" (06 B4).
const FIX_FRESH_MS: i64 = 10 * 60_000;
/// Sent within this long of being queued, a punch goes as live, not offline.
const LIVE_MS: i64 = 30_000;

// ── time since boot (CL-11) ───────────────────────────────────────────────

/// Milliseconds since the phone booted, counting deep sleep: `CLOCK_BOOTTIME`
/// on Android, `CLOCK_MONOTONIC` on Apple (which keeps counting asleep).
pub(crate) fn boot_ms() -> i64 {
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

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
struct Anchor {
    server_ms: i64,
    boot_ms: i64,
    wall_ms: i64,
    /// The server's signature over `server_ms` for this phone (`X-Dawam-Time`).
    /// Without it the server dates the punch but marks it unverified.
    #[serde(default)]
    sig: Option<String>,
}

/// What the server needs to date an event recorded now (`OfflineStamp`).
fn stamp(anchor: Option<Anchor>, boot: i64, wall: i64, gps_time: Option<&str>) -> Value {
    let Some(a) = anchor else {
        // Never saw the server: only the satellites can date it.
        return json!({ "server_time": ms_rfc3339(wall), "elapsed_ms": 0, "rebooted": true, "gps_time": gps_time });
    };
    let mut v = stamp_unsigned(&a, boot, wall, gps_time);
    if let Some(sig) = a.sig {
        v["anchor"] = json!(sig);
    }
    v
}

fn stamp_unsigned(a: &Anchor, boot: i64, wall: i64, gps_time: Option<&str>) -> Value {
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

/// The last reading and when it was taken (time since boot, so a clock change
/// can't make an old one look fresh; a reboot makes it stale).
#[derive(Deserialize, Serialize, Clone, Debug, Default)]
struct NotedFix {
    #[serde(flatten)]
    fix: DawamFix,
    #[serde(default)]
    noted_boot_ms: Option<i64>,
}

impl NotedFix {
    fn fresh_at(&self, boot: i64) -> bool {
        self.noted_boot_ms.is_some_and(|b| boot >= b && boot - b <= FIX_FRESH_MS)
    }
}

/// Great-circle metres between `(lat, lng)` points: madar-shared's
/// `madar_dawam::geofence::haversine_m`, the server's `haversine_meters`.
fn haversine_m(a: (f64, f64), b: (f64, f64)) -> f64 {
    madar_dawam::geofence::haversine_m(a, b)
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
    /// My own requests are approved as I file them (`hr.requests.self_approve`,
    /// RQ-5): a leave then needs its paid/unpaid choice at filing (RQ-2).
    pub self_approves: bool,
    /// Which manager tabs show, from `caps` (PM-4).
    pub tabs: ManageTabs,
    /// Public holidays are the owner's (decision #3): set or dismissed only
    /// by someone holding the rules right at every branch. Everyone else
    /// reads them.
    pub decides_holidays: bool,
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
    /// The cap only where the server shows it (the salary's visibility).
    pub advance_cap: BTreeMap<String, i64>,
    /// Per person: what they owe is within the cap, the server's word for
    /// someone whose cap I may not see (decision #7).
    pub advance_within: BTreeMap<String, bool>,
    pub outstanding: BTreeMap<String, i64>,
    /// Paid through Dawam. Off (an app-using owner, say): no estimate, no
    /// payslips, but every other screen works.
    pub on_payroll: bool,
    /// People on this month's payroll with no salary set (decision #9): the
    /// server's count. Approval is refused while it is above 0.
    pub missing_salary_count: i64,
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
    /// `emp|date` of every date that holds its own set (the server's
    /// `date_sets`): it can go back to the usual pattern.
    pub own_days: Vec<String>,
    /// `emp|date` of the dates changed to a day off.
    pub days_off: Vec<String>,
    /// Each colleague's state right now, as the server decides it (AT-3):
    /// employee id → `state` (`in` | `late` | `absent` | `on_leave` | `off` |
    /// `done`), `since` (clock-in) and `late_minutes`. Managers only; the
    /// phone never works presence out from grace times and its own clock.
    pub presence: BTreeMap<String, PresenceV>,
    /// Inside the fence of the branch I work at now, from a FRESH fix; `None`
    /// when there is no reading from the last few minutes (06 B4: unknown is
    /// never "inside").
    pub inside: Option<bool>,
    pub distance_m: Option<f64>,
    /// The same reading against every branch I may clock in at, by branch id
    /// (a shift card shows its own branch's line).
    pub fences: BTreeMap<String, FenceV>,
    /// This phone accepted the location notice, as the server recorded it
    /// (AT-5). Until then the app shows the notice, never the tabs.
    pub privacy_accepted: bool,
}

/// Where I am against one branch's fence, from a fresh reading.
#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct FenceV {
    /// `inside` · `outside` · `unknown` (no reading from the last minutes).
    pub state: String,
    /// Metres from the branch, rounded; `None` when unknown.
    pub distance_m: Option<i64>,
    pub radius: i64,
}

#[derive(Serialize, Debug, Default, PartialEq)]
pub struct PresenceV {
    pub state: String,
    pub since: Option<String>,
    pub late_minutes: i64,
}

/// The server's team board rows → presence by employee.
fn presence_of(board: &Value) -> BTreeMap<String, PresenceV> {
    arr(board, "rows")
        .iter()
        .map(|r| {
            (
                s(r, "employee_id"),
                PresenceV { state: s(r, "state"), since: so(r, "check_in_at"), late_minutes: r["late_minutes"].as_i64().unwrap_or(0) },
            )
        })
        .filter(|(id, p)| !id.is_empty() && !p.state.is_empty())
        .collect()
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
    /// My ceiling on a bonus before it waits for the owner (AD-5)…
    pub adjustment_limit: Option<i64>,
    /// …and on a deduction: two limits, the server's.
    pub deduction_limit: Option<i64>,
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
    /// The ISO weekdays (Mon = 1 … Sun = 7) the block may be rostered on;
    /// the board offers it only on those.
    pub days: Vec<i64>,
    /// Its own times on some weekdays (the server's), on top of start/end.
    pub day_times: Vec<DayTimeV>,
}

/// A block's own start/end on one ISO weekday (minutes of the day).
#[derive(Serialize, Debug, Clone)]
pub struct DayTimeV {
    pub day: i64,
    pub start: i64,
    pub end: i64,
}

impl TplV {
    /// The block's times on `d`: that weekday's own, else its default.
    fn times_on(&self, d: NaiveDate) -> (i64, i64) {
        let dow = i64::from(d.weekday().number_from_monday());
        self.day_times.iter().find(|t| t.day == dow).map_or((self.start, self.end), |t| (t.start, t.end))
    }
}

#[derive(Serialize, Debug)]
pub struct PersonV {
    pub id: String,
    pub name: String,
    pub phone: String,
    pub role: String,
    pub branches: Vec<String>,
    /// Monthly salary in piastres; `None` when not set or hidden from me
    /// (`salary_set` tells which, decision #9). Never a made-up 0.
    pub salary: Option<i64>,
    /// A salary is set. False: "not set" (—), payroll can't be approved
    /// while they are on it. An older server doesn't say: set.
    pub salary_set: bool,
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
    /// The EFFECTIVE times (minutes of the day) the server resolved: the
    /// assignment's own, else the block's for that weekday, else its default.
    pub start: i64,
    pub end: i64,
    /// Ends on the following date (it still belongs to `date`, SC-10).
    pub next_day: bool,
    /// The server's own instants for it (DW1): read as sent, never rebuilt
    /// from the wall-clock times, so a DST day can't lose or move a shift.
    #[serde(skip)]
    pub start_at: Option<DateTime<Utc>>,
    #[serde(skip)]
    pub end_at: Option<DateTime<Utc>>,
    /// This assignment has its own from/to: show it as edited.
    pub edited: bool,
    /// The date holds its own set of shifts (not the standing pattern).
    pub own_day: bool,
    /// On the roster (not only a worked record): part of the date's set.
    #[serde(skip)]
    pub rostered: bool,
    pub cover_by: Option<String>,
    /// A cover's own row (`cover|<record>`, the coverer's): whose shift it
    /// covered. The covered person's shift never takes the cover's punches.
    pub cover_of: Option<String>,
    /// That cover's decision: `pending` · `confirmed` · `rejected` (a
    /// rejected one is not paid and must not read like a confirmed one).
    pub cover_status: Option<String>,
    pub in_at: Option<String>,
    pub out_at: Option<String>,
    pub in_method: Option<String>,
    pub out_method: Option<String>,
    pub punch_reason: Option<String>,
    pub leave: Option<String>,
    pub half_leave: bool,
    /// Which half a half-day leave takes off: `first` or `second` (RQ-8).
    pub leave_half: Option<String>,
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
    /// Its day is in no approved or paid pay period, so it can still be
    /// fixed (RQ-4, B13). Decided here from the periods, not on the phone.
    pub month_open: bool,
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
    /// A manager's own request that someone above them decides (RQ-5): the
    /// server's word, never worked out from roles here.
    pub to_owner: bool,
    /// The pay an approver starts from for an excuse or early departure: the
    /// branch's rule, else the business's (RQ-7). `None` = the server didn't say.
    pub paid_default: Option<bool>,
    /// The server's answer to "may I decide this one?" (RQ-5) when it sends
    /// one; the inbox follows it over any reading of `to_owner`.
    pub can_decide: Option<bool>,
    /// A half-day leave's half: `first` or `second` (RQ-8).
    pub leave_half: Option<String>,
    /// An advance asked for: what would be owed with it is within the cap
    /// (the server's `within_cap`, decision #7).
    pub within_cap: Option<bool>,
    /// The work shift (template) a late arrival, early departure or excuse
    /// is for (B4); `None` = the shift its time falls in.
    pub tpl: Option<String>,
    pub decided_by: Option<String>,
    pub decision_note: Option<String>,
    /// Who cancelled it and why (RQ-F6): a cancel no longer overwrites the
    /// approval above; `None` when nobody but the filer cancelled it, or
    /// before the server kept cancels apart.
    pub cancelled_by: Option<String>,
    pub cancel_note: Option<String>,
    /// The canceller's name when the server sends it.
    pub cancelled_by_name: Option<String>,
    /// Every day it covers is in no approved or paid period: it can still be
    /// cancelled or changed (RQ-4, B13).
    pub month_open: bool,
}

#[derive(Serialize, Debug)]
pub struct AdjV {
    pub id: String,
    pub emp: String,
    pub bonus: bool,
    pub amount: i64,
    pub pct: Option<f64>,
    /// What it comes to: the server's figure (a % of salary already resolved).
    pub value: i64,
    /// A waived rule deduction: shown struck through, charged nothing (AD-6).
    pub waived: bool,
    pub reason: String,
    pub by: String,
    pub at: String,
    pub period: String,
    pub recurring: bool,
    pub status: String,
    /// A stopped every-month line's last day (`YYYY-MM-DD`): the end of the
    /// month that was open when it was stopped (decision #6).
    pub ends_on: Option<String>,
    /// A rule-made line (lateness, absence…): "Rule · absence" in the
    /// phone's language, never "One-off · by —" (minor #30). None for a
    /// line someone added.
    pub rule: Option<String>,
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
    /// What they owe is within the cap (the server's `within_cap`).
    pub within_cap: Option<bool>,
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
    /// The day a bonus or deduction counts on (`YYYY-MM-DD`), so two lines
    /// with the same reason ("Late by 55 minutes") can be told apart (AD-6).
    pub date: Option<String>,
    /// Why it was waived, or its amount overridden (AD-6, minor #29).
    pub note: Option<String>,
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
    /// On payroll with no salary set (decision #9): its Salary line reads
    /// "—", and approval waits until it is set.
    pub salary_missing: bool,
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
        /// A half day's half: `first` (default) or `second` (RQ-8).
        #[serde(default)] leave_half: Option<String>,
        /// A leave approved as it is filed (a self-approver's): paid or unpaid,
        /// required by the server (RQ-2, `LEAVE_PAY_REQUIRED`).
        #[serde(default)] paid: Option<bool>,
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
    /// Undoing an approved request says why (AT-7).
    Cancel { req: String, #[serde(default)] note: Option<String> },
    Decide {
        req: String,
        approve: bool,
        #[serde(default)] paid: Option<bool>,
        #[serde(default)] amount: Option<i64>,
        #[serde(default)] installments: Option<i64>,
        #[serde(default)] note: Option<String>,
    },
    /// `excuse_paid` · `excuse_unpaid` · `deduct` · `revoke` · `confirm` · `ignore`
    Resolve { flag: String, how: String, #[serde(default)] deduct: i64, #[serde(default)] reason: Option<String> },
    AddAdjustment {
        emp: String,
        bonus: bool,
        #[serde(default)] amount: i64,
        reason: String,
        #[serde(default)] pct: Option<f64>,
        #[serde(default)] recurring: bool,
    },
    /// Declining says why (AD-9, decision #8): the server refuses a
    /// rejection without a reason.
    DecideAdj { adj: String, yes: bool, #[serde(default)] reason: Option<String> },
    DeleteAdj { adj: String },
    /// [reason]: why it stops (AD-9); the server refuses a stop without one.
    StopAdj {
        adj: String,
        #[serde(default)]
        reason: String,
    },
    Waive { key: String, reason: String },
    /// Undo a waiver, with a reason (AT-7): the rule's figure comes back.
    Unwaive { key: String, reason: String },
    RecordAdvance { emp: String, amount: i64, installments: i64 },
    LogExpense { emp: String, amount: i64, purpose: String, via: String },
    /// The whole date is exactly this block, or a day off (`tpl` None).
    SetDay { emp: String, date: String, tpl: Option<String> },
    /// Every block a person works on a date (a split day); empty = a day off.
    SetShifts { emp: String, date: String, blocks: Vec<BlockA> },
    /// One more block on the date; the rest of the day stays.
    AddBlock { emp: String, date: String, tpl: String },
    /// Take this one shift off its date; the rest of the day stays.
    RemoveBlock { shift: String },
    /// Back to the standing pattern.
    ResetDay { emp: String, date: String },
    /// This one assignment's own from/to (minutes of the day; both None =
    /// back to the block's). An end at or before the start is the next day.
    SetTimes { shift: String, #[serde(default)] start: Option<i64>, #[serde(default)] end: Option<i64> },
    /// Give this shift to a colleague; both keep the rest of their day.
    GiveShift { shift: String, to: String },
    /// Take an open shift back (open or claimed).
    CancelOpen { shift: String },
    /// Ask a colleague to swap: `mine` is MY shift, `theirs` the colleague's (06 B2).
    AskSwap { mine: String, theirs: String },
    MoveShift { shift: String, day: String, tpl: String },
    Assign { shift: String, emp: Option<String> },
    PostOpen { branch: String, date: String, tpl: String },
    Claim { shift: String },
    Publish { branch: String, week: String },
    AcceptSuggestion { id: String },
    RejectSuggestion { id: String },
    DecideHoliday { date: String, decision: String },
    /// My preferences, or (`emp` someone else) a manager's override, logged (SC-12).
    SetPrefs {
        time: Option<String>,
        cant: Vec<i64>,
        #[serde(default)] emp: Option<String>,
        #[serde(default)] note: Option<String>,
    },
    /// The weekly coverage grid for a branch (SC-13): `[{day_of_week, band_start, band_end, staff}]`.
    SetCoverage { branch: String, needs: Value },
    ReadAll,
    /// Signing out: the server forgets this phone and its pushes (APP-6).
    SignOut,
    /// This phone accepts the location notice (AT-5), on the server.
    AcceptPrivacy,
    /// A reading the host just took (Home opening, a resume): kept with its
    /// time so the fence line is real (06 B4). Local only, never sent.
    NoteFix { fix: DawamFix },
    ApprovePayroll,
    /// Back to a live preview, with the reason the audit log keeps (AD-9).
    ReopenPayroll { #[serde(default)] reason: String },
    MarkPaid { emp: String, method: String },
}

impl Act {
    /// Works offline: queued and sent later (APP-8).
    fn queueable(&self) -> bool {
        matches!(self, Act::ClockIn { .. } | Act::ClockOut { .. } | Act::Cover { .. } | Act::PunchFor { .. })
    }
}

/// One block of a date, with this assignment's own times if it has any.
#[derive(Deserialize, Debug, Clone)]
pub struct BlockA {
    pub tpl: String,
    #[serde(default)]
    pub start: Option<i64>,
    #[serde(default)]
    pub end: Option<i64>,
}

/// The server's refusals of a punch (E2E B1: they came as English with an
/// HTTP prefix). They keep the server's body, so the core words them with
/// the server's `vars` as `staff.err_<code in lower case>`.
pub(crate) const PUNCH_CODES: &[&str] = &[
    "OUTSIDE_FENCE",
    "CHECKIN_TOO_EARLY",
    "SHIFT_ENDED",
    "LOCATION_REQUIRED",
    "BRANCH_NO_LOCATION",
    "EMPLOYMENT_NOT_ACTIVE",
    "NOT_AN_EMPLOYEE",
    "BRANCH_OTHER_ORG",
    "NOT_YOUR_BRANCH",
    "ALREADY_CHECKED_IN",
    // The till's PIN punch with POS or Dawam switched off (P-010).
    "MODULE_OFF",
    // A colleague is covering this shift (owner decision #1): every way of
    // punching its owner in is refused, with the coverer's name.
    "SHIFT_COVERED",
];

/// The server's money refusals (E2E money BB2): the body is kept, and the
/// core words them as `staff.err_<code in lower case>` with the server's
/// figures, a `*_piastres` figure shown as money in the phone's language.
pub(crate) const MONEY_CODES: &[&str] = &[
    "ADVANCE_OVER_CAP",
    // Approving payroll while someone on it has no salary (decision #9),
    // with their `names`.
    "SALARY_MISSING",
];

/// A money refusal in `locale`, from the server's body (`{error, code,
/// vars}`); the server's own `error` when the body can't be read or the
/// core has no words for it.
pub(crate) fn money_words(locale: &str, code: &str, body: &str) -> String {
    let ar = i18n::is_arabic(locale);
    let v: Value = serde_json::from_str(body).unwrap_or(Value::Null);
    let args: BTreeMap<String, String> = v.get("vars").and_then(Value::as_object).into_iter().flatten()
        .map(|(k, x)| {
            let text = match x {
                Value::Number(n) if k.ends_with("_piastres") => n.as_i64().map_or_else(|| n.to_string(), |p| egp(p, ar)),
                Value::Number(n) => n.to_string(),
                Value::String(t) => t.clone(),
                // A list of names, as a sentence lists them.
                Value::Array(a) => a.iter().map(|x| x.as_str().map_or_else(|| x.to_string(), str::to_string)).collect::<Vec<_>>().join(if ar { "، " } else { ", " }),
                other => other.to_string(),
            };
            (k.clone(), text)
        })
        .collect();
    let server = || v.get("error").and_then(Value::as_str).map_or_else(|| body.to_string(), str::to_string);
    let key = format!("staff.err_{}", code.to_lowercase());
    let words = i18n::tr(locale, &key);
    let out = fill(&words, &args);
    if words != key && !out.contains('{') {
        return out;
    }
    // Sent without its figures (the cap to a manager, decision #7): the
    // same refusal with no amounts, when the core has words for that.
    let bare = format!("{key}_no_figures");
    let words = i18n::tr(locale, &bare);
    if v.is_object() && words != bare && !words.contains('{') { words } else { server() }
}

/// A punch refusal in `locale`, from the server's body (`{error, code,
/// vars}`): the core's words with the server's figures, an instant shown at
/// the branch's time; the server's own `error` when the body can't be read.
pub(crate) fn punch_words(locale: &str, code: &str, body: &str, tz: chrono_tz::Tz) -> String {
    let v: Value = serde_json::from_str(body).unwrap_or(Value::Null);
    let args: BTreeMap<String, String> = v.get("vars").and_then(Value::as_object).into_iter().flatten()
        .map(|(k, x)| {
            let text = match x {
                Value::Number(n) => n.as_f64().map_or_else(|| n.to_string(), |f| format!("{}", f.round() as i64)),
                Value::String(t) => crate::timefmt::hhmm_in(tz, t, locale).unwrap_or_else(|| t.clone()),
                other => other.to_string(),
            };
            (k.clone(), text)
        })
        .collect();
    let server = || v.get("error").and_then(Value::as_str).map_or_else(|| body.to_string(), str::to_string);
    let key = format!("staff.err_{}", code.to_lowercase());
    let words = i18n::tr(locale, &key);
    let out = fill(&words, &args);
    // No words for it, or a figure the server didn't send: its own sentence.
    if words == key || out.contains('{') { server() } else { out }
}

/// The server's roster refusals (audit 02): worded in the phone's language
/// as `staff.err_<code in lower case>`.
pub(crate) const ROSTER_CODES: &[&str] = &[
    "SHIFT_NOT_ON_DAY",
    "SHIFT_OTHER_BRANCH",
    "SHIFT_INACTIVE",
    "SHIFT_EMPTY",
    "SHIFTS_OVERLAP",
    "SHIFT_DAYS_IN_USE",
    "NOT_ROSTERED",
    "SWAP_STALE",
    "SWAP_STARTED",
    "SWAP_OTHER_BRANCH",
    "WEEK_NOT_PUBLISHED",
    "ALREADY_ROSTERED",
    "ALREADY_CLAIMED",
    "SWAP_EXISTS",
    "SUGGESTION_STALE",
];

/// Giving a shift to someone already on it names them (E2E roster m2): the
/// manager is not the one "already on that shift".
fn already_rostered_names(e: CoreError, snap: &Snapshot, to: &str, locale: &str) -> CoreError {
    match e {
        CoreError::Server { status, code, .. } if code == "ALREADY_ROSTERED" => {
            let name = snap.people.iter().find(|p| p.id == to).map_or_else(String::new, |p| p.name.clone());
            let detail = if name.is_empty() {
                i18n::tr(locale, "staff.err_already_rostered")
            } else {
                i18n::tr(locale, "staff.err_already_rostered_name").replace("{name}", &name)
            };
            CoreError::Server { status, code, detail }
        }
        e => e,
    }
}

/// The server's plain refusals carry its error kind in front ("Conflict:
/// Someone already claimed that shift."): the person reads the sentence only
/// (E2E roster: the toast said "Conflict: …").
fn plain_sentence(detail: &str) -> String {
    ["Conflict: ", "Bad request: ", "Not found: ", "Forbidden: "]
        .iter()
        .find_map(|p| detail.strip_prefix(p))
        .unwrap_or(detail)
        .to_string()
}

/// `minute of the day` → the server's `HH:MM:SS`.
fn hms_of(m: i64) -> String {
    format!("{}:00", hhmm(m.rem_euclid(1440)))
}

/// A date's set as the server takes it: each block, with its own times only
/// when the assignment has them.
fn blocks_json(blocks: &[BlockA]) -> Value {
    Value::Array(
        blocks
            .iter()
            .map(|b| match (b.start, b.end) {
                (Some(a), Some(z)) => json!({ "work_shift_id": b.tpl, "start_time": hms_of(a), "end_time": hms_of(z) }),
                _ => json!({ "work_shift_id": b.tpl }),
            })
            .collect(),
    )
}

/// One person's rostered blocks on a date, as the snapshot has them (their
/// own times kept), in start order.
fn day_set(snap: &Snapshot, emp: &str, d: &str) -> Vec<BlockA> {
    let mut v: Vec<&ShiftV> = snap.shifts.iter().filter(|x| x.rostered && x.emp.as_deref() == Some(emp) && x.date == d).collect();
    v.sort_by_key(|x| x.start);
    v.into_iter()
        .map(|x| BlockA { tpl: x.tpl.clone(), start: x.edited.then_some(x.start), end: x.edited.then_some(x.end) })
        .collect()
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
/// Server weekday (0 = Sunday … 6 = Saturday) → ISO (Mon = 1 … Sun = 7).
fn iso_day(d: i64) -> i64 {
    if d.rem_euclid(7) == 0 { 7 } else { d.rem_euclid(7) }
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
/// A 409 on a queued op means "the server already holds this" only when
/// an earlier try may have landed (a resend after a lost answer: a
/// counted retry) or when what it asked for is already so — a check-out
/// or a ping with nothing open. A first try refused with 409 (rules not
/// saved, a closed month, a shift that can't be covered, clock out
/// first) is a refusal (E2E clocking C2).
///
/// A coded refusal is always a refusal (owner decision BC-3: a check-out
/// dated in a closed month is answered 409 PERIOD_CLOSED and must not read
/// "clocked out"), except "already checked in", which a resend meets when
/// its first try landed. A ping refused for any reason is dropped quietly:
/// the next one follows.
pub(crate) fn conflict_means_held(item: &store::OutboxItem, code: &str) -> bool {
    if item.op_type == "dawam_ping" {
        return true;
    }
    let refused = crate::net::DAWAM_CODES.contains(&code)
        || ROSTER_CODES.contains(&code)
        || (PUNCH_CODES.contains(&code) && code != "ALREADY_CHECKED_IN");
    if refused {
        return false;
    }
    item.attempts > 0 || item.op_type == "dawam_check_out"
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
            // A dashboard-written day and a manager's punch both read "by
            // your manager" on the phone (CL-16 keeps them apart server-side).
            "manual" | "manager" => "manager",
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
                // The server's signed time when it sent one (CL-11); an older
                // server only has its `Date`, which dates but doesn't vouch.
                let a = match self.api.staff_anchor() {
                    Some(sa) if sa.server_ms().is_some() => Anchor {
                        server_ms: sa.server_ms().unwrap_or_default(),
                        boot_ms: sa.boot_ms,
                        wall_ms: sa.wall_ms,
                        sig: Some(sa.signed),
                    },
                    _ => Anchor { server_ms: self.corrected_now_ms(), boot_ms: boot_ms(), wall_ms: wall_ms(), sig: None },
                };
                if let Ok(j) = serde_json::to_string(&a) {
                    let _ = self.store.kv_put(K_ANCHOR, &j);
                }
                Ok(if text.trim().is_empty() { Value::Null } else { serde_json::from_str(&text).unwrap_or(Value::Null) })
            }
            Err(e) => {
                if matches!(e, CoreError::Offline { .. }) {
                    self.note_connectivity(false);
                }
                Err(match e {
                    // A roster refusal, in the phone's language.
                    CoreError::Server { status, code, .. } if ROSTER_CODES.contains(&code.as_str()) => {
                        let detail = i18n::tr(&self.current_locale(), &format!("staff.err_{}", code.to_lowercase()));
                        CoreError::Server { status, code, detail }
                    }
                    // A money refusal (the advance cap), in the phone's language
                    // with the server's figure as money.
                    CoreError::Server { status, code, detail } if MONEY_CODES.contains(&code.as_str()) => {
                        let detail = money_words(&self.current_locale(), &code, &detail);
                        CoreError::Server { status, code, detail }
                    }
                    // A punch refusal, in the phone's language with the server's figures.
                    CoreError::Server { status, code, detail } if PUNCH_CODES.contains(&code.as_str()) => {
                        let detail = punch_words(&self.current_locale(), &code, &detail, self.dawam_tz());
                        CoreError::Server { status, code, detail }
                    }
                    CoreError::Server { status, code, detail } => CoreError::Server { status, code, detail: plain_sentence(&detail) },
                    e => e,
                })
            }
        }
    }

    /// The last server time this phone saw: the newest signed one any staff
    /// call brought back (a refresh too), else the one kept from before.
    fn dawam_anchor(&self) -> Option<Anchor> {
        let kept: Option<Anchor> = self.store.kv_get(K_ANCHOR).ok().flatten().and_then(|j| serde_json::from_str(&j).ok());
        let live = self.api.staff_anchor().and_then(|sa| {
            Some(Anchor { server_ms: sa.server_ms()?, boot_ms: sa.boot_ms, wall_ms: sa.wall_ms, sig: Some(sa.signed) })
        });
        match (kept, live) {
            (Some(k), Some(l)) if k.wall_ms >= l.wall_ms => Some(k),
            (_, Some(l)) => {
                if let Ok(j) = serde_json::to_string(&l) {
                    let _ = self.store.kv_put(K_ANCHOR, &j);
                }
                Some(l)
            }
            (k, None) => k,
        }
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
                // Who is in, late or absent: the server's call (AT-3).
                "/staff/team/presence".into(),
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
            // A server that failed or throttled this read (5xx, 429) said
            // nothing about what there is to show: keep the old mirror whole
            // rather than write that view empty ("No shift today", E2E S-301).
            Err(e @ CoreError::Transient { .. }) => Some(Err(e)),
            Err(CoreError::Server { status: 429, detail, .. }) => Some(Err(CoreError::Transient { detail })),
            // A view the server refuses this person is simply left empty.
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
        let mut date_sets: Vec<Value> = Vec::new();
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
                date_sets.extend(arr(&v, "date_sets").iter().cloned());
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
            ("date_sets", json!(date_sets)),
            ("presence", g("/staff/team/presence")),
        ];
        self.store.with_tx(|tx| write_mirror(tx, &m))?;
        Ok(())
    }

    /// Today in the branch's time zone (AT-1), from the server's clock.
    fn dawam_today(&self) -> NaiveDate {
        let tz = self.dawam_tz();
        Utc.timestamp_millis_opt(self.corrected_now_ms()).single().unwrap_or_else(Utc::now).with_timezone(&tz).date_naive()
    }

    /// The zone of the branch I work at (AT-1, audit 03 bug 12): my own
    /// first branch, not whichever branch the mirror happens to list first
    /// (an owner or a manager sees every branch). No branch of mine known
    /// yet: the first one, then Cairo.
    fn dawam_tz(&self) -> chrono_tz::Tz {
        let me = self.dawam_me().unwrap_or_default();
        let (branches, people) = self
            .store
            .with_conn(|c| Ok((read_table(c, "dawam_branches")?, read_table(c, "dawam_people")?)))
            .unwrap_or_default();
        let mine: Vec<String> = people
            .iter()
            .find(|p| s(p, "employee_id") == me)
            .map(|p| arr(p, "branch_ids").iter().filter_map(Value::as_str).map(str::to_string).collect())
            .unwrap_or_default();
        let zone_of = |b: &Value| so(b, "timezone").and_then(|t| t.parse::<chrono_tz::Tz>().ok());
        mine.iter()
            .find_map(|id| branches.iter().find(|b| s(b, "id") == *id).and_then(zone_of))
            .or_else(|| branches.first().and_then(zone_of))
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
        self.dawam_note_fix(&fix);
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

    /// Keep a reading with the moment it was taken (06 B4).
    fn dawam_note_fix(&self, fix: &DawamFix) {
        let noted = NotedFix { fix: fix.clone(), noted_boot_ms: Some(boot_ms()) };
        let _ = self.store.kv_put(K_FIX, &serde_json::to_string(&noted).unwrap_or_default());
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
        if let Act::NoteFix { fix } = &act {
            self.dawam_note_fix(fix);
            return self.dawam_snapshot(false).await;
        }
        if matches!(act, Act::AcceptPrivacy) {
            if !online {
                return Err(needs_connection(&self.current_locale()));
            }
            self.dawam_srv("POST", "/staff/me/privacy", Some(json!({}))).await?;
            // Anything that waited for the notice goes now.
            let _ = self.store.clear_network_backoff();
            let _ = self.drain_outbox().await;
            return self.dawam_snapshot(true).await;
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
        let filed = self.dawam_online(act).await?;
        let snap = self.dawam_snapshot(true).await?;
        // What the server made of a request just filed (RQ-5): approved at
        // once for a filer who approves their own, else waiting — the screen
        // words its answer from this, never from the filer's role.
        Ok(match filed {
            Some(f) => {
                let mut v: Value = serde_json::from_str(&snap).map_err(|e| CoreError::Internal { detail: format!("snapshot: {e}") })?;
                v["filed"] = f;
                v.to_string()
            }
            None => snap,
        })
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
        // The punch's own reading, spoof signals included (CL-8/9): a shift
        // with tracking off has no pings, so the punch is all there is.
        let fix_body = |fix: &Option<DawamFix>| {
            json!({
                "latitude": fix.as_ref().map(|f| f.latitude),
                "longitude": fix.as_ref().map(|f| f.longitude),
                "accuracy_meters": fix.as_ref().and_then(|f| f.accuracy),
                "is_mock": fix.as_ref().map(|f| f.mock),
            })
        };
        let noted = |fix: &Option<DawamFix>| {
            if let Some(f) = fix {
                self.dawam_note_fix(f);
            }
        };
        let gps = |fix: &Option<DawamFix>| fix.as_ref().and_then(|f| f.gps_time.clone());
        match act {
            Act::ClockIn { shift, fix, tracking_off } => {
                if snap.active_shift.is_some() {
                    return Err(CoreError::Validation { field: String::new(), detail: i18n::tr(&self.current_locale(), "staff.clock_out_first") });
                }
                noted(&fix);
                let mut body = fix_body(&fix);
                body["branch_id"] = json!(branch_of(&shift));
                body["tracking_off"] = json!(tracking_off);
                body["shift"] = json!(shift);
                self.dawam_enqueue("dawam_check_in", "/staff/me/check-in", body, gps(&fix).as_deref())
            }
            Act::ClockOut { fix } => {
                noted(&fix);
                self.dawam_enqueue("dawam_check_out", "/staff/me/check-out", fix_body(&fix), gps(&fix).as_deref())
            }
            Act::Cover { shift, fix } => {
                noted(&fix);
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

    /// The online-only actions: one or two server calls each. Filing returns
    /// the server's answer: `{ id, status, to_owner }`.
    async fn dawam_online(&self, act: Act) -> Result<Option<Value>, CoreError> {
        let snap = self.dawam_build()?;
        let locale = self.current_locale();
        let invalid = |key: &str| CoreError::Validation { field: String::new(), detail: i18n::tr(&locale, key) };
        let mut filed: Option<Value> = None;
        let period_id = snap.period.id.clone().unwrap_or_default();
        match act {
            Act::File { kind, from, to, half, leave_half, paid, time, time2, note, amount, installments, shift, shift2, peer } => {
                let d = from.unwrap_or_else(|| self.dawam_today().to_string());
                match kind.as_str() {
                    "salaryAdvance" => {
                        let row = self.dawam_srv("POST", "/staff/me/advances", Some(json!({
                            "amount_piastres": amount, "installments": installments.unwrap_or(1),
                            "reason": Some(note).filter(|n| !n.is_empty()),
                        }))).await?;
                        let mut f = filed_of("v", &row);
                        // Over the cap only the owner can approve it (minor #34):
                        // the server's `within_cap` on the new advance.
                        if row.get("within_cap").and_then(Value::as_bool) == Some(false) {
                            f["to_owner"] = json!(true);
                        }
                        filed = Some(f);
                    }
                    // `shift` is MINE, `shift2` the colleague's.
                    "swap" => {
                        let _ = peer;
                        self.dawam_ask_swap(&snap, shift.as_deref().unwrap_or_default(), shift2.as_deref().unwrap_or_default()).await?;
                    }
                    "openShift" => {
                        self.dawam_srv("POST", &format!("/staff/open-shifts/{}/claim", tail(shift.as_deref().unwrap_or_default())), Some(json!({}))).await?;
                    }
                    k => {
                        let server = kind_to_server(k).ok_or_else(|| CoreError::Validation { field: "kind".into(), detail: k.into() })?;
                        let note = note.trim().to_string();
                        match server {
                            // The server titles a mission with its note (§3): say so here.
                            "mission" if !note.chars().any(char::is_alphanumeric) => return Err(invalid("staff.a_mission_needs_a_note")),
                            // Ending earlier on the clock runs past midnight (B5); only an
                            // empty window is refused.
                            "excuse" if time.is_some() && time == time2 => return Err(invalid("staff.the_window_can_t_be_empty")),
                            "correction" if time.is_none() && time2.is_none() => return Err(invalid("staff.change_a_time_first")),
                            _ => {}
                        }
                        // Only a correction names a record: the person's OWN record of
                        // that shift (RQ-9); the server refuses anyone else's.
                        let record = (server == "correction")
                            .then(|| shift.as_deref().and_then(|sid| snap.shifts.iter().find(|x| x.id == sid)).and_then(|_| self.dawam_record_of(shift.as_deref()?)))
                            .flatten();
                        let mut body = json!({ "kind": server, "on_date": d, "is_half_day": half });
                        if let Some(t) = to { body["end_date"] = json!(t); }
                        if let (true, Some(p)) = (server == "leave", paid) {
                            body["is_paid"] = json!(p);
                        }
                        if server == "leave" && half {
                            body["leave_half"] = json!(match leave_half.as_deref() {
                                Some("second") => "second",
                                _ => "first",
                            });
                        }
                        // The shift a timed request is for (B4): on a split day it
                        // never reaches the other shift. A correction names it only
                        // when no record holds that shift yet (RQ-9: nobody clocked).
                        if matches!(server, "late_arrival" | "early_departure" | "excuse") || (server == "correction" && record.is_none()) {
                            if let Some(sid) = shift.as_deref().filter(|x| !x.starts_with("open|")) {
                                let (_, _, tpl) = parts(sid);
                                if !tpl.is_empty() {
                                    body["work_shift_id"] = json!(tpl);
                                }
                            }
                        }
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
                        let row = self.dawam_srv("POST", "/staff/me/requests", Some(body)).await?;
                        filed = Some(filed_of("q", &row));
                    }
                }
            }
            Act::PeerAnswer { req, yes } => {
                self.dawam_srv("PATCH", &format!("/staff/me/swaps/{}", tail(&req)), Some(json!({ "approve": yes }))).await?;
            }
            // The one who asked takes a swap back before the manager decides.
            Act::Cancel { req, .. } if req.starts_with("w|") => {
                self.dawam_srv("POST", &format!("/staff/me/swaps/{}/cancel", tail(&req)), Some(json!({}))).await?;
            }
            Act::Cancel { req, note } => {
                if !req.starts_with("q|") {
                    return Err(CoreError::Validation { field: String::new(), detail: i18n::tr(&locale, "staff.ask_manager_to_cancel") });
                }
                let note = note.map(|n| n.trim().to_string()).filter(|n| !n.is_empty());
                // AT-7: undoing an approved request says why.
                let approved = snap.requests.iter().any(|r| r.id == req && r.status == "approved");
                if approved && note.is_none() {
                    return Err(invalid("staff.say_why_you_cancel"));
                }
                let mut body = json!({ "status": "cancelled" });
                if let Some(n) = note {
                    body["note"] = json!(n);
                }
                self.dawam_srv("PATCH", &format!("/staff/requests/{}/decision", tail(&req)), Some(body)).await?;
            }
            Act::Decide { req, approve, paid, amount, installments, note } => {
                let id = tail(&req);
                // Declining an advance says why (decision #8).
                let note = note.map(|n| n.trim().to_string()).filter(|n| !n.is_empty());
                if !approve && req.starts_with("v|") && note.is_none() {
                    return Err(invalid("staff.say_why_you_decline"));
                }
                // Pay is asked only of leave, an excuse and an early departure
                // (RQ-7); any other kind's decision carries none.
                let kind = snap.requests.iter().find(|r| r.id == req).map(|r| r.kind.clone()).unwrap_or_default();
                let paid = paid.filter(|_| approve && matches!(kind.as_str(), "leave" | "excuse" | "earlyDeparture"));
                let (path, body) = match req.split('|').next().unwrap_or_default() {
                    "q" => {
                        let mut body = json!({ "status": if approve { "approved" } else { "rejected" }, "note": note });
                        if let Some(p) = paid {
                            body["is_paid"] = json!(p);
                        }
                        (format!("/staff/requests/{id}/decision"), body)
                    }
                    "v" => (
                        format!("/staff/advances/{id}/review"),
                        json!({ "approve": approve, "amount_piastres": amount, "installments": installments, "reason": note, "note": note }),
                    ),
                    "w" => (format!("/staff/swaps/{id}/decision"), json!({ "approve": approve })),
                    "o" => (format!("/staff/open-shifts/{id}/decision"), json!({ "approve": approve })),
                    "c" => (format!("/staff/attendance/{id}/cover"), json!({ "approve": approve })),
                    "t" => (format!("/staff/attendance/{id}/overtime"), json!({ "approve": approve })),
                    other => return Err(CoreError::Validation { field: "req".into(), detail: other.into() }),
                };
                let answer = self.dawam_srv("PATCH", &path, Some(body)).await?;
                // An approved claim's day against the labour limits (RU-13,
                // minor #26): a warning for the approver, never a block.
                let broken: Vec<(String, Value)> = labour_warnings(arr(&answer, "warnings")).into_values().flatten().collect();
                if req.starts_with("o|") && !broken.is_empty() {
                    filed = Some(json!({ "id": req, "status": "approved", "to_owner": false, "warnings": broken }));
                }
            }
            Act::Resolve { flag, how, deduct, reason } => {
                let mut body = json!({ "action": how });
                if deduct > 0 { body["amount_piastres"] = json!(deduct); }
                if let Some(r) = reason.filter(|r| !r.trim().is_empty()) { body["reason"] = json!(r.trim()); }
                self.dawam_srv("PATCH", &format!("/staff/flags/{flag}"), Some(body)).await?;
                // Over my deduction limit the line waits for the owner (AD-5,
                // minor #33): the server's limit, "above it, it waits".
                let charges = matches!(how.as_str(), "deduct" | "excuse_unpaid");
                if charges && snap.settings.deduction_limit.is_some_and(|limit| deduct > limit) {
                    filed = Some(json!({ "id": format!("f|{flag}"), "status": "pending", "to_owner": true }));
                }
            }
            Act::AddAdjustment { emp, bonus, amount, reason, pct, recurring } => {
                let mut body = json!({ "employee_id": emp, "kind": if bonus { "bonus" } else { "deduction" }, "reason": reason, "recurring": recurring });
                match pct {
                    Some(p) => body["percent_of_base"] = json!(p),
                    None => body["amount_piastres"] = json!(amount),
                }
                let row = self.dawam_srv("POST", "/staff/adjustments", Some(body)).await?;
                // What the server made of it (AD-5): over the adder's limit it
                // waits for the owner, and the screen must say so, not "Added".
                filed = Some(filed_of(if bonus { "a|bonus" } else { "a|deduction" }, &row));
            }
            Act::DecideAdj { adj, yes, reason } => {
                let (_, kind, id) = parts(&adj);
                let mut body = json!({ "approve": yes });
                if !yes {
                    let why = reason.map(|r| r.trim().to_string()).filter(|r| !r.is_empty()).ok_or_else(|| invalid("staff.say_why_you_decline"))?;
                    body["reason"] = json!(why);
                }
                self.dawam_srv("PATCH", &format!("/staff/adjustments/{kind}/{id}/decision"), Some(body)).await?;
            }
            Act::DeleteAdj { adj } => {
                let (_, kind, id) = parts(&adj);
                let table = if kind == "bonus" { "bonuses" } else { "deductions" };
                self.dawam_srv("DELETE", &format!("/staff/payroll/{table}/{id}"), None).await?;
            }
            Act::StopAdj { adj, reason } => {
                let (_, kind, id) = parts(&adj);
                self.dawam_srv("POST", &format!("/staff/adjustments/{kind}/{id}/stop"), Some(json!({ "reason": reason }))).await?;
            }
            Act::Waive { key, reason } => {
                if let Some(id) = key.strip_prefix("d|") {
                    self.dawam_srv("PATCH", &format!("/staff/payroll/deductions/{id}/waive"), Some(json!({ "reason": reason }))).await?;
                }
            }
            Act::Unwaive { key, reason } => {
                if let Some(id) = key.strip_prefix("d|") {
                    self.dawam_srv("PATCH", &format!("/staff/payroll/deductions/{id}/unwaive"), Some(json!({ "reason": reason }))).await?;
                }
            }
            Act::RecordAdvance { emp, amount, installments } => {
                // One atomic call (AV-2): recorded and approved, or nothing.
                self.dawam_srv("POST", "/staff/advances/record", Some(json!({ "employee_id": emp, "amount_piastres": amount, "installments": installments }))).await?;
            }
            Act::LogExpense { emp, amount, purpose, via } => {
                self.dawam_srv("POST", "/staff/expense-advances", Some(json!({ "employee_id": emp, "amount_piastres": amount, "purpose": purpose, "via": via }))).await?;
            }
            Act::SetDay { emp, date: d, tpl } => {
                let blocks: Vec<BlockA> = tpl.into_iter().map(|tpl| BlockA { tpl, start: None, end: None }).collect();
                self.dawam_put_day(&emp, &d, &blocks).await?;
            }
            Act::SetShifts { emp, date: d, blocks } => self.dawam_put_day(&emp, &d, &blocks).await?,
            Act::AddBlock { emp, date: d, tpl } => {
                let mut blocks = day_set(&snap, &emp, &d);
                if !blocks.iter().any(|b| b.tpl == tpl) {
                    blocks.push(BlockA { tpl, start: None, end: None });
                }
                self.dawam_put_day(&emp, &d, &blocks).await?;
            }
            Act::RemoveBlock { shift } => {
                let (emp, d, tpl) = parts(&shift);
                let blocks: Vec<BlockA> = day_set(&snap, emp, d).into_iter().filter(|b| b.tpl != tpl).collect();
                self.dawam_put_day(emp, d, &blocks).await?;
            }
            Act::ResetDay { emp, date: d } => {
                self.dawam_srv("DELETE", &format!("/staff/schedules/days?employee_id={emp}&on_date={d}"), None).await?;
            }
            Act::SetTimes { shift, start, end } => {
                let (emp, d, tpl) = parts(&shift);
                let (start, end) = match (start, end) {
                    (Some(a), Some(z)) => (Some(hms_of(a)), Some(hms_of(z))),
                    _ => (None, None),
                };
                self.dawam_srv("PUT", "/staff/schedules/days/times", Some(json!({
                    "employee_id": emp, "on_date": d, "work_shift_id": tpl, "start_time": start, "end_time": end,
                }))).await?;
            }
            Act::GiveShift { shift, to } => {
                let (emp, d, tpl) = parts(&shift);
                self.dawam_srv("POST", "/staff/schedules/days/move", Some(json!({
                    "employee_id": emp, "to_employee_id": to, "on_date": d, "work_shift_id": tpl,
                })))
                .await
                .map_err(|e| already_rostered_names(e, &snap, &to, &locale))?;
            }
            Act::CancelOpen { shift } => {
                self.dawam_srv("POST", &format!("/staff/open-shifts/{}/cancel", tail(&shift)), Some(json!({}))).await?;
            }
            Act::AskSwap { mine, theirs } => self.dawam_ask_swap(&snap, &mine, &theirs).await?,
            // Dragged to another day or block: only that block moves; the rest
            // of both days stays (SC-11).
            Act::MoveShift { shift, day: to_day, tpl } => {
                let (emp, from_day, from_tpl) = parts(&shift);
                if emp != "open" {
                    let from: Vec<BlockA> = day_set(&snap, emp, from_day).into_iter().filter(|b| b.tpl != from_tpl).collect();
                    let mut to = if to_day == from_day { from.clone() } else { day_set(&snap, emp, &to_day) };
                    to.retain(|b| b.tpl != tpl);
                    to.push(BlockA { tpl, start: None, end: None });
                    // The day it goes to first (E2E roster): a refusal there — a
                    // block not worked that weekday, an overlap — must leave both
                    // days as they were, not take the shift off its own day.
                    self.dawam_put_day(emp, &to_day, &to).await?;
                    if to_day != from_day {
                        self.dawam_put_day(emp, from_day, &from).await?;
                    }
                }
            }
            Act::Assign { shift, emp } => {
                if let Some(open) = shift.strip_prefix("open|") {
                    // An open shift given to someone: theirs, and no longer open.
                    let Some(e) = emp else { return Ok(None) };
                    let Some(sh) = snap.shifts.iter().find(|x| x.id == shift) else { return Ok(None) };
                    let mut blocks = day_set(&snap, &e, &sh.date);
                    blocks.push(BlockA { tpl: sh.tpl.clone(), start: None, end: None });
                    self.dawam_put_day(&e, &sh.date, &blocks).await?;
                    self.dawam_srv("POST", &format!("/staff/open-shifts/{open}/cancel"), Some(json!({}))).await?;
                    return Ok(None);
                }
                let (owner, d, tpl) = parts(&shift);
                let branch = snap.templates.iter().find(|t| t.id == tpl).map(|t| t.branch.clone()).unwrap_or_default();
                match emp {
                    Some(e) => {
                        self.dawam_srv("POST", "/staff/schedules/days/move", Some(json!({
                            "employee_id": owner, "to_employee_id": e, "on_date": d, "work_shift_id": tpl,
                        })))
                        .await
                        .map_err(|err| already_rostered_names(err, &snap, &e, &locale))?;
                    }
                    None => {
                        let rest: Vec<BlockA> = day_set(&snap, owner, d).into_iter().filter(|b| b.tpl != tpl).collect();
                        self.dawam_put_day(owner, d, &rest).await?;
                        self.dawam_srv("POST", "/staff/open-shifts", Some(json!({ "branch_id": branch, "work_shift_id": tpl, "on_date": d }))).await?;
                    }
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
            Act::SetPrefs { time, cant, emp, note } => {
                let days: Vec<i64> = cant.iter().map(|d| d % 7).collect();
                let body = json!({ "pref_time": time, "cant_work_days": days, "note": note });
                match emp.filter(|e| *e != snap.me) {
                    Some(e) => self.dawam_srv("PUT", &format!("/staff/employees/{e}/preferences"), Some(body)).await?,
                    None => self.dawam_srv("PUT", "/staff/me/preferences", Some(body)).await?,
                };
            }
            Act::ReadAll => {
                self.dawam_srv("POST", "/staff/me/notifications/read", Some(json!({ "ids": [] }))).await?;
            }
            // Without a period id there is nothing to approve or reopen: say so
            // rather than POST to `/periods//generate` (audit 06 B14).
            Act::ApprovePayroll | Act::ReopenPayroll { .. } if period_id.is_empty() => {
                return Err(CoreError::Validation { field: String::new(), detail: i18n::tr(&self.current_locale(), "staff.no_period_yet") });
            }
            Act::ApprovePayroll => {
                self.dawam_srv("POST", &format!("/staff/payroll/periods/{period_id}/generate"), Some(json!({}))).await?;
            }
            Act::ReopenPayroll { reason } => {
                self.dawam_srv("PATCH", &format!("/staff/payroll/periods/{period_id}/status"), Some(json!({ "status": "draft", "reason": reason }))).await?;
            }
            Act::MarkPaid { emp, method } => {
                self.dawam_srv("PATCH", &format!("/staff/payroll/periods/{period_id}/payslips/{emp}/paid"), Some(json!({ "method": method }))).await?;
            }
            Act::ClockIn { .. }
            | Act::ClockOut { .. }
            | Act::Cover { .. }
            | Act::PunchFor { .. }
            | Act::SignOut
            | Act::AcceptPrivacy
            | Act::NoteFix { .. } => {}
        }
        Ok(filed)
    }

    /// PUT the date's whole set (a split day, or a day off when empty).
    async fn dawam_put_day(&self, emp: &str, d: &str, blocks: &[BlockA]) -> Result<(), CoreError> {
        self.dawam_srv("PUT", "/staff/schedules/days", Some(json!({ "employee_id": emp, "on_date": d, "shifts": blocks_json(blocks) })))
            .await
            .map(|_| ())
    }

    /// Ask for a swap: `mine` must be my own shift (06 B2: the app once sent
    /// the two the wrong way round and every swap was refused).
    async fn dawam_ask_swap(&self, snap: &Snapshot, mine: &str, theirs: &str) -> Result<(), CoreError> {
        let (me, my_date, my_tpl) = parts(mine);
        let (peer, peer_date, peer_tpl) = parts(theirs);
        if me != snap.me || peer == snap.me || peer.is_empty() {
            return Err(CoreError::Validation { field: String::new(), detail: i18n::tr(&self.current_locale(), "staff.swap_pick_your_shift") });
        }
        self.dawam_srv("POST", "/staff/me/swaps", Some(json!({
            "my_date": my_date, "my_shift_id": my_tpl,
            "peer_id": peer, "peer_date": peer_date, "peer_shift_id": peer_tpl,
        })))
        .await
        .map(|_| ())
    }

    async fn dawam_suggestion(&self, snap: &Snapshot, id: &str, accept: bool) -> Result<(), CoreError> {
        let branch = snap.suggestions.iter().find(|g| g.id == id).map(|g| g.branch.clone()).unwrap_or_default();
        self.dawam_srv("POST", "/staff/roster/suggestions/decide", Some(json!({ "branch_id": branch, "id": id, "accept": accept }))).await.map(|_| ())
    }

    /// The attendance record behind a shift, for a correction (RQ-9): the
    /// person's OWN record. A colleague's cover of that shift is theirs, and
    /// the server refuses a correction of it (404).
    fn dawam_record_of(&self, shift: &str) -> Option<String> {
        let (user, d, tpl) = parts(shift);
        self.store
            .with_conn(|c| read_table(c, "dawam_attendance"))
            .ok()?
            .into_iter()
            .find(|r| s(r, "employee_id") == user && s(r, "business_date") == d && s(r, "work_shift_id") == tpl)
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
        let (warn_rows, coverage, date_sets, board) = self.store.with_conn(|c| {
            Ok((read_meta(c, "warnings"), read_meta(c, "coverage"), read_meta(c, "date_sets"), read_meta(c, "presence")))
        })?;
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
            self_approves: caps.iter().any(|c| c == "hr.requests.self_approve"),
            tabs: manage_tabs(&caps),
            decides_holidays: decides_holidays(&ctx),
            caps,
            fetched_at,
            privacy_accepted: ctx.get("privacy_accepted_at").is_some_and(|x| !x.is_null()),
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
                // The server counts 0 = Sunday; the app counts ISO (Sun = 7).
                // An older server sends none: every day.
                days: {
                    let mut d: Vec<i64> = arr(w, "valid_days").iter().filter_map(Value::as_i64).map(iso_day).collect();
                    if d.is_empty() {
                        d = (1..=7).collect();
                    }
                    d.sort_unstable();
                    d
                },
                day_times: arr(w, "day_times")
                    .iter()
                    .map(|t| DayTimeV {
                        day: iso_day(i(t, "day_of_week")),
                        start: minute_of(&s(t, "start_time")).unwrap_or(0),
                        end: minute_of(&s(t, "end_time")).unwrap_or(0),
                    })
                    .collect(),
            });
        }
        for p in rows("dawam_people") {
            out.people.push(PersonV {
                id: s(p, "employee_id"),
                name: s(p, "name"),
                phone: s(p, "phone"),
                role: role_of(&s(p, "role")).into(),
                branches: arr(p, "branch_ids").iter().filter_map(Value::as_str).map(str::to_string).collect(),
                salary: p.get("base_salary_piastres").and_then(Value::as_i64),
                salary_set: p.get("salary_set").and_then(Value::as_bool).unwrap_or(true),
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
            deduction_limit: ctx.get("deduction_limit_piastres").and_then(Value::as_i64),
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
            // The server's effective times; an older server sends none.
            let (ds, de) = tp.times_on(d);
            let start = minute_of(&s(r, "start_time")).unwrap_or(ds);
            let end = minute_of(&s(r, "end_time")).unwrap_or(de);
            shifts.push(ShiftV {
                id: sid,
                emp: so(r, "employee_id"),
                tpl: id,
                date: d.to_string(),
                published: is_pub(&tp.branch, d),
                changed: b(r, "changed"),
                start,
                end,
                next_day: r.get("crosses_midnight").and_then(Value::as_bool).unwrap_or(end <= start),
                edited: b(r, "times_edited"),
                own_day: b(r, "from_override"),
                rostered: true,
                leave: b(r, "on_leave").then(|| "paid".to_string()),
                start_at: at(r, "start_at"),
                end_at: at(r, "end_at"),
                ..Default::default()
            });
        }
        for o in rows("dawam_open_shifts") {
            let (Some(d), id) = (date(o, "on_date"), s(o, "work_shift_id")) else { continue };
            let Some(tp) = tpl(&id) else { continue };
            let (start, end) = tp.times_on(d);
            shifts.push(ShiftV { id: format!("open|{}", s(o, "id")), tpl: id, date: d.to_string(), published: is_pub(&tp.branch, d), start, end, next_day: end <= start, start_at: at(o, "start_at"), end_at: at(o, "end_at"), ..Default::default() });
            if s(o, "status") == "claimed" {
                if let Some(by) = so(o, "claimed_by") {
                    out.requests.push(ReqV { id: format!("o|{}", s(o, "id")), kind: "openShift".into(), emp: by, created: now.to_rfc3339(), status: "pending".into(), from: Some(d.to_string()), shift: Some(format!("open|{}", s(o, "id"))), installments: 1, ..Default::default() });
                }
            }
        }
        // A record's shift, by record id (flags and requests name records).
        let mut record_of: HashMap<String, String> = HashMap::new();
        // A person's own records first, so a cover can see the shift it covers
        // whatever order the server listed them in.
        let mut attendance: Vec<&Value> = rows("dawam_attendance").iter().collect();
        attendance.sort_by_key(|r| so(r, "covered_employee_id").is_some());
        for r in attendance {
            let Some(d) = date(r, "business_date") else { continue };
            let wid = s(r, "work_shift_id");
            let Some(tp) = tpl(&wid) else { continue };
            let user = s(r, "employee_id");
            if let Some(owner) = so(r, "covered_employee_id") {
                // A cover is its own row, the coverer's (CV-7): the covered
                // person's shift never takes its punches. While it is pending
                // or confirmed the covered shift reads covered (off its owner's
                // Home, not coverable again); a rejected one leaves it alone.
                let rid = s(r, "id");
                let cid = format!("cover|{rid}");
                let owner_sid = shift_id(&owner, d, &wid);
                let owner_ix = shifts.iter().position(|x| x.id == owner_sid);
                if s(r, "cover_status") != "rejected" {
                    if let Some(ix) = owner_ix {
                        shifts[ix].cover_by = Some(user.clone());
                    }
                }
                // The cover's own window: the record's scheduled instants at
                // the branch's time, else the covered shift's, else the block's.
                let wall = |x: Option<DateTime<Utc>>| {
                    x.map(|t| {
                        let l = t.with_timezone(&tz);
                        i64::from(l.hour() * 60 + l.minute())
                    })
                };
                let (start, end) = match (wall(at(r, "scheduled_start_at")), wall(at(r, "scheduled_end_at"))) {
                    (Some(a), Some(z)) => (a, z),
                    _ => owner_ix.map_or_else(|| tp.times_on(d), |ix| (shifts[ix].start, shifts[ix].end)),
                };
                shifts.push(ShiftV {
                    id: cid.clone(),
                    emp: Some(user.clone()),
                    cover_of: Some(owner.clone()),
                    cover_status: so(r, "cover_status"),
                    tpl: wid.clone(),
                    date: d.to_string(),
                    published: true,
                    start,
                    end,
                    next_day: end <= start,
                    start_at: at(r, "scheduled_start_at").or_else(|| owner_ix.and_then(|ix| shifts[ix].start_at)),
                    end_at: at(r, "scheduled_end_at").or_else(|| owner_ix.and_then(|ix| shifts[ix].end_at)),
                    in_at: at(r, "check_in_at").map(|x| x.to_rfc3339()),
                    out_at: at(r, "check_out_at").map(|x| x.to_rfc3339()),
                    in_method: method_of(&s(r, "check_in_method")),
                    out_method: method_of(&s(r, "check_out_method")),
                    punch_reason: so(r, "punch_reason"),
                    tracking_off: b(r, "tracking_off"),
                    late_minutes: i(r, "late_minutes"),
                    ..Default::default()
                });
                record_of.insert(rid.clone(), cid.clone());
                if s(r, "cover_status") == "pending" {
                    let created = at(r, "check_in_at").map_or_else(|| now.to_rfc3339(), |x| x.to_rfc3339());
                    out.requests.push(ReqV { id: format!("c|{rid}"), kind: "cover".into(), emp: user.clone(), created, status: "pending".into(), from: Some(d.to_string()), shift: Some(cid.clone()), installments: 1, ..Default::default() });
                }
                if s(r, "overtime_status") == "pending" {
                    let created = at(r, "check_out_at").map_or_else(|| now.to_rfc3339(), |x| x.to_rfc3339());
                    out.requests.push(ReqV { id: format!("t|{rid}"), kind: "overtime".into(), emp: user.clone(), created, status: "pending".into(), from: Some(d.to_string()), shift: Some(cid), minutes: i(r, "overtime_minutes"), installments: 1, ..Default::default() });
                }
                continue;
            }
            let owner = user.clone();
            let sid = shift_id(&owner, d, &wid);
            let branch = tp.branch.clone();
            let idx = match shifts.iter().position(|x| x.id == sid) {
                Some(ix) => ix,
                None => {
                    // A worked shift is a fact, published or not.
                    let (start, end) = tp.times_on(d);
                    shifts.push(ShiftV { id: sid.clone(), emp: Some(owner.clone()), tpl: wid.clone(), date: d.to_string(), published: true, start, end, next_day: end <= start, ..Default::default() });
                    let _ = &branch;
                    shifts.len() - 1
                }
            };
            let sh = &mut shifts[idx];
            // The record's scheduled instants, when the roster didn't send any.
            sh.start_at = sh.start_at.or_else(|| at(r, "scheduled_start_at"));
            sh.end_at = sh.end_at.or_else(|| at(r, "scheduled_end_at"));
            sh.in_at = at(r, "check_in_at").map(|x| x.to_rfc3339());
            sh.out_at = at(r, "check_out_at").map(|x| x.to_rfc3339());
            sh.in_method = method_of(&s(r, "check_in_method"));
            sh.out_method = method_of(&s(r, "check_out_method"));
            sh.punch_reason = so(r, "punch_reason");
            sh.tracking_off = b(r, "tracking_off");
            sh.late_minutes = i(r, "late_minutes");
            sh.absent = s(r, "status") == "absent";
            record_of.insert(s(r, "id"), sid.clone());
            if s(r, "overtime_status") == "pending" {
                out.requests.push(ReqV { id: format!("t|{}", s(r, "id")), kind: "overtime".into(), emp: user.clone(), created: sh.out_at.clone().unwrap_or_else(|| now.to_rfc3339()), status: "pending".into(), from: Some(d.to_string()), shift: Some(sid.clone()), minutes: i(r, "overtime_minutes"), installments: 1, ..Default::default() });
            }
        }

        // What is queued shows at once, marked queued (APP-8).
        let active_of = |shifts: &[ShiftV]| {
            shifts.iter().position(|x| x.in_at.is_some() && x.out_at.is_none() && x.emp.as_deref() == Some(&me) && x.cover_by.is_none())
        };
        for q in &queued {
            let p: Value = serde_json::from_str(&q.payload).unwrap_or_default();
            let when = q.event_at.clone();
            let method = if wall_ms() - i(&p, "queued_ms") > LIVE_MS { "offline" } else { "app" };
            match q.op_type.as_str() {
                "dawam_check_in" => {
                    let sid = s(&p["body"], "shift");
                    if let Some(sh) = shifts.iter_mut().find(|x| x.id == sid) {
                        sh.in_at = Some(when);
                        sh.in_method = Some(method.into());
                        sh.queued = true;
                    }
                }
                // A queued cover is my own row at once, like the server's will
                // be; the covered shift reads covered (not offered again).
                "dawam_cover" => {
                    let sid = s(&p["body"], "shift");
                    if let Some(ix) = shifts.iter().position(|x| x.id == sid) {
                        shifts[ix].cover_by = Some(me.clone());
                        let o = shifts[ix].clone();
                        shifts.push(ShiftV {
                            id: format!("cover|{}", q.id),
                            emp: Some(me.clone()),
                            cover_of: o.emp.clone(),
                            cover_by: None,
                            in_at: Some(when),
                            in_method: Some("cover".into()),
                            queued: true,
                            absent: false,
                            out_at: None,
                            out_method: None,
                            late_minutes: 0,
                            ..o
                        });
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
                shift: rec.and_then(|rid| record_of.get(&rid).cloned()),
                to_owner: b(q, "to_owner"),
                paid_default: q.get("paid_default").and_then(Value::as_bool),
                can_decide: q.get("can_decide").and_then(Value::as_bool),
                leave_half: so(q, "leave_half").filter(|_| b(q, "is_half_day")),
                tpl: so(q, "work_shift_id"),
                decided_by: actor(so(q, "decided_by")),
                decision_note: so(q, "decision_note"),
                cancelled_by: actor(so(q, "cancelled_by")),
                cancel_note: so(q, "cancel_note"),
                cancelled_by_name: so(q, "cancelled_by_name"),
                installments: 1,
                ..Default::default()
            };
            if r.status == "approved" {
                let from = r.from.clone().unwrap_or_default();
                // An excuse's `end_date` is the next morning when it runs past
                // midnight (B5): it still belongs to its own day's shift.
                let to = if kind == "excuse" { from.clone() } else { r.to.clone().unwrap_or_else(|| from.clone()) };
                let named = r.tpl.clone();
                for sh in shifts.iter_mut().filter(|x| {
                    x.emp.as_deref() == Some(&user) && x.date >= from && x.date <= to && named.as_ref().is_none_or(|t| *t == x.tpl)
                }) {
                    match kind {
                        "leave" => {
                            sh.leave = Some(if r.paid.unwrap_or(true) { "paid" } else { "unpaid" }.into());
                            sh.half_leave = r.half;
                            sh.leave_half = r.leave_half.clone();
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
                                // Ending earlier on the clock = past midnight (B5).
                                sh.excuse_min = (z - a).rem_euclid(1440);
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
                    within_cap: a.get("within_cap").and_then(Value::as_bool),
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
                within_cap: a.get("within_cap").and_then(Value::as_bool),
            });
        }
        // The cap is the server's figure only (AV-5, AT-3, DW3): no percent
        // maths here — a person the server sends none for (salary hidden
        // from me) has none.
        out.advance_cap.extend(advance_caps(rows("dawam_people")));
        out.advance_within.extend(
            rows("dawam_people").iter().filter_map(|p| Some((s(p, "employee_id"), p.get("advance_within_cap")?.as_bool()?))),
        );
        if let Some(cap) = estimate.get("advance_cap_piastres").and_then(Value::as_i64) {
            out.advance_cap.insert(me.clone(), cap);
        }
        if let Some(o) = estimate.get("advance_outstanding_piastres").and_then(Value::as_i64) {
            out.outstanding.insert(me.clone(), o);
        }
        out.on_payroll = estimate.get("on_payroll").and_then(Value::as_bool).unwrap_or(true);

        // Absent past its end with nothing to excuse it (the sweep's rule,
        // read ahead of the sweep so the day shows at once).
        let holiday_days: HashSet<String> = rows("dawam_holidays").iter().filter(|h| s(h, "decision") == "holiday").map(|h| s(h, "on_date")).collect();
        // Nobody is absent before the business saved its rules (B-ONB-1):
        // not while they are unsaved, nor on a shift that started before the
        // first save. A server that doesn't send the save time: the plain rule.
        let judged = |sh: &ShiftV| -> bool {
            if !out.settings.rules_saved {
                return false;
            }
            match st.get("rules_saved_at") {
                None => true,
                Some(v) => {
                    let saved = v.as_str().and_then(|x| DateTime::parse_from_rfc3339(x).ok()).map(|d| d.with_timezone(&Utc));
                    saved.zip(shift_start(sh, &tz)).is_some_and(|(saved, start)| start >= saved)
                }
            }
        };
        for sh in shifts.iter_mut() {
            if tpl(&sh.tpl).is_none() {
                continue;
            }
            let end = shift_end(sh, &tz);
            if sh.emp.is_some() && sh.published && sh.in_at.is_none() && sh.leave.is_none() && !sh.mission && !holiday_days.contains(&sh.date) && end.is_some_and(|e| e < now) && judged(sh) {
                sh.absent = true;
            }
            if sh.cover_by.is_some() && sh.cover_by.as_deref() != sh.emp.as_deref() {
                sh.absent = sh.leave.is_none();
            }
        }

        // Me, now (SC-10: last night's shift still running counts).
        let today_s = today.to_string();
        for sh in &shifts {
            if tpl(&sh.tpl).is_none() {
                continue;
            }
            // My own shifts not taken by a cover, and the covers I do (their own rows).
            let mine = sh.emp.as_deref() == Some(&me) && sh.cover_by.is_none();
            let running = shift_start(sh, &tz).zip(shift_end(sh, &tz)).is_some_and(|(a, z)| a <= now && z > now);
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
            let shift = rec.and_then(|rid| record_of.get(&rid).cloned());
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
            // Stop means from next month (decision #6): the server ends the
            // line on the open period's last day, so it stays active on the
            // list until that day has passed.
            let ends_on = date(a, "ends_on");
            let status = match s(a, "status").as_str() {
                "pending" => "pendingOwner",
                "rejected" => "rejected",
                _ if ends_on.is_some_and(|e| e < today) => "stopped",
                _ => "active",
            };
            let pct = a.get("percent_of_base").filter(|x| !x.is_null()).map(|_| f(a, "percent_of_base"));
            // The server values a % line (AT-3, DW3); it is never priced here.
            let value = adj_value(a, pct);
            out.adjustments.push(AdjV {
                id: format!("a|{}|{}", s(a, "kind"), s(a, "id")),
                emp: s(a, "employee_id"),
                bonus: s(a, "kind") == "bonus",
                amount: i(a, "amount_piastres"),
                value,
                waived: a.get("waived_at").is_some_and(|x| !x.is_null()),
                pct,
                // A rule line in the phone's language, like the payslip; a
                // typed reason as typed.
                reason: rule_words(a, &locale),
                by: actor(so(a, "created_by")).unwrap_or_default(),
                at: s(a, "created_at"),
                period: s(a, "effective_date"),
                recurring: b(a, "recurring"),
                status: status.into(),
                ends_on: ends_on.map(|d| d.to_string()),
                rule: rule_label(a, &locale),
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
                .filter(|r| r.status == "pending" && r.emp != me && visible.contains(r.emp.as_str()) && r.can_decide.unwrap_or(!r.to_owner || owner))
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
        // The server's count; an older one sends none: the flagged rows.
        out.missing_salary_count = current
            .get("missing_salary_count")
            .and_then(Value::as_i64)
            .unwrap_or_else(|| out.slips.iter().filter(|x| x.salary_missing).count() as i64);
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
        out.presence = presence_of(&board);
        // The dates that hold their own set (a date change), and which of
        // those are a day off: "back to the usual pattern" applies there only.
        for ds in date_sets.as_array().into_iter().flatten() {
            let (Some(d), emp) = (date(ds, "date"), s(ds, "employee_id")) else { continue };
            let key = format!("{emp}|{d}");
            if b(ds, "day_off") {
                out.days_off.push(key.clone());
            }
            out.own_days.push(key);
        }

        // Where I am against each branch's fence, from a FRESH reading only
        // (06 B4): an old one, or none, is "unknown" — never "inside".
        let noted: Option<NotedFix> = self.store.kv_get(K_FIX).ok().flatten().and_then(|j| serde_json::from_str(&j).ok());
        out.charge_phone = out.active_shift.is_some() && noted.as_ref().and_then(|x| x.fix.battery).is_some_and(|b| b <= LOW_BATTERY);
        let fresh = noted.filter(|n| n.fresh_at(boot_ms())).map(|n| n.fix);
        for br in rows("dawam_branches") {
            let radius = effective_radius(br);
            let centre = br.get("latitude").and_then(Value::as_f64).zip(br.get("longitude").and_then(Value::as_f64));
            let fence = match (&fresh, centre) {
                (Some(fx), Some(c)) => {
                    let d = haversine_m(c, (fx.latitude, fx.longitude));
                    let state = if madar_dawam::geofence::inside(d, radius) { "inside" } else { "outside" };
                    FenceV { state: state.into(), distance_m: Some(d.round() as i64), radius }
                }
                _ => FenceV { state: "unknown".into(), distance_m: None, radius },
            };
            out.fences.insert(s(br, "id"), fence);
        }
        let here_branch = out.my_now.first().and_then(|sid| shifts.iter().find(|x| &x.id == sid)).and_then(|x| tpl(&x.tpl)).map(|t| t.branch.clone());
        if let Some(f) = here_branch.and_then(|b| out.fences.get(&b)).filter(|f| f.state != "unknown") {
            out.distance_m = f.distance_m.map(|d| d as f64);
            out.inside = Some(f.state == "inside");
        }

        // Which days can still change (RQ-4, B13): any day outside every
        // approved or paid period, the current one and the earlier ones alike.
        let closed: Vec<(String, String)> = std::iter::once(&out.period)
            .chain(out.history.iter())
            .filter(|p| p.status != "open" && !p.start.is_empty())
            .map(|p| (p.start.clone(), p.end.clone()))
            .collect();
        let open_span = |from: &str, to: &str| !closed.iter().any(|(a, z)| a.as_str() <= to && z.as_str() >= from);
        for sh in shifts.iter_mut() {
            sh.month_open = open_span(&sh.date, &sh.date);
        }
        for r in out.requests.iter_mut() {
            r.month_open = match (r.from.as_deref(), r.to.as_deref()) {
                (Some(a), z) => open_span(a, z.unwrap_or(a).max(a)),
                (None, _) => true,
            };
        }

        shifts.sort_by(|a, z| (a.date.as_str(), a.id.as_str()).cmp(&(z.date.as_str(), z.id.as_str())));
        out.shifts = shifts;
        Ok(out)
    }
}

/// The server's answer to a filing, as the screens read it: the id they
/// know it by, its status, and whether it waits for someone above (RQ-5).
fn filed_of(prefix: &str, row: &Value) -> Value {
    json!({
        "id": format!("{prefix}|{}", s(row, "id")),
        "status": status_of(&s(row, "status")),
        "to_owner": b(row, "to_owner"),
    })
}

/// `user|date|tpl` → its parts.
fn parts(id: &str) -> (&str, &str, &str) {
    let mut p = id.splitn(3, '|');
    (p.next().unwrap_or_default(), p.next().unwrap_or_default(), p.next().unwrap_or_default())
}

/// A shift's start: the server's instant (DW1). Only a shift the server sent
/// no instant for is placed here, by the server's own rule.
fn shift_start(sh: &ShiftV, tz: &chrono_tz::Tz) -> Option<DateTime<Utc>> {
    if sh.start_at.is_some() {
        return sh.start_at;
    }
    let d = NaiveDate::parse_from_str(&sh.date, "%Y-%m-%d").ok()?;
    let t = NaiveTime::from_num_seconds_from_midnight_opt((sh.start.rem_euclid(1440) * 60) as u32, 0)?;
    wall_instant(tz, d.and_time(t))
}

/// Its end: the server's instant, else on the next date when it crosses
/// midnight.
fn shift_end(sh: &ShiftV, tz: &chrono_tz::Tz) -> Option<DateTime<Utc>> {
    if sh.end_at.is_some() {
        return sh.end_at;
    }
    let d = NaiveDate::parse_from_str(&sh.date, "%Y-%m-%d").ok()?;
    let d = if sh.end <= sh.start { d + Duration::days(1) } else { d };
    let t = NaiveTime::from_num_seconds_from_midnight_opt((sh.end.rem_euclid(1440) * 60) as u32, 0)?;
    wall_instant(tz, d.and_time(t))
}

/// A branch wall-clock time as an instant, the way Postgres's
/// `(date + time) AT TIME ZONE tz` places it (the server's shift instants):
/// a time in the spring-forward gap moves forward by the gap, and a time
/// that happens twice in the autumn is the later (standard-time) one.
/// chrono's `.earliest()` gave `None` and one hour early respectively.
fn wall_instant(tz: &chrono_tz::Tz, wall: NaiveDateTime) -> Option<DateTime<Utc>> {
    use chrono::offset::LocalResult;
    match tz.from_local_datetime(&wall) {
        LocalResult::Single(x) => Some(x.with_timezone(&Utc)),
        LocalResult::Ambiguous(_, later) => Some(later.with_timezone(&Utc)),
        LocalResult::None => (1..=3)
            .find_map(|h| tz.from_local_datetime(&(wall + Duration::hours(h))).latest())
            .map(|x| x.with_timezone(&Utc)),
    }
}

/// Each person's salary-advance cap as the server computed it (numeric
/// rounding in `dawam_advance_cap`); none where the server sent none.
fn advance_caps(people: &[Value]) -> impl Iterator<Item = (String, i64)> + '_ {
    people.iter().filter_map(|p| Some((s(p, "employee_id"), p.get("advance_cap_piastres")?.as_i64()?)))
}

/// What an adjustment is worth: the server's `value_piastres` (a % of salary
/// is rounded by the server's numeric maths: 1500 × 33.3% = 500, where f64
/// gave 499). Without it, a flat line is its amount; a % line is unpriced (0).
fn adj_value(a: &Value, pct: Option<f64>) -> i64 {
    a.get("value_piastres").and_then(Value::as_i64).unwrap_or_else(|| if pct.is_some() { 0 } else { i(a, "amount_piastres") })
}

/// A branch's geofence radius by the server's rule (madar-shared's
/// `madar_dawam::geofence::effective_radius`, DW2): unset is 200 m, and 0 is
/// 0 m — not 200, or the phone says "inside" where the server refuses the punch.
fn effective_radius(br: &Value) -> i64 {
    madar_dawam::geofence::effective_radius(br.get("geo_radius_meters").and_then(Value::as_i64))
}

/// The pay period `d` falls in, for a business starting on `start_day` (PAY-1):
/// madar-shared's `madar_dawam::pay::period_window`, the server's.
fn period_around(d: NaiveDate, start_day: i64) -> (NaiveDate, NaiveDate) {
    madar_dawam::pay::period_window(d, start_day)
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

/// Who decides public holidays (decision #3): `hr.rules.edit` held at
/// every branch, as the server lists it in `caps_everywhere` (the same right
/// as the rules). A server that doesn't send that list yet: the owner.
fn decides_holidays(ctx: &Value) -> bool {
    match ctx.get("caps_everywhere").and_then(Value::as_array) {
        Some(all) => all.iter().any(|c| c.as_str() == Some("hr.rules.edit")),
        None => role_of(&s(ctx, "role")) == "owner",
    }
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
            // An audited month (the fairness check): "Aug 2026", like the calendar's range.
            ("month", Value::String(x)) => NaiveDate::parse_from_str(&x[..x.len().min(10)], "%Y-%m-%d")
                .map(|d| format!("{} {}", i18n::tr(locale, &format!("staff.month_{}", d.month())), d.year()))
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
        date: None,
        note: None,
    });
    let ot = i(s_, "overtime_piastres");
    if ot > 0 {
        let m = i(s_, "overtime_minutes");
        lines.push(LineV { key: "ot".into(), en: format!("Overtime ({m} min)"), ar: format!("وقت إضافي ({m} د)"), amount: ot, rule: false, manual: None, waived: false, date: None, note: None });
    }
    for l in arr(bd, "bonuses") {
        let (en, ar) = match (s(l, "kind").as_str(), s(l, "reason")) {
            ("cover", _) => ("Cover shifts".to_string(), "ورديات تغطية".to_string()),
            ("holiday", _) => ("Public holiday worked".to_string(), "شغل في إجازة رسمية".to_string()),
            (_, r) => (r.clone(), r),
        };
        let id = so(l, "id");
        lines.push(LineV { key: format!("b|{}", id.clone().unwrap_or_default()), en, ar, amount: i(l, "piastres"), rule: false, manual: id.map(|x| format!("a|bonus|{x}")), waived: false, date: so(l, "effective_date"), note: None });
    }
    for l in arr(bd, "deductions") {
        let carry = s(l, "kind") == "carry";
        let manual = s(l, "source") == "manual";
        let id = s(l, "id");
        lines.push(LineV {
            key: if carry { "carry".into() } else { format!("d|{id}") },
            en: if carry { "Carried from the last payslip".into() } else { rule_words(l, "en") },
            ar: if carry { "مُرحّل من القسيمة اللي فاتت".into() } else { rule_words(l, "ar") },
            amount: -i(l, "piastres"),
            rule: !carry && !manual,
            manual: manual.then(|| format!("a|deduction|{id}")),
            waived: b(l, "waived"),
            date: so(l, "effective_date"),
            note: so(l, "waive_reason").filter(|_| b(l, "waived")).or_else(|| so(l, "override_reason")).filter(|n| !n.trim().is_empty()),
        });
    }
    let mut collected = BTreeMap::new();
    for a in arr(bd, "advances") {
        let take = i(a, "applied_piastres");
        if take == 0 {
            continue;
        }
        collected.insert(s(a, "id"), take);
        lines.push(LineV { key: format!("adv|{}", s(a, "id")), en: "Advance installment".into(), ar: "قسط سلفة".into(), amount: -take, rule: false, manual: None, waived: false, date: None, note: None });
    }
    SlipV {
        emp: s(s_, "employee_id"),
        start: p.start.clone(),
        end: p.end.clone(),
        lines,
        net: i(s_, "net_piastres"),
        carry_out: i(s_, "carry_out_piastres"),
        collected,
        frozen,
        salary_missing: b(s_, "salary_missing"),
    }
}

/// What made a rule line (minor #30): "Rule · late", "Rule · absence"…; None
/// for a line someone added by hand.
fn rule_label(a: &Value, locale: &str) -> Option<String> {
    let key = match s(a, "source").as_str() {
        "" | "manual" => return None,
        "late_penalty" => "staff.rule_late",
        "absence" => "staff.rule_absence",
        "excused_unpaid" => "staff.rule_excuse",
        "flag" => "staff.rule_flag",
        _ => "staff.rule",
    };
    Some(i18n::tr(locale, key))
}

/// A deduction's words in [lang]: a rule-made line by the server's
/// `reason_code` + `reason_vars` (so Arabic reads Arabic), else the server's
/// `reason` — a person's own words, or a code this build doesn't know.
fn rule_words(l: &Value, lang: &str) -> String {
    const CODES: [&str; 7] = ["late", "absent_no_punch", "unpaid_leave", "absent_half_unpaid_leave", "unpaid_excused_minutes", "unpaid_excuse", "left_mid_shift"];
    match l.get("reason_code").and_then(Value::as_str).filter(|c| CODES.contains(c)) {
        Some(code) => {
            let vars: BTreeMap<String, String> = l.get("reason_vars").and_then(Value::as_object).into_iter().flatten()
                .map(|(k, v)| (k.clone(), v.as_str().map_or_else(|| v.to_string(), str::to_string)))
                .collect();
            fill(&crate::i18n::tr(lang, &format!("staff.pay_reason_{code}")), &vars)
        }
        None => s(l, "reason"),
    }
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
    fn presence_is_the_servers_board_by_person() {
        let board = json!({ "rows": [
            { "employee_id": "e1", "state": "late", "check_in_at": "2026-09-23T06:12:00Z", "late_minutes": 12 },
            { "employee_id": "e4", "state": "absent", "late_minutes": 0 },
            { "employee_id": "", "state": "in" },
            { "employee_id": "e9", "state": "" }
        ]});
        let p = presence_of(&board);
        assert_eq!(p.len(), 2, "rows without a person or a state are dropped");
        assert_eq!(p["e1"], PresenceV { state: "late".into(), since: Some("2026-09-23T06:12:00Z".into()), late_minutes: 12 });
        assert_eq!(p["e4"].state, "absent");
        assert!(presence_of(&Value::Null).is_empty(), "no board (employee, offline first run): nothing");
    }

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

    /// The stamp this phone sends is madar-shared's `OfflineStamp`, the type
    /// the server decodes it with, and an anchor's time is read the server's way.
    #[test]
    fn the_stamp_is_the_shared_offline_stamp() {
        let signed = format!("v1.1758700000000.{}", "ab".repeat(32));
        for a in [
            None,
            Some(Anchor { server_ms: 1_758_700_000_000, boot_ms: 50_000, wall_ms: 1_758_700_000_000, sig: Some(signed.clone()) }),
        ] {
            let v = stamp(a, 80_000, 1_758_700_030_000, Some("2026-09-24T08:00:00Z"));
            let s: madar_dawam::stamp::OfflineStamp = serde_json::from_value(v.clone()).expect("the shared stamp type");
            assert_eq!(s.elapsed_ms, v["elapsed_ms"].as_i64().unwrap());
        }
        let anchor = crate::net::StaffAnchor { signed, boot_ms: 0, wall_ms: 0 };
        assert_eq!(anchor.server_ms(), Some(1_758_700_000_000));
    }

    #[test]
    fn an_offline_stamp_counts_uptime_and_notices_a_reboot() {
        let a = Anchor { server_ms: 1_000_000, boot_ms: 50_000, wall_ms: 2_000_000, sig: None };
        let s = stamp(Some(a.clone()), 110_000, 2_060_000, None);
        assert_eq!(s["elapsed_ms"], 60_000);
        assert_eq!(s["rebooted"], false);
        // Uptime went backwards: the phone restarted.
        let s = stamp(Some(a.clone()), 5_000, 2_060_000, Some("2026-09-22T08:00:00Z"));
        assert_eq!(s["rebooted"], true);
        assert_eq!(s["gps_time"], "2026-09-22T08:00:00Z");
        // Restarted and has since run longer than before: the boot moment moved.
        let s = stamp(Some(a.clone()), 60_000_000, 2_000_000 + 3_600_000 * 20, None);
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

    /// The money acts the screens send (Phase B payroll): a reopen carries
    /// its reason, a flag deduction its reason, an un-waive its reason.
    #[test]
    fn money_acts_carry_their_reasons() {
        let reopen: Act = serde_json::from_value(json!({ "action": "reopen_payroll", "reason": "a line was missing" })).unwrap();
        assert!(matches!(reopen, Act::ReopenPayroll { ref reason } if reason == "a line was missing"));
        // An old screen that sends none still parses (the server refuses it in words).
        let bare: Act = serde_json::from_value(json!({ "action": "reopen_payroll" })).unwrap();
        assert!(matches!(bare, Act::ReopenPayroll { ref reason } if reason.is_empty()));
        let resolve: Act = serde_json::from_value(json!({ "action": "resolve", "flag": "f1", "how": "deduct", "deduct": 500, "reason": "left early" })).unwrap();
        assert!(matches!(resolve, Act::Resolve { ref reason, deduct: 500, .. } if reason.as_deref() == Some("left early")));
        let unwaive: Act = serde_json::from_value(json!({ "action": "unwaive", "key": "d|x", "reason": "wrong day" })).unwrap();
        assert!(matches!(unwaive, Act::Unwaive { ref key, ref reason } if key == "d|x" && reason == "wrong day"));
        let record: Act = serde_json::from_value(json!({ "action": "record_advance", "emp": "e2", "amount": 150000, "installments": 3 })).unwrap();
        assert!(matches!(record, Act::RecordAdvance { amount: 150_000, installments: 3, .. }));
    }

    /// DW1: a shift's instants are the server's, so a DST day neither loses
    /// a shift (Cairo 2026-04-24 00:30 is in the spring gap) nor moves one an
    /// hour early (2026-10-29 23:30 happens twice).
    #[test]
    fn shift_instants_are_the_servers_on_dst_days() {
        let tz: chrono_tz::Tz = "Africa/Cairo".parse().unwrap();
        let utc = |x: &str| DateTime::parse_from_rfc3339(x).unwrap().with_timezone(&Utc);
        // Postgres: 00:30 in the gap is 01:30 +03; 08:30 is +03.
        let gap = ShiftV { date: "2026-04-24".into(), start: 30, end: 510, start_at: Some(utc("2026-04-23T22:30:00Z")), end_at: Some(utc("2026-04-24T05:30:00Z")), ..Default::default() };
        assert_eq!(shift_start(&gap, &tz), Some(utc("2026-04-23T22:30:00Z")), "the gap shift exists and starts at the server's instant");
        assert_eq!(shift_end(&gap, &tz), Some(utc("2026-04-24T05:30:00Z")));
        // Postgres: the repeated 23:30 is standard time (+02); ends 07:30 +02.
        let twice = ShiftV { date: "2026-10-29".into(), start: 1410, end: 450, next_day: true, start_at: Some(utc("2026-10-29T21:30:00Z")), end_at: Some(utc("2026-10-30T05:30:00Z")), ..Default::default() };
        assert_eq!(shift_start(&twice, &tz), Some(utc("2026-10-29T21:30:00Z")), "not an hour early");
        assert_eq!(shift_end(&twice, &tz), Some(utc("2026-10-30T05:30:00Z")));

        // A shift the server sent no instant for is placed by the same rule.
        let no_at = |x: &ShiftV| ShiftV { start_at: None, end_at: None, ..x.clone() };
        assert_eq!(shift_start(&no_at(&gap), &tz), Some(utc("2026-04-23T22:30:00Z")), "was None with .earliest()");
        assert_eq!(shift_start(&no_at(&twice), &tz), Some(utc("2026-10-29T21:30:00Z")), "was 20:30Z with .earliest()");
        assert_eq!(shift_end(&no_at(&twice), &tz), Some(utc("2026-10-30T05:30:00Z")));
        // An ordinary day is unchanged.
        let plain = ShiftV { date: "2026-09-23".into(), start: 480, end: 960, ..Default::default() };
        assert_eq!(shift_start(&plain, &tz), Some(utc("2026-09-23T05:00:00Z")));
    }

    /// DW1: the snapshot places a shift by the roster's own instants. Here
    /// they disagree with the wall-clock times (as they do on a DST day): the
    /// shift started an hour ago by the server, and the phone must say so.
    #[tokio::test(flavor = "multi_thread")]
    async fn the_snapshot_places_a_shift_by_the_servers_instants() {
        use crate::staff::session_tests::{later, session, signed_in, EMP};
        use crate::testkit::{Stub, StubResponse, BRANCH};
        let exp = later();
        let now = Utc::now();
        let yesterday = (now.with_timezone(&chrono_tz::Africa::Cairo).date_naive() - Duration::days(1)).to_string();
        let (a, z) = ((now - Duration::hours(1)).to_rfc3339(), (now + Duration::hours(3)).to_rfc3339());
        let stub = Stub::start(move |r| {
            let path = r.path.split('?').next().unwrap_or_default();
            let res = match path {
                "/auth/staff/otp/verify" => StubResponse::json(200, session(&exp)),
                "/staff/me/context" => StubResponse::json(200, json!({
                    "role": "employee", "org_name": "Nile Café", "caps": [],
                    "privacy_accepted_at": "2026-09-01T08:00:00Z",
                    "branches": [{ "id": BRANCH, "name": "Zamalek", "geo_radius_meters": 200,
                                   "latitude": 30.0609, "longitude": 31.2197, "timezone": "Africa/Cairo" }],
                    "work_shifts": [{ "id": "w1", "name": "Night", "branch_id": BRANCH,
                                      "start_time": "00:30:00", "end_time": "04:30:00", "grace_minutes": 10 }],
                    "people": [{ "employee_id": EMP, "name": "Sara", "role": "employee", "branch_ids": [BRANCH] }],
                    "settings": { "period_start_day": 26 },
                })),
                // Yesterday 00:30–04:30 by the wall clock — long over — but
                // the server's instants say it is running now.
                "/staff/me/roster" => StubResponse::json(200, json!({
                    "shifts": [{ "employee_id": EMP, "date": yesterday, "work_shift_id": "w1",
                                 "start_time": "00:30:00", "end_time": "04:30:00",
                                 "start_at": a, "end_at": z }],
                    "team": [], "open_shifts": [], "swaps": [], "unpublished_weeks": [],
                })),
                p if p.ends_with("estimate") => StubResponse::json(200, json!({})),
                _ => StubResponse::json(200, json!([])),
            };
            Some(res)
        })
        .await;
        let core = signed_in(&stub).await;
        let v: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        let id = format!("{EMP}|{}|w1", (Utc::now().with_timezone(&chrono_tz::Africa::Cairo).date_naive() - Duration::days(1)));
        assert!(v["shifts"].as_array().unwrap().iter().any(|x| x["id"] == id.as_str()), "{v:#}");
        assert_eq!(v["my_now"], json!([id]), "running by the server's instants (was rebuilt from 00:30–04:30)");
        let sh = v["shifts"].as_array().unwrap().iter().find(|x| x["id"] == id.as_str()).unwrap();
        assert_eq!(sh["absent"], false, "not absent: by the server it hasn't ended");
    }

    /// DW2: the phone's fence follows the server's radius rule: unset is
    /// 200 m, 0 is 0 m (the server refuses a punch 150 m away), never 200.
    #[test]
    fn the_fence_radius_follows_the_servers_rule() {
        assert_eq!(effective_radius(&json!({})), 200);
        assert_eq!(effective_radius(&json!({ "geo_radius_meters": null })), 200);
        assert_eq!(effective_radius(&json!({ "geo_radius_meters": 0 })), 0, "was 200 on the phone");
        assert_eq!(effective_radius(&json!({ "geo_radius_meters": -5 })), 0);
        assert_eq!(effective_radius(&json!({ "geo_radius_meters": 350 })), 350);
        let d = haversine_m((30.02047, 31.004112), (30.02047 + 150.0 / 111_195.0, 31.004112));
        assert!(d > effective_radius(&json!({ "geo_radius_meters": 0 })) as f64, "150 m away is outside a 0 m fence");
    }

    /// DW3: money is the server's figure; the core no longer prices a % of
    /// salary in f64 (1500 EGP at 33.3%: the server's 500, f64 gave 499).
    #[test]
    fn caps_and_percent_lines_are_the_servers_figures() {
        let people = vec![
            json!({ "employee_id": "e1", "base_salary_piastres": 150_000, "advance_cap_piastres": 50_000 }),
            json!({ "employee_id": "e2", "base_salary_piastres": null }),
        ];
        let caps: BTreeMap<String, i64> = advance_caps(&people).collect();
        assert_eq!(caps.get("e1"), Some(&50_000), "the server's numeric rounding, not f64's 49 950");
        assert_eq!(caps.get("e2"), None, "no figure sent: none made up here");
        let pct = json!({ "percent_of_base": "33.3", "value_piastres": 50_000 });
        assert_eq!(adj_value(&pct, Some(33.3)), 50_000);
        assert_eq!(adj_value(&json!({ "percent_of_base": "33.3" }), Some(33.3)), 0, "never priced on the phone");
        assert_eq!(adj_value(&json!({ "amount_piastres": 12_500 }), None), 12_500);
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
                    { "id": "d1", "reason": "Late", "piastres": 5_000, "source": "late_penalty", "effective_date": "2026-09-17" },
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
        // A rule line reads in each language by its code; a person's words stay theirs.
        let coded = json!({ "employee_id": "u", "net_piastres": 0, "breakdown": { "deductions": [
            { "id": "d9", "reason": "Late by 55 minutes", "piastres": 12_500, "source": "late_penalty", "reason_code": "late", "reason_vars": { "minutes": 55 } },
            { "id": "d8", "reason": "Left early", "piastres": 100, "source": "flag", "reason_code": "left_mid_shift", "reason_vars": null },
            { "id": "d7", "reason": "Absent", "piastres": 100, "source": "absence", "reason_code": "something_new" },
            { "id": "d6", "reason": "Broke a glass", "piastres": 100, "source": "manual", "reason_code": null }
        ] } });
        let w = slip_of(&coded, &p, 0, false);
        let words = |k: &str| w.lines.iter().find(|l| l.key == k).map(|l| (l.en.clone(), l.ar.clone())).unwrap();
        assert_eq!(words("d|d9"), ("Late by 55 minutes".into(), "تأخير 55 دقيقة".into()));
        assert_eq!(words("d|d8"), ("Left mid-shift".into(), "خرج أثناء الوردية".into()));
        assert_eq!(words("d|d7"), ("Absent".into(), "Absent".into()), "an unknown code keeps the server's words");
        assert_eq!(words("d|d6"), ("Broke a glass".into(), "Broke a glass".into()), "a person's own words are never translated");
        // AD-6: each bonus and deduction carries its day.
        assert_eq!(sl.lines.iter().find(|l| l.key == "d|d1").unwrap().date.as_deref(), Some("2026-09-17"));
        assert_eq!(sl.lines[0].date, None, "the salary line has no day");
    }


    /// Minor #29 (AD-6): a waived line says why. The server's `waive_reason`
    /// (or an overridden line's `override_reason`) rides the line as `note`.
    #[test]
    fn a_waived_line_carries_its_reason() {
        let p = PeriodV { start: "2026-08-26".into(), end: "2026-09-25".into(), status: "open".into(), ..Default::default() };
        let c = json!({ "employee_id": "u", "net_piastres": 0, "breakdown": { "deductions": [
            { "id": "d1", "reason": "Absent", "piastres": 0, "source": "absence", "waived": true, "waive_reason": "Hospital visit" },
            { "id": "d2", "reason": "Late", "piastres": 2_000, "source": "late_penalty", "override_reason": "Traffic on the ring road" },
            { "id": "d3", "reason": "Late", "piastres": 5_000, "source": "late_penalty" }
        ] } });
        let sl = slip_of(&c, &p, 0, false);
        let note = |k: &str| sl.lines.iter().find(|l| l.key == k).unwrap().note.clone();
        assert_eq!(note("d|d1").as_deref(), Some("Hospital visit"));
        assert_eq!(note("d|d2").as_deref(), Some("Traffic on the ring road"));
        assert_eq!(note("d|d3"), None);
        assert_eq!(sl.lines[0].note, None, "the salary line has none");
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
        let secs = chrono::Offset::fix(cairo.offset()).local_minus_utc();
        let off = format!("{}{:02}:{:02}", if secs < 0 { '-' } else { '+' }, secs.abs() / 3600, secs.abs() % 3600 / 60);
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

    /// E2E (clocking C2): the server refuses a punch with 409 for real
    /// reasons — the owner hasn't saved the rules, the month is closed, the
    /// shift can't be covered now. A first send refused that way is a
    /// refusal: the screen gets the server's words and the queue drops it.
    /// It was acked as "the server already holds it", so the phone showed
    /// "Clocked in at 3:10 PM" and nothing was recorded. A 409 still means
    /// "already held" for a resend (an earlier try may have landed) and for a
    /// check-out or a ping (nothing is open: what it asked for is so).
    #[tokio::test(flavor = "multi_thread")]
    async fn a_punch_refused_with_409_is_a_refusal_not_a_silent_done() {
        use crate::testkit::{online_core, Stub, StubResponse, BRANCH, TELLER};
        use std::sync::{Arc, Mutex};

        let check_in = Arc::new(Mutex::new((409_u16, json!({
            "error": "Your business hasn't set its attendance rules yet — ask the owner to finish set-up.",
            "code": "RULES_NOT_SET",
        }))));
        let answer = check_in.clone();
        let cairo = Utc::now().with_timezone(&chrono_tz::Africa::Cairo);
        let today = cairo.date_naive().to_string();
        let hms = |t: NaiveTime| format!("{}:00", hhmm((t.hour() * 60 + t.minute()) as i64));
        let (start, end) = (hms(cairo.time() - Duration::hours(1)), hms(cairo.time() + Duration::hours(3)));
        let stub = Stub::start(move |r| {
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
                    "settings": { "period_start_day": 26, "advance_cap_percent": "50", "rules_saved": false },
                })),
                "/staff/me/roster" => StubResponse::json(200, json!({
                    "shifts": [{ "employee_id": TELLER, "date": today, "work_shift_id": "w1" }],
                    "team": [], "open_shifts": [], "swaps": [], "unpublished_weeks": [],
                })),
                "/staff/me/check-in" => {
                    let (status, body) = answer.lock().unwrap().clone();
                    StubResponse::json(status, body)
                }
                "/staff/me/check-out" => StubResponse::json(409, json!({ "error": "You are not clocked in." })),
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
        let fix = DawamFix { latitude: 30.0609, longitude: 31.2197, accuracy: Some(8.0), ..Default::default() };
        let clock_in = json!({ "action": "clock_in", "shift": shift, "fix": fix }).to_string();

        // Rules not saved: refused in the server's words, nothing shown as in.
        let err = core.dawam_do(clock_in.clone()).await.expect_err("a refused clock-in is not a success");
        assert!(format!("{err:?}").contains("hasn't set its attendance rules"), "{err:?}");
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(false).await.unwrap()).unwrap();
        assert_eq!(snap["active_shift"], Value::Null, "nothing is clocked in");
        assert_eq!(snap["queued"], 0, "the refused punch left the queue");
        let acked: i64 = core.store
            .with_conn(|c| Ok(c.query_row("SELECT COUNT(*) FROM outbox WHERE status = 'acked' AND op_type LIKE 'dawam_%'", [], |r| r.get(0))?))
            .unwrap();
        assert_eq!(acked, 0, "a refusal is never acked");

        // A stale screen on a shift already punched (S-075): its words.
        *check_in.lock().unwrap() = (409, json!({
            "error": "You have already checked in for this shift", "code": "ALREADY_CHECKED_IN", "vars": {},
        }));
        let err = core.dawam_do(clock_in.clone()).await.expect_err("already in: said so");
        assert!(format!("{err:?}").contains(&i18n::tr("en", "staff.err_already_checked_in")), "{err:?}");

        // A resend after a lost answer (the first try hit a 5xx): 409 = held.
        *check_in.lock().unwrap() = (503, json!({ "error": "busy" }));
        core.dawam_do(clock_in.clone()).await.expect("a 5xx keeps it queued");
        *check_in.lock().unwrap() = (409, json!({
            "error": "You have already checked in for this shift", "code": "ALREADY_CHECKED_IN", "vars": {},
        }));
        core.store.with_conn(|c| Ok(c.execute("UPDATE outbox SET next_attempt_at = 0", [])?)).unwrap();
        let snap: Value = serde_json::from_str(&core.dawam_sync().await.unwrap()).unwrap();
        assert_eq!(snap["queued"], 0, "the resend is held by the server");
        assert_eq!(dead_dawam_ops(&core), 0, "a resend's 409 is not a refusal");

        // A check-out with nothing open: what it asked for is already so.
        core.dawam_do(json!({ "action": "clock_out", "fix": fix }).to_string()).await.expect("nothing open is not an error");
        assert_eq!(dead_dawam_ops(&core), 0);
    }

    /// Owner decision BC-3 (E2E clocking): nothing is written into a closed
    /// month — a check-out dated in an approved or paid month gets 409
    /// PERIOD_CLOSED. The core took any 409 on a check-out as "nothing open,
    /// already so" and dropped it as done, so the phone read "clocked out"
    /// while the server still had the shift open. A coded refusal is a
    /// refusal: it comes back in the person's words and the shift stays open
    /// on screen. The plain "you are not clocked in" 409 is still held, and a
    /// ping refused for any reason is still dropped without a word.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_check_out_in_a_closed_month_is_refused_not_dropped() {
        use crate::testkit::{online_core, Stub, StubResponse, BRANCH, TELLER};
        use std::sync::{Arc, Mutex};

        let closed = json!({
            "error": "PERIOD_CLOSED: that month is paid — a check-out dated 2026-09-24 can't change it.",
            "code": "PERIOD_CLOSED", "vars": { "date": "2026-09-24", "paid": true },
        });
        let check_out = Arc::new(Mutex::new((409_u16, closed.clone())));
        let (out_answer, ping_closed) = (check_out.clone(), closed.clone());
        let cairo = Utc::now().with_timezone(&chrono_tz::Africa::Cairo);
        let today = cairo.date_naive().to_string();
        let hms = |t: NaiveTime| format!("{}:00", hhmm((t.hour() * 60 + t.minute()) as i64));
        let (start, end) = (hms(cairo.time() - Duration::hours(1)), hms(cairo.time() + Duration::hours(3)));
        let in_at = (Utc::now() - Duration::minutes(30)).to_rfc3339();
        let stub = Stub::start(move |r| {
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
                    "settings": { "period_start_day": 26, "advance_cap_percent": "50", "rules_saved": true },
                })),
                "/staff/me/roster" => StubResponse::json(200, json!({
                    "shifts": [{ "employee_id": TELLER, "date": today, "work_shift_id": "w1" }],
                    "team": [], "open_shifts": [], "swaps": [], "unpublished_weeks": [],
                })),
                // The server still holds the shift open: the check-out was refused.
                "/staff/me/attendance" => StubResponse::json(200, json!([{
                    "id": "r1", "employee_id": TELLER, "business_date": today, "work_shift_id": "w1",
                    "branch_id": BRANCH, "status": "present", "check_in_at": in_at, "check_in_method": "mobile_gps",
                }])),
                "/staff/me/check-out" => {
                    let (status, body) = out_answer.lock().unwrap().clone();
                    StubResponse::json(status, body)
                }
                "/staff/me/pings" => StubResponse::json(409, ping_closed.clone()),
                "/health" => StubResponse::text(200, "ok"),
                p if p.ends_with("estimate") || p.ends_with("context") => StubResponse::json(200, json!({})),
                _ => StubResponse::json(200, json!([])),
            })
        })
        .await;
        let core = online_core(&stub.base, "").await;
        core.set_online(true);
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        let shift = snap["active_shift"].as_str().expect("clocked in on the server").to_string();
        let fix = DawamFix { latitude: 30.0609, longitude: 31.2197, accuracy: Some(8.0), ..Default::default() };
        let clock_out = json!({ "action": "clock_out", "fix": fix }).to_string();
        let acked = |core: &MadarCore| -> i64 {
            core.store
                .with_conn(|c| Ok(c.query_row("SELECT COUNT(*) FROM outbox WHERE status = 'acked' AND op_type LIKE 'dawam_%'", [], |r| r.get(0))?))
                .unwrap()
        };

        for lang in ["en", "ar"] {
            core.set_locale(lang.into());
            match core.dawam_do(clock_out.clone()).await {
                Err(CoreError::Server { status: 409, detail, .. }) => {
                    assert_eq!(detail, i18n::tr(lang, "staff.err_period_closed"), "{lang}: in the person's words");
                }
                other => panic!("{lang}: a closed month refuses the check-out, got {other:?}"),
            }
            let snap: Value = serde_json::from_str(&core.dawam_snapshot(false).await.unwrap()).unwrap();
            assert_eq!(snap["active_shift"], json!(shift), "{lang}: still clocked in on screen");
            assert_eq!(snap["queued"], 0, "{lang}: the refused check-out left the queue");
            assert_eq!(acked(&core), 0, "{lang}: a refusal is never acked");
        }

        // A ping refused because the month is closed: dropped without a word.
        core.set_locale("en".into());
        core.dawam_ping(fix.clone()).await.expect("a refused ping says nothing");
        assert_eq!(dead_dawam_ops(&core), 0, "a refused ping is not shown as stuck");

        // "You are not clocked in": what the check-out asked for is already so.
        *check_out.lock().unwrap() = (409, json!({ "error": "Conflict: You are not clocked in." }));
        core.dawam_do(clock_out.clone()).await.expect("nothing open is not an error");
        assert_eq!(dead_dawam_ops(&core), 0);
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

    /// A signed server time as the backend writes it (`v1.<ms>.<64 hex>`);
    /// the phone never checks the tag, it only carries it back.
    fn signed_at(ms: i64) -> String {
        format!("v1.{ms}.{}", "ab".repeat(32))
    }

    /// What a [`staff_stub`] does, switched by the test as it goes.
    struct Knobs {
        /// false = the signal is gone (every call hangs up).
        up: std::sync::atomic::AtomicBool,
        /// The first token (`t1`) is refused as expired.
        t1_expired: std::sync::atomic::AtomicBool,
        /// This phone accepted the location notice (AT-5).
        accepted: std::sync::atomic::AtomicBool,
    }

    fn knobs() -> std::sync::Arc<Knobs> {
        use std::sync::atomic::AtomicBool;
        std::sync::Arc::new(Knobs { up: AtomicBool::new(true), t1_expired: AtomicBool::new(false), accepted: AtomicBool::new(true) })
    }

    /// A Dawam stub for a signed-in employee with a shift around now at a
    /// Cairo branch; every answer carries the signed time. `refresh` answers
    /// `/auth/staff/refresh`.
    async fn staff_stub(
        k: std::sync::Arc<Knobs>,
        refresh: impl Fn() -> crate::testkit::StubResponse + Send + Sync + 'static,
    ) -> crate::testkit::Stub {
        use crate::staff::session_tests::{later, session, EMP};
        use crate::testkit::{Stub, StubResponse, BRANCH};
        use std::sync::atomic::Ordering;
        let exp = later();
        let cairo = Utc::now().with_timezone(&chrono_tz::Africa::Cairo);
        let today = cairo.date_naive().to_string();
        let hms = |t: NaiveTime| format!("{}:00", hhmm((t.hour() * 60 + t.minute()) as i64));
        let (start, end) = (hms(cairo.time() - Duration::hours(1)), hms(cairo.time() + Duration::hours(3)));
        Stub::start(move |r| {
            if !k.up.load(Ordering::SeqCst) {
                return Some(StubResponse::hangup());
            }
            let bearer = r.header("authorization").unwrap_or_default();
            let located = r.method == "POST" && r.json().get("latitude").is_some_and(|x| !x.is_null());
            let path = r.path.split('?').next().unwrap_or_default();
            let res = match path {
                "/auth/staff/otp/verify" => StubResponse::json(200, session(&exp)),
                "/auth/staff/refresh" => refresh(),
                "/health" => StubResponse::text(200, "ok"),
                _ if bearer == "Bearer t1" && k.t1_expired.load(Ordering::SeqCst) => {
                    StubResponse::json(401, json!({ "error": "expired", "code": "TOKEN_EXPIRED" }))
                }
                "/staff/me/context" => StubResponse::json(200, json!({
                    "role": "employee", "org_name": "Nile Café", "caps": [],
                    "privacy_accepted_at": if k.accepted.load(Ordering::SeqCst) { json!("2026-09-01T08:00:00Z") } else { Value::Null },
                    "branches": [{ "id": BRANCH, "name": "Zamalek", "geo_radius_meters": 200,
                                   "latitude": 30.0609, "longitude": 31.2197, "timezone": "Africa/Cairo" }],
                    "work_shifts": [{ "id": "w1", "name": "Morning", "branch_id": BRANCH,
                                      "start_time": start, "end_time": end, "grace_minutes": 10 }],
                    "people": [{ "employee_id": EMP, "name": "Sara", "role": "employee", "branch_ids": [BRANCH],
                                 "base_salary_piastres": 900000, "pay_method": "cash", "cant_work_days": [] }],
                    "settings": { "period_start_day": 26, "advance_cap_percent": "50" },
                })),
                "/staff/me/roster" => StubResponse::json(200, json!({
                    "shifts": [{ "employee_id": EMP, "date": today, "work_shift_id": "w1" }],
                    "team": [], "open_shifts": [], "swaps": [], "unpublished_weeks": [],
                })),
                "/staff/me/privacy" => {
                    k.accepted.store(true, Ordering::SeqCst);
                    StubResponse::json(200, json!({ "accepted_at": "2026-09-23T08:00:00Z" }))
                }
                "/staff/me/check-in" | "/staff/me/check-out" | "/staff/me/pings" if located && !k.accepted.load(Ordering::SeqCst) => {
                    StubResponse::json(403, json!({ "error": "Accept the location notice in the app first.", "code": "PRIVACY_NOT_ACCEPTED" }))
                }
                "/staff/me/check-in" => StubResponse::json(201, json!({ "id": "r1" })),
                "/staff/me/check-out" => StubResponse::json(200, json!({ "id": "r1" })),
                "/staff/me/pings" => StubResponse::json(200, json!({ "inside": true })),
                p if p.ends_with("estimate") => StubResponse::json(200, json!({})),
                _ => StubResponse::json(200, json!([])),
            };
            // Every staff answer carries the server's signed time (CL-11).
            Some(res.with_header("x-dawam-time", &signed_at(Utc::now().timestamp_millis())))
        })
        .await
    }

    /// Hours without a signal (the anchor was received that long ago).
    fn age_the_anchor(core: &MadarCore, by: Duration) -> Anchor {
        let a: Anchor = serde_json::from_str(&core.store.kv_get(K_ANCHOR).unwrap().unwrap()).unwrap();
        let ms = by.num_milliseconds();
        let old = Anchor {
            server_ms: a.server_ms - ms,
            boot_ms: a.boot_ms - ms,
            wall_ms: a.wall_ms - ms,
            sig: Some(signed_at(a.server_ms - ms)),
        };
        core.store.kv_put(K_ANCHOR, &serde_json::to_string(&old).unwrap()).unwrap();
        core.api.set_staff_anchor(Some(crate::net::StaffAnchor {
            signed: old.sig.clone().unwrap(),
            boot_ms: old.boot_ms,
            wall_ms: old.wall_ms,
        }));
        old
    }

    fn dead_dawam_ops(core: &MadarCore) -> i64 {
        core.store
            .with_conn(|c| Ok(c.query_row("SELECT COUNT(*) FROM outbox WHERE status = 'dead' AND op_type LIKE 'dawam_%'", [], |r| r.get(0))?))
            .unwrap()
    }

    /// The owner's case (RESUME "Offline × Phase A token"). The signal goes
    /// for three hours — the 60-minute staff token runs out long before it
    /// comes back. The punches and pings wait on the phone, each stamped with
    /// the SIGNED server time it last saw plus the time since boot from it.
    /// When the signal is back the token is refreshed once, through the
    /// device, and the queue goes out in order, each one dated from that
    /// signed time — nothing lost, nothing re-dated to the sync.
    #[tokio::test(flavor = "multi_thread")]
    async fn hours_offline_past_the_token_then_one_refresh_and_an_ordered_signed_flush() {
        use crate::staff::session_tests::{later, signed_in, EMP, ORG};
        use crate::testkit::StubResponse;
        use std::sync::atomic::Ordering;

        let k = knobs();
        let stub = staff_stub(k.clone(), || {
            StubResponse::json(200, json!({ "token": "t2", "expires_at": later(), "employee_id": EMP, "org_id": ORG }))
        })
        .await;
        let core = signed_in(&stub).await;
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        let shift = snap["my_now"][0].as_str().expect("today's shift is mine").to_string();
        let kept: Anchor = serde_json::from_str(&core.store.kv_get(K_ANCHOR).unwrap().unwrap()).unwrap();
        assert!(kept.sig.as_deref().is_some_and(|x| x.starts_with("v1.")), "the signed time is kept: {kept:?}");

        // The signal goes, and stays gone three hours: the anchor is that old
        // and the 60-minute token ran out two hours ago.
        k.up.store(false, Ordering::SeqCst);
        let three_h = Duration::hours(3);
        let old = age_the_anchor(&core, three_h);
        core.api.set_staff_expiry(Some(&(Utc::now() - Duration::hours(2)).to_rfc3339()));
        k.t1_expired.store(true, Ordering::SeqCst);

        let fix = DawamFix { latitude: 30.0609, longitude: 31.2197, accuracy: Some(9.0), ..Default::default() };
        core.dawam_do(json!({ "action": "clock_in", "shift": shift, "fix": fix }).to_string()).await.unwrap();
        core.dawam_ping(fix.clone()).await.unwrap();
        core.dawam_ping(fix.clone()).await.unwrap();
        let snap: Value =
            serde_json::from_str(&core.dawam_do(json!({ "action": "clock_out", "fix": fix }).to_string()).await.unwrap()).unwrap();
        assert_eq!(snap["queued"], 4, "all four wait on the phone");
        assert_eq!(dead_dawam_ops(&core), 0, "an unreachable refresh never kills a punch");
        assert!(!core.sync_status().auth_paused, "no signal is not a signed-out phone");

        // Back online: queued long ago, so each goes with its offline stamp.
        core.store.with_conn(|c| Ok(c.execute("UPDATE outbox SET payload = json_set(payload, '$.queued_ms', 0)", [])?)).unwrap();
        stub.seen.lock().unwrap().clear();
        k.up.store(true, Ordering::SeqCst);
        let snap: Value = serde_json::from_str(&core.dawam_sync().await.unwrap()).unwrap();
        assert_eq!(snap["queued"], 0, "flushed");
        assert_eq!(stub.requests("/auth/staff/refresh").len(), 1, "one refresh through the device, not one per punch");
        assert_eq!(stub.requests("/auth/staff/refresh")[0].header("x-staff-device").as_deref(), Some("dev-1"));
        let posts: Vec<_> = stub.seen.lock().unwrap().iter().filter(|r| r.method == "POST" && r.path.starts_with("/staff/")).cloned().collect();
        assert_eq!(
            posts.iter().map(|r| r.path.as_str()).collect::<Vec<_>>(),
            ["/staff/me/check-in", "/staff/me/pings", "/staff/me/pings", "/staff/me/check-out"],
            "in the order they happened"
        );
        let punch = posts[0].json();
        assert_eq!((punch["accuracy_meters"].as_f64(), punch["is_mock"].as_bool()), (Some(9.0), Some(false)), "the punch's own spoof signals (CL-9)");
        let mut last = 0;
        for p in &posts {
            assert_eq!(p.header("authorization").as_deref(), Some("Bearer t2"), "the fresh token");
            let off = &p.json()["offline"];
            assert_eq!(off["anchor"], json!(old.sig), "the signed time from before the signal went");
            assert_eq!(off["server_time"], json!(ms_rfc3339(old.server_ms)));
            assert_eq!(off["rebooted"], false);
            let el = off["elapsed_ms"].as_i64().unwrap();
            assert!(el >= three_h.num_milliseconds() && el < (three_h + Duration::minutes(5)).num_milliseconds(), "{el}");
            assert!(el >= last, "dated in order");
            last = el;
        }
    }

    /// A refresh the server can't answer (503) is a blip, not a refusal: the
    /// queued punch stays queued however often it fails, and goes the moment
    /// the refresh works.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_failing_refresh_keeps_the_punch_queued_until_it_works() {
        use crate::staff::session_tests::{later, signed_in, EMP, ORG};
        use crate::testkit::StubResponse;
        use std::sync::atomic::{AtomicBool, Ordering};
        use std::sync::Arc;

        let broken = Arc::new(AtomicBool::new(false));
        let b2 = broken.clone();
        let k = knobs();
        let stub = staff_stub(k.clone(), move || {
            if b2.load(Ordering::SeqCst) {
                StubResponse::json(503, json!({ "error": "down for a moment" }))
            } else {
                StubResponse::json(200, json!({ "token": "t2", "expires_at": later(), "employee_id": EMP, "org_id": ORG }))
            }
        })
        .await;
        let core = signed_in(&stub).await;
        core.dawam_snapshot(true).await.unwrap();
        broken.store(true, Ordering::SeqCst);
        k.t1_expired.store(true, Ordering::SeqCst);
        core.api.set_staff_expiry(Some(&(Utc::now() - Duration::hours(1)).to_rfc3339()));
        core.dawam_enqueue("dawam_ping", "/staff/me/pings", json!({ "latitude": 30.06, "longitude": 31.21 }), None).unwrap();
        for round in 0..12 {
            // However long it has been failing, it is due again.
            core.store.with_conn(|c| Ok(c.execute("UPDATE outbox SET next_attempt_at = 0", [])?)).unwrap();
            let _ = core.dawam_sync().await;
            assert_eq!(core.dawam_queued().unwrap().len(), 1, "round {round}: still queued");
            assert_eq!(dead_dawam_ops(&core), 0, "round {round}: never dead");
        }
        assert!(stub.requests("/staff/me/pings").iter().all(|r| r.header("authorization").as_deref() == Some("Bearer t1")));
        broken.store(false, Ordering::SeqCst);
        core.store.with_conn(|c| Ok(c.execute("UPDATE outbox SET next_attempt_at = 0", [])?)).unwrap();
        core.dawam_sync().await.unwrap();
        assert!(core.dawam_queued().unwrap().is_empty(), "sent once the refresh worked");
        assert_eq!(stub.requests("/staff/me/pings").last().unwrap().header("authorization").as_deref(), Some("Bearer t2"));
    }

    /// A phone signed out elsewhere (`DEVICE_REVOKED`) parks the queue instead
    /// of dropping it: the punches wait, and go under the person's next
    /// sign-in.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_revoked_phone_parks_the_queue_and_the_next_sign_in_sends_it() {
        use crate::staff::session_tests::{later, EMP, ORG};
        use crate::testkit::StubResponse;
        use std::sync::atomic::{AtomicBool, Ordering};
        use std::sync::Arc;

        let revoked = Arc::new(AtomicBool::new(false));
        let r2 = revoked.clone();
        let k = knobs();
        let stub = staff_stub(k.clone(), move || {
            if r2.load(Ordering::SeqCst) {
                StubResponse::json(401, json!({ "error": "This phone was signed out.", "code": "DEVICE_REVOKED" }))
            } else {
                StubResponse::json(200, json!({ "token": "t2", "expires_at": later(), "employee_id": EMP, "org_id": ORG }))
            }
        })
        .await;
        let core = crate::staff::session_tests::signed_in(&stub).await;
        core.dawam_snapshot(true).await.unwrap();
        revoked.store(true, Ordering::SeqCst);
        k.t1_expired.store(true, Ordering::SeqCst);
        core.api.set_staff_expiry(Some(&(Utc::now() - Duration::hours(1)).to_rfc3339()));
        core.dawam_enqueue("dawam_ping", "/staff/me/pings", json!({ "latitude": 30.06, "longitude": 31.21 }), None).unwrap();
        let err = core.dawam_sync().await.unwrap_err();
        assert!(matches!(err, CoreError::Unauthenticated { .. }), "{err:?}");
        assert!(core.sync_status().auth_paused, "parked");
        assert_eq!(core.dawam_queued().unwrap().len(), 1, "kept");
        assert_eq!(dead_dawam_ops(&core), 0);

        // The app signs out (keeping the queue); the person signs in again.
        core.logout(false).unwrap();
        revoked.store(false, Ordering::SeqCst);
        core.staff_otp_verify("+201001234567".into(), "123456".into(), None, None, None).await.unwrap();
        core.dawam_sync().await.unwrap();
        assert!(core.dawam_queued().unwrap().is_empty(), "sent under the new sign-in");
    }

    /// 06 B4: the fence line is the real distance from a FRESH reading. No
    /// reading, or one from long ago, is "unknown" — never "inside".
    #[tokio::test(flavor = "multi_thread")]
    async fn the_fence_line_is_a_fresh_real_distance_and_unknown_is_not_inside() {
        use crate::staff::session_tests::signed_in;
        use crate::testkit::{StubResponse, BRANCH};
        let stub = staff_stub(knobs(), || StubResponse::json(503, json!({}))).await;
        let core = signed_in(&stub).await;
        let snap = |j: String| serde_json::from_str::<Value>(&j).unwrap();

        let v = snap(core.dawam_snapshot(true).await.unwrap());
        assert_eq!(v["fences"][BRANCH], json!({ "state": "unknown", "distance_m": null, "radius": 200 }));
        assert!(v["inside"].is_null(), "no reading: unknown, not inside");

        // 150 m north of the branch: inside, and it says how far.
        let near = DawamFix { latitude: 30.0609 + 150.0 / 111_195.0, longitude: 31.2197, accuracy: Some(10.0), ..Default::default() };
        let v = snap(core.dawam_do(json!({ "action": "note_fix", "fix": near }).to_string()).await.unwrap());
        assert_eq!(v["fences"][BRANCH]["state"], "inside");
        assert_eq!(v["fences"][BRANCH]["distance_m"], 150);
        assert_eq!((v["inside"].as_bool(), v["distance_m"].as_f64()), (Some(true), Some(150.0)));
        assert!(stub.requests("/staff/me/pings").is_empty(), "noting a reading sends nothing");

        // 340 m away: outside, with its own distance (the old line always said 340).
        let far = DawamFix { latitude: 30.0609 + 612.0 / 111_195.0, ..near.clone() };
        let v = snap(core.dawam_do(json!({ "action": "note_fix", "fix": far }).to_string()).await.unwrap());
        assert_eq!((v["fences"][BRANCH]["state"].as_str(), v["fences"][BRANCH]["distance_m"].as_i64()), (Some("outside"), Some(612)));

        // The same reading an hour later says nothing about now.
        let old = NotedFix { fix: near, noted_boot_ms: Some(boot_ms() - 60 * 60_000) };
        core.store.kv_put(K_FIX, &serde_json::to_string(&old).unwrap()).unwrap();
        let v = snap(core.dawam_snapshot(false).await.unwrap());
        assert_eq!(v["fences"][BRANCH]["state"], "unknown");
        assert!(v["inside"].is_null() && v["distance_m"].is_null());
        // A reading kept by an older build (no time) is stale too.
        core.store.kv_put(K_FIX, r#"{"latitude":30.0609,"longitude":31.2197}"#).unwrap();
        let v = snap(core.dawam_snapshot(false).await.unwrap());
        assert_eq!(v["fences"][BRANCH]["state"], "unknown");
    }

    /// AT-5: the notice is accepted per phone on the server. The snapshot
    /// says whether it was; accepting needs a connection; a punch made before
    /// is held (never dropped) and goes once the notice is accepted.
    #[tokio::test(flavor = "multi_thread")]
    async fn the_notice_is_accepted_on_the_server_and_a_held_punch_goes_after() {
        use crate::staff::session_tests::signed_in;
        use crate::testkit::StubResponse;
        use std::sync::atomic::Ordering;
        let k = knobs();
        k.accepted.store(false, Ordering::SeqCst);
        let stub = staff_stub(k.clone(), || StubResponse::json(503, json!({}))).await;
        let core = signed_in(&stub).await;
        let snap = |j: String| serde_json::from_str::<Value>(&j).unwrap();
        let v = snap(core.dawam_snapshot(true).await.unwrap());
        assert_eq!(v["privacy_accepted"], false, "a new phone has not accepted");
        let shift = v["my_now"][0].as_str().unwrap().to_string();

        // A punch that reaches the server before the notice is accepted.
        let fix = DawamFix { latitude: 30.0609, longitude: 31.2197, accuracy: Some(9.0), ..Default::default() };
        let _ = core.dawam_do(json!({ "action": "clock_in", "shift": shift, "fix": fix }).to_string()).await;
        assert_eq!(core.dawam_queued().unwrap().len(), 1, "held, not dropped");
        assert_eq!(dead_dawam_ops(&core), 0);

        // Offline, accepting says it needs a connection.
        k.up.store(false, Ordering::SeqCst);
        core.set_online(false);
        let err = core.dawam_do(json!({ "action": "accept_privacy" }).to_string()).await.unwrap_err();
        assert!(matches!(err, CoreError::Offline { .. }), "{err:?}");
        k.up.store(true, Ordering::SeqCst);
        core.set_online(true);

        let v = snap(core.dawam_do(json!({ "action": "accept_privacy" }).to_string()).await.unwrap());
        assert_eq!(stub.requests("/staff/me/privacy").len(), 1);
        assert_eq!(v["privacy_accepted"], true);
        assert_eq!(v["queued"], 0, "the held punch went once the notice was accepted");
        assert_eq!(stub.requests("/staff/me/check-in").len(), 2, "refused once, then taken");
    }

    /// AT-1 / audit 03 bug 12: "today" is my branch's day, not the first
    /// branch the mirror lists (a manager sees every branch).
    #[tokio::test(flavor = "multi_thread")]
    async fn today_is_my_branchs_day_not_the_first_branch_listed() {
        use crate::testkit::{online_core, Stub, StubResponse, TELLER};
        let stub = Stub::start(|r| {
            let path = r.path.split('?').next().unwrap_or_default();
            Some(match path {
                "/staff/me/context" => StubResponse::json(200, json!({
                    "role": "employee", "org_name": "Nile", "caps": [],
                    "branches": [
                        { "id": "far", "name": "Honolulu", "timezone": "Pacific/Honolulu" },
                        { "id": "mine", "name": "Kiritimati", "timezone": "Pacific/Kiritimati" },
                    ],
                    "work_shifts": [], "settings": {},
                    "people": [{ "employee_id": TELLER, "name": "Sara", "role": "employee", "branch_ids": ["mine"] }],
                })),
                "/health" => StubResponse::text(200, "ok"),
                p if p.ends_with("estimate") => StubResponse::json(200, json!({})),
                _ => StubResponse::json(200, json!([])),
            })
        })
        .await;
        let core = online_core(&stub.base, "").await;
        core.set_online(true);
        core.dawam_snapshot(true).await.unwrap();
        // UTC−10 and UTC+14 are always on different days.
        let kiritimati = Utc::now().with_timezone(&chrono_tz::Pacific::Kiritimati).date_naive();
        assert_eq!(core.dawam_today(), kiritimati);
        assert_eq!(core.dawam_tz(), chrono_tz::Pacific::Kiritimati);
    }

    #[test]
    fn a_managers_punch_and_a_correction_read_as_what_they_are() {
        assert_eq!(method_of("manager").as_deref(), Some("manager"), "CL-16: the server writes `manager` now");
        assert_eq!(method_of("manual").as_deref(), Some("manager"));
        assert_eq!(method_of("correction").as_deref(), Some("correction"));
        assert_eq!(method_of("till").as_deref(), Some("till"));
        assert_eq!(method_of("nonsense"), None);
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

    /// A stub server for the roster board: the owner (TELLER here) at one
    /// branch; Omar (`P`) has a split day on `day` — Morning, and an Evening
    /// with its own times running past midnight; one open shift.
    async fn roster_stub(day: String) -> crate::testkit::Stub {
        roster_stub_refusing(day, None).await
    }

    /// [`roster_stub`], whose day writes on [refuse] are refused: the block
    /// isn't worked that weekday (`SHIFT_NOT_ON_DAY`).
    async fn roster_stub_refusing(day: String, refuse: Option<String>) -> crate::testkit::Stub {
        use crate::testkit::{Stub, StubResponse, BRANCH, TELLER};
        Stub::start(move |r| {
            let path = r.path.split('?').next().unwrap_or_default();
            Some(match (r.method.as_str(), path) {
                ("PUT", "/staff/schedules/days") if refuse.as_deref().is_some_and(|d| r.json()["on_date"] == d) => StubResponse::json(400, json!({
                    "error": "Evening isn't a shift on that day.", "code": "SHIFT_NOT_ON_DAY" })),
                ("GET", "/staff/me/context") => StubResponse::json(200, json!({
                    "role": "owner", "org_name": "Nile Café",
                    "caps": ["hr.schedule.read", "hr.schedule.edit", "hr.schedule.publish"],
                    "branches": [{ "id": BRANCH, "name": "Zamalek", "timezone": "Africa/Cairo" }],
                    "work_shifts": [
                        { "id": "w1", "name": "Morning", "branch_id": BRANCH, "start_time": "08:00:00", "end_time": "12:00:00",
                          "valid_days": [0, 1, 2, 3, 4, 5, 6], "day_times": [] },
                        { "id": "w2", "name": "Evening", "branch_id": BRANCH, "start_time": "16:00:00", "end_time": "00:00:00",
                          "valid_days": [6, 0, 1, 2, 3, 4, 5],
                          "day_times": [{ "day_of_week": 4, "start_time": "16:00:00", "end_time": "01:00:00" }] },
                        { "id": "w3", "name": "Brunch", "branch_id": BRANCH, "start_time": "10:00:00", "end_time": "14:00:00",
                          "valid_days": [6, 0, 1] }
                    ],
                    "people": [
                        { "employee_id": TELLER, "name": "Tasbeeh", "role": "owner", "branch_ids": [BRANCH] },
                        { "employee_id": "P", "name": "Omar", "role": "employee", "branch_ids": [BRANCH] },
                        { "employee_id": "Q", "name": "Ziad", "role": "employee", "branch_ids": [BRANCH] }
                    ],
                    "settings": { "period_start_day": 26 },
                })),
                ("GET", "/staff/roster") => StubResponse::json(200, json!({
                    "published_weeks": [],
                    "shifts": [
                        { "employee_id": "P", "date": day, "work_shift_id": "w1", "start_time": "08:00:00", "end_time": "12:00:00",
                          "crosses_midnight": false, "times_edited": false, "from_override": true, "changed": false },
                        { "employee_id": "P", "date": day, "work_shift_id": "w2", "start_time": "18:00:00", "end_time": "02:00:00",
                          "crosses_midnight": true, "times_edited": true, "from_override": true, "changed": true }
                    ],
                    "open_shifts": [{ "id": "o1", "branch_id": BRANCH, "work_shift_id": "w3", "on_date": day, "status": "open" }],
                    "date_sets": [{ "employee_id": "P", "date": day, "day_off": false },
                                  { "employee_id": "Q", "date": day, "day_off": true }],
                })),
                (_, "/health") => StubResponse::text(200, "ok"),
                ("POST", "/staff/open-shifts/taken/claim") => StubResponse::json(409, json!({ "error": "Conflict: Someone already claimed that shift." })),
                ("POST", "/staff/open-shifts/coded/claim") => StubResponse::json(409, json!({
                    "error": "Someone already claimed that shift.", "code": "ALREADY_CLAIMED" })),
                ("POST", "/staff/schedules/days/move") if r.json()["to_employee_id"] == "Q" => StubResponse::json(409, json!({
                    "error": "Already rostered.", "code": "ALREADY_ROSTERED" })),
                ("POST", "/staff/me/swaps") if r.json()["peer_id"] == "Q" => StubResponse::json(409, json!({
                    "error": "You've already asked for this swap — it's waiting.", "code": "SWAP_EXISTS" })),
                ("GET", p) if p.ends_with("estimate") || p.ends_with("coverage") => StubResponse::json(200, json!({})),
                ("GET", _) => StubResponse::json(200, json!([])),
                ("PUT", "/staff/schedules/days") if r.json()["employee_id"] == "Q" => StubResponse::json(409, json!({
                    "error": "Morning on 2026-10-01 and Brunch on 2026-10-01 overlap.", "code": "SHIFTS_OVERLAP" })),
                _ => StubResponse::json(200, json!({})),
            })
        })
        .await
    }

    fn the_day() -> String {
        // A Thursday, so the Evening's Thursday times apply.
        let mut d = Utc::now().date_naive() + Duration::days(2);
        while d.weekday() != chrono::Weekday::Thu {
            d += Duration::days(1);
        }
        d.to_string()
    }

    /// The board shows what the server resolved (AT-3): each block's days
    /// and weekday times, each shift's own times, crossing midnight, edited,
    /// a date of its own, changed after publish.
    #[tokio::test(flavor = "multi_thread")]
    async fn the_board_carries_block_days_times_and_markers() {
        let day = the_day();
        let stub = roster_stub(day.clone()).await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        core.set_online(true);
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        let tpl = |id: &str| snap["templates"].as_array().unwrap().iter().find(|t| t["id"] == id).unwrap().clone();
        assert_eq!(tpl("w3")["days"], json!([1, 6, 7]), "Sat, Sun, Mon in ISO");
        assert_eq!(tpl("w1")["days"], json!([1, 2, 3, 4, 5, 6, 7]));
        assert_eq!(tpl("w2")["day_times"], json!([{ "day": 4, "start": 960, "end": 60 }]));
        let sh = |tp: &str| {
            snap["shifts"].as_array().unwrap().iter().find(|x| x["id"] == json!(format!("P|{day}|{tp}"))).unwrap().clone()
        };
        let ev = sh("w2");
        assert_eq!((ev["start"].as_i64(), ev["end"].as_i64()), (Some(18 * 60), Some(2 * 60)));
        assert_eq!(ev["next_day"], true);
        assert_eq!(ev["edited"], true);
        assert_eq!(ev["own_day"], true);
        assert_eq!(ev["changed"], true);
        let m = sh("w1");
        assert_eq!((m["start"].as_i64(), m["edited"].as_bool()), (Some(480), Some(false)));
        // An open Brunch reads that day's block times.
        // The dates with their own set, and the one changed to a day off.
        assert_eq!(snap["own_days"], json!([format!("P|{day}"), format!("Q|{day}")]));
        assert_eq!(snap["days_off"], json!([format!("Q|{day}")]));
        let open = snap["shifts"].as_array().unwrap().iter().find(|x| x["id"] == "open|o1").unwrap();
        assert_eq!((open["start"].as_i64(), open["end"].as_i64()), (Some(600), Some(840)));
    }

    /// Every date edit on the board touches one block and sends the rest of
    /// the day with it, the edited times included (SC-5, SC-11).
    #[tokio::test(flavor = "multi_thread")]
    async fn board_edits_keep_the_rest_of_a_split_day() {
        let day = the_day();
        let stub = roster_stub(day.clone()).await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        core.set_online(true);
        core.dawam_snapshot(true).await.unwrap();
        let act = |v: Value| core.dawam_do(v.to_string());
        let last = |method: &str, path: &str| {
            stub.seen.lock().unwrap().iter().rev().find(|r| r.method == method && r.path.starts_with(path)).cloned().expect(path)
        };

        act(json!({ "action": "remove_block", "shift": format!("P|{day}|w1") })).await.unwrap();
        let body = last("PUT", "/staff/schedules/days").json();
        assert_eq!(body["employee_id"], "P");
        assert_eq!(body["shifts"], json!([{ "work_shift_id": "w2", "start_time": "18:00:00", "end_time": "02:00:00" }]));

        act(json!({ "action": "add_block", "emp": "P", "date": day, "tpl": "w3" })).await.unwrap();
        let body = last("PUT", "/staff/schedules/days").json();
        let ids: Vec<&str> = body["shifts"].as_array().unwrap().iter().map(|b| b["work_shift_id"].as_str().unwrap()).collect();
        assert_eq!(ids, ["w1", "w2", "w3"]);

        act(json!({ "action": "set_shifts", "emp": "P", "date": day, "blocks": [] })).await.unwrap();
        assert_eq!(last("PUT", "/staff/schedules/days").json()["shifts"], json!([]), "a day off");

        act(json!({ "action": "set_times", "shift": format!("P|{day}|w1"), "start": 450, "end": 90 })).await.unwrap();
        let body = last("PUT", "/staff/schedules/days/times").json();
        assert_eq!((body["start_time"].as_str(), body["end_time"].as_str()), (Some("07:30:00"), Some("01:30:00")));
        assert_eq!(body["work_shift_id"], "w1");
        act(json!({ "action": "set_times", "shift": format!("P|{day}|w1") })).await.unwrap();
        let body = last("PUT", "/staff/schedules/days/times").json();
        assert!(body["start_time"].is_null() && body["end_time"].is_null(), "back to the block's times");

        act(json!({ "action": "reset_day", "emp": "P", "date": day })).await.unwrap();
        assert_eq!(last("DELETE", "/staff/schedules/days").path, format!("/staff/schedules/days?employee_id=P&on_date={day}"));

        act(json!({ "action": "give_shift", "shift": format!("P|{day}|w2"), "to": "Q" })).await.unwrap();
        assert_eq!(
            last("POST", "/staff/schedules/days/move").json(),
            json!({ "employee_id": "P", "to_employee_id": "Q", "on_date": day, "work_shift_id": "w2" })
        );
        // The board's "assign to someone" is the same move, never a day off.
        act(json!({ "action": "assign", "shift": format!("P|{day}|w1"), "emp": "Q" })).await.unwrap();
        assert_eq!(last("POST", "/staff/schedules/days/move").json()["work_shift_id"], "w1");

        // Dragging the morning to Brunch the same day swaps that block only.
        act(json!({ "action": "move_shift", "shift": format!("P|{day}|w1"), "day": day, "tpl": "w3" })).await.unwrap();
        let body = last("PUT", "/staff/schedules/days").json();
        let ids: Vec<&str> = body["shifts"].as_array().unwrap().iter().map(|b| b["work_shift_id"].as_str().unwrap()).collect();
        assert_eq!(ids, ["w2", "w3"]);

        act(json!({ "action": "cancel_open", "shift": "open|o1" })).await.unwrap();
        assert_eq!(last("POST", "/staff/open-shifts/").path, "/staff/open-shifts/o1/cancel");

        act(json!({ "action": "set_prefs", "emp": "P", "time": "morning", "cant": [5], "note": "Opens" })).await.unwrap();
        let put = last("PUT", "/staff/employees/");
        assert_eq!(put.path, "/staff/employees/P/preferences");
        assert_eq!(put.json()["note"], "Opens");
        act(json!({ "action": "set_prefs", "time": null, "cant": [7] })).await.unwrap();
        assert_eq!(last("PUT", "/staff/me/preferences").json()["cant_work_days"], json!([0]), "ISO Sunday → the server's 0");
    }

    /// E2E roster (the iPad board's drag, S-256): a shift dragged to a day its
    /// block isn't worked on is refused by the server — but the core had
    /// already written its own day without it, so the person lost the shift.
    /// The day it goes to is written first; a refusal there leaves both days
    /// as they were.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_refused_move_to_another_day_loses_nothing() {
        let day = the_day();
        let next = (NaiveDate::parse_from_str(&day, "%Y-%m-%d").unwrap() + Duration::days(1)).to_string();
        let stub = roster_stub_refusing(day.clone(), Some(next.clone())).await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        core.set_online(true);
        core.dawam_snapshot(true).await.unwrap();
        let err = core
            .dawam_do(json!({ "action": "move_shift", "shift": format!("P|{day}|w2"), "day": next, "tpl": "w2" }).to_string())
            .await
            .unwrap_err();
        assert!(matches!(&err, CoreError::Server { code, .. } if code == "SHIFT_NOT_ON_DAY"), "{err:?}");
        let puts: Vec<Value> = stub.requests("/staff/schedules/days").into_iter().filter(|r| r.method == "PUT").map(|r| r.json()).collect();
        assert!(
            !puts.iter().any(|b| b["on_date"] == day.as_str()),
            "the shift's own day must not be rewritten when the move is refused: {puts:?}"
        );
    }

    /// 06 B2: a swap names MY shift as mine. The old app sent them reversed
    /// and every swap was refused; the core now refuses that locally.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_swap_sends_my_shift_as_mine() {
        use crate::testkit::TELLER;
        let day = the_day();
        let stub = roster_stub(day.clone()).await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        core.set_online(true);
        core.dawam_snapshot(true).await.unwrap();
        let mine = format!("{TELLER}|{day}|w1");
        let theirs = format!("P|{day}|w2");
        core.dawam_do(json!({ "action": "ask_swap", "mine": mine, "theirs": theirs }).to_string()).await.unwrap();
        let sent = stub.requests("/staff/me/swaps");
        assert_eq!(
            sent.last().unwrap().json(),
            json!({ "my_date": day, "my_shift_id": "w1", "peer_id": "P", "peer_date": day, "peer_shift_id": "w2" })
        );
        // The request form (`file`) names them the same way: shift = mine.
        core.dawam_do(json!({ "action": "file", "kind": "swap", "shift": mine, "shift2": theirs, "peer": "P" }).to_string()).await.unwrap();
        assert_eq!(stub.requests("/staff/me/swaps").last().unwrap().json()["my_shift_id"], "w1");
        // Reversed: refused here, nothing sent.
        let n = stub.requests("/staff/me/swaps").len();
        let err = core.dawam_do(json!({ "action": "ask_swap", "mine": theirs, "theirs": mine }).to_string()).await.unwrap_err();
        assert!(matches!(err, CoreError::Validation { .. }), "{err:?}");
        assert_eq!(stub.requests("/staff/me/swaps").len(), n);
        // The requester takes a pending swap back.
        core.dawam_do(json!({ "action": "cancel", "req": "w|s1" }).to_string()).await.unwrap();
        assert_eq!(stub.requests("/staff/me/swaps/s1/cancel").len(), 1);
    }

    /// A roster refusal reads in the phone's language, not the server's English.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_roster_refusal_is_worded_for_the_person() {
        let day = the_day();
        let stub = roster_stub(day.clone()).await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        core.set_online(true);
        core.dawam_snapshot(true).await.unwrap();
        for locale in ["en", "ar"] {
            core.set_locale(locale.into());
            let err = core
                .dawam_do(json!({ "action": "add_block", "emp": "Q", "date": day, "tpl": "w3" }).to_string())
                .await
                .unwrap_err();
            match err {
                CoreError::Server { status, code, detail } => {
                    assert_eq!((status, code.as_str()), (409, "SHIFTS_OVERLAP"));
                    assert_eq!(detail, i18n::tr(locale, "staff.err_shifts_overlap"));
                }
                e => panic!("{e:?}"),
            }
        }
    }

    /// E2E money BB2: an advance over the cap reads in the phone's language
    /// with the server's figure as money — never the English sentence on an
    /// Arabic phone.
    #[test]
    fn money_refusals_are_worded_with_the_servers_figures() {
        let body = r#"{"error":"Conflict: ADVANCE_OVER_CAP: that's over the advance cap — at most 1650 EGP more; the owner can approve it.","code":"ADVANCE_OVER_CAP","vars":{"more_piastres":165000,"more_egp":1650}}"#;
        let en = money_words("en", "ADVANCE_OVER_CAP", body);
        let ar = money_words("ar", "ADVANCE_OVER_CAP", body);
        assert!(en.contains("EGP 1,650.00"), "{en}");
        assert!(ar.contains("1,650.00 ج.م"), "{ar}");
        assert!(!ar.contains("advance cap"), "Arabic, not English: {ar}");
        // An unreadable body keeps what the server said.
        assert_eq!(money_words("ar", "ADVANCE_OVER_CAP", "not json"), "not json");
        for c in MONEY_CODES {
            let k = format!("staff.err_{}", c.to_lowercase());
            let (en, ar) = (i18n::tr("en", &k), i18n::tr("ar", &k));
            assert_ne!(en, k, "{k} has no English");
            assert_ne!(ar, en, "{k} has no Arabic");
        }
        // The wire keeps the body for these codes, so the vars survive.
        match crate::net::status_to_error(409, body) {
            CoreError::Server { status, code, detail } => {
                assert_eq!((status, code.as_str()), (409, "ADVANCE_OVER_CAP"));
                assert!(detail.contains("\"vars\""), "{detail}");
            }
            e => panic!("{e:?}"),
        }
    }

    /// Owner decision #7 (D7): a manager never sees the cap (it gives the
    /// salary away). The server's over-cap refusal to a manager carries no
    /// figures (`{over_cap: true}`) and reads "only the owner can approve";
    /// the owner's keeps the figure. The advance cards and the record sheet
    /// read the server's `within_cap` / `advance_within_cap`, never a cap.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_manager_sees_within_or_over_the_cap_never_the_figure() {
        use crate::testkit::StubResponse;
        let manager = r#"{"error":"That's over the advance cap. Only the owner can approve it.","code":"ADVANCE_OVER_CAP","vars":{"over_cap":true}}"#;
        for lang in ["en", "ar"] {
            let w = money_words(lang, "ADVANCE_OVER_CAP", manager);
            assert_eq!(w, i18n::tr(lang, "staff.err_advance_over_cap_no_figures"), "{lang}");
            assert!(!w.contains('{') && !w.chars().any(|c| c.is_ascii_digit()), "no amounts: {w}");
        }
        assert_eq!(money_words("en", "ADVANCE_OVER_CAP", manager), "Over the advance cap: only the owner can approve it.");
        let owner = r#"{"error":"x","code":"ADVANCE_OVER_CAP","vars":{"over_cap":true,"more_piastres":165000,"more_egp":1650}}"#;
        assert!(money_words("en", "ADVANCE_OVER_CAP", owner).contains("EGP 1,650.00"), "the owner keeps the figure");

        let (_stub, core) = cafe(&["hr.attendance.read", "hr.advances.decide"], |m, p, _| match (m, p) {
            ("GET", "/staff/me/context") => Some(StubResponse::json(200, json!({
                "role": "manager", "org_name": "Nile Café", "caps": ["hr.attendance.read", "hr.advances.decide"],
                "branches": [{ "id": crate::testkit::BRANCH, "name": "Zamalek", "timezone": "Africa/Cairo" }],
                "work_shifts": [], "settings": { "period_start_day": 26 },
                "people": [
                    { "employee_id": crate::testkit::TELLER, "name": "Sara", "role": "manager", "branch_ids": [crate::testkit::BRANCH] },
                    { "employee_id": "e4", "name": "Youssef", "role": "employee", "branch_ids": [crate::testkit::BRANCH],
                      "base_salary_piastres": null, "advance_cap_piastres": null, "advance_within_cap": false },
                    { "employee_id": "e5", "name": "Laila", "role": "employee", "branch_ids": [crate::testkit::BRANCH],
                      "base_salary_piastres": null, "advance_cap_piastres": null, "advance_within_cap": true },
                ],
            }))),
            ("GET", "/staff/payroll/advances") => Some(StubResponse::json(200, json!([
                { "id": "v1", "employee_id": "e4", "status": "pending", "amount_piastres": 200000, "installments": 1,
                  "created_at": "2026-09-20T09:00:00Z", "cap_piastres": null, "outstanding_piastres": 150000, "within_cap": false },
                { "id": "v2", "employee_id": "e5", "status": "approved", "amount_piastres": 50000, "installments": 1,
                  "remaining_piastres": 50000, "created_at": "2026-09-01T09:00:00Z", "cap_piastres": null, "within_cap": true },
            ]))),
            _ => None,
        })
        .await;
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        assert_eq!(snap["advance_cap"], json!({}), "no cap figure for a manager");
        assert_eq!(snap["advance_within"], json!({ "e4": false, "e5": true }));
        let v1 = snap["requests"].as_array().unwrap().iter().find(|r| r["id"] == "v|v1").unwrap();
        assert_eq!(v1["within_cap"], json!(false), "the pending advance: over the cap");
        assert_eq!(snap["advances"][0]["within_cap"], json!(true));
        for k in ["staff.outstanding_within_cap", "staff.outstanding_over_cap"] {
            assert_ne!(i18n::tr("ar", k), i18n::tr("en", k), "{k}");
        }
    }

    /// E2E roster (Omar, iPhone): someone claimed the open shift first and the
    /// toast read "Conflict: Someone already claimed that shift." — the
    /// server's error kind in front, English on an Arabic phone. The kind goes;
    /// once the server names it (ALREADY_CLAIMED) it is worded per language.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_claim_lost_to_a_colleague_reads_as_a_sentence() {
        let day = the_day();
        let stub = roster_stub(day.clone()).await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        core.set_online(true);
        core.dawam_snapshot(true).await.unwrap();
        let claim = |id: &str| core.dawam_do(json!({ "action": "claim", "shift": format!("open|{id}") }).to_string());
        match claim("taken").await.unwrap_err() {
            CoreError::Server { detail, .. } => assert_eq!(detail, "Someone already claimed that shift."),
            e => panic!("{e:?}"),
        }
        for locale in ["en", "ar"] {
            core.set_locale(locale.into());
            match claim("coded").await.unwrap_err() {
                CoreError::Server { code, detail, .. } => {
                    assert_eq!(code, "ALREADY_CLAIMED");
                    assert_eq!(detail, i18n::tr(locale, "staff.err_already_claimed"));
                }
                e => panic!("{e:?}"),
            }
        }
    }

    /// E2E roster m2: giving a shift to someone already on it told the
    /// manager "You're already on that shift." It names the person.
    #[tokio::test(flavor = "multi_thread")]
    async fn giving_a_shift_to_someone_on_it_names_them() {
        let day = the_day();
        let stub = roster_stub(day.clone()).await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        core.set_online(true);
        core.dawam_snapshot(true).await.unwrap();
        for locale in ["en", "ar"] {
            core.set_locale(locale.into());
            let err = core
                .dawam_do(json!({ "action": "give_shift", "shift": format!("P|{day}|w1"), "to": "Q" }).to_string())
                .await
                .unwrap_err();
            match err {
                CoreError::Server { code, detail, .. } => {
                    assert_eq!(code, "ALREADY_ROSTERED");
                    assert_eq!(detail, i18n::tr(locale, "staff.err_already_rostered_name").replace("{name}", "Ziad"));
                }
                e => panic!("{e:?}"),
            }
        }
    }

    /// A swap asked twice (backend B-ROTA-7, SWAP_EXISTS) reads in the phone's
    /// language, like the other roster refusals.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_swap_asked_twice_is_worded_for_the_person() {
        use crate::testkit::TELLER;
        let day = the_day();
        let stub = roster_stub(day.clone()).await;
        let core = crate::testkit::online_core(&stub.base, "").await;
        core.set_online(true);
        core.dawam_snapshot(true).await.unwrap();
        for locale in ["en", "ar"] {
            core.set_locale(locale.into());
            let err = core
                .dawam_do(json!({ "action": "ask_swap", "mine": format!("{TELLER}|{day}|w1"), "theirs": format!("Q|{day}|w2") }).to_string())
                .await
                .unwrap_err();
            match err {
                CoreError::Server { code, detail, .. } => {
                    assert_eq!(code, "SWAP_EXISTS");
                    assert_eq!(detail, i18n::tr(locale, "staff.err_swap_exists"));
                }
                e => panic!("{e:?}"),
            }
        }
    }

    /// E2E B1: a refused punch reads in the phone's language with the
    /// server's figures — never "Forbidden: You are 1201 m…" in Arabic.
    #[test]
    fn punch_refusals_are_worded_with_the_servers_figures() {
        let tz: chrono_tz::Tz = "Africa/Cairo".parse().unwrap();
        let fence = r#"{"error":"You are 1201 m from the branch — you must be within 200 m to clock in","code":"OUTSIDE_FENCE","vars":{"distance_m":1201.4,"radius_m":200}}"#;
        assert_eq!(punch_words("en", "OUTSIDE_FENCE", fence, tz), "You're 1201 m from the branch. Clock in within 200 m.");
        assert_eq!(punch_words("ar", "OUTSIDE_FENCE", fence, tz), "إنت على بُعد 1201 م من الفرع. لازم تكون في حدود 200 م عشان تسجّل حضور.");
        let early = r#"{"error":"Too early","code":"CHECKIN_TOO_EARLY","vars":{"shift":"Evening","minutes":120,"opens_at":"2026-09-24T11:00:00Z"}}"#;
        let en = punch_words("en", "CHECKIN_TOO_EARLY", early, tz);
        assert!(en.contains("Evening") && en.contains("02:00 PM") && en.contains("120"), "{en}");
        let ar = punch_words("ar", "CHECKIN_TOO_EARLY", early, tz);
        assert!(ar.contains("Evening") && ar.contains("02:00") && ar.contains("120") && ar.starts_with("لسه"), "{ar}");
        // An unreadable body keeps what the server said.
        assert_eq!(punch_words("ar", "OUTSIDE_FENCE", "not json", tz), "not json");
        for c in PUNCH_CODES {
            let k = format!("staff.err_{}", c.to_lowercase());
            let (en, ar) = (i18n::tr("en", &k), i18n::tr("ar", &k));
            assert_ne!(en, k, "{k} has no English");
            assert_ne!(ar, en, "{k} has no Arabic");
        }
        // The wire keeps the body for these codes, so the vars survive.
        match crate::net::status_to_error(403, fence) {
            CoreError::Server { status, code, detail } => {
                assert_eq!((status, code.as_str()), (403, "OUTSIDE_FENCE"));
                assert!(detail.contains("\"vars\""), "{detail}");
            }
            e => panic!("{e:?}"),
        }
    }

    /// Owner decision #1 (D1): a shift a colleague is covering refuses
    /// every punch for its owner, 409 `SHIFT_COVERED` `{coverer_name}`. The
    /// phone and the manager's punch read it in the person's language, with
    /// the coverer's name, and it is a refusal, never "already held".
    #[test]
    fn a_covered_shift_is_refused_with_the_coverers_name() {
        let tz: chrono_tz::Tz = "Africa/Cairo".parse().unwrap();
        let body = r#"{"error":"Bassem is covering this shift. A manager ends or rejects the cover first.","code":"SHIFT_COVERED","vars":{"coverer_name":"Bassem"}}"#;
        let en = punch_words("en", "SHIFT_COVERED", body, tz);
        let ar = punch_words("ar", "SHIFT_COVERED", body, tz);
        assert_eq!(en, "Bassem is covering this shift. A manager has to end or reject the cover first.");
        assert!(ar.contains("Bassem") && !ar.contains("covering"), "{ar}");
        match crate::net::status_to_error(409, body) {
            CoreError::Server { status, code, detail } => {
                assert_eq!((status, code.as_str()), (409, "SHIFT_COVERED"));
                assert!(detail.contains("\"vars\""), "the coverer's name survives: {detail}");
            }
            e => panic!("{e:?}"),
        }
        let first_try = store::OutboxItem {
            seq: 1, id: "p".into(), op_type: "dawam_punch_for".into(), idempotency_key: "p".into(), payload: "{}".into(),
            event_at: String::new(), status: "inflight".into(), attempts: 0, last_error: None, server_id: None,
            depends_on_seq: None, next_attempt_at: 0, user_id: None, clock_offset_ms: None, till_id: None,
            device_id: None, entity_type: None, entity_id: None,
        };
        assert!(!conflict_means_held(&first_try, "SHIFT_COVERED"), "a refusal, not a silent done");
    }

    #[test]
    fn every_roster_refusal_and_notice_is_in_both_languages() {
        let keys = ROSTER_CODES.iter().map(|c| format!("staff.err_{}", c.to_lowercase())).chain(
            [
                "staff.n_open_shift_cancelled", "staff.n_swap_cancelled", "staff.n_prefs_changed", "staff.n_learning_frozen",
                "staff.n_learning_resumed", "staff.n_fairness_ready", "staff.n_fairness_flagged", "staff.edited",
                "staff.ends_next_day", "staff.back_to_pattern", "staff.move_to", "staff.cancel_open_shift", "staff.cancel_swap",
            ]
            .map(str::to_string),
        );
        for k in keys {
            let (en, ar) = (i18n::tr("en", &k), i18n::tr("ar", &k));
            assert_ne!(en, k, "{k} has no English");
            assert_ne!(ar, en, "{k} has no Arabic");
        }
        // The server's notice arguments fill in.
        let t = notice_text("en", "staff.n_fairness_flagged", &json!({ "branch": "Arkan", "month": "2026-08-01", "gap": 35 }));
        assert!(t.contains("Arkan") && t.contains("35"), "{t}");
    }

    #[test]
    fn a_fairness_notice_names_its_month() {
        // The server sends the audited month as a date (`2026-08-01`); the
        // inbox said "(2026-08-01)" in both languages (E2E posnotif N-047).
        let en = notice_text("en", "staff.n_fairness_ready", &json!({ "branch": "Arkan", "month": "2026-08-01" }));
        assert!(en.contains("(Aug 2026)") && !en.contains("2026-08-01"), "{en}");
        let ar = notice_text("ar", "staff.n_fairness_flagged", &json!({ "branch": "Arkan", "month": "2026-08-01", "gap": 33 }));
        let aug = format!("({} 2026)", i18n::tr("ar", "staff.month_8"));
        assert!(ar.contains(&aug) && !ar.contains("2026-08-01"), "{ar}");
    }

    // ── requests and rules (phase B): the wire the server now expects ──

    /// A one-branch café as `role` sees it (`caps` decide the manager side),
    /// with a morning (`w1`) and an evening (`w2`) shift at the branch. `extra`
    /// answers first; everything else is empty.
    async fn cafe(
        caps: &'static [&'static str],
        extra: impl Fn(&str, &str, &crate::testkit::SeenRequest) -> Option<crate::testkit::StubResponse> + Send + Sync + 'static,
    ) -> (crate::testkit::Stub, std::sync::Arc<MadarCore>) {
        use crate::testkit::{online_core, Stub, StubResponse, BRANCH, TELLER};
        let stub = Stub::start(move |r| {
            let path = r.path.split('?').next().unwrap_or_default().to_string();
            if let Some(x) = extra(r.method.as_str(), &path, r) {
                return Some(x);
            }
            Some(match path.as_str() {
                "/staff/me/context" => StubResponse::json(200, json!({
                    "role": if caps.is_empty() { "employee" } else { "manager" }, "org_name": "Nile Café", "caps": caps,
                    "branches": [{ "id": BRANCH, "name": "Zamalek", "timezone": "Africa/Cairo" }],
                    "work_shifts": [
                        { "id": "w1", "name": "Morning", "branch_id": BRANCH, "start_time": "08:00:00", "end_time": "12:00:00" },
                        { "id": "w2", "name": "Evening", "branch_id": BRANCH, "start_time": "18:00:00", "end_time": "23:00:00" }
                    ],
                    "settings": { "period_start_day": 26 },
                    "people": [
                        { "employee_id": TELLER, "name": "Sara", "role": if caps.is_empty() { "employee" } else { "manager" }, "branch_ids": [BRANCH] },
                        { "employee_id": "e4", "name": "Youssef", "role": "employee", "branch_ids": [BRANCH] },
                        { "employee_id": "m2", "name": "Omar", "role": "manager", "branch_ids": [BRANCH] }
                    ],
                })),
                "/health" => StubResponse::text(200, "ok"),
                "/staff/payroll/current" => StubResponse::json(404, json!({ "error": "no period" })),
                p if p.ends_with("estimate") || p.contains("/coverage") => StubResponse::json(200, json!({})),
                _ => StubResponse::json(200, json!([])),
            })
        })
        .await;
        let core = online_core(&stub.base, "").await;
        core.set_online(true);
        (stub, core)
    }

    fn today_cairo() -> NaiveDate {
        Utc::now().with_timezone(&chrono_tz::Africa::Cairo).date_naive()
    }

    fn posted(stub: &crate::testkit::Stub, path: &str) -> Value {
        stub.seen.lock().unwrap().iter().rev().find(|r| r.method != "GET" && r.path.starts_with(path)).expect(path).json()
    }

    /// B-ONB-1: nobody is absent before the business saved its rules. The
    /// read-ahead marked a missed shift absent from before the first save,
    /// so the app showed Youssef 6 absences where the server had 5. A shift
    /// that started before `rules_saved_at` is never absent; while that is
    /// null (or `rules_saved` is false) none is. A server that doesn't send
    /// the field keeps the plain rule.
    #[tokio::test(flavor = "multi_thread")]
    async fn no_shift_is_absent_before_the_rules_were_saved() {
        use crate::testkit::{online_core, Stub, StubResponse, BRANCH, TELLER};
        use std::sync::{Arc, Mutex};
        let today = today_cairo();
        let (before, after) = ((today - Duration::days(3)).to_string(), (today - Duration::days(1)).to_string());
        let saved_at = format!("{}T10:00:00+03:00", today - Duration::days(2));
        let settings = Arc::new(Mutex::new(json!({ "period_start_day": 26, "rules_saved": true, "rules_saved_at": saved_at })));
        let answer = settings.clone();
        let (b, a) = (before.clone(), after.clone());
        let stub = Stub::start(move |r| {
            let path = r.path.split('?').next().unwrap_or_default();
            Some(match path {
                "/staff/me/context" => StubResponse::json(200, json!({
                    "role": "employee", "org_name": "Nile Café", "caps": [],
                    "branches": [{ "id": BRANCH, "name": "Zamalek", "timezone": "Africa/Cairo" }],
                    "work_shifts": [{ "id": "w1", "name": "Morning", "branch_id": BRANCH, "start_time": "08:00:00", "end_time": "12:00:00" }],
                    "people": [{ "employee_id": TELLER, "name": "Youssef", "role": "employee", "branch_ids": [BRANCH] }],
                    "settings": answer.lock().unwrap().clone(),
                })),
                "/staff/me/roster" => StubResponse::json(200, json!({
                    "shifts": [{ "employee_id": TELLER, "date": b, "work_shift_id": "w1" },
                               { "employee_id": TELLER, "date": a, "work_shift_id": "w1" }],
                    "team": [], "open_shifts": [], "swaps": [], "unpublished_weeks": [],
                })),
                "/health" => StubResponse::text(200, "ok"),
                p if p.ends_with("estimate") => StubResponse::json(200, json!({})),
                _ => StubResponse::json(200, json!([])),
            })
        })
        .await;
        let core = online_core(&stub.base, "").await;
        core.set_online(true);
        let absent = |snap: &Value, d: &str| {
            snap["shifts"].as_array().unwrap().iter().find(|x| x["date"] == d).map(|x| x["absent"].clone()).unwrap()
        };
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        assert_eq!(absent(&snap, &before), json!(false), "before the rules were saved: not absent");
        assert_eq!(absent(&snap, &after), json!(true), "after: absent");

        *settings.lock().unwrap() = json!({ "period_start_day": 26, "rules_saved": false, "rules_saved_at": null });
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        assert_eq!((absent(&snap, &before), absent(&snap, &after)), (json!(false), json!(false)), "rules never saved: nobody is absent");
        *settings.lock().unwrap() = json!({ "period_start_day": 26, "rules_saved": true, "rules_saved_at": null });
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        assert_eq!((absent(&snap, &before), absent(&snap, &after)), (json!(false), json!(false)), "no save time yet: nobody is absent");
        *settings.lock().unwrap() = json!({ "period_start_day": 26, "rules_saved": true });
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        assert_eq!((absent(&snap, &before), absent(&snap, &after)), (json!(true), json!(true)), "an older server: the plain rule");
    }

    /// Minor #13: signing in while one's account or the whole business is
    /// suspended says why, in the phone's language: "Your account isn't
    /// active. Ask your manager." or "This business is paused."
    #[tokio::test]
    async fn a_suspended_sign_in_says_why() {
        let core = crate::testkit::offline_core("http://127.0.0.1:1", "").await;
        for lang in ["en", "ar"] {
            core.set_locale(lang.into());
            for (body, key) in [
                (r#"{"error":"This organisation is suspended","code":"ORG_SUSPENDED"}"#, "staff.err_org_suspended"),
                (r#"{"error":"Employee inactive","code":"EMPLOYEE_INACTIVE"}"#, "staff.err_employee_inactive"),
            ] {
                match core.staff_error(crate::net::status_to_error(403, body)) {
                    CoreError::Forbidden { action, .. } => assert_eq!(action, i18n::tr(lang, key), "{lang}"),
                    e => panic!("{e:?}"),
                }
            }
        }
        assert_ne!(i18n::tr("en", "staff.err_org_suspended"), i18n::tr("ar", "staff.err_org_suspended"));

        // Asked at the code request (the server refuses there, so no WhatsApp
        // is sent), and at the code check.
        let stub = crate::testkit::Stub::start(|r| {
            r.path.starts_with("/auth/staff/otp/").then(|| {
                crate::testkit::StubResponse::json(403, json!({ "error": "This organisation is suspended", "code": "ORG_SUSPENDED" }))
            })
        })
        .await;
        let core = crate::testkit::offline_core(&stub.base, "").await;
        core.set_locale("ar".into());
        let said = |e: CoreError| match e {
            CoreError::Forbidden { action, .. } => action,
            e => panic!("{e:?}"),
        };
        assert_eq!(said(core.staff_otp_request("01001234567".into()).await.unwrap_err()), i18n::tr("ar", "staff.err_org_suspended"));
        let verify = core.staff_otp_verify("01001234567".into(), "123456".into(), None, None, None).await.unwrap_err();
        assert_eq!(said(verify), i18n::tr("ar", "staff.err_org_suspended"));
    }

    /// Owner decision #3 (D3): public holidays are the owner's, like the
    /// rules. The actions show only for someone holding `hr.rules.edit` at
    /// every branch (the server's `caps_everywhere`); a server that doesn't
    /// send that list yet: the owner. A manager's tap the server refuses
    /// (403 OWNER_ONLY) reads in the phone's language.
    #[tokio::test(flavor = "multi_thread")]
    async fn holidays_are_decided_by_the_owner_only() {
        let owner = json!({ "role": "owner", "caps": ["hr.rules.edit"] });
        let manager = json!({ "role": "manager", "caps": ["hr.rules.edit", "hr.schedule.edit"] });
        assert!(decides_holidays(&owner), "an older server: the owner decides");
        assert!(!decides_holidays(&manager), "an older server: a manager doesn't, whatever his caps at one branch");
        let everywhere = json!({ "role": "manager", "caps_everywhere": ["hr.rules.edit"] });
        assert!(decides_holidays(&everywhere), "the rules right held at every branch decides");
        let one_branch = json!({ "role": "owner", "caps": ["hr.rules.edit"], "caps_everywhere": [] });
        assert!(!decides_holidays(&one_branch), "the server's list wins over the role");

        let (_stub, core) = cafe(&["hr.schedule.read", "hr.schedule.edit"], |m, p, _| {
            (m == "PUT" && p.starts_with("/staff/holidays/")).then(|| {
                crate::testkit::StubResponse::json(403, json!({ "error": "Only the owner decides public holidays.", "code": "OWNER_ONLY" }))
            })
        })
        .await;
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        assert_eq!(snap["decides_holidays"], json!(false), "a manager sees holidays read-only");
        for lang in ["en", "ar"] {
            core.set_locale(lang.into());
            let err = core
                .dawam_do(json!({ "action": "decide_holiday", "date": "2026-10-06", "decision": "holiday" }).to_string())
                .await
                .unwrap_err();
            match err {
                CoreError::Forbidden { resource, action } => {
                    assert_eq!(resource, "OWNER_ONLY");
                    assert_eq!(action, i18n::tr(lang, "staff.err_owner_only"), "{lang}");
                }
                e => panic!("{e:?}"),
            }
        }
        assert_ne!(i18n::tr("en", "staff.err_owner_only"), i18n::tr("ar", "staff.err_owner_only"));
    }

    /// RQ-9 (§3): a correction names the person's OWN record of the shift. A
    /// colleague's cover of it is theirs, and the server refuses it (404). A
    /// shift nobody clocked has no record: the correction names the shift.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_correction_names_my_own_record_never_a_cover_of_my_shift() {
        use crate::testkit::{StubResponse, BRANCH, TELLER};
        let d = today_cairo().to_string();
        let day = d.clone();
        let (stub, core) = cafe(&[], move |m, p, _| match (m, p) {
            ("GET", "/staff/me/roster") => Some(StubResponse::json(200, json!({ "shifts": [
                { "employee_id": TELLER, "date": day, "work_shift_id": "w1" },
                { "employee_id": TELLER, "date": day, "work_shift_id": "w2" }
            ], "team": [], "unpublished_weeks": [] }))),
            // The cover row comes first, as the old match would have taken it.
            ("GET", "/staff/me/attendance") => Some(StubResponse::json(200, json!([
                { "id": "cover", "employee_id": "e4", "covered_employee_id": TELLER, "business_date": day, "work_shift_id": "w1", "branch_id": BRANCH, "status": "present" },
                { "id": "mine", "employee_id": TELLER, "business_date": day, "work_shift_id": "w1", "branch_id": BRANCH, "status": "present" }
            ]))),
            ("POST", "/staff/me/requests") => Some(StubResponse::json(201, json!({ "id": "q9", "status": "pending" }))),
            _ => None,
        })
        .await;
        core.dawam_snapshot(true).await.unwrap();
        let shift = format!("{TELLER}|{d}|w1");
        let act = json!({ "action": "file", "kind": "correction", "from": d, "shift": shift, "time2": 12 * 60 + 30 }).to_string();
        core.dawam_do(act).await.unwrap();
        let body = posted(&stub, "/staff/me/requests");
        assert_eq!(body["attendance_record_id"], "mine");
        // Only the time that changed goes (§3): the check-in is left as it is.
        assert_eq!(body["to_time"], "12:30");
        assert!(body.get("from_time").is_none(), "an unchanged check-in is not proposed: {body}");
        assert!(body.get("work_shift_id").is_none(), "a record, not the shift, when there is one");
        // The evening shift has no record: the shift goes instead.
        let evening = format!("{TELLER}|{d}|w2");
        let act = json!({ "action": "file", "kind": "correction", "from": d, "shift": evening, "time": 18 * 60, "time2": 23 * 60 }).to_string();
        core.dawam_do(act).await.unwrap();
        let body = posted(&stub, "/staff/me/requests");
        assert_eq!(body["work_shift_id"], "w2");
        assert!(body.get("attendance_record_id").is_none(), "never a record of another shift: {body}");
        // A correction that changes nothing never leaves the phone.
        let act = json!({ "action": "file", "kind": "correction", "from": d, "shift": shift }).to_string();
        let err = core.dawam_do(act).await.unwrap_err();
        assert!(format!("{err:?}").contains(&i18n::tr("en", "staff.change_a_time_first")), "{err:?}");
    }

    /// The cover proof (M-CV-1, M-CV-2): the coverer's own cover row says
    /// its status (a rejected cover must not read like a confirmed one), and
    /// it spans the cover's own window, the record's scheduled instants,
    /// never the block's default day (Home showed "8h 00m" for a 20-minute
    /// cover when the covered shift was not in the coverer's picture).
    #[tokio::test(flavor = "multi_thread")]
    async fn a_cover_row_has_its_own_status_and_window() {
        use crate::testkit::{StubResponse, BRANCH, TELLER};
        let d = today_cairo().to_string();
        for status in ["pending", "confirmed", "rejected"] {
            // I covered e4's shift; e4's roster is not in my picture.
            let cov = json!({ "id": "cov", "employee_id": TELLER, "covered_employee_id": "e4", "business_date": d, "work_shift_id": "w1",
                "branch_id": BRANCH, "status": "present", "cover_status": status, "check_in_method": "cover",
                "scheduled_start_at": format!("{d}T07:40:00Z"), "scheduled_end_at": format!("{d}T08:00:00Z"),
                "check_in_at": format!("{d}T07:41:00Z") });
            let (_stub, core) = cafe(&[], move |m, p, _| match (m, p) {
                ("GET", "/staff/me/attendance") => Some(StubResponse::json(200, json!([cov.clone()]))),
                _ => None,
            })
            .await;
            let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
            let cover = snap["shifts"].as_array().unwrap().iter().find(|x| x["id"] == "cover|cov").cloned().expect("my cover row");
            assert_eq!(cover["cover_status"], json!(status), "the cover's own status");
            // 07:40Z–08:00Z is 10:40–11:00 in Cairo: 20 minutes, not Morning's 4 h.
            assert_eq!((cover["start"].clone(), cover["end"].clone()), (json!(640), json!(660)), "{status}: the cover's own window");
        }
        assert_ne!(i18n::tr("en", "staff.cover_not_confirmed"), i18n::tr("ar", "staff.cover_not_confirmed"));
    }

    /// E2E (posnotif, requests, clocking): a cover record shared the covered
    /// person's shift id, so whichever row the server listed last won —
    /// the owner's Timesheet showed the coverer's punches as theirs and lost
    /// the absence, a confirmed cover never reached the coverer's Timesheet
    /// (CV-7), and a REJECTED cover still took the shift off the owner's Home
    /// ("No shift today"). Now a cover is its own row (`cover|<record>`, the
    /// coverer's, naming whose shift it covered); the owner's shift comes
    /// only from the owner's own record, marked covered while the cover is
    /// pending or confirmed; a rejected cover leaves the owner's shift alone.
    /// The same in either list order.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_cover_is_its_own_row_and_never_takes_the_owners_record() {
        use crate::testkit::{StubResponse, BRANCH, TELLER};
        let d = today_cairo().to_string();
        let shift_of = |snap: &Value, id: &str| snap["shifts"].as_array().unwrap().iter().find(|x| x["id"] == json!(id)).cloned();
        let in_my_now = |snap: &Value, id: &str| snap["my_now"].as_array().unwrap().iter().any(|x| x == &json!(id));
        let mine = format!("{TELLER}|{d}|w1");
        for status in ["pending", "confirmed", "rejected"] {
            for cover_first in [true, false] {
                let tag = format!("{status}, cover {}", if cover_first { "first" } else { "last" });
                // I am the owner: absent (the sweep), and e4 covered my shift.
                let own = json!({ "id": "own", "employee_id": TELLER, "business_date": d, "work_shift_id": "w1", "branch_id": BRANCH, "status": "absent" });
                let cov = json!({ "id": "cov", "employee_id": "e4", "covered_employee_id": TELLER, "business_date": d, "work_shift_id": "w1",
                    "branch_id": BRANCH, "status": "present", "cover_status": status, "check_in_method": "cover",
                    "check_in_at": format!("{d}T06:10:00Z"), "check_out_at": format!("{d}T08:55:00Z") });
                let rows = if cover_first { json!([cov, own]) } else { json!([own, cov]) };
                let day = d.clone();
                let (_stub, core) = cafe(&[], move |m, p, _| match (m, p) {
                    ("GET", "/staff/me/roster") => Some(StubResponse::json(200, json!({ "shifts": [
                        { "employee_id": TELLER, "date": day, "work_shift_id": "w1" }
                    ], "team": [], "unpublished_weeks": [] }))),
                    ("GET", "/staff/me/attendance") => Some(StubResponse::json(200, rows.clone())),
                    _ => None,
                })
                .await;
                let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
                let owner = shift_of(&snap, &mine).unwrap_or_else(|| panic!("{tag}: my shift is there"));
                assert_eq!(owner["in_at"], Value::Null, "{tag}: never the coverer's punches on my shift");
                assert_eq!(owner["out_at"], Value::Null, "{tag}");
                assert_eq!(owner["absent"], json!(true), "{tag}: I stay absent (CV-6)");
                let cover = shift_of(&snap, "cover|cov").unwrap_or_else(|| panic!("{tag}: the cover is its own row"));
                assert_eq!(cover["emp"], json!("e4"), "{tag}: the coverer's row");
                assert_eq!(cover["cover_of"], json!(TELLER), "{tag}: naming whose shift it covered");
                assert!(cover["in_at"].is_string() && cover["out_at"].is_string(), "{tag}: with the cover's punches");
                assert_eq!(cover["absent"], json!(false), "{tag}");
                if status == "rejected" {
                    assert_eq!(owner["cover_by"], Value::Null, "{tag}: a rejected cover takes nothing");
                    assert!(in_my_now(&snap, &mine), "{tag}: the shift stays on my Home (Missed, not 'No shift today')");
                } else {
                    assert_eq!(owner["cover_by"], json!("e4"), "{tag}: marked covered");
                    assert!(!in_my_now(&snap, &mine), "{tag}: a covered shift leaves my Home, as before");
                }
                assert!(!in_my_now(&snap, "cover|cov"), "{tag}: someone else's cover is not mine");
                let req = snap["requests"].as_array().unwrap().iter().find(|r| r["id"] == json!("c|cov")).cloned();
                if status == "pending" {
                    assert_eq!(req.expect("a pending cover to confirm")["shift"], json!("cover|cov"), "{tag}: the request names the cover");
                } else {
                    assert!(req.is_none(), "{tag}: only a pending cover waits");
                }
            }
        }

        // I am the coverer, still on the cover: it is my row, my Home card,
        // my running shift; the covered person's shift is not mine.
        let d2 = d.clone();
        let (_stub, core) = cafe(&[], move |m, p, _| match (m, p) {
            ("GET", "/staff/me/roster") => Some(StubResponse::json(200, json!({ "shifts": [], "team": [], "unpublished_weeks": [] }))),
            ("GET", "/staff/me/attendance") => Some(StubResponse::json(200, json!([
                { "id": "cov2", "employee_id": TELLER, "covered_employee_id": "e4", "business_date": d2, "work_shift_id": "w2",
                  "branch_id": BRANCH, "status": "present", "cover_status": "pending", "check_in_method": "cover",
                  "check_in_at": (Utc::now() - Duration::minutes(20)).to_rfc3339() }
            ]))),
            _ => None,
        })
        .await;
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        assert_eq!(snap["active_shift"], json!("cover|cov2"), "my running shift is the cover");
        assert!(in_my_now(&snap, "cover|cov2"), "the cover is on my Home");
        assert!(!in_my_now(&snap, &format!("e4|{d}|w2")), "the covered person's shift is not mine");
        let cover = shift_of(&snap, "cover|cov2").expect("my cover row");
        assert_eq!((cover["emp"].clone(), cover["cover_of"].clone(), cover["cover_by"].clone()), (json!(TELLER), json!("e4"), Value::Null));
    }

    /// A cover queued offline is my own running row at once (APP-8), and the
    /// covered shift reads covered; it never takes that shift's place.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_queued_cover_is_my_own_row_at_once() {
        use crate::testkit::{StubResponse, TELLER};
        let d = today_cairo().to_string();
        let day = d.clone();
        let (_stub, core) = cafe(&[], move |m, p, _| match (m, p) {
            ("GET", "/staff/me/roster") => Some(StubResponse::json(200, json!({ "shifts": [
                { "employee_id": "e4", "date": day, "work_shift_id": "w2" }
            ], "team": [], "unpublished_weeks": [] }))),
            // The signal is gone when the cover goes out.
            ("POST", "/staff/me/cover") => Some(StubResponse::hangup()),
            _ => None,
        })
        .await;
        core.dawam_snapshot(true).await.unwrap();
        let theirs = format!("e4|{d}|w2");
        let fix = DawamFix { latitude: 30.0609, longitude: 31.2197, accuracy: Some(8.0), ..Default::default() };
        let snap: Value = serde_json::from_str(&core.dawam_do(json!({ "action": "cover", "shift": theirs, "fix": fix }).to_string()).await.unwrap()).unwrap();
        let active = snap["active_shift"].as_str().expect("the queued cover runs").to_string();
        assert!(active.starts_with("cover|"), "{active}");
        let row = snap["shifts"].as_array().unwrap().iter().find(|x| x["id"] == json!(active)).unwrap();
        assert_eq!((row["emp"].clone(), row["cover_of"].clone(), row["queued"].clone()), (json!(TELLER), json!("e4"), json!(true)));
        assert!(row["in_at"].is_string());
        let covered = snap["shifts"].as_array().unwrap().iter().find(|x| x["id"] == json!(theirs)).unwrap();
        assert_eq!((covered["cover_by"].clone(), covered["in_at"].clone()), (json!(TELLER), Value::Null), "theirs reads covered, never my punch");
        assert!(!snap["my_now"].as_array().unwrap().iter().any(|x| x == &json!(theirs)));
    }

    /// RQ-8 and B4: a half day says which half, a timed request names its
    /// shift (split days), only a correction carries a record, and the
    /// server's answer to the filing comes back for the screen (RQ-5).
    /// E2E money CB1/CB6: a pay line says what the server made of it (over
    /// the adder's limit it waits for the owner, AD-5 — never "Added"), and
    /// stopping an every-month line carries its reason (AD-3, AD-9: the
    /// server refuses a stop without one).
    #[tokio::test(flavor = "multi_thread")]
    async fn a_pay_line_returns_the_servers_status_and_a_stop_carries_its_reason() {
        use crate::testkit::StubResponse;
        let (stub, core) = cafe(&["hr.adjustments.create", "hr.deductions.create"], move |m, p, r| match (m, p) {
            ("POST", "/staff/adjustments") => Some(StubResponse::json(201, json!({
                "id": "d1", "kind": r.json()["kind"], "status": if r.json()["amount_piastres"] == json!(100001) { "pending" } else { "approved" },
            }))),
            ("POST", "/staff/adjustments/bonus/m1/stop") => Some(StubResponse::json(200, json!({ "id": "m1" }))),
            _ => None,
        })
        .await;
        core.dawam_snapshot(true).await.unwrap();

        let act = json!({ "action": "add_adjustment", "emp": "e1", "bonus": false, "amount": 100001, "reason": "cups", "recurring": false }).to_string();
        let snap: Value = serde_json::from_str(&core.dawam_do(act).await.unwrap()).unwrap();
        assert_eq!(snap["filed"], json!({ "id": "a|deduction|d1", "status": "pending", "to_owner": false }), "over the limit: waits");
        let act = json!({ "action": "add_adjustment", "emp": "e1", "bonus": true, "amount": 5000, "reason": "week", "recurring": false }).to_string();
        let snap: Value = serde_json::from_str(&core.dawam_do(act).await.unwrap()).unwrap();
        assert_eq!(snap["filed"]["status"], "approved");
        assert_eq!(snap["filed"]["id"], "a|bonus|d1");

        let act = json!({ "action": "stop_adj", "adj": "a|bonus|m1", "reason": "moved to a meal card" }).to_string();
        core.dawam_do(act).await.unwrap();
        assert_eq!(posted(&stub, "/staff/adjustments/bonus/m1/stop"), json!({ "reason": "moved to a meal card" }));
    }

    /// Owner decision #9 (D9): a salary can be "not set" (null), never a
    /// silent 0. The snapshot tells "not set" (`salary_set` false) from
    /// "hidden from me" (set, no figure); the payroll preview flags who has
    /// none and how many, and approving while someone has none is refused
    /// (409 SALARY_MISSING {names}) in the owner's language, naming them.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_salary_not_set_is_flagged_and_blocks_approval() {
        use crate::testkit::{StubResponse, BRANCH, TELLER};
        let (_stub, core) = cafe(&["hr.attendance.read", "hr.payroll.run"], |m, p, _| match (m, p) {
            ("GET", "/staff/me/context") => Some(StubResponse::json(200, json!({
                "role": "owner", "org_name": "Nile Café", "caps": ["hr.attendance.read", "hr.payroll.run"],
                "branches": [{ "id": BRANCH, "name": "Zamalek", "timezone": "Africa/Cairo" }],
                "work_shifts": [], "settings": { "period_start_day": 26 },
                "people": [
                    { "employee_id": TELLER, "name": "Hana", "role": "owner", "branch_ids": [BRANCH], "base_salary_piastres": 0, "salary_set": true },
                    { "employee_id": "e4", "name": "Youssef", "role": "employee", "branch_ids": [BRANCH], "base_salary_piastres": null, "salary_set": false },
                    { "employee_id": "e5", "name": "Laila", "role": "employee", "branch_ids": [BRANCH], "base_salary_piastres": 850000, "salary_set": true },
                    { "employee_id": "e6", "name": "Omar", "role": "manager", "branch_ids": [BRANCH], "base_salary_piastres": null, "salary_set": true },
                ],
            }))),
            ("GET", "/staff/payroll/current") => Some(StubResponse::json(200, json!({
                "period": { "id": "p9", "start_date": "2026-08-26", "end_date": "2026-09-25", "status": "draft" },
                "missing_salary_count": 1,
                "totals": { "missing_salary_count": 1 },
                "preview": [
                    { "employee_id": "e4", "base_piastres": 0, "net_piastres": 0, "salary_missing": true, "breakdown": {} },
                    { "employee_id": "e5", "base_piastres": 850000, "net_piastres": 850000, "salary_missing": false, "breakdown": {} },
                ],
                "payslips": [], "history": [],
            }))),
            ("POST", "/staff/payroll/periods/p9/generate") => Some(StubResponse::json(409, json!({
                "error": "Set a salary for Youssef first.", "code": "SALARY_MISSING",
                "vars": { "names": ["Youssef", "Mona"], "employee_ids": ["e4", "e7"] } }))),
            _ => None,
        })
        .await;
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        let person = |id: &str| snap["people"].as_array().unwrap().iter().find(|p| p["id"] == id).cloned().unwrap();
        assert_eq!((person("e4")["salary"].clone(), person("e4")["salary_set"].clone()), (Value::Null, json!(false)), "not set");
        assert_eq!((person("e6")["salary"].clone(), person("e6")["salary_set"].clone()), (Value::Null, json!(true)), "hidden from me");
        assert_eq!(person("e5")["salary"], json!(850000));
        assert_eq!(person(crate::testkit::TELLER)["salary"], json!(0), "a real 0 stays 0");
        assert_eq!(snap["missing_salary_count"], json!(1));
        let slip = |id: &str| snap["slips"].as_array().unwrap().iter().find(|x| x["emp"] == id).cloned().unwrap();
        assert_eq!((slip("e4")["salary_missing"].clone(), slip("e5")["salary_missing"].clone()), (json!(true), json!(false)));

        for lang in ["en", "ar"] {
            core.set_locale(lang.into());
            match core.dawam_do(json!({ "action": "approve_payroll" }).to_string()).await.unwrap_err() {
                CoreError::Server { code, detail, .. } => {
                    assert_eq!(code, "SALARY_MISSING");
                    let sep = if lang == "ar" { "، " } else { ", " };
                    assert!(detail.contains(&format!("Youssef{sep}Mona")), "{lang}: names them: {detail}");
                    assert!(!detail.contains('[') && !detail.contains('{'), "{detail}");
                    assert_eq!(detail, i18n::tr(lang, "staff.err_salary_missing").replace("{names}", &format!("Youssef{sep}Mona")));
                }
                e => panic!("{e:?}"),
            }
        }
        let args = json!({ "name": "Youssef", "employee_id": "e4", "by": "Omar" });
        assert_eq!(
            notice_text("en", "staff.n_salary_missing", &args),
            "Omar added Youssef without a salary. Set it before approving payroll."
        );
        let n = notice_text("ar", "staff.n_salary_missing", &args);
        assert!(n.contains("Youssef") && n.contains("Omar") && !n.contains('{'), "{n}");
        for k in ["staff.payroll_salary_missing", "staff.salary_not_set", "staff.approve_blocked_salary_missing"] {
            assert_ne!(i18n::tr("ar", k), i18n::tr("en", k), "{k}");
        }
    }

    /// Minor #26 (RU-13): approving an open-shift claim that makes a long
    /// day warns, never blocks. The server answers the decision with the
    /// labour limits the day now breaks; the core hands them back with the
    /// picture, as the board's warnings are (key + figures).
    #[tokio::test(flavor = "multi_thread")]
    async fn approving_a_claim_returns_the_limits_it_breaks() {
        use crate::testkit::StubResponse;
        let day = (today_cairo() + Duration::days(2)).to_string();
        let d = day.clone();
        let (_stub, core) = cafe(&["hr.attendance.read", "hr.schedule.edit"], move |m, p, _| match (m, p) {
            ("PATCH", "/staff/open-shifts/o1/decision") => Some(StubResponse::json(200, json!({ "status": "approved", "warnings": [
                { "employee_id": "e4", "date": d, "kind": "day_hours", "minutes": 660, "limit_minutes": 480 },
                { "employee_id": "e4", "date": d, "kind": "presence", "minutes": 780, "limit_minutes": 600 },
            ] }))),
            ("PATCH", "/staff/open-shifts/o2/decision") => Some(StubResponse::text(204, "")),
            _ => None,
        })
        .await;
        core.dawam_snapshot(true).await.unwrap();
        let snap: Value = serde_json::from_str(&core.dawam_do(json!({ "action": "decide", "req": "o|o1", "approve": true }).to_string()).await.unwrap()).unwrap();
        assert_eq!(snap["filed"]["id"], "o|o1");
        assert_eq!(snap["filed"]["warnings"], json!([
            ["staff.warn_day_hours", { "date": day, "hours": "8", "worked": "11" }],
            ["staff.warn_presence", { "date": day, "hours": "10", "worked": "13" }],
        ]));
        let snap: Value = serde_json::from_str(&core.dawam_do(json!({ "action": "decide", "req": "o|o2", "approve": true }).to_string()).await.unwrap()).unwrap();
        assert_eq!(snap.get("filed"), None, "an older server's 204 says nothing");
    }

    /// Minor #33: a deduction from a flag over the manager's deduction limit
    /// waits for the owner, and the manager is told so, as the bonus and
    /// deduction sheet does (the limit is the server's, "above it, the
    /// deduction waits").
    #[tokio::test(flavor = "multi_thread")]
    async fn a_flag_deduction_over_my_limit_waits_for_the_owner() {
        use crate::testkit::{StubResponse, BRANCH, TELLER};
        let (_stub, core) = cafe(&["hr.attendance.read", "hr.deductions.create"], |m, p, _| match (m, p) {
            ("GET", "/staff/me/context") => Some(StubResponse::json(200, json!({
                "role": "manager", "org_name": "Nile Café", "caps": ["hr.attendance.read", "hr.deductions.create"],
                "deduction_limit_piastres": 100_000,
                "branches": [{ "id": BRANCH, "name": "Zamalek", "timezone": "Africa/Cairo" }],
                "work_shifts": [], "settings": { "period_start_day": 26 },
                "people": [
                    { "employee_id": TELLER, "name": "Sara", "role": "manager", "branch_ids": [BRANCH] },
                    { "employee_id": "e4", "name": "Youssef", "role": "employee", "branch_ids": [BRANCH] },
                ],
            }))),
            ("PATCH", p) if p.starts_with("/staff/flags/") => Some(StubResponse::json(200, json!({ "id": "f1" }))),
            _ => None,
        })
        .await;
        core.dawam_snapshot(true).await.unwrap();
        let over = json!({ "action": "resolve", "flag": "f1", "how": "deduct", "deduct": 150_000, "reason": "Left for 3 h" });
        let snap: Value = serde_json::from_str(&core.dawam_do(over.to_string()).await.unwrap()).unwrap();
        assert_eq!(snap["filed"]["status"], "pending", "over the limit: waits for the owner");
        let within = json!({ "action": "resolve", "flag": "f1", "how": "deduct", "deduct": 100_000, "reason": "Left" });
        let snap: Value = serde_json::from_str(&core.dawam_do(within.to_string()).await.unwrap()).unwrap();
        assert_eq!(snap.get("filed"), None, "at the limit: done");
        let ignore = json!({ "action": "resolve", "flag": "f1", "how": "ignore" });
        let snap: Value = serde_json::from_str(&core.dawam_do(ignore.to_string()).await.unwrap()).unwrap();
        assert_eq!(snap.get("filed"), None, "no money: nothing waits");
    }

    /// Minor #34: an employee already over the advance cap may still ask;
    /// the answer says only the owner can approve it (the server's
    /// `within_cap` on the new advance, never worked out here).
    #[tokio::test(flavor = "multi_thread")]
    async fn an_advance_asked_over_the_cap_goes_to_the_owner() {
        use crate::testkit::StubResponse;
        use std::sync::atomic::{AtomicBool, Ordering};
        use std::sync::Arc;
        let within = Arc::new(AtomicBool::new(false));
        let w = within.clone();
        let (_stub, core) = cafe(&[], move |m, p, _| match (m, p) {
            ("POST", "/staff/me/advances") => Some(StubResponse::json(201, json!({
                "id": "v9", "status": "pending", "amount_piastres": 50_000, "within_cap": w.load(Ordering::SeqCst),
            }))),
            _ => None,
        })
        .await;
        core.dawam_snapshot(true).await.unwrap();
        let ask = json!({ "action": "file", "kind": "salaryAdvance", "amount": 50_000, "installments": 1 }).to_string();
        let snap: Value = serde_json::from_str(&core.dawam_do(ask.clone()).await.unwrap()).unwrap();
        assert_eq!(snap["filed"], json!({ "id": "v|v9", "status": "pending", "to_owner": true }), "over the cap: the owner's");
        within.store(true, Ordering::SeqCst);
        let snap: Value = serde_json::from_str(&core.dawam_do(ask).await.unwrap()).unwrap();
        assert_eq!(snap["filed"]["to_owner"], json!(false));
    }

    /// Owner decision #8 (D8): declining a pay line or an advance says why.
    /// The core asks before sending (no call without a reason), sends it
    /// (`reason` for a pay line; `note` and `reason` for an advance), and
    /// the server's 400 REASON_REQUIRED reads in the phone's language.
    #[tokio::test(flavor = "multi_thread")]
    async fn declining_a_pay_line_or_an_advance_needs_a_reason() {
        use crate::testkit::StubResponse;
        let (stub, core) = cafe(&["hr.attendance.read", "hr.payroll.run", "hr.advances.decide"], |m, p, _| match (m, p) {
            ("GET", "/staff/payroll/advances") => Some(StubResponse::json(200, json!([
                { "id": "v1", "employee_id": "e4", "status": "pending", "amount_piastres": 200000, "installments": 1,
                  "created_at": "2026-09-20T09:00:00Z" },
            ]))),
            ("PATCH", _) => Some(StubResponse::json(200, json!({}))),
            _ => None,
        })
        .await;
        core.dawam_snapshot(true).await.unwrap();
        let patches = |stub: &crate::testkit::Stub| stub.seen.lock().unwrap().iter().filter(|r| r.method == "PATCH").count();
        for lang in ["en", "ar"] {
            core.set_locale(lang.into());
            for act in [
                json!({ "action": "decide_adj", "adj": "a|bonus|b1", "yes": false }),
                json!({ "action": "decide_adj", "adj": "a|bonus|b1", "yes": false, "reason": "  " }),
                json!({ "action": "decide", "req": "v|v1", "approve": false }),
            ] {
                match core.dawam_do(act.to_string()).await.unwrap_err() {
                    CoreError::Validation { detail, .. } => assert_eq!(detail, i18n::tr(lang, "staff.say_why_you_decline"), "{lang} {act}"),
                    e => panic!("{e:?}"),
                }
            }
        }
        assert_eq!(patches(&stub), 0, "nothing is sent without a reason");
        core.dawam_do(json!({ "action": "decide_adj", "adj": "a|bonus|b1", "yes": false, "reason": " Paid twice " }).to_string()).await.unwrap();
        assert_eq!(posted(&stub, "/staff/adjustments/bonus/b1/decision"), json!({ "approve": false, "reason": "Paid twice" }));
        core.dawam_do(json!({ "action": "decide_adj", "adj": "a|bonus|b2", "yes": true }).to_string()).await.unwrap();
        assert_eq!(posted(&stub, "/staff/adjustments/bonus/b2/decision"), json!({ "approve": true }), "approving needs none");
        core.dawam_do(json!({ "action": "decide", "req": "v|v1", "approve": false, "note": "Owes too much" }).to_string()).await.unwrap();
        let sent = posted(&stub, "/staff/advances/v1/review");
        assert_eq!((sent["approve"].clone(), sent["note"].clone(), sent["reason"].clone()), (json!(false), json!("Owes too much"), json!("Owes too much")));

        let refused = r#"{"error":"Say why you're rejecting it.","code":"REASON_REQUIRED"}"#;
        for lang in ["en", "ar"] {
            core.set_locale(lang.into());
            match core.staff_error(crate::net::status_to_error(400, refused)) {
                CoreError::Server { status, code, detail } => {
                    assert_eq!((status, code.as_str()), (400, "REASON_REQUIRED"));
                    assert_eq!(detail, i18n::tr(lang, "staff.err_reason_required"));
                }
                e => panic!("{e:?}"),
            }
        }
        assert_ne!(i18n::tr("en", "staff.err_reason_required"), i18n::tr("ar", "staff.err_reason_required"));
    }

    /// Owner decision #6 (D6): Stop means from next month. The server ends
    /// the line at the end of the open period (`ends_on`), so this month
    /// keeps it: the list shows it active, ending on that day, and only a
    /// line whose end has passed reads "stopped".
    #[tokio::test(flavor = "multi_thread")]
    async fn a_stopped_line_stays_active_until_its_month_ends() {
        use crate::testkit::StubResponse;
        let (later, gone) = ((today_cairo() + Duration::days(10)).to_string(), (today_cairo() - Duration::days(3)).to_string());
        let (l, g) = (later.clone(), gone.clone());
        let (_stub, core) = cafe(&["hr.attendance.read", "hr.adjustments.create"], move |m, p, _| match (m, p) {
            ("GET", "/staff/adjustments") => Some(StubResponse::json(200, json!([
                { "id": "m1", "kind": "bonus", "employee_id": "e4", "status": "approved", "recurring": true,
                  "amount_piastres": 30000, "reason": "Transport", "effective_date": "2026-08-26", "ends_on": l },
                { "id": "m2", "kind": "bonus", "employee_id": "e4", "status": "approved", "recurring": true,
                  "amount_piastres": 20000, "reason": "Meal", "effective_date": "2026-07-26", "ends_on": g },
                { "id": "m3", "kind": "bonus", "employee_id": "e4", "status": "approved", "recurring": true,
                  "amount_piastres": 10000, "reason": "Phone", "effective_date": "2026-07-26", "ends_on": null },
            ]))),
            _ => None,
        })
        .await;
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        let line = |id: &str| snap["adjustments"].as_array().unwrap().iter().find(|a| a["id"] == id).cloned().unwrap();
        assert_eq!((line("a|bonus|m1")["status"].clone(), line("a|bonus|m1")["ends_on"].clone()), (json!("active"), json!(later)), "this month keeps it");
        assert_eq!(line("a|bonus|m2")["status"], json!("stopped"), "its last month is over");
        assert_eq!((line("a|bonus|m3")["status"].clone(), line("a|bonus|m3")["ends_on"].clone()), (json!("active"), Value::Null));
        for k in ["staff.stops_from_next_month", "staff.stopped_from_next_month", "staff.last_month_ends"] {
            assert_ne!(i18n::tr("en", k), k);
            assert_ne!(i18n::tr("ar", k), i18n::tr("en", k), "{k}");
        }
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn filing_sends_the_half_and_the_shift_and_returns_the_servers_status() {
        use crate::testkit::{StubResponse, BRANCH, TELLER};
        let d = today_cairo().to_string();
        let day = d.clone();
        let (stub, core) = cafe(&[], move |m, p, r| match (m, p) {
            ("GET", "/staff/me/roster") => Some(StubResponse::json(200, json!({ "shifts": [
                { "employee_id": TELLER, "date": day, "work_shift_id": "w1" },
                { "employee_id": TELLER, "date": day, "work_shift_id": "w2" }
            ], "team": [], "unpublished_weeks": [] }))),
            ("GET", "/staff/me/attendance") => Some(StubResponse::json(200, json!([
                { "id": "rec", "employee_id": TELLER, "business_date": day, "work_shift_id": "w2", "branch_id": BRANCH, "status": "present" }
            ]))),
            // A filer who approves their own gets it approved at once.
            ("POST", "/staff/me/requests") => Some(StubResponse::json(201, json!({
                "id": "q1", "status": if r.json()["kind"] == "leave" { "approved" } else { "pending" }, "to_owner": r.json()["kind"] == "excuse",
            }))),
            _ => None,
        })
        .await;
        core.dawam_snapshot(true).await.unwrap();

        let act = json!({ "action": "file", "kind": "leave", "from": d, "half": true, "leave_half": "second", "note": "Dentist" }).to_string();
        let snap: Value = serde_json::from_str(&core.dawam_do(act).await.unwrap()).unwrap();
        let body = posted(&stub, "/staff/me/requests");
        assert_eq!((body["is_half_day"].clone(), body["leave_half"].clone()), (json!(true), json!("second")));
        assert_eq!(snap["filed"], json!({ "id": "q|q1", "status": "approved", "to_owner": false }), "the screen words the server's answer");

        let act = json!({ "action": "file", "kind": "leave", "from": d, "half": true }).to_string();
        core.dawam_do(act).await.unwrap();
        assert_eq!(posted(&stub, "/staff/me/requests")["leave_half"], "first", "a half day with no half is the first");
        let act = json!({ "action": "file", "kind": "leave", "from": d }).to_string();
        core.dawam_do(act).await.unwrap();
        assert!(posted(&stub, "/staff/me/requests").get("leave_half").is_none(), "a whole day names no half");
        assert!(posted(&stub, "/staff/me/requests").get("is_paid").is_none(), "no choice made, none sent");
        // A self-approver's leave carries the pay choice (QUESTIONS #19, RQ-2).
        let act = json!({ "action": "file", "kind": "leave", "from": d, "paid": false }).to_string();
        core.dawam_do(act).await.unwrap();
        assert_eq!(posted(&stub, "/staff/me/requests")["is_paid"], json!(false));

        // The evening shift of a split day, by name; no record on a late arrival.
        let evening = format!("{TELLER}|{d}|w2");
        let act = json!({ "action": "file", "kind": "lateArrival", "from": d, "time": 18 * 60 + 30, "shift": evening }).to_string();
        let snap: Value = serde_json::from_str(&core.dawam_do(act).await.unwrap()).unwrap();
        let body = posted(&stub, "/staff/me/requests");
        assert_eq!(body["work_shift_id"], "w2");
        assert!(body.get("attendance_record_id").is_none(), "only a correction names a record: {body}");
        assert_eq!(snap["filed"]["status"], "pending");

        // An excuse may run past midnight (B5); a manager's goes above them.
        let act = json!({ "action": "file", "kind": "excuse", "from": d, "time": 22 * 60 + 30, "time2": 60, "shift": evening }).to_string();
        let snap: Value = serde_json::from_str(&core.dawam_do(act).await.unwrap()).unwrap();
        let body = posted(&stub, "/staff/me/requests");
        assert_eq!((body["from_time"].clone(), body["to_time"].clone()), (json!("22:30"), json!("01:00")));
        assert_eq!(snap["filed"]["to_owner"], true);
        // Only an empty window is refused, and before it leaves the phone.
        let n = stub.requests("/staff/me/requests").len();
        let act = json!({ "action": "file", "kind": "excuse", "from": d, "time": 600, "time2": 600 }).to_string();
        assert!(core.dawam_do(act).await.is_err());
        // A mission needs a note (the server titles it with the note, §3).
        let act = json!({ "action": "file", "kind": "mission", "from": d, "note": " . " }).to_string();
        let err = core.dawam_do(act).await.unwrap_err();
        assert!(format!("{err:?}").contains(&i18n::tr("en", "staff.a_mission_needs_a_note")), "{err:?}");
        assert_eq!(stub.requests("/staff/me/requests").len(), n, "nothing refused here reached the server");
        let act = json!({ "action": "file", "kind": "mission", "from": d, "note": "Supplier in Obour" }).to_string();
        core.dawam_do(act).await.unwrap();
        let body = posted(&stub, "/staff/me/requests");
        assert_eq!((body["title"].clone(), body["reason"].clone()), (json!("Supplier in Obour"), json!("Supplier in Obour")));
    }

    /// RQ-7: pay is asked only of leave, an excuse and an early departure;
    /// the approver starts from the server's `paid_default`; `to_owner` is
    /// the server's word, not a list of roles (RQ-5).
    #[tokio::test(flavor = "multi_thread")]
    async fn a_decision_carries_pay_only_where_pay_is_asked() {
        use crate::testkit::StubResponse;
        let d = today_cairo().to_string();
        let day = d.clone();
        let (stub, core) = cafe(&["hr.leave.edit", "hr.attendance.read"], move |m, p, _| match (m, p) {
            ("GET", "/staff/requests") => Some(StubResponse::json(200, json!([
                { "id": "late", "kind": "late_arrival", "employee_id": "e4", "status": "pending", "on_date": day, "to_time": "09:30:00", "created_at": "2026-09-22T08:00:00Z" },
                { "id": "early", "kind": "early_departure", "employee_id": "e4", "status": "pending", "on_date": day, "from_time": "11:00:00", "paid_default": true, "created_at": "2026-09-22T08:01:00Z" },
                { "id": "exc", "kind": "excuse", "employee_id": "e4", "status": "pending", "on_date": day, "from_time": "09:00:00", "to_time": "10:00:00", "paid_default": false, "created_at": "2026-09-22T08:02:00Z" },
                // A manager's own request, routed above them by the server.
                { "id": "mgr", "kind": "leave", "employee_id": "m2", "status": "pending", "on_date": day, "to_owner": true, "created_at": "2026-09-22T08:03:00Z" },
                // An employee whose role reads "manager" in no list: the server says who decides.
                { "id": "emp", "kind": "leave", "employee_id": "e4", "status": "pending", "on_date": day, "to_owner": false, "created_at": "2026-09-22T08:04:00Z" },
                // The server's own answer wins when it sends one.
                { "id": "said_yes", "kind": "leave", "employee_id": "m2", "status": "pending", "on_date": day, "to_owner": true, "can_decide": true, "created_at": "2026-09-22T08:05:00Z" },
                { "id": "said_no", "kind": "leave", "employee_id": "e4", "status": "pending", "on_date": day, "to_owner": false, "can_decide": false, "created_at": "2026-09-22T08:06:00Z" }
            ]))),
            ("PATCH", _) => Some(StubResponse::json(200, json!({}))),
            _ => None,
        })
        .await;
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        let req = |id: &str| snap["requests"].as_array().unwrap().iter().find(|q| q["id"] == json!(format!("q|{id}"))).unwrap().clone();
        assert_eq!(req("early")["paid_default"], true);
        assert_eq!(req("exc")["paid_default"], false);
        assert!(req("late")["paid_default"].is_null());
        assert_eq!((req("mgr")["to_owner"].clone(), req("emp")["to_owner"].clone()), (json!(true), json!(false)));
        let inbox: Vec<&str> = snap["inbox"].as_array().unwrap().iter().filter_map(Value::as_str).collect();
        assert!(!inbox.contains(&"q|mgr"), "a peer manager's own request waits for someone above: {inbox:?}");
        assert!(inbox.contains(&"q|emp"));
        assert!(inbox.contains(&"q|said_yes") && !inbox.contains(&"q|said_no"), "{inbox:?}");

        let decide = |id: &str, paid: bool| json!({ "action": "decide", "req": format!("q|{id}"), "approve": true, "paid": paid }).to_string();
        core.dawam_do(decide("late", true)).await.unwrap();
        let body = posted(&stub, "/staff/requests/late/decision");
        assert!(body.get("is_paid").is_none(), "a late arrival has no pay to decide: {body}");
        core.dawam_do(decide("early", false)).await.unwrap();
        assert_eq!(posted(&stub, "/staff/requests/early/decision")["is_paid"], false);
        core.dawam_do(decide("exc", true)).await.unwrap();
        assert_eq!(posted(&stub, "/staff/requests/exc/decision")["is_paid"], true);
        core.dawam_do(decide("emp", false)).await.unwrap();
        assert_eq!(posted(&stub, "/staff/requests/emp/decision")["is_paid"], false);
        // Declining never carries pay.
        core.dawam_do(json!({ "action": "decide", "req": "q|exc", "approve": false, "paid": true }).to_string()).await.unwrap();
        assert!(posted(&stub, "/staff/requests/exc/decision").get("is_paid").is_none());
    }

    /// B5 and B4 on the day: an approved excuse past midnight is its own
    /// day's excuse, of the right length, and a request naming the evening
    /// shift leaves the morning shift alone. RQ-8: the half shows.
    #[tokio::test(flavor = "multi_thread")]
    async fn an_approved_request_lands_on_its_own_shift_and_night_excuses_count_right() {
        use crate::testkit::{StubResponse, TELLER};
        let today = today_cairo();
        let (d, next) = (today.to_string(), (today + Duration::days(1)).to_string());
        let (day, day2) = (d.clone(), next.clone());
        let (_stub, core) = cafe(&[], move |m, p, _| match (m, p) {
            ("GET", "/staff/me/roster") => Some(StubResponse::json(200, json!({ "shifts": [
                { "employee_id": TELLER, "date": day, "work_shift_id": "w1" },
                { "employee_id": TELLER, "date": day, "work_shift_id": "w2" },
                { "employee_id": TELLER, "date": day2, "work_shift_id": "w2" }
            ], "team": [], "unpublished_weeks": [] }))),
            ("GET", "/staff/me/requests") => Some(StubResponse::json(200, json!([
                { "id": "x", "kind": "excuse", "employee_id": TELLER, "status": "approved", "on_date": day, "end_date": day2,
                  "from_time": "22:30:00", "to_time": "00:30:00", "work_shift_id": "w2", "is_paid": true, "created_at": "2026-09-22T08:00:00Z" },
                { "id": "h", "kind": "leave", "employee_id": TELLER, "status": "approved", "on_date": day2, "end_date": day2,
                  "is_half_day": true, "leave_half": "second", "is_paid": false, "created_at": "2026-09-22T08:00:00Z" }
            ]))),
            _ => None,
        })
        .await;
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        let sh = |date: &str, tpl: &str| snap["shifts"].as_array().unwrap().iter().find(|x| x["id"] == json!(format!("{TELLER}|{date}|{tpl}"))).unwrap().clone();
        assert_eq!(sh(&d, "w2")["excuse_min"], 120, "22:30 → 00:30 is two hours");
        assert_eq!(sh(&d, "w2")["excuse_paid"], true);
        assert_eq!(sh(&d, "w1")["excuse_min"], 0, "the morning shift isn't the one excused");
        assert_eq!(sh(&next, "w2")["excuse_min"], 0, "the next day isn't excused by the night before");
        assert_eq!((sh(&next, "w2")["half_leave"].clone(), sh(&next, "w2")["leave_half"].clone()), (json!(true), json!("second")));
        let q = snap["requests"].as_array().unwrap().iter().find(|q| q["id"] == "q|h").unwrap();
        assert_eq!(q["leave_half"], "second");
        let q = snap["requests"].as_array().unwrap().iter().find(|q| q["id"] == "q|x").unwrap();
        assert_eq!(q["tpl"], "w2");
    }

    /// RQ-4 / B13: a day can change while no approved or paid period holds
    /// it — last month's draft too — and not once its payroll is approved.
    #[tokio::test(flavor = "multi_thread")]
    async fn which_days_can_change_comes_from_the_periods() {
        use crate::testkit::{StubResponse, TELLER};
        let today = today_cairo();
        let (start, _) = period_around(today, 26);
        let prev = start - chrono::Months::new(1);
        let older = prev - chrono::Months::new(1);
        let (d_prev, d_older, d_now) = ((prev + Duration::days(2)).to_string(), (older + Duration::days(2)).to_string(), today.to_string());
        let (a, b, c) = (d_prev.clone(), d_older.clone(), d_now.clone());
        let (s0, s1, s2) = (start.to_string(), prev.to_string(), older.to_string());
        let (_stub, core) = cafe(&[], move |m, p, _| match (m, p) {
            ("GET", "/staff/me/roster") => Some(StubResponse::json(200, json!({ "shifts": [
                { "employee_id": TELLER, "date": c, "work_shift_id": "w1" },
                { "employee_id": TELLER, "date": a, "work_shift_id": "w1" },
                { "employee_id": TELLER, "date": b, "work_shift_id": "w1" }
            ], "team": [], "unpublished_weeks": [] }))),
            ("GET", "/staff/me/pay/estimate") => Some(StubResponse::json(200, json!({ "period_start": s0, "period_end": (start + chrono::Months::new(1) - Duration::days(1)).to_string() }))),
            // Only the month before last has a frozen payslip: last month is still a draft.
            ("GET", "/staff/me/payslips") => Some(StubResponse::json(200, json!([
                { "employee_id": TELLER, "period_start": s2, "period_end": (prev - Duration::days(1)).to_string(), "net_piastres": 1 }
            ]))),
            ("GET", "/staff/me/requests") => Some(StubResponse::json(200, json!([
                // A leave reaching back into the closed month is closed too.
                { "id": "span", "kind": "leave", "employee_id": TELLER, "status": "approved", "on_date": (prev - Duration::days(1)).to_string(), "end_date": s1, "is_paid": true, "created_at": "2026-09-22T08:00:00Z" },
                { "id": "open", "kind": "leave", "employee_id": TELLER, "status": "approved", "on_date": s1, "is_paid": true, "created_at": "2026-09-22T08:00:00Z" }
            ]))),
            _ => None,
        })
        .await;
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        let open = |date: &str| snap["shifts"].as_array().unwrap().iter().find(|x| x["date"] == json!(date)).unwrap()["month_open"].clone();
        assert_eq!(open(&d_now), true);
        assert_eq!(open(&d_prev), true, "last month's payroll is still a draft (B13)");
        assert_eq!(open(&d_older), false, "the month before is approved");
        let q = |id: &str| snap["requests"].as_array().unwrap().iter().find(|q| q["id"] == json!(format!("q|{id}"))).unwrap()["month_open"].clone();
        assert_eq!(q("span"), false);
        assert_eq!(q("open"), true);
    }

    /// E2E posnotif S-301: a burst of refreshes (a push each) ran past the
    /// server's per-person limit; the refused (429) roster read was taken as
    /// "nothing to show", so Home said "No shift today" until the next
    /// refresh. A throttled or failing read keeps the last picture whole.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_throttled_refresh_keeps_the_last_picture() {
        use crate::testkit::{StubResponse, TELLER};
        use std::sync::atomic::{AtomicUsize, Ordering};
        let d = today_cairo().to_string();
        let calls = std::sync::Arc::new(AtomicUsize::new(0));
        let seen = calls.clone();
        let (_stub, core) = cafe(&[], move |m, p, _| match (m, p) {
            ("GET", "/staff/me/roster") => {
                // The first read answers; every later one is throttled.
                if seen.fetch_add(1, Ordering::SeqCst) == 0 {
                    Some(StubResponse::json(200, json!({ "shifts": [
                        { "employee_id": TELLER, "date": d, "work_shift_id": "w1" }
                    ], "team": [], "unpublished_weeks": [] })))
                } else {
                    Some(StubResponse::json(429, json!({ "error": "Too many requests" })))
                }
            }
            _ => None,
        })
        .await;
        let mine = |snap: &Value| snap["shifts"].as_array().unwrap().iter().filter(|x| x["emp"] == json!(TELLER)).count();
        let first: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        assert_eq!(mine(&first), 1);
        let again: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        assert!(calls.load(Ordering::SeqCst) >= 2, "the second refresh asked again");
        assert_eq!(mine(&again), 1, "a 429 must not blank the roster");
    }

    /// E2E posnotif: the Payroll tab's adjustments list showed a rule line in
    /// the server's English ("Absent — no check-in recorded") on an Arabic
    /// screen. A line with a reason code is worded here, as on the payslip.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_rule_line_in_the_adjustments_list_is_worded_in_the_phone_language() {
        use crate::testkit::{StubResponse, TELLER};
        let (_stub, core) = cafe(&["hr.attendance.read", "hr.payroll.run"], |m, p, _| match (m, p) {
            ("GET", "/staff/adjustments") => Some(StubResponse::json(200, json!([
                { "id": "d1", "kind": "deduction", "employee_id": TELLER, "amount_piastres": 25000, "value_piastres": 25000,
                  "reason": "Absent — no check-in recorded", "effective_date": "2026-09-24", "source": "absence",
                  "status": "approved", "recurring": false, "reason_code": "absent_no_punch", "reason_vars": {} },
                { "id": "d2", "kind": "deduction", "employee_id": TELLER, "amount_piastres": 3000, "value_piastres": 3000,
                  "reason": "Broken glass", "effective_date": "2026-09-24", "source": "manual",
                  "status": "approved", "recurring": false, "reason_code": null, "reason_vars": null }
            ]))),
            _ => None,
        })
        .await;
        for lang in ["ar", "en"] {
            core.set_locale(lang.into());
            let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
            let reason = |id: &str| {
                snap["adjustments"].as_array().unwrap().iter().find(|a| a["id"] == json!(format!("a|deduction|{id}"))).unwrap()["reason"].clone()
            };
            assert_eq!(reason("d1"), json!(i18n::tr(lang, "staff.pay_reason_absent_no_punch")), "{lang}");
            assert_eq!(reason("d2"), json!("Broken glass"), "a typed reason stays as typed");
            // Minor #30: a rule-made line says so ("Rule · absence"), not
            // "One-off · by —".
            let rule = |id: &str| {
                snap["adjustments"].as_array().unwrap().iter().find(|a| a["id"] == json!(format!("a|deduction|{id}"))).unwrap()["rule"].clone()
            };
            assert_eq!(rule("d1"), json!(i18n::tr(lang, "staff.rule_absence")), "{lang}");
            assert_eq!(rule("d2"), Value::Null, "a line added by hand");
        }
        for k in ["staff.rule_absence", "staff.rule_late", "staff.rule_excuse", "staff.rule_flag", "staff.rule"] {
            assert_ne!(i18n::tr("ar", k), i18n::tr("en", k), "{k}");
        }
        assert_ne!(i18n::tr("ar", "staff.pay_reason_absent_no_punch"), "Absent — no check-in recorded");
    }

    /// Decision #1: a closed month is `PERIOD_CLOSED` everywhere, and the
    /// phone says it in the person's language.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_closed_month_is_worded_in_both_languages() {
        use crate::testkit::StubResponse;
        let d = today_cairo().to_string();
        let (_stub, core) = cafe(&[], |m, p, _| match (m, p) {
            ("POST", "/staff/me/requests") => Some(StubResponse::json(409, json!({
                "error": "PERIOD_CLOSED: that month's payroll is approved", "code": "PERIOD_CLOSED",
            }))),
            _ => None,
        })
        .await;
        core.dawam_snapshot(true).await.unwrap();
        for lang in ["en", "ar"] {
            core.set_locale(lang.into());
            let act = json!({ "action": "file", "kind": "leave", "from": d }).to_string();
            match core.dawam_do(act).await {
                Err(CoreError::Server { status, code, detail }) => {
                    assert_eq!((status, code.as_str()), (409, "PERIOD_CLOSED"));
                    assert_eq!(detail, i18n::tr(lang, "staff.err_period_closed"));
                }
                other => panic!("expected the closed month, got {other:?}"),
            }
        }
        assert_ne!(i18n::tr("en", "staff.err_period_closed"), i18n::tr("ar", "staff.err_period_closed"));
    }

    /// E2E B-TEAM-1: nobody decides their own flag — the server answers 403
    /// `OWN_DECISION`, and the phone says it in the person's language (it
    /// showed the server's English on an Arabic screen).
    #[tokio::test(flavor = "multi_thread")]
    async fn deciding_your_own_flag_is_worded_in_both_languages() {
        use crate::testkit::StubResponse;
        let (_stub, core) = cafe(&["hr.attendance.read", "hr.attendance.edit"], |m, p, _| match (m, p) {
            ("PATCH", "/staff/flags/f1") => Some(StubResponse::json(403, json!({
                "error": "Someone else has to decide this one.", "code": "OWN_DECISION",
            }))),
            _ => None,
        })
        .await;
        core.dawam_snapshot(true).await.unwrap();
        for lang in ["en", "ar"] {
            core.set_locale(lang.into());
            let act = json!({ "action": "resolve", "flag": "f1", "how": "ignore" }).to_string();
            match core.dawam_do(act).await {
                Err(CoreError::Server { status, code, detail }) => {
                    assert_eq!((status, code.as_str()), (403, "OWN_DECISION"));
                    assert_eq!(detail, i18n::tr(lang, "staff.err_own_decision"));
                }
                other => panic!("expected the own-decision refusal, got {other:?}"),
            }
        }
        assert_ne!(i18n::tr("en", "staff.err_own_decision"), "staff.err_own_decision");
        assert_ne!(i18n::tr("en", "staff.err_own_decision"), i18n::tr("ar", "staff.err_own_decision"));
    }

    /// AT-7: cancelling an approved request says why; a pending one doesn't
    /// have to.
    #[tokio::test(flavor = "multi_thread")]
    async fn cancelling_an_approved_request_carries_the_reason() {
        use crate::testkit::{StubResponse, TELLER};
        let d = today_cairo().to_string();
        let day = d.clone();
        let (stub, core) = cafe(&[], move |m, p, _| match (m, p) {
            ("GET", "/staff/me/requests") => Some(StubResponse::json(200, json!([
                { "id": "a", "kind": "leave", "employee_id": TELLER, "status": "approved", "on_date": day, "is_paid": true, "created_at": "2026-09-22T08:00:00Z" },
                { "id": "p", "kind": "leave", "employee_id": TELLER, "status": "pending", "on_date": day, "created_at": "2026-09-22T08:00:00Z" }
            ]))),
            ("PATCH", _) => Some(StubResponse::json(200, json!({}))),
            _ => None,
        })
        .await;
        core.dawam_snapshot(true).await.unwrap();
        let err = core.dawam_do(json!({ "action": "cancel", "req": "q|a" }).to_string()).await.unwrap_err();
        assert!(format!("{err:?}").contains(&i18n::tr("en", "staff.say_why_you_cancel")), "{err:?}");
        assert!(stub.requests("/staff/requests/a").is_empty(), "refused before the server");
        core.dawam_do(json!({ "action": "cancel", "req": "q|a", "note": "Plans changed" }).to_string()).await.unwrap();
        assert_eq!(posted(&stub, "/staff/requests/a/decision"), json!({ "status": "cancelled", "note": "Plans changed" }));
        core.dawam_do(json!({ "action": "cancel", "req": "q|p" }).to_string()).await.unwrap();
        assert_eq!(posted(&stub, "/staff/requests/p/decision"), json!({ "status": "cancelled" }));
    }

    /// RQ-F6 (backend a686678): a cancel keeps the approval in decided_* and
    /// writes cancelled_* — the app reads the canceller from cancelled_by
    /// (the linked person), never from decided_by; the person is told.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_cancel_by_someone_else_is_read_from_cancelled_by() {
        use crate::testkit::{StubResponse, TELLER};
        let d = today_cairo().to_string();
        let day = d.clone();
        let (_stub, core) = cafe(&[], move |m, p, _| match (m, p) {
            ("GET", "/staff/me/requests") => Some(StubResponse::json(200, json!([
                { "id": "c", "kind": "leave", "employee_id": TELLER, "status": "cancelled", "on_date": day, "end_date": day,
                  "is_paid": false, "decided_by": "u-karim", "decision_note": "Get well",
                  "cancelled_by": "u-omar", "cancel_note": "She came in after all", "created_at": "2026-09-22T08:00:00Z" },
                { "id": "p", "kind": "leave", "employee_id": TELLER, "status": "cancelled", "on_date": day, "end_date": day,
                  "cancelled_by": null, "created_at": "2026-09-22T08:00:00Z" }
            ]))),
            ("GET", "/staff/me/context") => None,
            _ => None,
        })
        .await;
        let snap: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
        let q = |id: &str| snap["requests"].as_array().unwrap().iter().find(|q| q["id"] == json!(format!("q|{id}"))).unwrap().clone();
        assert_eq!(q("c")["decided_by"], "u-karim", "the approver stays the approver");
        assert_eq!(q("c")["decision_note"], "Get well");
        assert_eq!(q("c")["cancelled_by"], "u-omar");
        assert_eq!(q("c")["cancel_note"], "She came in after all");
        assert_eq!(q("p")["cancelled_by"], Value::Null);
        for lang in ["en", "ar"] {
            let text = notice_text(lang, "staff.n_request_cancelled", &json!({ "kind": "leave", "date": "2026-09-23", "note": "She came in" }));
            assert!(!text.starts_with("staff."), "{text}");
            assert!(text.contains("She came in") && text.contains("23"), "{text}");
        }
        assert_eq!(
            notice_text("en", "staff.n_request_cancelled", &json!({ "kind": "leave", "date": "2026-09-23", "note": "She came in" })),
            "Your Leave request for 23 Sep was cancelled: She came in"
        );
    }

    /// A request refused because someone already decided it, or because an
    /// overlapping one exists, reads in the phone's language (E2E: English
    /// on an Arabic phone): REQUEST_ALREADY_DECIDED, OVERLAPPING_REQUEST.
    #[tokio::test(flavor = "multi_thread")]
    async fn request_refusals_read_in_the_phones_language() {
        use crate::testkit::{StubResponse, TELLER};
        let d = today_cairo().to_string();
        let day = d.clone();
        let (_stub, core) = cafe(&["hr.leave.edit"], move |m, p, _| match (m, p) {
            ("GET", "/staff/requests") | ("GET", "/staff/me/requests") => Some(StubResponse::json(200, json!([
                { "id": "a", "kind": "leave", "employee_id": "e4", "status": "pending", "on_date": day, "end_date": day, "created_at": "2026-09-22T08:00:00Z", "can_decide": true }
            ]))),
            ("PATCH", "/staff/requests/a/decision") => Some(StubResponse::json(409, json!({
                "error": "Conflict: This request is already approved", "code": "REQUEST_ALREADY_DECIDED", "vars": { "status": "approved" }
            }))),
            ("POST", "/staff/me/requests") => Some(StubResponse::json(409, json!({
                "error": "Conflict: You already have a request like this for that time.", "code": "OVERLAPPING_REQUEST"
            }))),
            _ => None,
        })
        .await;
        core.dawam_snapshot(true).await.unwrap();
        let _ = TELLER;
        for lang in ["en", "ar"] {
            core.set_locale(lang.into());
            match core.dawam_do(json!({ "action": "decide", "req": "q|a", "approve": true, "paid": true }).to_string()).await {
                Err(CoreError::Server { status, code, detail }) => {
                    assert_eq!((status, code.as_str()), (409, "REQUEST_ALREADY_DECIDED"));
                    assert_eq!(detail, i18n::tr(lang, "staff.err_request_already_decided"));
                }
                other => panic!("expected the refusal, got {other:?}"),
            }
            match core.dawam_do(json!({ "action": "file", "kind": "leave", "from": d }).to_string()).await {
                Err(CoreError::Server { status, code, detail }) => {
                    assert_eq!((status, code.as_str()), (409, "OVERLAPPING_REQUEST"));
                    assert_eq!(detail, i18n::tr(lang, "staff.err_overlapping_request"));
                }
                other => panic!("expected the refusal, got {other:?}"),
            }
        }
        assert_ne!(i18n::tr("en", "staff.err_overlapping_request"), i18n::tr("ar", "staff.err_overlapping_request"));
        assert_ne!(i18n::tr("en", "staff.err_request_already_decided"), i18n::tr("ar", "staff.err_request_already_decided"));
    }

    /// A refusal the core words itself is a whole sentence: no field name in
    /// front of it (E2E requests: "req Ask your manager to cancel this one.",
    /// the raw "req" even on an Arabic phone).
    #[tokio::test(flavor = "multi_thread")]
    async fn a_refusal_in_words_carries_no_field_name() {
        use crate::testkit::{StubResponse, TELLER};
        let (_stub, core) = cafe(&[], move |m, p, _| match (m, p) {
            ("GET", "/staff/me/advances") => Some(StubResponse::json(200, json!([
                { "id": "v1", "employee_id": TELLER, "amount_piastres": 120000, "installments": 3, "status": "pending", "created_at": "2026-09-22T08:00:00Z" }
            ]))),
            _ => None,
        })
        .await;
        core.dawam_snapshot(true).await.unwrap();
        for lang in ["en", "ar"] {
            core.set_locale(lang.into());
            match core.dawam_do(json!({ "action": "cancel", "req": "v|v1" }).to_string()).await {
                Err(CoreError::Validation { field, detail }) => {
                    assert_eq!(field, "", "a worded refusal names no field");
                    assert_eq!(detail, i18n::tr(lang, "staff.ask_manager_to_cancel"));
                }
                other => panic!("expected the refusal, got {other:?}"),
            }
        }
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
