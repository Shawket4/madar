/// `dawam.approvals` page: the port of the web's dawam/approvals-page.tsx `ApprovalsPage`; TEAM-APR rows. Open to anyone who may decide at least one of its lists.
///
/// PLACEHOLDER from the area scaffold: the unit's builder replaces the body.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/page_gate.dart';
import '../shared/refresh_button.dart';

/// The lists' rights (TEAM-APR-001): requests any(`hr.leave.edit`,
/// `hr.attendance.edit`), advances `hr.advances.decide`, swaps and open-shift
/// claims `hr.schedule.edit`, covers `hr.shift_cover.confirm`, overtime
/// `hr.overtime.approve`, pay lines over a limit `hr.payroll.run`.
const List<String> approvalsCaps = [
  Cap.hrLeaveEdit,
  Cap.hrAttendanceEdit,
  Cap.hrAdvancesDecide,
  Cap.hrScheduleEdit,
  Cap.hrShiftCoverConfirm,
  Cap.hrOvertimeApprove,
  Cap.hrPayrollRun,
];

class ApprovalsPage extends ConsumerWidget {
  const ApprovalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return TeamPageGate(
      allowed: (a) => a.canAny(approvalsCaps),
      titleKey: 'dawam.approvals',
      whoKey: 'dawam.approvalsNoAccess',
      child: DashPageScaffold(
        title: t('dawam.approvals'),
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
