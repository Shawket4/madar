/// The mock backend for Bookings settings (`/settings/bookings`, SET-BKG
/// rows), as MadarRust `src/bookings/settings.rs` answers:
///
/// - `GET /bookings/settings?branch_id=`: `bookings.read` and a branch the
///   caller may see; a branch never set up answers the backend's defaults
///   (`BookingSettings::defaults`: online off).
/// - `PUT /bookings/settings`: `bookings.edit` (the backend's "bookings:
///   update") at the body's branch, then `BookingSettings::validate` word for
///   word (400s); the whole row is replaced and returned.
///
/// The rows are the area seed's (`SetupSeed.bookingSettings`, table
/// `booking_settings`, one row per branch, no `id`; sell's rows, value for
/// value).
/// The sell area answers the same two routes for its bookings page from the
/// same table, so the app registers whichever area comes first and both read
/// one record. In this package's own tests these handlers answer.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'support.dart';

abstract final class BookingSettingsMock {
  static const String table = SetupSeed.bookingSettingsTable;

  /// `BookingSettings::defaults`.
  static Map<String, Object?> defaults(String branchId) => {
    'branch_id': branchId,
    'enabled': false,
    'hours': [
      for (var d = 0; d < 7; d++) {'dow': d, 'open': '12:00', 'close': '23:00'},
    ],
    'slot_minutes': 30,
    'default_duration_minutes': 90,
    'min_party': 1,
    'max_party': 12,
    'lead_time_minutes': 60,
    'horizon_days': 30,
    'hold_minutes': 15,
    'auto_no_show_minutes': 30,
    'reminder_lead_minutes': 120,
    'require_otp': true,
    'max_covers_per_slot': null,
    'blackout_dates': const <String>[],
  };

  static MockRow? row(MockDb db, String branchId) =>
      db[table].firstWhere((r) => r['branch_id'] == branchId);

  /// The branch's settings as the API states them.
  static Map<String, Object?> wire(MockDb db, String branchId) {
    final r = row(db, branchId);
    return r == null ? defaults(branchId) : Map.of(r);
  }
}

/// `parse_hhmm`: `%H:%M` after a trim.
bool _hhmmOk(Object? s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch('${s ?? ''}'.trim());
  return m != null && int.parse(m[1]!) < 24 && int.parse(m[2]!) < 60;
}

void registerBookingSettingsMocks(MockServer server, MockDb db) {
  /// `BookingSettings::validate`, word for word.
  void validate(MockRequest req, Map<String, Object?> s) {
    int n(String k) => (s[k] as num?)?.toInt() ?? 0;
    int? opt(String k) => (s[k] as num?)?.toInt();
    if (![15, 30, 60].contains(n('slot_minutes'))) {
      req.badRequest('slot_minutes must be 15, 30 or 60');
    }
    final duration = n('default_duration_minutes');
    if (duration < 15 || duration > 600) {
      req.badRequest('default_duration_minutes must be between 15 and 600');
    }
    if (n('min_party') < 1 || n('max_party') < n('min_party')) {
      req.badRequest('party limits must satisfy 1 <= min_party <= max_party');
    }
    if (n('lead_time_minutes') < 0) {
      req.badRequest('lead_time_minutes must be >= 0');
    }
    if (n('horizon_days') < 1 || n('horizon_days') > 365) {
      req.badRequest('horizon_days must be between 1 and 365');
    }
    if (n('hold_minutes') < 0 || n('hold_minutes') > 180) {
      req.badRequest('hold_minutes must be between 0 and 180');
    }
    final noShow = opt('auto_no_show_minutes');
    if (noShow != null && (noShow < 5 || noShow > 240)) {
      req.badRequest('auto_no_show_minutes must be between 5 and 240');
    }
    final reminder = opt('reminder_lead_minutes');
    if (reminder != null && (reminder < 15 || reminder > 2880)) {
      req.badRequest('reminder_lead_minutes must be between 15 and 2880');
    }
    final cap = opt('max_covers_per_slot');
    if (cap != null && cap <= 0) {
      req.badRequest('max_covers_per_slot must be > 0');
    }
    final seen = <int>{};
    for (final h in (s['hours'] as List? ?? const [])) {
      final e = h as Map;
      final dow = (e['dow'] as num).toInt();
      if (dow < 0 || dow > 6) req.badRequest('hours.dow must be 0..6');
      if (!seen.add(dow)) req.badRequest('hours: day $dow listed twice');
      if (!_hhmmOk(e['open']) || !_hhmmOk(e['close'])) {
        req.badRequest('hours.open / hours.close must be HH:MM');
      }
    }
    for (final d in (s['blackout_dates'] as List? ?? const [])) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('$d') ||
          DateTime.tryParse('$d') == null) {
        req.badRequest("blackout_dates: '$d' is not YYYY-MM-DD");
      }
    }
  }

  onIfAbsent(server, 'GET', '/bookings/settings', (req) {
    req.requireCap('bookings.read');
    final branchId = req.q('branch_id');
    if (branchId == null || branchId.isEmpty) {
      req.badRequest('Query deserialize error: missing field `branch_id`');
    }
    req.requireBranch(branchId);
    return MockResponse.ok(BookingSettingsMock.wire(db, branchId));
  });

  onIfAbsent(server, 'PUT', '/bookings/settings', (req) {
    req.requireCap('bookings.edit');
    final body = req.json;
    final branchId = body['branch_id'];
    if (branchId is! String) {
      req.badRequest('Json deserialize error: missing field `branch_id`');
    }
    req.requireBranch(branchId);
    validate(req, body);
    final row = {...BookingSettingsMock.defaults(branchId), ...body};
    final table = db[BookingSettingsMock.table];
    final existing = BookingSettingsMock.row(db, branchId);
    if (existing == null) {
      table.put(row);
    } else {
      existing
        ..clear()
        ..addAll(row);
    }
    return MockResponse.ok(BookingSettingsMock.wire(db, branchId));
  });
}
