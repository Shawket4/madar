/// The Attendance page's two forms (`staff/attendance-dialogs.tsx`): add a
/// record by hand (TEAM-ATT-023…033), correct one (TEAM-ATT-035…037). Every
/// time is typed and shown on the BRANCH's clock (AT-1), with the zone named
/// under the times. Validated on Save, then again on every change.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        AttendanceRecord,
        Branch,
        CorrectRecordRequest,
        Employee,
        ManualRecordRequest,
        WorkShift;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/attendance_errors.dart';
import '../shared/staff_query.dart';
import '../shared/team_format.dart';
import '../shared/team_util.dart';
import '../shared/week.dart' show addDays;
import 'attendance_data.dart';
import 'attendance_providers.dart';

/// No work shift (`NONE`).
const String _none = '__none__';

/// "From the times": the server derives the status (`DERIVED`).
const String _derived = '__derived__';

/// The time half of a punch (`minmax(0, 8.5rem)`).
const double _timeWidth = 136;

/// Opens "Add record"; [branchId] is the scope bar's branch.
Future<void> showAttendanceAddDialog(BuildContext context, String? branchId) =>
    showDashDialog<void>(
      context,
      builder: (_) => AttendanceAddDialog(branchId: branchId),
    );

/// Opens "Correct record" on [record], as the page's [query] lists it.
Future<void> showAttendanceCorrectDialog(
  BuildContext context,
  AttendanceRecord record,
  AttendanceQuery query,
) => showDashDialog<void>(
  context,
  builder: (_) => AttendanceCorrectDialog(record: record, query: query),
);

/// The zone of [branchId], falling back to the page's (`useBranchZone`).
String _branchZone(WidgetRef ref, String? branchId) {
  final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
  for (final b in branches) {
    if (b.id == branchId && b.timezone.isNotEmpty) return b.timezone;
  }
  return ref.watch(activeTimezoneProvider);
}

// ── Add a record by hand ─────────────────────────────────────────────────

/// Hand-entered attendance: the escape hatch for a day the app never saw.
class AttendanceAddDialog extends ConsumerStatefulWidget {
  const AttendanceAddDialog({required this.branchId, super.key});

  /// The single branch in scope, or null for every branch.
  final String? branchId;

  @override
  ConsumerState<AttendanceAddDialog> createState() =>
      _AttendanceAddDialogState();
}

class _AttendanceAddDialogState extends ConsumerState<AttendanceAddDialog> {
  String _employee = '';
  late String _date = teamTodayIsoOf(ref);
  String _status = _derived;
  String _shift = _none;
  String _branch = '';
  String _in = '';
  String _out = '';
  String _reason = '';
  bool _submitted = false;
  String? _branchError;
  bool _busy = false;

  Map<String, String> _problems(Translator t) => {
    if (_employee.isEmpty) 'employee': t('staff.pickEmployee'),
    if (!isYmd(_date)) 'date': t('staff.pickDate'),
    if (!outAfterIn(_in, _out)) 'out': t('staff.outBeforeIn'),
    if (_reason.trim().isEmpty) 'reason': t('staff.reasonRequired'),
    // The time field says it; the form only refuses (never sends a blank).
    if (!stampReadable(_in) || !stampReadable(_out)) 'time': '',
  };

