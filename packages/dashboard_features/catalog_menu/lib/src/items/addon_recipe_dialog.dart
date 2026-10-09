/// The add-on recipe dialog (the web's `addon-recipe-dialog.tsx`,
/// MENU-ITEMS-102..105): the recipe builder with one "One size" column, the
/// margin against the add-on's default price, "New ingredient" offered, its
/// own "Save recipe": `PUT /modifier-options/{oid}/recipe` with the lines
/// linked to a catalog ingredient → invalidate the catalog → "Recipe saved"
/// → close. A failure toasts the server's words and stays open, unsaved.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show AddonIngredient, AddonItem, OptionRecipeLineInput;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recipes/recipe_builder.dart';
import '../recipes/recipe_providers.dart';
import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';

Future<void> showAddonRecipeDialog(
  BuildContext context, {
  required String orgId,
  required AddonItem addon,
}) => showDashDialog<void>(
  context,
  width: DashMetrics.dialogWide,
  builder: (_) => AddonRecipeDialog(orgId: orgId, addon: addon),
);

class AddonRecipeDialog extends ConsumerWidget {
  const AddonRecipeDialog({
    required this.orgId,
    required this.addon,
    super.key,
  });

  final String orgId;
  final AddonItem addon;

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    List<CleanRow> rows,
  ) async {
    final t = ref.read(tProvider);
    final invalidate = ref.menuInvalidate;
    try {
      await ref
          .read(apiProvider)
          .menu
          .putOptionRecipe(
            oid: addon.id,
            body: [
              for (final r in rows)
                if (r.orgIngredientId != null)
                  OptionRecipeLineInput(
                    ingredientId: r.orgIngredientId!,
                    quantity: r.quantityUsed,
                    unit: r.ingredientUnit,
                  ),
            ],
          );
      invalidate.catalog();
      if (context.mounted) {
        DashToast.success(context, t('recipes.builder.saved'));
        Navigator.of(context).pop();
      }
    } on Object catch (e) {
      if (context.mounted) DashToast.error(context, errorMessage(e, t));
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final catalog =
        ref.watch(ingredientCatalogProvider(orgId)).value ?? const [];
    final lines = ref.watch(addonIngredientsProvider(addon.id));
    return DashSurface(
      title: t('menu.addonRecipe.title'),
      // The web writes the raw name here (MENU-ITEMS-110); the active
      // language's name is what it means.
      description:
          '${translatedName(addon.name, addon.nameTranslations, t.lang)} — '
          '${t('menu.addonRecipe.desc')}',
      body: lines.isLoading && !lines.hasValue
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.xxl),
              child: Center(child: MadarSpinner()),
            )
          : RecipeBuilder(
              orgId: orgId,
              sizes: const [oneSize],
              initialRows: [
                for (final r in lines.value ?? const <AddonIngredient>[])
                  RecipeRowInit(
                    sizeLabel: oneSize,
                    orgIngredientId: r.orgIngredientId,
                    ingredientName: r.ingredientName,
                    ingredientUnit: r.unit,
                    quantityUsed: r.quantityUsed,
                  ),
              ],
              catalog: catalog,
              priceForSize: (_) => addon.defaultPrice,
              onSave: (rows, _) => _save(context, ref, rows),
            ),
    );
  }
}
