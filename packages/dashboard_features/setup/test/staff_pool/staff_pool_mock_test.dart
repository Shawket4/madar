// The Staff drinks mock against the backend's rules (MadarRust
// `src/staff_pool/settings.rs`), and the pane's pure rules
// (`staff_pool_data.dart`, the web's `form-schema.ts`) against hand-computed
// answers.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_setup/src/staff_pool/staff_pool_data.dart';
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
  String path = splSettings,
  Map<String, String>? query,
}) async {
  if (as != null) b.server.persona = as;
  try {
    final r = await b.server.send(
      ApiRequest(
        method: method,
        path: path,
        query: {
          'branch_id': ?(branch == null ? null : [branch]),
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

String _words(MockResponse r) => MockServer.toApiException(r).message;

Map<String, Object?> _body({
  String? branch,
  int allowance = 2,
  List<String>? items,
  bool enabled = true,
}) => {
  'org_id': SeedIds.sabahOrg,
  'branch_id': branch,
  'enabled': enabled,
  'daily_allowance': allowance,
  'eligible_item_ids': items ?? [itemId('latte')],
};

void main() {
  group('GET /staff-pool/settings', () {
    test('the seed the reports area also reads: org 3, Heliopolis 4, '
        'Zamalek 5, New Cairo off, Maadi following', () async {
      final b = splServer();
      final org = await _send(b, 'GET');
      expect(org.json, {
        'org_id': SeedIds.sabahOrg,
        'branch_id': null,
        'enabled': true,
        'daily_allowance': 3,
        'eligible_item_ids': StaffPoolSettingsMock.eligibleItemIds,
      });
      expect(StaffPoolSettingsMock.eligibleItemIds, hasLength(8));
      final helio = await _send(b, 'GET', branch: SeedIds.heliopolis);
      expect((helio.json! as Map)['daily_allowance'], 4);
      expect((helio.json! as Map)['branch_id'], SeedIds.heliopolis);
      final zam = await _send(b, 'GET', branch: SeedIds.zamalek);
      expect((zam.json! as Map)['daily_allowance'], 5);
      final nc = await _send(b, 'GET', branch: SeedIds.newCairo);
      expect((nc.json! as Map)['enabled'], false);
      // Maadi has no row: the org's, reported under Maadi (load_effective).
      final maadi = await _send(b, 'GET', branch: SeedIds.maadi);
      expect(maadi.json, {...org.json! as Map, 'branch_id': SeedIds.maadi});
    });

    test('with no rows at all: off, nothing allowed', () async {
      final b = splServer();
      b.db[StaffPoolSettingsMock.table].removeWhere((_) => true);
      final org = await _send(b, 'GET');
      expect(org.json, StaffPoolSettingsMock.defaults(SeedIds.sabahOrg, null));
      final maadi = await _send(b, 'GET', branch: SeedIds.maadi);
      expect((maadi.json! as Map)['branch_id'], SeedIds.maadi);
      expect((maadi.json! as Map)['eligible_item_ids'], isEmpty);
    });

    test(
      'the till capability reads it; a branch must be known and held',
      () async {
        final b = splServer(persona: Persona.manager);
        expect((await _send(b, 'GET', branch: SeedIds.zamalek)).status, 200);
        final other = await _send(b, 'GET', branch: SeedIds.heliopolis);
        expect(other.status, 403);
        expect(
          other.error,
          _words(MockResponse.forbidden('Not assigned to this branch')),
        );
        final limited = await _send(b, 'GET', as: Persona.limited);
        expect(limited.status, 403);
        expect(
          limited.error,
          _words(MockResponse.denied('orders.staff_drink.record')),
        );
        final unknown = await _send(
          b,
          'GET',
          branch: mockUuid('branch:nowhere'),
          as: Persona.owner,
        );
        expect(unknown.status, 404);
        expect((await _send(b, 'GET', branch: 'not-a-uuid')).status, 400);
      },
    );

    test('a platform admin with no organisation is told to pick one', () async {
      final b = splServer(persona: Persona.platform);
      b.server.platformOrgId = null;
      final r = await _send(b, 'GET');
      expect(r.status, 400);
      expect(
        r.error,
        _words(MockResponse.badRequest('Pick an organisation first')),
      );
    });
  });

  group('PUT /staff-pool/settings', () {
    test("saves a branch's own row, which the next read returns", () async {
      final b = splServer();
      final r = await _send(
        b,
        'PUT',
        body: _body(branch: SeedIds.maadi, allowance: 6),
      );
      expect(r.status, 200);
      expect((r.json! as Map)['branch_id'], SeedIds.maadi);
      final back = await _send(b, 'GET', branch: SeedIds.maadi);
      expect((back.json! as Map)['daily_allowance'], 6);
      expect((back.json! as Map)['eligible_item_ids'], [itemId('latte')]);
      // The org's own row is untouched.
      expect(savedRow(b.db, null)!['daily_allowance'], 3);
    });

    test('updates in place: one row per scope', () async {
      final b = splServer();
      final n = b.db[StaffPoolSettingsMock.table].length;
      await _send(
        b,
        'PUT',
        body: _body(allowance: 0, enabled: false, items: []),
      );
      expect(b.db[StaffPoolSettingsMock.table].length, n);
      final org = await _send(b, 'GET');
      expect(org.json, {
        'org_id': SeedIds.sabahOrg,
        'branch_id': null,
        'enabled': false,
        'daily_allowance': 0,
        'eligible_item_ids': <String>[],
      });
    });

    test('needs org.settings.edit; refuses a negative allowance and an item '
        'off the menu', () async {
      final b = splServer(persona: Persona.manager);
      final denied = await _send(
        b,
        'PUT',
        body: _body(branch: SeedIds.zamalek),
      );
      expect(denied.status, 403);
      expect(denied.error, _words(MockResponse.denied('org.settings.edit')));
      b.server.persona = Persona.owner;
      final negative = await _send(b, 'PUT', body: _body(allowance: -1));
      expect(negative.status, 400);
      expect(
        negative.error,
        _words(
          MockResponse.badRequest('A daily allowance cannot be less than zero'),
        ),
      );
      final gone = await _send(
        b,
        'PUT',
        body: _body(items: [itemId('latte'), mockUuid('menu-item:retired')]),
      );
      expect(gone.status, 400);
      expect(
        gone.error,
        _words(
          MockResponse.badRequest(
            "Some of those drinks are not on this organisation's menu any more",
          ),
        ),
      );
      // A repeated id counts once.
      final twice = await _send(
        b,
        'PUT',
        body: _body(items: [itemId('latte'), itemId('latte')]),
      );
      expect(twice.status, 200);
      expect((await _send(b, 'PUT', body: {'enabled': true})).status, 400);
    });
  });

  group('DELETE /staff-pool/settings', () {
    test(
      "removes a branch's own row; the branch then follows the org",
      () async {
        final b = splServer();
        final r = await _send(b, 'DELETE', branch: SeedIds.heliopolis);
        expect(r.status, 204);
        expect(savedRow(b.db, SeedIds.heliopolis), isNull);
        final back = await _send(b, 'GET', branch: SeedIds.heliopolis);
        expect((back.json! as Map)['daily_allowance'], 3);
      },
    );

    test('asks the capability before the branch', () async {
      final b = splServer(persona: Persona.manager);
      final denied = await _send(b, 'DELETE');
      expect(denied.error, _words(MockResponse.denied('org.settings.edit')));
      final missing = await _send(b, 'DELETE', as: Persona.owner);
      expect(missing.status, 400);
      expect(
        missing.error,
        _words(
          MockResponse.badRequest(
            'Name the branch whose override you want to remove',
          ),
        ),
      );
    });
  });

  test('GET /menu-items lists the org menu by name', () async {
    final b = splServer();
    final r = await _send(
      b,
      'GET',
      path: splMenu,
      query: {'org_id': SeedIds.sabahOrg},
    );
    final names = [
      for (final m in r.json! as List) (m as Map)['name'] as String,
    ];
    expect(names, isNotEmpty);
    expect(names, [...names]..sort());
  });

  group('the form rules (form-schema.ts)', () {
    test('the allowance: digits only, 0 to 1000, spaces trimmed', () {
      for (final ok in ['0', '3', ' 12 ', '1000']) {
        expect(allowanceOk(ok), isTrue, reason: ok);
      }
      for (final bad in [
        '',
        ' ',
        '-1',
        '1.5',
        '1e3',
        'abc',
        '1001',
        '٣',
        '99999999999999999999',
      ]) {
        expect(allowanceOk(bad), isFalse, reason: bad);
      }
    });

    test('the pool is off when switched off or with no items', () {
      expect(poolIsOff(enabled: true, itemIds: const []), isTrue);
      expect(poolIsOff(enabled: false, itemIds: const ['a']), isTrue);
      expect(poolIsOff(enabled: true, itemIds: const ['a']), isFalse);
    });

    test('from the wire and back: 0 for a missing allowance, the scope saved '
        'to, the items de-duplicated in order', () {
      final f = StaffPoolForm.from(
        const StaffPoolSettings(orgId: 'o', branchId: 'b'),
      );
      expect(
        f,
        const StaffPoolForm(enabled: false, allowance: '0', itemIds: []),
      );
      final w = f
          .copyWith(allowance: ' 7 ', itemIds: ['x', 'y', 'x'])
          .toWire(orgId: 'o');
      expect(w.toJson(), {
        'branch_id': null,
        'daily_allowance': 7,
        'eligible_item_ids': ['x', 'y'],
        'enabled': false,
        'org_id': 'o',
      });
      expect(f.toWire(orgId: 'o', branchId: 'b').branchId, 'b');
    });
  });
}
