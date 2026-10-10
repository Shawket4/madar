/// The inventory area's mock backend: its handlers on the shared
/// [MockServer], over the seeded [MockDb] (registered after the core's, so a
/// handler here can replace a core route).
///
/// Order: the area's rows ([InventorySeed]) go into the db first, then the
/// reads several pages share, then each unit's own routes. A route
/// registered twice keeps the LAST handler, so every route has exactly one
/// owner: the shared reads in `shared_reads_mock.dart`, the rest in the unit
/// file whose rows it serves (each file's header lists its routes).
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'counts_mock.dart';
import 'ingredients_mock.dart';
import 'inv_settings_mock.dart';
import 'purchasing_mock.dart';
import 'shared_reads_mock.dart';
import 'today_mock.dart';
import 'transfers_mock.dart';
import 'waste_mock.dart';

void registerInventoryMocks(MockServer server, MockDb db) {
  InventorySeed.loadInto(db);
  registerInventorySharedReads(server, db);
  registerTodayMocks(server, db);
  registerCountsMocks(server, db);
  registerIngredientsMocks(server, db);
  registerPurchasingMocks(server, db);
  registerWasteMocks(server, db);
  registerTransfersMocks(server, db);
  registerInvSettingsMocks(server, db);
}
