// The Inventory settings screenshot matrix: the page at {phone, tablet,
// desktop} x {en light, ar dark}; the categories' loading, error and empty
// states, the inline rename, the field's refusal and both delete dialogs at
// desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set; the
// pages still render (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];
const _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  ScrollableState? state;
  for (final e
      in find
          .ancestor(of: page, matching: find.byType(Scrollable))
          .evaluate()
          .followedBy(
            find
                .descendant(of: page, matching: find.byType(Scrollable))
                .evaluate(),
          )) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis == Axis.vertical && s.position.maxScrollExtent > 0) {
      state = s;
      break;
    }
  }
  if (state == null) {
    await h.shot('inv_settings/$name-1');
    return;
  }
  final position = state.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('inv_settings/$name-$i');
    if (y >= position.maxScrollExtent || i >= 5) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpSettings(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang';
    Future<DashHarness> open(
      WidgetTester tester, [
      ({MockServer server, MockDb db})? s,
    ]) => pumpSettings(
      tester,
      size: size,
      locale: lang,
      dark: dark,
      server: s?.server,
      db: s?.db,
    );

    testWidgets('loading, $tag', (tester) async {
      final s = settingsServer();
      s.server.hold('GET', settingsRoute);
      s.server.hold('GET', categoriesRoute);
      final h = await open(tester, s);
      await shootPage(h, 'loading');
    });

    testWidgets('categories failed, settings failed, $tag', (tester) async {
      final s = settingsServer();
      for (final r in [settingsRoute, categoriesRoute]) {
        s.server.fail('GET', r, MockResponse.error(500, 'boom'), times: null);
      }
      final h = await open(tester, s);
      await shootPage(h, 'failed');
    });

    testWidgets('no categories, $tag', (tester) async {
      final s = settingsServer();
      s.server.fail(
        'GET',
        categoriesRoute,
        MockResponse.ok(const []),
        times: null,
      );
      final h = await open(tester, s);
      await shootPage(h, 'empty');
    });

    testWidgets('rename and a refused value, $tag', (tester) async {
      final h = await open(tester);
      await h.enterText(inPage(byKey('inv-settings-pct')), '-2');
      await h.tap(inPage(byKey('inv-settings-save')));
      await h.tap(inRow('milk', byKey('inv-category-edit-${cat('milk')}')));
      await h.enterText(inPage(byKey('inv-category-rename')), 'Fresh milk');
      await h.enterText(inPage(byKey('inv-settings-new-name')), 'Seasonal');
      await shootPage(h, 'editing');
    });

    testWidgets('delete dialog, in use, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(inRow('milk', byKey('inv-category-delete-${cat('milk')}')));
      await h.shot('inv_settings/delete-in-use');
      await h.tap(inDialog(find.byType(DashSelectTrigger)));
      await h.shot('inv_settings/delete-picker');
    });

    testWidgets('delete dialog, empty, $tag', (tester) async {
      final s = settingsServer();
      addEmptyCategory(s.db);
      final h = await open(tester, s);
      await h.tap(
        inRow(
          'seasonal',
          byKey('inv-category-delete-${InvIds.category('seasonal')}'),
        ),
      );
      await h.shot('inv_settings/delete-empty');
    });
  }
}
