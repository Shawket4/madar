/// The Orders screen's Riverpod state — one list with two scopes.
///
/// THIS SHIFT is the till's own ledger: `listShiftOrders()` (the synced
/// sales plus the still-queued ones, straight from the local mirror, so it
/// works with no network) with `shiftStats()` for the header's count line.
/// ALL is every shift in the branch: `searchOrders()`, online only, paged
/// 50 at a time by the server. The two share one search box, one chip row
/// and one selection, so a teller who cannot find yesterday's receipt under
/// This shift flips one segment and keeps typing.
///
/// The search and the type chips filter CLIENT-SIDE over the rows in hand —
/// the server search has no number / customer / amount filter, so under All
/// the match runs over the pages loaded so far and "Load more" widens it.
/// The one thing the server IS asked for is the Voided chip, which maps to
/// its `status` filter so paging finds voided sales instead of scanning
/// past them.
///
/// The filtered rows are memoized in one pass — recomputed only by the
/// mutations that change their inputs (rows, search, chip), so a toast or a
/// detail fetch reuses the cached list for free.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart'
    show ChipTone, Money, ToastData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Client-side page under This shift — how many rows paint before "Show
/// more". The full shift stays in memory.
const int kHistoryPageSize = 20;

/// Which shifts the list covers.
enum OrdersScope {
  /// The open shift on this till, from the local mirror. Works offline.
  thisShift,

  /// Every shift in the branch, from the server. Online only.
  all,
}

/// The chip row: the three origins a sale can have, and the one correction
/// the core knows.
///
/// Dine-in used to mean "not delivery", which swept every counter sale in
/// with the tables. The server tells the three apart now — a bill settled
/// from a waiter's ticket is dine-in, anything rung straight through the till
/// is takeaway — and only dine-in carries a service charge, so conflating
/// them hid the difference that decides what a sale was charged.
///
/// Rows rung before September 2026 all say `dine_in`, because `takeaway`
/// could not be expressed; the Dine-in chip therefore still shows old counter
/// sales. That is the recorded history, not a filter bug.
enum OrdersFilter {
  /// Every row.
  all,

  /// Eaten here — settled from a waiter's ticket.
  dineIn,

  /// Rung at the counter and carried out.
  takeaway,

  /// Online (delivery) orders.
  online,

  /// Voided sales, of any origin.
  voided;

  /// Whether [o] passes this chip.
  bool matches(OrderSummaryView o) => switch (this) {
    OrdersFilter.all => true,
    OrdersFilter.dineIn => o.orderType == 'dine_in',
    OrdersFilter.takeaway => o.orderType == 'takeaway',
    OrdersFilter.online => o.orderType == 'delivery',
    OrdersFilter.voided => o.status == 'voided',
  };
}

/// Immutable snapshot of the Orders screen.
class HistoryState {
  /// Creates the (initial) state.
  const HistoryState({
    this.scope = OrdersScope.thisShift,
    this.rows = const [],
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.online = true,
    this.hasShift = false,
    this.stats,
    this.serverTotal = 0,
    this.hasMore = false,
    this.search = '',
    this.filter = OrdersFilter.all,
    this.visibleLimit = kHistoryPageSize,
    this.selectedId,
    this.detail,
    this.receipt,
    this.refunds,
    this.detailLoading = false,
    this.toast,
    this.filtered = const [],
    this.loyaltyOffered = false,
  });

  /// The active scope.
  final OrdersScope scope;

  /// Every row the scope has produced so far (all of the shift, or the
  /// server pages loaded under All).
  final List<OrderSummaryView> rows;

  /// A first load is in flight (skeleton when [rows] is empty).
  final bool loading;

  /// A further server page is in flight (All only).
  final bool loadingMore;

  /// The server's refusal, in the core's words, when a search failed.
  final String? error;

  /// Whether the till could reach the server when All last loaded — drives
  /// the honest notice under All.
  final bool online;

  /// A shift is open — the header names it, or says there is none.
  final bool hasShift;

  /// The branch runs a loyalty programme. False keeps *Add points* off a
  /// sale: in a shop with no programme the sheet has no card to scan, and
  /// offering it reads as a broken button rather than an unsold feature.
  final bool loyaltyOffered;

  /// Count + total for the header under This shift (voids excluded by the
  /// core).
  final ShiftStatsView? stats;

  /// The server's total match count under All.
  final int serverTotal;

  /// The server has a further page (All only).
  final bool hasMore;

  /// The live search query.
  final String search;

  /// The active chip.
  final OrdersFilter filter;

  /// How many filtered rows paint under This shift ("Show more").
  final int visibleLimit;

  /// The sale open beside the list (tablet) or pushed over it (phone).
  final String? selectedId;

