/// The backend rules the area's mock handlers share, so the combos list, the
/// combo editor, its price check and the deals all derive the same answers
/// from the area seed (`area_seed.dart`):
///
/// - [windowMatches] / [windowsOpen]: `madar-catalog::sale_window` (a
///   half-open time range, crossing midnight when it ends before it starts;
///   weekday and dates judged on the day the window started; only the
///   all-branch windows and the given branch's apply; none = always open);
/// - [analyseCombo]: `combos/economics.rs` `analyse` (list value, cost and
///   margin of the default and the costliest picks, and the warnings);
/// - [comboJson] / [comboSummaryJson]: the `Combo` and `ComboSummary` the
///   backend answers, assembled from the `menu_items` row, the spec and the
///   analysis;
/// - [menuItemFullJson]: one row of `GET /menu-items?full=true`.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';

// ── Sale windows ──────────────────────────────────────────────────────────

/// The branch-local wall clock now (Cairo), as `DateTime.utc` fields.
DateTime offersWallNow(MockDb db) => MockClock.wall(db.clock.now);

int? _secondsOf(Object? time) {
  if (time is! String) return null;
  final parts = time.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final s = parts.length == 3 ? int.tryParse(parts[2]) : 0;
  if (h == null || m == null || s == null) return null;
  if (h > 23 || m > 59 || s > 59 || h < 0 || m < 0 || s < 0) return null;
  return h * 3600 + m * 60 + s;
}

