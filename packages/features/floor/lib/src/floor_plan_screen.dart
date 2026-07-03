/// Floor plan + host board (render-and-operate) — a pixel-and-behavior
/// port of the Kotlin FloorPlanScreen.kt over the shared Rust core.
/// Geometry is authored in the dashboard; this renders the branch floor to
/// scale, shows live status, and drives host ops (seat / notify / set
/// status), plus the settle jump: tap a table occupied by an open ticket to
/// review + settle it.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_floor/src/floor_provider.dart';
import 'package:feature_floor/src/floor_sheets.dart';
import 'package:feature_floor/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (FloorPlanScreen.kt) that fall between the 4-pt Space
// steps — kept verbatim so the Flutter chrome measures identically.

/// Table outline stroke (natives: 2.dp).
const double _tableBorder = 2;

/// Table fill alpha over the status color (natives: 0.22f).
const double _tableFillAlpha = 0.22;

/// Canvas wash alpha over ink (natives: 0x0A black).
const double _canvasAlpha = 0.04;

/// Fallback canvas extent when a section carries none (natives: 1000×700).
const double _fallbackCanvasW = 1000;
const double _fallbackCanvasH = 700;

/// Seats line size inside a table (natives: 10.sp).
const double _seatsSize = 10;

/// Reservations header size (natives: 18.sp bold).
const double _resTitleSize = 18;

/// Reservation row radius / inset (natives: 10.dp / 10.dp).
const double _resRowRadius = 10;
const double _resRowPad = 10;

/// Gap between the Seat button and the bell (natives: 6.dp).
const double _bellGap = 6;

/// Live-status refresh period (matches the app's connectivity heartbeat).
const Duration _refreshPeriod = Duration(seconds: 15);

/// Dine-in table map: floor sections, a to-scale canvas with color-coded
/// live table states, and the reservations board (seat / notify). All
/// rendered state flows from [floorProvider]; tapping a table occupied by
/// an open ticket jumps to its review + settle, any other tap (and every
/// long-press) opens the status picker.
class FloorPlanScreen extends ConsumerStatefulWidget {
  const FloorPlanScreen({super.key});

  @override
  ConsumerState<FloorPlanScreen> createState() => _FloorPlanScreenState();
}

