/// `/reports/staff` Staff discipline (REP-STF rows): one card per
/// department, ranked (`features/reports/staff/staff-discipline-page.tsx`).
/// A Dawam page: the module gate shows the Dawam-off words when it is off.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart';

/// The route's page (`DashRoute.builder`).
Widget staffDisciplinePageBuilder(BuildContext context, GoRouterState state) =>
    const StaffDisciplinePage();

class StaffDisciplinePage extends ConsumerWidget {
  const StaffDisciplinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('reports.staff.title'),
      subtitleWidget: const ReportPeriodSubtitle(),
      body: DashEmptyState(
        icon: 'layers',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
