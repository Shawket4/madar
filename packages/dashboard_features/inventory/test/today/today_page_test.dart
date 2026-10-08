// Today (`/inventory/today`), driven through the real app shell: one test
// (or more) per inventory row INV-TOD-001…038. Figures are checked against
// the seed's raw rows (support.dart), never against the mock's views.
import 'package:dashboard_api/dashboard_api.dart' show LowStockRow;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/purchasing/purchase_order_dialog.dart';
import 'package:dashboard_inventory/src/purchasing/receive_dialog.dart';
import 'package:dashboard_inventory/src/shared/inventory_data.dart';
import 'package:dashboard_inventory/src/today/today_page.dart';
import 'package:dashboard_inventory/src/today/today_parts.dart';
import 'package:dashboard_inventory/src/waste/waste_dialog.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final _now = MockClock.defaultNow;

/// Finds [matching] inside the widget of type [T].
Finder inside<T>(Finder matching) =>
    find.descendant(of: find.byType(T), matching: matching);

DashDataTable<LowStockRow> lowTable(WidgetTester tester) =>
    tester.widget(find.byType(DashDataTable<LowStockRow>));

/// Lets a sibling unit's dialog (opened from Today) make its own reads
/// without failing Today's test while that unit is being built.
void tolerateSiblings(DashHarness h) {
  h.allowUnmatched = true;
  h.allowMissingKeys = true;
}

