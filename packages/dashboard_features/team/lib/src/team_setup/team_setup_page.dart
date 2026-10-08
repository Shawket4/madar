/// Set-up (`/staff/setup`, the web's `dawam/setup-page.tsx` `SetupPage`,
/// TEAM-SET rows): the owner's four steps after a business is created —
/// where each branch is, who works there, their shifts, and the rules they
/// are paid by. A guided flow, one decision per screen: it opens on the
/// first step that isn't done, each step's tick comes from the data itself
/// (never a box someone ticks), any step opens at any time, and every step
/// does its job right here with the same calls its full page makes.
///
/// A capability, not a role: the page is for whoever holds `hr.rules.edit`.
/// A reading-width page; its Refresh also covers `/branches`.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/page_gate.dart';
import '../shared/refresh_button.dart';
import '../shared/refresh_toast.dart';
import '../shared/setup_data.dart';
import '../shared/staff_query.dart';
import 'setup_branches_step.dart';
import 'setup_dialogs.dart';
import 'setup_steps.dart';

/// The checklist reads the branches (step 1) besides Dawam's own.
const List<String> setupRefreshPrefixes = [dawamKeyPrefix, '/branches'];

/// How long a read stays fresh before coming back to the app refetches it
/// (the app-wide `staleTime`, TEAM-ALL-009).
const Duration setupStaleAfter = Duration(seconds: 30);

class TeamSetupPage extends ConsumerWidget {
  const TeamSetupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => TeamPageGate(
    allowed: (a) => a.can(Cap.hrRulesEdit),
    titleKey: 'dawam.setup',
    whoKey: 'dawam.setupNoAccess',
    child: const _SetupBody(),
  );
}

class _SetupBody extends ConsumerStatefulWidget {
  const _SetupBody();

  @override
  ConsumerState<_SetupBody> createState() => _SetupBodyState();
}

class _SetupBodyState extends ConsumerState<_SetupBody> {
  SetupStep? _step;
  late final AppLifecycleListener _lifecycle;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Refetch on focus (`dawamQuery`): coming back after the reads went stale
  /// asks again; sooner does nothing.
  void _onResume() {
    final at = _loadedAt;
    if (at == null || !mounted) return;
    final now = ref.read(clockProvider)();
    if (now.difference(at) < setupStaleAfter) return;
    _loadedAt = now;
    ref.read(staffRevisionsProvider.notifier).refetch();
    ref.invalidate(branchesProvider);
  }

  String _short(Translator t, SetupStep s) => switch (s) {
    SetupStep.branches => t('dawam.stepBranches'),
    SetupStep.employees => t('dawam.stepEmployees'),
    SetupStep.shifts => t('dawam.stepShifts'),
    SetupStep.rules => t('dawam.stepRules'),
  };

  (String, String) _titleHint(Translator t, SetupStep s) => switch (s) {
    SetupStep.branches => (
      t('dawam.setupBranchesV2'),
      t('dawam.setupBranchesHintV2'),
    ),
    SetupStep.employees => (
      t('dawam.setupEmployeesV2'),
      t('dawam.setupEmployeesHint'),
    ),
    SetupStep.shifts => (t('dawam.setupShiftsV2'), t('dawam.setupShiftsHintV2')),
    SetupStep.rules => (t('dawam.setupRulesV2'), t('dawam.setupRulesHint')),
  };

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final authz = ref.watch(authzProvider);
    // `useSetupData(canSetUp, true)`: nothing is asked without the right.
    final canSetUp = authz.can(Cap.hrRulesEdit);
    final data = canSetUp
        ? ref.watch(teamSetupDataProvider)
        : const TeamSetupData();
    final reads = canSetUp
        ? <AsyncValue<Object?>>[
            ref.watch(branchesProvider),
            ref.watch(setupActiveEmployeesProvider),
            ref.watch(setupWorkShiftsProvider),
            ref.watch(setupAttendanceSettingsProvider),
          ]
        : const <AsyncValue<Object?>>[];
    if (canSetUp) {
      // A failed background refresh of a `/staff` read keeps its data and
      // says so once (`/branches` is outside `/staff`: no toast).
      listenStaffRefreshFailure(ref, context, setupActiveEmployeesProvider);
      listenStaffRefreshFailure(ref, context, setupWorkShiftsProvider);
      listenStaffRefreshFailure(ref, context, setupAttendanceSettingsProvider);
    }
    final p = data.progress;
    if (p.ready) {
      _loadedAt ??= ref.read(clockProvider)();
      // Open on the first step that isn't done, once the answers are in.
      _step ??=
          SetupStep.values.where((s) => !p.done[s]!).firstOrNull ??
          SetupStep.rules;
    }

