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
import 'package:feature_order/src/table_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

export 'package:feature_order/src/table_glyph.dart';

// ── Table picker sheet (hold/edit/fire flows) ────────────────────────────────

/// A picked table (or an explicit "no table").
@immutable
class TablePick {
  const TablePick(this.tableId, this.label);
  final String? tableId;
  final String? label;
}

/// Why [to] cannot take the party on [from], as an i18n key — or null when it
/// can. The same table explains itself instead of silently cancelling.
String? moveRefusalKey(
  FloorTableStateView to, {
  required String? from,
  required List<TicketView> tickets,
}) {
  if (to.id == from) return 'err.move_same';
  if (tableIsMoveTarget(to, from: from, tickets: tickets)) return null;
  return tableNeedsClearing(to) ? 'err.move_dirty' : 'err.move_booked';
}

/// Moves the party on [from] to [to] — every screen's one move. Refuses with
/// the reason, confirms a swap ("Swap T2 ↔ T5?") when [to] is occupied, and
/// offers Undo only after the core says it moved. Returns whether it moved.
Future<bool> moveParty(
  BuildContext context,
  WidgetRef ref, {
  required String from,
  required String to,
}) async {
  final bridge = ref.read(bridgeProvider);
  final notifier = ref.read(orderProvider.notifier);
  final s = ref.read(orderProvider);
  final tables = s.floorLayout?.tables ?? const <FloorTableStateView>[];
  final target = tables.where((t) => t.id == to).firstOrNull;
  final source = tables.where((t) => t.id == from).firstOrNull;
  if (target == null) return false;
  final refusal = moveRefusalKey(target, from: from, tickets: s.openTickets);
  if (refusal != null) {
    notifier.showToast(
      bridge.tr(key: refusal),
      tone: ChipTone.warning,
      icon: 'xmark.circle',
    );
    return false;
  }
  final ticket = s.openTickets
      .where((x) => x.tableId == to && isLiveTicket(x))
      .firstOrNull;
  if (urgencyOf(target, ticket) != FloorUrgency.free) {
    final ok = await showMadarConfirm(
      context,
      title:
          '${bridge.tr(key: 'tables.swap')} '
          '${source?.label ?? ''} ↔ ${target.label}?',
      confirmLabel: bridge.tr(key: 'tables.swap'),
      cancelLabel: bridge.tr(key: 'common.cancel'),
    );
    if (!ok) return false;
  }
  final moved = await notifier.swapTables(from, to);
  if (moved) {
    notifier.showToast(
      bridge.tr(key: 'tables.moved'),
      tone: ChipTone.success,
      icon: 'checkmark.circle',
      actionLabel: bridge.tr(key: 'order.undo'),
      action: () => unawaited(notifier.swapTables(to, from)),
      seconds: 5,
    );
  }
  return moved;
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
  if (ref.read(orderProvider).floorLayout == null) return null;
  return await showMadarSheet<TablePick>(
    context,
    size: SheetSize.hug,
    // Live: a table seated, bussed or held while the picker is open reads
    // as such at once, not as it was when the sheet opened.
    builder: (sheetContext) => Consumer(
      builder: (_, r, _) {
        final s = r.watch(orderProvider);
        final layout = s.floorLayout;
        if (layout == null) return const SizedBox.shrink();
        return _TablePickerBody(
          layout: layout,
          tickets: s.openTickets,
          forMove: forMove,
          currentTableId: currentTableId,
          allowClear: allowClear,
          title: bridge.tr(key: 'tables.pick'),
          clearLabel: bridge.tr(key: 'tables.no_table'),
          seatsWord: bridge.tr(key: 'tables.seats'),
          noSectionLabel: bridge.tr(key: 'tables.no_section'),
          words: TableStatusWords.of(bridge),
        );
      },
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
    this.ready = '',
    this.locale = 'en',
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
    ready: bridge.tr(key: 'bill.ready'),
    locale: bridge.locale(),
  );

  /// The kitchen has plated the bill.
  final String ready;

  /// The app language, for clocks on the tables.
  final String locale;

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
  double? viewportHeight,
  double? roomHeight,
}) {
  if (roomWidth <= 0 || viewportWidth <= 0) return 1;
  // Fit BOTH axes when the window has a height: a room fitted by width alone
  // left half a portrait iPad empty under it, or ran off a short landscape.
  var fit = viewportWidth / roomWidth;
  if (viewportHeight != null &&
      viewportHeight > 0 &&
      roomHeight != null &&
      roomHeight > 0) {
    fit = math.min(fit, viewportHeight / roomHeight);
  }
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
/// selection, a move in progress.
///
/// The room is FITTED to the window in both axes — `min(w/roomW, h/roomH)`,
/// capped at [kMaxFloorScale] — and centred both ways. After a pinch, a
/// "fit room" button puts it back.
class FloorCanvas extends StatefulWidget {
  const FloorCanvas({
    required this.section,
    required this.tables,
    required this.tickets,
    required this.seatsWord,
    required this.words,
    required this.onTap,
    this.onLongPress,
    this.enabledOf,
    this.onDisabledTap,
    this.selectedId,
    this.swapArmedId,
    this.zoomable = false,
    this.fitLabel,
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

  /// Per-table interactivity (picker or move mode); null = everything.
  final bool Function(FloorTableStateView)? enabledOf;

  /// A dimmed table still answers a tap when this is set — to say WHY it
  /// cannot be picked, rather than ignoring the finger.
  final ValueChanged<FloorTableStateView>? onDisabledTap;
  final String? selectedId;

  /// A move in progress: the table the party is leaving.
  final String? swapArmedId;

  /// Pinch-zoom + pan (the tables screen; the picker stays a plain scroll).
  final bool zoomable;

  /// Label of the "fit room" button shown after a pinch; null hides it.
  final String? fitLabel;

  @override
  State<FloorCanvas> createState() => _FloorCanvasState();
}

class _FloorCanvasState extends State<FloorCanvas> {
  final _transform = TransformationController();
  bool _moved = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  void _onTransform() {
    final moved = !_transform.value.isIdentity();
    if (moved != _moved) setState(() => _moved = moved);
  }

  @override
  void dispose() {
    _transform
      ..removeListener(_onTransform)
      ..dispose();
    super.dispose();
  }

  void _fit() => _transform.value = Matrix4.identity();

  TableMoveRole _roleOf(FloorTableStateView t) {
    final enabled = widget.enabledOf?.call(t) ?? true;
    if (widget.swapArmedId != null) {
      if (t.id == widget.swapArmedId) return TableMoveRole.source;
      return enabled ? TableMoveRole.target : TableMoveRole.refused;
    }
    return enabled ? TableMoveRole.none : TableMoveRole.refused;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final colors = context.madarColors;
    // The section's stored size is only a hint for laying out never-arranged
    // (QR-era) tables — it is NOT the extent of the room.
    final spreadW = (w.section?.canvasW ?? 1000).toDouble();
    final spreadH = (w.section?.canvasH ?? 700).toDouble();
    final (placed, _) = spreadTables(w.tables, spreadW, spreadH);
    final bounds = floorBounds(placed);
    TicketView? ticketOn(String tableId) => w.tickets
        .where((t) => t.tableId == tableId && isLiveTicket(t))
        .firstOrNull;
    final now = DateTime.now();
    // NO fill on purpose: the tables are what should read, not a slab under
    // them. A faint dot grid is the only ground; a hairline marks the edge.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: colors.borderLight),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.card),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bounded = constraints.hasBoundedHeight;
            final scale = floorScale(
              viewportWidth: constraints.maxWidth,
              roomWidth: bounds.width,
              smallestTable: smallestTableEdge(placed),
              viewportHeight: bounded ? constraints.maxHeight : null,
              roomHeight: bounds.height,
            );
            final drawnW = bounds.width * scale;
            final drawnH = bounds.height * scale;
            // Centred both ways when the room is smaller than the window; when
            // it is bigger (the minimum table size beat the fit) it pans.
            final dx = math.max(0, (constraints.maxWidth - drawnW) / 2);
            final dy = bounded
                ? math.max(0, (constraints.maxHeight - drawnH) / 2)
                : 0;
            final canvasW = math.max(constraints.maxWidth, drawnW);
            final canvasH = bounded
                ? math.max(constraints.maxHeight, drawnH)
                : drawnH;
            final room = CustomPaint(
              painter: _FloorGridPainter(
                pitch: 50 * scale,
                color: colors.border.withValues(alpha: 0.5),
              ),
              child: SizedBox(
                width: canvasW,
                height: canvasH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final p in placed)
                      // Positioned, NOT PositionedDirectional: a floor plan is
                      // PHYSICAL space. `start` measures from the right in
                      // Arabic and would mirror the whole room.
                      Positioned(
                        left: dx + (p.x - bounds.left) * scale,
                        top: dy + (p.y - bounds.top) * scale,
                        width: p.table.width * scale,
                        height: p.table.height * scale,
                        // One table's update must not repaint the room.
                        child: RepaintBoundary(
                          child: Transform.rotate(
                            angle: p.table.rotation * math.pi / 180,
                            child: _cell(
                              p.table,
                              ticketOn(p.table.id),
                              scale,
                              now,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );

            if (w.zoomable && bounded) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      transformationController: _transform,
                      constrained: false,
                      minScale: kFloorViewerMinScale,
                      maxScale: kFloorViewerMaxScale,
                      boundaryMargin: const EdgeInsets.all(80),
                      child: room,
                    ),
                  ),
                  if (_moved && w.fitLabel != null)
                    PositionedDirectional(
                      end: Space.md,
                      bottom: Space.md,
                      child: MadarButton(
                        key: const ValueKey('floor.fit_room'),
                        label: w.fitLabel!,
                        glyph: MadarGlyph.scan,
                        variant: MadarButtonVariant.secondary,
                        size: MadarButtonSize.compact,
                        onTap: _fit,
                      ),
                    ),
                ],
              );
            }
            // An UNBOUNDED height (nested in a scroller) has no window to pan
            // within: fall back to a horizontal scroll or a self-sized viewer.
            if (canvasW > constraints.maxWidth + 0.5) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: room,
              );
            }
            if (!w.zoomable) return room;
            return InteractiveViewer(
              maxScale: kFloorViewerMaxScale,
              child: room,
            );
          },
        ),
      ),
    );
  }

  Widget _cell(
    FloorTableStateView t,
    TicketView? ticket,
    double scale,
    DateTime now,
  ) {
    final w = widget;
    final words = w.words;
    final enabled = w.enabledOf?.call(t) ?? true;
    final state = tableGlyphState(t, ticket, now: now);
    final guest = t.bookingGuest?.trim();
    final at = t.bookingStartsAt == null
        ? null
        : words.timeOf?.call(t.bookingStartsAt!);
    return TableGlyph(
      table: t,
      ticket: ticket,
      scale: scale,
      now: now,
      seatsWord: w.seatsWord,
      locale: words.locale,
      semanticsState: state == TableGlyphState.ready && words.ready.isNotEmpty
          ? words.ready
          : words.wordFor(t, occupied: ticket != null || t.heldOrderId != null),
      reservedChip: guest == null || guest.isEmpty
          ? null
          : (at == null ? guest : '$guest · ${MadarFormat.ltr(at)}'),
      selected: w.selectedId == t.id,
      moveRole: _roleOf(t),
      onTap: enabled
          ? () => w.onTap(t)
          : (w.onDisabledTap == null ? null : () => w.onDisabledTap!(t)),
      onLongPress: w.onLongPress == null ? null : () => w.onLongPress!(t),
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
