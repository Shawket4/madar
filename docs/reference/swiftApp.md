Perfect. Now let me compile the final report with all the information I've gathered:

## Final Report: SwiftUI App Architecture & Reference

### 1. **Inventory of Views/Screens** (File → Screen)

| File | Purpose | Characteristics |
|------|---------|------------------|
| **MadarApp.swift** | App entry point | WindowGroup host for RootView; single AppModel ownership |
| **ContentView.swift** | Home placeholder | Signed-in proof-of-concept (will be replaced; minimal) |
| **LoginView.swift** | PIN-based teller sign-in | Device-setup & branch-picker prior to login |
| **OpenShiftView.swift** | Shift opening | Cash count & opening-cash prefill from server |
| **OrderView.swift** | Main POS screen (82KB) | Heart of the app: catalog browse, cart, order management; responsive split layout (phone/tablet/desktop) |
| **OrderDetailsView.swift** | Placed order detail | Expand past order with line/modifier breakdown (from history) |
| **OrderHistoryView.swift** | Current shift orders | Synced + queued; stats pill, void/reprint per row |
| **OrderSearchView.swift** | Order lookup | Search by ref, date, customer; synced archive access |
| **TenderView.swift** | Checkout drawer | Payment method selection, cash change, tip, split payments, customer capture; driven by reusable CheckoutDrawer component |
| **ReceiptPaper.swift** | Receipt preview | White thermal-paper card (theme-invariant); shows order meta, items, modifiers, bundle breakdown, totals; printed + on-screen |
| **WaiterTicketsView.swift** | Ticket UI helpers | TicketStatusChip, VoidTicketSheet; shared across settle + order-details |
| **IncomingView.swift** | Unified "Orders" hub | Two-tab surface (delivery + waiter tickets); live counts, segmented control |
| **DeliveryView.swift** | Delivery queue management | Live delivery orders, status progression, prep-time, cancel/reject, finalize |
| **KitchenDisplayView.swift** | KDS board | Full-screen layout; ticket grid (oldest-first), bump-by-tap, age SLA coloring (fresh→amber→red) |
| **SettleTicketsView.swift** | Settle waiter tickets | Same CheckoutDrawer as tender; ticket hold/move/void |
| **FloorPlanView.swift** | Host board + reservations | Floor plan render (core-authored geometry), live table status, seat bookings, status picker |
| **CashAndShiftsView.swift** | Shift history & cash | Past shifts list (collapsible per-shift orders), cash movements, reprint Z-reports |
| **CloseShiftView.swift** | Shift closing | Cash count (with system expectation), optional note, verification |
| **SettingsView.swift** | Device settings | Theme (light/dark/system), language (en/ar), printer config, till binding, LAN relay, diagnostics, sign-out |
| **SyncView.swift** | Sync center / outbox | Queued + failed commands, retry + force-push actions; local reads (offline-safe) |
| **ShiftReportPreview.swift** | Z-report preview | Print mid-shift + past-shift reports (thermal-paper style) |
| **DraftsView.swift** | Held orders (parked carts) | Tab-style held-order switcher in the order screen; HH:MM naming |
| **ItemDetailView.swift** | Item customization sheet | Addons, sizes, optional fields, recipe preview (live); add/edit cart line |
| **BundleDetailView.swift** | Bundle (combo) sheet | Component selection with per-component addons |
| **StationPickerView.swift** | KDS station selection | One-time device-setup for kitchen-role devices |
| **ReauthView.swift** | Mid-shift token re-auth | Pin re-entry to resume syncing after 401 |

### 2. **Theme Directory: Design Tokens**

**File Structure:**
- `/Theme/Tokens.swift` — Core color, spacing, radius, icon size, opacity, motion, elevation, typography
- `/Theme/Typography.swift` — Typo enum (display, h1–h3, title, body, label, money sizes)
- `/Theme/Layout.swift` — Responsive (breakpoints: tablet 600, wide 760, desktop 1100)
- `/Theme/IconCatalog.swift` — SF-Symbol → Lucide icon mapping

**Key Token Values:**

