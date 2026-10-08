/// The menu catalogue area's mock backend: its handlers on the shared
/// [MockServer], over the seeded [MockDb] (registered after the core's, so a
/// handler here can replace a core route).
library;

import 'package:dashboard_api/mock.dart';

void registerCatalogMenuMocks(MockServer server, MockDb db) {}
