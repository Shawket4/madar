/// The mock backend for Legal (REP-LEG): the org tax report and the nine
/// audit reports, as MadarRust `reports/legal.rs` and `org_tax_report`
/// answer them.
///
/// - Every read needs `reports.legal` (403 in the backend's envelope) and
///   the caller's own org (a platform admin may read any); the payroll
///   audits also need `hr.payroll.read`, attendance corrections
///   `hr.attendance.read`. An unknown org is a 404.
/// - A branch-bound caller (a manager) gets only their branches: orders,
///   refunds, loyalty and attendance by their branch; deductions by the
///   branches the employee works at.
/// - Tax, Voids, Discounts, Waivers and Price overrides are computed from
///   the core seed's orders (the same sold set as `../area_seed.dart`, so
///   Legal › Tax agrees with Operations and Tills). The seed's orders carry
///   no refunds, no waived service charge and no price flag, so those three
///   tabs are empty until a test records some ([recordLegalRefund],
///   [waiveLegalServiceCharge], [flagLegalPrice]); a recorded refund is
///   netted by the Tax report too.
/// - Manual deductions, deduction overrides (with their audit log), manual
///   loyalty adjustments and attendance corrections are this unit's own
///   tables (`legal_*`), for Sabah Coffee and Nakhla Bakery.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import '../area_seed.dart' show isSold, summarizeSales;

// ── tables ────────────────────────────────────────────────────────────────

/// Refunds against orders (`order_refunds`).
const String legalRefundsTable = 'legal_refunds';

/// Payroll deductions (`payroll_deductions`).
const String legalDeductionsTable = 'legal_payroll_deductions';

/// The money audit log of deduction waives / unwaives / overrides
/// (`payroll_audit_log`).
const String legalPayrollLogTable = 'legal_payroll_audit_log';

/// Loyalty ledger rows (`loyalty_transactions`).
const String legalLoyaltyTable = 'legal_loyalty_transactions';

/// Attendance records someone edited after the fact (`attendance_records`).
const String legalAttendanceTable = 'legal_attendance_records';

/// Order ids the server flagged for a discount replayed without the right
/// (`authz_replay_flags`, `orders.discount.*`).
const String legalDiscountFlagsTable = 'legal_discount_flags';

/// Named discount presets an order's `discount_id` may point at, when no
/// area has loaded `discounts`.
const String legalDiscountPresetsTable = 'legal_discount_presets';

DateTime _cairo(int m, int d, [int h = 12, int mi = 0]) =>
    MockClock.fromCairo(2026, m, d, h, mi);

String _u(String key) => SeedIds.user(key);
String _e(String key) => SeedIds.employee(key);

// ── seed: payroll ─────────────────────────────────────────────────────────

/// A deduction row.
MockRow _deduction(
  String key, {
  required String org,
  required String employee,
  required String source,
  required String? reason,
  required int? amount,
  required DateTime createdAt,
  required String createdBy,
  String? effectiveDate,
  String? reasonCode,
  int? original,
  DateTime? waivedAt,
  String? waivedBy,
  DateTime? overriddenAt,
  String? overriddenBy,
}) => {
  'id': mockUuid('legal:deduction:$key'),
  'org_id': org,
  'employee_id': _e(employee),
  'source': source,
  'reason': reason,
  'reason_code': reasonCode,
  'amount_piastres': amount,
  'original_amount_piastres': original,
  'created_by': createdBy,
  'created_at': createdAt.toIso8601String(),
  'effective_date': effectiveDate,
  'waived_at': waivedAt?.toIso8601String(),
  'waived_by': waivedBy,
  'overridden_at': overriddenAt?.toIso8601String(),
  'overridden_by': overriddenBy,
};

