// The booking dialog (SELL-BKG-036 … 059, 078), driven from the page.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/area_seed.dart';
import 'package:dashboard_sell/src/bookings/booking_dialog.dart';
import 'package:dashboard_sell/src/shared/phone.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// 18:00 Cairo today, the slot most tests choose.
const String _six = '2026-10-08T15:00:00.000Z';

Finder _k(String key) => inDialog(find.byKey(ValueKey(key)));

Future<DashHarness> _openNew(
  WidgetTester tester, {
  ({MockServer server, MockDb db})? s,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  Persona persona = Persona.owner,
}) async {
  final h = await pumpBookings(
    tester,
    s: s,
    size: size,
    locale: locale,
    persona: persona,
  );
  await h.tap(find.byKey(const ValueKey('bookings-new')));
  return h;
}

Future<DashHarness> _openEdit(WidgetTester tester, {int n = 3}) async {
  final h = await pumpBookings(tester);
  await h.tap(find.byKey(ValueKey('booking-actions-${heliBooking(n)}')));
  await h.tap(find.text('Edit').last);
  return h;
}

Future<void> _guest(
  DashHarness h, {
  String name = 'Sara',
  String phone = '01001234567',
}) async {
  await h.enterText(_k('booking-name'), name);
  await h.enterText(_k('booking-phone'), phone);
}

Finder _switch(String label) => inDialog(
  find.byWidgetPredicate((w) => w is DashSwitch && w.semanticLabel == label),
);

bool _switchOn(WidgetTester tester, String label) =>
    tester.widget<DashSwitch>(_switch(label)).value;

