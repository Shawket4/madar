// The usage dialog ("Used on N items" → tick the items that offer a group),
// rows MENU-GRP-017..022 and -050. Coffee beans is offered on Espresso,
// Americano and Cortado (required); Milk on 15 items (optional).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/groups/group_usage_dialog.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _title = 'Items offering Coffee beans';

Future<DashHarness> openBeansUsage(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  ({MockServer server, MockDb db})? seeded,
  DashSize size = DashSize.desktop,
  String locale = 'en',
}) async {
  final h = await pumpGroups(
    tester,
    persona: persona,
    seeded: seeded,
    size: size,
    locale: locale,
  );
  await h.tap(textIn(rowOf(beansId), h.t('menu.groups.usedOn', count: 3)));
  return h;
}

Finder dialog() => find.byType(GroupUsageDialog);

/// The checkbox of the item a screen reader calls [name].
DashCheckbox box(WidgetTester tester, String name) => tester.widget(
  find.byWidgetPredicate((w) => w is DashCheckbox && w.semanticLabel == name),
);

Finder itemRow(String name) => find
    .ancestor(
      of: find.byWidgetPredicate(
        (w) => w is DashCheckbox && w.semanticLabel == name,
      ),
      matching: find.byType(Row),
    )
    .first;

Future<void> search(DashHarness h, String q) => h.enterText(
  find.descendant(of: dialog(), matching: find.byType(DashSearchInput)),
  q,
);

/// The item ids offering [groupId] in the db.
Set<String> offering(MockDb db, String groupId) => {
  for (final l in db[MenuTables.groupLinks].where(
    (l) => l['group_id'] == groupId,
  ))
    l['menu_item_id'] as String,
};

