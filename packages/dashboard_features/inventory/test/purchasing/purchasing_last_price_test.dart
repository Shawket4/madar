// Purchase orders remember the last price: in New purchase order a line's
// total defaults to the last price paid for the ingredient (the chosen
// supplier's, else any supplier's) × the quantity, with a hint saying where
// it came from. A typed total is never overwritten; changing the supplier
// re-defaults only the untouched lines. (web `purchase-order-dialog.test.tsx`)
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder get _options => find.byType(DashOptionList<String>);

/// Opens the select keyed [key], optionally searches, and picks [label].
Future<void> _choose(
  DashHarness h,
  String key,
  String label, {
  String? search,
}) async {
  await h.tap(byKey(key));
  if (search != null) await h.enterText(_options, search);
  await h.tap(
    find
        .descendant(of: _options, matching: find.text(label))
        .hitTestable()
        .last,
  );
}

Future<void> _pickIngredient(DashHarness h, int i, String name) =>
    _choose(h, 'po-line-ingredient-$i', name, search: name);

/// New purchase order on Zamalek over [s].
Future<DashHarness> _openNewPo(
  WidgetTester tester,
  ({MockServer server, MockDb db}) s,
) async {
  final h = await pumpPurchasing(
    tester,
    path: purchasingAt(SeedIds.zamalek),
    server: s.server,
    db: s.db,
  );
  await h.tap(byKey('purchasing-new-order'));
  expect(poDialog, findsOneWidget);
  return h;
}

Finder _hint(int i) => inPo(byKey('po-line-last-price-$i'));

Finder _hintHas(int i, String s) => find.descendant(
  of: _hint(i),
  matching: find.textContaining(s, findRichText: true),
);

void main() {
  group('New purchase order: the last price is the default', () {
    testWidgets('the supplier\'s last price (its delivery\'s invoiced '
        'price) prefills the total, with a hint; not the catalog', (
      tester,
    ) async {
      final s = purchasingServer();
      // The catalog now says 3 piastres a ml; Delta Dairy's last delivery
      // was invoiced at 4.5 (r-1041-a).
      s.db[InvTables.ingredients].update(PurIds.ingredient('full-cream'), {
        'cost_per_unit': 3,
      });
      final h = await _openNewPo(tester, s);
      await _choose(h, 'po-supplier', 'Delta Dairy');
      await _pickIngredient(h, 0, 'Full Cream Milk');
      await h.enterText(byKey('po-line-qty-0'), '2000');
      expect(inputText(tester, 'po-line-total-0'), '90.00');

      final call = h.server
          .callsTo('/purchasing/orgs/{org_id}/last-prices')
          .last;
      expect(call.query['supplier_id'], [PurIds.supplier('delta-dairy')]);
      expect(_hint(0), findsOneWidget);
      expect(_hintHas(0, 'Last: EGP 0.045 / ml · '), findsOneWidget);
      expect(_hintHas(0, 'from another supplier'), findsNothing);

      // In litres: the same price, converted (4.5 × 1000 per L).
      await _choose(h, 'po-line-unit-0', 'L');
      await h.enterText(byKey('po-line-qty-0'), '12');
      expect(inputText(tester, 'po-line-total-0'), '540.00');
      expect(_hintHas(0, 'Last: EGP 45.00 / L'), findsOneWidget);
    });

    testWidgets('a supplier that never sold it: any supplier\'s last price, '
        'marked "from another supplier"; never bought: the catalog, no hint', (
      tester,
    ) async {
      final s = purchasingServer();
      s.db[InvTables.ingredients].update(PurIds.ingredient('full-cream'), {
        'cost_per_unit': 3,
      });
      final h = await _openNewPo(tester, s);
      await _choose(h, 'po-supplier', 'Nile Roasters');
      await _pickIngredient(h, 0, 'Full Cream Milk');
      await h.enterText(byKey('po-line-qty-0'), '2000');
      expect(inputText(tester, 'po-line-total-0'), '90.00');
      expect(_hintHas(0, 'from another supplier'), findsOneWidget);

      // Sugar was never on a purchase order: the catalog estimate, no hint.
      await h.tap(byKey('po-add-line'));
      await _pickIngredient(h, 1, 'Sugar');
      await h.enterText(byKey('po-line-qty-1'), '1000');
      final sugar = s.db[InvTables.ingredients].find(
        PurIds.ingredient('sugar'),
      )!;
      final cost = sugar['cost_per_unit'] as num?;
      expect(
        inputText(tester, 'po-line-total-1'),
        cost == null
            ? ''
            : ((cost * 1000 + 0.5).floor() / 100).toStringAsFixed(2),
      );
      expect(_hint(1), findsNothing);
    });

    testWidgets('a typed total is never overwritten; a new supplier '
        're-defaults only the untouched lines', (tester) async {
      final s = purchasingServer();
      // Metro Wholesale has house blend on order at 100.00 a kg; Nile
      // Roasters' last delivery was invoiced at 900.00 a kg (r-1037-a).
      final po = s.db[InvTables.purchaseOrders].insert({
        'org_id': SeedIds.sabahOrg,
        'branch_id': SeedIds.zamalek,
        'supplier_id': PurIds.supplier('metro'),
        'status': 'ordered',
        'created_by': SeedIds.user('karim'),
      });
      s.db[InvTables.poLines].insert({
        'purchase_order_id': po['id'],
        'org_ingredient_id': PurIds.ingredient('house-blend'),
        'purchase_unit': 'kg',
        'units_per_purchase_unit': 1000.0,
        'quantity_ordered': 1.0,
        'quantity_received': 0.0,
        'unit_cost': 10000,
        'unit_cost_exact': 10000.0,
        'line_cost': 10000,
      }, timestamps: false);

      final h = await _openNewPo(tester, s);
      await _choose(h, 'po-supplier', 'Nile Roasters');
      await _pickIngredient(h, 0, 'House Blend Beans');
      await h.enterText(byKey('po-line-qty-0'), '1000');
      // 90 piastres a gram × 1000 g.
      expect(inputText(tester, 'po-line-total-0'), '900.00');
      await h.tap(byKey('po-add-line'));
      await _pickIngredient(h, 1, 'House Blend Beans');
      await h.enterText(byKey('po-line-qty-1'), '1000');
      expect(inputText(tester, 'po-line-total-1'), '900.00');
      // Typed by hand on the second line.
      await h.enterText(byKey('po-line-total-1'), '850');

      await _choose(h, 'po-supplier', 'Metro Wholesale');
      await h.settle();
      // The untouched line follows Metro's price (10 piastres a gram).
      expect(inputText(tester, 'po-line-total-0'), '100.00');
      expect(_hintHas(0, 'Last: EGP 0.10 / g'), findsOneWidget);
      expect(_hintHas(0, 'from another supplier'), findsNothing);
      // The typed one keeps what was typed.
      expect(inputText(tester, 'po-line-total-1'), '850');

      // A new quantity re-defaults only the untouched line too.
      await h.enterText(byKey('po-line-qty-0'), '500');
      await h.enterText(byKey('po-line-qty-1'), '500');
      expect(inputText(tester, 'po-line-total-0'), '50.00');
      expect(inputText(tester, 'po-line-total-1'), '850');
    });
  });
}
