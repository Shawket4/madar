/// The all-orders search screen's Riverpod state — cross-shift results,
/// filters (date range + status; the teller query stays widget-local in
/// its text field) and load-more pagination. The request-sequence guard is
/// preserved: stale completions bail so a slow response can't clobber a
/// newer query or double-advance the page.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart' show ChipTone, ToastData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// RFC3339 timestamp [days] ago (UTC) — the natives' `isoDaysAgo`.
String _isoDaysAgo(int days) =>
    DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String();

/// Immutable snapshot of the all-orders search screen.
class OrderSearchState {
  /// Creates the (initial) search state.
  const OrderSearchState({
    this.results = const [],
    this.total = 0,
    this.hasMore = false,
    this.searching = false,
    this.status,
    this.days = 7,
    this.toast,
  });

  /// The accumulated result pages.
  final List<OrderSummaryView> results;

  /// The server-side total match count (the header figure).
  final int total;

  /// Another page is available (shows the load-more row).
  final bool hasMore;

  /// A query is in flight.
  final bool searching;

  /// The status filter (null = all).
  final String? status;

  /// The date-range filter in days back (0 = all time).
  final int days;

  /// The screen's transient toast, if any.
  final ToastData? toast;

  static const Object _unset = Object();

  /// Copies with the given fields replaced (`_unset` keeps nullables).
  OrderSearchState copyWith({
    List<OrderSummaryView>? results,
    int? total,
    bool? hasMore,
    bool? searching,
    Object? status = _unset,
    int? days,
    Object? toast = _unset,
  }) {
    return OrderSearchState(
      results: results ?? this.results,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      searching: searching ?? this.searching,
      status: status == _unset ? this.status : status as String?,
      days: days ?? this.days,
      toast: toast == _unset ? this.toast : toast as ToastData?,
    );
  }
}

/// Owns [OrderSearchState]; runs the initial (last-7-days) query on first
/// watch.
class OrderSearchNotifier extends Notifier<OrderSearchState> {
  bool _alive = true;

  /// Request-sequence guard: bumped per [run]; stale completions bail so a
  /// slow response can't clobber a newer query or double-advance [_page].
  int _querySeq = 0;
  int _page = 1;
  int _toastSeq = 0;

  @override
  OrderSearchState build() {
    ref.watch(bridgeProvider);
    _alive = true;
    ref.onDispose(() => _alive = false);
    unawaited(Future.microtask(() => run(reset: true, teller: '')));
    return const OrderSearchState();
  }

  MadarBridge get _bridge => ref.read(bridgeProvider);

  /// Run / page the all-orders search. [reset] starts a fresh query at
  /// page 1; otherwise it appends the next page (load-more). [teller] is
  /// the widget-local teller field's current text.
  Future<void> run({required bool reset, required String teller}) async {
    if (!_alive) return;
    final seq = ++_querySeq;
    if (reset) _page = 1;
    state = state.copyWith(
      results: reset ? const [] : state.results,
      searching: true,
    );
    try {
      final tellerQuery = teller.trim();
      final pg = await _bridge.searchOrders(
        status: state.status,
        tellerName: tellerQuery.isEmpty ? null : tellerQuery,
        from: state.days > 0 ? _isoDaysAgo(state.days) : null,
        page: _page,
      );
      if (seq != _querySeq || !_alive) return;
      _page += 1;
      state = state.copyWith(
        results: reset ? pg.orders : [...state.results, ...pg.orders],
        total: pg.total,
        hasMore: pg.hasMore,
        searching: false,
      );
    } on MadarError catch (e) {
      if (seq != _querySeq || !_alive) return;
      state = state.copyWith(searching: false);
      surfaceError(e);
    }
  }

  /// Date-range chip tap — sets the filter and reruns from page 1.
  void setDays(int days, {required String teller}) {
    state = state.copyWith(days: days);
    unawaited(run(reset: true, teller: teller));
  }

  /// Status chip tap — sets the filter and reruns from page 1.
  void setStatus(String? status, {required String teller}) {
    state = state.copyWith(status: status);
    unawaited(run(reset: true, teller: teller));
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
}

/// The all-orders search screen's state — fresh per visit (auto-dispose).
final NotifierProvider<OrderSearchNotifier, OrderSearchState> searchProvider =
    NotifierProvider.autoDispose<OrderSearchNotifier, OrderSearchState>(
      OrderSearchNotifier.new,
    );
