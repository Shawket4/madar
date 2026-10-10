/// "New choice group" (the web's `features/menu/groups/group-editor-dialog.tsx`
/// with `group={null}`, as the add-on dialog's "New group" opens it): the
/// name, what choosing does (nothing / adds ingredients / swaps an
/// ingredient category), how many the customer must pick, and the options
/// inline with their price and what each one deducts.
///
/// Save writes the group (`POST /modifier-groups`), then each option
/// (`POST …/options` + `PATCH /modifier-options/{id}` for its sort and
/// default) and its recipe when it has one (`PUT …/recipe`), refreshes the
/// catalog reads and resolves with the group as listed again, so the add-on
/// dialog can pick it.
///
/// Edit mode (an existing group, its usage, read-only viewing) is the menu
/// area's; onboarding only ever creates.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        CreateGroupRequest,
        CreateOptionRequest,
        GroupOut,
        IngredientCategory,
        OptionRecipeLineInput,
        OrgIngredient,
        PatchGroupRequest,
        PatchOptionRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'group_form.dart';
import 'group_model.dart';
import 'ingredient_options.dart';
import 'label_grid_editor.dart';
import 'label_model.dart';
import 'menu_reads.dart';
import 'menu_text.dart';

/// Opens the editor; resolves with the created group, or null.
Future<GroupOut?> showGroupEditorDialog(
  BuildContext context, {
  required String orgId,
}) => showDashDialog<GroupOut>(
  context,
  width: GroupEditorDialog.width,
  builder: (_) => GroupEditorDialog(orgId: orgId),
);

class GroupEditorDialog extends ConsumerStatefulWidget {
  const GroupEditorDialog({required this.orgId, super.key});

  /// `sm:max-w-3xl`.
  static const double width = 768;

  final String orgId;

