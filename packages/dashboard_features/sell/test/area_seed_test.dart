// The area seed: its rows agree with each other and with the core seed, and
// registering the area loads them once.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_sell/dashboard_sell.dart';
import 'package:dashboard_sell/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final seed = SellSeed.instance;
  final now = SellSeed.now;

  test('every booking names tables of its own branch', () {
    final byId = {for (final t in seed.tables) t.id: t};
    for (final b in seed.bookings) {
      expect(b.tableIds.length, b.tableLabels.length);
      expect(b.needsTable, b.tableIds.isEmpty, reason: b.guestName);
      for (final (i, id) in b.tableIds.indexed) {
        final t = byId[id]!;
        expect(t.branchId, b.branchId);
        expect(t.label, b.tableLabels[i]);
        expect(t.isActive, isTrue);
      }
    }
  });

  test('active bookings never overlap on a table', () {
    final active = seed.bookings
        .where((b) => b.status == 'confirmed' || b.status == 'seated')
        .toList();
    for (final a in active) {
      for (final b in active) {
        if (identical(a, b)) continue;
        final shared = a.tableIds.any(b.tableIds.contains);
        final overlap =
            a.startsAt.isBefore(b.endsAt) && b.startsAt.isBefore(a.endsAt);
        expect(shared && overlap, isFalse, reason: '${a.id} / ${b.id}');
      }
    }
  });

  test('seated tables and open tickets agree', () {
    for (final k in seed.openTickets) {
      final t = seed.tables.firstWhere((t) => t.id == k.tableId);
      expect(t.status, 'seated');
      expect(t.branchId, k.branchId);
      expect(k.bill!.total, k.subtotal);
      expect(k.items.fold<int>(0, (s, i) => s + i.lineTotal), k.subtotal);
    }
    final ticketTables = {for (final k in seed.openTickets) k.tableId};
    final parked = seed.tables.where(
      (t) => t.status == 'seated' && !ticketTables.contains(t.id),
    );
    expect(parked.map((t) => t.label), ['T3']);
  });

  test('Nada Kamal is seated at Heliopolis T1 from her booking', () {
    final b = seed.bookings.firstWhere((b) => b.id == SellIds.nadaBooking);
    final nada = MockSeed.instance.customers.first;
    expect(b.status, 'seated');
    expect(b.customerId, nada.id);
    expect(b.guestName, nada.name);
    expect(b.guestPhone, '201001234567');
    expect(b.tableLabels, ['T1']);
    final ticket = seed.openTickets.firstWhere(
      (k) => k.bookingId == SellIds.nadaBooking,
    );
    expect(ticket.tableId, SellIds.table('heliopolis', 'T1'));
    expect(ticket.customerId, nada.id);
    expect(b.openTicketId, ticket.id);
  });

  test("Heliopolis' morning: a late, a due, an old bill, a table to clear", () {
    final today = MockClock.cairoDate(now);
    final hl = seed.bookings.where(
      (b) =>
          b.branchId == SeedIds.heliopolis &&
          MockClock.cairoDate(b.startsAt) == today,
    );
    final late = hl.where(
      (b) => b.status == 'confirmed' && b.startsAt.isBefore(now),
    );
    final due = hl.where(
      (b) =>
          b.status == 'confirmed' &&
          !b.startsAt.isBefore(now) &&
          !b.heldFrom.isAfter(now),
    );
    expect(late.single.tableLabels, ['T3']);
    expect(due.single.tableLabels, ['T6']);
    expect(hl.where((b) => b.needsTable).single.partySize, 6);
    final old = seed.openTickets.where(
      (k) =>
          k.branchId == SeedIds.heliopolis &&
          now.difference(k.openedAt) > const Duration(hours: 3),
    );
    expect(old.single.status, 'ready');
    final t5 = seed.tables.firstWhere(
      (t) => t.id == SellIds.table('heliopolis', 'T5'),
    );
    expect(t5.status, 'dirty');
  });

  test("a table's next booking follows the backend's rule", () {
    final t3 = seed.tables.firstWhere(
      (t) => t.id == SellIds.table('heliopolis', 'T3'),
    );
    expect(t3.nextBooking?.status, 'confirmed');
    expect(t3.nextBooking!.heldFrom.isAfter(now), isFalse);
    for (final t in seed.tables) {
      final n = t.nextBooking;
      if (n == null) continue;
      expect(n.endsAt.isAfter(now), isTrue);
      expect(n.startsAt.isBefore(now.add(const Duration(hours: 24))), isTrue);
      expect(n.status == 'confirmed' || n.status == 'seated', isTrue);
    }
  });

  test('each branch has its sections, settings and an unassigned table', () {
    for (final b in SeedIds.sabahBranches) {
      expect(seed.sections.where((s) => s.branchId == b), isNotEmpty);
      expect(seed.bookingSettings.where((s) => s.branchId == b), hasLength(1));
    }
    final zamalek = seed.bookingSettings.firstWhere(
      (s) => s.branchId == SeedIds.zamalek,
    );
    expect(zamalek.enabled, isFalse);
    expect(seed.tables.where((t) => t.sectionId == null).map((t) => t.label), [
      'Bar 1',
    ]);
  });

  test('registering the area loads the seed once, as model JSON', () {
    final db = MockDb.seeded();
    final server = MockServer(persona: Persona.owner, clock: db.clock);
    registerSellMocks(server, db);
    registerSellMocks(server, db);
    expect(db[SellTables.floorTables].length, seed.tables.length);
    expect(db[SellTables.bookings].length, seed.bookings.length);
    expect(db[SellTables.openTickets].length, seed.openTickets.length);
    expect(db[SellTables.floorTransfers].length, seed.transfers.length);
    expect(db[SellTables.floorSections].length, seed.sections.length);
    final settings = bookingSettingsRow(db, SeedIds.maadi)!;
    expect(settings.containsKey('id'), isFalse);
    expect(BookingSettings.fromJson(settings).branchId, SeedIds.maadi);
    for (final r in db[SellTables.floorTables].rows) {
      expect(FloorTable.fromJson(r).id, r['id']);
    }
    for (final r in db[SellTables.bookings].rows) {
      expect(BookingView.fromJson(r).id, r['id']);
    }
    for (final r in db[SellTables.openTickets].rows) {
      expect(OpenTicketView.fromJson(r).id, r['id']);
    }
    for (final r in db[SellTables.floorTransfers].rows) {
      expect(TransferView.fromJson(r).id, r['id']);
    }
  });
}
