import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` moved to the misc library in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:madar/app/host_vault.dart';
import 'package:madar/app/lan_bonjour.dart';
import 'package:madar/app/lan_retry.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Base URL override for dev builds:
/// `flutter run --dart-define=MADAR_API=http://192.168.1.10:8080`.
const _apiBase = String.fromEnvironment(
  'MADAR_API',
  defaultValue: 'https://api.madar-pos.cloud',
);
const _environment = String.fromEnvironment('MADAR_ENV', defaultValue: 'prod');

/// This build's version as the platform bundle reports it (the pubspec
/// `version`), for the core's client header. `null` when the platform cannot
/// say (a test host without the plugin) — the core then falls back.
Future<String?> appVersion() async {
  try {
    final version = (await PackageInfo.fromPlatform()).version;
    return version.isEmpty ? null : version;
  } on Object {
    return null;
  }
}

/// What a successful boot yields: the live core handle + the host vault.
class BootData {
  const BootData({required this.core, required this.vault});

  final MadarCore core;
  final HostVault vault;
}

/// A failed boot — pre-localized where the core got far enough to
/// translate, raw otherwise (the natives' exact fallback).
class BootFailure implements Exception {
  const BootFailure({required this.message, required this.retryLabel});

  final String message;
  final String retryLabel;

  @override
  String toString() => message;
}

/// "Retry" before the core can translate anything — the boot failed, so
/// the core's tables may be unreachable. Bilingual on the device locale,
/// never a raw `sync.retry` key on screen.
String bootRetryFallback([String? languageCode]) {
  final code = languageCode ?? PlatformDispatcher.instance.locale.languageCode;
  return code == 'ar' ? 'إعادة المحاولة' : 'Retry';
}

/// The core's word for [key], or [fallback] when the core has none (a
/// missing key comes back as the key itself).
String _trOr(MadarBridge? bridge, String key, String fallback) {
  final word = bridge?.tr(key: key);
  return word == null || word.isEmpty || word == key ? fallback : word;
}

/// Boot: open the store, start the core, attach the vault command stream,
/// restore the persisted session. NO business logic lives here — the core
/// decides online/offline, token custody, validation, and the route.
class BootNotifier extends AsyncNotifier<BootData> {
  @override
  Future<BootData> build() async {
    MadarCore? core;
    try {
      final vault = await HostVault.open();
      final docs = await getApplicationSupportDirectory();
      core = await MadarCore.start(
        config: MadarConfig(
          baseUrl: _apiBase,
          environment: _environment,
          dbPath: '${docs.path}${Platform.pathSeparator}madar.db',
          locale: vault.locale.isEmpty ? 'en' : vault.locale,
          appVersion: await appVersion(),
        ),
      );

      // Session durability is core-owned now: one sync local read re-hydrates
      // the persisted session from the core's own store. No host vault, no
      // write-ordering queue — that whole class of race is gone.
      core.bridge.restoreSessionCached();
      // Persisted landscape flip — seed + wire the persister. The controller
      // is an app-global singleton (it spans both provider containers), so
      // it's wired directly rather than through an override.
      OrientationController.instance.persister = ({required landscapeRight}) {
        vault.landscapeRight = landscapeRight;
      };
      OrientationController.instance.restoreFlip(
        landscapeRight: vault.landscapeRight,
      );
      // Persisted tablet-cutoff override — same wiring shape as the flip.
      OrientationController.instance.thresholdPersister =
          ({required tabletThresholdInches}) {
            vault.tabletThresholdInches = tabletThresholdInches;
          };
      OrientationController.instance.restoreTabletThresholdInches(
        vault.tabletThresholdInches,
      );
      return BootData(core: core, vault: vault);
    } on Object catch (e) {
      final bridge = core?.bridge;
      throw BootFailure(
        message: e is MadarError && bridge != null
            ? bridge.humanMessage(e)
            : '$e',
        retryLabel: _trOr(bridge, 'sync.retry', bootRetryFallback()),
      );
    }
  }
}

final bootProvider = AsyncNotifierProvider<BootNotifier, BootData>(
  BootNotifier.new,
);

