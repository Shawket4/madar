// The Bookings settings mock against the backend's rules (MadarRust
// `src/bookings/settings.rs`), and the pane's pure rules
// (`booking_settings_data.dart`) against hand-computed answers.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

typedef _Backend = ({MockServer server, MockDb db});
typedef _Answer = ({int status, Object? json, String error});

Future<_Answer> _send(
  _Backend b,
  String method, {
  String? branch,
  Object? body,
  Persona? as,
}) async {
  if (as != null) b.server.persona = as;
  try {
    final r = await b.server.send(
      ApiRequest(
        method: method,
        path: bkgSettings,
        query: {
          'branch_id': ?(branch == null ? null : [branch]),
        },
        body: body,
      ),
    );
    final text = utf8.decode(r.bodyBytes);
    return (
      status: r.status,
      json: text.isEmpty ? null : jsonDecode(text),
      error: '',
    );
  } on ApiException catch (e) {
    return (status: e.status, json: null, error: e.message);
  }
}

String _words(MockResponse r) => MockServer.toApiException(r).message;

Map<String, Object?> _rules(String branchId, [Map<String, Object?>? patch]) => {
  ...BookingSettingsMock.defaults(branchId),
  ...?patch,
};

void main() {
  group('pure rules', () {
    test('day names, Sunday = 0, in both languages', () {
      expect(bookingDayName(0, arabic: false), 'Sunday');
      expect(bookingDayName(6, arabic: false), 'Saturday');
      expect(bookingDayName(5, arabic: true), 'الجمعة');
    });

    test('the body: the whole object, blank optional fields as null', () {
      final draft = _rules(SeedIds.maadi, {
        'auto_no_show_minutes': null,
        'reminder_lead_minutes': 60,
        'max_covers_per_slot': null,
      });
      final json = bookingSettingsBody(draft).toJson();
      expect(json['auto_no_show_minutes'], isNull);
      expect(json.containsKey('auto_no_show_minutes'), isTrue);
      expect(json.containsKey('max_covers_per_slot'), isTrue);
      expect(json['reminder_lead_minutes'], 60);
      expect(json['branch_id'], SeedIds.maadi);
    });
  });

  group('GET /bookings/settings', () {
    test(
      'a branch set up answers its row; one never set up, the defaults',
      () async {
        final b = bkgServer();
        final helio = await _send(b, 'GET', branch: SeedIds.heliopolis);
        expect(helio.status, 200);
        final h = BookingSettings.fromJson(helio.json! as Map<String, Object?>);
        expect(h.enabled, isTrue);
        expect(h.blackoutDates, ['2026-10-31']);
        b.db[BookingSettingsMock.table].removeWhere(
          (r) => r['branch_id'] == SeedIds.newCairo,
        );
        final cairo = await _send(b, 'GET', branch: SeedIds.newCairo);
        expect(cairo.json, BookingSettingsMock.defaults(SeedIds.newCairo));
        expect((cairo.json! as Map)['enabled'], isFalse);
      },
    );

    test('needs a branch_id', () async {
      final a = await _send(bkgServer(), 'GET');
      expect(a.status, 400);
    });

    test('bookings.read, at a branch the caller may see', () async {
      final none = await _send(
        bkgServer(persona: Persona.limited),
        'GET',
        branch: SeedIds.maadi,
      );
      expect(none.status, 403);
      expect(none.error, _words(MockResponse.denied('bookings.read')));
      final b = bkgServer(persona: Persona.manager);
      expect((await _send(b, 'GET', branch: SeedIds.zamalek)).status, 200);
      expect((await _send(b, 'GET', branch: SeedIds.heliopolis)).status, 403);
    });
  });

  group('PUT /bookings/settings', () {
    test(
      'replaces the row; the next read shows it; a first save creates it',
      () async {
        final b = bkgServer();
        final body = _rules(SeedIds.newCairo, {
          'enabled': true,
          'max_party': 10,
        });
        final a = await _send(b, 'PUT', body: body);
        expect(a.status, 200);
        expect((a.json! as Map)['max_party'], 10);
        final read = await _send(b, 'GET', branch: SeedIds.newCairo);
        expect((read.json! as Map)['enabled'], isTrue);
        expect(
          b.db[BookingSettingsMock.table].where(
            (r) => r['branch_id'] == SeedIds.newCairo,
          ),
          hasLength(1),
        );
      },
    );

    test('the backend\'s validation, word for word', () async {
      final b = bkgServer();
      final cases = <Map<String, Object?>, String>{
        {'slot_minutes': 20}: 'slot_minutes must be 15, 30 or 60',
        {'default_duration_minutes': 10}:
            'default_duration_minutes must be between 15 and 600',
        {'min_party': 4, 'max_party': 2}:
            'party limits must satisfy 1 <= min_party <= max_party',
        {'horizon_days': 0}: 'horizon_days must be between 1 and 365',
        {'hold_minutes': 200}: 'hold_minutes must be between 0 and 180',
        {'auto_no_show_minutes': 2}:
            'auto_no_show_minutes must be between 5 and 240',
        {'reminder_lead_minutes': 5000}:
            'reminder_lead_minutes must be between 15 and 2880',
        {'max_covers_per_slot': 0}: 'max_covers_per_slot must be > 0',
        {
          'hours': [
            {'dow': 1, 'open': 'noon', 'close': '23:00'},
          ],
        }: 'hours.open / hours.close must be HH:MM',
        {
          'hours': [
            {'dow': 1, 'open': '12:00', 'close': '23:00'},
            {'dow': 1, 'open': '13:00', 'close': '22:00'},
          ],
        }: 'hours: day 1 listed twice',
        {
          'blackout_dates': ['31/10/2026'],
        }: "blackout_dates: '31/10/2026' is not YYYY-MM-DD",
      };
      for (final e in cases.entries) {
        final a = await _send(b, 'PUT', body: _rules(SeedIds.maadi, e.key));
        expect(a.status, 400, reason: e.value);
        expect(a.error, _words(MockResponse.badRequest(e.value)));
      }
      // Nothing was stored.
      expect(BookingSettingsMock.row(b.db, SeedIds.maadi)!['min_party'], 2);
    });

    test('bookings.edit at the body\'s branch', () async {
      final b = bkgServer(persona: Persona.manager);
      expect(
        (await _send(b, 'PUT', body: _rules(SeedIds.heliopolis))).status,
        403,
      );
      expect(
        (await _send(b, 'PUT', body: _rules(SeedIds.zamalek))).status,
        200,
      );
      final limited = await _send(
        bkgServer(persona: Persona.limited),
        'PUT',
        body: _rules(SeedIds.maadi),
      );
      expect(limited.error, _words(MockResponse.denied('bookings.edit')));
    });
  });
}
