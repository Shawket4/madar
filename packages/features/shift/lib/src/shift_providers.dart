/// The shift feature's Riverpod spine — one `Notifier` per surface, mirroring
/// the natives' per-screen state: the Till home (the drawer's figures and
/// every drawer at the branch for a manager), the open-shift form (prefill +
/// connectivity heartbeat), the close-shift count (expected drawer +
/// variance), the cash in/out ledger, the shift-history list (+ per-row
/// report prefetch), and the Z-report preview sheet (report / orders / print
/// feedback). All bridge calls go through [bridgeProvider]; any call that can
/// move `app_route()` or the drawer hands off to [shellProvider]'s
/// `refresh()`.
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

/// Roles whose Till sees every drawer at the branch, not just their own.
/// The wire enum is super_admin | org_admin | branch_manager | teller |
/// waiter | kitchen; the rule from the design is "manager = not a teller,
/// waiter or kitchen device", written positively so an unknown future role
/// is NOT a manager by accident.
const Set<String> _managerRoles = {
  'super_admin',
  'org_admin',
  'branch_manager',
};

/// Whether the signed-in person's Till lists every drawer.
bool isManagerRole(String? role) =>
    role != null && _managerRoles.contains(role);

/// The name of the till this device is bound to ("Till 1"), or null when the
/// device is unbound or the catalog mirror has not got the till yet. Tills
/// are named on the server; the device only holds the id.
Future<String?> _boundTillName(MadarBridge bridge) async {
  final tillId = bridge.deviceConfig().tillId;
  if (tillId == null) return null;
  try {
    final tills = await bridge.listTills();
    for (final till in tills) {
      if (till.id == tillId) return till.name;
    }
  } on Exception catch (_) {}
  return null;
}

/// The device's shift: server-fresh when online, the local cache otherwise —
/// and never let a transient refresh error nuke a good local shift.
Future<ShiftView?> _deviceShift(MadarBridge bridge) async {
  if (bridge.currentSession()?.online ?? false) {
    try {
      return await bridge.refreshShift();
    } on Exception catch (_) {}
  }
  try {
    return await bridge.currentShift();
  } on Exception catch (_) {
    return null;
  }
}

// ─── Till home ───────────────────────────────────────────────────────────────

/// The Till tab's state: the drawer (shift + till name), this shift's
/// headline figures (sales from the queue-merged orders, cash in till from the
/// report), the movement ledger, and — for a manager — every drawer at the
/// branch.
@immutable
class TillState {
  /// Creates the Till state.
  const TillState({
    this.loading = true,
    this.shift,
    this.tillName,
    this.report,
    this.stats,
    this.queuedOrders = 0,
    this.movements = const [],
    this.online = true,
    this.isManager = false,
    this.drawers = const [],
    this.drawerReportLoadingId,
    this.toast,
  });

  /// The first load has not resolved the shift yet.
  final bool loading;

  /// The device's shift — null when no shift is open on this till.
  final ShiftView? shift;

  /// The bound till's server name ("Till 1"), or null when unbound.
  final String? tillName;

  /// This shift's report (expected cash, per-method lines); null while it
  /// loads or when the shift is not open.
  final ShiftReportView? report;

  /// Sales total + order count over the queue-merged orders (voids
  /// excluded); null until loaded.
  final ShiftStatsView? stats;

  /// How many of this shift's orders are still in the outbox.
  final int queuedOrders;

  /// The open shift's cash movements, newest first.
  final List<CashMovementView> movements;

  /// The device is online (the honest-figures flag on the stat cards).
  final bool online;

  /// The signed-in role sees every drawer at the branch.
  final bool isManager;

  /// Every shift at the branch (managers only): open ones first.
  final List<ShiftSummaryView> drawers;

  /// The drawer whose report is being fetched (row spinner), or null.
  final String? drawerReportLoadingId;

  /// The latest failure toast, or null.
  final ToastData? toast;

  /// A shift is open on this till.
  bool get hasOpenShift => shift?.isOpen ?? false;

