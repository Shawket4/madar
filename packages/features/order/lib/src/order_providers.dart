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

/// A table left needing a bus by a checkout, waiting on the teller's answer.
///
/// The pair is carried (not just the id) so the prompt can name the table even
/// after the floor mirror reloads without it — the question is about a table
/// the teller was JUST standing at, and "clear table 12?" is answerable where
/// "clear this table?" is not.
@immutable
class PendingTableClear {
  const PendingTableClear(this.tableId, this.label);

  final String tableId;
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is PendingTableClear &&
      other.tableId == tableId &&
      other.label == label;

  @override
  int get hashCode => Object.hash(tableId, label);
}

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
    this.cartName,
    this.cartDraftId,
    this.cartTableId,
    this.cartTableLabel,
    this.cartBookingId,
    this.drafts = const [],
    this.openTickets = const [],
    this.arrivals = const [],
    this.floorLayout,
    this.transferQueue = const [],
    this.pendingTableClear,
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

  /// RFC3339 stamp of the cart's FIRST item (the empty→non-empty
  /// transition) — the live-cart chip's sort key + "HH:MM" label in the
  /// held-orders strip. It NEVER updates while the order lives: a restored
  /// draft adopts its own createdAt, and re-parking passes it back, so a
  /// held order keeps its oldest→newest position across switch cycles.
  final String? cartStartedAtIso;

  /// Free-text name of the live order (the strip's rename affordance) —
  /// null/empty renders the "HH:MM" time label instead. Survives hold →
  /// restore cycles via the draft's name.
  final String? cartName;

  /// The draft id this cart was restored FROM (null = a brand-new order).
  /// Passed back on hold so the draft keeps its identity (and the strip's
  /// manual drag order, keyed by id, holds).
  final String? cartDraftId;

  /// The floor table picked for the LIVE order (applied when it parks) —
  /// set from the edit sheet or a canvas tap. Null = no table.
  final String? cartTableId;
  final String? cartTableLabel;

  /// The booking this order seats (set by "Seat this party"); the fired
  /// ticket carries it so the server links the two. Cleared on fire/park.
  final String? cartBookingId;

  // ── drafts + waiter tickets ──────────────────────────────────────────────
  final List<DraftView> drafts;
  final List<TicketView> openTickets;

  /// Today's active bookings (the arrivals list), from the offline cache.
  final List<BookingView> arrivals;

  // ── floor (offline mirror) ───────────────────────────────────────────────
  /// The branch layout + occupancy. EMPTY sections+tables = the branch has
  /// no floor configured → every table affordance stays hidden (the gate).
  final FloorLayoutView? floorLayout;
  final List<TransferQueueView> transferQueue;

  /// A table whose party just CHECKED OUT and that is now waiting to be
  /// cleared. Set the moment the sale lands; the surface that sees it asks the
  /// teller once ("clear it now?") and then drops it. Declining is not a
  /// failure — the table simply stays `dirty` on the canvas with a one-tap
  /// clear, so bussing is never silently assumed to have happened.
  final PendingTableClear? pendingTableClear;

  /// The feature gate: true only when a layout exists for this branch.
  bool get hasFloor =>
      floorLayout != null &&
      (floorLayout!.sections.isNotEmpty || floorLayout!.tables.isNotEmpty);

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
    Object? cartName = _unset,
    Object? cartDraftId = _unset,
    Object? cartTableId = _unset,
    Object? cartTableLabel = _unset,
    Object? cartBookingId = _unset,
    List<DraftView>? drafts,
    List<TicketView>? openTickets,
    List<BookingView>? arrivals,
    Object? floorLayout = _unset,
    List<TransferQueueView>? transferQueue,
    Object? pendingTableClear = _unset,
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
    cartName: identical(cartName, _unset) ? this.cartName : cartName as String?,
    cartDraftId: identical(cartDraftId, _unset)
        ? this.cartDraftId
        : cartDraftId as String?,
    cartTableId: identical(cartTableId, _unset)
        ? this.cartTableId
        : cartTableId as String?,
    cartTableLabel: identical(cartTableLabel, _unset)
        ? this.cartTableLabel
        : cartTableLabel as String?,
    cartBookingId: identical(cartBookingId, _unset)
        ? this.cartBookingId
        : cartBookingId as String?,
    drafts: drafts ?? this.drafts,
    openTickets: openTickets ?? this.openTickets,
    arrivals: arrivals ?? this.arrivals,
    floorLayout: identical(floorLayout, _unset)
        ? this.floorLayout
        : floorLayout as FloorLayoutView?,
    transferQueue: transferQueue ?? this.transferQueue,
    pendingTableClear: identical(pendingTableClear, _unset)
        ? this.pendingTableClear
        : pendingTableClear as PendingTableClear?,
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
    // Independent bridge reads run CONCURRENTLY (FRB executes them on the
    // Rust pool) — cold-open latency is the slowest call, not the sum. If
    // reconcile discovers a force-closed shift the route moves anyway, and
    // stats re-refresh after every tender, so the overlap is benign.
    if (state.isWaiter) {
      await Future.wait([loadCatalog(), loadOpenTickets()]);
    } else {
      await Future.wait([reconcileShift(), loadCatalog(), loadShiftStats()]);
    }
    await _fetchCatalogIfEmpty();
    await Future.wait([loadCart(), loadDrafts(), loadFloor()]);
    await refreshConnectivity();
    // Pull the floor after connectivity is known: a layout the dashboard
    // changed while this till was closed lands without a manual data sync.
    unawaited(syncFloor());
  }

  /// Fresh device: the local mirror is EMPTY until the first server pull —
  /// don't sit on a blank menu waiting for the manual "sync data" button.
  /// Keeps the skeleton up while the pull runs; best-effort, so an OFFLINE
  /// first boot just lands on the empty state (which offers a sync action).
  Future<void> _fetchCatalogIfEmpty() async {
    if (state.menuItems.isNotEmpty || state.categories.isNotEmpty) return;
    if (_bridge.currentSession() == null) return;
    state = state.copyWith(isLoadingCatalog: true);
    await _quiet(() async {
      await _bridge.refreshCatalog();
      return true;
    });
    await loadCatalog();
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

  /// Profiling-only synthetic catalog multiplier
  /// (`--dart-define=MADAR_SYNTH_CATALOG=N`): each real item is cloned N−1
  /// times with unique ids/names, simulating a production-size menu.
  /// Defaults to 1 (off) — the expansion branch is tree-shaken out of every
  /// build that doesn't pass the define.
  static const int _synthCatalog = int.fromEnvironment(
    'MADAR_SYNTH_CATALOG',
    defaultValue: 1,
  );

  static List<MenuItemView> _synthesize(List<MenuItemView> items) => [
    for (var i = 0; i < _synthCatalog; i++)
      for (final m in items)
        if (i == 0)
          m
        else
          MenuItemView(
            id: '${m.id}-synth$i',
            name: '${m.name} $i',
            description: m.description,
            categoryId: m.categoryId,
            basePriceMinor: m.basePriceMinor,
            imageUrl: m.imageUrl,
            localImagePath: m.localImagePath,
            isActive: m.isActive,
            defaultMilkAddonId: m.defaultMilkAddonId,
            allowedAddonIds: m.allowedAddonIds,
            sizes: m.sizes,
            addonSlots: m.addonSlots,
            optionalFields: m.optionalFields,
            recipes: m.recipes,
            recipeSteps: m.recipeSteps,
          ),
  ];

  Future<void> loadCatalog() async {
    try {
      final categories = await _bridge.listCategories();
      final menuItems = await _bridge.listMenuItems();
      final bundles = await _bridge.availableBundles(
        nowRfc3339: nowRfc3339Local(),
      );
      state = state.copyWith(
        categories: categories,
        menuItems: _synthCatalog > 1 ? _synthesize(menuItems) : menuItems,
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
      // The catalog pull also refreshed the floor/held mirrors — re-project.
      // (refreshCatalog pulls the floor itself, so no second fetch here.)
      await Future.wait([loadDrafts(), loadFloor()]);
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

  /// Deterministic in the core (pure function of name + dark), but reached
  /// over FFI — memoized here so grid/tab builds don't cross the bridge on
  /// every frame.
  final _styleCache = <(String, bool), CatStyleView>{};

  CatStyleView categoryStyle(String name, {required bool dark}) =>
      _styleCache[(name, dark)] ??= _bridge.categoryStyle(
        name: name,
        dark: dark,
      );

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
        // The order is gone once the cart empties (placed/cleared) — its
        // name, draft identity, and table pick go with it.
        cartName: lines.isEmpty ? null : state.cartName,
        cartDraftId: lines.isEmpty ? null : state.cartDraftId,
        cartTableId: lines.isEmpty ? null : state.cartTableId,
        cartTableLabel: lines.isEmpty ? null : state.cartTableLabel,
        cartBookingId: lines.isEmpty ? null : state.cartBookingId,
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
      cartName: null,
      cartDraftId: null,
      cartTableId: null,
      cartTableLabel: null,
      cartBookingId: null,
      cartTotals: totals,
    );
  }

  // ── item customization ─────────────────────────────────────────────────────
  /// The item's addons with charged prices resolved by the core.
  Future<List<ItemAddonView>> loadItemAddons(String itemId) async =>
      await _quiet(() => _bridge.listItemAddons(itemId: itemId)) ?? const [];

  /// The item's MODIFIER GROUPS (unified-model projection) — display-ready
  /// groups with constraints + charged prices resolved by the core.
  Future<List<ModifierGroupView>> loadItemModifierGroups(String itemId) async =>
      await _quiet(() => _bridge.listItemModifierGroups(itemId: itemId)) ??
      const [];

  /// Check a selection against the item's group constraints (min/max/required).
  /// Empty = valid. Errors degrade to "valid" (`_quiet`) — enforcement is a UX
  /// nicety; the core's resolver stays defensive either way.
  Future<List<GroupViolationView>> validateItemSelections({
    required String itemId,
    required List<AddonSelection> addons,
    required List<String> optionalIds,
  }) async =>
      await _quiet(
        () => _bridge.validateItemSelections(
          itemId: itemId,
          addons: addons,
          optionalFieldIds: optionalIds,
        ),
      ) ??
      const [];

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

  /// Park the current cart as a held order — onto its picked table, if any.
  /// A lost table race still parks (the core drops the table + returns true);
  /// the teller gets a toast instead of a failure.
  Future<void> holdCart() async {
    final conflict = await _quiet(
      () => _bridge.holdCartOnTable(
        // The draft keeps the ORDER's identity: its free-text name (may be
        // empty → the chip shows the time), the id it was restored from (a
        // re-park is the SAME draft), and its first-item timestamp — so chips
        // never reshuffle or re-stamp across hold/restore cycles.
        name: state.cartName ?? '',
        draftId: state.cartDraftId,
        startedAt: state.cartStartedAtIso,
        tableId: state.cartTableId,
      ),
    );
    if (conflict ?? false) {
      showToast(_tr('tables.taken'), tone: ChipTone.warning, icon: 'table');
    }
    state = state.copyWith(
      cartStartedAtIso: null,
      cartName: null,
      cartDraftId: null,
      cartTableId: null,
      cartTableLabel: null,
      cartBookingId: null,
    );
    await loadCart();
    await Future.wait([loadDrafts(), loadFloor()]);
  }

  /// Restore a held order into the cart (replacing the current one),
  /// adopting the draft's FULL identity: its createdAt as the immutable
  /// start timestamp, its free-text name, its table, and its id (passed back
  /// on the next hold so the draft never changes identity).
  Future<void> restoreDraft(String id) async {
    final draft = state.drafts.where((d) => d.id == id).firstOrNull;
    if (draft?.lockedByOther ?? false) {
      showToast(_tr('tables.locked'), tone: ChipTone.warning, icon: 'lock');
      return;
    }
    try {
      final lines = await _bridge.restoreDraft(id: id);
      state = state.copyWith(cartLines: lines);
    } on MadarError catch (e) {
      state = state.copyWith(error: _bridge.humanMessage(e));
    }
    final totals = await _fetchTotals();
    final name = draft?.name.trim() ?? '';
    state = state.copyWith(
      cartStartedAtIso: draft?.createdAt ?? state.cartStartedAtIso,
      // Drafts parked before names existed carry an "HH:MM" auto-label —
      // treat those as unnamed so the chip falls back to the live time.
      cartName: name.isEmpty || _looksLikeTimeLabel(name) ? null : name,
      cartDraftId: draft?.id,
      cartTableId: draft?.tableId,
      cartTableLabel: draft?.tableLabel,
      cartTotals: totals,
    );
    await Future.wait([loadDrafts(), loadFloor()]);
    _refreshShell();
  }

  /// Legacy auto-labels ("14:05") from before free-text names — not names.
  static bool _looksLikeTimeLabel(String s) =>
      RegExp(r'^\d{1,2}:\d{2}$').hasMatch(s);

  /// Rename the LIVE order (free text; empty clears back to the time
  /// label). Persists on the next hold via the draft's name.
  void setCartName(String? name) {
    final trimmed = name?.trim() ?? '';
    state = state.copyWith(cartName: trimmed.isEmpty ? null : trimmed);
  }

  /// Pick (or clear) the LIVE order's table — applied when it parks.
  void setCartTable(String? tableId, String? tableLabel) =>
      state = state.copyWith(cartTableId: tableId, cartTableLabel: tableLabel);

  Future<void> discardDraft(String id) async {
    try {
      await _bridge.discardDraft(id: id);
    } on MadarError catch (e) {
      showToast(
        _bridge.humanMessage(e),
        tone: ChipTone.danger,
        icon: 'xmark.circle',
      );
    }
    await Future.wait([loadDrafts(), loadFloor()]);
  }

  /// Tab-style switch to a held order: park the current cart first (if any)
  /// so nothing is lost, then load the target under its own createdAt.
  Future<void> switchToHeldOrder(String id) async {
    // Check the lock BEFORE parking the current cart, so a blocked switch
    // leaves the live order exactly where it was.
    final target = state.drafts.where((d) => d.id == id).firstOrNull;
    if (target?.lockedByOther ?? false) {
      showToast(_tr('tables.locked'), tone: ChipTone.warning, icon: 'lock');
      return;
    }
    if (state.cartLines.isNotEmpty) {
      await _quiet(() async {
        // Park the CURRENT order under its own identity (see holdCart) —
        // table included.
        await _bridge.holdCartOnTable(
          name: state.cartName ?? '',
          draftId: state.cartDraftId,
          startedAt: state.cartStartedAtIso,
          tableId: state.cartTableId,
        );
        return true;
      });
    }
    state = state.copyWith(
      cartStartedAtIso: null,
      cartName: null,
      cartDraftId: null,
      cartTableId: null,
      cartTableLabel: null,
      cartBookingId: null,
    );
    await restoreDraft(id);
  }

  /// A resumed draft's cart just CHECKED OUT — close the loop: the held
  /// order completes (its table lands `dirty`, its waitlist wish cancels)
  /// right behind the order in the outbox.
  Future<void> onOrderSettled(String? draftId) async {
    // Captured before the reloads drop it: the table the sale just vacated.
    final table = state.cartTableId;
    final label = state.cartTableLabel;
    if (draftId != null) {
      await _quiet(() async {
        await _bridge.completeDraft(id: draftId);
        return true;
      });
    }
    // A table the LIVE cart claimed without ever parking still has to be
    // handed on — otherwise it reads taken until the next pull.
    if (table != null) await _busTableLocally(table);
    if (table != null) _askToClear(table, label);
    await Future.wait([
      loadCart(),
      loadShiftStats(),
      loadDrafts(),
      loadFloor(),
    ]);
  }

  /// Mark a table as needing a bus after its party checked out. The server
  /// does the same walk on settle/complete; this keeps the LOCAL mirror in
  /// step so the canvas is right the instant the sale lands (and offline).
  Future<void> _busTableLocally(String tableId) async {
    await _quiet(() async {
      await _bridge.mirrorTableStatus(tableId: tableId, status: 'dirty');
      return true;
    });
  }

  /// Hand a table straight back to the room — no bussing step. Used when no
  /// party vacated it (a void, a move, an unassign).
  Future<void> _freeTableLocally(String tableId) async {
    await _quiet(() async {
      await _bridge.mirrorTableStatus(tableId: tableId, status: 'free');
      return true;
    });
  }

  /// Queue the "clear it now?" question for the surface that can ask it.
  /// Never asks about a table that is not on this branch's floor (a cart can
  /// carry a stale table id), so the teller is never prompted about a table
  /// they cannot see.
  void _askToClear(String tableId, String? label) {
    final known = state.floorLayout?.tables
        .where((t) => t.id == tableId)
        .firstOrNull;
    if (state.floorLayout != null && known == null) return;
    state = state.copyWith(
      pendingTableClear: PendingTableClear(tableId, label ?? known?.label),
    );
  }

  /// The teller answered "clear it" — the table goes back to the room.
  Future<void> clearPendingTable() async {
    final pending = state.pendingTableClear;
    state = state.copyWith(pendingTableClear: null);
    if (pending == null) return;
    await clearTable(pending.tableId);
  }

  /// Bus a table clean: it has been cleared for real, so it goes back to the
  /// room. The teller's one-tap answer on the tables screen, and the same walk
  /// the post-checkout prompt takes when they say "clear it now".
  Future<void> clearTable(String tableId) async {
    await _clearTableOnServer(tableId);
    showToast(
      _tr('tables.cleared'),
      tone: ChipTone.success,
      icon: 'checkmark.circle',
    );
  }

  /// The teller answered "not yet" — the table STAYS `dirty`, visible on the
  /// canvas with a one-tap clear. Dismissing the question is a decision, not
  /// a no-op, so nothing about the table changes here.
  void dismissPendingTableClear() =>
      state = state.copyWith(pendingTableClear: null);

  // ── floor canvas + transfer waitlist ───────────────────────────────────────
  /// Re-project the floor from the local mirrors (instant, offline-safe).
  Future<void> loadFloor() async {
    final layout = await _quiet(_bridge.floorLayout);
    final queue = await _quiet(_bridge.listTransferQueue);
    final arrivals = await _quiet(_bridge.listArrivals);
    state = state.copyWith(
      floorLayout: layout ?? state.floorLayout,
      transferQueue: queue ?? state.transferQueue,
      arrivals: arrivals ?? state.arrivals,
    );
  }

  /// A booked party arrived at their table: mark the booking seated
  /// (optimistic + queued) and point the LIVE order at that table under the
  /// guest's name, so the fire that follows links back to the booking.
  Future<void> seatBooking(FloorTableStateView t) async {
    final id = t.bookingId;
    if (id == null) return;
    await _seatBooking(
      id,
      tableId: t.id,
      tableLabel: t.label,
      guest: t.bookingGuest,
    );
  }

  /// Seat from the arrivals list (the booking's own table, if it has one).
  Future<void> seatArrival(BookingView b) async {
    final tableId = b.tableIds.isEmpty ? null : b.tableIds.first;
    final label = b.tableLabels.isEmpty ? null : b.tableLabels.first;
    await _seatBooking(
      b.id,
      tableId: tableId,
      tableLabel: label,
      guest: b.guestName,
    );
  }

  Future<void> _seatBooking(
    String bookingId, {
    required String? tableId,
    required String? tableLabel,
    required String? guest,
  }) async {
    try {
      await _bridge.seatBooking(bookingId: bookingId, tableId: tableId);
    } on MadarError catch (e) {
      showToast(
        _bridge.humanMessage(e),
        tone: ChipTone.danger,
        icon: 'xmark.circle',
      );
      return;
    }
    state = state.copyWith(
      cartTableId: tableId ?? state.cartTableId,
      cartTableLabel: tableLabel ?? state.cartTableLabel,
      cartBookingId: bookingId,
      cartName: (guest?.trim().isNotEmpty ?? false)
          ? guest!.trim()
          : state.cartName,
    );
    showToast(
      _tr('tables.booking_seated'),
      tone: ChipTone.success,
      icon: 'checkmark.circle',
    );
    await loadFloor();
    _refreshShell();
  }

  /// The party never came: release their table (optimistic + queued).
  Future<void> noShowBooking(String bookingId) async {
    try {
      await _bridge.noShowBooking(bookingId: bookingId);
    } on MadarError catch (e) {
      showToast(
        _bridge.humanMessage(e),
        tone: ChipTone.danger,
        icon: 'xmark.circle',
      );
      return;
    }
    if (state.cartBookingId == bookingId) {
      state = state.copyWith(cartBookingId: null);
    }
    showToast(
      _tr('tables.booking_no_show'),
      tone: ChipTone.warning,
      icon: 'xmark.circle',
    );
    await loadFloor();
  }

  /// PULL the floor from the server, then re-project. This is what makes a
  /// dashboard layout edit show up: the mirror only changes when something
  /// fetches. Called on opening a floor surface, on a `floor.*` realtime
  /// event, and by the safety poll while realtime is down. Best-effort —
  /// offline just re-projects what's already mirrored.
  Future<void> syncFloor() async {
    await _quiet(() async {
      await _bridge.refreshFloor();
      return true;
    });
    await loadFloor();
  }

  /// Clear a bussed table: the one human act the server cannot derive. The
  /// teller's one-tap answer on the tables screen, and the same walk the
  /// post-checkout prompt takes when they say "clear it now". Offline-safe.
  Future<void> _clearTableOnServer(String tableId) async {
    try {
      await _bridge.clearTable(tableId: tableId);
    } on MadarError catch (e) {
      showToast(
        _bridge.humanMessage(e),
        tone: ChipTone.danger,
        icon: 'xmark.circle',
      );
    }
    await loadFloor();
  }

  /// Turn a table back over: release whatever the POS may release, then mark
  /// it available. The teller's counterpart to seating.
  ///
  /// A live WAITER TICKET is never silently orphaned — its bill still has to
  /// be settled or moved, so the action refuses and says so. A parked held
  /// order simply DETACHES (the order survives, table-less, in the strip).
  Future<bool> makeTableAvailable(
    FloorTableStateView table, {
    TicketView? ticket,
  }) async {
    if (ticket != null) {
      showToast(
        _tr('tables.settle_first'),
        tone: ChipTone.warning,
        icon: 'fork.knife',
      );
      return false;
    }
    if (table.heldOrderId != null) {
      if (table.heldLockedByOther) {
        showToast(_tr('tables.locked'), tone: ChipTone.warning, icon: 'lock');
        return false;
      }
      // Detach first: the server buses the freed table, and the status op
      // queued right behind it lands the table on `free`.
      if (!await assignDraftTable(table.heldOrderId!, null)) return false;
    }
    await _clearTableOnServer(table.id);
    showToast(
      _tr('tables.freed'),
      tone: ChipTone.success,
      icon: 'checkmark.circle',
    );
    return true;
  }

  /// Assign / move / unassign a PARKED draft's table (loud on conflicts).
  Future<bool> assignDraftTable(String draftId, String? tableId) async {
    try {
      await _bridge.assignDraftTable(id: draftId, tableId: tableId);
    } on MadarError catch (e) {
      showToast(_bridge.humanMessage(e), tone: ChipTone.warning, icon: 'table');
      return false;
    }
    await Future.wait([loadDrafts(), loadFloor()]);
    return true;
  }

  /// Swap whatever sits on two tables (held orders and/or waiter tickets).
  Future<void> swapTables(String tableA, String tableB) async {
    try {
      await _bridge.swapFloorTables(tableA: tableA, tableB: tableB);
      showToast(
        _tr('tables.moved'),
        tone: ChipTone.success,
        icon: 'checkmark.circle',
      );
    } on MadarError catch (e) {
      showToast(
        _bridge.humanMessage(e),
        tone: ChipTone.danger,
        icon: 'xmark.circle',
      );
    }
    await Future.wait([
      loadDrafts(),
      loadFloor(),
      if (state.isWaiter) loadOpenTickets(),
    ]);
  }

  /// Queue a party for a move (a section, or one specific table).
  Future<void> createTransfer({
    required String occupantKind,
    required String occupantId,
    String? targetSectionId,
    String? targetTableId,
    String? note,
  }) async {
    try {
      await _bridge.createTransfer(
        occupantKind: occupantKind,
        occupantId: occupantId,
        targetSectionId: targetSectionId,
        targetTableId: targetTableId,
        note: note,
      );
      showToast(_tr('tables.queued'), tone: ChipTone.success, icon: 'clock');
    } on MadarError catch (e) {
      showToast(_bridge.humanMessage(e), tone: ChipTone.warning, icon: 'clock');
    }
    await loadFloor();
  }

  Future<void> cancelTransfer(String id) async {
    await _quiet(() async {
      await _bridge.cancelTransfer(id: id);
      return true;
    });
    await loadFloor();
  }

  /// Seat a waiting party on [tableId] (must satisfy its wish).
  Future<bool> fulfillTransfer(String id, String tableId) async {
    try {
      await _bridge.fulfillTransfer(id: id, tableId: tableId);
      showToast(
        _tr('tables.moved'),
        tone: ChipTone.success,
        icon: 'checkmark.circle',
      );
    } on MadarError catch (e) {
      showToast(_bridge.humanMessage(e), tone: ChipTone.warning, icon: 'table');
      return false;
    }
    await Future.wait([loadDrafts(), loadFloor()]);
    return true;
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
      state = state.copyWith(activeTicketId: null, cartBookingId: null);
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
        // The booking this order seats, if the waiter tapped "Seat this party".
        bookingId: state.cartBookingId,
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
      // The ticket's table, captured before the board reloads without it.
      final table = state.openTickets
          .where((t) => t.id == ticketId)
          .firstOrNull
          ?.tableId;
      final label = state.floorLayout?.tables
          .where((t) => t.id == table)
          .firstOrNull
          ?.label;
      await _bridge.settleTicket(
        ticketId: ticketId,
        shiftId: shiftId,
        paymentMethodId: paymentMethodId,
        amountTenderedMinor: amountTenderedMinor,
        tipMinor: tipMinor,
        tipPaymentMethodId: tipPaymentMethodId,
      );
      // The party paid and left their plates: the table needs a bus, and the
      // teller — not the app — decides when it is ready for the next party.
      if (table != null) await _busTableLocally(table);
      await loadOpenTickets();
      await loadFloor();
      if (table != null) _askToClear(table, label);
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
      final table = state.openTickets
          .where((t) => t.id == ticketId)
          .firstOrNull
          ?.tableId;
      await _bridge.voidTicket(ticketId: ticketId, reason: reason);
      if (table != null) await _freeTableLocally(table);
      await loadOpenTickets();
      await loadFloor();
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
    // Restore edge with a parked outbox → raise the re-auth prompt (see
    // syncFromStatus — the core suppresses authPaused while offline).
    if (!wasOnline && online && (status?.authPaused ?? false)) {
      ref.read(reauthRequestProvider.notifier).request();
    }
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
    // Connectivity just came back with the outbox parked on an expired
    // bearer — NOW a re-login can actually mint a JWT, so raise the re-auth
    // prompt (the core suppresses `authPaused` while offline by design).
    if (!wasOnline && status.online && status.authPaused) {
      ref.read(reauthRequestProvider.notifier).request();
    }
    if (!wasOnline && status.online && !state.isWaiter) {
      await reconcileShift();
    }
  }

  /// Run a bridge call whose failure the natives swallow (cache reads,
  /// best-effort refreshes) — returns null instead of surfacing the error. A
  /// transport-class failure nudges the connectivity service (one debounced
  /// probe), so offline is noticed here instead of on a blanket timer.
  Future<T?> _quiet<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on MadarError catch (e) {
      ref.read(connectivityRefreshProvider.notifier).reportError(e);
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
