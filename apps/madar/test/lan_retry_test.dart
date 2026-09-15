import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar/app/lan_retry.dart';

/// A fake bridge: `lanStart` fails until [failuresLeft] runs out.
class _FakeLan {
  _FakeLan(FakeAsync clock) {
    retrier = LanRetrier(
      start: () async {
        attempts.add(clock.elapsed);
        if (failuresLeft > 0) {
          failuresLeft--;
          throw StateError('no LAN secret');
        }
        running = true;
      },
      isRunning: () => running,
      signedIn: () => signedIn,
      onStarted: () => started++,
    );
  }

  int failuresLeft = 0;
  bool running = false;
  bool signedIn = true;
  final attempts = <Duration>[];
  int started = 0;

  late final LanRetrier retrier;
}

void main() {
  test('backs off 5s, 10s, 20s, 40s, then caps at 60s until it starts', () {
    fakeAsync((clock) {
      final lan = _FakeLan(clock)..failuresLeft = 7;
      lan.retrier.kick();
      clock.elapse(const Duration(minutes: 10));
      final gaps = [
        for (var i = 1; i < lan.attempts.length; i++)
          (lan.attempts[i] - lan.attempts[i - 1]).inSeconds,
      ];
      expect(gaps, [5, 10, 20, 40, 60, 60, 60]);
      expect(lan.running, isTrue);
      expect(lan.started, 1);
      expect(
        lan.retrier.scheduledDelay,
        isNull,
        reason: 'no retries once running',
      );
    });
  });

  test('does nothing while signed out, and sign-out stops retrying', () {
    fakeAsync((clock) {
      final lan = _FakeLan(clock)
        ..signedIn = false
        ..failuresLeft = 100;
      lan.retrier.kick();
      clock.elapse(const Duration(minutes: 2));
      expect(lan.attempts, isEmpty);

      lan.signedIn = true;
      lan.retrier.kick();
      clock.elapse(const Duration(seconds: 16));
      expect(lan.attempts.length, 3, reason: 'now, +5s, +15s');

      lan.signedIn = false;
      clock.elapse(const Duration(minutes: 5));
      expect(
        lan.attempts.length,
        3,
        reason: 'the next tick sees the sign-out and stops',
      );
      expect(lan.retrier.scheduledDelay, isNull);
    });
  });

  test('a kick (reconnect / resume) retries at once and resets the ladder', () {
    fakeAsync((clock) {
      final lan = _FakeLan(clock)..failuresLeft = 100;
      lan.retrier.kick();
      clock.elapse(const Duration(seconds: 36)); // attempts at 0, 5, 15, 35
      expect(lan.attempts.length, 4);
      expect(lan.retrier.scheduledDelay, const Duration(seconds: 40));

      lan.retrier.kick(); // network came back
      clock.flushMicrotasks();
      expect(lan.attempts.length, 5);
      expect(lan.retrier.scheduledDelay, const Duration(seconds: 5));
    });
  });

  test('an already-running relay is not restarted', () {
    fakeAsync((clock) {
      final lan = _FakeLan(clock)..running = true;
      lan.retrier.kick();
      clock.elapse(const Duration(minutes: 1));
      expect(lan.attempts, isEmpty);
      expect(lan.started, 1);
    });
  });
}
