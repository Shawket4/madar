// Shared set-up for the bookings tests: the app on the seeded mock server
// with the sell area, Heliopolis picked (its day: a completed 09:00, Nada
// Kamal seated at 09:30, a LATE 09:45, a DUE 10:15 online booking, a 13:00
// party of six with no table, a 19:30 online booking and a cancelled 20:00;
// now = Thursday 2026-10-08 10:00 Cairo).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_sell/dashboard_sell.dart';
import 'package:dashboard_sell/src/area_seed.dart';
import 'package:dashboard_sell/src/bookings/booking_dialog.dart';
import 'package:dashboard_sell/src/bookings/booking_settings_dialog.dart';
import 'package:dashboard_sell/src/bookings/bookings_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sell_harness.dart';

const String today = '2026-10-08';
const String bookingsPath = '/bookings';
const String dayTemplate = '/bookings';
const String settingsTemplate = '/bookings/settings';
const String tablesTemplate = '/floor/tables';
const String sectionsTemplate = '/floor/sections';
const String availabilityTemplate = '/bookings/availability';

/// Heliopolis's bookings today, by their seed number.
String heliBooking(int n) => SellIds.booking('heliopolis', today, n);

/// A seeded server with the core's and the sell area's handlers, for a test
/// that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) bookingsServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerSellMocks(server, db);
  return (server: server, db: db);
}

/// Opens [path] with [branchId] picked (Heliopolis by default; [noBranch] =
/// All branches).
Future<DashHarness> pumpBookings(
  WidgetTester tester, {
  String path = bookingsPath,
  Persona? persona = Persona.owner,
  String? branchId,
  bool noBranch = false,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? s,
}) => pumpSell(
  tester,
  path,
  persona: persona,
  branchId: noBranch ? null : (branchId ?? SeedIds.heliopolis),
  size: size,
  locale: locale,
  dark: dark,
  server: s?.server,
  db: s?.db,
);

/// [f] on the bookings page only (the sidebar and header repeat words).
Finder inPage(Finder f) =>
    find.descendant(of: find.byType(BookingsPage), matching: f);

/// [text] on the page.
Finder pageText(String text) => inPage(find.text(text));

/// [f] inside the booking dialog.
Finder inDialog(Finder f) =>
    find.descendant(of: find.byType(BookingDialog), matching: f);

/// [f] inside the settings dialog.
Finder inSettings(Finder f) =>
    find.descendant(of: find.byType(BookingSettingsDialog), matching: f);

/// Text widgets containing [s] (rich text included) under [of].
Finder textIn(Finder of, String s) => find.descendant(
  of: of,
  matching: find.textContaining(s, findRichText: true),
);

/// The table's row for the booking with guest [name] (its row actions).
Finder actionsOf(String id) => find.byKey(ValueKey('booking-actions-$id'));

/// The bookings the server holds, as views.
List<BookingView> stored(MockDb db) => [
  for (final r in db[SellTables.bookings].rows) BookingView.fromJson(r),
];
