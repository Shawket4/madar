/// What the Schedule computes in the browser (`dawam/day-editor.tsx`,
/// `dawam/schedule-checks.ts`, `dawam/coverage-editor.tsx`,
/// `dawam/schedule-page.tsx`), as pure functions: a block's times on a
/// weekday, the clash check said before saving, the coverage grid both ways,
/// the roster's cell maps and the holidays list.
library;

import 'package:dashboard_api/dashboard_api.dart';

/// `HH:MM[:SS]` → `HH:MM` (`hhmm`); empty for null.
String hhmm(String? v) => (v ?? '').length >= 5 ? v!.substring(0, 5) : v ?? '';

/// A block's times on [weekday]: that day's own, else its default.
({String start, String end}) blockTimesOn(WorkShiftBrief w, int weekday) {
  for (final d in w.dayTimes) {
    if (d.dayOfWeek == weekday) {
      return (start: hhmm(d.startTime), end: hhmm(d.endTime));
    }
  }
  return (start: hhmm(w.startTime), end: hhmm(w.endTime));
}

/// The blocks the server rosters on [weekday] (`valid_days`).
List<WorkShiftBrief> blocksOn(List<WorkShiftBrief> templates, int weekday) => [
  for (final w in templates)
    if (w.validDays.contains(weekday)) w,
];

/// The day as it stands, sent back unchanged: a shift keeps its own times
/// only when it has them (`blockOf`).
DayBlock blockOf(RosterShift s) => DayBlock(
  workShiftId: s.workShiftId,
  startTime: s.timesEdited ? s.startTime : null,
  endTime: s.timesEdited ? s.endTime : null,
  explicitNulls: const {'start_time', 'end_time'},
);

// ── Clash checks (`schedule-checks.ts`) ───────────────────────────────────

/// A block a manager reads by name, with its wall-clock times.
typedef TimedBlock = ({String name, String start, String end});

TimedBlock timedOf(String name, String start, String end) =>
    (name: name, start: hhmm(start), end: hhmm(end));

/// "09:30" / "09:30:00" → 570; null for anything else.
int? toMinutes(String? v) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v ?? '');
  return m == null ? null : int.parse(m[1]!) * 60 + int.parse(m[2]!);
}

/// [start, end) in minutes from the day's midnight; an end at or before the
/// start runs past 1440.
(int, int)? spanOf(String start, String end) {
  final s = toMinutes(start);
  final e = toMinutes(end);
  if (s == null || e == null) return null;
  return (s, e <= s ? e + 1440 : e);
}

/// Every pair of blocks whose times overlap, in the order given; touching
/// ends do not clash.
List<(TimedBlock, TimedBlock)> overlapsOf(List<TimedBlock> blocks) {
  final out = <(TimedBlock, TimedBlock)>[];
  for (var i = 0; i < blocks.length; i++) {
    for (var j = i + 1; j < blocks.length; j++) {
      final a = spanOf(blocks[i].start, blocks[i].end);
      final b = spanOf(blocks[j].start, blocks[j].end);
      if (a != null && b != null && a.$1 < b.$2 && b.$1 < a.$2) {
        out.add((blocks[i], blocks[j]));
      }
    }
  }
  return out;
}

/// The blocks of [day] that [next] would clash with.
List<TimedBlock> clashesWith(List<TimedBlock> day, TimedBlock next) => [
  for (final (a, b) in overlapsOf([next, ...day]))
    if (identical(a, next)) b,
];

// ── Coverage grid (`coverage-editor.tsx`) ─────────────────────────────────

/// Saturday first, as the roster's week runs; 0 = Sunday … 6 = Saturday.
const List<int> coverageDayOrder = [6, 0, 1, 2, 3, 4, 5];

const String _endOfDay = '23:59:59';

/// `dow|hour` → people needed.
typedef CoverageGrid = Map<String, int>;

String coverageKey(int dow, int hour) => '$dow|$hour';

String hourLabel(int h) => '${h.toString().padLeft(2, '0')}:00';

int _hourOf(String t) => int.parse(t.substring(0, 2));

/// A band's end hour: a partial hour rounds up.
int _endHour(String t) {
  final p = t.split(':').map(int.parse).toList();
  return p[0] + ((p.length > 1 && p[1] != 0) || (p.length > 2 && p[2] != 0) ? 1 : 0);
}

/// Bands (department-wide only) → one cell per weekday and hour.
CoverageGrid toGrid(List<CoverageNeed> needs) {
  final g = <String, int>{};
  for (final n in needs) {
    if (n.departmentId != null) continue;
    for (var h = _hourOf(n.bandStart); h < _endHour(n.bandEnd); h++) {
      g[coverageKey(n.dayOfWeek, h)] = n.staff;
    }
  }
  return g;
}

