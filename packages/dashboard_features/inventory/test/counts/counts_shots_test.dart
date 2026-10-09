// The Stock counts screenshot matrix: an open count (New Cairo) and All
// branches at {phone, tablet, desktop} x {en light, ar dark}; the first-run
// branch, the history's loading and error, the editor's loading, error and
// empty states, the scope dialog, the variance report and the cancel
// confirmation at desktop-en-light and phone-ar-light. Written only with
// FDASH_SHOTS set; the pages still render (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];
const _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  ScrollableState? state;
  for (final e in find
      .descendant(of: page, matching: find.byType(Scrollable))
      .evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis == Axis.vertical && s.position.maxScrollExtent > 0) {
      state = s;
      break;
    }
  }
  if (state == null) {
    final outer = find.ancestor(of: page, matching: find.byType(Scrollable));
    for (final e in outer.evaluate()) {
      final s = (e as StatefulElement).state as ScrollableState;
      if (s.position.axis == Axis.vertical && s.position.maxScrollExtent > 0) {
        state = s;
        break;
      }
    }
  }
  if (state == null) {
    await h.shot('counts/$name-1');
    return;
  }
  final position = state.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('counts/$name-$i');
    if (y >= position.maxScrollExtent || i >= 5) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('default, New Cairo (open count), $tag', (tester) async {
        final h = await pumpCounts(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          branch: SeedIds.newCairo,
        );
        await shootPage(h, 'default-new-cairo');
        await h.flushTimers();
      });
      testWidgets('default, all branches, $tag', (tester) async {
        final h = await pumpCounts(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'default-all');
      });
    }
  }

  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang';

    testWidgets('first run (Heliopolis), $tag', (tester) async {
      final h = await pumpCounts(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.heliopolis,
      );
      await h.shot('counts/first-run');
    });

    testWidgets('history loading, $tag', (tester) async {
      final s = countsServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpCounts(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.zamalek,
      );
      await h.shot('counts/history-loading');
      gate.release();
      await h.settle();
    });

    testWidgets('history error, $tag', (tester) async {
      final s = countsServer();
      s.server.fail(
        'GET',
        listRoute,
        MockResponse.error(500, 'Counts are resting'),
        times: null,
      );
      final h = await pumpCounts(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.zamalek,
      );
      await h.shot('counts/history-error');
    });

    testWidgets('editor loading, error, empty, $tag', (tester) async {
      final s = countsServer();
      final gate = s.server.hold('GET', getRoute);
      final h = await pumpCounts(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.newCairo,
      );
      await h.shot('counts/editor-loading');
      s.server.fail(
        'GET',
        getRoute,
        MockResponse.error(500, 'down'),
        times: null,
      );
      gate.release();
      await h.settle();
      await h.shot('counts/editor-error');
      s.server.clearFailures();
      s.db[InvTables.stocktakeItems].removeWhere(
        (i) => i['stocktake_id'] == openNewCairo,
      );
      await h.tap(inEditor(find.text(h.t('common.retry'))));
      await h.shot('counts/editor-empty');
      await h.flushTimers();
    });

    testWidgets('scope dialog, $tag', (tester) async {
      final h = await pumpCounts(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.zamalek,
      );
      await h.tap(inPage(byKey('counts-start')));
      await h.shot('counts/scope-full');
      await pick(
        h,
        inScope(byKey('count-scope')),
        h.t('inventory.stocktakes.scopeItems'),
      );
      await pick(h, inScope(byKey('count-scope-add')), 'Oat Milk');
      await pick(h, inScope(byKey('count-scope-add')), 'Sugar');
      await h.shot('counts/scope-items');
      await pick(
        h,
        inScope(byKey('count-scope')),
        h.t('inventory.stocktakes.scopeCategory'),
      );
      await h.tap(inScope(byKey('count-scope-category')));
      await h.shot('counts/scope-category-open');
    });

    testWidgets('editor with a flagged row, the reason list, cancel '
        'confirmation, $tag', (tester) async {
      final h = await pumpCounts(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.newCairo,
      );
      await h.tap(
        find.descendant(
          of: inEditor(byKey('count-filter')),
          matching: find.text(h.t('inventory.stocktakes.filterFlagged')),
        ),
      );
      await h.shot('counts/editor-flagged');
      await h.tap(inEditor(byKey('count-reason-${InvIds.ingredient('croissant')}')));
      await h.shot('counts/editor-reason-open');
      await h.flushTimers();
    });

    testWidgets('variance report, $tag', (tester) async {
      final h = await pumpCounts(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.zamalek,
      );
      await h.tap(inTable(byKey('counts-report-$zamalekFull')));
      await h.shot('counts/variance-report');
    });

    testWidgets('cancel confirmation, $tag', (tester) async {
      final h = await pumpCounts(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.newCairo,
      );
      await h.tap(inEditor(byKey('count-cancel')));
      await h.shot('counts/cancel-confirm');
      await h.flushTimers();
    });
  }
}
