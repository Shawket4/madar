// `/devices`, the Devices view and the Edit device dialog, driven through
// the real app shell (inventory rows ADM-DEV-001..013, -020, -029).
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_admin/src/devices/devices_data.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final _zamalek = atBranch(SeedIds.zamalek);

/// The pencil (named [label]) of the [index]th row.
Finder editButton([int index = 0, String label = 'Edit']) => find
    .byWidgetPredicate((w) => w is DashIconButton && w.semanticLabel == label)
    .at(index);

/// The open dialog's field [key].
Finder field(String key) => find.byKey(ValueKey(key));

Device _device(
  String code, {
  String branch = 'heliopolis',
  String? label,
  String kind = 'pos',
  String? platform,
  String? version,
}) => Device(
  id: mockUuid('device:test:$branch:$code'),
  orgId: SeedIds.sabahOrg,
  branchId: MockSeed.branchIdOf(branch),
  code: code,
  codeConflict: false,
  kind: DeviceKind.fromJson(kind),
  label: label,
  platform: platform,
  appVersion: version,
  firstSeenAt: DateTime.utc(2026, 9, 1, 8),
  lastSeenAt: DateTime.utc(2026, 10, 8, 6, 30),
);

void main() {
  group('nav, header, module', () {
    testWidgets('ADM-DEV-001 the nav leaf: branches.edit or till.open, POS '
        'orgs only', (tester) async {
      final leaf = navLeaves().firstWhere((l) => l.to == '/devices');
      for (final (persona, shown) in [
        (Persona.owner, true),
        (Persona.manager, true),
        (Persona.limited, false),
        (Persona.dawamOnly, false),
      ]) {
        final h = await pumpDevices(tester, persona: persona);
        h.allowUnmatched = persona == Persona.dawamOnly;
        expect(
          h.container.read(navLeafVisibleProvider)(leaf),
          shown,
          reason: persona.name,
        );
      }
    });

    testWidgets('ADM-DEV-001 a Dawam-only org meets the module gate, and no '
        'device is read', (tester) async {
      final h = await pumpDevices(tester, persona: Persona.dawamOnly);
      expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
      expect(h.server.callsTo(DevicesRoutes.devices), isEmpty);
      expect(h.server.callsTo(DevicesRoutes.clients), isEmpty);
    });

    testWidgets('ADM-DEV-002 title, subtitle and the Devices / Client '
        'versions switch held in the URL', (tester) async {
      final h = await pumpDevices(tester, query: _zamalek);
      expect(find.text('Devices'), findsWidgets);
      expect(
        find.text(
          'POS, kitchen and waiter devices that have signed in at this branch.',
        ),
        findsOneWidget,
      );
      final view = find.byKey(const ValueKey('devices-view'));
      expect(
        find.descendant(of: view, matching: find.text('Devices')),
        findsOneWidget,
      );
      await h.tap(
        find.descendant(of: view, matching: find.text('Client versions')),
      );
      expect(h.location.queryParameters['view'], 'clients');
      expect(h.location.queryParameters['branchId'], SeedIds.zamalek);
      expect(find.text('Clients seen'), findsOneWidget);
      expect(deviceRows(), findsNothing);
      await h.tap(find.descendant(of: view, matching: find.text('Devices')));
      expect(h.location.queryParameters.containsKey('view'), isFalse);
      expect(deviceRows(), findsNWidgets(5));
    });
  });

  group('the Devices view', () {
    testWidgets('ADM-DEV-003 no branch picked: "Select a branch", nothing '
        'read', (tester) async {
      final h = await pumpDevices(tester);
      expect(find.text('Select a branch to view its tills'), findsOneWidget);
      expect(find.text('Devices are registered per branch.'), findsOneWidget);
      expect(h.server.callsTo(DevicesRoutes.devices), isEmpty);
      expect(h.server.callsTo(DevicesRoutes.codes), isEmpty);
      expect(find.text('Activation codes'), findsNothing);
    });

    testWidgets('ADM-DEV-003 a branch manager without a branch in the link '
        'sees the same', (tester) async {
      final h = await pumpDevices(tester, persona: Persona.manager);
      expect(find.text('Select a branch to view its tills'), findsOneWidget);
      expect(h.server.callsTo(DevicesRoutes.devices), isEmpty);
    });

    testWidgets('ADM-DEV-004 the branch\'s devices, 20 a page, no search, no '
        'Columns menu', (tester) async {
      final h = await pumpDevices(tester, query: _zamalek);
      final calls = h.server.callsTo(DevicesRoutes.devices);
      expect(calls, hasLength(1));
      expect(calls.single.query['branch_id'], [SeedIds.zamalek]);
      expect(deviceRows(), findsNWidgets(5));
      for (final code in ['K1', 'T1', 'T2', 'W1', 'W2']) {
        expect(find.text(code), findsOneWidget);
      }
      expect(find.byType(DashSearchInput), findsNothing);
      expect(find.text('Columns'), findsNothing);
      expect(find.text('Page 1 of 1'), findsNothing);
    });

    testWidgets('ADM-DEV-004 more than 20 devices page', (tester) async {
      final b = DevicesBackend();
      b.devices.insertAll([
        for (var i = 1; i <= 21; i++) _device('P$i', label: 'Pad $i').toJson(),
      ]);
      final h = await pumpDevices(
        tester,
        query: atBranch(SeedIds.heliopolis),
        backend: b,
      );
      expect(deviceRows(), findsNWidgets(20));
      expect(find.text('Page 1 of 2'), findsOneWidget);
      await h.tap(
        find.byWidgetPredicate(
          (w) => w is DashIconButton && w.semanticLabel == 'Next',
        ),
      );
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(deviceRows(), findsNWidgets(3));
    });

    testWidgets('ADM-DEV-005 the code, and a warning only where another '
        'device uses it', (tester) async {
      await pumpDevices(tester, query: atBranch(SeedIds.newCairo));
      expect(deviceRows(), findsNWidgets(3));
      expect(find.text('Another device uses this code'), findsNWidgets(2));
      expect(
        find.byKey(
          ValueKey('code-conflict-${AdminSeed.deviceId('new-cairo', 'T1')}'),
        ),
        findsNothing,
      );
      for (final id in [
        AdminSeed.deviceId('new-cairo', 'T2'),
        AdminSeed.deviceId('new-cairo', 'T2-b'),
      ]) {
        expect(find.byKey(ValueKey('code-conflict-$id')), findsOneWidget);
      }
    });

    testWidgets('ADM-DEV-006 Name, Type, App: "—" when missing, an unknown '
        'kind as sent', (tester) async {
      final b = DevicesBackend();
      b.devices.insertAll([
        _device('P1', kind: 'printer').toJson(),
        _device('P2', label: 'Drive window', platform: 'android').toJson(),
      ]);
      await pumpDevices(
        tester,
        query: atBranch(SeedIds.heliopolis),
        backend: b,
      );
      // The table draws its headers in capitals.
      for (final header in ['Code', 'Name', 'Type', 'App', 'Status']) {
        expect(find.text(header.toUpperCase()), findsOneWidget, reason: header);
      }
      expect(find.text('Kitchen screen'), findsNWidgets(2));
      expect(find.text('POS'), findsNWidgets(2));
      expect(find.text('printer'), findsOneWidget);
      expect(find.text('linux · 0.4.2'), findsOneWidget);
      expect(find.text('android · 0.12.4'), findsOneWidget);
      expect(find.text('android'), findsOneWidget);
      // P1: no name and no app.
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('Drive window'), findsOneWidget);
    });

    testWidgets('ADM-DEV-007 Status: Retired / Active; Last seen as a '
        'stamp', (tester) async {
      await pumpDevices(tester, query: atBranch(SeedIds.maadi));
      expect(find.text('Retired'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('LAST SEEN'), findsOneWidget);
      // T1 8 minutes ago (today: the time only); T9 on 19 Aug 18:40 UTC.
      expect(textHas('09:52 AM'), findsOneWidget);
      expect(textHas('19 Aug · 09:40 PM'), findsOneWidget);
    });

    testWidgets('ADM-DEV-008 loading draws skeleton rows', (tester) async {
      final b = DevicesBackend();
      final gate = b.server.hold('GET', DevicesRoutes.devices);
      final h = await pumpDevices(tester, query: _zamalek, backend: b);
      expect(deviceRows(), findsNothing);
      expect(find.text('No devices yet'), findsNothing);
      expect(find.byType(DashErrorState), findsNothing);
      gate.release();
      await h.settle();
      expect(deviceRows(), findsNWidgets(5));
    });

    testWidgets('ADM-DEV-008 a failed load: the error and Retry', (
      tester,
    ) async {
      final b = DevicesBackend();
      b.server.fail(
        'GET',
        DevicesRoutes.devices,
        MockResponse.error(500, 'Internal error'),
      );
      final h = await pumpDevices(tester, query: _zamalek, backend: b);
      expect(find.text("Couldn't load this"), findsOneWidget);
      expect(find.text('Internal error'), findsOneWidget);
      expect(find.text('No devices yet'), findsNothing);
      await h.tapText('Retry');
      expect(deviceRows(), findsNWidgets(5));
      expect(h.server.callsTo(DevicesRoutes.devices), hasLength(2));
    });

    testWidgets('ADM-DEV-008 no devices: the empty state', (tester) async {
      final b = DevicesBackend();
      b.devices.removeWhere((d) => d['branch_id'] == SeedIds.heliopolis);
      await pumpDevices(
        tester,
        query: atBranch(SeedIds.heliopolis),
        backend: b,
      );
      expect(find.text('No devices yet'), findsOneWidget);
      expect(
        find.text(
          'A device appears here the first time it signs in at this branch.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('ADM-DEV-020 another branch in the scope reads its devices '
        'and codes', (tester) async {
      final h = await pumpDevices(tester, query: _zamalek);
      expect(find.text('W2'), findsOneWidget);
      await h.go('/devices${atBranch(SeedIds.newCairo)}');
      final devices = h.server.callsTo(DevicesRoutes.devices);
      final codes = h.server.callsTo(DevicesRoutes.codes, method: 'GET');
      expect(devices.last.query['branch_id'], [SeedIds.newCairo]);
      expect(codes.last.query['branch_id'], [SeedIds.newCairo]);
      expect(find.text('W2'), findsNothing);
      expect(deviceRows(), findsNWidgets(3));
      expect(find.text('6301 8245'), findsOneWidget);
    });
  });

  group('the Edit device dialog', () {
    testWidgets('ADM-DEV-009 a row opens it', (tester) async {
      final h = await pumpDevices(tester, query: _zamalek);
      await h.tap(find.text('Floor tablet'));
      expect(find.text('Edit device'), findsOneWidget);
      expect(find.text('W1'), findsWidgets);
    });

    testWidgets('ADM-DEV-009 the pencil (named "Edit") opens it', (
      tester,
    ) async {
      final h = await pumpDevices(tester, query: _zamalek);
      await h.tap(editButton(1));
      expect(find.text('Edit device'), findsOneWidget);
      final code = tester.widget<DashTextField>(field('device-code'));
      expect(code.value, 'T1');
    });

    testWidgets('ADM-DEV-010 the dialog: code, name, Retired, Cancel / Save', (
      tester,
    ) async {
      final h = await pumpDevices(tester, query: atBranch(SeedIds.maadi));
      await h.tap(find.text('Old counter iPad'));
      expect(find.text('Edit device'), findsOneWidget);
      expect(
        find.text("The code prefixes this device's order numbers, e.g. 36B-12."),
        findsOneWidget,
      );
      final code = tester.widget<DashTextField>(field('device-code'));
      expect(code.value, 'T9');
      expect(code.mono, isTrue);
      expect(code.maxLength, 6);
      expect(code.label, 'Code');
      final label = tester.widget<DashTextField>(field('device-label'));
      expect(label.value, 'Old counter iPad');
      expect(label.label, 'Name');
      expect(
        find.text(
          'Its code is freed for another device and it leaves the availability lists.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<DashSwitch>(find.byType(DashSwitch)).value, isTrue);
      expect(top('Cancel'), findsOneWidget);
      expect(top('Save'), findsOneWidget);
      await h.shot('devices/edit-dialog');
    });

    testWidgets('ADM-DEV-011 a code that is not 1–6 letters or digits is '
        'refused under the field', (tester) async {
      final h = await pumpDevices(tester, query: _zamalek);
      await h.tap(editButton(1));
      await h.enterText(field('device-code'), 'T-1');
      expect(find.text('1–6 letters or digits'), findsNothing);
      await h.tap(top('Save'));
      expect(find.text('1–6 letters or digits'), findsOneWidget);
      expect(h.server.callsTo(DevicesRoutes.device), isEmpty);
      // Re-checked as it changes; trimmed and uppercased before the check.
      await h.enterText(field('device-code'), ' t1 ');
      expect(find.text('1–6 letters or digits'), findsNothing);
      await h.enterText(field('device-code'), '');
      await h.tap(top('Save'));
      expect(find.text('1–6 letters or digits'), findsOneWidget);
      expect(h.server.callsTo(DevicesRoutes.device), isEmpty);
    });

    testWidgets('ADM-DEV-011 what is typed shows in capitals', (tester) async {
      final h = await pumpDevices(tester, query: _zamalek);
      await h.tap(editButton(1));
      await h.enterText(field('device-code'), 'b7');
      expect(tester.widget<DashTextField>(field('device-code')).value, 'B7');
    });

    testWidgets('ADM-DEV-012 Save sends {code, label, retired}; "Saved", '
        'closed, devices and tills refetched', (tester) async {
      final h = await pumpDevices(tester, query: _zamalek);
      final stale = watchInvalidations(h);
      final reads = h.server.callsTo(DevicesRoutes.devices).length;
      await h.tap(editButton(1));
      await h.enterText(field('device-code'), ' t5 ');
      await h.enterText(field('device-label'), '  Window  ');
      await h.tap(find.byKey(const ValueKey('device-retired')));
      await h.tap(top('Save'));
      final patch = h.server.callsTo(DevicesRoutes.device).single;
      expect(patch.method, 'PATCH');
      expect(patch.path, '/devices/${AdminSeed.deviceId('zamalek', 'T1')}');
      expect(patch.body, {'code': 'T5', 'label': 'Window', 'retired': true});
      expect(find.text('Edit device'), findsNothing);
      expect(stale, [
        ['/devices', '/tills'],
      ]);
      expect(h.server.callsTo(DevicesRoutes.devices).length, reads + 1);
      expect(find.text('T5'), findsOneWidget);
      expect(find.text('Retired'), findsOneWidget);
      await h.expectToast('Saved');
    });

    testWidgets('ADM-DEV-012 a blank name is sent as null', (tester) async {
      final h = await pumpDevices(tester, query: _zamalek);
      await h.tap(editButton(1));
      await h.enterText(field('device-label'), '   ');
      await h.tap(top('Save'));
      expect(h.server.callsTo(DevicesRoutes.device).single.body, {
        'code': 'T1',
        'label': null,
        'retired': false,
      });
      await h.expectToast('Saved');
      expect(find.text('Counter 1'), findsNothing);
    });

    testWidgets('ADM-DEV-012 a refusal (a code another device uses) toasts '
        'and keeps the dialog', (tester) async {
      final h = await pumpDevices(tester, query: _zamalek);
      await h.tap(editButton(1));
      await h.enterText(field('device-code'), 'K1');
      await h.tap(top('Save'));
      expect(h.server.callsTo(DevicesRoutes.device).single.status, 409);
      // The supplement's words when the tables have them, else the
      // server's sentence (never with its "Conflict: " kind).
      const key = 'errors.codes.DEVICE_CODE_TAKEN';
      expect(
        find.text(
          h.strings.exists('en', key)
              ? h.t(key)
              : 'Another device at this branch uses that code',
        ),
        findsOneWidget,
      );
      expect(find.text('Edit device'), findsOneWidget);
      expect(
        tester.widget<DashButton>(find.byKey(const ValueKey('device-save'))).loading,
        isFalse,
      );
      await h.flushTimers();
    });

    testWidgets('ADM-DEV-012 Save spins while the answer is on its way', (
      tester,
    ) async {
      final b = DevicesBackend();
      final gate = b.server.hold('PATCH', DevicesRoutes.device);
      final h = await pumpDevices(tester, query: _zamalek, backend: b);
      await h.tap(editButton(1));
      await h.tap(top('Save'));
      final save = find.byKey(const ValueKey('device-save'));
      expect(tester.widget<DashButton>(save).loading, isTrue);
      gate.release();
      await h.settle();
      expect(find.text('Edit device'), findsNothing);
      await h.expectToast('Saved');
    });

    testWidgets('ADM-DEV-013 till.open only: the list reads, Save is refused, '
        'no activation codes', (tester) async {
      final h = await pumpDevices(
        tester,
        persona: Persona.manager,
        query: _zamalek,
      );
      expect(deviceRows(), findsNWidgets(5));
      expect(find.text('Activation codes'), findsNothing);
      expect(h.server.callsTo(DevicesRoutes.codes), isEmpty);
      await h.tap(editButton(1));
      await h.tap(top('Save'));
      expect(h.server.callsTo(DevicesRoutes.device).single.status, 403);
      expect(
        find.text("You don't have permission to perform this action."),
        findsOneWidget,
      );
      expect(find.text('Edit device'), findsOneWidget);
      await h.flushTimers();
    });

    testWidgets('ADM-DEV-013 in Arabic the refusal reads in Arabic', (
      tester,
    ) async {
      final h = await pumpDevices(
        tester,
        persona: Persona.manager,
        query: _zamalek,
        locale: 'ar',
      );
      await h.tap(editButton(1, h.t('common.edit')));
      await h.tap(top(h.t('common.save')));
      expect(find.text(h.t('errors.unauthorized')), findsOneWidget);
      await h.flushTimers();
    });

    testWidgets('ADM-DEV-029 Escape, a tap outside, × and Cancel each close '
        'it; it re-fills on every open; no URL', (tester) async {
      final h = await pumpDevices(tester, query: _zamalek);
      final before = h.location;
      Future<void> open() async {
        await h.tap(editButton(1));
        expect(find.text('Edit device'), findsOneWidget);
        expect(h.location, before);
      }

      await open();
      await h.enterText(field('device-code'), 'ZZ');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(find.text('Edit device'), findsNothing);

      await open();
      expect(
        tester.widget<DashTextField>(field('device-code')).value,
        'T1',
        reason: 're-filled from the device',
      );
      await tester.tapAt(const Offset(8, 450));
      await h.settle();
      expect(find.text('Edit device'), findsNothing);

      await open();
      await h.tap(
        find.byWidgetPredicate(
          (w) => w is DashIconButton && w.semanticLabel == 'Close',
        ).hitTestable(),
      );
      expect(find.text('Edit device'), findsNothing);

      await open();
      await h.tap(top('Cancel'));
      expect(find.text('Edit device'), findsNothing);
      expect(h.server.callsTo(DevicesRoutes.device), isEmpty);
    });

    testWidgets('ADM-DEV-029 Cancel stays enabled while saving; the answer '
        'still lands', (tester) async {
      final b = DevicesBackend();
      final gate = b.server.hold('PATCH', DevicesRoutes.device);
      final h = await pumpDevices(tester, query: _zamalek, backend: b);
      await h.tap(editButton(1));
      await h.enterText(field('device-code'), 'T7');
      await h.tap(top('Save'));
      final cancel = tester.widget<DashButton>(
        find.byKey(const ValueKey('device-cancel')),
      );
      expect(cancel.onPressed, isNotNull);
      expect(cancel.loading, isFalse);
      await h.tap(top('Cancel'));
      expect(find.text('Edit device'), findsNothing);
      gate.release();
      await h.settle();
      expect(find.text('T7'), findsOneWidget);
      await h.expectToast('Saved');
    });
  });

  test('ADM-DEV-028 DevicesSearch.parse validates the URL', () {
    expect(
      DevicesSearch.parse({'view': 'clients', 'days': '30', 'all': 'true'}),
      const DevicesSearch(view: DevicesView.clients, days: 30, all: true),
    );
    expect(
      DevicesSearch.parse({'view': 'x', 'days': '5'}),
      const DevicesSearch(),
    );
    expect(DevicesSearch.parse({'all': 'yes'}).legacyOnly, isTrue);
    expect(DevicesSearch.parse({'days': '14'}).days, 14);
    expect(DevicesSearch.parse({}).effectiveDays, 14);
  });

  test('ADM-DEV-015 groupActivationCode', () {
    expect(groupActivationCode('40721958'), '4072 1958');
    expect(groupActivationCode('123'), '123');
  });
}
