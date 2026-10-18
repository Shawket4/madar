// "Already on Foodics?" in the menu step (web `features/menu-import`): the
// exports read on the device by madar-shared's reader (the bridge, the same
// Rust the web runs as wasm), the preview, the server's dry run, the import;
// a replace behind the typed sentence; who is offered it; the screenshots.
import 'dart:convert';

import 'package:dashboard_admin/src/mock/onboarding_mock.dart';
import 'package:dashboard_admin/src/onboarding/step_navigator.dart';
import 'package:dashboard_api/dashboard_api.dart' show MyAuthz;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show PickedFile;
import 'package:dashboard_kit/dashboard_kit.dart' show DashButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _categories =
    'id,name,name_localized,reference,image\n'
    ',Coffee,قهوة,cat-1,\n'
    ',Cold,بارد,cat-2,\n';
const _products =
    'id,name,sku,category_reference,tax_group_reference,is_sold_by_weight,'
    'is_active,is_stock_product,price,barcode,description,preparation_time,'
    'calories,walking_minutes_to_burn_calories,is_high_salt,image,'
    'name_localized,description_localized,ereceipt_item_type,'
    'ereceipt_item_code,ereceipt_unit_type\n'
    ',"Espresso",p-1,cat-1,,No,Yes,No,110,,,,,,No,,إسبريسو,,,,\n'
    ',"Latte",p-2,cat-1,,No,Yes,No,150,,,,,,No,,لاتيه,,,,\n'
    ',"Iced Latte",p-3,cat-2,,No,Yes,No,165.5,,,,,,No,,,,,,\n';
const _links =
    'product_name,product_name_localized,product_sku,modifier_name,'
    'modifier_name_localized,modifier_reference,minimum_options,'
    'maximum_options,free_options,default_options,unique_options\n'
    ',,p-1,Extra Flavors,,,0,2,0,,No\n'
    ',,p-2,Milk,,,1,1,0,,No\n'
    ',,p-2,Extra Flavors,,,0,2,0,,No\n'
    ',,p-3,Milk,,,1,1,0,,No\n';
const _groups =
    'id,reference,name,name_localized\n'
    ',,Milk,الحليب\n'
    ',,Extra Flavors,نكهات إضافية\n';
const _options =
    'id,modifier_reference,modifier_name,modifier_name_localized,'
    'tax_group_reference,name,sku,price,calories,name_localized,is_active\n'
    ',,Milk,,,Full Cream,,0,,كامل الدسم,Yes\n'
    ',,Milk,,,Oat,,45,,شوفان,Yes\n'
    ',,Extra Flavors,,,Vanilla,,20,,,Yes\n'
    ',,Extra Flavors,,,Caramel,,20,,,Yes\n';

/// A café's five Foodics exports, as the picker hands them over.
List<PickedFile> _exports() => [
  for (final (name, text) in [
    ('categories.csv', _categories),
    ('products.csv', _products),
    ('product_modifiers.csv', _links),
    ('modifier_groups.csv', _groups),
    ('modifier_options.csv', _options),
  ])
    PickedFile(name: name, bytes: utf8.encode(text)),
];

const _bulk = '/menu/bulk';

