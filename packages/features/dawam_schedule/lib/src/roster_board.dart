/// The manager's roster as a board: people down the side, the week across
/// the top (Saturday first), each day's shifts as small cards. The name
/// column and the day header stay put while the grid scrolls both ways
/// (two_dimensional_scrollables' TableView, pinned row and column). A tablet
/// sees the whole week; a phone sees about three days and snaps per day.
library;

import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:staff_core/staff_core.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

/// One row of the board: a person, or the open shifts (no [emp]).
@immutable
class RosterRow {
  const RosterRow({
    required this.emp,
    required this.name,
    required this.color,
    this.minutes = 0,
  });

  /// Null for the open-shifts row.
  final String? emp;
  final String name;
  final Color color;

  /// Rostered this week, leave taken out.
  final int minutes;
}

/// One column: a day, and what its header says.
@immutable
class RosterDay {
  const RosterDay(
    this.date, {
    this.today = false,
    this.holiday,
    this.staffed = 0,
    this.need,
  });

  final DateTime date;
  final bool today;

  /// A public holiday the owner set (RU-10), by name.
  final String? holiday;

  /// People on shift that day, and the most the coverage grid asks for at
  /// once (SC-13). No grid, no [need].
  final int staffed;
  final int? need;
}

/// One shift as the board shows it; the screen works out the words.
@immutable
class RosterCard {
  const RosterCard({
    required this.shift,
    required this.title,
    required this.window,
    required this.color,
    this.leave,
    this.half = false,
    this.changed = false,
    this.swap = false,
    this.claimed = false,
  });

  final Shift shift;

  /// The template's name, and its hours ("8 AM – 4 PM").
  final String title;
  final String window;

  /// The template's colour.
  final Color color;

  /// 'paid' | 'unpaid' when the person is on leave that day.
  final String? leave;
  final bool half;

  /// Changed after the week was published (SC-4).
  final bool changed;

  /// Part of a swap that waits for a colleague or the manager (SC-8).
  final bool swap;

  /// An open shift someone claimed (SC-9).
  final bool claimed;

  String get label => [
    if (leave == 'paid')
      tr('staff.paid_leave')
    else if (leave != null)
      tr('staff.unpaid_leave'),
    if (half) tr('staff.half_day'),
    title,
    window,
    if (changed) tr('staff.changed'),
    if (swap) tr('staff.swap_pending'),
    if (claimed) tr('staff.claimed'),
  ].join(' · ');
}

/// The card's height; a cell stacks its cards with [_gap] between.
const double _cardH = 46;
const double _gap = 4;
const double _pad = 3;

/// The week board. Every tap and drop goes back to the screen, which
/// sends the store's action.
class RosterBoard extends StatefulWidget {
  const RosterBoard({
    required this.rows,
    required this.days,
    required this.cardsAt,
    required this.onTapCard,
    required this.onTapEmpty,
    this.onDrop,
    this.focus = 0,
    super.key,
  });

  final List<RosterRow> rows;
  final List<RosterDay> days;
  final List<RosterCard> Function(String? emp, DateTime day) cardsAt;
  final void Function(Shift) onTapCard;
  final void Function(String? emp, DateTime day) onTapEmpty;

  /// A card dropped on another day of its row (a move) or on another row
  /// the same day (a reassignment). Null: no dragging.
  final void Function(Shift, String? emp, DateTime day)? onDrop;

  /// The day a phone scrolls to first (today, in this week).
  final int focus;

  @override
  State<RosterBoard> createState() => _RosterBoardState();
}

class _RosterBoardState extends State<RosterBoard> {
  final _h = ScrollController();
  double _dayW = 0;
  bool _fits = false;
  bool _focusPending = true;

  @override
  void didUpdateWidget(RosterBoard old) {
    super.didUpdateWidget(old);
    final week = widget.days.firstOrNull?.date;
    if (week != old.days.firstOrNull?.date || widget.focus != old.focus) {
      _focusPending = true;
    }
  }

  @override
  void dispose() {
    _h.dispose();
    super.dispose();
  }

