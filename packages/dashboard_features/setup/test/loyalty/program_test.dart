// The Program tab: load, read-only, inherited, every setting, the birthday
// preview, the wallet check, validation, save and revert (SET-LOY-008 … 034,
// 083).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/loyalty/program_pane.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

String _text(WidgetTester tester, String key) =>
    tester.widget<EditableText>(inputOf(programField(key))).controller.text;

Finder _inField(String key, Finder f) =>
    find.descendant(of: programField(key), matching: f);

Future<void> _type(DashHarness h, String key, String text) =>
    h.enterText(programField(key), text);

Future<void> _save(DashHarness h) =>
    h.tap(find.byKey(const ValueKey('loyalty-save')));

List<MockCall> _puts(DashHarness h) =>
    h.server.callsTo(LoyaltyRoutes.settings, method: 'PUT');

void main() {
  group('load', () {
    testWidgets('SET-LOY-008 loading: two card skeletons', (tester) async {
      final m = loyaltyServer();
      final gate = m.server.hold('GET', LoyaltyRoutes.settings);
      final h = await pumpLoyalty(tester, backend: m);
      expect(
        find.byKey(const ValueKey('loyalty-program-loading')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('loyalty-program-loading')),
          matching: find.byType(DashSkeleton),
        ),
        findsNWidgets(2),
      );
      gate.release();
      await h.settle();
      expect(programField('program_name'), findsOneWidget);
    });

    testWidgets('SET-LOY-009 a failed read: "Couldn\'t load the program", the '
        'server\'s words and Retry, which reads again', (tester) async {
      final m = loyaltyServer();
      final boom = MockResponse.error(500, 'Database error: timeout');
      m.server.fail('GET', LoyaltyRoutes.settings, boom, times: 1);
      final h = await pumpLoyalty(tester, backend: m);
      expect(pageText("Couldn't load the program"), findsOneWidget);
      expect(pageText(h.refusalWords(boom)), findsOneWidget);
      expect(find.byType(DashSkeleton), findsNothing);
      await h.tap(inPage(find.text('Retry')));
      expect(h.server.callsTo(LoyaltyRoutes.settings), hasLength(2));
      expect(programField('program_name'), findsOneWidget);
    });

    testWidgets('a background refresh re-seeds the form until it is edited', (
      tester,
    ) async {
      final m = loyaltyServer();
      final h = await pumpLoyalty(tester, backend: m);
      settingsRow(m.db)['program_name'] = 'Sabah Rewards';
      h.container.read(realtimeBusProvider).invalidate(const [
        LoyaltyRoutes.settings,
      ]);
      await h.settle();
      expect(_text(tester, 'program_name'), 'Sabah Rewards');
      await _type(h, 'terms', 'Edited terms');
      settingsRow(m.db)['program_name'] = 'Sabah Club';
      h.container.read(realtimeBusProvider).invalidate(const [
        LoyaltyRoutes.settings,
      ]);
      await h.settle();
      expect(_text(tester, 'program_name'), 'Sabah Rewards');
      expect(_text(tester, 'terms'), 'Edited terms');
    });
  });

  group('who and where', () {
    testWidgets('SET-LOY-010 a read-only viewer: the note, every control '
        'disabled, no Save row', (tester) async {
      final m = loyaltyServer();
      grantOnly(m.server, const ['loyalty.read', 'loyalty.members.list']);
      final h = await pumpLoyalty(tester, backend: m);
      expect(pageText(h.t('loyalty.readOnly')), findsOneWidget);
      final name = tester.widget<DashTextInput>(
        _inField('program_name', find.byType(DashTextInput)),
      );
      expect(name.enabled, isFalse);
      expect(
        tester.widget<DashPressable>(toggle('Program is running').first).onTap,
        isNull,
      );
      expect(find.byKey(const ValueKey('loyalty-save')), findsNothing);
      expect(
        tester
            .widget<DashSegmentedControl<String>>(
              find.byKey(const ValueKey('loyalty-mode')),
            )
            .enabled,
        isFalse,
      );
    });

    testWidgets('SET-LOY-011 a branch with no row of its own: the inherited '
        'note; Save is on unchanged; no Revert', (tester) async {
      final h = await pumpLoyalty(tester, query: atBranch(SeedIds.maadi));
      expect(pageText(h.t('loyalty.inheritedHint')), findsOneWidget);
      expect(buttonAt(tester, 'loyalty-save').onPressed, isNotNull);
      expect(find.byKey(const ValueKey('loyalty-revert')), findsNothing);
    });
  });

  group('settings', () {
    testWidgets('SET-LOY-012 "Program is running" toggles and marks the form '
        'changed', (tester) async {
      final h = await pumpLoyalty(tester);
      expect(buttonAt(tester, 'loyalty-save').onPressed, isNull);
      expect(pageText('Customers can join and collect here.'), findsOneWidget);
      expect(toggleOn(tester, 'Program is running'), isTrue);
      await h.tap(toggle('Program is running'));
      expect(toggleOn(tester, 'Program is running'), isFalse);
      expect(buttonAt(tester, 'loyalty-save').onPressed, isNotNull);
    });

    testWidgets('SET-LOY-013 names: required English, right-to-left Arabic, '
        'side by side from 640', (tester) async {
      final h = await pumpLoyalty(tester);
      expect(_text(tester, 'program_name'), 'Sabah Stamps');
      expect(_text(tester, 'program_name_ar'), 'طوابع صباح');
      expect(
        tester
            .widget<DashTextInput>(
              _inField('program_name_ar', find.byType(DashTextInput)),
            )
            .textDirection,
        TextDirection.rtl,
      );
      expect(
        tester.getTopLeft(programField('program_name')).dy,
        tester.getTopLeft(programField('program_name_ar')).dy,
      );
      await _type(h, 'program_name', '   ');
      await _save(h);
      expect(
        _inField('program_name', find.text('Give the program a name.')),
        findsOneWidget,
      );
      expect(_puts(h), isEmpty);
    });

    testWidgets('SET-LOY-014 SET-LOY-015 points: the segmented choice swaps '
        'in the earn rate, the two switches and the tips note', (tester) async {
      final h = await pumpLoyalty(tester);
      expect(pageText('What customers collect'), findsOneWidget);
      expect(programField('earn_egp_per_point'), findsNothing);
      await h.tap(inPage(find.text('Points on spend')));
      expect(_text(tester, 'earn_egp_per_point'), '10');
      expect(
        pageText('Earn on what was actually paid, after discounts'),
        findsOneWidget,
      );
      expect(pageText('Include tax in what earns'), findsOneWidget);
      expect(pageText(h.t('loyalty.tipsNeverEarn')), findsOneWidget);
      expect(pageText('A stamp for every item, not every order'), findsNothing);
      expect(buttonAt(tester, 'loyalty-save').onPressed, isNotNull);
      await _type(h, 'earn_egp_per_point', '0');
      await _save(h);
      expect(
        _inField(
          'earn_egp_per_point',
          find.text('Enter an amount of at least 0.01 EGP.'),
        ),
        findsOneWidget,
      );
      expect(_puts(h), isEmpty);
    });

    testWidgets('SET-LOY-016 stamps: the per-item switch\'s hint follows it; '
        'the "which items" note only when on', (tester) async {
      final h = await pumpLoyalty(tester);
      expect(pageText(h.t('loyalty.stampPerItemOff')), findsOneWidget);
      expect(pageText(h.t('loyalty.stampPerItemWhich')), findsNothing);
      expect(pageText(h.t('loyalty.stampFreeItemHint')), findsOneWidget);
      await h.tap(toggle('A stamp for every item, not every order'));
      expect(pageText(h.t('loyalty.stampPerItemOn')), findsOneWidget);
      expect(pageText(h.t('loyalty.stampPerItemWhich')), findsOneWidget);
    });

    testWidgets('SET-LOY-017 the default cost: its unit follows the typed '
        'value; a whole number above zero', (tester) async {
      final h = await pumpLoyalty(tester);
      expect(pageText('Default cost of a reward (orders)'), findsOneWidget);
      expect(pageText(h.t('loyalty.defaultCostHint')), findsOneWidget);
      await _type(h, 'default_reward_cost', '1');
      expect(pageText('Default cost of a reward (order)'), findsOneWidget);
      await _type(h, 'default_reward_cost', '2.5');
      await _save(h);
      expect(
        _inField(
          'default_reward_cost',
          find.text('Enter a whole number above zero.'),
        ),
        findsOneWidget,
      );
      // The error replaces the hint (SET-LOY-083).
      expect(pageText(h.t('loyalty.defaultCostHint')), findsNothing);
    });

    testWidgets('SET-LOY-018 "Any item can be a reward" and its hint', (
      tester,
    ) async {
      final h = await pumpLoyalty(tester);
      expect(pageText(h.t('loyalty.anyItemHint')), findsOneWidget);
      expect(toggleOn(tester, 'Any item can be a reward'), isFalse);
      await h.tap(toggle('Any item can be a reward'));
      expect(toggleOn(tester, 'Any item can be a reward'), isTrue);
    });

    testWidgets('SET-LOY-019 SET-LOY-020 limits: the cap switch shows the '
        'figure and, while it is empty, the ceiling the server derives', (
      tester,
    ) async {
      final m = loyaltyServer();
      settingsRow(m.db)['balance_cap_enabled'] = true;
      final h = await pumpLoyalty(tester, backend: m);
      expect(pageText('Limits'), findsOneWidget);
      expect(pageText(h.t('loyalty.limitsHint')), findsOneWidget);
      expect(pageText(h.t('loyalty.capBalanceHint')), findsOneWidget);
      expect(pageText('Most a customer can hold (orders)'), findsOneWidget);
      // The dearest reward on the org's list is six stamps.
      expect(
        pageText(
          'Currently 6 orders — your dearest reward. Collecting past it buys '
          'nothing.',
        ),
        findsOneWidget,
      );
      await _type(h, 'balance_cap', '10');
      expect(find.byKey(const ValueKey('loyalty-cap-derived')), findsNothing);
      await h.tap(toggle('Stop collecting at a maximum'));
      expect(programField('balance_cap'), findsNothing);
    });

    testWidgets('SET-LOY-020 no rewards at all: "Add a reward and the '
        'ceiling follows…"', (tester) async {
      final m = loyaltyServer();
      settingsRow(m.db)['balance_cap_enabled'] = true;
      settingsRow(m.db)['default_reward_cost'] = 0;
      m.db[LoyaltyTables.rewards].clear();
      // An empty catalogue falls back to the default; with none derived the
      // form says how the ceiling will be found.
      final h = await pumpLoyalty(tester, backend: m);
      expect(
        pageText(
          'Currently 1 order — your dearest reward. Collecting past it buys '
          'nothing.',
        ),
        findsOneWidget,
      );
      settingsRow(m.db)['balance_cap_enabled'] = false;
      h.container.read(realtimeBusProvider).invalidate(const [
        LoyaltyRoutes.settings,
      ]);
      await h.settle();
      await h.tap(toggle('Stop collecting at a maximum'));
      expect(
        pageText('Add a reward and the ceiling follows the dearest one.'),
        findsOneWidget,
      );
      await _type(h, 'balance_cap', '0');
      await _save(h);
      expect(
        _inField(
          'balance_cap',
          find.text('Enter a whole number above zero, or leave it empty.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SET-LOY-021 most rewards per order: the figure, its '
        'placeholder and hint', (tester) async {
      final h = await pumpLoyalty(tester);
      expect(_text(tester, 'max_rewards_per_order'), '1');
      expect(pageText(h.t('loyalty.maxRewardsPerOrderHint')), findsOneWidget);
      await _type(h, 'max_rewards_per_order', '');
      expect(
        _inField(
          'max_rewards_per_order',
          find.text('Leave empty for no limit'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SET-LOY-022 verify phone on signup', (tester) async {
      final h = await pumpLoyalty(tester);
      expect(pageText(h.t('loyalty.requireOtpHint')), findsOneWidget);
      expect(toggleOn(tester, 'Verify phone on signup'), isTrue);
      await h.tap(toggle('Verify phone on signup'));
      expect(toggleOn(tester, 'Verify phone on signup'), isFalse);
    });

    testWidgets('SET-LOY-023 birthdays: on shows the gift and both messages; '
        'off hides them', (tester) async {
      final h = await pumpLoyalty(tester);
      expect(pageText(h.t('loyalty.birthdaysHint')), findsOneWidget);
      expect(_text(tester, 'birthday_reward_amount'), '1');
      expect(pageText(h.t('loyalty.birthdayGiftHint')), findsOneWidget);
      expect(
        _inField(
          'birthday_message',
          find.text('Leave empty to use ours. {name} becomes their name.'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DashTextInput>(
              _inField('birthday_message_ar', find.byType(DashTextInput)),
            )
            .textDirection,
        TextDirection.rtl,
      );
      await h.tap(toggle('Birthdays'));
      expect(programField('birthday_reward_amount'), findsNothing);
      expect(programField('birthday_message'), findsNothing);
      await h.flushTimers();
    });

    testWidgets('SET-LOY-024 the birthday preview: 400 ms after an edit the '
        'server renders the EDITED greeting, in both languages', (
      tester,
    ) async {
      final h = await pumpLoyalty(tester);
      await h.settle();
      final first = h.server.callsTo(LoyaltyRoutes.preview);
      expect(first, hasLength(1));
      expect(bodyOf(first.single)['birthday_reward_amount'], 1);
      final panel = find.byKey(const ValueKey('loyalty-birthday-preview'));
      expect(
        find.descendant(of: panel, matching: find.text("What they'll receive")),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.textContaining('Happy birthday, Sara!'),
        ),
        findsOneWidget,
      );
      await h.tester.enterText(
        inputOf(programField('birthday_message')),
        'Happy birthday {name}, from all of us',
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.server.callsTo(LoyaltyRoutes.preview), hasLength(1));
      await h.settle();
      final calls = h.server.callsTo(LoyaltyRoutes.preview);
      expect(calls, hasLength(2));
      expect(
        bodyOf(calls.last)['birthday_message'],
        'Happy birthday {name}, from all of us',
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.text('Happy birthday Sara, from all of us'),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('SET-LOY-024 a failed preview hides the panel, no toast', (
      tester,
    ) async {
      final m = loyaltyServer();
      m.server.fail(
        'POST',
        LoyaltyRoutes.preview,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpLoyalty(tester, backend: m);
      await h.settle();
      expect(h.server.callsTo(LoyaltyRoutes.preview), hasLength(1));
      expect(
        find.byKey(const ValueKey('loyalty-birthday-preview')),
        findsNothing,
      );
      expect(
        find.text(h.refusalWords(MockResponse.error(500, 'boom'))),
        findsNothing,
      );
    });

    testWidgets('SET-LOY-025 win-back: on shows the gift and the wording', (
      tester,
    ) async {
      final h = await pumpLoyalty(tester);
      expect(pageText(h.t('loyalty.winbackHint')), findsOneWidget);
      expect(programField('winback_reward_amount'), findsNothing);
      await h.tap(toggle('Win back quiet customers'));
      expect(
        _inField(
          'winback_reward_amount',
          find.text('Leave empty for words only'),
        ),
        findsOneWidget,
      );
      expect(pageText(h.t('loyalty.winbackGiftHint')), findsOneWidget);
      expect(pageText(h.t('loyalty.winbackMessageHint')), findsOneWidget);
    });

    testWidgets('SET-LOY-026 the terms shown on the pass', (tester) async {
      final h = await pumpLoyalty(tester);
      expect(pageText('Terms (shown on the pass)'), findsOneWidget);
      expect(
        _text(tester, 'terms'),
        'One stamp per order. Six stamps buy any regular hot drink.',
      );
      expect(h.server.unmatched, isEmpty);
    });

    testWidgets('SET-LOY-027 no branch with coordinates: the "will not '
        'notify" warning; with some, none', (tester) async {
      final m = loyaltyServer();
      for (final b in m.db['branches'].rows) {
        b['latitude'] = null;
      }
      final h = await pumpLoyalty(tester, backend: m);
      expect(
        pageText('Cards will not notify customers nearby'),
        findsOneWidget,
      );
      expect(pageText(h.t('loyalty.noGeofenceHint')), findsOneWidget);
    });

    testWidgets('SET-LOY-027 branches with coordinates: no warning', (
      tester,
    ) async {
      await pumpLoyalty(tester);
      expect(find.byKey(const ValueKey('loyalty-no-geofence')), findsNothing);
    });
  });

  group('wallet passes', () {
    testWidgets('SET-LOY-028 an owner sees no wallet check', (tester) async {
      await pumpLoyalty(tester);
      expect(find.byType(WalletStatusPanel), findsNothing);
    });

    testWidgets('SET-LOY-028 SET-LOY-029 platform: Check reads the status at '
        'org scope and draws the three providers', (tester) async {
      final m = loyaltyServer(persona: Persona.platform);
      final gate = m.server.hold('GET', LoyaltyRoutes.wallet);
      final h = await pumpLoyalty(
        tester,
        persona: Persona.platform,
        backend: m,
      );
      final panel = find.byType(WalletStatusPanel);
      expect(
        find.descendant(of: panel, matching: find.text('Wallet passes')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.text(h.t('loyalty.walletStatusHint')),
        ),
        findsOneWidget,
      );
      await h.tap(find.byKey(const ValueKey('loyalty-wallet-check')));
      expect(buttonAt(tester, 'loyalty-wallet-check').loading, isTrue);
      gate.release();
      await h.settle();
      expect(q1(h.server.callsTo(LoyaltyRoutes.wallet).single), isEmpty);
      Finder inPanel(String s) =>
          find.descendant(of: panel, matching: find.text(s));
      expect(inPanel('Apple Wallet'), findsOneWidget);
      expect(inPanel('Apple push (updates)'), findsOneWidget);
      expect(inPanel('Google Wallet'), findsOneWidget);
      expect(inPanel('Not set on the server:'), findsOneWidget);
      expect(inPanel('LOYALTY_APNS_KEY_ID'), findsOneWidget);
      expect(inPanel('Configured.'), findsOneWidget);
      expect(
        find.descendant(
          of: panel,
          matching: find.textContaining('UNDER_REVIEW'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SET-LOY-029 at a branch the check names it; a failure is a '
        'red line beside the previous result, cleared by the next Check', (
      tester,
    ) async {
      final m = loyaltyServer(persona: Persona.platform);
      final h = await pumpLoyalty(
        tester,
        persona: Persona.platform,
        query: atBranch(SeedIds.zamalek),
        backend: m,
      );
      await h.tap(find.byKey(const ValueKey('loyalty-wallet-check')));
      expect(q1(h.server.callsTo(LoyaltyRoutes.wallet).single), {
        'branch_id': SeedIds.zamalek,
      });
      final boom = MockResponse.error(502, 'Google did not answer');
      m.server.fail('GET', LoyaltyRoutes.wallet, boom);
      await h.tap(find.byKey(const ValueKey('loyalty-wallet-check')));
      expect(
        find.byKey(const ValueKey('loyalty-wallet-error')),
        findsOneWidget,
      );
      expect(pageText(h.refusalWords(boom)), findsOneWidget);
      expect(pageText('Apple Wallet'), findsOneWidget);
      await h.tap(find.byKey(const ValueKey('loyalty-wallet-check')));
      expect(find.byKey(const ValueKey('loyalty-wallet-error')), findsNothing);
    });
  });

  group('save and revert', () {
    testWidgets('SET-LOY-030 SET-LOY-083 errors under their fields and the '
        'summary beside Save, live after the first Save', (tester) async {
      final h = await pumpLoyalty(tester);
      await _type(h, 'program_name', '');
      expect(find.byKey(const ValueKey('loyalty-fix-errors')), findsNothing);
      await _save(h);
      expect(
        pageText('Fix the highlighted fields before saving.'),
        findsOneWidget,
      );
      await _type(h, 'program_name', 'Sabah');
      expect(find.byKey(const ValueKey('loyalty-fix-errors')), findsNothing);
      expect(_puts(h), isEmpty);
    });

    testWidgets('SET-LOY-083 a value left invalid in a hidden field never '
        'blocks Save: the cap goes as null', (tester) async {
      final h = await pumpLoyalty(tester);
      await h.tap(toggle('Stop collecting at a maximum'));
      await _type(h, 'balance_cap', '0');
      await h.tap(toggle('Stop collecting at a maximum'));
      await _save(h);
      expect(find.byKey(const ValueKey('loyalty-fix-errors')), findsNothing);
      final body = bodyOf(_puts(h).single);
      expect(body['balance_cap_enabled'], false);
      expect(body['balance_cap'], isNull);
      await h.expectToast('Program saved');
    });

    testWidgets('SET-LOY-083 a field hidden after a failed Save drops out of '
        'the summary; a hidden bad earn rate sends the saved one', (
      tester,
    ) async {
      final m = loyaltyServer();
      final h = await pumpLoyalty(tester, backend: m);
      final savedRate = settingsRow(m.db)['earn_piastres_per_point'];
      await h.tap(inPage(find.text('Points on spend')));
      await _type(h, 'earn_egp_per_point', '0');
      await _save(h);
      expect(
        pageText('Fix the highlighted fields before saving.'),
        findsOneWidget,
      );
      expect(_puts(h), isEmpty);
      // Stamps mode hides the rate: the summary goes and Save goes through.
      await h.tap(inPage(find.text(h.t('loyalty.modeVisits'))));
      expect(find.byKey(const ValueKey('loyalty-fix-errors')), findsNothing);
      await _save(h);
      final body = bodyOf(_puts(h).single);
      expect(body['mode'], 'visits');
      expect(body['earn_piastres_per_point'], savedRate);
      await h.expectToast('Program saved');
    });

    testWidgets('SET-LOY-031 Save sends the saved settings with the form on '
        'top, toasts and re-reads', (tester) async {
      final m = loyaltyServer();
      final h = await pumpLoyalty(tester, backend: m);
      final seen = watchInvalidations(h);
      final reads = h.server.callsTo(LoyaltyRoutes.settings).length;
      await _type(h, 'program_name', '  Sabah Club  ');
      await h.tap(toggle('Birthdays'));
      await h.tap(inPage(find.text('Points on spend')));
      await _type(h, 'earn_egp_per_point', '12.5');
      await _save(h);
      final body = bodyOf(_puts(h).single);
      expect(body['org_id'], SeedIds.sabahOrg);
      expect(body.containsKey('branch_id'), isTrue);
      expect(body['branch_id'], isNull);
      expect(body['program_name'], 'Sabah Club');
      expect(body['mode'], 'points');
      expect(body['earn_piastres_per_point'], 1250);
      expect(body['birthday_enabled'], false);
      expect(body['birthday_reward_amount'], isNull);
      expect(body['birthday_message'], isNull);
      expect(body['balance_cap'], isNull);
      expect(body['max_rewards_per_order'], 1);
      expect(body['stamp_per_line_item'], false);
      // A field the form does not show is carried from the saved row.
      expect(body['terms_ar'], startsWith('طابع واحد'));
      await h.expectToast('Program saved');
      expect(seen, contains(const [LoyaltyRoutes.settings]));
      expect(h.server.callsTo(LoyaltyRoutes.settings).length, reads + 2);
      expect(settingsRow(m.db)['program_name'], 'Sabah Club');
      expect(_text(tester, 'program_name'), 'Sabah Club');
      expect(buttonAt(tester, 'loyalty-save').onPressed, isNull);
    });

    testWidgets('SET-LOY-031 a branch saves under its own id; the inherited '
        'note goes', (tester) async {
      final m = loyaltyServer();
      final h = await pumpLoyalty(
        tester,
        query: atBranch(SeedIds.maadi),
        backend: m,
      );
      await _save(h);
      expect(bodyOf(_puts(h).single)['branch_id'], SeedIds.maadi);
      await h.expectToast('Program saved');
      expect(pageText(h.t('loyalty.inheritedHint')), findsNothing);
      expect(find.byKey(const ValueKey('loyalty-revert')), findsOneWidget);
    });

    testWidgets('SET-LOY-032 a refused save toasts the server\'s words', (
      tester,
    ) async {
      final m = loyaltyServer();
      final no = MockResponse.denied('loyalty.use');
      m.server.fail('PUT', LoyaltyRoutes.settings, no);
      final h = await pumpLoyalty(tester, backend: m);
      await _type(h, 'terms', 'New terms');
      await _save(h);
      await h.expectToast(h.refusalWords(no));
      expect(buttonAt(tester, 'loyalty-save').loading, isFalse);
      expect(_text(tester, 'terms'), 'New terms');
    });

    testWidgets('SET-LOY-033 a branch with its own row: "Follow the '
        'organisation" asks first; Cancel keeps it', (tester) async {
      final h = await pumpLoyalty(tester, query: atBranch(SeedIds.zamalek));
      expect(
        buttonAt(tester, 'loyalty-revert').label,
        'Follow the organisation',
      );
      await h.tap(find.byKey(const ValueKey('loyalty-revert')));
      expect(find.text("Use the organisation's program here?"), findsOneWidget);
      expect(find.text(h.t('loyalty.revertBody')), findsOneWidget);
      await h.tap(find.text('Cancel').last);
      expect(
        h.server.callsTo(LoyaltyRoutes.settings, method: 'DELETE'),
        isEmpty,
      );
    });

    testWidgets('SET-LOY-034 confirmed: DELETE ?branch_id, the toast, and '
        'the branch follows the organisation', (tester) async {
      final m = loyaltyServer();
      final h = await pumpLoyalty(
        tester,
        query: atBranch(SeedIds.zamalek),
        backend: m,
      );
      await h.tap(find.byKey(const ValueKey('loyalty-revert')));
      await h.tap(find.text('Follow the organisation').last);
      final del = h.server.callsTo(LoyaltyRoutes.settings, method: 'DELETE');
      expect(q1(del.single), {'branch_id': SeedIds.zamalek});
      await h.expectToast("Back to the organisation's program");
      expect(pageText(h.t('loyalty.inheritedHint')), findsOneWidget);
      expect(_text(tester, 'program_name'), 'Sabah Stamps');
    });

    testWidgets('SET-LOY-034 a refused revert toasts', (tester) async {
      final m = loyaltyServer();
      final boom = MockResponse.error(500, 'Database error: locked');
      m.server.fail('DELETE', LoyaltyRoutes.settings, boom);
      final h = await pumpLoyalty(
        tester,
        query: atBranch(SeedIds.zamalek),
        backend: m,
      );
      await h.tap(find.byKey(const ValueKey('loyalty-revert')));
      await h.tap(find.text('Follow the organisation').last);
      await h.expectToast(h.refusalWords(boom));
    });
  });
}
