// Operations › Tables (REP-OPS-006…033, 065, 067, 069) and the table kit's
// area-wide rules as this tab uses them (REP-ALL-009, 015…019, 021, 031).
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart'
    show ApiRequest, Dir, MetricsQueryRequest;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/mock/operations_mock.dart';
import 'package:design_system/design_system.dart' show MadarClippedText;
import 'package:dashboard_reports/src/operations/ops_charts.dart';
import 'package:dashboard_reports/src/operations/ops_support.dart';
import 'package:dashboard_reports/src/operations/ops_table_sheet.dart';
import 'package:dashboard_reports/src/operations/ops_tables.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The `tables` dataset's figures for [branchIds] over the page's period.
Map<String, Object?> _summary(DashHarness h, List<String> branchIds) {
  final s = h.container.read(currentScopeProvider);
  return opsTableMeasures(
    opsTableFacts(
      h.db!,
      branchIds: branchIds,
      from: DateTime.parse(s.from),
      to: DateTime.parse(s.to),
    ),
  );
}

num _kpi(WidgetTester tester, String key) => tester
    .widget<DashStatValue>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(DashStatValue),
      ),
    )
    .value;

Finder get _table => inPage(find.byKey(const ValueKey('ops-tables-table')));
Finder get _byTable => inPage(find.byKey(const ValueKey('ops-revenue-by-table')));
Finder get _busiest => inPage(find.byKey(const ValueKey('ops-busiest-hours')));
Finder get _section =>
    inPage(find.byKey(const ValueKey('ops-section-filter')));
Finder get _sheet => find.byType(OpsTableSheet);

List<OpsTableRow> _rows(WidgetTester tester) =>
    tester.widget<DashDataTable<OpsTableRow>>(_table).rows;

Finder get _names =>
    find.descendant(of: _table, matching: find.byKey(opsTableNameKey));

/// The ledger's table cells shown on the current page (first column).
List<String> _shownTables(WidgetTester tester) => [
  for (final e in _names.evaluate())
    (e.widget as MadarClippedText).data ?? '',
];

Future<void> _openRow(DashHarness h, String label) async {
  await h.tap(
    find.descendant(of: _names, matching: find.text(label)).first,
  );
}

