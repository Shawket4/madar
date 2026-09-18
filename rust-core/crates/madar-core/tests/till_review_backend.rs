//! "N actions need a manager" against the REAL backend.
//!
//! ```sh
//! MADAR_OB_TESTS=till_review_backend tool/offline_b_backend.sh
//! ```
//!
//! What it proves, end to end:
//! * a teller sells offline with a discount their permissions no longer cover
//!   (the grant is pulled while the till is offline), the sale REPLAYS and is
//!   accepted-and-flagged — the money moved, so it is never rejected;
//! * the till PULLS that flag and lists it as "needs a manager", naming the
//!   act, who did it, and why;
//! * a manager's PIN on the till clears the batch through the real
//!   `POST /authz/flags/bulk-review`: `authz_replay_flags` is reviewed, with
//!   `review_note` naming the approver;
//! * re-submitting clears nothing more and raises no error (idempotent), and
//!   the till's indicator is back to zero.
//!
//! Note (stream 11): the bulk endpoint authorizes the BEARER, so the person
//! signed in at the till must hold `approvals.review` — here a branch manager
//! on the till. The teller-signed-in case is covered by the core's
//! `a_refused_bulk_call_keeps_the_re_sent_ops_and_repeats_the_servers_words`
//! until the server takes a one-time approval on this route.

mod common;

use common::*;
use madar_core::checkout::CheckoutInput;

fn input(method_id: &str) -> CheckoutInput {
    CheckoutInput {
        payment_method_id: method_id.to_string(),
        amount_tendered_minor: 10_000_000,
        tip_minor: 0,
        tip_payment_method_id: None,
        customer_name: None,
        notes: None,
        splits: vec![],
        loyalty_customer_id: None,
        dine_in: false,
        customer_id: None,
        loyalty_redemptions: vec![],
    }
}

async fn drained(core: &madar_core::MadarCore) {
    for _ in 0..30 {
        if core.sync_status().pending_outbox == 0 {
            break;
        }
        let _ = core.sync_now().await;
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    }
}

