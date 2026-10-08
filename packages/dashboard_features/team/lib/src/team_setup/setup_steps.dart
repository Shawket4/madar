/// Set-up steps 2–4 (`dawam/setup-steps.tsx` `EmployeesStep`, `ShiftsStep`,
/// `RulesStep`; TEAM-SET-024…035): who works here, when they work, and what
/// lateness costs. Each one saves through the same call its full page makes
/// and says out loud when a save fails.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/staff_query.dart';
import '../shared/team_format.dart';
import '../shared/week.dart';
import 'geo.dart' show jsNumber;
import 'setup_rules.dart';

/// How many names the people step shows before "+N".
const int setupNamesShown = 24;

// ── Step 2: people ──────────────────────────────────────────────────────────

class SetupPeopleStep extends ConsumerWidget {
  const SetupPeopleStep({
    required this.employees,
    required this.canCreate,
    required this.onAddOne,
    required this.onImport,
    super.key,
  });

  final List<Employee> employees;

  /// `hr.staff.create`.
  final bool canCreate;
  final VoidCallback onAddOne;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final active = [
      for (final e in employees)
        if (e.employmentStatus == 'active') e,
    ];
    final noSalary = active.where((e) => !e.salarySet).length;
    final actions = canCreate
        ? Wrap(
            key: const ValueKey('setup-people-actions'),
            spacing: Space.sm,
            runSpacing: Space.sm,
            alignment: active.isEmpty
                ? WrapAlignment.center
                : WrapAlignment.start,
            children: [
              DashButton(
                key: const ValueKey('setup-add-employee'),
                label: t('dawam.addEmployee'),
                icon: 'user-round-plus',
                onPressed: onAddOne,
              ),
              DashButton(
                key: const ValueKey('setup-import-people'),
                label: t('dawam.importTitle'),
                icon: 'file-spreadsheet',
                variant: DashButtonVariant.outline,
                onPressed: onImport,
              ),
            ],
          )
        : Text(
            t('dawam.setupNoCreate'),
            key: const ValueKey('setup-no-create'),
            textAlign: active.isEmpty ? TextAlign.center : TextAlign.start,
            style: DashType.body.copyWith(color: c.textSecondary),
          );

    if (active.isEmpty) {
      return DashEmptyState(
        key: const ValueKey('setup-no-people'),
        icon: 'user-round-plus',
        title: t('dawam.setupNoEmployees'),
        description: t('dawam.setupNoEmployeesHint'),
        framed: false,
        action: actions,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Text(
          t('dawam.setupEmployeeCount', count: active.length),
          style: DashType.body.copyWith(color: c.textPrimary),
        ),
        Wrap(
          spacing: Space.xs + DashMetrics.hair,
          runSpacing: Space.xs + DashMetrics.hair,
          children: [
            for (final e in active.take(setupNamesShown))
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm + DashMetrics.hair,
                  vertical: Space.xs,
                ),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: Border.all(color: c.hairline),
                ),
                child: Text(
                  e.name,
                  style: DashType.body.copyWith(color: c.textPrimary),
                ),
              ),
            if (active.length > setupNamesShown)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm + DashMetrics.hair,
                  vertical: Space.xs,
                ),
                child: Text(
                  '+${active.length - setupNamesShown}',
                  key: const ValueKey('setup-people-more'),
                  style: DashType.body.copyWith(color: c.textSecondary),
                ),
              ),
          ],
        ),
        if (noSalary > 0)
          Semantics(
            container: true,
            key: const ValueKey('setup-no-salary'),
            child: Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: DashTone.warning.wash(c),
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.sm,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: DashMetrics.hair),
                    child: DashIcon(
                      'triangle-alert',
                      color: DashTone.warning.foreground(c),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      t('dawam.setupNoSalary', count: noSalary),
                      style: DashType.body.copyWith(color: c.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        actions,
      ],
    );
  }
}

// ── Step 3: shifts ──────────────────────────────────────────────────────────

/// Minutes from [start] to [end] on the wall clock, past midnight when the
/// end comes first (`spanMinutes`); null when either is not a time.
int? spanMinutes(String? start, String? end) {
  final a = DashTime.minutesOf(start);
  final b = DashTime.minutesOf(end);
  if (a == null || b == null) return null;
  if (a == b) return 0;
  return b > a ? b - a : b + 1440 - a;
}

/// Whether [start]→[end] finishes on the next calendar day (`endsNextDay`).
bool endsNextDay(String? start, String? end) {
  final a = DashTime.minutesOf(start);
  final b = DashTime.minutesOf(end);
  return a != null && b != null && b < a;
}

class SetupShiftsStep extends ConsumerWidget {
  const SetupShiftsStep({
    required this.shifts,
    required this.branchName,
    required this.canCreate,
    required this.onNew,
    super.key,
  });

