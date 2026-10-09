// The customer sheet (SELL-CUS-026 … 031, 040 … 043, 049 … 055, 058;
// SELL-ALL-016).
import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/area_seed.dart';
import 'package:dashboard_sell/src/customers/customer_sheet.dart';
import 'package:dashboard_sell/src/mock/customers_mock.dart';
import 'package:dashboard_sell/src/orders/order_sheet.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The customer with the most bookings, and how many.
(String, int) _booker(MockDb db) {
  final counts = <String, int>{};
  for (final b in db[SellTables.bookings].rows) {
    final id = b['customer_id'];
    if (id is String) counts[id] = (counts[id] ?? 0) + 1;
  }
  final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  return (best.key, best.value);
}

/// A member whose ledger holds a voided sale (an earn and its reversal).
String _memberWithVoid(MockDb db) =>
    db[CustomerTables.ledger].rows.firstWhere(
          (e) => e['kind'] == 'reverse_earn',
        )['customer_id']!
        as String;

void main() {
  group('frame and states', () {
    testWidgets('SELL-CUS-026 title, Member pill, phone LTR', (tester) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      expect(sheetText('Nada Kamal'), findsOneWidget);
      expect(sheetText('Member'), findsWidgets);
      final phone = sheetText('+20 100 123 4567');
      expect(phone, findsWidgets);
      expect(tester.widget<Text>(phone.first).textDirection, TextDirection.ltr);
      expect(
        h.server.callsTo('/customers/{id}').single.path,
        '/customers/$nadaId',
      );
    });

    testWidgets('SELL-CUS-026 a non-member without a phone: no pill, no '
        'description', (tester) async {
      final s = customersServer();
      final c = nonMember(s.db)..['phone'] = null;
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await h.tap(rowOf(c['name']! as String));
      expect(sheetText(c['name']! as String), findsOneWidget);
      expect(sheetText('Member'), findsNothing);
      expect(inSheet(textHas('+20')), findsNothing);
    });

    testWidgets('SELL-CUS-027 loading: one skeleton block', (tester) async {
      final h = await pumpCustomers(tester);
      final gate = h.server.hold('GET', '/customers/{id}');
      await openNada(h);
      expect(inSheet(find.byType(DashSkeleton)), findsOneWidget);
      expect(sheetText('Customer'), findsOneWidget);
      gate.release();
      h.server.clearFailures();
      await h.settle();
      expect(sheetText('Nada Kamal'), findsOneWidget);
    });

    testWidgets('SELL-CUS-027 failure: the words, the reason, Retry', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      final missing = MockResponse.error(404, 'Customer not found');
      h.server.fail('GET', '/customers/{id}', missing, times: null);
      await openNada(h);
      expect(sheetText("Couldn't load this customer"), findsOneWidget);
      expect(sheetText(h.refusalWords(missing)), findsOneWidget);
      h.server.clearFailures();
      // The press warmed the read too: a failed warm is dropped and the
      // sheet asks again, as React Query refetches an errored prefetch.
      final failed = h.server.callsTo('/customers/{id}').length;
      final gate = h.server.hold('GET', '/customers/{id}');
      await h.tap(inSheet(find.text('Retry')));
      // The failure stays, its Retry spinning, while the retry runs.
      expect(sheetText("Couldn't load this customer"), findsOneWidget);
      expect(inSheet(find.byType(DashSkeleton)), findsNothing);
      gate.release();
      h.server.clearFailures();
      await h.settle();
      expect(h.server.callsTo('/customers/{id}'), hasLength(failed + 1));
      expect(sheetText('Nada Kamal'), findsOneWidget);
    });

    testWidgets('SELL-CUS-028 an id merged away shows the kept customer', (
      tester,
    ) async {
      final s = customersServer();
      final gone = nonMember(s.db);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      // Merged elsewhere after the list was read.
      s.db[CustomerTables.merged].put({
        ...gone,
        'merged_into': nadaId,
        'merged_at': s.db.clock.now.toIso8601String(),
      });
      s.db['customers'].delete(gone['id']! as String);
      await h.tap(rowOf(gone['name']! as String));
      expect(
        sheetText('The customer you opened was merged into this one.'),
        findsOneWidget,
      );
      expect(sheetText('Nada Kamal'), findsOneWidget);
      expect(sheetText('Merged duplicates: 1'), findsOneWidget);
    });
  });

  group('customer side', () {
    testWidgets('SELL-CUS-029 stats: orders, spent, last visit, since', (
      tester,
    ) async {
      final s = customersServer();
      final nada = customerNamed(s.db, 'Nada Kamal');
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openNada(h);
      final fmt = h.container.read(formatProvider);
      for (final (label, value) in [
        ('Orders', fmt.fmtNumber(nada['orders_count']! as int)),
        ('Total spent', fmt.fmtMoney(nada['total_spent']! as int)),
        (
          'Last visit',
          fmt.fmtDate(DateTime.parse(nada['last_order_at']! as String)),
        ),
        (
          'Customer since',
          fmt.fmtDate(DateTime.parse(nada['created_at']! as String)),
        ),
      ]) {
        expect(sheetText(label), findsWidgets, reason: label);
        expect(inSheet(textHas(value)), findsWidgets, reason: value);
      }
    });

    testWidgets('SELL-CUS-030 the owner: Edit, Merge into…, Erase', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      expect(sheetText('Edit'), findsOneWidget);
      expect(sheetText('Merge into…'), findsOneWidget);
      expect(sheetText('Erase customer'), findsOneWidget);
    });

    testWidgets('SELL-CUS-030 a manager: no Erase (each its own cap)', (
      tester,
    ) async {
      final h = await pumpCustomers(tester, persona: Persona.manager);
      await openNada(h);
      expect(sheetText('Edit'), findsOneWidget);
      expect(sheetText('Merge into…'), findsOneWidget);
      expect(sheetText('Erase customer'), findsNothing);
    });

    testWidgets('SELL-CUS-030 view only: no actions row', (tester) async {
      final h = await pumpCustomers(tester, persona: Persona.limited);
      await openNada(h);
      expect(sheetText('Nada Kamal'), findsOneWidget);
      expect(sheetText('Edit'), findsNothing);
      expect(sheetText('Merge into…'), findsNothing);
      expect(sheetText('Erase customer'), findsNothing);
    });

    testWidgets('SELL-CUS-030 only merge granted: Merge alone', (tester) async {
      final s = customersServer();
      grantOnly(s.server, ['customers.view', 'customers.merge']);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openNada(h);
      expect(sheetText('Merge into…'), findsOneWidget);
      expect(sheetText('Edit'), findsNothing);
      expect(sheetText('Erase customer'), findsNothing);
    });

    testWidgets('SELL-CUS-031 details: phone, language, birthday, source, '
        'consent, notes, merged', (tester) async {
      final s = customersServer();
      customerNamed(s.db, 'Nada Kamal')
        ..['locale'] = 'ar'
        ..['birth_month'] = 3
        ..['birth_day'] = 14
        ..['marketing_opt_out'] = true
        ..['notes'] = 'Prefers oat milk.\nWindow table.';
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openNada(h);
      expect(sheetText('Details'), findsOneWidget);
      expect(sheetText('Language'), findsOneWidget);
      expect(sheetText('Arabic'), findsOneWidget);
      expect(sheetText('Birthday'), findsOneWidget);
      expect(sheetText('14 March'), findsOneWidget);
      expect(sheetText('Loyalty sign-up'), findsOneWidget);
      expect(sheetText('Offers and greetings'), findsOneWidget);
      expect(sheetText('Opted out'), findsOneWidget);
      expect(
        sheetText(
          'Only the customer can change whether they get offers, from their '
          'loyalty card page.',
        ),
        findsOneWidget,
      );
      expect(sheetText('Notes'), findsOneWidget);
      expect(sheetText('Prefers oat milk.\nWindow table.'), findsOneWidget);
      expect(inSheet(textHas('Merged duplicates')), findsNothing);
    });

    testWidgets('SELL-CUS-031 what is not known reads "Not given"', (
      tester,
    ) async {
      final s = customersServer();
      final c = nonMember(s.db)
        ..['phone'] = null
        ..['locale'] = null
        ..['birth_month'] = null
        ..['birth_day'] = null
        ..['source'] = 'mystery'
        ..['marketing_opt_out'] = false
        ..['notes'] = null;
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await h.tap(rowOf(c['name']! as String));
      expect(sheetText('Not given'), findsNWidgets(4));
      expect(sheetText('Allowed'), findsOneWidget);
      expect(sheetText('Notes'), findsNothing);
    });

    testWidgets('SELL-CUS-031 the birthday in Arabic', (tester) async {
      final s = customersServer();
      customerNamed(s.db, 'Nada Kamal')
        ..['birth_month'] = 3
        ..['birth_day'] = 14;
      final h = await pumpCustomers(
        tester,
        server: s.server,
        db: s.db,
        locale: 'ar',
      );
      await openNada(h);
      expect(sheetText('١٤ مارس'), findsOneWidget);
    });
  });

  group('loyalty card', () {
    testWidgets('SELL-CUS-040 a member\'s card is read under the scope', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      expect(sheetText('Loyalty'), findsOneWidget);
      final call = h.server.callsTo('/loyalty/members/{id}').single;
      expect(call.path, '/loyalty/members/$nadaId');
      expect(call.query, isEmpty);
    });

    testWidgets('SELL-CUS-040 a non-member\'s card is never asked for', (
      tester,
    ) async {
      final s = customersServer();
      final c = nonMember(s.db);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await h.tap(rowOf(c['name']! as String));
      expect(sheetText('Loyalty'), findsNothing);
      expect(h.server.callsTo('/loyalty/members/{id}'), isEmpty);
    });

    testWidgets('SELL-CUS-040 no card without a loyalty capability', (
      tester,
    ) async {
      final h = await pumpCustomers(tester, persona: Persona.limited);
      await openNada(h);
      expect(sheetText('Loyalty'), findsNothing);
      expect(h.server.callsTo('/loyalty/members/{id}'), isEmpty);
    });

    testWidgets('SELL-CUS-040 loading skeleton', (tester) async {
      final h = await pumpCustomers(tester);
      final gate = h.server.hold('GET', '/loyalty/members/{id}');
      await openNada(h);
      expect(sheetText('Loyalty'), findsOneWidget);
      expect(inSheet(find.byType(DashSkeleton)), findsOneWidget);
      gate.release();
      h.server.clearFailures();
      await h.settle();
      expect(inSheet(find.byType(DashSkeleton)), findsNothing);
      expect(sheetText('Lifetime'), findsOneWidget);
    });

    testWidgets('SELL-CUS-040 failure with the reason and Retry', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      final down = MockResponse.error(503, 'The wallet service is down');
      h.server.fail('GET', '/loyalty/members/{id}', down, times: null);
      await openNada(h);
      expect(sheetText("Couldn't load this member"), findsOneWidget);
      expect(sheetText(h.refusalWords(down)), findsOneWidget);
      // The customer side still reads.
      expect(sheetText('Details'), findsOneWidget);
      h.server.clearFailures();
      await h.tap(inSheet(find.text('Retry')));
      expect(sheetText("Couldn't load this member"), findsNothing);
      expect(sheetText('Lifetime'), findsOneWidget);
    });

    testWidgets('SELL-CUS-041 the summary and the joined line', (tester) async {
      final s = customersServer();
      customerNamed(s.db, 'Nada Kamal')['points_balance'] = 40;
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openNada(h);
      final m = (await tester.runAsync(
        () => DashboardApi(s.server).loyalty.getLoyaltyMember(id: nadaId),
      ))!.member;
      expect(m.balance, 6);
      final fmt = h.container.read(formatProvider);
      expect(sheetText('Balance'), findsOneWidget);
      // The balance, and (6 % 6 = 0) the whole card still to go.
      expect(sheetText('6 orders'), findsNWidgets(2));
      expect(sheetText('Lifetime'), findsOneWidget);
      expect(sheetText('${m.lifetimeVisits}'), findsWidgets);
      expect(sheetText('Rewards earned'), findsOneWidget);
      expect(sheetText('${m.rewardsReady}'), findsWidgets);
      expect(sheetText('To next reward'), findsOneWidget);
      expect(m.pointsToNextReward, 6);
      expect(
        sheetText(
          'Joined ${fmt.fmtDate(m.enrolledAt)} · Also holds 40 points from '
          'before the program changed mode',
        ),
        findsOneWidget,
      );
    });

    testWidgets('SELL-CUS-042 the owner: Adjust and Remove, no wallet', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      expect(sheetText('Adjust balance'), findsOneWidget);
      expect(sheetText('Remove from loyalty programme'), findsOneWidget);
      expect(sheetText('Google Wallet object'), findsNothing);
    });

    testWidgets('SELL-CUS-042 a platform admin also gets the wallet', (
      tester,
    ) async {
      final h = await pumpCustomers(tester, persona: Persona.platform);
      await openNada(h);
      expect(sheetText('Adjust balance'), findsOneWidget);
      expect(sheetText('Google Wallet object'), findsOneWidget);
      expect(sheetText('Remove from loyalty programme'), findsOneWidget);
    });

    testWidgets('SELL-CUS-042 a manager reads the card, no member actions', (
      tester,
    ) async {
      final h = await pumpCustomers(tester, persona: Persona.manager);
      await openNada(h);
      expect(sheetText('Loyalty'), findsOneWidget);
      expect(sheetText('Adjust balance'), findsNothing);
      expect(sheetText('Remove from loyalty programme'), findsNothing);
      expect(sheetText('Google Wallet object'), findsNothing);
    });

    testWidgets('SELL-CUS-043 the ledger: kinds, actors, notes, amounts', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      for (final head in ['WHEN', 'WHAT', 'AMOUNT', 'BRANCH / ORDER']) {
        expect(sheetText(head), findsOneWidget, reason: head);
      }
      expect(sheetText('Manual adjustment'), findsWidgets);
      expect(sheetText('by Nour El-Sayed'), findsWidgets);
      expect(sheetText('“Stamp missed on 12 Sep order”'), findsOneWidget);
      expect(sheetText('Earned on a sale'), findsWidgets);
      expect(inSheet(textHas('+1')), findsWidgets);
      expect(sheetText('View order'), findsWidgets);
    });

    testWidgets(
      'SELL-CUS-043 Arabic: only the signed number is left-to-right',
      (tester) async {
        final h = await pumpCustomers(tester, locale: 'ar');
        await openNada(h);
        // The number isolated, the unit after it in the page's direction.
        final line =
            '\u2066+1\u2069 ${h.t('loyalty.unitOrders', count: 1)}';
        final amounts = inSheet(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == line,
          ),
        );
        expect(amounts, findsWidgets);
        expect(
          tester.renderObject<RenderParagraph>(amounts.first).textDirection,
          TextDirection.rtl,
        );
      },
    );

    testWidgets('SELL-CUS-043 a voided sale: struck through, "reversed"', (
      tester,
    ) async {
      final s = customersServer();
      final id = _memberWithVoid(s.db);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openSheet(h, id);
      expect(sheetText('Earn reversed (void)'), findsWidgets);
      expect(sheetText('reversed'), findsWidgets);
      expect(inSheet(textHas('−1')), findsWidgets);
    });

    testWidgets('SELL-CUS-043 "View order" opens that order', (tester) async {
      final h = await pumpCustomers(tester);
      h.allowUnmatched = true; // the order sheet's own extra reads
      await openNada(h);
      await h.scrollUntilVisible(
        sheetText('View order').first,
        scrollable: inSheet(find.byType(Scrollable)).first,
      );
      await h.tap(sheetText('View order').first);
      expect(find.byType(OrderSheet), findsOneWidget);
      expect(find.byType(CustomerSheet), findsOneWidget);
      expect(h.server.callsTo('/orders/{order_id}'), hasLength(1));
    });

    testWidgets('SELL-CUS-043 no movements yet; 200 shown means truncated', (
      tester,
    ) async {
      final s = customersServer();
      final rows = s.db[CustomerTables.ledger].rows;
      rows.removeWhere((e) => e['customer_id'] == nadaId);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openNada(h);
      expect(sheetText('No movements yet'), findsOneWidget);
      expect(
        sheetText('Earns, rewards and adjustments will show here.'),
        findsOneWidget,
      );
      await h.tap(inSheet(find.bySemanticsLabel('Close')));
      final base = rows.firstWhere((e) => e['kind'] == 'earn');
      for (var i = 0; i < 200; i++) {
        rows.add({...base, 'id': 'ledger-$i', 'customer_id': nadaId});
      }
      h.container.read(realtimeBusProvider).invalidate(const ['/loyalty/']);
      await openNada(h);
      await h.scrollUntilVisible(
        sheetText('Showing the latest 200 movements.'),
        scrollable: inSheet(find.byType(Scrollable)).first,
        delta: 2000,
      );
      expect(sheetText('Showing the latest 200 movements.'), findsOneWidget);
    });
  });

  group('addresses', () {
    testWidgets('SELL-CUS-049 saved addresses with their use', (tester) async {
      final s = customersServer();
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openNada(h);
      expect(
        h.server.callsTo('/customers/{id}/addresses').single.path,
        '/customers/$nadaId/addresses',
      );
      final fmt = h.container.read(formatProvider);
      expect(sheetText('Addresses'), findsOneWidget);
      expect(sheetText('Home'), findsOneWidget);
      expect(sheetText('Delivery'), findsOneWidget);
      expect(
        sheetText(
          'Unit 14 · Floor 3 · 12 El-Thawra St, Heliopolis · Next to Korba '
          'metro',
        ),
        findsOneWidget,
      );
      expect(sheetText('Ring twice, the bell is quiet.'), findsOneWidget);
      expect(sheetText('Used 9×'), findsOneWidget);
      // The unlabelled one is named by its channel.
      expect(sheetText('In-mall'), findsOneWidget);
      expect(
        sheetText('City Stars, Phase 2 · Unit Shop 214 · Floor 2'),
        findsOneWidget,
      );
      final home = s.db[CustomerTables.addresses].rows.firstWhere(
        (a) => a['label'] == 'Home',
      );
      expect(
        sheetText(
          'Last ${fmt.fmtDate(DateTime.parse(home['last_used_at']! as String))}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('SELL-CUS-049 absent and never asked without the capability', (
      tester,
    ) async {
      final h = await pumpCustomers(tester, persona: Persona.limited);
      await openNada(h);
      expect(sheetText('Addresses'), findsNothing);
      expect(h.server.callsTo('/customers/{id}/addresses'), isEmpty);
    });

    testWidgets('SELL-CUS-049 empty', (tester) async {
      final s = customersServer();
      s.db[CustomerTables.addresses].clear();
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openNada(h);
      expect(
        sheetText(
          'No saved addresses. One is kept the first time they order for '
          'delivery.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('SELL-CUS-049 error with Retry', (tester) async {
      final h = await pumpCustomers(tester);
      final slow = MockResponse.error(500, 'The addresses timed out');
      h.server.fail('GET', '/customers/{id}/addresses', slow, times: null);
      await openNada(h);
      expect(sheetText(h.refusalWords(slow)), findsOneWidget);
      h.server.clearFailures();
      final gate = h.server.hold('GET', '/customers/{id}/addresses');
      await h.tap(inSheet(find.text('Retry')));
      expect(sheetText(h.refusalWords(slow)), findsOneWidget);
      expect(sheetText(h.t('customers.addresses.empty')), findsNothing);
      gate.release();
      h.server.clearFailures();
      await h.settle();
      expect(sheetText('Home'), findsOneWidget);
    });
  });

  group('bookings', () {
    testWidgets('SELL-CUS-050 newest first, party and branch, status', (
      tester,
    ) async {
      final s = customersServer();
      final (id, _) = _booker(s.db);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openSheet(h, id);
      final call = h.server.callsTo('/customers/{id}/bookings').single;
      expect(call.path, '/customers/$id/bookings');
      expect(q1(call), {'limit': '10', 'offset': '0'});
      final newest =
          (s.db[SellTables.bookings].where((b) => b['customer_id'] == id)..sort(
                (a, b) => (b['starts_at']! as String).compareTo(
                  a['starts_at']! as String,
                ),
              ))
              .first;
      final fmt = h.container.read(formatProvider);
      final branch = s.db['branches'].find(newest['branch_id']! as String)!;
      expect(sheetText('Bookings'), findsOneWidget);
      expect(
        sheetText(
          fmt.fmtDateTime(DateTime.parse(newest['starts_at']! as String)),
        ),
        findsWidgets,
      );
      expect(
        inSheet(
          textHas('Party of ${newest['party_size']} · ${branch['name']}'),
        ),
        findsWidgets,
      );
      expect(
        sheetText(h.t('bookings.status.${newest['status']}')),
        findsWidgets,
      );
    });

    testWidgets('SELL-CUS-050 empty and error', (tester) async {
      final s = customersServer();
      s.db[SellTables.bookings].removeWhere((b) => b['customer_id'] == nadaId);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openNada(h);
      expect(
        sheetText(
          "No bookings. A table booked under this customer's number shows "
          'here.',
        ),
        findsOneWidget,
      );
      await h.tap(inSheet(find.bySemanticsLabel('Close')));
      final slow = MockResponse.error(500, 'The bookings timed out');
      h.server.fail('GET', '/customers/{id}/bookings', slow, times: null);
      h.container.read(realtimeBusProvider).invalidate(const ['/customers']);
      await openNada(h);
      expect(sheetText(h.refusalWords(slow)), findsOneWidget);
      h.server.clearFailures();
      await h.tap(inSheet(find.text('Retry')));
      expect(sheetText(h.refusalWords(slow)), findsNothing);
    });

    testWidgets('SELL-CUS-051 / 058 with bookings.read the date opens the '
        'booking on its branch and day', (tester) async {
      final s = customersServer();
      final (id, _) = _booker(s.db);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      h.allowUnmatched = true; // the Bookings page's reads are its unit's
      await openSheet(h, id);
      final newest =
          (s.db[SellTables.bookings].where((b) => b['customer_id'] == id)..sort(
                (a, b) => (b['starts_at']! as String).compareTo(
                  a['starts_at']! as String,
                ),
              ))
              .first;
      final fmt = h.container.read(formatProvider);
      final when = DateTime.parse(newest['starts_at']! as String);
      final link = inSheet(
        find.byWidgetPredicate(
          (w) => w is DashPressable && w.semanticLabel == fmt.fmtDateTime(when),
        ),
      );
      expect(link, findsWidgets);
      await h.tap(link.first);
      expect(find.byType(CustomerSheet), findsNothing);
      expect(h.location.path, '/bookings');
      final day = inZone(when, fmt.timezone);
      final date =
          '${day.year}-${'${day.month}'.padLeft(2, '0')}-'
          '${'${day.day}'.padLeft(2, '0')}';
      expect(h.location.queryParameters, {
        'branchId': newest['branch_id'],
        'date': date,
        'booking': newest['id'],
      });
      expect(
        h.container.read(currentScopeProvider).branchId,
        newest['branch_id'],
      );
    });

    testWidgets('SELL-CUS-051 without bookings.read the date is plain', (
      tester,
    ) async {
      final s = customersServer();
      final (id, _) = _booker(s.db);
      grantOnly(s.server, ['customers.view']);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openSheet(h, id);
      final fmt = h.container.read(formatProvider);
      final first = s.db[SellTables.bookings].rows.firstWhere(
        (b) => b['customer_id'] == id,
      );
      expect(
        inSheet(
          find.byWidgetPredicate(
            (w) =>
                w is DashPressable &&
                w.semanticLabel ==
                    fmt.fmtDateTime(
                      DateTime.parse(first['starts_at']! as String),
                    ),
          ),
        ),
        findsNothing,
      );
      expect(sheetText('Bookings'), findsOneWidget);
    });

    testWidgets('SELL-CUS-052 "Show more" when the page came back full', (
      tester,
    ) async {
      final s = customersServer();
      final table = s.db[SellTables.bookings];
      final base = table.rows.first;
      for (var i = 0; i < 12; i++) {
        table.insert({
          ...base,
          'id': mockUuid('nada-booking:$i'),
          'customer_id': nadaId,
          'starts_at': s.db.clock.now
              .subtract(Duration(days: i + 1))
              .toUtc()
              .toIso8601String(),
        }, timestamps: false);
      }
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openNada(h);
      await h.scrollUntilVisible(
        sheetText('Show more'),
        scrollable: inSheet(find.byType(Scrollable)).first,
      );
      await h.tap(sheetText('Show more'));
      expect(q1(h.server.callsTo('/customers/{id}/bookings').last), {
        'limit': '20',
        'offset': '0',
      });
      expect(sheetText('Show more'), findsNothing);
    });
  });

  group('recent orders', () {
    testWidgets('SELL-CUS-053 the table; an order stacks over the sheet, '
        'without Void', (tester) async {
      final s = customersServer();
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      h.allowUnmatched = true; // the order sheet's own extra reads
      await openNada(h);
      final newest =
          (s.db['orders'].where((o) => o['customer_id'] == nadaId)..sort(
                (a, b) => (b['created_at']! as String).compareTo(
                  a['created_at']! as String,
                ),
              ))
              .first;
      final ref =
          newest['order_ref'] as String? ??
          (newest['id']! as String).substring(0, 8);
      expect(sheetText('Recent orders'), findsOneWidget);
      for (final head in ['ORDER', 'BRANCH', 'STATUS', 'TOTAL', 'DATE']) {
        expect(sheetText(head), findsOneWidget, reason: head);
      }
      final fmt = h.container.read(formatProvider);
      expect(
        sheetText(
          fmt.fmtDateTime(DateTime.parse(newest['created_at']! as String)),
        ),
        findsWidgets,
      );
      final link = inSheet(
        find.byWidgetPredicate(
          (w) => w is DashPressable && w.semanticLabel == ref,
        ),
      );
      await h.scrollUntilVisible(
        link.first,
        scrollable: inSheet(find.byType(Scrollable)).first,
      );
      await h.tap(link.first);
      expect(find.byType(OrderSheet), findsOneWidget);
      expect(find.byType(CustomerSheet), findsOneWidget);
      expect(
        h.server.callsTo('/orders/{order_id}').single.path,
        '/orders/${newest['id']}',
      );
      expect(
        find.descendant(
          of: find.byType(OrderSheet),
          matching: find.text('Void'),
        ),
        findsNothing,
      );
    });

    testWidgets('SELL-CUS-053 another of their orders switches the one order '
        'sheet, never stacks a second', (tester) async {
      final s = customersServer();
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      h.allowUnmatched = true; // the order sheet's own extra reads
      await openNada(h);
      final mine =
          (s.db['orders'].where((o) => o['customer_id'] == nadaId)..sort(
                (a, b) => (b['created_at']! as String).compareTo(
                  a['created_at']! as String,
                ),
              ))
              .toList();
      String refOf(MockRow o) =>
          o['order_ref'] as String? ?? (o['id']! as String).substring(0, 8);
      Finder link(Finder sheet, MockRow o) => find.descendant(
        of: sheet,
        matching: find.byWidgetPredicate(
          (w) => w is DashPressable && w.semanticLabel == refOf(o),
        ),
      );
      final page = find.byType(CustomerSheet).first;
      await h.scrollUntilVisible(
        link(page, mine[0]),
        scrollable: find
            .descendant(of: page, matching: find.byType(Scrollable))
            .first,
      );
      await h.tap(link(page, mine[0]));
      expect(
        tester.widget<OrderSheet>(find.byType(OrderSheet)).orderId,
        mine[0]['id'],
      );
      // From the order, its member's (read-only) sheet, then another order.
      await h.tap(
        find.descendant(
          of: find.byType(OrderSheet),
          matching: find.byWidgetPredicate(
            (w) => w is DashPressable && w.semanticLabel == 'Nada Kamal',
          ),
        ),
      );
      expect(find.byType(CustomerSheet), findsNWidgets(2));
      final member = find.byType(CustomerSheet).last;
      await h.scrollUntilVisible(
        link(member, mine[1]),
        scrollable: find
            .descendant(of: member, matching: find.byType(Scrollable))
            .first,
      );
      await h.tap(link(member, mine[1]));
      await h.settle();
      expect(find.byType(OrderSheet), findsOneWidget);
      expect(
        tester.widget<OrderSheet>(find.byType(OrderSheet)).orderId,
        mine[1]['id'],
      );
      // The page's own customer sheet is still there under it.
      expect(find.byType(CustomerSheet), findsOneWidget);
    });

    testWidgets('SELL-CUS-053 none: only "No orders yet", no heading', (
      tester,
    ) async {
      final s = customersServer();
      final c = nonMember(s.db);
      s.db['orders'].removeWhere((o) => o['customer_id'] == c['id']);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await h.tap(rowOf(c['name']! as String));
      expect(sheetText('No orders yet'), findsOneWidget);
      expect(sheetText('Recent orders'), findsNothing);
    });
  });

  group('who opens it', () {
    testWidgets('SELL-CUS-054 a loyalty-only viewer sees the card alone', (
      tester,
    ) async {
      final s = customersServer();
      grantOnly(s.server, ['loyalty.members.list']);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openSheet(h, nadaId);
      expect(sheetText('Nada Kamal'), findsOneWidget);
      expect(sheetText('Member'), findsWidgets);
      expect(sheetText('Loyalty'), findsOneWidget);
      expect(h.server.callsTo('/customers/{id}'), isEmpty);
      expect(h.server.callsTo('/customers/{id}/bookings'), isEmpty);
      expect(h.server.callsTo('/customers/{id}/addresses'), isEmpty);
      expect(
        h.server.callsTo('/loyalty/members/{id}').single.path,
        '/loyalty/members/$nadaId',
      );
      for (final gone in [
        'Details',
        'Bookings',
        'Addresses',
        'Recent orders',
        'Edit',
        'Adjust balance',
      ]) {
        expect(sheetText(gone), findsNothing, reason: gone);
      }
    });

    testWidgets(
      'SELL-CUS-054 a loyalty-only viewer\'s failure reads "member"',
      (tester) async {
        final s = customersServer();
        grantOnly(s.server, ['loyalty.read']);
        final missing = MockResponse.error(404, 'Member not found');
        s.server.fail('GET', '/loyalty/members/{id}', missing, times: null);
        final h = await pumpCustomers(tester, server: s.server, db: s.db);
        await openSheet(h, nadaId);
        expect(sheetText("Couldn't load this member"), findsOneWidget);
        expect(sheetText(h.refusalWords(missing)), findsOneWidget);
      },
    );

    testWidgets('SELL-CUS-055 / SELL-ALL-016 read-only: no actions, an order '
        'closes the customer sheet first', (tester) async {
      final h = await pumpCustomers(tester, persona: Persona.platform);
      h.allowUnmatched = true; // the order sheet's own extra reads
      await openSheet(h, nadaId, readOnly: true);
      expect(sheetText('Nada Kamal'), findsOneWidget);
      expect(sheetText('Details'), findsOneWidget);
      expect(sheetText('Loyalty'), findsOneWidget);
      for (final gone in [
        'Edit',
        'Merge into…',
        'Erase customer',
        'Adjust balance',
        'Remove from loyalty programme',
        'Google Wallet object',
      ]) {
        expect(sheetText(gone), findsNothing, reason: gone);
      }
      final view = sheetText('View order').first;
      await h.scrollUntilVisible(
        view,
        scrollable: inSheet(find.byType(Scrollable)).first,
      );
      await h.tap(view);
      expect(find.byType(CustomerSheet), findsNothing);
      expect(find.byType(OrderSheet), findsOneWidget);
    });
  });
}
