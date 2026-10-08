/// The create-ingredient dialog (the web's
/// `features/recipes/create-ingredient-dialog.tsx`, MENU-RCP-017..022): name,
/// ingredient category (defaults to `general`), unit and optional unit cost;
/// creates an org ingredient. Opened from the recipe builder and onboarding;
/// exported from the package.
///
/// It is not a form on the web (no implicit Enter submit): Save is the only
/// way to write.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show CreateCatalogItemRequest, IngredientCategory, OrgIngredient;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';

/// Opens the dialog; resolves with the created ingredient, or null when
/// cancelled.
Future<OrgIngredient?> showCreateIngredientDialog(
  BuildContext context, {
  required String orgId,
}) => showDashDialog<OrgIngredient>(
  context,
  builder: (_) => CreateIngredientDialog(orgId: orgId),
);

/// The ingredient category a new ingredient starts in: the one whose slug is
/// `general`, else the first.
IngredientCategory? defaultIngredientCategory(
  List<IngredientCategory> categories,
) =>
    categories.where((c) => c.slug == 'general').firstOrNull ??
    categories.firstOrNull;

/// The cost box in pounds as the wire's piastres per unit: blank (or not a
/// number) is null, "unknown" — never 0.
double? ingredientCostPiastres(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final egp = jsParseFloat(trimmed);
  if (!egp.isFinite) return null;
  return egpToPiastres(egp).toDouble();
}

class CreateIngredientDialog extends ConsumerStatefulWidget {
  const CreateIngredientDialog({required this.orgId, super.key});

  final String orgId;

  @override
  ConsumerState<CreateIngredientDialog> createState() =>
      _CreateIngredientDialogState();
}

class _CreateIngredientDialogState
    extends ConsumerState<CreateIngredientDialog> {
  String _name = '';
  String? _categoryId;
  String _unit = 'g';
  String _cost = '';
  bool _busy = false;

  Future<void> _submit() async {
    final name = _name.trim();
    if (name.isEmpty) return;
    final t = ref.read(tProvider);
    final cost = ingredientCostPiastres(_cost);
    final categoryId = _categoryId;
    setState(() => _busy = true);
    try {
      final created = await ref
          .read(apiProvider)
          .inventory
          .createCatalogItem(
            orgId: widget.orgId,
            body: CreateCatalogItemRequest(
              name: name,
              categoryId: categoryId,
              unit: _unit,
              costPerUnit: cost,
              explicitNulls: {
                if (categoryId == null) 'category_id',
                if (cost == null) 'cost_per_unit',
              },
            ),
          );
      ref.menuInvalidate.recipes();
      if (!mounted) return;
      DashToast.success(context, t('common.savedChanges'));
      Navigator.of(context).pop(created);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final categories =
        ref.watch(ingredientCategoriesProvider(widget.orgId)).value ??
        const <IngredientCategory>[];
    // The web's effect: once the categories land, an unset category becomes
    // `general` (else the first).
    _categoryId ??= defaultIngredientCategory(categories)?.id;
    final canSave = _name.trim().isNotEmpty;

    return DashSurface(
      title: t('recipes.createIngredient'),
      description: t('recipes.subtitle'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          DashTextField(
            label: t('inventory.catalog.name'),
            value: _name,
            autofocus: true,
            onChanged: (v) => setState(() => _name = v),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(
                child: DashSelectField<String>(
                  label: t('inventory.catalog.category'),
                  placeholder: t('inventory.catalog.category'),
                  value: _categoryId,
                  options: [
                    for (final c in categories)
                      DashOption(value: c.id, label: c.name),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
              ),
              Expanded(
                child: DashSelectField<String>(
                  label: t('inventory.catalog.unit'),
                  value: _unit,
                  options: [
                    for (final u in ingredientUnits)
                      DashOption(value: u, label: unitWord(t, u)),
                  ],
                  onChanged: (v) => setState(() => _unit = v),
                ),
              ),
            ],
          ),
          DashTextField(
            label: t('inventory.catalog.costPerUnit'),
            value: _cost,
            placeholder: '—',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            onChanged: (v) => setState(
              () => _cost = cleanDecimal(
                DashTime.latinDigits(v).replaceAll('٫', '.'),
              ),
            ),
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          label: t('common.save'),
          loading: _busy,
          onPressed: canSave ? _submit : null,
        ),
      ],
    );
  }
}
