// ── The table glyph ──────────────────────────────────────────────────────────
//
// ONE drawing of a table, shared with the dashboard's canvas
// (`MadarDashboard/src/features/floor/table-glyph.tsx`). Every geometry
// constant here is in CANVAS UNITS — the units the dashboard authors in — and
// is multiplied by the live scale at paint time. Change a constant in one
// place, change it in the other.
//
// What a teller reads across a room, loudest first:
//   * READY — a green ring, a check, and (once, unless motion is reduced) a
//     pulse. The kitchen is waiting on the floor.
//   * NEEDS CLEARING — hatched, red ring, sparkle. The room owes work.
//   * A BILL — a stronger blue body with the amount and the clock on it; the
//     clock turns amber, then red, as the party waits.
//   * SEATED, no bill — a light blue body and the clock.
//   * RESERVED — an amber DASHED ring and whose table it is.
//   * FREE — a white body, a hairline, quiet chairs, and how many it seats.
// State never rests on colour alone: every state has a glyph or a texture.
import 'dart:async';
import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:feature_order/src/floor_list.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Rounded-rect corner radius (canvas units).
const double kTableCorner = 10;

/// Ring weights (canvas units): a free table's hairline, an occupied table's
/// ring, the ready ring, and the selection halo.
const double kTableRingFree = 1.5;
const double kTableRing = 2;
const double kTableRingReady = 3;
const double kTableRingSelected = 3;

/// How far the selection halo sits outside the body (canvas units).
const double kTableHaloGap = 5;

/// Body tint strength over the surface: seated with no bill, with a bill.
const double kTableFillSeated = 0.10;
const double kTableFillBill = 0.22;

/// Legacy name for the bill tint — the dashboard's `fillOpacity`.
const double kTableFillOpacity = kTableFillBill;

/// Reserved ring dash and gap (canvas units).
const double kTableDash = 6;
const double kTableDashGap = 4;

/// Type on a table (canvas units before the legibility clamps below).
const double kTableLabelSize = 18;
const double kTableChipSize = 12;

/// Minimum rendered sizes: a label never drops under 14px.
const double kTableLabelMinPx = 14;
const double kTableChipMinPx = 11;

/// A party waiting this long turns the clock amber, then red.
const int kTableLongWaitMinutes = 45;
const int kTableVeryLongWaitMinutes = 90;

/// A circle's content lives in its inscribed square: 1/√2 of the diameter.
const double kCircleSafe = 0.7071;

/// Past this many seats the rim turns into a smear — the count carries it.
const int kSeatRenderCap = 12;

/// The situation a glyph draws — a flat, testable reading of one table.
enum TableGlyphState {
  free,
  seated,
  bill,
  ready,
  needsClearing,
  reserved,
  held,
}

/// What one table looks like right now. Pure: no widgets, no clock reads.
TableGlyphState tableGlyphState(
  FloorTableStateView t,
  TicketView? ticket, {
  DateTime? now,
}) {
  switch (urgencyOf(t, ticket, now: now)) {
    case FloorUrgency.needsClearing:
      return TableGlyphState.needsClearing;
    case FloorUrgency.reserved:
      return TableGlyphState.reserved;
    case FloorUrgency.foodReady:
      return TableGlyphState.ready;
    case FloorUrgency.seated:
      return ticket != null ? TableGlyphState.bill : TableGlyphState.seated;
    case FloorUrgency.free:
      return t.status == 'held' ? TableGlyphState.held : TableGlyphState.free;
  }
}

/// The clock's tone: calm, then amber past [kTableLongWaitMinutes], then red
/// past [kTableVeryLongWaitMinutes].
MadarTone waitTone(Duration? seated) {
  final m = seated?.inMinutes ?? 0;
  if (m >= kTableVeryLongWaitMinutes) return MadarTone.danger;
  if (m >= kTableLongWaitMinutes) return MadarTone.warning;
  return MadarTone.neutral;
}

/// The state's colour — ring, chairs, tint. One per state.
Color glyphTone(MadarColors c, TableGlyphState s) => switch (s) {
  TableGlyphState.free => c.textMuted,
  TableGlyphState.seated || TableGlyphState.bill => c.info,
  TableGlyphState.ready => c.success,
  TableGlyphState.needsClearing => c.danger,
  TableGlyphState.reserved || TableGlyphState.held => c.warning,
};