List<MockRow> _deductions() {
  final sabah = SeedIds.sabahOrg;
  final nakhla = SeedIds.nakhlaOrg;
  final nour = _u('nour');
  final yasmin = SeedIds.dawamOwner;
  MockRow manual(
    String key,
    String org,
    String employee,
    String reason,
    int? amount,
    DateTime at,
    String by,
  ) => _deduction(
    key,
    org: org,
    employee: employee,
    source: 'manual',
    reason: reason,
    amount: amount,
    original: amount,
    createdAt: at,
    createdBy: by,
    effectiveDate: MockClock.cairoDate(at),
  );
  return [
    // Operator-entered deductions.
    manual(
      'm1',
      sabah,
      'youssef',
      'Broken glassware',
      7500,
      _cairo(9, 14, 16, 20),
      nour,
    ),
    manual(
      'm2',
      sabah,
      'ziad',
      'Cash shortage at close',
      12000,
      _cairo(9, 22, 23, 40),
      nour,
    ),
    manual(
      'm3',
      sabah,
      'omar',
      'Cash shortage at close',
      4500,
      _cairo(10, 1, 23, 25),
      nour,
    ),
    manual(
      'm4',
      sabah,
      'farida',
      'Uniform not returned',
      25000,
      _cairo(9, 29, 12),
      nour,
    ),
    // A percentage deduction: counted, adds no amount.
    manual(
      'm5',
      sabah,
      'adham',
      'Late for opening, third time this month',
      null,
      _cairo(10, 4, 10, 15),
      nour,
    ),
    manual(
      'm6',
      sabah,
      'mariam',
      'Broken glassware',
      5000,
      _cairo(10, 6, 18, 5),
      nour,
    ),
    // Before the default period.
    manual(
      'm7',
      sabah,
      'ali',
      'Cash shortage at close',
      6000,
      _cairo(8, 25, 23, 10),
      nour,
    ),
    manual(
      'm8',
      nakhla,
      'hamza',
      'Damaged baking trays',
      15000,
      _cairo(9, 18, 14),
      yasmin,
    ),
    manual(
      'm9',
      nakhla,
      'malak',
      'Cash shortage at close',
      3500,
      _cairo(10, 3, 21, 30),
      yasmin,
    ),
    // Automatic deductions a manager later waived or overrode.
    _deduction(
      'a1',
      org: sabah,
      employee: 'youssef',
      source: 'late_penalty',
      reason: 'Late check-in (25 min)',
      reasonCode: 'late',
      amount: 5000,
      original: 5000,
      createdAt: _cairo(9, 18, 23, 59),
      createdBy: nour,
      effectiveDate: '2026-09-18',
    ), // waived, then the waiver undone: in the history only
    _deduction(
      'a2',
      org: sabah,
      employee: 'mariam',
      source: 'absence',
      reason: 'Absent, no check-in',
      reasonCode: 'absent_no_punch',
      amount: 10000,
      original: 20000,
      createdAt: _cairo(9, 19, 23, 59),
      createdBy: nour,
      effectiveDate: '2026-09-19',
      overriddenAt: _cairo(9, 21, 12),
      overriddenBy: nour,
    ),
    _deduction(
      'a3',
      org: sabah,
      employee: 'ali',
      source: 'late_penalty',
      reason: 'Late check-in (15 min)',
      reasonCode: 'late',
      amount: 3000,
      original: 3000,
      createdAt: _cairo(10, 1, 23, 59),
      createdBy: nour,
      effectiveDate: '2026-10-01',
      waivedAt: _cairo(10, 2, 11, 30),
      waivedBy: nour,
    ),
    _deduction(
      'a4',
      org: sabah,
      employee: 'salma',
      source: 'absence',
      reason: 'Absent, no check-in',
      reasonCode: 'absent_no_punch',
      amount: 15000,
      original: 30000,
      createdAt: _cairo(9, 27, 23, 59),
      createdBy: nour,
      effectiveDate: '2026-09-27',
      overriddenAt: _cairo(9, 28, 16),
      overriddenBy: nour,
    ),
    _deduction(
      'a5',
      org: sabah,
      employee: 'omar',
      source: 'late_penalty',
      reason: 'Late check-in (20 min)',
      reasonCode: 'late',
      amount: 4000,
      original: 4000,
      createdAt: _cairo(10, 4, 23, 59),
      createdBy: nour,
      effectiveDate: '2026-10-04',
      waivedAt: _cairo(10, 5, 9, 45),
      waivedBy: nour,
    ),
    _deduction(
      'a6',
      org: sabah,
      employee: 'hana',
      source: 'late_penalty',
      reason: 'Late check-in (20 min)',
      reasonCode: 'late',
      amount: 1000,
      original: 2500,
      createdAt: _cairo(10, 6, 23, 59),
      createdBy: nour,
      effectiveDate: '2026-10-06',
      overriddenAt: _cairo(10, 7, 13, 10),
      overriddenBy: nour,
    ),
    _deduction(
      'a7',
      org: nakhla,
      employee: 'seif',
      source: 'late_penalty',
      reason: 'Late check-in (30 min)',
      reasonCode: 'late',
      amount: 4000,
      original: 4000,
      createdAt: _cairo(9, 24, 23, 59),
      createdBy: yasmin,
      effectiveDate: '2026-09-24',
      waivedAt: _cairo(9, 25, 10),
      waivedBy: yasmin,
    ),
    _deduction(
      'a8',
      org: nakhla,
      employee: 'jana',
      source: 'absence',
      reason: 'Absent, no check-in',
      reasonCode: 'absent_no_punch',
      amount: 9000,
      original: 18000,
      createdAt: _cairo(10, 1, 23, 59),
      createdBy: yasmin,
      effectiveDate: '2026-10-01',
      overriddenAt: _cairo(10, 2, 15),
      overriddenBy: yasmin,
    ),
  ];
}

