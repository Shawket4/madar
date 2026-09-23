import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staff_core/staff_core.dart';

/// Backend base URL. Override with
/// `--dart-define=MADAR_API=http://192.168.1.10:8082`.
const _apiBase = String.fromEnvironment(
  'MADAR_API',
  defaultValue: 'https://api.madar-pos.cloud',
);
const _environment = String.fromEnvironment('MADAR_ENV', defaultValue: 'prod');

/// Starts madar-core through the staff bridge — its own SQLite store, apart
/// from the POS and dashboard — and returns the root overrides: the core's
/// words, and the language and theme hooks that write through to the core
/// and the prefs store under the POS's own keys (`madar.locale`,
/// `madar.theme`). The `readyScopeOverrides` pattern of apps/madar.
Future<List<Override>> boot() async {
  final prefs = await SharedPreferences.getInstance();
  final dir = await getApplicationSupportDirectory();
  final saved = prefs.getString('madar.locale') ?? '';
  final core = await MadarCore.start(
    config: MadarConfig(
      baseUrl: _apiBase,
      environment: _environment,
      dbPath: '${dir.path}${Platform.pathSeparator}madar_staff.db',
      locale: saved.isEmpty ? 'ar' : saved, // Arabic first (APP-4)
    ),
  );
  words = (key) => core.bridge.tr(key: key);
  wordsIn = (lang, key) => core.bridge.trIn(locale: lang, key: key);
  final lang = core.bridge.locale().startsWith('ar') ? 'ar' : 'en';
  final backend = _BridgeBackend(core.bridge);
  final store = DawamStore(backend);
  await store.restore();
  final opened = ValueNotifier<String?>(null);
  final push = _Push(core.bridge, store, lang, opened);
  backend.beforeSignOut = push.forget;
  unawaited(push.start());
  return [
    openedPushProvider.overrideWithValue(opened),
    dawamProvider.overrideWith((ref) {
      ref.onDispose(store.stop);
      return store;
    }),
    localeProvider.overrideWith(() => LocaleNotifier(initial: lang)),
    localePersisterProvider.overrideWithValue((l) {
      core.bridge.setLocale(locale: l);
      unawaited(prefs.setString('madar.locale', l));
      push.language(l);
    }),
    themeChoiceProvider.overrideWith(
      () => ThemeChoiceNotifier(
        initial: ThemeChoice.parse(prefs.getString('madar.theme')),
      ),
    ),
    themeChoicePersisterProvider.overrideWithValue(
      (c) => unawaited(prefs.setString('madar.theme', c.name)),
    ),
  ];
}

/// Push notifications (APP-6). Once someone is signed in, the phone's FCM
/// token goes to the server with the language its pushes are written in; a
/// push that arrives while the app is open refreshes the picture; a tapped
/// push opens its screen; signing out forgets the token.
class _Push {
  _Push(this.bridge, this.store, this.lang, this.opened);

  final MadarBridge bridge;
  final DawamStore store;
  final ValueNotifier<String?> opened;
  String lang;
  String? _sent; // who|language last registered
  bool _on = false; // Firebase is configured on this build

  Future<void> start() async {
    try {
      // From the platform's own google-services.json / GoogleService-Info
      // .plist, which are git-ignored (public repo) and regenerated with
      // `flutterfire configure` — see the README. Missing: no push, and the
      // catch below keeps everything else working.
      await Firebase.initializeApp();
    } on Object {
      return; // no Firebase here: the in-app inbox still works
    }
    _on = true;
    final m = FirebaseMessaging.instance;
    // Shown while the app is open too, like the inbox badge.
    await m.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    m.onTokenRefresh.listen((_) => unawaited(_register(force: true)));
    FirebaseMessaging.onMessage.listen((_) => store.sync());
    // Tapped while the app ran in the background, or the tap that launched
    // it: refresh, and open the screen the push is about (06 B8).
    FirebaseMessaging.onMessageOpenedApp.listen(_opened);
    final first = await m.getInitialMessage();
    if (first != null) _opened(first);
    store.addListener(() {
      if (store.me == null) {
        _sent = null;
      } else {
        unawaited(_register());
      }
    });
    if (store.me != null) unawaited(_register());
  }

  void _opened(RemoteMessage msg) {
    store.sync();
    opened.value = msg.data['key'] as String?;
  }

  /// Signing out (06 B3): this phone's token is deleted at Firebase, so
  /// nothing more reaches it even if the server never heard the sign-out.
  Future<void> forget() async {
    _sent = null;
    if (!_on) return;
    try {
      await FirebaseMessaging.instance.deleteToken().timeout(
        const Duration(seconds: 5),
      );
    } on Object {
      // offline: the server-side revoke (or the next sign-in) covers it
    }
  }

  void language(String l) {
    lang = l;
    unawaited(_register());
  }

