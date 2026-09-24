// The POS's OS banners (live alerts, and a push that lands while the app is
// open) carry their tag, and tapping one — or the tap that launches the
// app — reaches the shell's handler, which opens the Queue like the in-app
// toast's View. Drives the real plugin through its Android method channel.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar/app/notifications.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  Map<String, Object?>? launch;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls = [];
    launch = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'initialize' => true,
            'getNotificationAppLaunchDetails' => launch,
            'requestNotificationsPermission' => true,
            _ => null,
          };
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<void> tapFromOs(String? payload) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            _channel.name,
            _channel.codec.encodeMethodCall(
              MethodCall('didReceiveNotificationResponse', {
                'notificationId': 1,
                'payload': payload,
                'notificationResponseType': 0,
              }),
            ),
            (_) {},
          );

  test('a banner carries its tag, and a tap hands it to the shell', () async {
    final tapped = <String?>[];
    final s = await NotificationService.initialize(
      channelName: 'Orders',
      onTap: tapped.add,
    );
    await s.post(title: 'New order', body: '#12', tag: 'delivery.created:o1');
    final show = calls.lastWhere((c) => c.method == 'show');
    expect((show.arguments as Map)['payload'], 'delivery.created:o1');
    expect(
      (show.arguments as Map)['id'],
      'delivery.created:o1'.hashCode & 0x7fffffff,
      reason: 'the same tag replaces its banner',
    );
    await tapFromOs('delivery.created:o1');
    expect(tapped, ['delivery.created:o1']);
  });

  test('the tap that launched the app is handed over too', () async {
    launch = {
      'notificationLaunchedApp': true,
      'notificationResponse': {
        'notificationId': 7,
        'payload': 'delivery.created:o2',
        'notificationResponseType': 0,
      },
    };
    final tapped = <String?>[];
    await NotificationService.initialize(
      channelName: 'Orders',
      onTap: tapped.add,
    );
    expect(tapped, ['delivery.created:o2']);
  });

  test('no launch tap, no call', () async {
    launch = {'notificationLaunchedApp': false};
    final tapped = <String?>[];
    await NotificationService.initialize(
      channelName: 'Orders',
      onTap: tapped.add,
    );
    expect(tapped, isEmpty);
  });
}