List<MockRow> _payrollLog() {
  final nour = _u('nour');
  final yasmin = SeedIds.dawamOwner;
  MockRow log(
    String key,
    String org,
    String deduction,
    String employee,
    String action,
    String actor,
    DateTime at,
    String reason,
    Map<String, int> details,
  ) => {
    'id': mockUuid('legal:payroll-log:$key'),
    'org_id': org,
    'entity': 'payroll_deductions',
    'entity_id': mockUuid('legal:deduction:$deduction'),
    'employee_id': _e(employee),
    'action': 'deduction.$action',
    'actor_id': actor,
    'created_at': at.toIso8601String(),
    'reason': reason,
    'details': details,
  };
  final s = SeedIds.sabahOrg;
  final n = SeedIds.nakhlaOrg;
  return [
    log(
      '1',
      s,
      'a1',
      'youssef',
      'waive',
      nour,
      _cairo(9, 20, 9),
      'Traffic accident on the ring road',
      {'amount_piastres': 5000},
    ),
    log(
      '2',
      s,
      'a1',
      'youssef',
      'unwaive',
      nour,
      _cairo(9, 22, 10),
      'Waived by mistake: he was late on another day',
      {'amount_piastres': 5000},
    ),
    log(
      '3',
      s,
      'a2',
      'mariam',
      'override',
      nour,
      _cairo(9, 21, 12),
      'Half of it: she called in sick late',
      {'from_piastres': 20000, 'to_piastres': 10000},
    ),
    log(
      '4',
      s,
      'a4',
      'salma',
      'override',
      nour,
      _cairo(9, 28, 16),
      "Doctor's note for the second half of the shift",
      {'from_piastres': 30000, 'to_piastres': 15000},
    ),
    log(
      '5',
      s,
      'a3',
      'ali',
      'waive',
      nour,
      _cairo(10, 2, 11, 30),
      'Metro outage on line 3',
      {'amount_piastres': 3000},
    ),
    log(
      '6',
      s,
      'a5',
      'omar',
      'waive',
      nour,
      _cairo(10, 5, 9, 45),
      "Covered a colleague's closing the night before",
      {'amount_piastres': 4000},
    ),
    log(
      '7',
      s,
      'a6',
      'hana',
      'override',
      nour,
      _cairo(10, 7, 13, 10),
      'Five minutes late, not twenty: the clock was fast',
      {'from_piastres': 2500, 'to_piastres': 1000},
    ),
    log(
      '8',
      n,
      'a7',
      'seif',
      'waive',
      yasmin,
      _cairo(9, 25, 10),
      'Power cut in Dokki that morning',
      {'amount_piastres': 4000},
    ),
    log(
      '9',
      n,
      'a8',
      'jana',
      'override',
      yasmin,
      _cairo(10, 2, 15),
      'Left at noon with permission',
      {'from_piastres': 18000, 'to_piastres': 9000},
    ),
  ];
}

// ── seed: loyalty and attendance ──────────────────────────────────────────

List<MockRow> _loyalty() {
  MockRow tx(
    String key,
    String? branch,
    int points,
    DateTime at,
    String by, {
    String kind = 'adjust',
    String source = 'manual',
    int customer = 0,
  }) => {
    'id': mockUuid('legal:loyalty:$key'),
    'org_id': SeedIds.sabahOrg,
    'branch_id': branch,
    'customer_id': MockSeed.customerId(customer),
    'kind': kind,
    'source': source,
    'points': points,
    'created_by': by,
    'created_at': at.toIso8601String(),
  };
  return [
    tx(
      '1',
      SeedIds.zamalek,
      50,
      _cairo(9, 12, 18, 30),
      _u('karim'),
      customer: 3,
    ),
    tx(
      '2',
      SeedIds.zamalek,
      30,
      _cairo(9, 27, 11, 5),
      _u('karim'),
      customer: 12,
    ),
    tx(
      '3',
      SeedIds.maadi,
      -40,
      _cairo(9, 19, 20, 10),
      _u('tarek'),
      kind: 'reverse_adjust',
      customer: 7,
    ),
    tx(
      '4',
      SeedIds.heliopolis,
      25,
      _cairo(10, 3, 9, 40),
      _u('rana'),
      customer: 21,
    ),
    tx(
      '5',
      SeedIds.newCairo,
      60,
      _cairo(9, 30, 17, 15),
      _u('dina'),
      customer: 5,
    ),
    // Made from the dashboard, away from any branch.
    tx('6', null, 100, _cairo(9, 16, 13), _u('nour'), customer: 0),
    tx(
      '7',
      SeedIds.zamalek,
      20,
      _cairo(10, 7, 19, 45),
      _u('karim'),
      customer: 30,
    ),
    // Not a person's hand: never audited.
    tx(
      '8',
      SeedIds.heliopolis,
      50,
      _cairo(9, 24, 8),
      _u('nour'),
      source: 'birthday',
      customer: 9,
    ),
    tx(
      '9',
      SeedIds.maadi,
      12,
      _cairo(9, 25, 9),
      _u('hana'),
      kind: 'earn',
      source: 'pos',
      customer: 2,
    ),
    // Before the default period.
    tx('10', SeedIds.maadi, 20, _cairo(8, 30, 12), _u('tarek'), customer: 14),
  ];
}

