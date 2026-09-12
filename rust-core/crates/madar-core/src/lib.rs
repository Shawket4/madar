//! Madar POS shared core.
//!
//! THE ONE RULE: all real logic lives here. The Swift (iPhone/iPad) and Kotlin
//! (Android + desktop) apps are UI and platform glue only — they call into this
//! library over UniFFI for data, business rules, API calls, offline/sync and
//! printing. If a piece of logic could ever differ between platforms, that's a
//! bug; it belongs in Rust.
//!
//! Build-out is phased (see ../../../PLAN.md):
//!   Phase 1 (here): core skeleton + UniFFI bindings proven on every platform.
//!   Phase 2: API client (crates/madar-api) + auth + online read/write.
//!   Phase 3: SQLite local store + read-through cache + durable outbox.
//!   Phase 4: sync engine + backend offline-first support.
//!   Phase 5: printing (ESC/POS) in Rust.

#[cfg(feature = "uniffi-ffi")]
uniffi::setup_scaffolding!();

mod config;
pub use config::MadarConfig;

/// The client-authoritative pricing engine (pure; the money source of truth).
pub mod pricing;
/// Tax and service charge. Mirrors `MadarRust/src/tax/engine.rs` byte for byte
/// below the header, pinned by `tax_vectors.json`. See its module docs.
pub mod tax;

/// Cart — client-only in-progress order state, priced via `pricing`.
pub mod bookings;
pub mod cart;
/// Category styling (icon + gradient palette) — port of Flutter's `CatStyle`.
pub mod catstyle;
/// Checkout — assemble an order from the cart + place it via the outbox.
pub mod checkout;
/// Delivery-order management (teller side) — list/advance/cancel/finalize.
pub mod delivery;
/// Device binding (branch / till / station / printer / reconfigure) — persisted in
/// the CORE store so the hosts hold no device state (THE ONE RULE).
pub mod device;
/// The coarse FFI error model the host reacts to (PLAN §7.6).
pub mod error;
mod filestore;
/// Static UI-string localization — one source of truth for both hosts.
/// Server-backed held orders (parked carts that own floor tables), the
/// floor-layout mirror, and the transfer waitlist — all offline-first.
pub mod held;
pub mod i18n;
/// Kitchen Display System — station feed + per-line bump (kitchen topic consumer).
pub mod kds;
/// LAN offline relay (Phase E) — signed message envelope, per-branch HMAC, peer
/// registry; the second delivery path beside the cloud bus. Outbox stays the truth.
pub mod lan;
/// Menu / catalog reads — branch-effective mirror + view DTOs (PLAN §R9).
pub mod loyalty;
pub mod menu;
/// HTTP layer — drives the generated `madar-api` reqwest client (PLAN §R4 net/).
pub mod net;
/// Crash + background-error reporting (Sentry) with a disk-backed offline
/// transport. Errors raised inside the core's 8 background tasks never cross the
/// FFI, so this is the ONLY way they become visible. No DSN configured => fully
/// disabled and the core behaves exactly as it did before.
pub mod obs;
/// Order history reads — synced + still-queued orders for the shift.
pub mod orders;
/// Client of the unified realtime bus — ONE SSE connection per device, hand-rolled
/// over `bytes_stream()`, dispatched to the host through one callback listener.
pub mod realtime;
/// Thermal-receipt rendering (ESC/POS) + best-effort network printing.
pub mod receipt;
/// Local recipe preview — effective ingredients for a configured item (parity
/// with Flutter's `computeRecipeLocally`).
pub mod recipe;
/// Receipt → 1-bit raster bitmap (logo + Arabic via the embedded Cairo font),
/// for the raster-only TSP143III. Mirrors the on-screen ReceiptPaper preview.
pub mod render;
/// Dashboard analytics reads — projected KPI DTOs for the management app.
pub mod reports;
/// Reservations & floor-plan view types (host operations exported from `lib.rs`).
pub mod reservations;
/// Session & auth — online login, offline unlock, token custody (PLAN §7.2).
pub mod session;
/// Shift lifecycle — open/current via the outbox (PLAN §7.4).
pub mod shift;
/// Employee self-service reads/writes for the staff app (`/staff/me/*`).
pub mod staff;
/// Local store — SQLite mirror + durable outbox + id_map + sync cursors (PLAN §8).
pub mod store;
/// Waiter open tickets — fire-now-pay-later dine-in tickets via the outbox.
pub mod tickets;
/// Branch-timezone-aware timestamp formatting for display (mirrors Flutter AppTz).
pub mod timefmt;

/// Pure internal functions exposed ONLY to the cargo-fuzz harness. Gated on
/// `cfg(fuzzing)` (set automatically by `cargo +nightly fuzz`), so it never
/// exists in a normal build and adds nothing to the shipped library.
#[cfg(fuzzing)]
pub mod __fuzz {
    /// Thin `pub` wrapper so the fuzz crate can reach the `pub(crate)` verifier
    /// (a `pub use` of a `pub(crate)` item is illegal — this calls it instead).
    pub fn verify_offline_pin(pin: &str, phc: &str) -> bool {
        crate::session::verify_offline_pin(pin, phc)
    }
}

use std::sync::{Arc, Mutex, RwLock};

use error::CoreError;

/// Crate version (semver of the core library).
#[cfg_attr(feature = "uniffi-ffi", uniffi::exportNone)]
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// The FFI *surface* contract version, independent of the crate version. Bump
/// on every breaking change to the exported API so all three apps can assert at
/// startup that they were built against a compatible core (see PLAN.md §"FFI
/// surface versioning").
#[cfg_attr(feature = "uniffi-ffi", uniffi::exportNone)]
pub fn ffi_surface_version() -> u32 {
    // 1: realtime SSE (`subscribe_realtime`/`unsubscribe_realtime` + `EventListener`)
    //    + `AppRoute` payload variants (KitchenDisplay/WaiterTickets).
    // 2: device config moved into the core store — `app_route()`/`open_shift`/
    //    `refresh_shift` drop their host-passed params; `DeviceMode` removed; new
    //    `device_config`/`set_device_*` surface + `kitchen` role drives the KDS route.
    // 3: LAN offline relay (Phase E) — `lan_start`/`lan_stop`/`lan_active`/
    //    `lan_peer_count`/`lan_branch_has_open_till`/`set_device_lan_hub` + the
    //    `DeviceConfigView.lan_hub` field.
    // 4: core-driven realtime — `start_realtime(listener, player)` + the
    //    `RealtimePlayer` callback (the core owns topics-per-role + the alert
    //    decision/dedup/localized text; the host just plays ping/notification/haptic).
    4
}

/// Smoke-test call used to prove the binding pipeline end-to-end from each host.
#[cfg_attr(feature = "uniffi-ffi", uniffi::exportNone)]
pub fn greet(name: String) -> String {
    format!("Madar core v{} says hello, {name}", core_version())
}

/// The screen the host should show, decided by the core (PLAN §R11). The host
/// consults this only at deliberate transitions (cold start, post-login,
/// post-open/close-shift, sign-out) — never as a side effect of connectivity.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Enum))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AppRoute {
    /// Till not bound to a branch → manager device-setup.
    DeviceSetup,
    /// Configured but signed out → teller/waiter PIN login.
    Login,
    /// Signed in, no open shift → open-shift screen.
    OpenShift,
    /// Signed in with an open shift → order screen.
    Order,
    /// Device run as a kitchen display → the KDS for `station_id` (no shift needed).
    KitchenDisplay { station_id: String },
    /// A signed-in WAITER (holds no shift) → the open-tickets / take-order screen.
    WaiterTickets,
}

/// A till (physical drawer) the device can bind to — the device-setup / Settings
/// till picker. Cash continuity + the one-open-shift rule key on the till.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct TillView {
    pub id: String,
    pub name: String,
    pub is_default: bool,
    pub is_active: bool,
}

/// Top-level handle the host creates once and keeps alive for the app lifetime.
///
/// Phase 1 exposes config + version only. Later phases hang the API client,
/// local store, sync engine and printer off this object — the host keeps
/// holding the same handle.
/// One fully-projected catalog for a locale — the kv JSON mirrors parsed and
/// localized ONCE, items/bundles carrying their resolved `local_image_path`,
/// plus the parsed unified-modifier doc. Shared via `Arc` so every read path
/// (grid load, customization sheet, per-toggle recipe preview) borrows the
/// same snapshot instead of re-parsing multi-hundred-KB JSON per call.
struct CatalogSnapshot {
    locale: String,
    items: Vec<menu::MenuItemView>,
    bundles: Vec<menu::BundleView>,
    categories: Vec<menu::CategoryView>,
    addons: Vec<menu::AddonItemView>,
    unified: Option<menu::UnifiedDoc>,
}

/// kv key persisting the dashboard's active org/branch scope override.
const K_DASHBOARD_SCOPE: &str = "dashboard:active_scope";

/// The dashboard's runtime-selected org/branch scope. A `None` field means
/// "fall back to the session-derived value" (see `MadarCore::effective_scope`).
/// Dashboard-only; the POS never sets it.
#[derive(Clone, Debug, Default, serde::Serialize, serde::Deserialize)]
pub struct ActiveScopeView {
    pub org_id: Option<String>,
    pub branch_id: Option<String>,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Object))]
pub struct MadarCore {
    config: MadarConfig,
    /// The ONE embedded store (single writer behind its internal Mutex). `Arc` so the
    /// LAN relay bridge shares this EXACT instance (never a second connection — that
    /// would break the single-writer invariant and contend on WAL). Phase E.
    store: Arc<store::Store>,
    /// Active UI locale (en/ar) — runtime-changeable via `set_locale`; seeds from
    /// `config.locale`. Drives `tr`/`is_rtl` + catalog `*_translations` resolution.
    /// Active UI locale — `Arc` so the realtime `AlertingListener` can read it to
    /// localize notification titles (the host plays them, the core writes them).
    locale: Arc<RwLock<String>>,
    /// HTTP client to the backend (holds the live bearer token).
    api: net::ApiClient,
    /// The live session (`None` = signed out). Set by login / offline unlock /
    /// cold-start restore; cleared on logout.
    session: RwLock<Option<session::SessionState>>,
    /// The host's secure-bytes vault for the session blob (Keychain/Keystore).
    /// Server-vs-device clock skew in SECONDS — SHARED with the `ApiClient`, which
    /// refreshes it from the `Date` header of EVERY response (not just the ping), so
    /// `corrected_now` stays server-aligned between heartbeats. Persisted to kv on
    /// ping for a corrected cold-offline boot. Also drives the clock-skew banner.
    clock_skew_secs: Arc<std::sync::atomic::AtomicI64>,
    /// Consecutive failed `/health` probes that could NOT be confirmed by a real
    /// outbox send (empty backlog / no bearer). We only drop the online banner once
    /// this reaches [`K_OFFLINE_CONFIRM`] — a single failed probe (a waking radio /
    /// DNS-TLS not-ready right after a resume or rotation) must not flap it. Reset
    /// to 0 by any confirmed connectivity (a ping OK or an outbox ack).
    offline_probe_fails: std::sync::atomic::AtomicU32,
    /// Core-owned catalog image cache (menu/bundle photos + org logo).
    images: filestore::FileStore,
    /// Recipe-step animations, in their own directory so evicting the orphans
    /// of one cache never deletes the other's files.
    animations: filestore::FileStore,
    /// Parsed-catalog cache (see [`CatalogSnapshot`]). Rebuilt lazily on read;
    /// keyed by locale (a switch re-projects on the next read) and dropped by
    /// `refresh_catalog` after the kv commit + image phase — the only
    /// production writer of the catalog mirrors.
    catalog_cache: Mutex<Option<Arc<CatalogSnapshot>>>,
    /// `true` after a drain hit a 401: the outbox is parked (no retry budget
    /// burned, no heartbeat hammering) until the next successful login clears it.
    auth_paused: std::sync::atomic::AtomicBool,
    /// `true` when the live bearer is a still-valid token owned by a DIFFERENT
    /// teller, kept ONLY to flush the backlog after this teller's offline unlock.
    /// The drain invalidates it once the queue is caught up and then requires this
    /// teller to relogin under their own account (a teller must never operate
    /// indefinitely under someone else's identity). See `unlock_offline`.
    borrowed_token: std::sync::atomic::AtomicBool,
    /// A small in-memory ring buffer of diagnostic warnings (sync dead-letters,
    /// cascade failures, auth parks) — surfaced in Settings → Diagnostics so a
    /// teller/manager can see WHY something is stuck without a debugger.
    diag: Mutex<std::collections::VecDeque<DiagEntry>>,
    /// Single-flight guard for `drain_outbox`. The drain is triggered from many
    /// async entry points (login, checkout, open/close shift, cash movement,
    /// void, sync_now, retry, the connectivity heartbeat); without serialization
    /// two overlapping drains each snapshot the same `due_for_sync` backlog and
    /// double-send every row (and `recover_inflight` could reset a sibling's
    /// in-flight op). Held across the whole drain body so only one runs at a time
    /// — the second caller waits, then runs a fresh pass that sees any newly
    /// enqueued op. Mirrors the Flutter queue's `_drainFuture` single-flight.
    drain_lock: tokio::sync::Mutex<()>,
    /// The single live realtime subscription (the device's ONE SSE connection).
    /// Replacing or clearing it aborts the previous supervisor task, so a device
    /// never holds two streams. `None` = not subscribed.
    realtime: Mutex<Option<realtime::StreamHandle>>,
    /// The ONE unified event listener (set by `subscribe_realtime`), shared by BOTH
    /// the cloud SSE supervisor AND the LAN relay bridge so a cross-LAN event and its
    /// cloud twin reach the same sink (deduped by the host's snapshot-reload). Phase E.
    unified_listener: Arc<Mutex<Option<Arc<dyn realtime::EventListener>>>>,
    /// The running LAN relay (`None` = not started). The second delivery path beside
    /// the cloud bus; outbox stays the source of truth. Phase E.
    lan: Arc<Mutex<Option<Arc<lan::LanRelay>>>>,
    /// Dashboard-only: the runtime-selected org/branch scope override. `None`
    /// (or a `None` field) falls back to the session-derived scope. Persisted to
    /// kv (`dashboard:active_scope`) so the app reopens on the last branch.
    active_scope: RwLock<Option<ActiveScopeView>>,
}

/// One diagnostic log line.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct DiagLogView {
    pub at: String,
    pub level: String,
    pub message: String,
}

#[derive(Clone, Debug)]
struct DiagEntry {
    at: String,
    level: String,
    message: String,
}

#[cfg_attr(feature = "uniffi-ffi", uniffi::exportNone)]
impl MadarCore {
    /// Construct with explicit config (the host fills `db_path` with an
    /// app-private file). Opens + migrates the local store and builds the HTTP
    /// client; the session starts empty (host calls `restore_session` at boot).
    #[cfg_attr(feature = "uniffi-ffi", uniffi::constructor)]
    pub fn new(config: MadarConfig) -> Result<Arc<Self>, error::CoreError> {
        let store = Arc::new(store::Store::open(&config.db_path)?);
        // Bring crash reporting up as early as the store allows (its queue lives
        // in that SQLite file). Deliberately AFTER `Store::open` and BEFORE
        // anything else: a store that won't open is a hard boot failure the host
        // already surfaces, whereas everything past this line can panic inside a
        // background task where only Sentry would ever see it. `init` is
        // idempotent, non-blocking and infallible — with no DSN it is a no-op, so
        // this line changes nothing about how the core boots today.
        obs::init(store.clone(), &config.environment, &config.db_path);
        // Restore the last-known server skew so even a cold OFFLINE boot (no ping
        // yet) stamps queued ops with corrected, non-future times. SHARED with the
        // ApiClient so every response's Date header keeps it fresh.
        let skew = store
            .kv_get("clock_skew_secs")
            .ok()
            .flatten()
            .and_then(|s| s.parse::<i64>().ok())
            .unwrap_or(0);
        let clock_skew_secs = Arc::new(std::sync::atomic::AtomicI64::new(skew));
        // One-time sweep of the stuck rows v0.2.0 left behind. Cheap (an
        // indexed delete over a handful of rows), idempotent, and it runs here
        // rather than on first sync so the sync screen is already honest the
        // first time anyone opens it.
        let _ = store.purge_dead_held_ops();
        let api = net::ApiClient::new(config.base_url.clone(), clock_skew_secs.clone())?;
        let images = filestore::FileStore::new(&config.db_path, "images");
        let animations = filestore::FileStore::new(&config.db_path, "animations");
        let locale = Arc::new(RwLock::new(config.locale.clone()));
        // Dashboard scope override, restored across restarts (dashboard app only;
        // absent for the POS, which never writes this key).
        let active_scope = store
            .kv_get(K_DASHBOARD_SCOPE)
            .ok()
            .flatten()
            .and_then(|s| serde_json::from_str::<ActiveScopeView>(&s).ok());
        Ok(Arc::new(Self {
            config,
            store,
            locale,
            api,
            session: RwLock::new(None),
            clock_skew_secs,
            images,
            animations,
            catalog_cache: Mutex::new(None),
            offline_probe_fails: std::sync::atomic::AtomicU32::new(0),
            auth_paused: std::sync::atomic::AtomicBool::new(false),
            borrowed_token: std::sync::atomic::AtomicBool::new(false),
            diag: Mutex::new(std::collections::VecDeque::new()),
            drain_lock: tokio::sync::Mutex::new(()),
            realtime: Mutex::new(None),
            unified_listener: Arc::new(Mutex::new(None)),
            lan: Arc::new(Mutex::new(None)),
            active_scope: RwLock::new(active_scope),
        }))
    }

    /// Construct from the baked-in `.env` defaults (in-memory store until the
    /// host supplies a `db_path`).
    #[cfg_attr(feature = "uniffi-ffi", uniffi::constructor)]
    pub fn from_env() -> Result<Arc<Self>, error::CoreError> {
        Self::new(MadarConfig::from_env())
    }

    /// API base URL the core will talk to (from `.env`).
    pub fn base_url(&self) -> String {
        self.config.base_url.clone()
    }

    /// Environment name (`prod` | `staging` | `dev`).
    pub fn environment(&self) -> String {
        self.config.environment.clone()
    }

    /// SQLite path the host handed us (empty => in-memory).
    pub fn db_path(&self) -> String {
        self.config.db_path.clone()
    }

    /// Core crate version.
    pub fn version(&self) -> String {
        core_version()
    }

    /// Outbox items still waiting to sync (pending + in-flight) — the host shows
    /// this in the sync-status chrome.
    pub fn pending_outbox_count(&self) -> Result<u32, error::CoreError> {
        self.store.pending_count()
    }

    // ── session (sync) ──────────────────────────────────────────────────────

    /// Re-hydrate a session from the host's persisted blob at cold start. Returns
    /// the snapshot if the blob is valid, else `None` (fresh install / corrupt).
    pub fn restore_session(&self, blob: Vec<u8>) -> Option<session::SessionSnapshot> {
        // Write-through: a host-supplied blob (legacy keychain migration)
        // lands in the core's own store so the next boot restores locally.
        let _ = self.store.blob_put(session::K_SESSION_BLOB, &blob);
        let mut state = session::SessionState::from_blob(&blob)?;
        // A cold-restored session has NOT pinged yet — connectivity is only ever
        // truthful after a live heartbeat. Start offline-until-proven-online so we
        // never report a stale `online=true` (which would make the UI try a hard
        // online path before the first `refresh_connectivity`).
        state.snapshot.online = false;
        self.api.set_bearer(state.token.clone());
        let snapshot = state.snapshot.clone();
        *self.session.write().unwrap_or_else(|e| e.into_inner()) = Some(state);
        Some(snapshot)
    }

    /// Re-hydrate the session from the CORE's own store (the normal cold
    /// boot) — no host vault round-trip. `None` = signed out / fresh store.
    pub fn restore_session_cached(&self) -> Option<session::SessionSnapshot> {
        let blob = self
            .store
            .blob_get(session::K_SESSION_BLOB)
            .ok()
            .flatten()?;
        self.restore_session(blob)
    }

    pub fn is_authenticated(&self) -> bool {
        self.session
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .is_some()
    }

    /// The cached session — never hits the network.
    pub fn current_session(&self) -> Option<session::SessionSnapshot> {
        self.session
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .map(|s| s.snapshot.clone())
    }

    /// Permission check against the mirrored matrix. Optimistic while a session
    /// is offline-unlocked (permissions not yet loaded) — see `SessionState`.
    pub fn has_permission(&self, resource: String, action: String) -> bool {
        self.session
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .map(|s| s.has_permission(&resource, &action))
            .unwrap_or(false)
    }

    /// Offline unlock: verify a typed PIN against the cached org bundle
    /// (argon2id). No network, no token; identity is the real server `user_id`.
    pub fn unlock_offline(
        &self,
        name: String,
        pin: String,
        branch_id: String,
    ) -> Result<session::SessionSnapshot, CoreError> {
        use std::sync::atomic::Ordering::Relaxed;
        let mut state = session::unlock_from_bundle(&self.store, &name, &pin, &branch_id)?;
        let teller_id = state.snapshot.user_id.clone();
        let now = self.corrected_now().timestamp();
        // What to do with the prior session's cached JWT depends on WHO owns it.
        // `/sync/replay` attributes each op to its EMBEDDED teller (the bearer only
        // has to be an active in-org token), so a foreign-but-valid token CAN flush
        // the backlog — but a teller must never operate indefinitely under someone
        // else's identity, so a foreign token is used once then invalidated.
        let prior = self
            .session
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .and_then(|p| p.token.clone());
        let valid = prior
            .as_deref()
            .map(|t| !token_is_expired(t, now))
            .unwrap_or(false);
        let owned = prior.as_deref().and_then(jwt_sub).as_deref() == Some(teller_id.as_str());

        // `bearer` is the live (in-memory) token; `persist_token` is what's written
        // to the host vault. They DIFFER for a foreign token: it flushes the backlog
        // in memory but is NEVER persisted — a restart must not resurrect it and let
        // this teller keep operating under someone else's identity.
        let (bearer, persist_token, borrowed, paused) = match (prior, valid, owned) {
            // Valid token OWNED by THIS teller → keep AND persist: work + sync
            // normally, no banner. The "brief blip, don't make me sign in again" path.
            (Some(t), true, true) => (Some(t.clone()), Some(t), false, false),
            // Valid token owned by a DIFFERENT teller → use it in memory ONLY to flush
            // the backlog (not persisted); the drain invalidates it once caught up and
            // then requires THIS teller to relogin. No banner yet (let the flush run).
            (Some(t), true, false) => (Some(t), None, true, false),
            // A prior token existed but EXPIRED → drop it and surface the re-login
            // banner (the cached JWT genuinely lapsed).
            (Some(_), false, _) => (None, None, false, true),
            // No prior token at all (a genuine first offline unlock) → no bearer, no
            // banner; the queue holds until an online login installs one.
            (None, _, _) => (None, None, false, false),
        };
        state.token = persist_token;
        self.api.set_bearer(bearer);
        self.borrowed_token.store(borrowed, Relaxed);
        self.auth_paused.store(paused, Relaxed);
        let snapshot = state.snapshot.clone();
        self.persist_and_set(state);
        Ok(snapshot)
    }

    /// Sign out: clear the live session + token (the JWT is stateless — there is
    /// no server-side logout endpoint, so clearing locally is the revocation) and
    /// the host vault. Does NOT force-close the open shift, and KEEPS the cached
    /// shift: the open drawer is DEVICE state, not session state — it stays so the
    /// next sign-in can enforce that only its owner resumes it (and route them
    /// straight into it). The in-progress CART is session state, so it's dropped.
    /// Preserves the outbox unless `wipe_outbox`.
    pub fn logout(&self, wipe_outbox: bool) -> Result<(), CoreError> {
        self.api.set_bearer(None);
        self.borrowed_token
            .store(false, std::sync::atomic::Ordering::Relaxed);
        *self.session.write().unwrap_or_else(|e| e.into_inner()) = None;
        let _ = self.store.blob_delete(session::K_SESSION_BLOB);
        // Tear down any live realtime stream + listener so the next sign-in starts
        // clean. start_realtime's "already subscribed" guard would otherwise see the
        // stale handle and no-op, leaving the NEXT user with no events. Host signOut
        // calls unsubscribe_realtime, but the error/timeout logout paths don't — so
        // make logout itself bulletproof.
        self.unsubscribe_realtime();
        *self
            .unified_listener
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = None;
        // NB: the cached shift is intentionally KEPT (device drawer state) — see
        // the ownership gate in `sign_in`.
        let _ = cart::clear(&self.store);
        if wipe_outbox {
            self.store.wipe_outbox()?;
        }
        Ok(())
    }
}

impl MadarCore {
    /// Fetch a synced order's full record, CACHING it write-through so its detail +
    /// reprint work OFFLINE. Online: fetch + `cache:order:{id}`. Offline / on error:
    /// the cached `OrderFull` (populated here when the order was opened once online —
    /// the list path can't, its element is the items-less `models::Order`). Errors
    /// only for a synced order this device has never seen online. Non-exported
    /// (returns a raw `OrderFull`, not a uniffi type) — the public methods project it.
    async fn get_order_or_cache(
        &self,
        order_id: &str,
    ) -> Result<madar_api::models::OrderFull, CoreError> {
        use madar_api::apis::orders_api;
        let key = format!("cache:order:{order_id}");
        if self.current_session().map(|s| s.online).unwrap_or(false) {
            if let Ok(o) = orders_api::get_order(
                &self.api.config(),
                orders_api::GetOrderParams {
                    order_id: order_id.to_string(),
                },
            )
            .await
            {
                cache_views(&self.store, &key, std::slice::from_ref(&o));
                return Ok(o);
            }
        }
        cached_views::<madar_api::models::OrderFull>(&self.store, &key)
            .into_iter()
            .next()
            .ok_or_else(|| CoreError::Offline {
                detail: "order not cached yet — view it once online to enable offline reprint"
                    .into(),
            })
    }

    /// Persist a session into the core's own store and install it as the
    /// live session. Durability is a local SQLite write now — no host vault,
    /// no cross-store ordering to get wrong.
    fn persist_and_set(&self, state: session::SessionState) {
        let _ = self
            .store
            .blob_put(session::K_SESSION_BLOB, &state.to_blob());
        *self.session.write().unwrap_or_else(|e| e.into_inner()) = Some(state);
    }

    /// The active runtime locale (defaults to `config.locale`).
    fn current_locale(&self) -> String {
        self.locale
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
    }

    /// `(org_id, branch_id)` from the live session — needed for branch-effective
    /// catalog fetches. Errors if signed out / no org.
    fn org_branch(&self) -> Result<(String, Option<String>), CoreError> {
        let g = self.session.read().unwrap_or_else(|e| e.into_inner());
        let s = g.as_ref().ok_or_else(|| CoreError::Unauthenticated {
            detail: "not signed in".into(),
        })?;
        let org = s
            .snapshot
            .org_id
            .clone()
            .ok_or_else(|| CoreError::Validation {
                field: "org_id".into(),
                detail: "session has no org".into(),
            })?;
        Ok((org, s.snapshot.branch_id.clone()))
    }

    /// Whether a shift command of `op_type` for the CURRENTLY CACHED shift is
    /// still queued — scoped to that shift's id. The outbox is device-global and
    /// survives sign-out, so an unrelated teller's orphaned command must NOT
    /// count (it would keep a force-closed shift alive for the next teller on a
    /// shared till). open_shift ops are keyed by the shift PK; close_shift ops by
    /// `{shift_id}:close` (so open + close for one shift don't collide in the
    /// idempotent outbox).
    fn shift_command_pending(&self, op_type: &str) -> Result<bool, CoreError> {
        let sid = match shift::current(&self.store)? {
            Some(s) => s.id,
            None => return Ok(false),
        };
        let close_id = format!("{sid}:close");
        Ok(self
            .store
            .pending()?
            .iter()
            .any(|i| i.op_type == op_type && (i.id == sid || i.id == close_id)))
    }

    /// Whether the device currently has an OPEN shift — the deterministic,
    /// offline-safe answer that enforces the SEQUENTIAL-ONLY shift model (one
    /// shift at a time per device, even offline). True iff:
    ///   • the cached shift is open, OR
    ///   • an `open_shift` command is still queued for a shift that has NO
    ///     matching `close_shift` queued — a defense for the case where a bad
    ///     reconcile dropped the cache while the open hadn't synced yet.
    /// A shift CLOSED locally (its close already queued) is NOT open here, so the
    /// next shift may open immediately — that's the normal offline "close A, then
    /// open B" flow, and the FIFO drain still replays close-A before open-B.
    fn device_has_open_shift(&self) -> Result<bool, CoreError> {
        if shift::current(&self.store)?
            .map(|s| s.is_open)
            .unwrap_or(false)
        {
            return Ok(true);
        }
        let pending = self.store.pending()?;
        let has_uncovered_open = pending.iter().any(|op| {
            op.op_type == "open_shift"
                && !pending
                    .iter()
                    .any(|c| c.op_type == "close_shift" && c.id == format!("{}:close", op.id))
        });
        Ok(has_uncovered_open)
    }

    /// Comma-separated shift ids the device has a queued `close_shift` for — sent
    /// as the login acknowledgment so the server's open-shift login guard permits
    /// the legitimate offline handover (this device closed that shift offline; the
    /// close will replay right after login) while still rejecting a takeover.
    fn closing_shift_ids_csv(&self) -> String {
        self.store
            .pending()
            .unwrap_or_default()
            .iter()
            .filter(|i| i.op_type == "close_shift")
            .filter_map(|i| i.shift_id.clone())
            .collect::<Vec<_>>()
            .join(",")
    }

    /// (enqueuing teller id, device→server clock skew in ms) stamped on every
    /// queued op — the drain scopes by teller and re-bases timestamps at sync.
    fn outbox_meta(&self) -> (Option<String>, Option<i64>) {
        let user_id = self
            .session
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .map(|s| s.snapshot.user_id.clone());
        let skew_ms = self
            .clock_skew_secs
            .load(std::sync::atomic::Ordering::Relaxed)
            .saturating_mul(1000);
        (user_id, Some(skew_ms))
    }

    /// Append a diagnostic line (capped ring buffer of 200) — surfaced in
    /// Settings → Diagnostics. Best-effort; never fails the caller.
    fn push_diag(&self, level: &str, message: impl Into<String>) {
        let mut g = self.diag.lock().unwrap_or_else(|e| e.into_inner());
        g.push_back(DiagEntry {
            at: chrono::Utc::now().to_rfc3339(),
            level: level.into(),
            message: message.into(),
        });
        while g.len() > 200 {
            g.pop_front();
        }
    }

    /// Drain the durable outbox — the single place outbox writes hit the network.
    /// Ports the Flutter offline-queue engine (offline_queue.dart) so a device
    /// can run months offline and replay safely:
    ///   • backoff-gated, FIFO, user-scoped `due_for_sync`;
    ///   • crash recovery (inflight → pending) + acked-row retention purge;
    ///   • dependency gating that WAITS on an unsynced/dead prerequisite (never
    ///     cascades the dependent dead — that would strand its sale; the dead ROOT
    ///     surfaces the jam, and resolving it flows the whole chain);
    /// Re-point any orders STRANDED by a DEAD `open_shift` (this teller's) onto
    /// `target` and revive them so they sync onto it. Only DEAD opens move (a
    /// pending one is a legitimate not-yet-synced shift, never merged). This is the
    /// auto-heal the drain runs every pass so the orphan state never persists;
    /// `recover_orphaned_orders` is the manual fallback over the same primitive.
    fn heal_orphaned_orders(&self, target: &str, teller_id: &str) -> Result<u32, CoreError> {
        let mut remapped = 0u32;
        for orphan in self.store.dead_open_shift_ids(teller_id)? {
            if orphan != target {
                remapped += self.store.remap_shift(&orphan, target)?;
            }
        }
        if remapped > 0 {
            self.store.requeue_dead_for_shift(target)?;
        }
        Ok(remapped)
    }

    /// Set the live `online` flag. A CONFIRMED connectivity (`true`) also resets the
    /// unconfirmed-failure streak, so the next lone probe failure starts fresh.
    /// (Kept in this NON-`#[cfg_attr(feature = "uniffi-ffi", uniffi::exportNone)]` impl so it stays an internal helper and
    /// doesn't leak into the FFI surface the hosts see.)
    fn set_online(&self, online: bool) {
        if let Some(sess) = self
            .session
            .write()
            .unwrap_or_else(|e| e.into_inner())
            .as_mut()
        {
            sess.snapshot.online = online;
        }
        if online {
            self.offline_probe_fails
                .store(0, std::sync::atomic::Ordering::Relaxed);
        }
    }

    /// Every image URL the fresh catalog references (menu items + bundles +
    /// the org logo) — the keep-set for eviction and the download work-list.
    fn catalog_image_urls(&self) -> std::collections::HashSet<String> {
        let mut urls = std::collections::HashSet::new();
        let locale = self.current_locale();
        if let Ok(items) = menu::menu_items(&self.store, &locale) {
            urls.extend(items.into_iter().filter_map(|i| i.image_url));
        }
        if let Ok(bundles) = menu::bundles(&self.store, &locale) {
            urls.extend(bundles.into_iter().filter_map(|b| b.image_url));
        }
        urls.extend(self.org_logo_url());
        urls.retain(|u| !u.is_empty());
        urls
    }

    /// The image phase of `refresh_catalog`: evict orphans of the fresh
    /// catalog, then download whatever it references that isn't on disk yet —
    /// bounded concurrency (5), absolute-URL fetches (no bearer/base-url), a
    /// hard time budget so a slow CDN can't stall the refresh (stragglers
    /// complete on the NEXT refresh), and per-image failures swallowed:
    /// this can never fail the catalog.
    async fn sync_catalog_images(&self) {
        let urls = self.catalog_image_urls();
        self.images.evict_except(&urls);
        let missing: Vec<String> = urls
            .into_iter()
            .filter(|u| !self.images.is_cached(u))
            .collect();
        if missing.is_empty() {
            return;
        }
        let budget = std::time::Duration::from_secs(15);
        let _ = tokio::time::timeout(budget, async {
            for chunk in missing.chunks(5) {
                let downloads = chunk.iter().map(|url| async move {
                    if let Ok(bytes) = self.api.get_url_bytes(url).await {
                        if !bytes.is_empty() {
                            let _ = self.images.store(url, &bytes);
                        }
                    }
                });
                futures_util::future::join_all(downloads).await;
            }
        })
        .await;
    }

    /// A step's address is relative to the API base (so no extra configuration
    /// has to agree with the deployment); the cache is keyed by the absolute
    /// URL, whose `?v=` fingerprint makes a replaced animation a new file.
    fn animation_absolute_url(&self, path: &str) -> String {
        if path.starts_with("http://") || path.starts_with("https://") {
            return path.to_string();
        }
        format!("{}{}", self.api.base_url().trim_end_matches('/'), path)
    }

    /// Every step animation the CURRENT menu references — never the library.
    fn step_animation_urls(&self) -> std::collections::HashSet<String> {
        let locale = self.current_locale();
        let mut urls = std::collections::HashSet::new();
        if let Ok(items) = menu::menu_items(&self.store, &locale) {
            for item in items {
                for step in item.recipe_steps {
                    if let Some(u) = step.animation_url.filter(|u| !u.is_empty()) {
                        urls.insert(self.animation_absolute_url(&u));
                    }
                }
            }
        }
        urls
    }

    /// The animation phase of `refresh_catalog`, mirroring the image phase:
    /// evict what this menu no longer references, then download what it does
    /// and we lack. Bounded concurrency, a hard time budget, and every failure
    /// swallowed — a step without its animation still shows its name.
    async fn sync_step_animations(&self) {
        let urls = self.step_animation_urls();
        self.animations.evict_except(&urls);
        let missing: Vec<String> = urls
            .into_iter()
            .filter(|u| !self.animations.is_cached(u))
            .collect();
        if missing.is_empty() {
            return;
        }
        let budget = std::time::Duration::from_secs(15);
        let _ = tokio::time::timeout(budget, async {
            for chunk in missing.chunks(5) {
                let downloads = chunk.iter().map(|url| async move {
                    if let Ok(bytes) = self.api.get_url_bytes(url).await {
                        if !bytes.is_empty() {
                            let _ = self.animations.store(url, &bytes);
                        }
                    }
                });
                futures_util::future::join_all(downloads).await;
            }
        })
        .await;
    }

    async fn drain_outbox(&self) -> Result<(), CoreError> {
        use std::sync::atomic::Ordering::Relaxed;
        // Single-flight: only one drain iterates the backlog at a time. A second
        // concurrent trigger (heartbeat + a fresh checkout, say) waits here, then
        // runs its own pass once we finish — so it picks up anything we hadn't
        // snapshotted, but never double-sends a row this pass already owns.
        let _drain_guard = self.drain_lock.lock().await;
        // Crash recovery + retention housekeeping (cheap, idempotent). Safe to run
        // under the guard: with drains serialized, the only `inflight` rows here
        // are genuinely crash-stranded, never a live sibling's in-flight op.
        let _ = self.store.recover_inflight();
        let _ = self
            .store
            .purge_acked_older_than(now_ms() - K_ACKED_RETENTION_MS);
        // Swap out cached shift/order history past the retention window. Rides
        // the drain rather than a timer of its own: a till that never drains is
        // offline, and dropping history it cannot re-fetch is the one moment
        // this must not happen.
        let _ = self.prune_stale_caches();
        // Auto-heal: re-point any orders stranded by a DEAD open_shift onto the
        // teller's current open shift so the orphan state never persists. Best-effort
        // — when no shift is open to heal onto, the surfaced sync_status.blocked count
        // + recover_orphaned_orders() are the fallback.
        if let Ok(Some(cur)) = shift::current(&self.store) {
            if let (Some(teller), _) = self.outbox_meta() {
                let _ = self.heal_orphaned_orders(&cur.id, &teller);
            }
        }
        // A 401-parked queue burns nothing until the next successful login.
        if self.auth_paused.load(Relaxed) {
            return Ok(());
        }
        // No bearer (an offline-unlocked session with no cached JWT, or signed out)
        // → there is no credential to authenticate /sync/replay, so every op would
        // 401. With a LIVE session this is a reauth-needed state the teller must
        // see: latch `auth_paused` so the host surfaces the re-login banner —
        // holding silently left the queue reading "syncing (N)" forever with no
        // error anywhere (field bug). A successful online login installs a bearer
        // and clears the park exactly like a 401-park. Signed out entirely, keep
        // the silent hold: there is nobody to prompt, and the backlog drains on
        // the next login.
        if !self.api.has_bearer() {
            if self.current_session().is_some() {
                self.auth_paused.store(true, Relaxed);
            }
            return Ok(());
        }

        // Flush the ENTIRE device backlog regardless of which teller is signed in:
        // /sync/replay attributes each op to its own EMBEDDED teller, so any teller
        // (or a device principal) drains everyone's queued work. The old
        // teller-scoped drain stranded a prior teller's ops on a shared till — the
        // "must be the same teller to sync" bug.
        for item in self.store.due_for_sync(now_ms(), None)? {
            // A shift close must be the LAST op for its shift — wait while any of
            // that shift's orders/voids/cash are still live (shift-scoped).
            if item.op_type == "close_shift" {
                if let Some(sid) = item.shift_id.as_deref() {
                    if self.store.has_live_shift_writes(sid, item.seq)? {
                        continue;
                    }
                }
            }

            // Prerequisite gating: don't send until the dependency is acked.
            if let Some(dep) = item.depends_on_seq {
                match self.store.status_of_seq(dep)?.as_deref() {
                    // Still in flight OR dead-lettered → WAIT, don't cascade. Marking
                    // this op dead too would STRAND its sales (the field bug: an
                    // order's open dead-letters → the order cascades dead → the sale
                    // is lost). Waiting on a dead dependency keeps the whole chain
                    // RECOVERABLE: resolving the root op (the user retries it, or
                    // discards it — both surfaced in the stuck list) lets every
                    // dependent flow on the next drain. Waiting burns no retry budget,
                    // so this never loops; the dead ROOT is what surfaces the problem.
                    Some("pending") | Some("inflight") | Some("dead") => continue,
                    _ => {} // acked / discarded → safe to proceed
                }
            }

            self.store.mark_inflight(item.seq)?;
            let outcome = self.send_outbox_item(&item).await;
            // A REAL outbox send is the authority for the online banner: a clean ack
            // proves we're online; a transport failure proves we're offline. (A
            // 4xx/5xx/401 reached the server — those are handled by the arms below
            // without touching `online`.) This is why a lone /health blip on resume
            // no longer flaps the banner: only a genuine send failure flips it off.
            match &outcome {
                SendOutcome::Acked(_) => self.set_online(true),
                SendOutcome::Offline => self.set_online(false),
                _ => {}
            }
            match outcome {
                // Applied server-side (or idempotently already-applied).
                SendOutcome::Acked(server_id) => {
                    self.store.mark_acked(item.seq, server_id.as_deref())?;
                }
                // Permanent rejection — surface in the stuck list, never silently drop.
                SendOutcome::Dead(err) => {
                    self.store.mark_dead(item.seq, &err)?;
                    self.push_diag("error", format!("{} rejected: {err}", item.op_type));
                    // A rejected open leaves the teller selling against a phantom
                    // shift — clear the optimistic local shift.
                    if item.op_type == "open_shift"
                        && shift::current(&self.store)?.map(|s| s.id) == Some(item.id.clone())
                    {
                        let _ = shift::clear(&self.store);
                    }
                }
                // Token expired → park the whole queue (no budget burned) until
                // the next successful login re-drains.
                SendOutcome::AuthExpired => {
                    self.store
                        .mark_retry_no_count(item.seq, now_ms() + K_NETWORK_RETRY_MS)?;
                    // A rejected BORROWED (foreign) token is no good — drop it and
                    // require this teller's own relogin; otherwise just park.
                    if self.borrowed_token.load(Relaxed) {
                        self.invalidate_borrowed_token();
                    } else {
                        self.auth_paused.store(true, Relaxed);
                    }
                    self.push_diag(
                        "warn",
                        "sync paused — session expired; sign in again to resume",
                    );
                    return Ok(());
                }
                // Connectivity blip — reschedule WITHOUT consuming retry budget,
                // and stop this pass (the network is down for the rest too).
                SendOutcome::Offline => {
                    self.store
                        .mark_retry_no_count(item.seq, now_ms() + K_NETWORK_RETRY_MS)?;
                    return Ok(());
                }
                // Server error (5xx) / undecodable 2xx → counted exponential
                // backoff; dead-letter after the retry budget is exhausted.
                SendOutcome::Retry(err) => {
                    let attempts = item.attempts + 1;
                    if attempts >= K_MAX_RETRIES {
                        self.store.mark_dead(item.seq, &err)?;
                    } else {
                        let backoff = compute_backoff_ms(attempts, item.seq);
                        self.store.mark_retry(item.seq, &err, now_ms() + backoff)?;
                    }
                }
            }
        }
        // A BORROWED bearer (a different teller's still-valid token, kept only to
        // flush this device's backlog after an offline unlock) is invalidated once
        // the queue is caught up — the current teller must then relogin under their
        // OWN account to keep syncing. Done AFTER the drain so the flush completes;
        // `pending_count` excludes `dead`, so a permanently-stuck op can't pin the
        // borrowed token forever (the dead row surfaces in the stuck list instead).
        if self.borrowed_token.load(Relaxed) && self.store.pending_count()? == 0 {
            self.invalidate_borrowed_token();
            self.push_diag("warn", "offline backlog flushed under a previous teller's session — sign in again to continue");
        }
        Ok(())
    }

    /// Dispatch one queued op to the network and classify the result into a
    /// `SendOutcome`. Timestamps are re-based to the fresh server offset first
    /// (correct-at-sync), so a sale rung on a wrong-by-a-constant clock records
    /// the right time. Idempotency keys live in the persisted payload, so a
    /// replay after a lost response dedups server-side.
    /// Queue a bump/unbump as a durable replay op and try to drain it now. Each tap
    /// is its OWN op (unique id) so a rapid bump→unbump→bump replays in FIFO order to
    /// the correct final state; `/sync/replay` dedups idempotently on the line.
    async fn enqueue_bump(&self, item_id: String, bumped: bool) -> Result<(), CoreError> {
        let cmd = kds::BumpCommand {
            item_id: item_id.clone(),
        };
        let (user_id, clock_offset_ms) = self.outbox_meta();
        let op_id = uuid::Uuid::new_v4().to_string();
        self.store.enqueue(&store::NewOutboxOp {
            id: op_id,
            op_type: if bumped {
                "bump_kitchen"
            } else {
                "unbump_kitchen"
            }
            .into(),
            idempotency_key: format!("{}:{}", cmd.item_id, if bumped { "bump" } else { "unbump" }),
            payload: serde_json::to_string(&cmd)?,
            event_at: self.corrected_now().to_rfc3339(),
            depends_on_seq: None,
            user_id: user_id.clone(),
            clock_offset_ms,
            shift_id: None,
        })?;
        // Instant cross-device delivery over the LAN (carrying the replay op so a
        // peer can mirror it for durability, + the item_id so a peer greys the line
        // on its overlay). The outbox above stays the source of truth; this is just
        // the fast path. No-op when the relay isn't running.
        let op = if bumped {
            "bump_kitchen_item"
        } else {
            "unbump_kitchen_item"
        };
        let envelope =
            serde_json::json!({ "op": op, "teller_id": user_id, "item_id": item_id }).to_string();
        let data = serde_json::json!({ "item_id": item_id }).to_string();
        let ev = if bumped {
            "kitchen.item_bumped"
        } else {
            "kitchen.item_unbumped"
        };
        self.lan_publish("kitchen", ev, data, Some(envelope)).await;
        let _ = self.drain_outbox().await;
        Ok(())
    }

    /// The still-pending bump intents `(line_id, bumped)` in FIFO order — overlaid
    /// onto the KDS feed so the board reflects un-synced taps. Best-effort.
    fn pending_bumps(&self) -> Vec<(String, bool)> {
        self.store
            .pending()
            .unwrap_or_default()
            .iter()
            .filter_map(|i| {
                let bumped = match i.op_type.as_str() {
                    "bump_kitchen" => true,
                    "unbump_kitchen" => false,
                    _ => return None,
                };
                let cmd: kds::BumpCommand = serde_json::from_str(&i.payload).ok()?;
                Some((cmd.item_id, bumped))
            })
            .collect()
    }

    async fn send_outbox_item(&self, item: &store::OutboxItem) -> SendOutcome {
        let delta = self.rebase_delta_ms(item);

        // Every queued op flushes through ONE endpoint — `POST /sync/replay` —
        // carrying its ORIGINAL teller so the backend attributes it to the teller
        // who rang it, not to whoever is signed in now. This is what lets ANY
        // teller (or a device principal) drain the whole shared-till backlog.
        let teller_id = match item.user_id.clone() {
            Some(t) => t,
            // A legacy/un-attributed op can't be replayed safely — surface it.
            None => return SendOutcome::Dead("queued op has no teller attribution".into()),
        };

        // Deserialize the stored command, re-base its timestamp to the fresh
        // server skew (correct-at-sync), and wrap it in the replay envelope.
        // `idem` is how a 409/404 is read for this op (unchanged from the live
        // per-resource path). The envelope's `request` is the GENERATED type, so
        // the wire shape is identical to the live endpoint's body.
        let (envelope, idem): (serde_json::Value, Idem) = match item.op_type.as_str() {
            "open_shift" => {
                let mut cmd: shift::OpenShiftCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                rebase_dopt(&mut cmd.request.opened_at, delta);
                (
                    serde_json::json!({ "op": "open_shift", "teller_id": teller_id, "branch_id": cmd.branch_id, "request": cmd.request }),
                    Idem::No,
                )
            }
            "close_shift" => {
                let mut cmd: shift::CloseShiftCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                rebase_dopt(&mut cmd.request.closed_at, delta);
                (
                    serde_json::json!({ "op": "close_shift", "teller_id": teller_id, "shift_id": cmd.shift_id, "request": cmd.request }),
                    Idem::Yes,
                )
            }
            "create_order" => {
                let mut cmd: checkout::CheckoutCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                // Re-base created_at for clock skew — but NEVER across the business
                // day baked into order_ref at ring-up. If the skew shift would change
                // the branch-local day, keep the original so the stored created_at,
                // the stored order_ref, and the PRINTED receipt all agree on the day
                // (else the receipt's order_ref reports under a different day).
                let original = cmd.request.created_at;
                rebase_dopt(&mut cmd.request.created_at, delta);
                // Keep the original day-stamp when rebasing would cross the branch-day
                // baked into order_ref — UNLESS the original sits in the SERVER's future
                // beyond tolerance (the device clock ran ahead across midnight). The
                // backend rejects a future created_at (reject_if_future, 5-min slack)
                // and would DEAD-LETTER the sale, so there the server-aligned rebased
                // value wins: a one-off order_ref day mismatch beats losing the sale.
                let original_is_future = original
                    .flatten()
                    .map(|dt| {
                        dt.with_timezone(&chrono::Utc)
                            > self.corrected_now() + chrono::Duration::minutes(4)
                    })
                    .unwrap_or(false);
                if !original_is_future
                    && self.crosses_branch_day(&original, &cmd.request.created_at)
                {
                    cmd.request.created_at = original;
                }
                (
                    serde_json::json!({ "op": "create_order", "teller_id": teller_id, "request": cmd.request }),
                    Idem::No,
                )
            }
            "void_order" => {
                let mut cmd: orders::VoidOrderCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                rebase_dopt(&mut cmd.request.voided_at, delta);
                (
                    serde_json::json!({ "op": "void_order", "teller_id": teller_id, "order_id": cmd.order_id, "request": cmd.request }),
                    Idem::VoidIdem,
                )
            }
            "award_loyalty_points" => {
                let mut cmd: loyalty::AwardCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                // Rebase the press onto server time, exactly as queued orders
                // and voids are. Without this a till whose clock is an hour fast
                // sends a `requested_at` in the server's future and the server
                // correctly refuses it — punishing the customer for the till.
                rebase_dopt(&mut cmd.request.requested_at, delta);
                (
                    serde_json::json!({ "op": "award_loyalty_points", "teller_id": teller_id, "request": cmd.request }),
                    Idem::Yes,
                )
            }
            "cash_movement" => {
                let mut cmd: shift::CashMovementCommand = match serde_json::from_str(&item.payload)
                {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                rebase_dopt(&mut cmd.request.created_at, delta);
                (
                    serde_json::json!({ "op": "cash_movement", "teller_id": teller_id, "shift_id": cmd.shift_id, "request": cmd.request }),
                    Idem::Yes,
                )
            }
            // ── Waiter open tickets (fire-now-pay-later) ──────────────────────
            // The waiter fires/rounds; the cashier settles; either voids. Each is
            // idempotent on a client-minted key and lands through the same replay
            // envelope as orders. No timestamp to rebase (the request carries none;
            // the settle order is stamped server-side at replay).
            "open_ticket" => {
                let cmd: tickets::FireTicketCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                (
                    serde_json::json!({ "op": "fire_open_ticket", "teller_id": teller_id, "request": cmd.request }),
                    Idem::Yes,
                )
            }
            "ticket_add_round" => {
                let cmd: tickets::AddRoundCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                (
                    serde_json::json!({ "op": "add_ticket_round", "teller_id": teller_id, "ticket_id": cmd.ticket_id, "request": cmd.request }),
                    // A genuine round-retry dedups to 200 server-side (on the round
                    // idempotency key, checked before the conflict gate). So a 409
                    // ("round to a settled/voided ticket") or 404 (ticket never
                    // landed) is a REAL conflict — dead-letter it (surface in the
                    // stuck list) instead of silently acking the lost round.
                    Idem::No,
                )
            }
            "settle_open_ticket" => {
                let cmd: tickets::SettleTicketCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                (
                    serde_json::json!({ "op": "settle_open_ticket", "teller_id": teller_id, "ticket_id": cmd.ticket_id, "request": cmd.request }),
                    // A genuine settle-retry of an already-settled ticket dedups to
                    // 200 (the existing order, keyed on the ticket id). So the only
                    // 409 ("settle a voided ticket") or 404 (the fire never landed)
                    // is a REAL conflict — the cashier took cash but no order would
                    // exist. Dead-letter it (stuck list) instead of acking a lost sale.
                    Idem::No,
                )
            }
            "void_ticket" => {
                let cmd: tickets::VoidTicketCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                (
                    serde_json::json!({ "op": "void_open_ticket", "teller_id": teller_id, "ticket_id": cmd.ticket_id, "request": cmd.request }),
                    Idem::Yes,
                )
            }
            // ── KDS bump / unbump (Phase E §2) ────────────────────────────────
            // Idempotent on the line: a 409/404 (re-bump of a gone/bumped line) is
            // a success. Replay returns 204 No Content — handled specially below.
            "bump_kitchen" | "unbump_kitchen" => {
                let cmd: kds::BumpCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                let op = if item.op_type == "bump_kitchen" {
                    "bump_kitchen_item"
                } else {
                    "unbump_kitchen_item"
                };
                (
                    serde_json::json!({ "op": op, "teller_id": teller_id, "item_id": cmd.item_id }),
                    Idem::Yes,
                )
            }
            // ── Floor ops ─────────────────────────────────────────────────────
            // Parked orders are NOT here: they are this terminal's own drafts,
            // so they never reach the outbox. What remains is the genuinely
            // shared state -- swaps, the transfer queue, and clearing a bussed
            // table. A 409 means the floor moved on: ack it and let the
            // post-drain pull reconcile the mirror.
            "swap_tables" => {
                let cmd: held::SwapCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                (
                    serde_json::json!({ "op": "swap_tables", "teller_id": teller_id, "request": cmd.request }),
                    Idem::Yes,
                )
            }
            "create_table_transfer" => {
                let cmd: held::CreateTransferCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                (
                    serde_json::json!({ "op": "create_table_transfer", "teller_id": teller_id, "request": cmd.request }),
                    Idem::Yes,
                )
            }
            "cancel_table_transfer" => {
                let cmd: held::TransferOpCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                (
                    serde_json::json!({ "op": "cancel_table_transfer", "teller_id": teller_id, "transfer_id": cmd.transfer_id }),
                    Idem::Yes,
                )
            }
            "fulfill_table_transfer" => {
                let cmd: held::TransferOpCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                (
                    serde_json::json!({ "op": "fulfill_table_transfer", "teller_id": teller_id, "transfer_id": cmd.transfer_id, "request": cmd.request }),
                    Idem::Yes,
                )
            }
            "clear_table" => {
                let cmd: held::TableStateCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                (
                    serde_json::json!({ "op": "clear_table", "teller_id": teller_id, "table_id": cmd.table_id, "request": cmd.request }),
                    Idem::Yes,
                )
            }
            // The occupancy half of a device-local hold. The ORDER never goes
            // anywhere; only "this table is taken" does, so the dashboard's
            // floor and every other till see the room as it is. A 409 (the
            // floor moved on while we were offline) acks like the other floor
            // ops — the next pull reconciles.
            "hold_table" => {
                let cmd: held::TableStateCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                (
                    serde_json::json!({ "op": "hold_table", "teller_id": teller_id, "table_id": cmd.table_id, "request": cmd.request }),
                    Idem::Yes,
                )
            }
            "release_table" => {
                let cmd: held::TableStateCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                (
                    serde_json::json!({ "op": "release_table", "teller_id": teller_id, "table_id": cmd.table_id, "request": cmd.request }),
                    Idem::Yes,
                )
            }
            "seat_booking" => {
                let cmd: bookings::SeatBookingCommand = match serde_json::from_str(&item.payload) {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                (
                    serde_json::json!({ "op": "seat_booking", "teller_id": teller_id, "booking_id": cmd.booking_id, "request": cmd.request }),
                    Idem::Yes,
                )
            }
            "no_show_booking" => {
                let cmd: bookings::NoShowBookingCommand = match serde_json::from_str(&item.payload)
                {
                    Ok(c) => c,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                (
                    serde_json::json!({ "op": "no_show_booking", "teller_id": teller_id, "booking_id": cmd.booking_id }),
                    Idem::Yes,
                )
            }
            // A LAN mirror-relay backup: the payload IS the `/sync/replay` envelope
            // (verbatim from the originating device, with the ORIGINAL teller_id), so
            // it posts as-is and dedups server-side against the originator's own copy.
            "lan_mirror" => {
                let envelope: serde_json::Value = match serde_json::from_str(&item.payload) {
                    Ok(v) => v,
                    Err(e) => return SendOutcome::Dead(format!("payload: {e}")),
                };
                (envelope, Idem::Yes)
            }
            other => return SendOutcome::Dead(format!("unknown op_type {other}")),
        };

        match self.api.post_json("/sync/replay", &envelope).await {
            Ok(body) => {
                // Bump/unbump reply 204 No Content. An EMPTY body is the real
                // backend's ack; a NON-empty 200 for these is a captive-portal stub
                // → keep queued. (Checked before the JSON-object guard below, which
                // reads an empty body as portal-suspicious — correct for the JSON
                // ops, wrong for these 204s.)
                if matches!(item.op_type.as_str(), "bump_kitchen" | "unbump_kitchen") {
                    return if body.trim().is_empty() {
                        SendOutcome::Acked(None)
                    } else {
                        SendOutcome::Offline
                    };
                }
                // A LAN mirror wraps any op (a 204 bump or a JSON-object fire/settle);
                // an empty body OR a real JSON object is the backend's ack. A non-empty
                // non-object (HTML portal) keeps the backup queued.
                if item.op_type == "lan_mirror" {
                    return if body.trim().is_empty() || replay_backend_object(&body).is_some() {
                        SendOutcome::Acked(None)
                    } else {
                        SendOutcome::Offline
                    };
                }
                // Captive-portal / transparent-proxy defense. Our backend ALWAYS
                // answers /sync/replay with a JSON object (the op's result). A 200
                // carrying a Wi-Fi login page (HTML), a redirect stub, or an empty
                // body is NOT our backend — acking it would SILENTLY DROP a queued
                // sale. Treat any non-JSON-object 200 as a connectivity blip so the
                // op stays queued and reschedules (no retry budget burned).
                let json = match replay_backend_object(&body) {
                    Some(v) => v,
                    None => return SendOutcome::Offline,
                };
                let obj = &json;
                match item.op_type.as_str() {
                    // Cache the server's authoritative shift so the device reflects
                    // server-derived fields (opening_cash_was_edited, etc.). A 2xx
                    // object we can't decode as a Shift still means the open LANDED
                    // (replay is idempotent) — count it, don't loop forever.
                    "open_shift" => {
                        if let Ok(server) =
                            serde_json::from_value::<madar_api::models::Shift>(obj.clone())
                        {
                            // Only refresh the local shift when this ack is for the
                            // shift the device is CURRENTLY on. A late ack of a prior or
                            // abandoned optimistic open (the teller has since closed it
                            // or moved to another shift) must NOT clobber the newer
                            // current shift with this stale server snapshot.
                            let is_current =
                                shift::current(&self.store).ok().flatten().map(|s| s.id)
                                    == Some(server.id.to_string());
                            if is_current {
                                let _ = shift::save(&self.store, &server);
                            }
                            SendOutcome::Acked(Some(server.id.to_string()))
                        } else {
                            SendOutcome::Acked(None)
                        }
                    }
                    // The money path. `OrderFull` flattens the order, so a real
                    // create response carries the order `id` at the TOP level. A
                    // JSON-object 200 WITHOUT a top-level `id` isn't a successful
                    // create (a proxy/portal stub) — keep it queued rather than ack
                    // a phantom sale. (Also finally captures the server order id,
                    // which the old `order.id` lookup never found post-flatten.)
                    "create_order" => match obj.get("id").and_then(|x| x.as_str()) {
                        Some(id) => {
                            // Bridge the client-minted order id → the server id so a
                            // later lookup (e.g. void-by-client-id) can resolve it.
                            // (The id_map row was never populated before — latent.)
                            let _ = self.store.id_map_put("order", &item.id, id);
                            // Advance this shift's synced base to the number the
                            // server actually assigned, so the NEXT ring-up predicts
                            // the right `#N` online too (where the order leaves the
                            // queue the instant it acks).
                            if let (Some(sid), Some(n)) = (
                                item.shift_id.as_deref(),
                                obj.get("order_number").and_then(|v| v.as_i64()),
                            ) {
                                checkout::bump_order_base(&self.store, sid, n);
                            }
                            SendOutcome::Acked(Some(id.to_string()))
                        }
                        None => SendOutcome::Offline,
                    },
                    // Ticket ops return their view/order, which carries a top-level
                    // `id`. A JSON-object 200 WITHOUT one is a portal/proxy stub —
                    // keep it queued rather than ack a phantom fire/settle.
                    "open_ticket" | "ticket_add_round" | "settle_open_ticket" | "void_ticket" => {
                        match obj.get("id").and_then(|x| x.as_str()) {
                            Some(id) => {
                                // A SETTLE hands back the paid order it just
                                // materialised. Record it: the settle call itself
                                // answers only "is this still queued", and by the
                                // time it returns the ticket has left the board —
                                // so without this nothing knows which order the
                                // money became, and a receipt cannot be printed
                                // after settling.
                                if item.op_type == "settle_open_ticket" {
                                    let _ = self.store.id_map_put("order", &item.id, id);
                                }
                                SendOutcome::Acked(Some(id.to_string()))
                            }
                            None => SendOutcome::Offline,
                        }
                    }
                    _ => SendOutcome::Acked(None),
                }
            }
            Err(e) => classify_send(e, idem),
        }
    }

    /// Milliseconds to add to a queued timestamp to re-base it from the skew the
    /// device had at enqueue to the fresh skew we hold now (correct-at-sync). 0
    /// when either offset is unknown (legacy rows) — never makes things worse.
    fn rebase_delta_ms(&self, item: &store::OutboxItem) -> i64 {
        let now_skew_ms = self
            .clock_skew_secs
            .load(std::sync::atomic::Ordering::Relaxed)
            .saturating_mul(1000);
        match item.clock_offset_ms {
            Some(then) => now_skew_ms.saturating_sub(then),
            None => 0,
        }
    }

    /// True if two timestamps fall on DIFFERENT branch-local calendar days — used
    /// to stop a clock-skew re-base from moving an order's created_at off the day
    /// its (already-printed) order_ref encodes.
    fn crosses_branch_day(
        &self,
        a: &Option<Option<chrono::DateTime<chrono::FixedOffset>>>,
        b: &Option<Option<chrono::DateTime<chrono::FixedOffset>>>,
    ) -> bool {
        let tz = timefmt::branch_tz(&self.store);
        let day = |f: &Option<Option<chrono::DateTime<chrono::FixedOffset>>>| {
            f.as_ref()
                .and_then(|o| o.as_ref())
                .map(|dt| dt.with_timezone(&tz).date_naive())
        };
        match (day(a), day(b)) {
            (Some(da), Some(db)) => da != db,
            _ => false,
        }
    }

    /// Wall-clock time CORRECTED by the last-known server skew. Queued ops must be
    /// stamped with this (not raw `Utc::now()`) so a till whose clock is wrong
    /// doesn't future-date its writes — the backend's `reject_if_future` would
    /// 400 a future-stamped open_shift/order and dead-letter the whole chain.
    /// Mirrors Flutter's `TimeUtils.now = DateTime.now() + offset`; the drain's
    /// `rebase_delta_ms` then only corrects for CHANGES in the skew between
    /// enqueue and send. The stamped offset is recorded per row in
    /// `clock_offset_ms` (via `outbox_meta`), keeping the two halves consistent.
    fn corrected_now(&self) -> chrono::DateTime<chrono::Utc> {
        // `saturating_mul` + the ±48h skew clamp (net.rs) keep this from overflowing
        // even if a bogus `Date` header or a corrupt persisted skew slipped through.
        let skew_ms = self
            .clock_skew_secs
            .load(std::sync::atomic::Ordering::Relaxed)
            .saturating_mul(1000);
        chrono::Utc::now() + chrono::Duration::milliseconds(skew_ms)
    }

    /// Clear a SPURIOUS auth-park by ASKING, rather than by guessing from `exp`.
    ///
    /// This used to un-park whenever the cached token had not expired, on the
    /// theory that an unexpired token could only have been refused by something
    /// standing in front of our backend. That theory is wrong in every case where
    /// a live token is revoked rather than lapsed — a rotated signing secret, a
    /// deactivated user, a suspended org — and it produced a loop nobody could get
    /// out of: un-park, drain, 401, re-park, forever, with the banner suppressed on
    /// the same "not expired yet" reasoning. The teller's only way out was to WAIT
    /// for the token to expire.
    ///
    /// One authenticated request settles it. If the backend accepts the bearer, the
    /// park really was spurious and the queue resumes; if it refuses, the park was
    /// right and stays. A transport failure decides nothing and leaves it parked,
    /// which costs nothing — a parked queue drains no differently from an offline
    /// one, and the banner is online-gated anyway.
    ///
    /// Only ever reached while parked, so it adds no request to a healthy till.
    async fn unpark_if_token_accepted(&self) {
        use std::sync::atomic::Ordering::Relaxed;
        if !self.auth_paused.load(Relaxed) || !self.api.has_bearer() {
            return;
        }
        if madar_api::apis::auth_api::get_my_permissions(&self.api.config())
            .await
            .is_ok()
        {
            self.auth_paused.store(false, Relaxed);
        }
    }

    /// Drop a BORROWED (foreign) bearer + its persisted token and require this teller
    /// to relogin under their OWN account: clears the borrow flag, nulls the bearer,
    /// and sets `auth_paused`, which is on its own what raises the reauth banner
    /// (a same-teller online relogin clears it).
    fn invalidate_borrowed_token(&self) {
        use std::sync::atomic::Ordering::Relaxed;
        self.borrowed_token.store(false, Relaxed);
        self.api.set_bearer(None);
        self.auth_paused.store(true, Relaxed);
        let updated = {
            let mut g = self.session.write().unwrap_or_else(|e| e.into_inner());
            if let Some(s) = g.as_mut() {
                s.token = None;
            }
            g.clone()
        };
        if let Some(s) = updated {
            let _ = self.store.blob_put(session::K_SESSION_BLOB, &s.to_blob());
        }
    }
}

/// What a single send attempt resolved to (drives the outbox state machine).
enum SendOutcome {
    /// Applied (or idempotently already-applied); carries the server id if known.
    Acked(Option<String>),
    /// Permanent rejection — dead-letter, surface in the stuck list.
    Dead(String),
    /// 401 — park the whole queue until the next successful login.
    AuthExpired,
    /// Connectivity blip — reschedule without burning retry budget; stop the pass.
    Offline,
    /// Retryable server/transport error — counted exponential backoff.
    Retry(String),
}

/// Idempotency profile of an endpoint, deciding how 409/404 are read.
enum Idem {
    /// Not idempotent for our purposes: 409/404 are genuine rejections → dead.
    No,
    /// Idempotent already-applied: 409/404 → treat as success.
    Yes,
    /// Void: 409 → already-voided (success); 404 → order never synced → dead.
    VoidIdem,
}

/// Captive-portal / transparent-proxy guard for a `/sync/replay` 200. Our backend
/// always answers with a JSON OBJECT (the op's result). A 200 carrying a Wi-Fi
/// login page (HTML), a redirect stub, an empty body, or a bare JSON array/scalar
/// is NOT our backend — return `None` so the caller keeps the op queued instead
/// of acking (and silently dropping) a real sale. Returns the parsed object only
/// when the body is genuinely our backend's shape.
fn replay_backend_object(body: &str) -> Option<serde_json::Value> {
    serde_json::from_str::<serde_json::Value>(body)
        .ok()
        .filter(serde_json::Value::is_object)
}

/// Classify a `CoreError` from a send into a `SendOutcome` per the endpoint's
/// idempotency profile. Mirrors the Flutter drain's per-status branches.
fn classify_send(err: CoreError, idem: Idem) -> SendOutcome {
    match err {
        CoreError::Offline { .. } => SendOutcome::Offline,
        CoreError::Unauthenticated { .. } => SendOutcome::AuthExpired,
        // 5xx / timeouts / undecodable 2xx — retry with backoff.
        CoreError::Transient { detail } | CoreError::Internal { detail } => {
            SendOutcome::Retry(detail)
        }
        // Permanent validation/permission — retrying can't help.
        CoreError::Validation { detail, .. } | CoreError::Forbidden { action: detail, .. } => {
            SendOutcome::Dead(detail)
        }
        CoreError::Server { status, detail, .. } => match (status, idem) {
            (409, Idem::Yes) | (409, Idem::VoidIdem) | (404, Idem::Yes) => SendOutcome::Acked(None),
            // void 404 = the order never landed → don't silently swallow the void.
            (404, Idem::VoidIdem) => {
                SendOutcome::Dead(format!("order not found on server — {detail}"))
            }
            _ => SendOutcome::Dead(detail),
        },
    }
}

/// Map the host's friendlier void-reason key to the backend's accepted enum
/// (`customer_request` | `wrong_order` | `quality_issue` | `other`). Backend keys
/// pass through unchanged, and anything unrecognized falls back to `other` (always
/// accepted) so a void never dead-letters on a reason-vocabulary mismatch — which
/// would silently keep a refunded sale as revenue.
fn map_void_reason(reason: &str) -> madar_api::models::VoidReason {
    use madar_api::models::VoidReason as R;
    match reason {
        "customer" | "customer_request" => R::CustomerRequest,
        "mistake" | "wrong_order" => R::WrongOrder,
        "quality" | "quality_issue" => R::QualityIssue,
        _ => R::Other,
    }
}

/// Narrow a minor-unit cash amount to the i32 the wire expects, REJECTING a value
/// that doesn't fit rather than silently wrapping it to a negative (a corrupt
/// amount that would mis-reconcile the drawer). Amounts this large are never real
/// cash, so a validation error is the right surface.
fn cash_i32(v: i64, field: &str) -> Result<i32, CoreError> {
    i32::try_from(v).map_err(|_| CoreError::Validation {
        field: field.into(),
        detail: "amount is out of range".into(),
    })
}

// ── offline read cache (server lists mirrored to kv) ─────────────────────────

/// Write-through cache for a server-fetched list, keyed in the kv store. Persists
/// the projected views as JSON so the NEXT read returns the last-synced snapshot
/// when offline (or when the live fetch fails) — the history screens (orders,
/// shifts, cash, delivery) stay populated offline instead of collapsing to only
/// the locally-queued rows. Free functions, not methods, because `#[cfg_attr(feature = "uniffi-ffi", uniffi::exportNone)]`
/// can't carry a generic across the FFI. Best-effort: a write failure skips the cache.
fn cache_views<T: serde::Serialize>(store: &store::Store, key: &str, views: &[T]) {
    if let Ok(json) = serde_json::to_string(views) {
        let _ = store.kv_put(key, &json);
    }
}

/// Synthesize an offline-overlay `TicketView` for a still-queued fire so the waiter
/// sees the ticket immediately, before it syncs. Status `"queued"`; the subtotal is
/// a rough estimate from the priced items (addons excluded — the server recomputes
/// authoritatively on sync); detailed lines arrive with the server view.
fn queued_ticket_view(
    cmd: &tickets::FireTicketCommand,
    event_at: &str,
    // The waiter who fired it (the current session) — the server round-trip will
    // confirm the same name once the queued fire syncs.
    waiter_name: Option<String>,
) -> tickets::TicketView {
    let subtotal_minor: i64 = cmd
        .request
        .items
        .iter()
        .map(|it| it.unit_price.flatten().unwrap_or(0) as i64 * it.quantity as i64)
        .sum();
    tickets::TicketView {
        id: cmd.ticket_id.clone(),
        ticket_ref: None,
        table_id: cmd.request.table_id.flatten().map(|u| u.to_string()),
        status: "queued".into(),
        customer_name: cmd.request.customer_name.clone().flatten(),
        waiter_name,
        guest_count: cmd.request.guest_count.flatten(),
        subtotal_minor,
        // A fire the server has not seen has no priced bill: the branch's
        // effective tax policy is the server's to apply, and a guess here would
        // be a number the settle then contradicts.
        bill: None,
        order_id: None,
        opened_at: event_at.to_string(),
        queued_offline: true,
        lines: Vec::new(),
    }
}

/// Read a previously cached server list (empty when nothing's been synced yet).
fn cached_views<T: serde::de::DeserializeOwned>(store: &store::Store, key: &str) -> Vec<T> {
    store
        .kv_get(key)
        .ok()
        .flatten()
        .and_then(|s| serde_json::from_str::<Vec<T>>(&s).ok())
        .unwrap_or_default()
}

// ── cached history retention ─────────────────────────────────────────────────
/// How long a closed shift and its orders stay fully readable offline before
/// they are swapped out. See [`MadarCore::prune_stale_caches`].
pub(crate) const CACHE_RETENTION_DAYS: i64 = 30;

/// The per-shift / per-order cache prefixes the retention sweep covers. These
/// grow one row per shift or order forever; everything else under `cache:` is a
/// fixed set of live mirrors replaced wholesale on each pull.
pub(crate) const CACHE_HISTORY_PREFIXES: &[&str] = &[
    "cache:shift_report:", // the Z-report behind a past shift
    "cache:shift_orders:", // that shift's order list
    "cache:cash:",         // its drawer movements
    "cache:order:",        // individual orders kept for offline reprint
];

/// Ceilings on how MANY rows each history prefix may hold, applied after the age
/// sweep. The window bounds how old cached history gets; it does not bound how
/// much of it there is, and `cache:order:` grows by one full order record for
/// every order anyone opens — hundreds a day in a busy branch, all of them well
/// inside 30 days.
///
/// The shift-scoped caches get a smaller ceiling simply because they are
/// one-per-shift: 400 is already far more shifts than 30 days can produce, so it
/// only ever catches a clock that jumped.
pub(crate) const CACHE_ROW_CAPS: &[(&str, u32)] = &[
    ("cache:order:", 2_000),
    ("cache:shift_report:", 400),
    ("cache:shift_orders:", 400),
    ("cache:cash:", 400),
];

// ── outbox backoff (mirrors offline_queue.dart constants) ────────────────────
const K_MAX_RETRIES: i64 = 8;
const K_BASE_BACKOFF_MS: i64 = 2_000; // 2s
const K_MAX_BACKOFF_MS: i64 = 300_000; // 5min
const K_NETWORK_RETRY_MS: i64 = 15_000; // fixed reschedule for connectivity blips
                                        // Consecutive UNCONFIRMED failed /health probes before we drop the online banner.
                                        // A real outbox send failure flips offline immediately; this only gates the
                                        // empty-backlog case so a lone resume/rotation blip can't flap the banner.
const K_OFFLINE_CONFIRM: u32 = 2;
const K_ACKED_RETENTION_MS: i64 = 48 * 60 * 60 * 1000; // keep acked rows 48h

/// Epoch milliseconds (matches the outbox's `next_attempt_at` / `synced_at`).
fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

/// Exponential backoff with jitter: BASE·2^(attempts-1), capped at MAX, plus a
/// deterministic per-item jitter (0–999ms, seeded by seq — no RNG dep) to avoid
/// a thundering herd when many items came due together.
fn compute_backoff_ms(attempts: i64, seq: i64) -> i64 {
    let shift = (attempts.clamp(1, 30) - 1) as u32;
    let exp = K_BASE_BACKOFF_MS.saturating_mul(1i64.checked_shl(shift).unwrap_or(i64::MAX));
    let capped = exp.min(K_MAX_BACKOFF_MS);
    let jitter = (seq.wrapping_mul(2_654_435_761)).rem_euclid(1000);
    (capped + jitter).min(K_MAX_BACKOFF_MS)
}

/// Re-base a double-`Option` timestamp (the generated `Option<Option<DateTime>>`).
fn rebase_dopt(field: &mut Option<Option<chrono::DateTime<chrono::FixedOffset>>>, delta_ms: i64) {
    if delta_ms != 0 {
        if let Some(Some(dt)) = field.as_mut().map(|o| o.as_mut()) {
            *dt += chrono::Duration::milliseconds(delta_ms);
        }
    }
}

// ── JWT expiry (a LOCAL hint, never a trust boundary) ─────────────────────────
// The client reads the cached token's `exp` only to decide whether the reauth
// banner is warranted and whether a 401-park is spurious. The signature is NEVER
// verified here — the server stays the sole authority; a forged/garbage token at
// worst keeps the banner up (conservative). This is why no jsonwebtoken/base64
// dependency is pulled: we decode just the middle (payload) segment by hand.

/// Minimal dependency-free base64url decoder (RFC 4648 §5, padding optional) for
/// the JWT payload segment. `None` on any invalid character.
fn base64url_decode(s: &str) -> Option<Vec<u8>> {
    fn sextet(c: u8) -> Option<u8> {
        match c {
            b'A'..=b'Z' => Some(c - b'A'),
            b'a'..=b'z' => Some(c - b'a' + 26),
            b'0'..=b'9' => Some(c - b'0' + 52),
            b'-' => Some(62),
            b'_' => Some(63),
            _ => None,
        }
    }
    let s = s.trim_end_matches('=');
    let mut out = Vec::with_capacity(s.len() * 3 / 4);
    let mut buf: u32 = 0;
    let mut bits: u32 = 0;
    for &c in s.as_bytes() {
        buf = (buf << 6) | sextet(c)? as u32;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buf >> bits) as u8);
        }
    }
    Some(out)
}

/// The decoded JWT payload (middle segment) as JSON, or `None` if not a
/// well-formed three-segment token. No signature check (see above).
fn jwt_payload(token: &str) -> Option<serde_json::Value> {
    let payload = token.split('.').nth(1)?;
    let json = base64url_decode(payload)?;
    serde_json::from_slice(&json).ok()
}

/// The `exp` (epoch seconds) of a JWT, or `None` if absent/non-numeric/malformed.
fn jwt_exp_secs(token: &str) -> Option<i64> {
    jwt_payload(token)?.get("exp").and_then(|e| e.as_i64())
}

/// The `sub` (subject = the user/teller id this token was minted for), or `None`.
/// Used to confirm a cached token is owned by the teller now unlocking offline.
fn jwt_sub(token: &str) -> Option<String> {
    jwt_payload(token)?
        .get("sub")
        .and_then(|s| s.as_str())
        .map(str::to_string)
}

/// Whether `token`'s `exp` is at/past `now_secs`. Treats an unreadable token as
/// expired (conservative — a token we can't parse can't be trusted to still work).
fn token_is_expired(token: &str, now_secs: i64) -> bool {
    match jwt_exp_secs(token) {
        Some(exp) => now_secs >= exp,
        None => true,
    }
}

// ── shift + routing (sync reads) ─────────────────────────────────────────────
#[cfg_attr(feature = "uniffi-ffi", uniffi::exportNone)]
impl MadarCore {
    /// The device's current shift (open or closed), served from the local store.
    pub fn current_shift(&self) -> Result<Option<shift::ShiftView>, CoreError> {
        shift::current(&self.store)
    }

    /// Suggested opening cash for the next shift (minor units) — the previous
    /// shift's declared closing, for cash continuity. 0 when none is known. The
    /// open-shift screen prefills this; deviating from it requires a reason.
    pub fn suggested_opening_cash_minor(&self) -> Result<i64, CoreError> {
        shift::suggested_opening_cash(&self.store)
    }

    /// The screen to show — decided ENTIRELY from core state (no host params; the
    /// device binding lives in the core store now). Resolution order: device-setup
    /// (unbound or mid-reconfigure) → login → kitchen-role device → the KDS for its
    /// configured station → waiter → tickets (no shift) → teller open/closed shift.
    pub fn app_route(&self) -> AppRoute {
        let cfg = device::load(&self.store);
        if !cfg.configured() {
            return AppRoute::DeviceSetup;
        }
        let guard = self.session.read().unwrap_or_else(|e| e.into_inner());
        let session = match guard.as_ref() {
            Some(s) => s,
            None => return AppRoute::Login,
        };
        // A kitchen-role device shows the KDS for its configured station (it needs
        // the session for the bus + kitchen permission, but holds no shift). With
        // no station bound yet, it must finish device setup first.
        if session.snapshot.role == "kitchen" {
            return match cfg.station_id {
                Some(station_id) => AppRoute::KitchenDisplay { station_id },
                None => AppRoute::DeviceSetup,
            };
        }
        // Waiters take orders and fire tickets but hold NO shift — route them to the
        // waiter screen BEFORE the open-shift gate (which they could never satisfy).
        if session.snapshot.role == "waiter" {
            return AppRoute::WaiterTickets;
        }
        // An open shift counts only if it belongs to THIS teller (a stale shift
        // from a previous teller on the device must not route them past setup).
        match shift::current(&self.store) {
            Ok(Some(s)) if s.is_open && s.teller_id == session.snapshot.user_id => AppRoute::Order,
            _ => AppRoute::OpenShift,
        }
    }

    /// Tear down the device's realtime subscription, if any. Idempotent — safe to
    /// call on sign-out, branch switch, or before re-subscribing with new topics.
    pub fn unsubscribe_realtime(&self) {
        let mut slot = self.realtime.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(h) = slot.take() {
            h.stop();
        }
    }

    /// Whether a realtime subscription is currently held (the supervisor task is
    /// alive — not a statement about live connectivity, which the listener reports).
    pub fn is_realtime_subscribed(&self) -> bool {
        self.realtime
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .is_some()
    }

    // ── device binding (branch / till / station / printer) ────────────────────
    // All persisted in the core store; the host reads `device_config()` to render
    // device-setup / Settings and calls the setters. No host-side device state.

    /// The device's current binding (for device-setup / Settings + screen chrome).
    pub fn device_config(&self) -> device::DeviceConfigView {
        device::load(&self.store).into()
    }

    /// Bind the device to a branch (device setup). Clears the reconfigure flag.
    pub fn set_device_branch(
        &self,
        branch_id: String,
        branch_name: Option<String>,
    ) -> Result<(), CoreError> {
        device::update(&self.store, |c| {
            c.branch_id = Some(branch_id);
            c.branch_name = branch_name;
            c.reconfiguring = false;
        })?;
        Ok(())
    }

    /// Bind the device's till (POS drawer). `None` = use the branch default till.
    pub fn set_device_till(&self, till_id: Option<String>) -> Result<(), CoreError> {
        device::update(&self.store, |c| {
            c.till_id = till_id.filter(|s| !s.is_empty())
        })?;
        Ok(())
    }

    /// Bind the device's kitchen station (a KDS device). `None` clears it.
    pub fn set_device_station(&self, station_id: Option<String>) -> Result<(), CoreError> {
        device::update(&self.store, |c| {
            c.station_id = station_id.filter(|s| !s.is_empty())
        })?;
        Ok(())
    }

    /// Set the device's receipt/chit printer (host:port + brand `"epson"`/`"star"`).
    /// `None` host clears it.
    pub fn set_device_printer(
        &self,
        host: Option<String>,
        port: Option<u16>,
        brand: Option<String>,
    ) -> Result<(), CoreError> {
        device::update(&self.store, |c| {
            c.printer_host = host.filter(|s| !s.is_empty());
            c.printer_port = port;
            c.printer_brand = brand.filter(|s| !s.is_empty());
        })?;
        Ok(())
    }

    /// Pick the printer transport — `"bluetooth"` (Classic SPP) or anything else
    /// (defaults to `"lan"`, raw-TCP). Only the active transport's binding is used
    /// at print time; the other's address is kept so switching back is lossless.
    pub fn set_device_printer_transport(&self, kind: String) -> Result<(), CoreError> {
        let kind = if kind == "bluetooth" {
            "bluetooth"
        } else {
            "lan"
        };
        device::update(&self.store, |c| {
            c.printer_transport = Some(kind.to_string());
        })?;
        Ok(())
    }

    /// Bind the paired Bluetooth printer (MAC + cached display name). `None`
    /// address clears the binding. The CORE stores it but never opens the socket
    /// — the Flutter transport connects; this is just the single source of truth.
    pub fn set_device_printer_bt(
        &self,
        address: Option<String>,
        name: Option<String>,
    ) -> Result<(), CoreError> {
        device::update(&self.store, |c| {
            c.printer_bt_address = address.filter(|s| !s.is_empty());
            c.printer_bt_name = name.filter(|s| !s.is_empty());
        })?;
        Ok(())
    }

    /// Pin the receipt raster width in dots (the Settings paper-size toggle):
    /// 384 for a 58 mm roll, 576 for 80 mm. `None` clears the override so the
    /// width falls back to the transport default (Bluetooth → 384, LAN → 576).
    pub fn set_device_printer_paper(&self, dots: Option<u32>) -> Result<(), CoreError> {
        device::update(&self.store, |c| {
            c.printer_paper_dots = dots.filter(|&d| d >= 64);
        })?;
        Ok(())
    }

    /// Re-enter device setup (keeps the binding but forces the setup screen until
    /// `set_device_branch` confirms a — possibly new — branch).
    pub fn start_reconfigure(&self) -> Result<(), CoreError> {
        device::update(&self.store, |c| c.reconfiguring = true)?;
        Ok(())
    }

    /// Wipe the device binding entirely (factory reset of the device config).
    pub fn clear_device(&self) -> Result<(), CoreError> {
        device::save(&self.store, &device::DeviceConfig::default())
    }
}

// ── realtime bus (one SSE per device) ─────────────────────────────────────────
#[cfg_attr(feature = "uniffi-ffi", uniffi::export(async_runtime = "tokio"))]
impl MadarCore {
    /// Open (or REPLACE) the device's ONE realtime subscription for `branch_id`,
    /// asking only for `topics` the device's role/mode needs (e.g. `["delivery"]`
    /// on a till, `["kitchen"]` on a KDS, `["tickets","kitchen"]` on a waiter
    /// device). Any prior subscription is torn down first — never two connections.
    /// Events flow to `listener` until `unsubscribe_realtime`; the supervisor
    /// reconnects on drops (jittered backoff) and resumes from `Last-Event-ID`. A
    /// 401 stops it (re-subscribe after the next login). Must run on the tokio
    /// runtime so the supervisor task can spawn.
    pub async fn subscribe_realtime(
        &self,
        branch_id: String,
        topics: Vec<String>,
        listener: Box<dyn realtime::EventListener>,
    ) {
        // Share the listener (Arc) so the LAN relay bridge forwards to the SAME sink
        // as the cloud SSE — a cross-LAN event and its cloud twin both land here and
        // dedup via the host's snapshot-reload.
        let listener: Arc<dyn realtime::EventListener> = Arc::from(listener);
        *self
            .unified_listener
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Some(listener.clone());
        let client = self.api.realtime_client();
        let handle = realtime::spawn_supervisor(client, branch_id, topics, listener, None);
        let mut slot = self.realtime.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(old) = slot.take() {
            old.stop();
        }
        *slot = Some(handle);
    }

    /// Start the device's ONE session-level realtime subscription — the unified entry
    /// the hosts call once after login (and on connectivity-regain). The CORE owns all
    /// the policy: it derives the topics from the signed-in role ([`topics_for_role`]),
    /// opens/replaces the single SSE, and wires an [`AlertingListener`] so every event
    /// (cloud OR LAN) both refreshes the host's board (via `listener`) AND raises a
    /// deduped, localized alert through `player` (ping + notification + haptic). The
    /// host's `player` is pure platform primitive — no decision logic. Idempotent in
    /// effect (replaces any prior subscription). Errs only if not signed in.
    pub async fn start_realtime(
        &self,
        listener: Box<dyn realtime::EventListener>,
        player: Box<dyn realtime::RealtimePlayer>,
    ) -> Result<(), CoreError> {
        // Idempotent: the supervisor auto-reconnects, so a re-call (e.g. on
        // connectivity-regain or a screen re-appearing) is a no-op. A fresh login
        // starts clean — `unsubscribe_realtime` in signOut cleared the handle.
        if self
            .realtime
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .is_some()
        {
            return Ok(());
        }
        let session = self
            .current_session()
            .ok_or_else(|| CoreError::Unauthenticated {
                detail: "sign in before starting realtime".into(),
            })?;
        let branch_id = session
            .branch_id
            .clone()
            .ok_or_else(|| CoreError::Validation {
                field: "branch".into(),
                detail: "no branch bound".into(),
            })?;
        let topics = realtime::topics_for_role(&session.role);
        // The alerting wrapper is the unified listener → the LAN bridge alerts too.
        let alerting: Arc<dyn realtime::EventListener> = Arc::new(realtime::AlertingListener::new(
            Arc::from(listener),
            Arc::from(player),
            self.locale.clone(),
            session.role.clone(),
            self.branch_timezone(),
        ));
        *self
            .unified_listener
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Some(alerting.clone());
        let client = self.api.realtime_client();
        // Cloud-only events (online orders, bookings) get re-published on the LAN
        // by every device that heard them, under one deterministic id, so a
        // peer with no internet still hears each once. See `LanCloudRelay`.
        let relay: Arc<dyn realtime::CloudRelay> = Arc::new(LanCloudRelay {
            lan: self.lan.clone(),
            branch_id: branch_id.clone(),
        });
        let handle = realtime::spawn_supervisor(client, branch_id, topics, alerting, Some(relay));
        let mut slot = self.realtime.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(old) = slot.take() {
            old.stop();
        }
        *slot = Some(handle);
        Ok(())
    }
}

// ── LAN offline relay (Phase E) ───────────────────────────────────────────────

/// The cloud→LAN bridge: a cloud-only event this device just heard over SSE is
/// re-published on the LAN as a DISPLAY event (no replay op — the write already
/// happened in the cloud). The `msg_id` is derived from the branch + the SSE
/// event id, so every till that relays the same event sends the same id and
/// the LAN dedup delivers it once per peer. No-op without a running relay.
struct LanCloudRelay {
    lan: Arc<Mutex<Option<Arc<lan::LanRelay>>>>,
    branch_id: String,
}

impl realtime::CloudRelay for LanCloudRelay {
    fn relay(&self, event_id: &str, event: &realtime::RealtimeEvent) {
        let relay = self.lan.lock().unwrap_or_else(|e| e.into_inner()).clone();
        let Some(relay) = relay else { return };
        let msg_id = format!("cloud:{}:{}", self.branch_id, event_id);
        let topic = event
            .event_type
            .split('.')
            .next()
            .map(|t| if t == "booking" { "bookings" } else { t })
            .unwrap_or("orders")
            .to_string();
        let event = event.clone();
        let at = chrono::Utc::now().timestamp_millis();
        tokio::spawn(async move {
            relay
                .publish_with_id(msg_id, &topic, &event.event_type, event.data, None, at)
                .await;
        });
    }
}

/// The relay's inbound sink: forward a verified LAN event to the unified listener
/// (so the board refreshes just like a cloud event) and — for a write carrying a
/// replay op — MIRROR that op into the outbox so the write reaches the cloud even if
/// the originating device dies first. Shares the core's ONE `Store` (`Arc`, the SAME
/// connection — single-writer invariant preserved, no second WAL writer to contend),
/// plus a clone of the shared listener slot.
struct LanBridge {
    listener: Arc<Mutex<Option<Arc<dyn realtime::EventListener>>>>,
    store: Arc<store::Store>,
}

impl lan::LanInbound for LanBridge {
    fn on_lan_message(&self, msg: &lan::LanMessage) {
        // 1. Merge into the LAN-KDS overlay so an offline fire/bump shows on THIS
        //    device's board (the host refresh below reads the cached feed + overlay).
        match msg.event_type.as_str() {
            "kitchen.fired" => {
                if let Ok(t) = serde_json::from_str::<kds::KdsTicketView>(&msg.data) {
                    lan_kds_merge_ticket(&self.store, t);
                }
            }
            "kitchen.item_bumped" | "kitchen.item_unbumped" => {
                if let Some(id) = serde_json::from_str::<serde_json::Value>(&msg.data)
                    .ok()
                    .and_then(|v| v.get("item_id").and_then(|x| x.as_str()).map(String::from))
                {
                    lan_kds_apply_bump(&self.store, &id, msg.event_type == "kitchen.item_bumped");
                }
            }
            _ => {}
        }
        // 2. Forward to the unified listener (host refreshes the relevant board).
        if let Some(l) = self
            .listener
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
        {
            l.on_event(realtime::RealtimeEvent {
                event_type: msg.event_type.clone(),
                data: msg.data.clone(),
            });
        }
        // 3. Mirror-relay: enqueue the carried replay op as our own durable backup,
        //    idempotency-keyed so the cloud dedups it against the originator's copy.
        if let Some(op) = &msg.replay_op {
            mirror_replay_op(&self.store, op);
        }
    }
}

/// kv key for the LAN-overlay kitchen feed (projections of un-synced fires).
const LAN_KDS_CACHE: &str = "cache:kds:lan";

fn lan_kds_read(store: &store::Store) -> Vec<kds::KdsTicketView> {
    store
        .kv_get(LAN_KDS_CACHE)
        .ok()
        .flatten()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}
fn lan_kds_write(store: &store::Store, v: &[kds::KdsTicketView]) {
    if let Ok(j) = serde_json::to_string(v) {
        let _ = store.kv_put(LAN_KDS_CACHE, &j);
    }
}
/// Upsert a LAN-projected kitchen ticket (by derived id) into the overlay.
fn lan_kds_merge_ticket(store: &store::Store, t: kds::KdsTicketView) {
    let mut v = lan_kds_read(store);
    match v.iter_mut().find(|x| x.id == t.id) {
        Some(slot) => *slot = t,
        None => v.push(t),
    }
    lan_kds_write(store, &v);
}
/// Apply a LAN-relayed bump to the overlay (greys the line on a peer's board too).
fn lan_kds_apply_bump(store: &store::Store, item_id: &str, bumped: bool) {
    let mut v = lan_kds_read(store);
    kds::apply_lan_bump(&mut v, item_id, bumped);
    lan_kds_write(store, &v);
}

/// Enqueue a received LAN write-op into the local outbox (robustness #4). The
/// envelope is the `/sync/replay` body; we re-wrap it as a `lan_mirror` outbox row
/// keyed on the op's idempotency key so a duplicate (we + the originator both drain
/// it) collapses server-side. Best-effort — a parse/enqueue failure just drops the
/// backup (the originator's own outbox is still the primary path).
fn mirror_replay_op(store: &store::Store, envelope_json: &str) {
    let Ok(env) = serde_json::from_str::<serde_json::Value>(envelope_json) else {
        return;
    };
    let op = env.get("op").and_then(|v| v.as_str()).unwrap_or_default();
    let teller_id = env
        .get("teller_id")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());
    let event_at = chrono::Utc::now().to_rfc3339();

    // Kitchen bump/unbump TOGGLE one line's state. Key the backup LINE-scoped (op-
    // agnostic) and UPSERT so the LATEST tap wins: a bump→unbump→bump burst must not
    // dedup-keep the first bump and then replay the stale unbump if the device dies.
    if op == "bump_kitchen_item" || op == "unbump_kitchen_item" {
        let line = env.get("item_id").and_then(|v| v.as_str()).unwrap_or(op);
        let _ = store.upsert_mirror(&store::NewOutboxOp {
            id: format!("lanmirror:kline:{line}"),
            op_type: "lan_mirror".into(),
            idempotency_key: format!("kline:{line}"),
            payload: envelope_json.to_string(),
            event_at,
            depends_on_seq: None,
            user_id: teller_id,
            clock_offset_ms: None,
            shift_id: None,
        });
        return;
    }

    // Every other op is distinct (its own idempotency key) → keep-first dedup on the
    // op kind + its primary idempotency handle.
    let handle = env
        .get("request")
        .and_then(|r| r.get("idempotency_key"))
        .and_then(|v| v.as_str())
        .or_else(|| env.get("item_id").and_then(|v| v.as_str()))
        .or_else(|| env.get("ticket_id").and_then(|v| v.as_str()))
        .unwrap_or(op);
    let _ = store.enqueue(&store::NewOutboxOp {
        id: format!("lanmirror:{op}:{handle}"),
        op_type: "lan_mirror".into(),
        idempotency_key: format!("{op}:{handle}"),
        payload: envelope_json.to_string(),
        event_at,
        depends_on_seq: None,
        user_id: teller_id,
        clock_offset_ms: None,
        shift_id: None,
    });
}

/// Split a manual hub address (`host` or `host:port`) → (`host`, `port`), defaulting
/// to the fixed relay port so a manager need only type the hub's IP.
fn parse_hub_addr(addr: &str) -> (String, u16) {
    match addr.rsplit_once(':') {
        Some((h, p)) => (h.to_string(), p.parse().unwrap_or(lan::DEFAULT_TCP_PORT)),
        None => (addr.to_string(), lan::DEFAULT_TCP_PORT),
    }
}

impl MadarCore {
    /// Stable per-device id for the LAN mesh — minted once, persisted in the store.
    fn lan_device_id(&self) -> String {
        if let Ok(Some(id)) = self.store.kv_get("lan_device_id") {
            if !id.is_empty() {
                return id;
            }
        }
        let id = uuid::Uuid::new_v4().to_string();
        let _ = self.store.kv_put("lan_device_id", &id);
        id
    }

    /// The org's LAN secret (hex) from the cached offline-auth bundle — the HMAC root.
    fn lan_secret_hex(&self) -> Option<String> {
        let raw = self.store.kv_get(session::BUNDLE_KEY).ok()??;
        let v: serde_json::Value = serde_json::from_str(&raw).ok()?;
        v.get("lan_secret")
            .and_then(|x| x.as_str())
            .map(|s| s.to_string())
    }

    /// This device's current OPEN shift id (advertised to the LAN shift gate), if any.
    fn current_open_shift_id(&self) -> Option<String> {
        shift::current(&self.store)
            .ok()
            .flatten()
            .filter(|s| s.is_open)
            .map(|s| s.id)
    }

    /// Push the current open-shift state to the running relay (the till advert) — call
    /// after a shift opens/closes so the LAN shift gate reflects it within seconds.
    fn lan_sync_open_shift(&self) {
        if let Some(relay) = self.lan.lock().unwrap_or_else(|e| e.into_inner()).clone() {
            relay.set_open_shift(self.current_open_shift_id());
        }
    }

    /// Publish a write event over the LAN (instant cross-device delivery): `data` is
    /// the display payload (e.g. a fire projection) and `replay_op` the mirror-relay
    /// envelope. No-op when the relay isn't up.
    async fn lan_publish(
        &self,
        topic: &str,
        event_type: &str,
        data: String,
        replay_op: Option<String>,
    ) {
        let relay = self.lan.lock().unwrap_or_else(|e| e.into_inner()).clone();
        if let Some(relay) = relay {
            let at = self.corrected_now().timestamp_millis();
            relay.publish(topic, event_type, data, replay_op, at).await;
        }
    }
}

// ── LAN relay control (Phase E) ───────────────────────────────────────────────
#[cfg_attr(feature = "uniffi-ffi", uniffi::export(async_runtime = "tokio"))]
impl MadarCore {
    /// Start the LAN relay for the signed-in branch (idempotent). Needs a session +
    /// the cached bundle's LAN secret; binds the embedded server, begins discovery
    /// (mDNS + UDP beacon), advertises this till's open shift, and wires any manual
    /// hub. Safe to call after every login — a no-op if already running.
    pub async fn lan_start(&self) -> Result<(), CoreError> {
        if self.lan.lock().unwrap_or_else(|e| e.into_inner()).is_some() {
            return Ok(());
        }
        let session = self
            .current_session()
            .ok_or_else(|| CoreError::Unauthenticated {
                detail: "sign in before starting the LAN relay".into(),
            })?;
        let branch_id = session
            .branch_id
            .clone()
            .ok_or_else(|| CoreError::Validation {
                field: "branch".into(),
                detail: "no branch bound".into(),
            })?;
        let secret = self.lan_secret_hex().ok_or_else(|| CoreError::Validation {
            field: "lan_secret".into(),
            detail: "no LAN secret — sign in online once to fetch the bundle".into(),
        })?;
        let dev = device::load(&self.store);
        let cfg = lan::LanConfig {
            device_id: self.lan_device_id(),
            branch_id: branch_id.clone(),
            role: session.role.clone(),
            station_id: dev.station_id.clone(),
            key: lan::branch_key(&secret, &branch_id),
            tcp_port: lan::DEFAULT_TCP_PORT,
            beacon_port: lan::DEFAULT_BEACON_PORT,
        };
        // Tag every subsequent crash report with the device's OPERATING identity —
        // the install uuid, the branch and the role. Non-identifying by design (see
        // `obs::set_device_scope`), and this is the earliest point where all three
        // are known, so a report from a terminal in another city can be traced to a
        // station without naming a person.
        crate::obs::set_device_scope(Some(&cfg.device_id), Some(&cfg.branch_id), Some(&cfg.role));
        let bridge = Arc::new(LanBridge {
            listener: self.unified_listener.clone(),
            store: self.store.clone(), // the SAME store instance, shared via Arc
        });
        let relay = Arc::new(lan::LanRelay::new(cfg, bridge));
        relay.start().await?;
        relay.set_open_shift(self.current_open_shift_id());
        if let Some(hub) = dev.lan_hub.filter(|s| !s.trim().is_empty()) {
            let (host, port) = parse_hub_addr(hub.trim());
            relay.add_manual_hub(host, port);
        }
        *self.lan.lock().unwrap_or_else(|e| e.into_inner()) = Some(relay);
        Ok(())
    }
}

#[cfg_attr(feature = "uniffi-ffi", uniffi::exportNone)]
impl MadarCore {
    /// Stop + tear down the LAN relay (idempotent). Call on logout / branch switch.
    pub fn lan_stop(&self) {
        if let Some(relay) = self.lan.lock().unwrap_or_else(|e| e.into_inner()).take() {
            relay.stop();
        }
    }

    /// Whether the LAN relay is currently running.
    pub fn lan_active(&self) -> bool {
        self.lan.lock().unwrap_or_else(|e| e.into_inner()).is_some()
    }

    /// Live discovered peers + manual hubs (a "LAN: N devices" diagnostics chip).
    pub fn lan_peer_count(&self) -> u32 {
        self.lan
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .map(|r| r.peer_count())
            .unwrap_or(0)
    }

    /// The LAN shift-open gate: is a till at this branch advertising a FRESH open
    /// shift right now? The freshest "is the branch operating" signal (it beats the
    /// backend, which may not yet know a till opened/closed). `false` if not running.
    pub fn lan_branch_has_open_till(&self) -> bool {
        self.lan
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .map(|r| r.branch_has_open_till())
            .unwrap_or(false)
    }

    /// Persist a manual LAN hub-IP (`host` or `host:port`) in the device config and,
    /// if the relay is running, register it immediately. `None`/empty clears it.
    pub fn set_device_lan_hub(&self, hub: Option<String>) -> Result<(), CoreError> {
        let hub = hub.filter(|s| !s.trim().is_empty());
        device::update(&self.store, |c| c.lan_hub = hub.clone())?;
        if let (Some(addr), Some(relay)) = (
            hub,
            self.lan.lock().unwrap_or_else(|e| e.into_inner()).clone(),
        ) {
            let (host, port) = parse_hub_addr(addr.trim());
            relay.add_manual_hub(host, port);
        }
        Ok(())
    }
}

// ── localization (sync) ──────────────────────────────────────────────────────
#[cfg_attr(feature = "uniffi-ffi", uniffi::exportNone)]
impl MadarCore {
    /// Localized UI string for `key` in the device locale (en/ar; falls back to
    /// en, then the key). The single source of truth for both hosts.
    pub fn tr(&self, key: String) -> String {
        i18n::tr(&self.current_locale(), &key)
    }
    /// The active locale (BCP-47).
    pub fn locale(&self) -> String {
        self.current_locale()
    }
    /// Change the active UI locale at runtime (e.g. "en" / "ar"). Strings,
    /// RTL, and catalog `*_translations` all re-resolve on the next read; the
    /// host persists the choice and re-renders.
    pub fn set_locale(&self, locale: String) {
        *self.locale.write().unwrap_or_else(|e| e.into_inner()) = locale;
    }
    /// Whether the locale is right-to-left (host flips layout direction).
    pub fn is_rtl(&self) -> bool {
        i18n::is_rtl(&self.current_locale())
    }
}

// ── receipt rendering (sync; pure byte assembly) ─────────────────────────────
#[cfg_attr(feature = "uniffi-ffi", uniffi::exportNone)]
impl MadarCore {
    /// Render a placed order's receipt to printer bytes ready to stream to a
    /// thermal printer. The receipt is rasterized to a 1-bit bitmap (logo +
    /// Arabic, matching the on-screen preview) and wrapped in the brand's raster
    /// protocol — text commands can't drive the raster-only TSP143III. Labels
    /// resolve from the active locale; `store_name` (branch) and `currency` come
    /// from the host. `width` (a character count) is retained for API stability;
    /// the raster width now comes from the device's paper config
    /// (`DeviceConfig::paper_dots` — 384 dots for a 58 mm Bluetooth portable, 576
    /// for a 72 mm LAN head). Pair with `send_to_printer`.
    /// Render ONE item as a kitchen chit — no money, no logo, no totals.
    ///
    /// A different document from a receipt rather than a shorter one: a cook
    /// needs the item, the count, what was changed and which table it belongs
    /// to, and everything else is noise on a pass. Per item on purpose, so a
    /// chit follows its plate and the grill never reads the bar's work.
    pub fn render_kitchen_chit(
        &self,
        chit: receipt::KitchenChit,
        width: u32,
        brand: receipt::PrinterBrand,
    ) -> Vec<u8> {
        let loc = self.current_locale();
        let tr = |k: &str| i18n::tr(&loc, k);
        let labels = receipt::KitchenChitLabels {
            heading: tr("kitchen.chit_heading"),
            table: tr("kitchen.chit_table"),
            note: tr("kitchen.chit_note"),
        };
        receipt::escpos_kitchen_chit(&chit, &labels, width, brand)
    }

    pub fn render_receipt(
        &self,
        mut receipt: checkout::ReceiptView,
        store_name: String,
        currency: String,
        width: u32,
        brand: receipt::PrinterBrand,
    ) -> Vec<u8> {
        // Stamp the printed receipt in the BRANCH timezone — the ESC/POS formatter
        // renders the timestamp in its own offset, so convert it first (a Cairo
        // store prints Cairo time even on a device set to another zone).
        receipt.created_at = timefmt::to_branch_local(&self.store, &receipt.created_at);
        let loc = self.current_locale();
        let tr = |k: &str| i18n::tr(&loc, k);
        let ctx = receipt::EscPosCtx {
            store_name,
            currency,
            width,
            labels: receipt::ReceiptLabels {
                order: tr("receipt.order"),
                reference: tr("receipt.ref"),
                voided: tr("receipt.voided"),
                delivery: tr("receipt.delivery"),
                channel_in_mall: tr("delivery.in_mall"),
                channel_outside: tr("delivery.outside"),
                customer: tr("receipt.customer"),
                phone: tr("receipt.phone"),
                address: tr("receipt.address"),
                zone: tr("receipt.zone"),
                delivery_ref: tr("receipt.delivery_ref"),
                payment_hint: tr("receipt.payment_hint"),
                notes: tr("receipt.notes"),
                subtotal: tr("order.subtotal"),
                discount: tr("order.discount"),
                service_charge: tr("order.service_charge"),
                tax: tr("order.tax"),
                delivery_fee: tr("receipt.delivery_fee"),
                total: tr("order.total"),
                tip: tr("order.tip"),
                cash: tr("receipt.cash"),
                change: tr("order.change"),
                payment: tr("receipt.payment"),
                teller: tr("receipt.teller"),
                served_by: tr("receipt.served_by"),
                queued: tr("order.queued_hint"),
                thank_you: tr("receipt.thank_you"),
            },
        };
        // Logo bytes were cached (online) into the blob store by the branch fetch;
        // read-through here so printing stays offline-capable. None → name-only header.
        let logo = self
            .store
            .blob_get(checkout::KEY_ORG_LOGO_PNG)
            .ok()
            .flatten();
        // Raster width + cut come from the device's paper config, not the host —
        // a 58 mm Bluetooth portable renders 384 dots with no cut, a 72 mm LAN
        // head renders 576 dots with a partial cut.
        let cfg = device::load(&self.store);
        let bitmap = render::render_receipt(&receipt, &ctx, logo.as_deref(), cfg.paper_dots());
        receipt::raster_for(brand, &bitmap, cfg.printer_has_cutter())
    }

    /// Cash-drawer kick bytes for the chosen printer dialect — send via
    /// `send_to_printer` right after a CASH sale's receipt so the till pops.
    /// Caller gates on `receipt.is_cash` (and skips it on reprints).
    pub fn cash_drawer_kick(&self, brand: receipt::PrinterBrand) -> Vec<u8> {
        receipt::drawer_kick_for(brand)
    }

    /// Render the shift report (Z-report) to printer bytes — rasterized like
    /// `render_receipt` (text commands can't drive the TSP143III). `width` is
    /// retained for API stability; the raster width comes from the device's paper
    /// config (`DeviceConfig::paper_dots`). Pair with `send_to_printer`.
    pub fn render_shift_report(
        &self,
        mut report: shift::ShiftReportView,
        store_name: String,
        currency: String,
        width: u32,
        brand: receipt::PrinterBrand,
        orders: Vec<orders::OrderSummaryView>,
    ) -> Vec<u8> {
        let _ = width;
        // Stamp the report's timestamps in the BRANCH timezone (as render_receipt
        // does for created_at), so the printed times read in the store's local time.
        report.opened_at = timefmt::to_branch_local(&self.store, &report.opened_at);
        report.printed_at = timefmt::to_branch_local(&self.store, &report.printed_at);
        if let Some(c) = report.closed_at.clone() {
            report.closed_at = Some(timefmt::to_branch_local(&self.store, &c));
        }
        let loc = self.current_locale();
        let tr = |k: &str| i18n::tr(&loc, k);
        let labels = receipt::ShiftReportLabels {
            title: tr("shift.report_title"),
            business_date: tr("shift.business_date"),
            printed_at: tr("shift.printed_at"),
            teller: tr("shift.teller"),
            opened: tr("shift.opened_at"),
            closed: tr("shifts.closed"),
            interim: tr("shift.interim"),
            payments: tr("shift.payments"),
            orders: tr("shift.orders"),
            total_collected: tr("shift.total_collected"),
            drawer_ops: tr("shift.drawer_ops"),
            cash_in: tr("shift.cash_in"),
            cash_out: tr("shift.cash_out"),
            cash_recon: tr("shift.cash_recon"),
            opening: tr("shift.opening_cash"),
            opening_mismatch: tr("shift.opening_mismatch"),
            opening_reason: tr("shift.opening_reason_label"),
            expected: tr("shift.expected_cash"),
            actual: tr("shift.counted_cash"),
            not_closed: tr("shift.not_closed"),
            difference: tr("shift.difference"),
            short_by: tr("shift.drawer_short"),
            over_by: tr("shift.drawer_over"),
            voided: tr("history.voided"),
            transactions: tr("shift.transactions"),
            end_of_report: tr("shift.end_of_report"),
            cash_moves: tr("shift.cash_moves"),
            by_method: tr("shift.by_method"),
        };
        let cfg = device::load(&self.store);
        let bitmap = render::render_shift_report(
            &report,
            &store_name,
            &currency,
            &labels,
            &orders,
            cfg.paper_dots(),
        );
        receipt::raster_for(brand, &bitmap, cfg.printer_has_cutter())
    }
}

// ── catalog reads (sync; serve the local mirror, always succeed offline) ─────
#[cfg_attr(feature = "uniffi-ffi", uniffi::exportNone)]
impl MadarCore {
    /// Themed style (icon key + gradient palette) for a category/item name —
    /// the host maps `icon` to a glyph and paints the gradient. Pure; mirrors
    /// Flutter's `CatStyle.of`. `dark` picks the dark-mode palette.
    pub fn category_style(&self, name: String, dark: bool) -> catstyle::CatStyleView {
        catstyle::category_style(&name, dark)
    }

    /// The parsed + projected catalog for the CURRENT locale — built once,
    /// then served from the cache until `refresh_catalog` invalidates it (or
    /// the locale changes). Every read path shares this snapshot, so a toggle
    /// in the customization sheet or a grid reload no longer re-parses the kv
    /// JSON mirrors.
    fn catalog(&self) -> Result<Arc<CatalogSnapshot>, CoreError> {
        let locale = self.current_locale();
        if let Some(cached) = self
            .catalog_cache
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .filter(|c| c.locale == locale)
        {
            return Ok(cached.clone());
        }
        // Build OUTSIDE the lock — parsing a large menu takes milliseconds and
        // must not block concurrent cached readers. A racing rebuild is benign
        // (same inputs; last write wins).
        // Resolve cached image paths HERE (one pass per snapshot) so the host
        // never does per-cell FFI on the catalog grid.
        let mut items = menu::menu_items(&self.store, &locale)?;
        for item in &mut items {
            item.local_image_path = item
                .image_url
                .as_deref()
                .and_then(|u| self.images.path_if_cached(u));
        }
        for step in items.iter_mut().flat_map(|i| i.recipe_steps.iter_mut()) {
            step.local_animation_path = step
                .animation_url
                .as_deref()
                .map(|u| self.animation_absolute_url(u))
                .and_then(|u| self.animations.path_if_cached(&u));
        }
        let mut bundles = menu::bundles(&self.store, &locale)?;
        for bundle in &mut bundles {
            bundle.local_image_path = bundle
                .image_url
                .as_deref()
                .and_then(|u| self.images.path_if_cached(u));
        }
        let snapshot = Arc::new(CatalogSnapshot {
            categories: menu::categories(&self.store, &locale)?,
            addons: menu::addons(&self.store, &locale)?,
            unified: menu::unified_doc(&self.store),
            locale,
            items,
            bundles,
        });
        *self.catalog_cache.lock().unwrap_or_else(|e| e.into_inner()) = Some(snapshot.clone());
        Ok(snapshot)
    }

    /// Drop the parsed snapshot — called after anything that rewrites the kv
    /// catalog mirrors or the on-disk image cache. The next read re-projects.
    fn invalidate_catalog_cache(&self) {
        *self.catalog_cache.lock().unwrap_or_else(|e| e.into_inner()) = None;
    }

    pub fn list_menu_items(&self) -> Result<Vec<menu::MenuItemView>, CoreError> {
        Ok(self.catalog()?.items.clone())
    }
    pub fn list_categories(&self) -> Result<Vec<menu::CategoryView>, CoreError> {
        Ok(self.catalog()?.categories.clone())
    }
    pub fn list_addon_catalog(&self) -> Result<Vec<menu::AddonItemView>, CoreError> {
        Ok(self.catalog()?.addons.clone())
    }
    /// Bundles orderable right now — status active and within their date/time
    /// window at `now` (branch-local). The host passes its local time so the
    /// window is evaluated in the till's timezone (Flutter parity).
    pub fn available_bundles(
        &self,
        now_rfc3339: String,
    ) -> Result<Vec<menu::BundleView>, CoreError> {
        let now = chrono::DateTime::parse_from_rfc3339(&now_rfc3339).map_err(|_| {
            CoreError::Validation {
                field: "now".into(),
                detail: "bad timestamp".into(),
            }
        })?;
        // local_image_path is already resolved on the snapshot.
        Ok(self
            .catalog()?
            .bundles
            .iter()
            .filter(|b| menu::bundle_available(b, now))
            .cloned()
            .collect())
    }
    pub fn list_payment_methods(&self) -> Result<Vec<menu::PaymentMethodView>, CoreError> {
        menu::payment_methods(&self.store, &self.current_locale())
    }
    pub fn list_discounts(&self) -> Result<Vec<menu::DiscountView>, CoreError> {
        menu::discounts(&self.store, &self.current_locale())
    }
}

// ── cart (sync; client-only order state, offline-safe, kv-persisted) ──────────
#[cfg_attr(feature = "uniffi-ffi", uniffi::exportNone)]
impl MadarCore {
    /// The current cart lines (empty when none).
    pub fn cart_lines(&self) -> Result<Vec<cart::CartLineView>, CoreError> {
        cart::lines(&self.store)
    }
    /// Add one unit of a menu item (merges into the matching line). The host
    /// passes the resolved display name + unit price so the cart is self-contained.
    pub fn cart_add(
        &self,
        item_id: String,
        name: String,
        unit_price_minor: i64,
    ) -> Result<Vec<cart::CartLineView>, CoreError> {
        cart::add(&self.store, &item_id, &name, unit_price_minor)
    }
    /// Add a CONFIGURED line (size + addons + optionals + notes). The core
    /// resolves the charged prices from the cached catalog (size unit price;
    /// addon swap-delta vs additive; optional prices) and merges identical
    /// configs. `addons` carry the chosen ids + quantities; the prices are
    /// resolved here, not trusted from the host.
    pub fn cart_add_configured(
        &self,
        item_id: String,
        size_label: Option<String>,
        addons: Vec<cart::AddonSelection>,
        optional_field_ids: Vec<String>,
        qty: i64,
        notes: Option<String>,
    ) -> Result<Vec<cart::CartLineView>, CoreError> {
        let catalog = self.catalog()?;
        let item = catalog
            .items
            .iter()
            .find(|i| i.id == item_id)
            .ok_or_else(|| CoreError::Validation {
                field: "item".into(),
                detail: "unknown item".into(),
            })?;
        let line = cart::resolve_line(
            item,
            &catalog.addons,
            size_label,
            &addons,
            &optional_field_ids,
            qty,
            notes,
        );
        cart::add_resolved(&self.store, line)
    }
    /// Add a configured BUNDLE line: the fixed bundle price + each component's
    /// chosen item/size/addons/optionals. The core resolves the component
    /// up-charges from the catalog (component base/size price is never charged —
    /// the bundle price covers it) and merges identical bundle configs.
    pub fn cart_add_bundle(
        &self,
        bundle_id: String,
        components: Vec<cart::BundleComponentSelection>,
        qty: i64,
    ) -> Result<Vec<cart::CartLineView>, CoreError> {
        let catalog = self.catalog()?;
        let bundle = catalog
            .bundles
            .iter()
            .find(|b| b.id == bundle_id)
            .ok_or_else(|| CoreError::Validation {
                field: "bundle".into(),
                detail: "unknown bundle".into(),
            })?;
        let line =
            cart::resolve_bundle_line(bundle, &catalog.items, &catalog.addons, &components, qty);
        cart::add_resolved(&self.store, line)
    }
    /// Active addons offered for an item, with their CHARGED price resolved (swap
    /// delta / full) — the customization sheet groups these by `addon_type`.
    pub fn list_item_addons(&self, item_id: String) -> Result<Vec<cart::ItemAddonView>, CoreError> {
        let catalog = self.catalog()?;
        let item = catalog
            .items
            .iter()
            .find(|i| i.id == item_id)
            .ok_or_else(|| CoreError::Validation {
                field: "item".into(),
                detail: "unknown item".into(),
            })?;
        Ok(cart::item_addons(item, &catalog.addons))
    }
    /// The item's MODIFIER GROUPS — the grouped (unified-model) projection of
    /// `list_item_addons` + the item's priced optionals: slot-configured groups
    /// keep their min/max/required, unslotted addon types get default groups
    /// (milk single-select by convention), optionals surface as one
    /// `Optional`-kind group. Charged prices use the same swap-delta rules as
    /// the flat sheet, so rendering by groups instead of types changes nothing
    /// about the money. Works offline (pure projection over the mirrored catalog).
    pub fn list_item_modifier_groups(
        &self,
        item_id: String,
    ) -> Result<Vec<cart::ModifierGroupView>, CoreError> {
        let catalog = self.catalog()?;
        let item = catalog
            .items
            .iter()
            .find(|i| i.id == item_id)
            .ok_or_else(|| CoreError::Validation {
                field: "item".into(),
                detail: "unknown item".into(),
            })?;
        // Prefer the UNIFIED mirror (`/catalog/sync`, the new modifier model) —
        // authoritative grouping/naming/constraints from the backend. Absent
        // (old backend / pre-backfill org / item not present) ⇒ the legacy
        // projection over the mirrored flat streams, same view shape.
        if let Some(unified) = catalog
            .unified
            .as_ref()
            .and_then(|doc| doc.groups_for(&item_id))
        {
            return Ok(cart::item_modifier_groups_unified(
                item,
                &catalog.addons,
                unified,
                &catalog.locale,
            ));
        }
        Ok(cart::item_modifier_groups(item, &catalog.addons))
    }
    /// Check a selection against the item's group constraints (min/max/required).
    /// Empty result = valid; each entry is one violated group for inline display.
    /// Hosts call this before `cart_add_configured` (which itself stays lenient —
    /// enforcement is a UI concern, resolving stays defensive).
    pub fn validate_item_selections(
        &self,
        item_id: String,
        addons: Vec<cart::AddonSelection>,
        optional_field_ids: Vec<String>,
    ) -> Result<Vec<cart::GroupViolationView>, CoreError> {
        let groups = self.list_item_modifier_groups(item_id)?;
        Ok(cart::validate_group_selections(
            &groups,
            &addons,
            &optional_field_ids,
        ))
    }
    /// Live recipe preview for the current selection (size + addons + optionals).
    /// Pure projection over the mirrored catalog, so the customization sheet can
    /// recompute on every toggle, online or offline. Mirrors the Flutter teller
    /// app: base by size, milk/coffee swaps, additive addons (× qty), and
    /// optional-field ingredient contributions.
    pub fn compute_recipe(
        &self,
        item_id: String,
        size_label: Option<String>,
        addons: Vec<cart::AddonSelection>,
        optional_field_ids: Vec<String>,
    ) -> Result<Vec<recipe::ComputedRecipeLineView>, CoreError> {
        let catalog = self.catalog()?;
        let item = catalog
            .items
            .iter()
            .find(|i| i.id == item_id)
            .ok_or_else(|| CoreError::Validation {
                field: "item".into(),
                detail: "unknown item".into(),
            })?;
        Ok(recipe::compute_recipe(
            item,
            &catalog.addons,
            size_label.as_deref(),
            &addons,
            &optional_field_ids,
        ))
    }
    /// Set a line's absolute quantity (by its key); `qty <= 0` removes the line.
    pub fn cart_set_qty(
        &self,
        item_id: String,
        qty: i64,
    ) -> Result<Vec<cart::CartLineView>, CoreError> {
        cart::set_qty(&self.store, &item_id, qty)
    }
    /// Remove a line entirely (stashed for undo — see `cart_restore_removed`).
    pub fn cart_remove(&self, item_id: String) -> Result<Vec<cart::CartLineView>, CoreError> {
        cart::remove(&self.store, &item_id)
    }
    /// Undo the last `cart_remove` — re-inserts the swiped-away line. No-op if
    /// nothing was removed (or it was already restored / the cart was cleared).
    pub fn cart_restore_removed(&self) -> Result<Vec<cart::CartLineView>, CoreError> {
        cart::restore_last_removed(&self.store)
    }
    /// Empty the cart.
    pub fn cart_clear(&self) -> Result<(), CoreError> {
        cart::clear(&self.store)
    }
    // ── held orders (server-backed parked carts, branch-shared) ───────────
    //
    // The old device-local drafts became first-class backend entities that own
    // floor tables. Every mutation is optimistic-local (the `held` mirror) plus
    // a queued `/sync/replay` op — same offline-first walk as orders/tickets.

    /// Park the current cart as a held order (no table). `draft_id`/`started_at`
    /// keep a re-parked (previously restored) draft's identity + strip position.
    pub fn hold_cart(
        &self,
        name: String,
        draft_id: Option<String>,
        started_at: Option<String>,
    ) -> Result<(), CoreError> {
        self.hold_cart_on_table(name, draft_id, started_at, None)
            .map(|_| ())
    }

    /// Park the current cart, optionally onto a floor table. Returns `true`
    /// when the requested table was DROPPED because it's taken per the local
    /// mirror (the park itself always succeeds — data beats position; the host
    /// shows a "table was taken" toast). The queued op re-arbitrates on sync.
    pub fn hold_cart_on_table(
        &self,
        name: String,
        draft_id: Option<String>,
        started_at: Option<String>,
        table_id: Option<String>,
    ) -> Result<bool, CoreError> {
        let branch = self.session_branch_id()?;
        let payload = cart::cart_payload(&self.store)?;
        if payload
            .get("lines")
            .and_then(|l| l.as_array())
            .map(|a| a.is_empty())
            .unwrap_or(true)
        {
            return Err(CoreError::Validation {
                field: "cart".into(),
                detail: "cart is empty".into(),
            });
        }
        let id = draft_id
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
        let created = started_at
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| self.corrected_now().to_rfc3339());
        let device = self.lan_device_id();
        let was_on = self.draft_table(&id);
        let (entry, conflict) = held::park_local(
            &self.store,
            &id,
            &branch,
            &name,
            payload.clone(),
            table_id.clone(),
            &device,
            &created,
        )?;
        // The ORDER is NOT queued. Parked drafts are device-local by design
        // (the 5 Sep refactor) and the backend has no held-order endpoints at
        // all any more, so an op for one could only ever dead-letter — which
        // is exactly what it did: every park wrote a permanent stuck row into
        // the sync screen's list. Its TABLE is a different matter; see
        // `sync_hold_occupancy`.
        self.sync_hold_occupancy(was_on, entry.table_id.clone(), false)?;
        cart::clear(&self.store)?;
        Ok(conflict)
    }

    /// The branch's parked orders (every till's), newest first. Orders being
    /// edited on another till come back `locked_by_other`. Also lifts any
    /// pre-upgrade device-local drafts into the shared model (once).
    pub fn list_drafts(&self) -> Result<Vec<cart::DraftView>, CoreError> {
        self.migrate_legacy_drafts();
        held::drafts(&self.store, &self.lan_device_id())
    }

    /// Restore a held order into the cart (claims it for this till so no other
    /// till edits it concurrently). Errors when another till holds the claim.
    pub fn restore_draft(&self, id: String) -> Result<Vec<cart::CartLineView>, CoreError> {
        let device = self.lan_device_id();
        let now = self.corrected_now().to_rfc3339();
        let payload = held::claim_local(&self.store, &id, &device, &now)?;
        let lines = cart::set_cart_payload(&self.store, &payload)?;
        // Device-local: nothing to queue (see `hold_cart_on_table`).
        Ok(lines)
    }

    /// Give a restored draft's claim back WITHOUT re-parking (the cart wasn't
    /// changed) — e.g. the teller switches away right after resuming.
    pub fn release_draft(&self, id: String) -> Result<(), CoreError> {
        let device = self.lan_device_id();
        let now = self.corrected_now().to_rfc3339();
        // Device-local: nothing to queue (see `hold_cart_on_table`).
        held::release_local(&self.store, &id, &device, &now)
    }

    /// Discard a parked draft (tombstone; frees its table + waitlist wish).
    pub fn discard_draft(&self, id: String) -> Result<(), CoreError> {
        let device = self.lan_device_id();
        let now = self.corrected_now().to_rfc3339();
        let was_on = self.draft_table(&id);
        // The order is device-local (see `hold_cart_on_table`); its table is
        // not. Nobody ever sat, so the table goes straight back to the room.
        held::terminate_local(&self.store, &id, "discarded", Some(&device), &now)?;
        self.sync_hold_occupancy(was_on, None, false)
    }

    /// Mark a restored draft COMPLETED after its cart checked out (the host
    /// calls this right after a successful ring-up of a resumed draft). Frees
    /// the table; the queued op drains AFTER the order create (FIFO).
    pub fn complete_draft(&self, id: String, _order_id: Option<String>) -> Result<(), CoreError> {
        let now = self.corrected_now().to_rfc3339();
        let was_on = self.draft_table(&id);
        // The order is device-local (see `hold_cart_on_table`); its table is
        // not. The party ATE, so the table needs a cloth before anyone else
        // sits — `dirty`, not `free`, on the server exactly as locally.
        held::terminate_local(&self.store, &id, "completed", None, &now)?;
        self.sync_hold_occupancy(was_on, None, true)
    }

    /// Assign / move / unassign a parked draft's table (interactive — loud
    /// error when the table is taken per the local mirror). Syncs as a re-park.
    pub fn assign_draft_table(
        &self,
        id: String,
        table_id: Option<String>,
    ) -> Result<(), CoreError> {
        let now = self.corrected_now().to_rfc3339();
        let was_on = self.draft_table(&id);
        // The order is device-local (see `hold_cart_on_table`); its table is
        // not — a move releases the old one and takes the new one, in that
        // order.
        let out = held::assign_table_local(&self.store, &id, table_id, &now)?;
        self.sync_hold_occupancy(was_on, out.table_id, false)
    }

    /// Swap whatever sits on two tables (held orders and/or waiter tickets) —
    /// one empty side = a move. Optimistic for held occupants; the queued op is
    /// the arbiter and the next pull reconciles.
    pub fn swap_tables(&self, table_a: String, table_b: String) -> Result<(), CoreError> {
        let branch = self.session_branch_id()?;
        let now = self.corrected_now().to_rfc3339();
        // A parked draft on either side moves too, and the server cannot see
        // that: its swap sets each side's status from the TICKET it found, so
        // it would free a table this till just moved a draft onto.
        let held_before = self.held_sides(&table_a, &table_b);
        held::swap_local(&self.store, &table_a, &table_b, &now)?;
        let cmd = held::SwapCommand {
            request: serde_json::json!({
                "branch_id": branch, "table_a": table_a, "table_b": table_b
            }),
        };
        self.enqueue_held_op(
            "swap_tables",
            format!("swap:{}", uuid::Uuid::new_v4()),
            &serde_json::to_string(&cmd)?,
        )?;
        // Queued AFTER the swap, so it lands last and has the final word on
        // the two statuses. Each op is a no-op server-side when a ticket owns
        // the table, so the ticket always wins the race.
        let held_after = self.held_sides(&table_a, &table_b);
        for (table, before, after) in [
            (&table_a, held_before.0, held_after.0),
            (&table_b, held_before.1, held_after.1),
        ] {
            match (before, after) {
                (false, true) => self.sync_hold_occupancy(None, Some(table.clone()), false)?,
                (true, false) => self.sync_hold_occupancy(Some(table.clone()), None, false)?,
                _ => {}
            }
        }
        Ok(())
    }

    /// Whether each of two tables carries a parked draft right now.
    fn held_sides(&self, a: &str, b: &str) -> (bool, bool) {
        let on = |t: &str| {
            held::held_on_table(&self.store, t, None)
                .ok()
                .flatten()
                .is_some()
        };
        (on(a), on(b))
    }

    /// The branch floor: sections + tables + held-order occupancy, fully
    /// offline. EMPTY when the branch has no layout — the host's feature gate.
    pub fn floor_layout(&self) -> Result<held::FloorLayoutView, CoreError> {
        held::layout(&self.store, &self.lan_device_id())
    }

    /// The transfer waitlist (waiting entries, FIFO, display-ready).
    pub fn list_transfer_queue(&self) -> Result<Vec<held::TransferQueueView>, CoreError> {
        held::transfer_queue(&self.store)
    }

    /// Queue a party (held order or open ticket) to move to a section or a
    /// specific table. An outside/no-table order queues too.
    pub fn create_transfer(
        &self,
        occupant_kind: String,
        occupant_id: String,
        target_section_id: Option<String>,
        target_table_id: Option<String>,
        note: Option<String>,
    ) -> Result<(), CoreError> {
        if target_section_id.is_none() && target_table_id.is_none() {
            return Err(CoreError::Validation {
                field: "target".into(),
                detail: "a transfer needs a target section or table".into(),
            });
        }
        let branch = self.session_branch_id()?;
        let now = self.corrected_now().to_rfc3339();
        let id = uuid::Uuid::new_v4().to_string();
        let from_table = if occupant_kind == "held_order" {
            held::get(&self.store, &occupant_id)?.and_then(|h| h.table_id)
        } else {
            None // a ticket's table is resolved server-side at create
        };
        held::create_transfer_local(
            &self.store,
            held::TransferWire {
                id: id.clone(),
                branch_id: branch.clone(),
                occupant_kind: occupant_kind.clone(),
                occupant_id: occupant_id.clone(),
                occupant_label: None,
                from_table_id: from_table,
                target_section_id: target_section_id.clone(),
                target_table_id: target_table_id.clone(),
                note: note.clone(),
                status: "waiting".into(),
                created_at: now.clone(),
                updated_at: now,
            },
        )?;
        let cmd = held::CreateTransferCommand {
            transfer_id: id.clone(),
            request: serde_json::json!({
                "id": id, "branch_id": branch, "occupant_kind": occupant_kind,
                "occupant_id": occupant_id, "target_section_id": target_section_id,
                "target_table_id": target_table_id, "note": note,
            }),
        };
        self.enqueue_held_op(
            "create_table_transfer",
            format!("transfer:{id}"),
            &serde_json::to_string(&cmd)?,
        )
    }

    /// Withdraw a waiting transfer wish.
    pub fn cancel_transfer(&self, id: String) -> Result<(), CoreError> {
        let now = self.corrected_now().to_rfc3339();
        held::cancel_transfer_local(&self.store, &id, &now)?;
        let cmd = held::TransferOpCommand {
            transfer_id: id.clone(),
            request: serde_json::json!({}),
        };
        self.enqueue_held_op(
            "cancel_table_transfer",
            format!("transfer-cancel:{id}:{}", uuid::Uuid::new_v4()),
            &serde_json::to_string(&cmd)?,
        )
    }

    /// Seat a waiting party on `table_id` (must satisfy its wish; loud error on
    /// a locally-occupied table).
    pub fn fulfill_transfer(&self, id: String, table_id: String) -> Result<(), CoreError> {
        let now = self.corrected_now().to_rfc3339();
        // A transfer for a PARKED DRAFT moves it between tables locally and the
        // server never hears of the draft, so the occupancy has to follow it.
        // A transfer for a waiter's ticket needs none of this: the server moves
        // the ticket and derives both statuses from it.
        let draft = held::transfer_held_occupant(&self.store, &id);
        let was_on = draft.as_deref().and_then(|d| self.draft_table(d));
        held::fulfill_transfer_local(&self.store, &id, &table_id, &now)?;
        let cmd = held::TransferOpCommand {
            transfer_id: id.clone(),
            request: serde_json::json!({ "table_id": table_id }),
        };
        self.enqueue_held_op(
            "fulfill_table_transfer",
            format!("transfer-fulfill:{id}:{}", uuid::Uuid::new_v4()),
            &serde_json::to_string(&cmd)?,
        )?;
        if draft.is_some() {
            self.sync_hold_occupancy(was_on, Some(table_id), false)?;
        }
        Ok(())
    }

    /// Keep the LOCAL canvas in step with a status the server is about to
    /// derive anyway — dirty after a checkout, free after a void or a move.
    ///
    /// Deliberately local-only: it queues nothing. The server reaches the same
    /// conclusion from the ticket's lifecycle, so sending it would be a second
    /// writer of a derived value, and the two would eventually disagree. This
    /// exists purely so the canvas is right the instant the sale lands, and
    /// while offline.
    pub fn mirror_table_status(&self, table_id: String, status: String) -> Result<(), CoreError> {
        if !matches!(status.as_str(), "free" | "held" | "seated" | "dirty") {
            return Err(CoreError::Validation {
                field: "status".into(),
                detail: "unknown table status".into(),
            });
        }
        held::set_table_state_local(&self.store, &table_id, Some(&status), None, false)
    }

    /// Clear a bussed table: the one human act a table's status cannot derive.
    ///
    /// Everything else about the status follows from the ticket on the table --
    /// seated when one lands, free when nobody vacated, dirty after a checkout.
    /// But no server can see that the plates are gone, so the teller says so,
    /// from the prompt right after the sale or the tables screen afterwards.
    ///
    /// This replaced a general "set any status, and optionally move the table
    /// to another section" call. That let a terminal assert a table was free
    /// while a ticket was open on it, and its server counterpart wrote the
    /// status with no lock and no occupancy check.
    ///
    /// Optimistic-local + queued, like every other floor op.
    pub fn clear_table(&self, table_id: String) -> Result<(), CoreError> {
        held::set_table_state_local(&self.store, &table_id, Some("free"), None, false)?;
        let cmd = held::TableStateCommand {
            table_id: table_id.clone(),
            request: serde_json::json!({}),
        };
        self.enqueue_held_op(
            "clear_table",
            format!("table-clear:{table_id}:{}", uuid::Uuid::new_v4()),
            &serde_json::to_string(&cmd)?,
        )
    }

    /// Push the OCCUPANCY of a device-local hold, and nothing else.
    ///
    /// A parked cart never leaves the till — not its lines, not its money, not
    /// its name. But which table it is sitting on is not the till's private
    /// business: it is a fact about the room. While it stayed local, the
    /// dashboard's floor and every other terminal were told a table with
    /// somebody's order waiting on it was free, and the next party got seated
    /// on top of it.
    ///
    /// So exactly one bit crosses the wire: taken, or given back. `bus` is the
    /// one thing the server cannot derive — whether the party ATE before the
    /// hold ended (checked out → the table needs a cloth) or never sat at all
    /// (discarded → straight back to the room).
    ///
    /// FIFO ordering carries a move: release the old table, then hold the new
    /// one, in that order.
    fn sync_hold_occupancy(
        &self,
        before: Option<String>,
        after: Option<String>,
        bus: bool,
    ) -> Result<(), CoreError> {
        if before == after {
            return Ok(());
        }
        if let Some(old) = before.clone().filter(|b| Some(b) != after.as_ref()) {
            let cmd = held::TableStateCommand {
                table_id: old.clone(),
                request: serde_json::json!({ "bus": bus }),
            };
            self.enqueue_held_op(
                "release_table",
                format!("table-release:{old}:{}", uuid::Uuid::new_v4()),
                &serde_json::to_string(&cmd)?,
            )?;
        }
        if let Some(new) = after.filter(|a| Some(a) != before.as_ref()) {
            let cmd = held::TableStateCommand {
                table_id: new.clone(),
                request: serde_json::json!({}),
            };
            self.enqueue_held_op(
                "hold_table",
                format!("table-hold:{new}:{}", uuid::Uuid::new_v4()),
                &serde_json::to_string(&cmd)?,
            )?;
        }
        Ok(())
    }

    /// The table a parked order is on right now, if the till still knows it.
    fn draft_table(&self, id: &str) -> Option<String> {
        held::get(&self.store, id)
            .ok()
            .flatten()
            .and_then(|h| h.table_id)
    }

    /// Enqueue one floor op (no shift gating — floor state floats free of
    /// tills, like waiter tickets).
    fn enqueue_held_op(
        &self,
        op_type: &str,
        op_id: String,
        payload: &str,
    ) -> Result<(), CoreError> {
        let (user_id, clock_offset_ms) = self.outbox_meta();
        self.store.enqueue(&store::NewOutboxOp {
            id: op_id.clone(),
            op_type: op_type.into(),
            idempotency_key: op_id,
            payload: payload.to_string(),
            event_at: self.corrected_now().to_rfc3339(),
            depends_on_seq: None,
            user_id,
            clock_offset_ms,
            shift_id: None,
        })?;
        Ok(())
    }

    /// One-time lift of pre-upgrade device-local drafts into the shared model.
    /// Needs a signed-in branch; silently skipped otherwise (runs again on the
    /// next `list_drafts`). Best-effort by design.
    fn migrate_legacy_drafts(&self) {
        let Ok(branch) = self.session_branch_id() else {
            return;
        };
        let device = self.lan_device_id();
        let Ok(lifted) = held::migrate_legacy(&self.store, &branch, &device) else {
            return;
        };
        // Lifting a pre-upgrade draft into the shared local model is itself a
        // local move — there is nothing on the server to tell about it.
        let _ = lifted;
    }
    /// Apply a discount (by id) to the cart — reflected in `cart_totals`.
    pub fn cart_set_discount(&self, discount_id: String) -> Result<(), CoreError> {
        cart::set_discount(&self.store, &discount_id)
    }
    /// Remove the cart discount.
    pub fn cart_clear_discount(&self) -> Result<(), CoreError> {
        cart::clear_discount(&self.store)
    }
    /// The selected discount id (for the tender UI), or `None`.
    pub fn cart_discount_id(&self) -> Result<Option<String>, CoreError> {
        cart::discount_id(&self.store)
    }
    /// Priced cart summary under the session's tax policy (tax-free when
    /// signed out), computed through the shared engine.
    pub fn cart_totals(&self) -> Result<cart::CartTotals, CoreError> {
        let policy = self
            .current_session()
            .map(|s| s.tax_policy())
            .unwrap_or_default();
        cart::totals(&self.store, &policy)
    }
}

/// A queued/failed outbox command, projected for the sync center.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct OutboxItemView {
    pub id: String,
    /// `open_shift` | `close_shift` | `create_order` | …
    pub op_type: String,
    /// `pending` | `inflight` | `dead`.
    pub status: String,
    pub attempts: i64,
    pub last_error: Option<String>,
    pub event_at: String,
}

/// One-shot sync health for the action-bar chip + offline banner. `pending` is
/// the in-flight/queued set, `failed` the stuck (dead) set, `online` the
/// session's connectivity. The host maps these to the chip label/tone.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SyncStatusView {
    pub pending: u32,
    pub failed: u32,
    /// Orders STRANDED by a dead `open_shift` (waiting on a dependency that will
    /// never ack). The drain auto-heals these onto the current shift; this count is
    /// the fallback signal — when >0 with no open shift, the host can offer
    /// `recover_orphaned_orders()` ("open a shift to recover N stranded sales").
    pub blocked: u32,
    pub online: bool,
    /// `true` when the outbox is parked on a 401 — the host prompts a re-login
    /// to resume syncing (nothing drains until then).
    pub auth_paused: bool,
}

// ── sync center (outbox visibility + retry/discard) ──────────────────────────
#[cfg_attr(feature = "uniffi-ffi", uniffi::exportNone)]
impl MadarCore {
    /// Queued + failed commands for the sync center (acked rows hidden), oldest
    /// first. Always succeeds offline.
    pub fn list_outbox(&self) -> Result<Vec<OutboxItemView>, CoreError> {
        Ok(self
            .store
            .list_active()?
            .into_iter()
            .map(|i| OutboxItemView {
                id: i.id,
                op_type: i.op_type,
                status: i.status,
                attempts: i.attempts,
                last_error: i.last_error,
                event_at: i.event_at,
            })
            .collect())
    }

    /// Discard a single DEAD command (the teller gives up on it). Returns true
    /// if a dead command with that id was removed.
    pub fn discard_outbox_item(&self, id: String) -> Result<bool, CoreError> {
        self.store.discard_dead(&id)
    }

    /// Sync health for the action-bar chip + offline banner (counts + online),
    /// in one cheap local read. Always succeeds offline.
    pub fn sync_status(&self) -> Result<SyncStatusView, CoreError> {
        // The host renders the re-login banner on `auth_paused`, and the flag is
        // trusted on its own now. It is latched from exactly one place — a
        // `CoreError::Unauthenticated`, which `status_to_error` produces ONLY for a
        // 401 carrying our own error envelope. A captive portal or proxy answers
        // with HTML and is classified `Offline` long before it reaches here. So the
        // flag already means "our backend read this bearer and refused it", which
        // is both more direct and more truthful than asking whether `exp` has
        // passed.
        //
        // It used to be gated on expiry as well, and that gate was the bug: a token
        // revoked rather than lapsed — rotated secret, deactivated user, suspended
        // org — is refused by the server while its `exp` is still in the future, so
        // the queue parked, the app looked merely offline, and the teller was never
        // told to sign in. They had to wait out the token.
        //
        // Still gated on being ONLINE: re-auth mints a fresh JWT from the server,
        // so prompting while unreachable is a dead end (the offline banner tells
        // that story instead). The sticky flag keeps the drain parked meanwhile and
        // the prompt resurfaces the moment connectivity is confirmed — the host
        // watches the offline→online edge.
        let online = self.current_session().map(|s| s.online).unwrap_or(false);
        let auth_paused = self.auth_paused.load(std::sync::atomic::Ordering::Relaxed) && online;
        Ok(SyncStatusView {
            pending: self.store.pending_count()?,
            failed: self.store.dead_count()?,
            blocked: self.store.count_orders_blocked_by_dead_dep()?,
            online,
            auth_paused,
        })
    }

    /// FALLBACK recovery for the sync center: re-point every order STRANDED by a
    /// dead `open_shift` onto the CURRENT open shift and sync. The drain already
    /// heals this automatically each pass; this is the manual escape hatch (e.g. the
    /// teller had no shift open when the drain ran, then opens one and taps
    /// "recover N stranded sales"). Returns the number of outbox rows recovered.
    pub async fn recover_orphaned_orders(&self) -> Result<u32, CoreError> {
        let cur = shift::current(&self.store)?.ok_or_else(|| CoreError::Validation {
            field: "shift".into(),
            detail: "open a shift first so the stranded orders can move onto it".into(),
        })?;
        let teller = self.outbox_meta().0.unwrap_or_default();
        let n = self.heal_orphaned_orders(&cur.id, &teller)?;
        let _ = self.drain_outbox().await;
        Ok(n)
    }

    /// Recent diagnostic warnings (newest first) — the Settings → Diagnostics
    /// feed. Captures sync dead-letters, cascade failures, and auth parks.
    pub fn recent_logs(&self) -> Vec<DiagLogView> {
        let g = self.diag.lock().unwrap_or_else(|e| e.into_inner());
        g.iter()
            .rev()
            .map(|e| DiagLogView {
                at: e.at.clone(),
                level: e.level.clone(),
                message: e.message.clone(),
            })
            .collect()
    }

    /// Clear the diagnostics feed.
    pub fn clear_logs(&self) {
        self.diag.lock().unwrap_or_else(|e| e.into_inner()).clear();
    }

    /// Server-vs-device clock skew in MINUTES (server minus device, refreshed by
    /// `refresh_connectivity`). The host shows a banner past a threshold so the
    /// teller fixes the clock before offline work is mis-timestamped.
    pub fn clock_skew_minutes(&self) -> i32 {
        (self
            .clock_skew_secs
            .load(std::sync::atomic::Ordering::Relaxed)
            / 60) as i32
    }

    /// Format a stored RFC3339 timestamp for DISPLAY in the BRANCH's timezone (not
    /// the device's) — the single source of truth so Swift + Kotlin render every
    /// order/shift/cash/receipt time identically (and correctly, regardless of where
    /// the device sits). Mirrors Flutter's `AppTz.local()` + `formatting.dart`.
    pub fn format_time(&self, rfc3339: String, style: timefmt::TimeStyle) -> String {
        timefmt::format(&self.store, &rfc3339, style)
    }

    /// The branch's IANA timezone name (cached at login, or the Cairo fallback) —
    /// for any host that needs the raw zone (e.g. a platform date picker).
    pub fn branch_timezone(&self) -> String {
        timefmt::branch_tz(&self.store).name().to_string()
    }

    /// Live shift stats (sales total + order count) for the action-bar pill,
    /// derived from the orders the host already loaded via `list_shift_orders`
    /// (synced + queued), voided excluded. Pure — no extra network.
    pub fn shift_stats(&self, orders: Vec<orders::OrderSummaryView>) -> orders::ShiftStatsView {
        orders::shift_stats(&orders)
    }
}

// ── Dashboard (management app) surface ───────────────────────────────────────
// Plain, NON-uniffi-exported methods consumed ONLY by the dashboard FRB crate
// (`madar-frb-dashboard`). Kept off the uniffi surface so the POS natives never
// carry them, and off `madar-frb` so the teller binary doesn't either.
impl MadarCore {
    /// Dashboard email/password sign-in (org_admin / super_admin / branch_manager).
    /// Reuses the online-login core WITHOUT the POS device/shift assumptions: no
    /// device-branch pin, no open-shift ownership gate, no offline-auth bundle,
    /// outbox drain, shift refresh, or numbering cache. Online-only — an email
    /// login has no cached offline verifier to fall back to.
    pub async fn dashboard_sign_in(
        &self,
        email: String,
        password: String,
        org_id: Option<String>,
    ) -> Result<session::SessionSnapshot, CoreError> {
        use madar_api::apis::auth_api;
        use std::sync::atomic::Ordering::Relaxed;

        let wire = session::wire_login_request(&session::LoginRequest {
            mode: session::LoginMode::Email,
            name: None,
            pin: None,
            branch_id: None,
            email: Some(email),
            password: Some(password),
            org_id,
        })?;

        // Raw POST — the dashboard carries no POS `X-Madar-Closing-Shifts` header.
        let body = self.api.post_json("/auth/login", &wire).await?;
        let resp: madar_api::models::LoginResponse =
            serde_json::from_str(&body).map_err(|e| CoreError::Internal {
                detail: format!("decode: {e}"),
            })?;

        self.api.set_bearer(Some(resp.token.clone()));
        self.auth_paused.store(false, Relaxed);
        self.borrowed_token.store(false, Relaxed);

        // Org-level session — no branch pin (the scope bar selects the branch).
        let mut snapshot = session::snapshot_from_login(&resp, None);
        // Admin permissions are authoritative — mirror them (best-effort: a perms
        // blip must not void an otherwise good login).
        let permissions = match auth_api::get_my_permissions(&self.api.config()).await {
            Ok(p) => {
                snapshot.permissions_loaded = true;
                session::permissions_from(&p)
            }
            Err(_) => Vec::new(),
        };
        self.persist_and_set(session::SessionState {
            snapshot: snapshot.clone(),
            permissions,
            token: Some(resp.token),
        });
        Ok(snapshot)
    }

    /// The dashboard's current explicit scope override (may be empty / partial).
    pub fn active_scope(&self) -> Option<ActiveScopeView> {
        self.active_scope
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
    }

    /// Set the dashboard's active org/branch scope and persist it. A `None`
    /// field clears that dimension (falls back to the session value on reads).
    pub fn set_active_scope(&self, org_id: Option<String>, branch_id: Option<String>) {
        let scope = ActiveScopeView { org_id, branch_id };
        if let Ok(json) = serde_json::to_string(&scope) {
            let _ = self.store.kv_put(K_DASHBOARD_SCOPE, &json);
        }
        *self.active_scope.write().unwrap_or_else(|e| e.into_inner()) = Some(scope);
    }

    /// Resolve the effective `(org_id, branch_id)` for a dashboard read: the
    /// explicit scope override layered over the session-derived scope. Errors if
    /// signed out, or if neither the override nor the session supplies an org (a
    /// super_admin must pick an org before scoped reads work).
    fn effective_scope(&self) -> Result<(String, Option<String>), CoreError> {
        let (sess_org, sess_branch) = {
            let g = self.session.read().unwrap_or_else(|e| e.into_inner());
            let s = g.as_ref().ok_or_else(|| CoreError::Unauthenticated {
                detail: "not signed in".into(),
            })?;
            (s.snapshot.org_id.clone(), s.snapshot.branch_id.clone())
        };
        let ov = self.active_scope();
        let org = ov
            .as_ref()
            .and_then(|s| s.org_id.clone())
            .or(sess_org)
            .ok_or_else(|| CoreError::Validation {
                field: "org_id".into(),
                detail: "no organization selected".into(),
            })?;
        let branch = ov.and_then(|s| s.branch_id).or(sess_branch);
        Ok((org, branch))
    }

    /// Dashboard home KPI summary for the active scope over `[from, to]`
    /// (RFC3339 strings). A specific branch uses `branch_sales`; "all branches"
    /// (no branch selected) aggregates `org_branch_comparison` — same source the
    /// web dashboard uses. Online-only.
    pub async fn dashboard_summary(
        &self,
        from: Option<String>,
        to: Option<String>,
    ) -> Result<reports::DashboardSummaryView, CoreError> {
        use madar_api::apis::reports_api;
        let (org_id, branch) = self.effective_scope()?;
        let date = |s: Option<String>| {
            s.filter(|x| !x.is_empty())
                .and_then(|x| chrono::DateTime::parse_from_rfc3339(&x).ok())
        };
        let currency = self
            .current_session()
            .map(|s| s.currency_code)
            .unwrap_or_default();
        match branch {
            Some(branch_id) => {
                let params = reports_api::BranchSalesParams {
                    branch_id,
                    from: date(from),
                    to: date(to),
                    limit: Some(10),
                    // The dashboard reports on everything sold; the exclusion
                    // list is a web-only "hide these SKUs" affordance.
                    exclude_items: None,
                };
                let rep = reports_api::branch_sales(&self.api.config(), params)
                    .await
                    .map_err(net::map_api_error)?;
                Ok(reports::from_report(rep, currency, &self.current_locale()))
            }
            None => {
                let params = reports_api::OrgBranchComparisonParams {
                    org_id,
                    from: date(from),
                    to: date(to),
                    limit: None,
                };
                let rep = reports_api::org_branch_comparison(&self.api.config(), params)
                    .await
                    .map_err(net::map_api_error)?;
                Ok(reports::from_comparison(rep, currency))
            }
        }
    }

    /// Revenue trend for the active scope over `[from, to]` at `granularity`
    /// ("hourly"/"daily"/…; defaults to "daily"). All-branches uses the nil-uuid
    /// sentinel, which the timeseries endpoint rolls up. Online-only.
    pub async fn dashboard_timeseries(
        &self,
        from: Option<String>,
        to: Option<String>,
        granularity: Option<String>,
    ) -> Result<Vec<reports::DashboardTimePointView>, CoreError> {
        use madar_api::apis::reports_api;
        let (_, branch) = self.effective_scope()?;
        let branch_id = branch.unwrap_or_else(|| reports::ALL_BRANCHES_ID.to_string());
        let date = |s: Option<String>| {
            s.filter(|x| !x.is_empty())
                .and_then(|x| chrono::DateTime::parse_from_rfc3339(&x).ok())
        };
        let params = reports_api::BranchSalesTimeseriesParams {
            branch_id,
            from: date(from),
            to: date(to),
            granularity: Some(granularity.unwrap_or_else(|| "daily".into())),
        };
        let points = reports_api::branch_sales_timeseries(&self.api.config(), params)
            .await
            .map_err(net::map_api_error)?;
        Ok(reports::timepoints_from(points))
    }
}

#[cfg_attr(feature = "uniffi-ffi", uniffi::export(async_runtime = "tokio"))]
impl MadarCore {
    /// Online login (PIN or email). Mints a bearer, mirrors permissions, caches
    /// the org's offline-auth bundle for later offline unlock, and persists the
    /// session to the host vault. Returns `Offline` if disconnected.
    pub async fn login(
        &self,
        req: session::LoginRequest,
    ) -> Result<session::SessionSnapshot, CoreError> {
        use madar_api::apis::{auth_api, orgs_api};

        let wire = session::wire_login_request(&req)?;
        // Tell the server which open shifts THIS device is already closing (queued
        // close commands). The login guard rejects signing in over ANOTHER teller's
        // open shift, EXCEPT one we acknowledge here — that's a legitimate offline
        // handover whose close lands via /sync/replay moments after this login.
        let ack_closing = self.closing_shift_ids_csv();
        let body = self
            .api
            .post_with_header(
                "/auth/login",
                &wire,
                ("X-Madar-Closing-Shifts", &ack_closing),
            )
            .await?;
        let resp: madar_api::models::LoginResponse =
            serde_json::from_str(&body).map_err(|e| CoreError::Internal {
                detail: format!("decode: {e}"),
            })?;

        // Token is live from here on. A fresh token un-parks a 401-stalled
        // outbox so a re-login resumes syncing immediately.
        self.api.set_bearer(Some(resp.token.clone()));
        self.auth_paused
            .store(false, std::sync::atomic::Ordering::Relaxed);
        // A fresh online login installs THIS teller's own token, so any borrowed
        // (foreign) token state is moot.
        self.borrowed_token
            .store(false, std::sync::atomic::Ordering::Relaxed);

        // PIN login carries the device branch; email login has none.
        let branch_id = req.branch_id.clone();
        let mut snapshot = session::snapshot_from_login(&resp, branch_id);

        // Mirror permissions (best-effort — a perms blip must not void a good login).
        let permissions = match auth_api::get_my_permissions(&self.api.config()).await {
            Ok(p) => {
                snapshot.permissions_loaded = true;
                session::permissions_from(&p)
            }
            Err(_) => Vec::new(),
        };

        // Cache the org's offline-auth bundle so any org teller can unlock offline
        // later (best-effort — failure just means no offline unlock until next login).
        if let Some(org_id) = snapshot.org_id.clone() {
            if let Ok(bundle) = orgs_api::offline_auth_bundle(
                &self.api.config(),
                orgs_api::OfflineAuthBundleParams { id: org_id },
            )
            .await
            {
                session::cache_bundle(&self.store, &bundle, &snapshot);
            }
        }

        let state = session::SessionState {
            snapshot: snapshot.clone(),
            permissions,
            token: Some(resp.token),
        };
        self.persist_and_set(state);

        // Drain BEFORE the host reconciles the shift. On a shared till the device
        // may hold a previous teller's backlog (e.g. the close of an online shift
        // they left offline); flushing it now — attributed to its own teller via
        // /sync/replay — means the just-signed-in teller sees the CURRENT server
        // state, not a stale open shift that's about to be closed. Best-effort.
        let _ = self.drain_outbox().await;
        // Adopt THIS teller's current shift right here (teller-scoped server query)
        // so the device cache + routing are correct the instant login returns — the
        // host needn't win a race with a separate reconcile, and a stale or another
        // teller's open shift can never leave us on the wrong screen. Best-effort.
        let _ = self.refresh_shift().await;
        // Cache the branch timezone + the open shift's order-number base / branch
        // code so an OFFLINE checkout can predict the EXACT number/ref the server
        // will mint (identical post-checkout + reprint receipts). Best-effort.
        let _ = self.cache_numbering_context().await;
        Ok(snapshot)
    }

    /// Cache the branch code + IANA timezone (from `get_branch`) so an OFFLINE
    /// checkout can MINT the exact number/ref the server stores — from first boot,
    /// no synced order needed (the first login is always online, so this always runs
    /// before any offline stretch). Best-effort + online-only.
    async fn cache_numbering_context(&self) {
        let Ok((_, Some(branch_id))) = self.org_branch() else {
            return;
        };
        if let Ok(b) = madar_api::apis::branches_api::get_branch(
            &self.api.config(),
            madar_api::apis::branches_api::GetBranchParams { id: branch_id },
        )
        .await
        {
            let _ = self.store.kv_put(checkout::KEY_BRANCH_TZ, &b.timezone);
            if let Some(code) = b.code.flatten().filter(|s| !s.is_empty()) {
                let _ = self.store.kv_put(checkout::KEY_BRANCH_CODE, &code);
            }
            // Persist the org logo URL the SAME way as the branch code/tz (durable
            // kv from the same get_branch), so it survives restarts/offline and a
            // manual sync re-pulls it. Only overwrite with a non-empty value, so a
            // transient blank can't wipe a good cached logo.
            if let Some(logo) = b.org_logo_url.flatten().filter(|s| !s.is_empty()) {
                let _ = self.store.kv_put(checkout::KEY_ORG_LOGO_URL, &logo);
                // Pull the logo BYTES too, so the (offline-capable) receipt
                // rasterizer can composite it without ever hitting the network.
                // Best-effort: a failure just leaves the last good cached logo
                // (or none) in place — the receipt still prints with the name.
                if let Ok(bytes) = self.api.get_url_bytes(&logo).await {
                    if !bytes.is_empty() {
                        let _ = self.store.blob_put(checkout::KEY_ORG_LOGO_PNG, &bytes);
                    }
                }
            }
        }

        // Seed the open shift's synced order-number base from the server, so the
        // very next ring-up predicts MAX(order_number)+1 (not #1) even online and
        // even right after resuming a shift that already has orders. Best-effort:
        // offline this no-ops and the base advances on ack instead.
        if let Ok(Some(shift)) = shift::current(&self.store) {
            if shift.is_open {
                if let Ok(orders) = self.list_orders_for_shift(shift.id.clone()).await {
                    let max = orders
                        .iter()
                        .filter_map(|o| o.order_number)
                        .max()
                        .unwrap_or(0) as i64;
                    checkout::bump_order_base(&self.store, &shift.id, max);
                }
            }
        }
    }

    /// This device's managed code — the `<DEVICE>` segment of every order_ref.
    /// Auto-assigned (stable random) on first use; the manager renames it in
    /// Settings (e.g. `T1`/`W2`/`K1`) so a branch's devices are distinct.
    pub fn device_code(&self) -> String {
        checkout::device_code_or_default(&self.store)
    }

    /// Set this device's managed code (Settings). Sanitized to short A-Z0-9; an
    /// empty/blank value is ignored (keeps the current code).
    pub fn set_device_code(&self, code: String) {
        let clean: String = code
            .chars()
            .filter(|c| c.is_ascii_alphanumeric())
            .take(6)
            .collect::<String>()
            .to_uppercase();
        if !clean.is_empty() {
            let _ = self.store.kv_put(checkout::KEY_DEVICE_CODE, &clean);
        }
    }

    /// One-call sign-in. The online→offline decision lives HERE, not in the host
    /// UI (the One Rule): try an online `login` first; if the network is down and
    /// this is a teller PIN login, fall back to an offline unlock against the
    /// cached org bundle. Validation / auth errors propagate (no fallback) so a
    /// wrong PIN online doesn't silently try the offline path.
    pub async fn sign_in(
        &self,
        req: session::LoginRequest,
    ) -> Result<session::SessionSnapshot, CoreError> {
        // The device's bound branch is authoritative — read it from the core device
        // config (the host no longer tracks it). PIN login derives the org from it.
        let mut req = req;
        if let Some(b) = device::load(&self.store).branch_id {
            req.branch_id = Some(b);
        }

        // OWNERSHIP GATE (online OR offline): the device may hold an OPEN shift
        // left by a previous teller who signed out without closing it. A shift is
        // its owner's drawer — only they may resume it. Anyone else is rejected
        // (they must close it first), so no teller can ever take over a shift they
        // don't own. Checked up-front, by name, against the device's cached shift
        // (kept across logout). A shift the device already CLOSED locally is not
        // `is_open`, so the normal close-then-switch handover still works.
        if let Some(name) = req.name.as_deref() {
            if let Some(s) = shift::current(&self.store)? {
                if s.is_open && !s.teller_name.eq_ignore_ascii_case(name.trim()) {
                    return Err(CoreError::Forbidden {
                        resource: "shift".into(),
                        action: format!(
                            "This device has an open shift belonging to {}. It must be closed before signing in.",
                            s.teller_name
                        ),
                    });
                }
            }
        }

        // Whether a connectivity failure may fall back to an offline unlock.
        let offline_ok = matches!(req.mode, session::LoginMode::Pin)
            && req.name.is_some()
            && req.pin.is_some()
            && req.branch_id.is_some();
        let offline = |this: &Self| {
            this.unlock_offline(
                req.name.clone().unwrap_or_default(),
                req.pin.clone().unwrap_or_default(),
                req.branch_id.clone().unwrap_or_default(),
            )
        };

        // Hard-bound the online attempt: a black-holed/slow network must never
        // leave the teller on an endless spinner. On timeout → treat as offline.
        let attempt =
            tokio::time::timeout(std::time::Duration::from_secs(7), self.login(req.clone())).await;

        match attempt {
            Ok(Ok(snapshot)) => Ok(snapshot),
            // We never really reached the backend — transport loss OR a captive
            // portal / proxy answering in its place (HTML we can't decode, or a
            // 511/407/408). PIN sign-in falls through to the cached offline
            // verifier. A genuine rejection (401/403/400) propagates so a wrong
            // PIN online is never silently retried offline.
            Ok(Err(e)) if offline_ok && net::is_connectivity_failure(&e) => offline(self),
            Ok(Err(e)) => Err(e),
            // Timed out → treat as offline.
            Err(_elapsed) if offline_ok => offline(self),
            Err(_elapsed) => Err(CoreError::Offline {
                detail: "sign-in timed out — check your connection".into(),
            }),
        }
    }

    /// List the org's active branches — for the device-setup picker. Requires a
    /// live (manager) session; online-only.
    pub async fn list_branches(&self) -> Result<Vec<session::BranchView>, CoreError> {
        use madar_api::apis::branches_api;
        let (org_id, _) = self.org_branch()?;
        let branches = branches_api::list_branches(
            &self.api.config(),
            branches_api::ListBranchesParams { org_id },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(branches
            .into_iter()
            .filter(|b| b.is_active)
            .map(|b| session::BranchView {
                id: b.id.to_string(),
                name: b.name,
                is_active: b.is_active,
                org_logo_url: b.org_logo_url.flatten().filter(|s| !s.is_empty()),
            })
            .collect())
    }

    /// Pull the branch-effective catalog (items + categories + addons + bundles +
    /// payment methods + discounts) and mirror the canonical JSON into the local
    /// store. Online-only; the offline reads (`list_*`) then serve this mirror.
    /// Atomic-ish: every stream is fetched before any is written, so a mid-pull
    /// failure leaves the previous mirror intact.
    pub async fn refresh_catalog(&self) -> Result<(), CoreError> {
        use madar_api::apis::{bundles_api, discounts_api, menu_api, payment_methods_api};
        use madar_api::models::BundleStatus;

        let (org_id, branch_id) = self.org_branch()?;

        // Menu items — full, branch-effective shape via raw GET (the typed
        // `list_menu_items` is `Vec<MenuItem>` and would drop sizes/slots).
        let mut q: Vec<(&str, String)> = vec![("org_id", org_id.clone()), ("full", "true".into())];
        if let Some(b) = &branch_id {
            q.push(("branch_id", b.clone()));
        }
        let menu_items_json = self.api.get_text("/menu-items", &q).await?;

        // Addons — the plain `/addon-items` array (NOT `/catalog`): it's
        // branch-effective AND embeds each addon's ingredients (the recipe
        // preview needs them). Raw GET because the embedded `quantity_used` is a
        // BigDecimal string the generated `AddonItem` (f64) can't decode.
        let mut aq: Vec<(&str, String)> = vec![("org_id", org_id.clone())];
        if let Some(b) = &branch_id {
            aq.push(("branch_id", b.clone()));
        }
        let addons_json = self.api.get_text("/addon-items", &aq).await?;

        let categories = menu_api::list_categories(
            &self.api.config(),
            menu_api::ListCategoriesParams {
                org_id: org_id.clone(),
            },
        )
        .await
        .map_err(net::map_api_error)?;

        let bundles = bundles_api::list_bundles(
            &self.api.config(),
            bundles_api::ListBundlesParams {
                org_id: Some(org_id.clone()),
                status: Some(BundleStatus::Active),
                branch_id: branch_id.clone(),
                search: None,
                page: Some(1),
                per_page: Some(500),
                sort: None,
            },
        )
        .await
        .map_err(net::map_api_error)?;

        // Payment methods + discounts are CHECKOUT-time data — not needed to render
        // or FIRE the menu. A role that can read the menu but not these (a WAITER
        // fires tickets and never tenders, so it has no payment_methods:read grant)
        // must STILL get its catalog. So these are best-effort: a 403/failure leaves
        // them empty rather than aborting the whole catalog and blanking the menu.
        let payment_methods = payment_methods_api::list_payment_methods(&self.api.config())
            .await
            .unwrap_or_default();

        let discounts = discounts_api::list_discounts(
            &self.api.config(),
            discounts_api::ListDiscountsParams {
                org_id: org_id.clone(),
            },
        )
        .await
        .unwrap_or_default();

        // Unified catalog (menu unification, `GET /catalog/sync`): the new
        // modifier model with branch-effective prices, revision-gated via
        // `since`. BEST-EFFORT by design — an old backend (404), a
        // not-yet-backfilled org, or a branchless session just leaves the key
        // untouched and every reader falls back to the legacy projection.
        let unified_json: Option<String> = match &branch_id {
            Some(b) => {
                let mut uq: Vec<(&str, String)> = vec![("branch_id", b.clone())];
                if let Some(rev) = menu::unified_revision(&self.store) {
                    uq.push(("since", rev.to_string()));
                }
                match self.api.get_text("/catalog/sync", &uq).await {
                    // changed:false ⇒ device is current; KEEP the existing mirror.
                    Ok(body) if menu::unified_unchanged(&body) => None,
                    Ok(body) => Some(body),
                    Err(_) => None,
                }
            }
            None => None,
        };

        // All streams fetched OK → commit the mirror.
        self.store.kv_put(menu::K_MENU_ITEMS, &menu_items_json)?;
        self.store
            .kv_put(menu::K_CATEGORIES, &serde_json::to_string(&categories)?)?;
        self.store.kv_put(menu::K_ADDONS, &addons_json)?;
        if let Some(unified) = unified_json {
            self.store.kv_put(menu::K_UNIFIED, &unified)?;
        }
        self.store
            .kv_put(menu::K_BUNDLES, &serde_json::to_string(&bundles.data)?)?;
        self.store.kv_put(
            menu::K_PAYMENT_METHODS,
            &serde_json::to_string(&payment_methods)?,
        )?;
        self.store
            .kv_put(menu::K_DISCOUNTS, &serde_json::to_string(&discounts)?)?;

        // A catalog sync also re-pulls the branch context (code, timezone, ORG LOGO
        // URL) + re-seeds the order-number base — the same get_branch persisted the
        // same durable kv way. So the manual "sync data" button refreshes a changed
        // logo/branch too, not just the menu. Best-effort: a branch-fetch hiccup
        // never fails the catalog commit above.
        let _ = self.cache_numbering_context().await;

        // Floor layout + held orders + transfer waitlist — best-effort, like
        // payment methods: a 403/404 (older backend, no grant) leaves the
        // mirrors untouched and the feature simply stays hidden.
        self.refresh_floor_and_held().await;

        // Image phase — AFTER the data commit, best-effort, time-budgeted.
        // Downloads whatever the fresh catalog references that isn't on disk
        // yet and evicts orphans; a flaky CDN can never fail the catalog.
        self.sync_catalog_images().await;
        // Step animations, same discipline: only what THIS menu references,
        // orphans evicted, failures swallowed. Nothing outside a manual sync
        // ever downloads one.
        self.sync_step_animations().await;
        // The kv mirrors (and possibly the on-disk images) just changed —
        // drop the parsed snapshot so the next read re-projects.
        self.invalidate_catalog_cache();
        Ok(())
    }

    /// Best-effort pull of the floor layout + held orders + transfer waitlist
    /// into their kv mirrors. Never fails the caller: a signed-out session, an
    /// older backend (404), or a missing grant (403) just leaves the mirrors as
    /// they are. Entries with a STILL-PENDING local op keep their optimistic
    /// state (the op is the truth until it drains).
    async fn refresh_floor_and_held(&self) {
        let Ok(branch) = self.session_branch_id() else {
            return;
        };
        let q = [("branch_id", branch.clone())];
        if let (Ok(sections), Ok(tables)) = (
            self.api.get_text("/floor/sections", &q).await,
            self.api.get_text("/floor/tables", &q).await,
        ) {
            if held::save_floor(&self.store, &sections, &tables).is_ok() {
                // A queued seat / no-show keeps its optimistic state on the
                // canvas until it drains.
                self.reapply_pending_booking_ops();
                // Re-apply a QUEUED local clear on top of the fresh pull, so a
                // table the teller just bussed does not flicker back to dirty
                // between this pull and its drain.
                //
                // Queued HOLDS and RELEASES ride the same rail, in queue order:
                // a table this till just parked an order on must not read free
                // between the park and its drain, or the canvas invites the
                // teller to seat somebody on top of their own draft.
                if let Ok(items) = self.store.pending() {
                    for i in items.iter().filter(|i| {
                        matches!(
                            i.op_type.as_str(),
                            "clear_table" | "hold_table" | "release_table"
                        )
                    }) {
                        let Ok(cmd) = serde_json::from_str::<held::TableStateCommand>(&i.payload)
                        else {
                            continue;
                        };
                        let status = match i.op_type.as_str() {
                            "hold_table" => "seated",
                            "release_table" => {
                                // The party ate: the table is waiting for a
                                // cloth, not free.
                                if cmd.request.get("bus").and_then(|b| b.as_bool()) == Some(true) {
                                    "dirty"
                                } else {
                                    "free"
                                }
                            }
                            _ => "free",
                        };
                        let _ = held::set_table_state_local(
                            &self.store,
                            &cmd.table_id,
                            Some(status),
                            None,
                            false,
                        );
                    }
                }
            }
        }

        // Held orders are NOT pulled. A parked order is this terminal's own
        // draft -- it has no server copy to reconcile with, and asking for one
        // was the whole reason parking needed a network at all.
        //
        // Transfers still ARE pulled, so they still need the pending-op guard.
        // It must not be empty here: a FULL pull rebuilds the mirror from the
        // server list alone, so a transfer this device created but has not yet
        // drained (the server has never heard of it) would be dropped outright
        // and disappear from the waitlist while its op sits in the outbox.
        let protect = self.pending_held_ids();
        let tcursor = self.store.kv_get(held::K_TRANSFERS_CURSOR).ok().flatten();
        let mut tq: Vec<(&str, String)> = vec![("branch_id", branch)];
        if let Some(c) = &tcursor {
            tq.push(("since", c.clone()));
        }
        if let Ok(body) = self.api.get_text("/floor/transfers", &tq).await {
            let _ = held::merge_transfers(&self.store, &body, tcursor.is_none(), &protect);
        }
    }

    /// Re-pull the floor layout + held orders + transfer waitlist NOW. The
    /// host calls this when it opens a floor surface or when a `floor.*`
    /// realtime event lands (a manager re-arranged the room in the dashboard,
    /// another till seated a party). Best-effort: offline leaves the mirrors
    /// untouched and the canvas keeps rendering what it has.
    pub async fn refresh_floor(&self) -> Result<(), CoreError> {
        self.refresh_floor_and_held().await;
        // The arrivals list rides along: a `booking.*` event triggers the
        // same floor refresh the host already does.
        let _ = self.refresh_arrivals().await;
        Ok(())
    }

    /// Re-apply queued booking ops (seat / no-show) on top of a fresh pull, so
    /// the arrivals list and the canvas keep the teller's answer until the
    /// cloud confirms it.
    fn reapply_pending_booking_ops(&self) {
        let Ok(items) = self.store.pending() else {
            return;
        };
        for i in &items {
            let (id, status) = match i.op_type.as_str() {
                "seat_booking" => {
                    match serde_json::from_str::<bookings::SeatBookingCommand>(&i.payload) {
                        Ok(c) => (c.booking_id, "seated"),
                        Err(_) => continue,
                    }
                }
                "no_show_booking" => {
                    match serde_json::from_str::<bookings::NoShowBookingCommand>(&i.payload) {
                        Ok(c) => (c.booking_id, "no_show"),
                        Err(_) => continue,
                    }
                }
                _ => continue,
            };
            let _ = bookings::set_status_local(&self.store, &id, status);
            let _ = held::set_booking_status_local(&self.store, &id, status);
        }
    }

    /// Transfer ids with a queued-but-unacked local op — their mirror entries
    /// must not be clobbered by a pull until the op lands.
    ///
    /// Held orders used to be half of this guard. They are not any more: a
    /// parked draft is device-local and queues nothing, so there is no in-flight
    /// window for a pull to race. Only the transfer wishes, which are real
    /// server state, still need protecting.
    fn pending_held_ids(&self) -> Vec<String> {
        let Ok(items) = self.store.pending() else {
            return Vec::new();
        };
        items
            .iter()
            .filter_map(|i| match i.op_type.as_str() {
                "create_table_transfer" | "cancel_table_transfer" | "fulfill_table_transfer" => {
                    serde_json::from_str::<held::TransferOpCommand>(&i.payload)
                        .ok()
                        .map(|c| c.transfer_id)
                }
                _ => None,
            })
            .collect()
    }

    /// The org's logo URL for the current branch, from the durable kv mirror
    /// (`cache_numbering_context`/`refresh_catalog` persist it from `get_branch`).
    /// `None` until the first online branch fetch. The host reads this as the
    /// source of truth for the receipt logo, so it survives restarts + offline and
    /// refreshes on a manual data sync.
    pub fn org_logo_url(&self) -> Option<String> {
        self.store
            .kv_get(checkout::KEY_ORG_LOGO_URL)
            .ok()
            .flatten()
            .filter(|s| !s.is_empty())
    }

    /// Local file path of the cached org logo (downloaded by the image phase
    /// of `refresh_catalog`) — `None` until the first successful sync. The
    /// host renders the receipt-preview logo from this, fully offline.
    pub fn org_logo_local_path(&self) -> Option<String> {
        self.org_logo_url()
            .and_then(|u| self.images.path_if_cached(&u))
    }

    /// Open a shift. Writes an optimistic local shift + queues an idempotent
    /// open-shift command (client UUID = shift PK), then drains best-effort. The
    /// shift is usable immediately, online or offline. Returns the current shift.
    pub async fn open_shift(
        &self,
        opening_cash_minor: i64,
        edit_reason: Option<String>,
    ) -> Result<shift::ShiftView, CoreError> {
        // SEQUENTIAL-ONLY: refuse to open a second shift while one is still open
        // on this device. Without this guard a second open silently overwrote the
        // cached shift (orphaning the first server-side and losing its close) —
        // the "shift open-or-not isn't robust" bug. The teller must close the
        // current shift first; the close may still be syncing, that's fine.
        if self.device_has_open_shift()? {
            return Err(CoreError::Validation {
                field: "shift".into(),
                detail:
                    "A shift is already open on this device. Close it before opening a new one."
                        .into(),
            });
        }
        let (branch_id, teller_id, teller_name) = {
            let g = self.session.read().unwrap_or_else(|e| e.into_inner());
            let s = g.as_ref().ok_or_else(|| CoreError::Unauthenticated {
                detail: "not signed in".into(),
            })?;
            let branch = s
                .snapshot
                .branch_id
                .clone()
                .ok_or_else(|| CoreError::Validation {
                    field: "branch_id".into(),
                    detail: "session has no branch".into(),
                })?;
            (
                branch,
                s.snapshot.user_id.clone(),
                s.snapshot.display_name.clone(),
            )
        };
        let branch_uuid = uuid::Uuid::parse_str(&branch_id).map_err(|_| CoreError::Validation {
            field: "branch_id".into(),
            detail: "bad uuid".into(),
        })?;
        let teller_uuid = uuid::Uuid::parse_str(&teller_id).map_err(|_| CoreError::Validation {
            field: "teller_id".into(),
            detail: "bad uuid".into(),
        })?;
        // The device's bound till (drawer) comes from the core device config, NOT a
        // host param. `None` lets the backend pick the branch's default till.
        let till_uuid = match device::load(&self.store).till_id.filter(|s| !s.is_empty()) {
            Some(s) => Some(
                uuid::Uuid::parse_str(&s).map_err(|_| CoreError::Validation {
                    field: "till_id".into(),
                    detail: "bad till id".into(),
                })?,
            ),
            None => None,
        };
        let shift_id = uuid::Uuid::new_v4();
        let opened_at = self.corrected_now().fixed_offset();
        let opening_cash = cash_i32(opening_cash_minor, "opening_cash")?;
        // A non-empty discrepancy reason ⇒ the teller deviated from the carried-
        // over closing. The server re-derives this authoritatively; we mirror it
        // locally for display and pass the reason through.
        let edit_reason = edit_reason.filter(|r| !r.trim().is_empty());
        let was_edited = edit_reason.is_some();

        // Optimistic local shift — visible immediately on every read.
        let local = madar_api::models::Shift {
            branch_id: branch_uuid,
            id: shift_id,
            opened_at,
            opening_cash,
            opening_cash_was_edited: was_edited,
            status: "open".into(),
            teller_id: teller_uuid,
            teller_name,
            till_id: till_uuid.map(Some),
            ..Default::default()
        };
        shift::save(&self.store, &local)?;

        // Queue the durable command (idempotent on the client shift UUID).
        let request = madar_api::models::OpenShiftRequest {
            id: Some(Some(shift_id)),
            opened_at: Some(Some(opened_at)),
            opening_cash,
            edit_reason: edit_reason.map(Some),
            till_id: till_uuid.map(Some),
            ..Default::default()
        };
        let cmd = shift::OpenShiftCommand { branch_id, request };
        let (user_id, clock_offset_ms) = self.outbox_meta();
        // Sequential handover: if a prior shift's close is still queued, this open
        // DEPENDS on it. The branch must be confirmed free (the close fully drained)
        // before the open replays — otherwise the open races the still-open prior
        // shift and 409s ("a shift is already open for this branch"), dead-letters,
        // cascades its orders, and clears the local shift back to the open screen.
        // None when no close is queued (the prior shift closed online → branch free).
        let depends_on_seq = self.store.latest_unsynced_close_seq()?;
        self.store.enqueue(&store::NewOutboxOp {
            id: shift_id.to_string(),
            op_type: "open_shift".into(),
            idempotency_key: shift_id.to_string(),
            payload: serde_json::to_string(&cmd)?,
            event_at: opened_at.to_rfc3339(),
            depends_on_seq,
            user_id,
            clock_offset_ms,
            shift_id: Some(shift_id.to_string()),
        })?;

        // Best-effort: send now if online (offline just leaves it queued).
        let _ = self.drain_outbox().await;

        // Advertise this till's now-open shift to the LAN gate (if the relay is up).
        self.lan_sync_open_shift();

        shift::current(&self.store)?.ok_or_else(|| CoreError::Internal {
            detail: "shift not persisted".into(),
        })
    }

    /// Close the current open shift: count the closing drawer cash + an optional
    /// note. Marks the shift closed locally (routing flips to open-shift now) and
    /// queues an idempotent `close_shift` command; works offline. Errors if there
    /// is no open shift.
    pub async fn close_shift(
        &self,
        closing_cash_minor: i64,
        cash_note: Option<String>,
    ) -> Result<(), CoreError> {
        let shift = shift::current(&self.store)?
            .filter(|s| s.is_open)
            .ok_or_else(|| CoreError::Validation {
                field: "shift".into(),
                detail: "no open shift".into(),
            })?;

        let closed_at = self.corrected_now().fixed_offset();
        let mut request = madar_api::models::CloseShiftRequest::new(cash_i32(
            closing_cash_minor,
            "closing_cash",
        )?);
        request.cash_note = Some(cash_note);
        request.closed_at = Some(Some(closed_at));

        // Optimistic: mark closed locally so routing flips to open-shift now,
        // and drop the in-progress cart (a closed shift sells nothing).
        shift::close_local(&self.store)?;
        cart::clear(&self.store)?;
        // Carry the declared closing into the NEXT shift's suggested opening, so
        // cash continuity holds even before this close syncs.
        shift::cache_suggested_opening_cash(&self.store, closing_cash_minor)?;

        // Queue the durable command. Keyed by `{shift_id}:close` so it doesn't
        // collide with the still-pending open_shift command (id == shift PK).
        let cmd = shift::CloseShiftCommand {
            shift_id: shift.id.clone(),
            request,
        };
        let (user_id, clock_offset_ms) = self.outbox_meta();
        self.store.enqueue(&store::NewOutboxOp {
            id: format!("{}:close", shift.id),
            op_type: "close_shift".into(),
            idempotency_key: format!("{}:close", shift.id),
            payload: serde_json::to_string(&cmd)?,
            event_at: closed_at.to_rfc3339(),
            // Gate behind the shift's open (if still queued); the close-last
            // drain rule then also waits for every order/cash of this shift.
            depends_on_seq: self.store.live_seq_of(&shift.id)?,
            user_id,
            clock_offset_ms,
            shift_id: Some(shift.id.clone()),
        })?;

        // Best-effort: the FIFO drain runs the open + orders before the close,
        // so the close never races ahead of them.
        let _ = self.drain_outbox().await;

        // Stop advertising an open shift to the LAN gate (this till just closed).
        self.lan_sync_open_shift();
        Ok(())
    }

    /// The current shift's report — drives the close-shift system-cash +
    /// discrepancy. Online: the server report plus still-queued cash sales.
    /// Offline / on error: opening cash + queued cash (`from_server = false`).
    pub async fn shift_report(&self) -> Result<shift::ShiftReportView, CoreError> {
        use madar_api::apis::shifts_api;
        let shift = shift::current(&self.store)?.ok_or_else(|| CoreError::Validation {
            field: "shift".into(),
            detail: "no shift".into(),
        })?;
        // Scope to THIS shift — a prior shift's still-undrained cash sales sit in the
        // outbox too, and counting them would overstate this drawer's expected cash.
        let queued_cash = checkout::queued_cash_total_for(&self.store, &shift.id)?;
        let online = self.current_session().map(|s| s.online).unwrap_or(false);
        if online {
            let res = shifts_api::get_shift_report(
                &self.api.config(),
                shifts_api::GetShiftReportParams {
                    shift_id: shift.id.clone(),
                },
            )
            .await;
            if let Ok(report) = res {
                // Remember it: a later close that happens offline needs to know
                // what this shift actually took, not just what we have queued.
                // Same key the past-shift report path uses.
                cache_views(
                    &self.store,
                    &shift::report_cache_key(&shift.id),
                    std::slice::from_ref(&report),
                );
                return Ok(shift::report_view(&report, queued_cash));
            }
        }
        // Offline: reconstruct the drawer block from the still-queued movements.
        let teller = self
            .current_session()
            .map(|s| s.display_name)
            .unwrap_or_default();
        let movements: Vec<shift::ShiftReportCashLine> = self
            .store
            .list_active_of_types(&["cash_movement"])?
            .into_iter()
            .filter(|i| i.shift_id.as_deref() == Some(shift.id.as_str()))
            .filter_map(|i| {
                serde_json::from_str::<shift::CashMovementCommand>(&i.payload)
                    .ok()
                    .map(|cmd| shift::ShiftReportCashLine {
                        amount_minor: cmd.request.amount as i64,
                        note: cmd.request.note,
                        moved_by_name: teller.clone(),
                        created_at: i.event_at.clone(),
                    })
            })
            .collect();
        // Prefer the last server report we cached for this shift. Rebuilding from
        // the outbox alone only ever sees work THIS device has yet to drain, so a
        // teller who joined a shift that already had sales — or whose sales have
        // since drained — would otherwise count a full drawer against an expected
        // cash of just the opening float.
        if let Some(report) = cached_views::<madar_api::models::ShiftReportResponse>(
            &self.store,
            &shift::report_cache_key(&shift.id),
        )
        .into_iter()
        .next()
        {
            return Ok(shift::cached_report_view(&report, queued_cash, movements));
        }
        Ok(shift::offline_report_view(
            shift.opening_cash_minor,
            queued_cash,
            movements,
            shift.teller_name.clone(),
            shift.opened_at.clone(),
            chrono::Utc::now().to_rfc3339(),
        ))
    }

    /// Record a cash-drawer movement against the open shift — pay-IN when
    /// `amount_minor > 0`, pay-OUT when `< 0`. OFFLINE-FIRST: queued through the
    /// durable outbox (gated behind the shift's open) and idempotent on a minted
    /// `client_ref`, so a replay after a lost response never double-applies cash.
    pub async fn record_cash_movement(
        &self,
        amount_minor: i64,
        note: String,
    ) -> Result<shift::CashMovementView, CoreError> {
        let shift = shift::current(&self.store)?
            .filter(|s| s.is_open)
            .ok_or_else(|| CoreError::Validation {
                field: "shift".into(),
                detail: "no open shift".into(),
            })?;

        // Mirror the backend's validation up-front: a zero amount or empty note 400s
        // there. Without this the drawer "moves" optimistically and the op then dead-
        // letters, leaving the local view out of sync with a movement the server never
        // recorded. Reject before queueing so the host shows the error immediately.
        let note = note.trim().to_string();
        if amount_minor == 0 {
            return Err(CoreError::Validation {
                field: "amount".into(),
                detail: "amount cannot be zero".into(),
            });
        }
        if note.is_empty() {
            return Err(CoreError::Validation {
                field: "note".into(),
                detail: "a note is required for cash movements".into(),
            });
        }

        // The client_ref IS the outbox id — stable across replays so the backend
        // dedups on its `client_ref` unique index.
        let client_ref = uuid::Uuid::new_v4();
        let created_at = self.corrected_now().fixed_offset();
        let mut request = madar_api::models::CashMovementRequest::new(
            cash_i32(amount_minor, "amount")?,
            note.clone(),
        );
        request.client_ref = Some(Some(client_ref));
        request.created_at = Some(Some(created_at));
        let cmd = shift::CashMovementCommand {
            shift_id: shift.id.clone(),
            request,
        };

        let (user_id, clock_offset_ms) = self.outbox_meta();
        self.store.enqueue(&store::NewOutboxOp {
            id: client_ref.to_string(),
            op_type: "cash_movement".into(),
            idempotency_key: client_ref.to_string(),
            payload: serde_json::to_string(&cmd)?,
            event_at: created_at.to_rfc3339(),
            depends_on_seq: self.store.live_seq_of(&shift.id)?,
            user_id,
            clock_offset_ms,
            shift_id: Some(shift.id.clone()),
        })?;
        // Best-effort send now; offline just leaves it queued.
        let _ = self.drain_outbox().await;

        // Optimistic view (the drawer moved regardless of sync state).
        let teller = self
            .current_session()
            .map(|s| s.display_name)
            .unwrap_or_default();
        Ok(shift::CashMovementView {
            id: client_ref.to_string(),
            amount_minor,
            note,
            moved_by_name: teller,
            created_at: created_at.to_rfc3339(),
        })
    }

    /// Cash movements for the open shift — server rows merged with still-queued
    /// (offline) ones, so the drawer view is complete with or without a connection.
    pub async fn list_cash_movements(&self) -> Result<Vec<shift::CashMovementView>, CoreError> {
        use madar_api::apis::shifts_api;
        let shift = shift::current(&self.store)?.ok_or_else(|| CoreError::Validation {
            field: "shift".into(),
            detail: "no shift".into(),
        })?;

        // Queued (not-yet-synced) movements for this shift, parsed from the outbox.
        let teller = self
            .current_session()
            .map(|s| s.display_name)
            .unwrap_or_default();
        let queued: Vec<shift::CashMovementView> = self
            .store
            .list_active()?
            .into_iter()
            .filter(|i| {
                i.op_type == "cash_movement" && i.shift_id.as_deref() == Some(shift.id.as_str())
            })
            .filter_map(|i| {
                serde_json::from_str::<shift::CashMovementCommand>(&i.payload)
                    .ok()
                    .map(|cmd| shift::CashMovementView {
                        id: i.id.clone(),
                        amount_minor: cmd.request.amount as i64,
                        note: cmd.request.note,
                        moved_by_name: teller.clone(),
                        created_at: i.event_at.clone(),
                    })
            })
            .collect();

        // Server rows: live when online (cached write-through for offline), else the
        // last-synced snapshot. So the drawer shows ALL movements offline — both the
        // ones synced before the outage and the ones rung during it — not just queued.
        let key = format!("cache:cash:{}", shift.id);
        let server: Vec<shift::CashMovementView> =
            if self.current_session().map(|s| s.online).unwrap_or(false) {
                match shifts_api::list_cash_movements(
                    &self.api.config(),
                    shifts_api::ListCashMovementsParams {
                        shift_id: shift.id.clone(),
                    },
                )
                .await
                {
                    Ok(list) => {
                        let views: Vec<_> = list.iter().map(shift::cash_movement_view).collect();
                        cache_views(&self.store, &key, &views);
                        views
                    }
                    Err(_) => cached_views(&self.store, &key),
                }
            } else {
                cached_views(&self.store, &key)
            };
        // Server first (chronological), then the still-queued tail, deduped on the
        // client_ref-based view id so a movement that synced between enqueue and this
        // read isn't doubled in the drawer total.
        Ok(shift::merge_cash_for_view(server, queued))
    }

    /// Past shifts for this branch, newest first (the history screen). Live when
    /// online (cached write-through), else the last-synced snapshot — so the past-
    /// shifts table still populates offline instead of erroring to an empty screen.
    pub async fn list_shifts(&self) -> Result<Vec<shift::ShiftSummaryView>, CoreError> {
        use madar_api::apis::shifts_api;
        let (_, branch_id) = self.org_branch()?;
        let branch = branch_id.unwrap_or_else(|| "00000000-0000-0000-0000-000000000000".into());
        const KEY: &str = "cache:shifts";
        let mut views: Vec<shift::ShiftSummaryView> =
            if self.current_session().map(|s| s.online).unwrap_or(false) {
                match shifts_api::list_shifts(
                    &self.api.config(),
                    shifts_api::ListShiftsParams {
                        branch_id: branch,
                        page: None,
                        per_page: None,
                    },
                )
                .await
                {
                    Ok(paginated) => {
                        let v: Vec<_> = paginated
                            .data
                            .iter()
                            .map(shift::shift_summary_view)
                            .collect();
                        // Cache the SERVER truth (pre-overlay); the offline-close
                        // overlay is re-applied on every read from the queue below.
                        cache_views(&self.store, KEY, &v);
                        v
                    }
                    Err(_) => cached_views(&self.store, KEY),
                }
            } else {
                cached_views(&self.store, KEY)
            };

        // Overlay shifts CLOSED OFFLINE: the server snapshot still has them open
        // (the close is only queued), so without this a shift closed offline shows
        // as still-active in the list. Drops off automatically once the close syncs
        // (the queued op clears) and the server list reflects the closed shift.
        let overlay = shift::queued_close_overlay(&self.store);
        if !overlay.is_empty() {
            for v in views.iter_mut() {
                if let Some((closed_at, declared)) = overlay.get(&v.id) {
                    v.is_open = false;
                    v.status = "closed".into();
                    if v.closed_at.is_none() {
                        v.closed_at = closed_at.clone();
                    }
                    if v.closing_declared_minor.is_none() {
                        v.closing_declared_minor = Some(*declared);
                    }
                }
            }
        }

        // Add shifts opened OFFLINE that aren't on the server yet (the normal
        // offline workflow: open AND close a whole shift with no connection). They
        // live only in the outbox until they sync, so without this they'd be missing
        // from past shifts entirely. Dedup by id against the server list.
        let server_ids: std::collections::HashSet<String> =
            views.iter().map(|v| v.id.clone()).collect();
        for local in shift::local_shifts(&self.store) {
            if !server_ids.contains(&local.id) {
                views.push(local);
            }
        }
        // Newest-first by opened_at (the merge of server + local needs a re-sort).
        views.sort_by(|a, b| b.opened_at.cmp(&a.opened_at));
        Ok(views)
    }

    /// Place the current cart as an order: price it (client-authoritative),
    /// queue an idempotent `create_order` command, clear the cart, and try to
    /// send now. Works offline — the order stays queued and `queued_offline` is
    /// `true` on the receipt until it syncs. Errors if there's no open shift,
    /// the cart is empty, or the payment method is unknown.
    pub async fn checkout(
        &self,
        input: checkout::CheckoutInput,
    ) -> Result<checkout::ReceiptView, CoreError> {
        let (branch_id, tax_policy, teller_name) = {
            let g = self.session.read().unwrap_or_else(|e| e.into_inner());
            let s = g.as_ref().ok_or_else(|| CoreError::Unauthenticated {
                detail: "not signed in".into(),
            })?;
            let branch = s
                .snapshot
                .branch_id
                .clone()
                .ok_or_else(|| CoreError::Validation {
                    field: "branch_id".into(),
                    detail: "session has no branch".into(),
                })?;
            (
                branch,
                s.snapshot.tax_policy(),
                s.snapshot.display_name.clone(),
            )
        };
        let shift = shift::current(&self.store)?
            .filter(|s| s.is_open)
            .ok_or_else(|| CoreError::Validation {
                field: "shift".into(),
                detail: "no open shift".into(),
            })?;

        let now = self.corrected_now().to_rfc3339();
        let prepared = checkout::prepare(
            &self.store,
            &self.current_locale(),
            &branch_id,
            &shift.id,
            &input,
            &tax_policy,
            now,
        )?;

        // Queue the durable command. Idempotent on the client order UUID (both
        // the outbox `id` and the in-body `idempotency_key`), gated behind the
        // shift's open if that hasn't synced yet.
        let (user_id, clock_offset_ms) = self.outbox_meta();
        self.store.enqueue(&store::NewOutboxOp {
            id: prepared.order_id.to_string(),
            op_type: "create_order".into(),
            idempotency_key: prepared.order_id.to_string(),
            payload: serde_json::to_string(&prepared.command)?,
            event_at: prepared.event_at.clone(),
            depends_on_seq: self.store.live_seq_of(&shift.id)?,
            user_id,
            clock_offset_ms,
            shift_id: Some(shift.id.clone()),
        })?;
        // The sale is committed locally; the cart is now spent.
        cart::clear(&self.store)?;

        // Best-effort: send now if online (offline leaves it queued).
        let _ = self.drain_outbox().await;

        // If the order is no longer pending, the drain sent it.
        let order_id = prepared.order_id.to_string();
        let still_pending = self.store.pending()?.iter().any(|i| i.id == order_id);
        let mut receipt = prepared.receipt;
        receipt.queued_offline = still_pending;
        receipt.teller_name = Some(teller_name).filter(|s| !s.trim().is_empty());
        Ok(receipt)
    }

    /// Force a sync now — drains the outbox. Cancellable/idempotent.
    pub async fn sync_now(&self) -> Result<(), CoreError> {
        // An explicit push should recover a SPURIOUSLY parked queue — but only on
        // proof that the bearer is good, never on the assumption that an unexpired
        // one must be. A token the backend refuses stays parked, and the banner
        // now says so instead of waiting for it to lapse.
        self.unpark_if_token_accepted().await;
        // Adopt any new tax policy BEFORE pricing anything else: a till that
        // has been running since before a rate change would otherwise keep
        // building bills the server will refuse.
        self.refresh_tax_policy().await;
        // An explicit sync clears the offline (no-count) backoff so a backlog built
        // during an outage flushes NOW, not after the ~15s network-retry window.
        let _ = self.store.clear_network_backoff();
        let drained = self.drain_outbox().await;
        // Pull AFTER push so the floor/held mirrors reflect what just acked
        // (and pick up other tills' parks/moves). Best-effort.
        self.refresh_floor_and_held().await;
        drained
    }

    /// Re-read the branch's tax policy from the backend and adopt it.
    ///
    /// This is what makes a rate changed in the dashboard reach a till. The
    /// policy used to be cached once, at online login, and never looked at
    /// again — so a device that stayed signed in for a month priced every bill
    /// under whatever the rate was when someone last signed in. That was
    /// merely wrong before. It is now an OUTAGE: the server refuses an order
    /// whose total disagrees with its own, so a till holding a stale rate
    /// cannot complete a sale until it signs in again.
    ///
    /// Best-effort and silent. Offline, the cached policy is still the best
    /// answer available, and failing a sync over it would be worse than
    /// pricing under yesterday's rate for one more shift.
    async fn refresh_tax_policy(&self) {
        use madar_api::apis::auth_api;
        // Only with a live bearer: an offline-unlocked session has no token,
        // and there is nothing to ask.
        let has_token = {
            let g = self.session.read().unwrap_or_else(|e| e.into_inner());
            g.as_ref().map(|s| s.token.is_some()).unwrap_or(false)
        };
        if !has_token {
            return;
        }
        let Ok(me) = auth_api::me(&self.api.config()).await else {
            return;
        };

        let blob = {
            let mut g = self.session.write().unwrap_or_else(|e| e.into_inner());
            match g.as_mut() {
                Some(s) => {
                    let p = &me.tax_policy;
                    let requires_table = me.require_table_for_orders.unwrap_or(false);
                    let changed = s.snapshot.tax_rate != p.tax_rate
                        || s.snapshot.tax_inclusive != p.tax_inclusive
                        || s.snapshot.service_charge_rate != p.service_charge_rate
                        || s.snapshot.service_charge_taxable != p.service_charge_taxable
                        || s.snapshot.require_table_for_orders != requires_table;
                    if !changed {
                        None
                    } else {
                        // Adopting a policy the shop changed since sign-in.
                        s.snapshot.tax_rate = p.tax_rate;
                        s.snapshot.tax_inclusive = p.tax_inclusive;
                        s.snapshot.service_charge_rate = p.service_charge_rate;
                        s.snapshot.service_charge_taxable = p.service_charge_taxable;
                        // Switching this on changes the till's HOME SCREEN, so
                        // it has to arrive the same way a rate does — on sync,
                        // not on the next sign-in.
                        s.snapshot.require_table_for_orders = requires_table;
                        Some((s.to_blob(), s.snapshot.clone()))
                    }
                }
                None => None,
            }
        };

        if let Some((blob, snapshot)) = blob {
            let _ = self.store.blob_put(session::K_SESSION_BLOB, &blob);
            // And the offline cache, so the next unlock without a network
            // starts from the new policy rather than the one it was born with.
            session::cache_org_config(&self.store, &snapshot);
        }
    }

    /// Requeue every dead command (clearing its error) and try to send now.
    /// Best-effort — offline just leaves them pending again.
    pub async fn retry_outbox(&self) -> Result<(), CoreError> {
        self.unpark_if_token_accepted().await;
        self.store.requeue_dead()?;
        self.drain_outbox().await
    }

    /// The connectivity heartbeat: ping the backend, update the live `online`
    /// flag + clock skew, and drain the outbox on success. The host calls this on
    /// foreground + on a timer so the offline/clock-skew banners and the sync
    /// chip reflect reality without waiting for the next deliberate action.
    /// Returns the new online state.
    /// If the live session is authenticated (holds a token) but its permissions
    /// never loaded — a blip during sign-in left `permissions_loaded == false`, so
    /// `has_permission` stays optimistically OPEN for the session lifetime (audit
    /// #26) — re-fetch them now and lock the gate to the real grants. A token-LESS
    /// offline-unlock can't fetch (no bearer); its security is enforced server-side
    /// at `/sync/replay` instead (audit #12).
    async fn refresh_permissions_if_needed(&self) {
        use madar_api::apis::auth_api;
        let needs = {
            let g = self.session.read().unwrap_or_else(|e| e.into_inner());
            g.as_ref()
                .map(|s| s.token.is_some() && !s.snapshot.permissions_loaded)
                .unwrap_or(false)
        };
        if !needs {
            return;
        }
        let Ok(p) = auth_api::get_my_permissions(&self.api.config()).await else {
            return;
        };
        let perms = session::permissions_from(&p);
        // Update under the write lock, capture the blob, then RELEASE before
        // the store write (keep lock scopes minimal; the store has its own).
        let blob = {
            let mut g = self.session.write().unwrap_or_else(|e| e.into_inner());
            match g.as_mut() {
                Some(s) if s.token.is_some() && !s.snapshot.permissions_loaded => {
                    s.permissions = perms;
                    s.snapshot.permissions_loaded = true;
                    Some(s.to_blob())
                }
                _ => None,
            }
        };
        if let Some(blob) = blob {
            let _ = self.store.blob_put(session::K_SESSION_BLOB, &blob);
        }
    }

    pub async fn refresh_connectivity(&self) -> bool {
        match self.api.ping().await {
            Ok(skew) => {
                if let Some(s) = skew {
                    self.clock_skew_secs
                        .store(s, std::sync::atomic::Ordering::Relaxed);
                    // Persist so a later cold offline boot stamps corrected times.
                    let _ = self.store.kv_put("clock_skew_secs", &s.to_string());
                }
                // /health reached a server → online (a fast recovery signal; also
                // resets the unconfirmed-failure streak).
                self.set_online(true);
                // Connectivity is CONFIRMED, so this is the moment a park can be
                // tested rather than guessed at: one authenticated request says
                // whether the bearer is still good. Accepted ⇒ the park was a portal
                // blip and the queue resumes; refused ⇒ it was real, the park holds,
                // and the banner is now up asking for a re-login.
                self.unpark_if_token_accepted().await;
                // Connectivity is CONFIRMED — un-gate the offline backlog so it
                // drains on this pass instead of waiting out the network window.
                let _ = self.store.clear_network_backoff();
                let _ = self.drain_outbox().await; // best-effort
                                                   // Lock the client permission gate to the REAL grants if a sign-in
                                                   // perms-blip left it optimistically open (audit #26) — now that
                                                   // connectivity is confirmed, re-fetch.
                self.refresh_permissions_if_needed().await;
                true
            }
            Err(_) => {
                use std::sync::atomic::Ordering::Relaxed;
                // A lone failed /health probe is NOT proof we're offline: a waking
                // radio / DNS-TLS-not-ready right after a resume or rotation errs the
                // first request, then recovers. CONFIRM against a REAL network op
                // before dropping the banner. If there's a flushable backlog, drain
                // it — `drain_outbox` sets `online` from the actual send outcome (an
                // ack ⇒ online, a transport failure ⇒ offline), so the OUTBOX is the
                // authority. With nothing to flush (empty backlog / no bearer) we
                // can't prove it that way, so require K_OFFLINE_CONFIRM consecutive
                // failed probes — a single blip can't flap the banner.
                let flushable = self.api.has_bearer()
                    && !self.auth_paused.load(Relaxed)
                    && self.store.pending_count().unwrap_or(0) > 0;
                if flushable {
                    let _ = self.drain_outbox().await;
                } else if self.offline_probe_fails.fetch_add(1, Relaxed) + 1 >= K_OFFLINE_CONFIRM {
                    self.set_online(false);
                }
                self.current_session().map(|s| s.online).unwrap_or(false)
            }
        }
    }

    /// The current shift's orders — the still-queued sales (from the outbox,
    /// shown first, always available offline) plus the server's synced orders
    /// when online (best-effort). Errors if there's no current shift.
    pub async fn list_shift_orders(&self) -> Result<Vec<orders::OrderSummaryView>, CoreError> {
        use madar_api::apis::orders_api;
        let shift = shift::current(&self.store)?.ok_or_else(|| CoreError::Validation {
            field: "shift".into(),
            detail: "no shift".into(),
        })?;
        let (branch_id, online) = {
            let g = self.session.read().unwrap_or_else(|e| e.into_inner());
            let s = g.as_ref().ok_or_else(|| CoreError::Unauthenticated {
                detail: "not signed in".into(),
            })?;
            let b = s
                .snapshot
                .branch_id
                .clone()
                .ok_or_else(|| CoreError::Validation {
                    field: "branch_id".into(),
                    detail: "session has no branch".into(),
                })?;
            (b, s.snapshot.online)
        };

        // Always show the still-queued sales (offline-safe).
        let all = orders::queued(&self.store, &shift.id)?;

        // The shift's SYNCED orders: live when online (cached write-through), else
        // the last-synced snapshot. So going offline keeps the orders already synced
        // this shift visible — not just the ones rung during the outage.
        let key = format!("cache:shift_orders:{}", shift.id);
        let mut server: Vec<orders::OrderSummaryView> = if online {
            let params = orders_api::ListOrdersParams {
                branch_id: Some(branch_id),
                shift_id: Some(shift.id.clone()),
                updated_after: None,
                page: None,
                per_page: Some(200),
                teller_name: None,
                waiter_name: None,
                payment_method: None,
                status: None,
                from: None,
                to: None,
                order_type: None,
                exclude_items: None,
                channel: None,
                include_items: Some(true),
            };
            match orders_api::list_orders(&self.api.config(), params).await {
                Ok(page) => {
                    // Do NOT preload page.data into cache:order:{id} for offline reprint:
                    // the list element is models::Order (no `items` field), so it can't
                    // deserialize as the OrderFull that get_order_or_cache reads — that
                    // was a silent offline-reprint failure. The real OrderFull is cached
                    // when the order is opened once online (see get_order_or_cache).
                    let views: Vec<_> = page.data.iter().map(|o| orders::from_server(o)).collect();
                    cache_views(&self.store, &key, &views);
                    views
                }
                Err(_) => cached_views(&self.store, &key),
            }
        } else {
            cached_views(&self.store, &key)
        };
        // Overlay an optimistic "voided" status for orders with a queued void command
        // (the void hasn't synced yet) — applies to fresh OR cached server rows.
        let voiding = orders::pending_void_ids(&self.store)?;
        for v in server.iter_mut() {
            if voiding.contains(&v.id) {
                v.status = "voided".into();
            }
        }
        // Dedup: drop any queued order that has already synced (its client-minted
        // order_ref now appears on a server row), else it double-shows + the stats
        // pill double-counts during the inflight/lost-response window.
        Ok(orders::merge_for_view(all, server))
    }

    /// Fetch a synced order's full detail (lines + modifiers) — the expanded
    /// history row. Offline-durable for any order seen online (cached).
    pub async fn order_detail(
        &self,
        order_id: String,
    ) -> Result<orders::OrderDetailView, CoreError> {
        let o = self.get_order_or_cache(&order_id).await?;
        Ok(orders::order_detail_view(&o, &self.current_locale()))
    }

    // ── Loyalty ─────────────────────────────────────────────────────────────
    // Identify the member at the till and, when they have earned it, hand over a
    // reward. Points are never awarded here: earning rides in the order's own
    // payload (`CheckoutInput::loyalty_customer_id`) and the server computes it
    // from the sale's totals, on the live path and on replay alike.

    /// Look a member up from a scanned pass barcode, or by phone when their
    /// phone is dead.
    ///
    /// Online-only, deliberately: a balance is shared state that any till in the
    /// org can move, and showing a stale number to a customer is worse than
    /// asking the teller to reconnect. The error says exactly that.
    pub async fn loyalty_lookup(
        &self,
        token: Option<String>,
        phone: Option<String>,
    ) -> Result<loyalty::LoyaltyScanView, CoreError> {
        use madar_api::apis::loyalty_api;
        let branch = self.session_branch_id()?;
        if !self.current_session().map(|s| s.online).unwrap_or(false) {
            return Err(CoreError::Offline {
                detail: "a points balance can only be looked up online".into(),
            });
        }
        let branch_uuid = uuid::Uuid::parse_str(&branch).map_err(|_| CoreError::Validation {
            field: "branch_id".into(),
            detail: "session branch is not a uuid".into(),
        })?;
        let mut request = madar_api::models::LookupRequest::new(branch_uuid);
        // Trimmed, and empty treated as absent: a barcode field that lost focus
        // must not be sent as a token the server then reports as "no member".
        request.token = token
            .map(|t| t.trim().to_string())
            .filter(|t| !t.is_empty())
            .map(Some);
        request.phone = phone
            .map(|p| p.trim().to_string())
            .filter(|p| !p.is_empty())
            .map(Some);
        if request.token.is_none() && request.phone.is_none() {
            return Err(CoreError::Validation {
                field: "token".into(),
                detail: "scan a card or type a phone number".into(),
            });
        }
        let result = loyalty_api::loyalty_lookup(
            &self.api.config(),
            loyalty_api::LoyaltyLookupParams {
                lookup_request: request,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(loyalty::scan_view(&result))
    }

    /// Add a sale's points to a member's balance — the button on the receipt,
    /// and on a past order in the history.
    ///
    /// Unlike the lookup this is a WRITE, so it works offline: the press is
    /// stamped and queued, and drains through `/sync/replay` into the very same
    /// server code. That is why the window is anchored to when the button was
    /// pressed rather than when the op arrived — a till that was offline for two
    /// days still credits an award its teller made in time.
    ///
    /// The window is checked here as well as on the server. This copy stops a
    /// pointless queued op; the server's copy is the one that decides.
    pub async fn loyalty_award(
        &self,
        order_id: Option<String>,
        order_key: Option<String>,
        order_created_at: String,
        token: Option<String>,
        phone: Option<String>,
        // The member already identified for this sale, if the card was scanned
        // at the till. Then collecting the points needs no second scan.
        customer_id: Option<String>,
    ) -> Result<loyalty::LoyaltyAwardOutcome, CoreError> {
        use madar_api::apis::loyalty_api;
        let branch = self.session_branch_id()?;
        let locale = self.current_locale();
        let now = self.corrected_now();
        if !loyalty::award_window_open(&order_created_at, &now.to_rfc3339()) {
            return Err(CoreError::Validation {
                field: "order".into(),
                detail: format!(
                    "points can only be added within {} hours of a sale",
                    loyalty::AWARD_WINDOW_HOURS
                ),
            });
        }
        let branch_uuid = uuid::Uuid::parse_str(&branch).map_err(|_| CoreError::Validation {
            field: "branch_id".into(),
            detail: "session branch is not a uuid".into(),
        })?;

        let mut request = madar_api::models::AwardRequest::new(branch_uuid);
        request.order_id = order_id
            .as_deref()
            .and_then(|s| uuid::Uuid::parse_str(s).ok())
            .map(Some);
        request.order_key = order_key
            .as_deref()
            .and_then(|s| uuid::Uuid::parse_str(s).ok())
            .map(Some);
        request.token = token
            .map(|t| t.trim().to_string())
            .filter(|t| !t.is_empty())
            .map(Some);
        request.phone = phone
            .map(|p| p.trim().to_string())
            .filter(|p| !p.is_empty())
            .map(Some);
        request.customer_id = customer_id
            .as_deref()
            .and_then(|s| uuid::Uuid::parse_str(s).ok())
            .map(Some);
        if request.order_id.is_none() && request.order_key.is_none() {
            return Err(CoreError::Validation {
                field: "order".into(),
                detail: "no order to add points to".into(),
            });
        }
        // A card scanned at the till already named the customer, and the order
        // remembers it. Requiring a SECOND scan to collect the points for the
        // same sale is what made this read as two unrelated features standing
        // at one counter.
        if request.token.is_none() && request.phone.is_none() && request.customer_id.is_none() {
            return Err(CoreError::Validation {
                field: "token".into(),
                detail: "scan a card or type a phone number".into(),
            });
        }
        // The moment of the press, on the device's corrected clock. The drain
        // rebases it again by the measured offset before sending, so a till with
        // a wrong clock is not punished by the server's bounds.
        request.requested_at = Some(Some(now.into()));

        if self.current_session().map(|s| s.online).unwrap_or(false) {
            match loyalty_api::loyalty_award(
                &self.api.config(),
                loyalty_api::LoyaltyAwardParams {
                    award_request: request.clone(),
                },
            )
            .await
            {
                // `already_awarded` rides back out with the balance: a second
                // press on the same sale is safe (the ledger is unique per
                // order), and the teller is told it was already collected
                // rather than shown a second "added".
                Ok(result) => return Ok(loyalty::award_outcome(&locale, &result)),
                Err(e) => match net::map_api_error(e) {
                    // The session said online but the round trip failed — this
                    // is the offline case arriving a moment late. Queue the
                    // press rather than losing it.
                    CoreError::Offline { .. } | CoreError::Transient { .. } => {}
                    // Anything else is a real answer from the server (the window
                    // has closed, the card is not ours, the program is off) and
                    // must reach the teller instead of being queued to fail
                    // again later, silently, forever.
                    other => return Err(other),
                },
            }
        }

        // Gate the award behind the SALE when that sale is itself still queued.
        // The order's outbox id is its client-minted key, which is the same
        // `order_key` this award names — so the two are linked with no new
        // bookkeeping. Without this the award could reach the server first and
        // be refused for an order that had not arrived yet.
        let depends_on_seq = match order_key.as_deref() {
            Some(key) => self.store.live_seq_of(key)?,
            None => None,
        };
        let cmd = loyalty::AwardCommand { request };
        let (user_id, clock_offset_ms) = self.outbox_meta();
        let op_id = format!("loyalty_award:{}", uuid::Uuid::new_v4());
        self.store.enqueue(&store::NewOutboxOp {
            id: op_id.clone(),
            op_type: "award_loyalty_points".into(),
            idempotency_key: op_id,
            payload: serde_json::to_string(&cmd)?,
            event_at: now.to_rfc3339(),
            depends_on_seq,
            user_id,
            clock_offset_ms,
            shift_id: None,
        })?;
        // Try to send it straight away; offline simply leaves it queued.
        let _ = self.drain_outbox().await;
        // Queued: there is no balance to show yet. The outcome says so in as
        // many words rather than inventing a number.
        Ok(loyalty::award_queued(&locale))
    }

    /// Re-render a synced order as a receipt for reprint — same ESC/POS path as a
    /// fresh receipt. Offline-durable for any order seen online (cached).
    pub async fn render_order_receipt(
        &self,
        order_id: String,
        store_name: String,
        currency: String,
        width: u32,
        brand: receipt::PrinterBrand,
    ) -> Result<Vec<u8>, CoreError> {
        let o = self.get_order_or_cache(&order_id).await?;
        let receipt = orders::order_to_receipt(&o, &self.current_locale());
        Ok(self.render_receipt(receipt, store_name, currency, width, brand))
    }

    /// Project a synced order into a ReceiptView (no bytes) — for an on-screen
    /// receipt preview before reprinting. Offline-durable for any order seen online.
    pub async fn order_receipt_view(
        &self,
        order_id: String,
    ) -> Result<checkout::ReceiptView, CoreError> {
        let o = self.get_order_or_cache(&order_id).await?;
        Ok(orders::order_to_receipt(&o, &self.current_locale()))
    }

    /// A PAST shift's synced orders (history-screen expansion). Live when online
    /// (cached write-through, same key as the current-shift list), else the last-
    /// synced snapshot — so an expanded past shift keeps its orders offline.
    pub async fn list_orders_for_shift(
        &self,
        shift_id: String,
    ) -> Result<Vec<orders::OrderSummaryView>, CoreError> {
        use madar_api::apis::orders_api;
        let (branch_id, online) = {
            let g = self.session.read().unwrap_or_else(|e| e.into_inner());
            let s = g.as_ref().ok_or_else(|| CoreError::Unauthenticated {
                detail: "not signed in".into(),
            })?;
            let b = s
                .snapshot
                .branch_id
                .clone()
                .ok_or_else(|| CoreError::Validation {
                    field: "branch_id".into(),
                    detail: "session has no branch".into(),
                })?;
            (b, s.snapshot.online)
        };
        let key = format!("cache:shift_orders:{shift_id}");
        // Queued (offline-rung) orders for THIS shift first — a shift opened AND
        // sold on entirely offline has ALL its orders here, not on the server, so
        // without this its history would be empty offline.
        let all = orders::queued(&self.store, &shift_id)?;
        let mut server: Vec<orders::OrderSummaryView> = if online {
            let params = orders_api::ListOrdersParams {
                branch_id: Some(branch_id),
                shift_id: Some(shift_id.clone()),
                updated_after: None,
                page: None,
                per_page: Some(200),
                teller_name: None,
                waiter_name: None,
                payment_method: None,
                status: None,
                from: None,
                to: None,
                order_type: None,
                exclude_items: None,
                channel: None,
                include_items: Some(true),
            };
            match orders_api::list_orders(&self.api.config(), params).await {
                Ok(page) => {
                    // Do NOT preload page.data into cache:order:{id} for offline reprint:
                    // the list element is models::Order (no `items` field), so it can't
                    // deserialize as the OrderFull that get_order_or_cache reads — that
                    // was a silent offline-reprint failure. The real OrderFull is cached
                    // when the order is opened once online (see get_order_or_cache).
                    let views: Vec<_> = page.data.iter().map(|o| orders::from_server(o)).collect();
                    cache_views(&self.store, &key, &views);
                    views
                }
                Err(_) => cached_views(&self.store, &key),
            }
        } else {
            cached_views(&self.store, &key)
        };
        // Optimistic "voided" overlay for orders with a queued void (fresh OR cached).
        let voiding = orders::pending_void_ids(&self.store)?;
        for v in server.iter_mut() {
            if voiding.contains(&v.id) {
                v.status = "voided".into();
            }
        }
        // Dedup: drop any queued order that has already synced (its client-minted
        // order_ref now appears on a server row), else it double-shows + the stats
        // pill double-counts during the inflight/lost-response window.
        Ok(orders::merge_for_view(all, server))
    }

    /// Search the branch's orders ACROSS shifts (history lookup) with optional
    /// filters (status / teller / payment method / from-to dates) + pagination
    /// (50/page, 1-based). Online-only — the shift-scoped list is the offline path,
    /// so a Server/Network error surfaces rather than returning a stale snapshot.
    pub async fn search_orders(
        &self,
        status: Option<String>,
        teller_name: Option<String>,
        payment_method: Option<String>,
        from: Option<String>,
        to: Option<String>,
        page: u32,
    ) -> Result<orders::OrderSearchPage, CoreError> {
        use madar_api::apis::orders_api;
        let branch_id = {
            let g = self.session.read().unwrap_or_else(|e| e.into_inner());
            let s = g.as_ref().ok_or_else(|| CoreError::Unauthenticated {
                detail: "not signed in".into(),
            })?;
            s.snapshot
                .branch_id
                .clone()
                .ok_or_else(|| CoreError::Validation {
                    field: "branch_id".into(),
                    detail: "session has no branch".into(),
                })?
        };
        let blank = |s: Option<String>| s.filter(|x| !x.is_empty());
        let date = |s: Option<String>| {
            s.filter(|x| !x.is_empty())
                .and_then(|x| chrono::DateTime::parse_from_rfc3339(&x).ok())
        };
        let f_status = blank(status);
        let f_teller = blank(teller_name);
        let f_payment = blank(payment_method);
        let f_from = date(from);
        let f_to = date(to);
        let per_page = 50i64;
        let params = orders_api::ListOrdersParams {
            branch_id: Some(branch_id),
            shift_id: None,
            updated_after: None,
            page: Some(page.max(1) as i64),
            per_page: Some(per_page),
            teller_name: f_teller.clone(),
            waiter_name: None,
            payment_method: f_payment.clone(),
            status: f_status.clone(),
            from: f_from,
            to: f_to,
            order_type: None,
            exclude_items: None,
            channel: None,
            include_items: Some(false),
        };
        let resp = orders_api::list_orders(&self.api.config(), params)
            .await
            .map_err(net::map_api_error)?;
        let mut orders: Vec<_> = resp.data.iter().map(orders::from_server).collect();
        let mut total = resp.total.max(0) as u32;
        let has_more = resp.page * resp.per_page < resp.total;
        // Surface still-queued OFFLINE orders on page 1, else search history is
        // silently missing them. Apply the data-driven filters (status / payment /
        // date); a teller filter excludes them (no echoed teller name yet). Dedup
        // by order_ref against the server page (an order that just synced is there).
        if page.max(1) == 1 && f_teller.is_none() {
            let q: Vec<orders::OrderSummaryView> = orders::queued_all(&self.store)?
                .into_iter()
                .filter(|o| {
                    f_status.as_deref().map_or(true, |s| o.status == s)
                        && f_payment.as_deref().map_or(true, |p| o.payment_label == p)
                        && {
                            let c = chrono::DateTime::parse_from_rfc3339(&o.created_at).ok();
                            f_from.map_or(true, |f| c.is_some_and(|c| c >= f))
                                && f_to.map_or(true, |t| c.is_some_and(|c| c <= t))
                        }
                })
                .collect();
            let server_len = orders.len();
            orders = orders::merge_for_view(q, orders);
            total += (orders.len() - server_len) as u32; // count the queued ones we added
        }
        Ok(orders::OrderSearchPage {
            orders,
            page: page.max(1),
            total,
            has_more,
        })
    }

    /// A PAST shift's Z-report (history-screen reprint). Live when online (cached
    /// write-through), else the cached report; and for a shift opened+closed
    /// entirely OFFLINE — which never had a server report — reconstructed from the
    /// local opening cash + that shift's queued cash sales + movements.
    pub async fn shift_report_for(
        &self,
        shift_id: String,
    ) -> Result<shift::ShiftReportView, CoreError> {
        use madar_api::apis::shifts_api;
        let key = format!("cache:shift_report:{shift_id}");
        if self.current_session().map(|s| s.online).unwrap_or(false) {
            if let Ok(report) = shifts_api::get_shift_report(
                &self.api.config(),
                shifts_api::GetShiftReportParams {
                    shift_id: shift_id.clone(),
                },
            )
            .await
            {
                cache_views(&self.store, &key, std::slice::from_ref(&report));
                // A partially-synced past shift may still hold queued cash not in
                // the (cached) server report — add it, else expected_cash is
                // understated and the drawer reads a false "over".
                return Ok(shift::report_view(
                    &report,
                    checkout::queued_cash_total_for(&self.store, &shift_id)?,
                ));
            }
        }
        // Offline / fetch failed: the last-synced report if we have one…
        if let Some(report) =
            cached_views::<madar_api::models::ShiftReportResponse>(&self.store, &key)
                .into_iter()
                .next()
        {
            return Ok(shift::report_view(&report, 0));
        }
        // …otherwise an offline-only shift: reconstruct the drawer from local state.
        self.offline_report_for(&shift_id)
    }

    /// Reconstruct a shift's Z-report from purely LOCAL state (opening cash + that
    /// shift's queued cash sales + movements) — for a shift opened+closed offline
    /// that the server has never seen. Mirrors the current-shift `shift_report`
    /// offline branch, scoped to an arbitrary shift id.
    fn offline_report_for(&self, shift_id: &str) -> Result<shift::ShiftReportView, CoreError> {
        // Resolve opening cash + teller + opened-at from the current shift if it
        // matches, else from the reconstructed local-shift list (distinct types,
        // so pull the three values out of each rather than unifying the objects).
        let (opening, teller_name, opened_at) =
            if let Some(s) = shift::current(&self.store)?.filter(|s| s.id == shift_id) {
                (s.opening_cash_minor, Some(s.teller_name), s.opened_at)
            } else if let Some(s) = shift::local_shifts(&self.store)
                .into_iter()
                .find(|s| s.id == shift_id)
            {
                (s.opening_cash_minor, s.teller_name, s.opened_at)
            } else {
                (0, None, String::new())
            };
        let teller = teller_name.filter(|t| !t.is_empty()).unwrap_or_else(|| {
            self.current_session()
                .map(|s| s.display_name)
                .unwrap_or_default()
        });
        let queued_cash = checkout::queued_cash_total_for(&self.store, shift_id)?;
        let movements: Vec<shift::ShiftReportCashLine> = self
            .store
            .list_active_of_types(&["cash_movement"])?
            .into_iter()
            .filter(|i| i.shift_id.as_deref() == Some(shift_id))
            .filter_map(|i| {
                serde_json::from_str::<shift::CashMovementCommand>(&i.payload)
                    .ok()
                    .map(|cmd| shift::ShiftReportCashLine {
                        amount_minor: cmd.request.amount as i64,
                        note: cmd.request.note,
                        moved_by_name: teller.clone(),
                        created_at: i.event_at.clone(),
                    })
            })
            .collect();
        Ok(shift::offline_report_view(
            opening,
            queued_cash,
            movements,
            teller,
            opened_at,
            chrono::Utc::now().to_rfc3339(),
        ))
    }

    /// Void a synced order (mistake/refund). Queues an idempotent `void_order`
    /// command keyed `{order_id}:void` and tries to send now; works offline.
    /// History reflects it immediately via the pending-void overlay. Only synced
    /// orders (with a server id) can be voided — a queued order isn't on the
    /// server yet.
    pub async fn void_order(
        &self,
        order_id: String,
        reason: String,
        note: Option<String>,
        restore_inventory: bool,
    ) -> Result<(), CoreError> {
        // Must be signed in (the replay needs a token).
        if !self.is_authenticated() {
            return Err(CoreError::Unauthenticated {
                detail: "not signed in".into(),
            });
        }
        let voided_at = self.corrected_now().fixed_offset();
        // Translate the host reason key to the backend's accepted vocabulary — an
        // unmapped value (e.g. the old "mistake"/"customer"/"quality") would 400 and
        // dead-letter the void, leaving the refunded order counted as revenue.
        let mut request =
            madar_api::models::VoidOrderRequest::new(map_void_reason(&reason).to_string());
        request.note = Some(note);
        request.restore_inventory = Some(Some(restore_inventory));
        request.voided_at = Some(Some(voided_at));

        // The void targets a SYNCED order (server id), so it has no queued
        // create_order to gate behind. If that order was created offline and is
        // still queued, the void depends on it (and the drain's 404-on-void
        // handling protects against the order never landing).
        let cmd = orders::VoidOrderCommand {
            order_id: order_id.clone(),
            request,
        };
        let (user_id, clock_offset_ms) = self.outbox_meta();
        self.store.enqueue(&store::NewOutboxOp {
            id: format!("{order_id}:void"),
            op_type: "void_order".into(),
            idempotency_key: format!("{order_id}:void"),
            payload: serde_json::to_string(&cmd)?,
            event_at: voided_at.to_rfc3339(),
            depends_on_seq: self.store.live_seq_of(&order_id)?,
            user_id,
            clock_offset_ms,
            // Stamp the void with the current shift so the close-last gate
            // (`has_live_shift_writes`, which lists `void_order`) holds this
            // shift's close back until the void has synced. Without it the close
            // could replay before the void and freeze the Z-report's
            // closing_cash_system too high (the voided sale still counted).
            shift_id: shift::current(&self.store)?.map(|s| s.id),
        })?;
        let _ = self.drain_outbox().await;
        Ok(())
    }

    /// Reconcile the device's shift with the server (online). Caches the server's
    /// open shift, or CLEARS the local cache when the server reports none — e.g.
    /// a dashboard force-close, or a shift opened on another device. The server
    /// is the source of truth when online; call this on login and on app resume.
    pub async fn refresh_shift(&self) -> Result<Option<shift::ShiftView>, CoreError> {
        use madar_api::apis::shifts_api;
        let till_id = device::load(&self.store).till_id;
        let (branch_id, signed_in_teller, role) = {
            let g = self.session.read().unwrap_or_else(|e| e.into_inner());
            let s = g.as_ref().ok_or_else(|| CoreError::Unauthenticated {
                detail: "not signed in".into(),
            })?;
            let branch = s
                .snapshot
                .branch_id
                .clone()
                .ok_or_else(|| CoreError::Validation {
                    field: "branch_id".into(),
                    detail: "session has no branch".into(),
                })?;
            (branch, s.snapshot.user_id.clone(), s.snapshot.role.clone())
        };
        // Only tellers hold a shift. Waiters/kitchen devices never open one, so
        // skip `/shifts/current` for them — they lack `shifts:read`, and the call
        // would 403 (harmlessly swallowed by the host, but noisy in the logs). They
        // simply have no shift.
        if role != "teller" {
            return Ok(None);
        }
        let prefill = shifts_api::get_current_shift(
            &self.api.config(),
            // The device's bound till scopes the carryover suggestion; `None` =
            // the branch default-till (single-till behavior).
            shifts_api::GetCurrentShiftParams {
                branch_id,
                till_id: till_id.filter(|s| !s.is_empty()),
            },
        )
        .await
        .map_err(net::map_api_error)?;

        // Adopt the SERVER's carried-over opening-cash suggestion (its last synced
        // declared closing) only when we're FULLY SYNCED — internet reachable AND
        // no queued ops. A still-queued close means the server's last-close figure
        // is stale, so the locally-cached value (set when we closed) is the fresher
        // truth; online-but-unsynced and fully-offline both keep the local
        // suggestion. The `> 0` guard additionally stops a server 0 (no prior close
        // it knows of) from clobbering a good local value.
        let fully_synced = self.store.pending_count().map(|n| n == 0).unwrap_or(false);
        if fully_synced && prefill.suggested_opening_cash > 0 {
            shift::cache_suggested_opening_cash(
                &self.store,
                prefill.suggested_opening_cash as i64,
            )?;
        }

        // The server's "no open shift" is only authoritative once our own
        // open_shift command has actually reached it. While it's still queued,
        // the optimistic local shift stands — clearing it here is what bounced
        // the teller straight back to the open-shift screen.
        let open_pending = self.shift_command_pending("open_shift")?;
        let close_pending = self.shift_command_pending("close_shift")?;
        match shift::reconcile(&prefill, &signed_in_teller, open_pending, close_pending) {
            shift::ShiftReconcile::Adopt(server_shift) => {
                // Recover orphaned offline sales. If this teller has queued/dead ops
                // on a shift the device opened optimistically OFFLINE that never
                // became real server-side (the optimistic open conflicted on the
                // branch and dead-lettered, cascading its orders), those sales
                // belong on the teller's REAL open shift — the one we're adopting.
                // Re-point them onto it and requeue the dead ones so they sync,
                // instead of stranding the sales forever.
                let server_id = server_shift.id.to_string();
                let teller_id = server_shift.teller_id.to_string();
                let mut remapped = 0u32;
                for orphan in self.store.orphan_open_shift_ids(&teller_id, &server_id)? {
                    remapped += self.store.remap_shift(&orphan, &server_id)?;
                }
                let requeued = if remapped > 0 {
                    self.store.requeue_dead_for_shift(&server_id)?
                } else {
                    0
                };
                shift::save(&self.store, &server_shift)?;
                if remapped > 0 {
                    self.push_diag(
                        "info",
                        format!("recovered {remapped} queued op(s) ({requeued} re-tried) onto the active shift after an offline shift conflict"),
                    );
                    // Flush the re-pointed sales now (single-flight-guarded).
                    let _ = self.drain_outbox().await;
                }
                // Seed the offline close-report base WHILE WE STILL HAVE NETWORK.
                // Adopting means this teller is joining a shift that may already
                // hold sales none of which are in our outbox; if the network drops
                // before they ever open the report screen, this snapshot is the
                // only thing standing between them and a close that expects just
                // the opening float. Best effort — never block sign-in on it.
                self.cache_shift_report_snapshot(&server_id).await;
                Ok(Some(shift::view_from(&server_shift)))
            }
            shift::ShiftReconcile::KeepLocal => shift::current(&self.store),
            shift::ShiftReconcile::Clear => {
                shift::clear(&self.store)?;
                Ok(None)
            }
        }
    }

    /// Evict cached shift history older than [`CACHE_RETENTION_DAYS`].
    ///
    /// A closed shift, its orders, its drawer movements and its Z-report stay
    /// fully readable offline for the retention window and are then dropped, so
    /// a till that runs for a year does not carry a year of history in its
    /// SQLite file. Only per-shift and per-order history is swept — the live
    /// mirrors (open tickets, KDS, floor, tills) are current state, not history,
    /// and are replaced wholesale on every pull.
    ///
    /// Eviction is by LAST READ-THROUGH, not by the shift's own date: every
    /// cache write re-stamps `updated_at`, so a shift someone actually opens
    /// keeps its place and only genuinely untouched history ages out. Anything
    /// dropped is re-fetchable while online.
    pub fn prune_stale_caches(&self) -> Result<u32, CoreError> {
        let cutoff =
            (chrono::Utc::now() - chrono::Duration::days(CACHE_RETENTION_DAYS)).to_rfc3339();
        let mut n = 0;
        for prefix in CACHE_HISTORY_PREFIXES {
            n += self.store.purge_cache_older_than(prefix, &cutoff)?;
        }
        // Then the count ceiling: the window bounds age, not volume.
        for (prefix, cap) in CACHE_ROW_CAPS {
            n += self.store.purge_cache_keep_newest(prefix, *cap)?;
        }
        // Deleting rows only frees pages inside the file; hand them back to the
        // device, or the retention window buys space nobody can use.
        if n > 0 {
            let _ = self.store.reclaim_free_pages();
        }
        Ok(n)
    }

    /// Fetch and cache the server's report for `shift_id`, so an offline close
    /// has real figures to work from. Best effort: a failure here just leaves the
    /// previous snapshot (or none) in place, and the caller carries on.
    async fn cache_shift_report_snapshot(&self, shift_id: &str) {
        use madar_api::apis::shifts_api;
        if let Ok(report) = shifts_api::get_shift_report(
            &self.api.config(),
            shifts_api::GetShiftReportParams {
                shift_id: shift_id.to_string(),
            },
        )
        .await
        {
            cache_views(
                &self.store,
                &shift::report_cache_key(shift_id),
                std::slice::from_ref(&report),
            );
        }
    }

    /// Print pre-rendered ESC/POS bytes to the DEVICE's configured printer (from the
    /// core device config — the host passes no host:port). Errors if no printer is
    /// bound. Thin wrapper over `send_to_printer`; the device binding is the source
    /// of truth so the hosts hold no printer state.
    pub async fn print_to_device(&self, bytes: Vec<u8>) -> Result<(), CoreError> {
        let cfg = device::load(&self.store);
        let host =
            cfg.printer_host
                .filter(|s| !s.is_empty())
                .ok_or_else(|| CoreError::Validation {
                    field: "printer".into(),
                    detail: "no printer configured for this device".into(),
                })?;
        let port = cfg.printer_port.unwrap_or(9100);
        self.send_to_printer(host, port, bytes).await
    }

    /// Best-effort raw-TCP send of pre-rendered ESC/POS bytes to a network
    /// (JetDirect / port 9100) thermal printer. Opens a short-lived socket,
    /// writes, flushes. Errors map to `Transient` so the host can offer a retry.
    ///
    /// NOTE: unverifiable here without hardware — the rendered bytes are the
    /// tested contract (`receipt` module); delivery is the host's to confirm.
    pub async fn send_to_printer(
        &self,
        host: String,
        port: u16,
        bytes: Vec<u8>,
    ) -> Result<(), CoreError> {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        use tokio::time::{sleep, timeout, Duration};
        let addr = format!("{host}:{port}");

        // Connect with a short retry. The auto-print fires the instant checkout
        // finishes, when the FIRST connect can transiently fail — the printer is
        // still finishing the previous job (single-session #9100), the ARP entry is
        // cold, or the post-sale backend sync is saturating the link. A manual
        // reprint a moment later always succeeds, so a couple of quick retries make
        // the automatic print as reliable as the manual one. Only the CONNECT is
        // retried; the write is never replayed, so a partial send can't double-print.
        let mut stream = {
            let mut last: Option<CoreError> = None;
            let mut ok = None;
            for attempt in 0..3u32 {
                if attempt > 0 {
                    sleep(Duration::from_millis(300)).await;
                }
                match timeout(
                    Duration::from_secs(4),
                    tokio::net::TcpStream::connect(&addr),
                )
                .await
                {
                    Ok(Ok(s)) => {
                        ok = Some(s);
                        break;
                    }
                    Ok(Err(e)) => {
                        last = Some(CoreError::Transient {
                            detail: format!("printer connect: {e}"),
                        })
                    }
                    Err(_) => {
                        last = Some(CoreError::Transient {
                            detail: format!("printer timeout: {addr}"),
                        })
                    }
                }
            }
            match ok {
                Some(s) => s,
                None => return Err(last.unwrap()),
            }
        };

        // Star printers (TSP143IIILAN and friends) continuously push ASB status
        // bytes back to the host. If we only write and never read, the printer's
        // TX buffer fills, which back-pressures its RX and stalls the job *before
        // it prints* — a silent "connection succeeds, nothing prints" failure,
        // confirmed on hardware. So we drain (and discard) the status channel
        // concurrently with the write. This is what the Star SDK does, and it
        // works whether or not the printer's "#9100 Multi Session" option is on.
        let (mut rd, mut wr) = stream.split();
        let write_job = async {
            wr.write_all(&bytes).await?;
            wr.flush().await
        };
        let drain = async {
            let mut buf = [0u8; 512];
            // Read until the printer stops sending or closes; bytes are discarded.
            while let Ok(n) = rd.read(&mut buf).await {
                if n == 0 {
                    break;
                }
            }
        };
        tokio::pin!(drain);
        // Completing the write is success; keep draining throughout so the job is
        // never starved. (A printer that closes first hits the drain branch.)
        tokio::select! {
            w = write_job => w.map_err(|e| CoreError::Transient {
                detail: format!("printer write: {e}"),
            })?,
            _ = &mut drain => {}
        }
        // The write completing means every byte was accepted by the printer (the
        // concurrent drain kept its RX from stalling), so the job will print from
        // its buffer regardless of when we close. A brief final drain consumes any
        // trailing status without making the UI wait — the old 2s grace was the
        // ~3s "loading" the teller saw on every sale.
        let _ = timeout(Duration::from_millis(200), drain).await;
        Ok(())
    }
}

// ── delivery-order management (online; teller works the live branch queue) ───
impl MadarCore {
    /// The signed-in session's branch id, or a validation error.
    fn session_branch_id(&self) -> Result<String, CoreError> {
        let g = self.session.read().unwrap_or_else(|e| e.into_inner());
        let s = g.as_ref().ok_or_else(|| CoreError::Unauthenticated {
            detail: "not signed in".into(),
        })?;
        s.snapshot
            .branch_id
            .clone()
            .ok_or_else(|| CoreError::Validation {
                field: "branch_id".into(),
                detail: "session has no branch".into(),
            })
    }
}

// ── waiter open tickets (fire-now-pay-later via the outbox) ───────────────────
#[cfg_attr(feature = "uniffi-ffi", uniffi::export(async_runtime = "tokio"))]
impl MadarCore {
    /// FIRE the current cart as a new dine-in open ticket (round 1). Prices the
    /// cart client-authoritatively (same engine as checkout), enqueues the durable
    /// fire op (offline-first), clears the cart, and best-effort drains. Returns a
    /// slim "sent to kitchen" confirmation — NOT a money receipt. The branch must
    /// be operating (the server enforces an open till at fire time).
    /// Seat a party: take the table, and nothing else.
    ///
    /// Sitting down is not a bill. This used to open an EMPTY TICKET, which put
    /// a zero-value tab in every report and made a party who changed their mind
    /// and left something you had to void. Occupancy travels on its own now, on
    /// the same `hold_table` op a parked cart uses, and the tab starts with the
    /// party's first round — which claims the table they are already sitting at.
    ///
    /// Optimistic-local + queued, so a party can be seated with no network.
    pub async fn seat_table(&self, table_id: String) -> Result<(), CoreError> {
        self.session_branch_id()?;
        held::set_table_state_local(&self.store, &table_id, Some("seated"), None, false)?;
        self.sync_hold_occupancy(None, Some(table_id), false)?;
        let _ = self.drain_outbox().await;
        Ok(())
    }

    /// Give a table back without a sale: the party left before ordering, or the
    /// teller seated the wrong one. Frees it outright — nobody ate, so there is
    /// nothing to bus.
    pub async fn unseat_table(&self, table_id: String) -> Result<(), CoreError> {
        self.session_branch_id()?;
        held::set_table_state_local(&self.store, &table_id, Some("free"), None, false)?;
        self.sync_hold_occupancy(Some(table_id), None, false)?;
        let _ = self.drain_outbox().await;
        Ok(())
    }

    pub async fn fire_ticket(
        &self,
        table_id: Option<String>,
        customer_name: Option<String>,
        notes: Option<String>,
        guest_count: Option<i32>,
        booking_id: Option<String>,
    ) -> Result<tickets::TicketFiredView, CoreError> {
        let branch_id = self.session_branch_id()?;
        let branch_uuid = uuid::Uuid::parse_str(&branch_id).map_err(|_| CoreError::Validation {
            field: "branch_id".into(),
            detail: "bad branch id".into(),
        })?;
        let lines = cart::lines(&self.store)?;
        if lines.is_empty() {
            return Err(CoreError::Validation {
                field: "cart".into(),
                detail: "cart is empty".into(),
            });
        }
        let items = checkout::lines_to_wire_items(&lines);
        let ticket_id = uuid::Uuid::new_v4();
        let round_id = uuid::Uuid::new_v4();
        let table_uuid = table_id
            .as_deref()
            .and_then(|s| uuid::Uuid::parse_str(s).ok());
        let booking_uuid = booking_id
            .as_deref()
            .and_then(|s| uuid::Uuid::parse_str(s).ok());
        let request = tickets::build_fire_request(
            branch_uuid,
            items,
            ticket_id,
            round_id,
            table_uuid,
            customer_name,
            notes,
            guest_count,
            booking_uuid,
        );
        // The booked party sat down: reflect it locally before the server does.
        if let Some(bid) = booking_id.as_deref() {
            let _ = bookings::set_status_local(&self.store, bid, "seated");
            let _ = held::set_booking_status_local(&self.store, bid, "seated");
        }
        let cmd = tickets::FireTicketCommand {
            ticket_id: ticket_id.to_string(),
            request,
        };

        let (user_id, clock_offset_ms) = self.outbox_meta();
        let teller = user_id.clone();
        self.store.enqueue(&store::NewOutboxOp {
            id: ticket_id.to_string(),
            op_type: "open_ticket".into(),
            idempotency_key: ticket_id.to_string(),
            payload: serde_json::to_string(&cmd)?,
            event_at: self.corrected_now().to_rfc3339(),
            depends_on_seq: None, // a ticket floats free of any shift/till
            user_id,
            clock_offset_ms,
            shift_id: None, // the waiter holds no shift
        })?;
        cart::clear(&self.store)?;
        // Instant LAN delivery → the KDS sees the fire NOW. `data` is a projection of
        // the ticket with the SAME derived ids the server will mint (so it dedups on
        // reconnect); `replay_op` lets a kitchen peer mirror it for durability. The
        // outbox stays the truth.
        let projection = kds::build_fire_projection(
            &round_id.to_string(),
            &lines,
            None,
            1,
            self.corrected_now().to_rfc3339(),
        );
        let data = projection
            .as_ref()
            .and_then(|p| serde_json::to_string(p).ok())
            .unwrap_or_else(|| "{}".into());
        let envelope = serde_json::json!({
            "op": "fire_open_ticket", "teller_id": teller, "request": cmd.request
        })
        .to_string();
        self.lan_publish("kitchen", "kitchen.fired", data, Some(envelope))
            .await;
        let _ = self.drain_outbox().await;

        let tid = ticket_id.to_string();
        let queued_offline = self.store.pending()?.iter().any(|i| i.id == tid);
        Ok(tickets::TicketFiredView {
            ticket_id: tid,
            ticket_ref: None,
            queued_offline,
        })
    }

    /// Add a ROUND of the current cart to an existing open ticket. Same offline-first
    /// path as `fire_ticket`; gated behind the original fire if it hasn't synced.
    pub async fn add_ticket_round(
        &self,
        ticket_id: String,
    ) -> Result<tickets::TicketFiredView, CoreError> {
        let lines = cart::lines(&self.store)?;
        if lines.is_empty() {
            return Err(CoreError::Validation {
                field: "cart".into(),
                detail: "cart is empty".into(),
            });
        }
        let items = checkout::lines_to_wire_items(&lines);
        let round_id = uuid::Uuid::new_v4();
        let request = tickets::build_round_request(items, round_id);
        let cmd = tickets::AddRoundCommand {
            ticket_id: ticket_id.clone(),
            round_id: round_id.to_string(),
            request,
        };
        let (user_id, clock_offset_ms) = self.outbox_meta();
        let teller = user_id.clone();
        self.store.enqueue(&store::NewOutboxOp {
            id: round_id.to_string(),
            op_type: "ticket_add_round".into(),
            idempotency_key: round_id.to_string(),
            payload: serde_json::to_string(&cmd)?,
            event_at: self.corrected_now().to_rfc3339(),
            // The round can't land before the ticket exists — gate on the queued fire.
            depends_on_seq: self.store.live_seq_of(&ticket_id)?,
            user_id,
            clock_offset_ms,
            shift_id: None,
        })?;
        cart::clear(&self.store)?;
        // Instant LAN delivery of the new round — its own kitchen ticket (derived
        // from THIS round's id), projected for offline visibility + a mirror envelope.
        let projection = kds::build_fire_projection(
            &round_id.to_string(),
            &lines,
            None,
            0,
            self.corrected_now().to_rfc3339(),
        );
        let data = projection
            .as_ref()
            .and_then(|p| serde_json::to_string(p).ok())
            .unwrap_or_else(|| "{}".into());
        let envelope = serde_json::json!({
            "op": "add_ticket_round", "teller_id": teller, "ticket_id": ticket_id, "request": cmd.request
        })
        .to_string();
        self.lan_publish("kitchen", "kitchen.fired", data, Some(envelope))
            .await;
        let _ = self.drain_outbox().await;
        let rid = round_id.to_string();
        let queued_offline = self.store.pending()?.iter().any(|i| i.id == rid);
        Ok(tickets::TicketFiredView {
            ticket_id,
            ticket_ref: None,
            queued_offline,
        })
    }

    /// VOID an open ticket (and pull its kitchen tickets off the KDS). Offline-first.
    pub async fn void_ticket(
        &self,
        ticket_id: String,
        reason: Option<String>,
    ) -> Result<bool, CoreError> {
        let mut request = madar_api::models::VoidOpenTicketRequest::new();
        // The wire takes the backend's enum now; the host's friendlier keys go
        // through the same map as an order void. A key that maps to `other`
        // keeps its original wording as the note — the backend requires one
        // with `other`, and the wording is the only thing that says why.
        if let Some(raw) = reason.filter(|s| !s.trim().is_empty()) {
            let mapped = map_void_reason(raw.trim());
            if mapped == madar_api::models::VoidReason::Other && raw.trim() != "other" {
                request.note = Some(Some(raw.trim().to_string()));
            }
            request.reason = Some(Some(mapped));
        }
        let cmd = tickets::VoidTicketCommand {
            ticket_id: ticket_id.clone(),
            request,
        };
        let (user_id, clock_offset_ms) = self.outbox_meta();
        let op_id = format!("{ticket_id}:void");
        self.store.enqueue(&store::NewOutboxOp {
            id: op_id.clone(),
            op_type: "void_ticket".into(),
            idempotency_key: op_id.clone(),
            payload: serde_json::to_string(&cmd)?,
            event_at: self.corrected_now().to_rfc3339(),
            depends_on_seq: self.store.live_seq_of(&ticket_id)?,
            user_id,
            clock_offset_ms,
            shift_id: None,
        })?;
        let _ = self.drain_outbox().await;
        Ok(self.store.pending()?.iter().any(|i| i.id == op_id))
    }

    /// SETTLE an open ticket into a paid order in the cashier's shift (a till
    /// action). Offline-first: the order is materialized server-side at replay,
    /// deduped on the ticket id. Returns true when still queued (offline). The
    /// cashier's settle-time discount/tip override the ticket's own.
    #[allow(clippy::too_many_arguments)]
    pub async fn settle_ticket(
        &self,
        ticket_id: String,
        shift_id: String,
        // The host passes payment-method IDS (like checkout); the core resolves the
        // raw method NAME the backend validates against.
        payment_method_id: String,
        amount_tendered_minor: Option<i64>,
        tip_minor: Option<i64>,
        tip_payment_method_id: Option<String>,
        discount_id: Option<String>,
        discount_type: Option<String>,
        // A FRACTION when `discount_type` is `percentage` (0.10 = 10%), minor
        // units when `fixed` — the same convention as `tax_rate`.
        discount_value: Option<f64>,
        // The member spending a balance on this bill, and which of its LINES
        // their rewards cover. Empty for a settle with no rewards, which is
        // almost all of them.
        loyalty_customer_id: Option<String>,
        loyalty_redemptions: Vec<checkout::CheckoutRedemption>,
    ) -> Result<Option<String>, CoreError> {
        let shift_uuid = uuid::Uuid::parse_str(&shift_id).map_err(|_| CoreError::Validation {
            field: "shift_id".into(),
            detail: "bad shift id".into(),
        })?;
        // Redeeming gives away goods against a balance any till can spend, so it
        // cannot be settled blind. Refused here rather than queued: a queued
        // redemption would be discovered to be unaffordable long after the
        // customer walked out with the item.
        if !loyalty_redemptions.is_empty()
            && !self.current_session().map(|s| s.online).unwrap_or(false)
        {
            return Err(CoreError::Offline {
                detail: "a reward can only be redeemed online".into(),
            });
        }
        let payment_method = checkout::raw_payment_method(&self.store, &payment_method_id)?
            .map(|p| p.name)
            .ok_or_else(|| CoreError::Validation {
                field: "payment_method".into(),
                detail: "unknown payment method".into(),
            })?;
        let tip_method = tip_payment_method_id
            .as_deref()
            .filter(|s| !s.is_empty())
            .and_then(|id| checkout::raw_payment_method(&self.store, id).ok().flatten())
            .map(|p| p.name);
        let mut request =
            madar_api::models::SettleOpenTicketRequest::new(payment_method, shift_uuid);
        request.amount_tendered = amount_tendered_minor.map(|v| Some(v as i32));
        request.tip_amount = tip_minor.filter(|v| *v > 0).map(|v| Some(v as i32));
        request.tip_payment_method = tip_method.map(Some);
        request.discount_id = discount_id
            .as_deref()
            .and_then(|s| uuid::Uuid::parse_str(s).ok())
            .map(Some);
        request.discount_type = discount_type.filter(|s| !s.trim().is_empty()).map(Some);
        request.discount_value = discount_value.map(Some);
        request.loyalty_customer_id = loyalty_customer_id
            .as_deref()
            .and_then(|s| uuid::Uuid::parse_str(s).ok())
            .map(Some);
        if !loyalty_redemptions.is_empty() {
            request.loyalty_redemptions = Some(
                loyalty_redemptions
                    .iter()
                    .map(|r| madar_api::models::LoyaltyRedemptionInput {
                        // A ticket names its LINE; the server resolves the index.
                        item_index: None,
                        ticket_line_id: r
                            .ticket_line_id
                            .as_deref()
                            .and_then(|s| uuid::Uuid::parse_str(s).ok())
                            .map(Some),
                        units: Some(Some(r.units)),
                    })
                    .collect(),
            );
        }
        let cmd = tickets::SettleTicketCommand {
            ticket_id: ticket_id.clone(),
            request,
        };

        let (user_id, clock_offset_ms) = self.outbox_meta();
        let op_id = format!("{ticket_id}:settle");
        self.store.enqueue(&store::NewOutboxOp {
            id: op_id.clone(),
            op_type: "settle_open_ticket".into(),
            idempotency_key: op_id.clone(),
            payload: serde_json::to_string(&cmd)?,
            event_at: self.corrected_now().to_rfc3339(),
            // Settle has TWO prerequisites: the ticket's fire must have landed (else
            // the backend 404s and — now that settle is non-idempotent — dead-letters
            // the paid sale), AND it attaches to the cashier's shift's open. Gate on
            // whichever is enqueued later (its ack implies the earlier one drained
            // first under FIFO). When the fire was rung on another device it isn't in
            // this outbox (live_seq_of → None) and is already server-side, so the
            // shift gate alone applies.
            depends_on_seq: [
                self.store.live_seq_of(&ticket_id)?,
                self.store.live_seq_of(&shift_id)?,
            ]
            .into_iter()
            .flatten()
            .max(),
            user_id,
            clock_offset_ms,
            shift_id: Some(shift_id.clone()),
        })?;
        let _ = self.drain_outbox().await;
        // The paid order the settle produced, when it acked — that is what a
        // receipt prints from. `None` means the settle is still queued: there
        // is no order yet, and inventing one would print a receipt for a sale
        // the server has not accepted.
        Ok(self.settled_order_id(op_id)?)
    }

    /// The paid order a settle produced, once it has acked.
    ///
    /// `settle_ticket` answers "is this still queued" and nothing else, and by
    /// the time it returns the ticket has left the board — so this is how a
    /// receipt gets printed after settling. `None` while the settle is still
    /// queued offline: there is no order yet, and inventing one would print a
    /// receipt for a sale the server has not accepted.
    pub fn settled_order_id(&self, settle_op_id: String) -> Result<Option<String>, CoreError> {
        Ok(self.store.id_map_get("order", &settle_op_id)?)
    }

    /// The branch's OPEN/READY open tickets (newest first). Server list (write-through
    /// cached, so it survives offline) PLUS any still-queued local fires overlaid as
    /// `status = "queued"` — offline-first visibility before the fire syncs.
    pub async fn list_open_tickets(&self) -> Result<Vec<tickets::TicketView>, CoreError> {
        use madar_api::apis::open_tickets_api as ot;
        let branch_id = self.session_branch_id()?;
        let server: Vec<madar_api::models::OpenTicketView> = match ot::list_open_tickets(
            &self.api.config(),
            ot::ListOpenTicketsParams {
                branch_id,
                status: None,
            },
        )
        .await
        {
            Ok(list) => {
                cache_views(&self.store, "cache:open_tickets", &list);
                list
            }
            Err(_) => cached_views(&self.store, "cache:open_tickets"),
        };
        let mut out: Vec<tickets::TicketView> = server
            .iter()
            .filter(|v| v.status != "settled" && v.status != "voided")
            .map(|v| tickets::to_view(v, false))
            .collect();
        // Ticket ids the waiter has already settled or voided OFFLINE (still queued).
        // Their not-yet-synced fire must NOT show as open — else a phantom ticket
        // lingers (and a cashier could settle a ticket already voided).
        let cleared: std::collections::HashSet<String> = self
            .store
            .pending()?
            .iter()
            .filter(|i| {
                matches!(
                    i.op_type.as_str(),
                    "settle_open_ticket" | "void_ticket" | "void_open_ticket"
                )
            })
            .filter_map(|i| {
                serde_json::from_str::<serde_json::Value>(&i.payload)
                    .ok()
                    .and_then(|v| {
                        v.get("ticket_id")
                            .and_then(|t| t.as_str())
                            .map(String::from)
                    })
            })
            .collect();
        // Overlay still-queued fires (a pending fire is never in the server list),
        // unless that ticket was already settled/voided offline. The waiter is the
        // current session (whoever is firing offline).
        let waiter = self
            .current_session()
            .map(|s| s.display_name)
            .filter(|s| !s.is_empty());
        for item in self
            .store
            .pending()?
            .iter()
            .filter(|i| i.op_type == "open_ticket")
        {
            if let Ok(cmd) = serde_json::from_str::<tickets::FireTicketCommand>(&item.payload) {
                if cleared.contains(&cmd.ticket_id) {
                    continue;
                }
                out.push(queued_ticket_view(&cmd, &item.event_at, waiter.clone()));
            }
        }
        Ok(out)
    }

    /// One open ticket by server id (the detail screen). Online; a queued (unsynced)
    /// ticket has no server id yet — read it from `list_open_tickets` instead.
    pub async fn get_ticket(&self, ticket_id: String) -> Result<tickets::TicketView, CoreError> {
        use madar_api::apis::open_tickets_api as ot;
        let v = ot::get_open_ticket(
            &self.api.config(),
            ot::GetOpenTicketParams { id: ticket_id },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(tickets::to_view(&v, false))
    }
}

// ── Kitchen Display System (station feed + bump) ─────────────────────────────
#[cfg_attr(feature = "uniffi-ffi", uniffi::export(async_runtime = "tokio"))]
impl MadarCore {
    /// The branch's kitchen stations (the KDS device-setup / chit-routing picker).
    /// Write-through cached so the picker survives offline.
    pub async fn kds_list_stations(&self) -> Result<Vec<kds::KdsStationView>, CoreError> {
        use madar_api::apis::kitchen_api as k;
        let branch_id = self.session_branch_id()?;
        let stations: Vec<madar_api::models::KitchenStation> =
            match k::list_stations(&self.api.config(), k::ListStationsParams { branch_id }).await {
                Ok(list) => {
                    cache_views(&self.store, "cache:kds_stations", &list);
                    list
                }
                Err(_) => cached_views(&self.store, "cache:kds_stations"),
            };
        Ok(stations.iter().map(kds::station_view).collect())
    }

    /// The KDS feed: outstanding kitchen tickets for the branch (optionally filtered
    /// to a `station_id` — tickets with pending work for it). Sorted oldest-first
    /// (rush to top), ready tickets last. Write-through cached per station so the
    /// board still shows the last snapshot after a reconnect.
    pub async fn kds_list(
        &self,
        station_id: Option<String>,
    ) -> Result<Vec<kds::KdsTicketView>, CoreError> {
        use madar_api::apis::kitchen_api as k;
        let branch_id = self.session_branch_id()?;
        let cache_key = match &station_id {
            Some(s) => format!("cache:kds:{s}"),
            None => "cache:kds:all".to_string(),
        };
        let feed: Vec<madar_api::models::KitchenTicketView> = match k::feed(
            &self.api.config(),
            k::FeedParams {
                branch_id,
                station_id,
            },
        )
        .await
        {
            Ok(list) => {
                cache_views(&self.store, &cache_key, &list);
                list
            }
            Err(_) => cached_views(&self.store, &cache_key),
        };
        let mut out: Vec<kds::KdsTicketView> = feed.iter().map(kds::ticket_view).collect();
        // Overlay LAN-projected fires not yet in the server feed (offline visibility);
        // prune any whose derived id now appears in the feed (they synced → server wins).
        let mut lan = lan_kds_read(&self.store);
        let synced: std::collections::HashSet<String> = out.iter().map(|t| t.id.clone()).collect();
        let before = lan.len();
        lan.retain(|t| !synced.contains(&t.id));
        if lan.len() != before {
            lan_kds_write(&self.store, &lan);
        }
        kds::overlay_lan_tickets(&mut out, lan);
        // Overlay still-pending (un-synced) bumps so the board shows the cook's
        // latest tap instantly — even offline, before the bump drains to the server.
        kds::overlay_pending_bumps(&mut out, &self.pending_bumps());
        kds::sort_feed(&mut out);
        Ok(out)
    }

    /// Bump a kitchen line (mark it done at its station). OUTBOX-FIRST (Phase E §2):
    /// the bump is written to the durable replay queue, then drained immediately —
    /// online-direct when connected, queued through a network blip otherwise. A
    /// ticket goes "ready" server-side once all its lines are bumped; the board
    /// reflects this tap instantly via the pending-bump overlay.
    pub async fn kds_bump(&self, item_id: String) -> Result<(), CoreError> {
        self.enqueue_bump(item_id, true).await
    }

    /// Un-bump a kitchen line (undo a mistaken bump). Same outbox-first path.
    pub async fn kds_unbump(&self, item_id: String) -> Result<(), CoreError> {
        self.enqueue_bump(item_id, false).await
    }

    /// The branch's active tills (the device-setup / Settings till picker). Write-
    /// through cached so the picker still works offline. Default till first.
    pub async fn list_tills(&self) -> Result<Vec<TillView>, CoreError> {
        use madar_api::apis::tills_api as t;
        let branch_id = self.session_branch_id()?;
        let tills: Vec<madar_api::models::Till> =
            match t::list_tills(&self.api.config(), t::ListTillsParams { branch_id }).await {
                Ok(list) => {
                    cache_views(&self.store, "cache:tills", &list);
                    list
                }
                Err(_) => cached_views(&self.store, "cache:tills"),
            };
        let mut out: Vec<TillView> = tills
            .iter()
            .filter(|t| t.is_active)
            .map(|t| TillView {
                id: t.id.to_string(),
                name: t.name.clone(),
                is_default: t.is_default,
                is_active: t.is_active,
            })
            .collect();
        out.sort_by(|a, b| b.is_default.cmp(&a.is_default).then(a.name.cmp(&b.name)));
        Ok(out)
    }
}

#[cfg_attr(feature = "uniffi-ffi", uniffi::export(async_runtime = "tokio"))]
impl MadarCore {
    /// The branch's delivery queue (newest first). `status` is a comma-separated
    /// wire filter (e.g. "received,confirmed"); `None` = all. Online-only.
    pub async fn list_delivery_orders(
        &self,
        status: Option<String>,
    ) -> Result<Vec<delivery::DeliveryOrderView>, CoreError> {
        use madar_api::apis::delivery_api as d;
        let branch = self.session_branch_id()?;
        let loc = self.current_locale();
        // Live when online (cached write-through, keyed by the status filter), else
        // the last-synced snapshot — the delivery board still shows offline.
        let key = format!("cache:delivery:{}", status.as_deref().unwrap_or("all"));
        if !self.current_session().map(|s| s.online).unwrap_or(false) {
            return Ok(cached_views(&self.store, &key));
        }
        match d::list_delivery_orders(
            &self.api.config(),
            d::ListDeliveryOrdersParams {
                branch_id: branch,
                status,
                limit: Some(200),
            },
        )
        .await
        {
            Ok(orders) => {
                let views: Vec<_> = orders
                    .iter()
                    .map(|o| delivery::order_view(o, &loc))
                    .collect();
                cache_views(&self.store, &key, &views);
                Ok(views)
            }
            Err(_) => Ok(cached_views(&self.store, &key)),
        }
    }

    /// A single delivery order by id.
    pub async fn delivery_order_detail(
        &self,
        id: String,
    ) -> Result<delivery::DeliveryOrderView, CoreError> {
        use madar_api::apis::delivery_api as d;
        let loc = self.current_locale();
        let o = d::get_delivery_order(&self.api.config(), d::GetDeliveryOrderParams { id })
            .await
            .map_err(net::map_api_error)?;
        Ok(delivery::order_view(&o, &loc))
    }

    /// Set a delivery order's status to an explicit wire value.
    pub async fn delivery_set_status(
        &self,
        id: String,
        status: String,
    ) -> Result<delivery::DeliveryOrderView, CoreError> {
        use madar_api::apis::delivery_api as d;
        let loc = self.current_locale();
        let o = d::set_status(
            &self.api.config(),
            d::SetStatusParams {
                id,
                status_input: madar_api::models::StatusInput::new(status),
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(delivery::order_view(&o, &loc))
    }

    /// Advance one step in the lifecycle from `current` (received→confirmed→…→
    /// delivered). Errors if there's no further forward step.
    pub async fn delivery_advance_status(
        &self,
        id: String,
        current: String,
    ) -> Result<delivery::DeliveryOrderView, CoreError> {
        let next = delivery::next_status(&current).ok_or_else(|| CoreError::Validation {
            field: "status".into(),
            detail: "no further status".into(),
        })?;
        self.delivery_set_status(id, next.to_string()).await
    }

    /// Set the per-order extra prep time (non-negative multiple of 5 minutes).
    pub async fn delivery_set_prep_time(
        &self,
        id: String,
        extra_minutes: i32,
    ) -> Result<delivery::DeliveryOrderView, CoreError> {
        use madar_api::apis::delivery_api as d;
        let loc = self.current_locale();
        let o = d::set_prep_time(
            &self.api.config(),
            d::SetPrepTimeParams {
                id,
                prep_time_input: madar_api::models::PrepTimeInput::new(extra_minutes),
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(delivery::order_view(&o, &loc))
    }

    /// Cancel a delivery order. `restore_inventory = false` means the food was
    /// made and is wasted (the frozen plan is deducted + logged as waste).
    pub async fn delivery_cancel(
        &self,
        id: String,
        reason: Option<String>,
        restore_inventory: bool,
    ) -> Result<delivery::DeliveryOrderView, CoreError> {
        use madar_api::apis::delivery_api as d;
        let loc = self.current_locale();
        let mut input = madar_api::models::CancelInput::new();
        input.reason = Some(reason.filter(|s| !s.trim().is_empty()));
        input.restore_inventory = Some(restore_inventory);
        let o = d::cancel_delivery_order(
            &self.api.config(),
            d::CancelDeliveryOrderParams {
                id,
                cancel_input: input,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(delivery::order_view(&o, &loc))
    }

    /// Finalize a delivery order into a real completed sale on the current open
    /// shift — replays the frozen snapshot. `payment_method_id` resolves to the
    /// raw wire method. Returns the new order id/ref + any oversold warnings.
    pub async fn delivery_finalize(
        &self,
        id: String,
        payment_method_id: String,
    ) -> Result<delivery::DeliveryFinalizeView, CoreError> {
        use madar_api::apis::delivery_api as d;
        let raw =
            checkout::raw_payment_method(&self.store, &payment_method_id)?.ok_or_else(|| {
                CoreError::Validation {
                    field: "payment_method".into(),
                    detail: "unknown payment method".into(),
                }
            })?;
        let shift = shift::current(&self.store)?
            .filter(|s| s.is_open)
            .ok_or_else(|| CoreError::Validation {
                field: "shift".into(),
                detail: "no open shift".into(),
            })?;
        let shift_uuid = uuid::Uuid::parse_str(&shift.id).map_err(|_| CoreError::Validation {
            field: "shift_id".into(),
            detail: "bad shift id".into(),
        })?;
        let input = madar_api::models::FinalizeInput::new(raw.name, shift_uuid);
        let res = d::finalize_delivery_order(
            &self.api.config(),
            d::FinalizeDeliveryOrderParams {
                id,
                finalize_input: input,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(delivery::DeliveryFinalizeView {
            order_id: res.order_id.to_string(),
            order_ref: res.order_ref.flatten().filter(|s| !s.is_empty()),
            warnings: res.warnings,
        })
    }

    /// The branch's delivery settings + accepting overrides.
    pub async fn delivery_settings(&self) -> Result<delivery::DeliverySettingsView, CoreError> {
        use madar_api::apis::delivery_api as d;
        let branch = self.session_branch_id()?;
        let s = d::get_branch_settings(
            &self.api.config(),
            d::GetBranchSettingsParams { branch_id: branch },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(delivery::settings_view(&s))
    }

    /// Set a channel's accepting override. `channel` = "in_mall"/"outside",
    /// `mode` = "auto"/"open"/"closed". 409 if opening a dashboard-disabled channel.
    pub async fn delivery_set_accepting(
        &self,
        channel: String,
        mode: String,
    ) -> Result<delivery::DeliverySettingsView, CoreError> {
        use madar_api::apis::delivery_api as d;
        let branch = self.session_branch_id()?;
        let branch_uuid = uuid::Uuid::parse_str(&branch).map_err(|_| CoreError::Validation {
            field: "branch_id".into(),
            detail: "bad branch id".into(),
        })?;
        let input = madar_api::models::AcceptingInput::new(branch_uuid, channel, mode);
        let s = d::set_accepting(
            &self.api.config(),
            d::SetAcceptingParams {
                accepting_input: input,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(delivery::settings_view(&s))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greet_includes_version() {
        let msg = greet("Teller".into());
        assert!(msg.contains("Teller"));
        assert!(msg.contains(&core_version()));
    }

    #[test]
    fn backoff_is_exponential_capped_and_jittered() {
        // BASE·2^(n-1): 2s, 4s, 8s … then capped at 5min.
        assert!((2_000..3_000).contains(&compute_backoff_ms(1, 7)));
        assert!((4_000..5_000).contains(&compute_backoff_ms(2, 7)));
        assert!((8_000..9_000).contains(&compute_backoff_ms(3, 7)));
        // Far out it saturates at the 5-minute cap (never overflows).
        assert_eq!(compute_backoff_ms(40, 7), K_MAX_BACKOFF_MS);
        assert_eq!(compute_backoff_ms(100, 1), K_MAX_BACKOFF_MS);
        // Jitter spreads two different items apart at the same attempt.
        assert_ne!(compute_backoff_ms(1, 1), compute_backoff_ms(1, 999));
    }

    #[test]
    fn backoff_edge_cases_clamp_attempts_and_stay_in_band() {
        // attempts <= 0 are clamped to the first step (shift 0) → BASE band.
        assert!((2_000..3_000).contains(&compute_backoff_ms(0, 7)));
        assert!((2_000..3_000).contains(&compute_backoff_ms(-5, 7)));
        // Jitter is bounded to [0, 1000) and added on top of the (capped) base.
        let j = compute_backoff_ms(1, 7) - K_BASE_BACKOFF_MS;
        assert!((0..1000).contains(&j));
        // Same (attempts, seq) is deterministic — no RNG.
        assert_eq!(compute_backoff_ms(3, 42), compute_backoff_ms(3, 42));
        // The capped value never exceeds the max even with jitter added.
        assert!(compute_backoff_ms(8, 999_999) <= K_MAX_BACKOFF_MS);
    }

    #[test]
    fn rebase_dopt_shifts_a_present_timestamp_by_the_delta() {
        let base = chrono::DateTime::parse_from_rfc3339("2026-06-20T12:00:00+00:00").unwrap();
        let mut field = Some(Some(base));
        rebase_dopt(&mut field, 60_000); // +1 minute
        assert_eq!(field, Some(Some(base + chrono::Duration::minutes(1))));
        // A negative delta walks it back.
        rebase_dopt(&mut field, -120_000); // -2 minutes from the new value
        assert_eq!(field, Some(Some(base - chrono::Duration::minutes(1))));
    }

    #[test]
    fn rebase_dopt_zero_delta_is_a_noop() {
        let base = chrono::DateTime::parse_from_rfc3339("2026-06-20T12:00:00+00:00").unwrap();
        let mut field = Some(Some(base));
        rebase_dopt(&mut field, 0);
        assert_eq!(field, Some(Some(base)));
    }

    #[test]
    fn rebase_dopt_tolerates_absent_double_option_levels() {
        // Outer None (field omitted) — must not panic, stays None.
        let mut none: Option<Option<chrono::DateTime<chrono::FixedOffset>>> = None;
        rebase_dopt(&mut none, 60_000);
        assert_eq!(none, None);
        // Inner None (explicit null) — stays Some(None).
        let mut inner_none: Option<Option<chrono::DateTime<chrono::FixedOffset>>> = Some(None);
        rebase_dopt(&mut inner_none, 60_000);
        assert_eq!(inner_none, Some(None));
    }

    #[test]
    fn clock_skew_minutes_divides_seconds_truncating_toward_zero() {
        let core = MadarCore::from_env().unwrap();
        // Default is 0.
        assert_eq!(core.clock_skew_minutes(), 0);
        // 125s → 2 min (truncated).
        core.clock_skew_secs
            .store(125, std::sync::atomic::Ordering::Relaxed);
        assert_eq!(core.clock_skew_minutes(), 2);
        // Negative skew truncates toward zero too: -125s → -2 min.
        core.clock_skew_secs
            .store(-125, std::sync::atomic::Ordering::Relaxed);
        assert_eq!(core.clock_skew_minutes(), -2);
        // Under a minute → 0.
        core.clock_skew_secs
            .store(59, std::sync::atomic::Ordering::Relaxed);
        assert_eq!(core.clock_skew_minutes(), 0);
    }

    #[test]
    fn sync_status_reflects_outbox_counts_and_default_flags() {
        // Signed out, empty outbox → all zero, offline, not auth-paused.
        let core = MadarCore::from_env().unwrap();
        let s = core.sync_status().unwrap();
        assert_eq!(
            s,
            SyncStatusView {
                pending: 0,
                failed: 0,
                blocked: 0,
                online: false,
                auth_paused: false
            }
        );
    }

    #[test]
    fn classify_send_maps_every_status_correctly() {
        let dead = |o: &SendOutcome| matches!(o, SendOutcome::Dead(_));
        let ack = |o: &SendOutcome| matches!(o, SendOutcome::Acked(_));
        let retry = |o: &SendOutcome| matches!(o, SendOutcome::Retry(_));

        // Connectivity / auth / server-error.
        assert!(matches!(
            classify_send(CoreError::Offline { detail: "x".into() }, Idem::No),
            SendOutcome::Offline
        ));
        assert!(matches!(
            classify_send(CoreError::Unauthenticated { detail: "x".into() }, Idem::No),
            SendOutcome::AuthExpired
        ));
        assert!(retry(&classify_send(
            CoreError::Transient {
                detail: "503".into()
            },
            Idem::No
        )));
        // Permanent validation / permission → dead.
        assert!(dead(&classify_send(
            CoreError::Validation {
                field: "".into(),
                detail: "bad".into()
            },
            Idem::No
        )));
        assert!(dead(&classify_send(
            CoreError::Forbidden {
                resource: "api".into(),
                action: "no".into()
            },
            Idem::No
        )));
        // 409: order/open NOT recorded → dead; void/close already-applied → ack.
        assert!(dead(&classify_send(srv(409), Idem::No)));
        assert!(ack(&classify_send(srv(409), Idem::Yes)));
        assert!(ack(&classify_send(srv(409), Idem::VoidIdem)));
        // 404: idempotent gone → ack; but a VOID 404 (order never landed) → dead.
        assert!(ack(&classify_send(srv(404), Idem::Yes)));
        assert!(dead(&classify_send(srv(404), Idem::VoidIdem)));
    }

    fn srv(status: u16) -> CoreError {
        CoreError::Server {
            status,
            code: "x".into(),
            detail: "boom".into(),
        }
    }

    #[test]
    fn replay_backend_object_rejects_captive_portal_and_non_objects() {
        // A Wi-Fi login page served as 200 text/html — NOT our backend. The whole
        // point: this must NOT be acked, or a queued sale is silently lost.
        assert!(
            replay_backend_object("<!DOCTYPE html><html><body>Sign in to WiFi</body></html>")
                .is_none()
        );
        // Empty body and whitespace (some proxies return 200 with no payload).
        assert!(replay_backend_object("").is_none());
        assert!(replay_backend_object("   ").is_none());
        // Bare JSON array / scalar / string are valid JSON but not our object shape.
        assert!(replay_backend_object("[1,2,3]").is_none());
        assert!(replay_backend_object("42").is_none());
        assert!(replay_backend_object("\"ok\"").is_none());
        // A genuine backend object passes (even an empty one — shape, not contents).
        assert!(replay_backend_object("{}").is_some());
        let order = replay_backend_object(r#"{"id":"abc-123","total_amount":1500}"#).unwrap();
        assert_eq!(order.get("id").and_then(|v| v.as_str()), Some("abc-123"));
    }

    #[test]
    fn cache_views_roundtrips_and_is_corruption_safe() {
        #[derive(serde::Serialize, serde::Deserialize, PartialEq, Debug, Clone)]
        struct Row {
            id: i64,
            name: String,
        }
        let store = store::Store::open("").unwrap();
        // Nothing cached yet → empty (the cold-start / never-synced case).
        assert!(cached_views::<Row>(&store, "cache:t").is_empty());
        // Write-through, then read back the exact snapshot.
        let rows = vec![
            Row {
                id: 1,
                name: "a".into(),
            },
            Row {
                id: 2,
                name: "b".into(),
            },
        ];
        cache_views(&store, "cache:t", &rows);
        assert_eq!(cached_views::<Row>(&store, "cache:t"), rows);
        // A re-sync overwrites (the snapshot is the latest, not appended).
        let fewer = vec![Row {
            id: 9,
            name: "z".into(),
        }];
        cache_views(&store, "cache:t", &fewer);
        assert_eq!(cached_views::<Row>(&store, "cache:t"), fewer);
        // A corrupt/foreign payload reads back as empty rather than erroring the read.
        store.kv_put("cache:bad", "{not json").unwrap();
        assert!(cached_views::<Row>(&store, "cache:bad").is_empty());
    }

    #[test]
    fn diag_ring_buffer_caps_and_orders_newest_first() {
        let core = MadarCore::from_env().unwrap();
        assert!(core.recent_logs().is_empty());
        for i in 0..250 {
            core.push_diag("warn", format!("m{i}"));
        }
        let logs = core.recent_logs();
        assert_eq!(logs.len(), 200); // capped at 200
        assert_eq!(logs[0].message, "m249"); // newest first
        assert_eq!(logs[0].level, "warn");
        core.clear_logs();
        assert!(core.recent_logs().is_empty());
    }

    #[test]
    fn catalog_snapshot_caches_until_invalidated_and_rekeys_on_locale() {
        let item_json = |name: &str, name_ar: &str| {
            format!(
                r#"[{{"base_price":4200,"created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z",
                 "id":"00000000-0000-0000-0000-0000000000a2","org_id":"00000000-0000-0000-0000-0000000000ff",
                 "is_active":true,"name":"{name}","name_translations":{{"en":"{name}","ar":"{name_ar}"}},
                 "description_translations":{{}},"addon_slots":[],"allowed_addon_ids":[],
                 "optional_fields":[],"recipes":[],"sizes":[]}}]"#
            )
        };
        let core = MadarCore::from_env().unwrap();
        core.store
            .kv_put(menu::K_MENU_ITEMS, &item_json("Espresso", "اسبريسو"))
            .unwrap();
        assert_eq!(core.list_menu_items().unwrap()[0].name, "Espresso");
        // A raw kv rewrite WITHOUT invalidation keeps serving the snapshot —
        // that's the cache working (only `refresh_catalog` writes these keys
        // in production, and it invalidates right after).
        core.store
            .kv_put(menu::K_MENU_ITEMS, &item_json("Latte", "لاتيه"))
            .unwrap();
        assert_eq!(core.list_menu_items().unwrap()[0].name, "Espresso");
        core.invalidate_catalog_cache();
        assert_eq!(core.list_menu_items().unwrap()[0].name, "Latte");
        // A locale switch re-projects lazily — no explicit invalidation needed.
        core.set_locale("ar".into());
        assert_eq!(core.list_menu_items().unwrap()[0].name, "لاتيه");
    }

    #[test]
    fn core_reads_env_config() {
        let core = MadarCore::from_env().unwrap();
        assert!(core.base_url().starts_with("http"));
        assert!(!core.environment().is_empty());
        assert_eq!(core.pending_outbox_count().unwrap(), 0);
    }

    #[test]
    fn surface_version_is_pinned() {
        // 1: realtime SSE + AppRoute payload variants. 2: core-owned device config.
        // 3: LAN offline relay surface. 4: core-driven realtime (start_realtime +
        // RealtimePlayer). Every breaking FFI change MUST bump this and this assertion.
        assert_eq!(ffi_surface_version(), 4);
    }

    #[test]
    fn mirror_replay_op_enqueues_a_dedup_keyed_backup() {
        let store = store::Store::open("").unwrap();
        // A received LAN bump → mirrored into our outbox as a `lan_mirror` backup,
        // attributed to the ORIGINAL teller, keyed for server-side dedup.
        let env =
            serde_json::json!({ "op": "bump_kitchen_item", "teller_id": "t1", "item_id": "k9" })
                .to_string();
        mirror_replay_op(&store, &env);
        let pending = store.pending().unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].op_type, "lan_mirror");
        assert_eq!(pending[0].payload, env, "the envelope posts verbatim");
        assert_eq!(
            pending[0].user_id.as_deref(),
            Some("t1"),
            "original actor preserved"
        );
        // A re-received duplicate (gossip / both paths) collapses to one row.
        mirror_replay_op(&store, &env);
        assert_eq!(
            store.pending().unwrap().len(),
            1,
            "idempotent on the op handle"
        );
        // A fire envelope keys on its request idempotency_key.
        let fire = serde_json::json!({
            "op": "fire_open_ticket", "teller_id": "w2",
            "request": { "idempotency_key": "tic-1", "items": [] }
        })
        .to_string();
        mirror_replay_op(&store, &fire);
        assert_eq!(
            store.pending().unwrap().len(),
            2,
            "distinct op → distinct backup"
        );
    }

    #[test]
    fn mirror_kitchen_toggle_keeps_the_latest_tap() {
        let store = store::Store::open("").unwrap();
        let bump =
            serde_json::json!({ "op": "bump_kitchen_item", "teller_id": "t1", "item_id": "k9" })
                .to_string();
        let unbump =
            serde_json::json!({ "op": "unbump_kitchen_item", "teller_id": "t1", "item_id": "k9" })
                .to_string();
        // bump → unbump → bump on ONE line collapses to a single line-scoped backup
        // that ends on the LATEST tap (bump) — NOT the first bump with the unbump still
        // queued behind it (which would replay a stale state if the device died).
        mirror_replay_op(&store, &bump);
        mirror_replay_op(&store, &unbump);
        mirror_replay_op(&store, &bump);
        let pending = store.pending().unwrap();
        assert_eq!(pending.len(), 1, "one line-scoped backup, not three");
        assert_eq!(pending[0].payload, bump, "backup reflects the LATEST tap");
        // A different line keeps its own backup.
        let other =
            serde_json::json!({ "op": "bump_kitchen_item", "teller_id": "t1", "item_id": "k7" })
                .to_string();
        mirror_replay_op(&store, &other);
        assert_eq!(
            store.pending().unwrap().len(),
            2,
            "a different line → its own backup"
        );
    }

    #[tokio::test]
    async fn image_sync_survives_an_unreachable_host() {
        let dir = std::env::temp_dir().join(format!("madar-img-sync-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let core = MadarCore::new(MadarConfig {
            base_url: "http://127.0.0.1:1".into(), // nothing listening
            environment: "dev".into(),
            db_path: dir.join("madar.db").to_string_lossy().into_owned(),
            locale: "en".into(),
        })
        .unwrap();
        core.store
            .kv_put(checkout::KEY_ORG_LOGO_URL, "http://127.0.0.1:1/logo.png")
            .unwrap();
        // Every download fails (connect refused) — the image phase must still
        // return cleanly (it can never fail the catalog) with nothing cached.
        core.sync_catalog_images().await;
        assert_eq!(core.org_logo_local_path(), None);
        let _ = std::fs::remove_dir_all(dir);
    }

    #[tokio::test]
    async fn step_animations_download_only_what_the_menu_uses() {
        let dir = std::env::temp_dir().join(format!("madar-anim-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let core = MadarCore::new(MadarConfig {
            base_url: "http://127.0.0.1:1".into(), // nothing listening
            environment: "dev".into(),
            db_path: dir.join("madar.db").to_string_lossy().into_owned(),
            locale: "en".into(),
        })
        .unwrap();
        // One item using one preset step and one written step.
        core.store
            .kv_put(
                menu::K_MENU_ITEMS,
                r#"[{
                  "id": "00000000-0000-0000-0000-0000000000a1",
                  "org_id": "00000000-0000-0000-0000-000000000001",
                  "name": "Latte", "name_translations": {}, "base_price": 5000,
                  "is_active": true, "allowed_addon_ids": [],
                  "recipe_steps": [
                    {"kind": "preset", "name": "Steam milk", "name_ar": "",
                     "animation_url": "/static/step-animations/steam_milk.json?v=abc"},
                    {"kind": "custom", "name": "Serve", "name_ar": "", "animation_url": null}
                  ]
                }]"#,
            )
            .unwrap();

        // The referenced animation, made absolute against the API base — and
        // ONLY that one. The library the server holds is never enumerated here.
        let urls = core.step_animation_urls();
        assert_eq!(urls.len(), 1, "a written step pulls nothing");
        assert!(urls.contains("http://127.0.0.1:1/static/step-animations/steam_milk.json?v=abc"));

        // Every download fails (connect refused): the phase still returns
        // cleanly and the step simply has no local file to draw.
        core.sync_step_animations().await;
        let items = core.list_menu_items().unwrap();
        assert_eq!(items[0].recipe_steps[0].local_animation_path, None);

        // A file that IS cached resolves onto the projected step, and the
        // animation cache is separate from the image one, so evicting the
        // orphans of either never deletes the other's files.
        let url = "http://127.0.0.1:1/static/step-animations/steam_milk.json?v=abc";
        core.animations
            .store(url, br#"{"v":"5.7.4","layers":[]}"#)
            .unwrap();
        core.images
            .store("http://127.0.0.1:1/x.png", b"photo")
            .unwrap();
        core.invalidate_catalog_cache();
        let items = core.list_menu_items().unwrap();
        assert!(
            items[0].recipe_steps[0]
                .local_animation_path
                .as_deref()
                .is_some_and(|p| p.ends_with(".json")),
            "the cached animation resolves to a local path"
        );
        assert_eq!(items[0].recipe_steps[1].local_animation_path, None);

        // Re-syncing with the SAME menu keeps it; the image store is untouched.
        core.sync_step_animations().await;
        assert!(core.animations.is_cached(url), "still referenced, so kept");
        assert!(core.images.is_cached("http://127.0.0.1:1/x.png"));

        // Drop the step from the menu: the next sync evicts its animation.
        core.store
            .kv_put(
                menu::K_MENU_ITEMS,
                r#"[{
                  "id": "00000000-0000-0000-0000-0000000000a1",
                  "org_id": "00000000-0000-0000-0000-000000000001",
                  "name": "Latte", "name_translations": {}, "base_price": 5000,
                  "is_active": true, "allowed_addon_ids": [], "recipe_steps": []
                }]"#,
            )
            .unwrap();
        core.invalidate_catalog_cache();
        core.sync_step_animations().await;
        assert!(
            !core.animations.is_cached(url),
            "unreferenced animations are swept"
        );
        assert!(
            core.images.is_cached("http://127.0.0.1:1/x.png"),
            "the image cache is its own"
        );
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn set_locale_changes_strings_and_rtl_at_runtime() {
        let core = MadarCore::from_env().unwrap();
        core.set_locale("en".into());
        assert_eq!(core.tr("login.sign_in".into()), "Sign in");
        assert!(!core.is_rtl());
        core.set_locale("ar".into());
        assert_eq!(core.tr("login.sign_in".into()), "تسجيل الدخول");
        assert!(core.is_rtl());
        assert_eq!(core.locale(), "ar");
    }

    /// sign_in falls back to an offline unlock when the network is unreachable
    /// and a cached bundle holds the teller's PIN. Points the core at a dead
    /// port so the online `login` fails fast with `Offline`.
    #[tokio::test]
    async fn sign_in_falls_back_to_offline_unlock_when_network_down() {
        use argon2::password_hash::SaltString;
        use argon2::{Argon2, PasswordHasher};

        let core = MadarCore::new(MadarConfig {
            base_url: "http://127.0.0.1:1".into(), // nothing listening → connect refused
            environment: "dev".into(),
            db_path: String::new(),
            locale: "en".into(),
        })
        .unwrap();

        // Seed the org bundle the offline unlock verifies against.
        let salt = SaltString::encode_b64(b"madar-test-salt").unwrap();
        let phc = Argon2::default()
            .hash_password(b"1234", &salt)
            .unwrap()
            .to_string();
        let bundle = serde_json::json!({
            "org_id": "00000000-0000-0000-0000-0000000000aa",
            "generated_at": "2026-06-19T10:00:00Z",
            "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
            "tellers": [{
                "user_id": "00000000-0000-0000-0000-0000000000bb",
                "name": "Sara", "role": "teller", "is_active": true,
                "offline_pin_hash": phc,
            }]
        });
        core.store
            .kv_put(session::BUNDLE_KEY, &bundle.to_string())
            .unwrap();
        core.store
            .kv_put(session::ORG_CONFIG_KEY, r#"{"org_id":"00000000-0000-0000-0000-0000000000aa","currency_code":"EGP","tax_rate":0.14}"#)
            .unwrap();

        let req = session::LoginRequest {
            mode: session::LoginMode::Pin,
            name: Some("Sara".into()),
            pin: Some("1234".into()),
            branch_id: Some("00000000-0000-0000-0000-000000000001".into()),
            email: None,
            password: None,
            org_id: None,
        };
        let snap = core
            .sign_in(req)
            .await
            .expect("offline fallback should sign in");
        assert_eq!(snap.display_name, "Sara");
        assert!(!snap.online);
        assert!(core.is_authenticated());

        // A wrong PIN offline (still network-down) must NOT sign in.
        let bad = session::LoginRequest {
            pin: Some("0000".into()),
            ..session::LoginRequest {
                mode: session::LoginMode::Pin,
                name: Some("Sara".into()),
                pin: None,
                branch_id: Some("00000000-0000-0000-0000-000000000001".into()),
                email: None,
                password: None,
                org_id: None,
            }
        };
        assert!(core.sign_in(bad).await.is_err());
    }

    /// The offline banner must NOT flap on a transient probe failure (a waking radio
    /// / DNS-TLS-not-ready right after a resume or rotation errs the first /health
    /// ping, then recovers). A single failed probe holds the banner; only two
    /// consecutive UNCONFIRMED failures (empty outbox → no real send can prove it)
    /// drop it, and a confirmed reachability resets the streak.
    #[tokio::test]
    async fn refresh_connectivity_debounces_transient_probe_failures() {
        use argon2::password_hash::SaltString;
        use argon2::{Argon2, PasswordHasher};

        let core = MadarCore::new(MadarConfig {
            base_url: "http://127.0.0.1:1".into(), // nothing listening → every ping errs
            environment: "dev".into(),
            db_path: String::new(),
            locale: "en".into(),
        })
        .unwrap();

        // Establish a session via the offline unlock (no bearer, empty outbox).
        let salt = SaltString::encode_b64(b"madar-test-salt").unwrap();
        let phc = Argon2::default()
            .hash_password(b"1234", &salt)
            .unwrap()
            .to_string();
        let bundle = serde_json::json!({
            "org_id": "00000000-0000-0000-0000-0000000000aa",
            "generated_at": "2026-06-19T10:00:00Z",
            "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
            "tellers": [{
                "user_id": "00000000-0000-0000-0000-0000000000bb",
                "name": "Sara", "role": "teller", "is_active": true,
                "offline_pin_hash": phc,
            }]
        });
        core.store
            .kv_put(session::BUNDLE_KEY, &bundle.to_string())
            .unwrap();
        core.store
            .kv_put(session::ORG_CONFIG_KEY, r#"{"org_id":"00000000-0000-0000-0000-0000000000aa","currency_code":"EGP","tax_rate":0.14}"#)
            .unwrap();
        core.sign_in(session::LoginRequest {
            mode: session::LoginMode::Pin,
            name: Some("Sara".into()),
            pin: Some("1234".into()),
            branch_id: Some("00000000-0000-0000-0000-000000000001".into()),
            email: None,
            password: None,
            org_id: None,
        })
        .await
        .expect("offline sign-in");

        let online = || core.current_session().map(|s| s.online).unwrap_or(false);

        // Simulate having been online before the transient blip.
        core.set_online(true);
        assert!(online());

        // One failed probe (empty outbox, no bearer to flush) — banner HOLDS.
        assert!(
            core.refresh_connectivity().await,
            "a single blip keeps us online"
        );
        assert!(online(), "still online after one failed probe");

        // A second consecutive failed probe confirms we're genuinely offline.
        assert!(
            !core.refresh_connectivity().await,
            "two consecutive blips → offline"
        );
        assert!(!online());

        // A confirmed reachability resets the streak → it again tolerates one blip.
        core.set_online(true);
        assert!(
            core.refresh_connectivity().await,
            "streak reset → one blip tolerated again"
        );
        assert!(online());
    }
}

/// Routing-lifecycle tests — the class of bug behind the open-shift "bounce".
/// These poke the private session/store (same-crate) to drive `app_route`
/// through every transition without a network.
#[cfg(test)]
mod lifecycle_tests {
    use super::*;

    fn teller_session(user_id: &str, branch: Option<&str>) -> session::SessionState {
        session::SessionState {
            snapshot: session::SessionSnapshot {
                user_id: user_id.into(),
                display_name: "Sara".into(),
                role: "teller".into(),
                org_id: Some("org-1".into()),
                branch_id: branch.map(Into::into),
                currency_code: "EGP".into(),
                tax_rate: 0.14,
                tax_inclusive: false,
                service_charge_rate: 0.0,
                service_charge_taxable: true,
                require_table_for_orders: false,
                online: true,
                permissions_loaded: true,
            },
            permissions: vec![],
            token: None,
        }
    }

    fn kitchen_session(user_id: &str, branch: Option<&str>) -> session::SessionState {
        let mut s = teller_session(user_id, branch);
        s.snapshot.role = "kitchen".into();
        s
    }

    fn set_session(core: &MadarCore, state: Option<session::SessionState>) {
        *core.session.write().unwrap_or_else(|e| e.into_inner()) = state;
    }

    fn seed_shift(core: &MadarCore, teller: uuid::Uuid, status: &str) {
        let _ = seed_shift_returning_id(core, teller, status);
    }

    fn seed_shift_returning_id(core: &MadarCore, teller: uuid::Uuid, status: &str) -> String {
        let id = uuid::Uuid::new_v4();
        let s = madar_api::models::Shift {
            id,
            branch_id: uuid::Uuid::new_v4(),
            teller_id: teller,
            teller_name: "Sara".into(),
            opening_cash: 50000,
            status: status.into(),
            ..Default::default()
        };
        shift::save(&core.store, &s).unwrap();
        id.to_string()
    }

    fn enqueue_open_shift(core: &MadarCore, id: &str) {
        core.store
            .enqueue(&store::NewOutboxOp {
                id: id.into(),
                op_type: "open_shift".into(),
                idempotency_key: id.into(),
                payload: "{}".into(),
                event_at: "2026-06-20T12:00:00+00:00".into(),
                shift_id: Some(id.into()),
                ..Default::default()
            })
            .unwrap();
    }

    fn enqueue_close_shift(core: &MadarCore, shift_id: &str) {
        let id = format!("{shift_id}:close");
        core.store
            .enqueue(&store::NewOutboxOp {
                id: id.clone(),
                op_type: "close_shift".into(),
                idempotency_key: id,
                payload: "{}".into(),
                event_at: "2026-06-20T18:00:00+00:00".into(),
                shift_id: Some(shift_id.into()),
                ..Default::default()
            })
            .unwrap();
    }

    /// A real signed-in core pinned OFFLINE (dead url), against a cached bundle —
    /// for driving the genuine open/close/checkout FFI paths with no network.
    /// Parking a cart used to queue a `park_held_order` op that no drain arm
    /// could send, so every park wrote a permanent stuck row into the sync
    /// screen's list. A parked draft is device-local: it must queue NOTHING.
    #[tokio::test]
    async fn parking_a_cart_queues_nothing_and_leaves_no_stuck_row() {
        let core = signed_in_offline_core().await;
        let before = core.store.pending().unwrap().len();

        // A cart with something in it — parking refuses an empty one.
        cart::set_cart_payload(
            &core.store,
            &serde_json::json!({
                "lines": [{
                    "key": "k1", "item_id": "00000000-0000-0000-0000-0000000000c1",
                    "name": "Latte", "unit_price_minor": 5000, "qty": 1,
                    "addons": [], "optionals": []
                }]
            }),
        )
        .unwrap();
        core.hold_cart_on_table("Table 5".into(), None, None, None)
            .unwrap();

        assert_eq!(
            core.store.pending().unwrap().len(),
            before,
            "a parked draft is device-local and must queue no op"
        );
        assert_eq!(
            core.store.dead_count().unwrap(),
            0,
            "and therefore cannot leave a stuck row behind"
        );
    }

    /// EVERY hold operation is device-local, not just the park.
    ///
    /// A hold is this till's own parked cart. Nothing about it belongs to the
    /// server — the `held_orders` table it used to sync to is gone — and the
    /// only thing that ever reaches the backend is the ORDER it becomes at
    /// checkout, through the ordinary create path.
    ///
    /// Parking alone was pinned. Assigning a table, resuming, releasing,
    /// discarding and completing were not, and each of them writes to the same
    /// mirror; any one of them queuing an op would put a permanent stuck row
    /// in the sync screen that no drain arm could ever clear.
    #[tokio::test]
    async fn no_hold_operation_ever_queues_anything() {
        let core = signed_in_offline_core().await;
        let before = core.store.pending().unwrap().len();

        cart::set_cart_payload(
            &core.store,
            &serde_json::json!({
                "lines": [{
                    "key": "k1", "item_id": "00000000-0000-0000-0000-0000000000c1",
                    "name": "Latte", "unit_price_minor": 5000, "qty": 1,
                    "addons": [], "optionals": []
                }]
            }),
        )
        .unwrap();
        core.hold_cart_on_table("Table 5".into(), None, None, None)
            .unwrap();

        let id = core
            .list_drafts()
            .unwrap()
            .first()
            .expect("the draft exists")
            .id
            .clone();

        // Every remaining verb, in the order a teller would reach them.
        core.assign_draft_table(id.clone(), None).unwrap();
        core.restore_draft(id.clone()).unwrap();
        core.release_draft(id.clone()).unwrap();
        core.restore_draft(id.clone()).unwrap();
        core.complete_draft(id.clone(), None).unwrap();

        assert_eq!(
            core.store.pending().unwrap().len(),
            before,
            "a hold with no table is device-local from park to checkout — \
             nothing at all is queued"
        );
        assert_eq!(
            core.store.dead_count().unwrap(),
            0,
            "so no hold can leave a stuck row nobody can clear"
        );
    }

    /// Discarding is device-local too, and it is the other way a hold ends.
    #[tokio::test]
    async fn discarding_a_hold_queues_nothing_either() {
        let core = signed_in_offline_core().await;
        let before = core.store.pending().unwrap().len();
        cart::set_cart_payload(
            &core.store,
            &serde_json::json!({
                "lines": [{
                    "key": "k1", "item_id": "00000000-0000-0000-0000-0000000000c1",
                    "name": "Latte", "unit_price_minor": 5000, "qty": 1,
                    "addons": [], "optionals": []
                }]
            }),
        )
        .unwrap();
        core.hold_cart_on_table("Table 9".into(), None, None, None)
            .unwrap();
        let id = core.list_drafts().unwrap().first().unwrap().id.clone();

        core.discard_draft(id).unwrap();

        assert_eq!(core.store.pending().unwrap().len(), before);
        assert_eq!(core.store.dead_count().unwrap(), 0);
    }

    /// Two free tables in the floor mirror — enough for the occupancy to have
    /// somewhere to go.
    fn seed_two_tables(core: &MadarCore) {
        core.store
            .kv_put(
                held::K_FLOOR_TABLES,
                r#"[{"id":"t1","section_id":"s","label":"T1","seats":4,"shape":"rect","status":"free","pos_x":0,"pos_y":0,"width":80,"height":80,"rotation":0,"is_active":true},
                    {"id":"t2","section_id":"s","label":"T2","seats":2,"shape":"rect","status":"free","pos_x":9,"pos_y":9,"width":80,"height":80,"rotation":0,"is_active":true}]"#,
            )
            .unwrap();
    }

    /// The one thing a hold DOES push, and the exact shape of it: the table is
    /// taken, then given back. Never the order — not its lines, not its money,
    /// not its name — because the room is shared and the draft is not.
    #[tokio::test]
    async fn a_hold_on_a_table_pushes_the_occupancy_and_only_that() {
        let core = signed_in_offline_core().await;
        let (t1, t2) = ("t1".to_string(), "t2".to_string());
        seed_two_tables(&core);
        let before = core.store.pending().unwrap().len();

        cart::set_cart_payload(
            &core.store,
            &serde_json::json!({
                "lines": [{
                    "key": "k1", "item_id": "00000000-0000-0000-0000-0000000000c1",
                    "name": "Latte", "unit_price_minor": 5000, "qty": 1,
                    "addons": [], "optionals": []
                }]
            }),
        )
        .unwrap();
        core.hold_cart_on_table("Sara".into(), None, None, Some(t1.clone()))
            .unwrap();
        let id = core.list_drafts().unwrap().first().unwrap().id.clone();

        // Move it, then check it out.
        core.assign_draft_table(id.clone(), Some(t2.clone()))
            .unwrap();
        core.complete_draft(id.clone(), None).unwrap();

        let ops: Vec<(String, String)> = core.store.pending().unwrap()[before..]
            .iter()
            .map(|i| (i.op_type.clone(), i.payload.clone()))
            .collect();
        let kinds: Vec<&str> = ops.iter().map(|(k, _)| k.as_str()).collect();
        assert_eq!(
            kinds,
            vec!["hold_table", "release_table", "hold_table", "release_table"],
            "take t1; move = give t1 back then take t2; checkout gives t2 back"
        );
        // FIFO carries the move: the release of the old table is queued before
        // the hold of the new one, so the server never sees the party on two.
        assert!(ops[0].1.contains(&t1));
        assert!(ops[1].1.contains(&t1));
        assert!(ops[2].1.contains(&t2));
        assert!(ops[3].1.contains(&t2));

        // A move is not a meal: t1 goes back to the room. The checkout IS one.
        assert!(
            ops[1].1.contains("\"bus\":false"),
            "moving off a table does not dirty it: {}",
            ops[1].1
        );
        assert!(
            ops[3].1.contains("\"bus\":true"),
            "the party ate — the table needs a cloth: {}",
            ops[3].1
        );

        // And nothing of the ORDER itself rode along.
        for (_, payload) in &ops {
            assert!(!payload.contains("Sara"), "the guest's name stayed home");
            assert!(!payload.contains("Latte"), "the lines stayed home");
            assert!(!payload.contains("5000"), "the money stayed home");
            assert!(!payload.contains(&id), "the draft id stayed home");
        }
    }

    /// A swap moves a parked draft too, and the server cannot see that: its own
    /// swap sets each side's status from the TICKET it finds, so it would free
    /// the very table the draft just landed on. The correction is queued behind
    /// the swap, so it has the last word.
    #[tokio::test]
    async fn swapping_a_parked_draft_corrects_the_occupancy_behind_the_swap() {
        let core = signed_in_offline_core().await;
        seed_two_tables(&core);
        cart::set_cart_payload(
            &core.store,
            &serde_json::json!({
                "lines": [{
                    "key": "k1", "item_id": "00000000-0000-0000-0000-0000000000c1",
                    "name": "Latte", "unit_price_minor": 5000, "qty": 1,
                    "addons": [], "optionals": []
                }]
            }),
        )
        .unwrap();
        core.hold_cart_on_table("Sara".into(), None, None, Some("t1".into()))
            .unwrap();
        let before = core.store.pending().unwrap().len();

        core.swap_tables("t1".into(), "t2".into()).unwrap();

        let ops: Vec<(String, String)> = core.store.pending().unwrap()[before..]
            .iter()
            .map(|i| (i.op_type.clone(), i.payload.clone()))
            .collect();
        let kinds: Vec<&str> = ops.iter().map(|(k, _)| k.as_str()).collect();
        assert_eq!(
            kinds,
            vec!["swap_tables", "release_table", "hold_table"],
            "the corrections land AFTER the swap the server would otherwise win"
        );
        assert!(ops[1].1.contains("t1"), "t1 is given back");
        assert!(ops[2].1.contains("t2"), "t2 is taken");
        assert!(
            ops[1].1.contains("\"bus\":false"),
            "a swap is not a meal: t1 goes back to the room"
        );
    }

    /// Tills upgrading from v0.2.0 arrive carrying dead rows from the old ops.
    /// Boot clears exactly those, and nothing else — a dead row of another kind
    /// is a real failure someone may still need to see.
    #[test]
    fn boot_sweeps_the_old_dead_held_ops_and_spares_every_other_kind() {
        let store = store::Store::open("").unwrap();
        let mut seq = 0i64;
        let mut queue = |op_type: &str| {
            seq += 1;
            store
                .enqueue(&store::NewOutboxOp {
                    id: format!("{op_type}-{seq}"),
                    op_type: op_type.into(),
                    idempotency_key: format!("{op_type}-{seq}"),
                    payload: "{}".into(),
                    event_at: "2026-09-07T10:00:00Z".into(),
                    depends_on_seq: None,
                    user_id: None,
                    clock_offset_ms: None,
                    shift_id: None,
                })
                .unwrap();
        };
        for op in [
            "park_held_order",
            "claim_held_order",
            "release_held_order",
            "discard_held_order",
            "complete_held_order",
            "create_order",
            "clear_table",
        ] {
            queue(op);
        }
        for item in store.pending().unwrap() {
            store.mark_dead(item.seq, "stale").unwrap();
        }
        assert_eq!(store.dead_count().unwrap(), 7);

        let swept = store.purge_dead_held_ops().unwrap();
        assert_eq!(swept, 5, "the five held-order ops go");
        // A dead order and a dead clear are real failures — they stay.
        assert_eq!(store.dead_count().unwrap(), 2);
        // And running it again is a no-op, so it is safe on every boot.
        assert_eq!(store.purge_dead_held_ops().unwrap(), 0);
    }

    /// The org's tax policy has to reach the price the customer is shown.
    ///
    /// Every hop already looked right on its own — the backend resolves the
    /// BRANCH's policy at login and at `/auth/me`, the snapshot carries all
    /// four fields, the offline bundle round-trips them, and the engine has its
    /// own inclusive/exclusive tests. What nothing covered was the whole chain:
    /// a shop that turns "menu prices include tax" on, and a till that then
    /// prices as though it had not.
    #[tokio::test]
    async fn the_shops_tax_policy_reaches_the_price_on_screen() {
        let line = serde_json::json!({
            "lines": [{
                "key": "k1", "item_id": "00000000-0000-0000-0000-0000000000c1",
                "name": "Latte", "unit_price_minor": 10000, "qty": 1,
                "addons": [], "optionals": []
            }]
        });

        // EXCLUSIVE: 100.00 on the menu, tax added on top.
        let core = signed_in_offline_core().await;
        cart::set_cart_payload(&core.store, &line).unwrap();
        let out = core.cart_totals().unwrap();
        assert_eq!(out.subtotal_minor, 10000);
        assert_eq!(out.tax_minor, 1400, "14% added on top");
        assert_eq!(out.total_minor, 11400);

        // INCLUSIVE, and a taxed service charge: the same shop, two switches.
        let core = signed_in_offline_core_with(
            r#"{"org_id":"00000000-0000-0000-0000-0000000000aa","currency_code":"EGP",
                "tax_rate":0.14,"tax_inclusive":true,
                "service_charge_rate":0.12,"service_charge_taxable":true}"#,
        )
        .await;
        cart::set_cart_payload(&core.store, &line).unwrap();
        let out = core.cart_totals().unwrap();
        assert_eq!(out.subtotal_minor, 10000);
        assert_eq!(out.service_charge_minor, 1200, "12% of the bill");
        // Inclusive: the 112.00 the customer pays already contains the tax.
        assert_eq!(out.total_minor, 11200, "the menu price is what they pay");
        assert!(
            out.tax_minor > 0 && out.tax_minor < 1400,
            "tax is carved OUT of the gross, not added: got {}",
            out.tax_minor
        );
    }

    async fn signed_in_offline_core() -> Arc<MadarCore> {
        signed_in_offline_core_with(
            r#"{"org_id":"00000000-0000-0000-0000-0000000000aa","currency_code":"EGP","tax_rate":0.14}"#,
        )
        .await
    }

    async fn signed_in_offline_core_with(org_config: &str) -> Arc<MadarCore> {
        use argon2::password_hash::SaltString;
        use argon2::{Argon2, PasswordHasher};
        let core = MadarCore::new(MadarConfig {
            base_url: "http://127.0.0.1:1".into(),
            environment: "dev".into(),
            db_path: String::new(),
            locale: "en".into(),
        })
        .unwrap();
        let salt = SaltString::encode_b64(b"madar-test-salt").unwrap();
        let phc = Argon2::default()
            .hash_password(b"1234", &salt)
            .unwrap()
            .to_string();
        core.store
            .kv_put(
                session::BUNDLE_KEY,
                &serde_json::json!({
                    "org_id": "00000000-0000-0000-0000-0000000000aa",
                    "generated_at": "2026-06-19T10:00:00Z",
                    "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
                    "tellers": [{ "user_id": "00000000-0000-0000-0000-0000000000bb",
                        "name": "Sara", "role": "teller", "is_active": true, "offline_pin_hash": phc }]
                })
                .to_string(),
            )
            .unwrap();
        core.store
            .kv_put(session::ORG_CONFIG_KEY, org_config)
            .unwrap();
        core.sign_in(session::LoginRequest {
            mode: session::LoginMode::Pin,
            name: Some("Sara".into()),
            pin: Some("1234".into()),
            branch_id: Some("00000000-0000-0000-0000-000000000001".into()),
            email: None,
            password: None,
            org_id: None,
        })
        .await
        .unwrap();
        core
    }

    /// ISSUE 1 fix (deterministic, no backend): the offline "close A → open B"
    /// handover wires open B's outbox DEPENDENCY onto A's still-queued close, so on
    /// reconnect B's open can NEVER replay before A's close commits. Without that
    /// gate the open races the still-open branch, 409s "a shift is already open for
    /// this branch", dead-letters, cascades B's orders, and strands the teller on
    /// the open-shift screen — the field bug. A first-ever open (no queued close)
    /// has no dependency, since the branch is already free.
    #[tokio::test]
    async fn offline_open_after_close_depends_on_the_close() {
        let core = signed_in_offline_core().await;

        // First-ever open: no prior close queued → no dependency (branch is free).
        core.open_shift(50_000, None).await.unwrap();
        let open_a = core
            .store
            .list_active()
            .unwrap()
            .into_iter()
            .find(|i| i.op_type == "open_shift")
            .unwrap();
        assert_eq!(
            open_a.depends_on_seq, None,
            "the first open has no close to wait on"
        );

        // Close A (queues behind the open), then open B offline.
        core.close_shift(48_000, None).await.unwrap();
        core.open_shift(48_000, None).await.unwrap();

        let active = core.store.list_active().unwrap();
        let close_a = active
            .iter()
            .find(|i| i.op_type == "close_shift")
            .expect("close A queued");
        let open_b = active
            .iter()
            .filter(|i| i.op_type == "open_shift")
            .max_by_key(|i| i.seq)
            .expect("open B queued");
        assert!(open_b.seq > close_a.seq, "B opened after A's close");
        assert_eq!(
            open_b.depends_on_seq,
            Some(close_a.seq),
            "open B must DEPEND on A's close — the sequential-handover gate that prevents the 409",
        );
    }

    /// HARDENING (dependents WAIT on a dead dependency, never cascade-dead): if the
    /// prior shift's queued close DEAD-letters (e.g. a backend cash-continuity
    /// rejection), the dependent open — and by extension its orders — must stay
    /// PENDING (recoverable), not cascade dead and strand the sale. Resolving the
    /// root op later (retry/discard) then flows the whole chain. This is what keeps
    /// a teller-switch whose close fails from orphaning the next teller's sales.
    #[tokio::test]
    async fn dependent_op_waits_on_a_dead_dependency_instead_of_cascading() {
        let core = signed_in_offline_core().await;

        // Open A → close A → open B (B depends on A's close), all offline.
        core.open_shift(50_000, None).await.unwrap();
        core.close_shift(48_000, None).await.unwrap();
        core.open_shift(48_000, None).await.unwrap();

        let active = core.store.list_active().unwrap();
        let open_a = active
            .iter()
            .filter(|i| i.op_type == "open_shift")
            .min_by_key(|i| i.seq)
            .unwrap()
            .seq;
        let close_a = active
            .iter()
            .find(|i| i.op_type == "close_shift")
            .unwrap()
            .seq;
        let open_b = active
            .iter()
            .filter(|i| i.op_type == "open_shift")
            .max_by_key(|i| i.seq)
            .unwrap()
            .seq;

        // Pretend A's open already synced, then A's close DIES on the server.
        core.store.mark_acked(open_a, Some("srv-a")).unwrap();
        core.store
            .mark_dead(close_a, "continuity: closing cash mismatch")
            .unwrap();

        // Drain: open B's dependency (close A) is dead → it must WAIT, not cascade.
        let _ = core.drain_outbox().await;

        let after = core.store.list_active().unwrap();
        let ob = after
            .iter()
            .find(|i| i.seq == open_b)
            .expect("open B still in the outbox");
        assert_eq!(
            ob.status, "pending",
            "open B waits on the dead close — never cascade-dead"
        );
        assert_eq!(
            core.store.dead_count().unwrap(),
            1,
            "only the ROOT close is dead; the chain stays recoverable"
        );
    }

    /// SEQUENTIAL-ONLY: `device_has_open_shift` is the deterministic gate. It's
    /// true for a cached OPEN shift and for an uncovered queued open (defense for
    /// a lost cache), and FALSE once the open is covered by a close — so the
    /// offline "close A → open B" flow is never blocked.
    #[test]
    fn device_has_open_shift_tracks_cache_and_uncovered_queued_opens() {
        let core = MadarCore::from_env().unwrap();
        assert!(!core.device_has_open_shift().unwrap()); // nothing yet

        // A cached OPEN shift counts.
        seed_shift_returning_id(&core, uuid::Uuid::new_v4(), "open");
        assert!(core.device_has_open_shift().unwrap());

        // Closed locally with nothing queued → no longer open.
        shift::close_local(&core.store).unwrap();
        assert!(!core.device_has_open_shift().unwrap());

        // Cache lost but an open is still queued with no close → still "open".
        shift::clear(&core.store).unwrap();
        let sid = uuid::Uuid::new_v4().to_string();
        enqueue_open_shift(&core, &sid);
        assert!(core.device_has_open_shift().unwrap());

        // Queue its close → the open is now covered → not open (reopen allowed).
        enqueue_close_shift(&core, &sid);
        assert!(!core.device_has_open_shift().unwrap());
    }

    /// The behavioral guarantee: a second `open_shift` while one is open is
    /// rejected; after a (local) close it's allowed again — the sequential
    /// offline shift cycle. Driven fully offline (dead url) on a real session.
    #[tokio::test]
    async fn open_shift_rejects_a_second_open_then_allows_reopen_after_close() {
        use argon2::password_hash::SaltString;
        use argon2::{Argon2, PasswordHasher};

        let core = MadarCore::new(MadarConfig {
            base_url: "http://127.0.0.1:1".into(),
            environment: "dev".into(),
            db_path: String::new(),
            locale: "en".into(),
        })
        .unwrap();
        let salt = SaltString::encode_b64(b"madar-test-salt").unwrap();
        let phc = Argon2::default()
            .hash_password(b"1234", &salt)
            .unwrap()
            .to_string();
        core.store
            .kv_put(
                session::BUNDLE_KEY,
                &serde_json::json!({
                    "org_id": "00000000-0000-0000-0000-0000000000aa",
                    "generated_at": "2026-06-19T10:00:00Z",
                    "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
                    "tellers": [{ "user_id": "00000000-0000-0000-0000-0000000000bb",
                        "name": "Sara", "role": "teller", "is_active": true, "offline_pin_hash": phc }]
                })
                .to_string(),
            )
            .unwrap();
        core.store
            .kv_put(session::ORG_CONFIG_KEY, r#"{"org_id":"00000000-0000-0000-0000-0000000000aa","currency_code":"EGP","tax_rate":0.14}"#)
            .unwrap();
        core.sign_in(session::LoginRequest {
            mode: session::LoginMode::Pin,
            name: Some("Sara".into()),
            pin: Some("1234".into()),
            branch_id: Some("00000000-0000-0000-0000-000000000001".into()),
            email: None,
            password: None,
            org_id: None,
        })
        .await
        .unwrap();

        // First open succeeds.
        core.open_shift(50000, None).await.unwrap();
        assert!(core.current_shift().unwrap().unwrap().is_open);

        // A second open while one is open is REJECTED (and leaves the first intact).
        let second = core.open_shift(60000, None).await;
        assert!(
            matches!(second, Err(CoreError::Validation { .. })),
            "got {second:?}"
        );
        let still = core.current_shift().unwrap().unwrap();
        assert!(still.is_open);
        assert_eq!(
            still.opening_cash_minor, 50000,
            "the original shift must be untouched"
        );

        // Close it (locally; the close just queues offline) → reopen is allowed.
        core.close_shift(48000, None).await.unwrap();
        assert!(!core.current_shift().unwrap().unwrap().is_open);
        core.open_shift(48000, None)
            .await
            .expect("reopen after close must be allowed");
        assert!(core.current_shift().unwrap().unwrap().is_open);
    }

    /// Skeptic-1 regression: the open-shift pending guard must be scoped to the
    /// cached shift's id, NOT device-global. A foreign teller's orphaned command
    /// (left in the shared outbox after sign-out) must not keep a shift alive.
    #[test]
    fn open_pending_is_scoped_to_the_cached_shift_not_device_global() {
        let core = MadarCore::from_env().unwrap();
        let shift_id = seed_shift_returning_id(&core, uuid::Uuid::new_v4(), "open");
        assert!(!core.shift_command_pending("open_shift").unwrap()); // nothing queued
                                                                     // A DIFFERENT shift's orphaned open_shift command does NOT count.
        enqueue_open_shift(&core, &uuid::Uuid::new_v4().to_string());
        assert!(!core.shift_command_pending("open_shift").unwrap());
        // Our own cached shift's command DOES.
        enqueue_open_shift(&core, &shift_id);
        assert!(core.shift_command_pending("open_shift").unwrap());
    }

    /// End-to-end offline: open a shift, sell nothing, then close it. The shift
    /// flips to closed locally (route → open-shift) and the close command queues
    /// behind the open (FIFO); the cart is dropped.
    #[tokio::test]
    async fn closing_a_shift_offline_routes_back_to_open_shift() {
        use argon2::password_hash::SaltString;
        use argon2::{Argon2, PasswordHasher};

        let core = MadarCore::new(MadarConfig {
            base_url: "http://127.0.0.1:1".into(),
            environment: "dev".into(),
            db_path: String::new(),
            locale: "en".into(),
        })
        .unwrap();
        let salt = SaltString::encode_b64(b"madar-test-salt").unwrap();
        let phc = Argon2::default()
            .hash_password(b"1234", &salt)
            .unwrap()
            .to_string();
        core.store
            .kv_put(
                session::BUNDLE_KEY,
                &serde_json::json!({
                    "org_id": "00000000-0000-0000-0000-0000000000aa",
                    "generated_at": "2026-06-19T10:00:00Z",
                    "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
                    "tellers": [{ "user_id": "00000000-0000-0000-0000-0000000000bb",
                        "name": "Sara", "role": "teller", "is_active": true, "offline_pin_hash": phc }]
                })
                .to_string(),
            )
            .unwrap();
        core.store
            .kv_put(session::ORG_CONFIG_KEY, r#"{"org_id":"00000000-0000-0000-0000-0000000000aa","currency_code":"EGP","tax_rate":0.14}"#)
            .unwrap();
        // The device is bound to its branch in the CORE store; sign-in + app_route
        // both read it from there now (no host-passed branch).
        core.set_device_branch("00000000-0000-0000-0000-000000000001".into(), None)
            .unwrap();
        core.sign_in(session::LoginRequest {
            mode: session::LoginMode::Pin,
            name: Some("Sara".into()),
            pin: Some("1234".into()),
            branch_id: Some("00000000-0000-0000-0000-000000000001".into()),
            email: None,
            password: None,
            org_id: None,
        })
        .await
        .unwrap();

        core.open_shift(50000, None).await.unwrap();
        core.cart_add("item-1".into(), "Latte".into(), 1000)
            .unwrap();
        assert_eq!(core.app_route(), AppRoute::Order);

        core.close_shift(48000, Some("short by 20".into()))
            .await
            .unwrap();
        // Routed back to open-shift, cart dropped, and both commands queued.
        assert_eq!(core.app_route(), AppRoute::OpenShift);
        assert!(core.cart_lines().unwrap().is_empty());
        assert_eq!(core.pending_outbox_count().unwrap(), 2); // open + close
        assert!(core.shift_command_pending("close_shift").unwrap());
    }

    #[tokio::test]
    async fn close_shift_without_an_open_shift_is_rejected() {
        let core = MadarCore::from_env().unwrap();
        let err = core.close_shift(1000, None).await;
        assert!(matches!(err, Err(CoreError::Validation { .. })));
    }

    #[test]
    fn route_device_setup_until_branch_bound() {
        let core = MadarCore::from_env().unwrap();
        assert_eq!(core.app_route(), AppRoute::DeviceSetup); // unbound (no device config)
        core.set_device_branch("b".into(), Some("Main".into()))
            .unwrap();
        core.start_reconfigure().unwrap();
        assert_eq!(core.app_route(), AppRoute::DeviceSetup); // bound but mid-reconfigure
    }

    #[test]
    fn route_login_when_configured_but_signed_out() {
        let core = MadarCore::from_env().unwrap();
        core.set_device_branch("b".into(), None).unwrap();
        assert_eq!(core.app_route(), AppRoute::Login);
    }

    #[test]
    fn route_open_shift_when_signed_in_without_a_shift() {
        let core = MadarCore::from_env().unwrap();
        core.set_device_branch("b".into(), None).unwrap();
        set_session(
            &core,
            Some(teller_session(&uuid::Uuid::new_v4().to_string(), Some("b"))),
        );
        assert_eq!(core.app_route(), AppRoute::OpenShift);
    }

    #[test]
    fn route_order_when_own_shift_is_open() {
        // The regression: a teller's own open shift routes to Order and STAYS.
        let core = MadarCore::from_env().unwrap();
        core.set_device_branch("b".into(), None).unwrap();
        let teller = uuid::Uuid::new_v4();
        set_session(&core, Some(teller_session(&teller.to_string(), Some("b"))));
        seed_shift(&core, teller, "open");
        assert_eq!(core.app_route(), AppRoute::Order);
    }

    #[test]
    fn route_open_shift_for_a_foreign_tellers_shift() {
        // A stale shift left by a DIFFERENT teller must not route the new one in.
        let core = MadarCore::from_env().unwrap();
        core.set_device_branch("b".into(), None).unwrap();
        let me = uuid::Uuid::new_v4();
        set_session(&core, Some(teller_session(&me.to_string(), Some("b"))));
        seed_shift(&core, uuid::Uuid::new_v4(), "open");
        assert_eq!(core.app_route(), AppRoute::OpenShift);
    }

    #[test]
    fn route_open_shift_when_the_shift_is_closed() {
        let core = MadarCore::from_env().unwrap();
        core.set_device_branch("b".into(), None).unwrap();
        let teller = uuid::Uuid::new_v4();
        set_session(&core, Some(teller_session(&teller.to_string(), Some("b"))));
        seed_shift(&core, teller, "closed");
        assert_eq!(core.app_route(), AppRoute::OpenShift);
    }

    #[test]
    fn route_kitchen_role_to_the_kds_for_its_station() {
        // A kitchen-role device routes to the KDS for its configured station,
        // needing NO shift — but stays in device-setup until a station is bound.
        let core = MadarCore::from_env().unwrap();
        core.set_device_branch("b".into(), None).unwrap();
        set_session(
            &core,
            Some(kitchen_session(
                &uuid::Uuid::new_v4().to_string(),
                Some("b"),
            )),
        );
        assert_eq!(
            core.app_route(),
            AppRoute::DeviceSetup,
            "kitchen device needs a station"
        );
        core.set_device_station(Some("grill".into())).unwrap();
        assert_eq!(
            core.app_route(),
            AppRoute::KitchenDisplay {
                station_id: "grill".into()
            }
        );
    }

    /// End-to-end offline: sign in offline, open a shift (the open_shift command
    /// can't reach the server, so it stays queued), and assert the route lands —
    /// and STAYS — on Order. This is the open-shift "bounce" reproduced E2E.
    #[tokio::test]
    async fn opening_a_shift_offline_routes_to_order_and_stays() {
        use argon2::password_hash::SaltString;
        use argon2::{Argon2, PasswordHasher};

        let core = MadarCore::new(MadarConfig {
            base_url: "http://127.0.0.1:1".into(), // nothing listening → offline
            environment: "dev".into(),
            db_path: String::new(),
            locale: "en".into(),
        })
        .unwrap();

        let salt = SaltString::encode_b64(b"madar-test-salt").unwrap();
        let phc = Argon2::default()
            .hash_password(b"1234", &salt)
            .unwrap()
            .to_string();
        let bundle = serde_json::json!({
            "org_id": "00000000-0000-0000-0000-0000000000aa",
            "generated_at": "2026-06-19T10:00:00Z",
            "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
            "tellers": [{
                "user_id": "00000000-0000-0000-0000-0000000000bb",
                "name": "Sara", "role": "teller", "is_active": true,
                "offline_pin_hash": phc,
            }]
        });
        core.store
            .kv_put(session::BUNDLE_KEY, &bundle.to_string())
            .unwrap();
        core.store
            .kv_put(session::ORG_CONFIG_KEY, r#"{"org_id":"00000000-0000-0000-0000-0000000000aa","currency_code":"EGP","tax_rate":0.14}"#)
            .unwrap();

        let branch = "00000000-0000-0000-0000-000000000001";
        core.set_device_branch(branch.into(), None).unwrap();
        let snap = core
            .sign_in(session::LoginRequest {
                mode: session::LoginMode::Pin,
                name: Some("Sara".into()),
                pin: Some("1234".into()),
                branch_id: Some(branch.into()),
                email: None,
                password: None,
                org_id: None,
            })
            .await
            .expect("offline sign-in");
        assert!(!snap.online);
        // Signed in, no shift yet → open-shift.
        assert_eq!(core.app_route(), AppRoute::OpenShift);

        let shift = core
            .open_shift(50000, None)
            .await
            .expect("open shift offline");
        assert!(shift.is_open);
        // The command is queued (couldn't reach the server)…
        assert_eq!(core.pending_outbox_count().unwrap(), 1);
        // …and the route is Order — and stays there (the bounce is gone).
        assert_eq!(core.app_route(), AppRoute::Order);
        assert_eq!(core.app_route(), AppRoute::Order);
    }

    #[test]
    fn cart_totals_use_the_session_tax_rate() {
        let core = MadarCore::from_env().unwrap();
        set_session(
            &core,
            Some(teller_session(&uuid::Uuid::new_v4().to_string(), Some("b"))),
        );
        core.cart_add("item-1".into(), "Latte".into(), 1000)
            .unwrap();
        core.cart_add("item-1".into(), "Latte".into(), 1000)
            .unwrap(); // qty 2
        let t = core.cart_totals().unwrap();
        assert_eq!(t.item_count, 2);
        assert_eq!(t.subtotal_minor, 2000);
        assert_eq!(t.tax_minor, 280); // 0.14 * 2000
        assert_eq!(t.total_minor, 2280);
    }

    #[test]
    fn cart_totals_are_tax_free_when_signed_out() {
        let core = MadarCore::from_env().unwrap();
        core.cart_add("i".into(), "X".into(), 1000).unwrap();
        let t = core.cart_totals().unwrap();
        assert_eq!(t.tax_minor, 0);
        assert_eq!(t.total_minor, 1000);
    }

    // ════════════════════════════════════════════════════════════════════════
    // OFFLINE ROBUSTNESS — JWT expiry, truthful reauth banner, auth-park recovery,
    // and the no-bearer drain guard (the fixes for "queued but nothing pushes" +
    // "forced re-login on a brief blip").
    // ════════════════════════════════════════════════════════════════════════

    /// Unpadded base64url-encode (test-only) to mint JWT payloads for the decoder.
    fn b64url(bytes: &[u8]) -> String {
        const A: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        let mut out = String::new();
        for chunk in bytes.chunks(3) {
            let n = ((chunk[0] as u32) << 16)
                | ((*chunk.get(1).unwrap_or(&0) as u32) << 8)
                | (*chunk.get(2).unwrap_or(&0) as u32);
            out.push(A[((n >> 18) & 63) as usize] as char);
            out.push(A[((n >> 12) & 63) as usize] as char);
            if chunk.len() > 1 {
                out.push(A[((n >> 6) & 63) as usize] as char);
            }
            if chunk.len() > 2 {
                out.push(A[(n & 63) as usize] as char);
            }
        }
        out
    }

    /// A fake three-segment JWT carrying `{sub, exp}` (the client never verifies the
    /// signature — these are only local hints).
    fn fake_jwt_sub(sub: &str, exp_secs: i64) -> String {
        let payload = serde_json::json!({ "sub": sub, "exp": exp_secs }).to_string();
        format!("hdr.{}.sig", b64url(payload.as_bytes()))
    }
    fn fake_jwt(exp_secs: i64) -> String {
        fake_jwt_sub("u", exp_secs)
    }

    const TELLER_BB: &str = "00000000-0000-0000-0000-0000000000bb";
    const BRANCH_1: &str = "00000000-0000-0000-0000-000000000001";

    /// A dead-url core with Sara's (id `bb`) offline bundle cached but NOT signed in.
    fn offline_core_with_bundle() -> Arc<MadarCore> {
        use argon2::password_hash::SaltString;
        use argon2::{Argon2, PasswordHasher};
        let core = MadarCore::new(MadarConfig {
            base_url: "http://127.0.0.1:1".into(),
            environment: "dev".into(),
            db_path: String::new(),
            locale: "en".into(),
        })
        .unwrap();
        let salt = SaltString::encode_b64(b"madar-test-salt").unwrap();
        let phc = Argon2::default()
            .hash_password(b"1234", &salt)
            .unwrap()
            .to_string();
        core.store
            .kv_put(
                session::BUNDLE_KEY,
                &serde_json::json!({
                    "org_id": "00000000-0000-0000-0000-0000000000aa",
                    "generated_at": "2026-06-19T10:00:00Z",
                    "lan_secret": "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
                    "tellers": [{ "user_id": TELLER_BB, "name": "Sara", "role": "teller",
                                  "is_active": true, "offline_pin_hash": phc }]
                })
                .to_string(),
            )
            .unwrap();
        core.store
            .kv_put(session::ORG_CONFIG_KEY, r#"{"org_id":"00000000-0000-0000-0000-0000000000aa","currency_code":"EGP","tax_rate":0.14}"#)
            .unwrap();
        core
    }

    /// Seed a prior in-memory session whose token is minted for `token_sub`.
    fn install_prior_token(core: &MadarCore, token_sub: &str, exp_secs: i64) {
        let token = fake_jwt_sub(token_sub, exp_secs);
        let state = session::SessionState {
            snapshot: session::SessionSnapshot {
                user_id: token_sub.into(),
                display_name: "prev".into(),
                role: "teller".into(),
                org_id: Some("00000000-0000-0000-0000-0000000000aa".into()),
                branch_id: Some(BRANCH_1.into()),
                currency_code: "EGP".into(),
                tax_rate: 0.14,
                tax_inclusive: false,
                service_charge_rate: 0.0,
                service_charge_taxable: true,
                require_table_for_orders: false,
                online: false,
                permissions_loaded: true,
            },
            permissions: Vec::new(),
            token: Some(token.clone()),
        };
        core.api.set_bearer(Some(token));
        core.persist_and_set(state);
    }

    /// Install a live online-style session holding `token` with the given exp.
    fn signed_in_with_token(core: &MadarCore, exp_secs: i64) {
        let token = fake_jwt(exp_secs);
        let state = session::SessionState {
            snapshot: session::SessionSnapshot {
                user_id: "00000000-0000-0000-0000-0000000000bb".into(),
                display_name: "Sara".into(),
                role: "teller".into(),
                org_id: Some("00000000-0000-0000-0000-0000000000aa".into()),
                branch_id: Some("00000000-0000-0000-0000-000000000001".into()),
                currency_code: "EGP".into(),
                tax_rate: 0.14,
                tax_inclusive: false,
                service_charge_rate: 0.0,
                service_charge_taxable: true,
                require_table_for_orders: false,
                online: false,
                permissions_loaded: true,
            },
            permissions: Vec::new(),
            token: Some(token.clone()),
        };
        core.api.set_bearer(Some(token));
        core.persist_and_set(state);
    }

    #[test]
    fn jwt_exp_decode_and_expiry_check() {
        assert_eq!(jwt_exp_secs(&fake_jwt(1_900_000_000)), Some(1_900_000_000));
        assert_eq!(jwt_exp_secs("not-a-jwt"), None);
        assert_eq!(jwt_exp_secs("a..c"), None); // empty payload segment
        assert_eq!(jwt_exp_secs("hdr.bm90anNvbg.sig"), None); // payload not JSON
                                                              // past exp → expired; future exp → not; unreadable → expired (conservative).
        assert!(token_is_expired(&fake_jwt(1_000), 2_000));
        assert!(!token_is_expired(&fake_jwt(9_000), 2_000));
        assert!(token_is_expired("garbage", 2_000));
    }

    #[test]
    fn session_persists_in_the_core_store_across_restart() {
        let dir = std::env::temp_dir().join(format!("madar-vault-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let db = dir.join("madar.db").to_string_lossy().into_owned();
        let cfg = || MadarConfig {
            base_url: "http://127.0.0.1:1".into(),
            environment: "dev".into(),
            db_path: db.clone(),
            locale: "en".into(),
        };
        let now = chrono::Utc::now().timestamp();

        // "First run": install a live session — persist_and_set writes
        // session:blob into the core's OWN store, no host vault involved.
        let core = MadarCore::new(cfg()).unwrap();
        signed_in_with_token(&core, now + 3600);
        drop(core);

        // "Restart": a fresh handle over the same sqlite restores locally,
        // offline-until-proven-online.
        let core = MadarCore::new(cfg()).unwrap();
        let restored = core.restore_session_cached().expect("session restored");
        assert!(!restored.online, "cold restore must start offline");
        assert!(core.is_authenticated());

        // Logout wipes the persisted blob — the next restart is signed out.
        core.logout(false).unwrap();
        drop(core);
        let core = MadarCore::new(cfg()).unwrap();
        assert!(
            core.restore_session_cached().is_none(),
            "logout must clear the persisted session"
        );
        let _ = std::fs::remove_dir_all(dir);
    }

    /// A token can die without expiring, and the teller has to be told.
    ///
    /// The banner used to require the cached JWT to have passed its `exp`. A
    /// revoked token — rotated secret, deactivated user, suspended org — is
    /// refused by the server while `exp` is still hours away, so the queue parked
    /// silently, the till looked merely offline, and the only way out was to wait
    /// for a token the server had already stopped honouring.
    #[test]
    fn the_reauth_banner_shows_for_a_refused_token_even_before_it_expires() {
        use std::sync::atomic::Ordering::Relaxed;
        let core = MadarCore::from_env().unwrap();
        let now = core.corrected_now().timestamp();

        // Unexpired, and refused anyway: `auth_paused` is only ever latched from a
        // 401 carrying our own error envelope, so it already means the backend
        // looked at this bearer and said no.
        signed_in_with_token(&core, now + 3600);
        core.set_online(true);
        core.auth_paused.store(true, Relaxed);
        assert!(
            core.sync_status().unwrap().auth_paused,
            "a refused token must prompt a re-login without waiting for its exp"
        );

        // Still suppressed while unreachable: re-auth mints a JWT from the server,
        // so the prompt would be a dead end. The host resurfaces it on the
        // offline→online edge.
        core.set_online(false);
        assert!(
            !core.sync_status().unwrap().auth_paused,
            "no re-login prompt while there is no server to re-login against"
        );

        // And an expired one, once online, behaves exactly the same.
        signed_in_with_token(&core, now - 3600);
        core.auth_paused.store(true, Relaxed);
        core.set_online(true);
        assert!(
            core.sync_status().unwrap().auth_paused,
            "an expired JWT must surface the re-login banner once online"
        );
    }

    /// Un-parking is evidence, not arithmetic.
    ///
    /// With no backend to ask, the park stands — whatever the clock says about the
    /// token. The old rule cleared it on `exp` alone, which is what let a refused
    /// token loop between un-park, drain, 401 and re-park without ever prompting.
    #[tokio::test]
    async fn an_unexpired_token_does_not_unpark_itself() {
        use std::sync::atomic::Ordering::Relaxed;
        let core = MadarCore::from_env().unwrap();
        let now = core.corrected_now().timestamp();

        signed_in_with_token(&core, now + 3600);
        core.auth_paused.store(true, Relaxed);
        core.unpark_if_token_accepted().await;
        assert!(
            core.auth_paused.load(Relaxed),
            "nothing confirmed the bearer, so the park must hold"
        );

        signed_in_with_token(&core, now - 3600);
        core.auth_paused.store(true, Relaxed);
        core.unpark_if_token_accepted().await;
        assert!(
            core.auth_paused.load(Relaxed),
            "expired token → park retained for re-login"
        );
    }

    #[tokio::test]
    async fn drain_holds_and_parks_without_a_bearer_when_signed_in() {
        // An offline-unlocked session has no token → the drain must HOLD the
        // backlog (never POST /sync/replay with no credential) AND latch
        // auth_paused so the host surfaces the re-login banner. The old silent
        // hold left the UI reading "syncing (N)" forever with no error — the
        // field bug. The park is recoverable: a fresh online login installs a
        // bearer and clears auth_paused (see login), then the backlog drains.
        use std::sync::atomic::Ordering::Relaxed;
        let core = signed_in_offline_core().await;
        assert!(!core.api.has_bearer(), "offline unlock holds no bearer");
        core.store
            .enqueue(&store::NewOutboxOp {
                id: "o1".into(),
                op_type: "create_order".into(),
                idempotency_key: "o1".into(),
                payload: "{}".into(),
                event_at: "2026-06-19T10:00:00Z".into(),
                user_id: Some("00000000-0000-0000-0000-0000000000bb".into()),
                ..Default::default()
            })
            .unwrap();
        let before = core.store.pending_count().unwrap();
        core.drain_outbox().await.unwrap();
        assert_eq!(
            core.store.pending_count().unwrap(),
            before,
            "no-bearer drain leaves the queue intact"
        );
        assert!(
            core.auth_paused.load(Relaxed),
            "a live session with no bearer must park → the reauth banner shows"
        );
    }

    #[tokio::test]
    async fn drain_holds_silently_without_a_bearer_when_signed_out() {
        // Signed out entirely there is nobody to prompt — hold without the
        // park; the backlog drains on the next login.
        use std::sync::atomic::Ordering::Relaxed;
        let core = offline_core_with_bundle();
        assert!(core.current_session().is_none());
        assert!(!core.api.has_bearer());
        core.store
            .enqueue(&store::NewOutboxOp {
                id: "o1".into(),
                op_type: "create_order".into(),
                idempotency_key: "o1".into(),
                payload: "{}".into(),
                event_at: "2026-06-19T10:00:00Z".into(),
                user_id: Some("00000000-0000-0000-0000-0000000000bb".into()),
                ..Default::default()
            })
            .unwrap();
        let before = core.store.pending_count().unwrap();
        core.drain_outbox().await.unwrap();
        assert_eq!(core.store.pending_count().unwrap(), before);
        assert!(
            !core.auth_paused.load(Relaxed),
            "signed out → no park; nobody to prompt"
        );
    }

    // ── offline unlock: the cached JWT must be OWNED by the unlocking teller ──────

    #[test]
    fn unlock_offline_keeps_own_valid_token() {
        use std::sync::atomic::Ordering::Relaxed;
        let core = offline_core_with_bundle();
        let now = core.corrected_now().timestamp();
        // Prior session holds SARA's OWN, still-valid token.
        install_prior_token(&core, TELLER_BB, now + 3600);
        let snap = core
            .unlock_offline("Sara".into(), "1234".into(), BRANCH_1.into())
            .unwrap();
        assert_eq!(snap.user_id, TELLER_BB);
        assert!(
            core.api.has_bearer(),
            "own valid token is kept as the bearer"
        );
        assert!(
            !core.borrowed_token.load(Relaxed),
            "own token is not 'borrowed'"
        );
        assert!(
            !core.sync_status().unwrap().auth_paused,
            "no re-login banner with an own valid token"
        );
        // The own token IS persisted (survives a restart).
        let persisted = core
            .session
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .and_then(|s| s.token.clone());
        assert!(persisted.is_some(), "own token persisted");
    }

    #[tokio::test]
    async fn unlock_offline_borrows_foreign_token_then_invalidates_after_flush() {
        use std::sync::atomic::Ordering::Relaxed;
        let core = offline_core_with_bundle();
        let now = core.corrected_now().timestamp();
        // Prior session holds a DIFFERENT teller's still-valid token (shared till).
        install_prior_token(&core, "00000000-0000-0000-0000-0000000000cc", now + 3600);

        let snap = core
            .unlock_offline("Sara".into(), "1234".into(), BRANCH_1.into())
            .unwrap();
        assert_eq!(snap.user_id, TELLER_BB);
        // It's used IN MEMORY to flush, flagged borrowed, NOT persisted, no banner yet.
        assert!(
            core.api.has_bearer(),
            "foreign token kept in-memory to flush the backlog"
        );
        assert!(
            core.borrowed_token.load(Relaxed),
            "foreign token is flagged borrowed"
        );
        assert!(
            !core.sync_status().unwrap().auth_paused,
            "no banner while flushing"
        );
        let persisted = core
            .session
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .and_then(|s| s.token.clone());
        assert!(
            persisted.is_none(),
            "a FOREIGN token must never be persisted (no restart resurrection)"
        );

        // Queue is caught up (empty) → the drain invalidates the borrowed token and
        // requires Sara to relogin under her own account.
        core.drain_outbox().await.unwrap();
        assert!(
            !core.api.has_bearer(),
            "borrowed token invalidated once the backlog is flushed"
        );
        assert!(!core.borrowed_token.load(Relaxed));
        assert!(
            core.auth_paused.load(Relaxed),
            "re-login park latched after a borrowed flush"
        );
        // Surfaced only once online (re-auth needs the server to mint a JWT).
        core.set_online(true);
        assert!(
            core.sync_status().unwrap().auth_paused,
            "re-login required after a borrowed flush, prompted once online"
        );
    }

    #[test]
    fn unlock_offline_expired_prior_token_requires_relogin() {
        let core = offline_core_with_bundle();
        let now = core.corrected_now().timestamp();
        // Prior token is Sara's OWN but EXPIRED.
        install_prior_token(&core, TELLER_BB, now - 3600);
        core.unlock_offline("Sara".into(), "1234".into(), BRANCH_1.into())
            .unwrap();
        assert!(!core.api.has_bearer(), "an expired token is dropped");
        assert!(
            core.auth_paused.load(std::sync::atomic::Ordering::Relaxed),
            "an expired cached JWT parks the queue internally"
        );
        // The prompt stays suppressed while offline (an offline unlock IS
        // offline) — re-auth needs the server; the restore edge resurfaces it.
        assert!(
            !core.sync_status().unwrap().auth_paused,
            "no re-login banner while unreachable"
        );
        core.set_online(true);
        assert!(
            core.sync_status().unwrap().auth_paused,
            "the re-login banner surfaces once connectivity is confirmed"
        );
    }

    #[test]
    fn unlock_offline_no_prior_token_holds_quietly() {
        let core = offline_core_with_bundle();
        // No prior session/token at all (a genuine first offline unlock).
        core.unlock_offline("Sara".into(), "1234".into(), BRANCH_1.into())
            .unwrap();
        assert!(!core.api.has_bearer(), "no token to use");
        assert!(!core
            .borrowed_token
            .load(std::sync::atomic::Ordering::Relaxed));
        assert!(
            !core.sync_status().unwrap().auth_paused,
            "no banner on a fresh offline unlock (nothing expired)"
        );
    }
}

// ── Reservations & floor plan (host operations) ───────────────────────────────
// View types + conversions live in `reservations.rs`; these exported methods are
// here so they can reach MadarCore's private `api` + session via `self`. These
// are LIVE host actions (not offline outbox ops) — direct calls to the backend.
#[cfg_attr(feature = "uniffi-ffi", uniffi::export(async_runtime = "tokio"))]
impl MadarCore {
    /// Floor sections for the signed-in branch (dashboard-authored geometry).
    pub async fn list_floor_sections(
        &self,
    ) -> Result<Vec<reservations::FloorSectionView>, CoreError> {
        use madar_api::apis::reservations_api;
        let branch_id = self.reservations_branch()?;
        let rows = reservations_api::list_sections(
            &self.api.config(),
            reservations_api::ListSectionsParams { branch_id },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(rows.into_iter().map(Into::into).collect())
    }

    /// Tables (geometry + live status) for the signed-in branch.
    pub async fn list_floor_tables(&self) -> Result<Vec<reservations::FloorTableView>, CoreError> {
        use madar_api::apis::reservations_api;
        let branch_id = self.reservations_branch()?;
        let rows = reservations_api::list_floor_tables(
            &self.api.config(),
            reservations_api::ListFloorTablesParams { branch_id },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(rows.into_iter().map(Into::into).collect())
    }

    /// Move an open ticket to another table (the "switch table" action). Frees the
    /// old table, occupies the new one, and keeps the booking assignment in sync.
    pub async fn move_ticket_to_table(
        &self,
        ticket_id: String,
        table_id: String,
    ) -> Result<(), CoreError> {
        use madar_api::apis::open_tickets_api;
        let tid = reservations::parse_uuid("table_id", &table_id)?;
        open_tickets_api::move_ticket_table(
            &self.api.config(),
            open_tickets_api::MoveTicketTableParams {
                id: ticket_id,
                move_ticket_table_request: madar_api::models::MoveTicketTableRequest::new(tid),
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(())
    }
}

// ── Bookings at service time ─────────────────────────────────────────────────
#[cfg_attr(feature = "uniffi-ffi", uniffi::export(async_runtime = "tokio"))]
impl MadarCore {
    /// Pull today's active bookings (the arrivals list) into the offline cache.
    /// Best-effort like `refresh_floor`: offline / 403 leaves the cache as is.
    /// Queued seat / no-show answers stay applied on top.
    pub async fn refresh_arrivals(&self) -> Result<(), CoreError> {
        use madar_api::apis::bookings_api;
        let Ok(branch_id) = self.session_branch_id() else {
            return Ok(());
        };
        let date = self.service_date_today();
        let rows = match bookings_api::list_bookings(
            &self.api.config(),
            bookings_api::ListBookingsParams {
                branch_id,
                date: Some(date),
                from: None,
                to: None,
                active: Some(true),
                status: None,
            },
        )
        .await
        {
            Ok(rows) => rows,
            Err(_) => return Ok(()),
        };
        let list: Vec<bookings::BookingView> = rows.into_iter().map(Into::into).collect();
        bookings::save_arrivals(&self.store, &list)?;
        self.reapply_pending_booking_ops();
        Ok(())
    }

    /// Today's active bookings from the cache, earliest first.
    pub fn list_arrivals(&self) -> Result<Vec<bookings::BookingView>, CoreError> {
        let mut list = bookings::load_arrivals(&self.store)?;
        list.sort_by(|a, b| a.starts_at.cmp(&b.starts_at));
        Ok(list)
    }

    /// The party arrived: mark the booking seated (optionally on another
    /// table). Optimistic-local + queued; the ticket the waiter fires next
    /// carries the booking id and links itself server-side.
    pub fn seat_booking(
        &self,
        booking_id: String,
        table_id: Option<String>,
    ) -> Result<(), CoreError> {
        bookings::set_status_local(&self.store, &booking_id, "seated")?;
        held::set_booking_status_local(&self.store, &booking_id, "seated")?;
        let request = match table_id {
            Some(t) => serde_json::json!({ "table_ids": [t] }),
            None => serde_json::json!({}),
        };
        let cmd = bookings::SeatBookingCommand {
            booking_id: booking_id.clone(),
            request,
        };
        self.enqueue_held_op(
            "seat_booking",
            format!("booking-seat:{booking_id}"),
            &serde_json::to_string(&cmd)?,
        )
    }

    /// The party never came: release the table. Optimistic-local + queued.
    pub fn no_show_booking(&self, booking_id: String) -> Result<(), CoreError> {
        bookings::set_status_local(&self.store, &booking_id, "no_show")?;
        held::set_booking_status_local(&self.store, &booking_id, "no_show")?;
        let cmd = bookings::NoShowBookingCommand {
            booking_id: booking_id.clone(),
        };
        self.enqueue_held_op(
            "no_show_booking",
            format!("booking-no-show:{booking_id}"),
            &serde_json::to_string(&cmd)?,
        )
    }

    /// Today's service date (`YYYY-MM-DD`) in the branch zone, 05:00 → 05:00
    /// like the backend, so a 00:30 booking still belongs to tonight.
    fn service_date_today(&self) -> String {
        use chrono::Timelike;
        let tz = timefmt::branch_tz(&self.store);
        let now = self.corrected_now().with_timezone(&tz);
        let date = if now.hour() < 5 {
            now.date_naive() - chrono::Duration::days(1)
        } else {
            now.date_naive()
        };
        date.format("%Y-%m-%d").to_string()
    }
}

// Non-exported helper: the signed-in branch id, required for reservations calls.
impl MadarCore {
    fn reservations_branch(&self) -> Result<String, CoreError> {
        let (_, branch) = self.org_branch()?;
        branch.ok_or_else(|| CoreError::Validation {
            field: "branch_id".into(),
            detail: "no branch selected in this session".into(),
        })
    }
}

// ── Staff (employee self-service) surface ────────────────────────────────────
// Plain, NON-uniffi-exported methods consumed ONLY by the staff FRB crate
// (`madar-frb-staff`). Kept off the uniffi surface and off `madar-frb` so
// neither the POS natives nor the teller binary carry an HR surface.
//
// Every method here is ONLINE-ONLY and deliberately so. Clocking in is a claim
// about where and when someone was; letting it queue in the outbox would mean
// accepting a timestamp and a location the device chose, which is exactly what
// the geofence exists to prevent. A failed check-in must be visibly failed.
impl MadarCore {
    /// Employee sign-in. Same email/password path as the dashboard: no device
    /// pin, no shift, no offline bundle.
    pub async fn staff_sign_in(
        &self,
        email: String,
        password: String,
    ) -> Result<session::SessionSnapshot, CoreError> {
        self.dashboard_sign_in(email, password, None).await
    }

    /// The home screen: today's business date, the open record, what is rostered,
    /// and whether the buttons should be live.
    pub async fn staff_today(&self) -> Result<staff::TodayView, CoreError> {
        use madar_api::apis::staff_api;
        let t = staff_api::my_today(&self.api.config())
            .await
            .map_err(net::map_api_error)?;
        Ok(staff::today_view(t))
    }

    /// Clock in at `branch_id` from the device's current position.
    ///
    /// The coordinates are EVIDENCE, not a decision: the server measures the
    /// distance itself and refuses the punch when it falls outside the branch's
    /// fence. A refusal surfaces as a `CoreError` carrying the server's own
    /// wording (which includes the measured distance), so the host can show it
    /// verbatim rather than inventing a message.
    pub async fn staff_check_in(
        &self,
        branch_id: String,
        latitude: Option<f64>,
        longitude: Option<f64>,
    ) -> Result<staff::AttendanceRecordView, CoreError> {
        use madar_api::apis::staff_api;
        let branch = uuid::Uuid::parse_str(&branch_id).map_err(|_| CoreError::Validation {
            field: "branch_id".into(),
            detail: "not a valid id".into(),
        })?;
        let mut body = madar_api::models::CheckInRequest::new(branch);
        body.latitude = latitude.map(Some);
        body.longitude = longitude.map(Some);
        let rec = staff_api::check_in(
            &self.api.config(),
            staff_api::CheckInParams {
                check_in_request: body,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(staff::record_view(rec))
    }

    /// Clock out of whichever record is currently open. The server picks it —
    /// the app never names a record, so it cannot close the wrong one.
    pub async fn staff_check_out(
        &self,
        latitude: Option<f64>,
        longitude: Option<f64>,
    ) -> Result<staff::AttendanceRecordView, CoreError> {
        use madar_api::apis::staff_api;
        let mut body = madar_api::models::CheckOutRequest::new();
        body.latitude = latitude.map(Some);
        body.longitude = longitude.map(Some);
        let rec = staff_api::check_out(
            &self.api.config(),
            staff_api::CheckOutParams {
                check_out_request: body,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(staff::record_view(rec))
    }

    /// The employee's own attendance over `[from, to]` (ISO `yyyy-mm-dd`).
    pub async fn staff_attendance(
        &self,
        from: String,
        to: String,
    ) -> Result<Vec<staff::AttendanceRecordView>, CoreError> {
        use madar_api::apis::staff_api;
        let parse = |s: &str, field: &str| {
            chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").map_err(|_| CoreError::Validation {
                field: field.to_string(),
                detail: "expected yyyy-mm-dd".into(),
            })
        };
        let rows = staff_api::my_attendance(
            &self.api.config(),
            staff_api::MyAttendanceParams {
                from: parse(&from, "from")?,
                to: parse(&to, "to")?,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(rows.into_iter().map(staff::record_view).collect())
    }

    /// Own requests of every kind, newest first.
    pub async fn staff_requests(&self) -> Result<Vec<staff::StaffRequestView>, CoreError> {
        use madar_api::apis::staff_api;
        let rows = staff_api::my_requests(&self.api.config())
            .await
            .map_err(net::map_api_error)?;
        Ok(rows.into_iter().map(staff::request_view).collect())
    }

    /// File a request of any kind. It lands as `pending`; a manager decides.
    ///
    /// The server validates the SHAPE per kind (a late arrival needs a time, a
    /// permission needs both ends, and so on) and returns a message naming what
    /// is missing — so the app does not carry a second copy of those rules.
    /// `from_time` / `to_time` are `HH:MM` in the branch's local clock.
    #[allow(clippy::too_many_arguments)]
    pub async fn staff_create_request(
        &self,
        kind: String,
        on_date: String,
        end_date: Option<String>,
        from_time: Option<String>,
        to_time: Option<String>,
        leave_type_id: Option<String>,
        is_half_day: bool,
        title: Option<String>,
        reason: Option<String>,
        // `correction` only — the record whose punch is wrong.
        attendance_record_id: Option<String>,
    ) -> Result<staff::StaffRequestView, CoreError> {
        use madar_api::apis::staff_api;
        let parse_date = |s: &str, field: &str| {
            chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").map_err(|_| CoreError::Validation {
                field: field.to_string(),
                detail: "expected yyyy-mm-dd".into(),
            })
        };
        // The wire wants `HH:MM:SS`; the UI works in minutes.
        let with_seconds = |t: String| if t.len() == 5 { format!("{t}:00") } else { t };

        let mut body =
            madar_api::models::CreateStaffRequest::new(kind, parse_date(&on_date, "on_date")?);
        body.end_date = end_date
            .map(|d| parse_date(&d, "end_date"))
            .transpose()?
            .map(Some);
        body.from_time = from_time.map(with_seconds).map(Some);
        body.to_time = to_time.map(with_seconds).map(Some);
        body.leave_type_id = leave_type_id
            .map(|id| {
                uuid::Uuid::parse_str(&id).map_err(|_| CoreError::Validation {
                    field: "leave_type_id".into(),
                    detail: "not a valid id".into(),
                })
            })
            .transpose()?
            .map(Some);
        body.is_half_day = Some(Some(is_half_day));
        body.title = title.map(Some);
        body.reason = reason.map(Some);
        body.attendance_record_id = attendance_record_id
            .map(|id| {
                uuid::Uuid::parse_str(&id).map_err(|_| CoreError::Validation {
                    field: "attendance_record_id".into(),
                    detail: "not a valid id".into(),
                })
            })
            .transpose()?
            .map(Some);

        let row = staff_api::create_my_request(
            &self.api.config(),
            staff_api::CreateMyRequestParams {
                create_staff_request: body,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(staff::request_view(row))
    }

    /// Remaining entitlement per leave type for `year` (defaults to the current
    /// calendar year server-side when `None`).
    pub async fn staff_leave_balances(
        &self,
        year: Option<i64>,
    ) -> Result<Vec<staff::LeaveBalanceView>, CoreError> {
        use madar_api::apis::staff_api;
        let rows = staff_api::my_leave_balances(
            &self.api.config(),
            staff_api::MyLeaveBalancesParams {
                user_id: None,
                year: year.map(|y| y as i32),
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(rows.into_iter().map(staff::leave_balance_view).collect())
    }

    /// The employee's own payslips. Only finalised periods are returned, so a
    /// half-finished regeneration never flashes numbers at them.
    pub async fn staff_payslips(&self) -> Result<Vec<staff::PayslipView>, CoreError> {
        use madar_api::apis::staff_api;
        let rows = staff_api::my_payslips(&self.api.config())
            .await
            .map_err(net::map_api_error)?;
        Ok(rows.into_iter().map(staff::payslip_view).collect())
    }

    /// The employee's own salary advances and what is still owed.
    pub async fn staff_advances(&self) -> Result<Vec<staff::SalaryAdvanceView>, CoreError> {
        use madar_api::apis::staff_api;
        let rows = staff_api::my_advances(&self.api.config())
            .await
            .map_err(net::map_api_error)?;
        Ok(rows.into_iter().map(staff::advance_view).collect())
    }

    /// Request a salary advance, repaid over `installments` months. Lands as
    /// `pending` until someone with payroll access approves it.
    pub async fn staff_request_advance(
        &self,
        amount_minor: i64,
        installments: i64,
        reason: Option<String>,
    ) -> Result<staff::SalaryAdvanceView, CoreError> {
        use madar_api::apis::staff_api;
        if amount_minor <= 0 {
            return Err(CoreError::Validation {
                field: "amount".into(),
                detail: "must be greater than zero".into(),
            });
        }
        let mut body = madar_api::models::CreateAdvanceRequest::new(amount_minor);
        body.installments = Some(Some(installments.max(1) as i32));
        body.reason = reason.map(Some);
        let row = staff_api::create_my_advance(
            &self.api.config(),
            staff_api::CreateMyAdvanceParams {
                create_advance_request: body,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(staff::advance_view(row))
    }

    // ── Manager surface ──────────────────────────────────────────
    //
    // Every one of these is permission-checked SERVER-SIDE. The app hides the
    // tabs when `has_permission` says no, but that is a courtesy: a forged
    // client reaching these endpoints still gets a 403.

    /// The employee's own roster for a date range — the Shifts tab.
    pub async fn staff_schedule(
        &self,
        from: String,
        to: String,
    ) -> Result<Vec<staff::ScheduledDayView>, CoreError> {
        use madar_api::apis::staff_api;
        let rows = staff_api::my_schedule(
            &self.api.config(),
            staff_api::MyScheduleParams {
                from: parse_ymd(&from, "from")?,
                to: parse_ymd(&to, "to")?,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(rows.into_iter().map(staff::scheduled_day_view).collect())
    }

    /// Who is in, late, absent or on leave right now.
    pub async fn manager_team_presence(
        &self,
        branch_id: Option<String>,
    ) -> Result<staff::TeamPresenceView, CoreError> {
        use madar_api::apis::staff_api;
        let row = staff_api::team_presence(
            &self.api.config(),
            staff_api::TeamPresenceParams { branch_id },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(staff::team_presence_view(row))
    }

    /// The approvals queue, or any slice of it.
    pub async fn manager_requests(
        &self,
        status: Option<String>,
        kind: Option<String>,
    ) -> Result<Vec<staff::StaffRequestView>, CoreError> {
        use madar_api::apis::staff_api;
        let rows = staff_api::list_requests(
            &self.api.config(),
            staff_api::ListRequestsParams {
                user_id: None,
                kind,
                status,
                from: None,
                to: None,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(rows.into_iter().map(staff::request_view).collect())
    }

    /// Approve or reject a request. `is_paid` only bites on `excuse` and
    /// `early_departure`; the server resolves it from the org default otherwise.
    pub async fn manager_decide_request(
        &self,
        request_id: String,
        approve: bool,
        note: Option<String>,
        is_paid: Option<bool>,
    ) -> Result<staff::StaffRequestView, CoreError> {
        use madar_api::apis::staff_api;
        let mut body = madar_api::models::RequestDecision::new(
            if approve { "approved" } else { "rejected" }.to_string(),
        );
        body.note = note.map(Some);
        body.is_paid = is_paid.map(Some);
        let row = staff_api::decide_request(
            &self.api.config(),
            staff_api::DecideRequestParams {
                id: request_id,
                request_decision: body,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(staff::request_view(row))
    }

    /// The roster, optionally filtered by a search string.
    pub async fn manager_employees(
        &self,
        search: Option<String>,
    ) -> Result<Vec<staff::EmployeeView>, CoreError> {
        use madar_api::apis::staff_api;
        let rows = staff_api::list_employees(
            &self.api.config(),
            staff_api::ListEmployeesParams {
                department_id: None,
                employment_status: None,
                search,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(rows.into_iter().map(staff::employee_view).collect())
    }

    /// Payroll periods, newest first.
    pub async fn manager_payroll_periods(
        &self,
    ) -> Result<Vec<staff::PayrollPeriodView>, CoreError> {
        use madar_api::apis::staff_api;
        let rows = staff_api::list_periods(&self.api.config())
            .await
            .map_err(net::map_api_error)?;
        Ok(rows.into_iter().map(staff::period_view).collect())
    }

    /// What generating this period WOULD pay — the run screen's table.
    ///
    /// Read-only: this is the same computation the generator runs, so the
    /// figures a manager approves are the figures that get written.
    pub async fn manager_payroll_preview(
        &self,
        period_id: String,
    ) -> Result<Vec<staff::PayrollLineView>, CoreError> {
        use madar_api::apis::staff_api;
        let rows = staff_api::preview_period(
            &self.api.config(),
            staff_api::PreviewPeriodParams { id: period_id },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(rows.into_iter().map(staff::payroll_line_view).collect())
    }

    /// Approve the run: generate the payslips and freeze the figures.
    pub async fn manager_payroll_generate(&self, period_id: String) -> Result<i64, CoreError> {
        use madar_api::apis::staff_api;
        let slips = staff_api::generate_period(
            &self.api.config(),
            staff_api::GeneratePeriodParams { id: period_id },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(slips.len() as i64)
    }

    /// Move a generated period to `paid` (or `closed`).
    pub async fn manager_payroll_set_status(
        &self,
        period_id: String,
        status: String,
    ) -> Result<staff::PayrollPeriodView, CoreError> {
        use madar_api::apis::staff_api;
        let row = staff_api::set_period_status(
            &self.api.config(),
            staff_api::SetPeriodStatusParams {
                id: period_id,
                period_status_request: madar_api::models::PeriodStatusRequest::new(status),
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(staff::period_view(row))
    }

    // ── Payroll adjustments ──────────────────────────────────────

    /// Bonuses or deductions over a window, newest first.
    ///
    /// `base_salary_minor` resolves percent-of-base rows into piastres — pass
    /// the employee's base when listing one person, 0 when listing everyone
    /// (a percentage row then reads as 0 rather than as a wrong number).
    pub async fn manager_adjustments(
        &self,
        deductions: bool,
        user_id: Option<String>,
        from: Option<String>,
        to: Option<String>,
        base_salary_minor: i64,
    ) -> Result<Vec<staff::AdjustmentView>, CoreError> {
        use madar_api::apis::staff_api;
        let from = from.map(|d| parse_ymd(&d, "from")).transpose()?;
        let to = to.map(|d| parse_ymd(&d, "to")).transpose()?;
        // `map_err` inside each arm: the generated client gives every operation
        // its own error enum, so the two branches have no common type until
        // they are both mapped to `CoreError`.
        let rows = if deductions {
            staff_api::list_deductions(
                &self.api.config(),
                staff_api::ListDeductionsParams { user_id, from, to },
            )
            .await
            .map_err(net::map_api_error)?
        } else {
            staff_api::list_bonuses(
                &self.api.config(),
                staff_api::ListBonusesParams { user_id, from, to },
            )
            .await
            .map_err(net::map_api_error)?
        };
        Ok(rows
            .into_iter()
            .map(|r| staff::adjustment_view(r, base_salary_minor))
            .collect())
    }

    /// Add a bonus or a manual deduction.
    pub async fn manager_create_adjustment(
        &self,
        deductions: bool,
        user_id: String,
        amount_minor: i64,
        reason: String,
        effective_date: String,
    ) -> Result<staff::AdjustmentView, CoreError> {
        use madar_api::apis::staff_api;
        if amount_minor <= 0 {
            return Err(CoreError::Validation {
                field: "amount".into(),
                detail: "must be greater than zero".into(),
            });
        }
        if reason.trim().is_empty() {
            return Err(CoreError::Validation {
                field: "reason".into(),
                detail: "required".into(),
            });
        }
        let user = uuid::Uuid::parse_str(&user_id).map_err(|_| CoreError::Validation {
            field: "user_id".into(),
            detail: "not a valid id".into(),
        })?;
        let mut body = madar_api::models::CreateAdjustmentRequest::new(
            parse_ymd(&effective_date, "effective_date")?,
            reason,
            user,
        );
        body.amount_piastres = Some(Some(amount_minor));

        let row = if deductions {
            staff_api::create_deduction(
                &self.api.config(),
                staff_api::CreateDeductionParams {
                    create_adjustment_request: body,
                },
            )
            .await
            .map_err(net::map_api_error)?
        } else {
            staff_api::create_bonus(
                &self.api.config(),
                staff_api::CreateBonusParams {
                    create_adjustment_request: body,
                },
            )
            .await
            .map_err(net::map_api_error)?
        };
        Ok(staff::adjustment_view(row, 0))
    }

    /// Delete a hand-entered adjustment. The server refuses on rule-generated
    /// rows — those are waived or overridden, never erased.
    pub async fn manager_delete_adjustment(
        &self,
        deductions: bool,
        id: String,
    ) -> Result<(), CoreError> {
        use madar_api::apis::staff_api;
        if deductions {
            staff_api::delete_deduction(
                &self.api.config(),
                staff_api::DeleteDeductionParams { id },
            )
            .await
            .map_err(net::map_api_error)?;
        } else {
            staff_api::delete_bonus(&self.api.config(), staff_api::DeleteBonusParams { id })
                .await
                .map_err(net::map_api_error)?;
        }
        Ok(())
    }

    /// Charge a different figure than the rule computed. The original is kept.
    pub async fn manager_override_deduction(
        &self,
        id: String,
        amount_minor: i64,
        reason: String,
    ) -> Result<staff::AdjustmentView, CoreError> {
        use madar_api::apis::staff_api;
        if reason.trim().is_empty() {
            return Err(CoreError::Validation {
                field: "reason".into(),
                detail: "required — an override with no reason is indistinguishable from a mistake"
                    .into(),
            });
        }
        let row = staff_api::override_deduction(
            &self.api.config(),
            staff_api::OverrideDeductionParams {
                id,
                override_deduction_request: madar_api::models::OverrideDeductionRequest::new(
                    amount_minor,
                    reason,
                ),
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(staff::adjustment_view(row, 0))
    }

    /// Cancel a deduction without erasing it — it stays visible, payroll skips it.
    pub async fn manager_waive_deduction(
        &self,
        id: String,
        reason: String,
    ) -> Result<staff::AdjustmentView, CoreError> {
        use madar_api::apis::staff_api;
        if reason.trim().is_empty() {
            return Err(CoreError::Validation {
                field: "reason".into(),
                detail: "required".into(),
            });
        }
        let row = staff_api::waive_deduction(
            &self.api.config(),
            staff_api::WaiveDeductionParams {
                id,
                waive_deduction_request: madar_api::models::WaiveDeductionRequest::new(reason),
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(staff::adjustment_view(row, 0))
    }

    /// Every salary advance in the org.
    pub async fn manager_advances(&self) -> Result<Vec<staff::SalaryAdvanceView>, CoreError> {
        use madar_api::apis::staff_api;
        let rows = staff_api::list_advances(
            &self.api.config(),
            staff_api::ListAdvancesParams {
                user_id: None,
                from: None,
                to: None,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(rows.into_iter().map(staff::advance_view).collect())
    }

    /// Approve or reject an advance request.
    pub async fn manager_decide_advance(
        &self,
        advance_id: String,
        approve: bool,
        note: Option<String>,
    ) -> Result<staff::SalaryAdvanceView, CoreError> {
        use madar_api::apis::staff_api;
        let mut body = madar_api::models::AdvanceDecision::new(
            if approve { "approved" } else { "rejected" }.to_string(),
        );
        body.note = note.map(Some);
        let row = staff_api::decide_advance(
            &self.api.config(),
            staff_api::DecideAdvanceParams {
                id: advance_id,
                advance_decision: body,
            },
        )
        .await
        .map_err(net::map_api_error)?;
        Ok(staff::advance_view(row))
    }
}

/// `yyyy-mm-dd` → a date, with a field-named error the UI can show.
fn parse_ymd(value: &str, field: &str) -> Result<chrono::NaiveDate, CoreError> {
    chrono::NaiveDate::parse_from_str(value, "%Y-%m-%d").map_err(|_| CoreError::Validation {
        field: field.to_string(),
        detail: "expected yyyy-mm-dd".into(),
    })
}