  Future<void> _save(String? recordBranch, String tz) async {
    final t = ref.read(tProvider);
    if (_problems(t).isNotEmpty) {
      setState(() => _submitted = true);
      return;
    }
    if (recordBranch == null) {
      setState(() {
        _submitted = true;
        _branchError = t('dawam.pickBranch');
      });
      return;
    }
    setState(() {
      _submitted = true;
      _busy = true;
    });
    final f = ref.read(formatProvider);
    final staff = ref.read(staffRevisionsProvider.notifier);
    try {
      await ref
          .read(apiProvider)
          .staff
          .createManualRecord(
            body: ManualRecordRequest(
              employeeId: _employee,
              branchId: recordBranch,
              businessDate: _date,
              workShiftId: _shift == _none ? null : _shift,
              checkInAt: fromZonedInput(_in, tz),
              checkOutAt: fromZonedInput(_out, tz),
              status: _status == _derived ? null : _status,
              reason: _reason.trim(),
              explicitNulls: const {
                'work_shift_id',
                'check_in_at',
                'check_out_at',
                'status',
              },
            ),
          );
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, attendanceErrorText(e, t, f));
      setState(() => _busy = false);
      return;
    }
    staff.invalidateAttendance();
    if (!mounted) return;
    DashToast.success(context, t('staff.recordAdded'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final employees =
        ref.watch(staffActiveEmployeesProvider).value ?? const <Employee>[];
    final shifts =
        ref.watch(staffWorkShiftsProvider).value ?? const <WorkShift>[];
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];

    // With every branch in scope, the record's branch is the person's: their
    // only one, or the one picked among theirs.
    Employee? person;
    for (final e in employees) {
      if (e.id == _employee) person = e;
    }
    final theirs = person?.branchIds ?? const <String>[];
    final recordBranch =
        widget.branchId ??
        (theirs.length == 1
            ? theirs.first
            : theirs.contains(_branch)
            ? _branch
            : null);
    final askBranch = widget.branchId == null && theirs.length > 1;
    final tz = _branchZone(ref, recordBranch);

    // The picked day and the 40 after it: a colleague covering the picked
    // shift refuses its owner's clock-in (D1); a record there in an approved
    // or paid month closes the day too (months close in order).
    final validDate = isYmd(_date);
    final ahead = validDate
        ? ref.watch(
            attendanceListProvider(attendanceWindow(_date, addDays(_date, 40))),
          )
        : null;
    final aheadRows = ahead?.value ?? const <AttendanceRecord>[];
    final monthClosed = aheadRows.any(
      (r) => r.monthClosed == true && r.businessDate.compareTo(_date) >= 0,
    );
    final coverer = _employee.isNotEmpty && validDate && _shift != _none
        ? coveredBy(aheadRows, _employee, _date, workShiftId: _shift)
        : null;
    final coverBlocks = coverer != null && _in.isNotEmpty;

    final problems = _submitted ? _problems(t) : const <String, String>{};
    final branchName = {for (final b in branches) b.id: b.name};

    final date = DashDateFormField(
      label: t('staff.date'),
      placeholder: t('staff.pickDate'),
      value: dashParseYmd(_date),
      today: dashParseYmd(teamTodayIsoOf(ref)),
      errorText: problems['date'],
      onChanged: (d) => setState(() => _date = dashYmd(d)),
    );
    final status = DashSelectField<String>(
      label: t('staff.attendanceStatus'),
      value: _status,
      options: [
        DashOption(value: _derived, label: t('staff.statusFromTimes')),
        for (final s in attendanceStatuses)
          DashOption(value: s, label: attendanceStatusText(t, s)),
      ],
      onChanged: (v) => setState(() => _status = v),
    );

    return DashSurface(
      title: t('staff.addRecord'),
      description: t('staff.addRecordHint'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          DashSelectField<String>(
            label: t('staff.employee'),
            placeholder: t('staff.pickEmployee'),
            value: _employee.isEmpty ? null : _employee,
            errorText: problems['employee'],
            options: [
              for (final e in employees) DashOption(value: e.id, label: e.name),
            ],
            onChanged: (v) => setState(() => _employee = v),
          ),
          if (askBranch)
            DashSelectField<String>(
              label: t('dawam.branch'),
              placeholder: t('dawam.pickBranch'),
              value: _branch.isEmpty ? null : _branch,
              errorText: _branchError,
              options: [
                for (final id in theirs)
                  DashOption(value: id, label: branchName[id] ?? id),
              ],
              onChanged: (v) => setState(() {
                _branch = v;
                _branchError = null;
              }),
            )
          else if (_branchError != null)
            _FormError(_branchError!),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(child: date),
              Expanded(child: status),
            ],
          ),
          DashSelectField<String>(
            label: t('staff.workShift'),
            value: _shift,
            options: [
              DashOption(value: _none, label: t('staff.unscheduled')),
              // The record's branch's blocks and business-wide ones only.
              for (final s in shifts)
                if (s.branchId == null || s.branchId == recordBranch)
                  DashOption(value: s.id, label: s.name),
            ],
            onChanged: (v) => setState(() => _shift = v),
          ),
          _TimesFields(
            tz: tz,
            checkIn: _in,
            checkOut: _out,
            outError: problems['out'],
            onIn: (v) => setState(() => _in = v),
            onOut: (v) => setState(() => _out = v),
          ),
          if (coverer != null)
            _DashedNote(t('dawam.coveredByHint', args: {'name': coverer})),
          if (monthClosed) _DashedNote(t('staff.dayMonthClosed')),
          DashTextField(
            label: t('staff.reason'),
            placeholder: t('staff.reasonPlaceholder'),
            value: _reason,
            errorText: problems['reason'],
            onChanged: (v) => setState(() => _reason = v),
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.ghost,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          label: t('common.save'),
          loading: _busy,
          onPressed: _busy || coverBlocks || monthClosed
              ? null
              : () => _save(recordBranch, tz),
        ),
      ],
    );
  }
}