List<MockRow> _attendance() {
  MockRow rec(
    String key,
    String org,
    String branch,
    String employee,
    String? editedBy,
    String? reason,
    DateTime at,
  ) => {
    'id': mockUuid('legal:attendance:$key'),
    'org_id': org,
    'branch_id': branch,
    'employee_id': _e(employee),
    'edited_by': editedBy,
    'edit_reason': reason,
    'updated_at': at.toIso8601String(),
  };
  final s = SeedIds.sabahOrg;
  final n = SeedIds.nakhlaOrg;
  const request = 'Approved punch correction request';
  const autoClosed = 'Auto-closed: no checkout recorded';
  return [
    rec(
      '1',
      s,
      SeedIds.zamalek,
      'mariam',
      _u('karim'),
      'Forgot to clock out after closing',
      _cairo(9, 15, 10),
    ),
    rec(
      '2',
      s,
      SeedIds.zamalek,
      'youssef',
      _u('karim'),
      request,
      _cairo(9, 23, 9, 30),
    ),
    rec(
      '3',
      s,
      SeedIds.zamalek,
      'laila',
      _u('karim'),
      autoClosed,
      _cairo(9, 29, 11),
    ),
    rec('4', s, SeedIds.zamalek, 'adham', _u('karim'), null, _cairo(10, 2, 15)),
    rec(
      '5',
      s,
      SeedIds.zamalek,
      'hassan',
      _u('karim'),
      'Written by an approved punch correction',
      _cairo(10, 6, 12, 20),
    ),
    rec(
      '6',
      s,
      SeedIds.maadi,
      'hana',
      _u('tarek'),
      request,
      _cairo(9, 17, 10, 10),
    ),
    rec(
      '7',
      s,
      SeedIds.maadi,
      'ziad',
      _u('tarek'),
      'Phone battery died at check-in',
      _cairo(10, 1, 9, 5),
    ),
    rec(
      '8',
      s,
      SeedIds.newCairo,
      'omar',
      _u('dina'),
      'Marked automatically: no check-in',
      _cairo(9, 21, 16),
    ),
    rec(
      '9',
      s,
      SeedIds.newCairo,
      'salma',
      _u('dina'),
      autoClosed,
      _cairo(10, 5, 8, 50),
    ),
    rec(
      '10',
      s,
      SeedIds.heliopolis,
      'ali',
      _u('rana'),
      'Phone battery died at check-in',
      _cairo(9, 26, 7, 55),
    ),
    rec(
      '11',
      s,
      SeedIds.heliopolis,
      'farida',
      _u('rana'),
      request,
      _cairo(10, 7, 18),
    ),
    // Closed by the nightly job, never touched by a person: not audited.
    rec('12', s, SeedIds.maadi, 'ziad', null, autoClosed, _cairo(9, 30, 3)),
    rec(
      '13',
      n,
      SeedIds.dokki,
      'malak',
      SeedIds.dawamOwner,
      request,
      _cairo(9, 20, 9),
    ),
    rec(
      '14',
      n,
      SeedIds.nasrCity,
      'hamza',
      SeedIds.dawamOwner,
      'Bakery door sensor was down',
      _cairo(10, 4, 7, 30),
    ),
    rec(
      '15',
      n,
      SeedIds.nasrCity,
      'reem',
      SeedIds.dawamOwner,
      autoClosed,
      _cairo(9, 30, 10),
    ),
  ];
}

// ── test support: recording what the seed does not carry ─────────────────

