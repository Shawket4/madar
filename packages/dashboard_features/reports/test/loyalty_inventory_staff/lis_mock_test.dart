// The unit's mock handlers against hand-computed figures: the backend's
// gates, scoping, sorting and validation, and figures that agree with the
// core seed and the area seed.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show ensureTimeZones;
import 'package:dashboard_reports/src/area_seed.dart';
import 'package:dashboard_reports/src/mock/loyalty_inventory_staff_mock.dart';
import 'package:flutter_test/flutter_test.dart';

({MockServer server, MockDb db}) _server([Persona p = Persona.owner]) {
  final db = MockDb.seeded();
  final server = MockServer(persona: p, clock: db.clock);
  registerCoreMocks(server, db);
  registerLoyaltyInventoryStaffMocks(server, db);
  return (server: server, db: db);
}

Future<(int, Object?)> _get(
  MockServer s,
  String path, [
  Map<String, String> q = const {},
]) async {
  try {
    final r = await s.send(
      ApiRequest(
        method: 'GET',
        path: path,
        query: {
          for (final e in q.entries) e.key: [e.value],
        },
      ),
    );
    return (r.status, jsonDecode(utf8.decode(r.bodyBytes)) as Object?);
  } on ApiException catch (e) {
    return (e.status, e.code);
  }
}

const _from = '2026-09-08T21:00:00.000Z';
const _to = '2026-10-08T20:59:59.999Z';
const _range = {'from': _from, 'to': _to};

