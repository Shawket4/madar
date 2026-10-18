/// The Operations report's building blocks, taken from its Overview tab so
/// every tab is laid out, loads, fails and empties the same way (the web's
/// `features/reports/operations/report-kit.tsx`):
///
///   OpsReportStack                one rhythm between sections (16 px)
///     DashLedgerStrip             KPIs; a failed read reads "—" ([opsKpi])
///     OpsChartGrid                charts, two up from 1024 px
///       DashChartCard
///         OpsChartBody            skeleton → error → empty → the chart
///     OpsTableCard                a titled card holding a DashDataTable
///       or an OpsRankTable        (a ranked, sortable table with motion,
///                                 `ops_rank_table.dart`)
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'ops_charts.dart';

/// The vertical rhythm of a tab: KPIs, chart grid and full-width cards,
/// 16 px apart (`ReportStack`, `space-y-4`).
class OpsReportStack extends StatelessWidget {
  const OpsReportStack({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.lg,
    children: children,
  );
}

/// Cards two up (equal height) from 1024 px, one column below
/// (`ChartGrid`, `grid gap-4 lg:grid-cols-2`).
class OpsChartGrid extends StatelessWidget {
  const OpsChartGrid({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= DashBreakpoints.lg) {
      final rows = <Widget>[
        for (var i = 0; i < children.length; i += 2)
          OpsEqualRow(
            children: [
              children[i],
              if (i + 1 < children.length)
                children[i + 1]
              else
                const SizedBox.shrink(),
            ],
          ),
      ];
      return rows.length == 1 ? rows.single : OpsReportStack(children: rows);
    }
    return OpsReportStack(children: children);
  }
}

/// A KPI through the tab's read: a failed one reads "—" with no hint, never
/// 0 (the web's `kpi()`); loading keeps its skeleton.
DashLedgerItem opsKpi(DashLedgerItem item, {required bool failed}) => failed
    ? DashLedgerItem(
        key: item.key,
        label: item.label,
        valueText: '—',
        icon: item.icon,
        tone: item.tone,
        loading: item.loading,
        action: item.action,
      )
    : item;

/// A card's body through its states, in the order the Overview checks them:
/// loading, failed, empty, then the content (`ChartBody`). Plot-height states
/// keep the card its size from skeleton to figure; `height: null` (a list
/// card) takes its own, with [skeleton] in place of the plot's.
class OpsChartBody extends StatelessWidget {
  const OpsChartBody({
    required this.loading,
    required this.failed,
    required this.empty,
    required this.emptyTitle,
    required this.onRetry,
    required this.chart,
    this.height = opsChartHeight,
    this.skeleton,
    this.retrying = false,
    super.key,
  });

  final bool loading;
  final bool failed;
  final bool empty;
  final String emptyTitle;
  final VoidCallback onRetry;
  final WidgetBuilder chart;

  /// The skeleton's and the states' height (null = their own).
  final double? height;

  /// The loading look of an `auto` card (a list), instead of the plot's.
  final Widget? skeleton;

  /// A manual Retry is running: the error stays, its button spins.
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return skeleton ?? DashSkeleton(height: height ?? opsChartHeight);
    }
    Widget sized(Widget w) => height == null
        ? w
        : SizedBox(
            height: height,
            child: Center(child: w),
          );
    if (failed) {
      return sized(
        DashErrorState(framed: false, onRetry: onRetry, retrying: retrying),
      );
    }
    if (empty) {
      return sized(DashEmptyState(title: emptyTitle, framed: false));
    }
    return chart(context);
  }
}

/// A titled card holding a table: the full-width section of a tab
/// (`TableCard`). The table runs edge to edge on desktop, its toolbar on the
/// card's gutter; on a phone its rows become cards, inset like the rest of
/// the card's content. A failed load reads like a failed chart, and
/// [footnote] lines up with the title.
class OpsTableCard extends StatelessWidget {
  const OpsTableCard({
    required this.title,
    required this.child,
    this.description,
    this.actions = const [],
    this.footnote,
    this.failed = false,
    this.loading = false,
    this.retrying = false,
    this.onRetry,
    super.key,
  });

  final String title;
  final String? description;
  final List<Widget> actions;

  /// The table (frameless, its toolbar padded by [opsTableToolbarPadding]).
  final Widget child;
  final Widget? footnote;

  /// The read failed: the card shows the chart error instead of the table
  /// (unless it is loading again, [loading]).
  final bool failed;
  final bool loading;
  final bool retrying;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final phone = DashBreakpoints.isPhone(context);
    final inset = phone ? Space.md : 0.0;
    final gutter = phone ? Space.md : Space.card;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.card),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.lg,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.card),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.xs,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: DashType.sectionTitle.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      if (description != null)
                        Text(
                          description!,
                          style: DashType.body.copyWith(color: c.textSecondary),
                        ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: failed && (!loading || retrying)
                ? SizedBox(
                    height: opsChartHeight,
                    child: Center(
                      child: DashErrorState(
                        framed: false,
                        onRetry: onRetry,
                        retrying: retrying,
                      ),
                    ),
                  )
                : child,
          ),
          if (footnote != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: DefaultTextStyle.merge(
                style: DashType.small.copyWith(color: c.textSecondary),
                child: footnote!,
              ),
            ),
        ],
      ),
    );
  }
}

/// The toolbar's inset for a table inside an [OpsTableCard]: on the card's
/// gutter on desktop (the web's `toolbarClassName="sm:px-5"`); a phone's
/// card already insets the whole table.
EdgeInsetsGeometry opsTableToolbarPadding(BuildContext context) =>
    DashBreakpoints.isPhone(context)
    ? EdgeInsets.zero
    : const EdgeInsets.symmetric(horizontal: Space.card);
