/// The till feature's Riverpod spine — one `Notifier` per surface, mirroring
/// the natives' per-screen state: the Till home (the drawer's figures and
/// every drawer at the branch for a manager), the open-till form (prefill +
/// connectivity heartbeat), the close-till count (expected drawer +
/// variance), the cash in/out ledger, the till-history list (+ per-row
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

/// ESC/POS character columns (natives: renderTillReport(..., 32u, ...)).
const int _printWidth = 32;

/// copyWith sentinel so nullable fields can be cleared explicitly.
const Object _unset = Object();

/// A bridge failure in the core's words, for a load that failed.
UiText _failure(Object e) =>
    e is MadarError ? UiText.error(e) : const UiText.key('err.generic');

/// The person's till on this device, from the core's cache. Tolerates the
/// bridge answering synchronously or not.
Future<TillView?> _cachedTill(MadarBridge bridge) =>
    Future<TillView?>.sync(() => bridge.currentTill());

/// The device's till: server-fresh when online, the local cache otherwise —
/// and never let a transient refresh error nuke a good local till.
Future<TillView?> _deviceTill(MadarBridge bridge) async {
  if (bridge.currentSession()?.online ?? false) {
    try {
      return await bridge.refreshTill();
    } on Exception catch (_) {}
  }
  try {
    return await _cachedTill(bridge);
  } on Exception catch (_) {
    return null;
  }
}

// ─── Till home ───────────────────────────────────────────────────────────────

/// The Till tab's state: the drawer (till + till name), this till's
/// headline figures (sales from the queue-merged orders, cash in till from the
/// report), the movement ledger, and — for a manager — every drawer at the
/// branch.
@immutable
class TillState {
  /// Creates the Till state.
  const TillState({
    this.loading = true,
    this.till,
    this.branchTills = const [],
    this.notice,
    this.forceClosingId,
    this.report,
    this.stats,
    this.queuedOrders = 0,
    this.movements = const [],
    this.online = true,
    this.isManager = false,
    this.canForceClose = false,
    this.drawers = const [],
    this.drawerReportLoadingId,
    this.toast,
    this.printingX = false,
  });

  /// An X report is being fetched and sent — a second tap is ignored.
  final bool printingX;

  /// The first load has not resolved the till yet.
  final bool loading;

  /// The device's till — null when no till is open on this till.
  final TillView? till;

  /// Every open till at the branch (server list merged with LAN adverts by
  /// the core), this device's first.
  final List<BranchOpenTillView> branchTills;

  /// Bills left open at the branch (null when there are none).
  final OpenBillsNoticeView? notice;

  /// The till a manager is force-closing (row spinner), or null.
  final String? forceClosingId;

  /// This till's report (expected cash, per-method lines); null while it
  /// loads or when the till is not open.
  final TillReportView? report;

  /// Sales total + order count over the queue-merged orders (voids
  /// excluded); null until loaded.
  final TillStatsView? stats;

  /// How many of this till's orders are still in the outbox.
  final int queuedOrders;

  /// The open till's cash movements, newest first.
  final List<CashMovementView> movements;

  /// The device is online (the honest-figures flag on the stat cards).
  final bool online;

  /// The signed-in person sees every drawer at the branch
  /// (`till.read.branch`).
  final bool isManager;

  /// The signed-in person may force-close another device's till
  /// (`till.force_close`).
  final bool canForceClose;

  /// Every till at the branch (managers only): open ones first.
  final List<TillSummaryView> drawers;

  /// The drawer whose report is being fetched (row spinner), or null.
  final String? drawerReportLoadingId;

  /// The latest failure toast, or null.
  final ToastData? toast;

  /// A till is open on this till.
  bool get hasOpenTill => till?.isOpen ?? false;

  /// Copies with the given overrides (nullables clear through the sentinel).
  TillState copyWith({
    bool? loading,
    Object? till = _unset,
    List<BranchOpenTillView>? branchTills,
    Object? notice = _unset,
    Object? forceClosingId = _unset,
    Object? report = _unset,
    Object? stats = _unset,
    int? queuedOrders,
    List<CashMovementView>? movements,
    bool? online,
    bool? isManager,
    bool? canForceClose,
    List<TillSummaryView>? drawers,
    Object? drawerReportLoadingId = _unset,
    Object? toast = _unset,
    bool? printingX,
  }) {
    return TillState(
      printingX: printingX ?? this.printingX,
      loading: loading ?? this.loading,
      till: till == _unset ? this.till : till as TillView?,
      branchTills: branchTills ?? this.branchTills,
      notice: notice == _unset ? this.notice : notice as OpenBillsNoticeView?,
      forceClosingId: forceClosingId == _unset
          ? this.forceClosingId
          : forceClosingId as String?,
      report: report == _unset ? this.report : report as TillReportView?,
      stats: stats == _unset ? this.stats : stats as TillStatsView?,
      queuedOrders: queuedOrders ?? this.queuedOrders,
      movements: movements ?? this.movements,
      online: online ?? this.online,
      isManager: isManager ?? this.isManager,
      canForceClose: canForceClose ?? this.canForceClose,
      drawers: drawers ?? this.drawers,
      drawerReportLoadingId: drawerReportLoadingId == _unset
          ? this.drawerReportLoadingId
          : drawerReportLoadingId as String?,
      toast: toast == _unset ? this.toast : toast as ToastData?,
    );
  }
}

