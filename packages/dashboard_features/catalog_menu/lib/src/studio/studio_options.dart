/// Studio section 5, Options (the web's `section-options.tsx`): priced
/// add-ons private to this item, each with an optional single-ingredient
/// deduction. Rows are drafts the save replace-sets. Ungated: the server
/// decides (MENU-STUDIO-112).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show OrgIngredient;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/ingredient_options.dart';
import '../shared/menu_providers.dart';
import '../shared/menu_text.dart';
import 'studio_model.dart';
import 'studio_widgets.dart';

class StudioOptionsSection extends ConsumerWidget {
  const StudioOptionsSection({
    required this.rows,
    required this.catalog,
    required this.onChanged,
    super.key,
  });

  final List<OptionRow> rows;
  final List<OrgIngredient> catalog;
  final ValueChanged<List<OptionRow>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final byId = ingredientsById(catalog);
    final options = ingredientOptions(catalog, t);

    void set(int i, OptionRow r) =>
        onChanged([for (final (j, x) in rows.indexed) j == i ? r : x]);

    Widget labelled(String label, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xs,
      children: [
        Text(label, style: DashType.smallMedium.copyWith(color: c.textSecondary)),
        child,
      ],
    );

    Widget row(int i, OptionRow r) {
      final ing = r.ingredientId.isEmpty ? null : byId[r.ingredientId];
      final unitCost = positiveUnitCost(ing);
      final qty = jsParseFloat(r.quantity);
      final lineCost = ing != null && unitCost != null && qty.isFinite
          ? fmt.fmtMoney(unitCost * qty)
          : null;
      return Container(
        key: ValueKey('studio-option-$i'),
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            Wrap(
              spacing: Space.md,
              runSpacing: Space.sm,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                  width: Space.xxl * 7,
                  child: labelled(
                    t('common.name'),
                    DashTextInput(
                      value: r.name,
                      placeholder: t('menu.studio.options.namePh'),
                      semanticLabel: t('common.name'),
                      onChanged: (v) => set(i, r.copyWith(name: v)),
                    ),
                  ),
                ),
                SizedBox(
                  width: Space.xxl * 4,
                  child: labelled(
                    // The web hard-codes "(EGP)" here, in both languages.
                    '${t('common.price')} (EGP)',
                    DashTextInput(
                      value: r.price,
                      mono: true,
                      textAlign: TextAlign.end,
                      semanticLabel: '${t('common.price')} (EGP)',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (v) => set(i, r.copyWith(price: v)),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.xs,
                  children: [
                    DashSwitch(
                      value: r.isActive,
                      semanticLabel: t('common.active'),
                      onChanged: (v) => set(i, r.copyWith(isActive: v)),
                    ),
                    Text(
                      t('common.active'),
                      style: DashType.body.copyWith(color: c.textPrimary),
                    ),
                  ],
                ),
                DashIconButton(
                  icon: 'trash-2',
                  color: c.danger,
                  semanticLabel: t('common.remove'),
                  onPressed: () => onChanged([
                    for (final (j, x) in rows.indexed)
                      if (j != i) x,
                  ]),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.only(top: Space.md),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: Wrap(
                spacing: Space.md,
                runSpacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    t('menu.studio.options.deducts'),
                    style: DashType.smallMedium.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  SizedBox(
                    width: Space.xxl * 7,
                    child: DashSelect<String>(
                      options: options,
                      value: r.ingredientId.isEmpty ? null : r.ingredientId,
                      searchable: true,
                      placeholder: t('menu.studio.options.noDeduction'),
                      semanticLabel: t('menu.studio.options.deducts'),
                      searchPlaceholder: t('common.search'),
                      emptyText: t('common.noResults'),
                      onChanged: (v) => set(
                        i,
                        r.copyWith(ingredientId: v, unit: byId[v]?.unit ?? r.unit),
                      ),
                    ),
                  ),
                  if (r.ingredientId.isNotEmpty) ...[
                    SizedBox(
                      width: Space.xxl * 4 + Space.lg,
                      child: DashTextInput(
                        value: r.quantity,
                        mono: true,
                        placeholder: '0.000',
                        textAlign: TextAlign.end,
                        semanticLabel: t('common.quantity'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        trailing: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            end: Space.sm,
                          ),
                          child: Text(
                            unitWord(t, r.unit),
                            style: DashType.small.copyWith(color: c.textMuted),
                          ),
                        ),
                        onChanged: (v) => set(i, r.copyWith(quantity: v)),
                      ),
                    ),
                    if (lineCost != null)
                      StudioHint(
                        t('menu.studio.options.cost', args: {'cost': lineCost}),
                      ),
                    DashButton(
                      label: t('common.clear'),
                      variant: DashButtonVariant.link,
                      size: DashButtonSize.compact,
                      onPressed: () => set(
                        i,
                        r.copyWith(ingredientId: '', quantity: ''),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        for (final (i, r) in rows.indexed) row(i, r),
        StudioDashedAdd(
          label: t('menu.studio.options.add'),
          onTap: () => onChanged([...rows, const OptionRow()]),
        ),
      ],
    );
  }
}
