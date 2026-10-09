// Verifier scratch test (not part of the worktree): the Legal sidebar leaf
// follows reports.legal, and the page's own gate answers a direct link.
import 'package:dashboard_api/dashboard_api.dart' show MyAuthz;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_reports/src/legal/legal_page.dart';
import 'package:dashboard_reports/src/mock/legal_mock.dart';
import 'package:flutter_test/flutter_test.dart';

const legalArea = DashArea(key: 'reports', routes: [DashRoute(path: '/reports/legal', builder: legalPageBuilder, titleKey: 'reports.legal.title', titleFallback: 'Legal', tabs: legalTabs)], registerMocks: registerLegalMocks, i18nSupplements: ['packages/dashboard_reports/assets/i18n/en.json','packages/dashboard_reports/assets/i18n/ar.json','packages/dashboard_reports/assets/i18n/legal.en.json','packages/dashboard_reports/assets/i18n/legal.ar.json']);

Future<List<String>> leaves(DashHarness h) async {
  final more = find.descendant(
    of: find.byType(DashSidebar),
    matching: find.textContaining(RegExp(r'^\d+ more$')),
  );
  while (more.evaluate().isNotEmpty) {
    await h.tap(more.first);
  }
  return [
    for (final w in h.tester.widgetList<PrefetchOnIntent>(
      find.descendant(of: find.byType(DashSidebar), matching: find.byType(PrefetchOnIntent)),
    ))
      w.to,
  ];
}

void without(MockServer server, Persona persona, Set<String> drop) {
  server.on('GET', '/authz/me', (req) {
    final caps = [for (final c in persona.capabilities) if (!drop.contains(c)) c]..sort();
    return MockResponse.ok(MyAuthz(
      userId: persona.userId, branchId: req.q('branch_id'), capabilities: caps,
      everywhere: persona.branchIds == null ? caps : const [], askManager: const [],
      limits: const {}, owner: false, platform: false, roleKinds: persona.roleKinds,
      epoch: 1, specVersion: 2));
  });
}

void main() {
  testWidgets('owner without reports.legal: no Legal leaf, Operations kept; direct link Restricted', (tester) async {
    final db = MockDb.seeded();
    final server = MockServer(persona: Persona.owner, clock: db.clock);
    registerCoreMocks(server, db);
    registerLegalMocks(server, db);
    without(server, Persona.owner, {Cap.reportsLegal});
    final h = await DashHarness.pump(tester, areas: const [legalArea], path: '/reports/legal', server: server, db: db);
    final l = await leaves(h);
    expect(l, contains('/reports/operations'));
    expect(l, isNot(contains('/reports/legal')));
    expect(find.text(h.t('reports.noAccess')), findsOneWidget);
    expect([for (final c in server.calls) if ((c.template ?? '').startsWith('/reports/orgs/')) c], isEmpty);
  });

  testWidgets('limited (orders.read, no reports.legal): Operations leaf, no Legal', (tester) async {
    final h = await DashHarness.pump(tester, areas: const [legalArea], path: '/reports/legal', persona: Persona.limited);
    final l = await leaves(h);
    expect(l, contains('/reports/operations'));
    expect(l, isNot(contains('/reports/legal')));
  });

  testWidgets('manager and owner: Legal leaf shown', (tester) async {
    for (final p in [Persona.manager, Persona.owner]) {
      final h = await DashHarness.pump(tester, areas: const [legalArea], path: '/reports/legal', persona: p);
      final l = await leaves(h);
      expect(l, contains('/reports/legal'), reason: p.name);
    }
  });
}
