// The transfer drawer (INV-TRF-009, INV-TRF-013…024, INV-TRF-041): header,
// lines, value, note, stamps, the steps per side and status, and the
// dispatch / receive / decline / cancel flows. Owner on All branches unless
// a test says otherwise.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The step buttons the drawer offers, in order.
List<String> _steps(WidgetTester tester) {
  final keys = [
    for (final e in inDrawer(
      find.byWidgetPredicate(
        (w) =>
            w is DashButton &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('transfer-step-'),
      ),
    ).evaluate())
      (
        tester.getCenter(find.byWidget(e.widget)).dx,
        (e.widget.key! as ValueKey<String>).value.substring(14),
      ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final k in keys) k.$2];
}

DashButton _step(WidgetTester tester, String key) =>
    tester.widget(inDrawer(byKey('transfer-step-$key')));

void main() {
  testWidgets('INV-TRF-013 header: the reference and its status pill; '
      'source → destination with the Warehouse glyph on a warehouse', (
    tester,
  ) async {
    final s = transfersServer();
    withWarehouse(s.db);
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    await openRow(h, 'TR-5');
    expect(inDrawer(find.text('TR-5')), findsOneWidget);
    expect(
      find.descendant(
        of: inDrawer(find.byType(DashStatusPill)),
        matching: find.text('Received'),
      ),
      findsOneWidget,
    );
    final route = inDrawer(byKey('transfer-drawer-route'));
    expect(
      find.descendant(of: route, matching: find.text('Maadi')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: route, matching: find.text('Zamalek')),
      findsOneWidget,
    );
    Finder glyph(String name) => find.descendant(
      of: route,
      matching: find.byWidgetPredicate((w) => w is DashIcon && w.name == name),
    );
    expect(glyph('warehouse'), findsNothing);
    expect(glyph('arrow-right'), findsOneWidget);
  });

  testWidgets('INV-TRF-014 requested lines read "Asked"; received ones add '
      '"Received" with the signed difference', (tester) async {
    final s = transfersServer();
    receiveShort(s.db);
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    await openRow(h, 'TR-6');
    expect(inDrawer(find.text('Asked')), findsOneWidget);
    expect(inDrawer(find.text('1,500 ml')), findsOneWidget);
    expect(inDrawer(find.text('1,000 g')), findsOneWidget);
    expect(inDrawer(find.text('Received')), findsNothing);
    await h.tap(find.byTooltip('Close').last);
    await openRow(h, 'TR-7');
    final lines = inDrawer(byKey('transfer-lines'));
    expect(
      find.descendant(of: lines, matching: find.text('Sent')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: lines, matching: find.text('Received')),
      findsOneWidget,
    );
    expect(inDrawer(find.text('10 pcs')), findsOneWidget);
    expect(inDrawer(find.text('8 pcs')), findsOneWidget);
    final f = h.container.read(formatProvider);
    expect(inDrawer(find.text(f.fmtNumber(-2))), findsOneWidget);
    expect(inDrawer(find.text('Two crushed in the van')), findsOneWidget);
    // Vanilla arrived as sent: no difference under it.
    expect(inDrawer(find.text('300 ml')), findsNWidgets(2));
  });

  testWidgets('INV-TRF-015 received short: "Lost in transit" at the line '
      'cost; over: "More arrived than was sent"', (tester) async {
    final s = transfersServer();
    final t = receiveShort(s.db);
    final cost =
        ((t['lines']! as List).cast<MockRow>().firstWhere(
                  (l) => l['ingredient_name'] == 'Croissant Dough',
                )['unit_cost']!
                as num)
            .toDouble();
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    final f = h.container.read(formatProvider);
    await openRow(h, 'TR-7');
    expect(
      inDrawer(find.text('Lost in transit: ${f.fmtMoney(2 * cost)}')),
      findsOneWidget,
    );
    // Over by 1 croissant instead.
    final croissant = (t['lines']! as List).cast<MockRow>().firstWhere(
      (l) => l['ingredient_name'] == 'Croissant Dough',
    );
    croissant['qty_received'] = 11.0;
    await h.tap(find.byTooltip('Close').last);
    h.container.read(realtimeBusProvider).invalidate(const ['/inventory']);
    await h.settle();
    await openRow(h, 'TR-7');
    expect(
      inDrawer(find.text('More arrived than was sent: ${f.fmtMoney(cost)}')),
      findsOneWidget,
    );
    // Exact (TR-5): no value line.
    await h.tap(find.byTooltip('Close').last);
    await openRow(h, 'TR-5');
    expect(inDrawer(byKey('transfer-transit-value')), findsNothing);
  });

  testWidgets('INV-TRF-016 the note, line breaks kept, only when present', (
    tester,
  ) async {
    final s = transfersServer();
    doc(s.db, 't6')['note'] = 'Weekend rush\nPlease before Friday';
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    await openRow(h, 'TR-6');
    expect(inDrawer(find.text('Note')), findsOneWidget);
    expect(
      inDrawer(find.text('Weekend rush\nPlease before Friday')),
      findsOneWidget,
    );
    await h.tap(find.byTooltip('Close').last);
    await openRow(h, 'TR-7');
    expect(inDrawer(byKey('transfer-note')), findsNothing);
  });

  testWidgets('INV-TRF-017 stamps: Requested or Created, Sent, Received, '
      'Cancelled, each "<name> · <date-time>"', (tester) async {
    final h = await pumpTransfers(tester);
    final f = h.container.read(formatProvider);
    await openRow(h, 'TR-6');
    expect(
      find.descendant(
        of: inDrawer(byKey('transfer-stamp-requested')),
        matching: find.text(
          '\u2068Karim Adel\u2069 · ${f.fmtDateTime(DateTime.utc(2026, 10, 7, 9, 10))}',
        ),
      ),
      findsOneWidget,
    );
    expect(inDrawer(byKey('transfer-stamp-created')), findsNothing);
    await h.tap(find.byTooltip('Close').last);
    await openRow(h, 'TR-5');
    final at =
        '\u2068Tarek Saber\u2069 · ${f.fmtDateTime(DateTime.utc(2026, 10, 6, 8, 30))}';
    for (final (key, label) in [
      ('created', 'Created'),
      ('sent', 'Sent'),
      ('received', 'Received'),
    ]) {
      final row = inDrawer(byKey('transfer-stamp-$key'));
      expect(
        find.descendant(of: row, matching: find.text(label)),
        findsOneWidget,
      );
      expect(find.descendant(of: row, matching: find.text(at)), findsOneWidget);
    }
    expect(inDrawer(byKey('transfer-stamp-cancelled')), findsNothing);
    await h.tap(find.byTooltip('Close').last);
    await openRow(h, 'TR-8');
    expect(
      find.descendant(
        of: inDrawer(byKey('transfer-stamp-cancelled')),
        matching: find.text(
          '\u2068Dina Fouad\u2069 · ${f.fmtDateTime(DateTime.utc(2026, 10, 2, 13, 20))}',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('INV-TRF-017 (ar) (divergence) a stamp isolates the Latin '
      'name, so the Arabic date never joins its run', (tester) async {
    final h = await pumpTransfers(tester, locale: 'ar');
    final f = h.container.read(formatProvider);
    await openRow(h, 'TR-6');
    final at = f.fmtDateTime(DateTime.utc(2026, 10, 7, 9, 10));
    expect(
      find.descendant(
        of: inDrawer(byKey('transfer-stamp-requested')),
        matching: find.text('\u2068Karim Adel\u2069 · $at'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('INV-TRF-018 the steps by status for someone at both sides: '
      'requested, draft, in transit, received', (tester) async {
    final s = transfersServer();
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    await openRow(h, 'TR-6');
    expect(_steps(tester), ['cancel', 'decline', 'edit', 'accept']);
    expect(inDrawer(find.text('Withdraw')), findsOneWidget);
    await h.tap(find.byTooltip('Close').last);
    await openRow(h, 'TR-7');
    expect(_steps(tester), ['cancel', 'edit', 'dispatch']);
    expect(inDrawer(find.text('Cancel transfer')), findsOneWidget);
    expect(inDrawer(find.text('Send now')), findsOneWidget);
    await h.tap(find.byTooltip('Close').last);
    await openRow(h, 'TR-5');
    expect(_steps(tester), isEmpty);
    expect(inDrawer(find.byType(DashButton)), findsNothing);
  });

  testWidgets('INV-TRF-018 in transit: Cancel transfer and Receive', (
    tester,
  ) async {
    final s = transfersServer();
    dispatchDraft(s.db);
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    await openRow(h, 'TR-7');
    expect(_steps(tester), ['cancel', 'receive']);
  });

  testWidgets('INV-TRF-018 / INV-TRF-041 manager at Zamalek, the request\'s '
      'destination: Withdraw and Edit only', (tester) async {
    final h = await pumpTransfers(
      tester,
      persona: Persona.manager,
      branch: SeedIds.zamalek,
    );
    await openRow(h, 'TR-6');
    expect(_steps(tester), ['cancel', 'edit']);
    await h.tap(find.byTooltip('Close').last);
    // TR-5 (received) and TR-3: nothing to do.
    await openRow(h, 'TR-3');
    expect(_steps(tester), isEmpty);
  });

  testWidgets('INV-TRF-041 a step needs its cap AT its side: without create '
      'at Maadi, no Accept or Decline on TR-6', (tester) async {
    final s = transfersServer();
    holdAt(s.server, SeedIds.maadi, {Cap.inventoryTransfersCreate});
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    await openRow(h, 'TR-6');
    expect(_steps(tester), ['cancel', 'edit']);
    expect(
      h.server
          .callsTo(authzRoute)
          .map((c) => c.query['branch_id']?.single)
          .toSet(),
      containsAll([SeedIds.maadi, SeedIds.zamalek]),
    );
  });

  testWidgets('INV-TRF-041 the authz-at reads hold nothing until they '
      'answer: no button flashes', (tester) async {
    final s = transfersServer();
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    final gate = s.server.hold('GET', authzRoute);
    await openRow(h, 'TR-7');
    expect(_steps(tester), isEmpty);
    gate.release();
    await h.settle();
    expect(_steps(tester), ['cancel', 'edit', 'dispatch']);
  });

  testWidgets('INV-TRF-019 Send now: confirm, dispatch, invalidate, toast, '
      'the drawer shows it in transit', (tester) async {
    final s = transfersServer();
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    await openRow(h, 'TR-7');
    await h.tap(inDrawer(byKey('transfer-step-dispatch')));
    expect(find.text('Send TR-7?'), findsOneWidget);
    expect(
      find.text(
        "The stock leaves Maadi now and is in transit until it's received.",
      ),
      findsOneWidget,
    );
    final lists = h.server.callsTo(listRoute).length;
    await h.tap(find.text('Send now').last);
    expect(
      h.server.callsTo(stepRoute('dispatch')).single.path,
      '/inventory/transfers/${doc(s.db, 't7')['id']}/dispatch',
    );
    await h.expectToast('Transfer sent');
    expect(h.server.callsTo(listRoute).length, greaterThan(lists));
    expect(
      find.descendant(
        of: inDrawer(find.byType(DashStatusPill)),
        matching: find.text('In transit'),
      ),
      findsOneWidget,
    );
    expect(_steps(tester), ['cancel', 'receive']);
  });

  testWidgets('INV-TRF-019 Send now refused: 409 TRANSFER_INSUFFICIENT_STOCK '
      'toasts its words; the drawer stays', (tester) async {
    final s = transfersServer();
    stockRow(s.db, SeedIds.maadi, 'croissant')!['on_hand'] = 4.0;
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    await openRow(h, 'TR-7');
    await h.tap(inDrawer(byKey('transfer-step-dispatch')));
    await h.tap(find.text('Send now').last);
    await h.expectToast(
      h.refusalWords(
        MockResponse.conflict(
          'Not enough stock to send: Croissant Dough (4.000 on hand).',
          code: 'TRANSFER_INSUFFICIENT_STOCK',
        ),
      ),
    );
    expect(drawer, findsOneWidget);
    expect(_steps(tester), ['cancel', 'edit', 'dispatch']);
  });

  testWidgets('INV-TRF-009 the drawer stays open after a step moves the '
      'transfer out of the current tab', (tester) async {
    final h = await pumpTransfers(tester);
    await h.tap(inPage(find.text('Draft')));
    await openRow(h, 'TR-7');
    await h.tap(inDrawer(byKey('transfer-step-dispatch')));
    await h.tap(find.text('Send now').last);
    await h.expectToast('Transfer sent');
    expect(drawer, findsOneWidget);
    expect(inDrawer(find.text('TR-7')), findsOneWidget);
    expect(
      find.descendant(
        of: inDrawer(find.byType(DashStatusPill)),
        matching: find.text('In transit'),
      ),
      findsOneWidget,
    );
    expect(inTable(find.text('TR-7')), findsNothing);
  });

  testWidgets('INV-TRF-020 Edit opens the dialog in edit mode; its result '
      'replaces the drawer\'s transfer', (tester) async {
    final h = await pumpTransfers(tester);
    await openRow(h, 'TR-7');
    await h.tap(inDrawer(byKey('transfer-step-edit')));
    expect(inDialog(find.text('Edit transfer')), findsOneWidget);
    await h.enterText(inDialog(byKey('transfer-qty-0')), '6');
    await h.tap(inDialog(byKey('transfer-save')));
    await h.expectToast('Draft saved');
    expect(inDrawer(find.text('6 pcs')), findsOneWidget);
  });

  testWidgets('INV-TRF-020 Accept opens accept mode; Save draft makes it the '
      'source\'s draft', (tester) async {
    final h = await pumpTransfers(tester);
    await openRow(h, 'TR-6');
    await h.tap(inDrawer(byKey('transfer-step-accept')));
    expect(inDialog(find.text('Accept request')), findsOneWidget);
    await h.tap(inDialog(byKey('transfer-save-draft')));
    expect(h.server.callsTo(stepRoute('accept')), hasLength(1));
    await h.expectToast('Draft saved');
    expect(
      find.descendant(
        of: inDrawer(find.byType(DashStatusPill)),
        matching: find.text('Draft'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('INV-TRF-021 Receive: a card per line prefilled with what was '
      'sent; short shows "Short by" and an optional note; over needs one', (
    tester,
  ) async {
    final s = transfersServer();
    final t = dispatchDraft(s.db);
    final lines = (t['lines']! as List).cast<MockRow>();
    final cro =
        lines.firstWhere(
              (l) => l['ingredient_name'] == 'Croissant Dough',
            )['id']!
            as String;
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    await openRow(h, 'TR-7');
    await h.tap(inDrawer(byKey('transfer-step-receive')));
    expect(inReceive(find.text('Receive TR-7')), findsOneWidget);
    expect(
      inReceive(
        find.text(
          'Count what arrived. Anything short is recorded as lost in transit.',
        ),
      ),
      findsOneWidget,
    );
    expect(inReceive(find.text('Sent 10 pcs')), findsOneWidget);
    expect(inReceive(find.text('Sent 300 ml')), findsOneWidget);
    expect(
      find.descendant(
        of: inReceive(byKey('receive-qty-$cro')),
        matching: find.text('10'),
      ),
      findsOneWidget,
    );
    DashButton submit() => tester.widget(inReceive(byKey('receive-submit')));
    expect(submit().onPressed, isNotNull);
    await h.enterText(inReceive(byKey('receive-qty-$cro')), '7.5');
    expect(inReceive(find.text('Short by 2.5')), findsOneWidget);
    expect(inReceive(find.text('What happened? (optional)')), findsOneWidget);
    expect(submit().onPressed, isNotNull);
    await h.enterText(inReceive(byKey('receive-qty-$cro')), '10.001');
    expect(
      inReceive(find.text('Why did more arrive? (required)')),
      findsOneWidget,
    );
    expect(submit().onPressed, isNull);
    await h.enterText(inReceive(byKey('receive-note-$cro')), 'Baker added one');
    expect(submit().onPressed, isNotNull);
    await h.enterText(inReceive(byKey('receive-qty-$cro')), '10.0004');
    expect(
      inReceive(byKey('receive-note-$cro')),
      findsNothing,
      reason: 'the same in thousandths',
    );
    // Not a number: Receive is off.
    await h.enterText(inReceive(byKey('receive-qty-$cro')), '');
    expect(submit().onPressed, isNull);
    await h.tap(inReceive(byKey('receive-cancel')));
    expect(receiveDialog, findsNothing);
    expect(h.server.callsTo(stepRoute('receive')), isEmpty);
  });

  testWidgets('INV-TRF-022 Receive: sends every line, toasts, the drawer '
      'shows it received; the server\'s refusal toasts and keeps the dialog', (
    tester,
  ) async {
    final s = transfersServer();
    final t = dispatchDraft(s.db);
    final cro =
        (t['lines']! as List).cast<MockRow>().firstWhere(
              (l) => l['ingredient_name'] == 'Croissant Dough',
            )['id']!
            as String;
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    await openRow(h, 'TR-7');
    await h.tap(inDrawer(byKey('transfer-step-receive')));
    // B6: worded by its code, at 409 (the server now) or 400 (before).
    for (final status in [409, 400]) {
      s.server.fail(
        'POST',
        stepRoute('receive'),
        MockResponse.error(
          status,
          'More Croissant Dough arrived than was sent. Add a note saying why.',
          code: 'OVER_RECEIVE_NEEDS_NOTE',
        ),
      );
      await h.tap(inReceive(byKey('receive-submit')));
      await h.expectToast('More arrived than was sent. Add a note saying why.');
      expect(receiveDialog, findsOneWidget);
    }
    await h.enterText(inReceive(byKey('receive-qty-$cro')), '9');
    await h.enterText(inReceive(byKey('receive-note-$cro')), ' One fell ');
    await h.tap(inReceive(byKey('receive-submit')));
    final body = h.server.callsTo(stepRoute('receive')).last.body! as Map;
    final sent = (body['lines']! as List).cast<Map>();
    expect(sent, hasLength(2));
    expect(sent.firstWhere((l) => l['line_id'] == cro), {
      'line_id': cro,
      'qty_received': 9,
      'note': 'One fell',
    });
    expect(sent.firstWhere((l) => l['line_id'] != cro)['note'], isNull);
    await h.expectToast('Transfer received');
    expect(receiveDialog, findsNothing);
    expect(
      find.descendant(
        of: inDrawer(find.byType(DashStatusPill)),
        matching: find.text('Received'),
      ),
      findsOneWidget,
    );
    expect(onHand(s.db, SeedIds.heliopolis, 'croissant'), greaterThan(0));
  });

  testWidgets('INV-TRF-023 Decline: "{{to}} sees your reason."; the reason '
      'is required; "Request declined"', (tester) async {
    final h = await pumpTransfers(tester);
    await openRow(h, 'TR-6');
    await h.tap(inDrawer(byKey('transfer-step-decline')));
    expect(inClose(find.text('Decline TR-6?')), findsOneWidget);
    expect(inClose(find.text('Zamalek sees your reason.')), findsOneWidget);
    expect(inClose(find.text('Reason')), findsOneWidget);
    DashButton submit() =>
        tester.widget(inClose(byKey('transfer-close-submit')));
    expect(submit().onPressed, isNull);
    expect(submit().variant, DashButtonVariant.destructive);
    await h.enterText(inClose(byKey('transfer-close-reason')), '  ');
    expect(submit().onPressed, isNull);
    await h.enterText(
      inClose(byKey('transfer-close-reason')),
      ' We are short too ',
    );
    await h.tap(inClose(byKey('transfer-close-submit')));
    expect(h.server.callsTo(stepRoute('decline')).single.body, {
      'note': 'We are short too',
    });
    await h.expectToast('Request declined');
    expect(closeDialog, findsNothing);
    expect(
      find.descendant(
        of: inDrawer(find.byType(DashStatusPill)),
        matching: find.text('Cancelled'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('INV-TRF-023 Withdraw (a request) and Cancel (a draft): '
      '"Nothing has moved yet."; the reason optional, sent as null', (
    tester,
  ) async {
    final h = await pumpTransfers(tester);
    await openRow(h, 'TR-6');
    await h.tap(inDrawer(byKey('transfer-step-cancel')));
    expect(inClose(find.text('Cancel TR-6?')), findsOneWidget);
    expect(inClose(find.text('Nothing has moved yet.')), findsOneWidget);
    expect(inClose(find.text('(Optional)')), findsOneWidget);
    await h.tap(inClose(byKey('transfer-close-back')));
    expect(closeDialog, findsNothing);
    await h.tap(find.byTooltip('Close').last);
    await openRow(h, 'TR-7');
    await h.tap(inDrawer(byKey('transfer-step-cancel')));
    await h.tap(inClose(byKey('transfer-close-submit')));
    expect(h.server.callsTo(stepRoute('cancel')).single.body, {'note': null});
    await h.expectToast('Transfer cancelled');
  });

  testWidgets('INV-TRF-023 Cancel in transit: the stock goes back on hand at '
      'the source', (tester) async {
    final s = transfersServer();
    final before = onHand(s.db, SeedIds.maadi, 'croissant');
    dispatchDraft(s.db);
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    await openRow(h, 'TR-7');
    await h.tap(inDrawer(byKey('transfer-step-cancel')));
    expect(
      inClose(find.text('The stock goes back on hand at Maadi.')),
      findsOneWidget,
    );
    await h.tap(inClose(byKey('transfer-close-submit')));
    await h.expectToast('Transfer cancelled');
    expect(onHand(s.db, SeedIds.maadi, 'croissant'), before);
  });

  testWidgets('INV-TRF-024 a stale refusal (TRANSFER_CHANGED) toasts its '
      'words and refreshes inventory; the dialog stays', (tester) async {
    final s = transfersServer();
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    await openRow(h, 'TR-7');
    await h.tap(inDrawer(byKey('transfer-step-cancel')));
    final stale = MockResponse.conflict(
      'Someone else just changed this transfer. Reload it and try again.',
      code: 'TRANSFER_CHANGED',
    );
    s.server.fail('POST', stepRoute('cancel'), stale);
    final lists = h.server.callsTo(listRoute).length;
    await h.tap(inClose(byKey('transfer-close-submit')));
    await h.expectToast(h.refusalWords(stale));
    expect(closeDialog, findsOneWidget);
    expect(h.server.callsTo(listRoute).length, greaterThan(lists));
  });

  testWidgets('INV-TRF-024 a plain refusal toasts and refreshes nothing', (
    tester,
  ) async {
    final s = transfersServer();
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    await openRow(h, 'TR-7');
    await h.tap(inDrawer(byKey('transfer-step-dispatch')));
    final boom = MockResponse.error(500, 'Database unavailable');
    s.server.fail('POST', stepRoute('dispatch'), boom);
    final lists = h.server.callsTo(listRoute).length;
    await h.tap(find.text('Send now').last);
    await h.expectToast(h.refusalWords(boom));
    expect(h.server.callsTo(listRoute), hasLength(lists));
    expect(_step(tester, 'dispatch').loading, isFalse);
  });

  testWidgets('INV-TRF-018 buttons are off while a step runs', (tester) async {
    final s = transfersServer();
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    await openRow(h, 'TR-7');
    final gate = s.server.hold('POST', stepRoute('dispatch'));
    await h.tap(inDrawer(byKey('transfer-step-dispatch')));
    await h.tap(find.text('Send now').last);
    expect(_step(tester, 'cancel').onPressed, isNull);
    expect(_step(tester, 'edit').onPressed, isNull);
    expect(_step(tester, 'dispatch').loading, isTrue);
    gate.release();
    await h.settle();
    await h.expectToast('Transfer sent');
    expect(_step(tester, 'receive').onPressed, isNotNull);
  });
}
