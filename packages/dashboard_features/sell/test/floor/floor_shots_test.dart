// The floor's screenshot matrix: the default state at {phone, tablet,
// desktop} × {en light, ar dark}, scrolled through; and every other state
// (editing with a table picked, the dialogs, the menu, the confirms, the
// conflict, loading, empty, no branch) at desktop-en-light and
// phone-ar-light. Written only with FDASH_SHOTS set; the pages still render
// (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_sell/src/area_seed.dart';
import 'package:dashboard_sell/src/floor/floor_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'floor_support.dart';

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(of: find.byType(FloorPage), matching: find.byType(Scrollable))
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('floor/$name-$i');
    if (y >= position.maxScrollExtent || i >= 6) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

Future<void> _edit(DashHarness h) =>
    h.tap(find.byKey(const ValueKey('floor-lock')));

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpFloor(tester, size: size, locale: lang, dark: dark);
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final tag = '${size.name} $lang';

    testWidgets('editing, a table picked, $tag', (tester) async {
      final h = await pumpFloor(tester, size: size, locale: lang);
      await _edit(h);
      await h.tap(tableBox('T1'));
      await shootPage(h, 'editing');
    });

    testWidgets('add table and area dialogs, $tag', (tester) async {
      final h = await pumpFloor(tester, size: size, locale: lang);
      await _edit(h);
      await h.tap(inFloor(find.text(h.t('floor.addTable'))).first);
      await h.shot('floor/add-table-dialog');
      await h.enterText(find.byKey(const ValueKey('floor-add-label')), '');
      await h.tap(find.text(h.t('floor.addTable')).last);
      await h.shot('floor/add-table-errors');
    });

    testWidgets('area dialog, menu and delete, $tag', (tester) async {
      final h = await pumpFloor(tester, size: size, locale: lang);
      await _edit(h);
      await h.tap(floorText(h.t('floor.addSection')));
      await h.tap(find.text(h.t('common.save')));
      await h.shot('floor/section-dialog');
    });

    testWidgets('area menu and its delete confirm, $tag', (tester) async {
      final h = await pumpFloor(tester, size: size, locale: lang);
      await _edit(h);
      await h.tap(floorText('Terrace').first);
      await h.tap(find.bySemanticsLabel(h.t('floor.sectionActions')));
      await h.shot('floor/area-menu');
      await h.tap(find.text(h.t('common.delete')).last);
      await h.shot('floor/delete-area');
    });

    testWidgets('fulfil dialog and cancel confirm, $tag', (tester) async {
      final h = await pumpFloor(tester, size: size, locale: lang);
      await h.scrollUntilVisible(
        floorText(h.t('floor.fulfill')).first,
        scrollable: find
            .descendant(
              of: find.byType(FloorPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await h.tap(floorText(h.t('floor.fulfill')).first);
      await h.tap(find.text('T7').last);
      await h.shot('floor/fulfill');
      await h.tap(find.text(h.t('common.cancel')).last);
      await h.tap(floorText(h.t('floor.fulfill')).last);
      await h.shot('floor/fulfill-none');
    });

    testWidgets('the layout conflict, $tag', (tester) async {
      final s = floorServer();
      final h = await pumpFloor(tester, size: size, locale: lang, s: s);
      await _edit(h);
      await h.tap(tableBox('T4'));
      s.db[SellTables.floorTables].find(
        SellIds.table('heliopolis', 'T4'),
      )!['updated_at'] = '2026-10-08T06:59:00.000Z';
      await h.tap(find.bySemanticsLabel(h.t('floor.rotateCw')).first);
      await letSave(h);
      await h.shot('floor/conflict');
      await tester.pump(const Duration(seconds: 13));
      await h.settle(rounds: 2);
    });

    testWidgets('loading, $tag', (tester) async {
      final s = floorServer();
      final gate = s.server.hold('GET', tablesPath);
      final h = await pumpFloor(tester, size: size, locale: lang, s: s);
      await h.shot('floor/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed reads, $tag', (tester) async {
      final s = floorServer();
      s.server.fail(
        'GET',
        tablesPath,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpFloor(tester, size: size, locale: lang, s: s);
      await h.shot('floor/failed');
    });

    testWidgets('no branch picked, $tag', (tester) async {
      final h = await pumpFloor(
        tester,
        size: size,
        locale: lang,
        allBranches: true,
      );
      await h.shot('floor/no-branch');
    });

    testWidgets('an empty area, editing, $tag', (tester) async {
      final s = floorServer();
      s.db[SellTables.floorSections].insert({
        'id': 'rooftop',
        'org_id': SeedIds.sabahOrg,
        'branch_id': SeedIds.heliopolis,
        'name': 'Rooftop',
        'ordering': 2,
        'canvas_w': 1000,
        'canvas_h': 700,
      });
      final h = await pumpFloor(tester, size: size, locale: lang, s: s);
      await _edit(h);
      await h.tap(floorText('Rooftop'));
      await h.shot('floor/empty-area');
    });
  }
}