  @override
  ConsumerState<GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends ConsumerState<GroupEditorDialog> {
  final GroupDraft _d = GroupDraft();
  var _seq = 0;
  bool _submitted = false;
  bool _busy = false;

  GroupMessages _messages(Translator t) => GroupMessages(
    required: t('common.requiredField'),
    maxAtLeastOne: t('menu.groups.editor.maxAtLeastOne'),
    swapNeedsIngredient: t('menu.groups.editor.swapNeedsIngredient'),
    swapNeedsCategory: t('menu.groups.editor.swapNeedsCategory'),
    duplicateIngredient: t('menu.groups.editor.duplicateIngredient'),
    qtyPositive: t('menu.groups.editor.qtyPositive'),
    priceMin: t('onboarding.form.priceMin'),
    notANumber: t('onboarding.form.notANumber'),
  );

  void _edit(VoidCallback change) => setState(change);

  Future<void> _save() async {
    final t = ref.read(tProvider);
    setState(() => _submitted = true);
    if (validateGroup(_d, _messages(t)).isNotEmpty) return;
    setState(() => _busy = true);
    final api = ref.read(apiProvider).menu;
    final catalog =
        ref.read(ingredientCatalogProvider(widget.orgId)).value ?? const [];
    final byId = ingredientsById(catalog);
    final groups =
        ref.read(modifierGroupsProvider(widget.orgId)).value ?? const [];
    final invalidate = ref.menuInvalidate;
    final sel = pickRuleToSelection(_d.pickRule);
    final swaps = _d.effect == GroupEffect.swaps;
    try {
      final taken = [
        for (final g in groups)
          if (g.legacyAddonType case final type? when type.isNotEmpty) type,
      ];
      var saved = await api.createGroup(
        body: CreateGroupRequest(
          name: _d.name,
          nameTranslations: _d.nameAr.isEmpty
              ? const <String, Object?>{}
              : {'ar': _d.nameAr},
          selectionType: sel.selectionType,
          minSelections: sel.minSelections,
          maxSelections: sel.maxSelections,
          isRequired: sel.isRequired,
          sort: groups.length,
          effect: _d.effect.name,
          swapCategoryId: swaps ? _d.swapCategoryId : null,
          legacyAddonType: swaps
              ? null
              : effectToLegacyType(_d.effect, null, _d.name, taken),
          explicitNulls: {
            'max_selections',
            if (!swaps) 'swap_category_id',
            if (swaps) 'legacy_addon_type',
          },
        ),
      );
      if (!_d.isActive) {
        saved = await api.patchGroup(
          gid: saved.id,
          body: const PatchGroupRequest(isActive: false),
        );
      }
      for (final (sort, o) in _d.options.indexed) {
        final swapIng = swaps && o.swapIngredientId.isNotEmpty
            ? o.swapIngredientId
            : null;
        final created = await api.createOption(
          gid: saved.id,
          body: CreateOptionRequest(
            name: o.name,
            nameTranslations: o.nameAr.isEmpty
                ? const <String, Object?>{}
                : {'ar': o.nameAr},
            price: egpToPiastres(jsNumber(o.price)),
            isActive: o.isActive,
            replacesIngredientId: swapIng,
            explicitNulls: {if (swapIng == null) 'replaces_ingredient_id'},
          ),
        );
        // CreateOptionRequest has no sort / default: set them right after.
        await api.patchOption(
          oid: created.id,
          body: PatchOptionRequest(sort: sort, isDefault: o.isDefault),
        );
        final lines = optionRecipeLines(
          _d.effect,
          swapIngredientId: o.swapIngredientId,
          lines: o.lines,
          unitOf: (id) => byId[id]?.unit,
        );
        if (recipeSig(lines) != recipeSig(const [])) {
          await api.putOptionRecipe(
            oid: created.id,
            body: [
              for (final l in lines)
                OptionRecipeLineInput(
                  ingredientId: l.ingredientId,
                  quantity: l.quantity,
                  unit: l.unit,
                  sizeLabel: l.sizeLabel,
                  explicitNulls: {if (l.sizeLabel == null) 'size_label'},
                ),
            ],
          );
        }
      }
      invalidate.catalog();
      if (!mounted) return;
      DashToast.success(context, t('common.savedChanges'));
      // `saved` predates the option writes: hand back the group as listed.
      GroupOut result = saved;
      try {
        final fresh = await api.listGroups(orgId: widget.orgId);
        result = fresh.where((g) => g.id == saved.id).firstOrNull ?? saved;
      } on Object {
        // The web's `.catch(() => [])`: the saved group is enough.
      }
      if (mounted) Navigator.of(context).pop(result);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final catalogQ = ref.watch(ingredientCatalogProvider(widget.orgId));
    final categories =
        ref.watch(ingredientCategoriesProvider(widget.orgId)).value ??
        const <IngredientCategory>[];
    // The group list is read for the new group's sort and its legacy type.
    ref.watch(modifierGroupsProvider(widget.orgId));
    final catalog = catalogQ.value ?? const <OrgIngredient>[];
    final byId = ingredientsById(catalog);
    final errors = _submitted
        ? validateGroup(_d, _messages(t))
        : const <String, String>{};
    final ingredientChoices = ingredientOptions(catalog, t);
    final swapChoices = [
      for (final i in catalog)
        if (i.isActive && i.categoryId == _d.swapCategoryId)
          DashOption<String>(
            value: i.id,
            label: i.name,
            hint: unitWord(t, i.unit),
          ),
    ];
    final effect = _d.effect;

    Widget legend(String text) =>
        Text(text, style: DashType.bodyMedium.copyWith(color: c.textPrimary));
    Widget info(String text, {Color? color}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: DashMetrics.hair),
          child: DashIcon('info', size: IconSize.xs, color: c.textSecondary),
        ),
        Expanded(
          child: Text(
            text,
            style: DashType.small.copyWith(color: color ?? c.textSecondary),
          ),
        ),
      ],
    );

