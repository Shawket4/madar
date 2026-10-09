// The combos list's mock backend against hand-computed answers: what
// `GET /combos` returns for the area seed (figures worked out from the core
// seed's prices and the area's unit costs), its filters, paging, validation
// and refusals, and the menu-item delete a combo goes through.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

({MockServer server, DashboardApi api, MockDb db}) _api([
  Persona persona = Persona.owner,
]) {
  final s = combosServer(persona: persona);
  return (server: s.server, api: DashboardApi(s.server), db: s.db);
}

Future<int> _status(Future<Object?> call) async {
  try {
    await call;
    return 200;
  } on ApiException catch (e) {
    return e.status;
  }
}

Future<ApiException> _error(Future<Object?> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  throw StateError('no error');
}

List<String> _names(PaginatedCombos p) => [for (final c in p.data) c.name];

void main() {
  group('GET /combos', () {
    test('the seed: every combo by name, with its figures', () async {
      final o = _api();
      final p = await o.api.menu.listCombos();
      expect(_names(p), [
        'Brunch for Two',
        'Coffee & Cookie',
        'Iced Afternoon',
        "Kids' Cocoa & Cookie",
        'Morning Croissant Combo',
        'Ramadan Suhoor Box',
      ]);
      expect((p.page, p.perPage, p.total, p.totalPages), (1, 50, 6, 1));

      final cookie = p.data[1];
      // Americano Regular EGP 85 (cost 15) + cookie EGP 55 (cost 18) at 120:
      // margin (120 − 33) / 120 = 72.5 %, a saving of 20, nothing to warn.
      expect(cookie.id, comboId('coffee-cookie'));
      expect(cookie.price, 12000);
      expect(cookie.categoryId, isNull);
      expect(cookie.slotCount, 2);
      expect(cookie.isFixed, isTrue);
      expect(cookie.isActive, isTrue);
      expect(cookie.availableNow, isTrue);
      expect(cookie.marginDefault, '0.7250');
      expect(cookie.warningCount, 0);
      expect(cookie.windowCount, 0);
      expect(cookie.nameTranslations['ar'], 'قهوة وكوكيز');

      final kids = p.data[3];
      // Hot chocolate EGP 120 (cost 31) + cookie EGP 55 (cost 18) at 150:
      // (150 − 49) / 150 = 67.33 %. Fri/Sat 10:00–18:00 only; the seed's
      // now is Thursday 10:00 in Cairo.
      expect(kids.marginDefault, '0.6733');
      expect(kids.isFixed, isTrue);
      expect(kids.windowCount, 1);
      expect(kids.availableNow, isFalse);
      expect(kids.categoryId, OffersSeed.category('dessert'));

      final suhoor = p.data[5];
      expect(suhoor.isActive, isFalse);
      expect(suhoor.availableNow, isFalse);
      expect(suhoor.slotCount, 3);
      expect(suhoor.isFixed, isFalse);
    });

    test('on sale follows the clock: Iced Afternoon at 16:00, Kids\' Cocoa '
        'on a Friday', () async {
      final o = _api();
      Future<bool> now(String key) async => (await o.api.menu.listCombos())
          .data
          .firstWhere((c) => c.id == comboId(key))
          .availableNow;
      expect(await now('iced-afternoon'), isFalse);
      o.db.clock.advance(const Duration(hours: 6)); // Thursday 16:00
      expect(await now('iced-afternoon'), isTrue);
      o.db.clock.advance(const Duration(hours: 19)); // Friday 11:00
      expect(await now('kids-cocoa'), isTrue);
      expect(await now('iced-afternoon'), isFalse);
    });

    test('q: the English or the Arabic name, any case, % and _ literal', () async {
      final o = _api();
      expect(_names(await o.api.menu.listCombos(q: 'COOKIE')), [
        'Coffee & Cookie',
        "Kids' Cocoa & Cookie",
      ]);
      expect(_names(await o.api.menu.listCombos(q: 'كوكيز')), [
        'Coffee & Cookie',
        "Kids' Cocoa & Cookie",
      ]);
      expect(_names(await o.api.menu.listCombos(q: '  brunch ')), [
        'Brunch for Two',
      ]);
      expect((await o.api.menu.listCombos(q: '%')).data, isEmpty);
      expect((await o.api.menu.listCombos(q: '_')).data, isEmpty);
      expect((await o.api.menu.listCombos(q: '   ')).total, 6);
    });

    test('category_id and is_active narrow it', () async {
      final o = _api();
      expect(
        _names(
          await o.api.menu.listCombos(
            categoryId: OffersSeed.category('breakfast'),
          ),
        ),
        ['Brunch for Two', 'Ramadan Suhoor Box'],
      );
      expect(
        _names(
          await o.api.menu.listCombos(
            categoryId: OffersSeed.category('breakfast'),
            isActive: true,
          ),
        ),
        ['Brunch for Two'],
      );
      expect(_names(await o.api.menu.listCombos(isActive: false)), [
        'Ramadan Suhoor Box',
      ]);
    });

    test('pages: 25 a page, the last one short; per_page clamped 1–200; a '
        'page past the end is empty', () async {
      final o = _api();
      addCombos(o.db, 30);
      final p1 = await o.api.menu.listCombos(page: 1, perPage: 25);
      expect((p1.data.length, p1.total, p1.totalPages), (25, 36, 2));
      final p2 = await o.api.menu.listCombos(page: 2, perPage: 25);
      expect(p2.data.length, 11);
      expect(p2.data.last.name, 'Ramadan Suhoor Box');
      expect((await o.api.menu.listCombos(page: 3, perPage: 25)).data, isEmpty);
      expect((await o.api.menu.listCombos(perPage: 500)).perPage, 200);
      expect((await o.api.menu.listCombos(perPage: 0)).perPage, 1);
      expect((await o.api.menu.listCombos(page: 0)).page, 1);
    });

    test('an org with none: zero pages', () async {
      final o = _api();
      clearCombos(o.db);
      final p = await o.api.menu.listCombos(page: 1, perPage: 25);
      expect(p.data, isEmpty);
      expect((p.total, p.totalPages), (0, 0));
    });

    test('malformed query values are a 400, as actix answers', () async {
      final o = _api();
      Future<int> ask(Map<String, List<String>> query) => _status(
        o.server.send(ApiRequest(method: 'GET', path: '/combos', query: query)),
      );
      expect(
        await ask({
          'category_id': ['bakery'],
        }),
        400,
      );
      expect(
        await ask({
          'is_active': ['yes'],
        }),
        400,
      );
      expect(
        await ask({
          'page': ['two'],
        }),
        400,
      );
    });

    test('a platform admin with no org picked is refused', () async {
      final o = _api(Persona.platform);
      final e = await _error(o.api.menu.listCombos());
      expect(e.status, 403);
      expect(e.message, 'Forbidden: A super admin must scope this to an org');
    });

    test('deleted combos and plain items never show', () async {
      final o = _api();
      OffersSeed.loadInto(o.db);
      o.db.table(OffersTables.menuItems).find(comboId('suhoor-box'))![
          'deleted_at'] = '2026-10-01T09:00:00.000Z';
      final p = await o.api.menu.listCombos();
      expect(p.total, 5);
      expect(_names(p), isNot(contains('Ramadan Suhoor Box')));
      expect(_names(p), isNot(contains('Café Latte')));
    });
  });

  group('DELETE /menu-items/{id}', () {
    test('needs menu.items.delete; a delete takes the combo off the list', () async {
      final limited = _api(Persona.limited);
      final e = await _error(
        limited.api.menu.deleteMenuItem(id: comboId('iced-afternoon')),
      );
      expect(e.status, 403);
      expect(e.code, isNull, reason: 'uncoded: the web words it itself');

      final o = _api();
      await o.api.menu.deleteMenuItem(id: comboId('iced-afternoon'));
      final p = await o.api.menu.listCombos();
      expect(p.total, 5);
      expect(_names(p), isNot(contains('Iced Afternoon')));
      // Again: still 204, as the backend answers.
      await o.api.menu.deleteMenuItem(id: comboId('iced-afternoon'));
    });
  });
}
