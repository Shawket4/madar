/// The bookings unit's mock backend (MadarRust `src/bookings/{handlers,
/// settings,availability}.rs`): GET/POST /bookings, GET/PATCH /bookings/{id},
/// POST /bookings/{id}/seat|complete|no-show|cancel, GET
/// /bookings/availability, GET/PUT /bookings/settings, and the two floor reads
/// the page shares with the floor unit (GET /floor/tables, /floor/sections),
/// registered only when the floor unit has not.
///
/// Gates as the backend: reads `bookings.read`, create `bookings.create`,
/// every other write `bookings.edit` (the backend's "bookings: update"), the
/// floor reads `floor.layout.read`; a branch the person cannot see is a 403.
/// Refusals carry no code (SELL-ALL-017). State is real: a write shows in the
/// next list, seating takes the booking's tables on the floor.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import '../shared/phone.dart';
import 'customers_mock.dart' show CustomerTables, mockExportsPerMinute;

void registerBookingsMocks(MockServer server, MockDb db) {
  final h = _Bookings(db);
  server
    ..on('GET', '/bookings/settings', h.getSettings)
    ..on('PUT', '/bookings/settings', h.putSettings)
    ..on('GET', '/bookings/availability', h.availability)
    ..on('GET', '/bookings', h.list)
    ..on('POST', '/bookings', h.create)
    ..on('GET', '/bookings/{id}', h.get)
    ..on('PATCH', '/bookings/{id}', h.update)
    ..on('POST', '/bookings/{id}/cancel', h.cancel)
    ..on('POST', '/bookings/{id}/no-show', h.noShow)
    ..on('POST', '/bookings/{id}/seat', h.seat)
    ..on('POST', '/bookings/{id}/complete', h.complete);
  // The floor unit owns these reads; the bookings page needs them too.
  if (!server.handles('GET', '/floor/tables')) {
    server.on('GET', '/floor/tables', h.tables);
  }
  if (!server.handles('GET', '/floor/sections')) {
    server.on('GET', '/floor/sections', h.sections);
  }
}

// ── Pure rules (availability.rs), unit-tested in bookings_mock_test ───────

/// A table the auto-assigner may give (`TableCap`).
typedef MockTableCap = ({String id, String label, int seats, String? section});

/// A booking's hold on a table for a window (`Claim`).
typedef MockClaim = ({String table, DateTime starts, DateTime ends});

/// Best fit (`best_fit`): the smallest single table that seats the party (a
/// preferred section wins ties, then fewer wasted seats, then the label);
/// else the pair in one section with the least waste; null when nothing fits.
List<String>? mockBestFit(
  List<MockTableCap> free,
  int party,
  String? sectionPref,
) {
  bool miss(String? section) => sectionPref != null && section != sectionPref;
  final singles = [
    for (final t in free)
      if (t.seats >= party) t,
  ];
  singles.sort((a, b) {
    final m = (miss(a.section) ? 1 : 0) - (miss(b.section) ? 1 : 0);
    if (m != 0) return m;
    final w = (a.seats - party) - (b.seats - party);
    return w != 0 ? w : a.label.compareTo(b.label);
  });
  if (singles.isNotEmpty) return [singles.first.id];
  (bool, int, List<String>)? best;
  for (var i = 0; i < free.length; i++) {
    for (var j = i + 1; j < free.length; j++) {
      final a = free[i], b = free[j];
      if (a.section != b.section) continue;
      final seats = a.seats + b.seats;
      if (seats < party) continue;
      final key = (miss(a.section), seats - party, [a.id, b.id]);
      final better =
          best == null ||
          (key.$1 ? 1 : 0) < (best.$1 ? 1 : 0) ||
          (key.$1 == best.$1 && key.$2 < best.$2);
      if (better) best = key;
    }
  }
  return best?.$3;
}

