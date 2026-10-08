/// The admin area's mock backend: its handlers on the shared
/// [MockServer], over the seeded [MockDb] (registered after the core's, so a
/// handler here can replace a core route). The area seed goes in first, then
/// each unit registers its own routes.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'branches_mock.dart';
import 'devices_mock.dart';
import 'onboarding_mock.dart';
import 'orgs_mock.dart';
import 'review_mock.dart';
import 'roles_mock.dart';
import 'users_mock.dart';

void registerAdminMocks(MockServer server, MockDb db) {
  loadAdminSeed(db);
  registerOrgsMocks(server, db);
  registerUsersMocks(server, db);
  registerBranchesMocks(server, db);
  registerOnboardingMocks(server, db);
  registerDevicesMocks(server, db);
  registerRolesMocks(server, db);
  registerReviewMocks(server, db);
}
