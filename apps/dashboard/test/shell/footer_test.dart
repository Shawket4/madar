// The frame's foot: "Powered by Madar" on a shop's own branding leads to
// Madar POS's site (app-footer.tsx), and the copyright names Cairo's year in
// the page's numerals (shared/dates.ts `currentYear`).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('Powered by Madar opens Madar POS site, in the page language', (
    tester,
  ) async {
    // Sabah Coffee is on its own branding.
    final h = await pumpShell(tester);
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

  testWidgets('the copyright year in Arabic numerals on an Arabic page', (
    tester,
  ) async {
    final h = await pumpShell(tester, locale: 'ar');
    final year = h.container.read(copyrightYearProvider);
    expect(year, matches(RegExp(r'^[٠-٩]{4}$')));
    expect(find.textContaining(year), findsWidgets);
  });
}
