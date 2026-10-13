// The owner's rule (2026-10-11): a filter carries through navigation. The
// admin pages' filters come back after another page: Devices' URL-held view
// (`DashRoute.rememberQuery`), a table's search (its page bucket) and
// Review's "Show reviewed" (`DashRememberedState`).
import 'package:dashboard_admin/dashboard_admin.dart';
import 'package:dashboard_admin/src/branches/branches_page.dart';
import 'package:dashboard_admin/src/devices/devices_page.dart';
import 'package:dashboard_admin/src/review/review_page.dart';
import 'package:dashboard_admin/src/users/users_page.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<DashHarness> _pump(WidgetTester tester, String path) =>
    DashHarness.pump(tester, areas: const [adminArea], path: path);

void main() {
  testWidgets('devices: ?view=clients comes back on a bare /devices', (
    tester,
  ) async {
    final h = await _pump(tester, '${DevicesPage.path}?view=clients&all=true');
    await h.go(UsersPage.path);
    await h.go(DevicesPage.path);
    expect(h.location.queryParameters, {'view': 'clients', 'all': 'true'});
  });

  testWidgets('users: the table search comes back', (tester) async {
    final h = await _pump(tester, UsersPage.path);
    final search = find.descendant(
      of: find.byType(UsersPage),
      matching: find.byType(DashSearchInput),
    );
    await h.enterText(search, 'karim');
    await tester.pump(const Duration(milliseconds: 400));
    await h.settle();
    await h.go(BranchesPage.path);
    await h.go(UsersPage.path);
    expect(tester.widget<DashSearchInput>(search).value, 'karim');
  });

  testWidgets('review: Show reviewed comes back', (tester) async {
    final h = await _pump(tester, ReviewPage.path);
    final toggle = find.byKey(const ValueKey('review-show-reviewed'));
    await h.tap(toggle);
    expect(tester.widget<DashSwitch>(toggle).value, isTrue);
    await h.go(UsersPage.path);
    await h.go(ReviewPage.path);
    expect(tester.widget<DashSwitch>(toggle).value, isTrue);
  });
}
