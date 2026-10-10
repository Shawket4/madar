// The Payment methods screenshot matrix: the default state at every size in
// {en light, ar dark}, and every other state (Availability, the editor, the
// icon list, loading, failed, empty, no branch, no org) at desktop-en-light
// and phone-ar-light. Writes PNGs only with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/payment_methods/payment_methods_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'pm_support.dart';

const _shot = 'payment-methods';

/// Shoots the page one screen at a time down its scroll (the settings
/// shell's), `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  ScrollableState? state;
  for (final e
      in find
          .ancestor(
            of: find.byType(PaymentMethodsPage),
            matching: find.byType(Scrollable),
          )
          .evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis == Axis.vertical) {
      state = s;
      break;
    }
  }
  if (state == null) return h.shot('$_shot/$name-1');
  final position = state.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('$_shot/$name-$i');
    if (y >= position.maxScrollExtent || i >= 4) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

Future<void> _availability(DashHarness h) => h.tap(
  inPage(
    find.descendant(
      of: find.byKey(const ValueKey('pm-tabs')),
      matching: find.text(h.t('paymentMethods.availability.title')),
    ),
  ),
);

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpPm(tester, size: size, locale: lang, dark: dark);
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final tag = '${size.name} $lang';
    Future<DashHarness> open(
      WidgetTester tester, {
      String query = '',
      Persona persona = Persona.owner,
      ({MockServer server, MockDb db})? backend,
    }) => pumpPm(
      tester,
      query: query,
      size: size,
      locale: lang,
      persona: persona,
      backend: backend,
    );

    testWidgets('availability, $tag', (tester) async {
      final h = await open(tester, query: zamalek);
      await _availability(h);
      await shootPage(h, 'availability');
    });

    testWidgets('availability restricted + invalid, $tag', (tester) async {
      final h = await open(tester, query: zamalek);
      await _availability(h);
      final k = 'allow-list-user-${SeedIds.user('karim')}';
      await h.tap(inEditor(k, find.byType(DashSwitch)));
      await h.tap(inEditor(k, find.text(h.t('common.save'))));
      await h.tester.ensureVisible(editor(k));
      await h.settle(rounds: 2);
      await h.shot('$_shot/availability-invalid');
    });

    testWidgets('availability no branch, $tag', (tester) async {
      final h = await open(tester);
      await _availability(h);
      await h.shot('$_shot/availability-no-branch');
    });

    testWidgets('availability loading, $tag', (tester) async {
      final m = setupMockServer();
      m.server.hold('GET', PmRoutes.availability);
      final h = await open(tester, query: zamalek, backend: m);
      await _availability(h);
      await h.shot('$_shot/availability-loading');
    });

    testWidgets('availability failed, $tag', (tester) async {
      final m = setupMockServer();
      m.server.fail(
        'GET',
        PmRoutes.availability,
        MockResponse.error(500, 'Service unavailable: try again'),
        times: null,
      );
      final h = await open(tester, query: zamalek, backend: m);
      await _availability(h);
      await h.shot('$_shot/availability-failed');
    });

    testWidgets('new dialog, $tag', (tester) async {
      final h = await open(tester, query: '?edit=new');
      await h.shot('$_shot/dialog-new');
      await h.tap(find.byKey(const ValueKey('pm-save')));
      await h.shot('$_shot/dialog-new-invalid');
    });

    testWidgets('edit dialog, $tag', (tester) async {
      final h = await open(tester, query: '?edit=${pmId('instapay')}');
      await h.shot('$_shot/dialog-edit');
      final scroll = find
          .ancestor(
            of: find.byKey(const ValueKey('pm-visible')),
            matching: find.byType(Scrollable),
          )
          .first;
      await h.tester.drag(scroll, const Offset(0, -600));
      await h.settle(rounds: 2);
      await h.shot('$_shot/dialog-edit-2');
    });

    testWidgets('icon list, $tag', (tester) async {
      final h = await open(tester, query: '?edit=new');
      await h.tap(
        find.descendant(
          of: find.byKey(const ValueKey('pm-icon')),
          matching: find.text(h.t('settings.pm.iconLabel.money')),
        ),
      );
      await h.shot('$_shot/icon-list');
    });

    testWidgets('loading, $tag', (tester) async {
      final m = setupMockServer();
      m.server.hold('GET', PmRoutes.list);
      final h = await open(tester, backend: m);
      await h.shot('$_shot/loading');
    });

    testWidgets('failed, $tag', (tester) async {
      final h = await open(tester, persona: Persona.limited);
      await h.shot('$_shot/failed');
    });

    testWidgets('empty, $tag', (tester) async {
      final m = setupMockServer();
      m.db['payment_methods'].clear();
      final h = await open(tester, backend: m);
      await h.shot('$_shot/empty');
    });

    testWidgets('no org, $tag', (tester) async {
      final h = await open(tester, persona: Persona.platform);
      await h.shot('$_shot/no-org');
    });
  }
}
