// The branch dialog (ADM-BRA-020..038): its fields, what Save and Create
// send, the warehouse Type, the refusals and the re-seed from a refresh.
import 'package:dashboard_admin/src/branches/branch_dialog.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder _inDialog(Finder f) =>
    find.descendant(of: find.byType(BranchDialog), matching: f);

Finder _dialogText(String s) => _inDialog(find.text(s));

Finder _switch(String label) =>
    find.byWidgetPredicate((w) => w is DashSwitch && w.semanticLabel == label);

Future<void> _type(DashHarness h, String key, String text) =>
    h.enterText(field(key), text);

Future<void> _submit(DashHarness h) =>
    h.tapKey(const ValueKey('branch-submit'));

Future<void> _kind(DashHarness h, String label) => h.tap(
  find.descendant(of: field('branch-kind'), matching: find.text(label)),
);

Future<void> _printer(DashHarness h, String label) async {
  await h.tap(field('branch-printer-model'));
  await pick(h, label);
}

Map<String, Object?> _patch(DashHarness h) => lastBody(h.server, itemRoute);

Map<String, Object?> _post(DashHarness h) =>
    lastBody(h.server, listRoute, method: 'POST');

List<MockCall> _posts(DashHarness h) =>
    h.server.callsTo(listRoute, method: 'POST');

List<MockCall> _patches(DashHarness h) =>
    h.server.callsTo(itemRoute, method: 'PATCH');

Future<DashHarness> _edit(
  WidgetTester tester,
  String id, {
  Persona persona = Persona.owner,
  ({MockServer server, MockDb db})? s,
}) => pumpBranches(
  tester,
  path: '$branchesPath?edit=$id',
  persona: persona,
  server: s?.server,
  db: s?.db,
);

/// A platform admin with Sabah picked, on [path].
Future<DashHarness> _asPlatform(WidgetTester tester, String path) async {
  final h = await pumpBranches(tester, persona: Persona.platform);
  await h.container.read(selectedOrgProvider.notifier).select(SeedIds.sabahOrg);
  await h.settle();
  await h.go(path);
  return h;
}

