//! Cash spot check (owner design 2026-09-16 evening, item 5): the REAL
//! `MadarCore` against the REAL backend.
//!
//! ```sh
//! MADAR_OB_TESTS=cash_spot_backend tool/offline_b_backend.sh
//! ```
//!
//! * a manager takes a spot check OFFLINE; it lands once when back online and
//!   the server's report lists it;
//! * a teller without the grant gets a manager's one-time PIN for one check; the
//!   server stores who approved it and records a verified approval;
//! * a teller without the grant closes BLIND with a short drawer; the till lands
//!   in the owner's review queue (reconciliation disagreed).

mod common;

use common::*;

async fn org_of(fx: &Fixture) -> uuid::Uuid {
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    fx.db
        .query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch])
        .await
        .unwrap()
        .get(0)
}

/// A branch manager at the fixture's branch with their own PIN.
async fn manager(fx: &Fixture, pin: &str) -> (uuid::Uuid, String) {
    let id = uuid::Uuid::new_v4();
    let name = format!("SPOT-mgr-{}", &id.simple().to_string()[..6]);
    let org = org_of(fx).await;
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    fx.db
        .execute(
            "INSERT INTO users (id, org_id, name, role, pin_hash)
             VALUES ($1, $2, $3, 'branch_manager'::public.user_role, crypt($4, gen_salt('bf', 4)))",
            &[&id, &org, &name, &pin],
        )
        .await
        .unwrap();
    fx.db
        .execute(
            "INSERT INTO user_branch_assignments (user_id, branch_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
            &[&id, &branch],
        )
        .await
        .unwrap();
    (id, name)
}

async fn drain(core: &madar_core::MadarCore) {
    for _ in 0..40 {
        if core.sync_status().pending_outbox == 0 {
            break;
        }
        let _ = core.sync_now().await;
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    }
    let left = core.list_outbox().unwrap_or_default();
    assert!(left.is_empty(), "everything landed: {left:?}");
}

#[tokio::test]
#[ignore]
async fn a_manager_takes_a_spot_check_offline_and_it_lands_once() {
    let fx = fixture(0).await;
    let (_, mgr) = manager(&fx, "735102").await;
    let proxy = Proxy::start(&fx.base).await;
    let db = temp_db("spot-mgr");
    let core = signed_in_pin(&proxy.base, &db, &mgr, &fx.branch, "735102").await;
    core.refresh_connectivity().await;
    core.refresh_catalog().await.expect("catalog");
    core.sync_full().await.expect("snapshot");
    assert!(core.till_figures_visible(), "managers hold till.cash_spot_check by default");
    assert_eq!(core.cash_spot_access().outcome, "allow");

    let till_id = core.open_till(5_000, None).await.expect("open").till.expect("till").id;
    let cash = method(&core, true).expect("cash");
    sell(&core, 1, &cash, 1_000_000).await;
    settle(&core, 60).await;

    proxy.offline();
    for _ in 0..3 {
        core.refresh_connectivity().await;
    }
    let view = core.cash_spot_view(None).await.expect("live view offline");
    let counted = view.expected_cash_minor - 250;
    let done = core
        .record_cash_spot_check(counted, vec![], Some("offline count".into()), None)
        .await
        .expect("queued offline");
    assert_eq!(done.verdict, "short");
    assert_eq!(done.check.discrepancy_minor, -250);

    proxy.online();
    core.refresh_connectivity().await;
    drain(&core).await;

    let till = uuid::Uuid::parse_str(&till_id).unwrap();
    let rows = fx
        .db
        .query(
            "SELECT id, cash_discrepancy, approved_by FROM till_spot_checks WHERE till_id = $1",
            &[&till],
        )
        .await
        .unwrap();
    assert_eq!(rows.len(), 1, "one check, landed once");
    assert_eq!(rows[0].get::<_, i64>(1), -250);
    assert!(rows[0].get::<_, Option<uuid::Uuid>>(2).is_none());
    let flags: i64 = fx
        .db
        .query_one("SELECT COUNT(*) FROM authz_replay_flags WHERE op = 'CashSpotCheck'", &[])
        .await
        .unwrap()
        .get(0);
    assert_eq!(flags, 0, "a manager's check is not flagged");
    let report = server_report(&fx, &mgr, &till_id).await;
    assert_eq!(report.spot_checks.len(), 1, "the Z report lists it");
}