/// Records a partial refund of [amount] piastres against order [orderId]
/// (its tax part at the order's applied rate, tax-inclusive), issued by
/// [issuedBy] at [issuedAt] for [reason] (a person's own words).
MockRow recordLegalRefund(
  MockDb db, {
  required String orderId,
  required int amount,
  required String reason,
  required String issuedBy,
  required DateTime issuedAt,
}) {
  final order = db['orders'].get(orderId, what: 'Order not found');
  final rate = (order['tax_rate_applied'] as num?)?.toDouble() ?? 0.14;
  final tax = (amount * rate / (1 + rate)).round();
  return db[legalRefundsTable].insert({
    'id': db.newId(legalRefundsTable),
    'order_id': orderId,
    'branch_id': order['branch_id'],
    'amount': amount,
    'tax': tax,
    'reason': reason,
    'issued_by': issuedBy,
    'issued_at': issuedAt.toUtc().toIso8601String(),
  }, timestamps: false);
}

/// Waives order [orderId]'s service charge of [amount] piastres.
void waiveLegalServiceCharge(
  MockDb db, {
  required String orderId,
  required int amount,
  required String by,
  required DateTime at,
}) => db['orders'].get(orderId).addAll({
  'service_charge_waived_amount': amount,
  'service_charge_waived_by': by,
  'service_charge_waived_at': at.toUtc().toIso8601String(),
});

/// Marks order [orderId] as sold at a price the catalogue disagreed with.
void flagLegalPrice(MockDb db, String orderId) =>
    db['orders'].get(orderId)['price_flagged'] = true;

/// Marks order [orderId]'s discount as replayed without the right.
void flagLegalDiscount(MockDb db, String orderId) =>
    db[legalDiscountFlagsTable].insert({'id': orderId}, timestamps: false);

// ── handlers ──────────────────────────────────────────────────────────────

