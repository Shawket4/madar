/// Stock counts: the mock backend for the INV-CNT rows. Routes this unit owns
/// (the only file that registers them):
///
/// - POST /stocktakes/branches/{branch_id} (createStocktake) — also used by Ingredients' "Count this item"
/// - GET /stocktakes/{id} (getStocktake)
/// - PUT /stocktakes/{id}/items (upsertItems)
/// - POST /stocktakes/{id}/finalize (finalizeStocktake)
/// - POST /stocktakes/{id}/cancel (cancelStocktake)
/// - GET /stocktakes/{id}/variance-report (varianceReport)
///
/// The list (`GET /stocktakes/branches/{branch_id}`) is a shared read.
library;

import 'package:dashboard_api/mock.dart';

void registerCountsMocks(MockServer server, MockDb db) {}
