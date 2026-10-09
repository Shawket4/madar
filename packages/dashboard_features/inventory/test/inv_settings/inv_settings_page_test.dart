// Inventory settings, driven through the real shell: the header, the
// tolerance card and its Save, the categories list and its states, the phone
// layout, the gating and the persona refusals (INV-SET rows; the category
// actions are in inv_settings_categories_test.dart).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder get _pct => inPage(byKey('inv-settings-pct'));
Finder get _save => inPage(byKey('inv-settings-save'));
Finder get _tolerance => inPage(byKey('inv-settings-tolerance'));
Finder get _categories => inPage(byKey('inv-settings-categories'));

String _pctText(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(of: _pct, matching: find.byType(EditableText)),
    )
    .controller
    .text;

bool _enabled(WidgetTester tester, Finder f) =>
    tester.widget<DashButton>(f).onPressed != null;

bool _pctEnabled(WidgetTester tester) =>
    tester.widget<DashTextInput>(_pct).enabled;

void main() {
  testWidgets('INV-SET-001 header: title and subtitle at reading width, no '
      'actions', (tester) async {
    final h = await pumpSettings(tester);
    expect(inPage(find.text('Inventory settings')), findsWidgets);
    expect(
      inPage(find.text('Organization-wide inventory rules')),
      findsOneWidget,
    );
    final scaffold = tester.widget<DashPageScaffold>(
      inPage(find.byType(DashPageScaffold)),
    );
    expect(scaffold.width, DashPageWidth.reading);
    expect(scaffold.actions, isEmpty);
    expect(h.location.path, settingsPath);
  });

  testWidgets('INV-SET-002 a platform admin with no organization: "Select an '
      'organization to manage inventory", nothing read', (tester) async {
    final h = await pumpSettings(tester, persona: Persona.platform);
    expect(
      find.text('Select an organization to manage inventory'),
      findsOneWidget,
    );
    expect(find.text('Inventory settings'), findsWidgets);
    expect(h.server.callsTo(settingsRoute), isEmpty);
    expect(h.server.callsTo(categoriesRoute), isEmpty);
  });

  testWidgets('INV-SET-002 a platform admin with Sabah picked sees the page', (
    tester,
  ) async {
    final h = await pumpSettings(
      tester,
      persona: Persona.platform,
      prefs: sabahPicked(),
    );
    expect(_pctText(tester), '5');
    expect(
      h.server.callsTo(settingsRoute).single.path,
      '/inventory/orgs/$org/settings',
    );
  });

  testWidgets('INV-SET-003 reads the org settings and categories once each', (
    tester,
  ) async {
    final h = await pumpSettings(tester);
    expect(
      h.server.callsTo(settingsRoute, method: 'GET').single.path,
      '/inventory/orgs/$org/settings',
    );
    expect(
      h.server.callsTo(categoriesRoute, method: 'GET').single.path,
      '/inventory/orgs/$org/categories',
    );
  });

  testWidgets('INV-SET-004 the tolerance card: title and description', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(
      find.descendant(
        of: _tolerance,
        matching: find.text('Stock-count variance tolerance'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _tolerance,
        matching: textHas('at least this percent. Flagged items need a reason'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('INV-SET-005 "Percent" field prefilled from the server, a % '
      'inside it; disabled while loading', (tester) async {
    final s = settingsServer();
    s.db[InvTables.settings].update(org, {
      'stocktake_variance_threshold_pct': 2.5,
    });
    final gate = s.server.hold('GET', settingsRoute);
    final h = await pumpSettings(tester, server: s.server, db: s.db);
    expect(
      find.descendant(of: _tolerance, matching: find.text('Percent')),
      findsOneWidget,
    );
    expect(find.descendant(of: _pct, matching: find.text('%')), findsOneWidget);
    expect(_pctText(tester), '');
    expect(_pctEnabled(tester), isFalse);
    expect(_enabled(tester, _save), isFalse);
    gate.release();
    await h.settle();
    expect(_pctText(tester), '2.5');
    expect(_pctEnabled(tester), isTrue);
    expect(_enabled(tester, _save), isTrue);
  });

  testWidgets('INV-SET-006 Save PUTs the number, refetches and toasts '
      '"Settings saved"', (tester) async {
    final h = await pumpSettings(tester);
    await h.enterText(_pct, '7.5');
    await h.tap(_save);
    final put = h.server.callsTo(settingsRoute, method: 'PUT').single;
    expect(put.path, '/inventory/orgs/$org/settings');
    expect(put.body, {'stocktake_variance_threshold_pct': 7.5});
    expect(h.server.callsTo(settingsRoute, method: 'GET'), hasLength(2));
    expect(h.server.callsTo(categoriesRoute, method: 'GET'), hasLength(2));
    await h.expectToast('Settings saved');
    expect(_pctText(tester), '7.5');
  });

  testWidgets('INV-SET-006 a blank field disables Save', (tester) async {
    final h = await pumpSettings(tester);
    await h.enterText(_pct, '');
    expect(_enabled(tester, _save), isFalse);
    expect(h.server.callsTo(settingsRoute, method: 'PUT'), isEmpty);
  });

  testWidgets('INV-SET-006 (divergence) a negative or unreadable value asks '
      'nothing and the field says why', (tester) async {
    final h = await pumpSettings(tester);
    await h.enterText(_pct, '-1');
    await h.tap(_save);
    expect(h.server.callsTo(settingsRoute, method: 'PUT'), isEmpty);
    expect(
      find.descendant(of: _tolerance, matching: find.text('0 % or more')),
      findsOneWidget,
    );
    expect(
      tester.widget<DashTextInput>(_pct).invalid,
      isTrue,
      reason: 'the field is marked',
    );
    await h.enterText(_pct, 'abc');
    expect(
      tester.widget<DashTextInput>(_pct).invalid,
      isFalse,
      reason: 'typing clears the message',
    );
    await h.tap(_save);
    expect(h.server.callsTo(settingsRoute, method: 'PUT'), isEmpty);
    expect(tester.widget<DashTextInput>(_pct).invalid, isTrue);
    expect(
      find.descendant(
        of: _tolerance,
        matching: find.text('"abc" isn\'t a number'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('INV-SET-006 over 100: the server\'s 400 is a toast', (
    tester,
  ) async {
    final h = await pumpSettings(tester);
    await h.enterText(_pct, '150');
    await h.tap(_save);
    expect(h.server.callsTo(settingsRoute, method: 'PUT').single.status, 400);
    await h.expectToast(
      h.refusalWords(
        MockResponse.badRequest(
          'stocktake_variance_threshold_pct must be between 0 and 100',
        ),
      ),
    );
    expect(_pctText(tester), '150', reason: 'the typed value stays');
  });

  testWidgets('INV-SET-006 a form seeded from the cache re-seeds on a '
      'background refresh until edited', (tester) async {
    final s = settingsServer();
    final h = await pumpSettings(tester, server: s.server, db: s.db);
    expect(_pctText(tester), '5');
    s.db[InvTables.settings].update(org, {
      'stocktake_variance_threshold_pct': 8,
    });
    h.container.read(realtimeBusProvider).invalidate(const ['/inventory']);
    await h.settle();
    expect(_pctText(tester), '8', reason: 'not edited: follows the server');
    await h.enterText(_pct, '6');
    s.db[InvTables.settings].update(org, {
      'stocktake_variance_threshold_pct': 9,
    });
    h.container.read(realtimeBusProvider).invalidate(const ['/inventory']);
    await h.settle();
    expect(_pctText(tester), '6', reason: 'edited: the typed value stays');
  });

  testWidgets('INV-SET-007 the settings read fails: no error UI, the field '
      'stays disabled and empty, Save disabled', (tester) async {
    final s = settingsServer();
    s.server.fail(
      'GET',
      settingsRoute,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    await pumpSettings(tester, server: s.server, db: s.db);
    expect(_pctText(tester), '');
    expect(_pctEnabled(tester), isFalse);
    expect(_enabled(tester, _save), isFalse);
    expect(
      find.descendant(of: _tolerance, matching: find.byType(DashErrorState)),
      findsNothing,
    );
    expect(inList(find.text('General')), findsOneWidget);
  });

  testWidgets('INV-SET-008 the categories card: Tags icon, title, '
      'description', (tester) async {
    await pumpSettings(tester);
    final header = tester.widget<DashSectionHeader>(
      find.descendant(
        of: _categories,
        matching: find.byType(DashSectionHeader),
      ),
    );
    expect(header.icon, 'tags');
    expect(header.title, 'Ingredient categories');
    expect(header.description, startsWith('Group ingredients for counting'));
  });

  testWidgets('INV-SET-009 the list by sort order then name; each row: name, '
      'slug · "{{count}} ingredients"', (tester) async {
    final s = settingsServer();
    // Same sort order as Milk: the name breaks the tie.
    addEmptyCategory(s.db, name: 'Almond', sort: 2);
    await pumpSettings(tester, server: s.server, db: s.db);
    final ids = [for (final c in invCategories) cat(c.slug), cat('almond')];
    expect(orderOf(tester, ids.reversed), [
      cat('general'),
      cat('coffee_bean'),
      cat('almond'),
      cat('milk'),
      cat('dairy'),
      cat('syrup'),
      cat('dry_goods'),
      cat('bakery'),
      cat('packaging'),
    ]);
    final milk = usersOf(s.db, 'milk');
    expect(milk, greaterThan(0));
    expect(inRow('milk', find.text('Milk')), findsOneWidget);
    expect(inRow('milk', textHas('milk · $milk ingredients')), findsOneWidget);
    expect(inRow('almond', textHas('almond · 0 ingredients')), findsOneWidget);
  });

  testWidgets('INV-SET-009 the name tie-break ignores case (localeCompare)', (
    tester,
  ) async {
    final s = settingsServer();
    addEmptyCategory(s.db, name: 'beta', sort: 20);
    addEmptyCategory(s.db, name: 'Alpha', sort: 20);
    addEmptyCategory(s.db, name: 'Gamma', sort: 20);
    await pumpSettings(tester, server: s.server, db: s.db);
    expect(orderOf(tester, [cat('gamma'), cat('beta'), cat('alpha')]), [
      cat('alpha'),
      cat('beta'),
      cat('gamma'),
    ]);
    // (divergence) English singular: "1 ingredient", not "1 ingredients".
    expect(usersOf(s.db, 'general'), 1);
    expect(
      inRow(
        'general',
        find.byWidgetPredicate(
          (w) =>
              w is RichText && w.text.toPlainText() == 'general · 1 ingredient',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('INV-SET-011 "Default" badge on General only', (tester) async {
    await pumpSettings(tester);
    expect(inRow('general', find.text('Default')), findsOneWidget);
    expect(inList(find.text('Default')), findsOneWidget);
  });

  testWidgets('INV-SET-017 categories loading: 4 skeleton rows; the add row '
      'is there (INV-SET-025)', (tester) async {
    final s = settingsServer();
    final gate = s.server.hold('GET', categoriesRoute);
    final h = await pumpSettings(tester, server: s.server, db: s.db);
    final loading = inPage(byKey('inv-settings-categories-loading'));
    expect(loading, findsOneWidget);
    expect(
      find.descendant(of: loading, matching: find.byType(DashSkeleton)),
      findsNWidgets(12),
    );
    expect(inPage(byKey('inv-settings-new-name')), findsOneWidget);
    expect(inPage(textHas('Categories you add')), findsNothing);
    gate.release();
    await h.settle();
    expect(inList(find.text('General')), findsOneWidget);
  });

  testWidgets('INV-SET-018 categories error: "Couldn\'t load ingredient '
      'categories" + Retry, which asks only that read; the add row stays '
      '(INV-SET-025)', (tester) async {
    final s = settingsServer();
    s.server.fail('GET', categoriesRoute, MockResponse.error(500, 'boom'));
    final h = await pumpSettings(tester, server: s.server, db: s.db);
    final error = inPage(byKey('inv-settings-categories-error'));
    expect(
      find.descendant(
        of: error,
        matching: find.text("Couldn't load ingredient categories"),
      ),
      findsOneWidget,
    );
    expect(inPage(byKey('inv-settings-new-name')), findsOneWidget);
    expect(_pctText(tester), '5', reason: 'the tolerance card is unaffected');
    final settingsBefore = h.server.callsTo(settingsRoute).length;
    await h.tap(find.descendant(of: error, matching: find.text('Retry')));
    expect(h.server.callsTo(categoriesRoute, method: 'GET'), hasLength(2));
    expect(h.server.callsTo(settingsRoute).length, settingsBefore);
    expect(inList(find.text('General')), findsOneWidget);
  });

  testWidgets('INV-SET-019 no categories: the centred hint line', (
    tester,
  ) async {
    final s = settingsServer();
    s.server.fail(
      'GET',
      categoriesRoute,
      MockResponse.ok(const []),
      times: null,
    );
    await pumpSettings(tester, server: s.server, db: s.db);
    expect(
      inList(
        find.text('Categories you add appear here and in the ingredient form.'),
      ),
      findsOneWidget,
    );
    expect(inPage(byKey('inv-settings-new-name')), findsOneWidget);
  });

  testWidgets('INV-SET-022 phone: one column; a row\'s controls stay on one '
      'line beside the name', (tester) async {
    await pumpSettings(tester, size: DashSize.phone);
    final y = tester.getCenter(row('milk')).dy;
    final controls = [
      inRow('milk', find.byType(DashSwitch)),
      inRow('milk', byKey('inv-category-edit-${cat('milk')}')),
      inRow('milk', byKey('inv-category-delete-${cat('milk')}')),
    ];
    final ys = {for (final f in controls) tester.getCenter(f).dy};
    expect(ys, hasLength(1), reason: 'one line');
    expect((ys.single - y).abs(), lessThan(1), reason: 'centred in the row');
    expect(
      tester.getCenter(inRow('milk', find.text('Milk'))).dx,
      lessThan(tester.getCenter(controls.first).dx),
    );
    expect(
      tester.getTopLeft(_tolerance).dx,
      tester.getTopLeft(_categories).dx,
      reason: 'single column',
    );
  });

  testWidgets('INV-SET-023 a manager (inventory.adjust, no items.create / '
      'items.delete) sees every control enabled', (tester) async {
    final h = await pumpSettings(tester, persona: Persona.manager);
    expect(_pctEnabled(tester), isTrue);
    expect(_enabled(tester, _save), isTrue);
    expect(
      tester.widget<DashSwitch>(inRow('milk', find.byType(DashSwitch))).enabled,
      isTrue,
    );
    expect(
      inRow('milk', byKey('inv-category-delete-${cat('milk')}')),
      findsOneWidget,
    );
    expect(h.server.callsTo(categoriesRoute), hasLength(1));
  });

  testWidgets('INV-ALL-006 (divergence) limited (no inventory.adjust): the '
      'shell\'s Restricted page, nothing read', (tester) async {
    final h = await pumpSettings(tester, persona: Persona.limited);
    expect(page, findsNothing);
    expect(h.server.callsTo(settingsRoute), isEmpty);
    expect(h.server.callsTo(categoriesRoute), isEmpty);
  });
}
