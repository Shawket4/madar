// The Till sessions mock handler against figures worked out by hand from the
// core seed's rows: MadarRust `branch_till_sessions`'s gate, scoping, range
// rules and cash arithmetic (SPEC 3.2).
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show allBranchesId;
import 'package:dashboard_reports/src/mock/tills_report_mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// The default period at the seed's now (30 days to 8 Oct, Cairo).
final _from = DateTime.utc(2026, 9, 8, 21);
final _to = DateTime.utc(2026, 10, 8, 20, 59, 59);

Future<List<Map<String, Object?>>> _get(
  MockServer s, {
  String branch = '',
  DateTime? from,
  DateTime? to,
}) async {
  final r = await s.send(
    ApiRequest(
      method: 'GET',
      path: '/reports/branches/${branch.isEmpty ? allBranchesId : branch}/tills',
      query: {
        'from': [(from ?? _from).toIso8601String()],
        'to': [(to ?? _to).toIso8601String()],
      },
    ),
  );
  return [
    for (final row in jsonDecode(utf8.decode(r.bodyBytes)) as List)
      (row as Map).cast<String, Object?>(),
  ];
}

Future<ApiException> _refused(Future<Object?> f) async {
  try {
    await f;
    fail('expected a refusal');
  } on ApiException catch (e) {
    return e;
  }
}

/// The seed's tills opened in the period at [branches], by hand.
List<MockRow> _tills(MockDb db, Iterable<String> branches) => [
  for (final t in db['tills'].rows)
    if (branches.contains(t['branch_id']) &&
        !DateTime.parse('${t['opened_at']}').isBefore(_from) &&
        !DateTime.parse('${t['opened_at']}').isAfter(_to))
      t,
];

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

