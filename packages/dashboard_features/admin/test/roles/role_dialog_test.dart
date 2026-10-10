// The role dialog (ADM-ROL-017, 018, 023, 024): "New role" and "Rename
// role", driven through the Roles page on the mock server.
import 'package:dashboard_admin/src/mock/roles_mock.dart' show RolesSeed;
import 'package:dashboard_admin/src/roles/role_dialog.dart';
import 'package:dashboard_admin/src/roles/roles_data.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<DashHarness> _openNew(
  WidgetTester tester, {
  MockServer? server,
  MockDb? db,
  DashSize size = DashSize.desktop,
}) async {
  final h = await pumpRoles(tester, server: server, db: db, size: size);
  await h.tapKey(const ValueKey('roles-new'));
  expect(find.byType(RoleDialog), findsOneWidget);
  return h;
}

Future<void> _type(DashHarness h, String key, String text) =>
    h.enterText(field(key), text);

/// The labels the select [key] offers.
List<String> _options(WidgetTester tester, String key) => [
  for (final o in tester.widget<DashSelectField<String>>(field(key)).options)
    o.label,
];

void main() {
  testWidgets('ADM-ROL-017 New role: names, "Works like" (Cashier by '
      'default), "Start from" (the usual defaults + roles of that kind), '
      'no description', (tester) async {
    final h = await _openNew(tester);
    expect(inSurface('New role'), findsOneWidget);
    expect(inSurface('Name (English)'), findsOneWidget);
    expect(inSurface('Name (Arabic)'), findsOneWidget);
    expect(inSurface('Works like'), findsOneWidget);
    expect(inSurface('Start from'), findsOneWidget);
    expect(tester.widget<DashSurface>(surface).description, isNull);
    expect(
      tester.widget<DashSelectField<String>>(field('role-kind')).value,
      'teller',
    );
    expect(_options(tester, 'role-kind'), [
      'Branch manager',
      'Cashier',
      'Waiter',
      'Kitchen',
    ]);
    expect(_options(tester, 'role-copy-from'), [
      'The usual defaults',
      'Cashier',
      'Senior cashier',
    ]);
    await h.shot('roles/new-dialog');
  });

  testWidgets('ADM-ROL-017 names are required and at most 80 characters, '
      'trimmed (zod\'s words); nothing sent', (tester) async {
    final h = await _openNew(tester);
    await _type(h, 'role-name-en', '   ');
    await h.tapKey(const ValueKey('role-submit'));
    expect(
      inSurface('Too small: expected string to have >=1 characters'),
      findsNWidgets(2),
    );
    await _type(h, 'role-name-en', 'x' * 81);
    await _type(h, 'role-name-ar', 'مشرف الوردية');
    await h.tapKey(const ValueKey('role-submit'));
    expect(
      inSurface('Too big: expected string to have <=80 characters'),
      findsOneWidget,
    );
    await h.shot('roles/new-dialog-errors');
    expect(h.server.callsTo(rolesRoute, method: 'POST'), isEmpty);
  });

  testWidgets('ADM-ROL-017 Arabic: the names stay readable, the kinds and '
      'zod\'s words in Arabic', (tester) async {
    final h = await pumpRoles(tester, locale: 'ar');
    await h.tapKey(const ValueKey('roles-new'));
    expect(inSurface('دور جديد'), findsOneWidget);
    await h.tapKey(const ValueKey('role-submit'));
    expect(
      inSurface('قصير جدًا: يجب أن يحتوي على حرف واحد على الأقل'),
      findsNWidgets(2),
    );
    expect(_options(tester, 'role-kind'), [
      'مدير الفرع',
      'كاشير',
      'نادل',
      'المطبخ',
    ]);
  });

  testWidgets('ADM-ROL-018 Create: trimmed names, kind, copy_from null; '
      'closes, selects the new role and lists it', (tester) async {
    final h = await _openNew(tester);
    final lists = h.server.callsTo(rolesRoute, method: 'GET').length;
    await _type(h, 'role-name-en', '  Shift lead ');
    await _type(h, 'role-name-ar', 'مشرف الوردية');
    await h.tap(field('role-kind'));
    await pick(h, 'Branch manager');
    await h.tapKey(const ValueKey('role-submit'));
    expect(lastBody(h.server, rolesRoute, method: 'POST'), {
      'name_en': 'Shift lead',
      'name_ar': 'مشرف الوردية',
      'kind': 'branch_manager',
      'copy_from': null,
    });
    expect(find.byType(RoleDialog), findsNothing);
    final created = h.db!['roles'].rows.firstWhere(
      (r) => r['name_en'] == 'Shift lead',
    );
    expect(h.location.queryParameters['role'], created['id']);
    expect(
      h.server.callsTo(rolesRoute, method: 'GET').length,
      greaterThan(lists),
    );
    expect(inHeader('Shift lead'), findsOneWidget);
    expect(
      inHeader('Works like Branch manager on older tablets'),
      findsOneWidget,
    );
    expect(inHeader('Built in'), findsNothing);
    expect(
      tester.widget<DashListRow>(roleRow(created['id']! as String)).selected,
      isTrue,
    );
    expect(toasts, findsNothing);
  });

  testWidgets('ADM-ROL-018 Create starting from a role sends copy_from and '
      'copies its grants', (tester) async {
    final h = await _openNew(tester);
    await _type(h, 'role-name-en', 'Night cashier');
    await _type(h, 'role-name-ar', 'كاشير ليلي');
    await h.tap(field('role-copy-from'));
    await pick(h, 'Senior cashier');
    await h.tapKey(const ValueKey('role-submit'));
    expect(
      lastBody(h.server, rolesRoute, method: 'POST')['copy_from'],
      RolesSeed.seniorCashier,
    );
    // Senior cashier may void; the copy may too.
    expect(switchOf(tester, 'orders.void').value, isTrue);
  });

  testWidgets('ADM-ROL-018/023 a refused create toasts the server\'s words '
      'and keeps the dialog open', (tester) async {
    final s = rolesServer();
    final refusal = MockResponse.badRequest(
      'A role needs an English and an Arabic name',
    );
    s.server.fail('POST', rolesRoute, refusal);
    final h = await _openNew(tester, server: s.server, db: s.db);
    await _type(h, 'role-name-en', 'Shift lead');
    await _type(h, 'role-name-ar', 'مشرف الوردية');
    await h.tapKey(const ValueKey('role-submit'));
    await h.expectToast(shown(h, refusal));
    expect(find.byType(RoleDialog), findsOneWidget);
    expect(
      tester
          .widget<DashButton>(find.byKey(const ValueKey('role-submit')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('ADM-ROL-018 Rename: "Rename role", names only; PATCH '
      '{name_en, name_ar}; closes and selects it', (tester) async {
    final h = await pumpRoles(
      tester,
      path: '$rolesPath?role=${roleId('waiter')}',
    );
    await h.tapKey(const ValueKey('role-rename'));
    expect(inSurface('Rename role'), findsOneWidget);
    expect(field('role-kind'), findsNothing);
    expect(field('role-copy-from'), findsNothing);
    await h.shot('roles/rename-dialog');
    await _type(h, 'role-name-en', 'Floor staff ');
    await h.tapKey(const ValueKey('role-submit'));
    final call = h.server.callsTo(roleRoute, method: 'PATCH').single;
    expect(call.path, '/authz/roles/${roleId('waiter')}');
    expect(call.body, {'name_en': 'Floor staff', 'name_ar': 'نادل'});
    expect(find.byType(RoleDialog), findsNothing);
    expect(h.location.queryParameters['role'], roleId('waiter'));
    expect(inHeader('Floor staff'), findsOneWidget);
    expect(
      tester.widget<DashListRow>(roleRow(roleId('waiter'))).title,
      'Floor staff',
    );
  });

  testWidgets('ADM-ROL-018 the owner role can be renamed', (tester) async {
    final h = await pumpRoles(
      tester,
      path: '$rolesPath?role=${roleId('org_admin')}',
    );
    await h.tapKey(const ValueKey('role-rename'));
    await _type(h, 'role-name-en', 'Owner & founder');
    await h.tapKey(const ValueKey('role-submit'));
    expect(inHeader('Owner & founder'), findsOneWidget);
  });

  testWidgets('ADM-ROL-024 Save is disabled while it saves (no spinner); '
      'Cancel stays enabled and closing mid-save still selects the role', (
    tester,
  ) async {
    final s = rolesServer();
    final gate = s.server.hold('POST', rolesRoute);
    final h = await _openNew(tester, server: s.server, db: s.db);
    await _type(h, 'role-name-en', 'Shift lead');
    await _type(h, 'role-name-ar', 'مشرف الوردية');
    await h.tapKey(const ValueKey('role-submit'));
    final save = tester.widget<DashButton>(
      find.byKey(const ValueKey('role-submit')),
    );
    expect(save.onPressed, isNull);
    expect(save.loading, isFalse);
    await h.tap(inSurface('Cancel'));
    expect(find.byType(RoleDialog), findsNothing);
    gate.release();
    await h.settle();
    final created = s.db['roles'].rows.firstWhere(
      (r) => r['name_en'] == 'Shift lead',
    );
    expect(h.location.queryParameters['role'], created['id']);
    expect(roleRow(created['id']! as String), findsOneWidget);
  });

  testWidgets('ADM-ROL-024 (divergence) changing "Works like" drops a '
      '"Start from" of another kind', (tester) async {
    final h = await _openNew(tester);
    await h.tap(field('role-copy-from'));
    await pick(h, 'Senior cashier');
    await h.tap(field('role-kind'));
    await pick(h, 'Waiter');
    expect(
      tester.widget<DashSelectField<String>>(field('role-copy-from')).value,
      'none',
    );
    expect(
      find.descendant(
        of: field('role-copy-from'),
        matching: find.text('The usual defaults'),
      ),
      findsOneWidget,
    );
    await _type(h, 'role-name-en', 'Runner');
    await _type(h, 'role-name-ar', 'مساعد');
    await h.tapKey(const ValueKey('role-submit'));
    final body = lastBody(h.server, rolesRoute, method: 'POST');
    expect(body['kind'], 'waiter');
    expect(body['copy_from'], isNull);
  });

  testWidgets('ADM-ROL-024 the dialog starts blank each time it opens', (
    tester,
  ) async {
    final h = await _openNew(tester);
    await _type(h, 'role-name-en', 'Shift lead');
    await h.tap(field('role-kind'));
    await pick(h, 'Kitchen');
    await h.tap(inSurface('Cancel'));
    await h.tapKey(const ValueKey('roles-new'));
    expect(tester.widget<DashTextField>(field('role-name-en')).value, '');
    expect(
      tester.widget<DashSelectField<String>>(field('role-kind')).value,
      'teller',
    );
  });

  testWidgets('ADM-ROL-017 phone: the dialog is a full-screen sheet', (
    tester,
  ) async {
    await _openNew(tester, size: DashSize.phone);
    expect(
      tester.getSize(surface).width,
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
    );
    expect(inSurface('New role'), findsOneWidget);
  });

  testWidgets('ADM-ROL-018 a rename opened on old data takes the newer names '
      'until it is typed into', (tester) async {
    final h = await pumpRoles(
      tester,
      path: '$rolesPath?role=${roleId('waiter')}',
    );
    await h.tapKey(const ValueKey('role-rename'));
    h.db!['roles'].find(roleId('waiter'))!['name_en'] = 'Server';
    h.container.invalidate(accessRolesProvider);
    await h.settle();
    expect(tester.widget<DashTextField>(field('role-name-en')).value, 'Server');
    await _type(h, 'role-name-ar', 'نادل الصالة');
    h.db!['roles'].find(roleId('waiter'))!['name_en'] = 'Host';
    h.container.invalidate(accessRolesProvider);
    await h.settle();
    expect(tester.widget<DashTextField>(field('role-name-en')).value, 'Server');
  });
}
