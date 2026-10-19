// The Setup page's fixtures: readiness answers for each stage, written as
// the server words them (`orgs/readiness.rs`), and the page opened on them.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

const readinessRoute = '/orgs/{id}/readiness';

ReadinessProblem branch(String id, String name) =>
    ReadinessProblem(entityType: 'branch', entityId: id, name: name);

ReadinessProblem item(String id, String name) =>
    ReadinessProblem(entityType: 'item', entityId: id, name: name, itemId: id);

ReadinessCheck check(
  String key, {
  bool ok = false,
  bool blocking = false,
  int? count,
  int? total,
  List<ReadinessProblem> problems = const [],
  int more = 0,
}) => ReadinessCheck(
  key: key,
  level: blocking ? CheckLevel.blocking : CheckLevel.advice,
  ok: ok,
  count: count ?? problems.length + more,
  total: total,
  problems: problems,
  more: more,
);

/// A shop that signed up an hour ago: a branch, nothing else.
Readiness freshShop() => Readiness(
  orgId: SeedIds.sabahOrg,
  ready: false,
  live: false,
  checks: [
    check('branch', ok: true, blocking: true, count: 1),
    check('menu', blocking: true, count: 0),
    check(
      'payment',
      blocking: true,
      total: 1,
      problems: [branch(SeedIds.maadi, 'Maadi')],
    ),
    check('sign_in', ok: true, blocking: true, count: 0, total: 1),
    check(
      'tablet',
      blocking: true,
      total: 1,
      problems: [branch(SeedIds.maadi, 'Maadi')],
    ),
    check('items_no_category', ok: true),
    check('items_zero_price', ok: true),
    check('required_group_empty', ok: true),
    check('menu_lint', ok: true),
    check('recipes', ok: true, total: 0),
    check('ingredient_costs', ok: true),
    check('team', count: 1),
    check('receipt', count: 0),
  ],
);

/// Every blocking check passes; advice still open; no order yet.
Readiness readyShop({bool live = false}) => Readiness(
  orgId: SeedIds.sabahOrg,
  ready: true,
  live: live,
  firstOrderAt: live ? DateTime.utc(2026, 10, 12, 9, 30) : null,
  checks: [
    check('branch', ok: true, blocking: true, count: 2),
    check('menu', ok: true, blocking: true, count: 38),
    check('payment', ok: true, blocking: true, count: 0, total: 2),
    check('sign_in', ok: true, blocking: true, count: 0, total: 2),
    check('tablet', ok: true, blocking: true, count: 0, total: 2),
    check(
      'items_no_category',
      problems: [item('i-1', 'Iced Spanish Latte'), item('i-2', 'Matcha')],
    ),
    check('items_zero_price', problems: [item('i-3', 'Tap water')]),
    check(
      'required_group_empty',
      problems: [
        const ReadinessProblem(
          entityType: 'option',
          entityId: 'g-1',
          name: 'Milk',
          rule: 'F16',
          groupId: 'g-1',
        ),
      ],
    ),
    check('menu_lint', ok: true),
    check(
      'recipes',
      total: 38,
      problems: [for (var i = 0; i < 20; i++) item('r-$i', 'Item ${i + 1}')],
      more: 4,
    ),
    check(
      'ingredient_costs',
      problems: [
        const ReadinessProblem(
          entityType: 'ingredient',
          entityId: 'ing-1',
          name: 'Oat milk',
        ),
      ],
    ),
    check('team', ok: true, count: 6),
    check('receipt', ok: true, count: 1),
  ],
);

/// A server answering [r] (its org id kept) for the shop in scope.
({MockServer server, MockDb db}) serving(
  Readiness r, {
  Persona persona = Persona.owner,
}) {
  final s = homeServer(persona: persona);
  s.server.on('GET', readinessRoute, (req) {
    req.requireCap('org.settings.read');
    return MockResponse.ok(r);
  });
  return s;
}

/// Opens `/setup` on [r].
Future<DashHarness> pumpSetup(
  WidgetTester tester,
  Readiness r, {
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  bool reducedMotion = true,
  Persona persona = Persona.owner,
}) {
  final s = serving(r, persona: persona);
  return pumpHome(
    tester,
    path: '/setup',
    server: s.server,
    db: s.db,
    size: size,
    locale: locale,
    dark: dark,
    persona: persona,
    reducedMotion: reducedMotion,
  );
}
