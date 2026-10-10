// Staff drinks settings (`/settings/staff-pool`), driven through the real
// app shell on the mock server: one test per SET-SPL row.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dashboard_setup/src/staff_pool/staff_pool_data.dart';

import 'support.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

Finder _switch() =>
    find.descendant(of: _key('spl-enabled'), matching: find.byType(DashSwitch));

int _gets(DashHarness h) => h.server.callsTo(splSettings, method: 'GET').length;

void main() {
  testWidgets('SET-SPL-001 neither org.settings cap: the lock and its words, '
      'nothing asked', (tester) async {
    for (final p in [Persona.limited, Persona.manager]) {
      final h = await pumpStaffPool(tester, persona: p);
      expect(_key('spl-restricted'), findsOneWidget, reason: p.name);
      expect(paneText('Staff drinks'), findsOneWidget);
      expect(paneText('Not available on this account'), findsOneWidget);
      expect(
        paneText(
          "Your account can't change this. The owner can give you access.",
        ),
        findsOneWidget,
      );
      expect(h.server.callsTo(splSettings), isEmpty);
      expect(h.server.callsTo(splMenu), isEmpty);
    }
  });

  testWidgets('SET-SPL-002 loading: two card skeletons until the answer', (
    tester,
  ) async {
    final m = splServer();
    final gate = m.server.hold('GET', splSettings);
    final h = await pumpStaffPool(tester, backend: m);
    expect(inPane(_key('spl-loading')), findsOneWidget);
    expect(inPane(find.byType(DashSkeleton)), findsNWidgets(2));
    expect(inPane(_key('spl-failed')), findsNothing);
    expect(inPane(_key('spl-card')), findsNothing);
    gate.release();
    await h.settle();
    expect(inPane(_key('spl-loading')), findsNothing);
    expect(inPane(_key('spl-card')), findsOneWidget);
  });

  testWidgets('SET-SPL-003 a failed read: its words, the message, and Retry '
      'asks it again', (tester) async {
    final m = splServer();
    m.server.fail(
      'GET',
      splSettings,
      MockResponse.error(500, 'Database is resting'),
      times: null,
    );
    final h = await pumpStaffPool(tester, backend: m);
    expect(paneText("Couldn't load the staff drinks settings"), findsOneWidget);
    expect(
      paneText(h.refusalWords(MockResponse.error(500, 'Database is resting'))),
      findsOneWidget,
    );
    expect(inPane(_key('spl-loading')), findsNothing);
    final before = _gets(h);
    m.server.clearFailures();
    await h.tap(inPane(find.text('Retry')));
    expect(_gets(h), before + 1);
    expect(inPane(_key('spl-card')), findsOneWidget);
  });

  testWidgets('SET-SPL-003 (refusal) a reader the server refuses sees the '
      "server's words", (tester) async {
    final m = splServer();
    final denied = MockResponse.denied('orders.staff_drink.record');
    m.server.fail('GET', splSettings, denied, times: null);
    final h = await pumpStaffPool(tester, backend: m);
    expect(paneText("Couldn't load the staff drinks settings"), findsOneWidget);
    expect(paneText(h.refusalWords(denied)), findsOneWidget);
  });

  testWidgets('SET-SPL-004 the pane header and description', (tester) async {
    final h = await pumpStaffPool(tester);
    expect(paneText('Staff drinks'), findsOneWidget);
    expect(paneText(h.t('staffPool.settingsSubtitle')), findsOneWidget);
  });

  testWidgets('SET-SPL-005 a reader: the note, every control disabled, no '
      'Save or Revert', (tester) async {
    final m = splServer();
    grantOnly(m.server, const [
      'org.settings.read',
      'orders.staff_drink.record',
    ]);
    final h = await pumpStaffPool(
      tester,
      backend: m,
      query: atBranch(SeedIds.heliopolis),
    );
    expect(paneText(h.t('staffPool.readOnly')), findsOneWidget);
    expect(tester.widget<DashSwitch>(_switch()).enabled, isFalse);
    expect(
      tester.widget<DashTextField>(_key('spl-allowance')).enabled,
      isFalse,
    );
    final trigger = find.descendant(
      of: _key('spl-items-trigger'),
      matching: find.byType(DashPressable),
    );
    expect(tester.widget<DashPressable>(trigger.first).enabled, isFalse);
    expect(_key('spl-save'), findsNothing);
    expect(_key('spl-revert'), findsNothing);
    // The chips' × do nothing either.
    final x = find.descendant(
      of: _key('spl-chips'),
      matching: find.byType(DashIconButton),
    );
    expect(tester.widget<DashIconButton>(x.first).onPressed, isNull);
  });

  testWidgets('SET-SPL-006 a branch following the organisation (the '
      'server\'s inherited, under the branch\'s id): the note, Save offered '
      'untouched, no Revert; saved, it has its own', (tester) async {
    final m = splServer();
    final h = await pumpStaffPool(
      tester,
      backend: m,
      query: atBranch(SeedIds.maadi),
    );
    expect(paneText(h.t('staffPool.inheritedHint')), findsOneWidget);
    expect(_key('spl-revert'), findsNothing);
    expect(buttonAt(tester, 'spl-save').onPressed, isNotNull);
    await h.tap(_key('spl-save'));
    final put = h.server.callsTo(splSettings, method: 'PUT').single;
    expect((put.body as Map)['branch_id'], SeedIds.maadi);
    expect(savedRow(m.db, SeedIds.maadi)?['daily_allowance'], 3);
    await h.expectToast('Staff drinks saved');
    expect(paneText(h.t('staffPool.inheritedHint')), findsNothing);
    expect(_key('spl-revert'), findsOneWidget);
  });

  testWidgets('SET-SPL-006 an own row and the organisation scope show no '
      'inherited note', (tester) async {
    var h = await pumpStaffPool(tester, query: atBranch(SeedIds.heliopolis));
    expect(paneText(h.t('staffPool.inheritedHint')), findsNothing);
    expect(_key('spl-revert'), findsOneWidget);
    h = await pumpStaffPool(tester);
    expect(paneText(h.t('staffPool.inheritedHint')), findsNothing);
    expect(_key('spl-revert'), findsNothing);
    expect(buttonAt(tester, 'spl-save').onPressed, isNull);
  });

  testWidgets(
    'SET-SPL-007 the switch: its words, and flipping it offers Save',
    (tester) async {
      final h = await pumpStaffPool(tester);
      expect(paneText('Staff drinks are on'), findsOneWidget);
      expect(
        paneText("Tellers can ring up a staff drink against the day's pool."),
        findsOneWidget,
      );
      expect(tester.widget<DashSwitch>(_switch()).value, isTrue);
      expect(buttonAt(tester, 'spl-save').onPressed, isNull);
      await h.tap(_switch());
      expect(tester.widget<DashSwitch>(_switch()).value, isFalse);
      expect(buttonAt(tester, 'spl-save').onPressed, isNotNull);
      // Back as it was: nothing to save (react-hook-form's isDirty).
      await h.tap(_switch());
      expect(buttonAt(tester, 'spl-save').onPressed, isNull);
    },
  );

  testWidgets('SET-SPL-008 the allowance: label, the figure, mono, and the '
      'hint while valid', (tester) async {
    final h = await pumpStaffPool(tester, query: atBranch(SeedIds.zamalek));
    expect(paneText('Drinks a day, for the whole branch'), findsOneWidget);
    final field = tester.widget<DashTextField>(_key('spl-allowance'));
    expect(field.value, '5');
    expect(field.mono, isTrue);
    expect(paneText(h.t('staffPool.allowanceHint')), findsOneWidget);
  });

  testWidgets('SET-SPL-009/016 the allowance must be a whole number 0 to 1000; '
      'the error replaces the hint and the summary sits by Save', (
    tester,
  ) async {
    final h = await pumpStaffPool(tester);
    const error = 'A whole number of drinks, 0 or more.';
    for (final bad in ['-1', '1.5', 'abc', '', '1001']) {
      await h.enterText(_key('spl-allowance'), bad);
      await h.tap(_key('spl-save'));
      expect(paneText(error), findsOneWidget, reason: '"$bad"');
      expect(paneText(h.t('staffPool.allowanceHint')), findsNothing);
      expect(
        paneText('Fix the highlighted fields before saving.'),
        findsOneWidget,
      );
    }
    expect(h.server.callsTo(splSettings, method: 'PUT'), isEmpty);
    // Re-checked on each change once Save was tried; zero is a real setting.
    await h.enterText(_key('spl-allowance'), '0');
    expect(paneText(error), findsNothing);
    expect(paneText('Fix the highlighted fields before saving.'), findsNothing);
    await h.tap(_key('spl-save'));
    expect(savedRow(h.db!, null)!['daily_allowance'], 0);
    await h.expectToast('Staff drinks saved');
  });

  testWidgets('SET-SPL-010 the trigger counts the items, or says the pool is '
      'off', (tester) async {
    final m = splServer();
    savedRow(m.db, null)!['eligible_item_ids'] = [itemId('latte')];
    final h = await pumpStaffPool(tester, backend: m);
    expect(paneText('1 item counts as a staff drink'), findsOneWidget);
    await h.tap(_key('spl-items-trigger'));
    await h.tap(inPicker(find.text(itemName('americano'))));
    expect(paneText('2 items count as a staff drink'), findsOneWidget);
    await h.tap(inPicker(find.text('Clear')));
    expect(paneText('No items chosen — the pool is off'), findsOneWidget);
  });

  testWidgets('SET-SPL-011 opening the picker loads the menu: the note, '
      'search, heading, a check per chosen item; Loading… then No results', (
    tester,
  ) async {
    final m = splServer();
    savedRow(m.db, null)!['eligible_item_ids'] = <String>[];
    final gate = m.server.hold('GET', splMenu);
    final h = await pumpStaffPool(tester, backend: m);
    expect(h.server.callsTo(splMenu), isEmpty, reason: 'nothing to name yet');
    await h.tap(_key('spl-items-trigger'));
    final menu = h.server.callsTo(splMenu).single;
    expect(menu.query['org_id'], [SeedIds.sabahOrg]);
    expect(
      inPicker(find.text(h.t('staffPool.itemsPickerNote'))),
      findsOneWidget,
    );
    expect(inPicker(find.text('Loading…')), findsOneWidget);
    gate.release();
    await h.settle();
    expect(inPicker(find.text('Counts as a staff drink')), findsOneWidget);
    expect(inPicker(find.text(itemName('latte'))), findsOneWidget);
    await h.tap(inPicker(find.text(itemName('latte'))));
    expect(
      tester
          .widget<DashOptionList<String>>(
            inPicker(find.byType(DashOptionList<String>)),
          )
          .isSelected(itemId('latte')),
      isTrue,
    );
    await h.enterText(inPicker(find.byType(DashTextInput)), 'zzz');
    expect(inPicker(find.text('No results found')), findsOneWidget);
  });

  testWidgets('SET-SPL-012 Clear empties the list (shown only while any is '
      'chosen)', (tester) async {
    final h = await pumpStaffPool(tester);
    await h.tap(_key('spl-items-trigger'));
    await h.tap(inPicker(_key('spl-items-clear')));
    expect(inPicker(_key('spl-items-clear')), findsNothing);
    expect(_key('spl-chips'), findsNothing);
    expect(buttonAt(tester, 'spl-save').onPressed, isNotNull);
  });

  testWidgets('SET-SPL-013 a chip per chosen item, named once the menu '
      'loads, each with its remove', (tester) async {
    final m = splServer();
    final gate = m.server.hold('GET', splMenu);
    final h = await pumpStaffPool(tester, backend: m);
    final chips = find.descendant(
      of: _key('spl-chips'),
      matching: find.byType(DashIconButton),
    );
    expect(chips, findsNWidgets(8));
    // The raw id until the names arrive.
    expect(inPane(find.text(itemId('latte'))), findsOneWidget);
    gate.release();
    await h.settle();
    expect(inPane(find.text(itemName('latte'))), findsOneWidget);
    final remove = find.bySemanticsLabel('Remove ${itemName('latte')}');
    expect(remove, findsOneWidget);
    await h.tap(remove);
    expect(inPane(find.text(itemName('latte'))), findsNothing);
    expect(chips, findsNWidgets(7));
    expect(paneText('7 items count as a staff drink'), findsOneWidget);
  });

  testWidgets('SET-SPL-014 the pricing rule under the items, in English and '
      'Arabic', (tester) async {
    var h = await pumpStaffPool(tester);
    final rule = find.descendant(
      of: _key('spl-items'),
      matching: find.textContaining(
        "What's free is the smallest size and the default of each required "
        'choice',
      ),
    );
    expect(rule, findsOneWidget);
    expect(
      find.descendant(
        of: _key('spl-items'),
        matching: find.text('Items that count'),
      ),
      findsOneWidget,
    );
    h = await pumpStaffPool(tester, locale: 'ar');
    expect(
      inPane(
        find.textContaining(
          'المجاني هو أصغر حجم والاختيار الأساسي في كل اختيار إلزامي',
        ),
      ),
      findsOneWidget,
    );
    expect(inPane(find.textContaining("What's free")), findsNothing);
    expect(h.locale, 'ar');
  });

  testWidgets('SET-SPL-015 the pool-off notice: no items, switched off, and '
      'nothing when on with items', (tester) async {
    const noItems =
        'The pool is off: with no items chosen, nobody can ring up a staff '
        'drink — whatever the switch above says.';
    const disabled =
        "The pool is off. Tellers can't ring up a staff drink here.";
    final h = await pumpStaffPool(tester, query: atBranch(SeedIds.newCairo));
    expect(paneText(disabled), findsOneWidget);
    await h.tap(_switch());
    expect(inPane(_key('spl-off')), findsNothing);
    await h.tap(_key('spl-items-trigger'));
    await h.tap(inPicker(_key('spl-items-clear')));
    expect(paneText(noItems), findsOneWidget);
    expect(paneText('No items chosen — the pool is off'), findsOneWidget);
  });

  testWidgets('SET-SPL-017 Save sends the scope saved to, the number and the '
      'de-duplicated items, toasts and re-reads', (tester) async {
    final h = await pumpStaffPool(tester, query: atBranch(SeedIds.heliopolis));
    await h.enterText(_key('spl-allowance'), ' 6 ');
    await h.tap(_switch());
    final before = _gets(h);
    await h.tap(_key('spl-save'));
    final put = h.server.callsTo(splSettings, method: 'PUT').single;
    expect(put.body, {
      'org_id': SeedIds.sabahOrg,
      'branch_id': SeedIds.heliopolis,
      'enabled': false,
      'daily_allowance': 6,
      'eligible_item_ids': StaffPoolSettingsMock.eligibleItemIds,
    });
    await h.expectToast('Staff drinks saved');
    expect(_gets(h), before + 1);
    expect(savedRow(h.db!, SeedIds.heliopolis)!['daily_allowance'], 6);
    expect(tester.widget<DashTextField>(_key('spl-allowance')).value, '6');
    expect(buttonAt(tester, 'spl-save').onPressed, isNull);
  });

  testWidgets('SET-SPL-017 the organisation scope saves branch_id null', (
    tester,
  ) async {
    final h = await pumpStaffPool(tester);
    await h.enterText(_key('spl-allowance'), '2');
    await h.tap(_key('spl-save'));
    final body =
        h.server.callsTo(splSettings, method: 'PUT').single.body as Map;
    expect(body.containsKey('branch_id'), isTrue);
    expect(body['branch_id'], isNull);
    await h.expectToast('Staff drinks saved');
  });

  testWidgets("SET-SPL-017 a refused Save toasts the server's words and "
      'keeps the edit', (tester) async {
    final m = splServer();
    final h = await pumpStaffPool(tester, backend: m);
    await h.enterText(_key('spl-allowance'), '9');
    final stale = MockResponse.badRequest(
      "Some of those drinks are not on this organisation's menu any more",
    );
    m.server.fail('PUT', splSettings, stale);
    final before = _gets(h);
    await h.tap(_key('spl-save'));
    await h.expectToast(h.refusalWords(stale));
    expect(_gets(h), before);
    expect(tester.widget<DashTextField>(_key('spl-allowance')).value, '9');
    final denied = MockResponse.denied('org.settings.edit');
    m.server.fail('PUT', splSettings, denied);
    await h.tap(_key('spl-save'));
    await h.expectToast(h.refusalWords(denied));
  });

  testWidgets('SET-SPL-018 Revert at a branch with its own row asks first; '
      'Cancel changes nothing', (tester) async {
    final h = await pumpStaffPool(tester, query: atBranch(SeedIds.heliopolis));
    await h.tap(_key('spl-revert'));
    expect(
      inDialog(find.text("Use the organisation's allowance here?")),
      findsOneWidget,
    );
    expect(inDialog(find.text(h.t('staffPool.revertBody'))), findsOneWidget);
    await h.tap(inDialog(find.text('Cancel')));
    expect(h.server.callsTo(splSettings, method: 'DELETE'), isEmpty);
    expect(savedRow(h.db!, SeedIds.heliopolis), isNotNull);
  });

  testWidgets('SET-SPL-019 Revert confirmed removes the override, toasts and '
      "shows the organisation's figures", (tester) async {
    final h = await pumpStaffPool(tester, query: atBranch(SeedIds.heliopolis));
    expect(tester.widget<DashTextField>(_key('spl-allowance')).value, '4');
    await h.enterText(_key('spl-allowance'), '8');
    await h.tap(_key('spl-revert'));
    await h.tap(inDialog(find.text('Follow the organisation')));
    final del = h.server.callsTo(splSettings, method: 'DELETE').single;
    expect(del.query['branch_id'], [SeedIds.heliopolis]);
    await h.expectToast("Back to the organisation's allowance");
    expect(savedRow(h.db!, SeedIds.heliopolis), isNull);
    expect(tester.widget<DashTextField>(_key('spl-allowance')).value, '3');
  });

  testWidgets("SET-SPL-019 a refused Revert toasts the server's words", (
    tester,
  ) async {
    final m = splServer();
    final h = await pumpStaffPool(
      tester,
      backend: m,
      query: atBranch(SeedIds.heliopolis),
    );
    final denied = MockResponse.denied('org.settings.edit');
    m.server.fail('DELETE', splSettings, denied);
    await h.tap(_key('spl-revert'));
    await h.tap(inDialog(find.text('Follow the organisation')));
    await h.expectToast(h.refusalWords(denied));
    expect(savedRow(m.db, SeedIds.heliopolis), isNotNull);
  });

  testWidgets('SET-SPL-020 the header branch is the scope; switching reloads '
      'the form and drops the edit', (tester) async {
    final h = await pumpStaffPool(tester);
    expect(h.server.callsTo(splSettings).last.query['branch_id'], isNull);
    expect(tester.widget<DashTextField>(_key('spl-allowance')).value, '3');
    await h.enterText(_key('spl-allowance'), '7');
    await h.container.read(scopeProvider.notifier).setBranch(SeedIds.zamalek);
    await h.settle();
    expect(h.server.callsTo(splSettings).last.query['branch_id'], [
      SeedIds.zamalek,
    ]);
    expect(tester.widget<DashTextField>(_key('spl-allowance')).value, '5');
    await h.container.read(scopeProvider.notifier).setBranch(null);
    await h.settle();
    expect(tester.widget<DashTextField>(_key('spl-allowance')).value, '3');
  });

  testWidgets('SET-SPL-021 no organisation in scope: the failure with no '
      'message and nothing asked; Retry asks and shows why', (tester) async {
    final h = await pumpStaffPool(
      tester,
      persona: Persona.platform,
      pickOrg: false,
    );
    expect(paneText("Couldn't load the staff drinks settings"), findsOneWidget);
    expect(inPane(_key('spl-loading')), findsNothing);
    expect(h.server.callsTo(splSettings), isEmpty);
    await h.tap(inPane(find.text('Retry')));
    expect(h.server.callsTo(splSettings), hasLength(1));
    expect(
      paneText(
        h.refusalWords(MockResponse.badRequest('Pick an organisation first')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SET-SPL-021 (divergence) permissions still loading: the '
      'skeleton, never the failure', (tester) async {
    final m = splServer();
    final gate = m.server.hold('GET', '/authz/me');
    final h = await pumpStaffPool(tester, backend: m);
    expect(inPane(_key('spl-failed')), findsNothing);
    expect(_key('spl-restricted'), findsNothing);
    expect(h.server.callsTo(splSettings), isEmpty);
    gate.release();
    await h.settle();
    expect(inPane(_key('spl-card')), findsOneWidget);
  });

  testWidgets('SET-SPL-022 every menu item, named in Arabic in Arabic; '
      'search by that name; picking keeps the list open; 288 wide', (
    tester,
  ) async {
    final m = splServer();
    final h = await pumpStaffPool(tester, backend: m, locale: 'ar');
    await h.tap(_key('spl-items-trigger'));
    final list = tester.widget<DashOptionList<String>>(
      inPicker(find.byType(DashOptionList<String>)),
    );
    final all = m.db['menu_items'].where(
      (r) => r['org_id'] == SeedIds.sabahOrg,
    );
    expect(list.options, hasLength(all.length));
    // The 288 px card (`w-72`), less its 1 px border each side.
    expect(tester.getSize(_key('spl-picker')).width, 288 - 2);
    // Chips are named in Arabic too.
    expect(
      find.descendant(
        of: _key('spl-chips'),
        matching: find.text(itemName('latte', 'ar')),
      ),
      findsOneWidget,
    );
    await h.enterText(
      inPicker(find.byType(DashTextInput)),
      itemName('latte', 'ar'),
    );
    final row = find.descendant(
      of: inPicker(find.byType(ListView)),
      matching: find.text(itemName('latte', 'ar')),
    );
    expect(row, findsOneWidget);
    await h.tap(row);
    expect(_key('spl-picker'), findsOneWidget, reason: 'still open');
    expect(
      find.descendant(
        of: _key('spl-chips'),
        matching: find.text(itemName('latte', 'ar')),
      ),
      findsNothing,
    );
  });

  testWidgets('SET-SPL-022 search is case-insensitive on the name', (
    tester,
  ) async {
    final h = await pumpStaffPool(tester);
    await h.tap(_key('spl-items-trigger'));
    await h.enterText(
      inPicker(find.byType(DashTextInput)),
      itemName('latte').toUpperCase(),
    );
    expect(inPicker(find.text(itemName('latte'))), findsOneWidget);
    expect(inPicker(find.text(itemName('americano'))), findsNothing);
  });

  testWidgets('a background refresh refills an untouched form and leaves an '
      'edited one alone', (tester) async {
    final h = await pumpStaffPool(tester);
    final row = savedRow(h.db!, null)!;
    row['daily_allowance'] = 11;
    h.container.invalidate(staffPoolSettingsProvider(null));
    await h.settle();
    expect(tester.widget<DashTextField>(_key('spl-allowance')).value, '11');
    await h.tap(_switch());
    row['daily_allowance'] = 12;
    h.container.invalidate(staffPoolSettingsProvider(null));
    await h.settle();
    expect(tester.widget<DashTextField>(_key('spl-allowance')).value, '11');
    expect(tester.widget<DashSwitch>(_switch()).value, isFalse);
  });

  testWidgets('SET-SPL-011 phone: a pick in the open card keeps a refresh '
      'that landed after it opened', (tester) async {
    final h = await pumpStaffPool(tester, size: DashSize.phone);
    await _openPhonePicker(h);
    savedRow(h.db!, null)!['daily_allowance'] = 11;
    h.container.invalidate(staffPoolSettingsProvider(null));
    await h.settle();
    expect(tester.widget<DashTextField>(_key('spl-allowance')).value, '11');
    await h.tap(inPicker(find.text(itemName('latte'))));
    expect(tester.widget<DashTextField>(_key('spl-allowance')).value, '11');
  });

  testWidgets('phone: the list opens in a card over the page and follows '
      'each toggle', (tester) async {
    final h = await pumpStaffPool(tester, size: DashSize.phone);
    await _openPhonePicker(h);
    expect(
      find.descendant(of: dashPopoverCard, matching: _key('spl-picker')),
      findsOneWidget,
    );
    await h.tap(inPicker(find.text(itemName('latte'))));
    expect(
      tester
          .widget<DashOptionList<String>>(
            inPicker(find.byType(DashOptionList<String>)),
          )
          .isSelected(itemId('latte')),
      isFalse,
    );
    expect(inPicker(_key('spl-items-clear')), findsOneWidget);
    await h.tap(inPicker(_key('spl-items-clear')));
    expect(inPicker(_key('spl-items-clear')), findsNothing);
  });
}

/// Opens the items card on a phone and scrolls its list to the latte, as a
/// thumb would: the card shows a handful of rows at a time.
Future<void> _openPhonePicker(DashHarness h) async {
  await h.tap(_key('spl-items-trigger'));
  await h.scrollUntilVisible(
    inPicker(find.text(itemName('latte'))),
    delta: 100,
    scrollable: find
        .descendant(
          of: inPicker(find.byType(ListView)),
          matching: find.byType(Scrollable),
        )
        .first,
  );
}
