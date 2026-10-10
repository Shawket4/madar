// The Legal mock handlers against figures computed by hand from the seed,
// and the backend's gates (`legal::guard` / `guard_with`), scoping and
// errors (SPEC 3.2).
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_reports/src/mock/legal_mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'legal_support.dart';

const List<String> _audits = [
  'refunds-audit',
  'voids-audit',
  'discounts-audit',
  'waivers-audit',
  'price-overrides',
  'manual-deductions-audit',
  'deduction-overrides-audit',
  'loyalty-adjustments-audit',
  'attendance-corrections-audit',
];

Map<String, List<String>> _range([
  String from = defaultFrom,
  String to = defaultTo,
]) => {
  'from': [from],
  'to': [to],
};

Future<ApiResponse> _get(
  MockServer s,
  String org,
  String segment, {
  Map<String, List<String>>? query,
}) => s.send(
  ApiRequest(
    method: 'GET',
    path: '/reports/orgs/$org/$segment',
    query: query ?? _range(),
  ),
);

Future<ApiException> _refused(Future<ApiResponse> f) async {
  try {
    final r = await f;
    fail('expected a refusal, got ${r.status}');
  } on ApiException catch (e) {
    return e;
  }
}

Map<String, dynamic> _json(ApiResponse r) =>
    jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

Future<AuditReport> _audit(
  MockServer s,
  String segment, {
  String org = '',
  Map<String, List<String>>? query,
}) async => AuditReport.fromJson(
  _json(
    await _get(s, org.isEmpty ? SeedIds.sabahOrg : org, segment, query: query),
  ),
);

List<(String, int, int)> _rows(List<AuditBreakdownEntry> rows) => [
  for (final r in rows) (r.label, r.count, r.amountMinor),
];

