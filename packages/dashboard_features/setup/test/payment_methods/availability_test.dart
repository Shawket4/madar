// The Availability tab of `/settings/payment-methods` (SET-PAY-022..040,
// SET-SHL-019): the branch, teller and device allow-lists, driven through the
// real app shell at Zamalek (restricted to cash, card, wallet and InstaPay;
// Youssef to cash; the second counter to card, wallet and InstaPay).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/payment_methods/allow_list_editor.dart';
import 'package:dashboard_setup/src/payment_methods/pm_data.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'pm_support.dart';

const _branch = 'allow-list-branch';
String _user(String key) => 'allow-list-user-${SeedIds.user(key)}';
String _device(String code) =>
    'allow-list-device-${PmSeed.deviceId('zamalek', code)}';

/// Opens the page at [query] and switches to the Availability tab.
Future<DashHarness> _open(
  WidgetTester tester, {
  String? query,
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  ({MockServer server, MockDb db})? backend,
}) async {
  final h = await pumpPm(
    tester,
    query: query ?? zamalek,
    persona: persona,
    size: size,
    locale: locale,
    backend: backend,
  );
  await h.tap(
    inPage(
      find.descendant(
        of: find.byKey(const ValueKey('pm-tabs')),
        matching: find.text(h.t('paymentMethods.availability.title')),
      ),
    ),
  );
  return h;
}

Finder _switch(String key) => inEditor(key, find.byType(DashSwitch));
Finder _save(String key) => inEditor(key, find.byType(DashButton));
Finder _choice(String key, String method) =>
    inEditor(key, find.byKey(ValueKey('allow-choice-${pmId(method)}')));

DashButton _saveButton(WidgetTester tester, String key) =>
    tester.widget(_save(key));

/// The method names [key] offers, in order.
List<String> _offered(WidgetTester tester, String key) => [
  for (final e in inEditor(key, find.byType(DashCheckbox)).evaluate())
    (e.widget as DashCheckbox).semanticLabel,
];

List<String> _ticked(WidgetTester tester, String key) => [
  for (final e in inEditor(key, find.byType(DashCheckbox)).evaluate())
    if ((e.widget as DashCheckbox).value == true)
      (e.widget as DashCheckbox).semanticLabel,
];

