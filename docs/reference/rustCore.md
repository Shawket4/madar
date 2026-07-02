Based on my thorough exploration of the madar-core Rust crate, I now have sufficient information to produce the comprehensive API inventory. Let me compile the final report:

---

# Madar POS Core - Complete API Inventory for Flutter Bridge

## Executive Summary

The `madar-core` crate is a unified Rust business logic layer for the Madar POS system, exposed via UniFFI to Kotlin/Swift apps. It uses **procmacro UniFFI** (no `.udl` file), tokio async, embedded SQLite, and runs its own outbox/sync engine. The crate has **90+ exported methods** organized as impl blocks on the `MadarCore` object, plus ~40 record/enum types. The entire business logic lives here; hosts are UI + platform glue only.

---

## 1. Main Entry Object: MadarCore

### Constructor Signatures

```rust
// pub fn new(config: MadarConfig) -> Result<Arc<Self>, CoreError>
// Creates with explicit config (db_path, base_url, environment, locale)
// Opens + migrates SQLite store, builds HTTP client, session starts empty

// pub fn from_env() -> Result<Arc<Self>, CoreError>
// Constructs from .env defaults (in-memory store until host supplies db_path)
```

### Configuration Record

```rust
#[derive(uniffi::Record, Clone, Debug)]
pub struct MadarConfig {
    pub db_path: String,              // App-private SQLite path (empty = in-memory)
    pub base_url: String,             // API server URL
    pub environment: String,          // "prod" | "staging" | "dev"
    pub locale: String,               // Initial UI locale (en/ar)
}
```

### Core Internals (Sync-Safe via Arc/RwLock/Mutex)

- **store**: `Arc<store::Store>` — embedded SQLite, single-writer behind Mutex
- **session**: `RwLock<Option<SessionState>>` — live session (or None = signed out)
- **token_store**: `Mutex<Option<Box<dyn TokenStore>>>` — host's secure vault (Keychain/Keystore)
- **api**: `net::ApiClient` — HTTP client with live bearer token
- **realtime**: `Mutex<Option<StreamHandle>>` — one SSE subscription per device
- **lan**: `Mutex<Option<LanRelay>>` — LAN offline relay (Phase E)
- **unified_listener**: `Arc<Mutex<Option<Arc<dyn EventListener>>>>` — shared event sink (cloud + LAN)
- **clock_skew_secs**: `Arc<AtomicI64>` — server-vs-device skew in seconds
- **offline_probe_fails**: `AtomicU32` — consecutive unconfirmed /health failures
- **auth_paused**: `AtomicBool` — outbox parked on 401 (sticky until re-login)
- **borrowed_token**: `AtomicBool` — live bearer is a foreign teller's token (use-once)
- **drain_lock**: `tokio::sync::Mutex<()>` — serializes outbox drain
- **locale**: `Arc<RwLock<String>>` — runtime-changeable UI locale
- **diag**: `Mutex<VecDeque<DiagEntry>>` — ring buffer of 200 diagnostic log lines

---

## 2. Exported Methods (90+ total)

### 2.1 Sync/Non-Async Queries (Safe for FFI)

#### Core Metadata
- `core_version() -> String` — Crate semver
- `ffi_surface_version() -> u32` — FFI contract version (currently **4**)
- `greet(name: String) -> String` — Smoke test

#### Session State (Sync Reads)
- `is_authenticated() -> bool` — Session exists in memory
- `current_session() -> Option<SessionSnapshot>` — Cached live session snapshot
- `has_permission(resource: String, action: String) -> bool` — ACL check (optimistic offline)
- `base_url() -> String` — API base URL from config
- `environment() -> String` — Environment name from config
- `db_path() -> String` — SQLite path from config
- `version() -> String` — Core version
- `pending_outbox_count() -> Result<u32, CoreError>` — Ops still queued/inflight
- `locale() -> String` — Active UI locale
- `is_rtl() -> bool` — Whether current locale is right-to-left
- `clock_skew_minutes() -> i32` — Server-vs-device skew in minutes (for banner)

#### Device Binding
- `device_config() -> DeviceConfigView` — Current device binding (branch/till/station/printer)
- `device_code() -> String` — This device's managed code (T1, W2, K1, etc.)
- `set_device_code(code: String)` — Update device code (sanitized to A-Z0-9, max 6 chars)

#### Realtime Subscriptions
- `is_realtime_subscribed() -> bool` — Whether SSE supervisor task is alive
- `unsubscribe_realtime()` — Tear down current subscription (idempotent)

#### LAN Relay Status
- `lan_active() -> bool` — Whether LAN relay is running
- `lan_peer_count() -> u32` — Live discovered peers + manual hubs
- `lan_branch_has_open_till() -> bool` — "Is a till advertising an open shift right now?"

#### Shift & Routing
- `current_shift() -> Result<Option<ShiftView>, CoreError>` — Device's cached open/closed shift
- `suggested_opening_cash_minor() -> Result<i64, CoreError>` — Previous shift's declared closing (for continuity)
- `app_route() -> AppRoute` — Screen to show (DeviceSetup/Login/OpenShift/Order/KitchenDisplay/WaiterTickets)

#### Localization
- `tr(key: String) -> String` — Localized UI string for key (en/ar; fallback to en then key)
- `set_locale(locale: String)` — Change active locale at runtime; host re-renders

#### Catalog Reads (Serve Local Mirror, Succeed Offline)
- `list_menu_items() -> Result<Vec<MenuItemView>, CoreError>` — All active menu items
- `list_categories() -> Result<Vec<CategoryView>, CoreError>` — Category list
- `list_addon_catalog() -> Result<Vec<AddonItemView>, CoreError>` — All addons with ingredients
- `available_bundles(now_rfc3339: String) -> Result<Vec<BundleView>, CoreError>` — Active bundles at time (branch-local)
- `list_payment_methods() -> Result<Vec<PaymentMethodView>, CoreError>`
- `list_discounts() -> Result<Vec<DiscountView>, CoreError>`
- `category_style(name: String, dark: bool) -> CatStyleView` — Icon + gradient (no network)

