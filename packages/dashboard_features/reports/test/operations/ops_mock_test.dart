// The Operations mock handlers against figures computed by hand from the
// core seed's rows, so the page agrees with the home's numbers and the
// backend's gates, scoping and errors (SPEC 3.2).
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show allBranchesId;
import 'package:dashboard_reports/src/mock/operations_mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final _from = DateTime.utc(2026, 9, 8, 21);
final _to = DateTime.utc(2026, 10, 8, 20, 59, 59);

Map<String, List<String>> _range([Map<String, String> more = const {}]) => {
  'from': [_from.toIso8601String()],
  'to': [_to.toIso8601String()],
  for (final e in more.entries) e.key: [e.value],
};

Future<ApiResponse> _get(
  MockServer s,
  String path, {
  Map<String, List<String>>? query,
  Map<String, String> headers = const {},
}) => s.send(
  ApiRequest(
    method: 'GET',
    path: path,
    query: query ?? _range(),
    headers: headers,
  ),
);

/// The refusal [f] ends in (the transport throws on a non-2xx).
Future<ApiException> _refused(Future<ApiResponse> f) async {
  try {
    final r = await f;
    fail('expected a refusal, got ${r.status}');
  } on ApiException catch (e) {
    return e;
  }
}

Object? _json(ApiResponse r) => jsonDecode(utf8.decode(r.bodyBytes));

/// The seed's orders in the period, by hand.
List<MockRow> _seedOrders(MockDb db, Iterable<String> branches) => [
  for (final o in db['orders'].rows)
    if (branches.contains(o['branch_id']) &&
        !DateTime.parse(o['created_at']! as String).isBefore(_from) &&
        !DateTime.parse(o['created_at']! as String).isAfter(_to))
      o,
];

bool _sold(MockRow o) => o['status'] != 'voided' && o['status'] != 'refunded';

int _sum(Iterable<MockRow> rows, String field) =>
    rows.fold(0, (s, o) => s + ((o[field] as num?)?.toInt() ?? 0));