void main() {
  testWidgets('ADM-BRA-020 the titles: New Branch, Edit Branch, and the '
      'warehouse ones following the Type live; the description', (
    tester,
  ) async {
    final h = await pumpBranches(tester, path: '$branchesPath?edit=new');
    expect(_dialogText('New Branch'), findsOneWidget);
    expect(
      _dialogText('Manage your branch locations and printer config'),
      findsOneWidget,
    );
    await _kind(h, 'Warehouse');
    expect(_dialogText('New warehouse'), findsOneWidget);
    await h.tapText('Cancel');
    await h.go('$branchesPath?edit=${SeedIds.zamalek}');
    expect(_dialogText('Edit Branch'), findsOneWidget);
    await _kind(h, 'Warehouse');
    expect(_dialogText('Edit warehouse'), findsOneWidget);
  });

  testWidgets('ADM-BRA-021 the name is required; "Warehouse name" for a '
      'warehouse', (tester) async {
    final h = await pumpBranches(tester, path: '$branchesPath?edit=new');
    expect(_dialogText('Branch Name'), findsOneWidget);
    await _submit(h);
    expect(_dialogText('This field is required'), findsOneWidget);
    expect(_posts(h), isEmpty);
    await _kind(h, 'Warehouse');
    expect(_dialogText('Warehouse name'), findsOneWidget);
  });

  testWidgets('ADM-BRA-022/026/023/029 a new branch: blank phone and address '
      'are null, Africa/Cairo, radius 200, the timezone list', (tester) async {
    final h = await pumpBranches(tester, path: '$branchesPath?edit=new');
    expect(h.server.callsTo(timezonesRoute), hasLength(1));
    expect(_dialogText('Africa/Cairo'), findsOneWidget);
    expect(
      _dialogText(
        'Optional. Used to auto-resolve which branch a device '
        'is at.',
      ),
      findsOneWidget,
    );
    expect(fieldText(tester, 'branch-radius'), '200');
    await _type(h, 'branch-name', 'Sheikh Zayed');
    await _type(h, 'branch-latitude', '30.0444');
    await _type(h, 'branch-longitude', '31.2357');
    await _submit(h);
    await h.expectToast('Branch created');
    final body = _post(h);
    expect(body['org_id'], SeedIds.sabahOrg);
    expect(body['kind'], 'branch');
    expect(body.containsKey('phone') && body['phone'] == null, isTrue);
    expect(body.containsKey('address') && body['address'] == null, isTrue);
    expect(body['timezone'], 'Africa/Cairo');
    expect(body['latitude'], 30.0444);
    expect(body['longitude'], 31.2357);
    expect(body['geo_radius_meters'], 200);
  });

  testWidgets('ADM-BRA-022/026 (divergence) emptying a stored phone or '
      'address clears it', (tester) async {
    final s = branchesServer();
    final h = await _edit(tester, SeedIds.zamalek, s: s);
    await _type(h, 'branch-phone', '');
    await _type(h, 'branch-address', '');
    await _submit(h);
    await h.expectToast('Branch updated');
    expect(_patch(h)['phone'], '');
    expect(_patch(h)['address'], '');
    expect(branchRow(s.db, SeedIds.zamalek)['address'], '');
  });

  testWidgets('ADM-BRA-023 another timezone from the searchable list', (
    tester,
  ) async {
    final h = await _edit(tester, SeedIds.zamalek);
    await h.tap(_dialogText('Africa/Cairo'));
    await h.enterText(find.byType(DashOptionList<String>), 'riyadh');
    await h.tapText('Asia/Riyadh');
    await _submit(h);
    expect(_patch(h)['timezone'], 'Asia/Riyadh');
    await h.flushTimers();
  });

  testWidgets('ADM-BRA-024 old bills: a whole number 1..168, default 3', (
    tester,
  ) async {
    final h = await _edit(tester, SeedIds.zamalek);
    expect(fieldText(tester, 'branch-old-bill-hours'), '3');
    await _type(h, 'branch-old-bill-hours', '200');
    await _submit(h);
    expect(_inDialog(find.textContaining('168')), findsWidgets);
    expect(_patches(h), isEmpty);
    await _type(h, 'branch-old-bill-hours', '12');
    await _submit(h);
    expect(_patch(h)['old_bill_hours'], 12);
    await h.flushTimers();
  });

  testWidgets('ADM-BRA-024 Enter in a number box submits, as in the web form', (
    tester,
  ) async {
    final h = await _edit(tester, SeedIds.zamalek);
    await _type(h, 'branch-old-bill-hours', '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    expect(_patch(h)['old_bill_hours'], 12);
    await h.flushTimers();
  });

  testWidgets('ADM-BRA-025 the drawer float in pounds, sent in piastres; '
      'blank is null', (tester) async {
    final s = branchesServer();
    final h = await _edit(tester, SeedIds.zamalek, s: s);
    final stored = branchRow(s.db, SeedIds.zamalek)['standard_float']! as num;
    final shown = fieldText(tester, 'branch-standard-float');
    expect(double.parse(shown.replaceAll(',', '')), stored / 100);
    await _type(h, 'branch-standard-float', '1500.5');
    await _submit(h);
    expect(_patch(h)['standard_float'], 150050);
    await h.flushTimers();
    await h.go('$branchesPath?edit=${SeedIds.maadi}');
    await _type(h, 'branch-standard-float', '');
    await _submit(h);
    final body = _patch(h);
    expect(body.containsKey('standard_float'), isTrue);
    expect(body['standard_float'], isNull);
    await h.flushTimers();
  });

  testWidgets('ADM-BRA-027/028 the printer: a model shows IP and Port; None '
      'sends brand, IP and port as null', (tester) async {
    final h = await pumpBranches(tester, path: '$branchesPath?edit=new');
    expect(_dialogText('Printer Configuration'), findsOneWidget);
    expect(_dialogText('None (no printer)'), findsOneWidget);
    expect(field('branch-printer-ip'), findsNothing);
    await _printer(h, 'Star TSP100');
    expect(fieldText(tester, 'branch-printer-port'), '9100');
    await _type(h, 'branch-printer-ip', '192.168.1.120');
    await _type(h, 'branch-name', 'Sheikh Zayed');
    await _submit(h);
    await h.expectToast('Branch created');
    expect(_post(h)['printer_brand'], 'star');
    expect(_post(h)['printer_ip'], '192.168.1.120');
    expect(_post(h)['printer_port'], 9100);

    await h.go('$branchesPath?edit=${SeedIds.zamalek}');
    await _printer(h, 'None (no printer)');
    expect(field('branch-printer-ip'), findsNothing);
    await _submit(h);
    final body = _patch(h);
    for (final k in ['printer_brand', 'printer_ip', 'printer_port']) {
      expect(body.containsKey(k), isTrue, reason: k);
      expect(body[k], isNull, reason: k);
    }
    await h.flushTimers();
  });

  testWidgets('ADM-BRA-030/031 a platform admin: the override switch, on '
      'sends percent as fractions', (tester) async {
    final h = await _asPlatform(
      tester,
      '$branchesPath?edit=${SeedIds.zamalek}',
    );
    expect(_dialogText('This branch taxes differently'), findsOneWidget);
    // Every seed branch carries its own rates: the switch is on.
    expect(
      tester.widget<DashSwitch>(_switch('This branch taxes differently')).value,
      isTrue,
    );
    await _type(h, 'branch-tax-rate', '5');
    await _type(h, 'branch-service-charge', '12');
    await h.tap(_switch('Menu prices include tax'));
    await _submit(h);
    final body = _patch(h);
    expect(body['tax_rate'], closeTo(0.05, 1e-9));
    expect(body['service_charge_rate'], closeTo(0.12, 1e-9));
    expect(body['tax_inclusive'], isFalse);
    expect(body['service_charge_taxable'], isTrue);
    await h.flushTimers();
  });

  testWidgets('ADM-BRA-031 the override off: all four sent as null', (
    tester,
  ) async {
    final h = await _asPlatform(
      tester,
      '$branchesPath?edit=${SeedIds.zamalek}',
    );
    await h.tap(_switch('This branch taxes differently'));
    expect(field('branch-tax-rate'), findsNothing);
    await _submit(h);
    final body = _patch(h);
    for (final k in [
      'tax_rate',
      'tax_inclusive',
      'service_charge_rate',
      'service_charge_taxable',
    ]) {
      expect(body.containsKey(k), isTrue, reason: k);
      expect(body[k], isNull, reason: k);
    }
    await h.flushTimers();
  });

  testWidgets('ADM-BRA-034 (divergence) a platform admin\'s override on a new '
      'branch rides the follow-up PATCH (the POST takes no rates)', (
    tester,
  ) async {
    final h = await _asPlatform(tester, '$branchesPath?edit=new');
    await _type(h, 'branch-name', 'Sheikh Zayed');
    await h.tap(_switch('This branch taxes differently'));
    await _type(h, 'branch-tax-rate', '5');
    await _submit(h);
    await h.expectToast('Branch created');
    expect(_post(h).containsKey('tax_rate'), isFalse);
    expect(_patch(h)['tax_rate'], closeTo(0.05, 1e-9));
    expect(_patch(h)['old_bill_hours'], 3);
  });

  testWidgets('ADM-BRA-030/031 an owner never sees the override; the stored '
      'rates go back unchanged', (tester) async {
    final s = branchesServer();
    final h = await _edit(tester, SeedIds.zamalek, s: s);
    expect(_dialogText('This branch taxes differently'), findsNothing);
    await _submit(h);
    final row = branchRow(s.db, SeedIds.zamalek);
    final body = _patch(h);
    expect(body['tax_rate'], row['tax_rate']);
    expect(body['tax_inclusive'], row['tax_inclusive']);
    expect(body['service_charge_rate'], row['service_charge_rate']);
    await h.flushTimers();
  });

  testWidgets('ADM-BRA-030 a warehouse never shows the override, even to a '
      'platform admin', (tester) async {
    final h = await _asPlatform(tester, '$branchesPath?edit=new-warehouse');
    expect(_dialogText('This branch taxes differently'), findsNothing);
    await _kind(h, 'Branch');
    expect(_dialogText('This branch taxes differently'), findsOneWidget);
  });

  testWidgets('ADM-BRA-032/033 Active (edit only) and Save: one PATCH, '
      '"Branch updated", the list asked again, closed', (tester) async {
    final s = branchesServer();
    final h = await _edit(tester, SeedIds.zamalek, s: s);
    expect(
      _dialogText('Inactive branches are hidden from the POS.'),
      findsOneWidget,
    );
    await _type(h, 'branch-name', 'Zamalek Riverside');
    await h.tap(_switch('Active'));
    final lists = h.server.callsTo(listRoute, method: 'GET').length;
    await _submit(h);
    await h.expectToast('Branch updated');
    expect(_patches(h), hasLength(1));
    final body = _patch(h);
    expect(body['name'], 'Zamalek Riverside');
    expect(body['is_active'], isFalse);
    expect(body.containsKey('kind'), isFalse, reason: 'Type unchanged');
    for (final k in [
      'address',
      'phone',
      'timezone',
      'printer_brand',
      'latitude',
      'geo_radius_meters',
      'old_bill_hours',
      'standard_float',
    ]) {
      expect(body.containsKey(k), isTrue, reason: k);
    }
    expect(find.byType(BranchDialog), findsNothing);
    expect(
      h.server.callsTo(listRoute, method: 'GET').length,
      greaterThan(lists),
    );
    expect(rowOf('Zamalek Riverside'), findsOneWidget);
    expect(branchRow(s.db, SeedIds.zamalek)['is_active'], isFalse);

    await h.go('$branchesPath?edit=new');
    expect(_switch('Active'), findsNothing);
  });

  testWidgets('ADM-BRA-033/038 a branch made a warehouse: kind sent, '
      'stored', (tester) async {
    final s = branchesServer();
    final row = addLocation(s.db, name: 'Abbasiya Kiosk', kind: 'branch');
    final h = await _edit(tester, row['id']! as String, s: s);
    await _kind(h, 'Warehouse');
    await _submit(h);
    await h.expectToast('Branch updated');
    expect(_patch(h)['kind'], 'warehouse');
    expect(branchRow(s.db, row['id']! as String)['kind'], 'warehouse');
    final pill = find.descendant(
      of: rowOf('Abbasiya Kiosk'),
      matching: find.byType(DashStatusPill),
    );
    expect(tester.widget<DashStatusPill>(pill.first).label, 'Warehouse');
  });

  testWidgets('ADM-BRA-033 a branch still selling: BRANCH_STILL_SELLING, '
      'the dialog stays', (tester) async {
    final h = await _edit(tester, SeedIds.zamalek);
    await _kind(h, 'Warehouse');
    await _submit(h);
    await h.expectToast(h.t('errors.codes.BRANCH_STILL_SELLING'));
    expect(_dialogText('Edit warehouse'), findsOneWidget);
  });

  testWidgets('ADM-BRA-033/034 over max_warehouses: WAREHOUSE_LIMIT on a '
      'switch and on a create', (tester) async {
    final s = branchesServer();
    addLocation(s.db);
    final kiosk = addLocation(s.db, name: 'Abbasiya Kiosk', kind: 'branch');
    maxWarehouses(s.db, 1);
    final h = await _edit(tester, kiosk['id']! as String, s: s);
    await _kind(h, 'Warehouse');
    await _submit(h);
    await h.expectToast(h.t('errors.codes.WAREHOUSE_LIMIT'));
    await h.tapText('Cancel');
    await h.go('$branchesPath?edit=new-warehouse');
    await _type(h, 'branch-name', 'Badr Warehouse');
    await _submit(h);
    await h.expectToast(h.t('errors.codes.WAREHOUSE_LIMIT'));
    expect(_dialogText('New warehouse'), findsOneWidget);
  });

  testWidgets('ADM-BRA-034 create: POST without till settings, then PATCH '
      'them onto the new branch', (tester) async {
    final h = await pumpBranches(tester, path: '$branchesPath?edit=new');
    await _type(h, 'branch-name', 'Sheikh Zayed');
    await _type(h, 'branch-old-bill-hours', '6');
    await _type(h, 'branch-standard-float', '2000');
    await _submit(h);
    await h.expectToast('Branch created');
    final post = _post(h);
    expect(post.containsKey('old_bill_hours'), isFalse);
    expect(post.containsKey('standard_float'), isFalse);
    final made = branchNamed(h.db!, 'Sheikh Zayed');
    expect(_patches(h).single.path, '/branches/${made['id']}');
    expect(_patch(h)['old_bill_hours'], 6);
    expect(_patch(h)['standard_float'], 200000);
    expect(rowOf('Sheikh Zayed'), findsOneWidget);
    expect(find.byType(BranchDialog), findsNothing);
  });

  testWidgets('ADM-BRA-034/038 a warehouse: one POST with kind, no till '
      'settings, no printer box, "Warehouse created"', (tester) async {
    final h = await pumpBranches(
      tester,
      path: '$branchesPath?edit=new-warehouse',
    );
    expect(field('branch-old-bill-hours'), findsNothing);
    expect(field('branch-standard-float'), findsNothing);
    expect(_dialogText('Printer Configuration'), findsNothing);
    await _type(h, 'branch-name', 'Badr Warehouse');
    await _submit(h);
    await h.expectToast('Warehouse created');
    expect(_post(h)['kind'], 'warehouse');
    expect(_patches(h), isEmpty);
    expect(stat(tester, 'Warehouses').value, 1);
  });

  testWidgets('ADM-BRA-035 while saving: the spinner, Cancel off; a failure '
      'toasts and the dialog stays', (tester) async {
    final s = branchesServer();
    final gate = s.server.hold('PATCH', itemRoute);
    final h = await _edit(tester, SeedIds.zamalek, s: s);
    await _submit(h);
    DashButton btn(String label) => tester.widget(
      _inDialog(
        find.byWidgetPredicate((w) => w is DashButton && w.label == label),
      ),
    );
    expect(btn('Save').loading, isTrue);
    expect(btn('Cancel').onPressed, isNull);
    gate.release();
    await h.settle();
    await h.expectToast('Branch updated');

    final boom = MockResponse.error(500, 'boom');
    s.server.fail('PATCH', itemRoute, boom);
    await h.go('$branchesPath?edit=${SeedIds.maadi}');
    await _submit(h);
    await h.expectToast(h.refusalWords(boom));
    expect(_dialogText('Edit Branch'), findsOneWidget);
    expect(btn('Cancel').onPressed, isNotNull);
  });

  testWidgets('ADM-BRA-036 (divergence) the till-settings PATCH fails after '
      'the POST: Create again retries the PATCH, no second branch', (
    tester,
  ) async {
    final s = branchesServer();
    final boom = MockResponse.error(500, 'boom');
    s.server.fail('PATCH', itemRoute, boom);
    final h = await pumpBranches(
      tester,
      path: '$branchesPath?edit=new',
      server: s.server,
      db: s.db,
    );
    await _type(h, 'branch-name', 'Sheikh Zayed');
    await _submit(h);
    await h.expectToast(h.refusalWords(boom));
    expect(_posts(h), hasLength(1));
    expect(rowOf('Sheikh Zayed'), findsOneWidget, reason: 'it exists');
    await _submit(h);
    await h.expectToast('Branch created');
    expect(_posts(h), hasLength(1));
    expect(_patches(h), hasLength(2));
    expect(_patches(h).first.path, _patches(h).last.path);
    expect(
      s.db['branches'].where((r) => r['name'] == 'Sheikh Zayed'),
      hasLength(1),
    );
  });

  testWidgets('ADM-BRA-037 (divergence) a cleared number box is null, not 0; '
      'the radius is required', (tester) async {
    final h = await _edit(tester, SeedIds.zamalek);
    await _type(h, 'branch-radius', '');
    await _type(h, 'branch-printer-port', '');
    await _submit(h);
    // A blank radius would send null, which the server keeps as the old one.
    expect(_patches(h), isEmpty);
    await _type(h, 'branch-radius', '150');
    await _submit(h);
    final body = _patch(h);
    expect(body['printer_port'], isNull);
    expect(body['geo_radius_meters'], 150);
    await h.flushTimers();
  });

  testWidgets('ADM-BRA-019/020 an edit whose branch leaves the list (deleted '
      'elsewhere) closes', (tester) async {
    final s = branchesServer();
    final h = await _edit(tester, SeedIds.zamalek, s: s);
    expect(find.byType(BranchDialog), findsOneWidget);
    s.db['branches'].removeWhere((r) => r['id'] == SeedIds.zamalek);
    h.container.read(realtimeBusProvider).invalidate(const ['/branches']);
    await h.settle();
    expect(find.byType(BranchDialog), findsNothing);
    expect(h.location.path, branchesPath);
    expect(h.location.queryParameters['edit'], isNull);
  });

  testWidgets('ADM-BRA-038 the Type: Branch / Warehouse, its hint, and the '
      'amber line when an edit changes it', (tester) async {
    final h = await _edit(tester, SeedIds.zamalek);
    expect(_dialogText('Type'), findsOneWidget);
    expect(
      _dialogText('Sells through tills and devices, and keeps its own stock.'),
      findsOneWidget,
    );
    expect(
      _inDialog(find.textContaining('It must have no open tills')),
      findsNothing,
    );
    await _kind(h, 'Warehouse');
    expect(
      _dialogText(
        'Holds stock and sends it to branches. It never sells: no '
        'tills, devices or menu.',
      ),
      findsOneWidget,
    );
    expect(
      _dialogText(
        'It must have no open tills, open orders or bills, and no '
        'paired devices. Its menu settings are kept for if you switch it '
        'back.',
      ),
      findsOneWidget,
    );
    expect(field('branch-old-bill-hours'), findsNothing);
    expect(_dialogText('Printer Configuration'), findsNothing);
    await _kind(h, 'Branch');
    expect(
      _inDialog(find.textContaining('It must have no open tills')),
      findsNothing,
    );
    expect(field('branch-old-bill-hours'), findsOneWidget);
  });

  testWidgets('ADM-BRA-038 a warehouse made a branch: the "Its stock stays" '
      'line, kind sent', (tester) async {
    final s = branchesServer();
    final w = addLocation(s.db);
    final h = await _edit(tester, w['id']! as String, s: s);
    expect(_dialogText('Edit warehouse'), findsOneWidget);
    await _kind(h, 'Branch');
    expect(
      _dialogText(
        'Its stock stays. Set up its menu, tills and devices to '
        'start selling.',
      ),
      findsOneWidget,
    );
    await _submit(h);
    await h.expectToast('Branch updated');
    expect(_patch(h)['kind'], 'branch');
  });

  testWidgets('an edit re-seeds from a refresh until it is changed', (
    tester,
  ) async {
    final s = branchesServer();
    final h = await _edit(tester, SeedIds.zamalek, s: s);
    final bus = h.container.read(realtimeBusProvider);
    branchRow(s.db, SeedIds.zamalek)['name'] = 'Zamalek Nile';
    bus.invalidate(const ['/branches']);
    await h.settle();
    expect(fieldText(tester, 'branch-name'), 'Zamalek Nile');
    await _type(h, 'branch-phone', '0227350000');
    branchRow(s.db, SeedIds.zamalek)['name'] = 'Zamalek Corniche';
    bus.invalidate(const ['/branches']);
    await h.settle();
    expect(fieldText(tester, 'branch-name'), 'Zamalek Nile');
    await _submit(h);
    expect(_patch(h)['name'], 'Zamalek Nile');
    await h.flushTimers();
  });
}
