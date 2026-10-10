// The Combos and deals settings pane, one driven test per SET-CMB row,
// through the real app shell on the mock server.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('gates and states', () {
    for (final p in [Persona.limited, Persona.manager]) {
      testWidgets('SET-CMB-001 ${p.name}: the pane refuses in place and asks '
          'nothing', (tester) async {
        final h = await pumpCombos(tester, persona: p);
        expect(byKey('cmb-restricted'), findsOneWidget);
        expect(paneText('Combos and deals'), findsOneWidget);
        expect(paneText('Not available on this account'), findsOneWidget);
        expect(paneText(h.t('combos.settings.noAccess')), findsOneWidget);
        expect(h.server.callsTo(cmbSettings), isEmpty);
      });
    }

    testWidgets('SET-CMB-002 loading: two card skeletons', (tester) async {
      final m = cmbServer();
      final gate = m.server.hold('GET', cmbSettings);
      final h = await pumpCombos(tester, backend: m);
      expect(byKey('cmb-loading'), findsOneWidget);
      expect(inPane(find.byType(DashSkeleton)), findsNWidgets(2));
      expect(paneText(h.t('combos.settings.noBranches')), findsNothing);
      gate.release();
      await h.settle();
      expect(byKey('cmb-loading'), findsNothing);
      expect(byKey('cmb-channels'), findsOneWidget);
    });

    testWidgets('SET-CMB-003 a failed read: the error, its words, and Retry '
        'asks only this read', (tester) async {
      final m = cmbServer();
      final boom = MockResponse.error(500, 'Database is resting');
      m.server.fail('GET', cmbSettings, boom);
      final h = await pumpCombos(tester, backend: m);
      expect(paneText("Couldn't load the combo settings"), findsOneWidget);
      expect(paneText(h.refusalWords(boom)), findsOneWidget);
      final branches = h.server.callsTo('/branches').length;
      await h.tap(inPane(find.text('Retry')));
      expect(h.server.callsTo(cmbSettings), hasLength(2));
      expect(h.server.callsTo('/branches'), hasLength(branches));
      expect(byKey('cmb-channels'), findsOneWidget);
    });

    testWidgets('SET-CMB-003 a refused read shows the server\'s words', (
      tester,
    ) async {
      final m = cmbServer();
      final denied = MockResponse.denied('org.settings.read');
      m.server.fail('GET', cmbSettings, denied, times: null);
      final h = await pumpCombos(tester, backend: m);
      expect(paneText(h.refusalWords(denied)), findsOneWidget);
    });

    testWidgets('SET-CMB-004 the pane header and description', (tester) async {
      final h = await pumpCombos(tester);
      expect(paneText('Combos and deals'), findsOneWidget);
      expect(paneText(h.t('combos.settings.subtitle')), findsOneWidget);
    });

    testWidgets('SET-CMB-005 a reader: the note, everything disabled, no '
        'Save', (tester) async {
      final m = cmbServer();
      grantOnly(m.server, const ['org.settings.read']);
      final h = await pumpCombos(tester, backend: m);
      expect(paneText(h.t('combos.settings.readOnly')), findsOneWidget);
      for (final c in ComboChannel.values) {
        expect(tester.widget<DashSwitch>(sellSwitch(c)).enabled, isFalse);
      }
      expect(
        tester.widget<DashTextInput>(byKey('cmb-margin')).enabled,
        isFalse,
      );
      expect(byKey('cmb-save'), findsNothing);
      for (final c in ComboChannel.values) {
        expect(cellWidget(tester, SeedIds.heliopolis, c).enabled, isFalse);
      }
    });

    testWidgets('B5 menu.combos.edit alone opens the editor: the read is '
        'answered, no read-only note, Save offered', (tester) async {
      final m = cmbServer();
      grantOnly(m.server, const ['menu.combos.edit']);
      final h = await pumpCombos(tester, backend: m);
      expect(byKey('cmb-channels'), findsOneWidget);
      expect(paneText(h.t('combos.settings.readOnly')), findsNothing);
      expect(byKey('cmb-save'), findsOneWidget);
      expect(h.server.callsTo(cmbSettings), hasLength(1));
    });

    testWidgets('SET-CMB-017 no org picked: the load-failed state with no '
        'words; Retry asks and shows the server\'s answer', (tester) async {
      final h = await pumpCombos(
        tester,
        persona: Persona.platform,
        pickOrg: false,
      );
      expect(paneText("Couldn't load the combo settings"), findsOneWidget);
      expect(byKey('cmb-loading'), findsNothing);
      expect(h.server.callsTo(cmbSettings), isEmpty);
      await h.tap(inPane(find.text('Retry')));
      expect(h.server.callsTo(cmbSettings), hasLength(1));
      expect(
        paneText(
          h.refusalWords(
            MockResponse.forbidden('A super admin must scope this to an org'),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SET-CMB-017 a platform admin inside an org reads it', (
      tester,
    ) async {
      final h = await pumpCombos(tester, persona: Persona.platform);
      expect(byKey('cmb-channels'), findsOneWidget);
      expect(h.server.callsTo(cmbSettings), hasLength(1));
    });

    testWidgets('SET-CMB-017 (divergence) grants still loading: a skeleton, '
        'not a failure', (tester) async {
      final m = cmbServer();
      final gate = m.server.hold('GET', '/authz/me');
      final h = await pumpCombos(tester, backend: m);
      expect(byKey('cmb-loading'), findsOneWidget);
      expect(paneText("Couldn't load the combo settings"), findsNothing);
      gate.release();
      await h.settle();
      expect(byKey('cmb-channels'), findsOneWidget);
    });
  });

  group('the organisation', () {
    testWidgets('SET-CMB-006 four channels with hints; the seed has the '
        'delivery apps off', (tester) async {
      final h = await pumpCombos(tester);
      for (final c in ComboChannel.values) {
        expect(
          find.descendant(
            of: byKey('cmb-sell-${c.name}'),
            matching: find.text(h.t(c.labelKey)),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: byKey('cmb-sell-${c.name}'),
            matching: find.text(h.t(c.hintKey)),
          ),
          findsOneWidget,
        );
      }
      expect(paneText('Sold on'), findsOneWidget);
      expect(paneText(h.t('combos.settings.channelsHint')), findsOneWidget);
      expect(
        tester.widget<DashSwitch>(sellSwitch(ComboChannel.pos)).value,
        isTrue,
      );
      expect(
        tester.widget<DashSwitch>(sellSwitch(ComboChannel.delivery)).value,
        isFalse,
      );
    });

    testWidgets('SET-CMB-006 a channel the server leaves out reads as on', (
      tester,
    ) async {
      final m = cmbServer();
      final body = ComboSettingsMock.wire(m.db, SeedIds.sabahOrg);
      body['channels'] = {'pos': false};
      m.server.fail('GET', cmbSettings, MockResponse.ok(body), times: null);
      await pumpCombos(tester, backend: m);
      expect(
        tester.widget<DashSwitch>(sellSwitch(ComboChannel.pos)).value,
        isFalse,
      );
      for (final c in [
        ComboChannel.qr,
        ComboChannel.online,
        ComboChannel.delivery,
      ]) {
        expect(tester.widget<DashSwitch>(sellSwitch(c)).value, isTrue);
      }
    });

    testWidgets('SET-CMB-007 the margin loads as a percent, with its hint', (
      tester,
    ) async {
      final m = cmbServer();
      final h = await pumpCombos(tester, backend: m);
      expect(tester.widget<EditableText>(marginInput()).controller.text, '55');
      expect(paneText('Minimum margin'), findsOneWidget);
      expect(paneText(h.t('combos.settings.minMarginHint')), findsOneWidget);
      expect(paneText('%'), findsOneWidget);
      final input = tester.widget<DashTextInput>(byKey('cmb-margin'));
      expect(input.textDirection, TextDirection.ltr);
      expect(input.mono, isTrue);
    });

    testWidgets('SET-CMB-007 no margin: blank, the placeholder', (
      tester,
    ) async {
      final m = cmbServer();
      m.db[ComboSettingsMock.margins].put({
        'id': SeedIds.sabahOrg,
        'combo_min_margin': null,
      });
      await pumpCombos(tester, backend: m);
      expect(tester.widget<EditableText>(marginInput()).controller.text, '');
      expect(
        tester.widget<DashTextInput>(byKey('cmb-margin')).placeholder,
        'No warning',
      );
    });

    testWidgets('SET-CMB-008 a margin outside 0–99 replaces the hint with the '
        'error on Save and sends nothing; fixing it clears it', (tester) async {
      final h = await pumpCombos(tester);
      await h.enterText(byKey('cmb-margin'), '100');
      expect(
        byKey('cmb-margin-error'),
        findsNothing,
        reason: 'not before Save',
      );
      await h.tap(byKey('cmb-save'));
      expect(paneText('Enter a percentage from 0 to 99.'), findsOneWidget);
      expect(paneText(h.t('combos.settings.minMarginHint')), findsNothing);
      expect(h.server.callsTo(cmbSettings, method: 'PUT'), isEmpty);
      await h.enterText(byKey('cmb-margin'), 'abc');
      expect(byKey('cmb-margin-error'), findsOneWidget);
      await h.enterText(byKey('cmb-margin'), '99.5');
      expect(byKey('cmb-margin-error'), findsNothing);
      expect(paneText(h.t('combos.settings.minMarginHint')), findsOneWidget);
    });

    testWidgets('SET-CMB-009 Save: disabled until a change; sends the rate '
        'and the four switches; toast; the read refreshes', (tester) async {
      final m = cmbServer();
      final h = await pumpCombos(tester, backend: m);
      expect(saveButton(tester).onPressed, isNull);
      await h.enterText(byKey('cmb-margin'), '42.5');
      expect(saveButton(tester).onPressed, isNotNull);
      final reads = h.server.callsTo(cmbSettings, method: 'GET').length;
      await h.tap(byKey('cmb-save'));
      final put = h.server.callsTo(cmbSettings, method: 'PUT').single;
      expect(put.body, {
        'min_margin': '0.4250',
        'channels': {
          'pos': true,
          'qr': true,
          'online': true,
          'delivery': false,
        },
      });
      await h.expectToast('Combo settings saved');
      expect(storedMargin(m.db), '0.4250');
      expect(
        h.server.callsTo(cmbSettings, method: 'GET').length,
        greaterThan(reads),
      );
      expect(
        tester.widget<EditableText>(marginInput()).controller.text,
        '42.5',
      );
      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('SET-CMB-009 a blank margin saves null (no warning)', (
      tester,
    ) async {
      final m = cmbServer();
      final h = await pumpCombos(tester, backend: m);
      await h.enterText(byKey('cmb-margin'), '');
      await h.tap(byKey('cmb-save'));
      final put = h.server.callsTo(cmbSettings, method: 'PUT').single;
      expect((put.body! as Map)['min_margin'], isNull);
      expect((put.body! as Map).containsKey('min_margin'), isTrue);
      await h.expectToast('Combo settings saved');
      expect(storedMargin(m.db), isNull);
    });

    testWidgets('SET-CMB-009 a refused Save keeps the edit and toasts the '
        'server\'s words', (tester) async {
      final m = cmbServer();
      final denied = MockResponse.denied('menu.combos.edit');
      m.server.fail('PUT', cmbSettings, denied);
      final h = await pumpCombos(tester, backend: m);
      await h.enterText(byKey('cmb-margin'), '30');
      await h.tap(byKey('cmb-save'));
      await h.expectToast(h.refusalWords(denied));
      expect(tester.widget<EditableText>(marginInput()).controller.text, '30');
      expect(saveButton(tester).onPressed, isNotNull);
      expect(storedMargin(m.db), ComboSettingsMock.sabahMinMargin);
    });

    testWidgets('SET-CMB-015 flipping a switch marks the form changed and '
        'saves nothing on its own', (tester) async {
      final m = cmbServer();
      final h = await pumpCombos(tester, backend: m);
      await h.tap(sellSwitch(ComboChannel.qr));
      expect(
        tester.widget<DashSwitch>(sellSwitch(ComboChannel.qr)).value,
        isFalse,
      );
      expect(saveButton(tester).onPressed, isNotNull);
      expect(h.server.callsTo(cmbSettings, method: 'PUT'), isEmpty);
      // Flipping it back is no change.
      await h.tap(sellSwitch(ComboChannel.qr));
      expect(saveButton(tester).onPressed, isNull);
      await h.tap(sellSwitch(ComboChannel.delivery));
      await h.tap(byKey('cmb-save'));
      final put = h.server.callsTo(cmbSettings, method: 'PUT').single;
      expect(((put.body! as Map)['channels'] as Map)['delivery'], isTrue);
      await h.expectToast('Combo settings saved');
    });

    testWidgets('SET-SHL-018 Enter in the margin box saves', (tester) async {
      final h = await pumpCombos(tester);
      await h.enterText(byKey('cmb-margin'), '20');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(h.server.callsTo(cmbSettings, method: 'PUT'), hasLength(1));
      await h.expectToast('Combo settings saved');
    });
  });

  group('branch exceptions', () {
    testWidgets('SET-CMB-010 the card and its hint', (tester) async {
      final h = await pumpCombos(tester);
      expect(paneText('Branch exceptions'), findsOneWidget);
      expect(paneText(h.t('combos.settings.branchesHint')), findsOneWidget);
      expect(paneText('No branches yet.'), findsNothing);
    });

    testWidgets('SET-CMB-010 no SELLING branch (warehouses only): "No '
        'branches yet."', (tester) async {
      final m = cmbServer();
      final none = [
        for (final r in m.db['branches'].rows)
          if (r['org_id'] == SeedIds.sabahOrg) {...r, 'kind': 'warehouse'},
      ];
      m.server.fail('GET', '/branches', MockResponse.ok(none), times: null);
      await pumpCombos(tester, backend: m);
      expect(paneText('No branches yet.'), findsOneWidget);
      expect(byKey('cmb-branch-table'), findsNothing);
    });

    testWidgets('SET-CMB-010 branches still loading: a skeleton, never "No '
        'branches yet."', (tester) async {
      final m = cmbServer();
      final gate = m.server.hold('GET', '/branches');
      final h = await pumpCombos(tester, backend: m);
      expect(byKey('cmb-branches-loading'), findsOneWidget);
      expect(paneText('No branches yet.'), findsNothing);
      gate.release();
      await h.settle();
      expect(byKey('cmb-branch-table'), findsOneWidget);
    });

    testWidgets('SET-CMB-011 one row per selling branch, the four channels, '
        'saved values; Follow names the SAVED org switch', (tester) async {
      final m = cmbServer();
      final branches = m.db['branches'];
      branches.insert({
        ...branches.get(SeedIds.zamalek),
        'id': 'wh-main',
        'name': 'Main Warehouse',
        'code': 'WH',
        'kind': 'warehouse',
      }, timestamps: false);
      final h = await pumpCombos(tester, backend: m);
      final table = byKey('cmb-branch-table');
      for (final head in [
        'BRANCH',
        'POS',
        'QR TABLE MENU',
        'ONLINE ORDERING',
        'DELIVERY APPS',
      ]) {
        expect(
          find.descendant(of: table, matching: find.text(head)),
          findsOneWidget,
        );
      }
      for (final name in ['Heliopolis', 'Maadi', 'New Cairo', 'Zamalek']) {
        expect(
          find.descendant(of: table, matching: find.text(name)),
          findsOneWidget,
        );
      }
      expect(paneText('Main Warehouse'), findsNothing);
      expect(byKey('cmb-row-wh-main'), findsNothing);

      String shown(String b, ComboChannel c) {
        final w = cellWidget(tester, b, c);
        return w.options.firstWhere((o) => o.value == w.value).label;
      }

      expect(shown(SeedIds.zamalek, ComboChannel.qr), 'Off here');
      expect(shown(SeedIds.newCairo, ComboChannel.delivery), 'On here');
      expect(shown(SeedIds.maadi, ComboChannel.pos), 'Follow (on)');
      expect(shown(SeedIds.maadi, ComboChannel.delivery), 'Follow (off)');
      expect(
        cellWidget(tester, SeedIds.maadi, ComboChannel.qr).semanticLabel,
        'Maadi: QR table menu',
      );
      // An unsaved flip above does not change what "Follow" says.
      await h.tap(sellSwitch(ComboChannel.delivery));
      expect(shown(SeedIds.maadi, ComboChannel.delivery), 'Follow (off)');
    });

    testWidgets('SET-CMB-012 a cell saves at once: the merged override, the '
        'row busy until the re-read, the toast', (tester) async {
      final m = cmbServer();
      final h = await pumpCombos(tester, backend: m);
      final gate = m.server.hold('PUT', cmbBranch);
      final reads = h.server.callsTo(cmbSettings).length;
      await pickCell(h, SeedIds.zamalek, ComboChannel.pos, 'Off here');
      for (final c in ComboChannel.values) {
        expect(cellWidget(tester, SeedIds.zamalek, c).enabled, isFalse);
      }
      expect(
        cellWidget(tester, SeedIds.maadi, ComboChannel.pos).enabled,
        isTrue,
      );
      gate.release();
      await h.settle();
      final put = h.server.callsTo(cmbBranch, method: 'PUT').single;
      expect(put.path, '/settings/combos/branches/${SeedIds.zamalek}');
      expect(put.body, {
        'pos': false,
        'qr': false,
        'online': null,
        'delivery': null,
      });
      await h.expectToast('Branch exception saved');
      expect(h.server.callsTo(cmbSettings).length, greaterThan(reads));
      expect(storedOverride(m.db, SeedIds.zamalek)!['pos'], isFalse);
      final w = cellWidget(tester, SeedIds.zamalek, ComboChannel.pos);
      expect(w.value, ComboTri.off);
      expect(w.enabled, isTrue);
    });

    testWidgets('SET-CMB-013 a change that leaves nothing set deletes the '
        'override', (tester) async {
      final m = cmbServer();
      final h = await pumpCombos(tester, backend: m);
      await pickCell(h, SeedIds.zamalek, ComboChannel.qr, 'Follow (on)');
      expect(h.server.callsTo(cmbBranch, method: 'PUT'), isEmpty);
      final del = h.server.callsTo(cmbBranch, method: 'DELETE').single;
      expect(del.path, '/settings/combos/branches/${SeedIds.zamalek}');
      await h.expectToast('Branch exception saved');
      expect(storedOverride(m.db, SeedIds.zamalek), isNull);
      expect(
        cellWidget(tester, SeedIds.zamalek, ComboChannel.qr).value,
        ComboTri.inherit,
      );
    });

    testWidgets('SET-CMB-014 a failed cell: the server\'s words, the saved '
        'value back', (tester) async {
      final m = cmbServer();
      final boom = MockResponse.error(500, 'Database is resting');
      m.server.fail('PUT', cmbBranch, boom);
      final h = await pumpCombos(tester, backend: m);
      await pickCell(h, SeedIds.maadi, ComboChannel.online, 'Off here');
      await h.expectToast(h.refusalWords(boom));
      final w = cellWidget(tester, SeedIds.maadi, ComboChannel.online);
      expect(w.value, ComboTri.inherit);
      expect(w.enabled, isTrue);
      expect(storedOverride(m.db, SeedIds.maadi), isNull);
    });

    testWidgets('SET-CMB-014 a manager-only branch refusal is worded', (
      tester,
    ) async {
      final m = cmbServer();
      final denied = MockResponse.denied('menu.combos.edit');
      m.server.fail('DELETE', cmbBranch, denied);
      final h = await pumpCombos(tester, backend: m);
      await pickCell(
        h,
        SeedIds.newCairo,
        ComboChannel.delivery,
        'Follow (off)',
      );
      await h.expectToast(h.refusalWords(denied));
      expect(storedOverride(m.db, SeedIds.newCairo), isNotNull);
    });

    testWidgets('SET-CMB-018 (divergence) a branch change keeps unsaved edits '
        'above', (tester) async {
      final h = await pumpCombos(tester);
      await h.enterText(byKey('cmb-margin'), '33');
      await h.tap(sellSwitch(ComboChannel.online));
      await pickCell(h, SeedIds.heliopolis, ComboChannel.qr, 'Off here');
      await h.expectToast('Branch exception saved');
      expect(tester.widget<EditableText>(marginInput()).controller.text, '33');
      expect(
        tester.widget<DashSwitch>(sellSwitch(ComboChannel.online)).value,
        isFalse,
      );
      expect(saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('SET-CMB-018 an edit undone after a refresh shows the fresh '
        'value', (tester) async {
      final m = cmbServer();
      final h = await pumpCombos(tester, backend: m);
      await h.tap(sellSwitch(ComboChannel.online));
      // Another tab saves a new margin; the branch change re-reads it while
      // the form is edited, so it stays.
      m.db[ComboSettingsMock.margins].put({
        'id': SeedIds.sabahOrg,
        'combo_min_margin': '0.2000',
      });
      await pickCell(h, SeedIds.heliopolis, ComboChannel.qr, 'Off here');
      await h.expectToast('Branch exception saved');
      expect(tester.widget<EditableText>(marginInput()).controller.text, '55');
      // Undone: the form is untouched again and shows the fresh answer.
      await h.tap(sellSwitch(ComboChannel.online));
      expect(tester.widget<EditableText>(marginInput()).controller.text, '20');
      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('SET-CMB-011 phone: one block per branch, a line per channel', (
      tester,
    ) async {
      final m = cmbServer();
      final h = await pumpCombos(tester, backend: m, size: DashSize.phone);
      expect(byKey('cmb-branch-table'), findsNothing);
      expect(byKey('cmb-branch-list'), findsOneWidget);
      await pickCell(h, SeedIds.maadi, ComboChannel.pos, 'Off here');
      await h.expectToast('Branch exception saved');
      expect(storedOverride(m.db, SeedIds.maadi)!['pos'], isFalse);
    });

    testWidgets('SET-CMB-011 a narrow pane scrolls the table sideways', (
      tester,
    ) async {
      final h = await pumpCombos(tester);
      tester.view.physicalSize = const Size(800, 900) * DashSize.pixelRatio;
      await h.settle();
      final table = byKey('cmb-branch-table');
      expect(table, findsOneWidget);
      expect(tester.getSize(table).width, 576);
      expect(
        find.ancestor(of: table, matching: find.byType(SingleChildScrollView)),
        findsWidgets,
      );
    });
  });

  testWidgets('SET-CMB-016 the path the combos pages link to opens this pane', (
    tester,
  ) async {
    final h = await pumpSetup(tester);
    await h.go('/settings/combos');
    expect(h.location.path, '/settings/combos');
    expect(byKey('cmb-channels'), findsOneWidget);
  });

  testWidgets('intent: the page has no read behind a press (every control '
      'writes); resting on them asks nothing', (tester) async {
    final h = await pumpCombos(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final before = h.server.calls.length;
    for (final f in [
      cell(SeedIds.heliopolis, ComboChannel.pos),
      sellSwitch(ComboChannel.qr),
      byKey('cmb-margin'),
    ]) {
      await mouse.moveTo(tester.getCenter(f));
      await h.settle();
    }
    expect(h.server.calls.length, before);
  });
}