// ── Correct a record ─────────────────────────────────────────────────────

typedef _Seed = ({String checkIn, String checkOut, String status});

/// Correct an existing record. The server re-derives late, overtime and the
/// status from the new stamps; only what changed is sent.
class AttendanceCorrectDialog extends ConsumerStatefulWidget {
  const AttendanceCorrectDialog({
    required this.record,
    required this.query,
    super.key,
  });

  /// The record as the page showed it when Correct was tapped.
  final AttendanceRecord record;

  /// The page's read: a background refresh re-seeds the form until edited.
  final AttendanceQuery query;

  @override
  ConsumerState<AttendanceCorrectDialog> createState() =>
      _AttendanceCorrectDialogState();
}

class _AttendanceCorrectDialogState
    extends ConsumerState<AttendanceCorrectDialog> {
  _Seed? _initial;
  String _in = '';
  String _out = '';
  String _status = 'present';
  String _reason = '';
  bool _edited = false;
  bool _submitted = false;
  bool _busy = false;

  Map<String, String> _problems(Translator t) => {
    if (!outAfterIn(_in, _out)) 'out': t('staff.outBeforeIn'),
    if (_reason.trim().isEmpty) 'reason': t('staff.reasonRequired'),
    // The time field says it; the form only refuses (never sends a blank).
    if (!stampReadable(_in) || !stampReadable(_out)) 'time': '',
  };

  void _edit(VoidCallback change) => setState(() {
    change();
    _edited = true;
  });

  Future<void> _save(AttendanceRecord record, _Seed initial, String tz) async {
    final t = ref.read(tProvider);
    if (_problems(t).isNotEmpty) {
      setState(() => _submitted = true);
      return;
    }
    setState(() {
      _submitted = true;
      _busy = true;
    });
    final f = ref.read(formatProvider);
    final staff = ref.read(staffRevisionsProvider.notifier);
    try {
      await ref
          .read(apiProvider)
          .staff
          .correctRecord(
            id: record.id,
            body: CorrectRecordRequest(
              // Untouched: kept by the server.
              checkInAt: _in != initial.checkIn
                  ? fromZonedInput(_in, tz)
                  : null,
              checkOutAt: _out != initial.checkOut
                  ? fromZonedInput(_out, tz)
                  : null,
              status: _status != initial.status ? _status : null,
              reason: _reason.trim(),
              explicitNulls: const {'check_in_at', 'check_out_at', 'status'},
            ),
          );
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, attendanceErrorText(e, t, f));
      setState(() => _busy = false);
      return;
    }
    staff.invalidateAttendance();
    if (!mounted) return;
    DashToast.success(context, t('staff.recordCorrected'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final rows = ref.watch(attendanceListProvider(widget.query)).value;
    var record = widget.record;
    for (final r in rows ?? const <AttendanceRecord>[]) {
      if (r.id == record.id) record = r;
    }
    final tz = _branchZone(ref, record.branchId);
    final seed = (
      checkIn: toZonedInput(record.checkInAt, tz),
      checkOut: toZonedInput(record.checkOutAt, tz),
      status: record.status,
    );
    if (!_edited && seed != _initial) {
      _in = seed.checkIn;
      _out = seed.checkOut;
      _status = seed.status;
    }
    if (!_edited || _initial == null) _initial = seed;
    final initial = _initial!;
    // A colleague covering this shift: its owner can't be clocked in (D1).
    final coverer = recordCoverer(rows ?? [record], record);
    final coverBlocks =
        coverer != null && _in.isNotEmpty && _in != initial.checkIn;
    final problems = _submitted ? _problems(t) : const <String, String>{};

    return DashSurface(
      title: t('staff.correctRecord'),
      description: '${record.employeeName ?? ''} · ${record.businessDate}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          _TimesFields(
            tz: tz,
            checkIn: _in,
            checkOut: _out,
            outError: problems['out'],
            onIn: (v) => _edit(() => _in = v),
            onOut: (v) => _edit(() => _out = v),
          ),
          if (coverer != null)
            _DashedNote(t('dawam.coveredByHint', args: {'name': coverer})),
          DashSelectField<String>(
            label: t('staff.attendanceStatus'),
            value: _status,
            options: [
              for (final s in attendanceStatuses)
                DashOption(value: s, label: attendanceStatusText(t, s)),
            ],
            onChanged: (v) => _edit(() => _status = v),
          ),
          DashTextField(
            label: t('staff.reason'),
            placeholder: t('staff.correctionReason'),
            value: _reason,
            errorText: problems['reason'],
            onChanged: (v) => _edit(() => _reason = v),
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.ghost,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          label: t('common.save'),
          loading: _busy,
          onPressed: _busy || coverBlocks
              ? null
              : () => _save(record, initial, tz),
        ),
      ],
    );
  }
}

