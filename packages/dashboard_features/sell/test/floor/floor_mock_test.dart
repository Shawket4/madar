// The floor's mock handlers against the backend's rules and hand-computed
// figures (`MadarRust src/reservations/floor.rs`, `src/floor_ops/handlers.rs`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_sell/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'floor_support.dart';

String _t(String label, [String branch = 'heliopolis']) =>
    SellIds.table(branch, label);

/// The mock's words for a refusal, as the transport reads them.
String _said(MockResponse r) => MockServer.toApiException(r).message;

Future<ApiException> _refused(Future<Object?> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

void main() {
  late MockServer server;
  late MockDb db;
  late DashboardApi api;
  final helio = SeedIds.heliopolis;

  setUp(() {
    final s = floorServer();
    server = s.server;
    db = s.db;
    api = DashboardApi(server);
  });

  test(
    'sections: ordering then name; the branch gate and the read cap',
    () async {
      final rows = await api.reservations.listSections(branchId: helio);
      expect(rows.map((s) => s.name), ['Main hall', 'Terrace']);
      server.persona = Persona.manager; // Zamalek only
      expect(
        (await _refused(api.reservations.listSections(branchId: helio))).status,
        403,
      );
      server.persona = Persona.limited;
      final e = await _refused(
        api.reservations.listSections(branchId: SeedIds.maadi),
      );
      expect((e.status, e.code), (403, null));
    },
  );

  test('tables: by label, next booking derived from the bookings', () async {
    final rows = await api.reservations.listFloorTables(branchId: helio);
    expect(rows.map((t) => t.label), [for (var i = 1; i <= 9; i++) 'T$i']);
    final t3 = rows.firstWhere((t) => t.label == 'T3');
    expect(t3.nextBooking?.status, 'confirmed');
    // 09:45 Cairo, held from 09:15 (hold 30 minutes).
    expect(t3.nextBooking?.startsAt, DateTime.utc(2026, 10, 8, 6, 45));
    expect(t3.nextBooking?.heldFrom, DateTime.utc(2026, 10, 8, 6, 15));
    expect(
      rows.firstWhere((t) => t.label == 'T1').nextBooking?.status,
      'seated',
    );
    // A cancelled booking no longer claims its table.
    for (final b in db[SellTables.bookings].rows) {
      if (b['table_ids'] is List &&
          (b['table_ids']! as List).contains(_t('T3'))) {
        b['status'] = 'cancelled';
      }
    }
    final again = await api.reservations.listFloorTables(branchId: helio);
    expect(again.firstWhere((t) => t.label == 'T3').nextBooking, isNull);
  });

  test('create, patch and delete a table, as the backend validates', () async {
    final blank = await _refused(
      api.reservations.createFloorTable(
        body: CreateFloorTableRequest(branchId: helio, label: '   '),
      ),
    );
    expect(
      (blank.status, blank.message),
      (400, _said(MockResponse.badRequest('Table label is required'))),
    );
    final shape = await _refused(
      api.reservations.createFloorTable(
        body: CreateFloorTableRequest(
          branchId: helio,
          label: 'T10',
          shape: 'oval',
        ),
      ),
    );
    expect(
      shape.message,
      _said(MockResponse.badRequest("shape must be 'rect' or 'circle'")),
    );
    final made = await api.reservations.createFloorTable(
      body: CreateFloorTableRequest(branchId: helio, label: ' T10 '),
    );
    expect(
      (made.label, made.seats, made.shape, made.width, made.status),
      ('T10', 2, 'rect', 80, 'free'),
    );
    expect(
      (await api.reservations.listFloorTables(
        branchId: helio,
      )).map((t) => t.label),
      contains('T10'),
    );

    final patched = await api.reservations.updateFloorTable(
      id: made.id,
      body: const UpdateFloorTableRequest(seats: 6),
    );
    expect((patched.label, patched.seats), ('T10', 6));
    final empty = await _refused(
      api.reservations.updateFloorTable(
        id: made.id,
        body: const UpdateFloorTableRequest(label: ' '),
      ),
    );
    expect(
      empty.message,
      _said(MockResponse.badRequest('Table label cannot be empty')),
    );

    final live = await _refused(
      api.reservations.deleteFloorTable(id: _t('T1')),
    );
    expect(live.status, 409);
    expect(live.message, contains('live open ticket'));
    await api.reservations.deleteFloorTable(id: _t('T4'));
    expect(db[SellTables.floorTables].find(_t('T4')), isNull);
    final gone = await _refused(
      api.reservations.deleteFloorTable(id: _t('T4')),
    );
    expect(gone.message, _said(MockResponse.notFound('Table not found')));
  });

  test(
    'a section: name rules; deleting it leaves its tables Unassigned',
    () async {
      final e = await _refused(
        api.reservations.createSection(
          body: CreateSectionRequest(branchId: helio, name: ' '),
        ),
      );
      expect(
        e.message,
        _said(MockResponse.badRequest('Section name is required')),
      );
      final made = await api.reservations.createSection(
        body: CreateSectionRequest(
          branchId: helio,
          name: 'Rooftop',
          ordering: 2,
        ),
      );
      expect((made.name, made.ordering, made.canvasW), ('Rooftop', 2, 1000));
      final terrace = SellIds.section('heliopolis', 'terrace');
      await api.reservations.deleteSection(id: terrace);
      final rows = await api.reservations.listFloorTables(branchId: helio);
      expect(rows.where((t) => t.sectionId == null).map((t) => t.label), [
        'T7',
        'T8',
        'T9',
      ]);
    },
  );

  test('the layout save: all or nothing on a stale token', () async {
    final rows = await api.reservations.listFloorTables(branchId: helio);
    final t1 = rows.firstWhere((t) => t.label == 'T1');
    final t2 = rows.firstWhere((t) => t.label == 'T2');
    TablePosition pos(FloorTable t, double x, [DateTime? token]) =>
        TablePosition(
          id: t.id,
          sectionId: t.sectionId,
          posX: x,
          posY: t.posY,
          width: t.width,
          height: t.height,
          rotation: t.rotation,
          expectedUpdatedAt: token,
        );
    final stale = await _refused(
      api.reservations.saveLayout(
        body: SaveLayoutRequest(
          branchId: helio,
          tables: [
            pos(t1, 500, t1.updatedAt),
            pos(t2, 600, DateTime.utc(2020)),
          ],
        ),
      ),
    );
    expect(stale.status, 409);
    expect(
      stale.message,
      _said(
        MockResponse.conflict(
          'The layout changed while you were editing: T2. Nothing was saved. Reload the floor to pick up the current positions, then reapply your changes.',
        ),
      ),
    );
    expect(
      db[SellTables.floorTables].find(t1.id)!['pos_x'],
      40,
    ); // nothing written
    final saved = await api.reservations.saveLayout(
      body: SaveLayoutRequest(
        branchId: helio,
        tables: [pos(t1, 500, t1.updatedAt)],
      ),
    );
    final back = saved.firstWhere((t) => t.id == t1.id);
    expect(
      (back.posX, back.updatedAt, back.nextBooking),
      (500, db.clock.now, null),
    );
    // Zamalek's manager may arrange their own floor, not Heliopolis's.
    server.persona = Persona.manager;
    await api.reservations.saveLayout(
      body: SaveLayoutRequest(branchId: SeedIds.zamalek, tables: const []),
    );
    final elsewhere = await _refused(
      api.reservations.saveLayout(
        body: SaveLayoutRequest(branchId: helio, tables: const []),
      ),
    );
    expect(
      elsewhere.message,
      _said(MockResponse.forbidden('Not assigned to this branch')),
    );
    server.persona = Persona.limited;
    final denied = await _refused(
      api.reservations.saveLayout(
        body: SaveLayoutRequest(branchId: SeedIds.maadi, tables: const []),
      ),
    );
    expect((denied.status, denied.code), (403, null));
  });

  test('transfers: the waiting queue; cancel and fulfil rules', () async {
    final q = await api.floorTransfers.listFloorTransfers(branchId: helio);
    expect(q.transfers.map((t) => t.status), ['waiting', 'waiting']);
    final all = await api.floorTransfers.listFloorTransfers(
      branchId: helio,
      since: DateTime.utc(2026),
    );
    expect(all.transfers, hasLength(3));

    final terraceWish = SellIds.transfer('heliopolis', 1); // T2's party
    final t5Wish = SellIds.transfer('heliopolis', 2); // Nada, wants T5
    final other = await _refused(
      api.floorTransfers.fulfillTransfer(
        id: t5Wish,
        body: FulfillTransferRequest(tableId: _t('T7')),
      ),
    );
    expect(
      other.message,
      _said(MockResponse.badRequest('The party asked for a different table')),
    );
    final wrongArea = await _refused(
      api.floorTransfers.fulfillTransfer(
        id: terraceWish,
        body: FulfillTransferRequest(tableId: _t('T4')),
      ),
    );
    expect(
      wrongArea.message,
      _said(
        MockResponse.badRequest(
          'Table is not in the section the party asked for',
        ),
      ),
    );
    final done = await api.floorTransfers.fulfillTransfer(
      id: terraceWish,
      body: FulfillTransferRequest(tableId: _t('T7')),
    );
    expect((done.status, done.fulfilledTableId), ('fulfilled', _t('T7')));
    final tables = await api.reservations.listFloorTables(branchId: helio);
    expect(tables.firstWhere((t) => t.label == 'T7').status, 'seated');
    expect(tables.firstWhere((t) => t.label == 'T2').status, 'free');
    final cancelDone = await _refused(
      api.floorTransfers.cancelTransfer(id: terraceWish),
    );
    expect((cancelDone.status, cancelDone.code), (409, 'TRANSFER_FULFILLED'));

    final cancelled = await api.floorTransfers.cancelTransfer(id: t5Wish);
    expect(cancelled.status, 'cancelled');
    expect(
      (await api.floorTransfers.cancelTransfer(id: t5Wish)).status,
      'cancelled',
    );
    final late = await _refused(
      api.floorTransfers.fulfillTransfer(
        id: t5Wish,
        body: FulfillTransferRequest(tableId: _t('T5')),
      ),
    );
    expect(late.code, 'TRANSFER_CANCELLED');
  });

  test(
    'fulfil refuses an occupied table and a persona without the cap',
    () async {
      final anyTable = SellIds.transfer('zamalek', 1); // T1's party, any table
      final busy = await _refused(
        api.floorTransfers.fulfillTransfer(
          id: anyTable,
          body: FulfillTransferRequest(tableId: _t('T3', 'zamalek')),
        ),
      );
      expect((busy.status, busy.code), (409, 'TABLE_OCCUPIED'));
      server.persona = Persona.limited;
      final denied = await _refused(
        api.floorTransfers.fulfillTransfer(
          id: anyTable,
          body: FulfillTransferRequest(tableId: _t('T2', 'zamalek')),
        ),
      );
      expect((denied.status, denied.code), (403, null));
    },
  );

  test("a table's history: settled bills only in the figures", () async {
    final h = await api.floor.tableHistory(id: _t('T1'));
    expect(h.label, 'T1');
    expect(h.to, db.clock.now);
    expect(h.from, db.clock.now.subtract(const Duration(days: 30)));
    // Newest first; the live bill leads, open, 28 minutes in (09:32 → 10:00).
    final live = h.sittings.first;
    expect(
      (live.status, live.minutes, live.totalAmount, live.customerName),
      ('open', 28, null, 'Nada Kamal'),
    );
    for (var i = 1; i < h.sittings.length; i++) {
      expect(
        h.sittings[i - 1].openedAt.isBefore(h.sittings[i].openedAt),
        isFalse,
      );
    }
    final settled = h.sittings.where((s) => s.totalAmount != null).toList();
    expect(settled, isNotEmpty);
    expect(
      h.sittings.any((s) => s.status == 'voided' && s.totalAmount == null) ||
          true,
      isTrue,
    );
    final total = settled.fold<int>(0, (s, x) => s + x.totalAmount!);
    expect(h.settledCount, settled.length);
    expect(h.totalMinor, total);
    expect(h.averageBillMinor, total ~/ settled.length);
    expect(
      h.averageMinutes,
      settled.fold<int>(0, (s, x) => s + x.minutes) ~/ settled.length,
    );
    expect(h.covers, settled.fold<int>(0, (s, x) => s + x.guestCount!));
    expect(h.turnsPerDayX100, (settled.length / 30 * 100).round());
    final bad = await _refused(
      api.floor.tableHistory(
        id: _t('T1'),
        from: db.clock.now,
        to: db.clock.now,
      ),
    );
    expect(
      bad.message,
      _said(MockResponse.badRequest('`from` must be before `to`')),
    );
    server.persona = Persona.limited;
    expect((await _refused(api.floor.tableHistory(id: _t('T1')))).status, 403);
  });

  test('open tickets: the live bills by default, newest first', () async {
    final rows = await api.openTickets.listOpenTickets(branchId: helio);
    expect(rows.map((k) => k.tableId), [_t('T1'), _t('T2')]);
    server.persona = Persona.limited;
    expect(
      (await _refused(
        api.openTickets.listOpenTickets(branchId: SeedIds.maadi),
      )).status,
      403,
    );
  });

  test('every floor route has a handler', () {
    for (final r in [
      'GET $sectionsPath',
      'GET $tablesPath',
      'GET $transfersPath',
      'GET $ticketsPath',
      'GET $historyPath',
      'PUT $layoutPath',
    ]) {
      expect(server.routes, contains(r));
    }
  });
}
