/// The menu catalogue area's mock backend: its handlers on the shared
/// [MockServer], over the seeded [MockDb] (registered after the core's, so a
/// handler here can replace a core route). The area's own data is loaded
/// first ([CatalogMenuSeed]), then the shared reads, then each unit's
/// handlers.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'bases_mock.dart';
import 'groups_mock.dart';
import 'items_mock.dart';
import 'pricing_mock.dart';
import 'recipes_mock.dart';
import 'shared_mock.dart';
import 'studio_mock.dart';

void registerCatalogMenuMocks(MockServer server, MockDb db) {
  CatalogMenuSeed.loadInto(db);
  registerSharedMenuMocks(server, db);
  registerItemsMocks(server, db);
  registerStudioMocks(server, db);
  registerRecipesMocks(server, db);
  registerGroupsMocks(server, db);
  registerPricingMocks(server, db);
  registerBasesMocks(server, db);
}
