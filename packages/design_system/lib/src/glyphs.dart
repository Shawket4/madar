/// The Madar glyph set — system v2.
///
/// One icon language for the whole till: a 24-unit grid, a 2.5-unit stroke
/// with round caps and joins, drawn once here as path data (the canvas's own
/// paths, verbatim) and painted by [MadarGlyphIcon]. A glyph has two states:
/// OUTLINE at rest and FILLED when it is the active tab, where the closed
/// shapes take a 28% wash of the stroke colour behind the stroke — a duotone,
/// not a different drawing, so the tab does not jump when it lights up.
///
/// Direction. A glyph that points somewhere along the reading axis — back,
/// forward, undo, sign out, backspace — is drawn for LTR and flipped under
/// RTL, so "back" points at the start edge in both scripts. A glyph that is a
/// thing (a printer, a clock) never flips.
///
/// Why not Lucide. The old kit resolved SF-Symbol names to Lucide glyphs at a
/// 2-unit stroke; the canvas draws its own set at 2.5 so a glyph holds its
/// weight beside 17-bold button labels. `MadarIcon` still accepts the old
/// names and routes the ones this set covers here, so a feature that has not
/// migrated already gets the new drawing.
library;

import 'dart:ui' as ui;

import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:flutter/widgets.dart';

/// One stroke or fill inside a glyph.
@immutable
class GlyphShape {
  const GlyphShape(
    this.d, {
    this.fill = false,
    this.duo = true,
    this.dashed = false,
    this.contrast = false,
  });

  /// SVG path data on the 24 grid.
  final String d;

  /// Solid fill, no stroke — a dot, a filled disc.
  final bool fill;

  /// Takes the 28% wash when the glyph is [MadarGlyphIcon.filled]. Off for
  /// open strokes (a check mark has no inside).
  final bool duo;

  /// Dashed stroke — the hollow "offline" disc.
  final bool dashed;

  /// Stroked in the CONTRAST colour (the surface behind the glyph) — the
  /// tick inside a filled checkbox.
  final bool contrast;
}

/// A circle as path data.
String _circle(double cx, double cy, double r) =>
    'M${cx - r} ${cy}a$r $r 0 1 0 ${2 * r} 0a$r $r 0 1 0 ${-2 * r} 0z';

/// A rounded rectangle as path data.
String _rect(double x, double y, double w, double h, double r) =>
    'M${x + r} ${y}h${w - 2 * r}a$r $r 0 0 1 $r ${r}v${h - 2 * r}'
    'a$r $r 0 0 1 ${-r} ${r}h${-(w - 2 * r)}a$r $r 0 0 1 ${-r} ${-r}'
    'v${-(h - 2 * r)}a$r $r 0 0 1 $r ${-r}z';

// Recurring shapes, named once.
final String _disc85 = _circle(12, 12, 8.5);
final String _disc9 = _circle(12, 12, 9);

/// Every glyph in the set. Named for what it MEANS on the till where that is
/// clearer than what it draws ([chevronBack] rather than chevron-left).
enum MadarGlyph {
  // ── Direction (mirrored under RTL) ────────────────────────────────────
  /// Points at the start edge. Back.
  chevronBack(mirror: true),

  /// Points at the end edge. Disclosure, next.
  chevronForward(mirror: true),

  /// Out and towards the end: money in.
  arrowUpEnd(mirror: true),

  /// In and towards the start: money out.
  arrowDownStart(mirror: true),
  undo(mirror: true),
  signOut(mirror: true),
  backspace(mirror: true),

  // ── Direction (fixed) ─────────────────────────────────────────────────
  chevronUp,
  chevronDown,
  arrowUp,
  arrowDown,
  move,

  // ── Verbs ─────────────────────────────────────────────────────────────
  close,
  check,
  plus,
  minus,
  search,
  more,
  refresh,
  edit,
  trash,
  printer,
  camera,
  scan,
  split,
  percent,

  // ── Tabs and places ───────────────────────────────────────────────────
  /// Sell.
  bag,

  /// Floor.
  grid,

  /// Queue.
  inbox,

  /// Till.
  wallet,

  /// Bills.
  receipt,

