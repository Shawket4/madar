// The delivery unit's mock handlers against the backend's rules
// (MadarRust `src/delivery/settings.rs`), and the page's pure rules
// (`delivery_data.dart`) against hand-computed answers.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_setup/src/delivery/delivery_data.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'support.dart';

typedef _Backend = ({MockServer server, MockDb db});

/// One answer: its status, its JSON, and a refusal's words.
typedef _Answer = ({int status, Object? json, String error});

Future<_Answer> _send(
  _Backend b,
  String method,
  String path, {
  Map<String, String>? query,
  Object? body,
  Persona? as,
}) async {
  if (as != null) b.server.persona = as;
  try {
    final r = await b.server.send(
      ApiRequest(
        method: method,
        path: path,
        query: {
          for (final e in (query ?? const {}).entries) e.key: [e.value],
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

Map<String, Object?> _settingsBody(
  String branchId, [
  Map<String, Object?>? x,
]) => {
  ...DeliveryForm.from(
    DeliverySeed.defaults(branchId),
  ).toInput(branchId).toJson(),
  ...?x,
};

Map<String, Object?> _zone(String branchId, int m, {int fee = 1000}) => {
  'branch_id': branchId,
  'name': 'Ring',
  'name_translations': <String, Object?>{},
  'max_road_distance_meters': m,
  'fee': fee,
  'is_active': true,
};

String _error(_Answer r) => r.error;

/// What the transport makes of [r] (the words a refusal shows).
String _words(MockResponse r) => MockServer.toApiException(r).message;

void main() {
  group('GET /delivery/settings', () {
    test('a seeded branch answers its row; one never set up the defaults '
        '(prep 20, OTP and GPS on, channels off)', () async {
      final b = setupMockServer();
      final r = await _send(
        b,
        'GET',
        DeliveryRoutes.settings,
        query: {'branch_id': SeedIds.newCairo},
      );
      expect(r.status, 200);
      final s = BranchDeliverySettings.fromJson(
        r.json! as Map<String, Object?>,
      );
      expect(s.inMallFee, 1500);
      expect(s.maxRoadDistanceMeters, 8000);
      b.db['delivery_settings'].removeWhere(
        (row) => row['branch_id'] == SeedIds.zamalek,
      );
      final d = BranchDeliverySettings.fromJson(
        (await _send(
              b,
              'GET',
              DeliveryRoutes.settings,
              query: {'branch_id': SeedIds.zamalek},
            )).json!
            as Map<String, Object?>,
      );
      expect(d.prepTimeMinutes, 20);
      expect(d.otpRequired, isTrue);
      expect(d.inMallRequireLocation, isTrue);
      expect(d.pickupEnabled, isFalse);
    });

    test('refusals: no read capability 403; another branch 403; no branch '
        '400; an unknown branch 404', () async {
      final b = setupMockServer();
      var r = await _send(
        b,
        'GET',
        DeliveryRoutes.settings,
        query: {'branch_id': SeedIds.maadi},
        as: Persona.limited,
      );
      expect(r.status, 403);
      r = await _send(
        b,
        'GET',
        DeliveryRoutes.settings,
        query: {'branch_id': SeedIds.heliopolis},
        as: Persona.manager,
      );
      expect(
        _error(r),
        _words(MockResponse.forbidden('Not assigned to this branch')),
      );
      r = await _send(b, 'GET', DeliveryRoutes.settings, as: Persona.owner);
      expect(r.status, 400);
      r = await _send(
        b,
        'GET',
        DeliveryRoutes.settings,
        query: {'branch_id': mockUuid('branch:nowhere')},
      );
      expect(r.status, 404);
    });
  });

  group('PUT /delivery/settings', () {
    test(
      'saves every field, keeps the POS override and answers the row',
      () async {
        final b = setupMockServer();
        final row = b.db['delivery_settings'].firstWhere(
          (r) => r['branch_id'] == SeedIds.maadi,
        )!;
        row['outside_override'] = 'closed';
        final r = await _send(
          b,
          'PUT',
          DeliveryRoutes.settings,
          body: _settingsBody(SeedIds.maadi, {
            'outside_enabled': true,
            'max_road_distance_meters': 4200,
            'pickup_discount_id': DeliverySeed.discountId('student'),
            'prep_time_minutes': 9,
          }),
        );
        expect(r.status, 200);
        final s = BranchDeliverySettings.fromJson(
          r.json! as Map<String, Object?>,
        );
        expect(s.outsideOverride, 'closed');
        expect(s.maxRoadDistanceMeters, 4200);
        expect(s.pickupDiscountId, DeliverySeed.discountId('student'));
        expect(row['prep_time_minutes'], 9);
        // A branch with no row yet gets one.
        b.db['delivery_settings'].removeWhere(
          (r) => r['branch_id'] == SeedIds.zamalek,
        );
        await _send(
          b,
          'PUT',
          DeliveryRoutes.settings,
          body: _settingsBody(SeedIds.zamalek, {'prep_time_minutes': 5}),
        );
        final again = await _send(
          b,
          'GET',
          DeliveryRoutes.settings,
          query: {'branch_id': SeedIds.zamalek},
        );
        expect((again.json! as Map)['prep_time_minutes'], 5);
      },
    );

    test('400s: negative fee or prep, distance 0, auto-reject 0, a bad '
        'time, an inactive or unknown discount', () async {
      final b = setupMockServer();
      Future<String> err(Map<String, Object?> x) async {
        final r = await _send(
          b,
          'PUT',
          DeliveryRoutes.settings,
          body: _settingsBody(SeedIds.heliopolis, x),
        );
        expect(r.status, 400, reason: '$x');
        return _error(r);
      }

      expect(
        await err({'pickup_fee': -1}),
        _words(MockResponse.badRequest('channel fees must be >= 0')),
      );
      expect(
        await err({'prep_time_minutes': -1}),
        _words(MockResponse.badRequest('prep_time_minutes must be >= 0')),
      );
      expect(
        await err({'max_road_distance_meters': 0}),
        _words(MockResponse.badRequest('max_road_distance_meters must be > 0')),
      );
      expect(await err({'auto_reject_minutes': 0}), contains('auto_reject'));
      expect(
        await err({'in_mall_open_time': 'abc:00'}),
        contains('Json deserialize error'),
      );
      expect(
        await err({
          'outside_discount_id': DeliverySeed.discountId('opening-week'),
        }),
        _words(MockResponse.badRequest('Discount not found or inactive')),
      );
      expect(
        await err({'outside_discount_id': mockUuid('discount:gone')}),
        _words(MockResponse.badRequest('Discount not found or inactive')),
      );
    });

    test('needs delivery.settings.edit and the branch', () async {
      final b = setupMockServer();
      var r = await _send(
        b,
        'PUT',
        DeliveryRoutes.settings,
        body: _settingsBody(SeedIds.maadi),
        as: Persona.limited,
      );
      expect(r.status, 403);
      r = await _send(
        b,
        'PUT',
        DeliveryRoutes.settings,
        body: _settingsBody(SeedIds.maadi),
        as: Persona.manager,
      );
      expect(
        _error(r),
        _words(MockResponse.forbidden('Not assigned to this branch')),
      );
      r = await _send(
        b,
        'PUT',
        DeliveryRoutes.settings,
        body: _settingsBody(SeedIds.zamalek),
        as: Persona.manager,
      );
      expect(r.status, 200);
    });
  });

  group('zones', () {
    test(
      'list: the branch\'s rings closest first, the spec\'s fields only',
      () async {
        final b = setupMockServer();
        final r = await _send(
          b,
          'GET',
          DeliveryRoutes.zones,
          query: {'branch_id': SeedIds.heliopolis},
        );
        final rows = (r.json! as List).cast<Map<String, Object?>>();
        expect(
          [for (final z in rows) z['max_road_distance_meters']],
          [2000, 4000, 6000],
        );
        expect(rows.first.keys.toSet(), {
          'id',
          'branch_id',
          'name',
          'name_translations',
          'max_road_distance_meters',
          'fee',
          'is_active',
        });
        final zam = await _send(
          b,
          'GET',
          DeliveryRoutes.zones,
          query: {'branch_id': SeedIds.zamalek},
        );
        expect(zam.json, isEmpty);
      },
    );

    test(
      'create 201 and listed; 400 for distance 0 or a negative fee; '
      '409 for a taken distance; omitted translations stored as null',
      () async {
        final b = setupMockServer();
        var r = await _send(
          b,
          'POST',
          DeliveryRoutes.zones,
          body: _zone(SeedIds.zamalek, 1500),
        );
        expect(r.status, 201);
        r = await _send(
          b,
          'POST',
          DeliveryRoutes.zones,
          body: _zone(SeedIds.zamalek, 0),
        );
        expect(
          _error(r),
          _words(
            MockResponse.badRequest('max_road_distance_meters must be > 0'),
          ),
        );
        r = await _send(
          b,
          'POST',
          DeliveryRoutes.zones,
          body: _zone(SeedIds.zamalek, 2000, fee: -1),
        );
        expect(_error(r), _words(MockResponse.badRequest('fee must be >= 0')));
        r = await _send(
          b,
          'POST',
          DeliveryRoutes.zones,
          body: _zone(SeedIds.zamalek, 1500),
        );
        expect(r.status, 409);
        r = await _send(
          b,
          'POST',
          DeliveryRoutes.zones,
          body: {..._zone(SeedIds.zamalek, 3000)}..remove('name_translations'),
        );
        expect(r.status, 201);
        expect((r.json! as Map).containsKey('name_translations'), isTrue);
        expect((r.json! as Map)['name_translations'], isNull);
        final list = await _send(
          b,
          'GET',
          DeliveryRoutes.zones,
          query: {'branch_id': SeedIds.zamalek},
        );
        expect(list.json, hasLength(2));
      },
    );

    test('update: 200; 409 against another ring, not itself; 404 for a '
        'ring of another branch', () async {
      final b = setupMockServer();
      final id = DeliverySeed.zoneId('heliopolis', 1);
      var r = await _send(
        b,
        'PATCH',
        '/delivery/zones/$id',
        body: _zone(SeedIds.heliopolis, 2000, fee: 1800),
      );
      expect(r.status, 200);
      expect((r.json! as Map)['fee'], 1800);
      r = await _send(
        b,
        'PATCH',
        '/delivery/zones/$id',
        body: _zone(SeedIds.heliopolis, 4000),
      );
      expect(r.status, 409);
      r = await _send(
        b,
        'PATCH',
        '/delivery/zones/$id',
        body: _zone(SeedIds.maadi, 9000),
      );
      expect(_error(r), _words(MockResponse.notFound('Zone not found')));
    });

    test('delete: 204 and gone; 404 the second time; caps per verb', () async {
      final b = setupMockServer();
      final id = DeliverySeed.zoneId('maadi', 2);
      var r = await _send(
        b,
        'DELETE',
        '/delivery/zones/$id',
        query: {'branch_id': SeedIds.maadi},
        as: Persona.limited,
      );
      expect(r.status, 403);
      r = await _send(
        b,
        'DELETE',
        '/delivery/zones/$id',
        query: {'branch_id': SeedIds.maadi},
        as: Persona.owner,
      );
      expect(r.status, 204);
      expect(b.db[DeliverySeed.zonesTable].find(id), isNull);
      r = await _send(
        b,
        'DELETE',
        '/delivery/zones/$id',
        query: {'branch_id': SeedIds.maadi},
      );
      expect(r.status, 404);
      r = await _send(
        b,
        'POST',
        DeliveryRoutes.zones,
        body: _zone(SeedIds.maadi, 7000),
        as: Persona.limited,
      );
      expect(r.status, 403);
    });
  });

  test(
    'GET /discounts: the org\'s seven, by name, with the legacy value',
    () async {
      final b = setupMockServer();
      final r = await _send(
        b,
        'GET',
        DeliveryRoutes.discounts,
        query: {'org_id': SeedIds.sabahOrg},
      );
      final rows = [
        for (final d in r.json! as List)
          Discount.fromJson(d as Map<String, Object?>),
      ];
      expect(
        [for (final d in rows) d.name],
        [
          'Corporate: Vodafone',
          'Late Order Apology',
          'Loyalty Welcome',
          'Manager Comp',
          'Opening Week',
          'Staff Meal',
          'Student Discount',
        ],
      );
      expect(
        [for (final d in rows) d.value],
        [13, 5000, 2500, 100, 20, 50, 15],
      );
      final other = await _send(
        b,
        'GET',
        DeliveryRoutes.discounts,
        query: {'org_id': SeedIds.nakhlaOrg},
      );
      expect(other.status, 403);
    },
  );

  group('pure rules', () {
    DeliveryZone z(int m) => DeliveryZone(
      branchId: SeedIds.maadi,
      fee: 0,
      id: 'z$m',
      isActive: true,
      maxRoadDistanceMeters: m,
      name: 'z$m',
      nameTranslations: const {},
    );

    test('numberZones: closest first, 1-based', () {
      final n = numberZones([z(3000), z(500), z(1200)]);
      expect(
        [for (final x in n) (x.number, x.zone.maxRoadDistanceMeters)],
        [(1, 500), (2, 1200), (3, 3000)],
      );
    });

    test('defaultZoneKm: farthest + 1, or 1; kmToMeters rounds', () {
      expect(defaultZoneKm(const []), 1);
      expect(defaultZoneKm([z(2500), z(6000)]), 7);
      expect(defaultZoneKm([z(2250)]), 3.25);
      expect(kmToMeters(7.25), 7250);
      expect(kmToMeters(0.0005), 1);
    });

    test('timeFromField: HH:MM → HH:MM:00, empty → null', () {
      expect(timeFromField('09:30'), '09:30:00');
      expect(timeFromField(''), isNull);
    });

    test('discountLabel: name · percent or money; Arabic name in Arabic', () {
      final pct = Discount(
        createdAt: DateTime.utc(2026),
        dtype: 'percentage',
        id: 'a',
        isActive: true,
        name: 'Student Discount',
        nameTranslations: const {'ar': 'خصم الطلاب'},
        orgId: SeedIds.sabahOrg,
        updatedAt: DateTime.utc(2026),
        value: 15,
      );
      final fixed = Discount(
        createdAt: DateTime.utc(2026),
        dtype: 'fixed',
        id: 'b',
        isActive: true,
        name: 'Loyalty Welcome',
        nameTranslations: const {},
        orgId: SeedIds.sabahOrg,
        updatedAt: DateTime.utc(2026),
        value: 2500,
      );
      const en = DashFormat(
        lang: 'en',
        timezone: 'Africa/Cairo',
        currency: 'EGP',
      );
      const ar = DashFormat(
        lang: 'ar',
        timezone: 'Africa/Cairo',
        currency: 'EGP',
      );
      expect(discountLabel(pct, 'en', en), 'Student Discount · 15%');
      expect(discountLabel(pct, 'ar', ar), 'خصم الطلاب · 15%');
      expect(discountLabel(fixed, 'en', en), 'Loyalty Welcome · EGP 25.00');
      expect(
        discountLabel(fixed, 'ar', ar),
        'Loyalty Welcome · ${ar.fmtMoney(2500)}',
      );
    });

    test('DeliveryForm: the distance rule and the body\'s explicit nulls', () {
      final f = DeliveryForm.from(DeliverySeed.defaults(SeedIds.maadi));
      expect(f.distanceOk, isTrue, reason: 'never set');
      f.maxDistanceEdited = true;
      expect(f.distanceOk, isFalse, reason: 'emptied');
      f.maxDistance = 0;
      expect(f.distanceOk, isFalse);
      f.maxDistance = 1;
      expect(f.distanceOk, isTrue);
      f.maxDistance = null;
      f.maxDistanceEdited = false;
      f[DeliveryChannel.pickup].fee = 12.345;
      final body =
          jsonDecode(jsonEncode(f.toInput(SeedIds.maadi).toJson()))
              as Map<String, Object?>;
      expect(body['pickup_fee'], 1235);
      expect(body['prep_time_minutes'], 20);
      for (final k in [
        'in_mall_open_time',
        'pickup_close_time',
        'max_road_distance_meters',
        'umbrella_discount_id',
      ]) {
        expect(body.containsKey(k), isTrue, reason: k);
        expect(body[k], isNull, reason: k);
      }
      expect(body.containsKey('auto_reject_minutes'), isFalse);
      expect(DeliveryForm.feeOk(null), isTrue);
      expect(DeliveryForm.feeOk(double.nan), isFalse);
      expect(DeliveryForm.prepOk(-1), isFalse);
    });
  });
}
