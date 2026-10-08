/// The till report (`features/tills/till-report-sheet.tsx` with
/// `reconciliation-table.tsx`, `till-spot-views.tsx`, `till-deductions.tsx`;
/// SELL-TIL-045–054, -062): an end-side panel (full screen on a phone), held
/// in the URL as `?report=<till id>`.
///
/// Section order: info, Sales, Payment summary, Payment check, Cash
/// reconciliation, Spot reports viewed, Stock used, Cash movements.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        DeductionLogRow,
        ShiftSummary,
        TillReconciliationLine,
        TillReportResponse,
        TillSpotView;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'till_badges.dart';
import 'tills_data.dart';

/// The web's `sm:max-w-md`.
const double tillReportWidth = 448;

/// Opens the report panel; it shows the till [tillId] holds and closes
/// itself when [tillId] becomes null. [onOpenTill] switches it to another
/// till ("See the other till").
Future<void> showTillReport(
  BuildContext context, {
  required ValueListenable<String?> tillId,
  required ValueChanged<String> onOpenTill,
}) => showDashSidePanel<void>(
  context,
  width: tillReportWidth,
  builder: (_) => TillReportPanel(tillId: tillId, onOpenTill: onOpenTill),
);

class TillReportPanel extends StatefulWidget {
  const TillReportPanel({
    required this.tillId,
    required this.onOpenTill,
    super.key,
  });

  final ValueListenable<String?> tillId;
  final ValueChanged<String> onOpenTill;

  @override
  State<TillReportPanel> createState() => _TillReportPanelState();
}

class _TillReportPanelState extends State<TillReportPanel> {
  @override
  void initState() {
    super.initState();
    widget.tillId.addListener(_changed);
  }

  @override
  void dispose() {
    widget.tillId.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (widget.tillId.value == null) {
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      final nav = Navigator.of(context);
      if (route.isCurrent) {
        nav.pop();
      } else {
        nav.removeRoute(route);
      }
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.tillId.value;
    if (id == null) return const SizedBox.shrink();
    return TillReportView(
      key: ValueKey(id),
      tillId: id,
      onOpenTill: widget.onOpenTill,
    );
  }
}

/// The report of one till inside a [DashSurface].
class TillReportView extends ConsumerWidget {
  const TillReportView({
    required this.tillId,
    required this.onOpenTill,
    super.key,
  });

  final String tillId;
  final ValueChanged<String> onOpenTill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final report = ref.watch(tillReportProvider(tillId));
    final summary = ref.watch(tillSummaryProvider(tillId));
    final data = report.value;
    Widget body;
    if (report.hasError && data == null) {
      body = DashErrorState(
        title: t('tills.report.loadError'),
        onRetry: () => ref.invalidate(tillReportProvider(tillId)),
      );
    } else if (data == null) {
      body = Column(
        key: const ValueKey('till-report-loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          for (var i = 0; i < 4; i++)
            const DashSkeleton(height: Space.xxl * 3, radius: Radii.card),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          _InfoCard(report: data, onOpenTill: onOpenTill),
          if (summary.value case final s?) _SalesCard(summary: s),
          _PaymentsCard(report: data),
          if (data.reconciliation.isNotEmpty)
            ReconciliationTable(lines: data.reconciliation),
          _CashCard(report: data),
          TillSpotViews(tillId: tillId),
          TillDeductions(tillId: tillId),
          if (data.cashMovements.isNotEmpty) _MovementsSection(report: data),
        ],
      );
    }
    return DashSurface(
      title: t('tills.report.title'),
      description: data?.till.tellerName ?? t('common.loading'),
      bodyPadding: const EdgeInsetsDirectional.all(Space.lg),
      body: body,
    );
  }
}

/// A label / figure line of a report card (`Row`).
class ReportLine extends StatelessWidget {
  const ReportLine({
    required this.label,
    required this.value,
    this.color,
    this.labelColor,
    this.small = false,
    this.indent = false,
    super.key,
  });

  final String label;
  final String value;

