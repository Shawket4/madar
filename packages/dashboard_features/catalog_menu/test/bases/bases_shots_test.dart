// The `bases` unit's screenshot matrix: `/menu/bases` and `/menu/packaging`
// at {phone, tablet, desktop} x {en light, ar dark}, scrolled through the
// whole page; and every other state (loading, failed, empty, read-only, the
// applied counts, the delete confirm, the editors and their pickers) at
// desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set;
// the pages still render (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/bases/base_editor_dialog.dart';
import 'package:dashboard_catalog_menu/src/bases/bases_page.dart';
import 'package:dashboard_catalog_menu/src/bases/packaging_rules_page.dart';
import 'package:dashboard_catalog_menu/src/bases/rule_dialog.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];

/// Shoots [page] top to bottom: `<shot>-1`, `<shot>-2`, …
Future<void> shootPage(DashHarness h, Type page, String shot) async {
  final scroll = find
      .descendant(of: find.byType(page), matching: find.byType(Scrollable))
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('$shot-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

Future<void> _tapIn(DashHarness h, Type scope, String text) =>
    h.tap(find.descendant(of: find.byType(scope), matching: find.text(text)));

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('bases default, $tag', (tester) async {
        final h = await pumpMenu(tester, size: size, locale: lang, dark: dark);
        await shootPage(h, RecipeBasesPage, 'bases/default');
      });

      testWidgets('packaging default, $tag', (tester) async {
        final h = await pumpMenu(
          tester,
          path: packagingPath,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, PackagingRulesPage, 'packaging/default');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final tag = '${size.name} $lang';

    // ── /menu/bases ──────────────────────────────────────────────────────

    testWidgets('bases loading, $tag', (tester) async {
      final s = menuServer();
      final gate = s.server.hold('GET', '/recipe-bases');
      final h = await pumpMenu(tester, size: size, locale: lang, seeded: s);
      await h.shot('bases/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('bases failed, $tag', (tester) async {
      final s = menuServer();
      s.server.fail(
        'GET',
        '/recipe-bases',
        MockResponse.error(500, 'Database is down'),
        times: null,
      );
      final h = await pumpMenu(tester, size: size, locale: lang, seeded: s);
      await h.shot('bases/error');
      h.server.clearFailures();
    });

    testWidgets('bases empty, $tag', (tester) async {
      final s = menuServer();
      CatalogMenuSeed.loadInto(s.db);
      s.db[MenuTables.bases].clear();
      final h = await pumpMenu(tester, size: size, locale: lang, seeded: s);
      await h.shot('bases/empty');
    });

    testWidgets('bases read-only, $tag', (tester) async {
      final h = await pumpMenu(
        tester,
        size: size,
        locale: lang,
        persona: Persona.manager,
      );
      await h.shot('bases/read-only');
    });

    testWidgets('bases delete confirm, $tag', (tester) async {
      final h = await pumpMenu(tester, size: size, locale: lang);
      await h.tap(labelIn(rowOf(icedBase), h.t('common.delete')));
      await h.shot('bases/delete-confirm');
    });

    testWidgets('bases editor new, required, picker, $tag', (tester) async {
      final h = await pumpMenu(tester, size: size, locale: lang);
      await _tapIn(h, RecipeBasesPage, h.t('modeling.bases.new'));
      await h.shot('bases/editor-new');
      await _tapIn(h, BaseEditorDialog, h.t('common.save'));
      await h.shot('bases/editor-required');
      await h.tap(
        find.descendant(
          of: find.byType(BaseEditorDialog),
          matching: find.text(h.t('modeling.grid.addIngredient')),
        ),
      );
      await h.shot('bases/editor-picker');
    });

    testWidgets('bases editor edit, used by, $tag', (tester) async {
      final h = await pumpMenu(tester, size: size, locale: lang);
      await h.tap(labelIn(rowOf(espressoBase), h.t('common.edit')));
      await h.shot('bases/editor-edit');
      await _tapIn(h, BaseEditorDialog, h.t('modeling.bases.usedBy'));
      await h.scrollUntilVisible(
        find.text(h.t('common.save')).last,
        scrollable: find
            .descendant(
              of: find.byType(BaseEditorDialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await h.shot('bases/editor-used-by');
    });

    // ── /menu/packaging ──────────────────────────────────────────────────

    testWidgets('packaging loading, $tag', (tester) async {
      final s = menuServer();
      final gate = s.server.hold('GET', '/packaging-rules');
      final h = await pumpMenu(
        tester,
        path: packagingPath,
        size: size,
        locale: lang,
        seeded: s,
      );
      await h.shot('packaging/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('packaging failed, $tag', (tester) async {
      final s = menuServer();
      s.server.fail(
        'GET',
        '/packaging-rules',
        MockResponse.error(500, 'Database is down'),
        times: null,
      );
      final h = await pumpMenu(
        tester,
        path: packagingPath,
        size: size,
        locale: lang,
        seeded: s,
      );
      await h.shot('packaging/error');
      h.server.clearFailures();
    });

    testWidgets('packaging empty, $tag', (tester) async {
      final s = menuServer();
      CatalogMenuSeed.loadInto(s.db);
      s.db[MenuTables.rules].clear();
      final h = await pumpMenu(
        tester,
        path: packagingPath,
        size: size,
        locale: lang,
        seeded: s,
      );
      await h.shot('packaging/empty');
    });

    testWidgets('packaging read-only, $tag', (tester) async {
      final h = await pumpMenu(
        tester,
        path: packagingPath,
        size: size,
        locale: lang,
        persona: Persona.manager,
      );
      await h.shot('packaging/read-only');
    });

    testWidgets('packaging applied, $tag', (tester) async {
      final h = await pumpMenu(
        tester,
        path: packagingPath,
        size: size,
        locale: lang,
      );
      await _tapIn(h, PackagingRulesPage, h.t('modeling.packaging.apply'));
      await h.shot('packaging/applied');
    });

    testWidgets('packaging delete confirm, $tag', (tester) async {
      final h = await pumpMenu(
        tester,
        path: packagingPath,
        size: size,
        locale: lang,
      );
      await h.tap(
        labelIn(rowOf(MenuSeedIds.rule('iced')), h.t('common.delete')),
      );
      await h.shot('packaging/delete-confirm');
    });

    testWidgets('packaging dialog new, required, pickers, $tag', (
      tester,
    ) async {
      final h = await pumpMenu(
        tester,
        path: packagingPath,
        size: size,
        locale: lang,
      );
      await _tapIn(h, PackagingRulesPage, h.t('modeling.packaging.new'));
      await h.shot('packaging/dialog-new');
      await _tapIn(h, RuleDialog, h.t('common.save'));
      await h.shot('packaging/dialog-required');
      await h.tap(
        find.descendant(
          of: find.byType(RuleDialog),
          matching: find.byWidgetPredicate(
            (w) =>
                w is DashSelect &&
                w.semanticLabel == h.t('modeling.packaging.matchCategory'),
          ),
        ),
      );
      await h.shot('packaging/dialog-category');
    });

    testWidgets('packaging dialog edit, $tag', (tester) async {
      final h = await pumpMenu(
        tester,
        path: packagingPath,
        size: size,
        locale: lang,
      );
      await h.tap(
        labelIn(rowOf(MenuSeedIds.rule('hot_large')), h.t('common.edit')),
      );
      await h.shot('packaging/dialog-edit');
    });
  }
}