/// The day's slot starts for the host (`slot_starts`): none on a blackout
/// day or a day without hours; every [BookingSettings.slotMinutes] from the
/// open until the last start that still ends by the close (a close at or
/// before the open runs past midnight).
// ponytail: every Sabah branch is in Cairo, so the wall clock is MockClock's.
List<DateTime> mockSlotStarts(BookingSettings s, String date) {
  if (s.blackoutDates.contains(date)) return const [];
  final p = date.split('-').map(int.parse).toList();
  final dow = DateTime.utc(p[0], p[1], p[2]).weekday % 7;
  final entry = s.hours.where((h) => h.dow == dow).firstOrNull;
  final open = _hhmm(entry?.open), close = _hhmm(entry?.close);
  if (open == null || close == null) return const [];
  final openAt = MockClock.fromCairo(p[0], p[1], p[2], open.$1, open.$2);
  final nextDay = close.$1 * 60 + close.$2 <= open.$1 * 60 + open.$2;
  final closeAt = MockClock.fromCairo(
    p[0],
    p[1],
    p[2] + (nextDay ? 1 : 0),
    close.$1,
    close.$2,
  );
  final last = closeAt.subtract(Duration(minutes: s.defaultDurationMinutes));
  return [
    for (
      var t = openAt;
      !t.isAfter(last);
      t = t.add(Duration(minutes: s.slotMinutes))
    )
      t,
  ];
}

(int, int)? _hhmm(String? s) {
  final m = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$').firstMatch(s ?? '');
  if (m == null) return null;
  final h = int.parse(m[1]!), min = int.parse(m[2]!);
  return h < 24 && min < 60 ? (h, min) : null;
}

/// The backend's defaults for a branch with no settings row.
BookingSettings mockDefaultBookingSettings(String branchId) => BookingSettings(
  branchId: branchId,
  enabled: false,
  hours: [
    for (var d = 0; d < 7; d++)
      HoursEntry(dow: d, open: '12:00', close: '23:00'),
  ],
  slotMinutes: 30,
  defaultDurationMinutes: 90,
  minParty: 1,
  maxParty: 12,
  leadTimeMinutes: 60,
  horizonDays: 30,
  holdMinutes: 15,
  autoNoShowMinutes: 30,
  reminderLeadMinutes: 120,
  requireOtp: true,
  blackoutDates: const [],
);

// ── Handlers ──────────────────────────────────────────────────────────────

class _Bookings {
  _Bookings(this.db);

  final MockDb db;

  MockTable get _bookings => db[SellTables.bookings];
  MockTable get _tables => db[SellTables.floorTables];

  String _branchQuery(MockRequest req) {
    final id = req.q('branch_id');
    if (id == null || id.isEmpty) {
      req.badRequest('Query deserialize error: missing field `branch_id`');
    }
    return id;
  }

  BookingSettings _settings(String branchId) {
    final row = bookingSettingsRow(db, branchId);
    return row == null
        ? mockDefaultBookingSettings(branchId)
        : BookingSettings.fromJson(row);
  }

  MockRow _booking(MockRequest req) {
    final row = _bookings.find(req.param('id'));
    if (row == null) req.notFound('Booking not found');
    req.requireBranch(row['branch_id']! as String);
    return row;
  }

  // Settings.

  MockResponse getSettings(MockRequest req) {
    req.requireCap('bookings.read');
    final branchId = _branchQuery(req);
    req.requireBranch(branchId);
    return MockResponse.ok(_settings(branchId).toJson());
  }

  MockResponse putSettings(MockRequest req) {
    req.requireCap('bookings.edit');
    final s = req.bodyAs(BookingSettings.fromJson);
    req.requireBranch(s.branchId);
    _validateSettings(req, s);
    final json = s.toJson();
    final row = bookingSettingsRow(db, s.branchId);
    if (row == null) {
      db[SellTables.bookingSettings].put(json);
    } else {
      row
        ..clear()
        ..addAll(json);
    }
    return MockResponse.ok(_settings(s.branchId).toJson());
  }

