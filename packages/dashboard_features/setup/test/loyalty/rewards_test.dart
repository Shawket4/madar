// The Rewards tab: the catalogue (rows, problems, add, save, discard) and
// the items that collect a stamp (SET-LOY-035 … 051).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

String _item(String key) => MockSeed.menuItemId(key);

Finder _cost(String key) => find.byKey(ValueKey('reward-cost-${_item(key)}'));

Finder _earning() => find.byKey(const ValueKey('loyalty-earning'));

Finder _inEarning(Finder f) => find.descendant(of: _earning(), matching: f);

Finder _rewardsCard() => find.ancestor(
  of: find.text('Add a reward'),
  matching: find.byType(DashCard),
);

Future<DashHarness> _open(
  WidgetTester tester, {
  String query = '',
  ({MockServer server, MockDb db})? backend,
}) async {
  final h = await pumpLoyalty(tester, query: query, backend: backend);
  await openTab(h, 'Rewards');
  return h;
}

Finder _options() => find.byWidgetPredicate((w) => w is DashOptionList);

/// An option row's words containing [s] (not the search box's).
Finder _option(String s) => find.descendant(
  of: _options(),
  matching: find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').contains(s),
  ),
);

/// Searches the open picker for [name].
Future<void> _search(DashHarness h, String name) => h.enterText(
  find.descendant(of: _options(), matching: find.byType(DashTextInput)),
  name,
);

/// Opens the picker inside [scope], searches and picks [name].
Future<void> _pick(DashHarness h, Finder scope, String name) async {
  await h.tap(
    find.descendant(of: scope, matching: find.byType(DashSelect<String>)),
  );
  await _search(h, name);
  await h.tap(_option(name));
}

List<MockCall> _puts(DashHarness h, String route) =>
    h.server.callsTo(route, method: 'PUT');

