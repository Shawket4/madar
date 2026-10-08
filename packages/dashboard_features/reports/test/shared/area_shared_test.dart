// The reports area's shared pieces: the area seed's rules (so every unit
// builds on the same figures) and the helpers in lib/src/shared.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_reports/src/area_seed.dart';
import 'package:dashboard_reports/src/shared/report_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(ensureTimeZones);

  group('area seed', () {
    test('the sold-set sums agree with each other', () {
      final db = MockDb.seeded();
      final rows = reportOrders(db, branchIds: SeedIds.sabahBranches);
      expect(rows, isNotEmpty);
      final s = summarizeSales(rows);
      expect(s.orders + s.voided, rows.length);
      expect(s.voided, greaterThan(0));
      int sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);
      expect(sum(s.byMethod), s.revenue);
      expect(sum(s.revenueByChannel), s.revenue);
      expect(sum(s.ordersByChannel), s.orders);
      expect(s.byMethod.containsKey('mixed'), isFalse);
    });

    test('a period narrows the orders, inclusively', () {
      final db = MockDb.seeded();
      final all = reportOrders(db, branchIds: [SeedIds.zamalek]);
      final at = DateTime.parse(all.last['created_at']! as String);
      final one = reportOrders(
        db,
        branchIds: [SeedIds.zamalek],
        from: at,
        to: at,
      );
      expect(one.map((o) => o['id']), contains(all.last['id']));
      expect(one.every((o) => o['branch_id'] == SeedIds.zamalek), isTrue);
    });

    test(
      'menu costs: a share of the price, unknown for incomplete recipes',
      () {
        expect(menuUnitCost('v60', 'one_size'), isNull);
        expect(menuUnitCost('shakshuka', 'one_size'), isNull);
        final single = menuUnitCost('espresso', 'Single')!;
        expect(single, greaterThan(0));
        expect(single, lessThan(7000));
        expect(menuUnitCost('cortado', 'one_size'), isNotNull);
        expect(menuUnitCost('espresso', 'Venti'), isNull);
        expect(reportSizeLabel(seedMenuItem('cortado')!, 0), 'one_size');
        expect(reportSizeLabel(seedMenuItem('latte')!, 1), 'Large');
      },
    );

    test('the catalog: price streaks, stock exceptions, deliveries', () {
      final beans = reportIngredient('espresso_beans');
      expect(beans.risingStreak, 3);
      expect(beans.streakPct, closeTo(12.5, 1e-9));
      expect(reportIngredient('chai').unitCost, isNull);
      expect(onHand(SeedIds.maadi, 'oat_milk'), -2);
      expect(onHand(SeedIds.zamalek, 'strawberries'), 0);
      expect(
        onHand(SeedIds.newCairo, 'whole_milk'),
        lessThan(reportIngredient('whole_milk').parMin),
      );
      expect(onHand(SeedIds.heliopolis, 'butter'), greaterThan(0));
      expect(reportDeliveries, isNotEmpty);
      expect(reportDeliveries.every((d) => d.leadDays > 0), isTrue);
      final zm = deliveriesIn(branchIds: [SeedIds.zamalek]);
      expect(zm.every((d) => d.branchId == SeedIds.zamalek), isTrue);
      expect(
        zm.where((d) => d.ingredient == 'espresso_beans').length,
        beans.deliveries.length,
      );
    });

    test(
      'branch narrowing: the sentinel means the persona\'s branches',
      () async {
        final server = MockServer(persona: Persona.manager);
        server.on(
          'GET',
          '/probe/{id}',
          (req) => MockResponse.ok(reportBranchIds(req, req.param('id'))),
        );
        final all = await server.send(
          const ApiRequest(method: 'GET', path: '/probe/$allBranchesId'),
        );
        expect(jsonDecode(utf8.decode(all.bodyBytes)), [SeedIds.zamalek]);
        await expectLater(
          server.send(
            ApiRequest(method: 'GET', path: '/probe/${SeedIds.maadi}'),
          ),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
        );
      },
    );
  });

  group('shared helpers', () {
    const f = DashFormat(timezone: 'Africa/Cairo');

    test('local dates and business dates follow the active zone', () {
      expect(localDateParam(f, '2026-10-07T22:30:00.000Z'), '2026-10-08');
      expect(localDateParam(f, '2026-10-07T20:30:00.000Z'), '2026-10-07');
      expect(
        sameLocalDay(f, '2026-10-07T22:30:00.000Z', '2026-10-08T20:00:00.000Z'),
        isTrue,
      );
      expect(
        fmtBusinessDate(f, '2026-10-08'),
        f.fmtDate('2026-10-08T09:00:00.000Z'),
      );
      expect(fmtBusinessDate(f, 'not a date'), '—');
      expect(fmtBusinessDate(f, null), '—');
    });

    test('codes become words, unknown codes stay as stored', () {
      final t = Translator(
        Strings({
          'en': {
            'payments.cash': 'Cash',
            'orders.dineIn': 'Dine-in',
            'orders.delivery': 'Delivery',
          },
        }),
        'en',
      );
      expect(paymentMethodLabel(t, 'cash'), 'Cash');
      expect(paymentMethodLabel(t, 'instapay'), 'instapay');
      expect(channelLabel(t, 'dine_in'), 'Dine-in');
      expect(channelLabel(t, 'delivery'), 'Delivery');
      expect(channelLabel(t, 'kiosk'), 'kiosk');
      expect(t.strings.log.missing, isEmpty);
      expect(translatedName('Latte', {'ar': 'لاتيه'}, 'ar'), 'لاتيه');
      expect(translatedName('Latte', {'ar': ''}, 'ar'), 'Latte');
      expect(translatedName('Latte', {'ar': 'لاتيه'}, 'en'), 'Latte');
      expect(translatedName('Latte', null, 'ar'), 'Latte');
    });

    test('initial inventory scope follows the scope bar once', () {
      Scope scope(String? branch) => Scope(
        orgId: SeedIds.sabahOrg,
        branchId: branch,
        preset: ScopePreset.last30Days,
        range: const PeriodRange(
          '2026-09-09T00:00:00Z',
          '2026-10-08T23:59:59Z',
        ),
        timezone: 'Africa/Cairo',
      );
      expect(initialInventoryScope(scope(null)), InventoryScope.org);
      expect(
        initialInventoryScope(scope(SeedIds.maadi)),
        InventoryScope.branch,
      );
      expect(
        inventoryBranchMissing(InventoryScope.branch, scope(null)),
        isTrue,
      );
      expect(inventoryBranchMissing(InventoryScope.org, scope(null)), isFalse);
    });

    test('export re-reads carry X-Madar-Export: 1', () async {
      final server = MockServer();
      server.on('GET', '/probe', (req) => MockResponse.ok(const {}));
      final api = HeaderTransport(server, exportRequestHeaders);
      await api.send(const ApiRequest(method: 'GET', path: '/probe'));
      expect(server.calls.last.headers['X-Madar-Export'], '1');
    });
  });
}
