/// `/reports/staff-pool` Staff drinks (REP-SPL rows): the day's pool, the
/// period's totals and every drink with its note
/// (`features/staff-pool/staff-pool-report-page.tsx`, `staff-drinks-summary.tsx`,
/// `staff-drinks-table.tsx`, `util.ts`).
///
/// The pool belongs to one branch's business day (it resets at the branch's
/// own midnight), so the cards report the LAST day of the scope's period,
/// while the list and its totals cover the whole period. "Over allowance" is
/// the loudest figure when it is not zero: going over is allowed, and being
/// seen afterwards is its only control.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show StaffDrink, StaffDrinksSummary, StaffPoolToday;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart';
import 'staff_drink_order_sheet.dart';
import 'staff_drinks_summary.dart';
import 'staff_drinks_table.dart';
import 'staff_pool_providers.dart';
import 'unit_support.dart';

/// The route's page (`DashRoute.builder`).
Widget staffPoolReportPageBuilder(BuildContext context, GoRouterState state) =>
    const StaffPoolReportPage();

class StaffPoolReportPage extends ConsumerWidget {
  const StaffPoolReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final scope = ref.watch(currentScopeProvider);
    final canSee = ref.watch(
      authzProvider.select((a) => a.can(Cap.ordersStaffDrinkRecord)),
    );
    // A drink rung on a sale links to it — for someone who may read orders.
    final canOpenOrders = ref.watch(
      authzProvider.select((a) => a.can(Cap.ordersRead)),
    );
    final title = t('staffPool.reportTitle');
    final refused = reportRestricted(ref, title: title, canSee: canSee);
    if (refused != null) return refused;

    final fromDate = localDateParam(f, scope.from);
    final businessDate = localDateParam(f, scope.to);
    final oneDay = fromDate == businessDate;
    final branchId = scope.branchId;
    final c = context.madarColors;

