/// The combo editor's mock backend (`/menu/combos/:comboId`), behaving as
/// MadarRust's `src/combos/handlers.rs` and `src/uploads/handlers.rs`:
///
/// - `GET /combos/{id}` (`menu.items.read`, at `branch_id` when sent): the
///   org's live combo, else 404 "Combo not found"; an id that is not a UUID
///   is a 400, as actix's path extractor answers;
/// - `POST /combos` / `PUT /combos/{id}` (`menu.combos.edit`): the body
///   checked as `validate` does (400 "A combo needs a name", 400 coded
///   `COMBO_SLOTS_REQUIRED`, `COMBO_SLOT_INVALID {slot_index, field}`,
///   `COMBO_CHOICE_NOT_ALLOWED`, `COMBO_NESTED`, the windows' rules as
///   `COMBO_SLOT_INVALID {window_index, field}`), then stored: the combo as
///   a `menu_items` row of `kind: combo`, its slots and windows in the area's
///   `combo_specs` (slot and choice ids kept when sent, so an update diffs
///   in place); 201 / 200 with the `Combo`;
/// - `POST /combos/economics` (`menu.items.read` at `branch_id`): the draft
///   analysed by `analyseCombo`, nothing saved;
/// - `POST /uploads/menu-items/{menu_item_id}` (`menu.items.edit`, same org,
///   a multipart `image`): accepted for processing; the answer keeps the OLD
///   `image_url`. Registered only when no other area answers it.
///
/// The pick lists and the delete are the area's shared handlers
/// (`shared_mocks.dart`).
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'offers_rules.dart';

/// Every route this file answers, for the tests' coverage check.
const List<(String, String)> comboEditorMockRoutes = [
  ('GET', '/combos/{id}'),
  ('POST', '/combos'),
  ('PUT', '/combos/{id}'),
  ('POST', '/combos/economics'),
  ('POST', '/uploads/menu-items/{menu_item_id}'),
];

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

void registerComboEditorMocks(MockServer server, MockDb db) {
  final items = db.table(OffersTables.menuItems);
  final specs = db.table(OffersTables.comboSpecs);

  String uuidParam(MockRequest req, String name) {
    final id = req.param(name);
    if (!_uuid.hasMatch(id)) req.badRequest('can not parse "$id" to a Uuid');
    return id;
  }

  MockRow liveCombo(MockRequest req, String id) {
    final r = items.find(id);
    if (r == null ||
        r['org_id'] != req.orgId ||
        r['kind'] != 'combo' ||
        r['deleted_at'] != null) {
      req.notFound('Combo not found');
    }
    return r;
  }

  server.on('GET', '/combos/{id}', (req) {
    final branchId = req.q('branch_id');
    req.requireCap('menu.items.read', branchId: branchId);
    final id = uuidParam(req, 'id');
    return MockResponse.ok(
      comboJson(db, liveCombo(req, id), branchId: branchId),
    );
  });

  server.on('POST', '/combos', (req) {
    req.requireCap('menu.combos.edit');
    final org = req.orgId!;
    final body = req.json;
    _validate(req, db, org, body);
    final id = db.newId(OffersTables.menuItems);
    final now = db.nowIso;
    final row = items.insert({
      'id': id,
      'org_id': org,
      ..._itemFields(body),
      'kind': 'combo',
      'image_url': null,
      'default_milk_addon_id': null,
      'deleted_at': null,
      'created_at': now,
      'updated_at': now,
    }, timestamps: false);
    specs.insert(_spec(db, id, body), timestamps: false);
    return MockResponse.created(comboJson(db, row));
  });

  server.on('PUT', '/combos/{id}', (req) {
    req.requireCap('menu.combos.edit');
    final org = req.orgId!;
    final id = uuidParam(req, 'id');
    final row = liveCombo(req, id);
    final body = req.json;
    _validate(req, db, org, body);
    row
      ..addAll(_itemFields(body))
      ..['updated_at'] = db.nowIso;
    final spec = _spec(db, id, body);
    final old = specs.find(id);
    if (old == null) {
      specs.insert(spec, timestamps: false);
    } else {
      old.addAll(spec);
    }
    return MockResponse.ok(comboJson(db, row));
  });

  server.on('POST', '/combos/economics', (req) {
    final body = req.json;
    final branchId = body['branch_id'] as String?;
    req.requireCap('menu.items.read', branchId: branchId);
    // `draft_slots`: the draft's ids kept, a fresh one for each new row.
    final slots = [
      for (final s in _maps(body['slots']))
        {
          ...s,
          'id': s['id'] ?? db.newId('combo_slots'),
          'choices': [
            for (final c in _maps(s['choices']))
              {...c, 'id': c['id'] ?? db.newId('combo_choices')},
          ],
        },
    ];
    return MockResponse.ok(
      analyseCombo(
        db,
        orgId: req.orgId!,
        branchId: branchId,
        price: (body['price'] as num?)?.toInt() ?? 0,
        slots: slots,
      ),
    );
  });

  const upload = '/uploads/menu-items/{menu_item_id}';
  if (!server.handles('POST', upload)) {
    server.on('POST', upload, (req) {
      req.requireCap('menu.items.edit');
      final id = uuidParam(req, 'menu_item_id');
      final row = items.find(id);
      if (row == null || row['deleted_at'] != null) {
        req.notFound('Menu item not found');
      }
      if (!req.persona.isPlatform && row['org_id'] != req.orgId) {
        req.fail(
          MockResponse.forbidden('Menu item belongs to a different org'),
        );
      }
      if (req.file('image') == null) req.badRequest('No image field');
      return MockResponse.ok({
        'image_url': row['image_url'],
        'asset_job_id': db.newId('asset_jobs'),
        'status': 'processing',
      });
    });
  }
}

