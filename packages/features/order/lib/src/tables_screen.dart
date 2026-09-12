// The tables surface: the offline floor canvas (sections + to-scale tables +
// live occupancy), the tap/long-press actions (seat here / open / move / swap /
// waitlist), and the transfer-waitlist sheet. Renders ONLY when the branch has
// a dashboard-authored layout (`OrderState.hasFloor`) — no layout, no feature.
//
// All state comes from [orderProvider] (the core's kv mirrors); every action is
// a bridge call that applies optimistically offline and queues its op.

import 'dart:async';
import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/floor_list.dart';
import 'package:feature_order/src/open_tickets_screen.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/order_screen.dart';
import 'package:feature_order/src/table_clear_prompt.dart';
import 'package:feature_order/src/waiter_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// ── Table picker sheet (hold/edit/fire flows) ────────────────────────────────

/// A picked table (or an explicit "no table").
@immutable
class TablePick {
  const TablePick(this.tableId, this.label);
  final String? tableId;
  final String? label;
}

/// Grid picker over the branch layout, grouped by section. Occupied tables are
/// disabled (except [currentTableId] — the order's own table stays pickable so
/// "keep it" is obvious). Returns null when dismissed without a choice.
Future<TablePick?> showTablePickerSheet(
  BuildContext context,
  WidgetRef ref, {
  String? currentTableId,
  bool allowClear = true,
}) async {
  final bridge = ref.read(bridgeProvider);
  final layout = ref.read(orderProvider).floorLayout;
  if (layout == null) return null;
  return await showMadarSheet<TablePick>(
    context,
    size: SheetSize.hug,
    builder: (sheetContext) => _TablePickerBody(
      layout: layout,
      currentTableId: currentTableId,
      allowClear: allowClear,
      title: bridge.tr(key: 'tables.pick'),
      clearLabel: bridge.tr(key: 'tables.no_table'),
      seatsWord: bridge.tr(key: 'tables.seats'),
      noSectionLabel: bridge.tr(key: 'tables.no_section'),
      words: TableStatusWords.of(bridge),
    ),
  );
}

/// The picker IS the floor: the same to-scale canvas the dashboard authored
/// (and the tables screen renders), with free tables tappable. No chip
/// stand-ins — the teller picks by pointing at the room.
class _TablePickerBody extends StatefulWidget {
  const _TablePickerBody({
    required this.layout,
    required this.currentTableId,
    required this.allowClear,
    required this.title,
    required this.clearLabel,
    required this.seatsWord,
    required this.noSectionLabel,
    required this.words,
  });

  final FloorLayoutView layout;
  final String? currentTableId;
  final bool allowClear;
  final String title;
  final String clearLabel;
  final String seatsWord;
  final String noSectionLabel;
  final TableStatusWords words;

  @override
  State<_TablePickerBody> createState() => _TablePickerBodyState();
}

class _TablePickerBodyState extends State<_TablePickerBody> {
  String? _sectionId;

  @override
  void initState() {
    super.initState();
    // Open on the section holding the order's CURRENT table, else the first.
    final current = widget.layout.tables
        .where((t) => t.id == widget.currentTableId)
        .firstOrNull;
    _sectionId = current?.sectionId ?? widget.layout.sections.firstOrNull?.id;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final layout = widget.layout;
    // Same rule as the tables screen: section tabs plus an "unassigned" tab,
    // so a table outside every section is still pickable.
    final sectionIds = {for (final s in layout.sections) s.id};
    final orphans = layout.tables
        .where((t) => t.sectionId == null || !sectionIds.contains(t.sectionId))
        .toList(growable: false);
    final tabs = <(String, String)>[
      for (final s in layout.sections) (s.id, s.name),
      if (orphans.isNotEmpty) (_kNoSection, widget.noSectionLabel),
    ];
    int countIn(String id) => id == _kNoSection
        ? orphans.length
        : layout.tables.where((t) => t.sectionId == id).length;
    final activeId = tabs.any((t) => t.$1 == _sectionId)
        ? _sectionId!
        : (tabs.where((t) => countIn(t.$1) > 0).firstOrNull?.$1 ??
              tabs.firstOrNull?.$1 ??
              _kNoSection);
    final active = layout.sections.where((s) => s.id == activeId).firstOrNull;
    final tables = activeId == _kNoSection
        ? orphans
        : layout.tables
              .where((t) => t.sectionId == activeId)
              .toList(growable: false);
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: MadarType.h3.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Space.lg),
          if (tabs.length > 1) ...[
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final (id, name) in tabs)
                  GestureDetector(
                    onTap: () {
                      MadarHaptics.selection();
                      setState(() => _sectionId = id);
                    },
                    child: Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: Space.lg,
                        vertical: Space.sm,
                      ),
                      decoration: BoxDecoration(
                        color: id == activeId ? colors.accent : colors.surface,
                        borderRadius: BorderRadius.circular(Radii.pill),
                        border: Border.all(
                          color: id == activeId ? colors.accent : colors.border,
                        ),
                      ),
                      child: Text(
                        name,
                        style: MadarType.label.copyWith(
                          fontWeight: FontWeight.w700,
                          color: id == activeId
                              ? colors.textOnAccent
                              : colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.md),
          ],
          Flexible(
            child: SingleChildScrollView(
              child: FloorCanvas(
                section: active,
                tables: tables,
                seatsWord: widget.seatsWord,
                words: widget.words,
                tickets: const [],
                // A table is pickable when nothing sits on it — or it's the
                // order's OWN current table ("keep it" stays obvious).
                enabledOf: (t) =>
                    t.status != 'seated' || t.id == widget.currentTableId,
                selectedId: widget.currentTableId,
                onTap: (t) {
                  MadarHaptics.selection();
                  Navigator.of(context).maybePop(TablePick(t.id, t.label));
                },
              ),
            ),
          ),
          if (widget.allowClear) ...[
            const SizedBox(height: Space.lg),
            MadarButton(
              label: widget.clearLabel,
              variant: MadarButtonVariant.outline,
              onTap: () =>
                  Navigator.of(context).maybePop(const TablePick(null, null)),
            ),
          ],
        ],
      ),
    );
  }
}

/// The translated state vocabulary, passed into the canvas so the cells can
/// SAY their state rather than only colour it (and so screen readers can read
/// it out). Built once per screen from the bridge's translations.
@immutable
class TableStatusWords {
  const TableStatusWords({
    required this.free,
    required this.held,
    required this.seated,
    required this.needsClearing,
    this.reserved = '',
    this.timeOf,
  });

  /// The vocabulary as the bridge translates it.
  factory TableStatusWords.of(MadarBridge bridge) => TableStatusWords(
    free: bridge.tr(key: 'tables.free'),
    held: bridge.tr(key: 'tables.held_res'),
    seated: bridge.tr(key: 'tables.seated'),
    needsClearing: bridge.tr(key: 'tables.needs_clearing'),
    reserved: bridge.tr(key: 'tables.reserved'),
    timeOf: (iso) => bridge.formatTime(rfc3339: iso, style: TimeStyle.time),
  );

  final String free;
  final String held;
  final String seated;
  final String needsClearing;

  /// A booked party's hold has begun (the table is kept for them).
  final String reserved;

  /// Branch-zone clock label for an RFC3339 instant (the booking's time on
  /// the pill). Null in tests → the pill shows the guest alone.
  final String Function(String rfc3339)? timeOf;

  /// The word for one table's current state.
  String wordFor(FloorTableStateView t, {required bool occupied}) {
    if (occupied || t.status == 'seated' || tableBookingSeated(t)) {
      return seated;
    }
    if (tableNeedsClearing(t, occupied: occupied)) return needsClearing;
    if (tableIsReserved(t)) return reserved;
    return t.status == 'held' ? held : free;
  }
}

/// A confirmed booking's hold window has begun on this table: it is kept for
/// that party until they arrive (or are marked a no-show). Derived from the
/// booking's `held_from` by the clock — the server never writes it to status.
bool tableIsReserved(FloorTableStateView t, {DateTime? now}) {
  if (t.bookingId == null || t.bookingStatus != 'confirmed') return false;
  final from = DateTime.tryParse(t.bookingHeldFrom ?? '');
  if (from == null) return false;
  return !from.isAfter(now ?? DateTime.now());
}

/// A booked party was seated (the POS said so) but no ticket sits on the
/// table yet — the table reads as taken, not as free.
bool tableBookingSeated(FloorTableStateView t) =>
    t.bookingId != null && t.bookingStatus == 'seated';

/// A booking claims this table later today (before or after its hold began).
bool tableHasBooking(FloorTableStateView t) =>
    t.bookingId != null && t.bookingStatus == 'confirmed';

/// True when a table is paid-and-vacated but not yet bussed. A checkout no
/// longer hands the table straight back to the room — only a human does — so
/// this state is real, common, and must never read as available.
///
/// A table with somebody ON it is never "needs clearing", whatever its stored
/// status says. That can happen honestly — a party seated onto a table the
/// previous one left dirty, a status write that lost a race — and in every such
/// case the live occupant is the truth: telling a teller to bus an occupied
/// table would have them clear a party that is still eating.
bool tableNeedsClearing(FloorTableStateView t, {bool occupied = false}) =>
    t.status == 'dirty' && !occupied;

/// Status → tone. Four states, four tones: taken (accent), held for a party
/// (warning), needs clearing (danger — it is the one state that owes the room
/// WORK), available (success).
Color tableTone(
  MadarColors colors,
  FloorTableStateView t, {
  bool occupied = false,
}) {
  if (occupied || t.status == 'seated' || tableBookingSeated(t)) {
    return colors.accent;
  }
  if (tableNeedsClearing(t, occupied: occupied)) return colors.danger;
  return t.status == 'held' || tableIsReserved(t)
      ? colors.warning
      : colors.success;
}

