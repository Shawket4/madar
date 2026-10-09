/// Menu profitability, the Financial page's first tab: a whole page nested
/// in it (`features/insights/profitability-page.tsx`, REP-FIN-006…045,
/// 071, 072): the margin ledger with its KPIs, the margin-target editor,
/// the cost basis, the Ledger / Repricing / Decisions tabs, the class and
/// flag filters, the flag actions and the ledger export.
///
/// Basis, view, filters and the inner tab are this widget's state, so
/// leaving the tab and coming back resets them (REP-FIN-071).
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashRoutePrefetch;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart' show ReportAsync;
import 'fin_data.dart';
import 'fin_export.dart';
import 'fin_insights_tabs.dart';
import 'fin_quadrant.dart';

/// The page's own 288 px popovers (`w-72`).
const double finPopoverWidth = 288;

class FinProfitabilityView extends ConsumerStatefulWidget {
  const FinProfitabilityView({super.key});

  @override
  ConsumerState<FinProfitabilityView> createState() =>
      _FinProfitabilityViewState();
}

class _FinProfitabilityViewState extends ConsumerState<FinProfitabilityView> {
  bool _current = false;
  String _tab = 'ledger';
  bool _quadrant = false;
  String? _class;
  bool _flagged = false;
  bool _exporting = false;

  /// Decisions in flight (`createDecision.isPending`): every flag's
  /// buttons wait.
  int _pending = 0;

  CreateDecisionRequest _decision(
    MarginLedgerRow r,
    Signal s,
    String action,
    String? branchId,
  ) => CreateDecisionRequest(
    branchId: branchId,
    menuItemId: r.menuItemId,
    sizeLabel: r.sizeLabel,
    signalKind: s.kind,
    action: action,
    detail: s.params,
    explicitNulls: const {'branch_id'},
  );

  Future<void> _post(CreateDecisionRequest body, String orgId) async {
    setState(() => _pending++);
    try {
      await ref
          .read(apiProvider)
          .insights
          .createDecision(orgId: orgId, body: body);
    } finally {
      if (mounted) setState(() => _pending--);
    }
  }

  /// Where a flag's Fix goes.
  static String _fixPath(MarginLedgerRow r, Signal s) => s.link == 'pricing'
      ? '/menu/pricing'
      : '/menu/items/${r.menuItemId}${s.link == 'studio_recipe' ? '?tab=recipe' : ''}';

  /// REP-FIN-030 Fix: record `acted` without waiting, then go fix it.
  void _fix(MarginLedgerRow r, Signal s, Scope scope) {
    final bus = ref.read(realtimeBusProvider);
    _post(
      _decision(r, s, 'acted', scope.branchId),
      scope.orgId!,
    ).then((_) => invalidateInsights(bus), onError: (Object _) {});
    context.go(_fixPath(r, s));
  }

