/// The dashboard's menu catalogue area: its pages ([catalogMenuRoutes]), its
/// mock backend ([registerCatalogMenuMocks]) and its i18n supplement, as
/// [catalogMenuArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerCatalogMenuMocks;
export 'src/routes.dart' show catalogMenuRoutes;

/// The menu catalogue area as the shell mounts it.
const DashArea catalogMenuArea = DashArea(
  key: 'catalog_menu',
  routes: catalogMenuRoutes,
  registerMocks: registerCatalogMenuMocks,
  i18nSupplements: [
    'packages/dashboard_catalog_menu/assets/i18n/en.json',
    'packages/dashboard_catalog_menu/assets/i18n/ar.json',
  ],
);