DateTime? _day(Object? iso) {
  if (iso is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso.trim());
  if (m == null) return null;
  return DateTime.utc(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}

/// Whether window [w] (a `SaleWindow` JSON) covers the wall-clock [wall].
bool windowMatches(Map<String, Object?> w, DateTime wall) {
  final today = DateTime.utc(wall.year, wall.month, wall.day);
  final t = wall.hour * 3600 + wall.minute * 60 + wall.second;
  final hasStart = w['starts_at'] != null;
  final hasEnd = w['ends_at'] != null;
  DateTime startDay;
  if (!hasStart && !hasEnd) {
    startDay = today;
  } else if (hasStart && hasEnd) {
    final s = _secondsOf(w['starts_at']);
    final e = _secondsOf(w['ends_at']);
    if (s == null || e == null || s == e) return false;
    if (s < e) {
      if (t < s || t >= e) return false;
      startDay = today;
    } else if (t >= s) {
      startDay = today;
    } else if (t < e) {
      startDay = today.subtract(const Duration(days: 1));
    } else {
      return false;
    }
  } else {
    return false;
  }
  final weekdays = (w['weekdays'] as num?)?.toInt() ?? 127;
  final bit = startDay.weekday % 7; // Sunday = 0
  if (weekdays & (1 << bit) == 0) return false;
  final from = w['valid_from'];
  final to = w['valid_to'];
  final fromDay = from == null ? null : _day(from);
  final toDay = to == null ? null : _day(to);
  if ((from != null && fromDay == null) || (to != null && toDay == null)) {
    return false;
  }
  if (fromDay != null && startDay.isBefore(fromDay)) return false;
  if (toDay != null && startDay.isAfter(toDay)) return false;
  return true;
}

/// Whether something with [windows] is on sale at [branchId] (null = the
/// org) at [wall].
bool windowsOpen(
  List<Object?> windows,
  String? branchId,
  DateTime wall,
) {
  final applicable = [
    for (final w in windows.whereType<Map<String, Object?>>())
      if (w['branch_id'] == null ||
          (branchId != null && w['branch_id'] == branchId))
        w,
  ];
  if (applicable.isEmpty) return true;
  return applicable.any((w) => windowMatches(w, wall));
}

// ── Menu items ────────────────────────────────────────────────────────────

/// One active-or-not size of an item: the label and its price (piastres).
typedef OffersSize = ({String label, int price, bool active});

/// An item's sizes as `all_sizes` carries them: its `item_sizes` rows, or
/// the synthetic `one_size` row at `base_price` for a single-price item.
List<OffersSize> itemSizesOf(MockDb db, Map<String, Object?> item) {
  final id = item['id'];
  final rows = db
      .table(OffersTables.itemSizes)
      .where((s) => s['menu_item_id'] == id);
  if (rows.isEmpty) {
    return [
      (
        label: oneSizeLabel,
        price: (item['base_price'] as num?)?.toInt() ?? 0,
        active: true,
      ),
    ];
  }
  return [
    for (final s in rows)
      (
        label: s['label']! as String,
        price: (s['price_override'] as num?)?.toInt() ?? 0,
        active: s['is_active'] != false,
      ),
  ];
}

/// `GET /menu-items?full=true`'s row for [item]: the `MenuItem` fields plus
/// `sizes` (the real size rows), `all_sizes` (with the synthetic `one_size`
/// row) and empty add-on, optional-field and recipe lists.
Map<String, Object?> menuItemFullJson(MockDb db, Map<String, Object?> item) {
  final id = item['id'];
  final real = db
      .table(OffersTables.itemSizes)
      .where((s) => s['menu_item_id'] == id);
  final all = real.isNotEmpty
      ? real
      : [
          {
            'id': mockUuid('size:$id:$oneSizeLabel'),
            'menu_item_id': id,
            'label': oneSizeLabel,
            'price_override': item['base_price'],
            'is_active': true,
          },
        ];
  return {
    ...item,
    'sizes': [...real],
    'all_sizes': [...all],
    'addon_slots': const <Object?>[],
    'allowed_addon_ids': const <Object?>[],
    'optional_fields': const <Object?>[],
    'recipes': const <Object?>[],
  };
}

/// Sellable items (`kind: item`, not deleted, switched on) of [orgId].
bool _live(Map<String, Object?>? row, String orgId) =>
    row != null &&
    row['org_id'] == orgId &&
    (row['kind'] ?? 'item') == 'item' &&
    row['deleted_at'] == null &&
    row['is_active'] != false;

// ── Combos ────────────────────────────────────────────────────────────────

/// The combos of [orgId] as `menu_items` rows (`kind: combo`, not deleted),
/// by name then id, as `GET /combos` orders them.
List<Map<String, Object?>> comboRows(MockDb db, String orgId) {
  final rows = db
      .table(OffersTables.menuItems)
      .where(
        (r) =>
            r['org_id'] == orgId &&
            r['kind'] == 'combo' &&
            r['deleted_at'] == null,
      );
  rows.sort((a, b) {
    final c = (a['name']! as String).compareTo(b['name']! as String);
    return c != 0 ? c : (a['id']! as String).compareTo(b['id']! as String);
  });
  return rows;
}

/// The combo's slots and windows (empty when it has no spec row yet).
Map<String, Object?> comboSpec(MockDb db, String id) =>
    db.table(OffersTables.comboSpecs).find(id) ??
    {'id': id, 'slots': const <Object?>[], 'windows': const <Object?>[]};

List<Map<String, Object?>> _maps(Object? list) => [
  for (final e in (list as List<Object?>? ?? const []))
    if (e is Map<String, Object?>) e,
];

/// The wire's fraction string ("0.5933"), four places, half away from zero.
String rateFraction(num v) => ((v * 10000).round() / 10000).toStringAsFixed(4);

/// The org's minimum combo margin (null = no warning).
String? comboMinMargin(MockDb db, String orgId) =>
    db.table(OffersTables.orgSettings).find(orgId)?['combo_min_margin']
        as String?;

/// The unit cost of [itemId] at [sizeLabel], or null when it is not known.
int? unitCost(MockDb db, String itemId, String sizeLabel) =>
    (db.table(OffersTables.itemCosts).find('$itemId|$sizeLabel')?['cost']
            as num?)
        ?.toInt();

/// The economics of [slots] (`ComboSlot`/`ComboSlotWrite` JSON) sold at
/// [price] (piastres), at [branchId] or the org, as `ComboEconomics` JSON.
/// [emptySlots] receives the ids of slots with nothing to sell now.
Map<String, Object?> analyseCombo(
  MockDb db, {
  required String orgId,
  String? branchId,
  required int price,
  required List<Map<String, Object?>> slots,
  Set<Object?>? emptySlots,
}) {
  final items = db.table(OffersTables.menuItems);
  final minRaw = comboMinMargin(db, orgId);
  final min = minRaw == null ? null : num.tryParse(minRaw);
  final warnings = <Map<String, Object?>>[];
  final warned = <String>{};
  void warn(String code, Object? key, Map<String, Object?> vars) {
    if (warned.add('$code|$key')) warnings.add({'code': code, 'vars': vars});
  }

  List<String> members(Object? categoryId) => [
    for (final r in items.rows)
      if (r['category_id'] == categoryId && _live(r, orgId)) r['id']! as String,
  ];

  var listDefault = 0;
  var listMin = 0;
  var listMax = 0;
  int? costDefault = 0;
  int? costMax = 0;
  for (final slot in slots) {
    final choices = _maps(slot['choices']);
    for (final c in choices) {
      final i = c['menu_item_id'];
      if (i is String && !_live(items.find(i), orgId)) {
        warn('CHOICE_INACTIVE', i, {'menu_item_id': i});
      }
    }
    final cands = <({String item, int price, int? cost})>[];
    for (final c in choices) {
      final itemId = c['menu_item_id'];
      final ids = itemId is String
          ? [itemId]
          : (c['category_id'] is String
                ? members(c['category_id'])
                : const <String>[]);
      for (final id in ids) {
        final row = items.find(id);
        if (!_live(row, orgId) || cands.any((k) => k.item == id)) continue;
        final sizes = [
          for (final s in itemSizesOf(db, row!))
            if (s.active) s,
        ]..sort((a, b) => a.price.compareTo(b.price));
        if (sizes.isEmpty) continue;
        final wanted = c['included_size_label'];
        final OffersSize inc;
        if (wanted is String && wanted.isNotEmpty) {
          final hit = sizes.where((s) => s.label == wanted);
          if (hit.isEmpty) continue;
          inc = hit.first;
        } else {
          inc = sizes.first;
        }
        final cost = unitCost(db, id, inc.label);
        if (cost == null) warn('COST_UNKNOWN', id, {'menu_item_id': id});
        cands.add((item: id, price: inc.price, cost: cost));
      }
    }
    if (cands.isEmpty) {
      warn('SLOT_EMPTY_NOW', slot['id'], {'slot_id': slot['id']});
      emptySlots?.add(slot['id']);
      continue;
    }
    final lo = (slot['min'] as num?)?.toInt() ?? 0;
    final hi = (slot['max'] as num?)?.toInt() ?? 0;
    final defId = slot['default_item_id'];
    final def = cands.firstWhere(
      (c) => c.item == defId,
      orElse: () => cands.first,
    );
    final prices = cands.map((c) => c.price);
    listDefault += lo * def.price;
    listMin += lo * prices.reduce((a, b) => a < b ? a : b);
    listMax += hi * prices.reduce((a, b) => a > b ? a : b);
    if (costDefault != null && def.cost != null) {
      costDefault += lo * def.cost!;
    } else if (lo != 0) {
      costDefault = null;
    }
    final worst = cands.every((c) => c.cost != null)
        ? cands.map((c) => c.cost!).reduce((a, b) => a > b ? a : b)
        : null;
    costMax = costMax != null && worst != null ? costMax + hi * worst : null;
  }

  double? margin(int? cost) =>
      cost == null || price <= 0 ? null : (price - cost) / price;
  final marginDefault = margin(costDefault);
  final marginWorst = margin(costMax);
  final judged = marginWorst ?? marginDefault;
  if (min != null && judged != null && judged < min) {
    warnings.insert(0, {
      'code': 'MARGIN_BELOW_MIN',
      'vars': {'margin': rateFraction(judged), 'min': rateFraction(min)},
    });
  }
  if (price >= listDefault) {
    warnings.add({'code': 'NO_SAVING', 'vars': <String, Object?>{}});
  }
  return {
    'branch_id': branchId,
    'price': price,
    'list_default': listDefault,
    'list_min': listMin,
    'list_max': listMax,
    'cost_default': costDefault,
    'cost_max': costMax,
    'margin_default': marginDefault == null
        ? null
        : rateFraction(marginDefault),
    'margin_worst': marginWorst == null ? null : rateFraction(marginWorst),
    'min_margin': min == null ? null : rateFraction(min),
    'saving_default': listDefault - price,
    'warnings': warnings,
  };
}

/// The fixed-bundle rule (`isFixedShape`): every slot picks exactly its one
/// item choice.
bool isFixedSlots(List<Map<String, Object?>> slots) =>
    slots.isNotEmpty &&
    slots.every((s) {
      final choices = _maps(s['choices']);
      return s['min'] == s['max'] &&
          choices.length == 1 &&
          choices.single['menu_item_id'] != null &&
          choices.single['category_id'] == null;
    });

/// Whether the combo [row] is on sale on the till now at [branchId] (null =
/// the org): switched on, a window open, and every slot that must be picked
/// (`min > 0`) has something to sell.
bool comboAvailableNow(
  MockDb db,
  Map<String, Object?> row, {
  String? branchId,
  Map<String, Object?>? spec,
  Set<Object?>? emptySlots,
}) {
  if (row['is_active'] == false) return false;
  final s = spec ?? comboSpec(db, row['id']! as String);
  if (!windowsOpen(_maps(s['windows']), branchId, offersWallNow(db))) {
    return false;
  }
  final empty = emptySlots ?? <Object?>{};
  if (emptySlots == null) {
    analyseCombo(
      db,
      orgId: row['org_id']! as String,
      branchId: branchId,
      price: (row['base_price'] as num?)?.toInt() ?? 0,
      slots: _maps(s['slots']),
      emptySlots: empty,
    );
  }
  return !_maps(
    s['slots'],
  ).any((slot) => ((slot['min'] as num?) ?? 0) > 0 && empty.contains(slot['id']));
}

/// `GET /combos/{id}`'s `Combo` for the `menu_items` row [row].
Map<String, Object?> comboJson(
  MockDb db,
  Map<String, Object?> row, {
  String? branchId,
}) {
  final spec = comboSpec(db, row['id']! as String);
  final slots = _maps(spec['slots']);
  final empty = <Object?>{};
  final economics = analyseCombo(
    db,
    orgId: row['org_id']! as String,
    branchId: branchId,
    price: (row['base_price'] as num?)?.toInt() ?? 0,
    slots: slots,
    emptySlots: empty,
  );
  return {
    'id': row['id'],
    'kind': 'combo',
    'name': row['name'],
    'name_translations': row['name_translations'] ?? const <String, Object?>{},
    'category_id': row['category_id'],
    'description': row['description'],
    'description_translations':
        row['description_translations'] ?? const <String, Object?>{},
    'is_active': row['is_active'] ?? true,
    'price': row['base_price'] ?? 0,
    'image_url': row['image_url'],
    'is_fixed': isFixedSlots(slots),
    'available_now': comboAvailableNow(
      db,
      row,
      branchId: branchId,
      spec: spec,
      emptySlots: empty,
    ),
    'windows': _maps(spec['windows']),
    'slots': slots,
    'economics': economics,
    'created_at': row['created_at'],
    'updated_at': row['updated_at'],
  };
}

/// One row of `GET /combos` (`ComboSummary`) for the `menu_items` row [row].
Map<String, Object?> comboSummaryJson(
  MockDb db,
  Map<String, Object?> row,
) {
  final c = comboJson(db, row);
  final economics = c['economics']! as Map<String, Object?>;
  return {
    'id': c['id'],
    'name': c['name'],
    'name_translations': c['name_translations'],
    'category_id': c['category_id'],
    'image_url': c['image_url'],
    'price': c['price'],
    'slot_count': (c['slots']! as List).length,
    'is_fixed': c['is_fixed'],
    'is_active': c['is_active'],
    'available_now': c['available_now'],
    'margin_default': economics['margin_default'],
    'warning_count': (economics['warnings']! as List).length,
    'window_count': (c['windows']! as List).length,
  };
}
