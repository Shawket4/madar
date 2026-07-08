import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` moved to the misc library in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
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
        retryLabel: bridge?.tr(key: 'sync.retry') ?? 'sync.retry',
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
    darkModeProvider.overrideWith(
      () => DarkModeNotifier(initialDark: boot.vault.themeMode == 'dark'),
    ),
    localePersisterProvider.overrideWithValue((locale) {
      boot.vault.locale = locale;
    }),
    themePersisterProvider.overrideWithValue(({required dark}) {
      boot.vault.themeMode = dark ? 'dark' : 'light';
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

  /// The `realtimeArmerProvider` hook — `ShellNotifier.refresh` calls it
  /// after every state-moving bridge call; the subscription is
  /// session-gated so it arms on login and disarms after sign-out.
  void call() => unawaited(_ensure());

  Future<void> _ensure() async {
    if (_core.bridge.currentSession() == null) {
      _realtime = null;
      return;
    }
    unawaited(_core.bridge.lanStart().then((_) {}, onError: (_) {}));
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
      case RealtimeMessage_Event(:final eventType):
        if (eventType.startsWith('kitchen.')) {
          _ref.read(kitchenTickProvider.notifier).bump();
        }
        if (eventType.startsWith('ticket.')) {
          _ref.read(ticketTickProvider.notifier).bump();
        }
        if (eventType.startsWith('delivery.') ||
            eventType.startsWith('order.')) {
          _ref.read(deliveryTickProvider.notifier).bump();
        }
      case RealtimeMessage_ConnectionChanged(:final connected):
        _ref.read(realtimeConnectedProvider.notifier).update(connected);
    }
  }

  void dispose() {
    unawaited(_events?.cancel());
    unawaited(_alerts?.cancel());
  }
}
