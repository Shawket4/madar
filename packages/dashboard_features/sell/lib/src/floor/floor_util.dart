/// The floor's pure maths and rules — the web's `features/floor/util.ts` and
/// `gestures.ts`, ported one function per function so the web's own tests
/// (`selection`, `history`, `util`, `viewport`, `gestures`) port as they are.
///
/// Everything here is in CANVAS UNITS on an unbounded plane: tables may sit
/// at negative coordinates, the view is a window that pans and zooms over it.
/// A floor plan is physical space, so nothing here knows about reading
/// direction.
library;

import 'dart:convert';
import 'dart:math' as math;

// ── Status ────────────────────────────────────────────────────────────────

/// The four display tones (`TABLE_TONES`), in legend order.
enum TableTone { available, held, seated, dirty }

/// A table is taken when the POS marked it `seated`, or when a live open
/// ticket occupies it (`isTableTaken`).
bool isTableTaken(String status, String? occupant) =>
    status == 'seated' || (occupant != null && occupant.isNotEmpty);

/// The last party's plates are still on it and nobody sits there
/// (`needsClearing`): a live occupant always wins over `dirty`.
bool needsClearing(String status, String? occupant) =>
    status == 'dirty' && !isTableTaken(status, occupant);

/// The one mapper every floor surface uses (`toneFor`): taken, then needs
/// clearing, then reserved while a booking's hold runs, else available. The
/// raw `held` status (a teller's short hold) stays a POS concern and reads
/// as available.
TableTone toneFor(String status, String? occupant, {bool held = false}) {
  if (isTableTaken(status, occupant)) return TableTone.seated;
  if (needsClearing(status, occupant)) return TableTone.dirty;
  return held ? TableTone.held : TableTone.available;
}

/// Has a confirmed booking's hold begun (`isHeldNow`)? From `held_from`
/// until the booking is seated or over.
bool isHeldNow({
  required String? status,
  required DateTime? heldFrom,
  required DateTime now,
}) =>
    status == 'confirmed' &&
    heldFrom != null &&
    !heldFrom.isAfter(now);

// ── Grid, rotation, sizes ─────────────────────────────────────────────────

/// Snap pitch (canvas units) of drag, resize and nudge.
const double kFloorGrid = 10;

/// The rotation handle's and the ± buttons' step, in degrees.
const double kRotationStep = 15;

/// The smallest a resize may make a table.
const double kMinTableSize = 24;

/// How far a pasted copy sits from where it was dropped.
const double kPasteOffset = 20;

/// Autosave fires this long after the last change.
const Duration kAutosaveDebounce = Duration(milliseconds: 600);

/// Undo steps kept (`HISTORY_LIMIT`).
const int kHistoryLimit = 100;

/// `snapTo`: to the [pitch] grid when [on], else to a whole unit.
double snapTo(double v, bool on, [double pitch = kFloorGrid]) =>
    on ? _jsRound(v / pitch) * pitch : _jsRound(v).toDouble();

/// JavaScript's `Math.round` (halves toward +∞).
double _jsRound(double v) => (v + 0.5).floorToDouble();

/// `Math.round` as an int.
int jsRoundInt(double v) => (v + 0.5).floor();

/// Degrees into 0 ≤ a < 360.
double normalizeAngle(double deg) => ((deg % 360) + 360) % 360;

/// Default footprint per shape (`DEFAULT_TABLE_SIZE`).
({double w, double h}) defaultTableSize(String shape) =>
    shape == 'circle' ? (w: 90, h: 90) : (w: 120, h: 80);

// ── Rectangles, viewport ──────────────────────────────────────────────────

/// A rectangle in canvas units (may have a negative width while a marquee
/// is dragged up or left).
class FloorRect {
  const FloorRect(this.x, this.y, this.w, this.h);

  final double x;
  final double y;
  final double w;
  final double h;

  @override
  bool operator ==(Object other) =>
      other is FloorRect &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'FloorRect($x, $y, $w, $h)';
}

/// The patch of floor shown when an area has no tables (`EMPTY_VIEW`).
const FloorRect kEmptyView = FloorRect(0, 0, 1000, 700);

/// The window onto the plane: world coordinate at the top-left, and pixels
/// per world unit.
class FloorView {
  const FloorView({required this.x, required this.y, required this.zoom});

  final double x;
  final double y;
  final double zoom;

  FloorView copyWith({double? x, double? y, double? zoom}) =>
      FloorView(x: x ?? this.x, y: y ?? this.y, zoom: zoom ?? this.zoom);

  @override
  bool operator ==(Object other) =>
      other is FloorView && other.x == x && other.y == y && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(x, y, zoom);

