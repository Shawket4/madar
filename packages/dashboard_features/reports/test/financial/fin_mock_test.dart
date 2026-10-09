// The Financial mock handlers against figures computed by hand from the
// core seed's rows and the area seed, so the page agrees with the other
// report pages and with the backend's gates, scoping, validation and
// state (SPEC 3.2).
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show allBranchesId;
import 'package:dashboard_reports/src/area_seed.dart';
import 'package:dashboard_reports/src/mock/financial_mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final _from = DateTime.utc(2026, 9, 8, 21);
final _to = DateTime.utc(2026, 10, 8, 20, 59, 59);

Map<String, List<String>> _range([Map<String, String> more = const {}]) => {
  'from': [_from.toIso8601String()],
  'to': [_to.toIso8601String()],
  for (final e in more.entries) e.key: [e.value],
};

Future<ApiResponse> _send(
  MockServer s,
  String method,
  String path, {
  Map<String, List<String>>? query,
  Object? body,
  Map<String, String> headers = const {},
}) => s.send(
  ApiRequest(
    method: method,
    path: path,
    query: query ?? _range(),
    body: body,
    headers: headers,
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

Object? _json(ApiResponse r) => jsonDecode(utf8.decode(r.bodyBytes));

Map<String, Object?> _obj(ApiResponse r) =>
    (_json(r)! as Map).cast<String, Object?>();

List<Map<String, Object?>> _list(ApiResponse r) => [
  for (final e in _json(r)! as List) (e as Map).cast<String, Object?>(),
];

/// The sold orders of [branches] in the period, by hand.
List<MockRow> _sold(MockDb db, Iterable<String> branches) => [
  for (final o in db['orders'].rows)
    if (branches.contains(o['branch_id']) &&
        o['status'] != 'voided' &&
        o['status'] != 'refunded' &&
        !DateTime.parse(o['created_at']! as String).isBefore(_from) &&
        !DateTime.parse(o['created_at']! as String).isAfter(_to))
      o,
];

void main() {
  final org = SeedIds.sabahOrg;
  const ledger = '/insights/branches/$allBranchesId/menu-margin';

  group('ledger (REP-FIN-007, 011…014)', () {
    test('revenue is every sold line in the period; margin is revenue less '
        'the snapshot cost over the costed rows', () async {
      final s = finServer();
      final r = MarginLedgerReport.fromJson(
        _obj(await _send(s.server, 'GET', ledger)),
      );
      var revenue = 0;
      for (final o in _sold(s.db, SeedIds.sabahBranches)) {
        for (final l in MockSeed.instance.orderItems(o['id']! as String)) {
          if (l.menuItemId case final id? when seedMenuItemById(id) != null) {
            revenue += l.lineTotal;
          }
        }
      }
      expect(r.totals.revenue, revenue);
      expect(r.rows.fold<int>(0, (a, x) => a + x.revenue), revenue);
      var margin = 0;
      var known = 0;
      for (final x in r.rows) {
        final unit = menuUnitCost(
          seedMenuItemById(x.menuItemId)!.key,
          x.sizeLabel,
        );
        if (unit == null || x.quantitySold == 0) continue;
        expect(x.cost, unit * x.quantitySold, reason: x.itemName);
        margin += x.revenue - unit * x.quantitySold;
        known += x.revenue;
      }
      expect(r.totals.marginKnown, margin);
      expect(r.totals.marginPct, closeTo(margin / known * 100, 1e-9));
      // v60 and shakshuka sold with no recipe cost.
      expect(r.rowsCostUnknown, 2);
      expect(r.targetPct, finSeedOrgTargetPct);
      expect(r.targetSource, 'org');
    });

    test(
      'Today\'s costs re-cost the coffee drinks; a bad basis is refused',
      () async {
        final s = finServer();
        final snap = MarginLedgerReport.fromJson(
          _obj(await _send(s.server, 'GET', ledger)),
        );
        final cur = MarginLedgerReport.fromJson(
          _obj(
            await _send(
              s.server,
              'GET',
              ledger,
              query: _range({'cost_basis': 'current'}),
            ),
          ),
        );
        expect(cur.costBasis, 'current');
        expect(cur.totals.revenue, snap.totals.revenue);
        expect(cur.totals.marginKnown, lessThan(snap.totals.marginKnown));
        final e = await _refused(
          _send(s.server, 'GET', ledger, query: _range({'cost_basis': 'x'})),
        );
        expect(e.status, 400);
      },
    );

    test(
      'Zamalek ranks against its own 72% override; Maadi against the org',
      () async {
        final s = finServer();
        final z = MarginLedgerReport.fromJson(
          _obj(
            await _send(
              s.server,
              'GET',
              '/insights/branches/${SeedIds.zamalek}/menu-margin',
            ),
          ),
        );
        expect(
          (z.targetPct, z.targetSource),
          (finSeedZamalekTargetPct, 'branch'),
        );
        final m = MarginLedgerReport.fromJson(
          _obj(
            await _send(
              s.server,
              'GET',
              '/insights/branches/${SeedIds.maadi}/menu-margin',
            ),
          ),
        );
        expect((m.targetPct, m.targetSource), (finSeedOrgTargetPct, 'org'));
      },
    );

    test('a manager sees only Zamalek; a branch outside is refused', () async {
      final s = finServer(persona: Persona.manager);
      final e = await _refused(
        _send(
          s.server,
          'GET',
          '/insights/branches/${SeedIds.maadi}/menu-margin',
        ),
      );
      expect(e.status, 403);
    });
  });

  group('decisions and targets (REP-FIN-030…041, 050)', () {
    test('a dismissal is logged first and silences that flag on the next '
        'ledger', () async {
      final s = finServer();
      final before = MarginLedgerReport.fromJson(
        _obj(await _send(s.server, 'GET', ledger)),
      );
      final row = before.rows.firstWhere(
        (r) => r.flags.any((f) => f.kind == 'below_target'),
      );
      final res = await _send(
        s.server,
        'POST',
        '/insights/decisions',
        query: {
          'org_id': [org],
        },
        body: {
          'branch_id': null,
          'menu_item_id': row.menuItemId,
          'size_label': row.sizeLabel,
          'signal_kind': 'below_target',
          'action': 'dismissed',
          'detail': {},
        },
      );
      expect(res.status, 201);
      final log = _list(
        await _send(
          s.server,
          'GET',
          '/insights/decisions',
          query: {
            'org_id': [org],
          },
        ),
      );
      expect(log.first['menu_item_id'], row.menuItemId);
      expect(log.first['action'], 'dismissed');
      expect(log.first['impact'], isNull, reason: 'measuring');
      final after = MarginLedgerReport.fromJson(
        _obj(await _send(s.server, 'GET', ledger)),
      );
      final again = after.rows.firstWhere(
        (r) => r.menuItemId == row.menuItemId && r.sizeLabel == row.sizeLabel,
      );
      expect(again.flags.map((f) => f.kind), isNot(contains('below_target')));
    });

    test('a branch\'s log holds only its own decisions', () async {
      final s = finServer();
      final z = _list(
        await _send(
          s.server,
          'GET',
          '/insights/decisions',
          query: {
            'org_id': [org],
            'branch_id': [SeedIds.zamalek],
          },
        ),
      );
      expect(z.map((d) => d['branch_id']).toSet(), {SeedIds.zamalek});
    });

    test('a manager cannot record a decision or move the target', () async {
      final s = finServer(persona: Persona.manager);
      final e = await _refused(
        _send(
          s.server,
          'PUT',
          '/insights/margin-target',
          query: {
            'org_id': [org],
          },
          body: {'target_pct': 70},
        ),
      );
      expect(e.status, 403);
    });

    test('the org target moves the ledger; 0 and 100 are refused', () async {
      final s = finServer();
      Future<ApiResponse> put(num pct) => _send(
        s.server,
        'PUT',
        '/insights/margin-target',
        query: {
          'org_id': [org],
        },
        body: {'target_pct': pct},
      );
      expect((await _refused(put(0))).status, 400);
      expect((await _refused(put(100))).status, 400);
      final t = MarginTargets.fromJson(_obj(await put(55.5)));
      expect(t.orgDefaultPct, 55.5);
      final r = MarginLedgerReport.fromJson(
        _obj(await _send(s.server, 'GET', ledger)),
      );
      expect(r.targetPct, 55.5);
    });
  });

  group('sales (REP-FIN-055…064)', () {
    test('the daily series, the peak hours and the channels add up to the '
        'sold orders\' totals', () async {
      final s = finServer();
      final sold = _sold(s.db, SeedIds.sabahBranches);
      final total = sold.fold<int>(
        0,
        (a, o) => a + (o['total_amount']! as num).toInt(),
      );
      final series = _list(
        await _send(
          s.server,
          'GET',
          '/reports/branches/$allBranchesId/sales/timeseries',
          query: _range({'granularity': 'daily'}),
        ),
      );
      expect(series.fold<int>(0, (a, p) => a + (p['revenue']! as int)), total);
      expect(
        series.fold<int>(0, (a, p) => a + (p['orders']! as int)),
        sold.length,
      );
      final hours = _list(
        await _send(
          s.server,
          'GET',
          '/reports/branches/$allBranchesId/sales/peak-hours',
        ),
      );
      expect(hours, hasLength(24));
      expect(hours.fold<int>(0, (a, p) => a + (p['revenue']! as int)), total);
      final days = _list(
        await _send(
          s.server,
          'GET',
          '/reports/branches/$allBranchesId/sales/peak-days',
        ),
      );
      expect(days, hasLength(7));
      expect(
        days.fold<int>(0, (a, p) => a + (p['orders']! as int)),
        sold.length,
      );
      final channels = _list(
        await _send(
          s.server,
          'GET',
          '/reports/branches/$allBranchesId/channel-breakdown',
        ),
      );
      expect(
        channels.fold<int>(0, (a, c) => a + (c['revenue']! as int)),
        total,
      );
    });

    test('REP-ALL-027 the 11th export read in a minute is throttled', () async {
      final s = finServer();
      Future<ApiResponse> read() => _send(
        s.server,
        'GET',
        '/reports/branches/$allBranchesId/channel-breakdown',
        headers: {'X-Madar-Export': '1'},
      );
      for (var i = 0; i < finExportPerMinute; i++) {
        expect((await read()).status, 200);
      }
      final e = await _refused(read());
      expect((e.status, e.code), (429, 'EXPORT_RATE_LIMITED'));
      // An on-screen read is never counted.
      expect(
        (await _send(
          s.server,
          'GET',
          '/reports/branches/$allBranchesId/channel-breakdown',
        )).status,
        200,
      );
    });
  });

  group('inventory (REP-FIN-066…069)', () {
    test('the org\'s stock value is the four branches\' together', () async {
      final s = finServer();
      final o = InventoryValuationReport.fromJson(
        _obj(
          await _send(
            s.server,
            'GET',
            '/reports/orgs/$org/inventory-valuation',
            query: const {},
          ),
        ),
      );
      var sum = 0;
      var unknown = 0;
      for (final b in SeedIds.sabahBranches) {
        final r = InventoryValuationReport.fromJson(
          _obj(
            await _send(
              s.server,
              'GET',
              '/reports/branches/$b/inventory-valuation',
              query: const {},
            ),
          ),
        );
        sum += r.totalValue;
        unknown = r.unknownCostCount;
      }
      // Rounding per branch vs once on the summed stock: within a piastre
      // per ingredient.
      expect((o.totalValue - sum).abs(), lessThan(o.items.length));
      expect(o.unknownCostCount, unknown);
      expect(o.items.fold<int>(0, (a, i) => a + (i.value ?? 0)), o.totalValue);
    });

    test('the org\'s supplier spend is its branches\' spend', () async {
      final s = finServer();
      final o = _list(
        await _send(s.server, 'GET', '/reports/orgs/$org/supplier-spend'),
      );
      var sum = 0;
      for (final b in SeedIds.sabahBranches) {
        sum += _list(
          await _send(s.server, 'GET', '/reports/branches/$b/supplier-spend'),
        ).fold<int>(0, (a, r) => a + (r['total_spend']! as int));
      }
      expect(o.fold<int>(0, (a, r) => a + (r['total_spend']! as int)), sum);
    });

    test(
      'the trend lists three straight rises with the base and the rise',
      () async {
        final s = finServer();
        final rows = [
          for (final r in _list(
            await _send(
              s.server,
              'GET',
              '/reports/orgs/$org/material-cost-trend',
            ),
          ))
            MaterialCostTrendRow.fromJson(r),
        ];
        expect(rows, isNotEmpty);
        for (final r in rows) {
          expect(r.streakLength, greaterThanOrEqualTo(3));
          expect(
            r.pctIncrease,
            closeTo((r.currentCost - r.baseCost) / r.baseCost * 100, 0.05),
          );
        }
      },
    );

    test('a person without purchasing.orders.read is refused spend', () async {
      final s = finServer(persona: Persona.limited);
      final e = await _refused(
        _send(s.server, 'GET', '/reports/orgs/$org/supplier-spend'),
      );
      expect(e.status, 403);
      final v = await _refused(
        _send(
          s.server,
          'GET',
          '/reports/orgs/$org/inventory-valuation',
          query: const {},
        ),
      );
      expect(v.status, 403);
    });
  });
}
