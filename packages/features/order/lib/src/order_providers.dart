import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Sentinel for [OrderState.copyWith]'s nullable fields, so an explicit
/// `null` can be distinguished from "leave unchanged".
const Object _unset = Object();

const CartTotals _emptyTotals = CartTotals(
  itemCount: 0,
  subtotalMinor: 0,
  discountMinor: 0,
  taxMinor: 0,
  totalMinor: 0,
);

/// Immutable snapshot of the natives' AppModel slice the order surface
/// consumes: catalog, cart (+ start timestamp), drafts, open tickets,
/// connectivity chrome, shift stats, and the toast/error slots. All business
/// logic stays in the core; [OrderNotifier] only sequences bridge calls.
@immutable
class OrderState {
  const OrderState({
    required this.isWaiter,
    required this.currency,
    this.shift,
    this.categories = const [],
    this.menuItems = const [],
    this.bundles = const [],
    this.isLoadingCatalog = true,
    this.isSyncingData = false,
    this.cartLines = const [],
    this.cartTotals = _emptyTotals,
    this.cartStartedAtIso,
    this.drafts = const [],
    this.openTickets = const [],
    this.activeTicketId,
    this.isOnline = true,
    this.pendingCount = 0,
    this.syncFailed = 0,
    this.syncAuthPaused = false,
    this.clockSkewMinutes = 0,
    this.error,
    this.isBusy = false,
    this.toast,
    this.shiftSalesMinor = 0,
    this.shiftOrderCount = 0,
  });

  // ── session ──────────────────────────────────────────────────────────────
  /// Waiter devices fire tickets instead of tendering (the natives'
  /// isWaiterDevice — a session-role check, re-derived on [OrderNotifier.init]).
  final bool isWaiter;
  final String currency;
  final ShiftView? shift;

  // ── catalog ──────────────────────────────────────────────────────────────
  final List<CategoryView> categories;
  final List<MenuItemView> menuItems;
  final List<BundleView> bundles;
  final bool isLoadingCatalog;
  final bool isSyncingData;

  // ── cart ─────────────────────────────────────────────────────────────────
  final List<CartLineView> cartLines;
  final CartTotals cartTotals;

  /// RFC3339 stamp of the cart's empty→non-empty transition — the live-cart
  /// chip's sort key + "HH:MM" label in the held-orders strip. A restored
  /// draft adopts its own createdAt instead.
  final String? cartStartedAtIso;

  // ── drafts + waiter tickets ──────────────────────────────────────────────
  final List<DraftView> drafts;
  final List<TicketView> openTickets;

  /// The waiter's selected round target (null = firing a NEW ticket).
  final String? activeTicketId;

  TicketView? get activeTicket => isWaiter
      ? openTickets.where((t) => t.id == activeTicketId).firstOrNull
      : null;

  // ── chrome ───────────────────────────────────────────────────────────────
  final bool isOnline;
  final int pendingCount;
  final int syncFailed;
  final bool syncAuthPaused;
  final int clockSkewMinutes;
  final String? error;
  final bool isBusy;

  // ── toast ────────────────────────────────────────────────────────────────
  final ToastData? toast;

  // ── shift stats (top-bar pill) ───────────────────────────────────────────
  /// Live shift totals — "EGP X · N orders", voided excluded, summed in the
  /// core (the natives' loadHistory → core.shiftStats).
  final int shiftSalesMinor;
  final int shiftOrderCount;

  // ── derived lookups ──────────────────────────────────────────────────────
  String categoryName(String? id) =>
      categories.where((c) => c.id == id).firstOrNull?.name ?? '';

  MenuItemView? menuItemById(String itemId) =>
      menuItems.where((i) => i.id == itemId).firstOrNull;

  /// Total quantity of an item already in the cart, summed across its config
  /// variants — drives the catalog card's in-cart badge.
  int cartQtyForItem(String itemId) => cartLines
      .where((l) => l.itemId == itemId)
      .fold(0, (sum, l) => sum + l.qty);

