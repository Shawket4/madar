# UI grounding — the approved design mapped to what the bridge can do

*2026-09-12 · the Ground phase for `/home/apex/ClaudeProjects/pos-ui-sketch.md` · written against
`packages/rust_bridge/lib/src/generated/api/bridge.dart` as it stands today (frb 2.13.0: 151 methods
on `MadarBridge` + 3 free functions).*

The owner's one criticism of the design is that it "isn't fully rooted to the actual app features".
This document is the root. Every control in the design is tied here to the exact bridge call that
backs it, or is named as a gap with the honest substitute. Builders work from this, not from the
sketch's assumptions.

Ground rules that follow from the code, not from taste:

1. **`bridge.dart` is the whole surface.** Dart never talks HTTP. If a call is not in §1 it does not
   exist for the till, no matter what the server has (§6 lists what the server has that the bridge
   does not — those are asks for the master, not things to build against).
2. **Every string is `bridge.tr(key: ...)`.** The key table is compiled into
   `rust-core/crates/madar-core/src/i18n.rs` (504 keys, en + ar). There is no Dart-side string
   table. A new user-visible string therefore needs a new key in the core — put it in
   `needsFromOthers`; until it lands, reuse an existing key (Appendix A lists all of them by
   namespace). Do not hardcode, not even "temporarily".
3. **Pricing lives in the core.** `SessionSnapshot` carries `taxRate / taxInclusive /
   serviceChargeRate / serviceChargeTaxable` so screens can *word* things correctly, but no screen
   computes money: cart money comes from `cartTotals()`, bill money from the server, sale money from
   `orderDetail()` / `orderReceiptView()`.
4. **Realtime arrives as ticks.** `apps/madar/lib/app/boot.dart` maps event prefixes to
   `app_core` providers: `kitchen.*` → `kitchenTickProvider`, `ticket.*` → `ticketTickProvider`,
   `delivery.*` / `order.*` → `deliveryTickProvider`, `floor.*` / `table.*` / `transfer.*` /
   `booking.*` → `floorTickProvider` (+ `bookingTickProvider`). A screen watches its tick and
   re-reads. Alerts (chime / OS notification / haptic) are decided in the core (`AlertCommand`).
5. **Times go through `formatTime(rfc3339, style)`** (`TimeStyle.time | dateShort | dateTime |
   receipt`) — branch timezone, never the device's. Money through `MoneyText` (Plex Mono, tabular,
   forced LTR).
6. **Errors are `MadarError`**: `offline · unauthenticated · forbidden(resource, action) ·
   validation(field, detail) · server(status, code, detail) · transient · internal`. "The server's
   sentence" on a refused row is `server.detail` / `OutboxItemView.lastError`.

---

## 1. The bridge surface, grouped by what it is for

Signatures abbreviated; `→` is the return type. `[online]` = fails offline with `MadarError.offline`
(everything else works from the mirror or the outbox). `[sync]` = synchronous.

### Boot, device, identity
- `ffiSurfaceVersion() → int` [sync] · `coreVersion() → String` · `version() → String` ·
  `environment() → String` (`prod|staging|dev`) · `baseUrl() → String` · `dbPath() → String` ·
  `greet(name)` (smoke test).
- `MadarBridge.newInstance(config: MadarConfig{baseUrl, environment, dbPath, locale})`.
- `deviceConfig() → DeviceConfigView{branchId, branchName, tillId, stationId, printerHost, printerPort,
  printerBrand, printerTransport, printerBtAddress, printerBtName, printerPaperDots, reconfiguring,
  lanHub, configured}` [sync] · `deviceCode() → String` [sync] · `setDeviceCode(code)` [sync].
- `setDeviceBranch(branchId, branchName?)` · `setDeviceTill(tillId?)` · `setDeviceStation(stationId?)` ·
  `setDevicePrinter(host?, port?, brand?)` · `setDevicePrinterBt(address?, name?)` ·
  `setDevicePrinterPaper(dots?)` (384 = 58 mm, 576 = 80 mm) · `setDevicePrinterTransport(kind)`
  (`bluetooth|lan`) · `setDeviceLanHub(hub?)` · `startReconfigure()` · `clearDevice()`.
- `listBranches() → List<BranchView{id, name, isActive, orgLogoUrl}>` [online, manager session] ·
  `listTills() → List<TillView{id, name, isDefault, isActive}>` (write-through cached) ·
  `kdsListStations() → List<KdsStationView{id, name, isDefault, isActive, printerBrand, printerIp, printerPort}>`.

### Session, auth, ACL
- `appRoute() → AppRoute` [sync]: `deviceSetup | login | openShift | order | kitchenDisplay(stationId) |
  waiterTickets`. The core decides: unbound → deviceSetup; no session → login; role `kitchen` →
  kitchenDisplay (or deviceSetup with no station); role `waiter` → waiterTickets (no shift gate);
  else open shift owned by THIS user → order, otherwise openShift.
- `currentSession() → SessionSnapshot?` [sync] `{userId, displayName, role, orgId, branchId,
  currencyCode, taxRate, taxInclusive, serviceChargeRate, serviceChargeTaxable,
  requireTableForOrders, online, permissionsLoaded}`.
- `isAuthenticated()` [sync] · `login(req)` [online] · `signIn(req)` (online first, offline PIN
  fallback) · `unlockOffline(name, pin, branchId)` · `restoreSessionCached()` [sync] ·
  `restoreSession(blob)` (legacy) · `logout(wipeOutbox)`.
- `LoginRequest{mode: pin|email, name?, pin?, branchId?, email?, password?, orgId?}`.
- `hasPermission(resource, action) → bool` [sync] — cached `/auth/permissions`; optimistic while
  `permissionsLoaded == false`. Known pairs used by the core's tests: `orders/create`,
  `orders/void`, `orders/delete`, `shifts/create`, `menu/create`.

### Locale, time, presentation
- `locale()` · `setLocale(locale)` [sync] · `isRtl()` [sync] · `tr(key)` [sync] ·
  `formatTime(rfc3339, style)` [sync] · `branchTimezone()` [sync] · `clockSkewMinutes()` [sync] ·
  `categoryStyle(name, dark) → CatStyleView{icon, bgTop, bgBottom, iconColor, accent}` [sync]
  (legacy gradient palette — the new kit is flat; use only `icon`).

### Connectivity, sync, outbox, realtime, LAN
- `refreshConnectivity() → bool` · `syncStatus() → SyncStatusView{pending, failed, blocked, online,
  authPaused}` · `pendingOutboxCount() → int`.
- `listOutbox() → List<OutboxItemView{id, opType, status, attempts, lastError, eventAt}>` —
  `status ∈ pending | dead` (acked hidden); `opType ∈ open_shift | close_shift | cash_movement |
  create_order | void_order | open_ticket | ticket_add_round | void_ticket | settle_open_ticket |
  award_loyalty_points | hold_table | clear_table | seat_booking | no_show | transfer | swap_tables |
  lan_mirror`.
- `syncNow()` · `retryOutbox()` (ALL dead rows — there is no per-row retry) ·
  `discardOutboxItem(id) → bool` (per row) · `recoverOrphanedOrders() → int` (the BLOCKED fix).
- `recentLogs() → List<DiagLogView{at, level, message}>` · `clearLogs()`.
- `startRealtime(events, alerts)` · `unsubscribeRealtime()` [sync] · `isRealtimeSubscribed()` [sync].
  Topics per role are chosen in the core: waiter = tickets, kitchen, floor, bookings; kitchen =
  kitchen; everyone else = delivery, kitchen, tickets, orders, floor, bookings.
