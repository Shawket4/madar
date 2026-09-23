//! The batch flow: full success, partial, none allowed, idempotent re-submit,
//! and the list offline.
use serde_json::json;

use crate::store;
use crate::testkit::{self, Stub, StubResponse, BRANCH, TELLER};

const MANAGER: &str = "00000000-0000-0000-0000-0000000000cc";

/// Add a manager to the offline bundle (PIN 9999) and give them grants the
/// approval path can read (the teller row the pull caches).
fn add_manager(core: &crate::MadarCore, caps: &[&str]) {
    use argon2::password_hash::SaltString;
    use argon2::{Argon2, PasswordHasher};
    let salt = SaltString::encode_b64(b"madar-test-salt").unwrap();
    let phc = Argon2::default().hash_password(b"9999", &salt).unwrap().to_string();
    let raw = core.store.kv_get(crate::session::BUNDLE_KEY).unwrap().unwrap();
    let mut bundle: serde_json::Value = serde_json::from_str(&raw).unwrap();
    bundle["tellers"].as_array_mut().unwrap().push(json!({
        "user_id": MANAGER, "name": "Mona", "role": "branch_manager",
        "is_active": true, "offline_pin_hash": phc
    }));
    core.store.kv_put(crate::session::BUNDLE_KEY, &bundle.to_string()).unwrap();
    let row = json!({ "id": MANAGER, "capabilities": caps, "ask_manager": [], "limits": {}, "is_owner": false });
    core.store
        .with_conn(|c| {
            c.execute(
                "INSERT OR REPLACE INTO sync_rows(type,id,branch_id,seq,data) VALUES('teller',?1,?2,1,?3)",
                rusqlite::params![MANAGER, BRANCH, row.to_string()],
            )?;
            Ok(())
        })
        .unwrap();
}

/// Queue an op and let the server have refused it for `cap`.
fn refused(core: &crate::MadarCore, op_type: &str, payload: serde_json::Value, cap: &str) -> i64 {
    core.store
        .enqueue(&store::NewOutboxOp {
            id: uuid::Uuid::new_v4().to_string(),
            op_type: op_type.into(),
            idempotency_key: uuid::Uuid::new_v4().to_string(),
            payload: payload.to_string(),
            event_at: "2026-09-17T10:00:00Z".into(),
            depends_on_seq: None,
            user_id: Some(TELLER.into()),
            clock_offset_ms: None,
            till_id: None,
            ..Default::default()
        })
        .unwrap();
    let seq = core.store.list_active().unwrap().last().unwrap().seq;
    core.store.mark_dead_refused(seq, "needs a manager", cap).unwrap();
    seq
}

fn cache_flag(core: &crate::MadarCore, id: i64, cap: &str, reason: &str) {
    let mut flags: Vec<serde_json::Value> = core
        .store
        .kv_get("review:flags")
        .unwrap()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();
    flags.push(json!({
        "id": id, "branch_id": BRANCH, "op": "CreateOrder", "author_name": "Sara",
        "capability": cap, "reason": reason, "occurred_at": "2026-09-17T09:00:00Z"
    }));
    core.store.kv_put("review:flags", &serde_json::to_string(&flags).unwrap()).unwrap();
}

#[test]
fn the_capability_of_a_refused_op_comes_from_its_type_and_its_discount_kind() {
    use super::capability_for_op;
    assert_eq!(capability_for_op("void_order", "{}"), Some("orders.void"));
    assert_eq!(capability_for_op("refund_order", "{}"), Some("refunds.create"));
    assert_eq!(capability_for_op("record_waste", "{}"), Some("inventory.waste.record"));
    // The payloads' flat `discount_*` fields (real payloads built through the
    // checkout are pinned in `checkout.rs`).
    assert_eq!(
        capability_for_op(
            "create_order",
            &json!({"request":{"discount_kind":"manual_percent","discount_type":"percentage","discount_value":0.1}})
                .to_string()
        ),
        Some("orders.discount.manual_percent")
    );
    assert_eq!(
        capability_for_op(
            "settle_open_ticket",
            &json!({"ticket_id":"t","request":{"discount_kind":"preset","discount_id":"00000000-0000-0000-0000-0000000000d1"}})
                .to_string()
        ),
        Some("orders.discount.preset")
    );
    // A sale with no discount is never refused for one — and an op no
    // permission gates stays an ordinary dead letter.
    assert_eq!(capability_for_op("create_order", "{}"), None);
    assert_eq!(capability_for_op("open_till", "{}"), None);
}