    return DashSurface(
      title: t('menu.groups.editor.newTitle'),
      description: t('menu.groups.editor.desc'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          DashBilingualField(
            label: t('common.name'),
            en: _d.name,
            ar: _d.nameAr,
            enError: errors[GroupField.name],
            onEnChanged: (v) => _edit(() => _d.name = v),
            onArChanged: (v) => _edit(() => _d.nameAr = v),
          ),
          // What does choosing do?
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              legend(t('menu.groups.editor.effectLabel')),
              for (final e in GroupEffect.values)
                _EffectRow(
                  selected: effect == e,
                  label: switch (e) {
                    GroupEffect.none => t('menu.groups.effect.none'),
                    GroupEffect.adds => t('menu.groups.effect.adds'),
                    GroupEffect.swaps => t('menu.groups.effect.swapsPrefix'),
                  },
                  onTap: () => _edit(() => _d.effect = e),
                  trailing: e == GroupEffect.swaps
                      ? [
                          SizedBox(
                            width: _swapCategoryWidth,
                            child: DashSelect<String>(
                              key: const ValueKey('grp-swap-category'),
                              options: [
                                for (final cat in categories)
                                  DashOption(value: cat.id, label: cat.name),
                              ],
                              value: _d.swapCategoryId.isEmpty
                                  ? null
                                  : _d.swapCategoryId,
                              searchable: true,
                              invalid: errors[GroupField.swapCategory] != null,
                              placeholder: t(
                                'menu.groups.editor.swapCategoryPh',
                              ),
                              semanticLabel: t(
                                'menu.groups.editor.swapCategoryPh',
                              ),
                              searchPlaceholder: t('common.search'),
                              emptyText: t('common.noResults'),
                              onChanged: (id) => _edit(() {
                                _d.swapCategoryId = id;
                                _d.effect = GroupEffect.swaps;
                              }),
                            ),
                          ),
                          Text(
                            t('menu.groups.effect.swapsSuffix'),
                            style: DashType.body.copyWith(color: c.textPrimary),
                          ),
                        ]
                      : const [],
                ),
              if (errors[GroupField.swapCategory] case final e?)
                Text(e, style: DashType.small.copyWith(color: c.errorText)),
            ],
          ),
          // Customer must pick
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              legend(t('menu.groups.editor.pickLabel')),
              if (effect == GroupEffect.swaps)
                info(t('menu.groups.editor.swapExactlyOne'))
              else
                Wrap(
                  spacing: Space.md,
                  runSpacing: Space.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DashSegmentedControl<PickKind>(
                      semanticLabel: t('menu.groups.editor.pickLabel'),
                      value: _d.pick,
                      options: [
                        DashOption(
                          value: PickKind.exactlyOne,
                          label: t('menu.groups.pick.exactlyOne'),
                        ),
                        DashOption(
                          value: PickKind.upTo,
                          label: t('menu.groups.pick.upTo'),
                        ),
                        DashOption(
                          value: PickKind.any,
                          label: t('menu.groups.pick.any'),
                        ),
                      ],
                      onChanged: (v) => _edit(() => _d.pick = v),
                    ),
                    if (_d.pick == PickKind.upTo)
                      SizedBox(
                        width: _upToWidth,
                        child: DashTextInput(
                          key: const ValueKey('grp-up-to'),
                          value: _d.upTo,
                          semanticLabel: t('menu.groups.editor.upToCount'),
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          invalid: errors[GroupField.upTo] != null,
                          onChanged: (v) => _edit(
                            () => _d.upTo = v.replaceAll(RegExp(r'[^\d]'), ''),
                          ),
                        ),
                      ),
                    if (errors[GroupField.upTo] case final e?)
                      Text(
                        e,
                        style: DashType.small.copyWith(color: c.errorText),
                      ),
                  ],
                ),
            ],
          ),
          // Options
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              legend(t('menu.groups.editor.optionsLabel')),
              info(switch (effect) {
                GroupEffect.swaps => t('menu.groups.editor.swapHelp'),
                GroupEffect.adds => t('menu.groups.editor.addsHelp'),
                GroupEffect.none => t('menu.groups.editor.noneHelp'),
              }),
              if (effect == GroupEffect.swaps &&
                  swapChoices.isEmpty &&
                  !catalogQ.isLoading)
                Text(
                  _d.swapCategoryId.isNotEmpty
                      ? t('menu.groups.editor.noSwapIngredients')
                      : t('menu.groups.editor.swapPickCategory'),
                  style: DashType.small.copyWith(color: c.errorText),
                ),
              for (final (i, o) in _d.options.indexed)
                _OptionCard(
                  key: o.key,
                  index: i,
                  option: o,
                  effect: effect,
                  errors: errors,
                  byId: byId,
                  ingredientChoices: ingredientChoices,
                  swapChoices: swapChoices,
                  onEdit: _edit,
                  onDefault: (on) => _edit(() => _d.setDefault(i, on)),
                  onRemove: () => _edit(() => _d.options.removeAt(i)),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: DashButton(
                  label: t('menu.groups.editor.addOption'),
                  icon: 'plus',
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  onPressed: () => _edit(
                    () => _d.options.add(
                      OptionDraft(key: ValueKey('grp-option-${_seq++}')),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(label: t('common.save'), loading: _busy, onPressed: _save),
      ],
    );
  }
}

