/// Margin watch (`features/insights/margin-watch-card.tsx`): the period's
/// gross margin and its change, the open-signal and cost-unknown tallies,
/// the three best and three worst margins with each one's first signal in
/// plain words (`features/insights/signals.ts`), and a link to the full
/// ledger.
library;

import 'package:dashboard_api/dashboard_api.dart' show MarginLedgerRow, Signal;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'home_parts.dart';
import 'home_providers.dart';

/// `signalReason`: a signal's plain-language reason from its kind and its
/// evidence (money in piastres, percents 0–100).
String signalReason(Translator t, DashFormat fmt, Signal signal) {
  final p = signal.params;
  num num_(String k) {
    final v = p[k];
    if (v is num) return v;
    return num.tryParse('${v ?? 0}') ?? 0;
  }

  String pct1(num v) =>
      fmt.fmtNumber(v, const NumberOptions(maximumFractionDigits: 1));
  switch (signal.kind) {
    case 'below_cost':
      return t(
        'insights.signals.reason.below_cost',
        args: {'margin': fmt.fmtMoney(num_('margin'))},
      );
    case 'below_target':
      final base = t(
        'insights.signals.reason.below_target',
        args: {
          'marginPct': pct1(num_('margin_pct')),
          'targetPct': pct1(num_('target_pct')),
        },
      );
      if (num_('adaptive_bar') > 0) {
        return '$base ${t('insights.signals.reason.adaptive_note', args: {'pts': pct1(num_('adaptive_bar'))})}';
      }
      return base;
    case 'cost_spike':
      return t(
        'insights.signals.reason.cost_spike',
        args: {
          'ingredient': '${p['ingredient'] ?? ''}',
          'pct': pct1(num_('pct')),
        },
      );
    case 'price_candidate':
      if (p['caution'] == true) {
        return t(
          'insights.signals.reason.price_candidate_caution',
          args: {
            'delta': fmt.fmtMoney(num_('last_margin_per_day_delta').abs()),
          },
        );
      }
      if (p['elasticity'] is num) {
        final forecast = num_('expected_margin_per_day_delta');
        return t(
          'insights.signals.reason.price_candidate_learned',
          args: {
            'price': fmt.fmtMoney(num_('suggested_price')),
            'forecast': fmt.fmtMoney(forecast < 0 ? 0 : forecast),
          },
        );
      }
      return t(
        'insights.signals.reason.price_candidate',
        args: {'price': fmt.fmtMoney(num_('suggested_price'))},
      );
    case 'removal_candidate':
      return t('insights.signals.reason.removal_candidate');
    case 'recipe_incomplete':
      return t('insights.signals.reason.recipe_incomplete');
    default:
      return signal.kind;
  }
}

/// The readable tints for figures (`TINT`): the state colour mixed toward
/// the text colour.
Color _tint(MadarColors c, DashTone tone) => tone.foreground(c);

class HomeMarginWatchCard extends ConsumerWidget {
  const HomeMarginWatchCard({required this.scope, super.key});

