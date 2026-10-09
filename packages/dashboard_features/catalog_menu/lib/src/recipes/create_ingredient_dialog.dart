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
    // Taken before the await: the refresh happens even if the dialog is gone.
    final invalidate = ref.menuInvalidate;
    final api = ref.read(apiProvider);
    setState(() => _busy = true);
    try {
      final created = await api.inventory.createCatalogItem(
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
      invalidate.recipes();
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
    final categoriesQ = ref.watch(ingredientCategoriesProvider(widget.orgId));
    final categories = categoriesQ.value ?? const <IngredientCategory>[];
    final categoriesLoading =
        categoriesQ.isLoading && !categoriesQ.hasValue && !categoriesQ.hasError;
    final categoriesFailed = categoriesQ.hasError && !categoriesQ.hasValue;
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
                  placeholder: categoriesLoading
                      ? t('common.loading')
                      : t('inventory.catalog.category'),
                  // Nothing to pick until the read lands (never an empty
                  // "no results" list while it loads or after it failed).
                  enabled: categories.isNotEmpty,
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
          if (categoriesFailed)
            RecipeLoadError(
              title: t('inventory.settings.categoriesFailed'),
              message: errorMessage(categoriesQ.error, t),
              retrying: categoriesQ.isLoading,
              onRetry: () =>
                  ref.invalidate(ingredientCategoriesProvider(widget.orgId)),
            ),
          DashTextField(
            label: t('inventory.catalog.costPerUnit'),
            value: _cost,
            placeholder: '—',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

/// A read that failed with nothing to show, compact enough for a dialog or
/// the builder: what failed, the server's words, and Retry (spinning while
/// the retry runs). The web shows nothing here (see the divergences file).
class RecipeLoadError extends ConsumerWidget {
  const RecipeLoadError({
    required this.title,
    required this.message,
    required this.retrying,
    required this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: DashTone.danger.wash(c),
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Row(
          spacing: Space.md,
          children: [
            DashIcon(
              'alert-triangle',
              size: IconSize.sm,
              color: DashTone.danger.foreground(c),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: DashType.bodyStrong.copyWith(
                      color: DashTone.danger.foreground(c),
                    ),
                  ),
                  if (message.isNotEmpty)
                    Text(
                      message,
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                ],
              ),
            ),
            DashButton(
              label: t('common.retry'),
              icon: 'rotate-cw',
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              loading: retrying,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
