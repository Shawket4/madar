/// The table glyph — the web's `features/floor/table-glyph.tsx` — and the
/// constants it shares with the POS.
///
/// ONE drawing of a table across the ecosystem: the POS paints the same
/// object from the same numbers (madar `packages/features/order/lib/src/
/// table_glyph.dart`, `kTable*` / `seatSlots`; dashboard web
/// `table-glyph.tsx`, `TABLE_*`). The POS package is not a dependency of
/// the dashboard (it needs the POS bridge), so the constants are copied here
/// EXACTLY: change one, change all three.
///
/// Every geometry constant is in CANVAS UNITS and is multiplied by the live
/// zoom at paint time. The drawing is physical: it is never mirrored in
/// Arabic.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

import 'floor_util.dart';

// ── Shared constants (POS `kTable*`, web `TABLE_*`) ────────────────────────

/// Rounded-rect corner radius.
const double kTableCorner = 10;

/// A free table's hairline, an occupied ring, the ready ring, the selection.
const double kTableRingFree = 1.5;
const double kTableRing = 2;
const double kTableRingReady = 3;
const double kTableRingSelected = 3;

/// How far the selection halo sits outside the body.
const double kTableHaloGap = 5;

/// Body tint over the surface: seated with no bill, with a bill.
const double kTableFillSeated = 0.10;
const double kTableFillBill = 0.22;

/// A reserved table's dashed ring.
const double kTableDash = 6;
const double kTableDashGap = 4;

/// Type on a table.
const double kTableLabelSize = 18;
const double kTableChipSize = 12;

/// A party waiting this long turns the clock amber, then red (POS only).
const int kTableLongWaitMinutes = 45;
const int kTableVeryLongWaitMinutes = 90;

/// Past this many seats the rim turns into a smear — the count carries it.
const int kSeatRenderCap = 12;

/// How far chairs reach beyond the table edge (`SEAT_ALLOWANCE`).
const double kSeatAllowance = 22;

/// One chair, in table-local canvas units (origin = the table's top-left).
typedef SeatSlot = ({double x, double y, double angle});

/// Chair capsule dimensions for a table of this size (`seatMetrics`).
({double len, double thick, double gap}) seatMetrics(double w, double h) {
  final len = (math.min(w, h) * 0.26).clamp(10.0, 28.0);
  return (len: len, thick: len * 0.42, gap: 4);
}

/// Where the chairs go (`seatSlots`): pairs facing each other on opposite
/// sides by side length, an odd seat at the HEAD of the table; circles
/// evenly; none past [kSeatRenderCap].
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
  final horizPairs = jsRoundInt((pairs * w) / (w + h)).clamp(0, pairs);
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

/// The glyph that names each tone — state never rests on colour alone.
String? toneIcon(TableTone tone) => switch (tone) {
  TableTone.available => null,
  TableTone.held => 'calendar-clock',
  TableTone.seated => 'users',
  TableTone.dirty => 'sparkles',
};

/// The tone's ring colour (`TABLE_TONE_STYLE`): seated is the primary ink,
/// reserved amber, needs-clearing red, available green (its body recedes).
Color toneColor(MadarColors c, TableTone tone) => switch (tone) {
  TableTone.available => c.success,
  TableTone.held => c.warning,
  TableTone.seated => c.accent,
  TableTone.dirty => c.danger,
};

/// The chip text shown on the bottom edge (the occupant wins; otherwise a
/// reservation unless the table needs clearing), cut to fit the table.
String? chipTextFor({
  required double w,
  required String? occupant,
  required String? reservation,
  required TableTone tone,
}) {
  final chipMax = math.max(w - 12, 48.0);
  final chipChars = math.max(3, ((chipMax - 16) / 8).floor());
  final source = occupant ?? (tone == TableTone.dirty ? null : reservation);
  if (source == null) return null;
  if (source.length > chipChars) {
    return '${source.substring(0, chipChars - 1)}…';
  }
  return source;
}

/// Everything one table needs to be drawn.
class FloorTableVisual {
  const FloorTableVisual({
    required this.id,
    required this.geo,
    required this.shape,
    required this.label,
    required this.seats,
    required this.status,
    this.occupant,
    this.reservation,
    this.held = false,
  });