/// Cells → bands: runs of equal hours merged, empty and zero cells dropped,
/// the last band of a day ending "23:59:59".
List<CoverageNeed> fromGrid(CoverageGrid g) {
  final out = <CoverageNeed>[];
  for (var dow = 0; dow < 7; dow++) {
    var h = 0;
    while (h < 24) {
      final staff = g[coverageKey(dow, h)];
      if (staff == null || staff == 0) {
        h++;
        continue;
      }
      var end = h + 1;
      while (end < 24 && g[coverageKey(dow, end)] == staff) {
        end++;
      }
      out.add(
        CoverageNeed(
          dayOfWeek: dow,
          bandStart: '${hourLabel(h)}:00',
          bandEnd: end == 24 ? _endOfDay : '${hourLabel(end)}:00',
          staff: staff,
          explicitNulls: const {'department_id'},
        ),
      );
      h = end;
    }
  }
  return out;
}

/// The hours shown: 06:00–23:00, widened earlier to any hour with a need.
List<int> coverageHours(Iterable<String> usedKeys) {
  var from = 6;
  for (final k in usedKeys) {
    final h = int.parse(k.split('|')[1]);
    if (h < from) from = h;
  }
  return [for (var h = from; h < 24; h++) h];
}

/// A typed cell: an integer 0–200; empty, unreadable or 0 is no need (null).
int? readCoverageCell(String v) {
  final n = num.tryParse(v.trim());
  if (n == null || !n.isFinite) return null;
  final i = n.truncate().clamp(0, 200);
  return i == 0 ? null : i;
}

// ── The roster's maps (`schedule-page.tsx`) ───────────────────────────────

String cellKey(String employeeId, String date) => '$employeeId|$date';

/// The viewed week's roster by `employee|date`.
class RosterIndex {
  RosterIndex(RosterView? view, String branchId)
    : templates = [
        for (final w in view?.workShifts ?? const <WorkShiftBrief>[])
          if (w.branchId == null || w.branchId == branchId) w,
      ] {
    for (final s in view?.shifts ?? const <RosterShift>[]) {
      (shifts[cellKey(s.employeeId, s.date)] ??= []).add(s);
    }
    for (final s in view?.elsewhere ?? const <ElsewhereShift>[]) {
      (elsewhere[cellKey(s.employeeId, s.date)] ??= []).add(s);
    }
    for (final d in view?.dateSets ?? const <DateSet>[]) {
      dateSets[cellKey(d.employeeId, d.date)] = d.dayOff;
    }
    for (final w in view?.warnings ?? const <LabourWarning>[]) {
      (warnings[cellKey(w.employeeId, w.date)] ??= []).add(w);
    }
    changedDays = {
      for (final s in view?.shifts ?? const <RosterShift>[])
        if (s.changed) cellKey(s.employeeId, s.date),
    }.length;
  }

  /// The blocks of this board: business-wide or this branch's.
  final List<WorkShiftBrief> templates;
  final Map<String, List<RosterShift>> shifts = {};

  /// Their shifts at other branches: shown, never this board's to edit.
  final Map<String, List<ElsewhereShift>> elsewhere = {};

  /// The date holds its own set; `true` = a day off by date change.
  final Map<String, bool> dateSets = {};
  final Map<String, List<LabourWarning>> warnings = {};

  /// Days of the week changed after it was published.
  late final int changedDays;

  List<RosterShift> shiftsOf(String employeeId, String date) =>
      shifts[cellKey(employeeId, date)] ?? const [];

  List<ElsewhereShift> elsewhereOf(String employeeId, String date) =>
      elsewhere[cellKey(employeeId, date)] ?? const [];

  List<LabourWarning> warningsOf(String employeeId, String date) =>
      warnings[cellKey(employeeId, date)] ?? const [];
}

/// The next 45 days' holidays and the viewed week's own, one per date,
/// sorted.
List<HolidayView> mergeHolidays(
  List<HolidayView>? upcoming,
  List<HolidayView>? week,
) {
  final seen = <String>{};
  final out = [
    for (final h in [...?upcoming, ...?week])
      if (seen.add(h.onDate)) h,
  ]..sort((a, b) => a.onDate.compareTo(b.onDate));
  return out;
}

/// `YYYY-MM-01` of [weekStart]'s month (the fairness card's month).
String monthOf(String weekStart) => '${weekStart.substring(0, 8)}01';
