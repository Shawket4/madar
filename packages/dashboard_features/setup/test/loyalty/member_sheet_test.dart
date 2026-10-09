// A member's card from the Members tab: the stats, the actions per persona,
// the ledger, adjust, leave and the Google Wallet diagnostics
// (SET-LOY-062, 064 … 075, 084).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/loyalty/google_object_dialog.dart';
import 'package:dashboard_setup/src/loyalty/member_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<DashHarness> _openNada(
  WidgetTester tester, {
  String query = '',
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  ({MockServer server, MockDb db})? backend,
  String name = 'Nada Kamal',
}) async {
  final h = await pumpLoyalty(
    tester,
    query: query,
    persona: persona,
    size: size,
    locale: locale,
    backend: backend ?? loyaltyServer(persona: persona),
  );
  await openTab(h, h.t('loyalty.tabMembers'));
  await h.enterText(inPage(find.byType(DashSearchInput)), name);
  await tester.pump(const Duration(milliseconds: 350));
  await h.settle();
  await h.tap(
    inPage(
      find.byWidgetPredicate(
        (w) => w is DashPressable && w.semanticLabel == name,
      ),
    ),
  );
  return h;
}

Finder _stat(String label) => inSheet(
  find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
);

String _statValue(WidgetTester tester, String label) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: _stat(label), matching: find.byType(Text)),
  );
  return texts.last.data!;
}

List<MockRow> _ledger(MockDb db, String id) => [
  for (final e in db[LoyaltyTables.ledger].rows)
    if (e['customer_id'] == id) e,
];

