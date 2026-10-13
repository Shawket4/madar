// The owner's rule (2026-10-11): a filter carries through navigation. Each
// sell list, filtered, left for another page and opened again, shows the
// same filters and asks the server for the same filtered rows
// (`DashRememberedState`, `DashRoute.rememberQuery`).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_sell/src/bookings/bookings_page.dart';
import 'package:dashboard_sell/src/customers/customers_page.dart';
import 'package:dashboard_sell/src/orders/orders_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sell_harness.dart';

Finder _option(String text) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w.runtimeType.toString().startsWith('DashOptionList'),
  ),
  matching: find.text(text),
);

Future<DashHarness> _pump(WidgetTester tester, String path) =>
    pumpSell(tester, path, branchId: SeedIds.heliopolis);

void main() {
  testWidgets('orders: status and payment filters come back', (tester) async {
    final h = await _pump(tester, '/orders');
    await h.tap(find.byKey(const ValueKey('orders-status')));
    await h.tap(_option('Voided'));
    await h.tap(find.byKey(const ValueKey('orders-payment')));
    await h.tap(_option(h.t('payments.cash')));
    await h.go('/customers');
    expect(find.byType(CustomersPage), findsOneWidget);
    final before = h.server.callsTo('/orders').length;
    await h.go('/orders');
    expect(find.byType(OrdersPage), findsOneWidget);
    final calls = h.server.callsTo('/orders');
    expect(calls.length, greaterThanOrEqualTo(before));
    final q = calls.last.query;
    expect(q['status'], ['voided']);
    expect(q['payment_method'] ?? q['payment'], ['cash']);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('orders-status')),
        matching: find.text('Voided'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('customers: Members only comes back', (tester) async {
    final h = await _pump(tester, '/customers');
    await h.tap(
      find.descendant(
        of: find.byType(CustomersPage),
        matching: find.text('Members only'),
      ),
    );
    await h.go('/orders');
    await h.go('/customers');
    final last = h.server.callsTo('/customers', method: 'GET').last;
    expect(last.query['member'], ['true']);
  });

  testWidgets('bookings: the status filter comes back', (tester) async {
    final h = await _pump(tester, '/bookings');
    await h.tap(
      find.descendant(
        of: find.byKey(const ValueKey('bookings-filter')),
        matching: find.text('No-show'),
      ),
    );
    Finder nothing() => find.descendant(
      of: find.byType(BookingsPage),
      matching: find.text('Nothing matches this filter'),
    );
    expect(nothing(), findsOneWidget);
    await h.go('/orders');
    await h.go('/bookings');
    expect(nothing(), findsOneWidget);
  });

  testWidgets('tills: URL filters come back; a branch switch drops the '
      'branch-bound teller', (tester) async {
    final h = await _pump(tester, '/tills?status=closed&teller=t-1');
    await h.go('/orders');
    await h.go('/tills');
    expect(h.location.queryParameters, {'status': 'closed', 'teller': 't-1'});
    await h.container.read(scopeProvider.notifier).setBranch(SeedIds.maadi);
    await h.settle();
    expect(h.location.queryParameters, {'status': 'closed'});
  });
}