  OrderState copyWith({
    bool? isWaiter,
    String? currency,
    Object? shift = _unset,
    List<CategoryView>? categories,
    List<MenuItemView>? menuItems,
    List<BundleView>? bundles,
    bool? isLoadingCatalog,
    bool? isSyncingData,
    List<CartLineView>? cartLines,
    CartTotals? cartTotals,
    Object? cartStartedAtIso = _unset,
    List<DraftView>? drafts,
    List<TicketView>? openTickets,
    Object? activeTicketId = _unset,
    bool? isOnline,
    int? pendingCount,
    int? syncFailed,
    bool? syncAuthPaused,
    int? clockSkewMinutes,
    Object? error = _unset,
    bool? isBusy,
    Object? toast = _unset,
    int? shiftSalesMinor,
    int? shiftOrderCount,
  }) => OrderState(
    isWaiter: isWaiter ?? this.isWaiter,
    currency: currency ?? this.currency,
    shift: identical(shift, _unset) ? this.shift : shift as ShiftView?,
    categories: categories ?? this.categories,
    menuItems: menuItems ?? this.menuItems,
    bundles: bundles ?? this.bundles,
    isLoadingCatalog: isLoadingCatalog ?? this.isLoadingCatalog,
    isSyncingData: isSyncingData ?? this.isSyncingData,
    cartLines: cartLines ?? this.cartLines,
    cartTotals: cartTotals ?? this.cartTotals,
    cartStartedAtIso: identical(cartStartedAtIso, _unset)
        ? this.cartStartedAtIso
        : cartStartedAtIso as String?,
    drafts: drafts ?? this.drafts,
    openTickets: openTickets ?? this.openTickets,
    activeTicketId: identical(activeTicketId, _unset)
        ? this.activeTicketId
        : activeTicketId as String?,
    isOnline: isOnline ?? this.isOnline,
    pendingCount: pendingCount ?? this.pendingCount,
    syncFailed: syncFailed ?? this.syncFailed,
    syncAuthPaused: syncAuthPaused ?? this.syncAuthPaused,
    clockSkewMinutes: clockSkewMinutes ?? this.clockSkewMinutes,
    error: identical(error, _unset) ? this.error : error as String?,
    isBusy: isBusy ?? this.isBusy,
    toast: identical(toast, _unset) ? this.toast : toast as ToastData?,
    shiftSalesMinor: shiftSalesMinor ?? this.shiftSalesMinor,
    shiftOrderCount: shiftOrderCount ?? this.shiftOrderCount,
  );
}

/// The order surface's notifier — the old OrderController re-homed on the
/// provider spine. Screens call methods via
/// `ref.read(orderProvider.notifier)`; rendered state flows from
/// [orderProvider] (narrow `select`s on hot paths).
class OrderNotifier extends Notifier<OrderState> {
  MadarBridge get _bridge => ref.read(bridgeProvider);

  String _tr(String key) => _bridge.tr(key: key);

  /// Route/session may have moved in the core — the old `onStateChanged`.
  void _refreshShell() => ref.read(shellProvider.notifier).refresh();

  @override
  OrderState build() {
    final session = _bridge.currentSession();
    return OrderState(
      isWaiter: session?.role == 'waiter',
      currency: session?.currencyCode ?? '',
    );
  }

  // ── toast ──────────────────────────────────────────────────────────────────
  VoidCallback? _toastAction;
  int _toastSeq = 0;

  void showToast(
    String text, {
    ChipTone tone = ChipTone.neutral,
    String? actionLabel,
    VoidCallback? action,
    double seconds = 2.6,
    String? icon,
  }) {
    _toastSeq += 1;
    _toastAction = action;
    state = state.copyWith(
      toast: ToastData(
        id: _toastSeq,
        text: text,
        tone: tone,
        actionLabel: actionLabel,
        seconds: seconds,
        icon: icon,
      ),
    );
  }

  void dismissToast(int id) {
    if (state.toast?.id != id) return;
    _toastAction = null;
    state = state.copyWith(toast: null);
  }

  void runToastAction() {
    final action = _toastAction;
    _toastAction = null;
    state = state.copyWith(toast: null);
    action?.call();
  }

  void clearError() => state = state.copyWith(error: null);

