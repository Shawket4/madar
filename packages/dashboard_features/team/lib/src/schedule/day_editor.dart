/// One person's date on the schedule (`dawam/day-editor.tsx`,
/// TEAM-SCH-040…050): the shifts they work that day (several on a split
/// day, or a day off), each with its own from/to if the manager set one,
/// given to someone else, or the whole date put back on the standing
/// pattern. Only blocks valid on that weekday are offered, at that day's
/// times; a clash is said before anything is sent; the server decides the
/// rest and its labour-limit warnings are passed on.
///
/// The dialog reads the week's roster itself, so a change that keeps it
/// open (new times) shows the refreshed day.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Branch, DayBlock, DayView, LabourWarning, MoveShiftRequest, MoveView, PutDayRequest, PutTimesRequest, RosterPerson, RosterShift, WorkShiftBrief;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rules/night_range_field.dart';
import '../shared/attendance_errors.dart';
import '../shared/staff_query.dart';
import '../shared/team_format.dart';
import '../shared/week.dart';
import 'schedule_data.dart';
import 'schedule_grid.dart';
import 'schedule_providers.dart';

/// Opens the day editor on [person]'s [date] of the week [key] reads.
Future<void> showDayEditor(
  BuildContext context, {
  required RosterKey key,
  required RosterPerson person,
  required String date,
}) => showDashDialog<void>(
  context,
  builder: (_) => DayEditor(rosterKey: key, person: person, date: date),
);

class DayEditor extends ConsumerStatefulWidget {
  const DayEditor({
    required this.rosterKey,
    required this.person,
    required this.date,
    super.key,
  });

  final RosterKey rosterKey;
  final RosterPerson person;
  final String date;

  @override
  ConsumerState<DayEditor> createState() => _DayEditorState();
}

class _DayEditorState extends ConsumerState<DayEditor> {
  bool _busy = false;
  String? _editing;
  String _from = '';
  String _to = '';
  String? _moving;
  String? _moveTo;
  String? _adding;

  String get _employee => widget.person.employeeId;
  String get _branch => widget.rosterKey.branchId;

