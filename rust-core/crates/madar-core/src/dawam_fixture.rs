//! A small café as the server would answer it, run through the real core, so
//! the staff app's widget tests read snapshots the core itself produced.
//!
//!     MADAR_WRITE_DAWAM_FIXTURES=1 cargo test -p madar-core --lib dawam_fixture
//!
//! writes `apps/staff/test/fixtures/{e1,e2,e3}.json` (employee, branch manager,
//! owner). Without the variable the test still builds all three and checks
//! the picture, so a core change that breaks a screen's data fails here.

use chrono::{Datelike, Duration, NaiveDate, Utc};
use serde_json::{json, Value};

use crate::testkit::{online_core, Stub, StubResponse};

const B1: &str = "b1";
const B2: &str = "b2";

struct World {
    today: NaiveDate,
}

impl World {
    fn d(&self, days: i64) -> String {
        (self.today + Duration::days(days)).to_string()
    }
    fn at(&self, days: i64, hm: &str) -> String {
        // Cairo is UTC+3 in the fixture's months; the value only has to be stable.
        format!("{}T{}:00+03:00", self.d(days), hm)
    }

    fn context(&self, role: &str) -> Value {
        let pay = role != "employee";
        let person = |id: &str, name: &str, phone: &str, role: &str, branches: &[&str], salary: i64, gender: &str| {
            json!({
                "user_id": id, "name": name, "phone": phone, "role": role, "branch_ids": branches,
                "gender": gender, "hire_date": "2025-01-05",
                "base_salary_piastres": if pay || id == "e1" { Some(salary) } else { None },
                "pay_method": if id == "e1" { "bank" } else { "cash" }, "pay_account": "",
                "pref_time": if id == "e1" { Some("morning") } else { None },
                "cant_work_days": if id == "e4" { vec![5] } else { vec![] },
                "device_model": "iPhone 14", "device_since": "2026-03-02T09:00:00Z",
            })
        };
        let mut people = vec![
            person("e1", "Sara Ahmed", "01001234567", "employee", &[B1], 900_000, "f"),
            person("e2", "Omar Khaled", "01002345678", "manager", &[B1], 1_400_000, "m"),
            person("e3", "Hana Mostafa", "01003333333", "owner", &[B1, B2], 0, "f"),
            person("e4", "Youssef Adel", "01004567890", "employee", &[B1], 800_000, "m"),
        ];
        if role == "owner" {
            people.push(person("e5", "Laila Hassan", "01005678901", "employee", &[B2], 850_000, "f"));
        }
        json!({
            "role": role, "org_name": "Nile Café",
            "caps": if role == "owner" { vec!["hr.payroll.run", "hr.schedule.publish"] } else if role == "manager" { vec!["hr.schedule.publish"] } else { vec![] },
            "adjustment_limit_piastres": if role == "manager" { Some(100_000) } else { None },
            "branches": [
                { "id": B1, "name": "Zamalek", "geo_radius_meters": 200, "latitude": 30.0609, "longitude": 31.2197, "timezone": "Africa/Cairo" },
                { "id": B2, "name": "Maadi", "geo_radius_meters": 150, "latitude": 29.9602, "longitude": 31.2569, "timezone": "Africa/Cairo" }
            ],
            "work_shifts": [
                { "id": "zM", "name": "Morning", "branch_id": B1, "start_time": "08:00:00", "end_time": "16:00:00", "grace_minutes": 10 },
                { "id": "zE", "name": "Evening", "branch_id": B1, "start_time": "15:00:00", "end_time": "23:00:00", "grace_minutes": 10 },
                { "id": "mM", "name": "Morning", "branch_id": B2, "start_time": "08:00:00", "end_time": "16:00:00", "grace_minutes": 10 }
            ],
            "people": people,
            "settings": {
                "period_start_day": 26, "overtime_mode": "approval",
                "overtime_day_multiplier": "1.35", "overtime_night_multiplier": "1.70",
                "holiday_multiplier": "2", "advance_cap_percent": "50", "absence_deduction_days": "1"
            }
        })
    }

