//! Manual customers on the till (phase 6): search, add and attach, offline.
//!
//! The list is the feed's `customer` rows (org-wide). A customer added here is
//! written into that same local list at once and queued as `create_customer`
//! with a client-minted id, so it can be attached to a sale before the server
//! has heard of it. The server stores a duplicate phone merged into the live
//! holder and resolves the id on the order, so nothing here dedupes.
//!
//! PDPL: the phone is shown only to `customers.view` holders. Anyone who may
//! attach may still FIND a customer by typing their phone.

use serde::{Deserialize, Serialize};

use crate::error::CoreError;
use crate::MadarCore;

const TYPE: &str = "customer";
const MAX_RESULTS: usize = 50;
/// kv prefix: the customer this device attached to a rung sale, by order key.
const ORDER_CUSTOMER_KV: &str = "order_customer:";

/// A customer as the till shows it.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CustomerView {
    pub id: String,
    pub name: String,
    /// `None` without `customers.view`, or when there is no phone.
    pub phone: Option<String>,
    /// Masked for someone who may not see it, e.g. `•••• 4567`.
    pub phone_hint: Option<String>,
    /// The id their loyalty balance lives under, when they are a member. Under
    /// the shared key this IS `id`; a server that predates it may still name a
    /// different one. Either way: `Some` means "offer their loyalty".
    pub loyalty_customer_id: Option<String>,
    /// Added on this till and not yet confirmed by the server.
    pub pending: bool,
    /// A loyalty member. A server that predates the flag says it by sending
    /// `loyalty_customer_id` alone.
    pub is_member: bool,
    /// The balance as the feed last carried it, in words ("120 points").
    /// `None` for a non-member and for a server that does not send balances.
    /// A hint for the picker only — spending goes through a live lookup.
    pub balance_label: Option<String>,
    /// Where the customer first came from (`pos`, `online`, `loyalty`, …).
    pub source: Option<String>,
}

/// The canonical key a phone is matched by (see [`crate::phone`]).
pub(crate) fn phone_key(phone: &str) -> Option<String> {
    crate::phone::canonical(phone)
}

/// The key a ROW is matched by. Derived from its `phone` rather than trusted
/// from its stored `phone_key`: a server that predates the canonical form still
/// sends the local `01…` key, and both must meet a query in the same form.
fn row_key(row: &serde_json::Value) -> Option<String> {
    let s = |k: &str| row.get(k).and_then(|v| v.as_str());
    s("phone")
        .and_then(phone_key)
        .or_else(|| s("phone_key").and_then(phone_key))
        // Not a number the rule accepts: still findable by the digits it has.
        .or_else(|| s("phone_key").or(s("phone")).map(crate::phone::digits).filter(|d| !d.is_empty()))
}

fn hint(phone: &str) -> Option<String> {
    let d = crate::phone::digits(phone);
    (d.len() >= 4).then(|| format!("•••• {}", &d[d.len() - 4..]))
}

/// The id a row's loyalty lives under: the one it names, else its own when the
/// server flags it a member (the shared key).
fn member_id(row: &serde_json::Value) -> Option<String> {
    let s = |k: &str| row.get(k).and_then(|v| v.as_str()).map(str::to_string);
    s("loyalty_customer_id").or_else(|| {
        row.get("is_member").and_then(|v| v.as_bool()).unwrap_or(false).then(|| s("id")).flatten()
    })
}

/// `mode` is the branch's programme (`points` / `visits`): which of the two
/// balances the row carries is the one this shop's customers count.
fn view(row: &serde_json::Value, may_see_phone: bool, pending: bool, mode: &str, locale: &str) -> Option<CustomerView> {
    let s = |k: &str| row.get(k).and_then(|v| v.as_str()).map(str::to_string);
    let phone = s("phone").filter(|p| !p.trim().is_empty());
    let loyalty_customer_id = member_id(row);
    let balance = row
        .get(if mode == "visits" { "visits_balance" } else { "points_balance" })
        .and_then(|v| v.as_i64());
    Some(CustomerView {
        id: s("id")?,
        name: s("name")?,
        phone_hint: phone.as_deref().and_then(hint),
        phone: phone.filter(|_| may_see_phone),
        is_member: loyalty_customer_id.is_some(),
        balance_label: balance
            .filter(|_| loyalty_customer_id.is_some())
            .map(|b| format!("{b} {}", crate::loyalty::balance_label(mode, locale))),
        loyalty_customer_id,
        pending,
        source: s("source"),
    })
}

