// Smoke test from the area scaffold: the requests page opens through the
// real shell on the mock server. The unit's builder adds the driven tests.
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('requests: /staff/requests opens for the owner', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [teamArea],
      path: '/staff/requests',
    );
    expect(h.location.path, '/staff/requests');
    expect(find.text(h.t('staff.requests')), findsWidgets);
    await h.shot('scaffold');
  });
}
