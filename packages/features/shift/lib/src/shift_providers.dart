/// The shift feature's Riverpod spine — one `Notifier` per surface, mirroring
/// the natives' per-screen state: the open-shift form (prefill + connectivity
/// heartbeat), the close-shift count (expected drawer + variance), the cash
/// in/out ledger, the shift-history list (+ per-row report prefetch), and the
/// Z-report preview sheet (report / orders / print feedback). All bridge calls
/// go through [bridgeProvider]; any call that can move `app_route()` or the
/// drawer hands off to [shellProvider]'s `refresh()`.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart' show ChipTone, ToastData;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Family TYPE annotations moved to the misc library in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// ESC/POS character columns (natives: renderShiftReport(..., 32u, ...)).
const int _printWidth = 32;

/// copyWith sentinel so nullable fields can be cleared explicitly.
const Object _unset = Object();

// ─── Open shift ──────────────────────────────────────────────────────────────

/// Open-shift form state: the count, the carried-over suggestion, the busy /
/// error pair, and the top-pinned connectivity chrome.
@immutable
class OpenShiftState {
  /// Creates the open-shift state.
  const OpenShiftState({
    this.openingMinor = 0,
    this.suggestedMinor = 0,
    this.busy = false,
    this.error,
    this.online = true,
    this.authPaused = false,
  });

  /// The teller's opening count, minor units.
  final int openingMinor;

  /// Carried-over suggestion (previous declared closing), minor units.
  final int suggestedMinor;

  /// An openShift call is in flight.
  final bool busy;

  /// The last submit error (human message), or null.
  final String? error;

  /// Connectivity chrome: the device is online.
  final bool online;

  /// Connectivity chrome: sync paused on a genuine session expiry.
  final bool authPaused;

  /// The count deviates from the carried-over closing → a reason is required.
  bool get needsReason => suggestedMinor > 0 && openingMinor != suggestedMinor;

  /// Copies with the given overrides ([error] clears through the sentinel).
  OpenShiftState copyWith({
    int? openingMinor,
    int? suggestedMinor,
    bool? busy,
    Object? error = _unset,
    bool? online,
    bool? authPaused,
  }) {
    return OpenShiftState(
      openingMinor: openingMinor ?? this.openingMinor,
      suggestedMinor: suggestedMinor ?? this.suggestedMinor,
      busy: busy ?? this.busy,
      error: error == _unset ? this.error : error as String?,
      online: online ?? this.online,
      authPaused: authPaused ?? this.authPaused,
    );
  }
}

/// The open-shift surface controller. On entry it reconciles the device's
/// shift (adopting an already-open one — hand-off to the shell) and primes the
/// carried-over prefill. Connectivity is reflected app-wide via the
/// ConnectivityService pulse — no screen-local polling.
class OpenShiftNotifier extends Notifier<OpenShiftState> {
  bool _disposed = false;
  late MadarBridge _bridge;

  @override
  OpenShiftState build() {
    _bridge = ref.read(bridgeProvider);
    ref
      ..onDispose(() => _disposed = true)
      // Reflect the core's online/sync state whenever the app-wide
      // ConnectivityService re-checks (OS network change / resume / a failed
      // request) and pulses — without a screen-local poll. A teller who landed
      // here offline re-adopts their active shift on the offline→online edge.
      ..listen(connectivityPulseProvider, (_, _) {
        unawaited(_reflectStatus());
      });
    // Prime the prefill on entry (reconcile FIRST — it adopts an already-open
    // shift so a teller who lands here never opens a SECOND shift on top of a
    // live one), plus a one-time connectivity refresh so freshly-entered state
    // is accurate. Kicked off a microtask late so build() finishes first.
    unawaited(
      Future<void>.microtask(() {
        unawaited(_prime());
        unawaited(refreshConnectivity());
      }),
    );
    return const OpenShiftState();
  }

