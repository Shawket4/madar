// Smoke: the unit's page(s) open through the real shell on the mock
// server, titled, at desktop (en, light) and phone (ar, dark).
import 'package:dashboard_api/mock.dart' show Persona;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_reports/dashboard_reports.dart';
import 'package:flutter_test/flutter_test.dart';

const _pages = [('Legal', '/reports/legal', 'reports.legal.title')];

const _looks = [(DashSize.desktop, 'en', false), (DashSize.phone, 'ar', true)];

void main() {
  for (final (name, path, titleKey) in _pages) {
    for (final (size, locale, dark) in _looks) {
      testWidgets('$name opens at $path (${size.name}, $locale)', (
        tester,
      ) async {
        final h = await DashHarness.pump(
          tester,
          areas: const [reportsArea],
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

  testWidgets('REP-LEG-001 the real area\'s route: the page\'s own gate, '
      'not the shell\'s', (tester) async {
    final route = reportsRoutes.singleWhere((r) => r.path == '/reports/legal');
    expect(route.caps, isEmpty);
    expect(route.module, isNull);
    final h = await DashHarness.pump(
      tester,
      areas: const [reportsArea],
      path: '/reports/legal',
      persona: Persona.limited,
    );
    expect(find.text(h.t('reports.noAccess')), findsOneWidget);
  });
}