/// The row a loyalty member is: their own id first (the shared key), else the
/// row that names them.
fn member_row<'a>(rows: &'a [serde_json::Value], member_id: &str) -> Option<&'a serde_json::Value> {
    let s = |r: &'a serde_json::Value, k: &str| r.get(k).and_then(|v| v.as_str());
    rows.iter()
        .find(|r| s(r, "id") == Some(member_id))
        .or_else(|| rows.iter().find(|r| s(r, "loyalty_customer_id") == Some(member_id)))
}

/// Rank rows for a query: phone digits match by key; text by name prefix, then
/// word prefix, then contains. An empty query lists by name.
pub(crate) fn search_rows(
    rows: &[serde_json::Value],
    query: &str,
) -> Vec<serde_json::Value> {
    let q = query.trim().to_lowercase();
    let digits = crate::phone::digits(&q);
    // A part of a number typed the international way (`0020…`) sits in the key
    // without its `00`.
    let part = digits.strip_prefix("00").unwrap_or(&digits).to_string();
    let phone_query = digits.len() >= 3 && digits.len() * 2 >= q.chars().filter(|c| !c.is_whitespace()).count();
    let key_q = phone_key(&q);
    let mut hits: Vec<(u8, String, serde_json::Value)> = rows
        .iter()
        .filter_map(|r| {
            let name = r.get("name").and_then(|v| v.as_str())?.to_string();
            let lname = name.to_lowercase();
            let rank = if q.is_empty() {
                3
            } else if phone_query {
                let key = row_key(r)?;
                // A whole number meets the key in canonical form. A part of one
                // (the last four, or a local `010…` still being typed) is found
                // inside it: `0` + national is always inside `20` + national.
                match &key_q {
                    Some(k) if key == *k => 0,
                    _ if key.contains(&part) => 1,
                    _ => return None,
                }
            } else if lname.starts_with(&q) {
                0
            } else if lname.split_whitespace().any(|w| w.starts_with(&q)) {
                1
            } else if lname.contains(&q) {
                2
            } else {
                return None;
            };
            Some((rank, lname, r.clone()))
        })
        .collect();
    hits.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)));
    hits.into_iter().map(|(_, _, r)| r).take(MAX_RESULTS).collect()
}

impl MadarCore {
    fn customer_rows(&self, branch: &str) -> Vec<serde_json::Value> {
        crate::sync_pull::rows_of_type(&self.store, branch, TYPE)
    }

    fn pending_customer_ids(&self) -> std::collections::HashSet<String> {
        self.store
            .list_active()
            .unwrap_or_default()
            .into_iter()
            .filter(|i| i.op_type == "create_customer")
            .filter_map(|i| i.entity_id)
            .collect()
    }

    fn require_cap(&self, key: &str) -> Result<(), CoreError> {
        if self.can(key.to_string()) {
            Ok(())
        } else {
            Err(CoreError::Forbidden {
                resource: "customers".into(),
                action: key.to_string(),
            })
        }
    }

    /// What every projection of a row needs: may the phone be shown, which ids
    /// are still queued, and the programme + language a balance is worded in.
    fn view_of(&self) -> impl Fn(&serde_json::Value) -> Option<CustomerView> {
        let see = self.can("customers.view".into());
        let pending = self.pending_customer_ids();
        let locale = self.current_locale();
        let mode = self
            .branch_field::<serde_json::Value>(crate::branch_reads::F_LOYALTY)
            .ok()
            .and_then(|f| f.value())
            .map(|v| crate::loyalty::settings_from_value(Some(&v)).mode)
            .unwrap_or_default();
        move |r| {
            let id = r.get("id").and_then(|v| v.as_str()).unwrap_or_default();
            view(r, see, pending.contains(id), &mode, &locale)
        }
    }