    final Widget body;
    if (!p.ready && data.error != null) {
      body = DashErrorState(
        key: const ValueKey('setup-error'),
        title: t('dawam.setupLoadError'),
        message: errorMessage(data.error, t),
        onRetry: () => retryTeamSetup(ref),
      );
    } else if (!p.ready || _step == null) {
      body = const Column(
        key: ValueKey('setup-loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          DashSkeleton(height: 56, radius: Radii.control),
          DashSkeleton(height: 288, radius: Radii.card),
        ],
      );
    } else {
      body = _content(context, t, authz, data, p, _step!);
    }

    return DashPageScaffold(
      title: t('dawam.setupTitle'),
      subtitle: p.ready
          ? t(
              'dawam.setupProgress',
              args: {'n': p.count, 'total': SetupStep.values.length},
            )
          : t('dawam.setupSubtitle'),
      actions: [
        DawamRefreshButton(
          key: const ValueKey('setup-refresh'),
          busy: anyFetching(reads),
          prefixes: setupRefreshPrefixes,
          onRefresh: () => ref.invalidate(branchesProvider),
        ),
      ],
      width: DashPageWidth.reading,
      body: body,
    );
  }

  Widget _content(
    BuildContext context,
    Translator t,
    Authz authz,
    TeamSetupData data,
    SetupProgress p,
    SetupStep step,
  ) {
    final c = context.madarColors;
    final phone = DashBreakpoints.isPhone(context);
    final steps = SetupStep.values;
    final i = steps.indexOf(step);
    final prev = i > 0 ? steps[i - 1] : null;
    final next = i < steps.length - 1 ? steps[i + 1] : null;
    final branches = data.branches ?? const <Branch>[];
    String branchName(String? id) => id == null
        ? t('staff.wholeBusiness')
        : (branches.where((b) => b.id == id).firstOrNull?.name ?? '');
    final (title, hint) = _titleHint(t, step);

    final Widget stepBody = switch (step) {
      SetupStep.branches => SetupBranchesStep(
        branches: branches,
        canEdit: authz.can(Cap.branchesEdit),
      ),
      SetupStep.employees => SetupPeopleStep(
        employees: data.employees ?? const [],
        canCreate: authz.can(Cap.hrStaffCreate),
        onAddOne: () => openSetupAddEmployee(context, ref),
        onImport: () => openSetupImportPeople(context, ref),
      ),
      SetupStep.shifts => SetupShiftsStep(
        shifts: data.shifts ?? const [],
        branchName: branchName,
        canCreate: authz.can(Cap.hrScheduleCreate),
        onNew: () => openSetupNewShift(
          context,
          ref,
          branches: branches,
          wholeBusiness: authz.canEverywhere(Cap.hrScheduleCreate),
        ),
      ),
      SetupStep.rules => SetupRulesStep(
        settings: data.settings!,
        canGender: authz.can(Cap.hrRosterSettings),
      ),
    };

    final footer = Container(
      margin: const EdgeInsets.only(top: Space.xl),
      padding: const EdgeInsets.only(top: Space.lg),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.md,
        runSpacing: Space.md,
        children: [
          if (prev != null)
            DashButton(
              key: const ValueKey('setup-back'),
              label: _short(t, prev),
              icon: Directionality.of(context) == TextDirection.rtl
                  ? 'arrow-right'
                  : 'arrow-left',
              variant: DashButtonVariant.ghost,
              onPressed: () => setState(() => _step = prev),
            )
          else
            const SizedBox.shrink(),
          if (next != null)
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.md,
              runSpacing: Space.sm,
              children: [
                if (!p.done[step]!)
                  Text(
                    t('dawam.setupComeBack'),
                    key: const ValueKey('setup-come-back'),
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                DashButton(
                  key: const ValueKey('setup-next'),
                  label: t(
                    'dawam.setupNext',
                    args: {'step': _short(t, next)},
                  ),
                  trailingIcon: DashIcon.arrowForward(context),
                  variant: p.done[step]!
                      ? DashButtonVariant.primary
                      : DashButtonVariant.outline,
                  onPressed: () => setState(() => _step = next),
                ),
              ],
            ),
        ],
      ),
    );

    final card = Semantics(
      container: true,
      label: title,
      explicitChildNodes: true,
      child: Container(
        key: const ValueKey('setup-step-card'),
        padding: EdgeInsets.all(phone ? Space.lg : Space.xl),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: Space.lg + Space.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.xs,
                children: [
                  Text(
                    t(
                      'dawam.setupStepOf',
                      args: {'n': i + 1, 'total': steps.length},
                    ),
                    style: DashType.smallMedium.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      key: const ValueKey('setup-step-title'),
                      style: DashType.paneTitle.copyWith(color: c.textPrimary),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: DashMetrics.proseWide,
                    ),
                    child: Text(
                      hint,
                      style: DashType.body.copyWith(color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            KeyedSubtree(key: ValueKey('setup-body-${step.name}'), child: stepBody),
            footer,
          ],
        ),
      ),
    );

    return Column(
      key: const ValueKey('setup-ready'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        _Stepper(
          current: step,
          done: p.done,
          shortOf: (s) => _short(t, s),
          onPick: (s) => setState(() => _step = s),
        ),
        if (p.complete) const _AllSet(),
        card,
      ],
    );
  }
}

