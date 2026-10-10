// The screenshot matrix (SPEC 6.2): the default page at every size in
// English light and Arabic dark; every other state (loading, failed, empty,
// the dialogs, the confirm, a refused save) at desktop-en-light and
// phone-ar-light. Writes PNGs only with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// One PNG per screen of [of] (the page by default), scrolled top to
/// bottom.
Future<void> shootScroll(DashHarness h, String name, {Finder? of}) async {
  final scrolls = find.descendant(
    of: of ?? page,
    matching: find.byType(Scrollable),
  );
  ScrollableState? state;
  for (final e in scrolls.evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis == Axis.vertical) {
      state = s;
      break;
    }
  }
  if (state == null || state.position.maxScrollExtent <= 0) {
    await h.shot('deals/$name-1');
    return;
  }
  final position = state.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('deals/$name-$i');
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
        final s = dealsServer();
        addPromoDeals(s.db, 7);
        final h = await pumpDeals(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          server: s.server,
          db: s.db,
        );
        await shootScroll(h, 'default');
      });
    }
  }

  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang';

    Future<DashHarness> pump(
      WidgetTester tester, {
      String path = dealsPath,
      Persona persona = Persona.owner,
      ({MockServer server, MockDb db})? s,
    }) => pumpDeals(
      tester,
      path: path,
      persona: persona,
      size: size,
      locale: lang,
      dark: dark,
      server: s?.server,
      db: s?.db,
    );

    testWidgets('loading, $tag', (tester) async {
      final s = dealsServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pump(tester, s: s);
      await h.shot('deals/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = dealsServer();
      s.server.fail(
        'GET',
        listRoute,
        MockResponse.error(500, 'Database unavailable'),
        times: null,
      );
      final h = await pump(tester, s: s);
      await h.shot('deals/failed');
    });

    testWidgets('empty, $tag', (tester) async {
      final s = dealsServer();
      s.db.table(OffersTables.deals).clear();
      final h = await pump(tester, s: s);
      await h.shot('deals/empty');
    });

    testWidgets('restricted, $tag', (tester) async {
      final s = serverWithCaps(['orders.read']);
      final h = await pump(tester, s: s, persona: Persona.limited);
      await h.shot('deals/restricted');
    });

    testWidgets('read-only list, $tag', (tester) async {
      final h = await pump(tester, persona: Persona.manager);
      await h.shot('deals/read-only');
    });

    testWidgets('new dialog, $tag', (tester) async {
      final h = await pump(tester, path: '$dealsPath?edit=new');
      await shootScroll(h, 'new-dialog', of: dialog);
      await h.tap(
        find.descendant(of: dialog, matching: find.text(h.t('deals.create'))),
      );
      await shootScroll(h, 'new-dialog-errors', of: dialog);
    });

    testWidgets('edit dialog, buy X get Y with a reward list, $tag', (
      tester,
    ) async {
      final h = await pump(
        tester,
        path: '$dealsPath?edit=${dealId('coffee-cookie-free')}',
      );
      await shootScroll(h, 'edit-dialog', of: dialog);
    });

    testWidgets('edit dialog with windows, read-only, $tag', (tester) async {
      final h = await pump(
        tester,
        path: '$dealsPath?edit=${dealId('weekend-breakfast')}',
        persona: Persona.manager,
      );
      await shootScroll(h, 'read-only-dialog', of: dialog);
    });

    testWidgets('item picker, $tag', (tester) async {
      final h = await pump(tester, path: '$dealsPath?edit=new');
      final trigger = labelledSelect(h.t('combos.choice.pickItem'));
      await h.tester.ensureVisible(trigger);
      await h.tap(trigger);
      await h.shot('deals/item-picker');
    });

    testWidgets('delete confirm, $tag', (tester) async {
      final h = await pump(tester);
      await h.tap(
        inRow(
          'Juice trio for 270',
          find.bySemanticsLabel(h.t('common.delete')),
        ),
      );
      await h.shot('deals/delete-confirm');
    });

    testWidgets('a refused save, $tag', (tester) async {
      final s = dealsServer();
      s.server.fail(
        'PUT',
        itemRoute,
        MockResponse.error(
          400,
          'Check the deal\'s "get_percent".',
          code: 'DEAL_INVALID',
          vars: {'field': 'get_percent'},
        ),
      );
      final h = await pump(
        tester,
        path: '$dealsPath?edit=${dealId('iced-latte-half')}',
        s: s,
      );
      final save = find.descendant(
        of: dialog,
        matching: find.text(h.t('common.save')),
      );
      await h.tester.ensureVisible(save);
      await h.tap(save);
      await h.shot('deals/refused-save');
      await h.flushTimers();
    });
  }
}