  /// Both words in this colour (a destructive "Voided").
  final Color? color;
  final Color? labelColor;
  final bool small;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final base = small ? DashType.small : DashType.body;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent ? Space.md : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.sm,
        children: [
          Expanded(
            child: Text(
              label,
              style: base.copyWith(
                color: labelColor ?? color ?? c.textSecondary,
              ),
            ),
          ),
          Text(
            dashFigure(value),
            textAlign: TextAlign.end,
            style: DashType.monoMedium.copyWith(
              fontSize: small ? 12 : 14,
              color: color ?? c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.children, this.title, super.key});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          if (title != null)
            Semantics(
              header: true,
              child: Text(
                title!,
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.xs),
    child: Divider(
      height: 1,
      thickness: 1,
      color: context.madarColors.hairline,
    ),
  );
}

class _InfoCard extends ConsumerWidget {
  const _InfoCard({required this.report, required this.onOpenTill});

  final TillReportResponse report;
  final ValueChanged<String> onOpenTill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final till = report.till;
    final device = [
      till.deviceCode,
      till.deviceLabel,
    ].where((s) => s != null && s.isNotEmpty).join(' · ');
    final range = report.orderNumberRange;
    String num(int? n) =>
        range.deviceCode != null && range.deviceCode!.isNotEmpty
        ? '${range.deviceCode}-${Strings.jsString(n)}'
        : Strings.jsString(n);
    final held = report.heldOrdersLeftOpen;
    final heldTotal = report.heldOrdersLeftOpenTotal;
    final badges = [
      if (VerificationBadge.shows(till.verification))
        VerificationBadge(verification: till.verification),
      if (till.openedWhileAnotherOpen)
        FlagBadge(till: till, onOpenOther: onOpenTill),
    ];
    return _ReportCard(
      key: const ValueKey('till-report-info'),
      children: [
        ReportLine(
          label: t('tills.opened'),
          value: fmt.fmtDateTime(till.openedAt),
        ),
        if (till.closedAt != null)
          ReportLine(
            label: t('tills.closed'),
            value: fmt.fmtDateTime(till.closedAt),
          ),
        if (device.isNotEmpty)
          ReportLine(label: t('tills.device'), value: device),
        if (range.first != null)
          ReportLine(
            label: t('tills.orderRange'),
            value: '${num(range.first)} – ${num(range.last)}',
          ),
        if (report.openBillsAtClose != null)
          ReportLine(
            label: t('tills.openBillsAtClose'),
            value: '${report.openBillsAtClose}',
          ),
        if (held != null && held != 0)
          ReportLine(
            label: t('tills.heldOrdersLeftOpen'),
            value: heldTotal != null
                ? '$held · ${fmt.fmtMoney(heldTotal)}'
                : '$held',
          ),
        if (report.oldBillsAtClose != null)
          ReportLine(
            label: t('tills.oldBillsAtClose'),
            value: '${report.oldBillsAtClose}',
          ),
        if (badges.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: badges,
            ),
          ),
      ],
    );
  }
}

class _SalesCard extends ConsumerWidget {
  const _SalesCard({required this.summary});

  final ShiftSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final danger = DashTone.danger.foreground(context.madarColors);
    return _ReportCard(
      key: const ValueKey('till-summary'),
      title: t('tills.salesSummary'),
      children: [
        ReportLine(
          label: t('dashboard.orders'),
          value: '${summary.totalOrders}',
        ),
        ReportLine(
          label: t('dashboard.revenue'),
          value: fmt.fmtMoney(summary.totalRevenue),
        ),
        if (summary.totalDiscount != 0)
          ReportLine(
            label: t('nav.discounts'),
            value: fmt.fmtMoney(summary.totalDiscount),
          ),
        if (summary.totalTax != 0)
          ReportLine(
            label: t('tills.tax'),
            value: fmt.fmtMoney(summary.totalTax),
          ),
        if (summary.voidedOrders != 0)
          ReportLine(
            label: t('orders.voided'),
            value: '${summary.voidedOrders}',
            color: danger,
          ),
      ],
    );
  }
}

class _PaymentsCard extends ConsumerWidget {
  const _PaymentsCard({required this.report});

