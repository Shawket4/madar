/// The dashboard's menu catalogue area: its pages ([catalogMenuRoutes]), its
/// mock backend ([registerCatalogMenuMocks]) and its i18n supplements, as
/// [catalogMenuArea].
///
/// Also exported for other areas (onboarding): the recipe builder, the
/// create-ingredient dialog and the category dialog.
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerCatalogMenuMocks;
export 'src/recipes/create_ingredient_dialog.dart'
    show CreateIngredientDialog, showCreateIngredientDialog;
export 'src/recipes/recipe_builder.dart'
    show CleanRow, RecipeBuilder, RecipeRowInit, RemovedRow;
export 'src/routes.dart' show catalogMenuRoutes;
export 'src/shared/category_dialog.dart'
    show CategoryDialog, showCategoryDialog;

/// The menu catalogue area as the shell mounts it.
const DashArea catalogMenuArea = DashArea(
  key: 'catalog_menu',
  routes: catalogMenuRoutes,
  registerMocks: registerCatalogMenuMocks,
  i18nSupplements: [
    'packages/dashboard_catalog_menu/assets/i18n/en.json',
    'packages/dashboard_catalog_menu/assets/i18n/ar.json',
    'packages/dashboard_catalog_menu/assets/i18n/items.en.json',
    'packages/dashboard_catalog_menu/assets/i18n/items.ar.json',
    'packages/dashboard_catalog_menu/assets/i18n/studio.en.json',
    'packages/dashboard_catalog_menu/assets/i18n/studio.ar.json',
    'packages/dashboard_catalog_menu/assets/i18n/recipes.en.json',
    'packages/dashboard_catalog_menu/assets/i18n/recipes.ar.json',
    'packages/dashboard_catalog_menu/assets/i18n/groups.en.json',
    'packages/dashboard_catalog_menu/assets/i18n/groups.ar.json',
    'packages/dashboard_catalog_menu/assets/i18n/pricing.en.json',
    'packages/dashboard_catalog_menu/assets/i18n/pricing.ar.json',
    'packages/dashboard_catalog_menu/assets/i18n/bases.en.json',
    'packages/dashboard_catalog_menu/assets/i18n/bases.ar.json',
  ],
);
