/// What the web's Requests inbox works out in the browser
/// (`staff/requests-inbox.tsx`): the kinds it offers, the cancel words, and
/// the New request form's rules and body, as pure functions. The row words
/// it shares with Approvals (`describeWindow`, `approveMeans`, `isMine`,
/// `mayDecide`) live in `approvals_data.dart`.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';

/// Every kind the filter offers, in the web's order (`KINDS`).
const List<String> requestKinds = [
  'leave',
  'late_arrival',
  'early_departure',
  'excuse',
  'mission',
  'correction',
];

/// What a person may file here: never a correction, which the staff app
/// files against a record (`FILEABLE`).
const List<String> fileableKinds = [
  'leave',
  'late_arrival',
  'early_departure',
  'excuse',
  'mission',
];

/// Joins the parts that say something (`[...].filter(Boolean).join(sep)`).
String joinSaid(Iterable<String?> parts, String sep) => [
  for (final p in parts)
    if (p != null && p.isNotEmpty) p,
].join(sep);

/// Who cancelled it and why (`cancelWords`): the server's name for the
/// canceller, else the employee linked to their account; "Cancelled" when
/// nobody can be named. Null for anything not cancelled.
String? cancelWords(StaffRequest r, Map<String, String> names, Translator t) {
  if (r.status != 'cancelled') return null;
  final by = r.cancelledBy;
  final who = r.cancelledByName ?? (by == null ? null : names[by]);
  final head = who != null
      ? t('staff.cancelledBy', args: {'name': who})
      : by != null
      ? t('staff.req_cancelled')
      : null;
  final s = joinSaid([head, r.cancelNote], ': ');
  return s.isEmpty ? null : s;
}

/// The New request form (`NewRequestValues`).
class NewRequestForm {
  NewRequestForm({required this.onDate}) : endDate = onDate;

  String kind = 'late_arrival';
  String? employeeId;
  String onDate;
  String endDate;
  String fromTime = '12:00';
  String toTime = '14:00';
  bool halfDay = false;
  String leaveHalf = 'first';

  /// `''`, `paid` or `unpaid`: asked only when the leave is approved as filed.
  String pay = '';
  String title = '';
  String reason = '';

  bool get isSpan => kind == 'mission' || (kind == 'leave' && !halfDay);
  bool get needsFrom => kind == 'early_departure' || kind == 'excuse';
  bool get needsTo => kind == 'late_arrival' || kind == 'excuse';
}

/// The form's refusals by field (`newRequestSchema`), in the reader's words.
/// The date is a picker that is never empty (see the divergences file).
Map<String, String> newRequestProblems(NewRequestForm v, Translator t) => {
  if (v.title.length > 200)
    'title': t('staff.titleTooLong')
  // The server takes the note as a mission's title; with neither it refuses.
  else if (v.kind == 'mission' &&
      v.title.trim().isEmpty &&
      v.reason.trim().isEmpty)
    'title': t('staff.missionNeedsText'),
  if (v.reason.length > 500) 'reason': t('staff.reasonTooLong'),
  if (v.isSpan && v.endDate.isNotEmpty && v.endDate.compareTo(v.onDate) < 0)
    'end_date': t('staff.endBeforeStart'),
  if (v.needsFrom && v.fromTime.isEmpty) 'from_time': t('staff.timeNeeded'),
  if (v.needsTo && v.toTime.isEmpty) 'to_time': t('staff.timeNeeded'),
};

/// What the form sends (`newRequestBody`). Leave has no type (RQ-2); a half
/// day is one day; times go as `HH:MM:00`.
CreateStaffRequest newRequestBody(NewRequestForm v) {
  final half = v.kind == 'leave' && v.halfDay;
  String hhmmss(String s) => s.length == 5 ? '$s:00' : s;
  final title = v.title.trim();
  final reason = v.reason.trim();
  return CreateStaffRequest(
    employeeId: v.employeeId,
    kind: v.kind,
    onDate: v.onDate,
    endDate: v.isSpan ? (v.endDate.isEmpty ? v.onDate : v.endDate) : null,
    fromTime: v.needsFrom ? hhmmss(v.fromTime) : null,
    toTime: v.needsTo ? hhmmss(v.toTime) : null,
    isHalfDay: v.kind == 'leave' ? half : null,
    leaveHalf: half ? v.leaveHalf : null,
    // A leave approved as it is filed carries its pay choice (RQ-2).
    isPaid: v.kind == 'leave' && v.pay.isNotEmpty ? v.pay == 'paid' : null,
    title: v.kind == 'mission' && title.isNotEmpty ? title : null,
    reason: reason.isEmpty ? null : reason,
    explicitNulls: const {'end_date', 'from_time', 'to_time', 'title', 'reason'},
  );
}