#[tokio::test]
#[ignore]
async fn a_flagged_offline_sale_is_listed_at_the_till_and_one_pin_clears_it() {
    let fx = fixture(1).await;
    let (teller_id, teller) = fx.tellers[0].clone();
    let branch = uuid::Uuid::parse_str(&fx.branch).unwrap();
    let org: uuid::Uuid = fx
        .db
        .query_one("SELECT org_id FROM branches WHERE id = $1", &[&branch])
        .await
        .unwrap()
        .get(0);

    // A branch manager who may review flags, signed in at the till.
    let manager_id = uuid::Uuid::new_v4();
    let manager = format!("REVIEW-mgr-{}", &manager_id.simple().to_string()[..6]);
    fx.db
        .execute(
            "INSERT INTO users (id, org_id, name, role, pin_hash)
             VALUES ($1, $2, $3, 'branch_manager'::public.user_role, crypt('864210', gen_salt('bf', 4)))",
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
    let approvals_review: i16 = 214;
    fx.db
        .execute(
            "INSERT INTO user_overrides (org_id, user_id, capability_id, effect, limits, reason)
             VALUES ($1, $2, $3, 'allow', '{}'::jsonb, 'scenario')
             ON CONFLICT DO NOTHING",
            &[&org, &manager_id, &approvals_review],
        )
        .await
        .unwrap();

    // The teller may take 5.00 off by hand — for now.
    let manual_amount: i16 = 205;
    fx.db
        .execute(
            "INSERT INTO user_overrides (org_id, user_id, capability_id, effect, limits, reason)
             VALUES ($1, $2, $3, 'allow', '{\"max_amount\": 500}'::jsonb, 'scenario')",
            &[&org, &teller_id, &manual_amount],
        )
        .await
        .unwrap();

    let db = temp_db("till_review");
    // The manager's PIN has to be on the device for an offline approval.
    {
        let seed = signed_in_pin(&fx.base, &db, &manager, &fx.branch, "864210").await;
        seed.logout(false).ok();
    }
    let core = core_at(&fx.base, &db, &teller, &fx.branch).await;
    core.open_till(10_000, None).await.expect("open");
    let cash = method(&core, true).expect("cash");
    let item = core
        .list_menu_items()
        .expect("items")
        .into_iter()
        .find(|i| i.base_price_minor > 1_000)
        .expect("an item over 10.00");
    core.cart_add(None, item.id.clone(), item.name.clone(), item.base_price_minor)
        .expect("add");
    core.apply_discount(None, "manual_amount".into(), None, Some(500), None, None)
        .expect("within the cap, offline");

    // The owner takes the grant away while the sale is still in the queue.
    fx.db
        .execute(
            "DELETE FROM user_overrides WHERE user_id = $1 AND capability_id = $2",
            &[&teller_id, &manual_amount],
        )
        .await
        .unwrap();
    fx.db
        .execute(
            "INSERT INTO user_overrides (org_id, user_id, capability_id, effect, limits, reason)
             VALUES ($1, $2, $3, 'deny', '{}'::jsonb, 'scenario')",
            &[&org, &teller_id, &manual_amount],
        )
        .await
        .unwrap();

    let sale = core.checkout(None, input(&cash)).await.expect("checkout");
    drained(&core).await;

    // The money moved, so the server kept the sale and flagged it.
    let flag: (i64, String, String) = {
        let r = fx
            .db
            .query_one(
                "SELECT id, capability, reason FROM authz_replay_flags
                  WHERE author_id = $1 AND reviewed_at IS NULL ORDER BY id DESC LIMIT 1",
                &[&teller_id],
            )
            .await
            .expect("the sale was accepted and flagged");
        (r.get(0), r.get(1), r.get(2))
    };
    assert_eq!(flag.2, "unauthorized_offline", "{flag:?}");
    assert!(!sale.local_order_id.is_empty());

    // A TELLER cannot even pull the flags: `GET /authz/flags` wants
    // `approvals.review` from the bearer. The till degrades quietly (the
    // indicator keeps whatever it last knew) rather than erroring at them.
    let refused_pull = core.refresh_review_flags().await;
    assert!(
        matches!(refused_pull, Err(madar_core::error::CoreError::Forbidden { .. })),
        "{refused_pull:?}"
    );
    core.logout(false).ok();

    // A manager signed in at the till pulls it, and the till says a manager is
    // needed, naming the act in the shop's words.
    let mgr_core = signed_in_pin(&fx.base, &db, &manager, &fx.branch, "864210").await;
    let n = mgr_core.refresh_review_flags().await.expect("pull the flags");
    assert!(n >= 1, "the flag reached the till");
    let view = mgr_core.pending_manager_actions();
    let listed = view
        .items
        .iter()
        .find(|i| i.id == format!("flag:{}", flag.0))
        .expect("the flagged sale is listed");
    assert_eq!(listed.kind, "flagged");
    assert_eq!(listed.what, "Discount over the cap");
    assert_eq!(listed.capability, flag.1);
    assert!(!listed.why.is_empty());
    assert!(view.headline.starts_with(&view.count.to_string()));

    // One PIN clears the batch.
    let res = mgr_core
        .authorize_manager_actions("864210".into(), vec![format!("flag:{}", flag.0)])
        .await
        .expect("authorize");
    assert_eq!(res.authorized, vec![format!("flag:{}", flag.0)], "{res:?}");
    assert!(res.left.is_empty(), "{:?}", res.left);

    let (reviewed_by, note): (Option<uuid::Uuid>, Option<String>) = {
        let r = fx
            .db
            .query_one(
                "SELECT reviewed_by, review_note FROM authz_replay_flags WHERE id = $1 AND reviewed_at IS NOT NULL",
                &[&flag.0],
            )
            .await
            .expect("the flag is resolved on the server");
        (r.get(0), r.get(1))
    };
    assert_eq!(reviewed_by, Some(manager_id));
    assert!(note.unwrap_or_default().contains(&manager), "the note names the approver");

    // Idempotent: the same batch again clears nothing more and never errors.
    mgr_core.refresh_review_flags().await.expect("pull");
    let again = mgr_core
        .authorize_manager_actions("864210".into(), vec![format!("flag:{}", flag.0)])
        .await
        .expect("a second pass is not an error");
    assert!(again.authorized.is_empty(), "{again:?}");
    assert!(again.left.is_empty(), "{again:?}");
    assert!(
        !mgr_core
            .pending_manager_actions()
            .items
            .iter()
            .any(|i| i.id == format!("flag:{}", flag.0)),
        "the indicator is back down"
    );
}
