/// Inventory settings: the mock backend for the INV-SET rows. Routes this unit owns
/// (the only file that registers them):
///
/// - GET /inventory/orgs/{org_id}/settings (getInventorySettings)
/// - PUT /inventory/orgs/{org_id}/settings (updateInventorySettings)
/// - POST /inventory/orgs/{org_id}/categories (createIngredientCategory) — also used by Ingredients' "New category…"
/// - PATCH /inventory/orgs/{org_id}/categories/{id} (updateIngredientCategory)
/// - DELETE /inventory/orgs/{org_id}/categories/{id} (deleteIngredientCategory)
///
/// The categories list is a shared read.
library;

import 'package:dashboard_api/mock.dart';

void registerInvSettingsMocks(MockServer server, MockDb db) {}
