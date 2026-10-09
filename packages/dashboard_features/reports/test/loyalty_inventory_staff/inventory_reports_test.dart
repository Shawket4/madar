// `/reports/inventory` Inventory reports, driven through the real app shell
// (inventory rows REP-INV-001 to -018): the gate, the tabs, the scope
// toggle and its branch gate, the four report tables, PO lead time, Low
// stock, the exports, the prefetch and the live refresh.
import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashSidebar;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/area_seed.dart';
import 'package:dashboard_reports/src/loyalty_inventory_staff/inventory_low_stock.dart';
import 'package:dashboard_reports/src/mock/loyalty_inventory_staff_mock.dart';
import 'package:dashboard_reports/src/shared/inventory_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final _from = DateTime.parse(defaultFrom);
final _to = DateTime.parse(defaultTo);

Finder get table => find.byWidgetPredicate((w) => w is DashDataTable);

/// The columns of the table on screen.
List<DashColumn<Object?>> columnsOf(WidgetTester tester) =>
    (tester.widget(table) as dynamic).columns as List<DashColumn<Object?>>;

/// The rows given to the table on screen.
List<Object?> rowsOf(WidgetTester tester) =>
    (tester.widget(table) as dynamic).rows as List<Object?>;

/// The header Export button.
Finder get headerExport => find.byKey(const ValueKey('inv-export'));

bool exportEnabled(WidgetTester tester, Finder f) =>
    tester
        .widget<DashButton>(find.descendant(of: f, matching: find.byType(DashButton)))
        .onPressed !=
    null;

/// Picks [item] ("Export Excel" / "Export CSV") from [button]'s menu.
Future<void> exportMenu(DashHarness h, Finder button, String item) async {
  await h.tap(button);
  await h.tap(find.text(item).last);
}

Future<void> pickScope(DashHarness h, String label) => h.tap(
  find.descendant(
    of: find.byKey(const ValueKey('inv-scope')),
    matching: find.text(label),
  ),
);