    final Widget body;
    if (branchId == null) {
      // The pool is one shop's day: no honest all-branches total.
      body = DashEmptyState(
        icon: 'cup-soda',
        title: t('staffPool.pickBranch'),
        description: t('staffPool.pickBranchBody'),
      );
    } else {
      final drinksQuery = (
        branchId: branchId,
        from: fromDate,
        to: businessDate,
      );
      final todayQuery = (branchId: branchId, businessDate: businessDate);
      // All three are asked at once; the drinks do not wait for the pool.
      final today = watchWhen(ref, canSee, staffPoolTodayProvider(todayQuery));
      final drinks = watchWhen(ref, canSee, staffDrinksProvider(drinksQuery));
      final summary = watchWhen(
        ref,
        canSee,
        staffDrinksSummaryProvider(drinksQuery),
      );
      if (today.firstLoad) {
        body = const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            DashSkeleton(height: _Heights.cards, radius: Radii.card),
            DashSkeleton(height: _Heights.table, radius: Radii.card),
          ],
        );
      } else if (today.hasError) {
        body = DashErrorState(
          retryLabel: t('common.retry'),
          onRetry: () => ref.invalidate(staffPoolTodayProvider(todayQuery)),
        );
      } else if (today.value != null && !today.value!.enabled) {
        body = DashEmptyState(
          icon: 'cup-soda',
          title: t('staffPool.reportOff'),
          description: t('staffPool.reportOffBody'),
        );
      } else {
        body = _PoolDay(
          today: today.value,
          drinks: drinks,
          summary: summary,
          dayLabel: f.fmtDate(scope.to),
          rangeLabel: oneDay
              ? f.fmtDate(scope.to)
              : t(
                  'staffPool.drinksRange',
                  args: {
                    'from': f.fmtDate(scope.from),
                    'to': f.fmtDate(scope.to),
                  },
                ),
          showDate: !oneDay,
          onRetryDrinks: () => ref.invalidate(staffDrinksProvider(drinksQuery)),
          onRetrySummary: () =>
              ref.invalidate(staffDrinksSummaryProvider(drinksQuery)),
          onOpenOrder: canOpenOrders
              ? (id) => showStaffDrinkOrderSheet(context, orderId: id)
              : null,
        );
      }
    }

    return DashPageScaffold(
      title: title,
      subtitleWidget: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs + DashMetrics.hair,
        children: [
          DashIcon('calendar-range', size: IconSize.xs, color: c.textSecondary),
          Flexible(
            child: Text(
              f.fmtDate(scope.to),
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
      body: body,
    );
  }
}

abstract final class _Heights {
  /// `h-28`.
  static const double cards = Space.xxl * 3 + Space.lg;

  /// `h-64`.
  static const double table = Space.xxl * 8;
}

/// The pool on the period's last day, then every drink of the period.
class _PoolDay extends ConsumerWidget {
  const _PoolDay({
    required this.today,
    required this.drinks,
    required this.summary,
    required this.dayLabel,
    required this.rangeLabel,
    required this.showDate,
    required this.onRetryDrinks,
    required this.onRetrySummary,
    required this.onOpenOrder,
  });

  final StaffPoolToday? today;
  final AsyncValue<List<StaffDrink>?> drinks;
  final AsyncValue<StaffDrinksSummary?> summary;
  final String dayLabel;
  final String rangeLabel;
  final bool showDate;
  final VoidCallback onRetryDrinks;
  final VoidCallback onRetrySummary;
  final ValueChanged<String>? onOpenOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final over = today?.over ?? 0;
    final remaining = today?.remaining ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Text(
          t('staffPool.poolOn', args: {'date': dayLabel}),
          style: DashType.body.copyWith(color: c.textSecondary),
        ),
        _StatGrid(
          cards: [
            (
              label: t('staffPool.statAllowance'),
              value: today?.allowance ?? 0,
              icon: 'cup-soda',
              tone: DashTone.neutral,
              hint: null,
            ),
            (
              label: t('staffPool.statUsed'),
              value: today?.used ?? 0,
              icon: null,
              tone: DashTone.neutral,
              hint: null,
            ),
            (
              label: t('staffPool.statRemaining'),
              value: remaining,
              icon: null,
              tone: remaining > 0 ? DashTone.success : DashTone.neutral,
              hint: null,
            ),
            // Loud only when there is something to be loud about.
            (
              label: t('staffPool.statOver'),
              value: over,
              icon: null,
              tone: over > 0 ? DashTone.danger : DashTone.neutral,
              hint: over > 0 ? t('staffPool.statOverHint') : null,
            ),
          ],
        ),
        DashCard(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.lg,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.xs,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      t('staffPool.drinksTitle'),
                      style: DashType.sectionTitle.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    rangeLabel,
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
              StaffDrinksSummaryStrip(
                summary: summary.hasError ? null : summary.value,
                loading: summary.firstLoad,
                failed: summary.hasError,
                onRetry: onRetrySummary,
              ),
              StaffDrinksTable(
                drinks: drinks.hasError
                    ? const []
                    : (drinks.value ?? const <StaffDrink>[]),
                loading: drinks.firstLoad,
                error: drinks.hasError ? drinks.error : null,
                onRetry: onRetryDrinks,
                showDate: showDate,
                onOpenOrder: onOpenOrder,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

typedef _StatSpec = ({
  String label,
  int value,
  String? icon,
  DashTone tone,
  String? hint,
});

/// The four cards: one column on a phone, two from 640 wide, four from 1280
/// (`grid gap-3 sm:grid-cols-2 xl:grid-cols-4`); cards in a row share a
/// height. The Over allowance card wears a ring while it is above zero.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.cards});

  final List<_StatSpec> cards;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final w = MediaQuery.sizeOf(context).width;
    final cols = w >= DashBreakpoints.xl
        ? 4
        : w >= DashBreakpoints.sm
        ? 2
        : 1;
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += cols) {
      final slice = cards.sublist(i, (i + cols).clamp(0, cards.length));
      final footer = cols > 1 && slice.any((s) => s.hint != null);
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.md,
          children: [
            for (final s in slice)
              Expanded(
                child: Container(
                  foregroundDecoration: s.tone == DashTone.danger
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.card),
                          border: Border.all(
                            color: c.danger.withValues(
                              alpha: Opacities.disabled,
                            ),
                            width: DashMetrics.hair,
                          ),
                        )
                      : null,
                  child: DashStatCard(
                    label: s.label,
                    value: s.value,
                    format: DashStatFormat.number,
                    icon: s.icon,
                    tone: s.tone,
                    hint: s.hint,
                    reserveFooter: footer,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: rows,
    );
  }
}
