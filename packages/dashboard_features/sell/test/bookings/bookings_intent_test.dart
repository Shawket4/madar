// Intent warming on Bookings: a control the pointer rests on warms the reads
// its press makes, with the same keys, so the press asks nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/area_seed.dart';
import 'package:dashboard_sell/src/bookings/booking_dialog.dart';
import 'package:dashboard_sell/src/bookings/booking_settings_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

/// Rests [mouse] on [f], scrolled into view first.
Future<void> _rest(DashHarness h, TestGesture mouse, Finder f) async {
  await h.tester.ensureVisible(f);
  await h.settle();
  await mouse.moveTo(h.tester.getCenter(f));
  await h.settle();
}

/// The availability reads for [exclude] (the booking edited) and [section].
int _avail(MockServer s, {String? exclude, String? section}) => [
  for (final c in s.callsTo(availabilityTemplate, method: 'GET'))
    if (c.query['exclude_booking_id']?.single == exclude &&
        c.query['section_id']?.single == section)
      c,
].length;

int _days(MockServer s, String date) => [
  for (final c in s.callsTo(dayTemplate, method: 'GET'))
    if (c.query['date']?.single == date) c,
].length;

Future<void> _close(DashHarness h) async {
  await h.tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await h.settle();
  expect(find.byType(BookingDialog), findsNothing);
}

void main() {
  testWidgets('a row, its Edit item and a timeline block warm the edit '
      'dialog; the press asks nothing more', (tester) async {
    final h = await pumpBookings(tester);
    final mouse = await _mouse(tester);
    final s = h.server;
    final four = stored(h.db!).firstWhere((b) => b.id == heliBooking(4));
    final sections = s.callsTo(sectionsTemplate).length;

    // A row (onRowIntent); the guest's link inside it has the same label.
    final row = inPage(
      find.byWidgetPredicate(
        (w) => w is DashPressable && w.semanticLabel == four.guestName,
      ),
    ).first;
    expect(_avail(s, exclude: four.id), 0);
    await _rest(h, mouse, row);
    expect(_avail(s, exclude: four.id), 1, reason: 'the slots are warmed');
    expect(s.callsTo(sectionsTemplate).length, sections + 1);
    await h.tap(row);
    expect(find.byType(BookingDialog), findsOneWidget);
    expect(_avail(s, exclude: four.id), 1, reason: 'opened from the cache');
    expect(s.callsTo(sectionsTemplate).length, sections + 1);
    await _close(h);

    // The row menu's Edit (DashMenuItem.onIntent).
    final three = heliBooking(3);
    await h.tap(actionsOf(three));
    final edit = find.text('Edit').last;
    await _rest(h, mouse, edit);
    expect(_avail(s, exclude: three), 1);
    await h.tap(edit);
    expect(find.byType(BookingDialog), findsOneWidget);
    expect(_avail(s, exclude: three), 1);
    await _close(h);

    // A timeline block (DashPressable.onIntent).
    await h.tap(inPage(find.text('Timeline')));
    final two = heliBooking(2);
    final block = find.byKey(ValueKey('timeline-block-$two'));
    await _rest(h, mouse, block);
    expect(_avail(s, exclude: two), 1);
    await h.tap(block);
    expect(find.byType(BookingDialog), findsOneWidget);
    expect(_avail(s, exclude: two), 1);
  });

  testWidgets('New booking and a section option warm the slots they ask', (
    tester,
  ) async {
    final h = await pumpBookings(tester);
    final mouse = await _mouse(tester);
    final s = h.server;
    final terrace = SellIds.section('heliopolis', 'terrace');

    final add = find.byKey(const ValueKey('bookings-new'));
    expect(_avail(s), 0);
    await _rest(h, mouse, add);
    expect(_avail(s), 1);
    await h.tap(add);
    expect(find.byType(BookingDialog), findsOneWidget);
    expect(_avail(s), 1, reason: 'the dialog opened from the cache');

    // A section option (onOptionIntent).
    await h.tap(
      find.descendant(
        of: find.byType(BookingDialog),
        matching: find.byKey(const ValueKey('booking-section')),
      ),
    );
    final option = find.text('Terrace').last;
    await _rest(h, mouse, option);
    expect(_avail(s, section: terrace), 1);
    await h.tap(option);
    expect(_avail(s, section: terrace), 1);
  });

  testWidgets('the next day warms its list; stale settings refresh on intent', (
    tester,
  ) async {
    final h = await pumpBookings(tester);
    final mouse = await _mouse(tester);
    final s = h.server;

    final next = find.byKey(const ValueKey('bookings-next-day'));
    expect(_days(s, '2026-10-09'), 0);
    await _rest(h, mouse, next);
    expect(_days(s, '2026-10-09'), 1);
    await h.tap(next);
    expect(_days(s, '2026-10-09'), 1, reason: 'the day came from the cache');

    // Settings opened on data older than 30 s refetch on intent, not after.
    h.db!.clock.advance(const Duration(seconds: 31));
    final settings = find.byKey(const ValueKey('bookings-settings'));
    final before = s.callsTo(settingsTemplate, method: 'GET').length;
    await _rest(h, mouse, settings);
    expect(s.callsTo(settingsTemplate, method: 'GET'), hasLength(before + 1));
    await h.tap(settings);
    expect(find.byType(BookingSettingsDialog), findsOneWidget);
    expect(s.callsTo(settingsTemplate, method: 'GET'), hasLength(before + 1));
  });
}
