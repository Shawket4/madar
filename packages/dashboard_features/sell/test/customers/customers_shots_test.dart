// The Customers screenshot matrix: the default page at {phone, tablet,
// desktop} x {en light, ar dark} (its top and its end); every other state,
// sheet and dialog at desktop-en-light and phone-ar-light. Written only with
// FDASH_SHOTS set; the screens still render (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/customers/customer_sheet.dart';
import 'package:dashboard_sell/src/customers/customers_page.dart';
import 'package:dashboard_sell/src/mock/customers_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];

/// Scrolls [scrollable] to [fraction] of its extent (0 top, 1 end).
Future<void> _scrollTo(
  DashHarness h,
  Finder scrollable,
  double fraction,
) async {
  final p = h.tester.state<ScrollableState>(scrollable.first).position;
  p.jumpTo(p.maxScrollExtent * fraction);
  await h.settle(rounds: 2);
}

Finder get _pageScroll => find.descendant(
  of: find.byType(CustomersPage),
  matching: find.byType(Scrollable),
);

Finder get _sheetScroll => find.descendant(
  of: find.byType(CustomerSheet),
  matching: find.byType(Scrollable),
);

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('default, $tag', (tester) async {
        final h = await pumpCustomers(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await h.shot('customers/default-1');
        await _scrollTo(h, _pageScroll, 1);
        await h.shot('customers/default-end');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final tag = '${size.name} $lang';

    testWidgets('loading, $tag', (tester) async {
      final s = customersServer();
      final gate = s.server.hold('GET', '/customers');
      final h = await pumpCustomers(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
      );
      await h.shot('customers/loading');
      gate.release();
      s.server.clearFailures();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = customersServer();
      s.server.fail(
        'GET',
        '/customers',
        MockResponse.error(500, 'The database did not answer'),
        times: null,
      );
      final h = await pumpCustomers(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
      );
      await h.shot('customers/failed');
    });

    testWidgets('empty, $tag', (tester) async {
      final s = customersServer();
      s.db['customers'].clear();
      final h = await pumpCustomers(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
      );
      await h.shot('customers/empty');
    });

    testWidgets('no match, members only, $tag', (tester) async {
      final h = await pumpCustomers(tester, size: size, locale: lang);
      await h.tap(pageText(h.t('customers.membersOnly')));
      await h.enterText(inPage(find.byType(DashSearchInput)), 'zzzz');
      await tester.pump(const Duration(milliseconds: 350));
      await h.settle();
      await h.shot('customers/no-match');
    });

    testWidgets('restricted, $tag', (tester) async {
      final s = customersServer();
      grantOnly(s.server, ['orders.read']);
      final h = await pumpCustomers(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
      );
      await h.shot('customers/restricted');
    });

    testWidgets('source filter open, $tag', (tester) async {
      final h = await pumpCustomers(tester, size: size, locale: lang);
      await h.tap(pageText(h.t('customers.source.all')));
      await h.shot('customers/source-filter');
    });

    testWidgets('the sheet, $tag', (tester) async {
      final s = customersServer();
      customerNamed(s.db, 'Nada Kamal')
        ..['birth_month'] = 3
        ..['birth_day'] = 14
        ..['notes'] = 'Prefers oat milk.';
      final h = await pumpCustomers(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        persona: Persona.platform,
      );
      await openNada(h);
      await h.shot('customers/sheet-1');
      await _scrollTo(h, _sheetScroll, 0.3);
      await h.shot('customers/sheet-2');
      await _scrollTo(h, _sheetScroll, 1);
      await h.shot('customers/sheet-end');
    });

    testWidgets('the sheet loading and failed, $tag', (tester) async {
      final h = await pumpCustomers(tester, size: size, locale: lang);
      final gate = h.server.hold('GET', '/customers/{id}');
      await openNada(h);
      await h.shot('customers/sheet-loading');
      h.server.clearFailures();
      h.server.fail(
        'GET',
        '/customers/{id}',
        MockResponse.error(404, 'Customer not found'),
        times: null,
      );
      gate.release();
      await h.settle();
      await h.shot('customers/sheet-failed');
    });

    testWidgets('a non-member\'s sheet with bookings, $tag', (tester) async {
      final s = customersServer();
      final counts = <String, int>{};
      for (final b in s.db['bookings'].rows) {
        final id = b['customer_id'];
        if (id is String) counts[id] = (counts[id] ?? 0) + 1;
      }
      final id = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final h = await pumpCustomers(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
      );
      await openSheet(h, id.key);
      await _scrollTo(h, _sheetScroll, 1);
      await h.shot('customers/sheet-bookings');
    });

    testWidgets('add dialog with errors, $tag', (tester) async {
      final h = await pumpCustomers(tester, size: size, locale: lang);
      await h.tap(pageText(h.t('customers.add')));
      await h.enterText(find.byKey(const ValueKey('customer-phone')), '123');
      await h.tap(
        find
            .byWidgetPredicate(
              (w) => w is DashButton && w.label == h.t('customers.add'),
            )
            .last,
      );
      await h.shot('customers/add-dialog');
    });

    testWidgets('edit dialog, $tag', (tester) async {
      final h = await pumpCustomers(tester, size: size, locale: lang);
      await openNada(h);
      await h.tap(sheetText(h.t('common.edit')));
      await h.shot('customers/edit-dialog');
    });

    testWidgets('erase confirm, $tag', (tester) async {
      final h = await pumpCustomers(tester, size: size, locale: lang);
      await openNada(h);
      await h.tap(sheetText(h.t('customers.erase')));
      await h.shot('customers/erase-confirm');
    });

    testWidgets('merge dialog, picker and the turned-round merge, $tag', (
      tester,
    ) async {
      final s = customersServer();
      final y = nonMember(s.db);
      final h = await pumpCustomers(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
      );
      await openNada(h);
      await h.tap(sheetText(h.t('customers.mergeInto')));
      await h.shot('customers/merge-dialog');
      await h.tap(find.byKey(const ValueKey('merge-pick')));
      await h.shot('customers/merge-picker');
      await h.enterText(
        find.byKey(const ValueKey('merge-search')),
        y['name']! as String,
      );
      await tester.pump(const Duration(milliseconds: 350));
      await h.settle();
      await h.tap(
        find
            .byWidgetPredicate(
              (w) => w is DashPressable && w.semanticLabel == y['name'],
            )
            .last,
      );
      await h.shot('customers/merge-reversed');
    });

    testWidgets('adjust dialog with errors, $tag', (tester) async {
      final h = await pumpCustomers(tester, size: size, locale: lang);
      await openNada(h);
      await h.tap(sheetText(h.t('loyalty.adjustTitle')));
      await h.tap(
        find
            .byWidgetPredicate(
              (w) => w is DashButton && w.label == h.t('loyalty.adjustConfirm'),
            )
            .last,
      );
      await h.shot('customers/adjust-dialog');
    });

    testWidgets('leave the programme, $tag', (tester) async {
      final h = await pumpCustomers(tester, size: size, locale: lang);
      await openNada(h);
      await h.tap(sheetText(h.t('loyalty.leave.action')));
      await h.shot('customers/leave-dialog');
    });

    testWidgets('wallet dialog, $tag', (tester) async {
      final h = await pumpCustomers(
        tester,
        size: size,
        locale: lang,
        persona: Persona.platform,
      );
      await openNada(h);
      await h.tap(sheetText(h.t('loyalty.googleObject')));
      await h.shot('customers/wallet-dialog');
      await h.tap(
        find
            .byWidgetPredicate(
              (w) =>
                  w is DashButton &&
                  w.label == h.t('loyalty.refreshFromGoogle'),
            )
            .last,
      );
      await h.shot('customers/wallet-refreshed');
    });

    testWidgets('a card-only viewer, $tag', (tester) async {
      final s = customersServer();
      grantOnly(s.server, ['loyalty.members.list']);
      final h = await pumpCustomers(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
      );
      await openSheet(h, nadaId);
      await h.shot('customers/sheet-card-only');
      expect(s.db[CustomerTables.ledger].rows, isNotEmpty);
    });
  }
}
