//! The staff FRB entry object. `MadarBridge` wraps `Arc<MadarCore>` and exposes
//! ONLY the employee self-service surface (auth, i18n, connectivity); the
//! attendance/leave/payroll reads live in a sibling `impl MadarBridge` block
//! (see `staff.rs`).
//!
//! Rules (docs/reference/frbDesign.md): methods take `&self` ONLY (the core is
//! interior-mutable); anything that may spawn/network stays `async`;
//! `#[frb(sync)]` is reserved for cheap in-memory reads used during builds.
use std::sync::Arc;

use flutter_rust_bridge::frb;
use madar_core::MadarCore;

use crate::api::error::MadarError;
use crate::api::types::{MadarConfig, SessionSnapshot};

/// FFI contract version this wrapper was written against. Dart asserts equality.
#[frb(sync)]
pub fn ffi_surface_version() -> u32 {
    madar_core::ffi_surface_version()
}

/// madar-core semver, for the About/diagnostics screen.
#[frb(sync)]
pub fn core_version() -> String {
    madar_core::core_version()
}

#[frb(opaque)]
pub struct MadarBridge {
    // pub(crate): the domain files (staff.rs) add their own `impl MadarBridge`
    // blocks and delegate through this same handle.
    pub(crate) inner: Arc<MadarCore>,
}

impl MadarBridge {
    /// Open the store (SQLite + migrations) + build the HTTP client. Session
    /// restore is a separate explicit step.
    pub fn new(config: MadarConfig) -> Result<MadarBridge, MadarError> {
        Ok(MadarBridge {
            inner: MadarCore::new(config).map_err(MadarError::from)?,
        })
    }

    // ── session ───────────────────────────────────────────────────────────

    /// Re-hydrate the persisted session from the core's OWN store (cold boot).
    /// `None` = signed out / fresh install.
    #[frb(sync)]
    pub fn restore_session_cached(&self) -> Option<SessionSnapshot> {
        self.inner.restore_session_cached()
    }

    #[frb(sync)]
    pub fn is_authenticated(&self) -> bool {
        self.inner.is_authenticated()
    }

    #[frb(sync)]
    pub fn current_session(&self) -> Option<SessionSnapshot> {
        self.inner.current_session()
    }

    /// Whether the signed-in user holds a permission — what decides between the
    /// employee's five tabs and the manager's four.
    ///
    /// This is a UI hint, NOT the gate: every manager endpoint checks the same
    /// permission server-side, so hiding a tab is a courtesy and forging one
    /// buys nothing.
    #[frb(sync)]
    pub fn has_permission(&self, resource: String, action: String) -> bool {
        self.inner.has_permission(resource, action)
    }

    /// Employee email/password sign-in. Online-only — an employee account has no
    /// cached offline verifier, and clocking in offline is not a thing we want.
    pub async fn staff_sign_in(
        &self,
        email: String,
        password: String,
    ) -> Result<SessionSnapshot, MadarError> {
        self.inner
            .staff_sign_in(email, password)
            .await
            .map_err(MadarError::from)
    }

    pub fn logout(&self, wipe_outbox: bool) -> Result<(), MadarError> {
        self.inner.logout(wipe_outbox).map_err(MadarError::from)
    }

    // ── i18n (shared with the core; drives text + direction) ─────────────────

    /// Localized UI string for `key` (en/ar; falls back to en, then the key).
    #[frb(sync)]
    pub fn tr(&self, key: String) -> String {
        self.inner.tr(key)
    }

    #[frb(sync)]
    pub fn locale(&self) -> String {
        self.inner.locale()
    }

    #[frb(sync)]
    pub fn set_locale(&self, locale: String) {
        self.inner.set_locale(locale);
    }

    #[frb(sync)]
    pub fn is_rtl(&self) -> bool {
        self.inner.is_rtl()
    }

    // ── connectivity ─────────────────────────────────────────────────────────

    /// Ping /health; updates the online flag. True when reachable.
    ///
    /// The staff app leans on this more than the others: every action it offers
    /// is online-only, so it can tell the employee "you're offline" up front
    /// instead of letting a check-in fail at the moment it matters.
    pub async fn refresh_connectivity(&self) -> bool {
        self.inner.refresh_connectivity().await
    }
}
