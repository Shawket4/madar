/// The sell area's own seed: the domain data several units share, so their
/// numbers agree — the floor plans (Floor; Bookings' tables and timeline),
/// the bookings (Bookings; the floor's reservations; a customer's Bookings
/// section), each branch's booking settings, the open tickets (the floor's
/// occupants; Tills' open bills) and the transfer queue.
///
/// It is built on the core seed (`package:dashboard_api/mock.dart`): Sabah
/// Coffee's four branches, its staff (tellers, Zamalek's waiters) and its
/// customers, at the core seed's "now" (Thursday 2026-10-08, 10:00 Cairo).
/// Every row is a generated model's `toJson()`, so handlers answer the spec's
/// exact shape. A unit may add its own rows in its own mock file (orders:
/// delivery orders; tills: cash movements, spot views; customers: addresses),
/// referencing these ids.
///
/// The morning at a glance, per branch (now = 10:00):
/// - Heliopolis: T1 seated by Nada Kamal's 09:30 booking (party 3, open
///   ticket); T2 a walk-in whose ticket has been open since 06:58 (an old
///   bill, ready); T3 held for a LATE 09:45 booking; T6 held for a DUE 10:15
///   booking; T5 needs clearing; a 13:00 party of 6 needs a table; T9 is
///   inactive; two parties wait in the transfer queue.
/// - Maadi: T2 seated (open ticket); T4 needs clearing.
/// - New Cairo: T1 and T3 seated (open tickets); T6 needs clearing.
/// - Zamalek: online booking off; T1 seated by a waiter's ticket; T3 seated
///   with no ticket (an order parked on a till); T4 needs clearing; "Bar 1"
///   has no section (the Unassigned chip); one party waits for any table.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import 'shared/phone.dart';

/// The [MockDb] tables the area seed fills.
abstract final class SellTables {
  /// [FloorSection] rows.
  static const String floorSections = 'floor_sections';

  /// [FloorTable] rows (with `next_booking`, derived from [bookings]).
  static const String floorTables = 'floor_tables';

  /// [BookingView] rows.
  static const String bookings = 'bookings';

  /// [BookingSettings] rows, one per branch. They have NO `id`: look one up
  /// with [bookingSettingsRow] and change it in place.
  static const String bookingSettings = 'booking_settings';

  /// [OpenTicketView] rows (`/open-tickets`).
  static const String openTickets = 'open_tickets';

  /// [TransferView] rows (`/floor/transfers`).
  static const String floorTransfers = 'floor_transfers';
}

/// The stable ids of the area seed's rows.
abstract final class SellIds {
  static String section(String branchKey, String key) =>
      mockUuid('floor-section:$branchKey:$key');

  static String table(String branchKey, String label) =>
      mockUuid('floor-table:$branchKey:$label');

  static String booking(String branchKey, String date, int n) =>
      mockUuid('booking:$branchKey:$date:$n');

  static String ticket(String branchKey, String label) =>
      mockUuid('open-ticket:$branchKey:$label');

  static String transfer(String branchKey, int n) =>
      mockUuid('floor-transfer:$branchKey:$n');

  /// Heliopolis's 09:30 booking: Nada Kamal, party of 3, seated at T1.
  static final String nadaBooking = booking('heliopolis', '2026-10-08', 2);
}

/// Loads the area seed into [db] once (a second call is a no-op).
void loadSellSeed(MockDb db) {
  if (db.hasTable(SellTables.floorTables)) return;
  SellSeed.instance.loadInto(db);
}

/// [branchId]'s booking settings row (mutable), if the branch has one.
MockRow? bookingSettingsRow(MockDb db, String branchId) => db
    .table(SellTables.bookingSettings)
    .firstWhere((r) => r['branch_id'] == branchId);

// ── The plans ────────────────────────────────────────────────────────────

class _T {
  const _T(
    this.label,
    this.seats,
    this.shape, {
    this.active = true,
    this.rotation = 0,
  });