#### Cart Operations (Client-Side, Offline-Safe, KV-Persisted)
- `cart_lines() -> Result<Vec<CartLineView>, CoreError>` — Current cart lines
- `cart_add(item_id, name, unit_price_minor) -> Result<Vec<CartLineView>, CoreError>` — Add/merge unit
- `cart_add_configured(item_id, size_label, addons, optional_field_ids, qty, notes) -> Result<Vec<CartLineView>, CoreError>` — Add configured line (core resolves addon/size prices)
- `cart_add_bundle(bundle_id, components, qty) -> Result<Vec<CartLineView>, CoreError>` — Add bundle with component selections
- `list_item_addons(item_id) -> Result<Vec<ItemAddonView>, CoreError>` — Charged addon prices for item
- `compute_recipe(item_id, size_label, addons, optional_field_ids) -> Result<Vec<ComputedRecipeLineView>, CoreError>` — Live recipe (base + swaps + addos + optionals)
- `cart_set_qty(item_id, qty) -> Result<Vec<CartLineView>, CoreError>` — Set line quantity
- `cart_remove(item_id) -> Result<Vec<CartLineView>, CoreError>` — Remove (undo-able)
- `cart_restore_removed() -> Result<Vec<CartLineView>, CoreError>` — Undo last remove
- `cart_clear() -> Result<(), CoreError>` — Empty cart
- `cart_set_discount(discount_id) -> Result<(), CoreError>` — Apply discount
- `cart_clear_discount() -> Result<(), CoreError>` — Remove discount
- `cart_discount_id() -> Result<Option<String>, CoreError>` — Current discount id
- `cart_totals() -> Result<CartTotals, CoreError>` — Priced summary (subtotal/discount/tax/total; uses session org tax rate)
- `hold_cart(name: String) -> Result<(), CoreError>` — Park as draft
- `list_drafts() -> Result<Vec<DraftView>, CoreError>` — Parked drafts (newest first)
- `restore_draft(id: String) -> Result<Vec<CartLineView>, CoreError>` — Restore draft to cart
- `discard_draft(id: String) -> Result<(), CoreError>` — Delete draft

#### Outbox Visibility & Control
- `list_outbox() -> Result<Vec<OutboxItemView>, CoreError>` — Queued + failed ops (oldest first)
- `discard_outbox_item(id: String) -> Result<bool, CoreError>` — Discard a DEAD command
- `sync_status() -> Result<SyncStatusView, CoreError>` — Counts + online + auth_paused for action-bar chip
- `recent_logs() -> Vec<DiagLogView>` — Diagnostics feed (newest first, max 200)
- `clear_logs()` — Wipe diagnostics

#### Rendering & Printing
- `render_receipt(receipt, store_name, currency, width, brand) -> Vec<u8>` — Receipt bytes (rasterized to 1-bit bitmap, ESC/POS wrapped)
- `render_shift_report(report, store_name, currency, width, brand) -> Vec<u8>` — Z-report bytes
- `cash_drawer_kick(brand: PrinterBrand) -> Vec<u8>` — Cash-drawer kick bytes for brand

#### Time & Format
- `format_time(rfc3339: String, style: TimeStyle) -> String` — Display timestamp in BRANCH timezone (not device)
- `branch_timezone() -> String` — IANA tz name (cached at login, Cairo fallback)
- `shift_stats(orders: Vec<OrderSummaryView>) -> ShiftStatsView` — Stats from host-loaded orders (no network)

---

### 2.2 Async Methods (Tokio Runtime Required)

#### Authentication (Sync Entry Points)
- `async login(req: LoginRequest) -> Result<SessionSnapshot, CoreError>` — Online login (PIN or email); mints bearer, mirrors permissions, caches bundle
- `async sign_in(req: LoginRequest) -> Result<SessionSnapshot, CoreError>` — One-call: try online; fallback to offline unlock if network down + PIN mode
- `unlock_offline(name, pin, branch_id) -> Result<SessionSnapshot, CoreError>` — **Sync**, offline PIN verify (argon2id against bundle)
- `logout(wipe_outbox: bool) -> Result<(), CoreError>` — **Sync**, sign out + tear down realtime

#### Catalog Refresh (Online)
- `async refresh_catalog() -> Result<(), CoreError>` — Fetch branch-effective menu + categories + addons + bundles + payments + discounts; mirror to store
- `async list_branches() -> Result<Vec<BranchView>, CoreError>` — Org's active branches (manager session, device setup picker)
- `async cache_numbering_context()` — Internal: cache branch tz + code + logo for offline order_ref minting

#### Shift Lifecycle (Outbox-First)
- `async open_shift(opening_cash_minor: i64, opening_reason: Option<String>) -> Result<ShiftView, CoreError>` — Enqueue open, drain, return view
- `async close_shift(closing_cash_minor: i64, closing_reason: Option<String>) -> Result<(), CoreError>` — Enqueue close, drain
- `async refresh_shift() -> Result<Option<ShiftView>, CoreError>` — Fetch THIS teller's current shift (server-scoped), cache it
- `async shift_report() -> Result<ShiftReportView, CoreError>` — Compute Z-report from synced orders

#### Cash Drawer (Outbox-First)
- `async record_cash_movement(shift_id, type, amount_minor, reason, timestamp) -> Result<CashMovementView, CoreError>` — Enqueue movement
- `async list_cash_movements() -> Result<Vec<CashMovementView>, CoreError>` — Shift's cash in/out (synced + queued)

#### Checkout (Outbox-First, Offline-First Pricing)
- `async checkout(payment_method_id, amount_tendered_minor, tip_minor, tip_method_id, discount, discount_value) -> Result<CheckoutView, CoreError>` — FIRE cart as order; client-auth prices; enqueue; return receipt view
  - *Returns: order_id, order_ref, receipt_view with lines, totals, payment details*
  - *Handles: stock warnings (oversold), dead dependencies waiting*

#### Sync & Connectivity (Manual Triggers)
- `async sync_now() -> Result<(), CoreError>` — Force immediate outbox drain (no-op if in-flight; single-flighted)
- `async retry_outbox() -> Result<(), CoreError>` — Retry all DEAD commands (by moving back to pending)
- `async refresh_connectivity() -> bool` — Ping /health; update online banner; return true if online
- `async recover_orphaned_orders() -> Result<u32, CoreError>` — Fallback: re-point orders blocked by dead open_shift

