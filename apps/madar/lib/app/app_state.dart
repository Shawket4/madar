import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:madar/app/host_vault.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Base URL override for dev builds:
/// `flutter run --dart-define=MADAR_API=http://192.168.1.10:8080`.
const _apiBase = String.fromEnvironment(
  'MADAR_API',
  defaultValue: 'https://api.madar-pos.cloud',
);
const _environment = String.fromEnvironment(
  'MADAR_ENV',
  defaultValue: 'prod',
);

/// Boot phase of the shell — splash renders until [AppPhase.ready].
enum AppPhase { booting, ready, failed }

/// The single app-scope state holder: owns the core handle, the host vault,
/// the session snapshot, and the derived route. The Dart mirror of the
/// natives' AppModel — NO business logic lives here; the core decides
/// online/offline, token custody, validation, and the route.
class MadarAppState extends ChangeNotifier {
  MadarAppState();

  MadarCore? _core;
  HostVault? _vault;
  StreamSubscription<VaultCommand>? _vaultSub;
  RealtimeSession? _realtime;
  StreamSubscription<RealtimeMessage>? _eventsSub;
  StreamSubscription<AlertCommand>? _alertsSub;

  /// Bumped on every realtime event whose type matches the board — screens
  /// (KDS / tickets / incoming) listen and reload. The natives' tick
  /// counters, folded into one notifier per board.
  final kitchenTick = ValueNotifier<int>(0);
  final ticketTick = ValueNotifier<int>(0);
  final deliveryTick = ValueNotifier<int>(0);

  /// The SSE connection state — drives the KDS header dot and the
  /// 'kds.reconnecting' banner (the natives' `realtimeConnected`).
  final realtimeConnected = ValueNotifier<bool>(true);

  /// The latest core-raised alert (localized text decided in Rust);
  /// the shell chrome shows it as a toast + plays the order chime.
  /// Paired with a monotonically increasing sequence so two identical
  /// consecutive commands (AlertCommand is a freezed value type — they
  /// compare equal) still notify listeners.
  final alert = ValueNotifier<(int, AlertCommand)?>(null);
  int _alertSeq = 0;

  /// Serializes secure-storage writes so Save/Clear land in emission
  /// order — concurrent platform-channel applies could otherwise persist
  /// a stale session blob after a sign-out.
  Future<void> _vaultQueue = Future<void>.value();

  AppPhase phase = AppPhase.booting;
  String? bootError;
  SessionSnapshot? session;
  AppRoute route = const AppRoute.deviceSetup();
  String locale = 'en';
  bool rtl = false;
  ThemeMode themeMode = ThemeMode.light;

  /// The live core — only valid once [phase] is ready.
  MadarCore get core => _core!;

  /// Boot: open the store, restore the persisted session, resolve the
  /// route. Any failure lands in [AppPhase.failed] with a human message.
  Future<void> boot() async {
    try {
      final vault = _vault = await HostVault.open();
      final docs = await getApplicationSupportDirectory();
      final core = _core = await MadarCore.start(
        config: MadarConfig(
          baseUrl: _apiBase,
          environment: _environment,
          dbPath: '${docs.path}${Platform.pathSeparator}madar.db',
          locale: vault.locale.isEmpty ? 'en' : vault.locale,
        ),
      );

      // Persist token custody changes the moment the core emits them —
      // chained so each write completes before the next begins.
      _vaultSub = core.attachVault((cmd) {
        // A failed write must not wedge the queue for later commands.
        _vaultQueue = _vaultQueue
            .then((_) => vault.apply(cmd))
            .catchError((Object _) {});
      });

      final blob = await vault.readBlob();
      if (blob != null) {
        session = await core.bridge.restoreSession(blob: blob);
      }

      themeMode = vault.themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light;
      _syncLocale();
      route = core.bridge.appRoute();
      phase = AppPhase.ready;
      unawaited(_ensureRealtime());
    } on Object catch (e) {
      bootError = e is MadarError && _core != null
          ? _core!.bridge.humanMessage(e)
          : '$e';
      phase = AppPhase.failed;
    }
    notifyListeners();
  }

  /// Localized string lookup — every UI string goes through the core.
  String tr(String key) => _core?.bridge.tr(key: key) ?? key;

  /// Re-read the route from the core after any state-changing call and
  /// rebuild the shell if it moved. Also (re)arms realtime — a login is
  /// exactly such a call, and the subscription is session-gated.
  void refreshRoute() {
    final next = core.bridge.appRoute();
    session = core.bridge.currentSession();
    if (next != route) {
      route = next;
    }
    unawaited(_ensureRealtime());
    notifyListeners();
  }

  /// Open the device's ONE session-level realtime subscription + the LAN
  /// relay — the natives' post-login lifecycle. Idempotent: the core no-ops
  /// while a subscription is alive; we only re-attach after sign-out tore
  /// ours down.
  Future<void> _ensureRealtime() async {
    if (session == null) {
      _realtime = null;
      return;
    }
    unawaited(core.bridge.lanStart().then((_) {}, onError: (_) {}));
    if (_realtime != null) return;
    try {
      final rt = _realtime = await core.startRealtime();
      _eventsSub = rt.events.listen(_onRealtimeEvent);
      _alertsSub = rt.alerts.listen((cmd) => alert.value = (++_alertSeq, cmd));
    } on Object {
      // Offline or already-subscribed — the connectivity heartbeat and the
      // next refreshRoute retry naturally.
      _realtime = null;
    }
  }

  void _onRealtimeEvent(RealtimeMessage message) {
    switch (message) {
      case RealtimeMessage_Event(:final eventType):
        if (eventType.startsWith('kitchen.')) kitchenTick.value++;
        if (eventType.startsWith('ticket.')) ticketTick.value++;
        if (eventType.startsWith('delivery.') ||
            eventType.startsWith('order.')) {
          deliveryTick.value++;
        }
      case RealtimeMessage_ConnectionChanged(:final connected):
        realtimeConnected.value = connected;
    }
  }

  void setLocale(String next) {
    core.bridge.setLocale(locale: next);
    _vault?.locale = next;
    _syncLocale();
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    _vault?.themeMode = mode == ThemeMode.dark ? 'dark' : 'light';
    notifyListeners();
  }

  void _syncLocale() {
    locale = core.bridge.locale();
    rtl = core.bridge.isRtl();
  }

  @override
  void dispose() {
    unawaited(_vaultSub?.cancel());
    unawaited(_eventsSub?.cancel());
    unawaited(_alertsSub?.cancel());
    kitchenTick.dispose();
    ticketTick.dispose();
    deliveryTick.dispose();
    realtimeConnected.dispose();
    alert.dispose();
    super.dispose();
  }
}