    /// Two weeks: Sara mornings and Youssef evenings at Zamalek, Laila at Maadi.
    fn roster(&self, who: &[&str]) -> Vec<Value> {
        let mut out = Vec::new();
        for day in -7..8 {
            for (u, t) in [("e1", "zM"), ("e4", "zE"), ("e5", "mM")] {
                if who.contains(&u) {
                    out.push(json!({ "user_id": u, "date": self.d(day), "work_shift_id": t, "changed": u == "e1" && day == 1, "on_leave": false }));
                }
            }
        }
        out
    }

    fn attendance(&self) -> Vec<Value> {
        let rec = |id: &str, u: &str, day: i64, t: &str, inn: Option<&str>, out: Option<&str>, status: &str, late: i64| {
            json!({
                "id": id, "user_id": u, "business_date": self.d(day), "work_shift_id": t, "status": status,
                "check_in_at": inn.map(|h| self.at(day, h)), "check_out_at": out.map(|h| self.at(day, h)),
                "check_in_method": inn.map(|_| "mobile_gps"), "check_out_method": out.map(|_| "mobile_gps"),
                "late_minutes": late, "overtime_minutes": 0, "worked_minutes": 470, "tracking_off": false,
                "covered_user_id": null, "cover_status": null, "overtime_status": null,
            })
        };
        vec![
            rec("r1", "e1", -1, "zM", Some("08:12"), Some("16:05"), "late", 2),
            rec("r2", "e4", -1, "zE", None, None, "absent", 0),
            rec("r3", "e4", 0, "zE", Some("15:40"), None, "late", 30),
        ]
    }

    fn requests(&self) -> Vec<Value> {
        vec![
            json!({ "id": "q1", "kind": "leave", "user_id": "e4", "status": "pending", "on_date": self.d(3), "is_half_day": false, "reason": "Family wedding", "created_at": self.at(0, "07:00") }),
            json!({ "id": "q2", "kind": "late_arrival", "user_id": "e1", "status": "approved", "on_date": self.d(2), "from_time": "09:30:00", "is_half_day": false, "reason": "Doctor", "created_at": self.at(-2, "10:00"), "decided_by": "e2" }),
        ]
    }

    fn slip(&self, u: &str, base: i64, net: i64) -> Value {
        json!({
            "user_id": u, "base_piastres": base, "net_piastres": net, "overtime_piastres": 0, "overtime_minutes": 0,
            "bonuses_piastres": 0, "deductions_piastres": base - net, "advance_installment_piastres": 0, "carry_out_piastres": 0,
            "breakdown": { "paid_days": 31, "window_days": 31, "bonuses": [],
                "deductions": if base > net { vec![json!({ "id": format!("d-{u}"), "reason": "Late arrival", "piastres": base - net, "source": "late_penalty" })] } else { vec![] },
                "advances": [] }
        })
    }