  /// Reflect the core's CURRENT online/sync state into the chrome WITHOUT
  /// pinging — the app-level ConnectivityService already refreshed the core
  /// and pulsed us. Reconciles the shift on an offline→online edge.
  Future<void> _reflectStatus() async {
    if (_bridge.currentSession() == null) return;
    final wasOnline = state.online;
    SyncStatusView? status;
    try {
      status = await _bridge.syncStatus();
    } on Exception catch (_) {}
    if (_disposed || status == null) return;
    state = state.copyWith(
      online: status.online,
      authPaused: status.authPaused,
    );
    if (!wasOnline && status.online) await _reconcileShift();
  }

  /// The teller edited the count.
  void setAmount(int minor) => state = state.copyWith(openingMinor: minor);

  Future<void> _prime() async {
    await _reconcileShift();
    if (_disposed) return;
    await _loadPrefill();
  }

  /// Reconcile the device's shift with the server when online (existing shift
  /// on login, dashboard force-close); use the local cache offline. Never let
  /// a transient refresh error nuke a good local shift — fall back to the
  /// cache. Adopting an open shift moves `app_route()` → hand off to the
  /// shell.
  Future<void> _reconcileShift() async {
    final shell = ref.read(shellProvider.notifier);
    ShiftView? shift;
    if (_bridge.currentSession()?.online ?? false) {
      try {
        shift = await _bridge.refreshShift();
      } on Exception catch (_) {
        shift = await _currentShiftOrNull();
      }
    } else {
      shift = await _currentShiftOrNull();
    }
    if (shift?.isOpen ?? false) shell.refresh();
  }

  Future<ShiftView?> _currentShiftOrNull() async {
    try {
      return await _bridge.currentShift();
    } on Exception catch (_) {
      return null;
    }
  }

  /// Prime the open-shift form: show the locally-cached carried-over
  /// suggestion instantly, then refresh it from the server (last synced
  /// declared closing) when online. Seed the count once while still
  /// untouched.
  Future<void> _loadPrefill() async {
    var suggested = await _readSuggested();
    if (_disposed) return;
    _applySuggested(suggested);
    if (_bridge.currentSession()?.online ?? false) {
      try {
        await _bridge.refreshShift();
      } on Exception catch (_) {}
      suggested = await _readSuggested();
      if (_disposed) return;
      _applySuggested(suggested);
    }
  }

  Future<int> _readSuggested() async {
    try {
      return await _bridge.suggestedOpeningCashMinor();
    } on Exception catch (_) {
      return 0;
    }
  }

  void _applySuggested(int suggested) {
    state = state.copyWith(
      suggestedMinor: suggested,
      openingMinor: state.openingMinor == 0 && suggested > 0
          ? suggested
          : state.openingMinor,
    );
  }

  /// Connectivity heartbeat — ping (updates online + drains), then re-read
  /// the sync chrome. On an offline→online transition, re-adopt the server's
  /// authoritative shift (the core drained the backlog during the ping).
  Future<void> refreshConnectivity() async {
    if (_bridge.currentSession() == null) return;
    final wasOnline = state.online;
    try {
      await _bridge.refreshConnectivity();
    } on Exception catch (_) {}
    SyncStatusView? status;
    try {
      status = await _bridge.syncStatus();
    } on Exception catch (_) {}
    if (_disposed) return;
    if (status != null) {
      state = state.copyWith(
        online: status.online,
        authPaused: status.authPaused,
      );
    }
    if (!wasOnline && state.online) await _reconcileShift();
  }

  /// Open the shift with the current count (+ [reason] when the count
  /// deviates from the carry-over). A successful open moves `app_route()` —
  /// the shell hand-off happens here.
  Future<void> submit({required String reason}) async {
    if (state.needsReason && reason.trim().isEmpty) {
      // Guidance next to the action that triggers it — the natives' flagError.
      state = state.copyWith(
        error: _bridge.tr(key: 'shift.opening_reason_required'),
      );
      return;
    }
    final shell = ref.read(shellProvider.notifier);
    state = state.copyWith(busy: true, error: null);
    try {
      await _bridge.openShift(
        openingCashMinor: state.openingMinor,
        openingReason: state.needsReason ? reason : null,
      );
      if (!_disposed) state = state.copyWith(busy: false);
      shell.refresh();
    } on MadarError catch (e) {
      if (_disposed) return;
      state = state.copyWith(busy: false, error: _bridge.humanMessage(e));
    } on Exception catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        busy: false,
        error: _bridge.tr(key: 'err.generic'),
      );
    }
  }

  /// The recessive exit — the natives' signOut: realtime + LAN teardown, then
  /// the best-effort core logout. The shell re-reads `app_route()` after.
  Future<void> signOut() async {
    final shell = ref.read(shellProvider.notifier);
    _bridge.unsubscribeRealtime();
    try {
      await _bridge.lanStop();
    } on Exception catch (_) {}
    try {
      await _bridge.logout(wipeOutbox: false);
    } on Exception catch (_) {}
    shell.refresh();
  }
}

