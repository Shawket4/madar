/// `staff.rules` page: the port of the web's staff/attendance-rules-page.tsx `AttendanceRulesPage`; TEAM-RUL rows.
///
/// PLACEHOLDER from the area scaffold: the unit's builder replaces the body.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/page_gate.dart';
import '../shared/refresh_button.dart';

class AttendanceRulesPage extends ConsumerWidget {
  const AttendanceRulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return TeamPageGate(
      allowed: (a) => a.canAny(const [Cap.hrRulesEdit, Cap.hrRulesView]),
      titleKey: 'staff.rules',
      whoKey: 'staff.rulesNoAccess',
      child: DashPageScaffold(
        title: t('staff.rules'),
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