#### Order History (Online, Write-Through Cached)
- `async list_shift_orders() -> Result<Vec<OrderSummaryView>, CoreError>` — Orders for THIS teller's current shift (synced + queued)
- `async list_orders_for_shift(shift_id: String) -> Result<Vec<OrderSummaryView>, CoreError>` — Orders for a specific shift
- `async search_orders(query: String, limit: Option<i32>) -> Result<Vec<OrderSummaryView>, CoreError>` — Search by order_ref / customer / etc.
- `async order_detail(order_id: String) -> Result<OrderDetailView, CoreError>` — Full order (lines with addons, payments, delivery, etc.)
- `async order_receipt_view(order_id: String) -> Result<ReceiptView, CoreError>` — Receipt DTO for reprint
- `async render_order_receipt(order_id, store_name, currency, brand) -> Result<Vec<u8>, CoreError>` — Receipt bytes (reprint)
- `async shift_report_for(shift_id: String) -> Result<ShiftReportView, CoreError>` — Z-report for a closed shift

#### Order Mutations
- `async void_order(order_id, reason) -> Result<bool, CoreError>` — Void queued or synced order (outbox-first; returns true if still pending)

#### Printer I/O (Sync Writes, Async Connect)
- `async print_to_device(bytes: Vec<u8>) -> Result<(), CoreError>` — Print to configured device (local host/port)
- `async send_to_printer(host, port, bytes) -> Result<(), CoreError>` — Print to explicit host:port (3 retry attempts, 4s each)

#### Realtime Subscriptions (Tokio Tasks)
- `async subscribe_realtime(branch_id, topics, listener) -> ()` — **Sync entry**, open ONE SSE for topics; supervisor reconnects on drops
- `async start_realtime(listener, player) -> Result<(), CoreError>` — **Sync entry**, high-level: open session-level subscription (core owns topics-per-role); wrap listener in alerting wrapper; wire player for pings/notifications

#### LAN Relay (Phase E, Tokio)
- `async lan_start() -> Result<(), CoreError>` — Start embedded relay server + discovery (mDNS + UDP) + hub wire
- `lan_stop()` — **Sync**, stop + tear down relay (idempotent)
- `set_device_lan_hub(hub: Option<String>) -> Result<(), CoreError>` — **Sync**, persist manual hub address + register if relay running

#### Waiter Open Tickets (Fire-Now-Pay-Later, Outbox-First)
- `async fire_ticket(table_id, customer_name, notes, guest_count) -> Result<TicketFiredView, CoreError>` — FIRE cart as open ticket (round 1); enqueue; LAN-publish
- `async add_ticket_round(ticket_id) -> Result<TicketFiredView, CoreError>` — Add round to existing ticket (depends on fire)
- `async void_ticket(ticket_id, reason) -> Result<bool, CoreError>` — Void open ticket
- `async settle_ticket(ticket_id, shift_id, payment_method_id, amount_tendered, tip, tip_method, discount_id, discount_type, discount_value) -> Result<bool, CoreError>` — Settle into paid order (outbox-first; depends on fire + shift open)
- `async list_open_tickets() -> Result<Vec<TicketView>, CoreError>` — Branch open/ready tickets (server + queued fires overlaid)
- `async get_ticket(ticket_id: String) -> Result<TicketView, CoreError>` — One open ticket by server id

#### Kitchen Display System (Outbox-First)
- `async kds_list_stations() -> Result<Vec<KdsStationView>, CoreError>` — Branch stations (cached)
- `async kds_list(station_id: Option<String>) -> Result<Vec<KdsTicketView>, CoreError>` — KDS feed (cached per station + LAN overlay + pending bumps)
- `async kds_bump(item_id: String) -> Result<(), CoreError>` — Bump line (outbox + drain + LAN-publish)
- `async kds_unbump(item_id: String) -> Result<(), CoreError>` — Unbump line

#### Tills
- `async list_tills() -> Result<Vec<TillView>, CoreError>` — Active tills (default first, cached)

#### Delivery Orders (Online, Manager/Teller)
- `async list_delivery_orders(status: Option<String>) -> Result<Vec<DeliveryOrderView>, CoreError>` — Branch queue (newest first, cached)
- `async delivery_order_detail(id: String) -> Result<DeliveryOrderView, CoreError>` — One delivery order
- `async delivery_set_status(id, status: String) -> Result<DeliveryOrderView, CoreError>` — Explicit wire status
- `async delivery_advance_status(id, current: String) -> Result<DeliveryOrderView, CoreError>` — Step forward (received→confirmed→…→delivered)
- `async delivery_set_prep_time(id, extra_minutes) -> Result<DeliveryOrderView, CoreError>` — Per-order prep buffer
- `async delivery_cancel(id, reason, restore_inventory) -> Result<DeliveryOrderView, CoreError>` — Cancel + log waste
- `async delivery_finalize(id, payment_method_id) -> Result<DeliveryFinalizeView, CoreError>` — Replay frozen snapshot as sale (on current shift)
- `async delivery_settings() -> Result<DeliverySettingsView, CoreError>` — Accepting overrides + channel status
- `async delivery_set_accepting(channel, mode) -> Result<DeliverySettingsView, CoreError>` — Set in_mall/outside to auto/open/closed

#### Reservations & Floor (Incomplete in Current Phase)
- `async list_floor_sections() -> Result<Vec<FloorSectionView>, CoreError>`
- `async list_floor_tables() -> Result<Vec<FloorTableView>, CoreError>`
- `async list_reservations() -> Result<Vec<ReservationView>, CoreError>`
- `async seat_reservation(reservation_id, table_id) -> Result<(), CoreError>`
- `async set_floor_table_status(table_id, status) -> Result<(), CoreError>`
- `async notify_reservation(reservation_id) -> Result<(), CoreError>`
- `async move_ticket_to_table(ticket_id, table_id) -> Result<(), CoreError>`

#### Device Management (Config Mutations, Sync)
- `set_device_branch(branch_id, branch_name) -> Result<(), CoreError>` — Bind device to branch
- `set_device_till(till_id: Option<String>) -> Result<(), CoreError>` — Bind till (None = branch default)
- `set_device_station(station_id: Option<String>) -> Result<(), CoreError>` — KDS device station
- `set_device_printer(host, port, brand) -> Result<(), CoreError>` — Receipt printer (epson/star)
- `start_reconfigure() -> Result<(), CoreError>` — Re-enter device setup (keeps binding)
- `clear_device() -> Result<(), CoreError>` — Wipe device config (factory reset)

#### Callback Installation (Sync, Must Call Early)
- `set_token_store(store: Box<dyn TokenStore>)` — Install host's secure vault (call right after new, before restore_session)

