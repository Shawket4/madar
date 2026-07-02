import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Screen-local mirror of the natives' AppModel floor slice
/// (AppModel.kt: loadFloor / seatReservation / setTableStatus /
/// notifyReservation / settleTicket): sections, tables, bookings, the
/// open-tickets join, and the toast/error slots. All business logic stays
/// in the core; this only sequences bridge calls and notifies the widgets.
class FloorController extends ChangeNotifier {
  /// Creates the floor-plan state holder over [core].
  FloorController({required this.core, required this.onStateChanged});

  /// The shared Rust core.
  final MadarCore core;

  /// Shell callback — fired after any bridge call that can move
  /// `app_route()` / the shift stats (settling a ticket).
  final VoidCallback onStateChanged;

  /// The generated bridge — every core method lives here.
  MadarBridge get bridge => core.bridge;

  /// Core-localized string lookup.
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

  /// The signed-in org's currency code (empty pre-login).
  String get currency => bridge.currentSession()?.currencyCode ?? '';

  // ── floor state ─────────────────────────────────────────────────────────────
  /// Floor areas (dashboard-authored geometry), ordered by the core.
  List<FloorSectionView> sections = const [];

  /// Tables (geometry + live status) across all sections.
  List<FloorTableView> tables = const [];

  /// Active bookings — reservations + waitlist.
  List<ReservationView> reservations = const [];

  /// Open tickets — joined onto tables by [ticketForTable] so an occupied
  /// table can jump straight to its ticket/settle.
  List<TicketView> openTickets = const [];

  /// A blocking floor op is in flight (seat / settle).
  bool isBusy = false;

  /// Human-readable failure of the last op (the natives' `error` slot).
  String? error;

  /// Dismiss the error banner.
  void clearError() {
    error = null;
    _notify();
  }

  /// The settleable open ticket sitting on [tableId], if any.
  TicketView? ticketForTable(String tableId) {
    for (final ticket in openTickets) {
      if (ticket.tableId == tableId &&
          (ticket.status == 'open' || ticket.status == 'ready')) {
        return ticket;
      }
    }
    return null;
  }

  // ── toast ───────────────────────────────────────────────────────────────────
  /// The active toast payload (null = none).
  ToastData? toast;
  int _toastSeq = 0;

  /// Present a transient toast pill.
  void showToast(
    String text, {
    ChipTone tone = ChipTone.neutral,
    String? icon,
  }) {
    _toastSeq += 1;
    toast = ToastData(id: _toastSeq, text: text, tone: tone, icon: icon);
    _notify();
  }

  /// Auto-dismiss callback for [ToastHost].
  void dismissToast(int id) {
    if (toast?.id != id) return;
    toast = null;
    _notify();
  }

  // ── loads ───────────────────────────────────────────────────────────────────
  /// Best-effort refresh of every floor slice — each list keeps its last
  /// good value on failure (the natives' `runCatching { … }.getOrNull()`).
  Future<void> loadFloor() async {
    sections = await _quiet(bridge.listFloorSections) ?? sections;
    tables = await _quiet(bridge.listFloorTables) ?? tables;
    reservations = await _quiet(bridge.listReservations) ?? reservations;
    openTickets = await _quiet(bridge.listOpenTickets) ?? openTickets;
    _notify();
  }

  // ── host ops ────────────────────────────────────────────────────────────────
  /// Seat a party onto one or more tables (multiple ⇒ merged). Opens a
  /// dine-in ticket in the core.
  Future<bool> seatReservation(String bookingId, List<String> tableIds) async {
    isBusy = true;
    _notify();
    try {
      await bridge.seatReservation(bookingId: bookingId, tableIds: tableIds);
      await loadFloor();
      showToast(
        tr('reservations.seated'),
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

  /// Set a table's live status (`free` | `held` | `seated` | `dirty`).
  Future<void> setTableStatus(String tableId, String status) async {
    try {
      await bridge.setFloorTableStatus(tableId: tableId, status: status);
      await loadFloor();
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
      _notify();
    }
  }

  /// Send the booking's nudge (reservation departure / waitlist ready).
  Future<void> notifyReservation(String bookingId) async {
    try {
      await bridge.notifyReservation(bookingId: bookingId);
      await loadFloor();
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
      _notify();
    }
  }

  /// SETTLE an occupied table's open ticket into a paid order in the
  /// cashier's shift — the natives' AppModel.settleTicket verbatim
  /// (shift-guard → core call → reload + toast).
  Future<bool> settleTicket({
    required String ticketId,
    required String paymentMethodId,
    int? amountTenderedMinor,
    int? tipMinor,
    String? tipPaymentMethodId,
  }) async {
    final shiftId = (await _quiet(bridge.currentShift))?.id;
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
      await loadFloor();
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

  Future<T?> _quiet<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on MadarError {
      return null;
    }
  }
}
