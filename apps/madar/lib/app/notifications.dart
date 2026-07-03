import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Host-side OS notifications — the platform primitive the CORE drives via
/// `AlertCommand.notify`. The Flutter equivalent of the natives'
/// RealtimePlayer.postNotification: a high-importance channel and a
/// tag-deduped `show` (re-posting the same entity REPLACES it). The core
/// decides WHEN (which events, dedup, localized title/body); this holds no
/// policy. Best-effort throughout — a POS must never crash on a failed
/// notification.
class NotificationService {
  NotificationService._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'madar_realtime';
  static const _channelName = 'Madar alerts';

  /// Boot the plugin, create the Android channel, and request permission
  /// (Android 13+ / iOS / macOS). Returns a ready service; never throws.
  static Future<NotificationService> initialize() async {
    final plugin = FlutterLocalNotificationsPlugin();
    try {
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
        ),
      );

      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          importance: Importance.high,
        ),
      );
      await android?.requestNotificationsPermission();

      await plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      await plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } on Object {
      // Unsupported platform or a denied prompt — the in-app toast + chime
      // still fire; OS notifications are the bonus tier.
    }
    return NotificationService._(plugin);
  }

  /// Post (or REPLACE, when [tag] repeats) an OS notification. The channel
  /// carries the sound + importance; the core already localized the text.
  Future<void> post({
    required String title,
    required String body,
    required String tag,
  }) async {
    try {
      await _plugin.show(
        // Same tag → same id → the OS replaces the prior notification
        // (the natives' `tag.hashCode` dedup).
        tag.hashCode & 0x7fffffff,
        title,
        body.isEmpty ? null : body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
      );
    } on Object {
      // Best-effort — never surface a notification failure to the POS UI.
    }
  }
}
