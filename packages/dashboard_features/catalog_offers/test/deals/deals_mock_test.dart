// The `/deals` handlers against MadarRust `src/deals/handlers.rs`: gates per
// persona (and at a branch), org scoping, every DEAL_INVALID field, the
// list's order and filter, and state that persists (create, update, the
// branch overrides, the soft delete).
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

typedef _Answer = ({int status, Object? json, ApiException? error});

/// Sends [method] [path] as [persona] (with [body]) straight to the
/// handlers; a refusal comes back as its status and exception.
Future<_Answer> _send(
  MockServer server,
  String method,
  String path, {
  Object? body,
  Map<String, String> headers = const {},
}) async {
  try {
    final r = await server.send(
      ApiRequest(method: method, path: path, body: body, headers: headers),
    );
    final text = utf8.decode(r.bodyBytes);
    return (
      status: r.status,
      json: text.isEmpty ? null : jsonDecode(text),
      error: null,
    );
  } on ApiException catch (e) {
    return (status: e.status, json: null, error: e);
  }
}

Map<String, Object?> _cat(String key, [String? size]) => {
  'menu_item_id': null,
  'category_id': OffersSeed.category(key),
  'size_label': size,
};

Map<String, Object?> _item(String key, [String? size]) => {
  'menu_item_id': OffersSeed.item(key),
  'category_id': null,
  'size_label': size,
};

/// A valid N-for-price body; [over] replaces fields.
Map<String, Object?> _nFor([Map<String, Object?> over = const {}]) => {
  'name': 'Any 2 bites for 90',
  'name_translations': <String, Object?>{},
  'kind': 'n_for_price',
  'qty': 2,
  'price': 9000,
  'get_qty': null,
  'get_percent': null,
  'max_per_order': null,
  'sort': 5,
  'is_active': true,
  'pool': [_cat('bakery')],
  'reward_pool': <Object?>[],
  'windows': <Object?>[],
  ...over,
};

/// A valid buy-get body; [over] replaces fields.
Map<String, Object?> _buyGet([Map<String, Object?> over = const {}]) => _nFor({
  'name': 'Buy 2 coffees, get a cookie',
  'kind': 'buy_get',
  'qty': 2,
  'price': null,
  'get_qty': 1,
  'get_percent': 100,
  'pool': [_cat('hot')],
  'reward_pool': [_item('cookie')],
  ...over,
});

Map<String, Object?> _window([Map<String, Object?> over = const {}]) => {
  'branch_id': null,
  'weekdays': 127,
  'starts_at': null,
  'ends_at': null,
  'valid_from': null,
  'valid_to': null,
  ...over,
};

List<Map<String, Object?>> _list(_Answer a) => [
  for (final r in a.json! as List) (r as Map).cast<String, Object?>(),
];

