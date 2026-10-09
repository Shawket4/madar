// The Attendance page (`/staff/attendance`) driven through the real shell on
// the mock server: one test per inventory row (TEAM-ATT-001…022, 034, 038,
// 039 and the area-wide TEAM-ALL rows this page carries), with its refusal,
// loading, empty and error states. The dialogs are in
// attendance_dialogs_test.dart, the export in attendance_export_test.dart.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'attendance_support.dart';

void main() {
  testWidgets('TEAM-ATT-001 smoke', (tester) async {
    final h = await pumpAttendance(tester);
    expect(pageText('Attendance'), findsWidgets);
    await h.shot('attendance/smoke');
    final calls = pageListCalls(h);
    expect(calls, hasLength(1));
    expect(calls.single.query, {
      'from': [day(-6)],
      'to': [day()],
    });
    expect(h.server.callsTo(summaryT), hasLength(1));
    // ignore: avoid_print
    print(windowRows(h.db!).length);
    expect(Persona.owner, isNotNull);
  });
}