  /// Me.
  user,
  users,
  table,
  flame,
  bike,
  bookmark,
  settings,
  globe,
  bell,
  tag,
  star,
  sparkle,
  clock,
  calendar,
  list,
  menu,
  note,
  phone,
  lock,
  banknote,
  card,
  wifi,
  wifiOff,

  // ── State discs (the outbox pill, a row's state word) ─────────────────
  /// Queued: half full.
  half,

  /// Partly done: a quarter.
  quarter,

  /// Offline: a dashed ring.
  hollow,

  /// Done: a full disc.
  full,

  /// Waiting: an empty ring.
  ring,
  checkCircle,
  xCircle,
  alertCircle,
  alertTriangle,
  squareCheck,
  square,
  radio,

  /// The brand M in the rail's mark.
  mark;

  const MadarGlyph({this.mirror = false});

  /// Flips under RTL.
  final bool mirror;

  /// The shapes that draw this glyph.
  List<GlyphShape> get shapes => _shapes[this]!;
}

final Map<MadarGlyph, List<GlyphShape>> _shapes = {
  MadarGlyph.chevronBack: const [GlyphShape('m15 18-6-6 6-6', duo: false)],
  MadarGlyph.chevronForward: const [GlyphShape('m9 18 6-6-6-6', duo: false)],
  MadarGlyph.chevronUp: const [GlyphShape('m18 15-6-6-6 6', duo: false)],
  MadarGlyph.chevronDown: const [GlyphShape('m6 9 6 6 6-6', duo: false)],
  MadarGlyph.arrowUp: const [GlyphShape('M12 19V5m-7 7 7-7 7 7', duo: false)],
  MadarGlyph.arrowDown: const [GlyphShape('M12 5v14m7-7-7 7-7-7', duo: false)],
  MadarGlyph.arrowUpEnd: const [GlyphShape('M7 17 17 7M8 7h9v9', duo: false)],
  MadarGlyph.arrowDownStart: const [
    GlyphShape('M17 7 7 17M16 17H7V8', duo: false),
  ],
  MadarGlyph.undo: const [
    GlyphShape('M4 10h11a5 5 0 0 1 0 10h-3', duo: false),
    GlyphShape('m8 6-4 4 4 4', duo: false),
  ],
  MadarGlyph.signOut: const [
    GlyphShape('M10 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h4', duo: false),
    GlyphShape('m15 8 4 4-4 4M19 12H9', duo: false),
  ],
  MadarGlyph.backspace: const [
    GlyphShape('M20 5H9L3 12l6 7h11a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1z'),
    GlyphShape('m12 9 6 6m0-6-6 6', duo: false),
  ],
  MadarGlyph.move: const [
    GlyphShape('M12 3v18M3 12h18', duo: false),
    GlyphShape(
      'm8 7 4-4 4 4M8 17l4 4 4-4M7 8l-4 4 4 4M17 8l4 4-4 4',
      duo: false,
    ),
  ],
  MadarGlyph.close: const [GlyphShape('M18 6 6 18M6 6l12 12', duo: false)],
  MadarGlyph.check: const [GlyphShape('m5 12.5 4.5 4.5L19 7.5', duo: false)],
  MadarGlyph.plus: const [GlyphShape('M12 5v14M5 12h14', duo: false)],
  MadarGlyph.minus: const [GlyphShape('M5 12h14', duo: false)],
  MadarGlyph.search: [
    GlyphShape(_circle(11, 11, 7)),
    const GlyphShape('m20 20-4-4', duo: false),
  ],
  MadarGlyph.more: [
    GlyphShape(_circle(5, 12, 1.6), fill: true),
    GlyphShape(_circle(12, 12, 1.6), fill: true),
    GlyphShape(_circle(19, 12, 1.6), fill: true),
  ],
  MadarGlyph.refresh: const [
    GlyphShape('M20 12a8 8 0 0 1-14.5 4.6M4 12a8 8 0 0 1 14.5-4.6', duo: false),
    GlyphShape('M4 20v-5h5M20 4v5h-5', duo: false),
  ],
  MadarGlyph.edit: const [
    GlyphShape('M4 20h4L19 9l-4-4L4 16z'),
    GlyphShape('m13 7 4 4', duo: false),
  ],
  MadarGlyph.trash: const [
    GlyphShape('M4 7h16M10 7V4h4v3', duo: false),
    GlyphShape('m6 7 1 13h10l1-13z'),
    GlyphShape('M10 11v5M14 11v5', duo: false),
  ],
  MadarGlyph.printer: [
    const GlyphShape('M7 9V3h10v6', duo: false),
    const GlyphShape(
      'M7 17H4a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1h16a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-3',
      duo: false,
    ),
    GlyphShape(_rect(7, 14, 10, 7, 1)),
  ],
  MadarGlyph.camera: [
    const GlyphShape('M4 8h3l2-3h6l2 3h3v11H4z'),
    GlyphShape(_circle(12, 13, 3.5), duo: false),
  ],
  MadarGlyph.scan: const [
    GlyphShape(
      'M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3',
      duo: false,
    ),
    GlyphShape('M4 12h16', duo: false),
  ],
  MadarGlyph.split: [
    GlyphShape(_disc9),
    const GlyphShape('M12 3v18', duo: false),
  ],
  MadarGlyph.percent: [
    const GlyphShape('M19 5 5 19', duo: false),
    GlyphShape(_circle(7, 7, 2.5)),
    GlyphShape(_circle(17, 17, 2.5)),
  ],
  MadarGlyph.bag: const [
    GlyphShape('M5 8h14l-1 12a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1L5 8z'),
    GlyphShape('M9 8V6a3 3 0 0 1 6 0v2', duo: false),
  ],
  // Four equal squares read as an app switcher, not a room — wrong for a
  // tab that means "the floor" and, per every `square.grid.2x2` call site
  // in `features/order`, almost always stands for a table or the floor
  // itself. A room boundary with tables inside says what it is.
  MadarGlyph.grid: [
    GlyphShape(_rect(3, 3, 18, 18, 4)),
    GlyphShape(_circle(9, 9, 1.8), fill: true),
    GlyphShape(_circle(16, 9, 1.8), fill: true),
    GlyphShape(_circle(9, 16, 1.8), fill: true),
    GlyphShape(_circle(16, 16, 1.8), fill: true),
  ],
  MadarGlyph.inbox: const [
    GlyphShape('M4 4h16v10h-5l-1.5 3h-3L9 14H4z'),
    GlyphShape('M4 14v6h16v-6', duo: false),
  ],
  MadarGlyph.wallet: [
    GlyphShape(_rect(3, 6, 18, 14, 3)),
    const GlyphShape('M3 10h18', duo: false),
    GlyphShape(_circle(16.5, 15, 1.5), fill: true),
  ],
  MadarGlyph.receipt: const [
    GlyphShape('M6 3h12v18l-3-2-3 2-3-2-3 2z'),
    GlyphShape('M9 8h6M9 12h6M9 16h3', duo: false),
  ],
  MadarGlyph.user: [
    GlyphShape(_circle(12, 8, 4)),
    const GlyphShape('M4 21a8 8 0 0 1 16 0', duo: false),
  ],
  MadarGlyph.users: [
    GlyphShape(_circle(9, 8, 3.5)),
    const GlyphShape('M2.5 20a6.5 6.5 0 0 1 13 0', duo: false),
    GlyphShape(_circle(17, 9, 2.5)),
    const GlyphShape('M21.5 19a5 5 0 0 0-5-5', duo: false),
  ],
  MadarGlyph.table: [
    GlyphShape(_rect(3, 6, 18, 6, 2)),
    const GlyphShape('M6 12v7M18 12v7', duo: false),
  ],
  MadarGlyph.flame: const [
    GlyphShape(
      'M12 3c1 4 5 5 5 10a5 5 0 0 1-10 0c0-2 1-3 2-4 0 2 1 3 2 3 0-4 1-6 1-9z',
    ),
  ],
  MadarGlyph.bike: [
    GlyphShape(_circle(6, 16, 3.5)),
    GlyphShape(_circle(18, 16, 3.5)),
    const GlyphShape('M6 16 10 8h4l4 8M10 8l4 8M13 5h3', duo: false),
  ],
  MadarGlyph.bookmark: const [GlyphShape('M6 4h12v16l-6-3-6 3z')],
  MadarGlyph.settings: [
    const GlyphShape('M4 7h9M18 7h2M4 17h3M12 17h8', duo: false),
    GlyphShape(_circle(15.5, 7, 2.5)),
    GlyphShape(_circle(9.5, 17, 2.5)),
  ],
  MadarGlyph.globe: [
    GlyphShape(_disc9),
    const GlyphShape('M3 12h18', duo: false),
    const GlyphShape('M12 3c-3 3-3 15 0 18M12 3c3 3 3 15 0 18', duo: false),
  ],
  MadarGlyph.bell: const [
    GlyphShape('M6 16V11a6 6 0 0 1 12 0v5l2 2H4z'),
    GlyphShape('M10 21h4', duo: false),
  ],
  MadarGlyph.tag: [
    const GlyphShape('M3 3h8l10 10-8 8L3 11z'),
    GlyphShape(_circle(8, 8, 1.5), fill: true),
  ],
  MadarGlyph.star: const [
    GlyphShape(
      'm12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z',
    ),
  ],
  MadarGlyph.sparkle: const [
    GlyphShape(
      'M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M6 18l2.5-2.5M15.5 8.5 18 6',
      duo: false,
    ),
  ],
  MadarGlyph.clock: [
    GlyphShape(_disc9),
    const GlyphShape('M12 7v5l3.5 2', duo: false),
  ],
  MadarGlyph.calendar: [
    GlyphShape(_rect(3, 5, 18, 16, 3)),
    const GlyphShape('M3 10h18M8 3v4M16 3v4', duo: false),
  ],
  MadarGlyph.list: [
    const GlyphShape('M8 6h13M8 12h13M8 18h13', duo: false),
    GlyphShape(_circle(4, 6, 1.2), fill: true),
    GlyphShape(_circle(4, 12, 1.2), fill: true),
    GlyphShape(_circle(4, 18, 1.2), fill: true),
  ],
  MadarGlyph.menu: const [GlyphShape('M4 7h16M4 12h16M4 17h16', duo: false)],
  MadarGlyph.note: const [
    GlyphShape(
      'M5 4h14a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1h-8l-5 4v-4H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z',
    ),
  ],
  MadarGlyph.phone: const [
    GlyphShape(
      'M5 3h4l2 5-2.5 1.5a11 11 0 0 0 6 6L16 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 5a2 2 0 0 1 2-2z',
    ),
  ],
  MadarGlyph.lock: [
    GlyphShape(_rect(4, 10, 16, 11, 3)),
    const GlyphShape('M8 10V7a4 4 0 0 1 8 0v3', duo: false),
  ],
  MadarGlyph.banknote: [
    GlyphShape(_rect(2, 6, 20, 12, 2)),
    GlyphShape(_circle(12, 12, 2.5), duo: false),
    GlyphShape(_circle(6, 12, 1), fill: true),
    GlyphShape(_circle(18, 12, 1), fill: true),
  ],
  MadarGlyph.card: [
    GlyphShape(_rect(3, 5, 18, 14, 3)),
    const GlyphShape('M3 10h18M7 15h4', duo: false),
  ],
  MadarGlyph.wifi: [
    const GlyphShape(
      'M2 9a15 15 0 0 1 20 0M5.5 12.5a10 10 0 0 1 13 0M9 16a5 5 0 0 1 6 0',
      duo: false,
    ),
    GlyphShape(_circle(12, 19.5, 1.2), fill: true),
  ],
  MadarGlyph.wifiOff: [
    const GlyphShape(
      'M2 9a15 15 0 0 1 4-2.5M22 9a15 15 0 0 0-11-3M5.5 12.5a10 10 0 0 1 5-2.3M18.5 12.5a10 10 0 0 0-2-1.4M9 16a5 5 0 0 1 6 0',
      duo: false,
    ),
    GlyphShape(_circle(12, 19.5, 1.2), fill: true),
    const GlyphShape('m3 3 18 18', duo: false),
  ],
  MadarGlyph.half: [
    GlyphShape(_disc85, duo: false),
    const GlyphShape('M12 3.5a8.5 8.5 0 0 1 0 17z', fill: true),
  ],
  MadarGlyph.quarter: [
    GlyphShape(_disc85, duo: false),
    const GlyphShape('M12 3.5a8.5 8.5 0 0 1 8.5 8.5H12z', fill: true),
  ],
  MadarGlyph.hollow: [GlyphShape(_disc85, duo: false, dashed: true)],
  MadarGlyph.full: [GlyphShape(_disc85, fill: true)],
  MadarGlyph.ring: [GlyphShape(_disc85, duo: false)],
  MadarGlyph.checkCircle: [
    GlyphShape(_disc9),
    const GlyphShape('m8.5 12.5 2.5 2.5 5-5', duo: false),
  ],
  MadarGlyph.xCircle: [
    GlyphShape(_disc9),
    const GlyphShape('m9 9 6 6m0-6-6 6', duo: false),
  ],
  MadarGlyph.alertCircle: [
    GlyphShape(_disc9),
    const GlyphShape('M12 7v6', duo: false),
    GlyphShape(_circle(12, 16.5, 1.2), fill: true),
  ],
  MadarGlyph.alertTriangle: [
    const GlyphShape('M12 3 2 20h20L12 3z'),
    const GlyphShape('M12 10v4', duo: false),
    GlyphShape(_circle(12, 17, 1.2), fill: true),
  ],
  MadarGlyph.squareCheck: [
    GlyphShape(_rect(3, 3, 18, 18, 5), fill: true),
    const GlyphShape('m8 12.5 2.8 2.8L16.5 9', duo: false, contrast: true),
  ],
  MadarGlyph.square: [GlyphShape(_rect(3, 3, 18, 18, 5), duo: false)],
  MadarGlyph.radio: [GlyphShape(_disc9, duo: false)],
  MadarGlyph.mark: const [GlyphShape('M4 20V6l8 9 8-9v14', duo: false)],
};

