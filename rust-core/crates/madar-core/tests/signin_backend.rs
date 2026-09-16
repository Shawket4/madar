//! The POS sign-in overhaul (POS_SIGNIN_OVERHAUL.md §3.4, §4, §8.5): the REAL
//! `MadarCore` against the REAL backend.
//!
//! Ignored by `cargo test`. Run through the offline-B harness:
//!
//! ```sh
//! MADAR_OB_TESTS=signin_backend tool/offline_b_backend.sh
//! ```
//!
//! One test on purpose: `/auth/login` is behind a per-address governor (ten
//! calls, then one every six seconds), and every call below is budgeted.
//!
//! What it proves, on one fresh device:
//! * an activation code from the dashboard binds the device to its branch with
//!   no person involved;
//! * wrong PINs earn the growing delay, the refusal names the wait, and the core
//!   keeps it for the PIN pad's countdown;
//! * once the wait is over, the PIN ALONE signs the right person in (no name on
//!   the wire), and that clears the wait.

mod common;

use common::*;
use madar_core::error::CoreError;
use madar_core::session::{LoginMode, LoginRequest};
use std::time::Duration;

fn pin_only(pin: &str) -> LoginRequest {
    LoginRequest {
        mode: LoginMode::Pin,
        name: None,
        pin: Some(pin.into()),
        branch_id: None, // the core fills in the device's bound branch
        email: None,
        password: None,
        org_id: None,
    }
}

#[tokio::test]
#[ignore]
async fn a_code_binds_the_device_wrong_pins_wait_and_the_pin_alone_signs_in() {
    let fx = fixture(0).await;
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    let org: uuid::Uuid = fx
        .db
        .query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch])
        .await
        .unwrap()
        .get(0);

    // A person with an org-unique six-digit PIN.
    let id = uuid::Uuid::new_v4();
    let name = format!("SIGNIN-{}", &id.simple().to_string()[..6]);
    let pin = format!("{:06}", (id.as_u128() % 900_000) + 100_000);
    fx.db
        .execute(
            "INSERT INTO users (id, org_id, name, role, pin_hash)
             VALUES ($1, $2, $3, 'teller'::public.user_role, crypt($4, gen_salt('bf', 4)))",
            &[&id, &org, &name, &pin],
        )
        .await
        .expect("insert person");

    // The dashboard's side, straight into the table: a free code for the branch.
    let code = format!("{:08}", id.as_u128() % 100_000_000);
    fx.db
        .execute(
            "INSERT INTO device_activation_codes (org_id, branch_id, code, label)
             VALUES ($1, $2, $3, 'Scenario tablet')",
            &[&org, &branch, &code],
        )
        .await
        .expect("insert code");

    let core = madar_core::MadarCore::new(madar_core::MadarConfig {
        base_url: fx.base.clone(),
        environment: "dev".into(),
        db_path: temp_db("signin"),
        locale: "en".into(),
        app_version: None,
    })
    .expect("core");
    assert!(core.device_config().branch_id.is_none(), "a fresh device");

    let bound = core.activate_device(code.clone()).await.expect("activate");
    assert_eq!(bound.id, fx.branch);
    assert_eq!(core.device_config().branch_id.as_deref(), Some(fx.branch.as_str()));
    // Single use.
    assert!(matches!(
        core.activate_device(code).await,
        Err(CoreError::Validation { .. })
    ));

    // Four misses are free and the fifth trips the delay; the sixth is refused
    // with the wait before any lookup.
    let wrong = if pin == "999999" { "999998" } else { "999999" };
    for i in 0..5 {
        match core.sign_in(pin_only(wrong)).await {
            Err(CoreError::Unauthenticated { .. }) => {}
            other => panic!("miss {i}: expected a plain refusal, got {other:?}"),
        }
    }
    match core.sign_in(pin_only(wrong)).await {
        Err(CoreError::Server { status: 429, code, detail }) => {
            assert_eq!(code, "PIN_THROTTLED");
            let secs: i64 = detail.parse().expect("seconds");
            assert!((1..=5).contains(&secs), "{secs}");
        }
        other => panic!("expected the delay, got {other:?}"),
    }
    let wait = core.pin_wait_seconds();
    assert!((1..=5).contains(&wait), "the pad counts down from {wait}");

    tokio::time::sleep(Duration::from_secs(u64::from(wait) + 1)).await;
    let session = core.sign_in(pin_only(&pin)).await.expect("the PIN alone");
    assert_eq!(session.display_name, name);
    assert!(session.online);
    assert_eq!(core.pin_wait_seconds(), 0, "a correct PIN clears the wait");
    core.logout(false).ok();
}