void main() {
  group('header and reads', () {
    testWidgets('INV-TOD-001 title and subtitle, no header actions', (
      tester,
    ) async {
      final h = await pumpToday(tester);
      expect(find.byType(TodayPage), findsOneWidget);
      expect(inside<DashPageHeader>(find.text('Today')), findsOneWidget);
      expect(
        find.text('Your morning briefing: alerts, deliveries and counts due'),
        findsOneWidget,
      );
      expect(inside<DashPageHeader>(find.byType(DashButton)), findsNothing);
      expect(h.location.path, todayPath);
    });

    testWidgets('INV-TOD-002 no organization: the title and pick-an-org', (
      tester,
    ) async {
      final h = await pumpToday(tester, persona: Persona.platform);
      expect(inside<DashPageHeader>(find.text('Today')), findsOneWidget);
      expect(
        find.text('Select an organization to manage inventory'),
        findsOneWidget,
      );
      expect(
        find.text('Your morning briefing: alerts, deliveries and counts due'),
        findsNothing,
      );
      expect(find.byType(DashStatCard), findsNothing);
      for (final r in [orgValuation, orgLow, orgOrders, branchLow]) {
        expect(h.server.callsTo(r), isEmpty, reason: r);
      }
    });

    testWidgets('INV-TOD-003 a branch: the branch reads, then the org ones', (
      tester,
    ) async {
      final h = await pumpToday(tester, branch: SeedIds.zamalek);
      final z = SeedIds.zamalek;
      expect(
        h.server.callsTo(branchValuation).last.path,
        '/reports/branches/$z/inventory-valuation',
      );
      expect(
        h.server.callsTo(branchLow).last.path,
        '/reports/branches/$z/low-stock',
      );
      expect(
        h.server.callsTo(stockRoute).last.path,
        '/inventory/branches/$z/stock',
      );
      expect(h.server.callsTo(stocktakesRoute).last.path, '/stocktakes/branches/$z');
      final waste = h.server.callsTo(wasteRoute).last;
      expect(waste.path, '/inventory/branches/$z/waste');
      expect(waste.query, isEmpty);
      final orders = h.server.callsTo(orgOrders).last;
      expect(orders.path, '/purchasing/orgs/${SeedIds.sabahOrg}/orders');
      expect(orders.query, {
        'expected_before': [endOfToday],
      });
      expect(h.server.callsTo(suppliersRoute), isNotEmpty);
      expect(h.server.callsTo(catalogRoute), isNotEmpty);
      expect(h.server.callsTo(orgValuation), isEmpty);
      expect(h.server.callsTo(orgLow), isEmpty);
    });

    testWidgets('INV-TOD-003 all branches: org roll-ups, no branch reads', (
      tester,
    ) async {
      final h = await pumpToday(tester);
      final org = SeedIds.sabahOrg;
      expect(
        h.server.callsTo(orgValuation).last.path,
        '/reports/orgs/$org/inventory-valuation',
      );
      expect(h.server.callsTo(orgLow).last.path, '/reports/orgs/$org/low-stock');
      expect(h.server.callsTo(orgOrders), isNotEmpty);
      expect(h.server.callsTo(suppliersRoute), isNotEmpty);
      expect(h.server.callsTo(catalogRoute), isNotEmpty);
      for (final r in [
        branchValuation,
        branchLow,
        stockRoute,
        stocktakesRoute,
        wasteRoute,
      ]) {
        expect(h.server.callsTo(r), isEmpty, reason: r);
      }
    });

    testWidgets('INV-ALL-008 a deep link picks the branch', (tester) async {
      final h = await pumpToday(tester, path: todayAt(SeedIds.zamalek));
      expect(
        h.server.callsTo(branchLow).last.path,
        '/reports/branches/${SeedIds.zamalek}/low-stock',
      );
      expect(kpi(tester, 'Low stock').value, 5);
      expect(find.text('Croissant Dough'), findsWidgets);
    });

    testWidgets('INV-TOD-004 today ends in the branch\'s zone, not Cairo', (
      tester,
    ) async {
      final s = todayServer();
      s.db['branches'].update(SeedIds.zamalek, {'timezone': 'Asia/Dubai'});
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      // 10:00 Cairo is 11:00 in Dubai, still the 8th: its end is 19:59:59.999Z.
      expect(h.server.callsTo(orgOrders).last.query['expected_before'], [
        '2026-10-08T19:59:59.999Z',
      ]);
    });
  });

  group('first run', () {
    testWidgets('INV-TOD-005 a branch never counted: the card, and its way in', (
      tester,
    ) async {
      final h = await pumpToday(tester, branch: SeedIds.heliopolis);
      expect(find.text('Start by counting this branch'), findsOneWidget);
      expect(
        textHas('Nothing has been counted here yet, so the numbers below'),
        findsOneWidget,
      );
      tolerateSiblings(h);
      await h.tap(byKey('today-first-count'));
      expect(h.location.path, '/inventory/counts');
    });

    testWidgets('INV-TOD-005 not for a counted branch, nor all branches', (
      tester,
    ) async {
      final h = await pumpToday(tester, branch: SeedIds.zamalek);
      expect(find.text('Start by counting this branch'), findsNothing);
      await h.go(todayPath);
      expect(find.text('Start by counting this branch'), findsNothing);
    });

    testWidgets('INV-TOD-005 not when the counts read failed', (tester) async {
      final s = todayServer();
      s.server.fail(
        'GET',
        stocktakesRoute,
        MockResponse.error(500, 'Database unavailable'),
        times: null,
      );
      await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.heliopolis,
      );
      expect(find.text('Start by counting this branch'), findsNothing);
      // Not first run, so the empty low-stock words are "All good".
      expect(
        find.text('All good — nothing below its reorder point'),
        findsOneWidget,
      );
    });

    testWidgets('INV-TOD-005 not while the counts are loading', (tester) async {
      final s = todayServer();
      final gate = s.server.hold('GET', stocktakesRoute);
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.heliopolis,
      );
      expect(find.text('Start by counting this branch'), findsNothing);
      gate.release();
      await h.settle();
      expect(find.text('Start by counting this branch'), findsOneWidget);
    });
  });

  group('KPIs', () {
    testWidgets('INV-TOD-006 stock value of the branch, unknown costs', (
      tester,
    ) async {
      final h = await pumpToday(tester, branch: SeedIds.zamalek);
      final want = stockValue(h.db!, [SeedIds.zamalek]);
      expect(want.unknown, 1); // Dried Hibiscus has no cost yet.
      final card = kpi(tester, 'Stock value');
      expect(card.value, want.total);
      expect(card.format, DashStatFormat.money);
      expect(card.icon, 'wallet');
      expect(card.hint, '1 unknown cost');
      final f = h.container.read(formatProvider);
      expect(find.text(f.fmtMoney(want.total)), findsOneWidget);
    });

    testWidgets('INV-TOD-006 all branches: the org roll-up', (tester) async {
      final h = await pumpToday(tester);
      final want = stockValue(h.db!, SeedIds.sabahBranches);
      expect(kpi(tester, 'Stock value').value, want.total);
      expect(kpi(tester, 'Stock value').hint, '${want.unknown} unknown cost');
    });

    testWidgets('INV-TOD-006 a skeleton while the valuation loads', (
      tester,
    ) async {
      final s = todayServer();
      final gate = s.server.hold('GET', branchValuation);
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(kpi(tester, 'Stock value').loading, isTrue);
      expect(kpi(tester, 'Low stock').loading, isFalse);
      gate.release();
      await h.settle();
      expect(kpi(tester, 'Stock value').loading, isFalse);
      expect(kpi(tester, 'Stock value').hint, '1 unknown cost');
    });

    testWidgets('INV-TOD-006 a failed read: EGP 0.00, no hint, no error', (
      tester,
    ) async {
      final s = todayServer();
      s.server.fail(
        'GET',
        branchValuation,
        MockResponse.error(500, 'Database unavailable'),
        times: null,
      );
      await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      final card = kpi(tester, 'Stock value');
      expect(card.loading, isFalse);
      expect(card.hint, isNull);
      expect(card.value, 0);
      expect(find.text('EGP 0.00'), findsOneWidget);
      expect(find.text('Database unavailable'), findsNothing);
    });

    testWidgets('INV-TOD-006 a failed refetch keeps the last figure', (
      tester,
    ) async {
      final s = todayServer();
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      final want = stockValue(s.db, [SeedIds.zamalek]).total;
      s.server.fail(
        'GET',
        branchValuation,
        MockResponse.error(500, 'Database unavailable'),
      );
      h.container.read(realtimeBusProvider).invalidate(['/reports']);
      await h.settle();
      expect(kpi(tester, 'Stock value').value, want);
      expect(kpi(tester, 'Stock value').hint, '1 unknown cost');
    });

    testWidgets('INV-TOD-007 low stock: rows, critical, warning glyph', (
      tester,
    ) async {
      final h = await pumpToday(tester, branch: SeedIds.zamalek);
      final rows = lowRowsOf(h.db!, [SeedIds.zamalek]);
      expect(rows, hasLength(5));
      final card = kpi(tester, 'Low stock');
      expect(card.value, 5);
      expect(card.tone, DashTone.warning);
      expect(card.icon, 'alert-triangle');
      expect(card.hint, '2 critical');
    });

    testWidgets('INV-TOD-007 skeleton while low stock loads', (tester) async {
      final s = todayServer();
      final gate = s.server.hold('GET', branchLow);
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(kpi(tester, 'Low stock').loading, isTrue);
      expect(kpi(tester, 'Stock value').loading, isFalse);
      gate.release();
      await h.settle();
      expect(kpi(tester, 'Low stock').value, 5);
    });

    testWidgets('INV-TOD-008 deliveries: every branch\'s, overdue included', (
      tester,
    ) async {
      await pumpToday(tester, branch: SeedIds.maadi);
      // PO-1044 and PO-1042 (Zamalek) due today, PO-1041 (Maadi) overdue.
      final card = kpi(tester, 'Deliveries');
      expect(card.value, 3);
      expect(card.icon, 'truck');
      expect(card.hint, 'arriving today');
    });

    testWidgets('INV-TOD-008 skeleton while the orders load', (tester) async {
      final s = todayServer();
      final gate = s.server.hold('GET', orgOrders);
      final h = await pumpToday(tester, server: s.server, db: s.db);
      expect(kpi(tester, 'Deliveries').loading, isTrue);
      gate.release();
      await h.settle();
      expect(kpi(tester, 'Deliveries').value, 3);
    });

    testWidgets('INV-TOD-009 counts due at a branch: >14 days or never', (
      tester,
    ) async {
      final h = await pumpToday(tester, branch: SeedIds.zamalek);
      final want = countsDueAt(h.db!, SeedIds.zamalek, _now);
      // The whole catalog bar the milk recounted on 4 Oct.
      expect(want, greaterThan(15));
      final card = kpi(tester, 'Counts due');
      expect(card.value, want);
      expect(card.icon, 'calendar-clock');
      expect(card.hint, '>14 days or never');
    });

    testWidgets('INV-TOD-009 all branches: an em dash, never loading', (
      tester,
    ) async {
      await pumpToday(tester);
      final card = kpi(tester, 'Counts due');
      expect(card.value, isNull);
      expect(card.valueText, '—');
      expect(card.loading, isFalse);
      expect(card.hint, '>14 days or never');
    });

    testWidgets('INV-TOD-009 skeleton only while the branch stock loads', (
      tester,
    ) async {
      final s = todayServer();
      final gate = s.server.hold('GET', stockRoute);
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.heliopolis,
      );
      expect(kpi(tester, 'Counts due').loading, isTrue);
      gate.release();
      await h.settle();
      // Heliopolis has counted nothing: the whole catalog is due.
      expect(
        kpi(tester, 'Counts due').value,
        h.db![InvTables.ingredients].length,
      );
    });

    testWidgets('INV-TOD-010 a figure too wide is shortened, exact on tap', (
      tester,
    ) async {
      final s = todayServer();
      s.server.on('GET', branchValuation, (req) {
        return MockResponse.ok({
          'total_value': 123456789,
          'unknown_cost_count': 0,
          'items': <Object>[],
        });
      });
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        size: DashSize.phone,
        branch: SeedIds.zamalek,
      );
      const exact = 'EGP 1,234,567.89';
      final value = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is DashStatCard && w.label == 'Stock value',
        ),
        matching: find.byType(DashStatValue),
      );
      expect(find.descendant(of: value, matching: find.text(exact)), findsNothing);
      await h.tap(
        find.descendant(of: value, matching: find.byType(DashPressable)),
      );
      expect(find.text(exact), findsOneWidget);
    });

    testWidgets('INV-TOD-010 counts up from zero on first reveal', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        branch: SeedIds.zamalek,
        reducedMotion: false,
      );
      final want = h.container
          .read(formatProvider)
          .fmtMoney(stockValue(h.db!, [SeedIds.zamalek]).total);
      // The figure is still counting after the first frames…
      expect(find.text(want), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await h.settle();
      // …and lands on the exact value.
      expect(find.text(want), findsOneWidget);
    });
  });

  group('low stock', () {
    testWidgets('INV-TOD-011 header: glyph, title, count, View all', (
      tester,
    ) async {
      final h = await pumpToday(tester, branch: SeedIds.zamalek);
      final header = tester.widget<DashSectionHeader>(
        find.ancestor(
          of: find.text('Low stock — reorder soon'),
          matching: find.byType(DashSectionHeader),
        ),
      );
      expect(header.icon, 'alert-triangle');
      expect(header.count, 5);
      final viewAll = tester.widget<DashButton>(byKey('today-view-all'));
      expect(viewAll.label, 'View all');
      expect(viewAll.variant, DashButtonVariant.ghost);
      expect(viewAll.trailingIcon, 'chevron-right');
      tolerateSiblings(h);
      await h.tap(byKey('today-view-all'));
      expect(h.location.path, '/inventory/ingredients');
    });

    testWidgets('INV-TOD-011 the chevron points to the end in Arabic', (
      tester,
    ) async {
      await pumpToday(tester, branch: SeedIds.zamalek, locale: 'ar');
      final viewAll = tester.widget<DashButton>(byKey('today-view-all'));
      expect(viewAll.label, 'عرض الكل');
      expect(viewAll.trailingIcon, 'chevron-left');
    });

    testWidgets('INV-TOD-011 no count while loading or after a failure', (
      tester,
    ) async {
      final s = todayServer();
      final gate = s.server.hold('GET', branchLow);
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      DashSectionHeader header() => tester.widget(
        find.ancestor(
          of: find.text('Low stock — reorder soon'),
          matching: find.byType(DashSectionHeader),
        ),
      );
      expect(header().count, isNull);
      s.server.fail(
        'GET',
        branchLow,
        MockResponse.error(500, 'Database unavailable'),
      );
      gate.release();
      await h.settle();
      expect(header().count, 5);
      h.container.read(realtimeBusProvider).invalidate(['/reports']);
      await h.settle();
      expect(header().count, isNull);
    });

    testWidgets('INV-TOD-012 columns, pills, figures, supplier', (
      tester,
    ) async {
      final h = await pumpToday(tester, branch: SeedIds.zamalek);
      for (final label in [
        'NAME',
        'BRANCH',
        'ON HAND',
        'REORDER POINT',
        'ORDER',
        'SUPPLIER',
      ]) {
        expect(
          inside<DashDataTable<LowStockRow>>(find.text(label)),
          findsOneWidget,
          reason: label,
        );
      }
      final table = lowTable(tester);
      expect(table.pageSize, 12);
      expect(table.hideViewOptions, isTrue);
      expect(table.searchPlaceholder, isNull);
      expect(find.text('Columns'), findsNothing);
      // Server order: by branch, then name.
      expect(table.rows.map((r) => r.ingredientName), [
        'Croissant Dough',
        'Matcha Powder',
        'Oat Milk',
        'Paper Cup 12oz',
        'Vanilla Syrup',
      ]);
      expect(inside<DashDataTable<LowStockRow>>(find.text('Critical')),
          findsNWidgets(2));
      expect(inside<DashDataTable<LowStockRow>>(find.text('Low')),
          findsNWidgets(3));
      final critical = tester.widget<DashStatusPill>(
        find.ancestor(
          of: find.text('Critical').first,
          matching: find.byType(DashStatusPill),
        ),
      );
      expect(critical.tone, DashTone.danger);
      expect(critical.icon, 'octagon-x');
      final oat = stockRow(h.db!, SeedIds.zamalek, 'oat')!;
      expect(oat['on_hand'], -350);
      expect(textHas('−350 ml'), findsOneWidget);
      expect(textHas('4,000 ml'), findsOneWidget);
      expect(textHas('9,350 ml'), findsOneWidget);
      expect(find.text('Metro Wholesale'), findsNWidgets(3));
      expect(find.text('Zamalek'), findsWidgets);
    });

    testWidgets('INV-TOD-012 a row with no supplier shows a muted dash', (
      tester,
    ) async {
      final s = todayServer();
      setStock(s.db, SeedIds.zamalek, 'ice', onHand: 1000, parMin: 5000);
      await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(lowTable(tester).rows.map((r) => r.ingredientName), contains('Ice Cubes'));
      expect(inside<DashDataTable<LowStockRow>>(find.text('—')), findsOneWidget);
    });

    testWidgets('INV-TOD-012 12 rows a page, then a pager', (tester) async {
      final s = todayServer();
      for (final k in [
        'house-blend',
        'ethiopia',
        'decaf',
        'turkish',
        'skimmed',
        'almond',
        'heavy-cream',
        'whipped-cream',
      ]) {
        setStock(s.db, SeedIds.zamalek, k, onHand: 1, parMin: 100000);
      }
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(lowTable(tester).rows, hasLength(13));
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(
        inside<DashDataTable<LowStockRow>>(find.text('Create PO')),
        findsNWidgets(12),
      );
      await h.tapLabel('Next');
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(
        inside<DashDataTable<LowStockRow>>(find.text('Create PO')),
        findsOneWidget,
      );
    });

    testWidgets('INV-TOD-013 Create PO: the row\'s branch, supplier, ceil qty', (
      tester,
    ) async {
      final h = await pumpToday(tester, branch: SeedIds.zamalek);
      tolerateSiblings(h);
      final oat = InvIds.ingredient('oat');
      await h.tap(byKey('today-create-po-${SeedIds.zamalek}-$oat'));
      final dialog = tester.widget<PurchaseOrderDialog>(
        find.byType(PurchaseOrderDialog),
      );
      expect(dialog.branchId, SeedIds.zamalek);
      expect(dialog.prefill!.supplierId, InvIds.supplier('metro'));
      expect(dialog.prefill!.lines, hasLength(1));
      expect(dialog.prefill!.lines.single.orgIngredientId, oat);
      expect(dialog.prefill!.lines.single.quantity, 9350);
      expect(dialog.prefill!.lines.single.purchaseUnit, isNull);
      expect(find.text('New purchase order'), findsWidgets);
    });

    testWidgets('INV-TOD-013 with all branches, the row\'s own branch', (
      tester,
    ) async {
      final h = await pumpToday(tester);
      tolerateSiblings(h);
      final sugar = InvIds.ingredient('sugar');
      await h.tap(byKey('today-create-po-${SeedIds.newCairo}-$sugar'));
      final dialog = tester.widget<PurchaseOrderDialog>(
        find.byType(PurchaseOrderDialog),
      );
      expect(dialog.branchId, SeedIds.newCairo);
      expect(dialog.prefill!.lines.single.orgIngredientId, sugar);
    });

    testWidgets('INV-TOD-013 an inactive default supplier is still sent', (
      tester,
    ) async {
      final s = todayServer();
      setStock(s.db, SeedIds.zamalek, 'hibiscus', onHand: 10.4, parMin: 500);
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      tolerateSiblings(h);
      final hib = InvIds.ingredient('hibiscus');
      await h.tap(byKey('today-create-po-${SeedIds.zamalek}-$hib'));
      final dialog = tester.widget<PurchaseOrderDialog>(
        find.byType(PurchaseOrderDialog),
      );
      expect(dialog.prefill!.supplierId, InvIds.supplier('cairo-fresh'));
    });

    testWidgets('INV-TOD-013 a fractional suggestion rounds up, never 0', (
      tester,
    ) async {
      expect(reorderQuantity(0), 1);
      expect(reorderQuantity(0.2), 1);
      expect(reorderQuantity(1), 1);
      expect(reorderQuantity(12.01), 13);
      expect(reorderQuantity(9350), 9350);
    });

    testWidgets('INV-TOD-014 skeleton rows while low stock loads', (
      tester,
    ) async {
      final s = todayServer();
      final gate = s.server.hold('GET', branchLow);
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(lowTable(tester).loading, isTrue);
      expect(inside<DashDataTable<LowStockRow>>(find.byType(DashSkeleton)),
          findsWidgets);
      expect(find.text('Create PO'), findsNothing);
      gate.release();
      await h.settle();
      expect(lowTable(tester).loading, isFalse);
      expect(find.text('Create PO'), findsNWidgets(5));
    });

    testWidgets('INV-TOD-015 a failed read: the words, the reason, Retry', (
      tester,
    ) async {
      final s = todayServer();
      s.server.fail(
        'GET',
        branchLow,
        MockResponse.error(500, 'Database unavailable'),
      );
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      final err = find.descendant(
        of: find.byType(DashDataTable<LowStockRow>),
        matching: find.byType(DashErrorState),
      );
      expect(err, findsOneWidget);
      expect(inside<DashDataTable<LowStockRow>>(find.text("Couldn't load this")),
          findsOneWidget);
      expect(
        inside<DashDataTable<LowStockRow>>(find.text('Database unavailable')),
        findsOneWidget,
      );
      expect(find.text('Page 1 of 1'), findsNothing);
      final before = h.server.callsTo(branchLow).length;
      await h.tap(find.descendant(of: err, matching: find.text('Retry')));
      expect(h.server.callsTo(branchLow).length, before + 1);
      expect(err, findsNothing);
      expect(find.text('Create PO'), findsNWidgets(5));
    });

    testWidgets('INV-TOD-016 nothing low: "All good"', (tester) async {
      final s = todayServer();
      for (final bs in s.db[InvTables.branchStock].rows.toList()) {
        if (bs['branch_id'] == SeedIds.zamalek) {
          s.db[InvTables.branchStock].update(bs['id']! as String, {
            'par_min': null,
          });
        }
      }
      await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(
        find.text('All good — nothing below its reorder point'),
        findsOneWidget,
      );
      final empty = tester.widget<DashEmptyState>(
        find.ancestor(
          of: find.text('All good — nothing below its reorder point'),
          matching: find.byType(DashEmptyState),
        ),
      );
      expect(empty.icon, 'package-check');
      expect(kpi(tester, 'Low stock').value, 0);
      expect(kpi(tester, 'Low stock').hint, '0 critical');
    });

    testWidgets('INV-TOD-016 first run: set a reorder point first', (
      tester,
    ) async {
      await pumpToday(tester, branch: SeedIds.heliopolis);
      expect(
        find.text(
          'Low-stock alerts appear once you set a reorder point on an ingredient.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('All good — nothing below its reorder point'),
        findsNothing,
      );
    });
  });

  group('arriving today', () {
    testWidgets('INV-TOD-017 the section header', (tester) async {
      await pumpToday(tester);
      final header = tester.widget<DashSectionHeader>(
        inside<TodayArrivingSection>(find.byType(DashSectionHeader)),
      );
      expect(header.title, 'Arriving today');
      expect(header.icon, 'truck');
      expect(header.trailing, isNull);
    });

    testWidgets('INV-TOD-018 rows: reference or #id · supplier, date, Receive', (
      tester,
    ) async {
      final h = await pumpToday(tester, branch: SeedIds.zamalek);
      final rows = tester
          .widgetList<DashListRow>(inside<TodayArrivingSection>(find.byType(DashListRow)))
          .toList();
      final id1044 = InvIds.purchaseOrder('po-1044');
      expect(rows.map((r) => r.title), [
        'PO-1041 · Delta Dairy',
        '${ltr('#${id1044.substring(0, 8)}')} · Delta Dairy',
        'PO-1042 · Nile Roasters',
      ]);
      expect(rows.map((r) => r.meta), [
        ltr('07 Oct 2026'),
        ltr('08 Oct 2026'),
        ltr('08 Oct 2026'),
      ]);
      expect(rows.every((r) => r.icon == 'truck'), isTrue);
      tolerateSiblings(h);
      await h.tap(byKey('today-receive-$id1044'));
      final dialog = tester.widget<ReceiveDialog>(find.byType(ReceiveDialog));
      expect(dialog.purchaseOrderId, id1044);
    });

    testWidgets('INV-TOD-018 only the first eight', (tester) async {
      final s = todayServer();
      for (var i = 0; i < 7; i++) {
        addOrder(
          s.db,
          key: 'extra-$i',
          branchId: SeedIds.newCairo,
          status: 'ordered',
          reference: 'PO-20$i',
        );
      }
      await pumpToday(tester, server: s.server, db: s.db);
      expect(kpi(tester, 'Deliveries').value, 10);
      expect(
        inside<TodayArrivingSection>(find.byType(DashListRow)),
        findsNWidgets(8),
      );
    });

    testWidgets('INV-TOD-019 skeleton rows while loading', (tester) async {
      final s = todayServer();
      final gate = s.server.hold('GET', orgOrders);
      final h = await pumpToday(tester, server: s.server, db: s.db);
      expect(
        inside<TodayArrivingSection>(find.byType(TodayListSkeleton)),
        findsOneWidget,
      );
      expect(
        inside<TodayArrivingSection>(find.byType(DashSkeleton)),
        findsNWidgets(9),
      );
      gate.release();
      await h.settle();
      expect(find.byType(TodayListSkeleton), findsNothing);
    });

    testWidgets('INV-TOD-020 failed: its own words and Retry, no reason', (
      tester,
    ) async {
      final s = todayServer();
      s.server.fail(
        'GET',
        orgOrders,
        MockResponse.error(500, 'Database unavailable'),
      );
      final h = await pumpToday(tester, server: s.server, db: s.db);
      final err = tester.widget<DashErrorState>(
        inside<TodayArrivingSection>(find.byType(DashErrorState)),
      );
      expect(err.title, "Couldn't load deliveries");
      expect(err.message, isNull);
      expect(find.text('Database unavailable'), findsNothing);
      await h.tap(inside<TodayArrivingSection>(find.text('Retry')));
      expect(
        inside<TodayArrivingSection>(find.byType(DashListRow)),
        findsNWidgets(3),
      );
    });

    testWidgets('INV-TOD-021 none due: "No deliveries scheduled today"', (
      tester,
    ) async {
      final s = todayServer();
      for (final po in s.db[InvTables.purchaseOrders].rows.toList()) {
        s.db[InvTables.purchaseOrders].update(po['id']! as String, {
          'expected_at': '2026-10-20T20:59:59.999Z',
        });
      }
      await pumpToday(tester, server: s.server, db: s.db);
      expect(find.text('No deliveries scheduled today'), findsOneWidget);
      expect(kpi(tester, 'Deliveries').value, 0);
    });
  });

  group("today's waste", () {
    testWidgets('INV-TOD-022 Log waste opens the dialog for the branch', (
      tester,
    ) async {
      final h = await pumpToday(tester, branch: SeedIds.zamalek);
      final header = tester.widget<DashSectionHeader>(
        inside<TodayWasteSection>(find.byType(DashSectionHeader)),
      );
      expect(header.title, "Today's waste");
      expect(header.icon, 'trash-2');
      final button = tester.widget<DashButton>(byKey('today-log-waste'));
      expect(button.label, 'Log waste');
      expect(button.icon, 'trash-2');
      expect(button.variant, DashButtonVariant.outline);
      expect(button.onPressed, isNotNull);
      tolerateSiblings(h);
      await h.tap(byKey('today-log-waste'));
      final dialog = tester.widget<RecordWasteDialog>(
        find.byType(RecordWasteDialog),
      );
      expect(dialog.branchId, SeedIds.zamalek);
      expect(dialog.presetIngredientId, isNull);
    });

    testWidgets('INV-TOD-022 Log waste is disabled with all branches', (
      tester,
    ) async {
      await pumpToday(tester);
      expect(
        tester.widget<DashButton>(byKey('today-log-waste')).onPressed,
        isNull,
      );
    });

    testWidgets('INV-TOD-023 all branches: pick a branch', (tester) async {
      await pumpToday(tester);
      expect(
        inside<TodayWasteSection>(
          find.text('Select a branch to manage its stock'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('INV-TOD-024 the lines received today, newest first', (
      tester,
    ) async {
      await pumpToday(tester, branch: SeedIds.zamalek);
      final rows = tester
          .widgetList<DashListRow>(inside<TodayWasteSection>(find.byType(DashListRow)))
          .toList();
      expect(rows.map((r) => r.title), [
        'Full Cream Milk',
        'House Blend Beans',
        'Croissant Dough',
        'Full Cream Milk',
      ]);
      expect(rows.map((r) => r.meta), ['Spoiled', 'Spoiled', 'Damaged', 'Expired']);
      expect(rows.map((r) => r.value), ['440 ml', '36 g', '4 pcs', '500 ml']);
      expect(rows.every((r) => r.variant == DashListRowVariant.ledger), isTrue);
      expect(rows.every((r) => r.signIn == false && r.numericValue), isTrue);
      // Logged on the 6th, received yesterday: not today's.
      expect(
        inside<TodayWasteSection>(find.text('Whipped Cream')),
        findsNothing,
      );
    });

    testWidgets('INV-TOD-024 by receive time; no reason, no meta; eight', (
      tester,
    ) async {
      final s = todayServer();
      // Happened yesterday on an offline till, received today: counts.
      addWaste(
        s.db,
        key: 'late',
        branchId: SeedIds.maadi,
        ingredientKey: 'cocoa',
        qty: 50,
        createdAt: '2026-10-08T06:00:00.000Z',
        occurredAt: '2026-10-07T15:00:00.000Z',
        reason: null,
      );
      // Says today, but the server got it before midnight: does not.
      addWaste(
        s.db,
        key: 'early',
        branchId: SeedIds.maadi,
        ingredientKey: 'sugar',
        qty: 100,
        createdAt: '2026-10-07T20:59:00.000Z',
        occurredAt: '2026-10-08T06:00:00.000Z',
      );
      // The first instant of today counts.
      addWaste(
        s.db,
        key: 'edge',
        branchId: SeedIds.maadi,
        ingredientKey: 'decaf',
        qty: 20,
        createdAt: startOfToday,
        reason: 'refund',
      );
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.maadi,
      );
      final rows = {
        for (final r in tester.widgetList<DashListRow>(
          inside<TodayWasteSection>(find.byType(DashListRow)),
        ))
          r.title: r,
      };
      expect(rows.keys.toSet(), {'Cocoa Powder', 'Decaf Beans'});
      expect(rows['Cocoa Powder']!.meta, isNull);
      expect(rows['Cocoa Powder']!.value, '50 g');
      expect(rows['Decaf Beans']!.meta, 'Refunded sale');

      for (var i = 0; i < 9; i++) {
        addWaste(
          s.db,
          key: 'many-$i',
          branchId: SeedIds.maadi,
          ingredientKey: 'sugar',
          qty: 10.0 + i,
          createdAt: '2026-10-08T06:3$i:00.000Z',
        );
      }
      h.container.read(realtimeBusProvider).invalidate(inventoryPathFamilies);
      await h.settle();
      expect(
        inside<TodayWasteSection>(find.byType(DashListRow)),
        findsNWidgets(8),
      );
    });

    testWidgets('INV-TOD-025 skeleton while the waste loads', (tester) async {
      final s = todayServer();
      final gate = s.server.hold('GET', wasteRoute);
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(
        inside<TodayWasteSection>(find.byType(TodayListSkeleton)),
        findsOneWidget,
      );
      gate.release();
      await h.settle();
      expect(
        inside<TodayWasteSection>(find.byType(DashListRow)),
        findsNWidgets(4),
      );
    });

    testWidgets("INV-TOD-026 failed: \"Couldn't load today's waste\" + Retry", (
      tester,
    ) async {
      final s = todayServer();
      s.server.fail(
        'GET',
        wasteRoute,
        MockResponse.error(500, 'Database unavailable'),
      );
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      final err = tester.widget<DashErrorState>(
        inside<TodayWasteSection>(find.byType(DashErrorState)),
      );
      expect(err.title, "Couldn't load today's waste");
      expect(err.message, isNull);
      await h.tap(inside<TodayWasteSection>(find.text('Retry')));
      expect(
        inside<TodayWasteSection>(find.byType(DashListRow)),
        findsNWidgets(4),
      );
    });

    testWidgets('INV-TOD-027 nothing today: "No waste logged today"', (
      tester,
    ) async {
      await pumpToday(tester, branch: SeedIds.maadi);
      expect(
        inside<TodayWasteSection>(find.text('No waste logged today')),
        findsOneWidget,
      );
    });
  });

  group('dialogs and refresh', () {
    testWidgets('INV-TOD-028 after an order is placed, every figure refreshes', (
      tester,
    ) async {
      final s = todayServer();
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(kpi(tester, 'Deliveries').value, 3);
      final lowCalls = h.server.callsTo(branchLow).length;
      final valCalls = h.server.callsTo(branchValuation).length;
      // What the purchase-order dialog leaves behind: a new order due today
      // (placed), then `invalidateInventory`.
      addOrder(
        s.db,
        key: 'placed',
        branchId: SeedIds.zamalek,
        status: 'ordered',
        reference: 'PO-1045',
      );
      h.container.read(realtimeBusProvider).invalidate(inventoryPathFamilies);
      await h.settle();
      expect(kpi(tester, 'Deliveries').value, 4);
      expect(textHas('PO-1045 · Metro Wholesale'), findsOneWidget);
      expect(h.server.callsTo(branchLow).length, lowCalls + 1);
      expect(h.server.callsTo(branchValuation).length, valCalls + 1);
    });

    testWidgets('INV-TOD-028 closing clears the prefill', (tester) async {
      final h = await pumpToday(tester, branch: SeedIds.zamalek);
      tolerateSiblings(h);
      final oat = InvIds.ingredient('oat');
      final matcha = InvIds.ingredient('matcha');
      await h.tap(byKey('today-create-po-${SeedIds.zamalek}-$oat'));
      expect(find.byType(PurchaseOrderDialog), findsOneWidget);
      Navigator.of(
        tester.element(find.byType(PurchaseOrderDialog)),
        rootNavigator: true,
      ).pop();
      await h.settle();
      expect(find.byType(PurchaseOrderDialog), findsNothing);
      await h.tap(byKey('today-create-po-${SeedIds.zamalek}-$matcha'));
      final dialog = tester.widget<PurchaseOrderDialog>(
        find.byType(PurchaseOrderDialog),
      );
      expect(dialog.prefill!.lines.single.orgIngredientId, matcha);
      expect(dialog.prefill!.lines.single.quantity, 320);
    });

    testWidgets('INV-TOD-029 after a delivery is received, Today refreshes', (
      tester,
    ) async {
      final s = todayServer();
      final h = await pumpToday(tester, server: s.server, db: s.db);
      tolerateSiblings(h);
      final po = InvIds.purchaseOrder('po-1042');
      await h.tap(byKey('today-receive-$po'));
      expect(
        tester.widget<ReceiveDialog>(find.byType(ReceiveDialog)).purchaseOrderId,
        po,
      );
      Navigator.of(
        tester.element(find.byType(ReceiveDialog)),
        rootNavigator: true,
      ).pop();
      await h.settle();
      // What the receive dialog leaves behind: the order received, then
      // `invalidateInventory`.
      s.db[InvTables.purchaseOrders].update(po, {'status': 'received'});
      h.container.read(realtimeBusProvider).invalidate(inventoryPathFamilies);
      await h.settle();
      expect(kpi(tester, 'Deliveries').value, 2);
      expect(textHas('PO-1042'), findsNothing);
    });

    testWidgets('INV-TOD-030 after waste is recorded, the list refreshes', (
      tester,
    ) async {
      final s = todayServer();
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.maadi,
      );
      expect(find.text('No waste logged today'), findsOneWidget);
      // What the waste dialog leaves behind: a line, then the invalidation.
      addWaste(
        s.db,
        key: 'recorded',
        branchId: SeedIds.maadi,
        ingredientKey: 'almond',
        qty: 250,
        createdAt: '2026-10-08T07:00:00.000Z',
        reason: 'spoiled',
      );
      h.container.read(realtimeBusProvider).invalidate(inventoryPathFamilies);
      await h.settle();
      final row = tester.widget<DashListRow>(
        inside<TodayWasteSection>(find.byType(DashListRow)),
      );
      expect(row.title, 'Almond Milk');
      expect(row.value, '250 ml');
    });
  });

  group('all branches, layout, gating', () {
    testWidgets('INV-TOD-031 all branches: every branch\'s rows, org figures', (
      tester,
    ) async {
      final h = await pumpToday(tester);
      final table = lowTable(tester);
      expect(table.rows, hasLength(lowRowsOf(h.db!, SeedIds.sabahBranches).length));
      expect(table.rows.map((r) => r.branchName).toSet(), {
        'Maadi',
        'New Cairo',
        'Zamalek',
      });
      expect(kpi(tester, 'Low stock').value, 9);
      expect(kpi(tester, 'Counts due').valueText, '—');
      expect(find.text('Start by counting this branch'), findsNothing);
      expect(find.text('Select a branch to manage its stock'), findsOneWidget);
      expect(
        tester.widget<DashButton>(byKey('today-log-waste')).onPressed,
        isNull,
      );
    });

    testWidgets('INV-TOD-032 desktop: four KPIs across, lists side by side', (
      tester,
    ) async {
      await pumpToday(tester, branch: SeedIds.zamalek);
      final tops = {
        for (final c in tester.widgetList<DashStatCard>(find.byType(DashStatCard)))
          tester.getTopLeft(find.byWidget(c)).dy,
      };
      expect(tops, hasLength(1));
      final a = tester.getTopLeft(find.byType(TodayArrivingSection));
      final w = tester.getTopLeft(find.byType(TodayWasteSection));
      expect(a.dy, w.dy);
      expect(w.dx, greaterThan(a.dx));
    });

    testWidgets('INV-TOD-032 tablet: KPIs across, lists side by side', (
      tester,
    ) async {
      await pumpToday(tester, size: DashSize.tablet, branch: SeedIds.zamalek);
      final a = tester.getTopLeft(find.byType(TodayArrivingSection));
      final w = tester.getTopLeft(find.byType(TodayWasteSection));
      expect(a.dy, w.dy);
    });

    testWidgets('INV-TOD-032 phone: KPIs two across, sections stacked, cards', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        size: DashSize.phone,
        branch: SeedIds.zamalek,
      );
      final tops = [
        for (final c in tester.widgetList<DashStatCard>(find.byType(DashStatCard)))
          tester.getTopLeft(find.byWidget(c)).dy,
      ];
      expect(tops.toSet(), hasLength(2));
      final low = tester.getTopLeft(find.byType(TodayLowStockSection)).dy;
      final a = tester.getTopLeft(find.byType(TodayArrivingSection)).dy;
      final w = tester.getTopLeft(find.byType(TodayWasteSection)).dy;
      expect(low < a && a < w, isTrue);
      // Rows are cards: no header row, Create PO on each card.
      expect(inside<DashDataTable<LowStockRow>>(find.text('NAME')), findsNothing);
      expect(find.byType(DashCard), findsWidgets);
      tolerateSiblings(h);
      final oat = InvIds.ingredient('oat');
      await h.tap(byKey('today-create-po-${SeedIds.zamalek}-$oat'));
      expect(find.byType(PurchaseOrderDialog), findsOneWidget);
    });

    testWidgets('INV-TOD-032 phone first run: text over a full-width button', (
      tester,
    ) async {
      await pumpToday(
        tester,
        size: DashSize.phone,
        branch: SeedIds.heliopolis,
      );
      final title = tester.getRect(find.text('Start by counting this branch'));
      final button = tester.getRect(byKey('today-first-count'));
      expect(button.top, greaterThan(title.bottom));
      expect(tester.widget<DashButton>(byKey('today-first-count')).expand, isTrue);
    });

    testWidgets('INV-TOD-033 the branch manager gets every action', (
      tester,
    ) async {
      await pumpToday(
        tester,
        persona: Persona.manager,
        branch: SeedIds.zamalek,
      );
      expect(find.text('Create PO'), findsNWidgets(5));
      // The orders he may read: Zamalek's two due today.
      expect(find.text('Receive'), findsNWidgets(2));
      expect(
        tester.widget<DashButton>(byKey('today-log-waste')).onPressed,
        isNotNull,
      );
    });

    testWidgets('INV-TOD-034 draft, received and cancelled are not arriving', (
      tester,
    ) async {
      final s = todayServer();
      addOrder(s.db, key: 'd', branchId: SeedIds.maadi, status: 'draft', reference: 'PO-D');
      addOrder(s.db, key: 'r', branchId: SeedIds.maadi, status: 'received', reference: 'PO-R');
      addOrder(s.db, key: 'c', branchId: SeedIds.maadi, status: 'cancelled', reference: 'PO-C');
      addOrder(s.db, key: 'p', branchId: SeedIds.maadi, status: 'partially_received', reference: 'PO-P');
      await pumpToday(tester, server: s.server, db: s.db);
      expect(kpi(tester, 'Deliveries').value, 4);
      expect(textHas('PO-D'), findsNothing);
      expect(textHas('PO-R'), findsNothing);
      expect(textHas('PO-C'), findsNothing);
      expect(textHas('PO-P'), findsOneWidget);
    });

    testWidgets('INV-TOD-035 one ingredient at two branches: two rows', (
      tester,
    ) async {
      final s = todayServer();
      setStock(s.db, SeedIds.maadi, 'oat', onHand: 500, parMin: 3600, parMax: 8100);
      final h = await pumpToday(tester, server: s.server, db: s.db);
      tolerateSiblings(h);
      final oat = InvIds.ingredient('oat');
      final keys = lowTable(tester).rows.map(lowStockRowKey).toList();
      expect(keys, containsAll(['${SeedIds.maadi}-$oat', '${SeedIds.zamalek}-$oat']));
      expect(keys.toSet(), hasLength(keys.length));
      await h.tap(byKey('today-create-po-${SeedIds.maadi}-$oat'));
      final dialog = tester.widget<PurchaseOrderDialog>(
        find.byType(PurchaseOrderDialog),
      );
      expect(dialog.branchId, SeedIds.maadi);
      expect(dialog.prefill!.lines.single.quantity, 7600);
    });

    testWidgets('INV-TOD-036 below zero: tinted, semibold, "Below zero"', (
      tester,
    ) async {
      await pumpToday(tester, branch: SeedIds.zamalek);
      final figure = tester.widget<Text>(find.textContaining('−350 ml'));
      expect(figure.style!.fontWeight, FontWeight.w600);
      expect(
        inside<DashDataTable<LowStockRow>>(find.text('Below zero')),
        findsOneWidget,
      );
      // Croissant Dough sits at exactly zero: critical, but not below zero.
      expect(textHas('0 pcs'), findsWidgets);
    });

    testWidgets('INV-TOD-037 failed reads read as zero on the KPIs', (
      tester,
    ) async {
      final s = todayServer();
      for (final r in [branchValuation, branchLow, orgOrders, stockRoute]) {
        s.server.fail(
          'GET',
          r,
          MockResponse.error(500, 'Database unavailable'),
          times: null,
        );
      }
      await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      expect(kpi(tester, 'Stock value').value, 0);
      expect(kpi(tester, 'Stock value').hint, isNull);
      expect(kpi(tester, 'Low stock').value, 0);
      expect(kpi(tester, 'Low stock').hint, '0 critical');
      expect(kpi(tester, 'Deliveries').value, 0);
      expect(kpi(tester, 'Deliveries').hint, 'arriving today');
      expect(kpi(tester, 'Counts due').value, 0);
      expect(kpi(tester, 'Counts due').valueText, isNull);
      for (final label in ['Stock value', 'Low stock', 'Deliveries', 'Counts due']) {
        expect(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is DashStatCard && w.label == label,
            ),
            matching: find.byType(DashErrorState),
          ),
          findsNothing,
        );
      }
    });

    testWidgets('INV-TOD-038 the day is kept until the zone changes', (
      tester,
    ) async {
      final s = todayServer();
      final h = await pumpToday(tester, server: s.server, db: s.db);
      // Past midnight in Cairo; the page stays open and refetches.
      s.db.clock.set(DateTime.utc(2026, 10, 8, 22, 30));
      h.container.read(realtimeBusProvider).invalidate(inventoryPathFamilies);
      await h.settle();
      expect(h.server.callsTo(orgOrders).last.query['expected_before'], [
        endOfToday,
      ]);
      // A fresh visit asks about the new day.
      tolerateSiblings(h);
      await h.go('/inventory/counts');
      await h.go(todayPath);
      expect(h.server.callsTo(orgOrders).last.query['expected_before'], [
        '2026-10-09T20:59:59.999Z',
      ]);
    });
  });

  group('realtime', () {
    testWidgets('a till event refreshes the valuation and low stock', (
      tester,
    ) async {
      final s = todayServer();
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      final low = h.server.callsTo(branchLow).length;
      final val = h.server.callsTo(branchValuation).length;
      final orders = h.server.callsTo(orgOrders).length;
      setStock(s.db, SeedIds.zamalek, 'sugar', onHand: 10, parMin: 3000);
      h.container
          .read(realtimeBusProvider)
          .dispatch(const RealtimeFrame(event: 'till.closed', data: '{}'));
      await h.settle();
      expect(h.server.callsTo(branchLow).length, low + 1);
      expect(h.server.callsTo(branchValuation).length, val + 1);
      // Orders are not under /reports: untouched.
      expect(h.server.callsTo(orgOrders).length, orders);
      expect(kpi(tester, 'Low stock').value, 6);
    });
  });
}