#[tokio::test]
#[ignore]
async fn a_tellers_one_time_pin_unlocks_one_spot_check() {
    let fx = fixture(1).await;
    let (teller_id, teller) = fx.tellers[0].clone();
    let (mgr_id, mgr) = manager(&fx, "864211").await;
    let db = temp_db("spot-pin");
    {
        // The manager signs in once here, so the bundle carries their verifier.
        let core = signed_in_pin(&fx.base, &db, &mgr, &fx.branch, "864211").await;
        core.logout(false).ok();
    }
    let core = core_at(&fx.base, &db, &teller, &fx.branch).await;
    let till_id = core.open_till(5_000, None).await.expect("open").till.expect("till").id;
    let cash = method(&core, true).expect("cash");
    sell(&core, 1, &cash, 1_000_000).await;
    settle(&core, 60).await;

    assert!(!core.till_figures_visible(), "a teller counts blind by default");
    assert_eq!(core.cash_spot_access().outcome, "needs_approval");
    assert!(core.cash_spot_view(None).await.is_err());
    assert!(core.approve_cash_spot("1234".into()).is_err(), "the teller cannot unlock it");
    let approval = core.approve_cash_spot("864211".into()).expect("the manager's PIN");
    assert_eq!(approval.approver_name, mgr);
    assert_eq!(core.current_session().expect("session").user_id, teller_id.to_string(), "the person did not change");

    let view = core.cash_spot_view(Some(approval.clone())).await.expect("unlocked view");
    core.record_cash_spot_check(view.expected_cash_minor, vec![], None, Some(approval.clone()))
        .await
        .expect("recorded");
    assert!(core.cash_spot_view(Some(approval)).await.is_err(), "one action only");
    drain(&core).await;

    let till = uuid::Uuid::parse_str(&till_id).unwrap();
    let row = fx
        .db
        .query_one(
            "SELECT checked_by, approved_by, cash_discrepancy FROM till_spot_checks WHERE till_id = $1",
            &[&till],
        )
        .await
        .unwrap();
    assert_eq!(row.get::<_, uuid::Uuid>(0), teller_id);
    assert_eq!(row.get::<_, Option<uuid::Uuid>>(1), Some(mgr_id));
    assert_eq!(row.get::<_, i64>(2), 0);
    let verified: bool = fx
        .db
        .query_one(
            "SELECT verified FROM approvals WHERE subject_user_id = $1 AND op = 'CashSpotCheck'",
            &[&teller_id],
        )
        .await
        .unwrap()
        .get(0);
    assert!(verified);
    let flags: i64 = fx
        .db
        .query_one(
            "SELECT COUNT(*) FROM authz_replay_flags WHERE author_id = $1 AND op = 'CashSpotCheck'",
            &[&teller_id],
        )
        .await
        .unwrap()
        .get(0);
    assert_eq!(flags, 0, "a verified approval is not a flag");
}

#[tokio::test]
#[ignore]
async fn a_blind_close_without_the_grant_flags_its_discrepancy() {
    let fx = fixture(1).await;
    let (_, teller) = fx.tellers[0].clone();
    let db = temp_db("spot-blind");
    let core = core_at(&fx.base, &db, &teller, &fx.branch).await;
    let till_id = core.open_till(5_000, None).await.expect("open").till.expect("till").id;
    let cash = method(&core, true).expect("cash");
    sell(&core, 1, &cash, 1_000_000).await;
    settle(&core, 60).await;

    assert!(!core.till_figures_visible());
    assert!(core.till_report_checked().await.is_err(), "no figures before the close");
    let preview = core.close_till_preview_checked().await.expect("preview");
    assert!(preview.figures_hidden);
    assert_eq!(preview.expected_cash_minor, 0);

    // What the drawer really holds, known only to the test.
    let expected = core.close_till_preview().await.expect("truth").expected_cash_minor;
    let counts = preview
        .methods
        .iter()
        .filter(|m| !m.is_cash)
        .map(|m| madar_core::till::ReconciliationInput {
            method: m.method.clone(),
            status: "counted".into(),
            declared_amount_minor: Some(0),
            note: None,
        })
        .collect();
    core.close_till(expected - 700, None, counts).await.expect("blind close");
    let after = core.till_report_checked().await.expect("the finished report after the close");
    assert!(!after.is_open);
    drain(&core).await;

    let till = uuid::Uuid::parse_str(&till_id).unwrap();
    let row = fx
        .db
        .query_one(
            "SELECT reconciliation_status, cash_discrepancy FROM tills WHERE id = $1",
            &[&till],
        )
        .await
        .unwrap();
    assert_eq!(row.get::<_, Option<String>>(0).as_deref(), Some("disagreed"), "in the review queue");
    assert_eq!(row.get::<_, Option<i32>>(1), Some(-700));
}