  final TillReportResponse report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    return _ReportCard(
      key: const ValueKey('till-payments'),
      title: t('tills.paymentSummary'),
      children: [
        if (report.paymentSummary.isEmpty)
          Text(
            t('common.noResults'),
            style: DashType.body.copyWith(color: c.textSecondary),
          )
        else
          for (final p in report.paymentSummary)
            Row(
              spacing: Space.sm,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: paymentMethodLabel(t, p.paymentMethod),
                      children: [
                        TextSpan(
                          text: ' (${p.orderCount})',
                          style: DashType.small.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
                ),
                Text(
                  dashFigure(fmt.fmtMoney(p.total)),
                  style: DashType.monoMedium.copyWith(
                    fontSize: 14,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
        const _Rule(),
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: Text(
                t('tills.netPayments'),
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
            ),
            Text(
              dashFigure(fmt.fmtMoney(report.netPayments)),
              style: DashType.monoStrong.copyWith(
                fontSize: 14,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
        // Tips sit outside the method buckets and outside net payments.
        if (report.totalTips != 0) ...[
          const _Rule(),
          ReportLine(
            label: t('tills.tips'),
            value: fmt.fmtMoney(report.totalTips),
          ),
          if (report.cashTips != 0)
            ReportLine(
              label: t('tills.tipsCash'),
              value: fmt.fmtMoney(report.cashTips),
              small: true,
              indent: true,
            ),
        ],
        if (report.voidedAmount != 0)
          ReportLine(
            label: t('dashboard.voided'),
            value: fmt.fmtMoney(report.voidedAmount),
            color: DashTone.danger.foreground(c),
          ),
      ],
    );
  }
}

/// The per-method close check (SELL-TIL-050). Empty for tills closed before
/// the rework, and then not shown.
class ReconciliationTable extends ConsumerWidget {
  const ReconciliationTable({required this.lines, super.key});

  final List<TillReconciliationLine> lines;

  static DashTone _tone(String status) => switch (status) {
    'checked' => DashTone.success,
    'disagreed' => DashTone.danger,
    _ => DashTone.neutral,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (lines.isEmpty) return const SizedBox.shrink();
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final head = DashType.tableHeader.copyWith(color: c.textSecondary);
    final figure = DashType.mono.copyWith(fontSize: 13, color: c.textPrimary);
    Widget cell(Widget child, {bool end = false, bool first = false}) =>
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: first ? 0 : Space.md,
            top: Space.xs + 2,
            bottom: Space.xs + 2,
          ),
          child: Align(
            alignment: end
                ? AlignmentDirectional.topEnd
                : AlignmentDirectional.topStart,
            child: child,
          ),
        );
    final rows = <TableRow>[
      TableRow(
        children: [
          cell(
            Text(t('tills.reconciliation.method'), style: head),
            first: true,
          ),
          cell(Text(t('tills.reconciliation.system'), style: head), end: true),
          cell(
            Text(t('tills.reconciliation.declared'), style: head),
            end: true,
          ),
          cell(Text(t('common.status'), style: head), end: true),
        ],
      ),
      for (final l in lines)
        TableRow(
          key: ValueKey('reconciliation-line-${l.method}'),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.hairline)),
          ),
          children: [
            cell(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    paymentMethodLabel(t, l.method),
                    style: DashType.body.copyWith(color: c.textPrimary),
                  ),
                  if (l.note != null && l.note!.isNotEmpty)
                    Text(
                      l.note!,
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                  if (l.changedAfterClose)
                    Text(
                      t(
                        'tills.reconciliation.changedAfterClose',
                        args: {'amount': fmt.fmtMoney(l.currentSystemTotal)},
                      ),
                      style: DashType.small.copyWith(
                        color: DashTone.warning.foreground(c),
                      ),
                    ),
                ],
              ),
              first: true,
            ),
            cell(
              Text(dashFigure(fmt.fmtMoney(l.systemTotal)), style: figure),
              end: true,
            ),
            cell(
              Text(
                l.declaredAmount != null
                    ? dashFigure(fmt.fmtMoney(l.declaredAmount))
                    : '—',
                style: figure,
              ),
              end: true,
            ),
            cell(
              DashStatusPill(
                label: t.exists('tills.reconciliation.${l.status}')
                    ? t('tills.reconciliation.${l.status}')
                    : l.status,
                tone: _tone(l.status),
                small: true,
              ),
              end: true,
            ),
          ],
        ),
    ];
    return _ReportCard(
      key: const ValueKey('reconciliation-table'),
      title: t('tills.reconciliation.title'),
      children: [
        LayoutBuilder(
          builder: (context, box) {
            const minWidth = 380.0;
            final w = box.maxWidth < minWidth ? minWidth : box.maxWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: w,
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(),
                    1: IntrinsicColumnWidth(),
                    2: IntrinsicColumnWidth(),
                    3: IntrinsicColumnWidth(),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.top,
                  children: rows,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CashCard extends ConsumerWidget {
  const _CashCard({required this.report});

  final TillReportResponse report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final till = report.till;
    final original = till.openingCashOriginal;
    final warn = DashTone.warning.foreground(c);
    final discrepancy = till.cashDiscrepancy;
    return _ReportCard(
      key: const ValueKey('till-cash'),
      title: t('tills.cashReconciliation'),
      children: [
        ReportLine(
          label: t('tills.openingCash'),
          value: fmt.fmtMoney(till.openingCash),
        ),
        if (till.openingCashWasEdited) ...[
          if (original != null)
            ReportLine(
              label: t('tills.expectedOpening'),
              value: fmt.fmtMoney(original),
              color: c.textSecondary,
            ),
          Container(
            key: const ValueKey('opening-edited'),
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              color: DashTone.warning.wash(c),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: warn.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                Row(
                  spacing: Space.xs + 2,
                  children: [
                    DashIcon('alert-triangle', size: IconSize.xs, color: warn),
                    Expanded(
                      child: Text(
                        t('tills.openingEdited'),
                        style: DashType.bodyStrong.copyWith(color: warn),
                      ),
                    ),
                    if (original != null)
                      Text(
                        dashFigure(
                          '${till.openingCash - original > 0 ? '+' : ''}'
                          '${fmt.fmtMoney(till.openingCash - original)}',
                        ),
                        style: DashType.monoStrong.copyWith(
                          fontSize: 14,
                          color: warn,
                        ),
                      ),
                  ],
                ),
                if (till.openingCashEditReason case final reason?
                    when reason.isNotEmpty)
                  Text(
                    reason,
                    style: DashType.small.copyWith(color: c.textPrimary),
                  ),
              ],
            ),
          ),
        ],
        ReportLine(
          label: t('tills.cashIn'),
          value: fmt.fmtMoney(report.cashMovementsIn),
        ),
        ReportLine(
          label: t('tills.cashOut'),
          value: fmt.fmtMoney(report.cashMovementsOut),
        ),
        if (till.closingCashSystem != null)
          ReportLine(
            label: t('tills.expectedCash'),
            value: fmt.fmtMoney(till.closingCashSystem),
          ),
        if (till.closingCashDeclared != null)
          ReportLine(
            label: t('tills.closingCash'),
            value: fmt.fmtMoney(till.closingCashDeclared),
          ),
        if (discrepancy != null) ...[
          const _Rule(),
          Builder(
            builder: (context) {
              final tone = discrepancy == 0
                  ? DashTone.success.foreground(c)
                  : DashTone.danger.foreground(c);
              return Row(
                key: const ValueKey('report-discrepancy'),
                spacing: Space.sm,
                children: [
                  Expanded(
                    child: Text(
                      t('tills.discrepancy'),
                      style: DashType.bodyStrong.copyWith(color: tone),
                    ),
                  ),
                  Text(
                    dashFigure(fmt.fmtMoney(discrepancy)),
                    style: DashType.monoStrong.copyWith(
                      fontSize: 14,
                      color: tone,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

/// Who looked at the till's spot report (SELL-TIL-052); shown only to
/// whoever holds `till.read`.
class TillSpotViews extends ConsumerWidget {
  const TillSpotViews({required this.tillId, super.key});

  final String tillId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(authzStateProvider).can(Cap.tillRead)) {
      return const SizedBox.shrink();
    }
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final q = ref.watch(tillSpotViewsProvider(tillId));
    final views = q.value;
    if (views == null && q.hasError) {
      return Semantics(
        liveRegion: true,
        child: Text(
          tillsErrorMessage(q.error, t),
          key: const ValueKey('spot-views-error'),
          style: DashType.body.copyWith(color: c.textSecondary),
        ),
      );
    }
    if (views == null) {
      return const DashSkeleton(height: Space.xxl * 3, radius: Radii.card);
    }
    return Column(
      key: const ValueKey('till-spot-views'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashSectionHeader(
          title: t('tills.spotViews.title'),
          icon: 'eye',
          count: views.length,
        ),
        if (views.isEmpty)
          Text(
            t('tills.spotViews.empty'),
            key: const ValueKey('spot-views-empty'),
            style: DashType.body.copyWith(color: c.textSecondary),
          )
        else
          DashListCard(
            children: [for (final v in views) _SpotViewRow(view: v)],
          ),
      ],
    );
  }
}

class _SpotViewRow extends ConsumerWidget {
  const _SpotViewRow({required this.view});

  final TillSpotView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final meta = StringBuffer(dashFigure(fmt.fmtDateTime(view.viewedAt)));
    if (view.approvedBy != null) {
      meta
        ..write(' · ')
        ..write(
          t(
            'tills.spotViews.unlockedBy',
            args: {'name': view.approvedByName ?? ''},
          ),
        );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.sm,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  view.viewedByName,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                Text(
                  meta.toString(),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          if (view.printed)
            DashBadge(
              t('tills.spotViews.printed'),
              key: const ValueKey('spot-view-printed'),
            ),
        ],
      ),
    );
  }
}

/// One line of "Stock used" (`DeductionTotal`).
class DeductionTotal {
  DeductionTotal(this.key, this.name, this.unit);

  final String key;
  final String name;
  final String unit;

  /// Net stock used: sales minus what voids/refunds put back.
  double used = 0;

  /// Put back by voids/refunds (positive).
  double returned = 0;
}

/// `summarizeDeductions`: one line per stock item and unit, most used first.
List<DeductionTotal> summarizeDeductions(List<DeductionLogRow> rows) {
  final byItem = <String, DeductionTotal>{};
  for (final r in rows) {
    final key = '${r.inventoryItemId}:${r.unit}';
    final cur = byItem[key] ??= DeductionTotal(key, r.itemName, r.unit);
    cur.used += r.quantityDeducted;
    if (r.quantityDeducted < 0) cur.returned -= r.quantityDeducted;
  }
  final out = byItem.values.toList()
    ..sort((a, b) {
      final d = b.used.compareTo(a.used);
      return d != 0 ? d : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return out;
}

/// `qty`: rounded to 3 decimals with its unit.
String deductionQty(DashFormat fmt, double n, String unit) =>
    '${fmt.fmtNumber((n * 1000).round() / 1000)} ${fmtUnit(unit)}'.trim();

/// The stock the till's orders took (SELL-TIL-053); nothing when none.
class TillDeductions extends ConsumerWidget {
  const TillDeductions({required this.tillId, super.key});

  final String tillId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final q = ref.watch(tillDeductionsProvider(tillId));
    final rows = q.value;
    if (rows == null && q.hasError) {
      return Semantics(
        liveRegion: true,
        child: Text(
          t('tills.deductions.loadError'),
          key: const ValueKey('deductions-error'),
          style: DashType.body.copyWith(color: c.textSecondary),
        ),
      );
    }
    if (rows == null) {
      return const DashSkeleton(height: Space.xxl * 3, radius: Radii.card);
    }
    final totals = summarizeDeductions(rows);
    if (totals.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('till-deductions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashSectionHeader(
          title: t('tills.deductions.title'),
          icon: 'package-minus',
          count: totals.length,
        ),
        DashListCard(
          children: [
            for (final d in totals)
              DashListRow(
                title: d.name,
                meta: d.returned > 0
                    ? t(
                        'tills.deductions.returned',
                        args: {'amount': deductionQty(fmt, d.returned, d.unit)},
                      )
                    : null,
                value: deductionQty(fmt, d.used, d.unit),
                numericValue: true,
              ),
          ],
        ),
      ],
    );
  }
}

class _MovementsSection extends ConsumerWidget {
  const _MovementsSection({required this.report});

  final TillReportResponse report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final moves = report.cashMovements;
    return Column(
      key: const ValueKey('till-movements'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashSectionHeader(title: t('tills.cashMovements'), count: moves.length),
        DashListCard(
          children: [
            for (final m in moves)
              DashListRow(
                variant: DashListRowVariant.ledger,
                signIn: m.amount >= 0,
                title: m.note.isNotEmpty
                    ? m.note
                    : t(m.amount < 0 ? 'tills.cashOut' : 'tills.cashIn'),
                meta: '${m.movedByName} · ${fmt.fmtDateTime(m.createdAt)}',
                value: fmt.fmtMoneySigned(m.amount),
                numericValue: true,
              ),
          ],
        ),
      ],
    );
  }
}
