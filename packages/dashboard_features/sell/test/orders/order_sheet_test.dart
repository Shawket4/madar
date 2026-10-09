// The order sheet (SELL-ORD-011, 035 … 062, 086, 087, 090; SELL-ALL-016).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show dashFigure;
import 'package:dashboard_sell/src/customers/customer_sheet.dart';
import 'package:dashboard_sell/src/orders/order_sheet.dart';
import 'package:dashboard_sell/src/orders/orders_page.dart';
import 'package:dashboard_sell/src/shared/phone.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'orders_support.dart';

Finder inSheet(Finder f) =>
    find.descendant(of: find.byType(OrderSheet), matching: f);

Finder inKey(String key, Finder f) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: f);

String _today(MockDb db) => MockClock.cairoDate(db.clock.now);

/// One of the customer's orders in the customer sheet (by its ref).
Finder customerOrder(MockDb db, String orderId) => find.descendant(
  of: find.byType(CustomerSheet),
  matching: find.text(db['orders'].find(orderId)!['order_ref']! as String),
);

/// A summary line's figure (the kit isolates it as a figure).
Finder figure(String money) => find.text(dashFigure(money));

Future<DashHarness> _open(
  WidgetTester tester,
  String orderId, {
  String? branchId = '',
  MockServer? server,
  MockDb? db,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  Persona persona = Persona.owner,
}) => pumpOrders(
  tester,
  query: '?order=$orderId',
  persona: persona,
  branchId: branchId,
  server: server,
  db: db,
  size: size,
  locale: locale,
);