/// The Till tab's controller. Loads the drawer on entry and again whenever
/// the shell's truth moves (a till opened or closed, a re-login) or the
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
      ..listen(connectivityPulseProvider, (_, _) => unawaited(refresh()))
      // The drawer moved (a pay in/out, a sale, refund, void) without the
      // route or session changing — the shell listener above never fires
      // for it, which left expected cash stale until a screen change.
      ..listen(drawerTickProvider, (_, _) => unawaited(refresh()));
    unawaited(Future<void>.microtask(refresh));
    return TillState(
      isManager: _bridge.can(cap: Cap.tillReadBranch),
      canForceClose: _bridge.can(cap: Cap.tillForceClose),
    );
  }

  /// Reload everything the tab shows. The figures load in parallel; each
  /// degrades on its own so one failing call cannot blank the tab.
  Future<void> refresh() async {
    final isManager = _bridge.can(cap: Cap.tillReadBranch);
    final till = await _deviceTill(_bridge);
    if (_disposed) return;
    final open = till?.isOpen ?? false;
    final (
      branchTills,
      report,
      orders,
      movements,
      drawers,
      sync,
      notice,
    ) = await (
      _quiet(_bridge.branchOpenTills),
      open ? _quiet(_bridge.tillReport) : Future<TillReportView?>.value(),
      open
          ? _quiet(_bridge.listTillOrders)
          : Future<List<OrderSummaryView>?>.value(),
      open
          ? _quiet(_bridge.listCashMovements)
          : Future<List<CashMovementView>?>.value(),
      isManager
          ? _quiet(_bridge.listTills)
          : Future<List<TillSummaryView>?>.value(),
      _quiet(() async => _bridge.syncStatus()),
      _quiet(_bridge.openBillsNotice),
    ).wait;
    if (_disposed) return;
    // Stats are computed in the core over the orders the till just listed —
    // the same queue-merged set the Orders row counts.
    TillStatsView? stats;
    if (orders != null) {
      stats = await _quiet(() => _bridge.tillStats(orders: orders));
      if (_disposed) return;
    }
    final branchDrawers = drawers ?? const <TillSummaryView>[];
    state = state.copyWith(
      loading: false,
      till: till,
      branchTills: branchTills ?? const [],
      notice: notice,
      report: report,
      stats: stats,
      queuedOrders: orders?.where((o) => o.queued).length ?? 0,
      movements: movements ?? const [],
      online: sync?.online ?? state.online,
      isManager: isManager,
      canForceClose: _bridge.can(cap: Cap.tillForceClose),
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
  Future<TillReportView?> fetchDrawerReport(String tillId) async {
    if (state.drawerReportLoadingId != null) return null;
    state = state.copyWith(drawerReportLoadingId: tillId);
    try {
      final report = await _bridge.tillReportFor(tillId: tillId);
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

  /// A manager force-closes another person's till from the branch list
  /// (they left it open on a device nobody can reach). Returns true on
  /// success; the list re-reads either way.
  Future<bool> forceClose(String tillId, String reason) async {
    if (state.forceClosingId != null) return false;
    state = state.copyWith(forceClosingId: tillId);
    try {
      await _bridge.forceCloseTill(tillId: tillId, reason: reason);
      if (_disposed) return true;
      state = state.copyWith(forceClosingId: null);
      await refresh();
      return true;
    } on Exception catch (e) {
      if (_disposed) return false;
      _toastSeq += 1;
      state = state.copyWith(
        forceClosingId: null,
        toast: ToastData(
          id: _toastSeq,
          text: _failure(e).of(_bridge),
          tone: ChipTone.danger,
          icon: 'xmark.circle',
        ),
      );
      return false;
    }
  }

  /// Print the X report — the mid-till read — straight to the bound
  /// printer, with no screen in between.
  ///
  /// Tapping "Print X" used to open the preview sheet, so the one control
  /// literally labelled *Print* did not print: it took two more taps. The
  /// preview is still there on a long press, for the times the shape wants
  /// checking before paper is spent on it, but the tap does what it says.
  ///
  /// Summary only, never the per-order breakdown: an X mid-till is a read
  /// of the drawer, and the expanded form belongs to the Z at close.
  ///
  /// The report is read FRESH at the tap, never the one cached on the tab:
  /// a tap while the tab was still loading used to do nothing, and a tap
  /// after a sale printed the drawer as it stood at the last reload. A tap
  /// while one is already printing is ignored instead of printing twice.
  Future<void> printX() async {
    if (state.printingX) return;
    final tx = ref.read(printerServiceProvider).activeTransport();
    if (tx == null) {
      _tillToast('receipt.no_printer', tone: ChipTone.warning, icon: 'printer');
      return;
    }
    state = state.copyWith(printingX: true);
    final config = _bridge.deviceConfig();
    try {
      final report = await _bridge.tillReport();
      final bytes = await _bridge.renderTillReport(
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
        state = state.copyWith(report: report, printingX: false);
        _tillToast(
          'receipt.printed',
          tone: ChipTone.success,
          icon: 'checkmark.circle',
        );
      }
    } on Exception catch (_) {
      if (!_disposed) {
        state = state.copyWith(printingX: false);
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
    } on Object catch (_) {
      return null;
    }
  }
}

/// Till tab state (auto-disposed with the tab so a re-entry reloads).
final NotifierProvider<TillNotifier, TillState> tillProvider =
    NotifierProvider.autoDispose<TillNotifier, TillState>(TillNotifier.new);

// ─── Open till ──────────────────────────────────────────────────────────────

/// Open-till form state: the count, the carried-over suggestion, the busy /
/// error pair, and the top-pinned connectivity chrome.
@immutable
class OpenTillState {
  /// Creates the open-till state.
  const OpenTillState({
    this.openingMinor = 0,
    this.suggestedMinor = 0,
    this.busy = false,
    this.error,
    this.online = true,
    this.authPaused = false,
    this.elsewhere,
    this.notice,
    this.isManager = false,
    this.forceClosing = false,
  });

  /// The person's till is open on ANOTHER device (the server or a LAN peer
  /// said so): opening here is blocked until it is closed there — or a
  /// manager force-closes it. Null when nothing blocks.
  final TillElsewhereView? elsewhere;

  /// Bills left open at the branch since the last till closed, or null when
  /// there are none.
  final OpenBillsNoticeView? notice;

  /// The signed-in person may force-close a till from another device.
  final bool isManager;

  /// A force-close is in flight.
  final bool forceClosing;

  /// The teller's opening count, minor units.
  final int openingMinor;

  /// Carried-over suggestion (previous declared closing), minor units.
  final int suggestedMinor;

  /// An openTill call is in flight.
  final bool busy;

  /// The last submit error (human message), or null.
  final UiText? error;

  /// Connectivity chrome: the device is online.
  final bool online;

  /// Connectivity chrome: sync paused on a genuine session expiry.
  final bool authPaused;

  /// The count deviates from the carried-over closing → a reason is required.
  bool get needsReason => suggestedMinor > 0 && openingMinor != suggestedMinor;

  /// Copies with the given overrides ([error] clears through the sentinel).
  OpenTillState copyWith({
    int? openingMinor,
    int? suggestedMinor,
    bool? busy,
    Object? error = _unset,
    bool? online,
    bool? authPaused,
    Object? elsewhere = _unset,
    Object? notice = _unset,
    bool? isManager,
    bool? forceClosing,
  }) {
    return OpenTillState(
      elsewhere: elsewhere == _unset
          ? this.elsewhere
          : elsewhere as TillElsewhereView?,
      notice: notice == _unset ? this.notice : notice as OpenBillsNoticeView?,
      isManager: isManager ?? this.isManager,
      forceClosing: forceClosing ?? this.forceClosing,
      openingMinor: openingMinor ?? this.openingMinor,
      suggestedMinor: suggestedMinor ?? this.suggestedMinor,
      busy: busy ?? this.busy,
      error: error == _unset ? this.error : error as UiText?,
      online: online ?? this.online,
      authPaused: authPaused ?? this.authPaused,
    );
  }
}

/// The open-till surface controller. On entry it reconciles the device's
/// till (adopting an already-open one — hand-off to the shell) and primes the
/// carried-over prefill. Connectivity is reflected app-wide via the
/// ConnectivityService pulse — no screen-local polling.
class OpenTillNotifier extends Notifier<OpenTillState> {
  bool _disposed = false;
  late MadarBridge _bridge;

  @override
  OpenTillState build() {
    _bridge = ref.read(bridgeProvider);
    ref
      ..onDispose(() => _disposed = true)
      // Reflect the core's online/sync state whenever the app-wide
      // ConnectivityService re-checks (OS network change / resume / a failed
      // request) and pulses — without a screen-local poll. A teller who landed
      // here offline re-adopts their active till on the offline→online edge.
      ..listen(connectivityPulseProvider, (_, _) {
        unawaited(_reflectStatus());
      });
    // Prime the prefill on entry (reconcile FIRST — it adopts an already-open
    // till so a teller who lands here never opens a SECOND till on top of a
    // live one), plus a one-time connectivity refresh so freshly-entered state
    // is accurate. Kicked off a microtask late so build() finishes first.
    unawaited(
      Future<void>.microtask(() {
        unawaited(_prime());
        unawaited(refreshConnectivity());
      }),
    );
    return OpenTillState(
      // Offered only to someone who may force-close a till elsewhere.
      isManager: _bridge.can(cap: Cap.tillForceClose),
    );
  }

  /// Reflect the core's CURRENT online/sync state into the chrome WITHOUT
  /// pinging — the app-level ConnectivityService already refreshed the core
  /// and pulsed us. Reconciles the till on an offline→online edge.
  Future<void> _reflectStatus() async {
    if (_bridge.currentSession() == null) return;
    final wasOnline = state.online;
    SyncStatusView? status;
    try {
      status = _bridge.syncStatus();
    } on Exception catch (_) {}
    if (_disposed || status == null) return;
    state = state.copyWith(
      online: status.online,
      authPaused: status.authPaused,
    );
    if (!wasOnline && status.online) {
      await _reconcileTill();
      await _checkElsewhere();
    }
  }

  /// The teller edited the count.
  void setAmount(int minor) => state = state.copyWith(openingMinor: minor);

  Future<void> _prime() async {
    await _reconcileTill();
    if (_disposed) return;
    await (_loadPrefill(), _checkElsewhere(), _loadNotice()).wait;
  }

  /// Ask the core whether this person's till is already open on another
  /// device — the server when online, LAN peers otherwise. Answering "no"
  /// when neither can say is the core's call (opening is then allowed and
  /// marked unverified); the screen only shows what it is told.
  Future<void> _checkElsewhere() async {
    TillElsewhereView? elsewhere;
    try {
      elsewhere = await _bridge.checkTillElsewhere();
    } on Object catch (_) {
      return;
    }
    if (_disposed) return;
    state = state.copyWith(elsewhere: elsewhere);
  }

  /// "N bills left open since …" — bills belong to the branch and outlive a
  /// till, so the next person to open one is told. Null when none.
  Future<void> _loadNotice() async {
    OpenBillsNoticeView? notice;
    try {
      notice = await _bridge.openBillsNotice();
    } on Object catch (_) {
      return;
    }
    if (_disposed) return;
    state = state.copyWith(notice: notice);
  }

  /// A manager closes the till left open on the other device, from here, so
  /// this person can open one on this device. [reason] goes on the record.
  Future<void> forceCloseElsewhere(String reason) async {
    final other = state.elsewhere;
    if (other == null || state.forceClosing) return;
    state = state.copyWith(forceClosing: true, error: null);
    try {
      await _bridge.forceCloseTill(tillId: other.tillId, reason: reason);
      if (_disposed) return;
      state = state.copyWith(forceClosing: false, elsewhere: null);
      await _checkElsewhere();
    } on MadarError catch (e) {
      if (_disposed) return;
      state = state.copyWith(forceClosing: false, error: UiText.error(e));
    } on Exception catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        forceClosing: false,
        error: const UiText.key('err.generic'),
      );
    }
  }

  /// Reconcile the device's till with the server when online (existing till
  /// on login, dashboard force-close); use the local cache offline. Never let
  /// a transient refresh error nuke a good local till — fall back to the
  /// cache. Adopting an open till moves `app_route()` → hand off to the
  /// shell.
  Future<void> _reconcileTill() async {
    final shell = ref.read(shellProvider.notifier);
    TillView? till;
    if (_bridge.currentSession()?.online ?? false) {
      try {
        till = await _bridge.refreshTill();
      } on Exception catch (_) {
        till = await _currentTillOrNull();
      }
    } else {
      till = await _currentTillOrNull();
    }
    if (till?.isOpen ?? false) shell.refresh();
  }

  Future<TillView?> _currentTillOrNull() async {
    try {
      return await _cachedTill(_bridge);
    } on Exception catch (_) {
      return null;
    }
  }

  /// Prime the open-till form: show the locally-cached carried-over
  /// suggestion instantly, then refresh it from the server (last synced
  /// declared closing) when online. Seed the count once while still
  /// untouched.
  Future<void> _loadPrefill() async {
    var suggested = await _readSuggested();
    if (_disposed) return;
    _applySuggested(suggested);
    if (_bridge.currentSession()?.online ?? false) {
      try {
        await _bridge.refreshTill();
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
  /// authoritative till (the core drained the backlog during the ping).
  Future<void> refreshConnectivity() async {
    if (_bridge.currentSession() == null) return;
    final wasOnline = state.online;
    try {
      await _bridge.refreshConnectivity();
    } on Exception catch (_) {}
    SyncStatusView? status;
    try {
      status = _bridge.syncStatus();
    } on Exception catch (_) {}
    if (_disposed) return;
    if (status != null) {
      state = state.copyWith(
        online: status.online,
        authPaused: status.authPaused,
      );
    }
    if (!wasOnline && state.online) await _reconcileTill();
  }

  /// Open the till with the current count (+ [reason] when the count
  /// deviates from the carry-over). A successful open moves `app_route()` —
  /// the shell hand-off happens here.
  Future<void> submit({required String reason}) async {
    if (state.needsReason && reason.trim().isEmpty) {
      // Guidance next to the action that triggers it — the natives' flagError.
      state = state.copyWith(
        error: const UiText.key('till.opening_reason_required'),
      );
      return;
    }
    final shell = ref.read(shellProvider.notifier);
    state = state.copyWith(busy: true, error: null);
    try {
      final outcome = await _bridge.openTill(
        openingCashMinor: state.openingMinor,
        openingReason: state.needsReason ? reason : null,
      );
      // Still open on another device: nothing was opened here. Say where,
      // and stay on this screen.
      if (outcome.openElsewhere case final other?) {
        if (!_disposed) {
          state = state.copyWith(busy: false, elsewhere: other);
        }
        return;
      }
      if (!_disposed) state = state.copyWith(busy: false, elsewhere: null);
      shell.refresh();
    } on MadarError catch (e) {
      if (_disposed) return;
      state = state.copyWith(busy: false, error: UiText.error(e));
    } on Exception catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        busy: false,
        error: const UiText.key('err.generic'),
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

/// Open-till surface state (auto-disposed with the screen so the heartbeat
/// stops and the form resets between visits).
final NotifierProvider<OpenTillNotifier, OpenTillState> openTillProvider =
    NotifierProvider.autoDispose<OpenTillNotifier, OpenTillState>(
      OpenTillNotifier.new,
    );

// ─── Close till ─────────────────────────────────────────────────────────────

/// One payment method's check at close: ticked Checked (the system total is
/// right), or Doesn't match with the amount the teller sees and a note.
@immutable
class MethodCheck {
  /// Creates a method check; no [status] means not answered yet.
  const MethodCheck({this.status, this.amountMinor, this.note = ''});

  /// `checked` | `disagreed`, or null while unanswered.
  final String? status;

  /// The amount the teller sees, when [status] is `disagreed`.
  final int? amountMinor;

  /// What happened, when [status] is `disagreed` (required then).
  final String note;

  /// The teller said it does not match.
  bool get disagrees => status == 'disagreed';

  /// A blind count: the amount the teller sees, compared by the core.
  bool get counted => status == 'counted';

  /// A disagreement still missing its amount.
  bool get missingAmount => disagrees && amountMinor == null;

  /// A disagreement still missing its note.
  bool get missingNote => disagrees && note.trim().isEmpty;

  /// Answered completely: Checked, or a disagreement with amount and note.
  bool get complete =>
      status == 'checked' ||
      counted ||
      (disagrees && !missingAmount && !missingNote);

  /// Copies with the given overrides ([amountMinor] clears via the sentinel).
  MethodCheck copyWith({
    String? status,
    Object? amountMinor = _unset,
    String? note,
  }) => MethodCheck(
    status: status ?? this.status,
    amountMinor: amountMinor == _unset ? this.amountMinor : amountMinor as int?,
    note: note ?? this.note,
  );
}

/// Close-till state: the open till, its report (the expected drawer and its
/// arithmetic), the close preview (every payment method used on the till,
/// and whether this is the branch's last open till), the teller's cash
/// count, one check per non-cash method, and the busy / error pair.
@immutable
class CloseTillState {
  /// Creates the close-till state.
  const CloseTillState({
    this.countedMinor,
    this.busy = false,
    this.error,
    this.till,
    this.report,
    this.preview,
    this.checks = const {},
    this.attempted = false,
    this.orderCount,
    this.loadError,
    this.closedTillId,
    this.blind = false,
    this.figures,
  });

  /// The person counts blind (no `till.cash_spot_check`): no expected
  /// figures before the close; the report comes after it.
  final bool blind;

  /// The expected figures a one-time PIN unlocked on a blind close.
  final CloseTillPreviewView? figures;

  /// The teller's counted drawer, minor units — null until they enter one.
  /// It used to start at 0, so the screen said "Short by" the whole float
  /// before anybody had counted anything, and 0 plus a reason could close.
  final int? countedMinor;

  /// Why the report could not be read, or null. Without it the expected
  /// figure never arrives, so the close stays disabled — say why, and retry.
  final UiText? loadError;

  /// The till that was just closed — set on success so the screen can offer
  /// its Z report before leaving.
  final String? closedTillId;

  /// A closeTill call is in flight.
  final bool busy;

  /// The last close error (human message), or null.
  final UiText? error;

  /// The open till for the header (null while loading).
  final TillView? till;

  /// The report carrying the expected drawer (null while loading).
  final TillReportView? report;

  /// Every method used on this till + the last-till warning (null while it
  /// loads; the core computes it locally when offline).
  final CloseTillPreviewView? preview;

  /// The teller's answer per non-cash method, keyed by method.
  final Map<String, MethodCheck> checks;

  /// Close was tapped once: unanswered rows now say what they need.
  final bool attempted;

  /// How many sales this till rang (voids excluded), or null until known.
  final int? orderCount;

  /// The non-cash methods to check, in the core's order.
  List<CloseTillMethodView> get methodsToCheck => [
    for (final m in preview?.methods ?? const <CloseTillMethodView>[])
      if (!m.isCash) m,
  ];

  /// The answer for [method] (unanswered when none yet).
  MethodCheck checkFor(String method) => checks[method] ?? const MethodCheck();

  /// The count deviates from the system's expected drawer → a closing reason
  /// is required (the open screen's discrepancy pattern).
  bool get needsReason =>
      !blind &&
      report != null &&
      countedMinor != null &&
      countedMinor != report!.expectedCashMinor;

  /// A count has been entered and the expected drawer is known.
  bool get canClose =>
      (blind || report != null) && countedMinor != null && !busy;

  /// Copies with the given overrides (nullables clear through the sentinel).
  CloseTillState copyWith({
    Object? countedMinor = _unset,
    bool? busy,
    Object? error = _unset,
    Object? till = _unset,
    Object? report = _unset,
    Object? preview = _unset,
    Map<String, MethodCheck>? checks,
    bool? attempted,
    Object? orderCount = _unset,
    Object? loadError = _unset,
    Object? closedTillId = _unset,
    bool? blind,
    Object? figures = _unset,
  }) {
    return CloseTillState(
      blind: blind ?? this.blind,
      figures: figures == _unset
          ? this.figures
          : figures as CloseTillPreviewView?,
      countedMinor: countedMinor == _unset
          ? this.countedMinor
          : countedMinor as int?,
      loadError: loadError == _unset ? this.loadError : loadError as UiText?,
      closedTillId: closedTillId == _unset
          ? this.closedTillId
          : closedTillId as String?,
      busy: busy ?? this.busy,
      error: error == _unset ? this.error : error as UiText?,
      till: till == _unset ? this.till : till as TillView?,
      report: report == _unset ? this.report : report as TillReportView?,
      preview: preview == _unset
          ? this.preview
          : preview as CloseTillPreviewView?,
      checks: checks ?? this.checks,
      attempted: attempted ?? this.attempted,
      orderCount: orderCount == _unset ? this.orderCount : orderCount as int?,
    );
  }
}

/// The close-till surface controller — primes the till, its report and the
/// close preview on entry, holds the per-method checks, and performs the
/// close. Closing is never blocked by a disagreement: a difference is
/// recorded with its note, not refused.
class CloseTillNotifier extends Notifier<CloseTillState> {
  bool _disposed = false;
  late MadarBridge _bridge;

  @override
  CloseTillState build() {
    _bridge = ref.read(bridgeProvider);
    ref
      ..onDispose(() => _disposed = true)
      // Same drawer signal as the Till, so both read one expected figure.
      ..listen(drawerTickProvider, (_, _) => unawaited(_load()));
    unawaited(Future<void>.microtask(_load));
    return const CloseTillState();
  }

  /// The teller edited the count — null when they cleared it.
  void setCounted(int? minor) => state = state.copyWith(countedMinor: minor);

  /// The teller ticked Checked on [method].
  void markChecked(String method) => _setCheck(
    method,
    state.checkFor(method).copyWith(status: 'checked', amountMinor: null),
  );

  /// The teller said [method] does not match.
  void markDisagreed(String method) =>
      _setCheck(method, state.checkFor(method).copyWith(status: 'disagreed'));

  /// The amount the teller sees for [method].
  void setDeclared(String method, int? minor) => _setCheck(
    method,
    state.checkFor(method).copyWith(status: 'disagreed', amountMinor: minor),
  );

  /// A blind count of [method]: the amount the teller sees.
  void countMethod(String method, int? minor) => _setCheck(
    method,
    state.checkFor(method).copyWith(status: 'counted', amountMinor: minor),
  );

  /// The expected figures a one-time PIN unlocked.
  void showFigures(CloseTillPreviewView figures) =>
      state = state.copyWith(figures: figures);

  /// What happened with [method].
  void setMethodNote(String method, String note) =>
      _setCheck(method, state.checkFor(method).copyWith(note: note));

  void _setCheck(String method, MethodCheck check) =>
      state = state.copyWith(checks: {...state.checks, method: check});

  /// Load the report again after a failure.
  Future<void> retry() => _load();

  /// Prime the screen: the open till for the header (server-fresh when
  /// online, cache otherwise), the report for the expected drawer figures,
  /// the close preview for the methods to check, and the sales count.
  Future<void> _load() async {
    final till = await _deviceTill(_bridge);
    if (_disposed) return;
    final blind = !_bridge.tillFiguresVisible();
    state = state.copyWith(till: till, blind: blind);
    if (!blind) {
      try {
        final report = await _bridge.tillReport();
        if (!_disposed) {
          state = state.copyWith(report: report, loadError: null);
        }
      } on Exception catch (e) {
        if (!_disposed) state = state.copyWith(loadError: _failure(e));
      }
    }
    try {
      final preview = await _bridge.closeTillPreview();
      if (!_disposed) state = state.copyWith(preview: preview);
    } on Object catch (_) {
      // No preview: the count still closes; there is nothing to check.
    }
    try {
      final orders = await _bridge.listTillOrders();
      final stats = await _bridge.tillStats(orders: orders);
      if (!_disposed) state = state.copyWith(orderCount: stats.orderCount);
    } on Exception catch (_) {}
  }

  /// The words for what still stops [close], or null when it may go. A
  /// method left unanswered never stops it (the core records it as not
  /// reviewed — decision 11: closing is never blocked); a difference the
  /// teller started needs its amount and a note.
  UiText? _missing(String note) {
    if (state.countedMinor == null) {
      return const UiText.key('till.count_required');
    }
    if (state.needsReason && note.trim().isEmpty) {
      return const UiText.key('till.closing_reason_required');
    }
    for (final m in state.methodsToCheck) {
      final check = state.checkFor(m.method);
      if (check.missingAmount || check.missingNote) {
        return const UiText.key('till.reconcile_note_required');
      }
    }
    return null;
  }

  /// Close the till with the counted drawer (+ [note], REQUIRED when the
  /// count deviates) and each method's check. Returns true on success — the
  /// SCREEN then offers the Z report and hands off to the shell.
  ///
  /// [leaveHeldOpen]: the held-orders warning was answered "close anyway" (or
  /// there was nothing held); the core refuses otherwise while any are open.
  Future<bool> close({required String note, bool leaveHeldOpen = false}) async {
    if (state.busy) return false;
    final missing = _missing(note);
    if (missing != null) {
      state = state.copyWith(error: missing, attempted: true);
      return false;
    }
    final counted = state.countedMinor!;
    final tillId = state.till?.id;
    state = state.copyWith(busy: true, error: null, attempted: true);
    try {
      final trimmed = note.trim();
      await _bridge.closeTill(
        closingCashMinor: counted,
        cashNote: trimmed.isEmpty ? null : trimmed,
        reconciliation: [
          for (final m in state.methodsToCheck)
            if (state.checkFor(m.method) case final check
                when check.status != null)
              ReconciliationInput(
                method: m.method,
                status: check.status!,
                declaredAmountMinor: check.disagrees || check.counted
                    ? check.amountMinor
                    : null,
                note: check.disagrees ? check.note.trim() : null,
              ),
        ],
        leaveHeldOpen: leaveHeldOpen,
      );
      // The core emptied this person's carts with the till; screens re-read.
      ref.read(cartsClearedTickProvider.notifier).bump();
      if (!_disposed) {
        state = state.copyWith(busy: false, closedTillId: tillId);
      }
      return true;
    } on MadarError catch (e) {
      if (_disposed) return false;
      state = state.copyWith(busy: false, error: UiText.error(e));
      return false;
    } on Exception catch (_) {
      if (_disposed) return false;
      state = state.copyWith(
        busy: false,
        error: const UiText.key('err.generic'),
      );
      return false;
    }
  }
}

/// Close-till surface state (auto-disposed with the screen).
final NotifierProvider<CloseTillNotifier, CloseTillState> closeTillProvider =
    NotifierProvider.autoDispose<CloseTillNotifier, CloseTillState>(
      CloseTillNotifier.new,
    );

// ─── Cash movements ──────────────────────────────────────────────────────────

/// Cash in/out ledger state: the open till's movements, the record form's
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
    this.loadError,
  });

  /// Why the ledger could not be read, or null — never shown as "no
  /// movements".
  final UiText? loadError;

  /// The open till's movements (server rows merged with queued ones).
  final List<CashMovementView> movements;

  /// The ledger list is loading.
  final bool loading;

  /// Record form: pay-in (true) or pay-out. Pay-out is the default — it is
  /// the movement a till actually makes (milk, change, a courier), and the
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
  final UiText? error;

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
    Object? loadError = _unset,
  }) {
    return CashMovementsState(
      loadError: loadError == _unset ? this.loadError : loadError as UiText?,
      movements: movements ?? this.movements,
      loading: loading ?? this.loading,
      isIn: isIn ?? this.isIn,
      kind: kind ?? this.kind,
      corrects: corrects ?? this.corrects,
      amountMinor: amountMinor ?? this.amountMinor,
      note: note ?? this.note,
      busy: busy ?? this.busy,
      error: error == _unset ? this.error : error as UiText?,
    );
  }
}

/// The cash in/out surface controller — loads the ledger on entry and
/// records signed movements against the open till (OFFLINE-FIRST, queued
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

  /// The open till's cash movements — server rows merged with still-queued
  /// ones in the core. A failure keeps what was on screen and says so with a
  /// retry; an empty ledger and an unreadable one are not the same thing.
  Future<void> load() async {
    state = state.copyWith(loading: true);
    try {
      final movements = await _bridge.listCashMovements();
      if (_disposed) return;
      state = state.copyWith(
        movements: movements,
        loading: false,
        loadError: null,
      );
    } on Exception catch (e) {
      if (_disposed) return;
      state = state.copyWith(loading: false, loadError: _failure(e));
    }
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
      // The core's report already counts the movement (acked, or still
      // queued in the outbox) — tell every drawer surface to re-read it.
      ref.read(drawerTickProvider.notifier).bump();
      return true;
    } on MadarError catch (e) {
      if (_disposed) return false;
      state = state.copyWith(busy: false, error: UiText.error(e));
      return false;
    } on Exception catch (_) {
      if (_disposed) return false;
      state = state.copyWith(
        busy: false,
        error: const UiText.key('err.generic'),
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

// ─── Till history ───────────────────────────────────────────────────────────

/// Till-history state: the closed tills, the live till for pinning, the
/// per-row report-prefetch spinner, and the failure toast.
@immutable
class TillHistoryState {
  /// Creates the till-history state.
  const TillHistoryState({
    this.tills = const [],
    this.live,
    this.loading = false,
    this.reportLoadingId,
    this.expanded = const {},
    this.ordersByTill = const {},
    this.ordersLoadingId,
    this.toast,
    this.loadError,
    this.ordersErrors = const {},
  });

  /// Why the list could not be read, or null.
  final UiText? loadError;

  /// Per-till failures of the expanded orders panel (keyed by till id).
  final Map<String, UiText> ordersErrors;

  /// Past tills, newest first.
  final List<TillSummaryView> tills;

  /// The live till (for pinning on top), or null.
  final TillView? live;

  /// The list is loading.
  final bool loading;

  /// The till id whose Z-report is being prefetched (row spinner), or null.
  final String? reportLoadingId;

  /// Till ids whose inline orders panel is expanded.
  final Set<String> expanded;

  /// Lazily loaded per-till orders (keyed by till id); a present-but-empty
  /// list means "loaded, none".
  final Map<String, List<OrderSummaryView>> ordersByTill;

  /// The till id whose orders are being fetched (panel spinner), or null.
  final String? ordersLoadingId;

  /// The latest failure toast, or null.
  final ToastData? toast;

  /// Copies with the given overrides (nullables clear through the sentinel).
  TillHistoryState copyWith({
    List<TillSummaryView>? tills,
    Object? live = _unset,
    bool? loading,
    Object? reportLoadingId = _unset,
    Set<String>? expanded,
    Map<String, List<OrderSummaryView>>? ordersByTill,
    Object? ordersLoadingId = _unset,
    Object? toast = _unset,
    Object? loadError = _unset,
    Map<String, UiText>? ordersErrors,
  }) {
    return TillHistoryState(
      loadError: loadError == _unset ? this.loadError : loadError as UiText?,
      ordersErrors: ordersErrors ?? this.ordersErrors,
      tills: tills ?? this.tills,
      live: live == _unset ? this.live : live as TillView?,
      loading: loading ?? this.loading,
      reportLoadingId: reportLoadingId == _unset
          ? this.reportLoadingId
          : reportLoadingId as String?,
      expanded: expanded ?? this.expanded,
      ordersByTill: ordersByTill ?? this.ordersByTill,
      ordersLoadingId: ordersLoadingId == _unset
          ? this.ordersLoadingId
          : ordersLoadingId as String?,
      toast: toast == _unset ? this.toast : toast as ToastData?,
    );
  }
}

/// The till-history surface controller — loads the page on entry and
/// prefetches a tapped row's Z-report for the shared preview sheet.
class TillHistoryNotifier extends Notifier<TillHistoryState> {
  bool _disposed = false;
  int _toastSeq = 0;
  late MadarBridge _bridge;

  @override
  TillHistoryState build() {
    _bridge = ref.read(bridgeProvider);
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(load));
    return const TillHistoryState();
  }

  /// Past tills (newest first) + the live till for pinning. A failed list
  /// is an error with a retry, not "No tills yet".
  Future<void> load() async {
    state = state.copyWith(loading: true, loadError: null);
    List<TillSummaryView>? tills;
    UiText? failure;
    try {
      tills = await _bridge.listTills();
    } on Exception catch (e) {
      failure = _failure(e);
    }
    TillView? live;
    try {
      live = await _cachedTill(_bridge);
    } on Exception catch (_) {
      live = null;
    }
    if (_disposed) return;
    state = state.copyWith(
      tills: tills ?? state.tills,
      live: live,
      loading: false,
      loadError: failure,
    );
  }

  /// Prefetch a past till's Z-report via `tillReportFor` (spinner in the
  /// row's chevron slot, danger toast on failure — the natives'
  /// `openTillReportPreviewFor`). Returns null while another row is busy or
  /// on failure; the SCREEN presents the sheet with the result.
  Future<TillReportView?> fetchReport(String tillId) async {
    if (state.reportLoadingId != null) return null;
    state = state.copyWith(reportLoadingId: tillId);
    try {
      final report = await _bridge.tillReportFor(tillId: tillId);
      if (!_disposed) state = state.copyWith(reportLoadingId: null);
      return report;
    } on Exception catch (_) {
      if (_disposed) return null;
      _toastSeq += 1;
      state = state.copyWith(
        reportLoadingId: null,
        toast: ToastData(
          id: _toastSeq,
          text: _bridge.tr(key: 'till.report_load_failed'),
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

  /// Expand/collapse a past till's inline orders panel; the first expand
  /// lazy-loads that till's orders (row by row, printable).
  Future<void> toggleTillOrders(String tillId) async {
    final expanded = {...state.expanded};
    if (!expanded.add(tillId)) expanded.remove(tillId);
    state = state.copyWith(expanded: expanded);
    if (!expanded.contains(tillId) || state.ordersByTill.containsKey(tillId)) {
      return;
    }
    await loadTillOrders(tillId);
  }

  /// Fetch (or re-fetch after a failure) one past till's orders. A failure
  /// is kept per till so the panel says so and offers a retry, instead of
  /// "No orders in this till".
  Future<void> loadTillOrders(String tillId) async {
    state = state.copyWith(
      ordersLoadingId: tillId,
      ordersErrors: {...state.ordersErrors}..remove(tillId),
    );
    try {
      final orders = await _bridge.listOrdersForTill(tillId: tillId);
      if (_disposed) return;
      state = state.copyWith(
        ordersByTill: {...state.ordersByTill, tillId: orders},
        ordersLoadingId: null,
      );
    } on Exception catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        ordersErrors: {...state.ordersErrors, tillId: _failure(e)},
        ordersLoadingId: null,
      );
    }
  }

  /// Print a single order's receipt from an expanded till row — renders in
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

/// Till-history surface state (auto-disposed with the screen).
final NotifierProvider<TillHistoryNotifier, TillHistoryState>
tillHistoryProvider =
    NotifierProvider.autoDispose<TillHistoryNotifier, TillHistoryState>(
      TillHistoryNotifier.new,
    );

// ─── Z-report preview sheet ──────────────────────────────────────────────────

/// The natives' `PrintState` — the terminal print feedback the teller needs
/// (sent / no printer bound / unreachable).
enum TillPrintState {
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

/// The preview sheet's DATA identity: a pre-fetched [report] (close-till /
/// past tills) or null to load the current till's, plus the past-till
/// [tillId] for the lazy Orders section. Equality is identity on [report]
/// (one sheet presentation carries one report instance) + value on
/// [tillId], so the family key is stable across sheet rebuilds.
@immutable
class TillReportRequest {
  /// Creates the request.
  const TillReportRequest({this.report, this.tillId});

  /// A pre-fetched report, or null to load the current till's on entry.
  final TillReportView? report;

  /// Past-till id for the lazy Orders section (null → current till).
  final String? tillId;

  @override
  bool operator ==(Object other) =>
      other is TillReportRequest &&
      identical(other.report, report) &&
      other.tillId == tillId;

  @override
  int get hashCode => Object.hash(identityHashCode(report), tillId);
}

/// Z-report preview state: the report, the lazy-loaded orders, and the
/// terminal print feedback.
@immutable
class TillReportSheetState {
  /// Creates the preview state.
  const TillReportSheetState({
    this.report,
    this.orders,
    this.expanded = false,
    this.print = TillPrintState.idle,
    this.loadError,
    this.ordersError,
  });

  /// Why the report could not be read, or null (the sheet used to spin
  /// forever).
  final UiText? loadError;

  /// Why the orders section could not be read, or null.
  final UiText? ordersError;

  /// The rendered report (null while the current till's loads → skeleton).
  final TillReportView? report;

  /// The till's orders for the Orders section — null until first expanded
  /// (then null again = loading → skeleton rows); load failures degrade to
  /// the empty line.
  final List<OrderSummaryView>? orders;

  /// Whether the orders breakdown is expanded — OFF by default. Drives BOTH
  /// the on-screen preview and whether print includes the per-order section.
  final bool expanded;

  /// Print feedback.
  final TillPrintState print;

  /// Copies with the given overrides (nullables clear through the sentinel).
  TillReportSheetState copyWith({
    Object? report = _unset,
    Object? orders = _unset,
    bool? expanded,
    TillPrintState? print,
    Object? loadError = _unset,
    Object? ordersError = _unset,
  }) {
    return TillReportSheetState(
      loadError: loadError == _unset ? this.loadError : loadError as UiText?,
      ordersError: ordersError == _unset
          ? this.ordersError
          : ordersError as UiText?,
      report: report == _unset ? this.report : report as TillReportView?,
      orders: orders == _unset
          ? this.orders
          : orders as List<OrderSummaryView>?,
      expanded: expanded ?? this.expanded,
      print: print ?? this.print,
    );
  }
}

/// The preview sheet's controller — seeds the pre-fetched report (or loads
/// the current till's), lazy-loads the till's orders, and streams the
/// rendered Z-report to the configured network printer.
class TillReportNotifier extends Notifier<TillReportSheetState> {
  /// Creates the notifier for one family [arg].
  TillReportNotifier(this.arg);

  /// The presented request (a pre-fetched report, or the till to load).
  final TillReportRequest arg;

  bool _disposed = false;
  late MadarBridge _bridge;

  @override
  TillReportSheetState build() {
    _bridge = ref.read(bridgeProvider);
    ref.onDispose(() => _disposed = true);
    // Orders are NOT loaded until the teller expands the section (they add a
    // round trip + a lot of rows). Only the summary loads eagerly.
    if (arg.report == null) unawaited(Future<void>.microtask(_load));
    return TillReportSheetState(report: arg.report);
  }

  /// The current till's report — or, when the request names a till (a
  /// just-closed one), that till's.
  Future<void> _load() async {
    state = state.copyWith(loadError: null);
    try {
      final id = arg.tillId;
      final report = id == null
          ? await _bridge.tillReport()
          : await _bridge.tillReportFor(tillId: id);
      if (_disposed) return;
      state = state.copyWith(report: report);
    } on Exception catch (e) {
      if (!_disposed) state = state.copyWith(loadError: _failure(e));
    }
  }

  /// Retry a failed report or orders load.
  void retry() {
    if (state.report == null) unawaited(_load());
    if (state.expanded && state.orders == null) unawaited(_loadOrders());
  }

  /// Expand/collapse the orders breakdown. On first expand, lazy-load the
  /// till's orders — a past till via `listOrdersForTill`, the current
  /// till via the queue-merged `listTillOrders`.
  void toggleExpanded() {
    final next = !state.expanded;
    state = state.copyWith(expanded: next);
    if (next && state.orders == null) unawaited(_loadOrders());
  }

  Future<void> _loadOrders() async {
    state = state.copyWith(ordersError: null);
    try {
      final id = arg.tillId;
      final orders = id == null
          ? await _bridge.listTillOrders()
          : await _bridge.listOrdersForTill(tillId: id);
      if (!_disposed) state = state.copyWith(orders: orders);
    } on Exception catch (e) {
      if (!_disposed) state = state.copyWith(ordersError: _failure(e));
    }
  }

  /// Render the Z-report in the core and stream the bytes to the device's
  /// configured network printer — the natives' printReportView: no printer
  /// bound is a distinct state (not a failure), and the send is best-effort.
  Future<void> printReport() async {
    final report = state.report;
    if (report == null || state.print == TillPrintState.printing) return;
    final config = _bridge.deviceConfig();
    final tx = ref.read(printerServiceProvider).activeTransport();
    if (tx == null) {
      state = state.copyWith(print: TillPrintState.noPrinter);
      return;
    }
    state = state.copyWith(print: TillPrintState.printing);
    // Expanded means "print it with its orders": if they are still on their
    // way, wait for them rather than printing a Z without the section the
    // teller is looking at.
    if (state.expanded && state.orders == null) {
      await _loadOrders();
      if (_disposed) return;
      if (state.orders == null) {
        state = state.copyWith(print: TillPrintState.failed);
        return;
      }
    }
    try {
      final bytes = await _bridge.renderTillReport(
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
      if (!_disposed) state = state.copyWith(print: TillPrintState.printed);
    } on Exception catch (_) {
      if (!_disposed) state = state.copyWith(print: TillPrintState.failed);
    }
  }

  /// Print a SINGLE order's receipt from the till's orders list (per-order
  /// print in past tills). Reuses the footer print-feedback state so the
  /// teller sees sent / no-printer / failed just like the report print.
  Future<void> printOrder(OrderSummaryView order) async {
    if (state.print == TillPrintState.printing) return;
    final config = _bridge.deviceConfig();
    final tx = ref.read(printerServiceProvider).activeTransport();
    if (tx == null) {
      state = state.copyWith(print: TillPrintState.noPrinter);
      return;
    }
    state = state.copyWith(print: TillPrintState.printing);
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
      if (!_disposed) state = state.copyWith(print: TillPrintState.printed);
    } on Exception catch (_) {
      if (!_disposed) state = state.copyWith(print: TillPrintState.failed);
    }
  }
}

/// Z-report preview state, keyed per presentation (auto-disposed with the
/// sheet so print feedback resets between opens).
final NotifierProviderFamily<
  TillReportNotifier,
  TillReportSheetState,
  TillReportRequest
>
tillReportProvider = NotifierProvider.autoDispose
    .family<TillReportNotifier, TillReportSheetState, TillReportRequest>(
      TillReportNotifier.new,
    );
