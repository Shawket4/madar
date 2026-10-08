// Smoke test for the roles unit: the page mounts through the real shell
// on the mock server (no unmatched route, no missing word, no overflow).
import 'package:dashboard_admin/dashboard_admin.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the Roles & Permissions page opens', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [adminArea],
      path: '/access/roles',
      persona: Persona.owner,
    );
    expect(h.location.path, '/access/roles');
    expect(find.text(h.t('nav.rolesPermissions')), findsWidgets);
    await h.shot('roles/scaffold');
  });

  testWidgets('without the read capabilities: the Access tabs over a lock '
      '(ADM-ROL-001)', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [adminArea],
      path: '/access/roles',
      persona: Persona.limited,
    );
    expect(find.text(h.t('common.restrictedTitle')), findsOneWidget);
    expect(find.text(h.t('access.noAccess')), findsOneWidget);
    expect(find.text(h.t('nav.users')), findsWidgets);
    expect(h.server.callsTo('/authz/roles'), isEmpty);
  });
}