#[tokio::test]
async fn the_list_works_offline_and_says_it_needs_a_connection() {
    let stub = Stub::start(|_| None).await;
    let core = testkit::offline_core(&stub.base, "").await;
    refused(&core, "void_order", json!({"order_id":"o1","amount_minor":500}), "orders.void");
    cache_flag(&core, 7, "orders.discount.manual_amount", "unauthorized_offline");

    let v = core.pending_manager_actions();
    assert_eq!(v.count, 2, "both halves show with no network");
    assert!(v.headline.starts_with("2 "), "{}", v.headline);
    assert!(!v.can_authorize);
    assert!(v.blocked_reason.contains("Connect"), "{}", v.blocked_reason);
    // Oldest first: the flag happened at 09:00, the refusal at 10:00.
    assert_eq!(v.items[0].kind, "flagged");
    assert_eq!(v.items[0].what, "Discount over the cap");
    assert_eq!(v.items[1].kind, "refused");
    assert_eq!(v.items[1].what, "Void");
    assert_eq!(v.items[1].amount_minor, Some(500));
    assert_eq!(v.items[1].person_name, "Sara");

    // Nothing can be authorized without a connection, and it says why.
    let err = core.authorize_manager_actions("9999".into(), vec![]).await.unwrap_err();
    assert!(matches!(err, crate::error::CoreError::Offline { .. }), "{err:?}");
}