void main() {
  testWidgets('SELL-ORD-011/035/036 ?order= opens the sheet: ref, status, date', (
    tester,
  ) async {
    final id = OrderSeedIds.showcase('offline');
    final h = await _open(tester, id);
    final fmt = h.container.read(formatProvider);
    final o = h.db!['orders'].find(id)!;
    expect(find.byType(OrderSheet), findsOneWidget);
    expect(h.server.callsTo(orderRoute).single.path, '/orders/$id');
    expect(inSheet(find.text(o['order_ref']! as String)), findsOneWidget);
    expect(inSheet(find.text('Completed')), findsOneWidget);
    expect(inSheet(find.text(fmt.fmtDateTimeFull(o['created_at']))), findsWidgets);
    await h.shot('orders/sheet');
  });

  testWidgets('SELL-ORD-062 Close removes ?order=', (tester) async {
    final h = await _open(tester, OrderSeedIds.showcase('offline'));
    expect(h.location.queryParameters['order'], isNotNull);
    await h.tap(inSheet(find.bySemanticsLabel('Close')));
    expect(find.byType(OrderSheet), findsNothing);
    expect(h.location.queryParameters.containsKey('order'), isFalse);
  });

  testWidgets('SELL-ORD-037 loading: four skeleton blocks, "Order", "Loading…"', (
    tester,
  ) async {
    final s = ordersServer();
    final gate = s.server.hold('GET', orderRoute);
    final h = await _open(tester, OrderSeedIds.showcase('offline'), server: s.server, db: s.db);
    expect(find.byKey(const ValueKey('order-sheet-skeleton')), findsOneWidget);
    expect(inSheet(find.text('Order')), findsOneWidget);
    expect(inSheet(find.text('Loading…')), findsOneWidget);
    expect(find.byKey(const ValueKey('order-sheet-void')), findsNothing);
    gate.release();
    await h.settle();
    expect(find.byKey(const ValueKey('order-sheet-skeleton')), findsNothing);
  });

  testWidgets('SELL-ORD-087 a bad ?order= stays on the skeleton; Close works', (
    tester,
  ) async {
    final h = await _open(tester, '00000000-0000-0000-0000-00000000dead');
    expect(h.server.callsTo(orderRoute).single.status, 404);
    expect(find.byKey(const ValueKey('order-sheet-skeleton')), findsOneWidget);
    expect(inSheet(find.text('Loading…')), findsOneWidget);
    await h.tap(inSheet(find.bySemanticsLabel('Close')));
    expect(find.byType(OrderSheet), findsNothing);
  });

  testWidgets('SELL-ORD-038 Void in the header closes the sheet and opens the dialog', (
    tester,
  ) async {
    final id = OrderSeedIds.showcase('offline');
    final h = await _open(tester, id);
    await h.tap(find.byKey(const ValueKey('order-sheet-void')));
    expect(find.byType(OrderSheet), findsNothing);
    expect(find.text('Void order ${h.db!['orders'].find(id)!['order_ref']}'), findsOneWidget);
    expect(h.location.queryParameters.containsKey('order'), isFalse);
  });

  testWidgets('SELL-ORD-039 a voided order: the Voided card, no Void, total struck', (
    tester,
  ) async {
    await _open(tester, OrderSeedIds.showcase('voided'));
    expect(inKey('order-sheet-voided', find.text('Voided')), findsOneWidget);
    expect(inKey('order-sheet-voided', find.text('Other')), findsOneWidget);
    expect(find.byKey(const ValueKey('order-sheet-void')), findsNothing);
    final total = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('order-sheet-total')),
        matching: find.text('Total'),
      ),
    );
    expect(total.style!.decoration, TextDecoration.lineThrough);
  });

  testWidgets('SELL-ORD-039 an unknown void reason shows raw', (tester) async {
    final s = ordersServer();
    s.db['orders'].find(OrderSeedIds.showcase('voided'))!['void_reason'] = 'till_crashed';
    await _open(tester, OrderSeedIds.showcase('voided'), server: s.server, db: s.db);
    expect(inKey('order-sheet-voided', find.text('till_crashed')), findsOneWidget);
  });

  testWidgets('SELL-ORD-040 the reward-refused alert quotes the server', (tester) async {
    final h = await _open(tester, OrderSeedIds.showcase('refused'));
    final card = find.byKey(const ValueKey('order-sheet-reward-refused'));
    expect(find.descendant(of: card, matching: find.text(h.t('orders.rewardRefusedTitle'))), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text(h.t('orders.rewardRefusedBody'))), findsOneWidget);
    expect(
      find.descendant(
        of: card,
        matching: find.text('“Not enough stamps: the card holds 3 and the reward needs 6.”'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SELL-ORD-041/060 the loyalty member opens read-only; another of '
      'their orders replaces this one, this one just closes the member', (
    tester,
  ) async {
    final id = OrderSeedIds.showcase('reward');
    final h = await _open(tester, id);
    final member = h.db!['orders'].find(id)!;
    expect(inSheet(find.text('Loyalty member')), findsOneWidget);
    await h.tap(find.byKey(const ValueKey('order-sheet-member')));
    expect(find.byType(CustomerSheet), findsOneWidget);
    expect(h.server.callsTo('/customers/{id}').last.path, '/customers/${member['customer_id']}');
    // This same order: only the member sheet closes.
    await h.tap(customerOrder(h.db!, id));
    expect(find.byType(CustomerSheet), findsNothing);
    expect(find.byType(OrderSheet), findsOneWidget);
    expect(h.location.queryParameters['order'], id);
    // Another of their orders: the sheet follows it.
    await h.tap(find.byKey(const ValueKey('order-sheet-member')));
    final other = h.db!['orders']
        .where((o) => o['customer_id'] == member['customer_id'] && o['id'] != id)
        .reduce((a, b) => (a['created_at']! as String).compareTo(b['created_at']! as String) > 0 ? a : b);
    await h.tap(customerOrder(h.db!, other['id']! as String));
    expect(find.byType(CustomerSheet), findsNothing);
    expect(h.location.queryParameters['order'], other['id']);
    expect(find.byType(OrderSheet), findsOneWidget);
    expect(inSheet(find.text(other['order_ref']! as String)), findsOneWidget);
  });

  testWidgets('SELL-ORD-041 a forgotten member reads "Deleted member", no link', (
    tester,
  ) async {
    final s = ordersServer();
    s.db['orders'].find(OrderSeedIds.showcase('reward'))!['loyalty_member_name'] = null;
    await _open(tester, OrderSeedIds.showcase('reward'), server: s.server, db: s.db);
    expect(inSheet(find.text('Deleted member')), findsOneWidget);
    expect(find.byKey(const ValueKey('order-sheet-member')), findsNothing);
  });

  testWidgets('SELL-ORD-041/042 without the people caps the names are text', (
    tester,
  ) async {
    final s = ordersServer();
    dropCaps(s.server, {'customers.view', 'loyalty.members.list', 'loyalty.read'});
    final h = await _open(tester, OrderSeedIds.showcase('reward'), server: s.server, db: s.db);
    final name = s.db['orders'].find(OrderSeedIds.showcase('reward'))!['customer_name']! as String;
    expect(find.byKey(const ValueKey('order-sheet-member')), findsNothing);
    expect(inSheet(find.text('Loyalty member')), findsOneWidget);
    await h.tap(inSheet(find.text(name)).first);
    expect(find.byType(CustomerSheet), findsNothing);
    expect(h.server.callsTo('/customers/{id}'), isEmpty);
  });

  testWidgets('SELL-ORD-042 info rows: teller, started by, waiter, customer, split legs', (
    tester,
  ) async {
    final id = OrderSeedIds.showcase('split');
    final h = await _open(tester, id, branchId: SeedIds.zamalek);
    final fmt = h.container.read(formatProvider);
    final o = h.db!['orders'].find(id)!;
    expect(inSheet(find.text('Youssef Samir')), findsOneWidget);
    expect(inSheet(find.text('Started by')), findsOneWidget);
    expect(inSheet(find.text('Mariam Fathy')), findsOneWidget);
    expect(inSheet(find.text('Adham Reda')), findsOneWidget);
    final legs = (o['payment_legs']! as List).cast<Map<String, Object?>>();
    expect(inSheet(find.text('Cash ${fmt.fmtMoney(legs[0]['amount']! as int)}')), findsOneWidget);
    expect(inSheet(find.text('Card ${fmt.fmtMoney(legs[1]['amount']! as int)}')), findsOneWidget);
    expect(inSheet(find.text('Tip')), findsOneWidget);
  });

  testWidgets('SELL-ORD-042 one leg: one method badge; no started-by when the '
      'teller started it', (tester) async {
    final h = await _open(tester, OrderSeedIds.showcase('offline'));
    expect(inSheet(find.text('Card')), findsOneWidget);
    expect(inSheet(find.text('Started by')), findsNothing);
    expect(inSheet(find.text('Waiter')), findsNothing);
    expect(h.server.callsTo(deliveryOrderRoute), isEmpty);
  });

  testWidgets('SELL-ORD-043/044/045 an outside delivery: the card, the note, '
      'Open in Maps, the progress', (tester) async {
    final s = ordersServer();
    final sale = OrderSeedIds.deliverySale('heliopolis', _today(s.db), 8);
    final h = await _open(tester, sale, server: s.server, db: s.db);
    final card = find.byKey(const ValueKey('order-sheet-delivery'));
    Finder inCard(Finder f) => find.descendant(of: card, matching: f);
    expect(inSheet(find.text('Outside')), findsWidgets);
    expect(inCard(find.text('Phone')), findsOneWidget);
    expect(
      inCard(find.text('Abou Bakr El-Seddik St 7 · Behind Triumph Hotel · Floor 11 · Unit 8')),
      findsOneWidget,
    );
    expect(inCard(find.text('Heliopolis — Zone A')), findsOneWidget);
    expect(inCard(find.textContaining('2.7 km')), findsOneWidget);
    expect(inCard(find.text('DLV-1008H8')), findsOneWidget);
    // Ordered by the customer for someone else; the customer read once.
    final owner = s.db['customers'].find(s.db['orders'].find(sale)!['customer_id']! as String)!;
    expect(h.server.callsTo('/customers/{id}').single.path, '/customers/${owner['id']}');
    final note = find.byKey(const ValueKey('order-sheet-contact-note'));
    final noteText = tester.widget<Text>(find.descendant(of: note, matching: find.byType(Text))).textSpan!.toPlainText();
    expect(noteText, startsWith('Ordered by ${owner['name']} for Mona Adel · '));
    expect(noteText, contains(formatPhoneDisplay('01223456781').replaceAll(' ', '\u00A0')));
    await h.tap(find.byKey(const ValueKey('order-sheet-maps')));
    expect(h.openedLinks.single.toString(), startsWith('https://www.google.com/maps/search/?api=1&query=30.0997,31.3305'));
    // Delivery progress: on the road.
    final steps = find.byKey(const ValueKey('order-sheet-timeline'));
    expect(find.descendant(of: steps, matching: find.text('Delivery progress')), findsOneWidget);
    for (final w in ['Received', 'Confirmed', 'Preparing', 'Ready', 'Out for delivery', 'Delivered']) {
      expect(find.descendant(of: steps, matching: find.text(w)), findsOneWidget, reason: w);
    }
    expect(find.bySemanticsLabel(h.t('deliveryTimeline.hint')), findsOneWidget);
    final fmt = h.container.read(formatProvider);
    final d = s.db['delivery_orders'].find(s.db['orders'].find(sale)!['delivery_order_id']! as String)!;
    expect(find.descendant(of: steps, matching: find.text(fmt.fmtDateTimeFull(d['out_for_delivery_at']))), findsOneWidget);
    await h.shot('orders/sheet-delivery');
  });

  testWidgets('SELL-ORD-044 without customers.view: "Ordered for someone else", '
      'no customer read', (tester) async {
    final s = ordersServer();
    dropCaps(s.server, {'customers.view'});
    final sale = OrderSeedIds.deliverySale('heliopolis', _today(s.db), 8);
    final h = await _open(tester, sale, server: s.server, db: s.db);
    final note = find.byKey(const ValueKey('order-sheet-contact-note'));
    final text = tester.widget<Text>(find.descendant(of: note, matching: find.byType(Text))).textSpan!.toPlainText();
    expect(text, startsWith('Ordered for someone else: Mona Adel'));
    expect(h.server.callsTo('/customers/{id}'), isEmpty);
  });

  testWidgets('SELL-ORD-043 an in-mall delivery: place, floor, unit, notes, no Maps', (
    tester,
  ) async {
    final s = ordersServer();
    final sale = OrderSeedIds.deliverySale('heliopolis', _today(s.db), 7);
    await _open(tester, sale, server: s.server, db: s.db);
    final card = find.byKey(const ValueKey('order-sheet-delivery'));
    Finder inCard(Finder f) => find.descendant(of: card, matching: f);
    expect(inCard(find.text('In-mall')), findsOneWidget);
    expect(inCard(find.text('Korba Plaza · Floor 2 · Unit 217')), findsOneWidget);
    expect(inCard(find.text('Leave it at the shop counter.')), findsOneWidget);
    expect(find.byKey(const ValueKey('order-sheet-contact-note')), findsNothing);
    expect(find.byKey(const ValueKey('order-sheet-maps')), findsNothing);
  });

  testWidgets('SELL-ORD-045 a cancelled delivery shows only the danger pill', (
    tester,
  ) async {
    final s = ordersServer();
    final sale = OrderSeedIds.deliverySale('heliopolis', _today(s.db), 8);
    s.db['delivery_orders'].find(s.db['orders'].find(sale)!['delivery_order_id']! as String)!['status'] = 'cancelled';
    await _open(tester, sale, server: s.server, db: s.db);
    final steps = find.byKey(const ValueKey('order-sheet-timeline'));
    expect(find.descendant(of: steps, matching: find.text('Cancelled')), findsOneWidget);
    expect(find.descendant(of: steps, matching: find.text('Received')), findsNothing);
  });

  testWidgets('SELL-ORD-086 delivery.* refreshes an open sheet\'s progress', (
    tester,
  ) async {
    final s = ordersServer();
    final sale = OrderSeedIds.deliverySale('heliopolis', _today(s.db), 8);
    final h = await _open(tester, sale, server: s.server, db: s.db);
    final reads = h.server.callsTo(deliveryOrderRoute).length;
    final orderReads = h.server.callsTo(orderRoute).length;
    final d = s.db['delivery_orders'].find(s.db['orders'].find(sale)!['delivery_order_id']! as String)!;
    d['status'] = 'delivered';
    d['delivered_at'] = s.db.clock.now.toIso8601String();
    h.realtime.current!.emit('delivery.status_changed', data: '{}');
    await h.settle();
    expect(h.server.callsTo(deliveryOrderRoute).length, reads + 1);
    expect(h.server.callsTo(orderRoute).length, orderReads, reason: 'the order itself stays');
    final fmt = h.container.read(formatProvider);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('order-sheet-timeline')),
        matching: find.text(fmt.fmtDateTimeFull(d['delivered_at'])),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SELL-ORD-046/049/050/051/057 a combo with its parts and a deal', (
    tester,
  ) async {
    final id = OrderSeedIds.showcase('combo');
    final h = await _open(tester, id);
    final fmt = h.container.read(formatProvider);
    final items = find.byKey(const ValueKey('order-sheet-items'));
    Finder inItems(Finder f) => find.descendant(of: items, matching: f);
    expect(inItems(find.text('Items')), findsOneWidget);
    expect(inItems(find.text('${ltr('1 ×')} Breakfast Box')), findsOneWidget);
    expect(inItems(find.text('Combo')), findsOneWidget);
    expect(inItems(find.text('${fmt.fmtMoney(18500)} each, before extras')), findsOneWidget);
    expect(inItems(find.text('Croissant warmed, please')), findsOneWidget);
    // 110 + 90: the parts.
    expect(inItems(find.text(fmt.fmtMoney(20000))), findsOneWidget);
    expect(inItems(find.text('Hot drink')), findsOneWidget);
    expect(inItems(find.text('Pastry · +${fmt.fmtMoney(1500)} upgrade')), findsOneWidget);
    expect(inItems(find.text('Morning Duo · ${fmt.fmtMoney(-1000)}')), findsOneWidget);
    // The parts sit under their header, in order.
    final header = tester.getTopLeft(inItems(find.text('${ltr('1 ×')} Breakfast Box'))).dy;
    final part = tester.getTopLeft(inItems(find.text('Hot drink'))).dy;
    expect(part, greaterThan(header));
    final summary = find.byKey(const ValueKey('order-sheet-summary'));
    Finder inSum(Finder f) => find.descendant(of: summary, matching: f);
    expect(inSum(find.text('Items at normal price')), findsOneWidget);
    expect(inSum(figure(fmt.fmtMoney(31000))), findsOneWidget);
    expect(inSum(find.text('Morning Duo')), findsOneWidget);
    expect(inSum(figure(fmt.fmtMoney(-1000))), findsOneWidget);
    expect(inSum(figure(fmt.fmtMoney(30000))), findsOneWidget);
    await h.shot('orders/sheet-combo');
  });

  testWidgets('SELL-ORD-046 a part whose header is missing shows as a plain line', (
    tester,
  ) async {
    final s = ordersServer();
    final row = s.db['order_details'].find(OrderSeedIds.showcase('combo'))!;
    row['items'] = [...(row['items']! as List).skip(1)];
    await _open(tester, OrderSeedIds.showcase('combo'), server: s.server, db: s.db);
    expect(find.text('Combo'), findsNothing);
    expect(find.textContaining('Caffè Latte'), findsOneWidget);
  });

  testWidgets('SELL-ORD-047/048/058 a reward line: pill, one minus, the '
      'loyalty line in the summary', (tester) async {
    final id = OrderSeedIds.showcase('reward');
    final h = await _open(tester, id);
    final fmt = h.container.read(formatProvider);
    final name = h.db!['orders'].find(id)!['loyalty_member_name']! as String;
    final items = find.byKey(const ValueKey('order-sheet-items'));
    expect(find.descendant(of: items, matching: find.text('Reward')), findsOneWidget);
    expect(find.descendant(of: items, matching: find.text('(Regular)')), findsOneWidget);
    // en.json's template holds the minus: one, never two (divergence log).
    expect(
      find.descendant(of: items, matching: find.text('Reward covers 1 · −${fmt.fmtMoney(11500)}')),
      findsOneWidget,
    );
    expect(find.textContaining('−−'), findsNothing);
    expect(find.descendant(of: items, matching: find.text('× 1 · ${fmt.fmtMoney(11500)}')), findsOneWidget);
    final summary = find.byKey(const ValueKey('order-sheet-summary'));
    expect(find.descendant(of: summary, matching: find.text('Loyalty rewards · $name')), findsOneWidget);
    expect(find.descendant(of: summary, matching: figure(fmt.fmtMoney(-11500))), findsOneWidget);
  });

  testWidgets('SELL-ORD-047/052/053/054/055/057 a staff drink: pills, add-ons, '
      'optionals, notes, the breakdown, the summary', (tester) async {
    final h = await _open(tester, OrderSeedIds.showcase('staff'));
    final fmt = h.container.read(formatProvider);
    final items = find.byKey(const ValueKey('order-sheet-items'));
    Finder inItems(Finder f) => find.descendant(of: items, matching: f);
    expect(inItems(find.text('Staff drink')), findsOneWidget);
    final addons = [
      for (final e in inItems(find.byType(RichText)).evaluate())
        (e.widget as RichText).text.toPlainText(),
    ];
    expect(addons, contains('+ Oat milk (${nbsp(fmt.fmtMoney(2500))})'));
    expect(
      addons,
      contains('+ Extra shot (${nbsp(fmt.fmtMoney(3000))}) given free ${nbsp(fmt.fmtMoney(-3000))}'),
    );
    expect(inItems(find.text('Less sugar')), findsOneWidget);
    expect(inItems(find.text('For Ali, end of shift')), findsOneWidget);
    final line = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('staff-line-'),
    );
    Finder inLine(Finder f) => find.descendant(of: line, matching: f);
    expect(inLine(find.text('Normal price, with extras')), findsOneWidget);
    expect(inLine(find.text(fmt.fmtMoney(18500))), findsOneWidget);
    expect(inLine(find.text(fmt.fmtMoney(-16000))), findsOneWidget);
    expect(inLine(find.text(fmt.fmtMoney(2500))), findsOneWidget);
    final summary = find.byKey(const ValueKey('order-sheet-summary'));
    Finder inSum(Finder f) => find.descendant(of: summary, matching: f);
    expect(inSum(find.text('Items at normal price')), findsOneWidget);
    expect(inSum(find.text('Staff drinks · given free')), findsOneWidget);
    expect(inSum(figure(fmt.fmtMoney(-16000))), findsOneWidget);
    expect(inSum(figure(fmt.fmtMoney(18500))), findsOneWidget);
    await h.shot('orders/sheet-staff');
  });

  testWidgets('SELL-ORD-047/056/059 cost per line, the ingredients list, COGS', (
    tester,
  ) async {
    final h = await _open(tester, OrderSeedIds.showcase('combo'));
    final fmt = h.container.read(formatProvider);
    final latte = OrderSeedIds.line(OrderSeedIds.showcase('combo'), 1);
    // 18 g blend × 0.95 + 160 ml milk × 0.042 + cup 1.80 + lid 0.60.
    expect(find.text('Cost: ${fmt.fmtMoney(2622)}'), findsNWidgets(2));
    final toggle = find.byKey(ValueKey('ingredients-$latte'));
    expect(find.descendant(of: toggle, matching: find.text('Ingredients Used (4)')), findsOneWidget);
    expect(find.textContaining('House espresso blend'), findsNothing, reason: 'closed');
    await h.tap(toggle);
    expect(find.text('House espresso blend: ${ltr('18 g')}'), findsOneWidget);
    expect(find.text(fmt.fmtMoney(1710)), findsOneWidget);
    // Packaging carries no snapshot cost: priced from the catalogue.
    expect(find.text('12oz paper cup: ${ltr('1 pcs')}'), findsOneWidget);
    expect(find.text(fmt.fmtMoney(180)), findsWidgets);
    expect(h.server.callsTo(catalogRoute).single.path, '/inventory/orgs/${SeedIds.sabahOrg}/catalog');
    // COGS 26.22 + 18.00 + 26.22; profit on 300.00.
    final cogs = find.byKey(const ValueKey('order-sheet-cogs'));
    String all() => [
      for (final e in find.descendant(of: cogs, matching: find.byType(RichText)).evaluate())
        (e.widget as RichText).text.toPlainText(),
    ].join(' | ');
    expect(all(), contains('COGS: ${fmt.fmtMoney(7044)}'));
    expect(all(), contains('Gross profit: ${fmt.fmtMoney(22956)} (${fmt.fmtPercent(22956 / 30000)})'));
  });

  testWidgets('SELL-ORD-047/059 a line without a cost: "Cost unknown", ≥ and ≤', (
    tester,
  ) async {
    final h = await _open(tester, OrderSeedIds.showcase('split'), branchId: SeedIds.zamalek);
    expect(find.textContaining('Cost unknown for this line'), findsOneWidget);
    final cogs = find.byKey(const ValueKey('order-sheet-cogs'));
    final text = [
      for (final e in find.descendant(of: cogs, matching: find.byType(RichText)).evaluate())
        (e.widget as RichText).text.toPlainText(),
    ].join(' | ');
    expect(text, contains('≥ '));
    expect(text, contains('≤ '));
    expect(h.server.unmatched, isEmpty);
  });

  testWidgets('SELL-ORD-058 a discount with its attribution', (tester) async {
    final s = ordersServer();
    final o = s.db['orders'].firstWhere(
      (o) => o['branch_id'] == SeedIds.heliopolis && (o['discount_amount']! as int) > 0,
    )!;
    final h = await _open(tester, o['id']! as String, server: s.server, db: s.db, branchId: SeedIds.heliopolis);
    final fmt = h.container.read(formatProvider);
    final summary = find.byKey(const ValueKey('order-sheet-summary'));
    Finder inSum(Finder f) => find.descendant(of: summary, matching: f);
    expect(inSum(find.text('Discount')), findsOneWidget);
    expect(inSum(figure(fmt.fmtMoney(-(o['discount_amount']! as int)))), findsOneWidget);
    expect(
      inSum(find.text('${h.t('discounts.kind.manualPercent')} · 10% · by ${o['discount_applied_by_name']}')),
      findsOneWidget,
    );
    expect(inSum(find.text('Tax')), findsOneWidget);
    expect(inSum(find.text('Delivery fee')), findsNothing);
  });

  testWidgets('SELL-ORD-061/SELL-ALL-016 a customer from the table: an order '
      'chosen there opens in this page\'s sheet, with Void', (tester) async {
    final h = await pumpOrders(tester);
    final reward = h.db!['orders'].find(OrderSeedIds.showcase('reward'))!;
    await h.tap(inTable(find.text(reward['customer_name']! as String)));
    expect(find.byType(CustomerSheet), findsOneWidget);
    await h.tap(customerOrder(h.db!, OrderSeedIds.showcase('reward')));
    expect(find.byType(CustomerSheet), findsNothing);
    expect(find.byType(OrderSheet), findsOneWidget);
    expect(h.location.queryParameters['order'], OrderSeedIds.showcase('reward'));
    expect(find.byKey(const ValueKey('order-sheet-void')), findsOneWidget);
  });

  testWidgets('SELL-ORD-090 the sheet opened from elsewhere has no Void', (tester) async {
    final h = await pumpOrders(tester);
    final ctx = tester.element(find.byType(OrdersPage));
    showOrderSheet(ctx, orderId: OrderSeedIds.showcase('offline'));
    await h.settle();
    expect(find.byType(OrderSheet), findsOneWidget);
    expect(inSheet(find.text('Completed')), findsOneWidget);
    expect(find.byKey(const ValueKey('order-sheet-void')), findsNothing);
  });

  testWidgets('SELL-ORD-035 phone: the sheet is full screen, close at the start', (
    tester,
  ) async {
    final h = await _open(tester, OrderSeedIds.showcase('combo'), size: DashSize.phone, locale: 'ar');
    expect(find.byType(OrderSheet), findsOneWidget);
    expect(tester.getSize(find.byType(OrderSheet)).width, DashSize.phone.size.width);
    await h.shot('orders/sheet');
  });

  testWidgets('SELL-ORD-087 a refused read (another branch) stays on the skeleton', (
    tester,
  ) async {
    final s = ordersServer(persona: Persona.manager);
    final h = await _open(
      tester,
      OrderSeedIds.showcase('offline'),
      server: s.server,
      db: s.db,
      branchId: SeedIds.zamalek,
      persona: Persona.manager,
    );
    expect(h.server.callsTo(orderRoute).single.status, 403);
    expect(find.byKey(const ValueKey('order-sheet-skeleton')), findsOneWidget);
  });
}