/// The state's own glyph, so a table never says what it is by colour alone.
MadarGlyph? glyphIcon(TableGlyphState s) => switch (s) {
  TableGlyphState.free => null,
  TableGlyphState.seated || TableGlyphState.bill => MadarGlyph.users,
  TableGlyphState.ready => MadarGlyph.checkCircle,
  TableGlyphState.needsClearing => MadarGlyph.sparkle,
  TableGlyphState.reserved => MadarGlyph.calendar,
  TableGlyphState.held => MadarGlyph.lock,
};

/// How a table answers a move in progress.
enum TableMoveRole { none, source, target, refused }

/// One chair, in table-local canvas units (origin = the table's top-left).
typedef SeatSlot = ({double x, double y, double angle});

/// Chair capsule dimensions for a table of this size, in canvas units.
({double len, double thick, double gap}) seatMetrics(double w, double h) {
  final len = (math.min(w, h) * 0.26).clamp(10.0, 28.0);
  return (len: len, thick: len * 0.42, gap: 4);
}

/// Where the chairs go — the same algorithm as the dashboard's `seatSlots`.
///
/// People sit in PAIRS facing each other, so pairs are allocated to opposite
/// sides by side length and an odd seat goes to the HEAD of the table. Splitting
/// raw seat counts instead leaves a 6-top with 2 chairs on one side and 1 on
/// the other, which reads as a drawing mistake rather than a room.
List<SeatSlot> seatSlots(String shape, double w, double h, int seats) {
  if (seats <= 0 || seats > kSeatRenderCap) return const [];
  final m = seatMetrics(w, h);
  final out = <SeatSlot>[];

  if (shape == 'circle') {
    final rx = w / 2 + m.gap + m.thick / 2;
    final ry = h / 2 + m.gap + m.thick / 2;
    for (var i = 0; i < seats; i++) {
      final a = -math.pi / 2 + (2 * math.pi * i) / seats;
      out.add((
        x: w / 2 + rx * math.cos(a),
        y: h / 2 + ry * math.sin(a),
        angle: a * 180 / math.pi + 90,
      ));
    }
    return out;
  }

  final pairs = seats ~/ 2;
  final horizPairs = ((pairs * w) / (w + h)).round().clamp(0, pairs);
  final vertPairs = pairs - horizPairs;
  final wide = w >= h;
  final odd = seats.isOdd;
  final sides = <(int, String)>[
    (horizPairs, 'top'),
    (horizPairs + (odd && !wide ? 1 : 0), 'bottom'),
    (vertPairs, 'left'),
    (vertPairs + (odd && wide ? 1 : 0), 'right'),
  ];
  final off = m.gap + m.thick / 2;
  for (final (n, edge) in sides) {
    for (var i = 0; i < n; i++) {
      final t = (i + 0.5) / n;
      switch (edge) {
        case 'top':
          out.add((x: w * t, y: -off, angle: 0));
        case 'bottom':
          out.add((x: w * t, y: h + off, angle: 0));
        case 'left':
          out.add((x: -off, y: h * t, angle: 90));
        default:
          out.add((x: w + off, y: h * t, angle: 90));
      }
    }
  }
  return out;
}

/// One table on the canvas. Rotation is the caller's; everything else — the
/// chairs, the body, the ring, the chips, the badges — is drawn here from
/// canvas units × [scale].
class TableGlyph extends StatefulWidget {
  const TableGlyph({
    required this.table,
    required this.ticket,
    required this.scale,
    required this.seatsWord,
    required this.semanticsState,
    required this.onTap,
    this.locale = 'en',
    this.reservedChip,
    this.selected = false,
    this.moveRole = TableMoveRole.none,
    this.onLongPress,
    this.now,
    super.key,
  });

  final FloorTableStateView table;
  final TicketView? ticket;
  final double scale;
  final String seatsWord;

  /// The state as words, for screen readers (never colour alone).
  final String semanticsState;

  /// The app language, for the clock (`42m` / `42 د`).
  final String locale;

