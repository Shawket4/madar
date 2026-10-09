// `/settings/delivery-zones` Delivery zones and the zone dialog, driven
// through the real app shell (SET-DZN-001..022).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/delivery/delivery_data.dart';
import 'package:dashboard_setup/src/delivery/delivery_zones_page.dart';
import 'package:dashboard_setup/src/delivery/zone_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'support.dart';

final String _helio = atBranch(SeedIds.heliopolis);
final String _maadi = atBranch(SeedIds.maadi);
final String _newCairo = atBranch(SeedIds.newCairo);
final String _zamalek = atBranch(SeedIds.zamalek);

Future<DashHarness> _pump(
  WidgetTester tester, {
  String query = '',
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  ({MockServer server, MockDb db})? backend,
}) => pumpDelivery(
  tester,
  path: zonesPath,
  query: query,
  persona: persona,
  size: size,
  locale: locale,
  backend: backend,
);

/// The rings the table shows, in order: (number, name).
List<(int, String)> _rings(WidgetTester tester) => [
  for (final c in tester.widgetList<ZoneCell>(inZones(find.byType(ZoneCell))))
    (c.zone.number, c.zone.zone.name),
];

DashDataTable<NumberedZone> _table(WidgetTester tester) =>
    tester.widget(inZones(find.byType(DashDataTable<NumberedZone>)));

Finder _dialog() => find.byType(ZoneDialog);

