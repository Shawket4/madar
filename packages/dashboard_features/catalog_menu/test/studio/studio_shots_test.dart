// The studio's screenshot matrix: the default state (Spanish Latte: base and
// packaging lines, written steps, two groups) at {phone, tablet, desktop} x
// {en light, ar dark}, scrolled through the whole page; and its other states
// at desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set;
// the page still renders (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/studio/menu_studio_page.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(
        of: find.byType(MenuStudioPage),
        matching: find.byType(Scrollable),
      )
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('studio/$name-$i');
    if (y >= position.maxScrollExtent) break;
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
      testWidgets('default, $tag', (tester) async {
        final s = studioServer();
        seedBreakfastCombo(s.db);
        final h = await pumpStudio(
          tester,
          key: 'spanish',
          size: size,
          locale: lang,
          dark: dark,
          seeded: s,
        );
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang) in [(DashSize.desktop, 'en'), (DashSize.phone, 'ar')]) {
    final tag = '${size.name} $lang';

    testWidgets('loading, $tag', (tester) async {
      final s = studioServer();
      final gate = s.server.hold('GET', studioT);
      final h = await pumpStudio(tester, size: size, locale: lang, seeded: s);
      await h.shot('studio/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('unsaved changes, $tag', (tester) async {
      final h = await pumpStudio(tester, size: size, locale: lang);
      await h.enterText(fieldWithText('Caffè Latte'), 'Caffè Latte Deluxe');
      await h.enterText(fieldWithText('115'), '120');
      await h.shot('studio/unsaved');
    });

    testWidgets('duplicate confirm, $tag', (tester) async {
      final h = await pumpStudio(tester, size: size, locale: lang);
      await h.tap(studioText(h.t('menu.grid.duplicate')));
      await h.shot('studio/duplicate-confirm');
    });

    testWidgets('column menu and copy from, $tag', (tester) async {
      final h = await pumpStudio(tester, size: size, locale: lang);
      await h.tap(studioLabel(h.t('modeling.grid.columnActions')).at(1));
      await h.shot('studio/column-menu');
      // A person taps the row where it is (no scrolling to it first).
      await tester.tap(find.bySemanticsLabel(h.t('modeling.grid.copyFrom')));
      await h.settle();
      await h.shot('studio/column-copy-from');
    });

    testWidgets('scale dialog, $tag', (tester) async {
      final h = await pumpStudio(tester, size: size, locale: lang);
      await h.tap(studioLabel(h.t('modeling.grid.columnActions')).at(1));
      await h.tap(find.bySemanticsLabel(h.t('modeling.grid.scale')));
      await h.shot('studio/scale-dialog');
    });

    testWidgets('base picker open, $tag', (tester) async {
      final h = await pumpStudio(tester, size: size, locale: lang);
      await h.tap(find.byKey(const ValueKey('studio-base-picker')));
      await h.shot('studio/base-picker-open');
    });

    testWidgets('set cost, $tag', (tester) async {
      final h = await pumpStudio(
        tester,
        key: 'pistachio_latte',
        size: size,
        locale: lang,
      );
      await h.tap(studioText(h.t('menu.studio.recipe.setCost')));
      await h.shot('studio/set-cost');
    });

    testWidgets('linked copy, $tag', (tester) async {
      final s = studioServer();
      linkCopy(s.db, 'iced_spanish', 'spanish');
      final h = await pumpStudio(
        tester,
        key: 'iced_spanish',
        size: size,
        locale: lang,
        seeded: s,
      );
      await h.scrollUntilVisible(
        studioText(h.t('modeling.linked.follows')),
        scrollable: inStudio(find.byType(Scrollable)).first,
      );
      await h.shot('studio/linked-copy');
      await h.tap(studioText(h.t('modeling.linked.unlink')));
      await h.shot('studio/unlink-confirm');
    });

    testWidgets('read-only (manager), $tag', (tester) async {
      final h = await pumpStudio(
        tester,
        key: 'spanish',
        persona: Persona.manager,
        size: size,
        locale: lang,
      );
      await shootPage(h, 'read-only');
    });

    testWidgets('step picker, $tag', (tester) async {
      final h = await pumpStudio(tester, size: size, locale: lang);
      await h.tap(studioText(h.t('menu.studio.steps.addFromLibrary')));
      await h.shot('studio/step-picker');
    });

    testWidgets('meal picked and preview with choices, $tag', (tester) async {
      final s = studioServer();
      seedBreakfastCombo(s.db);
      final h = await pumpStudio(tester, size: size, locale: lang, seeded: s);
      final triggers = inSection(
        h.t('combos.meal.title'),
        find.byType(DashSelectTrigger),
      );
      await h.tap(triggers.first);
      await h.tap(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is DashOptionList),
          matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? '').contains('Breakfast'),
          ),
        ),
      );
      await h.tester.ensureVisible(studioText(h.t('combos.meal.title')));
      await h.settle(rounds: 2);
      await h.shot('studio/meal-picked');
      await h.tap(inStudio(find.widgetWithText(DashChoiceChip, 'Large')));
      await h.tap(
        inStudio(
          find.ancestor(
            of: find.textContaining('Oat milk'),
            matching: find.byType(DashChoiceChip),
          ),
        ),
      );
      await h.flushTimers();
      await h.scrollUntilVisible(
        studioText(h.t('modeling.preview.cost')),
        scrollable: inStudio(find.byType(Scrollable)).first,
      );
      await h.shot('studio/preview-choices');
    });

    testWidgets('failed, $tag', (tester) async {
      final s = studioServer();
      s.server.fail(
        'GET',
        studioT,
        MockResponse.notFound('Menu item not found'),
        times: null,
      );
      final h = await pumpStudio(tester, size: size, locale: lang, seeded: s);
      await h.shot('studio/failed');
    });
  }
}
