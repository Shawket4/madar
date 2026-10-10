// The Bookings settings screenshot matrix: the default state at every size
// in {en light, ar dark}, and every other state (a branch picked, the rules
// dialog loading, open, scrolled to the blackouts, a failed read, the branch
// list open) at desktop-en-light and phone-ar-light. Writes PNGs only with
// FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _states = [
  ('en', false, DashSize.desktop),
  ('ar', false, DashSize.phone),
];

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpBookingRules(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await h.shot('bookings/default');
      });
    }
  }

  for (final (lang, dark, size) in _states) {
    final tag = '${size.name} $lang';
    Future<DashHarness> pump(
      WidgetTester tester, {
      ({MockServer server, MockDb db})? backend,
    }) => pumpBookingRules(
      tester,
      size: size,
      locale: lang,
      dark: dark,
      backend: backend,
    );

    testWidgets('branch list open, $tag', (tester) async {
      final h = await pump(tester);
      await h.tap(byKey('bkg-branch'));
      await h.shot('bookings/branches-open');
    });

    testWidgets('rules loading, $tag', (tester) async {
      final m = bkgServer();
      final gate = m.server.hold('GET', bkgSettings);
      final h = await pump(tester, backend: m);
      await openRules(h, 'Heliopolis');
      await h.shot('bookings/rules-loading');
      gate.release();
      await h.settle();
    });

    testWidgets('rules, $tag', (tester) async {
      final h = await pump(tester);
      await openRules(h, 'Heliopolis');
      await h.shot('bookings/rules-1');
      await tester.ensureVisible(rulesKey('bkg-max_covers_per_slot'));
      await h.settle(rounds: 2);
      await h.shot('bookings/rules-2');
      await tester.ensureVisible(rulesKey('bkg-blackout-add'));
      await h.settle(rounds: 2);
      await h.shot('bookings/rules-3');
    });

    testWidgets('rules failed, $tag', (tester) async {
      final m = bkgServer();
      m.server.fail(
        'GET',
        bkgSettings,
        MockResponse.error(500, 'Database is resting'),
        times: null,
      );
      final h = await pump(tester, backend: m);
      await openRules(h, 'Maadi');
      await h.shot('bookings/rules-failed');
    });
  }
}
