// The customer card: who someone is, from what the till already holds, with
// their saved addresses asked of the server only for someone who may see
// them — and never in the way when they cannot be had.

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

class _Fake implements MadarBridge {
  _Fake({this.mayViewAddresses = true, this.addresses, this.arabic = false});

  final bool mayViewAddresses;
  final bool arabic;

  /// Null: the server cannot be reached.
  final List<CustomerAddressView>? addresses;

  /// The customers this till's list holds.
  final customers = <String, CustomerView>{};

  /// Who the addresses were asked for.
  final asked = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final a = invocation.namedArguments;
    if (name == #can) {
      return a[#cap] != Cap.customersAddressesView || mayViewAddresses;
    }
    if (name == #tr) return coreWord(a[#key] as String, arabic: arabic);
    if (name == #customerById) return customers[a[#id]];
    if (name == #customerAddresses) {
      asked.add(a[#customerId] as String);
      final rows = addresses;
      return rows == null
          ? Future<List<CustomerAddressView>>.error(
              const MadarError.offline(detail: 'offline'),
            )
          : Future.value(rows);
    }
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
  balanceLabel: '120 points',
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
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('name, the phone hint, the member badge and balance, addresses', (
    tester,
  ) async {
    final bridge = _Fake(
      addresses: const [
        CustomerAddressView(
          id: 'a-1',
          label: 'Home',
          line: 'Tower B · 12 · 3 · 12 Brazil St',
          notes: 'Ring twice',
          useCount: 7,
        ),
        CustomerAddressView(id: 'a-2', line: 'Office Park', useCount: 1),
      ],
    );
    await _pump(tester, bridge, const CustomerCardSheet(customer: _mona));
    expect(bridge.asked, ['c-mona']);
    expect(find.text('Mona Adel'), findsOneWidget);
    // Without `customers.view` the core sends only the hint; the card shows
    // what it was given and never anything more.
    expect(find.textContaining('•••• 4567'), findsOneWidget);
    expect(find.text('MEMBER'), findsOneWidget);
    expect(find.text('120 points'), findsOneWidget);
    expect(find.text('Home · 7 orders'), findsOneWidget);
    expect(find.text('Tower B · 12 · 3 · 12 Brazil St'), findsOneWidget);
    expect(find.text('Ring twice'), findsOneWidget);
    expect(find.text('Office Park'), findsOneWidget);
  });

  testWidgets('offline: the card stands, the addresses say why not', (
    tester,
  ) async {
    await _pump(tester, _Fake(), const CustomerCardSheet(customer: _mona));
    expect(find.text('Mona Adel'), findsOneWidget);
    expect(find.text('120 points'), findsOneWidget);
    expect(
      find.text('Saved addresses are not available offline'),
      findsOneWidget,
    );
  });

  testWidgets('no saved addresses says so', (tester) async {
    await _pump(
      tester,
      _Fake(addresses: const []),
      const CustomerCardSheet(customer: _mona),
    );
    expect(find.text('No saved addresses'), findsOneWidget);
  });

  testWidgets('without customers.addresses.view nothing is asked or shown', (
    tester,
  ) async {
    final bridge = _Fake(mayViewAddresses: false, addresses: const []);
    await _pump(tester, bridge, const CustomerCardSheet(customer: _mona));
    expect(bridge.asked, isEmpty);
    expect(find.text('SAVED ADDRESSES'), findsNothing);
    expect(find.text('No saved addresses'), findsNothing);
    expect(find.text('Mona Adel'), findsOneWidget);
  });

  testWidgets('a customer added on this till a moment ago is not asked for', (
    tester,
  ) async {
    final bridge = _Fake(addresses: const []);
    const fresh = CustomerView(
      id: 'c-new',
      name: 'Hana',
      pending: true,
      isMember: false,
    );
    await _pump(tester, bridge, const CustomerCardSheet(customer: fresh));
    expect(bridge.asked, isEmpty);
    expect(find.text('No phone'), findsOneWidget);
    expect(find.text('NOT SYNCED YET'), findsOneWidget);
  });

  group('the linked customer on an order', () {
    testWidgets('names the customer with the member badge', (tester) async {
      final bridge = _Fake(addresses: const [])..customers['c-mona'] = _mona;
      await _pump(
        tester,
        bridge,
        const LinkedCustomerRow(customerId: 'c-mona'),
      );
      expect(find.text('Mona Adel'), findsOneWidget);
      expect(find.text('MEMBER'), findsOneWidget);
    });

    testWidgets('an order placed for someone else says by whom, for whom', (
      tester,
    ) async {
      final bridge = _Fake(addresses: const [])..customers['c-mona'] = _mona;
      await _pump(
        tester,
        bridge,
        const LinkedCustomerRow(
          customerId: 'c-mona',
          orderedFor: 'Nour Hassan · 0122 333 4455',
        ),
      );
      expect(
        find.text('Ordered by Mona Adel for Nour Hassan · 0122 333 4455'),
        findsOneWidget,
      );
    });

    testWidgets('in Arabic too', (tester) async {
      final bridge = _Fake(addresses: const [], arabic: true)
        ..customers['c-mona'] = _mona;
      await _pump(
        tester,
        bridge,
        const LinkedCustomerRow(customerId: 'c-mona', orderedFor: 'نور'),
      );
      expect(find.text('طلبه Mona Adel لصالح نور'), findsOneWidget);
    });

    testWidgets('a customer this till does not hold renders nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        _Fake(addresses: const []),
        const LinkedCustomerRow(customerId: 'c-unknown'),
      );
      expect(find.byType(MadarCard), findsNothing);
    });
  });
}
