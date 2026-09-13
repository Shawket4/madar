/// The Orders screen's Riverpod state — one list with two scopes.
///
/// THIS TILL is the till's own ledger: `listTillOrders()` (the synced
/// sales plus the still-queued ones, straight from the local mirror, so it
/// works with no network) with `tillStats()` for the header's count line.
/// ALL is every till in the branch: `searchOrders()`, online only, paged
/// 50 at a time by the server. The two share one search box, one chip row
/// and one selection, so a teller who cannot find yesterday's receipt under
/// This till flips one segment and keeps typing.
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

/// How many further server pages a search under All fetches on its own
/// looking for a match before it stops and leaves "Load more" to the teller.
const int kSearchAutoPages = 5;

/// Client-side page under This till — how many rows paint before "Show
/// more". The full till stays in memory.
const int kHistoryPageSize = 20;

/// Which tills the list covers.
enum OrdersScope {
  /// The open till on this till, from the local mirror. Works offline.
  thisTill,

  /// Every till in the branch, from the server. Online only.
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
    this.scope = OrdersScope.thisTill,
    this.rows = const [],
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.online = true,
    this.hasTill = false,
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

  /// Every row the scope has produced so far (all of the till, or the
  /// server pages loaded under All).
  final List<OrderSummaryView> rows;

  /// A first load is in flight (skeleton when [rows] is empty).
  final bool loading;

  /// A further server page is in flight (All only).
  final bool loadingMore;

  /// The server's refusal, in the core's words, when a search failed.
  final UiText? error;

  /// Whether the till could reach the server when All last loaded — drives
  /// the honest notice under All.
  final bool online;

  /// A till is open — the header names it, or says there is none.
  final bool hasTill;

  /// The branch runs a loyalty programme. False keeps *Add points* off a
  /// sale: in a shop with no programme the sheet has no card to scan, and
  /// offering it reads as a broken button rather than an unsold feature.
  final bool loyaltyOffered;

  /// Count + total for the header under This till (voids excluded by the
  /// core).
  final TillStatsView? stats;

  /// The server's total match count under All.
  final int serverTotal;

  /// The server has a further page (All only).
  final bool hasMore;

  /// The live search query.
  final String search;

  /// The active chip.
  final OrdersFilter filter;

  /// How many filtered rows paint under This till ("Show more").
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
    bool? hasTill,
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
      error: error == _unset ? this.error : error as UiText?,
      online: online ?? this.online,
      hasTill: hasTill ?? this.hasTill,
      loyaltyOffered: loyaltyOffered ?? this.loyaltyOffered,
      stats: stats == _unset ? this.stats : stats as TillStatsView?,
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

/// Owns [HistoryState]; loads the till on first watch.
class HistoryNotifier extends Notifier<HistoryState> {
  bool _alive = true;
  int _toastSeq = 0;

  /// Request-sequence guard for the All scope: bumped per query, so a slow
  /// page cannot land over a newer query or double-advance [_page].
  int _querySeq = 0;
  int _page = 1;