void main() {
  group('gates', () {
    test('every read needs reports.legal (limited: 403)', () async {
      final s = legalServer(persona: Persona.limited).server;
      for (final seg in ['tax', ..._audits]) {
        final e = await _refused(_get(s, SeedIds.sabahOrg, seg));
        expect(e.status, 403, reason: seg);
      }
    });

    test('the payroll audits need hr.payroll.read; attendance '
        'hr.attendance.read (a manager holds only the second)', () async {
      final s = legalServer(persona: Persona.manager).server;
      for (final seg in [
        'manual-deductions-audit',
        'deduction-overrides-audit',
      ]) {
        final e = await _refused(_get(s, SeedIds.sabahOrg, seg));
        expect(e.status, 403, reason: seg);
      }
      final ok = await _get(
        s,
        SeedIds.sabahOrg,
        'attendance-corrections-audit',
      );
      expect(ok.status, 200);
    });

    test(
      'another org is refused; an unknown org is a 404 (platform)',
      () async {
        final owner = legalServer().server;
        expect(
          (await _refused(
            _get(owner, SeedIds.nakhlaOrg, 'voids-audit'),
          )).status,
          403,
        );
        final platform = legalServer(persona: Persona.platform).server;
        final r = await _get(
          platform,
          SeedIds.nakhlaOrg,
          'manual-deductions-audit',
        );
        expect(r.status, 200);
        expect(
          (await _refused(
            _get(platform, mockUuid('legal:no-such-org'), 'voids-audit'),
          )).status,
          404,
        );
      },
    );
  });

  group('figures', () {
    test('manual deductions: the period\'s six, by reason as typed', () async {
      final s = legalServer().server;
      final d = await _audit(s, 'manual-deductions-audit');
      expect(d.totalCount, 6);
      expect(d.totalAmountMinor, 7500 + 12000 + 4500 + 25000 + 5000);
      expect(_rows(d.byReason), [
        ('Broken glassware', 2, 12500),
        ('Cash shortage at close', 2, 16500),
        ('Late for opening, third time this month', 1, 0),
        ('Uniform not returned', 1, 25000),
      ]);
      for (final r in d.byReason) {
        expect(r.code, isNull);
      }
      expect(_rows(d.byIssuer), [('Nour El-Sayed', 6, 54000)]);
    });

    test('a narrower period narrows the report', () async {
      final s = legalServer().server;
      // 1 Oct (Cairo): Omar's cash shortage only.
      final d = await _audit(
        s,
        'manual-deductions-audit',
        query: _range('2026-09-30T21:00:00.000Z', '2026-10-01T20:59:59.999Z'),
      );
      expect(d.totalCount, 1);
      expect(_rows(d.byReason), [('Cash shortage at close', 1, 4500)]);
    });

    test('deduction overrides: forgiven amounts by type, the history newest '
        'first with the amounts each act moved', () async {
      final s = legalServer().server;
      final d = await _audit(s, 'deduction-overrides-audit');
      expect(d.totalCount, 5);
      expect(d.totalAmountMinor, 10000 + 3000 + 15000 + 4000 + 1500);
      expect(_rows(d.byReason), [
        ('overridden', 3, 26500),
        ('waived', 2, 7000),
      ]);
      expect(d.byReason.every((r) => r.code == null), isTrue);
      final h = d.history!;
      expect(
        [for (final e in h) e.action],
        [
          'override',
          'waive',
          'waive',
          'override',
          'unwaive',
          'override',
          'waive',
        ],
      );
      for (var i = 1; i < h.length; i++) {
        expect(h[i - 1].at.isBefore(h[i].at), isFalse);
      }
      final unwaive = h[4];
      expect(unwaive.amountBeforePiastres, 0);
      expect(unwaive.amountAfterPiastres, 5000);
      expect(unwaive.effectiveDate, '2026-09-18');
      expect(unwaive.actorName, 'Nour El-Sayed');
      expect(h.first.amountBeforePiastres, 2500);
      expect(h.first.amountAfterPiastres, 1000);
    });

    test('loyalty adjustments: manual adjustments only, points by size, by '
        'branch with "unspecified" for none', () async {
      final s = legalServer().server;
      final d = await _audit(s, 'loyalty-adjustments-audit');
      expect(d.totalCount, 7);
      expect(d.totalAmountMinor, 325);
      expect(_rows(d.byReason), [
        ('Zamalek', 3, 100),
        ('Heliopolis', 1, 25),
        ('Maadi', 1, 40),
        ('New Cairo', 1, 60),
        ('unspecified', 1, 100),
      ]);
    });

    test('attendance corrections: edited by a person, server reasons coded, '
        'no amount', () async {
      final s = legalServer().server;
      final d = await _audit(s, 'attendance-corrections-audit');
      expect(d.totalCount, 11);
      expect(d.totalAmountMinor, 0);
      final byLabel = {for (final r in d.byReason) r.label: r};
      expect(byLabel['Approved punch correction request']!.count, 3);
      expect(
        byLabel['Approved punch correction request']!.code,
        'correction_request',
      );
      expect(byLabel['Auto-closed: no checkout recorded']!.code, 'auto_closed');
      expect(
        byLabel['Marked automatically: no check-in']!.code,
        'marked_absent',
      );
      expect(byLabel['unspecified']!.code, 'unspecified');
      expect(byLabel['Phone battery died at check-in']!.code, isNull);
      expect(_rows(d.byIssuer).first, ('Karim Adel', 5, 0));
    });

    test('voids: coded reasons, the managers who voided, money', () async {
      final s = legalServer();
      final d = await _audit(s.server, 'voids-audit');
      final voids = [
        for (final o in s.db['orders'].rows)
          if (o['status'] == 'voided' &&
              SeedIds.sabahBranches.contains(o['branch_id']) &&
              '${o['voided_at']}'.compareTo(defaultFrom) >= 0 &&
              '${o['voided_at']}'.compareTo(defaultTo) <= 0)
            o,
      ];
      expect(d.totalCount, voids.length);
      expect(
        d.totalAmountMinor,
        voids.fold<int>(0, (t, o) => t + (o['total_amount'] as num).toInt()),
      );
      for (final r in d.byReason) {
        expect(r.code, r.label);
      }
      expect(d.byReason.fold<int>(0, (t, r) => t + r.count), voids.length);
    });

    test('discounts: by discount, by kind, and the newest 200 sales', () async {
      final s = legalServer();
      final d = await _audit(s.server, 'discounts-audit');
      expect(d.byReason.single.label, 'percentage');
      expect(d.byReason.single.code, 'percentage');
      expect(d.byKind!.single.label, 'manual_percent');
      expect(d.byKind!.single.count, d.totalCount);
      expect(d.entries, hasLength(200));
      expect(
        d.entries!.first.createdAt.isAfter(d.entries!.last.createdAt),
        isTrue,
      );
      expect(d.entries!.every((e) => e.percentBps == 1000), isTrue);
      expect(d.entries!.any((e) => e.flagged), isFalse);
    });

    test(
      'refunds, waivers and price overrides follow what is recorded',
      () async {
        final s = legalServer();
        for (final seg in [
          'refunds-audit',
          'waivers-audit',
          'price-overrides',
        ]) {
          expect((await _audit(s.server, seg)).totalCount, 0, reason: seg);
        }
        final o = s.db['orders'].rows.firstWhere(
          (o) =>
              o['branch_id'] == SeedIds.maadi &&
              o['status'] == 'completed' &&
              '${o['created_at']}'.compareTo(defaultFrom) > 0,
        );
        final id = o['id']! as String;
        recordLegalRefund(
          s.db,
          orderId: id,
          amount: 2280,
          reason: 'Wrong size',
          issuedBy: SeedIds.user('tarek'),
          issuedAt: s.db.clock.now,
        );
        waiveLegalServiceCharge(
          s.db,
          orderId: id,
          amount: 700,
          by: SeedIds.user('tarek'),
          at: s.db.clock.now,
        );
        flagLegalPrice(s.db, id);
        final refunds = await _audit(s.server, 'refunds-audit');
        expect(_rows(refunds.byReason), [('Wrong size', 1, 2280)]);
        expect(_rows(refunds.byIssuer), [('Tarek Saber', 1, 2280)]);
        final waivers = await _audit(s.server, 'waivers-audit');
        expect(_rows(waivers.byReason), [('Maadi', 1, 700)]);
        final prices = await _audit(s.server, 'price-overrides');
        expect(_rows(prices.byReason), [
          ('Maadi', 1, (o['total_amount'] as num).toInt()),
        ]);
        // The refund's tax at 14% inclusive: 2280 × 0.14 / 1.14 = 280.
        final tax = TaxReport.fromJson(
          _json(await _get(s.server, SeedIds.sabahOrg, 'tax')),
        );
        expect(tax.refundedTax, 280);
      },
    );
  });

  group('a manager sees their own branches', () {
    test('attendance and loyalty: Zamalek only', () async {
      final s = legalServer(persona: Persona.manager).server;
      final att = await _audit(s, 'attendance-corrections-audit');
      expect(att.totalCount, 5);
      expect(_rows(att.byIssuer), [('Karim Adel', 5, 0)]);
      final loy = await _audit(s, 'loyalty-adjustments-audit');
      expect(_rows(loy.byReason), [('Zamalek', 3, 100)]);
    });

    test('tax: Zamalek\'s orders only', () async {
      final s = legalServer(persona: Persona.manager);
      final mine = TaxReport.fromJson(
        _json(await _get(s.server, SeedIds.sabahOrg, 'tax')),
      );
      final all = TaxReport.fromJson(
        _json(await _get(legalServer().server, SeedIds.sabahOrg, 'tax')),
      );
      expect(mine.taxCollected, greaterThan(0));
      expect(mine.taxCollected, lessThan(all.taxCollected));
      var tax = 0;
      for (final o in s.db['orders'].rows) {
        if (o['branch_id'] != SeedIds.zamalek || o['status'] == 'voided') {
          continue;
        }
        final at = '${o['created_at']}';
        if (at.compareTo(defaultFrom) < 0 || at.compareTo(defaultTo) > 0) {
          continue;
        }
        tax += (o['tax_amount'] as num? ?? 0).toInt();
      }
      expect(mine.taxCollected, tax);
    });
  });

  test('Nakhla Bakery (Dawam only): its own deductions', () async {
    final s = legalServer(persona: Persona.dawamOnly).server;
    final manual = await _audit(
      s,
      'manual-deductions-audit',
      org: SeedIds.nakhlaOrg,
    );
    expect(manual.totalCount, 2);
    expect(manual.totalAmountMinor, 15000 + 3500);
    final over = await _audit(
      s,
      'deduction-overrides-audit',
      org: SeedIds.nakhlaOrg,
    );
    expect(_rows(over.byReason), [
      ('overridden', 1, 9000),
      ('waived', 1, 4000),
    ]);
    expect(over.history, hasLength(2));
  });
}