/// Corner status icon, so state never rests on colour alone: taken = people,
/// held for a party = hand, needs clearing = sparkles, available = nothing
/// (the quiet default, which also carries a seat count no other state shows).
String? tableStatusIcon(FloorTableStateView t, {required bool occupied}) {
  if (occupied || t.status == 'seated' || tableBookingSeated(t)) {
    return 'person.2';
  }
  if (tableNeedsClearing(t, occupied: occupied)) return 'sparkles';
  if (tableIsReserved(t)) return 'calendar.days';
  return t.status == 'held' ? 'hand.raised' : null;
}

/// "How long has this table been sitting" — `45m`, `2h 10m`. Null when the
/// stamp is missing or in the future (clock skew), so nothing odd renders.
String? elapsedLabel(String? sinceIso, {DateTime? now}) {
  if (sinceIso == null || sinceIso.isEmpty) return null;
  final since = DateTime.tryParse(sinceIso);
  if (since == null) return null;
  final mins = (now ?? DateTime.now()).difference(since.toLocal()).inMinutes;
  if (mins < 1) return 'now';
  if (mins < 60) return '${mins}m';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// How far a table's chairs (and its occupant pill) reach beyond its own box.
/// Mirrors the dashboard's `SEAT_ALLOWANCE` so both frame the room the same.
const double kSeatAllowance = 22;

/// Ceiling on how far framing may magnify the room. Fitting content to the
/// viewport is right for a big floor and absurd for a small one — a two-table
/// bar would otherwise render each table the size of a dinner plate. Mirrors
/// the spirit of the dashboard's zoom ceiling.
const double kMaxFloorScale = 1.6;

/// Pinch-zoom ceiling for the CANVAS ITSELF — the transform a finger drives —
/// as distinct from [kMaxFloorScale], which only bounds the initial FIT before
/// anyone has touched the screen. A terrace, an inside, and a bar drawn at the
/// fitted scale still leaves a two-top too small to tap accurately on a cheap
/// tablet from across the counter, so zooming in gets far more headroom than
/// the fit ever grants.
const double kFloorViewerMaxScale = 4;

/// Pinch-zoom floor for the same transform — enough to pull back and see a
/// whole section from one gesture, never so far that a table stops being a
/// target a finger can find again.
const double kFloorViewerMinScale = 0.5;

/// The smallest a table may be drawn, in logical pixels.
///
/// A FLOOR under the fit, not a preference. Fitting a whole room to the
/// viewport is the right instinct on a desk and ruinous on a phone: a thirty
/// table dining room in 360 points scales to about 0.18, which draws an 80-unit
/// table at fourteen pixels — smaller than the fingertip meant to press it, and
/// far below the 44-point target both platforms ask for.
///
/// So the room stops shrinking here and starts SCROLLING instead. A plan you
/// have to pan is usable; a plan you cannot hit is not.
const double kMinTablePx = 44;

/// The shortest edge of the smallest table in the room, in world units.
///
/// The floor is set by the SMALLEST table, not the average: it is the one a
/// finger misses first, and a room is only as usable as its worst target.
double smallestTableEdge(List<PlacedTable> placed) {
  var smallest = double.infinity;
  for (final p in placed) {
    final edge = math.min(p.table.width, p.table.height);
    if (edge > 0 && edge < smallest) smallest = edge;
  }
  return smallest.isFinite ? smallest : 80;
}

/// How much to magnify the room.
///
/// Fit it to the viewport, then bound that fit at both ends:
///
///   * never past [kMaxFloorScale], or a two-table bar draws each table the
///     size of a dinner plate;
///   * never below the scale that keeps the smallest table [kMinTablePx]
///     across, because a table smaller than the finger pressing it is not a
///     control. Below that the room stops shrinking and starts scrolling.
///
/// The minimum wins when the two disagree. A plan you have to pan is usable; a
/// plan you cannot hit is not.
double floorScale({
  required double viewportWidth,
  required double roomWidth,
  required double smallestTable,
}) {
  if (roomWidth <= 0 || viewportWidth <= 0) return 1;
  final fit = viewportWidth / roomWidth;
  final minScale = smallestTable > 0 ? kMinTablePx / smallestTable : fit;
  final capped = math.min(fit, kMaxFloorScale);
  return math.max(capped, minScale);
}

/// The world box the room actually occupies, chairs included.
///
/// The dashboard's floor is an UNBOUNDED plane — a table may sit at negative
/// coordinates or far past the section's old nominal size. Framing to a stored
/// canvas width (which nothing authors any more) silently crops those tables
/// off the POS, so the two surfaces stop showing the same room. Frame what is
/// THERE instead.
({double left, double top, double width, double height}) floorBounds(
  List<PlacedTable> placed,
) {
  if (placed.isEmpty) {
    return (left: 0, top: 0, width: 1000, height: 700);
  }
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final p in placed) {
    // A rotated table sweeps a wider box; the diagonal is the safe envelope.
    final r =
        math.sqrt(
          p.table.width * p.table.width + p.table.height * p.table.height,
        ) /
        2;
    final cx = p.x + p.table.width / 2;
    final cy = p.y + p.table.height / 2;
    minX = math.min(minX, cx - r);
    minY = math.min(minY, cy - r);
    maxX = math.max(maxX, cx + r);
    maxY = math.max(maxY, cy + r);
  }
  minX -= kSeatAllowance;
  minY -= kSeatAllowance;
  maxX += kSeatAllowance;
  maxY += kSeatAllowance;
  return (
    left: minX,
    top: minY,
    width: math.max(1, maxX - minX),
    height: math.max(1, maxY - minY),
  );
}

/// Display position of one table (spread applied — see [spreadTables]).
typedef PlacedTable = ({FloorTableStateView table, double x, double y});

/// Tables created before the dashboard floor pass (QR-era rows) all carry the
/// default geometry and PILE UP at the same point — a stack of identical
/// squares. Display-only fix: any group sharing an exact position is flowed
/// into a grid below the arranged content, so every table is visible and
/// tappable until the dashboard arranges the room. Authored positions are
/// never touched. Returns the placements + the canvas height they need.
(List<PlacedTable>, double) spreadTables(
  List<FloorTableStateView> tables,
  double canvasW,
  double canvasH,
) {
  const cell = 120.0;
  const pad = 16.0;
  final byPos = <String, int>{};
  for (final t in tables) {
    final key = '${t.posX.round()}:${t.posY.round()}';
    byPos[key] = (byPos[key] ?? 0) + 1;
  }
  bool stacked(FloorTableStateView t) =>
      (byPos['${t.posX.round()}:${t.posY.round()}'] ?? 0) > 1;

  // Grid rows start below whatever IS arranged (or at the top when nothing is).
  var gridTop = pad;
  for (final t in tables) {
    if (!stacked(t)) gridTop = math.max(gridTop, t.posY + t.height + pad);
  }
  final perRow = math.max(1, ((canvasW - pad) / cell).floor());
  var slot = 0;
  final placed = <PlacedTable>[];
  var bottom = canvasH;
  for (final t in tables) {
    if (!stacked(t)) {
      placed.add((table: t, x: t.posX, y: t.posY));
      continue;
    }
    final x = pad + (slot % perRow) * cell;
    final y = gridTop + (slot ~/ perRow) * cell;
    slot += 1;
    placed.add((table: t, x: x, y: y));
    bottom = math.max(bottom, y + t.height + pad);
  }
  return (placed, bottom);
}

/// How much of a long bill the ticket sheet shows before it scrolls — enough
/// for a real dinner, short enough that the actions never leave the screen.
const double _kBillMaxHeight = 260;

/// The shared floor canvas — one renderer for the tables screen AND the table
/// picker, so the POS always shows the room the dashboard drew (same glyphs,
/// same scale rules). Behavior is injected: tap, long-press, per-table enable,
/// selection ring, swap arming.
class FloorCanvas extends StatelessWidget {
  const FloorCanvas({
    required this.section,
    required this.tables,
    required this.tickets,
    required this.seatsWord,
    required this.words,
    required this.onTap,
    this.onLongPress,
    this.enabledOf,
    this.selectedId,
    this.swapArmedId,
    this.zoomable = false,
    super.key,
  });

  final FloorSectionInfo? section;
  final List<FloorTableStateView> tables;
  final List<TicketView> tickets;
  final String seatsWord;

  /// Translated state vocabulary for the cells (and their screen-reader
  /// labels), so a table's state is never colour-only.
  final TableStatusWords words;
  final ValueChanged<FloorTableStateView> onTap;
  final ValueChanged<FloorTableStateView>? onLongPress;

  /// Per-table interactivity (picker mode); null = everything tappable.
  final bool Function(FloorTableStateView)? enabledOf;
  final String? selectedId;
  final String? swapArmedId;

