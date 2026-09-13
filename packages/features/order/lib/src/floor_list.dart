// The floor as a LIST, beside the floor as a plan.
//
// A scale drawing is the right tool for "where is that table" and the wrong
// one for everything else. It fits a whole room into a phone, so a thirty-table
// floor renders each table as an unreadable rectangle; and it is silent —
// tables are drawn, not described, so a teller has to open each one to learn
// how long a party has been sitting, what their bill is, or whether the kitchen
// has their food.
//
// This is the same room, sorted by what needs a person. Every row answers the
// questions the plan makes you tap to ask.
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// What a row is waiting on, which is also how the list is ordered.
///
/// The order is deliberate: a list exists to be worked down. Anything that owes
/// the room work comes first, anything merely occupied is next, and a free
/// table — the thing you scan for, not the thing you act on — is last.
enum FloorUrgency {
  /// Paid, plates still there. The only state that owes the room work.
  needsClearing,

  /// The kitchen says the food is up.
  foodReady,

  /// Somebody is sitting there.
  seated,

  /// Kept for a booked party who has not arrived.
  reserved,

  /// Nobody there.
  free,
}

/// One row's worth of truth about a table.
@immutable
class FloorRow {
  const FloorRow({
    required this.table,
    required this.ticket,
    required this.urgency,
    required this.sectionName,
  });

  final FloorTableStateView table;
  final TicketView? ticket;
  final FloorUrgency urgency;
  final String? sectionName;

  /// How long the party has been sitting, or null when nobody is.
  Duration? seatedFor(DateTime now) => FloorTableModel.seatedForOf(
    table,
    ticket,
    now,
    occupied:
        urgency == FloorUrgency.seated || urgency == FloorUrgency.foodReady,
  );

  /// The table's whole state, for a row, a sheet or an inspector.
  FloorTableModel get model => FloorTableModel(table: table, ticket: ticket);
}

/// Everything a surface needs to say about one table — status, clock,
/// covers, server, bill total, ready — and what can be done with it. The
/// floor's sheets read this today; an inspector panel reads the same thing.
@immutable
class FloorTableModel {
  const FloorTableModel({required this.table, required this.ticket, this.now});

  final FloorTableStateView table;

  /// The live bill on the table, if this device knows one.
  final TicketView? ticket;

  /// The clock the model is read at (null = the wall clock).
  final DateTime? now;

  FloorUrgency get urgency => urgencyOf(table, ticket, now: now);

  /// A party is here: a bill, a parked draft, a seated table or a seated
  /// booking. The bill-less cases are the ones a stale ticket list hides.
  bool get occupied =>
      urgency == FloorUrgency.seated || urgency == FloorUrgency.foodReady;

  bool get hasBill => ticket != null;

  /// The kitchen has plated the whole bill.
  bool get ready => ticket?.ready ?? false;

  /// RFC3339: when the party sat. See [seatedForOf].
  String? get seatedAt => occupied ? _sinceOf(table, ticket) : null;

  Duration? seatedFor(DateTime at) =>
      seatedForOf(table, ticket, at, occupied: occupied);

  /// Covers: the host's count on the table, else the bill's guest count.
  int? get covers {
    final n = table.covers ?? ticket?.guestCount;
    return (n != null && n > 0) ? n : null;
  }

  String? get server {
    final w = ticket?.waiterName?.trim();
    return (w == null || w.isEmpty) ? null : w;
  }

  /// What the party owes: the server-priced total, else (a queued fire) the
  /// running subtotal. Null with no bill or nothing on it.
  int? get billTotalMinor {
    final t = ticket;
    if (t == null) return null;
    final v = t.bill?.totalMinor ?? t.subtotalMinor;
    return v > 0 ? v : null;
  }