/// The grid every glyph is drawn on.
const double glyphGrid = 24;

/// The stroke, in grid units. Scales with the glyph.
const double glyphStroke = 2.5;

/// Paints one [MadarGlyph].
///
/// [color] defaults to the ambient [IconTheme] colour, then the theme's
/// primary text. [filled] is the active-tab state: closed shapes take a wash
/// of the colour behind the stroke. [contrast] is what a contrast stroke is
/// drawn in (the tick in a filled checkbox); it defaults to the surface.
///
/// ```dart
/// MadarGlyphIcon(MadarGlyph.receipt, size: IconSize.xxl, filled: active)
/// ```
class MadarGlyphIcon extends StatelessWidget {
  const MadarGlyphIcon(
    this.glyph, {
    this.size = IconSize.lg,
    this.color,
    this.filled = false,
    this.contrast,
    this.semanticLabel,
    super.key,
  });

  final MadarGlyph glyph;
  final double size;
  final Color? color;
  final bool filled;
  final Color? contrast;

  /// What the glyph means where it stands, for a screen reader. A glyph
  /// beside a label needs none.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ??
        IconTheme.of(context).color ??
        MadarColors.of(context).textPrimary;
    final onColor = contrast ?? MadarColors.of(context).surface;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    Widget paint = CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(
        shapes: glyph.shapes,
        color: resolved,
        contrast: onColor,
        filled: filled,
      ),
    );
    if (glyph.mirror && rtl) {
      paint = Transform.flip(flipX: true, child: paint);
    }
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel == null,
      child: SizedBox.square(dimension: size, child: paint),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({
    required this.shapes,
    required this.color,
    required this.contrast,
    required this.filled,
  });

  final List<GlyphShape> shapes;
  final Color color;
  final Color contrast;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / glyphGrid;
    canvas
      ..save()
      ..scale(scale);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = glyphStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final wash = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: Opacities.subtle);
    final solid = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    // Wash first, so every stroke sits on top of every fill.
    if (filled) {
      for (final shape in shapes) {
        if (shape.duo && !shape.fill) {
          canvas.drawPath(parseSvgPath(shape.d), wash);
        }
      }
    }
    for (final shape in shapes) {
      final path = parseSvgPath(shape.d);
      if (shape.fill) {
        canvas.drawPath(path, solid);
        continue;
      }
      if (shape.dashed) {
        canvas.drawPath(_dash(path, 4, 3.5), stroke);
        continue;
      }
      if (shape.contrast) {
        canvas.drawPath(path, Paint.from(stroke)..color = contrast);
        continue;
      }
      canvas.drawPath(path, stroke);
    }
    canvas.restore();
  }

  /// Chops [source] into `on`/`off` runs — Flutter has no dash effect of its
  /// own, and the hollow disc is the only glyph that needs one.
  static Path _dash(Path source, double on, double off) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + on).clamp(0.0, metric.length);
        out.addPath(metric.extractPath(distance, end), Offset.zero);
        distance += on + off;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.shapes != shapes ||
      old.color != color ||
      old.contrast != contrast ||
      old.filled != filled;
}

