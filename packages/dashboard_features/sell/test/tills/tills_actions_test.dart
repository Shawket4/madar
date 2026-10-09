// Tills (SELL-TIL rows): the row menu, force close, delete, and the open /
// cash movement / close dialogs, with each persona's refusals.
import 'package:dashboard_api/dashboard_api.dart' show DashboardApi;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/tills/cash_movement_dialog.dart';
import 'package:dashboard_sell/src/tills/close_till_dialog.dart';
import 'package:dashboard_sell/src/tills/open_till_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tills_support.dart';

String get _helio => SeedIds.heliopolis;

const _menuWords = [
  'View report',
  'Cash Movement',
  'Close till',
  'Force close',
  'Delete',
];

/// Makes Ali's open Heliopolis till (its orders and all) the owner's.
void ownHelioMorning(MockDb db) {
  db['tills'].get(TillIds.helioMorning)
    ..['teller_id'] = SeedIds.owner
    ..['teller_name'] = 'Nour El-Sayed';
}

/// The branch's last declared close (`suggested_opening_cash`).
int lastDeclared(MockDb db, String branchId) {
  final closed =
      db['tills'].rows
          .where(
            (t) =>
                t['branch_id'] == branchId &&
                t['status'] != 'open' &&
                t['closing_cash_declared'] != null,
          )
          .toList()
        ..sort(
          (a, b) =>
              (b['opened_at']! as String).compareTo(a['opened_at']! as String),
        );
  return closed.first['closing_cash_declared']! as int;
}

DashButton _button(WidgetTester tester, String label) =>
    tester.widget<DashButton>(
      find.ancestor(
        of: inSurface(find.text(label)).last,
        matching: find.byType(DashButton),
      ),
    );

