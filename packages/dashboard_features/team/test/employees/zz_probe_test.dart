import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('probe supplement', (tester) async {
    final h = await DashHarness.pump(tester, areas: const [teamArea], path: '/staff/employees');
    h.allowMissingKeys = true;
    // ignore: avoid_print
    print('PROBE en=${h.strings.exists('en', 'teamEmployees.chooseFile')} ar=${h.strings.exists('ar', 'teamEmployees.chooseFile')} langs=${h.strings.languages.toList()}');
  });
}
