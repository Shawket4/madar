// `/settings/kitchen-stations`, driven through the real app shell
// (SET-KST-001..024).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/brand_appearance/settings_shell.dart';
import 'package:dashboard_setup/src/kitchen/kitchen_stations_page.dart';
import 'package:dashboard_setup/src/kitchen/station_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_support.dart';

Finder _dialog() => find.byType(StationDialog);
Finder _inDialog(Finder f) => find.descendant(of: _dialog(), matching: f);
Finder _table() => inStations(byKey('kitchen-stations-table'));
Finder _inTable(Finder f) => find.descendant(of: _table(), matching: f);
Finder _bar() => inStations(byKey('kitchen-mode-bar'));
Finder _inBar(Finder f) => find.descendant(of: _bar(), matching: f);

/// The mode select's value.
String? _mode(WidgetTester tester) =>
    tester.widget<DashSelect<String>>(byKey('kitchen-mode')).value;

/// Picks [option] in the mode select.
Future<void> _pickMode(DashHarness h, String option) async {
  await h.tap(byKey('kitchen-mode'));
  await h.tap(top(option));
}

Map<String, Object?> _body(MockCall c) => c.body! as Map<String, Object?>;

/// A station row as stored.
MockRow _station(MockDb db, String id) => db[KitchenSeed.stationsTable].find(id)!;