#### Session Restore (Sync, Cold-Boot)
- `restore_session(blob: Vec<u8>) -> Option<SessionSnapshot>` — Restore persisted session from host vault (returns Some if valid, None if corrupt/expired)

---

## 3. Exported Records & Enums

### Session/Auth Types
```rust
#[derive(uniffi::Enum)]
pub enum LoginMode { Pin, Email }

#[derive(uniffi::Record)]
pub struct LoginRequest {
    pub mode: LoginMode,
    pub name: Option<String>,           // Teller name (PIN)
    pub pin: Option<String>,
    pub branch_id: Option<String>,      // Device branch (PIN)
    pub email: Option<String>,          // Manager email
    pub password: Option<String>,
    pub org_id: Option<String>,         // Disambiguator (Email)
}

#[derive(uniffi::Record)]
pub struct SessionSnapshot {
    pub user_id: String,
    pub display_name: String,
    pub role: String,
    pub org_id: Option<String>,
    pub branch_id: Option<String>,
    pub currency_code: String,
    pub tax_rate: f64,
    pub online: bool,                   // false for offline-unlocked session
    pub permissions_loaded: bool,       // false until /auth/permissions mirrors
}

#[derive(uniffi::Record)]
pub struct BranchView {
    pub id: String,
    pub name: String,
    pub is_active: bool,
    pub org_logo_url: Option<String>,
}
```

### Device Config
```rust
#[derive(uniffi::Record)]
pub struct DeviceConfigView {
    pub branch_id: Option<String>,
    pub branch_name: Option<String>,
    pub till_id: Option<String>,
    pub station_id: Option<String>,     // KDS station
    pub printer_host: Option<String>,
    pub printer_port: Option<u16>,
    pub printer_brand: Option<String>,  // "epson" | "star"
    pub lan_hub: Option<String>,
    pub reconfiguring: bool,            // Currently mid-setup
}
```

### Route Enum
```rust
#[derive(uniffi::Enum, Clone, Debug, PartialEq, Eq)]
pub enum AppRoute {
    DeviceSetup,
    Login,
    OpenShift,
    Order,
    KitchenDisplay { station_id: String },
    WaiterTickets,
}
```

### Shift Types
```rust
#[derive(uniffi::Record)]
pub struct ShiftView {
    pub id: String,
    pub teller_id: String,
    pub teller_name: String,
    pub is_open: bool,
    pub opening_cash_minor: i64,
    pub opening_cash_was_edited: bool,
    pub opening_cash_edited_reason: Option<String>,
    pub opened_at: String,              // RFC3339
    pub closed_at: Option<String>,
    pub expected_cash_minor: i64,
    pub counted_cash_minor: Option<i64>,
    pub difference_minor: Option<i64>,
}

#[derive(uniffi::Record)]
pub struct ShiftReportView {
    pub shift_id: String,
    pub opened_at: String,
    pub closed_at: Option<String>,
    pub printed_at: String,
    pub total_collected_minor: i64,
    pub cash_in_minor: i64,             // Drawer additions
    pub cash_out_minor: i64,            // Drawer reductions
    pub orders: Vec<OrderLineView>,
    pub cash_moves: Vec<CashMovementView>,
    pub payments_summary: Map<String, i64>,
    // ... more fields
}

#[derive(uniffi::Record)]
pub struct CashMovementView {
    pub id: String,
    pub movement_type: String,          // "cash_in" | "cash_out"
    pub amount_minor: i64,
    pub reason: Option<String>,
    pub created_at: String,
}

#[derive(uniffi::Record)]
pub struct ShiftSummaryView {
    pub id: String,
    pub teller_name: String,
    pub status: String,                 // "open" | "closed"
    pub opened_at: String,
    pub closed_at: Option<String>,
}
```

### Cart Types
```rust
#[derive(uniffi::Record)]
pub struct CartLineView {
    pub item_id: String,
    pub name: String,
    pub unit_price_minor: i64,
    pub qty: i64,
    pub total_minor: i64,               // qty * unit_price
    pub size_label: Option<String>,
    pub addons: Vec<CartAddonView>,
    pub optional_fields: Vec<CartOptionalView>,
    pub notes: Option<String>,
}

#[derive(uniffi::Record)]
pub struct CartAddonView {
    pub addon_id: String,
    pub name: String,
    pub quantity: i64,
    pub charged_price_minor: i64,       // Swap delta or full
    pub is_swap: bool,
}

#[derive(uniffi::Record)]
pub struct CartOptionalView {
    pub field_id: String,
    pub name: String,
    pub selected_option_id: String,
    pub charged_price_minor: i64,
}

#[derive(uniffi::Record)]
pub struct AddonSelection {
    pub addon_id: String,
    pub quantity: i64,
}

#[derive(uniffi::Record)]
pub struct BundleComponentSelection {
    pub component_id: String,
    pub selected_item_id: String,
    pub size_label: Option<String>,
    pub addons: Vec<AddonSelection>,
    pub optional_field_ids: Vec<String>,
}

#[derive(uniffi::Record)]
pub struct CartTotals {
    pub subtotal_minor: i64,
    pub discount_minor: i64,
    pub tax_minor: i64,
    pub total_minor: i64,
}

#[derive(uniffi::Record)]
pub struct DraftView {
    pub id: String,
    pub name: String,
    pub created_at: String,             // RFC3339
}
```

### Menu Types
```rust
#[derive(uniffi::Record)]
pub struct MenuItemView {
    pub id: String,
    pub name: String,
    pub category_id: String,
    pub unit_price_minor: i64,
    pub sizes: Vec<MenuSizeView>,
    pub is_active: bool,
    pub description: Option<String>,
}

#[derive(uniffi::Record)]
pub struct MenuSizeView {
    pub label: String,
    pub unit_price_minor: i64,
    pub up_charge_minor: Option<i64>,
}

#[derive(uniffi::Record)]
pub struct CategoryView {
    pub id: String,
    pub name: String,
    pub display_order: i32,
    pub is_active: bool,
}

#[derive(uniffi::Record)]
pub struct AddonItemView {
    pub id: String,
    pub name: String,
    pub addon_type: String,             // Group for UI
    pub addon_type_label: Option<String>,
    pub base_price_minor: i64,
    pub is_swap: bool,
    pub is_active: bool,
    pub ingredients: Vec<IngredientView>,
}

#[derive(uniffi::Record)]
pub struct BundleView {
    pub id: String,
    pub name: String,
    pub price_minor: i64,
    pub components: Vec<BundleComponentView>,
}

#[derive(uniffi::Record)]
pub struct PaymentMethodView {
    pub id: String,
    pub name: String,
    pub is_active: bool,
}

#[derive(uniffi::Record)]
pub struct DiscountView {
    pub id: String,
    pub name: String,
    pub discount_type: String,          // "flat" | "percent"
    pub value: i32,
    pub is_active: bool,
}

#[derive(uniffi::Record)]
pub struct CatStyleView {
    pub icon: String,
    pub gradient_start: String,         // hex
    pub gradient_end: String,
}
```