void main() {
  group('row menu', () {
    testWidgets('SELL-TIL-023 my open till: View report, Cash movement, Close '
        'till, Force close, Delete', (tester) async {
      final s = tillsServer();
      ownHelioMorning(s.db);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openRowMenu(h, TillIds.helioMorning);
      expect(menuLabels(h, _menuWords), _menuWords);
      await pickMenu(h, 'View report');
      expect(h.location.queryParameters['report'], TillIds.helioMorning);
    });

    testWidgets('SELL-TIL-023/063 someone else\'s open till: no cash or '
        'close', (tester) async {
      final h = await pumpTills(tester);
      await openRowMenu(h, TillIds.helioSecond);
      expect(menuLabels(h, _menuWords), [
        'View report',
        'Force close',
        'Delete',
      ]);
    });

    testWidgets('SELL-TIL-023/063 a closed till: View report and Delete', (
      tester,
    ) async {
      final h = await pumpTills(tester);
      await openRowMenu(h, TillIds.seeded('heliopolis', 1, 'evening'));
      expect(menuLabels(h, _menuWords), ['View report', 'Delete']);
    });

    testWidgets('SELL-TIL-063 with All branches my open till offers no cash '
        'movement or close (my till is not read)', (tester) async {
      final s = tillsServer();
      ownHelioMorning(s.db);
      final h = await pumpTills(
        tester,
        allBranches: true,
        server: s.server,
        db: s.db,
      );
      await openRowMenu(h, TillIds.helioMorning);
      expect(menuLabels(h, _menuWords), [
        'View report',
        'Force close',
        'Delete',
      ]);
    });

    testWidgets('SELL-TIL-029 manager (till.force_close, no till.delete): '
        'Force close but no Delete', (tester) async {
      final h = await pumpTills(
        tester,
        persona: Persona.manager,
        branchId: SeedIds.zamalek,
      );
      await openRowMenu(h, TillIds.zamalekMorning);
      expect(menuLabels(h, _menuWords), ['View report', 'Force close']);
    });

    testWidgets('SELL-TIL-029 limited (neither cap) on her own open till: '
        'View report, Cash movement, Close till only', (tester) async {
      final h = await pumpTills(
        tester,
        persona: Persona.limited,
        branchId: SeedIds.maadi,
      );
      await openRowMenu(h, TillIds.maadiMorning);
      expect(menuLabels(h, _menuWords), [
        'View report',
        'Cash Movement',
        'Close till',
      ]);
    });
  });

  group('force close and delete', () {
    testWidgets('SELL-TIL-027 Force close: confirm → {reason: null} → toast, '
        'the list and reports refetch', (tester) async {
      final h = await pumpTills(tester);
      final lists = h.server.callsTo(tillsList).length;
      await openRowMenu(h, TillIds.helioSecond);
      await pickMenu(h, 'Force close');
      final dialog = find.byType(DashConfirmDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(
            "Closes the till without a cash count. Use only when a teller "
            "can't close it on their device.",
          ),
        ),
        findsOneWidget,
      );
      await confirm(h, 'Force close');
      final call = h.server
          .callsTo('/tills/{tillId}/force-close', method: 'POST')
          .single;
      expect(call.path, '/tills/${TillIds.helioSecond}/force-close');
      expect(call.body, {'reason': null});
      await h.expectToast('Till force-closed');
      expect(h.server.callsTo(tillsList).length, lists + 1);
      final badges = find.byKey(ValueKey('till-badges-${TillIds.helioSecond}'));
      expect(
        find.descendant(of: badges, matching: find.text('Force Closed')),
        findsOneWidget,
      );
    });

    testWidgets('SELL-TIL-027 Force close refused: the server words', (
      tester,
    ) async {
      final s = tillsServer();
      s.server.fail(
        'POST',
        '/tills/{tillId}/force-close',
        MockResponse.denied('till.force_close'),
      );
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openRowMenu(h, TillIds.helioSecond);
      await pickMenu(h, 'Force close');
      await confirm(h, 'Force close');
      await h.expectToast("You don't have permission to perform this action.");
    });

    testWidgets('SELL-TIL-028 Delete: confirm "Delete till" → DELETE → toast, '
        'the row is gone', (tester) async {
      final h = await pumpTills(tester, branchId: SeedIds.newCairo);
      final empty = TillIds.emptyTill;
      await openRowMenu(h, empty);
      await pickMenu(h, 'Delete');
      final dialog = find.byType(DashConfirmDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('Delete till')),
        findsOneWidget,
      );
      final opened = h.container
          .read(formatProvider)
          .fmtDateTime(h.db!['tills'].get(empty)['opened_at']);
      expect(
        find.descendant(of: dialog, matching: find.text('Delete "$opened"?')),
        findsOneWidget,
      );
      await confirm(h, 'Delete');
      expect(
        h.server.callsTo('/tills/{tillId}', method: 'DELETE').single.path,
        '/tills/$empty',
      );
      await h.expectToast('Till deleted');
      expect(find.byKey(ValueKey('till-badges-$empty')), findsNothing);
    });

    testWidgets('SELL-TIL-028 Delete refused (a till with sales): the '
        'server sentence', (tester) async {
      final h = await pumpTills(tester);
      final id = TillIds.seeded('heliopolis', 1, 'evening');
      await openRowMenu(h, id);
      await pickMenu(h, 'Delete');
      await confirm(h, 'Delete');
      await h.expectToast(
        'Cannot delete a till that has recorded (non-voided) orders — its '
        'sales are part of the financial record.',
      );
      expect(find.byKey(ValueKey('till-badges-$id')), findsOneWidget);
    });
  });

  group('open till', () {
    testWidgets('SELL-TIL-030/031/032/033 Open till: the suggested float, '
        'blank disables, submit opens it, the button goes', (tester) async {
      final s = tillsServer();
      final suggested = lastDeclared(s.db, _helio);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await h.tap(inPage(find.text('Open till')));
      expect(find.byType(OpenTillDialog), findsOneWidget);
      expect(inSurface(find.text('Open Till')), findsWidgets);
      expect(
        inSurface(
          find.text('Declare the opening drawer float to start a till.'),
        ),
        findsOneWidget,
      );
      expect(inSurface(find.text('Opening Cash')), findsOneWidget);
      final fmt = h.container.read(formatProvider);
      expect(
        inSurface(find.text('Suggested: ${fmt.fmtMoney(suggested)}')),
        findsOneWidget,
      );
      final field = find.byKey(const ValueKey('opening-cash'));
      final text = h.tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(text.controller.text, Strings.jsString(suggested / 100));
      // Blank: no submit.
      await h.enterText(field, '');
      expect(_button(tester, 'Open Till').onPressed, isNull);
      await h.enterText(field, '-5');
      expect(_button(tester, 'Open Till').onPressed, isNull);
      await h.enterText(field, Strings.jsString(suggested / 100));
      await h.tap(inSurface(find.text('Open Till')).last);
      final post = h.server
          .callsTo('/tills/branches/{branchId}/open', method: 'POST')
          .single;
      expect(post.path, '/tills/branches/$_helio/open');
      expect(post.body, {'opening_cash': suggested});
      await h.expectToast('Till opened');
      expect(find.byType(OpenTillDialog), findsNothing);
      // My till is open here now: no button, and it is listed.
      expect(inPage(find.text('Open till')), findsNothing);
      expect(inKey('open-now', find.text('Nour El-Sayed')), findsOneWidget);
    });

    testWidgets('SELL-TIL-033 Cancel closes without a request', (tester) async {
      final h = await pumpTills(tester);
      await h.tap(inPage(find.text('Open till')));
      await h.tap(inSurface(find.text('Cancel')));
      expect(find.byType(OpenTillDialog), findsNothing);
      expect(
        h.server.callsTo('/tills/branches/{branchId}/open', method: 'POST'),
        isEmpty,
      );
    });

    testWidgets('SELL-TIL-033 limited without till.open: the refusal '
        'words, the dialog stays open', (tester) async {
      final s = tillsServer(persona: Persona.limited);
      // Her till is someone else's here, so the button shows.
      s.db['tills'].get(TillIds.maadiMorning)['teller_id'] = SeedIds.user(
        'ali',
      );
      final h = await pumpTills(
        tester,
        persona: Persona.limited,
        branchId: SeedIds.maadi,
        server: s.server,
        db: s.db,
      );
      await h.tap(inPage(find.text('Open till')));
      await h.tap(inSurface(find.text('Open Till')).last);
      expect(
        h.server
            .callsTo('/tills/branches/{branchId}/open', method: 'POST')
            .single
            .status,
        403,
      );
      await h.expectToast("You don't have permission to perform this action.");
      expect(find.byType(OpenTillDialog), findsOneWidget);
    });

    testWidgets('SELL-TIL-033 already open at another branch: the server '
        'sentence (409)', (tester) async {
      final s = tillsServer();
      s.db['tills'].get(TillIds.maadiMorning)
        ..['teller_id'] = SeedIds.owner
        ..['teller_name'] = 'Nour El-Sayed';
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await h.tap(inPage(find.text('Open till')));
      await h.tap(inSurface(find.text('Open Till')).last);
      await h.expectToast(
        'You already have an open till at another branch. Close it before '
        'opening a new one.',
      );
      expect(find.byType(OpenTillDialog), findsOneWidget);
    });
  });

  testWidgets('SELL-TIL-031 opened before my till is known: blank, then '
      'filled with the suggestion when the read lands', (tester) async {
    final s = tillsServer();
    final suggested = lastDeclared(s.db, _helio);
    final current = s.server.hold('GET', tillsCurrent);
    final h = await pumpTills(tester, server: s.server, db: s.db);
    await h.tap(inPage(find.text('Open till')));
    final field = find.byKey(const ValueKey('opening-cash'));
    String text() => h.tester
        .widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .controller
        .text;
    expect(text(), '');
    expect(inSurface(find.textContaining('Suggested')), findsNothing);
    current.release();
    await h.settle();
    expect(text(), Strings.jsString(suggested / 100));
    final fmt = h.container.read(formatProvider);
    expect(
      inSurface(find.text('Suggested: ${fmt.fmtMoney(suggested)}')),
      findsOneWidget,
    );
  });

  testWidgets('SELL-TIL-033/037 (web) Enter in the float or the amount does '
      'not submit', (tester) async {
    final s = tillsServer();
    ownHelioMorning(s.db);
    final h = await pumpTills(tester, server: s.server, db: s.db);
    await openRowMenu(h, TillIds.helioMorning);
    await pickMenu(h, 'Cash Movement');
    await h.enterText(find.byKey(const ValueKey('cash-amount')), '20');
    await h.enterText(find.byKey(const ValueKey('cash-note')), 'Change');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    expect(
      h.server.callsTo('/tills/{tillId}/cash-movements', method: 'POST'),
      isEmpty,
    );
  });

  testWidgets('SELL-TIL-033 (web) Enter in Opening Cash does not submit', (
    tester,
  ) async {
    final h = await pumpTills(tester);
    await h.tap(inPage(find.text('Open till')));
    await h.tap(find.byKey(const ValueKey('opening-cash')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    expect(
      h.server.callsTo('/tills/branches/{branchId}/open', method: 'POST'),
      isEmpty,
    );
  });

  testWidgets('SELL-TIL-043 Enter in "Cash counted in drawer" submits', (
    tester,
  ) async {
    final s = tillsServer();
    ownHelioMorning(s.db);
    final h = await pumpTills(tester, server: s.server, db: s.db);
    await openRowMenu(h, TillIds.helioMorning);
    await pickMenu(h, 'Close till');
    await h.enterText(find.byKey(const ValueKey('closing-cash')), '1000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    expect(
      h.server.callsTo('/tills/{tillId}/close', method: 'POST').single.path,
      '/tills/${TillIds.helioMorning}/close',
    );
    await h.expectToast('Till closed');
  });

  group('cash movement', () {
    testWidgets('SELL-TIL-034/035/036/037 Cash movement: Cash in by default, '
        'amount and note required, Cash out sends a negative amount', (
      tester,
    ) async {
      final s = tillsServer();
      ownHelioMorning(s.db);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      final lists = h.server.callsTo(tillsList).length;
      await openRowMenu(h, TillIds.helioMorning);
      await pickMenu(h, 'Cash Movement');
      expect(find.byType(CashMovementDialog), findsOneWidget);
      expect(
        inSurface(
          find.text('Record cash paid into or taken out of the drawer.'),
        ),
        findsOneWidget,
      );
      DirectionButton dir(String label) => tester.widget<DirectionButton>(
        find.ancestor(
          of: inSurface(find.text(label)),
          matching: find.byType(DirectionButton),
        ),
      );
      expect(dir('Cash in').pressed, isTrue);
      expect(dir('Cash out').pressed, isFalse);
      expect(inSurface(find.text('Reason for this movement')), findsOneWidget);
      expect(_button(tester, 'Save').onPressed, isNull);
      await h.tap(inSurface(find.text('Cash out')));
      expect(dir('Cash out').pressed, isTrue);
      await h.enterText(find.byKey(const ValueKey('cash-amount')), '50');
      expect(_button(tester, 'Save').onPressed, isNull);
      await h.enterText(find.byKey(const ValueKey('cash-note')), '  Bank run ');
      await h.tap(inSurface(find.text('Save')));
      final post = h.server
          .callsTo('/tills/{tillId}/cash-movements', method: 'POST')
          .single;
      expect(post.path, '/tills/${TillIds.helioMorning}/cash-movements');
      expect(post.body, {'amount': -5000, 'note': 'Bank run'});
      await h.expectToast('Cash movement recorded');
      expect(find.byType(CashMovementDialog), findsNothing);
      expect(h.server.callsTo(tillsList).length, lists + 1);
    });

    testWidgets('SELL-TIL-037 a refused movement toasts and stays open', (
      tester,
    ) async {
      final s = tillsServer();
      ownHelioMorning(s.db);
      s.server.fail(
        'POST',
        '/tills/{tillId}/cash-movements',
        MockResponse.denied('till.operate'),
      );
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openRowMenu(h, TillIds.helioMorning);
      await pickMenu(h, 'Cash Movement');
      await h.enterText(find.byKey(const ValueKey('cash-amount')), '20');
      await h.enterText(find.byKey(const ValueKey('cash-note')), 'Change');
      await h.tap(inSurface(find.text('Save')));
      await h.expectToast("You don't have permission to perform this action.");
      expect(find.byType(CashMovementDialog), findsOneWidget);
    });
  });

  group('close till', () {
    testWidgets('SELL-TIL-038 Close till: a skeleton until the preview loads', (
      tester,
    ) async {
      final s = tillsServer();
      ownHelioMorning(s.db);
      final gate = s.server.hold('GET', tillClosePreview);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openRowMenu(h, TillIds.helioMorning);
      await pickMenu(h, 'Close till');
      expect(
        find.byKey(const ValueKey('close-preview-loading')),
        findsOneWidget,
      );
      expect(
        inSurface(find.text('Count the drawer and check each payment method.')),
        findsOneWidget,
      );
      gate.release();
      await h.settle();
      expect(find.byKey(const ValueKey('closing-cash')), findsOneWidget);
    });

    testWidgets('SELL-TIL-039/040/041/042/043 Close till: the count, the '
        'note, the payment check (a mismatch needs an amount and a note)', (
      tester,
    ) async {
      final s = tillsServer();
      ownHelioMorning(s.db);
      // The server's own preview, to check the form against.
      final preview = (await tester.runAsync(
        () => DashboardApi(
          s.server,
        ).tills.closePreview(tillId: TillIds.helioMorning),
      ))!;
      final h = await pumpTills(tester, server: s.server, db: s.db);
      final fmt = h.container.read(formatProvider);
      await openRowMenu(h, TillIds.helioMorning);
      await pickMenu(h, 'Close till');
      final dialog = find.byType(CloseTillDialog);
      expect(
        inSurface(
          find.text('Expected cash: ${fmt.fmtMoney(preview.expectedCash)}'),
        ),
        findsOneWidget,
      );
      // No count: the cash error, no request.
      await h.tap(find.byKey(const ValueKey('close-till-submit')));
      expect(inSurface(find.text('Enter the counted cash.')), findsOneWidget);
      expect(
        h.server.callsTo('/tills/{tillId}/close', method: 'POST'),
        isEmpty,
      );
      // The payment check lists each non-cash method, Checked by default.
      final rows = find.descendant(
        of: dialog,
        matching: find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('reconcile-row-'),
        ),
      );
      expect(rows, findsWidgets);
      final methodKey =
          (tester.widget(rows.first).key! as ValueKey<String>).value;
      final method = methodKey.substring('reconcile-row-'.length);
      expect(inSurface(find.text('Payment check')), findsOneWidget);
      final nonCash = [
        for (final m in preview.methods)
          if (!m.isCash) m,
      ];
      expect(rows, findsNWidgets(nonCash.length));
      expect(method, nonCash.first.method);
      expect(
        find.descendant(
          of: rows.first,
          matching: find.text(h.t('payments.${nonCash.first.method}')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rows.first,
          matching: find.text(
            'System total: ${fmt.fmtMoney(nonCash.first.systemTotal)}',
          ),
        ),
        findsOneWidget,
      );
      await h.tap(
        find.descendant(of: rows.first, matching: find.text("Doesn't match")),
      );
      expect(inSurface(find.text('Amount you see')), findsWidgets);
      await h.enterText(find.byKey(const ValueKey('closing-cash')), '1000');
      await h.enterText(
        find.byKey(const ValueKey('close-note')),
        ' Counted twice ',
      );
      await h.tap(find.byKey(const ValueKey('close-till-submit')));
      expect(
        inSurface(find.text('Add the amount and a note for the difference.')),
        findsOneWidget,
      );
      await h.enterText(
        find.byKey(ValueKey('reconcile-amount-$method')),
        '120.5',
      );
      await h.enterText(
        find.byKey(ValueKey('reconcile-note-$method')),
        'One slip missing',
      );
      await h.tap(find.byKey(const ValueKey('close-till-submit')));
      final post = h.server
          .callsTo('/tills/{tillId}/close', method: 'POST')
          .single;
      expect(post.path, '/tills/${TillIds.helioMorning}/close');
      final body = post.body! as Map<String, Object?>;
      expect(body['closing_cash_declared'], 100000);
      expect(body['cash_note'], 'Counted twice');
      final rec = (body['reconciliation']! as List)
          .cast<Map<String, Object?>>();
      expect(rec.first, {
        'method': method,
        'status': 'disagreed',
        'declared_amount': 12050,
        'note': 'One slip missing',
      });
      for (final r in rec.skip(1)) {
        expect(r['status'], 'checked');
      }
      await h.expectToast('Till closed');
      expect(dialog, findsNothing);
      // The other till is still open: no last-till warning.
      expect(find.byType(LastTillWarningDialog), findsNothing);
    });

    testWidgets('SELL-TIL-043 a blank note is sent as null; Cancel closes', (
      tester,
    ) async {
      final s = tillsServer();
      ownHelioMorning(s.db);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openRowMenu(h, TillIds.helioMorning);
      await pickMenu(h, 'Close till');
      await h.tap(inSurface(find.text('Cancel')));
      expect(find.byType(CloseTillDialog), findsNothing);
      await openRowMenu(h, TillIds.helioMorning);
      await pickMenu(h, 'Close till');
      await h.enterText(find.byKey(const ValueKey('closing-cash')), '0');
      await h.tap(find.byKey(const ValueKey('close-till-submit')));
      final body =
          h.server.callsTo('/tills/{tillId}/close', method: 'POST').single.body!
              as Map<String, Object?>;
      expect(body.containsKey('cash_note'), isTrue);
      expect(body['cash_note'], isNull);
      await h.flushTimers();
    });

    testWidgets('SELL-TIL-044 closing the last open till with bills open: '
        'the warning, then OK', (tester) async {
      final s = tillsServer();
      ownHelioMorning(s.db);
      closeOthers(s.db, _helio, TillIds.helioMorning);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openRowMenu(h, TillIds.helioMorning);
      await pickMenu(h, 'Close till');
      await h.enterText(find.byKey(const ValueKey('closing-cash')), '1000');
      await h.tap(find.byKey(const ValueKey('close-till-submit')));
      await h.expectToast('Till closed', keep: true);
      final warning = find.byType(LastTillWarningDialog);
      expect(warning, findsOneWidget);
      expect(
        find.descendant(
          of: warning,
          matching: find.text('That was the last open till'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: warning,
          matching: find.textContaining('(EGP 820.00) are still open'),
        ),
        findsOneWidget,
      );
      // Like the web's, it has a close X as well as OK.
      expect(
        find.descendant(of: warning, matching: find.bySemanticsLabel('Close')),
        findsOneWidget,
      );
      await h.tap(find.descendant(of: warning, matching: find.text('OK')));
      expect(warning, findsNothing);
      await h.flushTimers();
    });

    testWidgets('SELL-TIL-061 (divergence) a refused close preview shows the '
        'refusal and Retry, not an endless skeleton', (tester) async {
      // Hana (limited) holds her own open till at Maadi but not till.operate.
      final h = await pumpTills(
        tester,
        persona: Persona.limited,
        branchId: SeedIds.maadi,
      );
      await openRowMenu(h, TillIds.maadiMorning);
      await pickMenu(h, 'Close till');
      expect(find.byKey(const ValueKey('close-preview-loading')), findsNothing);
      expect(
        inSurface(
          find.text("You don't have permission to perform this action."),
        ),
        findsOneWidget,
      );
      expect(inSurface(find.text('Retry')), findsOneWidget);
    });

    testWidgets('SELL-TIL-061 (divergence) a refetched preview keeps what was '
        'typed', (tester) async {
      final s = tillsServer();
      ownHelioMorning(s.db);
      final h = await pumpTills(tester, server: s.server, db: s.db);
      await openRowMenu(h, TillIds.helioMorning);
      await pickMenu(h, 'Close till');
      await h.enterText(find.byKey(const ValueKey('closing-cash')), '777');
      final before = h.server.callsTo(tillClosePreview).length;
      h.realtime.current!.emit('till.cash_moved', data: '{}');
      await h.settle();
      expect(h.server.callsTo(tillClosePreview).length, before + 1);
      final text = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('closing-cash')),
          matching: find.byType(EditableText),
        ),
      );
      expect(text.controller.text, '777');
    });
  });

  testWidgets('SELL-TIL-030 limited persona with an open till here: no Open '
      'till; the bills notice is refused (no tickets.read), so its KPIs read '
      'zero and no line shows', (tester) async {
    final h = await pumpTills(
      tester,
      persona: Persona.limited,
      branchId: SeedIds.maadi,
    );
    expect(inPage(find.text('Open till')), findsNothing);
    expect(h.server.callsTo(tillsNotice).single.status, 403);
    expect(find.byKey(const ValueKey('open-bills-notice')), findsNothing);
    expect(find.byKey(const ValueKey('tills-kpis')), findsOneWidget);
  });

  testWidgets('SELL-ALL-002 dawamOnly: the module gate, no tills read', (
    tester,
  ) async {
    final h = await pumpTills(
      tester,
      persona: Persona.dawamOnly,
      allBranches: true,
    );
    expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
    expect(tillsPage, findsNothing);
    expect(h.server.callsTo(tillsList), isEmpty);
  });
}
