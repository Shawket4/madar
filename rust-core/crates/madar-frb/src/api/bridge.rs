//! The single FRB entry object. `MadarBridge` wraps `Arc<MadarCore>`; every
//! method is a one-line delegation. Spike scope for now — the remaining
//! domains (catalog, cart, orders, tickets, kds, delivery, …) land as sibling
//! `impl MadarBridge` blocks per domain file.
//!
//! Rules (see docs/reference/frbDesign.md in the madar repo):
//! - Methods take `&self` ONLY (the core is interior-mutable) — keeps FRB's
//!   opaque lock shared and calls concurrent.
//! - Anything that may `tokio::spawn` or touch network stays `async`.
//! - `#[frb(sync)]` is reserved for cheap in-memory reads used during builds.
use std::sync::Arc;

use flutter_rust_bridge::frb;
use madar_core::MadarCore;

use crate::api::error::MadarError;
use crate::api::realtime::{AlertCommand, RealtimeMessage, SinkListener, SinkPlayer};
use crate::api::routes::AppRoute;
use crate::api::types::{LoginRequest, MadarConfig, SessionSnapshot, ShiftView};
use crate::frb_generated::StreamSink;

/// FFI contract version this wrapper was written against (madar-core's
/// `ffi_surface_version`). Dart asserts equality at startup.
#[frb(sync)]
pub fn ffi_surface_version() -> u32 {
    madar_core::ffi_surface_version()
}

/// madar-core semver, for the About/diagnostics screen.
#[frb(sync)]
pub fn core_version() -> String {
    madar_core::core_version()
}

/// Round-trip smoke test.
#[frb(sync)]
pub fn greet(name: String) -> String {
    madar_core::greet(name)
}

#[frb(opaque)]
pub struct MadarBridge {
    // pub(crate): the domain files (cart.rs, orders.rs, …) add their own
    // `impl MadarBridge` blocks and delegate through this same handle.
    pub(crate) inner: Arc<MadarCore>,
}

impl MadarBridge {
    /// Open the store (SQLite + migrations), build the HTTP client, restore
    /// nothing — session restore is a separate explicit step.
    pub fn new(config: MadarConfig) -> Result<MadarBridge, MadarError> {
        Ok(MadarBridge {
            inner: MadarCore::new(config).map_err(MadarError::from)?,
        })
    }

    // ── host callbacks (attach BEFORE restore_session / login) ────────────



    // ── session ───────────────────────────────────────────────────────────

    /// Restore a HOST-supplied session blob (the one-time legacy keychain
    /// migration path). Writes through to the core's own store.
    pub fn restore_session(&self, blob: Vec<u8>) -> Option<SessionSnapshot> {
        self.inner.restore_session(blob)
    }

    /// Re-hydrate the persisted session from the core's OWN store — the
    /// normal cold boot. `None` = signed out / fresh install.
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

    /// Online login (PIN teller / email manager).
    pub async fn login(&self, req: LoginRequest) -> Result<SessionSnapshot, MadarError> {
        self.inner.login(req).await.map_err(MadarError::from)
    }

    /// One-call sign-in: online first, offline PIN unlock fallback.
    pub async fn sign_in(&self, req: LoginRequest) -> Result<SessionSnapshot, MadarError> {
        self.inner.sign_in(req).await.map_err(MadarError::from)
    }

    /// Offline PIN unlock (argon2id against the cached credentials bundle).
    pub fn unlock_offline(
        &self,
        name: String,
        pin: String,
        branch_id: String,
    ) -> Result<SessionSnapshot, MadarError> {
        self.inner
            .unlock_offline(name, pin, branch_id)
            .map_err(MadarError::from)
    }

    /// Cached ACL check (optimistic while offline).
    #[frb(sync)]
    pub fn has_permission(&self, resource: String, action: String) -> bool {
        self.inner.has_permission(resource, action)
    }

    pub fn logout(&self, wipe_outbox: bool) -> Result<(), MadarError> {
        self.inner.logout(wipe_outbox).map_err(MadarError::from)
    }

    // ── routing ───────────────────────────────────────────────────────────

    /// The screen to show. Re-read at deliberate transitions only.
    #[frb(sync)]
    pub fn app_route(&self) -> AppRoute {
        self.inner.app_route().into()
    }

    // ── i18n ──────────────────────────────────────────────────────────────

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

    // ── shift (spike subset) ──────────────────────────────────────────────

    pub fn current_shift(&self) -> Result<Option<ShiftView>, MadarError> {
        self.inner.current_shift().map_err(MadarError::from)
    }

    /// Outbox-first: enqueues the open, drains, returns the local view.
    pub async fn open_shift(
        &self,
        opening_cash_minor: i64,
        opening_reason: Option<String>,
    ) -> Result<ShiftView, MadarError> {
        self.inner
            .open_shift(opening_cash_minor, opening_reason)
            .await
            .map_err(MadarError::from)
    }

    // ── sync / connectivity (spike subset) ────────────────────────────────

    pub fn pending_outbox_count(&self) -> Result<u32, MadarError> {
        self.inner.pending_outbox_count().map_err(MadarError::from)
    }

    /// Ping /health; updates the online flag. True when reachable.
    pub async fn refresh_connectivity(&self) -> bool {
        self.inner.refresh_connectivity().await
    }

    // ── realtime ──────────────────────────────────────────────────────────

    /// Open the device's ONE session-level subscription. The core owns topic
    /// policy and alert decisions; `events` refreshes boards, `alerts`
    /// performs platform primitives. Idempotent while a subscription lives.
    pub async fn start_realtime(
        &self,
        events: StreamSink<RealtimeMessage>,
        alerts: StreamSink<AlertCommand>,
    ) -> Result<(), MadarError> {
        self.inner
            .start_realtime(Box::new(SinkListener(events)), Box::new(SinkPlayer(alerts)))
            .await
            .map_err(MadarError::from)
    }

    /// Tear down the subscription (idempotent). Call before re-attaching
    /// sinks — including on Flutter hot restart.
    #[frb(sync)]
    pub fn unsubscribe_realtime(&self) {
        self.inner.unsubscribe_realtime();
    }

    #[frb(sync)]
    pub fn is_realtime_subscribed(&self) -> bool {
        self.inner.is_realtime_subscribed()
    }
}