    fn answer(&self, role: &str, path: &str) -> Value {
        let manager = role != "employee";
        let all = ["e1", "e4", "e5"];
        match path {
            "/staff/me/context" => self.context(role),
            "/staff/me/roster" => json!({
                "shifts": if manager { vec![] } else { self.roster(&["e1"]) },
                "team": if manager { vec![] } else { self.roster(&["e4"]) },
                "open_shifts": [{ "id": "o1", "branch_id": B1, "on_date": self.d(4), "work_shift_id": "zE", "status": "open" }],
                "swaps": if manager { json!([]) } else { json!([{ "id": "w1", "requester_id": "e1", "requester_date": self.d(5), "requester_shift_id": "zM", "peer_id": "e4", "peer_date": self.d(5), "peer_shift_id": "zE", "status": "awaiting_peer", "created_at": self.at(0, "06:00") }]) },
                "unpublished_weeks": [], "pref_time": "morning",
            }),
            "/staff/roster" => json!({
                "published_weeks": [crate::dawam::week_start(self.today).to_string()],
                "shifts": self.roster(&all), "open_shifts": [],
                "holidays": [{ "on_date": format!("{}-10-06", self.today.year()), "name_en": "Armed Forces Day", "name_ar": "عيد القوات المسلحة", "decision": null }],
            }),
            "/staff/attendance" => json!(self.attendance()),
            "/staff/me/attendance" => json!(self.attendance().into_iter().filter(|r| r["user_id"] == "e1").collect::<Vec<_>>()),
            "/staff/requests" => json!(self.requests()),
            "/staff/me/requests" => json!(self.requests().into_iter().filter(|r| r["user_id"] == "e1").collect::<Vec<_>>()),
            "/staff/payroll/advances" | "/staff/me/advances" => json!([
                { "id": "v1", "user_id": "e1", "amount_piastres": 100_000, "installments": 2, "remaining_piastres": 50_000, "status": "approved", "created_at": self.at(-20, "10:00"), "decided_at": self.at(-20, "11:00"), "decided_by": "e2" },
                { "id": "v2", "user_id": "e4", "amount_piastres": 50_000, "installments": 1, "remaining_piastres": 50_000, "status": "pending", "reason": "Rent", "created_at": self.at(0, "08:00") }
            ]),
            "/staff/flags" => json!([
                { "id": "f1", "user_id": "e4", "user_name": "Youssef Adel", "branch_id": B1, "attendance_record_id": "r3", "kind": "left_mid_shift", "minutes_away": 35, "detected_at": self.at(0, "17:10"), "resolution": null, "suggested_deduction_piastres": 5_500 }
            ]),
            "/staff/adjustments" | "/staff/me/adjustments" => json!([
                { "id": "a1", "kind": "deduction", "user_id": "e4", "amount_piastres": 20_000, "reason": "Broke a glass", "created_by": "e2", "created_at": self.at(-3, "12:00"), "effective_date": self.d(-3), "status": "approved", "recurring": false, "source": "manual" },
                { "id": "a2", "kind": "bonus", "user_id": "e1", "amount_piastres": 150_000, "reason": "Best month", "created_by": "e2", "created_at": self.at(0, "09:00"), "effective_date": self.d(0), "status": "pending", "recurring": false, "source": "manual" }
            ]),
            "/staff/expense-advances" | "/staff/me/expense-advances" => json!([
                { "id": "x1", "user_id": "e1", "amount_piastres": 30_000, "given_on": self.d(-1), "branch_id": B1, "purpose": "Milk", "handed_by": "e2", "via": "cash" }
            ]),
            "/staff/swaps" => json!([]),
            "/staff/me/notifications" => json!([
                { "id": "n1", "key": "staff.n_week_published", "args": { "date": crate::dawam::week_start(self.today).to_string() }, "created_at": self.at(-2, "18:00"), "read_at": null },
                { "id": "n2", "key": "staff.n_request_approved", "args": { "kind": "late_arrival", "date": self.d(2) }, "created_at": self.at(-1, "12:00"), "read_at": self.at(-1, "13:00") }
            ]),
            "/staff/me/pay/estimate" => json!({ "period_start": "2026-08-26", "period_end": "2026-09-25", "slip": self.slip("e1", 900_000, 895_000), "advance_room_piastres": 400_000 }),
            "/staff/payroll/current" if role == "owner" => json!({
                "period": { "id": "p2", "start_date": "2026-08-26", "end_date": "2026-09-25", "status": "draft" },
                "preview": [self.slip("e1", 900_000, 895_000), self.slip("e4", 800_000, 745_000), self.slip("e2", 1_400_000, 1_400_000), self.slip("e5", 850_000, 850_000)],
                "payslips": [],
                "history": [{ "id": "p1", "start_date": "2026-07-26", "end_date": "2026-08-25", "status": "paid" }],
            }),
            "/staff/payroll/periods/p1/payslips" => json!([
                { "period_start": "2026-07-26", "user_id": "e1", "paid_method": "bank", "net_piastres": 850_000, "overtime_piastres": 0, "bonuses_piastres": 0, "deductions_piastres": 50_000, "advance_installment_piastres": 0, "breakdown": { "bonuses": [], "deductions": [], "advances": [] } }
            ]),
            "/staff/me/coverable" if !manager => json!([]),
            "/staff/roster/suggestions" => json!([
                { "id": "g1", "date": self.d(2), "user_id": "e4", "user_name": "Youssef Adel", "shift_name": "Evening", "work_shift_id": "zE", "reason_key": "staff.sg_gap", "reason_args": { "shift": "Evening", "short": 1 }, "confidence": 72, "by_default": true }
            ]),
            _ => json!([]),
        }
    }
}

