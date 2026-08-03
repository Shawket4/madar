//! The dashboard FRB entry object. `MadarBridge` wraps `Arc<MadarCore>` and
//! exposes ONLY the management-dashboard surface (auth, scope, branches, i18n);
//! analytics reads live in sibling `impl MadarBridge` blocks per domain file
//! (see `reports.rs`).
//!
//! Rules (docs/reference/frbDesign.md): methods take `&self` ONLY (the core is
//! interior-mutable); anything that may spawn/network stays `async`;
//! `#[frb(sync)]` is reserved for cheap in-memory reads used during builds.
use std::sync::Arc;

use flutter_rust_bridge::frb;
use madar_core::MadarCore;

use crate::api::error::MadarError;
use crate::api::types::{ActiveScopeView, BranchView, MadarConfig, SessionSnapshot};

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
    // pub(crate): the domain files (reports.rs, …) add their own
    // `impl MadarBridge` blocks and delegate through this same handle.
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

    /// Dashboard email/password sign-in (org_admin / super_admin / branch_manager).
    /// Online-only; no POS device/shift assumptions.
    pub async fn dashboard_sign_in(
        &self,
        email: String,
        password: String,
        org_id: Option<String>,
    ) -> Result<SessionSnapshot, MadarError> {
        self.inner
            .dashboard_sign_in(email, password, org_id)
            .await
            .map_err(MadarError::from)
    }

    /// Cached ACL check (drives nav/action gating).
    #[frb(sync)]
    pub fn has_permission(&self, resource: String, action: String) -> bool {
        self.inner.has_permission(resource, action)
    }

    pub fn logout(&self, wipe_outbox: bool) -> Result<(), MadarError> {
        self.inner.logout(wipe_outbox).map_err(MadarError::from)
    }

    // ── scope (dashboard org/branch selector) ───────────────────────────────

    /// The current explicit scope override (may be empty / partial).
    #[frb(sync)]
    pub fn active_scope(&self) -> Option<ActiveScopeView> {
        self.inner.active_scope()
    }

    /// Set + persist the active org/branch scope. A `None` field falls back to
    /// the session value on subsequent reads.
    #[frb(sync)]
    pub fn set_active_scope(&self, org_id: Option<String>, branch_id: Option<String>) {
        self.inner.set_active_scope(org_id, branch_id);
    }

    /// The org's active branches (scope-bar picker). Online-only.
    pub async fn list_branches(&self) -> Result<Vec<BranchView>, MadarError> {
        self.inner.list_branches().await.map_err(MadarError::from)
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
    pub async fn refresh_connectivity(&self) -> bool {
        self.inner.refresh_connectivity().await
    }
}
