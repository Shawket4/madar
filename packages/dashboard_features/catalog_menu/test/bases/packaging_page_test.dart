// `/menu/packaging` driven through the real app shell (inventory rows
// MENU-PKG-001..016, plus the area rows that touch it: MENU-AREA-010, -013,
// -014). Expectations are worked out from the area seed: six rules in seed
// order — "Hot cup" (Hot Coffee), "Hot cup · Regular" / "· Large" (Hot
// Coffee + a size label), "Iced cup" (Iced Coffee), "Juice cup" (Fresh
// Juice) and the inactive "Espresso to go (paused)" (the Espresso item).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/bases/bases_widgets.dart';
import 'package:dashboard_catalog_menu/src/bases/packaging_rules_page.dart';
import 'package:dashboard_catalog_menu/src/bases/rule_dialog.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _list = '/packaging-rules';
const _one = '/packaging-rules/{id}';
const _apply = '/packaging-rules/apply';
const _categories = '/categories';
const _items = '/costing/catalog';
const _catalog = '/inventory/orgs/{org_id}/catalog';

String _rule(String key) => MenuSeedIds.rule(key);
final String _hotAny = _rule('hot_any');
final String _hotRegular = _rule('hot_regular');
final String _hotLarge = _rule('hot_large');
final String _iced = _rule('iced');
final String _juice = _rule('juice');
final String _espressoCup = _rule('espresso_cup');

final String _cup16Clear = MenuSeedIds.ingredient('cup_16oz_clear');
final String _domeLid = MenuSeedIds.ingredient('dome_lid');
final String _straw = MenuSeedIds.ingredient('straw');
final String _cup8 = MenuSeedIds.ingredient('cup_8oz');

const String _saved = 'Rule saved. Apply rules to update existing sizes.';

Finder get _page => find.byType(PackagingRulesPage);
Finder get _dialog => find.byType(RuleDialog);
Finder _inPage(Finder f) => find.descendant(of: _page, matching: f);
Finder _inDialog(Finder f) => find.descendant(of: _dialog, matching: f);

/// The dialog's select a screen reader calls [label].
Finder _select(String label) => _inDialog(
  find.byWidgetPredicate((w) => w is DashSelect && w.semanticLabel == label),
);

Future<void> _openEdit(DashHarness h, String id) =>
    h.tap(labelIn(rowOf(id), h.t('common.edit')));

Future<void> _openNew(DashHarness h) =>
    h.tap(_inPage(find.text(h.t('modeling.packaging.new'))));

Future<void> _save(DashHarness h) =>
    h.tap(_inDialog(find.text(h.t('common.save'))));

/// The sub-line widget of the row [id].
Finder _sublineOf(String id) => find
    .descendant(of: rowOf(id), matching: find.byType(MadarClippedText))
    .last;

/// The sub-line of the row [id] as sent to the text engine (with its bidi
/// isolates).
String _raw(WidgetTester tester, String id) =>
    tester.widget<MadarClippedText>(_sublineOf(id)).data!;

/// The sub-line of the row [id] as read (bidi isolates left out).
String _subline(WidgetTester tester, String id) =>
    _raw(tester, id).replaceAll(RegExp('[\u2068\u2069]'), '');

/// The live items' sizes in [org], with their item.
List<(MockRow, MockRow)> _liveSizes(MockDb db) => [
  for (final s in db[MenuTables.sizes].rows)
    if (db[MenuTables.menuItems].find(s['menu_item_id'] as String)
        case final item?
        when item['deleted_at'] == null && item['org_id'] == SeedIds.sabahOrg)
      (s, item),
];

