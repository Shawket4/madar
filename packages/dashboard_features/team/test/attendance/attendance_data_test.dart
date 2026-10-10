// The Attendance page's browser-side rules (`attendance_data.dart`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_team/src/attendance/attendance_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'attendance_support.dart';

AttendanceRecord rec(Map<String, Object?> row) =>
    AttendanceRecord.fromJson(row);

void main() {
  test('zoned input: an instant on a branch clock and back (AT-1)', () {
    final at = DateTime.parse('2026-09-22T06:02:00Z');
    expect(toZonedInput(at, 'Africa/Cairo'), '2026-09-22T09:02');
    expect(toZonedInput(at, 'Asia/Tokyo'), '2026-09-22T15:02');
    expect(toZonedInput(null, 'Africa/Cairo'), '');
    expect(
      fromZonedInput('2026-09-22T18:30', 'Africa/Cairo'),
      DateTime.parse('2026-09-22T15:30:00Z'),
    );
    expect(fromZonedInput('', 'Africa/Cairo'), isNull);
    expect(fromZonedInput('2026-09-22Tsoon', 'Africa/Cairo'), isNull);
  });

  test('a day and a time join only when both are there', () {
    expect(splitDateTime('2026-09-22T09:02'), (
      date: '2026-09-22',
      time: '09:02',
    ));
    expect(splitDateTime(''), (date: '', time: ''));
    expect(joinDateTime('2026-09-22', ''), '');
    expect(joinDateTime('2026-09-22', '09:30'), '2026-09-22T09:30');
    expect(stampReadable(''), isTrue);
    expect(stampReadable('2026-09-22T09:30'), isTrue);
    expect(stampReadable('2026-09-22Tsoon'), isFalse);
  });

  test('out after in, when both are typed', () {
    expect(outAfterIn('', '2026-09-22T08:00'), isTrue);
    expect(outAfterIn('2026-09-22T09:00', '2026-09-22T08:00'), isFalse);
    expect(outAfterIn('2026-09-22T09:00', '2026-09-22T09:00'), isFalse);
    expect(outAfterIn('2026-09-22T09:00', '2026-09-23T01:00'), isTrue);
  });

  test('the cover badge goes on the owner\'s own unpunched row only (D1)', () {
    final owner = rec(
      recordRow(
        id: 'a',
        employeeKey: 'mariam',
        date: day(-1),
        status: 'absent',
        workShiftId: 'w1',
      ),
    );
    final cover = rec(
      recordRow(
        id: 'c',
        employeeKey: 'youssef',
        date: day(-1),
        workShiftId: 'w1',
        inAt: cairo(day(-1), '07:00'),
        coveredEmployeeId: emp('mariam'),
        coverStatus: 'pending',
      ),
    );
    final rows = [owner, cover];
    expect(recordCoverer(rows, owner), 'Youssef Samir');
    expect(recordCoverer(rows, cover), isNull);
    final rejected = rec({...cover.toJson(), 'cover_status': 'rejected'});
    expect(recordCoverer([owner, rejected], owner), isNull);
    final other = rec({...owner.toJson(), 'work_shift_id': 'w2'});
    expect(recordCoverer([other, cover], other), isNull);
  });

  test('the headline sums the per-person summary', () {
    AttendanceSummary s(int p, int l, int a, int ot) => AttendanceSummary(
      employeeId: 'e',
      employeeName: 'E',
      presentDays: p,
      lateDays: l,
      absentDays: a,
      halfDays: 0,
      leaveDays: 0,
      totalLateMinutes: 0,
      totalOvertimeMinutes: ot,
      totalWorkedMinutes: 0,
    );
    expect(attendanceTotals([s(3, 1, 0, 45), s(2, 0, 1, 30)]), (
      present: 5,
      late: 1,
      absent: 1,
      overtime: 75,
    ));
    expect(attendanceTotals(const []), (
      present: 0,
      late: 0,
      absent: 0,
      overtime: 0,
    ));
  });
}
