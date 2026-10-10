// The Staff drinks and Bundles mock handlers against figures worked out by
// hand from the seeded rows, the backend's gates and errors
// (`staff_pool/record.rs`, `reports/bundles.rs`), and the pure rules the
// pages compute in the browser (`staffDrinkMoney`, the item text, the mix
// order, the wire rates, the order sheet's staff line).
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show DashFormat;
import 'package:dashboard_reports/src/mock/staff_pool_bundles_mock.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/bundles_mix_dialog.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/staff_drink_money.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/staff_drink_order_sheet.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/staff_drinks_table.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/unit_support.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<ApiResponse> _get(
  MockServer s,
  String path,
  Map<String, String> query,
) => s.send(
  ApiRequest(
    method: 'GET',
    path: path,
    query: {
      for (final e in query.entries) e.key: [e.value],
    },
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

StaffDrink _drink({
  int? comp,
  int? extras,
  int? reported,
  String? size,
  int qty = 1,
}) => StaffDrink.fromJson({
  'id': 'd',
  'branch_id': 'b',
  'order_id': null,
  'menu_item_id': 'm',
  'item_name': 'Latte',
  'size_label': size,
  'quantity': qty,
  'note': 'n',
  'business_date': '2026-10-08',
  'allowance_at_record': 3,
  'used_before': 0,
  'overspent': false,
  'overspent_on_replay': false,
  'cost_minor': null,
  'recorded_by': 'u',
  'recorded_at': '2026-10-08T06:00:00Z',
  'comp_minor': comp,
  'extras_minor': extras,
  'comp_minor_reported': reported,
});

void main() {
  group('staff drinks handlers', () {
    test('REP-SPL-004 the day\'s pool adds up the day\'s quantity', () async {
      final s = reportsServer();
      final r =
          _json(
                await _get(s.server, todayTpl, {
                  'branch_id': SeedIds.heliopolis,
                  'business_date': defaultTo,
                }),
              )!
              as Map<String, Object?>;
      // Heliopolis rang five singles this morning against its four.
      expect(r['enabled'], isTrue);
      expect(r['allowance'], 4);
      expect(r['used'], 5);
      expect(r['remaining'], 0);
      expect(r['over'], 1);
      expect(r['business_date'], defaultTo);
    });

    test('REP-SPL-004 no date: the branch\'s business day of now', () async {
      final s = reportsServer();
      final r =
          _json(await _get(s.server, todayTpl, {'branch_id': SeedIds.zamalek}))!
              as Map<String, Object?>;
      expect(r['business_date'], defaultTo);
      expect(r['remaining'], 2);
    });

    test('REP-SPL-008 New Cairo is switched off', () async {
      final s = reportsServer();
      final r =
          _json(
                await _get(s.server, todayTpl, {'branch_id': SeedIds.newCairo}),
              )!
              as Map<String, Object?>;
      expect(r['enabled'], isFalse);
    });

    test('pool_state: nothing negative, over and left never both', () {
      expect(StaffPoolMock.poolState(4, 5), {
        'allowance': 4,
        'used': 5,
        'remaining': 0,
        'over': 1,
      });
      expect(StaffPoolMock.poolState(5, 3)['remaining'], 2);
      expect(StaffPoolMock.poolState(-1, -2), {
        'allowance': 0,
        'used': 0,
        'remaining': 0,
        'over': 0,
      });
    });

    test('REP-SPL-005/006 the summary sums exactly the listed rows', () async {
      final s = reportsServer();
      final q = {
        'branch_id': SeedIds.maadi,
        'from': defaultFrom,
        'to': defaultTo,
      };
      final rows = (_json(await _get(s.server, drinksTpl, q))! as List)
          .cast<Map<String, Object?>>();
      final sum =
          _json(await _get(s.server, summaryTpl, q))! as Map<String, Object?>;
      int add(String f) =>
          rows.fold<int>(0, (a, r) => a + ((r[f] as int?) ?? 0));
      expect(sum['drinks'], rows.length);
      expect(sum['quantity'], add('quantity'));
      expect(sum['comp_minor'], add('comp_minor'));
      expect(sum['extras_minor'], add('extras_minor'));
      expect(sum['cost_minor'], add('cost_minor'));
      expect(
        sum['overspent'],
        rows.where((r) => r['overspent'] == true).length,
      );
      expect(
        sum['unpriced'],
        rows.where((r) => r['comp_minor'] == null).length,
      );
      // Maadi's old till before 15 Sep: rows with no figures, and none after.
      expect(sum['unpriced'], greaterThan(0));
      expect(
        rows.where(
          (r) =>
              r['comp_minor'] == null &&
              '${r['business_date']}'.compareTo(
                    StaffPoolMock.maadiPricedFrom,
                  ) >=
                  0,
        ),
        isEmpty,
      );
      // Newest first: business day, then the clock.
      for (var i = 1; i < rows.length; i++) {
        final a = rows[i - 1], b = rows[i];
        final day = '${a['business_date']}'.compareTo('${b['business_date']}');
        expect(day >= 0, isTrue);
        if (day == 0) {
          expect(
            '${a['recorded_at']}'.compareTo('${b['recorded_at']}') >= 0,
            isTrue,
          );
        }
      }
    });

    test('a range that ends before it starts is a 400', () async {
      final s = reportsServer();
      final e = await _refused(
        _get(s.server, drinksTpl, {
          'branch_id': SeedIds.maadi,
          'from': '2026-10-08',
          'to': '2026-10-01',
        }),
      );
      expect(e.status, 400);
    });

    test('a branch is required, and a real one', () async {
      final s = reportsServer();
      expect((await _refused(_get(s.server, todayTpl, {}))).status, 400);
      expect(
        (await _refused(
          _get(s.server, todayTpl, {'branch_id': 'nope'}),
        )).status,
        400,
      );
      expect(
        (await _refused(
          _get(s.server, todayTpl, {'branch_id': mockUuid('branch:nowhere')}),
        )).status,
        404,
      );
    });

    test('REP-SPL-001 without the capability: 403', () async {
      final s = reportsServer(persona: Persona.limited);
      for (final tpl in [todayTpl, drinksTpl, summaryTpl]) {
        final e = await _refused(
          _get(s.server, tpl, {'branch_id': SeedIds.maadi}),
        );
        expect(e.status, 403, reason: tpl);
      }
    });

    test('a manager reads only her own branch', () async {
      final s = reportsServer(persona: Persona.manager);
      final ok = await _get(s.server, todayTpl, {'branch_id': SeedIds.zamalek});
      expect(ok.status, 200);
      final e = await _refused(
        _get(s.server, todayTpl, {'branch_id': SeedIds.heliopolis}),
      );
      expect(e.status, 403);
    });

    test('REP-SPL-019 the sale behind a drink: comp off its line', () async {
      final s = reportsServer();
      final drink = StaffPoolMock.drinksIn(
        s.db,
        SeedIds.heliopolis,
        defaultTo,
        defaultTo,
      ).first;
      final o = OrderFull.fromJson(
        _json(
              await s.server.send(
                ApiRequest(method: 'GET', path: '/orders/${drink['order_id']}'),
              ),
            )!
            as Map<String, Object?>,
      );
      final line = o.items.single;
      expect(line.staffDrinkId, drink['id']);
      expect(line.staffCompMinor, drink['comp_minor']);
      final staff = staffDrinkLine(line)!;
      // Normal price − comp = charged = the sale's total.
      expect(staff.normal - staff.comp, staff.charged);
      expect(staff.charged, o.totalAmount);
      expect(staff.charged, drink['extras_minor']);
    });

    test('REP-SPL-019 the sale: orders.read, at a branch one holds', () async {
      final noRead = reportsServer(persona: Persona.limited);
      final drink = StaffPoolMock.drinksIn(
        noRead.db,
        SeedIds.maadi,
        defaultTo,
        defaultTo,
      ).first;
      // The limited cashier reads orders at Maadi: allowed.
      final r = await noRead.server.send(
        ApiRequest(method: 'GET', path: '/orders/${drink['order_id']}'),
      );
      expect(r.status, 200);
      final other = StaffPoolMock.drinksIn(
        noRead.db,
        SeedIds.heliopolis,
        defaultTo,
        defaultTo,
      ).first;
      // …but not another branch's sale.
      final e = await _refused(
        noRead.server.send(
          ApiRequest(method: 'GET', path: '/orders/${other['order_id']}'),
        ),
      );
      expect(e.status, 403);
    });
  });

  group('bundles handlers', () {
    test(
      'REP-BUN-004/005 totals are the rows\' sums; rows by revenue',
      () async {
        final s = reportsServer();
        final r = BundlesReport.fromJson(
          _json(
                await _get(s.server, bundlesTpl, {
                  'from': defaultFrom,
                  'to': defaultTo,
                  'kind': 'combo',
                }),
              )!
              as Map<String, Object?>,
        );
        expect(r.rows, isNotEmpty);
        expect(r.totals.sold, r.rows.fold<int>(0, (a, x) => a + x.sold));
        expect(r.totals.revenue, r.rows.fold<int>(0, (a, x) => a + x.revenue));
        expect(r.totals.cost, r.rows.fold<int>(0, (a, x) => a + x.cost));
        for (final x in r.rows) {
          expect(x.saving, x.listValue - x.revenue, reason: x.name);
          expect(x.orders, lessThanOrEqualTo(x.sold), reason: x.name);
        }
        for (var i = 1; i < r.rows.length; i++) {
          expect(r.rows[i - 1].revenue >= r.rows[i].revenue, isTrue);
        }
      },
    );

    test('the margin: four places, half away from zero, none at 0', () {
      expect(BundlesMock.margin(270000, 87540), '0.6758');
      expect(BundlesMock.margin(180000, 67540), '0.6248');
      expect(BundlesMock.margin(100, 150), '-0.5000');
      expect(BundlesMock.margin(0, 10), isNull);
    });

    test('a bad kind, a bad date or a reversed range is a 400', () async {
      final s = reportsServer();
      Future<int> status(Map<String, String> q) async =>
          (await _refused(_get(s.server, bundlesTpl, q))).status;
      expect(
        await status({'from': defaultFrom, 'to': defaultTo, 'kind': 'x'}),
        400,
      );
      expect(await status({'from': '2026-13-01', 'to': defaultTo}), 400);
      expect(await status({'from': defaultTo, 'to': defaultFrom}), 400);
      expect(await status({'to': defaultTo}), 400);
    });

    test('REP-BUN-001 without reports.bundles: 403', () async {
      final s = reportsServer(persona: Persona.limited);
      final e = await _refused(
        _get(s.server, bundlesTpl, {'from': defaultFrom, 'to': defaultTo}),
      );
      expect(e.status, 403);
    });

    test('REP-BUN-013 an unknown combo\'s mix is a 404', () async {
      final s = reportsServer();
      final e = await _refused(
        _get(s.server, '/reports/bundles/combos/${mockUuid('combo:x')}/mix', {
          'from': defaultFrom,
          'to': defaultTo,
        }),
      );
      expect(e.status, 404);
    });

    test('REP-BUN-015 each slot\'s picks add up to the combos sold', () async {
      final s = reportsServer();
      // One pick per slot (Brunch for Two takes two of each).
      final id = BundlesMock.comboId('coffee-cookie');
      final q = {
        'from': defaultFrom,
        'to': defaultTo,
        'branch_id': SeedIds.heliopolis,
      };
      final report = BundlesReport.fromJson(
        _json(await _get(s.server, bundlesTpl, {...q, 'kind': 'combo'}))!
            as Map<String, Object?>,
      );
      final sold = report.rows.firstWhere((r) => r.id == id).sold;
      final mix = ComboMix.fromJson(
        _json(await _get(s.server, '/reports/bundles/combos/$id/mix', q))!
            as Map<String, Object?>,
      );
      expect(mix.slots, isNotEmpty);
      for (final slot in mix.slots) {
        expect(
          slot.picks.fold<int>(0, (a, p) => a + p.count),
          sold,
          reason: slot.name,
        );
      }
    });
  });

  group('the pages\' own rules', () {
    test('REP-SPL-017 staffDrinkMoney: unpriced, priced, till disagreed', () {
      expect(staffDrinkMoney(_drink()), isA<StaffDrinkUnpriced>());
      final free = staffDrinkMoney(_drink(comp: 7000, extras: 0));
      expect(free, isA<StaffDrinkPriced>());
      expect((free as StaffDrinkPriced).extras, 0);
      expect(free.tillSaid, isNull);
      final agreed = staffDrinkMoney(_drink(comp: 7000, reported: 7000));
      expect((agreed as StaffDrinkPriced).tillSaid, isNull);
      final differs = staffDrinkMoney(_drink(comp: 7000, reported: 9000));
      expect((differs as StaffDrinkPriced).tillSaid, 9000);
      expect(differs.comp, 7000);
      expect(differs.extras, isNull);
    });

    test('REP-SPL-015 the item: size when sized, quantity past one', () {
      expect(staffDrinkItemText(_drink()), 'Latte');
      expect(staffDrinkItemText(_drink(size: '')), 'Latte');
      expect(staffDrinkItemText(_drink(size: 'Large')), 'Latte · Large');
      expect(
        staffDrinkItemText(_drink(size: 'Large', qty: 2)),
        'Latte · Large × 2',
      );
      expect(staffDrinkItemText(_drink(qty: 3)), 'Latte × 3');
    });

    test('REP-BUN-015 the mix: most picked first, ties as sent', () {
      MixPick p(String n, int c) => MixPick.fromJson({
        'menu_item_id': n,
        'name': n,
        'name_translations': <String, Object?>{},
        'size_label': null,
        'count': c,
        'surcharge_total': 0,
      });
      final picks = [p('a', 3), p('b', 9), p('c', 3), p('d', 12)];
      mergeSortPicks(picks);
      expect([for (final x in picks) x.name], ['d', 'b', 'a', 'c']);
    });

    test('REP-BUN-006/007 the wire\'s rates', () {
      const f = DashFormat();
      expect(rateOfWire('0.6248'), 0.6248);
      expect(rateOfWire(' '), isNull);
      expect(rateOfWire('x'), isNull);
      expect(rateOfWire(null), isNull);
      expect(fmtRateWire(f, '0.6248'), '62.5%');
      expect(fmtRateWire(f, null), '—');
    });
  });
}
