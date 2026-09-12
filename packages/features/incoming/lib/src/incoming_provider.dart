/// Queue state — the Riverpod spine behind `QueueScreen`: the bills waiting
/// to be charged, the branch's live online orders with their accepting
/// overrides, and the per-card lifecycle actions. All business rules
/// (status steps, reject-vs-cancel, finalize replay, settle dedup) live in
/// the CORE; this only sequences bridge calls and keeps the screen honest
/// about what it could not reach. Actions that book a real sale on the open
/// shift (finalize, settle) refresh the shell.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_incoming/src/queue_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The wire statuses the Queue keeps — everything not yet terminal. Finished
/// orders belong to history, not an inbox.
const String kActiveDeliveryStatuses =
    'received,confirmed,preparing,ready,out_for_delivery';

/// The Ready-in chips, as offsets on the branch's base prep time. The wire
/// takes a non-negative multiple of 5, so nothing sits below the base; the
/// base itself is preselected so Accept is one tap.
const List<int> kPrepOffsets = [0, 10, 25, 40];

/// The two segments the till can back today. Kitchen (routing mode `till`)
/// stays out until the bridge can read the routing mode — shown ungated it
/// would let a till bump lines behind a KDS.
/// The Queue's segments. `kitchen` only exists when the branch routes fired
/// rounds to the TILL (mode `till` or `both`) — see [tillShowsKitchen]. In
/// `kds` mode the kitchen owns its board and the counter must not bump
/// behind it, so the segment is not offered at all.
enum QueueSegment { bills, online, kitchen }

/// copyWith sentinel — lets callers CLEAR the nullable fields (`error`,
/// `toast`) by passing an explicit `null`.
const Object _unset = Object();

/// Immutable Queue state: both feeds plus everything the segments render.
class IncomingState {
  const IncomingState({
    this.segment,
    this.isBusy = false,
    this.busyOrderIds = const {},
    this.error,
    this.deliveryOrders = const [],
    this.isLoadingDelivery = false,
    this.onlineStale = false,
    this.deliverySettings,
    this.notices = const {},
    this.openTickets = const [],
    this.tableLabels = const {},
    this.hasFloor = false,
    this.shiftOpen,
    this.toast,
  });

  /// Selected segment. Null until the screen's first [IncomingNotifier.enter]
  /// — the screen falls back to its `initialSegment` for that first frame.
  final QueueSegment? segment;

  /// Busy flag for the sheet confirms (decline, cancel, charge).
  final bool isBusy;

  /// Orders with a lifecycle call in flight — the card's own button spins,
  /// the rest of the board stays live.
  final Set<String> busyOrderIds;

  /// Banner text from the last failed bridge call.
  final String? error;

  /// The branch's live online orders (online-only read).
  final List<DeliveryOrderView> deliveryOrders;

  /// True while the online list refresh is in flight.
  final bool isLoadingDelivery;

  /// The last online refresh could not reach the server: [deliveryOrders] is
  /// the last list we had, and the segment says so.
  final bool onlineStale;

  /// The branch's delivery accepting settings + base prep time (online-only).
  final DeliverySettingsView? deliverySettings;

  /// One-line notices pinned to a card by order id — the server's sentence
  /// when an order changed under the teller (409) or a follow-up call failed
  /// after the main one landed.
  final Map<String, String> notices;

  /// The waiter-fired open tickets (the Bills segment's feed).
  final List<TicketView> openTickets;

  /// Table id → label, from the floor mirror, so a bill can say "T3".
  final Map<String, String> tableLabels;

  /// The branch has an authored floor (tables mirrored).
  final bool hasFloor;

  /// Whether this till has an open shift; null until read. Charge needs one.
  final bool? shiftOpen;

  /// The screen's floating toast, sequence-keyed.
  final ToastData? toast;

  /// Bills a teller can charge: open/ready, kitchen-ready first, then the
  /// oldest first (the ones a party has waited longest on).
  List<TicketView> get settleableTickets {
    return openTickets
        .where((t) => t.status == 'open' || t.status == 'ready')
        .toList()
      ..sort((a, b) {
        final ra = a.status == 'ready' ? 0 : 1;
        final rb = b.status == 'ready' ? 0 : 1;
        if (ra != rb) return ra - rb;
        return a.openedAt.compareTo(b.openedAt);
      });
  }

  /// Bills whose kitchen work is done.
  int get billsReadyCount =>
      openTickets.where((t) => t.status == 'ready').length;

  /// Online orders nobody has accepted yet.
  int get onlineNewCount =>
      deliveryOrders.where((o) => o.status == 'received').length;

