// The user dialog (ADM-USR-020..032, 053, 054): fields, role rules, both
// credentials, the PIN generator, create / edit payloads and the server's
// refusals.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show selectedOrgProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<DashHarness> _new(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  MockServer? server,
  MockDb? db,
  String locale = 'en',
}) => pumpUsers(
  tester,
  path: '$usersPath?edit=new',
  persona: persona,
  server: server,
  db: db,
  locale: locale,
);

Future<void> _type(DashHarness h, String key, String text) =>
    h.enterText(field(key), text);

Future<void> _role(DashHarness h, String label) async {
  await h.tap(field('user-role'));
  await pick(h, label);
}

List<String> _roleOptions(WidgetTester tester) => [
  for (final o
      in tester
          .widget<DashSelectField<Object?>>(
            find.byWidgetPredicate(
              (w) =>
                  w is DashSelectField && w.key == const ValueKey('user-role'),
            ),
          )
          .options)
    o.label,
];

void main() {
  testWidgets('ADM-USR-020 New User: title, description, role Teller, '
      'blank credentials', (tester) async {
    await _new(tester);
    expect(inSurface('New User'), findsOneWidget);
    expect(inSurface('Manage staff accounts and access'), findsOneWidget);
    expect(inSurface('Teller'), findsOneWidget);
    expect(fieldText(tester, 'user-name'), '');
    expect(fieldText(tester, 'user-pin'), '');
    expect(fieldText(tester, 'user-password'), '');
    expect(field('user-active'), findsNothing);
  });

  testWidgets('ADM-USR-020 Edit User: the person\'s values, PIN and password '
      'blank', (tester) async {
    await pumpUsers(tester, path: '$usersPath?edit=${uid('karim')}');
    expect(inSurface('Edit User'), findsOneWidget);
    expect(fieldText(tester, 'user-name'), 'Karim Adel');
    expect(fieldText(tester, 'user-email'), 'karim@sabah.test');
    expect(fieldText(tester, 'user-phone'), '+201002223344');
    expect(inSurface('Branch Manager'), findsOneWidget);
    expect(fieldText(tester, 'user-pin'), '');
    expect(fieldText(tester, 'user-password'), '');
  });

  testWidgets('ADM-USR-021 Full Name is required', (tester) async {
    final h = await _new(tester);
    await _type(h, 'user-pin', '135790');
    await h.tapKey(const ValueKey('user-submit'));
    expect(inSurface('This field is required'), findsOneWidget);
    expect(h.server.callsTo(listRoute, method: 'POST'), isEmpty);
  });

  testWidgets('ADM-USR-022 role options by the viewer\'s role', (tester) async {
    await _new(tester);
    expect(_roleOptions(tester), [
      'Organization Admin',
      'Branch Manager',
      'Teller',
      'Waiter',
      'Kitchen',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await _new(tester, persona: Persona.manager);
    expect(_roleOptions(tester), ['Teller', 'Waiter', 'Kitchen']);
  });

  testWidgets('ADM-USR-022/023 a platform admin: every role, the '
      'Organization select (current org first), Phone on its own row', (
    tester,
  ) async {
    final h = await pumpUsers(tester, persona: Persona.platform);
    await h.container
        .read(selectedOrgProvider.notifier)
        .select(SeedIds.sabahOrg);
    await h.settle();
    await h.go('$usersPath?edit=new');
    expect(_roleOptions(tester).first, 'Super Admin');
    expect(_roleOptions(tester), hasLength(6));
    expect(h.server.callsTo('/orgs', method: 'GET'), isNotEmpty);
    expect(inSurface('Organization'), findsOneWidget);
    expect(inSurface('Sabah Coffee'), findsOneWidget);
    await h.tap(field('user-org'));
    await pick(h, 'Layali Bistro');
    await _type(h, 'user-name', 'Rasha Kamal');
    await _type(h, 'user-pin', '864201');
    await h.tapKey(const ValueKey('user-submit'));
    await h.expectToast('User created');
    expect(
      lastBody(h.server, listRoute, method: 'POST')['org_id'],
      isNot(SeedIds.sabahOrg),
    );
  });

  testWidgets('ADM-USR-023 editing as a platform admin: no Organization', (
    tester,
  ) async {
    final h = await pumpUsers(tester, persona: Persona.platform);
    await h.container
        .read(selectedOrgProvider.notifier)
        .select(SeedIds.sabahOrg);
    await h.settle();
    await h.go('$usersPath?edit=${uid('karim')}');
    expect(inSurface('Edit User'), findsOneWidget);
    expect(field('user-org'), findsNothing);
  });

  testWidgets('ADM-USR-024 the PIN: label by role, digits only, six at most, '
      'six exactly, required for a new till role', (tester) async {
    final h = await _new(tester);
    expect(inSurface('PIN (6 digits)'), findsOneWidget);
    await _type(h, 'user-name', 'Sara Lotfy');
    await h.tapKey(const ValueKey('user-submit'));
    expect(inSurface('PIN is required'), findsOneWidget);
    await _type(h, 'user-pin', '12a4');
    expect(fieldText(tester, 'user-pin'), '124');
    await h.tapKey(const ValueKey('user-submit'));
    expect(inSurface('PIN must be 6 digits'), findsOneWidget);
    await _type(h, 'user-pin', '12345678');
    expect(fieldText(tester, 'user-pin').length, lessThanOrEqualTo(6));
    await _role(h, 'Branch Manager');
    expect(inSurface('Till PIN (optional)'), findsOneWidget);
  });

  testWidgets('ADM-USR-024 editing: the PIN shows ••••••', (tester) async {
    await pumpUsers(tester, path: '$usersPath?edit=${uid('mariam')}');
    expect(inSurface('••••••'), findsOneWidget);
  });

  testWidgets('ADM-USR-025 Generate fills a PIN nobody uses', (tester) async {
    final h = await _new(tester);
    await h.tapKey(const ValueKey('user-generate-pin'));
    expect(h.server.callsTo(pinRoute), hasLength(1));
    final pin = fieldText(tester, 'user-pin');
    expect(pin, matches(RegExp(r'^\d{6}$')));
    expect(sabahStaff.map((p) => p.pin), isNot(contains(pin)));
  });

  testWidgets('ADM-USR-025 Generate: spinner, then a failure toast', (
    tester,
  ) async {
    final s = usersServer();
    final gate = s.server.hold('GET', pinRoute);
    final h = await _new(tester, server: s.server, db: s.db);
    await h.tapKey(const ValueKey('user-generate-pin'));
    final btn = tester.widget<DashButton>(field('user-generate-pin'));
    expect(btn.loading, isTrue);
    s.server.clearFailures();
    final refusal = MockResponse.badRequest('Choose an organization first');
    s.server.fail('GET', pinRoute, refusal);
    gate.release();
    await h.settle();
    // The held call answers from the handler; ask again for the refusal.
    await h.tapKey(const ValueKey('user-generate-pin'));
    await h.expectToast(shown(h, refusal));
  });

  testWidgets('ADM-USR-026 email: optional for a till role, required for '
      'others, checked when typed', (tester) async {
    final h = await _new(tester);
    expect(inSurface('Email (optional)'), findsOneWidget);
    await _type(h, 'user-name', 'Sara Lotfy');
    await _type(h, 'user-pin', '135790');
    await _type(h, 'user-email', 'sara@');
    await h.tapKey(const ValueKey('user-submit'));
    expect(inSurface('Invalid email'), findsOneWidget);
    await _type(h, 'user-email', '');
    await _type(h, 'user-password', 'Latte2026!');
    await h.tapKey(const ValueKey('user-submit'));
    expect(inSurface('Email is required'), findsOneWidget);
    await _role(h, 'Branch Manager');
    expect(inSurface('Email address'), findsOneWidget);
    expect(h.server.callsTo(listRoute, method: 'POST'), isEmpty);
  });

  testWidgets('ADM-USR-027 password: required for a new manager, "Leave '
      'blank to keep" when editing', (tester) async {
    final h = await _new(tester);
    expect(inSurface('Password (optional)'), findsOneWidget);
    await _role(h, 'Branch Manager');
    expect(inSurface('Password'), findsOneWidget);
    await _type(h, 'user-name', 'Sara Lotfy');
    await _type(h, 'user-email', 'sara@sabah.test');
    await h.tapKey(const ValueKey('user-submit'));
    expect(inSurface('Password is required'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpUsers(tester, path: '$usersPath?edit=${uid('karim')}');
    expect(inSurface('Leave blank to keep'), findsOneWidget);
  });

  testWidgets('ADM-USR-028 the credentials hint follows the role', (
    tester,
  ) async {
    final h = await _new(tester);
    expect(inSurface(h.t('users.posCredHint2')), findsOneWidget);
    await _role(h, 'Organization Admin');
    expect(inSurface(h.t('users.dashCredHint2')), findsOneWidget);
  });

  testWidgets('ADM-USR-029 Active Account only when editing', (tester) async {
    await pumpUsers(tester, path: '$usersPath?edit=${uid('mariam')}');
    expect(inSurface('Active Account'), findsOneWidget);
    expect(inSurface('Inactive users cannot log in'), findsOneWidget);
  });

  testWidgets('ADM-USR-030 Create: the body, refetch, toast, close; the new '
      'person is listed', (tester) async {
    final h = await _new(tester);
    final before = h.server.callsTo(listRoute, method: 'GET').length;
    await _type(h, 'user-name', 'Sara Lotfy');
    await _type(h, 'user-pin', '135790');
    await _type(h, 'user-email', 'sara@sabah.test');
    await _type(h, 'user-password', 'Latte2026!');
    await h.tapKey(const ValueKey('user-submit'));
    await h.expectToast('User created');
    expect(lastBody(h.server, listRoute, method: 'POST'), {
      'name': 'Sara Lotfy',
      'role': 'teller',
      'org_id': SeedIds.sabahOrg,
      'email': 'sara@sabah.test',
      'phone': null,
      'pin': '135790',
      'password': 'Latte2026!',
    });
    expect(surface, findsNothing);
    expect(h.location.queryParameters.containsKey('edit'), isFalse);
    expect(h.server.callsTo(listRoute, method: 'GET').length, before + 1);
    expect(stat(tester, 'Total Users').value, 17);
    expect(stat(tester, 'Tellers').value, 9);
  });

  testWidgets('ADM-USR-031 Save Changes: blank credentials are left out', (
    tester,
  ) async {
    final h = await pumpUsers(tester, path: '$usersPath?edit=${uid('mariam')}');
    expect(inSurface('Save Changes'), findsOneWidget);
    await _type(h, 'user-phone', '+201110001112');
    await h.tap(
      find.descendant(
        of: field('user-active'),
        matching: find.byType(DashSwitch),
      ),
    );
    await h.tapKey(const ValueKey('user-submit'));
    await h.expectToast('User updated');
    expect(lastBody(h.server, itemRoute, method: 'PATCH'), {
      'name': 'Mariam Fathy',
      'email': null,
      'phone': '+201110001112',
      'role': 'teller',
      'is_active': false,
    });
    expect(surface, findsNothing);
    final row = rowOf('Mariam Fathy').first;
    expect(
      find.descendant(of: row, matching: find.text('Inactive')),
      findsOneWidget,
    );
  });

  testWidgets('ADM-USR-031 a new PIN and password are sent when typed', (
    tester,
  ) async {
    final h = await pumpUsers(tester, path: '$usersPath?edit=${uid('karim')}');
    await _type(h, 'user-pin', '246802');
    await _type(h, 'user-password', 'NewPass2026!');
    await h.tapKey(const ValueKey('user-submit'));
    await h.expectToast('User updated');
    final body = lastBody(h.server, itemRoute, method: 'PATCH');
    expect(body['pin'], '246802');
    expect(body['password'], 'NewPass2026!');
  });

  testWidgets('ADM-USR-032 a refusal toasts, the dialog stays, Create spins '
      'meanwhile', (tester) async {
    final s = usersServer();
    final gate = s.server.hold('POST', listRoute);
    final h = await _new(tester, server: s.server, db: s.db);
    await _type(h, 'user-name', 'Sara Lotfy');
    // Mariam's PIN.
    await _type(h, 'user-pin', '482915');
    await h.tapKey(const ValueKey('user-submit'));
    expect(tester.widget<DashButton>(field('user-submit')).loading, isTrue);
    gate.release();
    await h.settle();
    await h.expectToast(
      shown(
        h,
        MockResponse.conflict(
          'Someone in this organization already uses that PIN',
        ),
      ),
    );
    expect(inSurface('New User'), findsOneWidget);
    expect(tester.widget<DashButton>(field('user-submit')).loading, isFalse);
  });

  testWidgets('ADM-USR-053 a role outside the viewer\'s options: an empty '
      'select, the stored role sent back', (tester) async {
    final h = await pumpUsers(
      tester,
      persona: Persona.manager,
      path: '$usersPath?edit=${uid('karim')}',
    );
    expect(inSurface('Branch Manager'), findsNothing);
    await h.tapKey(const ValueKey('user-submit'));
    await h.expectToast('User updated');
    expect(
      lastBody(h.server, itemRoute, method: 'PATCH')['role'],
      'branch_manager',
    );
  });

  testWidgets('ADM-USR-054 the server\'s refusals, in its words', (
    tester,
  ) async {
    final h = await _new(tester);
    await _role(h, 'Branch Manager');
    await _type(h, 'user-name', 'Nour Again');
    await _type(h, 'user-email', 'nour@sabah.test');
    await _type(h, 'user-password', 'Latte2026!');
    await h.tapKey(const ValueKey('user-submit'));
    await h.expectToast(
      shown(h, MockResponse.conflict('Email already in use')),
    );
    await _role(h, 'Teller');
    await _type(h, 'user-name', 'Mariam Fathy');
    await _type(h, 'user-email', '');
    await _type(h, 'user-password', '');
    await _type(h, 'user-pin', '975310');
    await h.tapKey(const ValueKey('user-submit'));
    await h.expectToast(
      shown(
        h,
        MockResponse.conflict(
          'A teller, waiter or kitchen user with this name already exists '
          'in this organization',
        ),
      ),
    );
  });

  testWidgets('ADM-USR-054 deactivating yourself is refused: '
      '"You don\'t have permission…"', (tester) async {
    final h = await pumpUsers(tester, path: '$usersPath?edit=${SeedIds.owner}');
    await h.tap(
      find.descendant(
        of: field('user-active'),
        matching: find.byType(DashSwitch),
      ),
    );
    await h.tapKey(const ValueKey('user-submit'));
    await h.expectToast(h.t('errors.unauthorized'));
    expect(inSurface('Edit User'), findsOneWidget);
  });

  testWidgets('ADM-USR-021..027 (divergence) every check shows on the first '
      'Create: a blank name and a missing PIN together', (tester) async {
    final h = await _new(tester);
    await h.tapKey(const ValueKey('user-submit'));
    expect(inSurface('This field is required'), findsOneWidget);
    expect(inSurface('PIN is required'), findsOneWidget);
    expect(h.server.callsTo(listRoute, method: 'POST'), isEmpty);
  });

  testWidgets('ADM-USR-053 Cancel stays enabled while saving and closes the '
      'dialog', (tester) async {
    final s = usersServer();
    final gate = s.server.hold('POST', listRoute);
    final h = await _new(tester, server: s.server, db: s.db);
    final lists = h.server.callsTo(listRoute, method: 'GET').length;
    await _type(h, 'user-name', 'Sara Lotfy');
    await _type(h, 'user-pin', '135790');
    await h.tapKey(const ValueKey('user-submit'));
    expect(tester.widget<DashButton>(field('user-submit')).loading, isTrue);
    final cancel = find.descendant(
      of: surface,
      matching: find.byWidgetPredicate(
        (w) => w is DashButton && w.label == 'Cancel',
      ),
    );
    expect(tester.widget<DashButton>(cancel).onPressed, isNotNull);
    await h.tap(cancel);
    expect(surface, findsNothing);
    gate.release();
    await h.settle();
    // The call still lands (the web does not stop it either).
    expect(h.server.callsTo(listRoute, method: 'POST').single.status, 201);
    expect(h.server.callsTo(listRoute, method: 'GET').length, lists + 1);
    expect(stat(tester, 'Total Users').value, 17);
    await h.flushTimers();
  });

  testWidgets('ADM-USR-053 Full Name is sent as typed (not trimmed)', (
    tester,
  ) async {
    final h = await _new(tester);
    await _type(h, 'user-name', '  Sara Lotfy ');
    await _type(h, 'user-pin', '135790');
    await h.tapKey(const ValueKey('user-submit'));
    await h.expectToast('User created');
    expect(
      lastBody(h.server, listRoute, method: 'POST')['name'],
      '  Sara Lotfy ',
    );
  });

  testWidgets('ADM-USR-053 (divergence) the Phone box reads left to right in '
      'Arabic', (tester) async {
    await pumpUsers(
      tester,
      locale: 'ar',
      path: '$usersPath?edit=${uid('karim')}',
    );
    final phone = tester.widget<EditableText>(
      find.descendant(
        of: field('user-phone'),
        matching: find.byType(EditableText),
      ),
    );
    expect(phone.textDirection, TextDirection.ltr);
    expect(phone.controller.text, '+201002223344');
  });
}
