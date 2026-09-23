//! The till's push token (APP-6). Pure delegation to madar-core: the app hands
//! over whatever Firebase gave it, the core decides the app name and the
//! language the server writes pushes in.
use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

impl MadarBridge {
    /// Register (or rebind) this device's push token. Needs a connection.
    pub async fn set_push_token(
        &self,
        token: String,
        locale: String,
        platform: String,
    ) -> Result<(), MadarError> {
        self.inner
            .set_push_token(token, locale, platform)
            .await
            .map_err(MadarError::from)
    }

    /// Forget this device's token — sign-out, or the till changing hands.
    pub async fn clear_push_token(&self, token: String) -> Result<(), MadarError> {
        self.inner.clear_push_token(token).await.map_err(MadarError::from)
    }
}