    /// Customers matching `query` (name, or phone digits), best first. Needs
    /// `customers.attach` or `customers.view`.
    pub fn search_customers(&self, query: String) -> Result<Vec<CustomerView>, CoreError> {
        if !self.can("customers.attach".into()) {
            self.require_cap("customers.view")?;
        }
        let branch = self.session_branch_id()?;
        let view = self.view_of();
        Ok(search_rows(&self.customer_rows(&branch), &query).iter().filter_map(view).collect())
    }

    /// One customer from the local list (an attached sale shows its name).
    pub fn customer_by_id(&self, id: String) -> Result<Option<CustomerView>, CoreError> {
        let branch = self.session_branch_id()?;
        Ok(self
            .customer_rows(&branch)
            .iter()
            .find(|r| r.get("id").and_then(|v| v.as_str()) == Some(id.as_str()))
            .and_then(self.view_of()))
    }

    /// The customer a loyalty member IS, from the local list: the row under the
    /// member's own id (the shared key), else the row a server that predates it
    /// linked to the member. `None` when this till holds neither — the member
    /// is then known to the sale by their loyalty id alone.
    pub fn customer_for_member(&self, member_id: String) -> Result<Option<CustomerView>, CoreError> {
        let branch = self.session_branch_id()?;
        Ok(member_row(&self.customer_rows(&branch), &member_id).and_then(self.view_of()))
    }

    /// The ONE person a sale names, as the pair the wire still carries.
    ///
    /// `loyalty_customer_id` is the member whose balance the sale spends (only
    /// ever sent with redemptions); `customer_id` is who bought it. They must
    /// never name two people, so the member decides: the customer becomes the
    /// member's own row. A server that predates the shared key may hold the
    /// member under an id `customers` has never heard of, so the member's id is
    /// sent as `customer_id` ONLY when the local list has that row; failing
    /// that the row linked to the member; failing that, nobody — the sale goes
    /// out with the loyalty id alone, as it always has. Never an error: a sale
    /// is not refused over who bought it.
    pub(crate) fn one_person(
        &self,
        customer_id: Option<String>,
        loyalty_customer_id: Option<String>,
    ) -> (Option<String>, Option<String>) {
        let Some(member) = loyalty_customer_id.filter(|m| !m.trim().is_empty()) else {
            return (customer_id, None);
        };
        let rows = self.session_branch_id().map(|b| self.customer_rows(&b)).unwrap_or_default();
        let resolved = member_row(&rows, &member)
            .and_then(|r| r.get("id").and_then(|v| v.as_str()).map(str::to_string));
        if customer_id.is_some() && customer_id != resolved {
            crate::obs::capture_bg_warning("customers.one_person", "a sale named a customer who is not its member; the member stands");
        }
        (resolved, Some(member))
    }

