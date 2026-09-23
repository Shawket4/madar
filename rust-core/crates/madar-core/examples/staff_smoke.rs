// Staff-app smoke check: drives every staff/manager call through madar-core against a
// LOCAL backend seeded by `cargo run --bin seed-staff-demo` (password Demo1234!).
//   cargo run -p madar-core --example staff_smoke [email]   (GEN=1 also runs payroll)
// Some FAILs are deliberate refusals (geofence, missing fields, no manager rights).
use madar_core::{MadarConfig, MadarCore};

macro_rules! probe {
    ($name:expr, $e:expr) => {
        match $e.await {
            Ok(v) => { let s = format!("{:?}", v); println!("OK   {:<28} {}", $name, &s[..s.len().min(160)]); Some(v) }
            Err(e) => { println!("FAIL {:<28} {:?}", $name, e); None }
        }
    };
}

#[tokio::main]
async fn main() {
    let who = std::env::args().nth(1).unwrap_or("admin@demo.madar".into());
    let db = std::env::temp_dir().join(format!("probe-{}.db", std::process::id()));
    let core = MadarCore::new(MadarConfig {
        base_url: "http://localhost:8082".into(), environment: "dev".into(),
        db_path: db.to_string_lossy().into(), locale: "en".into(), app_version: Some("probe".into()),
    }).unwrap();
    println!("== as {who}");
    let s = probe!("staff_sign_in", core.staff_sign_in(who.clone(), "Demo1234!".into()));
    let Some(s) = s else { return };
    println!("     branch={:?} role={} perms_loaded={} attendance:read={}", s.branch_id, s.role, s.permissions_loaded, core.has_permission("attendance".into(), "read".into()));
    let today = probe!("staff_today", core.staff_today());
    let branch = today.as_ref().map(|t| t.branch_id.clone()).filter(|b| !b.is_empty()).or(s.branch_id.clone()).unwrap_or_default();
    // Far from any fence → should be a clean refusal, not a decode error.
    probe!("staff_check_in(far)", core.staff_check_in(branch.clone(), Some(0.0), Some(0.0)));
    probe!("staff_check_in(onsite)", core.staff_check_in(branch.clone(), Some(30.0444), Some(31.2357)));
    probe!("staff_check_out", core.staff_check_out(Some(30.0444), Some(31.2357)));
    probe!("staff_attendance", core.staff_attendance("2026-08-20".into(), "2026-09-21".into()));
    probe!("staff_schedule", core.staff_schedule("2026-09-21".into(), "2026-09-28".into()));
    let reqs = probe!("staff_requests", core.staff_requests());
    probe!("staff_leave_balances", core.staff_leave_balances(None));
    probe!("staff_payslips", core.staff_payslips());
    probe!("staff_advances", core.staff_advances());
    probe!("create_request(late)", core.staff_create_request("late_arrival".into(), "2026-09-22".into(), None, Some("09:30".into()), None, None, false, None, Some("probe".into()), None));
    probe!("create_request(permission)", core.staff_create_request("permission".into(), "2026-09-23".into(), None, Some("12:00".into()), Some("13:00".into()), None, false, None, Some("probe".into()), None));
    if let Some(r) = probe!("staff_attendance(for fix)", core.staff_attendance("2026-09-01".into(), "2026-09-21".into())).and_then(|v| v.into_iter().next()) {
        probe!("create_request(correction)", core.staff_create_request("correction".into(), r.business_date, None, None, Some("17:00".into()), None, false, None, Some("probe".into()), Some(r.id)));
    }
    probe!("create_request(late ok)", core.staff_create_request("late_arrival".into(), "2026-09-24".into(), None, None, Some("09:30".into()), None, false, None, None, None));
    probe!("create_request(leave)", core.staff_create_request("leave".into(), "2026-10-01".into(), Some("2026-10-02".into()), None, None, None, false, None, None, None));
    probe!("request_advance", core.staff_request_advance(10000, 2, Some("probe".into())));
    let _ = reqs;
    // manager
    probe!("manager_team_presence", core.manager_team_presence(None));
    let q = probe!("manager_requests", core.manager_requests(Some("pending".into()), None));
    if let Some(r) = q.and_then(|v| v.into_iter().next()) { probe!("manager_decide_request", core.manager_decide_request(r.id, true, Some("ok".into()), None)); }
    let emps = probe!("manager_employees", core.manager_employees(None));
    let periods = probe!("manager_payroll_periods", core.manager_payroll_periods());
    if let Some(p) = periods.as_ref().and_then(|v| v.iter().find(|p| p.status == "draft")) {
        probe!("manager_payroll_preview", core.manager_payroll_preview(p.id.clone()));
    }
    if std::env::var("GEN").is_ok() { if let Some(p) = periods.as_ref().and_then(|v| v.iter().find(|p| p.name.starts_with("August"))) {
        probe!("manager_payroll_generate", core.manager_payroll_generate(p.id.clone()));
        probe!("manager_payroll_set_status", core.manager_payroll_set_status(p.id.clone(), "paid".into()));
    } }
    probe!("manager_adjustments(ded)", core.manager_adjustments(true, None, None, None, 0));
    probe!("manager_adjustments(bon)", core.manager_adjustments(false, None, None, None, 0));
    // Creating adjustments and deciding advances moved to the Dawam acts
    // (`/staff/adjustments`, `/staff/advances/record`); see dawam.rs.
    let _ = emps;
    let adv = probe!("manager_advances", core.manager_advances());
    let _ = adv;
    let _ = std::fs::remove_file(db);
}