  // ── lifecycle ──────────────────────────────────────────────────────────────
  /// Mirror of the natives' on-appear LaunchedEffect: re-derive the session
  /// slice (a new teller may have signed in since the last mount), reconcile
  /// the shift (catches a dashboard force-close — teller only; a waiter
  /// holds no shift), load the catalog + cart + drafts/tickets, and ping
  /// connectivity.
  Future<void> init() async {
    final session = _bridge.currentSession();
    state = state.copyWith(
      isWaiter: session?.role == 'waiter',
      currency: session?.currencyCode ?? '',
      isLoadingCatalog: true,
      activeTicketId: null,
      error: null,
      clockSkewMinutes: _bridge.clockSkewMinutes(),
    );
    if (state.isWaiter) {
      await Future.wait([loadCatalog(), loadOpenTickets()]);
    } else {
      await reconcileShift();
      await loadCatalog();
      await loadShiftStats();
    }
    await loadCart();
    await loadDrafts();
    await refreshConnectivity();
  }

  // ── shift ──────────────────────────────────────────────────────────────────
  /// Live shift totals — refreshed on init and after the tender drawer
  /// closes (a placed order moves them).
  Future<void> loadShiftStats() async {
    if (state.isWaiter) return;
    final orders = await _quiet(_bridge.listShiftOrders);
    if (orders == null) return;
    final stats = await _quiet(() => _bridge.shiftStats(orders: orders));
    if (stats == null) return;
    state = state.copyWith(
      shiftSalesMinor: stats.salesMinor,
      shiftOrderCount: stats.orderCount,
    );
  }

  /// Sync the open shift with the server (online) or read the cache. The
  /// core may discover the shift was force-closed — the route can move, so
  /// the shell is refreshed.
  Future<void> reconcileShift() async {
    ShiftView? shift;
    try {
      shift = await _bridge.refreshShift();
    } on MadarError {
      shift = await _quiet<ShiftView?>(_bridge.currentShift);
    }
    state = state.copyWith(shift: shift);
    _refreshShell();
  }

  // ── catalog ────────────────────────────────────────────────────────────────
  Future<void> loadCatalog() async {
    try {
      final categories = await _bridge.listCategories();
      final menuItems = await _bridge.listMenuItems();
      final bundles = await _bridge.availableBundles(
        nowRfc3339: nowRfc3339Local(),
      );
      state = state.copyWith(
        categories: categories,
        menuItems: menuItems,
        bundles: bundles,
        isLoadingCatalog: false,
      );
    } on MadarError catch (e) {
      state = state.copyWith(
        error: _bridge.humanMessage(e),
        isLoadingCatalog: false,
      );
    }
  }

  /// Manual "sync server data" — re-pulls the catalog (menu, add-ons,
  /// bundles, payment methods, discounts), then re-projects.
  Future<void> refreshServerData() async {
    if (state.isSyncingData) return;
    state = state.copyWith(isSyncingData: true);
    try {
      await _bridge.refreshCatalog();
      await loadCatalog();
      showToast(
        _tr('chrome.sync_done'),
        tone: ChipTone.success,
        icon: 'checkmark.circle',
      );
    } on MadarError catch (e) {
      // An expired / missing bearer must open the re-auth flow, not
      // dead-end in a toast — the teller can fix it right there.
      if (e is MadarError_Unauthenticated) {
        ref.read(reauthRequestProvider.notifier).request();
      } else {
        showToast(
          _bridge.humanMessage(e),
          tone: ChipTone.danger,
          icon: 'xmark.circle',
        );
      }
    } finally {
      state = state.copyWith(isSyncingData: false);
    }
  }

  CatStyleView categoryStyle(String name, {required bool dark}) =>
      _bridge.categoryStyle(name: name, dark: dark);

  // ── cart ───────────────────────────────────────────────────────────────────
  /// Stamp the start timestamp on the empty→non-empty transition, drop it
  /// once the cart empties; a non-null value is never clobbered.
  String? _startedAtFor(List<CartLineView> lines) =>
      lines.isEmpty ? null : (state.cartStartedAtIso ?? nowIso());

  Future<CartTotals> _fetchTotals() async =>
      await _quiet(_bridge.cartTotals) ?? _emptyTotals;

  /// Run a cart mutation that returns the new lines, then refresh totals.
  Future<void> _applyCart(Future<List<CartLineView>> Function() op) async {
    try {
      final lines = await op();
      final startedAt = _startedAtFor(lines);
      final totals = await _fetchTotals();
      state = state.copyWith(
        cartLines: lines,
        cartStartedAtIso: startedAt,
        cartTotals: totals,
      );
    } on MadarError catch (e) {
      state = state.copyWith(error: _bridge.humanMessage(e));
    }
  }

