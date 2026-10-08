/// `/reports/loyalty` Loyalty (REP-LOY rows): tabs Overview, Campaigns,
/// Liability (`features/reports/loyalty/loyalty-report-page.tsx`).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart';

/// The route's page (`DashRoute.builder`).
Widget loyaltyReportPageBuilder(BuildContext context, GoRouterState state) =>
    const LoyaltyReportPage();

/// The tabs (REP-LOY-002), page state; default Overview.
const List<DashRouteTab> loyaltyReportTabs = [
  DashRouteTab(id: 'overview', labelKey: 'reports.loyalty.tabs.overview'),
  DashRouteTab(id: 'campaigns', labelKey: 'reports.loyalty.tabs.campaigns'),
  DashRouteTab(id: 'liability', labelKey: 'reports.loyalty.tabs.liability'),
];

class LoyaltyReportPage extends ConsumerWidget {
  const LoyaltyReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('reports.loyalty.title'),
      subtitleWidget: const ReportPeriodSubtitle(),
      body: DashEmptyState(
        icon: 'layers',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
