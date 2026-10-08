/// The dashboard's offers catalogue area: its pages ([catalogOffersRoutes]),
/// its mock backend ([registerCatalogOffersMocks]) and its i18n supplement, as
/// [catalogOffersArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerCatalogOffersMocks;
export 'src/routes.dart' show catalogOffersRoutes;

/// The offers catalogue area as the shell mounts it.
const DashArea catalogOffersArea = DashArea(
  key: 'catalog_offers',
  routes: catalogOffersRoutes,
  registerMocks: registerCatalogOffersMocks,
  i18nSupplements: [
    'packages/dashboard_catalog_offers/assets/i18n/en.json',
    'packages/dashboard_catalog_offers/assets/i18n/ar.json',
  ],
);
