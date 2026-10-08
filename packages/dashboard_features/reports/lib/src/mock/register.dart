/// The reports area's mock backend: its handlers on the shared
/// [MockServer], over the seeded [MockDb] (registered after the core's, so a
/// handler here can replace a core route). Each unit registers its own
/// routes; the figures they share come from `../area_seed.dart`.
library;

import 'package:dashboard_api/mock.dart';

import 'basira_mock.dart';
import 'financial_mock.dart';
import 'legal_mock.dart';
import 'loyalty_inventory_staff_mock.dart';
import 'operations_mock.dart';
import 'staff_pool_bundles_mock.dart';
import 'tills_report_mock.dart';

void registerReportsMocks(MockServer server, MockDb db) {
  registerOperationsMocks(server, db);
  registerFinancialMocks(server, db);
  registerLegalMocks(server, db);
  registerBasiraMocks(server, db);
  registerTillsReportMocks(server, db);
  registerStaffPoolBundlesMocks(server, db);
  registerLoyaltyInventoryStaffMocks(server, db);
}
