// `/devices?view=clients`, the Client versions view, driven through the real
// app shell (inventory rows ADM-DEV-021..028).
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_admin/src/orgs/org_errors.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _clients = '?view=clients';

/// The ledger strip's figure labelled [label].
DashLedgerItem figure(WidgetTester tester, String label) => tester
    .widget<DashLedgerStrip>(find.byKey(const ValueKey('clients-kpis')))
    .items
    .firstWhere((i) => i.label == label);

Finder inClients(Finder f) => find.descendant(
  of: find.byKey(const ValueKey('clients-table')),
  matching: f,
);

/// The last Client versions request's query.
Map<String, List<String>> lastQuery(DashHarness h) =>
    h.server.callsTo(DevicesRoutes.clients).last.query;

void main() {
  group('figures and the read', () {
    testWidgets('ADM-DEV-021 Clients seen, On legacy paths (warning), App '
        'versions', (tester) async {
      await pumpDevices(tester, query: _clients);
      expect(figure(tester, 'Clients seen').value, 3);
      final legacy = figure(tester, 'On legacy paths');
      expect(legacy.value, 3);
      expect(legacy.tone, DashTone.warning);
      // T1, T2 and W2 all run 0.12.4.
      expect(figure(tester, 'App versions').value, 1);
    });

    testWidgets('ADM-DEV-021 every client: 12 seen, 3 on legacy, the distinct '
        'versions; none on legacy is a success tone', (tester) async {
      final backend = DevicesBackend();
      final h = await pumpDevices(
        tester,
        query: '$_clients&all=true',
        backend: backend,
      );
      expect(figure(tester, 'Clients seen').value, 12);
      expect(figure(tester, 'On legacy paths').value, 3);
      final rows = await backend.api.devices.listClientVersions(
        legacyOnly: false,
      );
      final versions = {
        for (final r in rows)
          if ((r.appVersion ?? '').isNotEmpty) r.appVersion,
      };
      expect(figure(tester, 'App versions').value, versions.length);
      for (final r in backend.clients.rows) {
        r['last_legacy_at'] = null;
      }
      await h.go('/devices$_clients&all=true&days=30');
      expect(figure(tester, 'On legacy paths').value, 0);
      expect(figure(tester, 'On legacy paths').tone, DashTone.success);
    });

    testWidgets('ADM-DEV-022 org-wide: no branch_id and a Branch column; a '
        'branch: its id and no Branch column', (tester) async {
      final h = await pumpDevices(tester, query: _clients);
      expect(lastQuery(h), {
        'legacy_only': ['true'],
        'days': ['14'],
      });
      expect(inClients(find.text('BRANCH')), findsOneWidget);
      expect(inClients(find.text('Heliopolis')), findsWidgets);
      await h.go('/devices$_clients&branchId=${SeedIds.zamalek}');
      expect(lastQuery(h)['branch_id'], [SeedIds.zamalek]);
      expect(inClients(find.text('BRANCH')), findsNothing);
      expect(clientRows(), findsOneWidget);
    });
  });

  group('the toolbar', () {
    testWidgets('ADM-DEV-023 the window: Last 7 / 14 / 30 / 90 days, 14 '
        'unwritten', (tester) async {
      final h = await pumpDevices(tester, query: _clients);
      final window = find.byKey(const ValueKey('clients-window'));
      expect(
        find.descendant(of: window, matching: find.text('Last 14 days')),
        findsOneWidget,
      );
      expect(tester.widget<DashSelect<int>>(window).semanticLabel, 'Window');
      await h.tap(window);
      for (final d in [7, 14, 30, 90]) {
        expect(top('Last $d days'), findsWidgets, reason: '$d');
      }
      await h.tap(top('Last 30 days').last); // the list, not the trigger's sizer
      expect(h.location.queryParameters['days'], '30');
      expect(lastQuery(h)['days'], ['30']);
      await h.tap(window);
      await h.tap(top('Last 14 days').last);
      expect(h.location.queryParameters.containsKey('days'), isFalse);
      // The 14-day read is still cached: nothing more is asked.
      expect(h.server.callsTo(DevicesRoutes.clients), hasLength(2));
    });

    testWidgets('ADM-DEV-024 Legacy clients only: on by default; off writes '
        'all=true', (tester) async {
      final h = await pumpDevices(tester, query: _clients);
      final toggle = find.byKey(const ValueKey('clients-legacy-only'));
      expect(
        tester.widget<DashSwitch>(
          find.descendant(of: toggle, matching: find.byType(DashSwitch)),
        ).value,
        isTrue,
      );
      await h.tap(find.descendant(of: toggle, matching: find.text('Legacy clients only')));
      expect(h.location.queryParameters['all'], 'true');
      expect(lastQuery(h)['legacy_only'], ['false']);
      expect(clientRows(), findsNWidgets(12));
      await h.tap(toggle);
      expect(h.location.queryParameters.containsKey('all'), isFalse);
      expect(clientRows(), findsNWidgets(3));
    });
  });

  group('the table', () {
    testWidgets('ADM-DEV-025 Device, Branch, Version, Last seen, Last legacy '
        'hit', (tester) async {
      final h = await pumpDevices(tester, query: '$_clients&all=true');
      for (final header in [
        'DEVICE',
        'BRANCH',
        'VERSION',
        'LAST SEEN',
        'LAST LEGACY HIT',
      ]) {
        expect(inClients(find.text(header)), findsOneWidget, reason: header);
      }
      expect(inClients(find.text('Unregistered client')), findsOneWidget);
      expect(inClients(find.text('Dart/3.9 (dart:io)')), findsOneWidget);
      expect(inClients(find.text('T1')), findsWidgets);
      expect(inClients(find.text('madar-pos/0.12.4 (android)')), findsWidgets);
      expect(inClients(find.text('0.12.4')), findsNWidgets(3));
      expect(inClients(find.text('Up to date')), findsNWidgets(9));
      expect(inClients(find.text('Legacy')), findsNWidgets(3));
      expect(inClients(textHas('legacy_shifts_route')), findsNWidgets(3));
      expect(inClients(textHas('+1')), findsNWidgets(3));
      // The last legacy path of each of the three legacy rows.
      expect(inClients(textHas('/shifts/branches/')), findsNWidgets(3));
      // The client string and the path read left to right, cut with a hint.
      final client = tester.widget<MadarClippedText>(
        inClients(
          find.byWidgetPredicate(
            (w) => w is MadarClippedText && w.data == 'Dart/3.9 (dart:io)',
          ),
        ),
      );
      expect(client.textDirection, TextDirection.ltr);
      expect(client.maxLines, 1);
      expect(h.server.unmatched, isEmpty);
    });

    testWidgets('ADM-DEV-025 twenty a page', (tester) async {
      final backend = DevicesBackend();
      final now = backend.db.clock.now;
      for (var i = 0; i < 20; i++) {
        backend.clients.insert({
          'client': 'curl/8.$i',
          'branch_id': SeedIds.maadi,
          'first_seen_at': now.subtract(const Duration(days: 2)).toIso8601String(),
          'last_seen_at': now.subtract(Duration(hours: i + 1)).toIso8601String(),
          'legacy_kinds': const <String>[],
        }, timestamps: false);
      }
      await pumpDevices(
        tester,
        query: '$_clients&all=true',
        backend: backend,
      );
      expect(clientRows(), findsNWidgets(20));
      expect(inClients(find.text('Page 1 of 2')), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('ADM-DEV-026 legacy only and nothing: "No legacy clients"', (
      tester,
    ) async {
      final backend = DevicesBackend();
      backend.clients.removeWhere((_) => true);
      await pumpDevices(tester, query: _clients, backend: backend);
      expect(inClients(find.text('No legacy clients')), findsOneWidget);
      expect(
        inClients(
          find.text('Nothing used a pre-rework path in the last 14 days.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ADM-DEV-026 every client and nothing: "No clients seen", '
        'the window in the words', (tester) async {
      final backend = DevicesBackend();
      backend.clients.removeWhere((_) => true);
      await pumpDevices(
        tester,
        query: '$_clients&all=true&days=30',
        backend: backend,
      );
      expect(inClients(find.text('No clients seen')), findsOneWidget);
      expect(
        inClients(
          find.text('No app has called the server in the last 30 days.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ADM-DEV-026 loading: the figures and the rows wait, no empty '
        'words', (tester) async {
      final backend = DevicesBackend();
      final gate = backend.server.hold('GET', DevicesRoutes.clients);
      final h = await pumpDevices(tester, query: _clients, backend: backend);
      expect(figure(tester, 'Clients seen').loading, isTrue);
      expect(clientRows(), findsNothing);
      expect(find.text('No legacy clients'), findsNothing);
      gate.release();
      await h.settle();
      expect(figure(tester, 'Clients seen').loading, isFalse);
      expect(clientRows(), findsNWidgets(3));
    });

    testWidgets('ADM-DEV-026 a failed read: the error and Retry', (
      tester,
    ) async {
      final backend = DevicesBackend();
      backend.server.fail(
        'GET',
        DevicesRoutes.clients,
        MockResponse.error(500, 'Internal error'),
      );
      final h = await pumpDevices(tester, query: _clients, backend: backend);
      expect(inClients(find.byType(DashErrorState)), findsOneWidget);
      expect(find.text('No legacy clients'), findsNothing);
      await h.tap(inClients(find.text('Retry')));
      expect(clientRows(), findsNWidgets(3));
      expect(h.server.callsTo(DevicesRoutes.clients), hasLength(2));
    });

    testWidgets('ADM-DEV-027 without branches.edit the read is refused: the '
        'error in words, and Retry', (tester) async {
      final h = await pumpDevices(
        tester,
        query: '$_clients&branchId=${SeedIds.zamalek}',
        persona: Persona.manager,
      );
      final call = h.server.callsTo(DevicesRoutes.clients).single;
      expect(call.status, 403);
      final words = orgErrorWords(
        MockServer.toApiException(MockResponse.denied('branches.edit')),
        h.container.read(tProvider),
      );
      expect(inClients(find.text(words)), findsOneWidget);
      await h.tap(inClients(find.text('Retry')));
      expect(h.server.callsTo(DevicesRoutes.clients), hasLength(2));
      expect(inClients(find.text(words)), findsOneWidget);
    });

    testWidgets('ADM-DEV-027 in Arabic the refusal reads in Arabic', (
      tester,
    ) async {
      final h = await pumpDevices(
        tester,
        query: '$_clients&branchId=${SeedIds.zamalek}',
        persona: Persona.manager,
        locale: 'ar',
      );
      expect(inClients(find.text(h.t('errors.unauthorized'))), findsOneWidget);
    });
  });

  testWidgets('ADM-DEV-028 the link is checked: an unknown view is Devices; '
      'a window off the list is 14; all only for "true"', (tester) async {
    final h = await pumpDevices(
      tester,
      query: '?view=bogus&branchId=${SeedIds.zamalek}',
    );
    expect(deviceRows(), findsNWidgets(5));
    expect(h.server.callsTo(DevicesRoutes.clients), isEmpty);
    await h.go('/devices?view=clients&days=5&all=1');
    expect(lastQuery(h)['legacy_only'], ['true']);
    expect(lastQuery(h)['days'], ['14']);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('clients-window')),
        matching: find.text('Last 14 days'),
      ),
      findsOneWidget,
    );
  });
}