### Checkout/Receipt Types
```rust
#[derive(uniffi::Record)]
pub struct CheckoutView {
    pub order_id: String,
    pub order_ref: Option<String>,      // e.g. "T1-26-001"
    pub receipt_view: ReceiptView,
    pub warnings: Vec<String>,          // Stock oversold, etc.
}

#[derive(uniffi::Record)]
pub struct ReceiptView {
    pub order_id: String,
    pub order_ref: Option<String>,
    pub order_number: Option<i32>,
    pub customer_name: Option<String>,
    pub lines: Vec<ReceiptLineView>,
    pub subtotal_minor: i64,
    pub discount_minor: i64,
    pub tax_minor: i64,
    pub total_minor: i64,
    pub tip_minor: i64,
    pub amount_tendered_minor: i64,
    pub change_minor: i64,
    pub payment_method: String,
    pub teller_name: String,
    pub created_at: String,             // RFC3339
    pub is_cash: bool,
    pub is_delivery: bool,
    pub delivery: Option<DeliveryReceiptView>,
    pub notes: Option<String>,
}

#[derive(uniffi::Enum)]
pub enum PrinterBrand { Epson, Star }
```

### Order Types
```rust
#[derive(uniffi::Record)]
pub struct OrderSummaryView {
    pub id: String,
    pub order_ref: Option<String>,
    pub order_number: Option<i32>,
    pub customer_name: Option<String>,
    pub status: String,                 // "open" | "paid" | "voided"
    pub total_minor: i64,
    pub payment_method: String,
    pub created_at: String,
    pub teller_name: String,
}

#[derive(uniffi::Record)]
pub struct OrderDetailView {
    pub id: String,
    pub order_ref: Option<String>,
    pub order_number: Option<i32>,
    pub lines: Vec<OrderLineView>,
    pub subtotal_minor: i64,
    pub discount_minor: i64,
    pub tax_minor: i64,
    pub total_minor: i64,
    pub tip_minor: i64,
    pub amount_tendered_minor: i64,
    pub change_minor: i64,
    pub payment_method: String,
    pub payments: Vec<PaymentView>,
    pub customer_name: Option<String>,
    pub teller_name: String,
    pub created_at: String,
    pub delivery: Option<DeliveryOrderView>,
    pub status: String,
}

#[derive(uniffi::Record)]
pub struct OrderLineView {
    pub item_id: String,
    pub item_name: String,
    pub qty: i64,
    pub unit_price_minor: i64,
    pub addons: Vec<OrderAddonView>,
    pub total_minor: i64,
}
```

### KDS Types
```rust
#[derive(uniffi::Record)]
pub struct KdsStationView {
    pub id: String,
    pub name: String,
    pub abbreviation: Option<String>,
}

#[derive(uniffi::Record)]
pub struct KdsTicketView {
    pub id: String,                     // Derived from round_id
    pub order_id: Option<String>,
    pub order_ref: Option<String>,
    pub table_label: Option<String>,
    pub lines: Vec<KdsLineView>,
    pub status: String,                 // "new" | "started" | "ready" | "served"
    pub fired_at: String,               // RFC3339
    pub notes: Option<String>,
}

#[derive(uniffi::Record)]
pub struct KdsLineView {
    pub item_id: String,
    pub name: String,
    pub qty: i64,
    pub modifiers: String,
    pub bumped: bool,                   // Line marked done
}
```

### Realtime Types
```rust
#[derive(uniffi::Record, Clone, Debug)]
pub struct RealtimeEvent {
    pub event_type: String,             // e.g. "delivery.created", "ticket.fired"
    pub data: String,                   // Raw JSON payload
}
```

### Tickets (Waiter Open-Tickets)
```rust
#[derive(uniffi::Record)]
pub struct TicketView {
    pub id: String,
    pub ticket_ref: Option<String>,
    pub table_id: Option<String>,
    pub status: String,                 // "queued" | "open" | "settled" | "voided"
    pub customer_name: Option<String>,
    pub waiter_name: Option<String>,
    pub guest_count: Option<i32>,
    pub subtotal_minor: i64,
    pub order_id: Option<String>,       // When settled into order
    pub opened_at: String,
    pub queued_offline: bool,           // Still pending sync
    pub lines: Vec<TicketLineView>,
}

#[derive(uniffi::Record)]
pub struct TicketFiredView {
    pub ticket_id: String,
    pub ticket_ref: Option<String>,
    pub queued_offline: bool,
}
```

### Delivery
```rust
#[derive(uniffi::Record)]
pub struct DeliveryOrderView {
    pub id: String,
    pub delivery_ref: String,
    pub customer_name: String,
    pub customer_phone: Option<String>,
    pub address: Option<String>,
    pub zone: Option<String>,
    pub status: String,                 // "received" | "confirmed" | …
    pub channel: String,                // "in_mall" | "outside"
    pub prep_time_minutes: i32,
    pub total_minor: i64,
}

#[derive(uniffi::Record)]
pub struct DeliverySettingsView {
    pub in_mall_accepting: String,      // "auto" | "open" | "closed"
    pub outside_accepting: String,
}

#[derive(uniffi::Record)]
pub struct DeliveryFinalizeView {
    pub order_id: String,
    pub order_ref: Option<String>,
    pub warnings: Vec<String>,
}
```

### Outbox/Sync
```rust
#[derive(uniffi::Record)]
pub struct OutboxItemView {
    pub id: String,
    pub op_type: String,                // "open_shift" | "create_order" | …
    pub status: String,                 // "pending" | "inflight" | "dead"
    pub attempts: i64,
    pub last_error: Option<String>,
    pub event_at: String,
}

#[derive(uniffi::Record)]
pub struct SyncStatusView {
    pub pending: u32,
    pub failed: u32,
    pub blocked: u32,                   // Orders waiting on dead open_shift
    pub online: bool,
    pub auth_paused: bool,              // Outbox parked on 401
}

#[derive(uniffi::Record)]
pub struct DiagLogView {
    pub at: String,
    pub level: String,                  // "warn" | "error"
    pub message: String,
}
```

