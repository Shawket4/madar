//! The till's push token (APP-6 for the POS): hand Firebase's token to the
//! server so it can reach this device when the app is closed, and hand it back
//! on sign-out so a shared till stops ringing for whoever left.
//!
//! Policy lives on the server — which events push, to whom, in what words.
//! This is the registration only, and it needs a connection: a token is worth
//! nothing queued, since it is replaced the moment the app reinstalls.

use serde_json::json;

use crate::{CoreError, MadarCore};

/// Which app the token belongs to, in `push_devices.app`.
pub const APP: &str = "pos";

impl MadarCore {
    /// Register (or rebind) this device's push token.
    pub async fn set_push_token(
        &self,
        token: String,
        locale: String,
        platform: String,
    ) -> Result<(), CoreError> {
        let token = token.trim();
        if token.is_empty() {
            return Err(CoreError::Validation {
                field: "token".into(),
                detail: "empty push token".into(),
            });
        }
        let locale = if locale.starts_with("ar") { "ar" } else { "en" };
        self.api
            .send_json(
                reqwest::Method::PUT,
                "/push/token",
                Some(&json!({
                    "app": APP, "token": token, "locale": locale, "platform": platform,
                })),
            )
            .await
            .map(|_| ())
    }

    /// Forget this device's token (sign-out, or the person switching tills).
    pub async fn clear_push_token(&self, token: String) -> Result<(), CoreError> {
        let token = token.trim();
        if token.is_empty() {
            return Ok(());
        }
        self.api
            .send_json(
                reqwest::Method::DELETE,
                "/push/token",
                Some(&json!({ "app": APP, "token": token })),
            )
            .await
            .map(|_| ())
    }
}

#[cfg(test)]
mod tests {
    use crate::testkit::{self, Stub, StubResponse};
    use serde_json::json;

    #[tokio::test]
    async fn the_token_goes_up_with_the_app_name_and_language() {
        let stub = Stub::start(|r| {
            (r.path == "/push/token").then(|| StubResponse::text(204, ""))
        })
        .await;
        let core = testkit::online_core(&stub.base, "").await;

        core.set_push_token(" fcm-abc ".into(), "ar-EG".into(), "android".into())
            .await
            .unwrap();
        assert_eq!(
            stub.requests("/push/token")[0].json(),
            json!({ "app": "pos", "token": "fcm-abc", "locale": "ar", "platform": "android" })
        );

        core.clear_push_token("fcm-abc".into()).await.unwrap();
        let sent = stub.requests("/push/token");
        assert_eq!(sent[1].method, "DELETE");
        assert_eq!(sent[1].json(), json!({ "app": "pos", "token": "fcm-abc" }));

        // Nothing to say, nothing sent.
        core.clear_push_token("  ".into()).await.unwrap();
        assert_eq!(stub.requests("/push/token").len(), 2);
        assert!(core.set_push_token("".into(), "en".into(), "ios".into()).await.is_err());
    }
}
