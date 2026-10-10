/// Time zones and the wall-clock reading the web does with `@date-fns/tz`'s
/// `TZDate`: madar-time's `local_parts` / `local_instant` through the core,
/// over the zone database the server and the POS read (chrono-tz).
library;

import 'package:rust_bridge_dashboard/rules.dart' as rules;

/// The web's `APP_TZ`: the zone used until the scope's own is known.
const String appTimezone = 'Africa/Cairo';

/// Whether [name] is a zone the database knows.
bool isKnownTimezone(String name) =>
    rules.localParts(tzName: name, atMs: 0) != null;

/// [instant] read on the wall clock of [zone] (an unknown zone reads as
/// [appTimezone]). The answer is a UTC [DateTime] carrying the wall clock's
/// fields (and the instant's own seconds), not the instant itself.
DateTime inZone(DateTime instant, String zone) {
  final u = instant.toUtc();
  final ms = u.millisecondsSinceEpoch;
  final p =
      rules.localParts(tzName: zone, atMs: ms) ??
      rules.localParts(tzName: appTimezone, atMs: ms)!;
  final d = p.date.split('-').map(int.parse).toList();
  return DateTime.utc(
    d[0],
    d[1],
    d[2],
    p.hour,
    p.minute,
    u.second,
    u.millisecond,
  );
}

/// `new TZDate(y, m, d, h, mi, zone)`: a wall-clock time in [zone] (month
/// 0-based, out-of-range parts rolling over as JavaScript's `Date` does; an
/// unknown zone reads as [appTimezone]), as an instant. A time the clocks
/// skip moves forward by the gap; one they repeat is the earlier.
DateTime wallClock(
  String zone,
  int year,
  int month0,
  int day, [
  int hour = 0,
  int minute = 0,
]) {
  final n = DateTime.utc(year, month0 + 1, day);
  final ymd =
      '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
  final ms =
      rules.localInstant(tzName: zone, date: ymd, hour: hour, minute: minute) ??
      rules.localInstant(
        tzName: appTimezone,
        date: ymd,
        hour: hour,
        minute: minute,
      )!;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

/// `Date#toISOString()`: UTC, milliseconds, `Z`.
String isoString(DateTime instant) {
  final u = instant.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final ms = u.millisecond.toString().padLeft(3, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}.${ms}Z';
}

final RegExp _dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// `new Date(value)` for what the web passes: a [DateTime], an ISO string
/// (a date-only string is UTC midnight; a date-time without an offset is the
/// device's local time, as in JavaScript), or epoch milliseconds. Null when it
/// is not a valid date.
DateTime? parseJsDate(Object? value) {
  if (value is DateTime) return value;
  if (value is num) {
    if (!value.isFinite) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  if (value is! String) return null;
  final s = value.trim();
  final d = _dateOnly.firstMatch(s);
  if (d != null) {
    return DateTime.utc(
      int.parse(d.group(1)!),
      int.parse(d.group(2)!),
      int.parse(d.group(3)!),
    );
  }
  return DateTime.tryParse(s);
}
