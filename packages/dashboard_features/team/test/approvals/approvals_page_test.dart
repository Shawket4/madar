// Smoke test from the area scaffold: the approvals page opens through the
// real shell on the mock server. The unit's builder adds the driven tests.
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('approvals: /staff/approvals opens for the owner', (
    tester,
  ) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [teamArea],
      path: '/staff/approvals',
    );
    expect(h.location.path, '/staff/approvals');
    expect(find.text(h.t('dawam.approvals')), findsWidgets);
    await h.shot('scaffold');
  });
}