  /// The tab badge: what actually needs a human — new online orders plus
  /// bills ready to charge. A bill still cooking is not a number to nag with.
  int get queueBadge => billsReadyCount + onlineNewCount;

  /// The Ready-in choices, in minutes, on the branch's base. Null while the
  /// base is unknown (settings not yet read): a chip whose minutes we cannot
  /// name is not offered.
  List<int>? get prepChoices {
    final base = deliverySettings?.prepTimeMinutes;
    if (base == null) return null;
    return [for (final o in kPrepOffsets) base + o];
  }

  /// At least one delivery channel is enabled — otherwise there is nothing
  /// to accept from and the Accepting row is noise.
  bool get anyChannelEnabled =>
      (deliverySettings?.inMallEnabled ?? false) ||
      (deliverySettings?.outsideEnabled ?? false);

  /// Copy with the given fields replaced. `null` keeps the current value,
  /// except [error] and [toast] which clear on an explicit `null`.
  IncomingState copyWith({
    QueueSegment? segment,
    bool? isBusy,
    Set<String>? busyOrderIds,
    Object? error = _unset,
    List<DeliveryOrderView>? deliveryOrders,
    bool? isLoadingDelivery,
    bool? onlineStale,
    DeliverySettingsView? deliverySettings,
    Map<String, String>? notices,
    List<TicketView>? openTickets,
    Map<String, String>? tableLabels,
    bool? hasFloor,
    bool? shiftOpen,
    Object? toast = _unset,
  }) {
    return IncomingState(
      segment: segment ?? this.segment,
      isBusy: isBusy ?? this.isBusy,
      busyOrderIds: busyOrderIds ?? this.busyOrderIds,
      error: identical(error, _unset) ? this.error : error as String?,
      deliveryOrders: deliveryOrders ?? this.deliveryOrders,
      isLoadingDelivery: isLoadingDelivery ?? this.isLoadingDelivery,
      onlineStale: onlineStale ?? this.onlineStale,
      deliverySettings: deliverySettings ?? this.deliverySettings,
      notices: notices ?? this.notices,
      openTickets: openTickets ?? this.openTickets,
      tableLabels: tableLabels ?? this.tableLabels,
      hasFloor: hasFloor ?? this.hasFloor,
      shiftOpen: shiftOpen ?? this.shiftOpen,
      toast: identical(toast, _unset) ? this.toast : toast as ToastData?,
    );
  }
}

/// The Queue controller. All bridge writes flow through here; the widgets
/// only render [IncomingState] and forward taps.
class IncomingNotifier extends Notifier<IncomingState> {
  MadarBridge get _bridge => ref.read(bridgeProvider);

  String _tr(String key) => _bridge.tr(key: key);

  int _toastSeq = 0;

  @override
  IncomingState build() => const IncomingState();

  /// Screen entry: land on [segment], clear stale failures, and load every
  /// feed so the segment counts populate immediately (each segment also
  /// reloads on its live tick).
  void enter({required QueueSegment segment}) {
    state = state.copyWith(segment: segment, error: null);
    unawaited(loadDeliveryOrders());
    unawaited(loadOpenTickets());
    unawaited(loadShift());
    unawaited(loadFloorLabels());
  }

  void setSegment(QueueSegment segment) {
    if (state.segment != segment) state = state.copyWith(segment: segment);
  }

  // ── online orders (online-only; the teller works the live branch queue) ──