  Future<void> loadCart() => _applyCart(_bridge.cartLines);

  /// Add one unit of [item] — the core merges into the matching line.
  Future<void> addToCart(MenuItemView item) => _applyCart(
    () => _bridge.cartAdd(
      itemId: item.id,
      name: item.name,
      unitPriceMinor: item.basePriceMinor,
    ),
  );

  Future<void> setCartQty(String lineKey, int qty) =>
      _applyCart(() => _bridge.cartSetQty(itemId: lineKey, qty: qty));

  /// Swipe-to-delete: remove the whole line and offer an Undo toast.
  ///
  /// The row is dropped from the state SYNCHRONOUSLY (listeners notified)
  /// before the bridge round-trip: any rebuild landing in the await window
  /// (the 15s heartbeat notify, a toast) with the dismissed Dismissible
  /// still in the tree throws "A dismissed Dismissible widget is still part
  /// of the tree". The bridge result reconciles after.
  Future<void> swipeRemoveCartLine(CartLineView line) async {
    final lines = state.cartLines
        .where((l) => l.key != line.key)
        .toList(growable: false);
    state = state.copyWith(
      cartLines: lines,
      cartStartedAtIso: _startedAtFor(lines),
    );
    await _applyCart(() => _bridge.cartRemove(itemId: line.key));
    showToast(
      '${_tr('order.removed')} ${line.name}',
      actionLabel: _tr('order.undo'),
      action: () => unawaited(undoRemoveCartLine()),
      seconds: 4,
      icon: 'trash',
    );
  }

  Future<void> undoRemoveCartLine() => _applyCart(_bridge.cartRestoreRemoved);

  Future<void> clearCart() async {
    await _quiet(() async {
      await _bridge.cartClear();
      return true;
    });
    final totals = await _fetchTotals();
    state = state.copyWith(
      cartLines: const [],
      cartStartedAtIso: null,
      cartTotals: totals,
    );
  }

  // ── item customization ─────────────────────────────────────────────────────
  /// The item's addons with charged prices resolved by the core.
  Future<List<ItemAddonView>> loadItemAddons(String itemId) async =>
      await _quiet(() => _bridge.listItemAddons(itemId: itemId)) ?? const [];

  /// Live recipe preview for the current selection — pure + cheap, so the
  /// sheet recomputes per toggle (online or offline).
  Future<List<ComputedRecipeLineView>> recipePreview({
    required String itemId,
    required List<AddonSelection> addons,
    required List<String> optionalIds,
    String? sizeLabel,
  }) async =>
      await _quiet(
        () => _bridge.computeRecipe(
          itemId: itemId,
          sizeLabel: sizeLabel,
          addons: addons,
          optionalFieldIds: optionalIds,
        ),
      ) ??
      const [];

  /// Add (or, in edit mode, replace) a configured line. The core resolves
  /// the charged prices from the catalog; we just pass the selection.
  Future<void> addConfigured({
    required String itemId,
    required List<AddonSelection> addons,
    required List<String> optionalIds,
    required int qty,
    String? sizeLabel,
    String? notes,
    String? replaceLineKey,
  }) async {
    if (replaceLineKey != null) {
      await _quiet(() => _bridge.cartRemove(itemId: replaceLineKey));
    }
    try {
      await _bridge.cartAddConfigured(
        itemId: itemId,
        sizeLabel: sizeLabel,
        addons: addons,
        optionalFieldIds: optionalIds,
        qty: qty,
        notes: notes,
      );
    } on MadarError catch (e) {
      state = state.copyWith(error: _bridge.humanMessage(e));
    }
    await loadCart();
  }

  // ── bundles ────────────────────────────────────────────────────────────────
  /// Add a configured bundle — the core resolves each component's charged
  /// extras and records one bundle line at the fixed bundle price.
  Future<void> addBundle(
    String bundleId,
    List<BundleComponentSelection> components,
  ) async {
    try {
      await _bridge.cartAddBundle(
        bundleId: bundleId,
        components: components,
        qty: 1,
      );
    } on MadarError catch (e) {
      state = state.copyWith(error: _bridge.humanMessage(e));
    }
    await loadCart();
  }

  // ── drafts / held orders ───────────────────────────────────────────────────
  Future<void> loadDrafts() async {
    final drafts = await _quiet(_bridge.listDrafts);
    state = state.copyWith(drafts: drafts ?? state.drafts);
  }

