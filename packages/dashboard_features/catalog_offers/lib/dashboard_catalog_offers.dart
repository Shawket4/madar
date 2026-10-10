/// The dashboard's offers catalogue area: its pages ([catalogOffersRoutes]),
/// its mock backend ([registerCatalogOffersMocks]) and its i18n supplement, as
/// [catalogOffersArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerCatalogOffersMocks;
export 'src/routes.dart' show catalogOffersRoutes;

/// The offers catalogue area as the shell mounts it. Its supplement tables:
/// the area's own, then one pair per page unit (so each page's port adds
/// words without touching another's file).
const DashArea catalogOffersArea = DashArea(
  key: 'catalog_offers',
  routes: catalogOffersRoutes,
  registerMocks: registerCatalogOffersMocks,
  i18nSupplements: [
    'packages/dashboard_catalog_offers/assets/i18n/en.json',
    'packages/dashboard_catalog_offers/assets/i18n/ar.json',
    'packages/dashboard_catalog_offers/assets/i18n/combos.en.json',
    'packages/dashboard_catalog_offers/assets/i18n/combos.ar.json',
    'packages/dashboard_catalog_offers/assets/i18n/combo_editor.en.json',
    'packages/dashboard_catalog_offers/assets/i18n/combo_editor.ar.json',
    'packages/dashboard_catalog_offers/assets/i18n/deals.en.json',
    'packages/dashboard_catalog_offers/assets/i18n/deals.ar.json',
    'packages/dashboard_catalog_offers/assets/i18n/discounts.en.json',
    'packages/dashboard_catalog_offers/assets/i18n/discounts.ar.json',
  ],
);