  /// Copies with the given overrides (nullables clear through the sentinel).
  TillState copyWith({
    bool? loading,
    Object? shift = _unset,
    Object? tillName = _unset,
    Object? report = _unset,
    Object? stats = _unset,
    int? queuedOrders,
    List<CashMovementView>? movements,
    bool? online,
    bool? isManager,
    List<ShiftSummaryView>? drawers,
    Object? drawerReportLoadingId = _unset,
    Object? toast = _unset,
  }) {
    return TillState(
      loading: loading ?? this.loading,
      shift: shift == _unset ? this.shift : shift as ShiftView?,
      tillName: tillName == _unset ? this.tillName : tillName as String?,
      report: report == _unset ? this.report : report as ShiftReportView?,
      stats: stats == _unset ? this.stats : stats as ShiftStatsView?,
      queuedOrders: queuedOrders ?? this.queuedOrders,
      movements: movements ?? this.movements,
      online: online ?? this.online,
      isManager: isManager ?? this.isManager,
      drawers: drawers ?? this.drawers,
      drawerReportLoadingId: drawerReportLoadingId == _unset
          ? this.drawerReportLoadingId
          : drawerReportLoadingId as String?,
      toast: toast == _unset ? this.toast : toast as ToastData?,
    );
  }
}

/// The Till tab's controller. Loads the drawer on entry and again whenever
/// the shell's truth moves (a shift opened or closed, a re-login) or the
/// device's connectivity changes — the figures on this tab are the ones a
/// teller reconciles against, so they must never be a stale first read.
class TillNotifier extends Notifier<TillState> {
  bool _disposed = false;
  int _toastSeq = 0;
  late MadarBridge _bridge;

  @override
  TillState build() {
    _bridge = ref.read(bridgeProvider);
    ref
      ..onDispose(() => _disposed = true)
      // The shell re-reads route + session after every state-moving bridge
      // call (open, close, sign-in). Each of those changes what this tab
      // shows, so it is the one signal to reload on.
      ..listen(shellProvider, (_, _) => unawaited(refresh()))
      ..listen(connectivityPulseProvider, (_, _) => unawaited(refresh()));
    unawaited(Future<void>.microtask(refresh));
    return TillState(isManager: isManagerRole(_bridge.currentSession()?.role));
  }

  /// Reload everything the tab shows. The figures load in parallel; each
  /// degrades on its own so one failing call cannot blank the tab.
  Future<void> refresh() async {
    final isManager = isManagerRole(_bridge.currentSession()?.role);
    final shift = await _deviceShift(_bridge);
    if (_disposed) return;
    final open = shift?.isOpen ?? false;
    final (tillName, report, orders, movements, drawers, sync) = await (
      _boundTillName(_bridge),
      open ? _quiet(_bridge.shiftReport) : Future<ShiftReportView?>.value(),
      open
          ? _quiet(_bridge.listShiftOrders)
          : Future<List<OrderSummaryView>?>.value(),
      open
          ? _quiet(_bridge.listCashMovements)
          : Future<List<CashMovementView>?>.value(),
      isManager
          ? _quiet(_bridge.listShifts)
          : Future<List<ShiftSummaryView>?>.value(),
      _quiet(_bridge.syncStatus),
    ).wait;
    if (_disposed) return;
    // Stats are computed in the core over the orders the till just listed —
    // the same queue-merged set the Orders row counts.
    ShiftStatsView? stats;
    if (orders != null) {
      stats = await _quiet(() => _bridge.shiftStats(orders: orders));
      if (_disposed) return;
    }
    final branchDrawers = drawers ?? const <ShiftSummaryView>[];
    state = state.copyWith(
      loading: false,
      shift: shift,
      tillName: tillName,
      report: report,
      stats: stats,
      queuedOrders: orders?.where((o) => o.queued).length ?? 0,
      movements: movements ?? const [],
      online: sync?.online ?? state.online,
      isManager: isManager,
      // Open drawers first — the manager is here to see who is on a till
      // right now; the closed ones are history.
      drawers: [
        ...branchDrawers.where((s) => s.isOpen),
        ...branchDrawers.where((s) => !s.isOpen),
      ],
    );
  }