void main() {
  test('every Sabah till opened in the period, newest first, each with its '
      'own orders and cash', () async {
    final s = tillsServer();
    final rows = await _get(s.server);
    final want = _tills(s.db, SeedIds.sabahBranches);
    expect(rows, hasLength(want.length));
    expect(rows.length, greaterThan(200));
    final opened = [for (final r in rows) DateTime.parse('${r['opened_at']}')];
    for (var i = 1; i < opened.length; i++) {
      expect(opened[i].isAfter(opened[i - 1]), isFalse);
    }
    for (final r in rows) {
      final orders = s.db['orders'].rows
          .where((o) => o['till_id'] == r['till_id'])
          .toList();
      final sold = orders.where(
        (o) => o['status'] != 'voided' && o['status'] != 'refunded',
      );
      expect(r['orders_count'], sold.length);
      expect(r['net_sales'], sold.fold<int>(0, (n, o) => n + _int(o['total_amount'])));
      var cash = 0;
      for (final o in orders.where((o) => o['status'] != 'voided')) {
        for (final l in (o['payment_legs']! as List).cast<Map>()) {
          if (l['is_cash'] == true) cash += _int(l['amount']);
        }
      }
      expect(r['net_cash_payment'], cash, reason: '${r['till_id']}');
      final branch = s.db['branches'].find('${r['branch_id']}')!;
      expect(r['branch_name'], branch['name']);
      expect(r['branch_code'], branch['code']);
    }
  });

  test('a closed row adds up: opening + net cash + pay-ins − pay-outs − drops '
      '+ adjustments = expected; declared − expected = variance', () async {
    final s = tillsServer();
    final rows = await _get(s.server);
    var closed = 0;
    for (final r in rows) {
      final system = r['closing_cash_system'] as int?;
      if (system == null) {
        expect(r['status'], 'open');
        expect(r['closed_at'], isNull);
        continue;
      }
      closed++;
      expect(
        _int(r['opening_cash']) +
            _int(r['net_cash_payment']) +
            _int(r['pay_ins']) -
            _int(r['pay_outs']) -
            _int(r['cash_drops']) +
            _int(r['cash_adjustments']),
        system,
        reason: '${r['till_id']}',
      );
      final declared = r['closing_cash_declared'] as int?;
      if (declared != null) {
        expect(declared - system, r['cash_discrepancy']);
      }
    }
    expect(closed, greaterThan(200));
    // Shorts, overs and even closes all appear.
    final v = [for (final r in rows) r['cash_discrepancy'] as int?];
    expect(v.where((x) => x != null && x < 0), isNotEmpty);
    expect(v.where((x) => x != null && x > 0), isNotEmpty);
    expect(v.where((x) => x == 0), isNotEmpty);
    // Today's morning tills are still open.
    expect(rows.where((r) => r['status'] == 'open'), hasLength(4));
  });

  test('a force-close: the drawer the system expected, no count, no variance',
      () async {
    final s = tillsServer();
    final rows = await _get(s.server);
    final forced = rows.where((r) => r['status'] == 'force_closed').toList();
    expect(forced, isNotEmpty);
    for (final r in forced) {
      expect(r['closing_cash_declared'], isNull);
      expect(r['cash_discrepancy'], isNull);
      expect(
        r['closing_cash_system'],
        _int(r['opening_cash']) + _int(r['net_cash_payment']),
      );
      expect(r['closed_at'], isNotNull);
    }
  });

  test('the business date is the opening\'s day in the branch\'s zone, not '
      'UTC\'s', () async {
    final s = tillsServer();
    final base = s.db['tills'].rows.last;
    s.db['tills'].insert({
      ...base,
      'id': 'till-late',
      'opened_at': '2026-10-01T22:30:00.000Z', // 01:30 on the 2nd in Cairo
      'status': 'closed',
      'closed_at': '2026-10-02T05:00:00.000Z',
    }, timestamps: false);
    final rows = await _get(s.server);
    final late = rows.singleWhere((r) => r['till_id'] == 'till-late');
    expect(late['business_date'], '2026-10-02');
    final seeded = rows.firstWhere((r) => r['till_id'] != 'till-late');
    expect(
      seeded['business_date'],
      MockClock.cairoDate(DateTime.parse('${seeded['opened_at']}')),
    );
  });

  test('cash movements land in their buckets; a correction counts against '
      'the kind it corrects, else as an adjustment', () async {
    final s = tillsServer();
    final till = _tills(s.db, [SeedIds.zamalek]).first;
    final id = till['id'];
    final m = s.db[tillMovementsTable];
    m.insert({'id': 'mv-in', 'till_id': id, 'kind': 'pay_in', 'amount': 2000});
    m.insert({'id': 'mv-out', 'till_id': id, 'kind': 'pay_out', 'amount': -1500});
    m.insert({
      'id': 'mv-drop',
      'till_id': id,
      'kind': 'safe_drop',
      'amount': -30000,
    });
    m.insert({
      'id': 'mv-fix',
      'till_id': id,
      'kind': 'correction',
      'amount': -500,
      'corrects_id': 'mv-in',
    });
    m.insert({'id': 'mv-adj', 'till_id': id, 'kind': 'correction', 'amount': 700});
    final row = (await _get(
      s.server,
    )).singleWhere((r) => r['till_id'] == id);
    expect(row['pay_ins'], 1500);
    expect(row['pay_outs'], 1500);
    expect(row['cash_drops'], 30000);
    expect(row['cash_adjustments'], 700);
  });

  test('a branch manager: her branch only; another branch is refused',
      () async {
    final s = tillsServer(persona: Persona.manager);
    final rows = await _get(s.server);
    expect(rows, hasLength(_tills(s.db, [SeedIds.zamalek]).length));
    expect(rows.every((r) => r['branch_id'] == SeedIds.zamalek), isTrue);
    final named = await _get(s.server, branch: SeedIds.zamalek);
    expect(named, hasLength(rows.length));
    final e = await _refused(_get(s.server, branch: SeedIds.maadi));
    expect(e.status, 403);
  });

  test('till.read alone: only the caller\'s own drawers', () async {
    final s = tillsServer(persona: Persona.limited);
    final rows = await _get(s.server);
    expect(rows, isNotEmpty);
    expect(rows.every((r) => r['teller_id'] == SeedIds.limited), isTrue);
    expect(rows.every((r) => r['branch_id'] == SeedIds.maadi), isTrue);
  });

  test('`to` before `from`: a 400', () async {
    final s = tillsServer();
    final e = await _refused(_get(s.server, from: _to, to: _from));
    expect(e.status, 400);
    expect(e.message, contains('`to` is before `from`'));
  });

  test('more than $maxTillSessions sessions: a 400, never a cut list',
      () async {
    final s = tillsServer();
    final base = s.db['tills'].rows.last;
    final opened = DateTime.parse('${base['opened_at']}');
    s.db['tills'].insertAll([
      for (var i = 0; i < maxTillSessions; i++)
        {
          ...base,
          'id': 'bulk-$i',
          'opened_at': opened
              .subtract(Duration(minutes: i))
              .toIso8601String(),
        },
    ]);
    final e = await _refused(_get(s.server));
    expect(e.status, 400);
    expect(e.message, contains('More than $maxTillSessions'));
  });
}