### Recipe
```rust
#[derive(uniffi::Record)]
pub struct ComputedRecipeLineView {
    pub ingredient_name: String,
    pub quantity: Decimal,              // Baked into a precise type
    pub unit: String,
}
```

### Time Formatting
```rust
#[derive(uniffi::Enum)]
pub enum TimeStyle {
    Short,                              // "Jun 20, 12:30 PM"
    Long,                               // "June 20, 2026, 12:30:45 PM"
    DateOnly,
    TimeOnly,
}
```

---

## 4. Callback Interfaces (Host Must Implement)

### TokenStore (Secure Vault)
```rust
#[uniffi::export(callback_interface)]
pub trait TokenStore: Send + Sync {
    fn save_blob(&self, blob: Vec<u8>);  // Keychain/Keystore write
    fn clear_blob(&self);                 // On logout
}
```
The core hands the host one serialized session blob to persist; token custody (expiry/refresh) stays in Rust.

### EventListener (Realtime Board Refresh)
```rust
#[uniffi::export(callback_interface)]
pub trait EventListener: Send + Sync {
    fn on_event(&self, event: RealtimeEvent);            // New event → refresh board
    fn on_connection_changed(&self, connected: bool);    // SSE connect/drop
}
```
The core calls this as SSE frames arrive. Implementations **must return promptly** (hop to UI thread).

### RealtimePlayer (Alerts Only — Platform Primitives)
```rust
#[uniffi::export(callback_interface)]
pub trait RealtimePlayer: Send + Sync {
    fn play_ping(&self);                                  // Play bundled "new work" sound
    fn post_notification(&self, title: String, body: String, tag: String);  // OS notification (tag = id for replace)
    fn haptic(&self);                                    // Confirmation haptic
}
```
**NO decision logic**: the core decides WHEN to alert (which events, dedup), builds localized text, and picks the tag. The host only performs primitives.

---

## 5. Realtime/Event Mechanism

### SSE Transport & Supervisor
- One SSE connection per device via `GET /realtime/stream?branch_id&topics=…`
- Backend topic-multiplexes + permission-filters events
- Hand-rolled on `reqwest::Response::bytes_stream()` (openapi-generator has no text/event-stream method)
- Supervisor is a single tokio task: connect → parse → dispatch → reconnect on drop (jittered backoff, resume from Last-Event-ID)
- A 401 stops the task WITHOUT pausing the outbox

### Event Types by Domain
- **delivery**: `delivery.created`, `delivery.updated`, `delivery.advanced`, `delivery.cancelled`
- **tickets**: `ticket.fired`, `ticket.round_added`, `ticket.ready`, `ticket.settled`, `ticket.voided`
- **kitchen**: `kitchen.fired`, `kitchen.item_bumped`, `kitchen.item_unbumped`, `kitchen.ticket_ready`
- **orders**: `order.placed`, `order.voided`, `order.fulfilled`

### Alerting (Core Decision Logic)
- The core wraps the host's `EventListener` in `AlertingListener`, which also holds `RealtimePlayer`
- For EVERY event: call `listener.on_event()` (board refresh)
- For NEW, alert-worthy events (fire/round/new-delivery/ready) that are INCOMING for the role:
  - Dedup on (event_type, entity_id) tag (bounded 512-element set)
  - Build localized title/body (via `i18n::tr`)
  - Call `player.play_ping()` → `post_notification()` → `haptic()`
- A waiter FIRES tickets but doesn't alert on `ticket.fired`; only `ticket.ready` is "new work" (food up)
- KDS only alerts on `kitchen.fired` (its incoming work), not bumps/ready

### Role-Based Topics
```rust
fn topics_for_role(role: &str) -> Vec<String> {
    match role {
        "kitchen" => vec!["kitchen"],
        "waiter" => vec!["tickets", "kitchen"],
        _ => vec!["delivery", "kitchen", "tickets", "orders"],  // Teller/Till/Manager
    }
}
```

---

## 6. State Propagation Pattern

**After a mutating call (cart add, checkout, hold, settle, etc.):**

1. **Return Value**: The call returns a new view (CartLineView[], CheckoutView with receipt, etc.)
2. **Event (for cross-device sync)**: The outbox drain publishes the op to the realtime bus (LAN + cloud)
3. **Query on Refresh**: The host later calls `list_*` (orders, tickets, delivery, etc.) to re-fetch the server state
4. **Outbox Overlay**: Client-side, the host sees queued (unsynced) items overlaid onto server lists (e.g., fires in `list_open_tickets` with `status="queued"`)

**Example: Fire Ticket**
1. `fire_ticket()` → enqueue op → drain → return TicketFiredView (id, ref, queued_offline)
2. Realtime event `kitchen.fired` triggers instantly (LAN/cloud path)
3. KDS refreshes via `kds_list()` → overlay includes LAN-projected fire
4. On reconnect, `list_open_tickets()` returns server-confirmed ticket (fire synced)

**State is NEVER pushed back to the host** — refreshes are always host-initiated (menu taps, tab focus, explicit sync).

---

## 7. app_route Resolution (Core-Driven)

**The screen to show is decided ENTIRELY by the core**, resolved in `app_route()`:

1. **DeviceSetup** — device unbound OR mid-reconfigure (`reconfiguring=true`)
2. **Login** — device bound + signed out
3. **Order** — signed in + open shift (and its owner is THIS teller)
4. **OpenShift** — signed in + no open shift (or stale shift from prior teller)
5. **KitchenDisplay { station_id }** — signed in, role=="kitchen", station configured
6. **WaiterTickets** — signed in, role=="waiter" (holds no shift)

The host calls `app_route()` at deliberate transitions:
- Cold start, post-login, post-open/close shift, post-logout, post-branch-switch
- **Never as a side effect of connectivity** — the UI is NOT reactive to online/offline (only the offline banner is)

---

## 8. Internationalization (i18n)

### API
```rust
pub fn tr(locale: &str, key: &str) -> String
pub fn is_rtl(locale: &str) -> bool
```

**Runtime-changeable:** `core.set_locale("ar")` re-resolves all strings + layout direction.

### Supported Locales
- `en` — English (LTR)
- `ar` — Arabic (RTL)

