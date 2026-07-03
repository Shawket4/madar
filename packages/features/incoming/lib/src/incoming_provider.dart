/// Incoming state — the Riverpod spine behind `IncomingScreen`: the branch
/// delivery queue with its accepting overrides and lifecycle actions, the
/// settleable open tickets, the shared busy/error pair, and the screen's
/// toast. All business rules (status steps, reject-vs-cancel, finalize
/// replay, settle dedup) live in the CORE; this only sequences bridge
/// calls. Actions that book a real sale on the open shift (finalize,
/// settle) refresh the shell.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The wire statuses the "Active" filter keeps (everything not yet terminal)
/// — the natives' `activeStatusFilter` (AppModel.kt).
const String kActiveDeliveryStatuses =
    'received,confirmed,preparing,ready,out_for_delivery';

/// copyWith sentinel — lets callers CLEAR the nullable fields (`error`,
/// `toast`) by passing an explicit `null`.
const Object _unset = Object();

/// Immutable incoming-screen state: both tab feeds plus everything the
/// boards render.
class IncomingState {
  const IncomingState({
    this.tab,
    this.isBusy = false,
    this.error,
    this.deliveryOrders = const [],
    this.isLoadingDelivery = false,
    this.deliveryActiveOnly = true,
    this.deliverySettings,
    this.openTickets = const [],
    this.toast,
  });

  /// Selected tab (0 = delivery, 1 = tickets). Null until the screen's
  /// first [IncomingNotifier.enter] — the screen falls back to its
  /// `initialTab` param for that pristine first frame.
  final int? tab;

  /// Shared busy flag for the mutation buttons (the natives' `isBusy`).
  final bool isBusy;

  /// Banner text from the last failed bridge call.
  final String? error;

  /// The branch delivery queue (online).
  final List<DeliveryOrderView> deliveryOrders;

  /// True while the delivery list refresh is in flight.
  final bool isLoadingDelivery;

  /// Filter toggle — active lifecycle states only (default) vs everything.
  final bool deliveryActiveOnly;

  /// The branch's delivery accepting settings (per-channel auto/open/closed).
  final DeliverySettingsView? deliverySettings;

  /// The waiter-fired open tickets (the settle tab's feed).
  final List<TicketView> openTickets;

  /// The screen's floating toast, sequence-keyed.
  final ToastData? toast;

  /// Only OPEN/READY tickets can be settled (the natives' filter).
  List<TicketView> get settleableTickets => openTickets
      .where((t) => t.status == 'open' || t.status == 'ready')
      .toList(growable: false);

  /// Copy with the given fields replaced. `null` keeps the current value,
  /// except [error] and [toast] which clear on an explicit `null`.
  IncomingState copyWith({
    int? tab,
    bool? isBusy,
    Object? error = _unset,
    List<DeliveryOrderView>? deliveryOrders,
    bool? isLoadingDelivery,
    bool? deliveryActiveOnly,
    DeliverySettingsView? deliverySettings,
    List<TicketView>? openTickets,
    Object? toast = _unset,
  }) {
    return IncomingState(
      tab: tab ?? this.tab,
      isBusy: isBusy ?? this.isBusy,
      error: identical(error, _unset) ? this.error : error as String?,
      deliveryOrders: deliveryOrders ?? this.deliveryOrders,
      isLoadingDelivery: isLoadingDelivery ?? this.isLoadingDelivery,
      deliveryActiveOnly: deliveryActiveOnly ?? this.deliveryActiveOnly,
      deliverySettings: deliverySettings ?? this.deliverySettings,
      openTickets: openTickets ?? this.openTickets,
      toast: identical(toast, _unset) ? this.toast : toast as ToastData?,
    );
  }
}

/// The incoming controller. All bridge writes flow through here; the
/// widgets only render [IncomingState] and forward taps.
class IncomingNotifier extends Notifier<IncomingState> {
  MadarBridge get _bridge => ref.read(bridgeProvider);

  String _tr(String key) => _bridge.tr(key: key);

  int _toastSeq = 0;

  @override
  IncomingState build() => const IncomingState();

  /// Screen entry: land on [tab], clear stale failures, and load both
  /// feeds so the tab badges populate immediately (each body also reloads
  /// itself on (re)mount + its live tick).
  void enter({required int tab}) {
    state = state.copyWith(tab: tab, error: null);
    unawaited(loadDeliveryOrders());
    unawaited(loadOpenTickets());
  }

