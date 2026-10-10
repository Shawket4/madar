// `/reports/tills` Till sessions, driven through the real app shell
// (inventory rows REP-TIL-001 to -024): the gate, the one read, the three
// tabs over it, every cell rule of the sessions table, the export.
import 'dart:async';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashSidebar, PrefetchOnIntent;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/mock/tills_report_mock.dart';
import 'package:dashboard_reports/src/shared/report_dates.dart';
import 'package:dashboard_reports/src/tills_report/tills_lib.dart' show fsi;
import 'package:dashboard_reports/src/tills_report/tills_parts.dart';
import 'package:dashboard_reports/src/tills_report/tills_sessions_table.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The cell of [column] in the row of till [id].
Finder cell(String id, String column) => find.byKey(tillCellKey(id, column));

/// Texts inside the cell of [column] in the row of till [id].
Finder inCell(String id, String column, Finder f) =>
    find.descendant(of: cell(id, column), matching: f);

/// The sidebar's Reports › Tills leaf (Sell › Tills is another).
Finder get tillsLeaf => find.descendant(
  of: find.byType(DashSidebar),
  matching: find.byWidgetPredicate(
    (w) => w is PrefetchOnIntent && w.to == tillsPath,
  ),
);

String cellText(WidgetTester tester, String id, String column) {
  final texts = tester.widgetList<Text>(inCell(id, column, find.byType(Text)));
  return [
    for (final t in texts) t.data ?? t.textSpan?.toPlainText() ?? '',
  ].join(' ');
}