  /// Pinch-zoom + pan (the tables screen; the picker stays a plain scroll).
  final bool zoomable;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    // The section's stored size is only a hint for laying out never-arranged
    // (QR-era) tables — it is NOT the extent of the room. The dashboard stopped
    // authoring it when the canvas became unbounded.
    final spreadW = (section?.canvasW ?? 1000).toDouble();
    final spreadH = (section?.canvasH ?? 700).toDouble();
    final (placed, _) = spreadTables(tables, spreadW, spreadH);
    final bounds = floorBounds(placed);
    TicketView? ticketOn(String tableId) => tickets
        .where((t) => t.tableId == tableId && isLiveTicket(t))
        .firstOrNull;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.md),
      // NO fill here on purpose. A boxed grey panel behind the room read as a
      // dirty smudge under both themes and fought the app's own background
      // for attention — the tables are the thing that should read, not the
      // slab they sit on. The faint dot grid below is the only "ground" the
      // room gets, and only a hairline now marks where the canvas begins.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.borderLight),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = floorScale(
              viewportWidth: constraints.maxWidth,
              roomWidth: bounds.width,
              smallestTable: smallestTableEdge(placed),
            );
            final drawnWidth = bounds.width * scale;
            // When the room is narrower than the viewport, centre it rather
            // than pinning it to the left edge. When it is WIDER — the phone
            // case, where the minimum table size beat the fit — there is
            // nothing to centre and the canvas pans instead.
            final dx = math.max(0, (constraints.maxWidth - drawnWidth) / 2);
            final canvasWidth = math.max(constraints.maxWidth, drawnWidth);
            final canvasHeight = bounds.height * scale;
            final child = CustomPaint(
              painter: _FloorGridPainter(
                pitch: 50 * scale,
                color: colors.border.withValues(alpha: 0.55),
              ),
              child: SizedBox(
                width: canvasWidth,
                height: canvasHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final p in placed)
                      // Positioned, NOT PositionedDirectional: a floor plan is
                      // PHYSICAL space. `start` measures from the right in
                      // Arabic, which mirrors the whole room — the table by the
                      // door would render by the window, and the POS would
                      // disagree with the layout the dashboard authored.
                      Positioned(
                        // Offset by the frame's origin, so a table authored at
                        // a negative coordinate lands on screen rather than
                        // outside it.
                        left: dx + (p.x - bounds.left) * scale,
                        top: (p.y - bounds.top) * scale,
                        width: p.table.width * scale,
                        height: p.table.height * scale,
                        // One table's realtime update (a ticket ticks in, a
                        // status flips) must not force every OTHER table in
                        // the room to repaint — without this every cell shares
                        // one picture layer, so a thirty-table floor redraws
                        // whole on every tick for a change to one cell.
                        child: RepaintBoundary(
                          child: Transform.rotate(
                            angle: p.table.rotation * math.pi / 180,
                            child: Opacity(
                              opacity: (enabledOf?.call(p.table) ?? true)
                                  ? 1
                                  : 0.38,
                              child: _TableCell(
                                table: p.table,
                                ticket: ticketOn(p.table.id),
                                scale: scale,
                                seatsWord: seatsWord,
                                words: words,
                                swapArmed: swapArmedId == p.table.id,
                                selected: selectedId == p.table.id,
                                onTap: (enabledOf?.call(p.table) ?? true)
                                    ? () => onTap(p.table)
                                    : null,
                                onLongPress: onLongPress == null
                                    ? null
                                    : () => onLongPress!(p.table),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );

            // The real pannable grid: a BOUNDED window (this screen now hands
            // the canvas an `Expanded` region rather than an unbounded
            // scroller) panning and pinch-zooming a room that is free to be
            // any size — a two-table bar or a forty-table terrace, in both
            // axes, not just the horizontal scroll a too-wide room used to
            // fall back to. `constrained: false` is what makes the room draw
            // at its own full size instead of being squeezed to the viewport.
            if (zoomable && constraints.hasBoundedHeight) {
              return InteractiveViewer(
                constrained: false,
                minScale: kFloorViewerMinScale,
                maxScale: kFloorViewerMaxScale,
                boundaryMargin: const EdgeInsets.all(80),
                child: child,
              );
            }

            // A caller that still hands this an UNBOUNDED height (nested in a
            // vertical scroller) has no fixed window to pan within —
            // `constrained: false` above would then ask this widget to be as
            // tall as an infinite constraint and throw during layout. This is
            // the historical bug the widget test below pins, so anything
            // without a bounded window falls back to the old, narrower shapes:
            // a horizontal scroll when the fit lost to the minimum table size,
            // a self-sized (but still pinchable) `InteractiveViewer` otherwise.
            final needsPan = canvasWidth > constraints.maxWidth + 0.5;
            if (needsPan) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: child,
              );
            }
            if (!zoomable) return child;
            return InteractiveViewer(
              maxScale: kFloorViewerMaxScale,
              child: child,
            );
          },
        ),
      ),
    );
  }
}

/// The faint dot grid under the tables — pure ground, never louder than the
/// glyphs. Pitch follows the canvas scale so it stays honest to the room.
class _FloorGridPainter extends CustomPainter {
  const _FloorGridPainter({required this.pitch, required this.color});

  final double pitch;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (pitch < 8) return; // too dense to mean anything — skip, not clutter
    final paint = Paint()..color = color;
    for (var x = pitch; x < size.width; x += pitch) {
      for (var y = pitch; y < size.height; y += pitch) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_FloorGridPainter old) =>
      old.pitch != pitch || old.color != color;
}

// ── The tables screen (canvas + actions + waitlist) ──────────────────────────

class TablesScreen extends ConsumerStatefulWidget {
  const TablesScreen({this.isHome = false, super.key});

  /// This screen IS the app's home, because the shop puts every sale on a
  /// table. There is nothing behind it to go back to, so it shows no back
  /// button — and picking a table PUSHES the order screen rather than popping
  /// to one that was never there.
  final bool isHome;

  @override
  ConsumerState<TablesScreen> createState() => _TablesScreenState();
}

/// Tab id for tables that belong to no section (or an orphaned one).
const String _kNoSection = '__no_section__';

