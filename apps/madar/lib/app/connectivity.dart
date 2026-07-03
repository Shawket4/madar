import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// App-wide connectivity awareness — the missing "actual device state" layer.
///
/// The core owns the online/offline decision (a confirmed `/health` probe or
/// a real outbox ack), but it only re-evaluates when the HOST asks. Before,
/// the only trigger was a 15s timer on the Order screen — so off that screen
/// connectivity went stale, and a dropped Wi-Fi was noticed only when the
/// next request timed out. This service drives `refreshConnectivity()` from
/// THREE signals, app-wide:
///   1. the OS network state changing (connectivity_plus) — instant,
///   2. the app resuming to the foreground,
///   3. an adaptive periodic probe — fast (30s) while offline or with a
///      pending outbox (recover / drain promptly), slow (5 min) when idle
///      and online (a battery-friendly safety net; the OS + resume signals
///      catch real transitions).
/// Each refresh bumps [onPulse] so connectivity-showing screens re-read.
class ConnectivityService with WidgetsBindingObserver {
  ConnectivityService({required this.core, required this.onPulse});

  final MadarCore core;
  final VoidCallback onPulse;

  static const _fastPeriod = Duration(seconds: 30);
  static const _idlePeriod = Duration(minutes: 5);

  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _timer;
  bool _online = true;
  bool _stopped = false;

  /// Begin observing. Fires an immediate probe so the state is fresh at boot.
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _sub = _connectivity.onConnectivityChanged.listen((_) {
      // Whether the OS reports a network or none, confirm with a real probe —
      // "connected" can still be a captive portal or an unreachable server.
      unawaited(_refresh());
    });
    unawaited(_refresh());
  }

  void dispose() {
    _stopped = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sub?.cancel());
    _timer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_stopped) return;
    var pending = 0;
    try {
      _online = await core.bridge.refreshConnectivity();
      pending = (await core.bridge.syncStatus()).pending;
    } on Object {
      _online = false;
    }
    if (_stopped) return;
    onPulse();
    _schedule(fast: !_online || pending > 0);
  }

  void _schedule({required bool fast}) {
    _timer?.cancel();
    _timer = Timer(
      fast ? _fastPeriod : _idlePeriod,
      () => unawaited(_refresh()),
    );
  }
}
