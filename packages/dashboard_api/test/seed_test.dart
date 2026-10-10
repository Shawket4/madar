// The seed: realistic, deterministic, fast, and every entity in the spec's
// exact shape (it parses back through its model's fromJson).
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

const _eq = DeepCollectionEquality();

/// toJson → fromJson → toJson is stable.
void _roundTrips<T>(
  String what,
  List<T> items,
  Map<String, Object?> Function(T) toJson,
  T Function(Map<String, Object?>) fromJson,
) {
  expect(items, isNotEmpty, reason: what);
  for (final item in items) {
    final json = jsonDecode(jsonEncode(toJson(item))) as Map<String, Object?>;
    final again = toJson(fromJson(json));
    expect(
      _eq.equals(jsonDecode(jsonEncode(again)), json),
      isTrue,
      reason: '$what ${json['id']}',
    );
  }
}

void main() {
  final seed = MockSeed.instance;

  test('the 30 days of orders and tills are generated in under 300 ms', () {
    // The first build also pays for JIT compilation; the generation cost is
    // the best of a few warm builds (robust when many test runs share the CPU).
    var best = 1 << 30;
    late MockSeed fresh;
    for (var i = 0; i < 4; i++) {
      fresh = MockSeed.fresh();
      final sw = Stopwatch()..start();
      fresh.orders;
      fresh.tills;
      fresh.customers;
      sw.stop();
      if (i > 0 && sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
    }
    // ignore: avoid_print
    print(
      'seed history: ${fresh.orders.length} orders, ${fresh.tills.length} tills, '
      '${fresh.customers.length} customers in $best ms (warm)',
    );
    expect(best, lessThan(300));
  });

  test('the seed is deterministic', () {
    final a = MockSeed.fresh();
    final b = MockSeed.fresh();
    String digest(MockSeed s) => jsonEncode([
      for (final o in s.orders.take(400)) o.toJson(),
      for (final o in s.orders.reversed.take(400)) o.toJson(),
      for (final t in s.tills) t.toJson(),
      for (final c in s.customers) c.toJson(),
    ]);
    expect(digest(a), digest(b));
    expect(a.orders.length, b.orders.length);
    expect(mockUuid('branch:maadi'), SeedIds.maadi);
    expect(
      SeedIds.maadi,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('every seed entity parses back through its model', () {
    _roundTrips('org', seed.orgs, (o) => o.toJson(), Org.fromJson);
    _roundTrips('branch', seed.allBranches, (o) => o.toJson(), Branch.fromJson);
    _roundTrips('user', seed.users, (o) => o.toJson(), UserPublic.fromJson);
    _roundTrips(
      'employee',
      seed.employees,
      (o) => o.toJson(),
      Employee.fromJson,
    );
    _roundTrips('role', seed.roles, (o) => o.toJson(), RoleView.fromJson);
    _roundTrips(
      'payment method',
      seed.paymentMethods,
      (o) => o.toJson(),
      OrgPaymentMethod.fromJson,
    );
    _roundTrips(
      'category',
      seed.categories,
      (o) => o.toJson(),
      Category.fromJson,
    );
    _roundTrips(
      'menu item',
      seed.menuItems,
      (o) => o.toJson(),
      MenuItem.fromJson,
    );
    _roundTrips('size', seed.itemSizes, (o) => o.toJson(), ItemSize.fromJson);
    _roundTrips(
      'group',
      seed.modifierGroups,
      (o) => o.toJson(),
      GroupOut.fromJson,
    );
    _roundTrips(
      'add-on',
      seed.addonItems,
      (o) => o.toJson(),
      AddonItem.fromJson,
    );
    _roundTrips(
      'work shift',
      seed.workShifts,
      (o) => o.toJson(),
      WorkShift.fromJson,
    );
    _roundTrips(
      'attendance settings',
      seed.attendanceSettings,
      (o) => o.toJson(),
      AttendanceSettings.fromJson,
    );
    _roundTrips(
      'customer',
      seed.customers,
      (o) => o.toJson(),
      Customer.fromJson,
    );
    _roundTrips('till', seed.tills, (o) => o.toJson(), Till.fromJson);
    _roundTrips('order', seed.orders, (o) => o.toJson(), Order.fromJson);
    final full = [for (final o in seed.orders.take(300)) seed.orderFull(o.id)!];
    _roundTrips('order (full)', full, (o) => o.toJson(), OrderFull.fromJson);
    for (final id in [SeedIds.sabahOrg, SeedIds.nakhlaOrg]) {
      _roundTrips(
        'onboarding',
        [seed.onboarding(id)],
        (o) => o.toJson(),
        OnboardingStatus.fromJson,
      );
      _roundTrips(
        'brand',
        [seed.brand(id)],
        (o) => o.toJson(),
        PublicBrand.fromJson,
      );
      _roundTrips(
        'modules',
        [seed.modules(id)],
        (o) => o.toJson(),
        OrgModules.fromJson,
      );
    }
  });

  test('Sabah Coffee: four Cairo branches, EGP, both modules', () {
    expect(seed.org.name, 'Sabah Coffee');
    expect(seed.org.currencyCode, 'EGP');
    expect(seed.org.timezone, 'Africa/Cairo');
    expect(seed.org.modules, ['pos', 'dawam']);
    expect(
      [for (final b in seed.branches) b.name],
      ['Heliopolis', 'Maadi', 'New Cairo', 'Zamalek'],
    );
    expect(seed.dawamOrg.modules, ['dawam']);
    expect(seed.menuItems, hasLength(40));
    expect(seed.categories, hasLength(7));
    expect(seed.customers, hasLength(200));
    expect(seed.customers.first.name, 'Nada Kamal');
    expect({for (final c in seed.customers) c.phone}, hasLength(200));
    expect(seed.modifierGroups.map((g) => g.name), ['Milk', 'Extras']);
    expect(seed.itemSizes, isNotEmpty);
    expect(seed.roles.map((r) => r.key), [
      'org_admin',
      'branch_manager',
      'teller',
      'waiter',
      'kitchen',
    ]);
    for (final u in seed.users) {
      expect(u.name, isNot(contains('Test')));
    }
  });

  test('30 days of orders per branch, nothing after now, money adds up', () {
    final now = MockSeed.now;
    final first = MockClock.startOfCairoDay(
      now,
    ).subtract(const Duration(days: 29));
    for (final b in seed.branches) {
      final mine = seed.orders.where((o) => o.branchId == b.id).toList();
      final days = {for (final o in mine) MockClock.cairoDate(o.createdAt)};
      expect(days, hasLength(30), reason: b.name);
      expect(mine.length, greaterThan(30 * 40), reason: b.name);
    }
    for (final o in seed.orders) {
      expect(o.createdAt.isAfter(now), isFalse);
      expect(o.createdAt.isBefore(first), isFalse);
      expect(o.totalAmount, o.subtotal - o.discountAmount);
      expect(o.paymentLegs.fold<int>(0, (s, l) => s + l.amount), o.totalAmount);
      expect(o.taxAmount, (o.totalAmount * 14 / 114).round());
      if (o.paymentMethod == 'cash') {
        expect(o.amountTendered! - o.changeGiven!, o.totalAmount);
      }
    }
    // Lines add up to the subtotal.
    for (final o in seed.orders.take(500)) {
      final items = seed.orderItems(o.id);
      expect(items, isNotEmpty);
      expect(items.fold<int>(0, (s, i) => s + i.lineTotal), o.subtotal);
    }
    final statuses = groupBy(
      seed.orders,
      (Order o) => o.status,
    ).map((k, v) => MapEntry(k, v.length));
    expect(statuses.keys.toSet(), {'completed', 'voided'});
    expect(statuses['voided']! / seed.orders.length, lessThan(0.04));
  });

  test(
    'tills: two a day per branch, today\'s morning ones open, cash reconciles',
    () {
      final open = seed.tills
          .where((t) => t.status == TillStatus.open)
          .toList();
      expect(open, hasLength(4));
      for (final t in open) {
        expect(t.closedAt, isNull);
        expect(
          MockClock.cairoDate(t.openedAt),
          MockClock.cairoDate(MockSeed.now),
        );
      }
      expect(
        seed.tills.where((t) => t.status == TillStatus.forceClosed),
        hasLength(1),
      );
      // 29 past days × 2 + today's morning, per branch.
      expect(seed.tills, hasLength(4 * (29 * 2 + 1)));
      for (final t in seed.tills.where((t) => t.status == TillStatus.closed)) {
        final cash = seed.orders
            .where((o) => o.tillId == t.id && o.status == 'completed')
            .expand((o) => o.paymentLegs)
            .where((l) => l.isCash ?? false)
            .fold<int>(0, (s, l) => s + l.amount);
        expect(t.closingCashSystem, MockSeed.floatPiastres + cash);
        expect(
          t.cashDiscrepancy,
          t.closingCashDeclared! - t.closingCashSystem!,
        );
      }
    },
  );

  test('customers carry the stats of their orders', () {
    final byCustomer = groupBy(
      seed.orders.where((o) => o.customerId != null && o.status == 'completed'),
      (Order o) => o.customerId!,
    );
    for (final c in seed.customers) {
      final mine = byCustomer[c.id] ?? const [];
      expect(c.ordersCount, mine.length, reason: c.name);
      expect(
        c.totalSpent,
        mine.fold<int>(0, (s, o) => s + o.totalAmount),
        reason: c.name,
      );
    }
    expect(seed.customers.where((c) => c.ordersCount > 5), isNotEmpty);
  });

  test('the Cairo clock helpers', () {
    expect(
      MockClock.cairoIso(MockClock.defaultNow),
      '2026-10-08T10:00:00+03:00',
    );
    expect(
      MockClock.offsetAt(DateTime.utc(2026, 1, 15)),
      const Duration(hours: 2),
    );
    expect(
      MockClock.offsetAt(DateTime.utc(2026, 7, 15)),
      const Duration(hours: 3),
    );
    expect(MockClock.fromCairo(2026, 10, 8, 10), MockClock.defaultNow);
    expect(
      MockClock.startOfCairoDay(MockClock.defaultNow),
      DateTime.utc(2026, 10, 7, 21),
    );
    final clock = MockClock()..advance(const Duration(hours: 1));
    expect(clock.now, DateTime.utc(2026, 10, 8, 8));
    expect(clock.today, '2026-10-08');
  });
}
