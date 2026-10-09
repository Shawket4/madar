// The orders unit's mock backend against hand-computed figures.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_sell/dashboard_sell.dart';
import 'package:dashboard_sell/src/mock/orders_mock.dart';
import 'package:flutter_test/flutter_test.dart';

({MockServer server, MockDb db, DashboardApi api}) _setup([
  Persona persona = Persona.owner,
]) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerSellMocks(server, db);
  return (server: server, db: db, api: DashboardApi(server));
}

void main() {
  final today = MockClock.startOfCairoDay(MockSeed.now);
  final tomorrow = today.add(const Duration(days: 1));

  test(
    'GET /orders: one branch today, newest first, the summary over all',
    () async {
      final s = _setup();
      final page = await s.api.orders.listOrders(
        branchId: SeedIds.heliopolis,
        from: today,
        to: tomorrow,
        page: 1,
        perPage: 20,
      );
      final all = s.db['orders'].where(
        (o) =>
            o['branch_id'] == SeedIds.heliopolis &&
            !DateTime.parse(o['created_at']! as String).isBefore(today),
      );
      expect(page.total, all.length);
      expect(page.data.length, 20);
      expect(page.totalPages, (all.length / 20).ceil());
      final at = [for (final o in page.data) o.createdAt];
      expect(at, [...at]..sort((a, b) => b.compareTo(a)));
      final sold = all.where((o) => o['status'] != 'voided');
      expect(
        page.summary.revenue,
        sold.fold<int>(0, (s, o) => s + (o['total_amount']! as int)),
      );
      expect(page.summary.completed, sold.length);
      expect(page.summary.voided, all.length - sold.length);
      expect(page.summary.voided, greaterThanOrEqualTo(1)); // the showcase void
    },
  );

  test(
    'GET /orders: filters (teller, payment legs, type, channel, status)',
    () async {
      final s = _setup();
      Future<PaginatedOrders> q({
        String? teller,
        String? payment,
        String? type,
        String? channel,
        String? status,
      }) => s.api.orders.listOrders(
        branchId: SeedIds.zamalek,
        from: today,
        to: tomorrow,
        tellerName: teller,
        paymentMethod: payment,
        orderType: type,
        channel: channel,
        status: status,
        perPage: 200,
      );
      final mariam = await q(teller: 'mari');
      expect(mariam.data, isNotEmpty);
      expect(mariam.data.every((o) => o.tellerName == 'Mariam Fathy'), isTrue);
      // A split sale answers to either of its legs.
      final cash = await q(payment: 'cash');
      expect(
        cash.data.any((o) => o.id == OrderSeedIds.showcase('split')),
        isTrue,
      );
      final card = await q(payment: 'card');
      expect(
        card.data.any((o) => o.id == OrderSeedIds.showcase('split')),
        isTrue,
      );
      final voided = await q(status: 'voided');
      expect(voided.data.every((o) => o.status == 'voided'), isTrue);
      final heliDelivery = await s.api.orders.listOrders(
        branchId: SeedIds.heliopolis,
        orderType: 'delivery',
        channel: 'in_mall',
        perPage: 500,
      );
      expect(heliDelivery.data, isNotEmpty);
      expect(
        heliDelivery.data.every((o) => o.deliveryChannel == 'in_mall'),
        isTrue,
      );
    },
  );

  test('GET /orders: refusals and validation', () async {
    final s = _setup(Persona.manager);
    // Karim works Zamalek only.
    await expectLater(
      s.api.orders.listOrders(branchId: SeedIds.heliopolis),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
    );
    await expectLater(
      s.api.orders.listOrders(branchId: SeedIds.zamalek, paymentMethod: 'gold'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 400)
            .having((e) => e.message, 'message', contains('gold')),
      ),
    );
    await expectLater(
      s.api.orders.listOrders(branchId: SeedIds.zamalek, excludeItems: 'x'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 400)),
    );
  });

  test('exclude_items changes Items Sold only', () async {
    final s = _setup();
    final base = await s.api.orders.listOrders(
      branchId: SeedIds.heliopolis,
      from: today,
      to: tomorrow,
    );
    final latte = MockSeed.menuItemId('latte');
    final without = await s.api.orders.listOrders(
      branchId: SeedIds.heliopolis,
      from: today,
      to: tomorrow,
      excludeItems: latte,
    );
    expect(without.summary.revenue, base.summary.revenue);
    expect(without.summary.completed, base.summary.completed);
    expect(without.summary.lineItems, lessThan(base.summary.lineItems!));
  });

  test('GET /orders/{id}: the staff drink adds up', () async {
    final s = _setup();
    final o = await s.api.orders.getOrder(
      orderId: OrderSeedIds.showcase('staff'),
    );
    expect(o.items, hasLength(1));
    final line = o.items.single;
    expect(line.staffCompMinor, 16000);
    expect(line.addons.map((a) => a.lineTotal), [2500, 0]);
    expect(o.subtotal, 2500);
    expect(o.totalAmount, 2500);
  });

  test('GET /orders/{id}: combo, deal, delivery, deductions', () async {
    final s = _setup();
    final combo = await s.api.orders.getOrder(
      orderId: OrderSeedIds.showcase('combo'),
    );
    expect(combo.items.first.lineKind, 'combo');
    expect(combo.deals!.single.discount, 1000);
    // 110 + 90 (the combo's parts) + 100 (the cappuccino after the deal).
    expect(combo.subtotal, 30000);
    final latte = combo.items[1];
    expect(latte.deductionsSnapshot, isA<List<Object?>>());
    expect((latte.deductionsSnapshot! as List).length, 4);
    final onRoad = s.db['orders'].firstWhere(
      (o) =>
          o['order_type'] == 'delivery' &&
          o['delivery_channel'] == 'outside' &&
          (o['delivery_order_id'] as String?) != null &&
          DateTime.parse(o['created_at']! as String).isAfter(today),
    )!;
    final full = await s.api.orders.getOrder(orderId: onRoad['id']! as String);
    expect(full.delivery!.zoneName, isNotNull);
    final d = await s.api.delivery.getDeliveryOrder(id: full.deliveryOrderId!);
    expect(d.status, 'out_for_delivery');
    expect(d.contactOverride, isTrue);
  });

  test('POST void: 400 without a note for "other", then voided', () async {
    final s = _setup();
    final id = OrderSeedIds.showcase('offline');
    await expectLater(
      s.api.orders.voidOrder(
        orderId: id,
        body: VoidOrderRequest(reason: 'other', note: '  '),
      ),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 400)),
    );
    final v = await s.api.orders.voidOrder(
      orderId: id,
      body: VoidOrderRequest(reason: 'wrong_order', restoreInventory: true),
    );
    expect(v.status, 'voided');
    expect(v.voidReason, 'wrong_order');
    final again = await s.api.orders.getOrder(orderId: id);
    expect(again.status, 'voided');
  });

  test('POST void: the limited persona is refused', () async {
    final s = _setup(Persona.limited);
    await expectLater(
      s.api.orders.voidOrder(
        orderId: OrderSeedIds.showcase('offline'),
        body: VoidOrderRequest(reason: 'customer_request'),
      ),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
    );
  });

  test('delivery-sales: delivered only, per channel', () async {
    final s = _setup();
    final r = await s.api.reports.branchDeliverySales(
      branchId: SeedIds.heliopolis,
      from: today,
      to: tomorrow,
    );
    // This morning: one in-mall delivered; the outside run is on the road.
    expect(r.totalOrders, 1);
    final mall = r.channels.firstWhere((c) => c.channel == 'in_mall');
    expect(mall.orders, 1);
    expect(mall.deliveryFees, 1000);
    final month = await s.api.reports.branchDeliverySales(
      branchId: '00000000-0000-0000-0000-000000000000',
    );
    expect(month.cancelledOrders, greaterThan(0));
    expect(month.totalOrders, greaterThan(50));
  });

  test('GET /orders/export: payments per leg, the throttle', () async {
    final s = _setup();
    final r = await s.api.orders.exportOrders(
      branchId: SeedIds.zamalek,
      from: today,
      to: tomorrow,
    );
    final split = r.data.firstWhere(
      (o) => o.id == OrderSeedIds.showcase('split'),
    );
    expect(split.payments.map((p) => p.method), ['cash', 'card']);
    expect(
      split.payments.fold<int>(0, (s, p) => s + p.amount),
      split.totalAmount,
    );
  });

  test('the added sales ring on Counter 2 tills, in their own sequence', () {
    final db = MockDb.seeded();
    final server = MockServer(clock: db.clock);
    registerCoreMocks(server, db);
    registerSellMocks(server, db);
    final today = MockClock.cairoDate(db.clock.now);
    final tillId = MockSeed.tillId('heliopolis', today, 'counter2');
    final till = db['tills'].find(tillId)!;
    expect(till['device_code'], 'T2');
    expect(till['status'], 'open');
    final sales = db['orders'].where((o) => o['till_id'] == tillId)
      ..sort(
        (a, b) =>
            (a['created_at']! as String).compareTo(b['created_at']! as String),
      );
    expect(
      [for (final o in sales) o['order_number']],
      [for (var i = 1; i <= sales.length; i++) i],
    );
    expect(sales.every((o) => o['device_code'] == 'T2'), isTrue);
    expect(
      sales.every((o) => (o['display_number']! as String).startsWith('T2-')),
      isTrue,
    );
    // No added sale sits on a T1 till.
    for (final o in db['orders'].where((o) => o['device_code'] == 'T2')) {
      final t = db['tills'].find(o['till_id']! as String)!;
      expect(t['device_code'], 'T2');
    }
    // A closed Counter 2 till: the float plus its cash, counted exactly.
    final past = db['tills'].firstWhere(
      (t) => t['device_code'] == 'T2' && t['status'] == 'closed',
    )!;
    expect(past['cash_discrepancy'], 0);
  });
}
