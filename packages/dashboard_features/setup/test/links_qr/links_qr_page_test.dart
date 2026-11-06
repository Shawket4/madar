// Settings › Links & QR codes (SET-LQR-001 – 008): one page for the links
// page, the menu without prices and every QR code; its jump chips, landing
// on a section, the old addresses redirecting here, the one settings entry,
// what each plan sees, and what resting on its entry warms.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_setup/src/brand_appearance/settings_shell.dart';
import 'package:dashboard_setup/src/links/links_page.dart';
import 'package:dashboard_setup/src/links_qr/links_qr_page.dart';
import 'package:dashboard_setup/src/qr/codes_section.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../qr/qr_support.dart';
import '../support.dart' show pumpSetup;

const _links = ValueKey('links-qr-links');
const _menu = ValueKey('links-qr-menu');
const _codes = ValueKey('links-qr-codes');

/// The page's vertical scroller.
ScrollableState _scrollable(WidgetTester tester) {
  for (final e
      in find
          .ancestor(
            of: find.byType(LinksQrPage),
            matching: find.byType(Scrollable),
          )
          .evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis == Axis.vertical) return s;
  }
  throw StateError('no vertical scroll');
}

ScrollPosition _scroll(WidgetTester tester) => _scrollable(tester).position;

/// [key]'s top, measured from the top of the page's viewport.
double _top(WidgetTester tester, Key key) {
  final box = _scrollable(tester).context.findRenderObject()! as RenderBox;
  return tester.getTopLeft(find.byKey(key)).dy -
      box.localToGlobal(Offset.zero).dy;
}

/// The page scrolled to [key]: at the top of the view, or as near as the
/// page's end allows.
bool _landed(WidgetTester tester, Key key) {
  final top = _top(tester, key);
  final p = _scroll(tester);
  return top.abs() < 1 ||
      (p.pixels > 0 &&
          (p.pixels - p.maxScrollExtent).abs() < 1 &&
          top >= 0 &&
          top < p.viewportDimension);
}

