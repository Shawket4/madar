/// `GET /orgs/{id}/readiness` (MadarRust `orgs/readiness.rs`): can the shop
/// sell yet, and what stops it, derived on every read from the mock tables
/// the areas share, as the backend derives it from the shop's rows.
///
/// Read with what the tables hold: the PIN holders from `user_pins` (else
/// the seed's people), a tablet from `devices` (else an order at the branch,
/// the backend's `client_seen`), recipes from `size_recipe_lines`.
/// ponytail: no menu lint here (`menu_lint` is always ok); a test that needs
/// it answers the route itself.
library;

import '../../generated/models.dart';
import '../mock_db.dart';
import '../seed_data.dart';
import '../seed_ids.dart';

const int _shown = 20;

/// The org's readiness as `readiness::load` answers it.
Readiness mockReadiness(MockDb db, String orgId) {
  final org = db['orgs'].get(orgId, what: 'Organization not found');
  bool mine(MockRow r) => r['org_id'] == orgId;
  bool live(MockRow r) => r['deleted_at'] == null && r['is_active'] != false;
  List<MockRow> rows(String table, bool Function(MockRow r) test) =>
      db.hasTable(table) ? db[table].rows.where(test).toList() : <MockRow>[];

  final branches = rows('branches', (b) => mine(b) && live(b))
    ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
  final branchIds = {for (final b in branches) b['id']};
  final orders = rows('orders', (o) => branchIds.contains(o['branch_id']));
  final firstOrder = orders.isEmpty
      ? null
      : orders
            .map((o) => DateTime.parse('${o['created_at']}'))
            .reduce((a, b) => a.isBefore(b) ? a : b);

  final modules = (org['modules'] as List?) ?? const [];
  final checks = modules.contains('pos')
      ? _posChecks(db, org, branches, orders, rows, mine, live)
      : <ReadinessCheck>[];
  return Readiness(
    orgId: orgId,
    ready: checks.every((c) => c.ok || c.level == CheckLevel.advice),
    live: firstOrder != null,
    firstOrderAt: firstOrder,
    checks: checks,
  );
}