  /// Park the current cart as a held order, named by the wall-clock "HH:MM"
  /// it's parked at. The core stamps createdAt (the strip's sort key).
  Future<void> holdCart() async {
    await _quiet(() async {
      await _bridge.holdCart(name: nowHHMM());
      return true;
    });
    state = state.copyWith(cartStartedAtIso: null);
    await loadCart();
    await loadDrafts();
  }

  /// Restore a held order into the cart (replacing the current one), adopting
  /// the draft's own createdAt as the cart's start timestamp.
  Future<void> restoreDraft(String id) async {
    final createdAt = state.drafts
        .where((d) => d.id == id)
        .firstOrNull
        ?.createdAt;
    try {
      final lines = await _bridge.restoreDraft(id: id);
      state = state.copyWith(cartLines: lines);
    } on MadarError catch (e) {
      state = state.copyWith(error: _bridge.humanMessage(e));
    }
    final totals = await _fetchTotals();
    state = state.copyWith(
      cartStartedAtIso: createdAt ?? state.cartStartedAtIso,
      cartTotals: totals,
    );
    await loadDrafts();
    _refreshShell();
  }

  Future<void> discardDraft(String id) async {
    await _quiet(() async {
      await _bridge.discardDraft(id: id);
      return true;
    });
    await loadDrafts();
  }

  /// Tab-style switch to a held order: park the current cart first (if any)
  /// so nothing is lost, then load the target under its own createdAt.
  Future<void> switchToHeldOrder(String id) async {
    final createdAt = state.drafts
        .where((d) => d.id == id)
        .firstOrNull
        ?.createdAt;
    if (state.cartLines.isNotEmpty) {
      await _quiet(() async {
        await _bridge.holdCart(name: nowHHMM());
        return true;
      });
    }
    state = state.copyWith(cartStartedAtIso: null);
    await restoreDraft(id);
    state = state.copyWith(
      cartStartedAtIso: createdAt ?? state.cartStartedAtIso,
    );
  }

  // ── waiter (dine-in tickets) ───────────────────────────────────────────────
  Future<void> loadOpenTickets() async {
    final tickets = await _quiet(_bridge.listOpenTickets);
    if (tickets == null) return;
    final active = state.activeTicketId;
    state = state.copyWith(
      openTickets: tickets,
      activeTicketId: active != null && tickets.any((t) => t.id == active)
          ? active
          : null,
    );
  }

  /// Select (or, passing the same id, keep) the round target; null targets a
  /// NEW ticket. Only sets the target — the cart stays the new round.
  void selectTicket(String? id) => state = state.copyWith(activeTicketId: id);

  /// Waiter checkout: fire the cart as a NEW ticket, or add it as a ROUND to
  /// the targeted ticket. Clears the target on success.
  Future<bool> fireOrAddRound({
    String? customerName,
    String? tableId,
    String? notes,
    int? guestCount,
  }) async {
    final target = state.activeTicketId;
    final ok = target != null
        ? await _addRound(target)
        : await _fireTicket(
            customerName: customerName,
            tableId: tableId,
            notes: notes,
            guestCount: guestCount,
          );
    if (ok) {
      state = state.copyWith(activeTicketId: null);
      _refreshShell();
    }
    return ok;
  }

