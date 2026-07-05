/// Past shifts — the branch's closed-shift history, a pixel-and-behavior
/// port of the Kotlin ShiftHistoryScreen (in CashAndShiftsScreen.kt).
/// Responsive: a fixed-column table at container width ≥
/// [Responsive.wideTable], per-row cards below it. The locally-open shift
/// is pinned on top (the natives' `shiftsWithLocalOpen`); tapping a row
/// opens the shared [ShiftReportSheet] with that shift's Z-report via
/// `shiftReportFor`. All data + rules live in the core; state lives in
/// [shiftHistoryProvider]; this screen renders. Full-screen over the order
/// screen.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_shift/src/controls.dart';
import 'package:feature_shift/src/shift_providers.dart';
import 'package:feature_shift/src/shift_report_sheet.dart';
import 'package:flutter/material.dart'
    show CircularProgressIndicator, Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (CashAndShiftsScreen.kt) that fall between the 4-pt Space
// steps — kept verbatim so the Flutter chrome measures identically.

/// Content cap (natives: widthIn(max = 880.dp)).
const double _contentMaxWidth = 880;

/// Fixed table columns (natives: ShiftStatusW / ShiftDeclaredW / ShiftChevW
/// = 26 / 110 / 44.dp).
const double _statusColWidth = 26;
const double _declaredColWidth = 110;
const double _chevronColWidth = 44;

/// Shift status dot (natives: 8.dp circle).
const double _statusDotSize = 8;

/// Row report-fetch spinner (natives: 14.dp / 2.dp stroke).
const double _rowSpinnerSize = 14;
const double _rowSpinnerStroke = 2;

/// The branch's shift history (full-screen over the order screen) —
/// read-only; nothing here moves shared state. The header's back pops it
/// via `Navigator.maybePop`.
class ShiftHistoryScreen extends ConsumerWidget {
  /// Creates the shift-history screen.
  const ShiftHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    // Narrow slice: only the toast layer repaints on toast churn.
    final toast = ref.watch(shiftHistoryProvider.select((s) => s.toast));
    // Scaffold: every screen root owns its own Scaffold in this app.
    return Scaffold(
      backgroundColor: colors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              MadarHeader(
                title: t('shifts.title'),
                onBack: () => Navigator.maybePop(context),
              ),
              const Expanded(
                child: SafeArea(top: false, child: _HistoryBody()),
              ),
            ],
          ),
          // Toasts float above everything on this screen.
          SafeArea(
            child: ToastHost(
              toast,
              onDismiss: (id) =>
                  ref.read(shiftHistoryProvider.notifier).dismissToast(id),
            ),
          ),
        ],
      ),
    );
  }
}

/// The natives' `shiftsWithLocalOpen`: prepend the locally-opened-but-
/// unsynced shift to the top of the page if it isn't already present, so
/// the live shift always shows.
List<ShiftSummaryView> _rowsWithLocalOpen(
  List<ShiftSummaryView> shifts,
  ShiftView? live,
) {
  if (live == null || !live.isOpen || shifts.any((s) => s.id == live.id)) {
    return shifts;
  }
  final pinned = ShiftSummaryView(
    id: live.id,
    tellerName: live.tellerName,
    openedAt: live.openedAt,
    openingCashMinor: live.openingCashMinor,
    status: live.status,
    isOpen: live.isOpen,
  );
  return [pinned, ...shifts];
}

