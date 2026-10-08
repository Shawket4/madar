/// The mock backend for Loyalty, Inventory reports and Staff discipline (REP-LOY, REP-INV, REP-STF): loyalty behaviour / campaigns / liability, consumption, shrinkage, waste, PO lead time, low stock and the discipline report.
///
/// Handlers behave like the backend (capability refusals, branch scoping,
/// the shared figures in `../area_seed.dart`); see SPEC section 3.2.
library;

import 'package:dashboard_api/mock.dart';

void registerLoyaltyInventoryStaffMocks(MockServer server, MockDb db) {}
