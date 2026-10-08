/// One audit tab (`features/reports/legal/audit-tab.tsx`, REP-LEG-013…027,
/// 038): every Legal tab but Tax is the same report shape — a total plus a
/// reason and an issuer breakdown — so one widget renders all nine.
///
/// Top to bottom: a small Export menu at the end side, the KPI strip, then
/// the breakdown cards (two a row from 1024 px wide, one below; History and
/// Discounted sales span the row; By kind follows them in order).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show AuditReport, DeductionOverrideEvent;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audit_cards.dart';
import 'legal_export.dart';
import 'legal_providers.dart';
import 'legal_sheets.dart';
import 'legal_words.dart';

/// Whether an audit has nothing to show (no report, or no event and no
/// history, `aud:154,163`).
bool auditIsEmpty(AuditReport? d) =>
    d == null || (d.totalCount == 0 && (d.history ?? const []).isEmpty);

class LegalAuditTab extends ConsumerStatefulWidget {
  const LegalAuditTab({
    required this.tab,
    required this.query,
    required this.enabled,
    super.key,
  });

  final LegalTab tab;

  /// The org and period; null while no org is in scope.
  final LegalQuery? query;

  /// An org is in scope and the person holds `reports.legal`.
  final bool enabled;

  @override
  ConsumerState<LegalAuditTab> createState() => _LegalAuditTabState();
}

class _LegalAuditTabState extends ConsumerState<LegalAuditTab> {
  bool _exporting = false;

  ExcelConfig _config(Translator t, AuditReport d) {
    final title = t(widget.tab.labelKey);
    return ExcelConfig(
      filename: 'Madar-$title',
      logoUrl: legalExportLogo(ref),
      sheets: auditSheets(
        t: t,
        report: d,
        amount: widget.tab.amount,
        reasonLabel: t(widget.tab.reasonLabelKey),
        exportTitle: title,
      ),
    );
  }

  Future<void> _excel(AuditReport d) async {
    setState(() => _exporting = true);
    try {
      await legalExportExcel(context, ref, _config(ref.read(tProvider), d));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _csv(AuditReport d) =>
      legalExportCsv(context, ref, _config(ref.read(tProvider), d));

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final tab = widget.tab;
    final query = widget.query;
    final key = query == null ? null : (tab, query);
    final AsyncValue<AuditReport?> q = widget.enabled && key != null
        ? ref.watch(legalAuditProvider(key))
        : const AsyncData<AuditReport?>(null);
    if (q.hasError) {
      return DashErrorState(
        onRetry: () => ref.invalidate(legalAuditProvider(key!)),
      );
    }
    final d = q.value;
    final loading = q.firstLoad;
    final amount = tab.amount;
    final history = d?.history ?? const <DeductionOverrideEvent>[];
    final empty = auditIsEmpty(d);
    final kpis = [
      DashLedgerItem(
        key: 'count',
        label: t('reports.legal.eventCount'),
        icon: 'list-checks',
        tone: DashTone.accent,
        value: d?.totalCount ?? 0,
        format: DashStatFormat.number,
        loading: loading,
      ),
      if (amount != AuditAmount.none)
        DashLedgerItem(
          key: 'amount',
          label: amount == AuditAmount.points
              ? t('reports.legal.eventPoints')
              : t('reports.legal.eventAmount'),
          icon: 'coins',
          tone: DashTone.warning,
          value: d?.totalAmountMinor ?? 0,
          format: amount == AuditAmount.points
              ? DashStatFormat.number
              : DashStatFormat.money,
          loading: loading,
        ),
    ];
    final Widget content;
    if (loading) {
      content = const _AuditGrid(
        items: [
          (DashSkeleton(height: 224, radius: Radii.card), false),
          (DashSkeleton(height: 224, radius: Radii.card), false),
        ],
      );
    } else if (empty) {
      content = DashEmptyState(title: t('reports.legal.empty'));
    } else {
      final report = d!;
      content = _AuditGrid(
        items: [
          if (report.totalCount > 0) ...[
            (
              BreakdownCard(
                icon: 'list-checks',
                title: t(tab.reasonLabelKey),
                rows: [
                  for (final r in report.byReason)
                    (
                      label: auditReasonText(t, r),
                      count: r.count,
                      amount: r.amountMinor,
                    ),
                ],
                amount: amount,
              ),
              false,
            ),
            (
              BreakdownCard(
                icon: 'user-round',
                title: t('reports.legal.byIssuer'),
                rows: [
                  for (final r in report.byIssuer)
                    (label: r.label, count: r.count, amount: r.amountMinor),
                ],
                amount: amount,
              ),
              false,
            ),
          ],
          if (history.isNotEmpty) (HistoryCard(events: history), true),
          if (report.byKind case final byKind?)
            (
              BreakdownCard(
                icon: 'tag',
                title: t('reports.legal.byKind'),
                rows: [
                  for (final r in byKind)
                    (
                      label: discountKindLabel(t, r.label),
                      count: r.count,
                      amount: r.amountMinor,
                    ),
                ],
                amount: amount,
              ),
              false,
            ),
          if (report.entries case final entries? when entries.isNotEmpty)
            (DiscountEntriesCard(entries: entries), true),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: DashExportButton(
            compact: true,
            loading: _exporting,
            enabled: !empty,
            onExport: () => _excel(d!),
            onExportCsv: () => _csv(d!),
          ),
        ),
        LegalKpiStrip(items: kpis),
        content,
      ],
    );
  }
}

/// The KPI strip. Two or more KPIs are the kit's strip; a single one keeps
/// the web's fallback grid (two columns, four from `lg`), so it takes one
/// slot instead of the whole row (the kit stretches it: kit candidate).
class LegalKpiStrip extends StatelessWidget {
  const LegalKpiStrip({required this.items, super.key});

  final List<DashLedgerItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.length != 1) return DashLedgerStrip(items: items);
    final it = items.single;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final cols = w >= DashBreakpoints.lg - Space.xxl * 4 ? 4 : 2;
        final gap = w >= DashBreakpoints.sm ? Space.lg : Space.md;
        return Row(
          spacing: gap,
          children: [
            Expanded(
              child: DashStatCard(
                key: ValueKey(it.key),
                label: it.label,
                value: it.value,
                format: it.format,
                icon: it.icon,
                tone: it.tone,
                loading: it.loading,
              ),
            ),
            for (var k = 1; k < cols; k++)
              const Expanded(child: SizedBox.shrink()),
          ],
        );
      },
    );
  }
}

/// The cards' grid: in order, two to a row from 1024 px wide (cards in a
/// row share a height), one to a row below; a full-width item ends the row
/// it would share and takes one of its own (CSS grid's flow, `aud:166`).
class _AuditGrid extends StatelessWidget {
  const _AuditGrid({required this.items});

  /// Each card and whether it spans the row.
  final List<(Widget, bool)> items;

  @override
  Widget build(BuildContext context) {
    final two = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;
    if (!two) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [for (final (w, _) in items) w],
      );
    }
    final rows = <Widget>[];
    var pending = <Widget>[];
    void flush() {
      if (pending.isEmpty) return;
      final pair = pending;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.lg,
            children: [
              for (final w in pair) Expanded(child: w),
              for (var k = pair.length; k < 2; k++)
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      );
      pending = [];
    }

    for (final (w, full) in items) {
      if (full) {
        flush();
        rows.add(w);
      } else {
        pending.add(w);
        if (pending.length == 2) flush();
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: rows,
    );
  }
}
