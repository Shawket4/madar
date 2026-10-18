/// Menu profitability's Repricing and Decisions tabs
/// (`features/insights/repricing-tab.tsx`, `decisions-tab.tsx`,
/// REP-FIN-046…053).
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart' show ReportAsync;
import 'fin_data.dart';

/// REP-FIN-046…049 underpriced items with a target-restoring price.
class FinRepricingTab extends ConsumerWidget {
  const FinRepricingTab({required this.branchId, super.key});

  /// The scope branch, or the all-branches sentinel.
  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final q = ref.watch(finRepricingProvider(branchId));
    final danger = DashTone.danger.foreground(c);
    final success = DashTone.success.foreground(c);
    Widget fig(String s, {Color? color, bool strong = false}) => Text(
      dashFigure(s),
      maxLines: 1,
      softWrap: false,
      style: (strong ? DashType.monoStrong : DashType.mono).copyWith(
        color: color ?? c.textPrimary,
      ),
    );
    final columns = <DashColumn<RepricingSuggestion>>[
      DashColumn(
        id: 'item',
        label: t('insights.repricing.item'),
        phone: DashPhoneRole.title,
        flex: 3,
        minWidth: 220,
        text: (s) => s.itemName,
        cell: (context, s) => Wrap(
          spacing: Space.xs + DashMetrics.hair,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (s.belowCost)
              DashIcon('triangle-alert', size: IconSize.xs, color: danger),
            Text(
              s.itemName,
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
            if (s.sizeLabel != 'one_size')
              Text(
                s.sizeLabel,
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
          ],
        ),
      ),
      DashColumn(
        id: 'current',
        label: t('insights.repricing.current'),
        numeric: true,
        text: (s) => f.fmtMoney(s.currentPrice),
      ),
      DashColumn(
        id: 'cost',
        label: t('insights.repricing.cost'),
        numeric: true,
        text: (s) => f.fmtMoney(s.cost),
      ),
      DashColumn(
        id: 'margin',
        label: t('insights.repricing.marginCol'),
        numeric: true,
        text: (s) => f.fmtPercent(s.marginPct / 100),
        cell: (context, s) => fig(
          f.fmtPercent(s.marginPct / 100),
          color: s.belowCost ? danger : null,
        ),
      ),
      DashColumn(
        id: 'suggested',
        label: t('insights.repricing.suggested'),
        numeric: true,
        text: (s) => f.fmtMoney(s.suggestedPrice),
        cell: (context, s) => fig(f.fmtMoney(s.suggestedPrice), strong: true),
      ),
      DashColumn(
        id: 'uplift',
        label: t('insights.repricing.uplift'),
        numeric: true,
        text: (s) => f.fmtMoney(s.uplift),
        cell: (context, s) => Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.ltr,
          spacing: DashMetrics.hair,
          children: [
            DashIcon('arrow-up-right', size: 12, color: success),
            fig(f.fmtMoney(s.uplift), color: success),
          ],
        ),
      ),
    ];
    if (q.awaitingFirst) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: const DashSkeleton(height: Space.xxl),
            ),
          ),
          DashDataTable<RepricingSuggestion>(
            columns: columns,
            rows: const [],
            rowKey: (s) => s.menuItemId,
            loading: true,
            hideViewOptions: true,
          ),
        ],
      );
    }
    final data = q.value;
    if (q.failed || data == null) {
      return DashErrorState(
        title: t('insights.repricing.error'),
        retrying: q.isLoading,
        retryLabel: t('common.retry'),
        onRetry: () => ref.invalidate(finRepricingProvider(branchId)),
      );
    }
    final costed = data.skusConsidered - data.skusCostUnknown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            Text(
              t(
                'insights.repricing.coverage',
                args: {
                  'target': f.fmtPercent(data.targetPct / 100),
                  'costed': costed,
                  'total': data.skusConsidered,
                },
              ),
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
            DashButton(
              key: const ValueKey('fin-adjust-prices'),
              label: t('insights.repricing.adjust'),
              size: DashButtonSize.compact,
              variant: DashButtonVariant.outline,
              onPressed: () => context.go('/menu/pricing'),
              to: '/menu/pricing',
            ),
          ],
        ),
        DashDataTable<RepricingSuggestion>(
          key: const ValueKey('fin-repricing'),
          columns: columns,
          rows: data.suggestions,
          rowKey: (s) => '${s.menuItemId}-${s.sizeLabel}',
          hideViewOptions: true,
          empty: DashEmptyState(
            title: t('insights.repricing.none'),
            description: data.skusCostUnknown > 0
                ? t('insights.repricing.noneCost')
                : t('insights.repricing.noneOk'),
          ),
        ),
      ],
    );
  }
}

double? _numIn(Map<String, Object?>? o, String key) {
  final v = o?[key];
  return v is num && v.isFinite ? v.toDouble() : null;
}

/// REP-FIN-050…053 the decision log with its measured before → after.
class FinDecisionsTab extends ConsumerWidget {
  const FinDecisionsTab({
    required this.orgId,
    required this.branchId,
    super.key,
  });

  final String orgId;

