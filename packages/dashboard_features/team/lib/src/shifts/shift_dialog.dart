/// One shift block (`staff/work-shift-dialog.tsx` `WorkShiftDialog`,
/// TEAM-SHF-011…024): its branch, its default times, the weekdays it may be
/// rostered on and its own times on some of them, and its own overtime
/// rates on top of the branch's rules. The server decides what follows from
/// these: whether a time runs into the next day, whether the block is past
/// the labour presence cap (a warning, never a refusal), and whether a
/// weekday can be taken away while people are rostered on it.
///
/// Opened from the Work shifts page (new and edit) and from Set-up step 3
/// (new, TEAM-SET-038).
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart' show Branch, WorkShift;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/attendance_errors.dart';
import '../shared/staff_query.dart';
import '../shared/team_format.dart';
import '../shared/time_range_field.dart';
import '../shared/week.dart';
import 'shift_form.dart';
import 'shift_inputs.dart';

/// Opens the shift dialog: [shift] to edit, null for a new block.
/// [wholeBusiness]: may this person make the block business-wide (the
/// right at every branch); without it a new block starts at the first of
/// [branches].
Future<void> showShiftDialog(
  BuildContext context, {
  required List<Branch> branches,
  required bool wholeBusiness,
  WorkShift? shift,
}) => showDashDialog<void>(
  context,
  width: DashMetrics.dialogWide,
  builder: (_) => WorkShiftDialog(
    shift: shift,
    branches: branches,
    wholeBusiness: wholeBusiness,
  ),
);

class WorkShiftDialog extends ConsumerStatefulWidget {
  const WorkShiftDialog({
    required this.shift,
    required this.branches,
    required this.wholeBusiness,
    super.key,
  });

  final WorkShift? shift;
  final List<Branch> branches;
  final bool wholeBusiness;

  @override
  ConsumerState<WorkShiftDialog> createState() => _WorkShiftDialogState();
}

class _WorkShiftDialogState extends ConsumerState<WorkShiftDialog> {
  late WorkShift? _shift = widget.shift;
  late ShiftValues _v;
  late bool _dayTimesOpen;
  late bool _moreOpen;

  /// The person changed something: a background refresh no longer re-seeds.
  bool _dirty = false;