/// The four steps across the top (`nav aria-label="Set-up steps"`): each a
/// button with its number (a tick when done), its short name and Done / To
/// do. Any step opens any time. The label stacks under the circle on a
/// phone.
class _Stepper extends ConsumerWidget {
  const _Stepper({
    required this.current,
    required this.done,
    required this.shortOf,
    required this.onPick,
  });

  final SetupStep current;
  final Map<SetupStep, bool> done;
  final String Function(SetupStep) shortOf;
  final ValueChanged<SetupStep> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final steps = SetupStep.values;
    return Semantics(
      container: true,
      label: t('dawam.setupSteps'),
      explicitChildNodes: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: wide ? Space.sm : Space.xs + DashMetrics.hair,
          children: [
            for (var n = 0; n < steps.length; n++)
              Expanded(
                child: _stepButton(context, t, c, steps[n], n, wide),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stepButton(
    BuildContext context,
    Translator t,
    MadarColors c,
    SetupStep s,
    int n,
    bool wide,
  ) {
    final isDone = done[s]!;
    final isCurrent = s == current;
    final state = isDone ? t('dawam.setupDone') : t('dawam.setupToDo');
    final radius = BorderRadius.circular(Radii.xs);
    final circle = Container(
      width: Space.xl,
      height: Space.xl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDone
            ? c.success
            : isCurrent
            ? c.accent
            : c.muted,
      ),
      child: isDone
          ? DashIcon('check', size: IconSize.xs, color: c.surface)
          : Text(
              '${n + 1}',
              style: DashType.smallStrong.copyWith(
                color: isCurrent ? c.textOnAccent : c.textSecondary,
              ),
            ),
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MadarClippedText(
          shortOf(s),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (isCurrent ? DashType.bodyStrong : DashType.bodyMedium)
              .copyWith(color: c.textPrimary),
        ),
        Text(state, style: DashType.small.copyWith(color: c.textSecondary)),
      ],
    );
    return DashPressable(
      key: ValueKey('setup-step-${s.name}'),
      onTap: () => onPick(s),
      selected: isCurrent,
      semanticLabel: '${n + 1}. ${shortOf(s)}, $state',
      excludeChildSemantics: true,
      builder: (context, st) => Container(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        padding: EdgeInsets.symmetric(
          horizontal: wide ? Space.md : Space.sm + DashMetrics.hair,
          vertical: Space.sm,
        ),
        foregroundDecoration: dashFocusRing(context, st, radius),
        decoration: BoxDecoration(
          color: isCurrent
              ? c.card
              : st.highlighted
              ? c.hover
              : null,
          borderRadius: radius,
          border: Border.all(color: isCurrent ? c.accent : c.hairline),
        ),
        child: wide
            ? Row(
                spacing: Space.sm,
                children: [
                  circle,
                  Expanded(child: words),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xs,
                children: [circle, words],
              ),
      ),
    );
  }
}

/// 4 of 4 (`role="status"`): the team can clock in; on to the schedule or
/// the board.
class _AllSet extends ConsumerWidget {
  const _AllSet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const ValueKey('setup-complete'),
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: DashTone.success.wash(c),
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: c.success.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.md,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: DashMetrics.hair),
              child: DashIcon(
                'party-popper',
                size: IconSize.lg,
                color: DashTone.success.foreground(c),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.sm,
                children: [
                  Text(
                    t('dawam.setupComplete'),
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      DashButton(
                        key: const ValueKey('setup-go-schedule'),
                        label: t('dawam.setupGoSchedule'),
                        size: DashButtonSize.compact,
                        onPressed: () => context.go('/staff/schedule'),
                      ),
                      DashButton(
                        key: const ValueKey('setup-go-team'),
                        label: t('dawam.setupGoTeam'),
                        size: DashButtonSize.compact,
                        variant: DashButtonVariant.outline,
                        onPressed: () => context.go('/staff/team'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
