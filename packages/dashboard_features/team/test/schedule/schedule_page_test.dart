// The Schedule page (`/staff/schedule`): one driven test per TEAM-SCH row
// of the page itself (the week bar, the grid, open shifts, suggestions,
// holidays), on the real shell and the seeded mock server.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schedule_support.dart';

void main() {
  testWidgets('TEAM-SCH-002/016 the owner opens Zamalek\'s week', (
    tester,
  ) async {
    final h = await pumpSchedule(tester);
    expect(h.location.path, schedulePath);
    expect(pageText('Schedule'), findsWidgets);
    expect(inGrid(find.text('Youssef Samir')), findsOneWidget);
    await h.shot('schedule/smoke');
  });

  testWidgets('smoke: phone', (tester) async {
    final h = await pumpSchedule(tester, size: DashSize.phone, locale: 'ar');
    expect(inGrid(find.text('Youssef Samir')), findsOneWidget);
    await h.shot('schedule/smoke');
    expect(SeedIds.zamalek, isNotEmpty);
  });
}
