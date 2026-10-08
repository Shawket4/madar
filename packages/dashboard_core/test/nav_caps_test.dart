// The generated capability registry and navigation against the web's own
// source, plus the web's nav tests (modules-nav, settings-nav, customers/nav)
// translated.
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_api/dashboard_api.dart' show MyAuthz;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

const _webRoot = '/Users/shawket/Desktop/Madar/MadarDashboard';
final _worktree = Directory.current.parent.parent.path;

Authz _holding(
  List<String> caps, {
  bool owner = false,
  List<String>? roleKinds,
}) => Authz.from(
  MyAuthz(
    userId: 'u',
    epoch: 0,
    specVersion: 0,
    owner: owner,
    platform: false,
    roleKinds: roleKinds ?? const [],
    capabilities: caps,
    askManager: const [],
    limits: const {},
  ),
);

final _everyone = Authz.platformAdmin();

List<String> _shown(List<String>? modules) => [
  for (final l in navLeaves())
    if (leafVisible(l, _everyone, modules: modules)) l.to,
];

void main() {
  group('capabilities', () {
    test('Cap matches the web capabilities.ts, name for name', () {
      final f = File('$_webRoot/src/generated/capabilities.ts');
      if (!f.existsSync()) {
        markTestSkipped('web repo not on this machine');
        return;
      }
      final ts = f.readAsStringSync();
      final block = ts.substring(
        ts.indexOf('export const Cap = {'),
        ts.indexOf('} as const;'),
      );
      final web = {
        for (final m in RegExp(
          r'^\s+(\w+): "([^"]+)" as Capability,',
          multiLine: true,
        ).allMatches(block))
          m.group(1)!: m.group(2)!,
      };
      expect(Cap.byName, web);
      expect(Cap.all, web.values.toList());
      expect(
        capabilitySpecHash,
        RegExp(r'SPEC_HASH = "([^"]+)"').firstMatch(ts)!.group(1),
      );
      final metaCount = RegExp(
        r'^  \{ id: \d+, key: "',
        multiLine: true,
      ).allMatches(ts).length;
      expect(capabilityRegistry, hasLength(metaCount));
    });

    test('the generated file is current (gen_dashboard_caps.py --check)', () {
      if (!Directory(_webRoot).existsSync()) {
        markTestSkipped('web repo not on this machine');
        return;
      }
      final r = Process.runSync('python3', [
        '$_worktree/tool/gen_dashboard_caps.py',
        '--check',
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });

    test('registry rows carry the web metadata', () {
      final first = capabilityRegistry.first;
      expect(first.key, Cap.platformOrgsCreate);
      expect(first.tier, 'legacy');
      expect(first.label('ar'), 'إنشاء المؤسسات (المنصة)');
      expect(capabilityGroups.map((g) => g.key), contains('hr'));
      expect(roleKindLabels['org_admin']!.en, 'Owner');
      expect(OrgModule.all, ['pos', 'dawam']);
      for (final c in capabilityRegistry) {
        expect(capabilityTiers, contains(c.tier));
        expect(capabilityRisks, contains(c.risk));
      }
    });

    test('defaultsFor: the role registry defaults, legacy excluded', () {
      final m = defaultsFor('branch_manager', 'u1')!;
      expect(m.userId, 'u1');
      expect(m.owner, isFalse);
      expect(m.capabilities, contains(Cap.ordersRead));
      expect(m.capabilities, isNot(contains(Cap.platformOrgsCreate)));
      expect(defaultsFor('org_admin')!.owner, isTrue);
      expect(defaultsFor(null), isNull);
    });
  });

  group('Authz (use-authz.test.ts)', () {
    MyAuthz me(List<String> caps, {List<String>? everywhere}) => MyAuthz(
      userId: 'u',
      epoch: 0,
      specVersion: 0,
      owner: false,
      platform: false,
      roleKinds: const [],
      capabilities: caps,
      askManager: const ['orders.void'],
      limits: const {},
      everywhere: everywhere,
    );

    test('canEverywhere is what the server lists as held at every branch', () {
      final k = Authz.from(me(['hr.staff.create'], everywhere: []));
      expect(k.can('hr.staff.create'), isTrue);
      expect(k.canEverywhere('hr.staff.create'), isFalse);
      expect(
        Authz.from(
          me(['hr.staff.create'], everywhere: ['hr.staff.create']),
        ).canEverywhere('hr.staff.create'),
        isTrue,
      );
    });

    test('falls back to the plain check without the list', () {
      expect(
        Authz.from(me(['hr.staff.create'])).canEverywhere('hr.staff.create'),
        isTrue,
      );
      expect(Authz.from(me([])).canEverywhere('hr.staff.create'), isFalse);
    });

    test('platform holds everything; nothing known holds nothing', () {
      expect(_everyone.canEverywhere('hr.staff.delete'), isTrue);
      expect(_everyone.can('anything'), isTrue);
      expect(_everyone.owner, isTrue);
      expect(Authz.none.ready, isFalse);
      expect(Authz.none.can(Cap.ordersRead), isFalse);
      expect(Authz.none.canAny(const []), isFalse);
    });

    test('canAsk: not held, but asking a manager is allowed', () {
      final k = Authz.from(me([Cap.ordersRead]));
      expect(k.canAsk('orders.void'), isTrue);
      expect(k.canAsk(Cap.ordersRead), isFalse);
      expect(k.canAny([Cap.tillRead, Cap.ordersRead]), isTrue);
    });
  });

  group('navigation parity', () {
    Map<String, Object?>? web;
    setUpAll(() {
      if (!Directory(_webRoot).existsSync()) return;
      final r = Process.runSync('node', [
        '$_worktree/tool/gen_dashboard_nav.mjs',
        '--json',
      ]);
      if (r.exitCode != 0) {
        fail('gen_dashboard_nav.mjs --json failed: ${r.stderr}');
      }
      web = json.decode(r.stdout as String) as Map<String, Object?>;
    });

    test('the sidebar is the web NAV, entry for entry', () {
      if (web == null) return markTestSkipped('web repo not on this machine');
      final icons = (web!['icons']! as Map).cast<String, String>();
      final groups = (web!['nav']! as List).cast<Map<String, Object?>>();
      expect(dashNav, hasLength(groups.length));
      void leafMatches(NavLeaf ours, Map<String, Object?> w) {
        expect(ours.to, w['to']);
        expect(ours.labelKey, w['labelKey']);
        expect(ours.fallback, w['fallback']);
        expect(ours.caps, w['caps']);
        expect(ours.module, w['module']);
        expect(ours.superAdminOnly, w['superAdminOnly'] ?? false);
        expect(ours.setup, w['setup'] ?? false);
        expect(ours.icon, icons[w['icon']]);
      }

      for (var g = 0; g < groups.length; g++) {
        final wg = groups[g];
        expect(dashNav[g].labelKey, wg['labelKey']);
        expect(dashNav[g].fallback, wg['fallback']);
        final entries = (wg['entries']! as List).cast<Map<String, Object?>>();
        expect(dashNav[g].entries, hasLength(entries.length));
        for (var e = 0; e < entries.length; e++) {
          final ours = dashNav[g].entries[e];
          final we = entries[e];
          if (we['children'] != null) {
            expect(ours, isA<NavParent>());
            final p = ours as NavParent;
            expect(p.basePath, we['basePath']);
            expect(p.labelKey, we['labelKey']);
            final kids = (we['children']! as List).cast<Map<String, Object?>>();
            expect(p.children, hasLength(kids.length));
            for (var k = 0; k < kids.length; k++) {
              leafMatches(p.children[k], kids[k]);
            }
          } else {
            leafMatches(ours as NavLeaf, we);
          }
        }
      }
    });

    test('settings sub-nav is the web SETTINGS_NAV', () {
      if (web == null) return markTestSkipped('web repo not on this machine');
      final groups = (web!['settings']! as List).cast<Map<String, Object?>>();
      expect(settingsNav, hasLength(groups.length));
      for (var g = 0; g < groups.length; g++) {
        final items = (groups[g]['items']! as List)
            .cast<Map<String, Object?>>();
        expect(settingsNav[g].labelKey, groups[g]['labelKey']);
        expect(settingsNav[g].items, hasLength(items.length));
        for (var i = 0; i < items.length; i++) {
          final o = settingsNav[g].items[i];
          final w = items[i];
          expect(o.to, w['to']);
          expect(o.labelKey, w['labelKey']);
          expect(o.descKey, w['descKey']);
          expect(o.desc, w['desc']);
          expect(o.caps, w['caps']);
          expect(o.module, w['module']);
          expect(o.superAdminOnly, w['superAdminOnly'] ?? false);
        }
      }
    });

    test('module routes are the web MODULE_ROUTES', () {
      if (web == null) return markTestSkipped('web repo not on this machine');
      final wr = [
        for (final r in (web!['moduleRoutes']! as List).cast<List<Object?>>())
          (r[0]! as String, r[1]! as String),
      ];
      expect(moduleRoutes, wr);
    });

    test('the 25 legacy redirects, each with the query it keeps', () {
      if (web == null) return markTestSkipped('web repo not on this machine');
      final wr = (web!['redirects']! as List).cast<Map<String, Object?>>();
      expect(legacyRedirects, hasLength(25));
      expect(legacyRedirects.map((r) => r.from), wr.map((r) => r['from']));
      expect(legacyRedirects.map((r) => r.to), wr.map((r) => r['to']));
      expect(
        legacyRedirects.map((r) => r.query.name),
        wr.map((r) => r['query']),
      );
    });

    test('the generated file is current (gen_dashboard_nav.mjs --check)', () {
      if (web == null) return markTestSkipped('web repo not on this machine');
      final r = Process.runSync('node', [
        '$_worktree/tool/gen_dashboard_nav.mjs',
        '--check',
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });

    test('every nav icon is a MadarIcon the design system draws', () {
      final names = {...madarIconCatalog.keys, ...madarIconGlyphs.keys};
      for (final l in navLeaves()) {
        expect(names, contains(l.icon), reason: l.to);
      }
      for (final g in dashNav) {
        for (final e in g.entries) {
          expect(names, contains(e.icon), reason: e.labelKey);
        }
      }
      for (final g in settingsNav) {
        for (final i in g.items) {
          expect(names, contains(i.icon), reason: i.to);
        }
      }
      expect(names, contains(languageIcon));
    });
  });

  group('nav by module (modules-nav.test.ts)', () {
    test('a Dawam-only org sees Dawam, people, branches and settings', () {
      final to = _shown(['dawam']);
      for (final p in [
        '/staff/team', '/staff/schedule', '/staff/payroll', '/staff/reports', //
        '/staff/rules',
        '/staff/employees',
        '/staff/attendance',
        '/staff/requests',
        '/reports/staff',
        '/reports/legal',
        '/branches',
        '/settings',
        '/access/users',
      ]) {
        expect(to, contains(p));
      }
      for (final p in [
        '/', '/orders', '/tills', '/menu/items', '/inventory/today', //
        '/reports/operations', '/devices',
      ]) {
        expect(to, isNot(contains(p)));
      }
    });

    test('a POS-only org sees no Dawam pages', () {
      final to = _shown(['pos']);
      expect(to, containsAll(['/orders', '/reports/legal']));
      for (final p in [
        '/staff/team',
        '/staff/schedule',
        '/staff/payroll',
        '/staff/approvals', //
        '/staff/reports',
        '/staff/employees',
        '/staff/attendance',
        '/staff/shifts',
        '/staff/requests', '/staff/rules', '/reports/staff',
      ]) {
        expect(to, isNot(contains(p)));
      }
    });

    test('an unknown module list hides nothing', () {
      expect(_shown(null).length, _shown(['pos', 'dawam']).length);
    });

    test('route module: staff pages Dawam, selling POS, shared none', () {
      for (final p in [
        '/staff/employees',
        '/staff/attendance',
        '/staff/shifts',
        '/staff/requests', //
        '/staff/rules', '/staff/setup', '/staff/team', '/staff/schedule',
        '/staff/approvals',
        '/staff/payroll',
        '/staff/reports',
        '/reports/staff',
      ]) {
        expect(moduleOfPath(p), 'dawam', reason: p);
      }
      for (final p in [
        '/orders',
        '/tills',
        '/menu/items',
        '/menu/items/abc',
        '/inventory/today', //
        '/reports/staff-pool', '/settings/loyalty', '/devices',
      ]) {
        expect(moduleOfPath(p), 'pos', reason: p);
      }
      for (final p in [
        '/',
        '/branches',
        '/settings',
        '/access/users',
        '/reports/legal',
        '/orgs',
      ]) {
        expect(moduleOfPath(p), isNull, reason: p);
      }
      expect(moduleOfPath('/orders/'), 'pos');
    });

    test('Rules show for view or edit, not for neither', () {
      final rules = navLeaves().firstWhere((l) => l.to == '/staff/rules');
      expect(
        leafVisible(rules, _holding(['hr.rules.view']), modules: ['dawam']),
        isTrue,
      );
      expect(
        leafVisible(rules, _holding(['hr.rules.edit']), modules: ['dawam']),
        isTrue,
      );
      expect(
        leafVisible(
          rules,
          _holding(['hr.attendance.read']),
          modules: ['dawam'],
        ),
        isFalse,
      );
    });

    test('Approvals show for anyone who decides something', () {
      final a = navLeaves().firstWhere((l) => l.to == '/staff/approvals');
      expect(
        leafVisible(a, _holding(['hr.attendance.edit']), modules: ['dawam']),
        isTrue,
      );
      expect(
        leafVisible(a, _holding(['hr.leave.edit']), modules: ['dawam']),
        isTrue,
      );
      expect(
        leafVisible(a, _holding(['hr.attendance.read']), modules: ['dawam']),
        isFalse,
      );
    });

    test(
      'Customers follows customers.view, never a role (customers/nav.test.ts)',
      () {
        final c = navLeaves().firstWhere((l) => l.to == '/customers');
        expect(
          leafVisible(
            c,
            _holding(
              ['customers.create', 'loyalty.read'],
              roleKinds: ['org_admin'],
            ),
          ),
          isFalse,
        );
        expect(
          leafVisible(c, _holding(['loyalty.members.list', 'loyalty.read'])),
          isFalse,
        );
        expect(leafVisible(c, _holding(['customers.view'])), isTrue);
      },
    );

    test('Set-up shows only while the checklist is unfinished', () {
      final s = navLeaves().firstWhere((l) => l.to == '/staff/setup');
      final k = _holding([Cap.hrRulesEdit]);
      expect(leafVisible(s, k, modules: ['dawam']), isFalse);
      expect(
        leafVisible(s, k, modules: ['dawam'], setupIncomplete: true),
        isTrue,
      );
      expect(
        leafVisible(s, _holding([]), modules: ['dawam'], setupIncomplete: true),
        isFalse,
      );
    });

    test('Organizations is platform-only', () {
      final orgs = navLeaves().firstWhere((l) => l.to == '/orgs');
      expect(leafVisible(orgs, _holding(Cap.all)), isFalse);
      expect(leafVisible(orgs, _everyone), isTrue);
    });
  });

  group('visibleSettings (settings-nav.test.ts)', () {
    final owner = _holding(
      [
        'delivery.settings.read', 'bookings.edit', 'loyalty.use', //
        'payment_methods.edit', 'org.settings.read', 'kitchen.stations.edit',
        'integrations.read',
      ],
      owner: true,
      roleKinds: ['org_admin'],
    );
    List<String> paths(List<String> modules) => [
      for (final g in visibleSettings(owner, modules))
        for (final i in g.items) i.to,
    ];

    test("a Dawam-only org keeps only what isn't the till's", () {
      expect(paths(['dawam']), ['/settings']);
    });

    test('a POS org sees its panes', () {
      expect(
        paths(['pos']),
        containsAll([
          '/settings/delivery', '/settings/payment-methods', //
          '/settings/kitchen-stations', '/settings/brand',
        ]),
      );
    });

    test('nothing module-tagged shows until the modules are known', () {
      expect(paths([]), ['/settings']);
    });

    test('every POS pane is refused by URL too (one module table)', () {
      for (final g in settingsNav) {
        for (final i in g.items) {
          expect(moduleOfPath(i.to), i.module, reason: i.to);
        }
      }
    });

    test('WhatsApp is platform-only', () {
      final all = [
        for (final g in visibleSettings(_everyone, OrgModule.all))
          for (final i in g.items) i.to,
      ];
      expect(all, contains('/settings/whatsapp'));
      expect(paths(['pos']), isNot(contains('/settings/whatsapp')));
    });
  });

  group('legacy redirects', () {
    test('land where the web sends them, with the query they keep', () {
      expect(
        resolveLegacyRedirect(Uri.parse('/analytics?x=1')),
        Uri.parse('/reports/operations'),
      );
      expect(
        resolveLegacyRedirect(Uri.parse('/inventory/')),
        Uri.parse('/inventory/today'),
      );
      expect(
        resolveLegacyRedirect(Uri.parse('/permissions?user=u9&branchId=b')),
        Uri.parse('/access/roles?user=u9'),
      );
      expect(
        resolveLegacyRedirect(Uri.parse('/users?edit=e1&branches=b1&zzz=1')),
        Uri.parse('/access/users?edit=e1&branches=b1'),
      );
      expect(
        resolveLegacyRedirect(Uri.parse('/shifts?branchId=b1&preset=7d')),
        Uri.parse('/tills?branchId=b1&preset=7d'),
      );
      expect(
        legacyRedirects.firstWhere((r) => r.from == '/shifts').replace,
        isTrue,
      );
      expect(resolveLegacyRedirect(Uri.parse('/orders')), isNull);
      // A redirect never lands on another redirect.
      for (final r in legacyRedirects) {
        expect(resolveLegacyRedirect(Uri.parse(r.to)), isNull, reason: r.to);
      }
    });
  });
}
