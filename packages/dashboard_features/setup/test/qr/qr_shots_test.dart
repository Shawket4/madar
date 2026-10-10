// The QR page's screenshot matrix: the default state at every size in
// en-light and ar-dark, plus the made codes, the in-mall errors, the table
// sheet, the preview and the loading / failed / no-org states at
// desktop-en-light and phone-ar-light.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_setup/src/qr/qr_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qr_support.dart';

const _shot = 'qr';

/// One PNG per screen of the page, at most four.
Future<void> shootPage(DashHarness h, String name) async {
  ScrollableState? state;
  for (final e
      in find
          .ancestor(of: find.byType(QrPage), matching: find.byType(Scrollable))
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

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpQr(tester, size: size, locale: lang, dark: dark);
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final at = '${size.name} $lang';

    testWidgets('org codes made, $at', (tester) async {
      final m = setupMockServer();
      for (final r in m.db['booking_settings'].rows) {
        r['enabled'] = false;
      }
      final h = await pumpQr(tester, size: size, locale: lang, backend: m);
      await h.tap(generateOf(QrKind.orgOrder));
      await h.tap(generateOf(QrKind.orgBooking));
      await shootPage(h, 'org-made');
    });

    testWidgets('branch codes, in-mall errors and the table sheet, $at', (
      tester,
    ) async {
      final h = await pumpQr(
        tester,
        size: size,
        locale: lang,
        query: atBranch(SeedIds.maadi),
      );
      await h.tap(generateOf(QrKind.branchOrder));
      await h.tap(generateOf(QrKind.branchBooking));
      await h.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('qr-place')),
          matching: find.byType(EditableText),
        ),
        'x' * 81,
      );
      await h.tap(generateOf(QrKind.branchOrderInMall));
      await h.tap(find.byKey(const ValueKey('qr-tables-make')));
      await shootPage(h, 'branch-made');
    });

    testWidgets('preview, $at', (tester) async {
      final h = await pumpQr(
        tester,
        size: size,
        locale: lang,
        query: atBranch(SeedIds.heliopolis),
      );
      await h.tap(find.byKey(const ValueKey('qr-tables-make')));
      await h.tap(
        find.descendant(
          of: find.byKey(const ValueKey('qr-tables-sheet')),
          matching: find.text('T1'),
        ),
      );
      await h.shot('$_shot/preview');
    });

    testWidgets('tables loading, $at', (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', QrRoutes.tables);
      final h = await pumpQr(
        tester,
        size: size,
        locale: lang,
        backend: m,
        query: atBranch(SeedIds.heliopolis),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('qr-tables')));
      await tester.pump();
      await h.shot('$_shot/tables-loading');
      gate.release();
      await h.settle();
    });

    testWidgets('tables failed, $at', (tester) async {
      final m = setupMockServer();
      m.server.fail(
        'GET',
        QrRoutes.tables,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpQr(
        tester,
        size: size,
        locale: lang,
        backend: m,
        query: atBranch(SeedIds.heliopolis),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('qr-tables')));
      await h.settle();
      await h.shot('$_shot/tables-failed');
    });

    testWidgets('no org, $at', (tester) async {
      final h = await pumpQr(
        tester,
        size: size,
        locale: lang,
        persona: Persona.platform,
        pickOrg: false,
      );
      h.allowUnmatched = true;
      await h.shot('$_shot/no-org');
    });
  }
}
