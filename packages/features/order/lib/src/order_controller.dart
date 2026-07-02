import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Screen-local mirror of the natives' AppModel slice the order screen
/// consumes: catalog, cart (+ start timestamp), drafts, open tickets,
/// connectivity chrome, and the toast/error slots. All business logic stays
/// in the core; this only sequences bridge calls and notifies the widgets.
class OrderController extends ChangeNotifier {
  OrderController({required this.core, required this.onStateChanged});

  final MadarCore core;

  /// Shell callback — fired after any bridge call that can move
  /// `app_route()` / the session (shift reconcile, fire-to-kitchen, …).
  final VoidCallback onStateChanged;

  MadarBridge get bridge => core.bridge;

  String tr(String key) => bridge.tr(key: key);

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── session ────────────────────────────────────────────────────────────────
  SessionSnapshot? get session => bridge.currentSession();

  String get currency => session?.currencyCode ?? '';

  /// Waiter devices fire tickets instead of tendering (the natives'
  /// isWaiterDevice — a session-role check).
  bool get isWaiter => session?.role == 'waiter';

  ShiftView? shift;

  // ── catalog ────────────────────────────────────────────────────────────────
  List<CategoryView> categories = const [];
  List<MenuItemView> menuItems = const [];
  List<BundleView> bundles = const [];
  bool isLoadingCatalog = true;
  bool isSyncingData = false;

  // ── cart ───────────────────────────────────────────────────────────────────
  List<CartLineView> cartLines = const [];
  CartTotals cartTotals = const CartTotals(
    itemCount: 0,
    subtotalMinor: 0,
    discountMinor: 0,
    taxMinor: 0,
    totalMinor: 0,
  );

  /// RFC3339 stamp of the cart's empty→non-empty transition — the live-cart
  /// chip's sort key + "HH:MM" label in the held-orders strip. A restored
  /// draft adopts its own createdAt instead.
  String? cartStartedAtIso;

  // ── drafts + waiter tickets ────────────────────────────────────────────────
  List<DraftView> drafts = const [];
  List<TicketView> openTickets = const [];

  /// The waiter's selected round target (null = firing a NEW ticket).
  String? activeTicketId;

  TicketView? get activeTicket => isWaiter
      ? openTickets.where((t) => t.id == activeTicketId).firstOrNull
      : null;

  // ── chrome ─────────────────────────────────────────────────────────────────
  bool isOnline = true;
  int pendingCount = 0;
  int syncFailed = 0;
  bool syncAuthPaused = false;
  String? error;
  bool isBusy = false;

  int get clockSkewMinutes => bridge.clockSkewMinutes();

