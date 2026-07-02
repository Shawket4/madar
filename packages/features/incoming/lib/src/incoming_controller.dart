import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The wire statuses the "Active" filter keeps (everything not yet terminal)
/// — the natives' `activeStatusFilter` (AppModel.kt).
const String kActiveDeliveryStatuses =
    'received,confirmed,preparing,ready,out_for_delivery';

/// Screen-local mirror of the natives' AppModel delivery + open-tickets
/// slices: the branch delivery queue with its accepting overrides and
/// lifecycle actions, and the settleable open tickets. All business rules
/// (status steps, reject-vs-cancel, finalize replay, settle dedup) live in
/// the core; this only sequences bridge calls and notifies the widgets.
class IncomingController extends ChangeNotifier {
  IncomingController({required this.core, required this.onStateChanged});

  final MadarCore core;

  /// Shell callback — fired after a bridge call that can move `app_route()`
  /// / the shift stats (a finalized delivery or a settled ticket books a
  /// real sale on the open shift).
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

  /// Shared busy flag for the mutation buttons (the natives' `isBusy`).
  bool isBusy = false;
  String? error;

  // ── delivery queue (online; teller works the live branch queue) ───────────
  List<DeliveryOrderView> deliveryOrders = const [];
  bool isLoadingDelivery = false;

  /// Filter toggle — active lifecycle states only (default) vs everything.
  bool deliveryActiveOnly = true;

  /// The branch's delivery accepting settings (per-channel auto/open/closed).
  DeliverySettingsView? deliverySettings;

  /// The branch delivery queue (online). Active-only by default; the
  /// accepting settings ride along quietly (natives' loadDeliveryOrders).
  Future<void> loadDeliveryOrders() async {
    isLoadingDelivery = true;
    _notify();
    try {
      deliveryOrders = await bridge.listDeliveryOrders(
        status: deliveryActiveOnly ? kActiveDeliveryStatuses : null,
      );
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
    } finally {
      isLoadingDelivery = false;
    }
    try {
      deliverySettings = await bridge.deliverySettings();
    } on MadarError {
      // Best-effort — the natives swallow this refresh.
    }
    _notify();
  }

  /// Cycle a channel's accepting override: auto → open → closed → auto.
  Future<void> cycleAccepting(String channel, String current) async {
    final next = switch (current) {
      'auto' => 'open',
      'open' => 'closed',
      _ => 'auto',
    };
    isBusy = true;
    error = null;
    _notify();
    try {
      deliverySettings = await bridge.deliverySetAccepting(
        channel: channel,
        mode: next,
      );
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
    } finally {
      isBusy = false;
      _notify();
    }
  }

  /// Advance one lifecycle step (Confirm → Preparing → … → Delivered).
  Future<void> advanceDelivery(DeliveryOrderView o) async {
    isBusy = true;
    error = null;
    _notify();
    try {
      await bridge.deliveryAdvanceStatus(id: o.id, current: o.status);
      await loadDeliveryOrders();
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
    } finally {
      isBusy = false;
      _notify();
    }
  }

  /// Add extra prep time (multiples of 5).
  Future<void> addDeliveryPrep(DeliveryOrderView o, {int minutes = 5}) async {
    try {
      await bridge.deliverySetPrepTime(id: o.id, extraMinutes: minutes);
      await loadDeliveryOrders();
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
      _notify();
    }
  }

  /// Cancel a delivery order (optionally restocking ingredients).
  Future<bool> cancelDelivery(
    DeliveryOrderView o, {
    required bool restoreInventory,
    String? reason,
  }) async {
    isBusy = true;
    error = null;
    _notify();
    try {
      await bridge.deliveryCancel(
        id: o.id,
        reason: reason,
        restoreInventory: restoreInventory,
      );
      await loadDeliveryOrders();
      return true;
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
      return false;
    } finally {
      isBusy = false;
      _notify();
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
    isBusy = true;
    error = null;
    _notify();
    try {
      final res = await bridge.deliveryFinalize(
        id: o.id,
        paymentMethodId: paymentMethodId,
      );
      await loadDeliveryOrders();
      final ref = res.orderRef == null ? '' : ' · ${res.orderRef}';
      if (res.warnings.isNotEmpty) {
        showToast(
          '${tr('delivery.finalized')}$ref — ${res.warnings.join('; ')}',
          tone: ChipTone.warning,
          icon: 'exclamationmark.triangle',
        );
      } else {
        showToast(
          '${tr('delivery.finalized')}$ref',
          tone: ChipTone.success,
          icon: 'checkmark.circle',
        );
      }
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

  // ── open tickets (the settle tab) ──────────────────────────────────────────
  List<TicketView> openTickets = const [];

  /// Only OPEN/READY tickets can be settled (the natives' filter).
  List<TicketView> get settleableTickets => openTickets
      .where((t) => t.status == 'open' || t.status == 'ready')
      .toList(growable: false);

  Future<void> loadOpenTickets() async {
    try {
      openTickets = await bridge.listOpenTickets();
      _notify();
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
    // error set and no notify.
    final shift = await _quiet(bridge.currentShift);
    if (shift == null) {
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
        shiftId: shift.id,
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

  // ── toast ──────────────────────────────────────────────────────────────────
  ToastData? toast;
  int _toastSeq = 0;

  void showToast(
    String text, {
    ChipTone tone = ChipTone.neutral,
    String? icon,
  }) {
    _toastSeq += 1;
    toast = ToastData(id: _toastSeq, text: text, tone: tone, icon: icon);
    _notify();
  }

  void dismissToast(int id) {
    if (toast?.id != id) return;
    toast = null;
    _notify();
  }

  /// Best-effort bridge read — returns null instead of throwing, so lookups
  /// inside unawaited flows can't escape as unhandled async errors (the same
  /// helper as FloorController._quiet).
  Future<T?> _quiet<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on MadarError {
      return null;
    }
  }
}
