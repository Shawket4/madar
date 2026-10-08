/// Mock handlers of the `items` unit: the items page (the catalog list, add-ons
/// and categories, their dialogs, paste rows, the export).
///
/// Read and write the area's tables through [MenuTables] and
/// [CatalogMenuData] so every unit's numbers agree.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';

void registerItemsMocks(MockServer server, MockDb db) {}
