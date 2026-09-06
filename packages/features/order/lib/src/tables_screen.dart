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
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/table_clear_prompt.dart';
import 'package:feature_order/src/widgets.dart';
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
  return showMadarSheet<TablePick>(
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
                    t.heldOrderId == null &&
                    (t.status != 'seated' || t.id == widget.currentTableId),
                selectedId: widget.currentTableId,
                onTap: (t) {
                  MadarHaptics.selection();
                  unawaited(
                    Navigator.of(context).maybePop(TablePick(t.id, t.label)),
                  );
                },
              ),
            ),
          ),
          if (widget.allowClear) ...[
            const SizedBox(height: Space.lg),
            ActionButton(
              label: widget.clearLabel,
              variant: ActionVariant.outline,
              onTap: () => unawaited(
                Navigator.of(context).maybePop(const TablePick(null, null)),
              ),
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
    if (tableNeedsClearing(t)) return needsClearing;
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
bool tableNeedsClearing(FloorTableStateView t) =>
    t.status == 'dirty' && t.heldOrderId == null;

/// Status → tone. Four states, four tones: taken (accent), held for a party
/// (warning), needs clearing (danger — it is the one state that owes the room
/// WORK), available (success).
Color tableTone(
  MadarColors colors,
  FloorTableStateView t, {
  bool occupied = false,
}) {
  if (occupied ||
      t.heldOrderId != null ||
      t.status == 'seated' ||
      tableBookingSeated(t)) {
    return colors.accent;
  }
  if (tableNeedsClearing(t)) return colors.danger;
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
  if (tableNeedsClearing(t)) return 'sparkles';
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
        .where(
          (t) =>
              t.tableId == tableId &&
              (t.status == 'open' || t.status == 'ready'),
        )
        .firstOrNull;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.md),
      child: DecoratedBox(
        // The floor is a MATERIAL, not a wash: the second neutral layer with a
        // faint dot grid (the same grid the dashboard editor snaps to), so the
        // room has ground and scale even before a single table is placed.
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.borderLight),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = math.min(
              constraints.maxWidth / bounds.width,
              kMaxFloorScale,
            );
            // When the cap bites, the room is narrower than the viewport —
            // centre it rather than pinning it to the left edge.
            final dx = math.max(
              0.0,
              (constraints.maxWidth - bounds.width * scale) / 2,
            );
            final child = CustomPaint(
              painter: _FloorGridPainter(
                pitch: 50 * scale,
                color: colors.border.withValues(alpha: 0.55),
              ),
              child: SizedBox(
                width: constraints.maxWidth,
                height: bounds.height * scale,
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
                  ],
                ),
              ),
            );
            if (!zoomable) return child;
            return InteractiveViewer(
              maxScale: 3,
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
  const TablesScreen({super.key});

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

  /// A reserved table flips by the clock (`held_from`), not by an event — a
  /// once-a-minute tick keeps the canvas and the counts honest between pulls.
  Timer? _clock;

  OrderNotifier get _notifier => ref.read(orderProvider.notifier);
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
    final seatedCount = allTables
        .where((t) => t.heldOrderId != null || t.status == 'seated')
        .length;
    // Kept for a booked party (or a teller's hold): counted once, shown amber.
    final heldCount = allTables
        .where(
          (t) =>
              t.heldOrderId == null &&
              t.status != 'seated' &&
              !tableBookingSeated(t) &&
              (t.status == 'held' || tableIsReserved(t)),
        )
        .length;
    final arrivals = ref.watch(orderProvider.select((s) => s.arrivals));
    // The work the floor owes itself: paid tables still waiting on a bus.
    final dirtyTables = allTables
        .where(tableNeedsClearing)
        .toList(
          growable: false,
        );
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

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: MadarIcon(
                      'chevron.backward',
                      tint: colors.textPrimary,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tr('tables.title'),
                          style: MadarType.h2.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        // The room at a glance. These chips carry the state
                        // vocabulary too, so no separate legend is needed —
                        // one row that both counts and teaches.
                        if (allTables.isNotEmpty)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                              top: Space.xs,
                            ),
                            child: Wrap(
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
                      ],
                    ),
                  ),
                  // Today's bookings — badge shows how many parties are due.
                  ActionButton(
                    label: arrivals.isEmpty
                        ? _tr('tables.arrivals')
                        : '${_tr('tables.arrivals')} · ${arrivals.length}',
                    icon: 'calendar.days',
                    variant: ActionVariant.outline,
                    onTap: () => unawaited(_openArrivals()),
                  ),
                  const SizedBox(width: Space.sm),
                  // The waitlist — badge shows how many parties wait.
                  ActionButton(
                    label: queue.isEmpty
                        ? _tr('tables.waitlist')
                        : '${_tr('tables.waitlist')} · ${queue.length}',
                    icon: 'clock',
                    variant: ActionVariant.outline,
                    onTap: () => unawaited(_openWaitlist()),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              if (tabs.length > 1)
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
              if (_swapFrom != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: Space.md),
                  child: _swapBanner(colors),
                ),
              const SizedBox(height: Space.md),
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
                    : SingleChildScrollView(
                        child: _canvas(
                          active,
                          tables,
                          tickets,
                          isWaiter: isWaiter,
                          colors: colors,
                        ),
                      ),
              ),
            ],
          ),
        ),
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
        Expanded(
          child: Text(_tr('tables.swap_pick'), style: MadarType.label),
        ),
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
  }) {
    TicketView? ticketOn(String tableId) => tickets
        .where(
          (t) =>
              t.tableId == tableId &&
              (t.status == 'open' || t.status == 'ready'),
        )
        .firstOrNull;
    return FloorCanvas(
      section: section,
      tables: tables,
      tickets: tickets,
      seatsWord: _tr('tables.seats'),
      words: TableStatusWords.of(ref.read(bridgeProvider)),
      zoomable: true,
      swapArmedId: _swapFrom,
      onTap: (t) => unawaited(
        _onTableTap(t, ticketOn(t.id), isWaiter: isWaiter),
      ),
      // Status + zone are one long-press away — the POS owns table STATE.
      onLongPress: (t) => unawaited(_tableSettingsSheet(t)),
    );
  }

  // ── actions ────────────────────────────────────────────────────────────────

  /// The live waiter ticket sitting on a table, if any.
  TicketView? _ticketOn(String tableId) => ref
      .read(orderProvider)
      .openTickets
      .where(
        (t) =>
            t.tableId == tableId && (t.status == 'open' || t.status == 'ready'),
      )
      .firstOrNull;

  Future<void> _onTableTap(
    FloorTableStateView t,
    TicketView? ticket, {
    required bool isWaiter,
  }) async {
    // Swap mode: the second tap completes the move/exchange.
    final from = _swapFrom;
    if (from != null) {
      setState(() => _swapFrom = null);
      if (from != t.id) await _notifier.swapTables(from, t.id);
      return;
    }
    if (t.heldOrderId != null) {
      await _heldTableSheet(t);
      return;
    }
    if (ticket != null) {
      await _ticketTableSheet(t, ticket, isWaiter: isWaiter);
      return;
    }
    // A paid-but-unbussed table asks its own question first.
    if (tableNeedsClearing(t)) {
      await _needsClearingSheet(t, isWaiter: isWaiter);
      return;
    }
    // A table kept for a booked party: seat them, mark them a no-show, or
    // knowingly seat a walk-in over the booking.
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
          _tr('tables.swap'),
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
    final hasCart = ref.read(orderProvider).cartLines.isNotEmpty;
    await _actionsSheet('${t.label} · ${_tr('tables.needs_clearing')}', [
      _SheetAction('sparkles', _tr('tables.clear'), () async {
        await _notifier.clearTable(t.id);
      }),
      if (!isWaiter && hasCart)
        _SheetAction('tray.and.arrow.down', _tr('tables.seat_here'), () async {
          _notifier.setCartTable(t.id, t.label);
          await _notifier.holdCart();
          if (mounted) await Navigator.of(context).maybePop();
        }),
      _SheetAction('arrow.triangle.2.circlepath', _tr('tables.swap'), () async {
        setState(() => _swapFrom = t.id);
      }),
      _SheetAction('gearshape', _tr('tables.settings'), () async {
        await _tableSettingsSheet(t);
      }),
    ]);
  }

  /// A free table: seat the live cart here, or start nothing.
  Future<void> _freeTableSheet(
    FloorTableStateView t, {
    required bool isWaiter,
  }) async {
    final hasCart = ref.read(orderProvider).cartLines.isNotEmpty;
    await _actionsSheet(t.label, [
      if (!isWaiter && hasCart)
        _SheetAction('tray.and.arrow.down', _tr('tables.seat_here'), () async {
          // Park the LIVE cart directly onto this table.
          _notifier.setCartTable(t.id, t.label);
          await _notifier.holdCart();
          if (mounted) await Navigator.of(context).maybePop();
        }),
      // Anything that isn't already available turns over from here — the
      // teller's manual counterpart to the automatic free-on-checkout.
      if (t.status != 'free')
        _SheetAction(
          'checkmark.circle',
          _tr('tables.make_available'),
          () async {
            await _notifier.makeTableAvailable(t);
          },
        ),
      _SheetAction('arrow.triangle.2.circlepath', _tr('tables.swap'), () async {
        setState(() => _swapFrom = t.id);
      }),
      _SheetAction('gearshape', _tr('tables.settings'), () async {
        await _tableSettingsSheet(t);
      }),
    ]);
  }

  /// Operational table state — the POS's half of the floor split (geometry is
  /// dashboard-authored): the status walk and which zone the PHYSICAL table
  /// currently sits in.
  Future<void> _tableSettingsSheet(FloorTableStateView t) async {
    final bridge = ref.read(bridgeProvider);
    final layout = ref.read(orderProvider).floorLayout;
    final ticket = _ticketOn(t.id);
    final occupied = t.heldOrderId != null || ticket != null;
    await _actionsSheet('${_tr('tables.settings')} · ${t.label}', [
      // Turning a table over is the teller's job, seated or not: a parked
      // order detaches, a live ticket refuses (see makeTableAvailable).
      if (t.status != 'free' || occupied)
        _SheetAction(
          'checkmark.circle',
          bridge.tr(key: 'tables.make_available'),
          () async {
            await _notifier.makeTableAvailable(t, ticket: ticket);
          },
        ),
      if (t.status != 'held' && !occupied)
        _SheetAction(
          'hand.raised',
          bridge.tr(key: 'tables.held_res'),
          () async {
            // removed: status is derived; sections are dashboard-authored
          },
        ),
      // Zone move — every OTHER section, plus "no section".
      for (final s in layout?.sections ?? const <FloorSectionInfo>[])
        if (t.sectionId != s.id)
          _SheetAction(
            'square.grid.2x2',
            '${bridge.tr(key: 'tables.section')} · ${s.name}',
            () async {
              // removed: status is derived; sections are dashboard-authored
            },
          ),
      if (t.sectionId != null)
        _SheetAction(
          'xmark.circle',
          bridge.tr(key: 'tables.no_section'),
          () async {
            // removed: status is derived; sections are dashboard-authored
          },
        ),
    ]);
  }

  /// A table owned by a held order: open / move / swap / waitlist / discard.
  Future<void> _heldTableSheet(FloorTableStateView t) async {
    final id = t.heldOrderId!;
    final locked = t.heldLockedByOther;
    await _actionsSheet(
      '${t.label}${(t.heldOrderName?.isNotEmpty ?? false) ? ' · ${t.heldOrderName}' : ''}',
      [
        _SheetAction('cart', _tr('tables.resume'), () async {
          if (locked) {
            _notifier.showToast(
              _tr('tables.locked'),
              tone: ChipTone.warning,
              icon: 'lock',
            );
            return;
          }
          await _notifier.switchToHeldOrder(id);
          if (mounted) await Navigator.of(context).maybePop();
        }),
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
        // The party left: detach the parked order (it survives, table-less)
        // and hand the table back to the room.
        _SheetAction(
          'checkmark.circle',
          _tr('tables.make_available'),
          () async {
            await _notifier.makeTableAvailable(t);
          },
        ),
        _SheetAction('gearshape', _tr('tables.settings'), () async {
          await _tableSettingsSheet(t);
        }),
      ],
    );
  }

  /// A waiter ticket's table: target rounds (waiter) or move it.
  Future<void> _ticketTableSheet(
    FloorTableStateView t,
    TicketView ticket, {
    required bool isWaiter,
  }) async {
    await _actionsSheet('${t.label} · ${ticket.ticketRef ?? ''}', [
      if (isWaiter)
        _SheetAction('cart', _tr('tables.resume'), () async {
          _notifier.selectTicket(ticket.id);
          if (mounted) await Navigator.of(context).maybePop();
        }),
      _SheetAction('arrow.triangle.2.circlepath', _tr('tables.move'), () async {
        setState(() => _swapFrom = t.id);
      }),
      _SheetAction('clock', _tr('tables.queue'), () async {
        await _createWishFlow('open_ticket', ticket.id);
      }),
      _SheetAction('checkmark.circle', _tr('tables.make_available'), () async {
        await _notifier.makeTableAvailable(t, ticket: ticket);
      }),
      _SheetAction('gearshape', _tr('tables.settings'), () async {
        await _tableSettingsSheet(t);
      }),
    ]);
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
                child: ActionButton(
                  label: '${bridge.tr(key: 'tables.wish_any')} ${s.name}',
                  variant: ActionVariant.outline,
                  onTap: () => unawaited(
                    Navigator.of(sheetContext).maybePop((s.id, null)),
                  ),
                ),
              ),
            ActionButton(
              label: bridge.tr(key: 'tables.pick'),
              variant: ActionVariant.outline,
              onTap: () =>
                  unawaited(Navigator.of(sheetContext).maybePop((null, ''))),
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
                        onCancel: () => unawaited(
                          _notifier.cancelTransfer(queue[i].id),
                        ),
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
                child: ActionButton(
                  label: a.label,
                  icon: a.icon,
                  variant: ActionVariant.outline,
                  onTap: () {
                    unawaited(Navigator.of(sheetContext).maybePop());
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
    final occupied = ticket != null || table.heldOrderId != null;
    final needsClearing = tableNeedsClearing(table);
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
    final slots =
        seatSlots(
              table.shape,
              table.width,
              table.height,
              table.seats,
            )
            .map<SeatSlot>(
              (s) => (x: s.x * scale, y: s.y * scale, angle: s.angle),
            )
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
    final who = table.heldOrderName?.trim().isNotEmpty ?? false
        ? table.heldOrderName!.trim()
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
            color: colors.textPrimary.withValues(
              alpha: occupied ? 0.16 : 0.06,
            ),
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
            if (table.heldLockedByOther)
              Positioned(
                right: (5 * scale).clamp(3, 8).toDouble(),
                top: (5 * scale).clamp(3, 8).toDouble(),
                child: MadarIcon('lock', tint: ring, size: glyphSize),
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
          ActionButton(
            label: fulfillLabel,
            variant: ActionVariant.outline,
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
            ActionButton(
              label: noShowLabel,
              icon: 'xmark.circle',
              variant: ActionVariant.outline,
              onTap: onNoShow,
            ),
            const SizedBox(width: Space.sm),
            ActionButton(
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
