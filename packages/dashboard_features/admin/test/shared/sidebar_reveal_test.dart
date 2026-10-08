// A deep link to a page low in the sidebar scrolls its row into view (the
// row is built even below the fold; a lazy list never built it).
import 'package:dashboard_admin/dashboard_admin.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opening /devices shows its row in the sidebar', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [adminArea],
      path: '/devices',
      persona: Persona.owner,
    );
    final sidebar = find.byType(DashSidebar);
    final row = find.descendant(
      of: sidebar,
      matching: find.text(h.t('nav.devices')),
    );
    expect(row, findsOneWidget);
    final view = tester.getRect(sidebar);
    final at = tester.getRect(row);
    expect(
      at.top >= view.top && at.bottom <= view.bottom,
      isTrue,
      reason: 'row $at outside the sidebar $view',
    );
  });
}
