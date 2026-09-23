//! Dawam at the till, in Madar orgs: a forgotten or dead phone clocks in or
//! out with the person's till PIN (CL-13), and a pay-out can be handed to an
//! employee as an expense advance (AV-8). The server decides both; a PIN is
//! never queued, so the punch needs a connection.

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::{CoreError, MadarCore, till};

const K_BRANCH_PEOPLE: &str = "till_dawam.branch_people";

/// Someone at this branch, for the pay-out's "who took it" picker.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct BranchPersonView {
    pub user_id: String,
    pub name: String,
}

/// What a till punch did, worded by the core.
#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct TillPunchView {
    pub name: String,
    /// `in` · `out`
    pub punched: String,
    /// "Amal clocked in at 09:02" in the till's language.
    pub message: String,
}

impl MadarCore {
    /// Clock whoever owns `pin` in, or out if they are in, at this branch.
    pub async fn till_punch(&self, pin: String) -> Result<TillPunchView, CoreError> {
        let branch = self.session_branch_id()?;
        let pin = pin.trim().to_string();
        if pin.is_empty() {
            return Err(CoreError::Validation { field: "pin".into(), detail: "enter your PIN".into() });
        }
        let text = self
            .api
            .send_json(reqwest::Method::POST, "/staff/attendance/till-punch", Some(&json!({ "branch_id": branch, "pin": pin })))
            .await?;
        let v: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
        let name = v["name"].as_str().unwrap_or_default().to_string();
        let punched = v["punched"].as_str().unwrap_or("in").to_string();
        let at_key = if punched == "out" { "check_out_at" } else { "check_in_at" };
        let locale = self.current_locale();
        let time = v["record"][at_key]
            .as_str()
            .map(|t| crate::timefmt::format(&self.store, t, crate::timefmt::TimeStyle::Time, &locale))
            .unwrap_or_default();
        let key = if punched == "out" { "staff.till_clocked_out" } else { "staff.till_clocked_in" };
        let message = crate::i18n::tr(&locale, key).replace("{name}", &name).replace("{time}", &time);
        Ok(TillPunchView { name, punched, message })
    }

    /// This branch's staff; the last list when offline.
    pub async fn branch_people(&self) -> Result<Vec<BranchPersonView>, CoreError> {
        let branch = self.session_branch_id()?;
        match self.api.send_json(reqwest::Method::GET, &format!("/staff/branches/{branch}/people"), None).await {
            Ok(text) => {
                let _ = self.store.kv_put(K_BRANCH_PEOPLE, &text);
                Ok(serde_json::from_str(&text).unwrap_or_default())
            }
            Err(e @ (CoreError::Offline { .. } | CoreError::Transient { .. })) => {
                match self.store.kv_get(K_BRANCH_PEOPLE).ok().flatten() {
                    Some(text) => Ok(serde_json::from_str(&text).unwrap_or_default()),
                    None => Err(e),
                }
            }
            Err(e) => Err(e),
        }
    }

    /// A pay-out handed to `person` for shop purchases: logged in Dawam as
    /// their expense advance, never deducted from pay (AV-8).
    pub async fn record_expense_advance(
        &self,
        amount_minor: i64,
        note: String,
        person: String,
    ) -> Result<till::CashMovementView, CoreError> {
        self.record_cash_movement_tagged(-amount_minor.abs(), note, Some("pay_out".into()), None, Some(person)).await
    }
}

#[cfg(test)]
mod tests {
    use crate::testkit::{self, Stub, StubResponse, BRANCH};
    use serde_json::json;

    #[tokio::test]
    async fn a_pin_punch_goes_to_the_server_and_comes_back_worded() {
        let stub = Stub::start(|r| {
            (r.path == "/staff/attendance/till-punch").then(|| {
                StubResponse::json(200, json!({ "user_id": "u", "name": "Amal", "punched": "in",
                    "record": { "check_in_at": "2026-09-22T07:02:00Z" } }))
            })
        })
        .await;
        let core = testkit::online_core(&stub.base, "").await;
        let v = core.till_punch(" 4321 ".into()).await.unwrap();
        assert_eq!((v.name.as_str(), v.punched.as_str()), ("Amal", "in"));
        assert!(v.message.starts_with("Amal clocked in at "), "{}", v.message);
        let sent = &stub.requests("/staff/attendance/till-punch")[0];
        assert_eq!(sent.json(), json!({ "branch_id": BRANCH, "pin": "4321" }));
    }

    #[tokio::test]
    async fn branch_people_are_kept_for_offline() {
        let stub = Stub::start(|r| {
            r.path.starts_with("/staff/branches/").then(|| {
                StubResponse::json(200, json!([{ "user_id": "u1", "name": "Amal" }]))
            })
        })
        .await;
        let core = testkit::online_core(&stub.base, "").await;
        assert_eq!(core.branch_people().await.unwrap()[0].name, "Amal");
        let offline = Stub::start(|_| Some(StubResponse::hangup())).await;
        let core2 = testkit::online_core(&offline.base, "").await;
        core2.store.kv_put(super::K_BRANCH_PEOPLE, r#"[{"user_id":"u1","name":"Amal"}]"#).unwrap();
        assert_eq!(core2.branch_people().await.unwrap().len(), 1, "the last list, offline");
    }
}