class _FloorPlanScreenState extends ConsumerState<FloorPlanScreen> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    // Post-frame: notifier writes during initState land mid-build (crash).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(floorProvider.notifier).loadFloor());
    });
    _refresh = Timer.periodic(
      _refreshPeriod,
      (_) => unawaited(ref.read(floorProvider.notifier).loadFloor()),
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  // ── taps ────────────────────────────────────────────────────────────────────
  /// Tap routing: occupied by an open ticket → summary + settle; otherwise
  /// the natives' status picker. Long-press always opens the status picker.
  Future<void> _onTapTable(FloorTableView table) async {
    final ticket = ref.read(floorProvider).ticketForTable(table.id);
    if (ticket != null) {
      await _openTicket(table, ticket);
      return;
    }
    await _openStatusPicker(table);
  }

  Future<void> _openStatusPicker(FloorTableView table) async {
    final status = await showMadarSheet<String>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => TableStatusSheet(table: table),
    );
    if (status != null) {
      await ref.read(floorProvider.notifier).setTableStatus(table.id, status);
    }
  }

  Future<void> _openTicket(FloorTableView table, TicketView ticket) async {
    final settle = await showMadarSheet<bool>(
      context,
      size: SheetSize.hug,
      builder: (_) => TableTicketSheet(ticket: ticket, tableLabel: table.label),
    );
    if (settle != true || !mounted) return;
    await showMadarSheet<bool>(
      context,
      size: SheetSize.large,
      builder: (_) => TableSettleSheet(ticket: ticket),
    );
  }

  Future<void> _openSeat(ReservationView booking) async {
    // Every seat session starts with a clean pick set — set up BEFORE the
    // sheet presents (floorProvider is kept alive, so this is safe).
    ref.read(floorProvider.notifier).clearSeatPicks();
    final floor = ref.read(floorProvider);
    final tables = floor.tablesIn(floor.activeSection?.id);
    await showMadarSheet<bool>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => SeatReservationSheet(booking: booking, tables: tables),
    );
  }

  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String tr(String key) => bridge.tr(key: key);
    // The board renders every slice (sections, tables, bookings, error,
    // toast) — the one legitimate whole-state watch on this screen.
    final floor = ref.watch(floorProvider);
    final notifier = ref.read(floorProvider.notifier);
    final section = floor.activeSection;
    final tables = floor.tablesIn(section?.id);
    final branchName = bridge.deviceConfig().branchName ?? '';
    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          MadarHeader(
            title: tr('reservations.title'),
            subtitle: branchName.isEmpty ? null : branchName,
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Stack(
                children: [
                  ListView(
                    padding: const EdgeInsetsDirectional.all(Space.lg),
                    children: [
                      if (floor.error case final error?) ...[
                        NoticeBanner(
                          text: error,
                          tone: ChipTone.danger,
                          icon: 'exclamationmark.circle',
                          onTap: notifier.clearError,
                        ),
                        const SizedBox(height: Space.md),
                      ],
                      if (floor.sections.length > 1) ...[
                        _SectionPicker(
                          sections: floor.sections,
                          activeId: section?.id,
                          onPick: notifier.pickSection,
                        ),
                        const SizedBox(height: Space.md),
                      ],
                      _FloorCanvas(
                        canvasW: (section?.canvasW ?? 0) > 0
                            ? section!.canvasW.toDouble()
                            : _fallbackCanvasW,
                        canvasH: (section?.canvasH ?? 0) > 0
                            ? section!.canvasH.toDouble()
                            : _fallbackCanvasH,
                        tables: tables,
                        onTap: (table) => unawaited(_onTapTable(table)),
                        onLongPress: (table) =>
                            unawaited(_openStatusPicker(table)),
                      ),
                      const SizedBox(height: Space.md),
                      Text(
                        tr('reservations.title'),
                        style: MadarType.h3.copyWith(
                          fontSize: _resTitleSize,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      if (floor.reservations.isEmpty)
                        Text(
                          tr('reservations.noBookings'),
                          style: MadarType.bodySm.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      for (final booking in floor.reservations) ...[
                        _ReservationRow(
                          booking: booking,
                          seatLabel: tr('reservations.seat'),
                          onSeat: () => unawaited(_openSeat(booking)),
                          onNotify: () => unawaited(
                            notifier.notifyReservation(booking.id),
                          ),
                        ),
                        const SizedBox(height: Space.md),
                      ],
                    ],
                  ),
                  // Toasts float above everything on this screen.
                  ToastHost(floor.toast, onDismiss: notifier.dismissToast),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section picker ──────────────────────────────────────────────────────────────

/// One outlined chip per floor section (natives: a Row of OutlinedButtons;
/// the active one is accent-tinted here so the pick reads).
class _SectionPicker extends StatelessWidget {
  const _SectionPicker({
    required this.sections,
    required this.activeId,
    required this.onPick,
  });

  final List<FloorSectionView> sections;
  final String? activeId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final section in sections)
          FloorButton(
            label: section.name,
            variant: section.id == activeId
                ? FloorButtonVariant.primary
                : FloorButtonVariant.outline,
            onTap: () => onPick(section.id),
          ),
      ],
    );
  }
}

// ── Floor canvas ────────────────────────────────────────────────────────────────

/// The to-scale canvas — the natives' BoxWithConstraintsFloor: full width,
/// height following the section's aspect, every table positioned + sized by
/// `geometry × (width / canvasW)`.
class _FloorCanvas extends StatelessWidget {
  const _FloorCanvas({
    required this.canvasW,
    required this.canvasH,
    required this.tables,
    required this.onTap,
    required this.onLongPress,
  });

  final double canvasW;
  final double canvasH;
  final List<FloorTableView> tables;
  final ValueChanged<FloorTableView> onTap;
  final ValueChanged<FloorTableView> onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.sm),
      child: ColoredBox(
        color: colors.textPrimary.withValues(alpha: _canvasAlpha),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = constraints.maxWidth / canvasW;
            return SizedBox(
              width: constraints.maxWidth,
              height: canvasH * scale,
              child: Stack(
                children: [
                  for (final table in tables)
                    PositionedDirectional(
                      start: table.posX * scale,
                      top: table.posY * scale,
                      width: table.width * scale,
                      height: table.height * scale,
                      child: _TableCell(
                        table: table,
                        onTap: () => onTap(table),
                        onLongPress: () => onLongPress(table),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One table on the canvas — status-tinted fill + border (rect or circle),
/// label + seats centered.
class _TableCell extends StatelessWidget {
  const _TableCell({
    required this.table,
    required this.onTap,
    required this.onLongPress,
  });

  final FloorTableView table;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final color = tableColor(colors, table.status);
    final radius = table.shape == 'circle'
        ? BorderRadius.circular(Radii.pill)
        : BorderRadius.circular(Radii.xs);
    return GestureDetector(
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      onLongPress: () {
        MadarHaptics.impact();
        onLongPress();
      },
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: _tableFillAlpha),
          borderRadius: radius,
          border: Border.all(color: color, width: _tableBorder),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  table.label,
                  maxLines: 1,
                  style: MadarType.label.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  '${table.seats}',
                  maxLines: 1,
                  style: MadarType.labelSm.copyWith(
                    fontSize: _seatsSize,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Reservations board ──────────────────────────────────────────────────────────

/// One booking row — name + "party · status", a Seat button, the notify
/// bell (natives: an OutlinedButton + a 🔔 TextButton).
class _ReservationRow extends StatelessWidget {
  const _ReservationRow({
    required this.booking,
    required this.seatLabel,
    required this.onSeat,
    required this.onNotify,
  });

  final ReservationView booking;
  final String seatLabel;
  final VoidCallback onSeat;
  final VoidCallback onNotify;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      padding: const EdgeInsetsDirectional.all(_resRowPad),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(_resRowRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
                Text(
                  '${booking.partySize} · ${booking.status}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.label.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          FloorButton(
            label: seatLabel,
            variant: FloorButtonVariant.outline,
            onTap: onSeat,
          ),
          const SizedBox(width: _bellGap),
          TactileScale(
            onTap: onNotify,
            child: const Padding(
              padding: EdgeInsetsDirectional.all(Space.sm),
              child: Text('🔔'),
            ),
          ),
        ],
      ),
    );
  }
}
