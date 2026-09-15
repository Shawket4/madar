//! Architecture E permissions: the REAL `MadarCore` against the REAL backend.
//!
//! Ignored by `cargo test`. Run through the offline-B harness, which builds the
//! backend, copies a local database, starts the server and tears it down:
//!
//! ```sh
//! MADAR_OB_TESTS=permissions_backend tool/offline_b_backend.sh
//! ```
//!
//! What it proves:
//! * a branch manager and an owner sign in with a PIN at a branch and get their
//!   capabilities from `/authz/me` (force-close a till, see every drawer), and
//!   work the till shell;
//! * a teller signs in and holds selling but not force-close;
//! * a waiter-kind person routes to tables, not the till;
//! * offline, an unlock adopts the person's capabilities from the synced teller
//!   row (the same answers as online).

mod common;

use common::*;

async fn person(fx: &Fixture, role: &str, owner: bool) -> String {
    let id = uuid::Uuid::new_v4();
    let name = format!("PERM-{role}-{}", &id.simple().to_string()[..6]);
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    let org: uuid::Uuid = fx
        .db
        .query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch])
        .await
        .unwrap()
        .get(0);
    fx.db
        .execute(
            &format!(
                "INSERT INTO users (id, org_id, name, role, pin_hash, is_owner)
                 VALUES ($1, $2, $3, '{role}'::public.user_role, crypt('1234', gen_salt('bf', 4)), $4)"
            ),
            &[&id, &org, &name, &owner],
        )
        .await
        .expect("insert person");
    if role != "org_admin" {
        fx.db
            .execute(
                "INSERT INTO user_branch_assignments (user_id, branch_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                &[&id, &branch],
            )
            .await
            .expect("assign branch");
    }
    name
}

#[tokio::test]
#[ignore]
async fn managers_and_owners_sign_in_with_a_pin_and_get_their_capabilities() {
    let fx = fixture(1).await;
    let teller = fx.tellers[0].1.clone();
    let manager = person(&fx, "branch_manager", false).await;
    let owner = person(&fx, "org_admin", true).await;

    for (name, force_close) in [(&manager, true), (&owner, true), (&teller, false)] {
        let db = temp_db("perm");
        let core = signed_in(&fx.base, &db, name, &fx.branch).await;
        let caps = core.capabilities();
        assert!(
            caps.contains(&"pos.sign_in".to_string()) || name == &owner,
            "{name}: {caps:?}"
        );
        assert!(core.can("payments.take".into()), "{name} takes money");
        assert_eq!(
            core.can("till.force_close".into()),
            force_close,
            "{name}: force close"
        );
        assert_eq!(
            core.can("till.read.branch".into()),
            force_close,
            "{name}: every drawer"
        );
        assert_eq!(core.work_kind(), "teller", "{name} works the till shell");
        core.logout(false).ok();
    }
}

#[tokio::test]
#[ignore]
async fn a_waiter_routes_to_tables() {
    let fx = fixture(0).await;
    let waiter = person(&fx, "waiter", false).await;
    let db = temp_db("perm-waiter");
    let core = signed_in(&fx.base, &db, &waiter, &fx.branch).await;
    assert!(!core.can("payments.take".into()));
    assert!(core.can("tickets.open".into()));
    assert_eq!(core.work_kind(), "waiter");
}

#[tokio::test]
#[ignore]
async fn an_offline_unlock_adopts_capabilities_from_the_feed() {
    let fx = fixture(1).await;
    let teller = fx.tellers[0].1.clone();
    let manager = person(&fx, "branch_manager", false).await;
    let proxy = Proxy::start(&fx.base).await;
    let db = temp_db("perm-offline");
    // The teller signs in online (caches the offline bundle), the feed lands.
    let core = core_at(&proxy.base, &db, &teller, &fx.branch).await;
    let online_teller = core.capabilities();
    core.logout(false).ok();

    proxy.offline();
    core.refresh_connectivity().await;
    core.unlock_offline(manager.clone(), "1234".into(), fx.branch.clone())
        .expect("the manager unlocks offline");
    assert!(
        core.can("till.force_close".into()),
        "the manager's row carries force close"
    );
    assert!(core.can("payments.take".into()));
    core.logout(false).ok();

    core.unlock_offline(teller.clone(), "1234".into(), fx.branch.clone())
        .expect("the teller unlocks offline");
    assert!(!core.can("till.force_close".into()));
    let mut offline_teller = core.capabilities();
    let mut online = online_teller.clone();
    offline_teller.sort();
    online.sort();
    assert_eq!(
        offline_teller, online,
        "offline answers equal online answers"
    );
}