void registerLegalMocks(MockServer server, MockDb db) {
  db
    ..lazyTable(legalDeductionsTable, _deductions)
    ..lazyTable(legalPayrollLogTable, _payrollLog)
    ..lazyTable(legalLoyaltyTable, _loyalty)
    ..lazyTable(legalAttendanceTable, _attendance)
    ..table(legalRefundsTable)
    ..table(legalDiscountFlagsTable)
    ..table(legalDiscountPresetsTable);

  server
    ..onOperation('org_tax_report', (req) {
      final s = _scope(req, db);
      final org = db['orgs'].get(s.orgId);
      final orders = _ordersCreated(db, s);
      final sold = summarizeSales(orders);
      final refunds = _refundsByOrder(db);
      var collected = 0;
      var refundedTax = 0;
      var refundedSold = 0;
      var service = 0;
      for (final o in orders) {
        if (o['status'] == 'voided') continue;
        collected += _int(o['tax_amount']);
        final r = refunds[o['id']];
        refundedTax += r?.tax ?? 0;
        if (isSold(o)) {
          refundedSold += r?.amount ?? 0;
          service += _int(o['service_charge_amount']);
        }
      }
      return MockResponse.ok(
        TaxReport(
          from: s.from,
          to: s.to,
          orgTaxRate: (org['tax_rate'] as num?)?.toDouble() ?? 0,
          orderCount: sold.orders,
          voidedOrders: sold.voided,
          subtotal: sold.subtotal,
          discountAmount: sold.discount,
          serviceChargeAmount: service,
          taxCollected: collected,
          refundedTax: refundedTax,
          netTaxDue: collected - refundedTax,
          netRevenue: sold.revenue - refundedSold,
        ),
      );
    })
    ..onOperation('refunds_audit', (req) {
      final s = _scope(req, db);
      final rows = [
        for (final r in db[legalRefundsTable].rows)
          if (s.branches.contains(r['branch_id']) && s.within(r['issued_at']))
            r,
      ];
      return _report(
        s,
        rows,
        amount: (r) => _int(r['amount']),
        reason: (r) => ('${r['reason']}', null),
        issuer: (r) => _userName(db, r['issued_by']),
      );
    })
    ..onOperation('voids_audit', (req) {
      final s = _scope(req, db);
      final rows = [
        for (final o in _orders(db, s))
          if (o['status'] == 'voided' && s.within(o['voided_at'])) o,
      ];
      return _report(
        s,
        rows,
        amount: (o) => _int(o['total_amount']),
        reason: (o) {
          final code = (o['void_reason'] as String?) ?? 'unspecified';
          return (code, code);
        },
        issuer: (o) => _userName(db, o['voided_by']),
      );
    })
    ..onOperation('discounts_audit', (req) {
      final s = _scope(req, db);
      final rows = [
        for (final o in _orders(db, s))
          if (isSold(o) &&
              _int(o['discount_amount']) > 0 &&
              s.within(o['created_at']))
            o,
      ];
      String? preset(MockRow o) => _presetName(db, o['discount_id']);
      String? appliedBy(MockRow o) =>
          _userName(db, o['discount_applied_by'] ?? o['teller_id']);
      final report = _reportJson(
        s,
        rows,
        amount: (o) => _int(o['discount_amount']),
        reason: (o) {
          final name = preset(o);
          if (name != null) return (name, null);
          final type = (o['discount_type'] as String?) ?? 'unspecified';
          return (type, type);
        },
        issuer: appliedBy,
        reasonLimit: 10,
      );
      final byKind = _group(
        rows,
        (o) => ((o['discount_kind'] as String?) ?? 'unattributed', null),
        (o) => _int(o['discount_amount']),
      );
      final flags = {for (final f in db[legalDiscountFlagsTable].rows) f['id']};
      final newest = [...rows]
        ..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
      return MockResponse.ok({
        ...report,
        'by_kind': byKind,
        'entries': [
          for (final o in newest.take(200))
            DiscountAuditEntry(
              orderId: o['id']! as String,
              orderRef: o['order_ref'] as String?,
              branchName: _branchName(db, o['branch_id']),
              createdAt: DateTime.parse(o['created_at']! as String),
              kind: o['discount_kind'] as String?,
              presetId: o['discount_id'] as String?,
              presetName: preset(o),
              amountMinor: _int(o['discount_amount']),
              percentBps: (o['discount_percent_bps'] as num?)?.toInt(),
              appliedByName: appliedBy(o),
              approvalId: o['discount_approval_id'] as String?,
              approvedByName: o['discount_approved_by_name'] as String?,
              flagged: flags.contains(o['id']),
            ).toJson(),
        ],
      });
    })
    ..onOperation('waivers_audit', (req) {
      final s = _scope(req, db);
      final rows = [
        for (final o in _orders(db, s))
          if (isSold(o) &&
              o['service_charge_waived_by'] != null &&
              s.within(o['service_charge_waived_at']))
            o,
      ];
      return _report(
        s,
        rows,
        amount: (o) => _int(o['service_charge_waived_amount']),
        reason: (o) => (_branchName(db, o['branch_id']), null),
        issuer: (o) => _userName(db, o['service_charge_waived_by']),
      );
    })
    ..onOperation('price_overrides', (req) {
      final s = _scope(req, db);
      final rows = [
        for (final o in _orders(db, s))
          if (isSold(o) &&
              o['price_flagged'] == true &&
              s.within(o['created_at']))
            o,
      ];
      return _report(
        s,
        rows,
        amount: (o) => _int(o['total_amount']),
        reason: (o) => (_branchName(db, o['branch_id']), null),
        issuer: (o) => _userName(db, o['teller_id']),
      );
    })
    ..onOperation('manual_deductions_audit', (req) {
      final s = _scope(req, db, also: 'hr.payroll.read');
      final rows = [
        for (final d in db[legalDeductionsTable].rows)
          if (d['org_id'] == s.orgId &&
              d['source'] == 'manual' &&
              _employeeInScope(db, s, d['employee_id']) &&
              s.within(d['created_at']))
            d,
      ];
      return _report(
        s,
        rows,
        amount: (d) => _int(d['amount_piastres']),
        reason: (d) => ('${d['reason']}', null),
        issuer: (d) => _userName(db, d['created_by']),
        reasonLimit: 10,
      );
    })
    ..onOperation('deduction_overrides_audit', (req) {
      final s = _scope(req, db, also: 'hr.payroll.read');
      final rows = [
        for (final d in db[legalDeductionsTable].rows)
          if (d['org_id'] == s.orgId &&
              (d['overridden_at'] != null || d['waived_at'] != null) &&
              _employeeInScope(db, s, d['employee_id']) &&
              s.within(d['waived_at'] ?? d['overridden_at']))
            d,
      ];
      int forgiven(MockRow d) {
        final original = d['original_amount_piastres'] ?? d['amount_piastres'];
        if (d['waived_at'] != null) return _int(original);
        final drop = _int(original) - _int(d['amount_piastres']);
        return drop < 0 ? 0 : drop;
      }

      final report = _reportJson(
        s,
        rows,
        amount: forgiven,
        // The server writes these two words without a code.
        reason: (d) => (d['waived_at'] != null ? 'waived' : 'overridden', null),
        issuer: (d) => _userName(db, d['waived_by'] ?? d['overridden_by']),
      );
      final deductions = {
        for (final d in db[legalDeductionsTable].rows) d['id']: d,
      };
      final log = [
        for (final l in db[legalPayrollLogTable].rows)
          if (l['org_id'] == s.orgId &&
              l['entity'] == 'payroll_deductions' &&
              _employeeInScope(db, s, l['employee_id']) &&
              s.within(l['created_at']))
            l,
      ]..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
      return MockResponse.ok({
        ...report,
        'history': [
          for (final l in log.take(500))
            () {
              final action = '${l['action']}'.split('.').last;
              final details = (l['details'] as Map?) ?? const {};
              final d = deductions[l['entity_id']];
              return DeductionOverrideEvent(
                deductionId: l['entity_id']! as String,
                employeeId: l['employee_id'] as String?,
                employeeName: _employeeName(db, l['employee_id']),
                action: action,
                actorId: l['actor_id'] as String?,
                actorName: _userName(db, l['actor_id']),
                at: DateTime.parse(l['created_at']! as String),
                reason: l['reason'] as String?,
                amountBeforePiastres: switch (action) {
                  'override' => _int(details['from_piastres']),
                  'waive' => _int(details['amount_piastres']),
                  _ => 0,
                },
                amountAfterPiastres: switch (action) {
                  'override' => _int(details['to_piastres']),
                  'unwaive' => _int(details['amount_piastres']),
                  _ => 0,
                },
                effectiveDate: d?['effective_date'] as String?,
                source: d?['source'] as String?,
                reasonCode: d?['reason_code'] as String?,
              ).toJson();
            }(),
        ],
      });
    })
    ..onOperation('loyalty_adjustments_audit', (req) {
      final s = _scope(req, db);
      final rows = [
        for (final t in db[legalLoyaltyTable].rows)
          if (t['org_id'] == s.orgId &&
              (t['kind'] == 'adjust' || t['kind'] == 'reverse_adjust') &&
              t['source'] == 'manual' &&
              (s.wholeOrg || s.branches.contains(t['branch_id'])) &&
              s.within(t['created_at']))
            t,
      ];
      return _report(
        s,
        rows,
        amount: (t) => _int(t['points']).abs(),
        reason: (t) => (
          t['branch_id'] == null
              ? 'unspecified'
              : _branchName(db, t['branch_id']),
          null,
        ),
        issuer: (t) => _userName(db, t['created_by']),
      );
    })
    ..onOperation('attendance_corrections_audit', (req) {
      final s = _scope(req, db, also: 'hr.attendance.read');
      final rows = [
        for (final a in db[legalAttendanceTable].rows)
          if (a['org_id'] == s.orgId &&
              a['edited_by'] != null &&
              s.branches.contains(a['branch_id']) &&
              s.within(a['updated_at']))
            a,
      ];
      final report = _reportJson(
        s,
        rows,
        amount: (_) => 0,
        reason: (a) {
          final r = a['edit_reason'] as String?;
          return (
            r ?? 'unspecified',
            switch (r) {
              null => 'unspecified',
              'Approved punch correction request' ||
              'Written by an approved punch correction' => 'correction_request',
              'Auto-closed: no checkout recorded' => 'auto_closed',
              'Marked automatically: no check-in' => 'marked_absent',
              _ => null,
            },
          );
        },
        issuer: (a) => _userName(db, a['edited_by']),
        reasonLimit: 10,
      );
      return MockResponse.ok({...report, 'total_amount_minor': 0});
    });
}

