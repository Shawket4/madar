/// Mock handlers of the `pricing` unit: pricing and availability (catalog
/// pages, the add-on catalog, branch and channel overrides).
///
/// Read and write the area's tables through [MenuTables] and
/// [CatalogMenuData] so every unit's numbers agree.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';

void registerPricingMocks(MockServer server, MockDb db) {}
