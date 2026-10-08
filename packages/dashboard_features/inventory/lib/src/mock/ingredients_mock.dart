/// Ingredients: the mock backend for the INV-ING rows. Routes this unit owns
/// (the only file that registers them):
///
/// - POST /inventory/orgs/{org_id}/catalog (createCatalogItem)
/// - PATCH /inventory/orgs/{org_id}/catalog/{id} (updateCatalogItem)
/// - DELETE /inventory/orgs/{org_id}/catalog/{id} (deleteCatalogItem)
/// - PUT /inventory/branches/{branch_id}/stock/{org_ingredient_id}/par (setParLevels)
/// - GET /inventory/branches/{branch_id}/movements (listMovements)
///
/// The catalog, branch stock and categories reads are shared reads; the
/// category create is Settings'.
library;

import 'package:dashboard_api/mock.dart';

void registerIngredientsMocks(MockServer server, MockDb db) {}
