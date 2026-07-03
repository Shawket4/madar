import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Sentinel for [FloorState.copyWith]'s nullable fields.
const Object _unset = Object();

/// Mirror of the natives' AppModel floor slice: sections, tables, bookings,
/// the open-tickets join, the host-op flags, and the transient seat picks
/// of the seat sheet. All business logic stays in the core.
@immutable
class FloorState {
  const FloorState({
    this.sections = const [],
    this.tables = const [],
    this.reservations = const [],
    this.openTickets = const [],
    this.isBusy = false,
    this.error,
    this.toast,
    this.activeSectionId,
    this.seatPicks = const {},
  });

  /// Floor areas (dashboard-authored geometry), ordered by the core.
  final List<FloorSectionView> sections;

  /// Tables (geometry + live status) across all sections.
  final List<FloorTableView> tables;

  /// Active bookings — reservations + waitlist.
  final List<ReservationView> reservations;

  /// Open tickets — joined onto tables by [ticketForTable] so an occupied
  /// table can jump straight to its ticket/settle.
  final List<TicketView> openTickets;

  /// A blocking floor op is in flight (seat / settle).
  final bool isBusy;

  /// Human-readable failure of the last op (the natives' `error` slot).
  final String? error;

  /// The active toast payload (null = none).
  final ToastData? toast;

  /// The picked section id (null = first section, the natives' default).
  final String? activeSectionId;

  /// Tables picked in the seat sheet (multiple ⇒ merged tables).
  final Set<String> seatPicks;

  /// The active [FloorSectionView], resolving a stale/unset pick to the
  /// first section.
  FloorSectionView? get activeSection {
    for (final section in sections) {
      if (section.id == activeSectionId) return section;
    }
    return sections.firstOrNull;
  }

  /// Tables belonging to [sectionId], in canvas order.
  List<FloorTableView> tablesIn(String? sectionId) => [
    for (final table in tables)
      if (table.sectionId == sectionId) table,
  ];

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

  FloorState copyWith({
    List<FloorSectionView>? sections,
    List<FloorTableView>? tables,
    List<ReservationView>? reservations,
    List<TicketView>? openTickets,
    bool? isBusy,
    Object? error = _unset,
    Object? toast = _unset,
    Object? activeSectionId = _unset,
    Set<String>? seatPicks,
  }) {
    return FloorState(
      sections: sections ?? this.sections,
      tables: tables ?? this.tables,
      reservations: reservations ?? this.reservations,
      openTickets: openTickets ?? this.openTickets,
      isBusy: isBusy ?? this.isBusy,
      error: error == _unset ? this.error : error as String?,
      toast: toast == _unset ? this.toast : toast as ToastData?,
      activeSectionId: activeSectionId == _unset
          ? this.activeSectionId
          : activeSectionId as String?,
      seatPicks: seatPicks ?? this.seatPicks,
    );
  }
}

/// The floor-plan state holder — the natives' AppModel floor slice
/// (AppModel.kt: loadFloor / seatReservation / setTableStatus /
/// notifyReservation / settleTicket) over the bridge. All business logic
/// stays in the core; this only sequences bridge calls.
class FloorNotifier extends Notifier<FloorState> {
  int _toastSeq = 0;

  @override
  FloorState build() => const FloorState();

  MadarBridge get _bridge => ref.read(bridgeProvider);

  /// Core-localized string lookup.
  String _tr(String key) => _bridge.tr(key: key);

  /// The signed-in org's currency code (empty pre-login).
  String get currency => _bridge.currentSession()?.currencyCode ?? '';

  // ── ui slices ───────────────────────────────────────────────────────────

  /// Pick the active floor section.
  void pickSection(String id) => state = state.copyWith(activeSectionId: id);

  /// Reset the seat sheet's table picks — the presenting screen calls this
  /// BEFORE showing the sheet so every seat session starts clean.
  void clearSeatPicks() => state = state.copyWith(seatPicks: const {});

  /// Toggle one table in the seat sheet's pick set.
  void toggleSeatPick(String tableId) {
    final picks = {...state.seatPicks};
    if (!picks.remove(tableId)) picks.add(tableId);
    state = state.copyWith(seatPicks: picks);
  }