  // ── toast ──────────────────────────────────────────────────────────────────
  ToastData? toast;
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
    toast = ToastData(
      id: _toastSeq,
      text: text,
      tone: tone,
      actionLabel: actionLabel,
      seconds: seconds,
      icon: icon,
    );
    _notify();
  }

  void dismissToast(int id) {
    if (toast?.id != id) return;
    toast = null;
    _toastAction = null;
    _notify();
  }

  void runToastAction() {
    final action = _toastAction;
    toast = null;
    _toastAction = null;
    action?.call();
    _notify();
  }

  void clearError() {
    error = null;
    _notify();
  }

  // ── lifecycle ──────────────────────────────────────────────────────────────
  /// Mirror of the natives' on-appear LaunchedEffect: reconcile the shift
  /// (catches a dashboard force-close — teller only; a waiter holds no
  /// shift), load the catalog + cart + drafts/tickets, and ping connectivity.
  Future<void> init() async {
    if (isWaiter) {
      await Future.wait([loadCatalog(), loadOpenTickets()]);
    } else {
      await reconcileShift();
      await loadCatalog();
    }
    await loadCart();
    await loadDrafts();
    await refreshConnectivity();
  }

  /// Sync the open shift with the server (online) or read the cache. The
  /// core may discover the shift was force-closed — the route can move, so
  /// the shell is notified.
  Future<void> reconcileShift() async {
    try {
      shift = await bridge.refreshShift();
    } on MadarError {
      shift = await _quiet<ShiftView?>(bridge.currentShift);
    }
    onStateChanged();
    _notify();
  }

  // ── catalog ────────────────────────────────────────────────────────────────
  Future<void> loadCatalog() async {
    try {
      categories = await bridge.listCategories();
      menuItems = await bridge.listMenuItems();
      bundles = await bridge.availableBundles(nowRfc3339: nowRfc3339Local());
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
    } finally {
      isLoadingCatalog = false;
      _notify();
    }
  }

  /// Manual "sync server data" — re-pulls the catalog (menu, add-ons,
  /// bundles, payment methods, discounts), then re-projects.
  Future<void> refreshServerData() async {
    if (isSyncingData) return;
    isSyncingData = true;
    _notify();
    try {
      await bridge.refreshCatalog();
      await loadCatalog();
      showToast(
        tr('chrome.sync_done'),
        tone: ChipTone.success,
        icon: 'checkmark.circle',
      );
    } on MadarError catch (e) {
      showToast(
        bridge.humanMessage(e),
        tone: ChipTone.danger,
        icon: 'xmark.circle',
      );
    } finally {
      isSyncingData = false;
      _notify();
    }
  }

  CatStyleView categoryStyle(String name, {required bool dark}) =>
      bridge.categoryStyle(name: name, dark: dark);

  String categoryName(String? id) =>
      categories.where((c) => c.id == id).firstOrNull?.name ?? '';

  /// Total quantity of an item already in the cart, summed across its config
  /// variants — drives the catalog card's in-cart badge.
  int cartQtyForItem(String itemId) => cartLines
      .where((l) => l.itemId == itemId)
      .fold(0, (sum, l) => sum + l.qty);

  // ── cart ───────────────────────────────────────────────────────────────────
  /// Stamp the start timestamp on the empty→non-empty transition, drop it
  /// once the cart empties; a non-null value is never clobbered.
  void _syncCartStartedAt() {
    if (cartLines.isEmpty) {
      cartStartedAtIso = null;
    } else {
      cartStartedAtIso ??= nowIso();
    }
  }

  Future<void> _refreshTotals() async {
    cartTotals =
        await _quiet(bridge.cartTotals) ??
        const CartTotals(
          itemCount: 0,
          subtotalMinor: 0,
          discountMinor: 0,
          taxMinor: 0,
          totalMinor: 0,
        );
  }

  /// Run a cart mutation that returns the new lines, then refresh totals.
  Future<void> _applyCart(Future<List<CartLineView>> Function() op) async {
    try {
      cartLines = await op();
      _syncCartStartedAt();
      await _refreshTotals();
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
    }
    _notify();
  }

  Future<void> loadCart() => _applyCart(bridge.cartLines);

  /// Add one unit of [item] — the core merges into the matching line.
  Future<void> addToCart(MenuItemView item) => _applyCart(
    () => bridge.cartAdd(
      itemId: item.id,
      name: item.name,
      unitPriceMinor: item.basePriceMinor,
    ),
  );

  Future<void> setCartQty(String lineKey, int qty) =>
      _applyCart(() => bridge.cartSetQty(itemId: lineKey, qty: qty));

  /// Swipe-to-delete: remove the whole line and offer an Undo toast.
  Future<void> swipeRemoveCartLine(CartLineView line) async {
    await _applyCart(() => bridge.cartRemove(itemId: line.key));
    showToast(
      '${tr('order.removed')} ${line.name}',
      actionLabel: tr('order.undo'),
      action: () => unawaited(undoRemoveCartLine()),
      seconds: 4,
      icon: 'trash',
    );
  }

  Future<void> undoRemoveCartLine() => _applyCart(bridge.cartRestoreRemoved);

  Future<void> clearCart() async {
    await _quiet(() async {
      await bridge.cartClear();
      return true;
    });
    cartLines = const [];
    cartStartedAtIso = null;
    await _refreshTotals();
    _notify();
  }

  // ── item customization ─────────────────────────────────────────────────────
  /// The item's addons with charged prices resolved by the core.
  Future<List<ItemAddonView>> loadItemAddons(String itemId) async =>
      await _quiet(() => bridge.listItemAddons(itemId: itemId)) ?? const [];

  /// Live recipe preview for the current selection — pure + cheap, so the
  /// sheet recomputes per toggle (online or offline).
  Future<List<ComputedRecipeLineView>> recipePreview({
    required String itemId,
    required List<AddonSelection> addons,
    required List<String> optionalIds,
    String? sizeLabel,
  }) async =>
      await _quiet(
        () => bridge.computeRecipe(
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
      await _quiet(() => bridge.cartRemove(itemId: replaceLineKey));
    }
    try {
      await bridge.cartAddConfigured(
        itemId: itemId,
        sizeLabel: sizeLabel,
        addons: addons,
        optionalFieldIds: optionalIds,
        qty: qty,
        notes: notes,
      );
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
    }
    await loadCart();
  }

  // ── bundles ────────────────────────────────────────────────────────────────
  MenuItemView? menuItemById(String itemId) =>
      menuItems.where((i) => i.id == itemId).firstOrNull;

  /// Add a configured bundle — the core resolves each component's charged
  /// extras and records one bundle line at the fixed bundle price.
  Future<void> addBundle(
    String bundleId,
    List<BundleComponentSelection> components,
  ) async {
    try {
      await bridge.cartAddBundle(
        bundleId: bundleId,
        components: components,
        qty: 1,
      );
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
    }
    await loadCart();
  }

  // ── drafts / held orders ───────────────────────────────────────────────────
  Future<void> loadDrafts() async {
    drafts = await _quiet(bridge.listDrafts) ?? drafts;
    _notify();
  }

  /// Park the current cart as a held order, named by the wall-clock "HH:MM"
  /// it's parked at. The core stamps createdAt (the strip's sort key).
  Future<void> holdCart() async {
    await _quiet(() async {
      await bridge.holdCart(name: nowHHMM());
      return true;
    });
    cartStartedAtIso = null;
    await loadCart();
    await loadDrafts();
  }

  /// Restore a held order into the cart (replacing the current one), adopting
  /// the draft's own createdAt as the cart's start timestamp.
  Future<void> restoreDraft(String id) async {
    final createdAt = drafts.where((d) => d.id == id).firstOrNull?.createdAt;
    try {
      cartLines = await bridge.restoreDraft(id: id);
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
    }
    cartStartedAtIso = createdAt ?? cartStartedAtIso;
    await _refreshTotals();
    await loadDrafts();
  }

  Future<void> discardDraft(String id) async {
    await _quiet(() async {
      await bridge.discardDraft(id: id);
      return true;
    });
    await loadDrafts();
  }

  /// Tab-style switch to a held order: park the current cart first (if any)
  /// so nothing is lost, then load the target under its own createdAt.
  Future<void> switchToHeldOrder(String id) async {
    final createdAt = drafts.where((d) => d.id == id).firstOrNull?.createdAt;
    if (cartLines.isNotEmpty) {
      await _quiet(() async {
        await bridge.holdCart(name: nowHHMM());
        return true;
      });
    }
    cartStartedAtIso = null;
    await restoreDraft(id);
    cartStartedAtIso = createdAt ?? cartStartedAtIso;
    _notify();
  }

  // ── waiter (dine-in tickets) ───────────────────────────────────────────────
  Future<void> loadOpenTickets() async {
    final tickets = await _quiet(bridge.listOpenTickets);
    if (tickets == null) return;
    openTickets = tickets;
    if (activeTicketId != null && !tickets.any((t) => t.id == activeTicketId)) {
      activeTicketId = null;
    }
    _notify();
  }

  /// Select (or, passing the same id, keep) the round target; null targets a
  /// NEW ticket. Only sets the target — the cart stays the new round.
  void selectTicket(String? id) {
    activeTicketId = id;
    _notify();
  }

  /// Waiter checkout: fire the cart as a NEW ticket, or add it as a ROUND to
  /// the targeted ticket. Clears the target on success.
  Future<bool> fireOrAddRound({
    String? customerName,
    String? tableId,
    String? notes,
    int? guestCount,
  }) async {
    final target = activeTicketId;
    final ok = target != null
        ? await _addRound(target)
        : await _fireTicket(
            customerName: customerName,
            tableId: tableId,
            notes: notes,
            guestCount: guestCount,
          );
    if (ok) {
      activeTicketId = null;
      onStateChanged();
    }
    _notify();
    return ok;
  }

  Future<bool> _fireTicket({
    String? customerName,
    String? tableId,
    String? notes,
    int? guestCount,
  }) async {
    isBusy = true;
    error = null;
    _notify();
    try {
      final fired = await bridge.fireTicket(
        tableId: tableId,
        customerName: customerName,
        notes: notes,
        guestCount: guestCount,
      );
      await loadCart();
      await loadOpenTickets();
      showToast(
        fired.queuedOffline
            ? '${tr('waiter.fired')} · ${tr('waiter.queued')}'
            : tr('waiter.fired'),
        tone: ChipTone.success,
        icon: 'checkmark.circle',
      );
      return true;
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
      return false;
    } finally {
      isBusy = false;
      _notify();
    }
  }

  Future<bool> _addRound(String ticketId) async {
    isBusy = true;
    error = null;
    _notify();
    try {
      await bridge.addTicketRound(ticketId: ticketId);
      await loadCart();
      await loadOpenTickets();
      showToast(
        tr('waiter.fired'),
        tone: ChipTone.success,
        icon: 'checkmark.circle',
      );
      return true;
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
      return false;
    } finally {
      isBusy = false;
      _notify();
    }
  }

  /// SETTLE an open ticket into a paid order in the cashier's shift through
  /// the shared checkout drawer (the natives' AppModel.settleTicket): the
  /// shift id is resolved here (no shift → `waiter.need_shift`), the tender
  /// fields come from the drawer's CheckoutResult, and success reloads the
  /// open board + notifies the shell (history/shift stats move).
  Future<bool> settleTicket(
    String ticketId,
    String paymentMethodId, {
    int? amountTenderedMinor,
    int? tipMinor,
    String? tipPaymentMethodId,
  }) async {
    final shiftId = shift?.id;
    if (shiftId == null) {
      error = tr('waiter.need_shift');
      _notify();
      return false;
    }
    isBusy = true;
    error = null;
    _notify();
    try {
      await bridge.settleTicket(
        ticketId: ticketId,
        shiftId: shiftId,
        paymentMethodId: paymentMethodId,
        amountTenderedMinor: amountTenderedMinor,
        tipMinor: tipMinor,
        tipPaymentMethodId: tipPaymentMethodId,
      );
      await loadOpenTickets();
      showToast(tr('waiter.settled'), tone: ChipTone.success);
      onStateChanged();
      return true;
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
      return false;
    } finally {
      isBusy = false;
      _notify();
    }
  }

  Future<void> voidTicket(String ticketId, String? reason) async {
    try {
      await bridge.voidTicket(ticketId: ticketId, reason: reason);
      await loadOpenTickets();
    } on MadarError catch (e) {
      showToast(
        bridge.humanMessage(e),
        tone: ChipTone.danger,
        icon: 'xmark.circle',
      );
    }
    activeTicketId = null;
    _notify();
  }

  // ── connectivity heartbeat ─────────────────────────────────────────────────
  /// Ping + refresh the sync chrome. On an offline→online transition the
  /// teller's shift is reconciled (mirrors the natives' refreshConnectivity).
  Future<void> refreshConnectivity() async {
    final wasOnline = isOnline;
    isOnline = await _quiet(bridge.refreshConnectivity) ?? false;
    final status = await _quiet(bridge.syncStatus);
    if (status != null) {
      pendingCount = status.pending;
      syncFailed = status.failed;
      syncAuthPaused = status.authPaused;
    }
    if (!wasOnline && isOnline && !isWaiter) {
      await reconcileShift();
    }
    _notify();
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