  final String id;
  final GeoItem geo;
  final String shape;
  final String label;
  final int seats;
  final String status;

  /// The ticket ref or party name sitting here.
  final String? occupant;

  /// "Guest · 07:30 PM" for a confirmed booking.
  final String? reservation;

  /// The booking's hold has begun.
  final bool held;

  TableTone get tone => toneFor(status, occupant, held: held);

  String? get chipText => chipTextFor(
    w: geo.w,
    occupant: occupant,
    reservation: reservation,
    tone: tone,
  );

  /// The hover title (`<title>`): "T1 · 4 seats · occupant / reservation".
  String title(String seatsWord) {
    final extra = occupant ?? reservation;
    return '$label · $seats $seatsWord${extra == null ? '' : ' · $extra'}';
  }
}

/// The colours and words a floor paint needs, resolved from the theme.
class FloorPaintStyle {
  const FloorPaintStyle({
    required this.colors,
    required this.seatsWord,
    required this.textDirection,
  });

  final MadarColors colors;
  final String seatsWord;
  final TextDirection textDirection;
}

/// Paints one table in TABLE-LOCAL screen space: the origin is the table's
/// unrotated top-left and one canvas unit is [z] pixels. The caller applies
/// the rotation about the table's centre.
void paintTableGlyph(
  Canvas canvas,
  FloorTableVisual t,
  double z,
  FloorPaintStyle style,
) {
  final c = style.colors;
  final w = t.geo.w;
  final h = t.geo.h;
  final tone = t.tone;
  final free = tone == TableTone.available;
  final ring = toneColor(c, tone);
  final circle = t.shape == 'circle';
  final body = Rect.fromLTWH(0, 0, w * z, h * z);
  final rrect = RRect.fromRectAndRadius(
    body,
    Radius.circular(kTableCorner * z),
  );
  Path shapePath() =>
      circle ? (Path()..addOval(body)) : (Path()..addRRect(rrect));

  // Chairs first, so the surface sits on top of them.
  final metrics = seatMetrics(w, h);
  final chairPaint = Paint()
    ..color = (free ? c.textSecondary : ring).withValues(
      alpha: free ? 0.35 : 0.55,
    );
  for (final s in seatSlots(t.shape, w, h, t.seats)) {
    canvas
      ..save()
      ..translate(s.x * z, s.y * z)
      ..rotate(s.angle * math.pi / 180);
    final len = metrics.len * z;
    final thick = metrics.thick * z;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: len, height: thick),
          Radius.circular(thick / 2),
        ),
        chairPaint,
      )
      ..restore();
  }

  // The lift: a soft shadow that puts the table ON the floor.
  final lift = Paint()
    ..color = c.textPrimary.withValues(alpha: 0.16)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * z);
  canvas
    ..save()
    ..translate(0, 1.5 * z)
    ..drawPath(shapePath(), lift)
    ..restore();

  // Body: a card face when free, a tint otherwise.
  final fill = Paint()
    ..color = free
        ? c.card
        : ring.withValues(
            alpha: tone == TableTone.seated ? kTableFillBill : kTableFillSeated,
          );
  if (!free) {
    // The tint sits over the card face, as the SVG's fill-opacity over the
    // floor does.
    canvas.drawPath(shapePath(), Paint()..color = c.card);
  }
  canvas.drawPath(shapePath(), fill);

  // The sheen: a few percent of top-light.
  final sheen = Paint()
    ..shader = ui.Gradient.linear(
      Offset(0, 0),
      Offset(0, h * z),
      [
        c.textPrimary.withValues(alpha: 0.05),
        c.textPrimary.withValues(alpha: 0),
        c.textPrimary.withValues(alpha: 0.06),
      ],
      const [0, 0.55, 1],
    );
  canvas.drawPath(shapePath(), sheen);

  // Needs clearing: hatched, so it never rests on colour alone.
  if (tone == TableTone.dirty) {
    canvas
      ..save()
      ..clipPath(shapePath());
    final hatch = Paint()
      ..color = c.danger.withValues(alpha: 0.28)
      ..strokeWidth = 2.5 * z;
    final step = 8 * z;
    final span = (w + h) * z;
    for (var d = -span; d < span; d += step) {
      canvas.drawLine(Offset(d, 0), Offset(d + h * z, h * z), hatch);
    }
    canvas.restore();
  }

  // The ring: a hairline when free, dashed while reserved.
  final ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..color = free ? c.border : ring
    ..strokeWidth = (free ? kTableRingFree : kTableRing) * z;
  final ringPath = shapePath();
  if (tone == TableTone.held) {
    canvas.drawPath(
      dashPath(ringPath, kTableDash * z, kTableDashGap * z),
      ringPaint,
    );
  } else {
    canvas.drawPath(ringPath, ringPaint);
  }

  // The tone glyph, top-left (physical, never mirrored).
  final icon = toneIcon(tone);
  final iconData = icon == null ? null : madarIconCatalog[icon];
  if (iconData != null) {
    _paintText(
      canvas,
      String.fromCharCode(iconData.codePoint),
      TextStyle(
        fontFamily: iconData.fontFamily,
        package: iconData.fontPackage,
        fontSize: 16 * z,
        color: ring,
        height: 1,
      ),
      Offset(7 * z, 7 * z),
      TextDirection.ltr,
      anchorTopLeft: true,
    );
  }

  // Label over "N seats" (the seats line drops on a small table).
  final compact = h < 64 || w < 72;
  final cx = w * z / 2;
  final cy = h * z / 2;
  _paintText(
    canvas,
    t.label,
    DashType.body.copyWith(
      fontSize: kTableLabelSize * z,
      fontWeight: FontWeight.w700,
      color: c.textPrimary,
      height: 1,
    ),
    Offset(cx, compact ? cy + 6 * z : cy - 2 * z),
    style.textDirection,
  );
  if (!compact) {
    _paintText(
      canvas,
      '${t.seats} ${style.seatsWord}',
      DashType.body.copyWith(
        fontSize: kTableChipSize * z,
        fontWeight: FontWeight.w400,
        color: c.textSecondary,
        height: 1,
      ),
      Offset(cx, cy + 16 * z),
      style.textDirection,
    );
  }

  // The chip on the bottom edge: the occupant, else the reservation.
  final chip = t.chipText;
  if (chip != null) {
    final chipMax = math.max(w - 12, 48.0);
    final chipW = math.min(chipMax, chip.length * 8 + 18.0);
    final chipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - chipW * z / 2, (h - 14) * z, chipW * z, 24 * z),
      Radius.circular(12 * z),
    );
    canvas
      ..drawRRect(chipRect, Paint()..color = c.card)
      ..drawRRect(
        chipRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = ring
          ..strokeWidth = 1.5 * z,
      );
    _paintText(
      canvas,
      chip,
      DashType.body.copyWith(
        fontSize: 13 * z,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
        height: 1,
      ),
      Offset(cx, (h + 3) * z),
      style.textDirection,
    );
  }
}

/// Paints [text] centred on [anchor]'s x with its alphabetic baseline on
/// [anchor]'s y (SVG `text-anchor="middle"`), or from its top-left.
void _paintText(
  Canvas canvas,
  String text,
  TextStyle style,
  Offset anchor,
  TextDirection direction, {
  bool anchorTopLeft = false,
}) {
  if ((style.fontSize ?? 0) <= 0.5) return;
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    maxLines: 1,
  )..layout();
  final offset = anchorTopLeft
      ? anchor
      : Offset(
          anchor.dx - tp.width / 2,
          anchor.dy -
              tp.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        );
  tp
    ..paint(canvas, offset)
    ..dispose();
}

/// [source] cut into [dash]-long strokes with [gap] between them.
Path dashPath(Path source, double dash, double gap) {
  final out = Path();
  if (dash <= 0) return source;
  for (final metric in source.computeMetrics()) {
    var d = 0.0;
    while (d < metric.length) {
      final end = math.min(d + dash, metric.length);
      out.addPath(metric.extractPath(d, end), Offset.zero);
      d = end + gap;
    }
  }
  return out;
}
