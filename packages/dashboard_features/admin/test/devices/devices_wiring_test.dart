// The Devices page through the real `adminArea` (its route in routes.dart,
// its mocks in register.dart, its i18n supplements), not the test area.
import 'package:dashboard_admin/dashboard_admin.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('ADM-DEV-001 /devices opens through the admin area', (
    tester,
  ) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [adminArea],
      path: '/devices${atBranch(SeedIds.zamalek)}',
      persona: Persona.owner,
    );
    expect(deviceRows(), findsNWidgets(5));
    expect(codeCells(), findsNWidgets(4));
    expect(h.server.unmatched, isEmpty);
  });
}