/// Open-shift surface state (auto-disposed with the screen so the heartbeat
/// stops and the form resets between visits).
final NotifierProvider<OpenShiftNotifier, OpenShiftState> openShiftProvider =
    NotifierProvider.autoDispose<OpenShiftNotifier, OpenShiftState>(
      OpenShiftNotifier.new,
    );

// ─── Close shift ─────────────────────────────────────────────────────────────

/// Close-shift state: the open shift + its Z-report (expected drawer), the
/// teller's count, and the busy / error pair.
@immutable
class CloseShiftState {
  /// Creates the close-shift state.
  const CloseShiftState({
    this.countedMinor = 0,
    this.busy = false,
    this.error,
    this.shift,
    this.report,
  });

  /// The teller's counted drawer, minor units.
  final int countedMinor;

  /// A closeShift call is in flight.
  final bool busy;

  /// The last close error (human message), or null.
  final String? error;

  /// The open shift for the summary card (null while loading).
  final ShiftView? shift;

  /// The Z-report carrying the expected drawer (null while loading).
  final ShiftReportView? report;

  /// The count deviates from the system's expected drawer → a closing reason
  /// is required (the open screen's discrepancy pattern).
  bool get needsReason =>
      report != null && countedMinor != report!.expectedCashMinor;

  /// Copies with the given overrides (nullables clear through the sentinel).
  CloseShiftState copyWith({
    int? countedMinor,
    bool? busy,
    Object? error = _unset,
    Object? shift = _unset,
    Object? report = _unset,
  }) {
    return CloseShiftState(
      countedMinor: countedMinor ?? this.countedMinor,
      busy: busy ?? this.busy,
      error: error == _unset ? this.error : error as String?,
      shift: shift == _unset ? this.shift : shift as ShiftView?,
      report: report == _unset ? this.report : report as ShiftReportView?,
    );
  }
}

/// The close-shift surface controller — primes the shift + Z-report on entry
/// and performs the close.
class CloseShiftNotifier extends Notifier<CloseShiftState> {
  bool _disposed = false;
  late MadarBridge _bridge;

  @override
  CloseShiftState build() {
    _bridge = ref.read(bridgeProvider);
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(_load));
    return const CloseShiftState();
  }

  /// The teller edited the count.
  void setCounted(int minor) => state = state.copyWith(countedMinor: minor);

  /// Prime the screen: the open shift for the summary card (server-fresh
  /// when online, cache otherwise — never let a transient refresh nuke a
  /// good local shift), then the Z-report for the expected drawer figures.
  Future<void> _load() async {
    ShiftView? shift;
    if (_bridge.currentSession()?.online ?? false) {
      try {
        shift = await _bridge.refreshShift();
      } on Exception catch (_) {
        shift = await _currentShiftOrNull();
      }
    } else {
      shift = await _currentShiftOrNull();
    }
    if (_disposed) return;
    state = state.copyWith(shift: shift);
    try {
      final report = await _bridge.shiftReport();
      if (!_disposed) state = state.copyWith(report: report);
    } on Exception catch (_) {}
  }

  Future<ShiftView?> _currentShiftOrNull() async {
    try {
      return await _bridge.currentShift();
    } on Exception catch (_) {
      return null;
    }
  }

  /// Close the shift with the counted drawer (+ [note], REQUIRED when the
  /// count deviates). Returns true on success — the SCREEN then pops the
  /// overlay first and hands off to the shell (route flips to open-shift).
  Future<bool> close({required String note}) async {
    if (state.needsReason && note.trim().isEmpty) {
      // Guidance next to the action that triggers it — the natives'
      // flagError, mirroring the open screen's required reason.
      state = state.copyWith(
        error: _bridge.tr(key: 'shift.opening_reason_required'),
      );
      return false;
    }
    state = state.copyWith(busy: true, error: null);
    try {
      final trimmed = note.trim();
      await _bridge.closeShift(
        closingCashMinor: state.countedMinor,
        cashNote: trimmed.isEmpty ? null : trimmed,
      );
      if (!_disposed) state = state.copyWith(busy: false);
      return true;
    } on MadarError catch (e) {
      if (_disposed) return false;
      state = state.copyWith(busy: false, error: _bridge.humanMessage(e));
      return false;
    } on Exception catch (_) {
      if (_disposed) return false;
      state = state.copyWith(
        busy: false,
        error: _bridge.tr(key: 'err.generic'),
      );
      return false;
    }
  }
}