void main() {
  testWidgets('SELL-BKG-036 New booking: the blank form', (tester) async {
    final h = await _openNew(tester);
    expect(inDialog(find.text('New booking')), findsOneWidget);
    expect(
      inDialog(
        find.text(
          'Pick a time the room can take; a table is assigned automatically.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<DashDateField>(inDialog(find.byType(DashDateField))).value,
      DateTime(2026, 10, 8),
    );
    expect(inDialog(find.text('2')), findsWidgets);
    expect(inDialog(find.textContaining('Chosen:')), findsNothing);
    expect(inDialog(find.text('Anywhere')), findsOneWidget);
    expect(_switchOn(tester, 'Choose tables myself'), isFalse);
    expect(_switchOn(tester, 'Book even if no table fits'), isFalse);
    expect(_switchOn(tester, 'Send WhatsApp confirmation'), isTrue);
    expect(h.server.callsTo(availabilityTemplate).single.query, {
      'branch_id': [SeedIds.heliopolis],
      'date': [today],
      'party_size': ['2'],
    });
    expect(h.server.callsTo(sectionsTemplate).single.query, {
      'branch_id': [SeedIds.heliopolis],
    });
  });

  testWidgets('SELL-BKG-037/053 Edit booking: prefilled, no WhatsApp switch', (
    tester,
  ) async {
    final h = await _openEdit(tester);
    final b = stored(h.db!).firstWhere((x) => x.id == heliBooking(3));
    expect(inDialog(find.text('Edit booking')), findsOneWidget);
    expect(
      inDialog(
        find.text(
          'Moving the time or party re-checks the tables; the guest gets a WhatsApp update.',
        ),
      ),
      findsOneWidget,
    );
    // 09:45 is not on the half-hour grid.
    expect(
      inDialog(find.text('Chosen: 09:45 AM · outside the booking slots')),
      findsOneWidget,
    );
    expect(inDialog(find.text('09:45')), findsOneWidget, reason: 'custom time');
    expect(
      tester
          .widget<DashTextInput>(
            find.descendant(
              of: _k('booking-duration'),
              matching: find.byType(DashTextInput),
            ),
          )
          .value,
      '90',
    );
    expect(inDialog(find.text(b.guestName)), findsOneWidget);
    expect(inDialog(find.text(formatPhoneInput(b.guestPhone))), findsOneWidget);
    expect(_switchOn(tester, 'Choose tables myself'), isTrue);
    expect(
      tester
          .widget<DashCheckbox>(
            find.descendant(
              of: _k('booking-table-${SellIds.table('heliopolis', 'T3')}'),
              matching: find.byType(DashCheckbox),
            ),
          )
          .value,
      isTrue,
    );
    expect(_switchOn(tester, 'Book even if no table fits'), isTrue);
    expect(inDialog(find.text('Send WhatsApp confirmation')), findsNothing);
    expect(
      h.server.callsTo(availabilityTemplate).last.query['exclude_booking_id'],
      [heliBooking(3)],
    );
  });

  testWidgets(
    'SELL-BKG-038 the date: past days off when creating; a new day clears the time',
    (tester) async {
      final h = await _openNew(tester);
      expect(
        tester
            .widget<DashDateField>(inDialog(find.byType(DashDateField)))
            .disablePast,
        isTrue,
      );
      await h.tap(_k('slot-$_six'));
      expect(inDialog(find.text('Chosen: 06:00 PM')), findsOneWidget);
      await h.tap(inDialog(find.byType(DashDateField)));
      await h.tap(find.text('20').last);
      expect(inDialog(find.textContaining('Chosen:')), findsNothing);
      expect(h.server.callsTo(availabilityTemplate).last.query['date'], [
        '2026-10-20',
      ]);
    },
  );

  testWidgets('SELL-BKG-038 editing may pick any day', (tester) async {
    await _openEdit(tester);
    expect(
      tester
          .widget<DashDateField>(inDialog(find.byType(DashDateField)))
          .disablePast,
      isFalse,
    );
  });

  testWidgets(
    'SELL-BKG-039/040 party re-asks availability; slots, chosen and full',
    (tester) async {
      final h = await _openNew(tester);
      // 26 slots for two: 09:00 … 09:30 PM.
      expect(inDialog(find.text('09:00 AM')), findsOneWidget);
      expect(inDialog(find.text('09:30 PM')), findsOneWidget);
      await h.enterText(_k('booking-party'), '20');
      expect(h.server.callsTo(availabilityTemplate).last.query['party_size'], [
        '20',
      ]);
      // Nothing seats twenty: every slot full, still choosable.
      expect(find.byTooltip('Full for this party'), findsWidgets);
      await h.tap(_k('slot-$_six'));
      expect(inDialog(find.text('Chosen: 06:00 PM')), findsOneWidget);
    },
  );

  testWidgets('SELL-BKG-041 a blackout day has no slots', (tester) async {
    final h = await pumpBookings(tester, path: '/bookings?date=2026-10-31');
    await h.tap(find.byKey(const ValueKey('bookings-new')));
    expect(
      inDialog(
        find.text(
          'No booking hours on this day — set a custom time below to force one.',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'SELL-BKG-042/043 a custom time: refused unless HH:MM; off the grid',
    (tester) async {
      final h = await _openNew(tester);
      await h.enterText(_k('booking-custom-time'), '7pm');
      await h.tap(_k('booking-use-time'));
      expect(inDialog(find.text('Enter a time as HH:MM')), findsOneWidget);
      await h.enterText(_k('booking-custom-time'), '19:45');
      await h.tap(_k('booking-use-time'));
      expect(inDialog(find.text('Enter a time as HH:MM')), findsNothing);
      expect(
        inDialog(find.text('Chosen: 07:45 PM · outside the booking slots')),
        findsOneWidget,
      );
    },
  );

  testWidgets('SELL-BKG-044 a full slot warns while tables are automatic', (
    tester,
  ) async {
    final h = await _openNew(tester);
    await h.enterText(_k('booking-party'), '20');
    await h.tap(_k('slot-$_six'));
    const hint =
        'No table fits this party then. Choose tables yourself, or force the booking and assign later.';
    expect(inDialog(find.text(hint)), findsOneWidget);
    await h.tap(_switch('Choose tables myself'));
    expect(inDialog(find.text(hint)), findsNothing);
  });

  testWidgets('SELL-BKG-045/046 name and phone are required, on their fields', (
    tester,
  ) async {
    final h = await _openNew(tester);
    await h.tap(_k('booking-submit'));
    expect(inDialog(find.text('Guest name is required')), findsOneWidget);
    expect(
      inDialog(find.text("Enter the guest's phone number")),
      findsOneWidget,
    );
    expect(h.server.callsTo('/bookings', method: 'POST'), isEmpty);
    await _guest(h, phone: '12345');
    await h.tap(_k('booking-submit'));
    expect(inDialog(find.text('Enter a valid phone number')), findsOneWidget);
    expect(h.server.callsTo('/bookings', method: 'POST'), isEmpty);
  });

  testWidgets('SELL-BKG-046 the phone refusal in Arabic', (tester) async {
    final h = await _openNew(tester, locale: 'ar');
    await _guest(h, phone: '12345');
    await h.tap(_k('booking-submit'));
    expect(inDialog(find.text('أدخل رقم هاتف صحيح')), findsOneWidget);
  });

  testWidgets('SELL-BKG-054 a valid guest still needs a time, then a party', (
    tester,
  ) async {
    final h = await _openNew(tester);
    await _guest(h, phone: '٠١٠٠١٢٣٤٥٦٧');
    await h.tap(_k('booking-submit'));
    expect(inDialog(find.text('Pick a time')), findsOneWidget);
    await h.tap(_k('slot-$_six'));
    await h.enterText(_k('booking-party'), '');
    await h.tap(_k('booking-submit'));
    expect(
      inDialog(find.text('Party size must be at least 1')),
      findsOneWidget,
    );
    expect(h.server.callsTo('/bookings', method: 'POST'), isEmpty);
  });

  testWidgets('SELL-BKG-047 a preferred section re-asks availability', (
    tester,
  ) async {
    final h = await _openNew(tester);
    await h.tap(_k('booking-section'));
    await h.tap(find.text('Terrace').last);
    expect(h.server.callsTo(availabilityTemplate).last.query['section_id'], [
      SellIds.section('heliopolis', 'terrace'),
    ]);
  });

  testWidgets('SELL-BKG-048/049/050/051/052 duration, notes, tables and force', (
    tester,
  ) async {
    final h = await _openNew(tester);
    final duration = find.descendant(
      of: _k('booking-duration'),
      matching: find.byType(DashTextInput),
    );
    expect(tester.widget<DashTextInput>(duration).placeholder, '90');
    expect(
      inDialog(find.text('Birthday, high chair, window seat…')),
      findsOneWidget,
    );
    expect(
      inDialog(
        find.text(
          'The smallest table that seats the party is picked; two tables in one section when needed.',
        ),
      ),
      findsOneWidget,
    );
    await h.tap(_k('slot-$_six'));
    expect(inDialog(find.text('Auto: T3')), findsOneWidget);
    await h.tap(_switch('Choose tables myself'));
    expect(
      inDialog(find.text('Selected: 0 seats for a party of 2')),
      findsOneWidget,
    );
    expect(
      _k('booking-table-${SellIds.table('heliopolis', 'T9')}'),
      findsNothing,
    );
    await h.tap(_k('booking-table-${SellIds.table('heliopolis', 'T1')}'));
    expect(
      inDialog(find.text('Selected: 4 seats for a party of 2')),
      findsOneWidget,
    );
    expect(
      inDialog(
        find.text('It shows under “needs a table” until you assign one.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'SELL-BKG-055 Confirm booking: the body, a toast, the day refetched, closed',
    (tester) async {
      final h = await _openNew(tester);
      final days = h.server.callsTo(dayTemplate).length;
      await _guest(h, name: '  Sara ', phone: '0100 123-4567');
      await h.tap(_k('slot-$_six'));
      await h.tap(_k('booking-submit'));
      expect(h.server.callsTo('/bookings', method: 'POST').single.body, {
        'branch_id': SeedIds.heliopolis,
        'party_size': 2,
        'starts_at': _six,
        'duration_minutes': null,
        'guest_name': 'Sara',
        'guest_phone': '201001234567',
        'notes': null,
        'section_id': null,
        'table_ids': null,
        'force': false,
        'send_confirmation': true,
      });
      await h.expectToast('Booking confirmed');
      expect(find.byType(BookingDialog), findsNothing);
      expect(h.server.callsTo(dayTemplate).length, greaterThan(days));
      expect(pageText('Sara'), findsOneWidget);
    },
  );

  testWidgets('SELL-BKG-055 chosen tables, duration and notes go as typed', (
    tester,
  ) async {
    final h = await _openNew(tester);
    await _guest(h);
    await h.tap(_k('slot-$_six'));
    await h.enterText(_k('booking-duration'), '120');
    await h.enterText(_k('booking-notes'), 'High chair');
    await h.tap(_switch('Choose tables myself'));
    await h.tap(_k('booking-table-${SellIds.table('heliopolis', 'T7')}'));
    await h.tap(_switch('Send WhatsApp confirmation'));
    await h.tap(_k('booking-submit'));
    final body =
        h.server.callsTo('/bookings', method: 'POST').single.body! as Map;
    expect(body['duration_minutes'], 120);
    expect(body['notes'], 'High chair');
    expect(body['table_ids'], [SellIds.table('heliopolis', 'T7')]);
    expect(body['send_confirmation'], isFalse);
    await h.expectToast('Booking confirmed');
  });

  testWidgets('SELL-BKG-056 Save an edit: the PATCH body, "" notes, a toast', (
    tester,
  ) async {
    final h = await _openEdit(tester, n: 4);
    await h.enterText(_k('booking-party'), '3');
    await h.tap(_k('booking-submit'));
    final call = h.server.callsTo('/bookings/{id}', method: 'PATCH').single;
    final b = stored(h.db!).firstWhere((x) => x.id == heliBooking(4));
    expect(call.path, '/bookings/${heliBooking(4)}');
    expect(call.body, {
      'party_size': 3,
      'starts_at': '2026-10-08T07:15:00.000Z',
      'duration_minutes': 90,
      'guest_name': b.guestName,
      'guest_phone': b.guestPhone,
      'notes': '',
      'section_id': null,
      'table_ids': [SellIds.table('heliopolis', 'T6')],
      'force': true,
    });
    await h.expectToast('Booking updated');
    expect(find.byType(BookingDialog), findsNothing);
  });

  testWidgets(
    'SELL-BKG-057 a refused save stays open with the server\'s words',
    (tester) async {
      final h = await _openNew(tester);
      await _guest(h);
      await h.enterText(_k('booking-party'), '40');
      await h.tap(_k('slot-$_six'));
      await h.tap(_k('booking-submit'));
      expect(
        inDialog(find.text('No table seats 40 at that time')),
        findsOneWidget,
      );
      expect(find.byType(BookingDialog), findsOneWidget);
    },
  );

  testWidgets('SELL-BKG-074 (refusal) a create without bookings.create', (
    tester,
  ) async {
    final s = bookingsServer();
    s.server.fail('POST', '/bookings', MockResponse.denied('bookings.create'));
    final h = await _openNew(tester, s: s);
    await _guest(h);
    await h.tap(_k('slot-$_six'));
    await h.tap(_k('booking-submit'));
    expect(
      inDialog(find.text("You don't have permission to perform this action.")),
      findsOneWidget,
    );
  });

  testWidgets('SELL-BKG-058 Cancel closes without a word sent', (tester) async {
    final h = await _openNew(tester);
    await h.tap(_k('booking-cancel'));
    expect(find.byType(BookingDialog), findsNothing);
    expect(h.server.callsTo('/bookings', method: 'POST'), isEmpty);
  });

  testWidgets(
    'SELL-BKG-059 desktop: at most 672 wide; phone: full screen, one column',
    (tester) async {
      await _openNew(tester);
      expect(
        tester.getSize(find.byType(BookingDialog)).width,
        lessThanOrEqualTo(672),
      );
      final name = tester.getTopLeft(_k('booking-name'));
      final phone = tester.getTopLeft(_k('booking-phone'));
      expect(name.dy, phone.dy, reason: 'side by side');
    },
  );

  testWidgets('SELL-BKG-059 phone: one column, full screen', (tester) async {
    await _openNew(tester, size: DashSize.phone);
    expect(
      tester.getSize(find.byType(BookingDialog)).width,
      DashSize.phone.size.width,
    );
    final name = tester.getTopLeft(_k('booking-name'));
    final phone = tester.getTopLeft(_k('booking-phone'));
    expect(phone.dy, greaterThan(name.dy));
  });

  testWidgets(
    'SELL-BKG-078 failed availability or a blank party: "no booking hours"',
    (tester) async {
      final s = bookingsServer();
      s.server.fail(
        'GET',
        availabilityTemplate,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await _openNew(tester, s: s);
      const none =
          'No booking hours on this day — set a custom time below to force one.';
      expect(inDialog(find.text(none)), findsOneWidget);
      s.server.clearFailures();
      final asked = h.server.callsTo(availabilityTemplate).length;
      await h.enterText(_k('booking-party'), '');
      expect(h.server.callsTo(availabilityTemplate).length, asked);
      expect(inDialog(find.text(none)), findsOneWidget);
    },
  );

  testWidgets(
    'SELL-BKG-078 party keeps the time; a new date keeps the custom box',
    (tester) async {
      final h = await _openNew(tester);
      await h.enterText(_k('booking-custom-time'), '18:00');
      await h.tap(_k('booking-use-time'));
      expect(inDialog(find.text('Chosen: 06:00 PM')), findsOneWidget);
      await h.enterText(_k('booking-party'), '4');
      expect(inDialog(find.text('Chosen: 06:00 PM')), findsOneWidget);
      await h.tap(inDialog(find.byType(DashDateField)));
      await h.tap(find.text('20').last);
      expect(inDialog(find.textContaining('Chosen:')), findsNothing);
      expect(inDialog(find.text('18:00')), findsOneWidget);
    },
  );

  testWidgets('SELL-BKG-040 a spinner beside Time while slots are fetched', (
    tester,
  ) async {
    final s = bookingsServer();
    final h = await _openNew(tester, s: s);
    expect(_k('booking-slots-busy'), findsNothing);
    final gate = s.server.hold('GET', availabilityTemplate);
    await h.enterText(_k('booking-party'), '4');
    expect(_k('booking-slots-busy'), findsOneWidget);
    gate.release();
    await h.settle();
    expect(_k('booking-slots-busy'), findsNothing);
    expect(inDialog(find.text('06:00 PM')), findsOneWidget);
  });

  testWidgets(
    'SELL-BKG-037 an untouched edit follows a fresh read; an edited one stays',
    (tester) async {
      final h = await _openEdit(tester, n: 4);
      String party() => tester
          .widget<EditableText>(
            find.descendant(
              of: _k('booking-party'),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;
      final row = h.db![SellTables.bookings].find(heliBooking(4))!;
      row['party_size'] = 5;
      h.realtime.current!.emit('booking.changed', data: '{}');
      await h.settle();
      expect(party(), '5', reason: 're-seeded from the fresh day');
      await h.enterText(_k('booking-name'), 'Edited');
      row['party_size'] = 6;
      h.realtime.current!.emit('booking.changed', data: '{}');
      await h.settle();
      expect(party(), '5', reason: 'an edit stops the re-seed');
      expect(inDialog(find.text('Edited')), findsOneWidget);
    },
  );
}
