// The transfer dialog (INV-TRF-025…037): new (send or request), edit and
// accept; sides, lines, stock checks, quick receive, the submit chain and
// its resume after a partial failure.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The text on the select [key]'s trigger.
Finder _shows(String key, String text) =>
    find.descendant(of: triggerIn(dialog, key), matching: find.text(text));

/// The options the open select lists.
List<String> _listed(WidgetTester tester) => [
  for (final e
      in find
          .descendant(
            of: find.byWidgetPredicate((w) => w is DashOptionList).last,
            matching: find.byType(Text),
          )
          .evaluate())
    (e.widget as Text).data ?? '',
];

Future<DashHarness> _open(
  WidgetTester tester, {
  MockServer? server,
  MockDb? db,
  Persona persona = Persona.owner,
  String? branch,
  bool all = false,
  DashSize size = DashSize.desktop,
}) async {
  final h = await pumpTransfers(
    tester,
    server: server,
    db: db,
    persona: persona,
    branch: all ? null : branch ?? SeedIds.zamalek,
    size: size,
  );
  await h.tap(inPage(byKey('transfers-new')));
  return h;
}

void main() {
  testWidgets('INV-TRF-025 new: "New transfer" with the send hint; From = '
      'here, To empty, one empty line, no note, nothing ticked', (
    tester,
  ) async {
    final h = await _open(tester);
    expect(inDialog(find.text('New transfer')), findsOneWidget);
    expect(
      inDialog(
        find.text(
          'Stock leaves when you send it, and lands when the other side '
          'receives it.',
        ),
      ),
      findsOneWidget,
    );
    expect(_shows('transfer-source', 'Zamalek'), findsOneWidget);
    expect(_shows('transfer-destination', '—'), findsOneWidget);
    expect(
      _shows('transfer-ingredient-0', 'Pick an ingredient'),
      findsOneWidget,
    );
    expect(inDialog(byKey('transfer-ingredient-1')), findsNothing);
    expect(button(tester, 'transfer-save-draft').onPressed, isNull);
    expect(button(tester, 'transfer-send').onPressed, isNull);
    // The dialog reads every location and the source's stock.
    expect(h.server.callsTo(locationsRoute), isNotEmpty);
    expect(
      h.server.callsTo(stockRoute).last.path,
      '/inventory/branches/${SeedIds.zamalek}/stock',
    );
  });

  testWidgets('INV-TRF-026 / INV-TRF-032 request mode: the ends swap, '
      '"Request stock", one "Send request" button', (tester) async {
    final h = await _open(tester);
    await pick(h, 'transfer-destination', 'Maadi');
    await h.tap(inDialog(find.text('Request stock')));
    expect(_shows('transfer-source', 'Maadi'), findsOneWidget);
    expect(_shows('transfer-destination', 'Zamalek'), findsOneWidget);
    expect(inDialog(find.text('Request stock')), findsNWidgets(2));
    expect(
      inDialog(
        find.text('The sending location reviews the request, then sends it.'),
      ),
      findsOneWidget,
    );
    expect(inDialog(byKey('transfer-save-draft')), findsNothing);
    expect(inDialog(byKey('transfer-send')), findsNothing);
    expect(inDialog(find.text('Send request')), findsOneWidget);
    // Back to sending swaps again.
    await h.tap(inDialog(find.text('Send stock')));
    expect(_shows('transfer-source', 'Zamalek'), findsOneWidget);
    expect(_shows('transfer-destination', 'Maadi'), findsOneWidget);
  });

  testWidgets('INV-TRF-027 your side lists where you work, the other side '
      'every location; the same twice says so', (tester) async {
    final h = await _open(tester, persona: Persona.manager);
    await h.tap(triggerIn(dialog, 'transfer-source'));
    expect(_listed(tester), ['Zamalek']);
    await h.tap(option('Zamalek').last);
    await h.tap(triggerIn(dialog, 'transfer-destination'));
    expect(_listed(tester), ['Heliopolis', 'Maadi', 'New Cairo', 'Zamalek']);
    await h.tap(option('Zamalek').last);
    expect(
      inDialog(find.text('Source and destination must differ')),
      findsOneWidget,
    );
  });

  testWidgets('INV-TRF-028 side check: no create at the source → "Request '
      'the stock instead"; in request mode no create at the destination → '
      '"only for a location you work at"', (tester) async {
    final s = transfersServer();
    holdAt(s.server, SeedIds.zamalek, {Cap.inventoryTransfersCreate});
    final h = await _open(tester, server: s.server, db: s.db);
    await pick(h, 'transfer-destination', 'Maadi');
    expect(
      inDialog(
        find.text(
          "You don't work at the sending location. Request the stock instead.",
        ),
      ),
      findsOneWidget,
    );
    await pickIngredient(h, 0, 'Vanilla Syrup');
    await h.enterText(inDialog(byKey('transfer-qty-0')), '10');
    expect(button(tester, 'transfer-save-draft').onPressed, isNull);
    // Asking FOR Zamalek (no create there): the request side check.
    await h.tap(inDialog(find.text('Request stock')));
    expect(_shows('transfer-destination', 'Zamalek'), findsOneWidget);
    expect(
      inDialog(
        find.text('You can only request stock for a location you work at.'),
      ),
      findsOneWidget,
    );
    expect(button(tester, 'transfer-save').onPressed, isNull);
  });

  testWidgets('INV-TRF-029 items: the source\'s stock on hand, with the '
      'figure; the on-hand line under a pick; red when asking for more', (
    tester,
  ) async {
    final h = await _open(tester);
    await h.tap(triggerIn(dialog, 'transfer-ingredient-0'));
    expect(_listed(tester), containsAll(['House Blend Beans', '5,680 g']));
    await h.enterText(
      find.byWidgetPredicate((w) => w is DashOptionList).last,
      'Vanilla',
    );
    expect(_listed(tester), containsAll(['Vanilla Syrup', '600 ml']));
    await h.tap(option('Vanilla Syrup').last);
    expect(inDialog(find.text('Zamalek on hand: 600 ml')), findsOneWidget);
    await pick(h, 'transfer-destination', 'Maadi');
    await h.enterText(inDialog(byKey('transfer-qty-0')), '600.0004');
    expect(button(tester, 'transfer-send').onPressed, isNotNull);
    await h.enterText(inDialog(byKey('transfer-qty-0')), '601');
    expect(button(tester, 'transfer-send').onPressed, isNull);
    expect(button(tester, 'transfer-save-draft').onPressed, isNotNull);
    final hint = tester.widget<Text>(inDialog(byKey('transfer-on-hand-0')));
    expect(
      hint.style!.color,
      isNot(
        equals(
          tester
              .widget<Text>(
                inDialog(
                  find.text(
                    'Stock leaves when you send it, and lands when the other side receives it.',
                  ),
                ),
              )
              .style
              ?.color,
        ),
      ),
    );
  });

  testWidgets('INV-TRF-029 lines: Add item, Remove (off with one line), a '
      'duplicate says so; Add item is off until From', (tester) async {
    final h = await _open(tester, all: true);
    expect(button(tester, 'transfer-add-line').onPressed, isNull);
    await pick(h, 'transfer-source', 'Zamalek');
    expect(
      tester
          .widget<DashIconButton>(inDialog(byKey('transfer-remove-0')))
          .onPressed,
      isNull,
    );
    await h.tap(inDialog(byKey('transfer-add-line')));
    expect(inDialog(byKey('transfer-ingredient-1')), findsOneWidget);
    await pickIngredient(h, 0, 'Vanilla Syrup');
    await pickIngredient(h, 1, 'Vanilla Syrup');
    expect(
      inDialog(find.text('Each item can appear only once.')),
      findsOneWidget,
    );
    await h.tap(inDialog(byKey('transfer-remove-1')));
    expect(
      inDialog(find.text('Each item can appear only once.')),
      findsNothing,
    );
    expect(inDialog(byKey('transfer-ingredient-1')), findsNothing);
  });

  testWidgets('INV-TRF-029 nothing on hand at the source: "Count it first"', (
    tester,
  ) async {
    final s = transfersServer();
    for (final r in s.db[InvTables.branchStock].where(
      (r) => r['branch_id'] == SeedIds.heliopolis,
    )) {
      r['on_hand'] = 0.0;
    }
    final h = await _open(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.heliopolis,
    );
    await h.tap(triggerIn(dialog, 'transfer-ingredient-0'));
    expect(
      find.text('This branch has nothing on hand to send. Count it first.'),
      findsOneWidget,
    );
  });

  testWidgets('INV-TRF-029 (divergence) a failed stock read shows the '
      'server\'s words and Retry, never "nothing on hand"', (tester) async {
    final s = transfersServer();
    final boom = MockResponse.error(500, 'Stock unavailable');
    s.server.fail('GET', stockRoute, boom, times: null);
    final h = await _open(tester, server: s.server, db: s.db);
    expect(inDialog(find.text(h.refusalWords(boom))), findsOneWidget);
    await h.tap(triggerIn(dialog, 'transfer-ingredient-0'));
    expect(
      find.text('This branch has nothing on hand to send. Count it first.'),
      findsNothing,
    );
  });

  testWidgets('INV-TRF-029 request mode picks from the catalog, hint = the '
      'unit', (tester) async {
    final h = await _open(tester);
    await h.tap(inDialog(find.text('Request stock')));
    await pick(h, 'transfer-source', 'Maadi');
    expect(h.server.callsTo(catalogRoute), isNotEmpty);
    await h.tap(triggerIn(dialog, 'transfer-ingredient-0'));
    expect(
      _listed(tester),
      containsAll(['Almond Milk', 'ml', 'Chai Spice Mix', 'g']),
    );
    await h.enterText(
      find.byWidgetPredicate((w) => w is DashOptionList).last,
      'Oat',
    );
    expect(_listed(tester), containsAll(['Oat Milk', 'ml']));
    await h.tap(option('Oat Milk').last);
    expect(inDialog(byKey('transfer-on-hand-0')), findsNothing);
  });

  testWidgets('INV-TRF-030 / INV-TRF-033 Save draft: creates with the lines '
      'and the trimmed note; "Draft saved"; the drawer opens on it', (
    tester,
  ) async {
    final h = await _open(tester);
    await pick(h, 'transfer-destination', 'Maadi');
    await pickIngredient(h, 0, 'Vanilla Syrup');
    await h.enterText(inDialog(byKey('transfer-qty-0')), '150');
    expect(inDialog(find.text('Note')), findsOneWidget);
    await h.enterText(inDialog(byKey('transfer-note-input')), '  For Friday ');
    await h.tap(inDialog(byKey('transfer-save-draft')));
    expect(h.server.callsTo(createRoute).single.body, {
      'destination_branch_id': SeedIds.maadi,
      'lines': [
        {
          'org_ingredient_id': InvIds.ingredient('vanilla-syrup'),
          'quantity': 150,
        },
      ],
      'note': 'For Friday',
      'request': false,
      'source_branch_id': SeedIds.zamalek,
    });
    await h.expectToast('Draft saved');
    expect(dialog, findsNothing);
    expect(inDrawer(find.text('TR-9')), findsOneWidget);
    expect(inDrawer(find.text('Draft')), findsWidgets);
  });

  testWidgets('INV-TRF-033 Send now: create then dispatch; "Transfer sent"', (
    tester,
  ) async {
    final s = transfersServer();
    final before = onHand(s.db, SeedIds.zamalek, 'vanilla-syrup');
    final h = await _open(tester, server: s.server, db: s.db);
    await pick(h, 'transfer-destination', 'Maadi');
    await pickIngredient(h, 0, 'Vanilla Syrup');
    await h.enterText(inDialog(byKey('transfer-qty-0')), '100');
    await h.tap(inDialog(byKey('transfer-send')));
    expect(h.server.callsTo(createRoute), hasLength(1));
    expect(h.server.callsTo(stepRoute('dispatch')), hasLength(1));
    expect(
      h.server.callsTo(createRoute).single.body,
      containsPair('note', null),
    );
    await h.expectToast('Transfer sent');
    expect(onHand(s.db, SeedIds.zamalek, 'vanilla-syrup'), before - 100);
    expect(inDrawer(find.text('In transit')), findsWidgets);
  });

  testWidgets('INV-TRF-031 / INV-TRF-033 working at both ends: "It\'s '
      'already there" turns the button into "Send and receive", which '
      'receives every line as sent', (tester) async {
    final s = transfersServer();
    final maadi = onHand(s.db, SeedIds.maadi, 'vanilla-syrup');
    final h = await _open(tester, server: s.server, db: s.db);
    await pick(h, 'transfer-destination', 'Maadi');
    await pickIngredient(h, 0, 'Vanilla Syrup');
    await h.enterText(inDialog(byKey('transfer-qty-0')), '100');
    expect(
      inDialog(find.text("It's already there: record it as received")),
      findsOneWidget,
    );
    expect(
      inDialog(
        find.text(
          'You work at both locations, so send and receive in one step.',
        ),
      ),
      findsOneWidget,
    );
    await h.tap(
      inDialog(find.text("It's already there: record it as received")),
    );
    expect(inDialog(find.text('Send and receive')), findsOneWidget);
    await h.tap(inDialog(byKey('transfer-send')));
    expect(h.server.callsTo(stepRoute('receive')), hasLength(1));
    await h.expectToast('Transfer received');
    expect(onHand(s.db, SeedIds.maadi, 'vanilla-syrup'), maadi + 100);
  });

  testWidgets('INV-TRF-031 no quick receive without edit at the destination, '
      'nor in request mode', (tester) async {
    final s = transfersServer();
    holdAt(s.server, SeedIds.maadi, {Cap.inventoryTransfersEdit});
    final h = await _open(tester, server: s.server, db: s.db);
    await pick(h, 'transfer-destination', 'Maadi');
    expect(inDialog(byKey('transfer-receive-now')), findsNothing);
    await pick(h, 'transfer-destination', 'Heliopolis');
    expect(inDialog(byKey('transfer-receive-now')), findsOneWidget);
    await h.tap(inDialog(find.text('Request stock')));
    expect(inDialog(byKey('transfer-receive-now')), findsNothing);
  });

  testWidgets('INV-TRF-033 a request: "Send request" makes it requested; '
      '"Request sent"', (tester) async {
    final h = await _open(tester, persona: Persona.manager);
    await h.tap(inDialog(find.text('Request stock')));
    await pick(h, 'transfer-source', 'Maadi');
    await pickIngredient(h, 0, 'Sugar');
    await h.enterText(inDialog(byKey('transfer-qty-0')), '2000');
    await h.tap(inDialog(byKey('transfer-save')));
    final body = h.server.callsTo(createRoute).single.body! as Map;
    expect(body['request'], true);
    expect(body['source_branch_id'], SeedIds.maadi);
    expect(body['destination_branch_id'], SeedIds.zamalek);
    await h.expectToast('Request sent');
    expect(inDrawer(find.text('Requested')), findsWidgets);
  });

  testWidgets('INV-TRF-034 a failed send after the draft was made: toast, '
      'the ends and the mode lock, the retry PATCHes then sends, never '
      'creating twice', (tester) async {
    final s = transfersServer();
    final h = await _open(tester, server: s.server, db: s.db);
    await pick(h, 'transfer-destination', 'Maadi');
    await pickIngredient(h, 0, 'Vanilla Syrup');
    await h.enterText(inDialog(byKey('transfer-qty-0')), '100');
    final boom = MockResponse.error(500, 'Dispatch failed');
    s.server.fail('POST', stepRoute('dispatch'), boom);
    final lists = h.server.callsTo(listRoute).length;
    await h.tap(inDialog(byKey('transfer-send')));
    await h.expectToast(h.refusalWords(boom));
    expect(dialog, findsOneWidget);
    expect(
      h.server.callsTo(listRoute).length,
      greaterThan(lists),
      reason: 'part of it went through',
    );
    expect(
      tester
          .widget<DashSegmentedControl<bool>>(inDialog(byKey('transfer-mode')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<DashSelect<String>>(inDialog(byKey('transfer-source')))
          .enabled,
      isFalse,
    );
    await h.enterText(inDialog(byKey('transfer-qty-0')), '90');
    await h.tap(inDialog(byKey('transfer-send')));
    expect(h.server.callsTo(createRoute), hasLength(1));
    expect(h.server.callsTo(itemRoute).single.method, 'PATCH');
    expect(h.server.callsTo(stepRoute('dispatch')), hasLength(2));
    await h.expectToast('Transfer sent');
  });

  testWidgets('INV-TRF-035 edit a request: locked ends, catalog lines, one '
      '"Save" → PATCH {lines, note} → "Request sent"', (tester) async {
    final h = await pumpTransfers(tester);
    await openRow(h, 'TR-6');
    await h.tap(inDrawer(byKey('transfer-step-edit')));
    expect(inDialog(find.text('Edit transfer')), findsOneWidget);
    expect(_shows('transfer-source', 'Maadi'), findsOneWidget);
    expect(
      tester
          .widget<DashSelect<String>>(inDialog(byKey('transfer-destination')))
          .enabled,
      isFalse,
    );
    expect(inDialog(byKey('transfer-mode')), findsNothing);
    expect(inDialog(byKey('transfer-save-draft')), findsNothing);
    expect(inDialog(find.text('Save')), findsOneWidget);
    expect(h.server.callsTo(catalogRoute), isNotEmpty);
    expect(
      _shows('transfer-ingredient-0', 'House Blend Beans'),
      findsOneWidget,
    );
    await h.enterText(inDialog(byKey('transfer-qty-1')), '1200');
    await h.tap(inDialog(byKey('transfer-save')));
    expect(h.server.callsTo(itemRoute).single.body, {
      'lines': [
        {
          'org_ingredient_id': InvIds.ingredient('house-blend'),
          'quantity': 1000,
        },
        {'org_ingredient_id': InvIds.ingredient('oat'), 'quantity': 1200},
      ],
      'note': 'Weekend rush: please send before Friday',
    });
    await h.expectToast('Request sent');
  });

  testWidgets('INV-TRF-036 accept: "Accept request" with its hint, no note; '
      'Send now accepts then dispatches', (tester) async {
    final h = await pumpTransfers(tester);
    await openRow(h, 'TR-6');
    await h.tap(inDrawer(byKey('transfer-step-accept')));
    expect(inDialog(find.text('Accept request')), findsOneWidget);
    expect(
      inDialog(
        find.text(
          'Change quantities to what you can send. It becomes your draft to '
          'pack and send.',
        ),
      ),
      findsOneWidget,
    );
    expect(inDialog(byKey('transfer-note-input')), findsNothing);
    expect(inDialog(byKey('transfer-receive-now')), findsOneWidget);
    await h.enterText(inDialog(byKey('transfer-qty-1')), '1000');
    await h.tap(inDialog(byKey('transfer-send')));
    expect(h.server.callsTo(stepRoute('accept')).single.body, {
      'lines': [
        {
          'org_ingredient_id': InvIds.ingredient('house-blend'),
          'quantity': 1000,
        },
        {'org_ingredient_id': InvIds.ingredient('oat'), 'quantity': 1000},
      ],
    });
    expect(h.server.callsTo(stepRoute('dispatch')), hasLength(1));
    await h.expectToast('Transfer sent');
  });

  testWidgets('INV-TRF-037 a server refusal toasts its words; the dialog '
      'stays open', (tester) async {
    final s = transfersServer();
    final h = await _open(tester, server: s.server, db: s.db);
    await pick(h, 'transfer-destination', 'Maadi');
    await pickIngredient(h, 0, 'Vanilla Syrup');
    await h.enterText(inDialog(byKey('transfer-qty-0')), '100');
    final refusal = MockResponse.badRequest(
      'Both locations must exist and belong to the same organization.',
    );
    s.server.fail('POST', createRoute, refusal);
    await h.tap(inDialog(byKey('transfer-save-draft')));
    await h.expectToast(h.refusalWords(refusal));
    expect(dialog, findsOneWidget);
    expect(button(tester, 'transfer-save-draft').loading, isFalse);
    final denied = MockResponse.denied('inventory.transfers.create');
    s.server.fail('POST', createRoute, denied);
    await h.tap(inDialog(byKey('transfer-save-draft')));
    await h.expectToast(h.refusalWords(denied));
  });

  testWidgets('INV-TRF-025 phone: the dialog is full screen', (tester) async {
    final h = await _open(tester, size: DashSize.phone);
    expect(dialog, findsOneWidget);
    expect(tester.getSize(dialog).width, closeTo(DashSize.phone.size.width, 1));
    await h.tap(inDialog(byKey('transfer-cancel')));
    expect(dialog, findsNothing);
  });
}