  @override
  String toString() => 'FloorView($x, $y, ×$zoom)';
}

const double kZoomMin = 0.1;
const double kZoomMax = 4;

/// One notch of the zoom buttons and keys.
const double kZoomStep = 1.25;

/// Breathing room around the content when fitting (screen pixels).
const double kFitPadding = 80;

double clampZoom(double z) => math.min(kZoomMax, math.max(kZoomMin, z));

/// The world box a set of tables occupies; a rotated table contributes the
/// circle its diagonal describes, so a fit never crops a corner
/// (`boundsOf`).
FloorRect boundsOf(Iterable<GeoItem> items, FloorRect fallback) {
  if (items.isEmpty) return fallback;
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final it in items) {
    final r = _hypot(it.w, it.h) / 2;
    final cx = it.x + it.w / 2;
    final cy = it.y + it.h / 2;
    minX = math.min(minX, cx - r);
    minY = math.min(minY, cy - r);
    maxX = math.max(maxX, cx + r);
    maxY = math.max(maxY, cy + r);
  }
  return FloorRect(minX, minY, maxX - minX, maxY - minY);
}

double _hypot(double a, double b) => math.sqrt(a * a + b * b);

/// Frames [bounds] centred in a viewport of [w]×[h] pixels (`fitView`).
FloorView fitView(
  FloorRect bounds,
  double w,
  double h, {
  double padding = kFitPadding,
}) {
  final zoom = clampZoom(
    math.min(w / (bounds.w + padding * 2), h / (bounds.h + padding * 2)),
  );
  return FloorView(
    zoom: zoom,
    x: bounds.x + bounds.w / 2 - w / (2 * zoom),
    y: bounds.y + bounds.h / 2 - h / (2 * zoom),
  );
}

/// Scales about a fixed world point, so what sits under the cursor stays
/// under it (`zoomAt`). At a limit the view does not move.
FloorView zoomAt(FloorView view, double factor, double ax, double ay) {
  final zoom = clampZoom(view.zoom * factor);
  if (zoom == view.zoom) return view;
  return FloorView(
    zoom: zoom,
    x: ax - (ax - view.x) * (view.zoom / zoom),
    y: ay - (ay - view.y) * (view.zoom / zoom),
  );
}

/// The world rectangle a view of [w]×[h] pixels shows (`viewRect`).
FloorRect viewRect(FloorView view, double w, double h) =>
    FloorRect(view.x, view.y, w / view.zoom, h / view.zoom);

// ── Undo history ──────────────────────────────────────────────────────────

/// Snapshots per GESTURE, not per frame (`UndoHistory`).
class UndoHistory<T> {
  const UndoHistory({this.past = const [], this.future = const []});

  final List<T> past;
  final List<T> future;
}

/// Records the state a gesture is about to change; clears the redo branch;
/// keeps at most [kHistoryLimit] steps (`pushHistory`).
UndoHistory<T> pushHistory<T>(UndoHistory<T> history, T snapshot) {
  final past = [...history.past, snapshot];
  return UndoHistory(
    past: past.length > kHistoryLimit
        ? past.sublist(past.length - kHistoryLimit)
        : past,
  );
}

/// One step back, or null when there is nothing to undo (`applyUndo`).
({T value, UndoHistory<T> history})? applyUndo<T>(
  UndoHistory<T> history,
  T current,
) {
  if (history.past.isEmpty) return null;
  return (
    value: history.past.last,
    history: UndoHistory(
      past: history.past.sublist(0, history.past.length - 1),
      future: [current, ...history.future],
    ),
  );
}

/// One step forward, or null when the redo branch is empty (`applyRedo`).
({T value, UndoHistory<T> history})? applyRedo<T>(
  UndoHistory<T> history,
  T current,
) {
  if (history.future.isEmpty) return null;
  return (
    value: history.future.first,
    history: UndoHistory(
      past: [...history.past, current],
      future: history.future.sublist(1),
    ),
  );
}

// ── Geometry items: selection, alignment, clipboard ───────────────────────

/// A table as far as geometry is concerned (`GeoItem`).
class GeoItem {
  const GeoItem({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.rot,
  });

  final String id;
  final double x;
  final double y;
  final double w;
  final double h;

  /// Degrees.
  final double rot;

  double get cx => x + w / 2;
  double get cy => y + h / 2;

  GeoItem copyWith({double? x, double? y, double? w, double? h, double? rot}) =>
      GeoItem(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        rot: rot ?? this.rot,
      );

  /// Same place, size and angle.
  bool sameAs(GeoItem o) =>
      o.x == x && o.y == y && o.w == w && o.h == h && o.rot == rot;

