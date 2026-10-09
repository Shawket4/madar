// The Transfers screenshot matrix: the default page at every size in EN
// light and AR dark (a branch and All branches), then loading, failed,
// empty, the row menu, the reverse confirm, the edit-note dialog and the
// New transfer dialog at desktop-en-light and phone-ar-light.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
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
    await h.shot('transfers/$name-1');
    return;
  }
  final position = state.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('transfers/$name-$i');
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
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('default, Zamalek, $tag', (tester) async {
        final h = await pumpTransfers(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          branch: SeedIds.zamalek,
        );
        await shootPage(h, 'default-zamalek');
      });
      testWidgets('default, all branches, $tag', (tester) async {
        final h = await pumpTransfers(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'default-all');
      });
    }
  }

  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang';
    Future<DashHarness> open(WidgetTester tester, {String? branch}) =>
        pumpTransfers(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          branch: branch ?? SeedIds.zamalek,
        );

    testWidgets('loading, $tag', (tester) async {
      final s = transfersServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpTransfers(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      await shootPage(h, 'loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = transfersServer();
      s.server.fail('GET', listRoute, MockResponse.error(500, 'Server error'));
      final h = await pumpTransfers(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      await shootPage(h, 'failed');
    });

    testWidgets('empty (Heliopolis), $tag', (tester) async {
      final h = await open(tester, branch: SeedIds.heliopolis);
      await shootPage(h, 'empty');
    });

    testWidgets('row menu and reverse confirm, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(menuOf('t1'));
      await h.shot('transfers/row-menu');
      await h.tap(menuItem(h.t('inventory.transfers.reverseTitle')));
      await h.shot('transfers/reverse-confirm');
    });

    testWidgets('edit note, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(menuOf('t1'));
      await h.tap(menuItem(h.t('inventory.transfers.editNote')));
      await h.shot('transfers/edit-note');
    });

    testWidgets('new transfer: blank, filled over on hand, same branch, '
        'picker, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(inPage(byKey('transfers-new')));
      await h.shot('transfers/dialog-blank');
      await pick(h, 'transfer-destination', 'Maadi');
      await pickIngredient(h, 'Vanilla Syrup');
      await h.enterText(inDialog(byKey('transfer-quantity')), '750');
      await h.enterText(
        inDialog(byKey('transfer-note')),
        lang == 'en' ? 'For the weekend rush' : 'لزحمة نهاية الأسبوع',
      );
      await h.shot('transfers/dialog-over');
      await h.tap(trigger('transfer-ingredient'));
      await h.shot('transfers/dialog-picker');
    });

    testWidgets('new transfer: nothing to send (Heliopolis), $tag', (
      tester,
    ) async {
      final h = await open(tester);
      await h.tap(inPage(byKey('transfers-new')));
      await h.tap(trigger('transfer-source'));
      await h.shot('transfers/dialog-source-open');
      await h.tap(option('Heliopolis').last);
      await h.tap(trigger('transfer-ingredient'));
      await h.shot('transfers/dialog-nothing');
    });
  }
}
