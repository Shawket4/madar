Now let me create the comprehensive inventory report. Based on all my exploration, I can now generate the detailed document:

# Kotlin Compose POS Application: Exhaustive Screen & Behavior Inventory

## 1. SCREENS & COMPOSABLES INVENTORY

### Screen Files (by route + function)

#### A. Authentication & Device Setup
1. **LoginScreen.kt** → AppRoute.Login (or DeviceSetup for manager)
   - Implements: PIN login (teller) OR email/password (manager device setup)
   - Wide layout: BrandPanel (55%) | FormColumn (45%)
   - Narrow: centered FormColumn with logo
   - Two phases: CREDENTIALS (email) → PICK_BRANCH (branch picker)

2. **ReauthScreen.kt** → Modal over Order/OpenShift
   - Triggered by: syncAuthPaused flag (token expired mid-shift)
   - Same teller re-enters PIN to resume sync (no handover)
   - Escape: "switch teller" closes shift, routes to login
   - Self-gating (reads showReauth)

3. **StationPickerScreen.kt** → AppRoute.DeviceSetup (KDS device)
   - Kitchen-role device picks its station after login
   - Leads to KitchenDisplayScreen

#### B. Shift Management
4. **OpenShiftScreen.kt** → AppRoute.OpenShift
   - Confirms WHAT'S in drawer (opening cash count)
   - Wide: BrandPanel (50%) | FormColumn (50%)
   - Narrow: centered FormColumn
   - Loads: suggestedOpeningCashMinor (carried-over closing)
   - Connectivity chrome pinned top (offline + auth-paused banners)

5. **CloseShiftScreen.kt** → Overlay over OrderScreen
   - Shows: summary card, cash card (counted input), report card, mismatch display
   - Loads ShiftReportView for expected cash breakdown
   - Preview button → ShiftReportPreviewScreen

#### C. Order Management (Cashier Flow)
6. **OrderScreen.kt** → AppRoute.Order or AppRoute.WaiterTickets
   - **Responsive**: Wide (≥760dp) splits into NavRail | Catalog | CartPanel
   - **Narrow**: NavRail hidden, top bar with "More" drawer, Catalog | CartBar (opens sheet)
   - **Keyboard shortcut**: Ctrl/⌘+Enter checks out (desktop)
   - Core components:
     - **CatalogColumn**: Categories tab, search, item grid with add badges
     - **CartPanel** (wide) / CartBar (narrow): lines, held-orders strip, checkout
     - **Held-orders strip**: Tabs of parked carts (live cart + drafts), drag-to-reorder
     - **NavRail**: Pinned sections (incoming, drafts, history, search, cash, shifts, print, sync, settings, More)
   - Chrome: offline banner, auth-paused banner, clock skew, error
   - LaunchedEffect: reconciles shift, loads catalog/cart/history, 15s connectivity heartbeat

7. **TenderScreen.kt** → Modal (checkout overlay)
   - **CheckoutDrawer**: Single shared component for:
     - Cashier checkout (placeOrder)
     - Ticket settle (settleTicket via IncomingScreen)
     - Delivery finalize (finalizeDelivery)
   - Inputs: payment method, cash/tendered, tip, optional discount (cashier only), customer fields (cashier only)
   - **Split logic**: divvies tender across multiple payment methods
   - On success → ReceiptConfirmation sheet (receipt preview + print button)

#### D. Waiter Flow
8. **WaiterScreen.kt** → Part of OrderScreen (isWaiterDevice branch)
   - Same catalog + cart as cashier, but:
     - Terminal action: "Fire" (new ticket) or "Add round" (to activeTicketId)
     - Fire NEW → FireDetailsSheet collects dine-in (table, customer, covers, notes)
     - Fire/add round → clears cart
   - Waiter holds NO shift/history (fires tickets only)
   - Loads openTickets on entry + reacts to ticketTick (SSE)

9. **Incoming Screen** → Unified "Orders" delivery + tickets
   - Replaces separate delivery + settle screens
   - **Two tabs** (segmented bar, live count badges):
     - Tab 0: DeliveryBody
     - Tab 1: TicketsSettleBody
   - Both driven by SSE (deliveryTick / ticketTick)
   - Slower 60s poll as safety net

10. **DeliveryScreen.kt** → DeliveryBody (inside IncomingScreen)
    - Shows: active/all filter, accepting chips (in-mall/outside auto→open→closed), delivery queue
    - Per order: status badge, advance lifecycle, bump prep time, cancel (restock), finalize (→settle)
    - Finalize uses shared CheckoutDrawer (paymentMethodId only)
    - SSE-driven + 60s safety poll

11. **TicketsSettleBody** (in WaiterScreen.kt)
    - Shows: open/ready tickets (cashier view for waiter-fired tickets)
    - Tap → view details sheet, Settle button
    - Settle uses shared CheckoutDrawer (same as cashier checkout, but ticket subtotal instead of cart totals)
    - SSE-driven on ticketTick

#### E. Kitchen Display
12. **KitchenDisplayScreen.kt** → AppRoute.KitchenDisplay
    - Full-screen board for kitchen-role device
    - Subscribes to `kitchen` SSE topic
    - Header: station glyph + name, connection dot, ticket count, Settings button
    - Grid: KDS ticket cards (tap line to bump/unbump)
    - Tick-driven reload + 60s safety poll

