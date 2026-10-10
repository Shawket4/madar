// Financial's inventory-backed tabs and their export (REP-FIN-066…070).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/financial/fin_data.dart';
import 'package:dashboard_reports/src/mock/financial_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<DashHarness> openInv(
  WidgetTester t,
  String tabKey, {
  ({MockServer server, MockDb db})? s,
  String? branchId,
  Persona persona = Persona.owner,
}) async {
  final h = await pumpFin(
    t,
    server: s?.server,
    db: s?.db,
    branchId: branchId,
    persona: persona,
  );
  await openTab(h, h.t(tabKey));
  return h;
}

const _valuation = 'reports.financial.tabs.valuation';
const _spend = 'reports.financial.tabs.supplierSpend';
const _trend = 'reports.financial.tabs.materialCostTrend';

Finder exportButton() => find.byKey(const ValueKey('fin-inventory-export'));

Future<void> menu(DashHarness h, String item) async {
  await h.tap(exportButton());
  await h.tap(find.text(item).last);
}

String stamp(DashHarness h) =>
    isoString(h.container.read(clockProvider)()).substring(0, 10);

void main() {
  setUpAll(ensureTimeZones);

  group('valuation', () {
    testWidgets('REP-FIN-066 the KPIs and the value by catalog category, '
        'largest first; archived stock is Uncategorized', (t) async {
      final h = await openInv(t, _valuation);
      expect(
        callsTo(h, catalogRoute).single.path,
        '/inventory/orgs/${SeedIds.sabahOrg}/catalog',
      );
      final v = finValuation(SeedIds.sabahBranches);
      final f = h.container.read(formatProvider);
      expect(
        t.widget<DashStatCard>(kpiCard('Total value')).value,
        v.totalValue,
      );
      final unknown = t.widget<DashStatCard>(kpiCard('Unknown cost'));
      expect(unknown.value, v.unknownCostCount);
      expect(
        unknown.tone,
        v.unknownCostCount > 0 ? DashTone.warning : DashTone.neutral,
      );
      final rows = finByCategory(
        v,
        finCatalog(SeedIds.sabahOrg),
        'Uncategorized',
      );
      expect(rows.last.$1, 'Uncategorized');
      final list = find.byKey(const ValueKey('fin-by-category'));
      final names = [
        for (final e
            in find
                .descendant(of: list, matching: find.byType(Text))
                .evaluate())
          (e.widget as Text).data,
      ];
      expect(names, [
        for (final (c, value) in rows) ...[c, dashFigure(f.fmtMoney(value))],
      ]);
      final bars = t.widgetList<DashProgressBar>(
        find.descendant(of: list, matching: find.byType(DashProgressBar)),
      );
      expect(bars.first.value, bars.first.max);
      expect(bars.first.max, rows.first.$2.toDouble());
    });

    testWidgets('REP-FIN-066 with a branch picked: that branch\'s valuation', (
      t,
    ) async {
      final h = await openInv(t, _valuation, branchId: SeedIds.maadi);
      expect(
        callsTo(h, branchValuationRoute).single.path,
        '/reports/branches/${SeedIds.maadi}/inventory-valuation',
      );
      expect(callsTo(h, orgValuationRoute), isEmpty);
      await pickSegment(h, 'fin-inv-scope', 'Whole organization');
      expect(callsTo(h, orgValuationRoute), hasLength(1));
    });

    testWidgets('REP-FIN-073 the KPI strip is capped at 672 px from 1024', (
      t,
    ) async {
      await openInv(t, _valuation);
      final strip = find.ancestor(
        of: kpiCard('Total value'),
        matching: find.byType(DashLedgerStrip),
      );
      expect(t.getSize(strip).width, 672);
    });

    testWidgets('REP-FIN-066 loading: four skeleton rows', (t) async {
      final s = finServer();
      final gate = s.server.hold('GET', orgValuationRoute);
      final h = await openInv(t, _valuation, s: s);
      expect(
        find.byKey(const ValueKey('fin-by-category-loading')),
        findsOneWidget,
      );
      expect(pageText(h.t('inventory.reports.noValuation')), findsNothing);
      gate.release();
      await h.settle();
      expect(find.byKey(const ValueKey('fin-by-category')), findsOneWidget);
    });

    testWidgets('REP-FIN-067 a failure replaces the KPIs and the list: '
        '"Couldn\'t load stock valuation" and Retry', (t) async {
      final s = finServer();
      // Twice: the tab press's warm-up fails too (dropped, read again).
      s.server.fail(
        'GET',
        orgValuationRoute,
        MockResponse.error(500, 'boom'),
        times: 2,
      );
      final h = await openInv(t, _valuation, s: s);
      expect(pageText("Couldn't load stock valuation"), findsOneWidget);
      expect(find.byType(DashStatCard), findsNothing);
      final reads = callsTo(h, orgValuationRoute).length;
      await h.tap(inPage(find.text('Retry')));
      expect(callsTo(h, orgValuationRoute), hasLength(reads + 1));
      expect(find.byKey(const ValueKey('fin-by-category')), findsOneWidget);
      await h.shot('financial/valuation-failed');
    });

    testWidgets('REP-FIN-067 a refusal reads the same way', (t) async {
      final s = finServer();
      s.server.fail(
        'GET',
        orgValuationRoute,
        MockResponse.denied('inventory.read'),
        times: null,
      );
      await openInv(t, _valuation, s: s);
      expect(pageText("Couldn't load stock valuation"), findsOneWidget);
    });
  });

  group('supplier spend', () {
    testWidgets('REP-FIN-068 Supplier, Orders, Total spend for the org over '
        'the period', (t) async {
      final h = await openInv(t, _spend);
      final call = callsTo(h, orgSpendRoute).single;
      expect(call.query.keys.toSet(), {'from', 'to'});
      for (final c in ['SUPPLIER', 'ORDERS', 'TOTAL SPEND']) {
        expect(pageText(c), findsOneWidget, reason: c);
      }
      final scope = h.container.read(currentScopeProvider);
      final rows = finSupplierSpend(
        SeedIds.sabahBranches,
        from: DateTime.parse(scope.from),
        to: DateTime.parse(scope.to),
      );
      final f = h.container.read(formatProvider);
      expect(pageText(rows.first.supplierName), findsOneWidget);
      expect(inPage(figure(f.fmtMoney(rows.first.totalSpend))), findsOneWidget);
      expect(pageText('Columns'), findsNothing);
    });

    testWidgets('REP-FIN-068 a branch: its own spend', (t) async {
      final h = await openInv(t, _spend, branchId: SeedIds.newCairo);
      expect(
        callsTo(h, branchSpendRoute).single.path,
        '/reports/branches/${SeedIds.newCairo}/supplier-spend',
      );
    });

    testWidgets('REP-FIN-068 loading, a failure with Retry, empty', (t) async {
      final s = finServer();
      final gate = s.server.hold('GET', orgSpendRoute);
      final h = await openInv(t, _spend, s: s);
      expect(inPage(find.byType(DashSkeleton)), findsWidgets);
      expect(pageText(h.t('inventory.reports.noDataPeriod')), findsNothing);
      gate.release();
      await h.settle();
      // A failure with nothing to show yet: a period never read.
      final boom = MockResponse.error(500, 'Purchasing is down.');
      s.server.fail('GET', orgSpendRoute, boom);
      await h.container
          .read(scopeProvider.notifier)
          .setPreset(ScopePreset.last7Days);
      await h.settle();
      expect(pageText(h.refusalWords(boom)), findsOneWidget);
      s.server.on('GET', orgSpendRoute, (req) => MockResponse.ok(<Object?>[]));
      await h.tap(inPage(find.text('Retry')));
      expect(pageText(h.t('inventory.reports.noDataPeriod')), findsOneWidget);
    });
  });

  group('material cost trend', () {
    testWidgets('REP-FIN-069 the columns, the rise badge and the switch '
        'suggestion (or "—")', (t) async {
      final h = await openInv(t, _trend);
      for (final c in [
        'INGREDIENT',
        'SUPPLIER',
        'CURRENT COST',
        'PRICE TREND',
        'SUGGESTION',
      ]) {
        expect(pageText(c), findsOneWidget, reason: c);
      }
      final scope = h.container.read(currentScopeProvider);
      final rows = finMaterialCostTrend(
        SeedIds.sabahBranches,
        from: DateTime.parse(scope.from),
        to: DateTime.parse(scope.to),
      );
      final f = h.container.read(formatProvider);
      for (final r in rows) {
        final pct = f.fmtNumber(
          r.pctIncrease,
          const NumberOptions(maximumFractionDigits: 1),
        );
        expect(
          pageText('+$pct% over ${r.streakLength} deliveries'),
          findsOneWidget,
        );
        if (r.cheaperSupplierName != null) {
          expect(
            pageText(
              'Switch to ${r.cheaperSupplierName} (${f.fmtMoney(r.cheaperCost)})',
            ),
            findsOneWidget,
          );
        }
      }
      expect(rows.any((r) => r.cheaperSupplierName == null), isTrue);
      expect(pageText('—'), findsWidgets);
    });

    testWidgets('REP-FIN-069 empty: the period words and why', (t) async {
      final s = finServer();
      s.server.on('GET', orgTrendRoute, (req) => MockResponse.ok(<Object?>[]));
      final h = await openInv(t, _trend, s: s);
      expect(pageText(h.t('inventory.reports.noDataPeriod')), findsOneWidget);
      expect(
        pageText(
          'Nothing has had 3 straight price rises from its current supplier '
          'this period.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('REP-FIN-069 loading and a failure with Retry', (t) async {
      final s = finServer();
      final gate = s.server.hold('GET', orgTrendRoute);
      final h = await openInv(t, _trend, s: s);
      expect(inPage(find.byType(DashSkeleton)), findsWidgets);
      gate.release();
      await h.settle();
      final boom = MockResponse.error(500, 'Trend unavailable.');
      s.server.fail('GET', orgTrendRoute, boom);
      await h.container
          .read(scopeProvider.notifier)
          .setPreset(ScopePreset.last7Days);
      await h.settle();
      expect(pageText(h.refusalWords(boom)), findsOneWidget);
      final reads = callsTo(h, orgTrendRoute).length;
      await h.tap(inPage(find.text('Retry')));
      expect(callsTo(h, orgTrendRoute), hasLength(reads + 1));
      expect(pageText(h.refusalWords(boom)), findsNothing);
      expect(inPage(find.text('Retry')), findsNothing);
    });
  });

  group('export', () {
    testWidgets('REP-FIN-070 Valuation: "By category", "Total value", '
        'subtitled by the scope, Madar-Valuation', (t) async {
      final h = await openInv(t, _valuation);
      await menu(h, 'Export Excel');
      final rows = finByCategory(
        finValuation(SeedIds.sabahBranches),
        finCatalog(SeedIds.sabahOrg),
        'Uncategorized',
      );
      await h.expectToast('Exported ${rows.length} rows');
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.title, 'Valuation');
      expect(
        [for (final c in sheet.columns) c.header],
        ['By category', 'Total value'],
      );
      expect(sheet.subtitle, startsWith('Whole organization'));
      expect(sheet.rows.first.first, rows.first.$1);
      expect(h.files.saved.single.filename, 'Madar-Valuation-${stamp(h)}.xlsx');
      // The loaded data: no request.
      expect(callsTo(h, orgValuationRoute), hasLength(1));
    });

    testWidgets('REP-FIN-070 Supplier spend to CSV, "This branch"', (t) async {
      final h = await openInv(t, _spend, branchId: SeedIds.maadi);
      await menu(h, 'Export CSV');
      await h.flushTimers();
      expect(
        h.files.saved.single.filename,
        'Madar-Supplier spend-${stamp(h)}.csv',
      );
      final text = String.fromCharCodes(h.files.saved.single.bytes);
      expect(text.split('\n').first, startsWith('Supplier,Orders,Total spend'));
    });

    testWidgets('REP-FIN-070 Material cost trend: the five columns, the rise '
        'as "+pct%" text', (t) async {
      final h = await openInv(t, _trend);
      await menu(h, 'Export Excel');
      await h.flushTimers();
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.title, 'Material cost trend');
      expect(
        [for (final c in sheet.columns) c.header],
        ['Ingredient', 'Supplier', 'Current cost', 'Price trend', 'Suggestion'],
      );
      expect([for (final c in sheet.columns) c.width], [26, 22, 14, 14, 22]);
      expect(sheet.rows.first[3], matches(RegExp(r'^\+[\d.]+%$')));
    });

    testWidgets('REP-FIN-070 never disabled; an empty table: "Nothing to '
        'export"', (t) async {
      final h = await openInv(t, _spend);
      await pickSegment(h, 'fin-inv-scope', 'This branch');
      expect(t.widget<DashExportButton>(exportButton()).enabled, isTrue);
      await menu(h, 'Export Excel');
      await h.expectToast('Nothing to export');
      expect(h.files.saved, isEmpty);
    });
  });
}
