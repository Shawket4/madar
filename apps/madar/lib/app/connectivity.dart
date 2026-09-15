import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// App-wide connectivity awareness — the "actual device state" layer, with NO
/// blanket polling.
///
/// The core owns the online/offline decision (a confirmed `/health` probe or a
/// real outbox ack) and self-marks offline the instant an outbox send fails.
/// This service asks the core to re-evaluate only on genuine signals — never on
/// a fixed timer that would hammer the server across a large fleet:
///   1. the OS network state changing (connectivity_plus) — instant,
///   2. the app resuming to the foreground,
///   3. a FAILED transport request (a provider caught `Offline`/`Transient`
///      and called [refresh]) — debounced so a burst becomes one probe.
///
/// The ONLY timer runs while the outbox has queued/failed work (a drain every
/// minute) or while the device is OFFLINE (a re-check every 20s, queue or no
/// queue). Both catch a SILENT recovery — the server returns with the link
/// never dropping, so no OS event fires. An online, idle fleet makes zero
/// polling traffic.
///
/// A reconnect shows at once: the fast `/health` probe flips the pill before
/// the drain and pull that follow, which can take minutes on a big backlog.
///
/// Each refresh bumps [onPulse] so connectivity-showing screens re-read; an
/// offline→online transition calls [onReconnect] so the app re-arms realtime +
/// LAN (a subscription that failed to start while offline retries there — the
/// job the removed 15s heartbeat used to do).
class ConnectivityService with WidgetsBindingObserver {
  ConnectivityService({
    required this.core,
    required this.onPulse,
    required this.onReconnect,
    this.onNetworkSignal,
  });

  final MadarCore core;
  final VoidCallback onPulse;
  final VoidCallback onReconnect;

  /// Any OS network change or app resume, online or not — the LAN relay
  /// needs no internet, so it retries on these rather than on [onReconnect].
  final VoidCallback? onNetworkSignal;

  /// Drain-probe cadence — active ONLY while the outbox has pending/failed
  /// rows; cancelled the moment it drains.
  static const _drainPeriod = Duration(seconds: 60);

  /// Recovery re-check while offline — one `/health` per offline device.
  static const _offlinePeriod = Duration(seconds: 20);

  /// A check already running — a second trigger joins it instead of racing
  /// it (two interleaved checks could each read the other's half-set state).
  bool _probing = false;

  /// Coalesce a burst of failed requests into a single `/health` probe.
  static const _debounce = Duration(seconds: 3);

  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _drainTimer;
  bool _online = true;
  bool _stopped = false;
  DateTime? _lastProbe;

  /// Begin observing. Fires an immediate probe so the state is fresh at boot.
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _sub = _connectivity.onConnectivityChanged.listen((_) {
      onNetworkSignal?.call();
      // Whether the OS reports a network or none, confirm with a real probe —
      // "connected" can still be a captive portal or an unreachable server.
      unawaited(_probe(force: true));
    });
    unawaited(_probe(force: true));
  }

  void dispose() {
    _stopped = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sub?.cancel());
    _drainTimer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onNetworkSignal?.call();
      unawaited(_probe(force: true));
    }
  }

  /// Re-check connectivity after a failed transport request. Registered on
  /// `connectivityRefreshProvider` at boot; debounced (see [_debounce]).
  void refresh() => unawaited(_probe(force: false));

  Future<void> _probe({required bool force}) async {
    if (_stopped) return;
    // Debounce failed-request probes so a storm of failures = one /health.
    final now = DateTime.now();
    if (!force &&
        _lastProbe != null &&
        now.difference(_lastProbe!) < _debounce) {
      return;
    }
    _lastProbe = now;

    if (_probing) return;
    _probing = true;
    try {
      await _check();
    } finally {
      _probing = false;
    }
  }

  Future<void> _check() async {
    final wasOnline = _online;
    // 1. The fast probe. A reachable server flips the pill to online NOW —
    //    the drain and pull that follow a reconnect can take minutes on a
    //    big backlog, and the pill used to wait for all of it.
    var reachable = false;
    try {
      reachable = await core.bridge.probeConnectivity();
    } on Object {
      reachable = false;
    }
    if (_stopped) return;
    if (reachable) {
      _online = true;
      onPulse();
      if (!wasOnline) onReconnect();
    }
    // 2. The full check: drains the backlog and pulls on a good link, and
    //    CONFIRMS offline (two unconfirmed failures) on a bad one.
    try {
      _online = await core.bridge.refreshConnectivity();
    } on Object {
      _online = false;
    }
    if (_stopped) return;
    onPulse();
    if (!wasOnline && _online && !reachable) onReconnect();
    _schedule();
  }

  /// The one timer. While there is queued work it drains every minute; while
  /// OFFLINE it re-checks every [_offlinePeriod] even with nothing queued —
  /// otherwise a server that comes back without the OS reporting a network
  /// change (Wi-Fi never dropped) leaves the pill reading offline until the
  /// app is resumed. Online with an empty queue: no timer, no traffic.
  void _schedule() {
    _drainTimer?.cancel();
    var pending = 0;
    var failed = 0;
    try {
      final status = core.bridge.syncStatus();
      pending = status.pendingOutbox;
      failed = status.deadOutbox;
    } on Object {
      // Leave the counts at zero; the offline branch still re-checks.
    }
    final next = !_online
        ? _offlinePeriod
        : (pending > 0 || failed > 0)
        ? _drainPeriod
        : null;
    if (next != null) {
      _drainTimer = Timer(next, () => unawaited(_probe(force: true)));
    }
  }
}
