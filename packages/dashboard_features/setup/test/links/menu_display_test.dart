// The "Menu (no prices)" section on Settings › Links (the web's
// `menu-display-section.tsx`, 57f0dc1): on every plan; on Free the links
// page's own sections are locked and nothing behind them is fetched.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashSwitch;
import 'package:dashboard_setup/src/links/links_page.dart';
import 'package:dashboard_setup/src/mock/links_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'support.dart';

Future<void> _show(DashHarness h, Finder f) async {
  await h.tester.ensureVisible(f);
  await h.settle();
}

String _text(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

Finder _keyStarting(String prefix) => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(prefix),
);

void main() {
  testWidgets('paid: the editor as before, the section under it', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    expect(find.byType(LinksEditor), findsOneWidget);
    final section = byKey('menu-display-section');
    await _show(h, section);
    expect(section, findsOneWidget);
    expect(find.text(h.t('menuDisplay.editor.title')), findsOneWidget);
    // Sabah has its own host: the page is its `/menu`.
    expect(
      inKey(
        'menu-display-url',
        find.text('https://sabah-coffee.madar-pos.cloud/menu'),
      ),
      findsOneWidget,
    );
    // On: Open is offered, the off note is not.
    expect(byKey('menu-display-open'), findsOneWidget);
    expect(byKey('menu-display-off-note'), findsNothing);
    expect(gets(h, LinksRoutes.page), 1);
    expect(gets(h, LinksRoutes.menuDisplay), 1);
    expect(byKey('paid-lock-branding'), findsNothing);
  });

  testWidgets('a shop with no host of its own: the generic loyalty host', (
    tester,
  ) async {
    final m = setupMockServer();
    m.db['orgs'].update(SeedIds.sabahOrg, {'custom_branding': false});
    final h = await pumpLinks(tester, backend: m);
    await _show(h, byKey('menu-display-url'));
    expect(
      inKey(
        'menu-display-url',
        find.text('https://loyalty.madar-pos.cloud/menu/${SeedIds.sabahOrg}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Free: only the section is usable; the rest is locked and '
      'never fetched', (tester) async {
    final h = await pumpLinks(tester, overrides: [freePlan]);
    expect(byKey('links-free'), findsOneWidget);
    expect(byKey('menu-display-section'), findsOneWidget);
    expect(byKey('paid-lock-branding'), findsOneWidget);
    expect(byKey('links-locked-sections'), findsOneWidget);
    expect(find.text(h.t('links.editor.lockedTitle')), findsOneWidget);
    expect(find.text(h.t('plan.lock.badge')), findsOneWidget);
    expect(find.byType(LinksEditor), findsNothing);
    // The locked headings are not inputs.
    expect(
      find.descendant(
        of: byKey('links-locked-sections'),
        matching: find.byType(EditableText),
      ),
      findsNothing,
    );
    expect(gets(h, LinksRoutes.page), 0);
    expect(gets(h, LinksRoutes.public), 0);
    expect(gets(h, LinksRoutes.qr), 0);
    expect(gets(h, LinksRoutes.menuDisplay), 1);
  });

  testWidgets('save sends the switch, trimmed titles and the branch', (
    tester,
  ) async {
    final m = setupMockServer();
    final h = await pumpLinks(tester, backend: m, overrides: [freePlan]);
    final branches = m.db['branches']
        .query(
          filters: {'org_id': SeedIds.sabahOrg, 'is_active': true},
          sort: 'created_at',
        )
        .where((b) => (b['kind'] ?? 'branch') == 'branch')
        .toList();
    final first = branches.first['name']! as String;
    final last = branches.last;

    // The picker starts on the default, named after the first branch.
    expect(
      find.text(
        h.t('menuDisplay.editor.branchDefaultNamed', args: {'name': first}),
      ),
      findsOneWidget,
    );
    expect(_text(tester, 'menu-display-title-en-1'), 'Our menu');

    await h.tap(inKey('menu-display-enabled', find.byType(DashSwitch)));
    await h.enterText(_keyStarting('menu-display-title-en-'), '  Drinks  ');
    await h.enterText(_keyStarting('menu-display-title-ar-'), '');
    await h.tap(byKey('menu-display-branch'));
    await h.tap(find.text(last['name']! as String).last);
    await _show(h, byKey('menu-display-save'));
    await h.tap(byKey('menu-display-save'));
    await h.expectToast(h.t('menuDisplay.editor.saved'));

    final body = lastBody(h, 'PUT', LinksRoutes.menuDisplay);
    expect(body['enabled'], isFalse);
    expect(body['title_en'], 'Drinks');
    expect(body['title_ar'], isNull);
    expect(body['branch_id'], last['id']);
    final row = m.db[menuDisplayTable].get(SeedIds.sabahOrg);
    expect(row['enabled'], isFalse);
    // Saved off: the address says how to open it, and Open is gone.
    await _show(h, byKey('menu-display-url'));
    expect(byKey('menu-display-off-note'), findsOneWidget);
    expect(byKey('menu-display-open'), findsNothing);
    // The links page was never written.
    expect(h.server.callsTo(LinksRoutes.page, method: 'PUT'), isEmpty);
  });

  testWidgets('a title over 60 does not type past the limit', (tester) async {
    final h = await pumpLinks(tester, overrides: [freePlan]);
    await h.enterText(_keyStarting('menu-display-title-en-'), 'x' * 70);
    expect(_text(tester, 'menu-display-title-en-1'), 'x' * 60);
  });

  testWidgets('QR asks for the menu code; Copy copies the address', (
    tester,
  ) async {
    final h = await pumpLinks(tester, overrides: [freePlan]);
    final clip = FakeClipboard(tester);
    await _show(h, byKey('menu-display-copy'));
    await h.tap(byKey('menu-display-copy'));
    expect(clip.text, 'https://sabah-coffee.madar-pos.cloud/menu');
    await h.expectToast(h.t('links.editor.copied'));

    await h.tap(byKey('menu-display-qr'));
    final call = h.server.callsTo(LinksRoutes.qr, method: 'GET').last;
    expect(call.query['target'], ['menu_display']);
    expect(find.text(h.t('menuDisplay.editor.qrTitle')), findsOneWidget);
    await h.flushTimers();
  });

  testWidgets('a failed read says so and retries', (tester) async {
    final m = setupMockServer();
    m.server.fail(
      'GET',
      LinksRoutes.menuDisplay,
      MockResponse.error(500, 'Database is down'),
    );
    final h = await pumpLinks(tester, backend: m, overrides: [freePlan]);
    expect(byKey('menu-display-error'), findsOneWidget);
    await h.tapText(h.t('common.retry'));
    expect(byKey('menu-display-section'), findsOneWidget);
  });
}
