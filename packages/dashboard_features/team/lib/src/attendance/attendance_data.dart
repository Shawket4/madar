/// What the Attendance page computes in the browser (`staff/attendance-page.tsx`,
/// `attendance-dialogs.tsx`, `date-time-field.tsx`, `lib/zoned-input.ts`), as
/// pure functions.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';

import '../shared/team_util.dart';

/// The five statuses a record can have, in the web's order.
const List<String> attendanceStatuses = [
  'present',
  'late',
  'half_day',
  'absent',
  'on_leave',
];

/// How a punch was made, for every way but the phone's own (`METHOD_LABEL`,
/// CL-16): `mobile_gps` says nothing.
const Map<String, String> punchMethodKeys = {
  'manager': 'staff.method_manager',
  'manual': 'staff.method_manual',
  'till': 'staff.method_till',
  'correction': 'staff.method_correction',
  'offline': 'staff.method_offline',
  'cover': 'staff.method_cover',
  'kiosk': 'staff.method_kiosk',
  'auto': 'staff.method_auto',
};

/// The words for [method], or '' (`methodText`).
String punchMethodText(Translator t, String? method) {
  final key = method == null ? null : punchMethodKeys[method];
  return key == null ? '' : t(key);
}

/// A status as a word (`t("staff.att_<s>", s)`).
String attendanceStatusText(Translator t, String status) =>
    t.exists('staff.att_$status') ? t('staff.att_$status') : status;

/// The window's headline, summed over the per-employee summary.
typedef AttendanceTotals = ({int present, int late, int absent, int overtime});

AttendanceTotals attendanceTotals(Iterable<AttendanceSummary> rows) {
  var present = 0, late = 0, absent = 0, overtime = 0;
  for (final r in rows) {
    present += r.presentDays;
    late += r.lateDays;
    absent += r.absentDays;
    overtime += r.totalOvertimeMinutes;
  }
  return (present: present, late: late, absent: absent, overtime: overtime);
}

/// The colleague covering [r]'s shift, on the owner's own unpunched row
/// (D1); null on a cover row or a row with a punch.
String? recordCoverer(Iterable<AttendanceRecord> records, AttendanceRecord r) =>
    r.coveredEmployeeId != null || r.checkInAt != null
    ? null
    : coveredBy(
        records,
        r.employeeId,
        r.businessDate,
        workShiftId: r.workShiftId,
      );

// ── times on a branch's clock (`lib/zoned-input.ts`) ──────────────────────

String _pad(int n) => n.toString().padLeft(2, '0');

/// [instant] as `yyyy-MM-ddTHH:mm` on [zone]'s wall clock; '' for none
/// (`toZonedInput`).
String toZonedInput(DateTime? instant, String zone) {
  if (instant == null) return '';
  final d = inZone(instant, zone);
  return '${d.year.toString().padLeft(4, '0')}-${_pad(d.month)}-'
      '${_pad(d.day)}T${_pad(d.hour)}:${_pad(d.minute)}';
}

final RegExp _local = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$');

/// `yyyy-MM-ddTHH:mm` read on [zone]'s wall clock, as a UTC instant; null
/// for '' (`fromZonedInput`).
DateTime? fromZonedInput(String local, String zone) {
  final m = _local.firstMatch(local.trim());
  if (m == null) return null;
  int p(int i) => int.parse(m.group(i)!);
  return wallClock(zone, p(1), p(2) - 1, p(3), p(4), p(5));
}

/// The day and the `HH:MM` of a `yyyy-MM-ddTHH:mm` value (`splitDateTime`).
({String date, String time}) splitDateTime(String? v) {
  final parts = (v ?? '').split('T');
  final time = parts.length > 1 ? parts[1] : '';
  return (
    date: parts.first,
    time: time.length > 5 ? time.substring(0, 5) : time,
  );
}

/// Both halves, or '' (nothing to save yet) (`joinDateTime`).
String joinDateTime(String date, String time) =>
    date.isNotEmpty && time.isNotEmpty ? '${date}T$time' : '';

/// The out stamp, when both are typed, comes after the in stamp
/// (`outAfterIn`).
bool outAfterIn(String checkIn, String checkOut) =>
    checkIn.isEmpty || checkOut.isEmpty || checkOut.compareTo(checkIn) > 0;

final RegExp _ymd = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// A whole `yyyy-mm-dd` day.
bool isYmd(String? s) => _ymd.hasMatch(s ?? '');

// ── the Excel file (TEAM-ATT-021) ─────────────────────────────────────────

