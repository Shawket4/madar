// The Customers page and its list (SELL-CUS-001 … 021, 056, 057).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/customers/customer_sheet.dart';
import 'package:dashboard_sell/src/customers/google_object_dialog.dart';
import 'package:dashboard_sell/src/customers/people_widgets.dart';
import 'package:dashboard_sell/src/mock/customers_mock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('nav and gate', () {
    testWidgets('SELL-CUS-001 the Customers leaf follows customers.view', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      final sidebar = find.byType(DashSidebar);
      expect(
        find.descendant(of: sidebar, matching: find.text('Customers')),
        findsOneWidget,
      );
      expect(h.location.path, customersPath);
    });

    testWidgets(
      'SELL-CUS-001 hidden for someone who only lists loyalty members',
      (tester) async {
        final s = customersServer();
        grantOnly(s.server, ['orders.read', 'loyalty.members.list']);
        await pumpCustomers(tester, server: s.server, db: s.db, path: '/');
        final sidebar = find.byType(DashSidebar);
        expect(
          find.descendant(of: sidebar, matching: find.text('Orders')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sidebar, matching: find.text('Customers')),
          findsNothing,
        );
      },
    );

    testWidgets('SELL-CUS-002 Restricted page without customers.view, no '
        'reads', (tester) async {
      final s = customersServer();
      grantOnly(s.server, ['orders.read', 'loyalty.members.list']);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      final r = find.byType(Restricted);
      expect(r, findsOneWidget);
      expect(
        find.descendant(of: r, matching: find.text('Customers')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: r,
          matching: find.text(h.t('common.restrictedTitle')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: r,
          matching: find.text(
            'Only people who can see customers can open this page.',
          ),
        ),
        findsOneWidget,
      );
      expect(listCalls(h), isEmpty);
      expect(h.server.callsTo('/loyalty/settings'), isEmpty);
    });

    testWidgets('SELL-CUS-057 before permissions load: header only, no Add, '
        'no read', (tester) async {
      final s = customersServer();
      final gate = s.server.hold('GET', '/authz/me');
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      expect(pageText('Customers'), findsOneWidget);
      expect(pageText('Add customer'), findsNothing);
      expect(inPage(find.byType(DashSkeleton)), findsNothing);
      expect(listCalls(h), isEmpty);
      expect(find.byType(Restricted), findsNothing);
      gate.release();
      await h.settle();
      expect(pageText('Add customer'), findsOneWidget);
      expect(listCalls(h), hasLength(1));
    });
  });

  group('header', () {
    testWidgets('SELL-CUS-003 title, description, Add with customers.create', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      expect(pageText('Customers'), findsOneWidget);
      expect(pageText(h.t('customers.subtitle')), findsOneWidget);
      expect(pageText('Add customer'), findsOneWidget);
    });

    testWidgets('SELL-CUS-003 no Add without customers.create (limited)', (
      tester,
    ) async {
      await pumpCustomers(tester, persona: Persona.limited);
      expect(pageText('Customers'), findsOneWidget);
      expect(pageText('Add customer'), findsNothing);
      expect(rowOf('Nada Kamal'), findsOneWidget);
    });
  });

  group('reads, search and filters', () {
    testWidgets('SELL-CUS-007 the first read: limit 50, offset 0, nothing '
        'else', (tester) async {
      final h = await pumpCustomers(tester);
      expect(listCalls(h), hasLength(1));
      expect(q1(listCalls(h).single), {'limit': '50', 'offset': '0'});
      // The rows came back newest visit first; Nada leads.
      expect(rowOf('Nada Kamal'), findsOneWidget);
    });

    testWidgets('SELL-CUS-004 search: debounced, trimmed, server-side', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await h.enterText(inPage(find.byType(DashSearchInput)), '  0100 123  ');
      // Nothing yet: the box waits for typing to settle.
      expect(listCalls(h), hasLength(1));
      await tester.pump(const Duration(milliseconds: 350));
      await h.settle();
      expect(q1(listCalls(h).last), {
        'q': '0100 123',
        'limit': '50',
        'offset': '0',
      });
      expect(rowOf('Nada Kamal'), findsOneWidget);
      expect(inPage(find.byType(DashPressable)).evaluate().length, lessThan(8));
    });

    testWidgets('SELL-CUS-004 a new search restarts the load-more window', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await h.scrollUntilVisible(pageText('Load more'));
      await h.tap(pageText('Load more'));
      expect(q1(listCalls(h).last)['limit'], '100');
      await h.enterText(inPage(find.byType(DashSearchInput)), 'a');
      await tester.pump(const Duration(milliseconds: 350));
      await h.settle();
      expect(q1(listCalls(h).last), {'q': 'a', 'limit': '50', 'offset': '0'});
    });

    testWidgets('SELL-CUS-005 "Came from" filters by source', (tester) async {
      final h = await pumpCustomers(tester);
      await h.tap(pageText('Any source'));
      for (final s in [
        'Any source',
        'Till',
        'Online order',
        'Loyalty sign-up',
        'Booking',
        'Table QR',
        'Delivery app',
        'Dashboard',
      ]) {
        expect(find.text(s), findsWidgets, reason: s);
      }
      await h.tap(optionText('Booking'));
      expect(q1(listCalls(h).last), {
        'source': 'booking',
        'limit': '50',
        'offset': '0',
      });
      final booking = s1(h.db!, 'booking');
      expect(rowOf(booking), findsOneWidget);
    });

    testWidgets('SELL-CUS-006 "Members only" asks the server for members', (
      tester,
    ) async {
      final s = customersServer();
      final other = nonMember(s.db)['name']! as String;
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      expect(rowOf(other), findsOneWidget);
      await h.tap(pageText('Members only'));
      expect(q1(listCalls(h).last), {
        'member': 'true',
        'limit': '50',
        'offset': '0',
      });
      expect(rowOf(other), findsNothing);
      expect(rowOf('Nada Kamal'), findsOneWidget);
    });

    testWidgets('SELL-CUS-008 the programme is read only with loyalty.read', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      expect(h.server.callsTo('/loyalty/settings'), hasLength(1));
      expect(h.server.callsTo('/loyalty/settings').single.query, isEmpty);
    });

    testWidgets('SELL-CUS-008 no programme read without loyalty.read', (
      tester,
    ) async {
      final h = await pumpCustomers(tester, persona: Persona.limited);
      expect(h.server.callsTo('/loyalty/settings'), isEmpty);
    });
  });

  group('columns', () {
    testWidgets('SELL-CUS-009 Name with the Member pill for members', (
      tester,
    ) async {
      final s = customersServer();
      final other = nonMember(s.db)['name']! as String;
      await pumpCustomers(tester, server: s.server, db: s.db);
      expect(pageText('NAME'), findsOneWidget);
      expect(
        find.descendant(of: rowOf('Nada Kamal'), matching: find.text('Member')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rowOf(other), matching: find.text('Member')),
        findsNothing,
      );
    });

    testWidgets('SELL-CUS-010 Phone formatted, LTR, or a dash', (tester) async {
      final s = customersServer();
      final other = nonMember(s.db);
      other['phone'] = null;
      await pumpCustomers(tester, server: s.server, db: s.db);
      final phone = find.descendant(
        of: rowOf('Nada Kamal'),
        matching: find.text('+20 100 123 4567'),
      );
      expect(phone, findsOneWidget);
      expect(tester.widget<Text>(phone).textDirection, TextDirection.ltr);
      expect(
        find.descendant(
          of: rowOf(other['name']! as String),
          matching: find.text('—'),
        ),
        findsWidgets,
      );
    });

    testWidgets('SELL-CUS-011 Balance in the programme\'s unit', (
      tester,
    ) async {
      final s = customersServer();
      final one = firstShown(
        s.db,
        (c) => c['is_member'] == true && c['visits_balance'] == 1,
      );
      await pumpCustomers(tester, server: s.server, db: s.db);
      expect(pageText('BALANCE'), findsOneWidget);
      expect(
        find.descendant(of: rowOf('Nada Kamal'), matching: textHas('6 orders')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rowOf(one['name']! as String),
          matching: textHas('1 order'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SELL-CUS-011 no Balance column without loyalty.read', (
      tester,
    ) async {
      await pumpCustomers(tester, persona: Persona.limited);
      expect(pageText('BALANCE'), findsNothing);
      expect(pageText('NAME'), findsOneWidget);
    });

    testWidgets('SELL-CUS-011 no Balance column when the programme is off', (
      tester,
    ) async {
      final s = customersServer();
      for (final r in s.db[CustomerTables.loyaltySettings].rows) {
        r['enabled'] = false;
      }
      await pumpCustomers(tester, server: s.server, db: s.db);
      expect(pageText('BALANCE'), findsNothing);
    });

    testWidgets('SELL-CUS-012 Came from, Orders, Total spent, Last visit', (
      tester,
    ) async {
      final s = customersServer();
      final nada = customerNamed(s.db, 'Nada Kamal');
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      for (final head in ['CAME FROM', 'ORDERS', 'TOTAL SPENT', 'LAST VISIT']) {
        expect(pageText(head), findsOneWidget, reason: head);
      }
      final fmt = h.container.read(formatProvider);
      final row = rowOf('Nada Kamal');
      expect(
        find.descendant(of: row, matching: find.text('Loyalty sign-up')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: textHas(fmt.fmtNumber(nada['orders_count']! as int)),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: row,
          matching: textHas(fmt.fmtMoney(nada['total_spent']! as int)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: textHas(
            fmt.fmtDate(DateTime.parse(nada['last_order_at']! as String)),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SELL-CUS-012 a customer never seen shows a dash for Last '
        'visit', (tester) async {
      final s = customersServer();
      final c = nonMember(s.db);
      // Still first in line: met just now, never ordered.
      c['created_at'] = s.db.clock.now.toUtc().toIso8601String();
      c['last_order_at'] = null;
      c['source'] = 'mystery';
      await pumpCustomers(tester, server: s.server, db: s.db);
      final dashes = find.descendant(
        of: rowOf(c['name']! as String),
        matching: find.byType(MutedDash),
      );
      // Muted, each: Balance (non-member), Came from (unknown), Last visit.
      expect(dashes, findsNWidgets(3));
    });
  });

  group('rows, sheet, load more', () {
    testWidgets('SELL-CUS-013 a row opens its sheet and is selected', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      expect(find.byType(CustomerSheet), findsOneWidget);
      expect(
        h.server.callsTo('/customers/{id}').last.path,
        '/customers/$nadaId',
      );
      expect(rowSelected(tester, 'Nada Kamal'), isTrue);
    });

    testWidgets('SELL-CUS-056 closing the sheet clears the selection', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      await h.tap(inSheet(find.bySemanticsLabel('Close')));
      expect(find.byType(CustomerSheet), findsNothing);
      expect(rowSelected(tester, 'Nada Kamal'), isFalse);
      // Escape closes it the same way.
      await openNada(h);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(find.byType(CustomerSheet), findsNothing);
      expect(rowSelected(tester, 'Nada Kamal'), isFalse);
    });

    testWidgets('SELL-CUS-014 Load more widens the window by 50', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await h.scrollUntilVisible(pageText('Load more'));
      await h.tap(pageText('Load more'));
      expect(q1(listCalls(h).last), {'limit': '100', 'offset': '0'});
    });

    testWidgets('SELL-CUS-014 no Load more once the window came back short', (
      tester,
    ) async {
      final s = customersServer();
      final keep = {for (final c in s.db['customers'].rows.take(30)) c['id']};
      s.db['customers'].removeWhere((c) => !keep.contains(c['id']));
      await pumpCustomers(tester, server: s.server, db: s.db);
      expect(pageText('Load more'), findsNothing);
    });

    testWidgets('SELL-CUS-014 the rows stay while the wider window loads; '
        'Load more spins on a refetch', (tester) async {
      final h = await pumpCustomers(tester);
      await h.scrollUntilVisible(pageText('Load more'));
      final gate = h.server.hold('GET', '/customers');
      await h.tap(pageText('Load more'));
      // The rows already shown stay (`keepPreviousData`); the window came
      // back full of the old 50 against a limit of 100, so no button yet.
      expect(rowOf('Nada Kamal'), findsOneWidget);
      expect(pageButton('Load more'), findsNothing);
      gate.release();
      h.server.clearFailures();
      await h.settle();
      expect(pageButton('Load more'), findsOneWidget);
      // A refetch of the same window spins the button.
      final again = h.server.hold('GET', '/customers');
      h.container.read(realtimeBusProvider).invalidate(const ['/customers']);
      await h.settle();
      expect(
        tester.widget<DashButton>(pageButton('Load more')).loading,
        isTrue,
      );
      again.release();
      h.server.clearFailures();
      await h.settle();
      expect(
        tester.widget<DashButton>(pageButton('Load more')).loading,
        isFalse,
      );
    });

    testWidgets('SELL-CUS-015 platform: a wallet button on member rows', (
      tester,
    ) async {
      final s = customersServer(persona: Persona.platform);
      final other = nonMember(s.db)['name']! as String;
      final h = await pumpCustomers(
        tester,
        persona: Persona.platform,
        server: s.server,
        db: s.db,
      );
      final wallet = find.descendant(
        of: rowOf('Nada Kamal'),
        matching: walletButton,
      );
      expect(wallet, findsOneWidget);
      expect(
        find.descendant(of: rowOf(other), matching: walletButton),
        findsNothing,
      );
      await h.tap(wallet);
      expect(find.byType(GoogleObjectDialog), findsOneWidget);
      expect(
        h.server.callsTo('/loyalty/members/{id}/google-object').single.path,
        '/loyalty/members/$nadaId/google-object',
      );
      // The wallet button never opens the row.
      expect(find.byType(CustomerSheet), findsNothing);
    });

    testWidgets('SELL-CUS-015 no wallet button for an owner', (tester) async {
      await pumpCustomers(tester);
      expect(inPage(walletButton), findsNothing);
    });
  });

  group('states', () {
    testWidgets('SELL-CUS-016 loading skeleton', (tester) async {
      final s = customersServer();
      final gate = s.server.hold('GET', '/customers');
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      expect(inPage(find.byType(DashSkeleton)), findsWidgets);
      expect(rowOf('Nada Kamal'), findsNothing);
      gate.release();
      s.server.clearFailures();
      await h.settle();
      expect(rowOf('Nada Kamal'), findsOneWidget);
    });

    testWidgets('SELL-CUS-016 error with the server\'s words, Retry reads '
        'again', (tester) async {
      final s = customersServer();
      final boom = MockResponse.error(500, 'The database did not answer');
      s.server.fail('GET', '/customers', boom, times: null);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      expect(pageText("Couldn't load this"), findsOneWidget);
      expect(pageText(h.refusalWords(boom)), findsOneWidget);
      expect(pageText('No customers yet'), findsNothing);
      s.server.clearFailures();
      final before = listCalls(h).length;
      // While the retry runs the failure stays up: no empty state, no flash.
      final gate = s.server.hold('GET', '/customers');
      await h.tap(pageText('Retry'));
      expect(listCalls(h).length, before + 1);
      expect(pageText("Couldn't load this"), findsOneWidget);
      expect(pageText('No customers yet'), findsNothing);
      gate.release();
      s.server.clearFailures();
      await h.settle();
      expect(rowOf('Nada Kamal'), findsOneWidget);
    });

    testWidgets('SELL-CUS-016 a refusal reads "no permission"', (tester) async {
      final s = customersServer();
      s.server.fail(
        'GET',
        '/customers',
        MockResponse.denied('customers.view'),
        times: null,
      );
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      expect(pageText(h.t('errors.unauthorized')), findsOneWidget);
    });

    testWidgets('SELL-CUS-017 empty, nothing filtered', (tester) async {
      final s = customersServer();
      s.db['customers'].clear();
      await pumpCustomers(tester, server: s.server, db: s.db);
      expect(pageText('No customers yet'), findsOneWidget);
      expect(
        pageText('Customers added at the till or here appear in this list.'),
        findsOneWidget,
      );
      // Nothing to export.
      final export = pageButton('Export Excel');
      expect(tester.widget<DashButton>(export).onPressed, isNull);
    });

    testWidgets('SELL-CUS-018 empty under a search or filter', (tester) async {
      final h = await pumpCustomers(tester);
      await h.enterText(inPage(find.byType(DashSearchInput)), 'zzzz');
      await tester.pump(const Duration(milliseconds: 350));
      await h.settle();
      expect(pageText('No customers match'), findsOneWidget);
      expect(
        pageText('Try another name or phone number, or clear the filters.'),
        findsOneWidget,
      );
    });
  });

  group('export', () {
    testWidgets('SELL-CUS-019 walks every page from the top with the export '
        'header and the same filters', (tester) async {
      final h = await pumpCustomers(tester);
      await h.tap(pageText('Members only'));
      await h.tap(pageText('Export Excel'));
      await h.flushTimers();
      final walk = [
        for (final c in listCalls(h))
          if (c.headers['X-Madar-Export'] == '1') c,
      ];
      // 200 customers, about 60 % members: one full page, then the empty
      // page that ends the walk.
      expect(walk, hasLength(2));
      // Only the walk spends the export budget: the logo comes from the
      // brand the shell already holds.
      expect(
        {
          for (final c in h.server.calls)
            if (c.headers['X-Madar-Export'] == '1') c.template,
        },
        {'/customers'},
      );
      expect(q1(walk[0]), {'member': 'true', 'limit': '500', 'offset': '0'});
      final first = walk[0].status;
      expect(first, 200);
      final members = h.db!['customers'].rows
          .where((c) => c['is_member'] == true)
          .length;
      expect(q1(walk[1])['offset'], '$members');
      expect(h.files.saved.single.filename, startsWith('Madar-Customers-'));
      expect(h.files.saved.single.filename, endsWith('.xlsx'));
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.name, 'Customers');
      expect(sheet.rows, hasLength(members));
    });

    testWidgets('SELL-CUS-019 the search text is the subtitle', (tester) async {
      final h = await pumpCustomers(tester);
      await h.enterText(inPage(find.byType(DashSearchInput)), 'Nada');
      await tester.pump(const Duration(milliseconds: 350));
      await h.settle();
      await h.tap(pageText('Export Excel'));
      await h.flushTimers();
      expect(h.exports.built.single.sheets.single.subtitle, startsWith('Nada'));
    });

    testWidgets('SELL-CUS-019 spinner while it runs', (tester) async {
      final h = await pumpCustomers(tester);
      final gate = h.server.hold('GET', '/customers');
      await h.tap(pageText('Export Excel'));
      final export = pageButton('Export Excel');
      expect(tester.widget<DashButton>(export).loading, isTrue);
      gate.release();
      h.server.clearFailures();
      await h.settle();
      await h.flushTimers();
      expect(tester.widget<DashButton>(export).loading, isFalse);
    });

    testWidgets('SELL-CUS-019 refuses past 50,000 rows', (tester) async {
      final s = customersServer();
      final page = [
        for (final c in s.db['customers'].rows.take(1)) {...c},
      ];
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      // A huge list: every export page comes back full.
      s.server.on('GET', '/customers', (req) {
        final limit = req.qInt('limit') ?? 50;
        return MockResponse.ok([
          for (var i = 0; i < limit; i++) {...page.first, 'id': 'c$i'},
        ]);
      });
      await h.tap(pageText('Export Excel'));
      await h.expectToast(
        h.t('export.tooLarge', args: {'rows': '50,500', 'max': '50,000'}),
      );
      expect(h.files.saved, isEmpty);
    });

    testWidgets('SELL-CUS-019 / SELL-ALL-018 the export throttle toasts its '
        'words', (tester) async {
      final h = await pumpCustomers(tester);
      h.server.fail(
        'GET',
        '/customers',
        MockResponse.error(
          429,
          'Too many exports',
          code: 'EXPORT_RATE_LIMITED',
        ),
      );
      await h.tap(pageText('Export Excel'));
      await h.expectToast('Too many exports just now. Try again in a minute.');
      expect(h.files.saved, isEmpty);
      final export = pageButton('Export Excel');
      expect(tester.widget<DashButton>(export).loading, isFalse);
    });

    testWidgets('SELL-CUS-020 columns with the balance and its unit', (
      tester,
    ) async {
      final s = customersServer();
      final name = nonMember(s.db)['name'];
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await h.tap(pageText('Export Excel'));
      await h.flushTimers();
      final sheet = h.exports.built.single.sheets.single;
      expect(
        [for (final c in sheet.columns) c.header],
        [
          'Name',
          'Phone',
          'Member',
          'Balance',
          'Unit',
          'Came from',
          'Orders',
          'Total spent',
          'Last visit',
        ],
      );
      final nada = sheet.rows.firstWhere((r) => r[0] == 'Nada Kamal');
      expect(nada[1], '+20 100 123 4567');
      expect(nada[2], 'Yes');
      expect(nada[3], 6);
      expect(nada[4], 'orders');
      expect(nada[5], 'Loyalty sign-up');
      final other = sheet.rows.firstWhere((r) => r[0] == name);
      expect(other[2], 'No');
      expect(other[3], isNull);
      expect(other[4], '');
    });

    testWidgets('SELL-CUS-020 no balance columns without the programme', (
      tester,
    ) async {
      final h = await pumpCustomers(tester, persona: Persona.limited);
      await h.tap(pageText('Export Excel'));
      await h.flushTimers();
      final sheet = h.exports.built.single.sheets.single;
      expect(
        [for (final c in sheet.columns) c.header],
        [
          'Name',
          'Phone',
          'Member',
          'Came from',
          'Orders',
          'Total spent',
          'Last visit',
        ],
      );
    });
  });

  group('phone', () {
    testWidgets('SELL-CUS-021 cards: name + pill, pairs, no Came from', (
      tester,
    ) async {
      final h = await pumpCustomers(tester, size: DashSize.phone);
      final card = rowOf('Nada Kamal');
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Member')),
        findsOneWidget,
      );
      for (final label in [
        'Phone',
        'Balance',
        'Orders',
        'Total spent',
        'Last visit',
      ]) {
        expect(
          find.descendant(of: card, matching: find.text(label)),
          findsOneWidget,
          reason: label,
        );
      }
      expect(
        find.descendant(of: card, matching: find.text('Came from')),
        findsNothing,
      );
      // The filter row: search, source, Members only, Export; below 640 the
      // source select takes the whole line, like the search.
      expect(inPage(find.byType(DashSearchInput)), findsOneWidget);
      final source = inPage(
        find.byWidgetPredicate(
          (w) => w is DashSelectTrigger && w.label == 'Any source',
        ),
      );
      expect(
        tester.getSize(source).width,
        tester.getSize(inPage(find.byType(DashSearchInput))).width,
      );
      expect(pageText('Any source'), findsOneWidget);
      expect(pageText('Members only'), findsOneWidget);
      expect(pageText('Export Excel'), findsOneWidget);
      await h.tap(card);
      expect(find.byType(CustomerSheet), findsOneWidget);
    });
  });
}

/// The row's wallet inspector (platform only).
final Finder walletButton = find.byWidgetPredicate(
  (w) => w is DashIconButton && w.semanticLabel == 'Google Wallet object',
);

/// The first seed customer that came from [source].
String s1(MockDb db, String source) =>
    db['customers'].rows.firstWhere((c) => c['source'] == source)['name']!
        as String;
