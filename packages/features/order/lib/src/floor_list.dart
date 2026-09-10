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
  Duration? seatedFor(DateTime now) {
    final t = ticket;
    if (t == null) return null;
    final opened = DateTime.tryParse(t.openedAt);
    if (opened == null) return null;
    final d = now.difference(opened.toLocal());
    return d.isNegative ? Duration.zero : d;
  }
}

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
    final urgency = _urgencyOf(t, ticket);
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
    // Longest first: `openedAt` is RFC3339, so the EARLIER string sorts first
    // and that is exactly the table that has been waiting longest.
    final ao = a.ticket?.openedAt ?? '';
    final bo = b.ticket?.openedAt ?? '';
    final byAge = ao.compareTo(bo);
    if (byAge != 0) return byAge;
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
/// real table, and every "is anyone there" check that looked only for
/// `open`/`ready` read the table it had just taken as empty.
bool isLiveTicket(TicketView t) =>
    t.status == 'open' || t.status == 'ready' || t.status == 'queued';

FloorUrgency _urgencyOf(FloorTableStateView t, TicketView? ticket) {
  // A live occupant outranks a stored `dirty`. That can happen honestly — a
  // party seated onto a table the last one left dirty — and telling a teller to
  // bus an occupied table would have them clear people who are still eating.
  if (ticket != null) {
    return ticket.status == 'ready'
        ? FloorUrgency.foodReady
        : FloorUrgency.seated;
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
  if (t.status == 'dirty') return FloorUrgency.needsClearing;
  if (t.bookingId != null) return FloorUrgency.reserved;
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
String formatSeatedFor(Duration d) {
  if (d.inMinutes < 1) return '0m';
  if (d.inHours < 1) return '${d.inMinutes}m';
  final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${d.inHours}h ${mins}m';
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
  });

  factory FloorListWords.of(MadarBridge bridge) => FloorListWords(
    free: bridge.tr(key: 'tables.free'),
    seated: bridge.tr(key: 'tables.seated'),
    reserved: bridge.tr(key: 'tables.reserved'),
    needsClearing: bridge.tr(key: 'tables.needs_clearing'),
    ready: bridge.tr(key: 'ticket.status.ready'),
    seats: bridge.tr(key: 'tables.seats'),
    guests: bridge.tr(key: 'tables.guests'),
  );

  final String free;
  final String seated;
  final String reserved;
  final String needsClearing;
  final String ready;
  final String seats;
  final String guests;
}

// ── the list itself ──────────────────────────────────────────────────────────

/// The room as rows, sorted by what needs a person.
///
/// Every row answers, without a tap: how long they have been sitting, what the
/// bill is so far, whose table it is, and whether the kitchen is waiting. The
/// plan can show none of that — it draws tables, it does not describe them.
class FloorListView extends StatelessWidget {
  const FloorListView({
    required this.rows,
    required this.now,
    required this.currency,
    required this.words,
    required this.onTap,
    required this.onLongPress,
    this.armedId,
    super.key,
  });

  final List<FloorRow> rows;
  final DateTime now;
  final String currency;
  final FloorListWords words;
  final void Function(FloorTableStateView) onTap;
  final void Function(FloorTableStateView) onLongPress;

  /// The table a move started from, so it reads as picked up.
  final String? armedId;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, i) => _FloorRowTile(
        row: rows[i],
        now: now,
        currency: currency,
        words: words,
        armed: rows[i].table.id == armedId,
        onTap: () => onTap(rows[i].table),
        onLongPress: () => onLongPress(rows[i].table),
      ),
    );
  }
}

class _FloorRowTile extends StatelessWidget {
  const _FloorRowTile({
    required this.row,
    required this.now,
    required this.currency,
    required this.words,
    required this.armed,
    required this.onTap,
    required this.onLongPress,
  });

  final FloorRow row;
  final DateTime now;
  final String currency;
  final FloorListWords words;
  final bool armed;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final tone = _toneOf(colors, row.urgency);
    final seated = row.seatedFor(now);
    final ticket = row.ticket;

    return Semantics(
      button: true,
      label: '${row.table.label} · ${_statusWord(words, row.urgency)}',
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Ink(
          decoration: BoxDecoration(
            color: armed ? tone.withValues(alpha: 0.12) : colors.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: armed ? tone : colors.borderLight,
              width: armed ? 2 : 1,
            ),
          ),
          padding: const EdgeInsetsDirectional.all(Space.md),
          child: Row(
            children: [
              // The state, as a bar rather than a word: colour is the fastest
              // thing to read across a list, and the word is still beside it.
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.table.label,
                            overflow: TextOverflow.ellipsis,
                            style: MadarType.h3.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (row.sectionName != null) ...[
                          const SizedBox(width: Space.sm),
                          Flexible(
                            child: Text(
                              row.sectionName!,
                              overflow: TextOverflow.ellipsis,
                              style: MadarType.label.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.body.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              // The two numbers a teller actually wants: how long, how much.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    seated == null
                        ? _statusWord(words, row.urgency)
                        : formatSeatedFor(seated),
                    style: MadarType.label.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (ticket != null && ticket.subtotalMinor > 0) ...[
                    const SizedBox(height: 2),
                    MoneyText(
                      ticket.subtotalMinor,
                      currency: currency,
                      style: MadarType.money.copyWith(fontSize: 14),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Who is there and what is happening, in one line.
  String _subtitle() {
    final t = row.ticket;
    if (t == null) {
      // Whose order is parked here, when a draft is what occupies the
      // table. Without it the row says "4 seats" about a table that is
      // plainly taken.
      final held = row.table.heldOrderName?.trim();
      if (held != null && held.isNotEmpty) return held;
      if (row.urgency == FloorUrgency.reserved) {
        return row.table.bookingGuest ?? words.reserved;
      }
      if (row.urgency == FloorUrgency.needsClearing) return words.needsClearing;
      return '${row.table.seats} ${words.seats}';
    }
    final parts = <String>[
      if (t.guestCount != null && t.guestCount! > 0)
        '${t.guestCount} ${words.guests}'
      else
        '${row.table.seats} ${words.seats}',
      if (t.customerName?.trim().isNotEmpty ?? false) t.customerName!.trim(),
      if (t.waiterName?.trim().isNotEmpty ?? false) t.waiterName!.trim(),
      if (t.ticketRef?.trim().isNotEmpty ?? false) t.ticketRef!.trim(),
    ];
    return parts.join(' · ');
  }
}

Color _toneOf(MadarColors colors, FloorUrgency u) => switch (u) {
  FloorUrgency.needsClearing => colors.danger,
  FloorUrgency.foodReady => colors.success,
  FloorUrgency.seated => colors.accent,
  FloorUrgency.reserved => colors.warning,
  FloorUrgency.free => colors.textMuted,
};

String _statusWord(FloorListWords w, FloorUrgency u) => switch (u) {
  FloorUrgency.needsClearing => w.needsClearing,
  FloorUrgency.foodReady => w.ready,
  FloorUrgency.seated => w.seated,
  FloorUrgency.reserved => w.reserved,
  FloorUrgency.free => w.free,
};