/// The swap category picker (`w-48`).
const double _swapCategoryWidth = 192;

/// The "Up to…" count box (`w-20`).
const double _upToWidth = 80;

/// The option price box (`7rem`).
const double _priceWidth = 112;

/// An option line's amount box (`w-24`).
const double _amountWidth = 96;

/// One "What does choosing do?" choice: a radio row; the swap row carries
/// its category picker inline.
class _EffectRow extends StatelessWidget {
  const _EffectRow({
    required this.selected,
    required this.label,
    required this.onTap,
    required this.trailing,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final words = Text(
      label,
      style: DashType.body.copyWith(color: c.textPrimary),
    );
    final choice = DashPressable(
      onTap: onTap,
      selected: selected,
      checked: selected,
      isButton: false,
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        child: Row(
          mainAxisSize: trailing.isEmpty ? MainAxisSize.max : MainAxisSize.min,
          spacing: Space.sm,
          children: [
            DashRadioDot(selected: selected, focused: s.focused),
            if (trailing.isEmpty)
              Expanded(child: words)
            else
              Flexible(child: words),
          ],
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: selected ? c.accentBg.withValues(alpha: 0.5) : null,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: selected ? c.accent : c.hairline),
      ),
      child: trailing.isEmpty
          ? choice
          : Padding(
              padding: const EdgeInsetsDirectional.only(
                end: Space.md,
                bottom: Space.xs,
              ),
              // A narrow window wraps the picker under the words.
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [choice, ...trailing],
              ),
            ),
    );
  }
}

/// One option: name, Arabic name, price, Active, Default, remove; then what
/// it pours (swaps) or deducts (adds).
class _OptionCard extends ConsumerWidget {
  const _OptionCard({
    required this.index,
    required this.option,
    required this.effect,
    required this.errors,
    required this.byId,
    required this.ingredientChoices,
    required this.swapChoices,
    required this.onEdit,
    required this.onDefault,
    required this.onRemove,
    super.key,
  });

  final int index;
  final OptionDraft option;
  final GroupEffect effect;
  final Map<String, String> errors;
  final Map<String, OrgIngredient> byId;
  final List<DashOption<String>> ingredientChoices;
  final List<DashOption<String>> swapChoices;
  final void Function(VoidCallback change) onEdit;
  final ValueChanged<bool> onDefault;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final o = option;
    final i = index;
    final wide = !DashBreakpoints.isPhone(context);
    final labelStyle = DashType.small.copyWith(color: c.textSecondary);