### Fallback Chain
1. Key in active locale → use it
2. Missing in locale → fall back to en
3. Missing in en → return the key itself (e.g., "login.sign_in")

### CoreError → Human Message
The core's error enum carries structured detail; the host maps variant + `detail` field to a message:
- `Offline { detail }` → "You're offline. " + detail
- `Unauthenticated { detail }` → "Sign in again"
- `Forbidden { resource, action }` → "You don't have permission to " + action
- `Validation { field, detail }` → "Invalid " + field + ": " + detail
- `Server { status, code, detail }` → "[status] " + code + " server error"
- `Transient { detail }` → "Network issue: " + detail
- `Internal { detail }` → "App error: " + detail

---

## 9. Error Model

### CoreError Enum
```rust
#[derive(uniffi::Error, Debug, thiserror::Error)]
pub enum CoreError {
    #[error("offline: {detail}")]
    Offline { detail: String },

    #[error("auth required: {detail}")]
    Unauthenticated { detail: String },

    #[error("forbidden: {resource}/{action}")]
    Forbidden { resource: String, action: String },

    #[error("invalid: {field}: {detail}")]
    Validation { field: String, detail: String },

    #[error("server {status}: {code}")]
    Server { status: u16, code: String, detail: String },

    #[error("transient: {detail}")]
    Transient { detail: String },

    #[error("internal: {detail}")]
    Internal { detail: String },
}
```

### Which Methods Throw
**Online-only commands** (login, refresh_catalog, sync_now): `Offline`
**Permission checks** (checkout, void): `Forbidden`
**Validation** (empty cart, bad timestamps): `Validation`
**Sync/network** (send_to_printer, get_order): `Transient` or `Server` (retried by drain)
**Database/serde** (store corruption, bad enum): `Internal`

### Offline Semantics

**The outbox is the source of truth.** When offline:

1. **Mutating ops queue** → outbox (open_shift, create_order, fire_ticket, etc.)
2. **Reads succeed** from the local mirror (catalog, orders via cache, shift from store)
3. **Queries missing offline fail** with `Offline { "never cached" }` (e.g., a live web search)

**What "confirmed offline" means:** A real send attempt failed (connection refused, 5xx, timeout), NOT a speculative /health ping. The drain tracks this; `refresh_connectivity`'s ping is just a hint.