// ── Parts ────────────────────────────────────────────────────────────────

/// In and out, on the branch's clock, with the zone named under them.
class _TimesFields extends ConsumerWidget {
  const _TimesFields({
    required this.tz,
    required this.checkIn,
    required this.checkOut,
    required this.onIn,
    required this.onOut,
    this.outError,
  });

  final String tz;
  final String checkIn;
  final String checkOut;
  final ValueChanged<String> onIn;
  final ValueChanged<String> onOut;
  final String? outError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashFormField<String>(
          label: t('staff.checkIn'),
          builder: (context, invalid) => AttendanceDateTimeField(
            label: t('staff.checkIn'),
            value: checkIn,
            invalid: invalid,
            onChanged: onIn,
          ),
        ),
        DashFormField<String>(
          label: t('staff.checkOut'),
          errorText: outError,
          builder: (context, invalid) => AttendanceDateTimeField(
            label: t('staff.checkOut'),
            value: checkOut,
            invalid: invalid,
            onChanged: onOut,
          ),
        ),
        Text(
          t('staff.timesInZone', args: {'tz': tz}),
          style: DashType.small.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}

/// A punch's day and time (`DateTimeField`): the day from the calendar, the
/// time typed the way it is said (930, 9:30p, ٩:٣٠ م). The value stays
/// `yyyy-MM-ddTHH:mm` ('' for none); a half-typed pair (a day, no time yet)
/// is kept here and the form hears only whole values.
class AttendanceDateTimeField extends ConsumerStatefulWidget {
  const AttendanceDateTimeField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.invalid = false,
    super.key,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool invalid;

  @override
  ConsumerState<AttendanceDateTimeField> createState() =>
      _AttendanceDateTimeFieldState();
}

class _AttendanceDateTimeFieldState
    extends ConsumerState<AttendanceDateTimeField> {
  late ({String date, String time}) _draft = splitDateTime(widget.value);

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final value = widget.value;
    final shown =
        joinDateTime(_draft.date, _draft.time) == value || value.isEmpty
        ? _draft
        : splitDateTime(value);
    void set(({String date, String time}) next) {
      setState(() => _draft = next);
      widget.onChanged(joinDateTime(next.date, next.time));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        Expanded(
          child: DashDateField(
            value: dashParseYmd(shown.date),
            semanticLabel: widget.label,
            today: dashParseYmd(teamTodayIsoOf(ref)),
            invalid: widget.invalid,
            onChanged: (d) => set((date: dashYmd(d), time: shown.time)),
          ),
        ),
        SizedBox(
          width: _timeWidth,
          child: DashTimeField(
            value: shown.time,
            semanticLabel: '${widget.label} · ${t('dawamOps.timeOfDay')}',
            placeholder: t('inputs.timePlaceholder'),
            invalid: widget.invalid,
            onChanged: (time) => set((date: shown.date, time: time)),
          ),
        ),
      ],
    );
  }
}

/// A Save refused with no field to show it on (an employee with no branch).
class _FormError extends StatelessWidget {
  const _FormError(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      style: DashType.body.copyWith(color: context.madarColors.errorText),
    ),
  );
}

/// The dashed note under the times (`rounded-lg border border-dashed p-3`).
class _DashedNote extends StatelessWidget {
  const _DashedNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return CustomPaint(
      painter: _DashedBorder(c.hairline),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Text(
          text,
          style: DashType.body.copyWith(color: c.textSecondary),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(Radii.xs),
        ).deflate(0.5),
      );
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += Space.sm) {
        canvas.drawPath(m.extractPath(d, d + Space.xs), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
