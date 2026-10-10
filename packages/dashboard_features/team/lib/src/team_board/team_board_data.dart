/// What the Team board computes in the browser (`dawam/team-page.tsx`,
/// `dawam/phase-d.ts`), as pure functions.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_kit/dashboard_kit.dart';

/// A flag kind's glyph and word (`FLAG_META`); an unknown kind reads as
/// a suspicious location.
typedef FlagMeta = ({String icon, String key});

const Map<String, FlagMeta> flagMetas = {
  'left_mid_shift': (icon: 'map-pin-off', key: 'dawam.flag_left_mid_shift'),
  'suspicious': (icon: 'shield-alert', key: 'dawam.flag_suspicious'),
  'tracking_off': (icon: 'timer-off', key: 'dawam.flag_tracking_off'),
  'time_unverified': (icon: 'clock-3', key: 'dawam.flag_time_unverified'),
  'new_phone': (icon: 'smartphone', key: 'dawam.flag_new_phone'),
  'cover': (icon: 'user-round-check', key: 'dawam.flag_cover'),
  'phone_died': (icon: 'battery-low', key: 'dawam.flag_phone_died'),
};

FlagMeta flagMeta(String kind) => flagMetas[kind] ?? flagMetas['suspicious']!;

/// The hint key of a flag kind (`dawam.flagHint_<kind>`); an unknown kind
/// reads the cover's, as the web's `flagHint` default does.
String flagHintKey(String kind) => flagMetas.containsKey(kind)
    ? 'dawam.flagHint_$kind'
    : 'dawam.flagHint_cover';

/// A presence state → its pill tone (`STATE_TONE`).
const Map<String, DashTone> presenceTone = {
  'in': DashTone.success,
  'late': DashTone.warning,
  'absent': DashTone.danger,
  'on_leave': DashTone.info,
  'off': DashTone.neutral,
  'done': DashTone.neutral,
};

/// The board has someone on today's roster: anyone not off, scheduled, or
/// checked in. Everyone off with nothing scheduled is the empty board.
bool anyoneRostered(Iterable<PresenceRow> rows) => rows.any(
  (r) => r.state != 'off' || r.scheduledMinutes > 0 || r.checkInAt != null,
);

/// Rostered today, not in yet, and the check-in window is open
/// (`punchWindowOpen`): without `punch_opens_at` (an older server), never.
bool punchWindowOpen(PresenceRow r, DateTime now) {
  final opens = r.punchOpensAt;
  return r.state == 'off' &&
      r.scheduledMinutes > 0 &&
      r.checkInAt == null &&
      opens != null &&
      !opens.isAfter(now);
}

/// Whether the row offers a punch at all (before the right and the month).
bool punchOffered(PresenceRow r, DateTime now) =>
    const {'in', 'late', 'absent'}.contains(r.state) || punchWindowOpen(r, now);

/// Checked in and not out: the punch is a punch out.
bool punchesOut(PresenceRow r) => r.checkInAt != null && r.checkOutAt == null;

/// Whether a flag deduction waits for the owner: the server's
/// `deduction_status` when it says, else the caller's right and limit
/// (an older server): asking only, or above `max_amount`.
bool deductionWaits({
  required AttendanceFlag? handled,
  required String action,
  required int? amountPiastres,
  required bool holdsRight,
  required int? limit,
}) {
  final status = handled?.deductionStatus;
  if (status != null) return status == 'pending';
  return action == 'deduct' &&
      amountPiastres != null &&
      (!holdsRight || (limit != null && amountPiastres > limit));
}
