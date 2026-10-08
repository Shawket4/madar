// Today's mock backend (`lib/src/mock/today_mock.dart`) behaves like the
// backend's report handlers (MadarRust `reports/handlers.rs:1918-2090`):
// capabilities, branch and org scoping, the all-branches sentinel, shapes
// and figures. And Today's day bounds (INV-TOD-004, INV-TOD-038).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/today/today_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _all = '00000000-0000-0000-0000-000000000000';

Future<Object?> _get(
  MockServer s,
  String path, {
  Map<String, String> headers = const {},
}) async {
  final r = await s.send(ApiRequest(method: 'GET', path: path, headers: headers));
  return MockResponse(r.status, bodyBytes: r.bodyBytes).json;
}

Matcher _refused(int status, String message) => throwsA(
  isA<ApiException>()
      .having((e) => e.status, 'status', status)
      .having((e) => e.message, 'message', message),
);

class _Tz extends Notifier<String> {
  @override
  String build() => 'Africa/Cairo';

  void set(String zone) => state = zone;
}

final _tzProvider = NotifierProvider<_Tz, String>(_Tz.new);

void main() {
  setUpAll(ensureTimeZones);

  group('capabilities and scope', () {
    test('every route needs inventory.read', () async {
      final s = todayServer(persona: Persona.limited);
      for (final p in [
        '/reports/branches/${SeedIds.maadi}/inventory-valuation',
        '/reports/orgs/${SeedIds.sabahOrg}/inventory-valuation',
        '/reports/branches/${SeedIds.maadi}/low-stock',
        '/reports/orgs/${SeedIds.sabahOrg}/low-stock',
      ]) {
        await expectLater(
          _get(s.server, p),
          _refused(
            403,
            "Forbidden: You don't have permission to do this: "
            'See stock levels (inventory.read)',
          ),
          reason: p,
        );
      }
    });

    test('another org is refused on the org routes', () async {
      final s = todayServer();
      for (final p in [
        '/reports/orgs/${SeedIds.nakhlaOrg}/inventory-valuation',
        '/reports/orgs/${SeedIds.nakhlaOrg}/low-stock',
      ]) {
        await expectLater(
          _get(s.server, p),
          _refused(403, 'Forbidden: Not your org'),
        );
      }
    });

    test('an unknown branch is not found', () async {
      final s = todayServer();
      await expectLater(
        _get(s.server, '/reports/branches/${mockUuid('nowhere')}/low-stock'),
        _refused(404, 'Not found: Branch not found'),
      );
    });

    test('a branch-scoped person is refused another branch', () async {
      final s = todayServer(persona: Persona.manager);
      await expectLater(
        _get(s.server, '/reports/branches/${SeedIds.maadi}/inventory-valuation'),
        _refused(403, 'Forbidden: Not assigned to this branch'),
      );
    });

    test('the sentinel rolls up the branches the person works at', () async {
      final owner = todayServer();
      final all = await _get(owner.server, '/reports/branches/$_all/low-stock');
      expect(all, hasLength(9));
      final manager = todayServer(persona: Persona.manager);
      final mine =
          await _get(manager.server, '/reports/branches/$_all/low-stock')
              as List;
      expect(mine, hasLength(5));
      expect(
        mine.every((r) => (r as Map)['branch_id'] == SeedIds.zamalek),
        isTrue,
      );
    });

    test('the org routes roll up every branch, for a manager too', () async {
      final s = todayServer(persona: Persona.manager);
      final rows =
          await _get(s.server, '/reports/orgs/${SeedIds.sabahOrg}/low-stock')
              as List;
      expect(rows, hasLength(9));
    });

    test('the sentinel needs an org in scope', () async {
      final s = todayServer(persona: Persona.platform);
      await expectLater(
        _get(s.server, '/reports/branches/$_all/low-stock'),
        _refused(403, 'Forbidden: No organization in scope'),
      );
      final rows = await _get(
        s.server,
        '/reports/branches/$_all/low-stock',
        headers: {'X-Org-Id': SeedIds.sabahOrg},
      );
      expect(rows, hasLength(9));
    });
  });

  group('figures', () {
    test('valuation: a branch, the org, unknown costs', () async {
      final s = todayServer();
      final z = stockValue(s.db, [SeedIds.zamalek]);
      final branch = InventoryValuationReport.fromJson(
        (await _get(
              s.server,
              '/reports/branches/${SeedIds.zamalek}/inventory-valuation',
            ))!
            as Map<String, Object?>,
      );
      expect(branch.totalValue, z.total);
      expect(branch.unknownCostCount, z.unknown);
      final o = stockValue(s.db, SeedIds.sabahBranches);
      final org = InventoryValuationReport.fromJson(
        (await _get(
              s.server,
              '/reports/orgs/${SeedIds.sabahOrg}/inventory-valuation',
            ))!
            as Map<String, Object?>,
      );
      expect(org.totalValue, o.total);
      expect(org.unknownCostCount, 1);
    });

    test('valuation of a branch with no stock is zero', () async {
      final s = todayServer();
      final r = InventoryValuationReport.fromJson(
        (await _get(
              s.server,
              '/reports/branches/${SeedIds.heliopolis}/inventory-valuation',
            ))!
            as Map<String, Object?>,
      );
      expect(r.totalValue, 0);
      expect(r.unknownCostCount, 0);
      expect(r.items, isEmpty);
    });

    test('low stock: shape, suggestion, supplier, order', () async {
      final s = todayServer();
      final rows = [
        for (final r
            in (await _get(
                  s.server,
                  '/reports/branches/${SeedIds.zamalek}/low-stock',
                ))!
                as List)
          LowStockRow.fromJson(r as Map<String, Object?>),
      ];
      expect(rows.map((r) => r.ingredientName), [
        'Croissant Dough',
        'Matcha Powder',
        'Oat Milk',
        'Paper Cup 12oz',
        'Vanilla Syrup',
      ]);
      final oat = rows.firstWhere((r) => r.ingredientName == 'Oat Milk');
      expect(oat.onHand, -350);
      expect(oat.parMin, 4000);
      expect(oat.parMax, 9000);
      // GREATEST(COALESCE(par_max, par_min) - on_hand, 0).
      expect(oat.suggestedQty, 9350);
      expect(oat.supplierId, InvIds.supplier('metro'));
      expect(oat.supplierName, 'Metro Wholesale');
      expect(oat.branchName, 'Zamalek');
      expect(oat.unit, 'ml');
    });

    test('a change shows on the next read', () async {
      final s = todayServer();
      setStock(s.db, SeedIds.zamalek, 'sugar', onHand: 10, parMin: 3000);
      final rows =
          await _get(s.server, '/reports/branches/${SeedIds.zamalek}/low-stock')
              as List;
      expect(rows, hasLength(6));
    });
  });

  group('the day', () {
    test('INV-TOD-004 today in Cairo and in another zone', () {
      final now = MockClock.defaultNow;
      expect(TodayBounds.at('Africa/Cairo', now), const TodayBounds(
        startOfToday,
        endOfToday,
      ));
      expect(TodayBounds.at('Asia/Dubai', now), const TodayBounds(
        '2026-10-07T20:00:00.000Z',
        '2026-10-08T19:59:59.999Z',
      ));
      // 23:30 UTC on the 8th is already the 9th in Cairo.
      expect(
        TodayBounds.at('Africa/Cairo', DateTime.utc(2026, 10, 8, 23, 30)),
        const TodayBounds(
          '2026-10-08T21:00:00.000Z',
          '2026-10-09T20:59:59.999Z',
        ),
      );
    });

    test('INV-TOD-038 kept across midnight, redone on a zone change', () {
      var now = MockClock.defaultNow;
      final c = ProviderContainer(
        overrides: [
          activeTimezoneProvider.overrideWith((ref) => ref.watch(_tzProvider)),
          clockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(todayBoundsProvider, (_, _) {});
      addTearDown(sub.close);
      expect(sub.read().endIso, endOfToday);
      now = DateTime.utc(2026, 10, 9, 1);
      expect(sub.read().endIso, endOfToday);
      c.read(_tzProvider.notifier).set('Asia/Dubai');
      expect(sub.read().endIso, '2026-10-09T19:59:59.999Z');
    });
  });
}