void main() {
  group('MENU-PKG-001..006 the list', () {
    testWidgets('MENU-PKG-001 header: title, subtitle, "Apply rules" and '
        '"New rule"', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath);
      expect(_inPage(find.text('Packaging rules')), findsOneWidget);
      expect(
        find.text(
          'Cups, lids and straws added to sizes automatically. The most '
          'specific matching rule wins.',
        ),
        findsOneWidget,
      );
      final apply = tester.widget<DashButton>(
        find.ancestor(
          of: find.text('Apply rules'),
          matching: find.byType(DashButton),
        ),
      );
      expect(apply.variant, DashButtonVariant.outline);
      expect(apply.icon, 'play');
      final add = tester.widget<DashButton>(
        find.ancestor(
          of: find.text('New rule'),
          matching: find.byType(DashButton),
        ),
      );
      expect(add.icon, 'plus');
      expect(h.server.callsTo(_apply), isEmpty);
    });

    testWidgets('MENU-PKG-002 reads: the rules, the categories and the first '
        '500 items', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath);
      expect(h.server.callsTo(_list, method: 'GET'), hasLength(1));
      // The always-mounted dialog's ingredient picker reads with the page;
      // opening the dialog reuses it.
      expect(
        h.server.callsTo(_catalog).single.path,
        '/inventory/orgs/${SeedIds.sabahOrg}/catalog',
      );
      await _openEdit(h, _iced);
      expect(h.server.callsTo(_catalog), hasLength(1));
      await h.tap(_inDialog(find.text('Cancel')));
      expect(h.server.callsTo(_categories).single.query, {
        'org_id': [SeedIds.sabahOrg],
      });
      expect(h.server.callsTo(_items).single.query, {
        'org_id': [SeedIds.sabahOrg],
        'per_page': ['500'],
      });
      // Seed order (`sort`).
      final ys = [
        for (final id in [
          _hotAny,
          _hotRegular,
          _hotLarge,
          _iced,
          _juice,
          _espressoCup,
        ])
          tester.getTopLeft(rowOf(id)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(find.text('Hot cup · Regular'), findsOneWidget);
    });

    testWidgets('MENU-PKG-003 loading: one skeleton, then the rows', (
      tester,
    ) async {
      final s = menuServer();
      final gate = s.server.hold('GET', _list);
      final h = await pumpMenu(tester, path: packagingPath, seeded: s);
      expect(_inPage(find.byType(ModelingSkeleton)), findsOneWidget);
      expect(find.text('Iced cup'), findsNothing);
      gate.release();
      await h.settle();
      expect(find.byType(ModelingSkeleton), findsNothing);
      expect(find.text('Iced cup'), findsOneWidget);
    });

    testWidgets('MENU-PKG-003 error: the words, the server\'s reason, Retry '
        'refetches only the rules', (tester) async {
      final s = menuServer();
      s.server.fail('GET', _list, MockResponse.error(500, 'Database is down'));
      final h = await pumpMenu(tester, path: packagingPath, seeded: s);
      expect(find.text('Could not load packaging rules'), findsOneWidget);
      expect(find.text('Database is down'), findsOneWidget);
      final cats = h.server.callsTo(_categories).length;
      final items = h.server.callsTo(_items).length;
      await h.tap(_inPage(find.text('Retry')));
      expect(find.text('Could not load packaging rules'), findsNothing);
      expect(find.text('Iced cup'), findsOneWidget);
      expect(h.server.callsTo(_list, method: 'GET'), hasLength(2));
      expect(h.server.callsTo(_categories), hasLength(cats));
      expect(h.server.callsTo(_items), hasLength(items));
    });

    testWidgets('MENU-PKG-003 empty: the hint, the actions stay', (
      tester,
    ) async {
      final s = menuServer();
      CatalogMenuSeed.loadInto(s.db);
      s.db[MenuTables.rules].clear();
      await pumpMenu(tester, path: packagingPath, seeded: s);
      expect(find.text('No packaging rules yet'), findsOneWidget);
      expect(
        find.text('e.g. Iced drinks · Cup → 16oz cup, lid, straw.'),
        findsOneWidget,
      );
      expect(_inPage(find.text('New rule')), findsOneWidget);
      expect(_inPage(find.text('Apply rules')), findsOneWidget);
    });

    testWidgets('MENU-PKG-004 a row: name, Inactive pill, matches → lines', (
      tester,
    ) async {
      await pumpMenu(tester, path: packagingPath);
      // Item, then category, then size label; lines "name qty" joined ", ".
      expect(
        _subline(tester, _hotAny),
        'Hot Coffee → 8oz paper cup 1, Hot cup lid 1',
      );
      expect(
        _subline(tester, _hotRegular),
        'Hot Coffee · Regular → 12oz paper cup 1, Hot cup lid 1',
      );
      expect(
        _subline(tester, _hotLarge),
        'Hot Coffee · Large → 16oz paper cup 1, Hot cup lid 1, Cup sleeve 1',
      );
      expect(
        _subline(tester, _iced),
        'Iced Coffee → 16oz clear cup 1, Dome lid 1, Paper straw 1',
      );
      expect(
        _subline(tester, _juice),
        'Fresh Juice → 16oz clear cup 1, Paper straw 1',
      );
      expect(_subline(tester, _espressoCup), 'Espresso → 8oz paper cup 1');
      expect(
        find.descendant(
          of: rowOf(_espressoCup),
          matching: find.text('Inactive'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rowOf(_iced), matching: find.text('Inactive')),
        findsNothing,
      );
    });

    testWidgets('MENU-PKG-004 "—" for an unknown id, "Every size" with no '
        'match, "—" with no lines', (tester) async {
      final s = menuServer();
      CatalogMenuSeed.loadInto(s.db);
      final now = s.db.nowIso;
      for (final (id, cat, label) in [
        ('rule-gone', 'not-a-category', 'Cup'),
        ('rule-any', null, null),
      ]) {
        s.db[MenuTables.rules].insert({
          'id': id,
          'org_id': SeedIds.sabahOrg,
          'name': id,
          'match_category_id': cat,
          'match_size_label': label,
          'match_item_id': null,
          'is_active': true,
          'sort': 9,
          'lines': <Object?>[],
          'created_at': now,
          'updated_at': now,
        }, timestamps: false);
      }
      await pumpMenu(tester, path: packagingPath, seeded: s);
      expect(_subline(tester, 'rule-gone'), '— · Cup → —');
      expect(_subline(tester, 'rule-any'), 'Every size → —');
    });

    testWidgets('MENU-PKG-004 (divergence) Arabic: translated category, the '
        'arrow points along the reading direction', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath, locale: 'ar');
      // Each match and each line is a bidi isolate.
      expect(
        _raw(tester, _hotRegular),
        '\u2068قهوة ساخنة\u2069 · \u2068Regular\u2069 ← '
        '\u206812oz paper cup 1\u2069, \u2068Hot cup lid 1\u2069',
      );
      // Laid out right to left: category, size, arrow, then the lines — a
      // Latin "Regular" does not pull the arrow into its run.
      final text = _raw(tester, _hotRegular);
      final para = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: _sublineOf(_hotRegular),
          matching: find.byType(RichText),
        ),
      );
      double xOf(String part) {
        final i = text.indexOf(part);
        return para
            .getBoxesForSelection(
              TextSelection(baseOffset: i, extentOffset: i + part.length),
            )
            .first
            .left;
      }

      expect(xOf('قهوة'), greaterThan(xOf('Regular')));
      expect(xOf('Regular'), greaterThan(xOf('←')));
      expect(xOf('←'), greaterThan(xOf('12oz')));
      expect(xOf('12oz'), greaterThan(xOf('Hot cup lid')));
      expect(
        find.descendant(
          of: rowOf(_espressoCup),
          matching: find.text(h.t('common.inactive')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-PKG-005 row actions: Edit and Delete on every row', (
      tester,
    ) async {
      final h = await pumpMenu(tester, path: packagingPath);
      for (final id in [_hotAny, _iced, _espressoCup]) {
        expect(labelIn(rowOf(id), 'Edit'), findsOneWidget);
        expect(labelIn(rowOf(id), 'Delete'), findsOneWidget);
      }
      await _openEdit(h, _iced);
      expect(_inDialog(find.text('Edit rule')), findsOneWidget);
    });

    for (final persona in [Persona.manager, Persona.limited]) {
      testWidgets('MENU-PKG-006 ${persona.name}: no Apply, no New, no row '
          'actions', (tester) async {
        await pumpMenu(tester, path: packagingPath, persona: persona);
        expect(find.text('Iced cup'), findsOneWidget);
        expect(_inPage(find.text('Apply rules')), findsNothing);
        expect(_inPage(find.text('New rule')), findsNothing);
        expect(labelIn(_page, 'Edit'), findsNothing);
        expect(labelIn(_page, 'Delete'), findsNothing);
      });
    }

    testWidgets('MENU-PKG-006 apply cap only: "Apply rules", nothing else', (
      tester,
    ) async {
      final s = serverWithCaps(const [
        'menu.items.read',
        'menu.packaging_rules.apply',
      ], persona: Persona.owner);
      await pumpMenu(tester, path: packagingPath, seeded: s);
      expect(_inPage(find.text('Apply rules')), findsOneWidget);
      expect(_inPage(find.text('New rule')), findsNothing);
      expect(labelIn(_page, 'Edit'), findsNothing);
    });

    testWidgets('MENU-PKG-006 edit cap only: "New rule" and row actions, no '
        'Apply', (tester) async {
      final s = serverWithCaps(const [
        'menu.items.read',
        'menu.items.edit',
      ], persona: Persona.owner);
      await pumpMenu(tester, path: packagingPath, seeded: s);
      expect(_inPage(find.text('Apply rules')), findsNothing);
      expect(_inPage(find.text('New rule')), findsOneWidget);
      expect(labelIn(rowOf(_iced), 'Edit'), findsOneWidget);
      expect(labelIn(rowOf(_iced), 'Delete'), findsOneWidget);
    });

    testWidgets('MENU-PKG-006 a 403 on the read shows the refusal\'s words', (
      tester,
    ) async {
      final s = menuServer(persona: Persona.limited);
      s.server.fail(
        'GET',
        _list,
        MockResponse.denied('menu.items.read'),
        times: null,
      );
      final h = await pumpMenu(
        tester,
        path: packagingPath,
        persona: Persona.limited,
        seeded: s,
      );
      expect(find.text('Could not load packaging rules'), findsOneWidget);
      expect(
        textHas(h.refusalWords(MockResponse.denied('menu.items.read'))),
        findsOneWidget,
      );
      h.server.clearFailures();
    });

    testWidgets('MENU-AREA-010 platform admin, no org: the empty state, '
        'nothing fetched', (tester) async {
      final h = await pumpMenu(
        tester,
        path: packagingPath,
        persona: Persona.platform,
      );
      expect(find.text('No packaging rules yet'), findsOneWidget);
      expect(h.server.callsTo(_list), isEmpty);
      expect(h.server.callsTo(_categories), isEmpty);
      expect(h.server.callsTo(_items), isEmpty);
      expect(h.server.callsTo(_catalog), isEmpty);
      expect(_inPage(find.text('Apply rules')), findsOneWidget);
    });
  });

  group('MENU-PKG-007 apply rules', () {
    testWidgets('runs the apply, shows the counts until the next apply, '
        'refreshes the catalog (not the rules)', (tester) async {
      final s = menuServer();
      final h = await pumpMenu(tester, path: packagingPath, seeded: s);
      final db = h.db!;
      final rules = h.server.callsTo(_list, method: 'GET').length;
      final cats = h.server.callsTo(_categories).length;
      final items = h.server.callsTo(_items).length;
      final gate = s.server.hold('POST', _apply);
      await h.tap(_inPage(find.text('Apply rules')));
      final button = tester.widget<DashButton>(
        find.ancestor(
          of: find.text('Apply rules'),
          matching: find.byType(DashButton),
        ),
      );
      expect(button.loading, isTrue);
      gate.release();
      await h.settle();
      expect(h.server.callsTo(_apply).single.status, 200);

      // Hand count: every live size is checked; the hot, iced and juice
      // sizes match an active rule; the seed is already expanded, so
      // nothing changes; Green Tea's own 8oz cup is hand-entered packaging.
      final sizes = _liveSizes(db);
      final matched = sizes.where(
        (e) => [
          MenuSeedIds.category('hot'),
          MenuSeedIds.category('iced'),
          MenuSeedIds.category('juice'),
        ].contains(e.$2['category_id']),
      );
      expect(find.text('Rules applied'), findsOneWidget);
      expect(
        find.text(
          '${sizes.length} sizes checked · ${matched.length} matched a rule · '
          '0 changed · 1 keep hand-entered packaging',
        ),
        findsOneWidget,
      );
      // invalidateCatalog(): categories and items refetch; the rules do not.
      expect(h.server.callsTo(_list, method: 'GET'), hasLength(rules));
      expect(h.server.callsTo(_categories).length, greaterThan(cats));
      expect(h.server.callsTo(_items).length, greaterThan(items));
      expect(button.loading, isTrue); // the old widget; the new one is idle
      expect(
        tester
            .widget<DashButton>(
              find.ancestor(
                of: find.text('Apply rules'),
                matching: find.byType(DashButton),
              ),
            )
            .loading,
        isFalse,
      );
    });

    testWidgets('a rule edit, then Apply: the juice sizes change', (
      tester,
    ) async {
      final h = await pumpMenu(tester, path: packagingPath);
      final db = h.db!;
      final juiceSizes = _liveSizes(
        db,
      ).where((e) => e.$2['category_id'] == MenuSeedIds.category('juice'));
      expect(juiceSizes, isNotEmpty);
      await _openEdit(h, _juice);
      await addIngredient(h, 'Dome lid');
      await h.enterText(cell(h, 'Dome lid', 'Quantity'), '1');
      await _save(h);
      await h.expectToast(_saved);
      await h.tap(_inPage(find.text('Apply rules')));
      expect(textHas('· ${juiceSizes.length} changed ·'), findsOneWidget);
      final orange = juiceSizes.first.$1['id'];
      expect(
        db[MenuTables.recipeLines].where(
          (l) =>
              l['size_id'] == orange &&
              l['source'] == 'rule' &&
              l['ingredient_id'] == _domeLid,
        ),
        hasLength(1),
      );
      // A second apply changes nothing and replaces the counts.
      await h.tap(_inPage(find.text('Apply rules')));
      expect(textHas('· 0 changed ·'), findsOneWidget);
      expect(find.text('Rules applied'), findsOneWidget);
    });

    testWidgets('a refusal toasts the refusal\'s words, no alert', (
      tester,
    ) async {
      final h = await pumpMenu(tester, path: packagingPath);
      h.server.fail(
        'POST',
        _apply,
        MockResponse.denied('menu.packaging_rules.apply'),
      );
      await h.tap(_inPage(find.text('Apply rules')));
      await h.expectToast(
        h.refusalWords(MockResponse.denied('menu.packaging_rules.apply')),
      );
      expect(find.text('Rules applied'), findsNothing);
    });
  });

  group('MENU-PKG-008 delete', () {
    testWidgets('confirm (not destructive), delete, the rules refresh, no '
        'toast', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath);
      final rules = h.server.callsTo(_list, method: 'GET').length;
      final cats = h.server.callsTo(_categories).length;
      await h.tap(labelIn(rowOf(_iced), 'Delete'));
      expect(find.text('Delete "Iced cup"?'), findsOneWidget);
      expect(
        find.text(
          'Sizes keep their current packaging until rules are applied again.',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.byWidgetPredicate(
            (w) => w is DashIcon && w.name == 'alert-triangle',
          ),
        ),
        findsNothing,
      );
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      final del = h.server.callsTo(_one, method: 'DELETE').single;
      expect(del.path, '/packaging-rules/$_iced');
      expect(del.status, 204);
      expect(find.text('Iced cup'), findsNothing);
      expect(h.server.callsTo(_list, method: 'GET'), hasLength(rules + 1));
      // Only the rules: no catalog refresh.
      expect(h.server.callsTo(_categories), hasLength(cats));
      expect(find.text(_saved), findsNothing);
      expect(find.byType(DashConfirmDialog), findsNothing);
    });

    testWidgets('Cancel deletes nothing', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath);
      await h.tap(labelIn(rowOf(_iced), 'Delete'));
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Cancel'),
        ),
      );
      expect(h.server.callsTo(_one, method: 'DELETE'), isEmpty);
      expect(find.text('Iced cup'), findsOneWidget);
    });

    testWidgets('a refusal shows the refusal\'s words, the row stays', (
      tester,
    ) async {
      final h = await pumpMenu(tester, path: packagingPath);
      h.server.fail('DELETE', _one, MockResponse.denied('menu.items.edit'));
      await h.tap(labelIn(rowOf(_iced), 'Delete'));
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      await h.expectToast(
        h.refusalWords(MockResponse.denied('menu.items.edit')),
      );
      expect(find.text('Iced cup'), findsOneWidget);
    });
  });

  group('MENU-PKG-009..015 the rule dialog', () {
    testWidgets('MENU-PKG-009 new: title, the match help, empty fields', (
      tester,
    ) async {
      final h = await pumpMenu(tester, path: packagingPath);
      await _openNew(h);
      expect(_inDialog(find.text('New rule')), findsOneWidget);
      expect(
        _inDialog(
          find.text(
            'Leave a match empty to match any. An item match beats category + '
            'size, which beats either alone.',
          ),
        ),
        findsOneWidget,
      );
      // Both pickers on "Any"; the size label box shows "Any" as a hint.
      expect(_inDialog(find.text('Any')), findsNWidgets(3));
      expect(_inDialog(find.text('No ingredients yet.')), findsOneWidget);
    });

    testWidgets('MENU-PKG-009 edit: the rule\'s values; every open starts '
        'from the rule as listed', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath);
      await _openEdit(h, _hotLarge);
      expect(_inDialog(find.text('Edit rule')), findsOneWidget);
      expect(
        editable(tester, labelIn(_dialog, 'Name')).controller.text,
        'Hot cup · Large',
      );
      expect(
        editable(tester, labelIn(_dialog, 'Size label')).controller.text,
        'Large',
      );
      expect(
        find.descendant(
          of: _select('Menu category'),
          matching: find.text('Hot Coffee'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _select('Item'), matching: find.text('Any')),
        findsOneWidget,
      );
      expect(
        editable(tester, cell(h, 'Cup sleeve', 'Quantity')).controller.text,
        '1',
      );
      await h.enterText(labelIn(_dialog, 'Name'), 'Changed');
      await h.tap(_inDialog(find.text('Cancel')));
      await _openEdit(h, _hotLarge);
      expect(
        editable(tester, labelIn(_dialog, 'Name')).controller.text,
        'Hot cup · Large',
      );
    });

    testWidgets('MENU-PKG-010 the name is required (trimmed)', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath);
      await _openNew(h);
      await h.enterText(labelIn(_dialog, 'Name'), '   ');
      await _save(h);
      expect(_inDialog(find.text('This field is required')), findsOneWidget);
      expect(h.server.callsTo(_list, method: 'POST'), isEmpty);
      await h.enterText(labelIn(_dialog, 'Name'), 'Takeaway bag');
      expect(_inDialog(find.text('This field is required')), findsNothing);
    });

    testWidgets('MENU-PKG-011 the category picker: Any + the categories, '
        'translated', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath, locale: 'ar');
      await _openNew(h);
      await h.tap(_select(h.t('modeling.packaging.matchCategory')));
      final list = find.byWidgetPredicate((w) => w is DashOptionList);
      expect(
        find.descendant(of: list, matching: find.text('أي')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: list, matching: find.text('قهوة مثلجة')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: list, matching: find.text('Iced Coffee')),
        findsNothing,
      );
      await h.tap(find.descendant(of: list, matching: find.text('قهوة مثلجة')));
      expect(
        find.descendant(
          of: _select(h.t('modeling.packaging.matchCategory')),
          matching: find.text('قهوة مثلجة'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-PKG-012/013 size label and item: sent trimmed, picked; '
        'the three matches side by side', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath);
      await _openNew(h);
      final ys = {
        for (final l in ['Menu category', 'Size label', 'Item'])
          tester.getTopLeft(labelIn(_dialog, l).first).dy,
      };
      expect(ys, hasLength(1));
      await h.enterText(labelIn(_dialog, 'Name'), 'Cortado glass');
      await h.enterText(labelIn(_dialog, 'Size label'), '  Cup ');
      await h.tap(_select('Item'));
      await pickOption(h, 'Cortado');
      await addIngredient(h, '8oz paper cup');
      await h.enterText(cell(h, '8oz paper cup', 'Quantity'), '1');
      await _save(h);
      expect(h.server.callsTo(_list, method: 'POST').single.body, {
        'name': 'Cortado glass',
        'match_category_id': null,
        'match_size_label': 'Cup',
        'match_item_id': MenuSeedIds.item('cortado'),
        'is_active': true,
        'lines': [
          {'ingredient_id': _cup8, 'quantity': 1, 'unit': 'pcs'},
        ],
      });
      await h.expectToast(_saved);
      final id = h.db![MenuTables.rules].rows.firstWhere(
        (r) => r['name'] == 'Cortado glass',
      )['id'];
      expect(
        _subline(tester, id! as String),
        'Cortado · Cup → 8oz paper cup 1',
      );
    });

    testWidgets('MENU-PKG-014 the Active switch is sent', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath);
      await _openEdit(h, _iced);
      await h.tap(labelIn(_dialog, 'Active').first);
      await _save(h);
      expect(
        h.server.callsTo(_one, method: 'PATCH').single.body,
        containsPair('is_active', false),
      );
      await h.expectToast(_saved);
      expect(
        find.descendant(of: rowOf(_iced), matching: find.text('Inactive')),
        findsOneWidget,
      );
    });

    testWidgets('MENU-PKG-015 the lines grid: one Quantity column, + '
        'ingredient, remove, no size columns', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath);
      await _openEdit(h, _iced);
      expect(_inDialog(find.text('Quantity')), findsOneWidget);
      expect(_inDialog(find.text('Size column')), findsNothing);
      expect(labelIn(_dialog, 'Size label, e.g. Cup'), findsNothing);
      expect(labelIn(_dialog, 'Remove column'), findsNothing);
      // Lines already in the rule are not offered again.
      await h.tap(_inDialog(find.text('+ ingredient')));
      final list = find.byWidgetPredicate((w) => w is DashOptionList);
      expect(
        find.descendant(of: list, matching: find.text('Dome lid')),
        findsNothing,
      );
      await pickOption(h, 'Cup sleeve');
      expect(cell(h, 'Cup sleeve', 'Quantity'), findsOneWidget);
      // Digits and one dot.
      await h.enterText(cell(h, 'Cup sleeve', 'Quantity'), '2x.5.0');
      expect(
        editable(tester, cell(h, 'Cup sleeve', 'Quantity')).controller.text,
        '2.50',
      );
      // Enter / ↓ move down the column.
      await h.tap(cell(h, '16oz clear cup', 'Quantity'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await h.settle(rounds: 2);
      expect(
        editable(tester, cell(h, 'Dome lid', 'Quantity')).focusNode.hasFocus,
        isTrue,
      );
      await h.tap(labelIn(_dialog, 'Remove ingredient').last);
      expect(cell(h, 'Cup sleeve', 'Quantity'), findsNothing);
      await _save(h);
      expect(h.server.callsTo(_one, method: 'PATCH').single.body, {
        'name': 'Iced cup',
        'match_category_id': MenuSeedIds.category('iced'),
        'match_size_label': null,
        'match_item_id': null,
        'is_active': true,
        'lines': [
          {'ingredient_id': _cup16Clear, 'quantity': 1, 'unit': 'pcs'},
          {'ingredient_id': _domeLid, 'quantity': 1, 'unit': 'pcs'},
          {'ingredient_id': _straw, 'quantity': 1, 'unit': 'pcs'},
        ],
      });
      await h.expectToast(_saved);
    });

    testWidgets('MENU-AREA-014 until the catalog lands, lines read "Unknown '
        'ingredient"', (tester) async {
      final s = menuServer();
      // Read with the page (the web always mounts the dialog): held.
      final gate = s.server.hold('GET', _catalog);
      final h = await pumpMenu(tester, path: packagingPath, seeded: s);
      expect(find.text('Juice cup'), findsOneWidget);
      await _openEdit(h, _juice);
      expect(_inDialog(find.text('Unknown ingredient')), findsNWidgets(2));
      gate.release();
      await h.settle();
      expect(_inDialog(find.text('Unknown ingredient')), findsNothing);
      expect(_inDialog(find.text('Paper straw')), findsOneWidget);
    });
  });

  group('MENU-PKG-016 saving', () {
    testWidgets('create: the body, the toast, the rules refresh, closed', (
      tester,
    ) async {
      final h = await pumpMenu(tester, path: packagingPath);
      final rules = h.server.callsTo(_list, method: 'GET').length;
      final cats = h.server.callsTo(_categories).length;
      await _openNew(h);
      await h.enterText(labelIn(_dialog, 'Name'), '  Tea cup ');
      await h.tap(_select('Menu category'));
      await pickOption(h, 'Tea & More');
      await addIngredient(h, '8oz paper cup');
      await h.enterText(cell(h, '8oz paper cup', 'Quantity'), '1');
      await addIngredient(h, 'Hot cup lid');
      await _save(h);
      final post = h.server.callsTo(_list, method: 'POST').single;
      expect(post.status, 201);
      // The blank lid cell is no line.
      expect(post.body, {
        'name': 'Tea cup',
        'match_category_id': MenuSeedIds.category('tea'),
        'match_size_label': null,
        'match_item_id': null,
        'is_active': true,
        'lines': [
          {'ingredient_id': _cup8, 'quantity': 1, 'unit': 'pcs'},
        ],
      });
      await h.expectToast(_saved);
      expect(_dialog, findsNothing);
      expect(find.text('Tea cup'), findsOneWidget);
      expect(h.server.callsTo(_list, method: 'GET'), hasLength(rules + 1));
      // Not the catalog: a rule takes effect on Apply.
      expect(h.server.callsTo(_categories), hasLength(cats));
    });

    testWidgets('edit: PATCH the whole rule; a match set back to Any is '
        'sent as null', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath);
      await _openEdit(h, _hotRegular);
      await h.enterText(labelIn(_dialog, 'Size label'), '');
      await h.enterText(labelIn(_dialog, 'Name'), 'Hot cup (all)');
      await _save(h);
      final patch = h.server.callsTo(_one, method: 'PATCH').single;
      expect(patch.path, '/packaging-rules/$_hotRegular');
      expect(patch.body, containsPair('match_size_label', null));
      expect(patch.body, containsPair('name', 'Hot cup (all)'));
      await h.expectToast(_saved);
      expect(_subline(tester, _hotRegular), startsWith('Hot Coffee → '));
    });

    testWidgets('a rule matching nothing: the server\'s words, the dialog '
        'stays open', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath);
      await _openNew(h);
      await h.enterText(labelIn(_dialog, 'Name'), 'Everything');
      await _save(h);
      expect(h.server.callsTo(_list, method: 'POST').single.status, 400);
      await h.expectToast(
        'A rule must match a category, a size label or an item',
      );
      expect(_dialog, findsOneWidget);
      expect(find.text('Everything'), findsOneWidget); // still in the field
    });

    testWidgets('Cancel closes without a request', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath);
      await _openEdit(h, _iced);
      await h.enterText(labelIn(_dialog, 'Name'), 'Other');
      await h.tap(_inDialog(find.text('Cancel')));
      expect(_dialog, findsNothing);
      expect(h.server.callsTo(_one, method: 'PATCH'), isEmpty);
      expect(find.text('Iced cup'), findsOneWidget);
    });

    testWidgets('MENU-AREA-013 Enter in the name submits the dialog', (
      tester,
    ) async {
      final h = await pumpMenu(tester, path: packagingPath);
      await _openEdit(h, _iced);
      final name = labelIn(_dialog, 'Name');
      await h.tap(name);
      await h.enterText(name, 'Iced cup (clear)');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(
        h.server.callsTo(_one, method: 'PATCH').single.body,
        containsPair('name', 'Iced cup (clear)'),
      );
      await h.expectToast(_saved);
    });

    testWidgets('MENU-AREA-013 Enter on the last row submits', (tester) async {
      final h = await pumpMenu(tester, path: packagingPath);
      await _openEdit(h, _juice);
      await h.tap(cell(h, 'Paper straw', 'Quantity'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await h.settle();
      expect(h.server.callsTo(_one, method: 'PATCH'), hasLength(1));
      await h.expectToast(_saved);
      expect(_dialog, findsNothing);
    });
  });

  group('phone', () {
    testWidgets('MENU-PKG-013 the matches stack; the dialog is a full-screen '
        'form; Save works', (tester) async {
      final h = await pumpMenu(
        tester,
        path: packagingPath,
        size: DashSize.phone,
        locale: 'ar',
      );
      await _openEdit(h, _hotLarge);
      final ys = [
        for (final k in [
          'modeling.packaging.matchCategory',
          'modeling.packaging.matchSize',
          'modeling.packaging.matchItem',
        ])
          tester.getTopLeft(labelIn(_dialog, h.t(k)).first).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(ys.toSet(), hasLength(3));
      await _save(h);
      await h.expectToast(h.t('modeling.packaging.saved'));
    });
  });
}
