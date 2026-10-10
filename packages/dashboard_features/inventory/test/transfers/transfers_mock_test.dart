// The transfers unit's mock backend (`lib/src/mock/transfers_mock.dart`)
// against the backend (MadarRust `inventory/transfers.rs` @ 87340e2) and
// hand-worked figures from the seed:
//
//   TR-1 Maadi → New Cairo     Croissant Dough      12     19 Sep  received
//   TR-2 New Cairo → Zamalek   Vanilla Syrup       750 ml  24 Sep  received
//   TR-3 Zamalek → New Cairo   Paper Cup 12oz      100     30 Sep  received
//   TR-4 New Cairo → Maadi     House Blend Beans 1,000 g   03 Oct  received
//   TR-5 Maadi → Zamalek       Oat Milk          2,000 ml  06 Oct  received
//   TR-6 Maadi → Zamalek       Oat 1,500 + Blend 1,000     07 Oct  requested
//   TR-7 Maadi → Heliopolis    Croissant 10 + Vanilla 300  07 Oct  draft
//   TR-8 New Cairo → Zamalek   Caramel Syrup       500 ml  02 Oct  cancelled
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Matcher _refused(int status, [String? code]) => throwsA(
  isA<ApiException>()
      .having((e) => e.status, 'status', status)
      .having((e) => e.code, 'code', code ?? anything),
);

Matcher _says(String words) => throwsA(
  isA<ApiException>().having((e) => e.message, 'message', contains(words)),
);

({MockServer server, MockDb db, InventoryApi api}) _rig({
  Persona persona = Persona.owner,
  bool warehouse = false,
}) {
  final s = transfersServer(persona: persona);
  if (warehouse) withWarehouse(s.db);
  return (server: s.server, db: s.db, api: DashboardApi(s.server).inventory);
}

List<String> _refs(List<StockTransfer> rows) => [
  for (final r in rows) r.reference,
];

TransferLineInput _l(String key, double qty) =>
    TransferLineInput(orgIngredientId: InvIds.ingredient(key), quantity: qty);

String _id(String key) => InvIds.transfer(key);