    /// Attach a customer to a sale that is already rung — a settled bill, a
    /// finalized online order, a sale in the history — or, with no
    /// `customer_id`, take the customer off it. Needs `customers.attach`.
    ///
    /// Offline-first: the choice shows at once and reaches the server through
    /// the queue (`attach_customer`), behind the sale itself when that sale —
    /// or the customer — has not synced yet. `order_id` is whatever names the
    /// sale here: its server id, its client key, or the ticket it settled.
    /// One op per sale: choosing again before it is sent replaces the choice.
    /// Returns true while the attach is still queued.
    pub fn attach_customer(&self, order_id: String, customer_id: Option<String>) -> Result<bool, CoreError> {
        self.require_cap("customers.attach")?;
        let order_id = order_id.trim().to_string();
        if order_id.is_empty() {
            return Err(CoreError::Validation { field: "order_id".into(), detail: "no order to attach to".into() });
        }
        let customer_id = customer_id.map(|c| c.trim().to_string()).filter(|c| !c.is_empty());
        // The sale's own key on this device, when it holds the row.
        let okey = self.order_key_of(&order_id)?.unwrap_or_else(|| order_id.clone());
        let op_id = format!("attach:{okey}");
        // Behind the sale's own create (a counter sale is queued under its key,
        // a settle under `<ticket>:settle`) and behind the customer's, whichever
        // was queued last: FIFO means its ack implies the others.
        let mut gates = vec![self.store.live_seq_of(&okey)?, self.store.live_seq_of(&format!("{okey}:settle"))?];
        if let Some(c) = &customer_id {
            gates.push(self.store.live_seq_of(&format!("customer:{c}"))?);
        }
        let (user_id, clock_offset_ms) = self.outbox_meta();
        let op = crate::store::NewOutboxOp {
            id: op_id.clone(),
            op_type: "attach_customer".into(),
            idempotency_key: op_id.clone(),
            payload: serde_json::json!({ "order_id": okey, "customer_id": customer_id }).to_string(),
            event_at: self.corrected_now().to_rfc3339(),
            depends_on_seq: gates.into_iter().flatten().max(),
            user_id,
            clock_offset_ms,
            entity_type: Some("order_customer".into()),
            entity_id: Some(okey.clone()),
            ..Default::default()
        };
        self.store.with_tx_touch(|tx, touched| {
            // An attach this sale already SENT is history: the new choice is a
            // new op under the same key. One still waiting is simply replaced
            // (the latest choice wins); one in flight is left to land and the
            // new choice follows it.
            tx.execute("DELETE FROM outbox WHERE id=?1 AND status='acked'", [&op_id])?;
            let inflight: Option<i64> = {
                use rusqlite::OptionalExtension;
                tx.query_row("SELECT seq FROM outbox WHERE id=?1 AND status='inflight'", [&op_id], |r| r.get(0)).optional()?
            };
            match inflight {
                Some(seq) => {
                    let id = format!("{op_id}:{}", uuid::Uuid::new_v4());
                    crate::store::enqueue_on(tx, &crate::store::NewOutboxOp {
                        id: id.clone(),
                        idempotency_key: id,
                        depends_on_seq: Some(op.depends_on_seq.map_or(seq, |d| d.max(seq))),
                        ..op.clone()
                    })?;
                }
                None => {
                    crate::store::enqueue_on(tx, &op)?;
                    tx.execute(
                        "UPDATE outbox SET payload=?2, event_at=?3, depends_on_seq=?4, status='pending',
                                attempts=0, next_attempt_at=0, last_error=NULL
                          WHERE id=?1 AND status IN ('pending','dead')",
                        rusqlite::params![op_id, op.payload, op.event_at, op.depends_on_seq],
                    )?;
                }
            }
            // What this device shows for the sale until the server's row says it.
            tx.execute(
                "INSERT INTO kv(k, v, updated_at) VALUES(?1, ?2, ?3)
                 ON CONFLICT(k) DO UPDATE SET v=excluded.v, updated_at=excluded.updated_at",
                rusqlite::params![
                    format!("{ORDER_CUSTOMER_KV}{okey}"),
                    serde_json::json!({ "customer_id": customer_id }).to_string(),
                    op.event_at
                ],
            )?;
            touched.extend(crate::changes::tables_for_op("attach_customer"));
            Ok(())
        })?;
        self.send_in_background(Vec::new());
        Ok(self.store.live_seq_of(&op_id)?.is_some())
    }

    /// The customer on a rung sale, by any of its ids. This device's own choice
    /// stands while it is queued, and after that wherever the server's row does
    /// not carry `customer_id` at all (a server that predates it).
    pub fn order_customer(&self, order_id: String) -> Result<Option<CustomerView>, CoreError> {
        let okey = self.order_key_of(&order_id)?.unwrap_or_else(|| order_id.clone());
        let chosen: Option<Option<String>> = self
            .store
            .kv_get(&format!("{ORDER_CUSTOMER_KV}{okey}"))?
            .and_then(|raw| serde_json::from_str::<serde_json::Value>(&raw).ok())
            .map(|v| v.get("customer_id").and_then(|c| c.as_str()).map(str::to_string));
        let queued = self.store.live_seq_of(&format!("attach:{okey}"))?.is_some();
        let synced: Option<Option<String>> = self.store.with_conn(|c| {
            use rusqlite::OptionalExtension;
            let raw: Option<String> = c
                .query_row("SELECT raw FROM ledger_orders WHERE okey=?1", [&okey], |r| r.get(0))
                .optional()?;
            Ok(raw
                .and_then(|r| serde_json::from_str::<serde_json::Value>(&r).ok())
                .and_then(|v| v.get("customer_id").map(|c| c.as_str().map(str::to_string))))
        })?;
        let id = match (queued, chosen, synced) {
            (true, Some(mine), _) => mine,
            (_, _, Some(server)) => server,
            (_, mine, None) => mine.flatten(),
        };
        match id {
            Some(id) => self.customer_by_id(id),
            None => Ok(None),
        }
    }

