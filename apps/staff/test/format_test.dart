import 'package:flutter_test/flutter_test.dart';
import 'package:madar_staff/format.dart';

void main() {
  group('formatDuration', () {
    // The translator the app injects; here it just renders the template so the
    // test asserts on shape rather than on English copy.
    String t(String key, [Map<String, String>? args]) {
      var out = switch (key) {
        'common.minutes' => '{n} min',
        'common.hoursMinutes' => '{h}h {m}m',
        _ => key,
      };
      args?.forEach((k, v) => out = out.replaceAll('{$k}', v));
      return out;
    }

    test('nothing recorded reads as an em-dash, never "0m"', () {
      // On an attendance row these are different facts: a day with no stamps
      // and a day where someone worked zero minutes should not look alike.
      expect(formatDuration(0, t), '—');
      expect(formatDuration(-5, t), '—');
    });

    test('under an hour stays in minutes', () {
      expect(formatDuration(25, t), '25 min');
    });

    test('an hour or more splits into hours and minutes', () {
      expect(formatDuration(60, t), '1h 0m');
      expect(formatDuration(445, t), '7h 25m');
    });
  });

  group('formatDays', () {
    test('centidays come back as whole days when they divide evenly', () {
      expect(formatDays(300), '3');
      expect(formatDays(0), '0');
    });

    test('a half day survives the integer FFI round trip', () {
      // The whole reason the boundary carries centidays: 0.5 must not become 0.
      expect(formatDays(50), '0.5');
      expect(formatDays(250), '2.5');
    });
  });

  group('formatMoney', () {
    test('piastres render as major units with the currency', () {
      expect(formatMoney(300000, 'EGP'), 'EGP 3,000');
      expect(formatMoney(4550, 'EGP'), 'EGP 45.5');
    });

    test('an unknown currency renders the bare amount', () {
      expect(formatMoney(300000, ''), '3,000');
    });
  });

  group('formatClock', () {
    test('an empty stamp is an em-dash rather than a crash', () {
      expect(formatClock(''), '—');
      expect(formatClock('not-a-date'), '—');
    });
  });
}
