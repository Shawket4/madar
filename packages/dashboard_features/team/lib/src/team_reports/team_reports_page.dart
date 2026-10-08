/// `dawam.reports` page: the port of the web's dawam/reports-page.tsx `StaffReportsPage`; TEAM-RPT rows. Refused when no tab is allowed: attendance (`hr.attendance.read`), labour vs sales (`hr.payroll.read` + module pos), payroll and advances (`hr.payroll.read`).
///
/// PLACEHOLDER from the area scaffold: the unit's builder replaces the body.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/page_gate.dart';
import '../shared/refresh_button.dart';

class StaffReportsPage extends ConsumerWidget {
  const StaffReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return TeamPageGate(
      allowed: (a) => a.canAny(const [Cap.hrAttendanceRead, Cap.hrPayrollRead]),
      titleKey: 'dawam.reports',
      whoKey: 'dawam.reportsNoAccess',
      child: DashPageScaffold(
        title: t('dawam.reports'),
        actions: const [DawamRefreshButton()],
        body: _pending(t),
      ),
    );
  }

  Widget _pending(Translator t) => DashEmptyState(
    icon: 'layers',
    title: t('shell.pendingTitle'),
    description: t('shell.pendingBody'),
  );
}
