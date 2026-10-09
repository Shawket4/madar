// Smoke: the unit's page(s) open through the real shell on the mock
// server, titled, at desktop (en, light) and phone (ar, dark).
import 'package:dashboard_api/dashboard_api.dart' show MyAuthz;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show Cap;
import 'package:dashboard_core/shell.dart' show DashSidebar, PrefetchOnIntent;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_reports/dashboard_reports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'legal_support.dart';

/// Every sidebar leaf's path (the "n more" folds opened first).
Future<List<String>> _leaves(DashHarness h) async {
  final more = find.descendant(
    of: find.byType(DashSidebar),
    matching: find.textContaining(RegExp(r'^\d+ more$')),
  );
  while (more.evaluate().isNotEmpty) {
    await h.tap(more.first);
  }
  return [
    for (final w in h.tester.widgetList<PrefetchOnIntent>(
      find.descendant(
        of: find.byType(DashSidebar),
        matching: find.byType(PrefetchOnIntent),
      ),
    ))
      w.to,
  ];
}

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

  testWidgets('REP-LEG-001 / REP-ALL-002 the sidebar follows reports.legal: '
      'an owner without it has no Legal leaf (Operations kept), and a direct '
      'link meets the page\'s own Restricted, asking nothing', (tester) async {
    final s = legalServer();
    final persona = Persona.owner;
    s.server.on('GET', '/authz/me', (req) {
      final caps = [
        for (final c in persona.capabilities)
          if (c != Cap.reportsLegal) c,
      ]..sort();
      return MockResponse.ok(
        MyAuthz(
          userId: persona.userId,
          branchId: req.q('branch_id'),
          capabilities: caps,
          everywhere: persona.branchIds == null ? caps : const [],
          askManager: const [],
          limits: const {},
          owner: false,
          platform: false,
          roleKinds: persona.roleKinds,
          epoch: 1,
          specVersion: 2,
        ),
      );
    });
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    final leaves = await _leaves(h);
    expect(leaves, contains('/reports/operations'));
    expect(leaves, isNot(contains('/reports/legal')));
    expect(find.text(h.t('reports.noAccess')), findsOneWidget);
    expect(legalCalls(h), isEmpty);
  });
}