void main() {
  group('the gate', () {
    testWidgets('REP-INV-001 without inventory.read: Restricted "Inventory '
        'reports", neither consumption nor lead time asked', (tester) async {
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        persona: Persona.limited,
      );
      expect(find.text('Inventory reports'), findsWidgets);
      expect(find.text('Not available on this account'), findsOneWidget);
      expect(find.text(h.t('reports.noAccess')), findsOneWidget);
      expect(callsUnder(h, '/reports'), isEmpty);
      expect(headerExport, findsNothing);
      await h.shot('inventory/restricted');
    });

    testWidgets('REP-INV-001 a manager reads her branch', (tester) async {
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        persona: Persona.manager,
        branchId: SeedIds.zamalek,
      );
      final c = h.server.callsTo(branchTpl('consumption')).single;
      expect(c.path, '/reports/branches/${SeedIds.zamalek}/consumption');
      expect(c.status, 200);
    });
  });

  group('header, tabs, toggle', () {
    testWidgets('REP-INV-003 title, period, five tabs; Consumption first', (
      tester,
    ) async {
      final h = await pumpUnit(tester, path: inventoryPath);
      expect(inPage(find.text('Inventory reports')), findsOneWidget);
      expect(inPage(find.text('Last 30 days')), findsOneWidget);
      final strip = tester.widget<DashTabStrip<String>>(
        find.byType(DashTabStrip<String>),
      );
      expect([for (final t in strip.tabs) t.label], [
        'Consumption',
        'Shrinkage',
        'Waste',
        'PO lead time',
        'Low stock',
      ]);
      expect(strip.value, 'consumption');
      expect(h.server.callsTo(orgTpl('consumption')), hasLength(1));
    });

    testWidgets('REP-INV-004 without purchasing.orders.read: no PO lead '
        'time tab, never asked', (tester) async {
      final s = unitServer();
      authzWith(
        s.server,
        Persona.owner,
        capsWithout(Persona.owner, {Cap.purchasingOrdersRead}),
      );
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        server: s.server,
        db: s.db,
      );
      expect(tabLabel('PO lead time'), findsNothing);
      for (final l in ['Shrinkage', 'Waste', 'Low stock', 'Consumption']) {
        await openTab(h, l);
      }
      expect(h.server.callsTo(orgTpl('po-lead-time')), isEmpty);
      expect(h.server.callsTo(branchTpl('po-lead-time')), isEmpty);
    });

    testWidgets('REP-INV-005 the toggle starts on Whole organization with '
        'All branches, and is hidden on Low stock', (tester) async {
      final h = await pumpUnit(tester, path: inventoryPath);
      final toggle = tester.widget<DashSegmentedControl<InventoryScope>>(
        find.byType(DashSegmentedControl<InventoryScope>),
      );
      expect(toggle.value, InventoryScope.org);
      expect(inPage(find.text('This branch')), findsOneWidget);
      expect(inPage(find.text('Whole organization')), findsOneWidget);
      for (final l in ['Shrinkage', 'Waste', 'PO lead time']) {
        await openTab(h, l);
        expect(find.byKey(const ValueKey('inv-scope')), findsOneWidget);
      }
      await openTab(h, 'Low stock');
      expect(find.byKey(const ValueKey('inv-scope')), findsNothing);
    });

    testWidgets('REP-INV-005 with a branch picked it starts on This branch', (
      tester,
    ) async {
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        branchId: SeedIds.maadi,
      );
      final toggle = tester.widget<DashSegmentedControl<InventoryScope>>(
        find.byType(DashSegmentedControl<InventoryScope>),
      );
      expect(toggle.value, InventoryScope.branch);
      expect(
        h.server.callsTo(branchTpl('consumption')).single.path,
        '/reports/branches/${SeedIds.maadi}/consumption',
      );
      // The toggle does not follow later scope-bar changes.
      await h.container.read(scopeProvider.notifier).setBranch(null);
      await h.settle();
      expect(
        tester
            .widget<DashSegmentedControl<InventoryScope>>(
              find.byType(DashSegmentedControl<InventoryScope>),
            )
            .value,
        InventoryScope.branch,
      );
    });

    testWidgets('REP-INV-006 This branch with All branches: "Select a branch '
        'to manage its stock", export disabled; Low stock still shows', (
      tester,
    ) async {
      final h = await pumpUnit(tester, path: inventoryPath);
      final before = callsUnder(h, '/reports').length;
      await pickScope(h, 'This branch');
      expect(
        inPage(find.text('Select a branch to manage its stock')),
        findsOneWidget,
      );
      expect(table, findsNothing);
      expect(exportEnabled(tester, headerExport), isFalse);
      expect(callsUnder(h, '/reports'), hasLength(before));
      await h.shot('inventory/branch-gate');
      await openTab(h, 'Low stock');
      expect(
        inPage(find.text('Select a branch to manage its stock')),
        findsNothing,
      );
      expect(h.server.callsTo(orgTpl('low-stock')), hasLength(1));
    });

    testWidgets('REP-INV-002 no org in scope: "Select an organization to '
        'manage inventory"', (tester) async {
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        persona: Persona.platform,
      );
      expect(
        inPage(find.text('Select an organization to manage inventory')),
        findsOneWidget,
      );
      expect(callsUnder(h, '/reports'), isEmpty);
      expect(find.byType(DashTabStrip<String>), findsNothing);
      await h.shot('inventory/no-org');
    });

    testWidgets('REP-INV-007 only the open tab asks, from the endpoint the '
        'toggle names, with from/to', (tester) async {
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        branchId: SeedIds.newCairo,
      );
      expect(callsUnder(h, '/reports').map((c) => c.template), [
        branchTpl('consumption'),
      ]);
      await openTab(h, 'Shrinkage');
      final shr = h.server.callsTo(branchTpl('shrinkage')).single;
      expect(shr.path, '/reports/branches/${SeedIds.newCairo}/shrinkage');
      expect(shr.query['from'], [defaultFrom]);
      expect(shr.query['to'], [defaultTo]);
      await pickScope(h, 'Whole organization');
      final org = h.server.callsTo(orgTpl('shrinkage')).single;
      expect(org.path, '/reports/orgs/${SeedIds.sabahOrg}/shrinkage');
      expect(org.query['from'], [defaultFrom]);
      await openTab(h, 'Waste');
      await openTab(h, 'PO lead time');
      expect(h.server.callsTo(orgTpl('waste-report')), hasLength(1));
      expect(h.server.callsTo(orgTpl('po-lead-time')), hasLength(1));
      expect(h.server.callsTo(branchTpl('waste-report')), isEmpty);
      expect(callsUnder(h, '/reports').every((c) => c.status == 200), isTrue);
    });
  });

  group('the report tables', () {
    testWidgets('REP-INV-008 Consumption: Ingredient, Quantity, Consumed '
        'value', (tester) async {
      final h = await pumpUnit(tester, path: inventoryPath);
      final f = fmtOf(h);
      final rows = inventoryConsumption(
        SeedIds.sabahBranches,
        from: _from,
        to: _to,
      );
      expect([for (final c in columnsOf(tester)) c.label], [
        'Ingredient',
        'Quantity',
        'Consumed value',
      ]);
      final first = rows.first;
      expect(inPage(find.text(first.ingredientName)), findsOneWidget);
      expect(
        inPage(figure('${f.fmtNumber(first.consumedQty)} ${fmtUnit(first.unit)}')),
        findsOneWidget,
      );
      expect(inPage(figure(f.fmtMoney(first.consumedValue))), findsOneWidget);
      // An unknown cost reads "—", never 0.
      final chai = rows.firstWhere((r) => r.consumedValue == null);
      expect(rowsOf(tester), hasLength(rows.length));
      expect(
        (rowsOf(tester).firstWhere(
          (r) => (r as dynamic).key == chai.orgIngredientId,
        ) as dynamic).cells[2],
        '—',
      );
      await h.shot('inventory/consumption');
    });

    testWidgets('REP-INV-009 Shrinkage: reasons in words ("unexplained" is '
        'Other; an unknown code as is)', (tester) async {
      final s = unitServer();
      s.server.on(
        'GET',
        orgTpl('shrinkage'),
        (req) => MockResponse.ok([
          for (final (reason, qty) in [
            ('unexplained', 3.0),
            ('theft', 2.0),
            ('supplier_short', 1.5),
            ('lost_in_flood', 1.0),
          ])
            ShrinkageRow(
              reason: reason,
              orgIngredientId: reportIngredient('whole_milk').id,
              ingredientName: 'Whole milk',
              unit: 'l',
              shrinkageQty: qty,
              shrinkageValue: (qty * 4300).round(),
            ),
        ]),
      );
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Shrinkage');
      expect([for (final c in columnsOf(tester)) c.label], [
        'Ingredient',
        'Reason',
        'Quantity',
        'Value',
      ]);
      for (final w in ['Other', 'Theft', 'Supplier short', 'lost_in_flood']) {
        expect(inPage(find.text(w)), findsOneWidget, reason: w);
      }
      // `l` reads `L`.
      expect(inPage(figure('3 L')), findsOneWidget);
      expect(inPage(figure('EGP 129.00')), findsOneWidget);
      await h.shot('inventory/shrinkage');
    });

    testWidgets('REP-INV-009 Shrinkage reasons in Arabic', (tester) async {
      final h = await pumpUnit(tester, path: inventoryPath, locale: 'ar');
      await openTab(h, 'العجز');
      expect(inPage(find.text('أخرى')), findsWidgets);
      expect(inPage(find.text('خطأ في العد')), findsWidgets);
    });

    testWidgets('REP-INV-010 Waste: Ingredient, Reason, Quantity, Waste '
        'value', (tester) async {
      final h = await pumpUnit(tester, path: inventoryPath);
      await openTab(h, 'Waste');
      expect([for (final c in columnsOf(tester)) c.label], [
        'Ingredient',
        'Reason',
        'Quantity',
        'Waste value',
      ]);
      final rows = inventoryWasteReport(
        SeedIds.sabahBranches,
        from: _from,
        to: _to,
      );
      expect(rowsOf(tester), hasLength(rows.length));
      for (final w in [
        'Expired',
        'Spoiled',
        'Overproduction',
        'Damaged',
        'Voided order',
        'Refunded sale',
        'Other',
        'Theft',
      ]) {
        expect(inPage(find.text(w)), findsWidgets, reason: w);
      }
      await h.shot('inventory/waste');
    });

    testWidgets('REP-INV-011 PO lead time: the overall average (1 dp) and '
        'by supplier', (tester) async {
      final h = await pumpUnit(tester, path: inventoryPath);
      await openTab(h, 'PO lead time');
      final r = inventoryPoLeadTime(
        SeedIds.sabahBranches,
        from: _from,
        to: _to,
      );
      final f = fmtOf(h);
      String days(num v) =>
          f.fmtNumber(v, const NumberOptions(maximumFractionDigits: 1));
      final kpi = tester.widget<DashStatCard>(
        find.byKey(const ValueKey('overall')),
      );
      expect(kpi.label, 'Avg lead time (days)');
      expect(kpi.valueText, days(r.overallAvgDays));
      expect([for (final c in columnsOf(tester)) c.label], [
        'Supplier',
        'Orders received',
        'Avg lead time (days)',
      ]);
      final top = r.bySupplier.first;
      final row =
          rowsOf(tester).first as dynamic;
      expect(row.cells, [
        top.supplierName,
        f.fmtNumber(top.ordersReceived),
        days(top.avgLeadTimeDays),
      ]);
      await h.shot('inventory/lead-time');
    });

    testWidgets('REP-INV-011 PO lead time loading: the KPI and the table '
        'wait', (tester) async {
      final s = unitServer();
      final gate = s.server.hold('GET', orgTpl('po-lead-time'));
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'PO lead time');
      expect(
        tester.widget<DashStatCard>(find.byKey(const ValueKey('overall'))).loading,
        isTrue,
      );
      gate.release();
      await h.settle();
      expect(
        tester.widget<DashStatCard>(find.byKey(const ValueKey('overall'))).loading,
        isFalse,
      );
    });

    testWidgets('REP-INV-012 25 rows a page, no Columns menu, the first '
        'column the phone title', (tester) async {
      final s = unitServer();
      s.server.on(
        'GET',
        orgTpl('consumption'),
        (req) => MockResponse.ok([
          for (var i = 0; i < 30; i++)
            ConsumptionRow(
              orgIngredientId: mockUuid('probe:$i'),
              ingredientName: 'Ingredient ${i + 1}',
              unit: 'kg',
              consumedQty: 30.0 - i,
              consumedValue: 1000 * (30 - i),
            ),
        ]),
      );
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        server: s.server,
        db: s.db,
      );
      final t = tester.widget(table) as dynamic;
      expect(t.pageSize, 25);
      expect(t.hideViewOptions, isTrue);
      expect(columnsOf(tester).first.phone, DashPhoneRole.title);
      expect(inPage(find.text('Page 1 of 2')), findsOneWidget);
      expect(inPage(find.text('Columns')), findsNothing);
      expect(inPage(find.text('Ingredient 26')), findsNothing);
    });

    testWidgets('REP-INV-012 loading: skeleton rows, never "nothing '
        'recorded"', (tester) async {
      final s = unitServer();
      final gate = s.server.hold('GET', orgTpl('consumption'));
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        server: s.server,
        db: s.db,
      );
      expect((tester.widget(table) as dynamic).loading, isTrue);
      expect(
        inPage(find.text('Nothing recorded for this scope and period.')),
        findsNothing,
      );
      expect(exportEnabled(tester, headerExport), isFalse);
      await h.shot('inventory/loading');
      gate.release();
      await h.settle();
      expect(exportEnabled(tester, headerExport), isTrue);
    });

    testWidgets('REP-INV-012 failed: the server\'s words + Retry, asking '
        'only that read', (tester) async {
      final s = unitServer();
      final boom = MockResponse.error(500, 'The report could not be built');
      s.server.fail('GET', orgTpl('consumption'), boom);
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        server: s.server,
        db: s.db,
      );
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inPage(find.text(h.refusalWords(boom))), findsOneWidget);
      await h.shot('inventory/failed');
      final others = callsUnder(h, '/reports').length;
      await h.tap(inPage(find.text('Retry')));
      expect(callsUnder(h, '/reports'), hasLength(others + 1));
      expect(h.server.callsTo(orgTpl('consumption')), hasLength(2));
      expect(table, findsOneWidget);
      expect(inPage(find.text("Couldn't load this")), findsNothing);
    });

    testWidgets('REP-INV-012 a refusal from the server shows its words', (
      tester,
    ) async {
      final s = unitServer();
      final denied = MockResponse.denied('inventory.read');
      s.server.fail('GET', orgTpl('waste-report'), denied);
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Waste');
      expect(inPage(find.text(h.refusalWords(denied))), findsOneWidget);
    });

    testWidgets('REP-INV-012 empty: "Nothing recorded for this scope and '
        'period."', (tester) async {
      final s = unitServer();
      s.server.on('GET', orgTpl('consumption'), (req) => MockResponse.ok([]));
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        server: s.server,
        db: s.db,
      );
      expect(
        inPage(find.text('Nothing recorded for this scope and period.')),
        findsOneWidget,
      );
      expect(exportEnabled(tester, headerExport), isFalse);
      await h.shot('inventory/empty');
    });
  });

  group('the header export', () {
    testWidgets('REP-INV-013/014 Consumption to Excel: Madar-Consumption, '
        'the scope\'s words, the columns', (tester) async {
      final h = await pumpUnit(tester, path: inventoryPath);
      expect(exportEnabled(tester, headerExport), isTrue);
      await exportMenu(h, headerExport, 'Export Excel');
      await h.settle();
      final rows = inventoryConsumption(
        SeedIds.sabahBranches,
        from: _from,
        to: _to,
      );
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.title, 'Consumption');
      expect(sheet.name, 'Consumption');
      expect(sheet.subtitle, startsWith('Whole organization'));
      expect([for (final c in sheet.columns) c.header], [
        'Ingredient',
        'Quantity',
        'Unit',
        'Consumed value',
      ]);
      expect(sheet.rows, hasLength(rows.length));
      expect(sheet.rows.first.take(3), [
        rows.first.ingredientName,
        rows.first.consumedQty,
        fmtUnit(rows.first.unit),
      ]);
      expect(
        h.files.saved.single.filename,
        'Madar-Consumption-${exportStamp(h)}.xlsx',
      );
      await h.expectToast('Exported ${rows.length} rows');
    });

    testWidgets('REP-INV-014 Shrinkage and Waste sheets; This branch\'s '
        'words', (tester) async {
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        branchId: SeedIds.zamalek,
      );
      await openTab(h, 'Shrinkage');
      await exportMenu(h, headerExport, 'Export Excel');
      await h.settle();
      await openTab(h, 'Waste');
      await exportMenu(h, headerExport, 'Export Excel');
      await h.settle();
      final shr = h.exports.built[0].sheets.single;
      expect(shr.title, 'Shrinkage');
      expect(shr.subtitle, startsWith('This branch'));
      expect([for (final c in shr.columns) c.header], [
        'Ingredient',
        'Reason',
        'Quantity',
        'Unit',
        'Value',
      ]);
      final waste = h.exports.built[1].sheets.single;
      expect(waste.title, 'Waste');
      expect([for (final c in waste.columns) c.header], [
        'Ingredient',
        'Reason',
        'Quantity',
        'Unit',
        'Waste value',
      ]);
      final rows = inventoryWasteReport(
        [SeedIds.zamalek],
        from: _from,
        to: _to,
      );
      expect(waste.rows.first.take(4), [
        rows.first.ingredientName,
        h.t('inventory.waste.reasons.${rows.first.reason}'),
        rows.first.wasteQty,
        fmtUnit(rows.first.unit),
      ]);
      expect(
        [for (final f in h.files.saved) f.filename],
        [
          'Madar-Shrinkage-${exportStamp(h)}.xlsx',
          'Madar-Waste-${exportStamp(h)}.xlsx',
        ],
      );
      await h.flushTimers();
    });

    testWidgets('REP-INV-014 PO lead time to CSV: the first sheet, money-free '
        'numbers', (tester) async {
      final h = await pumpUnit(tester, path: inventoryPath);
      await openTab(h, 'PO lead time');
      await exportMenu(h, headerExport, 'Export CSV');
      await h.settle();
      final file = h.files.saved.single;
      expect(file.filename, 'Madar-PO lead time-${exportStamp(h)}.csv');
      final lines = file.asString.split('\r\n');
      expect(lines.first, 'Supplier,Orders received,Avg lead time (days)');
      final r = inventoryPoLeadTime(
        SeedIds.sabahBranches,
        from: _from,
        to: _to,
      );
      expect(lines, hasLength(r.bySupplier.length + 1));
      expect(lines[1], startsWith('${r.bySupplier.first.supplierName},'));
      await h.expectToast('Exported ${r.bySupplier.length} rows');
    });

    testWidgets('REP-INV-013 the Excel spinner; a failure says "Export '
        'failed"', (tester) async {
      final h = await pumpUnit(tester, path: inventoryPath);
      final hold = Completer<void>();
      h.exports.hold = hold.future;
      await exportMenu(h, headerExport, 'Export Excel');
      await h.settle();
      final button = tester.widget<DashButton>(
        find.descendant(of: headerExport, matching: find.byType(DashButton)),
      );
      expect(button.loading, isTrue);
      expect(find.text('Gathering data…'), findsOneWidget);
      await h.shot('inventory/exporting');
      hold.complete();
      await h.settle();
      await h.flushTimers();
      h.exports.hold = null;
      h.exports.failNext = StateError('disk full');
      await exportMenu(h, headerExport, 'Export Excel');
      await h.settle();
      await h.expectToast('Export failed');
    });

    testWidgets('REP-INV-013 no export on Low stock\'s header', (tester) async {
      final h = await pumpUnit(tester, path: inventoryPath);
      await openTab(h, 'Low stock');
      expect(headerExport, findsNothing);
      expect(find.byKey(const ValueKey('low-stock-export')), findsOneWidget);
    });
  });

  group('low stock', () {
    testWidgets('REP-INV-015/016 All branches: the org list with a Branch '
        'column; the pills; below zero', (tester) async {
      final s = unitServer();
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Low stock');
      expect(
        h.server.callsTo(orgTpl('low-stock')).single.path,
        '/reports/orgs/${SeedIds.sabahOrg}/low-stock',
      );
      expect([for (final c in columnsOf(tester)) c.label], [
        'Name',
        'Branch',
        'On hand',
        'Reorder point',
        'Order',
        'Supplier',
      ]);
      final t = tester.widget(table) as dynamic;
      expect(t.pageSize, 50);
      expect(t.hideViewOptions, isFalse);
      expect(inPage(find.text('Columns')), findsOneWidget);
      final rows = inventoryLowStock(s.db, SeedIds.sabahBranches);
      expect(rowsOf(tester), hasLength(rows.length));
      // Maadi's oat milk is below zero: Critical, tinted, "Below zero".
      expect(inPage(find.text('Oat milk')), findsOneWidget);
      expect(inPage(find.text('Critical')), findsNWidgets(2));
      expect(inPage(find.text('Low')), findsOneWidget);
      expect(inPage(find.text('Below zero')), findsOneWidget);
      expect(inPage(figure('−2 L')), findsOneWidget);
      final f = fmtOf(h);
      final milk = rows.firstWhere((r) => r.ingredientName == 'Whole milk');
      expect(inPage(figure('${f.fmtNumber(milk.parMin)} L')), findsOneWidget);
      expect(
        inPage(figure('${f.fmtNumber(milk.suggestedQty)} L')),
        findsOneWidget,
      );
      expect(inPage(find.text('Delta Dairy Co.')), findsNWidgets(2));
      expect(inPage(find.text('New Cairo')), findsOneWidget);
      await h.shot('inventory/low-stock');
    });

    testWidgets('REP-INV-015/016 a branch picked: its list, no Branch '
        'column; the toggle plays no part', (tester) async {
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        branchId: SeedIds.maadi,
      );
      await pickScope(h, 'Whole organization');
      await openTab(h, 'Low stock');
      expect(
        h.server.callsTo(branchTpl('low-stock')).single.path,
        '/reports/branches/${SeedIds.maadi}/low-stock',
      );
      expect(h.server.callsTo(orgTpl('low-stock')), isEmpty);
      expect(
        [for (final c in columnsOf(tester)) c.label],
        isNot(contains('Branch')),
      );
      expect(rowsOf(tester), hasLength(1));
    });

    testWidgets('REP-INV-016 a supplier-less row reads "—"', (tester) async {
      final s = unitServer();
      s.server.on(
        'GET',
        orgTpl('low-stock'),
        (req) => MockResponse.ok([
          LowStockRow(
            branchId: SeedIds.maadi,
            branchName: 'Maadi',
            orgIngredientId: mockUuid('probe:napkins'),
            ingredientName: 'Napkins',
            unit: 'pcs',
            onHand: 40,
            parMin: 50,
            suggestedQty: 110,
          ),
        ]),
      );
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Low stock');
      expect(inPage(find.text('—')), findsOneWidget);
      expect(inPage(find.text('Low')), findsOneWidget);
    });

    testWidgets('REP-INV-017 its own export: Madar-Low stock, the columns', (
      tester,
    ) async {
      final s = unitServer();
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Low stock');
      final export = find.byKey(const ValueKey('low-stock-export'));
      await exportMenu(h, export, 'Export Excel');
      await h.settle();
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.title, 'Low stock');
      expect([for (final c in sheet.columns) c.header], [
        'Name',
        'Branch',
        'On hand',
        'Reorder point',
        'Order',
        'Unit',
        'Supplier',
      ]);
      final rows = inventoryLowStock(s.db, SeedIds.sabahBranches);
      expect(sheet.rows.first, [
        rows.first.ingredientName,
        rows.first.branchName,
        rows.first.onHand,
        rows.first.parMin,
        rows.first.suggestedQty,
        'L',
        rows.first.supplierName,
      ]);
      expect(
        h.files.saved.single.filename,
        'Madar-Low stock-${exportStamp(h)}.xlsx',
      );
      await h.expectToast('Exported ${rows.length} rows');
      await exportMenu(h, export, 'Export CSV');
      await h.settle();
      expect(h.files.saved.last.filename, 'Madar-Low stock-${exportStamp(h)}.csv');
      await h.flushTimers();
    });

    testWidgets('REP-INV-017/018 empty: "Nothing below its reorder point", '
        'export disabled', (tester) async {
      final s = unitServer();
      s.server.on('GET', orgTpl('low-stock'), (req) => MockResponse.ok([]));
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Low stock');
      expect(
        inPage(find.text('Nothing below its reorder point')),
        findsOneWidget,
      );
      expect(
        exportEnabled(tester, find.byKey(const ValueKey('low-stock-export'))),
        isFalse,
      );
      await h.shot('inventory/low-stock-empty');
    });

    testWidgets('REP-INV-018 loading: skeleton rows, never the empty '
        'words', (tester) async {
      final s = unitServer();
      final gate = s.server.hold('GET', orgTpl('low-stock'));
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Low stock');
      expect((tester.widget(table) as dynamic).loading, isTrue);
      expect(inPage(find.text('Nothing below its reorder point')), findsNothing);
      gate.release();
      await h.settle();
      expect(inPage(find.text('Oat milk')), findsOneWidget);
    });

    testWidgets('REP-INV-018 failed: the server\'s words + Retry', (
      tester,
    ) async {
      final s = unitServer();
      final down = MockResponse.error(500, 'Stock is being recounted');
      s.server.fail('GET', orgTpl('low-stock'), down);
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Low stock');
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inPage(find.text(h.refusalWords(down))), findsOneWidget);
      expect(
        exportEnabled(tester, find.byKey(const ValueKey('low-stock-export'))),
        isFalse,
      );
      await h.shot('inventory/low-stock-failed');
      await h.tap(inPage(find.text('Retry')));
      expect(h.server.callsTo(orgTpl('low-stock')), hasLength(2));
      expect(inPage(find.text('Oat milk')), findsOneWidget);
      // No reorder actions here.
      expect(inPage(find.text('Create PO')), findsNothing);
    });

    testWidgets('REP-INV-016 the phone cards: the name heads each card', (
      tester,
    ) async {
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        size: DashSize.phone,
        locale: 'ar',
      );
      await openTab(h, 'مخزون منخفض');
      expect(inPage(find.text('Oat milk')), findsOneWidget);
      expect(inPage(find.text('تحت الصفر')), findsOneWidget);
      expect(find.byType(OnHandFigure), findsWidgets);
      await h.shot('inventory/low-stock');
    });
  });

  group('live and warm', () {
    testWidgets('REP-INV-007 a till event refetches the open report', (
      tester,
    ) async {
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        branchId: SeedIds.zamalek,
      );
      expect(h.server.callsTo(branchTpl('consumption')), hasLength(1));
      h.realtime.current!.emit('till.closed', data: '{}');
      await h.settle();
      expect(h.server.callsTo(branchTpl('consumption')), hasLength(2));
    });

    Future<void> hoverInventory(DashHarness h, WidgetTester tester) async {
      final row = find
          .descendant(
            of: find.byType(DashSidebar),
            matching: find.text(h.t('nav.reportsInventory')),
          )
          // Reports › Inventory comes before the Inventory group.
          .first;
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find
            .descendant(
              of: find.byType(DashSidebar),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await h.settle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(row));
      await h.settle();
    }

    testWidgets('REP-ALL-029 pointing at Inventory warms the branch\'s '
        'consumption; opening it asks nothing more', (tester) async {
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        branchId: SeedIds.zamalek,
      );
      expect(h.server.callsTo(branchTpl('consumption')), isEmpty);
      await hoverInventory(h, tester);
      final warmed = h.server.callsTo(branchTpl('consumption'));
      expect(warmed, hasLength(1), reason: 'warmed on hover');
      expect(warmed.single.path, '/reports/branches/${SeedIds.zamalek}/consumption');
      expect(warmed.single.query['from'], [defaultFrom]);
      await h.go(inventoryPath);
      expect(h.location.path, inventoryPath);
      expect(h.server.callsTo(branchTpl('consumption')), hasLength(1));
      expect(table, findsOneWidget);
    });

    testWidgets('REP-ALL-029 with All branches the org\'s consumption is '
        'warmed', (tester) async {
      final h = await pumpUnit(tester, path: loyaltyPath);
      await hoverInventory(h, tester);
      expect(h.server.callsTo(orgTpl('consumption')), hasLength(1));
      await h.go(inventoryPath);
      expect(h.server.callsTo(orgTpl('consumption')), hasLength(1));
    });
  });

  testWidgets('REP-INV-003 Arabic: the tabs and the toggle read in Arabic', (
    tester,
  ) async {
    final h = await pumpUnit(
      tester,
      path: inventoryPath,
      locale: 'ar',
      size: DashSize.phone,
    );
    expect(inPage(find.text('تقارير المخزون')), findsOneWidget);
    expect(tabLabel('الاستهلاك'), findsOneWidget);
    expect(inPage(find.text('كل المؤسسة')), findsOneWidget);
    await h.shot('inventory/phone');
  });
}
