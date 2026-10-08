/// Small rules several team pages share (`staff/util.ts`,
/// `dawam/money-dialogs.tsx` `readPounds`, `data/api/errors.ts`
/// `isStaleRefusal`): status tones, typed money, stale refusals, covers.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashTone;

/// Attendance status → pill tone (the backend's five values).
const Map<String, DashTone> attendanceStatusTone = {
  'present': DashTone.success,
  'late': DashTone.warning,
  'half_day': DashTone.warning,
  'absent': DashTone.danger,
  'on_leave': DashTone.info,
};

/// Request status (leave, late passes, missions, advances) → pill tone.
const Map<String, DashTone> requestStatusTone = {
  'pending': DashTone.warning,
  'approved': DashTone.success,
  'rejected': DashTone.danger,
  'cancelled': DashTone.neutral,
  'settled': DashTone.neutral,
};

/// Payroll period status → pill tone.
const Map<String, DashTone> periodStatusTone = {
  'draft': DashTone.neutral,
  'generated': DashTone.info,
  'paid': DashTone.success,
  'closed': DashTone.neutral,
};

/// Employment status → pill tone.
const Map<String, DashTone> employmentStatusTone = {
  'active': DashTone.success,
  'suspended': DashTone.warning,
  'terminated': DashTone.neutral,
};

/// Arabic-Indic and Persian digits → Latin (`latinDigits`).
String latinDigits(String s) => s.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (m) {
  final c = m.group(0)!.codeUnitAt(0);
  return String.fromCharCode(0x30 + (c >= 0x06f0 ? c - 0x06f0 : c - 0x0660));
});

/// Pounds → piastres (`egpToPiastres`).
int egpToPiastres(num egp) => (egp * 100).round();

/// Pounds as typed → piastres; null when it is not a positive amount
/// (`readPounds`): Arabic digits and separators too, "٩٬٠٠٠٫٥٠" is 9,000.50.
int? readPounds(String text) {
  final s = latinDigits(
    text,
  ).replaceAll('٫', '.').replaceAll(RegExp('[,٬]'), '').trim();
  final n = s.isEmpty ? 0.0 : double.tryParse(s);
  if (n == null || !n.isFinite || n <= 0) return null;
  return egpToPiastres(n);
}

/// Integer division rounding half away from zero (`rd` in the salary
/// calculator; multiply before dividing).
int rdiv(int a, int b) {
  if (b == 0) return 0;
  final q = a / b;
  return q.isNegative ? -((-q) + 0.5).floor() : (q + 0.5).floor();
}

/// Refusals that mean the screen is stale: someone else decided, claimed or
/// handled it first (TEAM-ALL-015). The page toasts the words AND refreshes
/// `/staff` so the list says what is true.
const Set<String> staleRefusalCodes = {
  'REQUEST_ALREADY_DECIDED',
  'ALREADY_DECIDED',
  'FLAG_HANDLED',
  'ALREADY_CLAIMED',
  'CLAIM_ALREADY_DECIDED',
  'NO_PENDING_CLAIM',
  'SWAP_STALE',
  'SUGGESTION_STALE',
  'NO_CLAIM_WAITING',
  'NO_SWAP_WAITING',
  'NO_SWAP_TO_CANCEL',
  'OPEN_SHIFT_CLOSED',
  'NO_COVER_WAITING',
  'NO_OVERTIME_WAITING',
  'PAYSLIP_ALREADY_PAID',
};

/// Whether [error] is a stale refusal (`isStaleRefusal`).
bool isStaleRefusal(Object? error) =>
    error is ApiException && staleRefusalCodes.contains(error.code);

/// Who is covering [employeeId]'s shift on [date] (`coveredBy`, owner
/// decision D1): a colleague's record naming them, with the cover pending or
/// confirmed (a rejected cover blocks nothing), on the same shift when
/// [workShiftId] is passed (null included); left out, any of the day's shifts
/// counts. Their name, or null.
String? coveredBy(
  Iterable<AttendanceRecord> records,
  String employeeId,
  String date, {
  Object? workShiftId = anyShift,
}) {
  for (final r in records) {
    if (r.coveredEmployeeId == employeeId &&
        r.employeeId != employeeId &&
        r.businessDate == date &&
        (r.coverStatus == 'pending' || r.coverStatus == 'confirmed') &&
        (identical(workShiftId, anyShift) || r.workShiftId == workShiftId)) {
      return r.employeeName ?? '—';
    }
  }
  return null;
}

/// [coveredBy]'s "any shift" (the web's `undefined`).
const Object anyShift = _AnyShift();

class _AnyShift {
  const _AnyShift();
}
