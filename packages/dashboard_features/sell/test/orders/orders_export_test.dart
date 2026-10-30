// The Orders export sheet and its workbook (SELL-ORD-070 … 085, 089;
// SELL-ALL-013, 014, 018).
import 'dart:async';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/orders/export_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'orders_support.dart';

Future<DashHarness> _openExport(
  WidgetTester tester, {
  String? branchId = '',
  MockServer? server,
  MockDb? db,
  DashSize size = DashSize.desktop,
  String locale = 'en',
}) async {
  final h = await pumpOrders(
    tester,
    branchId: branchId,
    server: server,
    db: db,
    size: size,
    locale: locale,
  );
  await h.tap(find.byKey(const ValueKey('orders-export')));
  return h;
}

Finder inExport(Finder f) =>
    find.descendant(of: find.byType(OrdersExportSheet), matching: f);

Finder get _run => find.byKey(const ValueKey('export-run'));

bool _enabled(WidgetTester tester, Finder f) =>
    tester.widget<DashButton>(f).onPressed != null;

void main() {
  testWidgets('SELL-ORD-070/071/072/SELL-ALL-014 the sheet opens on Accountant '
      'daily: title, presets, collapsed sheets', (tester) async {
    final h = await _openExport(tester);
    expect(inExport(find.text('Export Orders')), findsOneWidget);
    expect(inExport(find.text(h.t('ordersExport.subtitle'))), findsOneWidget);
    expect(inExport(find.text('EXPORT PRESETS')), findsOneWidget);
    for (final p in [
      'accountantDaily',
      'talabatReconcile',
      'tillHandoff',
      'ingredientConsumption',
      'custom',
    ]) {
      expect(
        inExport(find.text(h.t('ordersExport.presets.$p.label'))),
        findsOneWidget,
        reason: p,
      );
      expect(
        inExport(find.text(h.t('ordersExport.presets.$p.desc'))),
        findsOneWidget,
        reason: p,
      );
    }
    final selected = find.byWidgetPredicate(
      (w) =>
          w is DashPressable &&
          w.selected == true &&
          w.semanticLabel == 'Daily Accountant Export',
    );
    expect(selected, findsOneWidget);
    expect(find.byKey(const ValueKey('export-grains')), findsNothing);
    await h.shot('orders/export-sheet');
  });

  testWidgets('SELL-ORD-073 Customize: sheets locked unless Custom', (
    tester,
  ) async {
    final h = await _openExport(tester);
    await h.tap(find.byKey(const ValueKey('export-customize')));
    expect(find.byKey(const ValueKey('export-grains')), findsOneWidget);
    for (final g in ['order', 'line_item', 'payment', 'deduction']) {
      expect(
        inExport(find.text(h.t('ordersExport.grains.$g'))),
        findsOneWidget,
        reason: g,
      );
    }
    expect(
      inExport(find.text(h.t('ordersExport.lockedGrainsHint'))),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DashCheckboxField>(find.byKey(const ValueKey('grain-order')))
          .enabled,
      isFalse,
    );
    // Till handoff picks Orders + Payments.
    await h.tap(find.byKey(const ValueKey('preset-till_handoff')));
    expect(
      tester
          .widget<DashCheckboxField>(
            find.byKey(const ValueKey('grain-payment')),
          )
          .value,
      isTrue,
    );
    await h.tap(find.byKey(const ValueKey('preset-custom')));
    expect(
      inExport(find.text(h.t('ordersExport.lockedGrainsHint'))),
      findsNothing,
    );
    final lines = find.byKey(const ValueKey('grain-line_item'));
    expect(tester.widget<DashCheckboxField>(lines).enabled, isTrue);
    await h.tap(lines);
    expect(tester.widget<DashCheckboxField>(lines).value, isTrue);
    await h.tap(find.byKey(const ValueKey('export-customize')));
    expect(find.byKey(const ValueKey('export-grains')), findsNothing);
  });

  testWidgets(
    'SELL-ORD-074/075/076/089 the snapshot, the file name, the estimate',
    (tester) async {
      final h = await _openExport(tester);
      final scope = h.container.read(currentScopeProvider);
      expect(
        h.server.callsTo('/branches/{id}').last.path,
        '/branches/${SeedIds.heliopolis}',
      );
      expect(inExport(find.text('FILTERS SNAPSHOT')), findsOneWidget);
      expect(inExport(find.text('Heliopolis')), findsOneWidget);
      final range =
          '${scope.from.substring(0, 10)} → ${scope.to.substring(0, 10)}';
      expect(inExport(find.text(ltr(range))), findsOneWidget);
      expect(inExport(find.text('All payments')), findsOneWidget);
      // Accountant daily forces Completed.
      expect(inExport(find.text('Completed')), findsOneWidget);
      final name =
          'accountant-daily-heliopolis-${scope.from.substring(0, 10)}_to_${scope.to.substring(0, 10)}';
      final field = find.byKey(const ValueKey('export-filename'));
      expect(
        find.descendant(of: field, matching: find.text(name)),
        findsOneWidget,
      );
      expect(
        inExport(find.text(h.t('ordersExport.filenameHint'))),
        findsOneWidget,
      );
      final total = todaysOrders(h.db!, SeedIds.heliopolis).length;
      expect(inExport(find.text('Estimated rows: $total')), findsOneWidget);
      // Talabat reconcile: no payments.* key for the pair, so the raw text; the
      // estimate stays the list's.
      await h.tap(find.byKey(const ValueKey('preset-talabat_reconcile')));
      expect(
        inExport(find.text('talabat_online,talabat_cash')),
        findsOneWidget,
      );
      expect(inExport(find.text('All statuses')), findsOneWidget);
      expect(inExport(find.text('Estimated rows: $total')), findsOneWidget);
      expect(
        find.descendant(
          of: field,
          matching: find.textContaining('talabat-reconcile-heliopolis-'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('SELL-ORD-071 every open starts again', (tester) async {
    final h = await _openExport(tester);
    await h.tap(find.byKey(const ValueKey('preset-custom')));
    await h.enterText(find.byKey(const ValueKey('export-filename')), 'my-file');
    await h.tap(find.byKey(const ValueKey('export-customize')));
    await h.tap(inExport(find.text('Cancel')));
    expect(find.byType(OrdersExportSheet), findsNothing);
    await h.tap(find.byKey(const ValueKey('orders-export')));
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is DashPressable &&
            w.selected == true &&
            w.semanticLabel == 'Daily Accountant Export',
      ),
      findsOneWidget,
    );
    expect(inExport(find.text('my-file')), findsNothing);
    expect(find.byKey(const ValueKey('export-grains')), findsNothing);
  });

  testWidgets('SELL-ORD-077/078 Export Workbook is off with no sheet', (
    tester,
  ) async {
    final h = await _openExport(tester);
    expect(_enabled(tester, _run), isTrue);
    await h.tap(find.byKey(const ValueKey('preset-custom')));
    await h.tap(find.byKey(const ValueKey('export-customize')));
    await h.tap(find.byKey(const ValueKey('grain-order')));
    expect(_enabled(tester, _run), isFalse);
  });

  testWidgets(
    'SELL-ORD-077/081 All branches: the sheet opens, its Export does not',
    (tester) async {
      final all = await _openExport(tester, branchId: null);
      expect(find.byType(OrdersExportSheet), findsOneWidget);
      expect(
        inExport(find.text('—')),
        findsOneWidget,
        reason: 'no branch name',
      );
      expect(_enabled(tester, _run), isFalse);
      expect(all.server.callsTo('/branches/{id}'), isEmpty);
    },
  );

  testWidgets('SELL-ORD-079/080/082/SELL-ALL-013 Accountant daily: one read with '
      'the filters, the workbook, the sheet closes', (tester) async {
    final h = await _openExport(tester);
    final scope = h.container.read(currentScopeProvider);
    final fmt = h.container.read(formatProvider);
    await h.tap(_run);
    final call = h.server.callsTo(exportRoute).single;
    expect(call.headers['X-Madar-Export'], '1');
    expect(call.query['branch_id'], [SeedIds.heliopolis]);
    expect(call.query['status'], ['completed']);
    expect(call.query['from'], [scope.from]);
    expect(call.query['to'], [scope.to]);
    await h.expectToast(
      h.t(
        'excel.done',
        count: todaysOrders(
          h.db!,
          SeedIds.heliopolis,
        ).where((o) => o['status'] == 'completed').length,
      ),
    );
    expect(find.byType(OrdersExportSheet), findsNothing);
    final saved = h.files.saved.single;
    final stamp = h.db!.clock.now.toIso8601String().substring(0, 10);
    expect(
      saved.filename,
      'accountant-daily-heliopolis-${scope.from.substring(0, 10)}_to_${scope.to.substring(0, 10)}-$stamp.xlsx',
    );
    final book = h.exports.built.single;
    expect(book.sheets.map((s) => s.name), ['Orders']);
    final sheet = book.sheets.single;
    expect(sheet.title, 'Orders');
    expect(
      sheet.subtitle,
      startsWith(
        'Branch: Heliopolis · ${fmt.fmtDate(scope.from)} → ${fmt.fmtDate(scope.to)} · Completed',
      ),
    );
    expect(sheet.subtitle, contains('Generated: '));
    expect(sheet.columns.map((c) => c.header), [
      'Ref',
      'Date',
      'Teller',
      'Waiter',
      'Customer',
      'Payment Method',
      'Staff drinks given free',
      'Subtotal',
      'Discount',
      'Tax',
      'Tip',
      'Delivery fee',
      'Total',
      'Type',
      'Location',
      'Status',
      'Reason',
    ]);
    expect(sheet.totalsRow, isNotNull);
    final rows = sheet.rows;
    expect(rows.every((r) => r[15] == 'Completed'), isTrue);
    // The staff drink: given free 160.00, subtotal 25.00 (money in pounds).
    final staffRef = h.db!['orders'].find(
      OrderSeedIds.showcase('staff'),
    )!['order_ref'];
    final staff = rows.firstWhere((r) => r[0] == staffRef);
    expect(staff[6], 160);
    expect(staff[7], 25);
    // The outside delivery: a Maps link and the Delivery type.
    final out = rows.firstWhere((r) => r[14] != '—');
    expect(out[13], 'Delivery');
    expect(
      out[14],
      startsWith('https://www.google.com/maps/search/?api=1&query='),
    );
  });

  testWidgets('SELL-ORD-080/083/084/085 Custom with every sheet: the order of '
      'the sheets and their columns', (tester) async {
    final h = await _openExport(tester, branchId: SeedIds.zamalek);
    await h.tap(find.byKey(const ValueKey('preset-custom')));
    await h.tap(find.byKey(const ValueKey('export-customize')));
    for (final g in ['line_item', 'payment', 'deduction']) {
      await h.tap(find.byKey(ValueKey('grain-$g')));
    }
    await h.enterText(
      find.byKey(const ValueKey('export-filename')),
      'zamalek-morning',
    );
    await h.tap(_run);
    await h.flushTimers();
    expect(h.files.saved.single.filename, startsWith('zamalek-morning-'));
    final book = h.exports.built.single;
    expect(book.sheets.map((s) => s.name), [
      'Orders',
      'Line Items',
      'Payments',
      'Ingredient Usage',
      'Ingredient Usage (Totals)',
    ]);
    expect(book.sheets.every((s) => s.totalsRow != null), isTrue);
    expect(book.sheets[1].columns.map((c) => c.header), [
      'Ref',
      'Date',
      'Payment Method',
      'Waiter',
      'Item',
      'Size',
      'Qty',
      'Price',
      'Total',
      'Staff drinks given free',
      'Staff drink charged (with extras)',
      'COGS',
      'Addons',
      'Optionals',
      'Notes',
    ]);
    expect(book.sheets[2].columns.map((c) => c.header), [
      'Ref',
      'Date',
      'Total',
      'Payment Method',
      'Amount',
      'Reference',
    ]);
    expect(book.sheets[3].columns.map((c) => c.header), [
      'Ref',
      'Date',
      'Item',
      'Ingredient',
      'Qty',
      'Unit',
      'Source',
      'Category',
    ]);
    expect(book.sheets[4].columns.map((c) => c.header), [
      'Ingredient',
      'Total Quantity',
      'Unit',
      'Occurrences',
    ]);
    // The split sale: one payment row per leg, its order's total on each.
    final splitRef = h.db!['orders'].find(
      OrderSeedIds.showcase('split'),
    )!['order_ref'];
    final legs = book.sheets[2].rows.where((r) => r[0] == splitRef).toList();
    expect(legs.map((r) => r[3]), ['Cash', 'Card']);
    expect(legs.first[2], legs.last[2]);
    // The Orders sheet names both legs.
    final order = book.sheets[0].rows.firstWhere((r) => r[0] == splitRef);
    expect(order[5], contains(' + '));
    // The totals sheet runs biggest first.
    final qty = [for (final r in book.sheets[4].rows) r[1]! as num];
    expect(qty, [...qty]..sort((a, b) => b.compareTo(a)));
  });

  testWidgets('teller pick: the Orders sheet\'s Teller column names who '
      'sold (the picked person), else the signed-in person', (tester) async {
    final s = ordersServer();
    final completed = todaysOrders(
      s.db,
      SeedIds.heliopolis,
    ).where((o) => o['status'] == 'completed').toList();
    final picked = completed[0];
    final plain = completed[1];
    picked
      ..['sold_by'] = SeedIds.user('mona')
      ..['sold_by_name'] = 'Mona Adel';
    final h = await _openExport(tester, server: s.server, db: s.db);
    await h.tap(_run);
    await h.flushTimers();
    final sheet = h.exports.built.single.sheets.single;
    expect(sheet.columns[2].header, 'Teller');
    List<Object?> rowOf(Map<String, Object?> o) =>
        sheet.rows.firstWhere((r) => r[0] == o['order_ref']);
    expect(rowOf(picked)[2], 'Mona Adel');
    expect(rowOf(plain)[2], plain['teller_name']);
  });

  testWidgets('SELL-ORD-079 nothing matched: the toast, the sheet stays', (
    tester,
  ) async {
    final s = ordersServer();
    s.db['orders'].removeWhere((o) => o['branch_id'] == SeedIds.maadi);
    final h = await _openExport(
      tester,
      branchId: SeedIds.maadi,
      server: s.server,
      db: s.db,
    );
    await h.tap(_run);
    await h.expectToast(h.t('ordersExport.noOrders'));
    expect(find.byType(OrdersExportSheet), findsOneWidget);
    expect(h.files.saved, isEmpty);
  });

  testWidgets(
    'SELL-ORD-079/SELL-ALL-018 a refused export toasts its words; the '
    'sheet stays and stops spinning',
    (tester) async {
      final s = ordersServer();
      final response = MockResponse.error(
        429,
        'Too many exports; try again in a minute',
        code: 'EXPORT_RATE_LIMITED',
      );
      // Ten exports this minute already.
      for (var i = 0; i < 10; i++) {
        s.db['export_hits'].insert({
          'user': Persona.owner.userId,
          'at': s.db.clock.now.toIso8601String(),
        }, timestamps: false);
      }
      final h = await _openExport(tester, server: s.server, db: s.db);
      await h.tap(_run);
      expect(h.server.callsTo(exportRoute).single.status, 429);
      await h.expectToast(h.refusalWords(response));
      expect(find.byType(OrdersExportSheet), findsOneWidget);
      expect(tester.widget<DashButton>(_run).loading, isFalse);
    },
  );

  testWidgets(
    'SELL-ORD-070 while exporting: Close and Cancel off, Escape ignored',
    (tester) async {
      final h = await _openExport(tester);
      final hold = Completer<void>();
      h.exports.hold = hold.future;
      await h.tap(_run);
      expect(tester.widget<DashButton>(_run).loading, isTrue);
      expect(
        tester
            .widget<DashIconButton>(
              find
                  .descendant(
                    of: find.byType(OrdersExportSheet),
                    matching: find.byType(DashIconButton),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
      expect(
        _enabled(tester, inExport(find.widgetWithText(DashButton, 'Cancel'))),
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(find.byType(OrdersExportSheet), findsOneWidget);
      hold.complete();
      h.exports.hold = null;
      await h.settle();
      await h.flushTimers();
      expect(find.byType(OrdersExportSheet), findsNothing);
    },
  );
}
