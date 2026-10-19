/// `POST /menu/bulk` (`menu/bulk.rs`): the self-serve Foodics import the menu
/// import page sends, over the area's tables ([MenuTables]).
library;

import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

import '../area_seed.dart';

const String _oneSize = 'one_size';

void registerMenuImportMocks(MockServer server, MockDb db) {
  server.on('POST', '/menu/bulk', (req) => _bulkMenu(req, db));
}

/// The menu imports on record (`menu_imports`).
const String _imports = 'menu_imports';

/// Real imports one org may run in a day (`bulk::IMPORTS_PER_DAY`).
const int _importsPerDay = 20;

/// `bulk_menu` over the mock tables: madar-menu's checks (the same rules, run
/// through the bridge), the empty-menu rule for `add`, the typed sentence for
/// a real `replace`, the archive (items and categories stamped, groups
/// switched off), the writes and the day's cap. A dry run answers like the
/// real one and keeps nothing.
MockResponse _bulkMenu(MockRequest req, MockDb db) {
  final body = req.json;
  final mode = (body['mode'] as String?) ?? 'add';
  for (final cap in [
    'menu.categories.create',
    'menu.items.create',
    'menu.items.edit',
    if (mode == 'replace') ...['menu.categories.delete', 'menu.items.delete'],
  ]) {
    req.requireCap(cap);
  }
  final org = req.orgId;
  if (org == null) {
    req.fail(MockResponse.forbidden('A super admin must scope this to an org'));
  }
  final menu = body['menu'];
  if (menu is! Map) {
    req.badRequest('Json deserialize error: missing field `menu`');
  }
  final verdict =
      jsonDecode(rules.bulkValidate(menuJson: jsonEncode(menu)))
          as Map<String, Object?>;
  final err = verdict['Err'];
  if (err is Map<String, Object?>) {
    if (err['refusal'] == null) {
      req.badRequest('Json deserialize error: ${err['detail']}');
    }
    final version = err['refusal'] == 'unsupported_version';
    req.unprocessable(
      version
          ? 'This bulk menu version is not supported'
          : 'The menu cannot be imported',
      code: version ? 'BULK_MENU_UNSUPPORTED_VERSION' : 'BULK_MENU_INVALID',
      vars: err,
    );
  }
  final summary = verdict['Ok']! as Map<String, Object?>;
  final dryRun = req.q('dry_run') == 'true';
  bool mine(MockRow r) => r['org_id'] == org;

  if (!dryRun && db[_imports].rows.where(mine).length >= _importsPerDay) {
    req.fail(
      MockResponse.error(
        429,
        'An organization may import a menu $_importsPerDay times a day.',
        code: 'MENU_IMPORT_LIMIT',
      ),
    );
  }
  final liveCategories = db[MenuTables.categories].rows
      .where((c) => mine(c) && c['deleted_at'] == null)
      .toList();
  final liveItems = db[MenuTables.menuItems].rows
      .where((i) => mine(i) && i['deleted_at'] == null)
      .toList();
  final activeGroups = db[MenuTables.groups].rows
      .where((g) => mine(g) && g['is_active'] != false)
      .toList();
  Map<String, Object?>? archived;
  if (mode == 'add') {
    if (liveCategories.length + liveItems.length + activeGroups.length > 0) {
      req.fail(
        MockResponse.error(
          409,
          'The menu already has categories, items or groups; replace it instead.',
          code: 'MENU_NOT_EMPTY',
          vars: {
            'categories': liveCategories.length,
            'items': liveItems.length,
            'groups': activeGroups.length,
          },
        ),
      );
    }
  } else {
    if (!dryRun) {
      final name = db['orgs'].get(org)['name']! as String;
      final typed = (body['confirm'] as String?) ?? '';
      if (!rules.confirmsReplace(orgName: name, typed: typed)) {
        req.unprocessable(
          'Type the sentence shown to replace the whole menu.',
          code: 'MENU_REPLACE_NOT_CONFIRMED',
          vars: {
            'sentence_en': rules.replaceSentence(orgName: name, lang: 'en'),
            'sentence_ar': rules.replaceSentence(orgName: name, lang: 'ar'),
          },
        );
      }
    }
    archived = {
      'categories': liveCategories.length,
      'items': liveItems.length,
      'groups': activeGroups.length,
    };
  }
  if (dryRun) {
    return MockResponse.ok({
      'dry_run': true,
      'mode': mode,
      'summary': summary,
      'archived': archived,
      'import_id': null,
    });
  }

  // Put away what is there, the way the editors delete it.
  for (final r in [...liveItems, ...liveCategories]) {
    r['deleted_at'] = db.nowIso;
  }
  for (final g in activeGroups) {
    g['is_active'] = false;
  }
  _writeBulk(db, org, menu.cast<String, Object?>());
  final import = db[_imports].insert({
    'org_id': org,
    'mode': mode,
    'summary': summary,
    'archived': archived,
  });
  return MockResponse.created({
    'dry_run': false,
    'mode': mode,
    'summary': summary,
    'archived': archived,
    'import_id': import['id'],
  });
}