void main() {
  test('OFFR-DEA-005/006 GET /deals: the org\'s live deals by sort, name; '
      'is_active filters; nothing internal leaves', () async {
    final s = dealsServer();
    final all = _list(await _send(s.server, 'GET', '/deals'));
    expect([for (final d in all) d['name']], seededNames);
    for (final d in all) {
      expect(d.containsKey('org_id'), isFalse);
      expect(d.containsKey('deleted_at'), isFalse);
    }
    final coffee = all[1];
    expect(coffee['branch_overrides'], [
      {'branch_id': SeedIds.zamalek, 'is_active': false},
    ]);
    expect(
      (all[2]['windows']! as List).single,
      containsPair('starts_at', '12:00'),
    );

    final off = await s.server.send(
      const ApiRequest(
        method: 'GET',
        path: '/deals',
        query: {
          'is_active': ['false'],
        },
      ),
    );
    final offList = jsonDecode(utf8.decode(off.bodyBytes)) as List;
    expect(
      [for (final d in offList) (d as Map)['name']],
      ['Juice trio for 270'],
    );
 
    // Same sort: names as the list orders them (alef forms folded).
    final deals = s.db.table(OffersTables.deals);
    deals.find(dealId('pastry-pair'))!['name'] = 'آيس لاتيه';
    deals.find(dealId('juice-trio'))!
      ..['name'] = 'اسبريسو'
      ..['sort'] = 0;
    final again = _list(await _send(s.server, 'GET', '/deals'));
    expect([for (final d in again.take(2)) d['name']], ['اسبريسو', 'آيس لاتيه']);
  });

  test('OFFR-DEA-016 gates: menu.items.read lists; every write needs '
      'menu.deals.edit', () async {
    for (final p in [Persona.manager, Persona.limited]) {
      final s = dealsServer(persona: p);
      expect(_list(await _send(s.server, 'GET', '/deals')), hasLength(5));
      final id = dealId('pastry-pair');
      final writes = [
        await _send(s.server, 'POST', '/deals', body: _nFor()),
        await _send(s.server, 'PUT', '/deals/$id', body: _nFor()),
        await _send(s.server, 'DELETE', '/deals/$id'),
        await _send(
          s.server,
          'PUT',
          '/deals/$id/branches/${SeedIds.zamalek}',
          body: {'is_active': true},
        ),
        await _send(s.server, 'DELETE', '/deals/$id/branches/${SeedIds.maadi}'),
      ];
      for (final w in writes) {
        expect(w.status, 403, reason: '$p');
        expect(w.error!.message, contains('menu.deals.edit'));
      }
      expect(_list(await _send(s.server, 'GET', '/deals')), hasLength(5));
    }
  });

  test(
    'a platform admin with no org picked is refused; with one, served',
    () async {
      final s = dealsServer(persona: Persona.platform);
      final none = await _send(s.server, 'GET', '/deals');
      expect(none.status, 403);
      expect(none.error!.message, contains('scope this to an org'));
      final pinned = await _send(
        s.server,
        'GET',
        '/deals',
        headers: {'X-Org-Id': SeedIds.sabahOrg},
      );
      expect(_list(pinned), hasLength(5));
      final other = await _send(
        s.server,
        'GET',
        '/deals',
        headers: {'X-Org-Id': SeedIds.nakhlaOrg},
      );
      expect(_list(other), isEmpty);
    },
  );

  test(
    'OFFR-DEA-044 POST: 201 with the stored rule; the next list has it',
    () async {
      final s = dealsServer();
      final created = await _send(
        s.server,
        'POST',
        '/deals',
        body: _nFor({
          'name': '  Any 2 bites for 90 ',
          'windows': [
            _window({
              'weekdays': 96,
              'starts_at': '08:00:00',
              'ends_at': '12:00',
            }),
          ],
        }),
      );
      expect(created.status, 201);
      final rule = (created.json! as Map).cast<String, Object?>();
      expect(rule['name'], 'Any 2 bites for 90');
      expect(rule['branch_overrides'], isEmpty);
      expect(
        (rule['windows']! as List).single,
        containsPair('starts_at', '08:00'),
      );
      expect(DealRule.fromJson(rule).price, 9000);
      final names = [
        for (final d in _list(await _send(s.server, 'GET', '/deals')))
          d['name'],
      ];
      expect(names.last, 'Any 2 bites for 90');
    },
  );

  test('OFFR-DEA-045 PUT replaces the rule; branch PUT/DELETE keep the '
      'overrides, sorted by branch', () async {
    final s = dealsServer();
    final id = dealId('coffee-cookie-free');
    final put = await _send(
      s.server,
      'PUT',
      '/deals/$id',
      body: _buyGet({'name': 'Renamed', 'sort': 1, 'max_per_order': 3}),
    );
    expect(put.status, 200);
    expect((put.json! as Map)['max_per_order'], 3);
    expect(
      (await _send(
        s.server,
        'PUT',
        '/deals/$id/branches/${SeedIds.newCairo}',
        body: {'is_active': true},
      )).status,
      204,
    );
    await _send(
      s.server,
      'PUT',
      '/deals/$id/branches/${SeedIds.zamalek}',
      body: {'is_active': true},
    );
    var row = _list(
      await _send(s.server, 'GET', '/deals'),
    ).firstWhere((d) => d['id'] == id);
    final expected =
        [
          {'branch_id': SeedIds.newCairo, 'is_active': true},
          {'branch_id': SeedIds.zamalek, 'is_active': true},
        ]..sort(
          (a, b) =>
              (a['branch_id']! as String).compareTo(b['branch_id']! as String),
        );
    expect(row['name'], 'Renamed');
    expect(row['branch_overrides'], expected);
    expect(
      (await _send(
        s.server,
        'DELETE',
        '/deals/$id/branches/${SeedIds.zamalek}',
      )).status,
      204,
    );
    row = _list(
      await _send(s.server, 'GET', '/deals'),
    ).firstWhere((d) => d['id'] == id);
    expect(row['branch_overrides'], [
      {'branch_id': SeedIds.newCairo, 'is_active': true},
    ]);

    // An unknown branch, a body without is_active.
    expect(
      (await _send(
        s.server,
        'PUT',
        '/deals/$id/branches/${mockUuid('branch:nowhere')}',
        body: {'is_active': true},
      )).status,
      404,
    );
    expect(
      (await _send(
        s.server,
        'PUT',
        '/deals/$id/branches/${SeedIds.maadi}',
        body: <String, Object?>{},
      )).status,
      400,
    );
  });

  test('OFFR-DEA-015 DELETE soft-deletes: gone from the list, then 404 for '
      'every route', () async {
    final s = dealsServer();
    final id = dealId('juice-trio');
    expect((await _send(s.server, 'DELETE', '/deals/$id')).status, 204);
    expect(_list(await _send(s.server, 'GET', '/deals')), hasLength(4));
    expect(s.db.table(OffersTables.deals).find(id)!['deleted_at'], isNotNull);
    for (final a in [
      await _send(s.server, 'DELETE', '/deals/$id'),
      await _send(s.server, 'PUT', '/deals/$id', body: _nFor()),
      await _send(
        s.server,
        'PUT',
        '/deals/$id/branches/${SeedIds.maadi}',
        body: {'is_active': true},
      ),
    ]) {
      expect(a.status, 404);
      expect(a.error!.message, contains('Deal not found'));
    }
  });

  group('OFFR-DEA-046 DEAL_INVALID names the field', () {
    final cases = <String, (Map<String, Object?>, String)>{
      'blank name': (_nFor({'name': '   '}), 'name'),
      'N of 1': (_nFor({'qty': 1}), 'qty'),
      'N of 21': (_nFor({'qty': 21}), 'qty'),
      'no price': (_nFor({'price': null}), 'price'),
      'a negative price': (_nFor({'price': -1}), 'price'),
      'a get on N for a price': (_nFor({'get_qty': 1}), 'get_qty'),
      'a percent on N for a price': (_nFor({'get_percent': 50}), 'get_percent'),
      'a reward list on N for a price': (
        _nFor({
          'reward_pool': [_item('cookie')],
        }),
        'reward_pool',
      ),
      'buy 0': (_buyGet({'qty': 0}), 'qty'),
      'a price on buy-get': (_buyGet({'price': 100}), 'price'),
      'get 21': (_buyGet({'get_qty': 21}), 'get_qty'),
      'no get': (_buyGet({'get_qty': null}), 'get_qty'),
      'percent 0': (_buyGet({'get_percent': 0}), 'get_percent'),
      'percent 101': (_buyGet({'get_percent': 101}), 'get_percent'),
      'an unknown kind': (_nFor({'kind': 'bogo'}), 'kind'),
      'a cap of 0': (_nFor({'max_per_order': 0}), 'max_per_order'),
      'an empty pool': (_nFor({'pool': <Object?>[]}), 'pool'),
      'an entry naming both': (
        _nFor({
          'pool': [
            {
              'menu_item_id': OffersSeed.item('cookie'),
              'category_id': OffersSeed.category('bakery'),
              'size_label': null,
            },
          ],
        }),
        'pool',
      ),
      'an entry naming nothing': (
        _nFor({
          'pool': [
            {'menu_item_id': null, 'category_id': null, 'size_label': null},
          ],
        }),
        'pool',
      ),
      'a blank size': (
        _nFor({
          'pool': [_item('iced_latte', ' ')],
        }),
        'pool',
      ),
      'an unknown item': (
        _nFor({
          'pool': [
            {
              'menu_item_id': mockUuid('menu-item:gone'),
              'category_id': null,
              'size_label': null,
            },
          ],
        }),
        'pool',
      ),
      'a combo as an item': (
        _nFor({
          'pool': [
            {
              'menu_item_id': OffersSeed.comboId('morning-croissant'),
              'category_id': null,
              'size_label': null,
            },
          ],
        }),
        'pool',
      ),
      'an unknown reward category': (
        _buyGet({
          'reward_pool': [
            {
              'menu_item_id': null,
              'category_id': mockUuid('category:gone'),
              'size_label': null,
            },
          ],
        }),
        'reward_pool',
      ),
    };
    for (final MapEntry(key: what, value: (body, field)) in cases.entries) {
      test(what, () async {
        final s = dealsServer();
        final a = await _send(s.server, 'POST', '/deals', body: body);
        expect(a.status, 400);
        expect(a.error!.code, 'DEAL_INVALID');
        final vars = (a.error!.details! as Map)['vars'] as Map;
        expect(vars['field'], field);
        expect(_list(await _send(s.server, 'GET', '/deals')), hasLength(5));
      });
    }

    final windows = <String, (Map<String, Object?>, String)>{
      'no weekday': (_window({'weekdays': 0}), 'weekdays'),
      'a start alone': (_window({'starts_at': '08:00'}), 'ends_at'),
      'an end alone': (_window({'ends_at': '08:00'}), 'starts_at'),
      'the same hours': (
        _window({'starts_at': '08:00', 'ends_at': '08:00:00'}),
        'ends_at',
      ),
      'dates the wrong way': (
        _window({'valid_from': '2026-10-02', 'valid_to': '2026-10-01'}),
        'valid_to',
      ),
      'another org\'s branch': (
        _window({'branch_id': mockUuid('branch:nowhere')}),
        'branch_id',
      ),
    };
    for (final MapEntry(key: what, value: (window, field)) in windows.entries) {
      test('window: $what', () async {
        final s = dealsServer();
        final a = await _send(
          s.server,
          'POST',
          '/deals',
          body: _nFor({
            'windows': [_window(), window],
          }),
        );
        expect(a.status, 400);
        expect(a.error!.code, 'DEAL_INVALID');
        final vars = (a.error!.details! as Map)['vars'] as Map;
        expect(vars['field'], field);
        expect(vars['window_index'], 1);
      });
    }
  });
}