void main() {
  setUpAll(ensureTimeZones);

  group('REP-OPS-006 the request', () {
    testWidgets('one POST with the three widgets, the period and the '
        'language; the branch rides the header, not the body', (tester) async {
      final h = await pumpOps(tester);
      final calls = h.server.callsTo(metricsRoute, method: 'POST');
      expect(calls, hasLength(1));
      final scope = h.container.read(currentScopeProvider);
      final body = MetricsQueryRequest.fromJson(
        (jsonDecode(jsonEncode(calls.single.body)) as Map)
            .cast<String, Object?>(),
      );
      expect(body.locale, 'en');
      expect(body.period?.from, scope.from);
      expect(body.period?.to, scope.to);
      expect(body.period?.preset, isNull);
      final widgets = {for (final w in body.widgets) w.key: w.spec};
      expect(widgets.keys, ['summary', 'byTable', 'byHour']);
      expect(widgets['summary']!.measures, [
        'turns',
        'turns_per_day',
        'covers',
        'table_revenue',
        'revenue_per_cover',
        'avg_dwell_minutes',
        'active_tables',
        'revenue_per_table',
      ]);
      expect(widgets['summary']!.dimensions, anyOf(isNull, isEmpty));
      // All branches: branch + table.
      expect(widgets['byTable']!.dimensions, ['branch', 'table']);
      expect(widgets['byTable']!.sort?.measure, 'turns');
      expect(widgets['byTable']!.sort?.dir, Dir.desc);
      expect(widgets['byTable']!.limit, 500);
      expect(widgets['byHour']!.dimensions, ['hour']);
      expect(widgets['byHour']!.measures, ['turns', 'covers']);
      expect(widgets['byHour']!.limit, 24);
      final raw = calls.single.body! as Map;
      expect(raw.containsKey('branch_id'), isFalse);
      expect(
        calls.single.headers['X-Branch-Id'],
        anyOf(isNull, allBranchesId),
      );
    });

    testWidgets('a branch picked: section + table, the branch in the header',
        (tester) async {
      final h = await pumpOps(tester, branchId: SeedIds.maadi);
      final call = h.server.callsTo(metricsRoute, method: 'POST').single;
      expect(call.headers['X-Branch-Id'], SeedIds.maadi);
      final widgets = (call.body! as Map)['widgets'] as List;
      final byTable = widgets.firstWhere((w) => w['key'] == 'byTable') as Map;
      expect((byTable['spec'] as Map)['dimensions'], ['section', 'table']);
    });

    testWidgets('a language change asks again in Arabic', (tester) async {
      final h = await pumpOps(tester);
      await h.container.read(localeProvider.notifier).set('ar');
      await h.settle();
      final calls = h.server.callsTo(metricsRoute, method: 'POST');
      expect(calls, hasLength(2));
      expect((calls.last.body! as Map)['locale'], 'ar');
      await h.container.read(localeProvider.notifier).set('en');
      await h.settle();
      // Back to a key still cached: nothing asked.
      expect(h.server.callsTo(metricsRoute, method: 'POST'), hasLength(2));
    });

    testWidgets('a widget that failed inside the 200 shows the error, not '
        'the figures (REP-OPS-009)', (tester) async {
      final s = opsServer();
      s.server.on('POST', metricsRoute, (req) {
        return MockResponse.ok({
          'scope': {'all_branches': true, 'branches': [], 'label': 'x'},
          'timezone': 'Africa/Cairo',
          'results': {
            'summary': {'status': 'error', 'error': 'boom'},
            'byTable': {'status': 'error', 'error': 'boom'},
            'byHour': {'status': 'error', 'error': 'boom'},
          },
        });
      });
      final h = await pumpOps(tester, server: s.server, db: s.db);
      expect(pageText(h.t('tablesInsights.loadFailed')), findsOneWidget);
      expect(inPage(find.byType(DashLedgerStrip)), findsNothing);
    });
  });

  testWidgets('REP-OPS-007 / REP-ALL-021 the nested page: a "Tables" '
      'sub-heading with the period under it', (tester) async {
    await pumpOps(tester);
    final heading = inPage(find.byType(DashEmbeddedPages));
    expect(heading, findsOneWidget);
    expect(
      find.descendant(of: heading, matching: find.text('Tables')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: heading, matching: find.text('Last 30 days')),
      findsOneWidget,
    );
  });

  testWidgets('REP-OPS-008 loading: KPI skeletons, both charts\' skeletons, '
      'skeleton rows', (tester) async {
    final s = opsServer();
    final gate = s.server.hold('POST', metricsRoute);
    final h = await pumpOps(tester, server: s.server, db: s.db);
    for (final card in tester.widgetList<DashStatCard>(
      inPage(find.byType(DashStatCard)),
    )) {
      expect(card.loading, isTrue, reason: card.label);
    }
    for (final title in ['Busiest hours', 'Revenue by table']) {
      expect(
        find.descendant(
          of: chartCard(title),
          matching: find.byType(DashSkeleton),
        ),
        findsOneWidget,
      );
    }
    expect(tester.widget<DashDataTable<OpsTableRow>>(_table).loading, isTrue);
    await h.shot('operations/tables-loading');
    gate.release();
    await h.settle();
    expect(_busiest, findsOneWidget);
  });

  testWidgets('REP-OPS-009 a failed read: only the error and Retry; Retry '
      'asks again and the page fills', (tester) async {
    final s = opsServer();
    s.server.fail(
      'POST',
      metricsRoute,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h = await pumpOps(tester, server: s.server, db: s.db);
    expect(pageText("Couldn't load table insights"), findsOneWidget);
    expect(inPage(find.byType(DashLedgerStrip)), findsNothing);
    expect(inPage(find.byType(DashChartCard)), findsNothing);
    expect(_table, findsNothing);
    await h.shot('operations/tables-failed');
    s.server.clearFailures();
    final gate = s.server.hold('POST', metricsRoute);
    await h.tap(
      find.descendant(
        of: inPage(find.byType(DashErrorState)),
        matching: find.text('Retry'),
      ),
    );
    // Retrying: the button spins.
    expect(
      tester
          .widget<DashErrorState>(inPage(find.byType(DashErrorState)))
          .retrying,
      isTrue,
    );
    gate.release();
    await h.settle();
    expect(h.server.callsTo(metricsRoute, method: 'POST'), hasLength(2));
    expect(_table, findsOneWidget);
  });

  testWidgets('REP-OPS-010…015 / 069 the six KPIs: figures, hints, icons',
      (tester) async {
    final h = await pumpOps(tester);
    final m = _summary(h, SeedIds.sabahBranches);
    expect(m['turns'], greaterThan(0));
    expect(_kpi(tester, 'turns'), m['turns']);
    expect(_kpi(tester, 'covers'), m['covers']);
    expect(_kpi(tester, 'revenue'), m['table_revenue']);
    expect(_kpi(tester, 'per_table'), m['revenue_per_table']);
    expect(_kpi(tester, 'per_cover'), m['revenue_per_cover']);
    final f = h.container.read(formatProvider);
    // REP-OPS-010: at most 2 decimals.
    expect(
      pageText(
        '${fmtNum(f, m['turns_per_day']! as num, maxDp: 2)} per table a day',
      ),
      findsOneWidget,
    );
    // REP-OPS-013.
    expect(pageText('${m['active_tables']} tables used'), findsOneWidget);
    // REP-OPS-015: Average stay is ready text.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dwell')),
        matching: find.text(fmtDwell(m['avg_dwell_minutes']! as num)),
      ),
      findsOneWidget,
    );
    // REP-OPS-069: the icons, in order; no tint.
    final cards = tester.widgetList<DashStatCard>(
      inPage(find.byType(DashStatCard)),
    );
    expect([for (final c in cards) c.icon], [
      'rotate-ccw',
      'users',
      'coins',
      'armchair',
      'user-round',
      'clock',
    ]);
    expect([for (final c in cards) c.label], [
      'Turns',
      'Covers',
      'Table revenue',
      'Revenue per table',
      'Revenue per cover',
      'Average stay',
    ]);
    expect(cards.every((c) => c.tone == DashTone.neutral), isTrue);
    expect(cards.every((c) => c.dense), isTrue);
  });

  test('REP-OPS-015 fmtDwell: "—" under a minute, "42m", "1h", "1h 05m"', () {
    expect(fmtDwell(0), '—');
    expect(fmtDwell(0.4), '—');
    expect(fmtDwell(0.5), '1m');
    expect(fmtDwell(42), '42m');
    expect(fmtDwell(60), '1h');
    expect(fmtDwell(65), '1h 05m');
    expect(fmtDwell(125.6), '2h 06m');
  });

  test('REP-OPS-017 / 018 / 049 Recharts\' tick step: the rough step '
      'rounded up to 0.05 × 10ⁿ', () {
    expect(opsNiceStep(272, integer: true), 70);
    expect(opsNiceStep(84, integer: true), 25);
    expect(opsNiceStep(3, integer: true), 1);
    expect(opsNiceStep(2489300), 650000);
    expect(opsNiceStep(31896800), 8000000);
    expect(opsNiceStep(400), 100);
    expect(opsNiceStep(27), 7);
    expect(opsNiceStep(0), 1);
  });

  test('REP-OPS-016 sections sort as localeCompare does', () {
    OpsTableRow row(String section) => OpsTableRow.fromWire({
      'section': section,
      'table': 'T1',
    });
    expect(
      opsSectionsOf([
        row('terrace'),
        row('Main hall'),
        row('Garden'),
        row('main hall'),
      ]),
      ['Garden', 'main hall', 'Main hall', 'terrace'],
    );
  });

  testWidgets('REP-OPS-017 / 018 the axes step like Recharts: Busiest hours '
      '0…280 by 70, Revenue by table by EGP 6.5K', (tester) async {
    final h = await pumpOps(tester);
    final busiest = tester.widget<OpsBarChart>(_busiest);
    final top = busiest.values.fold<double>(0, (a, b) => a > b ? a : b);
    expect(top, greaterThan(260));
    expect(opsNiceStep(top, integer: true), 70);
    final rows = _rows(tester);
    final biggest = rows
        .map((r) => r.tableRevenue.toDouble())
        .fold<double>(0, (a, b) => a > b ? a : b);
    final f = h.container.read(formatProvider);
    expect(f.fmtMoneyCompact(opsNiceStep(biggest)), f.fmtMoneyCompact(650000));
  });

  testWidgets('REP-OPS-025 a branch picked: the floor is read with the page, '
      'so a row opens straight onto its history', (tester) async {
    final s = opsServer();
    final h = await pumpOps(
      tester,
      server: s.server,
      db: s.db,
      branchId: SeedIds.heliopolis,
    );
    expect(h.server.callsTo(floorRoute), hasLength(1));
    final gate = s.server.hold('GET', historyRoute);
    await _openRow(h, 'T1');
    // Only the history's two skeletons: the lookup is already in.
    expect(
      find.descendant(of: _sheet, matching: find.byType(DashSkeleton)),
      findsNWidgets(2),
    );
    expect(h.server.callsTo(floorRoute), hasLength(1));
    gate.release();
    await h.settle();
  });

  testWidgets('REP-OPS-013 one table used: the singular', (tester) async {
    final s = opsServer();
    s.server.on('POST', metricsRoute, (req) {
      return MockResponse.ok({
        'scope': {'all_branches': true, 'branches': [], 'label': 'x'},
        'timezone': 'Africa/Cairo',
        'results': {
          for (final k in ['summary', 'byTable', 'byHour'])
            k: {
              'status': 'ok',
              'columns': [],
              'grain': 'scalar',
              'period': {},
              'row_count': 1,
              'rows': [
                if (k == 'summary')
                  {'turns': 3, 'active_tables': 1, 'turns_per_day': 1.5},
              ],
              'truncated': false,
              'viz': 'kpi',
            },
        },
      });
    });
    final h = await pumpOps(tester, server: s.server, db: s.db);
    expect(pageText('1 table used'), findsOneWidget);
    expect(pageText('1.5 per table a day'), findsOneWidget);
    // No rows: the charts and the table say so (REP-OPS-017, 018, 022).
    expect(pageText(h.t('tablesInsights.empty')), findsNWidgets(3));
  });

  group('REP-OPS-016 / 067 the section filter', () {
    testWidgets('hidden with All branches (rows carry no section)', (
      tester,
    ) async {
      await pumpOps(tester);
      expect(_section, findsNothing);
    });

    testWidgets('a branch picked: "All sections" + the sections A–Z; it '
        'narrows the table and Revenue by table only', (tester) async {
      final h = await pumpOps(tester, branchId: SeedIds.heliopolis);
      expect(_section, findsOneWidget);
      final select = tester.widget<DashSelect<String>>(_section);
      expect([for (final o in select.options) o.label], [
        'All sections',
        'Main hall',
        'Terrace',
      ]);
      expect(select.semanticLabel, 'Section');
      final all = _rows(tester);
      final kpiTurns = _kpi(tester, 'turns');
      final hours = tester.widget<OpsBarChart>(_busiest).values;
      await pickOption(h, _section, 'Terrace');
      final narrowed = _rows(tester);
      expect(narrowed, isNotEmpty);
      expect(narrowed.length, lessThan(all.length));
      expect(narrowed.every((r) => r.section == 'Terrace'), isTrue);
      final chart = tester.widget<OpsBarChart>(_byTable);
      expect(chart.labels.toSet(), {for (final r in narrowed) r.table});
      // KPIs and Busiest hours stay whole.
      expect(_kpi(tester, 'turns'), kpiTurns);
      expect(tester.widget<OpsBarChart>(_busiest).values, hours);
      await h.shot('operations/tables-section');
    });

    testWidgets('(divergence) a branch change whose rows lack the chosen '
        'section falls back to All sections, never an empty ledger with '
        'no control', (tester) async {
      final h = await pumpOps(tester, branchId: SeedIds.heliopolis);
      await pickOption(h, _section, 'Terrace');
      await h.container.read(scopeProvider.notifier).setBranch(null);
      await h.settle();
      expect(_section, findsNothing);
      expect(_rows(tester), isNotEmpty);
      expect(pageText(h.t('tablesInsights.empty')), findsNothing);
      // A branch that has the section keeps it.
      await h.container
          .read(scopeProvider.notifier)
          .setBranch(SeedIds.heliopolis);
      await h.settle();
      expect(
        tester.widget<DashSelect<String>>(_section).value,
        'Terrace',
      );
    });
  });

  testWidgets('REP-OPS-017 Busiest hours: first to last hour with data, gaps '
      'zero, 12-hour labels, whole-number axis; translated tooltip '
      '(divergence REP-ALL-024)', (tester) async {
    final h = await pumpOps(tester);
    final chart = tester.widget<OpsBarChart>(_busiest);
    final s = h.container.read(currentScopeProvider);
    final facts = opsTableFacts(
      h.db!,
      branchIds: SeedIds.sabahBranches,
      from: DateTime.parse(s.from),
      to: DateTime.parse(s.to),
    );
    final hours = {for (final f in facts) f.hour}.toList()..sort();
    final first = int.parse(hours.first.substring(0, 2));
    final last = int.parse(hours.last.substring(0, 2));
    expect(chart.labels, hasLength(last - first + 1));
    final f = h.container.read(formatProvider);
    expect(chart.labels.first, f.fmtWireTime(hours.first));
    expect(chart.labels.first, matches(RegExp(r'^\d\d:00 (AM|PM)$')));
    for (var i = 0; i < chart.labels.length; i++) {
      final key = '${(first + i).toString().padLeft(2, '0')}:00';
      expect(
        chart.values[i],
        facts.where((x) => x.hour == key).length,
        reason: key,
      );
    }
    expect(chart.integerAxis, isTrue);
    expect(chart.tooltip(0), 'Turns: ${chart.values[0].toInt()}');
    expect(
      find.descendant(
        of: chartCard('Busiest hours'),
        matching: find.text('Parties settled at tables, by hour'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('REP-OPS-018 Revenue by table: the 12 biggest earners, every '
      'label, money tooltip', (tester) async {
    final h = await pumpOps(tester);
    final rows = _rows(tester);
    final top = ([...rows]
          ..sort((a, b) => b.tableRevenue.compareTo(a.tableRevenue)))
        .take(12)
        .toList();
    final chart = tester.widget<OpsBarChart>(_byTable);
    expect(chart.labels, [for (final r in top) r.table]);
    expect(chart.values, [for (final r in top) r.tableRevenue.toDouble()]);
    final f = h.container.read(formatProvider);
    expect(
      chart.tooltip(0),
      'Table revenue: ${f.fmtMoney(top.first.tableRevenue)}',
    );
    expect(chart.formatAxis(120000), f.fmtMoneyCompact(120000));
  });

  testWidgets('REP-OPS-019 the columns (Branch with All branches); rows in '
      'the server\'s order, turns first', (tester) async {
    final h = await pumpOps(tester);
    final table = tester.widget<DashDataTable<OpsTableRow>>(_table);
    expect([for (final c in table.columns) c.label], [
      'Table',
      'Section',
      'Branch',
      'Turns',
      'Turns / day',
      'Covers',
      'Table revenue',
      'Revenue per cover',
      'Average stay',
    ]);
    final turns = [for (final r in table.rows) r.turns];
    expect(turns, [...turns]..sort((a, b) => b.compareTo(a)));
    // One row's cells as the web prints them.
    final r = table.rows.first;
    final f = h.container.read(formatProvider);
    final row = find.ancestor(
      of: find.descendant(of: _table, matching: find.text(r.table)).first,
      matching: find.byWidgetPredicate((w) => w is Row),
    );
    expect(row, findsWidgets);
    expect(
      find.descendant(
        of: _table,
        matching: find.text(dashFigure(f.fmtMoney(r.tableRevenue))),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(of: _table, matching: find.text(fmtDwell(r.avgDwellMinutes))),
      findsWidgets,
    );
    expect(table.columns.first.phone, DashPhoneRole.title);
    await h.container.read(scopeProvider.notifier).setBranch(SeedIds.zamalek);
    await h.settle();
    // "No section" for a table outside any section.
    expect(_rows(tester).any((x) => x.section == 'No section'), isTrue);
    expect(
      [
        for (final c
            in tester.widget<DashDataTable<OpsTableRow>>(_table).columns)
          c.label,
      ],
      isNot(contains('Branch')),
    );
  });

  testWidgets('REP-OPS-020 / REP-ALL-015 search: over every column\'s raw '
      'value, case-insensitive; back to page 1', (tester) async {
    final h = await pumpOps(tester);
    expect(
      tester.widget<DashDataTable<OpsTableRow>>(_table).searchPlaceholder,
      'Search tables',
    );
    // Page 2 first.
    await h.tap(find.descendant(of: _table, matching: find.bySemanticsLabel('Next')));
    expect(
      find.descendant(of: _table, matching: textHas('Page 2 of')),
      findsOneWidget,
    );
    final search = find.descendant(
      of: _table,
      matching: find.byType(DashSearchInput),
    );
    await h.enterText(search, 'zamalek');
    final shown = _shownTables(tester);
    expect(shown, isNotEmpty);
    expect(
      find.descendant(of: _table, matching: textHas('Page 2 of')),
      findsNothing,
    );
    final rows = _rows(tester).where((r) => r.branch == 'Zamalek').toList();
    expect(shown.length, rows.length.clamp(0, 10));
    // A formatted figure never matches (the raw piastres do).
    await h.enterText(search, 'EGP');
    expect(_shownTables(tester), isEmpty);
    expect(
      find.descendant(of: _table, matching: find.text('No table sales in this period')),
      findsOneWidget,
    );
    final r = _rows(tester).first;
    await h.enterText(search, '${r.tableRevenue}');
    expect(_shownTables(tester), contains(r.table));
  });

  testWidgets('REP-OPS-021 / REP-ALL-016 / 017 ten rows a page with Previous '
      '/ Next; the Columns menu lists only "Table"', (tester) async {
    final h = await pumpOps(tester);
    final rows = _rows(tester);
    expect(rows.length, greaterThan(10));
    expect(_shownTables(tester), hasLength(10));
    final pages = (rows.length / 10).ceil();
    expect(
      find.descendant(of: _table, matching: find.text('Page 1 of $pages')),
      findsOneWidget,
    );
    await h.tap(find.descendant(of: _table, matching: find.bySemanticsLabel('Next')));
    expect(
      find.descendant(of: _table, matching: find.text('Page 2 of $pages')),
      findsOneWidget,
    );
    await h.tap(
      find.descendant(of: _table, matching: find.bySemanticsLabel('Previous')),
    );
    expect(
      find.descendant(of: _table, matching: find.text('Page 1 of $pages')),
      findsOneWidget,
    );
    // The Columns menu: one more "Table" (its only entry), no other label.
    final tables = find.text('Table').evaluate().length;
    final sections = find.text('Section').evaluate().length;
    await h.tap(find.descendant(of: _table, matching: find.text('Columns')));
    expect(find.text('Table'), findsNWidgets(tables + 1));
    expect(find.text('Section'), findsNWidgets(sections));
    await h.shot('operations/tables-columns');
    await h.tap(find.text('Table').last);
    expect(
      find.descendant(of: _table, matching: find.text(rows.first.table)),
      findsNothing,
    );
  });

  testWidgets('REP-ALL-016 phone: no Columns menu', (tester) async {
    await pumpOps(tester, size: DashSize.phone);
    expect(find.descendant(of: _table, matching: find.text('Columns')), findsNothing);
  });

  testWidgets('REP-OPS-022 no table sales: the empty words everywhere',
      (tester) async {
    final h = await pumpOps(tester);
    await h.container.read(scopeProvider.notifier).setCustomRange(
      '2026-01-01T00:00:00.000Z',
      '2026-01-02T00:00:00.000Z',
    );
    await h.settle();
    expect(pageText('No table sales in this period'), findsNWidgets(3));
    expect(_kpi(tester, 'turns'), 0);
    expect(
      find.descendant(of: find.byKey(const ValueKey('dwell')), matching: find.text('—')),
      findsOneWidget,
    );
    await h.shot('operations/tables-empty');
  });

  group('REP-OPS-023…033 a table\'s history', () {
    testWidgets('REP-OPS-023 / 025 / 027 / 030 / 031 a row opens the side '
        'panel: title, section, the figures and the bills', (tester) async {
      final h = await pumpOps(tester, branchId: SeedIds.heliopolis);
      await _openRow(h, 'T1');
      expect(_sheet, findsOneWidget);
      expect(find.text('Table T1'), findsOneWidget);
      expect(
        find.descendant(of: _sheet, matching: find.text('Main hall')),
        findsOneWidget,
      );
      final floor = h.server.callsTo(floorRoute).single;
      expect(floor.query['branch_id'], [SeedIds.heliopolis]);
      final history = h.server.callsTo(historyRoute).single;
      final id = opsTables
          .firstWhere((t) => t.branchKey == 'heliopolis' && t.label == 'T1')
          .id;
      expect(history.path, '/floor/tables/$id/history');
      final scope = h.container.read(currentScopeProvider);
      expect(
        DateTime.parse(history.query['from']!.single),
        DateTime.parse(scope.from),
      );
      expect(
        DateTime.parse(history.query['to']!.single),
        DateTime.parse(scope.to),
      );
      // The figures.
      final f = h.container.read(formatProvider);
      final res = await tester.runAsync(
        () => h.server.send(
          ApiRequest(method: 'GET', path: history.path, query: history.query),
        ),
      );
      final data = jsonDecode(utf8.decode(res!.bodyBytes)) as Map;
      expect(
        find.descendant(
          of: _sheet,
          matching: find.text(dashFigure(f.fmtMoney(data['total_minor']))),
        ),
        findsOneWidget,
      );
      for (final w in ['Takings', 'Average bill', 'Average stay', 'Turns a day', 'Bills']) {
        expect(find.descendant(of: _sheet, matching: find.text(w)), findsOneWidget);
      }
      final turns = fmtNum(
        f,
        (data['turns_per_day_x100'] as num) / 100,
        minDp: 1,
        maxDp: 1,
      );
      expect(
        find.descendant(of: _sheet, matching: find.text(dashFigure(turns))),
        findsOneWidget,
      );
      // The open bill: "Still open".
      expect(
        find.descendant(of: _sheet, matching: find.text('Still open')),
        findsOneWidget,
      );
      await h.shot('operations/table-history');
    });

    testWidgets('REP-OPS-031 a voided bill says "Voided"; covers in the '
        'sub-line', (tester) async {
      final s = opsServer();
      final t1 = opsTables.firstWhere(
        (t) => t.branchKey == 'heliopolis' && t.label == 'T1',
      );
      s.server.on('GET', historyRoute, (req) {
        return MockResponse.ok({
          'table_id': t1.id,
          'label': 'T1',
          'from': '2026-09-08T21:00:00Z',
          'to': '2026-10-08T20:59:59Z',
          'sittings': [
            {
              'open_ticket_id': 'a',
              'ticket_ref': 'T-HEL-1',
              'opened_at': '2026-10-01T10:00:00Z',
              'seated_at': '2026-10-01T10:00:00Z',
              'minutes': 45,
              'status': 'voided',
              'guest_count': 3,
            },
            {
              'open_ticket_id': 'b',
              'opened_at': '2026-10-01T12:00:00Z',
              'seated_at': '2026-10-01T12:00:00Z',
              'minutes': 0,
              'status': 'settled',
              'total_amount': 12550,
              'guest_count': 1,
            },
          ],
          'covers': 1,
          'settled_count': 1,
          'total_minor': 12550,
          'average_bill_minor': 12550,
          'average_minutes': 65,
          'turns_per_day_x100': 3,
        });
      });
      final h = await pumpOps(
        tester,
        server: s.server,
        db: s.db,
        branchId: SeedIds.heliopolis,
      );
      await _openRow(h, 'T1');
      expect(find.descendant(of: _sheet, matching: find.text('Voided')), findsOneWidget);
      expect(find.descendant(of: _sheet, matching: find.text('T-HEL-1')), findsOneWidget);
      expect(
        find.descendant(of: _sheet, matching: textHas('3 covers')),
        findsOneWidget,
      );
      // No customer and no ref: "—"; under a minute: "—".
      expect(find.descendant(of: _sheet, matching: find.text('—')), findsWidgets);
      expect(
        find.descendant(of: _sheet, matching: find.text(dashFigure('0.0'))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _sheet, matching: find.text(dashFigure('1h 05m'))),
        findsOneWidget,
      );
    });

    testWidgets('REP-OPS-024 All branches: "Choose a branch…", nothing '
        'looked up', (tester) async {
      final h = await pumpOps(tester);
      await _openRow(h, _rows(tester).first.table);
      expect(
        find.descendant(
          of: _sheet,
          matching: find.text(h.t('tablesInsights.pickBranch')),
        ),
        findsOneWidget,
      );
      expect(h.server.callsTo(floorRoute), isEmpty);
      expect(h.server.callsTo(historyRoute), isEmpty);
    });

    testWidgets('REP-OPS-025 the lookup\'s skeleton; REP-OPS-027 the '
        'history\'s two skeletons', (tester) async {
      final s = opsServer();
      // The page asks for the floor on mount; it is still out.
      final floorGate = s.server.hold('GET', floorRoute);
      final h = await pumpOps(
        tester,
        server: s.server,
        db: s.db,
        branchId: SeedIds.heliopolis,
      );
      await _openRow(h, 'T1');
      expect(
        find.descendant(of: _sheet, matching: find.byType(DashSkeleton)),
        findsOneWidget,
      );
      final historyGate = s.server.hold('GET', historyRoute);
      floorGate.release();
      await h.settle();
      expect(
        find.descendant(of: _sheet, matching: find.byType(DashSkeleton)),
        findsNWidgets(2),
      );
      historyGate.release();
      await h.settle();
      expect(find.descendant(of: _sheet, matching: find.text('Bills')), findsOneWidget);
    });

    testWidgets('REP-OPS-026 a table no longer on the plan', (tester) async {
      final h = await pumpOps(tester, branchId: SeedIds.zamalek);
      expect(_rows(tester).any((r) => r.table == 'T10'), isTrue);
      await h.enterText(
        find.descendant(of: _table, matching: find.byType(DashSearchInput)),
        'T10',
      );
      await _openRow(h, 'T10');
      expect(
        find.descendant(
          of: _sheet,
          matching: find.text('This table is no longer on the floor plan.'),
        ),
        findsOneWidget,
      );
      expect(h.server.callsTo(historyRoute), isEmpty);
    });

    testWidgets('REP-OPS-026 a failed lookup (a 403) reads the same, with '
        'no Retry', (tester) async {
      final s = opsServer();
      s.server.fail(
        'GET',
        floorRoute,
        MockResponse.denied('floor.layout.read'),
        times: null,
      );
      final h = await pumpOps(
        tester,
        server: s.server,
        db: s.db,
        branchId: SeedIds.heliopolis,
      );
      await _openRow(h, 'T1');
      expect(
        find.descendant(
          of: _sheet,
          matching: find.text(h.t('tablesInsights.tableGone')),
        ),
        findsOneWidget,
      );
      expect(find.descendant(of: _sheet, matching: find.text('Retry')), findsNothing);
    });

    testWidgets('REP-OPS-028 the history failed', (tester) async {
      final s = opsServer();
      s.server.fail(
        'GET',
        historyRoute,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpOps(
        tester,
        server: s.server,
        db: s.db,
        branchId: SeedIds.heliopolis,
      );
      await _openRow(h, 'T1');
      expect(
        find.descendant(
          of: _sheet,
          matching: find.text("Couldn't load this table's history."),
        ),
        findsOneWidget,
      );
    });

    testWidgets('REP-OPS-029 nothing sat here in the period', (tester) async {
      final s = opsServer();
      s.server.on('GET', historyRoute, (req) {
        return MockResponse.ok({
          'table_id': req.param('id'),
          'label': 'T1',
          'from': '2026-09-08T21:00:00Z',
          'to': '2026-10-08T20:59:59Z',
          'sittings': <Object>[],
          'covers': 0,
          'settled_count': 0,
          'total_minor': 0,
          'average_bill_minor': 0,
          'average_minutes': 0,
          'turns_per_day_x100': 0,
        });
      });
      final h = await pumpOps(
        tester,
        server: s.server,
        db: s.db,
        branchId: SeedIds.heliopolis,
      );
      await _openRow(h, 'T1');
      expect(
        find.descendant(
          of: _sheet,
          matching: find.text('Nothing sat here in this period.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _sheet,
          matching: find.text(h.t('floor.history.empty')),
        ),
        findsNothing,
      );
    });

    testWidgets('REP-OPS-032 a named sitting opens the customer (read-only); '
        'one of their orders opens the order', (tester) async {
      final h = await pumpOps(tester, branchId: SeedIds.heliopolis);
      await _openRow(h, 'T1');
      final customer = MockSeed.instance.customers[0];
      final link = find.descendant(
        of: _sheet,
        matching: find.widgetWithText(DashPressable, customer.name),
      );
      expect(link, findsOneWidget);
      await h.tap(link);
      expect(find.byType(OpsCustomerSheet), findsOneWidget);
      expect(h.server.callsTo('/customers/{id}').single.path, '/customers/${customer.id}');
      await h.shot('operations/customer');
      final order = find.descendant(
        of: find.byType(OpsCustomerSheet),
        matching: find.byType(DashButton),
      );
      expect(order, findsWidgets);
      await h.tap(order.first);
      expect(find.byType(OpsOrderSheet), findsOneWidget);
      // The customer panel closed first; the table's history stays.
      expect(find.byType(OpsCustomerSheet), findsNothing);
      expect(_sheet, findsOneWidget);
      expect(h.server.callsTo('/orders/{order_id}'), hasLength(1));
      expect(
        find.descendant(of: find.byType(OpsOrderSheet), matching: find.text('Total')),
        findsWidgets,
      );
      await h.shot('operations/order');
    });

    testWidgets('REP-OPS-032 the customer could not be read: the error and '
        'Retry, spinning while it runs; the order\'s too', (tester) async {
      final s = opsServer();
      final refusal = MockResponse.error(500, 'The customer read failed');
      s.server.fail('GET', '/customers/{id}', refusal, times: null);
      final h = await pumpOps(
        tester,
        server: s.server,
        db: s.db,
        branchId: SeedIds.heliopolis,
      );
      await _openRow(h, 'T1');
      await h.tap(
        find.descendant(
          of: _sheet,
          matching: find.widgetWithText(
            DashPressable,
            MockSeed.instance.customers[0].name,
          ),
        ),
      );
      final sheet = find.byType(OpsCustomerSheet);
      expect(
        find.descendant(of: sheet, matching: find.text("Couldn't load this customer")),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: textHas(h.refusalWords(refusal))),
        findsOneWidget,
      );
      s.server.clearFailures();
      final gate = s.server.hold('GET', '/customers/{id}');
      await h.tap(find.descendant(of: sheet, matching: find.text('Retry')));
      expect(
        tester
            .widget<DashErrorState>(
              find.descendant(of: sheet, matching: find.byType(DashErrorState)),
            )
            .retrying,
        isTrue,
      );
      gate.release();
      await h.settle();
      expect(find.descendant(of: sheet, matching: find.byType(DashErrorState)),
          findsNothing);
      // An order that cannot be read.
      final orderRefusal = MockResponse.error(500, 'The order read failed');
      s.server.fail('GET', '/orders/{order_id}', orderRefusal, times: null);
      await h.tap(
        find.descendant(of: sheet, matching: find.byType(DashButton)).first,
      );
      expect(
        find.descendant(
          of: find.byType(OpsOrderSheet),
          matching: textHas(h.refusalWords(orderRefusal)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('REP-OPS-032 without customers.view the name is plain text',
        (tester) async {
      final s = opsServer();
      authzWithout(s.server, Persona.owner, {Cap.customersView});
      final h = await pumpOps(
        tester,
        server: s.server,
        db: s.db,
        branchId: SeedIds.heliopolis,
      );
      await _openRow(h, 'T1');
      final customer = MockSeed.instance.customers[0];
      expect(
        find.descendant(of: _sheet, matching: find.text(customer.name)),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: _sheet,
          matching: find.widgetWithText(DashPressable, customer.name),
        ),
        findsNothing,
      );
    });

    testWidgets('REP-OPS-033 closing the panel clears the table; another row '
        'opens its own', (tester) async {
      final h = await pumpOps(tester, branchId: SeedIds.heliopolis);
      await _openRow(h, 'T1');
      expect(_sheet, findsOneWidget);
      await h.tap(find.bySemanticsLabel('Close').last);
      expect(_sheet, findsNothing);
      await _openRow(h, 'T2');
      expect(find.text('Table T2'), findsOneWidget);
    });

    testWidgets('REP-ALL-031 a row is a tap target named by its table, on '
        'the phone too', (tester) async {
      final h = await pumpOps(
        tester,
        size: DashSize.phone,
        branchId: SeedIds.heliopolis,
      );
      final table = tester.widget<DashDataTable<OpsTableRow>>(_table);
      expect(table.onRowTap, isNotNull);
      expect(table.rowSemanticLabel!(table.rows.first), table.rows.first.table);
      await h.tap(_names.first);
      expect(_sheet, findsOneWidget);
      await h.shot('operations/table-history');
    });
  });

  group('REP-OPS-065 / REP-ALL-009 live', () {
    testWidgets('a till event never refetches Tables (nor does resync)', (
      tester,
    ) async {
      final h = await pumpOps(tester, branchId: SeedIds.heliopolis);
      expect(h.server.callsTo(metricsRoute, method: 'POST'), hasLength(1));
      h.realtime.current!.emit('till.closed', data: '{}');
      await h.settle();
      h.realtime.current!.emit('resync');
      await h.settle();
      expect(h.server.callsTo(metricsRoute, method: 'POST'), hasLength(1));
    });

    testWidgets('a floor event refetches the open table\'s history, not the '
        'floor lookup', (tester) async {
      final h = await pumpOps(tester, branchId: SeedIds.heliopolis);
      await _openRow(h, 'T1');
      expect(h.server.callsTo(historyRoute), hasLength(1));
      h.realtime.current!.emit('ticket.updated', data: '{}');
      await h.settle();
      expect(h.server.callsTo(historyRoute), hasLength(2));
      h.realtime.current!.emit('resync');
      await h.settle();
      expect(h.server.callsTo(historyRoute), hasLength(3));
      expect(h.server.callsTo(floorRoute), hasLength(1));
    });

    testWidgets('with All branches there is no stream', (tester) async {
      final h = await pumpOps(tester);
      expect(h.realtime.current, isNull);
    });
  });

  group('REP-ALL-018 / 019 the table kit\'s states and phone cards', () {
    testWidgets('phone: every row a card titled by its table, the other '
        'cells labelled', (tester) async {
      final h = await pumpOps(tester, size: DashSize.phone, locale: 'ar');
      final table = tester.widget<DashDataTable<OpsTableRow>>(_table);
      expect(table.columns.first.phone, DashPhoneRole.title);
      expect(
        find.descendant(of: _table, matching: find.text(h.t('tablesInsights.covers'))),
        findsWidgets,
      );
      await h.shot('operations/tables-phone');
    });

    testWidgets('a failed background refetch replaces the rows with the '
        'error (REP-ALL-018)', (tester) async {
      final s = opsServer();
      final h = await pumpOps(tester, server: s.server, db: s.db);
      expect(_table, findsOneWidget);
      s.server.fail(
        'POST',
        metricsRoute,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      // Retry from elsewhere: the period changes and comes back.
      await h.container
          .read(scopeProvider.notifier)
          .setPreset(ScopePreset.last7Days);
      await h.settle();
      expect(pageText("Couldn't load table insights"), findsOneWidget);
      expect(_table, findsNothing);
    });
  });
}