  /// What can be done with this table right now, most likely first.
  /// [canCharge]: this shell takes money.
  List<FloorAction> actions({required bool canCharge}) => switch (urgency) {
    FloorUrgency.needsClearing => const [
      FloorAction.cleared,
      FloorAction.history,
    ],
    FloorUrgency.reserved => const [
      FloorAction.seatBooking,
      FloorAction.noShow,
      FloorAction.walkIn,
      FloorAction.history,
    ],
    FloorUrgency.free => const [FloorAction.seat, FloorAction.history],
    FloorUrgency.seated || FloorUrgency.foodReady => [
      if (hasBill) ...[
        if (canCharge) FloorAction.charge,
        FloorAction.addRound,
        FloorAction.move,
        FloorAction.openBill,
        FloorAction.voidBill,
      ] else ...[
        FloorAction.takeOrder,
        FloorAction.move,
        FloorAction.unseat,
        // A bill this device has not heard of yet (the list is stale or
        // offline) is still reachable: the door re-reads the bills.
        FloorAction.openBill,
      ],
      FloorAction.history,
    ],
  };

  /// Seating clock, best source first: the table's own seated stamp (the
  /// server's occupancy, or this device's seating), a parked order's start,
  /// then the bill's opening.
  static String? _sinceOf(FloorTableStateView t, TicketView? ticket) {
    for (final s in [t.seatedAt, t.heldSince, ticket?.openedAt]) {
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  static Duration? seatedForOf(
    FloorTableStateView t,
    TicketView? ticket,
    DateTime now, {
    required bool occupied,
  }) {
    if (!occupied) return null;
    final since = DateTime.tryParse(_sinceOf(t, ticket) ?? '');
    if (since == null) return null;
    final d = now.difference(since.toLocal());
    return d.isNegative ? Duration.zero : d;
  }
}

/// A thing a person can do with a table.
enum FloorAction {
  seat,
  takeOrder,
  openBill,
  charge,
  addRound,
  move,
  unseat,
  cleared,
  seatBooking,
  noShow,
  walkIn,
  voidBill,
  history,
}

/// The tables that owe the room a person right now, worst first: food up,
/// plates to clear, a party waiting past [longWait], a booking whose hold has
/// begun. [rows] come sorted by [buildFloorRows]; the order is kept.
List<FloorRow> needsAttention(
  List<FloorRow> rows, {
  required DateTime now,
  Duration longWait = const Duration(minutes: 45),
}) => [
  for (final r in rows)
    if (r.urgency == FloorUrgency.foodReady ||
        r.urgency == FloorUrgency.needsClearing ||
        r.urgency == FloorUrgency.reserved ||
        (r.urgency == FloorUrgency.seated &&
            (r.seatedFor(now) ?? Duration.zero) >= longWait))
      r,
];

/// Sort the room into a worklist.
///
/// Within a band, the longest-waiting comes first: of two seated tables the one
/// that has been there an hour needs looking at before the one seated two
/// minutes ago. Free tables fall back to their label, because there the
/// question really is "where is table 6".
List<FloorRow> buildFloorRows({
  required List<FloorTableStateView> tables,
  required TicketView? Function(String tableId) ticketOn,
  required String? Function(String? sectionId) sectionName,
  required DateTime now,
}) {
  final rows = <FloorRow>[];
  for (final t in tables) {
    final ticket = ticketOn(t.id);
    final urgency = urgencyOf(t, ticket, now: now);
    rows.add(
      FloorRow(
        table: t,
        ticket: ticket,
        urgency: urgency,
        sectionName: sectionName(t.sectionId),
      ),
    );
  }
  rows.sort((a, b) {
    final byBand = a.urgency.index.compareTo(b.urgency.index);
    if (byBand != 0) return byBand;
    if (a.urgency == FloorUrgency.free || a.urgency == FloorUrgency.reserved) {
      return _naturalLabel(
        a.table.label,
      ).compareTo(_naturalLabel(b.table.label));
    }
    // Longest first, by when the party SAT — the same clock the row shows. A
    // party with no clock yet sorts after every timed one, not before them.
    final ad = a.seatedFor(now);
    final bd = b.seatedFor(now);
    if (ad != null || bd != null) {
      if (ad == null) return 1;
      if (bd == null) return -1;
      final byAge = bd.compareTo(ad);
      if (byAge != 0) return byAge;
    }
    return _naturalLabel(a.table.label).compareTo(_naturalLabel(b.table.label));
  });
  return rows;
}

/// One visit to the table: what arrived, and when.
class BillRound {
  const BillRound({
    required this.number,
    required this.firedAt,
    required this.lines,
  });

  /// 1 for the round that opened the bill.
  final int number;

  /// RFC3339, as the core handed it over. Empty when the round has not synced
  /// back yet — the caller shows no clock rather than an invented one.
  final String firedAt;

  final List<TicketLineView> lines;
}

/// Group a bill's lines into the rounds they arrived on, in order.
///
/// The lines come back already sorted by round, so this only has to notice
/// where one round ends and the next begins.
List<BillRound> groupBillByRound(List<TicketLineView> lines) {
  final out = <BillRound>[];
  for (final line in lines) {
    final last = out.isEmpty ? null : out.last;
    if (last == null || last.number != line.roundNumber) {
      out.add(
        BillRound(
          number: line.roundNumber,
          firedAt: line.roundFiredAt,
          lines: [line],
        ),
      );
    } else {
      last.lines.add(line);
    }
  }
  return out;
}

/// A ticket that is still somebody's live bill.
///
/// `queued` belongs here: a round fired with no network is a real bill on a
/// real table, and every "is anyone there" check that looked only for `open`
/// read the table it had just taken as empty. Whether the kitchen is done is
/// [TicketView.ready]; a `ready` status only survives in an old cache, and it
/// is still a live bill.
bool isLiveTicket(TicketView t) =>
    t.status == 'open' || t.status == 'queued' || t.status == 'ready';

/// Where a table sits in the worklist.
FloorUrgency urgencyOf(
  FloorTableStateView t,
  TicketView? ticket, {
  DateTime? now,
}) {
  // A live occupant outranks a stored `dirty`. That can happen honestly — a
  // party seated onto a table the last one left dirty — and telling a teller to
  // bus an occupied table would have them clear people who are still eating.
  if (ticket != null) {
    return ticket.ready ? FloorUrgency.foodReady : FloorUrgency.seated;
  }
  // A PARKED DRAFT occupies a table with no ticket on it: the cart's Hold
  // button parks an order against its table. Reading that as free would offer
  // the table to a second party while somebody's order waits on it.
  if (t.heldOrderId != null) return FloorUrgency.seated;
  // And a draft parked on ANOTHER till occupies it just as firmly. That till
  // pushes the occupancy without the order, so the table arrives here `seated`
  // with no ticket and no draft this device can see — which is exactly what
  // the two checks above would read as an empty table.
  if (t.status == 'seated') return FloorUrgency.seated;
  // A booked party the host has seated is a party at the table.
  if (t.bookingId != null && t.bookingStatus == 'seated') {
    return FloorUrgency.seated;
  }
  if (t.status == 'dirty') return FloorUrgency.needsClearing;
  // Reserved only once the booking's hold has begun — the same clock rule the
  // plan draws by. A booking for tonight does not make a table taken at noon.
  if (t.bookingId != null && t.bookingStatus == 'confirmed') {
    final from = DateTime.tryParse(t.bookingHeldFrom ?? '');
    if (from != null && !from.isAfter(now ?? DateTime.now())) {
      return FloorUrgency.reserved;
    }
  }
  return FloorUrgency.free;
}

/// "T10" must sort after "T9", not between "T1" and "T2".
///
/// Table labels are overwhelmingly a prefix and a number, and a plain string
/// sort puts T10 second in a room that goes up to T12 — which reads as a bug
/// every single time somebody looks for a table.
String _naturalLabel(String label) {
  final m = RegExp(r'^(\D*)(\d+)(.*)$').firstMatch(label.trim());
  if (m == null) return label.toLowerCase();
  final prefix = (m.group(1) ?? '').toLowerCase();
  final digits = (m.group(2) ?? '').padLeft(6, '0');
  return '$prefix$digits${(m.group(3) ?? '').toLowerCase()}';
}

/// `1h 05m`, `42m`, `just now` — a duration a person reads at a glance.
///
/// Deliberately coarse. Seconds are noise on a floor, and the difference
/// between 41 and 42 minutes changes nothing anybody does.
///
/// [units] are the language's short hour/minute letters (`h`/`m`, `س`/`د`) —
/// pass [DurationUnits.of] from a screen; the Latin default is for tests.
String formatSeatedFor(
  Duration d, {
  DurationUnits units = DurationUnits.latin,
}) {
  final (h, m) = (units.hour, units.minute);
  if (d.inMinutes < 1) return '0$m';
  if (d.inHours < 1) return '${d.inMinutes}$m';
  final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${d.inHours}$h $mins$m';
}

/// The short hour / minute letters a clock figure carries, in the current
/// language. Resolved per build, so a language switch re-words every clock.
@immutable
class DurationUnits {
  const DurationUnits({required this.hour, required this.minute});

  factory DurationUnits.of(MadarBridge bridge) => DurationUnits(
    hour: bridge.tr(key: 'common.hours_short'),
    minute: bridge.tr(key: 'common.minutes_short'),
  );

  static const latin = DurationUnits(hour: 'h', minute: 'm');

  final String hour;
  final String minute;
}

/// The words this list needs, translated once by the caller.
///
/// Deliberately its own type rather than the canvas's `FloorListWords`: a
/// list says things a plan never has to — "the food is up", "4 guests" — and
/// borrowing that vocabulary would tie the two screens together for no gain.
@immutable
class FloorListWords {
  const FloorListWords({
    required this.free,
    required this.seated,
    required this.reserved,
    required this.needsClearing,
    required this.ready,
    required this.seats,
    required this.guests,
    this.units = DurationUnits.latin,
    this.cleared = 'Cleared',
    this.charge = 'Charge',
    this.seat = 'Seat',
  });

  factory FloorListWords.of(MadarBridge bridge) => FloorListWords(
    free: bridge.tr(key: 'tables.free'),
    seated: bridge.tr(key: 'tables.seated'),
    reserved: bridge.tr(key: 'tables.reserved'),
    needsClearing: bridge.tr(key: 'tables.needs_clearing'),
    ready: bridge.tr(key: 'ticket.status.ready'),
    seats: bridge.tr(key: 'tables.seats'),
    guests: bridge.tr(key: 'tables.guests'),
    units: DurationUnits.of(bridge),
    cleared: bridge.tr(key: 'floor.cleared'),
    charge: bridge.tr(key: 'sell.charge'),
    seat: bridge.tr(key: 'tables.seat_booking'),
  );

  /// A row's one-tap acts.
  final String cleared;
  final String charge;
  final String seat;

  /// The short hour/minute letters on a row's clock.
  final DurationUnits units;

  final String free;
  final String seated;
  final String reserved;
  final String needsClearing;
  final String ready;
  final String seats;
  final String guests;
}

// ── the list itself ──────────────────────────────────────────────────────────

/// The room as rows, in bands by what needs a person — Needs clearing, Ready,
/// Seated, Reserved, Free — each with its count. Every row answers without a
/// tap: how long, how many, whose, how much; the one-tap act for its state
/// (Cleared, Charge, Seat) sits on the row. The same tones as the plan.
class FloorListView extends StatelessWidget {
  const FloorListView({
    required this.rows,
    required this.now,
    required this.currency,
    required this.words,
    required this.onTap,
    required this.onLongPress,
    this.locale = 'en',
    this.canCharge = false,
    this.armedId,
    this.selectedId,
    this.onAction,
    super.key,
  });

  /// Sorted by [buildFloorRows]; the bands follow that order.
  final List<FloorRow> rows;
  final DateTime now;
  final String currency;
  final String locale;
  final FloorListWords words;
  final bool canCharge;
  final void Function(FloorTableStateView) onTap;
  final void Function(FloorTableStateView) onLongPress;

  /// The row's own act (Cleared, Charge, Seat this party); null hides it.
  final void Function(FloorAction action, FloorTableStateView table)? onAction;

  /// The table a move started from, so it reads as picked up.
  final String? armedId;

  /// The table the inspector shows.
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final bands = <FloorUrgency, List<FloorRow>>{};
    for (final r in rows) {
      (bands[r.urgency] ??= []).add(r);
    }
    final colors = context.madarColors;
    return ListView(
      padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
      children: [
        for (final (i, band) in bands.entries.indexed) ...[
          if (i > 0) const SizedBox(height: Space.xl),
          MadarSectionHeader(
            text: _statusWord(words, band.key),
            glyph: floorGlyphOf(band.key),
            trailing: Text(
              '${band.value.length}',
              textDirection: TextDirection.ltr,
              style: MadarType.numMd.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(height: Space.md),
          MadarCard(
            flush: true,
            child: Column(
              children: [
                for (final (j, r) in band.value.indexed) ...[
                  if (j > 0) const MadarHairline(light: true),
                  _row(r, colors),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(FloorRow r, MadarColors colors) {
    final seated = r.seatedFor(now);
    final model = r.model;
    final (FloorAction? act, String? label) = switch (r.urgency) {
      FloorUrgency.needsClearing => (FloorAction.cleared, words.cleared),
      FloorUrgency.foodReady when canCharge && r.ticket != null => (
        FloorAction.charge,
        words.charge,
      ),
      FloorUrgency.reserved => (FloorAction.seatBooking, words.seat),
      _ => (null, null),
    };
    final guest = (r.ticket?.customerName ?? r.table.heldOrderName)?.trim();
    final meta = <String>[
      if (seated != null)
        MadarFormat.ltr(MadarFormat.elapsed(seated, locale: locale)),
      if (model.covers case final n? when model.occupied)
        '$n ${words.guests}'
      else if (!model.occupied)
        '${r.table.seats} ${words.seats}',
      ?model.server,
      if (guest != null && guest.isNotEmpty) guest,
      if (r.urgency == FloorUrgency.reserved) ?r.table.bookingGuest,
    ];
    return Semantics(
      label: '${r.table.label} · ${_statusWord(words, r.urgency)}',
      child: MadarListRow.bill(
        key: ValueKey('floor.row.${r.table.id}'),
        title: r.table.label,
        meta: meta.join(' · '),
        minor: model.billTotalMinor,
        currency: currency,
        rail: _toneOf(r.urgency),
        // The plan's blue for a party, not the near-black accent.
        railColor: r.urgency == FloorUrgency.seated ? colors.info : null,
        selected: r.table.id == selectedId || r.table.id == armedId,
        ctaLabel: onAction == null ? null : label,
        onCta: onAction == null || act == null
            ? null
            : () => onAction!(act, r.table),
        onTap: () => onTap(r.table),
        chevron: false,
      ),
    );
  }
}

/// The state's glyph — the plan's, so a band, a chip and a table agree.
MadarGlyph floorGlyphOf(FloorUrgency u) => switch (u) {
  FloorUrgency.needsClearing => MadarGlyph.sparkle,
  FloorUrgency.foodReady => MadarGlyph.checkCircle,
  FloorUrgency.seated => MadarGlyph.users,
  FloorUrgency.reserved => MadarGlyph.calendar,
  FloorUrgency.free => MadarGlyph.hollow,
};

MadarTone _toneOf(FloorUrgency u) => switch (u) {
  FloorUrgency.needsClearing => MadarTone.danger,
  FloorUrgency.foodReady => MadarTone.success,
  FloorUrgency.seated => MadarTone.accent,
  FloorUrgency.reserved => MadarTone.warning,
  FloorUrgency.free => MadarTone.neutral,
};

String _statusWord(FloorListWords w, FloorUrgency u) => switch (u) {
  FloorUrgency.needsClearing => w.needsClearing,
  FloorUrgency.foodReady => w.ready,
  FloorUrgency.seated => w.seated,
  FloorUrgency.reserved => w.reserved,
  FloorUrgency.free => w.free,
};
