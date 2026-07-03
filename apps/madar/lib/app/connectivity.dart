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
/// The ONLY timer is a drain probe that runs *solely while the outbox has
/// queued/failed work* — it catches a SILENT recovery (the server returns with
/// the link never dropping, so no OS event fires) and drains. An idle fleet
/// makes zero polling traffic.
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
  });

  final MadarCore core;
  final VoidCallback onPulse;
  final VoidCallback onReconnect;

  /// Drain-probe cadence — active ONLY while the outbox has pending/failed
  /// rows; cancelled the moment it drains.
  static const _drainPeriod = Duration(seconds: 60);

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
    if (state == AppLifecycleState.resumed) unawaited(_probe(force: true));
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

    final wasOnline = _online;
    var pending = 0;
    var failed = 0;
    try {
      _online = await core.bridge.refreshConnectivity();
      final status = await core.bridge.syncStatus();
      pending = status.pending;
      failed = status.failed;
    } on Object {
      _online = false;
    }
    if (_stopped) return;
    onPulse();
    // Offline→online: re-arm realtime/LAN (the removed heartbeat's other job).
    if (!wasOnline && _online) onReconnect();
    // Keep a timer alive ONLY while there's queued work to drain; each probe
    // reschedules the next until the outbox empties, then stops entirely.
    _drainTimer?.cancel();
    if (pending > 0 || failed > 0) {
      _drainTimer = Timer(_drainPeriod, () => unawaited(_probe(force: true)));
    }
  }
}
