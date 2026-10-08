/// Waste log: the mock backend for the INV-WST rows. Routes this unit owns
/// (the only file that registers them):
///
/// - POST /inventory/branches/{branch_id}/waste (createWaste) — also used by Today and Ingredients
/// - GET /reports/branches/{branch_id}/waste-report (branchWasteReport)
///
/// The log (`GET /inventory/branches/{branch_id}/waste`) and the branch
/// stock are shared reads. A recorded waste is a `waste` movement in
/// `InvTables.movements` and lowers `InvTables.branchStock`.
library;

import 'package:dashboard_api/mock.dart';

void registerWasteMocks(MockServer server, MockDb db) {}
