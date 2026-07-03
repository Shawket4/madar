/// The history screen's Riverpod state — the current shift's orders plus
/// the filter / sort / expansion UI state. The filtered rows and the 7
/// filter-chip counts are memoized in ONE pass over the shift (the
/// natives' derived-state cache), recomputed only by the mutations that
/// change their inputs, so toast, detail-toggle and 'show more' updates
/// reuse the cached fields for free and `build()` just watches slices.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart' show ChipTone, ToastData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Client-side page size (natives: K_ORDER_PAGE_SIZE).
const int kHistoryPageSize = 20;

/// The five sortable columns. Only `#`/number ascends by default;
/// everything else descends (newest / biggest first).
enum HistorySortCol {
  /// The `#` / order-number column.
  number(defaultAscending: true),

  /// The payment-method column.
  payment(defaultAscending: false),

  /// The rung-at time column.
  time(defaultAscending: false),

  /// The teller column.
  teller(defaultAscending: false),

  /// The order-total column.
  amount(defaultAscending: false)
  ;

  const HistorySortCol({required this.defaultAscending});

  /// The direction a first tap on this column sorts in.
  final bool defaultAscending;
}

/// One sync-status filter axis value.
enum HistorySyncFilter {
  /// Every order.
  all,

  /// On the server and not voided.
  synced,

  /// Still queued locally.
  pending,

  /// Voided.
  voided
  ;

  /// Whether [o] passes this axis value.
  bool matches(OrderSummaryView o) => switch (this) {
    HistorySyncFilter.all => true,
    HistorySyncFilter.synced => !o.queued && o.status != 'voided',
    HistorySyncFilter.pending => o.queued,
    HistorySyncFilter.voided => o.status == 'voided',
  };
}

/// One order-origin filter axis value.
enum HistoryTypeFilter {
  /// Every origin.
  all,

  /// Anything that is not a delivery.
  dineIn,

  /// Delivery orders.
  delivery
  ;

  /// Whether [o] passes this axis value.
  bool matches(OrderSummaryView o) => switch (this) {
    HistoryTypeFilter.all => true,
    HistoryTypeFilter.dineIn => o.orderType != 'delivery',
    HistoryTypeFilter.delivery => o.orderType == 'delivery',
  };
}

/// Immutable snapshot of the history screen.
class HistoryState {
  /// Creates the (initial) history state.
  const HistoryState({
    this.history = const [],
    this.loading = false,
    this.report,
    this.hasShift = false,
    this.detail,
    this.expandedId,
    this.search = '',
    this.sync = HistorySyncFilter.all,
    this.type = HistoryTypeFilter.all,
    this.sortCol = HistorySortCol.number,
    this.sortAscending = false, // # defaults to DESC (newest first).
    this.visibleLimit = kHistoryPageSize,
    this.toast,
    this.filtered = const [],
    this.typeCounts = const {},
    this.syncCounts = const {},
  });

  /// The full shift — synced orders plus the still-queued sales.
  final List<OrderSummaryView> history;

  /// A load is in flight (skeleton when empty, header spinner otherwise).
  final bool loading;

  /// The live Z-report backing the stats strip (best-effort).
  final ShiftReportView? report;

  /// A shift is open — drives the header subtitle.
  final bool hasShift;

  /// The fetched lines for the expanded row (null = none/queued/loading).
  final OrderDetailView? detail;

  /// The expanded row's order id, if any.
  final String? expandedId;

  /// The live search query.
  final String search;

  /// The active sync-status filter.
  final HistorySyncFilter sync;

  /// The active order-origin filter.
  final HistoryTypeFilter type;

  /// The active sort column.
  final HistorySortCol sortCol;

  /// The active sort direction.
  final bool sortAscending;

  /// How many filtered rows paint (client-side "show more").
  final int visibleLimit;

  /// The screen's transient toast, if any.
  final ToastData? toast;

  // ── Memoized derived state (computed by the notifier, never set raw) ──