/// Close-shift surface state (auto-disposed with the screen).
final NotifierProvider<CloseShiftNotifier, CloseShiftState> closeShiftProvider =
    NotifierProvider.autoDispose<CloseShiftNotifier, CloseShiftState>(
      CloseShiftNotifier.new,
    );

// ─── Cash movements ──────────────────────────────────────────────────────────

/// Cash in/out ledger state: the open shift's movements, the record form's
/// direction + amount, and the busy / error pair.
@immutable
class CashMovementsState {
  /// Creates the cash-movements state.
  const CashMovementsState({
    this.movements = const [],
    this.loading = false,
    this.isIn = true,
    this.amountMinor = 0,
    this.busy = false,
    this.error,
  });

  /// The open shift's movements (server rows merged with queued ones).
  final List<CashMovementView> movements;

  /// The ledger list is loading.
  final bool loading;

  /// Record form: pay-in (true) or pay-out.
  final bool isIn;

  /// Record form: the amount, minor units.
  final int amountMinor;

  /// A recordCashMovement call is in flight.
  final bool busy;

  /// The last record error (human message), or null.
  final String? error;

  /// The Record CTA is enabled.
  bool get canRecord => amountMinor > 0 && !busy;

  /// Copies with the given overrides ([error] clears through the sentinel).
  CashMovementsState copyWith({
    List<CashMovementView>? movements,
    bool? loading,
    bool? isIn,
    int? amountMinor,
    bool? busy,
    Object? error = _unset,
  }) {
    return CashMovementsState(
      movements: movements ?? this.movements,
      loading: loading ?? this.loading,
      isIn: isIn ?? this.isIn,
      amountMinor: amountMinor ?? this.amountMinor,
      busy: busy ?? this.busy,
      error: error == _unset ? this.error : error as String?,
    );
  }
}

/// The cash in/out surface controller — loads the ledger on entry and
/// records signed movements against the open shift (OFFLINE-FIRST, queued
/// through the durable outbox).
class CashMovementsNotifier extends Notifier<CashMovementsState> {
  bool _disposed = false;
  late MadarBridge _bridge;

