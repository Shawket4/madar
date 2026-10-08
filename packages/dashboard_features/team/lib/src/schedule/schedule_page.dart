/// `dawam.schedule` page: the port of the web's dawam/schedule-page.tsx `SchedulePage`; TEAM-SCH rows.
///
/// PLACEHOLDER from the area scaffold: the unit's builder replaces the body.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/page_gate.dart';
import '../shared/refresh_button.dart';
import '../shared/rules_banner.dart';

class SchedulePage extends ConsumerWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return TeamPageGate(
      allowed: (a) => a.can(Cap.hrScheduleRead),
      titleKey: 'dawam.schedule',
      whoKey: 'dawam.scheduleNoAccess',
      child: DashPageScaffold(
        title: t('dawam.schedule'),
        actions: const [DawamRefreshButton()],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [const RulesFirstBanner(), _pending(t)],
        ),
      ),
    );
  }

  Widget _pending(Translator t) => DashEmptyState(
    icon: 'layers',
    title: t('shell.pendingTitle'),
    description: t('shell.pendingBody'),
  );
}