class _TablesScreenState extends ConsumerState<TablesScreen>
    with RealtimeGatedPoll<TablesScreen> {
  String? _sectionId;

  /// Swap/move mode: the FIRST table tapped, awaiting the second.
  String? _swapFrom;

  /// Plan or list.
  ///
  /// A scale drawing answers "where is that table" and nothing else. It fits a
  /// whole room onto a phone, so a busy floor renders as unreadable rectangles,
  /// and it is silent — how long a party has been sitting, what their bill is,
  /// whether the kitchen has their food are all a tap away each. The list says
  /// all of it, sorted by what needs a person. Both are the same room and the
  /// same actions; this only chooses how it is drawn.
  bool _asList = false;

  /// A reserved table flips by the clock (`held_from`), not by an event — a
  /// once-a-minute tick keeps the canvas and the counts honest between pulls.
  Timer? _clock;

  OrderNotifier get _notifier => ref.read(orderProvider.notifier);

  /// The live ticket on a table, if any. `settled` and `voided` have left the
  /// floor; only `open` and `ready` occupy a table.
  /// The live ticket on a table, if there is one.
  ///
  /// `queued` counts. A round fired with no network — or fired a second ago and
  /// not yet pulled back — is a real bill on a real table, and leaving it out
  /// made the floor treat a table it had just taken as untouchable.
  TicketView? _ticketOn(List<TicketView> tickets, String tableId) =>
      tickets.where((t) => t.tableId == tableId && isLiveTicket(t)).firstOrNull;
  String _tr(String key) => ref.read(bridgeProvider).tr(key: key);

  @override
  void initState() {
    super.initState();
    // The mirror is only as fresh as the last pull — fetch on entry so a
    // dashboard layout edit is on screen the moment the teller opens tables.
    unawaited(_notifier.syncFloor());
    _clock = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    // The teller may be standing on this screen when their own sale lands.
    listenForTableClear(context, ref);
    // A floor event landed (dashboard re-arranged the room, another till
    // seated a party) → re-pull. Realtime is the fast path…
    ref.listen(floorTickProvider, (_, _) => unawaited(_notifier.syncFloor()));
    // …and this is the fallback while the SSE stream is down.
    realtimeGatedPoll(
      interval: const Duration(seconds: 20),
      onPoll: () => unawaited(_notifier.syncFloor()),
    );
    final layout = ref.watch(orderProvider.select((s) => s.floorLayout));
    final queue = ref.watch(orderProvider.select((s) => s.transferQueue));
    final isWaiter = ref.watch(orderProvider.select((s) => s.isWaiter));
    final tickets = ref.watch(orderProvider.select((s) => s.openTickets));
    final sections = layout?.sections ?? const <FloorSectionInfo>[];
    final allTables = layout?.tables ?? const <FloorTableStateView>[];

    // Tabs = the authored sections, PLUS an "unassigned" tab whenever tables
    // sit outside every section (QR-era rows carry no section, and a deleted
    // section leaves its tables orphaned). Without this they'd be filtered
    // out of every tab and the room would look empty.
    final seatedCount = allTables.where((t) => t.status == 'seated').length;
    // Kept for a booked party. `held` was also a teller's own short-lived hold
    // on a table; nothing writes it any more, so a reservation is the only way
    // a table is kept for someone.
    final heldCount = allTables
        .where(
          (t) =>
              t.status != 'seated' &&
              !tableBookingSeated(t) &&
              (t.status == 'held' || tableIsReserved(t)),
        )
        .length;
    final arrivals = ref.watch(orderProvider.select((s) => s.arrivals));
    // The work the floor owes itself: paid tables still waiting on a bus.
    final dirtyTables = allTables
        .where(
          (t) =>
              tableNeedsClearing(t, occupied: _ticketOn(tickets, t.id) != null),
        )
        .toList(growable: false);
    final sectionIds = {for (final s in sections) s.id};
    final orphans = allTables
        .where((t) => t.sectionId == null || !sectionIds.contains(t.sectionId))
        .toList(growable: false);
    final tabs = <(String, String)>[
      for (final s in sections) (s.id, s.name),
      if (orphans.isNotEmpty) (_kNoSection, _tr('tables.no_section')),
    ];
    // Default to the first tab that actually HAS tables: landing on an empty
    // authored section while every table sits unassigned reads as "the app
    // lost my floor".
    int countIn(String id) => id == _kNoSection
        ? orphans.length
        : allTables.where((t) => t.sectionId == id).length;
    final activeId = tabs.any((t) => t.$1 == _sectionId)
        ? _sectionId!
        : (tabs.where((t) => countIn(t.$1) > 0).firstOrNull?.$1 ??
              tabs.firstOrNull?.$1 ??
              _kNoSection);
    final active = sections.where((s) => s.id == activeId).firstOrNull;
    final tables = activeId == _kNoSection
        ? orphans
        : allTables
              .where((t) => t.sectionId == activeId)
              .toList(growable: false);

    // A phone. Labels give way to icons, the title steps down a size, and the
    // padding tightens — the header row was already one button past what 360
    // points fits, and it will only get more crowded.
    final compact = MediaQuery.sizeOf(context).width < Responsive.tablet;

    // Pushed from the order screen unless it IS the home tab — and when it
    // is pushed there is no shell above it, so the header has to pay the
    // status-bar inset or the back tile sits under the clock.
    return MadarPageScaffold(
      safeTop: !widget.isHome,
      gutter: false,
      body: Column(
        children: [
          // THE house header, like every other screen. This screen used to
          // draw its own — a Material IconButton, a different title size, no
          // surface bar and no hairline — so the one screen a waiter stands in
          // front of all shift was the one that did not look like the app.
          MadarHeader(
            title: _tr('tables.title'),
            safeTop: !widget.isHome,
            // Nothing behind home to go back to.
            onBack: widget.isHome
                ? null
                : () => Navigator.of(context).maybePop(),
            actions: [
              // Bookings and the waitlist.
              //
              // On a phone these lose their words and keep their counts. A
              // label is the first thing to give up when the row will not fit
              // — an icon with "3" beside it still says everything that
              // matters, and the alternative was a header that overflowed its
              // own screen.
              MadarButton(
                label: compact
                    ? (arrivals.isEmpty ? '' : '${arrivals.length}')
                    : (arrivals.isEmpty
                          ? _tr('tables.arrivals')
                          : '${_tr('tables.arrivals')} · ${arrivals.length}'),
                icon: 'calendar.days',
                variant: MadarButtonVariant.outline,
                size: MadarButtonSize.compact,
                onTap: () => unawaited(_openArrivals()),
              ),
              MadarButton(
                label: compact
                    ? (queue.isEmpty ? '' : '${queue.length}')
                    : (queue.isEmpty
                          ? _tr('tables.waitlist')
                          : '${_tr('tables.waitlist')} · ${queue.length}'),
                icon: 'clock',
                variant: MadarButtonVariant.outline,
                size: MadarButtonSize.compact,
                onTap: () => unawaited(_openWaitlist()),
              ),
              // Plan or list. A control for the whole screen, so it belongs
              // with the screen's other controls. It used to sit on the filter
              // row, which on a one-area floor is otherwise empty — leaving one
              // button floating in a band of nothing above the room.
              MadarButton(
                // Icon only, at every width. The glyph IS the label — a grid
                // means "show me the room", a list means "show me the queue" —
                // and the two beside it already carry words and counts. Three
                // labelled buttons is what overflowed this row in the first
                // place.
                label: '',
                icon: _asList ? 'square.grid.2x2' : 'list.bullet',
                tooltip: _asList
                    ? _tr('tables.view_plan')
                    : _tr('tables.view_list'),
                variant: MadarButtonVariant.outline,
                size: MadarButtonSize.compact,
                onTap: () => setState(() => _asList = !_asList),
              ),
            ],
            // The room at a glance, on its own full-width line. These chips
            // carry the state vocabulary too, so no separate legend is needed
            // — one row that both counts and teaches. It used to be squeezed
            // in beside the title, fighting the buttons for what was left.
            below: allTables.isEmpty
                ? null
                : Wrap(
                    spacing: Space.md,
                    runSpacing: Space.xs,
                    children: [
                      _CountChip(
                        tone: colors.accent,
                        solid: true,
                        label: _tr('tables.seated'),
                        count: seatedCount,
                      ),
                      _CountChip(
                        tone: colors.success,
                        label: _tr('tables.free'),
                        count:
                            allTables.length -
                            seatedCount -
                            heldCount -
                            dirtyTables.length,
                      ),
                      if (dirtyTables.isNotEmpty)
                        _CountChip(
                          tone: colors.danger,
                          label: _tr('tables.needs_clearing'),
                          count: dirtyTables.length,
                        ),
                      if (heldCount > 0)
                        _CountChip(
                          tone: colors.warning,
                          label: _tr('tables.held_res'),
                          count: heldCount,
                        ),
                    ],
                  ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsetsDirectional.all(
                  compact ? Space.md : Space.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Areas, when there is more than one. A single-area floor
                    // has nothing to filter, so the row is not drawn at all
                    // rather than reserving a strip of empty chrome above the
                    // room.
                    if (tabs.length > 1) ...[
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          for (final (id, name) in tabs)
                            _sectionChip(
                              id: id,
                              name: name,
                              selected: id == activeId,
                              count: countIn(id),
                            ),
                        ],
                      ),
                      const SizedBox(height: Space.md),
                    ],
                    if (_swapFrom != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          top: Space.md,
                        ),
                        child: _swapBanner(colors),
                      ),
                    if (_swapFrom != null) const SizedBox(height: Space.md),
                    Expanded(
                      // An empty room still renders the screen (header + back) and
                      // says why — never a dead-end blank page.
                      child: allTables.isEmpty
                          ? EmptyState(
                              icon: 'square.grid.2x2',
                              title: _tr('tables.empty_title'),
                              message: _tr('tables.empty_desc'),
                              actionLabel: _tr('chrome.sync_data'),
                              onAction: () => unawaited(_notifier.syncFloor()),
                            )
                          : _asList
                          ? FloorListView(
                              rows: buildFloorRows(
                                tables: tables,
                                ticketOn: (id) => _ticketOn(tickets, id),
                                sectionName: (sid) => sid == null
                                    ? null
                                    : layout?.sections
                                          .where((s) => s.id == sid)
                                          .firstOrNull
                                          ?.name,
                                now: DateTime.now(),
                              ),
                              now: DateTime.now(),
                              currency: ref.watch(
                                orderProvider.select((s) => s.currency),
                              ),
                              words: FloorListWords.of(
                                ref.read(bridgeProvider),
                              ),
                              armedId: _swapFrom,
                              onTap: (t) => unawaited(
                                _onTablePrimary(
                                  t,
                                  _ticketOn(tickets, t.id),
                                  isWaiter: isWaiter,
                                ),
                              ),
                              onLongPress: (t) => unawaited(
                                _onTableMenu(
                                  t,
                                  _ticketOn(tickets, t.id),
                                  isWaiter: isWaiter,
                                ),
                              ),
                            )
                          // No outer scroller: the canvas gets this `Expanded`
                          // slot as a BOUNDED window, which is what lets
                          // `FloorCanvas` pan and pinch-zoom the room in both
                          // axes. Keyed by section so switching areas
                          // (terrace → inside → bar) cross-fades into the new
                          // room instead of snapping.
                          : AnimatedSwitcher(
                              duration: MediaQuery.of(context).disableAnimations
                                  ? Duration.zero
                                  : MotionSpec.gentleDuration,
                              child: _canvas(
                                active,
                                tables,
                                tickets,
                                isWaiter: isWaiter,
                                colors: colors,
                                key: ValueKey(activeId),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionChip({
    required String id,
    required String name,
    required bool selected,
    int? count,
  }) {
    final colors = context.madarColors;
    return GestureDetector(
      onTap: () {
        MadarHaptics.selection();
        setState(() => _sectionId = id);
      },
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.surface,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: selected ? colors.accent : colors.border),
        ),
        child: Text(
          count == null || count == 0 ? name : '$name · $count',
          style: MadarType.label.copyWith(
            fontWeight: FontWeight.w700,
            color: selected ? colors.textOnAccent : colors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _swapBanner(MadarColors colors) => Container(
    padding: const EdgeInsetsDirectional.all(Space.md),
    decoration: BoxDecoration(
      color: colors.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(Radii.sm),
      border: Border.all(color: colors.accent),
    ),
    child: Row(
      children: [
        MadarIcon('arrow.triangle.2.circlepath', tint: colors.accent),
        const SizedBox(width: Space.md),
        Expanded(child: Text(_tr('tables.swap_pick'), style: MadarType.label)),
        GestureDetector(
          onTap: () => setState(() => _swapFrom = null),
          child: MadarIcon('xmark.circle', tint: colors.textMuted),
        ),
      ],
    ),
  );

  Widget _canvas(
    FloorSectionInfo? section,
    List<FloorTableStateView> tables,
    List<TicketView> tickets, {
    required bool isWaiter,
    required MadarColors colors,
    Key? key,
  }) {
    TicketView? ticketOn(String tableId) => _ticketOn(tickets, tableId);
    return FloorCanvas(
      key: key,
      section: section,
      tables: tables,
      tickets: tickets,
      seatsWord: _tr('tables.seats'),
      words: TableStatusWords.of(ref.read(bridgeProvider)),
      zoomable: true,
      swapArmedId: _swapFrom,
      // One gesture, one sheet. The long-press used to open a "settings"
      // submenu whose only live action already sat on the tap sheet, and whose
      // other three had empty bodies — status is derived and sections are
      // dashboard-authored, so they could never have done anything. Both
      // gestures now open the sheet for what that table actually is.
      // Tap does the thing you came to do; long-press is everything else.
      //
      // Both used to open the same sheet, so the commonest act in the room —
      // seating a party — cost a tap, a modal, and a second tap, and
      // long-press did nothing it did not already do.
      onTap: (t) =>
          unawaited(_onTablePrimary(t, ticketOn(t.id), isWaiter: isWaiter)),
      onLongPress: (t) =>
          unawaited(_onTableMenu(t, ticketOn(t.id), isWaiter: isWaiter)),
    );
  }

  // ── actions ────────────────────────────────────────────────────────────────

  /// Finish a pending move, or say there is none. Shared by both gestures so a
  /// half-finished move cannot be left hanging by long-pressing out of it.
  bool _completedMove(FloorTableStateView t) {
    final from = _swapFrom;
    if (from == null) return false;
    setState(() => _swapFrom = null);
    if (from != t.id) unawaited(_notifier.swapTables(from, t.id));
    return true;
  }

  /// Leave for the order screen with this table's work in hand.
  ///
  /// Two shapes, one intent. Where the floor was pushed FROM the order screen,
  /// popping returns to it. Where the floor is home — a shop that puts every
  /// sale on a table — there is nothing behind it, so the order screen is
  /// pushed and takes itself away again once the round is in.
  Future<void> _toOrderScreen() async {
    if (!mounted) return;
    if (widget.isHome) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const OrderScreen()));
      return;
    }
    await Navigator.of(context).maybePop();
  }

  /// ONE act per state, on a single tap.
  ///
  /// The order below is the order a table's states actually exclude each other:
  /// a live bill beats a booking (the party is already sitting there), and a
  /// table waiting to be bussed beats a free one.
  ///
  /// The split at the end is the whole shape of the floor. A table with a BILL
  /// opens its bill — rounds, running total, and the two things you do with a
  /// party who has ordered: add to it, or take their money. A table with a
  /// party but NOTHING ORDERED YET goes straight to the menu, because there is
  /// no bill to look at and the only reason anyone taps it is to take their
  /// first order.
  Future<void> _onTablePrimary(
    FloorTableStateView t,
    TicketView? ticket, {
    required bool isWaiter,
  }) async {
    if (_completedMove(t)) return;

    // A bill on the table: show it.
    if (ticket != null) {
      await _ticketSheet(t, ticket, isWaiter: isWaiter);
      return;
    }
    // A PARKED DRAFT is an occupant too. The cart's Hold button parks the order
    // against its table, so a table can be taken with no ticket on it. Resuming
    // is the same act as adding a round: pick up what is already there.
    final held = t.heldOrderId;
    if (held != null) {
      if (t.heldLockedByOther) {
        _notifier.showToast(
          _tr('tables.locked'),
          tone: ChipTone.warning,
          icon: 'lock',
        );
        return;
      }
      await _notifier.switchToHeldOrder(held);
      await _toOrderScreen();
      return;
    }
    // Paid, plates still there. Clearing is the only honest act — a new party
    // cannot be seated on a table nobody has bussed.
    if (tableNeedsClearing(t)) {
      await _notifier.clearTable(t.id);
      return;
    }
    // Kept for a booked party: seating them is what the table is for.
    if (tableHasBooking(t)) {
      await _notifier.seatBooking(t);
      await _toOrderScreen();
      return;
    }
    // SEATED, NOTHING ORDERED. The commonest state on a floor and, until the
    // tab exists, one this screen used to have no answer for: it would tell the
    // teller the table was "taken on another till" and stop. There is nothing
    // to show and everything to take — go to the menu with the table in hand.
    if (t.status == 'seated') {
      _notifier.pointCartAtTable(t.id, t.label);
      await _toOrderScreen();
      return;
    }
    // Free: seat a walk-in. Takes the table on every device; the tab starts
    // with whatever they order first.
    await _notifier.seatTable(t);
    await _toOrderScreen();
  }

  /// Everything that is not the obvious act.
  ///
  /// A table with a bill has nothing extra here: its sheet already carries
  /// every verb, so a long-press opens the same thing a tap does rather than a
  /// second, shorter list of the same words.
  Future<void> _onTableMenu(
    FloorTableStateView t,
    TicketView? ticket, {
    required bool isWaiter,
  }) async {
    if (_completedMove(t)) return;
    if (ticket != null) {
      await _ticketSheet(t, ticket, isWaiter: isWaiter);
      return;
    }
    if (t.heldOrderId != null) {
      await _heldTableSheet(t);
      return;
    }
    if (tableNeedsClearing(t)) {
      await _needsClearingSheet(t, isWaiter: isWaiter);
      return;
    }
    if (tableHasBooking(t)) {
      await _reservedTableSheet(t, isWaiter: isWaiter);
      return;
    }
    await _freeTableSheet(t, isWaiter: isWaiter);
  }

  /// The booking's own sheet. Seating points the live order at this table
  /// under the guest's name; the ticket fired next links to the booking.
  Future<void> _reservedTableSheet(
    FloorTableStateView t, {
    required bool isWaiter,
  }) async {
    final bridge = ref.read(bridgeProvider);
    final when = t.bookingStartsAt == null
        ? ''
        : ' · ${bridge.formatTime(rfc3339: t.bookingStartsAt!, style: TimeStyle.time)}';
    final party = t.bookingParty == null
        ? ''
        : ' · ${t.bookingParty} ${_tr('tables.guests')}';
    await _actionsSheet(
      '${t.label} · ${_tr('tables.reserved_for')} ${t.bookingGuest ?? ''}$when$party',
      [
        _SheetAction('person.2', _tr('tables.seat_booking'), () async {
          await _notifier.seatBooking(t);
          if (mounted) await Navigator.of(context).maybePop();
        }),
        _SheetAction('xmark.circle', _tr('tables.no_show'), () async {
          final id = t.bookingId;
          if (id != null) await _notifier.noShowBooking(id);
        }),
        _SheetAction(
          'tray.and.arrow.down',
          _tr('tables.walk_in_anyway'),
          () async {
            await _freeTableSheet(t, isWaiter: isWaiter);
          },
        ),
        _SheetAction(
          'arrow.triangle.2.circlepath',
          _tr('tables.move'),
          () async {
            setState(() => _swapFrom = t.id);
          },
        ),
      ],
    );
  }

  /// Today's bookings, earliest first: seat or no-show from the list.
  Future<void> _openArrivals() async {
    final bridge = ref.read(bridgeProvider);
    unawaited(_notifier.syncFloor());
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final list = sheetRef.watch(orderProvider.select((s) => s.arrivals));
          final colors = context.madarColors;
          return Padding(
            padding: const EdgeInsetsDirectional.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  bridge.tr(key: 'tables.arrivals'),
                  style: MadarType.h3.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: Space.lg),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.all(Space.xl),
                    child: Text(
                      bridge.tr(key: 'tables.arrivals_empty'),
                      textAlign: TextAlign.center,
                      style: MadarType.body.copyWith(color: colors.textMuted),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: Space.sm),
                      itemBuilder: (context, i) => _ArrivalRow(
                        booking: list[i],
                        time: bridge.formatTime(
                          rfc3339: list[i].startsAt,
                          style: TimeStyle.time,
                        ),
                        guestsWord: bridge.tr(key: 'tables.guests'),
                        seatedWord: bridge.tr(key: 'tables.seated'),
                        seatLabel: bridge.tr(key: 'tables.seat_booking'),
                        noShowLabel: bridge.tr(key: 'tables.no_show'),
                        onSeat: () async {
                          await Navigator.of(sheetContext).maybePop();
                          if (!mounted) return;
                          await _notifier.seatArrival(list[i]);
                          if (mounted) {
                            await Navigator.of(this.context).maybePop();
                          }
                        },
                        onNoShow: () =>
                            unawaited(_notifier.noShowBooking(list[i].id)),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// A table whose party paid and left: the ONE thing it needs is clearing,
  /// so that is the first action and everything else stays available under
  /// it. This is the manual counterpart to the post-checkout prompt — a
  /// teller who said "not yet" then, or who was never asked (another till
  /// rang the sale), clears it from here.
  Future<void> _needsClearingSheet(
    FloorTableStateView t, {
    required bool isWaiter,
  }) async {
    // No "start order here" on a dirty table on purpose: if a new party is
    // sitting there, the plates ARE gone, and Clear is the one honest action.
    // Offering both would let a table go straight from one party to the next
    // while still telling the manager it needs bussing.
    await _actionsSheet('${t.label} · ${_tr('tables.needs_clearing')}', [
      _SheetAction('sparkles', _tr('tables.clear'), () async {
        await _notifier.clearTable(t.id);
      }),
      _SheetAction('arrow.triangle.2.circlepath', _tr('tables.move'), () async {
        setState(() => _swapFrom = t.id);
      }),
    ]);
  }

  /// A free table: seat the live cart here, or start nothing.
  Future<void> _freeTableSheet(
    FloorTableStateView t, {
    required bool isWaiter,
  }) async {
    // Seating is the TAP. What is left is the geometry, a held order that
    // wants a home, and a way back for a table stuck in a state nothing else
    // will clear.
    final drafts = ref
        .read(orderProvider)
        .drafts
        .where((d) => d.tableId == null && !d.lockedByOther)
        .toList(growable: false);
    await _actionsSheet(t.label, [
      // The other half of assigning a table from the drafts screen: a teller
      // standing at the floor puts the held order where the party actually
      // sat, without going to find it in a list first.
      if (drafts.isNotEmpty)
        _SheetAction('tray.full', _tr('tables.seat_held'), () async {
          await _pickHeldOrderFor(t, drafts);
        }),
      _SheetAction('arrow.triangle.2.circlepath', _tr('tables.move'), () async {
        setState(() => _swapFrom = t.id);
      }),
      if (t.status != 'free')
        _SheetAction('checkmark.circle', _tr('tables.free_it'), () async {
          await _notifier.makeTableAvailable(t);
        }),
    ]);
  }

  /// A table holding a PARKED DRAFT: move it, queue for it, or hand the table
  /// back.
  ///
  /// Resuming is the tap, so it is not repeated here — the same shape as a
  /// ticket's table.
  Future<void> _heldTableSheet(FloorTableStateView t) async {
    final id = t.heldOrderId!;
    await _actionsSheet(
      '${t.label}${(t.heldOrderName?.isNotEmpty ?? false) ? ' · ${t.heldOrderName}' : ''}',
      [
        _SheetAction(
          'arrow.triangle.2.circlepath',
          _tr('tables.move'),
          () async {
            setState(() => _swapFrom = t.id);
          },
        ),
        _SheetAction('clock', _tr('tables.queue'), () async {
          await _createWishFlow('held_order', id);
        }),
        // The party left: the parked order survives, table-less, and the table
        // goes back to the room.
        _SheetAction('checkmark.circle', _tr('tables.free_it'), () async {
          await _notifier.makeTableAvailable(t);
        }),
      ],
    );
  }

  /// THE BILL. What a table's tap opens once the party has ordered.
  ///
  /// The floor used to answer a tap on a seated table by dropping the teller
  /// into the menu, which meant "what do they owe?" was never on screen — you
  /// long-pressed for a list of verbs and guessed. A table is a party with a
  /// running bill, so tapping one shows the bill and the two things you do with
  /// it: add to it, or take their money.
  Future<void> _ticketSheet(
    FloorTableStateView t,
    TicketView ticket, {
    required bool isWaiter,
  }) async {
    if (!mounted) return;
    final bridge = ref.read(bridgeProvider);
    final currency = ref.read(orderProvider).currency;
    final seatedFor = formatSeatedFor(
      DateTime.now().toUtc().difference(
        DateTime.tryParse(ticket.openedAt)?.toUtc() ?? DateTime.now().toUtc(),
      ),
    );
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) {
        final colors = sheetContext.madarColors;
        void close() => Navigator.of(sheetContext).maybePop();
        return Padding(
          padding: const EdgeInsetsDirectional.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.label,
                      style: MadarType.h2.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (ticket.queuedOffline)
                    StatusChip(
                      label: _tr('waiter.queued'),
                      tone: ChipTone.warning,
                      icon: 'clock',
                    ),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(
                [
                  if (ticket.ticketRef != null) ticket.ticketRef!,
                  '${_tr('tables.seated')} $seatedFor',
                  if (ticket.guestCount != null)
                    '${ticket.guestCount} ${_tr('tables.guests')}',
                  if (ticket.waiterName != null) ticket.waiterName!,
                ].join(' · '),
                style: MadarType.bodySm.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: Space.lg),
              // Everything they have had. A ticket that fired offline has no
              // lines mirrored back yet, so it says so rather than looking like
              // an empty bill.
              if (ticket.lines.isEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: Space.md),
                  child: Text(
                    _tr('tables.bill_pending'),
                    style: MadarType.bodySm.copyWith(color: colors.textMuted),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _kBillMaxHeight),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Grouped by ROUND, because that is how a bill is read:
                        // the drinks at seven, the food at half past. A flat
                        // list of the same items says nothing about how the
                        // evening went, or what has been waiting longest.
                        for (final round in groupBillByRound(ticket.lines)) ...[
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                              top: Space.sm,
                              bottom: Space.xs,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_tr('tables.round')} ${round.number}',
                                    style: MadarType.labelSm.copyWith(
                                      color: colors.textMuted,
                                      letterSpacing: MadarType.tracking,
                                    ),
                                  ),
                                ),
                                if (round.firedAt.isNotEmpty)
                                  Text(
                                    bridge.formatTime(
                                      rfc3339: round.firedAt,
                                      style: TimeStyle.time,
                                    ),
                                    style: MadarType.num.copyWith(
                                      color: colors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          for (final line in round.lines)
                            _BillLine(line: line, currency: currency),
                        ],
                      ],
                    ),
                  ),
                ),
              const MadarHairline(),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _tr('order.total'),
                      style: MadarType.title.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    Money.format(ticket.subtotalMinor, currency: currency),
                    style: MadarType.moneyLg.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.lg),
              // The two acts. Adding is the common one and stays primary even
              // for a teller, who adds far more rounds than they settle.
              MadarButton(
                label: _tr('tables.add_round'),
                icon: 'plus.circle',
                onTap: () {
                  close();
                  unawaited(() async {
                    _notifier
                      ..pointCartAtTable(t.id, t.label)
                      ..selectTicket(ticket.id);
                    await _toOrderScreen();
                  }());
                },
              ),
              // Taking money is the teller's job.
              if (!isWaiter) ...[
                const SizedBox(height: Space.sm),
                MadarButton(
                  label: _tr('tables.settle'),
                  icon: 'creditcard',
                  variant: MadarButtonVariant.outline,
                  onTap: () {
                    close();
                    unawaited(_settleFromFloor(ticket));
                  },
                ),
              ],
              const SizedBox(height: Space.md),
              // Everything else a party can do, kept quiet beneath the money.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  MadarButton(
                    label: _tr('tables.move'),
                    icon: 'arrow.triangle.2.circlepath',
                    variant: MadarButtonVariant.outline,
                    size: MadarButtonSize.compact,
                    onTap: () {
                      close();
                      setState(() => _swapFrom = t.id);
                    },
                  ),
                  MadarButton(
                    label: _tr('tables.queue'),
                    icon: 'clock',
                    variant: MadarButtonVariant.outline,
                    size: MadarButtonSize.compact,
                    onTap: () {
                      close();
                      unawaited(_createWishFlow('open_ticket', ticket.id));
                    },
                  ),
                  // The party left without paying — or was seated by mistake.
                  // This ABANDONS a live tab, so it says so: "Make available"
                  // was the same words used for clearing an empty bussed
                  // table, a different act with different consequences.
                  MadarButton(
                    label: _tr('tables.free_it'),
                    icon: 'person.crop.circle.badge.xmark',
                    variant: MadarButtonVariant.outline,
                    size: MadarButtonSize.compact,
                    onTap: () {
                      close();
                      unawaited(_freeLiveTable(ticket));
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Take the money for a table, from the table.
  Future<void> _settleFromFloor(TicketView ticket) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OpenTicketsScreen(focusTicketId: ticket.id),
      ),
    );
  }

  /// Choose which held order goes on this table.
  ///
  /// Only unassigned drafts, and only ones no other till is editing — a locked
  /// draft cannot be moved out from under whoever has it open.
  Future<void> _pickHeldOrderFor(
    FloorTableStateView t,
    List<DraftView> drafts,
  ) async {
    if (!mounted) return;
    final picked = await showMadarSheet<DraftView>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_tr('tables.seat_held')} · ${t.label}',
              style: MadarType.h3.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Space.lg),
            for (final d in drafts)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
                child: MadarButton(
                  label: '${d.name} · ${d.itemCount}',
                  icon: 'tray.full',
                  variant: MadarButtonVariant.outline,
                  onTap: () => Navigator.of(sheetContext).maybePop(d),
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _notifier.assignDraftTable(picked.id, t.id);
  }

  /// Pick a wish target (a whole section, or one exact table), then queue it.
  Future<void> _createWishFlow(String kind, String occupantId) async {
    final layout = ref.read(orderProvider).floorLayout;
    if (layout == null) return;
    final bridge = ref.read(bridgeProvider);
    final target = await showMadarSheet<(String?, String?)>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              bridge.tr(key: 'tables.queue'),
              style: MadarType.h3.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Space.lg),
            for (final s in layout.sections)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
                child: MadarButton(
                  label: '${bridge.tr(key: 'tables.wish_any')} ${s.name}',
                  variant: MadarButtonVariant.outline,
                  onTap: () =>
                      Navigator.of(sheetContext).maybePop((s.id, null)),
                ),
              ),
            MadarButton(
              label: bridge.tr(key: 'tables.pick'),
              variant: MadarButtonVariant.outline,
              onTap: () => Navigator.of(sheetContext).maybePop((null, '')),
            ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    final (sectionId, tableSentinel) = target;
    String? tableId;
    if (tableSentinel != null) {
      final pick = await showTablePickerSheet(context, ref, allowClear: false);
      if (pick?.tableId == null) return;
      tableId = pick!.tableId;
    }
    await _notifier.createTransfer(
      occupantKind: kind,
      occupantId: occupantId,
      targetSectionId: sectionId,
      targetTableId: tableId,
    );
  }

  /// The waiting queue: fulfill (→ pick a satisfying free table) or cancel.
  Future<void> _openWaitlist() async {
    final bridge = ref.read(bridgeProvider);
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final queue = sheetRef.watch(
            orderProvider.select((s) => s.transferQueue),
          );
          final colors = context.madarColors;
          return Padding(
            padding: const EdgeInsetsDirectional.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  bridge.tr(key: 'tables.waitlist'),
                  style: MadarType.h3.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: Space.lg),
                if (queue.isEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.all(Space.xl),
                    child: Text(
                      bridge.tr(key: 'tables.empty_waitlist'),
                      textAlign: TextAlign.center,
                      style: MadarType.body.copyWith(color: colors.textMuted),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: queue.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: Space.sm),
                      itemBuilder: (context, i) => _WaitlistRow(
                        entry: queue[i],
                        fulfillLabel: bridge.tr(key: 'tables.fulfill'),
                        cancelLabel: bridge.tr(key: 'tables.cancel_wish'),
                        wishAny: bridge.tr(key: 'tables.wish_any'),
                        onFulfill: () async {
                          await Navigator.of(sheetContext).maybePop();
                          if (!mounted) return;
                          await _fulfillFlow(queue[i]);
                        },
                        onCancel: () =>
                            unawaited(_notifier.cancelTransfer(queue[i].id)),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _fulfillFlow(TransferQueueView entry) async {
    // An exact-table wish needs no picking; a section wish opens the picker.
    if (entry.targetTableId != null) {
      await _notifier.fulfillTransfer(entry.id, entry.targetTableId!);
      return;
    }
    final pick = await showTablePickerSheet(context, ref, allowClear: false);
    if (pick?.tableId == null) return;
    await _notifier.fulfillTransfer(entry.id, pick!.tableId!);
  }

  /// Confirm abandoning a LIVE tab.
  ///
  /// Freeing a bussed table and abandoning an unpaid one wore the same words
  /// ("Make available") and the same one tap. One tidies the room; the other
  /// walks away from money.
  ///
  /// It does NOT go through `makeTableAvailable`: that call refuses outright
  /// when a live ticket is passed, on purpose — a bill cannot be silently
  /// orphaned — so a confirmation in front of it only ever bought the teller
  /// a "settle this bill first" toast for an act they had already confirmed.
  ///
  /// An abandoned tab is a VOID, which is the honest name for it and the only
  /// one the ledger can read back: the bill is written off against a reason,
  /// and voiding already frees the table on its way through. So this opens
  /// the same reason-capturing void sheet the bill screen and the cart use,
  /// which is a confirmation with the one question a blind Yes/No cannot
  /// ask — why.
  Future<void> _freeLiveTable(TicketView ticket) async {
    if (!mounted) return;
    final result = await showMadarSheet<VoidTicketResult>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => WaiterVoidSheet(ticket: ticket),
    );
    if (result == null) return;
    await _notifier.voidTicket(ticket.id, result.reason);
  }

  Future<void> _actionsSheet(String title, List<_SheetAction> actions) async {
    if (actions.isEmpty) return;
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: MadarType.h3.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Space.lg),
            for (final a in actions)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
                child: MadarButton(
                  label: a.label,
                  icon: a.icon,
                  variant: MadarButtonVariant.outline,
                  onTap: () {
                    Navigator.of(sheetContext).maybePop();
                    unawaited(a.run());
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SheetAction {
  const _SheetAction(this.icon, this.label, this.run);
  final String icon;
  final String label;
  final Future<void> Function() run;
}
// ── The table glyph ──────────────────────────────────────────────────────────
//
// ONE drawing of a table, shared with the dashboard's authoring canvas
// (`src/features/reservations/table-glyph.tsx`). Every constant below is in
// CANVAS UNITS — the units the dashboard authors geometry in — multiplied by
// the live `scale` at paint time, so a room drawn there and a room worked here
// are recognisably the same room. Change a constant in one place, change it in
// the other.

/// Rounded-rect corner radius, ring weights, and body tint strength.
const double kTableCorner = 10;
const double kTableRing = 2;
const double kTableRingSelected = 4;
const double kTableFillOpacity = 0.18;

/// Past this many seats the rim turns into a smear — the count carries it.
const int kSeatRenderCap = 12;

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

/// The chairs, painted under the table body. Decorative only — never tap
/// targets, so they can sit closer together than the 44pt touch minimum
/// without competing with the table itself for a press.
class _SeatsPainter extends CustomPainter {
  const _SeatsPainter({
    required this.slots,
    required this.tone,
    required this.len,
    required this.thick,
  });

  final List<SeatSlot> slots;
  final Color tone;
  final double len;
  final double thick;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = tone.withValues(alpha: 0.55);
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
  bool shouldRepaint(_SeatsPainter old) =>
      old.tone != tone ||
      old.len != len ||
      old.thick != thick ||
      old.slots.length != slots.length;
}

/// One table on the canvas — a 1:1 port of the dashboard's `TableGlyph`
/// (rotate around center is applied by the caller): chairs around the rim,
/// ellipse / rx-10 rounded body at 0.18 status fill under a soft top-light,
/// ring stroke 2, the corner status icon (never colour alone), bold label,
/// "N seats" line when there is room, and the occupant pill riding the bottom
/// edge. All metrics are CANVAS units × the live scale, so the POS renders the
/// same picture as the dashboard.
class _TableCell extends StatelessWidget {
  const _TableCell({
    required this.table,
    required this.ticket,
    required this.scale,
    required this.seatsWord,
    required this.words,
    required this.swapArmed,
    required this.onTap,
    this.selected = false,
    this.onLongPress,
  });

  final FloorTableStateView table;
  final TicketView? ticket;
  final double scale;
  final String seatsWord;

  /// Translated state vocabulary — read out to screen readers and shown on
  /// the cell itself, so state never rests on colour alone.
  final TableStatusWords words;
  final bool swapArmed;
  final VoidCallback? onTap;

  /// Picker mode: the order's current table renders with the accent ring.
  final bool selected;
  final VoidCallback? onLongPress;

  /// Text follows the room's scale but never below legibility: geometry may
  /// shrink to 0.4×, type may not. This is what killed the canvas on narrow
  /// windows — 18px labels rendering at 7px.
  double _fs(double base, {double floor = 11, double cap = 22}) =>
      (base * scale).clamp(floor, cap);

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    // A parked draft occupies the table too — the cart's Hold button parks an
    // order against it with no ticket involved. Counting only tickets drew a
    // plainly-taken table in the free tone.
    final occupied = ticket != null || table.heldOrderId != null;
    final needsClearing = tableNeedsClearing(table, occupied: occupied);
    // ONE colour per state (the dashboard's `tint`), used for the body tint,
    // the ring, the chairs, and the pill. Ink is always the page's foreground —
    // no reversed-out text, so the two platforms never diverge on legibility.
    final tone = tableTone(colors, table, occupied: occupied);
    final ring = tone;
    final ink = colors.textPrimary;
    final w = table.width * scale;
    final h = table.height * scale;
    final isCircle = table.shape == 'circle';
    final radius = isCircle
        ? BorderRadius.all(Radius.elliptical(w / 2, h / 2))
        : BorderRadius.circular((kTableCorner * scale).clamp(6, 14).toDouble());

    // Chair geometry is computed in CANVAS units (so the clamps mean the same
    // thing the dashboard means by them) and only then scaled.
    final m = seatMetrics(table.width, table.height);
    final slots = seatSlots(table.shape, table.width, table.height, table.seats)
        .map<SeatSlot>((s) => (x: s.x * scale, y: s.y * scale, angle: s.angle))
        .toList(growable: false);

    // What a taken table says: WHO is on it, and HOW LONG they've been there —
    // the two things floor staff scan for. A free table says how many it
    // seats, which is what you need when choosing one. A table waiting to be
    // bussed says so in words — it is a job, and jobs get named.
    // A booked party shows on the pill too — "Ahmed · 19:30" while the table
    // is kept for them, then just "Ahmed" once they are seated — so the floor
    // knows whose table this is before a ticket exists.
    final bookedGuest =
        (table.bookingGuest?.trim().isNotEmpty ?? false) &&
            (tableIsReserved(table) ||
                tableBookingSeated(table) ||
                tableHasBooking(table))
        ? table.bookingGuest!.trim()
        : null;
    final bookedAt =
        bookedGuest != null &&
            !tableBookingSeated(table) &&
            table.bookingStartsAt != null
        ? words.timeOf?.call(table.bookingStartsAt!)
        : null;
    // Who is on this table. A NAME beats a reference: "Sara" tells a teller
    // something across a room and "T-0412" does not, so the customer's name
    // wins where the ticket carries one and the ref is the fallback.
    final onIt = ticket?.customerName?.trim() ?? table.heldOrderName?.trim();
    final who = (onIt?.isNotEmpty ?? false)
        ? onIt
        : ticket?.ticketRef ??
              (bookedGuest == null
                  ? null
                  : (bookedAt == null
                        ? bookedGuest
                        : '$bookedGuest · $bookedAt'));
    final howLong = elapsedLabel(table.heldSince);
    final statusWord = words.wordFor(table, occupied: occupied);
    final statusIcon = tableStatusIcon(table, occupied: occupied);

    final labelSize = _fs(20);
    final subSize = _fs(12, floor: 9.5, cap: 14);
    final pillSize = _fs(11, floor: 9, cap: 13);
    // Rendered-pixel budget: the label never yields, the lines under it do.
    final showSeats = h >= 62 * scale && h - labelSize >= subSize + 10;
    // The pill names the table's situation: who is on it (with time-on-table),
    // or — when nothing occupies it but it still owes the floor a bus — that.
    // One slot, so the state is never left to colour and texture alone.
    final pillText = (who?.isNotEmpty ?? false)
        ? (howLong == null ? who! : '$who · $howLong')
        : (needsClearing ? words.needsClearing : null);
    // The dashboard's estimator, verbatim (~0.55em per glyph), so both
    // platforms drop the pill on exactly the same tables rather than one
    // ellipsizing where the other omits.
    final pillFits =
        pillText != null && pillText.length * pillSize * 0.55 <= w - 20 * scale;
    final showPill = pillFits && h >= 46 * scale;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final glyphSize = (15 * scale).clamp(10, 18).toDouble();

    final body = AnimatedContainer(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutQuart,
      width: w,
      height: h,
      decoration: BoxDecoration(
        // NOTE: a BoxDecoration `gradient` REPLACES `color` — putting the
        // sheen here would silently erase the status tint and paint every
        // table grey. The sheen is a separate layer below, like the
        // dashboard's second shape over the fill.
        color: tone.withValues(alpha: kTableFillOpacity),
        borderRadius: radius,
        border: Border.all(
          color: selected || swapArmed ? colors.textPrimary : ring,
          width:
              (selected || swapArmed ? kTableRingSelected : kTableRing) *
              scale.clamp(1, 1.6),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.textPrimary.withValues(alpha: occupied ? 0.16 : 0.06),
            blurRadius: (occupied ? 10 : 6) * scale.clamp(0.6, 1.4),
            offset: Offset(0, (occupied ? 3 : 1) * scale.clamp(0.6, 1.4)),
          ),
        ],
      ),
      // `painter` (not `foregroundPainter`): the hatch belongs UNDER the label
      // and the pill, the way it sits under them on the dashboard.
      child: CustomPaint(
        painter: needsClearing
            ? _HatchPainter(
                tone: colors.danger,
                pitch: (9 * scale).clamp(6.0, 14.0),
                radius: radius,
                isCircle: isCircle,
              )
            : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The soft top-light that turns a tinted shape into a surface.
            // Kept to a few percent — material, not gloss.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.textPrimary.withValues(alpha: 0.05),
                      colors.textPrimary.withValues(alpha: 0),
                      colors.textPrimary.withValues(alpha: 0.06),
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
            ),
            // Label + seat count, centred.
            Positioned.fill(
              child: Padding(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: (6 * scale).clamp(4, 10).toDouble(),
                ),
                // Flexible, because the type has a legibility FLOOR while the
                // geometry does not: zoomed far out, an 11px label no longer
                // fits inside a 15px table. Letting the lines shrink clips them
                // gracefully instead of throwing a layout overflow, which in
                // debug paints the whole canvas with overflow stripes.
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        table.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.label.copyWith(
                          fontSize: labelSize,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: ink,
                        ),
                      ),
                    ),
                    if (showSeats)
                      Flexible(
                        child: Text(
                          '${table.seats} $seatsWord',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MadarType.labelSm.copyWith(
                            fontSize: subSize,
                            height: 1.15,
                            color: ink.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // The state's glyph, top-start corner.
            if (statusIcon != null)
              Positioned(
                left: (5 * scale).clamp(3, 8).toDouble(),
                top: (5 * scale).clamp(3, 8).toDouble(),
                child: MadarIcon(statusIcon, tint: ring, size: glyphSize),
              ),
            // Who is on it, riding the bottom edge — solid, so occupancy is
            // the heaviest mark on an otherwise quiet room.
            if (showPill)
              Positioned(
                left: (6 * scale).clamp(3, 10).toDouble(),
                right: (6 * scale).clamp(3, 10).toDouble(),
                bottom: -(4 * scale).clamp(2, 6).toDouble(),
                child: Container(
                  height: (19 * scale).clamp(14, 24).toDouble(),
                  alignment: Alignment.center,
                  padding: EdgeInsetsDirectional.symmetric(
                    horizontal: (6 * scale).clamp(4, 9).toDouble(),
                  ),
                  decoration: BoxDecoration(
                    color: ring,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    pillText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.labelSm.copyWith(
                      fontSize: pillSize,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: colors.textOnAccent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      // One labelled control per table. Without this the canvas is a wall of
      // unlabelled gesture targets: name, state, and occupant, in that order.
      label: [
        table.label,
        statusWord,
        if (occupied && (who?.isNotEmpty ?? false)) who!,
        if (!occupied && !needsClearing) '${table.seats} $seatsWord',
      ].join(', '),
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                MadarHaptics.selection();
                onTap!();
              },
        onLongPress: onLongPress == null
            ? null
            : () {
                MadarHaptics.impact();
                onLongPress!();
              },
        // Chairs are painted OUTSIDE the body box, so nothing here may clip.
        child: CustomPaint(
          painter: _SeatsPainter(
            slots: slots,
            tone: ring,
            len: m.len * scale,
            thick: m.thick * scale,
          ),
          child: body,
        ),
      ),
    );
  }
}

/// Diagonal hatching for the needs-a-bus state. Colour alone would leave the
/// one state that demands WORK indistinguishable from the rest for a
/// colour-blind teller — and it is the state the whole checkout flow now
/// depends on being noticed. Kept faint: texture under the label, never a
/// competitor to it.
class _HatchPainter extends CustomPainter {
  const _HatchPainter({
    required this.tone,
    required this.pitch,
    required this.radius,
    required this.isCircle,
  });

  final Color tone;
  final double pitch;

  /// The body's corner radius, so the hatch stops at the table's edge…
  final BorderRadius radius;

  /// …and follows the rim rather than boxing a round table in.
  final bool isCircle;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = tone.withValues(alpha: 0.16)
      ..strokeWidth = math.max(1, pitch * 0.28)
      ..style = PaintingStyle.stroke;
    final bounds = Offset.zero & size;
    canvas.save();
    if (isCircle) {
      canvas.clipPath(Path()..addOval(bounds));
    } else {
      canvas.clipRRect(radius.toRRect(bounds));
    }
    // 45° lines swept across the diagonal extent so the whole cell is covered
    // regardless of aspect ratio.
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
      old.tone != tone ||
      old.pitch != pitch ||
      old.isCircle != isCircle ||
      old.radius != radius;
}

/// A count + its state, in the state's own colour — the header row that
/// both summarises the room and teaches the canvas's vocabulary.
/// One line of a table's bill: what it is, what was done to it, what it cost.
class _BillLine extends StatelessWidget {
  const _BillLine({required this.line, required this.currency});

  final TicketLineView line;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    // A voided line stays ON the bill, struck through. Removing it would make
    // the total unexplainable to the person reading it.
    final struck = line.voided ? TextDecoration.lineThrough : null;
    final tone = line.voided ? colors.textMuted : colors.textPrimary;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _kBillQtyWidth,
            child: Text(
              '${line.qty}×',
              style: MadarType.money.copyWith(
                color: colors.textMuted,
                decoration: struck,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    line.name,
                    if (line.sizeLabel != null) '· ${line.sizeLabel}',
                  ].join(' '),
                  style: MadarType.body.copyWith(
                    color: tone,
                    decoration: struck,
                  ),
                ),
                if (line.modifiers.isNotEmpty)
                  Text(
                    line.modifiers.join(' · '),
                    style: MadarType.labelSm.copyWith(color: colors.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          Text(
            Money.format(line.lineTotalMinor, currency: currency),
            style: MadarType.money.copyWith(color: tone, decoration: struck),
          ),
        ],
      ),
    );
  }
}

/// Width of the quantity column, so every line's name starts at one x.
const double _kBillQtyWidth = 34;

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.tone,
    required this.label,
    required this.count,
    this.solid = false,
  });

  final Color tone;
  final String label;
  final int count;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: solid ? tone : tone.withValues(alpha: 0.22),
            shape: BoxShape.circle,
            border: Border.all(color: tone, width: 1.5),
          ),
        ),
        const SizedBox(width: Space.xs),
        Text(
          '$count $label',
          style: MadarType.labelSm.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// One waitlist row: who, where from, what they want, since when.
class _WaitlistRow extends StatelessWidget {
  const _WaitlistRow({
    required this.entry,
    required this.fulfillLabel,
    required this.cancelLabel,
    required this.wishAny,
    required this.onFulfill,
    required this.onCancel,
  });

  final TransferQueueView entry;
  final String fulfillLabel;
  final String cancelLabel;
  final String wishAny;
  final Future<void> Function() onFulfill;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final wish =
        entry.targetTableLabel ?? '$wishAny ${entry.targetSectionName ?? ''}';
    final from = entry.fromTableLabel;
    return Container(
      padding: const EdgeInsetsDirectional.all(Space.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.occupantLabel?.isNotEmpty ?? false
                      ? entry.occupantLabel!
                      : (from ?? ''),
                  style: MadarType.label.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  from != null ? '$from → $wish' : '→ $wish',
                  style: MadarType.labelSm.copyWith(color: colors.textMuted),
                ),
                if (entry.note?.isNotEmpty ?? false)
                  Text(
                    entry.note!,
                    style: MadarType.labelSm.copyWith(color: colors.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          MadarButton(
            label: fulfillLabel,
            variant: MadarButtonVariant.outline,
            onTap: () => unawaited(onFulfill()),
          ),
          const SizedBox(width: Space.sm),
          GestureDetector(
            onTap: onCancel,
            child: MadarIcon('xmark.circle', tint: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// One booking in the arrivals sheet: when, who, how many, where — and the
/// two answers the floor gives it.
class _ArrivalRow extends StatelessWidget {
  const _ArrivalRow({
    required this.booking,
    required this.time,
    required this.guestsWord,
    required this.seatedWord,
    required this.seatLabel,
    required this.noShowLabel,
    required this.onSeat,
    required this.onNoShow,
  });

  final BookingView booking;
  final String time;
  final String guestsWord;
  final String seatedWord;
  final String seatLabel;
  final String noShowLabel;
  final Future<void> Function() onSeat;
  final VoidCallback onNoShow;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final seated = booking.status == 'seated';
    final where = booking.tableLabels.join(' + ');
    return Container(
      padding: const EdgeInsetsDirectional.all(Space.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: seated ? colors.accent : colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$time · ${booking.guestName}',
                  style: MadarType.label.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  [
                    '${booking.partySize} $guestsWord',
                    if (where.isNotEmpty) where,
                    if (seated) seatedWord,
                    if (booking.notes?.isNotEmpty ?? false) booking.notes!,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.labelSm.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          if (!seated) ...[
            const SizedBox(width: Space.sm),
            MadarButton(
              label: noShowLabel,
              icon: 'xmark.circle',
              variant: MadarButtonVariant.outline,
              onTap: onNoShow,
            ),
            const SizedBox(width: Space.sm),
            MadarButton(
              label: seatLabel,
              icon: 'person.2',
              onTap: () => unawaited(onSeat()),
            ),
          ],
        ],
      ),
    );
  }
}
