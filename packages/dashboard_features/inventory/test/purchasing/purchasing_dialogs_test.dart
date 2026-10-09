// Purchasing's dialogs driven through the real shell: New purchase order
// (INV-PUR-027…042, -059, -063, -066, -067, -069…071), Receive order
// (INV-PUR-043…051, -065, -066, -068, -073) and the supplier dialog
// (INV-PUR-052…057).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/purchasing/purchasing_data.dart';
import 'package:dashboard_inventory/src/purchasing/purchasing_widgets.dart';
import 'package:dashboard_inventory/src/shared/inventory_lib.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final String _po1042 = PurIds.po('po-1042'); // Zamalek, ordered, 2 lines
final String _po1041 = PurIds.po('po-1041'); // Maadi, partially received
final String _po1040 = PurIds.po('po-1040'); // New Cairo, draft
final String _po1039 = PurIds.po('po-1039'); // Zamalek, received + a return
final String _po1038 = PurIds.po('po-1038'); // Heliopolis, cancelled

Finder get _options => find.byType(DashOptionList<String>);

/// Opens the select keyed [key], optionally searches, and picks [label].
Future<void> choose(
  DashHarness h,
  String key,
  String label, {
  String? search,
}) async {
  await h.tap(byKey(key));
  if (search != null) await h.enterText(_options, search);
  // `.last`: the search box holding the same words matches too.
  await h.tap(
    find
        .descendant(of: _options, matching: find.text(label))
        .hitTestable()
        .last,
  );
}

/// Opens New purchase order on Zamalek.
Future<DashHarness> openNewPo(
  WidgetTester tester, {
  MockServer? server,
  MockDb? db,
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
}) async {
  final h = await pumpPurchasing(
    tester,
    path: purchasingAt(SeedIds.zamalek),
    server: server,
    db: db,
    persona: persona,
    size: size,
  );
  await h.tap(byKey('purchasing-new-order'));
  expect(poDialog, findsOneWidget);
  return h;
}

/// Picks [name] on line [i] of the PO dialog.
Future<void> pickIngredient(DashHarness h, int i, String name) =>
    choose(h, 'po-line-ingredient-$i', name, search: name);

DashButton _placeOrder(WidgetTester tester) => button(tester, 'po-submit');

/// The locked unit cost of line [i].
String unitCostOf(WidgetTester tester, int i) =>
    tester.widget<DashAnimatedFigure>(byKey('po-line-unit-cost-$i')).text;

/// Opens the order [poId] from the orders table (All branches).
Future<DashHarness> openReceive(
  WidgetTester tester,
  String poId, {
  MockServer? server,
  MockDb? db,
  DashSize size = DashSize.desktop,
}) async {
  final h = await pumpPurchasing(tester, server: server, db: db, size: size);
  await orderMenu(h, poId, 'View order');
  expect(receiveDialog, findsOneWidget);
  return h;
}

Future<void> receiveTab(DashHarness h, String label) => h.tap(
  find.descendant(of: byKey('receive-tabs'), matching: find.text(label)),
);

/// Opens the supplier dialog: create, or edit [supplierKey].
Future<DashHarness> openSupplier(
  WidgetTester tester, {
  String? supplierKey,
  MockServer? server,
  MockDb? db,
  Persona persona = Persona.owner,
}) async {
  final h = await pumpPurchasing(
    tester,
    server: server,
    db: db,
    persona: persona,
  );
  await openTab(h, 'Suppliers');
  if (supplierKey == null) {
    await h.tap(byKey('purchasing-new-supplier'));
  } else {
    await supplierMenu(h, PurIds.supplier(supplierKey), 'Edit');
  }
  expect(supplierDialog, findsOneWidget);
  return h;
}