  /// The selected sale's fetched lines (null while loading, queued, or
  /// unreachable — the panel falls back to the summary figures).
  final OrderDetailView? detail;

  /// The selected sale's receipt projection — carries what the detail view
  /// does not (service, tip, change) and is what Reprint prints.
  final ReceiptView? receipt;

  /// What has already been given back against [selectedId], and what may
  /// still be. Null while it loads or when nothing could be fetched.
  final OrderRefundsView? refunds;

  /// The detail fetch for [selectedId] is in flight.
  final bool detailLoading;

  /// The screen's transient toast, if any.
  final ToastData? toast;

  // ── Memoized derived state (computed by the notifier, never set raw) ──

  /// [rows] passing the search and the chip, newest first.
  final List<OrderSummaryView> filtered;

  /// The selected row, if it is still in [rows].
  OrderSummaryView? get selected {
    final id = selectedId;
    if (id == null) return null;
    for (final o in rows) {
      if (o.id == id) return o;
    }
    return null;
  }

  static const Object _unset = Object();

  /// Copies with the given fields replaced (`_unset` keeps nullables).
  HistoryState copyWith({
    OrdersScope? scope,
    List<OrderSummaryView>? rows,
    bool? loading,
    bool? loadingMore,
    Object? error = _unset,
    bool? online,
    bool? hasShift,
    Object? stats = _unset,
    int? serverTotal,
    bool? hasMore,
    String? search,
    OrdersFilter? filter,
    int? visibleLimit,
    Object? selectedId = _unset,
    Object? detail = _unset,
    Object? receipt = _unset,
    Object? refunds = _unset,
    bool? detailLoading,
    Object? toast = _unset,
    List<OrderSummaryView>? filtered,
    bool? loyaltyOffered,
  }) {
    return HistoryState(
      scope: scope ?? this.scope,
      rows: rows ?? this.rows,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: error == _unset ? this.error : error as String?,
      online: online ?? this.online,
      hasShift: hasShift ?? this.hasShift,
      loyaltyOffered: loyaltyOffered ?? this.loyaltyOffered,
      stats: stats == _unset ? this.stats : stats as ShiftStatsView?,
      serverTotal: serverTotal ?? this.serverTotal,
      hasMore: hasMore ?? this.hasMore,
      search: search ?? this.search,
      filter: filter ?? this.filter,
      visibleLimit: visibleLimit ?? this.visibleLimit,
      selectedId: selectedId == _unset
          ? this.selectedId
          : selectedId as String?,
      detail: detail == _unset ? this.detail : detail as OrderDetailView?,
      refunds: refunds == _unset ? this.refunds : refunds as OrderRefundsView?,
      receipt: receipt == _unset ? this.receipt : receipt as ReceiptView?,
      detailLoading: detailLoading ?? this.detailLoading,
      toast: toast == _unset ? this.toast : toast as ToastData?,
      filtered: filtered ?? this.filtered,
    );
  }
}

/// Owns [HistoryState]; loads the shift on first watch.
class HistoryNotifier extends Notifier<HistoryState> {
  bool _alive = true;
  int _toastSeq = 0;

  /// Request-sequence guard for the All scope: bumped per query, so a slow
  /// page cannot land over a newer query or double-advance [_page].
  int _querySeq = 0;
  int _page = 1;

  @override
  HistoryState build() {
    ref.localizedBridge;
    _alive = true;
    ref.onDispose(() => _alive = false);
    unawaited(Future.microtask(load));
    unawaited(Future.microtask(_loadProgramme));
    return const HistoryState();
  }

  MadarBridge get _bridge => ref.read(bridgeProvider);

  /// Whether the branch runs a loyalty programme. Cached in the core, so an
  /// offline till still answers; a failure leaves the button hidden rather
  /// than offering a scan that cannot land.
  Future<void> _loadProgramme() async {
    bool offered;
    try {
      offered = (await _bridge.loyaltySettings()).enabled;
    } on MadarError {
      return;
    }
    if (!_alive) return;
    state = state.copyWith(loyaltyOffered: offered);
  }

  /// Load the active scope from scratch.
  Future<void> load() => switch (state.scope) {
    OrdersScope.thisShift => _loadShift(),
    OrdersScope.all => _loadAll(reset: true),
  };

