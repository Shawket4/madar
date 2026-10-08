/// Date helpers several report units share (section 11.3 of the inventory):
/// the branch-local `YYYY-MM-DD` the Bundles, Staff discipline and Staff
/// drinks reads send, and `fmtBusinessDate` (Tills, Staff drinks).
library;

import 'package:dashboard_core/dashboard_core.dart';

/// `localDate(iso)`: the calendar day of [iso] in the active zone as
/// `YYYY-MM-DD` (the web's `cairoParts` → padded parts).
String localDateParam(DashFormat f, String iso) {
  final p = f.cairoParts(iso);
  return '${p.y.toString().padLeft(4, '0')}-'
      '${(p.m + 1).toString().padLeft(2, '0')}-'
      '${p.d.toString().padLeft(2, '0')}';
}

/// Whether [from] and [to] fall on the same local day (Staff drinks'
/// `oneDay`, REP-SPL-011/015).
bool sameLocalDay(DashFormat f, String from, String to) =>
    localDateParam(f, from) == localDateParam(f, to);

final RegExp _ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// `fmtBusinessDate("YYYY-MM-DD")`: the day pinned to local noon in the
/// active zone, then `fmtDate`, so it never slips a day; "—" when malformed.
String fmtBusinessDate(DashFormat f, String? ymd) {
  final m = ymd == null ? null : _ymd.firstMatch(ymd);
  if (m == null) return '—';
  final noon = wallClock(
    f.timezone,
    int.parse(m.group(1)!),
    int.parse(m.group(2)!) - 1,
    int.parse(m.group(3)!),
    12,
  );
  return f.fmtDate(isoString(noon));
}