  @override
  bool operator ==(Object other) =>
      other is GeoItem && other.id == id && sameAs(other);

  @override
  int get hashCode => Object.hash(id, x, y, w, h, rot);

  @override
  String toString() => 'GeoItem($id, $x, $y, $w×$h, $rot°)';
}

/// The axis-aligned envelope of one item, rotation included (`envelopeOf`).
FloorRect envelopeOf(GeoItem it) {
  final r = _hypot(it.w, it.h) / 2;
  return FloorRect(it.cx - r, it.cy - r, r * 2, r * 2);
}

bool rectsIntersect(FloorRect a, FloorRect b) =>
    a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;

/// The ids a marquee touches — touch, not containment (`marqueeHits`).
List<String> marqueeHits(FloorRect marquee, Iterable<GeoItem> items) {
  final norm = normalizedRect(marquee);
  return [
    for (final it in items)
      if (rectsIntersect(norm, envelopeOf(it))) it.id,
  ];
}

/// A marquee dragged up or left, with positive width and height.
FloorRect normalizedRect(FloorRect r) => FloorRect(
  r.w < 0 ? r.x + r.w : r.x,
  r.h < 0 ? r.y + r.h : r.y,
  r.w.abs(),
  r.h.abs(),
);

/// The alignments (`ALIGNMENTS`); the toolbar offers the two centres.
enum FloorAlignment { left, hcenter, right, top, vcenter, bottom }

/// Aligns a selection on each table's ENVELOPE, returning only the items
/// that move (`alignItems`).
List<GeoItem> alignItems(List<GeoItem> items, FloorAlignment how) {
  if (items.length < 2) return const [];
  final env = [for (final it in items) (it: it, e: envelopeOf(it))];
  final minX = env.map((v) => v.e.x).reduce(math.min);
  final maxX = env.map((v) => v.e.x + v.e.w).reduce(math.max);
  final minY = env.map((v) => v.e.y).reduce(math.min);
  final maxY = env.map((v) => v.e.y + v.e.h).reduce(math.max);
  final out = <GeoItem>[];
  for (final (:it, :e) in env) {
    var dx = 0.0;
    var dy = 0.0;
    switch (how) {
      case FloorAlignment.left:
        dx = minX - e.x;
      case FloorAlignment.right:
        dx = maxX - (e.x + e.w);
      case FloorAlignment.hcenter:
        dx = (minX + maxX) / 2 - (e.x + e.w / 2);
      case FloorAlignment.top:
        dy = minY - e.y;
      case FloorAlignment.bottom:
        dy = maxY - (e.y + e.h);
      case FloorAlignment.vcenter:
        dy = (minY + maxY) / 2 - (e.y + e.h / 2);
    }
    if (dx != 0 || dy != 0) out.add(it.copyWith(x: it.x + dx, y: it.y + dy));
  }
  return out;
}

/// Equal GAPS along an axis, the outermost two held still
/// (`distributeItems`).
List<GeoItem> distributeItems(List<GeoItem> items, {bool alongX = true}) {
  if (items.length < 3) return const [];
  double pos(FloorRect e) => alongX ? e.x : e.y;
  double span(FloorRect e) => alongX ? e.w : e.h;
  final sorted = [for (final it in items) (it: it, e: envelopeOf(it))]
    ..sort((a, b) => pos(a.e).compareTo(pos(b.e)));
  final first = sorted.first.e;
  final last = sorted.last.e;
  final total = pos(last) + span(last) - pos(first);
  final used = sorted.fold<double>(0, (s, v) => s + span(v.e));
  final gap = (total - used) / (sorted.length - 1);
  final out = <GeoItem>[];
  var cursor = pos(first) + span(first) + gap;
  for (var i = 1; i < sorted.length - 1; i++) {
    final (:it, :e) = sorted[i];
    final delta = cursor - pos(e);
    if (delta != 0) {
      out.add(
        alongX ? it.copyWith(x: it.x + delta) : it.copyWith(y: it.y + delta),
      );
    }
    cursor += span(e) + gap;
  }
  return out;
}

/// What a copied table carries — blueprint only, never live status
/// (`ClipboardTable`).
class ClipboardTable {
  const ClipboardTable({
    required this.label,
    required this.seats,
    required this.shape,
    required this.w,
    required this.h,
    required this.rot,
    required this.dx,
    required this.dy,
  });

  final String label;
  final int seats;
  final String shape;
  final double w;
  final double h;
  final double rot;

  /// Offset from the copied selection's top-left.
  final double dx;
  final double dy;
}