  final String label;
  final int seats;
  final String shape;
  final bool active;
  final double rotation;
}

class _S {
  const _S(this.key, this.name, this.tables);

  /// Null = the branch's tables without a section.
  final String? key;
  final String name;
  final List<_T> tables;
}

const Map<String, List<_S>> _plans = {
  'heliopolis': [
    _S('main', 'Main hall', [
      _T('T1', 4, 'rect'),
      _T('T2', 4, 'rect'),
      _T('T3', 2, 'circle'),
      _T('T4', 2, 'circle'),
      _T('T5', 6, 'rect'),
      _T('T6', 4, 'rect'),
    ]),
    _S('terrace', 'Terrace', [
      _T('T7', 2, 'circle'),
      _T('T8', 2, 'circle'),
      _T('T9', 4, 'rect', active: false),
    ]),
  ],
  'maadi': [
    _S('indoor', 'Indoor', [
      _T('T1', 2, 'circle'),
      _T('T2', 4, 'rect'),
      _T('T3', 4, 'rect'),
      _T('T4', 6, 'rect'),
    ]),
    _S('garden', 'Garden', [
      _T('T5', 4, 'rect'),
      _T('T6', 4, 'rect'),
      _T('T7', 2, 'circle'),
      _T('T8', 2, 'circle'),
    ]),
  ],
  'new-cairo': [
    _S('ground', 'Ground floor', [
      _T('T1', 4, 'rect'),
      _T('T2', 4, 'rect'),
      _T('T3', 2, 'circle'),
      _T('T4', 2, 'circle'),
      _T('T5', 6, 'rect'),
      _T('T6', 4, 'rect'),
    ]),
    _S('mezzanine', 'Mezzanine', [
      _T('T7', 2, 'circle'),
      _T('T8', 2, 'circle'),
      _T('T9', 4, 'rect'),
    ]),
    _S('outdoor', 'Outdoor', [
      _T('T10', 4, 'rect'),
      _T('T11', 4, 'rect'),
      _T('T12', 8, 'rect'),
    ]),
  ],
  'zamalek': [
    _S('main', 'Main hall', [
      _T('T1', 2, 'circle'),
      _T('T2', 4, 'rect'),
      _T('T3', 4, 'rect'),
      _T('T4', 2, 'circle'),
      _T('T5', 6, 'rect', rotation: 90),
    ]),
    _S('nile', 'Nile terrace', [
      _T('T6', 2, 'circle'),
      _T('T7', 2, 'circle'),
      _T('T8', 4, 'rect', rotation: 45),
      _T('T9', 4, 'rect'),
    ]),
    _S(null, '', [_T('Bar 1', 2, 'circle')]),
  ],
};

/// Tables someone is sitting at now: (branch, table, ticket opened at Cairo
/// h:m, customer index in the core seed or null, guests, ready).
const List<(String, String, int, int, int?, int, bool)> _seated = [
  ('heliopolis', 'T1', 9, 32, 0, 3, false),
  ('heliopolis', 'T2', 6, 58, null, 2, true),
  ('maadi', 'T2', 9, 40, 7, 4, false),
  ('new-cairo', 'T1', 8, 15, 3, 2, false),
  ('new-cairo', 'T3', 9, 50, null, 2, false),
  ('zamalek', 'T1', 9, 5, 12, 2, false),
];

/// Tables marked dirty (paid, not yet cleared).
const List<(String, String)> _dirty = [
  ('heliopolis', 'T5'),
  ('maadi', 'T4'),
  ('new-cairo', 'T6'),
  ('zamalek', 'T4'),
];

/// A seated table with no ticket: an order parked on a till.
const List<(String, String)> _parked = [('zamalek', 'T3')];

const int _holdMinutes = 30;
const int _defaultDuration = 90;

// ── The seed ─────────────────────────────────────────────────────────────

/// Built once per process from the core seed; a [MockDb] copies it.
class SellSeed {
  SellSeed._();

