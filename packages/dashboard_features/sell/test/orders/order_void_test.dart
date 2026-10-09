// The void dialog (SELL-ORD-063 … 069, 088; SELL-ALL-017).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/orders/order_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'orders_support.dart';

final String _offline = OrderSeedIds.showcase('offline');

Future<void> _openVoid(DashHarness h, String id) async {
  await h.tap(find.byKey(ValueKey('order-actions-$id')));
  await h.tap(find.text('Void order').last);
}

Finder get _submit => find.byKey(const ValueKey('void-submit'));

bool _enabled(WidgetTester tester) =>
    tester.widget<DashButton>(_submit).onPressed != null;

Future<void> _pickReason(DashHarness h, String label) async {
  await h.tap(find.byKey(const ValueKey('void-reason')));
  await h.tap(
    find.descendant(
      of: find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('DashOptionList'),
      ),
      matching: find.text(label),
    ),
  );
}

void main() {
  testWidgets(
    'SELL-ORD-063/064/065/066 the dialog: title with the ref, reason, '
    'note, restore on',
    (tester) async {
      final h = await pumpOrders(tester);
      await _openVoid(h, _offline);
      final ref = h.db!['orders'].find(_offline)!['order_ref'];
      expect(find.text('Void order $ref'), findsOneWidget);
      expect(find.text(h.t('orders.voidDesc')), findsOneWidget);
      expect(find.text('Reason'), findsOneWidget);
      expect(find.text('Customer request'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('Add details…'), findsOneWidget);
      expect(find.text('Restore inventory from this order'), findsOneWidget);
      expect(
        tester
            .widget<DashSwitchField>(find.byKey(const ValueKey('void-restore')))
            .value,
        isTrue,
      );
      await h.tap(find.byKey(const ValueKey('void-reason')));
      for (final r in [
        'Customer request',
        'Wrong order',
        'Quality issue',
        'Other',
      ]) {
        expect(find.text(r), findsWidgets, reason: r);
      }
      await h.tap(find.text('Wrong order').last);
      await h.shot('orders/void-dialog');
    },
  );

  testWidgets(
    'SELL-ORD-065 "Other" needs a note: the star, the hint, Void off',
    (tester) async {
      final h = await pumpOrders(tester);
      await _openVoid(h, _offline);
      expect(_enabled(tester), isTrue);
      await _pickReason(h, 'Other');
      expect(find.text('A note is required for "Other"'), findsOneWidget);
      expect(_enabled(tester), isFalse);
      await h.enterText(find.byKey(const ValueKey('void-note')), '   ');
      expect(_enabled(tester), isFalse);
      await h.enterText(
        find.byKey(const ValueKey('void-note')),
        'Spilled at the counter',
      );
      expect(find.text('A note is required for "Other"'), findsNothing);
      expect(_enabled(tester), isTrue);
    },
  );

  testWidgets('SELL-ORD-067 Cancel closes without a call', (tester) async {
    final h = await pumpOrders(tester);
    await _openVoid(h, _offline);
    await h.tapText('Cancel');
    expect(_submit, findsNothing);
    expect(h.server.callsTo(voidRoute), isEmpty);
  });

  testWidgets('SELL-ORD-068 Void: the body, the toast, the list and the order '
      'refetched, reason and note reset, restore kept', (tester) async {
    final h = await pumpOrders(tester);
    await h.tap(find.byKey(ValueKey('order-actions-$_offline')));
    await h.tap(find.text('Details'));
    final lists = h.server.callsTo(listRoute).length;
    final reads = h.server.callsTo(orderRoute).length;
    await h.tap(
      find.descendant(
        of: find.byType(OrderSheet),
        matching: find.bySemanticsLabel('Close'),
      ),
    );
    await _openVoid(h, _offline);
    await _pickReason(h, 'Quality issue');
    await h.enterText(find.byKey(const ValueKey('void-note')), '  Cold milk  ');
    await h.tap(
      find.descendant(
        of: find.byKey(const ValueKey('void-restore')),
        matching: find.byType(DashSwitch),
      ),
    );
    await h.tap(_submit);
    final call = h.server.callsTo(voidRoute).single;
    expect(call.path, '/orders/$_offline/void');
    expect(call.body, {
      'reason': 'quality_issue',
      'note': 'Cold milk',
      'restore_inventory': false,
    });
    await h.expectToast('Order voided');
    expect(_submit, findsNothing);
    expect(
      h.server.callsTo(listRoute).length,
      lists + 1,
      reason: 'the list refetched',
    );
    // The order's own read is invalidated: opening it asks again.
    await h.tap(find.byKey(ValueKey('order-actions-$_offline')));
    await h.tap(find.text('Details'));
    expect(h.server.callsTo(orderRoute).length, reads + 1);
    expect(
      find.descendant(
        of: find.byType(OrderSheet),
        matching: find.text('Voided'),
      ),
      findsWidgets,
    );
    await h.tap(
      find.descendant(
        of: find.byType(OrderSheet),
        matching: find.bySemanticsLabel('Close'),
      ),
    );
    // Reason and note reset; the switch keeps its last value.
    final other = OrderSeedIds.showcase('staff');
    await _openVoid(h, other);
    expect(find.text('Customer request'), findsOneWidget);
    expect(find.text('Cold milk'), findsNothing);
    expect(
      tester
          .widget<DashSwitchField>(find.byKey(const ValueKey('void-restore')))
          .value,
      isFalse,
    );
  });

  testWidgets('SELL-ORD-088 Cancel keeps the reason and the note, even for '
      'another order', (tester) async {
    final h = await pumpOrders(tester);
    await _openVoid(h, _offline);
    await _pickReason(h, 'Wrong order');
    await h.enterText(find.byKey(const ValueKey('void-note')), 'Rang twice');
    await h.tapText('Cancel');
    await _openVoid(h, OrderSeedIds.showcase('staff'));
    expect(find.text('Wrong order'), findsOneWidget);
    expect(find.text('Rang twice'), findsOneWidget);
  });

  testWidgets(
    'SELL-ORD-069/SELL-ALL-017 a refusal toasts its words; the dialog '
    'stays',
    (tester) async {
      final h = await pumpOrders(
        tester,
        persona: Persona.limited,
        branchId: SeedIds.maadi,
      );
      final id =
          h.db!['orders']
                  .where(
                    (o) =>
                        o['branch_id'] == SeedIds.maadi &&
                        o['status'] == 'completed',
                  )
                  .last['id']!
              as String;
      await h.go('/orders?order=$id');
      await h.tap(find.byKey(const ValueKey('order-sheet-void')));
      await h.tap(_submit);
      expect(h.server.callsTo(voidRoute).single.status, 403);
      await h.expectToast(h.refusalWords(MockResponse.denied('orders.void')));
      expect(_submit, findsOneWidget);
      expect(tester.widget<DashButton>(_submit).loading, isFalse);
    },
  );

  testWidgets('SELL-ORD-069 a server refusal (400) toasts its words', (
    tester,
  ) async {
    final s = ordersServer();
    final response = MockResponse.badRequest('This sale was refunded');
    s.server.fail('POST', voidRoute, response);
    final h = await pumpOrders(tester, server: s.server, db: s.db);
    await _openVoid(h, _offline);
    await h.tap(_submit);
    await h.expectToast(h.refusalWords(response));
    expect(_submit, findsOneWidget);
  });

  testWidgets('SELL-ORD-068 void in flight: the button spins', (tester) async {
    final s = ordersServer();
    final gate = s.server.hold('POST', voidRoute);
    final h = await pumpOrders(tester, server: s.server, db: s.db);
    await _openVoid(h, _offline);
    await h.tap(_submit);
    expect(tester.widget<DashButton>(_submit).loading, isTrue);
    gate.release();
    await h.settle();
    await h.expectToast('Order voided');
  });

  testWidgets('SELL-ORD-069 a refunded sale cannot be voided: the 409 words, '
      'the dialog stays', (tester) async {
    final s = ordersServer();
    s.db['order_refunds'].insert({
      'order_id': _offline,
      'amount': 4500,
    }, timestamps: false);
    final h = await pumpOrders(tester, server: s.server, db: s.db);
    await _openVoid(h, _offline);
    await h.tap(_submit);
    expect(h.server.callsTo(voidRoute).single.status, 409);
    await h.expectToast(
      h.refusalWords(
        MockResponse.conflict(
          '4500 has already been refunded against this sale, so it cannot '
          'be voided — refund the remainder instead.',
        ),
      ),
    );
    expect(_submit, findsOneWidget);
    expect(s.db['orders'].find(_offline)!['status'], 'completed');
  });
}