  /// "Omar · 19:30" on a reserved table; null when there is no guest.
  final String? reservedChip;
  final bool selected;
  final TableMoveRole moveRole;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The clock the glyph is read at (null = the wall clock).
  final DateTime? now;

  @override
  State<TableGlyph> createState() => _TableGlyphState();
}

class _TableGlyphState extends State<TableGlyph>
    with SingleTickerProviderStateMixin {
  /// The ready pulse: a few breaths when the food comes up, then a steady
  /// ring — a floor that never stops moving stops being read.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _ready =>
      tableGlyphState(widget.table, widget.ticket, now: widget.now) ==
      TableGlyphState.ready;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(TableGlyph old) {
    super.didUpdateWidget(old);
    final wasReady =
        tableGlyphState(old.table, old.ticket, now: old.now) ==
        TableGlyphState.ready;
    if (wasReady != _ready) _syncPulse();
  }

  void _syncPulse() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_ready && !still && !_pulse.isAnimating && _pulse.value == 0) {
      unawaited(
        _pulse.repeat(count: 4).whenComplete(() {
          if (mounted) _pulse.value = 0;
        }),
      );
    } else if (!_ready || still) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final colors = context.madarColors;
    final t = w.table;
    final s = w.scale;
    final state = tableGlyphState(t, w.ticket, now: w.now);
    final model = FloorTableModel(table: t, ticket: w.ticket, now: w.now);
    final tone = glyphTone(colors, state);
    final isCircle = t.shape == 'circle';
    final bw = t.width * s;
    final bh = t.height * s;

    final body = switch (state) {
      TableGlyphState.free => colors.surface,
      TableGlyphState.seated => Color.alphaBlend(
        colors.info.withValues(alpha: kTableFillSeated),
        colors.surface,
      ),
      TableGlyphState.bill => Color.alphaBlend(
        colors.info.withValues(alpha: kTableFillBill),
        colors.surface,
      ),
      TableGlyphState.ready => Color.alphaBlend(
        colors.success.withValues(alpha: 0.16),
        colors.surface,
      ),
      TableGlyphState.needsClearing => Color.alphaBlend(
        colors.danger.withValues(alpha: 0.08),
        colors.surface,
      ),
      TableGlyphState.reserved || TableGlyphState.held => Color.alphaBlend(
        colors.warning.withValues(alpha: 0.10),
        colors.surface,
      ),
    };
    final ringWidth =
        switch (state) {
          TableGlyphState.free => kTableRingFree,
          TableGlyphState.ready => kTableRingReady,
          _ => kTableRing,
        } *
        s.clamp(1.0, 1.4);
    final ringColor = state == TableGlyphState.free ? colors.border : tone;

    // Chairs, in canvas units first so the clamps mean what the dashboard's do.
    final m = seatMetrics(t.width, t.height);
    final slots = seatSlots(t.shape, t.width, t.height, t.seats)
        .map<SeatSlot>((p) => (x: p.x * s, y: p.y * s, angle: p.angle))
        .toList(growable: false);
    final chairTone = state == TableGlyphState.free
        ? colors.textMuted.withValues(alpha: 0.35)
        : tone.withValues(alpha: 0.55);

    final seated = model.seatedFor(w.now ?? DateTime.now());
    final content = _content(context, state, model, seated, bw, bh);
    final badges = _badges(context, state, model, bw, bh);
    final halo = w.selected || w.moveRole != TableMoveRole.none;

    final glyph = SizedBox(
      width: bw,
      height: bh,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ChairsPainter(
                slots: slots,
                color: chairTone,
                len: m.len * s,
                thick: m.thick * s,
              ),
            ),
          ),
          if (halo || state == TableGlyphState.ready)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, _) => CustomPaint(
                  painter: _HaloPainter(
                    isCircle: isCircle,
                    corner: kTableCorner * s,
                    gap: kTableHaloGap * s.clamp(0.8, 1.4),
                    width: kTableRingSelected * s.clamp(0.8, 1.3),
                    color: _haloColor(colors, state),
                    glow:
                        w.moveRole == TableMoveRole.target ||
                        state == TableGlyphState.ready,
                    pulse: _pulse.value,
                    solid: w.selected || w.moveRole == TableMoveRole.source,
                    target: w.moveRole == TableMoveRole.target,
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: AnimatedContainer(
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : MotionSpec.standardDuration,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: body,
                shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: isCircle
                    ? null
                    : BorderRadius.circular((kTableCorner * s).clamp(6, 16)),
                boxShadow: [
                  BoxShadow(
                    color: colors.textPrimary.withValues(
                      alpha: state == TableGlyphState.free ? 0.05 : 0.10,
                    ),
                    blurRadius: 8 * s.clamp(0.6, 1.4),
                    offset: Offset(0, 2 * s.clamp(0.6, 1.4)),
                  ),
                ],
              ),
              child: CustomPaint(
                // `painter`, under the label: the hatch is texture, not ink.
                painter: state == TableGlyphState.needsClearing
                    ? _HatchPainter(
                        tone: colors.danger,
                        pitch: (9 * s).clamp(6.0, 14.0),
                        isCircle: isCircle,
                        corner: (kTableCorner * s).clamp(6, 16),
                      )
                    : null,
                foregroundPainter: _RingPainter(
                  isCircle: isCircle,
                  corner: (kTableCorner * s).clamp(6, 16),
                  width: ringWidth,
                  color: ringColor,
                  dashed: state == TableGlyphState.reserved,
                  dash: kTableDash * s.clamp(0.8, 1.4),
                  gapLen: kTableDashGap * s.clamp(0.8, 1.4),
                ),
                child: content,
              ),
            ),
          ),
          ...badges,
        ],
      ),
    );

    final refused = w.moveRole == TableMoveRole.refused;
    return Semantics(
      button: w.onTap != null,
      enabled: w.onTap != null && !refused,
      selected: w.selected,
      label: _semanticLabel(state, model, seated),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: w.onTap == null
            ? null
            : () {
                MadarHaptics.selection();
                w.onTap!();
              },
        onLongPress: w.onLongPress == null
            ? null
            : () {
                MadarHaptics.impact();
                w.onLongPress!();
              },
        child: AnimatedOpacity(
          opacity: refused ? 0.32 : 1,
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : MotionSpec.standardDuration,
          // A table whose long press does something keeps it: its cut label
          // and chips show no hint of their own then (the label is also the
          // glyph's semantics, read out whole).
          child: w.onLongPress == null
              ? glyph
              : MadarHoldHints.off(child: glyph),
        ),
      ),
    );
  }

  Color _haloColor(MadarColors c, TableGlyphState state) {
    if (widget.moveRole == TableMoveRole.source) return c.info;
    if (widget.selected) return c.textPrimary;
    return switch (widget.moveRole) {
      TableMoveRole.source => c.info,
      TableMoveRole.target => c.success,
      _ => c.success,
    };
  }
}