void main() {
  group('states', () {
    testWidgets('SET-PAY-022 no branch: "Select a branch" with the hint; the '
        'people are read, the availability is not', (tester) async {
      final h = await _open(tester, query: '');
      expect(
        inPage(find.text('Select a branch to view its tills')),
        findsOneWidget,
      );
      expect(
        inPage(find.text(h.t('paymentMethods.availability.pickBranchHint'))),
        findsOneWidget,
      );
      expect(h.server.callsTo(PmRoutes.availability), isEmpty);
      expect(h.server.callsTo(PmRoutes.devices), isEmpty);
      expect(h.server.callsTo(PmRoutes.users).single.query, {
        'org_id': [SeedIds.sabahOrg],
      });
    });

    testWidgets('SET-PAY-023 loading: three card skeletons', (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', PmRoutes.availability);
      final h = await _open(tester, backend: m);
      final loading = inPage(
        find.byKey(const ValueKey('pm-availability-loading')),
      );
      expect(
        find.descendant(of: loading, matching: find.byType(DashSkeleton)),
        findsNWidgets(3),
      );
      gate.release();
      await h.settle();
      expect(loading, findsNothing);
      expect(editor(_branch), findsOneWidget);
    });

    testWidgets('SET-PAY-024 a failed read: the error with its words and '
        'Retry refetching both reads', (tester) async {
      final m = setupMockServer();
      final missing = MockResponse.notFound('Branch not found');
      m.server.fail('GET', PmRoutes.availability, missing, times: null);
      final h = await _open(tester, backend: m);
      final error = inPage(find.byKey(const ValueKey('pm-availability-error')));
      expect(
        find.descendant(
          of: error,
          matching: find.text("Couldn't load payment method availability"),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: error,
          matching: find.text(h.refusalWords(missing)),
        ),
        findsOneWidget,
      );
      m.server.clearFailures();
      final before = h.server.calls.length;
      await h.tap(find.descendant(of: error, matching: find.text('Retry')));
      expect(editor(_branch), findsOneWidget);
      expect(
        {for (final c in h.server.calls.skip(before)) c.path},
        {'/payment-methods/availability', '/payment-methods'},
      );
    });

    testWidgets('SET-PAY-024 the methods read failing shows the same error', (
      tester,
    ) async {
      final m = setupMockServer();
      final h = await pumpPm(tester, query: zamalek, backend: m);
      final boom = MockResponse.error(500, 'Service unavailable: boom');
      m.server.fail('GET', PmRoutes.list, boom, times: null);
      h.container.invalidate(paymentMethodsProvider);
      await h.settle();
      await h.tap(
        inPage(
          find.descendant(
            of: find.byKey(const ValueKey('pm-tabs')),
            matching: find.text('Availability'),
          ),
        ),
      );
      expect(
        inPage(find.text("Couldn't load payment method availability")),
        findsOneWidget,
      );
      expect(inPage(find.text(h.refusalWords(boom))), findsOneWidget);
    });
  });

  group('sections', () {
    testWidgets('SET-PAY-025 Branch: every ACTIVE method, the branch\'s '
        'own ticks', (tester) async {
      final h = await _open(tester);
      expect(
        inPage(
          find.text(
            'The methods any charge at this branch can '
            'offer.',
          ),
        ),
        findsOneWidget,
      );
      expect(inEditor(_branch, find.text('Branch')), findsOneWidget);
      expect(_offered(tester, _branch), [
        'Cash',
        'Card',
        'Digital Wallet',
        'Mixed',
        'Talabat Online',
        'InstaPay',
      ]);
      expect(_ticked(tester, _branch), [
        'Cash',
        'Card',
        'Digital Wallet',
        'InstaPay',
      ]);
      expect(h.server.callsTo(PmRoutes.availability).single.query, {
        'branch_id': [SeedIds.zamalek],
      });
    });

    testWidgets('SET-PAY-026 Tellers: the branch\'s active tellers and '
        'managers, counted, two columns from 1024', (tester) async {
      final h = await _open(tester);
      expect(
        inPage(find.text("Narrow the branch's methods for one teller.")),
        findsOneWidget,
      );
      final header = tester.widget<DashSectionHeader>(
        inPage(
          find.byWidgetPredicate(
            (w) => w is DashSectionHeader && w.title == 'Tellers',
          ),
        ),
      );
      expect(header.count, 3);
      for (final name in ['Karim Adel', 'Mariam Fathy', 'Youssef Samir']) {
        expect(inPage(find.text(name)), findsOneWidget);
      }
      // Waiters, the kitchen and other branches' people are not listed.
      expect(inPage(find.text('Laila Ehab')), findsNothing);
      expect(inPage(find.text('Hana Mostafa')), findsNothing);
      expect(
        tester.getTopLeft(editor(_user('karim'))).dy,
        tester.getTopLeft(editor(_user('mariam'))).dy,
      );
      expect(h.server.callsTo(PmRoutes.users).single.query, {
        'org_id': [SeedIds.sabahOrg],
      });
    });

    testWidgets('SET-PAY-026 one column on a phone', (tester) async {
      await _open(tester, size: DashSize.phone);
      expect(
        tester.getTopLeft(editor(_user('mariam'))).dy,
        greaterThan(tester.getTopLeft(editor(_user('karim'))).dy),
      );
    });

    testWidgets('SET-PAY-026 nobody at the branch: "No tellers at this '
        'branch"', (tester) async {
      final m = setupMockServer();
      for (final k in ['dina', 'salma', 'omar']) {
        m.db['users'].update(SeedIds.user(k), {'is_active': false});
      }
      await _open(tester, query: atBranch(SeedIds.newCairo), backend: m);
      expect(inPage(find.text('No tellers at this branch')), findsOneWidget);
    });

    testWidgets('SET-PAY-027 Devices: the live devices, "code · name" in '
        'mono', (tester) async {
      await _open(tester);
      final header = tester.widget<DashSectionHeader>(
        inPage(
          find.byWidgetPredicate(
            (w) => w is DashSectionHeader && w.title == 'Devices',
          ),
        ),
      );
      expect(header.count, 5);
      final titles = [
        for (final e in inPage(find.byType(AllowListEditor)).evaluate())
          if ((e.widget as AllowListEditor).mono)
            (e.widget as AllowListEditor).title,
      ];
      expect(titles, [
        'K1 · Kitchen screen',
        'T1 · Counter 1',
        'T2 · Counter 2',
        'W1 · Floor tablet',
        'W2 · Terrace tablet',
      ]);
      expect(
        inPage(find.text("Narrow the branch's methods for one POS device.")),
        findsOneWidget,
      );
    });

    testWidgets('SET-PAY-027 a retired device is left out; none left: "No '
        'devices at this branch yet"', (tester) async {
      final m = setupMockServer();
      m.db[PmSeed.ownDevicesTable].update(PmSeed.deviceId('maadi', 'T1'), {
        'retired_at': '2026-10-01T08:00:00.000Z',
      });
      await _open(tester, query: atBranch(SeedIds.maadi), backend: m);
      expect(
        inPage(find.text('No devices at this branch yet')),
        findsOneWidget,
      );
    });
  });

  group('editors', () {
    testWidgets('SET-PAY-028 the header: "{{count}} selected" or "No '
        'restriction", "Only selected" / "All methods", "Restrict methods"', (
      tester,
    ) async {
      final h = await _open(tester);
      expect(inEditor(_branch, find.text('4 selected')), findsOneWidget);
      expect(inEditor(_branch, find.text('Only selected')), findsOneWidget);
      expect(
        inEditor(_user('youssef'), find.text('1 selected')),
        findsOneWidget,
      );
      expect(inEditor(_device('T2'), find.text('3 selected')), findsOneWidget);
      expect(
        inEditor(_user('karim'), find.text('No restriction')),
        findsOneWidget,
      );
      expect(
        inEditor(_user('karim'), find.text('All methods')),
        findsOneWidget,
      );
      expect(
        tester.widget<DashSwitch>(_switch(_branch)).semanticLabel,
        h.t('paymentMethods.availability.restrict'),
      );
      expect(tester.widget<DashSwitch>(_switch(_branch)).value, isTrue);
      expect(tester.widget<DashSwitch>(_switch(_user('karim'))).value, isFalse);
      expect(inEditor(_user('karim'), find.byType(DashCheckbox)), findsNothing);
    });

    testWidgets('SET-PAY-028 the words beside the switch toggle it too', (
      tester,
    ) async {
      final h = await _open(tester);
      final k = _user('karim');
      await h.tap(inEditor(k, find.text('All methods')));
      expect(inEditor(k, find.text('Only selected')), findsOneWidget);
      expect(tester.widget<DashSwitch>(_switch(k)).value, isTrue);
      expect(inEditor(k, find.byType(DashCheckbox)), findsNWidgets(4));
    });

    testWidgets('SET-PAY-029 restricted: a checkbox per method; ticking and '
        'unticking edit the list', (tester) async {
      final h = await _open(tester);
      await h.tap(_choice(_branch, 'mixed'));
      expect(inEditor(_branch, find.text('5 selected')), findsOneWidget);
      expect(_ticked(tester, _branch), contains('Mixed'));
      await h.tap(_choice(_branch, 'cash'));
      expect(inEditor(_branch, find.text('4 selected')), findsOneWidget);
      expect(_ticked(tester, _branch), isNot(contains('Cash')));
    });

    testWidgets('SET-PAY-030 SET-PAY-040 restricted with nothing ticked: '
        'refused after Save, nothing sent', (tester) async {
      final h = await _open(tester);
      final k = _user('karim');
      await h.tap(_switch(k));
      expect(inEditor(k, find.text('0 selected')), findsOneWidget);
      expect(
        inEditor(k, find.text('Pick at least one method, or allow all.')),
        findsNothing,
      );
      await h.tap(_save(k));
      expect(
        inEditor(k, find.text('Pick at least one method, or allow all.')),
        findsOneWidget,
      );
      expect(h.server.callsTo(PmRoutes.user), isEmpty);
      await h.tap(_choice(k, 'cash'));
      expect(
        inEditor(k, find.text('Pick at least one method, or allow all.')),
        findsNothing,
      );
    });

    testWidgets('SET-PAY-031 branch Save: disabled until changed, sends the '
        'ticked list, toasts and refetches', (tester) async {
      final h = await _open(tester);
      expect(_saveButton(tester, _branch).onPressed, isNull);
      await h.tap(_choice(_branch, 'instapay'));
      expect(_saveButton(tester, _branch).onPressed, isNotNull);
      final seen = watchInvalidations(h);
      final reads = h.server.callsTo(PmRoutes.availability).length;
      await h.tap(_save(_branch));
      final put = h.server.callsTo(PmRoutes.branch).single;
      expect(
        put.path,
        '/payment-methods/availability/branches/${SeedIds.zamalek}',
      );
      expect(put.body, {
        'restricted': true,
        'payment_method_ids': [
          pmId('cash'),
          pmId('card'),
          pmId('digital_wallet'),
        ],
      });
      await h.expectToast('Saved');
      expect(seen, [
        ['/payment-methods'],
      ]);
      expect(h.server.callsTo(PmRoutes.availability).length, reads + 1);
      expect(inEditor(_branch, find.text('3 selected')), findsOneWidget);
      expect(_saveButton(tester, _branch).onPressed, isNull);
      // InstaPay is no longer the branch's: the narrower editors drop it.
      await h.tap(_switch(_user('karim')));
      expect(_offered(tester, _user('karim')), [
        'Cash',
        'Card',
        'Digital Wallet',
      ]);
    });

    testWidgets('SET-PAY-031 turning the restriction off sends an empty '
        'unrestricted list', (tester) async {
      final h = await _open(tester);
      await h.tap(_switch(_branch));
      expect(inEditor(_branch, find.text('No restriction')), findsOneWidget);
      await h.tap(_save(_branch));
      expect(h.server.callsTo(PmRoutes.branch).single.body, {
        'restricted': false,
        'payment_method_ids': <String>[],
      });
      await h.expectToast('Saved');
      expect(inEditor(_branch, find.text('All methods')), findsOneWidget);
      expect(_offered(tester, _user('karim')), isEmpty);
      await h.tap(_switch(_user('karim')));
      expect(_offered(tester, _user('karim')), hasLength(6));
    });

    testWidgets('SET-PAY-031 every Save spins while any availability write '
        'runs', (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('PUT', PmRoutes.branch);
      final h = await _open(tester, backend: m);
      await h.tap(_choice(_branch, 'instapay'));
      await h.tap(_save(_branch));
      expect(_saveButton(tester, _branch).loading, isTrue);
      expect(_saveButton(tester, _user('karim')).loading, isTrue);
      gate.release();
      await h.settle();
      await h.expectToast('Saved');
      expect(_saveButton(tester, _branch).loading, isFalse);
    });

    testWidgets('SET-PAY-031 leaving the tab mid-save still refreshes', (
      tester,
    ) async {
      final m = setupMockServer();
      final gate = m.server.hold('PUT', PmRoutes.branch);
      final h = await _open(tester, backend: m);
      await h.tap(_choice(_branch, 'instapay'));
      await h.tap(_save(_branch));
      await h.tap(
        inPage(
          find.descendant(
            of: find.byKey(const ValueKey('pm-tabs')),
            matching: find.text('Payment Methods'),
          ),
        ),
      );
      final lists = h.server.callsTo(PmRoutes.list).length;
      gate.release();
      await h.settle();
      expect(h.server.callsTo(PmRoutes.list).length, lists + 1);
    });

    testWidgets('SET-PAY-031 SET-PAY-037 a refused write toasts the '
        "server's words (manager)", (tester) async {
      final h = await _open(tester, persona: Persona.manager);
      await h.tap(_choice(_branch, 'instapay'));
      await h.tap(_save(_branch));
      await h.expectToast(
        h.refusalWords(MockResponse.denied('payment_methods.edit')),
      );
      // The editor keeps what was typed.
      expect(inEditor(_branch, find.text('3 selected')), findsOneWidget);
    });

    testWidgets('SET-PAY-032 a teller\'s Save', (tester) async {
      final h = await _open(tester);
      final k = _user('mariam');
      await h.tap(_switch(k));
      await h.tap(_choice(k, 'card'));
      await h.tap(_save(k));
      final put = h.server.callsTo(PmRoutes.user).single;
      expect(
        put.path,
        '/payment-methods/availability/users/${SeedIds.user('mariam')}',
      );
      expect(put.body, {
        'restricted': true,
        'payment_method_ids': [pmId('card')],
      });
      await h.expectToast('Saved');
      expect(inEditor(k, find.text('1 selected')), findsOneWidget);
    });

    testWidgets('SET-PAY-033 a device\'s Save', (tester) async {
      final h = await _open(tester);
      final k = _device('T2');
      await h.tap(_switch(k));
      await h.tap(_save(k));
      final put = h.server.callsTo(PmRoutes.device).single;
      expect(
        put.path,
        '/payment-methods/availability/devices/${PmSeed.deviceId('zamalek', 'T2')}',
      );
      expect(put.body, {'restricted': false, 'payment_method_ids': <String>[]});
      await h.expectToast('Saved');
      expect(inEditor(k, find.text('No restriction')), findsOneWidget);
    });

    testWidgets('SET-PAY-034 SET-PAY-036 a live change refetches the list '
        'and the availability and resets the editors', (tester) async {
      final m = setupMockServer();
      final h = await _open(tester, backend: m);
      final k = _user('mariam');
      await h.tap(_switch(k));
      expect(inEditor(k, find.text('0 selected')), findsOneWidget);
      // Someone else restricts Youssef meanwhile.
      m.db[PmSeed.availabilityTable].insert({
        'owner': 'user',
        'owner_id': SeedIds.user('youssef'),
        'payment_method_id': pmId('card'),
        'org_id': SeedIds.sabahOrg,
      }, timestamps: false);
      final lists = h.server.callsTo(PmRoutes.list).length;
      final reads = h.server.callsTo(PmRoutes.availability).length;
      h.realtime.current!.emit(
        'payment_methods.availability_changed',
        data: '{"branch_id":"${SeedIds.zamalek}"}',
      );
      await h.settle();
      expect(h.server.callsTo(PmRoutes.list).length, lists + 1);
      expect(h.server.callsTo(PmRoutes.availability).length, reads + 1);
      expect(inEditor(k, find.text('No restriction')), findsOneWidget);
      expect(
        inEditor(_user('youssef'), find.text('2 selected')),
        findsOneWidget,
      );
    });

    testWidgets('SET-PAY-035 switching the header branch reloads the tab for '
        'that branch', (tester) async {
      final h = await _open(tester);
      await h.go('$pmPath${atBranch(SeedIds.heliopolis)}');
      // The tab stays open across the scope change.
      expect(
        inPage(find.byKey(const ValueKey('pm-availability'))),
        findsOneWidget,
      );
      expect(h.server.callsTo(PmRoutes.availability).last.query, {
        'branch_id': [SeedIds.heliopolis],
      });
      expect(inEditor(_branch, find.text('No restriction')), findsOneWidget);
      expect(inPage(find.text('Rana Helmy')), findsOneWidget);
      expect(inPage(find.text('Karim Adel')), findsNothing);
    });

    int? count(WidgetTester tester, String title) => tester
        .widget<DashSectionHeader>(
          inPage(
            find.byWidgetPredicate(
              (w) => w is DashSectionHeader && w.title == title,
            ),
          ),
        )
        .count;

    testWidgets('SET-PAY-039 the tellers and devices each show a skeleton '
        'while they load, and the count waits for the data', (tester) async {
      final m = setupMockServer();
      final users = m.server.hold('GET', PmRoutes.users);
      final devices = m.server.hold('GET', PmRoutes.devices);
      final h = await _open(tester, backend: m);
      for (final k in ['pm-tellers-loading', 'pm-devices-loading']) {
        expect(inPage(find.byKey(ValueKey(k))), findsOneWidget, reason: k);
      }
      expect(inPage(find.text('No tellers at this branch')), findsNothing);
      expect(inPage(find.text('No devices at this branch yet')), findsNothing);
      expect(count(tester, 'Tellers'), isNull);
      expect(count(tester, 'Devices'), isNull);
      expect(editor(_branch), findsOneWidget);
      users.release();
      devices.release();
      await h.settle();
      expect(inPage(find.byType(DashSkeleton)), findsNothing);
      expect(editor(_user('karim')), findsOneWidget);
      expect(count(tester, 'Tellers'), isNotNull);
      expect(count(tester, 'Devices'), isNotNull);
    });

    testWidgets('SET-PAY-039 a failed read shows "Couldn\'t load this", the '
        'server\'s words and a Retry for that list only', (tester) async {
      final m = setupMockServer();
      final boom = MockResponse.error(500, 'down');
      m.server.fail('GET', PmRoutes.users, boom, times: null);
      final h = await _open(tester, backend: m);
      final error = inPage(find.byKey(const ValueKey('pm-tellers-error')));
      expect(error, findsOneWidget);
      expect(
        find.descendant(of: error, matching: find.text("Couldn't load this")),
        findsOneWidget,
      );
      expect(
        find.descendant(of: error, matching: find.text(h.refusalWords(boom))),
        findsOneWidget,
      );
      expect(inPage(find.text('No tellers at this branch')), findsNothing);
      expect(count(tester, 'Tellers'), isNull);
      // The devices answered: their editors show.
      expect(editor(_device('T2')), findsOneWidget);
      final devices = h.server.callsTo(PmRoutes.devices).length;
      m.server.clearFailures();
      await h.tap(find.descendant(of: error, matching: find.text('Retry')));
      expect(editor(_user('karim')), findsOneWidget);
      expect(error, findsNothing);
      expect(h.server.callsTo(PmRoutes.devices), hasLength(devices));
    });

    testWidgets('SET-PAY-040 narrower editors offer the branch\'s methods, '
        'in the active language; the count includes ids no longer offered', (
      tester,
    ) async {
      final m = setupMockServer();
      // Mariam was once allowed Talabat Online, which Zamalek no longer takes.
      m.db[PmSeed.availabilityTable].insert({
        'owner': 'user',
        'owner_id': SeedIds.user('mariam'),
        'payment_method_id': pmId('talabat_online'),
        'org_id': SeedIds.sabahOrg,
      }, timestamps: false);
      await _open(tester, backend: m, locale: 'ar');
      final k = _user('mariam');
      expect(_offered(tester, k), ['نقدي', 'بطاقة', 'محفظة رقمية', 'إنستاباي']);
      expect(_ticked(tester, k), isEmpty);
      expect(inEditor(k, find.text('1 محددة')), findsOneWidget);
    });
  });
}
