# Implementation Plan: Flutter FFI Bridge for madar-core via flutter_rust_bridge v2

**Verified against FRB docs (cjycode.com/flutter_rust_bridge, current 2.13.0-beta line) and FRB source (frb_rust):** Dart closures arrive in Rust as `impl Fn(...) -> DartFnFuture<T>` (decoded to `'static` closures capturing a `DartOpaque` handle); `StreamSink<T>` is `Send + Sync`, can be "held forever" after the function returns, and `add_error` propagates to Dart stream error handlers; external-crate types are handled via `#[frb(mirror(...))]` on a publicly re-exported type, **but mirror does not support enums with struct variants**; custom error enums in `Result<T, E>` become typed Dart exceptions; panics become `PanicException`; FRB's default async runtime is its own multi-threaded `tokio::runtime::Runtime` (`SimpleAsyncRuntime`, customizable via `BaseAsyncRuntime`). Verified against the repo: madar-core does **not** own a tokio runtime — it relies on ambient runtime context (`tokio::spawn` in `realtime.rs:290`, `lan.rs`), which today is UniFFI's `async_runtime = "tokio"`; under FRB it will be FRB's runtime. `ComputedRecipeLineView.quantity` is `f64` (not Decimal — the exploration report was wrong on that one point); no `u64`, chrono, uuid, or Decimal types cross the FFI surface (all timestamps are RFC3339 `String`, ids are `String`).

---

## 1. `madar-frb` Crate Layout

### 1.1 Files

```
rust-core/crates/madar-frb/
├── Cargo.toml
└── src/
    ├── lib.rs                  # mod api; mod frb_generated (generated);
    ├── frb_generated.rs        # FRB codegen output (committed)
    └── api/
        ├── mod.rs
        ├── bridge.rs           # MadarBridge opaque handle: constructor + lifecycle + misc
        ├── error.rs            # MadarError (re-declared CoreError) + From impl
        ├── types.rs            # #[frb(mirror)] declarations + re-exports of core records/enums
        ├── routes.rs           # Re-declared AppRoute + conversion
        ├── vault.rs            # TokenStore adapter (StreamSink-backed)
        ├── realtime.rs         # EventListener/RealtimePlayer adapters + stream methods
        ├── session.rs          # impl MadarBridge: auth/session methods
        ├── catalog.rs          # impl MadarBridge: menu/categories/addons/bundles/discounts
        ├── cart.rs             # impl MadarBridge: cart + drafts
        ├── shift.rs            # impl MadarBridge: shift + cash movements + reports
        ├── orders.rs           # impl MadarBridge: checkout, order history, void
        ├── tickets.rs          # impl MadarBridge: waiter open tickets
        ├── kds.rs              # impl MadarBridge: kitchen display
        ├── delivery.rs         # impl MadarBridge: delivery queue + settings
        ├── device.rs           # impl MadarBridge: device config + LAN relay
        ├── printing.rs         # impl MadarBridge: render_receipt/send_to_printer/drawer kick
        └── sync.rs             # impl MadarBridge: outbox, sync_now, diagnostics, i18n, timefmt
```

Workspace `rust-core/Cargo.toml` gains `"crates/madar-frb"` in `members`. madar-core is untouched.

### 1.2 Cargo.toml

```toml
[package]
name = "madar-frb"
edition.workspace = true
version.workspace = true
publish.workspace = true
license.workspace = true

[lib]
crate-type = ["lib", "cdylib", "staticlib"]   # cdylib → Android .so; staticlib → iOS
name = "madar_frb"

[dependencies]
madar-core = { path = "../madar-core" }
flutter_rust_bridge = { version = "=2.x.y", features = ["rust-async"] }  # EXACT pin, must equal codegen + Dart pub version
```

No tokio dependency needed directly (adapters are sink-based, see §2); madar-core brings it transitively. The `uniffi::setup_scaffolding!()` symbols from madar-core will be compiled into the `madar_frb` cdylib — harmless dead exports (see §9 risks).

### 1.3 Type strategy: mirror where possible, re-declare where not