// ── helpers ───────────────────────────────────────────────────────────────

int _int(Object? v) => v is num ? v.toInt() : 0;

/// Who asks, about which org, over which branches and period.
class _Scope {
  _Scope(this.orgId, this.branches, this.from, this.to, this.wholeOrg);

  final String orgId;

  /// The org's branches the caller may see.
  final Set<String> branches;
  final DateTime? from;
  final DateTime? to;

  /// The caller sees the whole org (owner, platform admin).
  final bool wholeOrg;

  bool within(Object? iso) {
    if (iso is! String) return false;
    final at = DateTime.tryParse(iso);
    if (at == null) return false;
    if (from != null && at.isBefore(from!)) return false;
    if (to != null && at.isAfter(to!)) return false;
    return true;
  }
}

/// `legal::guard` (+ `guard_with`): `reports.legal`, the caller's own org,
/// the extra capability, then the branches the caller may read.
_Scope _scope(MockRequest req, MockDb db, {String? also}) {
  final orgId = req.param('org_id');
  final from = req.qDateTime('from');
  final to = req.qDateTime('to');
  req
    ..requireCap('reports.legal')
    ..requireSameOrg(orgId);
  db['orgs'].get(orgId, what: 'Organization not found');
  if (also != null) req.requireCap(also);
  final mine = req.persona.branchIds;
  final branches = {
    for (final b in db['branches'].rows)
      if (b['org_id'] == orgId && (mine == null || mine.contains(b['id'])))
        b['id']! as String,
  };
  return _Scope(orgId, branches, from, to, mine == null);
}

