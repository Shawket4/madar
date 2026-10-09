// Shared set-up for the `studio` unit's tests: the real app shell with the
// menu area on the seeded mock server, finders scoped to the studio page,
// and seed helpers for what the default seed does not carry (a linked copy,
// combos, item-only options).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/mock/studio_mock.dart';
import 'package:dashboard_catalog_menu/src/shared/menu_text.dart';
import 'package:dashboard_catalog_menu/src/studio/menu_studio_page.dart';
import 'package:dashboard_catalog_menu/src/studio/studio_widgets.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Route templates the studio calls.
const String studioT = '/menu-items/{id}/studio';
const String sizesT = '/menu-items/{id}/sizes';
const String recipeT = '/menu-item-sizes/{size_id}/recipe';
const String baseT = '/menu-item-sizes/{size_id}/base';
const String groupsT = '/menu-items/{id}/modifier-groups';
const String optionsT = '/menu-items/{id}/options';
const String stepsT = '/recipes/steps/{menu_item_id}';
const String presetsT = '/recipes/step-presets';
const String itemT = '/menu-items/{id}';
const String itemsT = '/menu-items';
const String dupT = '/menu-items/{id}/duplicate';
const String uploadT = '/uploads/menu-items/{menu_item_id}';
const String linkT = '/menu-items/{id}/recipe-link';
const String previewT = '/menu-items/{id}/preview';
const String mealT = '/menu-items/{id}/meal';
const String combosT = '/combos';
const String comboT = '/combos/{id}';
const String catalogT = '/inventory/orgs/{org_id}/catalog';
const String catalogItemT = '/inventory/orgs/{org_id}/catalog/{id}';
const String basesT = '/recipe-bases';
const String categoriesT = '/categories';
const String orgGroupsT = '/modifier-groups';

String item(String key) => MenuSeedIds.item(key);
String studioPath(String key, {String? tab}) =>
    '/menu/items/${item(key)}${tab == null ? '' : '?tab=$tab'}';

/// A seeded server with the core's and the menu area's handlers.
({MockServer server, MockDb db}) studioServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerCatalogMenuMocks(server, db);
  return (server: server, db: db);
}

/// Opens the studio of the seed item [key] (or [path]).
Future<DashHarness> pumpStudio(
  WidgetTester tester, {
  String key = 'latte',
  String? path,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? seeded,
  Map<String, String>? prefs,
}) => DashHarness.pump(
  tester,
  areas: const [catalogMenuArea],
  path: path ?? studioPath(key),
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: seeded?.server,
  db: seeded?.db,
  prefs: prefs,
);

/// [f] inside the studio page.
Finder inStudio(Finder f) =>
    find.descendant(of: find.byType(MenuStudioPage), matching: f);

/// Text inside the studio page.
Finder studioText(String s) => inStudio(find.text(s));

/// Text containing [s] inside the studio page (spans included).
Finder studioHas(String s) =>
    inStudio(find.textContaining(s, findRichText: true));

/// The control a screen reader calls [label], inside the studio.
Finder studioLabel(String label) => inStudio(find.bySemanticsLabel(label));

/// The editable text inside [f].
EditableText editableIn(WidgetTester tester, Finder f) => tester.widget(
  find.descendant(of: f, matching: find.byType(EditableText)).first,
);

/// The last call to `method template`.
MockCall lastCall(DashHarness h, String method, String template) =>
    h.server.callsTo(template, method: method).last;

/// The body of the last call to `method template` as a map.
Map<String, Object?> lastBody(DashHarness h, String method, String template) =>
    (lastCall(h, method, template).body! as Map).cast<String, Object?>();

/// Picks [name] in the open option list (typed into its search box first
/// when it has one; the list may be longer than its popover).
Future<void> pickOption(DashHarness h, String name) async {
  final list = find.byWidgetPredicate((w) => w is DashOptionList);
  final search = find.descendant(of: list, matching: find.byType(EditableText));
  if (search.evaluate().isNotEmpty) await h.enterText(search, name);
  await h.tap(find.descendant(of: list, matching: find.text(name)).last);
}

// ── seed helpers ───────────────────────────────────────────────────────────

/// Makes [copyKey]'s recipe follow [sourceKey] (a linked copy).
void linkCopy(MockDb db, String copyKey, String sourceKey) {
  CatalogMenuSeed.loadInto(db);
  db[MenuTables.menuItems].update(item(copyKey), {
    'recipe_source_item_id': item(sourceKey),
  });
  CatalogMenuData(db).rebuildItem(item(copyKey));
}

/// Gives [itemKey] item-only options through the backend's own write.
void seedItemOptions(
  ({MockServer server, MockDb db}) s,
  String itemKey,
  List<Map<String, Object?>> options,
) {
  StudioBackend(s.db).putItemOptions(
    MockRequest(
      server: s.server,
      method: 'PUT',
      path: '/menu-items/${item(itemKey)}/options',
      template: optionsT,
      pathParams: {'id': item(itemKey)},
      queryAll: const {},
      body: {'options': options},
      files: const [],
      headers: const {},
      persona: Persona.owner,
    ),
    s.db[MenuTables.menuItems].find(item(itemKey))!,
  );
}