List<Map<String, Object?>> _maps(Object? list) => [
  for (final e in (list as List<Object?>? ?? const []))
    if (e is Map<String, Object?>) e,
];

/// The `menu_items` columns a combo write sets.
MockRow _itemFields(Map<String, Object?> b) => {
  'category_id': b['category_id'],
  'name': (b['name']! as String).trim(),
  'name_translations': b['name_translations'] ?? const <String, Object?>{},
  'description': b['description'],
  'description_translations':
      b['description_translations'] ?? const <String, Object?>{},
  'base_price': b['price'],
  'is_active': b['is_active'] ?? true,
};

/// The combo's slots and windows as stored (`write_children`): ids kept
/// when sent, choices named after their item or category.
MockRow _spec(MockDb db, String comboId, Map<String, Object?> b) {
  (String, Object?) named(Map<String, Object?> c) {
    final item = c['menu_item_id'];
    final row = item is String
        ? db.table(OffersTables.menuItems).find(item)
        : db.table(OffersTables.categories).find('${c['category_id']}');
    return (
      (row?['name'] as String?) ?? '',
      row?['name_translations'] ?? const <String, Object?>{},
    );
  }

  return {
    'id': comboId,
    'slots': [
      for (final (i, s) in _maps(b['slots']).indexed)
        {
          'id': s['id'] ?? db.newId('combo_slots'),
          'name': (s['name']! as String).trim(),
          'name_translations':
              s['name_translations'] ?? const <String, Object?>{},
          'sort': s['sort'] ?? i,
          'min': s['min'],
          'max': s['max'],
          'default_item_id': s['default_item_id'],
          'default_size_label': s['default_size_label'],
          'choices': [
            for (final (j, c) in _maps(s['choices']).indexed)
              {
                'id': c['id'] ?? db.newId('combo_choices'),
                'menu_item_id': c['menu_item_id'],
                'category_id': c['category_id'],
                'name': named(c).$1,
                'name_translations': named(c).$2,
                'surcharge': c['surcharge'] ?? 0,
                'included_size_label': c['included_size_label'],
                'size_surcharges': [..._maps(c['size_surcharges'])],
                'sort': c['sort'] ?? j,
              },
          ],
        },
    ],
    'windows': [
      for (final w in _maps(b['windows']))
        {
          'id': db.newId('sale_windows'),
          'branch_id': w['branch_id'],
          'weekdays': w['weekdays'] ?? 127,
          'starts_at': _hhmm(w['starts_at']),
          'ends_at': _hhmm(w['ends_at']),
          'valid_from': w['valid_from'],
          'valid_to': w['valid_to'],
        },
    ],
  };
}

/// The database keeps `HH:MM`.
String? _hhmm(Object? v) =>
    v is String && v.length >= 5 ? v.substring(0, 5) : null;

/// `COMBO_SLOT_INVALID` about slot [i] (or window [i] with [window]).
Never _slotInvalid(
  MockRequest req,
  int i,
  String field, {
  bool window = false,
}) => req.fail(
  MockResponse.error(
    400,
    window
        ? 'Check window ${i + 1} ($field).'
        : 'Check slot ${i + 1} ($field).',
    code: 'COMBO_SLOT_INVALID',
    vars: {window ? 'window_index' : 'slot_index': i, 'field': field},
  ),
);

Never _coded(MockRequest req, String code, String reason, Object vars) =>
    req.fail(MockResponse.error(400, reason, code: code, vars: vars));

int? _secs(Object? t) {
  if (t is! String) return null;
  final m = RegExp(r'^(\d{2}):(\d{2})(?::(\d{2}))?$').firstMatch(t);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  final s = int.parse(m.group(3) ?? '0');
  if (h > 23 || min > 59 || s > 59) return null;
  return h * 3600 + min * 60 + s;
}

