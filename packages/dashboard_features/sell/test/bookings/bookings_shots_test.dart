// The bookings screenshot matrix: the default day at {phone, tablet,
// desktop} x {en light, ar dark}, scrolled through; the other states (the
// timeline, a row menu, the dialogs, empty, loading, failed, no branch) at
// desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set; the
// pages still render (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_sell/src/bookings/bookings_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(
        of: find.byType(BookingsPage),
        matching: find.byType(Scrollable),
      )
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('bookings/$name-$i');
    if (y >= position.maxScrollExtent || i >= 4) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpBookings(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final tag = '${size.name} $lang';

    testWidgets('timeline, $tag', (tester) async {
      final h = await pumpBookings(tester, size: size, locale: lang);
      await h.tap(inPage(find.text(h.t('bookings.viewTimeline'))));
      await shootPage(h, 'timeline');
    });

    testWidgets('row menu, $tag', (tester) async {
      final h = await pumpBookings(tester, size: size, locale: lang);
      await h.tap(actionsOf(heliBooking(3)));
      await h.shot('bookings/row-menu');
    });

    testWidgets('new booking, $tag', (tester) async {
      final h = await pumpBookings(tester, size: size, locale: lang);
      await h.tap(find.byKey(const ValueKey('bookings-new')));
      await h.tap(find.byKey(const ValueKey('booking-submit')));
      await h.shot('bookings/dialog-new');
    });

    testWidgets('edit booking, $tag', (tester) async {
      final h = await pumpBookings(
        tester,
        size: size,
        locale: lang,
        path: '/bookings?booking=${heliBooking(5)}',
      );
      await h.shot('bookings/dialog-edit');
    });

    testWidgets('settings, $tag', (tester) async {
      final h = await pumpBookings(tester, size: size, locale: lang);
      await h.tap(find.byKey(const ValueKey('bookings-settings')));
      await h.shot('bookings/dialog-settings');
    });

    testWidgets('empty day, $tag', (tester) async {
      final h = await pumpBookings(
        tester,
        size: size,
        locale: lang,
        path: '/bookings?date=2026-11-20',
      );
      await h.shot('bookings/empty');
    });

    testWidgets('loading, $tag', (tester) async {
      final s = bookingsServer();
      final gate = s.server.hold('GET', dayTemplate);
      final h = await pumpBookings(tester, size: size, locale: lang, s: s);
      await h.shot('bookings/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = bookingsServer();
      s.server.fail(
        'GET',
        dayTemplate,
        MockResponse.error(500, 'Database error'),
      );
      final h = await pumpBookings(tester, size: size, locale: lang, s: s);
      await h.shot('bookings/failed');
    });

    testWidgets('no branch, $tag', (tester) async {
      final h = await pumpBookings(
        tester,
        size: size,
        locale: lang,
        noBranch: true,
      );
      await h.shot('bookings/no-branch');
    });

    testWidgets('online off, $tag', (tester) async {
      final h = await pumpBookings(
        tester,
        size: size,
        locale: lang,
        branchId: SeedIds.zamalek,
      );
      await h.shot('bookings/online-off');
    });
  }
}