#[tokio::test]
async fn one_pin_clears_the_whole_batch_and_the_refused_op_goes_back_in_the_queue() {
    let stub = Stub::start(|r| {
        if r.path.starts_with("/authz/flags/bulk-review") {
            let body: serde_json::Value = serde_json::from_str(&r.body).unwrap();
            let ids = body["flag_ids"].clone();
            return Some(StubResponse::json(200, json!({ "resolved": ids, "pending": [] })));
        }
        None
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    core.set_online(true);
    add_manager(&core, &["orders.void", "orders.discount.manual_amount", "approvals.review"]);
    let seq = refused(&core, "void_order", json!({"order_id":"o1","amount_minor":500}), "orders.void");
    cache_flag(&core, 7, "orders.discount.manual_amount", "unauthorized_offline");

    let res = core.authorize_manager_actions("9999".into(), vec![]).await.unwrap();
    assert_eq!(res.authorized.len(), 2, "{res:?}");
    assert!(res.left.is_empty(), "{:?}", res.left);
    assert_eq!(res.summary, "2 of 2");

    // The refused op is queued again, carrying the approver's id — it was never
    // re-created, so its seq (and its place in the FIFO) is the same row.
    let back = core.store.list_active().unwrap().into_iter().find(|o| o.seq == seq).unwrap();
    assert_eq!(back.status, "pending");
    assert_eq!(back.attempts, 0);
    let p: serde_json::Value = serde_json::from_str(&back.payload).unwrap();
    assert_eq!(p["approval"]["approver_id"], MANAGER);
    assert_eq!(p["approval"]["capability"], "orders.void");
    assert!(core.store.refused_ops().unwrap().is_empty(), "no refusal left");

    // The note names the approver, so the dashboard's queue shows who cleared it.
    let sent = stub.requests("/authz/flags/bulk-review");
    assert_eq!(sent.len(), 1, "one call for every flag");
    assert!(sent[0].json()["note"].as_str().unwrap().contains("Mona"));
    assert_eq!(core.pending_manager_actions().count, 0);
}

#[tokio::test]
async fn what_this_approver_cannot_cover_stays_listed_with_its_reason() {
    let stub = Stub::start(|r| {
        if r.path.starts_with("/authz/flags/bulk-review") {
            // The server resolved one and left the other.
            return Some(StubResponse::json(
                200,
                json!({ "resolved": [7], "pending": [{ "id": 8, "reason": "no such open flag in this org" }] }),
            ));
        }
        None
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    core.set_online(true);
    // A manager who may clear discounts but NOT refunds.
    add_manager(&core, &["orders.discount.manual_amount"]);
    refused(&core, "refund_order", json!({"order_id":"o1","amount_minor":900}), "refunds.create");
    cache_flag(&core, 7, "orders.discount.manual_amount", "unauthorized_offline");
    cache_flag(&core, 8, "orders.discount.manual_amount", "unauthorized_offline");

    let res = core.authorize_manager_actions("9999".into(), vec![]).await.unwrap();
    assert_eq!(res.authorized, vec!["flag:7"]);
    assert_eq!(res.left.len(), 2, "{:?}", res.left);
    let refund = res.left.iter().find(|i| i.capability == "refunds.create").unwrap();
    assert!(!refund.why.is_empty(), "the refusal names why this approver cannot");
    let left_flag = res.left.iter().find(|i| i.id == "flag:8").unwrap();
    assert_eq!(left_flag.why, "no such open flag in this org");
    assert_eq!(res.summary, "1 of 3");

    // Nothing was dropped: the refund is still refused, flag 8 still cached.
    let after = core.pending_manager_actions();
    assert_eq!(after.count, 2);
    assert_eq!(core.store.refused_ops().unwrap().len(), 1);
}

#[tokio::test]
async fn an_approver_who_covers_nothing_clears_nothing_and_the_list_is_intact() {
    let stub = Stub::start(|_| None).await;
    let core = testkit::online_core(&stub.base, "").await;
    core.set_online(true);
    add_manager(&core, &["reports.pos_metrics"]);
    refused(&core, "void_order", json!({"order_id":"o1"}), "orders.void");
    cache_flag(&core, 7, "refunds.create", "unauthorized_offline");

    let res = core.authorize_manager_actions("9999".into(), vec![]).await.unwrap();
    assert!(res.authorized.is_empty());
    assert_eq!(res.left.len(), 2);
    assert_eq!(res.summary, "0 of 2");
    // The server was never asked to resolve anything.
    assert!(stub.requests("/authz/flags/bulk-review").is_empty());
    assert_eq!(core.pending_manager_actions().count, 2);
}

#[tokio::test]
async fn re_submitting_the_same_batch_is_a_no_op() {
    let stub = Stub::start(|r| {
        if r.path.starts_with("/authz/flags/bulk-review") {
            let body: serde_json::Value = serde_json::from_str(&r.body).unwrap();
            // The server is idempotent: an already-reviewed id resolves again.
            return Some(StubResponse::json(200, json!({ "resolved": body["flag_ids"], "pending": [] })));
        }
        None
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    core.set_online(true);
    add_manager(&core, &["orders.void"]);
    let seq = refused(&core, "void_order", json!({"order_id":"o1"}), "orders.void");
    cache_flag(&core, 7, "orders.void", "unauthorized_offline");

    let first = core.authorize_manager_actions("9999".into(), vec![]).await.unwrap();
    assert_eq!(first.authorized.len(), 2);
    let again = core.authorize_manager_actions("9999".into(), vec![]).await.unwrap();
    assert!(again.authorized.is_empty(), "nothing is left to clear");
    assert!(again.left.is_empty());
    // One call, one requeue: the second pass found nothing and changed nothing.
    assert_eq!(stub.requests("/authz/flags/bulk-review").len(), 1);
    let back = core.store.list_active().unwrap().into_iter().find(|o| o.seq == seq).unwrap();
    assert_eq!(back.status, "pending");
}

#[tokio::test]
async fn only_the_picked_items_are_authorized() {
    let stub = Stub::start(|_| None).await;
    let core = testkit::online_core(&stub.base, "").await;
    core.set_online(true);
    add_manager(&core, &["orders.void", "refunds.create"]);
    let void_seq = refused(&core, "void_order", json!({"order_id":"o1"}), "orders.void");
    refused(&core, "refund_order", json!({"order_id":"o2"}), "refunds.create");

    let res = core
        .authorize_manager_actions("9999".into(), vec![format!("op:{void_seq}")])
        .await
        .unwrap();
    assert_eq!(res.authorized, vec![format!("op:{void_seq}")]);
    assert!(res.left.is_empty(), "an item nobody picked is not a failure");
    assert_eq!(core.pending_manager_actions().count, 1, "the refund is untouched");
}

#[tokio::test]
async fn a_wrong_pin_is_one_refusal_for_the_batch_not_a_per_item_reason() {
    let stub = Stub::start(|_| None).await;
    let core = testkit::online_core(&stub.base, "").await;
    core.set_online(true);
    add_manager(&core, &["orders.void"]);
    refused(&core, "void_order", json!({"order_id":"o1"}), "orders.void");
    let err = core.authorize_manager_actions("0000".into(), vec![]).await.unwrap_err();
    assert!(matches!(err, crate::error::CoreError::Unauthenticated { .. }), "{err:?}");
    assert_eq!(core.pending_manager_actions().count, 1);
}

#[tokio::test]
async fn a_pull_keeps_only_this_branch_s_flags() {
    let stub = Stub::start(|r| {
        if r.path.starts_with("/authz/flags") {
            return Some(StubResponse::json(
                200,
                json!([
                    { "id": 1, "branch_id": BRANCH, "op": "CreateOrder", "author_id": TELLER, "author_name": "Sara",
                      "capability": "orders.void", "reason": "unauthorized_offline",
                      "occurred_at": "2026-09-17T09:00:00Z", "created_at": "2026-09-17T09:00:01Z" },
                    { "id": 2, "branch_id": "00000000-0000-0000-0000-00000000dead", "op": "CreateOrder", "author_id": TELLER,
                      "capability": "orders.void", "reason": "unauthorized_offline",
                      "occurred_at": "2026-09-17T09:00:00Z", "created_at": "2026-09-17T09:00:01Z" },
                    { "id": 3, "branch_id": null, "op": "Pin", "author_id": TELLER,
                      "capability": "orders.void", "reason": "pin_wrong_branch",
                      "occurred_at": "2026-09-17T09:00:00Z", "created_at": "2026-09-17T09:00:01Z" }
                ]),
            ));
        }
        None
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    let n = core.refresh_review_flags().await.unwrap();
    assert_eq!(n, 2, "this branch's flag and the branch-less one");
    let v = core.pending_manager_actions();
    assert_eq!(v.count, 2);
    assert!(v.items.iter().any(|i| i.why.contains("branch they don't work at")));
}

#[tokio::test]
async fn the_list_speaks_arabic() {
    let stub = Stub::start(|_| None).await;
    let core = testkit::offline_core(&stub.base, "").await;
    core.set_locale("ar".into());
    refused(&core, "record_waste", json!({"value_minor":100}), "inventory.waste.record");
    let v = core.pending_manager_actions();
    assert_eq!(v.items[0].what, "تالف");
    assert!(v.headline.contains("عملية محتاجة مدير"), "{}", v.headline);
    assert!(v.blocked_reason.contains("نت"), "{}", v.blocked_reason);
}

/// The server refuses the flags half — today that means the APPROVER does not
/// hold `approvals.review` (the routes take the one-time approval since
/// 2026-09-18). That must not cost the refusals, which were already re-queued
/// with the approval: they stay authorized and the flags come back with the
/// server's own words.
#[tokio::test]
async fn a_refused_bulk_call_keeps_the_re_sent_ops_and_repeats_the_servers_words() {
    let stub = Stub::start(|r| {
        if r.path.starts_with("/authz/flags/bulk-review") {
            return Some(StubResponse::json(
                403,
                json!({ "error": "missing permission: approvals.review" }),
            ));
        }
        None
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    core.set_online(true);
    add_manager(&core, &["orders.void", "approvals.review"]);
    let seq = refused(&core, "void_order", json!({"order_id":"o1"}), "orders.void");
    cache_flag(&core, 7, "orders.void", "unauthorized_offline");

    let res = core.authorize_manager_actions("9999".into(), vec![]).await.unwrap();
    assert_eq!(res.authorized, vec![format!("op:{seq}")], "the re-send stands");
    assert_eq!(res.left.len(), 1);
    assert!(res.left[0].why.contains("approvals.review"), "{}", res.left[0].why);
    assert_eq!(res.summary, "1 of 2");
    // The op really is back in the queue with its approval.
    let back = core.store.list_active().unwrap().into_iter().find(|o| o.seq == seq).unwrap();
    assert_eq!(back.status, "pending");
    assert!(back.payload.contains("approver_id"));
}

/// The other half of the same story (backend, 2026-09-18): with a TELLER signed
/// in at the till, the minted approval rides both the `GET /authz/flags` pull
/// and the bulk review, the batch fully works, and the server is told who
/// approved. `add_manager` gives Mona `approvals.review`; the signed-in person
/// (Sara) never changes.
#[tokio::test]
async fn a_teller_till_clears_its_flags_with_the_managers_approval_on_the_wire() {
    let stub = Stub::start(|r| {
        if r.path.starts_with("/authz/flags/bulk-review") {
            let body: serde_json::Value = serde_json::from_str(&r.body).unwrap_or_default();
            // Exactly what the backend does: no approval and this teller is
            // refused; a valid one and the flags clear.
            return Some(match body.get("approval") {
                Some(_) => StubResponse::json(200, json!({ "resolved": [7], "pending": [] })),
                None => StubResponse::json(
                    403,
                    json!({ "error": "missing permission: approvals.review" }),
                ),
            });
        }
        if r.path.starts_with("/authz/flags") {
            return Some(if r.path.contains("approval=") {
                StubResponse::json(
                    200,
                    json!([{ "id": 7, "branch_id": BRANCH, "op": "CreateOrder",
                             "author_id": TELLER, "author_name": "Sara",
                             "capability": "orders.void", "reason": "unauthorized_offline",
                             "occurred_at": "2026-09-17T09:00:00Z",
                             "created_at": "2026-09-17T09:00:00Z" }]),
                )
            } else {
                StubResponse::json(403, json!({ "error": "missing permission: approvals.review" }))
            });
        }
        None
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    core.set_online(true);
    add_manager(&core, &["orders.void", "approvals.review"]);
    let seq = refused(&core, "void_order", json!({"order_id":"o1"}), "orders.void");
    cache_flag(&core, 7, "orders.void", "unauthorized_offline");

    // The plain pull is still refused for a teller — nothing was weakened.
    assert!(core.refresh_review_flags().await.is_err());

    let res = core.authorize_manager_actions("9999".into(), vec![]).await.unwrap();
    assert_eq!(res.left, vec![], "nothing left over: {:?}", res.left);
    assert_eq!(res.authorized.len(), 2, "the re-send AND the flag");
    assert!(res.authorized.contains(&format!("op:{seq}")));
    assert!(res.authorized.contains(&"flag:7".to_string()));
    assert_eq!(res.summary, "2 of 2");

    // The pull carried the approval...
    let pulls = stub.requests("/authz/flags?");
    assert!(
        pulls.iter().any(|r| r.path.contains("approval=")),
        "the GET pull carries the minted approval: {:?}",
        pulls.iter().map(|r| r.path.clone()).collect::<Vec<_>>()
    );
    // ...and so did the bulk call, naming Mona as the approver, for Sara's act.
    let calls = stub.requests("/authz/flags/bulk-review");
    let body: serde_json::Value = serde_json::from_str(&calls.last().unwrap().body).unwrap();
    assert_eq!(body["approval"]["capability"], "approvals.review");
    assert_eq!(body["approval"]["approver_id"], MANAGER);
    assert!(
        body["note"].as_str().unwrap().contains(MANAGER),
        "the note names the approver: {}",
        body["note"]
    );
    assert_eq!(body["flag_ids"], json!([7]));

    // The cleared flag is gone from the local cache straight away.
    let left: Vec<serde_json::Value> = core
        .store
        .kv_get("review:flags")
        .unwrap()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();
    assert!(left.is_empty(), "the indicator falls without waiting for a pull");
}

/// An approver who does NOT hold `approvals.review` mints no approval, so the
/// call goes out plain and the server's 403 stands — partial results stay
/// honest and the refusal half is still settled.
#[tokio::test]
async fn an_approver_without_the_review_right_still_gets_the_servers_403_on_the_flags() {
    let stub = Stub::start(|r| {
        if r.path.starts_with("/authz/flags/bulk-review") {
            let body: serde_json::Value = serde_json::from_str(&r.body).unwrap_or_default();
            assert!(body.get("approval").is_none(), "nothing to send");
            return Some(StubResponse::json(
                403,
                json!({ "error": "missing permission: approvals.review" }),
            ));
        }
        None
    })
    .await;
    let core = testkit::online_core(&stub.base, "").await;
    core.set_online(true);
    add_manager(&core, &["orders.void"]);
    let seq = refused(&core, "void_order", json!({"order_id":"o1"}), "orders.void");
    cache_flag(&core, 7, "orders.void", "unauthorized_offline");

    let res = core.authorize_manager_actions("9999".into(), vec![]).await.unwrap();
    assert_eq!(res.authorized, vec![format!("op:{seq}")]);
    assert_eq!(res.left.len(), 1);
    assert!(res.left[0].why.contains("approvals.review"), "{}", res.left[0].why);
}
