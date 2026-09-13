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
import 'package:feature_order/src/order_providers.dart';
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
///
/// [forMove]: picking where the party on [currentTableId] goes. Any other
/// table that is not waiting to be cleared or kept for a booking is a target —
/// an occupied one SWAPS — and the party's own table is not.
Future<TablePick?> showTablePickerSheet(
  BuildContext context,
  WidgetRef ref, {
  String? currentTableId,
  bool allowClear = true,
  bool forMove = false,
}) async {
  final bridge = ref.read(bridgeProvider);
  final layout = ref.read(orderProvider).floorLayout;
  final tickets = ref.read(orderProvider).openTickets;
  if (layout == null) return null;
  return await showMadarSheet<TablePick>(
    context,
    size: SheetSize.hug,
    builder: (sheetContext) => _TablePickerBody(
      layout: layout,
      tickets: tickets,
      forMove: forMove,
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
    required this.tickets,
    required this.forMove,
    required this.currentTableId,
    required this.allowClear,
    required this.title,
    required this.clearLabel,
    required this.seatsWord,
    required this.noSectionLabel,
    required this.words,
  });

  final FloorLayoutView layout;
  final List<TicketView> tickets;
  final bool forMove;
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
                // The bills, so a table with one reads (and counts) as taken.
                tickets: widget.tickets,
                enabledOf: (t) => widget.forMove
                    ? tableIsMoveTarget(
                        t,
                        from: widget.currentTableId,
                        tickets: widget.tickets,
                      )
                    // A table is pickable when nothing sits on it — or it's
                    // the order's OWN current table ("keep it" stays obvious).
                    : t.id == widget.currentTableId ||
                          urgencyOf(
                                t,
                                widget.tickets
                                    .where(
                                      (x) =>
                                          x.tableId == t.id && isLiveTicket(x),
                                    )
                                    .firstOrNull,
                              ) ==
                              FloorUrgency.free,
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
    this.units = DurationUnits.latin,
    this.now = 'now',
  });

  /// The vocabulary as the bridge translates it.
  factory TableStatusWords.of(MadarBridge bridge) => TableStatusWords(
    free: bridge.tr(key: 'tables.free'),
    held: bridge.tr(key: 'tables.held_res'),
    seated: bridge.tr(key: 'tables.seated'),
    needsClearing: bridge.tr(key: 'tables.needs_clearing'),
    reserved: bridge.tr(key: 'tables.reserved'),
    timeOf: (iso) => bridge.formatTime(rfc3339: iso, style: TimeStyle.time),
    units: DurationUnits.of(bridge),
    now: bridge.tr(key: 'common.now'),
  );

  /// The short hour/minute letters on a seated table's clock.
  final DurationUnits units;

  /// A clock under a minute old.
  final String now;

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

/// Can the party on [from] move to [t]? Not onto itself, not onto plates,
/// not onto a table kept for a booking. An occupied table is fine: that is a
/// swap. The server refuses the same three, so the picker says no first.
bool tableIsMoveTarget(
  FloorTableStateView t, {
  required String? from,
  required List<TicketView> tickets,
  DateTime? now,
}) {
  if (t.id == from) return false;
  final ticket = tickets
      .where((x) => x.tableId == t.id && isLiveTicket(x))
      .firstOrNull;
  final u = urgencyOf(t, ticket, now: now);
  return u != FloorUrgency.needsClearing && u != FloorUrgency.reserved;
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
/// [units] and [nowWord] are the current language's (see [DurationUnits.of]
/// and `common.now`); the Latin defaults are for tests.
String? elapsedLabel(
  String? sinceIso, {
  DateTime? now,
  DurationUnits units = DurationUnits.latin,
  String nowWord = 'now',
}) {
  if (sinceIso == null || sinceIso.isEmpty) return null;
  final since = DateTime.tryParse(sinceIso);
  if (since == null) return null;
  final mins = (now ?? DateTime.now()).difference(since.toLocal()).inMinutes;
  if (mins < 1) return nowWord;
  if (mins < 60) return '$mins${units.minute}';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '$h${units.hour}' : '$h${units.hour} $m${units.minute}';
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

/// Tab id for tables that belong to no section (or an orphaned one).
const String _kNoSection = '__no_section__';

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
    // The table's clock, best source first: a parked order's own start, then
    // this device's seated stamp, then the bill's opened_at. The last one is
    // the safety net for a till that joined the shift AFTER the party sat —
    // it pulled a seated table from the server and never saw the seating, so
    // it has no stamp of its own and the bill is the only witness left.
    final howLong = elapsedLabel(
      table.seatedAt ?? table.heldSince ?? ticket?.openedAt,
      units: words.units,
      nowWord: words.now,
    );
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
    // The dashboard's estimator, verbatim (~0.55em per glyph), so both
    // platforms drop the pill on exactly the same tables rather than one
    // ellipsizing where the other omits.
    bool fits(String t) => t.length * pillSize * 0.55 <= w - 20 * scale;
    // WHO first, then the clock if there is room for it. The time is the
    // first thing to give up — a small table showing "Sara" is worth more
    // than one showing nothing because "Sara · 5h" overran the box, which is
    // what adding the clock did until this budgeted for it.
    final String? pillText;
    if (who?.isNotEmpty ?? false) {
      final withTime = howLong == null ? who! : '$who · $howLong';
      pillText = fits(withTime) ? withTime : who;
    } else {
      pillText = needsClearing ? words.needsClearing : null;
    }
    final showPill = pillText != null && fits(pillText) && h >= 46 * scale;
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
