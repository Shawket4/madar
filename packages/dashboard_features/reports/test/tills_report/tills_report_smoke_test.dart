// Smoke: the unit's page(s) open through the real shell on the mock
// server, titled, at desktop (en, light) and phone (ar, dark). Mounted as
// this unit's own area, so another unit's work in progress never stops it.
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _pages = [('Till sessions', '/reports/tills', 'reports.tills.title')];

const _looks = [(DashSize.desktop, 'en', false), (DashSize.phone, 'ar', true)];

void main() {
  for (final (name, path, titleKey) in _pages) {
    for (final (size, locale, dark) in _looks) {
      testWidgets('$name opens at $path (${size.name}, $locale)', (
        tester,
      ) async {
        final h = await DashHarness.pump(
          tester,
          areas: const [tillsArea],
          path: path,
          size: size,
          locale: locale,
          dark: dark,
        );
        expect(h.location.path, path);
        expect(find.text(h.t(titleKey)), findsWidgets);
        await h.shot('smoke');
      });
    }
  }
}
