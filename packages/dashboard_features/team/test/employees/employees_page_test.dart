// Smoke test from the area scaffold: the employees page opens through the
// real shell on the mock server. The unit's builder adds the driven tests.
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('employees: /staff/employees opens for the owner', (
    tester,
  ) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [teamArea],
      path: '/staff/employees',
    );
    expect(h.location.path, '/staff/employees');
    expect(find.text(h.t('staff.employees')), findsWidgets);
    await h.shot('scaffold');
  });
}
