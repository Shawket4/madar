// Legal's nine audit tabs one by one (REP-LEG-028…036), with the reason
// wording (REP-LEG-022) and the Discounts extras (REP-LEG-023, 024).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/area_seed.dart' show isSold;
import 'package:dashboard_reports/src/legal/audit_cards.dart';
import 'package:dashboard_reports/src/legal/legal_words.dart';
import 'package:dashboard_reports/src/mock/legal_mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'legal_support.dart';

bool _inPeriod(Object? iso) {
  if (iso == null) return false;
  final at = DateTime.parse('$iso');
  return !at.isBefore(DateTime.parse(defaultFrom)) &&
      !at.isAfter(DateTime.parse(defaultTo));
}

Future<void> _open(DashHarness h, LegalTab tab) => tapTab(h, h.t(tab.labelKey));

/// The last request, checked against the tab's endpoint and the period.
void _asked(DashHarness h, String segment) {
  final c = legalCalls(h).last;
  expect(c.template, auditRoute(segment));
  expect(c.path, '/reports/orgs/${SeedIds.sabahOrg}/$segment');
  expect(c.query['from'], [defaultFrom]);
  expect(c.query['to'], [defaultTo]);
}

/// A sold Sabah order created in the default period at [branch].
MockRow _sold(MockDb db, String branch, {int skip = 0}) => db['orders'].rows
    .where(
      (o) =>
          o['branch_id'] == branch &&
          o['status'] == 'completed' &&
          _inPeriod(o['created_at']),
    )
    .skip(skip)
    .first;

/// The seed's discounted sales in the default period.
List<MockRow> _discounted(MockDb db) => [
  for (final o in db['orders'].rows)
    if (SeedIds.sabahBranches.contains(o['branch_id']) &&
        isSold(o) &&
        (o['discount_amount'] as num? ?? 0) > 0 &&
        _inPeriod(o['created_at']))
      o,
];