  /// Scroll so [RosterBoard.focus] is the first day showing.
  void _jumpToFocus() {
    if (!_focusPending || !_h.hasClients) return;
    final p = _h.position;
    if (!p.hasContentDimensions) return;
    final target = widget.focus * _dayW;
    // Wait for a layout that can reach the day (the first frames of a tab
    // may lay the board out before it has its real width), unless the whole
    // week fits and there is nothing to scroll.
    if (target > p.maxScrollExtent + 1 && !_fits) return;
    _focusPending = false;
    _h.jumpTo(target.clamp(p.minScrollExtent, p.maxScrollExtent));
  }

  double _rowH(RosterRow r) {
    var n = 1;
    for (final d in widget.days) {
      n = math.max(n, widget.cardsAt(r.emp, d.date).length);
    }
    // +1: the cell's bottom hairline takes a pixel of its height.
    return math.max(60, _pad * 2 + n * _cardH + (n - 1) * _gap + 1);
  }

  @override
  Widget build(BuildContext context) {
    final phone = MadarLayout.of(context).isPhone;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final coverage = widget.days.any((d) => d.need != null);
    return LayoutBuilder(
      builder: (context, box) {
        final nameW = phone ? 92.0 : 184.0;
        final room = box.maxWidth - nameW;
        // The whole week where it fits roomily; else ~3 days a screen.
        _fits = room / 7 >= (phone ? 96 : 112);
        final dayW = _fits ? room / 7 : math.max(84, room / 3).toDouble();
        _dayW = dayW;
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToFocus());
        final headH = coverage ? 84.0 : 64.0;
        // A short roster ends where its last row does, not at the screen's
        // foot (+2 for the card's edge).
        final height = math.min(
          box.maxHeight,
          headH + widget.rows.fold(0.0, (a, r) => a + _rowH(r)) + 2,
        );
        final table = TableView.builder(
          pinnedRowCount: 1,
          pinnedColumnCount: 1,
          rowCount: widget.rows.length + 1,
          columnCount: widget.days.length + 1,
          horizontalDetails: ScrollableDetails(
            direction: rtl ? AxisDirection.left : AxisDirection.right,
            controller: _h,
            physics: _DaySnap(dayW),
          ),
          columnBuilder: (i) =>
              TableSpan(extent: FixedTableSpanExtent(i == 0 ? nameW : dayW)),
          rowBuilder: (i) => TableSpan(
            extent: FixedTableSpanExtent(
              i == 0 ? headH : _rowH(widget.rows[i - 1]),
            ),
          ),
          cellBuilder: (context, at) {
            if (at.row == 0) {
              return TableViewCell(
                child: at.column == 0
                    ? const _Corner()
                    : _DayHead(widget.days[at.column - 1], compact: phone),
              );
            }
            final row = widget.rows[at.row - 1];
            if (at.column == 0) {
              return TableViewCell(child: _NameCell(row, compact: phone));
            }
            final day = widget.days[at.column - 1];
            return TableViewCell(
              child: _Cell(
                row: row,
                day: day,
                cards: widget.cardsAt(row.emp, day.date),
                cardW: dayW - _pad * 2,
                onTapCard: widget.onTapCard,
                onTapEmpty: () => widget.onTapEmpty(row.emp, day.date),
                onDrop: widget.onDrop,
              ),
            );
          },
        );
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: height,
            child: MadarCard(flush: true, child: table),
          ),
        );
      },
    );
  }
}

/// Settles on a day's edge after a fling, as a pager settles on a page.
class _DaySnap extends ScrollPhysics {
  const _DaySnap(this.extent, {super.parent});

  final double extent;