  /// All rows passing search + both axes (AND), then sorted (memoized).
  final List<OrderSummaryView> filtered;

  /// Chip counts: type axis = search ∩ THIS chip's type rule (the natives').
  final Map<HistoryTypeFilter, int> typeCounts;

  /// Chip counts: sync axis = search ∩ current type ∩ THIS chip's sync rule.
  final Map<HistorySyncFilter, int> syncCounts;

  static const Object _unset = Object();

  /// Copies with the given fields replaced (`_unset` keeps nullables).
  HistoryState copyWith({
    List<OrderSummaryView>? history,
    bool? loading,
    Object? report = _unset,
    bool? hasShift,
    Object? detail = _unset,
    Object? expandedId = _unset,
    String? search,
    HistorySyncFilter? sync,
    HistoryTypeFilter? type,
    HistorySortCol? sortCol,
    bool? sortAscending,
    int? visibleLimit,
    Object? toast = _unset,
    List<OrderSummaryView>? filtered,
    Map<HistoryTypeFilter, int>? typeCounts,
    Map<HistorySyncFilter, int>? syncCounts,
  }) {
    return HistoryState(
      history: history ?? this.history,
      loading: loading ?? this.loading,
      report: report == _unset ? this.report : report as ShiftReportView?,
      hasShift: hasShift ?? this.hasShift,
      detail: detail == _unset ? this.detail : detail as OrderDetailView?,
      expandedId: expandedId == _unset
          ? this.expandedId
          : expandedId as String?,
      search: search ?? this.search,
      sync: sync ?? this.sync,
      type: type ?? this.type,
      sortCol: sortCol ?? this.sortCol,
      sortAscending: sortAscending ?? this.sortAscending,
      visibleLimit: visibleLimit ?? this.visibleLimit,
      toast: toast == _unset ? this.toast : toast as ToastData?,
      filtered: filtered ?? this.filtered,
      typeCounts: typeCounts ?? this.typeCounts,
      syncCounts: syncCounts ?? this.syncCounts,
    );
  }
}

/// Owns [HistoryState]; kicks off the initial load on first watch.
class HistoryNotifier extends Notifier<HistoryState> {
  bool _alive = true;
  int _toastSeq = 0;

  @override
  HistoryState build() {
    ref.watch(bridgeProvider);
    _alive = true;
    ref.onDispose(() => _alive = false);
    unawaited(Future.microtask(load));
    return const HistoryState();
  }

  MadarBridge get _bridge => ref.read(bridgeProvider);

  /// Load the current shift's orders (synced + queued), the live Z-report
  /// for the stats strip, and the shift presence for the subtitle — all
  /// best-effort like the natives' loadHistory.
  Future<void> load() async {
    if (!_alive) return;
    state = state.copyWith(loading: true);
    List<OrderSummaryView> history;
    try {
      history = await _bridge.listShiftOrders();
    } on MadarError {
      history = const [];
    }
    ShiftReportView? report;
    try {
      report = await _bridge.shiftReport();
    } on MadarError {
      report = null;
    }
    var hasShift = false;
    try {
      hasShift = await _bridge.currentShift() != null;
    } on MadarError {
      hasShift = false;
    }
    if (!_alive) return;
    state = _derive(
      state.copyWith(
        history: history,
        report: report,
        hasShift: hasShift,
        loading: false,
      ),
    );
  }

  /// Live search-query change — re-derives and resets the page.
  void setSearch(String query) {
    state = _derive(
      state.copyWith(search: query, visibleLimit: kHistoryPageSize),
    );
  }

  /// Order-origin chip tap — re-derives and resets the page.
  void setType(HistoryTypeFilter filter) {
    state = _derive(
      state.copyWith(type: filter, visibleLimit: kHistoryPageSize),
    );
  }

  /// Sync-status chip tap — re-derives and resets the page.
  void setSync(HistorySyncFilter filter) {
    state = _derive(
      state.copyWith(sync: filter, visibleLimit: kHistoryPageSize),
    );
  }

