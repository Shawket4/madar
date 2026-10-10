// The bookings handlers against hand-computed answers: the auto-assigner,
// the day's slots, the gates, the validation and the state a write leaves.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_sell/src/area_seed.dart';
import 'package:dashboard_sell/src/mock/bookings_mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

MockTableCap _t(String id, int seats, [String? section]) =>
    (id: id, label: id, seats: seats, section: section);

Future<MockResponse> _send(
  MockServer s,
  String method,
  String path, {
  Map<String, List<String>> query = const {},
  Object? body,
}) async {
  try {
    final r = await s.send(
      ApiRequest(method: method, path: path, query: query, body: body),
    );
    return MockResponse(r.status, bodyBytes: r.bodyBytes);
  } on ApiException catch (e) {
    return MockResponse.json(e.status, e.details);
  }
}

void main() {
  group('the auto-assigner (best_fit)', () {
    test('the smallest single table that seats the party', () {
      final free = [_t('T1', 2, 's'), _t('T2', 4, 's'), _t('T3', 6, 's')];
      expect(mockBestFit(free, 3, null), ['T2']);
      expect(mockBestFit(free, 6, null), ['T3']);
    });
    test('a preferred section wins ties', () {
      final free = [_t('A', 4, 'in'), _t('B', 4, 'out')];
      expect(mockBestFit(free, 4, 'out'), ['B']);
    });
    test(
      'two tables in one section when no single one fits; none for nine',
      () {
        final free = [_t('A1', 4, 'a'), _t('A2', 4, 'a'), _t('B1', 4, 'b')];
        expect(mockBestFit(free, 7, null), ['A1', 'A2']);
        expect(mockBestFit(free, 9, null), isNull);
      },
    );
  });

  group('the day\'s slots (slot_starts)', () {
    BookingSettings s(
      List<HoursEntry> hours, {
      List<String> blackout = const [],
    }) => mockDefaultBookingSettings('b').toJson().let(
      (j) => BookingSettings.fromJson({
        ...j,
        'hours': [for (final h in hours) h.toJson()],
        'blackout_dates': blackout,
      }),
    );
    test(
      'every slot from the open until the last start that ends by the close',
      () {
        // Thursday 18:00–21:00, 90 min: 18:00, 18:30, 19:00, 19:30.
        final slots = mockSlotStarts(
          s(const [HoursEntry(dow: 4, open: '18:00', close: '21:00')]),
          '2026-09-10',
        );
        expect(slots.length, 4);
        expect(slots.first, DateTime.utc(2026, 9, 10, 15));
        expect(
          mockSlotStarts(
            s(const [HoursEntry(dow: 4, open: '18:00', close: '21:00')]),
            '2026-09-11',
          ),
          isEmpty,
          reason: 'Friday closed',
        );
        expect(
          mockSlotStarts(
            s(
              const [HoursEntry(dow: 4, open: '18:00', close: '21:00')],
              blackout: const ['2026-09-10'],
            ),
            '2026-09-10',
          ),
          isEmpty,
          reason: 'blackout',
        );
      },
    );
    test('a close after midnight runs into the next day', () {
      final st = BookingSettings.fromJson({
        ...mockDefaultBookingSettings('b').toJson(),
        'slot_minutes': 60,
        'default_duration_minutes': 60,
        'hours': [
          const HoursEntry(dow: 5, open: '22:00', close: '02:00').toJson(),
        ],
      });
      expect(
        mockSlotStarts(st, '2026-09-11').length,
        4,
        reason: '22, 23, 00, 01',
      );
    });
  });

  group('handlers', () {
    test(
      'SELL-BKG-003 the day list: Heliopolis today, in start order',
      () async {
        final s = bookingsServer();
        final r = await _send(
          s.server,
          'GET',
          '/bookings',
          query: {
            'branch_id': [SeedIds.heliopolis],
            'date': [today],
          },
        );
        final list = (r.json! as List).cast<Map<String, Object?>>();
        expect(list.map((b) => b['guest_name']).toList(), hasLength(7));
        expect(list.map((b) => b['status']).toList(), [
          'completed',
          'seated',
          'confirmed',
          'confirmed',
          'confirmed',
          'confirmed',
          'cancelled',
        ]);
        expect(list[4]['needs_table'], isTrue);
        expect(list[1]['table_labels'], ['T1']);
      },
    );

    test('a reader without bookings.read is refused, with no code', () async {
      final s = bookingsServer(persona: Persona.limited);
      final r = await _send(
        s.server,
        'GET',
        '/bookings',
        query: {
          'branch_id': [SeedIds.maadi],
        },
      );
      expect(r.status, 403);
      expect((r.json! as Map)['code'], isNull);
    });

    test('a branch the person cannot see is refused', () async {
      final s = bookingsServer(persona: Persona.manager);
      final r = await _send(
        s.server,
        'GET',
        '/bookings/settings',
        query: {
          'branch_id': [SeedIds.heliopolis],
        },
      );
      expect(r.status, 403);
    });

    test(
      'SELL-BKG-040 availability: 09:00 … 21:30 for two, the server\'s pick',
      () async {
        final s = bookingsServer();
        final r = await _send(
          s.server,
          'GET',
          '/bookings/availability',
          query: {
            'branch_id': [SeedIds.heliopolis],
            'date': [today],
            'party_size': ['2'],
          },
        );
        final slots = ((r.json! as Map)['slots']! as List).cast<Map>();
        // Thursday 09:00–23:00, 30-minute slots, 90 minutes long: 26 starts.
        expect(slots, hasLength(26));
        expect(slots.first['starts_at'], '2026-10-08T06:00:00.000Z');
        expect(slots.last['starts_at'], '2026-10-08T18:30:00.000Z');
        // 18:00 Cairo: every two-seat table is free; T3 wins on its label.
        final evening = slots.firstWhere(
          (x) => x['starts_at'] == '2026-10-08T15:00:00.000Z',
        );
        expect(evening['available'], isTrue);
        expect(evening['table_ids'], [SellIds.table('heliopolis', 'T3')]);
      },
    );

    test(
      'SELL-BKG-055 create: canonical phone, server pick, state persists',
      () async {
        final s = bookingsServer();
        final r = await _send(
          s.server,
          'POST',
          '/bookings',
          body: {
            'branch_id': SeedIds.heliopolis,
            'party_size': 4,
            'starts_at': '2026-10-08T15:00:00.000Z',
            'guest_name': '  Sara ',
            'guest_phone': '0100 123-4567',
            'notes': null,
          },
        );
        expect(r.status, 201);
        final b = r.json! as Map;
        expect(b['guest_name'], 'Sara');
        expect(b['guest_phone'], '201001234567');
        expect(b['status'], 'confirmed');
        expect(b['ends_at'], '2026-10-08T16:30:00.000Z');
        expect(b['table_labels'], ['T1']);
        expect(stored(s.db).where((x) => x.guestName == 'Sara'), hasLength(1));
      },
    );

    test('create refusals: no table, past, bad phone, blank name', () async {
      final s = bookingsServer();
      Future<MockResponse> post(Map<String, Object?> patch) => _send(
        s.server,
        'POST',
        '/bookings',
        body: {
          'branch_id': SeedIds.heliopolis,
          'party_size': 2,
          'starts_at': '2026-10-08T15:00:00.000Z',
          'guest_name': 'Sara',
          'guest_phone': '01001234567',
          ...patch,
        },
      );
      expect((await post({'party_size': 40})).status, 409);
      expect((await post({'party_size': 40, 'force': true})).status, 201);
      expect(
        (await post({'starts_at': '2026-10-08T03:00:00.000Z'})).status,
        400,
      );
      expect((await post({'guest_phone': '12345'})).status, 400);
      expect((await post({'guest_name': '  '})).status, 400);
    });

    test(
      'SELL-BKG-017/018/019/020 the status moves and their refusals',
      () async {
        final s = bookingsServer();
        Future<int> post(String path, [Object? body]) async =>
            (await _send(s.server, 'POST', path, body: body)).status;
        final late = heliBooking(3);
        expect(await post('/bookings/$late/seat', {}), 200);
        expect(
          s.db[SellTables.floorTables].find(
            SellIds.table('heliopolis', 'T3'),
          )!['status'],
          'seated',
        );
        expect(await post('/bookings/$late/no-show'), 409);
        expect(await post('/bookings/$late/complete'), 200);
        expect(
          s.db[SellTables.floorTables].find(
            SellIds.table('heliopolis', 'T3'),
          )!['status'],
          'free',
        );
        expect(await post('/bookings/$late/cancel', {}), 409);
        final due = heliBooking(4);
        expect(await post('/bookings/$due/no-show'), 200);
        expect(await post('/bookings/$due/no-show'), 200, reason: 'idempotent');
        final evening = heliBooking(6);
        expect(
          await post('/bookings/$evening/cancel', {
            'reason': null,
            'notify_guest': true,
          }),
          200,
        );
        expect(s.db[SellTables.bookings].find(evening)!['status'], 'cancelled');
        expect(await post('/bookings/${heliBooking(1)}/seat', {}), 409);
      },
    );

    test('SELL-BKG-056 edit: a cancelled booking cannot change', () async {
      final s = bookingsServer();
      final r = await _send(
        s.server,
        'PATCH',
        '/bookings/${heliBooking(7)}',
        body: {'party_size': 3},
      );
      expect(r.status, 409);
      expect(
        (r.json! as Map)['error'],
        'Conflict: A cancelled booking cannot be changed',
      );
    });

    test(
      'SELL-BKG-073 settings: saved, read back; bad hours refused',
      () async {
        final s = bookingsServer();
        final base = BookingSettings.fromJson(
          (await _send(
                s.server,
                'GET',
                '/bookings/settings',
                query: {
                  'branch_id': [SeedIds.zamalek],
                },
              )).json!
              as Map<String, Object?>,
        ).toJson();
        expect(base['enabled'], isFalse);
        final ok = await _send(
          s.server,
          'PUT',
          '/bookings/settings',
          body: {...base, 'enabled': true},
        );
        expect(ok.status, 200);
        expect((ok.json! as Map)['enabled'], isTrue);
        final bad = await _send(
          s.server,
          'PUT',
          '/bookings/settings',
          body: {
            ...base,
            'hours': [
              {'dow': 1, 'open': 'noon', 'close': '23:00'},
            ],
          },
        );
        expect(bad.status, 400);
        expect(
          (bad.json! as Map)['error'],
          'Bad request: hours.open / hours.close must be HH:MM',
        );
      },
    );
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