  @override
  _DaySnap applyTo(ScrollPhysics? ancestor) =>
      _DaySnap(extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics p, double velocity) {
    if ((velocity <= 0 && p.pixels <= p.minScrollExtent) ||
        (velocity >= 0 && p.pixels >= p.maxScrollExtent) ||
        extent <= 0) {
      return super.createBallisticSimulation(p, velocity);
    }
    final t = toleranceFor(p);
    var day = p.pixels / extent;
    if (velocity < -t.velocity) {
      day -= 0.5;
    } else if (velocity > t.velocity) {
      day += 0.5;
    }
    final target = (day.roundToDouble() * extent).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if ((target - p.pixels).abs() < t.distance) return null;
    return ScrollSpringSimulation(
      spring,
      p.pixels,
      target,
      velocity,
      tolerance: t,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// The hairlines every cell draws on its end and bottom edges.
BoxDecoration _cellBox(MadarColors c, {Color? fill}) => BoxDecoration(
  color: fill ?? c.surface,
  border: BorderDirectional(
    end: BorderSide(color: c.borderLight),
    bottom: BorderSide(color: c.borderLight),
  ),
);

/// A day's wash: a set holiday, then today.
Color _dayFill(MadarColors c, RosterDay d) => d.holiday != null
    ? Color.alphaBlend(c.warningBg.withValues(alpha: 0.7), c.surface)
    : d.today
    ? Color.alphaBlend(c.accentBg.withValues(alpha: 0.45), c.surface)
    : c.surface;

class _Corner extends StatelessWidget {
  const _Corner();

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      decoration: _cellBox(c, fill: c.surfaceAlt),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.md),
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        tr('staff.team'),
        style: MadarType.label.copyWith(color: c.textSecondary),
      ),
    );
  }
}

class _DayHead extends StatelessWidget {
  const _DayHead(this.day, {required this.compact});

  final RosterDay day;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final need = day.need;
    final fill = day.holiday != null || day.today
        ? _dayFill(c, day)
        : c.surfaceAlt;
    return Semantics(
      label: [
        dayLabel(day.date),
        ?day.holiday,
        if (need != null)
          tr('staff.staffed_of_needed', {'n': day.staffed, 'need': need}),
      ].join(' · '),
      excludeSemantics: true,
      child: Container(
        decoration: _cellBox(c, fill: fill),
        padding: const EdgeInsets.symmetric(horizontal: _pad, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 3,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 3,
              children: [
                if (day.holiday != null)
                  MadarGlyphIcon(
                    MadarGlyph.flame,
                    size: IconSize.xs,
                    color: c.warning,
                  ),
                Flexible(
                  child: Text(
                    weekday(day.date.weekday),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.labelSm.copyWith(
                      color: day.today ? c.accentDeep : c.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: day.today ? c.accent : null,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${day.date.day}',
                style: MadarType.numMd.copyWith(
                  color: day.today ? c.textOnAccent : c.textPrimary,
                  height: 1,
                ),
              ),
            ),
            if (need != null) _Staffed(day.staffed, need),
          ],
        ),
      ),
    );
  }
}

/// "3/4": on shift against what the coverage grid asks.
class _Staffed extends StatelessWidget {
  const _Staffed(this.staffed, this.need);

  final int staffed;
  final int need;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final tone = staffed >= need ? MadarTone.success : MadarTone.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tone.tint(c),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          MadarGlyphIcon(MadarGlyph.users, size: 11, color: tone.color(c)),
          Text(
            '$staffed/$need',
            textDirection: TextDirection.ltr,
            style: MadarType.num.copyWith(
              fontSize: 11,
              color: tone.color(c),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The person's disc: their initial on their colour.
class RosterAvatar extends StatelessWidget {
  const RosterAvatar(this.row, {this.size = 30, super.key});

  final RosterRow row;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final open = row.emp == null;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: open ? c.warningBg : row.color,
        shape: BoxShape.circle,
      ),
      child: open
          ? MadarGlyphIcon(MadarGlyph.plus, size: size * 0.5, color: c.warning)
          : Text(
              row.name.characters.firstOrNull ?? '·',
              style: MadarType.label.copyWith(
                color: Colors.white,
                fontSize: size * 0.42,
              ),
            ),
    );
  }
}

