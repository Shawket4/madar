// Smoke test for the onboarding unit: the page mounts through the real shell
// on the mock server (no unmatched route, no missing word, no overflow).
import 'package:dashboard_admin/dashboard_admin.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the set-up wizard opens full screen', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [adminArea],
      path: '/onboarding',
      persona: Persona.owner,
    );
    expect(h.location.path, '/onboarding');
    expect(find.text(h.t('onboarding.title')), findsWidgets);
    await h.shot('onboarding/scaffold');
  });
}
