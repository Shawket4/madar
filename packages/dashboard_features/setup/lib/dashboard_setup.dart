/// The dashboard's setup area: its pages ([setupRoutes]), its mock backend
/// ([registerSetupMocks]) and its i18n supplement, as [setupArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerSetupMocks;
export 'src/routes.dart' show setupRoutes;

/// The setup area as the shell mounts it.
///
/// The supplement is one table pair for the area plus one pair per unit
/// (`assets/i18n/<unit>/{en,ar}.json`), so the units' builders never edit
/// the same file. The file name is the language.
const DashArea setupArea = DashArea(
  key: 'setup',
  routes: setupRoutes,
  registerMocks: registerSetupMocks,
  i18nSupplements: [
    'packages/dashboard_setup/assets/i18n/en.json',
    'packages/dashboard_setup/assets/i18n/ar.json',
    'packages/dashboard_setup/assets/i18n/booking_settings/en.json',
    'packages/dashboard_setup/assets/i18n/booking_settings/ar.json',
    'packages/dashboard_setup/assets/i18n/brand_appearance/en.json',
    'packages/dashboard_setup/assets/i18n/brand_appearance/ar.json',
    'packages/dashboard_setup/assets/i18n/combo_settings/en.json',
    'packages/dashboard_setup/assets/i18n/combo_settings/ar.json',
    'packages/dashboard_setup/assets/i18n/delivery/en.json',
    'packages/dashboard_setup/assets/i18n/delivery/ar.json',
    'packages/dashboard_setup/assets/i18n/integrations/en.json',
    'packages/dashboard_setup/assets/i18n/integrations/ar.json',
    'packages/dashboard_setup/assets/i18n/kitchen/en.json',
    'packages/dashboard_setup/assets/i18n/kitchen/ar.json',
    'packages/dashboard_setup/assets/i18n/links/en.json',
    'packages/dashboard_setup/assets/i18n/links/ar.json',
    'packages/dashboard_setup/assets/i18n/loyalty/en.json',
    'packages/dashboard_setup/assets/i18n/loyalty/ar.json',
    'packages/dashboard_setup/assets/i18n/payment_methods/en.json',
    'packages/dashboard_setup/assets/i18n/payment_methods/ar.json',
    'packages/dashboard_setup/assets/i18n/qr/en.json',
    'packages/dashboard_setup/assets/i18n/qr/ar.json',
    'packages/dashboard_setup/assets/i18n/staff_pool/en.json',
    'packages/dashboard_setup/assets/i18n/staff_pool/ar.json',
    'packages/dashboard_setup/assets/i18n/whatsapp/en.json',
    'packages/dashboard_setup/assets/i18n/whatsapp/ar.json',
  ],
);
