/// Transfers: the mock backend for the INV-TRF rows. Routes this unit owns
/// (the only file that registers them):
///
/// - GET /inventory/branches/{branch_id}/transfers (listTransfers)
/// - POST /inventory/transfers (createTransfer)
/// - PATCH /inventory/transfers/{id} (updateTransfer)
/// - DELETE /inventory/transfers/{id} (deleteTransfer) — removes the row (INV-TRF-029)
///
/// Branches come from the core (`GET /branches`); the source stock is a
/// shared read.
library;

import 'package:dashboard_api/mock.dart';

void registerTransfersMocks(MockServer server, MockDb db) {}
