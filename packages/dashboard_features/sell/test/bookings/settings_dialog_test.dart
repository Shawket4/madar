// The booking settings dialog (SELL-BKG-060 … 073, 079), from the page.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/area_seed.dart';
import 'package:dashboard_sell/src/bookings/booking_settings_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder _k(String key) => inSettings(find.byKey(ValueKey(key)));

Future<DashHarness> _open(
  WidgetTester tester, {
  ({MockServer server, MockDb db})? s,
  String locale = 'en',
  String? branchId,
}) async {
  final h = await pumpBookings(
    tester,
    s: s,
    locale: locale,
    branchId: branchId,
  );
  await h.tap(find.byKey(const ValueKey('bookings-settings')));
  return h;
}

Future<Map<String, Object?>> _save(DashHarness h) async {
  await h.tap(_k('settings-save'));
  return h.server.callsTo(settingsTemplate, method: 'PUT').single.body!
      as Map<String, Object?>;
}

void main() {
  testWidgets('SELL-BKG-060 opens on the branch\'s settings', (tester) async {
    final h = await _open(tester);
    expect(inSettings(find.text('Booking settings')), findsOneWidget);
    expect(
      inSettings(
        find.text(
          'How this branch takes bookings. Host bookings work regardless of the online switch.',
        ),
      ),
      findsOneWidget,
    );
    expect(h.server.callsTo(settingsTemplate).length, 1, reason: 'cached');
    expect(inSettings(find.text('Accept online bookings')), findsOneWidget);
  });

  testWidgets('SELL-BKG-060 "Loading…" until the settings arrive, Save off', (
    tester,
  ) async {
    final s = bookingsServer();
    final gate = s.server.hold('GET', settingsTemplate);
    final h = await _open(tester, s: s);
    expect(inSettings(find.text('Loading…')), findsOneWidget);
    expect(tester.widget<DashButton>(_k('settings-save')).onPressed, isNull);
    gate.release();
    await h.settle();
    expect(inSettings(find.text('Accept online bookings')), findsOneWidget);
  });

  testWidgets(
    'SELL-BKG-079 (divergence) a failed read shows the error and Retry',
    (tester) async {
      final s = bookingsServer();
      s.server.fail(
        'GET',
        settingsTemplate,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await _open(tester, s: s);
      expect(inSettings(find.text('boom')), findsOneWidget);
      expect(tester.widget<DashButton>(_k('settings-save')).onPressed, isNull);
      s.server.clearFailures();
      await h.tap(inSettings(find.text('Retry')));
      expect(inSettings(find.text('Accept online bookings')), findsOneWidget);
    },
  );

  testWidgets(
    'SELL-BKG-061/062/073 the switches, saved whole; a toast; the day refetched',
    (tester) async {
      final h = await _open(tester, branchId: SeedIds.zamalek);
      final days = h.server.callsTo(dayTemplate).length;
      await h.tap(_k('settings-enabled'));
      await h.tap(_k('settings-require_otp'));
      final body = await _save(h);
      expect(body['enabled'], isTrue);
      expect(body['require_otp'], isTrue);
      expect(body['branch_id'], SeedIds.zamalek);
      expect(body['hours'], hasLength(7));
      expect(body.containsKey('max_covers_per_slot'), isTrue);
      expect(body['max_covers_per_slot'], isNull);
      await h.expectToast('Changes saved');
      expect(find.byType(BookingSettingsDialog), findsNothing);
      expect(h.server.callsTo(dayTemplate).length, greaterThan(days));
      expect(pageText('Online booking is off for this branch'), findsNothing);
    },
  );

  testWidgets('SELL-BKG-063 hours: a day off, a day back on at 12:00–23:00', (
    tester,
  ) async {
    final h = await _open(tester);
    expect(inSettings(find.text('Sunday')), findsOneWidget);
    expect(inSettings(find.text('Saturday')), findsOneWidget);
    await h.tap(inSettings(find.bySemanticsLabel('Monday')));
    expect(inSettings(find.text('Closed')), findsOneWidget);
    await h.tap(inSettings(find.bySemanticsLabel('Monday')));
    await h.enterText(
      find.descendant(
        of: _k('settings-hours-0'),
        matching: find.byKey(const ValueKey('hours-close')),
      ),
      '22:30',
    );
    final hours = (await _save(h))['hours']! as List;
    expect(hours.firstWhere((e) => (e as Map)['dow'] == 1), {
      'dow': 1,
      'open': '12:00',
      'close': '23:00',
    });
    expect((hours.first as Map)['close'], '22:30');
    expect(hours.map((e) => (e as Map)['dow']), [0, 1, 2, 3, 4, 5, 6]);
    await h.expectToast('Changes saved');
  });

  testWidgets('SELL-BKG-063 the weekday names in Arabic', (tester) async {
    await _open(tester, locale: 'ar');
    expect(inSettings(find.text('الأحد')), findsOneWidget);
    expect(inSettings(find.text('الجمعة')), findsOneWidget);
  });

  testWidgets(
    'SELL-BKG-064/065/066/067/068/069/070/071 the numbers; blanks save 0 or null',
    (tester) async {
      final h = await _open(tester);
      await h.tap(
        find.descendant(
          of: _k('settings-slot_minutes'),
          matching: find.text('60'),
        ),
      );
      Future<void> type(String key, String v) =>
          h.enterText(_k('settings-$key'), v);
      await type('default_duration_minutes', '120');
      await type('min_party', '2');
      await type('max_party', '10');
      await type('lead_time_minutes', '');
      await type('horizon_days', '60');
      await type('hold_minutes', '20');
      await type('auto_no_show_minutes', '');
      await type('reminder_lead_minutes', '60');
      await type('max_covers_per_slot', '');
      expect(
        inSettings(find.text('Bigger groups are asked to call.')),
        findsOneWidget,
      );
      expect(
        inSettings(find.text('Blank = only when the booking window ends.')),
        findsOneWidget,
      );
      final body = await _save(h);
      expect(body['slot_minutes'], 60);
      expect(body['default_duration_minutes'], 120);
      expect(body['min_party'], 2);
      expect(body['max_party'], 10);
      expect(body['lead_time_minutes'], 0);
      expect(body['horizon_days'], 60);
      expect(body['hold_minutes'], 20);
      expect(body['auto_no_show_minutes'], isNull);
      expect(body.containsKey('auto_no_show_minutes'), isTrue);
      expect(body['reminder_lead_minutes'], 60);
      expect(body['max_covers_per_slot'], isNull);
      await h.expectToast('Changes saved');
    },
  );

  testWidgets('SELL-BKG-072 blackout dates: remove, add (sorted), no repeats', (
    tester,
  ) async {
    final h = await _open(tester);
    expect(inSettings(find.text('2026-10-31')), findsOneWidget);
    final add = _k('settings-blackout-add');
    expect(tester.widget<DashButton>(add).onPressed, isNull);
    await h.tap(_k('settings-blackout-date'));
    await h.tap(find.text('20').last);
    await h.tap(add);
    expect(inSettings(find.text('2026-10-20')), findsOneWidget);
    expect(tester.widget<DashButton>(add).onPressed, isNull, reason: 'cleared');
    await h.tap(
      find.descendant(
        of: _k('blackout-2026-10-31'),
        matching: find.bySemanticsLabel('Remove'),
      ),
    );
    expect(inSettings(find.text('2026-10-31')), findsNothing);
    final body = await _save(h);
    expect(body['blackout_dates'], ['2026-10-20']);
    await h.expectToast('Changes saved');
  });

  testWidgets('SELL-BKG-073 a refused save toasts and stays open', (
    tester,
  ) async {
    final h = await _open(tester);
    await h.enterText(
      find.descendant(
        of: _k('settings-hours-1'),
        matching: find.byKey(const ValueKey('hours-open')),
      ),
      'noon',
    );
    await h.tap(_k('settings-save'));
    await h.expectToast('hours.open / hours.close must be HH:MM');
    expect(find.byType(BookingSettingsDialog), findsOneWidget);
    final monday =
        (bookingSettingsRow(h.db!, SeedIds.heliopolis)!['hours']! as List)
            .cast<Map>()
            .firstWhere((e) => e['dow'] == 1);
    expect(monday['open'], '09:00', reason: 'nothing saved');
  });

  testWidgets('SELL-BKG-074 (refusal) a save without bookings.edit', (
    tester,
  ) async {
    final s = bookingsServer();
    s.server.fail(
      'PUT',
      settingsTemplate,
      MockResponse.denied('bookings.edit'),
    );
    final h = await _open(tester, s: s);
    await h.tap(_k('settings-save'));
    await h.expectToast("You don't have permission to perform this action.");
    expect(find.byType(BookingSettingsDialog), findsOneWidget);
  });

  testWidgets('SELL-BKG-073 Cancel closes; the next open starts afresh', (
    tester,
  ) async {
    final h = await _open(tester);
    await h.tap(_k('settings-enabled'));
    await h.tap(_k('settings-cancel'));
    expect(find.byType(BookingSettingsDialog), findsNothing);
    await h.tap(find.byKey(const ValueKey('bookings-settings')));
    expect(tester.widget<DashSwitch>(_k('settings-enabled')).value, isTrue);
    expect(h.server.callsTo(settingsTemplate, method: 'PUT'), isEmpty);
  });

  testWidgets(
    'SELL-BKG-079 opened on stale settings, the fresh read replaces the copy until an edit',
    (tester) async {
      final h = await pumpBookings(tester);
      bookingSettingsRow(h.db!, SeedIds.heliopolis)!['enabled'] = false;
      h.db!.clock.advance(const Duration(seconds: 31));
      await h.tap(find.byKey(const ValueKey('bookings-settings')));
      expect(h.server.callsTo(settingsTemplate), hasLength(2));
      expect(tester.widget<DashSwitch>(_k('settings-enabled')).value, isFalse);
      // Once something is typed, a later read no longer replaces it.
      await h.tap(_k('settings-require_otp'));
      bookingSettingsRow(h.db!, SeedIds.heliopolis)!['require_otp'] = true;
      h.realtime.current!.emit('booking.changed', data: '{}');
      await h.settle();
      expect(
        tester.widget<DashSwitch>(_k('settings-require_otp')).value,
        isFalse,
      );
      final body = await _save(h);
      expect(body['enabled'], isFalse);
      expect(body['require_otp'], isFalse);
      await h.expectToast('Changes saved');
    },
  );

  testWidgets(
    'SELL-BKG-073 a save refreshes the day even when the dialog closed mid-save',
    (tester) async {
      final s = bookingsServer();
      final h = await _open(tester, s: s);
      final gate = s.server.hold('PUT', settingsTemplate);
      final days = h.server.callsTo(dayTemplate).length;
      await h.tap(_k('settings-save'));
      Navigator.of(tester.element(find.byType(BookingSettingsDialog))).pop();
      await h.settle();
      expect(find.byType(BookingSettingsDialog), findsNothing);
      gate.release();
      await h.settle();
      expect(h.server.callsTo(dayTemplate).length, greaterThan(days));
    },
  );
}
