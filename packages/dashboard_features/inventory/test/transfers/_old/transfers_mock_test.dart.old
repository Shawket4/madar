// The transfers unit's mock backend (`lib/src/mock/transfers_mock.dart`)
// against the backend's handlers (MadarRust `inventory/handlers.rs`
// create_transfer, list_transfers, update_transfer, delete_transfer) and
// hand-worked figures from the area seed:
//
//   t1 Maadi → Zamalek     Oat Milk          2,000 ml  06 Oct
//   t2 New Cairo → Maadi   House Blend Beans 1,000 g   03 Oct
//   t3 Zamalek → New Cairo Paper Cup 12oz      100     30 Sep
//   t4 New Cairo → Zamalek Vanilla Syrup       750 ml  24 Sep
//   t5 Maadi → New Cairo   Croissant Dough      12     19 Sep
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Matcher _refused(int status) =>
    throwsA(isA<ApiException>().having((e) => e.status, 'status', status));

Matcher _says(String words) => throwsA(
  isA<ApiException>().having((e) => e.message, 'message', contains(words)),
);

CreateTransferRequest _body(
  String from,
  String to,
  String ingredient,
  double qty, {
  String? note,
}) => CreateTransferRequest(
  sourceBranchId: from,
  destinationBranchId: to,
  orgIngredientId: InvIds.ingredient(ingredient),
  quantity: qty,
  note: note,
);

InventoryApi _api({Persona persona = Persona.owner}) {
  final s = transfersServer(persona: persona);
  return DashboardApi(s.server).inventory;
}

List<String> _keys(List<StockTransfer> rows) => [
  for (final r in rows)
    for (final k in ['t1', 't2', 't3', 't4', 't5'])
      if (r.id == InvIds.transfer(k)) k,
];

