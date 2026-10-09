// The combo editor's screenshot matrix: the default state at every size in
// English light and Arabic dark, then each other state at desktop English
// light and phone Arabic light.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Shoots the editor top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = inEditor(find.byType(Scrollable)).first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('combo-editor/$name-$i');
    if (y >= position.maxScrollExtent || i >= 8) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('default (Morning Croissant), $tag', (tester) async {
        final h = await pumpEditor(
          tester,
          path: comboPath('morning-croissant'),
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final tag = '${size.name} $lang';

    testWidgets('new combo, $tag', (tester) async {
      final h = await pumpEditor(tester, size: size, locale: lang);
      await shootPage(h, 'new');
    });

    testWidgets('read only (manager), $tag', (tester) async {
      final h = await pumpEditor(
        tester,
        path: comboPath('brunch-for-two'),
        persona: Persona.manager,
        size: size,
        locale: lang,
      );
      await shootPage(h, 'read-only');
    });

    testWidgets('loading, $tag', (tester) async {
      final s = editorServer();
      final gate = s.server.hold('GET', '/combos/{id}');
      final h = await DashHarness.pump(
        tester,
        areas: const [catalogOffersArea],
        path: comboPath('coffee-cookie'),
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
      );
      await h.shot('combo-editor/loading');
      gate.release();
      await debounce(h);
    });

    testWidgets('error, $tag', (tester) async {
      final s = editorServer();
      s.server.fail(
        'GET',
        '/combos/{id}',
        MockResponse.error(500, 'The menu store is down'),
        times: null,
      );
      final h = await pumpEditor(
        tester,
        path: comboPath('coffee-cookie'),
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
      );
      await h.shot('combo-editor/error');
    });

    testWidgets('save errors, $tag', (tester) async {
      final h = await pumpEditor(tester, size: size, locale: lang);
      await typeInto(h, h.t('combos.price'), '-5');
      await tapLabelled(h, h.t('combos.create'));
      await h.shot('combo-editor/save-errors');
      await h.flushTimers();
    });

    testWidgets('delete confirm, $tag', (tester) async {
      final h = await pumpEditor(
        tester,
        path: comboPath('morning-croissant'),
        size: size,
        locale: lang,
      );
      await tapLabelled(h, h.t('common.delete'));
      await h.shot('combo-editor/delete-confirm');
    });

    testWidgets('saving, $tag', (tester) async {
      final h = await pumpEditor(
        tester,
        path: comboPath('coffee-cookie'),
        size: size,
        locale: lang,
      );
      await typeInto(h, h.t('combos.price'), '125');
      final gate = h.server.hold('PUT', '/combos/{id}');
      await tapLabelled(h, h.t('common.save'));
      await h.shot('combo-editor/saving');
      gate.release();
      await h.settle();
      await h.flushTimers();
    });

    testWidgets('date picker, $tag', (tester) async {
      final h = await pumpEditor(
        tester,
        path: comboPath('kids-cocoa'),
        size: size,
        locale: lang,
      );
      final first = inEditor(
        find.byWidgetPredicate(
          (w) =>
              w is DashDateField &&
              w.semanticLabel == h.t('combos.windows.fromDate'),
        ),
      );
      await h.tester.ensureVisible(first);
      await h.tap(first);
      await h.shot('combo-editor/date-picker');
    });

    for (final failed in [false, true]) {
      final state = failed ? 'failed' : 'loading';
      testWidgets('price check $state, $tag', (tester) async {
        final s = editorServer();
        MockGate? gate;
        if (failed) {
          s.server.fail(
            'POST',
            '/combos/economics',
            MockResponse.error(503, 'Costing is being rebuilt'),
            times: null,
          );
        } else {
          gate = s.server.hold('POST', '/combos/economics');
        }
        final h = await pumpEditor(
          tester,
          path: comboPath('coffee-cookie'),
          server: s.server,
          db: s.db,
          size: size,
          locale: lang,
        );
        await h.tester.ensureVisible(labelled(h.t('combos.econ.title')).first);
        await h.settle();
        await h.shot('combo-editor/price-check-$state');
        gate?.release();
        await h.settle();
      });
    }
  }
}
