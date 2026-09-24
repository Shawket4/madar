import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  final core = await startCore(prefs);
  words = (key) => core.bridge.tr(key: key);
  wordsIn = (lang, key) => core.bridge.trIn(locale: lang, key: key);
  final lang = core.bridge.locale().startsWith('ar') ? 'ar' : 'en';
  final backend = _BridgeBackend(core.bridge);
  final store = DawamStore(backend);
  await store.restore();
  // An older build kept the device token in the core's store: it moves to
  // the vault now (the core deletes its copy once taken).
  await DeviceVault.keep(core.bridge);
  final opened = ValueNotifier<String?>(null);
  final foreground = ValueNotifier<ForegroundPush?>(null);
  final push = _Push(core.bridge, store, lang, opened, foreground);
  backend.beforeSignOut = push.forget;
  unawaited(push.start());
  return [
    openedPushProvider.overrideWithValue(opened),
    foregroundPushProvider.overrideWithValue(foreground),
    dawamProvider.overrideWith((ref) {
      ref.onDispose(store.stop);
      return store;
    }),
    localeProvider.overrideWith(() => LocaleNotifier(initial: lang)),
    localePersisterProvider.overrideWithValue((l) {
      core.bridge.setLocale(locale: l);
      unawaited(prefs.setString('madar.locale', l));
      push.language(l);
      backend.relabel(); // the on-shift notification in the new language
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

/// Starts madar-core over the staff app's store and binds this phone's
/// device token from the platform vault. Used by the app and by the Android
/// location service's own engine (`background.dart`); in one process both
/// get the SAME core (the bridge keeps one per store).
Future<MadarCore> startCore([SharedPreferences? prefs]) async {
  final p = prefs ?? await SharedPreferences.getInstance();
  final dir = await getApplicationSupportDirectory();
  final saved = p.getString('madar.locale') ?? '';
  final core = await MadarCore.start(
    config: MadarConfig(
      baseUrl: _apiBase,
      environment: _environment,
      dbPath: '${dir.path}${Platform.pathSeparator}madar_staff.db',
      locale: saved.isEmpty ? 'ar' : saved, // Arabic first (APP-4)
    ),
  );
  await DeviceVault.bind(core.bridge);
  return core;
}

/// The phone's Dawam device token in the platform's secure storage — the
/// Keychain on iOS, the Keystore-backed store on Android — never the core's
/// SQLite (RO-3, audit 03 CL-1c). Readable after the first unlock, so the
/// location service can start again after a reboot.
abstract final class DeviceVault {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const _key = 'dawam.device_token';

  /// Give the core the token kept here (a cold start).
  static Future<void> bind(MadarBridge bridge) async {
    try {
      final t = await _storage.read(key: _key);
      if (t != null && t.isNotEmpty) bridge.staffBindDevice(token: t);
    } on Object {
      // no vault (a desktop test run): the core has nothing to bind
    }
  }

  /// Keep the token the core hands over after a sign-in (once).
  static Future<void> keep(MadarBridge bridge) async {
    final t = bridge.staffTakeDeviceToken();
    if (t == null) return;
    try {
      await _storage.write(key: _key, value: t);
    } on Object {
      // no vault: the phone signs in again next time
    }
  }

  static Future<void> forget() async {
    try {
      await _storage.delete(key: _key);
    } on Object {
      // nothing kept
    }
  }
}

/// Push notifications (APP-6). Once someone is signed in, the phone's FCM
/// token goes to the server with the language its pushes are written in; a
/// push that arrives while the app is open refreshes the picture; a tapped
/// push opens its screen; signing out forgets the token.
class _Push {
  _Push(this.bridge, this.store, this.lang, this.opened, this.foreground);

  final MadarBridge bridge;
  final DawamStore store;
  final ValueNotifier<String?> opened;
  final ValueNotifier<ForegroundPush?> foreground;
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
    FirebaseMessaging.onMessage.listen((msg) {
      store.sync();
      // iOS draws the banner itself (the presentation options above); on
      // Android nothing is shown for a push that arrives while the app is
      // open, so the shell shows it as a toast that opens its screen.
      if (Platform.isAndroid) {
        final text = foregroundPushText(
          msg.notification?.title,
          msg.notification?.body,
        );
        if (text.isNotEmpty) {
          foreground.value = (text: text, key: msg.data['key'] as String?);
        }
      }
    });
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

  /// The host side of background tracking (CL-4): Android's native location
  /// service (`DawamTrackingService`), iOS's significant-change monitoring
  /// (`AppDelegate`). The native side sends iOS relaunch fixes back here.
  static const _tracking = MethodChannel('com.madar.dawam/tracking');
  bool _trackingOn = false;
  StreamController<DawamFix>? _nativeFixes;

  Future<T> _wrap<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on MadarError catch (e) {
      final text = dawamErrorText(
        e,
        word: (key) => bridge.tr(key: key),
        human: bridge.humanMessage,
      );
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
    // Signed in: this phone's token goes straight to the vault.
    await DeviceVault.keep(bridge);
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
    // iOS stamps a fix with the phone's own clock, not the satellites': it
    // is not sent as GPS time (audit 03 CL-11b). Android's is the fix's time.
    gpsTime: Platform.isIOS ? null : pos.timestamp,
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

  /// On shift, while the app runs (CL-4). On Android the native location
  /// service pings on its own — through the same core, in its own engine —
  /// and keeps doing so after the app is closed or the phone restarts, so
  /// this stream is empty there. On iOS: the position stream with the blue
  /// indicator, plus the significant-change fixes that relaunched the app.
  /// The store throttles to one ping per 15 minutes.
  @override
  Stream<DawamFix> track() {
    if (Platform.isAndroid) return const Stream.empty();
    final LocationSettings settings = Platform.isIOS
        ? AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            pauseLocationUpdatesAutomatically: false,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
          )
        : const LocationSettings(accuracy: LocationAccuracy.high);
    final out = StreamController<DawamFix>();
    final subs = <StreamSubscription<DawamFix>>[
      Geolocator.getPositionStream(locationSettings: settings)
          .asyncMap((pos) async => _fix(pos, await _battery()))
          .listen(out.add, onError: out.addError),
      _native().stream.listen(out.add),
      // While iOS lets the app run but the stream is quiet (standing still):
      // a reading every 15 minutes all the same.
      Stream<void>.periodic(const Duration(minutes: 15))
          .asyncMap((_) => locate())
          .where((f) => f != null)
          .cast<DawamFix>()
          .listen(out.add),
    ];
    out.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };
    return out.stream;
  }

  /// Fixes the native side hands over (iOS significant-change events).
  StreamController<DawamFix> _native() {
    final c = _nativeFixes ??= StreamController<DawamFix>.broadcast();
    _tracking.setMethodCallHandler((call) async {
      if (call.method != 'fix') return null;
      final a = (call.arguments as Map).cast<String, Object?>();
      c.add((
        lat: (a['latitude']! as num).toDouble(),
        lng: (a['longitude']! as num).toDouble(),
        accuracy: (a['accuracy'] as num?)?.toDouble(),
        mock: a['mock'] == true,
        gpsTime: null, // iOS: the phone's clock, never sent as GPS time
        battery: await _battery(),
      ));
      return null;
    });
    return c;
  }

  /// Start or stop the background tracking (CL-4, CL-17). The on-shift
  /// notification is in the app's language (APP-4).
  @override
  Future<void> tracking({required bool on}) async {
    _trackingOn = on;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _tracking.invokeMethod<void>(on ? 'start' : 'stop', {
        'title': tr('staff.dawam'),
        'text': tr('staff.tracking_notice'),
      });
    } on Object {
      // an older native side: the in-app stream still pings while open
    }
  }

  /// The language changed: say the on-shift notification in it.
  void relabel() {
    if (_trackingOn) unawaited(tracking(on: true));
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
    await tracking(on: false);
    await DeviceVault.forget();
    await bridge.logout(wipeOutbox: false);
  }
}

/// What a refused core call says to the person. A 403 carries the server's
/// sentence in `action` (a limit, a scope). A lost connection reads "This
/// needs a connection…" in the phone's language: the staff app has no
/// offline sign-in, so the till's "this teller hasn't been set up for offline
/// sign-in yet" (the bridge's word for any offline error) was wrong here
/// (E2E roster: a swap, a claim or a preference tapped offline showed it).
@visibleForTesting
String dawamErrorText(
  MadarError e, {
  required String Function(String key) word,
  required String Function(MadarError) human,
}) => switch (e) {
  // The sentence only: the server's error kind in front ("Forbidden: This
  // needs …") is not for the person (E2E roster, a manager's holiday tap).
  MadarError_Forbidden(:final action) when action.isNotEmpty =>
    action.startsWith('Forbidden: ') ? action.substring(11) : action,
  MadarError_Offline() => word('staff.needs_connection'),
  _ => human(e),
};
