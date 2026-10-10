/// The mock's notion of "now": fixed by default at 2026-10-08 10:00 in Cairo
/// (07:00 UTC), so seeds, screenshots and period maths are stable.
library;

/// A settable clock with Africa/Cairo wall-clock helpers.
class MockClock {
  MockClock([DateTime? now]) : _now = (now ?? defaultNow).toUtc();

  /// 2026-10-08T10:00:00+03:00.
  static final DateTime defaultNow = DateTime.utc(2026, 10, 8, 7);

  static const String timezone = 'Africa/Cairo';

  DateTime _now;

  /// Now, in UTC.
  DateTime get now => _now;

  void set(DateTime now) => _now = now.toUtc();

  void advance(Duration by) => _now = _now.add(by);

  /// Cairo's UTC offset at [utc]: +03:00 in summer time (Egypt: from the last
  /// Friday of April to the last Thursday of October), +02:00 otherwise.
  static Duration offsetAt(DateTime utc) {
    final u = utc.toUtc();
    final (startUtc, endUtc) = _summer[u.year] ??= _summerOf(u.year);
    final ms = u.millisecondsSinceEpoch;
    return ms >= startUtc && ms < endUtc
        ? const Duration(hours: 3)
        : const Duration(hours: 2);
  }

  static final Map<int, (int, int)> _summer = {};

  /// Summer time of [year] as UTC epoch milliseconds [start, end).
  static (int, int) _summerOf(int year) {
    final start = _lastWeekday(
      year,
      4,
      DateTime.friday,
    ); // 00:00 local (+02:00)
    final end = _lastWeekday(
      year,
      10,
      DateTime.thursday,
    ).add(const Duration(days: 1)); // 24:00 local (+03:00)
    return (
      start.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
      end.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
    );
  }

  static DateTime _lastWeekday(int year, int month, int weekday) {
    var d = DateTime.utc(year, month + 1).subtract(const Duration(days: 1));
    while (d.weekday != weekday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  /// Cairo wall-clock fields of [utc], carried in a UTC DateTime.
  static DateTime wall(DateTime utc) => utc.toUtc().add(offsetAt(utc));

  /// The UTC instant of Cairo wall-clock time y-m-d h:mi.
  static DateTime fromCairo(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
    int second = 0,
  ]) {
    final guess = DateTime.utc(year, month, day, hour, minute, second);
    return guess.subtract(offsetAt(guess.subtract(const Duration(hours: 2))));
  }

  /// The UTC instant Cairo's day containing [utc] starts.
  static DateTime startOfCairoDay(DateTime utc) {
    final w = wall(utc);
    return fromCairo(w.year, w.month, w.day);
  }

  /// `2026-10-08` (Cairo date of [utc]).
  static String cairoDate(DateTime utc) {
    final w = wall(utc);
    return '${w.year.toString().padLeft(4, '0')}-${_two(w.month)}-${_two(w.day)}';
  }

  /// `2026-10-08T10:00:00+03:00`.
  static String cairoIso(DateTime utc) {
    final w = wall(utc);
    final off = offsetAt(utc).inHours;
    return '${cairoDate(utc)}T${_two(w.hour)}:${_two(w.minute)}:${_two(w.second)}'
        '+${_two(off)}:00';
  }

  /// Today's Cairo date at [now].
  String get today => cairoDate(_now);

  static String _two(int v) => v.toString().padLeft(2, '0');
}