void main() {
  testWidgets('MENU-GRP-017 title and description; also opened from the '
      'editor\'s "Manage…" on top of it', (tester) async {
    final h = await openBeansUsage(tester);
    expect(find.text(_title), findsOneWidget);
    expect(
      find.text(
        "Tick the items that offer this group. Per-item rules (required, which "
        "options) stay editable in each item's editor.",
      ),
      findsOneWidget,
    );
    await h.shot('groups/usage');
    await h.tap(textIn(dialog(), 'Cancel'));
    await h.tap(labelIn(rowOf(beansId), 'Edit'));
    await h.tap(textIn(surface('Edit choice group'), 'Manage…'));
    expect(find.text(_title), findsOneWidget);
    expect(find.text('Edit choice group'), findsOneWidget);
  });

  testWidgets('MENU-GRP-018 every live item by name, ticked where the group '
      'is offered', (tester) async {
    final h = await openBeansUsage(tester);
    final call = h.server.callsTo(itemsT).single;
    expect(call.query['org_id'], [SeedIds.sabahOrg]);
    for (final name in ['Espresso', 'Americano', 'Cortado']) {
      expect(box(tester, name).value, isTrue, reason: name);
    }
    expect(box(tester, 'Cappuccino').value, isFalse);
    final names = [
      for (final w in tester.widgetList<DashCheckbox>(
        find.descendant(of: dialog(), matching: find.byType(DashCheckbox)),
      ))
        w.semanticLabel,
    ];
    expect(names.first, 'Almond Croissant');
    expect(names, hasLength(40));
    expect(
      names,
      orderedEquals(
        [...names]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
      ),
    );
  });

  testWidgets('MENU-GRP-019 search: name contains, any case', (tester) async {
    final h = await openBeansUsage(tester);
    await search(h, 'ICED');
    final shown = [
      for (final w in tester.widgetList<DashCheckbox>(
        find.descendant(of: dialog(), matching: find.byType(DashCheckbox)),
      ))
        w.semanticLabel,
    ];
    expect(shown, isNotEmpty);
    expect(shown.every((n) => n.toLowerCase().contains('iced')), isTrue);
    expect(shown, contains('Iced Latte'));
  });

  testWidgets('MENU-GRP-020 badges: Inactive items, Required / Optional for '
      'items using the group', (tester) async {
    final s = groupsServer();
    final cortado = MenuSeedIds.item('cortado');
    s.db[MenuTables.menuItems].find(cortado)!['is_active'] = false;
    final h = await openBeansUsage(tester, seeded: s);
    expect(textIn(itemRow('Cortado'), 'Inactive'), findsOneWidget);
    expect(textIn(itemRow('Cortado'), 'Required'), findsOneWidget);
    expect(textIn(itemRow('Espresso'), 'Required'), findsOneWidget);
    expect(textIn(itemRow('Espresso'), 'Inactive'), findsNothing);
    expect(textIn(itemRow('Cappuccino'), 'Required'), findsNothing);
    expect(textIn(itemRow('Cappuccino'), 'Optional'), findsNothing);
    await h.tap(textIn(dialog(), 'Cancel'));
    await h.tap(textIn(rowOf(milkId), 'Used on 15 items'));
    expect(textIn(itemRow('Cappuccino'), 'Optional'), findsOneWidget);
  });

  group('MENU-GRP-021 Apply', () {
    testWidgets('disabled until the ticks differ; adds and drops the group '
        'keeping the other attachments; toast; closes; usage refetched', (
      tester,
    ) async {
      final h = await openBeansUsage(tester);
      final db = h.db!;
      final apply = find.descendant(
        of: dialog(),
        matching: find.widgetWithText(DashButton, 'Apply'),
      );
      expect(tester.widget<DashButton>(apply).onPressed, isNull);
      await h.tap(labelIn(dialog(), 'Cappuccino'));
      await h.tap(labelIn(dialog(), 'Cortado'));
      expect(tester.widget<DashButton>(apply).onPressed, isNotNull);
      final cappuccino = MenuSeedIds.item('cappuccino');
      final cortado = MenuSeedIds.item('cortado');
      final before = db[MenuTables.groupLinks]
          .where((l) => l['menu_item_id'] == cappuccino)
          .map((l) => l['group_id'])
          .toList();
      final usage = h.server.callsTo(usageT).length;
      await h.tap(apply);
      expect(
        [for (final c in h.server.callsTo(studioT)) c.path],
        ['/menu-items/$cappuccino/studio', '/menu-items/$cortado/studio'],
      );
      final puts = h.server.callsTo(attachT, method: 'PUT');
      expect(
        [for (final p in puts) p.path],
        [
          '/menu-items/$cappuccino/modifier-groups',
          '/menu-items/$cortado/modifier-groups',
        ],
      );
      final added = ((puts.first.body! as Map)['groups'] as List)
          .cast<Map<String, Object?>>();
      expect([for (final g in added) g['group_id']], [...before, beansId]);
      expect(added.last, {
        'group_id': beansId,
        'sort': before.length,
        'min_override': 1,
        'max_override': 1,
        'is_required_override': true,
        'included_option_ids': null,
      });
      expect(
        [for (final g in added) g['sort']],
        [for (var i = 0; i < added.length; i++) i],
      );
      final dropped = ((puts.last.body! as Map)['groups'] as List)
          .cast<Map<String, Object?>>();
      expect(dropped.map((g) => g['group_id']), isNot(contains(beansId)));
      expect(dropped.map((g) => g['group_id']), contains(milkId));
      await h.expectToast('Changes saved');
      expect(find.text(_title), findsNothing);
      expect(offering(db, beansId), {
        MenuSeedIds.item('espresso'),
        MenuSeedIds.item('americano'),
        cappuccino,
      });
      expect(h.server.callsTo(usageT).length, greaterThan(usage));
      expect(textIn(rowOf(beansId), 'Used on 3 items'), findsOneWidget);
    });

    testWidgets("a per-item failure: the server's words, the others still "
        'saved, the dialog stays open', (tester) async {
      final s = groupsServer();
      final refused = MockResponse.badRequest(
        'Modifier group not found in this organization',
      );
      s.server.fail('PUT', attachT, refused);
      final h = await openBeansUsage(tester, seeded: s);
      await h.tap(labelIn(dialog(), 'Cappuccino'));
      await h.tap(labelIn(dialog(), 'Cortado'));
      await h.tap(
        find.descendant(
          of: dialog(),
          matching: find.widgetWithText(DashButton, 'Apply'),
        ),
      );
      expect(find.text(h.refusalWords(refused)), findsWidgets);
      expect(h.server.callsTo(attachT, method: 'PUT'), hasLength(2));
      expect(find.text(_title), findsOneWidget);
      expect(
        offering(h.db!, beansId),
        isNot(contains(MenuSeedIds.item('cortado'))),
      );
      await h.flushTimers();
    });
  });

  for (final persona in [Persona.manager, Persona.limited]) {
    testWidgets('MENU-GRP-022 ${persona.name}: checkboxes off, no Apply', (
      tester,
    ) async {
      final h = await openBeansUsage(tester, persona: persona);
      expect(box(tester, 'Espresso').enabled, isFalse);
      expect(box(tester, 'Cappuccino').enabled, isFalse);
      expect(textIn(dialog(), 'Apply'), findsNothing);
      await h.tap(labelIn(dialog(), 'Cappuccino'));
      expect(box(tester, 'Cappuccino').value, isFalse);
    });
  }

  group('MENU-GRP-050 (divergence) states', () {
    testWidgets('loading: a skeleton in the box', (tester) async {
      final s = groupsServer();
      final gate = s.server.hold('GET', itemsT);
      final h = await openBeansUsage(tester, seeded: s);
      expect(
        find.descendant(of: dialog(), matching: find.byType(DashSkeleton)),
        findsOneWidget,
      );
      gate.release();
      await h.settle();
      expect(box(tester, 'Espresso').value, isTrue);
    });

    testWidgets('no match: "No results found"', (tester) async {
      final h = await openBeansUsage(tester);
      await search(h, 'zzz');
      expect(textIn(dialog(), 'No results found'), findsOneWidget);
      await h.shot('groups/usage-no-match');
    });

    testWidgets('a failed read: the words and Retry', (tester) async {
      final s = groupsServer();
      // Twice: the press's touch warms the read first, and a failed warm is
      // dropped so the dialog asks again.
      s.server.fail(
        'GET',
        itemsT,
        MockResponse.error(500, 'Database is down'),
        times: 2,
      );
      final h = await openBeansUsage(tester, seeded: s);
      expect(textIn(dialog(), "Couldn't load this"), findsOneWidget);
      expect(textIn(dialog(), 'Database is down'), findsOneWidget);
      final gate = s.server.hold('GET', itemsT);
      await h.tap(textIn(dialog(), 'Retry'));
      expect(textIn(dialog(), "Couldn't load this"), findsOneWidget);
      expect(textIn(dialog(), 'No results found'), findsNothing);
      gate.release();
      await h.settle();
      expect(box(tester, 'Espresso').value, isTrue);
    });

    testWidgets('MENU-GRP-018 (divergence) Arabic: sorted by the name shown; '
        'a blank Arabic name shows the name', (tester) async {
      final s = groupsServer();
      final latte = MenuSeedIds.item('latte');
      s.db[MenuTables.menuItems].find(latte)!['name_translations'] = {'ar': ''};
      await openBeansUsage(tester, seeded: s, locale: 'ar');
      final names = [
        for (final w in tester.widgetList<DashCheckbox>(
          find.descendant(of: dialog(), matching: find.byType(DashCheckbox)),
        ))
          w.semanticLabel,
      ];
      expect(names, contains('Caffè Latte'));
      expect(
        names,
        orderedEquals(
          [...names]
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
        ),
      );
    });

    testWidgets('Arabic: item names in Arabic', (tester) async {
      final h = await openBeansUsage(
        tester,
        locale: 'ar',
        size: DashSize.phone,
      );
      final espresso = h.db![MenuTables.menuItems].find(
        MenuSeedIds.item('espresso'),
      )!;
      final ar = (espresso['name_translations'] as Map)['ar'] as String;
      expect(box(tester, ar).value, isTrue);
      await h.shot('groups/usage');
    });
  });
}