Map<String, Object?> _ar(Object? ar) =>
    ar is String && ar.trim().isNotEmpty ? {'ar': ar.trim()} : const {};

/// The bulk menu's rows, in the shapes the editors write.
void _writeBulk(MockDb db, String org, Map<String, Object?> menu) {
  List<Map<String, Object?>> list(Map<String, Object?> m, String k) =>
      ((m[k] as List?) ?? const []).cast<Map<String, Object?>>();
  Map<String, Object?> option(Map<String, Object?> o, int sort) => {
    'id': db.newId('modifier_options'),
    'name': (o['name']! as String).trim(),
    'name_translations': _ar(o['name_ar']),
    'price': (o['price']! as num).toInt(),
    'is_default': false,
    'is_active': o['is_active'] as bool? ?? true,
    'sort': sort,
    'replaces_ingredient_id': null,
    'recipe': <Map<String, Object?>>[],
  };
  MockRow group(
    String name,
    Map<String, Object?> translations,
    int min,
    int? max,
    String? family,
    List<Map<String, Object?>> options,
    int sort,
  ) => db[MenuTables.groups].insert({
    'org_id': org,
    'name': name,
    'name_translations': translations,
    'selection_type': max == 1 ? 'single' : 'multi',
    'min_selections': min,
    'max_selections': max,
    'is_required': min > 0,
    'sort': sort,
    'is_active': true,
    'legacy_addon_type': family,
    'effect': 'adds',
    'swap_category_id': null,
    'swap_category_slug': null,
    'is_item_options': family == null,
    'options': options,
  }, timestamps: false);

  final categories = <String, Object?>{
    for (final (n, c) in list(menu, 'categories').indexed)
      (c['key']! as String).trim(): db[MenuTables.categories].insert({
        'org_id': org,
        'name': (c['name']! as String).trim(),
        'name_translations': _ar(c['name_ar']),
        'image_url': null,
        'is_active': true,
        'display_order': n,
        'deleted_at': null,
      })['id'],
  };
  final groups = <String, (MockRow, Map<String, Object?>)>{};
  for (final (n, g) in list(menu, 'groups').indexed) {
    final row = group(
      (g['name']! as String).trim(),
      _ar(g['name_ar']),
      (g['min']! as num).toInt(),
      (g['max'] as num?)?.toInt(),
      g['family']! as String,
      [for (final (i, o) in list(g, 'options').indexed) option(o, i)],
      n,
    );
    groups[(g['key']! as String).trim()] = (row, g);
  }
  final sizes = db[MenuTables.sizes];
  final links = db[MenuTables.groupLinks];
  for (final it in list(menu, 'items')) {
    final price = (it['price']! as num).toInt();
    final item = db[MenuTables.menuItems].insert({
      'org_id': org,
      'category_id': categories[(it['category']! as String).trim()],
      'name': (it['name']! as String).trim(),
      'name_translations': _ar(it['name_ar']),
      'description': (it['description'] as String?)?.trim(),
      'description_translations': _ar(it['description_ar']),
      'image_url': null,
      'base_price': price,
      'is_active': it['is_active'] as bool? ?? true,
      'deleted_at': null,
      'kind': 'item',
    });
    final itemSizes = list(it, 'sizes');
    for (final (n, z)
        in (itemSizes.isEmpty
                ? [
                    {'label': _oneSize, 'price': price, 'is_active': true},
                  ]
                : itemSizes)
            .indexed) {
      sizes.insert({
        'menu_item_id': item['id'],
        'label': (z['label']! as String).trim(),
        'price_override': (z['price']! as num).toInt(),
        'is_active': z['is_active'] as bool? ?? true,
        'sort': n,
      }, timestamps: false);
    }
    // The item's price mirrors its cheapest size on sale (schema trigger).
    final onSale = [
      for (final z in itemSizes)
        if (z['is_active'] != false) (z['price']! as num).toInt(),
    ];
    if (onSale.isNotEmpty) {
      item['base_price'] = onSale.reduce((a, b) => a < b ? a : b);
    }
    final itemLinks = list(it, 'groups');
    for (final (n, l) in itemLinks.indexed) {
      final (row, g) = groups[(l['group']! as String).trim()]!;
      final differs = l['min'] != g['min'];
      links.insert({
        'menu_item_id': item['id'],
        'group_id': row['id'],
        'sort': n,
        'included_option_ids': null,
        'min_override': differs ? l['min'] : null,
        'max_override': l['max'] == g['max'] ? null : l['max'],
        'is_required_override': differs ? (l['min']! as num) > 0 : null,
      }, timestamps: false);
    }
    final optionals = list(it, 'optionals');
    if (optionals.isNotEmpty) {
      final row = group('Options', const {}, 0, null, null, [
        for (final (i, o) in optionals.indexed)
          {...option(o, i), 'is_active': true},
      ], 0);
      links.insert({
        'menu_item_id': item['id'],
        'group_id': row['id'],
        'sort': itemLinks.length,
        'included_option_ids': null,
      }, timestamps: false);
    }
  }
}
