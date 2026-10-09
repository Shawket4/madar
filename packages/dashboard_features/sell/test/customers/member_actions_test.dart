// The loyalty card's actions inside the customer sheet: adjust, leave the
// programme, the Google Wallet inspector (SELL-CUS-044 … 048).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/customers/adjust_dialog.dart';
import 'package:dashboard_sell/src/customers/customer_sheet.dart';
import 'package:dashboard_sell/src/customers/google_object_dialog.dart';
import 'package:dashboard_sell/src/customers/leave_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _amount = ValueKey('adjust-amount');
const _branch = ValueKey('adjust-branch');
const _reason = ValueKey('adjust-reason');

Finder button(String label) =>
    find.byWidgetPredicate((w) => w is DashButton && w.label == label).last;

Future<void> openAdjust(DashHarness h) async {
  await openNada(h);
  await h.tap(sheetText('Adjust balance'));
}

Future<void> pickBranch(DashHarness h, String name) async {
  await h.tap(find.byKey(_branch));
  await h.tap(optionText(name));
}

String _heliopolis(DashHarness h) =>
    h.db!['branches'].find(SeedIds.heliopolis)!['name']! as String;

void main() {
  group('adjust', () {
    testWidgets('SELL-CUS-044 the dialog', (tester) async {
      final h = await pumpCustomers(tester);
      await openAdjust(h);
      expect(find.byType(AdjustDialog), findsOneWidget);
      expect(inDialog(find.text('Adjust balance')), findsOneWidget);
      expect(
        inDialog(
          find.text(
            'Nada Kamal has 6 orders. The reason is kept on their history.',
          ),
        ),
        findsOneWidget,
      );
      expect(inDialog(find.text('Add')), findsOneWidget);
      expect(inDialog(find.text('Deduct')), findsOneWidget);
      expect(inDialog(find.text('Amount (orders)')), findsOneWidget);
      // Several active branches and none preselected: the choice shows.
      expect(inDialog(find.text('Branch')), findsOneWidget);
      expect(inDialog(find.text('Pick a branch')), findsOneWidget);
      expect(inDialog(find.text('Reason')), findsOneWidget);
      expect(
        inDialog(find.text('e.g. Stamp missed on 12 Sep order')),
        findsOneWidget,
      );
      expect(inDialog(find.text('Save adjustment')), findsOneWidget);
      // Only active branches are offered.
      await h.tap(find.byKey(_branch));
      final active = h.db!['branches'].rows.where(
        (b) => b['org_id'] == SeedIds.sabahOrg && b['is_active'] == true,
      );
      for (final b in active) {
        expect(optionText(b['name']! as String), findsOneWidget);
      }
    });

    testWidgets('SELL-CUS-044 one active branch: no branch choice', (
      tester,
    ) async {
      final s = customersServer();
      for (final b in s.db['branches'].rows) {
        if (b['id'] != SeedIds.heliopolis) b['is_active'] = false;
      }
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openAdjust(h);
      expect(find.byKey(_branch), findsNothing);
    });

    testWidgets('SELL-CUS-045 the rules', (tester) async {
      final h = await pumpCustomers(tester);
      await openAdjust(h);
      await h.tap(button('Save adjustment'));
      expect(
        inDialog(find.text('Pick the branch this adjustment belongs to.')),
        findsOneWidget,
      );
      expect(
        inDialog(find.text('Enter a whole number above zero.')),
        findsOneWidget,
      );
      expect(
        inDialog(
          find.text(
            "Say why — at least 3 characters. It stays on the member's "
            'history.',
          ),
        ),
        findsOneWidget,
      );
      for (final bad in ['1.5', '0', '1000001', 'two']) {
        await h.enterText(find.byKey(_amount), bad);
        await h.tap(button('Save adjustment'));
        expect(
          inDialog(find.text('Enter a whole number above zero.')),
          findsOneWidget,
          reason: bad,
        );
      }
      await h.tap(inDialog(find.text('Deduct')));
      await h.enterText(find.byKey(_amount), '10');
      await h.tap(button('Save adjustment'));
      expect(
        inDialog(
          find.text(
            "They only have 6 orders — a deduction can't take the balance "
            'below zero.',
          ),
        ),
        findsOneWidget,
      );
      // The reason box stops at 500.
      await h.enterText(find.byKey(_reason), 'r' * 520);
      final reason = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(_reason),
          matching: find.byType(EditableText),
        ),
      );
      expect(reason.controller.text.length, 500);
      expect(h.server.callsTo('/loyalty/adjust'), isEmpty);
    });

    testWidgets('SELL-CUS-046 save: the body, toast, the card refetches', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await openAdjust(h);
      final reads = h.server.callsTo('/loyalty/members/{id}').length;
      await h.enterText(find.byKey(_amount), '2');
      await pickBranch(h, _heliopolis(h));
      await h.enterText(find.byKey(_reason), '  Stamps missed on 3 Oct  ');
      await h.tap(button('Save adjustment'));
      final post = h.server.callsTo('/loyalty/adjust').single;
      expect(post.body, {
        'branch_id': SeedIds.heliopolis,
        'customer_id': nadaId,
        'points': 2,
        'note': 'Stamps missed on 3 Oct',
      });
      await h.expectToast('Balance adjusted', keep: true);
      expect(find.byType(AdjustDialog), findsNothing);
      expect(
        h.server.callsTo('/loyalty/members/{id}').length,
        greaterThan(reads),
      );
      expect(sheetText('8 orders'), findsOneWidget);
      expect(sheetText('“Stamps missed on 3 Oct”'), findsOneWidget);
      await h.flushTimers();
    });

    testWidgets('SELL-CUS-046 a deduction sends a negative amount', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await openAdjust(h);
      await h.tap(inDialog(find.text('Deduct')));
      await h.enterText(find.byKey(_amount), '6');
      await pickBranch(h, _heliopolis(h));
      await h.enterText(find.byKey(_reason), 'Paper card returned');
      await h.tap(button('Save adjustment'));
      expect(
        (h.server.callsTo('/loyalty/adjust').single.body! as Map)['points'],
        -6,
      );
      await h.expectToast('Balance adjusted');
    });

    testWidgets('SELL-CUS-046 the server\'s "note required" goes on Reason '
        'and toasts', (tester) async {
      final h = await pumpCustomers(tester);
      await openAdjust(h);
      await h.enterText(find.byKey(_amount), '2');
      await pickBranch(h, _heliopolis(h));
      await h.enterText(find.byKey(_reason), 'abc');
      h.server.fail(
        'POST',
        '/loyalty/adjust',
        MockResponse.badRequest('Say why the points are being adjusted (note)'),
      );
      await h.tap(button('Save adjustment'));
      const words =
          'Say why the points are being adjusted — the reason is required.';
      expect(inDialog(find.text(words)), findsOneWidget);
      await h.expectToast(words);
      expect(find.byType(AdjustDialog), findsOneWidget);
    });

    testWidgets('SELL-CUS-046 another refusal toasts its sentence', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await openAdjust(h);
      await h.enterText(find.byKey(_amount), '2');
      await pickBranch(h, _heliopolis(h));
      await h.enterText(find.byKey(_reason), 'Goodwill');
      h.server.fail(
        'POST',
        '/loyalty/adjust',
        MockResponse.denied('loyalty.points.adjust'),
      );
      await h.tap(button('Save adjustment'));
      await h.expectToast(h.t('errors.unauthorized'));
    });
  });

  group('leave the programme', () {
    testWidgets('SELL-CUS-047 the alert, then removed: toast, the sheet '
        'stays, no longer a member', (tester) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      await h.tap(sheetText('Remove from loyalty programme'));
      expect(find.byType(LeaveProgrammeDialog), findsOneWidget);
      expect(
        find.text('Remove Nada Kamal from the loyalty programme?'),
        findsOneWidget,
      );
      for (final k in [
        'loyalty.leave.stops',
        'loyalty.leave.stays',
        'loyalty.leave.rejoin',
      ]) {
        expect(find.text(h.t(k)), findsOneWidget, reason: k);
      }
      await h.tap(button('Remove from programme'));
      expect(
        h.server.callsTo('/loyalty/members/{id}', method: 'DELETE').single.path,
        '/loyalty/members/$nadaId',
      );
      await h.expectToast('Removed from the loyalty programme', keep: true);
      expect(find.byType(LeaveProgrammeDialog), findsNothing);
      expect(find.byType(CustomerSheet), findsOneWidget);
      expect(sheetText('Loyalty'), findsNothing);
      expect(sheetText('Member'), findsNothing);
      await h.flushTimers();
    });

    testWidgets('SELL-CUS-047 cannot be dismissed while it runs', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      await h.tap(sheetText('Remove from loyalty programme'));
      final gate = h.server.hold('DELETE', '/loyalty/members/{id}');
      await h.tap(button('Remove from programme'));
      expect(tester.widget<DashButton>(button('Cancel')).onPressed, isNull);
      expect(
        tester.widget<DashButton>(button('Remove from programme')).loading,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(find.byType(LeaveProgrammeDialog), findsOneWidget);
      gate.release();
      h.server.clearFailures();
      await h.settle();
      await h.flushTimers();
    });

    testWidgets('SELL-CUS-047 Cancel keeps the card; a failure toasts', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      await h.tap(sheetText('Remove from loyalty programme'));
      await h.tap(button('Cancel'));
      expect(find.byType(LeaveProgrammeDialog), findsNothing);
      expect(
        h.server.callsTo('/loyalty/members/{id}', method: 'DELETE'),
        isEmpty,
      );
      await h.tap(sheetText('Remove from loyalty programme'));
      h.server.fail(
        'DELETE',
        '/loyalty/members/{id}',
        MockResponse.denied('loyalty.members.delete'),
      );
      await h.tap(button('Remove from programme'));
      await h.expectToast(h.t('errors.unauthorized'));
      expect(find.byType(LeaveProgrammeDialog), findsOneWidget);
    });

    testWidgets('SELL-CUS-047 a card-only viewer\'s sheet closes', (
      tester,
    ) async {
      final s = customersServer();
      grantOnly(s.server, ['loyalty.members.list', 'loyalty.members.delete']);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openSheet(h, nadaId);
      await h.tap(sheetText('Remove from loyalty programme'));
      await h.tap(button('Remove from programme'));
      await h.expectToast('Removed from the loyalty programme', keep: true);
      expect(find.byType(CustomerSheet), findsNothing);
      await h.flushTimers();
    });
  });

  group('wallet', () {
    testWidgets('SELL-CUS-048 the Google Wallet object from the card', (
      tester,
    ) async {
      final h = await pumpCustomers(tester, persona: Persona.platform);
      await openNada(h);
      await h.tap(sheetText('Google Wallet object'));
      expect(find.byType(GoogleObjectDialog), findsOneWidget);
      expect(
        find.text('What Google is holding for Nada Kamal.'),
        findsOneWidget,
      );
      expect(
        h.server.callsTo('/loyalty/members/{id}/google-object').single.path,
        '/loyalty/members/$nadaId/google-object',
      );
      expect(find.textContaining('accountName'), findsOneWidget);
      await h.tap(button('Send it again, and show me'));
      expect(
        h.server.callsTo('/loyalty/members/{id}/google-refresh').single.path,
        '/loyalty/members/$nadaId/google-refresh',
      );
      expect(find.text('loyaltyClass.patch'), findsOneWidget);
      expect(find.text('404'), findsOneWidget);
    });

    testWidgets('SELL-CUS-048 a failed read shows its words', (tester) async {
      final h = await pumpCustomers(tester, persona: Persona.platform);
      final bad = MockResponse.error(502, 'Google answered 500');
      h.server.fail(
        'GET',
        '/loyalty/members/{id}/google-object',
        bad,
        times: null,
      );
      await openNada(h);
      await h.tap(sheetText('Google Wallet object'));
      expect(find.text(h.refusalWords(bad)), findsOneWidget);
    });
  });
}