  Future<bool> _fireTicket({
    String? customerName,
    String? tableId,
    String? notes,
    int? guestCount,
  }) async {
    state = state.copyWith(isBusy: true, error: null);
    try {
      final fired = await _bridge.fireTicket(
        tableId: tableId,
        customerName: customerName,
        notes: notes,
        guestCount: guestCount,
      );
      await loadCart();
      await loadOpenTickets();
      showToast(
        fired.queuedOffline
            ? '${_tr('waiter.fired')} · ${_tr('waiter.queued')}'
            : _tr('waiter.fired'),
        tone: ChipTone.success,
        icon: 'checkmark.circle',
      );
      return true;
    } on MadarError catch (e) {
      state = state.copyWith(error: _bridge.humanMessage(e));
      return false;
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<bool> _addRound(String ticketId) async {
    state = state.copyWith(isBusy: true, error: null);
    try {
      await _bridge.addTicketRound(ticketId: ticketId);
      await loadCart();
      await loadOpenTickets();
      showToast(
        _tr('waiter.fired'),
        tone: ChipTone.success,
        icon: 'checkmark.circle',
      );
      return true;
    } on MadarError catch (e) {
      state = state.copyWith(error: _bridge.humanMessage(e));
      return false;
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  /// SETTLE an open ticket into a paid order in the cashier's shift through
  /// the shared checkout drawer (the natives' AppModel.settleTicket): the
  /// shift id is resolved here (no shift → `waiter.need_shift`), the tender
  /// fields come from the drawer's CheckoutResult, and success reloads the
  /// open board + refreshes the shell (history/shift stats move).
  Future<bool> settleTicket(
    String ticketId,
    String paymentMethodId, {
    int? amountTenderedMinor,
    int? tipMinor,
    String? tipPaymentMethodId,
  }) async {
    final shiftId = state.shift?.id;
    if (shiftId == null) {
      state = state.copyWith(error: _tr('waiter.need_shift'));
      return false;
    }
    state = state.copyWith(isBusy: true, error: null);
    try {
      await _bridge.settleTicket(
        ticketId: ticketId,
        shiftId: shiftId,
        paymentMethodId: paymentMethodId,
        amountTenderedMinor: amountTenderedMinor,
        tipMinor: tipMinor,
        tipPaymentMethodId: tipPaymentMethodId,
      );
      await loadOpenTickets();
      showToast(_tr('waiter.settled'), tone: ChipTone.success);
      _refreshShell();
      return true;
    } on MadarError catch (e) {
      state = state.copyWith(error: _bridge.humanMessage(e));
      return false;
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> voidTicket(String ticketId, String? reason) async {
    try {
      await _bridge.voidTicket(ticketId: ticketId, reason: reason);
      await loadOpenTickets();
    } on MadarError catch (e) {
      showToast(
        _bridge.humanMessage(e),
        tone: ChipTone.danger,
        icon: 'xmark.circle',
      );
    }
    state = state.copyWith(activeTicketId: null);
  }

  // ── connectivity heartbeat ─────────────────────────────────────────────────
  /// Ping + refresh the sync chrome. On an offline→online transition the
  /// teller's shift is reconciled (mirrors the natives' refreshConnectivity).
  Future<void> refreshConnectivity() async {
    final wasOnline = state.isOnline;
    final online = await _quiet(_bridge.refreshConnectivity) ?? false;
    final status = await _quiet(_bridge.syncStatus);
    state = state.copyWith(
      isOnline: online,
      pendingCount: status?.pending ?? state.pendingCount,
      syncFailed: status?.failed ?? state.syncFailed,
      syncAuthPaused: status?.authPaused ?? state.syncAuthPaused,
      clockSkewMinutes: _bridge.clockSkewMinutes(),
    );
    if (!wasOnline && online && !state.isWaiter) {
      await reconcileShift();
    }
  }

  /// Reflect the core's CURRENT sync/online state into the chrome WITHOUT
  /// pinging — the app-level connectivity service already refreshed the
  /// core (OS network change / resume / periodic probe) and pulsed us. We
  /// only re-read the cheap in-memory status and reconcile the shift on an
  /// offline→online edge. Cheaper and more responsive than a screen-local
  /// heartbeat, and it stays live even off the order screen.
  Future<void> syncFromStatus() async {
    final status = await _quiet(_bridge.syncStatus);
    if (status == null) return;
    final wasOnline = state.isOnline;
    state = state.copyWith(
      isOnline: status.online,
      pendingCount: status.pending,
      syncFailed: status.failed,
      syncAuthPaused: status.authPaused,
      clockSkewMinutes: _bridge.clockSkewMinutes(),
    );
    if (!wasOnline && status.online && !state.isWaiter) {
      await reconcileShift();
    }
  }

  /// Run a bridge call whose failure the natives swallow (cache reads,
  /// best-effort refreshes) — returns null instead of surfacing the error.
  Future<T?> _quiet<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on MadarError {
      return null;
    }
  }
}

/// THE order surface state — shared by the order screen, the drafts manager,
/// and the open-tickets settle board (a restore/settle on one mutates the
/// same cart/board the others render — the natives' single AppModel).
final orderProvider = NotifierProvider<OrderNotifier, OrderState>(
  OrderNotifier.new,
);