void main() {
  setUpAll(ensureTimeZones);

  group('loyalty', () {
    test('behaviour: the ledger\'s sums, org-wide counts kept', () async {
      final s = _server();
      final (status, body) = await _get(s.server, '/loyalty/behavior', _range);
      expect(status, 200);
      final b = LoyaltyBehavior.fromJson(body! as Map<String, Object?>);
      final members = loyaltyMembers(s.db, SeedIds.sabahOrg);
      expect(b.totalMembers, members.length);
      expect(b.totalMembers, greaterThan(50));
      expect(b.activeMembers, greaterThan(0));
      expect(
        b.activeMemberRate,
        closeTo(b.activeMembers / b.totalMembers, 1e-9),
      );
      expect(
        b.repeatVisitRate,
        closeTo(b.repeatMembers / (b.repeatMembers + b.oneTimeMembers), 1e-9),
      );
      expect(b.newMembersActive + b.returningMembersActive, b.activeMembers);
      expect(b.newMembersActive, greaterThan(0));
      expect(b.redemptionRatio, greaterThan(0));
      expect(b.redemptionRatio, lessThan(1));

      // One branch: activity narrows, the membership totals do not.
      final (_, one) = await _get(s.server, '/loyalty/behavior', {
        ..._range,
        'branch_id': SeedIds.maadi,
      });
      final m = LoyaltyBehavior.fromJson(one! as Map<String, Object?>);
      expect(m.totalMembers, b.totalMembers);
      expect(m.membersEverRedeemed, b.membersEverRedeemed);
      expect(m.activeMembers, lessThan(b.activeMembers));
    });

    test(
      'a manager counts only her branch; another branch is refused',
      () async {
        final owner = _server();
        final mgr = _server(Persona.manager);
        final (_, zm) = await _get(owner.server, '/loyalty/behavior', {
          ..._range,
          'branch_id': SeedIds.zamalek,
        });
        final (_, mine) = await _get(mgr.server, '/loyalty/behavior', _range);
        expect(
          (mine! as Map)['active_members'],
          (zm! as Map)['active_members'],
        );
        final (status, _) = await _get(mgr.server, '/loyalty/behavior', {
          ..._range,
          'branch_id': SeedIds.maadi,
        });
        expect(status, 403);
      },
    );

    test('refusals and validation', () async {
      final s = _server(Persona.limited);
      for (final p in [
        '/loyalty/behavior',
        '/loyalty/campaign-effectiveness',
        '/loyalty/liability-trend',
      ]) {
        expect((await _get(s.server, p, _range)).$1, 403, reason: p);
      }
      final o = _server();
      final (status, _) = await _get(o.server, '/loyalty/behavior', {
        'from': _to,
        'to': _from,
      });
      expect(status, 400);
    });

    test('campaigns: win-back and birthday, return within 30 days', () async {
      final s = _server();
      final (status, body) = await _get(
        s.server,
        '/loyalty/campaign-effectiveness',
        _range,
      );
      expect(status, 200);
      final c = CampaignEffectiveness.fromJson(body! as Map<String, Object?>);
      expect(c.campaigns.map((r) => r.campaign), ['winback', 'birthday']);
      for (final r in c.campaigns) {
        expect(r.sent, greaterThan(0), reason: r.campaign);
        expect(r.returnedWithin30d, lessThanOrEqualTo(r.sent));
        expect(r.returnRate, closeTo(r.returnedWithin30d / r.sent, 1e-9));
      }
    });

    test(
      'liability: weeks from Saturday 00:00 Cairo, summing the ledger',
      () async {
        final s = _server();
        final (status, body) = await _get(
          s.server,
          '/loyalty/liability-trend',
          _range,
        );
        expect(status, 200);
        final l = LiabilityTrend.fromJson(body! as Map<String, Object?>);
        expect(l.currency, 'visits');
        expect(l.points, isNotEmpty);
        for (final p in l.points) {
          final w = MockClock.wall(p.week);
          expect(w.weekday, DateTime.saturday);
          expect((w.hour, w.minute), (0, 0));
        }
        final from = DateTime.parse(_from), to = DateTime.parse(_to);
        final members = loyaltyMembers(s.db, SeedIds.sabahOrg);
        final net = loyaltyLedger(s.db, members)
            .where((t) => !t.at.isBefore(from) && t.at.isBefore(to))
            .fold<int>(0, (a, t) => a + t.points);
        expect(l.points.fold<int>(0, (a, p) => a + p.outstanding), net);
      },
    );
  });

  group('inventory', () {
    test('low-stock and waste-report are the inventory area\'s: kept when it '
        'registered them first; the rest are ours', () async {
      final db = MockDb.seeded();
      final server = MockServer(persona: Persona.owner, clock: db.clock);
      registerCoreMocks(server, db);
      const theirs = [
        '/reports/branches/{branch_id}/low-stock',
        '/reports/orgs/{org_id}/low-stock',
        '/reports/branches/{branch_id}/waste-report',
        '/reports/branches/{branch_id}/consumption',
      ];
      for (final t in theirs) {
        server.on('GET', t, (_) => MockResponse.ok(const ['inventory']));
      }
      registerLoyaltyInventoryStaffMocks(server, db);
      final z = SeedIds.zamalek;
      for (final path in [
        '/reports/branches/$z/low-stock',
        '/reports/orgs/${SeedIds.sabahOrg}/low-stock',
        '/reports/branches/$z/waste-report',
      ]) {
        expect((await _get(server, path, _range)).$2, [
          'inventory',
        ], reason: path);
      }
      final (_, consumption) = await _get(
        server,
        '/reports/branches/$z/consumption',
        _range,
      );
      expect(consumption, isNot(['inventory']));
    });

    test('consumption: daily use at the branch\'s size plus waste', () async {
      final s = _server();
      final (status, body) = await _get(
        s.server,
        '/reports/branches/${SeedIds.zamalek}/consumption',
        _range,
      );
      expect(status, 200);
      final rows = [
        for (final r in body! as List)
          ConsumptionRow.fromJson(r as Map<String, Object?>),
      ];
      final beans = rows.firstWhere(
        (r) => r.orgIngredientId == reportIngredient('espresso_beans').id,
      );
      final wasted = inventoryWaste
          .where(
            (w) =>
                w.branchId == SeedIds.zamalek &&
                w.ingredient == 'espresso_beans' &&
                !w.at.isBefore(DateTime.parse(_from)),
          )
          .fold<double>(0, (a, w) => a + w.qty);
      // 2.4 kg a day × Zamalek's size (74 / 69.25) × the days sold so far
      // (29 whole days and today's first 10 hours).
      final used = 2.4 * (74 / 69.25) * (29 + 10 / 24);
      expect(beans.consumedQty, closeTo(used + wasted, 0.01));
      expect(beans.consumedValue, (beans.consumedQty * 144000).round());
      final chai = rows.firstWhere(
        (r) => r.orgIngredientId == reportIngredient('chai').id,
      );
      expect(chai.consumedValue, isNull);
      // Largest quantity first.
      for (var i = 1; i < rows.length; i++) {
        expect(
          rows[i - 1].consumedQty,
          greaterThanOrEqualTo(rows[i].consumedQty),
        );
      }
    });

    test(
      'the org route rolls up every branch; another org is refused',
      () async {
        final s = _server();
        final (_, org) = await _get(
          s.server,
          '/reports/orgs/${SeedIds.sabahOrg}/waste-report',
          _range,
        );
        final (_, all) = await _get(
          s.server,
          '/reports/branches/00000000-0000-0000-0000-000000000000/waste-report',
          _range,
        );
        expect(jsonEncode(org), jsonEncode(all));
        final (status, _) = await _get(
          s.server,
          '/reports/orgs/${SeedIds.nakhlaOrg}/waste-report',
          _range,
        );
        expect(status, 403);
      },
    );

    test('shrinkage: a missing reason is "unexplained"; values', () async {
      final s = _server();
      final (_, body) = await _get(
        s.server,
        '/reports/orgs/${SeedIds.sabahOrg}/shrinkage',
        _range,
      );
      final rows = [
        for (final r in body! as List)
          ShrinkageRow.fromJson(r as Map<String, Object?>),
      ];
      expect(rows.map((r) => r.reason), contains('unexplained'));
      final chai = rows.where(
        (r) => r.orgIngredientId == reportIngredient('chai').id,
      );
      expect(chai.every((r) => r.shrinkageValue == null), isTrue);
    });

    test('low stock: the three exceptions, by branch then name', () async {
      final s = _server();
      final (_, body) = await _get(
        s.server,
        '/reports/orgs/${SeedIds.sabahOrg}/low-stock',
      );
      final rows = [
        for (final r in body! as List)
          LowStockRow.fromJson(r as Map<String, Object?>),
      ];
      expect(
        [for (final r in rows) (r.branchName, r.ingredientName, r.onHand)],
        [
          ('Maadi', 'Oat milk', -2.0),
          ('New Cairo', 'Whole milk', 31.0),
          ('Zamalek', 'Strawberries', 0.0),
        ],
      );
      final milk = rows[1];
      // 40 L × New Cairo's size (88 / 69.25) = 50.8; order up to 3×.
      expect(milk.parMin, 50.8);
      expect(milk.parMax, 152.5);
      expect(milk.suggestedQty, 121.5);
      expect(milk.supplierName, 'Delta Dairy Co.');
    });

    test('PO lead time: purchasing\'s gate; the averages', () async {
      final s = _server();
      final (status, body) = await _get(
        s.server,
        '/reports/branches/${SeedIds.maadi}/po-lead-time',
        _range,
      );
      expect(status, 200);
      final r = PoLeadTimeReport.fromJson(body! as Map<String, Object?>);
      expect(r.bySupplier, isNotEmpty);
      final total = r.bySupplier.fold<int>(0, (a, x) => a + x.ordersReceived);
      final weighted = r.bySupplier.fold<double>(
        0,
        (a, x) => a + x.avgLeadTimeDays * x.ordersReceived,
      );
      expect(r.overallAvgDays, closeTo(weighted / total, 1e-9));
      for (var i = 1; i < r.bySupplier.length; i++) {
        expect(
          r.bySupplier[i - 1].avgLeadTimeDays,
          greaterThanOrEqualTo(r.bySupplier[i].avgLeadTimeDays),
        );
      }
      final limited = _server(Persona.limited);
      expect(
        (await _get(
          limited.server,
          '/reports/branches/${SeedIds.maadi}/po-lead-time',
          _range,
        )).$1,
        403,
      );
    });

    test('a manager reading another branch is refused', () async {
      final s = _server(Persona.manager);
      final (status, _) = await _get(
        s.server,
        '/reports/branches/${SeedIds.maadi}/consumption',
        _range,
      );
      expect(status, 403);
    });
  });

  group('staff discipline', () {
    test('ranked within departments; the Zamalek waiters front of house, '
        'as the team seed places them', () async {
      final s = _server();
      final (status, body) = await _get(s.server, '/staff/discipline-report', {
        'from': '2026-09-09',
        'to': '2026-10-08',
      });
      expect(status, 200);
      final r = DisciplineReport.fromJson(body! as Map<String, Object?>);
      expect(r.rows, isNotEmpty);
      expect(r.rows.where((x) => x.departmentId == null), isEmpty);
      for (final name in ['Laila Ehab', 'Adham Reda']) {
        final w = r.rows.firstWhere((x) => x.employeeName == name);
        expect(w.departmentName, 'Front of house', reason: name);
      }
      expect(r.rows.any((x) => (x.coversGiven ?? 0) > 0), isTrue);
      expect(r.rows.any((x) => (x.coveredByOthers ?? 0) > 0), isTrue);
      // Within a department, rank follows absences, then lates, then minutes.
      final byDept = <String?, List<DisciplineRow>>{};
      for (final x in r.rows) {
        (byDept[x.departmentId] ??= []).add(x);
      }
      for (final g in byDept.values) {
        expect(g.first.rankInDepartment, 1);
        for (var i = 1; i < g.length; i++) {
          expect(
            g[i].rankInDepartment,
            greaterThanOrEqualTo(g[i - 1].rankInDepartment),
          );
        }
      }
    });

    test('validation and refusals', () async {
      final s = _server();
      expect(
        await _get(s.server, '/staff/discipline-report', {
          'from': '2026-10-08',
          'to': '2026-09-09',
        }),
        (400, 'RANGE_BACKWARDS'),
      );
      expect(
        await _get(s.server, '/staff/discipline-report', {
          'from': '2024-01-01',
          'to': '2026-10-08',
        }),
        (400, 'RANGE_TOO_WIDE'),
      );
      final limited = _server(Persona.limited);
      final (refused, _) = await _get(
        limited.server,
        '/staff/discipline-report',
        {'from': '2026-09-09', 'to': '2026-10-08'},
      );
      expect(refused, 403);
      final mgr = _server(Persona.manager);
      final (_, mine) = await _get(mgr.server, '/staff/discipline-report', {
        'from': '2026-09-09',
        'to': '2026-10-08',
      });
      final ids = {
        for (final x in (mine! as Map)['rows'] as List)
          (x as Map)['employee_id'],
      };
      final zamalek = {
        for (final e in s.db['employees'].rows)
          if ((e['branch_ids'] as List?)?.first == SeedIds.zamalek &&
              e['on_payroll'] == true)
            e['id'],
      };
      expect(ids, isNotEmpty);
      // A Zamalek manager sees Zamalek's people (and covers by them).
      expect(ids.difference(zamalek), isEmpty);
    });
  });
}