  /// The branch's active online orders. Unreachable → keep the last list and
  /// mark it stale; the segment says so instead of going blank. The accepting
  /// settings ride along quietly.
  Future<void> loadDeliveryOrders() async {
    state = state.copyWith(isLoadingDelivery: true);
    try {
      final orders = await _bridge.listDeliveryOrders(
        status: kActiveDeliveryStatuses,
      );
      state = state.copyWith(
        deliveryOrders: orders,
        isLoadingDelivery: false,
        onlineStale: false,
        // A card that left the list takes its notice with it.
        notices: {
          for (final e in state.notices.entries)
            if (orders.any((o) => o.id == e.key)) e.key: e.value,
        },
      );
    } on MadarError catch (e) {
      final transport = isTransportError(e);
      state = state.copyWith(
        isLoadingDelivery: false,
        onlineStale: transport,
        error: transport ? null : _fail(e),
      );
      if (transport) {
        ref.read(connectivityRefreshProvider.notifier).reportError(e);
      }
    }
    try {
      final settings = await _bridge.deliverySettings();
      state = state.copyWith(deliverySettings: settings);
    } on MadarError {
      // Best-effort — the list is the thing; the chips wait for the next pull.
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

  /// ACCEPT a new order with its ready-in time in one act: the wire's
  /// received → confirmed step, then the extra prep on top of the branch's
  /// base (skipped when the chip IS the base — extra 0 is nothing to say).
  /// If the prep call fails after the accept landed, the order stays
  /// accepted — there is no un-accept — and the card carries the reason.
  Future<void> acceptDelivery(
    DeliveryOrderView o, {
    int? readyInMinutes,
  }) async {
    _setBusy(o.id, busy: true);
    try {
      var updated = await _bridge.deliveryAdvanceStatus(
        id: o.id,
        current: o.status,
      );
      final base = state.deliverySettings?.prepTimeMinutes;
      final extra = (readyInMinutes != null && base != null)
          ? readyInMinutes - base
          : 0;
      if (extra > 0) {
        try {
          updated = await _bridge.deliverySetPrepTime(
            id: o.id,
            extraMinutes: extra,
          );
        } on MadarError catch (e) {
          _notice(o.id, _fail(e));
        }
      }
      _replace(updated);
      showToast(
        '${_bridge.trOr(QueueKeys.accepted)}${_refSuffix(updated)}',
        tone: ChipTone.success,
        icon: 'checkmark.circle',
      );
    } on MadarError catch (e) {
      if (!await _applyConflict(o, e)) state = state.copyWith(error: _fail(e));
    } finally {
      _setBusy(o.id, busy: false);
    }
  }

  /// DECLINE a new order. The server's cancel-from-received flips it to
  /// `rejected`; the food was never made, so stock goes back. A reason is
  /// required by the sheet, not the wire — a refusal without a why is the
  /// kind of thing the owner asks about the next morning.
  Future<bool> declineDelivery(DeliveryOrderView o, {required String reason}) {
    return _cancel(
      o,
      reason: reason,
      restoreInventory: true,
      toast: _bridge.trOr(QueueKeys.declined),
    );
  }

  /// Advance one lifecycle step (confirmed → preparing → ready → out).
  Future<void> advanceDelivery(DeliveryOrderView o) async {
    _setBusy(o.id, busy: true);
    try {
      _replace(
        await _bridge.deliveryAdvanceStatus(id: o.id, current: o.status),
      );
    } on MadarError catch (e) {
      if (!await _applyConflict(o, e)) state = state.copyWith(error: _fail(e));
    } finally {
      _setBusy(o.id, busy: false);
    }
  }

  /// Cancel a live order later in its life (the ⋯ menu), optionally putting
  /// ingredients back. `restoreInventory = false` = the food is made and
  /// wasted; the core deducts the frozen plan and logs the waste.
  Future<bool> cancelDelivery(
    DeliveryOrderView o, {
    required bool restoreInventory,
    String? reason,
  }) => _cancel(o, reason: reason, restoreInventory: restoreInventory);

  Future<bool> _cancel(
    DeliveryOrderView o, {
    required bool restoreInventory,
    String? reason,
    String? toast,
  }) async {
    state = state.copyWith(isBusy: true, error: null);
    try {
      final updated = await _bridge.deliveryCancel(
        id: o.id,
        reason: reason,
        restoreInventory: restoreInventory,
      );
      _replace(updated);
      if (toast != null) {
        showToast('$toast${_refSuffix(updated)}', icon: 'xmark.circle');
      }
      state = state.copyWith(isBusy: false);
      return true;
    } on MadarError catch (e) {
      if (await _applyConflict(o, e)) {
        state = state.copyWith(isBusy: false);
        return true;
      }
      state = state.copyWith(error: _fail(e), isBusy: false);
      return false;
    }
  }

  /// CHARGE an online order: finalize it into a real sale on the open shift
  /// against one payment method (all the wire takes). Oversold warnings
  /// surface instead of being dropped — replaying the frozen snapshot can
  /// oversell stock, and the teller must SEE that.
  Future<DeliveryFinalizeView?> finalizeDelivery(
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
      // A finalized order books a real sale on the open shift.
      ref.read(shellProvider.notifier).refresh();
      return res;
    } on MadarError catch (e) {
      if (await _applyConflict(o, e)) {
        state = state.copyWith(isBusy: false);
        return null;
      }
      state = state.copyWith(error: _fail(e), isBusy: false);
      return null;
    }
  }

  /// A card whose status changed under the teller (the server's 409) flips
  /// to its new state with the server's sentence as a one-line notice — no
  /// dialog. Returns true when [e] was such a race and has been applied.
  Future<bool> _applyConflict(DeliveryOrderView o, MadarError e) async {
    if (e is! MadarError_Server || e.status != 409) return false;
    _notice(o.id, _bridge.humanMessage(e));
    try {
      _replace(await _bridge.deliveryOrderDetail(id: o.id));
    } on MadarError {
      // Could not re-read the one card — refresh the board instead.
      await loadDeliveryOrders();
    }
    return true;
  }

  /// Swap an order in place; a terminal one leaves the board, and takes its
  /// notice with it (there is no card left to pin it to).
  void _replace(DeliveryOrderView updated) {
    final orders = [
      for (final o in state.deliveryOrders)
        if (o.id != updated.id) o else if (!updated.isTerminal) updated,
    ];
    if (!state.deliveryOrders.any((o) => o.id == updated.id) &&
        !updated.isTerminal) {
      orders.add(updated);
    }
    final notices = updated.isTerminal
        ? ({...state.notices}..remove(updated.id))
        : null;
    state = state.copyWith(deliveryOrders: orders, notices: notices);
  }

  void _notice(String orderId, String text) =>
      state = state.copyWith(notices: {...state.notices, orderId: text});

  /// Dismiss a card's notice.
  void clearNotice(String orderId) =>
      state = state.copyWith(notices: {...state.notices}..remove(orderId));

  void _setBusy(String orderId, {required bool busy}) {
    final ids = {...state.busyOrderIds};
    if (busy) {
      ids.add(orderId);
    } else {
      ids.remove(orderId);
    }
    state = state.copyWith(busyOrderIds: ids, error: busy ? null : state.error);
  }

  String _refSuffix(DeliveryOrderView o) =>
      o.orderRef == null ? '' : ' · ${o.orderRef}';

  // ── bills (the settle segment) ───────────────────────────────────────────

  Future<void> loadOpenTickets() async {
    try {
      final tickets = await _bridge.listOpenTickets();
      state = state.copyWith(openTickets: tickets);
    } on MadarError {
      // Quiet refresh — the cached list stands until the next tick.
    }
  }

  /// Whether Charge can work at all: settle books onto THIS till's shift.
  Future<void> loadShift() async {
    final shift = await _quiet(_bridge.currentShift);
    state = state.copyWith(shiftOpen: shift?.isOpen ?? false);
  }

  /// Table id → label from the floor mirror, so a bill row reads "T3" and a
  /// floorless shop is known to be one (its rows then lead with the guest).
  Future<void> loadFloorLabels() async {
    final layout = await _quiet(_bridge.floorLayout);
    if (layout == null) return;
    state = state.copyWith(
      tableLabels: {for (final t in layout.tables) t.id: t.label},
      hasFloor: layout.tables.isNotEmpty,
    );
  }

  /// CHARGE a bill: settle it into a paid order on the current open shift.
  /// Requires a shift, books via the core, then reloads + toasts.
  Future<bool> settleTicket({
    required String ticketId,
    required String paymentMethodId,
    int? amountTenderedMinor,
    int? tipMinor,
    String? tipPaymentMethodId,
  }) async {
    // Quiet lookup — a thrown MadarError here would otherwise escape into the
    // sheet's unawaited caller with no error set.
    final shift = await _quiet(_bridge.currentShift);
    if (shift == null || !shift.isOpen) {
      state = state.copyWith(
        error: _bridge.trOr(QueueKeys.needShift),
        shiftOpen: false,
      );
      return false;
    }
    state = state.copyWith(isBusy: true, error: null);
    try {
      await _bridge.settleTicket(
        ticketId: ticketId,
        shiftId: shift.id,
        paymentMethodId: paymentMethodId,
        // Rewards ride with the bill's own Charge (the Bill screen); the
        // Queue's row Charge is the quick path and carries none.
        loyaltyRedemptions: const [],
        // Settled from the queue with one method; no tender screen, no legs.
        splits: const [],
        amountTenderedMinor: amountTenderedMinor,
        tipMinor: tipMinor,
        tipPaymentMethodId: tipPaymentMethodId,
      );
      await loadOpenTickets();
      showToast(_tr('waiter.settled'), tone: ChipTone.success);
      state = state.copyWith(isBusy: false);
      // A settled bill books a real sale on the open shift.
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
  /// inside unawaited flows can't escape as unhandled async errors. A
  /// transport-class failure nudges the connectivity service (one probe).
  Future<T?> _quiet<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on MadarError catch (e) {
      ref.read(connectivityRefreshProvider.notifier).reportError(e);
      return null;
    }
  }
}

/// The Queue spine — app-lifetime; [IncomingNotifier.enter] resets it per
/// screen entry.
final incomingProvider = NotifierProvider<IncomingNotifier, IncomingState>(
  IncomingNotifier.new,
);