/// The core seed's orders at the scope's branches (any date).
Iterable<MockRow> _orders(MockDb db, _Scope s) =>
    db['orders'].rows.where((o) => s.branches.contains(o['branch_id']));

/// …created within the period (`o.created_at`).
List<MockRow> _ordersCreated(MockDb db, _Scope s) => [
  for (final o in _orders(db, s))
    if (s.within(o['created_at'])) o,
];

/// `v_order_refund_totals`: refunded amount and tax per order.
Map<Object?, ({int amount, int tax})> _refundsByOrder(MockDb db) {
  final out = <Object?, ({int amount, int tax})>{};
  for (final r in db[legalRefundsTable].rows) {
    final prev = out[r['order_id']] ?? (amount: 0, tax: 0);
    out[r['order_id']] = (
      amount: prev.amount + _int(r['amount']),
      tax: prev.tax + _int(r['tax']),
    );
  }
  return out;
}

bool _employeeInScope(MockDb db, _Scope s, Object? employeeId) {
  if (s.wholeOrg) return true;
  final e = employeeId is String ? db['employees'].find(employeeId) : null;
  final ids = e?['branch_ids'];
  return ids is List && ids.any(s.branches.contains);
}

String? _userName(MockDb db, Object? id) =>
    id is String ? (db['users'].find(id)?['name'] as String?) : null;

String? _employeeName(MockDb db, Object? id) =>
    id is String ? (db['employees'].find(id)?['name'] as String?) : null;

String _branchName(MockDb db, Object? id) =>
    (id is String ? (db['branches'].find(id)?['name'] as String?) : null) ?? '';

String? _presetName(MockDb db, Object? id) {
  if (id is! String) return null;
  for (final table in ['discounts', legalDiscountPresetsTable]) {
    if (!db.hasTable(table)) continue;
    final name = db[table].find(id)?['name'];
    if (name is String) return name;
  }
  return null;
}

/// `GROUP BY` a label (with its code) → breakdown rows, most events first
/// (ties by label, so the order is stable), at most [limit].
List<Map<String, Object?>> _group(
  Iterable<MockRow> rows,
  (String, String?) Function(MockRow row) key,
  int Function(MockRow row) amount, {
  int? limit,
}) {
  final groups = <String, ({String? code, int count, int amount})>{};
  for (final r in rows) {
    final (label, code) = key(r);
    final g = groups[label];
    groups[label] = (
      code: g?.code ?? code,
      count: (g?.count ?? 0) + 1,
      amount: (g?.amount ?? 0) + amount(r),
    );
  }
  final out = groups.entries.toList()
    ..sort((a, b) {
      final c = b.value.count.compareTo(a.value.count);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [
    for (final e in limit == null ? out : out.take(limit))
      AuditBreakdownEntry(
        label: e.key,
        code: e.value.code,
        count: e.value.count,
        amountMinor: e.value.amount,
      ).toJson(),
  ];
}

/// The shared report shape: totals, by reason, by issuer (top 10; rows
/// without a known person are not joined, as the SQL's inner join).
Map<String, Object?> _reportJson(
  _Scope s,
  List<MockRow> rows, {
  required int Function(MockRow row) amount,
  required (String, String?) Function(MockRow row) reason,
  required String? Function(MockRow row) issuer,
  int? reasonLimit,
}) => {
  'from': s.from?.toIso8601String(),
  'to': s.to?.toIso8601String(),
  'total_count': rows.length,
  'total_amount_minor': rows.fold<int>(0, (sum, r) => sum + amount(r)),
  'by_reason': _group(rows, reason, amount, limit: reasonLimit),
  'by_issuer': _group(
    [
      for (final r in rows)
        if (issuer(r) != null) r,
    ],
    (r) => (issuer(r)!, null),
    amount,
    limit: 10,
  ),
};

MockResponse _report(
  _Scope s,
  List<MockRow> rows, {
  required int Function(MockRow row) amount,
  required (String, String?) Function(MockRow row) reason,
  required String? Function(MockRow row) issuer,
  int? reasonLimit,
}) => MockResponse.ok(
  _reportJson(
    s,
    rows,
    amount: amount,
    reason: reason,
    issuer: issuer,
    reasonLimit: reasonLimit,
  ),
);