  @override
  HistoryState build() {
    ref
      ..localizedBridge
      // A sale, a refund, a void or a settled bill moves this till's list
      // without anybody touching the screen; re-read quietly so the list is
      // never the one from when it was opened.
      ..listen(drawerTickProvider, (_, _) => _refreshQuietly())
      ..listen(ticketTickProvider, (_, _) => _refreshQuietly())
      ..listen(connectivityPulseProvider, (_, _) => _refreshQuietly());
    _alive = true;
    ref.onDispose(() => _alive = false);
    unawaited(Future.microtask(load));
    unawaited(Future.microtask(_loadProgramme));
    // Loading from the first frame: "No till open" must not flash before
    // the till has been asked about.
    return const HistoryState(loading: true);
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

  /// A background re-read: only the This till ledger (All is paged by
  /// hand, and re-fetching it would throw away the pages loaded so far).
  void _refreshQuietly() {
    if (!_alive || state.scope != OrdersScope.thisTill || state.loading) {
      return;
    }
    unawaited(_loadTill());
  }

  /// Load the active scope from scratch.
  Future<void> load() => switch (state.scope) {
    OrdersScope.thisTill => _loadTill(),
    OrdersScope.all => _loadAll(reset: true),
  };

  /// The till's rows, its stats for the header, and whether a till is
  /// open — each best-effort, like the natives' loadHistory: a stats call
  /// that fails must not empty a list that loaded.
  ///
  /// No open till is a STATE, not a failure: the list says so and offers
  /// All, instead of asking the core for a till that is not there and
  /// raising a red toast on every visit. A list that cannot be read is an
  /// error with a retry, never an empty till.
  Future<void> _loadTill() async {
    if (!_alive) return;
    state = state.copyWith(loading: true, error: null);
    var hasTill = false;
    try {
      hasTill = (await _bridge.currentTill())?.isOpen ?? false;
    } on MadarError {
      hasTill = false;
    }
    if (!_alive || state.scope != OrdersScope.thisTill) return;
    if (!hasTill) {
      state = _derive(
        state.copyWith(
          rows: const <OrderSummaryView>[],
          stats: null,
          hasTill: false,
          loading: false,
        ),
      );
      _keepSelectionHonest();
      return;
    }
    List<OrderSummaryView> rows;
    try {
      rows = await _bridge.listTillOrders();
    } on MadarError catch (e) {
      if (!_alive || state.scope != OrdersScope.thisTill) return;
      if (e is MadarError_Unauthenticated &&
          ref.read(shellProvider).session != null) {
        ref.read(reauthRequestProvider.notifier).request();
      }
      state = state.copyWith(
        loading: false,
        hasTill: true,
        error: UiText.error(e),
      );
      return;
    }
    TillStatsView? stats;
    try {
      stats = await _bridge.tillStats(orders: rows);
    } on MadarError {
      stats = null;
    }
    if (!_alive || state.scope != OrdersScope.thisTill) return;
    state = _derive(
      state.copyWith(rows: rows, stats: stats, hasTill: true, loading: false),
    );
    _keepSelectionHonest();
  }

  /// Every till, one server page at a time. [reset] starts at page 1;
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
      _seekMatch();
    } on MadarError catch (e) {
      if (seq != _querySeq || !_alive) return;
      if (e is MadarError_Unauthenticated &&
          ref.read(shellProvider).session != null) {
        ref.read(reauthRequestProvider.notifier).request();
      }
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        error: UiText.error(e),
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
    _autoPages = 0;
    state = _derive(
      state.copyWith(search: query, visibleLimit: kHistoryPageSize),
    );
    _seekMatch();
  }

  /// Pages fetched on their own for the current query.
  int _autoPages = 0;

  /// The server cannot search by number, customer or amount, so under All a
  /// query with no match in the loaded pages keeps fetching — a few pages,
  /// then "Load more" is the teller's. It used to stop at the first page and
  /// say "No match" for a sale one page further back.
  void _seekMatch() {
    if (state.scope != OrdersScope.all ||
        state.search.trim().isEmpty ||
        state.filtered.isNotEmpty ||
        !state.hasMore ||
        state.loading ||
        state.loadingMore ||
        _autoPages >= kSearchAutoPages) {
      return;
    }
    _autoPages += 1;
    unawaited(_loadAll(reset: false));
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

  /// "Show more" — one more client page under This till, the next server
  /// page under All.
  void showMore() {
    switch (state.scope) {
      case OrdersScope.thisTill:
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
          o.displayNumber.toLowerCase().contains(qNumber.toLowerCase())) {
        return true;
      }
      return (o.customerName?.toLowerCase().contains(ql) ?? false) ||
          (o.tellerName?.toLowerCase().contains(ql) ?? false) ||
          (o.orderRef?.toLowerCase().contains(ql) ?? false) ||
          o.paymentLabel.toLowerCase().contains(ql) ||
          // An amount typed the way it reads on the row: "196" or "196.00".
          Money.format(o.totalMinor).startsWith(ql);
    }

    // The till mirror and the server both hand rows back newest first;
    // the sort only pins that when a queued sale is appended out of order.
    // By the INSTANT, not the string: RFC 3339 with different offsets does
    // not sort as text. Ties keep their arrival order (List.sort is not
    // stable), so equal times never swap rows between reloads.
    final indexed =
        <(int, DateTime?, OrderSummaryView)>[
          for (final (i, o) in s.rows.indexed)
            if (s.filter.matches(o) && matchesSearch(o))
              (i, DateTime.tryParse(o.createdAt), o),
        ]..sort((a, b) {
          final ta = a.$2;
          final tb = b.$2;
          if (ta != null && tb != null) {
            final c = tb.compareTo(ta);
            if (c != 0) return c;
          }
          return a.$1.compareTo(b.$1);
        });
    return s.copyWith(filtered: [for (final e in indexed) e.$3]);
  }
}

/// The Orders screen's state — fresh per visit (auto-dispose).
final NotifierProvider<HistoryNotifier, HistoryState> historyProvider =
    NotifierProvider.autoDispose<HistoryNotifier, HistoryState>(
      HistoryNotifier.new,
    );