void main() {
  group('branch sales (REP-OPS-034…045)', () {
    test('the totals are the seed\'s sold set: revenue, orders, voids, tax, '
        'methods, line items', () async {
      final s = opsServer();
      final res = await _get(s.server, '/reports/branches/$allBranchesId/sales');
      expect(res.status, 200);
      final r = BranchSalesReport.fromJson(
        (_json(res)! as Map).cast<String, Object?>(),
      );
      final orders = _seedOrders(s.db, SeedIds.sabahBranches);
      final sold = orders.where(_sold).toList();
      expect(r.totalOrders, sold.length);
      expect(r.voidedOrders, orders.where((o) => o['status'] == 'voided').length);
      expect(r.totalRevenue, _sum(sold, 'total_amount'));
      expect(r.totalTax, _sum(sold, 'tax_amount'));
      final methods = (r.revenueByMethod as Map).values.fold<num>(
        0,
        (a, b) => a + (b as num),
      );
      expect(methods, r.totalRevenue);
      var lines = 0;
      for (final o in sold) {
        for (final l in MockSeed.instance.orderItems(o['id']! as String)) {
          // Every seed line names its item, so this is the home's count too.
          expect(l.menuItemId, isNotNull);
          lines += l.quantity;
        }
      }
      expect(r.totalLineItems, lines);
      // Categories add up to the items' revenue; top items by quantity.
      final cats = r.byCategory.fold<int>(0, (a, c) => a + c.revenue);
      final items = r.byCategory
          .expand((c) => c.items)
          .fold<int>(0, (a, i) => a + i.revenue);
      expect(cats, items);
      final qty = [for (final i in r.topItems) i.quantitySold];
      expect(qty, [...qty]..sort((a, b) => b.compareTo(a)));
    });

    test('one branch = its own orders; the four add up to all', () async {
      final s = opsServer();
      var total = 0;
      for (final b in SeedIds.sabahBranches) {
        final r = BranchSalesReport.fromJson(
          (_json(await _get(s.server, '/reports/branches/$b/sales'))! as Map)
              .cast<String, Object?>(),
        );
        expect(
          r.totalRevenue,
          _sum(_seedOrders(s.db, [b]).where(_sold), 'total_amount'),
        );
        total += r.totalRevenue;
      }
      final all = BranchSalesReport.fromJson(
        (_json(await _get(s.server, '/reports/branches/$allBranchesId/sales'))!
                as Map)
            .cast<String, Object?>(),
      );
      expect(all.totalRevenue, total);
    });

    test('exclude_items narrows only the line-item count; a bad id is a 400',
        () async {
      final s = opsServer();
      final latte = MockSeed.menuItemId('latte');
      final base = (_json(await _get(
        s.server,
        '/reports/branches/$allBranchesId/sales',
      ))! as Map);
      final ex = (_json(await _get(
        s.server,
        '/reports/branches/$allBranchesId/sales',
        query: _range({'exclude_items': latte}),
      ))! as Map);
      expect(ex['total_revenue'], base['total_revenue']);
      expect(ex['total_orders'], base['total_orders']);
      expect(ex['total_line_items'], lessThan(base['total_line_items'] as num));
      final bad = await _refused(
        _get(
          s.server,
          '/reports/branches/$allBranchesId/sales',
          query: _range({'exclude_items': 'latte'}),
        ),
      );
      expect(bad.status, 400);
    });

    test('a manager: the sentinel is their branch; another branch is '
        'refused', () async {
      final s = opsServer(persona: Persona.manager);
      final r = (_json(await _get(
        s.server,
        '/reports/branches/$allBranchesId/sales',
      ))! as Map);
      expect(
        r['total_revenue'],
        _sum(_seedOrders(s.db, [SeedIds.zamalek]).where(_sold), 'total_amount'),
      );
      final other = await _refused(
        _get(s.server, '/reports/branches/${SeedIds.maadi}/sales'),
      );
      expect(other.status, 403);
    });

    test('refusals by persona: another org\'s branch is refused, a deleted '
        'branch is not found; the sentinel covers only the org in scope',
        () async {
      // Every seeded persona holds orders.read, so that gate cannot be
      // driven by one; these are the refusals the personas do reach.
      final s = opsServer(persona: Persona.dawamOnly);
      final other = await _refused(
        _get(s.server, '/reports/branches/${SeedIds.zamalek}/sales'),
      );
      // The backend's order (authz/scope.rs): another org's branch is a 403.
      expect(other.status, 403);
      final mine = (_json(await _get(
        s.server,
        '/reports/branches/$allBranchesId/sales',
      ))! as Map);
      expect(mine['total_orders'], 0);
      final comparison = await _refused(
        _get(s.server, '/reports/orgs/${SeedIds.sabahOrg}/comparison'),
      );
      expect(comparison.status, 403);
      final o = opsServer();
      o.db['branches'].update(SeedIds.maadi, {
        'deleted_at': o.db.nowIso,
      });
      final gone = await _refused(
        _get(o.server, '/reports/branches/${SeedIds.maadi}/tellers'),
      );
      expect(gone.status, 404);
      final all = (_json(await _get(
        o.server,
        '/reports/branches/$allBranchesId/sales',
      ))! as Map);
      expect(
        all['total_revenue'],
        _sum(
          _seedOrders(o.db, [
            SeedIds.heliopolis,
            SeedIds.newCairo,
            SeedIds.zamalek,
          ]).where(_sold),
          'total_amount',
        ),
      );
    });

    test('refusals by persona: a teller without the floor or ticket reads',
        () async {
      final l = opsServer(persona: Persona.limited);
      final floor = await _refused(
        _get(
          l.server,
          '/floor/tables',
          query: {
            'branch_id': [SeedIds.maadi],
          },
        ),
      );
      expect(floor.status, 403);
      final t1 = opsTables.firstWhere(
        (t) => t.branchKey == 'maadi' && t.label == 'T1',
      );
      final history = await _refused(
        _get(l.server, '/floor/tables/${t1.id}/history'),
      );
      expect(history.status, 403);
    });
  });

  group('the analytics reads (REP-OPS-047…055, 066)', () {
    test('tellers add up to the revenue; waiters are a subset', () async {
      final s = opsServer();
      final sold = _seedOrders(s.db, SeedIds.sabahBranches).where(_sold);
      final tellers = (_json(await _get(
        s.server,
        '/reports/branches/$allBranchesId/tellers',
      ))! as List);
      expect(
        tellers.fold<num>(0, (a, t) => a + ((t as Map)['revenue'] as num)),
        _sum(sold, 'total_amount'),
      );
      final w = WaiterStatsReport.fromJson(
        (_json(await _get(
          s.server,
          '/reports/branches/$allBranchesId/waiters',
        ))! as Map).cast<String, Object?>(),
      );
      expect(w.totalOrders, sold.length);
      expect(w.attributedOrders, w.waiters.fold<int>(0, (a, x) => a + x.orders));
      expect(w.attributedOrders, lessThan(w.totalOrders));
      // Only dine-in orders carry a waiter.
      final dineIn = sold.where((o) => o['order_type'] == 'dine_in').length;
      expect(w.attributedOrders, lessThanOrEqualTo(dineIn));
    });

    test('items-combined: most sold first; add-ons with revenue', () async {
      final s = opsServer();
      final items = (_json(await _get(
        s.server,
        '/reports/branches/$allBranchesId/items-combined',
        query: _range({'limit': '50'}),
      ))! as List);
      final qty = [for (final i in items) (i as Map)['total_qty'] as num];
      expect(qty, [...qty]..sort((a, b) => b.compareTo(a)));
      final addons = (_json(await _get(
        s.server,
        '/reports/branches/$allBranchesId/addons',
        query: _range({'limit': '20'}),
      ))! as List);
      expect(addons, isNotEmpty);
      expect(((addons.first as Map)['revenue'] as num), greaterThan(0));
    });

    test('the comparison: every org branch even for a manager; another org '
        'is refused', () async {
      final s = opsServer(persona: Persona.manager);
      final r = OrgComparisonReport.fromJson(
        (_json(await _get(
          s.server,
          '/reports/orgs/${SeedIds.sabahOrg}/comparison',
        ))! as Map).cast<String, Object?>(),
      );
      expect(r.branches, hasLength(4));
      final all = _seedOrders(s.db, SeedIds.sabahBranches).where(_sold);
      expect(
        r.branches.fold<int>(0, (a, b) => a + b.totalRevenue),
        _sum(all, 'total_amount'),
      );
      final v = r.branches.first;
      expect(
        v.voidRatePct,
        closeTo(v.voidedOrders / (v.voidedOrders + v.totalOrders) * 100, 1e-9),
      );
      final other = await _refused(
        _get(s.server, '/reports/orgs/another/comparison'),
      );
      expect(other.status, 403);
    });

    test('the export throttle: ten counted reads a minute, then 429', () async {
      final s = opsServer();
      for (var i = 0; i < opsExportMaxPerMinute; i++) {
        final r = await _get(
          s.server,
          '/reports/branches/$allBranchesId/tellers',
          headers: const {'X-Madar-Export': '1'},
        );
        expect(r.status, 200, reason: '$i');
      }
      final r = await _refused(
        _get(
          s.server,
          '/reports/branches/$allBranchesId/tellers',
          headers: const {'X-Madar-Export': '1'},
        ),
      );
      expect(r.status, 429);
      expect(r.code, 'EXPORT_RATE_LIMITED');
      // An ordinary read is never counted.
      final plain = await _get(
        s.server,
        '/reports/branches/$allBranchesId/tellers',
      );
      expect(plain.status, 200);
      s.db.clock.advance(const Duration(minutes: 1));
      final later = await _get(
        s.server,
        '/reports/branches/$allBranchesId/tellers',
        headers: const {'X-Madar-Export': '1'},
      );
      expect(later.status, 200);
    });
  });

  group('the tables dataset (REP-OPS-006)', () {
    Future<ApiResponse> query(
      MockServer s,
      List<Map<String, Object?>> widgets, {
      String? branch,
    }) => s.send(
      ApiRequest(
        method: 'POST',
        path: '/metrics/query',
        headers: {'X-Branch-Id': ?branch},
        body: {
          'locale': 'en',
          'period': {
            'from': _from.toIso8601String(),
            'to': _to.toIso8601String(),
          },
          'widgets': widgets,
        },
      ),
    );

    Map<String, Object?> summary(Object? body) =>
        ((((body! as Map)['results'] as Map)['s'] as Map)['rows'] as List)
            .first as Map<String, Object?>;

    test('turns = the settled dine-in bills at a table; revenue their '
        'totals; every dine-in order sat at a table', () async {
      final s = opsServer();
      final r = await query(s.server, [
        {
          'key': 's',
          'spec': {
            'dataset': 'tables',
            'measures': [
              'turns',
              'covers',
              'table_revenue',
              'active_tables',
              'revenue_per_cover',
            ],
          },
        },
      ]);
      expect(r.status, 200);
      final m = summary(_json(r));
      final dineIn = _seedOrders(s.db, SeedIds.sabahBranches)
          .where((o) => _sold(o) && o['order_type'] == 'dine_in')
          .toList();
      expect(m['turns'], dineIn.length);
      expect(m['table_revenue'], _sum(dineIn, 'total_amount'));
      expect(
        m['revenue_per_cover'],
        ((m['table_revenue']! as num) / (m['covers']! as num)).round(),
      );
      expect(m['active_tables'], greaterThan(10));
      for (final o in dineIn) {
        expect(OpsSeed.instance.sittingOf(o['id']! as String), isNotNull);
      }
    });

    test('the branch comes from X-Branch-Id; a manager sees only theirs',
        () async {
      final s = opsServer();
      final spec = [
        {
          'key': 's',
          'spec': {
            'dataset': 'tables',
            'measures': ['turns'],
          },
        },
      ];
      final one = summary(_json(await query(
        s.server,
        spec,
        branch: SeedIds.maadi,
      )));
      final maadi = _seedOrders(s.db, [SeedIds.maadi])
          .where((o) => _sold(o) && o['order_type'] == 'dine_in')
          .length;
      expect(one['turns'], maadi);
      final m = opsServer(persona: Persona.manager);
      final mine = summary(_json(await query(m.server, spec)));
      final zamalek = _seedOrders(m.db, [SeedIds.zamalek])
          .where((o) => _sold(o) && o['order_type'] == 'dine_in')
          .length;
      expect(mine['turns'], zamalek);
    });

    test('a widget that cannot run fails inside the 200; no widgets is a 400; '
        'reports.read is required', () async {
      final s = opsServer();
      final r = await query(s.server, [
        {
          'key': 'bad',
          'spec': {
            'dataset': 'tables',
            'measures': ['tips'],
          },
        },
      ]);
      expect(r.status, 200);
      final bad = ((_json(r)! as Map)['results'] as Map)['bad'] as Map;
      expect(bad['status'], 'error');
      expect(bad['error'], contains('tips'));
      expect((await _refused(query(s.server, const []))).status, 400);
      final dawam = opsServer(persona: Persona.limited);
      // The limited persona holds reports.read; refuse it to check the gate.
      dawam.server.fail(
        'POST',
        metricsRoute,
        MockResponse.denied('reports.read'),
      );
      expect((await _refused(query(dawam.server, const []))).status, 403);
    });

    test('by section + table: "No section" for a table outside any, sorted '
        'by turns', () async {
      final s = opsServer();
      final r = await query(s.server, [
        {
          'key': 's',
          'spec': {
            'dataset': 'tables',
            'dimensions': ['section', 'table'],
            'measures': ['turns'],
            'sort': {'measure': 'turns', 'dir': 'desc'},
            'limit': 500,
          },
        },
      ], branch: SeedIds.zamalek);
      final rows =
          (((_json(r)! as Map)['results'] as Map)['s'] as Map)['rows'] as List;
      expect(rows.any((x) => (x as Map)['section'] == 'No section'), isTrue);
      final turns = [for (final x in rows) (x as Map)['turns'] as num];
      expect(turns, [...turns]..sort((a, b) => b.compareTo(a)));
    });
  });

  test('REP-OPS-025/027/030 one sittings model: every table\'s ledger turns '
      'and revenue equal its history\'s settled bills, and both equal the '
      'core seed\'s sittings (the model the floor\'s history reads)', () async {
    final s = opsServer();
    for (final b in SeedIds.sabahBranches) {
      final res = await s.server.send(
        ApiRequest(
          method: 'POST',
          path: '/metrics/query',
          headers: {'X-Branch-Id': b},
          body: {
            'locale': 'en',
            'period': {
              'from': _from.toIso8601String(),
              'to': _to.toIso8601String(),
            },
            'widgets': [
              {
                'key': 't',
                'spec': {
                  'dataset': 'tables',
                  'dimensions': ['section', 'table'],
                  'measures': ['turns', 'table_revenue'],
                  'limit': 500,
                },
              },
            ],
          },
        ),
      );
      final rows =
          (((_json(res)! as Map)['results'] as Map)['t'] as Map)['rows']
              as List;
      expect(rows, isNotEmpty);
      for (final r in rows.cast<Map<String, Object?>>()) {
        final t = opsTables.firstWhere(
          (x) => x.branchId == b && x.label == r['table'],
        );
        // The shared model, by hand: settled dine-in sittings at the table.
        final shared = [
          for (final o in MockSeed.instance.orders)
            if (MockSeed.instance.sittingOf(o.id) case final st?
                when st.tableId == t.id &&
                    o.status != 'voided' &&
                    !st.seatedAt.isBefore(_from) &&
                    st.seatedAt.isBefore(_to))
              o,
        ];
        expect(r['turns'], shared.length, reason: '${t.branchKey} ${t.label}');
        expect(
          r['table_revenue'],
          shared.fold<int>(0, (a, o) => a + o.totalAmount),
        );
        if (t.retired != null) continue;
        final h = TableHistory.fromJson(
          (_json(await _get(
            s.server,
            '/floor/tables/${t.id}/history',
            query: _range(),
          ))! as Map).cast<String, Object?>(),
        );
        expect(h.settledCount, r['turns'], reason: '${t.branchKey} ${t.label}');
        expect(h.totalMinor, r['table_revenue']);
      }
    }
  });

  test('the plan is the one the floor lists: the core seed\'s active, '
      'unretired tables', () async {
    final s = opsServer();
    for (final b in SeedIds.sabahBranches) {
      final listed = [
        for (final t
            in _json(await _get(
                  s.server,
                  '/floor/tables',
                  query: {
                    'branch_id': [b],
                  },
                ))!
                as List)
          (t as Map)['id'],
      ]..sort();
      expect(listed, [
        for (final t in seedFloorTables)
          if (t.branchId == b && t.retired == null) t.id,
      ]..sort());
    }
  });

  group('the floor (REP-OPS-025…031)', () {
    test('the plan per branch, retired tables left out; branch_id is '
        'required; floor read is required', () async {
      final s = opsServer();
      final r = await _get(
        s.server,
        '/floor/tables',
        query: {
          'branch_id': [SeedIds.zamalek],
        },
      );
      expect(r.status, 200);
      final labels = [for (final t in _json(r)! as List) (t as Map)['label']];
      expect(labels, isNot(contains('T10')));
      expect(labels, contains('Bar 1'));
      expect(
        (await _refused(_get(s.server, '/floor/tables', query: const {})))
            .status,
        400,
      );
      final l = opsServer(persona: Persona.limited);
      expect(
        (await _refused(
          _get(
            l.server,
            '/floor/tables',
            query: {
              'branch_id': [SeedIds.maadi],
            },
          ),
        )).status,
        403,
      );
    });

    test('a table\'s history: settled bills count, open and voided are '
        'listed; a retired table is a 404', () async {
      final s = opsServer();
      final t1 = opsTables.firstWhere(
        (t) => t.branchKey == 'heliopolis' && t.label == 'T1',
      );
      final r = TableHistory.fromJson(
        (_json(await _get(s.server, '/floor/tables/${t1.id}/history'))! as Map)
            .cast<String, Object?>(),
      );
      final settled = r.sittings.where((x) => x.totalAmount != null).toList();
      expect(r.settledCount, settled.length);
      expect(
        r.totalMinor,
        settled.fold<int>(0, (a, x) => a + x.totalAmount!),
      );
      expect(r.averageBillMinor, r.totalMinor ~/ settled.length);
      expect(r.sittings.any((x) => x.status == 'open'), isTrue);
      final t10 = opsTables.firstWhere(
        (t) => t.branchKey == 'zamalek' && t.label == 'T10',
      );
      expect(
        (await _refused(_get(s.server, '/floor/tables/${t10.id}/history')))
            .status,
        404,
      );
    });
  });
}