  Future<void> _register({bool force = false}) async {
    final key = '${store.me}|$lang';
    if (store.me == null || (!force && _sent == key)) return;
    _sent = key;
    try {
      final m = FirebaseMessaging.instance;
      final perm = await m.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      // iOS hands out an FCM token only once APNs has answered (never on
      // the simulator); the next change tries again.
      final token = await m.getToken();
      if (token == null) {
        _sent = null;
        return;
      }
      await bridge.dawamSetPushToken(token: token, locale: lang);
    } on Object {
      _sent = null;
    }
  }
}

/// The staff bridge behind the store: madar-core does every figure and
/// every action; this only carries calls across and reads the phone's GPS.
class _BridgeBackend implements DawamBackend {
  _BridgeBackend(this.bridge);

  final MadarBridge bridge;

  /// Runs before the core signs out (the push token is forgotten).
  Future<void> Function()? beforeSignOut;

  Future<T> _wrap<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on MadarError catch (e) {
      // A 403 carries the server's sentence in `action` (a limit, a scope).
      final text = switch (e) {
        MadarError_Forbidden(:final action) when action.isNotEmpty => action,
        _ => bridge.humanMessage(e),
      };
      if (e is MadarError_Unauthenticated) throw DawamSignedOut(text, text);
      throw DawamError(text, text);
    }
  }

  @override
  Future<void> otpRequest(String phone) =>
      _wrap(() => bridge.staffOtpRequest(phone: phone));

  @override
  Future<Map<String, dynamic>> otpVerify(
    String phone,
    String code, {
    String? orgId,
  }) => _wrap(() async {
    final raw = await bridge.staffOtpVerify(
      phone: phone,
      code: code,
      orgId: orgId,
      platform: Platform.operatingSystem,
      model: Platform.operatingSystemVersion,
    );
    return jsonDecode(raw) as Map<String, dynamic>;
  });

  @override
  Future<String> snapshot({required bool refresh}) =>
      _wrap(() => bridge.dawamSnapshot(refresh: refresh));

  @override
  Future<String> act(Map<String, dynamic> action) =>
      _wrap(() => bridge.dawamDo(action: jsonEncode(action)));

  @override
  Future<String> ping(DawamFix fix) => _wrap(
    () => bridge.dawamPing(
      latitude: fix.lat,
      longitude: fix.lng,
      accuracy: fix.accuracy,
      mock: fix.mock,
      gpsTime: fix.gpsTime?.toUtc().toIso8601String(),
      battery: fix.battery,
    ),
  );

  @override
  Future<String> sync() => _wrap(bridge.dawamSync);

  @override
  Future<DawamFix?> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return _fix(pos, await _battery());
    } on Object {
      return null; // no fix: the server refuses a fenced punch and says why
    }
  }

  static Future<int?> _battery() async {
    try {
      return await Battery().batteryLevel;
    } on Object {
      return null; // a simulator, or no battery API: the core just won't warn
    }
  }

  static DawamFix _fix(Position pos, int? battery) => (
    lat: pos.latitude,
    lng: pos.longitude,
    accuracy: pos.accuracy,
    mock: pos.isMocked,
    gpsTime: pos.timestamp,
    battery: battery,
  );

  @override
  Future<bool> alwaysLocation() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied ||
          p == LocationPermission.whileInUse) {
        // On iOS a second request upgrades "while in use" to "Always".
        p = await Geolocator.requestPermission();
      }
      return p == LocationPermission.always;
    } on Object {
      return false;
    }
  }

  /// On shift, in the background too (CL-4): Android runs a foreground
  /// service with its notification, iOS shows its location indicator. The
  /// store throttles to one ping per 15 minutes.
  @override
  Stream<DawamFix> track() {
    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            intervalDuration: const Duration(minutes: 5),
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: tr('staff.dawam'),
              notificationText: tr('staff.tracking_notice'),
              enableWakeLock: false,
            ),
          )
        : Platform.isIOS
        ? AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            pauseLocationUpdatesAutomatically: false,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
          )
        : const LocationSettings(accuracy: LocationAccuracy.high);
    return Geolocator.getPositionStream(
      locationSettings: settings,
    ).asyncMap((pos) async => _fix(pos, await _battery()));
  }

  @override
  String? restoredUser() => bridge.restoreSessionCached()?.userId;

  /// The server forgets this phone and its pushes first (06 B3), then
  /// Firebase forgets the token, then the core signs out — whatever the
  /// network says, the phone is signed out.
  @override
  Future<void> signOut() async {
    try {
      await bridge.dawamDo(action: jsonEncode({'action': 'sign_out'}));
    } on Object {
      // offline or refused: signing out never waits on the server
    }
    await beforeSignOut?.call();
    await bridge.logout(wipeOutbox: false);
  }
}