/// Hours a row is rostered this week ("40h", "37.5h"): one figure, so it
/// fits a phone's name column.
String rosterHours(int minutes) => tr('staff.hours_short', {
  'h': minutes % 60 == 0
      ? '${minutes ~/ 60}'
      : (minutes / 60).toStringAsFixed(1),
});

class _NameCell extends StatelessWidget {
  const _NameCell(this.row, {required this.compact});

  final RosterRow row;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      decoration: _cellBox(c),
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: compact ? Space.sm : Space.md,
      ),
      child: Row(
        spacing: compact ? 6 : Space.sm,
        children: [
          // A phone's column is narrow: the colour as a bar, not a disc.
          if (compact)
            Container(
              width: 4,
              height: 28,
              decoration: BoxDecoration(
                color: row.emp == null ? c.warning : row.color,
                borderRadius: BorderRadius.circular(2),
              ),
            )
          else
            RosterAvatar(row),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  row.name,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: (compact ? MadarType.labelSm : MadarType.label)
                      .copyWith(
                        color: row.emp == null ? c.warning : c.textPrimary,
                        height: 1.25,
                      ),
                ),
                if (row.minutes > 0)
                  Text(
                    rosterHours(row.minutes),
                    maxLines: 1,
                    style: MadarType.num.copyWith(
                      fontSize: 11,
                      color: c.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A person's day: their cards, or "off" and a tap to add. A drop target
/// when the board allows dragging.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.row,
    required this.day,
    required this.cards,
    required this.cardW,
    required this.onTapCard,
    required this.onTapEmpty,
    required this.onDrop,
  });

  final RosterRow row;
  final RosterDay day;
  final List<RosterCard> cards;
  final double cardW;
  final void Function(Shift) onTapCard;
  final VoidCallback onTapEmpty;
  final void Function(Shift, String? emp, DateTime day)? onDrop;

  /// One change at a time: another day in the same row (a move), or another
  /// row the same day (a reassignment).
  bool _accepts(Shift s) => (s.emp == row.emp) != sameDay(s.date, day.date);

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    Widget content({required bool hover}) => Container(
      decoration: _cellBox(c, fill: _dayFill(c, day)),
      foregroundDecoration: hover
          ? BoxDecoration(
              border: Border.all(color: c.accent, width: 2),
              color: c.accent.withValues(alpha: 0.06),
            )
          : null,
      padding: const EdgeInsets.all(_pad),
      child: cards.isEmpty
          ? _Empty(open: row.emp == null, onTap: onTapEmpty)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: _gap,
              children: [
                for (final card in cards)
                  _draggable(context, card, ShiftCard(card, onTap: onTapCard)),
              ],
            ),
    );
    final drop = onDrop;
    if (drop == null) return content(hover: false);
    return DragTarget<Shift>(
      onWillAcceptWithDetails: (d) => _accepts(d.data),
      onAcceptWithDetails: (d) => drop(d.data, row.emp, day.date),
      builder: (context, candidates, _) =>
          content(hover: candidates.isNotEmpty),
    );
  }

  Widget _draggable(BuildContext context, RosterCard card, Widget child) {
    if (onDrop == null) return child;
    return _DragCard(card: card, width: cardW, child: child);
  }
}

/// A card that lifts on a long press. It fades in place rather than being
/// swapped for a stand-in, so the press that started the drag keeps its
/// widgets and ends cleanly.
class _DragCard extends StatefulWidget {
  const _DragCard({
    required this.card,
    required this.width,
    required this.child,
  });

  final RosterCard card;
  final double width;
  final Widget child;

  @override
  State<_DragCard> createState() => _DragCardState();
}

class _DragCardState extends State<_DragCard> {
  bool _lifted = false;

  void _set(bool v) {
    if (mounted && _lifted != v) setState(() => _lifted = v);
  }