void main() {
  group('GET transfers', () {
    test('the seed: five received documents, a request, a draft and a '
        'cancelled one, newest first', () async {
      final r = _rig();
      final all = await r.api.listTransfers(branchId: allBranches);
      expect(_refs(all), [
        'TR-7',
        'TR-6',
        'TR-5',
        'TR-4',
        'TR-8',
        'TR-3',
        'TR-2',
        'TR-1',
      ]);
      final tr5 = all[2];
      expect(tr5.status, TransferStatus.received);
      expect(tr5.sourceBranchName, 'Maadi');
      expect(tr5.destinationBranchName, 'Zamalek');
      expect(tr5.sourceKind, BranchKind.branch);
      expect(tr5.lines.single.ingredientName, 'Oat Milk');
      expect(tr5.lines.single.qtySent, 2000);
      expect(tr5.lines.single.qtyReceived, 2000);
      expect(tr5.created.byName, 'Tarek Saber');
      expect(tr5.received!.at, DateTime.utc(2026, 10, 6, 8, 30));
      expect(tr5.note, 'Zamalek ran short over the weekend');
      final tr6 = all[1];
      expect(tr6.status, TransferStatus.requested);
      expect(tr6.requested!.byName, 'Karim Adel');
      expect(
        [for (final l in tr6.lines) l.ingredientName],
        ['House Blend Beans', 'Oat Milk'],
        reason: 'lines by ingredient name',
      );
      expect(all[0].dispatched, isNull);
      expect(all[4].cancelled!.at, DateTime.utc(2026, 10, 2, 13, 20));
    });

    test('a location: both ways, direction and status filter', () async {
      final api = _rig().api;
      Future<List<String>> list({String? d, String? s}) async => _refs(
        await api.listTransfers(
          branchId: SeedIds.zamalek,
          direction: d,
          status: s,
        ),
      );
      expect(await list(), ['TR-6', 'TR-5', 'TR-8', 'TR-3', 'TR-2']);
      expect(await list(d: 'incoming'), ['TR-6', 'TR-5', 'TR-8', 'TR-2']);
      expect(await list(d: 'outgoing'), ['TR-3']);
      expect(await list(s: 'received'), ['TR-5', 'TR-3', 'TR-2']);
      expect(await list(d: 'incoming', s: 'requested'), ['TR-6']);
      expect(
        api.listTransfers(branchId: SeedIds.zamalek, status: 'lost'),
        _says('Unknown transfer status.'),
      );
    });

    test('all branches: where the person works; paging 100 by default, '
        'limit/offset', () async {
      final manager = _rig(persona: Persona.manager).api;
      expect(_refs(await manager.listTransfers(branchId: allBranches)), [
        'TR-6',
        'TR-5',
        'TR-8',
        'TR-3',
        'TR-2',
      ]);
      final api = _rig().api;
      expect(
        _refs(
          await api.listTransfers(branchId: allBranches, limit: 2, offset: 1),
        ),
        ['TR-6', 'TR-5'],
      );
      expect(
        await api.listTransfers(branchId: allBranches, offset: 8),
        isEmpty,
      );
    });

    test('refusals: no cap 403, another location 403, unknown 404', () async {
      expect(
        _rig(
          persona: Persona.limited,
        ).api.listTransfers(branchId: SeedIds.maadi),
        _refused(403),
      );
      expect(
        _rig(
          persona: Persona.manager,
        ).api.listTransfers(branchId: SeedIds.maadi),
        _refused(403),
      );
      expect(_rig().api.listTransfers(branchId: 'nowhere'), _refused(404));
    });
  });

  group('create, edit, accept, decline', () {
    test('a draft: numbered next, lines by name, nothing moves', () async {
      final r = _rig();
      final before = onHand(r.db, SeedIds.zamalek, 'vanilla-syrup');
      final tr = await r.api.createTransfer(
        body: CreateTransferRequest(
          sourceBranchId: SeedIds.zamalek,
          destinationBranchId: SeedIds.maadi,
          lines: [_l('vanilla-syrup', 200), _l('cocoa', 50.0004)],
          note: '  For the weekend ',
        ),
      );
      expect(tr.reference, 'TR-9');
      expect(tr.status, TransferStatus.draft);
      expect(tr.requested, isNull);
      expect(tr.created.byName, 'Nour El-Sayed');
      expect(tr.note, 'For the weekend');
      expect(
        [for (final l in tr.lines) (l.ingredientName, l.qtySent)],
        [('Cocoa Powder', 50), ('Vanilla Syrup', 200)],
      );
      expect(onHand(r.db, SeedIds.zamalek, 'vanilla-syrup'), before);
    });

    test('a request: made at the destination, stamped requested', () async {
      final r = _rig(persona: Persona.manager);
      final tr = await r.api.createTransfer(
        body: CreateTransferRequest(
          sourceBranchId: SeedIds.maadi,
          destinationBranchId: SeedIds.zamalek,
          request: true,
          lines: [_l('sugar', 2000)],
        ),
      );
      expect(tr.status, TransferStatus.requested);
      expect(tr.requested!.byName, 'Karim Adel');
      // Sending from Maadi is not his: 403 at the source.
      expect(
        r.api.createTransfer(
          body: CreateTransferRequest(
            sourceBranchId: SeedIds.maadi,
            destinationBranchId: SeedIds.zamalek,
            lines: [_l('sugar', 2000)],
          ),
        ),
        _refused(403),
      );
    });

    test('create refusals (400s)', () async {
      final api = _rig().api;
      Future<StockTransfer> make(List<TransferLineInput> lines, {String? to}) =>
          api.createTransfer(
            body: CreateTransferRequest(
              sourceBranchId: SeedIds.maadi,
              destinationBranchId: to ?? SeedIds.zamalek,
              lines: lines,
            ),
          );
      expect(
        make([_l('oat', 1)], to: SeedIds.maadi),
        _says('Pick two different locations.'),
      );
      expect(make([_l('oat', 1)], to: 'nowhere'), _says('Both locations'));
      expect(make([]), _says('A transfer needs at least one item.'));
      expect(make([_l('oat', 0.0004)]), _says('greater than 0'));
      expect(
        make([_l('oat', 1), _l('oat', 2)]),
        _says('Each item can appear only once on a transfer.'),
      );
      expect(
        api.createTransfer(
          body: CreateTransferRequest(
            sourceBranchId: SeedIds.maadi,
            destinationBranchId: SeedIds.zamalek,
            lines: [
              const TransferLineInput(orgIngredientId: 'ghost', quantity: 1),
            ],
          ),
        ),
        _says("An item is not in this organization's catalog."),
      );
    });

    test('edit a request (destination) and a draft (source); a step not '
        'open is 409 TRANSFER_STEP_NOT_OPEN', () async {
      final r = _rig();
      final tr6 = await r.api.updateTransfer(
        id: _id('t6'),
        body: UpdateTransferRequest(lines: [_l('oat', 1800)], note: ' ok '),
      );
      expect(tr6.status, TransferStatus.requested);
      expect(tr6.lines.single.qtySent, 1800);
      expect(tr6.note, 'ok');
      // A null note leaves it.
      final again = await r.api.updateTransfer(
        id: _id('t6'),
        body: const UpdateTransferRequest(explicitNulls: {'note'}),
      );
      expect(again.note, 'ok');
      expect(
        r.api.updateTransfer(
          id: _id('t1'),
          body: UpdateTransferRequest(lines: [_l('oat', 1)]),
        ),
        _refused(409, 'TRANSFER_STEP_NOT_OPEN'),
      );
      expect(
        r.api.updateTransfer(id: 'ghost', body: const UpdateTransferRequest()),
        _refused(404),
      );
      // The manager works at Zamalek, the request's destination, not at
      // Maadi, the draft's source.
      final m = _rig(persona: Persona.manager).api;
      await m.updateTransfer(
        id: _id('t6'),
        body: UpdateTransferRequest(lines: [_l('oat', 1000)]),
      );
      expect(
        m.updateTransfer(
          id: _id('t7'),
          body: UpdateTransferRequest(lines: [_l('oat', 1)]),
        ),
        _refused(403),
      );
    });

    test('accept makes the request the source\'s draft; decline needs a '
        'reason and cancels', () async {
      final r = _rig();
      final accepted = await r.api.acceptTransfer(
        id: _id('t6'),
        body: AcceptTransferRequest(lines: [_l('oat', 1000)]),
      );
      expect(accepted.status, TransferStatus.draft);
      expect(accepted.lines.single.qtySent, 1000);
      expect(
        r.api.declineTransfer(
          id: _id('t6'),
          body: const CloseTransferRequest(note: 'x'),
        ),
        _refused(409, 'TRANSFER_STEP_NOT_OPEN'),
      );
      final r2 = _rig();
      expect(
        r2.api.declineTransfer(
          id: _id('t6'),
          body: const CloseTransferRequest(note: '  '),
        ),
        _says("Say why you're declining the request."),
      );
      final declined = await r2.api.declineTransfer(
        id: _id('t6'),
        body: const CloseTransferRequest(note: 'We are short ourselves'),
      );
      expect(declined.status, TransferStatus.cancelled);
      expect(declined.cancelled!.byName, 'Nour El-Sayed');
      expect(
        declined.note,
        'Weekend rush: please send before Friday\nDeclined: We are short '
        'ourselves',
      );
      // The manager is not at Maadi, the request's source.
      expect(
        _rig(persona: Persona.manager).api.acceptTransfer(
          id: _id('t6'),
          body: const AcceptTransferRequest(),
        ),
        _refused(403),
      );
    });
  });

  group('dispatch, receive, cancel', () {
    test('dispatch takes the stock off the source at its cost; short → '
        '409 TRANSFER_INSUFFICIENT_STOCK', () async {
      final r = _rig();
      final croissants = onHand(r.db, SeedIds.maadi, 'croissant');
      final sent = await r.api.dispatchTransfer(id: _id('t7'));
      expect(sent.status, TransferStatus.dispatched);
      expect(sent.dispatched!.byName, 'Nour El-Sayed');
      expect(onHand(r.db, SeedIds.maadi, 'croissant'), croissants - 10);
      expect(sent.lines.every((l) => l.unitCost != null), isTrue);
      final outs = r.db[InvTables.movements].where(
        (m) => m['source_id'] == _id('t7'),
      );
      expect(
        [for (final m in outs) m['movement_type']],
        ['transfer_out', 'transfer_out'],
      );
      expect(
        r.api.dispatchTransfer(id: _id('t7')),
        _refused(409, 'TRANSFER_STEP_NOT_OPEN'),
      );

      final r2 = _rig();
      stockRow(r2.db, SeedIds.maadi, 'croissant')!['on_hand'] = 4.0;
      expect(
        r2.api.dispatchTransfer(id: _id('t7')),
        _refused(409, 'TRANSFER_INSUFFICIENT_STOCK'),
      );
      expect(
        r2.api.dispatchTransfer(id: _id('t7')),
        _says('Not enough stock to send: Croissant Dough (4.000 on hand).'),
      );
    });

    test('receive lands what arrived; checks every line once, no negative, '
        'a note for over', () async {
      final r = _rig();
      final t = dispatchDraft(r.db);
      final lines = (t['lines']! as List).cast<MockRow>();
      final cro =
          lines.firstWhere(
                (l) => l['ingredient_name'] == 'Croissant Dough',
              )['id']!
              as String;
      final van =
          lines.firstWhere(
                (l) => l['ingredient_name'] == 'Vanilla Syrup',
              )['id']!
              as String;
      Future<StockTransfer> receive(List<ReceiveTransferLine> l) =>
          r.api.receiveTransfer(
            id: _id('t7'),
            body: ReceiveTransferRequest(lines: l),
          );
      expect(
        receive([ReceiveTransferLine(lineId: cro, qtyReceived: 10)]),
        _says('Say what arrived for every line on the transfer, once each.'),
      );
      expect(
        receive([
          ReceiveTransferLine(lineId: cro, qtyReceived: -1),
          ReceiveTransferLine(lineId: van, qtyReceived: 300),
        ]),
        _says("A received quantity can't be negative."),
      );
      expect(
        receive([
          ReceiveTransferLine(lineId: cro, qtyReceived: 11),
          ReceiveTransferLine(lineId: van, qtyReceived: 300),
        ]),
        _refused(400, 'OVER_RECEIVE_NEEDS_NOTE'),
      );
      final heli = onHand(r.db, SeedIds.heliopolis, 'croissant');
      final got = await receive([
        ReceiveTransferLine(lineId: cro, qtyReceived: 8, note: ' Crushed '),
        ReceiveTransferLine(lineId: van, qtyReceived: 300.0004),
      ]);
      expect(got.status, TransferStatus.received);
      expect(got.received!.byName, 'Nour El-Sayed');
      final c = got.lines.firstWhere(
        (l) => l.ingredientName == 'Croissant Dough',
      );
      expect(c.qtyReceived, 8);
      expect(c.note, 'Crushed');
      expect(onHand(r.db, SeedIds.heliopolis, 'croissant'), heli + 8);
    });

    test('cancel: a draft moves nothing; in transit it lands back at the '
        'source and needs inventory.transfers.delete', () async {
      final r = _rig();
      final cancelled = await r.api.cancelStockTransfer(
        id: _id('t7'),
        body: const CloseTransferRequest(note: 'Not needed'),
      );
      expect(cancelled.status, TransferStatus.cancelled);
      expect(cancelled.note, 'Not needed');

      final r2 = _rig();
      final before = onHand(r2.db, SeedIds.maadi, 'croissant');
      dispatchDraft(r2.db);
      expect(onHand(r2.db, SeedIds.maadi, 'croissant'), before - 10);
      await r2.api.cancelStockTransfer(
        id: _id('t7'),
        body: const CloseTransferRequest(),
      );
      expect(onHand(r2.db, SeedIds.maadi, 'croissant'), before);

      // A manager holds create but not delete.
      final r3 = _rig(persona: Persona.manager);
      final t3 = doc(r3.db, 't8')
        ..['status'] = 'dispatched'
        ..['source_branch_id'] = SeedIds.zamalek;
      expect(t3['status'], 'dispatched');
      expect(
        r3.api.cancelStockTransfer(
          id: _id('t8'),
          body: const CloseTransferRequest(),
        ),
        _refused(403),
      );
    });
  });

  group('locations, differences, replenishment', () {
    test(
      'locations: every active location with its kind; create cap',
      () async {
        final r = _rig(warehouse: true);
        final rows = await r.api.transferLocations(orgId: SeedIds.sabahOrg);
        expect(
          [for (final l in rows) (l.name, l.kind)],
          [
            ('Heliopolis', 'branch'),
            ('Maadi', 'branch'),
            ('New Cairo', 'branch'),
            ('Zamalek', 'branch'),
            ('Central Store', 'warehouse'),
          ],
        );
        expect(
          _rig(
            persona: Persona.limited,
          ).api.transferLocations(orgId: SeedIds.sabahOrg),
          _refused(403),
        );
      },
    );

    test('differences: received lines that differ, in the period, signed, '
        'valued at the line cost', () async {
      final r = _rig();
      final t = receiveShort(r.db);
      final cost =
          ((t['lines']! as List).cast<MockRow>().firstWhere(
                    (l) => l['ingredient_name'] == 'Croissant Dough',
                  )['unit_cost']!
                  as num)
              .toDouble();
      final rows = await r.api.transferDifferences(
        orgId: SeedIds.sabahOrg,
        from: DateTime.utc(2026, 10, 1),
        to: DateTime.utc(2026, 10, 9),
      );
      expect(rows, hasLength(1));
      final d = rows.single;
      expect(d.reference, 'TR-7');
      expect(d.ingredientName, 'Croissant Dough');
      expect(d.difference, -2);
      expect(d.valueDifference, (-2 * cost).round());
      expect(d.note, 'Two crushed in the van');
      expect(
        await r.api.transferDifferences(
          orgId: SeedIds.sabahOrg,
          from: DateTime.utc(2026, 10, 9),
        ),
        isEmpty,
      );
    });

    test('replenishment: low rows, to max less what is coming, capped by '
        'the warehouse', () async {
      final r = _rig(warehouse: true);
      final rows = await r.api.replenishment(
        warehouseId: centralStore,
        branchId: SeedIds.zamalek,
      );
      final oat = rows.firstWhere((x) => x.ingredientName == 'Oat Milk');
      expect(oat.onHand, 2000);
      expect(oat.parMin, 3000);
      expect(oat.parMax, 10000);
      expect(oat.openInbound, 1500, reason: 'TR-6 asks Maadi for 1,500');
      expect(oat.inTransit, 0);
      expect(oat.need, 6500);
      expect(oat.available, 12000);
      expect(oat.suggested, 6500);
      expect(
        r.api.replenishment(
          warehouseId: SeedIds.maadi,
          branchId: SeedIds.zamalek,
        ),
        _says('Replenishment comes from a warehouse.'),
      );
      expect(
        r.api.replenishment(warehouseId: centralStore, branchId: centralStore),
        _refused(404),
      );
    });
  });
}