  /// Tab tap (0 = delivery, 1 = tickets).
  void setTab(int tab) {
    if (state.tab != tab) state = state.copyWith(tab: tab);
  }

  /// Active/All filter toggle — reloads the queue under the new filter.
  void setDeliveryActiveOnly({required bool activeOnly}) {
    if (state.deliveryActiveOnly == activeOnly) return;
    state = state.copyWith(deliveryActiveOnly: activeOnly);
    unawaited(loadDeliveryOrders());
  }

  // ── delivery queue (online; teller works the live branch queue) ───────────

  /// The branch delivery queue (online). Active-only by default; the
  /// accepting settings ride along quietly (natives' loadDeliveryOrders).
  Future<void> loadDeliveryOrders() async {
    state = state.copyWith(isLoadingDelivery: true);
    try {
      final orders = await _bridge.listDeliveryOrders(
        status: state.deliveryActiveOnly ? kActiveDeliveryStatuses : null,
      );
      state = state.copyWith(
        deliveryOrders: orders,
        isLoadingDelivery: false,
      );
    } on MadarError catch (e) {
      state = state.copyWith(error: _fail(e), isLoadingDelivery: false);
    }
    try {
      final settings = await _bridge.deliverySettings();
      state = state.copyWith(deliverySettings: settings);
    } on MadarError {
      // Best-effort — the natives swallow this refresh.
    }
  }

  /// Cycle a channel's accepting override: auto → open → closed → auto.
  Future<void> cycleAccepting(String channel, String current) async {
    final next = switch (current) {
      'auto' => 'open',
      'open' => 'closed',
      _ => 'auto',
    };
    state = state.copyWith(isBusy: true, error: null);
    try {
      final settings = await _bridge.deliverySetAccepting(
        channel: channel,
        mode: next,
      );
      state = state.copyWith(deliverySettings: settings, isBusy: false);
    } on MadarError catch (e) {
      state = state.copyWith(error: _fail(e), isBusy: false);
    }
  }

  /// Advance one lifecycle step (Confirm → Preparing → … → Delivered).
  Future<void> advanceDelivery(DeliveryOrderView o) async {
    state = state.copyWith(isBusy: true, error: null);
    try {
      await _bridge.deliveryAdvanceStatus(id: o.id, current: o.status);
      await loadDeliveryOrders();
      state = state.copyWith(isBusy: false);
    } on MadarError catch (e) {
      state = state.copyWith(error: _fail(e), isBusy: false);
    }
  }

  /// Add extra prep time (multiples of 5).
  Future<void> addDeliveryPrep(DeliveryOrderView o, {int minutes = 5}) async {
    try {
      await _bridge.deliverySetPrepTime(id: o.id, extraMinutes: minutes);
      await loadDeliveryOrders();
    } on MadarError catch (e) {
      state = state.copyWith(error: _fail(e));
    }
  }

  /// Cancel a delivery order (optionally restocking ingredients).
  Future<bool> cancelDelivery(
    DeliveryOrderView o, {
    required bool restoreInventory,
    String? reason,
  }) async {
    state = state.copyWith(isBusy: true, error: null);
    try {
      await _bridge.deliveryCancel(
        id: o.id,
        reason: reason,
        restoreInventory: restoreInventory,
      );
      await loadDeliveryOrders();
      state = state.copyWith(isBusy: false);
      return true;
    } on MadarError catch (e) {
      state = state.copyWith(error: _fail(e), isBusy: false);
      return false;
    }
  }

  /// Reject a just-received delivery order — a terminal state the core
  /// models distinctly from cancel (refusing incoming work, before any
  /// prep). Reject = cancel a not-yet-accepted (received) order: the
  /// backend's cancel endpoint flips received→rejected (later states→
  /// cancelled). The food isn't made yet, so restore inventory.
  Future<bool> rejectDelivery(DeliveryOrderView o) =>
      cancelDelivery(o, restoreInventory: true);