  /// Dismiss the error banner.
  void clearError() => state = state.copyWith(error: null);

  /// Present a transient toast pill.
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

  /// Auto-dismiss callback for `ToastHost`.
  void dismissToast(int id) {
    if (state.toast?.id != id) return;
    state = state.copyWith(toast: null);
  }

  // ── loads ───────────────────────────────────────────────────────────────

  /// Best-effort refresh of every floor slice — each list keeps its last
  /// good value on failure (the natives' `runCatching { … }.getOrNull()`).
  Future<void> loadFloor() async {
    final bridge = _bridge;
    final sections = await _quiet(bridge.listFloorSections);
    final tables = await _quiet(bridge.listFloorTables);
    final reservations = await _quiet(bridge.listReservations);
    final openTickets = await _quiet(bridge.listOpenTickets);
    state = state.copyWith(
      sections: sections ?? state.sections,
      tables: tables ?? state.tables,
      reservations: reservations ?? state.reservations,
      openTickets: openTickets ?? state.openTickets,
    );
  }

  // ── host ops ────────────────────────────────────────────────────────────

  /// Seat a party onto one or more tables (multiple ⇒ merged). Opens a
  /// dine-in ticket in the core.
  Future<bool> seatReservation(String bookingId, List<String> tableIds) async {
    final bridge = _bridge;
    state = state.copyWith(isBusy: true);
    try {
      await bridge.seatReservation(bookingId: bookingId, tableIds: tableIds);
      await loadFloor();
      showToast(
        _tr('reservations.seated'),
        tone: ChipTone.success,
        icon: 'checkmark.circle',
      );
      ref.read(shellProvider.notifier).refresh();
      return true;
    } on MadarError catch (e) {
      _raise(bridge, e);
      return false;
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  /// Set a table's live status (`free` | `held` | `seated` | `dirty`).
  Future<void> setTableStatus(String tableId, String status) async {
    final bridge = _bridge;
    try {
      await bridge.setFloorTableStatus(tableId: tableId, status: status);
      await loadFloor();
      ref.read(shellProvider.notifier).refresh();
    } on MadarError catch (e) {
      _raise(bridge, e);
    }
  }

  /// Send the booking's nudge (reservation departure / waitlist ready).
  Future<void> notifyReservation(String bookingId) async {
    final bridge = _bridge;
    try {
      await bridge.notifyReservation(bookingId: bookingId);
      await loadFloor();
    } on MadarError catch (e) {
      _raise(bridge, e);
    }
  }

  /// SETTLE an occupied table's open ticket into a paid order in the
  /// cashier's shift — the natives' AppModel.settleTicket verbatim
  /// (shift-guard → core call → reload + toast + shell refresh).
  Future<bool> settleTicket({
    required String ticketId,
    required String paymentMethodId,
    int? amountTenderedMinor,
    int? tipMinor,
    String? tipPaymentMethodId,
  }) async {
    final bridge = _bridge;
    final shiftId = (await _quiet(bridge.currentShift))?.id;
    if (shiftId == null) {
      state = state.copyWith(error: _tr('waiter.need_shift'));
      return false;
    }
    state = state.copyWith(isBusy: true, error: null);
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
      showToast(_tr('waiter.settled'), tone: ChipTone.success);
      ref.read(shellProvider.notifier).refresh();
      return true;
    } on MadarError catch (e) {
      _raise(bridge, e);
      return false;
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  /// Surface a failed op — human message into the error slot, plus the
  /// shared re-auth request on a 401 with a live session.
  void _raise(MadarBridge bridge, MadarError e) {
    state = state.copyWith(error: bridge.humanMessage(e));
    if (e is MadarError_Unauthenticated && bridge.currentSession() != null) {
      ref.read(reauthRequestProvider.notifier).request();
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

/// The floor board's shared state — kept alive across the shell so the
/// 15-second live refresh lands wherever the plan is shown.
final NotifierProvider<FloorNotifier, FloorState> floorProvider =
    NotifierProvider(FloorNotifier.new);
