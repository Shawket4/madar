// The settings shell and the area-wide rules (SET-SHL-001 … 021), driven
// through the app shell on the mock server. Panes other units own are only
// opened here, never changed.
import 'package:dashboard_api/dashboard_api.dart' show KitchenStation;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/brand_appearance/brand_page.dart';
import 'package:dashboard_setup/src/brand_appearance/settings_shell.dart';
import 'package:dashboard_setup/src/delivery/delivery_settings_page.dart';
import 'package:dashboard_setup/src/mock/delivery_mock.dart'
    show DeliveryRoutes, DeliverySeed;
import 'package:dashboard_setup/src/mock/kitchen_mock.dart'
    show KitchenRoutes, KitchenSeed;
import 'package:dashboard_setup/src/mock/payment_methods_mock.dart'
    show PmRoutes;
import 'package:dashboard_setup/src/payment_methods/payment_method_dialog.dart';
import 'package:dashboard_setup/src/shared/scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'support.dart';

Finder _rail() => inShell(byKey('settings-rail'));
Finder _inRail(Finder f) => find.descendant(of: _rail(), matching: f);
Finder _picker() => inShell(byKey('settings-picker'));

/// The rail's entries, in order, with whether each is the active one.
List<(String, bool)> _entries(WidgetTester tester) => [
  for (final p in tester.widgetList<DashPressable>(
    _inRail(find.byType(DashPressable)),
  ))
    (p.semanticLabel!, p.selected ?? false),
];

String? _active(WidgetTester tester) {
  for (final (label, on) in _entries(tester)) {
    if (on) return label;
  }
  return null;
}

final String _helio = '?branchId=${SeedIds.heliopolis}';

const List<String> _ownerPanes = [
  'Appearance',
  'Brand',
  'Links page',
  'Delivery',
  'Bookings',
  'Loyalty',
  'QR Codes',
  'Combos and deals',
  'Payment methods',
  'Staff drinks',
  'Stations',
  'Order routing',
  'Integrations',
];