/// `base` with `extra`'s keys laid over it.
fn with(mut base: Value, extra: Value) -> Value {
    for (k, v) in extra.as_object().unwrap() {
        base[k] = v.clone();
    }
    base
}

async fn snapshot_for(who: &str, role: &'static str) -> Value {
    let world = World { today: Utc::now().with_timezone(&chrono_tz::Africa::Cairo).date_naive() };
    let today = world.today;
    let stub = Stub::start(move |r| {
        let path = r.path.split('?').next().unwrap_or_default().to_string();
        let body = match path.as_str() {
            "/staff/me/payslips" => json!([with(world.slip("e1", 900_000, 850_000), json!({ "period_start": "2026-07-26", "period_end": "2026-08-25", "paid_method": "bank" }))]),
            p => world.answer(role, p),
        };
        Some(StubResponse::json(200, body))
    })
    .await;
    let core = online_core(&stub.base, "").await;
    if let Some(s) = core.session.write().unwrap().as_mut() {
        s.snapshot.user_id = who.to_string();
    }
    core.set_online(true);
    let mut v: Value = serde_json::from_str(&core.dawam_snapshot(true).await.unwrap()).unwrap();
    // The app's clock is the snapshot's `now`: pin it to 09:30 in Cairo so the
    // morning shift is on whatever time of day the fixtures are written.
    let nine = today.and_hms_opt(9, 30, 0).unwrap();
    let at = chrono::TimeZone::from_local_datetime(&chrono_tz::Africa::Cairo, &nine).single().unwrap();
    v["now"] = json!(at.with_timezone(&Utc).to_rfc3339());
    v
}

#[tokio::test(flavor = "multi_thread")]
async fn dawam_fixture_three_people_see_their_own_picture() {
    let e1 = snapshot_for("e1", "employee").await;
    let e2 = snapshot_for("e2", "manager").await;
    let e3 = snapshot_for("e3", "owner").await;

    // The employee: her own week, her requests and pay, no team.
    assert_eq!(e1["role"], "employee");
    assert!(!e1["can_manage"].as_bool().unwrap());
    assert!(e1["shifts"].as_array().unwrap().iter().any(|s| s["emp"] == "e1" && s["published"] == true));
    assert_eq!(e1["my_now"].as_array().unwrap().len(), 1, "today's morning shift");
    assert!(e1["slips"].as_array().unwrap().iter().any(|s| s["emp"] == "e1" && s["frozen"] == false), "the estimate");
    let notices: Vec<&str> = e1["notices"].as_array().unwrap().iter().filter_map(|n| n["text"].as_str()).collect();
    assert!(notices[0].contains("approved") && notices[1].contains("published"), "newest first, in words: {notices:?}");
    // The manager: the team's day, what waits on them, the flag.
    assert!(e2["can_manage"].as_bool().unwrap());
    let inbox: Vec<&str> = e2["inbox"].as_array().unwrap().iter().filter_map(Value::as_str).collect();
    assert!(inbox.contains(&"q|q1") && inbox.contains(&"v|v2"), "{inbox:?}");
    assert_eq!(e2["open_flags"], json!(["f1"]));
    let yesterday = e2["shifts"].as_array().unwrap().iter().find(|s| s["id"].as_str().unwrap().starts_with("e4|") && s["absent"] == true);
    assert!(yesterday.is_some(), "Youssef's missed evening reads absent");
    // The owner: payroll, and the adjustment over the manager's limit.
    assert!(e3["can_payroll"].as_bool().unwrap());
    assert_eq!(e3["adj_inbox"], json!(["a|bonus|a2"]));
    assert_eq!(e3["history"][0]["status"], "paid");
    assert_eq!(e3["slips"].as_array().unwrap().iter().filter(|s| s["frozen"] == false).count(), 4);

    if std::env::var("MADAR_WRITE_DAWAM_FIXTURES").is_ok() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../apps/staff/test/fixtures");
        std::fs::create_dir_all(&dir).unwrap();
        for (n, v) in [("e1", &e1), ("e2", &e2), ("e3", &e3)] {
            std::fs::write(dir.join(format!("{n}.json")), serde_json::to_string_pretty(v).unwrap()).unwrap();
        }
    }
}