String comboId(String key) => mockUuid('studio-test-combo:$key');
String slotId(String combo, String slot) =>
    mockUuid('studio-test-slot:$combo:$slot');

/// A combo in the combos area's shape (`kind: combo` menu item + its
/// `combo_specs` slots): "Breakfast Combo" EGP 150 with a drink slot that
/// takes the Hot coffee category and a pastry slot (Croissant default).
void seedBreakfastCombo(
  MockDb db, {
  bool drinkSlot = true,
  String key = 'breakfast',
  String name = 'Breakfast Combo',
}) {
  final id = comboId(key);
  db[MenuTables.menuItems].insert({
    'id': id,
    'org_id': SeedIds.sabahOrg,
    'category_id': null,
    'name': name,
    'name_translations': {'en': name, 'ar': 'كومبو $name'},
    'description': null,
    'description_translations': const <String, Object?>{},
    'base_price': 15000,
    'is_active': true,
    'kind': 'combo',
    'image_url': null,
    'deleted_at': null,
  });
  db[comboSpecsTable].insert({
    'id': id,
    'slots': [
      if (drinkSlot)
        {
          'id': slotId(key, 'drink'),
          'name': 'Hot drink',
          'name_translations': {'en': 'Hot drink', 'ar': 'مشروب ساخن'},
          'sort': 0,
          'min': 1,
          'max': 1,
          'default_item_id': item('americano'),
          'default_size_label': null,
          'choices': [
            {
              'id': mockUuid('studio-test-choice:$key:drink:0'),
              'menu_item_id': null,
              'category_id': MenuSeedIds.category('hot'),
              'name': 'Hot coffee',
              'name_translations': const <String, Object?>{},
              'surcharge': 0,
              'included_size_label': 'Regular',
              'size_surcharges': [
                {'size_label': 'Large', 'surcharge': 1500},
              ],
              'sort': 0,
            },
          ],
        },
      {
        'id': slotId(key, 'pastry'),
        'name': 'Pastry',
        'name_translations': {'en': 'Pastry', 'ar': 'معجنات'},
        'sort': 1,
        'min': 1,
        'max': 1,
        'default_item_id': item('croissant'),
        'default_size_label': null,
        'choices': [
          {
            'id': mockUuid('studio-test-choice:$key:pastry:0'),
            'menu_item_id': item('croissant'),
            'category_id': null,
            'name': 'Croissant',
            'name_translations': const <String, Object?>{},
            'surcharge': 0,
            'included_size_label': null,
            'size_surcharges': const <Object?>[],
            'sort': 0,
          },
          {
            'id': mockUuid('studio-test-choice:$key:pastry:1'),
            'menu_item_id': item('almond_croissant'),
            'category_id': null,
            'name': 'Almond Croissant',
            'name_translations': const <String, Object?>{},
            'surcharge': 2000,
            'included_size_label': null,
            'size_surcharges': const <Object?>[],
            'sort': 1,
          },
        ],
      },
    ],
    'windows': const <Object?>[],
  });
}

/// The seed's one-size label, for readability.
const String oneSizeLabel = oneSize;

// ── page helpers ───────────────────────────────────────────────────────────

/// The floating save bar.
final Finder saveBar = find.byKey(const ValueKey('studio-save-bar'));

/// [text] inside the save bar.
Finder inSaveBar(String text) =>
    find.descendant(of: saveBar, matching: find.text(text));

/// Taps Save on the bar and lets the writes land.
Future<void> tapSave(DashHarness h) async {
  await h.tap(inSaveBar(h.t('common.save')));
  await h.settle();
}

/// The text field currently holding [text] inside the studio.
Finder fieldWithText(String text) => inStudio(
  find.byWidgetPredicate((w) => w is EditableText && w.controller.text == text),
);

/// The section whose heading is [title] (the StudioSection widget).
Finder sectionOf(String title) => find.ancestor(
  of: studioText(title),
  matching: find.byType(StudioSection),
);

/// [f] inside the section titled [title].
Finder inSection(String title, Finder f) =>
    find.descendant(of: sectionOf(title).first, matching: f);

/// Signs [persona] in with its capabilities changed (the UI reads them from
/// `/authz/me`; the server keeps checking the persona's own).
void overrideCaps(
  MockServer server,
  Persona persona, {
  List<String> remove = const [],
  List<String> add = const [],
}) {
  server.on('GET', '/authz/me', (req) {
    final caps = {...persona.capabilities, ...add}
      ..removeAll(remove);
    final list = caps.toList()..sort();
    return MockResponse.ok({
      'user_id': persona.userId,
      'branch_id': req.q('branch_id'),
      'capabilities': list,
      'everywhere': persona.branchIds == null ? list : const <String>[],
      'ask_manager': const <String>[],
      'limits': const <String, Object?>{},
      'owner': false,
      'platform': false,
      'role_kinds': persona.roleKinds,
      'epoch': 1,
      'spec_version': 2,
    });
  });
}

/// Text inside the studio containing [s] once the bidi isolates the
/// formatter adds around figures are taken out.
Finder studioPlain(String s) => inStudio(
  find.byWidgetPredicate((w) {
    final text = w is Text ? (w.data ?? w.textSpan?.toPlainText()) : null;
    return text != null &&
        text.replaceAll(RegExp('[\u2066-\u2069]'), '').contains(s);
  }),
);