void main() {
  group('the card', () {
    testWidgets('SET-LOY-064 four stats: balance, lifetime, rewards earned, '
        'to next reward', (tester) async {
      final m = loyaltyServer();
      await _openNada(tester, backend: m);
      final lifetime = _ledger(m.db, nadaId)
          .where((e) => e['kind'] == 'earn' || e['kind'] == 'reverse_earn')
          .fold<int>(0, (s, e) => s + (e['points']! as int));
      expect(_statValue(tester, 'Balance'), '6 orders');
      expect(_statValue(tester, 'Lifetime'), '$lifetime');
      // The cheapest reward is the four-stamp cookie: one earned, two to go.
      expect(_statValue(tester, 'Rewards earned'), '1');
      expect(_statValue(tester, 'To next reward'), '2 orders');
      // Four across on a wide screen.
      final tops = {
        for (final l in ['Balance', 'Lifetime', 'Rewards earned', 'To next reward'])
          tester.getTopLeft(_stat(l)).dy,
      };
      expect(tops, hasLength(1));
      expect(inSheet(find.text('Nada Kamal')), findsOneWidget);
      expect(inSheet(find.text('+20 100 123 4567')), findsOneWidget);
    });

    testWidgets('SET-LOY-064 phone: two stats a row, the card full screen',
        (tester) async {
      await _openNada(tester, size: DashSize.phone);
      final tops = {
        for (final l in ['Balance', 'Lifetime', 'Rewards earned', 'To next reward'])
          tester.getTopLeft(_stat(l)).dy,
      };
      expect(tops, hasLength(2));
    });

    testWidgets('SET-LOY-065 "Joined …" and a balance held in the other '
        'currency', (tester) async {
      final m = loyaltyServer();
      m.db['customers'].find(nadaId)!['points_balance'] = 40;
      final h = await _openNada(tester, backend: m);
      expect(
        inSheet(find.textContaining('Joined ')),
        findsOneWidget,
      );
      expect(
        inSheet(
          find.textContaining(
            ' · Also holds 40 points from before the program changed mode',
          ),
        ),
        findsOneWidget,
      );
      expect(h.server.unmatched, isEmpty);
    });

    testWidgets('SET-LOY-066 the owner: Adjust and Remove, no Google',
        (tester) async {
      await _openNada(tester);
      expect(find.byKey(const ValueKey('member-adjust')), findsOneWidget);
      expect(find.byKey(const ValueKey('member-leave')), findsOneWidget);
      expect(find.byKey(const ValueKey('member-google')), findsNothing);
    });

    testWidgets('SET-LOY-066 platform: all three actions', (tester) async {
      await _openNada(tester, persona: Persona.platform);
      for (final k in ['member-adjust', 'member-leave', 'member-google']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('SET-LOY-066 a manager (no adjust, no delete): no actions',
        (tester) async {
      await _openNada(tester, persona: Persona.manager);
      expect(find.byKey(const ValueKey('member-adjust')), findsNothing);
      expect(find.byKey(const ValueKey('member-leave')), findsNothing);
    });

    testWidgets('SET-LOY-062 a failed card read: the words and Retry',
        (tester) async {
      final m = loyaltyServer();
      final boom = MockResponse.error(500, 'Database error: timeout');
      m.server.fail('GET', LoyaltyRoutes.member, boom, times: null);
      final h = await _openNada(tester, backend: m);
      expect(inSheet(find.text("Couldn't load this member")), findsOneWidget);
      expect(inSheet(find.text(h.refusalWords(boom))), findsOneWidget);
      m.server.clearFailures();
      await h.tap(inSheet(find.text('Retry')));
      expect(_statValue(tester, 'Balance'), '6 orders');
    });
  });

  group('the ledger', () {
    testWidgets('SET-LOY-067 rows: when, the labelled pill, who, the note, '
        'the signed amount, the branch and the order link', (tester) async {
      final m = loyaltyServer();
      final h = await _openNada(tester, backend: m);
      for (final head in ['WHEN', 'WHAT', 'AMOUNT', 'BRANCH / ORDER']) {
        expect(inSheet(find.text(head)), findsOneWidget, reason: head);
      }
      final manual = _ledger(m.db, nadaId).firstWhere(
        (e) => e['note'] == 'Stamp missed on 12 Sep order',
      );
      final row = find.byKey(ValueKey('ledger-row-${manual['id']}'));
      Finder inRow(Finder f) => find.descendant(of: row, matching: f);
      expect(inRow(find.text('Manual adjustment')), findsOneWidget);
      expect(inRow(find.text('by Nour El-Sayed')), findsOneWidget);
      expect(inRow(find.text('“Stamp missed on 12 Sep order”')), findsOneWidget);
      expect(inRow(find.textContaining('+1', findRichText: true)), findsOneWidget);
      expect(inRow(find.text('Heliopolis')), findsOneWidget);
      final sale = _ledger(m.db, nadaId).firstWhere((e) => e['kind'] == 'earn');
      final saleRow = find.byKey(ValueKey('ledger-row-${sale['id']}'));
      expect(
        find.descendant(of: saleRow, matching: find.text('Earned on a sale')),
        findsOneWidget,
      );
      h.allowUnmatched = true;
      await h.tap(
        find.descendant(of: saleRow, matching: find.text('View order')),
      );
      expect(h.location.path, '/orders');
      expect(h.location.queryParameters['order'], sale['order_id']);
      expect(find.byType(MemberSheet), findsNothing);
    });

    testWidgets('SET-LOY-067 a reversed row is struck through and marked; '
        'the reversal reads "Earn reversed (void)"', (tester) async {
      final m = loyaltyServer();
      final ledger = m.db[LoyaltyTables.ledger]..rows;
      final earn = _ledger(m.db, nadaId).firstWhere((e) => e['kind'] == 'earn');
      ledger.insert({
        ...earn,
        'id': 'reversal-1',
        'kind': 'reverse_earn',
        'source': 'void',
        'points': -1,
        'reverses_id': earn['id'],
        'created_by': null,
        'created_by_name': null,
        'created_at': m.db.nowIso,
      }, timestamps: false);
      await _openNada(tester, backend: m);
      final row = find.byKey(ValueKey('ledger-row-${earn['id']}'));
      expect(find.descendant(of: row, matching: find.text('reversed')), findsOneWidget);
      final amount = tester.widget<RichText>(
        find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().contains('+1'),
          ),
        ),
      );
      TextSpan? figure;
      amount.text.visitChildren((span) {
        if (span is TextSpan && (span.text ?? '').contains('+1')) {
          figure = span;
          return false;
        }
        return true;
      });
      expect(figure!.style!.decoration, TextDecoration.lineThrough);
      final rev = find.byKey(const ValueKey('ledger-row-reversal-1'));
      expect(
        find.descendant(of: rev, matching: find.text('Earn reversed (void)')),
        findsOneWidget,
      );
      expect(find.descendant(of: rev, matching: find.text('automatic')), findsOneWidget);
    });

    testWidgets('SET-LOY-084 an author whose account is gone reads "by —"',
        (tester) async {
      final m = loyaltyServer();
      final manual = _ledger(m.db, nadaId).firstWhere(
        (e) => e['note'] == 'Stamp missed on 12 Sep order',
      );
      manual['created_by_name'] = null;
      await _openNada(tester, backend: m);
      final row = find.byKey(ValueKey('ledger-row-${manual['id']}'));
      expect(find.descendant(of: row, matching: find.text('by —')), findsOneWidget);
    });

    testWidgets('SET-LOY-068 no movements yet', (tester) async {
      final m = loyaltyServer();
      m.db[LoyaltyTables.ledger].removeWhere((e) => e['customer_id'] == nadaId);
      final h = await _openNada(tester, backend: m);
      expect(inSheet(find.text('No movements yet')), findsOneWidget);
      expect(inSheet(find.text(h.t('loyalty.noLedgerHint'))), findsOneWidget);
    });

    testWidgets('SET-LOY-068 200 movements or more: "Showing the latest 200"',
        (tester) async {
      final m = loyaltyServer();
      final ledger = m.db[LoyaltyTables.ledger];
      final base = _ledger(m.db, nadaId).first;
      for (var i = 0; i < 200; i++) {
        ledger.insert({...base, 'id': 'bulk-$i'}, timestamps: false);
      }
      await _openNada(tester, backend: m);
      expect(
        inSheet(find.text('Showing the latest 200 movements.')),
        findsOneWidget,
      );
    });

    testWidgets('SET-LOY-067 phone: stacked ledger rows', (tester) async {
      await _openNada(tester, size: DashSize.phone);
      expect(inSheet(find.text('WHEN')), findsNothing);
      expect(inSheet(find.text('Manual adjustment')), findsWidgets);
    });
  });

  group('adjust', () {
    testWidgets('SET-LOY-069 the dialog: title, balance, Add/Deduct, amount '
        'in the unit, the branch, the reason', (tester) async {
      final h = await _openNada(tester);
      await h.tap(find.byKey(const ValueKey('member-adjust')));
      expect(inDialog(find.text('Adjust balance')), findsOneWidget);
      expect(
        inDialog(find.text(
          'Nada Kamal has 6 orders. The reason is kept on their history.',
        )),
        findsOneWidget,
      );
      expect(inDialog(find.text('Add')), findsOneWidget);
      expect(inDialog(find.text('Deduct')), findsOneWidget);
      expect(inDialog(find.text('Amount (orders)')), findsOneWidget);
      // At org scope with four branches: the choice shows, unpicked.
      expect(inDialog(find.text('Pick a branch')), findsOneWidget);
      expect(
        inDialog(find.text('e.g. Stamp missed on 12 Sep order')),
        findsOneWidget,
      );
    });

    testWidgets('SET-LOY-069 at a branch: it is the default', (tester) async {
      final h = await _openNada(tester, query: atBranch(SeedIds.zamalek));
      await h.tap(find.byKey(const ValueKey('member-adjust')));
      expect(inDialog(find.text('Zamalek')), findsOneWidget);
    });

    testWidgets('SET-LOY-069 a warehouse is never a choice and never counts '
        'toward "more than one branch"', (tester) async {
      final m = loyaltyServer();
      final branches = m.db['branches'];
      for (final r in [...branches.rows]) {
        if (r['org_id'] == SeedIds.sabahOrg && r['id'] != SeedIds.zamalek) {
          branches.update(r['id']! as String, {'is_active': false});
        }
      }
      branches.insert({
        ...branches.get(SeedIds.zamalek),
        'id': 'wh-main',
        'name': 'Main Warehouse',
        'code': 'WH',
        'kind': 'warehouse',
      }, timestamps: false);
      final h = await _openNada(tester, backend: m);
      await h.tap(find.byKey(const ValueKey('member-adjust')));
      // One selling branch left: it is the default, so no choice shows.
      expect(inDialog(find.text('Pick a branch')), findsNothing);
      expect(inDialog(find.text('Main Warehouse')), findsNothing);
      await h.enterText(find.byKey(const ValueKey('adjust-amount')), '1');
      await h.enterText(find.byKey(const ValueKey('adjust-reason')), 'Missed');
      await h.tap(find.byKey(const ValueKey('adjust-confirm')));
      expect(
        bodyOf(h.server.callsTo(LoyaltyRoutes.adjust).single)['branch_id'],
        SeedIds.zamalek,
      );
      await h.expectToast('Balance adjusted');
    });

    testWidgets('SET-LOY-070 validation: amount, overdraw, branch, reason',
        (tester) async {
      final h = await _openNada(tester);
      await h.tap(find.byKey(const ValueKey('member-adjust')));
      await h.tap(find.byKey(const ValueKey('adjust-confirm')));
      expect(inDialog(find.text('Enter a whole number above zero.')), findsOneWidget);
      expect(
        inDialog(find.text('Pick the branch this adjustment belongs to.')),
        findsOneWidget,
      );
      expect(
        inDialog(find.text(h.t('loyalty.errors.adjustReason'))),
        findsOneWidget,
      );
      await h.tap(inDialog(find.text('Deduct')));
      await h.enterText(find.byKey(const ValueKey('adjust-amount')), '10');
      await h.tap(find.byKey(const ValueKey('adjust-confirm')));
      expect(
        inDialog(find.text(
          "They only have 6 orders — a deduction can't take the balance below zero.",
        )),
        findsOneWidget,
      );
      expect(h.server.callsTo(LoyaltyRoutes.adjust), isEmpty);
    });

    testWidgets('SET-LOY-071 submit: the body, the toast, every person read '
        'refreshed, the dialog closes', (tester) async {
      final m = loyaltyServer();
      final h = await _openNada(tester, query: atBranch(SeedIds.zamalek), backend: m);
      final seen = watchInvalidations(h);
      await h.tap(find.byKey(const ValueKey('member-adjust')));
      await h.enterText(find.byKey(const ValueKey('adjust-amount')), '2');
      await h.enterText(
        find.byKey(const ValueKey('adjust-reason')),
        '  Two stamps missed on Friday  ',
      );
      await h.tap(find.byKey(const ValueKey('adjust-confirm')));
      expect(bodyOf(h.server.callsTo(LoyaltyRoutes.adjust).single), {
        'branch_id': SeedIds.zamalek,
        'customer_id': nadaId,
        'points': 2,
        'note': 'Two stamps missed on Friday',
      });
      await h.expectToast('Balance adjusted');
      expect(seen, contains(const ['/customers', '/loyalty/']));
      expect(find.byType(AdjustDialog), findsNothing);
      expect(_statValue(tester, 'Balance'), '8 orders');
    });

    testWidgets('SET-LOY-071 deduct sends a negative amount', (tester) async {
      final m = loyaltyServer();
      final h = await _openNada(tester, query: atBranch(SeedIds.zamalek), backend: m);
      await h.tap(find.byKey(const ValueKey('member-adjust')));
      await h.tap(inDialog(find.text('Deduct')));
      await h.enterText(find.byKey(const ValueKey('adjust-amount')), '3');
      await h.enterText(find.byKey(const ValueKey('adjust-reason')), 'Duplicate stamps');
      await h.tap(find.byKey(const ValueKey('adjust-confirm')));
      expect(bodyOf(h.server.callsTo(LoyaltyRoutes.adjust).single)['points'], -3);
      await h.flushTimers();
    });

    testWidgets('SET-LOY-072 the server\'s "note required" refusal lands on '
        'the reason, and toasts', (tester) async {
      final m = loyaltyServer();
      m.server.fail(
        'POST',
        LoyaltyRoutes.adjust,
        MockResponse.badRequest('Say why the points are being adjusted (note)'),
      );
      final h = await _openNada(tester, query: atBranch(SeedIds.zamalek), backend: m);
      await h.tap(find.byKey(const ValueKey('member-adjust')));
      await h.enterText(find.byKey(const ValueKey('adjust-amount')), '1');
      await h.enterText(find.byKey(const ValueKey('adjust-reason')), 'Fix');
      await h.tap(find.byKey(const ValueKey('adjust-confirm')));
      final words = h.t('loyalty.errors.serverNoteRequired');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('adjust-reason')),
          matching: find.text(words),
        ),
        findsOneWidget,
      );
      await h.expectToast(words);
    });

    testWidgets('SET-LOY-072 any other refusal: the server\'s words',
        (tester) async {
      final m = loyaltyServer();
      final no = MockResponse.denied('loyalty.points.adjust');
      m.server.fail('POST', LoyaltyRoutes.adjust, no);
      final h = await _openNada(tester, query: atBranch(SeedIds.zamalek), backend: m);
      await h.tap(find.byKey(const ValueKey('member-adjust')));
      await h.enterText(find.byKey(const ValueKey('adjust-amount')), '1');
      await h.enterText(find.byKey(const ValueKey('adjust-reason')), 'Manual fix');
      await h.tap(find.byKey(const ValueKey('adjust-confirm')));
      await h.expectToast(h.refusalWords(no));
      expect(inDialog(find.text('Adjust balance')), findsOneWidget);
    });
  });

  group('leave', () {
    testWidgets('SET-LOY-073 remove from the programme: the alert, the '
        'request, the toast; the card closes and the list drops them',
        (tester) async {
      final m = loyaltyServer();
      final h = await _openNada(tester, backend: m);
      final seen = watchInvalidations(h);
      await h.tap(find.byKey(const ValueKey('member-leave')));
      expect(
        find.text('Remove Nada Kamal from the loyalty programme?'),
        findsOneWidget,
      );
      for (final k in ['stops', 'stays', 'rejoin']) {
        expect(find.text(h.t('loyalty.leave.$k')), findsOneWidget, reason: k);
      }
      final gate = m.server.hold('DELETE', LoyaltyRoutes.member);
      await h.tap(find.byKey(const ValueKey('leave-confirm')));
      expect(buttonAt(tester, 'leave-confirm').loading, isTrue);
      expect(
        tester
            .widget<DashButton>(
              find.byWidgetPredicate(
                (w) => w is DashButton && w.label == 'Cancel',
              ).last,
            )
            .onPressed,
        isNull,
      );
      gate.release();
      await h.settle();
      expect(
        h.server.callsTo(LoyaltyRoutes.member, method: 'DELETE').single.path,
        '/loyalty/members/$nadaId',
      );
      await h.expectToast('Removed from the loyalty programme');
      expect(seen, contains(const ['/customers', '/loyalty/']));
      expect(find.byType(MemberSheet), findsNothing);
      expect(
        inPage(find.byWidgetPredicate(
          (w) => w is DashPressable && w.semanticLabel == 'Nada Kamal',
        )),
        findsNothing,
      );
    });

    testWidgets('SET-LOY-073 the Arabic copy', (tester) async {
      final h = await _openNada(tester, locale: 'ar');
      await h.tap(find.byKey(const ValueKey('member-leave')));
      expect(
        find.text(h.t('loyalty.leave.title', args: {'name': 'Nada Kamal'})),
        findsOneWidget,
      );
      expect(find.text(h.t('loyalty.leave.confirm')), findsOneWidget);
    });

    testWidgets('SET-LOY-073 a refusal toasts; the alert stays',
        (tester) async {
      final m = loyaltyServer();
      final no = MockResponse.denied('loyalty.members.delete');
      m.server.fail('DELETE', LoyaltyRoutes.member, no);
      final h = await _openNada(tester, backend: m);
      await h.tap(find.byKey(const ValueKey('member-leave')));
      await h.tap(find.byKey(const ValueKey('leave-confirm')));
      await h.expectToast(h.refusalWords(no));
      expect(find.byKey(const ValueKey('leave-confirm')), findsOneWidget);
    });
  });

  group('Google Wallet', () {
    testWidgets('SET-LOY-074 the object: branches sent and held (green when '
        'equal), the raw JSON', (tester) async {
      final m = loyaltyServer(persona: Persona.platform);
      final gate = m.server.hold('GET', LoyaltyRoutes.googleObject);
      final h = await _openNada(tester, persona: Persona.platform, backend: m);
      await h.tap(find.byKey(const ValueKey('member-google')));
      final dialog = find.byType(GoogleObjectDialog);
      expect(
        find.descendant(of: dialog, matching: find.byType(DashSkeleton)),
        findsOneWidget,
      );
      gate.release();
      await h.settle();
      expect(inDialog(find.text('Google Wallet object')), findsOneWidget);
      expect(
        inDialog(find.text('What Google is holding for Nada Kamal.')),
        findsOneWidget,
      );
      expect(
        inDialog(find.textContaining('Branches we send: ', findRichText: true)),
        findsOneWidget,
      );
      expect(
        inDialog(find.textContaining('"accountName": "Nada Kamal"')),
        findsOneWidget,
      );
    });

    testWidgets('SET-LOY-074 a member whose card lacks its locations: '
        '"Branches Google has: 0"', (tester) async {
      final m = loyaltyServer(persona: Persona.platform);
      final name = m.db['customers'].find(MockSeed.customerId(3))!;
      name['is_member'] = true;
      name['name'] = 'Salma Fathy';
      final h = await _openNada(
        tester,
        persona: Persona.platform,
        backend: m,
        name: 'Salma Fathy',
      );
      await h.tap(find.byKey(const ValueKey('member-google')));
      expect(
        inDialog(find.textContaining('Branches Google has: 0', findRichText: true)),
        findsOneWidget,
      );
    });

    testWidgets('SET-LOY-075 "Send it again, and show me": the report and '
        'every step; closing clears it', (tester) async {
      final h = await _openNada(tester, persona: Persona.platform);
      await h.tap(find.byKey(const ValueKey('member-google')));
      await h.tap(inDialog(find.text('Send it again, and show me')));
      expect(
        h.server.callsTo(LoyaltyRoutes.googleRefresh).single.path,
        '/loyalty/members/$nadaId/google-refresh',
      );
      expect(inDialog(find.textContaining('Sent: ', findRichText: true)), findsOneWidget);
      expect(inDialog(find.text('loyaltyObject.get')), findsOneWidget);
      expect(inDialog(find.text('404')), findsOneWidget);
      expect(inDialog(find.text('The class, as Google holds it')), findsOneWidget);
      await h.tap(inDialog(find.text('The class, as Google holds it')));
      expect(inDialog(find.textContaining('"reviewStatus"')), findsWidgets);
    });

    testWidgets('SET-LOY-075 a failed send: the server\'s words in red',
        (tester) async {
      final m = loyaltyServer(persona: Persona.platform);
      final boom = MockResponse.error(502, 'Google refused the class');
      m.server.fail('POST', LoyaltyRoutes.googleRefresh, boom);
      final h = await _openNada(tester, persona: Persona.platform, backend: m);
      await h.tap(find.byKey(const ValueKey('member-google')));
      await h.tap(inDialog(find.text('Send it again, and show me')));
      expect(inDialog(find.text(h.refusalWords(boom))), findsOneWidget);
    });
  });
}
