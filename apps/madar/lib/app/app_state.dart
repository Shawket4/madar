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

      // Persist token custody changes the moment the core emits them.
      _vaultSub = core.attachVault((cmd) => unawaited(vault.apply(cmd)));

      final blob = await vault.readBlob();
      if (blob != null) {
        session = await core.bridge.restoreSession(blob: blob);
      }

      themeMode = vault.themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light;
      _syncLocale();
      route = core.bridge.appRoute();
      phase = AppPhase.ready;
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
  /// rebuild the shell if it moved.
  void refreshRoute() {
    final next = core.bridge.appRoute();
    session = core.bridge.currentSession();
    if (next != route) {
      route = next;
    }
    notifyListeners();
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
    super.dispose();
  }
}
