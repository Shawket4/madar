// Legal's audit tabs, what they share (REP-LEG-013…021, 025…027, 038): the
// layout, the KPIs, the states, the cards and their rows, the history, the
// export and when it is offered.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/legal/audit_cards.dart';
import 'package:dashboard_reports/src/legal/audit_tab.dart';
import 'package:dashboard_reports/src/legal/legal_words.dart';
import 'package:dashboard_reports/src/mock/legal_mock.dart';
import 'package:design_system/design_system.dart' show MadarClippedText;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'legal_support.dart';

final String _voids = auditRoute('voids-audit');
final String _overrides = auditRoute('deduction-overrides-audit');

bool _inPeriod(Object? iso) {
  if (iso == null) return false;
  final at = DateTime.parse('$iso');
  return !at.isBefore(DateTime.parse(defaultFrom)) &&
      !at.isAfter(DateTime.parse(defaultTo));
}

/// The seed's voids at [branches] in the default period.
List<MockRow> voidsIn(MockDb db, [List<String>? branches]) => [
  for (final o in db['orders'].rows)
    if (o['status'] == 'voided' &&
        (branches ?? SeedIds.sabahBranches).contains(o['branch_id']) &&
        _inPeriod(o['voided_at']))
      o,
];

int _sum(Iterable<MockRow> rows, String field) =>
    rows.fold(0, (s, r) => s + (r[field] as num).toInt());

Future<void> _open(DashHarness h, LegalTab tab) => tapTab(h, h.t(tab.labelKey));