    /// A sale's key in the local ledger, from its key or its server id.
    fn order_key_of(&self, order_id: &str) -> Result<Option<String>, CoreError> {
        self.store.with_conn(|c| {
            use rusqlite::OptionalExtension;
            Ok(c.query_row(
                "SELECT okey FROM ledger_orders WHERE okey=?1 OR server_id=?1 LIMIT 1",
                [order_id],
                |r| r.get(0),
            )
            .optional()?)
        })
    }

    /// Add a customer on the till. Works offline: the customer is usable at
    /// once and reaches the server through the queue. Needs `customers.create`.
    pub fn create_customer(
        &self,
        name: String,
        phone: Option<String>,
    ) -> Result<CustomerView, CoreError> {
        self.require_cap("customers.create")?;
        let name = name.trim().chars().take(120).collect::<String>();
        if name.is_empty() {
            return Err(CoreError::Validation {
                field: "name".into(),
                detail: crate::i18n::tr(&self.current_locale(), "customers.name_required"),
            });
        }
        // Sent as typed (the server keeps it for display and canonicalises its
        // own key). A number the shared rule refuses is said so here, where it
        // can be retyped, rather than silently dropped.
        let phone = phone.map(|p| p.trim().to_string()).filter(|p| !p.is_empty());
        if phone.as_deref().is_some_and(|p| phone_key(p).is_none()) {
            return Err(CoreError::Validation {
                field: "phone".into(),
                detail: crate::i18n::tr(&self.current_locale(), "customers.phone_invalid"),
            });
        }
        let branch = self.session_branch_id()?;
        let id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now().to_rfc3339();
        let row = serde_json::json!({
            "id": id,
            "name": name,
            "phone": phone,
            "phone_key": phone.as_deref().and_then(phone_key),
            "loyalty_customer_id": null,
            "updated_at": now,
        });
        let (user_id, clock_offset_ms) = self.outbox_meta();
        let payload = serde_json::json!({
            "id": id, "name": name, "phone": phone, "branch_id": branch,
        });
        self.store.enqueue(&crate::store::NewOutboxOp {
            id: format!("customer:{id}"),
            op_type: "create_customer".into(),
            idempotency_key: format!("customer:{id}"),
            payload: payload.to_string(),
            event_at: now,
            user_id,
            clock_offset_ms,
            entity_type: Some(TYPE.into()),
            entity_id: Some(id.clone()),
            ..Default::default()
        })?;
        // Seq 0: any server copy of the row replaces it.
        self.store.with_conn(|c| {
            c.execute(
                "INSERT INTO sync_rows(type,id,branch_id,seq,data) VALUES(?1,?2,?3,0,?4)
                 ON CONFLICT(branch_id,type,id) DO NOTHING",
                rusqlite::params![TYPE, id, branch, row.to_string()],
            )?;
            Ok(())
        })?;
        self.send_in_background(Vec::new());
        Ok(self.view_of()(&row).expect("row has id and name"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn rows() -> Vec<serde_json::Value> {
        vec![
            json!({"id": "1", "name": "Mona Adel", "phone": "+20 100 123 4567", "phone_key": "01001234567"}),
            json!({"id": "2", "name": "Omar", "phone": "0111 222 3333", "phone_key": "01112223333"}),
            json!({"id": "3", "name": "Ahmed Monir", "phone": null, "phone_key": null}),
        ]
    }

    fn ids(v: Vec<serde_json::Value>) -> Vec<String> {
        v.iter().map(|r| r["id"].as_str().unwrap().to_string()).collect()
    }

    #[test]
    fn search_finds_by_name_prefix_word_and_phone() {
        assert_eq!(ids(search_rows(&rows(), "mon")), vec!["1", "3"], "prefix before word prefix");
        assert_eq!(ids(search_rows(&rows(), "+201001234567")), vec!["1"]);
        assert_eq!(ids(search_rows(&rows(), "4567")), vec!["1"], "the last digits find it");
        assert_eq!(ids(search_rows(&rows(), "")).len(), 3);
        assert!(search_rows(&rows(), "zzz").is_empty());
    }

    #[test]
    fn the_phone_is_hidden_without_view_but_hinted() {
        let v = view(&rows()[0], false, false, "points", "en").unwrap();
        assert_eq!(v.phone, None);
        assert_eq!(v.phone_hint.as_deref(), Some("•••• 4567"));
        assert_eq!(view(&rows()[0], true, false, "points", "en").unwrap().phone.as_deref(), Some("+20 100 123 4567"));
    }

    /// One query meets every shape a row's key has had: the old server's local
    /// `01…`, the canonical `20…`, and a row with no stored key at all.
    #[test]
    fn a_phone_is_found_whichever_form_the_server_keyed_it_by() {
        let rows = vec![
            json!({"id": "old", "name": "A", "phone": "0100 123 4567", "phone_key": "01001234567"}),
            json!({"id": "new", "name": "B", "phone": "201112223333", "phone_key": "201112223333"}),
            json!({"id": "bare", "name": "C", "phone": "+20 122 333 4444"}),
            // The phone is hidden upstream but the key is not: still found.
            json!({"id": "keyonly", "name": "D", "phone": null, "phone_key": "01555555555"}),
        ];
        for (q, id) in [
            ("01001234567", "old"), ("+201001234567", "old"), ("00201001234567", "old"), ("٠١٠٠١٢٣٤٥٦٧", "old"),
            ("01112223333", "new"), ("201112223333", "new"), ("1112223333", "new"),
            ("01223334444", "bare"), ("01555555555", "keyonly"), ("+201555555555", "keyonly"),
        ] {
            assert_eq!(ids(search_rows(&rows, q)), vec![id], "{q}");
        }
        // Still being typed, the local way and the international way.
        assert_eq!(ids(search_rows(&rows, "0100123")), vec!["old"]);
        assert_eq!(ids(search_rows(&rows, "+20111")), vec!["new"]);
        assert_eq!(ids(search_rows(&rows, "0020111")), vec!["new"]);
        assert_eq!(phone_key("0100 123 4567").as_deref(), Some("201001234567"));
    }

    #[test]
    fn a_member_is_told_by_either_server() {
        // A server that predates the shared key: a separate member id, no flag.
        let old = json!({"id": "c1", "name": "Mona", "loyalty_customer_id": "m9"});
        let v = view(&old, true, false, "points", "en").unwrap();
        assert!(v.is_member);
        assert_eq!(v.loyalty_customer_id.as_deref(), Some("m9"));
        assert_eq!((v.balance_label, v.source), (None, None));
        // The shared key: the member IS the customer, with a balance in the feed.
        let new = json!({"id": "c2", "name": "Omar", "is_member": true, "loyalty_customer_id": "c2",
                         "points_balance": 120, "visits_balance": 4, "source": "loyalty"});
        let v = view(&new, true, false, "points", "en").unwrap();
        assert_eq!(v.loyalty_customer_id.as_deref(), Some("c2"));
        assert_eq!(v.balance_label.as_deref(), Some("120 points"));
        assert_eq!(v.source.as_deref(), Some("loyalty"));
        assert_eq!(view(&new, true, false, "visits", "ar").unwrap().balance_label.as_deref(), Some("4 طلبات"));
        // The flag alone is enough; a non-member shows no balance even if one rides along.
        let flagged = json!({"id": "c3", "name": "Sara", "is_member": true});
        assert_eq!(view(&flagged, true, false, "points", "en").unwrap().loyalty_customer_id.as_deref(), Some("c3"));
        let plain = json!({"id": "c4", "name": "Ali", "is_member": false, "points_balance": 0});
        let v = view(&plain, true, false, "points", "en").unwrap();
        assert!(!v.is_member && v.balance_label.is_none() && v.loyalty_customer_id.is_none());
    }

    #[test]
    fn a_member_is_their_own_row_first_then_the_row_that_names_them() {
        let rows = vec![
            json!({"id": "c1", "name": "Linked", "loyalty_customer_id": "m1"}),
            json!({"id": "m1", "name": "Shared key"}),
        ];
        assert_eq!(member_row(&rows, "m1").unwrap()["id"], "m1");
        assert_eq!(member_row(&rows[..1], "m1").unwrap()["id"], "c1");
        assert!(member_row(&rows, "m2").is_none());
    }
}