  @override
  CashMovementsState build() {
    _bridge = ref.read(bridgeProvider);
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(load));
    return const CashMovementsState();
  }

  /// Pay-in / pay-out direction toggle.
  void setDirection({required bool isIn}) => state = state.copyWith(isIn: isIn);

  /// The teller edited the amount.
  void setAmount(int minor) => state = state.copyWith(amountMinor: minor);

  /// The open shift's cash movements — server rows merged with still-queued
  /// ones in the core. Load failures degrade to an empty list (the natives'
  /// `getOrDefault(emptyList())`).
  Future<void> load() async {
    state = state.copyWith(loading: true);
    List<CashMovementView> movements;
    try {
      movements = await _bridge.listCashMovements();
    } on Exception catch (_) {
      movements = const [];
    }
    if (_disposed) return;
    state = state.copyWith(movements: movements, loading: false);
  }

  /// Record a pay-in (`> 0`) or pay-out (`< 0`), reload the list, and reset
  /// the amount only on success — the natives' `recordCashMovement`. Returns
  /// true on success so the screen can clear its note field; the drawer's
  /// expected cash moved, so the shell refreshes here.
  Future<bool> record({required String note}) async {
    final shell = ref.read(shellProvider.notifier);
    state = state.copyWith(busy: true, error: null);
    try {
      final signed = state.isIn ? state.amountMinor : -state.amountMinor;
      await _bridge.recordCashMovement(amountMinor: signed, note: note.trim());
      await load();
      if (_disposed) return false;
      state = state.copyWith(busy: false, amountMinor: 0);
      shell.refresh();
      return true;
    } on MadarError catch (e) {
      if (_disposed) return false;
      state = state.copyWith(busy: false, error: _bridge.humanMessage(e));
      return false;
    } on Exception catch (_) {
      if (_disposed) return false;
      state = state.copyWith(
        busy: false,
        error: _bridge.tr(key: 'err.generic'),
      );
      return false;
    }
  }
}

/// Cash in/out surface state (auto-disposed with the screen).
final NotifierProvider<CashMovementsNotifier, CashMovementsState>
cashMovementsProvider =
    NotifierProvider.autoDispose<CashMovementsNotifier, CashMovementsState>(
      CashMovementsNotifier.new,
    );

// ─── Shift history ───────────────────────────────────────────────────────────

/// Shift-history state: the closed shifts, the live shift for pinning, the
/// per-row report-prefetch spinner, and the failure toast.
@immutable
class ShiftHistoryState {
  /// Creates the shift-history state.
  const ShiftHistoryState({
    this.shifts = const [],
    this.live,
    this.loading = false,
    this.reportLoadingId,
    this.expanded = const {},
    this.ordersByShift = const {},
    this.ordersLoadingId,
    this.toast,
  });

  /// Past shifts, newest first.
  final List<ShiftSummaryView> shifts;

  /// The live shift (for pinning on top), or null.
  final ShiftView? live;

  /// The list is loading.
  final bool loading;

  /// The shift id whose Z-report is being prefetched (row spinner), or null.
  final String? reportLoadingId;

  /// Shift ids whose inline orders panel is expanded.
  final Set<String> expanded;

  /// Lazily loaded per-shift orders (keyed by shift id); a present-but-empty
  /// list means "loaded, none".
  final Map<String, List<OrderSummaryView>> ordersByShift;

  /// The shift id whose orders are being fetched (panel spinner), or null.
  final String? ordersLoadingId;

  /// The latest failure toast, or null.
  final ToastData? toast;

  /// Copies with the given overrides (nullables clear through the sentinel).
  ShiftHistoryState copyWith({
    List<ShiftSummaryView>? shifts,
    Object? live = _unset,
    bool? loading,
    Object? reportLoadingId = _unset,
    Set<String>? expanded,
    Map<String, List<OrderSummaryView>>? ordersByShift,
    Object? ordersLoadingId = _unset,
    Object? toast = _unset,
  }) {
    return ShiftHistoryState(
      shifts: shifts ?? this.shifts,
      live: live == _unset ? this.live : live as ShiftView?,
      loading: loading ?? this.loading,
      reportLoadingId: reportLoadingId == _unset
          ? this.reportLoadingId
          : reportLoadingId as String?,
      expanded: expanded ?? this.expanded,
      ordersByShift: ordersByShift ?? this.ordersByShift,
      ordersLoadingId: ordersLoadingId == _unset
          ? this.ordersLoadingId
          : ordersLoadingId as String?,
      toast: toast == _unset ? this.toast : toast as ToastData?,
    );
  }
}

/// The shift-history surface controller — loads the page on entry and
/// prefetches a tapped row's Z-report for the shared preview sheet.
class ShiftHistoryNotifier extends Notifier<ShiftHistoryState> {
  bool _disposed = false;
  int _toastSeq = 0;
  late MadarBridge _bridge;

