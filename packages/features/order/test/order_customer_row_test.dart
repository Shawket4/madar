// The customer on a cart or an open bill: one row that picks, names and
// removes — gated on `customers.attach` — and the label a bills list shows.

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/order_customer_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

class _Fake implements MadarBridge {
  _Fake({this.mayAttach = true});

  final bool mayAttach;
  final customers = <String, CustomerView>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final a = invocation.namedArguments;
    if (name == #can) return a[#cap] != Cap.customersAttach || mayAttach;
    if (name == #tr) return coreWord(a[#key] as String);
    if (name == #customerById) return customers[a[#id]];
    if (name == #searchCustomers) return customers.values.toList();
    return null;
  }
}

const _mona = CustomerView(
  id: 'c-mona',
  name: 'Mona Adel',
  phoneHint: '•••• 4567',
  loyaltyCustomerId: 'c-mona',
  pending: false,
  isMember: true,
);

const _omar = CustomerView(
  id: 'c-omar',
  name: 'Omar',
  pending: false,
  isMember: false,
);

TicketView _bill({String? table, String? name, String? customerId}) =>
    TicketView(
      id: 't1',
      tableId: table,
      status: 'open',
      ready: false,
      customerName: name,
      customerId: customerId,
      subtotalMinor: 800,
      openedAt: '2026-09-13T09:00:00Z',
      queuedOffline: false,
      lines: const [],
    );

Future<void> _pump(WidgetTester tester, _Fake bridge, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
      child: MaterialApp(
        theme: MadarTheme.light(),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('nobody on the order and no permission: nothing at all', (
    tester,
  ) async {
    await _pump(
      tester,
      _Fake(mayAttach: false),
      OrderCustomerRow(customerId: null, onChanged: (_) {}),
    );
    expect(find.byKey(const ValueKey('order.customer')), findsNothing);
  });

  testWidgets('somebody on the order shows to everyone, removable with it', (
    tester,
  ) async {
    final seen = _Fake(mayAttach: false)..customers['c-mona'] = _mona;
    await _pump(
      tester,
      seen,
      OrderCustomerRow(customerId: 'c-mona', onChanged: (_) {}),
    );
    expect(find.text('Mona Adel · Member'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove customer'), findsNothing);

    final changes = <CustomerView?>[];
    final may = _Fake()..customers['c-mona'] = _mona;
    await _pump(
      tester,
      may,
      OrderCustomerRow(customerId: 'c-mona', onChanged: changes.add),
    );
    await tester.tap(find.bySemanticsLabel('Remove customer'));
    expect(changes, [null]);
  });

  testWidgets('nobody yet: the row opens the picker and hands back the pick', (
    tester,
  ) async {
    final changes = <CustomerView?>[];
    final bridge = _Fake()..customers['c-omar'] = _omar;
    await _pump(
      tester,
      bridge,
      OrderCustomerRow(customerId: null, onChanged: changes.add),
    );
    await tester.tap(find.byKey(const ValueKey('order.customer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Omar').last);
    await tester.pumpAndSettle();
    expect(changes.single?.id, 'c-omar');
  });

  test('a bills list names the linked customer, else the typed name', () {
    final bridge = _Fake()
      ..customers['c-mona'] = _mona
      ..customers['c-omar'] = _omar;
    String? label(TicketView t) =>
        billCustomerLabel(bridge, t, nameIsTitle: t.tableId == null);
    // On a table: the typed name, or the customer with the member badge.
    expect(label(_bill(table: 'T1', name: 'Sara')), 'Sara');
    expect(
      label(_bill(table: 'T1', name: 'Sara', customerId: 'c-mona')),
      'Mona Adel · Member',
    );
    expect(label(_bill(table: 'T1', customerId: 'c-omar')), 'Omar');
    // Table-less: the title is already the name; only the rest is added.
    expect(label(_bill(name: 'Sara')), isNull);
    expect(label(_bill(name: 'Omar', customerId: 'c-omar')), isNull);
    expect(label(_bill(name: 'Mona Adel', customerId: 'c-mona')), 'Member');
    expect(label(_bill(name: 'Table 9 lady', customerId: 'c-omar')), 'Omar');
    // A customer this till does not hold reads as the typed name.
    expect(label(_bill(table: 'T1', name: 'Sara', customerId: 'c-x')), 'Sara');
  });
}
