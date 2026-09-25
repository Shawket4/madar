// The app's side of the host's on-shift tracking (CL-4) on
// `com.madar.dawam/tracking`.
//
// App → host: `start` {title, text, fence: {latitude, longitude, radius}?}
// at clock-in (and when the fence moves), `stop` at clock-out,
// `requestAlways`, and `flush`: "I am listening, hand over what you kept".
//
// Host → app (iOS, AppDelegate.swift's DawamTracker): `fix` {id, latitude,
// longitude, accuracy, mock?, wake, age_s} — one reading the host took, and
// why (`region_exit`, `region_entry`, `significant_change`, `interval`). The
// host keeps each reading until the app answers it, so the one that
// relaunched a closed app is not lost while the app boots; the answer comes
// once the core has the ping, and the host holds the app awake until then.
// Android's service pings through its own engine instead (background.dart).
import 'package:flutter/services.dart';
import 'package:staff_core/staff_core.dart';

/// What the app does with a reading the host took ([DawamStore.wakeFix]).
typedef OnHostFix =
    Future<void> Function(DawamFix fix, {required String wake, Duration age});

class TrackingChannel {
  TrackingChannel({Future<int?> Function()? battery})
    : _battery = battery ?? (() async => null);

  static const name = 'com.madar.dawam/tracking';
  static const _channel = MethodChannel(name);

  final Future<int?> Function() _battery;

  /// Readings answered or being handled, by the host's id: the host sends a
  /// reading again when the app asks for a flush while it was in flight.
  final _handled = <String, Future<void>>{};

  /// Background tracking on, with the branch's [fence] to watch (none: the
  /// branch has no coordinates). [title] and [text] are Android's on-shift
  /// notification, in the app's language (APP-4).
  Future<void> start({
    required String title,
    required String text,
    DawamFence? fence,
  }) => _channel.invokeMethod<void>('start', {
    'title': title,
    'text': text,
    'fence': fence == null
        ? null
        : {
            'latitude': fence.lat,
            'longitude': fence.lng,
            'radius': fence.radius,
          },
  });

  Future<void> stop() => _channel.invokeMethod<void>('stop');

  /// iOS's upgrade to "Always" location (the host's own ask).
  Future<bool?> requestAlways() => _channel.invokeMethod<bool>('requestAlways');

  /// Take the host's readings from now on, and ask for the ones it kept.
  /// Early in boot, once the store knows who is signed in.
  Future<void> listen(OnHostFix onFix) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'fix') throw MissingPluginException();
      final a = (call.arguments as Map).cast<String, Object?>();
      final id = a['id'] as String? ?? '';
      final handling = _handled[id] ??= _handle(a, onFix);
      while (_handled.length > 50) {
        _handled.remove(_handled.keys.first);
      }
      await handling;
      return true;
    });
    await _channel.invokeMethod<void>('flush');
  }

  Future<void> _handle(Map<String, Object?> a, OnHostFix onFix) async => onFix(
    (
      lat: (a['latitude']! as num).toDouble(),
      lng: (a['longitude']! as num).toDouble(),
      accuracy: (a['accuracy'] as num?)?.toDouble(),
      mock: a['mock'] == true,
      gpsTime: null, // iOS: the phone's clock, never sent as GPS time
      battery: await _battery(),
    ),
    wake: a['wake'] as String? ?? 'unknown',
    age: Duration(seconds: (a['age_s'] as num?)?.round() ?? 0),
  );
}