  /// Column-header tap: same column flips direction, a new column starts
  /// at its default direction. Resets the page.
  void setSort(HistorySortCol col) {
    state = _derive(
      state.copyWith(
        sortCol: col,
        sortAscending: state.sortCol == col
            ? !state.sortAscending
            : col.defaultAscending,
        visibleLimit: kHistoryPageSize,
      ),
    );
  }

  /// Grow the visible window by one client-side page.
  void showMore() {
    state = state.copyWith(visibleLimit: state.visibleLimit + kHistoryPageSize);
  }

  /// Toggle a row's expansion; load its lines when it just opened (queued
  /// orders aren't on the server yet — skip, mirrors `.task(id:)`).
  void toggle(OrderSummaryView order) {
    final opening = state.expandedId != order.id;
    state = state.copyWith(
      expandedId: opening ? order.id : null,
      detail: opening ? null : state.detail,
    );
    if (opening && !order.queued) unawaited(_loadDetail(order.id));
  }

  Future<void> _loadDetail(String id) async {
    OrderDetailView? detail;
    try {
      detail = await _bridge.orderDetail(orderId: id);
    } on MadarError {
      detail = null;
    }
    if (!_alive || state.expandedId != id) return;
    state = state.copyWith(detail: detail);
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

  /// One pass over `history` producing the filtered+sorted rows and all 7
  /// chip counts — called ONLY by the mutations that change its inputs
  /// (search, the two axes, sort, history), so every other state write
  /// reuses the cached fields.
  HistoryState _derive(HistoryState s) {
    final query = s.search;
    final blank = query.trim().isEmpty;
    final ql = query.toLowerCase();
    bool matchesSearch(OrderSummaryView o) {
      if (blank) return true;
      return (o.orderNumber?.toString() ?? '').contains(query) ||
          o.paymentLabel.toLowerCase().contains(ql) ||
          (o.tellerName?.toLowerCase().contains(ql) ?? false) ||
          (o.customerName?.toLowerCase().contains(ql) ?? false);
    }

    int compare(OrderSummaryView a, OrderSummaryView b) {
      final c = switch (s.sortCol) {
        HistorySortCol.number => (a.orderNumber ?? -1).compareTo(
          b.orderNumber ?? -1,
        ),
        HistorySortCol.payment => a.paymentLabel.compareTo(b.paymentLabel),
        HistorySortCol.time => a.createdAt.compareTo(b.createdAt),
        HistorySortCol.teller => (a.tellerName ?? '').compareTo(
          b.tellerName ?? '',
        ),
        HistorySortCol.amount => a.totalMinor.compareTo(b.totalMinor),
      };
      return s.sortAscending ? c : -c;
    }

    final filtered = <OrderSummaryView>[];
    final typeCounts = {for (final f in HistoryTypeFilter.values) f: 0};
    final syncCounts = {for (final f in HistorySyncFilter.values) f: 0};
    for (final o in s.history) {
      if (!matchesSearch(o)) continue;
      for (final f in HistoryTypeFilter.values) {
        if (f.matches(o)) typeCounts[f] = typeCounts[f]! + 1;
      }
      if (!s.type.matches(o)) continue;
      for (final f in HistorySyncFilter.values) {
        if (f.matches(o)) syncCounts[f] = syncCounts[f]! + 1;
      }
      if (s.sync.matches(o)) filtered.add(o);
    }
    filtered.sort(compare);
    return s.copyWith(
      filtered: filtered,
      typeCounts: typeCounts,
      syncCounts: syncCounts,
    );
  }
}

/// The order-history screen's state — fresh per visit (auto-dispose).
final NotifierProvider<HistoryNotifier, HistoryState> historyProvider =
    NotifierProvider.autoDispose<HistoryNotifier, HistoryState>(
      HistoryNotifier.new,
    );