void main() {
  group('the gate', () {
    testWidgets('REP-TIL-001 till.read alone: Restricted with the reports\' '
        'words, no tabs, the sessions never asked for', (tester) async {
      final h = await pumpTills(tester, persona: Persona.limited);
      expect(pageText('Till sessions'), findsOneWidget);
      expect(pageText('Not available on this account'), findsOneWidget);
      expect(
        pageText(
          "Your account can't open this report. The owner can give you access.",
        ),
        findsOneWidget,
      );
      expect(find.byType(DashPageTabs<String>), findsNothing);
      expect(exportButton, findsNothing);
      expect(h.server.callsTo(tillsTpl), isEmpty);
      // The sidebar does not offer it either (REP-ALL-002).
      expect(tillsLeaf, findsNothing);
      await h.shot('restricted');
    });

    testWidgets('REP-TIL-001 till.read.branch opens it, and the sidebar '
        'offers it', (tester) async {
      final h = await pumpTills(tester, persona: Persona.manager);
      expect(pageText('Sessions'), findsOneWidget);
      expect(pageText('Not available on this account'), findsNothing);
      expect(h.server.callsTo(tillsTpl), hasLength(1));
      expect(tillsLeaf, findsOneWidget);
    });

    testWidgets('REP-TIL-001 / REP-ALL-030 (divergence SH-10) nothing renders '
        'and nothing is asked while the rights load; then the page and its '
        'read', (tester) async {
      final s = tillsServer();
      final gate = s.server.hold('GET', '/authz/me');
      final h = await pumpTills(tester, server: s.server, db: s.db);
      expect(tillsPage, findsOneWidget);
      expect(find.byType(DashPageTabs<String>), findsNothing);
      expect(pageText('Not available on this account'), findsNothing);
      expect(h.server.callsTo(tillsTpl), isEmpty);
      gate.release();
      await h.settle();
      expect(find.byType(DashPageTabs<String>), findsOneWidget);
      expect(h.server.callsTo(tillsTpl), hasLength(1));
    });

    testWidgets('REP-TIL-001 (divergence SH-10) rights that fail to load: the '
        "shell's error with Retry, which asks again", (tester) async {
      final s = tillsServer();
      s.server.fail(
        'GET',
        '/authz/me',
        MockResponse.error(500, 'Rights unavailable'),
        times: null,
      );
      final h = await pumpTills(tester, server: s.server, db: s.db);
      // The shell's gate answers before the page is built (the web's
      // ModuleGate / useAuthzLoadError).
      expect(find.text(h.t('shell.accessLoadError')), findsOneWidget);
      expect(find.text('Rights unavailable'), findsOneWidget);
      expect(tillsPage, findsNothing);
      expect(h.server.callsTo(tillsTpl), isEmpty);
      s.server.clearFailures();
      await h.tap(find.text('Retry'));
      expect(find.byType(DashPageTabs<String>), findsOneWidget);
      expect(h.server.callsTo(tillsTpl), hasLength(1));
    });
  });

  group('the read', () {
    testWidgets('REP-TIL-002 every branch: the sentinel and the scope\'s '
        'range only', (tester) async {
      final h = await pumpTills(tester);
      final call = h.server.callsTo(tillsTpl).single;
      expect(call.path, '/reports/branches/$allBranchesId/tills');
      final s = h.container.read(currentScopeProvider);
      expect(call.query.keys.toSet(), {'from', 'to'});
      expect(
        DateTime.parse(call.query['from']!.single),
        DateTime.parse(s.from),
      );
      expect(DateTime.parse(call.query['to']!.single), DateTime.parse(s.to));
    });

    testWidgets('REP-TIL-002 a picked branch is asked for by id; a branch '
        'or period change asks again', (tester) async {
      final h = await pumpTills(
        tester,
        path: '$tillsPath?branchId=${SeedIds.maadi}',
      );
      expect(
        h.server.callsTo(tillsTpl).last.path,
        '/reports/branches/${SeedIds.maadi}/tills',
      );
      await h.go('$tillsPath?branchId=${SeedIds.zamalek}&preset=7d');
      final last = h.server.callsTo(tillsTpl).last;
      expect(last.path, '/reports/branches/${SeedIds.zamalek}/tills');
      final s = h.container.read(currentScopeProvider);
      expect(
        DateTime.parse(last.query['from']!.single),
        DateTime.parse(s.from),
      );
    });

    testWidgets('REP-TIL-002 (REP-ALL-009) a till event refetches the '
        'sessions of the picked branch', (tester) async {
      final h = await pumpTills(
        tester,
        path: '$tillsPath?branchId=${SeedIds.zamalek}',
      );
      final before = h.server.callsTo(tillsTpl).length;
      h.realtime.current!.emit('till.opened', data: '{}');
      await h.settle();
      expect(h.server.callsTo(tillsTpl), hasLength(before + 1));
    });
  });

  group('the header', () {
    testWidgets('REP-TIL-003 no count while loading, then "N till sessions — '
        '…"', (tester) async {
      final s = tillsServer();
      final gate = s.server.hold('GET', tillsTpl);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      expect(
        pageText('Opening float, cash through the drawer, and the close'),
        findsOneWidget,
      );
      expect(pageHas('0 till sessions'), findsNothing);
      expect(pageText('No till sessions opened in this period'), findsNothing);
      gate.release();
      await h.settle();
      final n = _sessionsIn(h);
      expect(
        pageText(
          '$n till sessions — opening float, cash through the drawer, and '
          'the close',
        ),
        findsOneWidget,
      );
    });

    testWidgets('REP-TIL-003 one session: the singular', (tester) async {
      final s = serverWith(webSessions().take(1).toList());
      await pumpTills(tester, server: s.server, db: s.db);
      expect(
        pageText(
          '1 till session — opening float, cash through the drawer, and the '
          'close',
        ),
        findsOneWidget,
      );
    });

    testWidgets('REP-TIL-005 three tabs, Sessions first; switching asks '
        'nothing more', (tester) async {
      final h = await pumpTills(tester);
      final tabs = tester.widget<DashPageTabs<String>>(
        find.byType(DashPageTabs<String>),
      );
      expect(
        [for (final t in tabs.tabs) t.label],
        ['Sessions', 'Sales', 'Open & close'],
      );
      expect(tabs.value, 'sessions');
      expect(find.byType(TillSessionsTable), findsOneWidget);
      await openTab(h, 'Sales');
      expect(pageText('By session'), findsOneWidget);
      await openTab(h, 'Open & close');
      expect(pageText('Opens and closes by hour'), findsOneWidget);
      await openTab(h, 'Sessions');
      expect(h.server.callsTo(tillsTpl), hasLength(1));
    });
  });

  group('load states', () {
    testWidgets('REP-TIL-006 a refused range: the shorter-range sentence, no '
        'Retry, on all three tabs', (tester) async {
      final s = tillsServer();
      const serverWords =
          'More than 5000 till sessions in this range; narrow `from`/`to`';
      s.server.fail(
        'GET',
        tillsTpl,
        MockResponse.error(400, serverWords),
        times: null,
      );
      final h = await pumpTills(tester, server: s.server, db: s.db);
      const words =
          'Too many till sessions to list for this period. Choose a shorter '
          'date range.';
      for (final tab in ['Sessions', 'Sales', 'Open & close']) {
        await openTab(h, tab);
        expect(pageText(words), findsOneWidget, reason: tab);
        expect(pageHas('narrow'), findsNothing, reason: tab);
        expect(pageText('Retry'), findsNothing, reason: tab);
        expect(
          pageText('No till sessions opened in this period'),
          findsNothing,
          reason: tab,
        );
      }
      expect(tester.widget<DashExportButton>(exportButton).enabled, isFalse);
      await openTab(h, 'Sessions');
      await h.shot('range-refused');
    });

    testWidgets('REP-TIL-007 any other failure: the server\'s words and Retry '
        'on every tab, never the empty sentence; Retry asks again', (
      tester,
    ) async {
      final s = tillsServer();
      s.server.fail(
        'GET',
        tillsTpl,
        MockResponse.error(500, 'The ledger is busy'),
        times: null,
      );
      final h = await pumpTills(tester, server: s.server, db: s.db);
      for (final tab in ['Sessions', 'Sales', 'Open & close']) {
        await openTab(h, tab);
        expect(pageText("Couldn't load this"), findsOneWidget, reason: tab);
        expect(pageText('The ledger is busy'), findsOneWidget, reason: tab);
        expect(pageText('Retry'), findsOneWidget, reason: tab);
        expect(
          pageText('No till sessions opened in this period'),
          findsNothing,
          reason: tab,
        );
      }
      await h.shot('failed-timing');
      await openTab(h, 'Sessions');
      await h.shot('failed');
      s.server.clearFailures();
      final before = h.server.callsTo(tillsTpl).length;
      await h.tap(pageText('Retry'));
      expect(h.server.callsTo(tillsTpl), hasLength(before + 1));
      expect(pageText("Couldn't load this"), findsNothing);
      expect(find.byType(TillVariance), findsWidgets);
    });

    testWidgets('REP-TIL-007 a refusal (403) shows the server\'s words', (
      tester,
    ) async {
      final s = tillsServer();
      final denied = MockResponse.denied('till.read');
      s.server.fail('GET', tillsTpl, denied, times: null);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      expect(pageText(h.refusalWords(denied)), findsOneWidget);
      expect(pageText('Retry'), findsOneWidget);
    });

    testWidgets('REP-TIL-007 while a Retry runs the failure stays, its '
        'button spinning: no skeleton, no empty sentence', (tester) async {
      final s = tillsServer();
      // A ledger that keeps failing, so each held retry fails again.
      s.server.on(
        'GET',
        tillsTpl,
        (req) => req.fail(MockResponse.error(500, 'The ledger is busy')),
      );
      final h = await pumpTills(tester, server: s.server, db: s.db);
      for (final tab in ['Sessions', 'Sales', 'Open & close']) {
        await openTab(h, tab);
        final gate = s.server.hold('GET', tillsTpl);
        final before = h.server.callsTo(tillsTpl).length;
        await h.tap(pageText('Retry'));
        expect(h.server.callsTo(tillsTpl), hasLength(before + 1), reason: tab);
        DashErrorState state() =>
            tester.widget<DashErrorState>(inPage(find.byType(DashErrorState)));
        expect(state().retrying, isTrue, reason: tab);
        expect(pageText('The ledger is busy'), findsOneWidget, reason: tab);
        expect(inPage(find.byType(DashSkeleton)), findsNothing, reason: tab);
        expect(
          pageText('No till sessions opened in this period'),
          findsNothing,
          reason: tab,
        );
        if (tab == 'Sessions') await h.shot('retrying');
        gate.release();
        s.server.clearFailures();
        await h.settle();
        expect(state().retrying, isFalse, reason: tab);
        expect(pageText('The ledger is busy'), findsOneWidget, reason: tab);
      }
      // The ledger answers again: the next Retry gets through.
      registerTillsReportMocks(s.server, s.db);
      await h.tap(pageText('Retry'));
      expect(inPage(find.byType(DashErrorState)), findsNothing);
      expect(pageText('Opens and closes by hour'), findsOneWidget);
    });

    testWidgets('REP-TIL-002 / 007 a deleted branch: the server\'s 404 with '
        'Retry, not the range sentence', (tester) async {
      final s = tillsServer();
      s.db['branches'].update(SeedIds.maadi, {'deleted_at': s.db.nowIso});
      final h = await pumpTills(
        tester,
        server: s.server,
        db: s.db,
        path: '$tillsPath?branchId=${SeedIds.maadi}',
      );
      final call = h.server.callsTo(tillsTpl).last;
      expect(call.path, '/reports/branches/${SeedIds.maadi}/tills');
      expect(
        pageText(h.refusalWords(MockResponse.notFound('Branch not found'))),
        findsOneWidget,
      );
      expect(pageText('Retry'), findsOneWidget);
      expect(pageHas('Choose a shorter date range'), findsNothing);
      expect(pageText('No till sessions opened in this period'), findsNothing);
    });

    testWidgets('REP-TIL-016 an empty period: the empty sentence, Export off', (
      tester,
    ) async {
      final s = serverWith(const []);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      expect(
        pageText('No till sessions opened in this period'),
        findsOneWidget,
      );
      expect(tester.widget<DashExportButton>(exportButton).enabled, isFalse);
      expect(
        pageText(
          '0 till sessions — opening float, cash through the drawer, and the '
          'close',
        ),
        findsOneWidget,
      );
      await h.shot('empty');
    });

    testWidgets('REP-TIL-017 Sales and Open & close: a skeleton while '
        'loading, the empty sentence when empty', (tester) async {
      final s = serverWith(const []);
      final gate = s.server.hold('GET', tillsTpl);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      for (final tab in ['Sales', 'Open & close']) {
        await openTab(h, tab);
        final sk = tester.widget<DashSkeleton>(
          inPage(find.byType(DashSkeleton)),
        );
        expect(sk.height, 256, reason: tab);
        expect(
          pageText('No till sessions opened in this period'),
          findsNothing,
        );
      }
      await h.shot('loading-timing');
      gate.release();
      await h.settle();
      for (final tab in ['Sales', 'Open & close']) {
        await openTab(h, tab);
        expect(
          pageText('No till sessions opened in this period'),
          findsOneWidget,
          reason: tab,
        );
        expect(inPage(find.byType(DashSkeleton)), findsNothing);
      }
    });

    testWidgets('REP-TIL-017 the Sessions table shows skeleton rows while '
        'loading', (tester) async {
      final s = tillsServer();
      final gate = s.server.hold('GET', tillsTpl);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      expect(inPage(find.byType(DashSkeleton)), findsWidgets);
      expect(pageText('No till sessions opened in this period'), findsNothing);
      await h.shot('loading');
      gate.release();
      await h.settle();
    });
  });

  group('the sessions table', () {
    testWidgets('REP-TIL-008 the columns, in order, all labelled; the '
        'Columns menu lists every one (REP-TIL-015)', (tester) async {
      final s = serverWith(webSessions());
      final h = await pumpTills(tester, server: s.server, db: s.db);
      final table = tester.widget<DashDataTable<Object?>>(
        inPage(find.byWidgetPredicate((w) => w is DashDataTable)),
      );
      const labels = [
        'Business date',
        'Branch',
        'Branch ref.',
        'User',
        'Opened at',
        'Opening',
        'Net cash',
        'Pay-ins',
        'Pay-outs',
        'Cash drops',
        'Adjustments',
        'Declared',
        'Expected',
        'Variance',
        'Orders',
        'Net sales',
        'Closed at',
      ];
      expect([for (final c in table.columns) c.label], labels);
      expect(table.pageSize, 50);
      expect(table.searchPlaceholder, 'Search branch or user');
      final before = {
        for (final l in labels) l: find.text(l).evaluate().length,
      };
      await h.tap(pageText('Columns'));
      for (final l in labels) {
        expect(find.text(l), findsNWidgets(before[l]! + 1), reason: l);
      }
      await h.shot('columns-menu');
    });

    testWidgets('REP-TIL-008 / 009 a closed row\'s cells as the web formats '
        'them; an open till\'s unknown figures read "—"', (tester) async {
      final s = serverWith(webSessions());
      await pumpTills(tester, server: s.server, db: s.db);
      expect(cellText(tester, 'till_1', 'business_date'), '18 Sept 2026');
      expect(cellText(tester, 'till_1', 'branch_name'), 'Zamalek');
      expect(cellText(tester, 'till_1', 'branch_code'), 'ZAM');
      expect(cellText(tester, 'till_1', 'teller_name'), 'Nour Adel');
      expect(cellText(tester, 'till_1', 'opened_at'), '18 Sept, 09:05 AM');
      for (final (col, v) in [
        ('opening_cash', 'EGP 500.00'),
        ('net_cash_payment', 'EGP 4,123.00'),
        ('pay_ins', 'EGP 200.00'),
        ('pay_outs', 'EGP 75.00'),
        ('cash_drops', 'EGP 3,000.00'),
        ('cash_adjustments', 'EGP 0.00'),
        ('closing_cash_declared', 'EGP 1,733.00'),
        ('closing_cash_system', 'EGP 1,748.00'),
        ('orders_count', '148'),
        ('net_sales', 'EGP 4,862.00'),
      ]) {
        expect(inCell('till_1', col, figure(v)), findsOneWidget, reason: col);
      }
      expect(cellText(tester, 'till_1', 'closed_at'), '18 Sept, 08:40 PM');
      // REP-TIL-009: the open till's close is not known yet.
      for (final col in [
        'closing_cash_declared',
        'closing_cash_system',
        'cash_discrepancy',
      ]) {
        expect(inCell('till_3', col, figure('—')), findsOneWidget, reason: col);
      }
    });

    testWidgets('REP-TIL-010 variance: short in a true minus with "Short", '
        'over with a plus and "Over", zero unsigned, unknown "—"', (
      tester,
    ) async {
      final s = serverWith([
        ...webSessions(),
        {
          ...webSessions().first,
          'till_id': 'till_even',
          'closing_cash_declared': 174800,
          'cash_discrepancy': 0,
        },
      ]);
      await pumpTills(tester, server: s.server, db: s.db);
      final handle = tester.ensureSemantics();
      expect(
        inCell('till_1', 'cash_discrepancy', figure('−EGP 15.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: cell('till_1', 'cash_discrepancy'),
          matching: find.bySemanticsLabel('Short −EGP 15.00'),
        ),
        findsOneWidget,
      );
      expect(
        inCell('till_2', 'cash_discrepancy', figure('+EGP 7.50')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: cell('till_2', 'cash_discrepancy'),
          matching: find.bySemanticsLabel('Over +EGP 7.50'),
        ),
        findsOneWidget,
      );
      expect(
        inCell('till_even', 'cash_discrepancy', figure('EGP 0.00')),
        findsOneWidget,
      );
      expect(inCell('till_4', 'cash_discrepancy', figure('—')), findsOneWidget);
      // The tint: destructive for short, warning for over, none at zero.
      final c = tester.element(cell('till_1', 'cash_discrepancy')).madarColors;
      Color? tint(String id) => tester
          .widget<Text>(inCell(id, 'cash_discrepancy', find.byType(Text)))
          .style
          ?.color;
      expect(tint('till_1'), Color.lerp(c.danger, c.textPrimary, 0.5));
      expect(tint('till_2'), Color.lerp(c.warning, c.textPrimary, 0.5));
      expect(tint('till_even'), isNull);
      handle.dispose();
    });

    testWidgets('REP-TIL-011 adjustments are always signed', (tester) async {
      final s = serverWith([
        webSessions()[1],
        {...webSessions()[0], 'cash_adjustments': 2000},
      ]);
      await pumpTills(tester, server: s.server, db: s.db);
      expect(
        inCell('till_2', 'cash_adjustments', figure('−EGP 5.00')),
        findsOneWidget,
      );
      expect(
        inCell('till_1', 'cash_adjustments', figure('+EGP 20.00')),
        findsOneWidget,
      );
    });

    testWidgets('REP-TIL-012 an open till reads "Open"; a force-close shows '
        'its time and "Force-closed", Declared and Variance blank, Expected '
        'known', (tester) async {
      final s = serverWith(webSessions());
      final h = await pumpTills(tester, server: s.server, db: s.db);
      expect(
        inCell(
          'till_3',
          'closed_at',
          find.byWidgetPredicate((w) => w is DashBadge && w.outline),
        ),
        findsOneWidget,
      );
      expect(cellText(tester, 'till_3', 'closed_at'), 'Open');
      expect(
        cellText(tester, 'till_4', 'closed_at'),
        '19 Sept, 01:20 AM Force-closed',
      );
      expect(
        inCell('till_4', 'closing_cash_declared', figure('—')),
        findsOneWidget,
      );
      expect(inCell('till_4', 'cash_discrepancy', figure('—')), findsOneWidget);
      expect(
        inCell('till_4', 'closing_cash_system', figure('EGP 732.00')),
        findsOneWidget,
      );
      // A closed till carries no badge.
      expect(
        inCell(
          'till_1',
          'closed_at',
          find.byWidgetPredicate((w) => w is DashBadge && w.outline),
        ),
        findsNothing,
      );
      await h.shot('sessions');
    });

    testWidgets('REP-TIL-013 a branch with no code reads "—"', (tester) async {
      final s = serverWith([
        {...webSessions().first, 'branch_code': ''},
      ]);
      await pumpTills(tester, server: s.server, db: s.db);
      expect(cellText(tester, 'till_1', 'branch_code'), '—');
    });

    testWidgets('REP-TIL-014 / 024 the search matches what each column '
        'reads, never the formatted text', (tester) async {
      final s = serverWith(webSessions());
      final h = await pumpTills(tester, server: s.server, db: s.db);
      final search = inPage(find.byType(DashSearchInput));
      Future<void> look(String q) => h.enterText(
        find.descendant(of: search, matching: find.byType(EditableText)),
        q,
      );
      int shown() =>
          tester.widgetList(inPage(find.byType(TillVariance))).length;
      await look('omar');
      expect(shown(), 1);
      await look('Maadi');
      expect(shown(), 2);
      await look('ZAM');
      expect(shown(), 2);
      await look('2026-09-19');
      expect(shown(), 1);
      // Piastres, not pounds.
      await look('486200');
      expect(shown(), 1);
      await look('EGP 4,862');
      expect(shown(), 0);
      await look('18 Sept');
      expect(shown(), 0);
      expect(
        pageText('No till sessions opened in this period'),
        findsOneWidget,
      );
      await look('');
      expect(shown(), 4);
    });

    testWidgets('REP-TIL-015 fifty rows a page', (tester) async {
      final h = await pumpTills(tester);
      final n = _sessionsIn(h);
      expect(n, greaterThan(50));
      final pages = (n / 50).ceil();
      expect(pageText('Page 1 of $pages'), findsOneWidget);
      expect(tester.widgetList(inPage(find.byType(TillVariance))).length, 50);
    });
  });

  group('the Sales tab', () {
    testWidgets('REP-TIL-018 the four KPIs, worked out from the rows', (
      tester,
    ) async {
      final s = serverWith(webSessions());
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openTab(h, 'Sales');
      DashStatCard card(String label) => tester.widget<DashStatCard>(
        inPage(
          find.byWidgetPredicate((w) => w is DashStatCard && w.label == label),
        ),
      );
      // 486,200 + 312,400 + 171,900 + 104,800 piastres; 148 + 96 + 52 + 37.
      expect(card('Net sales').value, 1075300);
      expect(card('Orders').value, 333);
      // The bill over ORDERS: round(1,075,300 / 333) = 3,229.
      expect(card('Average bill').value, 3229);
      // Per till: 1,075,300 / 4.
      expect(card('Average per till').value, 268825);
      expect(card('Average per till').hint, 'across 4 sessions');
      expect(pageText('EGP 10,753.00'), findsOneWidget);
      expect(pageText('EGP 32.29'), findsOneWidget);
      expect(pageText('EGP 2,688.25'), findsOneWidget);
      expect(pageText('333'), findsOneWidget);
      await h.shot('sales');
    });

    testWidgets('REP-TIL-018 one session: "across 1 session"', (tester) async {
      final s = serverWith(webSessions().take(1).toList());
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openTab(h, 'Sales');
      expect(pageText('across 1 session'), findsOneWidget);
    });

    testWidgets('REP-TIL-019 by session: ranked by net sales, teller · branch '
        '· day, a bar against the best, orders · share of the period', (
      tester,
    ) async {
      final s = serverWith(webSessions());
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openTab(h, 'Sales');
      final ids = ['till_1', 'till_2', 'till_4', 'till_3'];
      final ys = [
        for (final id in ids)
          tester.getTopLeft(find.byKey(ValueKey('till-rank:$id'))).dy,
      ];
      expect([...ys]..sort(), ys);
      Finder line(String id, Finder f) => find.descendant(
        of: find.byKey(ValueKey('till-rank:$id')),
        matching: f,
      );
      expect(
        line('till_1', find.textContaining('Nour Adel', findRichText: true)),
        findsOneWidget,
      );
      expect(
        line(
          'till_1',
          find.textContaining(
            '${fsi('Zamalek')} · ${fsi('18 Sept 2026')}',
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      expect(line('till_1', figure('EGP 4,862.00')), findsOneWidget);
      final bar = tester.widget<DashProgressBar>(
        line('till_1', find.byType(DashProgressBar)),
      );
      expect(bar.semanticLabel, '100% of the best session');
      expect(bar.value, 486200);
      expect(bar.max, 486200);
      // 486,200 of 1,075,300 = 45.2%.
      expect(line('till_1', find.text('148 orders · 45.2%')), findsOneWidget);
      expect(
        tester
            .widget<DashProgressBar>(
              line('till_2', find.byType(DashProgressBar)),
            )
            .semanticLabel,
        '64.3% of the best session',
      );
      // One teller's two days are told apart.
      expect(
        line(
          'till_3',
          find.textContaining(
            '${fsi('Zamalek')} · ${fsi('19 Sept 2026')}',
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('REP-TIL-019 a period that took nothing: shares read "—"', (
      tester,
    ) async {
      final s = serverWith([
        {...webSessions().first, 'net_sales': 0, 'orders_count': 0},
      ]);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openTab(h, 'Sales');
      expect(pageText('0 orders · —'), findsOneWidget);
    });

    testWidgets('REP-TIL-020 more than 20 sessions: the top 20, then "Show '
        'all"; it toggles back', (tester) async {
      final many = [
        for (var i = 0; i < 45; i++)
          {
            ...webSessions().first,
            'till_id': 't-$i',
            'net_sales': 1000 * (i + 1),
          },
      ];
      final s = serverWith(many);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openTab(h, 'Sales');
      int lines() => tester
          .widgetList(
            inPage(
              find.byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith('till-rank:'),
              ),
            ),
          )
          .length;
      expect(lines(), 20);
      // The best one leads.
      expect(find.byKey(const ValueKey('till-rank:t-44')), findsOneWidget);
      expect(find.byKey(const ValueKey('till-rank:t-0')), findsNothing);
      await h.scrollUntilVisible(pageText('Show all 45 sessions'));
      await h.tap(pageText('Show all 45 sessions'));
      expect(lines(), 45);
      await h.scrollUntilVisible(pageText('Show the top 20'));
      await h.tap(pageText('Show the top 20'));
      expect(lines(), 20);
    });
  });

  group('the Open & close tab', () {
    testWidgets('REP-TIL-021 typical open and close (circular means, the '
        "branch's clock), average and longest length", (tester) async {
      final s = serverWith(webSessions());
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openTab(h, 'Open & close');
      DashStatCard card(String label) => tester.widget<DashStatCard>(
        inPage(
          find.byWidgetPredicate((w) => w is DashStatCard && w.label == label),
        ),
      );
      // Opens 09:05, 09:10, 18:30, 09:00 Cairo.
      expect(card('Typical open').valueText, '10:08 AM');
      // Closes 20:40, 21:02 and 01:20 (past midnight); one still open.
      expect(card('Typical close').valueText, '10:16 PM');
      expect(card('Typical close').hint, '1 still open');
      // (695 + 712 + 410) / 3 minutes = 605 min 40 s.
      expect(card('Average length').valueText, '10h 05m');
      // Omar's 06:10 → 18:02.
      expect(card('Longest session').valueText, '11h 52m');
      expect(
        card('Longest session').hint,
        '${fsi('Omar Fathy')} · ${fsi('Maadi')} · ${fsi('18 Sept 2026')}',
      );
      expect(pageText('10:08 AM'), findsOneWidget);
      await h.shot('timing');
    });

    testWidgets('REP-TIL-021 nothing closed: "—" for close and length, the '
        'open count as the hint', (tester) async {
      final s = serverWith([webSessions()[3]]);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openTab(h, 'Open & close');
      DashStatCard card(String label) => tester.widget<DashStatCard>(
        inPage(
          find.byWidgetPredicate((w) => w is DashStatCard && w.label == label),
        ),
      );
      expect(card('Typical open').valueText, '09:00 AM');
      expect(card('Typical close').valueText, '—');
      expect(card('Typical close').hint, '1 still open');
      expect(card('Average length').valueText, '—');
      expect(card('Longest session').valueText, '—');
      expect(card('Longest session').hint, isNull);
    });

    testWidgets('REP-TIL-022 opens and closes by local hour, the chart an '
        'image with its sentence', (tester) async {
      final s = serverWith(webSessions());
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openTab(h, 'Open & close');
      final chart = tester.widget<TillHourChart>(
        inPage(find.byType(TillHourChart)),
      );
      expect(chart.buckets, hasLength(24));
      final opened = {
        for (final b in chart.buckets)
          if (b.opened > 0) b.hour: b.opened,
      };
      final closed = {
        for (final b in chart.buckets)
          if (b.closed > 0) b.hour: b.closed,
      };
      expect(opened, {9: 3, 18: 1});
      // The force-close past midnight counts at 1 AM.
      expect(closed, {1: 1, 20: 1, 21: 1});
      expect(
        chart.summary,
        'Till opens and closes counted by hour of the day. Typical open '
        '10:08 AM, typical close 10:16 PM.',
      );
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel(chart.summary), findsOneWidget);
      handle.dispose();
      expect(pageText('Opened'), findsOneWidget);
      expect(pageText('Closed'), findsOneWidget);
      // Hour labels every third hour, on the 12-hour clock.
      expect(find.text('12:00 AM'), findsOneWidget);
      expect(find.text('03:00 AM'), findsOneWidget);
      expect(find.text('01:00 AM'), findsNothing);
    });
  });

  group('Arabic and the phone', () {
    testWidgets('REP-TIL-023 Arabic: real labels, Western digits, '
        'LTR-isolated figures', (tester) async {
      final s = serverWith(webSessions());
      final h = await pumpTills(
        tester,
        server: s.server,
        db: s.db,
        locale: 'ar',
      );
      expect(pageText(h.t('reports.tills.tabSessions')), findsOneWidget);
      expect(pageText('الورديات'), findsOneWidget);
      expect(pageHas('فرق النقدية'), findsWidgets);
      expect(pageHas('تسويات'), findsWidgets);
      expect(
        inCell('till_2', 'cash_discrepancy', figure('\u2066+7.50\u2069 ج.م')),
        findsOneWidget,
      );
      final handle = tester.ensureSemantics();
      expect(
        find.descendant(
          of: cell('till_2', 'cash_discrepancy'),
          matching: find.bySemanticsLabel(RegExp('^زيادة ')),
        ),
        findsOneWidget,
      );
      handle.dispose();
      expect(cellText(tester, 'till_2', 'orders_count'), contains('96'));
      await h.shot('sessions');
      // Each part of "teller · branch · date" keeps its own direction, so
      // the Arabic date's "18" never attaches to the English name.
      await openTab(h, h.t('reports.tills.tabSales'));
      final day = fmtBusinessDate(
        h.container.read(formatProvider),
        '2026-09-18',
      );
      expect(day, contains('18'));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('till-rank:till_1')),
          matching: find.textContaining(
            '${fsi('Nour Adel')} · ${fsi('Zamalek')} · ${fsi(day)}',
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      await h.shot('sales');
    });

    testWidgets('REP-TIL-024 phone: a card per session titled by its business '
        'date, the other 16 fields labelled; no Columns menu', (tester) async {
      final s = serverWith(webSessions());
      final h = await pumpTills(
        tester,
        server: s.server,
        db: s.db,
        size: DashSize.phone,
      );
      expect(pageText('Columns'), findsNothing);
      expect(inPage(find.byType(DashSearchInput)), findsOneWidget);
      // Every row shows; its business date leads.
      expect(cell('till_1', 'business_date'), findsOneWidget);
      final title = tester.getTopLeft(cell('till_1', 'business_date')).dy;
      for (final col in ['branch_name', 'teller_name', 'cash_discrepancy']) {
        expect(
          tester.getTopLeft(cell('till_1', col)).dy,
          greaterThan(title),
          reason: col,
        );
      }
      for (final l in [
        'Branch',
        'User',
        'Variance',
        'Closed at',
        'Net sales',
      ]) {
        expect(pageText(l), findsWidgets, reason: l);
      }
      expect(pageText('Business date'), findsNothing);
      await h.shot('sessions-phone');
    });
  });

  group('the export', () {
    testWidgets('REP-TIL-004 / 024 Excel: one sheet "Till sessions", 18 '
        'columns, no period line, no totals; "Madar-Till sessions-<date>"', (
      tester,
    ) async {
      final s = serverWith(webSessions());
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await h.tap(exportButton);
      await h.tap(find.text('Export Excel').last);
      final spec = h.exports.built.single;
      final sheet = spec.sheets.single;
      expect(sheet.name, 'Till sessions');
      expect(sheet.title, 'Till sessions');
      expect(
        [for (final c in sheet.columns) c.header],
        [
          'Business date',
          'Branch',
          'Branch ref.',
          'User',
          'Opened at',
          'Opening',
          'Net cash',
          'Pay-ins',
          'Pay-outs',
          'Cash drops',
          'Adjustments',
          'Declared',
          'Expected',
          'Variance',
          'Orders',
          'Net sales',
          'Closed at',
          'Status',
        ],
      );
      expect({for (final c in sheet.columns) c.width}, {20});
      expect(sheet.totalsRow, isNull);
      expect(sheet.subtitle, isNot(contains('Last 30 days')));
      expect(sheet.rows, hasLength(4));
      // Business date as text; money in pounds; the status words.
      expect(sheet.rows[0][0], '2026-09-18');
      expect(sheet.rows[0][5], 500);
      expect(sheet.rows[1][10], -5);
      expect(sheet.rows[2][11], isNull);
      expect(sheet.rows[0][14], 148);
      expect(
        [for (final r in sheet.rows) r[17]],
        ['Closed', 'Closed', 'Force-closed', 'Open'],
      );
      final stamp = isoString(
        h.container.read(clockProvider)(),
      ).substring(0, 10);
      expect(h.files.saved.single.filename, 'Madar-Till sessions-$stamp.xlsx');
      await h.expectToast('Exported 4 rows');
    });

    testWidgets('REP-TIL-004 CSV: the same columns, money in pounds', (
      tester,
    ) async {
      final s = serverWith(webSessions());
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await h.tap(exportButton);
      await h.tap(find.text('Export CSV').last);
      final file = h.files.saved.single;
      expect(file.filename, startsWith('Madar-Till sessions-'));
      expect(file.filename, endsWith('.csv'));
      final lines = file.asString.split('\r\n');
      expect(
        lines.first,
        'Business date,Branch,Branch ref.,User,Opened at,Opening,Net cash,'
        'Pay-ins,Pay-outs,Cash drops,Adjustments,Declared,Expected,Variance,'
        'Orders,Net sales,Closed at,Status',
      );
      expect(lines, hasLength(5));
      expect(lines[2], startsWith('2026-09-18,Maadi,MAD,Omar Fathy,'));
      expect(lines[2], contains(',500,2689,0,120,2000,-5,1071.5,1064,7.5,96,'));
      expect(lines[4], endsWith(',,Open'));
      expect(h.exports.built, isEmpty);
      await h.expectToast('Exported 4 rows');
    });

    // The CSV path sets the same flag, but the test file gateway answers a
    // save at once and cannot be held, so only the Excel spinner is pinned.
    testWidgets('REP-TIL-004 / 024 Excel spins while it runs', (tester) async {
      final s = serverWith(webSessions());
      final h = await pumpTills(tester, server: s.server, db: s.db);
      final hold = Completer<void>();
      h.exports.hold = hold.future;
      await h.tap(exportButton);
      await h.tap(find.text('Export Excel').last);
      expect(tester.widget<DashExportButton>(exportButton).loading, isTrue);
      expect(find.text('Gathering data…'), findsOneWidget);
      await h.shot('exporting');
      hold.complete();
      await h.settle();
      expect(tester.widget<DashExportButton>(exportButton).loading, isFalse);
      await h.flushTimers();
    });

    testWidgets('REP-TIL-004 a failed Excel export says so', (tester) async {
      final s = serverWith(webSessions());
      final h = await pumpTills(tester, server: s.server, db: s.db);
      h.exports.failNext = StateError('disk full');
      await h.tap(exportButton);
      await h.tap(find.text('Export Excel').last);
      await h.expectToast('Export failed');
      expect(h.files.saved, isEmpty);
      expect(tester.widget<DashExportButton>(exportButton).loading, isFalse);
    });
  });
}

/// The sessions the default read answered (the page's subtitle count).
int _sessionsIn(DashHarness h) {
  final s = h.container.read(currentScopeProvider);
  final from = DateTime.parse(s.from);
  final to = DateTime.parse(s.to);
  return h.db!['tills'].rows.where((t) {
    if (!SeedIds.sabahBranches.contains(t['branch_id'])) return false;
    final at = DateTime.parse('${t['opened_at']}');
    return !at.isBefore(from) && !at.isAfter(to);
  }).length;
}
