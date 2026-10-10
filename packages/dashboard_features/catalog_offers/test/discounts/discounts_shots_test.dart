// The screenshot matrix (SPEC 6.2): the default page at every size in
// English light and Arabic dark; every other state (loading, failed, empty,
// the dialogs, the confirm, a refused save) at desktop-en-light and
// phone-ar-light. Writes PNGs only with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// One PNG per screen of the page, scrolled top to bottom.
Future<void> shootPage(DashHarness h, String name) async {
  final scrolls = find.descendant(of: page, matching: find.byType(Scrollable));
  ScrollableState? state;
  for (final e in scrolls.evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis == Axis.vertical) {
      state = s;
      break;
    }
  }
  if (state == null || state.position.maxScrollExtent <= 0) {
    await h.shot('discounts/$name-1');
    return;
  }
  final position = state.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('discounts/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

const List<(DashSize, String, bool)> _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final s = discountsServer();
        addPromos(s.db, 6);
        final h = await pumpDiscounts(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          server: s.server,
          db: s.db,
        );
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang';

    testWidgets('loading, $tag', (tester) async {
      final s = discountsServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpDiscounts(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
      );
      await h.shot('discounts/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = discountsServer();
      s.server.fail(
        'GET',
        listRoute,
        MockResponse.error(500, 'Database unavailable'),
        times: null,
      );
      final h = await pumpDiscounts(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
      );
      await h.shot('discounts/failed');
    });

    testWidgets('empty, $tag', (tester) async {
      final s = discountsServer();
      s.db.table(OffersTables.discounts).clear();
      final h = await pumpDiscounts(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
      );
      await h.shot('discounts/empty');
    });

    testWidgets('new dialog, $tag', (tester) async {
      final h = await pumpDiscounts(
        tester,
        path: '/discounts?edit=new',
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('discounts/new-dialog');
      await h.tap(
        find.descendant(of: dialog, matching: find.text(h.t('common.create'))),
      );
      await h.shot('discounts/new-dialog-errors');
    });

    testWidgets('edit dialog, $tag', (tester) async {
      final h = await pumpDiscounts(
        tester,
        path: '/discounts?edit=${discountId('loyalty-welcome')}',
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('discounts/edit-dialog');
    });

    testWidgets('delete confirm, $tag', (tester) async {
      final h = await pumpDiscounts(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(labelled(h.t('common.delete')).first);
      await h.shot('discounts/delete-confirm');
    });

    testWidgets('search with no match, $tag', (tester) async {
      final h = await pumpDiscounts(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.enterText(labelled(h.t('common.search')), 'zzz');
      await h.shot('discounts/search-empty');
    });
  }

  testWidgets('no org (platform admin), desktop en', (tester) async {
    final h = await pumpDiscounts(tester, persona: Persona.platform);
    await h.shot('discounts/no-org');
  });
}
