// The waste unit's mock backend (`lib/src/mock/waste_mock.dart`) against the
// backend's handlers (MadarRust `inventory/handlers.rs` create_waste,
// `reports/handlers.rs` branch_waste_report) and hand-worked figures from
// the area seed; and the page's pure sums (`waste_data.dart`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/mock/waste_mock.dart' show wasteReport;
import 'package:dashboard_inventory/src/waste/waste_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Matcher _refused(int status) =>
    throwsA(isA<ApiException>().having((e) => e.status, 'status', status));

Matcher _says(String words) =>
    throwsA(isA<ApiException>().having((e) => e.message, 'message', words));

CreateWasteRequest _body(
  String ingredient,
  double qty, {
  String reason = 'expired',
  String? note,
}) => CreateWasteRequest(
  orgIngredientId: InvIds.ingredient(ingredient),
  quantity: qty,
  reason: reason,
  note: note,
);

void main() {
  group('POST /inventory/branches/{branch_id}/waste', () {
    test('records a waste movement and lowers the stock', () async {
      final s = wasteServer();
      final api = DashboardApi(s.server);
      final m = await api.inventory.createWaste(
        branchId: SeedIds.zamalek,
        body: _body('matcha', 15, reason: 'spoiled', note: 'Tin dropped'),
      );
      expect(m.movementType, 'waste');
      expect(m.quantity, -15);
      expect(m.balanceAfter, 65);
      expect(m.reason, 'spoiled');
      expect(m.note, 'Tin dropped');
      expect(m.unitCost, 250);
      expect(m.createdByName, 'Nour El-Sayed');
      expect(m.wasteSource, 'dashboard');
      expect(stockRow(s.db, SeedIds.zamalek, 'matcha')!['on_hand'], 65);
      final log = await api.inventory.listWaste(branchId: SeedIds.zamalek);
      expect(log.first.id, m.id, reason: 'latest first');
      // The seed's eight, Soy Milk's last (archived) line, and this one.
      expect(log.length, 10);
    });

    test('a blank note is stored as null', () async {
      final s = wasteServer();
      final m = await DashboardApi(s.server).inventory.createWaste(
        branchId: SeedIds.zamalek,
        body: _body('matcha', 1, note: '   '),
      );
      expect(m.note, isNull);
    });

    test('refusals, in the backend\'s order', () async {
      final s = wasteServer();
      final api = DashboardApi(s.server).inventory;
      // No such branch.
      await expectLater(
        api.createWaste(
          branchId: mockUuid('nowhere'),
          body: _body('matcha', 1),
        ),
        _refused(404),
      );
      // A reason a person may not type.
      await expectLater(
        api.createWaste(
          branchId: SeedIds.zamalek,
          body: _body('matcha', 1, reason: 'refund'),
        ),
        _refused(400),
      );
      // Zero or less.
      await expectLater(
        api.createWaste(branchId: SeedIds.zamalek, body: _body('matcha', 0)),
        _refused(400),
      );
      // Not in the org's catalog.
      await expectLater(
        api.createWaste(
          branchId: SeedIds.zamalek,
          body: CreateWasteRequest(
            orgIngredientId: mockUuid('ingredient:none'),
            quantity: 1,
            reason: 'expired',
          ),
        ),
        _refused(400),
      );
      // More than on hand (Matcha: 80 g); nothing at all (Croissant: 0); a
      // branch that never stocked it (Heliopolis).
      await expectLater(
        api.createWaste(branchId: SeedIds.zamalek, body: _body('matcha', 81)),
        _says(
          MockServer.toApiException(
            MockResponse.badRequest(
              'Only 80.000 on hand — cannot waste 81.000.',
            ),
          ).message,
        ),
      );
      await expectLater(
        api.createWaste(branchId: SeedIds.zamalek, body: _body('croissant', 1)),
        _refused(400),
      );
      await expectLater(
        api.createWaste(branchId: SeedIds.heliopolis, body: _body('matcha', 1)),
        _refused(400),
      );
      expect(stockRow(s.db, SeedIds.zamalek, 'matcha')!['on_hand'], 80);
    });

    test('inventory.waste.record and the branch are checked', () async {
      final limited = wasteServer(persona: Persona.limited);
      await expectLater(
        DashboardApi(
          limited.server,
        ).inventory.createWaste(branchId: SeedIds.maadi, body: _body('oat', 1)),
        _refused(403),
      );
      final manager = wasteServer(persona: Persona.manager);
      await expectLater(
        DashboardApi(
          manager.server,
        ).inventory.createWaste(branchId: SeedIds.maadi, body: _body('oat', 1)),
        _refused(403),
      );
    });
  });

  group('GET /reports/branches/{branch_id}/waste-report', () {
    test('per reason and ingredient, valued at the exact cost', () async {
      final s = wasteServer();
      final rows = await DashboardApi(
        s.server,
      ).reports.branchWasteReport(branchId: SeedIds.zamalek);
      Map<String, Object?> row(String reason, String ing) {
        final r = rows.firstWhere(
          (r) =>
              r.reason == reason && r.orgIngredientId == InvIds.ingredient(ing),
        );
        return {'qty': r.wasteQty, 'value': r.wasteValue};
      }

      expect(row('expired', 'full-cream'), {'qty': 500, 'value': 2250});
      expect(row('spoiled', 'full-cream'), {'qty': 440, 'value': 1980});
      expect(row('spoiled', 'house-blend'), {'qty': 36, 'value': 3326});
      expect(row('damaged', 'croissant'), {'qty': 4, 'value': 3600});
      // An archived ingredient's past waste still counts: Soy Milk's last
      // 1,000 ml at 11 piastres/ml.
      expect(row('expired', 'soy'), {'qty': 1000, 'value': 11000});
      expect(rows.length, 9);
      // Largest quantity first.
      expect(rows.first.wasteQty, 1000);
      expect(wasteTotal(rows), 32656 + 11000);
    });

    test('the period cuts by when the server got it', () async {
      final s = wasteServer();
      final rows = await DashboardApi(s.server).reports.branchWasteReport(
        branchId: SeedIds.zamalek,
        from: DateTime.utc(2026, 10, 7, 21),
        to: DateTime.utc(2026, 10, 8, 20, 59, 59, 999),
      );
      expect(wasteTotal(rows), 2250 + 1980 + 3326 + 3600);
      // The offline till's Whipped Cream happened on the 6th, arrived the 7th.
      final seventh = await DashboardApi(s.server).reports.branchWasteReport(
        branchId: SeedIds.zamalek,
        from: DateTime.utc(2026, 10, 6, 21),
        to: DateTime.utc(2026, 10, 7, 20, 59, 59, 999),
      );
      expect([for (final r in seventh) r.ingredientName], ['Whipped Cream']);
    });

    test('all branches rolls up the org; inventory.read is needed', () async {
      final s = wasteServer();
      final rows = await DashboardApi(
        s.server,
      ).reports.branchWasteReport(branchId: allBranches);
      final reasons = {for (final r in rows) r.reason};
      expect(reasons, containsAll(['refund', 'order_cancelled']));
      final limited = wasteServer(persona: Persona.limited);
      await expectLater(
        DashboardApi(
          limited.server,
        ).reports.branchWasteReport(branchId: SeedIds.maadi),
        _refused(403),
      );
    });

    test('an unknown cost makes the line unknown', () {
      final s = wasteServer();
      for (final m in s.db[InvTables.movements].rows) {
        if (m['org_ingredient_id'] == InvIds.ingredient('cocoa')) {
          m
            ..['unit_cost'] = null
            ..['unit_cost_exact'] = null;
        }
      }
      final rows = wasteReport(s.db, [SeedIds.zamalek]);
      final cocoa = rows.firstWhere((r) => r['reason'] == 'other');
      expect(cocoa['waste_value'], isNull);
    });
  });

  group('waste_data', () {
    WasteReportRow r(String reason, int? value) => WasteReportRow(
      ingredientName: 'x',
      orgIngredientId: 'x',
      reason: reason,
      unit: 'g',
      wasteQty: 1,
      wasteValue: value,
    );

    test('wasteByReason sums per reason, largest first, ties in order', () {
      final out = wasteByReason([
        r('expired', 100),
        r('theft', 300),
        r('expired', 200),
        r('other', null),
        r('spoiled', 300),
      ]);
      expect(
        [for (final o in out) (o.reason, o.value, o.hasValue)],
        [
          ('expired', 300, true),
          ('theft', 300, true),
          ('spoiled', 300, true),
          ('other', 0, false),
        ],
      );
      expect(wasteTotal([r('a', 5), r('b', null), r('c', 7)]), 12);
    });
  });
}
