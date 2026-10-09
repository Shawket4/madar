// The purchasing screenshot matrix: each tab's default state at {phone,
// tablet, desktop} x {en light, ar dark}; every dialog and state at
// desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set;
// the pages still render (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scrolls = find.byType(Scrollable);
  ScrollableState? state;
  for (final e in scrolls.evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis == Axis.vertical && s.position.maxScrollExtent > 0) {
      state = s;
      break;
    }
  }
  if (state == null) {
    await h.shot('purchasing/$name-1');
    return;
  }
  final position = state.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('purchasing/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

/// The dialog / state shots: desktop in English light, phone in Arabic light.
const _stateModes = [(DashSize.desktop, 'en'), (DashSize.phone, 'ar')];

Future<DashHarness> _at(
  WidgetTester tester,
  DashSize size,
  String lang, {
  String path = purchasingPath,
  MockServer? server,
  MockDb? db,
}) => pumpPurchasing(
  tester,
  path: path,
  size: size,
  locale: lang,
  server: server,
  db: db,
);

Future<void> _menu(DashHarness h, String key, String item) async {
  await h.scrollUntilVisible(byKey(key));
  await h.tap(byKey(key));
  await h.tap(find.text(item).hitTestable().last);
}

void main() {
  for (final (size, lang) in _stateModes) {
    final tag = '${size.name} $lang';
    testWidgets('new purchase order, filled, $tag', (tester) async {
      final h = await _at(tester, size, lang, path: purchasingAt(SeedIds.zamalek));
      await h.tap(byKey('purchasing-new-order'));
      await h.shot('purchasing/po-dialog-empty');
      await h.tap(byKey('po-line-ingredient-0'));
      final options = find.byType(DashOptionList<String>);
      await h.enterText(options, 'Full Cream');
      await h.shot('purchasing/po-dialog-picker');
      await h.tap(
        find
            .descendant(of: options, matching: find.text('Full Cream Milk'))
            .hitTestable()
            .last,
      );
      await h.enterText(byKey('po-line-qty-0'), '2000');
      await h.tap(byKey('po-add-line'));
      await h.shot('purchasing/po-dialog-filled');
      await h.tap(byKey('po-expected'));
      await h.tap(
        find
            .descendant(
              of: find.byType(DashCalendar),
              matching: find.byWidgetPredicate(
                (w) => w is Text && (w.data == '5' || w.data == '٥'),
              ),
            )
            .hitTestable()
            .last,
      );
      await h.shot('purchasing/po-dialog-past-date');
    });

    testWidgets('create draft PO from reorder, $tag', (tester) async {
      final h = await _at(tester, size, lang, path: purchasingAt(SeedIds.zamalek));
      await h.tap(
        find.descendant(
          of: byKey('purchasing-tabs'),
          matching: find.text(h.t('inventory.purchasing.reorder')),
        ),
      );
      await h.tap(byKey('reorder-create-0'));
      await h.shot('purchasing/po-dialog-prefilled');
    });

    testWidgets('receive dialog and history, $tag', (tester) async {
      final h = await _at(tester, size, lang);
      final po = PurIds.po('po-1041');
      await _menu(h, 'po-menu-$po', h.t('inventory.purchasing.viewOrder'));
      await h.shot('purchasing/receive');
      await h.tap(
        find.descendant(
          of: byKey('receive-tabs'),
          matching: find.text(h.t('inventory.purchasing.deliveryHistory')),
        ),
      );
      await h.shot('purchasing/receive-history');
      await h.tap(find.text(h.t('common.cancel')).hitTestable().last);
      final returned = PurIds.po('po-1039');
      await _menu(h, 'po-menu-$returned', h.t('inventory.purchasing.viewOrder'));
      await h.tap(
        find.descendant(
          of: byKey('receive-tabs'),
          matching: find.text(h.t('inventory.purchasing.deliveryHistory')),
        ),
      );
      await h.shot('purchasing/receive-history-return');
    });

    testWidgets('supplier dialog and confirms, $tag', (tester) async {
      final h = await _at(tester, size, lang);
      await h.tap(
        find.descendant(
          of: byKey('purchasing-tabs'),
          matching: find.text(h.t('inventory.purchasing.suppliers')),
        ),
      );
      await _menu(
        h,
        'supplier-menu-${PurIds.supplier('metro')}',
        h.t('common.edit'),
      );
      await h.shot('purchasing/supplier-edit');
      await h.tap(find.text(h.t('common.cancel')).hitTestable().last);
      await _menu(
        h,
        'supplier-menu-${PurIds.supplier('metro')}',
        h.t('common.delete'),
      );
      await h.shot('purchasing/supplier-delete-confirm');
      await h.tap(find.text(h.t('common.cancel')).hitTestable().last);
      await h.tap(
        find.descendant(
          of: byKey('purchasing-tabs'),
          matching: find.text(h.t('inventory.purchasing.orders')),
        ),
      );
      final po = PurIds.po('po-1042');
      await _menu(h, 'po-menu-$po', h.t('inventory.purchasing.cancel'));
      await h.shot('purchasing/cancel-confirm');
    });

    testWidgets('states: loading, failed, empty, $tag', (tester) async {
      final s = purchasingServer();
      final gate = s.server.hold('GET', PurT.orders);
      var h = await _at(tester, size, lang, server: s.server, db: s.db);
      await h.shot('purchasing/orders-loading');
      gate.release();
      await h.settle();

      final f = purchasingServer();
      f.server.fail(
        'GET',
        PurT.orders,
        MockResponse.error(500, 'The ledger is resting'),
        times: null,
      );
      f.server.fail(
        'GET',
        PurT.reorder,
        MockResponse.error(500, 'Suggestions are resting'),
        times: null,
      );
      h = await _at(
        tester,
        size,
        lang,
        path: purchasingAt(SeedIds.zamalek),
        server: f.server,
        db: f.db,
      );
      await h.shot('purchasing/orders-failed');
      await h.tap(
        find.descendant(
          of: byKey('purchasing-tabs'),
          matching: find.text(h.t('inventory.purchasing.reorder')),
        ),
      );
      await h.shot('purchasing/reorder-failed');

      final e = purchasingServer();
      e.db[InvTables.purchaseOrders].removeWhere((_) => true);
      for (final r in e.db[InvTables.branchStock].rows) {
        r['par_min'] = null;
      }
      h = await _at(
        tester,
        size,
        lang,
        path: purchasingAt(SeedIds.zamalek),
        server: e.server,
        db: e.db,
      );
      await h.shot('purchasing/orders-empty');
      await h.tap(
        find.descendant(
          of: byKey('purchasing-tabs'),
          matching: find.text(h.t('inventory.purchasing.reorder')),
        ),
      );
      await h.shot('purchasing/reorder-empty');
    });
  }

  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('orders, all branches, $tag', (tester) async {
        final h = await pumpPurchasing(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'orders-all');
      });
      testWidgets('orders, Zamalek, $tag', (tester) async {
        final h = await pumpPurchasing(
          tester,
          path: purchasingAt(SeedIds.zamalek),
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'orders-zamalek');
      });
      testWidgets('suppliers, $tag', (tester) async {
        final h = await pumpPurchasing(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await h.tap(find.text(h.t('inventory.purchasing.suppliers')).first);
        await shootPage(h, 'suppliers');
      });
      testWidgets('reorder, Zamalek, $tag', (tester) async {
        final h = await pumpPurchasing(
          tester,
          path: purchasingAt(SeedIds.zamalek),
          size: size,
          locale: lang,
          dark: dark,
        );
        await h.tap(find.text(h.t('inventory.purchasing.reorder')).first);
        await shootPage(h, 'reorder-zamalek');
      });
    }
  }
}
