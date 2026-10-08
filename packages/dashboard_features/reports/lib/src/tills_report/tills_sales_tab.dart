/// The Sales tab (REP-TIL-017 … -020): what each drawer actually took.
///
/// Four KPIs computed from the rows (net sales, orders, the average bill
/// over ORDERS, the average per till), then the sessions ranked by net
/// sales — teller · branch · business date, so one teller's days can be told
/// apart — each with a bar against the BEST session and its share of the
/// period. The ranking shows its top 20 until asked for all.
library;

import 'package:dashboard_api/dashboard_api.dart' show TillSessionRow;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart';
import 'tills_lib.dart';
import 'tills_parts.dart';

/// A quarter of tills is thousands of sessions; the ranking is about its
/// head.
const int tillsTopSessions = 20;

class TillSalesTab extends ConsumerStatefulWidget {
  const TillSalesTab({required this.load, super.key});

  final TillsLoad load;

  @override
  ConsumerState<TillSalesTab> createState() => _TillSalesTabState();
}

class _TillSalesTabState extends ConsumerState<TillSalesTab> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final load = widget.load;
    final state = tillTabState(context, t, load);
    if (state != null) return state;

    final rows = load.rows;
    final s = salesStats(rows);
    final ranked = rankBySales(rows);
    final top = ranked.first.netSales;
    final shown = _showAll ? ranked : ranked.take(tillsTopSessions).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        DashLedgerStrip(
          items: [
            DashLedgerItem(
              key: 'sales',
              label: t('reports.tills.totalSales'),
              value: s.sales,
              format: DashStatFormat.money,
              icon: 'coins',
            ),
            DashLedgerItem(
              key: 'orders',
              label: t('reports.tills.totalOrders'),
              value: s.orders,
              format: DashStatFormat.number,
              icon: 'receipt',
            ),
            DashLedgerItem(
              key: 'aov',
              label: t('reports.tills.avgOrderValue'),
              value: s.avgOrderValue,
              format: DashStatFormat.money,
              icon: 'trending-up',
            ),
            DashLedgerItem(
              key: 'perTill',
              label: t('reports.tills.avgPerTill'),
              value: s.avgSalesPerTill,
              format: DashStatFormat.money,
              icon: 'wallet',
              hint: t('reports.tills.acrossTills', count: s.tills),
            ),
          ],
        ),
        DashCard(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  t('reports.tills.bySession'),
                  style: DashType.sectionTitle.copyWith(color: c.textPrimary),
                ),
              ),
              const SizedBox(height: Space.sm),
              for (final (i, r) in shown.indexed) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: c.hairline),
                _SessionLine(
                  key: ValueKey('till-rank:${r.tillId}'),
                  row: r,
                  top: top,
                  total: s.sales,
                  format: f,
                ),
              ],
              if (ranked.length > tillsTopSessions)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: DashButton(
                      label: _showAll
                          ? t('reports.tills.showTop', count: tillsTopSessions)
                          : t('reports.tills.showAll', count: ranked.length),
                      variant: DashButtonVariant.ghost,
                      size: DashButtonSize.compact,
                      onPressed: () => setState(() => _showAll = !_showAll),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One ranked session: who, where, which day and what it took; a bar
/// against the best session; "N orders · share of the period".
class _SessionLine extends ConsumerWidget {
  const _SessionLine({
    required this.row,
    required this.top,
    required this.total,
    required this.format,
    super.key,
  });

  final TillSessionRow row;

  /// The best session's net sales (the bar's full width).
  final int top;

  /// The period's net sales (the share's whole).
  final int total;
  final DashFormat format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final f = format;
    final r = row;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs + 2,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: Space.md,
            children: [
              Expanded(
                child: MadarClippedText.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: r.tellerName,
                        style: DashType.bodyMedium.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      // The day too: one teller opens many tills a period.
                      TextSpan(
                        text:
                            ' · ${r.branchName} · '
                            '${fmtBusinessDate(f, r.businessDate)}',
                        style: DashType.body.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                dashFigure(f.fmtMoney(r.netSales)),
                maxLines: 1,
                softWrap: false,
                style: DashType.body.copyWith(
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Row(
            spacing: Space.sm,
            children: [
              // Against the best session, so the bars compare like with like.
              Expanded(
                child: DashProgressBar(
                  value: r.netSales.toDouble(),
                  max: top.toDouble(),
                  semanticLabel: t(
                    'reports.tills.barLabel',
                    args: {'share': f.fmtShare(r.netSales, top)},
                  ),
                ),
              ),
              Text(
                t(
                  'reports.tills.ordersShare',
                  args: {
                    'orders': f.fmtNumber(r.ordersCount),
                    'share': total > 0 ? f.fmtShare(r.netSales, total) : '—',
                  },
                ),
                maxLines: 1,
                softWrap: false,
                style: DashType.small.copyWith(
                  color: c.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
