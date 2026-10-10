// Menu profitability's ledger: the read, the KPIs, the table, its filters,
// its export and the quadrant (REP-FIN-006…028, 042…045, 071).
import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart' show MadarColorsX;
import 'package:fl_chart/fl_chart.dart';
import 'package:dashboard_reports/src/financial/fin_data.dart';
import 'package:dashboard_reports/src/financial/fin_profitability.dart';
import 'package:dashboard_reports/src/financial/fin_quadrant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder get ledgerTable => find.byKey(const ValueKey('fin-ledger'));

Finder inLedger(Finder f) => find.descendant(of: ledgerTable, matching: f);

/// The item cells on this page of the table.
List<MarginLedgerRow> shownRows() => [
  for (final e in inLedger(find.byType(FinItemCell)).evaluate())
    (e.widget as FinItemCell).row,
];

Future<void> pickClass(DashHarness h, String label) async {
  await h.tap(find.byKey(const ValueKey('fin-class-filter')));
  await h.tap(
    find.descendant(
      of: find.byType(DashOptionList<String>),
      matching: find.text(label),
    ),
  );
}

void main() {
  testWidgets('REP-FIN-007 one ledger for the period: the sentinel with All '
      'branches, from/to, no cost basis', (tester) async {
    final h = await pumpFin(tester);
    final c = callsTo(h, ledgerRoute).single;
    expect(c.path, '/insights/branches/$allBranchesId/menu-margin');
    final scope = h.container.read(currentScopeProvider);
    expect(c.query['from'], [
      DateTime.parse(scope.from).toUtc().toIso8601String(),
    ]);
    expect(c.query['to'], [DateTime.parse(scope.to).toUtc().toIso8601String()]);
    expect(c.query.containsKey('cost_basis'), isFalse);
  });

  testWidgets('REP-FIN-007 with a branch picked the ledger is that branch\'s', (
    tester,
  ) async {
    final h = await pumpFin(tester, branchId: SeedIds.zamalek);
    expect(
      callsTo(h, ledgerRoute).single.path,
      '/insights/branches/${SeedIds.zamalek}/menu-margin',
    );
  });

  testWidgets('REP-FIN-006 a platform admin with no org picked sees "Select '
      'an organization" and nothing is asked', (tester) async {
    final h = await pumpFin(tester, persona: Persona.platform);
    expect(pageText(h.t('insights.pickOrg')), findsOneWidget);
    expect(pageText(h.t('insights.profitability.title')), findsWidgets);
    expect(callsTo(h, ledgerRoute), isEmpty);
  });

  testWidgets('REP-FIN-008 the sub-heading\'s subtitle is a skeleton while '
      'loading, then the target trigger', (tester) async {
    final s = finServer();
    final gate = s.server.hold('GET', ledgerRoute);
    final h = await pumpFin(tester, server: s.server, db: s.db);
    expect(find.byKey(const ValueKey('fin-target-trigger')), findsNothing);
    expect(pageText('Menu profitability'), findsNWidgets(2));
    expect(inPage(find.byType(DashSkeleton)), findsWidgets);
    gate.release();
    await h.settle();
    expect(find.byKey(const ValueKey('fin-target-trigger')), findsOneWidget);
    expect(pageText('Org target 68%'), findsOneWidget);
  });

  testWidgets('REP-FIN-009 Today\'s costs adds cost_basis=current and '
      'refetches; Snapshot comes back from the cache', (tester) async {
    final h = await pumpFin(tester);
    final snap = served(h);
    await pickSegment(h, 'fin-basis', "Today's costs");
    final calls = callsTo(h, ledgerRoute);
    expect(calls, hasLength(2));
    expect(calls.last.query['cost_basis'], ['current']);
    final cur = served(h, current: true);
    expect(cur.totals.marginKnown, lessThan(snap.totals.marginKnown));
    final f = h.container.read(formatProvider);
    expect(
      find.descendant(
        of: kpiCard('Gross margin'),
        matching: figure(f.fmtMoney(cur.totals.marginKnown)),
      ),
      findsOneWidget,
    );
    await pickSegment(h, 'fin-basis', 'Snapshot');
    expect(callsTo(h, ledgerRoute), hasLength(2));
  });

  testWidgets('REP-FIN-010 the inner tabs are Ledger, Repricing, Decisions; '
      'Ledger first', (tester) async {
    final h = await pumpFin(tester);
    final labels = [
      for (final e
          in find
              .descendant(
                of: find.byKey(const ValueKey('fin-inner-tabs')),
                matching: find.byType(Text),
              )
              .evaluate())
        (e.widget as Text).data,
    ];
    expect(labels, ['Ledger', 'Repricing', 'Decisions']);
    expect(ledgerTable, findsOneWidget);
    expect(callsTo(h, repricingRoute), isEmpty);
    expect(callsTo(h, decisionsRoute), isEmpty);
  });

  testWidgets('REP-FIN-011/012/013 the KPIs: revenue, gross margin with its '
      'share of revenue, the gap below target in warning', (tester) async {
    final h = await pumpFin(tester);
    final r = served(h);
    final f = h.container.read(formatProvider);
    expect(
      find.descendant(
        of: kpiCard('Revenue'),
        matching: figure(f.fmtMoney(r.totals.revenue)),
      ),
      findsOneWidget,
    );
    final margin = tester.widget<DashStatCard>(kpiCard('Gross margin'));
    expect(margin.value, r.totals.marginKnown);
    expect(margin.tone, DashTone.success);
    expect(
      margin.hint,
      '${f.fmtPercent(r.totals.marginPct! / 100)} of revenue',
    );
    final gap = tester.widget<DashStatCard>(kpiCard('Margin below target'));
    expect(r.totals.belowTargetGap, greaterThan(0));
    expect(gap.value, r.totals.belowTargetGap);
    expect(gap.tone, DashTone.warning);
    // The 30 days before hold no sales: no trend pill.
    expect(tester.widget<DashStatCard>(kpiCard('Revenue')).trend, isNull);
  });

  testWidgets('REP-FIN-011/012 over 7 days the pills compare with the 7 '
      'days before', (tester) async {
    final h = await pumpFin(tester);
    await h.container
        .read(scopeProvider.notifier)
        .setPreset(ScopePreset.last7Days);
    await h.settle();
    final r = served(h);
    expect(r.totals.prevRevenue, greaterThan(0));
    final rev = tester.widget<DashStatCard>(kpiCard('Revenue'));
    expect(
      rev.trend,
      closeTo(
        (r.totals.revenue - r.totals.prevRevenue) / r.totals.prevRevenue,
        1e-9,
      ),
    );
    final m = tester.widget<DashStatCard>(kpiCard('Gross margin'));
    expect(
      m.trend,
      closeTo(
        (r.totals.marginKnown - r.totals.prevMarginKnown) /
            r.totals.prevMarginKnown,
        1e-9,
      ),
    );
  });

  testWidgets('REP-FIN-013 no gap: the card stays neutral', (tester) async {
    final s = finServer();
    ledgerAnswer(s, (j) {
      (j['totals']! as Map)['below_target_gap'] = 0;
      return j;
    });
    await pumpFin(tester, server: s.server, db: s.db);
    expect(
      tester.widget<DashStatCard>(kpiCard('Margin below target')).tone,
      DashTone.neutral,
    );
  });

  testWidgets('REP-FIN-014 the cost-unknown note counts the rows and sits '
      'above every inner tab', (tester) async {
    final h = await pumpFin(tester);
    expect(
      pageText('2 items excluded from margin — cost unknown'),
      findsOneWidget,
    );
    await openInner(h, 'Repricing');
    expect(find.byKey(const ValueKey('fin-cost-unknown')), findsOneWidget);
    await openInner(h, 'Decisions');
    expect(find.byKey(const ValueKey('fin-cost-unknown')), findsOneWidget);
  });

  testWidgets('REP-FIN-014 one row: the singular words', (tester) async {
    final s = finServer();
    ledgerAnswer(s, (j) => j..['rows_cost_unknown'] = 1);
    await pumpFin(tester, server: s.server, db: s.db);
    expect(
      pageText('1 item excluded from margin — cost unknown'),
      findsOneWidget,
    );
  });

  testWidgets('REP-FIN-014 none: no note', (tester) async {
    final s = finServer();
    ledgerAnswer(s, (j) => j..['rows_cost_unknown'] = 0);
    await pumpFin(tester, server: s.server, db: s.db);
    expect(find.byKey(const ValueKey('fin-cost-unknown')), findsNothing);
  });

  testWidgets('REP-FIN-015/016 Table first, with the web\'s columns', (
    tester,
  ) async {
    await pumpFin(tester);
    for (final h in [
      'ITEM',
      'SOLD',
      'REVENUE',
      'COST',
      'MARGIN',
      'MARGIN %',
      'SHARE %',
      'FLAGS',
    ]) {
      expect(inLedger(find.text(h)), findsOneWidget, reason: h);
    }
  });

  testWidgets('REP-FIN-016 cells: money, an em dash for an unknown cost, '
      'the margin % in warning under the target', (tester) async {
    final h = await pumpFin(tester);
    final r = served(h);
    final f = h.container.read(formatProvider);
    final unknown = r.rows.firstWhere(
      (x) => x.cost == null && x.quantitySold > 0,
    );
    final under = r.rows.firstWhere(
      (x) => x.marginPct != null && x.marginPct! < r.targetPct,
    );
    // Show every flagged row: a short list with both in it.
    await h.tap(find.byKey(const ValueKey('fin-flagged-only')));
    final pct = inLedger(figure(f.fmtPercent(under.marginPct! / 100)));
    expect(pct, findsWidgets);
    final c = tester.element(ledgerTable).madarColors;
    expect(
      tester.widget<Text>(pct.first).style!.color,
      DashTone.warning.foreground(c),
    );
    expect(unknown.flags.map((x) => x.kind), contains('recipe_incomplete'));
    expect(inLedger(find.text(unknown.itemName)), findsOneWidget);
    expect(inLedger(figure('—')), findsWidgets);
  });

  testWidgets('REP-FIN-016 a margin under zero is tinted danger', (
    tester,
  ) async {
    final s = finServer();
    ledgerAnswer(s, (j) {
      final row = rowsOf(j).first;
      row['margin'] = -1250;
      return j;
    });
    final h = await pumpFin(tester, server: s.server, db: s.db);
    final f = h.container.read(formatProvider);
    final cell = inLedger(figure(f.fmtMoney(-1250)));
    expect(
      tester.widget<Text>(cell).style!.color,
      DashTone.danger.foreground(tester.element(ledgerTable).madarColors),
    );
  });

  testWidgets('REP-FIN-017 the item: its size as stored unless one_size, '
      'the class chip, "Off menu"', (tester) async {
    final s = finServer();
    ledgerAnswer(s, (j) {
      final rows = rowsOf(j);
      rows.first['on_menu'] = false;
      return j;
    });
    final h = await pumpFin(tester, server: s.server, db: s.db);
    final r = served(h);
    final first = r.rows.first;
    final row = find
        .ancestor(
          of: inLedger(find.text(first.itemName)).first,
          matching: find.byType(Wrap),
        )
        .first;
    if (first.sizeLabel != 'one_size') {
      expect(
        find.descendant(of: row, matching: find.text(first.sizeLabel)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: row,
        matching: find.text(h.t('insights.class.${first.class_}')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Off menu')),
      findsOneWidget,
    );
    expect(inLedger(find.text('one_size')), findsNothing);
  });

  testWidgets('REP-FIN-017 the class chips are quiet pills; only Dog\'s '
      'words are muted', (tester) async {
    final h = await pumpFin(tester);
    final c = tester.element(ledgerTable).madarColors;
    for (final (klass, label, color) in [
      ('star', 'Star', c.textPrimary),
      ('dog', 'Dog', c.textSecondary),
    ]) {
      await pickClass(h, label);
      final r = shownRows().first;
      expect(r.class_, klass);
      final chip = find.byKey(ValueKey('class-${r.menuItemId}-${r.sizeLabel}'));
      final text = tester.widget<Text>(
        find.descendant(of: chip, matching: find.text(label)),
      );
      expect(text.style!.color, color, reason: klass);
      final pill = tester.widget<Container>(
        find.descendant(of: chip, matching: find.byType(Container)).first,
      );
      expect((pill.decoration! as BoxDecoration).color, c.surfaceAlt);
    }
  });

  testWidgets('REP-FIN-018 the class chip is focusable and explains itself', (
    tester,
  ) async {
    final h = await pumpFin(tester);
    final first = served(h).rows.first;
    final chip = tester.widget<DashPressable>(
      find.byKey(ValueKey('class-${first.menuItemId}-${first.sizeLabel}')),
    );
    final pop = first.popularityPct!;
    final shown = pop == pop.roundToDouble() ? '${pop.toInt()}' : '$pop';
    expect(
      chip.tooltip,
      'Popularity $shown% of units · profit vs menu average',
    );
    expect(chip.onTap, isNull);
  });

  testWidgets('REP-FIN-019 sold: the change vs the previous period, up in '
      'success, down in danger, hidden at zero', (tester) async {
    final s = finServer();
    ledgerAnswer(s, (j) {
      final rows = rowsOf(j);
      rows[0]['prev_quantity'] = (rows[0]['quantity_sold']! as int) + 5;
      rows[1]['prev_quantity'] = rows[1]['quantity_sold'];
      rows[2]['prev_quantity'] = (rows[2]['quantity_sold']! as int) - 3;
      return j;
    });
    final h = await pumpFin(tester, server: s.server, db: s.db);
    final rows = served(h).rows;
    Finder delta(MarginLedgerRow r) =>
        find.byKey(ValueKey('sold-delta-${r.menuItemId}-${r.sizeLabel}'));
    final c = tester.element(ledgerTable).madarColors;
    expect(
      find.descendant(of: delta(rows[0]), matching: figure('5')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DashIcon>(
            find.descendant(
              of: delta(rows[0]),
              matching: find.byType(DashIcon),
            ),
          )
          .color,
      DashTone.danger.foreground(c),
    );
    expect(delta(rows[1]), findsNothing);
    expect(
      find.descendant(of: delta(rows[2]), matching: figure('3')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(of: delta(rows[2]), matching: find.byType(Tooltip)),
          )
          .message,
      'vs previous period',
    );
  });

  testWidgets('REP-FIN-020 the class filter: All classes, Star, Workhorse, '
      'Challenge, Dog', (tester) async {
    final h = await pumpFin(tester);
    await h.tap(find.byKey(const ValueKey('fin-class-filter')));
    final options = [
      for (final e
          in find
              .descendant(
                of: find.byType(DashOptionList<String>),
                matching: find.byType(Text),
              )
              .evaluate())
        (e.widget as Text).data,
    ];
    expect(options, ['All classes', 'Star', 'Workhorse', 'Challenge', 'Dog']);
    await h.tap(
      find.descendant(
        of: find.byType(DashOptionList<String>),
        matching: find.text('Dog'),
      ),
    );
    final dogs = served(h).rows.where((r) => r.class_ == 'dog').toList();
    expect(dogs, isNotEmpty);
    expect(shownRows().map((r) => r.class_).toSet(), {'dog'});
    expect(shownRows(), hasLength(dogs.length));
  });

  testWidgets('REP-FIN-021/022 Flagged only keeps flagged rows; with a class '
      'both apply', (tester) async {
    final h = await pumpFin(tester);
    final all = served(h).rows;
    await h.tap(find.byKey(const ValueKey('fin-flagged-only')));
    final flagged = all.where((r) => r.flags.isNotEmpty).toList();
    expect(shownRows(), hasLength(flagged.length));
    expect(shownRows().every((r) => r.flags.isNotEmpty), isTrue);
    await pickClass(h, 'Star');
    final both = finFilterRows(all, klass: 'star', flaggedOnly: true);
    expect(shownRows().map((r) => r.itemName), [
      for (final r in both) r.itemName,
    ]);
  });

  testWidgets('REP-FIN-023 50 rows a page, no Columns menu', (tester) async {
    final h = await pumpFin(tester);
    final n = served(h).rows.length;
    expect(n, greaterThan(50));
    expect(shownRows(), hasLength(50));
    expect(inLedger(find.text('Page 1 of ${(n / 50).ceil()}')), findsOneWidget);
    expect(inLedger(find.text('Columns')), findsNothing);
  });

  testWidgets('REP-FIN-024 empty: "Nothing flagged" with Flagged only, else '
      '"No sales in this period"', (tester) async {
    final s = finServer();
    ledgerAnswer(s, (j) {
      for (final r in rowsOf(j)) {
        r['flags'] = <Object?>[];
      }
      return j;
    });
    final h = await pumpFin(tester, server: s.server, db: s.db);
    await h.tap(find.byKey(const ValueKey('fin-flagged-only')));
    expect(
      inLedger(find.text('Nothing flagged — margins look healthy')),
      findsOneWidget,
    );
  });

  testWidgets('REP-FIN-024 no rows: "No sales in this period"', (tester) async {
    final s = finServer();
    ledgerAnswer(s, (j) => j..['rows'] = <Object?>[]);
    await pumpFin(tester, server: s.server, db: s.db);
    expect(inLedger(find.text('No sales in this period')), findsOneWidget);
  });

  testWidgets(
    'REP-FIN-025 loading shows skeleton rows, never the empty words',
    (tester) async {
      final s = finServer();
      final gate = s.server.hold('GET', ledgerRoute);
      final h = await pumpFin(tester, server: s.server, db: s.db);
      expect(inLedger(find.byType(DashSkeleton)), findsWidgets);
      expect(inLedger(find.text('No sales in this period')), findsNothing);
      gate.release();
      await h.settle();
      expect(shownRows(), isNotEmpty);
    },
  );

  testWidgets('REP-FIN-025 a failed read shows the server\'s words and Retry '
      'reads the ledger again', (tester) async {
    final s = finServer();
    final boom = MockResponse.error(500, 'The ledger is unavailable.');
    s.server.fail('GET', ledgerRoute, boom);
    final h = await pumpFin(tester, server: s.server, db: s.db);
    expect(inLedger(find.text(h.refusalWords(boom))), findsOneWidget);
    expect(inLedger(find.text('No sales in this period')), findsNothing);
    await h.tap(inLedger(find.text('Retry')));
    expect(callsTo(h, ledgerRoute), hasLength(2));
    expect(shownRows(), isNotEmpty);
  });

  testWidgets('REP-ALL-018 a failed refetch replaces the ledger rows with '
      'the error', (tester) async {
    final s = finServer();
    final h = await pumpFin(tester, server: s.server, db: s.db);
    expect(shownRows(), isNotEmpty);
    s.server.fail('GET', ledgerRoute, MockResponse.error(500, 'Down'));
    invalidateInsights(h.container.read(realtimeBusProvider));
    await h.settle();
    expect(inLedger(find.text('Retry')), findsOneWidget);
    expect(shownRows(), isEmpty);
  });

  group('export', () {
    Finder exportButton() => find.byKey(const ValueKey('fin-ledger-export'));
    Future<void> menu(DashHarness h, String item) async {
      await h.tap(exportButton());
      await h.tap(find.text(item).last);
    }

    String stamp(DashHarness h) =>
        isoString(h.container.read(clockProvider)()).substring(0, 10);

    testWidgets('REP-FIN-026 Excel: the filtered rows on one sheet "Menu '
        'profitability", the web\'s columns, Madar-<title>-<date>.xlsx', (
      tester,
    ) async {
      final h = await pumpFin(tester);
      await h.tap(find.byKey(const ValueKey('fin-flagged-only')));
      final rows = finFilterRows(served(h).rows, flaggedOnly: true);
      await menu(h, 'Export Excel');
      await h.expectToast('Exported ${rows.length} rows');
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.name, 'Menu profitability');
      expect(sheet.title, 'Menu profitability');
      expect(
        [for (final c in sheet.columns) c.header],
        [
          'Item',
          'Size',
          'All classes',
          'Sold',
          'Revenue',
          'Cost',
          'Margin',
          'Margin %',
          'Flags',
        ],
      );
      expect([for (final c in sheet.columns) c.width].take(3), [28, 10, 12]);
      expect(sheet.rows, hasLength(rows.length));
      final first = rows.first;
      expect(sheet.rows.first[0], first.itemName);
      expect(sheet.rows.first[1], first.sizeLabel);
      expect(sheet.rows.first[2], h.t('insights.class.${first.class_}'));
      expect(sheet.rows.first[7], (first.marginPct! * 10).round() / 10);
      expect(sheet.rows.first[8], first.flags.map((f) => f.kind).join(', '));
      expect(
        h.files.saved.single.filename,
        'Madar-Menu profitability-${stamp(h)}.xlsx',
      );
    });

    testWidgets('REP-FIN-027 CSV: the same rows as .csv', (tester) async {
      final h = await pumpFin(tester);
      await pickClass(h, 'Dog');
      final rows = finFilterRows(served(h).rows, klass: 'dog');
      await menu(h, 'Export CSV');
      await h.expectToast('Exported ${rows.length} rows');
      final f = h.files.saved.single;
      expect(f.filename, 'Madar-Menu profitability-${stamp(h)}.csv');
      final text = String.fromCharCodes(f.bytes);
      expect(text.split('\n').first, startsWith('Item,Size,All classes,Sold'));
    });

    testWidgets('REP-FIN-026 in Arabic the file name is Arabic', (
      tester,
    ) async {
      final h = await pumpFin(tester, locale: 'ar');
      await menu(h, h.t('common.exportExcel'));
      await h.flushTimers();
      expect(
        h.files.saved.single.filename,
        'Madar-${h.t('insights.profitability.title')}-${stamp(h)}.xlsx',
      );
    });

    testWidgets('REP-FIN-028 nothing shown: the export is disabled', (
      tester,
    ) async {
      final s = finServer();
      ledgerAnswer(s, (j) {
        for (final r in rowsOf(j)) {
          r['flags'] = <Object?>[];
        }
        return j;
      });
      final h = await pumpFin(tester, server: s.server, db: s.db);
      expect(tester.widget<DashExportButton>(exportButton()).enabled, isTrue);
      await h.tap(find.byKey(const ValueKey('fin-flagged-only')));
      expect(tester.widget<DashExportButton>(exportButton()).enabled, isFalse);
    });
  });

  group('quadrant', () {
    Future<void> quadrant(DashHarness h) =>
        pickSegment(h, 'fin-view', 'Quadrant');

    testWidgets('REP-FIN-015/043 Quadrant: the chart card, its description, '
        'the corner captions and the four-class legend', (tester) async {
      final h = await pumpFin(tester);
      await quadrant(h);
      final m = FinQuadrant(served(h).rows);
      final f = h.container.read(formatProvider);
      expect(pageText('Popularity against margin per unit'), findsOneWidget);
      expect(
        pageText(
          'Dashed lines split high from low: '
          '${f.fmtPercent(m.popularityThresholdPct / 100)} of units sold, and '
          'the average margin per unit of '
          '${f.fmtMoney(m.unitMarginThreshold.round())}.',
        ),
        findsOneWidget,
      );
      expect(pageText('Challenges / Dogs'), findsOneWidget);
      expect(pageText('Stars / Workhorses'), findsOneWidget);
      for (final c in ['Star', 'Workhorse', 'Challenge', 'Dog']) {
        expect(
          find.descendant(
            of: find.byType(FinQuadrantView),
            matching: find.text(c),
          ),
          findsOneWidget,
        );
      }
      expect(ledgerTable, findsNothing);
    });

    testWidgets('REP-FIN-043 each class keeps its own colour AND shape', (
      tester,
    ) async {
      final h = await pumpFin(tester);
      await quadrant(h);
      final c = tester.element(find.byType(FinQuadrantView)).madarColors;
      expect(finClassMark(c, 'star'), (c.success, FinShape.star));
      expect(finClassMark(c, 'workhorse'), (c.info, FinShape.square));
      expect(finClassMark(c, 'challenge'), (c.warning, FinShape.triangle));
      expect(finClassMark(c, 'dog'), (c.danger, FinShape.circle));
    });

    testWidgets('REP-FIN-022/043/071 the quadrant plots the WHOLE ledger; the '
        'filters and Export hide and come back as they were', (tester) async {
      final h = await pumpFin(tester);
      await pickClass(h, 'Dog');
      await h.tap(find.byKey(const ValueKey('fin-flagged-only')));
      await quadrant(h);
      expect(
        tester.widget<FinQuadrantView>(find.byType(FinQuadrantView)).rows,
        hasLength(served(h).rows.length),
      );
      expect(find.byKey(const ValueKey('fin-class-filter')), findsNothing);
      expect(find.byKey(const ValueKey('fin-flagged-only')), findsNothing);
      expect(find.byKey(const ValueKey('fin-ledger-export')), findsNothing);
      await pickSegment(h, 'fin-view', 'Table');
      expect(
        tester
            .widget<DashSwitch>(find.byKey(const ValueKey('fin-flagged-only')))
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<DashSelect<String>>(
              find.byKey(const ValueKey('fin-class-filter')),
            )
            .value,
        'dog',
      );
    });

    testWidgets('REP-FIN-071 leaving Menu profitability resets basis, view, '
        'filters and the inner tab', (tester) async {
      final h = await pumpFin(tester);
      await pickSegment(h, 'fin-basis', "Today's costs");
      await pickClass(h, 'Star');
      await quadrant(h);
      await openTab(h, 'Revenue');
      await openTab(h, 'Menu profitability');
      expect(
        tester
            .widget<DashSegmentedControl<bool>>(
              find.byKey(const ValueKey('fin-basis')),
            )
            .value,
        isFalse,
      );
      expect(ledgerTable, findsOneWidget);
      expect(
        tester
            .widget<DashSelect<String>>(
              find.byKey(const ValueKey('fin-class-filter')),
            )
            .value,
        '',
      );
      await openInner(h, 'Decisions');
      await openTab(h, 'Revenue');
      await openTab(h, 'Menu profitability');
      expect(ledgerTable, findsOneWidget);
    });

    testWidgets('REP-FIN-042 loading: a 420 px skeleton, never "no sales"', (
      tester,
    ) async {
      final s = finServer();
      final gate = s.server.hold('GET', ledgerRoute);
      final h = await pumpFin(tester, server: s.server, db: s.db);
      await quadrant(h);
      expect(
        inPage(
          find.byWidgetPredicate(
            (w) => w is DashSkeleton && w.height == finQuadrantHeight,
          ),
        ),
        findsOneWidget,
      );
      expect(pageText('No sales in this period'), findsNothing);
      gate.release();
      await h.settle();
      expect(find.byType(FinQuadrantView), findsOneWidget);
    });

    testWidgets('REP-FIN-042 a failed read: the server\'s words and Retry', (
      tester,
    ) async {
      final s = finServer();
      final boom = MockResponse.error(500, 'The ledger is unavailable.');
      s.server.fail('GET', ledgerRoute, boom);
      final h = await pumpFin(tester, server: s.server, db: s.db);
      await quadrant(h);
      expect(pageText(h.refusalWords(boom)), findsOneWidget);
      await h.tap(inPage(find.text('Retry')));
      expect(find.byType(FinQuadrantView), findsOneWidget);
    });

    testWidgets('REP-FIN-042 sold but nothing costed: "Nothing to plot yet"', (
      tester,
    ) async {
      final s = finServer();
      ledgerAnswer(s, (j) {
        for (final r in rowsOf(j)) {
          r['class'] = null;
        }
        return j;
      });
      final h = await pumpFin(tester, server: s.server, db: s.db);
      await quadrant(h);
      expect(
        pageText('Nothing to plot yet — no item that sold has a known cost'),
        findsOneWidget,
      );
    });

    testWidgets('REP-FIN-042 nothing sold: "No sales in this period"', (
      tester,
    ) async {
      final s = finServer();
      ledgerAnswer(s, (j) => j..['rows'] = <Object?>[]);
      final h = await pumpFin(tester, server: s.server, db: s.db);
      await quadrant(h);
      expect(pageText('No sales in this period'), findsOneWidget);
    });

    testWidgets('REP-FIN-045 the plot is an image with its verdict; in '
        'Arabic it stays left to right', (tester) async {
      final h = await pumpFin(tester, locale: 'ar');
      await pickSegment(
        h,
        'fin-view',
        h.t('insights.profitability.viewQuadrant'),
      );
      final m = FinQuadrant(served(h).rows);
      final f = h.container.read(formatProvider);
      final summary = h.t(
        'insights.quadrant.summary',
        count: m.plotted,
        args: {
          'stars': f.fmtNumber(m.count('star')),
          'workhorses': f.fmtNumber(m.count('workhorse')),
          'challenges': f.fmtNumber(m.count('challenge')),
          'dogs': f.fmtNumber(m.count('dog')),
        },
      );
      final plot = find.byKey(const ValueKey('fin-quadrant-plot'));
      expect(
        tester.getSemantics(plot),
        matchesSemantics(label: summary, isImage: true),
      );
      expect(Directionality.of(tester.element(plot)), TextDirection.ltr);
      expect(
        Directionality.of(
          tester.element(find.text(h.t('insights.quadrant.challengesDogs'))),
        ),
        TextDirection.ltr,
      );
    });

    testWidgets('a tapped mark keeps its tooltip after the finger lifts; a '
        'tap on empty plot clears it', (tester) async {
      final h = await pumpFin(tester);
      await quadrant(h);
      final chart = find.byType(ScatterChart);
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      ScatterChartData data() => tester.widget<ScatterChart>(chart).data;
      final d = data();
      // The plot, past the 64 wide money axis and above the 28 tall one.
      final r = tester.getRect(chart);
      final plot = Rect.fromLTRB(r.left + 64, r.top, r.right, r.bottom - 28);
      Offset at(double x, double y) => Offset(
        plot.left + (x - d.minX) / (d.maxX - d.minX) * plot.width,
        plot.top + (d.maxY - y) / (d.maxY - d.minY) * plot.height,
      );
      // The topmost mark answers first.
      final i = d.scatterSpots.length - 1;
      final mark = d.scatterSpots[i];
      await tester.tapAt(at(mark.x, mark.y));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(data().showingTooltipIndicators, [i]);
      final tip = data().scatterTouchData.touchTooltipData.getTooltipItems(
        mark,
      )!;
      expect(tip.text, isNotEmpty);

      // A point of the plot well away from every mark.
      final empty =
          [
            for (var fx = 0.05; fx < 1; fx += 0.1)
              for (var fy = 0.05; fy < 1; fy += 0.1)
                Offset(
                  plot.left + plot.width * fx,
                  plot.top + plot.height * fy,
                ),
          ].firstWhere(
            (o) =>
                d.scatterSpots.every((s) => (at(s.x, s.y) - o).distance > 40),
          );
      await tester.tapAt(empty);
      await tester.pumpAndSettle();
      expect(data().showingTooltipIndicators, isEmpty);
    });
  });
}