void main() {
  group('the table', () {
    testWidgets('SET-DZN-001 the pane header and its New zone action', (
      tester,
    ) async {
      final h = await _pump(tester, query: _helio);
      expect(inZones(find.text('Delivery zones')), findsOneWidget);
      expect(
        inZones(find.text(h.t('delivery.zonesSubtitle'))),
        findsOneWidget,
      );
      expect(inZones(byKey('dzn-new')), findsOneWidget);
      expect(
        tester.widget<DashButton>(inZones(byKey('dzn-new'))).label,
        'New zone',
      );
    });

    testWidgets('SET-DZN-002 no branch: the pick-a-branch state, no New '
        'zone, nothing read', (tester) async {
      final h = await _pump(tester);
      expect(
        inZones(
          find.text(
            'Select a branch in the top bar to manage its delivery zones',
          ),
        ),
        findsOneWidget,
      );
      expect(inZones(byKey('dzn-new')), findsNothing);
      expect(h.server.callsTo(DeliveryRoutes.zones), isEmpty);
    });

    testWidgets('SET-DZN-003 loading: the table\'s skeleton, then the rings',
        (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', DeliveryRoutes.zones);
      final h = await _pump(tester, query: _helio, backend: m);
      expect(_table(tester).loading, isTrue);
      expect(inZones(find.text(h.t('delivery.noZones'))), findsNothing);
      gate.release();
      await h.settle();
      expect(_table(tester).loading, isFalse);
      expect(
        h.server.callsTo(DeliveryRoutes.zones).single.query['branch_id'],
        [SeedIds.heliopolis],
      );
      expect(_rings(tester), hasLength(3));
    });

    testWidgets('SET-DZN-004 a failed read: "Couldn\'t load this", the '
        'server\'s words and Retry, which asks again', (tester) async {
      final m = setupMockServer();
      final failure = MockResponse.error(500, 'Database unavailable');
      m.server.fail('GET', DeliveryRoutes.zones, failure);
      final h = await _pump(tester, query: _helio, backend: m);
      expect(inZones(find.text("Couldn't load this")), findsOneWidget);
      expect(inZones(find.text(h.refusalWords(failure))), findsOneWidget);
      expect(inZones(find.text(h.t('delivery.noZones'))), findsNothing);
      await h.tap(inZones(find.text('Retry')));
      expect(h.server.callsTo(DeliveryRoutes.zones), hasLength(2));
      expect(_rings(tester), hasLength(3));
    });

    testWidgets('SET-DZN-004 refused (no delivery.settings.read): the error '
        'state says the server\'s refusal', (tester) async {
      final h = await _pump(
        tester,
        query: _maadi,
        persona: Persona.limited,
      );
      expect(
        inZones(
          find.text(
            h.refusalWords(MockResponse.denied('delivery.settings.read')),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SET-DZN-005 closest ring first, numbered 1, 2, 3', (
      tester,
    ) async {
      final m = setupMockServer();
      // Stored out of order: the page sorts, whatever the answer's order.
      m.db[DeliverySeed.zonesTable].insert({
        'branch_id': SeedIds.heliopolis,
        'name': 'Nozha',
        'name_translations': <String, Object?>{},
        'max_road_distance_meters': 1000,
        'fee': 1000,
        'is_active': true,
      });
      await _pump(tester, query: _helio, backend: m);
      expect(_rings(tester), [
        (1, 'Nozha'),
        (2, 'Zone 1'),
        (3, 'Zone 2'),
        (4, 'Korba & Merghany'),
      ]);
    });

    testWidgets('SET-DZN-006 the Zone cell: badge, "Zone N", and the own '
        'name only when it differs', (tester) async {
      await _pump(tester, query: _helio);
      final third = find.byWidgetPredicate(
        (w) => w is ZoneCell && w.zone.number == 3,
      );
      expect(
        find.descendant(of: third, matching: find.text('Zone 3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: third, matching: find.text('Korba & Merghany')),
        findsOneWidget,
      );
      expect(find.descendant(of: third, matching: find.text('3')),
          findsOneWidget);
      final first = find.byWidgetPredicate(
        (w) => w is ZoneCell && w.zone.number == 1,
      );
      expect(
        find.descendant(of: first, matching: find.text('Zone 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: first, matching: find.byType(Text)),
        findsNWidgets(2),
        reason: 'the badge and "Zone 1", no name line',
      );
    });

    testWidgets('SET-DZN-007 Max distance: metres in km, one decimal at most',
        (tester) async {
      await _pump(tester, query: _newCairo);
      expect(inZones(find.text('MAX DISTANCE')), findsOneWidget);
      for (final w in ['3 km', '5.5 km', '8 km']) {
        expect(inZones(find.text(dashFigure(w))), findsOneWidget, reason: w);
      }
    });

    testWidgets('SET-DZN-008 Fee as money; Status Active / Inactive', (
      tester,
    ) async {
      await _pump(tester, query: _maadi);
      for (final w in ['FEE', 'STATUS']) {
        expect(inZones(find.text(w)), findsOneWidget, reason: w);
      }
      for (final w in ['EGP 10.00', 'EGP 20.00', 'EGP 30.00']) {
        expect(inZones(find.text(dashFigure(w))), findsOneWidget, reason: w);
      }
      final pills = tester
          .widgetList<DashStatusPill>(inZones(find.byType(DashStatusPill)))
          .toList();
      expect([for (final p in pills) p.label], ['Active', 'Active', 'Inactive']);
      expect([for (final p in pills) p.tone], [
        DashTone.success,
        DashTone.success,
        DashTone.neutral,
      ]);
    });

    testWidgets('SET-DZN-009 no search, no Columns menu; ten a page with the '
        'pager past ten', (tester) async {
      final m = setupMockServer();
      for (var i = 1; i <= 9; i++) {
        m.db[DeliverySeed.zonesTable].insert({
          'branch_id': SeedIds.heliopolis,
          'name': 'Ring $i',
          'name_translations': <String, Object?>{},
          'max_road_distance_meters': 6000 + i * 500,
          'fee': 4000 + i * 100,
          'is_active': true,
        });
      }
      final h = await _pump(tester, query: _helio, backend: m);
      expect(_table(tester).hideViewOptions, isTrue);
      expect(_table(tester).searchPlaceholder, isNull);
      expect(_rings(tester), hasLength(10));
      final page = h.t('common.page', args: {'current': 1, 'total': 2});
      expect(inZones(find.text(page)), findsOneWidget);
      final next = inZones(find.bySemanticsLabel(h.t('common.next')));
      await h.tap(next);
      expect(_rings(tester), [(11, 'Ring 8'), (12, 'Ring 9')]);
    });

    testWidgets('SET-DZN-010 no rings: "No delivery zones yet", its hint and '
        'a New zone button that opens the dialog', (tester) async {
      final h = await _pump(tester, query: _zamalek);
      expect(inZones(find.text('No delivery zones yet')), findsOneWidget);
      expect(
        inZones(
          find.text('Add rings from closest to farthest to quote delivery fees.'),
        ),
        findsOneWidget,
      );
      await h.tap(inZones(byKey('dzn-empty-new')));
      expect(_dialog(), findsOneWidget);
      expect(inDialog(find.text('New zone')), findsOneWidget);
    });

    testWidgets('SET-DZN-011 a row tap opens its editor; so does its pencil',
        (tester) async {
      final h = await _pump(tester, query: _helio);
      await h.tap(inZones(find.text('Korba & Merghany')));
      expect(inDialog(find.text('Edit zone')), findsOneWidget);
      expect(fieldText(tester, 'dzn-name'), 'Korba & Merghany');
      await h.tap(inDialog(byKey('dzn-cancel')));
      expect(_dialog(), findsNothing);
      final id = DeliverySeed.zoneId('heliopolis', 1);
      final pencil = inZones(byKey('dzn-edit-$id'));
      expect(
        tester.widget<DashIconButton>(pencil).semanticLabel,
        'Edit',
      );
      await h.tap(pencil);
      expect(fieldText(tester, 'dzn-name'), 'Zone 1');
      await h.tap(inDialog(byKey('dzn-cancel')));
    });

    testWidgets('SET-DZN-012 the trash asks first, naming the zone by its '
        'stored name; destructive Delete', (tester) async {
      final h = await _pump(tester, query: _helio);
      final id = DeliverySeed.zoneId('heliopolis', 3);
      final trash = tester.widget<DashIconButton>(
        inZones(byKey('dzn-delete-$id')),
      );
      expect(trash.semanticLabel, 'Delete');
      await h.tap(inZones(byKey('dzn-delete-$id')));
      final confirm = find.byType(DashConfirmDialog);
      expect(
        tester.widget<DashConfirmDialog>(confirm).title,
        'Delete the Korba & Merghany zone?',
      );
      expect(
        tester.widget<DashConfirmDialog>(confirm).description,
        h.t('delivery.deleteZoneHint'),
      );
      expect(tester.widget<DashConfirmDialog>(confirm).destructive, isTrue);
      await h.tap(
        find.descendant(of: confirm, matching: find.text('Cancel')),
      );
      expect(countCalls(h, 'DELETE', DeliveryRoutes.zone), 0);
    });

    testWidgets('SET-DZN-013 confirmed: DELETE with the branch, toast, the '
        'list refetched without it', (tester) async {
      final h = await _pump(tester, query: _helio);
      final seen = watchInvalidations(h);
      final id = DeliverySeed.zoneId('heliopolis', 2);
      await h.tap(inZones(byKey('dzn-delete-$id')));
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      final call = h.server.callsTo(DeliveryRoutes.zone, method: 'DELETE').single;
      expect(call.path, '/delivery/zones/$id');
      expect(call.query['branch_id'], [SeedIds.heliopolis]);
      await h.expectToast('Zone deleted');
      expect(seen, [
        ['/delivery/zones'],
      ]);
      expect(_rings(tester), [(1, 'Zone 1'), (2, 'Korba & Merghany')]);
    });

    testWidgets('SET-DZN-013 a refused delete toasts the server\'s words', (
      tester,
    ) async {
      final m = setupMockServer();
      final h = await _pump(tester, query: _helio, backend: m);
      final denied = MockResponse.denied('delivery.settings.delete');
      m.server.fail('DELETE', DeliveryRoutes.zone, denied);
      final id = DeliverySeed.zoneId('heliopolis', 2);
      await h.tap(inZones(byKey('dzn-delete-$id')));
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      await h.expectToast(h.refusalWords(denied));
      expect(_rings(tester), hasLength(3));
    });

    testWidgets('SET-DZN-020 phone: one card per ring with its figures; a '
        'card tap opens the editor full screen', (tester) async {
      final h = await _pump(tester, query: _helio, size: DashSize.phone);
      expect(_rings(tester), hasLength(3));
      for (final w in ['Max distance', 'Fee', 'Status']) {
        expect(inZones(find.text(w)), findsWidgets, reason: w);
      }
      final id = DeliverySeed.zoneId('heliopolis', 1);
      expect(inZones(byKey('dzn-edit-$id')), findsOneWidget);
      expect(inZones(byKey('dzn-delete-$id')), findsOneWidget);
      await h.tap(inZones(find.text('Korba & Merghany')));
      expect(inDialog(find.text('Edit zone')), findsOneWidget);
      expect(
        tester.getSize(_dialog()).width,
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
      );
    });

    testWidgets('SET-DZN-020 a Dawam-only org meets the module gate', (
      tester,
    ) async {
      final h = await _pump(tester, persona: Persona.dawamOnly);
      expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
      expect(h.server.callsTo(DeliveryRoutes.zones), isEmpty);
    });
  });

  group('the dialog', () {
    testWidgets('SET-DZN-014 New zone: title, subtitle, the defaults (km = '
        'farthest + 1, "Zone 4" placeholder, fee 0, active), Cancel closes',
        (tester) async {
      final h = await _pump(tester, query: _helio);
      await h.tap(inZones(byKey('dzn-new')));
      for (final w in [
        'New zone',
        'Define a delivery ring by its road-distance limit and flat fee.',
        'Zone name',
        'Leave blank to auto-name it by its order.',
        'Up to … km',
        'Road distance from the branch.',
        'Delivery fee (EGP)',
        'Flat fee for deliveries in this ring.',
        'Active',
        'Inactive zones are not used for quoting deliveries.',
        'Cancel',
        'Create',
      ]) {
        expect(inDialog(find.text(w)), findsOneWidget, reason: w);
      }
      expect(fieldText(tester, 'dzn-name'), '');
      expect(
        tester
            .widget<DashTextField>(inDialog(byKey('dzn-name')))
            .placeholder,
        'Zone 4',
      );
      expect(fieldText(tester, 'dzn-km'), '7');
      expect(fieldText(tester, 'dzn-fee'), '0');
      expect(
        tester.widget<DashSwitch>(inDialog(find.byType(DashSwitch))).value,
        isTrue,
      );
      await h.tap(inDialog(byKey('dzn-cancel')));
      expect(_dialog(), findsNothing);
      expect(countCalls(h, 'POST', DeliveryRoutes.zones), 0);
    });

    testWidgets('SET-DZN-014 no rings yet: the new zone starts at 1 km, '
        '"Zone 1"', (tester) async {
      final h = await _pump(tester, query: _zamalek);
      await h.tap(inZones(byKey('dzn-new')));
      expect(fieldText(tester, 'dzn-km'), '1');
      expect(
        tester.widget<DashTextField>(inDialog(byKey('dzn-name'))).placeholder,
        'Zone 1',
      );
    });

    testWidgets('SET-DZN-015 Edit zone: filled from the ring (m → km, '
        'piastres → EGP), Save', (tester) async {
      final h = await _pump(tester, query: _maadi);
      await h.tap(inZones(find.text('Degla & Zahraa')));
      expect(inDialog(find.text('Edit zone')), findsOneWidget);
      expect(fieldText(tester, 'dzn-km'), '5');
      expect(fieldText(tester, 'dzn-fee'), '30');
      expect(
        tester.widget<DashSwitch>(inDialog(find.byType(DashSwitch))).value,
        isFalse,
      );
      expect(inDialog(find.text('Save')), findsOneWidget);
    });

    testWidgets('SET-DZN-016 a distance of 0 and a negative fee are refused '
        'in the web\'s words; nothing sent', (tester) async {
      final h = await _pump(tester, query: _helio);
      await h.tap(inZones(byKey('dzn-new')));
      await typeIn(h, 'dzn-km', '0');
      await typeIn(h, 'dzn-fee', '-2');
      await h.tap(inDialog(byKey('dzn-save')));
      expect(inDialog(find.text('Distance must be greater than 0')),
          findsOneWidget);
      expect(inDialog(find.text('Fee cannot be negative')), findsOneWidget);
      await typeIn(h, 'dzn-km', '');
      await h.tap(inDialog(byKey('dzn-save')));
      expect(inDialog(find.text('Distance must be greater than 0')),
          findsOneWidget);
      expect(countCalls(h, 'POST', DeliveryRoutes.zones), 0);
    });

    testWidgets('SET-DZN-017 Create: the body (blank name → "Zone 4", km → '
        'm, EGP → piastres), toast, refetch, closed, the new ring listed', (
      tester,
    ) async {
      final h = await _pump(tester, query: _helio);
      final seen = watchInvalidations(h);
      await h.tap(inZones(byKey('dzn-new')));
      await typeIn(h, 'dzn-km', '7.25');
      await typeIn(h, 'dzn-fee', '42.5');
      await h.tap(inDialog(byKey('dzn-save')));
      expect(lastBody(h, 'POST', DeliveryRoutes.zones), {
        'branch_id': SeedIds.heliopolis,
        'name': 'Zone 4',
        'name_translations': <String, Object?>{},
        'max_road_distance_meters': 7250,
        'fee': 4250,
        'is_active': true,
      });
      await h.expectToast('Zone created');
      expect(_dialog(), findsNothing);
      expect(seen, [
        ['/delivery/zones'],
      ]);
      expect(_rings(tester).last, (4, 'Zone 4'));
      expect(inZones(find.text(dashFigure('7.3 km'))), findsOneWidget);
    });

    testWidgets('SET-DZN-017 a typed name is trimmed; switched off it is '
        'created inactive', (tester) async {
      final h = await _pump(tester, query: _zamalek);
      await h.tap(inZones(byKey('dzn-new')));
      await h.enterText(byKey('dzn-name'), '  Gezira  ');
      await h.tap(inDialog(find.byType(DashSwitch)));
      await h.tap(inDialog(byKey('dzn-save')));
      final body = lastBody(h, 'POST', DeliveryRoutes.zones);
      expect(body['name'], 'Gezira');
      expect(body['is_active'], false);
      expect(body['max_road_distance_meters'], 1000);
      await h.expectToast('Zone created');
    });

    testWidgets('SET-DZN-017 Enter in the name field submits the form', (
      tester,
    ) async {
      final h = await _pump(tester, query: _zamalek);
      await h.tap(inZones(byKey('dzn-new')));
      await typeIn(h, 'dzn-name', 'Gezira');
      expect(lastBody(h, 'POST', DeliveryRoutes.zones)['name'], 'Gezira');
      await h.expectToast('Zone created');
      expect(_dialog(), findsNothing);
    });

    testWidgets('SET-DZN-018 Update: the same body to the ring, toast, '
        'refetch, closed', (tester) async {
      final h = await _pump(tester, query: _maadi);
      final seen = watchInvalidations(h);
      await h.tap(inZones(find.text('Degla & Zahraa')));
      await typeIn(h, 'dzn-fee', '35');
      await h.tap(inDialog(find.byType(DashSwitch)));
      await h.tap(inDialog(byKey('dzn-save')));
      final id = DeliverySeed.zoneId('maadi', 3);
      final call = h.server.callsTo(DeliveryRoutes.zone, method: 'PATCH').single;
      expect(call.path, '/delivery/zones/$id');
      expect(lastBody(h, 'PATCH', DeliveryRoutes.zone), {
        'branch_id': SeedIds.maadi,
        'name': 'Degla & Zahraa',
        'name_translations': <String, Object?>{},
        'max_road_distance_meters': 5000,
        'fee': 3500,
        'is_active': true,
      });
      await h.expectToast('Zone updated');
      expect(_dialog(), findsNothing);
      expect(seen, [
        ['/delivery/zones'],
      ]);
      expect(inZones(find.text(dashFigure('EGP 35.00'))), findsOneWidget);
    });

    testWidgets('SET-DZN-019 a ring at that distance exists (409): its own '
        'words; the dialog stays open', (tester) async {
      final h = await _pump(tester, query: _helio);
      await h.tap(inZones(byKey('dzn-new')));
      await typeIn(h, 'dzn-km', '4');
      await h.tap(inDialog(byKey('dzn-save')));
      expect(
        h.server.callsTo(DeliveryRoutes.zones, method: 'POST').single.status,
        409,
      );
      await h.expectToast('A zone with this distance already exists');
      expect(_dialog(), findsOneWidget);
      expect(
        tester.widget<DashButton>(inDialog(byKey('dzn-save'))).loading,
        isFalse,
      );
    });

    testWidgets('SET-DZN-019 any other failure: the server\'s words; the '
        'dialog stays open', (tester) async {
      final m = setupMockServer();
      final h = await _pump(tester, query: _helio, backend: m);
      final denied = MockResponse.denied('delivery.settings.create');
      m.server.fail('POST', DeliveryRoutes.zones, denied);
      await h.tap(inZones(byKey('dzn-new')));
      await h.tap(inDialog(byKey('dzn-save')));
      await h.expectToast(h.refusalWords(denied));
      expect(_dialog(), findsOneWidget);
    });

    testWidgets('SET-DZN-021 clearing a ring\'s name saves "Zone <count + '
        '1>", not its ring number', (tester) async {
      final h = await _pump(tester, query: _helio);
      await h.tap(inZones(find.text('Korba & Merghany')));
      expect(
        tester.widget<DashTextField>(inDialog(byKey('dzn-name'))).placeholder,
        'Zone 4',
      );
      await h.enterText(byKey('dzn-name'), '');
      await h.tap(inDialog(byKey('dzn-save')));
      expect(lastBody(h, 'PATCH', DeliveryRoutes.zone)['name'], 'Zone 4');
      await h.expectToast('Zone updated');
    });

    testWidgets('SET-DZN-021 (divergence) an edit sends the ring\'s own '
        'translations back instead of wiping them', (tester) async {
      final m = setupMockServer();
      final id = DeliverySeed.zoneId('heliopolis', 3);
      m.db[DeliverySeed.zonesTable].find(id)!['name_translations'] = {
        'ar': 'كوربة والميرغني',
      };
      final h = await _pump(tester, query: _helio, backend: m);
      await h.tap(inZones(find.text('Korba & Merghany')));
      await h.tap(inDialog(byKey('dzn-save')));
      expect(lastBody(h, 'PATCH', DeliveryRoutes.zone)['name_translations'], {
        'ar': 'كوربة والميرغني',
      });
      await h.expectToast('Zone updated');
    });

    testWidgets('SET-DZN-022 km and fee side by side on a phone too; the '
        'dialog is a full-screen sheet there', (tester) async {
      final h = await _pump(tester, query: _helio, size: DashSize.phone);
      await h.tap(inZones(byKey('dzn-new')));
      expect(
        tester.getTopLeft(byKey('dzn-km')).dy,
        tester.getTopLeft(byKey('dzn-fee')).dy,
      );
    });

    testWidgets('SET-DZN-022 every open starts afresh: after a create the '
        'next new zone defaults past it', (tester) async {
      final h = await _pump(tester, query: _helio);
      await h.tap(inZones(byKey('dzn-new')));
      await h.enterText(byKey('dzn-name'), 'Far');
      await h.tap(inDialog(byKey('dzn-save')));
      await h.flushTimers();
      await h.tap(inZones(byKey('dzn-new')));
      expect(fieldText(tester, 'dzn-name'), '');
      expect(fieldText(tester, 'dzn-km'), '8');
      expect(
        tester.widget<DashTextField>(inDialog(byKey('dzn-name'))).placeholder,
        'Zone 5',
      );
    });

    testWidgets('SET-DZN-022 an open editor follows a refresh until the '
        'person types', (tester) async {
      final m = setupMockServer();
      final h = await _pump(tester, query: _maadi, backend: m);
      await h.tap(inZones(find.text('Degla & Zahraa')));
      final id = DeliverySeed.zoneId('maadi', 3);
      m.db[DeliverySeed.zonesTable].find(id)!['fee'] = 3200;
      h.container.read(realtimeBusProvider).invalidate(const [
        '/delivery/zones',
      ]);
      await h.settle();
      expect(fieldText(tester, 'dzn-fee'), '32');
      await typeIn(h, 'dzn-fee', '33');
      m.db[DeliverySeed.zonesTable].find(id)!['fee'] = 3400;
      h.container.read(realtimeBusProvider).invalidate(const [
        '/delivery/zones',
      ]);
      await h.settle();
      expect(fieldText(tester, 'dzn-fee'), '33');
    });
  });

  testWidgets('intent: pointing at a ring or New zone warms the editor\'s '
      'read; opening it asks the server nothing more', (tester) async {
    final h = await _pump(tester, query: _helio);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final reads = h.server.callsTo(DeliveryRoutes.zones).length;
    final row = inZones(find.text('Korba & Merghany'));
    await mouse.moveTo(tester.getCenter(row));
    await h.settle();
    await h.tap(row);
    expect(_dialog(), findsOneWidget);
    expect(h.server.callsTo(DeliveryRoutes.zones).length, reads);
    await h.tap(inDialog(byKey('dzn-cancel')));
    final pencil = inZones(byKey('dzn-edit-${DeliverySeed.zoneId('heliopolis', 1)}'));
    await mouse.moveTo(tester.getCenter(pencil));
    await h.settle();
    await h.tap(pencil);
    expect(_dialog(), findsOneWidget);
    expect(h.server.callsTo(DeliveryRoutes.zones).length, reads);
    await h.tap(inDialog(byKey('dzn-cancel')));
    await mouse.moveTo(tester.getCenter(inZones(byKey('dzn-new'))));
    await h.settle();
    await h.tap(inZones(byKey('dzn-new')));
    expect(_dialog(), findsOneWidget);
    expect(h.server.callsTo(DeliveryRoutes.zones).length, reads);
  });

  testWidgets('intent: the empty state\'s New zone warms the editor\'s read',
      (tester) async {
    final h = await _pump(tester, query: _zamalek);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final reads = h.server.callsTo(DeliveryRoutes.zones).length;
    final button = inZones(byKey('dzn-empty-new'));
    await mouse.moveTo(tester.getCenter(button));
    await h.settle();
    await h.tap(button);
    expect(_dialog(), findsOneWidget);
    expect(h.server.callsTo(DeliveryRoutes.zones).length, reads);
  });
}