void main() {
  group('the shell', () {
    testWidgets('SET-SHL-001 one shell: the page title "Settings", the list, '
        'the pane beside it', (tester) async {
      final h = await pumpBrand(tester);
      expect(inShell(find.text('Settings')), findsWidgets);
      expect(_rail(), findsOneWidget);
      expect(find.byType(BrandPage), findsOneWidget);
      final rail = tester.getTopRight(_rail());
      final pane = tester.getTopLeft(find.byType(BrandPage));
      expect(pane.dx, greaterThan(rail.dx), reason: 'the pane is beside it');
      expect(tester.getSize(_rail()).width, SettingsShell.railWidth);
      expect(h.location.path, brandPath);
    });

    testWidgets('SET-SHL-002 the active entry: Appearance only on the index; '
        'another on its path or below it', (tester) async {
      final h = await pumpBrand(tester, path: appearancePath);
      expect(_active(tester), 'Appearance');
      await h.go(brandPath);
      expect(_active(tester), 'Brand');
      await h.go('/settings/payment-methods?edit=new');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(_active(tester), 'Payment methods');
      final qr = settingsNav
          .expand((g) => g.items)
          .firstWhere((i) => i.to == '/settings/qr');
      final home = settingsNav.first.items.first;
      expect(SettingsShell.isActive(qr, '/settings/qr/print'), isTrue);
      expect(SettingsShell.isActive(qr, '/settings/qrx'), isFalse);
      expect(SettingsShell.isActive(home, '/settings/'), isTrue);
      expect(SettingsShell.isActive(home, '/settings/brand'), isFalse);
    });

    testWidgets('SET-SHL-002 the rail is sticky: it stays in view while a '
        'long pane scrolls, and still opens panes', (tester) async {
      final h = await pumpBrand(tester);
      final start = tester.getTopLeft(_rail()).dy;
      final scroll = tester
          .widgetList<Scrollable>(
            find.ancestor(
              of: find.byType(BrandPage),
              matching: find.byType(Scrollable),
            ),
          )
          .firstWhere((s) => s.axisDirection == AxisDirection.down);
      final state = tester.state<ScrollableState>(find.byWidget(scroll));
      state.position.jumpTo(600);
      await h.settle();
      final viewTop = tester.getTopLeft(find.byWidget(scroll)).dy;
      final now = tester.getTopLeft(_rail()).dy;
      expect(now, closeTo(viewTop + 16, 1));
      expect(now, lessThan(start));
      state.position.jumpTo(state.position.maxScrollExtent);
      await h.settle();
      final bottom = tester.getBottomLeft(_rail()).dy;
      final paneBottom = tester.getBottomLeft(find.byType(BrandPage)).dy;
      expect(
        bottom,
        lessThanOrEqualTo(paneBottom + 1),
        reason: 'never past the end of the pane',
      );
      await h.tap(_inRail(find.text('Appearance')));
      expect(h.location.path, appearancePath);
    });

    testWidgets('SET-SHL-003 groups and entries in the web\'s order, group '
        'labels in capitals, the web\'s glyphs', (tester) async {
      await pumpBrand(tester, path: appearancePath);
      expect([for (final (l, _) in _entries(tester)) l], _ownerPanes);
      final groups = [
        'THIS APP',
        'WAYS TO SELL',
        'MENU',
        'TAKING MONEY',
        'KITCHEN',
        'SYSTEM',
      ];
      final tops = [
        for (final g in groups) tester.getTopLeft(_inRail(find.text(g))).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(
        _inRail(
          find.byWidgetPredicate((w) => w is DashIcon && w.name == 'palette'),
        ),
        findsOneWidget,
      );
      expect(
        _inRail(
          find.byWidgetPredicate(
            (w) => w is DashIcon && w.name == 'credit-card',
          ),
        ),
        findsOneWidget,
      );
      // The descriptions are not drawn.
      expect(
        _inRail(find.text('Theme and language for this device.')),
        findsNothing,
      );
    });

    testWidgets('SET-SHL-004 a platform admin also sees WhatsApp', (
      tester,
    ) async {
      await pumpBrand(
        tester,
        path: appearancePath,
        persona: Persona.platform,
        prefs: pickedSabah,
      );
      expect(
        [for (final (l, _) in _entries(tester)) l],
        [..._ownerPanes, 'WhatsApp'],
      );
    });

    testWidgets('SET-SHL-004 SET-SHL-005 a Dawam-only org sees Appearance '
        'alone, under its own group only', (tester) async {
      await pumpBrand(tester, path: appearancePath, persona: Persona.dawamOnly);
      expect(_entries(tester), [('Appearance', true)]);
      expect(_inRail(find.text('THIS APP')), findsOneWidget);
      expect(_inRail(find.text('WAYS TO SELL')), findsNothing);
      expect(_inRail(find.text('SYSTEM')), findsNothing);
    });

    testWidgets('SET-SHL-004 modules not known yet: Appearance only', (
      tester,
    ) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', '/orgs/{id}/modules');
      final h = await pumpBrand(tester, path: appearancePath, backend: m);
      expect(_entries(tester), [('Appearance', true)]);
      gate.release();
      await h.settle();
      expect(_entries(tester), hasLength(_ownerPanes.length));
    });

    testWidgets('SET-SHL-004 the rule itself: module, platform, any-of caps', (
      tester,
    ) async {
      final h = await pumpBrand(tester, path: appearancePath);
      final authz = h.container.read(authzProvider);
      List<String> panes(List<String> modules) => [
        for (final g in visibleSettings(authz, modules))
          for (final i in g.items) i.to,
      ];
      expect(panes(const []), ['/settings']);
      expect(panes(const ['dawam']), ['/settings']);
      expect(panes(const ['pos']), hasLength(_ownerPanes.length));
      expect(panes(const ['pos']), isNot(contains('/settings/whatsapp')));
    });

    testWidgets('SET-SHL-004 a manager sees only the panes the caps allow', (
      tester,
    ) async {
      final h = await pumpBrand(
        tester,
        path: appearancePath,
        persona: Persona.manager,
      );
      final authz = h.container.read(authzProvider);
      final expected = [
        for (final g in settingsNav)
          for (final i in g.items)
            if (!i.superAdminOnly && (i.caps == null || i.caps!.any(authz.can)))
              h.t(i.labelKey),
      ];
      expect([for (final (l, _) in _entries(tester)) l], expected);
      expect(expected, isNot(contains('Combos and deals')));
    });

    testWidgets('SET-SHL-006 narrow: a picker above the pane, named "Settings '
        'section", showing the current pane; picking navigates', (
      tester,
    ) async {
      final h = await pumpBrand(tester, size: DashSize.phone);
      expect(_rail(), findsNothing);
      final select = tester.widget<DashSelect<String>>(_picker());
      expect(select.semanticLabel, 'Settings section');
      expect(select.value, brandPath);
      expect(select.options.map((o) => o.label), _ownerPanes);
      expect(select.options.first.icon, 'palette');
      final top = tester.getBottomLeft(_picker()).dy;
      expect(tester.getTopLeft(find.byType(BrandPage)).dy, greaterThan(top));
      await h.tap(_picker());
      await h.tap(find.text('Appearance').last);
      expect(h.location.path, appearancePath);
    });

    testWidgets('SET-SHL-006 from 640 the picker is 320 wide; the rail from '
        '1024', (tester) async {
      final h = await pumpBrand(tester, size: DashSize.phone);
      tester.view.physicalSize = const Size(800, 900) * DashSize.pixelRatio;
      await h.settle();
      expect(tester.getSize(_picker()).width, SettingsShell.pickerWidth);
      tester.view.physicalSize = const Size(1024, 900) * DashSize.pixelRatio;
      await h.settle();
      expect(_rail(), findsOneWidget);
      expect(_picker(), findsNothing);
    });

    testWidgets('SET-SHL-007 a path with no entry: nothing active, the picker '
        'shows "Settings"', (tester) async {
      final h = await pumpBrand(tester, path: '/settings/delivery-zones');
      expect(_active(tester), isNull);
      await h.go('/settings/delivery-zones');
      tester.view.physicalSize = const Size(390, 844) * DashSize.pixelRatio;
      await h.settle();
      final select = tester.widget<DashSelect<String>>(_picker());
      expect(select.value, isNull);
      expect(select.placeholder, 'Settings');
    });
  });

  group('area-wide', () {
    testWidgets('SET-SHL-008 a POS pane typed in a Dawam-only org meets the '
        'module gate; Appearance does not', (tester) async {
      final h = await pumpBrand(tester, persona: Persona.dawamOnly);
      expect(find.text('Not part of this business\'s plan'), findsOneWidget);
      expect(find.text(h.t('dawam.modulePosOff')), findsOneWidget);
      expect(find.byType(BrandPage), findsNothing);
      await h.go(appearancePath);
      expect(find.text('Appearance'), findsWidgets);
    });

    testWidgets('SET-SHL-008 modules read failed: the error with Retry', (
      tester,
    ) async {
      final m = setupMockServer();
      m.server.fail(
        'GET',
        '/orgs/{id}/modules',
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpBrand(tester, backend: m);
      expect(
        find.textContaining(h.t('dawam.modulesLoadError')),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsWidgets);
      expect(find.byType(BrandPage), findsNothing);
    });

    testWidgets('SET-SHL-009 no route gate: a manager reads Brand and '
        'Delivery; Integrations refuses in its own pane', (tester) async {
      final h = await pumpBrand(tester, persona: Persona.manager);
      expect(find.byType(BrandPage), findsOneWidget);
      await h.go('/settings/delivery?branchId=${SeedIds.zamalek}');
      expect(find.byType(DeliverySettingsPage), findsOneWidget);
      expect(
        h.container.read(authzProvider).can(Cap.integrationsRead),
        isFalse,
      );
      await h.go('/settings/integrations');
      expect(inShell(find.byType(SetupRefusalPane)), findsOneWidget);
    });

    testWidgets('SET-SHL-010 the sidebar\'s Setup leaves and their gates', (
      tester,
    ) async {
      await pumpBrand(tester, path: appearancePath);
      final setup = dashNav.firstWhere((g) => g.labelKey == 'nav.setup');
      final leaves = {
        for (final e in setup.entries.whereType<NavLeaf>()) e.to: e,
      };
      expect(leaves['/settings']!.caps, isNull);
      expect(leaves['/settings']!.module, isNull);
      expect(leaves['/settings/loyalty']!.caps, [
        'loyalty.use',
        'loyalty.members.list',
      ]);
      expect(leaves['/settings/loyalty']!.module, 'pos');
      expect(leaves['/settings/staff-pool']!.caps, [
        'org.settings.read',
        'org.settings.edit',
      ]);
      expect(find.text('Setup'), findsWidgets);
    });

    testWidgets('SET-SHL-011 the legacy addresses land on their panes', (
      tester,
    ) async {
      final h = await pumpBrand(tester, path: appearancePath);
      h.allowUnmatched = true;
      const legacy = {
        '/qr': '/settings/qr',
        '/delivery': '/settings/delivery',
        '/delivery/settings': '/settings/delivery',
        '/delivery/zones': '/settings/delivery-zones',
        '/kitchen/stations': '/settings/kitchen-stations',
        '/kitchen/routing': '/settings/kitchen-routing',
      };
      for (final e in legacy.entries) {
        await h.go(e.key);
        expect(h.location.path, e.value, reason: e.key);
      }
    });

    testWidgets('SET-SHL-012 ?edit=new opens the payment-method editor', (
      tester,
    ) async {
      final h = await pumpBrand(
        tester,
        path: '/settings/payment-methods?edit=new',
      );
      expect(find.byType(PaymentMethodDialog), findsOneWidget);
      expect(h.location.queryParameters['edit'], 'new');
    });

    testWidgets('SET-SHL-013 resting on a rail entry warms its pane; opening '
        'it asks nothing more', (tester) async {
      final h = await pumpBrand(tester, path: appearancePath);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      int lists() => h.server.callsTo(PmRoutes.list, method: 'GET').length;
      expect(lists(), 0);
      final entry = _inRail(find.text('Payment methods'));
      await mouse.moveTo(tester.getCenter(entry));
      await h.settle();
      expect(lists(), 1, reason: 'warmed on intent');
      await h.tap(entry);
      expect(h.location.path, '/settings/payment-methods');
      expect(lists(), 1, reason: 'opened from the cache');
    });

    testWidgets('SET-SHL-013 resting on Brand warms the org read (intent '
        'beyond the web); opening it asks nothing more', (tester) async {
      final h = await pumpBrand(tester, path: appearancePath);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      int reads() => h.server.callsTo(orgRoute, method: 'GET').length;
      expect(reads(), 0);
      final entry = _inRail(find.text('Brand'));
      await mouse.moveTo(tester.getCenter(entry));
      await h.settle();
      expect(reads(), 1, reason: 'warmed on intent');
      await h.tap(entry);
      expect(h.location.path, brandPath);
      expect(reads(), 1, reason: 'opened from the cache');
    });

    testWidgets('SET-SHL-013 the picker\'s options warm their pane too', (
      tester,
    ) async {
      final h = await pumpBrand(
        tester,
        path: appearancePath,
        size: DashSize.phone,
      );
      int lists() => h.server.callsTo(PmRoutes.list, method: 'GET').length;
      await h.tap(_picker());
      final option = find.text('Payment methods').last;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(option));
      await h.settle();
      expect(lists(), 1, reason: 'warmed on intent');
      await h.tap(option);
      expect(h.location.path, '/settings/payment-methods');
      expect(lists(), 1);
    });

    testWidgets('SET-SHL-014 SET-SHL-019 with a branch picked the stream is '
        'open and its events refresh the panes', (tester) async {
      final h = await pumpBrand(
        tester,
        path: '/settings/payment-methods$_helio',
      );
      expect(h.realtime.current, isNotNull);
      final pm = h.server.callsTo(PmRoutes.list, method: 'GET').length;
      h.realtime.current!.emit(
        'payment_methods.availability_changed',
        data: '{}',
      );
      await h.settle();
      expect(h.server.callsTo(PmRoutes.list, method: 'GET').length, pm + 1);
      await h.go('/settings/kitchen-stations$_helio');
      final st = h.server.callsTo(KitchenRoutes.stations, method: 'GET').length;
      h.realtime.current!.emit('kitchen.station_updated', data: '{}');
      await h.settle();
      expect(
        h.server.callsTo(KitchenRoutes.stations, method: 'GET').length,
        st + 1,
      );
    });

    testWidgets('SET-SHL-019 on "All branches" no stream, nothing live', (
      tester,
    ) async {
      final h = await pumpBrand(tester, path: '/settings/payment-methods');
      expect(h.realtime.current, isNull);
    });

    testWidgets('SET-SHL-015 the header branch scopes a branch pane; '
        'switching it reloads', (tester) async {
      final h = await pumpBrand(tester, path: '/settings/delivery$_helio');
      List<String?> asked() => [
        for (final c in h.server.callsTo(
          DeliveryRoutes.settings,
          method: 'GET',
        ))
          c.query['branch_id']?.single,
      ];
      expect(asked(), [SeedIds.heliopolis]);
      await h.go('/settings/delivery?branchId=${SeedIds.maadi}');
      expect(asked().last, SeedIds.maadi);
    });

    testWidgets('SET-SHL-016 tables: ten a page with Previous/Next past ten; '
        'a phone draws cards', (tester) async {
      final m = setupMockServer();
      for (var i = 1; i <= 9; i++) {
        m.db[DeliverySeed.zonesTable].insert({
          'branch_id': SeedIds.heliopolis,
          'name': 'Ring $i',
          'name_translations': <String, Object?>{},
          'max_road_distance_meters': 6000 + i * 500,
          'fee': 4000 + i * 100,
          'is_active': true,
        });
      }
      final h = await pumpBrand(
        tester,
        path: '/settings/delivery-zones$_helio',
        backend: m,
      );
      final page = h.t('common.page', args: {'current': 1, 'total': 2});
      expect(inShell(find.text(page)), findsOneWidget);
      await h.tap(inShell(find.bySemanticsLabel(h.t('common.next'))));
      final page2 = h.t('common.page', args: {'current': 2, 'total': 2});
      expect(inShell(find.text(page2)), findsOneWidget);
      tester.view.physicalSize = const Size(390, 844) * DashSize.pixelRatio;
      await h.settle();
      expect(inShell(find.text(h.t('common.columns'))), findsNothing);
    });

    testWidgets('SET-SHL-017 the confirm: Cancel and Escape both cancel', (
      tester,
    ) async {
      final h = await pumpBrand(
        tester,
        path: '/settings/delivery-zones$_helio',
      );
      final id = DeliverySeed.zoneId('heliopolis', 3);
      await h.tap(inShell(byKey('dzn-delete-$id')));
      final confirm = find.byType(DashConfirmDialog);
      expect(tester.widget<DashConfirmDialog>(confirm).destructive, isTrue);
      await h.tap(find.descendant(of: confirm, matching: find.text('Cancel')));
      expect(confirm, findsNothing);
      await h.tap(inShell(byKey('dzn-delete-$id')));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(confirm, findsNothing);
      expect(h.server.callsTo(DeliveryRoutes.zone, method: 'DELETE'), isEmpty);
    });

    testWidgets('SET-SHL-018 Escape closes a dialog (Enter submitting forms: '
        'SET-BRD-017)', (tester) async {
      final h = await pumpBrand(
        tester,
        path: '/settings/payment-methods?edit=new',
      );
      expect(find.byType(PaymentMethodDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(find.byType(PaymentMethodDialog), findsNothing);
    });

    testWidgets('SET-SHL-020 no org in scope: Brand asks nothing; Payment '
        'methods says "Select an organization"', (tester) async {
      final h = await pumpBrand(tester, persona: Persona.platform);
      expect(h.server.callsTo(orgRoute, method: 'GET'), isEmpty);
      expect(find.byType(BrandPage), findsOneWidget);
      await h.go('/settings/payment-methods');
      expect(inShell(find.text('Select an organization')), findsOneWidget);
    });

    testWidgets('SET-SHL-021 (divergence) search covers every column, '
        'whatever the first row holds', (tester) async {
      final m = setupMockServer();
      final stations = m.db[KitchenSeed.stationsTable];
      stations.update(KitchenSeed.stationId('zamalek', 'bar'), {
        'printer_brand': null,
        'printer_ip': null,
      });
      stations.update(KitchenSeed.stationId('zamalek', 'kitchen'), {
        'printer_brand': 'epson',
        'printer_ip': '192.168.10.30',
        'printer_port': 9100,
      });
      final h = await pumpBrand(
        tester,
        path: '/settings/kitchen-stations?branchId=${SeedIds.zamalek}',
        backend: m,
      );
      final table = inShell(byKey('kitchen-stations-table'));
      await h.enterText(
        find
            .descendant(of: table, matching: find.byType(DashSearchInput))
            .first,
        'epson',
      );
      await h.flushTimers();
      final rows = tester
          .widget<DashDataTable<KitchenStation>>(table)
          .rows
          .length;
      expect(rows, greaterThan(0));
      expect(
        find.descendant(of: table, matching: find.text('Kitchen')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: table, matching: find.text('Bar')),
        findsNothing,
      );
    });
  });
}
