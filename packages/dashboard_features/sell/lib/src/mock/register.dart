/// The sell area's mock backend: its handlers on the shared
/// [MockServer], over the seeded [MockDb] (registered after the core's, so a
/// handler here can replace a core route).
///
/// The area seed (floor plans, bookings, booking settings, open tickets,
/// transfers) goes into [db] first; then each unit registers its own routes
/// from its own file.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'bookings_mock.dart';
import 'customers_mock.dart';
import 'floor_mock.dart';
import 'orders_mock.dart';
import 'tills_mock.dart';

void registerSellMocks(MockServer server, MockDb db) {
  loadSellSeed(db);
  registerOrdersMocks(server, db);
  registerFloorMocks(server, db);
  registerBookingsMocks(server, db);
  registerTillsMocks(server, db);
  registerCustomersMocks(server, db);
}