Three buckets:

**(a) Mirrored records/enums (~38 types)** — everything that is a plain struct with all-pub fields or a fieldless enum. In `api/types.rs`:

```rust
pub use madar_core::{SessionSnapshot, MadarConfig, ShiftView, CartLineView, /* … */};
pub use madar_core::session::LoginMode;

#[frb(mirror(SessionSnapshot))]
pub struct _SessionSnapshot {
    pub user_id: String,
    pub display_name: String,
    // … exact field-for-field copy; codegen emits accessors against the REAL type,
    // so any drift in madar-core is a compile error in madar-frb (the safety net).
}

#[frb(mirror(LoginMode))]
pub enum _LoginMode { Pin, Email }
```

Requirements confirmed by docs: the real type must be publicly re-exported from madar-frb, fields must be `pub` (they are — uniffi::Record requires it), and the mirror must match exactly. This gives zero-conversion pass-through: wrapper method signatures use the real `madar_core` types directly.

Mirrorable: all `*View` records, `CartTotals`, `MadarConfig`, `LoginRequest`, `SessionSnapshot`, `AddonSelection`, `BundleComponentSelection`, `RealtimeEvent`, and unit enums `LoginMode`, `PrinterBrand`, `TimeStyle`.

**(b) Re-declared enums with struct variants (mirror unsupported)** — exactly two:

- `AppRoute` (`KitchenDisplay { station_id: String }`) → re-declare a local `AppRoute` in `api/routes.rs` (FRB natively supports struct-variant enums → Dart sealed class) plus a private `From<madar_core::AppRoute>` conversion.
- `CoreError` → becomes `MadarError` (§1.5).

**(c) Verify one edge case early:** `ShiftReportView.payments_summary` is a `HashMap<String, i64>` — FRB translates maps natively; confirm in the spike. If any record embeds a type FRB rejects, that single record drops from bucket (a) to a re-declared struct + `From` impl.

### 1.4 The main object: `#[frb(opaque)]` struct, not raw RustOpaque

```rust
// api/bridge.rs
#[frb(opaque)]
pub struct MadarBridge {
    inner: Arc<MadarCore>,
}

impl MadarBridge {
    pub fn new(config: MadarConfig) -> Result<MadarBridge, MadarError> {
        Ok(MadarBridge { inner: MadarCore::new(config)? })
    }
    // ~90 one-line delegating methods spread across the api/*.rs impl blocks
    pub fn app_route(&self) -> AppRoute { self.inner.app_route().into() }
    pub async fn checkout(&self, /* … */) -> Result<CheckoutView, MadarError> {
        self.inner.checkout(/* … */).await.map_err(Into::into)
    }
}
```

Rationale over alternatives:
- **Opaque struct with methods** → Dart gets a real `MadarBridge` class with methods; the `Arc<MadarCore>` never crosses the boundary; FRB wraps the opaque in its own lock but every method is `&self` (read lock) so calls stay concurrent — matching the core's internal Arc/RwLock design.
- **Raw `RustOpaque<Arc<MadarCore>>` + free functions**: works but produces an ugly Dart API (free functions taking a handle) — rejected.
- **`static OnceLock<Arc<MadarCore>>` singleton + free functions**: simplest, but bakes the one-instance assumption into Rust and complicates tests (parallel cores with distinct db paths). Keep as fallback if opaque-method codegen misbehaves.

