// The New transfer dialog (INV-TRF-012…022, -028), driven from the
// Transfers page through the real shell on the seeded mock server.
//
// Zamalek holds 600 ml Vanilla Syrup, 120 Paper Cups, 80 g Matcha; its Oat
// Milk is below zero and its Croissant Dough at 0 (neither can travel).
// Heliopolis has never counted anything.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<DashHarness> _open(
  WidgetTester tester, {
  ({MockServer server, MockDb db})? s,
  String? branch,
}) async {
  final h = await pumpTransfers(
    tester,
    server: s?.server,
    db: s?.db,
    branch: branch ?? SeedIds.zamalek,
  );
  await h.tap(inPage(byKey('transfers-new')));
  expect(dialog, findsOneWidget);
  return h;
}

/// The trigger's shown text.
Finder _shows(String key, String text) =>
    find.descendant(of: trigger(key), matching: find.text(text));

/// Fills a valid transfer: Zamalek → Maadi, 250 ml Vanilla Syrup.
Future<void> _fill(DashHarness h, {String qty = '250'}) async {
  await pick(h, 'transfer-destination', 'Maadi');
  await pickIngredient(h, 'Vanilla Syrup');
  await h.enterText(inDialog(byKey('transfer-quantity')), qty);
}

void main() {
  testWidgets('INV-TRF-012 opens as "New transfer" / "Transfers" with From = '
      'the picked branch and the rest blank; reopening resets it', (
    tester,
  ) async {
    final h = await _open(tester);
    expect(inDialog(find.text('New transfer')), findsWidgets);
    expect(inDialog(find.text('Transfers')), findsOneWidget);
    expect(_shows('transfer-source', 'Zamalek'), findsOneWidget);
    expect(_shows('transfer-destination', '—'), findsOneWidget);
    expect(_shows('transfer-ingredient', 'Pick an ingredient'), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
    await _fill(h);
    await h.enterText(inDialog(byKey('transfer-note')), 'For the weekend');
    await h.tap(inDialog(byKey('transfer-cancel')));
    expect(dialog, findsNothing);
    await h.tap(inPage(byKey('transfers-new')));
    expect(_shows('transfer-destination', '—'), findsOneWidget);
    expect(_shows('transfer-ingredient', 'Pick an ingredient'), findsOneWidget);
    expect(inDialog(find.text('For the weekend')), findsNothing);
    expect(inDialog(find.text('250')), findsNothing);
  });

  testWidgets('INV-TRF-013 changing From clears the ingredient and reads the '
      'new source\'s stock', (tester) async {
    final h = await _open(tester);
    await pickIngredient(h, 'Vanilla Syrup');
    expect(_shows('transfer-ingredient', 'Vanilla Syrup'), findsOneWidget);
    await pick(h, 'transfer-source', 'Maadi');
    expect(_shows('transfer-ingredient', 'Pick an ingredient'), findsOneWidget);
    expect(
      h.server.callsTo(stockRoute).last.path,
      '/inventory/branches/${SeedIds.maadi}/stock',
    );
  });

  testWidgets('INV-TRF-014 / INV-TRF-026 both selects offer every ACTIVE '
      'branch (the source too); the arrow sits between them', (tester) async {
    final s = transfersServer();
    s.db['branches'].find(SeedIds.heliopolis)!['is_active'] = false;
    final h = await _open(tester, s: s);
    await h.tap(trigger('transfer-destination'));
    for (final b in ['Maadi', 'New Cairo', 'Zamalek']) {
      expect(option(b), findsOneWidget, reason: b);
    }
    expect(option('Heliopolis'), findsNothing);
    await h.tap(option('Maadi'));
    expect(
      inDialog(
        find.byWidgetPredicate((w) => w is DashIcon && w.name == 'arrow-right'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('INV-TRF-015 the same branch twice: "Source and destination '
      'must differ", New transfer off', (tester) async {
    final h = await _open(tester);
    await pickIngredient(h, 'Vanilla Syrup');
    await h.enterText(inDialog(byKey('transfer-quantity')), '10');
    await pick(h, 'transfer-destination', 'Zamalek');
    expect(
      inDialog(find.text('Source and destination must differ')),
      findsOneWidget,
    );
    expect(submitButton(tester).onPressed, isNull);
    await pick(h, 'transfer-destination', 'Maadi');
    expect(inDialog(byKey('transfer-same-branch')), findsNothing);
    expect(submitButton(tester).onPressed, isNotNull);
  });

  testWidgets('INV-TRF-016 the picker lists only what the source holds, with '
      'its quantity, searchable by category', (tester) async {
    final h = await _open(tester);
    expect(
      tester
          .widget<DashSelectField<String>>(inDialog(byKey('transfer-ingredient')))
          .enabled,
      isTrue,
    );
    await h.tap(trigger('transfer-ingredient'));
    final list = find.byWidgetPredicate((w) => w is DashOptionList).last;
    await h.enterText(list, 'Vanilla');
    expect(option('Vanilla Syrup'), findsOneWidget);
    expect(option('600 ml'), findsOneWidget);
    await h.enterText(list, 'Oat');
    expect(option('Oat Milk'), findsNothing, reason: 'below zero');
    await h.enterText(list, 'Croissant');
    expect(option('Croissant Dough'), findsNothing, reason: 'none on hand');
    await h.enterText(list, 'Syrups & Sauces');
    expect(option('Vanilla Syrup'), findsOneWidget);
    expect(option('Paper Cup 12oz'), findsNothing);
  });

  testWidgets('INV-TRF-016 a source with nothing on hand: "This branch has '
      'nothing on hand to send. Count it first."', (tester) async {
    final h = await _open(tester);
    await pick(h, 'transfer-source', 'Heliopolis');
    await h.tap(trigger('transfer-ingredient'));
    expect(
      find.text('This branch has nothing on hand to send. Count it first.'),
      findsOneWidget,
    );
  });

  testWidgets('INV-TRF-017 under the picker: "Zamalek on hand: 600 ml"', (
    tester,
  ) async {
    final h = await _open(tester);
    await pickIngredient(h, 'Vanilla Syrup');
    expect(inDialog(find.text('Zamalek on hand: 600 ml')), findsOneWidget);
  });

  testWidgets('INV-TRF-018 more than on hand: "More than on hand", New '
      'transfer off', (tester) async {
    final h = await _open(tester);
    await _fill(h, qty: '600.5');
    expect(inDialog(find.text('More than on hand')), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
    await h.enterText(inDialog(byKey('transfer-quantity')), '600');
    expect(inDialog(byKey('transfer-exceeds')), findsNothing);
    expect(submitButton(tester).onPressed, isNotNull);
    await h.enterText(inDialog(byKey('transfer-quantity')), '0');
    expect(submitButton(tester).onPressed, isNull, reason: 'not above 0');
  });

  testWidgets('INV-TRF-019 / INV-TRF-020 New transfer posts the body (note '
      'trimmed), invalidates inventory, toasts, closes; the row and the '
      'stock follow', (tester) async {
    final s = transfersServer();
    final h = await _open(tester, s: s);
    expect(inDialog(find.text('(Optional)')), findsOneWidget);
    await _fill(h, qty: '250.5');
    await h.enterText(inDialog(byKey('transfer-note')), '  Maadi is out  ');
    final lists = h.server.callsTo(listRoute).length;
    await h.tap(inDialog(byKey('transfer-submit')));
    final call = h.server.callsTo(createRoute, method: 'POST').single;
    expect(call.body, {
      'destination_branch_id': SeedIds.maadi,
      'note': 'Maadi is out',
      'org_ingredient_id': InvIds.ingredient('vanilla-syrup'),
      'quantity': 250.5,
      'source_branch_id': SeedIds.zamalek,
    });
    await h.expectToast('Transfer recorded');
    expect(dialog, findsNothing);
    expect(h.server.callsTo(listRoute).length, lists + 1);
    expect(inTable(find.text('250.5 ml')), findsOneWidget);
    // Hers beside the seed's Vanilla Syrup transfer by the same person.
    expect(inTable(find.text('Nour El-Sayed')), findsNWidgets(2));
    expect(
      (stockRow(s.db, SeedIds.zamalek, 'vanilla-syrup')!['on_hand']! as num),
      349.5,
    );
  });

  testWidgets('INV-TRF-019 a blank note is sent as null', (tester) async {
    final h = await _open(tester);
    await _fill(h);
    await h.enterText(inDialog(byKey('transfer-note')), '   ');
    await h.tap(inDialog(byKey('transfer-submit')));
    final body =
        h.server.callsTo(createRoute, method: 'POST').single.body!
            as Map<String, Object?>;
    expect(body.containsKey('note'), isTrue);
    expect(body['note'], isNull);
    await h.expectToast('Transfer recorded');
  });

  testWidgets('INV-TRF-021 a refusal toasts the server\'s words; the dialog '
      'stays open with its input', (tester) async {
    final s = transfersServer();
    final h = await _open(tester, s: s);
    await _fill(h);
    // Another till sold most of it meanwhile.
    setOnHand(s.db, SeedIds.zamalek, 'vanilla-syrup', 100);
    await h.tap(inDialog(byKey('transfer-submit')));
    await h.expectToast(
      h.refusalWords(
        MockResponse.badRequest(
          'Only 100.000 on hand at the source branch — cannot transfer '
          '250.000.',
        ),
      ),
    );
    expect(dialog, findsOneWidget);
    expect(inDialog(find.text('250')), findsOneWidget);
    expect(submitButton(tester).loading, isFalse);
  });

  testWidgets('INV-TRF-021 manager refused at another source branch', (
    tester,
  ) async {
    final h = await pumpTransfers(
      tester,
      persona: Persona.manager,
      branch: SeedIds.zamalek,
    );
    await h.tap(inPage(byKey('transfers-new')));
    final denied = MockResponse.denied('inventory.transfers.create');
    h.server.fail('POST', createRoute, denied);
    await _fill(h);
    await h.tap(inDialog(byKey('transfer-submit')));
    await h.expectToast(h.refusalWords(denied));
    expect(dialog, findsOneWidget);
  });

  testWidgets('INV-TRF-022 Cancel and Esc close without a request', (
    tester,
  ) async {
    final h = await _open(tester);
    await h.tap(inDialog(byKey('transfer-cancel')));
    expect(dialog, findsNothing);
    await h.tap(inPage(byKey('transfers-new')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(dialog, findsNothing);
    expect(h.server.callsTo(createRoute, method: 'POST'), isEmpty);
  });

  testWidgets('INV-TRF-028 changing the destination keeps the ingredient', (
    tester,
  ) async {
    final h = await _open(tester);
    await pickIngredient(h, 'Vanilla Syrup');
    await pick(h, 'transfer-destination', 'Maadi');
    await pick(h, 'transfer-destination', 'New Cairo');
    expect(_shows('transfer-ingredient', 'Vanilla Syrup'), findsOneWidget);
  });

  testWidgets('INV-TRF-028 (divergence) while the source stock loads the '
      'picker says "Loading…", never "No results found"', (tester) async {
    final s = transfersServer();
    final h = await _open(tester, s: s);
    final gate = s.server.hold('GET', stockRoute);
    await pick(h, 'transfer-source', 'Maadi');
    await h.tap(trigger('transfer-ingredient'));
    expect(find.text('Loading…'), findsOneWidget);
    expect(find.text('No results found'), findsNothing);
    gate.release();
    await h.settle();
  });

  testWidgets('INV-TRF-028 (divergence) a failed source stock read shows the '
      'server\'s words + Retry, never "nothing on hand"', (tester) async {
    final s = transfersServer();
    final boom = MockResponse.error(500, 'Stock unavailable');
    s.server.fail('GET', stockRoute, boom, times: null);
    final h = await _open(tester, s: s);
    expect(inDialog(find.text(h.refusalWords(boom))), findsOneWidget);
    await h.tap(trigger('transfer-ingredient'));
    expect(
      find.text('This branch has nothing on hand to send. Count it first.'),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    s.server.clearFailures();
    final n = h.server.callsTo(stockRoute).length;
    await h.tap(inDialog(byKey('transfer-stock-retry')));
    expect(h.server.callsTo(stockRoute).length, n + 1);
    expect(inDialog(byKey('transfer-stock-retry')), findsNothing);
    await pickIngredient(h, 'Vanilla Syrup');
    expect(inDialog(find.text('Zamalek on hand: 600 ml')), findsOneWidget);
  });
}
