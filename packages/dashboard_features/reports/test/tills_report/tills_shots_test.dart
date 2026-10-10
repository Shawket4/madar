// The Till sessions screenshot matrix: the default page at phone, tablet and
// desktop in English light and Arabic dark (one PNG per screen of scroll),
// then every other state at desktop-en-light and phone-ar-light.
// Run with FDASH_SHOTS=<dir> to write the PNGs.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];
const _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

/// One PNG per screen of the page's scroll (at most three).
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(of: tillsPage, matching: find.byType(Scrollable))
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var y = 0.0;
  for (var i = 1; i <= 3; i++) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('reports-tills/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
  }
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      testWidgets('default, ${size.name} $lang ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        final h = await pumpTills(tester, size: size, locale: lang, dark: dark);
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang';
    final ar = lang == 'ar';

    Future<DashHarness> pump(
      WidgetTester tester, {
      ({MockServer server, MockDb db})? s,
      Persona persona = Persona.owner,
    }) => pumpTills(
      tester,
      size: size,
      locale: lang,
      dark: dark,
      persona: persona,
      server: s?.server,
      db: s?.db,
    );

    testWidgets('sales, $tag', (tester) async {
      final h = await pump(tester);
      await openTab(h, h.t('reports.tills.tabSales'));
      await shootPage(h, 'sales');
    });

    testWidgets('timing, $tag', (tester) async {
      final h = await pump(tester);
      await openTab(h, h.t('reports.tills.tabTiming'));
      await shootPage(h, 'timing');
    });

    testWidgets('closing cells, $tag', (tester) async {
      final h = await pump(tester, s: serverWith(webSessions()));
      await shootPage(h, 'cells');
    });

    if (size != DashSize.phone) {
      testWidgets('closing cells, scrolled to the end, $tag', (tester) async {
        final h = await pump(tester, s: serverWith(webSessions()));
        final sideways = find
            .descendant(of: tillsPage, matching: find.byType(Scrollable))
            .evaluate()
            .map((e) => (e as StatefulElement).state as ScrollableState)
            .where((s) => s.position.axis == Axis.horizontal)
            .reduce(
              (a, b) => a.position.maxScrollExtent >= b.position.maxScrollExtent
                  ? a
                  : b,
            );
        sideways.position.jumpTo(sideways.position.maxScrollExtent);
        await h.settle(rounds: 2);
        await h.shot('reports-tills/cells-end');
      });
    }

    testWidgets('loading, $tag', (tester) async {
      final s = tillsServer();
      final gate = s.server.hold('GET', tillsTpl);
      final h = await pump(tester, s: s);
      await h.shot('reports-tills/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = tillsServer();
      s.server.fail(
        'GET',
        tillsTpl,
        MockResponse.error(500, ar ? 'الخادم مشغول' : 'The ledger is busy'),
        times: null,
      );
      final h = await pump(tester, s: s);
      await h.shot('reports-tills/failed');
    });

    testWidgets('range refused, $tag', (tester) async {
      final s = tillsServer();
      s.server.fail(
        'GET',
        tillsTpl,
        MockResponse.error(400, 'More than 5000 till sessions in this range'),
        times: null,
      );
      final h = await pump(tester, s: s);
      await h.shot('reports-tills/refused');
    });

    testWidgets('empty, $tag', (tester) async {
      final h = await pump(tester, s: serverWith(const []));
      await h.shot('reports-tills/empty');
      await openTab(h, h.t('reports.tills.tabSales'));
      await h.shot('reports-tills/empty-sales');
    });

    testWidgets('restricted, $tag', (tester) async {
      final h = await pump(tester, persona: Persona.limited);
      await h.shot('reports-tills/restricted');
    });

    testWidgets('export menu, $tag', (tester) async {
      final h = await pump(tester);
      await h.tap(exportButton);
      await h.shot('reports-tills/export-menu');
    });

    if (size != DashSize.phone) {
      testWidgets('columns menu, $tag', (tester) async {
        final h = await pump(tester);
        await h.tap(pageText(h.t('common.columns')));
        await h.shot('reports-tills/columns-menu');
      });
    }

    testWidgets('search, $tag', (tester) async {
      final h = await pump(tester);
      await h.enterText(
        find.descendant(
          of: inPage(find.byType(DashSearchInput)),
          matching: find.byType(EditableText),
        ),
        'Zamalek',
      );
      await h.shot('reports-tills/search');
    });
  }
}
