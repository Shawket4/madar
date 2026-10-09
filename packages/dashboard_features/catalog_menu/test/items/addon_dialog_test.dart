// The add-on dialog and the add-on recipe dialog (MENU-ITEMS-093..105, 113,
// 115, MENU-AREA-013) driven through the real shell.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/shared/menu_providers.dart'
    show modifierGroupsProvider;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart' show MadarSpinner;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _options = '/modifier-groups/{gid}/options';
const String _option = '/modifier-options/{oid}';

Future<DashHarness> _onAddons(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  ({MockServer server, MockDb db})? seeded,
}) async {
  final h = await pumpItems(tester, persona: persona, seeded: seeded);
  await openTab(h, 'addons');
  return h;
}

Future<void> _new(DashHarness h) => h.tapText('New add-on');

Future<void> _edit(DashHarness h, String name) async {
  await openCardMenu(h, name);
  await pickMenu(h, 'Edit');
}

Future<void> _save(DashHarness h) => h.tap(inSurface(find.text('Save')));

String _text(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)).first,
    )
    .controller
    .text;

void main() {
  group('add-on dialog', () {
    testWidgets('MENU-ITEMS-093 titles, description, groups read; reset per '
        'open, the price in pounds', (tester) async {
      final h = await _onAddons(tester);
      final before = callsOf(h, 'GET', '/modifier-groups').length;
      await _new(h);
      expect(inSurface(find.text('New add-on')), findsOneWidget);
      expect(
        callsOf(h, 'GET', '/modifier-groups').length,
        greaterThanOrEqualTo(before),
      );
      expect(_text(tester, fieldIn(surface, 'Default price (EGP)')), '0');
      await h.tap(inSurface(find.text('Cancel')));
      await _edit(h, 'Oat milk');
      expect(inSurface(find.text('Edit add-on')), findsOneWidget);
      expect(_text(tester, fieldIn(surface, 'Name')), 'Oat milk');
      expect(_text(tester, fieldIn(surface, 'Name (ع)')), 'حليب الشوفان');
      expect(_text(tester, fieldIn(surface, 'Default price (EGP)')), '25');
    });

    testWidgets('MENU-ITEMS-093 (re-seed) opened on a list older than 30 s: '
        'the fresh add-on shows; once edited, a refetch keeps the edit; Save '
        'sends the fresh price and the edit', (tester) async {
      final s = itemsServer();
      final h = await _onAddons(tester, seeded: s);
      Map<String, Object?> oat() {
        final g = s.db[MenuTables.groups].find(MenuSeedIds.group('milk'))!;
        return (g['options'] as List).cast<Map<String, Object?>>().firstWhere(
          (o) => o['id'] == option('milk', 'oat'),
        );
      }

      oat()['price'] = 2800;
      s.db.clock.advance(const Duration(seconds: 31));
      final gets = callsOf(h, 'GET', '/addon-items').length;
      await _edit(h, 'Oat milk');
      expect(callsOf(h, 'GET', '/addon-items'), hasLength(gets + 1));
      expect(_text(tester, fieldIn(surface, 'Default price (EGP)')), '28');

      await h.enterText(fieldIn(surface, 'Name'), 'Oat');
      oat()['price'] = 3100;
      h.container.read(realtimeBusProvider).invalidate(const ['/addon-items']);
      await h.settle();
      expect(callsOf(h, 'GET', '/addon-items'), hasLength(gets + 2));
      expect(_text(tester, fieldIn(surface, 'Name')), 'Oat');
      expect(_text(tester, fieldIn(surface, 'Default price (EGP)')), '28');
      await _save(h);
      expect(lastCall(h, 'PATCH', _option).body, {
        'is_active': true,
        'name': 'Oat',
        'name_translations': {'ar': 'حليب الشوفان'},
        'price': 2800,
      });
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-094 / 095 name and group required', (tester) async {
      final h = await _onAddons(tester);
      await _new(h);
      await _save(h);
      expect(inSurface(find.text('This field is required')), findsNWidgets(2));
      expect(callsOf(h, 'POST', _options), isEmpty);
      expect(inSurface(find.text('Select…')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-095 only shared groups are offered', (
      tester,
    ) async {
      final s = itemsServer();
      s.db[MenuTables.groups].insert({
        ...s.db[MenuTables.groups].find(MenuSeedIds.group('extras'))!,
        'id': 'item-only-options',
        'name': 'Cortado options',
        'legacy_addon_type': null,
        'is_item_options': true,
      }, timestamps: false);
      final h = await _onAddons(tester, seeded: s);
      await _new(h);
      await h.tap(selectIn(surface, 'Group'));
      final list = find.byWidgetPredicate((w) => w is DashOptionList);
      expect(
        find.descendant(of: list, matching: find.text('Extras')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: list, matching: find.text('Cortado options')),
        findsNothing,
      );
    });

    testWidgets('MENU-ITEMS-096 edit: the group shown and locked, with the '
        'note', (tester) async {
      final h = await _onAddons(tester);
      await _edit(h, 'Oat milk');
      final group = tester.widget<DashSelect<String>>(
        selectIn(surface, 'Group'),
      );
      expect(group.enabled, isFalse);
      expect(group.value, MenuSeedIds.group('milk'));
      expect(
        inSurface(
          find.text(
            "The type (group) can't change — recreate the add-on to move it.",
          ),
        ),
        findsOneWidget,
      );
      expect(inSurface(find.text('New group')), findsNothing);
    });

    testWidgets('MENU-ITEMS-097 New group: the editor on top, the new group '
        'picked', (tester) async {
      final s = itemsServer();
      final h = await _onAddons(tester, seeded: s);
      await _new(h);
      await h.tap(inSurface(find.text('New group')));
      expect(find.byType(DashSurface), findsNWidgets(2));
      await h.enterText(fieldIn(surface, 'Name').first, 'Syrups');
      await h.tap(inSurface(find.text('Save')));
      await h.settle();
      expect(find.byType(DashSurface), findsOneWidget);
      final created = s.db[MenuTables.groups].firstWhere(
        (g) => g['name'] == 'Syrups',
      )!;
      final group = tester.widget<DashSelect<String>>(
        selectIn(surface, 'Group'),
      );
      expect(group.value, created['id']);
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-098 refusal: no menu.items.edit, no New group', (
      tester,
    ) async {
      final h = await _onAddons(tester, persona: Persona.manager);
      await _new(h);
      expect(inSurface(find.text('New group')), findsNothing);
    });

    testWidgets('MENU-ITEMS-099 / 100 / 101 / 115 create: the option in the '
        'group, price in piastres', (tester) async {
      final s = itemsServer();
      final h = await _onAddons(tester, seeded: s);
      await _new(h);
      await h.enterText(fieldIn(surface, 'Name'), 'Honey');
      await chooseIn(h, surface, 'Group', 'Extras');
      await h.enterText(fieldIn(surface, 'Default price (EGP)'), '12.5');
      await h.tap(switchIn(surface, 'Active'));
      await _save(h);
      final post = lastCall(h, 'POST', _options);
      expect(
        post.path,
        '/modifier-groups/${MenuSeedIds.group('extras')}/options',
      );
      expect(post.body, {'is_active': false, 'name': 'Honey', 'price': 1250});
      await h.expectToast('Changes saved');
      expect(find.byType(DashSurface), findsNothing);
      expect(inPage(find.text('Honey')), findsOneWidget);
    });

    testWidgets(
      'MENU-ITEMS-099 the price box takes no minus and two decimals',
      (tester) async {
        final h = await _onAddons(tester);
        await _new(h);
        await h.enterText(fieldIn(surface, 'Default price (EGP)'), '-3');
        expect(_text(tester, fieldIn(surface, 'Default price (EGP)')), '3');
        await h.enterText(fieldIn(surface, 'Default price (EGP)'), '3.456');
        expect(_text(tester, fieldIn(surface, 'Default price (EGP)')), '3');
      },
    );

    testWidgets('MENU-ITEMS-101 / 115 edit: patch name, {ar}, price, active', (
      tester,
    ) async {
      final h = await _onAddons(tester);
      await _edit(h, 'Oat milk');
      await h.enterText(fieldIn(surface, 'Default price (EGP)'), '27');
      await _save(h);
      final call = lastCall(h, 'PATCH', _option);
      expect(call.path, '/modifier-options/${option('milk', 'oat')}');
      expect(call.body, {
        'is_active': true,
        'name': 'Oat milk',
        'name_translations': {'ar': 'حليب الشوفان'},
        'price': 2700,
      });
      await h.expectToast('Changes saved');
    });

    testWidgets('MENU-ITEMS-101 a refused save keeps the dialog with the '
        'words', (tester) async {
      final h = await _onAddons(tester, persona: Persona.manager);
      await _edit(h, 'Oat milk');
      await _save(h);
      await h.expectToast(
        h.refusalWords(MockResponse.denied('menu.items.edit')),
      );
      expect(inSurface(find.text('Edit add-on')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-113 edit before the groups land: required under '
        'the locked select, nothing written', (tester) async {
      final s = itemsServer();
      s.server.fail(
        'GET',
        '/modifier-groups',
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await _onAddons(tester, seeded: s);
      await _edit(h, 'Oat milk');
      await _save(h);
      expect(inSurface(find.text('This field is required')), findsOneWidget);
      expect(callsOf(h, 'PATCH', _option), isEmpty);
    });

    testWidgets('MENU-AREA-013 Enter in the price submits', (tester) async {
      final h = await _onAddons(tester);
      await _edit(h, 'Oat milk');
      await typeAndSubmit(h, fieldIn(surface, 'Default price (EGP)'), '26');
      expect(lastCall(h, 'PATCH', _option).body, isA<Map>());
      await h.flushTimers();
    });
  });

  group('add-on recipe dialog', () {
    Future<void> openRecipe(DashHarness h, String name) async {
      await openCardMenu(h, name);
      await pickMenu(h, 'Edit recipe');
    }

    testWidgets('MENU-ITEMS-102 / 103 / 104 title, description, the lines and '
        'catalog read, one column, New ingredient', (tester) async {
      final h = await _onAddons(tester);
      await openRecipe(h, 'Extra shot');
      expect(inSurface(find.text('Add-on recipe')), findsOneWidget);
      expect(
        inSurface(
          find.text(
            'Extra shot — Ingredients deducted from stock when '
            'this add-on is chosen.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        lastCall(h, 'GET', '/recipes/addons/{addon_item_id}').path,
        '/recipes/addons/${option('extras', 'shot')}',
      );
      expect(
        lastCall(h, 'GET', '/inventory/orgs/{org_id}/catalog').path,
        '/inventory/orgs/$sabahOrg/catalog',
      );
      expect(
        find.bySemanticsLabel(
          h.t(
            'modeling.grid.cellAria',
            args: {
              'ingredient': 'House espresso blend',
              'size': h.t('recipes.oneSize'),
            },
          ),
        ),
        findsOneWidget,
      );
      expect(inSurface(find.text(h.t('recipes.newIngredient'))), findsWidgets);
    });

    testWidgets('MENU-ITEMS-103 a spinner while the lines load', (
      tester,
    ) async {
      final s = itemsServer();
      final gate = s.server.hold('GET', '/recipes/addons/{addon_item_id}');
      final h = await _onAddons(tester, seeded: s);
      await openRecipe(h, 'Extra shot');
      expect(inSurface(find.byType(MadarSpinner)), findsOneWidget);
      gate.release();
      await h.settle();
      expect(inSurface(find.byType(MadarSpinner)), findsNothing);
    });

    testWidgets('MENU-ITEMS-053 (intent) ⋯ Edit recipe warms the lines and '
        'the Edit item the groups; choosing them asks nothing more', (
      tester,
    ) async {
      final h = await _onAddons(tester);
      const lines = '/recipes/addons/{addon_item_id}';
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await openCardMenu(h, 'Extra shot');
      expect(callsOf(h, 'GET', lines), isEmpty);
      final item = find.text('Edit recipe').hitTestable();
      await mouse.moveTo(tester.getCenter(item));
      await h.settle();
      expect(callsOf(h, 'GET', lines).map((c) => c.path), [
        '/recipes/addons/${option('extras', 'shot')}',
      ]);
      await h.tap(item);
      expect(inSurface(find.text('Add-on recipe')), findsOneWidget);
      expect(callsOf(h, 'GET', lines), hasLength(1), reason: 'from the cache');
      await tester.tapAt(const Offset(4, 4));
      await h.settle();
      // Edit: the dialog's groups read, stale first so only the item warms it.
      await mouse.moveTo(Offset.zero);
      await openCardMenu(h, 'Extra shot');
      h.container.invalidate(
        modifierGroupsProvider((orgId: sabahOrg, includeInactive: false)),
      );
      final groups = callsOf(h, 'GET', '/modifier-groups').length;
      final edit = find.text('Edit').hitTestable();
      await mouse.moveTo(tester.getCenter(edit));
      await h.settle();
      expect(callsOf(h, 'GET', '/modifier-groups'), hasLength(groups + 1));
      await h.tap(edit);
      expect(inSurface(find.text('Edit add-on')), findsOneWidget);
      expect(callsOf(h, 'GET', '/modifier-groups'), hasLength(groups + 1));
    });

    testWidgets('MENU-ITEMS-103 (divergence) a failed lines read: words and '
        'Retry, never an empty builder whose Save would wipe the lines', (
      tester,
    ) async {
      final s = itemsServer();
      s.server.fail(
        'GET',
        '/recipes/addons/{addon_item_id}',
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await _onAddons(tester, seeded: s);
      await openRecipe(h, 'Extra shot');
      expect(inSurface(find.text("Couldn't load this")), findsOneWidget);
      expect(inSurface(find.text(h.t('recipes.builder.saveAll'))), findsNothing);
      s.server.clearFailures();
      await h.tap(inSurface(find.text('Retry')));
      expect(inSurface(find.text("Couldn't load this")), findsNothing);
      expect(
        inSurface(find.text(h.t('recipes.builder.saveAll'))),
        findsOneWidget,
      );
      expect(callsOf(h, 'PUT', '/modifier-options/{oid}/recipe'), isEmpty);
    });

    testWidgets('MENU-ITEMS-105 Save recipe: the linked lines, "Recipe '
        'saved", close', (tester) async {
      final h = await _onAddons(tester);
      await openRecipe(h, 'Extra shot');
      final box = find.bySemanticsLabel(
        h.t(
          'modeling.grid.cellAria',
          args: {
            'ingredient': 'House espresso blend',
            'size': h.t('recipes.oneSize'),
          },
        ),
      );
      await h.enterText(box, '20');
      await h.tap(inSurface(find.text(h.t('recipes.builder.saveAll'))));
      final put = lastCall(h, 'PUT', '/modifier-options/{oid}/recipe');
      expect(put.path, '/modifier-options/${option('extras', 'shot')}/recipe');
      expect(put.body, [
        {
          'ingredient_id': MenuSeedIds.ingredient('house_blend'),
          'quantity': 20.0,
          'unit': 'g',
        },
      ]);
      await h.expectToast(h.t('recipes.builder.saved'));
      expect(find.byType(DashSurface), findsNothing);
    });

    testWidgets('MENU-ITEMS-105 a refused save stays open, unsaved', (
      tester,
    ) async {
      final h = await _onAddons(tester, persona: Persona.manager);
      await openRecipe(h, 'Extra shot');
      final box = find.bySemanticsLabel(
        h.t(
          'modeling.grid.cellAria',
          args: {
            'ingredient': 'House espresso blend',
            'size': h.t('recipes.oneSize'),
          },
        ),
      );
      await h.enterText(box, '20');
      await h.tap(inSurface(find.text(h.t('recipes.builder.saveAll'))));
      await h.expectToast(
        h.refusalWords(MockResponse.denied('menu.items.edit')),
      );
      expect(inSurface(find.text('Add-on recipe')), findsOneWidget);
      expect(
        inSurface(find.text(h.t('recipes.builder.unsaved'))),
        findsWidgets,
      );
    });
  });
}