  /// The selected branch; null = the whole org's log.
  final String? branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final key = (orgId: orgId, branchId: branchId);
    final q = ref.watch(finDecisionsProvider(key));
    final users = ref.watch(finUsersProvider(orgId)).value;
    String? nameOf(String? id) {
      if (id == null) return null;
      for (final u in users ?? const <UserPublic>[]) {
        if (u.id == id) return u.name;
      }
      return null;
    }

    final success = DashTone.success.foreground(c);
    return DashDataTable<DecisionOut>(
      key: const ValueKey('fin-decisions'),
      rows: q.value ?? const [],
      rowKey: (r) => r.id,
      loading: q.awaitingFirst,
      retrying: q.isLoading,
      errorMessage: q.failed ? errorMessage(q.error, t) : null,
      onRetry: () => ref.invalidate(finDecisionsProvider(key)),
      hideViewOptions: true,
      empty: DashEmptyState(
        icon: 'clipboard-list',
        title: t('insights.decisions.empty'),
        description: t('insights.decisions.emptyHint'),
      ),
      columns: [
        DashColumn(
          id: 'item',
          label: t('insights.columns.item'),
          phone: DashPhoneRole.title,
          flex: 2,
          minWidth: 200,
          text: (r) => r.itemName,
          cell: (context, r) => Wrap(
            spacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MadarClippedText(
                r.itemName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              if (r.sizeLabel != 'one_size')
                DashBadge(r.sizeLabel, outline: true),
            ],
          ),
        ),
        DashColumn(
          id: 'signal',
          label: t('insights.columns.signal'),
          minWidth: 130,
          text: (r) => finSignalLabel(t, r.signalKind),
          cell: (context, r) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashStatusPill(
              label: finSignalLabel(t, r.signalKind),
              tone: finSignalTone(r.signalKind),
              small: true,
            ),
          ),
        ),
        DashColumn(
          id: 'action',
          label: t('insights.columns.action'),
          minWidth: 100,
          text: (r) => finActionLabel(t, r.action),
          cell: (context, r) => Text(
            finActionLabel(t, r.action),
            style: DashType.body.copyWith(color: c.textSecondary),
          ),
        ),
        DashColumn(
          id: 'when',
          label: t('insights.columns.when'),
          minWidth: 170,
          text: (r) => f.fmtDateTime(r.createdAt.toIso8601String()),
          cell: (context, r) {
            final who = nameOf(r.createdBy);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DashMetrics.hair,
              children: [
                Text(
                  dashFigure(f.fmtDateTime(r.createdAt.toIso8601String())),
                  style: DashType.mono.copyWith(color: c.textPrimary),
                ),
                if (who != null)
                  MadarClippedText(
                    who,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
              ],
            );
          },
        ),
        DashColumn(
          id: 'qty',
          label: t('insights.decisions.qtyPerDay'),
          numeric: true,
          minWidth: 140,
          cell: (context, r) => r.impact == null
              ? Text(
                  t('insights.decisions.measuring'),
                  style: DashType.body.copyWith(color: c.textSecondary),
                )
              : FinBeforeAfter(
                  before: _numIn(r.baseline, 'qty_per_day'),
                  after: _numIn(r.impact, 'qty_per_day'),
                  format: (v) => f.fmtNumber(
                    v,
                    const NumberOptions(maximumFractionDigits: 2),
                  ),
                ),
        ),
        DashColumn(
          id: 'margin',
          label: t('insights.columns.marginPct'),
          numeric: true,
          minWidth: 140,
          cell: (context, r) => r.impact == null
              ? const SizedBox.shrink()
              : FinBeforeAfter(
                  before: _numIn(r.baseline, 'margin_pct'),
                  after: _numIn(r.impact, 'margin_pct'),
                  format: (v) => f.fmtPercent(v / 100),
                ),
        ),
        DashColumn(
          id: 'status',
          // Visually hidden on the web (`sr-only`).
          label: '',
          width: Space.xxl + Space.lg,
          cell: (context, r) => r.impactComplete
              ? Semantics(
                  label: t('insights.decisions.complete'),
                  excludeSemantics: true,
                  child: DashIcon('check', size: IconSize.xs, color: success),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// REP-FIN-052 `before → after`, the after tinted by the change's direction.
class FinBeforeAfter extends StatelessWidget {
  const FinBeforeAfter({
    required this.before,
    required this.after,
    required this.format,
    super.key,
  });

  final double? before;
  final double? after;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    String show(double? v) => v == null ? '—' : format(v);
    final delta = before != null && after != null ? after! - before! : null;
    final tone = delta == null || delta == 0
        ? c.textSecondary
        : (delta > 0 ? DashTone.success : DashTone.danger).foreground(c);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        Text(
          dashFigure(show(before)),
          style: DashType.mono.copyWith(color: c.textSecondary),
        ),
        DashIcon(
          rtl ? 'arrow-left' : 'arrow-right',
          size: 12,
          color: c.textSecondary,
        ),
        Text(
          dashFigure(show(after)),
          style: DashType.monoMedium.copyWith(color: tone),
        ),
      ],
    );
  }
}