  /// Finalize into a real sale on the open shift, charged to a payment
  /// method. Surfaces oversold warnings instead of dropping them — replaying
  /// the frozen delivery snapshot into a real sale can oversell stock, and
  /// the teller must SEE that (the natives' finalizeDelivery).
  Future<bool> finalizeDelivery(
    DeliveryOrderView o,
    String paymentMethodId,
  ) async {
    state = state.copyWith(isBusy: true, error: null);
    try {
      final res = await _bridge.deliveryFinalize(
        id: o.id,
        paymentMethodId: paymentMethodId,
      );
      await loadDeliveryOrders();
      final orderRef = res.orderRef == null ? '' : ' · ${res.orderRef}';
      if (res.warnings.isNotEmpty) {
        showToast(
          '${_tr('delivery.finalized')}$orderRef — ${res.warnings.join('; ')}',
          tone: ChipTone.warning,
          icon: 'exclamationmark.triangle',
        );
      } else {
        showToast(
          '${_tr('delivery.finalized')}$orderRef',
          tone: ChipTone.success,
          icon: 'checkmark.circle',
        );
      }
      state = state.copyWith(isBusy: false);
      // A finalized delivery books a real sale on the open shift.
      ref.read(shellProvider.notifier).refresh();
      return true;
    } on MadarError catch (e) {
      state = state.copyWith(error: _fail(e), isBusy: false);
      return false;
    }
  }

  // ── open tickets (the settle tab) ──────────────────────────────────────────

  Future<void> loadOpenTickets() async {
    try {
      final tickets = await _bridge.listOpenTickets();
      state = state.copyWith(openTickets: tickets);
    } on MadarError {
      // Quiet refresh — the natives swallow this (runCatching).
    }
  }

  /// SETTLE a ticket into a paid order on the current open shift — the
  /// natives' settleTicket: requires a shift, books via the core, then
  /// reloads + toasts.
  Future<bool> settleTicket({
    required String ticketId,
    required String paymentMethodId,
    int? amountTenderedMinor,
    int? tipMinor,
    String? tipPaymentMethodId,
  }) async {
    // Quiet lookup (FloorController's pattern) — a thrown MadarError here
    // would otherwise escape into the sheet's unawaited caller with no
    // error set.
    final shift = await _quiet(_bridge.currentShift);
    if (shift == null) {
      state = state.copyWith(error: _tr('waiter.need_shift'));
      return false;
    }
    state = state.copyWith(isBusy: true, error: null);
    try {
      await _bridge.settleTicket(
        ticketId: ticketId,
        shiftId: shift.id,
        paymentMethodId: paymentMethodId,
        amountTenderedMinor: amountTenderedMinor,
        tipMinor: tipMinor,
        tipPaymentMethodId: tipPaymentMethodId,
      );
      await loadOpenTickets();
      showToast(_tr('waiter.settled'), tone: ChipTone.success);
      state = state.copyWith(isBusy: false);
      // A settled ticket books a real sale on the open shift.
      ref.read(shellProvider.notifier).refresh();
      return true;
    } on MadarError catch (e) {
      state = state.copyWith(error: _fail(e), isBusy: false);
      return false;
    }
  }

  // ── toast ──────────────────────────────────────────────────────────────────

  void showToast(
    String text, {
    ChipTone tone = ChipTone.neutral,
    String? icon,
  }) {
    _toastSeq += 1;
    state = state.copyWith(
      toast: ToastData(id: _toastSeq, text: text, tone: tone, icon: icon),
    );
  }

  void dismissToast(int id) {
    if (state.toast?.id != id) return;
    state = state.copyWith(toast: null);
  }

  /// Human message for a failed bridge call; an expired/missing bearer with
  /// a live session additionally raises the app-wide re-auth request.
  String _fail(MadarError e) {
    if (e is MadarError_Unauthenticated && _bridge.currentSession() != null) {
      ref.read(reauthRequestProvider.notifier).request();
    }
    return _bridge.humanMessage(e);
  }

  /// Best-effort bridge read — returns null instead of throwing, so lookups
  /// inside unawaited flows can't escape as unhandled async errors (the same
  /// helper as the floor feature's `_quiet`).
  Future<T?> _quiet<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on MadarError {
      return null;
    }
  }
}

/// The incoming spine — app-lifetime; [IncomingNotifier.enter] resets it
/// per screen entry.
final incomingProvider = NotifierProvider<IncomingNotifier, IncomingState>(
  IncomingNotifier.new,
);