**Outbox after an offline unlock with expired token:**
- The teller's cached JWT is invalid
- The foreign (previous teller's) still-valid token drains the queue ONCE then is invalidated
- This teller must re-login under their own account to keep syncing

---

## 10. Runtime Details Relevant to FFI

### Tokio Runtime
- The core spawns its own **single shared tokio runtime** (multi-threaded executor)
- Async methods MUST be called from an async context or via a platform thread-pool (Flutter's Dart VM maintains its own isolate)
- UniFFI's `async_runtime = "tokio"` means uniffi-generated bindings block on the async calls and return the result

### Send/Sync Constraints
- `MadarCore` is wrapped in `Arc<MadarCore>` (returned by `new()`)
- All internal fields use `Arc`, `RwLock`, `Mutex` for thread-safety
- Callbacks (`TokenStore`, `EventListener`, `RealtimePlayer`) MUST be `Send + Sync`

### Blocking vs Async
- **Sync (FFI-safe)**: reads (current_session, app_route, tr, cart_lines, list_outbox)
- **Async** (returns via tokio): login, checkout, open_shift, close_shift, printer I/O, sync_now, kds_*, delivery_*
- **Async callback** (fires from supervisor task, not directly called): on_event, on_connection_changed

### Global State
- **One Store per MadarCore** (no global singletons; the host holds the Arc)
- **One realtime subscription per MadarCore** (replaced by calling subscribe/start again)
- **One LAN relay per MadarCore** (one device per instance)
- **Outbox drain is single-flighted** (tokio::sync::Mutex serializes concurrent triggers)

---

## 11. Build & Packaging (Today)

### Kotlin App (`kotlin-app/composeApp/src/commonMain/kotlin/app/madar/AppModel.kt`)
1. **Cargo.toml** in `rust-core/crates/madar-core`:
   - Builds `cdylib` for Android (JNA-loaded .so)
   - Builds `staticlib` for iOS (.xcframework)
   - UniFFI proc-macro generates Kotlin bindings via `cargo-uniffi` or the standalone `uniffi-bindgen` binary

2. **Gradle Build** (`build.gradle.kts` in kotlin-app):
   - Cargo task to compile Rust → Android ABIs (arm64-v8a, armeabi-v7a, x86, x86_64)
   - Embedds .so files in APK

3. **Android ABIs**:
   - arm64-v8a (primary)
   - armeabi-v7a (fallback)
   - x86 (emulator)
   - x86_64 (emulator)

4. **Swift App** (ios/):
   - Xcode build phase: `cargo build --release --target aarch64-apple-ios`
   - SwiftPM or manual .xcframework embedding
   - Bindings via `uniffi-bindgen generate --library libmadar_core.a --language swift`

### iOS Packaging
- Static library (libmadar_core.a) embedded in .xcframework
- Swift bindings in the same framework
- Supports iOS 14+ (adjust based on Cargo.toml MSRV)

### Desktop (macOS/Linux/Windows)
- cargo build --release → dylib/so/dll
- JNI wrapper (not yet a first-class target, but the cdylib can be dlopen'd)

### Rust Edition & Dependencies
- **Edition**: 2021
- **Workspace**: `/rust-core` (madar-core, madar-api, other crates share workspace Cargo.toml)
- **Key Deps** (all in Cargo.toml):
  - uniffi 0.28 (proc-macro, feature "tokio")
  - tokio 1 (rt-multi-thread, sync, time, net, io-util)
  - madar-api (generated client, path-dep)
  - reqwest 0.13 (rustls-no-provider, stream)
  - rusqlite 0.31 (bundled SQLite)
  - chrono-tz (branch TZ math)
  - argon2 (offline PIN verify)
  - cosmic-text + image (receipt rasterizer)
  - hmac + sha2 (LAN HMAC signing)
  - mdns-sd (mDNS discovery)
  - serde + serde_json (DTO serialization)
  - uuid + chrono (ids + timestamps)

---

## 12. Crate Details

### Workspace Layout
```
rust-core/
├── crates/
│   ├── madar-core/         ← Main FFI surface
│   │   ├── src/
│   │   │   ├── lib.rs      ← MadarCore + free exports
│   │   │   ├── session.rs  ← Auth + session state
│   │   │   ├── shift.rs    ← Shift lifecycle
│   │   │   ├── orders.rs   ← Order queries + mutations
│   │   │   ├── cart.rs     ← Cart state (KV-persisted)
│   │   │   ├── checkout.rs ← Checkout engine + receipt DTOs
│   │   │   ├── delivery.rs ← Delivery order management
│   │   │   ├── tickets.rs  ← Open-ticket waiter fires
│   │   │   ├── kds.rs      ← Kitchen display system
│   │   │   ├── realtime.rs ← SSE supervisor + alerting
│   │   │   ├── lan.rs      ← LAN relay (Phase E)
│   │   │   ├── store.rs    ← SQLite + outbox + KV
│   │   │   ├── net.rs      ← HTTP client + error mapping
│   │   │   ├── error.rs    ← CoreError enum
│   │   │   ├── i18n.rs     ← Localization strings
│   │   │   ├── device.rs   ← Device config (branch/till/station/printer)
│   │   │   ├── menu.rs     ← Catalog views + queries
│   │   │   ├── pricing.rs  ← Pricing engine
│   │   │   ├── recipe.rs   ← Local recipe preview
│   │   │   ├── render.rs   ← Receipt rasterizer (1-bit bitmap)
│   │   │   ├── receipt.rs  ← ESC/POS formatter + printing
│   │   │   ├── catstyle.rs ← Category icon + gradient
│   │   │   ├── timefmt.rs  ← Branch-tz timestamp formatting
│   │   │   ├── reservations.rs ← Floor plan + reservations
│   │   │   └── config.rs   ← MadarConfig constructor
│   │   ├── build.rs        ← Custom build (uniffi scaffolding)
│   │   ├── tests/          ← Integration tests (offline replay, etc.)
│   │   └── Cargo.toml
│   ├── madar-api/          ← Generated OpenAPI reqwest client
│   │   ├── src/
│   │   │   ├── apis/       ← Per-endpoint modules (orders_api, auth_api, etc.)
│   │   │   └── models/     ← Wire DTOs (generated, auto-reconstructed via tool/generate_api.sh)
│   │   └── Cargo.toml
│   └── [other crates]
├── tool/
│   ├── generate_api.sh     ← Regenerate madar-api from backend OpenAPI spec
│   ├── build.sh            ← Kotlin/Swift build wrappers
│   └── [cargo-ndk, etc.]
└── Cargo.toml (workspace)
```

### Features & Cargo Flags
- **lib** crate-type (Rust consumers, tests, uniffi-bindgen)
- **cdylib** (Android .so via JNA)
- **staticlib** (iOS .a embedded in .xcframework)
- **uniffi** feature "cli" (bin for uniffi-bindgen generation)
- **tokio** async runtime for exported `async fn`

### Compatibility & FFI Versioning
- `ffi_surface_version()` returns **4**, bumped on breaking API changes
- Hosts assert this at startup to catch old/new mismatches
- Previous versions broke on:
  - v1 → v2: device config moved into core store (host params dropped)
  - v2 → v3: LAN relay surface added
  - v3 → v4: core-driven realtime (start_realtime + RealtimePlayer callback)

### How madar-api is Regenerated
```bash
tool/generate_api.sh <backend-openapi-spec-url>
# Downloads spec, runs openapi-generator-cli
# Overwrites src/apis/ and src/models/ (checked in to preserve Cargo.lock)
```
The crate directly consumes `madar_api::models` and `madar_api::apis` types; the wire is fully typed.

---

## Summary Table

| Domain | Key Methods | Async | Offline |
|--------|-----------|-------|---------|
| **Auth** | login, sign_in, unlock_offline, logout | login/sign_in async | unlock_offline ✓ |
| **Session** | current_session, is_authenticated, has_permission, restore_session | — | restore_session ✓ |
| **Shift** | open_shift, close_shift, current_shift, refresh_shift, shift_report | open/close/refresh/report async | open/close queue ✓ |
| **Cart** | cart_add*, cart_set_qty, cart_clear, hold_cart, list_drafts | — | all ✓ |
| **Checkout** | checkout | async | queue to outbox ✓ |
| **Orders** | list_shift_orders, order_detail, void_order, search_orders | list/order async | search fails ✗ |
| **KDS** | kds_list, kds_bump, kds_list_stations | async | kds_list cached ✓ |
| **Tickets** | fire_ticket, settle_ticket, list_open_tickets, void_ticket | async | fire/settle queue ✓ |
| **Delivery** | list_delivery_orders, delivery_finalize, delivery_set_status | async | list cached ✓ |
| **Printer** | render_receipt, send_to_printer, print_to_device | send async | render ✓, send ✗ |
| **Realtime** | subscribe_realtime, start_realtime, unsubscribe_realtime | subscribe/start async | no events ✗ |
| **LAN Relay** | lan_start, lan_stop, lan_peer_count, lan_branch_has_open_till | lan_start async | local only ✓ |
| **Sync** | sync_now, retry_outbox, refresh_connectivity, recover_orphaned_orders | all async | queued ops ✓ |
| **i18n** | tr, set_locale, is_rtl | — | all ✓ |
| **Device** | set_device_branch, set_device_till, device_config, set_device_printer | — | all ✓ |

---

## Conclusion

The madar-core Rust crate is a **complete, self-contained business logic engine** for a POS system. All 90+ exports are accessible via UniFFI over the FFI boundary. The Flutter binding must mirror:

1. **MadarCore** as the singleton lifecycle object (Arc<MadarCore>)
2. **All async methods** mapped to Dart futures (via platform channels or a generated FFI binding)
3. **All records & enums** as equivalent Dart/Flutter classes
4. **Callbacks** (TokenStore, EventListener, RealtimePlayer) implemented by the Flutter app
5. **Offline-first semantics**: the outbox, the cache, the local mirror, and the single-flighted drain
6. **Realtime flow**: SSE + LAN overlap, deduped alerts, role-based topics
7. **State propagation**: return values + host-initiated refreshes (no push from core)
8. **app_route**: core-driven routing; host just shows the screen
9. **Error handling**: CoreError variants mapped to user-friendly messages

The crate's architecture (one store, one session, one realtime, one outbox drain, one LAN relay) is a constraint by design — it enforces single-writer safety and deterministic offline behavior across all platforms.