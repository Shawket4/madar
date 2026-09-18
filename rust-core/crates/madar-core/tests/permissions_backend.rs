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
    // Each stage drops its core before the next opens the same device database.
    let online_teller = {
        let core = core_at(&proxy.base, &db, &teller, &fx.branch).await;
        let caps = core.capabilities();
        core.logout(false).ok();
        caps
    };

    // The manager signs in online once on this device too. The backend derives
    // an offline PIN verifier only on an online PIN login, so without this the
    // bundle lists them with a null hash and the unlock is refused with
    // "connect once to enable offline unlock" — which is the point of the
    // round trip, not a bug.
    {
        let core = core_at(&proxy.base, &db, &manager, &fx.branch).await;
        core.logout(false).ok();
    }

    // Sign the teller back in so the device re-fetches the bundle, now carrying
    // the manager's verifier, and ends up on the teller as it started.
    let core = core_at(&proxy.base, &db, &teller, &fx.branch).await;
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

/// Phase 5 (PERMISSIONS_ARCHITECTURE §4.2): the owner took voids away from a
/// teller and lets them ask a manager. On the till the void needs approval; a
/// manager types THEIR PIN on the same device; the void queues with the
/// approval, lands, and the server keeps a verified approval record.
#[tokio::test]
#[ignore]
async fn a_manager_approves_a_void_the_teller_may_only_ask_for() {
    let fx = fixture(1).await;
    let (teller_id, teller) = fx.tellers[0].clone();
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    let org: uuid::Uuid = fx
        .db
        .query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch])
        .await
        .unwrap()
        .get(0);
    // A manager with a PIN nobody else in the fixture shares.
    let manager_id = uuid::Uuid::new_v4();
    let manager = format!("PERM-approver-{}", &manager_id.simple().to_string()[..6]);
    fx.db
        .execute(
            "INSERT INTO users (id, org_id, name, role, pin_hash)
             VALUES ($1, $2, $3, 'branch_manager'::public.user_role, crypt('864209', gen_salt('bf', 4)))",
            &[&manager_id, &org, &manager],
        )
        .await
        .unwrap();
    fx.db
        .execute(
            "INSERT INTO user_branch_assignments (user_id, branch_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
            &[&manager_id, &branch],
        )
        .await
        .unwrap();
    // The owner's settings: no voids for this teller, but they may ask.
    let void_cap: i16 = 64;
    fx.db
        .execute(
            "INSERT INTO user_overrides (org_id, user_id, capability_id, effect, reason)
             VALUES ($1, $2, $3, 'deny', 'scenario')",
            &[&org, &teller_id, &void_cap],
        )
        .await
        .unwrap();
    fx.db
        .execute(
            "INSERT INTO org_capability_policy (org_id, capability_id, ask_manager) VALUES ($1, $2, true)
             ON CONFLICT (org_id, capability_id) DO UPDATE SET ask_manager = true",
            &[&org, &void_cap],
        )
        .await
        .unwrap();

    let db = temp_db("perm-approval");
    // The manager signs in online once on this device, so the bundle carries
    // their offline verifier; then the teller works the till.
    {
        let core = signed_in_pin(&fx.base, &db, &manager, &fx.branch, "864209").await;
        core.logout(false).ok();
    }
    let core = core_at(&fx.base, &db, &teller, &fx.branch).await;
    core.open_till(10_000, None).await.expect("open");
    let cash = method(&core, true).expect("cash");
    let sale = sell(&core, 1, &cash, 1_000_000).await;
    settle(&core, 60).await;

    let d = core.decide_order_act("orders.void".into(), sale.clone(), None);
    assert_eq!(d.outcome, "needs_approval", "{d:?}");
    assert!(core.approve_order_act("1234".into(), "orders.void".into(), sale.clone(), None).is_err(),
        "the teller cannot approve their own ask");
    let approval = core
        .approve_order_act("864209".into(), "orders.void".into(), sale.clone(), None)
        .expect("the manager approves");
    assert_eq!(approval.approver_name, manager);

    core.void_order_approved(sale.clone(), "customer_changed_mind".into(), None, false, Some(approval.clone()))
        .await
        .expect("void queues");
    for _ in 0..30 {
        if core.sync_status().pending_outbox == 0 {
            break;
        }
        let _ = core.sync_now().await;
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    }
    let left = core.list_outbox().unwrap_or_default();
    assert!(left.is_empty(), "the void landed: {left:?}");
    let row = fx
        .db
        .query_one(
            "SELECT verified, approver_user_id FROM approvals WHERE id = $1",
            &[&uuid::Uuid::parse_str(&approval.id).unwrap()],
        )
        .await
        .expect("the approval is on record");
    assert!(row.get::<_, bool>(0));
    assert_eq!(row.get::<_, uuid::Uuid>(1), manager_id);
}