  /// `BookingSettings::validate`, word for word.
  void _validateSettings(MockRequest req, BookingSettings s) {
    if (![15, 30, 60].contains(s.slotMinutes)) {
      req.badRequest('slot_minutes must be 15, 30 or 60');
    }
    if (s.defaultDurationMinutes < 15 || s.defaultDurationMinutes > 600) {
      req.badRequest('default_duration_minutes must be between 15 and 600');
    }
    if (s.minParty < 1 || s.maxParty < s.minParty) {
      req.badRequest('party limits must satisfy 1 <= min_party <= max_party');
    }
    if (s.leadTimeMinutes < 0) req.badRequest('lead_time_minutes must be >= 0');
    if (s.horizonDays < 1 || s.horizonDays > 365) {
      req.badRequest('horizon_days must be between 1 and 365');
    }
    if (s.holdMinutes < 0 || s.holdMinutes > 180) {
      req.badRequest('hold_minutes must be between 0 and 180');
    }
    final noShow = s.autoNoShowMinutes;
    if (noShow != null && (noShow < 5 || noShow > 240)) {
      req.badRequest('auto_no_show_minutes must be between 5 and 240');
    }
    final reminder = s.reminderLeadMinutes;
    if (reminder != null && (reminder < 15 || reminder > 2880)) {
      req.badRequest('reminder_lead_minutes must be between 15 and 2880');
    }
    final cap = s.maxCoversPerSlot;
    if (cap != null && cap <= 0) {
      req.badRequest('max_covers_per_slot must be > 0');
    }
    final seen = <int>{};
    for (final h in s.hours) {
      if (h.dow < 0 || h.dow > 6) req.badRequest('hours.dow must be 0..6');
      if (!seen.add(h.dow)) req.badRequest('hours: day ${h.dow} listed twice');
      if (_hhmm(h.open) == null || _hhmm(h.close) == null) {
        req.badRequest('hours.open / hours.close must be HH:MM');
      }
    }
    for (final d in s.blackoutDates) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d) ||
          DateTime.tryParse(d) == null) {
        req.badRequest("blackout_dates: '$d' is not YYYY-MM-DD");
      }
    }
  }

  // Reads.

  MockResponse list(MockRequest req) {
    req.requireCap('bookings.read');
    final branchId = _branchQuery(req);
    req.requireBranch(branchId);
    final export =
        req.headers['X-Madar-Export'] ?? req.headers['x-madar-export'];
    if (export == '1') _throttleExport(req);
    var from = req.qDateTime('from');
    var to = req.qDateTime('to');
    if (from == null || to == null) {
      final date = req.q('date') ?? MockClock.cairoDate(req.now);
      final p = _ymd(req, date);
      from = MockClock.fromCairo(p.$1, p.$2, p.$3);
      to = MockClock.fromCairo(p.$1, p.$2, p.$3 + 1);
    }
    final active = req.qBool('active') ?? false;
    final status = req.q('status');
    final rows = _bookings.where((b) {
      if (b['branch_id'] != branchId) return false;
      if (!DateTime.parse(b['starts_at']! as String).isBefore(to!)) {
        return false;
      }
      if (!DateTime.parse(b['ends_at']! as String).isAfter(from!)) {
        return false;
      }
      if (active && !SellSeed.isActive(b['status']! as String)) return false;
      return status == null || b['status'] == status;
    });
    rows.sort((a, b) {
      final s = (a['starts_at']! as String).compareTo(
        b['starts_at']! as String,
      );
      return s != 0
          ? s
          : (a['created_at']! as String).compareTo(b['created_at']! as String);
    });
    return MockResponse.ok([for (final b in rows) _view(b)]);
  }

  /// The backend's per-person export budget (SELL-ALL-018), on the same
  /// counter as every other export.
  void _throttleExport(MockRequest req) {
    final hits = db[CustomerTables.exportHits];
    final recent = hits.where(
      (h) =>
          h['user'] == req.persona.userId &&
          req.now.difference(DateTime.parse(h['at']! as String)).inSeconds < 60,
    );
    if (recent.length >= mockExportsPerMinute) {
      req.fail(
        MockResponse.error(
          429,
          'Too many exports; try again in a minute',
          code: 'EXPORT_RATE_LIMITED',
          retryAfterSeconds: 60,
        ),
      );
    }
    hits.insert({
      'user': req.persona.userId,
      'at': req.now.toIso8601String(),
    }, timestamps: false);
  }

  (int, int, int) _ymd(MockRequest req, String date) {
    final d = DateTime.tryParse(date);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) || d == null) {
      req.badRequest(
        'Query deserialize error: input contains invalid characters',
      );
    }
    return (d.year, d.month, d.day);
  }

  MockResponse get(MockRequest req) {
    req.requireCap('bookings.read');
    return MockResponse.ok(_view(_booking(req)));
  }

  MockResponse availability(MockRequest req) {
    req.requireCap('bookings.read');
    final branchId = _branchQuery(req);
    req.requireBranch(branchId);
    final party = req.qInt('party_size');
    final date = req.q('date');
    if (party == null || date == null) {
      req.badRequest('Query deserialize error: missing field');
    }
    _ymd(req, date);
    if (party <= 0) req.badRequest('party_size must be at least 1');
    final s = _settings(branchId);
    final duration = Duration(minutes: s.defaultDurationMinutes);
    final exclude = req.q('exclude_booking_id');
    final section = req.q('section_id');
    final slots = <SlotAvailability>[];
    for (final start in mockSlotStarts(s, date)) {
      final end = start.add(duration);
      var pick = end.isAfter(req.now)
          ? _pick(branchId, s, req.now, start, end, party, section, exclude)
          : null;
      final cap = s.maxCoversPerSlot;
      if (pick != null && cap != null) {
        if (_coversAt(branchId, start, exclude) + party > cap) pick = null;
      }
      slots.add(
        SlotAvailability(
          startsAt: start,
          endsAt: end,
          available: pick != null,
          tableIds: pick ?? const [],
        ),
      );
    }
    return MockResponse.ok(
      AvailabilityResponse(
        date: date,
        timezone: MockClock.timezone,
        slots: slots,
      ).toJson(),
    );
  }

  MockResponse tables(MockRequest req) {
    req.requireCap('floor.layout.read');
    final branchId = _branchQuery(req);
    req.requireBranch(branchId);
    final rows = _tables.where((t) => t['branch_id'] == branchId)
      ..sort(
        (a, b) => (a['label']! as String).toLowerCase().compareTo(
          (b['label']! as String).toLowerCase(),
        ),
      );
    return MockResponse.ok(rows);
  }

  MockResponse sections(MockRequest req) {
    req.requireCap('floor.layout.read');
    final branchId = _branchQuery(req);
    req.requireBranch(branchId);
    final rows =
        db[SellTables.floorSections].where((s) => s['branch_id'] == branchId)
          ..sort((a, b) {
            final o = (a['ordering']! as int).compareTo(b['ordering']! as int);
            return o != 0
                ? o
                : (a['name']! as String).toLowerCase().compareTo(
                    (b['name']! as String).toLowerCase(),
                  );
          });
    return MockResponse.ok(rows);
  }

  // The ground the assigner stands on.

  List<MockTableCap> _activeTables(String branchId) => [
    for (final t in _tables.where(
      (t) => t['branch_id'] == branchId && t['is_active'] == true,
    ))
      (
        id: t['id']! as String,
        label: t['label']! as String,
        seats: t['seats']! as int,
        section: t['section_id'] as String?,
      ),
  ];

  List<MockClaim> _claims(String branchId, String? exclude) => [
    for (final b in _bookings.where(
      (b) =>
          b['branch_id'] == branchId &&
          b['id'] != exclude &&
          SellSeed.isActive(b['status']! as String),
    ))
      for (final t in (b['table_ids']! as List).cast<String>())
        (
          table: t,
          starts: DateTime.parse(b['starts_at']! as String),
          ends: DateTime.parse(b['ends_at']! as String),
        ),
  ];

  /// `Ground::pick`: tables taken on the floor now are left out only for a
  /// window starting within the hold horizon.
  List<String>? _pick(
    String branchId,
    BookingSettings s,
    DateTime now,
    DateTime start,
    DateTime end,
    int party,
    String? section,
    String? exclude,
  ) {
    final horizon = Duration(minutes: math.max(s.holdMinutes, 15));
    final blocked = !start.isAfter(now.add(horizon))
        ? {
            for (final t in _tables.where(
              (t) => t['branch_id'] == branchId && t['status'] != 'free',
            ))
              t['id']! as String,
          }
        : const <String>{};
    final claims = _claims(branchId, exclude);
    final free = [
      for (final t in _activeTables(branchId))
        if (!blocked.contains(t.id) &&
            !claims.any(
              (c) =>
                  c.table == t.id &&
                  c.starts.isBefore(end) &&
                  c.ends.isAfter(start),
            ))
          t,
    ];
    return mockBestFit(free, party, section);
  }

  int _coversAt(String branchId, DateTime start, String? exclude) {
    var n = 0;
    for (final b in _bookings.rows) {
      if (b['branch_id'] != branchId || b['id'] == exclude) continue;
      if (!SellSeed.isActive(b['status']! as String)) continue;
      if (DateTime.parse(b['starts_at']! as String) == start) {
        n += b['party_size']! as int;
      }
    }
    return n;
  }

  /// The tables must be active on the branch; their seat sum.
  int _validateTables(MockRequest req, String branchId, List<String> ids) {
    final active = {for (final t in _activeTables(branchId)) t.id: t.seats};
    if (!ids.every(active.containsKey)) {
      req.badRequest('One or more tables are not on this branch');
    }
    return ids.fold(0, (n, id) => n + active[id]!);
  }

  // Writes.

  MockResponse create(MockRequest req) {
    req.requireCap('bookings.create');
    final body = req.bodyAs(CreateBookingRequest.fromJson);
    req.requireBranch(body.branchId);
    final s = _settings(body.branchId);
    if (body.partySize <= 0) req.badRequest('party_size must be at least 1');
    final name = body.guestName.trim();
    if (name.isEmpty) req.badRequest('guest_name is required');
    final phone = canonicalPhone(body.guestPhone);
    if (phone == null) req.badRequest('phone number looks invalid');
    final duration = body.durationMinutes ?? s.defaultDurationMinutes;
    if (duration < 15 || duration > 600) {
      req.badRequest('duration_minutes must be 15..600');
    }
    final starts = body.startsAt.toUtc();
    final ends = starts.add(Duration(minutes: duration));
    if (!ends.isAfter(req.now)) req.badRequest('That time has already passed');
    final force = body.force ?? false;
    final List<String> tableIds;
    if (body.tableIds case final ids?) {
      final seats = _validateTables(req, body.branchId, ids);
      if (ids.isNotEmpty && seats < body.partySize && !force) {
        req.conflict(
          'Those tables seat $seats, the party is ${body.partySize}',
        );
      }
      tableIds = ids;
    } else {
      final pick = _pick(
        body.branchId,
        s,
        req.now,
        starts,
        ends,
        body.partySize,
        body.sectionId,
        null,
      );
      if (pick == null && !force) {
        req.conflict('No table seats ${body.partySize} at that time');
      }
      tableIds = pick ?? const [];
    }
    _clash(req, body.branchId, tableIds, starts, ends, null);
    final customer = db[CustomerTables.customers].firstWhere(
      (c) => canonicalPhone(c['phone'] as String?) == phone,
    );
    final notes = body.notes?.trim();
    final now = req.now;
    final row = _bookings.insert({
      'id': db.newId(SellTables.bookings),
      'branch_id': body.branchId,
      'customer_id': customer?['id'],
      'guest_name': name,
      'guest_phone': phone,
      'locale': (body.locale ?? '').toLowerCase().startsWith('ar')
          ? 'ar'
          : 'en',
      'party_size': body.partySize,
      'starts_at': starts.toIso8601String(),
      'ends_at': ends.toIso8601String(),
      'held_from': starts
          .subtract(Duration(minutes: s.holdMinutes))
          .toIso8601String(),
      'status': 'confirmed',
      'source': 'host',
      'phone_verified': false,
      'section_id': body.sectionId,
      'notes': notes == null || notes.isEmpty ? null : notes,
      'table_ids': tableIds,
      'created_by': req.persona.userId,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    }, timestamps: false);
    return MockResponse.created(_view(row));
  }

  /// The claims' exclusion constraint (`map_claim_error`).
  void _clash(
    MockRequest req,
    String branchId,
    List<String> tableIds,
    DateTime starts,
    DateTime ends,
    String? exclude,
  ) {
    final taken = _claims(branchId, exclude).any(
      (c) =>
          tableIds.contains(c.table) &&
          c.starts.isBefore(ends) &&
          c.ends.isAfter(starts),
    );
    if (taken) req.conflict('That table is already booked for this time');
  }

  MockResponse update(MockRequest req) {
    req.requireCap('bookings.edit');
    final row = _booking(req);
    final body = req.bodyAs(UpdateBookingRequest.fromJson);
    final status = row['status']! as String;
    if (!SellSeed.isActive(status)) {
      req.conflict('A $status booking cannot be changed');
    }
    if (status == 'seated' && body.tableIds != null) {
      req.conflict('The party is already seated — move them on the floor');
    }
    final branchId = row['branch_id']! as String;
    final s = _settings(branchId);
    final party = body.partySize ?? row['party_size']! as int;
    if (party <= 0) req.badRequest('party_size must be at least 1');
    final starts0 = DateTime.parse(row['starts_at']! as String);
    final ends0 = DateTime.parse(row['ends_at']! as String);
    final starts = body.startsAt?.toUtc() ?? starts0;
    final duration =
        body.durationMinutes ?? ends0.difference(starts0).inMinutes;
    if (duration < 15 || duration > 600) {
      req.badRequest('duration_minutes must be 15..600');
    }
    final ends = starts.add(Duration(minutes: duration));
    if (!ends.isAfter(req.now)) req.badRequest('That time has already passed');
    final section = body.sectionId ?? row['section_id'] as String?;
    final moved = starts != starts0 || ends != ends0;
    final current = (row['table_ids']! as List).cast<String>();
    final seats = {for (final t in _activeTables(branchId)) t.id: t.seats};
    final currentSeats = current.fold(0, (n, id) => n + (seats[id] ?? 0));
    final force = body.force ?? true;
    List<String> tableIds;
    if (body.tableIds case final ids?) {
      final chosen = _validateTables(req, branchId, ids);
      if (ids.isNotEmpty && chosen < party && !force) {
        req.conflict('Those tables seat $chosen, the party is $party');
      }
      tableIds = ids;
    } else if (!moved && current.isNotEmpty && party <= currentSeats) {
      tableIds = current;
    } else {
      final free =
          current.isNotEmpty &&
          currentSeats >= party &&
          !_claims(branchId, row['id']! as String).any(
            (c) =>
                current.contains(c.table) &&
                c.starts.isBefore(ends) &&
                c.ends.isAfter(starts),
          );
      final pick = free
          ? current
          : _pick(
              branchId,
              s,
              req.now,
              starts,
              ends,
              party,
              section,
              row['id'] as String,
            );
      if (pick == null && !force) {
        req.conflict('No table seats $party at that time');
      }
      tableIds = pick ?? const [];
    }
    final name = body.guestName?.trim();
    if (body.guestName != null && name!.isEmpty) {
      req.badRequest('guest_name cannot be empty');
    }
    String? phone;
    if (body.guestPhone != null) {
      phone = canonicalPhone(body.guestPhone);
      if (phone == null) req.badRequest('phone number looks invalid');
    }
    _clash(req, branchId, tableIds, starts, ends, row['id']! as String);
    final notes = body.notes?.trim();
    row.addAll({
      'party_size': party,
      'starts_at': starts.toIso8601String(),
      'ends_at': ends.toIso8601String(),
      'held_from': starts
          .subtract(Duration(minutes: s.holdMinutes))
          .toIso8601String(),
      'section_id': section,
      'guest_name': ?name,
      'guest_phone': ?phone,
      if (body.notes != null) 'notes': notes!.isEmpty ? null : notes,
      'table_ids': tableIds,
      'updated_at': req.now.toIso8601String(),
    });
    return MockResponse.ok(_view(row));
  }

  MockResponse cancel(MockRequest req) {
    req.requireCap('bookings.edit');
    final row = _booking(req);
    final body = req.json;
    final status = row['status']! as String;
    if (status == 'cancelled') return MockResponse.ok(_view(row));
    if (!SellSeed.isActive(status)) {
      req.conflict('Booking is already $status');
    }
    if (status == 'seated') _release(row);
    final reason = (body['reason'] as String?)?.trim();
    _set(req, row, {
      'status': 'cancelled',
      'cancelled_at': req.now.toIso8601String(),
      'cancelled_by': 'host',
      'cancel_reason': reason == null || reason.isEmpty ? null : reason,
    });
    return MockResponse.ok(_view(row));
  }

  MockResponse noShow(MockRequest req) {
    req.requireCap('bookings.edit');
    final row = _booking(req);
    switch (row['status']) {
      case 'confirmed':
        _set(req, row, {
          'status': 'no_show',
          'no_show_at': req.now.toIso8601String(),
        });
      case 'no_show':
        break;
      case 'seated':
        req.conflict('The party was seated — cancel the booking if they left');
      default:
        req.conflict('Booking is already ${row['status']}');
    }
    return MockResponse.ok(_view(row));
  }

  MockResponse seat(MockRequest req) {
    req.requireCap('bookings.edit');
    final row = _booking(req);
    switch (row['status']) {
      case 'confirmed':
        final ids = req.json['table_ids'];
        if (ids is List) {
          final list = ids.cast<String>();
          _validateTables(req, row['branch_id']! as String, list);
          row['table_ids'] = list;
        }
        _take(req, row);
        _set(req, row, {
          'status': 'seated',
          'seated_at': row['seated_at'] ?? req.now.toIso8601String(),
        });
      case 'seated':
        break;
      default:
        req.conflict('Booking is ${row['status']}');
    }
    return MockResponse.ok(_view(row));
  }

  MockResponse complete(MockRequest req) {
    req.requireCap('bookings.edit');
    final row = _booking(req);
    switch (row['status']) {
      case 'seated':
        _release(row);
        _set(req, row, {
          'status': 'completed',
          'completed_at': row['completed_at'] ?? req.now.toIso8601String(),
        });
      case 'completed':
        break;
      default:
        req.conflict('Only a seated booking can be completed');
    }
    return MockResponse.ok(_view(row));
  }

  void _set(MockRequest req, MockRow row, MockRow patch) => row
    ..addAll(patch)
    ..['updated_at'] = req.now.toIso8601String();

  /// Seating takes the booking's tables for the party (`take_claimed_tables`).
  void _take(MockRequest req, MockRow booking) {
    for (final id in (booking['table_ids']! as List).cast<String>()) {
      final t = _tables.find(id);
      if (t == null || t['status'] == 'seated') continue;
      t.addAll({
        'status': 'seated',
        'seated_at': req.now.toIso8601String(),
        'party_size': booking['party_size'],
      });
    }
  }

  /// The party's hold is let go of (`release_claimed_tables`): a table with
  /// a bill on it stays the bill's.
  void _release(MockRow booking) {
    final billed = {
      for (final k in db[SellTables.openTickets].rows) k['table_id'],
    };
    for (final id in (booking['table_ids']! as List).cast<String>()) {
      final t = _tables.find(id);
      if (t == null || t['status'] != 'seated' || billed.contains(id)) continue;
      t.addAll({'status': 'free', 'seated_at': null, 'party_size': null});
    }
  }

  /// The row as the backend reads it: labels and `needs_table` follow the
  /// claimed tables. Written into the row itself, so every unit reading
  /// the table (a customer's bookings, the floor) sees a whole booking.
  MockRow _view(MockRow row) {
    final ids = (row['table_ids']! as List).cast<String>();
    return row
      ..['table_labels'] = [
        for (final id in ids) _tables.find(id)?['label'] ?? '?',
      ]
      ..['needs_table'] = ids.isEmpty;
  }
}
