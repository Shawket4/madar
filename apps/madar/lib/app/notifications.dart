import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Host-side OS notifications — the platform primitive the CORE drives via
/// `AlertCommand.notify`. The Flutter equivalent of the natives'
/// RealtimePlayer.postNotification: a high-importance channel and a
/// tag-deduped `show` (re-posting the same entity REPLACES it). The core
/// decides WHEN (which events, dedup, localized title/body); this holds no
/// policy. Best-effort throughout — a POS must never crash on a failed
/// notification.
class NotificationService {
  NotificationService._(this._plugin, this._channelName);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'madar_realtime';

  /// The channel's user-visible name (Android's notification settings), in
  /// the app's language — `notif.channel` from the core.
  String _channelName;

  /// Boot the plugin, create the Android channel, and request permission
  /// (Android 13+ / iOS / macOS). Returns a ready service; never throws.
  static Future<NotificationService> initialize({
    required String channelName,
  }) async {
    final plugin = FlutterLocalNotificationsPlugin();
    try {
      await plugin.initialize(
        settings: const InitializationSettings(
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
        AndroidNotificationChannel(
          _channelId,
          channelName,
          importance: Importance.max,
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
    return NotificationService._(plugin, channelName);
  }

  /// Re-name the channel after a language switch. Android updates the name
  /// of an existing channel in place when it is re-created under the same
  /// id; importance and sound are the user's to keep and are not touched.
  Future<void> rename(String channelName) async {
    if (channelName == _channelName) return;
    _channelName = channelName;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            AndroidNotificationChannel(
              _channelId,
              channelName,
              importance: Importance.max,
            ),
          );
    } on Object {
      // Best-effort, like everything here.
    }
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
        id: tag.hashCode & 0x7fffffff,
        title: title,
        body: body.isEmpty ? null : body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.max,
            priority: Priority.max,
          ),
          // Foreground presentation too — a POS is usually foreground when
          // the order lands; the banner + sound must still fire.
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
          macOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    } on Object {
      // Best-effort — never surface a notification failure to the POS UI.
    }
  }
}
