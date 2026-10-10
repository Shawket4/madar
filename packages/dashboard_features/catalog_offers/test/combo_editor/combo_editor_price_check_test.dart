// The combo editor's live price check, driven through the real shell: the
// figures the seed's combos give (hand-computed in the area's rules test),
// the warnings, when it asks and with what, and its loading and failed
// states.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_catalog_offers/src/combo_editor/combo_editor_providers.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _econ = '/combos/economics';

Finder get _panel => labelled('Price check').first;

Finder _inPanel(String text) =>
    find.descendant(of: _panel, matching: find.text(text));

void main() {
  testWidgets('OFFR-CED-060/065/066 Morning Croissant: prices at the '
      'organisation, every figure, the margin warning that never blocks', (
    tester,
  ) async {
    await pumpEditor(tester, path: comboPath('morning-croissant'));
    expect(_inPanel('Price check'), findsOneWidget);
    expect(_inPanel('Prices at organisation prices'), findsOneWidget);
    for (final (label, value) in [
      ('Combo price', 'EGP 165.00'),
      ('Bought separately', 'EGP 190.00'),
      ('Customer saves', 'EGP 25.00'),
      ('Cost (default picks)', 'EGP 64.00'),
      ('Margin (default picks)', '61.2%'),
      ('Margin (costliest picks)', '47.9%'),
      ('Your minimum', '55%'),
    ]) {
      expect(_inPanel(label), findsOneWidget, reason: label);
      expect(_inPanel(value), findsOneWidget, reason: value);
    }
    expect(_inPanel('EGP 135.00 to EGP 240.00'), findsOneWidget);
    expect(_inPanel('Up to EGP 86.00'), findsOneWidget);
    expect(
      find.descendant(
        of: labelled('Warnings'),
        matching: find.text('Margin 47.9% is below your minimum 55%.'),
      ),
      findsOneWidget,
    );
    expect(_inPanel('Warnings never stop you saving.'), findsOneWidget);
  });

  testWidgets('OFFR-CED-065/066 Brunch for Two: two items with no cost, so '
      'the cost is unknown and the margins are dashes', (tester) async {
    await pumpEditor(tester, path: comboPath('brunch-for-two'));
    expect(_inPanel('Unknown'), findsOneWidget);
    expect(_inPanel('—'), findsNWidgets(2));
    expect(
      _inPanel(
        'Halloumi Sandwich has no known cost, so the margin is incomplete.',
      ),
      findsOneWidget,
    );
    expect(
      _inPanel('Avocado Toast has no known cost, so the margin is incomplete.'),
      findsOneWidget,
    );
  });

  testWidgets('OFFR-CED-066 no warnings', (tester) async {
    await pumpEditor(tester, path: comboPath('coffee-cookie'));
    expect(_inPanel('No warnings.'), findsOneWidget);
  });

  testWidgets('OFFR-CED-066 a switched-off choice, an empty slot, and a code '
      'the page does not know', (tester) async {
    final s = editorServer();
    s.db
            .table(OffersTables.menuItems)
            .find(OffersSeed.item('americano'))!['is_active'] =
        false;
    final h = await pumpEditor(
      tester,
      path: comboPath('coffee-cookie'),
      server: s.server,
      db: s.db,
    );
    expect(
      _inPanel("Americano is switched off, so it can't be picked."),
      findsOneWidget,
    );
    expect(
      _inPanel('Coffee has no choice that can be sold right now.'),
      findsOneWidget,
    );

    s.server.fail(
      'POST',
      _econ,
      MockResponse.ok({
        'branch_id': null,
        'price': 12500,
        'list_default': 14000,
        'list_min': 14000,
        'list_max': 14000,
        'cost_default': null,
        'cost_max': null,
        'margin_default': null,
        'margin_worst': null,
        'min_margin': null,
        'saving_default': 1500,
        'warnings': [
          {'code': 'COMBO_SOMETHING_NEW', 'vars': <String, Object?>{}},
          {
            'code': 'COST_UNKNOWN',
            'vars': {'menu_item_id': mockUuid('gone')},
          },
          {
            'code': 'SLOT_EMPTY_NOW',
            'vars': {'slot_id': mockUuid('gone-slot')},
          },
        ],
      }),
    );
    await typeInto(h, 'Combo price', '125');
    expect(_inPanel('Check this combo (COMBO_SOMETHING_NEW).'), findsOneWidget);
    expect(
      _inPanel('An item has no known cost, so the margin is incomplete.'),
      findsOneWidget,
    );
    expect(
      _inPanel('A slot has no choice that can be sold right now.'),
      findsOneWidget,
    );
    expect(_inPanel('Not set'), findsOneWidget);
  });

  testWidgets('OFFR-CED-061/062 nothing is asked until there is a price and '
      'a slot with a choice; then the form\'s body, once per body, 450 ms '
      'after typing stops', (tester) async {
    final h = await pumpEditor(tester);
    expect(
      _inPanel(
        'Enter a price and at least one slot with a choice to see the figures.',
      ),
      findsOneWidget,
    );
    await typeInto(h, 'Combo price', '150');
    await choose(h, 'Choose an item', 'Butter Croissant', search: 'Butter');
    expect(h.server.callsTo(_econ), hasLength(1));
    final body = (h.server.callsTo(_econ).single.body! as Map)
        .cast<String, Object?>();
    expect(body['price'], 15000);
    expect(body['name'], '—');
    expect(body['branch_id'], isNull);
    final slot = (body['slots']! as List).single as Map;
    expect(slot['name'], '—');
    expect(
      ((slot['choices']! as List).single as Map)['menu_item_id'],
      OffersSeed.item('croissant'),
    );
    // Butter Croissant alone for EGP 150: no saving.
    expect(
      _inPanel('Customers save nothing versus ordering separately.'),
      findsOneWidget,
    );

    // Typing does not ask until the form settles.
    await h.enterText(labelled('Combo price'), '60');
    expect(h.server.callsTo(_econ), hasLength(1));
    await debounce(h);
    expect(h.server.callsTo(_econ), hasLength(2));
    expect((h.server.callsTo(_econ).last.body! as Map)['price'], 6000);

    // The same body again is answered from the cache.
    await typeInto(h, 'Combo price', '150');
    expect(h.server.callsTo(_econ), hasLength(2));
    expect(_inPanel('EGP 150.00'), findsOneWidget);
  });

  testWidgets('OFFR-CED-062 (divergence) an opened combo is asked at once, '
      'not after the debounce', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [catalogOffersArea],
      path: comboPath('coffee-cookie'),
    );
    expect(h.server.callsTo(_econ), hasLength(1));
    expect(_inPanel('No warnings.'), findsOneWidget);
  });

  testWidgets('OFFR-CED-066 (divergence) a warning about a slot with a blank '
      'name reads "A slot"', (tester) async {
    final s = editorServer();
    s.db
            .table(OffersTables.menuItems)
            .find(OffersSeed.item('americano'))!['is_active'] =
        false;
    final h = await pumpEditor(
      tester,
      path: comboPath('coffee-cookie'),
      server: s.server,
      db: s.db,
    );
    await typeInto(h, 'Slot name', '');
    expect(
      _inPanel('A slot has no choice that can be sold right now.'),
      findsOneWidget,
    );
  });

  testWidgets('OFFR-CED-062 the price check is never retried (the combo '
      'itself is, once, under the app\'s retry policy)', (tester) async {
    Future<int> asks(String template, ProviderListenable<Object?> read) async {
      final s = editorServer();
      s.server.fail(
        'POST',
        _econ,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      s.server.fail(
        'GET',
        template,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final c = ProviderContainer(
        retry: webRetry,
        overrides: [
          transportProvider.overrideWithValue(s.server),
          orgIdProvider.overrideWithValue(SeedIds.sabahOrg),
        ],
      );
      final sub = c.listen(read, (_, _) {});
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      sub.close();
      c.dispose();
      return s.server.callsTo(template).length;
    }

    final body = comboEconomicsKey({
      'name': '—',
      'price': 15000,
      'slots': <Object?>[],
    }, null);
    expect(await asks(_econ, comboEconomicsProvider(body)), 1);
    expect(
      await asks(
        '/combos/{id}',
        comboProvider(OffersSeed.comboId('coffee-cookie')),
      ),
      2,
    );
  });

  testWidgets('OFFR-CED-063 loading: five skeleton lines', (tester) async {
    final s = editorServer();
    final gate = s.server.hold('POST', _econ);
    final h = await pumpEditor(
      tester,
      path: comboPath('coffee-cookie'),
      server: s.server,
      db: s.db,
    );
    expect(
      find.descendant(of: _panel, matching: find.byType(DashSkeleton)),
      findsNWidgets(5),
    );
    gate.release();
    await h.settle();
    expect(_inPanel('No warnings.'), findsOneWidget);
  });

  testWidgets('OFFR-CED-064 failed: unavailable with the server\'s words, '
      'and Save still works', (tester) async {
    final s = editorServer();
    final refusal = MockResponse.error(503, 'Costing is being rebuilt');
    s.server.fail('POST', _econ, refusal, times: null);
    final h = await pumpEditor(
      tester,
      path: comboPath('coffee-cookie'),
      server: s.server,
      db: s.db,
    );
    expect(
      _inPanel('The price check is unavailable right now. You can still save.'),
      findsOneWidget,
    );
    expect(_inPanel(h.refusalWords(refusal)), findsOneWidget);
    await typeInto(h, 'Combo price', '118');
    await tapLabelled(h, 'Save');
    expect(h.server.callsTo('/combos/{id}', method: 'PUT'), hasLength(1));
    await h.expectToast('Changes saved');
  });

  testWidgets('OFFR-CED-060/067 a branch picked: prices at that branch; '
      'switching branch asks again with it', (tester) async {
    final h = await pumpEditor(
      tester,
      path: comboPath('coffee-cookie'),
      branch: SeedIds.maadi,
    );
    expect(_inPanel('Prices at Maadi'), findsOneWidget);
    expect(
      (h.server.callsTo(_econ).last.body! as Map)['branch_id'],
      SeedIds.maadi,
    );
    await h.container.read(scopeProvider.notifier).setBranch(SeedIds.zamalek);
    await debounce(h);
    expect(_inPanel('Prices at Zamalek'), findsOneWidget);
    expect(
      (h.server.callsTo(_econ).last.body! as Map)['branch_id'],
      SeedIds.zamalek,
    );
    final keys = {for (final c in h.server.callsTo(_econ)) jsonEncode(c.body)};
    expect(keys, hasLength(2));
  });
}
