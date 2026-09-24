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
    /// An employee id: what the pay-out's `expense_advance_to` carries.
    /// (`user_id` reads a list cached before employees had their own id.)
    #[serde(alias = "user_id")]
    pub employee_id: String,
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
        // The server takes a PIN punch only from the branch's own registered
        // till (audit 03 P0): the install's `X-Madar-Device` rides every call,
        // and its activation credential proves it when it has one.
        let credential = self.store.kv_get(crate::K_DEVICE_CREDENTIAL).ok().flatten().filter(|t| !t.is_empty());
        let headers: Vec<(&str, &str)> =
            credential.as_deref().map(|t| vec![("X-Madar-Device-Token", t)]).unwrap_or_default();
        let text = self
            .api
            .post_with_header("/staff/attendance/till-punch", &json!({ "branch_id": branch, "pin": pin }), &headers)
            .await
            .map_err(|e| self.till_punch_refusal(e))?;
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

    /// The server's refusal of a PIN punch, in the till's language. A wrong
    /// PIN is never a sign-out (it would read as one: the server says 401).
    fn till_punch_refusal(&self, e: CoreError) -> CoreError {
        let locale = self.current_locale();
        let worded = |key: &str| CoreError::Validation { field: String::new(), detail: crate::i18n::tr(&locale, key) };
        match e {
            CoreError::Forbidden { resource, .. } if resource == "TILL_ONLY" => worded("staff.err_till_only"),
            CoreError::Forbidden { resource, .. } if resource == "NO_TILL_SESSION" => worded("staff.err_no_till_session"),
            CoreError::Unauthenticated { .. } => worded("err.wrong_pin"),
            // The shift is over, the PIN's owner isn't an employee…: the
            // staff app's words, never the server's raw body.
            CoreError::Server { code, detail, .. } if crate::dawam::PUNCH_CODES.contains(&code.as_str()) => {
                let tz = crate::timefmt::branch_tz(&self.store);
                CoreError::Validation {
                    field: String::new(),
                    detail: crate::dawam::punch_words(&locale, &code, &detail, tz),
                }
            }
            e => e,
        }
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
                StubResponse::json(200, json!({ "employee_id": "e", "name": "Amal", "punched": "in",
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
        assert!(sent.header("x-madar-device").is_some(), "the till says which device it is");
        assert_eq!(sent.header("x-madar-device-token"), None, "a till bound the old way has no credential");
    }

    /// Audit 03 P0: the server takes a PIN punch only from the branch's own
    /// till, proven by its activation credential; the core sends it, and
    /// words each refusal for the teller (never as a sign-out).
    #[tokio::test]
    async fn a_pin_punch_proves_the_till_and_words_its_refusals() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        use std::sync::Arc;
        let n = Arc::new(AtomicUsize::new(0));
        let m = n.clone();
        let stub = Stub::start(move |r| {
            (r.path == "/staff/attendance/till-punch").then(|| match m.fetch_add(1, Ordering::SeqCst) {
                0 => StubResponse::json(403, json!({ "error": "Till punches are made on the branch till.", "code": "TILL_ONLY" })),
                1 => StubResponse::json(409, json!({ "error": "Open the till first.", "code": "NO_TILL_SESSION" })),
                _ => StubResponse::json(401, json!({ "error": "Wrong PIN" })),
            })
        })
        .await;
        let core = testkit::online_core(&stub.base, "").await;
        core.store.kv_put(crate::K_DEVICE_CREDENTIAL, "cred-1").unwrap();
        let said = |e: crate::CoreError| match e {
            crate::CoreError::Validation { detail, .. } => detail,
            e => panic!("{e:?}"),
        };
        assert_eq!(said(core.till_punch("1111".into()).await.unwrap_err()), crate::i18n::tr("en", "staff.err_till_only"));
        core.set_locale("ar".into());
        assert_eq!(said(core.till_punch("1111".into()).await.unwrap_err()), crate::i18n::tr("ar", "staff.err_no_till_session"));
        assert_eq!(said(core.till_punch("1111".into()).await.unwrap_err()), crate::i18n::tr("ar", "err.wrong_pin"));
        assert!(core.current_session().is_some(), "a wrong PIN signs nobody out");
        for r in stub.requests("/staff/attendance/till-punch") {
            assert_eq!(r.header("x-madar-device-token").as_deref(), Some("cred-1"));
        }
    }

    /// E2E posnotif: a punch refusal the till did not word (the shift is
    /// over, the PIN's owner isn't an employee) showed the server's raw JSON
    /// body in the red banner. It reads like the staff app's, in the till's
    /// language.
    #[tokio::test]
    async fn a_punch_refusal_is_worded_not_raw_json() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        use std::sync::Arc;
        let n = Arc::new(AtomicUsize::new(0));
        let m = n.clone();
        let stub = Stub::start(move |r| {
            (r.path == "/staff/attendance/till-punch").then(|| match m.fetch_add(1, Ordering::SeqCst) {
                0 | 1 => StubResponse::json(400, json!({ "error": "Morning has already ended", "code": "SHIFT_ENDED",
                    "vars": { "shift": "Morning" } })),
                _ => StubResponse::json(403, json!({ "error": "Karl isn't set up as an employee in Dawam.",
                    "code": "NOT_AN_EMPLOYEE" })),
            })
        })
        .await;
        let core = testkit::online_core(&stub.base, "").await;
        let said = |e: crate::CoreError| match e {
            crate::CoreError::Validation { detail, .. } => detail,
            e => panic!("{e:?}"),
        };
        assert_eq!(said(core.till_punch("1111".into()).await.unwrap_err()), "Morning has already ended.");
        core.set_locale("ar".into());
        assert_eq!(said(core.till_punch("1111".into()).await.unwrap_err()), "وردية Morning خلصت خلاص.");
        let not_employee = said(core.till_punch("1111".into()).await.unwrap_err());
        assert_eq!(not_employee, crate::i18n::tr("ar", "staff.err_not_an_employee"));
        assert!(!not_employee.contains('{'), "{not_employee}");
    }

    /// E2E posnotif P-010: with Dawam (or POS) switched off the server
    /// refuses the punch with `MODULE_OFF`; an Arabic till showed a generic
    /// "you don't have permission". It says what is off, in the till's
    /// language.
    #[tokio::test]
    async fn a_punch_with_dawam_off_says_so() {
        let stub = Stub::start(|r| {
            (r.path == "/staff/attendance/till-punch").then(|| {
                StubResponse::json(403, json!({ "error": "Till punches need both POS and Dawam switched on.",
                    "code": "MODULE_OFF" }))
            })
        })
        .await;
        let core = testkit::online_core(&stub.base, "").await;
        let said = |e: crate::CoreError| match e {
            crate::CoreError::Validation { detail, .. } => detail,
            e => panic!("{e:?}"),
        };
        assert_eq!(
            said(core.till_punch("1111".into()).await.unwrap_err()),
            "Till punches need both POS and Dawam switched on."
        );
        core.set_locale("ar".into());
        let ar = said(core.till_punch("1111".into()).await.unwrap_err());
        assert_eq!(ar, crate::i18n::tr("ar", "staff.err_module_off"));
        assert_ne!(ar, "staff.err_module_off", "the Arabic table has the words");
    }

    /// Owner decision #1 (D1): a PIN punch on a shift a colleague is
    /// covering is refused (409 SHIFT_COVERED) and the till says who is
    /// covering it, in the till's language.
    #[tokio::test]
    async fn a_pin_punch_on_a_covered_shift_names_the_coverer() {
        let stub = Stub::start(|r| {
            (r.path == "/staff/attendance/till-punch").then(|| {
                StubResponse::json(409, json!({ "error": "Bassem is covering this shift. A manager ends or rejects the cover first.",
                    "code": "SHIFT_COVERED", "vars": { "coverer_name": "Bassem" } }))
            })
        })
        .await;
        let core = testkit::online_core(&stub.base, "").await;
        let said = |e: crate::CoreError| match e {
            crate::CoreError::Validation { detail, .. } => detail,
            e => panic!("{e:?}"),
        };
        let en = said(core.till_punch("1111".into()).await.unwrap_err());
        assert_eq!(en, crate::i18n::tr("en", "staff.err_shift_covered").replace("{coverer_name}", "Bassem"));
        core.set_locale("ar".into());
        let ar = said(core.till_punch("1111".into()).await.unwrap_err());
        assert_eq!(ar, crate::i18n::tr("ar", "staff.err_shift_covered").replace("{coverer_name}", "Bassem"));
        assert!(core.current_session().is_some(), "a refusal signs nobody out");
    }

    #[tokio::test]
    async fn branch_people_are_kept_for_offline() {
        let stub = Stub::start(|r| {
            r.path.starts_with("/staff/branches/").then(|| {
                StubResponse::json(200, json!([{ "employee_id": "e1", "name": "Amal" }]))
            })
        })
        .await;
        let core = testkit::online_core(&stub.base, "").await;
        let people = core.branch_people().await.unwrap();
        assert_eq!((people[0].employee_id.as_str(), people[0].name.as_str()), ("e1", "Amal"));
        let offline = Stub::start(|_| Some(StubResponse::hangup())).await;
        let core2 = testkit::online_core(&offline.base, "").await;
        core2.store.kv_put(super::K_BRANCH_PEOPLE, r#"[{"user_id":"u1","name":"Amal"}]"#).unwrap();
        assert_eq!(core2.branch_people().await.unwrap().len(), 1, "the last list, offline");
    }
}
