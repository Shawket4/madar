// CL-4 on iOS: the protocol of `com.madar.dawam/tracking` between the app
// and AppDelegate.swift's DawamTracker. The tracker watches the branch's
// fence the app hands over with "start", takes its own readings (a fence
// crossing, a significant move, the 15-minute one) and keeps them until the
// app says it has them — so the reading that relaunched a closed app is not
// lost while the app boots: the app listens early and asks for a flush.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar_staff/tracking.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(TrackingChannel.name);
  const codec = StandardMethodCodec();
  final host =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// What the app sent the host.
  late List<MethodCall> sent;
  setUp(() {
    sent = [];
    host.setMockMethodCallHandler(channel, (c) async {
      sent.add(c);
      return null;
    });
  });
  tearDown(() {
    host.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null); // the app stops listening
  });

  /// The host hands the app one reading; what the app answered.
  Future<Object?> hostSends(Map<String, Object?> fix) async {
    ByteData? reply;
    await host.handlePlatformMessage(
      TrackingChannel.name,
      codec.encodeMethodCall(MethodCall('fix', fix)),
      (r) => reply = r,
    );
    return reply == null ? #notImplemented : codec.decodeEnvelope(reply!);
  }

  Map<String, Object?> reading(String id, String wake, {int age = 3}) => {
    'id': id,
    'latitude': 30.07,
    'longitude': 31.22,
    'accuracy': 65.0,
    'mock': false,
    'wake': wake,
    'age_s': age,
  };

  /// A store signed in as e1, on shift, pinging through the fake core.
  Future<(DawamStore, FakeCore)> onShift() async {
    final core = FakeCore('e1')..restored = 'e1';
    core.edit = (v) {
      final id = (v['my_now'] as List<dynamic>).first as String;
      v['active_shift'] = id;
      for (final s
          in (v['shifts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        if (s['id'] == id) s['in_at'] = '${s['date']}T09:02:00+03:00';
      }
    };
    final store = DawamStore(core);
    await store.restore();
    addTearDown(store.stop);
    return (store, core);
  }

  test('"start" carries the branch fence the store names', () async {
    final t = TrackingChannel();
    await t.start(
      title: 'Dawam',
      text: 'On shift',
      fence: (lat: 30.0609, lng: 31.2197, radius: 200),
    );
    await t.start(title: 'Dawam', text: 'On shift', fence: null);
    await t.stop();
    expect(sent.map((c) => c.method), ['start', 'start', 'stop']);
    expect(sent[0].arguments, {
      'title': 'Dawam',
      'text': 'On shift',
      'fence': {'latitude': 30.0609, 'longitude': 31.2197, 'radius': 200},
    });
    expect(
      (sent[1].arguments as Map)['fence'],
      isNull,
      reason: 'no coordinates: significant changes and updates only',
    );
  });

  test('a reading the host took is pinged, with its wake reason', () async {
    final (store, core) = await onShift();
    final wakes = <String>[];
    await TrackingChannel(battery: () async => 64).listen((
      fix, {
      required wake,
      age = Duration.zero,
    }) {
      wakes.add(wake);
      return store.wakeFix(fix, wake: wake, age: age);
    });
    expect(sent.map((c) => c.method), ['flush'], reason: 'asked at once');

    expect(await hostSends(reading('a', 'region_exit')), isTrue);
    expect(wakes, ['region_exit']);
    expect(core.pings.single, (
      lat: 30.07,
      lng: 31.22,
      accuracy: 65.0,
      mock: false,
      gpsTime: null, // iOS: the phone's clock, never sent as GPS time
      battery: 64,
    ));
  });

  test(
    'a flush hands over what the host kept, each once, oldest first',
    () async {
      final (store, core) = await onShift();
      await TrackingChannel(battery: () async => null).listen(store.wakeFix);
      expect(sent.single.method, 'flush');
      // The host answers the flush with its queue, one reading at a time: a
      // relaunch's significant change, then the fence it left.
      expect(await hostSends(reading('q1', 'significant_change')), isTrue);
      expect(await hostSends(reading('q2', 'region_exit')), isTrue);
      expect(core.pings, hasLength(2));
      // A reading the host sends again (it was in flight when the app asked
      // for the flush) is answered, not pinged twice.
      expect(await hostSends(reading('q2', 'region_exit')), isTrue);
      expect(core.pings, hasLength(2));
      // One kept for an hour (no app was running to take it) is answered, so
      // it leaves the host's queue, but not sent as where they are now.
      expect(await hostSends(reading('q3', 'region_exit', age: 3600)), isTrue);
      expect(core.pings, hasLength(2));
    },
  );

  test('before the app listens, the host keeps its readings', () async {
    // No handler yet (a relaunch still booting): the host is told "not
    // implemented", which keeps the reading in its queue for the flush.
    expect(await hostSends(reading('early', 'region_exit')), #notImplemented);
  });
}
