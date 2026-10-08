// Smoke test for the users unit: the page mounts through the real shell
// on the mock server (no unmatched route, no missing word, no overflow).
import 'package:dashboard_admin/dashboard_admin.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the Users page opens with the Access tabs', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [adminArea],
      path: '/access/users',
      persona: Persona.owner,
    );
    expect(h.location.path, '/access/users');
    expect(find.text(h.t('users.title')), findsWidgets);
    expect(find.text(h.t('nav.rolesPermissions')), findsOneWidget);
    expect(find.text(h.t('access.review.title')), findsOneWidget);
    await h.shot('users/scaffold');
  });
}
