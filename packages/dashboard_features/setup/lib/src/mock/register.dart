/// The setup area's mock backend: its handlers on the shared
/// [MockServer], over the seeded [MockDb] (registered after the core's, so a
/// handler here can replace a core route).
///
/// The area's shared records ([SetupSeed]) go in first; then each unit
/// registers its own routes from `<unit>_mock.dart`.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'booking_settings_mock.dart';
import 'brand_appearance_mock.dart';
import 'combo_settings_mock.dart';
import 'delivery_mock.dart';
import 'integrations_mock.dart';
import 'kitchen_mock.dart';
import 'links_mock.dart';
import 'loyalty_mock.dart';
import 'payment_methods_mock.dart';
import 'qr_mock.dart';
import 'staff_pool_mock.dart';
import 'whatsapp_mock.dart';

void registerSetupMocks(MockServer server, MockDb db) {
  SetupSeed.loadInto(db);
  registerBrandAppearanceMocks(server, db);
  registerLinksMocks(server, db);
  registerDeliveryMocks(server, db);
  registerBookingSettingsMocks(server, db);
  registerLoyaltyMocks(server, db);
  registerQrMocks(server, db);
  registerComboSettingsMocks(server, db);
  registerPaymentMethodsMocks(server, db);
  registerStaffPoolMocks(server, db);
  registerKitchenMocks(server, db);
  registerIntegrationsMocks(server, db);
  registerWhatsappMocks(server, db);
}