/// Staging run 2, bug 2: an OWNER's PIN could not approve anything at a till.
/// An owner is provisioned all-branches with no legacy `user_branch_assignments`
/// row, and the device's offline auth bundle filtered on that legacy table alone,
/// so the owner was absent from every device's bundle — and the POS resolves an
/// approver's PIN against exactly that bundle.
///
/// This is the manager scenario with the approver swapped for an owner: a teller
/// is signed in at the till, a void the teller may only ask for is unlocked by
/// the OWNER's PIN, the void lands, and the record names the owner. It fails
/// against the pre-fix backend, where the owner never reaches the bundle and
/// `approve_order_act` cannot find them.
#[tokio::test]
#[ignore]
async fn an_owners_pin_approves_a_void_at_a_tellers_till() {
    let fx = fixture(1).await;
    let (teller_id, teller) = fx.tellers[0].clone();
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    let org: uuid::Uuid = fx
        .db
        .query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch])
        .await
        .unwrap()
        .get(0);

    // The owner: a PIN nobody else in the fixture shares, an email (owners are
    // dashboard people), and deliberately NO `user_branch_assignments` row.
    let owner_id = uuid::Uuid::new_v4();
    let owner = format!("PERM-owner-{}", &owner_id.simple().to_string()[..6]);
    fx.db
        .execute(
            "INSERT INTO users (id, org_id, name, email, password_hash, role, pin_hash, is_owner)
             VALUES ($1, $2, $3, $4, 'x', 'org_admin'::public.user_role,
                     crypt('730415', gen_salt('bf', 4)), true)",
            &[
                &owner_id,
                &org,
                &owner,
                &format!("{}@scenario.test", owner.to_lowercase()),
            ],
        )
        .await
        .expect("insert owner");
    // Assert the shape the bug lived in rather than building it by hand: the
    // owner's role assignment is auto-provisioned all-branches, with no legacy row.
    let shape = fx
        .db
        .query_one(
            "SELECT ra.all_branches,
                    (SELECT count(*) FROM user_branch_assignments a WHERE a.user_id = $1)
               FROM role_assignments ra
              WHERE ra.user_id = $1 AND ra.revoked_at IS NULL",
            &[&owner_id],
        )
        .await
        .expect("the owner holds a role assignment");
    assert!(
        shape.get::<_, bool>(0),
        "an owner is provisioned across all branches"
    );
    assert_eq!(
        shape.get::<_, i64>(1),
        0,
        "and holds no legacy branch assignment — the shape the bundle used to miss"
    );

    // The owner's settings: no voids for this teller, but they may ask.
    let void_cap: i16 = 64;
    fx.db
        .execute(
            "INSERT INTO user_overrides (org_id, user_id, capability_id, effect, reason)
             VALUES ($1, $2, $3, 'deny', 'scenario')",
            &[&org, &teller_id, &void_cap],
        )
        .await
        .unwrap();
    fx.db
        .execute(
            "INSERT INTO org_capability_policy (org_id, capability_id, ask_manager) VALUES ($1, $2, true)
             ON CONFLICT (org_id, capability_id) DO UPDATE SET ask_manager = true",
            &[&org, &void_cap],
        )
        .await
        .unwrap();

    let db = temp_db("perm-owner-approval");
    // ACTIVATE the device first. This matters: the offline auth bundle is scoped
    // by the `X-Madar-Device` header, and only a device the backend knows narrows
    // it to a branch. An unactivated core gets the whole org and would never see
    // the gap this scenario is here to cover.
    let code = format!("{:08}", owner_id.as_u128() % 100_000_000);
    fx.db
        .execute(
            "INSERT INTO device_activation_codes (org_id, branch_id, code, label)
             VALUES ($1, $2, $3, 'Owner-approval scenario tablet')",
            &[&org, &branch, &code],
        )
        .await
        .expect("insert activation code");
    {
        let core = madar_core::MadarCore::new(madar_core::MadarConfig {
            base_url: fx.base.clone(),
            environment: "dev".into(),
            db_path: db.clone(),
            locale: "en".into(),
            app_version: None,
        })
        .expect("core");
        let bound = core.activate_device(code).await.expect("activate");
        assert_eq!(bound.id, fx.branch);
    }
    // The owner signs in online once on this device so the backend derives their
    // offline PIN verifier; then the TELLER works the till, as in the shop.
    {
        let core = signed_in_pin(&fx.base, &db, &owner, &fx.branch, "730415").await;
        core.logout(false).ok();
    }
    // The bundle this device now holds is branch-scoped, and it must list the
    // owner: that is exactly what the pre-fix backend got wrong.

    let core = core_at(&fx.base, &db, &teller, &fx.branch).await;
    core.open_till(10_000, None).await.expect("open");
    let cash = method(&core, true).expect("cash");
    let sale = sell(&core, 1, &cash, 1_000_000).await;
    settle(&core, 60).await;

    let d = core.decide_order_act("orders.void".into(), sale.clone(), None);
    assert_eq!(d.outcome, "needs_approval", "{d:?}");
    let approval = core
        .approve_order_act("730415".into(), "orders.void".into(), sale.clone(), None)
        .expect("the OWNER's PIN unlocks the void");
    assert_eq!(
        approval.approver_name, owner,
        "the approval names the owner, not the teller"
    );

    core.void_order_approved(
        sale.clone(),
        "customer_changed_mind".into(),
        None,
        false,
        Some(approval.clone()),
    )
    .await
    .expect("void queues");
    for _ in 0..30 {
        if core.sync_status().pending_outbox == 0 {
            break;
        }
        let _ = core.sync_now().await;
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    }
    let left = core.list_outbox().unwrap_or_default();
    assert!(left.is_empty(), "the void landed: {left:?}");
    let row = fx
        .db
        .query_one(
            "SELECT verified, approver_user_id FROM approvals WHERE id = $1",
            &[&uuid::Uuid::parse_str(&approval.id).unwrap()],
        )
        .await
        .expect("the approval is on record");
    assert!(row.get::<_, bool>(0), "the server verified it");
    assert_eq!(
        row.get::<_, uuid::Uuid>(1),
        owner_id,
        "the record attributes the act to the owner"
    );
}
