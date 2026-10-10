/// Time zones (IANA, from the `timezone` package's bundled database) and the
/// day-boundary arithmetic the web does with `@date-fns/tz`'s `TZDate`.
library;

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The web's `APP_TZ`: the zone used until the scope's own is known.
const String appTimezone = 'Africa/Cairo';

bool _loaded = false;

/// Loads the zone database once (cheap after the first call).
void ensureTimeZones() {
  if (_loaded) return;
  tzdata.initializeTimeZones();
  _loaded = true;
}

/// The location for [name], falling back to [appTimezone] for an unknown one.
tz.Location tzLocation(String? name) {
  ensureTimeZones();
  if (name == null || name.isEmpty) return tz.getLocation(appTimezone);
  try {
    return tz.getLocation(name);
  } on Object {
    return tz.getLocation(appTimezone);
  }
}

/// Whether [name] is a zone the database knows.
bool isKnownTimezone(String name) {
  ensureTimeZones();
  try {
    tz.getLocation(name);
    return true;
  } on Object {
    return false;
  }
}

/// [instant] read on the wall clock of [zone].
tz.TZDateTime inZone(DateTime instant, String zone) =>
    tz.TZDateTime.from(instant, tzLocation(zone));

/// `new TZDate(y, m, d, h, mi, s, ms, zone)`: a wall-clock time in [zone]
/// (month 0-based, overflow normalised like JavaScript's `Date`), as an
/// instant.
DateTime wallClock(
  String zone,
  int year,
  int month0,
  int day, [
  int hour = 0,
  int minute = 0,
  int second = 0,
  int millisecond = 0,
]) {
  final loc = tzLocation(zone);
  // Normalise the parts first (day 0, day -5, month 12 …) as Date does.
  final n = DateTime.utc(
    year,
    month0 + 1,
    day,
    hour,
    minute,
    second,
    millisecond,
  );
  return tz.TZDateTime(
    loc,
    n.year,
    n.month,
    n.day,
    n.hour,
    n.minute,
    n.second,
    n.millisecond,
  ).toUtc();
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
