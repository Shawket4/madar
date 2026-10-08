/// The Open & close tab (REP-TIL-017, -021, -022): when drawers open, when
/// they close, and for how long.
///
/// The typical open and close are CIRCULAR means of the times of day (a
/// late-night branch would otherwise report an average open of lunchtime);
/// the average length counts closed sessions with a non-negative span only;
/// the longest session names its teller, branch and business date. Then the
/// opens and closes by local hour.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart';
import 'tills_lib.dart';
import 'tills_parts.dart';

class TillTimingTab extends ConsumerWidget {
  const TillTimingTab({required this.load, super.key});

  final TillsLoad load;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final state = tillTabState(context, t, load);
    if (state != null) return state;

    final rows = load.rows;
    final s = timingStats(rows, f.timezone);
    final hours = byHour(rows, f.timezone);
    final longest = s.longest;
    final open = fmtMinutesOfDay(f, s.avgOpen);
    final close = fmtMinutesOfDay(f, s.avgClose);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        DashLedgerStrip(
          items: [
            DashLedgerItem(
              key: 'open',
              label: t('reports.tills.avgOpen'),
              valueText: open,
              icon: 'door-open',
            ),
            DashLedgerItem(
              key: 'close',
              label: t('reports.tills.avgClose'),
              valueText: close,
              icon: 'door-closed',
              hint: s.openNow > 0
                  ? t('reports.tills.stillOpenCount', count: s.openNow)
                  : null,
            ),
            DashLedgerItem(
              key: 'duration',
              label: t('reports.tills.avgDuration'),
              valueText: s.avgDurationMs == null
                  ? '—'
                  : f.fmtElapsedMs(s.avgDurationMs!),
              icon: 'hourglass',
            ),
            DashLedgerItem(
              key: 'longest',
              label: t('reports.tills.longest'),
              valueText: longest == null
                  ? '—'
                  : f.fmtDuration(longest.openedAt, longest.closedAt),
              icon: 'clock',
              hint: longest == null
                  ? null
                  : '${longest.tellerName} · ${longest.branchName} · '
                        '${fmtBusinessDate(f, longest.businessDate)}',
            ),
          ],
        ),
        DashChartCard(
          title: t('reports.tills.byHour'),
          child: TillHourChart(
            buckets: hours,
            summary: t(
              'reports.tills.byHourSummary',
              args: {'open': open, 'close': close},
            ),
          ),
        ),
      ],
    );
  }
}