/// Every check a combo write passes before anything is written.
void _validate(MockRequest req, MockDb db, String org, Map<String, Object?> b) {
  final name = b['name'];
  if (name is! String || name.trim().isEmpty) {
    req.badRequest('A combo needs a name');
  }
  if (((b['price'] as num?) ?? 0) < 0) {
    req.badRequest("The price can't be negative");
  }
  final slots = _maps(b['slots']);
  if (slots.isEmpty) {
    _coded(req, 'COMBO_SLOTS_REQUIRED', 'Add at least one slot.', const {});
  }
  final items = db.table(OffersTables.menuItems);
  final cats = db.table(OffersTables.categories);
  MockRow? item(Object? id) {
    final r = items.find('$id');
    return r != null && r['org_id'] == org && r['deleted_at'] == null
        ? r
        : null;
  }

  for (final (i, s) in slots.indexed) {
    if (((s['name'] as String?) ?? '').trim().isEmpty) {
      _slotInvalid(req, i, 'name');
    }
    final min = (s['min'] as num?)?.toInt() ?? -1;
    final max = (s['max'] as num?)?.toInt() ?? -1;
    if (min < 0 || min > 10) _slotInvalid(req, i, 'min');
    if (max < 1 || max > 10) _slotInvalid(req, i, 'max');
    if (min > max) _slotInvalid(req, i, 'min');
    final choices = _maps(s['choices']);
    if (choices.isEmpty) _slotInvalid(req, i, 'choices');
    final seenItems = <Object?>{};
    final seenCats = <Object?>{};
    for (final c in choices) {
      final extras = _maps(c['size_surcharges']);
      if (((c['surcharge'] as num?) ?? 0) < 0 ||
          extras.any((x) => ((x['surcharge'] as num?) ?? 0) < 0)) {
        _slotInvalid(req, i, 'surcharge');
      }
      final itemId = c['menu_item_id'];
      final catId = c['category_id'];
      if (itemId != null && catId == null) {
        final row = item(itemId);
        if (row == null) {
          _coded(
            req,
            'COMBO_CHOICE_NOT_ALLOWED',
            "That item can't be chosen "
                'here.',
            {'slot_index': i, 'menu_item_id': itemId},
          );
        }
        if (row['kind'] == 'combo') {
          _coded(req, 'COMBO_NESTED', "A combo can't contain another combo.", {
            'slot_index': i,
            'menu_item_id': itemId,
          });
        }
        if (!seenItems.add(itemId)) _slotInvalid(req, i, 'choices');
      } else if (itemId == null && catId != null) {
        final cat = cats.find('$catId');
        if (cat == null || cat['org_id'] != org || cat['deleted_at'] != null) {
          _coded(
            req,
            'COMBO_CHOICE_NOT_ALLOWED',
            "That category can't be "
                'chosen here.',
            {'slot_index': i, 'category_id': catId},
          );
        }
        if (!seenCats.add(catId)) _slotInvalid(req, i, 'choices');
      } else {
        _slotInvalid(req, i, 'choices');
      }
    }
    final d = s['default_item_id'];
    if (d != null) {
      final row = item(d);
      final admitted =
          row != null &&
          (row['kind'] ?? 'item') == 'item' &&
          choices.any(
            (c) =>
                c['menu_item_id'] == d ||
                (c['menu_item_id'] == null &&
                    c['category_id'] != null &&
                    c['category_id'] == row['category_id']),
          );
      if (!admitted) _slotInvalid(req, i, 'default_item_id');
    }
  }

  for (final (i, w) in _maps(b['windows']).indexed) {
    final days = (w['weekdays'] as num?)?.toInt() ?? 127;
    if (days < 1 || days > 127) {
      _slotInvalid(req, i, 'weekdays', window: true);
    }
    final from = w['starts_at'];
    final to = w['ends_at'];
    if (from != null && _secs(from) == null) {
      _slotInvalid(req, i, 'starts_at', window: true);
    }
    if (to != null && _secs(to) == null) {
      _slotInvalid(req, i, 'ends_at', window: true);
    }
    if (from != null && to == null) {
      _slotInvalid(req, i, 'ends_at', window: true);
    }
    if (from == null && to != null) {
      _slotInvalid(req, i, 'starts_at', window: true);
    }
    if (from != null && to != null && _secs(from) == _secs(to)) {
      _slotInvalid(req, i, 'ends_at', window: true);
    }
    final vf = w['valid_from'];
    final vt = w['valid_to'];
    if (vf is String && vt is String && vf.compareTo(vt) > 0) {
      _slotInvalid(req, i, 'valid_to', window: true);
    }
    final branch = w['branch_id'];
    if (branch != null) {
      final row = db['branches'].find('$branch');
      if (row == null || row['org_id'] != org || row['deleted_at'] != null) {
        _slotInvalid(req, i, 'branch_id', window: true);
      }
    }
  }
}
