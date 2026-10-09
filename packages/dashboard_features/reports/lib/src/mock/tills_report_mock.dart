/// The mock backend for Till sessions (REP-TIL): `/reports/branches/{branchId}/tills`.
///
/// Handlers behave like the backend (capability refusals, branch scoping,
/// the shared figures in `../area_seed.dart`); see SPEC section 3.2.
library;

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show appTimezone, inZone;

import '../area_seed.dart' show bindReportDb, isSold, reportBranchIds;

/// The cash movements the Tills page records (`POST /tills/{id}/cash-movements`,
/// the sell area's `CashMovement` rows; empty in the core seed).
const String tillMovementsTable = 'till_cash_movements';

/// MadarRust `MAX_TILL_SESSIONS`: past this the range is refused, never cut.
const int maxTillSessions = 5000;

void registerTillsReportMocks(MockServer server, MockDb db) {
  // The branch rows `reportBranchIds` checks (404 / another org / not
  // assigned); binding twice is harmless.
  bindReportDb(server, db);
  // MadarRust `branch_till_sessions`: tills opened in the range, newest
  // first; every till at a branch where the caller holds `till.read.branch`,
  // elsewhere only the caller's own.
  server.on('GET', '/reports/branches/{branch_id}/tills', (req) {
    req.requireCap('till.read');
    final branches = reportBranchIds(req, req.param('branch_id')).toSet();
    final from = req.qDateTime('from');
    final to = req.qDateTime('to');
    if (from != null && to != null && to.isBefore(from)) {
      req.badRequest('`to` is before `from`');
    }
    final seesAll = req.persona.can('till.read.branch');
    final tills = [
      for (final t in db['tills'].rows)
        if (branches.contains(t['branch_id']) &&
            (seesAll || t['teller_id'] == req.persona.userId) &&
            _opened(t, from, to))
          t,
    ];
    if (tills.length > maxTillSessions) {
      req.badRequest(
        'More than $maxTillSessions till sessions in this range; '
        'narrow `from`/`to`',
      );
    }
    final orders = _byTill(db['orders'].rows);
    final moves = _byTill(db[tillMovementsTable].rows);
    return MockResponse.ok(
      [
        for (final t in tills)
          tillSessionRow(
            db,
            t,
            orders: orders[t['id']] ?? const [],
            moves: moves[t['id']] ?? const [],
          ),
      ]..sort(_newestFirst),
    );
  });
}

Map<Object?, List<MockRow>> _byTill(Iterable<MockRow> rows) {
  final out = <Object?, List<MockRow>>{};
  for (final r in rows) {
    (out[r['till_id']] ??= []).add(r);
  }
  return out;
}

int _newestFirst(MockRow a, MockRow b) {
  final d = _at(b['opened_at']).compareTo(_at(a['opened_at']));
  return d != 0 ? d : '${a['till_id']}'.compareTo('${b['till_id']}');
}

DateTime _at(Object? iso) =>
    DateTime.tryParse('$iso') ?? DateTime.fromMillisecondsSinceEpoch(0);

bool _opened(MockRow till, DateTime? from, DateTime? to) {
  final at = DateTime.tryParse('${till['opened_at']}');
  if (at == null) return false;
  if (from != null && at.isBefore(from)) return false;
  if (to != null && at.isAfter(to)) return false;
  return true;
}

int _int(Object? v) => v is num ? v.toInt() : 0;

/// One `TillSessionRow`, by the backend's expressions:
/// - net cash: cash legs and cash tips of TENDERED sales (not voided; the
///   seed has no refunds, so nothing is handed back);
/// - pay-ins / pay-outs / drops / adjustments: the till's cash movements, a
///   correction counted against the kind it corrects;
/// - orders and net sales: the SOLD set;
/// - the business date: the opening's calendar day in the branch's zone
///   (else the org's).
///
/// [orders] and [moves] are the till's own rows.
MockRow tillSessionRow(
  MockDb db,
  MockRow t, {
  required List<MockRow> orders,
  required List<MockRow> moves,
}) {
  var cash = 0;
  var count = 0;
  var sales = 0;
  for (final o in orders) {
    if (o['status'] == 'voided') continue;
    if (isSold(o)) {
      count += 1;
      sales += _int(o['total_amount']);
    }
    final legs = o['payment_legs'];
    if (legs is List && legs.isNotEmpty) {
      for (final l in legs.whereType<Map<Object?, Object?>>()) {
        if ((l['is_cash'] as bool?) ?? l['method'] == 'cash') {
          cash += _int(l['amount']);
        }
      }
    } else if (o['payment_method'] == 'cash') {
      cash += _int(o['total_amount']);
    }
    final tipCash =
        (o['tip_is_cash'] as bool?) ??
        (o['tip_payment_method'] ?? o['payment_method']) == 'cash';
    if (tipCash) cash += _int(o['tip_amount']);
  }

  final kindOf = {for (final m in moves) m['id']: m['kind']};
  int bucket(String kind) => moves
      .where(
        (m) =>
            (m['kind'] == 'correction'
                ? (kindOf[m['corrects_id']] ?? 'correction')
                : m['kind']) ==
            kind,
      )
      .fold<int>(0, (s, m) => s + _int(m['amount']));

  final branch = db['branches'].find('${t['branch_id']}');
  final zone =
      (branch?['timezone'] as String?) ??
      (db['orgs'].find('${branch?['org_id']}')?['timezone'] as String?) ??
      appTimezone;
  final local = inZone(DateTime.parse('${t['opened_at']}'), zone);
  String two(int n) => n.toString().padLeft(2, '0');
  final opening = _int(t['opening_cash']);
  final payIns = bucket('pay_in');
  final payOuts = -bucket('pay_out');
  final drops = -bucket('safe_drop');
  final adjustments = bucket('correction');
  final forced = t['status'] == 'force_closed';
  return {
    'till_id': t['id'],
    'business_date': '${local.year}-${two(local.month)}-${two(local.day)}',
    'branch_id': t['branch_id'],
    'branch_name': branch?['name'] ?? t['branch_name'] ?? '',
    'branch_code': branch?['code'] ?? '',
    'teller_id': t['teller_id'],
    'teller_name': t['teller_name'] ?? '',
    'opened_at': t['opened_at'],
    'status': t['status'],
    'opening_cash': opening,
    'net_cash_payment': cash,
    'pay_ins': payIns,
    'pay_outs': payOuts,
    'cash_drops': drops,
    'cash_adjustments': adjustments,
    'closing_cash_declared': t['closing_cash_declared'],
    // A force-close freezes the drawer the system expected (MadarRust
    // `force_close` stores `compute_system_cash`); the core seed leaves it
    // out, so it is worked out here the same way.
    'closing_cash_system':
        t['closing_cash_system'] ??
        (forced
            ? opening + cash + payIns - payOuts - drops + adjustments
            : null),
    'cash_discrepancy': t['cash_discrepancy'],
    'closed_at': t['closed_at'],
    'orders_count': count,
    'net_sales': sales,
  };
}