// ── SVG path data → Path ───────────────────────────────────────────────

final Map<String, Path> _pathCache = {};

/// Turns SVG path data into a [Path]. Handles the commands the glyph set
/// uses — M L H V C S Q A Z, absolute and relative, with implicit repeats —
/// and caches by string, since a glyph is painted many times a frame and its
/// data never changes.
Path parseSvgPath(String d) => _pathCache.putIfAbsent(d, () => _parse(d));

final RegExp _token = RegExp(r'[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)');

Path _parse(String d) {
  final path = Path();
  final tokens = _token.allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var cmd = '';
  var x = 0.0;
  var y = 0.0;
  var startX = 0.0;
  var startY = 0.0;
  // Last control point, for S (smooth cubic) reflection.
  double? cx2;
  double? cy2;

  double next() => double.parse(tokens[i++]);
  bool numberAhead() => i < tokens.length && !_isCommand(tokens[i]);

  while (i < tokens.length) {
    final t = tokens[i];
    if (_isCommand(t)) {
      cmd = t;
      i++;
      if (cmd == 'Z' || cmd == 'z') {
        path.close();
        x = startX;
        y = startY;
        cx2 = cy2 = null;
        continue;
      }
    } else if (cmd == 'M') {
      // Implicit repeat after a moveto is a lineto.
      cmd = 'L';
    } else if (cmd == 'm') {
      cmd = 'l';
    }
    final rel = cmd == cmd.toLowerCase();
    final dx = rel ? x : 0.0;
    final dy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = next() + dx;
        y = next() + dy;
        path.moveTo(x, y);
        startX = x;
        startY = y;
        cx2 = cy2 = null;
      case 'L':
        x = next() + dx;
        y = next() + dy;
        path.lineTo(x, y);
        cx2 = cy2 = null;
      case 'H':
        x = next() + dx;
        path.lineTo(x, y);
        cx2 = cy2 = null;
      case 'V':
        y = next() + dy;
        path.lineTo(x, y);
        cx2 = cy2 = null;
      case 'C':
        final x1 = next() + dx;
        final y1 = next() + dy;
        final x2 = next() + dx;
        final y2 = next() + dy;
        x = next() + dx;
        y = next() + dy;
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx2 = x2;
        cy2 = y2;
      case 'S':
        final x1 = cx2 == null ? x : 2 * x - cx2;
        final y1 = cy2 == null ? y : 2 * y - cy2;
        final x2 = next() + dx;
        final y2 = next() + dy;
        x = next() + dx;
        y = next() + dy;
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx2 = x2;
        cy2 = y2;
      case 'Q':
        final x1 = next() + dx;
        final y1 = next() + dy;
        x = next() + dx;
        y = next() + dy;
        path.quadraticBezierTo(x1, y1, x, y);
        cx2 = cy2 = null;
      case 'A':
        final rx = next();
        final ry = next();
        final rotation = next();
        final largeArc = next() != 0;
        final sweep = next() != 0;
        x = next() + dx;
        y = next() + dy;
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rotation,
          largeArc: largeArc,
          clockwise: sweep,
        );
        cx2 = cy2 = null;
      default:
        throw FormatException('unsupported path command $cmd in "$d"');
    }
    // An implicit repeat of the same command follows when numbers do.
    if (!numberAhead()) continue;
  }
  return path;
}

bool _isCommand(String t) => t.length == 1 && RegExp('[A-Za-z]').hasMatch(t);

/// A path's drawn extent, for tests.
ui.Rect glyphBounds(MadarGlyph glyph) {
  var bounds = ui.Rect.zero;
  for (final shape in glyph.shapes) {
    final b = parseSvgPath(shape.d).getBounds();
    bounds = bounds == ui.Rect.zero ? b : bounds.expandToInclude(b);
  }
  return bounds;
}
