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
    ///
    /// ONE core per store in the process: on Android the app and its
    /// background location service (CL-4) are two Flutter engines in one
    /// process, and both must work through the same core — one outbox drain,
    /// one mirror, one session — never two over the same SQLite file.
    pub fn new(config: MadarConfig) -> Result<MadarBridge, MadarError> {
        use std::collections::HashMap;
        use std::sync::{Mutex, OnceLock, Weak};
        static CORES: OnceLock<Mutex<HashMap<String, Weak<MadarCore>>>> = OnceLock::new();
        let key = config.db_path.clone();
        let mut cores = CORES
            .get_or_init(Default::default)
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if let Some(inner) = cores.get(&key).and_then(Weak::upgrade).filter(|_| !key.is_empty()) {
            return Ok(MadarBridge { inner });
        }
        let inner = MadarCore::new(config).map_err(MadarError::from)?;
        if !key.is_empty() {
            cores.insert(key, Arc::downgrade(&inner));
        }
        Ok(MadarBridge { inner })
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

    /// `tr` in a named locale (`en` / `ar`), whatever the phone is set to —
    /// a payslip PDF in the other language (PAY-10).
    #[frb(sync)]
    pub fn tr_in(&self, locale: String, key: String) -> String {
        self.inner.tr_in(locale, key)
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

    /// `HH:mm` of an instant in the BRANCH's timezone (learned from the staff
    /// payloads), never the phone's. `—` for an empty or bad timestamp.
    #[frb(sync)]
    pub fn format_clock(&self, rfc3339: String) -> String {
        self.inner.format_clock(rfc3339)
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

#[cfg(test)]
mod tests {
    use super::*;

    fn config(db_path: &str) -> MadarConfig {
        MadarConfig {
            base_url: "http://127.0.0.1:9".into(),
            environment: "dev".into(),
            db_path: db_path.into(),
            locale: "en".into(),
            app_version: None,
        }
    }

    /// CL-4: the app and its background location service share one core
    /// over one store; a different store (or an in-memory one) is its own.
    #[test]
    fn one_core_per_store_in_the_process() {
        let dir = std::env::temp_dir().join(format!(
            "dawam-bridge-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let db = dir.join("staff.db").to_string_lossy().to_string();
        let app = MadarBridge::new(config(&db)).unwrap();
        let service = MadarBridge::new(config(&db)).unwrap();
        assert!(Arc::ptr_eq(&app.inner, &service.inner), "one core for one store");
        let other = MadarBridge::new(config(&dir.join("other.db").to_string_lossy())).unwrap();
        assert!(!Arc::ptr_eq(&app.inner, &other.inner));
        let a = MadarBridge::new(config("")).unwrap();
        let b = MadarBridge::new(config("")).unwrap();
        assert!(!Arc::ptr_eq(&a.inner, &b.inner), "in-memory stores are never shared");
        drop((app, service, other, a, b));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