  /// Runs a change: its toast, the server's labour warnings, `/staff`
  /// refreshed; closes unless [close] is off. A refusal keeps it open.
  Future<void> _run(
    Future<Object?> Function() fn,
    String ok, {
    bool close = true,
  }) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final staff = ref.read(staffRevisionsProvider.notifier);
    setState(() => _busy = true);
    Object? out;
    try {
      out = await fn();
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(context, attendanceErrorText(e, t, f));
        setState(() => _busy = false);
      }
      return;
    }
    staff.invalidateStaff();
    if (!mounted) return;
    DashToast.success(context, ok);
    final warnings = switch (out) {
      DayView(:final warnings) => warnings,
      MoveView(:final to) => to.warnings,
      _ => const <LabourWarning>[],
    };
    for (final w in warnings) {
      DashToast.warning(
        context,
        t(
          'dawam.limitWarning',
          args: {
            'limit': warningLabel(t, w.kind),
            'minutes': fmtHours(t.lang, w.minutes),
            'cap': fmtHours(t.lang, w.limitMinutes),
          },
        ),
      );
    }
    setState(() {
      _busy = false;
      _editing = null;
      _moving = null;
    });
    if (close) Navigator.of(context).pop();
  }

  Future<void> _setShifts(List<DayBlock> blocks) {
    final api = ref.read(apiProvider);
    return _run(
      () => api.staff.putDay(
        body: PutDayRequest(
          employeeId: _employee,
          onDate: widget.date,
          shifts: blocks,
          branchId: _branch,
        ),
      ),
      ref.read(tProvider)('dawam.dayChanged'),
    );
  }

  Future<void> _dayOff(List<RosterShift> shifts, bool published) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    if (shifts.isNotEmpty) {
      final sep = t('common.listSeparator');
      final hint = t(
        'dawamOps.dayOffHint',
        args: {'shifts': shifts.map((s) => s.shiftName).join(sep)},
      );
      final ok = await showDashConfirm(
        context,
        title: t(
          'dawamOps.dayOffTitle',
          args: {'name': widget.person.name, 'date': f.fmtDate(widget.date)},
        ),
        description: published
            ? '$hint ${t('dawamOps.toldPublished')}'
            : hint,
        confirmLabel: t('dawam.dayOff'),
      );
      if (!ok || !mounted) return;
    }
    await _setShifts(const []);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final view = ref.watch(scheduleRosterProvider(widget.rosterKey)).value;
    final index = RosterIndex(view, _branch);
    final date = widget.date;
    final weekday = weekdayOf(date);
    final shifts = index.shiftsOf(_employee, date);
    final away = index.elsewhereOf(_employee, date);
    final ownSet = index.dateSets.containsKey(cellKey(_employee, date));
    final published =
        view?.publishedWeeks.contains(weekStartOf(date)) ?? false;
    final staff = view?.staff ?? const <RosterPerson>[];
    final sep = t('common.listSeparator');

    final offered = [
      for (final w in blocksOn(index.templates, weekday))
        if (!shifts.any((s) => s.workShiftId == w.id)) w,
    ];
    TimedBlock timed(RosterShift s) =>
        timedOf(s.shiftName, s.startTime, s.endTime);
    List<TimedBlock> clashOfBlock(WorkShiftBrief w) {
      final at = blockTimesOn(w, weekday);
      return clashesWith([
        for (final s in shifts) timed(s),
      ], timedOf(w.name, at.start, at.end));
    }

    final adding = offered.where((w) => w.id == _adding).firstOrNull;
    final addClash = adding == null ? const <TimedBlock>[] : clashOfBlock(adding);
    final editClash =
        _editing != null && _from.isNotEmpty && _to.isNotEmpty
        ? clashesWith([
            for (final s in shifts)
              if (s.workShiftId != _editing) timed(s),
          ], timedOf('', _from, _to))
        : const <TimedBlock>[];
    final moving = shifts.where((s) => s.workShiftId == _moving).firstOrNull;
    final moveClash = moving != null && _moveTo != null
        ? clashesWith([
            for (final s in index.shiftsOf(_moveTo!, date)) timed(s),
          ], timed(moving))
        : const <TimedBlock>[];
    final moveToName = staff
        .where((p) => p.employeeId == _moveTo)
        .map((p) => p.name)
        .firstOrNull;
    final names = {
      for (final b in ref.watch(branchesProvider).value ?? const <Branch>[])
        b.id: b.name,
    };
    String branchOf(String id, [String? name]) =>
        name != null && name.isNotEmpty
        ? name
        : names[id] ?? t('dawamOps.otherBranch');
    final elsewhere = [
      for (final s in shifts)
        if (s.branchId != _branch) '${s.shiftName} (${branchOf(s.branchId)})',
      for (final s in away)
        '${s.shiftName} (${branchOf(s.branchId, s.branchName)})',
    ];
    String clashText(List<TimedBlock> list) => list
        .map((b) => '${b.name} ${ltr('${b.start}–${b.end}')}')
        .join(sep);

    final api = ref.read(apiProvider);
    final muted = DashType.small.copyWith(color: c.textSecondary);

    Widget labelled(String label, Widget field) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        Text(label, style: DashType.bodyMedium.copyWith(color: c.textPrimary)),
        field,
      ],
    );

    Widget shiftItem(RosterShift s) {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      return Container(
        key: ValueKey('day-shift-${s.workShiftId}'),
        padding: const EdgeInsets.all(Space.sm + 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        s.shiftName,
                        style: DashType.bodyMedium.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      ShiftTimes(
                        start: s.startTime,
                        end: s.endTime,
                        crossesMidnight: s.crossesMidnight,
                      ),
                      if (s.timesEdited) DashBadge(t('dawam.edited')),
                      if (s.changed)
                        _OutlineBadge(t('dawam.changedAfterPublish')),
                    ],
                  ),
                ),
                DashIconButton(
                  icon: 'clock',
                  semanticLabel: t(
                    'dawam.editTimesOf',
                    args: {'shift': s.shiftName},
                  ),
                  onPressed: () => setState(() {
                    _editing = s.workShiftId;
                    _from = hhmm(s.startTime);
                    _to = hhmm(s.endTime);
                  }),
                ),
                Transform.flip(
                  flipX: rtl,
                  child: DashIconButton(
                    icon: 'arrow-right-left',
                    semanticLabel: t(
                      'dawam.moveShiftOf',
                      args: {'shift': s.shiftName},
                    ),
                    onPressed: () => setState(() {
                      _moving = s.workShiftId;
                      _moveTo = null;
                    }),
                  ),
                ),
                DashIconButton(
                  icon: 'trash-2',
                  semanticLabel: t(
                    'dawam.removeShiftOf',
                    args: {'shift': s.shiftName},
                  ),
                  onPressed: _busy
                      ? null
                      : () => _setShifts([
                          for (final x in shifts)
                            if (x.workShiftId != s.workShiftId) blockOf(x),
                        ]),
                ),
              ],
            ),
            if (_editing == s.workShiftId) ...[
              NightRangeField(
                key: const Key('day-times'),
                start: _from,
                end: _to,
                onChanged: (a, b) => setState(() {
                  _from = a;
                  _to = b;
                }),
                startLabel: t('dawam.from'),
                endLabel: t('dawam.to'),
                groupLabel: t('dawam.editTimesOf', args: {'shift': s.shiftName}),
                lang: t.lang,
                sameTimeText: t('inputs.sameTime'),
                endsNextDayText: t('inputs.endsNextDay'),
                nextDayShortText: t('inputs.nextDayShort'),
                longOvernightText: (l) =>
                    t('inputs.longOvernight', args: {'length': l}),
                didYouMeanText: (time) =>
                    t('inputs.didYouMean', args: {'time': time}),
              ),
              if (editClash.isNotEmpty)
                _ClashNote(
                  t('dawamOps.clashTimes', args: {'with': clashText(editClash)}),
                ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  if (s.timesEdited)
                    DashButton(
                      label: t('dawam.blockTimes'),
                      variant: DashButtonVariant.ghost,
                      size: DashButtonSize.compact,
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => api.staff.putTimes(
                                body: PutTimesRequest(
                                  employeeId: _employee,
                                  onDate: date,
                                  workShiftId: s.workShiftId,
                                  explicitNulls: const {
                                    'start_time',
                                    'end_time',
                                  },
                                ),
                              ),
                              t('dawam.timesReset'),
                              close: false,
                            ),
                    ),
                  DashButton(
                    label: t('dawam.saveTimes'),
                    size: DashButtonSize.compact,
                    onPressed:
                        _busy ||
                            DashTime.toHHMM(_from).isEmpty ||
                            DashTime.toHHMM(_to).isEmpty ||
                            _from == _to ||
                            editClash.isNotEmpty
                        ? null
                        : () => _run(
                            () => api.staff.putTimes(
                              body: PutTimesRequest(
                                employeeId: _employee,
                                onDate: date,
                                workShiftId: s.workShiftId,
                                startTime: '${DashTime.toHHMM(_from)}:00',
                                endTime: '${DashTime.toHHMM(_to)}:00',
                              ),
                            ),
                            t('dawam.timesSaved'),
                            close: false,
                          ),
                  ),
                ],
              ),
            ],
            if (_moving == s.workShiftId) ...[
              labelled(
                t('dawam.giveTo'),
                DashSelect<String>(
                  key: const Key('day-give-to'),
                  value: _moveTo,
                  placeholder: t('staff.pickEmployee'),
                  semanticLabel: t('dawam.giveTo'),
                  options: [
                    for (final p in staff)
                      if (p.employeeId != _employee)
                        DashOption(value: p.employeeId, label: p.name),
                  ],
                  onChanged: (v) => setState(() => _moveTo = v),
                ),
              ),
              if (moveClash.isNotEmpty)
                _ClashNote(
                  t(
                    'dawamOps.clashMove',
                    args: {
                      'name': moveToName ?? '',
                      'with': clashText(moveClash),
                    },
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: DashButton(
                  label: t('dawam.move'),
                  size: DashButtonSize.compact,
                  onPressed: _busy || _moveTo == null || moveClash.isNotEmpty
                      ? null
                      : () => _run(
                          () => api.staff.moveShift(
                            body: MoveShiftRequest(
                              employeeId: _employee,
                              toEmployeeId: _moveTo!,
                              onDate: date,
                              workShiftId: s.workShiftId,
                            ),
                          ),
                          t('dawam.shiftMoved'),
                        ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        if (elsewhere.isNotEmpty)
          Semantics(
            container: true,
            child: Container(
              key: const Key('day-elsewhere'),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              decoration: BoxDecoration(
                color: c.muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(Radii.xs),
                border: Border.all(color: c.hairline),
              ),
              child: Text(
                t('dawamOps.alsoElsewhere', args: {'shifts': elsewhere.join(sep)}),
                style: DashType.body.copyWith(color: c.textPrimary),
              ),
            ),
          ),
        Semantics(
          container: true,
          label: t('dawam.shiftsThatDay'),
          explicitChildNodes: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              if (shifts.isEmpty)
                Text(t('dawam.off'), style: DashType.body.copyWith(color: c.textSecondary)),
              for (final s in shifts) shiftItem(s),
            ],
          ),
        ),
        labelled(
          t('dawam.addShift'),
          DashSelect<String>(
            key: const Key('day-add-shift'),
            value: _adding,
            placeholder: offered.isEmpty
                ? t('dawam.noShiftThatDay')
                : t('dawam.pickShift'),
            semanticLabel: t('dawam.addShift'),
            options: [
              for (final w in offered)
                () {
                  final at = blockTimesOn(w, weekday);
                  final clash = clashOfBlock(w);
                  return DashOption(
                    value: w.id,
                    label: '${w.name} · ${ltr('${at.start}–${at.end}')}',
                    hint: clash.isEmpty
                        ? null
                        : t(
                            'dawamOps.overlaps',
                            args: {
                              'with': clash.map((b) => b.name).join(', '),
                            },
                          ),
                  );
                }(),
            ],
            onChanged: (v) => setState(() => _adding = v),
          ),
        ),
        if (addClash.isNotEmpty)
          _ClashNote(t('dawamOps.clashAdd', args: {'with': clashText(addClash)})),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: DashButton(
            label: t('dawam.add'),
            icon: 'plus',
            variant: DashButtonVariant.outline,
            size: DashButtonSize.compact,
            onPressed: _busy || adding == null || addClash.isNotEmpty
                ? null
                : () => _setShifts([
                    for (final s in shifts) blockOf(s),
                    DayBlock(
                      workShiftId: adding.id,
                      explicitNulls: const {'start_time', 'end_time'},
                    ),
                  ]),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.sm,
          children: [
            DashIcon('triangle-alert', size: IconSize.xs, color: c.textSecondary),
            Expanded(child: Text(t('dawam.dayEditorWarn'), style: muted)),
          ],
        ),
        if (ownSet) Text(t('dawam.backToPatternHint'), style: muted),
      ],
    );

    final hint = t('dawam.dayEditorHint');
    return DashSurface(
      title: t(
        'dawam.dayEditorTitle',
        args: {'name': widget.person.name, 'date': f.fmtDate(date)},
      ),
      description: published ? '$hint ${t('dawamOps.toldPublished')}' : hint,
      body: body,
      actions: [
        if (ownSet)
          DashButton(
            label: t('dawam.backToPattern'),
            icon: 'rotate-ccw',
            variant: DashButtonVariant.outline,
            onPressed: _busy
                ? null
                : () => _run(
                    () => api.staff.resetDay(
                      employeeId: _employee,
                      onDate: date,
                      branchId: _branch,
                    ),
                    t('dawam.backToPatternDone'),
                  ),
          )
        else
          Center(
            widthFactor: 1,
            child: Text(t('dawam.followsPattern'), style: muted),
          ),
        DashButton(
          label: t('dawam.dayOff'),
          variant: DashButtonVariant.outline,
          onPressed: _busy ? null : () => _dayOff(shifts, published),
        ),
      ],
    );
  }
}

class _OutlineBadge extends StatelessWidget {
  const _OutlineBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: c.hairline),
      ),
      child: Text(
        label,
        style: DashType.smallMedium.copyWith(color: c.textPrimary),
      ),
    );
  }
}

/// A clash said before saving: the server would refuse it anyway, so the
/// button waits (`role="alert"`).
class _ClashNote extends StatelessWidget {
  const _ClashNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final color = context.madarColors.errorText;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        key: const Key('day-clash'),
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.xs + 2,
        children: [
          DashIcon('triangle-alert', size: IconSize.xs, color: color),
          Expanded(
            child: Text(
              text,
              style: DashType.smallMedium.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