Constructor stays a non-`#[frb(sync)]` method (SQLite open + migrations run on FRB's thread pool → Dart `Future`).

### 1.5 Error mapping

Re-declare in `api/error.rs`:

```rust
#[derive(Debug, thiserror::Error)]
pub enum MadarError {
    #[error("offline: {detail}")]       Offline { detail: String },
    #[error("auth: {detail}")]          Unauthenticated { detail: String },
    #[error("forbidden")]               Forbidden { resource: String, action: String },
    #[error("invalid {field}")]         Validation { field: String, detail: String },
    #[error("server {status}")]         Server { status: u16, code: String, detail: String },
    #[error("transient: {detail}")]     Transient { detail: String },
    #[error("internal: {detail}")]      Internal { detail: String },
}
impl From<madar_core::CoreError> for MadarError { /* 1:1 variant map */ }
```

Every wrapper method returns `Result<T, MadarError>`. FRB (verified) generates a Dart sealed class `MadarError` with typed variants and **throws it as an exception**; Dart repositories `on MadarError catch (e)` and pattern-match variants (`MadarError_Offline`, etc.) to drive the localized-message mapping from §8 (using `tr()` keys, same scheme as Kotlin/Swift hosts). Rust panics surface as `PanicException` — repositories treat that as `Internal`.

### 1.6 Sync vs async exposure policy

- Default: everything is generated **async in Dart** (sync Rust fns run on FRB's thread pool). This covers all SQLite-touching "sync" reads (cart, outbox, catalog).
- Mark `#[frb(sync)]` ONLY on cheap pure/lock-read functions needed during widget build: `tr`, `is_rtl`, `locale`, `format_time`, `category_style`, `core_version`, `ffi_surface_version`, `clock_skew_minutes`, `device_code`, `is_authenticated`, `current_session`, `app_route`. These read in-memory `RwLock` state only — sub-microsecond, safe on the UI thread.

---

## 2. Callback Strategy (per host trait)

FRB v2 offers three inversion mechanisms: (i) Dart closures as args (`impl Fn(...) -> DartFnFuture<T>`), (ii) `StreamSink<T>` params, (iii) `DartOpaque`. **FRB does NOT support Dart classes implementing Rust traits** (traits guide is Rust→Dart only) — so all three core callback traits are satisfied by **Rust adapter structs inside madar-frb** that implement madar-core's traits and forward to Dart via one of (i)/(ii).

### 2.1 `TokenStore` → `StreamSink<VaultCommand>` (recommended)

```rust
// api/vault.rs
pub enum VaultCommand { Save { blob: Vec<u8> }, Clear }

struct SinkTokenStore(StreamSink<VaultCommand>);
impl madar_core::session::TokenStore for SinkTokenStore {
    fn save_blob(&self, blob: Vec<u8>) { let _ = self.0.add(VaultCommand::Save { blob }); }
    fn clear_blob(&self)               { let _ = self.0.add(VaultCommand::Clear); }
}

impl MadarBridge {
    pub fn token_vault_stream(&self, sink: StreamSink<VaultCommand>) {
        self.inner.set_token_store(Box::new(SinkTokenStore(sink)));
    }
}
```

Dart listens and writes to `flutter_secure_storage` (Keychain/Keystore).

**Tradeoff vs Dart closures:** the trait methods are **sync** `fn(&self)` and are invoked from both async contexts (login on FRB's tokio runtime) *and* sync contexts (`logout()` runs on FRB's thread pool with **no ambient tokio runtime**). A closure adapter would need to `spawn` the `DartFnFuture`, requiring a captured `tokio::runtime::Handle` — extra machinery and a panic hazard if wired from a non-runtime thread. `StreamSink::add` is sync, runtime-free, and buffered by the Dart stream controller until listened, so the cold-boot ordering (attach vault stream → `restore_session`) has no race. **Cost:** persistence becomes fire-and-forget across the event loop — a hard kill immediately after login could lose the blob (next cold boot needs online login). Same durability class as today's Kotlin fire-to-main-thread behavior; accepted, documented in the repo layer ("persist immediately on event, no debounce").

### 2.2 `EventListener` → `StreamSink<RealtimeMessage>` (clear winner)

```rust
// api/realtime.rs
pub enum RealtimeMessage {
    Event { event_type: String, data: String },
    ConnectionChanged { connected: bool },
}

struct SinkListener(StreamSink<RealtimeMessage>);
impl madar_core::realtime::EventListener for SinkListener {
    fn on_event(&self, e: RealtimeEvent) { let _ = self.0.add(RealtimeMessage::Event { event_type: e.event_type, data: e.data }); }
    fn on_connection_changed(&self, c: bool) { let _ = self.0.add(RealtimeMessage::ConnectionChanged { connected: c }); }
}
```

The core requires listeners to "return promptly" (they run on the SSE supervisor task) — `sink.add` is a non-blocking enqueue, which is exactly that. A closure-based listener would force an `.await` (or a spawn) per event on the supervisor task; strictly worse. Folding `on_connection_changed` into the same stream preserves the core's event ordering guarantees in one Dart subscription.

### 2.3 `RealtimePlayer` → `StreamSink<AlertCommand>`

```rust
pub enum AlertCommand {
    Ping,
    Notify { title: String, body: String, tag: String },
    Haptic,
}
struct SinkPlayer(StreamSink<AlertCommand>);
impl madar_core::realtime::RealtimePlayer for SinkPlayer { /* forward each primitive */ }
```

The core's deliberate `play_ping → post_notification → haptic` ordering is preserved by the single FIFO stream. Dart side maps: `Ping` → `audioplayers` asset, `Notify` → `flutter_local_notifications` (tag → notification id via stable hash, replace-on-repost preserved), `Haptic` → `HapticFeedback.mediumImpact()`. **Tradeoff:** closures would allow the core to await completion of the primitive — but the trait is sync fire-and-forget by design ("calls must return promptly"), so streams lose nothing.

### 2.4 Wiring `start_realtime`

```rust
impl MadarBridge {
    pub async fn start_realtime(
        &self,
        events: StreamSink<RealtimeMessage>,
        alerts: StreamSink<AlertCommand>,
    ) -> Result<(), MadarError> {
        self.inner
            .start_realtime(Box::new(SinkListener(events)), Box::new(SinkPlayer(alerts)))
            .await.map_err(Into::into)
    }
    pub fn unsubscribe_realtime(&self) { self.inner.unsubscribe_realtime() }
}
```

`subscribe_realtime` (low-level, explicit topics) gets the same treatment with only the `events` sink — expose it for completeness/tests. Printer and LAN transports need **no** Dart glue: TCP printing and mDNS/UDP relay are done natively inside the core (iOS Bonjour glue via `set_device_lan_hub`/manual peers only, which is a plain method — no callback).

---

## 3. Realtime Events → Dart Stream: Lifecycle

- **Signature:** `Stream<RealtimeMessage> startRealtimeEvents(...)` — FRB turns each `StreamSink` param into a returned Dart `Stream`; the two-sink method above generates a method returning one stream per sink (FRB supports multiple `StreamSink` params; if the generated shape is awkward, split into `attach_alert_player(sink)` + `start_realtime(events_sink)` as two calls — decide in the spike).
- **Subscribe:** repository calls `start_realtime` once after login (and on connectivity-regain — core makes it idempotent: re-call is a no-op while a subscription lives).
- **Cancel:** Dart-side `StreamSubscription.cancel()` alone does NOT stop the Rust SSE supervisor — the sinks stay held by the core's `unified_listener`. Cancellation protocol: repository calls `bridge.unsubscribeRealtime()` (tears down the supervisor + drops the listener Arc → sinks dropped) and *then* cancels the Dart subscription. After teardown, `sink.add` returns `Err` in Rust — adapters already ignore the result (`let _ =`), so a late LAN event during teardown is safely dropped.
- **Backpressure:** none in FRB (unbounded buffering into the Dart stream controller — confirmed no backpressure mechanism in docs). Acceptable: event rate is human-scale POS traffic and the core already dedups alerts (512-entry tag set). The repository listener must stay cheap (decode `event_type`, invalidate a Riverpod provider) — no heavy work per event, mirroring the "return promptly" rule one level up.
- **Errors:** the supervisor never pushes stream errors (reconnects internally; 401 silently stops). `ConnectionChanged{false}` is the UI's only signal; the repository maps it to the offline banner state and a `retry` affordance that calls `start_realtime` again post-login.
- **Hot restart (critical):** Rust statics and the running supervisor survive Flutter hot restart while the Dart stream controllers die. On every `RustBridge.init()` the Dart side must call `unsubscribe_realtime()` before (re)attaching vault/realtime sinks, making cold-boot and hot-restart paths identical.

---

## 4. Async Model

- **Mapping:** every `async fn` on `MadarBridge` → Dart `Future<T>` (FRB default). Every plain `fn` → Dart `Future<T>` executed on FRB's worker thread pool, except the `#[frb(sync)]` allowlist in §1.6.
- **Executor:** FRB's `SimpleAsyncRuntime` = its own multi-threaded `tokio::runtime::Runtime` (verified in `frb_rust/src/rust_async/io.rs`). madar-core has **no runtime of its own** — it calls `tokio::spawn` from within its exported async fns (verified `realtime.rs:290`, `lan.rs:439+`). Consequences:
  - `start_realtime`, `subscribe_realtime`, `lan_start`, and the outbox drain futures all execute — and spawn their long-lived supervisor tasks — on FRB's tokio runtime. That runtime is a lazily-created process-lifetime static: tasks survive as long as the process. Functionally identical to the UniFFI `async_runtime = "tokio"` arrangement today.
  - **Rule for the wrapper:** any bridge method that ultimately calls `tokio::spawn` (the two realtime entries, `lan_start`, and every outbox-first mutator that triggers a drain) MUST be `async fn` in madar-frb (so it runs inside the runtime), never `#[frb(sync)]` and never a plain `fn` (thread-pool threads have no runtime context → `tokio::spawn` panics). madar-core's own signatures already enforce this (they're `async`), so the wrapper just preserves asyncness 1:1.
  - The UniFFI-managed runtime in madar-core is only entered via UniFFI entry points, which Flutter never calls — no dual-runtime contention. (Whether uniffi 0.28 even instantiates its runtime lazily is moot; it stays idle.)
- **Spike checks (§7):** (a) an async method that internally spawns (`start_realtime`) works and its supervisor keeps delivering events after the method returns; (b) two concurrent async calls on the same `MadarBridge` don't deadlock on FRB's opaque lock (all methods `&self` → shared read lock — should be concurrent; verify); (c) `logout()` (sync, called from thread pool) doesn't hit a runtime-context panic anywhere in the core path.

---

## 5. Codegen Setup

- **Dart package:** `flutter-app/packages/rust_bridge/` (plain Dart/Flutter plugin package).
- **Config** `flutter-app/packages/rust_bridge/flutter_rust_bridge.yaml`:

```yaml
rust_input: crate::api                     # scan only madar-frb's api module
rust_root: ../../../rust-core/crates/madar-frb
dart_output: lib/src/generated
dart_entrypoint_class_name: RustBridge
enable_lifetime: false
```

- **Generated Dart** lands in `packages/rust_bridge/lib/src/generated/` (committed to git, like the Kotlin/Swift bindings are today). `lib/rust_bridge.dart` exports ONLY the repository layer + the record types repositories return; `src/generated/**` is not exported (enforced by convention + a lint rule banning `src/generated` imports outside the package).
- **build_runner:** FRB codegen is NOT a build_runner builder — keep it fully out of `build.yaml`. If the repo layer later uses freezed/riverpod_generator, `dart run build_runner build` runs independently and never touches `src/generated`.
- **Regeneration script** `tool/gen-flutter-bindings.sh` (sibling of `rust-core/tool/build-android.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../flutter-app/packages/rust_bridge"
flutter_rust_bridge_codegen generate            # reads flutter_rust_bridge.yaml
cargo check -p madar-frb --manifest-path ../../../rust-core/Cargo.toml
```

`--watch` variant for dev. **Version pinning:** `flutter_rust_bridge` in Cargo.toml, `flutter_rust_bridge` in pubspec.yaml, and the installed `flutter_rust_bridge_codegen` must all be the same exact version — pin all three and record the version in the script header; add a CI assert.

---

## 6. Native Build Integration

Use **Cargokit** (FRB's recommended path for existing apps; the native-assets path is still gated on Flutter build hooks maturing). Bootstrap by running `flutter_rust_bridge_codegen integrate` in a scratch app and porting the generated `rust_builder` plugin, or vendor Cargokit directly:

- `packages/rust_bridge/` becomes an FFI plugin (`pluginClass: none`, `ffiPlugin: true`) with `android/`, `ios/`, `macos/` shims whose only job is invoking Cargokit against `rust-core/crates/madar-frb` (`manifest-dir` in `cargokit.yaml` pointing at the workspace member — Cargokit supports crates inside an external workspace; the artifact name is `madar_frb`).
- **Android:** Cargokit's gradle plugin builds via the NDK per the app's `abiFilters`. Ship the same ABI set the Kotlin app proves out in `rust-core/tool/build-android.sh`: **arm64-v8a, armeabi-v7a, x86_64** (the report's "x86" isn't in the actual script; skip it). Requirements carried over from the existing script: `ANDROID_NDK_HOME`, and prefer NDK r27+ for 16 KB page-size alignment. cargo-ndk is NOT needed (Cargokit drives cargo + linker env itself), but keep `build-android.sh` alive for the Kotlin app.
- **iOS:** Cargokit's podspec `script_phase` builds the `staticlib` for `aarch64-apple-ios` / `aarch64-apple-ios-sim` (+ `x86_64-apple-ios` sim) and links it into Runner — replacing what `rust-core/tool/build-ios.sh` does manually for swift-app (that script keeps serving swift-app; no UniFFI bindgen step exists in the Flutter path at all).
- The workspace `[profile.release]` (lto, codegen-units=1, strip) already applies to madar-frb for free. The TLS stack (rustls+ring, no OpenSSL) and bundled SQLite are proven to cross-compile by the existing Android/iOS builds — zero new native deps from madar-frb.
- Add `tool/build-flutter-android.sh` / rely on plain `flutter build apk` once Cargokit is wired (Cargokit runs inside gradle/Xcode; no pre-step needed apart from codegen).

---

## 7. "Hello Core" Spike (Definition of Done)

One Flutter screen + one integration test in `packages/rust_bridge/example/`, proving every mechanism end-to-end. Exact core methods:

1. **Construct:** `MadarBridge.new(MadarConfig(dbPath: <app-docs>/spike.db, baseUrl: <dev backend>, environment: "dev", locale: "en"))` → Future resolves; then assert `ffi_surface_version() == 4` and print `core_version()`.
2. **Sync reads:** `greet("Flutter")`, `app_route()` → must decode the re-declared sealed `AppRoute` as `AppRoute_DeviceSetup`; `tr("login.sign_in")` via `#[frb(sync)]` (call it inside a widget `build` to prove sync FFI), `set_locale("ar")` + `is_rtl()` → true.
3. **Async method:** `refresh_connectivity()` → `Future<bool>` (works unauthenticated; exercises reqwest on FRB's runtime). Also `pending_outbox_count()` → 0.
4. **Error mapping:** call `open_shift(0, null)` while signed out → expect Dart `MadarError_Unauthenticated` caught by type.
5. **Vault round-trip:** attach `token_vault_stream()`; `set_device_branch(...)` + `login(LoginRequest(mode: LoginMode.pin, name/pin/branchId ...))` against the dev backend → receive `VaultCommand.Save(blob)` on the stream; persist to `flutter_secure_storage`; dispose bridge, construct a second `MadarBridge`, `restore_session(blob)` → non-null `SessionSnapshot` with same `user_id`.
6. **Realtime stream:** after login, `start_realtime(events, alerts)` → receive `RealtimeMessage.ConnectionChanged(connected: true)` within a timeout; optionally fire a ticket from the Kotlin app / backend to observe an `Event`; then `unsubscribe_realtime()` and assert the Dart stream goes quiet. Hot-restart the app and repeat to validate §3's re-init protocol.
7. **Concurrency check:** `Future.wait([list_menu_items(), cart_lines(), sync_status()])` — no deadlock on the opaque lock.

Spike passes ⇒ all nine risk mechanisms (opaque methods, mirror decode, struct-variant enums, error enum as exception, sync annotation, StreamSink lifetime, tokio spawn-from-FRB, vault ordering, hot restart) are de-risked before writing the remaining ~80 delegations.

## 8. Repository Layer (`packages/rust_bridge/lib/src/repositories/`)

One handle-owner plus ten domain repositories, each holding the `MadarBridge` (constructor-injected). Grouping follows the core's impl-block domains, not screen shapes:

| Repository | Wraps (from the inventory) |
|---|---|
| `CoreLifecycle` | new/from_env, restore_session, token_vault_stream, ffi_surface_version assert, app_route, locale/tr/is_rtl/format_time, recent_logs/clear_logs |
| `AuthRepository` | sign_in, login, unlock_offline, logout, current_session, is_authenticated, has_permission, list_branches |
| `DeviceRepository` | device_config, set_device_branch/till/station/printer/code, start_reconfigure, clear_device, set_device_lan_hub, lan_start/stop/peer_count/branch_has_open_till |
| `CatalogRepository` | refresh_catalog, list_menu_items/categories/addon_catalog/payment_methods/discounts, available_bundles, list_item_addons, compute_recipe, category_style |
| `CartRepository` | all cart_*, hold_cart, drafts, cart_totals |
| `ShiftRepository` | open/close/refresh/current_shift, suggested_opening_cash_minor, shift_report(_for), record/list cash movements, shift_stats, list_tills |
| `OrdersRepository` | checkout, list_shift_orders, list_orders_for_shift, search_orders, order_detail, order_receipt_view, void_order, recover_orphaned_orders |
| `TicketsRepository` | fire_ticket, add_ticket_round, settle_ticket, void_ticket, list_open_tickets, get_ticket + reservations/floor methods |
| `KdsRepository` | kds_list_stations, kds_list, kds_bump/unbump |
| `DeliveryRepository` | all delivery_* |
| `SyncRepository` | sync_now, retry_outbox, refresh_connectivity, list_outbox, discard_outbox_item, sync_status, clock_skew_minutes |
| `RealtimeRepository` | start_realtime/unsubscribe (owns the two StreamSubscriptions, exposes `Stream<RealtimeMessage>` broadcast + performs AlertCommand primitives via injected `AlertPlayer` abstraction) |
| `PrintingRepository` | render_receipt/render_shift_report/render_order_receipt, print_to_device, send_to_printer, cash_drawer_kick |

Repository responsibilities (and nothing more): (1) translate `MadarError` → a small Dart failure type carrying the localized message built from `tr()` keys per the §8-i18n scheme in the core report; (2) own stream lifecycles (vault, realtime); (3) keep generated types in, domain types out where renaming helps (mostly pass-through — the `*View` records are already UI-shaped). **No caching, no state** — the core is the state.

**Riverpod v3 attach points (named, not designed):** `packages/rust_bridge` exposes only the repo classes; the app layer defines `coreProvider = FutureProvider<MadarBridge>` (construct + vault attach + restore_session), `Provider<XxxRepository>` per repo derived from it, and a `StreamProvider<RealtimeMessage>` over `RealtimeRepository`. Everything above that (route notifier reacting to `app_route()`, per-screen state) is out of scope here.

## 9. Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| 1 | **UniFFI + FRB in one cdylib** — madar-core's `uniffi::setup_scaffolding!()` symbols land in `madar_frb.so` (dead code, +size; two binding runtimes linked) | Benign functionally (Flutter never calls UniFFI entry points; UniFFI's tokio runtime is lazily unused). Accept for v1; later add a `ffi-uniffi` default-on feature in madar-core if size matters (that IS a core change — defer). |
| 2 | **Mirror drift** when core records evolve | Mirror mismatches are compile errors in madar-frb (verified doc claim); CI job builds madar-frb + runs codegen + `git diff --exit-code` on generated Dart. Keep asserting `ffi_surface_version()` at Dart init. |
| 3 | **Struct-variant enums unmirrable** (`AppRoute`, `CoreError`) | Re-declare + `From` conversions (§1.3b, §1.5) — 2 types only, unit-tested conversions. |
| 4 | **Dart closure long-term storage** (if StreamSink approach needs a closure fallback) | Decoded closures are `'static` capturing `DartOpaque` (verified in frb_generated source) but the extra `+ Send + Sync` bound in user signatures needs a spike check. Primary design avoids it entirely (all three callbacks are sinks). |
| 5 | **tokio spawn outside runtime** (sync wrapper method → panics) | Rule in §4: spawn-capable paths stay `async`; spike test 7 + `logout()` check. |
| 6 | **Hot restart leaks/stale sinks** (Rust supervisor survives, Dart controllers die) | Idempotent Dart init: `unsubscribe_realtime()` before re-attaching sinks; core's `start_realtime` replace semantics handle the rest. |
| 7 | **Vault durability** (sink-based save is fire-and-forget) | Persist immediately in the vault listener, no debounce; worst case = re-login online (same failure class as device wipe). If unacceptable later, switch `TokenStore` alone to a Dart closure awaited via a captured runtime `Handle`. |
| 8 | **i64/u64 width** | Surface uses i64/u32/u16/i32/f64 only (verified, incl. `quantity: f64` — no Decimal). Dart native int is 64-bit; no web target. `HashMap<String,i64>` (payments_summary) verified in spike. |
| 9 | **Type-name collisions** — mirrored names (`SessionSnapshot` etc.) identical to Kotlin/Swift binding names | Different artifacts/namespaces per app; within Dart, all generated types live under `src/generated` and are re-exported once. No action needed. |
| 10 | **FRB version churn** (2.13 still beta-line) | Triple-pin exact version (§5); upgrade deliberately with codegen re-run + spike re-test. |
| 11 | **Opaque lock contention** — FRB wraps `MadarBridge` in a RwLock; a long-running async method could in theory starve `&mut self` calls | No wrapper method takes `&mut self` (core is interior-mutable) → all read locks, fully concurrent. Enforce "never `&mut self`" as a crate lint/review rule. |
| 12 | **Codegen can't parse something** (e.g. multiple `StreamSink` params in one fn, impls spread across modules) | Spike covers both; fallbacks: split into two attach methods; consolidate impl blocks into fewer files. |

### Implementation sequence

1. Scaffold `madar-frb` (Cargo.toml, error.rs, bridge.rs with 6 spike methods, vault.rs, realtime.rs) + workspace member.
2. Scaffold `flutter-app/packages/rust_bridge` + Cargokit shims + `flutter_rust_bridge.yaml` + `tool/gen-flutter-bindings.sh`.
3. Run the §7 spike on iOS sim + Android emulator; resolve risks 4/5/8/12.
4. Add mirrors for all records (types.rs) + the remaining ~80 delegating methods, domain file by domain file, codegen after each.
5. Write repositories + the localized error mapper; CI: codegen-diff + `cargo check -p madar-frb` + spike integration test.

### Critical Files for Implementation
- /Users/shawket/Desktop/madar-pos/rust-core/crates/madar-frb/Cargo.toml (new — wrapper crate root)
- /Users/shawket/Desktop/madar-pos/rust-core/crates/madar-frb/src/api/bridge.rs (new — MadarBridge opaque + delegations)
- /Users/shawket/Desktop/madar-pos/rust-core/crates/madar-frb/src/api/realtime.rs (new — StreamSink adapters for EventListener/RealtimePlayer)
- /Users/shawket/Desktop/madar-pos/flutter-app/packages/rust_bridge/flutter_rust_bridge.yaml (new — codegen config)
- /Users/shawket/Desktop/madar-pos/rust-core/crates/madar-core/src/lib.rs (reference — the 90-method surface, `start_realtime` at line 1592, `set_token_store` at 312; unchanged)
- /Users/shawket/Desktop/madar-pos/rust-core/tool/build-android.sh and build-ios.sh (reference — proven target/ABI/NDK setup to mirror in Cargokit)