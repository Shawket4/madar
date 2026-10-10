// Purchasing's mock backend (`lib/src/mock/purchasing_mock.dart` and the
// shared reads it relies on) behaves like MadarRust's purchasing handlers:
// capabilities, branch scope, the backend's refusals in its words, and the
// figures a receipt writes (stock, weighted-average cost, the receipt),
// checked against hand-computed expectations. Plus the pure helpers the
// dialogs use (`purchasing_data.dart`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show allBranchesId;
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/purchasing/purchasing_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Matcher refused(int status, String words) => throwsA(
  isA<ApiException>()
      .having((e) => e.status, 'status', status)
      .having((e) => e.message, 'message', contains(words)),
);

({DashboardApi api, MockDb db}) backend([Persona p = Persona.owner]) {
  final s = purchasingServer(persona: p);
  return (api: DashboardApi(s.server), db: s.db);
}

final String org = SeedIds.sabahOrg;

MockRow stock(MockDb db, String branch, String ingredient) =>
    db[InvTables.branchStock].firstWhere(
      (r) =>
          r['branch_id'] == branch &&
          r['org_ingredient_id'] == PurIds.ingredient(ingredient),
    )!;

double dp6(num v) => (v * 1e6).roundToDouble() / 1e6;

void main() {
  group('suppliers', () {
    test('create trims the name, starts active, is listed by name; blank '
        'name and missing capability refused', () async {
      final b = backend();
      final made = await b.api.purchasing.createSupplier(
        orgId: org,
        body: const CreateSupplierRequest(name: '  Ras Sudr Fish '),
      );
      expect(made.name, 'Ras Sudr Fish');
      expect(made.isActive, isTrue);
      final names = [
        for (final s in await b.api.purchasing.listSuppliers(orgId: org))
          s.name,
      ];
      expect(names, [...names]..sort());
      expect(names, contains('Ras Sudr Fish'));
      await expectLater(
        b.api.purchasing.createSupplier(
          orgId: org,
          body: const CreateSupplierRequest(name: '   '),
        ),
        refused(400, 'name cannot be empty'),
      );
      await expectLater(
        backend(Persona.manager).api.purchasing.createSupplier(
          orgId: org,
          body: const CreateSupplierRequest(name: 'X'),
        ),
        refused(403, '(purchasing.suppliers.create)'),
      );
      await expectLater(
        backend(Persona.limited).api.purchasing.listSuppliers(orgId: org),
        refused(403, '(purchasing.suppliers.read)'),
      );
    });

    test('PATCH keeps a field sent as null (COALESCE); delete hides it but '
        'its orders keep the name', () async {
      final b = backend();
      final id = PurIds.supplier('golden-bakery');
      final s = await b.api.purchasing.updateSupplier(
        id: id,
        body: const UpdateSupplierRequest(
          name: 'Golden Bakery',
          contactName: null,
          isActive: false,
          explicitNulls: {'contact_name'},
        ),
      );
      expect(s.name, 'Golden Bakery');
      expect(s.contactName, 'Sherif Nabil');
      expect(s.isActive, isFalse);
      await b.api.purchasing.deleteSupplier(id: id);
      final left = await b.api.purchasing.listSuppliers(orgId: org);
      expect(left.map((x) => x.id), isNot(contains(id)));
      final orders = await b.api.purchasing.listPurchaseOrders(
        branchId: allBranchesId,
      );
      expect(
        orders.firstWhere((o) => o.reference == 'PO-1038').supplierName,
        'Golden Bakery',
      );
      await expectLater(
        b.api.purchasing.deleteSupplier(id: id),
        refused(404, 'Supplier not found'),
      );
      await expectLater(
        backend(
          Persona.manager,
        ).api.purchasing.deleteSupplier(id: PurIds.supplier('metro')),
        refused(403, '(purchasing.suppliers.delete)'),
      );
    });
  });

  group('orders: list, create, submit, cancel', () {
    test(
      'the all-branches id lists the org\'s orders, newest first, with '
      'branch names; status filters; a manager sees their branch only',
      () async {
        final b = backend();
        final all = await b.api.purchasing.listPurchaseOrders(
          branchId: allBranchesId,
        );
        expect(all, hasLength(9));
        final created = [for (final o in all) o.createdAt];
        expect(created, [...created]..sort((a, z) => z.compareTo(a)));
        expect(all.every((o) => o.branchName != null), isTrue);
        final open = await b.api.purchasing.listPurchaseOrders(
          branchId: allBranchesId,
          status: 'draft',
        );
        expect(open.single.reference, 'PO-1040');
        final mgr = await backend(
          Persona.manager,
        ).api.purchasing.listPurchaseOrders(branchId: allBranchesId);
        expect(mgr.map((o) => o.branchId).toSet(), {SeedIds.zamalek});
        await expectLater(
          backend(
            Persona.manager,
          ).api.purchasing.getPurchaseOrder(id: PurIds.po('po-1043')),
          refused(403, ''),
        );
      },
    );

    test('create: a draft with the server\'s unit factor and exact unit '
        'cost; listed next', () async {
      final b = backend();
      final po = await b.api.purchasing.createPurchaseOrder(
        branchId: SeedIds.zamalek,
        body: CreatePurchaseOrderRequest(
          supplierId: PurIds.supplier('delta-dairy'),
          reference: 'PO-2001',
          lines: [
            POLineInput(
              orgIngredientId: PurIds.ingredient('full-cream'),
              purchaseUnit: 'l',
              quantityOrdered: 12,
              lineCost: 54001,
            ),
          ],
        ),
      );
      expect(po.status, 'draft');
      expect(po.supplierName, 'Delta Dairy');
      final l = po.lines.single;
      expect(l.unitsPerPurchaseUnit, 1000);
      expect(l.lineCost, 54001);
      // 54,001 ÷ 12 = 4,500.083333… piastres a litre.
      expect(l.unitCostExact, 4500.083333);
      expect(l.unitCost, 4500);
      final listed = await b.api.purchasing.listPurchaseOrders(
        branchId: SeedIds.zamalek,
      );
      expect(listed.first.id, po.id);
    });

    test('create refusals in the backend\'s words', () async {
      final b = backend();
      Future<void> bad(List<POLineInput> lines, String words, {String? sup}) =>
          expectLater(
            b.api.purchasing.createPurchaseOrder(
              branchId: SeedIds.zamalek,
              body: CreatePurchaseOrderRequest(supplierId: sup, lines: lines),
            ),
            refused(400, words),
          );
      final milk = PurIds.ingredient('full-cream');
      await bad(const [], 'a purchase order needs at least one line');
      await bad([
        POLineInput(
          orgIngredientId: milk,
          purchaseUnit: 'ml',
          quantityOrdered: 0,
          lineCost: 1,
        ),
      ], 'quantity_ordered must be greater than 0');
      await bad([
        POLineInput(
          orgIngredientId: milk,
          purchaseUnit: 'ml',
          quantityOrdered: 1,
          lineCost: -1,
        ),
      ], 'line_cost cannot be negative');
      await bad([
        POLineInput(
          orgIngredientId: milk,
          purchaseUnit: 'kg',
          quantityOrdered: 1,
          lineCost: 1,
        ),
      ], "Purchase unit must match the ingredient's measure");
      await bad([
        POLineInput(
          orgIngredientId: mockUuid('nope'),
          purchaseUnit: 'ml',
          quantityOrdered: 1,
          lineCost: 1,
        ),
      ], 'Ingredient not found in this organization');
      await bad(
        [
          POLineInput(
            orgIngredientId: milk,
            purchaseUnit: 'ml',
            quantityOrdered: 1,
            lineCost: 1,
          ),
        ],
        'Supplier does not belong to this organization',
        sup: mockUuid('elsewhere'),
      );
      await expectLater(
        backend(Persona.limited).api.purchasing.createPurchaseOrder(
          branchId: SeedIds.maadi,
          body: const CreatePurchaseOrderRequest(lines: []),
        ),
        refused(403, '(purchasing.orders.create)'),
      );
    });

    test('submit draft → ordered, then 409; cancel ordered → cancelled; a '
        'partly received order cannot be cancelled', () async {
      final b = backend();
      final draft = PurIds.po('po-1040');
      final placed = await b.api.purchasing.submitPurchaseOrder(id: draft);
      expect(placed.status, 'ordered');
      await expectLater(
        b.api.purchasing.submitPurchaseOrder(id: draft),
        refused(409, 'Only a draft purchase order can be placed (submitted).'),
      );
      final cancelled = await b.api.purchasing.cancelPurchaseOrder(id: draft);
      expect(cancelled.status, 'cancelled');
      await expectLater(
        b.api.purchasing.cancelPurchaseOrder(id: PurIds.po('po-1041')),
        refused(409, 'Cannot cancel a purchase order that has already'),
      );
      await expectLater(
        backend(
          Persona.limited,
        ).api.purchasing.submitPurchaseOrder(id: PurIds.po('po-1041')),
        refused(403, '(purchasing.orders.edit)'),
      );
    });
  });

  group('receiving', () {
    test('a typed invoice total: stock up by the stock units, the '
        'weighted-average cost, a purchase_in movement, a receipt; the order '
        'partly received', () async {
      final b = backend();
      final po = PurIds.po('po-1042');
      final beans = PurIds.line('po-1042', 0);
      final before = stock(b.db, SeedIds.zamalek, 'house-blend');
      final prior = (before['on_hand']! as num).toDouble();
      final priorCost = (before['cost_per_unit']! as num).toDouble();
      final movements = b.db[InvTables.movements].length;

      final full = await b.api.purchasing.receivePurchaseOrder(
        id: po,
        body: ReceivePurchaseOrderRequest(
          lines: [
            ReceiveLineInput(
              lineId: beans,
              quantityReceived: 3,
              lineCost: 264050,
            ),
          ],
        ),
      );
      expect(full.status, 'partially_received');
      expect(full.lines.firstWhere((l) => l.id == beans).quantityReceived, 3);

      // 3 kg = 3,000 g at 264,050 piastres: 88.016667 a gram.
      const perGram = 88.016667;
      final after = stock(b.db, SeedIds.zamalek, 'house-blend');
      expect(after['on_hand'], prior + 3000);
      expect(
        after['cost_per_unit'],
        prior > 0
            ? dp6((prior * priorCost + 3000 * perGram) / (prior + 3000))
            : perGram,
      );
      expect(b.db[InvTables.movements].length, movements + 1);
      final mv = b.db[InvTables.movements].rows.last;
      expect(mv['movement_type'], 'purchase_in');
      expect(mv['quantity'], 3000);
      expect(mv['balance_after'], prior + 3000);
      expect(mv['source_id'], po);

      final receipts = await b.api.purchasing.listPoReceipts(id: po);
      final r = receipts.single;
      expect(r.isReturn, isFalse);
      final line = r.lines.single;
      expect(line.quantity, 3000);
      expect(line.lineCost, 264050);
      expect(line.unitCost, 88);
      expect(line.unitCostExact, perGram);
    });

    test('a blank total is the ordered total pro rata; the last line closes '
        'the order', () async {
      final b = backend();
      final po = PurIds.po('po-1041');
      final milk = PurIds.line('po-1041', 0);
      final r = await b.api.purchasing.receivePurchaseOrder(
        id: po,
        body: ReceivePurchaseOrderRequest(
          lines: [
            ReceiveLineInput(
              lineId: milk,
              quantityReceived: 24,
              explicitNulls: const {'line_cost', 'unit_cost'},
            ),
          ],
        ),
      );
      expect(r.status, 'received');
      final receipts = await b.api.purchasing.listPoReceipts(id: po);
      // Newest first; 270,000 × 24 ÷ 60 = 108,000 piastres for 24,000 ml.
      final latest = receipts.first;
      expect(latest.lines.single.lineCost, 108000);
      expect(latest.lines.single.quantity, 24000);
      expect(latest.lines.single.unitCostExact, 4.5);
      expect(receipts, hasLength(2));
    });

    test('refusals: over-receive, foreign line, duplicate line, empty, '
        'received order, capability', () async {
      final b = backend();
      final po = PurIds.po('po-1042');
      final beans = PurIds.line('po-1042', 0);
      Future<void> bad(List<ReceiveLineInput> lines, int status, String w) =>
          expectLater(
            b.api.purchasing.receivePurchaseOrder(
              id: po,
              body: ReceivePurchaseOrderRequest(lines: lines),
            ),
            refused(status, w),
          );
      await bad(
        [ReceiveLineInput(lineId: beans, quantityReceived: 6)],
        400,
        'Cannot receive 6 — only 5 of 5 ordered remain on this line.',
      );
      await bad(
        [
          ReceiveLineInput(
            lineId: PurIds.line('po-1041', 0),
            quantityReceived: 1,
          ),
        ],
        400,
        'Line does not belong to this purchase order',
      );
      await bad(
        [
          ReceiveLineInput(lineId: beans, quantityReceived: 1),
          ReceiveLineInput(lineId: beans, quantityReceived: 1),
        ],
        400,
        'Duplicate line_id in receive request',
      );
      await bad(const [], 400, 'no lines to receive');
      await expectLater(
        b.api.purchasing.receivePurchaseOrder(
          id: PurIds.po('po-1039'),
          body: ReceivePurchaseOrderRequest(
            lines: [
              ReceiveLineInput(
                lineId: PurIds.line('po-1039', 0),
                quantityReceived: 1,
              ),
            ],
          ),
        ),
        refused(409, 'Purchase order is already received or cancelled'),
      );
      // Nothing was written by the refusals.
      expect(await b.api.purchasing.listPoReceipts(id: po), isEmpty);
    });
  });

  group('reorder suggestions', () {
    test(
      'rows at or below par, up to par max (else par), grouped by '
      'supplier in supplier id order, no supplier last, by name inside',
      () async {
        final b = backend();
        final croissant = stock(b.db, SeedIds.zamalek, 'croissant');
        b.db[InvTables.branchStock].update(croissant['id']! as String, {
          'on_hand': 4.0,
          'par_min': 12.0,
          'par_max': 30.0,
        });
        b.db[InvTables.ingredients].update(PurIds.ingredient('croissant'), {
          'supplier_id': null,
        });
        final groups = await b.api.purchasing.reorderSuggestions(
          branchId: SeedIds.zamalek,
        );
        final expected = <String>[];
        for (final r in b.db[InvTables.branchStock].where(
          (r) => r['branch_id'] == SeedIds.zamalek,
        )) {
          final par = (r['par_min'] as num?)?.toDouble() ?? 0;
          if (par > 0 && (r['on_hand']! as num) <= par) {
            expected.add(r['org_ingredient_id']! as String);
          }
        }
        final got = [
          for (final g in groups)
            for (final l in g.lines) l.orgIngredientId,
        ];
        expect(got.toSet(), expected.toSet());
        expect(groups.last.supplierId, isNull);
        expect(groups.last.supplierName, isNull);
        final c = groups.last.lines.firstWhere(
          (l) => l.orgIngredientId == PurIds.ingredient('croissant'),
        );
        expect(c.onHand, 4);
        expect(c.suggestedQty, 26);
        final ids = [for (final g in groups) g.supplierId];
        expect(ids.toSet(), hasLength(ids.length), reason: 'one group each');
        for (final g in groups) {
          final names = [for (final l in g.lines) l.ingredientName];
          expect(names, [...names]..sort());
        }
        await expectLater(
          backend(
            Persona.manager,
          ).api.purchasing.reorderSuggestions(branchId: SeedIds.maadi),
          refused(403, ''),
        );
      },
    );
  });

  group('purchasing_data.dart', () {
    test('poReference: the reference, else # and the first 8 of the id', () {
      expect(poReference(id: 'abcdef1234', reference: 'PO-1'), 'PO-1');
      expect(poReference(id: 'abcdef1234', reference: ''), '#abcdef12');
      expect(poReference(id: 'abcdef1234'), '#abcdef12');
    });

    test('parseInputNumber reads Arabic digits; blank is NaN', () {
      expect(parseInputNumber('١٢٫٥'), 12.5);
      expect(parseInputNumber('2.5'), 2.5);
      expect(parseInputNumber('').isNaN, isTrue);
    });

    test('piastresToEgpFixed is toFixed(2)', () {
      expect(piastresToEgpFixed(108000), '1080.00');
      expect(piastresToEgpFixed(5), '0.05');
    });
  });
}