void main() {
  setUpAll(ensureTimeZones);

  testWidgets('REP-LEG-013 an audit tab: Export at the end, then the KPIs, '
      'then the cards', (tester) async {
    final h = await pumpLegal(tester);
    await _open(h, LegalTab.voids);
    final tab = tester.getRect(find.byType(LegalAuditTab));
    final export = tester.getRect(auditExport);
    final strip = tester.getRect(inAudit(find.byType(DashLedgerStrip)));
    final card = tester.getRect(auditCard('By reason'));
    expect(export.right, closeTo(tab.right, 1));
    expect(export.bottom, lessThanOrEqualTo(strip.top));
    expect(strip.bottom, lessThanOrEqualTo(card.top));
    // A small button.
    final button = tester.widget<DashButton>(
      find.descendant(of: auditExport, matching: find.byType(DashButton)),
    );
    expect(button.size, DashButtonSize.compact);
    expect(button.label, 'Export Excel');
  });

  testWidgets('REP-LEG-013 in Arabic the Export sits on the left', (
    tester,
  ) async {
    final h = await pumpLegal(tester, locale: 'ar');
    await _open(h, LegalTab.voids);
    final tab = tester.getRect(find.byType(LegalAuditTab));
    expect(tester.getRect(auditExport).left, closeTo(tab.left, 1));
  });

  testWidgets('REP-LEG-014 / 015 Voids: "Events" = the count, "Total amount" '
      '= the money, against the seed', (tester) async {
    final s = legalServer();
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _open(h, LegalTab.voids);
    final voids = voidsIn(s.db);
    expect(voids, isNotEmpty);
    final count = auditKpi(tester, 'count');
    expect(count.label, 'Events');
    expect(count.value, voids.length);
    expect(count.format, DashStatFormat.number);
    expect(count.tone, DashTone.accent);
    final amount = auditKpi(tester, 'amount');
    expect(amount.label, 'Total amount');
    expect(amount.value, _sum(voids, 'total_amount'));
    expect(amount.format, DashStatFormat.money);
    expect(amount.tone, DashTone.warning);
  });

  testWidgets('REP-LEG-015 Loyalty adjustments: "Points moved", a number', (
    tester,
  ) async {
    final h = await pumpLegal(tester);
    await _open(h, LegalTab.loyaltyAdjustments);
    final amount = auditKpi(tester, 'amount');
    expect(amount.label, 'Points moved');
    // 50 + 30 + 40 (a reversal, by size) + 25 + 60 + 100 + 20.
    expect(amount.value, 325);
    expect(amount.format, DashStatFormat.number);
    expect(auditKpi(tester, 'count').value, 7);
  });

  testWidgets('REP-LEG-015 Attendance corrections: "Events" alone', (
    tester,
  ) async {
    final h = await pumpLegal(tester);
    await _open(h, LegalTab.attendanceCorrections);
    expect(inAudit(find.byType(DashStatCard)), findsOneWidget);
    expect(auditKpi(tester, 'count').value, 11);
    expect(inAudit(find.byKey(const ValueKey('amount'))), findsNothing);
    expect(inAudit(find.text('Total amount')), findsNothing);
    expect(inAudit(find.text('Points moved')), findsNothing);
  });

  testWidgets('REP-LEG-016 loading: two 224 px skeletons, the KPIs\' own '
      'skeletons, Export off', (tester) async {
    final s = legalServer();
    final gate = s.server.hold('GET', _voids);
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _open(h, LegalTab.voids);
    final skeletons = tester
        .widgetList<DashSkeleton>(inAudit(find.byType(DashSkeleton)))
        .where((w) => w.height == 224);
    expect(skeletons, hasLength(2));
    for (final k in ['count', 'amount']) {
      expect(auditKpi(tester, k).loading, isTrue);
    }
    expect(auditExportEnabled(tester), isFalse);
    expect(inAudit(find.text(h.t('reports.legal.empty'))), findsNothing);
    await h.shot('legal/audit-loading');
    gate.release();
    await h.settle();
    expect(auditCard('By reason'), findsOneWidget);
    expect(auditExportEnabled(tester), isTrue);
  });

  testWidgets('REP-LEG-017 / REP-LEG-027 nothing in the period: "Nothing '
      'recorded in this period", zero KPIs, Export off', (tester) async {
    final h = await pumpLegal(tester);
    await _open(h, LegalTab.refunds);
    final empty = inAudit(find.byType(DashEmptyState));
    expect(empty, findsOneWidget);
    expect(
      tester.widget<DashEmptyState>(empty).title,
      'Nothing recorded in this period',
    );
    expect(auditKpi(tester, 'count').value, 0);
    expect(auditKpi(tester, 'amount').value, 0);
    expect(inAudit(find.byType(LegalCard)), findsNothing);
    expect(auditExportEnabled(tester), isFalse);
    await h.shot('legal/audit-empty');
  });

  testWidgets('REP-LEG-018 error: only the error state; Retry asks that '
      'audit alone again, the error staying while it runs', (tester) async {
    final s = legalServer();
    // Every read fails (the press's warm-up, dropped, and the tab's own),
    // however the two interleave, until the Retry.
    s.server.fail(
      'GET',
      _voids,
      MockResponse.error(500, 'Internal error'),
      times: null,
    );
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _open(h, LegalTab.voids);
    expect(inAudit(find.byType(DashErrorState)), findsOneWidget);
    expect(inAudit(find.text("Couldn't load this")), findsOneWidget);
    expect(auditExport, findsNothing);
    expect(inAudit(find.byType(DashStatCard)), findsNothing);
    await h.shot('legal/audit-error');
    s.server.clearFailures();
    final before = legalCalls(h).length;
    final gate = s.server.hold('GET', _voids);
    await tester.tap(inAudit(find.text('Retry')));
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<DashErrorState>(inAudit(find.byType(DashErrorState)))
          .retrying,
      isTrue,
    );
    expect(inAudit(find.text(h.t('reports.legal.empty'))), findsNothing);
    gate.release();
    await h.settle();
    expect(legalCalls(h), hasLength(before + 1));
    expect(legalCalls(h).last.template, _voids);
    expect(auditCard('By reason'), findsOneWidget);
  });

  testWidgets('REP-LEG-018 a refusal from the server is the same error state, '
      'never retried (asked once, plus the press\'s warm-up)', (tester) async {
    final s = legalServer();
    s.server.fail(
      'GET',
      _overrides,
      MockResponse.denied('hr.payroll.read'),
      times: null,
    );
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _open(h, LegalTab.deductionOverrides);
    expect(inAudit(find.byType(DashErrorState)), findsOneWidget);
    // The press's warm-up is refused, dropped, and the tab reads again; then
    // nothing more, however long the error stays up.
    final asked = h.server.callsTo(_overrides).length;
    expect(asked, inInclusiveRange(1, 2));
    await tester.pump(const Duration(seconds: 30));
    await h.settle();
    expect(h.server.callsTo(_overrides), hasLength(asked));
  });

  testWidgets('REP-LEG-019 / 020 each tab\'s cards: its own axis first, then '
      '"By staff member"', (tester) async {
    final s = legalServer();
    final order = s.db['orders'].rows.firstWhere(
      (o) => o['status'] == 'completed' && _inPeriod(o['created_at']),
    );
    final id = order['id']! as String;
    recordLegalRefund(
      s.db,
      orderId: id,
      amount: 5000,
      reason: 'Cold drink',
      issuedBy: SeedIds.user('nour'),
      issuedAt: s.db.clock.now,
    );
    waiveLegalServiceCharge(
      s.db,
      orderId: id,
      amount: 1200,
      by: SeedIds.user('nour'),
      at: s.db.clock.now,
    );
    flagLegalPrice(s.db, id);
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    const want = {
      LegalTab.refunds: 'By reason',
      LegalTab.voids: 'By reason',
      LegalTab.discounts: 'By discount',
      LegalTab.waivers: 'By branch',
      LegalTab.priceOverrides: 'By branch',
      LegalTab.manualDeductions: 'By reason',
      LegalTab.deductionOverrides: 'By type',
      LegalTab.loyaltyAdjustments: 'By branch',
      LegalTab.attendanceCorrections: 'By reason',
    };
    for (final MapEntry(key: tab, value: title) in want.entries) {
      await _open(h, tab);
      final titles = [
        for (final c in tester.widgetList<LegalCard>(
          inAudit(find.byType(LegalCard)),
        ))
          c.title,
      ];
      expect(titles.take(2), [title, 'By staff member'], reason: tab.id);
      final first = tester.widget<LegalCard>(auditCard(title));
      expect(first.icon, 'list-checks');
      expect(
        tester.widget<LegalCard>(auditCard('By staff member')).icon,
        'user-round',
      );
    }
  });

  testWidgets('REP-LEG-020 a card with no rows says "Nothing recorded in '
      'this period"', (tester) async {
    final s = legalServer();
    final order = s.db['orders'].rows.firstWhere(
      (o) => o['status'] == 'completed' && _inPeriod(o['created_at']),
    );
    // Issued by someone no longer on the books: no issuer row.
    recordLegalRefund(
      s.db,
      orderId: order['id']! as String,
      amount: 3000,
      reason: 'Wrong milk',
      issuedBy: mockUuid('legal:gone-user'),
      issuedAt: s.db.clock.now,
    );
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _open(h, LegalTab.refunds);
    expect(cardLabels(tester, 'By reason'), ['Wrong milk']);
    expect(
      inCard('By staff member', find.text('Nothing recorded in this period')),
      findsOneWidget,
    );
  });

  testWidgets('REP-LEG-020 no events (history only): no breakdown cards', (
    tester,
  ) async {
    final h = await pumpLegal(tester);
    // 22 Sep: only the undone waiver happened that day.
    await h.container
        .read(scopeProvider.notifier)
        .setCustomDays(DateTime(2026, 9, 22), DateTime(2026, 9, 22));
    await h.settle();
    await _open(h, LegalTab.deductionOverrides);
    expect(auditKpi(tester, 'count').value, 0);
    expect(auditCard('By type'), findsNothing);
    expect(auditCard('By staff member'), findsNothing);
    expect(auditCard('History'), findsOneWidget);
    expect(inAudit(find.text(h.t('reports.legal.empty'))), findsNothing);
    // REP-LEG-027: history alone is something to export.
    expect(auditExportEnabled(tester), isTrue);
  });

  testWidgets('REP-LEG-021 rows: label, "n events" / "1 event", money on the '
      'end side', (tester) async {
    final h = await pumpLegal(tester);
    await _open(h, LegalTab.manualDeductions);
    // Six in the period: 2 × Broken glassware (75 + 50), 2 × Cash shortage
    // (120 + 45), Late for opening (a percentage: no amount), Uniform (250).
    expect(cardLabels(tester, 'By reason'), [
      'Broken glassware',
      'Cash shortage at close',
      'Late for opening, third time this month',
      'Uniform not returned',
    ]);
    expect(inCard('By reason', find.text('2 events')), findsNWidgets(2));
    expect(inCard('By reason', find.text('1 event')), findsNWidgets(2));
    expect(inCard('By reason', find.text('EGP 125.00')), findsOneWidget);
    expect(inCard('By reason', find.text('EGP 165.00')), findsOneWidget);
    expect(inCard('By reason', find.text('EGP 0.00')), findsOneWidget);
    expect(inCard('By reason', find.text('EGP 250.00')), findsOneWidget);
    expect(auditKpi(tester, 'amount').value, 54000);
    expect(cardLabels(tester, 'By staff member'), [userName(h.db!, 'nour')]);
    expect(inCard('By staff member', find.text('6 events')), findsOneWidget);
    expect(inCard('By staff member', find.text('EGP 540.00')), findsOneWidget);
    // The label and its count sit at the start, the amount at the end.
    final label = tester.getRect(
      inCard('By reason', find.text('Broken glassware')),
    );
    final money = tester.getRect(inCard('By reason', find.text('EGP 125.00')));
    expect(money.left, greaterThan(label.right));
  });

  testWidgets('REP-LEG-021 points rows are plain numbers; attendance rows '
      'carry no amount', (tester) async {
    final h = await pumpLegal(tester);
    await _open(h, LegalTab.loyaltyAdjustments);
    expect(cardLabels(tester, 'By branch').first, 'Zamalek');
    expect(inCard('By branch', find.text('3 events')), findsOneWidget);
    expect(inCard('By branch', find.text('100')), findsNWidgets(2));
    expect(inCard('By branch', find.textContaining('EGP')), findsNothing);
    await _open(h, LegalTab.attendanceCorrections);
    expect(inCard('By reason', find.text('3 events')), findsOneWidget);
    expect(inCard('By reason', find.textContaining('EGP')), findsNothing);
    expect(
      inCard('By staff member', find.text(userName(h.db!, 'karim'))),
      findsOneWidget,
    );
    expect(inCard('By staff member', find.text('5 events')), findsOneWidget);
  });

  testWidgets('REP-LEG-021 Arabic: the count\'s plural forms', (tester) async {
    final h = await pumpLegal(tester, locale: 'ar');
    await _open(h, LegalTab.manualDeductions);
    expect(
      inCard(
        h.t('reports.legal.byReason'),
        find.text(
          h.t(
            'reports.legal.eventsCount',
            count: 1,
            args: {'n': fmtOf(h).fmtNumber(1)},
          ),
        ),
      ),
      findsNWidgets(2),
    );
    expect(
      h.t('reports.legal.eventsCount', count: 1, args: {'n': '1'}),
      'حدث واحد',
    );
    expect(
      h.t('reports.legal.eventsCount', count: 3, args: {'n': '3'}),
      '3 أحداث',
    );
  });

  testWidgets('REP-LEG-025 History: every waive, undo and override, newest '
      'first, with who, when, why and the amounts', (tester) async {
    final s = legalServer();
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _open(h, LegalTab.deductionOverrides);
    final card = auditCard('History');
    expect(tester.widget<LegalCard>(card).icon, 'history');
    final hist = tester.widget<HistoryCard>(find.byType(HistoryCard));
    expect(hist.events, hasLength(7));
    final names = [for (final e in hist.events) e.employeeName];
    String emp(String k) =>
        s.db['employees'].get(SeedIds.employee(k))['name']! as String;
    expect(names, [
      emp('hana'),
      emp('omar'),
      emp('ali'),
      emp('salma'),
      emp('youssef'),
      emp('mariam'),
      emp('youssef'),
    ]);
    // Badges.
    expect(
      find.descendant(
        of: card,
        matching: find.byWidgetPredicate((w) => w is DashBadge && w.outline),
      ),
      findsNWidgets(7),
    );
    expect(inCard('History', find.text('Waiver undone')), findsOneWidget);
    expect(inCard('History', find.text('Waived')), findsNWidgets(3));
    expect(inCard('History', find.text('Overridden')), findsNWidgets(3));
    // The newest: Hana's override, 25 → 10, by Nour, line of 6 Oct.
    final f = fmtOf(h);
    final first = hist.events.first;
    expect(
      inCard('History', find.text('EGP 25.00 → EGP 10.00')),
      findsOneWidget,
    );
    expect(
      inCard(
        'History',
        find.text(
          detailLine([
            f.fmtDateTime(first.at.toIso8601String()),
            'by ${userName(s.db, 'nour')}',
            'line of ${f.fmtDate('2026-10-06')}',
          ]),
        ),
      ),
      findsOneWidget,
    );
    expect(
      inCard(
        'History',
        find.text('Five minutes late, not twenty: the clock was fast'),
      ),
      findsOneWidget,
    );
    // The undone waiver: 0 → 50.
    expect(
      inCard('History', find.text('EGP 0.00 → EGP 50.00')),
      findsOneWidget,
    );
    await h.shot('legal/deduction-overrides');
  });

  testWidgets('REP-LEG-025 (divergence) in Arabic the arrow follows the '
      'reading direction', (tester) async {
    final h = await pumpLegal(tester, locale: 'ar');
    await _open(h, LegalTab.deductionOverrides);
    final f = fmtOf(h);
    expect(
      inCard(
        h.t('reports.legal.history'),
        find.text('${f.fmtMoney(2500)} ← ${f.fmtMoney(1000)}'),
      ),
      findsOneWidget,
    );
    expect(inAudit(find.text('History')), findsNothing);
    expect(inAudit(find.text('Waiver undone')), findsNothing);
    // REP-LEG-024 (divergence): the detail line's parts are isolated, so the
    // Latin name cannot split the Arabic date beside it.
    final cards = find.byType(HistoryCard);
    final e = tester.widget<HistoryCard>(cards).events.first;
    expect(
      find.descendant(
        of: cards,
        matching: find.text(
          detailLine([
            f.fmtDateTime(e.at.toIso8601String()),
            h.t('reports.legal.historyByName', args: {'name': e.actorName}),
            h.t(
              'reports.legal.historyLineOf',
              args: {'date': f.fmtDate(e.effectiveDate!)},
            ),
          ]),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('REP-LEG-026 audit to Excel: By type, By staff member and '
      'History, Madar-<tab>-<date>.xlsx', (tester) async {
    final h = await pumpLegal(tester);
    await _open(h, LegalTab.deductionOverrides);
    final asked = legalCalls(h).length;
    await auditMenu(h, 'Export Excel');
    final spec = h.exports.built.single;
    expect(
      [for (final s in spec.sheets) s.name],
      ['By type', 'By staff member', 'History'],
    );
    for (final sheet in spec.sheets) {
      expect(sheet.title, 'Deduction overrides');
    }
    expect(spec.sheets[0].subtitle, startsWith('By type'));
    expect(spec.sheets[1].subtitle, startsWith('By staff member'));
    expect(spec.sheets[2].subtitle, startsWith('History'));
    expect(
      [for (final c in spec.sheets[0].columns) c.header],
      ['Label', 'Events', 'Amount'],
    );
    expect(spec.sheets[0].columns[1].numFmt, '#,##0');
    expect(spec.sheets[0].columns[2].numFmt, '#,##0.00 "EGP"');
    // 3 overrides (100 + 150 + 15) and 2 waivers (30 + 40), worded.
    expect(spec.sheets[0].rows, [
      ['Overridden', 3, 265.0],
      ['Waived', 2, 70.0],
    ]);
    expect(
      [for (final st in spec.sheets[0].stats) st.label],
      ['Events', 'Total amount'],
    );
    expect(spec.sheets[0].stats[0].value, 5);
    expect(spec.sheets[0].stats[1].value, 335.0);
    expect(spec.sheets[1].rows, [
      [userName(h.db!, 'nour'), 5, 335.0],
    ]);
    expect(
      [for (final c in spec.sheets[2].columns) c.header],
      ['When', 'Employee', 'What', 'By', 'Reason', 'Before', 'After'],
    );
    expect(spec.sheets[2].rows, hasLength(7));
    expect(spec.sheets[2].rows.first.sublist(2), [
      'Overridden',
      userName(h.db!, 'nour'),
      'Five minutes late, not twenty: the clock was fast',
      25.0,
      10.0,
    ]);
    expect(
      h.files.saved.single.filename,
      'Madar-Deduction overrides-${exportStamp(h)}.xlsx',
    );
    expect(legalCalls(h), hasLength(asked));
    await h.expectToast('Exported 10 rows');
  });

  testWidgets('REP-LEG-026 points and attendance columns', (tester) async {
    final h = await pumpLegal(tester);
    await _open(h, LegalTab.loyaltyAdjustments);
    await auditMenu(h, 'Export Excel');
    var sheet = h.exports.built.last.sheets.first;
    expect(sheet.name, 'By branch');
    expect(
      [for (final c in sheet.columns) c.header],
      ['Label', 'Events', 'Points moved'],
    );
    expect(sheet.columns[2].numFmt, '#,##0');
    expect(sheet.stats[1].label, 'Points moved');
    expect(sheet.stats[1].value, 325);
    expect(h.exports.built.last.sheets, hasLength(2));
    await h.flushTimers();
    await _open(h, LegalTab.attendanceCorrections);
    await auditMenu(h, 'Export Excel');
    sheet = h.exports.built.last.sheets.first;
    expect([for (final c in sheet.columns) c.header], ['Label', 'Events']);
    expect([for (final st in sheet.stats) st.label], ['Events']);
    expect(sheet.rows.first, ['Approved correction request', 3]);
    await h.flushTimers();
  });

  testWidgets('REP-LEG-026 audit to CSV: the first sheet only', (tester) async {
    final h = await pumpLegal(tester);
    await _open(h, LegalTab.deductionOverrides);
    await auditMenu(h, 'Export CSV');
    final file = h.files.saved.single;
    expect(file.filename, 'Madar-Deduction overrides-${exportStamp(h)}.csv');
    expect(file.asString.split('\r\n'), [
      'Label,Events,Amount',
      'Overridden,3,265',
      'Waived,2,70',
    ]);
    await h.expectToast('Exported 2 rows');
  });

  testWidgets('REP-LEG-026 (divergence) the Arabic export is worded in '
      'Arabic, names and file included', (tester) async {
    final h = await pumpLegal(tester, locale: 'ar');
    await _open(h, LegalTab.deductionOverrides);
    await auditMenu(h, h.t('common.exportExcel'));
    final spec = h.exports.built.single;
    final latin = RegExp('[A-Za-z]');
    for (final s in spec.sheets) {
      expect(s.name, isNot(matches(latin)));
      for (final c in s.columns) {
        expect(c.header, isNot(matches(latin)), reason: c.header);
      }
    }
    expect(
      spec.sheets[0].rows.first.first,
      h.t('reports.legal.reason.overridden'),
    );
    expect(
      h.files.saved.single.filename,
      startsWith('Madar-${h.t('reports.legal.tabs.deductionOverrides')}-'),
    );
    await h.flushTimers();
  });

  testWidgets('REP-LEG-038 two cards a row from 1024 px; History and '
      'Discounted sales span the row; By kind follows them', (tester) async {
    final h = await pumpLegal(tester);
    await _open(h, LegalTab.deductionOverrides);
    final a = tester.getRect(auditCard('By type'));
    final b = tester.getRect(auditCard('By staff member'));
    final hist = tester.getRect(auditCard('History'));
    expect(a.top, b.top);
    expect(a.height, b.height);
    expect(b.left, greaterThan(a.right));
    expect(hist.top, greaterThan(a.bottom));
    expect(hist.width, closeTo(b.right - a.left, 1));
    await _open(h, LegalTab.discounts);
    final d = tester.getRect(auditCard('By discount'));
    final kind = tester.getRect(auditCard('By kind'));
    final sales = tester.getRect(auditCard('Discounted sales'));
    expect(kind.top, greaterThan(d.bottom));
    expect(kind.left, d.left);
    expect(kind.width, closeTo(d.width, 1));
    expect(sales.top, greaterThan(kind.bottom));
    expect(sales.width, greaterThan(kind.width * 2));
  });

  testWidgets('REP-LEG-038 below 1024 px one card a row', (tester) async {
    final h = await pumpLegal(tester, size: DashSize.phone);
    await _open(h, LegalTab.deductionOverrides);
    final a = tester.getRect(auditCard('By type'));
    final b = tester.getRect(auditCard('By staff member'));
    expect(b.top, greaterThan(a.bottom));
    expect(b.left, a.left);
    expect(b.width, a.width);
  });

  testWidgets('REP-LEG-038 labels cut on one line; History reasons wrap; By '
      'kind and Discounted sales stay out of the export', (tester) async {
    final s = legalServer();
    final long =
        'Broke the espresso machine portafilter during the morning '
        'rush and the replacement had to be ordered from Alexandria';
    s.db[legalDeductionsTable].insert({
      'id': mockUuid('legal:deduction:long'),
      'org_id': SeedIds.sabahOrg,
      'employee_id': SeedIds.employee('ziad'),
      'source': 'manual',
      'reason': long,
      'amount_piastres': 40000,
      'original_amount_piastres': 40000,
      'created_by': SeedIds.user('nour'),
      'created_at': s.db.clock.now.toIso8601String(),
      'effective_date': '2026-10-08',
    }, timestamps: false);
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _open(h, LegalTab.manualDeductions);
    final cut = tester.widget<MadarClippedText>(
      inCard('By reason', find.byType(MadarClippedText)).first,
    );
    expect(cut.maxLines, 1);
    expect(cut.overflow, TextOverflow.ellipsis);
    final row = tester.getSize(
      inCard('By reason', find.byType(MadarClippedText)).first,
    );
    expect(row.height, lessThan(30));
    await _open(h, LegalTab.deductionOverrides);
    final reason = tester.widget<Text>(
      inCard('History', find.text('Half of it: she called in sick late')),
    );
    expect(reason.maxLines, isNull);
    await _open(h, LegalTab.discounts);
    await auditMenu(h, 'Export Excel');
    expect(
      [for (final x in h.exports.built.single.sheets) x.name],
      ['By discount', 'By staff member'],
    );
    await h.flushTimers();
  });
}