/// The workbook's columns: worked, late, left early and overtime travel as
/// MINUTES, so a payroll sheet can add them up.
List<ExcelColumn<AttendanceRecord>> attendanceExportColumns(Translator t) => [
  ExcelColumn(
    header: t('staff.name'),
    accessor: (r) => r.employeeName ?? '—',
    type: ExcelColumnType.text,
    width: 24,
  ),
  ExcelColumn(
    header: t('staff.workShift'),
    accessor: (r) => r.workShiftName ?? t('staff.unscheduled'),
    type: ExcelColumnType.text,
    width: 20,
  ),
  ExcelColumn(
    header: t('staff.date'),
    accessor: (r) => r.businessDate,
    type: ExcelColumnType.date,
    width: 14,
  ),
  ExcelColumn(
    header: t('staff.attendanceStatus'),
    accessor: (r) => attendanceStatusText(t, r.status),
    type: ExcelColumnType.text,
    width: 14,
  ),
  ExcelColumn(
    header: t('staff.checkIn'),
    accessor: (r) => r.checkInAt,
    type: ExcelColumnType.dateTime,
    width: 22,
  ),
  ExcelColumn(
    header: t('staff.checkInDistance'),
    accessor: (r) => r.checkInDistanceMeters?.round(),
    type: ExcelColumnType.integer,
    width: 16,
  ),
  ExcelColumn(
    header: t('staff.checkOut'),
    accessor: (r) => r.checkOutAt,
    type: ExcelColumnType.dateTime,
    width: 22,
  ),
  ExcelColumn(
    header: t('staff.autoClosedColumn'),
    accessor: (r) => r.checkOutMethod == 'auto',
    type: ExcelColumnType.bool,
    width: 14,
  ),
  ExcelColumn(
    header: t('staff.inMethodColumn'),
    accessor: (r) => punchMethodText(t, r.checkInMethod),
    type: ExcelColumnType.text,
    width: 16,
  ),
  ExcelColumn(
    header: t('staff.outMethodColumn'),
    accessor: (r) => punchMethodText(t, r.checkOutMethod),
    type: ExcelColumnType.text,
    width: 16,
  ),
  ExcelColumn(
    header: t('staff.inReasonColumn'),
    accessor: (r) => r.punchReason ?? '',
    type: ExcelColumnType.text,
    width: 24,
  ),
  ExcelColumn(
    header: t('staff.outReasonColumn'),
    accessor: (r) => r.checkOutReason ?? '',
    type: ExcelColumnType.text,
    width: 24,
  ),
  ExcelColumn(
    header: t('staff.workedMinutes'),
    accessor: (r) => r.workedMinutes,
    type: ExcelColumnType.integer,
    width: 16,
    total: true,
  ),
  ExcelColumn(
    header: t('staff.lateMinutes'),
    accessor: (r) => r.lateMinutes,
    type: ExcelColumnType.integer,
    width: 16,
    total: true,
  ),
  ExcelColumn(
    header: t('dawamOps.leftEarlyMinutes'),
    accessor: (r) => r.earlyLeaveMinutes,
    type: ExcelColumnType.integer,
    width: 18,
    total: true,
  ),
  ExcelColumn(
    header: t('staff.overtimeMinutes'),
    accessor: (r) => r.overtimeMinutes,
    type: ExcelColumnType.integer,
    width: 18,
    total: true,
  ),
];

/// The whole file: `Madar-Attendance-<date>.xlsx`, one sheet titled
/// "Attendance", the status filter as its subtitle, `from → to` as its meta.
ExcelConfig attendanceExcel(
  Translator t, {
  required List<AttendanceRecord> rows,
  required String from,
  required String to,
  required String? status,
  String? logoUrl,
}) {
  final title = t('staff.attendance');
  return ExcelConfig(
    filename: 'Madar-Attendance',
    logoUrl: logoUrl,
    meta: '$from → $to',
    sheets: [
      _erase(
        ExcelSheet<AttendanceRecord>(
          name: title,
          title: title,
          subtitle: status == null
              ? t('staff.allStatuses')
              : attendanceStatusText(t, status),
          rows: rows,
          columns: attendanceExportColumns(t),
          totals: true,
        ),
      ),
    ],
  );
}

ExcelSheet<Object?> _erase(ExcelSheet<AttendanceRecord> s) => ExcelSheet(
  name: s.name,
  title: s.title,
  subtitle: s.subtitle,
  totals: s.totals,
  rows: s.rows,
  columns: [
    for (final c in s.columns)
      ExcelColumn<Object?>(
        header: c.header,
        type: c.type,
        width: c.width,
        total: c.total,
        accessor: (r) => c.accessor(r! as AttendanceRecord),
      ),
  ],
);