void main() {
  group('the catalogue', () {
    testWidgets('SET-LOY-035 loading: one card skeleton', (tester) async {
      final m = loyaltyServer();
      final gate = m.server.hold('GET', LoyaltyRoutes.rewards);
      final h = await _open(tester, backend: m);
      expect(
        find.byKey(const ValueKey('loyalty-rewards-loading')),
        findsOneWidget,
      );
      gate.release();
      await h.settle();
      expect(_cost('espresso'), findsOneWidget);
    });

    testWidgets('SET-LOY-036 a failed read: "Couldn\'t load the rewards" and '
        'Retry, which re-reads both', (tester) async {
      final m = loyaltyServer();
      final boom = MockResponse.error(500, 'Database error: timeout');
      // The tab's warm and the pane's own read both fail.
      m.server.fail('GET', LoyaltyRoutes.rewards, boom, times: 2);
      final h = await _open(tester, backend: m);
      expect(pageText("Couldn't load the rewards"), findsOneWidget);
      expect(pageText(h.refusalWords(boom)), findsOneWidget);
      final settings = h.server.callsTo(LoyaltyRoutes.settings).length;
      final reads = h.server.callsTo(LoyaltyRoutes.rewards).length;
      await h.tap(inPage(find.text('Retry')));
      expect(h.server.callsTo(LoyaltyRoutes.rewards), hasLength(reads + 1));
      expect(
        h.server.callsTo(LoyaltyRoutes.settings).length,
        greaterThan(settings),
      );
      expect(_cost('espresso'), findsOneWidget);
    });

    testWidgets('SET-LOY-037 a branch with no list of its own: the '
        'inherited note', (tester) async {
      final h = await _open(tester, query: atBranch(SeedIds.maadi));
      expect(pageText(h.t('loyalty.rewardsInherited')), findsOneWidget);
      expect(q1(h.server.callsTo(LoyaltyRoutes.rewards).single), {
        'branch_id': SeedIds.maadi,
      });
    });

    testWidgets('SET-LOY-038 "any item" on: the warning names the cost', (
      tester,
    ) async {
      final m = loyaltyServer();
      settingsRow(m.db)['reward_any_item'] = true;
      await _open(tester, backend: m);
      expect(
        pageText(
          '“Any item can be a reward” is on: every menu item costs 6 orders '
          'and the prices below are not used until you switch it off.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('SET-LOY-039 an empty catalogue: "No rewards yet"', (
      tester,
    ) async {
      final m = loyaltyServer();
      m.db[LoyaltyTables.rewards].clear();
      final h = await _open(tester, backend: m);
      expect(pageText('No rewards yet'), findsOneWidget);
      expect(pageText(h.t('loyalty.noRewardsHint')), findsOneWidget);
    });

    testWidgets('SET-LOY-040 rows: name, cost under its unit, remove', (
      tester,
    ) async {
      final h = await _open(tester);
      for (final (key, cost) in loyaltySeedRewards) {
        expect(
          tester.widget<DashTextInput>(_cost(key)).value,
          '$cost',
          reason: key,
        );
      }
      expect(inPage(find.text('Espresso')), findsOneWidget);
      expect(inPage(find.text('orders')), findsNWidgets(5));
      final removes = inPage(find.bySemanticsLabel('Remove'));
      expect(removes, findsNWidgets(5));
      await h.tap(removes.first);
      expect(_cost('espresso'), findsNothing);
      expect(buttonAt(tester, 'rewards-save').onPressed, isNotNull);
    });

    testWidgets('SET-LOY-040 read-only: costs disabled, no remove, no picker, '
        'no Save', (tester) async {
      final m = loyaltyServer();
      grantOnly(m.server, const ['loyalty.read', 'loyalty.members.list']);
      await _open(tester, backend: m);
      expect(tester.widget<DashTextInput>(_cost('espresso')).enabled, isFalse);
      expect(inPage(find.bySemanticsLabel('Remove')), findsNothing);
      expect(pageText('Add a reward'), findsNothing);
      expect(find.byKey(const ValueKey('rewards-save')), findsNothing);
    });

    testWidgets('SET-LOY-041 problems: a bad cost and a deleted item block; '
        'a switched-off item only warns', (tester) async {
      final m = loyaltyServer();
      m.db['menu_items'].find(_item('cappuccino'))!['is_active'] = false;
      final h = await _open(tester, backend: m);
      expect(pageText(h.t('loyalty.rewardInactive')), findsOneWidget);
      // Only a warning: the list can still be saved once changed.
      await h.enterText(_cost('latte'), '7');
      expect(buttonAt(tester, 'rewards-save').onPressed, isNotNull);
      await h.enterText(_cost('latte'), '0');
      expect(pageText('Enter a whole number above zero.'), findsOneWidget);
      expect(buttonAt(tester, 'rewards-save').onPressed, isNull);
      await h.enterText(_cost('latte'), '6');
      m.db['menu_items'].find(_item('espresso'))!['deleted_at'] = m.db.nowIso;
      h.container.read(realtimeBusProvider).invalidate(const ['/menu-items']);
      await h.settle();
      expect(
        pageText('This menu item has been deleted. Remove it to save.'),
        findsOneWidget,
      );
      expect(buttonAt(tester, 'rewards-save').onPressed, isNull);
    });

    testWidgets('SET-LOY-041 nothing is flagged while the menu is loading', (
      tester,
    ) async {
      final m = loyaltyServer();
      m.db['menu_items'].find(_item('cappuccino'))!['is_active'] = false;
      final gate = m.server.hold('GET', LoyaltyRoutes.menu);
      final h = await _open(tester, backend: m);
      expect(pageText(h.t('loyalty.rewardInactive')), findsNothing);
      gate.release();
      await h.settle();
      expect(pageText(h.t('loyalty.rewardInactive')), findsOneWidget);
    });

    testWidgets('SET-LOY-042 add a reward: active items not listed, "name · '
        'price"; the new row costs the default', (tester) async {
      final m = loyaltyServer();
      m.db['menu_items'].find(_item('mocha'))!['is_active'] = false;
      final h = await _open(tester, backend: m);
      expect(pageText('Add a reward'), findsOneWidget);
      expect(pageText(h.t('loyalty.pickItemHint')), findsOneWidget);
      final add = find.descendant(
        of: _rewardsCard(),
        matching: find.byWidgetPredicate(
          (w) => w is DashButton && w.label == 'Add',
        ),
      );
      expect(tester.widget<DashButton>(add).onPressed, isNull);
      await h.tap(
        find.descendant(
          of: _rewardsCard(),
          matching: find.byType(DashSelect<String>),
        ),
      );
      Finder option(String s) => _option(s);
      await _search(h, 'Espresso');
      expect(option('Espresso'), findsNothing);
      await _search(h, 'Mocha');
      // "Iced Mocha" stays; the switched-off "Mocha" is not offered.
      expect(
        find.descendant(
          of: _options(),
          matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? '').startsWith('Mocha · '),
          ),
        ),
        findsNothing,
      );
      expect(option('Iced Mocha · '), findsOneWidget);
      await _search(h, 'Flat');
      final label = tester.widget<Text>(option('Flat White')).data!;
      expect(label, startsWith('Flat White · '));
      expect(label, contains('115.00'));
      await h.tap(option('Flat White'));
      await h.tap(add);
      expect(tester.widget<DashTextInput>(_cost('flatwhite')).value, '6');
      expect(tester.widget<DashButton>(add).onPressed, isNull);
    });

    testWidgets('SET-LOY-043 Save sends the list in the scope\'s currency, '
        'toasts and re-reads', (tester) async {
      final m = loyaltyServer();
      final h = await _open(tester, backend: m);
      final seen = watchInvalidations(h);
      await h.enterText(_cost('cookie'), '3');
      await h.tap(find.byKey(const ValueKey('rewards-save')));
      final body = bodyOf(_puts(h, LoyaltyRoutes.rewards).single);
      expect(body.containsKey('branch_id'), isTrue);
      expect(body['branch_id'], isNull);
      final items = (body['items']! as List).cast<Map>();
      expect(items, hasLength(5));
      expect(items.last, {
        'menu_item_id': _item('cookie'),
        'cost_currency': 'visits',
        'cost_amount': 3,
      });
      await h.expectToast('Rewards saved');
      expect(seen, contains(const [LoyaltyRoutes.rewards]));
      expect(
        h.server.callsTo(LoyaltyRoutes.rewards, method: 'GET'),
        hasLength(2),
      );
      expect(buttonAt(tester, 'rewards-save').onPressed, isNull);
    });

    testWidgets('SET-LOY-043 a blocking problem on submit: "Fix the '
        'highlighted rewards, then save."', (tester) async {
      final m = loyaltyServer();
      final h = await _open(tester, backend: m);
      await h.enterText(_cost('cookie'), '0');
      await tester.showKeyboard(_cost('cookie'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      await h.expectToast('Fix the highlighted rewards, then save.');
      expect(_puts(h, LoyaltyRoutes.rewards), isEmpty);
    });

    testWidgets('SET-LOY-044 the server\'s "active menu items" refusal reads '
        'as the translated sentence', (tester) async {
      final m = loyaltyServer();
      final h = await _open(tester, backend: m);
      // Switched off elsewhere after the page loaded its menu.
      m.db['menu_items'].find(_item('espresso'))!['is_active'] = false;
      await h.enterText(_cost('cookie'), '5');
      await h.tap(find.byKey(const ValueKey('rewards-save')));
      await h.expectToast(h.t('loyalty.errors.serverInactiveReward'));
    });

    testWidgets('SET-LOY-044 any other refusal: the server\'s words', (
      tester,
    ) async {
      final m = loyaltyServer();
      final no = MockResponse.denied('loyalty.use');
      m.server.fail('PUT', LoyaltyRoutes.rewards, no);
      final h = await _open(tester, backend: m);
      await h.enterText(_cost('cookie'), '5');
      await h.tap(find.byKey(const ValueKey('rewards-save')));
      await h.expectToast(h.refusalWords(no));
    });

    testWidgets('SET-LOY-045 "Discard changes" only when changed; it puts '
        'the server\'s list back', (tester) async {
      final h = await _open(tester);
      expect(find.byKey(const ValueKey('rewards-discard')), findsNothing);
      await h.enterText(_cost('latte'), '9');
      await h.tap(find.byKey(const ValueKey('rewards-discard')));
      expect(tester.widget<DashTextInput>(_cost('latte')).value, '6');
      expect(find.byKey(const ValueKey('rewards-discard')), findsNothing);
    });
  });

  group('the items that collect', () {
    testWidgets('SET-LOY-046 a stamp card: the card and its "everything '
        'collects" line; a points card has none', (tester) async {
      final h = await _open(tester);
      expect(
        _inEarning(find.text('Items that collect a stamp')),
        findsOneWidget,
      );
      expect(
        _inEarning(find.text(h.t('loyalty.earningItemsAll'))),
        findsOneWidget,
      );
    });

    testWidgets('SET-LOY-046 points mode: no earning card', (tester) async {
      final m = loyaltyServer();
      settingsRow(m.db)['mode'] = 'points';
      final h = await _open(tester, backend: m);
      expect(_earning(), findsNothing);
      expect(h.server.callsTo(LoyaltyRoutes.earning), isEmpty);
    });

    testWidgets('SET-LOY-047 per-order counting: the inert note; at a branch '
        'that inherits, the inherited note', (tester) async {
      final h = await _open(tester, query: atBranch(SeedIds.maadi));
      expect(
        _inEarning(find.text(h.t('loyalty.earningItemsInert'))),
        findsOneWidget,
      );
      expect(
        _inEarning(find.text(h.t('loyalty.earningItemsInherited'))),
        findsOneWidget,
      );
    });

    testWidgets('SET-LOY-048 loading: a skeleton; a failed read reads as the '
        'whole menu, no error panel', (tester) async {
      final m = loyaltyServer();
      final gate = m.server.hold('GET', LoyaltyRoutes.earning);
      final h = await _open(tester, backend: m);
      expect(
        find.byKey(const ValueKey('loyalty-earning-loading')),
        findsOneWidget,
      );
      m.server.fail(
        'GET',
        LoyaltyRoutes.earning,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      gate.release();
      await h.settle();
      expect(
        _inEarning(find.text(h.t('loyalty.earningItemsAll'))),
        findsOneWidget,
      );
      expect(_inEarning(find.text('Retry')), findsNothing);
    });

    testWidgets('SET-LOY-049 SET-LOY-051 rows with remove; Save sends the '
        'ids; a reorder alone is not a change', (tester) async {
      final m = loyaltyServer();
      settingsRow(m.db)['stamp_per_line_item'] = true;
      for (final (i, k) in ['latte', 'cappuccino'].indexed) {
        m.db[LoyaltyTables.earning].insert({
          'org_id': SeedIds.sabahOrg,
          'branch_id': null,
          'menu_item_id': _item(k),
          'sort_order': i,
        }, timestamps: false);
      }
      final h = await _open(tester, backend: m);
      expect(
        _inEarning(find.text(h.t('loyalty.earningItemsSome'))),
        findsOneWidget,
      );
      expect(_inEarning(find.text('Caffè Latte')), findsOneWidget);
      expect(
        _inEarning(find.text(h.t('loyalty.earningItemsInert'))),
        findsNothing,
      );
      expect(buttonAt(tester, 'earning-save').onPressed, isNull);
      await h.tap(_inEarning(find.bySemanticsLabel('Remove')).first);
      expect(_inEarning(find.text('Caffè Latte')), findsNothing);
      await h.tap(find.byKey(const ValueKey('earning-save')));
      final body = bodyOf(_puts(h, LoyaltyRoutes.earning).single);
      expect(body['menu_item_ids'], [_item('cappuccino')]);
      expect(body.containsKey('branch_id'), isTrue);
      await h.expectToast('Saved');
      expect(
        h.server.callsTo(LoyaltyRoutes.earning, method: 'GET'),
        hasLength(2),
      );
    });

    testWidgets('SET-LOY-050 SET-LOY-051 add an item that collects; '
        'Discard puts the list back', (tester) async {
      final h = await _open(tester);
      expect(
        _inEarning(find.text('Add an item that collects')),
        findsOneWidget,
      );
      await _pick(h, _earning(), 'Mint Lemonade');
      await h.tap(
        _inEarning(
          find.byWidgetPredicate((w) => w is DashButton && w.label == 'Add'),
        ),
      );
      expect(_inEarning(find.text('Mint Lemonade')), findsOneWidget);
      expect(buttonAt(tester, 'earning-save').onPressed, isNotNull);
      await h.tap(find.byKey(const ValueKey('earning-discard')));
      expect(_inEarning(find.text('Mint Lemonade')), findsNothing);
    });

    testWidgets('SET-LOY-051 a refused save toasts the server\'s words', (
      tester,
    ) async {
      final m = loyaltyServer();
      final no = MockResponse.denied('loyalty.use');
      m.server.fail('PUT', LoyaltyRoutes.earning, no);
      final h = await _open(tester, backend: m);
      await _pick(h, _earning(), 'Mint Lemonade');
      await h.tap(
        _inEarning(
          find.byWidgetPredicate((w) => w is DashButton && w.label == 'Add'),
        ),
      );
      await h.tap(find.byKey(const ValueKey('earning-save')));
      await h.expectToast(h.refusalWords(no));
    });
  });
}