extension on _TableGlyphState {
  double _fs(double base, double floor, double cap) =>
      (base * widget.scale).clamp(floor, cap);

  /// Label, the state's glyph, and up to two chips — what fits, in priority
  /// order. A circle keeps everything inside its inscribed square so nothing
  /// collides with the rim.
  Widget _content(
    BuildContext context,
    TableGlyphState state,
    FloorTableModel model,
    Duration? seated,
    double bw,
    double bh,
  ) {
    final colors = context.madarColors;
    final t = widget.table;
    final isCircle = t.shape == 'circle';
    final safeW = (isCircle ? bw * kCircleSafe : bw) - 8;
    // Narrow content may use more of a circle's height than its inscribed
    // square: the chord near the middle is nearly the full diameter.
    final safeH = (isCircle ? bh * 0.8 : bh) - 6;
    final labelSize = _fs(kTableLabelSize, kTableLabelMinPx, 26);
    final chipSize = _fs(kTableChipSize, kTableChipMinPx, 14);
    final chipH = chipSize + 9;
    final iconSize = _fs(14, 12, 18);
    final gap = (2 * widget.scale).clamp(2.0, 4.0);

    double chipWidth(String text, {bool glyph = false}) =>
        text.replaceAll(RegExp('[\u2066-\u2069]'), '').length *
            chipSize *
            0.56 +
        12 +
        (glyph ? chipSize + 3 : 0);

    // A chip rides the middle of the body, where a circle's chord is wide.
    final chipMaxW = (isCircle ? bw * 0.86 : bw) - 8;
    final chips = <Widget>[];
    var budget = safeH - labelSize * 1.15;
    // The state's glyph comes first where it NAMES the state (ready, needs
    // clearing, reserved); on a seated table the covers badge already says
    // "people", so there it only takes what is left.
    final icon = glyphIcon(state);
    // Ready wears its check as a badge on the rim (see [_badges]), so the
    // amount AND the clock both fit inside.
    final iconFirst =
        icon != null &&
        state != TableGlyphState.seated &&
        state != TableGlyphState.bill &&
        state != TableGlyphState.ready;
    if (iconFirst && budget >= iconSize + gap) budget -= iconSize + gap;

    bool room(double h) => budget >= h + gap;

    void chip(
      String text, {
      MadarGlyph? glyph,
      MadarTone tone = MadarTone.neutral,
      bool mono = false,
      bool strong = false,
    }) {
      if (!room(chipH) || chipWidth(text, glyph: glyph != null) > chipMaxW) {
        return;
      }
      budget -= chipH + gap;
      chips.add(
        _Chip(
          text: text,
          glyph: glyph,
          tone: tone,
          size: chipSize,
          height: chipH,
          mono: mono,
          strong: strong,
        ),
      );
    }

    final clock = seated == null
        ? null
        : MadarFormat.elapsed(seated, locale: widget.locale);
    final amount = model.billTotalMinor;
    switch (state) {
      case TableGlyphState.free:
        chip('${t.seats}', glyph: MadarGlyph.users);
      case TableGlyphState.seated:
        if (clock != null) {
          chip(clock, glyph: MadarGlyph.clock, tone: waitTone(seated));
        }
      case TableGlyphState.bill:
      case TableGlyphState.ready:
        if (amount != null) {
          chip(
            MadarFormat.ltr(MadarFormat.groupAmount(amount)),
            mono: true,
            strong: true,
          );
        }
        if (clock != null) {
          chip(clock, glyph: MadarGlyph.clock, tone: waitTone(seated));
        }
      case TableGlyphState.needsClearing:
        chip(widget.semanticsState, tone: MadarTone.danger);
      case TableGlyphState.reserved:
        if (widget.reservedChip case final r?) chip(r, tone: MadarTone.warning);
      case TableGlyphState.held:
        final name = t.heldOrderName?.trim();
        if (name != null && name.isNotEmpty) chip(name);
    }
    // A parked draft's name, when that is who occupies the table.
    if (state == TableGlyphState.seated &&
        widget.ticket == null &&
        (t.heldOrderName?.trim().isNotEmpty ?? false)) {
      chip(t.heldOrderName!.trim());
    }

    final showIcon =
        icon != null &&
        (iconFirst
            ? safeH - labelSize * 1.15 >= iconSize + gap
            : state != TableGlyphState.ready &&
                  budget >= iconSize + gap &&
                  model.covers == null);
    return Center(
      child: SizedBox(
        width: math.max(0, chipMaxW),
        height: math.max(0, safeH),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          spacing: gap,
          children: [
            if (showIcon)
              MadarGlyphIcon(
                icon,
                size: iconSize,
                color: glyphTone(colors, state),
              ),
            // Flexible: type has a legibility floor and geometry does not, so
            // a far-zoomed label clips rather than overflowing.
            Flexible(
              child: Container(
                constraints: BoxConstraints(maxWidth: math.max(0, safeW)),
                alignment: Alignment.center,
                child: MadarClippedText(
                  t.label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: MadarType.title.copyWith(
                    fontSize: labelSize,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
            ...chips,
          ],
        ),
      ),
    );
  }

  /// Covers at the top-end rim, queued-offline at the top-start rim — both in
  /// physical space, like the room.
  List<Widget> _badges(
    BuildContext context,
    TableGlyphState state,
    FloorTableModel model,
    double bw,
    double bh,
  ) {
    final colors = context.madarColors;
    final t = widget.table;
    final size = _fs(22, 18, 26);
    final isCircle = t.shape == 'circle';
    // On a circle the corner is the 45° point on the rim.
    final inset = isCircle ? bw / 2 * (1 - kCircleSafe) : 0.0;
    final insetY = isCircle ? bh / 2 * (1 - kCircleSafe) : 0.0;
    final out = <Widget>[];
    final covers = model.covers;
    final occupied =
        state == TableGlyphState.bill ||
        state == TableGlyphState.ready ||
        state == TableGlyphState.seated;
    if (occupied && covers != null && bw >= 56) {
      out.add(
        Positioned(
          left: bw - inset - size * 0.45,
          top: insetY - size * 0.55,
          child: _Badge(
            size: size,
            fill: colors.surface,
            ink: colors.textPrimary,
            border: glyphTone(colors, state),
            child: Text(
              '$covers',
              textDirection: TextDirection.ltr,
              style: MadarType.num.copyWith(
                fontSize: size * 0.52,
                height: 1,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      );
    }
    if (state == TableGlyphState.ready) {
      out.add(
        Positioned(
          left: inset - size * 0.55,
          top: insetY - size * 0.55,
          child: _Badge(
            size: size,
            fill: colors.success,
            ink: colors.surface,
            border: colors.surface,
            child: MadarGlyphIcon(
              MadarGlyph.check,
              size: size * 0.6,
              color: colors.surface,
            ),
          ),
        ),
      );
    }
    if (widget.ticket?.queuedOffline ?? false) {
      out.add(
        Positioned(
          left: inset - size * 0.55,
          top: bh - insetY - size * 0.45,
          child: _Badge(
            size: size,
            fill: colors.warningBg,
            ink: colors.warning,
            border: colors.warning,
            child: MadarGlyphIcon(
              MadarGlyph.wifiOff,
              size: size * 0.58,
              color: colors.warning,
            ),
          ),
        ),
      );
    }
    return out;
  }

  String _semanticLabel(
    TableGlyphState state,
    FloorTableModel model,
    Duration? seated,
  ) {
    final t = widget.table;
    final who = (widget.ticket?.customerName ?? t.heldOrderName)?.trim() ?? '';
    return [
      t.label,
      widget.semanticsState,
      if (who.isNotEmpty) who,
      if (state == TableGlyphState.reserved) ?widget.reservedChip,
      if (seated != null) MadarFormat.elapsed(seated, locale: widget.locale),
      if (model.billTotalMinor case final a?) MadarFormat.groupAmount(a),
      if (state == TableGlyphState.free) '${t.seats} ${widget.seatsWord}',
    ].join(', ');
  }
}

/// A chip on a table: the clock, the amount, the seat count, a guest.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.tone,
    required this.size,
    required this.height,
    this.glyph,
    this.mono = false,
    this.strong = false,
  });

  final String text;
  final MadarGlyph? glyph;
  final MadarTone tone;
  final double size;
  final double height;
  final bool mono;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final (fill, ink) = switch (tone) {
      MadarTone.neutral => (
        colors.surface.withValues(alpha: strong ? 1 : 0.85),
        strong ? colors.textPrimary : colors.textSecondary,
      ),
      MadarTone.warning => (colors.warningBg, colors.warning),
      MadarTone.danger => (colors.dangerBg, colors.danger),
      MadarTone.success => (colors.successBg, colors.success),
      MadarTone.accent => (colors.accentBg, colors.accent),
    };
    final base = mono ? MadarType.num : MadarType.labelSm;
    return Container(
      height: height,
      padding: EdgeInsetsDirectional.symmetric(horizontal: size * 0.5),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          if (glyph != null) MadarGlyphIcon(glyph!, size: size, color: ink),
          Flexible(
            child: MadarClippedText(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: base.copyWith(
                fontSize: size,
                height: 1,
                fontWeight: strong || tone != MadarTone.neutral
                    ? FontWeight.w700
                    : FontWeight.w600,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A round badge riding the table's rim.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.size,
    required this.fill,
    required this.ink,
    required this.border,
    required this.child,
  });

  final double size;
  final Color fill;
  final Color ink;
  final Color border;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: fill,
      shape: BoxShape.circle,
      border: Border.all(color: border, width: 1.5),
    ),
    child: child,
  );
}

Path _shapePath(Rect r, {required bool isCircle, required double corner}) =>
    isCircle
    ? (Path()..addOval(r))
    : (Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(corner))));

/// The chairs, under the body. Decorative only — never tap targets.
class _ChairsPainter extends CustomPainter {
  const _ChairsPainter({
    required this.slots,
    required this.color,
    required this.len,
    required this.thick,
  });

  final List<SeatSlot> slots;
  final Color color;
  final double len;
  final double thick;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final s in slots) {
      canvas
        ..save()
        ..translate(s.x, s.y)
        ..rotate(s.angle * math.pi / 180)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: len, height: thick),
            Radius.circular(thick / 2),
          ),
          paint,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ChairsPainter old) =>
      old.color != color ||
      old.len != len ||
      old.thick != thick ||
      old.slots.length != slots.length;
}

