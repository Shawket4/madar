// `/bookings` driven through the real app shell (SELL-BKG rows), the page:
// reads, day navigation, the list and its actions, the timeline, export,
// deep links, live refresh and refusals. The dialogs have their own files.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/area_seed.dart';
import 'package:dashboard_sell/src/bookings/booking_dialog.dart';
import 'package:dashboard_sell/src/bookings/bookings_timeline.dart';
import 'package:dashboard_sell/src/customers/customer_sheet.dart';
import 'package:dashboard_sell/src/customers/people_widgets.dart' show LinkText;
import 'package:dashboard_sell/src/orders/order_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

String _name(int customer) => MockSeed.instance.customers[customer].name;

final String _nada = _name(0);
final String _lateGuest = _name(5);
final String _dueGuest = _name(9);
const String _bigParty = 'Mostafa Hegazy';

/// [label] in the open "…" menu (it floats in the overlay).
Finder _menuItem(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuList'),
  matching: find.text(label),
);

Future<void> _openMenu(DashHarness h, String bookingId) =>
    h.tap(actionsOf(bookingId));

Finder _confirm(String label) => find.descendant(
  of: find.byType(DashConfirmDialog),
  matching: find.text(label),
);

void main() {
  testWidgets('SELL-BKG-001 no branch: pick one, and nothing is read', (
    tester,
  ) async {
    final h = await pumpBookings(tester, noBranch: true);
    expect(pageText('Bookings'), findsOneWidget);
    expect(
      pageText('Select a branch in the top bar to see its bookings'),
      findsOneWidget,
    );
    expect(h.server.callsTo(dayTemplate), isEmpty);
    expect(h.server.callsTo(settingsTemplate), isEmpty);
    expect(h.server.callsTo(tablesTemplate), isEmpty);
  });

  testWidgets('SELL-BKG-002/003 header and the three reads, keyed as the web', (
    tester,
  ) async {
    final h = await pumpBookings(tester);
    expect(
      pageText(
        'Reserve tables for guests, then seat them from the POS when they arrive.',
      ),
      findsOneWidget,
    );
    expect(
      inPage(find.byKey(const ValueKey('bookings-export'))),
      findsOneWidget,
    );
    expect(pageText('Settings'), findsOneWidget);
    expect(pageText('New booking'), findsOneWidget);
    expect(h.server.callsTo(settingsTemplate).single.query, {
      'branch_id': [SeedIds.heliopolis],
    });
    expect(h.server.callsTo(tablesTemplate).single.query, {
      'branch_id': [SeedIds.heliopolis],
    });
    expect(h.server.callsTo(dayTemplate).single.query, {
      'branch_id': [SeedIds.heliopolis],
      'date': [today],
    });
  });

  testWidgets(
    'SELL-BKG-004/035 every 30 s the day is read again and Late/Due follow the clock',
    (tester) async {
      final h = await pumpBookings(tester);
      expect(pageText('Late'), findsOneWidget);
      expect(pageText('Due'), findsOneWidget);
      final reads = h.server.callsTo(dayTemplate).length;
      h.db!.clock.advance(const Duration(minutes: 16));
      await tester.pump(const Duration(seconds: 30));
      await h.settle();
      expect(h.server.callsTo(dayTemplate).length, reads + 1);
      // 10:16: the 10:15 party is late now, nobody is merely due.
      expect(pageText('Late'), findsNWidgets(2));
      expect(pageText('Due'), findsNothing);
    },
  );

  testWidgets('SELL-BKG-005 previous, next, Today and the day picker', (
    tester,
  ) async {
    final h = await pumpBookings(tester);
    expect(inPage(find.byKey(const ValueKey('bookings-today'))), findsNothing);
    await h.tap(find.byKey(const ValueKey('bookings-next-day')));
    expect(h.server.callsTo(dayTemplate).last.query['date'], ['2026-10-09']);
    expect(
      inPage(find.byKey(const ValueKey('bookings-today'))),
      findsOneWidget,
    );
    await h.tap(find.byKey(const ValueKey('bookings-prev-day')));
    await h.tap(find.byKey(const ValueKey('bookings-prev-day')));
    expect(h.server.callsTo(dayTemplate).last.query['date'], ['2026-10-07']);
    await h.tap(find.byKey(const ValueKey('bookings-today')));
    expect(inPage(find.byKey(const ValueKey('bookings-today'))), findsNothing);
    expect(pageText(_nada), findsOneWidget);
    // The picker: open it and choose the 20th.
    await h.tap(find.byKey(const ValueKey('bookings-date')));
    await h.tap(find.text('20').last);
    expect(h.server.callsTo(dayTemplate).last.query['date'], ['2026-10-20']);
  });

  testWidgets('SELL-BKG-005 the chevrons point the reading way in Arabic', (
    tester,
  ) async {
    await pumpBookings(tester, locale: 'ar');
    DashIconButton btn(String k) =>
        tester.widget<DashIconButton>(find.byKey(ValueKey(k)));
    expect(btn('bookings-prev-day').icon, 'chevron-right');
    expect(btn('bookings-next-day').icon, 'chevron-left');
  });

  testWidgets('SELL-BKG-006 the view starts on List and switches to Timeline', (
    tester,
  ) async {
    final h = await pumpBookings(tester);
    expect(
      inPage(find.byKey(const ValueKey('bookings-table'))),
      findsOneWidget,
    );
    await h.tap(inPage(find.text('Timeline')));
    expect(inPage(find.byType(BookingsTimeline)), findsOneWidget);
    expect(inPage(find.byKey(const ValueKey('bookings-table'))), findsNothing);
  });

  testWidgets('SELL-BKG-007 online booking off: the notice (Zamalek only)', (
    tester,
  ) async {
    await pumpBookings(tester, branchId: SeedIds.zamalek);
    expect(pageText('Online booking is off for this branch'), findsOneWidget);
  });

  testWidgets('SELL-BKG-007 online booking on: no notice', (tester) async {
    await pumpBookings(tester);
    expect(pageText('Online booking is off for this branch'), findsNothing);
  });

  testWidgets('SELL-BKG-008 the day\'s stats, skeletons while loading', (
    tester,
  ) async {
    final s = bookingsServer();
    final gate = s.server.hold('GET', dayTemplate);
    final h = await pumpBookings(tester, s: s);
    expect(inPage(find.byType(DashSkeleton)), findsWidgets);
    gate.release();
    await h.settle();
    String valueOf(String label) {
      final card = find.ancestor(
        of: pageText(label),
        matching: find.byType(DashStatCard),
      );
      return tester.widget<DashStatCard>(card).value.toString();
    }

    expect(valueOf('Bookings'), '7');
    expect(valueOf('Covers seated'), '5');
    expect(valueOf('Seated now'), '1');
    expect(valueOf('No-shows'), '0');
  });

  testWidgets(
    'SELL-BKG-009/080 needs a table: the alert lists every flagged booking and opens it',
    (tester) async {
      final s = bookingsServer();
      // A cancelled booking with no table is listed too.
      final t = s.db[SellTables.bookings];
      t.find(heliBooking(7))!['table_ids'] = <String>[];
      final h = await pumpBookings(tester, s: s);
      expect(pageText('2 booking(s) have no table'), findsOneWidget);
      final btn = find.byKey(ValueKey('needs-table-${heliBooking(5)}'));
      expect(
        tester
            .widget<DashButton>(btn)
            .label
            .replaceAll(RegExp('[\u2066-\u2069]'), ''),
        '01:00 PM · $_bigParty · 6',
      );
      await h.tap(btn);
      expect(inDialog(find.text('Edit booking')), findsOneWidget);
    },
  );

  testWidgets('SELL-BKG-010/023 the status filter, Active first', (
    tester,
  ) async {
    final h = await pumpBookings(tester);
    Finder table(String s) => find.descendant(
      of: find.byKey(const ValueKey('bookings-table')),
      matching: find.text(s),
    );
    // Active: confirmed + seated.
    expect(table(_nada), findsOneWidget);
    expect(table(_name(21)), findsNothing, reason: 'completed');
    expect(table(_name(30)), findsNothing, reason: 'cancelled');
    await h.tap(inPage(find.text('All')));
    expect(table(_name(21)), findsOneWidget);
    expect(table(_name(30)), findsOneWidget);
    await h.tap(
      find.descendant(
        of: find.byKey(const ValueKey('bookings-filter')),
        matching: find.text('Cancelled'),
      ),
    );
    expect(table(_name(30)), findsOneWidget);
    expect(table(_nada), findsNothing);
    await h.tap(
      find.descendant(
        of: find.byKey(const ValueKey('bookings-filter')),
        matching: find.text('No-show'),
      ),
    );
    expect(pageText('Nothing matches this filter'), findsOneWidget);
    expect(pageText('New booking'), findsOneWidget, reason: 'header only');
  });

  testWidgets(
    'SELL-BKG-011/012/013/014 the columns: time, guest, party, tables, status',
    (tester) async {
      await pumpBookings(tester);
      expect(pageText('09:45 AM'), findsOneWidget);
      expect(pageText('until 11:15 AM'), findsOneWidget);
      // Online, Late and Due.
      expect(pageText('Online'), findsNWidgets(2));
      final late = find.ancestor(
        of: pageText('Late'),
        matching: find.byType(Column),
      );
      expect(
        find.descendant(of: late.first, matching: find.text(_lateGuest)),
        findsOneWidget,
      );
      final due = find.ancestor(
        of: pageText('Due'),
        matching: find.byType(Column),
      );
      expect(
        find.descendant(of: due.first, matching: find.text(_dueGuest)),
        findsOneWidget,
      );
      // The phone, as read, and the notes.
      expect(pageText('+20 100 123 4567'), findsWidgets);
      expect(
        inPage(find.textContaining('Birthday — bring the candle')),
        findsOneWidget,
      );
      // Party, tables, status.
      expect(pageText('Needs a table'), findsOneWidget);
      expect(pageText('T1'), findsOneWidget);
      expect(pageText('Seated'), findsWidgets);
      expect(pageText('Confirmed'), findsWidgets);
    },
  );

  testWidgets('SELL-BKG-015 a row opens its edit dialog only while active', (
    tester,
  ) async {
    final h = await pumpBookings(tester);
    await h.tap(pageText('09:45 AM'));
    expect(inDialog(find.text('Edit booking')), findsOneWidget);
    await h.tap(inDialog(find.text('Cancel')));
    expect(find.byType(BookingDialog), findsNothing);
    await h.tap(inPage(find.text('All')));
    await h.tap(pageText('09:00 AM'));
    expect(find.byType(BookingDialog), findsNothing);
  });

  testWidgets('SELL-BKG-016 the row menu follows the status', (tester) async {
    final h = await pumpBookings(tester);
    await _openMenu(h, heliBooking(3));
    for (final w in ['Edit', 'Mark seated', 'No-show', 'Cancel booking']) {
      expect(_menuItem(w), findsOneWidget, reason: w);
    }
    expect(_menuItem('Complete'), findsNothing);
    await h.tap(_menuItem('Edit'));
    expect(inDialog(find.text('Edit booking')), findsOneWidget);
    await h.tap(inDialog(find.text('Cancel')));
    await _openMenu(h, heliBooking(2));
    expect(_menuItem('Complete'), findsOneWidget);
    expect(_menuItem('Mark seated'), findsNothing);
    expect(_menuItem('No-show'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    await h.tap(inPage(find.text('All')));
    await _openMenu(h, heliBooking(7));
    final item = tester.widget<DashMenu>(
      find.ancestor(
        of: actionsOf(heliBooking(7)),
        matching: find.byType(DashMenu),
      ),
    );
    expect(item.items.single.label, 'Cancelled');
    expect(item.items.single.enabled, isFalse);
  });

  testWidgets(
    'SELL-BKG-017/080 Mark seated: at once, a toast, bookings and floor refetch',
    (tester) async {
      final h = await pumpBookings(tester);
      final days = h.server.callsTo(dayTemplate).length;
      final floor = h.server.callsTo(tablesTemplate).length;
      await _openMenu(h, heliBooking(3));
      await h.tap(_menuItem('Mark seated'));
      final call = h.server.callsTo('/bookings/{id}/seat').single;
      expect(call.path, '/bookings/${heliBooking(3)}/seat');
      expect(call.body, <String, Object?>{});
      await h.expectToast('Marked as seated');
      expect(h.server.callsTo(dayTemplate).length, greaterThan(days));
      expect(h.server.callsTo(tablesTemplate).length, greaterThan(floor));
      expect(
        h.db![SellTables.bookings].find(heliBooking(3))!['status'],
        'seated',
      );
    },
  );

  testWidgets('SELL-BKG-018/080 Complete: at once, a toast', (tester) async {
    final h = await pumpBookings(tester);
    await _openMenu(h, heliBooking(2));
    await h.tap(_menuItem('Complete'));
    expect(
      h.server.callsTo('/bookings/{id}/complete').single.path,
      '/bookings/${heliBooking(2)}/complete',
    );
    await h.expectToast('Booking completed');
    expect(pageText(_nada), findsNothing, reason: 'no longer active');
  });

  testWidgets('SELL-BKG-019 No-show asks first, then marks', (tester) async {
    final h = await pumpBookings(tester);
    await _openMenu(h, heliBooking(4));
    await h.tap(_menuItem('No-show'));
    expect(find.text('Mark $_dueGuest as a no-show?'), findsOneWidget);
    expect(
      find.text('The table is released for other parties.'),
      findsOneWidget,
    );
    await h.tap(_confirm('No-show'));
    expect(
      h.server.callsTo('/bookings/{id}/no-show').single.path,
      '/bookings/${heliBooking(4)}/no-show',
    );
    await h.expectToast('Marked as no-show');
  });

  testWidgets('SELL-BKG-019 No-show dismissed: nothing is sent', (
    tester,
  ) async {
    final h = await pumpBookings(tester);
    await _openMenu(h, heliBooking(4));
    await h.tap(_menuItem('No-show'));
    await h.tap(_confirm('Cancel'));
    expect(h.server.callsTo('/bookings/{id}/no-show'), isEmpty);
  });

  testWidgets('SELL-BKG-020 Cancel booking asks, then tells the guest', (
    tester,
  ) async {
    final h = await pumpBookings(tester);
    await _openMenu(h, heliBooking(6));
    await h.tap(_menuItem('Cancel booking'));
    expect(find.text("Cancel ${_name(14)}'s booking?"), findsOneWidget);
    expect(
      find.text('The guest is told by WhatsApp and the table is released.'),
      findsOneWidget,
    );
    await h.tap(_confirm('Cancel booking'));
    expect(h.server.callsTo('/bookings/{id}/cancel').single.body, {
      'reason': null,
      'notify_guest': true,
    });
    await h.expectToast('Booking cancelled');
  });

  testWidgets('SELL-BKG-021 the list loads (skeleton) and fails (Retry)', (
    tester,
  ) async {
    final s = bookingsServer();
    s.server.fail('GET', dayTemplate, MockResponse.error(500, 'boom'));
    final h = await pumpBookings(tester, s: s);
    expect(pageText("Couldn't load this"), findsOneWidget);
    expect(pageText('boom'), findsOneWidget);
    final before = h.server.callsTo(dayTemplate).length;
    final settings = h.server.callsTo(settingsTemplate).length;
    await h.tap(inPage(find.text('Retry')));
    expect(h.server.callsTo(dayTemplate).length, before + 1);
    expect(h.server.callsTo(settingsTemplate).length, settings);
    expect(pageText(_nada), findsOneWidget);
  });

  testWidgets('SELL-BKG-022 an empty day says so and offers New booking', (
    tester,
  ) async {
    final h = await pumpBookings(tester, path: '/bookings?date=2026-11-20');
    expect(pageText('No bookings for this day'), findsOneWidget);
    expect(
      pageText(
        'Take one by phone with “New booking”, or turn on online booking in Settings.',
      ),
      findsOneWidget,
    );
    final export = tester.widget<DashExportButton>(
      find.byKey(const ValueKey('bookings-export')),
    );
    expect(export.enabled, isFalse, reason: 'SELL-BKG-033: nothing that day');
    await h.tap(
      find.descendant(
        of: find.byType(DashEmptyState),
        matching: find.text('New booking'),
      ),
    );
    expect(inDialog(find.text('New booking')), findsOneWidget);
  });

  testWidgets('SELL-BKG-024 fifty to a page, paged in the browser', (
    tester,
  ) async {
    final s = bookingsServer();
    final base = s.db[SellTables.bookings].find(heliBooking(6))!;
    for (var i = 0; i < 55; i++) {
      s.db[SellTables.bookings].insert({
        ...base,
        'id': 'extra-$i',
        'guest_name': 'Guest $i',
      }, timestamps: false);
    }
    final h = await pumpBookings(tester, s: s);
    expect(pageText('Page 1 of 2'), findsOneWidget);
    expect(h.server.callsTo(dayTemplate), hasLength(1));
    expect(
      inPage(find.text('Columns')),
      findsNothing,
      reason: 'no Columns menu',
    );
  });

  testWidgets('SELL-BKG-025 phone: cards titled by the guest', (tester) async {
    final h = await pumpBookings(tester, size: DashSize.phone);
    expect(pageText(_nada), findsOneWidget);
    expect(pageText('Party'), findsWidgets);
    expect(pageText('Tables'), findsWidgets);
    await h.tap(actionsOf(heliBooking(3)));
    expect(_menuItem('Mark seated'), findsOneWidget);
  });

  testWidgets(
    'SELL-BKG-026/028 the timeline: a row per table, hour ticks, blocks that open',
    (tester) async {
      final h = await pumpBookings(tester);
      await h.tap(inPage(find.text('Timeline')));
      final tl = find.byType(BookingsTimeline);
      Finder inTl(Finder f) => find.descendant(of: tl, matching: f);
      expect(inTl(find.text('Table')), findsOneWidget);
      expect(inTl(find.text('T1 · 4')), findsOneWidget);
      expect(inTl(find.text('T9 · 4')), findsNothing, reason: 'inactive');
      expect(inTl(find.text('Needs a table')), findsOneWidget);
      expect(inTl(find.text('09:00 AM')), findsOneWidget);
      expect(inTl(find.text('11:00 PM')), findsOneWidget);
      // Active only: the completed and cancelled ones are not drawn.
      expect(inTl(find.text('${_name(21)} · 2')), findsNothing);
      expect(inTl(find.text('$_nada · 3')), findsOneWidget);
      final seated = find.byKey(ValueKey('timeline-block-${heliBooking(2)}'));
      expect(
        find.descendant(
          of: seated,
          matching: find.byWidgetPredicate(
            (w) => w is DashIcon && w.name == 'armchair',
          ),
        ),
        findsOneWidget,
      );
      final due = find.byKey(ValueKey('timeline-block-${heliBooking(4)}'));
      expect(
        find.descendant(
          of: due,
          matching: find.byWidgetPredicate(
            (w) => w is DashIcon && w.name == 'calendar-clock',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byTooltip('$_dueGuest · 4 · 10:15 AM–11:45 AM'),
        findsOneWidget,
      );
      await h.tap(due);
      expect(inDialog(find.text('Edit booking')), findsOneWidget);
    },
  );

  testWidgets('SELL-BKG-027 a Friday past midnight spans the whole day', (
    tester,
  ) async {
    final h = await pumpBookings(tester, path: '/bookings?date=2026-10-09');
    await h.tap(inPage(find.text('Timeline')));
    final tl = find.byType(BookingsTimeline);
    expect(
      find.descendant(of: tl, matching: find.text('12:00 AM')),
      findsWidgets,
    );
    expect(
      find.descendant(of: tl, matching: find.text('11:00 PM')),
      findsOneWidget,
    );
  });

  testWidgets('SELL-BKG-029 the timeline with no tables', (tester) async {
    final s = bookingsServer();
    s.db[SellTables.floorTables].removeWhere(
      (t) => t['branch_id'] == SeedIds.heliopolis,
    );
    final h = await pumpBookings(tester, s: s);
    await h.tap(inPage(find.text('Timeline')));
    expect(pageText('This branch has no tables yet'), findsOneWidget);
    expect(
      pageText('Draw the floor first; bookings claim its tables.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'SELL-BKG-076 (divergence) a failed tables read is an error, not "no tables"',
    (tester) async {
      final s = bookingsServer();
      s.server.fail(
        'GET',
        tablesTemplate,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpBookings(tester, s: s);
      await h.tap(inPage(find.text('Timeline')));
      expect(pageText('This branch has no tables yet'), findsNothing);
      expect(pageText('boom'), findsOneWidget);
      s.server.clearFailures();
      await h.tap(inPage(find.text('Retry')));
      expect(pageText('T1 · 4'), findsOneWidget);
    },
  );

  testWidgets('SELL-BKG-076 (divergence) the timeline waits for its reads', (
    tester,
  ) async {
    final s = bookingsServer();
    final h = await pumpBookings(tester, s: s);
    final gate = s.server.hold('GET', dayTemplate);
    await h.tap(find.byKey(const ValueKey('bookings-next-day')));
    await h.tap(inPage(find.text('Timeline')));
    expect(inPage(find.byType(DashSkeleton)), findsWidgets);
    gate.release();
    await h.settle();
    expect(pageText('T1 · 4'), findsOneWidget);
  });

  testWidgets('SELL-BKG-075 the timeline reads right to left in Arabic', (
    tester,
  ) async {
    final h = await pumpBookings(tester, locale: 'ar');
    await h.tap(inPage(find.text(h.t('bookings.viewTimeline'))));
    final tl = find.byType(BookingsTimeline);
    final nine = tester.getCenter(
      find.descendant(of: tl, matching: find.text('09:00 ص')),
    );
    final ten = tester.getCenter(
      find.descendant(of: tl, matching: find.text('10:00 ص')),
    );
    expect(nine.dx, greaterThan(ten.dx));
    final label = tester.getCenter(
      find.descendant(of: tl, matching: find.text(h.t('bookings.table'))),
    );
    expect(label.dx, greaterThan(nine.dx));
  });

  testWidgets('SELL-BKG-030 ?date= opens that day', (tester) async {
    final h = await pumpBookings(tester, path: '/bookings?date=2026-10-10');
    expect(h.server.callsTo(dayTemplate).single.query['date'], ['2026-10-10']);
    expect(
      inPage(find.byKey(const ValueKey('bookings-today'))),
      findsOneWidget,
    );
  });

  testWidgets(
    'SELL-BKG-031/077 ?booking= opens its dialog (any status) and leaves the URL',
    (tester) async {
      final h = await pumpBookings(
        tester,
        path: '/bookings?date=$today&booking=${heliBooking(7)}',
      );
      expect(inDialog(find.text('Edit booking')), findsOneWidget);
      expect(h.location.queryParameters.containsKey('booking'), isFalse);
      expect(h.location.queryParameters.containsKey('date'), isFalse);
      // The filter went to All.
      await h.tap(inDialog(find.byKey(const ValueKey('booking-submit'))));
      final patch = h.server.callsTo('/bookings/{id}', method: 'PATCH').single;
      expect(patch.path, '/bookings/${heliBooking(7)}');
      expect(
        inDialog(find.text('A cancelled booking cannot be changed')),
        findsOneWidget,
      );
      await h.tap(inDialog(find.text('Cancel')));
      expect(pageText(_name(30)), findsOneWidget, reason: 'All');
    },
  );

  testWidgets('SELL-BKG-031 an unknown ?booking= just leaves the URL', (
    tester,
  ) async {
    final h = await pumpBookings(tester, path: '/bookings?booking=nope');
    expect(find.byType(BookingDialog), findsNothing);
    expect(h.location.queryParameters.containsKey('booking'), isFalse);
  });

  testWidgets('SELL-BKG-032 the guest name opens the read-only customer', (
    tester,
  ) async {
    final h = await pumpBookings(tester);
    await h.tap(pageText(_nada));
    expect(find.byType(CustomerSheet), findsOneWidget);
    expect(
      h.server.callsTo('/customers/{id}').single.path,
      '/customers/${MockSeed.instance.customers[0].id}',
    );
    // One of the customer's orders: the customer sheet closes and the order
    // opens in a sheet of its own, with no Void.
    // Recent orders close the sheet: the last link in it is an order.
    await h.tap(
      find
          .descendant(
            of: find.byType(CustomerSheet),
            matching: find.byType(LinkText),
          )
          .last,
    );
    expect(find.byType(CustomerSheet), findsNothing);
    final sheet = tester.widget<OrderSheet>(find.byType(OrderSheet));
    expect(sheet.onVoid, isNull);
  });

  testWidgets(
    'SELL-BKG-033/034 export: the day re-read as an export, filtered, every column',
    (tester) async {
      final h = await pumpBookings(tester);
      await h.tap(find.byKey(const ValueKey('bookings-export')));
      final call = h.server.callsTo(dayTemplate).last;
      expect(call.headers['X-Madar-Export'], '1');
      expect(call.query['date'], [today]);
      expect(
        h.files.saved.single.filename,
        'Madar-Bookings-2026-10-08-2026-10-08.xlsx',
      );
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.title, 'Bookings');
      expect(
        sheet.subtitle,
        startsWith('Active  ·  2026-10-08  ·  Generated: '),
      );
      expect(sheet.columns.map((c) => c.header), [
        'Time',
        'Ends',
        'Guest',
        'Phone',
        'Party',
        'Tables',
        'Status',
        'Source',
        'Notes',
      ]);
      expect(sheet.rows, hasLength(5));
      final big = sheet.rows.firstWhere((r) => r[2] == _bigParty);
      expect(big.sublist(4, 9), [
        6,
        'Needs a table',
        'Confirmed',
        'Taken here',
        'Business lunch, needs a quiet corner.',
      ]);
      expect(sheet.rows.firstWhere((r) => r[2] == _dueGuest)[7], 'Online');
      await h.expectToast('Exported 5 rows');
    },
  );

  testWidgets('SELL-BKG-033 export failure and the export throttle', (
    tester,
  ) async {
    final s = bookingsServer();
    final h = await pumpBookings(tester, s: s);
    s.server.fail(
      'GET',
      dayTemplate,
      MockResponse.error(429, 'Too many exports', code: 'EXPORT_RATE_LIMITED'),
    );
    await h.tap(find.byKey(const ValueKey('bookings-export')));
    await h.expectToast('Too many exports just now. Try again in a minute.');
    expect(h.files.saved, isEmpty);
    final export = tester.widget<DashExportButton>(
      find.byKey(const ValueKey('bookings-export')),
    );
    expect(export.loading, isFalse);
  });

  testWidgets('SELL-BKG-033 a filter matching nothing: nothing to export', (
    tester,
  ) async {
    final h = await pumpBookings(tester);
    await h.tap(
      find.descendant(
        of: find.byKey(const ValueKey('bookings-filter')),
        matching: find.text('No-show'),
      ),
    );
    await h.tap(find.byKey(const ValueKey('bookings-export')));
    await h.expectToast('Nothing to export');
    expect(h.files.saved, isEmpty);
  });

  testWidgets(
    'SELL-ALL-006 a booking.* event refreshes the day and the floor',
    (tester) async {
      final h = await pumpBookings(tester);
      final days = h.server.callsTo(dayTemplate).length;
      final floor = h.server.callsTo(tablesTemplate).length;
      h.realtime.current!.emit('booking.changed', data: '{}');
      await h.settle();
      expect(h.server.callsTo(dayTemplate).length, days + 1);
      expect(h.server.callsTo(tablesTemplate).length, floor + 1);
    },
  );

  testWidgets(
    'SELL-BKG-074 (refusal) without bookings.read the page renders and its reads refuse',
    (tester) async {
      final h = await pumpBookings(
        tester,
        persona: Persona.limited,
        branchId: SeedIds.maadi,
      );
      expect(
        pageText("You don't have permission to perform this action."),
        findsOneWidget,
      );
      // New booking still opens; the save is refused on the dialog's line.
      await h.tap(inPage(find.text('New booking')));
      expect(inDialog(find.text('New booking')), findsOneWidget);
      expect(
        inDialog(
          find.text(
            'No booking hours on this day — set a custom time below to force one.',
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SELL-BKG-074 (refusal) a row action without bookings.edit toasts the refusal',
    (tester) async {
      final s = bookingsServer();
      s.server.fail(
        'POST',
        '/bookings/{id}/seat',
        MockResponse.denied('bookings.edit'),
      );
      final h = await pumpBookings(tester, s: s);
      await _openMenu(h, heliBooking(3));
      await h.tap(_menuItem('Mark seated'));
      await h.expectToast("You don't have permission to perform this action.");
    },
  );

  testWidgets('SELL-BKG-074 the manager works their own branch', (
    tester,
  ) async {
    final h = await pumpBookings(
      tester,
      persona: Persona.manager,
      branchId: SeedIds.zamalek,
    );
    expect(h.server.callsTo(dayTemplate).single.query['branch_id'], [
      SeedIds.zamalek,
    ]);
    expect(
      pageText("You don't have permission to perform this action."),
      findsNothing,
    );
  });

  testWidgets('SELL-BKG-004 coming back to the app reads the day again', (
    tester,
  ) async {
    final h = await pumpBookings(tester);
    final reads = h.server.callsTo(dayTemplate).length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(h.server.callsTo(dayTemplate).length, reads + 1);
  });

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.tablet, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    for (final date in [today, '2026-10-09']) {
      testWidgets(
        'SELL-BKG-026 the hour labels never overlap (${size.name} $lang $date)',
        (tester) async {
          final h = await pumpBookings(
            tester,
            size: size,
            locale: lang,
            path: '/bookings?date=$date',
          );
          await h.tap(inPage(find.text(h.t('bookings.viewTimeline'))));
          final hour = RegExp(r'^\d\d:00 (AM|PM|ص|م)$');
          final rects = [
            for (final e
                in find
                    .descendant(
                      of: find.byType(BookingsTimeline),
                      matching: find.byType(Text),
                    )
                    .evaluate())
              if (hour.hasMatch((e.widget as Text).data ?? ''))
                tester.getRect(find.byWidget(e.widget)),
          ]..sort((a, b) => a.left.compareTo(b.left));
          expect(rects.length, greaterThan(10));
          for (var i = 1; i < rects.length; i++) {
            expect(
              rects[i].left,
              greaterThanOrEqualTo(rects[i - 1].right),
              reason: 'label $i overlaps its neighbour',
            );
          }
        },
      );
    }
  }
}