  static final SellSeed instance = SellSeed._();

  static DateTime get now => MockSeed.now;

  static final DateTime _layoutCreated = DateTime.utc(2026, 2, 1, 8);
  static final DateTime _layoutUpdated = DateTime.utc(2026, 9, 20, 8);

  MockSeed get _core => MockSeed.instance;

  String get _today => MockClock.cairoDate(now);

  /// The branch key of a Sabah branch id (`heliopolis`, …).
  static String branchKeyOf(String branchId) => _plans.keys.firstWhere(
    (k) => MockSeed.branchIdOf(k) == branchId,
  );

  static DateTime _at(String date, int hour, int minute) {
    final p = date.split('-').map(int.parse).toList();
    return MockClock.fromCairo(p[0], p[1], p[2], hour, minute);
  }

  static String _dayOffset(String date, int days) {
    final p = date.split('-').map(int.parse).toList();
    final d = DateTime.utc(p[0], p[1], p[2]).add(Duration(days: days));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  // Sections and the raw table layout.

  late final List<FloorSection> sections = [
    for (final b in _plans.keys)
      for (final (i, s) in _plans[b]!.where((s) => s.key != null).indexed)
        FloorSection(
          id: SellIds.section(b, s.key!),
          orgId: SeedIds.sabahOrg,
          branchId: MockSeed.branchIdOf(b),
          name: s.name,
          ordering: i,
          canvasW: 1000,
          canvasH: 700,
          createdAt: _layoutCreated,
          updatedAt: _layoutUpdated,
        ),
  ];

  /// (branch key, section, table) in plan order.
  late final List<(String, _S, _T)> _layout = [
    for (final b in _plans.keys)
      for (final s in _plans[b]!)
        for (final t in s.tables) (b, s, t),
  ];

  // Bookings.

  late final List<BookingView> bookings = _buildBookings();

  List<BookingView> _buildBookings() {
    final out = <BookingView>[];
    final customers = _core.customers;
    // (table id, day) -> windows already booked, for the assignment.
    final taken = <String, List<(DateTime, DateTime)>>{};

    BookingView make({
      required String branchKey,
      required String date,
      required int n,
      required int hour,
      required int minute,
      required int party,
      required String status,
      int? customer,
      String? guest,
      List<String>? tables,
      bool needsTable = false,
      String source = 'host',
      String? notes,
      int duration = _defaultDuration,
      MockRandom? rng,
    }) {
      final starts = _at(date, hour, minute);
      final ends = starts.add(Duration(minutes: duration));
      final c = customer == null ? null : customers[customer];
      final name = c?.name ?? guest ?? '';
      final phone = c?.phone ?? _guestPhone(rng ?? MockRandom('g:$n'));
      final branchId = MockSeed.branchIdOf(branchKey);
      final branchTables = [
        for (final (b, _, t) in _layout)
          if (b == branchKey && t.active) t,
      ]..sort((a, b) => a.seats.compareTo(b.seats));
      var picked = tables;
      if (picked == null && !needsTable) {
        for (final t in branchTables) {
          if (t.seats < party) continue;
          final id = SellIds.table(branchKey, t.label);
          final windows = taken[id] ?? const [];
          final clash = windows.any(
            (w) => w.$1.isBefore(ends) && starts.isBefore(w.$2),
          );
          if (!clash) {
            picked = [t.label];
            break;
          }
        }
      }
      final labels = picked ?? const <String>[];
      final ids = [for (final l in labels) SellIds.table(branchKey, l)];
      if (isActive(status)) {
        for (final id in ids) {
          (taken[id] ??= []).add((starts, ends));
        }
      }
      final created = starts.subtract(
        Duration(days: 1 + (n % 4), hours: 2 + (n % 5)),
      );
      final booked = created.isAfter(now)
          ? now.subtract(const Duration(hours: 1))
          : created;
      return BookingView(
        id: SellIds.booking(branchKey, date, n),
        branchId: branchId,
        customerId: c?.id,
        guestName: name,
        guestPhone: canonicalPhone(phone) ?? phone,
        locale: c?.locale ?? 'ar',
        partySize: party,
        startsAt: starts,
        endsAt: ends,
        heldFrom: starts.subtract(const Duration(minutes: _holdMinutes)),
        status: status,
        source: source,
        phoneVerified: source == 'public',
        needsTable: labels.isEmpty,
        tableIds: ids,
        tableLabels: labels,
        notes: notes,
        createdAt: booked,
        updatedAt: booked,
        createdBy: source == 'host'
            ? SeedIds.user(branchManagers[branchKey]!)
            : null,
        seatedAt: status == 'seated' || status == 'completed'
            ? starts.add(const Duration(minutes: 2))
            : null,
        completedAt: status == 'completed'
            ? ends.subtract(const Duration(minutes: 10))
            : null,
        noShowAt: status == 'no_show'
            ? starts.add(const Duration(minutes: 20))
            : null,
        cancelledAt: status == 'cancelled'
            ? starts.subtract(const Duration(hours: 5))
            : null,
        openTicketId: status == 'seated' && labels.isNotEmpty
            ? SellIds.ticket(branchKey, labels.first)
            : null,
      );
    }

    final today = _today;
    // Heliopolis today: every state the bookings page and the floor read.
    out.addAll([
      make(
        branchKey: 'heliopolis',
        date: today,
        n: 1,
        hour: 9,
        minute: 0,
        party: 2,
        status: 'completed',
        customer: 21,
        tables: const ['T4'],
        duration: 60,
      ),
      make(
        branchKey: 'heliopolis',
        date: today,
        n: 2,
        hour: 9,
        minute: 30,
        party: 3,
        status: 'seated',
        customer: 0,
        tables: const ['T1'],
        notes: 'Birthday — bring the candle with the cake.',
      ),
      make(
        branchKey: 'heliopolis',
        date: today,
        n: 3,
        hour: 9,
        minute: 45,
        party: 2,
        status: 'confirmed',
        customer: 5,
        tables: const ['T3'],
      ),
      make(
        branchKey: 'heliopolis',
        date: today,
        n: 4,
        hour: 10,
        minute: 15,
        party: 4,
        status: 'confirmed',
        customer: 9,
        tables: const ['T6'],
        source: 'public',
      ),
      make(
        branchKey: 'heliopolis',
        date: today,
        n: 5,
        hour: 13,
        minute: 0,
        party: 6,
        status: 'confirmed',
        guest: 'Mostafa Hegazy',
        needsTable: true,
        notes: 'Business lunch, needs a quiet corner.',
      ),
      make(
        branchKey: 'heliopolis',
        date: today,
        n: 6,
        hour: 19,
        minute: 30,
        party: 2,
        status: 'confirmed',
        customer: 14,
        source: 'public',
        notes: 'Window seat if possible.',
      ),
      make(
        branchKey: 'heliopolis',
        date: today,
        n: 7,
        hour: 20,
        minute: 0,
        party: 4,
        status: 'cancelled',
        customer: 30,
      ),
    ]);

    // Every branch, three days back and three ahead (Heliopolis today is the
    // hand-made day above).
    for (final b in _plans.keys) {
      for (var d = -3; d <= 3; d++) {
        if (b == 'heliopolis' && d == 0) continue;
        final date = _dayOffset(today, d);
        final rng = MockRandom('sell-bookings:$b:$date');
        final count = d < 0 ? rng.range(3, 5) : rng.range(2, 4);
        final slots = <int>{};
        for (var n = 1; n <= count; n++) {
          // 12:00 … 21:00 on the half hour (today: after now).
          int slot;
          do {
            slot = rng.range(d == 0 ? 25 : 24, 42);
          } while (!slots.add(slot));
          final hour = slot ~/ 2;
          final minute = slot.isOdd ? 30 : 0;
          final status = d < 0
              ? rng.weighted(
                  const ['completed', 'no_show', 'cancelled'],
                  const [14, 3, 3],
                )
              : (rng.chance(0.12) ? 'cancelled' : 'confirmed');
          final regular = rng.chance(0.7);
          out.add(
            make(
              branchKey: b,
              date: date,
              n: n,
              hour: hour,
              minute: minute,
              party: rng.weighted(const [2, 3, 4, 5, 6], const [9, 4, 6, 2, 2]),
              status: status,
              customer: regular ? rng.nextInt(40) : null,
              guest: regular
                  ? null
                  : '${rng.pick(seedFirstNames)} ${rng.pick(seedLastNames)}',
              source: rng.chance(0.3) ? 'public' : 'host',
              rng: rng,
            ),
          );
        }
      }
    }
    out.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return List.unmodifiable(out);
  }

  static bool isActive(String status) =>
      status == 'confirmed' || status == 'seated';

  static String _guestPhone(MockRandom rng) =>
      '01${rng.pick(const ['0', '1', '2', '5'])}'
      '${List.generate(8, (_) => rng.nextInt(10)).join()}';

  /// A table's next active booking within the day ahead (the backend's
  /// `next_booking`: ends after now, starts within 24 h, earliest first).
  TableBookingHint? _nextBookingOf(String tableId) {
    final limit = now.add(const Duration(hours: 24));
    for (final b in bookings) {
      if (!isActive(b.status) || !b.tableIds.contains(tableId)) continue;
      if (!b.endsAt.isAfter(now) || !b.startsAt.isBefore(limit)) continue;
      return TableBookingHint(
        bookingId: b.id,
        status: b.status,
        guestName: b.guestName,
        partySize: b.partySize,
        startsAt: b.startsAt,
        endsAt: b.endsAt,
        heldFrom: b.heldFrom,
      );
    }
    return null;
  }

  // Booking settings.

  late final List<BookingSettings> bookingSettings = [
    for (final b in _plans.keys)
      BookingSettings(
        branchId: MockSeed.branchIdOf(b),
        enabled: b != 'zamalek',
        requireOtp: b == 'heliopolis',
        slotMinutes: b == 'new-cairo' ? 15 : 30,
        defaultDurationMinutes: _defaultDuration,
        minParty: 1,
        maxParty: 8,
        leadTimeMinutes: 60,
        horizonDays: 30,
        holdMinutes: _holdMinutes,
        autoNoShowMinutes: b == 'maadi' ? null : 20,
        reminderLeadMinutes: b == 'new-cairo' ? null : 120,
        maxCoversPerSlot: b == 'heliopolis' ? 16 : null,
        blackoutDates: b == 'heliopolis'
            ? const ['2026-10-31']
            : const <String>[],
        hours: [
          for (var dow = 0; dow < 7; dow++)
            // Friday opens after prayers and runs past midnight.
            dow == 5
                ? const HoursEntry(dow: 5, open: '13:00', close: '01:00')
                : HoursEntry(dow: dow, open: '09:00', close: '23:00'),
        ],
      ),
  ];

  // Open tickets.

  late final List<OpenTicketView> openTickets = [
    for (final (i, (b, label, h, m, customer, guests, ready)) in _seated.indexed)
      _ticket(i, b, label, h, m, customer, guests, ready),
  ];

  OpenTicketView _ticket(
    int i,
    String branchKey,
    String label,
    int hour,
    int minute,
    int? customer,
    int guests,
    bool ready,
  ) {
    final opened = _at(_today, hour, minute);
    final c = customer == null ? null : _core.customers[customer];
    final id = SellIds.ticket(branchKey, label);
    final rng = MockRandom('sell-ticket:$branchKey:$label');
    final waiter = branchKey == 'zamalek';
    final openedBy = waiter
        ? 'laila'
        : branchTellers[branchKey]!.first;
    final items = <OpenTicketItemView>[];
    var subtotal = 0;
    final rounds = guests > 2 ? 2 : 1;
    for (var r = 1; r <= rounds; r++) {
      for (var k = 0; k < guests; k++) {
        final item = rng.pick(seedMenu);
        final (size, egp) = item.sizes.first;
        final total = egp * 100;
        subtotal += total;
        items.add(
          OpenTicketItemView(
            id: mockUuid('open-ticket-item:$id:$r:$k'),
            menuItemId: MockSeed.menuItemId(item.key),
            roundNumber: r,
            roundFiredAt: opened.add(Duration(minutes: (r - 1) * 25 + 1)),
            lineTotal: total,
            voided: false,
            line: {
              'item_name': item.name,
              'name_translations': {'en': item.name, 'ar': item.ar},
              'size_label': item.sizes.length > 1 ? size : null,
              'quantity': 1,
              'unit_price': total,
              'line_total': total,
            },
          ),
        );
      }
    }
    final tax = (subtotal * 14 / 114).round();
    final date = _today.substring(2).replaceAll('-', '');
    final code = seedBranches.firstWhere((s) => s.key == branchKey).code;
    return OpenTicketView(
      id: id,
      branchId: MockSeed.branchIdOf(branchKey),
      tableId: SellIds.table(branchKey, label),
      ticketRef: 'T-$code-$date-${(i + 1).toString().padLeft(4, '0')}',
      status: ready ? 'ready' : 'open',
      ready: ready,
      readyAt: ready ? opened.add(const Duration(minutes: 14)) : null,
      openedAt: opened,
      openedBy: SeedIds.user(openedBy),
      openedByName: sabahStaff.firstWhere((p) => p.key == openedBy).name,
      customerId: c?.id,
      customerName: c?.name,
      guestCount: guests,
      bookingId: branchKey == 'heliopolis' && label == 'T1'
          ? SellIds.nadaBooking
          : null,
      items: items,
      subtotal: subtotal,
      bill: TicketBill(
        subtotal: subtotal,
        discountAmount: 0,
        serviceChargeAmount: 0,
        serviceChargeRate: 0,
        taxAmount: tax,
        taxInclusive: true,
        taxRate: MockSeed.taxRate,
        total: subtotal,
      ),
      timezone: MockClock.timezone,
    );
  }

  // Tables (status and next booking derived from the rest).

  late final List<FloorTable> tables = [
    for (final (i, (b, s, t)) in _layout.indexed) _table(i, b, s, t),
  ];

  FloorTable _table(int i, String branchKey, _S section, _T t) {
    final id = SellIds.table(branchKey, t.label);
    // A tidy grid per section: three to a row, 180 × 140 apart; tables
    // without a section stand by the counter.
    final inSection = section.tables.indexOf(t);
    final col = inSection % 3;
    final row = inSection ~/ 3;
    final (w, h) = switch ((t.shape, t.seats)) {
      ('circle', _) => (90.0, 90.0),
      (_, 6) => (160.0, 90.0),
      (_, 8) => (200.0, 100.0),
      _ => (120.0, 80.0),
    };
    OpenTicketView? ticket;
    for (final k in openTickets) {
      if (k.tableId == id) ticket = k;
    }
    final parked = _parked.contains((branchKey, t.label));
    final dirty = _dirty.contains((branchKey, t.label));
    final status = ticket != null || parked
        ? 'seated'
        : (dirty ? 'dirty' : 'free');
    final seatedAt =
        ticket?.openedAt ??
        (parked ? _at(_today, 9, 20) : null);
    return FloorTable(
      id: id,
      orgId: SeedIds.sabahOrg,
      branchId: MockSeed.branchIdOf(branchKey),
      sectionId: section.key == null
          ? null
          : SellIds.section(branchKey, section.key!),
      label: t.label,
      seats: t.seats,
      shape: t.shape,
      posX: section.key == null ? 620.0 : 40.0 + col * 180,
      posY: section.key == null ? 420.0 : 40.0 + row * 140,
      width: w,
      height: h,
      rotation: t.rotation,
      isActive: t.active,
      status: status,
      seatedAt: seatedAt,
      partySize: ticket?.guestCount ?? (parked ? 3 : null),
      nextBooking: _nextBookingOf(id),
      createdAt: _layoutCreated,
      updatedAt: seatedAt ?? _layoutUpdated.add(Duration(minutes: i)),
    );
  }

  // Transfers.

  late final List<TransferView> transfers = [
    TransferView(
      id: SellIds.transfer('heliopolis', 1),
      branchId: SeedIds.heliopolis,
      occupantKind: 'open_ticket',
      occupantId: SellIds.ticket('heliopolis', 'T2'),
      occupantLabel: null,
      fromTableId: SellIds.table('heliopolis', 'T2'),
      targetSectionId: SellIds.section('heliopolis', 'terrace'),
      note: 'They would like to sit outside now that it is cooler.',
      status: 'waiting',
      requestedBy: SeedIds.user(branchTellers['heliopolis']!.first),
      createdAt: _at(_today, 9, 48),
      updatedAt: _at(_today, 9, 48),
    ),
    TransferView(
      id: SellIds.transfer('heliopolis', 2),
      branchId: SeedIds.heliopolis,
      occupantKind: 'open_ticket',
      occupantId: SellIds.ticket('heliopolis', 'T1'),
      occupantLabel: _core.customers[0].name,
      fromTableId: SellIds.table('heliopolis', 'T1'),
      targetTableId: SellIds.table('heliopolis', 'T5'),
      note: 'Two more friends are joining.',
      status: 'waiting',
      requestedBy: SeedIds.user(branchTellers['heliopolis']!.first),
      createdAt: _at(_today, 9, 55),
      updatedAt: _at(_today, 9, 55),
    ),
    TransferView(
      id: SellIds.transfer('heliopolis', 3),
      branchId: SeedIds.heliopolis,
      occupantKind: 'open_ticket',
      occupantId: SellIds.ticket('heliopolis', 'T2'),
      fromTableId: SellIds.table('heliopolis', 'T7'),
      fulfilledTableId: SellIds.table('heliopolis', 'T2'),
      status: 'fulfilled',
      requestedBy: SeedIds.user(branchTellers['heliopolis']!.first),
      resolvedAt: _at(_today, 7, 20),
      createdAt: _at(_today, 7, 12),
      updatedAt: _at(_today, 7, 20),
    ),
    TransferView(
      id: SellIds.transfer('zamalek', 1),
      branchId: SeedIds.zamalek,
      occupantKind: 'open_ticket',
      occupantId: SellIds.ticket('zamalek', 'T1'),
      occupantLabel: _core.customers[12].name,
      fromTableId: SellIds.table('zamalek', 'T1'),
      status: 'waiting',
      requestedBy: SeedIds.user('laila'),
      createdAt: _at(_today, 9, 41),
      updatedAt: _at(_today, 9, 41),
    ),
  ];

  /// Copies the seed into [db] (see [SellTables]).
  void loadInto(MockDb db) {
    db.table(SellTables.floorSections).insertAll([
      for (final s in sections) s.toJson(),
    ]);
    db.table(SellTables.floorTables).insertAll([
      for (final t in tables) t.toJson(),
    ]);
    db.table(SellTables.bookings).insertAll([
      for (final b in bookings) b.toJson(),
    ]);
    final settings = db.table(SellTables.bookingSettings);
    for (final s in bookingSettings) {
      settings.put(s.toJson());
    }
    db.table(SellTables.openTickets).insertAll([
      for (final k in openTickets) k.toJson(),
    ]);
    db.table(SellTables.floorTransfers).insertAll([
      for (final tr in transfers) tr.toJson(),
    ]);
  }
}