/// The page body — skeleton / empty / responsive table or cards, driven by
/// its own narrow slices of [shiftHistoryProvider]. Watches only the row
/// LIST here; per-row state (report spinner, orders expansion) is watched
/// row-locally in [_ShiftRowGroup] so toggling one row never rebuilds the
/// rest of the table.
class _HistoryBody extends ConsumerWidget {
  const _HistoryBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    final shifts = ref.watch(shiftHistoryProvider.select((s) => s.shifts));
    final live = ref.watch(shiftHistoryProvider.select((s) => s.live));
    final loading = ref.watch(shiftHistoryProvider.select((s) => s.loading));
    if (loading && shifts.isEmpty && live == null) {
      return const Align(alignment: Alignment.topCenter, child: SkeletonList());
    }
    final rows = _rowsWithLocalOpen(shifts, live);
    if (rows.isEmpty) {
      return EmptyState(
        icon: 'clock.arrow.circlepath',
        title: t('shifts.empty'),
      );
    }
    final currency = bridge.currentSession()?.currencyCode ?? '';
    // Width-driven, matching the natives' `wide = maxWidth >= 680`.
    return ResponsiveBuilder(
      builder: (context, info) {
        final wide = info.isWideTable;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            // Wide: header + rows live in one card; narrow keeps per-row
            // cards, built lazily.
            child: wide
                ? ListView(
                    padding: const EdgeInsetsDirectional.all(Space.lg),
                    children: [
                      ShiftFlushCard(
                        children: [
                          _ColumnHeader(tr: t),
                          for (final (index, s) in rows.indexed)
                            _ShiftRowGroup(
                              key: ValueKey(s.id),
                              shift: s,
                              odd: index.isOdd,
                              currency: currency,
                              bridge: bridge,
                              wide: true,
                            ),
                        ],
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsetsDirectional.all(Space.lg),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final s = rows[index];
                      return Padding(
                        padding: EdgeInsetsDirectional.only(
                          top: index > 0 ? Space.sm : 0,
                        ),
                        child: _ShiftRowGroup(
                          key: ValueKey(s.id),
                          shift: s,
                          odd: index.isOdd,
                          currency: currency,
                          bridge: bridge,
                          wide: false,
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

/// One shift's row + (optionally) its inline orders panel — the rebuild
/// isolation unit. Watches only ITS shift's slices of
/// [shiftHistoryProvider], so a spinner or expansion on one row leaves
/// every other row untouched. The orders slices are watched only while
/// expanded, so collapsed rows also ignore orders churn entirely.
class _ShiftRowGroup extends ConsumerWidget {
  const _ShiftRowGroup({
    required this.shift,
    required this.odd,
    required this.currency,
    required this.bridge,
    required this.wide,
    super.key,
  });

  final ShiftSummaryView shift;

  /// Zebra fill (wide table only).
  final bool odd;
  final String currency;
  final MadarBridge bridge;

  /// Table row (with trailing hairline) vs narrow card.
  final bool wide;

  /// Open a shift's Z-report in the shared preview sheet — the live shift
  /// loads the current report in-sheet; a past shift is fetched via
  /// `shiftReportFor` first (spinner in the row's chevron slot, danger
  /// toast on failure — the natives' `openShiftReportPreviewFor`).
  Future<void> _openReport(BuildContext context, WidgetRef ref) async {
    final s = shift;
    final state = ref.read(shiftHistoryProvider);
    if (state.reportLoadingId != null) return;
    MadarHaptics.selection();
    if (s.isOpen && s.id == state.live?.id) {
      await showMadarSheet<void>(
        context,
        size: SheetSize.large,
        builder: (_) => const ShiftReportSheet(),
      );
      return;
    }
    final report = await ref
        .read(shiftHistoryProvider.notifier)
        .fetchReport(s.id);
    if (report == null || !context.mounted) return;
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => ShiftReportSheet(report: report, shiftId: s.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = shift;
    final loadingReport = ref.watch(
      shiftHistoryProvider.select((st) => st.reportLoadingId == s.id),
    );
    final expanded = ref.watch(
      shiftHistoryProvider.select((st) => st.expanded.contains(s.id)),
    );
    void toggleOrders() => unawaited(
      ref.read(shiftHistoryProvider.notifier).toggleShiftOrders(s.id),
    );
    final panel = expanded
        ? _ShiftOrdersPanel(
            orders: ref.watch(
              shiftHistoryProvider.select((st) => st.ordersByShift[s.id]),
            ),
            loading: ref.watch(
              shiftHistoryProvider.select((st) => st.ordersLoadingId == s.id),
            ),
            currency: currency,
            bridge: bridge,
          )
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide)
          _WideShiftRow(
            shift: s,
            currency: currency,
            odd: odd,
            loadingReport: loadingReport,
            bridge: bridge,
            onTap: () => unawaited(_openReport(context, ref)),
            ordersExpanded: expanded,
            onToggleOrders: toggleOrders,
          )
        else
          _NarrowShiftCard(
            shift: s,
            currency: currency,
            loadingReport: loadingReport,
            bridge: bridge,
            onTap: () => unawaited(_openReport(context, ref)),
            ordersExpanded: expanded,
            onToggleOrders: toggleOrders,
          ),
        ?panel,
        if (wide) const ShiftHairline(),
      ],
    );
  }
}

/// Status-dot color (the natives' `_statusColor`): open→success,
/// force_closed→danger, closed/other→muted.
Color _statusColor(String status, MadarColors colors) => switch (status) {
  'open' => colors.success,
  'force_closed' => colors.danger,
  _ => colors.textMuted,
};

/// Wide-table column header — 42-tall, surfaceAlt fill, bottom hairline:
/// `[status dot 26][Teller][Opened][Closed][Declared 110][chevron 44]`.
/// The status-dot label is blank; Declared end-aligns.
class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.tr});

  final String Function(String key) tr;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ColoredBox(
      color: colors.surfaceAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: Metrics.tableHeaderHeight,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
            ),
            child: Row(
              spacing: Space.md,
              children: [
                const SizedBox(width: _statusColWidth),
                Expanded(child: _HeaderCell(label: tr('shift.teller'))),
                Expanded(child: _HeaderCell(label: tr('shift.opened_at'))),
                Expanded(child: _HeaderCell(label: tr('shifts.closed'))),
                SizedBox(
                  width: _declaredColWidth,
                  child: _HeaderCell(
                    label: tr('shifts.declared'),
                    alignEnd: true,
                  ),
                ),
                const SizedBox(width: _chevronColWidth),
              ],
            ),
          ),
          const ShiftHairline(),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label, this.alignEnd = false});

  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Align(
      alignment: alignEnd
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: MadarType.labelSm.copyWith(color: colors.textMuted),
      ),
    );
  }
}

