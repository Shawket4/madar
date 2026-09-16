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
    pub loyalty_customer_id: Option<String>,
    /// Added on this till and not yet confirmed by the server.
    pub pending: bool,
}

/// Digits only, a leading Egyptian country code folded to `0`. Mirrors the
/// server's `customers_phone_key`.
pub(crate) fn phone_key(phone: &str) -> Option<String> {
    let d: String = phone.chars().filter(|c| c.is_ascii_digit()).collect();
    if d.is_empty() {
        None
    } else if let Some(rest) = d.strip_prefix("0020") {
        Some(format!("0{rest}"))
    } else if d.len() == 12 && d.starts_with("20") {
        Some(format!("0{}", &d[2..]))
    } else {
        Some(d)
    }
}

fn hint(phone: &str) -> Option<String> {
    let d: String = phone.chars().filter(|c| c.is_ascii_digit()).collect();
    (d.len() >= 4).then(|| format!("•••• {}", &d[d.len() - 4..]))
}

fn view(row: &serde_json::Value, may_see_phone: bool, pending: bool) -> Option<CustomerView> {
    let s = |k: &str| row.get(k).and_then(|v| v.as_str()).map(str::to_string);
    let phone = s("phone").filter(|p| !p.trim().is_empty());
    Some(CustomerView {
        id: s("id")?,
        name: s("name")?,
        phone_hint: phone.as_deref().and_then(hint),
        phone: phone.filter(|_| may_see_phone),
        loyalty_customer_id: s("loyalty_customer_id"),
        pending,
    })
}

/// Rank rows for a query: phone digits match by key; text by name prefix, then
/// word prefix, then contains. An empty query lists by name.
pub(crate) fn search_rows(
    rows: &[serde_json::Value],
    query: &str,
) -> Vec<serde_json::Value> {
    let q = query.trim().to_lowercase();
    let digits: String = q.chars().filter(|c| c.is_ascii_digit()).collect();
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
                let key = r
                    .get("phone_key")
                    .and_then(|v| v.as_str())
                    .map(str::to_string)
                    .or_else(|| r.get("phone").and_then(|v| v.as_str()).and_then(phone_key))?;
                match &key_q {
                    Some(k) if key == *k => 0,
                    Some(k) if key.ends_with(k.as_str()) || key.contains(&digits) => 1,
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

    /// Customers matching `query` (name, or phone digits), best first. Needs
    /// `customers.attach` or `customers.view`.
    pub fn search_customers(&self, query: String) -> Result<Vec<CustomerView>, CoreError> {
        if !self.can("customers.attach".into()) {
            self.require_cap("customers.view")?;
        }
        let branch = self.session_branch_id()?;
        let see = self.can("customers.view".into());
        let pending = self.pending_customer_ids();
        Ok(search_rows(&self.customer_rows(&branch), &query)
            .iter()
            .filter_map(|r| {
                let id = r.get("id").and_then(|v| v.as_str()).unwrap_or_default();
                view(r, see, pending.contains(id))
            })
            .collect())
    }

    /// One customer from the local list (an attached sale shows its name).
    pub fn customer_by_id(&self, id: String) -> Result<Option<CustomerView>, CoreError> {
        let branch = self.session_branch_id()?;
        let see = self.can("customers.view".into());
        let pending = self.pending_customer_ids();
        Ok(self
            .customer_rows(&branch)
            .iter()
            .find(|r| r.get("id").and_then(|v| v.as_str()) == Some(id.as_str()))
            .and_then(|r| view(r, see, pending.contains(&id))))
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
        let phone = phone
            .map(|p| p.trim().chars().take(40).collect::<String>())
            .filter(|p| phone_key(p).is_some());
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
        Ok(view(&row, self.can("customers.view".into()), true).expect("row has id and name"))
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
        let v = view(&rows()[0], false, false).unwrap();
        assert_eq!(v.phone, None);
        assert_eq!(v.phone_hint.as_deref(), Some("•••• 4567"));
        assert_eq!(view(&rows()[0], true, false).unwrap().phone.as_deref(), Some("+20 100 123 4567"));
    }
}
