// Legal page: the gate, the tabs (modules and extra capabilities), the
// header, and which report is asked for (REP-LEG-001…007, 037).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_reports/src/legal/legal_words.dart';
import 'package:flutter_test/flutter_test.dart';

import 'legal_support.dart';

List<String> _labels(DashHarness h, Iterable<LegalTab> tabs) => [
  for (final t in tabs) h.t(t.labelKey),
];

void main() {
  testWidgets('REP-LEG-001 without reports.legal: Restricted "Legal", no '
      'tabs, nothing asked (shell gate)', (tester) async {
    final h = await pumpLegal(tester, persona: Persona.limited);
    expect(find.text(h.t('reports.legal.title')), findsWidgets);
    expect(find.text(h.t('common.restrictedTitle')), findsOneWidget);
    expect(legalStrip, findsNothing);
    expect(legalCalls(h), isEmpty);
  });

  testWidgets('REP-LEG-001 the page\'s own Restricted says the reports\' '
      'words', (tester) async {
    final h = await pumpLegal(tester, persona: Persona.limited, ownGate: true);
    expect(find.text(h.t('reports.legal.title')), findsWidgets);
    expect(find.text(h.t('common.restrictedTitle')), findsOneWidget);
    expect(find.text(h.t('reports.noAccess')), findsOneWidget);
    expect(legalStrip, findsNothing);
    expect(legalCalls(h), isEmpty);
    await h.shot('legal/restricted');
  });

  testWidgets('REP-LEG-001 the page\'s own gate opens for reports.legal', (
    tester,
  ) async {
    final h = await pumpLegal(tester, ownGate: true);
    expect(find.text(h.t('reports.noAccess')), findsNothing);
    expect(legalStrip, findsOneWidget);
    expect(h.server.callsTo(taxRoute), hasLength(1));
  });

  testWidgets('REP-LEG-001 Restricted in Arabic', (tester) async {
    final h = await pumpLegal(
      tester,
      persona: Persona.limited,
      ownGate: true,
      locale: 'ar',
      size: DashSize.phone,
    );
    expect(find.text('قانوني'), findsWidgets);
    expect(find.text(h.t('reports.noAccess')), findsOneWidget);
    await h.shot('legal/restricted');
  });

  testWidgets('REP-LEG-002 the tab strip, in the web\'s order', (tester) async {
    final h = await pumpLegal(tester);
    expect(tabLabels(h), _labels(h, LegalTab.values));
    expect(tabLabels(h), [
      'Tax',
      'Refunds',
      'Voids',
      'Discounts',
      'Waivers',
      'Price overrides',
      'Manual deductions',
      'Deduction overrides',
      'Loyalty adjustments',
      'Attendance corrections',
    ]);
  });

  testWidgets('REP-LEG-002 the tab strip in Arabic', (tester) async {
    final h = await pumpLegal(tester, locale: 'ar');
    expect(tabLabels(h), _labels(h, LegalTab.values));
    expect(tabLabels(h).first, 'الضريبة');
    // Right to left: the first tab sits on the right.
    final tax = tester.getCenter(tabText('الضريبة'));
    final refunds = tester.getCenter(tabText('المبالغ المستردة'));
    expect(tax.dx, greaterThan(refunds.dx));
  });

  testWidgets('REP-LEG-003 a manager: no payroll tabs, attendance kept; '
      'hidden tabs are never asked', (tester) async {
    final h = await pumpLegal(tester, persona: Persona.manager);
    final labels = tabLabels(h);
    expect(labels, isNot(contains(h.t(LegalTab.manualDeductions.labelKey))));
    expect(labels, isNot(contains(h.t(LegalTab.deductionOverrides.labelKey))));
    expect(labels, contains(h.t(LegalTab.attendanceCorrections.labelKey)));
    expect(labels, contains(h.t(LegalTab.loyaltyAdjustments.labelKey)));
    for (final t in labels) {
      await tapTab(h, t);
    }
    final asked = {for (final c in legalCalls(h)) c.template};
    expect(asked, isNot(contains(auditRoute('manual-deductions-audit'))));
    expect(asked, isNot(contains(auditRoute('deduction-overrides-audit'))));
    expect(asked, contains(auditRoute('attendance-corrections-audit')));
    expect(legalCalls(h).every((c) => c.status == 200), isTrue);
  });

  testWidgets('REP-LEG-003 without hr.attendance.read the attendance tab '
      'goes too', (tester) async {
    final s = legalServer();
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    // The owner's grants lose attendance: refresh what they may do.
    final caps = (h.server.persona.capabilities.toSet()
      ..remove(Cap.hrAttendanceRead));
    h.server.on('GET', '/authz/me', (req) {
      return MockResponse.ok({
        'user_id': req.persona.userId,
        'capabilities': caps.toList(),
        'everywhere': caps.toList(),
        'ask_manager': <String>[],
        'limits': <String, Object?>{},
        'owner': false,
        'platform': false,
        'role_kinds': ['org_admin'],
        'epoch': 2,
        'spec_version': 2,
      });
    });
    await h.container.read(authzProvider.notifier).refresh();
    await h.settle();
    expect(
      tabLabels(h),
      isNot(contains(h.t(LegalTab.attendanceCorrections.labelKey))),
    );
    expect(tabLabels(h), contains(h.t(LegalTab.manualDeductions.labelKey)));
  });

  testWidgets('REP-LEG-004 a Dawam-only org: the three pay and attendance '
      'tabs, the first selected, no till report asked', (tester) async {
    final h = await pumpLegal(tester, persona: Persona.dawamOnly);
    expect(
      tabLabels(h),
      _labels(h, const [
        LegalTab.manualDeductions,
        LegalTab.deductionOverrides,
        LegalTab.attendanceCorrections,
      ]),
    );
    final asked = [for (final c in legalCalls(h)) c.template];
    expect(asked, [auditRoute('manual-deductions-audit')]);
    // Its own org's figures.
    expect(legalCalls(h).single.path, contains(SeedIds.nakhlaOrg));
    expect(find.text('Damaged baking trays'), findsOneWidget);
  });

  testWidgets('REP-LEG-004 a POS-only org loses the three Dawam tabs', (
    tester,
  ) async {
    final s = legalServer();
    s.db['orgs'].update(SeedIds.sabahOrg, {
      'modules': ['pos'],
    });
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    expect(
      tabLabels(h),
      _labels(h, [
        for (final t in LegalTab.values)
          if (t.module == OrgModule.pos) t,
      ]),
    );
    for (final t in tabLabels(h)) {
      await tapTab(h, t);
    }
    final asked = {for (final c in legalCalls(h)) c.template};
    expect(asked, isNot(contains(auditRoute('manual-deductions-audit'))));
    expect(asked, isNot(contains(auditRoute('attendance-corrections-audit'))));
  });

  testWidgets('REP-LEG-005 Tax first; a picked tab that disappears falls back '
      'to the first visible one', (tester) async {
    final s = legalServer();
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    expect(h.server.callsTo(taxRoute), hasLength(1));
    await tapTab(h, h.t(LegalTab.attendanceCorrections.labelKey));
    expect(
      h.server.callsTo(auditRoute('attendance-corrections-audit')),
      hasLength(1),
    );
    // Dawam is switched off while the page is open.
    s.db['orgs'].update(SeedIds.sabahOrg, {
      'modules': ['pos'],
    });
    h.container.invalidate(orgModulesQueryProvider);
    await h.settle();
    expect(tabText(h.t(LegalTab.attendanceCorrections.labelKey)), findsNothing);
    // Back on Tax: its report is still fresh (< 30 s), shown from the cache
    // without a second request, as the web's staleTime does.
    expect(h.server.callsTo(taxRoute), hasLength(1));
    expect(find.text(h.t('analytics.tax.taxableSales')), findsOneWidget);
  });

  testWidgets('REP-LEG-005 no tab visible: the header alone', (tester) async {
    final s = legalServer();
    s.db['orgs'].update(SeedIds.sabahOrg, {'modules': <String>[]});
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    expect(find.text(h.t('reports.legal.title')), findsWidgets);
    expect(find.text(h.t('scope.preset.30d')), findsWidgets);
    expect(legalStrip, findsNothing);
    expect(legalCalls(h), isEmpty);
  });

  testWidgets('REP-LEG-006 header: "Legal" and the period', (tester) async {
    final h = await pumpLegal(tester);
    expect(find.text('Legal'), findsWidgets);
    expect(find.text('Last 30 days'), findsWidgets);
    await h.container
        .read(scopeProvider.notifier)
        .setPreset(ScopePreset.last7Days);
    await h.settle();
    expect(find.text('Last 7 days'), findsWidgets);
    // A new period asks again, with its own range.
    final last = h.server.callsTo(taxRoute).last;
    expect(last.query['from'], ['2026-10-01T21:00:00.000Z']);
  });

  testWidgets('REP-LEG-007 only the active tab is asked, with from/to', (
    tester,
  ) async {
    final h = await pumpLegal(tester);
    expect(legalCalls(h), hasLength(1));
    final tax = legalCalls(h).single;
    expect(tax.path, '/reports/orgs/${SeedIds.sabahOrg}/tax');
    expect(tax.query['from'], [defaultFrom]);
    expect(tax.query['to'], [defaultTo]);
    await tapTab(h, 'Voids');
    expect(legalCalls(h), hasLength(2));
    final voids = legalCalls(h).last;
    expect(voids.template, auditRoute('voids-audit'));
    expect(voids.query['from'], [defaultFrom]);
    expect(voids.query['to'], [defaultTo]);
    // The branch picker does not change an org-wide report's question.
    expect(voids.query.containsKey('branch_id'), isFalse);
  });

  testWidgets('REP-LEG-007 the server narrows a manager to their branches', (
    tester,
  ) async {
    final h = await pumpLegal(tester, persona: Persona.manager);
    await tapTab(h, 'Voids');
    final voidsAt = [
      for (final o in h.db!['orders'].rows)
        if (o['status'] == 'voided' &&
            o['branch_id'] == SeedIds.zamalek &&
            '${o['voided_at']}'.compareTo(defaultFrom) >= 0 &&
            '${o['voided_at']}'.compareTo(defaultTo) <= 0)
          o,
    ];
    expect(voidsAt, isNotEmpty);
    expectAnyText(numberForms(fmtOf(h), voidsAt.length));
    expect(find.text('Karim Adel'), findsOneWidget);
    expect(find.text('Tarek Saber'), findsNothing);
  });

  testWidgets('REP-LEG-037 until the modules answer: no tabs, nothing asked', (
    tester,
  ) async {
    final s = legalServer();
    final gate = s.server.hold('GET', '/orgs/{id}/modules');
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    expect(find.text('Legal'), findsWidgets);
    expect(legalStrip, findsNothing);
    expect(legalCalls(h), isEmpty);
    gate.release();
    await h.settle();
    expect(legalStrip, findsOneWidget);
    expect(h.server.callsTo(taxRoute), hasLength(1));
  });

  testWidgets('REP-LEG-037 a failed modules read leaves the header alone: no '
      'error, no Retry', (tester) async {
    final s = legalServer();
    s.server.fail(
      'GET',
      '/orgs/{id}/modules',
      MockResponse.error(500, 'Internal error'),
      times: null,
    );
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    expect(find.text('Legal'), findsWidgets);
    expect(legalStrip, findsNothing);
    expect(find.text(h.t('common.retry')), findsNothing);
    expect(legalCalls(h), isEmpty);
  });

  testWidgets('REP-LEG-037 a platform admin with no org: every tab, the Tax '
      'skeleton, nothing asked', (tester) async {
    final h = await pumpLegal(tester, persona: Persona.platform);
    expect(tabLabels(h), _labels(h, LegalTab.values));
    expect(legalCalls(h), isEmpty);
    expect(find.text(h.t('reports.legal.noVat')), findsNothing);
    expect(find.text(h.t('analytics.tax.taxableSales')), findsNothing);
    await tapTab(h, 'Voids');
    expect(legalCalls(h), isEmpty);
    expect(find.text(h.t('reports.legal.empty')), findsOneWidget);
  });

  testWidgets('REP-LEG-007 a till event refetches the active report '
      '(a branch selected)', (tester) async {
    final h = await pumpLegal(tester);
    await h.container
        .read(scopeProvider.notifier)
        .setBranch(SeedIds.heliopolis);
    await h.settle();
    final before = h.server.callsTo(taxRoute).length;
    h.realtime.current!.emit('till.closed', data: '{}');
    await h.settle();
    expect(h.server.callsTo(taxRoute).length, before + 1);
  });
}
