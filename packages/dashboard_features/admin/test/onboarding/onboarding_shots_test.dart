// The wizard's screenshot matrix: a fresh café at {phone, tablet, desktop} x
// {en light, ar dark}, scrolled through; every other state (loading, failed,
// the finale, the celebration, a step with counts, each inline editor) at
// desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set;
// the pages still render (and must not overflow) without.
import 'package:dashboard_admin/src/onboarding/step_navigator.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Shoots [scroll] top to bottom: `<name>-1`, `<name>-2`, …
Future<void> _shootScroll(DashHarness h, Finder scroll, String name) async {
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('onboarding/$name-$i');
    if (y >= position.maxScrollExtent || i >= 4) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

Future<void> shootPage(DashHarness h, String name) => _shootScroll(
  h,
  find.descendant(of: page, matching: find.byType(Scrollable)).first,
  name,
);

/// Shoots the open editor top to bottom.
Future<void> shootSurface(DashHarness h, String name) => _shootScroll(
  h,
  find.descendant(of: surface, matching: find.byType(Scrollable)).first,
  name,
);

/// Opens [title]'s step: from the navigator when there is one, else by
/// Continue until it shows.
Future<void> openStep(DashHarness h, String title) async {
  final nav = find.byType(OnbStepNavigator);
  if (nav.evaluate().isNotEmpty) {
    await h.tap(
      find.descendant(of: nav, matching: find.bySemanticsLabel(RegExp(title))),
    );
    return;
  }
  for (var i = 0; i < 10 && inPage(title).evaluate().isEmpty; i++) {
    await h.tap(buttonOf(h.t('onboarding.continue')));
  }
}

const _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

Future<DashHarness> _pump(
  WidgetTester tester,
  DashSize size,
  String lang,
  bool dark, {
  void Function(MockDb db)? seed,
  void Function(MockServer server)? answer,
}) async {
  final s = onboardingServer();
  freshCafe(s.db);
  seed?.call(s.db);
  answer?.call(s.server);
  return pumpOnboarding(
    tester,
    server: s.server,
    db: s.db,
    size: size,
    locale: lang,
    dark: dark,
  );
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await _pump(tester, size, lang, dark);
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang, dark) in _states) {
    final at = '${size.name} $lang';

    testWidgets('loading, $at', (tester) async {
      final s = onboardingServer();
      final gate = s.server.hold('GET', statusRoute);
      final h = await pumpOnboarding(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
      );
      await h.shot('onboarding/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $at', (tester) async {
      final h = await _pump(
        tester,
        size,
        lang,
        dark,
        answer: (s) => s.fail(
          'GET',
          statusRoute,
          MockResponse.error(500, 'boom'),
          times: null,
        ),
      );
      await h.shot('onboarding/failed');
    });

    testWidgets('counts and the menu step, $at', (tester) async {
      final h = await _pump(
        tester,
        size,
        lang,
        dark,
        seed: (db) {
          addBranch(db);
          addCategory(db);
          addCategory(db, name: 'Pastries', ar: 'مخبوزات');
        },
      );
      await openStep(h, h.t('onboarding.steps.menu_items.title'));
      await shootPage(h, 'menu-items');
    });

    testWidgets('no category yet, $at', (tester) async {
      final h = await _pump(tester, size, lang, dark);
      await openStep(h, h.t('onboarding.steps.menu_items.title'));
      await h.shot('onboarding/menu-items-no-category');
    });

    testWidgets('recipes list, $at', (tester) async {
      final h = await _pump(
        tester,
        size,
        lang,
        dark,
        seed: (db) {
          final cat = addCategory(db);
          for (final (en, ar) in [
            ('Latte', 'لاتيه'),
            ('Flat white', 'فلات وايت'),
            (
              'Turkish coffee with cardamom and a long name',
              'قهوة تركي محوّجة بالحبهان',
            ),
          ]) {
            addItem(db, cat, name: en, ar: ar);
          }
        },
      );
      await openStep(h, h.t('onboarding.steps.recipes.title'));
      await h.shot('onboarding/recipes');
    });

    testWidgets('ready to open, $at', (tester) async {
      final h = await _pump(tester, size, lang, dark, seed: everythingDone);
      await shootPage(h, 'finale');
    });

    testWidgets('celebration, $at', (tester) async {
      final h = await _pump(tester, size, lang, dark, seed: everythingDone);
      h.allowUnmatched = true;
      await h.tap(buttonOf(h.t('onboarding.steps.go_live.cta')));
      await h.shot('onboarding/celebration');
      await tester.pump(const Duration(seconds: 2));
      await h.settle();
    });

    testWidgets('payment method editor, $at', (tester) async {
      final h = await _pump(tester, size, lang, dark);
      await openStep(h, h.t('onboarding.steps.payment_methods.title'));
      await h.tap(buttonOf(h.t('onboarding.steps.payment_methods.cta')));
      await h.tap(buttonOf(h.t('common.save'), within: surface));
      await shootSurface(h, 'payment-method');
    });

    testWidgets('ingredient editor, $at', (tester) async {
      final h = await _pump(tester, size, lang, dark);
      await openStep(h, h.t('onboarding.steps.ingredients.title'));
      await h.tap(buttonOf(h.t('onboarding.steps.ingredients.cta')));
      await h.shot('onboarding/ingredient');
    });

    testWidgets('category editor, $at', (tester) async {
      final h = await _pump(tester, size, lang, dark);
      await openStep(h, h.t('onboarding.steps.categories.title'));
      await h.tap(buttonOf(h.t('onboarding.steps.categories.cta')));
      await h.tap(buttonOf(h.t('common.save'), within: surface));
      await h.shot('onboarding/category');
    });

    testWidgets('add-on editor and a new group, $at', (tester) async {
      final h = await _pump(
        tester,
        size,
        lang,
        dark,
        seed: (db) => addIngredient(db),
      );
      await openStep(h, h.t('onboarding.steps.addons.title'));
      await h.tap(buttonOf(h.t('onboarding.steps.addons.cta')));
      await h.shot('onboarding/addon');
      await h.tap(buttonOf(h.t('menu.groups.new'), within: surface));
      await h.tap(
        buttonOf(h.t('menu.groups.editor.addOption'), within: surface),
      );
      await h.tap(buttonOf(h.t('menu.groups.editor.addLine'), within: surface));
      await h.tap(buttonOf(h.t('common.save'), within: surface));
      await shootSurface(h, 'group-editor');
    });

    testWidgets('menu item editor, $at', (tester) async {
      final h = await _pump(
        tester,
        size,
        lang,
        dark,
        seed: (db) {
          addCategory(db);
          addIngredient(db);
        },
      );
      await openStep(h, h.t('onboarding.steps.menu_items.title'));
      await h.tap(buttonOf(h.t('onboarding.steps.menu_items.cta')));
      await h.tap(field('item-add-size'));
      await shootSurface(h, 'menu-item');
    });

    testWidgets('editing an item from recipes, $at', (tester) async {
      final h = await _pump(
        tester,
        size,
        lang,
        dark,
        seed: (db) {
          addItem(db, addCategory(db));
          addIngredient(db);
        },
      );
      await openStep(h, h.t('onboarding.steps.recipes.title'));
      await h.tap(buttonOf(h.t('onboarding.steps.recipes.addFor')).first);
      await h.tap(
        find.descendant(
          of: field('recipe-size-0'),
          matching: find.text(h.t('recipes.addIngredient')),
        ),
      );
      await shootSurface(h, 'menu-item-edit');
    });
  }
}