| Category | Token | Light | Dark | Notes |
|----------|-------|-------|------|-------|
| **Colors** | bg | #EFF3F4 | #14181E | Paper ↔ Ink |
| | surface | #FFFFFF | #1B2128 | Card/elevated |
| | accent | #0D6273 (Teal) | #2E94A6 (Teal light) | Primary action |
| | textPrimary | #14181E | #EFF3F4 | Default text |
| | textSecondary | #54636B | #AEB9C0 | Muted body |
| | textOnAccent | #FFFFFF | #FFFFFF | Contrast |
| | success | #16A34A | #3BCE7E | Confirmation |
| | danger | #DC2626 | #F4655A | Destructive |
| | warning | #B45309 | #F0A23F | Caution |
| **Spacing** | xs/sm/md/lg/xl/xxl | 4/8/12/16/24/32 | — | 4-pt grid |
| **Radii** | xs/sm/md/lg/xl/pill | 8/12/16/20/24/999 | — | Continuous |
| **Icon Sizes** | xs–xxl | 12/14/16/18/20/24 | — | Semantic |
| **Motion** | pressScale | 0.97 | — | Spring press |
| | press anim | spring(0.22, 0.7) | — | Tactile press |
| | standard anim | easeOut(0.22) | — | UI transitions |
| **Elevation** | card | navy wash 0.07 (light) / black 0.45 (dark) | — | Surface shadow |
| | raised | navy wash 0.13 (light) / black 0.55 (dark) | — | Sheet shadow |
| | glow | accent @ 0.38 (light) / 0.55 (dark) | — | CTA radiance |

**Typography Scale** (Cairo font family, tabular figures for money):
- **display**: 34px, weight 900 (hero numbers)
- **h1**: 30px, weight 900 (screen titles)
- **h2**: 22px, weight 700 (sheet titles)
- **h3**: 17px, weight 600 (card titles)
- **title**: 15px, weight 600 (row emphasis)
- **body**: 14px, weight 500 (default)
- **bodySm**: 13px, weight 400 (secondary)
- **label**: 12px, weight 600 (section headers, uppercase with 0.6pt tracking)
- **money**: 14px, weight 700, tabular (amounts)
- **moneyLg**: 24px, weight 900, tabular (totals)
- **moneyDisplay**: 34px, weight 900, tabular (grand total hero)

**Deltas vs Kotlin Tokens:** None — Tokens.swift is identical 1:1 port of Kotlin Theme.kt. Color hex values, spacings, radii, motion timings, icon sizes all match byte-for-byte (barring the field-name legacy naming convention like `navy`/`terracotta`).

### 3. **MadarIcon.swift: Icon Mapping** (SF Symbol → Lucide Asset)

The icon system uses **shared Lucide SVG assets** (in `Assets.xcassets/Icons`), generated via `/tool/gen-icons.sh`. This ensures pixel-identical icons across SwiftUI + Kotlin.

**Generated Mapping Table** (`madarIconAsset`, 113 entries):

| SF Symbol Name | Lucide Asset | Usage Example |
|---|---|---|
| exclamationmark.circle | circle-alert | Error messages |
| exclamationmark.triangle | triangle-alert | Warnings |
| xmark | x | Close button |
| checkmark.circle | circle-check | Success confirmations |
| checkmark | check | Checkmark lists |
| trash | trash-2 | Delete action |
| person | user | Account/teller |
| lock | lock | Auth, locked state |
| lock.open | lock-open | Unlocked |
| chevron.backward | chevron-left | Back (RTL-aware) |
| chevron.forward | chevron-right | Forward (RTL-aware) |
| printer | printer | Print button |
| creditcard | credit-card | Card payment |
| wifi.slash | wifi-off | Offline indicator |
| arrow.triangle.2.circlepath | refresh-cw | Sync |
| icloud.and.arrow.up | cloud-upload | Cloud push |
| gearshape | settings | Settings |
| storefront | store | Branch/location |
| cart | shopping-cart | Shopping cart |
| fork.knife | utensils-crossed | Kitchen display |
| clock | clock | Time/schedule |
| tray | inbox | Orders/incoming |
| receipt | receipt | Receipt/order |
| chart.pie | pie-chart | Stats/reporting |
| qrcode | qr-code | QR scanning |
| banknote | banknote | Cash payment |
| building.2 | building-2 | Branch selection |
| hand.raised | hand | Manual action |
| circle | circle | Radio button (unselected) |
| largecircle.fill.circle | circle-dot | Radio button (selected) |

**RTL Support:** `MadarIcon.mirror` dict flips directional glyphs (chevron.right ↔ chevron.left, chevron.forward ↔ chevron.backward) when `layoutDirection == .rightToLeft`.

### 4. **AppModel.swift: Public Surface** (Key State + Methods)