void main() {
  setUpAll(ensureTimeZones);

  testWidgets('REP-LEG-028 Refunds: refunds-audit; a person\'s own reason as '
      'typed, money, By reason', (tester) async {
    final s = legalServer();
    final a = _sold(s.db, SeedIds.heliopolis);
    final b = _sold(s.db, SeedIds.maadi);
    for (final (o, amount) in [(a, 5000), (b, 2500)]) {
      recordLegalRefund(
        s.db,
        orderId: o['id']! as String,
        amount: amount,
        reason: 'Cold drink',
        issuedBy: SeedIds.user('nour'),
        issuedAt: s.db.clock.now,
      );
    }
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _open(h, LegalTab.refunds);
    _asked(h, 'refunds-audit');
    expect(cardLabels(tester, 'By reason'), ['Cold drink']);
    expect(inCard('By reason', find.text('2 events')), findsOneWidget);
    expect(inCard('By reason', find.text('EGP 75.00')), findsOneWidget);
    expect(auditKpi(tester, 'amount').value, 7500);
    expect(cardLabels(tester, 'By staff member'), [userName(s.db, 'nour')]);
  });

  testWidgets('REP-LEG-029 / 022 Voids: void reason codes worded, never raw', (
    tester,
  ) async {
    final s = legalServer();
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _open(h, LegalTab.voids);
    _asked(h, 'voids-audit');
    final codes = <String, int>{};
    for (final o in s.db['orders'].rows) {
      if (o['status'] == 'voided' &&
          SeedIds.sabahBranches.contains(o['branch_id']) &&
          _inPeriod(o['voided_at'])) {
        final c = (o['void_reason'] as String?) ?? 'unspecified';
        codes[c] = (codes[c] ?? 0) + 1;
      }
    }
    expect(codes, isNotEmpty);
    final labels = cardLabels(tester, 'By reason');
    expect(labels.toSet(), {
      for (final c in codes.keys)
        c == 'unspecified'
            ? 'Not given'
            : const {
                'customer_request': 'Customer request',
                'wrong_order': 'Wrong order',
                'quality_issue': 'Quality issue',
                'other': 'Other',
              }[c],
    });
    for (final c in codes.keys) {
      expect(inAudit(find.text(c)), findsNothing, reason: c);
    }
    // Who voided: the branch managers.
    expect(
      cardLabels(tester, 'By staff member'),
      everyElement(
        isIn([
          for (final k in ['rana', 'tarek', 'dina', 'karim']) userName(s.db, k),
        ]),
      ),
    );
  });

  testWidgets('REP-LEG-022 Voids in Arabic: no English left', (tester) async {
    final h = await pumpLegal(tester, locale: 'ar');
    await _open(h, LegalTab.voids);
    final labels = cardLabels(tester, h.t('reports.legal.byReason'));
    expect(labels, isNotEmpty);
    for (final l in labels) {
      expect(l, isNot(matches(RegExp('[A-Za-z]'))), reason: l);
    }
  });

  testWidgets('REP-LEG-030 / 022 (divergence) Discounts: discounts-audit, By '
      'discount with a manual type worded, a named preset as named', (
    tester,
  ) async {
    final s = legalServer();
    final all = _discounted(s.db);
    expect(all.length, greaterThan(2));
    final preset = mockUuid('legal:preset:student');
    s.db[legalDiscountPresetsTable].insert({
      'id': preset,
      'name': 'Student 15%',
    }, timestamps: false);
    all.first['discount_id'] = preset;
    all.first['discount_kind'] = 'preset';
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _open(h, LegalTab.discounts);
    _asked(h, 'discounts-audit');
    expect(cardLabels(tester, 'By discount'), ['Percentage', 'Student 15%']);
    expect(inAudit(find.text('percentage')), findsNothing);
    expect(
      inCard('By discount', find.text('${all.length - 1} events')),
      findsOneWidget,
    );
    final money = all.fold<int>(
      0,
      (t, o) => t + (o['discount_amount'] as num).toInt(),
    );
    expect(auditKpi(tester, 'amount').value, money);
  });

  testWidgets('REP-LEG-023 Discounts: "By kind" (Tag), worded', (tester) async {
    final s = legalServer();
    final all = _discounted(s.db);
    all.first['discount_kind'] = null;
    all[1]['discount_kind'] = 'manual_amount';
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _open(h, LegalTab.discounts);
    expect(tester.widget<LegalCard>(auditCard('By kind')).icon, 'tag');
    expect(cardLabels(tester, 'By kind'), [
      'Percent by hand',
      'Amount by hand',
      'Not recorded',
    ]);
    expect(
      inCard('By kind', find.text('${all.length - 2} events')),
      findsOneWidget,
    );
    // No By kind card on the other tabs.
    await _open(h, LegalTab.voids);
    expect(auditCard('By kind'), findsNothing);
  });

  testWidgets('REP-LEG-024 Discounted sales: the newest 200; ref, kind, '
      'preset, percent, Flagged; branch · when · by · approved by; amount', (
    tester,
  ) async {
    final s = legalServer();
    final all = _discounted(s.db)
      ..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    final newest = all.first;
    final preset = mockUuid('legal:preset:student');
    s.db[legalDiscountPresetsTable].insert({
      'id': preset,
      'name': 'Student 12.5%',
    }, timestamps: false);
    newest['discount_id'] = preset;
    newest['discount_kind'] = 'preset';
    newest['discount_approved_by_name'] = userName(s.db, 'nour');
    newest['discount_percent_bps'] = 1250;
    flagLegalDiscount(s.db, newest['id']! as String);
    all[1]['order_ref'] = null;
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _open(h, LegalTab.discounts);
    final card = tester.widget<DiscountEntriesCard>(
      find.byType(DiscountEntriesCard),
    );
    // The newest 200 sales (the server's LIMIT 200).
    expect(all.length, greaterThan(200));
    expect(card.entries, hasLength(200));
    expect(card.entries.first.orderId, newest['id']);
    final f = fmtOf(h);
    final ref = newest['order_ref']! as String;
    expect(inCard('Discounted sales', find.text(ref)), findsOneWidget);
    expect(inCard('Discounted sales', find.text('12.5%')), findsOneWidget);
    expect(inCard('Discounted sales', find.text('Preset')), findsOneWidget);
    expect(
      inCard('Discounted sales', find.text('Student 12.5%')),
      findsOneWidget,
    );
    expect(inCard('Discounted sales', find.text('Flagged')), findsOneWidget);
    final badge = tester.widget<DashBadge>(
      inCard('Discounted sales', find.byType(DashBadge)),
    );
    expect(badge.tone, DashTone.danger);
    final branch = s.db['branches'].get(newest['branch_id']! as String)['name'];
    final by = s.db['users'].get(
      newest['discount_applied_by']! as String,
    )['name'];
    expect(
      inCard(
        'Discounted sales',
        find.text(
          '$branch · ${f.fmtDateTime('${newest['created_at']}')} · by $by · '
          'approved by ${userName(s.db, 'nour')}',
        ),
      ),
      findsOneWidget,
    );
    expect(
      inCard(
        'Discounted sales',
        find.text(f.fmtMoney((newest['discount_amount'] as num).toInt())),
      ),
      findsWidgets,
    );
    // No ref: the first 8 characters of the order id.
    expect(
      inCard(
        'Discounted sales',
        find.text((all[1]['id']! as String).substring(0, 8)),
      ),
      findsOneWidget,
    );
    expect(
      inCard('Discounted sales', find.text('Percent by hand')),
      findsNWidgets(199),
    );
    expect(inCard('Discounted sales', find.text('10%')), findsNWidgets(199));
    await h.shot('legal/discounts');
  });

  testWidgets('REP-LEG-031 Waivers: waivers-audit, By branch, money', (
    tester,
  ) async {
    final s = legalServer();
    for (final (b, amount) in [
      (SeedIds.zamalek, 1500),
      (SeedIds.zamalek, 900),
      (SeedIds.maadi, 1200),
    ]) {
      waiveLegalServiceCharge(
        s.db,
        orderId: _sold(s.db, b, skip: amount == 900 ? 1 : 0)['id']! as String,
        amount: amount,
        by: SeedIds.user(b == SeedIds.zamalek ? 'karim' : 'tarek'),
        at: s.db.clock.now,
      );
    }
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _open(h, LegalTab.waivers);
    _asked(h, 'waivers-audit');
    expect(cardLabels(tester, 'By branch'), ['Zamalek', 'Maadi']);
    expect(inCard('By branch', find.text('EGP 24.00')), findsOneWidget);
    expect(inCard('By branch', find.text('EGP 12.00')), findsOneWidget);
    expect(auditKpi(tester, 'amount').value, 3600);
    expect(cardLabels(tester, 'By staff member'), [
      userName(s.db, 'karim'),
      userName(s.db, 'tarek'),
    ]);
  });

  testWidgets('REP-LEG-032 Price overrides: price-overrides, By branch, the '
      'sale\'s money', (tester) async {
    final s = legalServer();
    final o = _sold(s.db, SeedIds.newCairo);
    flagLegalPrice(s.db, o['id']! as String);
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _open(h, LegalTab.priceOverrides);
    _asked(h, 'price-overrides');
    expect(cardLabels(tester, 'By branch'), ['New Cairo']);
    expect(inCard('By branch', find.text('1 event')), findsOneWidget);
    expect(auditKpi(tester, 'amount').value, o['total_amount']);
  });

  testWidgets('REP-LEG-033 Manual deductions: manual-deductions-audit, By '
      'reason as typed, money', (tester) async {
    final h = await pumpLegal(tester);
    await _open(h, LegalTab.manualDeductions);
    _asked(h, 'manual-deductions-audit');
    expect(auditKpi(tester, 'count').value, 6);
    expect(cardLabels(tester, 'By reason').first, 'Broken glassware');
  });

  testWidgets('REP-LEG-034 / 022 Deduction overrides: By type worded '
      '"Overridden" / "Waived", plus History', (tester) async {
    final h = await pumpLegal(tester);
    await _open(h, LegalTab.deductionOverrides);
    _asked(h, 'deduction-overrides-audit');
    expect(cardLabels(tester, 'By type'), ['Overridden', 'Waived']);
    expect(inAudit(find.text('overridden')), findsNothing);
    expect(inCard('By type', find.text('EGP 265.00')), findsOneWidget);
    expect(inCard('By type', find.text('EGP 70.00')), findsOneWidget);
    expect(auditKpi(tester, 'amount').value, 33500);
    expect(auditCard('History'), findsOneWidget);
  });

  testWidgets('REP-LEG-035 / 022 (divergence) Loyalty adjustments: points, '
      'By branch, an adjustment away from any branch worded "Not given"', (
    tester,
  ) async {
    final h = await pumpLegal(tester);
    await _open(h, LegalTab.loyaltyAdjustments);
    _asked(h, 'loyalty-adjustments-audit');
    expect(cardLabels(tester, 'By branch'), [
      'Zamalek',
      'Heliopolis',
      'Maadi',
      'New Cairo',
      'Not given',
    ]);
    expect(inAudit(find.text('unspecified')), findsNothing);
    expect(inCard('By branch', find.text('60')), findsOneWidget);
  });

  testWidgets('REP-LEG-036 / 022 Attendance corrections: the server\'s '
      'reasons worded, people\'s kept, no amount', (tester) async {
    final h = await pumpLegal(tester);
    await _open(h, LegalTab.attendanceCorrections);
    _asked(h, 'attendance-corrections-audit');
    final labels = cardLabels(tester, 'By reason');
    expect(labels.first, 'Approved correction request');
    expect(
      labels,
      containsAll([
        'Closed automatically: no check-out',
        'Marked absent automatically: no check-in',
        'Not given',
        'Phone battery died at check-in',
        'Forgot to clock out after closing',
      ]),
    );
    expect(
      inAudit(find.text('Auto-closed: no checkout recorded')),
      findsNothing,
    );
    expect(inAudit(find.textContaining('EGP')), findsNothing);
  });

  testWidgets('REP-LEG-036 / 022 Attendance in Arabic: codes worded, a '
      'person\'s English words kept as typed', (tester) async {
    final h = await pumpLegal(tester, locale: 'ar', dark: true);
    await _open(h, LegalTab.attendanceCorrections);
    final labels = cardLabels(tester, h.t('reports.legal.byReason'));
    expect(labels.first, h.t('reports.legal.reason.correction_request'));
    expect(labels, contains('Phone battery died at check-in'));
    expect(labels, contains(h.t('reports.legal.reason.unspecified')));
  });
}