  /// A manager tapped a drawer: fetch its report for the shared preview
  /// sheet (spinner on the row, toast on failure). Returns null while another
  /// row is busy or on failure; the SCREEN presents the sheet.
  Future<ShiftReportView?> fetchDrawerReport(String shiftId) async {
    if (state.drawerReportLoadingId != null) return null;
    state = state.copyWith(drawerReportLoadingId: shiftId);
    try {
      final report = await _bridge.shiftReportFor(shiftId: shiftId);
      if (!_disposed) state = state.copyWith(drawerReportLoadingId: null);
      return report;
    } on Exception catch (_) {
      if (_disposed) return null;
      _toastSeq += 1;
      state = state.copyWith(
        drawerReportLoadingId: null,
        toast: ToastData(
          id: _toastSeq,
          text: _bridge.tr(key: 'err.generic'),
          tone: ChipTone.danger,
          icon: 'xmark.circle',
        ),
      );
      return null;
    }
  }

  /// Print the X report — the mid-shift read — straight to the bound
  /// printer, with no screen in between.
  ///
  /// Tapping "Print X" used to open the preview sheet, so the one control
  /// literally labelled *Print* did not print: it took two more taps. The
  /// preview is still there on a long press, for the times the shape wants
  /// checking before paper is spent on it, but the tap does what it says.
  ///
  /// Summary only, never the per-order breakdown: an X mid-shift is a read
  /// of the drawer, and the expanded form belongs to the Z at close.
  Future<void> printX() async {
    final report = state.report;
    if (report == null) return;
    final tx = ref.read(printerServiceProvider).activeTransport();
    if (tx == null) {
      _tillToast('receipt.no_printer', tone: ChipTone.warning, icon: 'printer');
      return;
    }
    final config = _bridge.deviceConfig();
    try {
      final bytes = await _bridge.renderShiftReport(
        report: report,
        storeName: config.branchName ?? '',
        currency: _bridge.currentSession()?.currencyCode ?? '',
        width: _printWidth,
        brand: config.printerBrand == 'star'
            ? PrinterBrand.star
            : PrinterBrand.epson,
        orders: const <OrderSummaryView>[],
      );
      await tx.send(bytes);
      if (!_disposed) {
        _tillToast(
          'receipt.printed',
          tone: ChipTone.success,
          icon: 'checkmark.circle',
        );
      }
    } on Exception catch (_) {
      if (!_disposed) {
        _tillToast(
          'receipt.print_failed',
          tone: ChipTone.danger,
          icon: 'xmark.circle',
        );
      }
    }
  }

  void _tillToast(String key, {required ChipTone tone, required String icon}) {
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

  /// Dismiss the toast if it is still the presented one.
  void dismissToast(int id) {
    if (state.toast?.id == id) state = state.copyWith(toast: null);
  }

  /// Run a bridge read, degrading a failure to null (the natives'
  /// `getOrNull`) — the tab shows a dash, not an error, for one figure.
  static Future<T?> _quiet<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on Exception catch (_) {
      return null;
    }
  }
}