**Observable Properties:**
```swift
@Published var session: SessionSnapshot?          // Active login; nil = signed out
@Published var shift: ShiftView?                  // Current open shift (nil = closed)
@Published var cartLines: [CartLineView]          // In-progress cart (kv-persisted)
@Published var receipt: ReceiptView?              // Last placed order (for confirmation)
@Published var themeMode: ThemeMode               // light/dark/system preference
@Published var locale: String                     // en/ar (live; triggers re-projection)
@Published var deviceConfig: DeviceConfigView     // Branch/till/station binding
@Published var isOnline: Bool                     // Connectivity state
@Published var pendingCount, syncFailed: Int      // Outbox stats
@Published var realtimeConnected: Bool            // SSE connection live
@Published var errorMessage: String?              // Top-level error slot
```

**Major Methods:**
- **Sign-In/Out**: `signInTeller(name:pin:)` (PIN-based; core decides online↔offline), `reauth(pin:)` (mid-shift token refresh), `reauthSwitchTeller()`
- **Shift**: `openShift(openingCashMinor:editReason:)`, `closeShift(closingCashMinor:note:)`, `reconcileShift()` (fetch server state on login)
- **Catalog**: `loadCatalog()` (pull + cache), `reprojectCatalog()` (re-resolve on locale change), `syncServerData()` (manual refresh with user feedback)
- **Cart**: `addToCart(_:)`, `setCartQty(_:_:)`, `removeCartLine(_:)`, `swipeRemoveCartLine(_:)`, `undoRemoveCartLine()`, `clearCart()`, `holdCart()`, `restoreDraft(_:)`, `switchToHeldOrder(_:)`
- **Item Customization**: `openItemDetail(_:editKey:editLine:)`, `editCartLine(_:)`, `closeItemDetail()`, `recipePreview(itemId:sizeLabel:addons:optionalIds:)` (live ingredient preview), `addConfigured(itemId:sizeLabel:addons:optionalIds:qty:notes:)`
- **Checkout**: `placeOrder(paymentMethodId:amountTenderedMinor:tipMinor:tipPaymentMethodId:customerName:notes:splits:)`, `dismissReceipt()`
- **Receipt Print**: `printCurrentReceipt(kickDrawer:)` (auto-print on checkout, cash drawer kick), `printReceiptView(_:)` (reprint), `printShiftReport()` (Z-report)
- **Sync Center**: `loadOutbox()`, `retryOutbox()`, `syncNow()`, `discardOutboxItem(_:)`, `refreshPending()` (refresh sync stats chip)
- **Delivery**: `loadDeliveryOrders()`, `advanceDelivery(_:)`, `addDeliveryPrep(_:minutes:)`, `cancelDelivery(_:reason:restoreInventory:)`, `rejectDelivery(_:)`, `finalizeDelivery(_:paymentMethodId:)`
- **Tickets (Waiter)**: `loadOpenTickets()`, `voidTicket(_:reason:)`, `settleTicket(ticketId:input:)`
- **KDS**: `loadKds()`, `loadKdsStations()`, `bumpKdsLine(ticketId:lineId:)`
- **History**: `loadHistory()`, `loadOrderDetail(_:)`, `voidOrder(orderId:reason:note:restoreInventory:)`, `reprintOrder(_:)`
- **Device Config**: `setDevicePrinter(host:brand:)`, `setDeviceTill(_:)`, `setDeviceStation(_:)`, `setDeviceCode(_:)`, `setDeviceLanHub(_:)`, `refreshDeviceConfig()`
- **Floor Plan**: `loadFloor()`, `setTableStatus(_:status:)`, `seatReservation(_:tableIds:)`, `notifyReservation(_:)`
- **Toast**: `showToast(_:icon:tone:actionLabel:action:seconds:)`, `runToastAction()`

**Differences from Kotlin AppModel:**
- SwiftUI: token storage uses **KeychainTokenStore** (secure enclave); Kotlin uses Android KeyStore
- SwiftUI: theme + locale are **@Published** properties (live switching with core re-render); Kotlin threads through theme context
- SwiftUI: draft/held-order RFC3339 timestamps (`cartStartedAtIso`) manage the sort key + "HH:MM" display; Kotlin's `holdCart` is simpler
- SwiftUI: **single-flight realtime** (one SSE per session, KDS/waiter/teller all subscribe to the same stream); Kotlin subscriptions are app-level
- SwiftUI: `NetworkPrinter` endpoint on `MadarCore` (host does network I/O); Kotlin printer sends bytes directly

### 5. **Behavior Deltas: Swift vs Kotlin** (Both on `ui-rework-bold-refresh`)