void main() {
  group('GET /inventory/branches/{branch_id}/transfers', () {
    test('a branch: in and out, latest first; direction filters', () async {
      final api = _api();
      Future<List<String>> list([String? d]) async => _keys(
        await api.listTransfers(branchId: SeedIds.zamalek, direction: d),
      );
      expect(await list(), ['t1', 't3', 't4']);
      expect(await list('incoming'), ['t1', 't4']);
      expect(await list('outgoing'), ['t3']);
    });

    test(
      'the all-branches id rolls the org up; limit/offset page it',
      () async {
        final api = _api();
        expect(_keys(await api.listTransfers(branchId: allBranches)), [
          't1',
          't2',
          't3',
          't4',
          't5',
        ]);
        expect(
          _keys(
            await api.listTransfers(branchId: allBranches, limit: 2, offset: 1),
          ),
          ['t2', 't3'],
        );
        expect(
          await api.listTransfers(branchId: allBranches, offset: 5),
          isEmpty,
        );
      },
    );

    test('a row carries both branch names and who sent it', () async {
      final rows = await _api().listTransfers(branchId: SeedIds.maadi);
      final t1 = rows.first;
      expect(t1.sourceBranchName, 'Maadi');
      expect(t1.destinationBranchName, 'Zamalek');
      expect(t1.ingredientName, 'Oat Milk');
      expect(t1.quantity, 2000);
      expect(t1.unit, 'ml');
      expect(t1.initiatedByName, 'Tarek Saber');
      expect(t1.note, 'Zamalek ran short over the weekend');
    });

    test('refusals: no cap 403, another branch 403, unknown 404', () async {
      expect(
        _api(persona: Persona.limited).listTransfers(branchId: SeedIds.zamalek),
        _refused(403),
      );
      final manager = _api(persona: Persona.manager);
      expect(manager.listTransfers(branchId: SeedIds.maadi), _refused(403));
      expect(manager.listTransfers(branchId: 'nowhere'), _refused(404));
    });
  });

  group('POST /inventory/transfers', () {
    test(
      'moves the stock, writes both movements, lists the transfer',
      () async {
        final s = transfersServer();
        final api = DashboardApi(s.server).inventory;
        final maadiBefore =
            (stockRow(s.db, SeedIds.maadi, 'vanilla-syrup')?['on_hand'] as num?)
                ?.toDouble() ??
            0;
        final tr = await api.createTransfer(
          body: _body(
            SeedIds.zamalek,
            SeedIds.maadi,
            'vanilla-syrup',
            200,
            note: 'For the weekend',
          ),
        );
        expect(tr.sourceBranchName, 'Zamalek');
        expect(tr.destinationBranchName, 'Maadi');
        expect(tr.initiatedByName, 'Nour El-Sayed');
        expect(tr.note, 'For the weekend');
        expect(
          stockRow(s.db, SeedIds.zamalek, 'vanilla-syrup')!['on_hand'],
          400,
        );
        expect(
          stockRow(s.db, SeedIds.maadi, 'vanilla-syrup')!['on_hand'],
          maadiBefore + 200,
        );
        final moves = s.db[InvTables.movements].where(
          (m) => m['source_id'] == tr.id,
        );
        expect(
          [
            for (final m in moves)
              (m['movement_type'], m['quantity'], m['note']),
          ],
          [
            ('transfer_out', -200.0, 'Transfer out'),
            ('transfer_in', 200.0, 'Transfer in'),
          ],
        );
        final rows = await api.listTransfers(branchId: SeedIds.zamalek);
        expect(rows.first.id, tr.id);
      },
    );

    test(
      'the cost travels with the goods (destination average blended)',
      () async {
        final s = transfersServer();
        final api = DashboardApi(s.server).inventory;
        // Zamalek's house blend costs 92.4 a gram; Maadi's is the catalog's 90.
        final maadi = stockRow(s.db, SeedIds.maadi, 'house-blend')!;
        final prior = (maadi['on_hand']! as num).toDouble();
        final priorCost = (maadi['cost_per_unit']! as num).toDouble();
        await api.createTransfer(
          body: _body(SeedIds.zamalek, SeedIds.maadi, 'house-blend', 500),
        );
        expect(
          maadi['cost_per_unit'],
          closeTo((prior * priorCost + 500 * 92.4) / (prior + 500), 1e-9),
        );
      },
    );

    test('refusals in the backend\'s order and words', () async {
      final api = _api();
      expect(
        api.createTransfer(
          body: _body(SeedIds.zamalek, SeedIds.maadi, 'vanilla-syrup', 0),
        ),
        _says('quantity must be greater than 0'),
      );
      expect(
        api.createTransfer(
          body: _body(SeedIds.zamalek, SeedIds.zamalek, 'vanilla-syrup', 5),
        ),
        _says('Source and destination branches must be different'),
      );
      expect(
        api.createTransfer(
          body: _body(SeedIds.zamalek, SeedIds.maadi, 'vanilla-syrup', 601),
        ),
        _says(
          'Only 600.000 on hand at the source branch — cannot transfer '
          '601.000.',
        ),
      );
      expect(
        api.createTransfer(
          body: _body(SeedIds.zamalek, SeedIds.maadi, 'oat', 1),
        ),
        _says('Only -350.000 on hand'),
      );
      expect(
        api.createTransfer(
          body: _body(SeedIds.zamalek, 'nowhere', 'vanilla-syrup', 1),
        ),
        _refused(404),
      );
      expect(
        _api(persona: Persona.manager).createTransfer(
          body: _body(SeedIds.maadi, SeedIds.zamalek, 'almond', 1),
        ),
        _refused(403),
      );
      expect(
        _api(persona: Persona.limited).createTransfer(
          body: _body(SeedIds.zamalek, SeedIds.maadi, 'vanilla-syrup', 1),
        ),
        _refused(403),
      );
    });
  });

  group('PATCH /inventory/transfers/{id}', () {
    test('sets and clears the note; 404 for an unknown id', () async {
      final api = _api(persona: Persona.manager);
      final id = InvIds.transfer('t3');
      final a = await api.updateTransfer(
        id: id,
        body: const UpdateTransferRequest(note: 'Pop-up stand cups'),
      );
      expect(a.note, 'Pop-up stand cups');
      final b = await api.updateTransfer(
        id: id,
        body: const UpdateTransferRequest(explicitNulls: {'note'}),
      );
      expect(b.note, isNull);
      expect(
        api.updateTransfer(id: 'gone', body: const UpdateTransferRequest()),
        _refused(404),
      );
      expect(
        _api(persona: Persona.limited).updateTransfer(
          id: id,
          body: const UpdateTransferRequest(note: 'x'),
        ),
        _refused(403),
      );
    });
  });

  group('DELETE /inventory/transfers/{id}', () {
    test('INV-TRF-029 reverses the stock, records "Transfer reversal" twice, '
        'removes the row', () async {
      final s = transfersServer();
      final api = DashboardApi(s.server).inventory;
      setOnHand(s.db, SeedIds.newCairo, 'paper-cup-12', 140);
      await api.deleteTransfer(id: InvIds.transfer('t3'));
      expect(stockRow(s.db, SeedIds.newCairo, 'paper-cup-12')!['on_hand'], 40);
      expect(stockRow(s.db, SeedIds.zamalek, 'paper-cup-12')!['on_hand'], 220);
      final moves = s.db[InvTables.movements].where(
        (m) => m['note'] == 'Transfer reversal',
      );
      expect(
        [for (final m in moves) (m['branch_id'], m['movement_type'])],
        [(SeedIds.newCairo, 'transfer_out'), (SeedIds.zamalek, 'transfer_in')],
      );
      expect(_keys(await api.listTransfers(branchId: allBranches)), [
        't1',
        't2',
        't4',
        't5',
      ]);
    });

    test(
      '409 when the destination holds less; 403 without the cap; 404',
      () async {
        final api = _api();
        expect(
          api.deleteTransfer(id: InvIds.transfer('t4')),
          _says(
            'Cannot reverse transfer: the destination branch only has 600.000 '
            'left of the 750.000 transferred.',
          ),
        );
        expect(api.deleteTransfer(id: InvIds.transfer('t4')), _refused(409));
        expect(
          _api(
            persona: Persona.manager,
          ).deleteTransfer(id: InvIds.transfer('t3')),
          _refused(403),
        );
        expect(api.deleteTransfer(id: 'gone'), _refused(404));
      },
    );
  });
}