    final name = DashTextField(
      key: ValueKey('grp-option-name-$i'),
      label: t('common.name'),
      value: o.name,
      placeholder: t('menu.groups.editor.optionNamePh'),
      errorText: errors[GroupField.optionName(i)],
      onChanged: (v) => onEdit(() => o.name = v),
    );
    final nameAr = DashTextField(
      key: ValueKey('grp-option-ar-$i'),
      label: t('menu.groups.editor.arabicName'),
      value: o.nameAr,
      textDirection: TextDirection.rtl,
      onChanged: (v) => onEdit(() => o.nameAr = v),
    );
    final price = SizedBox(
      width: wide ? _priceWidth : null,
      child: DashTextField(
        key: ValueKey('grp-option-price-$i'),
        label: t('menu.groups.editor.priceAdds'),
        value: o.price,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        errorText: errors[GroupField.optionPrice(i)],
        onChanged: (v) => onEdit(() => o.price = cleanDecimal(v)),
      ),
    );
    Widget toggle(String label, bool value, ValueChanged<bool> on) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        DashSwitch(value: value, onChanged: on, semanticLabel: label),
        Text(label, style: labelStyle),
      ],
    );
    final switches = [
      toggle(
        t('common.active'),
        o.isActive,
        (v) => onEdit(() => o.isActive = v),
      ),
      toggle(t('menu.groups.editor.isDefault'), o.isDefault, onDefault),
      DashIconButton(
        icon: 'trash-2',
        semanticLabel: t('menu.groups.editor.removeOption'),
        color: c.errorText,
        onPressed: onRemove,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: Space.sm,
              children: [
                Expanded(child: name),
                Expanded(child: nameAr),
                price,
                ...switches,
              ],
            )
          else ...[
            name,
            nameAr,
            price,
            Wrap(
              spacing: Space.md,
              runSpacing: Space.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: switches,
            ),
          ],
          if (effect == GroupEffect.swaps)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.xs,
              children: [
                Text(t('menu.groups.editor.usesIngredient'), style: labelStyle),
                SizedBox(
                  width: wide ? 288 : double.infinity,
                  child: DashSelect<String>(
                    key: ValueKey('grp-option-swap-$i'),
                    options: swapChoices,
                    value: o.swapIngredientId.isEmpty
                        ? null
                        : o.swapIngredientId,
                    searchable: true,
                    invalid: errors[GroupField.optionSwap(i)] != null,
                    semanticLabel: t('menu.groups.editor.usesIngredient'),
                    searchPlaceholder: t('common.search'),
                    emptyText: t('common.noResults'),
                    onChanged: (v) => onEdit(() => o.swapIngredientId = v),
                  ),
                ),
                if (errors[GroupField.optionSwap(i)] case final e?)
                  Text(e, style: DashType.small.copyWith(color: c.errorText)),
              ],
            )
          else if (effect == GroupEffect.adds)
            _Deducts(
              index: i,
              option: o,
              errors: errors,
              byId: byId,
              ingredientChoices: ingredientChoices,
              onEdit: onEdit,
              cost: optionLinesCost(o.lines, (id) {
                final ing = byId[id];
                return ing == null
                    ? null
                    : (costPerUnit: ing.costPerUnit, unit: ing.unit);
              }),
              fmtMoney: (v) => fmt.fmtMoney(v),
            ),
        ],
      ),
    );
  }
}

/// "Deducts": the per-size switch, then either the grid or the plain lines
/// with "Add ingredient" and their cost.
class _Deducts extends ConsumerWidget {
  const _Deducts({
    required this.index,
    required this.option,
    required this.errors,
    required this.byId,
    required this.ingredientChoices,
    required this.onEdit,
    required this.cost,
    required this.fmtMoney,
  });

  final int index;
  final OptionDraft option;
  final Map<String, String> errors;
  final Map<String, OrgIngredient> byId;
  final List<DashOption<String>> ingredientChoices;
  final void Function(VoidCallback change) onEdit;
  final double? cost;
  final String Function(num v) fmtMoney;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final o = option;
    final i = index;
    final allLabel = t('modeling.grid.allSizes');
    final small = DashType.small.copyWith(color: c.textSecondary);
    // A new group is attached to no item yet: its columns are the lines' own.
    const itemSizeLabels = <String>[];