  /// The shift's rows, its stats for the header, and whether a shift is
  /// open — each best-effort, like the natives' loadHistory: a stats call
  /// that fails must not empty a list that loaded.
  Future<void> _loadShift() async {
    if (!_alive) return;
    state = state.copyWith(loading: true, error: null);
    List<OrderSummaryView> rows;
    try {
      rows = await _bridge.listShiftOrders();
    } on MadarError catch (e) {
      rows = const [];
      surfaceError(e);
    }
    ShiftStatsView? stats;
    try {
      stats = await _bridge.shiftStats(orders: rows);
    } on MadarError {
      stats = null;
    }
    var hasShift = false;
    try {
      hasShift = (await _bridge.currentShift())?.isOpen ?? false;
    } on MadarError {
      hasShift = false;
    }
    if (!_alive || state.scope != OrdersScope.thisShift) return;
    state = _derive(
      state.copyWith(
        rows: rows,
        stats: stats,
        hasShift: hasShift,
        loading: false,
      ),
    );
    _keepSelectionHonest();
  }

  /// Every shift, one server page at a time. [reset] starts at page 1;
  /// otherwise the next page is appended. Offline is not an error: the
  /// notice says so and whatever was loaded stays on screen.
  Future<void> _loadAll({required bool reset}) async {
    if (!_alive) return;
    final seq = ++_querySeq;
    if (reset) _page = 1;
    var online = true;
    try {
      online = (await _bridge.syncStatus()).online;
    } on MadarError {
      online = true; // Let the search itself say no, in the core's words.
    }
    if (seq != _querySeq || !_alive) return;
    if (!online) {
      state = _derive(
        state.copyWith(
          online: false,
          loading: false,
          loadingMore: false,
          error: null,
          rows: reset ? const <OrderSummaryView>[] : state.rows,
          hasMore: false,
        ),
      );
      return;
    }
    state = state.copyWith(
      online: true,
      loading: reset,
      loadingMore: !reset,
      error: null,
      rows: reset ? const <OrderSummaryView>[] : state.rows,
    );
    try {
      final pg = await _bridge.searchOrders(
        // The Voided chip is the one filter the server can take; origin and
        // the free-text match stay on this side.
        status: state.filter == OrdersFilter.voided ? 'voided' : null,
        page: _page,
      );
      if (seq != _querySeq || !_alive) return;
      _page += 1;
      state = _derive(
        state.copyWith(
          rows: reset ? pg.orders : [...state.rows, ...pg.orders],
          serverTotal: pg.total,
          hasMore: pg.hasMore,
          loading: false,
          loadingMore: false,
        ),
      );
      _keepSelectionHonest();
    } on MadarError catch (e) {
      if (seq != _querySeq || !_alive) return;
      if (e is MadarError_Unauthenticated &&
          ref.read(shellProvider).session != null) {
        ref.read(reauthRequestProvider.notifier).request();
      }
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        error: _bridge.humanMessage(e),
      );
    }
  }

  /// Segment tap. The selection is dropped: the sale open beside the list
  /// belongs to the list it came from.
  void setScope(OrdersScope scope) {
    if (scope == state.scope) return;
    _querySeq += 1; // Orphan any page still in flight for the old scope.
    state = _derive(
      state.copyWith(
        scope: scope,
        rows: const <OrderSummaryView>[],
        error: null,
        hasMore: false,
        serverTotal: 0,
        visibleLimit: kHistoryPageSize,
        selectedId: null,
        detail: null,
        receipt: null,
        detailLoading: false,
      ),
    );
    unawaited(load());
  }

  /// Live search-query change — re-derives and resets the page.
  void setSearch(String query) {
    state = _derive(
      state.copyWith(search: query, visibleLimit: kHistoryPageSize),
    );
  }

  /// Chip tap. Under All the Voided chip changes the server query, so the
  /// pages are fetched again; every other chip is a local re-derive.
  void setFilter(OrdersFilter filter) {
    if (filter == state.filter) return;
    final serverChanges =
        state.scope == OrdersScope.all &&
        (filter == OrdersFilter.voided || state.filter == OrdersFilter.voided);
    state = _derive(
      state.copyWith(filter: filter, visibleLimit: kHistoryPageSize),
    );
    if (serverChanges) unawaited(_loadAll(reset: true));
  }

  /// "Show more" — one more client page under This shift, the next server
  /// page under All.
  void showMore() {
    switch (state.scope) {
      case OrdersScope.thisShift:
        state = state.copyWith(
          visibleLimit: state.visibleLimit + kHistoryPageSize,
        );
      case OrdersScope.all:
        if (!state.loadingMore && state.hasMore) {
          unawaited(_loadAll(reset: false));
        }
    }
  }

  /// Open a sale. Its lines and its receipt are fetched together — the
  /// receipt is what Reprint prints, and it carries the service charge and
  /// tip the detail view does not — each best-effort and cached by the core
  /// for any order seen online. A queued sale is not on the server yet: the
  /// panel shows its summary figures and nothing is fetched.
  void select(OrderSummaryView order) {
    if (state.selectedId == order.id) return;
    state = state.copyWith(
      selectedId: order.id,
      detail: null,
      receipt: null,
      refunds: null,
      detailLoading: !order.queued,
    );
    if (!order.queued) unawaited(_loadDetail(order.id));
  }

  /// Close the sale panel.
  void clearSelection() {
    state = state.copyWith(
      selectedId: null,
      detail: null,
      receipt: null,
      refunds: null,
      detailLoading: false,
    );
  }

  Future<void> _loadDetail(String id) async {
    final detailF = _bridge
        .orderDetail(orderId: id)
        .then<OrderDetailView?>((d) => d)
        .onError<MadarError>((_, _) => null);
    final receiptF = _bridge
        .orderReceiptView(orderId: id)
        .then<ReceiptView?>((r) => r)
        .onError<MadarError>((_, _) => null);
    // What was already given back, so the panel can say so and the refund
    // sheet can default to the remainder rather than the full total.
    final refundsF = _bridge
        .listOrderRefunds(orderId: id)
        .then<OrderRefundsView?>((r) => r)
        .onError<MadarError>((_, _) => null);
    final detail = await detailF;
    final receipt = await receiptF;
    final refunds = await refundsF;
    if (!_alive || state.selectedId != id) return;
    state = state.copyWith(
      detail: detail,
      receipt: receipt,
      refunds: refunds,
      detailLoading: false,
    );
  }

  /// After a void: the row flips to Voided on the next read, and the sale
  /// stays open so the teller sees it did.
  Future<void> reloadAfterVoid() async {
    final id = state.selectedId;
    await load();
    if (!_alive || id == null || state.selectedId != id) return;
    state = state.copyWith(
      detail: null,
      receipt: null,
      refunds: null,
      detailLoading: true,
    );
    await _loadDetail(id);
  }

  /// A selection that the new rows no longer contain is closed rather than
  /// left pointing at a sale that is not on screen.
  void _keepSelectionHonest() {
    if (state.selectedId != null && state.selected == null) clearSelection();
  }

  /// Raise the screen toast (sequence-paired so repeats still notify).
  void showToast(String text, {required ChipTone tone, String? icon}) {
    _toastSeq += 1;
    state = state.copyWith(
      toast: ToastData(id: _toastSeq, text: text, tone: tone, icon: icon),
    );
  }

  /// Clear the toast if [id] is still the one showing.
  void dismissToast(int id) {
    if (state.toast?.id == id) state = state.copyWith(toast: null);
  }

  /// Surface a bridge failure: human-message danger toast, plus a reauth
  /// request when it's a 401 with a live session (the shared contract).
  void surfaceError(MadarError e) {
    if (e is MadarError_Unauthenticated &&
        ref.read(shellProvider).session != null) {
      ref.read(reauthRequestProvider.notifier).request();
    }
    showToast(
      _bridge.humanMessage(e),
      tone: ChipTone.danger,
      icon: 'xmark.circle',
    );
  }

  // ── Memoized derived state ──────────────────────────────────────────────

  /// One pass over `rows`: the search and the chip, newest first. Called
  /// ONLY by the mutations that change its inputs.
  HistoryState _derive(HistoryState s) {
    final query = s.search.trim();
    final ql = query.toLowerCase();
    // "#1042" and "1042" are the same question.
    final qNumber = ql.startsWith('#') ? ql.substring(1) : ql;
    bool matchesSearch(OrderSummaryView o) {
      if (query.isEmpty) return true;
      if (qNumber.isNotEmpty &&
          (o.orderNumber?.toString().contains(qNumber) ?? false)) {
        return true;
      }
      return (o.customerName?.toLowerCase().contains(ql) ?? false) ||
          (o.tellerName?.toLowerCase().contains(ql) ?? false) ||
          (o.orderRef?.toLowerCase().contains(ql) ?? false) ||
          o.paymentLabel.toLowerCase().contains(ql) ||
          // An amount typed the way it reads on the row: "196" or "196.00".
          Money.format(o.totalMinor).startsWith(ql);
    }

    // The shift mirror and the server both hand rows back newest first;
    // the sort only pins that when a queued sale is appended out of order.
    final filtered = <OrderSummaryView>[
      for (final o in s.rows)
        if (s.filter.matches(o) && matchesSearch(o)) o,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return s.copyWith(filtered: filtered);
  }
}

/// The Orders screen's state — fresh per visit (auto-dispose).
final NotifierProvider<HistoryNotifier, HistoryState> historyProvider =
    NotifierProvider.autoDispose<HistoryNotifier, HistoryState>(
      HistoryNotifier.new,
    );