void main() {
  group('New purchase order (INV-PUR-028…042)', () {
    testWidgets('INV-PUR-028 / INV-PUR-069 opens empty: title, description, '
        'no supplier, no date, no reference, one empty line under "Lines", '
        'Total EGP 0.00, Place order off', (tester) async {
      await openNewPo(tester);
      expect(inPo(find.text('New purchase order')), findsOneWidget);
      expect(inPo(find.text('Purchase orders')), findsOneWidget);
      expect(inPo(find.text('Select a supplier')), findsOneWidget);
      expect(inPo(find.text('Expected')), findsNWidgets(2)); // label + hint
      expect(inputText(tester, 'po-reference'), '');
      expect(inPo(find.text('Reference')), findsOneWidget);
      expect(inPo(find.text('(Optional)')), findsOneWidget);
      expect(inPo(find.text('Lines')), findsOneWidget);
      expect(inPo(find.text('Pick an ingredient')), findsOneWidget);
      expect(byKey('po-line-ingredient-1'), findsNothing);
      expect(inPo(find.text('Purchase unit')), findsOneWidget);
      expect(inPo(find.text('Ordered')), findsOneWidget);
      expect(inPo(find.text('Line total (EGP)')), findsOneWidget);
      expect(inPo(find.text('Total')), findsOneWidget);
      expect(inPo(textHas('EGP 0.00')), findsOneWidget);
      expect(_placeOrder(tester).onPressed, isNull);
      expect(_placeOrder(tester).label, 'Place order');
    });

    testWidgets('INV-PUR-029 / INV-PUR-059 the supplier picker offers the '
        'ACTIVE suppliers only; the inactive one is on the Suppliers tab', (
      tester,
    ) async {
      final h = await openNewPo(tester);
      await h.tap(byKey('po-supplier'));
      final offered = tester.widget<DashOptionList<String>>(_options).options;
      expect([for (final o in offered) o.label], [
        'Delta Dairy',
        'Golden Bakery Supply',
        'Metro Wholesale',
        'Nile Roasters',
        'PackRight Egypt',
      ]);
      await h.tap(
        find.descendant(of: _options, matching: find.text('Delta Dairy')),
      );
      expect(inPo(find.text('Delta Dairy')), findsOneWidget);
      await h.tap(inPo(find.text('Cancel')));
      await openTab(h, 'Suppliers');
      expect(inSuppliers(find.text('Cairo Fresh Produce')), findsOneWidget);
    });

    testWidgets('INV-PUR-040 / INV-PUR-029 / INV-PUR-031 / INV-PUR-066 Place '
        'order sends only the valid lines, the supplier, the reference '
        'trimmed; a DRAFT is created, "New purchase order", closed, listed', (
      tester,
    ) async {
      final s = purchasingServer();
      final h = await openNewPo(tester, server: s.server, db: s.db);
      await choose(h, 'po-supplier', 'Delta Dairy');
      await h.enterText(byKey('po-reference'), '  PO-2001  ');
      await pickIngredient(h, 0, 'Full Cream Milk');
      await choose(h, 'po-line-unit-0', 'L');
      await h.enterText(byKey('po-line-qty-0'), '12');
      // A second line left half done: not sent.
      await h.tap(byKey('po-add-line'));
      await pickIngredient(h, 1, 'Skimmed Milk');
      expect(_placeOrder(tester).onPressed, isNotNull);
      await h.tap(byKey('po-submit'));

      final post = h.server.callsTo(PurT.orders, method: 'POST').single;
      expect(post.path, '/purchasing/branches/${SeedIds.zamalek}/orders');
      expect(post.status, 201);
      expect(post.body, {
        'supplier_id': PurIds.supplier('delta-dairy'),
        'expected_at': null,
        'reference': 'PO-2001',
        'lines': [
          {
            'org_ingredient_id': PurIds.ingredient('full-cream'),
            'purchase_unit': 'l',
            'quantity_ordered': 12,
            // 4.5 piastres a ml × 12 L.
            'line_cost': 54000,
            'units_per_purchase_unit': null,
          },
        ],
      });
      await h.expectToast('New purchase order');
      expect(poDialog, findsNothing);
      final created = s.db[InvTables.purchaseOrders].firstWhere(
        (po) => po['reference'] == 'PO-2001',
      )!;
      expect(created['status'], 'draft');
      expect(inOrders(find.text('PO-2001')), findsOneWidget);
      expect(
        inOrders(find.widgetWithText(DashStatusPill, 'Open')),
        findsOneWidget,
      );
    });

    testWidgets('INV-PUR-031 a blank reference and no supplier are sent as '
        'null', (tester) async {
      final h = await openNewPo(tester);
      await h.enterText(byKey('po-reference'), '   ');
      await pickIngredient(h, 0, 'Sugar');
      await h.enterText(byKey('po-line-qty-0'), '5000');
      await h.tap(byKey('po-submit'));
      final body = lastBody(h, PurT.orders, 'POST');
      expect(body['reference'], isNull);
      expect(body.containsKey('reference'), isTrue);
      expect(body['supplier_id'], isNull);
      expect(body.containsKey('supplier_id'), isTrue);
      await h.expectToast('New purchase order');
    });

    testWidgets('INV-PUR-030 / INV-PUR-070 Expected: the calendar with Today '
        'and "Click a day"; Today is sent as the end of the day in Cairo; '
        'no clear control', (tester) async {
      final h = await openNewPo(tester);
      await h.tap(byKey('po-expected'));
      expect(find.byType(DashCalendar), findsOneWidget);
      expect(find.text('Click a day').hitTestable(), findsOneWidget);
      await h.tap(find.text('Today').hitTestable());
      expect(find.byType(DashCalendar), findsNothing, reason: 'closed');
      expect(inPo(find.text('08 Oct 2026')), findsOneWidget);
      expect(inPo(find.text('This date is in the past')), findsNothing);
      // Re-opened: the footer shows the pick; there is no way to empty it.
      await h.tap(byKey('po-expected'));
      expect(find.text('Click a day').hitTestable(), findsNothing);
      expect(find.text('Clear').hitTestable(), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();

      await pickIngredient(h, 0, 'Sugar');
      await h.enterText(byKey('po-line-qty-0'), '5000');
      await h.tap(byKey('po-submit'));
      expect(
        lastBody(h, PurT.orders, 'POST')['expected_at'],
        '2026-10-08T20:59:59.999Z',
      );
      await h.expectToast('New purchase order');
    });

    testWidgets('INV-PUR-030 / INV-PUR-070 a past day is allowed with "This '
        'date is in the past"', (tester) async {
      final h = await openNewPo(tester);
      await h.tap(byKey('po-expected'));
      await h.tap(
        find
            .descendant(of: find.byType(DashCalendar), matching: find.text('5'))
            .hitTestable(),
      );
      expect(inPo(find.text('05 Oct 2026')), findsOneWidget);
      expect(inPo(find.text('This date is in the past')), findsOneWidget);
      await pickIngredient(h, 0, 'Sugar');
      await h.enterText(byKey('po-line-qty-0'), '1');
      await h.tap(byKey('po-submit'));
      expect(
        lastBody(h, PurT.orders, 'POST')['expected_at'],
        '2026-10-05T20:59:59.999Z',
      );
      await h.flushTimers();
    });

    testWidgets('INV-PUR-032 / INV-PUR-034 the ingredient picker searches '
        'the whole catalog; picking sets the stock unit; the unit select '
        'offers the same measure only', (tester) async {
      final s = purchasingServer();
      final h = await openNewPo(tester, server: s.server, db: s.db);
      // Disabled until an ingredient is picked.
      expect(
        tester.widget<DashSelect<String>>(byKey('po-line-unit-0')).enabled,
        isFalse,
      );
      await h.tap(byKey('po-line-ingredient-0'));
      final all = tester.widget<DashOptionList<String>>(_options).options;
      expect(
        all.length,
        s.db[InvTables.ingredients]
            .where((r) => r['org_id'] == SeedIds.sabahOrg)
            .length,
      );
      await h.enterText(_options, 'beans');
      expect(
        find.descendant(of: _options, matching: find.text('Decaf Beans')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _options, matching: find.text('Sugar')),
        findsNothing,
      );
      await h.tap(
        find.descendant(of: _options, matching: find.text('Decaf Beans')),
      );
      final unit = tester.widget<DashSelect<String>>(byKey('po-line-unit-0'));
      expect(unit.enabled, isTrue);
      expect(unit.value, 'g');
      expect([for (final o in unit.options) o.label], ['g', 'kg']);

      await pickIngredient(h, 0, 'Oat Milk');
      final ml = tester.widget<DashSelect<String>>(byKey('po-line-unit-0'));
      expect(ml.value, 'ml');
      expect([for (final o in ml.options) o.label], ['ml', 'L']);
      await pickIngredient(h, 0, 'Cup Lid');
      final pcs = tester.widget<DashSelect<String>>(byKey('po-line-unit-0'));
      expect([for (final o in pcs.options) o.value], ['pcs']);
    });

    testWidgets('INV-PUR-036 / INV-PUR-037 the total follows the catalog '
        'estimate; the unit cost is total ÷ quantity at six decimals, per '
        'the purchase unit', (tester) async {
      final h = await openNewPo(tester);
      expect(unitCostOf(tester, 0), '—');
      expect(inPo(find.text('Unit cost (EGP per unit)')), findsOneWidget);
      await pickIngredient(h, 0, 'Full Cream Milk');
      expect(inPo(find.text('Unit cost (EGP per ml)')), findsOneWidget);
      // No quantity yet: no estimate.
      expect(inputText(tester, 'po-line-total-0'), '');
      await h.enterText(byKey('po-line-qty-0'), '2000');
      expect(inputText(tester, 'po-line-total-0'), '90.00');
      expect(unitCostOf(tester, 0), '0.045000');
      await choose(h, 'po-line-unit-0', 'L');
      expect(inPo(find.text('Unit cost (EGP per L)')), findsOneWidget);
      // 2,000 L now: re-estimated.
      expect(inputText(tester, 'po-line-total-0'), '90000.00');
      await h.enterText(byKey('po-line-qty-0'), '12');
      expect(inputText(tester, 'po-line-total-0'), '540.00');
      expect(unitCostOf(tester, 0), '45.000000');
      expect(inPo(textHas('EGP 540.00')), findsOneWidget);
      // The tooltip explains the lock.
      expect(
        find.byTooltip(
          'Worked out from the line total ÷ the quantity. Change either to '
          'change it.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('INV-PUR-067 / INV-PUR-036 a typed total is never '
        'overwritten when the quantity or unit changes', (tester) async {
      final h = await openNewPo(tester);
      await pickIngredient(h, 0, 'Full Cream Milk');
      await h.enterText(byKey('po-line-qty-0'), '2000');
      await h.enterText(byKey('po-line-total-0'), '100');
      expect(unitCostOf(tester, 0), '0.050000');
      await h.enterText(byKey('po-line-qty-0'), '4000');
      expect(inputText(tester, 'po-line-total-0'), '100');
      expect(unitCostOf(tester, 0), '0.025000');
      await choose(h, 'po-line-unit-0', 'L');
      expect(inputText(tester, 'po-line-total-0'), '100');
      // A new ingredient keeps the typed total too, but resets the unit.
      await pickIngredient(h, 0, 'Skimmed Milk');
      expect(inputText(tester, 'po-line-total-0'), '100');
      expect(
        tester.widget<DashSelect<String>>(byKey('po-line-unit-0')).value,
        'ml',
      );
    });

    testWidgets('INV-PUR-071 an ingredient with no catalog cost: blank '
        'total, Place order off until a total is typed', (tester) async {
      final h = await openNewPo(tester);
      await pickIngredient(h, 0, 'Dried Hibiscus');
      await h.enterText(byKey('po-line-qty-0'), '500');
      expect(inputText(tester, 'po-line-total-0'), '');
      expect(unitCostOf(tester, 0), '—');
      expect(_placeOrder(tester).onPressed, isNull);
      await h.enterText(byKey('po-line-total-0'), '75');
      expect(unitCostOf(tester, 0), '0.150000');
      expect(_placeOrder(tester).onPressed, isNotNull);
    });

    testWidgets('INV-PUR-038 / INV-PUR-039 / INV-PUR-033 Add line, the Total '
        'of the readable lines, ✕ removes any line; none left → Place order '
        'off', (tester) async {
      final h = await openNewPo(tester);
      await pickIngredient(h, 0, 'Full Cream Milk');
      await h.enterText(byKey('po-line-qty-0'), '2000'); // 90.00
      await h.tap(byKey('po-add-line'));
      await pickIngredient(h, 1, 'Sugar');
      await h.enterText(byKey('po-line-qty-1'), '1000');
      final sugar = inputText(tester, 'po-line-total-1');
      final sugarP = (double.parse(sugar) * 100).round();
      final f = h.container.read(formatProvider);
      expect(inPo(textHas(f.fmtMoney(9000 + sugarP))), findsOneWidget);
      // A line with a total but no ingredient still counts in the Total;
      // a minus sign cannot be typed (see the divergence log).
      await h.tap(byKey('po-add-line'));
      await h.enterText(byKey('po-line-total-2'), '-5');
      expect(inputText(tester, 'po-line-total-2'), '5');
      expect(inPo(textHas(f.fmtMoney(9500 + sugarP))), findsOneWidget);
      expect(
        tester.widget<DashIconButton>(byKey('po-line-remove-0')).semanticLabel,
        'Remove',
      );
      for (var i = 0; i < 3; i++) {
        await h.tap(byKey('po-line-remove-0'));
      }
      expect(byKey('po-line-ingredient-0'), findsNothing);
      expect(_placeOrder(tester).onPressed, isNull);
      expect(inPo(textHas('EGP 0.00')), findsOneWidget);
      await h.tap(byKey('po-add-line'));
      expect(inPo(find.text('Pick an ingredient')), findsOneWidget);
    });

    testWidgets('INV-PUR-035 the ordered quantity takes numbers only; zero '
        'is not a valid line', (tester) async {
      final h = await openNewPo(tester);
      await pickIngredient(h, 0, 'Sugar');
      await h.enterText(byKey('po-line-qty-0'), '0');
      expect(_placeOrder(tester).onPressed, isNull);
      await h.enterText(byKey('po-line-qty-0'), '2.5');
      expect(inputText(tester, 'po-line-qty-0'), '2.5');
      expect(_placeOrder(tester).onPressed, isNotNull);
    });

    testWidgets('INV-PUR-041 Cancel and Esc close it without a request', (
      tester,
    ) async {
      final h = await openNewPo(tester);
      await h.tap(inPo(find.text('Cancel')));
      expect(poDialog, findsNothing);
      await h.tap(byKey('purchasing-new-order'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(poDialog, findsNothing);
      expect(h.server.callsTo(PurT.orders, method: 'POST'), isEmpty);
    });

    testWidgets('INV-PUR-042 / INV-ALL-011 a refused order: the server\'s '
        'words, the dialog kept with what was typed', (tester) async {
      final s = purchasingServer(persona: Persona.manager);
      final denied = MockResponse.denied('purchasing.orders.create');
      s.server.fail('POST', PurT.orders, denied);
      final h = await openNewPo(
        tester,
        server: s.server,
        db: s.db,
        persona: Persona.manager,
      );
      await pickIngredient(h, 0, 'Sugar');
      await h.enterText(byKey('po-line-qty-0'), '5000');
      await h.tap(byKey('po-submit'));
      await h.expectToast(h.refusalWords(denied));
      expect(poDialog, findsOneWidget);
      expect(inputText(tester, 'po-line-qty-0'), '5000');
      expect(_placeOrder(tester).loading, isFalse);
    });

    testWidgets('INV-PUR-042 the server\'s own refusal (a unit of another '
        'measure) reads as its words', (tester) async {
      final s = purchasingServer();
      final h = await openNewPo(tester, server: s.server, db: s.db);
      // The catalog changed under the dialog: Sugar is now counted in pcs.
      s.db[InvTables.ingredients].update(PurIds.ingredient('sugar'), {
        'unit': 'pcs',
      });
      await pickIngredient(h, 0, 'Sugar');
      await h.enterText(byKey('po-line-qty-0'), '5');
      await h.tap(byKey('po-submit'));
      expect(h.server.callsTo(PurT.orders, method: 'POST').single.status, 400);
      await h.expectToast(
        h.refusalWords(
          MockResponse.badRequest(
            "Purchase unit must match the ingredient's measure (g/kg for "
            'weight, ml/l for volume, pcs for count).',
          ),
        ),
      );
      expect(poDialog, findsOneWidget);
    });

    testWidgets('INV-PUR-040 the busy state while the order is sent', (
      tester,
    ) async {
      final s = purchasingServer();
      final gate = s.server.hold('POST', PurT.orders);
      final h = await openNewPo(tester, server: s.server, db: s.db);
      await pickIngredient(h, 0, 'Sugar');
      await h.enterText(byKey('po-line-qty-0'), '5000');
      await h.tap(byKey('po-submit'));
      expect(_placeOrder(tester).loading, isTrue);
      gate.release();
      await h.settle();
      await h.expectToast('New purchase order');
      expect(poDialog, findsNothing);
    });

    testWidgets('INV-PUR-040 / INV-ALL-010 a created order refreshes every '
        'inventory read on the page', (tester) async {
      final s = purchasingServer();
      final h = await openNewPo(tester, server: s.server, db: s.db);
      final before = {
        for (final r in [PurT.orders, PurT.suppliers, PurT.catalog])
          r: h.server.callsTo(r, method: 'GET').length,
      };
      await pickIngredient(h, 0, 'Sugar');
      await h.enterText(byKey('po-line-qty-0'), '5000');
      await h.tap(byKey('po-submit'));
      await h.expectToast('New purchase order');
      for (final e in before.entries) {
        expect(
          h.server.callsTo(e.key, method: 'GET').length,
          greaterThan(e.value),
          reason: e.key,
        );
      }
    });

    testWidgets('INV-PUR-061 on a phone the dialog is full screen and the '
        'line keeps its three fields in a row', (tester) async {
      final h = await openNewPo(tester, size: DashSize.phone);
      final screen = tester.getSize(find.byType(DashSurface).first);
      expect(screen.width, closeTo(DashSize.phone.size.width, 1));
      final unit = tester.getTopLeft(byKey('po-line-unit-0')).dy;
      expect(tester.getTopLeft(byKey('po-line-qty-0')).dy, unit);
      expect(tester.getTopLeft(byKey('po-line-total-0')).dy, unit);
      await pickIngredient(h, 0, 'Sugar');
      expect(inputText(tester, 'po-line-total-0'), '');
    });
  });

  group('Create draft PO from Reorder (INV-PUR-027, -063)', () {
    testWidgets('INV-PUR-027 the group\'s supplier and every line at the '
        'suggested quantity in the stock unit, totals estimated; closing '
        'clears the prefill', (tester) async {
      final s = purchasingServer();
      final h = await pumpPurchasing(
        tester,
        path: purchasingAt(SeedIds.zamalek),
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Reorder');
      final groups = h.container
          .read(reorderSuggestionsProvider(SeedIds.zamalek))
          .requireValue;
      final g = groups.firstWhere((g) => g.supplierId != null);
      final i = groups.indexOf(g);
      await h.tap(byKey('reorder-create-$i'));
      expect(poDialog, findsOneWidget);
      expect(inPo(find.text(g.supplierName!)), findsOneWidget);
      for (var n = 0; n < g.lines.length; n++) {
        final l = g.lines[n];
        expect(
          inPo(find.text(l.ingredientName)),
          findsOneWidget,
          reason: l.ingredientName,
        );
        expect(
          inputText(tester, 'po-line-qty-$n'),
          jsNumberString(l.suggestedQty),
        );
        expect(
          tester.widget<DashSelect<String>>(byKey('po-line-unit-$n')).value,
          l.unit,
        );
        final ing = s.db[InvTables.ingredients].find(l.orgIngredientId)!;
        final cost = ing['cost_per_unit'] as num?;
        expect(
          inputText(tester, 'po-line-total-$n'),
          cost == null
              ? ''
              : ((cost * l.suggestedQty + 0.5).floor() / 100).toStringAsFixed(
                  2,
                ),
        );
      }
      await h.tap(inPo(find.text('Cancel')));
      await openTab(h, 'Purchase orders');
      await h.tap(byKey('purchasing-new-order'));
      expect(inPo(find.text('Select a supplier')), findsOneWidget);
      expect(byKey('po-line-ingredient-1'), findsNothing);
    });

    testWidgets('INV-PUR-063 a prefilled line whose ingredient is not in the '
        'catalog has no unit; Place order falls back to pcs', (tester) async {
      final s = purchasingServer();
      // The catalog answers nothing (an ingredient the dialog cannot name).
      s.server.on('GET', PurT.catalog, (req) => MockResponse.ok(const []));
      final h = await pumpPurchasing(
        tester,
        path: purchasingAt(SeedIds.zamalek),
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Reorder');
      await h.tap(byKey('reorder-create-0'));
      final unit = tester.widget<DashSelect<String>>(byKey('po-line-unit-0'));
      expect(unit.value, isNull);
      expect(unit.enabled, isFalse);
      expect(inputText(tester, 'po-line-total-0'), '');
      expect(inPo(find.text('Pick an ingredient')), findsWidgets);
      await h.enterText(byKey('po-line-total-0'), '10');
      await h.tap(byKey('po-submit'));
      final line =
          (lastBody(h, PurT.orders, 'POST')['lines']! as List).first
              as Map<String, Object?>;
      expect(line['purchase_unit'], 'pcs');
      await h.flushTimers();
    });
  });

  group('Receive order (INV-PUR-043…051)', () {
    testWidgets('INV-PUR-043 / INV-PUR-044 title with the supplier, the '
        'hint, the tabs; the columns, the remaining prefilled', (tester) async {
      final h = await openReceive(tester, _po1041);
      expect(
        h.server.callsTo(PurT.order).single.path,
        '/purchasing/orders/$_po1041',
      );
      expect(inReceive(find.text('Receive order · Delta Dairy')), findsOneWidget);
      expect(
        inReceive(
          find.text('Receive what arrived — the order stays open for the rest.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: byKey('receive-tabs'), matching: find.text('Receive')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: byKey('receive-tabs'),
          matching: find.text('Delivery history'),
        ),
        findsOneWidget,
      );
      for (final head in [
        'NAME',
        'ORDERED',
        'ALREADY',
        'REMAINING',
        'RECEIVING',
        'INVOICE TOTAL (EGP)',
      ]) {
        expect(inReceive(find.text(head)), findsOneWidget, reason: head);
      }
      final full = PurIds.line('po-1041', 0);
      final cream = PurIds.line('po-1041', 1);
      expect(inReceive(find.text('Full Cream Milk')), findsOneWidget);
      expect(inReceive(textHas('60 l')), findsOneWidget);
      expect(inReceive(textHas('36')), findsWidgets);
      expect(inReceive(textHas('24')), findsWidgets);
      // 24 L left on the milk; nothing on the cream.
      expect(inputText(tester, 'receive-qty-$full'), '24');
      expect(inputText(tester, 'receive-qty-$cream'), '');
      // Pro rata of the ordered total for what is arriving.
      expect(inputHint(tester, 'receive-total-$full'), '1080.00');
      expect(inputHint(tester, 'receive-total-$cream'), '—');
    });

    testWidgets('INV-PUR-068 the placeholder follows the typed quantity', (
      tester,
    ) async {
      final h = await openReceive(tester, _po1041);
      final full = PurIds.line('po-1041', 0);
      await h.enterText(byKey('receive-qty-$full'), '10');
      // 270,000 × 10 ÷ 60 = 45,000 piastres.
      expect(inputHint(tester, 'receive-total-$full'), '450.00');
      await h.enterText(byKey('receive-qty-$full'), '');
      expect(inputHint(tester, 'receive-total-$full'), '—');
    });

    testWidgets('INV-PUR-045 a line with nothing left is locked; a received '
        'order locks every line and hides Receive', (tester) async {
      final h = await openReceive(tester, _po1041);
      final cream = PurIds.line('po-1041', 1);
      final full = PurIds.line('po-1041', 0);
      expect(
        tester.widget<PoNumberInput>(byKey('receive-qty-$cream'))
            .enabled,
        isFalse,
      );
      expect(
        tester.widget<PoNumberInput>(byKey('receive-total-$cream'))
            .enabled,
        isFalse,
      );
      expect(
        tester.widget<PoNumberInput>(byKey('receive-qty-$full'))
            .enabled,
        isTrue,
      );
      await h.tap(inReceive(find.text('Cancel')));
      await orderMenu(h, _po1039, 'View order');
      expect(byKey('receive-submit'), findsNothing);
      for (var n = 0; n < 2; n++) {
        final id = PurIds.line('po-1039', n);
        expect(
          tester.widget<PoNumberInput>(byKey('receive-qty-$id'))
              .enabled,
          isFalse,
        );
      }
      await h.tap(inReceive(find.text('Cancel')));
      await orderMenu(h, _po1038, 'View order');
      expect(byKey('receive-submit'), findsNothing);
    });

    testWidgets('INV-PUR-046 / INV-PUR-066 Receive sends the lines with a '
        'quantity, a typed total in piastres or null for pro rata; '
        '"Receive", closed, the stock moved', (tester) async {
      final s = purchasingServer();
      final h = await openReceive(tester, _po1042, server: s.server, db: s.db);
      final beans = PurIds.line('po-1042', 0);
      final eth = PurIds.line('po-1042', 1);
      await h.enterText(byKey('receive-qty-$beans'), '3');
      await h.enterText(byKey('receive-total-$beans'), '2640.50');
      await h.enterText(byKey('receive-qty-$eth'), '0');
      await h.tap(byKey('receive-submit'));
      final post = h.server.callsTo(PurT.receive).single;
      expect(post.path, '/purchasing/orders/$_po1042/receive');
      expect(post.body, {
        'lines': [
          {
            'line_id': beans,
            'quantity_received': 3,
            'line_cost': 264050,
            'unit_cost': null,
          },
        ],
      });
      await h.expectToast('Receive');
      expect(receiveDialog, findsNothing);
      expect(
        s.db[InvTables.purchaseOrders].find(_po1042)!['status'],
        'partially_received',
      );
      expect(
        tester
            .widget<DashButton>(inPage(byKey('po-receive-$_po1042')))
            .label,
        'Receive remaining',
      );
    });

    testWidgets('INV-PUR-046 a blank total is sent as null (pro rata)', (
      tester,
    ) async {
      final h = await openReceive(tester, _po1042);
      await h.tap(byKey('receive-submit'));
      final lines = lastBody(h, PurT.receive, 'POST')['lines']! as List;
      expect(lines, [
        {
          'line_id': PurIds.line('po-1042', 0),
          'quantity_received': 5,
          'line_cost': null,
          'unit_cost': null,
        },
        {
          'line_id': PurIds.line('po-1042', 1),
          'quantity_received': 1,
          'line_cost': null,
          'unit_cost': null,
        },
      ]);
      await h.expectToast('Receive');
    });

    testWidgets('INV-PUR-046 (divergence) with nothing to receive the '
        'button is off (the web\'s button silently does nothing)', (
      tester,
    ) async {
      final h = await openReceive(tester, _po1042);
      for (var n = 0; n < 2; n++) {
        await h.enterText(byKey('receive-qty-${PurIds.line('po-1042', n)}'), '');
      }
      expect(button(tester, 'receive-submit').onPressed, isNull);
      expect(h.server.callsTo(PurT.receive), isEmpty);
    });

    testWidgets('INV-PUR-065 a DRAFT can be received', (tester) async {
      final s = purchasingServer();
      final h = await openReceive(tester, _po1040, server: s.server, db: s.db);
      await h.tap(byKey('receive-submit'));
      expect(h.server.callsTo(PurT.receive).single.status, 200);
      await h.expectToast('Receive');
      expect(
        s.db[InvTables.purchaseOrders].find(_po1040)!['status'],
        'received',
      );
    });

    testWidgets('INV-PUR-047 receiving more than is left: the server\'s '
        'words, the dialog kept', (tester) async {
      final h = await openReceive(tester, _po1042);
      final beans = PurIds.line('po-1042', 0);
      await h.enterText(byKey('receive-qty-$beans'), '6');
      await h.tap(byKey('receive-submit'));
      expect(h.server.callsTo(PurT.receive).single.status, 400);
      await h.expectToast(
        h.refusalWords(
          MockResponse.badRequest(
            'Cannot receive 6 — only 5 of 5 ordered remain on this line.',
          ),
        ),
      );
      expect(receiveDialog, findsOneWidget);
      expect(inputText(tester, 'receive-qty-$beans'), '6');
    });

    testWidgets('INV-PUR-047 an order cancelled meanwhile: the conflict\'s '
        'words', (tester) async {
      final s = purchasingServer();
      final h = await openReceive(tester, _po1042, server: s.server, db: s.db);
      s.db[InvTables.purchaseOrders].update(_po1042, {'status': 'cancelled'});
      await h.tap(byKey('receive-submit'));
      await h.expectToast(
        h.refusalWords(
          MockResponse.conflict(
            'Purchase order is already received or cancelled',
          ),
        ),
      );
      expect(receiveDialog, findsOneWidget);
    });

    testWidgets('INV-PUR-046 the busy state while sending; a manager may '
        'receive at their branch', (tester) async {
      final s = purchasingServer(persona: Persona.manager);
      final gate = s.server.hold('POST', PurT.receive);
      final h = await pumpPurchasing(
        tester,
        persona: Persona.manager,
        server: s.server,
        db: s.db,
      );
      await h.tap(inPage(byKey('po-receive-$_po1042')));
      await h.tap(byKey('receive-submit'));
      expect(button(tester, 'receive-submit').loading, isTrue);
      gate.release();
      await h.settle();
      await h.expectToast('Receive');
    });

    testWidgets('INV-PUR-050 Cancel and Esc close it without a request', (
      tester,
    ) async {
      final h = await openReceive(tester, _po1042);
      await h.tap(inReceive(find.text('Cancel')));
      expect(receiveDialog, findsNothing);
      await orderMenu(h, _po1042, 'View order');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(receiveDialog, findsNothing);
      expect(h.server.callsTo(PurT.receive), isEmpty);
    });

    testWidgets('INV-PUR-051 (divergence) while the order loads the lines '
        'are skeletons and Receive is off; a failed read shows its words '
        'and Retry (the web stays blank)', (tester) async {
      final s = purchasingServer();
      final gate = s.server.hold('GET', PurT.order);
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      await orderMenu(h, _po1042, 'View order');
      expect(inReceive(find.byType(DashSkeleton)), findsWidgets);
      expect(button(tester, 'receive-submit').onPressed, isNull);
      gate.release();
      await h.settle();
      expect(inReceive(find.text('House Blend Beans')), findsOneWidget);
      await h.tap(inReceive(find.text('Cancel')));

      final boom = MockResponse.error(500, 'Orders are resting');
      s.server.fail('GET', PurT.order, boom, times: null);
      await orderMenu(h, _po1041, 'View order');
      expect(inReceive(find.text(h.refusalWords(boom))), findsOneWidget);
      s.server.clearFailures();
      await h.tap(inReceive(find.text('Retry')));
      expect(inReceive(find.text('Full Cream Milk')), findsOneWidget);
    });

    testWidgets('INV-PUR-073 the order changing while open re-initialises '
        'the dialog: Receiving back to the remaining, totals cleared, the '
        'Receive tab', (tester) async {
      final s = purchasingServer();
      final h = await pumpPurchasing(
        tester,
        path: purchasingAt(SeedIds.zamalek),
        server: s.server,
        db: s.db,
      );
      await orderMenu(h, _po1042, 'View order');
      final beans = PurIds.line('po-1042', 0);
      await h.enterText(byKey('receive-qty-$beans'), '2');
      await h.enterText(byKey('receive-total-$beans'), '999');
      // A refetch with the same answer keeps what was typed.
      h.realtime.current!.emit('resync');
      await h.settle();
      expect(inputText(tester, 'receive-qty-$beans'), '2');
      // Someone receives 1 kg elsewhere; the next refetch changes the order.
      s.db[InvTables.poLines].find(beans)!['quantity_received'] = 1.0;
      await receiveTab(h, 'Delivery history');
      h.realtime.current!.emit('resync');
      await h.settle();
      expect(inputText(tester, 'receive-qty-$beans'), '4');
      expect(inputText(tester, 'receive-total-$beans'), '');
      expect(
        find.descendant(of: byKey('receive-tabs'), matching: find.byType(Text)),
        findsWidgets,
      );
      expect(inReceive(find.text('RECEIVING')), findsOneWidget);
    });
  });

  group('Delivery history (INV-PUR-048, -049)', () {
    testWidgets('INV-PUR-048 / INV-PUR-049 read every time the tab opens; '
        'one card per receipt, newest first: when, Return, who, the lines', (
      tester,
    ) async {
      final s = purchasingServer();
      final h = await openReceive(tester, _po1039, server: s.server, db: s.db);
      expect(h.server.callsTo(PurT.receipts), isEmpty);
      await receiveTab(h, 'Delivery history');
      expect(
        h.server.callsTo(PurT.receipts).single.path,
        '/purchasing/orders/$_po1039/receipts',
      );
      final f = h.container.read(formatProvider);
      final ret = byKey('receipt-${InvIds.receipt('r-1039-b')}');
      final first = byKey('receipt-${InvIds.receipt('r-1039-a')}');
      expect(
        tester.getTopLeft(ret).dy,
        lessThan(tester.getTopLeft(first).dy),
        reason: 'newest first',
      );
      Finder inCard(Finder card, Finder f) =>
          find.descendant(of: card, matching: f);
      expect(
        inCard(ret, find.text(f.fmtDateTime('2026-10-03T07:30:00Z'))),
        findsOneWidget,
      );
      expect(
        inCard(ret, find.widgetWithText(DashStatusPill, 'Return')),
        findsOneWidget,
      );
      expect(
        inCard(first, find.widgetWithText(DashStatusPill, 'Return')),
        findsNothing,
      );
      expect(
        inCard(ret, find.text(InventorySeed.personName('karim'))),
        findsOneWidget,
      );
      // The return: −50 lids, −EGP 30.00, 0.600000 a lid.
      expect(inCard(ret, find.text('Cup Lid')), findsOneWidget);
      expect(
        inCard(
          ret,
          textHas(
            f.fmtNumber(
              -50,
              const NumberOptions(signDisplay: SignDisplay.exceptZero),
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(inCard(ret, textHas(f.fmtMoney(-3000))), findsOneWidget);
      expect(inCard(ret, textHas('0.600000')), findsOneWidget);
      // The delivery: +500 cups at EGP 900.00.
      expect(inCard(first, textHas('+500')), findsOneWidget);
      expect(inCard(first, textHas(f.fmtMoney(90000))), findsOneWidget);
      // No header row in a receipt's lines.
      expect(inCard(first, find.text('NAME')), findsNothing);

      await receiveTab(h, 'Receive');
      await receiveTab(h, 'Delivery history');
      expect(h.server.callsTo(PurT.receipts), hasLength(2));
    });

    testWidgets('INV-PUR-049 a receiver with no name shows the id; a line '
        'with no cost "—"', (tester) async {
      final s = purchasingServer();
      final r = s.db[InvTables.receipts].find(InvIds.receipt('r-1041-a'))!;
      r['received_by_name'] = null;
      ((r['lines']! as List).first as Map)['line_cost'] = null;
      ((r['lines']! as List).first as Map)['unit_cost_exact'] = null;
      final h = await openReceive(tester, _po1041, server: s.server, db: s.db);
      await receiveTab(h, 'Delivery history');
      final card = byKey('receipt-${InvIds.receipt('r-1041-a')}');
      Finder inCard(Finder f) => find.descendant(of: card, matching: f);
      expect(inCard(find.text(r['received_by']! as String)), findsOneWidget);
      expect(inCard(textHas('—')), findsNWidgets(2));
    });

    testWidgets('INV-PUR-048 loading: two skeleton cards; empty: "No '
        'deliveries recorded yet."', (tester) async {
      final s = purchasingServer();
      final gate = s.server.hold('GET', PurT.receipts);
      final h = await openReceive(tester, _po1042, server: s.server, db: s.db);
      await receiveTab(h, 'Delivery history');
      expect(inReceive(find.byType(DashSkeleton)), findsWidgets);
      gate.release();
      await h.settle();
      expect(inReceive(find.text('No deliveries recorded yet.')), findsOneWidget);
    });

    testWidgets('INV-PUR-048 (divergence) a failed read shows its words and '
        'Retry (the web shows it as empty)', (tester) async {
      final s = purchasingServer();
      final boom = MockResponse.error(500, 'Receipts are resting');
      s.server.fail('GET', PurT.receipts, boom, times: null);
      final h = await openReceive(tester, _po1039, server: s.server, db: s.db);
      await receiveTab(h, 'Delivery history');
      expect(inReceive(find.text(h.refusalWords(boom))), findsOneWidget);
      expect(inReceive(find.text('No deliveries recorded yet.')), findsNothing);
      s.server.clearFailures();
      await h.tap(inReceive(find.text('Retry')));
      expect(
        byKey('receipt-${InvIds.receipt('r-1039-a')}'),
        findsOneWidget,
      );
    });

    testWidgets('INV-PUR-049 phone: the receive lines and receipts as cards',
        (tester) async {
      final h = await openReceive(tester, _po1041, size: DashSize.phone);
      final full = PurIds.line('po-1041', 0);
      expect(byKey('receive-line-$full'), findsOneWidget);
      expect(
        find.descendant(
          of: byKey('receive-line-$full'),
          matching: find.text('Remaining'),
        ),
        findsOneWidget,
      );
      await receiveTab(h, 'Delivery history');
      expect(byKey('receipt-${InvIds.receipt('r-1041-a')}'), findsOneWidget);
    });
  });

  group('Supplier dialog (INV-PUR-052…057)', () {
    testWidgets('INV-PUR-052 / INV-PUR-053 New supplier: empty, the name '
        'focused, no Active switch, Save off while the name is blank', (
      tester,
    ) async {
      final h = await openSupplier(tester);
      expect(inSupplier(find.text('New supplier')), findsOneWidget);
      expect(inSupplier(find.text('Suppliers')), findsOneWidget);
      for (final k in [
        'supplier-name',
        'supplier-contact',
        'supplier-email',
        'supplier-phone',
      ]) {
        expect(inputText(tester, k), '', reason: k);
      }
      expect(byKey('supplier-active'), findsNothing);
      final name = tester.widget<EditableText>(
        find.descendant(
          of: byKey('supplier-name'),
          matching: find.byType(EditableText),
        ),
      );
      expect(name.focusNode.hasFocus, isTrue);
      expect(button(tester, 'supplier-save').onPressed, isNull);
      await h.enterText(byKey('supplier-name'), '   ');
      expect(button(tester, 'supplier-save').onPressed, isNull);
      await h.enterText(byKey('supplier-name'), 'Ras Sudr Fish');
      expect(button(tester, 'supplier-save').onPressed, isNotNull);
    });

    testWidgets('INV-PUR-054 / INV-PUR-056 create: the fields trimmed or '
        'null, "Changes saved", closed, listed Active', (tester) async {
      final s = purchasingServer();
      final h = await openSupplier(tester, server: s.server, db: s.db);
      await h.enterText(byKey('supplier-name'), '  Nile Paper Co  ');
      await h.enterText(byKey('supplier-contact'), ' Samir Lotfy ');
      await h.enterText(byKey('supplier-email'), 'not-an-email');
      await h.enterText(byKey('supplier-phone'), '   ');
      final email = tester.widget<TextField>(
        find.descendant(
          of: byKey('supplier-email'),
          matching: find.byType(TextField),
        ),
      );
      expect(email.keyboardType, TextInputType.emailAddress);
      await h.tap(byKey('supplier-save'));
      final post = h.server.callsTo(PurT.suppliers, method: 'POST').single;
      expect(post.path, '/purchasing/orgs/${SeedIds.sabahOrg}/suppliers');
      expect(post.body, {
        'name': 'Nile Paper Co',
        'contact_name': 'Samir Lotfy',
        'email': 'not-an-email',
        'phone': null,
      });
      await h.expectToast('Changes saved');
      expect(supplierDialog, findsNothing);
      expect(inSuppliers(find.text('Nile Paper Co')), findsOneWidget);
      expect(
        s.db[InvTables.suppliers].firstWhere(
          (r) => r['name'] == 'Nile Paper Co',
        )!['is_active'],
        isTrue,
      );
    });

    testWidgets('INV-PUR-052 / INV-PUR-055 / INV-PUR-056 edit: prefilled, '
        'the Active switch; PATCH with is_active; the list re-read', (
      tester,
    ) async {
      final s = purchasingServer();
      final h = await openSupplier(
        tester,
        supplierKey: 'metro',
        server: s.server,
        db: s.db,
      );
      expect(inSupplier(find.text('Edit supplier')), findsOneWidget);
      expect(inputText(tester, 'supplier-name'), 'Metro Wholesale');
      expect(inputText(tester, 'supplier-contact'), 'Laila Farouk');
      expect(inputText(tester, 'supplier-email'), 'b2b@metro.example');
      expect(inputText(tester, 'supplier-phone'), '+20 100 444 5566');
      expect(inSupplier(find.text('Active')), findsOneWidget);
      expect(
        tester.widget<DashSwitchField>(byKey('supplier-active')).value,
        isTrue,
      );
      await h.tap(
        find.descendant(
          of: byKey('supplier-active'),
          matching: find.byType(DashSwitch),
        ),
      );
      await h.enterText(byKey('supplier-contact'), '');
      final reads = h.server.callsTo(PurT.suppliers, method: 'GET').length;
      await h.tap(byKey('supplier-save'));
      final patch = h.server.callsTo(PurT.supplier, method: 'PATCH').single;
      expect(patch.path, '/purchasing/suppliers/${PurIds.supplier('metro')}');
      expect(patch.body, {
        'name': 'Metro Wholesale',
        'contact_name': null,
        'email': 'b2b@metro.example',
        'phone': '+20 100 444 5566',
        'is_active': false,
      });
      await h.expectToast('Changes saved');
      expect(
        h.server.callsTo(PurT.suppliers, method: 'GET').length,
        greaterThan(reads),
      );
      final row = find.ancestor(
        of: exactText(suppliersTable, 'Metro Wholesale'),
        matching: find.byWidgetPredicate((w) => w is Row),
      );
      expect(row, findsWidgets);
      expect(
        s.db[InvTables.suppliers].find(PurIds.supplier('metro'))!['is_active'],
        isFalse,
      );
      // The server keeps a contact it is sent null for (COALESCE).
      expect(inSuppliers(find.text('Laila Farouk')), findsOneWidget);
    });

    testWidgets('INV-PUR-056 a refused save: the server\'s words, the '
        'dialog kept', (tester) async {
      final s = purchasingServer(persona: Persona.manager);
      final h = await openSupplier(
        tester,
        server: s.server,
        db: s.db,
        persona: Persona.manager,
      );
      await h.enterText(byKey('supplier-name'), 'Ras Sudr Fish');
      await h.tap(byKey('supplier-save'));
      expect(
        h.server.callsTo(PurT.suppliers, method: 'POST').single.status,
        403,
      );
      await h.expectToast(
        h.refusalWords(MockResponse.denied('purchasing.suppliers.create')),
      );
      expect(supplierDialog, findsOneWidget);
      expect(inputText(tester, 'supplier-name'), 'Ras Sudr Fish');
    });

    testWidgets('INV-PUR-056 the server\'s "name cannot be empty" reads as '
        'its words', (tester) async {
      final s = purchasingServer();
      final bad = MockResponse.badRequest('name cannot be empty');
      s.server.fail('POST', PurT.suppliers, bad);
      final h = await openSupplier(tester, server: s.server, db: s.db);
      await h.enterText(byKey('supplier-name'), 'X');
      await h.tap(byKey('supplier-save'));
      await h.expectToast(h.refusalWords(bad));
      expect(supplierDialog, findsOneWidget);
    });

    testWidgets('INV-PUR-057 Cancel and Esc close it without a request', (
      tester,
    ) async {
      final h = await openSupplier(tester, supplierKey: 'metro');
      await h.tap(inSupplier(find.text('Cancel')));
      expect(supplierDialog, findsNothing);
      await h.tap(byKey('purchasing-new-supplier'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(supplierDialog, findsNothing);
      expect(h.server.callsTo(PurT.suppliers, method: 'POST'), isEmpty);
      expect(h.server.callsTo(PurT.supplier, method: 'PATCH'), isEmpty);
    });

    testWidgets('INV-PUR-052 an edit form follows a background refresh of '
        'its row until the person types', (tester) async {
      final s = purchasingServer();
      final h = await openSupplier(
        tester,
        supplierKey: 'metro',
        server: s.server,
        db: s.db,
      );
      s.db[InvTables.suppliers].update(PurIds.supplier('metro'), {
        'phone': '+20 100 999 0000',
      });
      h.realtime.current?.emit('resync');
      h.container.read(realtimeBusProvider).invalidate(const ['/purchasing']);
      await h.settle();
      expect(inputText(tester, 'supplier-phone'), '+20 100 999 0000');
      await h.enterText(byKey('supplier-contact'), 'Laila F.');
      s.db[InvTables.suppliers].update(PurIds.supplier('metro'), {
        'phone': '+20 100 111 1111',
      });
      h.container.read(realtimeBusProvider).invalidate(const ['/purchasing']);
      await h.settle();
      expect(inputText(tester, 'supplier-phone'), '+20 100 999 0000');
      expect(inputText(tester, 'supplier-contact'), 'Laila F.');
    });
  });
}