  final Scope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final q = watchIf(ref, scope.orgId != null, homeMarginWatchProvider(scope));
    final data = q.value;
    final totals = data?.totals;
    final empty =
        data == null ||
        (data.top.isEmpty && data.bottom.isEmpty && totals?.revenue == 0);
    final Widget body;
    if (q.firstLoad) {
      body = const HomeSkeleton(height: HomeMetrics.block);
    } else if (q.hasError) {
      body = DashErrorState(
        framed: false,
        title: t('insights.watch.loadFailed'),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(homeMarginWatchProvider(scope)),
      );
    } else if (empty) {
      body = DashEmptyState(framed: false, title: t('insights.watch.empty'));
    } else {
      final tl = totals!;
      final delta = tl.prevMarginKnown > 0
          ? (tl.marginKnown - tl.prevMarginKnown) / tl.prevMarginKnown
          : null;
      final up = (delta ?? 0) >= 0;
      final deltaTone = up ? DashTone.success : DashTone.danger;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Wrap(
            spacing: Space.sm + DashMetrics.hair,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                fmt.fmtMoney(tl.marginKnown),
                style: DashType.statFigure(24).copyWith(color: c.textPrimary),
              ),
              if (tl.marginPct != null)
                Text(
                  fmt.fmtPercent(tl.marginPct! / 100),
                  style: DashType.body.copyWith(
                    color: c.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              if (delta != null)
                Semantics(
                  label:
                      '${fmt.fmtPercent(delta.abs())} ${t('insights.watch.vsPrev')}',
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: DashMetrics.hair,
                    children: [
                      DashIcon(
                        up ? 'arrow-up-right' : 'arrow-down-right',
                        size: IconSize.xs - 2,
                        color: _tint(c, deltaTone),
                      ),
                      Text(
                        fmt.fmtPercent(delta.abs()),
                        style: DashType.smallMedium.copyWith(
                          color: _tint(c, deltaTone),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (data.openSignals > 0 || data.rowsCostUnknown > 0)
            Wrap(
              spacing: Space.md,
              runSpacing: Space.xs,
              children: [
                if (data.openSignals > 0)
                  Text(
                    t('insights.watch.openSignals', count: data.openSignals),
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                if (data.rowsCostUnknown > 0)
                  Text(
                    t(
                      'insights.watch.costUnknown',
                      count: data.rowsCostUnknown,
                    ),
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
              ],
            ),
          LayoutBuilder(
            builder: (context, box) {
              final top = _WatchList(
                title: t('insights.watch.top'),
                rows: data.top,
                tone: DashTone.success,
              );
              final bottom = _WatchList(
                title: t('insights.watch.bottom'),
                rows: data.bottom,
                tone: DashTone.warning,
              );
              if (MediaQuery.sizeOf(context).width < DashBreakpoints.sm) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.lg,
                  children: [top, bottom],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.lg,
                children: [
                  Expanded(child: top),
                  Expanded(child: bottom),
                ],
              );
            },
          ),
          Container(
            padding: const EdgeInsets.only(top: Space.xs),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.hairline)),
            ),
            alignment: AlignmentDirectional.centerStart,
            child: HomeLink(
              label: t('insights.watch.viewAll'),
              arrow: true,
              onTap: () => context.go('/reports/operations/profitability'),
            ),
          ),
        ],
      );
    }
    return DashChartCard(title: t('insights.watch.title'), child: body);
  }
}

class _WatchList extends ConsumerWidget {
  const _WatchList({
    required this.title,
    required this.rows,
    required this.tone,
  });

  final String title;
  final List<MarginLedgerRow> rows;
  final DashTone tone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: DashType.meta.copyWith(
              color: c.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (rows.isEmpty)
          Text(
            t('common.noResults'),
            style: DashType.body.copyWith(color: c.textSecondary),
          )
        else
          for (final r in rows)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.sm,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm - 2),
                  child: Container(
                    width: Space.xs + 2,
                    height: Space.xs + 2,
                    decoration: BoxDecoration(
                      color: tone.solid(c),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: _WatchRow(row: r, t: t, fmt: fmt),
                ),
              ],
            ),
      ],
    );
  }
}

class _WatchRow extends StatelessWidget {
  const _WatchRow({required this.row, required this.t, required this.fmt});

  final MarginLedgerRow row;
  final Translator t;
  final DashFormat fmt;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final r = row;
    String? second;
    if (r.flags.isNotEmpty) {
      second = signalReason(t, fmt, r.flags.first);
    } else if (r.quantitySold > 0) {
      second = t('insights.watch.sold', count: r.quantitySold);
      if (r.marginPct != null) {
        second = '$second · ${fmt.fmtPercent(r.marginPct! / 100)}';
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          spacing: Space.sm,
          children: [
            Expanded(
              child: MadarClippedText.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: r.itemName,
                      style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                    ),
                    if (r.sizeLabel != 'one_size')
                      TextSpan(
                        text: ' · ${r.sizeLabel}',
                        style: DashType.body.copyWith(color: c.textSecondary),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              fmt.fmtMoney(r.margin),
              style: DashType.mono.copyWith(
                fontSize: DashType.body.fontSize,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
        if (second != null)
          MadarClippedText(
            second,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }
}