  /// Save was pressed once: problems show, and re-check on every change.
  bool _submitted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _seed(widget.shift);
  }

  void _seed(WorkShift? s) {
    _shift = s;
    _v = ShiftValues.of(s);
    // Without the right everywhere a new block starts at a branch.
    final branches = _branches(ref.read(branchesProvider));
    if (!widget.wholeBusiness &&
        _v.branchId == wholeBusiness &&
        branches.isNotEmpty) {
      _v.branchId = branches.first.id;
    }
    _dayTimesOpen = _v.hasDayTimes;
    _moreOpen = _v.hasOptionalRates;
  }

  /// The live branch list; [WorkShiftDialog.branches] until it loads.
  List<Branch> _branches(AsyncValue<List<Branch>?> live) =>
      live.value ?? widget.branches;

  void _edit(VoidCallback change) => setState(() {
    change();
    _dirty = true;
  });

  Future<void> _save() async {
    final t = ref.read(tProvider);
    final problems = shiftProblems(_v, t.call);
    setState(() => _submitted = true);
    if (problems.isNotEmpty) {
      // Never silent: open whatever section holds the problem, and say so.
      setState(() {
        if (problems.keys.any((k) => k.startsWith('day:'))) {
          _dayTimesOpen = true;
        }
        if (problems.keys.any(moreFields.contains)) _moreOpen = true;
      });
      DashToast.error(context, t('staff.fixShiftErrors'));
      return;
    }
    setState(() => _busy = true);
    final api = ref.read(apiProvider);
    final staff = ref.read(staffRevisionsProvider.notifier);
    final f = ref.read(formatProvider);
    final shift = _shift;
    try {
      final body = shiftBody(_v);
      final saved = shift == null
          ? await api.staff.createWorkShift(body: body)
          : await api.staff.updateWorkShift(id: shift.id, body: body);
      // The Dawam roster lists the blocks too: all of /staff.
      staff.invalidateStaff();
      if (!mounted) return;
      DashToast.success(context, t('staff.shiftSaved'));
      if (saved.overPresenceCap ?? false) {
        DashToast.warning(context, t('staff.overPresenceCap'));
      }
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, attendanceErrorText(e, t, f));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final editing = widget.shift;
    final branches = _branches(ref.watch(branchesProvider));
    // The web re-seeds when the branch count changes (its reset effect keyed
    // on branches.length); here only while the form is untouched.
    ref.listen(branchesProvider.select((b) => b.value?.length), (_, _) {
      if (!_dirty && !_busy) setState(() => _seed(_shift));
    });
    if (editing != null) {
      // A refresh that lands before the person edits re-seeds the form, so
      // a copy taken once never saves stale values over newer ones.
      ref.listen(staffWorkShiftsProvider, (_, next) {
        final fresh = next.value?.firstWhereOrNull((s) => s.id == editing.id);
        if (fresh == null || _dirty || _busy) return;
        if (fresh.updatedAt != _shift?.updatedAt) setState(() => _seed(fresh));
      });
    }
    final problems = _submitted
        ? shiftProblems(_v, t.call)
        : const <String, String>{};
    final twoColumns = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    Widget pair(Widget a, Widget b) => twoColumns
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.lg,
            children: [
              Expanded(child: a),
              Expanded(child: b),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.lg,
            children: [a, b],
          );
    String dayLabel(int dow) => t(weekdayKeys[dow]);
    String presetLabel(ShiftPreset p) => t(p.labelKey);

    Widget number(
      String field,
      String label,
      double? value,
      void Function(double?) set, {
      String? description,
      bool duration = true,
      List<double> presets = const [],
      double step = 5,
      bool allowEmpty = false,
      String? emptyLabel,
    }) {
      final unit = t('inputs.unitMin');
      return DashFormField<double?>(
        label: label,
        description: description,
        errorText: problems[field],
        builder: (context, invalid) => DashNumberInput(
          value: value,
          onChanged: (n) => _edit(() => set(n)),
          // The web's `<form>` submits on Enter.
          onSubmitted: (_) => _save(),
          step: duration ? step : 0.05,
          decimals: duration ? 0 : 2,
          stepper: duration,
          center: duration,
          suffix: duration ? unit : null,
          unitWord: duration ? unit : null,
          prefix: duration ? null : '×',
          presets: presets,
          presetLabel: (p) =>
              p >= 60 ? formatSpan(p, lang) : '${f.fmtNumber(p)} $unit',
          allowEmpty: allowEmpty,
          emptyLabel: emptyLabel,
          // Minutes past an hour read back as hours ("= 1 h 30 min").
          hint: duration && value != null && value >= 60
              ? '= ${formatSpan(value, lang)}'
              : null,
          invalid: invalid,
          semanticLabel: label,
        ),
      );
    }

    Widget switchBox(
      String label,
      String description,
      bool value,
      ValueChanged<bool> onChanged,
    ) => Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: c.hairline),
      ),
      child: DashSwitchField(
        label: label,
        description: description,
        value: value,
        onChanged: (v) => _edit(() => onChanged(v)),
      ),
    );

    final ownDays = [
      for (final d in weekOrder)
        if (_v.validDays.contains(d) &&
            ((_v.dayTimes[d]?.start.isNotEmpty ?? false) ||
                (_v.dayTimes[d]?.end.isNotEmpty ?? false)))
          d,
    ];
    final validInOrder = [
      for (final d in weekOrder)
        if (_v.validDays.contains(d)) d,
    ];

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        if (_shift?.overPresenceCap ?? false)
          Semantics(
            liveRegion: true,
            child: Container(
              key: const ValueKey('shift-over-cap'),
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: DashTone.warning.wash(c),
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.sm,
                children: [
                  DashIcon(
                    'triangle-alert',
                    size: IconSize.sm,
                    color: DashTone.warning.foreground(c),
                  ),
                  Expanded(
                    child: Text(
                      t('staff.overPresenceCap'),
                      style: DashType.body.copyWith(
                        color: DashTone.warning.foreground(c),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (editing == null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.xs + DashMetrics.hair,
            children: [
              Text(
                t('staff.startFrom'),
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              Wrap(
                spacing: Space.xs + DashMetrics.hair,
                runSpacing: Space.xs + DashMetrics.hair,
                children: [
                  for (final p in shiftPresets)
                    _PresetButton(
                      label: presetLabel(p),
                      times:
                          '${f.fmtWireTime(p.start)} – ${f.fmtWireTime(p.end)}',
                      on: _v.start == p.start && _v.end == p.end,
                      onTap: () => _edit(() {
                        if (presetMayRename(
                          _v.name,
                          shiftPresets.map(presetLabel),
                        )) {
                          _v.name = presetLabel(p);
                        }
                        _v
                          ..start = p.start
                          ..end = p.end;
                      }),
                    ),
                ],
              ),
            ],
          ),
        DashTextField(
          label: t('staff.shiftName'),
          placeholder: t('staff.shiftNamePlaceholder'),
          value: _v.name,
          errorText: problems['name'],
          onChanged: (v) => _edit(() => _v.name = v),
          onSubmitted: (_) => _save(),
        ),
        DashSelectField<String>(
          label: t('staff.shiftBranch'),
          description: t('staff.shiftBranchHint'),
          value: _v.branchId,
          options: [
            if (widget.wholeBusiness || _v.branchId == wholeBusiness)
              DashOption(value: wholeBusiness, label: t('staff.wholeBusiness')),
            for (final b in branches) DashOption(value: b.id, label: b.name),
          ],
          onChanged: (v) => _edit(() => _v.branchId = v),
        ),
        TeamTimeRangeField(
          start: _v.start,
          end: _v.end,
          startLabel: t('staff.startTime'),
          endLabel: t('staff.endTime'),
          error: problems['start'] ?? problems['end'],
          onChanged: (s, e) => _edit(() {
            _v
              ..start = s
              ..end = e;
          }),
        ),
        DashFormField<List<int>>(
          label: t('staff.validDays'),
          errorText: problems['days'],
          builder: (context, invalid) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: ShiftWeekdayPicker(
              value: _v.validDays,
              semanticLabel: t('staff.validDays'),
              invalid: invalid,
              onChanged: (d) => _edit(() => _v.validDays = d),
            ),
          ),
        ),
        ShiftCollapsible(
          key: const ValueKey('shift-day-times'),
          title: t('staff.dayTimes'),
          summary: ownDays.isEmpty
              ? t('staff.dayTimesNone')
              : t(
                  'staff.dayTimesSome',
                  args: {
                    'days': ownDays
                        .map(dayLabel)
                        .join(t('common.listSeparator')),
                  },
                ),
          open: _dayTimesOpen,
          onToggle: () => setState(() => _dayTimesOpen = !_dayTimesOpen),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              Text(
                t('staff.dayTimesHintV2'),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
              for (final dow in validInOrder)
                Row(
                  key: ValueKey('shift-day-$dow'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.sm,
                  children: [
                    SizedBox(
                      width: Space.xxl * 2 + Space.sm,
                      child: Padding(
                        padding: const EdgeInsets.only(top: Space.md),
                        child: Text(
                          dayLabel(dow),
                          style: DashType.bodyMedium.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TeamTimeRangeField(
                        start: _v.dayTimes[dow]?.start ?? '',
                        end: _v.dayTimes[dow]?.end ?? '',
                        optional: true,
                        hideLabels: true,
                        startLabel: t(
                          'staff.dayStart',
                          args: {'day': dayLabel(dow)},
                        ),
                        endLabel: t(
                          'staff.dayEnd',
                          args: {'day': dayLabel(dow)},
                        ),
                        error: problems['day:$dow'],
                        onChanged: (s, e) => _edit(
                          () => _v.dayTimes = {
                            ..._v.dayTimes,
                            dow: (start: s, end: e),
                          },
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        pair(
          number(
            'grace',
            t('staff.graceMinutesV2'),
            _v.grace,
            (n) => _v.grace = n,
            description: t('staff.graceHint'),
            presets: const [0, 5, 10, 15, 30],
          ),
          number(
            'break',
            t('staff.breakMinutesV2'),
            _v.breakMinutes,
            (n) => _v.breakMinutes = n,
            presets: const [0, 15, 30, 60],
          ),
        ),
        switchBox(
          t('staff.paidBreak'),
          t('staff.paidBreakHint'),
          _v.paidBreak,
          (v) => _v.paidBreak = v,
        ),
        ShiftCollapsible(
          key: const ValueKey('shift-more'),
          title: t('staff.moreShiftSettings'),
          summary: t('staff.moreShiftSettingsHint'),
          open: _moreOpen,
          onToggle: () => setState(() => _moreOpen = !_moreOpen),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.lg,
            children: [
              pair(
                number(
                  'otThreshold',
                  t('staff.otThreshold'),
                  _v.otThreshold,
                  (n) => _v.otThreshold = n,
                  description: t('staff.otThresholdHint'),
                  presets: const [0, 15, 30],
                ),
                number(
                  'otMultiplier',
                  t('staff.otMultiplier'),
                  _v.otMultiplier,
                  (n) => _v.otMultiplier = n,
                  duration: false,
                ),
              ),
              pair(
                number(
                  'otDay',
                  t('staff.otDayMultiplier'),
                  _v.otDay,
                  (n) => _v.otDay = n,
                  duration: false,
                  allowEmpty: true,
                  emptyLabel: t('staff.branchRate'),
                  description: t('staff.otRateHint'),
                ),
                number(
                  'otNight',
                  t('staff.otNightMultiplier'),
                  _v.otNight,
                  (n) => _v.otNight = n,
                  duration: false,
                  allowEmpty: true,
                  emptyLabel: t('staff.branchRate'),
                  description: t('staff.otRateHint'),
                ),
              ),
              pair(
                number(
                  'halfDay',
                  t('staff.halfDayThreshold'),
                  _v.halfDay,
                  (n) => _v.halfDay = n,
                  step: 30,
                  allowEmpty: true,
                  emptyLabel: t('staff.halfDayDefault'),
                ),
                number(
                  'checkin',
                  t('staff.checkinWindow'),
                  _v.checkin,
                  (n) => _v.checkin = n,
                  step: 15,
                  presets: const [30, 60, 120],
                ),
              ),
            ],
          ),
        ),
        switchBox(
          t('staff.active'),
          t('staff.activeShiftHint'),
          _v.isActive,
          (v) => _v.isActive = v,
        ),
      ],
    );

    return DashSurface(
      title: editing == null ? t('staff.newShift') : t('staff.editShift'),
      description: t('staff.shiftDialogHintV2'),
      body: body,
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.ghost,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          key: const ValueKey('shift-save'),
          label: t('common.save'),
          loading: _busy,
          onPressed: _busy ? null : _save,
        ),
      ],
    );
  }
}

/// A common shift to start from: its name and its times; pressed when the
/// form's times are its own.
class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.label,
    required this.times,
    required this.on,
    required this.onTap,
  });

  final String label;
  final String times;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final radius = BorderRadius.circular(Radii.xs);
    return DashPressable(
      onTap: onTap,
      checked: on,
      pressScale: false,
      semanticLabel: '$label $times',
      excludeChildSemantics: true,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.xs + DashMetrics.hair,
        ),
        foregroundDecoration: dashFocusRing(context, s, radius),
        decoration: BoxDecoration(
          color: on
              ? c.accent.withValues(alpha: 0.05)
              : (s.highlighted ? c.hover : null),
          borderRadius: radius,
          border: Border.all(color: on ? c.accent : c.input),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
            Text(
              times,
              style: DashType.small.copyWith(
                color: c.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
