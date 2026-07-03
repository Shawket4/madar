//! `CoreError` re-declared for FRB (struct-variant enums can't be mirrored).
//! Variant-for-variant identical; the Dart side catches it as a sealed class.
use madar_core::error::CoreError;

#[derive(Debug, thiserror::Error)]
pub enum MadarError {
    /// An online-only op was attempted while disconnected. Hot-path commands
    /// never return this — they queue to the outbox instead.
    #[error("offline: {detail}")]
    Offline { detail: String },
    /// 401 + refresh failed → surface sign-in.
    #[error("auth required: {detail}")]
    Unauthenticated { detail: String },
    #[error("forbidden: {resource}/{action}")]
    Forbidden { resource: String, action: String },
    /// Local validation: mode invariants, empty cart, future-dated event, …
    #[error("invalid: {field}: {detail}")]
    Validation { field: String, detail: String },
    #[error("server {status}: {code}")]
    Server {
        status: u16,
        code: String,
        detail: String,
    },
    /// 5xx / timeout — sync already retries; informational for the host.
    #[error("transient: {detail}")]
    Transient { detail: String },
    /// Store/migration/serde, or an FFI-version mismatch.
    #[error("internal: {detail}")]
    Internal { detail: String },
}

impl From<CoreError> for MadarError {
    fn from(e: CoreError) -> Self {
        match e {
            CoreError::Offline { detail } => Self::Offline { detail },
            CoreError::Unauthenticated { detail } => Self::Unauthenticated { detail },
            CoreError::Forbidden { resource, action } => Self::Forbidden { resource, action },
            CoreError::Validation { field, detail } => Self::Validation { field, detail },
            CoreError::Server {
                status,
                code,
                detail,
            } => Self::Server {
                status,
                code,
                detail,
            },
            CoreError::Transient { detail } => Self::Transient { detail },
            CoreError::Internal { detail } => Self::Internal { detail },
        }
    }
}