void main() {
  group('header and branch', () {
    testWidgets('SET-KST-001 title, subtitle and "New station" with a branch', (
      tester,
    ) async {
      final h = await pumpKitchen(tester);
      expect(inStations(find.text('Kitchen stations')), findsOneWidget);
      expect(
        inStations(find.text(h.t('kitchen.stationsSubtitle'))),
        findsOneWidget,
      );
      expect(inStations(byKey('kitchen-new-station')), findsOneWidget);
      expect(
        h.server.callsTo(KitchenRoutes.stations).single.query['branch_id'],
        [SeedIds.zamalek],
      );
    });

    testWidgets('SET-KST-002 "All branches": "Select a branch…", no New '
        'station, nothing read', (tester) async {
      final h = await pumpKitchen(tester, query: '');
      expect(
        inStations(
          find.text('Select a branch in the top bar to manage its kitchen'),
        ),
        findsOneWidget,
      );
      expect(inStations(byKey('kitchen-new-station')), findsNothing);
      expect(inStations(byKey('kitchen-mode-bar')), findsNothing);
      expect(h.server.callsTo(KitchenRoutes.stations), isEmpty);
      expect(h.server.callsTo(KitchenRoutes.routingMode), isEmpty);
    });

    testWidgets('SET-KST-002 a Dawam-only org meets the module gate; '
        'nothing read', (tester) async {
      final h = await pumpKitchen(
        tester,
        query: '',
        persona: Persona.dawamOnly,
      );
      expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
      expect(find.byType(KitchenStationsPage), findsNothing);
      expect(h.server.callsTo(KitchenRoutes.stations), isEmpty);
    });
  });

  group('routing mode', () {
    testWidgets('SET-KST-003 "Where tickets show" and its hint', (
      tester,
    ) async {
      final h = await pumpKitchen(tester);
      expect(_inBar(find.text('Where tickets show')), findsOneWidget);
      expect(_inBar(find.text(h.t('kitchen.routingModeHint'))), findsOneWidget);
      expect(
        h.server.callsTo(KitchenRoutes.routingMode).single.query['branch_id'],
        [SeedIds.zamalek],
      );
    });

    for (final (query, pill) in [
      (zamalek, 'Now: KDS screens'),
      (heliopolis, 'Now: Both'),
      (maadi, 'Now: Till queue'),
      (atBranch(SeedIds.newCairo), 'Now: Off (no kitchen)'),
    ]) {
      testWidgets('SET-KST-004 the effective pill: $pill', (tester) async {
        await pumpKitchen(tester, query: query);
        final p = tester.widget<DashStatusPill>(
          _inBar(byKey('kitchen-effective')),
        );
        expect(p.label, pill);
        expect(p.tone, DashTone.info);
      });
    }

    testWidgets('SET-KST-004 an effective mode with no words shows as sent', (
      tester,
    ) async {
      final m = setupMockServer();
      m.server.fail(
        'GET',
        KitchenRoutes.routingMode,
        MockResponse.ok({'mode': null, 'effective': 'printer'}),
        times: null,
      );
      await pumpKitchen(tester, backend: m);
      expect(
        tester
            .widget<DashStatusPill>(_inBar(byKey('kitchen-effective')))
            .label,
        'Now: printer',
      );
    });

    testWidgets('SET-KST-005 the select: Auto (stored null), KDS screens, POS '
        'queue, Both, Off; the stored mode shown', (tester) async {
      final h = await pumpKitchen(tester);
      expect(_mode(tester), 'auto');
      final select = tester.widget<DashSelect<String>>(byKey('kitchen-mode'));
      expect([for (final o in select.options) o.label], [
        'Auto',
        'KDS screens',
        'POS queue',
        'Both',
        'Off (no kitchen)',
      ]);
      expect(select.width, kitchenSelectWidth);
      await h.go('$stationsPath$heliopolis');
      expect(_mode(tester), 'both');
    });

    testWidgets('SET-KST-006 choosing a mode saves at once, toasts and '
        'refetches the mode', (tester) async {
      final h = await pumpKitchen(tester);
      final seen = watchInvalidations(h);
      await _pickMode(h, 'Both');
      final put = h.server.callsTo(KitchenRoutes.routingMode, method: 'PUT');
      expect(_body(put.single), {'branch_id': SeedIds.zamalek, 'mode': 'both'});
      await h.expectToast('Routing mode updated');
      expect(seen, [
        ['/kitchen/routes', '/kitchen/routing-mode'],
      ]);
      expect(
        h.server.callsTo(KitchenRoutes.routingMode, method: 'GET'),
        hasLength(2),
      );
      expect(_mode(tester), 'both');
      expect(
        tester.widget<DashStatusPill>(_inBar(byKey('kitchen-effective'))).label,
        'Now: Both',
      );
    });

    testWidgets('SET-KST-006 Auto sends an explicit null mode', (tester) async {
      final h = await pumpKitchen(tester, query: heliopolis);
      await _pickMode(h, 'Auto');
      final put = h.server.callsTo(KitchenRoutes.routingMode, method: 'PUT');
      final body = _body(put.single);
      expect(body.containsKey('mode'), isTrue);
      expect(body['mode'], isNull);
      await h.expectToast('Routing mode updated');
      expect(_mode(tester), 'auto');
      expect(
        tester.widget<DashStatusPill>(_inBar(byKey('kitchen-effective'))).label,
        'Now: KDS screens',
      );
    });

    testWidgets('SET-KST-006 a failed save toasts the server\'s words and '
        'keeps the mode', (tester) async {
      final m = setupMockServer();
      final refusal = MockResponse.badRequest(KitchenRefusals.badMode);
      m.server.fail('PUT', KitchenRoutes.routingMode, refusal);
      final h = await pumpKitchen(tester, backend: m);
      await _pickMode(h, 'KDS screens');
      await h.expectToast(h.refusalWords(refusal));
      expect(_mode(tester), 'auto');
      expect(
        h.server.callsTo(KitchenRoutes.routingMode, method: 'GET'),
        hasLength(1),
      );
    });

    testWidgets('SET-KST-023 while the mode loads (or when it failed) the '
        'select reads Auto, no pill; choosing still saves', (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', KitchenRoutes.routingMode);
      final h = await pumpKitchen(tester, backend: m);
      expect(_mode(tester), 'auto');
      expect(_inBar(byKey('kitchen-effective')), findsNothing);
      expect(_inTable(find.text('Bar')), findsOneWidget);
      gate.release();
      await h.settle();
      expect(_inBar(byKey('kitchen-effective')), findsOneWidget);

      final f = setupMockServer();
      f.server.fail(
        'GET',
        KitchenRoutes.routingMode,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h2 = await pumpKitchen(tester, backend: f);
      expect(_mode(tester), 'auto');
      expect(_inBar(byKey('kitchen-effective')), findsNothing);
      expect(_inBar(find.byType(DashErrorState)), findsNothing);
      await _pickMode(h2, 'Off (no kitchen)');
      expect(
        _body(
          h2.server
              .callsTo(KitchenRoutes.routingMode, method: 'PUT')
              .single,
        )['mode'],
        'off',
      );
      await h2.expectToast('Routing mode updated');
    });
  });

  group('table', () {
    testWidgets('SET-KST-007 Name (+ Default), Printer, Status in the '
        'server\'s order', (tester) async {
      await pumpKitchen(tester);
      final rows = [
        for (final e in _inTable(find.byType(StationPrinter)).evaluate())
          (e.widget as StationPrinter).station.name,
      ];
      expect(rows, ['Bar', 'Kitchen', 'Pastry']);
      final table = tester.widget<DashDataTable<KitchenStation>>(
        inStations(find.byType(DashDataTable<KitchenStation>)),
      );
      expect([for (final c in table.columns) c.label], [
        'Name',
        'Printer',
        'Status',
      ]);
      expect(table.hideViewOptions, isTrue);
      final pill = tester.widget<DashStatusPill>(
        _inTable(byKey('kitchen-default-${stationId('zamalek', 'bar')}')),
      );
      expect(pill.label, 'Default');
      expect(pill.tone, DashTone.accent);
      expect(pill.icon, 'star');
      expect(
        _inTable(byKey('kitchen-default-${stationId('zamalek', 'kitchen')}')),
        findsNothing,
      );
      expect(
        _inTable(find.textContaining('Epson · ', findRichText: true)),
        findsOneWidget,
      );
      expect(
        _inTable(find.textContaining('192.168.10.22', findRichText: true)),
        findsOneWidget,
      );
      expect(_inTable(find.text('—')), findsOneWidget);
      expect(_inTable(find.text('Active')), findsNWidgets(2));
      expect(_inTable(find.text('Inactive')), findsOneWidget);
    });

    testWidgets('SET-KST-008 search over the name and the printer model', (
      tester,
    ) async {
      final h = await pumpKitchen(tester);
      Finder field() =>
          _inTable(find.byType(DashSearchInput)).first;
      await h.enterText(field(), 'kit');
      await h.flushTimers();
      expect(_inTable(find.text('Kitchen')), findsOneWidget);
      expect(_inTable(find.text('Bar')), findsNothing);
      await h.enterText(field(), 'EPSON');
      await h.flushTimers();
      expect(_inTable(find.text('Bar')), findsOneWidget);
      expect(_inTable(find.text('Kitchen')), findsNothing);
      // The address is not searched (the column's value is the model).
      await h.enterText(field(), '192.168');
      await h.flushTimers();
      expect(_inTable(find.byType(StationPrinter)), findsNothing);
    });

    testWidgets('SET-KST-008 ten a page, with a pager past ten', (
      tester,
    ) async {
      final m = setupMockServer();
      for (var i = 1; i <= 9; i++) {
        m.db[KitchenSeed.stationsTable].insert({
          'org_id': SeedIds.sabahOrg,
          'branch_id': SeedIds.zamalek,
          'name': 'Line $i',
          'name_translations': const <String, Object?>{},
          'sort_order': 3,
          'is_default': false,
          'is_active': true,
        });
      }
      final h = await pumpKitchen(tester, backend: m);
      expect(_inTable(find.byType(StationPrinter)), findsNWidgets(10));
      expect(_inTable(find.text('Page 1 of 2')), findsOneWidget);
      await h.tap(_inTable(find.bySemanticsLabel('Next')));
      expect(_inTable(find.byType(StationPrinter)), findsNWidgets(2));
    });

    testWidgets('SET-KST-009 loading: skeleton rows until the list lands', (
      tester,
    ) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', KitchenRoutes.stations);
      final h = await pumpKitchen(tester, backend: m);
      expect(
        tester
            .widget<DashDataTable<KitchenStation>>(
              inStations(find.byType(DashDataTable<KitchenStation>)),
            )
            .loading,
        isTrue,
      );
      expect(_inTable(find.text('No stations yet')), findsNothing);
      gate.release();
      await h.settle();
      expect(_inTable(find.byType(StationPrinter)), findsNWidgets(3));
    });

    testWidgets('SET-KST-009 a failed read: "Couldn\'t load this", the '
        'message and Retry, which reads the list again', (tester) async {
      final m = setupMockServer();
      final boom = MockResponse.error(500, 'Database unavailable');
      m.server.fail('GET', KitchenRoutes.stations, boom);
      final h = await pumpKitchen(tester, backend: m);
      expect(_inTable(find.text("Couldn't load this")), findsOneWidget);
      expect(_inTable(find.text(h.refusalWords(boom))), findsOneWidget);
      expect(_inTable(find.text('No stations yet')), findsNothing);
      final modeReads = h.server.callsTo(KitchenRoutes.routingMode).length;
      await h.tap(_inTable(find.text('Retry')));
      expect(h.server.callsTo(KitchenRoutes.stations), hasLength(2));
      expect(h.server.callsTo(KitchenRoutes.routingMode), hasLength(modeReads));
      expect(_inTable(find.byType(StationPrinter)), findsNWidgets(3));
    });

    testWidgets('SET-KST-010 no stations: "No stations yet", the hint and '
        'New station', (tester) async {
      final h = await pumpKitchen(tester, query: maadi);
      final empty = _inTable(byKey('kitchen-no-stations'));
      expect(
        find.descendant(of: empty, matching: find.text('No stations yet')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: empty,
          matching: find.text(h.t('kitchen.noStationsHint')),
        ),
        findsOneWidget,
      );
      await h.tap(_inTable(byKey('kitchen-empty-new-station')));
      expect(_inDialog(find.text('New station')), findsOneWidget);
    });

    testWidgets('SET-KST-011 a row or its pencil opens the editor', (
      tester,
    ) async {
      final h = await pumpKitchen(tester);
      await h.tap(_inTable(find.text('Kitchen')));
      expect(_inDialog(find.text('Edit station')), findsOneWidget);
      expect(
        tester
            .widget<DashTextField>(_inDialog(byKey('station-name')))
            .value,
        'Kitchen',
      );
      await h.tap(_inDialog(byKey('station-cancel')));
      expect(_dialog(), findsNothing);
      final bar = stationId('zamalek', 'bar');
      final pencil = tester.widget<DashIconButton>(
        _inTable(byKey('kitchen-edit-$bar')),
      );
      expect(pencil.semanticLabel, 'Edit');
      await h.tap(_inTable(byKey('kitchen-edit-$bar')));
      expect(
        tester
            .widget<DashTextField>(_inDialog(byKey('station-name')))
            .value,
        'Bar',
      );
    });
  });

  group('delete', () {
    testWidgets('SET-KST-012 the trash asks first; Cancel keeps it', (
      tester,
    ) async {
      final h = await pumpKitchen(tester);
      final kitchen = stationId('zamalek', 'kitchen');
      expect(
        tester
            .widget<DashIconButton>(_inTable(byKey('kitchen-delete-$kitchen')))
            .semanticLabel,
        'Delete',
      );
      await h.tap(_inTable(byKey('kitchen-delete-$kitchen')));
      final confirm = find.byType(DashConfirmDialog);
      expect(
        find.descendant(of: confirm, matching: find.text('Delete "Kitchen"?')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: confirm,
          matching: find.text(h.t('kitchen.deleteStationConsequence')),
        ),
        findsOneWidget,
      );
      expect(tester.widget<DashConfirmDialog>(confirm).destructive, isTrue);
      await h.tap(find.descendant(of: confirm, matching: find.text('Cancel')));
      expect(h.server.callsTo(KitchenRoutes.station), isEmpty);
      expect(_inTable(find.text('Kitchen')), findsOneWidget);
    });

    testWidgets('SET-KST-013 Delete: the call, "Station deleted", the list '
        'read again', (tester) async {
      final h = await pumpKitchen(tester);
      final seen = watchInvalidations(h);
      final kitchen = stationId('zamalek', 'kitchen');
      await h.tap(_inTable(byKey('kitchen-delete-$kitchen')));
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      final del = h.server.callsTo(KitchenRoutes.station, method: 'DELETE');
      expect(del.single.path, '/kitchen/stations/$kitchen');
      await h.expectToast('Station deleted');
      expect(seen, [
        ['/kitchen/stations'],
      ]);
      expect(h.server.callsTo(KitchenRoutes.stations), hasLength(2));
      expect(_inTable(find.text('Kitchen')), findsNothing);
      expect(_station(h.db!, kitchen)['deleted_at'], isNotNull);
    });

    testWidgets('SET-KST-013 a failed delete toasts the server\'s words', (
      tester,
    ) async {
      final m = setupMockServer();
      final gone = MockResponse.notFound(KitchenRefusals.notFound);
      m.server.fail('DELETE', KitchenRoutes.station, gone);
      final h = await pumpKitchen(tester, backend: m);
      await h.tap(
        _inTable(byKey('kitchen-delete-${stationId('zamalek', 'bar')}')),
      );
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      await h.expectToast(h.refusalWords(gone));
      expect(h.server.callsTo(KitchenRoutes.stations), hasLength(1));
      expect(_inTable(find.text('Bar')), findsOneWidget);
    });
  });

  group('station dialog', () {
    testWidgets('SET-KST-014 New station: title, subtitle, Name with its '
        'placeholder; an empty name is required', (tester) async {
      final h = await pumpKitchen(tester);
      await h.tap(inStations(byKey('kitchen-new-station')));
      expect(_inDialog(find.text('New station')), findsOneWidget);
      expect(
        _inDialog(find.text(h.t('kitchen.stationSubtitle'))),
        findsOneWidget,
      );
      final name = tester.widget<DashTextField>(_inDialog(byKey('station-name')));
      expect(name.label, 'Name');
      expect(name.placeholder, 'Grill');
      await h.tap(_inDialog(byKey('station-save')));
      expect(_inDialog(find.text('This field is required')), findsOneWidget);
      expect(h.server.callsTo(KitchenRoutes.stations, method: 'POST'), isEmpty);
    });

    testWidgets('SET-KST-015 the printer block: Printer Model, None by '
        'default, then Star and Epson', (tester) async {
      final h = await pumpKitchen(tester);
      await h.tap(inStations(byKey('kitchen-new-station')));
      expect(_inDialog(find.text('Printer Configuration')), findsOneWidget);
      final brand = tester.widget<DashSelectField<String>>(
        _inDialog(byKey('station-brand')),
      );
      expect(brand.label, 'Printer Model');
      expect(brand.value, 'none');
      expect([for (final o in brand.options) o.label], [
        'None (no printer)',
        'Star',
        'Epson',
      ]);
      expect(_inDialog(byKey('station-ip')), findsNothing);
      expect(h.server.calls.where((c) => c.method != 'GET'), isEmpty);
    });

    testWidgets('SET-KST-016 a printer shows IP (192.168.1.50) and Port '
        '(9100) side by side; None hides them', (tester) async {
      final h = await pumpKitchen(tester);
      await h.tap(inStations(byKey('kitchen-new-station')));
      await h.tap(_inDialog(byKey('station-brand')));
      await h.tap(top('Epson'));
      final ip = tester.widget<DashTextField>(_inDialog(byKey('station-ip')));
      expect(ip.label, 'Printer IP');
      expect(ip.placeholder, '192.168.1.50');
      final port = tester.widget<DashTextField>(
        _inDialog(byKey('station-port')),
      );
      expect(port.label, 'Port');
      expect(port.value, '9100');
      expect(
        tester.getTopLeft(_inDialog(byKey('station-ip'))).dy,
        tester.getTopLeft(_inDialog(byKey('station-port'))).dy,
      );
      await h.tap(_inDialog(byKey('station-brand')));
      await h.tap(top('None (no printer)'));
      expect(_inDialog(byKey('station-ip')), findsNothing);
      expect(_inDialog(byKey('station-port')), findsNothing);
    });

    testWidgets('SET-KST-017 Default station (off, with its hint) and Active '
        '(on)', (tester) async {
      final h = await pumpKitchen(tester);
      await h.tap(inStations(byKey('kitchen-new-station')));
      expect(_inDialog(find.text('Default station')), findsOneWidget);
      expect(
        _inDialog(find.text(h.t('kitchen.defaultStationHint'))),
        findsOneWidget,
      );
      DashSwitch sw(String key) => tester.widget<DashSwitch>(
        find.descendant(
          of: _inDialog(byKey(key)),
          matching: find.byType(DashSwitch),
        ),
      );
      expect(sw('station-default').value, isFalse);
      expect(sw('station-active').value, isTrue);
      await h.tap(_inDialog(byKey('station-default')));
      expect(sw('station-default').value, isTrue);
    });

    testWidgets('SET-KST-018 create without a printer: the trimmed name, the '
        'branch, null printer fields; toast, refetch, close', (tester) async {
      final h = await pumpKitchen(tester);
      final seen = watchInvalidations(h);
      await h.tap(inStations(byKey('kitchen-new-station')));
      await h.enterText(_inDialog(byKey('station-name')), '  Grill  ');
      await h.tap(_inDialog(byKey('station-save')));
      final post = h.server.callsTo(KitchenRoutes.stations, method: 'POST');
      expect(_body(post.single), {
        'branch_id': SeedIds.zamalek,
        'name': 'Grill',
        'is_default': false,
        'is_active': true,
        'printer_brand': null,
        'printer_ip': null,
        'printer_port': null,
      });
      await h.expectToast('Station created');
      expect(seen, [
        ['/kitchen/stations'],
      ]);
      expect(_dialog(), findsNothing);
      expect(h.server.callsTo(KitchenRoutes.stations, method: 'GET'), hasLength(2));
      expect(_inTable(find.text('Grill')), findsOneWidget);
    });

    testWidgets('SET-KST-018 create with a printer and as the default: the '
        'old default gives the flag up', (tester) async {
      final h = await pumpKitchen(tester);
      await h.tap(inStations(byKey('kitchen-new-station')));
      await h.enterText(_inDialog(byKey('station-name')), 'Grill');
      await h.tap(_inDialog(byKey('station-brand')));
      await h.tap(top('Star'));
      await h.enterText(_inDialog(byKey('station-ip')), '192.168.10.30');
      await h.tap(_inDialog(byKey('station-default')));
      await h.tap(_inDialog(byKey('station-save')));
      final body = _body(
        h.server.callsTo(KitchenRoutes.stations, method: 'POST').single,
      );
      expect(body['printer_brand'], 'star');
      expect(body['printer_ip'], '192.168.10.30');
      expect(body['printer_port'], 9100);
      expect(body['is_default'], isTrue);
      await h.expectToast('Station created');
      expect(
        _inTable(byKey('kitchen-default-${stationId('zamalek', 'bar')}')),
        findsNothing,
      );
      expect(_inTable(find.text('Default')), findsOneWidget);
    });

    testWidgets('SET-KST-018 (divergence) an emptied port is sent as null, '
        'never 0; an empty IP as null', (tester) async {
      final h = await pumpKitchen(tester);
      await h.tap(inStations(byKey('kitchen-new-station')));
      await h.enterText(_inDialog(byKey('station-name')), 'Grill');
      await h.tap(_inDialog(byKey('station-brand')));
      await h.tap(top('Epson'));
      await h.enterText(_inDialog(byKey('station-port')), '');
      await h.tap(_inDialog(byKey('station-save')));
      final body = _body(
        h.server.callsTo(KitchenRoutes.stations, method: 'POST').single,
      );
      expect(body['printer_brand'], 'epson');
      expect(body['printer_ip'], isNull);
      expect(body['printer_port'], isNull);
      await h.expectToast('Station created');
    });

    testWidgets('SET-KST-018 edit: PATCH with every field; removing the '
        'printer clears it', (tester) async {
      final h = await pumpKitchen(tester);
      final bar = stationId('zamalek', 'bar');
      await h.tap(_inTable(byKey('kitchen-edit-$bar')));
      expect(
        tester
            .widget<DashSelectField<String>>(_inDialog(byKey('station-brand')))
            .value,
        'epson',
      );
      expect(
        tester.widget<DashTextField>(_inDialog(byKey('station-ip'))).value,
        '192.168.10.21',
      );
      await h.enterText(_inDialog(byKey('station-name')), 'Coffee bar');
      await h.tap(_inDialog(byKey('station-brand')));
      await h.tap(top('None (no printer)'));
      await h.tap(_inDialog(byKey('station-save')));
      final patch = h.server.callsTo(KitchenRoutes.station, method: 'PATCH');
      expect(patch.single.path, '/kitchen/stations/$bar');
      expect(_body(patch.single), {
        'name': 'Coffee bar',
        'is_default': true,
        'is_active': true,
        'printer_brand': null,
        'printer_ip': null,
        'printer_port': null,
      });
      await h.expectToast('Station updated');
      expect(_station(h.db!, bar)['printer_brand'], isNull);
      expect(_inTable(find.text('Coffee bar')), findsOneWidget);
    });

    testWidgets('SET-KST-018 Saving… while busy, then closes', (
      tester,
    ) async {
      final m = setupMockServer();
      final gate = m.server.hold('POST', KitchenRoutes.stations);
      final h = await pumpKitchen(tester, backend: m);
      await h.tap(inStations(byKey('kitchen-new-station')));
      await h.enterText(_inDialog(byKey('station-name')), 'Grill');
      await h.tap(_inDialog(byKey('station-save')));
      final save = tester.widget<DashButton>(_inDialog(byKey('station-save')));
      expect(save.label, 'Saving…');
      expect(save.loading, isTrue);
      gate.release();
      await h.settle();
      await h.expectToast('Station created');
      expect(_dialog(), findsNothing);
    });

    testWidgets('SET-KST-018 a failure toasts the server\'s words and stays '
        'open; Cancel closes without a request', (tester) async {
      final m = setupMockServer();
      final refusal = MockResponse.badRequest(KitchenRefusals.nameRequired);
      m.server.fail('POST', KitchenRoutes.stations, refusal);
      final h = await pumpKitchen(tester, backend: m);
      await h.tap(inStations(byKey('kitchen-new-station')));
      await h.enterText(_inDialog(byKey('station-name')), 'Grill');
      await h.tap(_inDialog(byKey('station-save')));
      await h.expectToast(h.refusalWords(refusal));
      expect(_dialog(), findsOneWidget);
      expect(
        tester.widget<DashButton>(_inDialog(byKey('station-save'))).label,
        'Save',
      );
      expect(h.server.callsTo(KitchenRoutes.stations, method: 'GET'), hasLength(1));
      await h.tap(_inDialog(byKey('station-cancel')));
      expect(_dialog(), findsNothing);
      expect(
        h.server.callsTo(KitchenRoutes.stations, method: 'POST'),
        hasLength(1),
      );
    });

    testWidgets('SET-KST-018 a blank name is the server\'s to refuse', (
      tester,
    ) async {
      final h = await pumpKitchen(tester);
      await h.tap(inStations(byKey('kitchen-new-station')));
      await h.enterText(_inDialog(byKey('station-name')), '   ');
      await h.tap(_inDialog(byKey('station-save')));
      expect(_body(
        h.server.callsTo(KitchenRoutes.stations, method: 'POST').single,
      )['name'], '');
      await h.expectToast(
        h.refusalWords(MockResponse.badRequest(KitchenRefusals.nameRequired)),
      );
      expect(_dialog(), findsOneWidget);
    });

    testWidgets('SET-KST-019 the editor opens on its station\'s values or the '
        'defaults, each time', (tester) async {
      final h = await pumpKitchen(tester);
      await h.tap(inStations(byKey('kitchen-new-station')));
      await h.enterText(_inDialog(byKey('station-name')), 'Draft');
      await h.tap(_inDialog(byKey('station-cancel')));
      await h.tap(inStations(byKey('kitchen-new-station')));
      expect(
        tester.widget<DashTextField>(_inDialog(byKey('station-name'))).value,
        '',
      );
      await h.tap(_inDialog(byKey('station-cancel')));
      await h.tap(_inTable(find.text('Pastry')));
      final active = tester.widget<DashSwitch>(
        find.descendant(
          of: _inDialog(byKey('station-active')),
          matching: find.byType(DashSwitch),
        ),
      );
      expect(active.value, isFalse);
      expect(
        tester
            .widget<DashSelectField<String>>(_inDialog(byKey('station-brand')))
            .value,
        'none',
      );
    });

    testWidgets('SET-KST-019 an untouched editor follows a background '
        'refresh; a touched one keeps what was typed', (tester) async {
      final h = await pumpKitchen(tester);
      final kitchen = stationId('zamalek', 'kitchen');
      await h.tap(_inTable(byKey('kitchen-edit-$kitchen')));
      h.db![KitchenSeed.stationsTable].update(kitchen, {'name': 'Hot line'});
      h.container.read(realtimeBusProvider).invalidate(const ['/kitchen']);
      await h.settle();
      expect(
        tester.widget<DashTextField>(_inDialog(byKey('station-name'))).value,
        'Hot line',
      );
      await h.tap(_inDialog(byKey('station-default')));
      h.db![KitchenSeed.stationsTable].update(kitchen, {'name': 'Grill'});
      h.container.read(realtimeBusProvider).invalidate(const ['/kitchen']);
      await h.settle();
      expect(
        tester.widget<DashTextField>(_inDialog(byKey('station-name'))).value,
        'Hot line',
      );
    });

    testWidgets('SET-KST-024 no IP or port checks (the server decides); Save '
        'on both; models capitalised', (tester) async {
      final h = await pumpKitchen(tester);
      await h.tap(inStations(byKey('kitchen-new-station')));
      expect(
        tester.widget<DashButton>(_inDialog(byKey('station-save'))).label,
        'Save',
      );
      await h.enterText(_inDialog(byKey('station-name')), 'Grill');
      await h.tap(_inDialog(byKey('station-brand')));
      await h.tap(top('Epson'));
      await h.enterText(_inDialog(byKey('station-ip')), 'printer.local');
      await h.tap(_inDialog(byKey('station-save')));
      expect(
        _body(
          h.server.callsTo(KitchenRoutes.stations, method: 'POST').single,
        )['printer_ip'],
        'printer.local',
      );
      await h.expectToast('Station created');
      expect(
        _inTable(find.textContaining('printer.local', findRichText: true)),
        findsOneWidget,
      );
      await h.tap(_inTable(byKey('kitchen-edit-${stationId('zamalek', 'bar')}')));
      expect(
        tester.widget<DashButton>(_inDialog(byKey('station-save'))).label,
        'Save',
      );
    });
  });

  group('layouts, live, refusals', () {
    testWidgets('SET-KST-020 phone: station cards; the mode controls under '
        'the words', (tester) async {
      final h = await pumpKitchen(tester, size: DashSize.phone);
      expect(_inTable(find.text('Bar')), findsOneWidget);
      final words = tester.getTopLeft(_inBar(find.text('Where tickets show')));
      final select = tester.getTopLeft(_inBar(byKey('kitchen-mode')));
      expect(select.dy, greaterThan(words.dy));
      await h.tap(_inTable(find.text('Kitchen')));
      expect(_inDialog(find.text('Edit station')), findsOneWidget);
    });

    testWidgets('SET-KST-020 desktop: the controls beside the words', (
      tester,
    ) async {
      await pumpKitchen(tester);
      final words = tester.getCenter(_inBar(find.text('Where tickets show')));
      final select = tester.getCenter(_inBar(byKey('kitchen-mode')));
      expect(select.dx, greaterThan(words.dx));
      expect((select.dy - words.dy).abs(), lessThan(40));
    });

    testWidgets('SET-KST-021 a kitchen.* event reads the stations and the '
        'mode again', (tester) async {
      final h = await pumpKitchen(tester);
      h.db![KitchenSeed.stationsTable].update(
        stationId('zamalek', 'pastry'),
        {'is_active': true},
      );
      h.realtime.current!.emit('kitchen.station_changed', data: '{}');
      await h.settle();
      expect(h.server.callsTo(KitchenRoutes.stations), hasLength(2));
      expect(h.server.callsTo(KitchenRoutes.routingMode), hasLength(2));
      expect(_inTable(find.text('Inactive')), findsNothing);
    });

    testWidgets('SET-KST-022 without kitchen.stations.*: the rail hides the '
        'pane; by URL the read refuses into the table', (tester) async {
      final h = await pumpKitchen(
        tester,
        query: maadi,
        persona: Persona.limited,
      );
      expect(
        find.descendant(
          of: find.byType(SettingsShell),
          matching: find.text('Stations'),
        ),
        findsNothing,
      );
      final refused = MockResponse.denied('kitchen.stations.read');
      expect(_inTable(find.text(h.refusalWords(refused))), findsOneWidget);
      expect(inStations(byKey('kitchen-new-station')), findsOneWidget);
      await _pickMode(h, 'Both');
      await h.expectToast(
        h.refusalWords(MockResponse.denied('kitchen.stations.edit')),
      );
    });

    testWidgets('SET-KST-022 a create refused by the server toasts', (
      tester,
    ) async {
      final h = await pumpKitchen(
        tester,
        query: maadi,
        persona: Persona.limited,
      );
      await h.tap(inStations(byKey('kitchen-new-station')));
      await h.enterText(_inDialog(byKey('station-name')), 'Grill');
      await h.tap(_inDialog(byKey('station-save')));
      await h.expectToast(
        h.refusalWords(MockResponse.denied('kitchen.stations.create')),
      );
      expect(_dialog(), findsOneWidget);
    });

    testWidgets('SET-KST-022 a branch manager runs their own branch', (
      tester,
    ) async {
      final h = await pumpKitchen(tester, persona: Persona.manager);
      expect(_inTable(find.byType(StationPrinter)), findsNWidgets(3));
      await _pickMode(h, 'POS queue');
      await h.expectToast('Routing mode updated');
    });
  });
}
