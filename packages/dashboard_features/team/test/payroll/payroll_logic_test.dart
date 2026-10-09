// The page's browser-side rules (`payroll_logic.dart`) and the money forms'
// error wording (`money_errors.dart`), against hand-worked answers.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_team/src/payroll/money_errors.dart';
import 'package:dashboard_team/src/payroll/payroll_logic.dart';
import 'package:flutter_test/flutter_test.dart';

import 'payroll_support.dart';

PayrollPeriod _period(String status, String start, String end) =>
    PayrollPeriod.fromJson({
      'id': 'p-$start',
      'org_id': 'o',
      'name': start,
      'start_date': start,
      'end_date': end,
      'status': status,
      'employee_count': 3,
      'total_net_piastres': 900000,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });

ApiException _coded(int status, String code, [Map<String, Object?>? vars]) =>
    ApiException(
      status: status,
      code: code,
      message: 'server words',
      details: {'error': 'server words', 'code': code, 'vars': ?vars},
    );

void main() {
  test('TEAM-MNY-001 the first open month', () {
    expect(firstOpenMonth(_period('draft', '2026-10-01', '2026-10-31'), '2026-10-08'), '2026-10');
    expect(firstOpenMonth(_period('generated', '2026-10-01', '2026-10-31'), '2026-10-08'), '2026-11');
    // Across a year, and a window that ends mid-month.
    expect(firstOpenMonth(_period('paid', '2026-12-01', '2026-12-31'), '2026-12-20'), '2027-01');
    expect(firstOpenMonth(_period('generated', '2026-09-25', '2026-10-24'), '2026-10-08'), '2026-11');
    expect(firstOpenMonth(null, '2026-10-08'), '2026-10');
    expect(monthToDate('2026-11'), '2026-11-01');
  });

  test('TEAM-PAY-006 days still to come, both ends counted', () {
    expect(daysStillToCome('2026-10-31', '2026-10-08'), 24);
    expect(daysStillToCome('2026-10-31', '2026-10-31'), 1);
    expect(daysStillToCome('2026-10-31', '2026-11-02'), 0);
  });

  test('TEAM-PAY-002 the phase of each server status', () {
    expect(periodPhase('draft'), PayPhase.open);
    expect(periodPhase('generated'), PayPhase.approved);
    expect(periodPhase('paid'), PayPhase.paid);
    expect(periodPhase('closed'), PayPhase.paid);
  });

  test('TEAM-PAY-004 the next step sentence', () {
    expect(nextStepKey(PayPhase.open, 2, 0, 5), 'dawamOps.payNextBlocked');
    expect(nextStepKey(PayPhase.open, 0, 0, 5), 'dawamOps.payNextApprove');
    expect(nextStepKey(PayPhase.approved, 0, 0, 5), 'dawamOps.payNextPayFirst');
    expect(nextStepKey(PayPhase.approved, 0, 3, 5), 'dawamOps.payNextPayRest');
    expect(nextStepKey(PayPhase.approved, 0, 5, 5), 'dawamOps.payNextDone');
    expect(nextStepKey(PayPhase.paid, 0, 5, 5), 'dawamOps.payNextClosed');
  });

  /// [path]'s JSON from the seeded mock, as the owner.
  Future<Object?> read(String path, [void Function(MockDb db)? edit]) async {
    final s = payrollServer(edit: edit);
    final r = await s.server.send(ApiRequest(method: 'GET', path: path));
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  test('TEAM-PAY-010 an older server without `unsettled`: from history', () async {
    final json = (await read(currentT, septemberUnpaid))! as Map<String, Object?>;
    final fromServer = unsettledOf(CurrentPayroll.fromJson(json));
    expect(fromServer.single.paidCount, 12);
    json.remove('unsettled');
    final u = unsettledOf(CurrentPayroll.fromJson(json));
    expect(u.single.startsOn, '2026-09-01');
    expect(u.single.paidCount, isNull);
  });

  test('TEAM-PAY-020/063 unpaid first, order kept; names fall back', () async {
    final list = (await read(
      '/staff/payroll/periods/${septemberId()}/payslips',
      septemberUnpaid,
    ))! as List<Object?>;
    final slips = [
      for (final j in list) Payslip.fromJson(j! as Map<String, Object?>),
    ];
    final rows = [for (final p in slips) SlipRow.frozen(p)];
    final out = unpaidFirst(rows);
    expect(out.take(3).every((r) => r.paidMethod == null), isTrue);
    expect(out.skip(3).every((r) => r.paidMethod != null), isTrue);
    final paid = [for (final r in rows) if (r.paidMethod != null) r.employeeId];
    expect([for (final r in out.skip(3)) r.employeeId], paid);
    final unnamed = Payslip.fromJson({
      ...(list.first! as Map<String, Object?>),
      'employee_name': null,
    });
    expect(SlipRow.frozen(unnamed, fallbackName: 'From the list').name, 'From the list');
    expect(SlipRow.frozen(unnamed).name, '—');
    // A run's own zero-net settlement is no payment by hand (TEAM-PAY-007).
    final none = Payslip.fromJson({
      ...(list.first! as Map<String, Object?>),
      'paid_method': 'none',
    });
    expect(SlipRow.frozen(none).paidByHand, isFalse);
  });

  testWidgets(
    'TEAM-ALL-017/019 / TEAM-MNY-017 money refusals in the reader\'s words',
    (tester) async {
      for (final lang in ['ar']) {
        final h = await pumpPayroll(tester, locale: lang);
        final t = h.container.read(tProvider);
        final f = h.container.read(formatProvider);
        String words(ApiException e, {ReasonFor? r, bool month = false}) =>
            dawamErrorMessage(e, t, f, reasonFor: r, monthForm: month);
        expect(words(_coded(409, 'RULES_NOT_SET')), t('errors.codes.RULES_NOT_SET'));
        expect(
          words(_coded(400, 'REASON_REQUIRED'), r: ReasonFor.payLine),
          t('errors.codes.REASON_REQUIRED_payLine'),
        );
        expect(words(_coded(400, 'REASON_REQUIRED')), t('errors.codes.REASON_REQUIRED'));
        expect(
          words(_coded(409, 'PERIOD_CLOSED', {'paid': true}), month: true),
          t('errors.codes.PERIOD_CLOSED_paid_month'),
        );
        expect(
          words(_coded(409, 'PERIOD_CLOSED', {'paid': true})),
          t('errors.codes.PERIOD_CLOSED_paid'),
        );
        expect(
          words(_coded(409, 'ADVANCE_OVER_CAP', {'over_cap': true})),
          t('errors.codes.ADVANCE_OVER_CAP_owner'),
        );
        expect(
          words(_coded(409, 'ADVANCE_OVER_CAP', {'over_cap': true, 'more_egp': 900})),
          t('errors.codes.ADVANCE_OVER_CAP', args: {'more_egp': 900}),
        );
        expect(
          words(const ApiException(status: 403, message: 'Forbidden: no')),
          t('errors.unauthorized'),
        );
        expect(t('errors.codes.RULES_NOT_SET'), isNot(contains('errors.')));
        await h.flushTimers();
      }
    },
  );
}