  final List<WorkShift> shifts;

  /// A branch's name, or "Every branch" for a business-wide block.
  final String Function(String? branchId) branchName;

  /// `hr.schedule.create`.
  final bool canCreate;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final active = [
      for (final s in shifts)
        if (s.isActive) s,
    ];
    final newButton = canCreate
        ? DashButton(
            key: const ValueKey('setup-new-shift'),
            label: t('staff.newShift'),
            icon: 'plus',
            onPressed: onNew,
          )
        : Text(
            t('dawam.setupNoShiftCreate'),
            key: const ValueKey('setup-no-shift-create'),
            textAlign: active.isEmpty ? TextAlign.center : TextAlign.start,
            style: DashType.body.copyWith(color: c.textSecondary),
          );
    if (active.isEmpty) {
      return DashEmptyState(
        key: const ValueKey('setup-no-shifts'),
        icon: 'moon-star',
        title: t('dawam.setupNoShifts'),
        description: t('dawam.setupNoShiftsHint'),
        framed: false,
        action: newButton,
      );
    }
    final rows = <Widget>[
      for (final s in active)
        _ShiftRow(
          key: ValueKey('setup-shift-${s.id}'),
          shift: s,
          times: '${f.fmtWireTime(s.startTime)} – ${f.fmtWireTime(s.endTime)}',
          span: switch (spanMinutes(s.startTime, s.endTime)) {
            null || 0 => null,
            final m => formatSpan(m, lang),
          },
          nextDay: endsNextDay(s.startTime, s.endTime)
              ? t('inputs.endsNextDay')
              : null,
          where:
              '${summarizeDays(s.validDays, lang, t('inputs.everyDay'), t('inputs.noDays'))}'
              ' · ${branchName(s.branchId)}',
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.xs),
            border: Border.all(color: c.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: c.hairline),
                rows[i],
              ],
            ],
          ),
        ),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            newButton,
            DashButton(
              key: const ValueKey('setup-open-shifts'),
              label: t('dawam.setupOpenShifts'),
              variant: DashButtonVariant.link,
              onPressed: () => context.go('/staff/shifts'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({
    required this.shift,
    required this.times,
    required this.span,
    required this.nextDay,
    required this.where,
    super.key,
  });

  final WorkShift shift;
  final String times;
  final String? span;
  final String? nextDay;
  final String where;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final lead = Wrap(
      spacing: Space.md,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          shift.name,
          style: DashType.bodyMedium.copyWith(color: c.textPrimary),
        ),
        Text(
          dashFigure(times),
          style: DashType.body.copyWith(color: c.textPrimary),
        ),
        if (span != null)
          Text(
            dashFigure(span!),
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
        if (nextDay != null)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.sm,
              vertical: DashMetrics.hair,
            ),
            decoration: BoxDecoration(
              color: DashTone.info.wash(c),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                DashIcon(
                  'moon-star',
                  size: IconSize.xs - 2,
                  color: DashTone.info.foreground(c),
                ),
                Text(
                  nextDay!,
                  style: DashType.smallMedium.copyWith(
                    color: DashTone.info.foreground(c),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    final trail = Text(
      where,
      style: DashType.small.copyWith(color: c.textSecondary),
    );
    return Padding(
      padding: const EdgeInsets.all(Space.md),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= DashMetrics.prose
            ? Row(
                spacing: Space.md,
                children: [
                  Expanded(child: lead),
                  trail,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.xs,
                children: [lead, trail],
              ),
      ),
    );
  }
}

// ── Step 4: rules ───────────────────────────────────────────────────────────

class SetupRulesStep extends ConsumerStatefulWidget {
  const SetupRulesStep({
    required this.settings,
    required this.canGender,
    super.key,
  });

  final AttendanceSettings settings;

  /// `hr.roster.settings`: the gender mode rides in the save.
  final bool canGender;

  @override
  ConsumerState<SetupRulesStep> createState() => _SetupRulesStepState();
}

class _SetupRulesStepState extends ConsumerState<SetupRulesStep> {
  bool _busy = false;

  SetupRules get _values => SetupRules.from(widget.settings);

  Future<void> _save() async {
    final t = ref.read(tProvider);
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .staff
          .putAttendanceSettings(
            body: _values.fullBody(canGender: widget.canGender),
          );
      if (!mounted) return;
      DashToast.success(context, t('dawam.setupRulesSaved'));
      ref.read(staffRevisionsProvider.notifier).invalidateAttendance();
      // The sidebar's own copy of the checklist (the set-up leaf leaves the
      // nav once the rules are saved).
      retrySetup(ref);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final values = _values;
    final saved = widget.settings.rulesSavedAt != null;
    final ex = PayExample(
      salary: PayExample.setupSalary,
      workingDays: values.exampleWorkingDays,
      shiftMinutes: PayExample.setupShiftMinutes,
    );
    final phone = DashBreakpoints.isPhone(context);

    Widget cell(
      String text, {
      TextAlign align = TextAlign.start,
      TextStyle? style,
      bool figure = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      child: Text(
        figure ? dashFigure(text) : text,
        textAlign: align,
        style: style ?? DashType.body.copyWith(color: c.textPrimary),
      ),
    );
    final head = DashType.smallMedium.copyWith(color: c.textSecondary);
    final hairline = BorderSide(color: c.hairline);

    final table = Semantics(
      container: true,
      label: t('staff.lateLadder'),
      child: Container(
        key: const ValueKey('setup-ladder'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(color: c.hairline),
        ),
        child: values.tiers.isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: c.muted.withValues(alpha: 0.6),
                    child: Row(
                      children: [
                        Expanded(
                          child: cell(t('dawam.setupLateBy'), style: head),
                        ),
                        Expanded(child: cell(t('staff.deduct'), style: head)),
                        Expanded(
                          child: cell(
                            t('dawam.setupOnSalary'),
                            align: TextAlign.end,
                            style: head,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(border: Border(top: hairline)),
                    child: cell(
                      t('staff.noTiers'),
                      style: DashType.body.copyWith(color: c.textSecondary),
                    ),
                  ),
                ],
              )
            : Table(
                columnWidths: const {
                  0: FlexColumnWidth(),
                  1: FlexColumnWidth(),
                  2: FlexColumnWidth(),
                },
                border: TableBorder(horizontalInside: hairline),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: c.muted.withValues(alpha: 0.6),
                    ),
                    children: [
                      cell(t('dawam.setupLateBy'), style: head),
                      cell(t('staff.deduct'), style: head),
                      cell(
                        t('dawam.setupOnSalary'),
                        align: TextAlign.end,
                        style: head,
                      ),
                    ],
                  ),
                  for (final tier in values.tiers)
                    TableRow(
                      children: [
                        cell(_range(t, tier), figure: true),
                        cell(_cost(t, f, tier)),
                        cell(
                          f.fmtMoney(tierPiastres(tier, ex)),
                          align: TextAlign.end,
                          style: DashType.bodyMedium.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
      ),
    );

    final facts = [
      t('dawam.setupAbsence', args: {'n': values.absenceDaysText}),
      values.overtimeMode == 'off'
          ? t('dawam.setupOtOff')
          : t('dawam.setupOtOn'),
      t('dawam.setupPayDay', args: {'n': values.periodStartDay}),
      t('dawam.setupGrace'),
    ];
    final factStyle = DashType.body.copyWith(color: c.textSecondary);
    final factList = phone
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.xs,
            children: [for (final s in facts) Text(s, style: factStyle)],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.xs,
            children: [
              for (var i = 0; i < facts.length; i += 2)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.lg,
                  children: [
                    Expanded(child: Text(facts[i], style: factStyle)),
                    Expanded(child: Text(facts[i + 1], style: factStyle)),
                  ],
                ),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Text(
          saved
              ? t('dawam.setupRulesAreSaved')
              : t('dawam.setupRulesSuggested'),
          style: DashType.body.copyWith(color: c.textPrimary),
        ),
        table,
        factList,
        Wrap(
          spacing: Space.md,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!saved)
              DashButton(
                key: const ValueKey('setup-save-rules'),
                label: t('dawam.setupSaveRules'),
                loading: _busy,
                onPressed: _save,
              ),
            DashButton(
              key: const ValueKey('setup-open-rules'),
              label: saved
                  ? t('dawam.setupOpenRules')
                  : t('dawam.setupAdjustRules'),
              variant: saved
                  ? DashButtonVariant.primary
                  : DashButtonVariant.outline,
              onPressed: () => context.go('/staff/rules'),
            ),
          ],
        ),
      ],
    );
  }

  String _range(Translator t, SetupTier tier) => tier.toMinutes == null
      ? t('staff.tierFromOnly', args: {'from': tier.fromMinutes})
      : t(
          'staff.tierRange',
          args: {'from': tier.fromMinutes, 'to': tier.toMinutes},
        );

  String _cost(
    Translator t,
    DashFormat f,
    SetupTier tier,
  ) => switch (tier.kind) {
    'minutes' => t('staff.tierCostMinutes', args: {'n': jsNumber(tier.value)}),
    'day_fraction' => t('staff.tierCostDay', args: {'n': jsNumber(tier.value)}),
    _ => f.fmtMoney(tier.value),
  };
}