  @override
  Widget build(BuildContext context) => LongPressDraggable<Shift>(
    data: widget.card.shift,
    onDragStarted: () => _set(true),
    onDragEnd: (_) => _set(false),
    feedback: Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: widget.width,
        child: Opacity(opacity: 0.92, child: ShiftCard(widget.card)),
      ),
    ),
    child: Opacity(opacity: _lifted ? 0.3 : 1, child: widget.child),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Semantics(
      button: true,
      label: tr('staff.add_shift'),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.xs),
        child: Center(
          child: open
              ? MadarGlyphIcon(
                  MadarGlyph.plus,
                  size: IconSize.sm,
                  color: c.textMuted,
                )
              : Text(
                  tr('staff.off'),
                  style: MadarType.labelSm.copyWith(color: c.textMuted),
                ),
        ),
      ),
    );
  }
}

/// A shift on the board: the template's colour on the start edge, its name
/// and hours; leave, a pending swap, a claim and a change after publishing
/// each say so with a glyph, never colour alone.
class ShiftCard extends StatelessWidget {
  const ShiftCard(this.card, {this.onTap, super.key});

  final RosterCard card;
  final void Function(Shift)? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final leave = card.leave;
    final hue = leave != null ? c.textMuted : card.color;
    final title = leave == null
        ? card.title
        : leave == 'paid'
        ? tr('staff.paid_leave')
        : tr('staff.unpaid_leave');
    final sub = leave == null
        ? card.window
        : card.half
        ? '${tr('staff.half_day')} · ${card.window}'
        : card.title;
    final tap = onTap;
    Widget out = Semantics(
      button: tap != null,
      label: card.label,
      excludeSemantics: true,
      child: Container(
        height: _cardH,
        padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 4, 4),
        decoration: BoxDecoration(
          color: leave != null
              ? c.surfaceAlt
              : Color.alphaBlend(hue.withValues(alpha: 0.13), c.surface),
          borderRadius: BorderRadius.circular(Radii.xs),
          border: BorderDirectional(start: BorderSide(color: hue, width: 3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 1,
          children: [
            Row(
              spacing: 3,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.labelSm.copyWith(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (card.swap)
                  MadarGlyphIcon(MadarGlyph.refresh, size: 12, color: c.info),
                if (card.claimed)
                  MadarGlyphIcon(MadarGlyph.user, size: 12, color: c.accent),
                if (card.changed)
                  MadarGlyphIcon(
                    MadarGlyph.alertCircle,
                    size: 12,
                    color: c.warning,
                  ),
              ],
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MadarType.labelSm.copyWith(
                color: c.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
    if (tap != null) {
      out = TactileScale(onTap: () => tap(card.shift), child: out);
    }
    return out;
  }
}

/// One day on a phone: every row as a line with its cards, for when three
/// narrow columns are too little.
class RosterDayList extends StatelessWidget {
  const RosterDayList({
    required this.rows,
    required this.day,
    required this.cardsAt,
    required this.onTapCard,
    required this.onTapEmpty,
    super.key,
  });

  final List<RosterRow> rows;
  final RosterDay day;
  final List<RosterCard> Function(String? emp, DateTime day) cardsAt;
  final void Function(Shift) onTapCard;
  final void Function(String? emp, DateTime day) onTapEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return ListView(
      children: [
        MadarCard.column(
          flush: true,
          children: [
            for (final (i, r) in rows.indexed) ...[
              if (i > 0) const MadarHairline(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                child: Row(
                  spacing: Space.md,
                  children: [
                    RosterAvatar(r),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MadarType.label.copyWith(
                              color: r.emp == null ? c.warning : c.textPrimary,
                            ),
                          ),
                          if (r.minutes > 0)
                            Text(
                              rosterHours(r.minutes),
                              style: MadarType.num.copyWith(
                                fontSize: 11,
                                color: c.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: 168, child: _dayCards(c, r)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _dayCards(MadarColors c, RosterRow r) {
    final cards = cardsAt(r.emp, day.date);
    if (cards.isEmpty) {
      return SizedBox(
        height: _cardH,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.xs),
          ),
          child: _Empty(
            open: r.emp == null,
            onTap: () => onTapEmpty(r.emp, day.date),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: _gap,
      children: [for (final card in cards) ShiftCard(card, onTap: onTapCard)],
    );
  }
}