  @override
  ShiftHistoryState build() {
    _bridge = ref.read(bridgeProvider);
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(load));
    return const ShiftHistoryState();
  }

  /// Past shifts (newest first) + the live shift for pinning. Load failures
  /// degrade to empty (the natives' `getOrDefault(emptyList())`).
  Future<void> load() async {
    state = state.copyWith(loading: true);
    List<ShiftSummaryView> shifts;
    try {
      shifts = await _bridge.listShifts();
    } on Exception catch (_) {
      shifts = const [];
    }
    ShiftView? live;
    try {
      live = await _bridge.currentShift();
    } on Exception catch (_) {
      live = null;
    }
    if (_disposed) return;
    state = state.copyWith(shifts: shifts, live: live, loading: false);
  }

  /// Prefetch a past shift's Z-report via `shiftReportFor` (spinner in the
  /// row's chevron slot, danger toast on failure — the natives'
  /// `openShiftReportPreviewFor`). Returns null while another row is busy or
  /// on failure; the SCREEN presents the sheet with the result.
  Future<ShiftReportView?> fetchReport(String shiftId) async {
    if (state.reportLoadingId != null) return null;
    state = state.copyWith(reportLoadingId: shiftId);
    try {
      final report = await _bridge.shiftReportFor(shiftId: shiftId);
      if (!_disposed) state = state.copyWith(reportLoadingId: null);
      return report;
    } on Exception catch (_) {
      if (_disposed) return null;
      _toastSeq += 1;
      state = state.copyWith(
        reportLoadingId: null,
        toast: ToastData(
          id: _toastSeq,
          text: _bridge.tr(key: 'receipt.print_failed'),
          tone: ChipTone.danger,
          icon: 'xmark.circle',
        ),
      );
      return null;
    }
  }

  void _showToast(String key, {required ChipTone tone, required String icon}) {
    _toastSeq += 1;
    state = state.copyWith(
      toast: ToastData(
        id: _toastSeq,
        text: _bridge.tr(key: key),
        tone: tone,
        icon: icon,
      ),
    );
  }

  /// Expand/collapse a past shift's inline orders panel; the first expand
  /// lazy-loads that shift's orders (row by row, printable).
  Future<void> toggleShiftOrders(String shiftId) async {
    final expanded = {...state.expanded};
    if (!expanded.add(shiftId)) expanded.remove(shiftId);
    state = state.copyWith(expanded: expanded);
    if (!expanded.contains(shiftId) ||
        state.ordersByShift.containsKey(shiftId)) {
      return;
    }
    state = state.copyWith(ordersLoadingId: shiftId);
    List<OrderSummaryView> orders;
    try {
      orders = await _bridge.listOrdersForShift(shiftId: shiftId);
    } on Exception catch (_) {
      orders = const [];
    }
    if (_disposed) return;
    state = state.copyWith(
      ordersByShift: {...state.ordersByShift, shiftId: orders},
      ordersLoadingId: null,
    );
  }

  /// Print a single order's receipt from an expanded shift row — renders in
  /// the core and streams to the configured printer, with toast feedback.
  Future<void> printOrder(OrderSummaryView order) async {
    final config = _bridge.deviceConfig();
    final tx = ref.read(printerServiceProvider).activeTransport();
    if (tx == null) {
      _showToast('receipt.no_printer', tone: ChipTone.warning, icon: 'printer');
      return;
    }
    try {
      final bytes = await _bridge.renderOrderReceipt(
        orderId: order.id,
        storeName: config.branchName ?? '',
        currency: _bridge.currentSession()?.currencyCode ?? '',
        width: _printWidth,
        brand: config.printerBrand == 'star'
            ? PrinterBrand.star
            : PrinterBrand.epson,
      );
      await tx.send(bytes);
      if (!_disposed) {
        _showToast(
          'receipt.printed',
          tone: ChipTone.success,
          icon: 'checkmark.circle',
        );
      }
    } on Exception catch (_) {
      if (!_disposed) {
        _showToast(
          'receipt.print_failed',
          tone: ChipTone.danger,
          icon: 'xmark.circle',
        );
      }
    }
  }

  /// Dismiss the toast if it is still the presented one.
  void dismissToast(int id) {
    if (state.toast?.id == id) state = state.copyWith(toast: null);
  }
}