#### F. Data & History
13. **OrderHistoryScreen.kt** → Full-screen overlay over OrderScreen
    - Current shift orders (queued + synced)
    - Responsive: width ≥680 → data TABLE (sortable cols: #, payment, time, teller, amount)
    - Narrow: expandable CARDS (tap → OrderDetailView sheet)
    - Sync filter: ALL / SYNCED / PENDING / VOIDED
    - Per-row actions: Void, Print, Expand details

14. **OrderSearchScreen.kt** → Full-screen overlay
    - All-orders search across shifts (online only)
    - Filters: status, teller, payment method, date range
    - Paginated (load-more)

15. **CashAndShiftsScreen.kt** → Contains CashMovementsScreen + ShiftHistoryScreen
    - **CashMovementsScreen**: Current shift pay-in/pay-out (online)
      - Record form: amount + note
      - List: movements (color-coded ±)
    - **ShiftHistoryScreen**: Past shifts (online)
      - Per shift: summary + lazy-load per-shift orders
      - Per shift: print Z-report button

#### G. Receipt & Reporting
16. **ReceiptPaper.kt** → Composable (not a screen)
    - On-screen receipt preview (white thermal paper theme)
    - Rendered from core's ReceiptView
    - Shows: logo, branch, order ref, lines, totals, payment, delivery channel

17. **ReceiptPreviewScreen.kt** → Modal over OrderScreen
    - Past order receipt preview (fetched via openOrderReceiptPreview)
    - Print button (printReceiptView) + toast-driven feedback

18. **ShiftReportPreview.kt** → ShiftReportPreviewScreen modal
    - Mid-shift Z-report preview (no close) OR past shift (from ShiftHistoryScreen)
    - Shows: ShiftReportBreakdown (per-method sales, proportional bars, cash in/out, movements, totals)
    - Print button (printReportView / printShiftReport)

#### H. Settings & Configuration
19. **SettingsScreen.kt** → Full-screen overlay over OrderScreen
    - Account card: teller name, online status, shift stats (narrow only)
    - Appearance: theme (light/dark/system)
    - Language: en/ar live switch (re-resolves strings + RTL)
    - Printer: device code, host, brand (Epson/Star)
    - Till (drawer) binding picker (if not KDS)
    - LAN relay diagnostics (active toggle, peer count)
    - Sync diagnostics: recent logs, clear
    - Reconfigure device: begin/cancel flow
    - Sign out

20. **SyncScreen.kt** → Full-screen overlay over OrderScreen
    - Outbox visibility: queued / in-flight / failed rows (with error)
    - Actions: Retry (failed only), Sync now (all queued)
    - Per-row: status chip, discard button

#### I. Drafts & Floor Plan
21. **DraftsScreen.kt** → Full-screen overlay
    - Parked carts (draft view + totals)
    - Tap → restore (replacing current cart), Discard

22. **FloorPlanScreen.kt** → Reservations & floor plan (online)
    - Section picker, canvas with tables (positioned to scale)
    - Live status (free/held/seated/dirty), color-coded
    - Reservation list, seat booking, notify/move actions

---

## 2. APPMODEL PUBLIC SURFACE (STATE FIELDS + METHODS)

### Session & Authentication
- **session** (SessionSnapshot?): Signed-in user (null = login screen)
- **isSignedIn** (Boolean): session != null
- **signInTeller(name, pin)**: PIN login (teller)
- **reauth(pin)**: Same-teller re-auth (token expired)
- **reauthSwitchTeller()**: Close shift, route to login
- **signOut()**: Tear down session, clear state

### Device Binding & Configuration
- **deviceConfig** (DeviceConfigView): Branch/till/station/printer binding
- **branchId, branchName** (String): Configured branch
- **orgLogoUrl** (String?): Org logo (durable kv, refreshed per sync)
- **reconfiguring** (Boolean): Device in reconfigure mode
- **isBranchConfigured** (Boolean): branchId.isNotBlank()
- **printerHost, printerBrand** (String, PrinterBrand): Printer config
- **lanHub** (String): Manual LAN relay address
- **deviceCode** (String): Till device code (T1/W2/K1 segment)
- **setDevicePrinter(host, brand)**: Persist printer
- **setLanHub(value)**: Persist LAN relay address
- **setDeviceTill(tillId)**: Bind till (drawer)
- **setDeviceStation(stationId)**: Bind KDS station
- **isKitchenDevice, isWaiterDevice** (Boolean): Session role check
- **refreshDeviceConfig()**: Mirror core→host

### Shift Management
- **shift** (ShiftView?): Open shift (drives route DeviceSetup ↔ OpenShift ↔ Order)
- **hasOpenShift** (Boolean): shift?.isOpen ?: false
- **suggestedOpeningCashMinor** (Long): Carried-over closing (prefill)
- **openShift(openingCashMinor, editReason)**: Create shift
- **loadOpenShiftPrefill()**: Refresh suggestion (online)
- **reconcileShift()**: Sync open shift with server (online) or read cache
- **loadShift()**: Read current shift (cache)
- **closeShift(closingCashMinor, note)**: End shift
- **showCloseShift** (Boolean): Drives overlay

### Catalog & Cart
- **categories, menuItems** (List<CategoryView/MenuItemView>): Branch catalog (offline-safe)
- **cartLines** (List<CartLineView>): Current cart
- **cartTotals** (CartTotals): Subtotal, discount, tax, total, item count
- **cartStartedAtIso** (String?): RFC3339 timestamp (empty→non-empty), drives held-orders sort + "HH:MM" label
- **cartDiscountId** (String?): Applied discount
- **paymentMethods, discounts** (List<...>): Org payment methods + discounts (cached)
- **addToCart(item), setCartQty, removeCartLine, clearCart()**: Cart mutations
- **swipeRemoveCartLine(line)**: Delete + undo toast
- **loadCart(), loadCatalog()**: Refresh cart + catalog
- **reprojectCatalog()**: Re-read catalog (locale change)
- **setDiscount(id)**: Apply or clear discount

### Bundles (Combos)
- **bundles** (List<BundleView>): Available within date/time window
- **detailBundle** (BundleView?): Drives customization sheet
- **loadBundles()**: Load with date/time gating
- **openBundleDetail(b), closeBundleDetail()**: Sheet control
- **componentItem(itemId)**: Resolve bundle component + addons
- **addBundle(bundleId, components)**: Add configured to cart

### Item Customization
- **detailItem** (MenuItemView?): Drives customization sheet
- **detailEditKey, detailEditLine** (String?, CartLineView?): Edit mode (vs add)
- **itemAddons** (List<ItemAddonView>): Item's addons (charged prices resolved)
- **hasOptions(item)**: Determine sheet entry vs direct add
- **openItemDetail(item, editKey, editLine)**: Open sheet
- **editCartLine(line)**: Re-open sheet for cart line
- **closeItemDetail()**: Sheet dismissal
- **recipePreview(itemId, sizeLabel, addons, optionalIds)**: Live preview
- **addConfigured(itemId, sizeLabel, addons, optionalIds, qty, notes)**: Add/replace line

### Checkout & Orders
- **receipt** (ReceiptView?): Last placed order (drives confirmation sheet)
- **isPlacingOrder** (Boolean): Checkout in flight
- **printState** (PrintState): IDLE / PRINTING / PRINTED / FAILED / NO_PRINTER
- **placeOrder(paymentMethodId, amountTenderedMinor, tipMinor, tipPaymentMethodId, customerName, notes, splits)**: Checkout (online or queued)
- **dismissReceipt()**: Close confirmation
- **cartQtyForItem(itemId)**: Badge helper

### Receipt & Printing
- **printReceipt(kickDrawer)**: Auto-print receipt (draw kick for cash sales)
- **printReportView(report)**: Print any shift report
- **printShiftReport()**: Print current shift Z-report
- **previewReceipt** (ReceiptView?): Past order preview (drives sheet)
- **openOrderReceiptPreview(orderId)**: Fetch + preview
- **printReceiptView(r)**: Print preview (toast-driven)
- **reprintOrder(id)**: Re-render + print past order
- **setPrinterHost(value), setPrinterBrand(value)**: Settings persistence
- **setDeviceCode(code)**: Device code persistence

### Order History
- **history** (List<OrderSummaryView>): Current shift orders
- **isLoadingHistory** (Boolean): Fetch in flight
- **shiftSalesMinor, shiftOrderCount** (Long, Int): Derived stats for bar pill
- **orderDetail** (OrderDetailView?): Expanded row (lazy-loaded)
- **showHistory** (Boolean): Drives screen
- **loadHistory()**: Fetch + derive stats
- **loadOrderDetail(id)**: Fetch line details
- **voidOrder(orderId, reason, note, restoreInventory)**: Void + reload
- **showOrderSearch** (Boolean): Drives screen
- **orderSearchResults, orderSearchTotal, orderSearchHasMore** (List, Int, Boolean): Search results + pagination
- **isSearchingOrders** (Boolean): Fetch in flight
- **searchOrders(status, teller, payment, fromIso, reset)**: Search + page

### Delivery
- **deliveryOrders** (List<DeliveryOrderView>): Branch queue
- **isLoadingDelivery** (Boolean): Fetch in flight
- **deliveryActiveOnly** (Boolean): Filter toggle (received/confirmed/preparing/ready/out_for_delivery vs all)
- **deliverySettings** (DeliverySettingsView?): Per-channel accepting override (auto/open/closed)
- **loadDeliveryOrders()**: Fetch (filtered by deliveryActiveOnly)
- **cycleAccepting(channel, current)**: Toggle channel accepting
- **advanceDelivery(o)**: Lifecycle step
- **addDeliveryPrep(o, minutes)**: Bump prep (5-min increments)
- **cancelDelivery(o, reason, restoreInventory)**: Cancel (restock)
- **rejectDelivery(o)**: Reject received (terminal, pre-prep)
- **finalizeDelivery(o, paymentMethodId)**: Convert to sale + settle (shared CheckoutDrawer)

### Waiter (Dine-In Tickets)
- **openTickets** (List<TicketView>): Branch open tickets
- **activeTicketId** (String?): Selected ticket (drives "Add round" vs "Fire")
- **loadOpenTickets()**: Fetch (SSE-driven + manual)
- **fireTicket(customerName, tableId, notes, guestCount)**: Fire NEW ticket (cashier settle later)
- **addRound(ticketId)**: Add round to activeTicketId
- **voidTicket(ticketId, reason)**: Void ticket
- **settleTicket(ticketId, paymentMethodId, amountTenderedMinor, tipMinor, tipPaymentMethodId)**: Settle (shared CheckoutDrawer, waiter's terminal action)
- **fireOrAddRound(...)**: Unified action (route on activeTicketId)

### Held Orders (Drafts)
- **drafts** (List<DraftView>): Parked carts
- **showDrafts** (Boolean): Drives screen
- **loadDrafts()**: Fetch
- **holdCart()**: Park current cart (named "HH:MM" wall-clock time, core stamps createdAt)
- **restoreDraft(id)**: Restore to cart (adopts createdAt as cartStartedAtIso)
- **discardDraft(id)**: Delete
- **switchToHeldOrder(id)**: Waiter tab-style switch (park current, load target)

### Cash Movements & Shift History
- **cashMovements** (List<CashMovementView>): Current shift pay-in/out
- **isLoadingCash** (Boolean): Fetch in flight
- **showCashMovements** (Boolean): Drives screen
- **loadCashMovements()**: Fetch (online)
- **recordCashMovement(amountMinor, note)**: Record pay-in (>0) or pay-out (<0)
- **shiftHistory** (List<ShiftSummaryView>): Past shifts
- **isLoadingShifts** (Boolean): Fetch in flight
- **showShiftHistory** (Boolean): Drives screen
- **loadShiftHistory()**: Fetch (online)
- **shiftOrders** (Map<String, List<OrderSummaryView>>): Per-shift orders (lazy-loaded)
- **loadingShiftOrders** (Set<String>): Fetch in flight (per shift id)
- **loadOrdersForShift(shiftId)**: Lazy load + cache
- **reprintShiftReport(shiftId)**: Fetch report + print

### Shift Reports
- **shiftReport** (ShiftReportView?): Current shift report (expected cash)
- **showReportPreview** (Boolean): Mid-shift preview sheet
- **previewShiftReport** (ShiftReportView?): Past shift preview (from history)
- **loadShiftReport()**: Fetch expected cash (close-shift)
- **openShiftReportPreview()**: Show mid-shift + reset print state
- **openShiftReportPreviewFor(shiftId)**: Fetch + preview past shift

### Kitchen Display (KDS)
- **kdsTickets** (List<KdsTicketView>): Board tickets
- **kdsStations** (List<KdsStationView>): Available stations
- **loadKds()**: Fetch tickets (filtered by deviceConfig.stationId)
- **loadKdsStations()**: Fetch stations
- **bumpKdsItem(itemId), unbumpKdsItem(itemId)**: Bump line (done marker)

### Tills & Configuration
- **tills** (List<TillView>): Branch drawers (Settings picker)
- **loadTills()**: Fetch

### Sync & Connectivity
- **outbox** (List<OutboxItemView>): Durable outbox
- **pendingCount** (Int): Queued/in-flight command count (sync chip badge)
- **syncFailed** (Int): Dead/stuck command count (needs-attention badge)
- **isOnline** (Boolean): Connectivity state (drives offline banner)
- **syncAuthPaused** (Boolean): Outbox parked on 401 (drives auth-paused banner)
- **clockSkewMinutes** (Int): Server-device skew (drives banner)
- **showSync** (Boolean): Drives screen
- **isPushing** (Boolean): Manual sync in flight
- **isSyncingData** (Boolean): Manual catalog re-pull in flight
- **loadOutbox(), refreshPending()**: Fetch outbox + stats
- **retryOutbox()**: Requeue failed commands
- **syncNow()**: Force-drain all queued (manual push)
- **discardOutboxItem(id)**: Delete dead item
- **refreshServerData()**: Manual catalog re-pull + re-project
- **refreshConnectivity()**: Ping + drain + reconcile shift (on transition online)

### Realtime & Events (SSE)
- **realtimeConnected** (Boolean): SSE connection state (reconnect banner)
- **kitchenTick, ticketTick, deliveryTick** (Int): Monotonic tick per topic (LaunchedEffect triggers)
- **ticketsHasNew, deliveryHasNew** (Boolean): Unseen event badges (animated nav indicator)
- **realtimeAlerts** (List<RealtimeAlertData>): In-app alert stack (newest first)
- **startRealtime()**: Open ONE session-level SSE (role-based topics)
- **startLanRelay()**: LAN offline relay (Phase E)
- **unsubscribeRealtime()**: Tear down SSE
- **onRealtimeEvent(event), onRealtimeConnection(connected)**: Bridge callbacks (SSE task thread → snapshot writes)
- **showRealtimeAlert(title, body, tag)**: Raise in-app banner (deduped by tag)
- **dismissRealtimeAlert(id)**: Dismiss banner
- **openOrdersFromAlert(alert)**: Tap banner → open Orders (delivery vs tickets tab)
- **clearTicketsBadge(), clearDeliveryBadge()**: Dismiss unseen indicators

### UI State & Chrome
- **isBusy** (Boolean): Operation in flight
- **error** (String?): Guidance/validation message (screens' error slot)
- **flagError(message), clearError()**: Error management
- **showSettings, showMore** (Boolean): Settings + More drawer overlays
- **showIncoming, incomingTab** (Boolean, Int): Unified Orders surface (tab 0/1)
- **route** (AppRoute): Current screen (session + shift + branch read-register)
- **hasOverlay** (Boolean): Union of all full-screen overlays (gates system back)
- **goBack()**: Close topmost overlay (back navigation)

### Toasts & Notifications
- **toast** (ToastData?): Active transient message
- **showToast(text, tone, actionLabel, action, seconds, icon)**: Flash message (auto-dismiss)
- **dismissToast(id), runToastAction()**: Toast control

### Localization & Theming
- **locale** (String): Active locale (en/ar)
- **themeMode** (ThemeMode): Appearance preference (LIGHT/DARK/SYSTEM)
- **isRTL** (Boolean): RTL layout direction
- **t(key)**: Localize string (core)
- **setLocale(value)**: Switch language (re-project catalog, persist)
- **setThemeMode(mode)**: Switch theme, persist

### Timestamp Formatting (Branch Timezone)
- **fmtTime, fmtDateShort, fmtDateTime, fmtReceipt**: Format timestamps (core, branch tz)

---

## 3. LAYOUT STRUCTURE: RESPONSIVE PATTERNS

### Breakpoints (Responsive.kt)
- **tablet** (≥600dp): Tablet spacing / wider forms
- **wideTable** (≥680dp): Table layout (OrderHistory, ShiftHistory)
- **wide** (≥760dp): Split / side-by-side (LoginScreen, OpenShiftScreen, OrderScreen)
- **desktop** (≥1100dp): Cap & center content (not yet implemented)

### LoginScreen Responsive
- **Wide (≥760dp)**: BrandPanel (55%) | FormColumn (45%, centered vertically)
- **Narrow**: Centered FormColumn with logo

### OpenShiftScreen Responsive
- **Wide (≥760dp)**: BrandPanel (50%) | FormColumn (50%, centered vertically)
- **Narrow**: Centered FormColumn with logo

### OrderScreen Responsive (Complex Split)
- **Wide (≥760dp)**:
  - NavRail (fixed width) | separator | CatalogColumn (flex) | separator | CartPanel (340dp)
  - Top bar (menu trigger hidden), sync chip visible, stats pill visible (More drawer)
- **Narrow**:
  - NavRail hidden
  - Top bar with "Options" toggle → MoreDrawer (expands left, carries full nav)
  - CatalogColumn (flex) | CartBar (sticky bottom)
  - Tap CartBar → CartPanel drawer (bottom sheet, 88% height)
  - Stats pill hidden (shown in More drawer's shift card)

### OrderHistory Responsive
- **Wide (≥680dp)**: Data TABLE (sortable cols, fixed row height)
- **Narrow**: Expandable CARDS (stack, tap → details sheet)

### Held-Orders Strip (CartPanel Top)
- **Component**: Horizontal scrolling tab bar
- **Tabs**: Live cart ("HH:MM" label) + parked drafts ("HH:MM" names)
- **Active**: Teal fill, count pill on-accent
- **Inactive**: Surface background, text secondary
- **Sort**: By RFC3339 (cartStartedAtIso / draft.createdAt) — newest first (right edge)
- **Interaction**: Tap → restore/switch cart, long-press drag to reorder
- **Drag**: Local drag state (reorder + haptic)

### Cart Panel (Wide)
- Header: "Cart" title, item-count badge, Clear link, Close button (phone only)
- Held-orders strip (tabs)
- Lines: row per item, qty field, price, edit/swipe-delete buttons
- Optional: Active ticket section (waiter only, above current round)
- Totals: Subtotal, discount, tax, total (hero money, teal)
- Checkout button: Terminal action (checkoutLabel, checkoutIcon)

### Chart & Breakdown Layouts
- **ShiftReportBreakdown**: Per-method sales row, proportional bar, total (tabular money)
  - Cash in/out rows, movements (with notes)
  - Void total, total payments, opening cash, opening mismatch (if edited)
  - All money bold teal (tabular)

---

## 4. KEY CROSS-CUTTING FLOWS (Precise Detail)

### A. Offline Banner Semantics
**State drivers**:
- **isOnline** (Boolean): Connectivity truth (set by refreshConnectivity → core.refreshConnectivity)
- **Confirmers**:
  - Outbox failure (dead item exists) → syncFailed > 0
  - Health ping timeout
- **Display**: NoticeBanner("chrome.offline_banner", ChipTone.WARNING, icon="wifi.slash")
- **Scope**: Shown on OpenShiftScreen top, OrderScreen top, every full-screen overlay's top chrome

### B. Auth-Paused Banner Semantics
**State driver**: **syncAuthPaused** (Boolean) — set when outbox hits 401 (token expired)
- **Display**: Tappable banner (AuthPausedBanner) with call-to-action pill
- **Tap action**: model.showReauth = true (opens ReauthScreen modal)
- **Scope**: OpenShiftScreen + OrderScreen top chrome
- **Resolution**: reauth(pin) succeeds → showReauth = false, refreshPending, showToast("chrome.sync_resumed")

### C. Opening-Cash Suggestion Logic
**Conditions**:
1. Online: true (core.refreshConnectivity() ping succeeds)
2. Fully synced: pendingCount == 0 AND syncFailed == 0
3. Shift closed: no open shift yet
- **Prefill source**: core.suggestedOpeningCashMinor() (last declared closing, durable kv)
- **Timing**: loadOpenShiftPrefill() refreshes server version (online) or reads cache (offline)
- **UI**: Hero AmountField on OpenShiftScreen, auto-focused

### D. Shared Checkout Drawer (ONE Component for 3 Flows)
**Component**: CheckoutDrawer (TenderScreen.kt)
**Entry points**:
1. **Cashier checkout** → TenderForm → placeOrder(paymentMethodId, amountTenderedMinor, ...)
2. **Ticket settle** → TicketsSettleBody settle action → settleTicket(ticketId, paymentMethodId, ...)
3. **Delivery finalize** → DeliveryBody finalize action → finalizeDelivery(orderId, paymentMethodId)

**Shared state**:
- **summary** (CheckoutSummary): subtotal, discount, tax, total (passed by caller)
- **title, terminalLabel, terminalIcon**: Customized per flow
- **showDiscountPicker**: Cashier only (ticket + delivery don't show)
- **showCustomerFields**: Cashier only (customerName + notes)

**Tender modes**:
1. **Simple** (non-split): Pick payment method → if cash, live change display → terminal
2. **Split**: Allocate money across multiple methods (CheckoutSplit list) → terminal

**Return**: CheckoutResult (primaryMethodId, tenderedMinor, tipMinor, tipPaymentMethodId, customerName, notes, splits, isCash)

**Termination**: On success receipt shows, caller dismisses on ReceiptConfirmation action

### E. Held-Orders Strip (Drafts Tab Behavior)
**Data source**: model.drafts (core.listDrafts)
**Sort order**: By RFC3339 (cartStartedAtIso) — newer on right
**Label per tab**: RFC3339 → "HH:MM" (wall-clock time, the moment parked)

**Creation**:
- holdCart() → park current (names by nowHHMM()), load cart/drafts
- core.holdCart() stamps createdAt, drives sort key and label

**Restore**:
- restoreDraft(id) → loads into cart, adopts draft.createdAt as cartStartedAtIso
- Live-cart tab keeps its true creation time (original or restored)

**Discard**:
- discardDraft(id) → trash button, reload drafts

**Drag-to-reorder** (Local state in CartPanel):
- Detect long-press + drag
- Haptic feedback on drag start
- Reorder drafts list (NOT persisted to core; core owns no reorder API)
- On release: persist if backend supports (current: no persist)

**Design**:
- Horizontal scrolling FitOrScrollRow
- Active: Teal fill, "HH:MM" + item count, teal text
- Inactive: Surface bg, secondary text
- New-round ("+" button) adds empty new cart under live tab

### F. Waiter Tickets-in-Cart (activeTicketId Selection)
**Data source**: model.openTickets (from loadOpenTickets)
**Display location**: CartPanel top section (above editable new round)
**State**: model.activeTicketId (String?)

**Selection interaction**:
- Waiter taps ticket chip → model.activeTicketId = ticketId
- Shows ticket's current items (read-only, visual confirmation)
- Terminal label changes: "Add round" (vs "Fire" if null)
- Tap again to deselect (toggle behavior)

**Fire flow**:
- activeTicketId = null → showFireDetails = true (dine-in details sheet)
- activeTicketId != null → fireOrAddRound() → addRound(ticketId) → core.addTicketRound()
- Success: Clear cart, activeTicketId = null, showToast("waiter.fired")

**Line actions on active ticket**:
- New round: Plus button at end of ticket's round section
- Void ticket: Trash icon (voidTicket(ticketId, reason))

### G. SSE Events Driving Per-Module Indicators
**Event types** (from core):
- kitchen.* → kitchenTick++ (KDS board reload)
- ticket.* → ticketTick++, ticketsHasNew = true (Tickets settle badge)
- delivery.* → deliveryTick++, deliveryHasNew = true (Delivery badge)

**Navigation indicators**:
- IncomingScreen tab badges: live count (deliveryCount, ticketCount.filter open/ready)
- NavRail "Incoming" badge: hasNew dot + animation (if deliveryHasNew || ticketsHasNew)
- Tapping Incoming clears badges: clearDeliveryBadge() + clearTicketsBadge()

**Board reload triggers**:
- Tick bump → LaunchedEffect(tick) in each screen body → loadDeliveryOrders() / loadKds() / loadOpenTickets()
- 60s safety-net poll (LaunchedEffect with while(isActive))
- Manual refresh (user button tap)

**Connection indicator**:
- KitchenHeader: Live connection dot (connected = model.realtimeConnected, green/gray)
- KDS reconnecting banner: Shows when !realtimeConnected

### H. Receipt Preview & Printing Flow
**Checkout → Receipt**:
1. placeOrder() succeeds → receipt = ReceiptView → TenderForm shows ReceiptConfirmation sheet
2. ReceiptConfirmation renders ReceiptPaper preview + Print button
3. Auto-print (printReceipt) on checkout (kicks drawer if cash sale)
4. Print button is manual reprint (no drawer kick, printReceipt(kickDrawer=false))
5. Dismiss → dismissReceipt(), route back to catalog

**Past order reprint**:
1. OrderHistoryScreen row Print action → reprintOrder(id)
2. Opens ReceiptPreviewScreen (fetches via openOrderReceiptPreview)
3. Shows ReceiptPaper preview + Print button (toast-driven feedback)
4. Tap close → previewReceipt = null

**Z-report printing**:
1. Mid-shift: openShiftReportPreview() → ShiftReportPreviewScreen
2. Past shift: openShiftReportPreviewFor(shiftId) → ShiftReportPreviewScreen
3. Renders ReceiptPaper + ShiftReportBreakdown + Print button
4. Print → printReportView(report) / printShiftReport()
5. Toast-driven: "receipt.printed" (success) or "receipt.print_failed"

**Printer setup**:
- No printer → PrintState.NO_PRINTER (toast or button disabled)
- Printing → PrintState.PRINTING (button spin + disabled)
- Success → PrintState.PRINTED (button shows check, auto-dismiss)
- Failure → PrintState.FAILED (toast)

---

## 5. NAVIGATION & ROUTING

### AppRoute Hierarchy (Core-Driven)
1. **DeviceSetup**: Unconfigured device
   - Manager email/password → branch picker
   - Kitchen device → StationPickerScreen
   - Leads to: Login (manager logout) or KitchenDisplay (station bound)

2. **Login**: Branch configured, no session
   - Teller PIN login
   - Leads to: OpenShift (on success)

3. **OpenShift**: Signed in, no open shift
   - Confirm opening cash
   - Leads to: Order (on success)

4. **Order**: Signed in, open shift, teller role
   - Main POS screen (catalog + cart)
   - Overlays: All full-screen screens (CloseShift, Sync, History, etc.)

5. **WaiterTickets**: Same as Order, but waiter role
   - Same UI (cashier checkout → settle; waiter fire)

6. **KitchenDisplay**: KDS role, open shift
   - Full-screen board

**Reading route**:
- AppModel.route property (get) → registers session/shift/deviceConfig reads
- Core decides (core.appRoute())

**Overlays** (not route; model flags):
- showCloseShift, showSync, showHistory, showOrderSearch, showCashMovements, showShiftHistory, showDrafts, showIncoming, showSettings, showReportPreview, previewShiftReport, previewReceipt, detailItem, detailBundle, showReauth, showMore
- Local to OrderScreen: showCart (bottom sheet), showTender (checkout), showFireDetails (waiter dine-in)
- goBack() closes topmost overlay in z-order

**System back handler** (App root):
- BackHandlerCompat(enabled=hasOverlay) → goBack()
- OrderScreen local: BackHandlerCompat(enabled=showTender||showCart) → close local sheets first

---

## 6. OPTIMISTIC UPDATES & HAPTICS

### Optimistic Updates (Sync Cart)
- **addToCart, removeCartLine, setCartQty, clearCart**: Synchronous on client (core touches kv)
- **addConfigured, addBundle**: Sync add
- **holdCart, restoreDraft, discardDraft**: Sync mutations
- **UI reflects immediately** (cartLines, cartTotals re-read)
- **No loading state** (instant feedback)

### Haptics
- **HapticFeedbackType.LongPress**: Held-orders card restore, CartBar open
- **haptics.warning()**: PIN pad entry error (too short, user feedback)
- **haptics.success()**: Haptic method not shown in read code (reserved for future)
- **Default interactions**: pressScale + tap visual feedback

### Toasts
- **Success**: ChipTone.SUCCESS, icon="checkmark.circle" (sync_resumed, waiter.fired, delivery.finalized, etc.)
- **Warning**: ChipTone.WARNING, icon="exclamationmark.triangle" (offline, no printer, oversold warnings)
- **Danger**: ChipTone.DANGER, icon="xmark.circle" (sync_failed, print_failed, KDS errors)
- **Custom**: Undo on swipe-delete, overstock warnings in delivery finalize

---

## 7. LOADING, EMPTY & ERROR STATES

### Loading States
- **isLoadingHistory**: History screen spinner (top-right, replaces Retry button)
- **isLoadingCash, isLoadingShifts, isLoadingDelivery**: Delivery/cash/shifts screens (SkeletonList)
- **isSearchingOrders**: Order search (spinner)
- **isBusy**: Any operation (overlay disables inputs)
- **isPushing, isSyncingData**: Sync button spinner

### Empty States
- **Drafts**: Icon (tray), "drafts.empty" message, centered
- **Delivery**: Icon (bicycle), "delivery.empty", centered
- **History**: Icon (doc.text), "history.empty", centered
- **KDS**: "kds.empty_state", centered
- **Open tickets (settle)**: "waiter.no_tickets", centered
- **Sync**: "sync.empty_state", centered

### Error States
- **Validation**: error banner (ChipTone.DANGER), user message from core
- **Server**: error banner (ChipTone.DANGER), user message + retry flow
- **Transient**: error banner, implicit retry (on connectivity heartbeat)
- **Offline on demand**: Toasts ("chrome.offline_banner"), manual refresh shows hint
- **Setup errors**: Screen error banner (OpenShift, CloseShift, Settings)
- **KDS reconnect**: "kds.reconnecting" banner (warning), show when !realtimeConnected

### Sync Status Indicators
- **Sync chip** (top bar, wide): Badge with pendingCount (queued) / syncFailed (dead)
- **Color**: Teal if pending > 0, red if syncFailed > 0
- **Tap**: showSync = true (SyncScreen overlay)

---

## 8. RECEIPT LAYOUT (ReceiptPaper)

**Theme**: White paper (0xFFFFFFFF), dark ink (0xFF1A1A1A), faint (0xFF6B6B6B), rule (0xFFCCCCCC)

**Sections** (top to bottom):
1. **Org logo** (if present): Aspect-fit, max 60dp height × 220dp width (no crop/squish)
2. **Voided marker** (if voided): "*** receipt.voided ***", bold red
3. **Store name**: uppercase, bold, 15sp
4. **Delivery channel** (if delivery): faint, "— delivery.in_mall/receipt.delivery —"
5. **Order ref**: "#" + ref, 13sp
6. **Timestamp**: fmtReceipt (branch tz), 11sp faint
7. **Diner name / table** (if dine-in): "Customer", 12sp
8. **Hairline separator**
9. **Line items**: item name + qty + price (aligned), 12sp × 11sp, no wrapping
10. **Modifiers** (addons): indent, smaller, faint
11. **Hairline separator**
12. **Subtotal, tax, discount** (if any): tabular, aligned right, 12sp
13. **Hero total**: **BOLD**, teal, 15sp, tabular
14. **Payment method**: "PAID WITH" + method name
15. **Change** (if cash): green, tabular, 12sp
16. **Tip** (if any): tabular, "TIP" + amount
17. **Hairline separator**
18. **Receipt notes** (optional): italic, faint
19. **Org footer** (if present): org name, address, contact (faint)

**Responsive**: max 360dp width, clip + border 1dp rule, 18dp padding

---

## 9. STATE FIELD NAMES & INITIALIZATION

### Core Fields (from AppModel init)
```kotlin
session: SessionSnapshot? = core.restoreSession(vault.loadBlob())
deviceConfig: DeviceConfigView = core.deviceConfig() [mirrored]
branchId, branchName: String [from deviceConfig]
orgLogoUrl: String? = core.orgLogoUrl() ?? vault.orgLogoUrl
reconfiguring: Boolean = core.deviceConfig().reconfiguring
themeMode: ThemeMode = vault.themeMode parsed
locale: String = vault.locale.ifBlank { core.locale() }
shift: ShiftView? = core.currentShift()
```

### Model.kt Public Methods (Grouped by Feature)
1. **Session**: signInTeller, reauth, reauthSwitchTeller, signOut
2. **Device**: setDevicePrinter, setLanHub, setDeviceTill, setDeviceStation, setDeviceCode, setLocale, setThemeMode
3. **Shift**: openShift, loadOpenShiftPrefill, reconcileShift, closeShift, loadShift
4. **Catalog**: loadCatalog, refreshServerData, reprojectCatalog
5. **Cart**: addToCart, setCartQty, removeCartLine, swipeRemoveCartLine, clearCart, loadCart
6. **Checkout**: placeOrder, dismissReceipt, cartQtyForItem
7. **Discount**: setDiscount
8. **Printing**: printReceipt, printShiftReport, printReportView, reprintOrder, printReceiptView
9. **History**: loadHistory, loadOrderDetail, voidOrder, searchOrders
10. **Receipt Preview**: openOrderReceiptPreview
11. **Close Shift**: loadShiftReport, openShiftReportPreview, openShiftReportPreviewFor
12. **Sync**: loadOutbox, refreshPending, retryOutbox, syncNow, discardOutboxItem
13. **Delivery**: loadDeliveryOrders, cycleAccepting, advanceDelivery, addDeliveryPrep, cancelDelivery, rejectDelivery, finalizeDelivery
14. **Waiter**: loadOpenTickets, fireTicket, addRound, fireOrAddRound, voidTicket, settleTicket
15. **Drafts**: loadDrafts, holdCart, restoreDraft, discardDraft, switchToHeldOrder
16. **Bundles**: loadBundles, openBundleDetail, closeBundleDetail, componentItem, addBundle
17. **Item Customization**: hasOptions, openItemDetail, editCartLine, closeItemDetail, recipePreview, addConfigured
18. **KDS**: loadKds, loadKdsStations, bumpKdsItem, unbumpKdsItem
19. **Cash/Shifts**: loadCashMovements, recordCashMovement, loadShiftHistory, loadOrdersForShift, reprintShiftReport
20. **Tills**: loadTills
21. **Floor Plan**: loadFloor, seatReservation, setTableStatus, notifyReservation, moveTicket
22. **Realtime**: startRealtime, startLanRelay, unsubscribeRealtime, onRealtimeEvent, onRealtimeConnection, showRealtimeAlert, dismissRealtimeAlert, openOrdersFromAlert
23. **Toast**: showToast, dismissToast, runToastAction
24. **Error/Nav**: flagError, clearError, goBack
25. **Diagnostics**: loadDiagnostics, clearDiagnostics

---

## SUMMARY

This Kotlin Compose POS mirrors the Flutter app's behavioral architecture:

1. **Single route-driven model** (core decides screen via AppRoute)
2. **Unified checkout drawer** (cashier, ticket, delivery share ONE component)
3. **One session-level SSE** (per-device realtime subscription, role-based topics)
4. **Responsive layouts** at 760dp breakpoint (wide = side-by-side, narrow = modal/drawer)
5. **Optimistic cart updates** (sync mutations, instant UI feedback)
6. **Held-orders strip** (RFC3339-sorted tabs, drag-to-reorder, creation-time preservation)
7. **Shared checker drawer** for split/tender/tip/discount (cashier only) + customer fields (cashier only)
8. **Offline safety net** (outbox, connectivity heartbeat, auth-paused handling)
9. **Waiter mode** (same cart, different terminal action: fire/round instead of checkout)
10. **KDS full-screen board** (station-bound, live ticket grid, per-line bump, SSE-driven)

All business logic, validation, ordering rules, and offline queuing live in the **core** (Rust). The Kotlin host is **pure UI** — state mirrors, haptics, toast, printing, networking, and navigation routing.