/// Opens [title]'s step: from the navigator when there is one, else by
/// Continue until it shows.
Future<void> _openStep(DashHarness h, String title) async {
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

/// A fresh café (or one [seed] changes) with the menu step open.
Future<({DashHarness h, MockDb db})> _menuStep(
  WidgetTester tester, {
  void Function(MockDb db)? seed,
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  void Function(MockServer server)? serve,
}) async {
  final s = onboardingServer(persona: persona);
  freshCafe(s.db);
  seed?.call(s.db);
  serve?.call(s.server);
  final h = await pumpOnboarding(
    tester,
    server: s.server,
    db: s.db,
    persona: persona,
    size: size,
    locale: locale,
  );
  await _openStep(h, h.t('onboarding.steps.categories.title'));
  return (h: h, db: s.db);
}

/// The sentence the dialog asks for, as shown.
String _sentence(DashHarness h) => h.tester
    .widget<Text>(find.byKey(const ValueKey('replace-sentence')))
    .textSpan!
    .toPlainText();

/// `/authz/me` without [cap]: the person the server would refuse it.
void Function(MockServer) _without(String cap) =>
    (server) => server.on('GET', '/authz/me', (req) {
      final p = req.persona;
      final caps = [
        for (final c in p.capabilities)
          if (c != cap) c,
      ]..sort();
      return MockResponse.ok(
        MyAuthz(
          userId: p.userId,
          branchId: req.q('branch_id'),
          capabilities: caps,
          everywhere: caps,
          askManager: const [],
          limits: const {},
          owner: p.isOwner,
          platform: p.isPlatform,
          roleKinds: p.roleKinds,
          epoch: 1,
          specVersion: 2,
        ),
      );
    });

/// Picks the exports in the open dialog.
Future<void> _pick(DashHarness h, [List<PickedFile>? files]) async {
  h.files.filesQueue.add(files ?? _exports());
  await h.tap(buttonOf(h.t('menuImport.chooseFiles'), within: surface));
  await h.settle();
}

int _live(MockDb db, String table) => db[table].rows
    .where((r) => r['org_id'] == sabah && r['deleted_at'] == null)
    .length;

/// Shoots the open dialog top to bottom: `<name>-1`, `<name>-2`, …
Future<void> _shootSurface(DashHarness h, String name) async {
  final scroll = find
      .descendant(of: surface, matching: find.byType(Scrollable))
      .first;
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

void main() {
  group('Import from Foodics', () {
    testWidgets('reads the exports here, shows the menu, asks the server, '
        'then imports', (tester) async {
      final r = await _menuStep(tester);
      expect(inPage('Already on Foodics?'), findsOneWidget);
      await r.h.tap(buttonOf('Import from Foodics'));
      expect(inSurface('Import your menu from Foodics'), findsOneWidget);
      await _pick(r.h);

      expect(inSurface('Iced Latte'), findsOneWidget);
      expect(inSurface('Espresso · إسبريسو'), findsOneWidget);
      expect(
        inSurface('Madar checked this menu: it is ready to import.'),
        findsOneWidget,
      );
      // The dry run carried the menu the reader built, and kept nothing.
      final dry = r.h.server.callsTo(_bulk, method: 'POST').single;
      expect(dry.query['dry_run'], ['true']);
      expect(dry.status, 200);
      final sent = (dry.body! as Map)['menu'] as Map;
      expect((sent['items'] as List).length, 3);
      expect(_live(r.db, OnbTables.menuItems), 0);

      await r.h.tap(buttonOf('Import the menu', within: surface));
      await r.h.expectToast('Your menu is in. Items: 3.');
      final calls = r.h.server.callsTo(_bulk, method: 'POST');
      expect(calls.last.query['dry_run'], isNull);
      expect(calls.last.status, 201);
      expect(_live(r.db, OnbTables.menuItems), 3);
      expect(_live(r.db, OnbTables.categories), 2);
      // The checklist asked again: the step counts what came in.
      expect(inPage('2 categories created.'), findsOneWidget);
      expect(inPage('Replace from Foodics'), findsOneWidget);
    });

    testWidgets('a file that is not a menu export is named, and nothing is '
        'sent', (tester) async {
      final r = await _menuStep(tester);
      await r.h.tap(buttonOf('Import from Foodics'));
      await _pick(r.h, [
        PickedFile(name: 'people.csv', bytes: utf8.encode('name,price\nx,1\n')),
      ]);
      expect(
        inSurface('people.csv is not a Foodics menu export.'),
        findsOneWidget,
      );
      expect(r.h.server.callsTo(_bulk, method: 'POST'), isEmpty);
    });

    testWidgets('replace waits for the typed sentence, then puts the old menu '
        'away', (tester) async {
      final r = await _menuStep(
        tester,
        seed: (db) => addCategory(db, name: 'Old drinks'),
      );
      await r.h.tap(buttonOf('Replace from Foodics'));
      expect(
        inSurface('Replace your menu with a Foodics export'),
        findsOneWidget,
      );
      await _pick(r.h);
      expect(
        _sentence(r.h),
        'To confirm, type: Replace the menu of Sabah Coffee',
      );
      final run = buttonOf('Replace the menu', within: surface);
      expect(r.h.tester.widget<DashButton>(run).onPressed, isNull);
      final box = find.descendant(
        of: surface,
        matching: find.byType(EditableText),
      );
      await r.h.enterText(box, 'Replace the menu of Sabah');
      expect(inSurface('Type the sentence exactly as shown.'), findsOneWidget);
      expect(r.h.tester.widget<DashButton>(run).onPressed, isNull);
      await r.h.enterText(box, '  replace the MENU of sabah coffee ');
      expect(r.h.tester.widget<DashButton>(run).onPressed, isNotNull);
      await r.h.tap(run);
      await r.h.expectToast('Your menu is in. Items: 3.');
      final last = r.h.server.callsTo(_bulk, method: 'POST').last;
      expect((last.body! as Map)['mode'], 'replace');
      expect(
        (last.body! as Map)['confirm'],
        '  replace the MENU of sabah coffee ',
      );
      // The old category is put away, not deleted.
      final old = r.db[OnbTables.categories].rows.singleWhere(
        (c) => c['name'] == 'Old drinks',
      );
      expect(old['deleted_at'], isNotNull);
      expect(_live(r.db, OnbTables.categories), 2);
    });

    testWidgets('an Arabic reader is shown the Arabic sentence and Arabic '
        'names first', (tester) async {
      final r = await _menuStep(
        tester,
        locale: 'ar',
        seed: (db) => addCategory(db, name: 'Old drinks'),
      );
      await r.h.tap(buttonOf('الاستبدال من Foodics'));
      await _pick(r.h);
      expect(_sentence(r.h), endsWith('استبدل قائمة Sabah Coffee'));
      expect(inSurface('إسبريسو · Espresso'), findsOneWidget);
    });

    testWidgets('when the server finds the menu is not empty, it offers the '
        'replace', (tester) async {
      final r = await _menuStep(tester);
      await r.h.tap(buttonOf('Import from Foodics'));
      // Someone added a category since the step was read.
      addCategory(r.db, name: 'Meanwhile');
      await _pick(r.h);
      expect(
        inSurface(
          'The menu already has categories or items. Replace it instead.',
        ),
        findsOneWidget,
      );
      await r.h.tap(buttonOf('Replace the menu instead', within: surface));
      expect(find.byKey(const ValueKey('replace-sentence')), findsOneWidget);
    });

    testWidgets('someone who may add but not delete is offered the import '
        'into an empty menu, never the replace', (tester) async {
      final empty = await _menuStep(
        tester,
        serve: _without('menu.items.delete'),
      );
      expect(inPage('Import from Foodics'), findsOneWidget);
      await empty.h.tap(buttonOf('Import from Foodics'));
      // Even when the server finds the menu is not empty.
      addCategory(empty.db, name: 'Meanwhile');
      await _pick(empty.h);
      expect(inSurface('Replace the menu instead'), findsNothing);
    });

    testWidgets('with a menu, someone who may not delete is offered nothing', (
      tester,
    ) async {
      await _menuStep(
        tester,
        seed: (db) => addCategory(db, name: 'Old drinks'),
        serve: _without('menu.items.delete'),
      );
      expect(inPage('Already on Foodics?'), findsNothing);
    });
  });

  group('Import from Foodics: screenshots', () {
    for (final (size, locale) in const [
      (DashSize.desktop, 'en'),
      (DashSize.phone, 'ar'),
      (DashSize.phone, 'en'),
    ]) {
      testWidgets('preview at ${size.name}-$locale', (tester) async {
        final r = await _menuStep(
          tester,
          size: size,
          locale: locale,
          seed: locale == 'ar'
              ? (db) => addCategory(db, name: 'Old drinks')
              : null,
        );
        await r.h.shot('onboarding/foodics-card');
        await r.h.tap(
          buttonOf(
            r.h.t(
              locale == 'ar'
                  ? 'menuImport.cardReplaceCta'
                  : 'menuImport.cardCta',
            ),
          ),
        );
        await r.h.shot('onboarding/foodics-pick');
        await _pick(r.h);
        await _shootSurface(r.h, 'foodics-preview');
      });
    }
  });
}