    final Widget body;
    if (o.perSize) {
      final blocks = o.currentBlocks(itemSizeLabels, allLabel);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          LabelGridEditor(
            key: ValueKey('grp-option-grid-$i'),
            blocks: blocks,
            catalogById: byId,
            ingredientOptions: ingredientChoices,
            onChanged: (next) => onEdit(() => o.setBlocks(next)),
            onAddColumn: (label) =>
                onEdit(() => o.setBlocks(addLabelColumn(blocks, label))),
            removableKeys: {
              for (final b in blocks)
                if (b.key != allSizes) b.key,
            },
            onRemoveColumn: (key) =>
                onEdit(() => o.setBlocks(removeLabelColumn(blocks, key))),
          ),
          if (errors[GroupField.optionGrid(i)] case final e?)
            Text(e, style: DashType.small.copyWith(color: c.errorText)),
          Text(t('modeling.options.perSizeHint'), style: small),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          for (final (j, l) in o.lines.indexed)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.sm,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: Space.xs,
                    children: [
                      DashSelect<String>(
                        key: ValueKey('grp-line-$i-$j'),
                        options: ingredientChoices,
                        value: l.ingredientId.isEmpty ? null : l.ingredientId,
                        searchable: true,
                        invalid:
                            errors[GroupField.lineIngredient(i, j)] != null,
                        semanticLabel: t('recipes.ingredient'),
                        searchPlaceholder: t('common.search'),
                        emptyText: t('common.noResults'),
                        onChanged: (id) => onEdit(
                          () => o.lines[j] = l.copyWith(
                            ingredientId: id,
                            unit: byId[id]?.unit ?? l.unit,
                          ),
                        ),
                      ),
                      if (errors[GroupField.lineIngredient(i, j)] case final e?)
                        Text(
                          e,
                          style: DashType.small.copyWith(color: c.errorText),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.xs,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: Space.xs + DashMetrics.hair,
                      children: [
                        SizedBox(
                          width: _amountWidth,
                          child: DashTextInput(
                            key: ValueKey('grp-line-qty-$i-$j'),
                            value: l.quantity,
                            semanticLabel: t('menu.groups.editor.amount'),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textDirection: TextDirection.ltr,
                            invalid:
                                errors[GroupField.lineQuantity(i, j)] != null,
                            onChanged: (v) => onEdit(
                              () => o.lines[j] = l.copyWith(
                                quantity: cleanDecimal(v),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: Space.xl,
                          child: Text(unitWord(t, l.unit), style: small),
                        ),
                      ],
                    ),
                    if (errors[GroupField.lineQuantity(i, j)] case final e?)
                      Text(
                        e,
                        style: DashType.small.copyWith(color: c.errorText),
                      ),
                  ],
                ),
                DashIconButton(
                  icon: 'trash-2',
                  semanticLabel: t('menu.groups.editor.removeLine'),
                  onPressed: () => onEdit(() => o.lines.removeAt(j)),
                ),
              ],
            ),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DashButton(
                label: t('menu.groups.editor.addLine'),
                icon: 'plus',
                variant: DashButtonVariant.ghost,
                size: DashButtonSize.compact,
                onPressed: () => onEdit(
                  () => o.lines.add(
                    const OptionLineDraft(
                      ingredientId: '',
                      quantity: '',
                      unit: 'g',
                    ),
                  ),
                ),
              ),
              if (cost case final v?)
                Text(
                  '${t('menu.groups.editor.cost')} ${fmtMoney(v)}',
                  style: small,
                ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        Text(
          t('menu.groups.editor.deducts'),
          style: DashType.smallMedium.copyWith(color: c.textSecondary),
        ),
        Row(
          spacing: Space.sm,
          children: [
            DashSwitch(
              value: o.perSize,
              semanticLabel: t('modeling.options.perSize'),
              onChanged: (on) =>
                  onEdit(() => o.togglePerSize(on, itemSizeLabels, allLabel)),
            ),
            Flexible(child: Text(t('modeling.options.perSize'), style: small)),
          ],
        ),
        body,
      ],
    );
  }
}