  /// REP-FIN-031…033 Dismiss / Snooze: the server suppresses the flag.
  Future<void> _decide(
    MarginLedgerRow r,
    Signal s,
    String action,
    Scope scope,
  ) async {
    final bus = ref.read(realtimeBusProvider);
    final t = ref.read(tProvider);
    try {
      await _post(_decision(r, s, action, scope.branchId), scope.orgId!);
      invalidateInsights(bus);
    } on Object {
      if (mounted) DashToast.error(context, t('common.somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final scope = ref.watch(currentScopeProvider);
    final title = t('insights.profitability.title');
    if (scope.orgId == null) {
      // REP-FIN-006.
      return DashPageScaffold(
        title: title,
        body: DashEmptyState(icon: 'building-2', title: t('insights.pickOrg')),
      );
    }
    final key = scope.finLedger(current: _current);
    final q = ref.watch(finLedgerProvider(key));
    final report = q.value;
    final totals = report?.totals;
    final loading = q.awaitingFirst;
    final gap = totals?.belowTargetGap ?? 0;
    final f = ref.watch(formatProvider);

    final strip = DashLedgerStrip(
      items: [
        DashLedgerItem(
          key: 'revenue',
          label: t('insights.profitability.revenue'),
          value: totals?.revenue ?? 0,
          format: DashStatFormat.money,
          trend: finTrend(totals?.revenue, totals?.prevRevenue),
          loading: loading,
        ),
        DashLedgerItem(
          key: 'margin',
          label: t('insights.profitability.grossMargin'),
          value: totals?.marginKnown ?? 0,
          format: DashStatFormat.money,
          tone: DashTone.success,
          trend: finTrend(totals?.marginKnown, totals?.prevMarginKnown),
          hint: totals?.marginPct == null
              ? null
              : t(
                  'insights.profitability.shareOfRevenue',
                  args: {'pct': f.fmtPercent(totals!.marginPct! / 100)},
                ),
          loading: loading,
        ),
        DashLedgerItem(
          key: 'gap',
          label: t('insights.profitability.belowTargetGap'),
          value: gap,
          format: DashStatFormat.money,
          tone: gap > 0 ? DashTone.warning : DashTone.neutral,
          loading: loading,
        ),
      ],
    );
    final c = context.madarColors;
    final unknown = report?.rowsCostUnknown ?? 0;

    final Widget content = switch (_tab) {
      'repricing' => FinRepricingTab(branchId: scope.scopeBranchId),
      'decisions' => FinDecisionsTab(
        orgId: scope.orgId!,
        branchId: scope.branchId,
      ),
      _ => _ledger(context, q, key, scope),
    };

    return DashPageScaffold(
      title: title,
      subtitleWidget: loading
          ? const DashSkeleton(width: 176, height: Space.xl - Space.xs)
          : report == null
          ? null
          : FinTargetEditor(
              orgId: scope.orgId!,
              branchId: scope.branchId,
              targetPct: report.targetPct,
              targetSource: report.targetSource,
            ),
      actions: [
        DashSegmentedControl<bool>(
          key: const ValueKey('fin-basis'),
          value: _current,
          onChanged: (v) => setState(() => _current = v),
          onIntent: (v) =>
              ref.warm(finLedgerProvider(scope.finLedger(current: v))),
          options: [
            DashOption(
              value: false,
              label: t('insights.profitability.basisSnapshot'),
            ),
            DashOption(
              value: true,
              label: t('insights.profitability.basisCurrent'),
            ),
          ],
        ),
      ],
      tabs: DashPageTabs<String>(
        key: const ValueKey('fin-inner-tabs'),
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        onIntent: (v) {
          if (v == 'repricing') {
            ref.warm(finRepricingProvider(scope.scopeBranchId));
          } else if (v == 'decisions') {
            ref.warm(
              finDecisionsProvider((
                orgId: scope.orgId!,
                branchId: scope.branchId,
              )),
            );
            ref.warm(finUsersProvider(scope.orgId!));
          }
        },
        tabs: [
          DashTab(
            value: 'ledger',
            label: t('insights.profitability.ledgerTab'),
          ),
          DashTab(
            value: 'repricing',
            label: t('insights.profitability.repricingTab'),
          ),
          DashTab(
            value: 'decisions',
            label: t('insights.profitability.decisionsTab'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              strip,
              if (unknown > 0)
                Row(
                  key: const ValueKey('fin-cost-unknown'),
                  spacing: Space.xs + DashMetrics.hair,
                  children: [
                    DashIcon('info', size: IconSize.sm, color: c.textSecondary),
                    Flexible(
                      child: Text(
                        t(
                          'insights.profitability.costUnknownNote',
                          count: unknown,
                        ),
                        style: DashType.body.copyWith(color: c.textSecondary),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          KeyedSubtree(key: ValueKey('fin-inner-$_tab'), child: content),
        ],
      ),
    );
  }

  Widget _ledger(
    BuildContext context,
    AsyncValue<MarginLedgerReport> q,
    FinLedgerKey key,
    Scope scope,
  ) {
    final t = ref.watch(tProvider);
    final all = q.value?.rows ?? const <MarginLedgerRow>[];
    void retry() => ref.invalidate(finLedgerProvider(key));
    final view = DashSegmentedControl<bool>(
      key: const ValueKey('fin-view'),
      value: _quadrant,
      onChanged: (v) => setState(() => _quadrant = v),
      options: [
        DashOption(value: false, label: t('insights.profitability.viewTable')),
        DashOption(
          value: true,
          label: t('insights.profitability.viewQuadrant'),
        ),
      ],
    );
    final Widget body;
    if (_quadrant) {
      // REP-FIN-042: the WHOLE ledger, never the filtered rows.
      if (q.awaitingFirst) {
        body = const DashSkeleton(height: finQuadrantHeight);
      } else if (q.failed) {
        body = DashErrorState(
          message: errorMessage(q.error, t),
          retrying: q.isLoading,
          retryLabel: t('common.retry'),
          onRetry: retry,
        );
      } else if (all.any((r) => r.class_ != null)) {
        body = FinQuadrantView(rows: all);
      } else {
        body = DashEmptyState(
          title: all.any((r) => r.quantitySold > 0)
              ? t('insights.quadrant.noCosts')
              : t('insights.profitability.noRows'),
        );
      }
    } else {
      final rows = finFilterRows(all, klass: _class, flaggedOnly: _flagged);
      body = DashDataTable<MarginLedgerRow>(
        key: const ValueKey('fin-ledger'),
        rows: rows,
        rowKey: (r) => '${r.menuItemId}-${r.sizeLabel}',
        loading: q.awaitingFirst,
        retrying: q.isLoading,
        errorMessage: q.failed ? errorMessage(q.error, t) : null,
        onRetry: retry,
        hideViewOptions: true,
        pageSize: 50,
        toolbar: _toolbar(context, rows),
        empty: DashEmptyState(
          title: _flagged
              ? t('insights.profitability.noFlags')
              : t('insights.profitability.noRows'),
        ),
        columns: _columns(context, q.value, scope),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        Align(alignment: AlignmentDirectional.centerStart, child: view),
        body,
      ],
    );
  }

  Widget _toolbar(BuildContext context, List<MarginLedgerRow> rows) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final flaggedLabel = t('insights.profitability.flaggedOnly');
    return Wrap(
      spacing: Space.md,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DashSelect<String>(
          key: const ValueKey('fin-class-filter'),
          expand: false,
          minWidth: 144,
          semanticLabel: t('insights.class.all'),
          value: _class ?? '',
          active: _class != null,
          onChanged: (v) => setState(() => _class = v.isEmpty ? null : v),
          options: [
            DashOption(value: '', label: t('insights.class.all')),
            for (final k in finClasses)
              DashOption(value: k, label: t('insights.class.$k')),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DashSwitch(
              key: const ValueKey('fin-flagged-only'),
              value: _flagged,
              semanticLabel: flaggedLabel,
              onChanged: (v) => setState(() => _flagged = v),
            ),
            Text(
              flaggedLabel,
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
          ],
        ),
        DashExportButton(
          key: const ValueKey('fin-ledger-export'),
          compact: true,
          loading: _exporting,
          enabled: rows.isNotEmpty,
          onExport: () => _exportExcel(rows),
          onExportCsv: () => finCsv(
            context,
            ref,
            filename: 'Madar-${t('insights.profitability.title')}',
            sheets: () async => [finLedgerSheet(t, rows)],
          ),
        ),
      ],
    );
  }

  Future<void> _exportExcel(List<MarginLedgerRow> rows) async {
    final t = ref.read(tProvider);
    setState(() => _exporting = true);
    await finExcel(
      context,
      ref,
      filename: 'Madar-${t('insights.profitability.title')}',
      sheets: () async => [finLedgerSheet(t, rows)],
    );
    if (mounted) setState(() => _exporting = false);
  }

  List<DashColumn<MarginLedgerRow>> _columns(
    BuildContext context,
    MarginLedgerReport? report,
    Scope scope,
  ) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final danger = DashTone.danger.foreground(c);
    final warning = DashTone.warning.foreground(c);
    String pct(double? v) => v == null ? '—' : f.fmtPercent(v / 100);
    Widget fig(String s, {Color? color}) => Text(
      dashFigure(s),
      maxLines: 1,
      softWrap: false,
      style: DashType.mono.copyWith(color: color ?? c.textPrimary),
    );
    return [
      DashColumn(
        id: 'item',
        label: t('insights.columns.item'),
        phone: DashPhoneRole.title,
        flex: 4,
        minWidth: 220,
        text: (r) => r.itemName,
        cell: (context, r) => FinItemCell(row: r),
      ),
      DashColumn(
        id: 'sold',
        label: t('insights.columns.sold'),
        numeric: true,
        flex: 2,
        minWidth: 96,
        text: (r) => f.fmtNumber(r.quantitySold),
        cell: (context, r) => FinSoldCell(row: r),
      ),
      DashColumn(
        id: 'revenue',
        label: t('insights.columns.revenue'),
        numeric: true,
        flex: 3,
        minWidth: 150,
        text: (r) => f.fmtMoney(r.revenue),
      ),
      DashColumn(
        id: 'cost',
        label: t('insights.columns.cost'),
        numeric: true,
        flex: 3,
        minWidth: 150,
        text: (r) => f.fmtMoney(r.cost),
      ),
      DashColumn(
        id: 'margin',
        label: t('insights.columns.margin'),
        numeric: true,
        flex: 3,
        minWidth: 150,
        text: (r) => f.fmtMoney(r.margin),
        cell: (context, r) => fig(
          f.fmtMoney(r.margin),
          color: r.margin != null && r.margin! < 0 ? danger : null,
        ),
      ),
      DashColumn(
        id: 'marginPct',
        label: t('insights.columns.marginPct'),
        numeric: true,
        flex: 2,
        minWidth: 90,
        text: (r) => pct(r.marginPct),
        cell: (context, r) => fig(
          pct(r.marginPct),
          color:
              r.marginPct != null &&
                  report != null &&
                  r.marginPct! < report.targetPct
              ? warning
              : null,
        ),
      ),
      DashColumn(
        id: 'share',
        label: t('insights.columns.share'),
        numeric: true,
        flex: 2,
        minWidth: 80,
        text: (r) => pct(r.marginSharePct),
        cell: (context, r) =>
            fig(pct(r.marginSharePct), color: c.textSecondary),
      ),
      DashColumn(
        id: 'flags',
        label: t('insights.columns.flags'),
        flex: 4,
        minWidth: 160,
        text: (r) => r.flags.map((s) => finSignalLabel(t, s.kind)).join(', '),
        cell: (context, r) => r.flags.isEmpty
            ? const SizedBox.shrink()
            : Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final s in r.flags)
                    FinFlagChip(
                      key: ValueKey(
                        'flag-${r.menuItemId}-${r.sizeLabel}-${s.kind}',
                      ),
                      signal: s,
                      busy: _pending > 0,
                      onFix: () => _fix(r, s, scope),
                      onFixIntent: () => ref.prefetchRoute(_fixPath(r, s)),
                      onDecide: (action) => _decide(r, s, action, scope),
                    ),
                ],
              ),
      ),
    ];
  }
}

/// REP-FIN-017 the item: name (cut at 224), size badge unless `one_size`
/// (the stored label as is), class chip, "Off menu".
class FinItemCell extends ConsumerWidget {
  const FinItemCell({required this.row, super.key});

  final MarginLedgerRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 224),
          child: MadarClippedText(
            row.itemName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
        ),
        if (row.sizeLabel != 'one_size') DashBadge(row.sizeLabel, outline: true),
        if (row.class_ != null && finClasses.contains(row.class_))
          DashPressable(
            key: ValueKey('class-${row.menuItemId}-${row.sizeLabel}'),
            isButton: false,
            pressScale: false,
            tooltip: t(
              'insights.class.tooltip',
              args: {'popularity': _jsNum(row.popularityPct ?? 0)},
            ),
            // Quiet chip; only Dog's words are muted (web CLASS_META).
            builder: (context, s) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm,
                vertical: DashMetrics.hair,
              ),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                t('insights.class.${row.class_}'),
                style: DashType.smallMedium.copyWith(
                  color: row.class_ == 'dog' ? c.textSecondary : c.textPrimary,
                ),
              ),
            ),
          ),
        if (!row.onMenu) DashBadge(t('insights.profitability.offMenu')),
      ],
    );
  }
}