List<ReadinessCheck> _posChecks(
  MockDb db,
  MockRow org,
  List<MockRow> branches,
  List<MockRow> orders,
  List<MockRow> Function(String, bool Function(MockRow)) rows,
  bool Function(MockRow) mine,
  bool Function(MockRow) live,
) {
  ReadinessProblem named(String type, MockRow r, {String? groupId}) =>
      ReadinessProblem(
        entityType: type,
        entityId: r['id']! as String,
        name: '${r['name']}',
        itemId: type == 'item' ? r['id']! as String : null,
        groupId: groupId,
      );

  final categories = {
    for (final c in rows('categories', (c) => mine(c) && live(c))) c['id'],
  };
  final items = rows('menu_items', (i) => mine(i) && live(i))
    ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
  final sizes = rows('item_sizes', (s) => s['is_active'] != false);
  final sellable = items.where((i) => categories.contains(i['category_id']));

  final methods = rows('payment_methods', (m) => mine(m) && live(m));
  final pinIds = db.hasTable('user_pins')
      ? {for (final p in db['user_pins'].rows) p['id']}
      : {
          for (final p in sabahStaff)
            if (p.pin != null) SeedIds.user(p.key),
        };
  final holders = rows(
    'users',
    (u) => mine(u) && live(u) && pinIds.contains(u['id']),
  );
  final devices = rows(
    'devices',
    (d) =>
        d['kind'] == 'pos' &&
        d['retired_at'] == null &&
        d['plan_inactive'] != true,
  );
  bool hasTablet(Object? b) => db.hasTable('devices')
      ? devices.any((d) => d['branch_id'] == b)
      : orders.any((o) => o['branch_id'] == b);

  final noTender = [
    if (methods.isEmpty)
      for (final b in branches) named('branch', b),
  ];
  final noSigner = [
    for (final b in branches)
      if (!holders.any(
        (u) => u['branch_id'] == null || u['branch_id'] == b['id'],
      ))
        named('branch', b),
  ];
  final noTablet = [
    for (final b in branches)
      if (!hasTablet(b['id'])) named('branch', b),
  ];
  final noCategory = [
    for (final i in items)
      if (!categories.contains(i['category_id'])) named('item', i),
  ];
  final zeroPrice = [
    for (final i in items)
      if ((i['base_price'] as num? ?? 0) == 0 &&
          !sizes.any(
            (s) =>
                s['menu_item_id'] == i['id'] &&
                (s['price_override'] as num? ?? 0) > 0,
          ))
        named('item', i),
  ];
  final emptyRequired = [
    for (final g in rows('modifier_groups', (g) => mine(g) && live(g)))
      if ((g['min_selections'] as num? ?? 0) > 0 &&
          !((g['options'] as List?) ?? const []).any(
            (o) => o is Map && o['is_active'] != false,
          ))
        ReadinessProblem(
          entityType: 'option',
          entityId: g['id']! as String,
          name: '${g['name']}',
          rule: 'F16',
          groupId: g['id']! as String,
        ),
  ];
  final team = rows('users', (u) => mine(u) && live(u)).length;

  final checks = [
    _present('branch', CheckLevel.blocking, branches.length),
    _present('menu', CheckLevel.blocking, sellable.length),
    _perBranch('payment', branches, noTender),
    _perBranch('sign_in', branches, noSigner),
    _perBranch('tablet', branches, noTablet),
    _listed('items_no_category', noCategory),
    _listed('items_zero_price', zeroPrice),
    _listed('required_group_empty', emptyRequired),
    _listed('menu_lint', const []),
  ];
  if (org['plan'] != 'free') {
    final lines = rows('size_recipe_lines', (_) => true);
    final noRecipe = [
      for (final i in items)
        if (!(() {
          final own = sizes.where((s) => s['menu_item_id'] == i['id']);
          return own.isNotEmpty &&
              own.every((s) => lines.any((l) => l['size_id'] == s['id']));
        })())
          named('item', i),
    ];
    final used = {for (final l in lines) l['ingredient_id']};
    final free = [
      for (final g in rows(
        'org_ingredients',
        (g) => mine(g) && live(g),
      )..sort((a, b) => '${a['name']}'.compareTo('${b['name']}')))
        if ((g['cost_per_unit'] as num? ?? 0) == 0 && used.contains(g['id']))
          named('ingredient', g),
    ];
    checks
      ..add(_listed('recipes', noRecipe, total: items.length))
      ..add(_listed('ingredient_costs', free));
  }
  final teamCheck = _present('team', CheckLevel.advice, team - 1);
  checks
    ..add(
      ReadinessCheck(
        key: 'team',
        level: CheckLevel.advice,
        ok: teamCheck.ok,
        count: team,
        more: 0,
        problems: const [],
      ),
    )
    ..add(
      _present('receipt', CheckLevel.advice, org['logo_url'] != null ? 1 : 0),
    );
  return checks;
}

ReadinessCheck _present(String key, CheckLevel level, int found) =>
    ReadinessCheck(
      key: key,
      level: level,
      ok: found > 0,
      count: found < 0 ? 0 : found,
      more: 0,
      problems: const [],
    );

ReadinessCheck _listed(
  String key,
  List<ReadinessProblem> problems, {
  CheckLevel level = CheckLevel.advice,
  int? total,
  bool? ok,
}) => ReadinessCheck(
  key: key,
  level: level,
  ok: ok ?? problems.isEmpty,
  count: problems.length,
  total: total,
  more: problems.length > _shown ? problems.length - _shown : 0,
  problems: problems.take(_shown).toList(),
);

ReadinessCheck _perBranch(
  String key,
  List<MockRow> branches,
  List<ReadinessProblem> failing,
) => _listed(
  key,
  failing,
  level: CheckLevel.blocking,
  total: branches.length,
  ok: failing.isEmpty && branches.isNotEmpty,
);
