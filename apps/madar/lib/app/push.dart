/// Push notifications for the till (APP-6): the phone's FCM token goes to the
/// server, and a push that lands while the app is closed opens the Queue.
///
/// Policy is the SERVER's — which events push, to whom, in what words. This
/// holds none of it. It registers the token, shows a banner when a push
/// arrives with the app open (the OS does it otherwise), and routes a tapped
/// notification to the Queue, which is where an order that just arrived is.
///
/// Android and iOS only: firebase_messaging has no Windows till, and a macOS
/// one would need its own APNs setup. Everything is best-effort — a POS must
/// never fail to sell because a notification did not work.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:rust_bridge/rust_bridge.dart';

/// Firebase needs a real entry point for a message that wakes a killed app.
/// Nothing to do here: the payload carries its own notification, so the OS
/// draws it; the tap is handled by [PosPush.start]'s `onMessageOpenedApp`.
@pragma('vm:entry-point')
Future<void> posPushBackgroundHandler(RemoteMessage message) async {}

/// Wired once by the shell, which owns the notification banner and the tabs.
class PosPush {
  PosPush({
    required this.bridge,
    required this.post,
    required this.openQueue,
    required this.locale,
  });

  /// The core: it decides the app name and the language of server pushes.
  final MadarBridge bridge;

  /// Show a notification while the app is in the foreground — the shell's
  /// `NotificationService.post`, so a push and a realtime alert look alike.
  final Future<void> Function({
    required String title,
    required String body,
    required String tag,
  })
  post;

  /// Go to the Queue — a tapped push is an order waiting to be dealt with.
  final void Function() openQueue;

  /// `ar` or `en`, for the words the server writes pushes in.
  String locale;

  String? _token;
  String? _sent; // token|locale last registered, so a rebuild is not a re-send
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _onMessage;
  StreamSubscription<RemoteMessage>? _onOpened;

  /// True on the platforms that have push at all.
  static bool get supported => Platform.isAndroid || Platform.isIOS;

  /// Start Firebase, ask for permission, and begin listening. Safe to call
  /// when Firebase is not configured on this machine: it returns quietly and
  /// the app runs without push.
  Future<void> start() async {
    if (!supported) return;
    try {
      // From the platform's own google-services.json / GoogleService-Info
      // .plist, both git-ignored (public repo) and regenerated with
      // `flutterfire configure` — see the README.
      await Firebase.initializeApp();
    } on Object {
      return; // no Firebase here: the in-app toasts still fire
    }
    try {
      final m = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(posPushBackgroundHandler);
      await m.requestPermission();
      // iOS shows its own banner in the foreground only if asked to; we draw
      // ours instead, so the two never double up.
      await m.setForegroundNotificationPresentationOptions(
        badge: true,
        sound: true,
      );
      _onMessage = FirebaseMessaging.onMessage.listen(_show);
      _onOpened = FirebaseMessaging.onMessageOpenedApp.listen(
        (_) => openQueue(),
      );
      // Opened from a notification while the app was not running at all.
      final initial = await m.getInitialMessage();
      if (initial != null) openQueue();
      _refresh = m.onTokenRefresh.listen((t) {
        _token = t;
        _debugToken(t);
        unawaited(register());
      });
      _token = await m.getToken();
      _debugToken(_token);
      await register();
    } on Object {
      // Permission refused, no APNs token yet, no network: none of it is
      // worth a broken till.
    }
  }

  /// Debug builds print the token, so a push can be tested from the Firebase
  /// console ("Send test message") before any server sends one. Never in
  /// release: a token is an address anyone can push to.
  static void _debugToken(String? token) {
    if (kDebugMode && token != null) debugPrint('[push] FCM token: $token');
  }

  /// Hand the token to the server. Called again when the language changes or
  /// someone new signs in; a repeat with nothing new to say is skipped.
  Future<void> register() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    final stamp = '$token|$locale';
    if (_sent == stamp) return;
    try {
      await bridge.setPushToken(
        token: token,
        locale: locale,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
      _sent = stamp;
    } on Object {
      _sent = null; // offline: the next call tries again
    }
  }

  /// The language changed: the server writes pushes in it.
  void language(String value) {
    if (value == locale) return;
    locale = value;
    unawaited(register());
  }

  /// Sign-out: stop this till ringing for whoever just left.
  Future<void> forget() async {
    final token = _token;
    _sent = null;
    if (token == null) return;
    try {
      await bridge.clearPushToken(token: token);
    } on Object {
      // Best-effort; the server also drops a token FCM reports as gone.
    }
  }

  /// A push with the app open: the server already wrote the words.
  Future<void> _show(RemoteMessage message) => _showParts(
    title: message.notification?.title,
    body: message.notification?.body,
    data: message.data,
    messageId: message.messageId,
  );

  Future<void> _showParts({
    required String? title,
    required String? body,
    required Map<String, dynamic> data,
    String? messageId,
  }) async {
    String field(String key) => data[key]?.toString() ?? '';
    final t = title ?? field('title');
    if (t.isEmpty) return;
    // Same order twice (a retry, a status change) replaces its banner.
    final tag = [
      field('tag'),
      field('order_id'),
      messageId ?? '',
      t,
    ].firstWhere((x) => x.isNotEmpty);
    await post(title: t, body: body ?? field('body'), tag: tag);
  }

  /// Tests: the token Firebase would have handed over.
  @visibleForTesting
  // A method, not a setter: there is deliberately no getter for the token.
  // ignore: use_setters_to_change_properties
  void debugSetToken(String token) => _token = token;

  /// Tests: a foreground push, without Firebase.
  @visibleForTesting
  Future<void> debugShow({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) => _showParts(title: title, body: body, data: data);

  /// Drop every listener (the shell going away).
  Future<void> dispose() async {
    await _refresh?.cancel();
    await _onMessage?.cancel();
    await _onOpened?.cancel();
  }
}