/// Shift-history surface state (auto-disposed with the screen).
final NotifierProvider<ShiftHistoryNotifier, ShiftHistoryState>
shiftHistoryProvider =
    NotifierProvider.autoDispose<ShiftHistoryNotifier, ShiftHistoryState>(
      ShiftHistoryNotifier.new,
    );

// ─── Z-report preview sheet ──────────────────────────────────────────────────

/// The natives' `PrintState` — the terminal print feedback the teller needs
/// (sent / no printer bound / unreachable).
enum ShiftPrintState {
  /// Nothing sent yet.
  idle,

  /// Render + send in flight.
  printing,

  /// Bytes reached the printer.
  printed,

  /// No printer configured on this device (distinct state, not a failure).
  noPrinter,

  /// Render or send failed.
  failed,
}

/// The preview sheet's DATA identity: a pre-fetched [report] (close-shift /
/// past shifts) or null to load the current shift's, plus the past-shift
/// [shiftId] for the lazy Orders section. Equality is identity on [report]
/// (one sheet presentation carries one report instance) + value on
/// [shiftId], so the family key is stable across sheet rebuilds.
@immutable
class ShiftReportRequest {
  /// Creates the request.
  const ShiftReportRequest({this.report, this.shiftId});

  /// A pre-fetched report, or null to load the current shift's on entry.
  final ShiftReportView? report;

  /// Past-shift id for the lazy Orders section (null → current shift).
  final String? shiftId;

  @override
  bool operator ==(Object other) =>
      other is ShiftReportRequest &&
      identical(other.report, report) &&
      other.shiftId == shiftId;

  @override
  int get hashCode => Object.hash(identityHashCode(report), shiftId);
}

/// Z-report preview state: the report, the lazy-loaded orders, and the
/// terminal print feedback.
@immutable
class ShiftReportSheetState {
  /// Creates the preview state.
  const ShiftReportSheetState({
    this.report,
    this.orders,
    this.expanded = false,
    this.print = ShiftPrintState.idle,
  });

  /// The rendered report (null while the current shift's loads → skeleton).
  final ShiftReportView? report;

  /// The shift's orders for the Orders section — null until first expanded
  /// (then null again = loading → skeleton rows); load failures degrade to
  /// the empty line.
  final List<OrderSummaryView>? orders;

  /// Whether the orders breakdown is expanded — OFF by default. Drives BOTH
  /// the on-screen preview and whether print includes the per-order section.
  final bool expanded;

  /// Print feedback.
  final ShiftPrintState print;

  /// Copies with the given overrides (nullables clear through the sentinel).
  ShiftReportSheetState copyWith({
    Object? report = _unset,
    Object? orders = _unset,
    bool? expanded,
    ShiftPrintState? print,
  }) {
    return ShiftReportSheetState(
      report: report == _unset ? this.report : report as ShiftReportView?,
      orders: orders == _unset
          ? this.orders
          : orders as List<OrderSummaryView>?,
      expanded: expanded ?? this.expanded,
      print: print ?? this.print,
    );
  }
}

/// The preview sheet's controller — seeds the pre-fetched report (or loads
/// the current shift's), lazy-loads the shift's orders, and streams the
/// rendered Z-report to the configured network printer.
class ShiftReportNotifier extends Notifier<ShiftReportSheetState> {
  /// Creates the notifier for one family [arg].
  ShiftReportNotifier(this.arg);

  /// The presented request (a pre-fetched report, or the shift to load).
  final ShiftReportRequest arg;

  bool _disposed = false;
  late MadarBridge _bridge;

  @override
  ShiftReportSheetState build() {
    _bridge = ref.read(bridgeProvider);
    ref.onDispose(() => _disposed = true);
    // Orders are NOT loaded until the teller expands the section (they add a
    // round trip + a lot of rows). Only the summary loads eagerly.
    if (arg.report == null) unawaited(Future<void>.microtask(_load));
    return ShiftReportSheetState(report: arg.report);
  }

