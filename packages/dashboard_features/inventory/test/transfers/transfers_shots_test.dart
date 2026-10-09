// The Transfers screenshot matrix: the default page at every size in EN
// light and AR dark (Zamalek), then at desktop-en-light and phone-ar-light:
// loading, failed, empty, Differences, a warehouse scope, the drawer (a
// request, a short receipt), the confirm, the receive, decline, transfer
// (send and request) and replenish dialogs.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashIconButton;
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
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang';
    Future<DashHarness> open(
      WidgetTester tester, {
      MockServer? server,
      MockDb? db,
      bool all = false,
    }) => pumpTransfers(
      tester,
      size: size,
      locale: lang,
      dark: dark,
      server: server,
      db: db,
      branch: all ? null : SeedIds.zamalek,
    );

    testWidgets('loading, $tag', (tester) async {
      final s = transfersServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpTransfers(
        tester,
        size: size,
        locale: lang,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      await h.shot('transfers/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = transfersServer();
      s.server.fail(
        'GET',
        listRoute,
        MockResponse.error(500, 'Database unavailable'),
        times: null,
      );
      final h = await pumpTransfers(
        tester,
        size: size,
        locale: lang,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      await h.shot('transfers/failed');
    });

    testWidgets('empty, $tag', (tester) async {
      final h = await pumpTransfers(
        tester,
        size: size,
        locale: lang,
        branch: SeedIds.heliopolis,
      );
      await h.tap(
        find.descendant(
          of: inPage(byKey('transfers-status')),
          matching: find.text(h.t('inventory.transfers.status.cancelled')),
        ),
      );
      await h.shot('transfers/empty');
    });

    testWidgets('differences, $tag', (tester) async {
      final s = transfersServer();
      receiveShort(s.db);
      final h = await pumpTransfers(
        tester,
        size: size,
        locale: lang,
        server: s.server,
        db: s.db,
      );
      await h.tap(
        find.descendant(
          of: inPage(byKey('transfers-status')),
          matching: find.text(h.t('inventory.transfers.differences')),
        ),
      );
      await shootPage(h, 'differences');
    });

    testWidgets('warehouse, $tag', (tester) async {
      final s = transfersServer();
      withWarehouse(s.db);
      receiveShort(s.db);
      final h = await pumpTransfers(
        tester,
        size: size,
        locale: lang,
        server: s.server,
        db: s.db,
        branch: centralStore,
      );
      await h.shot('transfers/warehouse');
      await h.tap(inPage(byKey('transfers-replenish')));
      await pick(h, 'replenish-branch', 'Zamalek', scope: replenishDialog);
      await h.shot('transfers/replenish');
      await h.tap(inReplenish(byKey('replenish-review')));
      await h.shot('transfers/replenish-review');
    });

    testWidgets('drawer, $tag', (tester) async {
      final s = transfersServer();
      receiveShort(s.db);
      final h = await pumpTransfers(
        tester,
        size: size,
        locale: lang,
        server: s.server,
        db: s.db,
      );
      await openRow(h, 'TR-6');
      await h.shot('transfers/drawer-requested');
      await h.tap(inDrawer(byKey('transfer-step-decline')));
      await h.enterText(inClose(byKey('transfer-close-reason')), 'Short too');
      await h.shot('transfers/decline');
      await h.tap(inClose(byKey('transfer-close-back')));
      await h.tap(
        find.descendant(
          of: drawer,
          matching: find.byWidgetPredicate(
            (w) => w is DashIconButton && w.icon == 'x',
          ),
        ),
      );
      await openRow(h, 'TR-7');
      await h.shot('transfers/drawer-received');
    });

    testWidgets('steps, $tag', (tester) async {
      final s = transfersServer();
      final t = dispatchDraft(s.db);
      final cro =
          (t['lines']! as List).cast<MockRow>().firstWhere(
                (l) => l['ingredient_name'] == 'Croissant Dough',
              )['id']!
              as String;
      final h = await pumpTransfers(
        tester,
        size: size,
        locale: lang,
        server: s.server,
        db: s.db,
      );
      await openRow(h, 'TR-7');
      await h.shot('transfers/drawer-in-transit');
      await h.tap(inDrawer(byKey('transfer-step-receive')));
      await h.enterText(inReceive(byKey('receive-qty-$cro')), '11');
      await h.shot('transfers/receive');
    });

    testWidgets('dialog, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(inPage(byKey('transfers-new')));
      await pick(h, 'transfer-destination', 'Maadi');
      await pickIngredient(h, 0, 'Vanilla Syrup');
      await h.enterText(inDialog(byKey('transfer-qty-0')), '700');
      await h.tap(inDialog(byKey('transfer-add-line')));
      await h.shot('transfers/dialog-send');
      await h.tap(
        inDialog(find.text(h.t('inventory.transfers.modeRequest'))).first,
      );
      await h.shot('transfers/dialog-request');
    });

    testWidgets('confirm, $tag', (tester) async {
      final h = await open(tester, all: true);
      await openRow(h, 'TR-7');
      await h.tap(inDrawer(byKey('transfer-step-dispatch')));
      await h.shot('transfers/dispatch-confirm');
    });
  }
}