/// A single table row, 56-tall, zebra fill on odd rows —
/// `[status dot][Teller][Opened][Closed][Declared][chevron]`.
class _WideShiftRow extends StatelessWidget {
  const _WideShiftRow({
    required this.shift,
    required this.currency,
    required this.odd,
    required this.loadingReport,
    required this.bridge,
    required this.onTap,
    required this.ordersExpanded,
    required this.onToggleOrders,
  });

  final ShiftSummaryView shift;
  final String currency;
  final bool odd;
  final bool loadingReport;
  final MadarBridge bridge;
  final VoidCallback onTap;

  /// The inline orders panel under this row is open.
  final bool ordersExpanded;

  /// Expand/collapse the inline orders panel.
  final VoidCallback onToggleOrders;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final s = shift;
    return ColoredBox(
      color: odd ? colors.surfaceAlt : Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: Metrics.tableRowHeight,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.lg,
          ),
          child: Row(
            spacing: Space.md,
            children: [
              SizedBox(
                width: _statusColWidth,
                child: Center(
                  child: Container(
                    width: _statusDotSize,
                    height: _statusDotSize,
                    decoration: BoxDecoration(
                      color: _statusColor(s.status, colors),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  s.tellerName ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
              ),
              Expanded(
                child: Text(
                  bridge.formatTime(
                    rfc3339: s.openedAt,
                    style: TimeStyle.dateTime,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.bodySm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  s.closedAt == null
                      ? '—'
                      : bridge.formatTime(
                          rfc3339: s.closedAt!,
                          style: TimeStyle.dateTime,
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.bodySm.copyWith(
                    color: s.closedAt == null
                        ? colors.textMuted
                        : colors.textSecondary,
                  ),
                ),
              ),
              SizedBox(
                width: _declaredColWidth,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    s.closingDeclaredMinor == null
                        ? '—'
                        : Money.format(
                            s.closingDeclaredMinor!,
                            currency: currency,
                          ),
                    maxLines: 1,
                    textDirection: TextDirection.ltr,
                    style: MadarType.money.copyWith(
                      color: s.closingDeclaredMinor == null
                          ? colors.textMuted
                          : colors.textPrimary,
                    ),
                  ),
                ),
              ),
              // Inline orders expander — row by row, printable.
              _OrdersToggle(expanded: ordersExpanded, onTap: onToggleOrders),
              SizedBox(
                width: _chevronColWidth,
                child: Center(
                  child: _RowDisclosure(loading: loadingReport),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Narrow row card: opened date + status chip up top, then the opening /
/// declared / discrepancy metric rows.
class _NarrowShiftCard extends StatelessWidget {
  const _NarrowShiftCard({
    required this.shift,
    required this.currency,
    required this.loadingReport,
    required this.bridge,
    required this.onTap,
    required this.ordersExpanded,
    required this.onToggleOrders,
  });

  final ShiftSummaryView shift;
  final String currency;
  final bool loadingReport;
  final MadarBridge bridge;
  final VoidCallback onTap;

  /// The inline orders panel under this card is open.
  final bool ordersExpanded;

  /// Expand/collapse the inline orders panel.
  final VoidCallback onToggleOrders;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final s = shift;
    String t(String key) => bridge.tr(key: key);
    final discrepancy = s.discrepancyMinor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.borderLight),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      bridge.formatTime(
                        rfc3339: s.openedAt,
                        style: TimeStyle.dateShort,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  StatusChip(
                    label: t(s.isOpen ? 'shifts.open_now' : 'shifts.closed'),
                    tone: s.isOpen ? ChipTone.success : ChipTone.neutral,
                  ),
                  _OrdersToggle(
                    expanded: ordersExpanded,
                    onTap: onToggleOrders,
                  ),
                  _RowDisclosure(loading: loadingReport),
                ],
              ),
              _MetricRow(
                label: t('shifts.opening'),
                value: Money.format(s.openingCashMinor, currency: currency),
              ),
              if (s.closingDeclaredMinor case final declared?)
                _MetricRow(
                  label: t('shifts.declared'),
                  value: Money.format(declared, currency: currency),
                ),
              if (discrepancy != null && discrepancy != 0)
                _MetricRow(
                  label: t('shifts.discrepancy'),
                  value:
                      '${discrepancy > 0 ? '+' : '−'}'
                      '${Money.format(discrepancy.abs(), currency: currency)}',
                  tone: ChipTone.danger,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The row's trailing affordance: a forward chevron, or a small spinner
/// while that row's Z-report is being fetched.
class _RowDisclosure extends StatelessWidget {
  const _RowDisclosure({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    if (loading) {
      return SizedBox.square(
        dimension: _rowSpinnerSize,
        child: CircularProgressIndicator(
          color: colors.accent,
          strokeWidth: _rowSpinnerStroke,
        ),
      );
    }
    return MadarIcon('chevron.forward', tint: colors.textMuted);
  }
}

/// The natives' `MetricRow`: label ↔ tabular money value, optional tone.
class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final ChipTone? tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      spacing: Space.md,
      children: [
        Text(
          label,
          style: MadarType.bodySm.copyWith(
            color: tone?.resolve(colors) ?? colors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: MadarType.money.copyWith(
            color: tone?.resolve(colors) ?? colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// The inline orders expander on a shift row — a list glyph that flips to a
/// collapse chevron while its panel is open. Separate from the row tap
/// (which opens the Z-report preview).
class _OrdersToggle extends StatelessWidget {
  const _OrdersToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return GestureDetector(
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox.square(
        dimension: _chevronColWidth,
        child: Center(
          child: MadarIcon(
            expanded ? 'chevron.up' : 'list.bullet',
            tint: expanded ? colors.accent : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// A past shift's orders, row by row under its shift row: number · time ·
/// payment method · total, voided rows struck through, each printable via
/// the trailing printer glyph. Loaded lazily on first expand.
class _ShiftOrdersPanel extends ConsumerWidget {
  const _ShiftOrdersPanel({
    required this.orders,
    required this.loading,
    required this.currency,
    required this.bridge,
  });

  /// The loaded orders — null while the first fetch is in flight.
  final List<OrderSummaryView>? orders;
  final bool loading;
  final String currency;
  final MadarBridge bridge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final orders = this.orders;
    if (loading || orders == null) {
      return const Padding(
        padding: EdgeInsetsDirectional.all(Space.lg),
        child: SkeletonList(count: 3),
      );
    }
    if (orders.isEmpty) {
      return Padding(
        padding: const EdgeInsetsDirectional.all(Space.lg),
        child: Text(
          bridge.tr(key: 'shifts.no_orders'),
          style: MadarType.bodySm.copyWith(color: colors.textMuted),
        ),
      );
    }
    return ColoredBox(
      color: colors.surfaceAlt.withValues(alpha: 0.5),
      child: Column(
        children: [
          for (final order in orders)
            _ShiftOrderLine(
              order: order,
              currency: currency,
              bridge: bridge,
              onPrint: () => unawaited(
                ref.read(shiftHistoryProvider.notifier).printOrder(order),
              ),
            ),
        ],
      ),
    );
  }
}

/// One order line in the panel. Tapping the row opens the shared receipt
/// preview (print from there too); the trailing printer glyph one-tap
/// prints. Voided rows fade with a struck-through total.
class _ShiftOrderLine extends ConsumerWidget {
  const _ShiftOrderLine({
    required this.order,
    required this.currency,
    required this.bridge,
    required this.onPrint,
  });

  final OrderSummaryView order;
  final String currency;
  final MadarBridge bridge;
  final VoidCallback onPrint;

  Future<void> _openPreview(BuildContext context, WidgetRef ref) async {
    final ReceiptView receipt;
    try {
      receipt = await bridge.orderReceiptView(orderId: order.id);
    } on MadarError {
      return; // Best-effort — a missing cached receipt just no-ops.
    }
    if (!context.mounted) return;
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => ReceiptSheet(receipt: receipt),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final voided = order.status == 'voided';
    final number = order.orderNumber;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_openPreview(context, ref)),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm,
        ),
        child: Row(
          spacing: Space.md,
          children: [
            SizedBox(
              width: 52,
              child: Text(
                number != null ? '#$number' : '—',
                style: MadarType.title.copyWith(
                  fontWeight: FontWeight.w700,
                  color: voided ? colors.textMuted : colors.textPrimary,
                ),
              ),
            ),
            Text(
              bridge.formatTime(
                rfc3339: order.createdAt,
                style: TimeStyle.time,
              ),
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
            Expanded(
              child: Text(
                voided ? bridge.tr(key: 'history.voided') : order.paymentLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.bodySm.copyWith(
                  color: voided ? colors.danger : colors.textMuted,
                ),
              ),
            ),
            Text(
              Money.format(order.totalMinor, currency: currency),
              textDirection: TextDirection.ltr,
              style: MadarType.money.copyWith(
                color: voided ? colors.textMuted : colors.textPrimary,
                decoration: voided ? TextDecoration.lineThrough : null,
              ),
            ),
            GestureDetector(
              onTap: onPrint,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsetsDirectional.all(Space.xs),
                child: MadarIcon('printer', tint: colors.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
