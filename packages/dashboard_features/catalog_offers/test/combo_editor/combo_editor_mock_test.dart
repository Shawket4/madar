// The combo editor's mock handlers against the backend's rules
// (`combos/handlers.rs`, `uploads/handlers.rs`), with hand-computed figures.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_catalog_offers/src/mock/combo_editor_mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late MockServer server;
  late MockDb db;
  late DashboardApi api;

  void as(Persona p) {
    final s = editorServer(persona: p);
    server = s.server;
    db = s.db;
    api = DashboardApi(server);
  }

  setUp(() => as(Persona.owner));

  final croissant = OffersSeed.item('croissant');
  final americano = OffersSeed.item('americano');

  /// Butter Croissant (75, cost 26) + Americano Regular (85, cost 15) for
  /// EGP 150.
  Map<String, Object?> breakfast({Map<String, Object?> extra = const {}}) => {
    'name': ' Breakfast deal ',
    'name_translations': {'ar': 'فطور'},
    'category_id': OffersSeed.category('bakery'),
    'description': null,
    'description_translations': <String, Object?>{},
    'is_active': true,
    'price': 15000,
    'windows': <Object?>[],
    'slots': [
      {
        'name': 'Main',
        'name_translations': <String, Object?>{},
        'sort': 0,
        'min': 1,
        'max': 1,
        'default_item_id': croissant,
        'default_size_label': null,
        'choices': [
          {
            'menu_item_id': croissant,
            'category_id': null,
            'surcharge': 0,
            'included_size_label': null,
            'size_surcharges': <Object?>[],
            'sort': 0,
          },
        ],
      },
      {
        'name': 'Drink',
        'name_translations': <String, Object?>{},
        'sort': 1,
        'min': 1,
        'max': 1,
        'default_item_id': null,
        'default_size_label': null,
        'choices': [
          {
            'menu_item_id': americano,
            'category_id': null,
            'surcharge': 0,
            'included_size_label': 'Regular',
            'size_surcharges': [
              {'size_label': 'Large', 'surcharge': 1000},
            ],
            'sort': 0,
          },
        ],
      },
    ],
    ...extra,
  };

  Future<ApiException> refused(Future<Object?> call) async {
    try {
      await call;
    } on ApiException catch (e) {
      return e;
    }
    fail('expected a refusal');
  }

  test('every route is registered', () {
    for (final (m, t) in comboEditorMockRoutes) {
      expect(server.handles(m, t), isTrue, reason: '$m $t');
    }
  });

  test(
    'OFFR-CED-072 create stores a combo menu item and reads it back',
    () async {
      final c = await api.menu.createCombo(
        body: ComboWrite.fromJson(breakfast()),
      );
      expect(server.calls.last.status, 201);
      expect(c.kind, 'combo');
      expect(c.name, 'Breakfast deal');
      expect(c.price, 15000);
      expect(c.isFixed, isTrue);
      expect(c.slots.map((s) => s.name), ['Main', 'Drink']);
      expect(c.slots.every((s) => s.id.isNotEmpty), isTrue);
      expect(c.slots[1].choices.single.sizeSurcharges.single.surcharge, 1000);
      expect(c.slots[0].choices.single.name, 'Butter Croissant');
      // 75 + 85 bought separately; cost 26 + 15.
      expect(c.economics.listDefault, 16000);
      expect(c.economics.savingDefault, 1000);
      expect(c.economics.costDefault, 4100);
      expect(c.economics.marginDefault, '0.7267');
      expect(c.economics.warnings, isEmpty);

      final again = await api.menu.getCombo(id: c.id);
      expect(again.toJson(), c.toJson());
      final row = db.table(OffersTables.menuItems).find(c.id)!;
      expect(row['kind'], 'combo');
      expect(row['base_price'], 15000);
    },
  );

  test(
    'OFFR-CED-073 update keeps the slot and choice ids it is sent',
    () async {
      final id = OffersSeed.comboId('coffee-cookie');
      final before = await api.menu.getCombo(id: id);
      final body = ComboDraftJson.of(before)..['price'] = 16000;
      final after = await api.menu.updateCombo(
        id: id,
        body: ComboWrite.fromJson(body),
      );
      expect(after.price, 16000);
      expect(after.slots.map((s) => s.id), before.slots.map((s) => s.id));
      expect(
        after.slots.first.choices.single.id,
        before.slots.first.choices.single.id,
      );
    },
  );

  test(
    'OFFR-CED-062 the price check analyses the draft, saving nothing',
    () async {
      final before = db.table(OffersTables.menuItems).length;
      final e = await api.menu.comboEconomics(
        body: ComboEconomicsRequest.fromJson({
          ...breakfast(),
          'branch_id': null,
        }),
      );
      expect(e.price, 15000);
      expect(e.listDefault, 16000);
      expect(e.listMin, 16000);
      expect(e.listMax, 16000);
      expect(e.costDefault, 4100);
      expect(e.costMax, 4100);
      expect(e.marginWorst, '0.7267');
      expect(e.minMargin, '0.5500');
      expect(db.table(OffersTables.menuItems).length, before);

      // Priced over the items' value: a warning, never a refusal.
      final dear = await api.menu.comboEconomics(
        body: ComboEconomicsRequest.fromJson({
          ...breakfast(),
          'price': 20000,
          'branch_id': SeedIds.maadi,
        }),
      );
      expect(dear.branchId, SeedIds.maadi);
      expect(dear.warnings.map((w) => w.code), ['NO_SAVING']);
    },
  );

  test('OFFR-CED-062 the price check at a branch the person is not assigned '
      'to is refused', () async {
    as(Persona.manager);
    final e = await refused(
      api.menu.comboEconomics(
        body: ComboEconomicsRequest.fromJson({
          ...breakfast(),
          'branch_id': SeedIds.maadi,
        }),
      ),
    );
    expect(e.status, 403);
  });

  test('OFFR-CED-075 the write refusals, as the backend words them', () async {
    Future<ApiException> create(Map<String, Object?> extra) => refused(
      api.menu.createCombo(body: ComboWrite.fromJson(breakfast(extra: extra))),
    );

    final noName = await create({'name': '  '});
    expect(
      (noName.status, noName.message),
      (400, 'Bad request: A combo needs a name'),
    );

    final noSlots = await create({'slots': <Object?>[]});
    expect((noSlots.status, noSlots.code), (400, 'COMBO_SLOTS_REQUIRED'));

    final slots = (breakfast()['slots']! as List).cast<Map<String, Object?>>();
    final overMax = await create({
      'slots': [
        {...slots[0], 'min': 3, 'max': 2},
      ],
    });
    expect(overMax.code, 'COMBO_SLOT_INVALID');
    expect((overMax.details! as Map)['vars'], {
      'slot_index': 0,
      'field': 'min',
    });

    final nested = await create({
      'slots': [
        {
          ...slots[0],
          'default_item_id': null,
          'choices': [
            {
              'menu_item_id': OffersSeed.comboId('kids-cocoa'),
              'category_id': null,
            },
          ],
        },
      ],
    });
    expect(nested.code, 'COMBO_NESTED');

    final stray = await create({
      'slots': [
        {...slots[1], 'default_item_id': croissant},
      ],
    });
    expect((stray.details! as Map)['vars'], {
      'slot_index': 0,
      'field': 'default_item_id',
    });

    final noDays = await create({
      'windows': [
        {'weekdays': 0},
      ],
    });
    expect(noDays.code, 'COMBO_SLOT_INVALID');
    expect((noDays.details! as Map)['vars'], {
      'window_index': 0,
      'field': 'weekdays',
    });

    as(Persona.manager);
    final denied = await create(const {});
    expect(denied.status, 403);
  });

  test('OFFR-CED-080 an unknown combo is 404 "Combo not found"; a malformed '
      'id is a 400', () async {
    final missing = await refused(
      api.menu.getCombo(id: mockUuid('no-such-combo')),
    );
    expect(
      (missing.status, missing.message),
      (404, 'Not found: Combo not found'),
    );
    final bad = await refused(api.menu.getCombo(id: 'abc'));
    expect(bad.status, 400);
    expect(bad.message, startsWith('Bad request: can not parse'));
    // A plain item is not a combo.
    final item = await refused(api.menu.getCombo(id: croissant));
    expect(item.status, 404);
  });

  test('OFFR-CED-074/084 the image upload is accepted for processing (the '
      'old image kept); without menu.items.edit it is refused', () async {
    final id = OffersSeed.comboId('coffee-cookie');
    final body = UploadImageMultipart(
      image: ApiFilePart(
        field: 'image',
        filename: 'meal.png',
        bytes: tinyPng,
        contentType: 'image/png',
      ),
    );
    final ok = await api.uploads.uploadMenuItemImage(
      menuItemId: id,
      body: body,
    );
    expect(ok.status, 'processing');
    expect(ok.imageUrl, isNull);
    expect(ok.assetJobId, isNotEmpty);

    as(Persona.manager);
    final e = await refused(
      api.uploads.uploadMenuItemImage(menuItemId: id, body: body),
    );
    expect(e.status, 403);
  });
}

/// A loaded combo as the `ComboWrite` JSON a Save sends (ids kept).
extension ComboDraftJson on Combo {
  static Map<String, Object?> of(Combo c) => {
    'name': c.name,
    'name_translations': c.nameTranslations,
    'category_id': c.categoryId,
    'description': c.description,
    'description_translations': c.descriptionTranslations,
    'is_active': c.isActive,
    'price': c.price,
    'windows': [for (final w in c.windows) w.toJson()],
    'slots': [for (final s in c.slots) s.toJson()],
  };
}