/// Till tab state (auto-disposed with the tab so a re-entry reloads).
final NotifierProvider<TillNotifier, TillState> tillProvider =
    NotifierProvider.autoDispose<TillNotifier, TillState>(TillNotifier.new);

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
    this.tillName,
    this.orderCount,
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

  /// The bound till's name for the header ("Till 1"), or null.
  final String? tillName;

  /// How many sales this shift rang (voids excluded), or null until known.
  final int? orderCount;

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
    Object? tillName = _unset,
    Object? orderCount = _unset,
  }) {
    return CloseShiftState(
      countedMinor: countedMinor ?? this.countedMinor,
      busy: busy ?? this.busy,
      error: error == _unset ? this.error : error as String?,
      shift: shift == _unset ? this.shift : shift as ShiftView?,
      report: report == _unset ? this.report : report as ShiftReportView?,
      tillName: tillName == _unset ? this.tillName : tillName as String?,
      orderCount: orderCount == _unset ? this.orderCount : orderCount as int?,
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

  /// Prime the screen: the open shift for the header (server-fresh when
  /// online, cache otherwise), then the Z-report for the expected drawer
  /// figures, the till's name, and the sales count — the last two are
  /// context for the header and degrade to nothing.
  Future<void> _load() async {
    final shift = await _deviceShift(_bridge);
    if (_disposed) return;
    state = state.copyWith(shift: shift);
    try {
      final report = await _bridge.shiftReport();
      if (!_disposed) state = state.copyWith(report: report);
    } on Exception catch (_) {}
    final tillName = await _boundTillName(_bridge);
    if (_disposed) return;
    state = state.copyWith(tillName: tillName);
    try {
      final orders = await _bridge.listShiftOrders();
      final stats = await _bridge.shiftStats(orders: orders);
      if (!_disposed) state = state.copyWith(orderCount: stats.orderCount);
    } on Exception catch (_) {}
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
/// kind + amount + note, and the busy / error pair.
///
/// Four kinds now that the bridge carries one: pay in, pay out, safe drop and
/// correction. The sign alone could not tell them apart — a safe drop and a
/// pay-out are both money leaving the drawer, and only one of them is money
/// leaving the business, so the Z-report counted the night's takings going to
/// the safe as spend. A correction names the movement it reverses, so a
/// mis-keyed 500 and its fix net to nothing instead of reading as 1,000 of
/// drawer activity.
@immutable
class CashMovementsState {
  /// Creates the cash-movements state.
  const CashMovementsState({
    this.movements = const [],
    this.loading = false,
    this.isIn = false,
    this.kind = 'pay_out',
    this.corrects,
    this.amountMinor = 0,
    this.note = '',
    this.busy = false,
    this.error,
  });

  /// The open shift's movements (server rows merged with queued ones).
  final List<CashMovementView> movements;

  /// The ledger list is loading.
  final bool loading;

  /// Record form: pay-in (true) or pay-out. Pay-out is the default — it is
  /// the movement a shift actually makes (milk, change, a courier), and the
  /// one the design leads with.
  final bool isIn;

  /// `pay_in` | `pay_out` | `safe_drop` | `correction`.
  final String kind;

  /// The movement this one reverses, when [kind] is `correction`.
  final String? corrects;

  /// Record form: the amount, minor units.
  final int amountMinor;

  /// Record form: what the money was for. Required — a movement with no
  /// note is the phantom cash the report used to show.
  final String note;

  /// A recordCashMovement call is in flight.
  final bool busy;

  /// The last record error (human message), or null.
  final String? error;

  /// The Record CTA is enabled: an amount, a note, nothing in flight.
  bool get canRecord => amountMinor > 0 && note.trim().isNotEmpty && !busy;

  /// Copies with the given overrides ([error] clears through the sentinel).
  CashMovementsState copyWith({
    List<CashMovementView>? movements,
    bool? loading,
    bool? isIn,
    String? kind,
    String? corrects,
    int? amountMinor,
    String? note,
    bool? busy,
    Object? error = _unset,
  }) {
    return CashMovementsState(
      movements: movements ?? this.movements,
      loading: loading ?? this.loading,
      isIn: isIn ?? this.isIn,
      kind: kind ?? this.kind,
      corrects: corrects ?? this.corrects,
      amountMinor: amountMinor ?? this.amountMinor,
      note: note ?? this.note,
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
  void setDirection({required bool isIn}) =>
      state = state.copyWith(isIn: isIn, kind: isIn ? 'pay_in' : 'pay_out');

  /// Pick what the movement IS. A safe drop and a correction both take money
  /// out; `corrects` is cleared when the kind is no longer a correction, so a
  /// stale id cannot ride along on an ordinary pay-out.
  void setKind(String kind, {String? corrects}) => state = state.copyWith(
    kind: kind,
    isIn: kind == 'pay_in',
    corrects: kind == 'correction' ? corrects : null,
  );

  /// The teller edited the amount.
  void setAmount(int minor) => state = state.copyWith(amountMinor: minor);

  /// The teller edited the note.
  void setNote(String note) => state = state.copyWith(note: note);

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
  /// the form only on success — the natives' `recordCashMovement`. Returns
  /// true on success so the screen can clear its note field; the drawer's
  /// expected cash moved, so the shell refreshes here.
  Future<bool> record() async {
    if (!state.canRecord) return false;
    final shell = ref.read(shellProvider.notifier);
    state = state.copyWith(busy: true, error: null);
    try {
      // A safe drop and a correction-of-a-pay-in both leave the drawer; the
      // sign follows the money, the kind says what it means.
      final signed = state.isIn ? state.amountMinor : -state.amountMinor;
      await _bridge.recordCashMovement(
        amountMinor: signed,
        note: state.note.trim(),
        kind: state.kind,
        corrects: state.corrects,
      );
      await load();
      if (_disposed) return false;
      state = state.copyWith(busy: false, amountMinor: 0, note: '');
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