- `lanStart()` · `lanStop()` · `lanActive()` [sync] · `lanPeerCount()` [sync] ·
  `lanBranchHasOpenTill()` [sync] (the freshest "is a till open at this branch" signal — the
  waiter's pre-fire warning).

### Catalog (offline mirror; `refreshCatalog()` [online] refills it)
- `listCategories() → List<CategoryView{id, name, imageUrl, isActive}>`.
- `listMenuItems() → List<MenuItemView{id, name, description, categoryId, basePriceMinor, imageUrl,
  localImagePath, isActive, defaultMilkAddonId, allowedAddonIds, sizes[ItemSizeView{id, label,
  priceMinor, isActive}], addonSlots[AddonSlotView{id, label, addonType, isRequired, minSelections,
  maxSelections}], optionalFields[...], recipes[...], recipeSteps[RecipeStepView{name, note,
  localAnimationPath, animationUrl}]}>`.
- `availableBundles(nowRfc3339) → List<BundleView{id, name, description, priceMinor, imageUrl,
  localImagePath, isAvailable, availableFrom/Until Date/Time, components[...]}>`.
- `listAddonCatalog()` · `listItemAddons(itemId) → List<ItemAddonView{addonItemId, name, addonType,
  chargedPriceMinor}>` · `listItemModifierGroups(itemId) → List<ModifierGroupView{groupId, name,
  kind: addon|optional, addonType, isRequired, minSelections, maxSelections,
  options[ModifierOptionView{id, name, chargedPriceMinor}]}>` (the unified sheet model).
- `validateItemSelections(itemId, addons, optionalFieldIds) → List<GroupViolationView{groupId,
  groupName, minRequired, maxAllowed, selected}>` (empty = valid) ·
  `computeRecipe(itemId, sizeLabel?, addons, optionalFieldIds) → List<ComputedRecipeLineView>`.
- `listPaymentMethods() → List<PaymentMethodView{id, name, isCash, icon, color}>` ·
  `listDiscounts() → List<DiscountView{id, name, dtype, value, isActive}>`.
- `orgLogoUrl() → String?` · `orgLogoLocalPath() → String?` [sync].

### Cart (device-local; the core owns it)
- `cartLines() → List<CartLineView{key, itemId, name, sizeLabel, addons, optionals, notes,
  unitPriceMinor, qty, lineTotalMinor, bundleId, bundleComponents}>` ·
  `cartTotals() → CartTotals{itemCount, subtotalMinor, discountMinor, taxMinor, serviceChargeMinor,
  totalMinor}` (priced by the core at the session's tax policy).
- `cartAdd(itemId, name, unitPriceMinor)` (quick-add; merges) ·
  `cartAddConfigured(itemId, sizeLabel?, addons, optionalFieldIds, qty, notes?)` ·
  `cartAddBundle(bundleId, components, qty)` · `cartSetQty(itemId, qty)` (`qty <= 0` removes) ·
  `cartRemove(itemId)` · `cartRestoreRemoved()` (the undo toast) · `cartClear()`.
- `cartSetDiscount(discountId)` · `cartClearDiscount()` · `cartDiscountId() → String?`.

### Parked carts (held orders / drafts)
- `listDrafts() → List<DraftView{id, name, itemCount, totalMinor, createdAt, tableId, tableLabel,
  lockedByOther}>` (every till's) · `holdCart(name, draftId?, startedAt?)` ·
  `holdCartOnTable(..., tableId?) → bool` (true = table was taken, parked without it — the design
  never calls this) · `restoreDraft(id) → cart lines` (claims it) · `releaseDraft(id)` (never mind)
  · `completeDraft(id, orderId?)` (after ring-up) · `discardDraft(id)` · `assignDraftTable(id, tableId?)`.

### Counter sale, receipts, printing
- `checkout(input: CheckoutInput{paymentMethodId, amountTenderedMinor, tipMinor, tipPaymentMethodId?,
  customerName?, notes?, splits[CheckoutSplit{paymentMethodId, amountMinor}], loyaltyCustomerId?,
  loyaltyRedemptions[CheckoutRedemption{itemIndex, ticketLineId?, units}]}) → ReceiptView`.
  Works offline: `receipt.queuedOffline == true`, `orderNumber == null`, `localOrderId` set.
- `ReceiptView{localOrderId, orderNumber, orderRef, isVoided, lines, paymentLabel, subtotalMinor,
  discountMinor, taxMinor, serviceChargeMinor, deliveryFeeMinor, totalMinor, tipMinor,
  amountTenderedMinor, changeMinor, isCash, customerName, tellerName, isDelivery, deliveryChannel,
  customerPhone, deliveryAddress, deliveryZone, deliveryRef, paymentHint, deliveryNotes,
  queuedOffline, createdAt}`.
- `orderReceiptView(orderId) → ReceiptView` (preview; cached for any order seen online) ·
  `renderReceipt(receipt, storeName, currency, width, brand) → bytes` ·
  `renderOrderReceipt(orderId, storeName, currency, width, brand) → bytes` ·
  `renderKitchenChit(chit, width, brand)` · `renderShiftReport(report, storeName, currency, width,
  brand, orders)` · `cashDrawerKick(brand) → bytes`.
- `sendToPrinter(host, port, bytes)` (raw TCP) · `printToDevice(bytes)` (the device's bound
  printer). The Flutter side actually prints through `app_core`'s `PrinterService` (TCP or
  Bluetooth transport chosen from `deviceConfig().printerTransport`).

### Floor, seating, bookings, transfers
- `floorLayout() → FloorLayoutView{sections[FloorSectionInfo{id, name, ordering, canvasW, canvasH}],
  tables[FloorTableStateView{id, sectionId, label, seats, shape: rect|circle, status: free|held|
  seated|dirty, posX, posY, width, height, rotation, heldOrderId, heldOrderName, heldSince,
  heldLockedByOther, bookingId, bookingGuest, bookingParty, bookingStartsAt, bookingHeldFrom,
  bookingStatus: confirmed|seated}]}` — EMPTY sections + tables = no floor (the gate).
- `refreshFloor()` (best-effort re-pull; call on opening the floor and on a floor tick) ·
  `seatTable(tableId)` · `unseatTable(tableId)` · `clearTable(tableId)` (dirty → free) ·
  `mirrorTableStatus(tableId, status)` (local mirror only) · `swapFloorTables(tableA, tableB)`
  (held orders and/or tickets; one empty side = a move).
- `listArrivals() → List<BookingView{id, status, partySize, startsAt, endsAt, heldFrom, guestName,
  guestPhone, notes, tableIds, tableLabels, needsTable, source}>` · `refreshArrivals()` ·
  `seatBooking(bookingId, tableId?)` · `noShowBooking(bookingId)`.
- `listTransferQueue() → List<TransferQueueView{id, occupantKind: held_order|open_ticket,
  occupantId, occupantLabel, fromTableId, fromTableLabel, targetSectionId, targetSectionName,
  targetTableId, targetTableLabel, note, status: waiting|fulfilled|cancelled, createdAt}>` ·
  `createTransfer(occupantKind, occupantId, targetSectionId?, targetTableId?, note?)` ·
  `fulfillTransfer(id, tableId)` · `cancelTransfer(id)`.

### Bills (open tickets)
- `listOpenTickets() → List<TicketView{id, ticketRef, tableId, status, customerName, waiterName,
  guestCount, subtotalMinor, orderId, openedAt, queuedOffline, lines[TicketLineView{id, menuItemId,
  name, qty, sizeLabel, modifiers, lineTotalMinor, voided, roundNumber, roundFiredAt}]}>` —
  `status ∈ open | ready | queued` in this list (`settled | voided` exist on the wire but such
  tickets are not listed). Write-through cached + queued fires overlaid.
- `getTicket(ticketId) → TicketView` [online; queued tickets have no server id].
- `fireTicket(tableId?, customerName?, notes?, guestCount?, bookingId?) → TicketFiredView{ticketId,
  ticketRef, queuedOffline}` (round 1 from the cart; clears the cart) ·
  `addTicketRound(ticketId) → TicketFiredView` (from the cart).
- `voidTicket(ticketId, reason?) → bool` (true = queued). Reason keys the core maps to the wire:
  `customer|customer_request → customer_request`, `mistake|wrong_order → wrong_order`,
  `quality|quality_issue → quality_issue`, anything else → `other` (with the raw text as the note).
- `settleTicket(ticketId, shiftId, paymentMethodId, amountTenderedMinor?, tipMinor?,
  tipPaymentMethodId?, discountId?, discountType?, discountValue?, loyaltyCustomerId?,
  loyaltyRedemptions) → String?` (order id once acked; `null` while queued offline). **No splits.**

### Kitchen (KDS)
- `kdsList(stationId?) → List<KdsTicketView{id, kitchenRef, tableLabel, roundNumber, sourceType,
  status: firing|ready|voided, createdAt, items[KdsLineView{id, name, qty, sizeLabel, modifiers,
  notes, stationId, stationName, bumped}]}>` (oldest first, ready last) ·
  `kdsBump(itemId)` · `kdsUnbump(itemId)` (both outbox-first, per LINE).

### Online orders (delivery)
- `listDeliveryOrders(status?) → List<DeliveryOrderView{id, orderRef, channel, status, customerName,
  customerPhone, address, deliveryNotes, paymentHint, subtotalMinor, discountMinor,
  deliveryFeeMinor, totalMinor, itemCount, lines[TicketLineView], createdAt, isTerminal}>`
  [online] — `status ∈ received | confirmed | preparing | ready | out_for_delivery | delivered |
  cancelled | rejected`; `channel` is the wire string (`in_mall | outside | pickup | umbrella`).
- `deliveryOrderDetail(id)` · `deliveryAdvanceStatus(id, current)` (one forward step; stops at
  `out_for_delivery` — `delivered` is finalize-only) · `deliverySetStatus(id, status)` ·
  `deliverySetPrepTime(id, extraMinutes)` (≥ 0, multiple of 5, ON TOP of the branch base) ·
  `deliveryCancel(id, reason?, restoreInventory)` (one cancel call for every state; the design
  says the server records `rejected` when the order was still `received` — the client crate does
  not document that, so render whatever `status` comes back) ·
  `deliveryFinalize(id, paymentMethodId) → DeliveryFinalizeView{orderId,
  orderRef, warnings}` (needs an open shift; method only — no tendered / tip / discount / split).
- `deliverySettings() → DeliverySettingsView{inMallEnabled, inMallOverride, inMallFeeMinor,
  outsideEnabled, outsideOverride, prepTimeMinutes}` · `deliverySetAccepting(channel: in_mall|outside,
  mode: auto|open|closed)`.

### Loyalty
- `classifyLoyaltyInput(raw) → LoyaltyScanInput{kind, value}` [sync, per keystroke] ·
  `loyaltyLookup(token?, phone?) → LoyaltyScanView{member: LoyaltyMemberView{id, name, phone,
  mode: points|visits, balance, nextRewardCost, rewardsReady, progressToNext, pointsToNextReward,
  canRedeem, progressLabel, balanceLabel}, rewards[LoyaltyRewardView{menuItemId, name, priceMinor,
  costCurrency, costAmount, costLabel}], recent[LoyaltyLedgerView], anyItem, anyItemCost}` [online].
- `loyaltyAward(orderId?, orderKey?, orderCreatedAt, token?, phone?, customerId?) →
  LoyaltyAwardOutcome{member?, queued, alreadyCollected, pointsAwarded, headline, detail}`
  (already phrased; works offline → `queued`) · `loyaltyAwardWindowOpen(orderCreatedAt, now) → bool` [sync].

### Shift, drawer, reports
- `currentShift() → ShiftView?{id, branchId, tellerId, tellerName, openingCashMinor, openedAt,
  status, isOpen}` · `refreshShift()` [online; call on login + resume] ·
  `suggestedOpeningCashMinor() → int` (this device's previous declared close).
- `openShift(openingCashMinor, openingReason?)` · `closeShift(closingCashMinor, cashNote?)` (both
  outbox-first).
- `recordCashMovement(amountMinor, note) → CashMovementView` (sign = direction; **no kind, no
  correction link**) · `listCashMovements() → List<CashMovementView{id, amountMinor, note,
  movedByName, createdAt}>`.
- `shiftReport() → ShiftReportView{tellerName, openedAt, closedAt, printedAt, isOpen,
  expectedCashMinor, openingCashMinor, openingCashWasEdited, openingCashOriginalMinor,
  openingCashEditReason, closingCashDeclaredMinor, totalPaymentsMinor, netPaymentsMinor,
  voidedAmountMinor, cashMovementsNetMinor, cashInMinor, cashOutMinor,
  paymentLines[{method, isCash, orderCount, totalMinor}], cashMovements[...], fromServer}` ·
  `shiftReportFor(shiftId)` · `shiftStats(orders) → {salesMinor, orderCount}` [pure].
- `listShifts() → List<ShiftSummaryView{id, branchName, tellerName, openedAt, closedAt,
  openingCashMinor, closingDeclaredMinor, closingSystemMinor, discrepancyMinor, status: open|closed|
  force_closed, isOpen}>` (the BRANCH's shifts, every teller, newest first) ·
  `listShiftOrders() → List<OrderSummaryView>` (this shift: queued + synced) ·
  `listOrdersForShift(shiftId)`.

### Orders (history)
- `OrderSummaryView{id, orderNumber, subtotalMinor, taxMinor, totalMinor, paymentLabel, status,
  createdAt, queued, tellerName, orderType: dine_in|delivery|…, customerName, orderRef}`.
- `orderDetail(orderId) → OrderDetailView{id, orderNumber, status, paymentLabel, subtotalMinor,
  discountMinor, taxMinor, totalMinor, createdAt, lines[{name, qty, sizeLabel, lineTotalMinor,
  addons, optionals}]}` (cached once seen online).
- `searchOrders(status?, tellerName?, paymentMethod?, from?, to?, page) → OrderSearchPage{orders,
  page, total, hasMore}` [online, 50/page] — **no number / phone / amount parameter**.
- `voidOrder(orderId, reason, note?, restoreInventory)` (outbox-first; same reason map as
  `voidTicket`).

---

## 2. Vocabularies the screens switch on

| Thing | Values | Source |
|---|---|---|
| Role | `super_admin · org_admin · branch_manager · teller · waiter · kitchen` | `SessionSnapshot.role` (wire enum). The core's `appRoute()` treats anything that is not `waiter`/`kitchen` as teller-class. **Manager shell = role ∉ {teller, waiter, kitchen}.** |
| Table status | `free · held · seated · dirty` (+ derived *reserved* when `bookingHeldFrom` has passed and nobody sits; + derived *taken* when `bookingStatus == seated`) | `FloorTableStateView` |
| Bill status | `open · ready · queued` (listed) · `settled · voided` (wire only) | `TicketView.status` |
| KDS ticket | `firing · ready · voided`; line `bumped` | `KdsTicketView` |
| Online order | `received · confirmed · preparing · ready · out_for_delivery · delivered · cancelled · rejected` | `DeliveryOrderView.status`; keys `delivery.status.*`, `delivery.action.*` |
| Channel | `in_mall · outside · pickup · umbrella` | `DeliveryOrderView.channel`; keys `delivery.in_mall/outside/pickup/umbrella` |
| Accepting | `auto · open · closed` | `DeliverySettingsView.*Override`; keys `delivery.mode_*` |
| Outbox row | `pending · dead` | `OutboxItemView.status` |
| Shift | `open · closed · force_closed` | `ShiftSummaryView.status` |
| Booking | `confirmed · seated` (on a table); `BookingView.status` wire string | floor / arrivals |
| Transfer | `waiting · fulfilled · cancelled` | `TransferQueueView.status` |
| Void reason (host keys) | `mistake · customer · quality · other` (mapped by the core) | keys `void.reason_*` |
| Loyalty mode | `points · visits` (balance label `points` / `orders`) | `LoyaltyMemberView.mode` |
| Sale type | `dine_in · delivery` (+ whatever the server writes) | `OrderSummaryView.orderType`; keys `history.type.*` |

---

## 3. Flags and overrides the till can read today

"Branch wins when set; NULL inherits" is done **on the server**: the till only ever sees the
merged, effective value. There is no way to tell an org value from a branch override from Dart.

| Flag in the design | Readable? | Where from | Read today in |
|---|---|---|---|
| **Floor authored** | yes | `floorLayout()` — sections or tables non-empty | `orderProvider.hasFloor` (`packages/features/order/lib/src/order_providers.dart:155`); `shell.dart:110` |
| **Every sale on a table** (`require_table_for_orders`) | yes | `currentSession()!.requireTableForOrders` — from login `/auth/login`, re-adopted on sync from `/auth/me`, cached for offline unlock | `apps/madar/lib/app/shell.dart:110` |
| **Tax inclusive** | yes | `currentSession()!.taxInclusive` (+ `taxRate`, fraction 0.14 = 14 %) | nowhere in Dart yet (the core prices with it) |
| **Service charge rate** (+ taxable) | yes | `currentSession()!.serviceChargeRate`, `.serviceChargeTaxable` | nowhere in Dart yet |
| **Currency code** | yes | `currentSession()!.currencyCode` | every money label |
| **Payment methods** (count) | yes | `listPaymentMethods()` (mirror) | `checkout_provider.dart:358/468` |
| **Discounts** (any active) | yes | `listDiscounts().where(isActive)` | `checkout_provider.dart:360` |
| **Delivery channels** | partly | `deliverySettings()` [online]: `inMallEnabled/Override/FeeMinor`, `outsideEnabled/Override`, `prepTimeMinutes`. `pickup` / `umbrella` are on the wire but NOT in the view | `incoming_provider.dart` |
| **Locale / RTL** | yes | `locale()`, `isRtl()`, `setLocale()` → `localeProvider` | `shell.dart` |
| **Role** | yes | `currentSession()!.role` | `shell.dart`, `chrome.dart`, `order_providers.dart:315` (`isWaiter`) |
| **Permissions** | yes | `hasPermission(resource, action)`, `permissionsLoaded` | nowhere in Dart yet |
| **Device binding** (branch, till, station, printer, LAN hub, code) | yes | `deviceConfig()`, `deviceCode()`, `listTills()`, `kdsListStations()` | settings, auth, shift, checkout |
| **Online / queued / stuck / blocked / auth paused** | yes | `syncStatus()`, `pendingOutboxCount()`, `listOutbox()` | `order_providers.dart`, `shift_providers.dart`, `sync_provider.dart` |
| **Clock skew** | yes | `clockSkewMinutes()` | `order_providers.dart` |
| **Live updates** | yes | `isRealtimeSubscribed()` + `realtimeConnectedProvider` | settings |
| **LAN** | yes | `lanActive()`, `lanPeerCount()`, `lanBranchHasOpenTill()` | settings (first two) |
| **Bundles window** | yes | `availableBundles(now)` | order |
| **Org logo** | yes | `orgLogoUrl()`, `orgLogoLocalPath()` | checkout |
| **Environment / server / versions** | yes | `environment()`, `baseUrl()`, `coreVersion()`, `version()` | settings |
| **Loyalty enabled / programme mode** | yes | `loyaltySettings() → LoyaltyProgrammeView {enabled, mode, programName, balanceLabel}`, write-through cached | checkout (every loyalty control), history (*Add points*) |
| **Kitchen routing mode** (`off · till · kds · both`) | yes | `kitchenRoutingMode()` (null until first reach), `setKitchenRoutingMode(mode)`; `kitchenRoutingModeProvider` + `tillShowsKitchen`/`kitchenIsRouted` | Queue (segment gate), settings (Diagnostics) |
| **Tips enabled** | **NO** | does not exist anywhere, wire included | — |
| **Standard float / safe-drop suggestion** | **NO** | does not exist on the wire | — |
| **Receipt footer / branding** | **NO** | on the org model server-side; the till never receives it | — |

---

## 4. Screen by screen

Legend: **fully** = every drawn control has a call · **partly** = built with the named controls
hidden/relabelled · **not-yet** = the screen cannot exist honestly yet. Package = who owns it
today (`feature_*`); "floor" screens live in `feature_order` (`tables_screen.dart`,
`floor_list.dart`, `waiter_sheets.dart`) until a `floor` package is split out.

### 4.0 Shells and the status strip — `apps/madar` (shell + chrome) — **fully**
| Control | Call |
|---|---|
| Which shell | `currentSession()!.role`: `waiter` → Waiter; `kitchen` → KDS board; everything else → Teller shell; Manager = Teller shell + `role ∉ {teller}` widening on Till |
| Which tabs | Floor tab iff `orderProvider.hasFloor`; Queue › Kitchen segment iff `tillShowsKitchen(kitchenRoutingModeProvider)` (§4.7) |
| Home tab | `requireTableForOrders && hasFloor` → Floor; else Sell; teller with no open shift → Till (`appRoute() == openShift`) |
| Name · branch · till | `displayName`, `deviceConfig().branchName`, `listTills()` matched on `deviceConfig().tillId` (default till when null) |
| Outbox pill | `syncStatus()`: `pending` → `◐ n`; `failed > 0` → danger `✕ n stuck` (`chrome.needs_attention`); `!online` → hollow `chrome.offline`; `authPaused` → banner `chrome.auth_paused` + `chrome.auth_paused_action` → reauth sheet (`feature_auth` `reauth_sheet.dart`); `blocked > 0` → included in the Sync screen |
| Clock skew banner | `clockSkewMinutes() >= 5` → `chrome.clock_skew` |
| Name sheet | Language `setLocale`; Settings → `feature_settings`; Sign out → `logout(wipeOutbox: false)`, disabled with `settings.sign_out_shift_open` while `currentShift()?.isOpen` |
| Badges | Bills ② = `listOpenTickets().where(status == 'ready').length`; Queue = that + `listDeliveryOrders('received').length` |
| Realtime | `startRealtime` is already wired in `boot.dart`; tabs watch their tick providers |

### 4.1 Sign in / Device setup / Open shift — `feature_auth`, `feature_shift` — **fully**
| Control | Call |
|---|---|
| Name + PIN | `signIn(LoginRequest(mode: pin, name, pin, branchId: deviceConfig().branchId))` (online, then offline unlock) |
| Manager email login / bind branch | `login(mode: email, ...)`, `listBranches()`, `setDeviceBranch()` |
| KDS station picker | `kdsListStations()`, `setDeviceStation()` |
| Good evening · Till 1 · last close | `displayName`, till name (above), `suggestedOpeningCashMinor()` |
| Opening cash + reason when edited | `openShift(openingCashMinor, openingReason)` — reason required by the core when it deviates (`shift.opening_reason_required`) |
| Switch teller | `logout(wipeOutbox: false)` |
| "Open the shift first" on Sell / Charge | `currentShift() == null || !isOpen` (`waiter.need_shift` exists as a key) |

### 4.2 Sell (counter + round builder) — `feature_order` — **fully**
| Control | Call |
|---|---|
| Category strip / Combos | `listCategories()`, `availableBundles(now)` (Combos tile face `order.configure`) |
| Search | client filter over `listMenuItems()` (`order.search`, `order.empty_search`) |
| Tile quick-add | **rule**: item needs the sheet iff `sizes.length > 1` OR any `listItemModifierGroups(itemId)` group has `isRequired` / `minSelections > 0`; otherwise `cartAdd(itemId, name, basePriceMinor)` (single size → `cartAddConfigured(sizeLabel)` directly). Cache the groups per item after the first read — the call is offline and cheap |
| Long-press tile / tap a line | item sheet (§4.3) |
| Count badge on tile | `cartLines()` summed by `itemId` |
| Header: Takeaway / T5 · Round 3 | round target = `orderProvider.cartTableId` / `activeTicketId`; round number = `max(lines.roundNumber) + 1` of that `TicketView` |
| ⋯ → Park | `holdCart(name, draftId, startedAt)` (never `holdCartOnTable`) |
| Parked chip + sheet | `listDrafts()`; restore `restoreDraft(id)` (skip `lockedByOther`); × `discardDraft(id)`; back out `releaseDraft(id)`; after ring-up `completeDraft(id, orderId)` |
| Bottom bar: Charge 145 | `cartTotals().totalMinor` → Charge (§4.8) |
| Bottom bar: Fire 3 items | round 1 `fireTicket(tableId, guestCount: covers held since seating, bookingId)`; later `addTicketRound(ticketId)`; result `queuedOffline` → `waiter.queued`; the branch-operating pre-check is `lanBranchHasOpenTill()` (warn, don't block — the server is the authority) |
| Takeaway wording | the header may SAY `Takeaway`, but nothing is sent: `CreateOrderRequest` has no `order_type` and the server refuses a table-less till sale when `requireTableForOrders`. So when the flag is on, Sell's Charge is **disabled with a reason** (reuse `tables.settle_first` / `tables.start_order_here`) and Sell exists only as the round builder — design fork Q2 stays "no" until §6.4 lands |

### 4.3 Item sheet — `feature_order` — **fully**
`listItemModifierGroups(itemId)` (required groups first, `isRequired`), sizes from `MenuItemView.sizes`,
`validateItemSelections()` before `cartAddConfigured()`, CTA disabled with the violated group's name
until empty; note → `notes`; "How it's made" → `MenuItemView.recipeSteps` + `computeRecipe()`
collapsed; qty stepper → `qty`. Editing a line = remove + re-add configured (there is no
`cartUpdateLine`; today's sheet does the same).

### 4.4 Round / cart sheet (phone) — `feature_order` — **fully**
`cartLines()`, `cartTotals()`; "On the bill" from the target `TicketView.lines` grouped by
`roundNumber` (`roundFiredAt` via `formatTime(time)`); swipe → `cartRemove(itemId)` + undo toast →
`cartRestoreRemoved()` (`order.removed`, `order.undo`); ⋯ Park / Clear → `holdCart` / `cartClear()`.
"Bill so far" = `ticket.subtotalMinor + cartTotals().subtotalMinor` (label it subtotal — see §4.6).

### 4.5 Floor — `feature_order` (floor files) — **partly**
| Control | Call |
|---|---|
| Plan / List, sections | `floorLayout()`; refresh on open + `floorTickProvider` → `refreshFloor()` |
| Counts row | derived from tables + `listOpenTickets()` joined on `tableId` (a table with a ticket `open/ready/queued` is occupied whatever its stored status — `floor_list.dart` already does this) |
| Arrivals › | `listArrivals()` (refresh `refreshArrivals()`); rows: seat → `seatBooking(bookingId, tableId?)`, no-show → `noShowBooking` |
| Waitlist › | `listTransferQueue()`; fulfil = tap wish → tap table → `fulfillTransfer(id, tableId)`; × `cancelTransfer(id)` |
| Row: state word · covers · guest · time · bill | state from table + ticket; covers `ticket.guestCount`; guest `ticket.customerName`; time `heldSince` / `ticket.openedAt`; bill `ticket.subtotalMinor` |
| FREE sheet: party size chips → Seat | `seatTable(tableId)` — **`seatTable` takes no party size.** Substitute: keep the chips (capacity preselected), hold covers **device-locally** keyed by table until the first round, pass as `fireTicket(guestCount)`. Another device will not see covers until the fire. Say nothing misleading: no "4 covers" on a seated-no-bill row on other devices |
| FREE sheet: Seat a booking here › | `listArrivals().where(needsTable)` → `seatBooking(bookingId, tableId)` |
| SEATED, NO BILL: Take an order | opens Sell bound to the table (`orderProvider` cartTableId) |
| SEATED: Move table | banner → tap target → `swapFloorTables(tableA: this, tableB: target)` (empty target = move, occupied = swap) |
| SEATED: Unseat | `unseatTable(tableId)` |
| SEATED, HAS BILL | → Bill screen (§4.6) |
| NEEDS CLEARING: Cleared | `clearTable(tableId)` |
| NEEDS CLEARING: Reprint last receipt | **hide** — nothing links a dirty table to its last order (`OrderSummaryView` has no table; the settled ticket is no longer listed). Reprint lives on Till › Orders |
| BOOKED: Seat this party / No-show / Walk-in here | `seatBooking(bookingId, tableId)` / `noShowBooking(bookingId)` / `seatTable(tableId)` (server arbitrates) |
| Legacy `held` status | render as *seated* (the design removed the glyph; `heldOrderId != null` still means occupied) |

### 4.6 Bill — `feature_order` (new `bill_screen.dart`; waiter + teller) — **partly**
| Control | Call |
|---|---|
| Header: T5 · Bill T-0412 · covers · waiter · age · guest | `TicketView{tableId→label, ticketRef, guestCount, waiterName, openedAt, customerName}` from `listOpenTickets()` (`getTicket` only for a synced id when online) |
| Rounds with times | `lines` grouped by `roundNumber`; `roundFiredAt` |
| ✓ served / ◔ cooking per round | **only bill-level**: `status == 'ready'` (every line bumped) vs `open`. No per-round readiness is exposed (the KDS feed has rounds but no ticket id to join on). Render the ✓ on the header when ready; rounds show times only |
| Struck voided line (who / why) | `TicketLineView.voided` (struck). Actor/reason are not on the view — no tap detail |
| Swipe → Void line | **hide** — no route on the wire (`void_open_ticket` is whole-ticket only). §6.2 |
| Subtotal | `subtotalMinor` |
| Service 12 % · VAT (included) · Total | **hide** — `TicketView` carries only the subtotal; the server's `TicketBill{subtotal, discount_amount, service_charge_amount, tax_amount, total, tax_rate, tax_inclusive}` exists on `OpenTicketView.bill` but is **not projected**. Show *Subtotal* and, when `serviceChargeRate > 0 || !taxInclusive`, one quiet line "service and tax are added when charged" (needs a key — until then reuse `order.service_charge` / `order.tax` with no figure). Top ask, §6.9 |
| Member row | **partly** — `loyaltyLookup` works; attaching ahead of Charge is a till-local note passed to `settleTicket(loyaltyCustomerId)` (§7.8 of the design already accepts this) |
| ⋯ Move table | `swapFloorTables` (as §4.5); hidden for a table-less bill |
| ⋯ Guest name · Covers | **hide** — no update route for an open ticket. Both are set at the FIRST fire only (`fireTicket(customerName, guestCount, notes)`): expose them in the round-1 sheet's ⋯ instead |
| ⋯ Void bill | `voidTicket(ticketId, reason)` — reasons `void.reason_mistake/customer/quality/other`, note (`void.note`) |
| + Add round | Sell bound to the ticket (`activeTicketId`) → `addTicketRound` |
| Charge (teller only) | §4.8 with a bill caller; after acking, the core mirrors the table `dirty` |
| Queued rows | `queuedOffline` → `◐` (`waiter.queued`) |

### 4.7 Queue — `feature_incoming` — **partly**
**Bills segment — fully.** `listOpenTickets()` sorted ready-first then oldest; row → Bill; row
*Charge* → §4.8 directly. Table-less rows only when `!hasFloor`.

**Online segment — partly.** `listDeliveryOrders('received,confirmed,preparing,ready,out_for_delivery')`
(online-only; offline shows `chrome.offline` + last list). Watch `deliveryTickProvider`.
| Control | Call |
|---|---|
| NEW card: fields | `customerName`, `customerPhone`, `address`, `deliveryNotes`, `itemCount`, `deliveryFeeMinor`, `totalMinor`, `paymentHint`, `channel`, age from `createdAt` |
| READY IN chips (multiples of 5 on the base) | base = `deliverySettings().prepTimeMinutes`; chip *t* → `deliverySetPrepTime(id, extraMinutes: t - base)` (only `t >= base`; chips below the base are not offered) |
| Accept | `deliveryAdvanceStatus(id, 'received')` → `confirmed`, then the prep-time call |
| Decline (reason) | `deliveryCancel(id, reason, restoreInventory: true)` — same call as Cancel; the returned `status` (`rejected` or `cancelled`) is what the card shows |
| ACCEPTED card | the wire has a `confirmed` step the design collapses; primary = `delivery.action.preparing` → `deliveryAdvanceStatus(id, 'confirmed')` (one step, per the design's own "always the next step" rule) |
| PREPARING → Mark ready | `deliveryAdvanceStatus(id, 'preparing')` |
| READY → Out for delivery / Picked up | `deliveryAdvanceStatus(id, 'ready')` (label by `channel == 'pickup'`) |
| OUT → Charge | `deliveryFinalize(id, paymentMethodId)` — needs `currentShift()`; §4.8 online caller |
| ⋯ Cancel + restock toggle | `deliveryCancel(id, reason, restoreInventory)` (`delivery.restore_inventory`) |
| ready at 19:45 | `promisedReadyAt` → "Ready by 19:50"; once the kitchen calls it, `readyAt` → "Ready 19:29". Never both on one card |
| 409 flips the card | catch `MadarError.server(status: 409)` → re-read `deliveryOrderDetail(id)`, one-line notice |
| Accepting: in-mall ● outside ○ | `deliverySettings()` → `deliverySetAccepting(channel, mode)`; chips only for `*Enabled` channels; `pickup`/`umbrella` cannot be shown or toggled (not in the view) |
| No channels enabled | hide the segment |

**Kitchen segment — fully.** Shown only when `tillShowsKitchen(kitchenRoutingModeProvider)` —
modes `till` and `both`. It mounts `KdsBoardBody(stationId: null)`, the cook's own board minus
its header, on the same `kdsProvider` family, so the counter and the kitchen cannot disagree
about a line. `kds` hides it (bumping here would clear a line off a screen a cook is working
from), `off` hides it (nothing is routed anywhere), and so does an unknown mode — a device that
has never reached the server does not get to guess. A mode that changes under a teller standing
on the segment falls back to Bills.

### 4.8 Charge (tender) + Done card — `feature_checkout` — counter **fully**, bill **partly**, online **partly**
| Control | Counter cart | Bill | Online order |
|---|---|---|---|
| Header | `Charge · Takeaway` | `Charge · T5` | `Charge · #D-118` |
| TOTAL hero | `cartTotals().totalMinor` | **`subtotalMinor`, labelled Subtotal** (no total on the view; see §4.6) | `totalMinor` (server-frozen) |
| Subtotal · Service · VAT lines | `cartTotals()` — wording: `taxInclusive` → "VAT n % included x" under the total; else "VAT n % +x" above (`order.tax`, `order.service_charge`); service line only when `serviceChargeMinor > 0` | hidden (not on the view) | `subtotalMinor`, `discountMinor`, `deliveryFeeMinor` (`delivery.*` keys); no tax line on the view |
| Discount › (only if any active) | `cartSetDiscount(id)` / `cartClearDiscount()` → re-read `cartTotals()` | `settleTicket(discountId, discountType: dtype, discountValue: value)` — no live preview; the server applies it | not available on `deliveryFinalize` — hide |
| Member › / redeem a line | `classifyLoyaltyInput`, `loyaltyLookup` [online → offline says `loyalty.queued_hint`/`err.offline_no_setup`-style sentence]; `CheckoutInput.loyaltyCustomerId`, `loyaltyRedemptions[itemIndex, units]` | `settleTicket(loyaltyCustomerId, loyaltyRedemptions[ticketLineId])` (`startSettle(ticketLines:)` already builds `RedeemableLine`s) | hide (not on `deliveryFinalize`) |
| Add tip › | `CheckoutInput.tipMinor / tipPaymentMethodId` | `settleTicket(tipMinor, tipPaymentMethodId)` | hide |
| Method grid (≥ 2) / button names the one method | `listPaymentMethods()` | same | same (method only) |
| Split | `CheckoutInput.splits` | `settleTicket(splits:)` — same tender screen, same legs | hide (one method only) |
| Cash tendered: Exact / presets / keypad / change | `amountTenderedMinor`; change from `ReceiptView.changeMinor` | `settleTicket(amountTenderedMinor)`; change computed locally against the subtotal — label it honestly ("against subtotal") or omit change for bills where `serviceChargeRate > 0 || !taxInclusive` | hide |
| Charge button | `checkout(input)` → `ReceiptView` | `settleTicket(...)` → order id or `null` (queued) | `deliveryFinalize` → `{orderId, orderRef, warnings}` |
| "Open the shift first" | `currentShift()?.isOpen != true` → disabled bar linking to Till | same | same |

**Done card**
| Control | Call |
|---|---|
| ✓ Sale #1042 · amount · method · change | `ReceiptView{orderNumber, totalMinor, paymentLabel, changeMinor}`; for a bill, the acked order id → `orderReceiptView(orderId)`; for online, `orderReceiptView(finalize.orderId)` |
| ◐ Queued · #local | `receipt.queuedOffline` → `receipt.localOrderId` (`order.queued_hint`); bill settle returned `null` → queued (`waiter.queued`) |
| Printed ✓ / Not printed — no printer › | `renderReceipt(...)` + `PrinterService` (transport from `deviceConfig()`); `cashDrawerKick(brand)` when `isCash`; no binding → `receipt.no_printer` linking to printer settings |
| Add points | `loyaltyAward(orderId / orderKey: localOrderId, orderCreatedAt: createdAt, customerId)` → show `headline`/`detail` (queued / already collected / added) — works offline |
| Reprint | `renderReceipt` again (or `renderOrderReceipt(orderId)`) |
| T5: Cleared / Not yet | `clearTable(tableId)`; dismiss = not yet (table stays `dirty`) |

### 4.9 Till — `feature_shift` — **partly**
| Control | Call |
|---|---|
| Till 1 · Sara · since 15:02 | till name, `currentShift(){tellerName, openedAt}` |
| SALES n · total | `listShiftOrders()` → `shiftStats(orders)` |
| CASH IN TILL | `shiftReport().expectedCashMinor` (`fromServer == false` → say it is opening + queued cash only: `shift.system_cash_explain`) |
| ▸ Cash by method, tips | `shiftReport().paymentLines`; **tips are not on the report** — drop the word |
| Orders this shift › | §4.10 |
| Cash in / out › (count) | `listCashMovements()` |
| Print X report › (INTERIM) | `shiftReport()` + `renderShiftReport(report, orders: listShiftOrders())` (`shift.interim`) |
| Past shifts › | `listShifts()` → row → `shiftReportFor(id)`, `listOrdersForShift(id)`, reprint Z via `renderShiftReport` |
| Close shift | §4.9b |
| **Manager: DRAWERS** | `listShifts().where(isOpen)` + closed ones — every teller's, with `tellerName`, `openedAt`, `status`. Row → read-only drawer page (`shiftReportFor`, `listOrdersForShift`). No till name on the view (label by teller) |
| **Manager: Force-close (reason)** | **hide** — not on the bridge (wire has `force_close_shift{reason}`; §6.7) |

**4.9a Cash in / out — partly**
| Control | Call |
|---|---|
| Kinds chips | only **Pay out** (`amountMinor < 0`) and **Pay in** (`> 0`) map to `recordCashMovement(amountMinor, note)`. **Safe drop: hide** (the wire has `kind: pay_in|pay_out|safe_drop|correction` — the bridge sends none; §6.8) |
| Amount autofocused · Note (required) | `MadarAmountField`; `note` required by the core |
| TODAY list | `listCashMovements()` (server + queued merged) |
| Correct › | **hide** — no `corrects_id` on the bridge; do not fake it with an opposite movement (the design forbids exactly that) |

**4.9b Close shift — partly**
| Control | Call |
|---|---|
| Expected cash + breakdown | `shiftReport(){expectedCashMinor, openingCashMinor, cashInMinor, cashOutMinor, paymentLines(isCash)}`; the "− refunds" term is dropped (no refunds anywhere) |
| Counted (autofocused) · Short by / Over by | local diff vs `expectedCashMinor`; note required when ≠ 0 (`shift.drawer_short/over`, `shift.cash_note`) |
| Suggested safe drop | **hide** — no standard float exists |
| ▸ Z report preview | `ShiftReportSheet` over `shiftReport()` |
| Close shift (danger) | `closeShift(closingCashMinor, cashNote)` → then `renderShiftReport` for the Z; `logout` is separate |

### 4.10 Orders (history) and the Sale — `feature_history` — **partly**
| Control | Call |
|---|---|
| One list, this shift | `listShiftOrders()` (queued rows `queued == true` → ◐) |
| Filters All · Takeaway · Dine-in · Online | `orderType` — the wire distinguishes `dine_in` and `delivery`; a "takeaway" bucket has no value to filter on → chips are **All · Dine-in · Online** (`history.type.*` keys exist for exactly these) |
| Refunded chip / REFUNDED rows | **hide** (no refunds) |
| Stats line | `shiftStats(orders)` + `shiftReport().paymentLines` |
| ⌕ number, phone, amount across shifts | `searchOrders(status, tellerName, paymentMethod, from, to, page)` [online] has **no free-text parameter**. Substitute: the field filters the loaded rows client-side by `orderNumber` / `orderRef` / `customerName`; date-range + teller + method are the server filters (`search.date_*`, `search.teller_hint`); phone and amount are dropped from the placeholder |
| Show more | `OrderSearchPage.hasMore` → `page + 1` |
| Sale header + lines + totals | `orderDetail(orderId)` (cached once seen online) |
| Member Omar · +19 pts | **hide** — not on `OrderDetailView` |
| Reprint | `renderOrderReceipt(orderId, ...)` |
| Add points (24 h) | `loyaltyAwardWindowOpen(createdAt, now)` gates; `loyaltyAward(orderId, orderCreatedAt)` |
| Refund | **hide** (§6.1). Void carries the whole correction load; the copy must not promise a refund |
| Void… (⋯) | `voidOrder(orderId, reason, note, restoreInventory)` — the till cannot pre-check "shift closed"; show the server's refusal sentence. The design's "Paid 3h ago — refund instead" wording is dropped |

**Refund sheet — not-yet.** Do not build. No route, no op, no call.

### 4.11 Loyalty moments — `feature_checkout` (scan + award sheets exist) — **partly**
| Moment | Call |
|---|---|
| Attach (camera / wedge / phone) | `classifyLoyaltyInput(raw)` per keystroke; `loyaltyLookup(token:)` or `(phone:)` [online] — offline: the sentence, not a spinner (`loyalty.queued_hint`) |
| Member card | `LoyaltyScanView{member, rewards, recent, anyItem, anyItemCost}`; `balanceLabel` swaps points/orders |
| Use a reward on a line | `CheckoutRedemption` (counter: `itemIndex`; bill: `ticketLineId`) |
| Not a member? Show join code | **hide** — no join URL/QR on the bridge |
| Earn (Add points) | `loyaltyAward` (§4.8) |
| Programme off → nothing renders | **cannot be known.** Decision: render the Member row and Add points; when `loyaltyLookup`/`loyaltyAward` return `MadarError.server` for a disabled programme, show `detail` and remember "off" for the session. Ask §6.10 makes it absent for real |

### 4.12 KDS — `feature_kds` — **fully**
`kdsList(stationId: deviceConfig().stationId)` on `kitchenTickProvider`; card header
`tableLabel` (largest) / `kitchenRef` · `roundNumber` · age from `createdAt`; line tap
`kdsBump(itemId)`, bumped line tap `kdsUnbump(itemId)`; **Bump all** = `kdsBump` for every
`!bumped` line in order (outbox-first, so it is safe; a failure surfaces as `MadarError` on the
card instead of being swallowed); a `ready` card leaves the board on the next read.

### 4.13 Sync — `feature_settings` (`sync_screen.dart`) — **partly**
| Control | Call |
|---|---|
| Online · live updates ✓ | `syncStatus().online`, `isRealtimeSubscribed()` + `realtimeConnectedProvider`, `lanPeerCount()` |
| Last pull 19:41 | **hide** — no timestamp on the bridge; the row times (`eventAt`) stand in |
| Sync now (n) | `syncNow()` (also refills the catalogue: call `refreshCatalog()` after it) |
| WAITING rows | `listOutbox().where(status == 'pending')` — `opType` → label (`sync.op_*` keys exist for open_shift / create_order / close_shift; others need keys), `eventAt` via `formatTime`, `attempts` |
| STUCK rows + the server's sentence | `status == 'dead'`, `lastError` |
| Retry / Discard per row | Discard → `discardOutboxItem(id)`; **Retry is all-or-nothing** → one *Retry all* button → `retryOutbox()` |
| BLOCKED n | `syncStatus().blocked` → action `recoverOrphanedOrders()` (returns the count moved) |

### 4.14 Settings — `feature_settings` — **fully**
Language `setLocale`; Theme Light/Dark from `darkModeProvider` (Auto is a Dart-side addition the
settings owner may make — `settings.theme_system` exists); Printer › `setDevicePrinterTransport /
setDevicePrinter / setDevicePrinterBt / setDevicePrinterPaper` (+ test print via `renderReceipt`);
Till › `listTills()` + `setDeviceTill`; Device › `deviceCode()/setDeviceCode`, `startReconfigure()`;
Diagnostics › `coreVersion()`, `baseUrl()`, `environment()`, `clockSkewMinutes()`, `lanActive()`,
`lanPeerCount()`, `setDeviceLanHub`, `recentLogs()/clearLogs()`, the "No floor layout" hint from
`!hasFloor`; Legal › static keys `settings.legal_*`; Sign out → `logout` gated by the open shift.

### 4.15 Waiter shell — `feature_order` (floor + bill) + `apps/madar` — **fully**
| Screen | Call |
|---|---|
| Floor | §4.5 minus Charge |
| Bills: MINE / OTHERS | `listOpenTickets()`; MINE = `waiterName == displayName` (string match — the view has no `openedBy` id); rows show `status == 'ready'` as ✓; badge = ready count; watch `ticketTickProvider` |
| + New bill (no floor) | Sell mounted table-less → `fireTicket(customerName: name)` |
| Me: "2 rounds waiting" | `listOutbox().where(opType ∈ {open_ticket, ticket_add_round, void_ticket})` |
| Me: Online · live | `syncStatus().online`, `isRealtimeSubscribed()` |
| Me: Language / Sign out | `setLocale` / `logout(wipeOutbox: false)` |

---

## 5. The design's §7 list, re-checked against today's bridge

| # | Design said | Now |
|---|---|---|
| 1 | Refunds — no route, no op, no call | **Route arrived, bridge did not.** The API client crate now has `refunds_api::{create_refund, get_refund, list_order_refunds, list_shift_refunds}` with `CreateRefundRequest{order_id, amount, method, reason ∈ customer_request/wrong_order/quality_issue/overcharged/late_or_undelivered/goodwill/other, lines[{order_item_id, quantity, amount}], shift_id, client_ref, note}`. `madar-core` never calls it; `bridge.dart` has nothing. **Still a gap.** |
| 2 | Void a single line | **Still a gap** — `open_tickets_api` has no line route; `void_open_ticket` is whole-ticket. |
| 3 | Split tender on a bill | **Wire accepts it, bridge does not** — `SettleOpenTicketRequest.payment_splits` exists; `settleTicket` has no `splits` parameter. Counter `checkout` does carry splits. **Gap on bills.** |
| 4 | Takeaway from a require-table shop | **Still a gap** — `CreateOrderRequest` has no `order_type`; the till cannot say "takeaway". |
| 5 | Bump all | **Still per line** — loop `kdsBump`. Acceptable (outbox-first). |
| 6 | Ready-at on an online order | **Still a gap in the view** — the wire `DeliveryOrder` has `confirmed_at`, `extra_prep_minutes`, `ready_at` (actual), and settings have `prep_time_minutes`, but `DeliveryOrderView` exposes none of the inputs. Small core projection. |
| 7 | Receipt content (table, member, points) | **Still a gap** — `receipt.rs` renders no table label / member on the sale receipt (only on the kitchen chit). |
| 8 | Loyalty on the bill before Charge | **Unchanged** — till-local until `settleTicket(loyaltyCustomerId)`. |

---

## 6. Gaps the design did NOT list, and the asks — ranked for the master

Each is "server has it / core lacks it" unless noted. Builders do not wait on these; the
substitutes above are what ships in the morning.

1. ~~**Refunds**~~ — DONE, end to end. `refundOrder` (outbox-first, `client_ref` idempotent, the
   issuing shift travelling with it), `listOrderRefunds` on the sale (cached, with refunds still
   in the outbox overlaid so a teller offline cannot hand the same money over twice),
   `listShiftRefunds`, and the Z-report's own returns lines on screen AND on paper
   (`refundsIssuedMinor` / `refundsIssuedCashMinor` / `cashInRefundedSalesMinor`).
   `compute_system_cash` subtracts cash refunds server-side.
2. ~~**Line void**~~ — DONE; see the entry below.
3. ~~**Kitchen routing mode**~~ — DONE. `kitchen_routing_mode()` reads `get_routing_mode →
   effective` write-through cached in kv and refreshed on every `sync_now`;
   `set_kitchen_routing_mode(mode)` writes it (online-only — a manager changing how the shop runs
   must fail loudly, not queue). `off` needed no suppression: readiness is drawn from ticket
   status, and in `off` no kitchen ticket is ever raised, so no ticket ever reads ready.
4. ~~**`order_type: takeaway`**~~ — DONE; see the entry below.
5. ~~**Splits on `settleTicket`**~~ — DONE. `settleTicket(splits:)` resolves each leg's method id
   to the raw name, dropping a leg whose method no longer exists rather than 400-ing the settle.
   `canSplit` is `!isOnline && methods >= 2`.
6. ~~**Delivery view: `confirmedAt`, `extraPrepMinutes`, `readyAt`**~~ — DONE, plus
   `preparingAt` and a computed `promisedReadyAt` (acceptance + branch base + the teller's
   extra, clamped forward, dropped once `readyAt` exists). The base prep time is cached in kv
   when the settings are read, so the promise survives going offline.
7. ~~**Force-close**~~ — DONE. `forceCloseShift(shiftId, reason)`, online-only with a required
   reason.
8. ~~**Cash movement `kind` + `corrects_id`**~~ — DONE. `recordCashMovement(kind:, corrects:)`.
9. ~~**`TicketView` totals**~~ — DONE. `TicketView.bill` (`TicketBillView`) carries the server's
   own figures, and the bill's Charge collects the TOTAL rather than the subtotal.

Still open, both SERVER work before the core can be asked for anything:

- ~~**Line void**~~ — DONE. `POST /open-tickets/{id}/items/{item_id}/void` + a `VoidTicketLine`
  replay op; the kitchen line now records which bill line it came from, so voiding a line takes
  that plate off the board. `voidTicketLine` on the bridge, and the core overlays a queued void
  on the ticket view — re-pricing the bill through the shared tax engine — so the waiter sees
  the plate come off and the cashier does not collect for it while the op is still in the outbox.
- ~~**`order_type: takeaway`**~~ — DONE, and it needs no request field: the server DERIVES it
  (a bill settled from a waiter's ticket is `dine_in`, anything rung straight through the till
  is `takeaway`), so a till cannot claim a type to dodge the service charge. The core stopped
  labelling queued counter sales `dine_in`, and Orders has Dine-in and Takeaway as separate
  chips rather than one that meant "not delivery".
   **Recommend doing this first** — it is the most visible dishonesty in the shipping app too.
10. ~~**Loyalty programme flag**~~ — DONE. A teller holds `loyalty:read`, so the till reads
    `get_loyalty_settings` at the branch scope directly; no login-payload change was needed.
11. **Open-ticket edit** — guest name / covers / notes after the first fire. Server work.
12. **Search by number / phone / amount** — `list_orders` params. Server work.
13. **Delivery settings: `pickup` / `umbrella`** in `DeliverySettingsView` + `deliverySetAccepting`
    accepting those channels. Projection.
14. **i18n keys** — the new screens need new keys in `i18n.rs` (Bill, Queue, Till, Charge, Sync
    wording per §4). Builders list exact keys in `needsFromOthers`; the master adds them in one pass.
    Until then, screens use the nearest existing key from Appendix A rather than a literal.
15. **Realtime sync timestamp** ("last pull") — a `lastSyncedAt` on `SyncStatusView`. Cosmetic.

Decisions taken here so nobody has to stop and ask (the owner said decide):
- Kitchen segment is **hidden**, not shown ungated.
- Readiness is **bill-level only** (header ✓ when `status == 'ready'`); rounds show times.
- Party-size chips **stay**; covers are held device-locally until the first fire.
- Till chips are **Pay out · Pay in**; Safe drop and Correct are absent.
- Refund is **absent everywhere**; Void is the only correction and says so plainly.
- Split is offered at the **counter only**.
- A bill's Charge hero is labelled **Subtotal** until #9 lands; change is shown against it only
  when `serviceChargeRate == 0 && taxInclusive` (then subtotal == total).
- Online Charge is **method-only** (that is all `deliveryFinalize` takes).
- Loyalty controls **render**; a server refusal for a disabled programme is shown once and then
  the controls hide for the session.
- Sync has **Retry all**, per-row Discard, and a BLOCKED action.
- Order search is **date / teller / method on the server, number / customer client-side**.

---

## Appendix A — every i18n key the core has today (en + ar), by namespace

Use these verbatim with `bridge.tr(key: 'ns.key')`. Anything not here is a new key for the master.

- **brand**: headline tagline
- **cash**: amount empty history in net note out record title total_in total_out
- **chrome**: auth_paused auth_paused_action clock_skew more needs_attention offline offline_banner online orders queued reauth_as reauth_body reauth_switch reauth_title sync_data sync_done sync_failed syncing sync_resumed view
- **common**: cancel done void
- **delivery**: accepting action.confirmed action.delivered action.out_for_delivery action.preparing action.ready active add_prep all cancel cancel_reason empty finalize finalized finalize_pay floor in_mall items mode_auto mode_closed mode_open outside pickup prep_time queue reject restore_inventory status.cancelled status.confirmed status.delivered status.out_for_delivery status.preparing status.ready status.received status.rejected title umbrella unit
- **drafts**: current empty hold title
- **err**: generic network not_allowed offline_no_setup
- **history**: col.amount col.teller col.time completed current_shift empty failed no_match order queued search show_more stat.orders synced title type.all type.delivery type.dine_in voided
- **home**: currency offline online role session signed_in sign_out teller
- **incoming**: title
- **kds**: all_clear reconnecting title waiter
- **kitchen**: chit_heading chit_note chit_table
- **login**: branch name pin_hint reconfigure sign_in subtitle welcome_back
- **loyalty**: add_points add_points_title already_collected customer earns left look_up no_points nothing_claimable not_identified phone_hint phone_label phone_placeholder points_added points_queued queued_hint remove rewards_ready scan_card scan_card_instead scan_hint scanner_ready scan_title use_phone
- **nav**: history incoming section.money section.orders section.system
- **notif**: booking_arriving new_booking new_delivery new_kitchen new_round new_ticket ready
- **order**: addon_coffee_type addon_extra addon_milk_type add_to_cart all bundle_includes bundle_save cart cart_empty cash_received change change_due checkout clear close_shift combos coming_soon configure customer customer_hint discount done empty empty_desc empty_search exact items max_reached new_order no_discount notes notes_hint optionals order_placed payment payment_method place_order queued_hint recipe removed rename_hint rename_title required save_component search search_addons select_prefix sent_hint service_charge short_by show_all_addons show_assigned_addons size split_payment split_remaining steps subtotal sync_menu table tax tender tip title total undo update_item view_cart view_order waiter
- **printing**: chit chit_sent failed no_printer
- **receipt**: address cash customer delivery delivery_fee delivery_ref no_printer notes order payment payment_hint phone print printed print_failed printing ref reprint served_by settled teller thank_you title voided zone
- **reservations**: moved seat seated status_dirty status_free status_held status_seated title
- **search**: date_24h date_30d date_7d exported load_more teller_hint title
- **settings**: account appearance clear device device_code_caption device_code_hint diagnostics flip_screen lan lan_active lan_caption language lan_hub_hint lan_offline lan_peers legal legal_copied legal_privacy legal_terms orientation pending printer printer_bluetooth printer_bt_connected printer_bt_disconnected printer_bt_none printer_bt_permission printer_bt_scan printer_epson printer_hint printer_lan printer_paper_58 printer_paper_80 printer_star printer_transport realtime realtime_off realtime_on recent_warnings reconfigure reconfigure_shift_open server sign_out sign_out_shift_open tablet_threshold theme_dark theme_light theme_system till till_default title version
- **setup**: cancel choose_branch choose_branch_desc choose_station choose_station_desc continue desc email no_stations password station_default title
- **shift**: business_date by_method cash_in cash_moves cash_note cash_out cash_recon close_title closing_desc counted_cash difference drawer_matches drawer_ops drawer_over drawer_short end_of_report expected_cash interim not_closed open_button opened_at opening_cash opening_desc opening_hint opening_mismatch opening_reason_hint opening_reason_label opening_reason_required open_title orders payments printed_at print_report report report_title signed_in_as suggested_from_close summary switch_teller system_cash system_cash_explain teller total_collected transactions welcome
- **shifts**: closed declared discrepancy empty no_orders opening open_now orders title
- **sync**: attempts discard empty failed op_close_shift op_create_order op_open_shift pending push pushing queued retry sending title
- **tables**: add_round arrivals arrivals_empty assign bill_pending booking_no_show booking_seated cancel_wish clear clear_ask clear_ask_generic clear_ask_hint cleared clear_later clear_now clear_table dirty_hint due empty_desc empty_title empty_waitlist free freed free_it free_it_warning fulfill guests held_res late locked make_available move moved needs_clearing no_section no_show no_table pick queue queued reserved reserved_for resume round seat_booking seated seat_held seats settle settle_first start_order_here status swap swap_pick taken title view_list view_plan waitlist walk_in_anyway wish_any
- **tender**: method total
- **ticket**: status.open status.queued status.ready status.settled status.voided
- **void**: action cancel confirm note reason reason_customer reason_mistake reason_other reason_quality restock title
- **waiter**: add_round covers customer_optional fire fired items need_shift new_order new_round no_tickets on_ticket queued settle settled table ticket tickets title void_reason void_title

## Appendix B — where each call is already used (so builders read a neighbour first)

`feature_order`: cart*, fireTicket, addTicketRound, voidTicket, settleTicket, floorLayout,
refreshFloor, seatTable, unseatTable, clearTable, mirrorTableStatus, swapFloorTables,
listArrivals, seatBooking, noShowBooking, listTransferQueue, createTransfer, fulfillTransfer,
cancelTransfer, listDrafts, holdCart, holdCartOnTable, restoreDraft, discardDraft, completeDraft,
assignDraftTable, listCategories, listMenuItems, availableBundles, listItemAddons,
listItemModifierGroups, validateItemSelections, computeRecipe, categoryStyle, refreshCatalog,
refreshShift, shiftStats, clockSkewMinutes, renderKitchenChit, cashDrawerKick.
`feature_checkout`: checkout, listPaymentMethods, listDiscounts, cartSetDiscount, cartClearDiscount,
cartDiscountId, cartTotals, classifyLoyaltyInput, loyaltyLookup, loyaltyAward,
loyaltyAwardWindowOpen, renderReceipt, orgLogoLocalPath.
`feature_incoming`: listOpenTickets, settleTicket, listDeliveryOrders, deliveryAdvanceStatus,
deliveryCancel, deliveryFinalize, deliverySetAccepting, deliverySetPrepTime, deliverySettings,
orderReceiptView.
`feature_shift`: currentShift, openShift, closeShift, suggestedOpeningCashMinor, recordCashMovement,
listCashMovements, shiftReport, shiftReportFor, listShifts, listShiftOrders, listOrdersForShift,
renderShiftReport, renderOrderReceipt, syncStatus, lanStop.
`feature_history`: listShiftOrders, orderDetail, searchOrders, voidOrder, shiftReport,
loyaltyAwardWindowOpen.
`feature_kds`: kdsList, kdsBump, kdsUnbump, kdsListStations.
`feature_settings`: listOutbox, syncNow, retryOutbox, discardOutboxItem, recentLogs, listTills,
setDevice*, deviceCode, setDeviceCode, lanActive, lanPeerCount, isRealtimeSubscribed, baseUrl.
`feature_auth`: login, signIn, listBranches, setDeviceBranch, startReconfigure, setDeviceStation,
kdsListStations.
`apps/madar`: appRoute, currentSession, restoreSessionCached, startRealtime, unsubscribeRealtime,
lanStart, lanStop, pendingOutboxCount, setLocale, isRtl, openShift, logout, cartLines, listMenuItems.
**Never called yet** (all real, all available): getTicket, hasPermission, listAddonCatalog,
deliveryOrderDetail, deliverySetStatus, recoverOrphanedOrders, lanBranchHasOpenTill,
branchTimezone, orgLogoUrl, printToDevice, sendToPrinter, unlockOffline, clearDevice, clearLogs,
environment, version, releaseDraft, restoreSession, isAuthenticated, dbPath.