/// The body's ring, solid or dashed (reserved), drawn inside the edge.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.isCircle,
    required this.corner,
    required this.width,
    required this.color,
    required this.dashed,
    required this.dash,
    required this.gapLen,
  });

  final bool isCircle;
  final double corner;
  final double width;
  final Color color;
  final bool dashed;
  final double dash;
  final double gapLen;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(width / 2);
    final path = _shapePath(r, isCircle: isCircle, corner: corner);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    paint.strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color ||
      old.width != width ||
      old.dashed != dashed ||
      old.isCircle != isCircle ||
      old.corner != corner;
}

/// Selection, a move's source and targets, and the ready glow: a second ring
/// outside the body, with an optional soft glow that breathes with [pulse].
class _HaloPainter extends CustomPainter {
  const _HaloPainter({
    required this.isCircle,
    required this.corner,
    required this.gap,
    required this.width,
    required this.color,
    required this.glow,
    required this.pulse,
    required this.solid,
    this.target = false,
  });

  final bool isCircle;
  final double corner;
  final double gap;
  final double width;
  final Color color;
  final bool glow;
  final double pulse;
  final bool solid;

  /// A move's valid destination: a stronger glow and a light ring.
  final bool target;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Offset.zero & size;
    if (target) {
      final r = body.inflate(gap);
      canvas
        ..drawPath(
          _shapePath(
            body.inflate(gap * 1.4),
            isCircle: isCircle,
            corner: corner + gap,
          ),
          Paint()
            ..color = color.withValues(alpha: 0.28)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, gap),
        )
        ..drawPath(
          _shapePath(r, isCircle: isCircle, corner: corner + gap),
          Paint()
            ..color = color.withValues(alpha: 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = width * 0.6,
        );
      return;
    }
    if (glow) {
      // 0 → 1 → 0 across one breath.
      final breath = math.sin(pulse * math.pi);
      final spread = gap + breath * gap;
      final r = body.inflate(spread);
      canvas.drawPath(
        _shapePath(r, isCircle: isCircle, corner: corner + spread),
        Paint()
          ..color = color.withValues(alpha: 0.22 - breath * 0.12)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, gap * 0.9),
      );
    }
    if (solid) {
      final r = body.inflate(gap);
      canvas.drawPath(
        _shapePath(r, isCircle: isCircle, corner: corner + gap),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width,
      );
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) =>
      old.pulse != pulse ||
      old.color != color ||
      old.glow != glow ||
      old.solid != solid ||
      old.target != target ||
      old.gap != gap;
}

/// Diagonal hatching for the needs-a-bus state — texture under the label.
class _HatchPainter extends CustomPainter {
  const _HatchPainter({
    required this.tone,
    required this.pitch,
    required this.isCircle,
    required this.corner,
  });

  final Color tone;
  final double pitch;
  final bool isCircle;
  final double corner;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = tone.withValues(alpha: 0.20)
      ..strokeWidth = math.max(1, pitch * 0.28)
      ..style = PaintingStyle.stroke;
    canvas
      ..save()
      ..clipPath(
        _shapePath(Offset.zero & size, isCircle: isCircle, corner: corner),
      );
    for (var x = -size.height; x < size.width; x += pitch) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter old) =>
      old.tone != tone || old.pitch != pitch || old.isCircle != isCircle;
}
