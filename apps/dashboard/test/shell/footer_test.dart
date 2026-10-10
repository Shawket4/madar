// The frame's foot: "Powered by Madar" on a shop's own branding leads to
// Madar POS's site (app-footer.tsx), and the copyright names Cairo's year in
// the page's numerals (shared/dates.ts `currentYear`).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('ADM-APP-028: Powered by Madar opens Madar POS site, in the '
      'page language', (tester) async {
    // Sabah Coffee is on its own branding. A page that fits the window shows
    // the foot at once.
    final h = await pumpShell(tester, path: '/nowhere');
    await h.tapText('Powered by Madar');
    expect(
      h.openedLinks.single.toString(),
      'https://get.madar-pos.cloud/en/?utm_source=dashboard'
      '&utm_medium=powered_by&utm_campaign=dashboard',
    );
    h.db!['orgs'].update(SeedIds.sabahOrg, {'custom_branding': false});
    h.container.invalidate(publicBrandProvider);
    await h.settle();
    expect(text('Powered by Madar'), findsNothing);
  });

  testWidgets('ADM-APP-014 ADM-APP-028: the copyright year in Arabic '
      'numerals on an Arabic page', (tester) async {
    final h = await pumpShell(tester, path: '/nowhere', locale: 'ar');
    final year = h.container.read(copyrightYearProvider);
    expect(year, matches(RegExp(r'^[٠-٩]{4}$')));
    expect(find.textContaining(year), findsWidgets);
  });

  testWidgets('ADM-APP-028: on a wide window the foot follows the page: seen '
      'at its end, not pinned', (tester) async {
    final h = await pumpShell(tester);
    // The home page is longer than the window.
    expect(text('Powered by Madar'), findsNothing);
    final page = find
        .descendant(
          of: find.byType(DashRouteHost),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first;
    await tester.drag(page, const Offset(0, -20000));
    await h.settle();
    expect(text('Powered by Madar'), findsOneWidget);
    await tester.drag(page, const Offset(0, 20000));
    await h.settle();
    expect(text('Powered by Madar'), findsNothing);
  });
}
