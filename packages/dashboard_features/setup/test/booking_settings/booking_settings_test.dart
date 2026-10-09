// The Bookings settings pane and its rules dialog, one driven test per
// SET-BKG row, through the real app shell on the mock server.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final String _helio = '?branchId=${SeedIds.heliopolis}';

Finder _hours(int dow, String box) => find.descendant(
  of: rulesKey('bkg-hours-$dow'),
  matching: byKey('bkg-hours-$box'),
);

void main() {
  group('the pane', () {
    testWidgets('SET-BKG-001 the header and description', (tester) async {
      await pumpBookingRules(tester);
      expect(inPane(find.text('Bookings')), findsOneWidget);
      expect(
        inPane(find.text('Slots, party sizes, holds and the phone code.')),
        findsOneWidget,
      );
    });

    testWidgets('SET-BKG-002 SET-BKG-021 the branch select: every selling '
        'branch by its stored name, inactive included, no warehouse', (
      tester,
    ) async {
      final m = bkgServer();
      final branches = m.db['branches'];
      branches.insert({
        ...branches.get(SeedIds.zamalek),
        'id': 'wh-main',
        'name': 'Main Warehouse',
        'code': 'WH',
        'kind': 'warehouse',
      }, timestamps: false);
      branches.get(SeedIds.maadi)['is_active'] = false;
      final h = await pumpBookingRules(tester, backend: m);
      final select = tester.widget<DashSelect<String>>(byKey('bkg-branch'));
      expect(select.placeholder, 'Pick a branch');
      expect(select.value, isNull);
      expect([for (final o in select.options) o.label], [
        'Heliopolis',
        'Maadi',
        'New Cairo',
        'Zamalek',
      ]);
      // 256 wide from 640 px.
      expect(tester.getSize(byKey('bkg-branch')).width, 256);
      await pickBranch(h, 'Maadi');
      expect(
        tester.widget<DashSelect<String>>(byKey('bkg-branch')).value,
        SeedIds.maadi,
      );
    });

    testWidgets('SET-BKG-002 phone: the select is full width', (tester) async {
      await pumpBookingRules(tester, size: DashSize.phone);
      final card = tester.getSize(byKey('bkg-card')).width;
      expect(tester.getSize(byKey('bkg-branch')).width, card - 2 * 20);
    });

    testWidgets('SET-BKG-003 Edit rules waits for a branch; the per-branch '
        'note', (tester) async {
      final h = await pumpBookingRules(tester);
      expect(
        tester.widget<DashButton>(byKey('bkg-edit')).onPressed,
        isNull,
      );
      expect(inPane(find.text(h.t('settings.bookingsPerBranch'))), findsOneWidget);
      await pickBranch(h, 'Heliopolis');
      expect(
        tester.widget<DashButton>(byKey('bkg-edit')).onPressed,
        isNotNull,
      );
      expect(h.server.callsTo(bkgSettings), isEmpty, reason: 'read on open');
    });

    testWidgets('SET-BKG-021 no org in scope: an empty select, Edit rules '
        'off, nothing asked', (tester) async {
      final h = await pumpBookingRules(
        tester,
        persona: Persona.platform,
        pickOrg: false,
      );
      final select = tester.widget<DashSelect<String>>(byKey('bkg-branch'));
      expect(select.options, isEmpty);
      expect(tester.widget<DashButton>(byKey('bkg-edit')).onPressed, isNull);
      expect(h.server.callsTo(bkgSettings), isEmpty);
    });

    testWidgets('SET-BKG-021 the pick is page-local: independent of the '
        'header, gone after leaving', (tester) async {
      final h = await pumpBookingRules(tester, query: _helio);
      expect(
        tester.widget<DashSelect<String>>(byKey('bkg-branch')).value,
        isNull,
        reason: 'not the header branch',
      );
      await pickBranch(h, 'Zamalek');
      await h.go('/settings');
      await h.go(bkgPath);
      expect(
        tester.widget<DashSelect<String>>(byKey('bkg-branch')).value,
        isNull,
      );
    });
  });

  group('the rules dialog', () {
    testWidgets('SET-BKG-004 opens with its title and hint and reads the '
        'branch\'s rules; "Loading…" until they arrive, Save off', (
      tester,
    ) async {
      final m = bkgServer();
      final gate = m.server.hold('GET', bkgSettings);
      final h = await pumpBookingRules(tester, backend: m);
      await openRules(h, 'Heliopolis');
      expect(inRules(find.text('Booking settings')), findsOneWidget);
      expect(inRules(find.text(h.t('bookings.settingsHint'))), findsOneWidget);
      expect(inRules(find.text('Loading…')), findsOneWidget);
      expect(rulesSave(tester).onPressed, isNull);
      gate.release();
      await h.settle();
      expect(rulesKey('bkg-form'), findsOneWidget);
      expect(rulesSave(tester).onPressed, isNotNull);
      expect(
        h.server.callsTo(bkgSettings).single.query['branch_id'],
        [SeedIds.heliopolis],
      );
    });

    testWidgets('SET-BKG-004 (divergence) a failed read shows its words and '
        'Retry instead of "Loading…" for ever', (tester) async {
      final m = bkgServer();
      final boom = MockResponse.error(500, 'Database is resting');
      m.server.fail('GET', bkgSettings, boom);
      final h = await pumpBookingRules(tester, backend: m);
      await openRules(h, 'Maadi');
      expect(rulesKey('bkg-failed'), findsOneWidget);
      expect(inRules(find.text(h.refusalWords(boom))), findsOneWidget);
      expect(rulesSave(tester).onPressed, isNull);
      await h.tap(inRules(find.text('Retry')));
      expect(rulesKey('bkg-form'), findsOneWidget);
      expect(h.server.callsTo(bkgSettings), hasLength(2));
    });

    testWidgets('SET-BKG-005 SET-BKG-006 the two switches, with hints, as '
        'stored', (tester) async {
      final h = await pumpBookingRules(tester);
      await openRules(h, 'Heliopolis');
      for (final k in [
        'bookings.enabled',
        'bookings.enabledHint',
        'bookings.requireOtp',
        'bookings.requireOtpHint',
      ]) {
        expect(inRules(find.text(h.t(k))), findsOneWidget, reason: k);
      }
      expect(tester.widget<DashSwitch>(rulesKey('bkg-enabled')).value, isTrue);
      expect(tester.widget<DashSwitch>(rulesKey('bkg-require_otp')).value, isTrue);
      await h.tap(rulesKey('bkg-enabled'));
      await h.tap(rulesKey('bkg-require_otp'));
      final body = await saveRules(h);
      expect(body['enabled'], isFalse);
      expect(body['require_otp'], isFalse);
      await h.expectToast('Changes saved');
    });

    testWidgets('SET-BKG-007 seven days Sunday → Saturday; ticking adds '
        '12:00–23:00, unticking says Closed', (tester) async {
      final m = bkgServer();
      final h = await pumpBookingRules(tester, backend: m);
      await openRules(h, 'Maadi');
      expect(inRules(find.text('Booking hours')), findsOneWidget);
      const days = [
        'Sunday',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
      ];
      for (final (i, d) in days.indexed) {
        expect(
          find.descendant(of: rulesKey('bkg-hours-$i'), matching: find.text(d)),
          findsOneWidget,
        );
      }
      final monday = find.descendant(
        of: rulesKey('bkg-hours-1'),
        matching: find.byType(DashCheckbox),
      );
      await h.tap(monday);
      expect(
        find.descendant(of: rulesKey('bkg-hours-1'), matching: find.text('Closed')),
        findsOneWidget,
      );
      await h.tap(monday);
      expect(tester.widget<DashTextInput>(_hours(1, 'open')).value, '12:00');
      expect(tester.widget<DashTextInput>(_hours(1, 'close')).value, '23:00');
      await h.tap(
        find.descendant(
          of: rulesKey('bkg-hours-3'),
          matching: find.byType(DashCheckbox),
        ),
      );
      final body = await saveRules(h);
      final hours = (body['hours']! as List).cast<Map>();
      expect([for (final e in hours) e['dow']], [0, 1, 2, 4, 5, 6]);
      expect(hours[1], {'dow': 1, 'open': '12:00', 'close': '23:00'});
      await h.expectToast('Changes saved');
    });

    testWidgets('SET-BKG-007 Arabic day names', (tester) async {
      final h = await pumpBookingRules(tester, locale: 'ar');
      await openRules(h, 'Heliopolis');
      expect(
        find.descendant(of: rulesKey('bkg-hours-0'), matching: find.text('الأحد')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rulesKey('bkg-hours-5'), matching: find.text('الجمعة')),
        findsOneWidget,
      );
    });

    testWidgets('SET-BKG-008 the times: free text, LTR, monospace, '
        'placeholders; the hint', (tester) async {
      final h = await pumpBookingRules(tester);
      await openRules(h, 'Heliopolis');
      final open = tester.widget<DashTextInput>(_hours(5, 'open'));
      expect(open.value, '13:00');
      expect(open.placeholder, '12:00');
      expect(open.mono, isTrue);
      expect(open.textDirection, TextDirection.ltr);
      expect(tester.widget<DashTextInput>(_hours(5, 'close')).placeholder, '23:00');
      expect(inRules(find.text(h.t('bookings.hoursHint'))), findsOneWidget);
      await h.enterText(_hours(2, 'close'), '02:30');
      final body = await saveRules(h);
      final tue = (body['hours']! as List).cast<Map>().firstWhere(
        (e) => e['dow'] == 2,
      );
      expect(tue['close'], '02:30');
      await h.expectToast('Changes saved');
    });

    testWidgets('SET-BKG-009 slot length 15 / 30 / 60', (tester) async {
      final h = await pumpBookingRules(tester);
      await openRules(h, 'Heliopolis');
      final seg = tester.widget<DashSegmentedControl<int>>(
        rulesKey('bkg-slot_minutes'),
      );
      expect([for (final o in seg.options) o.label], ['15', '30', '60']);
      expect(seg.value, 30);
      await h.tap(
        find.descendant(of: rulesKey('bkg-slot_minutes'), matching: find.text('60')),
      );
      expect((await saveRules(h))['slot_minutes'], 60);
      await h.expectToast('Changes saved');
    });

    testWidgets('SET-BKG-010 SET-BKG-011 the numbers: two columns, an emptied '
        'field is 0, a blank optional one is null', (tester) async {
      final h = await pumpBookingRules(tester);
      await openRules(h, 'Heliopolis');
      for (final k in [
        'bookings.defaultDuration',
        'bookings.minParty',
        'bookings.maxParty',
        'bookings.maxPartyHint',
        'bookings.leadTime',
        'bookings.leadTimeHint',
        'bookings.horizon',
        'bookings.hold',
        'bookings.holdHint',
        'bookings.autoNoShow',
        'bookings.autoNoShowHint',
        'bookings.reminder',
        'bookings.reminderHint',
        'bookings.coversCap',
        'bookings.coversCapHint',
      ]) {
        expect(inRules(find.text(h.t(k))), findsOneWidget, reason: k);
      }
      // Two columns: duration and smallest party share a line.
      expect(
        tester.getTopLeft(rulesKey('bkg-default_duration_minutes')).dy,
        tester.getTopLeft(rulesKey('bkg-min_party')).dy,
      );
      await h.enterText(rulesKey('bkg-lead_time_minutes'), '');
      await h.enterText(rulesKey('bkg-max_party'), '10');
      await h.enterText(rulesKey('bkg-auto_no_show_minutes'), '');
      await h.enterText(rulesKey('bkg-max_covers_per_slot'), '');
      await h.enterText(rulesKey('bkg-reminder_lead_minutes'), '60');
      final body = await saveRules(h);
      expect(body['lead_time_minutes'], 0);
      expect(body['max_party'], 10);
      expect(body['reminder_lead_minutes'], 60);
      expect(body.containsKey('auto_no_show_minutes'), isTrue);
      expect(body['auto_no_show_minutes'], isNull);
      expect(body['max_covers_per_slot'], isNull);
      await h.expectToast('Changes saved');
    });

    testWidgets('SET-BKG-012 SET-BKG-013 blackout dates: remove, add '
        '(sorted, no repeats, picker clears), the hint', (tester) async {
      final m = bkgServer();
      final h = await pumpBookingRules(tester, backend: m);
      await openRules(h, 'Heliopolis');
      expect(inRules(find.text('2026-10-31')), findsOneWidget);
      expect(inRules(find.text(h.t('bookings.blackoutsHint'))), findsOneWidget);
      final add = rulesKey('bkg-blackout-add');
      expect(tester.widget<DashButton>(add).onPressed, isNull);
      expect(
        tester.widget<DashDateField>(rulesKey('bkg-blackout-date')).disablePast,
        isTrue,
      );
      await h.tap(rulesKey('bkg-blackout-date'));
      await h.tap(find.text('20').last);
      await h.tap(add);
      expect(inRules(find.text('2026-10-20')), findsOneWidget);
      expect(tester.widget<DashButton>(add).onPressed, isNull, reason: 'cleared');
      // The same day again cannot be added twice.
      await h.tap(rulesKey('bkg-blackout-date'));
      await h.tap(find.text('20').last);
      expect(tester.widget<DashButton>(add).onPressed, isNull);
      await h.tap(
        find.descendant(
          of: rulesKey('bkg-blackout-2026-10-31'),
          matching: find.bySemanticsLabel('Remove'),
        ),
      );
      expect(inRules(find.text('2026-10-31')), findsNothing);
      final body = await saveRules(h);
      expect(body['blackout_dates'], ['2026-10-20']);
      await h.expectToast('Changes saved');
      expect(storedRules(m.db, SeedIds.heliopolis)!['blackout_dates'], [
        '2026-10-20',
      ]);
    });

    testWidgets('SET-BKG-014 Save sends the whole object, toasts, refreshes '
        '/bookings and /floor and closes', (tester) async {
      final m = bkgServer();
      final h = await pumpBookingRules(tester, backend: m);
      await openRules(h, 'New Cairo');
      final bookingsEpoch = h.container.read(
        realtimeEpochProvider('/bookings/settings'),
      );
      final floorEpoch = h.container.read(realtimeEpochProvider('/floor/tables'));
      final body = await saveRules(h);
      expect(body.keys.toSet(), {
        'branch_id',
        'enabled',
        'hours',
        'slot_minutes',
        'default_duration_minutes',
        'min_party',
        'max_party',
        'lead_time_minutes',
        'horizon_days',
        'hold_minutes',
        'auto_no_show_minutes',
        'reminder_lead_minutes',
        'require_otp',
        'max_covers_per_slot',
        'blackout_dates',
      });
      expect(body['branch_id'], SeedIds.newCairo);
      expect(body['slot_minutes'], 15);
      await h.expectToast('Changes saved');
      expect(find.byType(BookingRulesDialog), findsNothing);
      expect(
        h.container.read(realtimeEpochProvider('/bookings/settings')),
        bookingsEpoch + 1,
      );
      expect(
        h.container.read(realtimeEpochProvider('/floor/tables')),
        floorEpoch + 1,
      );
    });

    testWidgets('SET-BKG-015 a refused Save: the server\'s words, the dialog '
        'stays, nothing stored', (tester) async {
      final m = bkgServer();
      final h = await pumpBookingRules(tester, backend: m);
      await openRules(h, 'Heliopolis');
      await h.enterText(_hours(1, 'open'), 'noon');
      await h.tap(rulesKey('bkg-save'));
      await h.expectToast(
        h.refusalWords(
          MockResponse.badRequest('hours.open / hours.close must be HH:MM'),
        ),
      );
      expect(find.byType(BookingRulesDialog), findsOneWidget);
      expect(rulesSave(tester).onPressed, isNotNull);
      final monday = (storedRules(m.db, SeedIds.heliopolis)!['hours']! as List)
          .cast<Map>()
          .firstWhere((e) => e['dow'] == 1);
      expect(monday['open'], '09:00');
    });

    testWidgets('SET-BKG-015 the server checks the numbers', (tester) async {
      final h = await pumpBookingRules(tester);
      await openRules(h, 'Heliopolis');
      await h.enterText(rulesKey('bkg-hold_minutes'), '500');
      await h.tap(rulesKey('bkg-save'));
      await h.expectToast(
        h.refusalWords(
          MockResponse.badRequest('hold_minutes must be between 0 and 180'),
        ),
      );
      expect(find.byType(BookingRulesDialog), findsOneWidget);
    });

    testWidgets('SET-BKG-016 Cancel and Esc close without saving; reopening '
        'starts from the stored rules', (tester) async {
      final h = await pumpBookingRules(tester);
      await openRules(h, 'Heliopolis');
      await h.tap(rulesKey('bkg-enabled'));
      await h.tap(rulesKey('bkg-cancel'));
      expect(find.byType(BookingRulesDialog), findsNothing);
      await h.tap(byKey('bkg-edit'));
      expect(tester.widget<DashSwitch>(rulesKey('bkg-enabled')).value, isTrue);
      await h.tap(rulesKey('bkg-enabled'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(find.byType(BookingRulesDialog), findsNothing);
      expect(h.server.callsTo(bkgSettings, method: 'PUT'), isEmpty);
      await h.tap(byKey('bkg-edit'));
      expect(tester.widget<DashSwitch>(rulesKey('bkg-enabled')).value, isTrue);
    });

    testWidgets('SET-BKG-017 another branch opens on ITS rules, never the '
        'previous branch\'s draft', (tester) async {
      final m = bkgServer();
      final h = await pumpBookingRules(tester, backend: m);
      await openRules(h, 'Heliopolis');
      await h.tap(rulesKey('bkg-cancel'));
      final gate = m.server.hold('GET', bkgSettings);
      await openRules(h, 'Zamalek');
      expect(inRules(find.text('Loading…')), findsOneWidget);
      expect(rulesSave(tester).onPressed, isNull);
      gate.release();
      await h.settle();
      expect(tester.widget<DashSwitch>(rulesKey('bkg-enabled')).value, isFalse);
      final body = await saveRules(h);
      expect(body['branch_id'], SeedIds.zamalek);
      await h.expectToast('Changes saved');
    });

    testWidgets('SET-BKG-018 672 wide from 640 px', (tester) async {
      final h = await pumpBookingRules(tester);
      await openRules(h, 'Heliopolis');
      final wide = tester.getSize(find.byType(BookingRulesDialog)).width;
      expect(wide, lessThanOrEqualTo(672));
    });

    testWidgets('SET-BKG-018 phone: full width, one column', (tester) async {
      final p = await pumpBookingRules(tester, size: DashSize.phone);
      await openRules(p, 'Heliopolis');
      expect(
        tester.getTopLeft(rulesKey('bkg-default_duration_minutes')).dy,
        lessThan(tester.getTopLeft(rulesKey('bkg-min_party')).dy),
      );
      expect(
        tester.getSize(find.byType(BookingRulesDialog)).width,
        greaterThan(380),
      );
    });

    testWidgets('SET-BKG-019 (refusal) a manager outside the branch: the read '
        'is refused and worded', (tester) async {
      final h = await pumpBookingRules(tester, persona: Persona.manager);
      await openRules(h, 'Heliopolis');
      expect(rulesKey('bkg-failed'), findsOneWidget);
      final call = h.server.callsTo(bkgSettings).single;
      expect(call.status, 403);
    });

    testWidgets('SET-BKG-019 (refusal) a manager at their own branch edits '
        'its rules', (tester) async {
      final h = await pumpBookingRules(tester, persona: Persona.manager);
      await openRules(h, 'Zamalek');
      expect(rulesKey('bkg-form'), findsOneWidget);
      await h.tap(rulesKey('bkg-enabled'));
      expect((await saveRules(h))['enabled'], isTrue);
      await h.expectToast('Changes saved');
    });

    testWidgets('SET-BKG-019 (refusal) no bookings.read: the page renders, the '
        'read is refused in words', (tester) async {
      final h = await pumpBookingRules(tester, persona: Persona.limited);
      expect(inPane(find.text('Bookings')), findsOneWidget);
      await openRules(h, 'Maadi');
      expect(
        inRules(find.text(h.refusalWords(MockResponse.denied('bookings.read')))),
        findsOneWidget,
      );
    });

    testWidgets('SET-BKG-019 (refusal) a refused Save toasts and stays open', (
      tester,
    ) async {
      final m = bkgServer();
      final denied = MockResponse.denied('bookings.edit');
      m.server.fail('PUT', bkgSettings, denied);
      final o = await pumpBookingRules(tester, backend: m);
      await openRules(o, 'Maadi');
      await o.tap(rulesKey('bkg-save'));
      await o.expectToast(o.refusalWords(denied));
      expect(find.byType(BookingRulesDialog), findsOneWidget);
    });

    testWidgets('SET-BKG-020 (divergence) a booking.* event re-reads; the '
        'untouched draft follows, an edited one is kept', (tester) async {
      final m = bkgServer();
      final h = await pumpBookingRules(tester, backend: m, query: _helio);
      await openRules(h, 'Heliopolis');
      final reads = h.server.callsTo(bkgSettings).length;
      storedRules(m.db, SeedIds.heliopolis)!['max_party'] = 12;
      h.realtime.current!.emit('booking.created', data: '{}');
      await h.settle();
      expect(h.server.callsTo(bkgSettings).length, reads + 1);
      expect(tester.widget<DashTextInput>(rulesKey('bkg-max_party')).value, '12');

      await h.enterText(rulesKey('bkg-min_party'), '2');
      storedRules(m.db, SeedIds.heliopolis)!['max_party'] = 14;
      h.realtime.current!.emit('booking.updated', data: '{}');
      await h.settle();
      expect(tester.widget<DashTextInput>(rulesKey('bkg-max_party')).value, '12');
      expect(tester.widget<DashTextInput>(rulesKey('bkg-min_party')).value, '2');
    });
  });

  testWidgets('intent: resting on Edit rules warms the dialog\'s read; the '
      'press opens it from the cache', (tester) async {
    final h = await pumpBookingRules(tester);
    await pickBranch(h, 'Maadi');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    expect(h.server.callsTo(bkgSettings), isEmpty);
    await mouse.moveTo(tester.getCenter(byKey('bkg-edit')));
    await h.settle();
    expect(h.server.callsTo(bkgSettings), hasLength(1), reason: 'warmed');
    expect(h.server.callsTo(bkgSettings).single.query['branch_id'], [
      SeedIds.maadi,
    ]);
    await h.tap(byKey('bkg-edit'));
    expect(rulesKey('bkg-form'), findsOneWidget);
    expect(h.server.callsTo(bkgSettings), hasLength(1), reason: 'from cache');
  });
}
