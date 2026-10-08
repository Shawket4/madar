/// The offers catalogue area's mock backend: its handlers on the shared
/// [MockServer], over the seeded [MockDb] (registered after the core's, so a
/// handler here can replace a core route).
///
/// Order: the area seed, then the shared menu reads (only where no earlier
/// area answers them), then each page's own handlers (a later registration of
/// the same route replaces an earlier one).
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'combo_editor_mock.dart';
import 'combos_mock.dart';
import 'deals_mock.dart';
import 'discounts_mock.dart';
import 'shared_mocks.dart';

void registerCatalogOffersMocks(MockServer server, MockDb db) {
  OffersSeed.loadInto(db);
  registerOffersSharedMocks(server, db);
  registerCombosMocks(server, db);
  registerComboEditorMocks(server, db);
  registerDealsMocks(server, db);
  registerDiscountsMocks(server, db);
}
