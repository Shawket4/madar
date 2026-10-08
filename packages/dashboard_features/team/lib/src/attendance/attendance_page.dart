/// `staff.attendance` page: the port of the web's staff/attendance-page.tsx `AttendancePage`; TEAM-ATT rows. No in-page guard (TEAM-ALL-007).
///
/// PLACEHOLDER from the area scaffold: the unit's builder replaces the body.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/refresh_button.dart';

class AttendancePage extends ConsumerWidget {
  const AttendancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('staff.attendance'),
      actions: const [DawamRefreshButton()],
      body: _pending(t),
    );
  }

  Widget _pending(Translator t) => DashEmptyState(
    icon: 'layers',
    title: t('shell.pendingTitle'),
    description: t('shell.pendingBody'),
  );
}