/// The READY-subtree overrides: the booted core + the host hooks (locale
/// and theme persistence into the vault, the session-gated realtime
/// armer). Installed on the fresh container that scopes `MadarShell`.
List<Override> readyScopeOverrides(BootData boot) {
  return [
    coreProvider.overrideWithValue(boot.core),
    // Boot-time theme seed as an OVERRIDE — never a mutation during build.
    // The vault keeps the choice by name (light · dark · system).
    themeChoiceProvider.overrideWith(
      () =>
          ThemeChoiceNotifier(initial: ThemeChoice.parse(boot.vault.themeMode)),
    ),
    motionChoiceProvider.overrideWith(
      () =>
          MotionChoiceNotifier(initial: MotionChoice.parse(boot.vault.motion)),
    ),
    motionChoicePersisterProvider.overrideWithValue((choice) {
      boot.vault.motion = choice.name;
    }),
    localePersisterProvider.overrideWithValue((locale) {
      boot.vault.locale = locale;
    }),
    themeChoicePersisterProvider.overrideWithValue((choice) {
      boot.vault.themeMode = choice.name;
    }),
    realtimeArmerProvider.overrideWith((ref) {
      final armer = RealtimeArmer(core: boot.core, ref: ref);
      ref.onDispose(armer.dispose);
      return armer.call;
    }),
  ];
}

/// Opens the device's ONE session-level realtime subscription + the LAN
/// relay — the natives' post-login lifecycle. Idempotent: the core no-ops
/// while a subscription is alive; we only re-attach after sign-out tore
/// ours down. Realtime events fan out through the app_core providers:
/// ticks bump the per-board counters, connection changes drive
/// [realtimeConnectedProvider], and core-raised alerts land in
/// [alertProvider] for the chrome's toast + chime.
class RealtimeArmer {
  RealtimeArmer({required MadarCore core, required Ref ref})
    : _core = core,
      _ref = ref;

  final MadarCore _core;
  final Ref _ref;

  RealtimeSession? _realtime;
  StreamSubscription<RealtimeMessage>? _events;
  StreamSubscription<AlertCommand>? _alerts;

  /// Keeps the LAN relay started while signed in (backoff 5s → 60s); a
  /// failed start used to be swallowed once and never retried.
  late final LanRetrier _lan = LanRetrier(
    start: _core.bridge.lanStart,
    isRunning: _core.bridge.lanActive,
    signedIn: () => _core.bridge.currentSession() != null,
    // Native Bonjour advertises + browses once the relay runs (the iPad's
    // only discovery path; a second one everywhere else).
    onStarted: () => unawaited(_bonjour.ensure()),
  );
  late final LanBonjour _bonjour = LanBonjour(bridge: _core.bridge);
  late final TableChangeWatcher _tables = TableChangeWatcher(
    subscribe: _core.bridge.watchTables,
    apply: (tables) => applyTableChanges(_ref, tables),
  );

  /// The `realtimeArmerProvider` hook — `ShellNotifier.refresh` calls it
  /// after every state-moving bridge call; the subscription is
  /// session-gated so it arms on login and disarms after sign-out.
  void call() => unawaited(_ensure());

  Future<void> _ensure() async {
    // The core's table-change stream drives every board re-read: a pull that
    // landed, a sale rung here, a peer's mirrored op, a realtime event. One
    // subscription for the app's life; it outlives sign-outs.
    // Resubscribes with backoff if the stream drops, and keeps the boards
    // re-reading while it is down (see TableChangeWatcher).
    _tables.start();
    if (_core.bridge.currentSession() == null) {
      _realtime = null;
      _lan.stop();
      unawaited(_bonjour.stop());
      return;
    }
    // Every arm (sign-in, shell refresh, network reconnect, app resume)
    // retries the LAN at once if it is not running yet.
    _lan.kick();
    if (_realtime != null) return;
    try {
      final rt = _realtime = await _core.startRealtime();
      _events = rt.events.listen(_onEvent);
      _alerts = rt.alerts.listen(
        (cmd) => _ref.read(alertProvider.notifier).emit(cmd),
      );
    } on Object {
      // Offline or already-subscribed — the connectivity heartbeat and the
      // next shell refresh retry naturally.
      _realtime = null;
    }
  }

  void _onEvent(RealtimeMessage message) {
    switch (message) {
      // Board re-reads ride the core's table-change stream: the core turns
      // every event (and the pull it nudges) into the tables it moves.
      case RealtimeMessage_Event():
        break;
      case RealtimeMessage_ConnectionChanged(:final connected):
        _ref.read(realtimeConnectedProvider.notifier).update(connected);
    }
  }

  void dispose() {
    _lan.dispose();
    unawaited(_bonjour.stop());
    _tables.dispose();
    unawaited(_events?.cancel());
    unawaited(_alerts?.cancel());
  }
}