String _jsNum(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

/// REP-FIN-019 sold + the change vs the previous period.
class FinSoldCell extends ConsumerWidget {
  const FinSoldCell({required this.row, super.key});

  final MarginLedgerRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final delta = row.quantitySold - row.prevQuantity;
    final tone = (delta > 0 ? DashTone.success : DashTone.danger).foreground(c);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      textDirection: TextDirection.ltr,
      children: [
        Text(
          dashFigure(f.fmtNumber(row.quantitySold)),
          style: DashType.mono.copyWith(color: c.textPrimary),
        ),
        if (delta != 0)
          Tooltip(
            message: t('insights.profitability.vsPrev'),
            child: Row(
              key: ValueKey('sold-delta-${row.menuItemId}-${row.sizeLabel}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                DashIcon(
                  delta > 0 ? 'arrow-up-right' : 'arrow-down-right',
                  size: 12,
                  color: tone,
                ),
                Text(
                  dashFigure(f.fmtNumber(delta.abs())),
                  style: DashType.mono.copyWith(fontSize: 12, color: tone),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// REP-FIN-029 a flag: its pill opens the reason and Fix / Dismiss /
/// Snooze, all disabled while any decision is in flight.
class FinFlagChip extends ConsumerWidget {
  const FinFlagChip({
    required this.signal,
    required this.busy,
    required this.onFix,
    required this.onDecide,
    this.onFixIntent,
    super.key,
  });

  final Signal signal;
  final bool busy;
  final VoidCallback onFix;
  final Future<void> Function(String action) onDecide;

  /// About to press Fix: warm the page it opens.
  final VoidCallback? onFixIntent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final label = finSignalLabel(t, signal.kind);
    return DashPopover(
      width: finPopoverWidth,
      anchor: (context, pc) => DashPressable(
        onTap: pc.toggle,
        semanticLabel: label,
        excludeChildSemantics: true,
        pressScale: false,
        builder: (context, s) => DashStatusPill(
          label: label,
          tone: finSignalTone(signal.kind),
          small: true,
        ),
      ),
      content: (context, pc) => _FlagCard(
        signal: signal,
        busy: busy,
        onFix: onFix,
        onFixIntent: onFixIntent,
        onDecide: (a) async {
          await onDecide(a);
          pc.close();
        },
      ),
    );
  }
}

class _FlagCard extends ConsumerWidget {
  const _FlagCard({
    required this.signal,
    required this.busy,
    required this.onFix,
    required this.onFixIntent,
    required this.onDecide,
  });

  final Signal signal;
  final bool busy;
  final VoidCallback onFix;
  final VoidCallback? onFixIntent;
  final Future<void> Function(String action) onDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    return Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          Text(
            finSignalReason(t, f, signal),
            style: DashType.body.copyWith(color: c.textPrimary, height: 1.6),
          ),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              DashButton(
                label: t('insights.actions.fix'),
                icon: 'wrench',
                size: DashButtonSize.compact,
                onPressed: busy ? null : onFix,
                onIntent: onFixIntent,
              ),
              DashButton(
                label: t('insights.actions.dismiss'),
                icon: 'x',
                size: DashButtonSize.compact,
                variant: DashButtonVariant.outline,
                onPressed: busy ? null : () => onDecide('dismissed'),
              ),
              DashButton(
                label: t('insights.actions.snooze'),
                icon: 'bell-off',
                size: DashButtonSize.compact,
                variant: DashButtonVariant.outline,
                onPressed: busy ? null : () => onDecide('snoozed'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// REP-FIN-036…041 the target readout and its editor.
class FinTargetEditor extends ConsumerWidget {
  const FinTargetEditor({
    required this.orgId,
    required this.branchId,
    required this.targetPct,
    required this.targetSource,
    super.key,
  });

  final String orgId;

  /// The scoped branch; null = all branches (org default only).
  final String? branchId;
  final double targetPct;
  final String targetSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final text = finTargetText(t, f, targetPct, targetSource);
    return DashPopover(
      width: finPopoverWidth,
      anchor: (context, pc) => DashPressable(
        key: const ValueKey('fin-target-trigger'),
        onTap: pc.toggle,
        onIntent: () => ref.warm(finTargetsProvider(orgId)),
        semanticLabel: text,
        excludeChildSemantics: true,
        pressScale: false,
        builder: (context, s) {
          final c = context.madarColors;
          final color = s.hovered ? c.textPrimary : c.textSecondary;
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: DashMetrics.target),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs + DashMetrics.hair,
              children: [
                DashIcon('target', size: IconSize.xs, color: color),
                Flexible(
                  child: Text(
                    text,
                    style: DashType.body.copyWith(
                      color: color,
                      decoration: TextDecoration.underline,
                      decorationStyle: TextDecorationStyle.dotted,
                      decorationColor: c.textSecondary.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      content: (context, pc) =>
          FinTargetForm(orgId: orgId, branchId: branchId, onSaved: pc.close),
    );
  }
}

/// The editor's card: seeded from the targets each time it opens.
class FinTargetForm extends ConsumerStatefulWidget {
  const FinTargetForm({
    required this.orgId,
    required this.branchId,
    required this.onSaved,
    super.key,
  });

  final String orgId;
  final String? branchId;
  final VoidCallback onSaved;

  @override
  ConsumerState<FinTargetForm> createState() => _FinTargetFormState();
}

class _FinTargetFormState extends ConsumerState<FinTargetForm> {
  String _org = '';
  String _branch = '';

  /// The targets the fields were last seeded from: a refetch re-seeds each
  /// field the person has not typed in (target-editor.tsx:51-56).
  MarginTargets? _seededFrom;
  bool _orgEdited = false;
  bool _branchEdited = false;
  bool _saving = false;

  void _seed(MarginTargets d) {
    _seededFrom = d;
    if (!_orgEdited) _org = _initialOrg(d);
    if (!_branchEdited) _branch = _initialBranch(d);
  }

  String _initialBranch(MarginTargets? d) {
    final id = widget.branchId;
    if (id == null) return '';
    for (final b in d?.branches ?? const <BranchTarget>[]) {
      if (b.branchId == id) return finPctString(b.targetPct);
    }
    return '';
  }

  Future<void> _save(MarginTargets? d) async {
    final t = ref.read(tProvider);
    final bus = ref.read(realtimeBusProvider);
    final api = ref.read(apiProvider).insights;
    final orgDirty = _orgDirty(d);
    final branchDirty = _branchDirty(d);
    setState(() => _saving = true);
    var saved = false;
    try {
      if (orgDirty) {
        await api.putMarginTarget(
          orgId: widget.orgId,
          body: PutTargetRequest(targetPct: double.parse(_org.trim())),
        );
        saved = true;
      }
      if (branchDirty) {
        await api.putMarginTarget(
          orgId: widget.orgId,
          body: PutTargetRequest(
            branchId: widget.branchId,
            targetPct: double.parse(_branch.trim()),
          ),
        );
        saved = true;
      }
      invalidateInsights(bus);
      if (mounted) {
        DashToast.success(context, t('common.savedChanges'));
        widget.onSaved();
      }
    } on Object {
      // A saved org default is shown even when the branch PUT then failed
      // (divergence REP-FIN-040).
      if (saved) invalidateInsights(bus);
      if (mounted) DashToast.error(context, t('common.somethingWrong'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _initialOrg(MarginTargets? d) =>
      d?.orgDefaultPct == null ? '' : finPctString(d!.orgDefaultPct!);

  bool _orgDirty(MarginTargets? d) =>
      _org.trim().isNotEmpty && _org != _initialOrg(d);

  bool _branchDirty(MarginTargets? d) =>
      widget.branchId != null &&
      _branch.trim().isNotEmpty &&
      _branch != _initialBranch(d);

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final q = ref.watch(finTargetsProvider(widget.orgId));
    final d = q.value;
    if (d != null && !identical(d, _seededFrom)) _seed(d);
    final builtin = finPctString(d?.builtinDefaultPct ?? 60);
    final valid = finPctValid(_org) && finPctValid(_branch);
    final canSave = valid && (_orgDirty(d) || _branchDirty(d)) && !_saving;
    Widget field(
      String label,
      String value,
      String placeholder,
      ValueChanged<String> onChanged,
      Key key,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        Text(label, style: DashType.bodyMedium.copyWith(color: c.textPrimary)),
        DashTextInput(
          key: key,
          value: value,
          onChanged: onChanged,
          placeholder: placeholder,
          semanticLabel: label,
          invalid: !finPctValid(value),
          mono: true,
          textDirection: TextDirection.ltr,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-eE+]')),
          ],
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.lg,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              Text(
                t('insights.target.title'),
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              Text(
                t('insights.target.hint'),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ],
          ),
          if (q.awaitingFirst)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.sm,
              children: [
                const DashSkeleton(height: DashMetrics.control),
                if (widget.branchId != null)
                  const DashSkeleton(height: DashMetrics.control),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.md,
              children: [
                field(
                  t('insights.target.orgDefault'),
                  _org,
                  builtin,
                  (v) => setState(() {
                    _org = v;
                    _orgEdited = true;
                  }),
                  const ValueKey('fin-target-org'),
                ),
                if (widget.branchId != null)
                  field(
                    t('insights.target.branchOverride'),
                    _branch,
                    _org.isNotEmpty ? _org : builtin,
                    (v) => setState(() {
                      _branch = v;
                      _branchEdited = true;
                    }),
                    const ValueKey('fin-target-branch'),
                  ),
              ],
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: DashButton(
              key: const ValueKey('fin-target-save'),
              label: t('common.save'),
              size: DashButtonSize.compact,
              loading: _saving,
              onPressed: canSave ? () => _save(d) : null,
            ),
          ),
        ],
      ),
    );
  }
}
