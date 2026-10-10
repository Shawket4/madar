// `/menu/groups` driven through the real app shell: the list rows
// MENU-GRP-001..016 (and MENU-AREA-010 for this page). Expectations are
// hand-counted from the seed (see support.dart): Milk is offered on 15
// items, Extras on 19, Coffee beans on 3 (Espresso, Americano, Cortado),
// Sweetness on 1 (Turkish Coffee), Toppings on 2 (Caramel Frappé, Iced
// Mocha) and Serving cup on none.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/groups/group_usage_dialog.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The rows' top edges, in [ids] order.
List<double> tops(WidgetTester tester, List<String> ids) => [
  for (final id in ids) tester.getTopLeft(rowOf(id)).dy,
];

/// The group ids as shown, top to bottom.
List<String> shownOrder(WidgetTester tester) {
  final ids = [...seededOrder]
    ..retainWhere((id) => rowOf(id).evaluate().isNotEmpty)
    ..sort(
      (a, b) => tester
          .getTopLeft(rowOf(a))
          .dy
          .compareTo(tester.getTopLeft(rowOf(b)).dy),
    );
  return ids;
}

void main() {
  group('MENU-GRP-001..005 page, data and states', () {
    testWidgets('MENU-GRP-001 header: title, subtitle and "New group"', (
      tester,
    ) async {
      await pumpGroups(tester);
      final page = find.byType(DashPageScaffold);
      expect(textIn(page, 'Choice groups'), findsOneWidget);
      expect(
        textIn(
          page,
          'Milk, beans, flavours, extras: the choices the cashier offers on '
          'items.',
        ),
        findsOneWidget,
      );
      expect(textIn(page, 'New group'), findsOneWidget);
    });

    testWidgets('MENU-GRP-002 / MENU-AREA-010 no org: the pick-an-org state, '
        'no header, nothing fetched', (tester) async {
      final h = await pumpGroups(tester, persona: Persona.platform);
      expect(
        find.text('Select an organization to manage its menu'),
        findsOneWidget,
      );
      expect(find.byType(DashPageScaffold), findsNothing);
      expect(h.server.callsTo(listT), isEmpty);
      await h.container
          .read(selectedOrgProvider.notifier)
          .select(SeedIds.sabahOrg);
      await h.settle();
      expect(rowOf(milkId), findsOneWidget);
    });

    testWidgets('MENU-GRP-003 every shared group, inactive too, by sort then '
        'name; item-private option sets hidden', (tester) async {
      final s = groupsServer();
      // An item's own "Options" set (no legacy type) and a shared group that
      // ties Toppings on sort and sorts after it by name.
      s.db[MenuTables.groups]
        ..insert({
          ...groupRow(s.db, sweetnessId),
          'id': 'private-options',
          'name': 'Options',
          'legacy_addon_type': null,
          'is_item_options': true,
        }, timestamps: false)
        ..insert({
          ...groupRow(s.db, toppingsId),
          'id': 'whipped',
          'name': 'Whipped toppings',
          'legacy_addon_type': 'whipped_toppings',
        }, timestamps: false);
      final h = await pumpGroups(tester, seeded: s);
      final call = h.server.callsTo(listT).single;
      expect(call.query['org_id'], [SeedIds.sabahOrg]);
      expect(call.query['include_inactive'], ['true']);
      expect(find.text('Options'), findsNothing);
      expect(rowOf(servingId), findsOneWidget);
      final y = tops(tester, [...seededOrder.take(5), 'whipped', servingId]);
      expect(y, orderedEquals([...y]..sort()));
    });

    testWidgets('MENU-GRP-003 refusal: an org without POS (Dawam only) reads '
        'no groups', (tester) async {
      final h = await pumpGroups(tester, persona: Persona.dawamOnly);
      expect(h.server.callsTo(listT), isEmpty);
      expect(find.byType(DashPageScaffold), findsNothing);
    });

    testWidgets(
      'MENU-GRP-004 (divergence) loading: a skeleton, then the rows',
      (tester) async {
        final s = groupsServer();
        final gate = s.server.hold('GET', listT);
        final h = await pumpGroups(tester, seeded: s);
        final page = find.byType(DashPageScaffold);
        expect(
          find.descendant(of: page, matching: find.byType(DashSkeleton)),
          findsOneWidget,
        );
        expect(find.text('Milk'), findsNothing);
        await h.shot('groups/loading');
        gate.release();
        await h.settle();
        expect(rowOf(milkId), findsOneWidget);
      },
    );

    testWidgets('MENU-GRP-004 (divergence) a failed read: the words, the '
        "server's reason, Retry refetches the list only", (tester) async {
      final s = groupsServer();
      s.server.fail('GET', listT, MockResponse.error(500, 'Database is down'));
      final h = await pumpGroups(tester, seeded: s);
      expect(find.text("Couldn't load this"), findsOneWidget);
      expect(find.text('Database is down'), findsOneWidget);
      expect(find.text('No choice groups yet'), findsNothing);
      await h.shot('groups/error');
      final usageBefore = h.server.callsTo(usageT).length;
      // While the retry runs: still the error (its button spinning), never
      // the empty state or a skeleton.
      final gate = s.server.hold('GET', listT);
      await h.tapText('Retry');
      expect(find.text("Couldn't load this"), findsOneWidget);
      expect(find.text('No choice groups yet'), findsNothing);
      gate.release();
      await h.settle();
      expect(rowOf(milkId), findsOneWidget);
      expect(h.server.callsTo(listT), hasLength(2));
      expect(h.server.callsTo(usageT).length - usageBefore, 6);
    });

    testWidgets('MENU-GRP-005 empty: "No choice groups yet", New group stays', (
      tester,
    ) async {
      final s = groupsServer();
      registerNothing(s.db);
      final h = await pumpGroups(tester, seeded: s);
      expect(find.text('No choice groups yet'), findsOneWidget);
      expect(find.text('New group'), findsOneWidget);
      await h.shot('groups/empty');
    });
  });

  group('MENU-GRP-006..011 a row', () {
    testWidgets('MENU-GRP-006 name, Arabic name; the name opens the editor', (
      tester,
    ) async {
      final h = await pumpGroups(tester);
      expect(textIn(rowOf(beansId), 'Coffee beans'), findsOneWidget);
      expect(textIn(rowOf(beansId), 'البن'), findsOneWidget);
      await h.tap(textIn(rowOf(beansId), 'Coffee beans'));
      expect(find.text('Edit choice group'), findsOneWidget);
      expect(h.location.queryParameters['edit'], beansId);
    });

    testWidgets('MENU-GRP-007 pick rule badges', (tester) async {
      await pumpGroups(tester);
      expect(textIn(rowOf(milkId), 'Pick up to 1'), findsOneWidget);
      expect(textIn(rowOf(extrasId), 'Pick any number'), findsOneWidget);
      expect(textIn(rowOf(beansId), 'Pick exactly 1'), findsOneWidget);
      expect(textIn(rowOf(sweetnessId), 'Pick exactly 1'), findsOneWidget);
      expect(textIn(rowOf(toppingsId), 'Pick up to 2'), findsOneWidget);
      expect(textIn(rowOf(servingId), 'Pick any number'), findsOneWidget);
    });

    testWidgets('MENU-GRP-008 effect badges, the swap ones filled', (
      tester,
    ) async {
      final s = groupsServer();
      s.db[MenuTables.groups]
        ..insert({
          ...groupRow(s.db, beansId),
          'id': 'syrup-swap',
          'name': 'Syrup swap',
          'sort': 10,
          'legacy_addon_type': 'syrup_swap',
          'swap_category_id': MenuSeedIds.ingredientCategory('syrup'),
          'swap_category_slug': 'syrup',
        }, timestamps: false)
        ..insert({
          ...groupRow(s.db, servingId),
          'id': 'legacy',
          'name': 'Legacy',
          'sort': 11,
          'effect': 'legacy',
          'legacy_addon_type': 'legacy',
        }, timestamps: false);
      await pumpGroups(tester, seeded: s);
      expect(textIn(rowOf(milkId), "Swaps the drink's milk"), findsOneWidget);
      expect(textIn(rowOf(beansId), "Swaps the drink's beans"), findsOneWidget);
      expect(
        textIn(rowOf('syrup-swap'), 'Swaps an ingredient'),
        findsOneWidget,
      );
      expect(textIn(rowOf(extrasId), 'Adds ingredients'), findsOneWidget);
      expect(
        textIn(rowOf(sweetnessId), 'Nothing to stock (just a note or a price)'),
        findsOneWidget,
      );
      expect(
        textIn(rowOf('legacy'), 'Adds ingredients or nothing'),
        findsOneWidget,
      );
      GroupBadgeVariant variantOf(String id, String text) => tester
          .widget<GroupBadge>(
            find.ancestor(
              of: textIn(rowOf(id), text),
              matching: find.byType(GroupBadge),
            ),
          )
          .variant;
      expect(
        variantOf(beansId, "Swaps the drink's beans"),
        GroupBadgeVariant.filled,
      );
      expect(
        variantOf(extrasId, 'Adds ingredients'),
        GroupBadgeVariant.secondary,
      );
    });

    testWidgets('MENU-GRP-009 option count (plural) and Inactive', (
      tester,
    ) async {
      final s = groupsServer();
      final serving = groupRow(s.db, servingId);
      serving['options'] = [(serving['options'] as List).first];
      await pumpGroups(tester, seeded: s);
      expect(textIn(rowOf(milkId), '6 options'), findsOneWidget);
      expect(textIn(rowOf(servingId), '1 option'), findsOneWidget);
      expect(textIn(rowOf(servingId), 'Inactive'), findsOneWidget);
      expect(textIn(rowOf(milkId), 'Inactive'), findsNothing);
    });

    testWidgets('MENU-GRP-010 "Used on" per group: one usage read each, "…" '
        'and disabled until it lands, then opens the usage dialog', (
      tester,
    ) async {
      final s = groupsServer();
      final gate = s.server.hold('GET', usageT);
      final h = await pumpGroups(tester, seeded: s);
      expect(textIn(rowOf(milkId), '…'), findsOneWidget);
      await tester.tap(textIn(rowOf(milkId), '…'), warnIfMissed: false);
      await h.settle();
      expect(find.text('Items offering Milk'), findsNothing);
      gate.release();
      await h.settle();
      expect(
        {for (final c in h.server.callsTo(usageT)) c.path},
        {for (final id in seededOrder) '/modifier-groups/$id/usage'},
      );
      expect(h.server.callsTo(usageT), hasLength(6));
      expect(textIn(rowOf(milkId), 'Used on 15 items'), findsOneWidget);
      expect(textIn(rowOf(extrasId), 'Used on 19 items'), findsOneWidget);
      expect(textIn(rowOf(beansId), 'Used on 3 items'), findsOneWidget);
      expect(textIn(rowOf(sweetnessId), 'Used on 1 item'), findsOneWidget);
      expect(textIn(rowOf(servingId), 'Used on 0 items'), findsOneWidget);
      await h.tap(textIn(rowOf(beansId), 'Used on 3 items'));
      expect(find.text('Items offering Coffee beans'), findsOneWidget);
    });

    testWidgets('MENU-GRP-011 row actions: up / down disabled at the ends, '
        'Edit opens the editor', (tester) async {
      final h = await pumpGroups(tester);
      DashIconButton button(String id, String label) => tester.widget(
        find
            .ancestor(
              of: labelIn(rowOf(id), label),
              matching: find.byType(DashIconButton),
            )
            .first,
      );
      expect(button(milkId, 'Move up').onPressed, isNull);
      expect(button(milkId, 'Move down').onPressed, isNotNull);
      expect(button(servingId, 'Move down').onPressed, isNull);
      expect(button(servingId, 'Move up').onPressed, isNotNull);
      for (final id in seededOrder) {
        expect(labelIn(rowOf(id), 'Edit'), findsOneWidget);
        expect(labelIn(rowOf(id), 'Delete'), findsOneWidget);
        expect(
          labelIn(rowOf(id), 'Drag ${groupRow(h.db!, id)['name']} to reorder'),
          findsOneWidget,
        );
      }
      await h.tap(labelIn(rowOf(toppingsId), 'Edit'));
      expect(find.text('Edit choice group'), findsOneWidget);
      expect(h.location.queryParameters['edit'], toppingsId);
    });
  });

  group('MENU-GRP-012 reorder', () {
    testWidgets('Move down: optimistic, one PATCH per moved group, toast, '
        'list and catalog refetched', (tester) async {
      final h = await pumpGroups(tester);
      final lists = h.server.callsTo(listT).length;
      final invalidated = recordInvalidations(h);
      await h.tap(labelIn(rowOf(milkId), 'Move down'));
      expect(invalidated, containsAll(catalogPrefixes));
      final patches = h.server.callsTo(groupT, method: 'PATCH');
      expect(
        [for (final p in patches) p.path],
        ['/modifier-groups/$extrasId', '/modifier-groups/$milkId'],
      );
      expect(
        [for (final p in patches) p.body],
        [
          {'sort': 0},
          {'sort': 1},
        ],
      );
      await h.expectToast('Changes saved');
      expect(shownOrder(tester).take(2), [extrasId, milkId]);
      expect(h.server.callsTo(listT).length, greaterThan(lists));
      expect(groupRow(h.db!, milkId)['sort'], 1);
    });

    testWidgets('Move up on the last row', (tester) async {
      final h = await pumpGroups(tester);
      await h.tap(labelIn(rowOf(servingId), 'Move up'));
      expect(
        [for (final p in h.server.callsTo(groupT, method: 'PATCH')) p.body],
        [
          {'sort': 4},
          {'sort': 5},
        ],
      );
      await h.flushTimers();
      expect(shownOrder(tester).sublist(4), [servingId, toppingsId]);
    });

    testWidgets('a failed PATCH restores the order and shows the reason', (
      tester,
    ) async {
      final s = groupsServer();
      final denied = MockResponse.denied('menu.items.edit');
      s.server.fail('PATCH', groupT, denied);
      final h = await pumpGroups(tester, seeded: s);
      await h.tap(labelIn(rowOf(milkId), 'Move down'));
      expect(find.text(h.refusalWords(denied)), findsWidgets);
      await h.flushTimers();
      expect(shownOrder(tester), seededOrder);
    });

    testWidgets('drag by the handle', (tester) async {
      final h = await pumpGroups(tester);
      final handle = labelIn(rowOf(milkId), 'Drag Milk to reorder');
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await h.settle();
      expect(
        [for (final p in h.server.callsTo(groupT, method: 'PATCH')) p.path],
        ['/modifier-groups/$extrasId', '/modifier-groups/$milkId'],
      );
      await h.expectToast('Changes saved');
      expect(shownOrder(tester).take(2), [extrasId, milkId]);
    });
  });

  group('MENU-GRP-013 delete', () {
    testWidgets('confirm, delete, toast; an unused group goes', (tester) async {
      final h = await pumpGroups(tester);
      final invalidated = recordInvalidations(h);
      await h.tap(labelIn(rowOf(servingId), 'Delete'));
      expect(find.text('Delete Serving cup?'), findsOneWidget);
      expect(
        find.text(
          'If items still offer it or orders used it, it is switched off '
          'instead, so history stays intact.',
        ),
        findsOneWidget,
      );
      await h.shot('groups/delete-confirm');
      final confirm = find.ancestor(
        of: find.text('Delete Serving cup?'),
        matching: find.byType(DashConfirmDialog),
      );
      await h.tap(textIn(confirm, 'Delete'));
      expect(
        h.server.callsTo(groupT, method: 'DELETE').single.path,
        '/modifier-groups/$servingId',
      );
      await h.expectToast('Changes saved');
      expect(rowOf(servingId), findsNothing);
      expect(invalidated, containsAll(catalogPrefixes));
    });

    testWidgets('a group items still offer is switched off instead', (
      tester,
    ) async {
      final h = await pumpGroups(tester);
      await h.tap(labelIn(rowOf(beansId), 'Delete'));
      await h.tap(textIn(find.byType(DashConfirmDialog), 'Delete'));
      await h.expectToast('Changes saved');
      expect(textIn(rowOf(beansId), 'Inactive'), findsOneWidget);
    });

    testWidgets('Cancel sends nothing', (tester) async {
      final h = await pumpGroups(tester);
      await h.tap(labelIn(rowOf(servingId), 'Delete'));
      await h.tap(textIn(find.byType(DashConfirmDialog), 'Cancel'));
      expect(h.server.callsTo(groupT, method: 'DELETE'), isEmpty);
      expect(rowOf(servingId), findsOneWidget);
    });

    testWidgets("a refusal shows the server's words", (tester) async {
      final s = groupsServer();
      final denied = MockResponse.denied('menu.items.edit');
      s.server.fail('DELETE', groupT, denied);
      final h = await pumpGroups(tester, seeded: s);
      await h.tap(labelIn(rowOf(servingId), 'Delete'));
      await h.tap(textIn(find.byType(DashConfirmDialog), 'Delete'));
      expect(find.text(h.refusalWords(denied)), findsWidgets);
      await h.flushTimers();
      expect(rowOf(servingId), findsOneWidget);
    });
  });

  group('MENU-GRP-014 refusal: read-only people', () {
    for (final persona in [Persona.manager, Persona.limited]) {
      testWidgets('${persona.name}: no create, reorder, edit or delete', (
        tester,
      ) async {
        final h = await pumpGroups(tester, persona: persona);
        expect(rowOf(milkId), findsOneWidget);
        final page = find.byType(DashPageScaffold);
        expect(textIn(page, 'New group'), findsNothing);
        expect(labelIn(page, 'Delete'), findsNothing);
        expect(labelIn(page, 'Edit'), findsNothing);
        expect(labelIn(page, 'Move up'), findsNothing);
        expect(labelIn(page, 'Move down'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('to reorder')), findsNothing);
        await h.shot('groups/read-only-${persona.name}');
      });
    }

    testWidgets('the name opens the editor read-only: Close, no Save', (
      tester,
    ) async {
      final h = await pumpGroups(tester, persona: Persona.limited);
      await h.tap(textIn(rowOf(beansId), 'Coffee beans'));
      final editor = surface('Edit choice group');
      expect(textIn(editor, 'Close'), findsOneWidget);
      expect(textIn(editor, 'Save'), findsNothing);
      expect(textIn(editor, 'Cancel'), findsNothing);
      await h.shot('groups/editor-read-only');
    });

    testWidgets('"Used on" opens the usage dialog read-only', (tester) async {
      final h = await pumpGroups(tester, persona: Persona.limited);
      await h.tap(textIn(rowOf(beansId), 'Used on 3 items'));
      final dialog = surface('Items offering Coffee beans');
      expect(textIn(dialog, 'Apply'), findsNothing);
      expect(textIn(dialog, 'Cancel'), findsOneWidget);
    });
  });

  group('MENU-GRP-015 deep links', () {
    testWidgets('?edit=<id> opens that group; closing drops ?edit', (
      tester,
    ) async {
      final h = await pumpGroups(tester, path: '$groupsPath?edit=$toppingsId');
      final editor = surface('Edit choice group');
      expect(
        find.descendant(of: editor, matching: find.text('Toppings')),
        findsWidgets,
      );
      await h.tap(textIn(editor, 'Cancel'));
      expect(find.text('Edit choice group'), findsNothing);
      expect(h.location.queryParameters.containsKey('edit'), isFalse);
      expect(h.location.path, groupsPath);
    });

    testWidgets('?edit=<unknown> opens nothing', (tester) async {
      await pumpGroups(tester, path: '$groupsPath?edit=nope');
      expect(find.text('Edit choice group'), findsNothing);
      expect(find.text('New choice group'), findsNothing);
    });

    testWidgets('?edit=new opens the create editor for an editor', (
      tester,
    ) async {
      final h = await pumpGroups(tester, path: '$groupsPath?edit=new');
      expect(find.text('New choice group'), findsOneWidget);
      await h.tap(textIn(surface('New choice group'), 'Cancel'));
      expect(h.location.queryParameters.containsKey('edit'), isFalse);
    });

    testWidgets('?edit=new opens nothing without the capability', (
      tester,
    ) async {
      await pumpGroups(
        tester,
        path: '$groupsPath?edit=new',
        persona: Persona.limited,
      );
      expect(find.text('New choice group'), findsNothing);
    });

    testWidgets('"New group" sets ?edit=new', (tester) async {
      final h = await pumpGroups(tester);
      await h.tap(textIn(find.byType(DashPageScaffold), 'New group'));
      expect(h.location.queryParameters['edit'], 'new');
      expect(find.text('New choice group'), findsOneWidget);
    });
  });

  testWidgets('MENU-GRP-013/017 (divergence) Arabic: a blank Arabic name '
      'falls back to the name, never a hole in the sentence', (tester) async {
    final s = groupsServer();
    groupRow(s.db, servingId)['name_translations'] = {'ar': ''};
    groupRow(s.db, beansId)['name_translations'] = {'ar': '  '};
    final h = await pumpGroups(tester, seeded: s, locale: 'ar');
    await h.tap(labelIn(rowOf(servingId), h.t('common.delete')));
    expect(
      find.text(h.t('menu.groups.deleteTitle', args: {'name': 'Serving cup'})),
      findsOneWidget,
    );
    await h.tap(textIn(find.byType(DashConfirmDialog), h.t('common.cancel')));
    await h.tap(textIn(rowOf(beansId), h.t('menu.groups.usedOn', count: 3)));
    expect(
      find.text(h.t('menu.groups.usage.title', args: {'name': 'Coffee beans'})),
      findsOneWidget,
    );
    // The row shows no empty Arabic line either.
    expect(
      find.descendant(of: rowOf(servingId), matching: find.text('')),
      findsNothing,
    );
  });

  testWidgets('MENU-GRP-016 phone: badges, "Used on" and actions flow under '
      'the name', (tester) async {
    final h = await pumpGroups(tester, size: DashSize.phone);
    final name = tester.getTopLeft(textIn(rowOf(milkId), 'Milk')).dy;
    final badge = tester.getTopLeft(textIn(rowOf(milkId), 'Pick up to 1')).dy;
    final used = tester.getTopLeft(textIn(rowOf(milkId), 'Used on 15 items'));
    expect(badge, greaterThan(name));
    expect(used.dy, greaterThan(name));
    expect(labelIn(rowOf(milkId), 'Delete'), findsOneWidget);
    await h.shot('groups/phone-rows');
  });
}

/// Drops every group (the org has none yet).
void registerNothing(MockDb db) {
  db[MenuTables.groups].clear();
  db[MenuTables.groupLinks].clear();
}
