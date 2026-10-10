// The Review page's screenshot matrix: the default state at every size in
// EN light and AR dark, and every other state at desktop-en-light and
// phone-ar-light. Written only with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _variants = [
  (size: DashSize.phone, locale: 'en', dark: false),
  (size: DashSize.tablet, locale: 'en', dark: false),
  (size: DashSize.desktop, locale: 'en', dark: false),
  (size: DashSize.phone, locale: 'ar', dark: true),
  (size: DashSize.tablet, locale: 'ar', dark: true),
  (size: DashSize.desktop, locale: 'ar', dark: true),
];

const _stateVariants = [
  (size: DashSize.desktop, locale: 'en', dark: false),
  (size: DashSize.phone, locale: 'ar', dark: false),
];

void main() {
  for (final v in _variants) {
    testWidgets(
      'shots: default (${v.size.name} ${v.locale} ${v.dark ? 'dark' : 'light'})',
      (tester) async {
        final h = await pumpReview(
          tester,
          size: v.size,
          locale: v.locale,
          dark: v.dark,
        );
        expect(pick(1).evaluate().isEmpty, v.size == DashSize.phone);
        await h.shot('review/default');
      },
    );
  }

  for (final v in _stateVariants) {
    final tag = '${v.size.name} ${v.locale}';

    Future<DashHarness> open(
      WidgetTester tester, {
      MockServer? server,
      MockDb? db,
    }) => pumpReview(
      tester,
      size: v.size,
      locale: v.locale,
      dark: v.dark,
      server: server,
      db: db,
    );

    testWidgets('shots: reviewed shown ($tag)', (tester) async {
      final h = await open(tester);
      await h.tap(showReviewed);
      await h.shot('review/reviewed');
    });

    // No picks on a phone.
    if (v.size != DashSize.phone) {
      testWidgets('shots: bulk bar ($tag)', (tester) async {
        final s = reviewServer();
        final h = await open(tester, server: s.server, db: s.db);
        await h.tap(pick(1));
        await h.tap(pick(2));
        await h.shot('review/bulk');
      });

      testWidgets('shots: bulk partial toast ($tag)', (tester) async {
        final s = reviewServer();
        final h = await open(tester, server: s.server, db: s.db);
        await h.tap(pick(1));
        await h.tap(pick(2));
        flagRows(s.db).removeWhere((r) => r['id'] == 2);
        await h.tap(bulkResolve);
        await h.shot('review/bulk-partial');
        await h.flushTimers();
      });
    }

    testWidgets('shots: loading ($tag)', (tester) async {
      final s = reviewServer();
      final gate = s.server.hold('GET', flagsRoute);
      final h = await open(tester, server: s.server, db: s.db);
      await h.shot('review/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('shots: refused ($tag)', (tester) async {
      final s = reviewServer(persona: Persona.manager);
      final h = await pumpReview(
        tester,
        persona: Persona.manager,
        size: v.size,
        locale: v.locale,
        dark: v.dark,
        server: s.server,
        db: s.db,
      );
      await h.shot('review/refused');
    });

    testWidgets('shots: empty ($tag)', (tester) async {
      final s = reviewServer();
      flagRows(s.db).removeWhere((r) => r['reviewed_at'] == null);
      final h = await open(tester, server: s.server, db: s.db);
      await h.shot('review/empty');
    });
  }
}
