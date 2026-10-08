// Today's refusals, per persona and per server answer: who reaches the page
// (the nav leaf and the page gate are the shell's), what a module-less or
// org-less person sees, and how a 403 from the server reads on the page.
import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, ApiRequest, LowStockRow;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_inventory/src/today/today_page.dart';
import 'package:dashboard_inventory/src/today/today_parts.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder inside<T>(Finder matching) =>
    find.descendant(of: find.byType(T), matching: matching);

void main() {
  testWidgets('limited (no inventory.read): no Today leaf, Restricted page', (
    tester,
  ) async {
    final h = await pumpToday(tester, persona: Persona.limited);
    expect(find.byType(TodayPage), findsNothing);
    expect(find.byType(DashStatCard), findsNothing);
    for (final r in [orgValuation, orgLow, orgOrders, catalogRoute]) {
      expect(h.server.callsTo(r), isEmpty, reason: r);
    }
    expect(find.byType(Restricted), findsOneWidget);
  });

  testWidgets('dawamOnly (INV-ALL-005): not part of this business\'s plan', (
    tester,
  ) async {
    final h = await pumpToday(tester, persona: Persona.dawamOnly);
    h.allowUnmatched = true;
    expect(find.byType(TodayPage), findsNothing);
    expect(find.text("Not part of this business's plan"), findsOneWidget);
    expect(
      find.text(
        'Madar POS is switched off for this business. Ask Madar to switch it on.',
      ),
      findsOneWidget,
    );
    expect(h.server.callsTo(orgLow), isEmpty);
  });

  testWidgets('platform with no org (INV-ALL-009): pick an organization', (
    tester,
  ) async {
    await pumpToday(tester, persona: Persona.platform);
    expect(
      find.text('Select an organization to manage inventory'),
      findsOneWidget,
    );
    final empty = tester.widget<DashEmptyState>(find.byType(DashEmptyState));
    expect(empty.icon, 'boxes');
  });

  testWidgets('platform in Sabah: the whole page', (tester) async {
    final h = await pumpToday(
      tester,
      persona: Persona.platform,
      prefs: sabahPicked(),
    );
    expect(find.byType(TodayPage), findsOneWidget);
    expect(kpi(tester, 'Low stock').value, 9);
    expect(
      h.server.callsTo(orgLow).last.path,
      '/reports/orgs/${SeedIds.sabahOrg}/low-stock',
    );
  });

  testWidgets('manager at all branches: the org roll-ups (require_org only)', (
    tester,
  ) async {
    final h = await pumpToday(tester, persona: Persona.manager);
    expect(find.byType(TodayPage), findsOneWidget);
    expect(h.server.callsTo(orgLow), isNotEmpty);
    expect(kpi(tester, 'Low stock').value, 9);
    expect(find.text('Create PO'), findsNWidgets(9));
  });

  testWidgets('a branch the server refuses: the server\'s words', (
    tester,
  ) async {
    final s = todayServer(persona: Persona.manager);
    for (final r in [branchValuation, branchLow, stockRoute, wasteRoute]) {
      s.server.fail(
        'GET',
        r,
        MockResponse.forbidden('Not assigned to this branch'),
        times: null,
      );
    }
    final h = await pumpToday(
      tester,
      persona: Persona.manager,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    // The low-stock table shows the refusal itself (INV-ALL-018).
    expect(
      inside<DashDataTable<LowStockRow>>(
        find.text('Forbidden: Not assigned to this branch'),
      ),
      findsOneWidget,
    );
    // The waste list names only what failed (INV-ALL-026).
    expect(
      inside<TodayWasteSection>(find.text("Couldn't load today's waste")),
      findsOneWidget,
    );
    expect(
      inside<TodayWasteSection>(
        find.text('Forbidden: Not assigned to this branch'),
      ),
      findsNothing,
    );
    // The KPIs read as zero, never as an error (INV-TOD-037).
    expect(kpi(tester, 'Low stock').value, 0);
    expect(kpi(tester, 'Stock value').value, 0);
    expect(kpi(tester, 'Counts due').value, 0);
    // Deliveries come from the org's orders: still there (the manager's
    // two at Zamalek).
    expect(kpi(tester, 'Deliveries').value, 2);
    expect(h.server.callsTo(branchLow).last.status, 403);
  });

  testWidgets('manager: another branch is refused by the server', (
    tester,
  ) async {
    final s = todayServer(persona: Persona.manager);
    await expectLater(
      s.server.send(
        ApiRequest(
          method: 'GET',
          path: '/reports/branches/${SeedIds.maadi}/low-stock',
        ),
      ),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 403)
            .having(
              (e) => e.message,
              'message',
              'Forbidden: Not assigned to this branch',
            ),
      ),
    );
  });

  testWidgets('no purchasing.orders.read: deliveries fail alone', (
    tester,
  ) async {
    final s = todayServer();
    s.server.fail(
      'GET',
      orgOrders,
      MockResponse.denied('purchasing.orders.read'),
      times: null,
    );
    await pumpToday(tester, server: s.server, db: s.db, branch: SeedIds.zamalek);
    expect(
      inside<TodayArrivingSection>(find.text("Couldn't load deliveries")),
      findsOneWidget,
    );
    expect(inside<TodayArrivingSection>(find.text('Retry')), findsOneWidget);
    expect(kpi(tester, 'Deliveries').value, 0);
    expect(kpi(tester, 'Low stock').value, 5);
  });

  testWidgets('no inventory.waste.read: today\'s waste fails alone', (
    tester,
  ) async {
    final s = todayServer();
    s.server.fail(
      'GET',
      wasteRoute,
      MockResponse.denied('inventory.waste.read'),
      times: null,
    );
    await pumpToday(tester, server: s.server, db: s.db, branch: SeedIds.zamalek);
    expect(
      inside<TodayWasteSection>(find.text("Couldn't load today's waste")),
      findsOneWidget,
    );
    // Log waste stays offered: the server decides (INV-TOD-033).
    expect(
      tester.widget<DashButton>(byKey('today-log-waste')).onPressed,
      isNotNull,
    );
  });

  testWidgets('a 403 on low stock in Arabic: the server\'s words, Arabic UI', (
    tester,
  ) async {
    final s = todayServer();
    s.server.fail(
      'GET',
      branchLow,
      MockResponse.denied('inventory.read'),
      times: null,
    );
    await pumpToday(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
      locale: 'ar',
    );
    expect(inside<DashDataTable<LowStockRow>>(find.text('تعذّر التحميل')),
        findsOneWidget);
    expect(inside<DashDataTable<LowStockRow>>(find.text('إعادة المحاولة')),
        findsOneWidget);
    expect(kpi(tester, 'مخزون منخفض').value, 0);
  });
}
