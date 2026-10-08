/// The mock backend for Till sessions (REP-TIL): `/reports/branches/{branchId}/tills`.
///
/// Handlers behave like the backend (capability refusals, branch scoping,
/// the shared figures in `../area_seed.dart`); see SPEC section 3.2.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart' show isSold, reportBranchIds;

void registerTillsReportMocks(MockServer server, MockDb db) {
  // MadarRust `branch_till_sessions`: tills opened in the range, newest
  // first; every till at a branch where the caller holds `till.read.branch`,
  // elsewhere only the caller's own.
  server.on('GET', '/reports/branches/{branch_id}/tills', (req) {
    req.requireCap('till.read');
    final from = req.qDateTime('from');
    final to = req.qDateTime('to');
    if (from != null && to != null && to.isBefore(from)) {
      req.badRequest('`to` is before `from`');
    }
    final branches = reportBranchIds(req, req.param('branch_id')).toSet();
    final seesAll = req.persona.can('till.read.branch');
    final rows = <MockRow>[
      for (final t in db['tills'].rows)
        if (branches.contains(t['branch_id']) &&
            (seesAll || t['teller_id'] == req.persona.userId) &&
            _opened(t, from, to))
          _sessionRow(db, t),
    ]..sort((a, b) => '${b['opened_at']}'.compareTo('${a['opened_at']}'));
    return MockResponse.ok(rows);
  });
}

bool _opened(MockRow till, DateTime? from, DateTime? to) {
  final at = DateTime.tryParse('${till['opened_at']}');
  if (at == null) return false;
  if (from != null && at.isBefore(from)) return false;
  if (to != null && at.isAfter(to)) return false;
  return true;
}

int _int(Object? v) => v is num ? v.toInt() : 0;

/// One `TillSessionRow`: the till's own figures and what its orders took
/// (the seed has no cash movements or refunds, so those are 0).
MockRow _sessionRow(MockDb db, MockRow t) {
  var cash = 0;
  var orders = 0;
  var sales = 0;
  for (final o in db['orders'].rows) {
    if (o['till_id'] != t['id'] || !isSold(o)) continue;
    orders += 1;
    sales += _int(o['total_amount']);
    final legs = o['payment_legs'];
    if (legs is List && legs.isNotEmpty) {
      for (final l in legs) {
        if (l is Map && l['is_cash'] == true) cash += _int(l['amount']);
      }
    } else if (o['payment_method'] == 'cash') {
      cash += _int(o['total_amount']);
    }
    if (o['tip_payment_method'] == 'cash') cash += _int(o['tip_amount']);
  }
  final branch = db['branches'].find('${t['branch_id']}');
  final opened = DateTime.parse('${t['opened_at']}');
  return {
    'till_id': t['id'],
    // ponytail: the UTC day; the backend uses the branch's zone (Cairo, +2/+3).
    'business_date': opened.toIso8601String().substring(0, 10),
    'branch_id': t['branch_id'],
    'branch_name': t['branch_name'] ?? branch?['name'] ?? '',
    'branch_code': branch?['code'] ?? '',
    'teller_id': t['teller_id'],
    'teller_name': t['teller_name'] ?? '',
    'opened_at': t['opened_at'],
    'status': t['status'],
    'opening_cash': _int(t['opening_cash']),
    'net_cash_payment': cash,
    'pay_ins': 0,
    'pay_outs': 0,
    'cash_drops': 0,
    'cash_adjustments': 0,
    'closing_cash_declared': t['closing_cash_declared'],
    'closing_cash_system': t['closing_cash_system'],
    'cash_discrepancy': t['cash_discrepancy'],
    'closed_at': t['closed_at'],
    'orders_count': orders,
    'net_sales': sales,
  };
}