void main() {
  testWidgets('SET-LQR-001 the header, its line, the jump chips, and the '
      'three sections in setup order', (tester) async {
    final h = await pumpQr(tester);
    expect(inPage(find.text(h.t('linksQr.title'))), findsOneWidget);
    expect(inPage(find.text(h.t('linksQr.desc'))), findsOneWidget);
    final chips = find.byKey(const ValueKey('links-qr-jumps'));
    for (final key in ['linksQr.jump.links', 'linksQr.jump.menu']) {
      expect(
        find.descendant(of: chips, matching: find.text(h.t(key))),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: chips,
        matching: find.text(h.t('linksQr.jump.codes')),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(h.t('linksQr.jump.label')), findsOneWidget);
    final links = tester.getTopLeft(find.byKey(_links)).dy;
    final menu = tester.getTopLeft(find.byKey(_menu)).dy;
    final codes = tester.getTopLeft(find.byKey(_codes)).dy;
    expect(links, lessThan(menu));
    expect(menu, lessThan(codes));
    expect(find.byType(LinksEditor), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-display-section')), findsOneWidget);
    expect(find.byType(QrCodesSection), findsOneWidget);
    // Paid: nothing locked.
    expect(find.byKey(const ValueKey('paid-lock-branding')), findsNothing);
    expect(find.byKey(const ValueKey('paid-lock-online')), findsNothing);
  });

  testWidgets('SET-LQR-002 a jump chip brings its section into view', (
    tester,
  ) async {
    final h = await pumpQr(tester);
    expect(_scroll(tester).pixels, 0);
    await h.tap(find.byKey(const ValueKey('links-qr-jump-codes')));
    await tester.pump(const Duration(milliseconds: 400));
    await h.settle();
    expect(_scroll(tester).pixels, greaterThan(0));
    expect(_landed(tester, _codes), isTrue);
    await h.tap(find.byKey(const ValueKey('links-qr-jump-links')));
    await tester.pump(const Duration(milliseconds: 400));
    await h.settle();
    expect(_landed(tester, _links), isTrue);
  });

  testWidgets('SET-LQR-003 ?section=codes lands on the codes, once the links '
      'section above them has its height', (tester) async {
    final m = setupMockServer();
    final gate = m.server.hold('GET', '/orgs/{id}/links-page');
    await pumpQr(tester, backend: m, query: '?section=codes');
    // The editor is still loading: the page waits rather than scrolling to
    // a spot the editor is about to push down.
    expect(_scroll(tester).pixels, 0);
    gate.release();
    await pumpQrSettle(tester);
    expect(_landed(tester, _codes), isTrue);
  });

  testWidgets('SET-LQR-003 Free has no editor to wait for: straight to the '
      'menu', (tester) async {
    await pumpQr(tester, query: '?section=menu', overrides: [freePlan]);
    expect(_landed(tester, _menu), isTrue);
  });

  testWidgets('SET-LQR-004 the old addresses land here: Links page on the '
      'page, the QR pages on the codes', (tester) async {
    final h = await pumpQr(tester);
    await h.go('/settings/links');
    expect(h.location.toString(), '/settings/links-qr');
    await h.go('/settings/qr');
    expect(h.location.toString(), '/settings/links-qr?section=codes');
    await h.go('/settings/brand');
    await h.go('/qr');
    expect(h.location.toString(), '/settings/links-qr?section=codes');
    await h.settle();
    expect(_landed(tester, _codes), isTrue);
  });

  testWidgets('SET-LQR-005 one settings entry, "Links & QR codes", in Ways '
      'to sell, on every plan; the two it replaced are gone', (tester) async {
    for (final free in [false, true]) {
      final h = await pumpQr(tester, overrides: [if (free) freePlan]);
      final groups = SettingsShell.groupsFor(
        h.container.read(authzProvider),
        h.container.read(orgModulesProvider),
        features: h.container.read(planFeaturesProvider),
      );
      final all = [
        for (final g in groups)
          for (final i in g.items) i.to,
      ];
      expect(
        all.where((p) => p == '/settings/links-qr'),
        hasLength(1),
        reason: free ? 'Free' : 'paid',
      );
      expect(all, isNot(contains('/settings/links')));
      expect(all, isNot(contains('/settings/qr')));
      final group = groups.firstWhere(
        (g) => g.items.any((i) => i.to == '/settings/links-qr'),
      );
      expect(group.labelKey, 'settings.groupChannels');
      final entry = group.items.firstWhere((i) => i.to == '/settings/links-qr');
      expect(entry.labelKey, 'settings.linksAndQr');
      expect(entry.icon, 'qrcode');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('settings-rail')),
          matching: find.text(h.t('settings.linksAndQr')),
        ),
        findsOneWidget,
      );
      // Ungated: the plan has the page, module `pos`.
      expect(featureOfPath('/settings/links-qr'), isNull);
      expect(moduleOfPath('/settings/links-qr'), 'pos');
    }
  });

  testWidgets('SET-LQR-006 Free: the page opens; the links page is locked '
      'and never read; the menu is usable; the paid codes are locked', (
    tester,
  ) async {
    final h = await pumpQr(tester, overrides: [freePlan]);
    expect(find.byKey(const ValueKey('links-free')), findsOneWidget);
    expect(find.byKey(const ValueKey('paid-lock-branding')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-display-section')), findsOneWidget);
    expect(find.byKey(const ValueKey('paid-lock-online')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('qr-kind-orgMenuDisplay')),
      findsOneWidget,
    );
    expect(h.server.callsTo('/orgs/{id}/links-page'), isEmpty);
    expect(h.server.callsTo('/public/orgs/links'), isEmpty);
    expect(h.server.callsTo(QrRoutes.tables), isEmpty);
  });

  testWidgets('SET-LQR-007 SET-SHL-013 resting on the entry warms the '
      'editors\' reads and the tables; opening asks nothing more but the '
      'output sample', (tester) async {
    final h = await pumpSetup(
      tester,
      path: '/settings/brand${atBranch(SeedIds.heliopolis)}',
    );
    final entry = find.descendant(
      of: find.byKey(const ValueKey('settings-rail')),
      matching: find.text(h.t('settings.linksAndQr')),
    );
    int gets(String route) => h.server.callsTo(route, method: 'GET').length;
    final page = gets('/orgs/{id}/links-page');
    final menu = gets('/orgs/{id}/links-page/menu-display');
    final tables = gets(QrRoutes.tables);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(entry));
    await h.settle();
    await mouse.moveTo(Offset.zero);
    // The codes themselves are never warmed with the page: each one mints
    // a short link.
    expect(h.server.callsTo(QrRoutes.linksQr), isEmpty);
    await h.tap(entry);
    expect(h.location.path, '/settings/links-qr');
    expect(gets('/orgs/{id}/links-page'), page + 1);
    expect(gets('/orgs/{id}/links-page/menu-display'), menu + 1);
    expect(gets(QrRoutes.tables), tables + 1);
    // Only the output sample was asked for on opening.
    expect(
      [for (final c in h.server.callsTo(QrRoutes.linksQr)) queryOf(c)],
      [
        {'card': 'true', 'dpi': '150'},
      ],
    );
  });

  testWidgets('SET-LQR-008 no org in scope: "Select an organization", '
      'nothing asked', (tester) async {
    final h = await pumpQr(tester, persona: Persona.platform, pickOrg: false);
    h.allowUnmatched = true;
    expect(inPage(find.text(h.t('branches.pickOrg'))), findsOneWidget);
    expect(find.byKey(_links), findsNothing);
    expect(h.server.callsTo('/orgs/{id}/links-page'), isEmpty);
    expect(h.server.callsTo(QrRoutes.linksQr), isEmpty);
  });
}

/// Lets a released read land and the page settle after it.
Future<void> pumpQrSettle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}