  Future<void> _load() async {
    try {
      final report = await _bridge.shiftReport();
      if (_disposed) return;
      state = state.copyWith(report: report);
    } on Exception catch (_) {}
  }

  /// Expand/collapse the orders breakdown. On first expand, lazy-load the
  /// shift's orders — a past shift via `listOrdersForShift`, the current
  /// shift via the queue-merged `listShiftOrders`.
  void toggleExpanded() {
    final next = !state.expanded;
    state = state.copyWith(expanded: next);
    if (next && state.orders == null) unawaited(_loadOrders());
  }

  Future<void> _loadOrders() async {
    try {
      final id = arg.shiftId;
      final orders = id == null
          ? await _bridge.listShiftOrders()
          : await _bridge.listOrdersForShift(shiftId: id);
      if (!_disposed) state = state.copyWith(orders: orders);
    } on Exception catch (_) {
      if (!_disposed) {
        state = state.copyWith(orders: const <OrderSummaryView>[]);
      }
    }
  }

  /// Render the Z-report in the core and stream the bytes to the device's
  /// configured network printer — the natives' printReportView: no printer
  /// bound is a distinct state (not a failure), and the send is best-effort.
  Future<void> printReport() async {
    final report = state.report;
    if (report == null || state.print == ShiftPrintState.printing) return;
    final config = _bridge.deviceConfig();
    final tx = ref.read(printerServiceProvider).activeTransport();
    if (tx == null) {
      state = state.copyWith(print: ShiftPrintState.noPrinter);
      return;
    }
    state = state.copyWith(print: ShiftPrintState.printing);
    try {
      final bytes = await _bridge.renderShiftReport(
        report: report,
        storeName: config.branchName ?? '',
        currency: _bridge.currentSession()?.currencyCode ?? '',
        width: _printWidth,
        brand: config.printerBrand == 'star'
            ? PrinterBrand.star
            : PrinterBrand.epson,
        // Expanded → append the per-order breakdown to the printed report,
        // matching the on-screen preview. Collapsed → summary only.
        orders: state.expanded
            ? (state.orders ?? const <OrderSummaryView>[])
            : const <OrderSummaryView>[],
      );
      await tx.send(bytes);
      if (!_disposed) state = state.copyWith(print: ShiftPrintState.printed);
    } on Exception catch (_) {
      if (!_disposed) state = state.copyWith(print: ShiftPrintState.failed);
    }
  }

  /// Print a SINGLE order's receipt from the shift's orders list (per-order
  /// print in past shifts). Reuses the footer print-feedback state so the
  /// teller sees sent / no-printer / failed just like the report print.
  Future<void> printOrder(OrderSummaryView order) async {
    if (state.print == ShiftPrintState.printing) return;
    final config = _bridge.deviceConfig();
    final tx = ref.read(printerServiceProvider).activeTransport();
    if (tx == null) {
      state = state.copyWith(print: ShiftPrintState.noPrinter);
      return;
    }
    state = state.copyWith(print: ShiftPrintState.printing);
    try {
      final bytes = await _bridge.renderOrderReceipt(
        orderId: order.id,
        storeName: config.branchName ?? '',
        currency: _bridge.currentSession()?.currencyCode ?? '',
        width: _printWidth,
        brand: config.printerBrand == 'star'
            ? PrinterBrand.star
            : PrinterBrand.epson,
      );
      await tx.send(bytes);
      if (!_disposed) state = state.copyWith(print: ShiftPrintState.printed);
    } on Exception catch (_) {
      if (!_disposed) state = state.copyWith(print: ShiftPrintState.failed);
    }
  }
}

/// Z-report preview state, keyed per presentation (auto-disposed with the
/// sheet so print feedback resets between opens).
final NotifierProviderFamily<
  ShiftReportNotifier,
  ShiftReportSheetState,
  ShiftReportRequest
>
shiftReportProvider = NotifierProvider.autoDispose
    .family<ShiftReportNotifier, ShiftReportSheetState, ShiftReportRequest>(
      ShiftReportNotifier.new,
    );