/// The magic key that marks a floor payload (`CLIPBOARD_KIND`).
const String kClipboardKind = 'madar.floor.tables.v1';

/// The selection's blueprint as clipboard JSON (`serializeTables`).
String serializeTables(
  List<({String label, int seats, String shape})> tables,
  List<GeoItem> geo,
) {
  final minX = geo.map((g) => g.x).reduce(math.min);
  final minY = geo.map((g) => g.y).reduce(math.min);
  num n(double v) => v == v.roundToDouble() ? v.round() : v;
  return jsonEncode({
    'kind': kClipboardKind,
    'tables': [
      for (var i = 0; i < geo.length; i++)
        {
          'label': tables[i].label,
          'seats': tables[i].seats,
          'shape': tables[i].shape,
          'w': n(geo[i].w),
          'h': n(geo[i].h),
          'rot': n(geo[i].rot),
          'dx': n(geo[i].x - minX),
          'dy': n(geo[i].y - minY),
        },
    ],
  });
}

/// The tables of a floor payload, or null for anything else — a stray paste
/// never throws (`parseClipboard`).
List<ClipboardTable>? parseClipboard(String? text) {
  if (text == null || text.isEmpty) return null;
  Object? v;
  try {
    v = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (v is! Map || v['kind'] != kClipboardKind) return null;
  final list = v['tables'];
  if (list is! List || list.isEmpty) return null;
  final ok = <ClipboardTable>[];
  for (final t in list) {
    if (t is! Map) continue;
    final dx = t['dx'];
    final dy = t['dy'];
    final w = t['w'];
    if (dx is! num || dy is! num || w is! num) continue;
    final h = t['h'];
    final rot = t['rot'];
    final seats = t['seats'];
    ok.add(
      ClipboardTable(
        label: '${t['label'] ?? ''}',
        seats: seats is num ? seats.toInt() : 2,
        shape: t['shape'] is String ? t['shape'] as String : 'rect',
        w: w.toDouble(),
        h: h is num ? h.toDouble() : w.toDouble(),
        rot: rot is num ? rot.toDouble() : 0,
        dx: dx.toDouble(),
        dy: dy.toDouble(),
      ),
    );
  }
  return ok.isEmpty ? null : ok;
}

/// A label not already on the floor: a trailing " (n)" is stripped first so
/// copies of copies never stack suffixes (`uniqueLabel`).
String uniqueLabel(String base, Set<String> taken, {DateTime? now}) {
  final stem = base.replaceFirst(RegExp(r'\s+\(\d+\)$'), '');
  if (!taken.contains(stem)) return stem;
  for (var n = 2; n < 999; n++) {
    final candidate = '$stem ($n)';
    if (!taken.contains(candidate)) return candidate;
  }
  return '$stem ${(now ?? DateTime.now()).millisecondsSinceEpoch}';
}

/// "T<n+1>" from the highest numeric `T<n>` label, case-insensitive
/// (`suggestLabel`).
String suggestLabel(Iterable<String> labels) {
  var max = 0;
  final re = RegExp(r'^T(\d+)$', caseSensitive: false);
  for (final l in labels) {
    final m = re.firstMatch(l.trim());
    if (m != null) max = math.max(max, int.parse(m.group(1)!));
  }
  return 'T${max + 1}';
}

// ── Input → viewport intent (`gestures.ts`) ───────────────────────────────

/// A wheel or trackpad event's meaning: a continuous zoom, or a pan.
sealed class WheelIntent {
  const WheelIntent();
}

class WheelZoom extends WheelIntent {
  const WheelZoom(this.factor);
  final double factor;
}

class WheelPan extends WheelIntent {
  const WheelPan(this.dx, this.dy);
  final double dx;
  final double dy;
}

/// Ctrl/⌘ + wheel (and a trackpad pinch, which arrives that way) zooms,
/// exponentially so in-then-out lands where it started; a plain two-finger
/// scroll pans (`wheelIntent`). [deltaMode] 1 = lines, 2 = pages.
WheelIntent wheelIntent({
  required double deltaX,
  required double deltaY,
  int deltaMode = 0,
  bool ctrlOrMeta = false,
}) {
  const scales = [1.0, 16.0, 400.0];
  final scale = deltaMode >= 0 && deltaMode < 3 ? scales[deltaMode] : 1.0;
  final dx = deltaX * scale;
  final dy = deltaY * scale;
  if (ctrlOrMeta) return WheelZoom(math.exp(-dy * 0.01));
  return WheelPan(dx, dy);
}

/// The scale between two pinch distances; 1 on a degenerate first move.
double pinchFactor(double prev, double next) =>
    prev > 0 && next > 0 ? next / prev : 1;