| Feature | SwiftUI Behavior | Kotlin Behavior | Platform-Specific Notes |
|---------|---|---|---|
| **Typography** | "Go bolder" scale: display 34px/900, h1 30px/900, h2 22px/700 | Identical scale in Compose Type object | Both match Cairo font weights |
| **Press Scale** | 0.97 spring (response: 0.22, dampingFraction: 0.7) | 0.97 spring (Android spring constant) | Tactile spring signature matches |
| **Motion Timing** | .standard = easeOut(0.22) | Standard = easeOut(duration: 220ms) | Both ~220ms ease-out |
| **Elevation** | card/raised/glow with platform shadows (navy wash light, black dark) | Compose elevation composables (shadow color strategy same) | Light-mode uses navy tint; dark uses pure black |
| **Icons** | Lucide SVG from Assets.xcassets; SF Symbol fallback (sfSymbol()) if Lucide unmapped | Lucide resource + Material vector fallback | Both primary=Lucide, secondary=system vectors |
| **Haptics** | `Haptics.selection()` (UIImpactFeedbackGenerator), `Haptics.warning()` (UINotificationFeedbackGenerator) | Kotlin: Android Vibrator HAL | iOS tactile feedback stronger/finer control |
| **Realtime SSE** | One session-level subscription per device (KDS/waiter share same stream) | Same single-stream architecture | Both dedupe via event tag |
| **Cart Drafts** | RFC3339 `cartStartedAtIso` stamped on empty→non-empty; "HH:MM" label via `formatHHMM()` helper | Simpler: just persist cart snapshot, no explicit timestamp | SwiftUI's sort key ensures drafts keep chronological slot |
| **Printer I/O** | SwiftUI: `core.sendToPrinter(host:port:bytes:)` blocks host task | Kotlin: direct JetDirect TCP socket from app | Both non-blocking async; Swift awaits print completion |
| **Locale Live-Switch** | Text/RTL re-render instantly (core re-projects catalog views on `setLocale`) | Same: Compose recomposes on locale change | Both transparent to screens (catalog bound to @Published list) |
| **Responsive Layout** | GeometryReader width thresholds (wide ≥760) → split left/right cart column; phones collapse to bottom-sheet | Compose WindowSizeClass (similar breakpoints) | Both phone/tablet/desktop support; wide shows persistent cart |
| **Bottom Sheet** | Custom `MadarSheet` (draggable, scrim-tap-to-dismiss, custom sizing) | Flutter ResponsiveSheet mirrored in Compose | SwiftUI sheet stack handled manually (no competing .sheet modifiers) |
| **Floor Plan** | SVG-free: renders from core's FloorTableView geometry (x, y, w, h); table color by status | Same core-driven geometry | Pure vector layout (no raster); touch to set status, multi-select for merge |
| **Void Confirmation** | VoidTicketSheet with optional reason picker + free note field | Identical Compose sheet structure | Both compose reason string on confirm |

### 6. **Orientation & Responsive Layout**

**Orientation Locking:**
- **Supported**: Portrait + Landscape Left/Right (set in `Info-iOS.plist`: `UISupportedInterfaceOrientations`)
- **No explicit lock**: App adapts to all three; no forced portrait-only or landscape-only override
- iPad can rotate; iPhone follows device lock unless user overrides

**Responsive Split (SwiftUI):**
```swift
GeometryReader { geo in
    let wide = geo.size.width >= Responsive.wide  // 760pt
    
    if wide {
        HStack {
            catalogColumn()                          // Left: menu grid
            CartPanel(...)                           // Right: sticky cart column (340pt)
        }
    } else {
        VStack {
            catalogColumn()                          // Full-width menu grid
            CartBar(...)                             // Bottom bar; tap to open sheet
        }
    }
}
```

**Breakpoints** (`Responsive` enum):
- **tablet** = 600 → wider forms, tighter spacing
- **wideTable** = 680 → table layout (history, shifts)
- **wide** = 760 → split layout (order/login) + persist right column
- **desktop** = 1100 → cap content + center (not yet enforced)

**iPad/Desktop Behavior:**
- Wide screens: cart is a persistent right panel (no sheet); tender opens as a second sheet beside catalog
- Phones: cart is a bottom sheet; tap checkout to swap sheet content to tender
- Floor plan + KDS: full-screen board, no responsive change (already optimized for iPad)

---

This report captures the complete SwiftUI app as a behavioral reference for the Flutter rebuild. All token values, icon mappings, screen inventory, and responsive patterns are now documented for parity with the Kotlin/Flutter versions.