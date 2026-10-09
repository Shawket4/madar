/// The choice-group editor (the web's
/// `features/menu/groups/group-editor-dialog.tsx`, MENU-GRP-023..049):
/// create or edit a group, its options and what each option deducts. Opened
/// from the groups page, the add-on dialog ("New group") and the studio's
/// modifiers ("New group").
///
/// - Seeded once per opening (a background refetch never wipes typing); an
///   old swap group without `swap_category_id` waits for the ingredient
///   categories behind a spinner.
/// - Save writes the group, then each option (delete / patch / create), then
///   each option's recipe replace-set where it changed; then the catalog is
///   invalidated and the group re-read and handed back to the caller.
/// - Read-only (no `menu.items.edit`): every control disabled, "Close", no
///   Save.
/// - Fields the form hides are not validated (divergence MENU-GRP-049).
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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/ingredient_options.dart';
import '../shared/label_grid_editor.dart';
import '../shared/label_model.dart';
import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';
import 'group_form.dart';
import 'group_model.dart';
import 'groups_providers.dart';

/// Opens the editor: [group] null = a new group. Resolves with the saved
/// group as re-read from the server (the caller selects or attaches it), or
/// null when closed without saving.
Future<GroupOut?> showGroupEditorDialog(
  BuildContext context, {
  required String orgId,
  GroupOut? group,
  int? usedOn,
  VoidCallback? onManageItems,
  bool readOnly = false,
}) => showDashDialog<GroupOut>(
  context,
  width: GroupEditorDialog.width,
  builder: (_) => GroupEditorDialog(
    orgId: orgId,
    group: group,
    usedOn: usedOn,
    onManageItems: onManageItems,
    readOnly: readOnly,
  ),
);

class GroupEditorDialog extends ConsumerStatefulWidget {
  const GroupEditorDialog({
    required this.orgId,
    this.group,
    this.usedOn,
    this.onManageItems,
    this.readOnly = false,
    super.key,
  });

  /// The web's 768 px dialog.
  static const double width = 768;

  final String orgId;

  /// Null = create a new group.
  final GroupOut? group;

  /// Items the group is attached to, when known ("Used on N items"); the
  /// live usage replaces it once loaded.
  final int? usedOn;

  /// "Manage…": opens the usage dialog on top (the row shows whenever this
  /// or [usedOn] is given).
  final VoidCallback? onManageItems;

  /// Without the capability: every control disabled, no Save.
  final bool readOnly;

  @override
  ConsumerState<GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends ConsumerState<GroupEditorDialog> {
  /// The form, seeded once; null while seeding waits.
  GroupDraft? _draft;

  /// The same seed, untouched: what each option's recipe was.
  GroupDraft? _seeded;

  /// The group as it was when the form was seeded (the save's originals).
  GroupOut? _base;

  /// The person has changed something: a background refresh no longer
  /// re-seeds the form.
  bool _touched = false;
  bool _submitted = false;
  bool _busy = false;

  /// Where each message's field sits, to scroll a failed Save to the first.
  final Map<String, GlobalKey> _keys = {};

  GlobalKey _keyFor(String path) => _keys.putIfAbsent(path, GlobalKey.new);

  GroupsQuery get _groupsKey => (orgId: widget.orgId, includeInactive: false);

  GroupMessages _messages(Translator t) => GroupMessages(
    required: t('common.requiredField'),
    maxAtLeastOne: t('menu.groups.editor.maxAtLeastOne'),
    swapNeedsIngredient: t('menu.groups.editor.swapNeedsIngredient'),
    swapNeedsCategory: t('menu.groups.editor.swapNeedsCategory'),
    duplicateIngredient: t('menu.groups.editor.duplicateIngredient'),
    qtyPositive: t('menu.groups.editor.qtyPositive'),
    priceMin: t('menu.groups.editor.priceMin'),
    notANumber: t('menu.groups.editor.notANumber'),
  );

  void _edit(VoidCallback change) => setState(() {
    _touched = true;
    change();
  });

  /// Scrolls the first message's field into view (`name`, `up_to`,
  /// `swap_category_id`, an option, or one of its lines).
  void _reveal(String path) {
    final p = path.split('.');
    final target = p.first != 'options'
        ? path
        : p.length >= 4 && p[2] == 'lines'
        ? p.take(4).join('.')
        : p.take(2).join('.');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[target]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.1,
          duration: DashMotion.of(ctx, DashMotion.base),
        );
      }
    });
  }

  Future<void> _save() async {
    final d = _draft;
    if (d == null || _busy || widget.readOnly) return;
    final t = ref.read(tProvider);
    setState(() => _submitted = true);
    final errors = validateGroup(d, _messages(t));
    if (errors.isNotEmpty) {
      _reveal(errors.keys.first);
      return;
    }
    setState(() => _busy = true);
    final api = ref.read(apiProvider).menu;
    final invalidate = ref.menuInvalidate;
    final catalog = ref.read(ingredientCatalogProvider(widget.orgId)).value;
    final unitById = {for (final c in catalog ?? const []) c.id: c.unit};
    String? unitOf(String id) => unitById[id];
    final sel = pickRuleToSelection(d.pickRule);
    final effect = d.effect.name;
    final swaps = d.effect == GroupEffect.swaps;
    final name = d.name.trim();
    final group = _base;
    try {
      GroupOut saved;
      if (group != null) {
        saved = await api.patchGroup(
          gid: group.id,
          body: PatchGroupRequest(
            name: name,
            nameTranslations: {..._map(group.nameTranslations), 'ar': d.nameAr},
            selectionType: sel.selectionType,
            minSelections: sel.minSelections,
            // `null` clears the limit ("any number").
            maxSelections: sel.maxSelections,
            isRequired: sel.isRequired,
            isActive: d.isActive,
            effect: effect,
            // The server derives `legacy_addon_type` from the effect.
            swapCategoryId: swaps ? d.swapCategoryId : null,
            explicitNulls: {
              if (sel.maxSelections == null) 'max_selections',
              if (!swaps) 'swap_category_id',
            },
          ),
        );
      } else {
        final listed = ref.read(modifierGroupsProvider(_groupsKey)).value;
        final taken = [
          for (final g in listed ?? const <GroupOut>[])
            if ((g.legacyAddonType ?? '').isNotEmpty) g.legacyAddonType!,
        ];
        saved = await api.createGroup(
          body: CreateGroupRequest(
            name: name,
            nameTranslations: d.nameAr.isNotEmpty
                ? {'ar': d.nameAr}
                : const <String, Object?>{},
            selectionType: sel.selectionType,
            minSelections: sel.minSelections,
            maxSelections: sel.maxSelections,
            isRequired: sel.isRequired,
            sort: listed?.length ?? 0,
            effect: effect,
            swapCategoryId: swaps ? d.swapCategoryId : null,
            // Swaps: derived server-side from the category. Others: a
            // name-derived type old tills show as its own section.
            legacyAddonType: swaps
                ? null
                : effectToLegacyType(d.effect, null, name, taken),
            explicitNulls: {
              if (sel.maxSelections == null) 'max_selections',
              if (!swaps) 'swap_category_id',
              if (swaps) 'legacy_addon_type',
            },
          ),
        );
        if (!d.isActive) {
          saved = await api.patchGroup(
            gid: saved.id,
            body: const PatchGroupRequest(isActive: false),
          );
        }
      }

      final originals = {for (final o in group?.options ?? const []) o.id: o};
      final seededById = {
        for (final o in _seeded?.options ?? const <OptionDraft>[])
          if (o.id != null) o.id!: o,
      };
      final kept = {for (final o in d.options) ?o.id};
      for (final id in originals.keys) {
        if (!kept.contains(id)) await api.deleteOption(oid: id);
      }

      for (final (sort, o) in d.options.indexed) {
        final price = jsRound(jsNumber(o.price) * 100);
        final swapIng = swaps && o.swapIngredientId.isNotEmpty
            ? o.swapIngredientId
            : null;
        final optionName = o.name.trim();
        var optionId = o.id;
        if (optionId != null) {
          final prev = originals[optionId]!;
          if (prev.name != optionName ||
              arOf(prev.nameTranslations) != o.nameAr ||
              prev.price != price ||
              prev.isActive != o.isActive ||
              prev.isDefault != o.isDefault ||
              prev.sort != sort ||
              prev.replacesIngredientId != swapIng) {
            await api.patchOption(
              oid: optionId,
              body: PatchOptionRequest(
                name: optionName,
                nameTranslations: {
                  ..._map(prev.nameTranslations),
                  'ar': o.nameAr,
                },
                price: price,
                isActive: o.isActive,
                isDefault: o.isDefault,
                sort: sort,
                // `null` clears the swap link (the group stopped swapping).
                replacesIngredientId: swapIng,
                explicitNulls: {if (swapIng == null) 'replaces_ingredient_id'},
              ),
            );
          }
        } else {
          optionId = (await api.createOption(
            gid: saved.id,
            body: CreateOptionRequest(
              name: optionName,
              nameTranslations: o.nameAr.isNotEmpty
                  ? {'ar': o.nameAr}
                  : const <String, Object?>{},
              price: price,
              isActive: o.isActive,
              replacesIngredientId: swapIng,
              explicitNulls: {if (swapIng == null) 'replaces_ingredient_id'},
            ),
          )).id;
          // CreateOptionRequest has no sort/is_default: set them right after.
          await api.patchOption(
            oid: optionId,
            body: PatchOptionRequest(sort: sort, isDefault: o.isDefault),
          );
        }
        final next = optionRecipeLines(
          d.effect,
          swapIngredientId: o.swapIngredientId,
          lines: o.lines,
          unitOf: unitOf,
        );
        final before = o.id == null ? null : seededById[o.id];
        final prevLines = before == null
            ? const <OptionWireLine>[]
            : optionRecipeLines(
                _seeded!.effect,
                swapIngredientId: before.swapIngredientId,
                lines: before.lines,
                unitOf: unitOf,
              );
        if (recipeSig(next) != recipeSig(prevLines)) {
          await api.putOptionRecipe(
            oid: optionId,
            body: [
              for (final l in next)
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
      // `saved` predates the option writes: hand back the group with them.
      final fresh = await api
          .listGroups(orgId: widget.orgId)
          .catchError((Object _) => const <GroupOut>[]);
      final result = fresh.where((g) => g.id == saved.id).firstOrNull ?? saved;
      if (!mounted) return;
      DashToast.success(context, t('common.savedChanges'));
      Navigator.of(context).pop(result);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  static Map<String, Object?> _map(Object? json) =>
      json is Map ? json.cast<String, Object?>() : const {};

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final opened = widget.group;
    // The group as listed now (the page's read, already in the cache): a
    // background refresh re-seeds the form until the person edits it.
    final group = opened == null
        ? null
        : ref
                  .watch(
                    modifierGroupsProvider((
                      orgId: widget.orgId,
                      includeInactive: true,
                    )),
                  )
                  .value
                  ?.where((g) => g.id == opened.id)
                  .firstOrNull ??
              opened;
    final catalogQ = ref.watch(ingredientCatalogProvider(widget.orgId));
    ref.watch(modifierGroupsProvider(_groupsKey));
    final categoriesQ = ref.watch(ingredientCategoriesProvider(widget.orgId));
    final sizeLabels = group == null
        ? const <String>[]
        : ref.watch(groupSizeLabelsProvider(group.id));
    final liveUsedOn = group == null
        ? null
        : ref.watch(groupUsageProvider(group.id)).value?.length;

    if (_draft == null || (!_touched && !identical(group, _base))) {
      final categories = categoriesQ.hasValue
          ? categoriesQ.requireValue
          : (categoriesQ.hasError ? const <IngredientCategory>[] : null);
      final seeded = seedGroupDraft(group, categories);
      if (seeded != null) {
        _draft = seeded;
        _seeded = seedGroupDraft(group, categories);
        _base = group;
      }
    }
    final d = _draft;

    return DashSurface(
      title: group == null
          ? t('menu.groups.editor.newTitle')
          : t('menu.groups.editor.editTitle'),
      description: t('menu.groups.editor.desc'),
      body: d == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.xxl),
              child: Center(child: _Spinner()),
            )
          : _EditorBody(
              draft: d,
              editing: group != null,
              readOnly: widget.readOnly,
              errors: _submitted ? validateGroup(d, _messages(t)) : const {},
              catalog: catalogQ.value ?? const [],
              catalogSettled: !catalogQ.isLoading || catalogQ.hasValue,
              categories: categoriesQ.value ?? const [],
              itemSizeLabels: sizeLabels,
              usedOn:
                  group != null &&
                      (widget.usedOn != null || widget.onManageItems != null)
                  ? liveUsedOn ?? widget.usedOn
                  : null,
              onManageItems: widget.onManageItems,
              onEdit: _edit,
              onSubmit: _save,
              keyFor: _keyFor,
            ),
      actions: [
        DashButton(
          label: widget.readOnly ? t('common.close') : t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        if (!widget.readOnly)
          DashButton(
            label: t('common.save'),
            loading: _busy,
            onPressed: d == null ? null : _save,
          ),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: IconSize.md,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: context.madarColors.textMuted,
    ),
  );
}

/// The form itself: name, what choosing does, the pick rule, the options and
/// the usage line.
class _EditorBody extends ConsumerWidget {
  const _EditorBody({
    required this.draft,
    required this.editing,
    required this.readOnly,
    required this.errors,
    required this.catalog,
    required this.catalogSettled,
    required this.categories,
    required this.itemSizeLabels,
    required this.usedOn,
    required this.onManageItems,
    required this.onEdit,
    required this.onSubmit,
    required this.keyFor,
  });

  final GroupDraft draft;
  final bool editing;
  final bool readOnly;
  final Map<String, String> errors;
  final List<OrgIngredient> catalog;

  /// The catalog read has answered (or failed): the "no ingredient to swap"
  /// note may show.
  final bool catalogSettled;
  final List<IngredientCategory> categories;
  final List<String> itemSizeLabels;
  final int? usedOn;
  final VoidCallback? onManageItems;
  final void Function(VoidCallback change) onEdit;
  final VoidCallback onSubmit;
  final GlobalKey Function(String path) keyFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final d = draft;
    final enabled = !readOnly;
    final swaps = d.effect == GroupEffect.swaps;
    final catalogById = ingredientsById(catalog);
    final swapOptions = [
      for (final o in catalog)
        if (o.isActive && o.categoryId == d.swapCategoryId)
          DashOption<String>(
            value: o.id,
            label: o.name,
            hint: unitWord(t, o.unit),
          ),
    ];

    Widget legend(String text) =>
        Text(text, style: DashType.bodyMedium.copyWith(color: c.textPrimary));

    final nameLabel = t('common.name');
    final name = _Pair(
      first: DashTextField(
        label: nameLabel,
        value: d.name,
        enabled: enabled,
        errorText: errors[GroupField.name],
        onChanged: (v) => onEdit(() => d.name = v),
        onSubmitted: (_) => onSubmit(),
      ),
      second: DashTextField(
        label: context.dashStrings.arabicLabel(nameLabel),
        value: d.nameAr,
        enabled: enabled,
        textDirection: TextDirection.rtl,
        onChanged: (v) => onEdit(() => d.nameAr = v),
        onSubmitted: (_) => onSubmit(),
      ),
    );

    Widget effectRow(GroupEffect value, String label, {Widget? inline}) {
      final on = d.effect == value;
      return DashPressable(
        onTap: enabled ? () => onEdit(() => d.effect = value) : null,
        enabled: enabled,
        isButton: false,
        selected: on,
        checked: on,
        semanticLabel: label,
        excludeChildSemantics: inline == null,
        pressScale: false,
        builder: (context, s) => Container(
          constraints: const BoxConstraints(minHeight: DashMetrics.target),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          decoration: BoxDecoration(
            color: on ? c.accentBg : null,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: on ? c.accent : c.hairline),
          ),
          child: Row(
            spacing: Space.sm,
            children: [
              DashRadioDot(selected: on, enabled: enabled, focused: s.focused),
              Expanded(
                child:
                    inline ??
                    Text(
                      label,
                      style: DashType.body.copyWith(color: c.textPrimary),
                    ),
              ),
            ],
          ),
        ),
      );
    }

    final swapCategoryError = errors[GroupField.swapCategory];
    final effect = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        legend(t('menu.groups.editor.effectLabel')),
        effectRow(GroupEffect.none, t('menu.groups.effect.none')),
        effectRow(GroupEffect.adds, t('menu.groups.effect.adds')),
        effectRow(
          GroupEffect.swaps,
          '${t('menu.groups.effect.swapsPrefix')} '
          '${t('menu.groups.effect.swapsSuffix')}',
          inline: Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                t('menu.groups.effect.swapsPrefix'),
                style: DashType.body.copyWith(color: c.textPrimary),
              ),
              SizedBox(
                width: _Metrics.categoryPicker,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DashSelect<String>(
                      options: [
                        for (final cat in categories)
                          DashOption(value: cat.id, label: cat.name),
                      ],
                      value: d.swapCategoryId.isEmpty ? null : d.swapCategoryId,
                      enabled: enabled,
                      searchable: true,
                      invalid: swapCategoryError != null,
                      placeholder: t('menu.groups.editor.swapCategoryPh'),
                      semanticLabel: t('menu.groups.editor.swapCategoryPh'),
                      searchPlaceholder: t('common.search'),
                      emptyText: t('common.noResults'),
                      onChanged: (id) => onEdit(() {
                        d
                          ..swapCategoryId = id
                          ..effect = GroupEffect.swaps;
                      }),
                    ),
                    if (swapCategoryError != null)
                      _FieldError(swapCategoryError),
                  ],
                ),
              ),
              Text(
                t('menu.groups.effect.swapsSuffix'),
                style: DashType.body.copyWith(color: c.textPrimary),
              ),
            ],
          ),
        ),
        if (d.effect == GroupEffect.none && editing)
          _Note(t('menu.groups.editor.noneClears')),
      ],
    );

    final upToError = errors[GroupField.upTo];
    final pick = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        legend(t('menu.groups.editor.pickLabel')),
        if (swaps)
          _Info(t('menu.groups.editor.swapExactlyOne'), small: false)
        else
          Wrap(
            spacing: Space.md,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              DashSegmentedControl<PickKind>(
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
                value: d.pick,
                enabled: enabled,
                semanticLabel: t('menu.groups.editor.pickLabel'),
                onChanged: (v) => onEdit(() => d.pick = v),
              ),
              if (d.pick == PickKind.upTo)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.sm,
                  children: [
                    SizedBox(
                      width: _Metrics.upTo,
                      child: DashTextInput(
                        value: d.upTo,
                        enabled: enabled,
                        mono: true,
                        invalid: upToError != null,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        semanticLabel: t('menu.groups.editor.upToCount'),
                        onChanged: (v) => onEdit(() => d.upTo = v),
                        onSubmitted: (_) => onSubmit(),
                      ),
                    ),
                    if (upToError != null) _FieldError(upToError),
                  ],
                ),
            ],
          ),
      ],
    );

    final options = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        legend(t('menu.groups.editor.optionsLabel')),
        _Info(switch (d.effect) {
          GroupEffect.swaps => t('menu.groups.editor.swapHelp'),
          GroupEffect.adds => t('menu.groups.editor.addsHelp'),
          GroupEffect.none => t('menu.groups.editor.noneHelp'),
        }),
        if (swaps && swapOptions.isEmpty && catalogSettled)
          Text(
            d.swapCategoryId.isNotEmpty
                ? t('menu.groups.editor.noSwapIngredients')
                : t('menu.groups.editor.swapPickCategory'),
            style: DashType.small.copyWith(color: c.danger),
          ),
        for (final (i, o) in d.options.indexed)
          KeyedSubtree(
            key: keyFor('options.$i'),
            child: _OptionCard(
              key: o.key,
              keyFor: keyFor,
              index: i,
              draft: d,
              option: o,
              enabled: enabled,
              errors: errors,
              catalogById: catalogById,
              ingredientOptions: ingredientOptions(catalog, t),
              swapOptions: swapOptions,
              itemSizeLabels: itemSizeLabels,
              onEdit: onEdit,
              onSubmit: onSubmit,
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DashButton(
            label: t('menu.groups.editor.addOption'),
            icon: 'plus',
            variant: DashButtonVariant.outline,
            size: DashButtonSize.compact,
            onPressed: enabled
                ? () =>
                      onEdit(() => d.options.add(OptionDraft(key: UniqueKey())))
                : null,
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        KeyedSubtree(key: keyFor(GroupField.name), child: name),
        KeyedSubtree(key: keyFor(GroupField.swapCategory), child: effect),
        KeyedSubtree(key: keyFor(GroupField.upTo), child: pick),
        options,
        if (usedOn != null)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.hairline)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Wrap(
                spacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    t('menu.groups.usedOn', count: usedOn),
                    style: DashType.body.copyWith(color: c.textPrimary),
                  ),
                  if (onManageItems != null)
                    DashButton(
                      label: t('menu.groups.manage'),
                      variant: DashButtonVariant.link,
                      size: DashButtonSize.compact,
                      onPressed: onManageItems,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One option: name, Arabic name, price, Active, Default, remove; then what
/// it pours (swaps) or deducts (adds).
class _OptionCard extends ConsumerWidget {
  const _OptionCard({
    required this.keyFor,
    required this.index,
    required this.draft,
    required this.option,
    required this.enabled,
    required this.errors,
    required this.catalogById,
    required this.ingredientOptions,
    required this.swapOptions,
    required this.itemSizeLabels,
    required this.onEdit,
    required this.onSubmit,
    super.key,
  });

  final GlobalKey Function(String path) keyFor;
  final int index;
  final GroupDraft draft;
  final OptionDraft option;
  final bool enabled;
  final Map<String, String> errors;
  final Map<String, OrgIngredient> catalogById;
  final List<DashOption<String>> ingredientOptions;
  final List<DashOption<String>> swapOptions;
  final List<String> itemSizeLabels;
  final void Function(VoidCallback change) onEdit;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final o = option;
    final i = index;

    final nameField = DashTextField(
      label: t('common.name'),
      value: o.name,
      placeholder: t('menu.groups.editor.optionNamePh'),
      enabled: enabled,
      errorText: errors[GroupField.optionName(i)],
      onChanged: (v) => onEdit(() => o.name = v),
      onSubmitted: (_) => onSubmit(),
    );
    final arField = DashTextField(
      label: t('menu.groups.editor.arabicName'),
      value: o.nameAr,
      enabled: enabled,
      textDirection: TextDirection.rtl,
      onChanged: (v) => onEdit(() => o.nameAr = v),
      onSubmitted: (_) => onSubmit(),
    );
    final priceField = DashTextField(
      label: t('menu.groups.editor.priceAdds'),
      value: o.price,
      enabled: enabled,
      mono: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_decimalInput(2)],
      errorText: errors[GroupField.optionPrice(i)],
      onChanged: (v) => onEdit(() => o.price = v),
      onSubmitted: (_) => onSubmit(),
    );
    final active = _LabelledSwitch(
      label: t('common.active'),
      value: o.isActive,
      enabled: enabled,
      onChanged: (v) => onEdit(() => o.isActive = v),
    );
    final isDefault = _LabelledSwitch(
      label: t('menu.groups.editor.isDefault'),
      value: o.isDefault,
      enabled: enabled,
      onChanged: (v) => onEdit(() => draft.setDefault(i, v)),
    );
    final remove = DashIconButton(
      icon: 'trash-2',
      color: c.danger,
      semanticLabel: t('menu.groups.editor.removeOption'),
      onPressed: enabled ? () => onEdit(() => draft.options.removeAt(i)) : null,
    );

    final head = LayoutBuilder(
      builder: (context, box) => box.maxWidth >= _Metrics.optionOneLine
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: Space.sm,
              children: [
                Expanded(child: nameField),
                Expanded(child: arField),
                SizedBox(width: _Metrics.price, child: priceField),
                active,
                isDefault,
                remove,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.sm,
              children: [
                nameField,
                arField,
                priceField,
                Row(
                  spacing: Space.md,
                  children: [active, isDefault, const Spacer(), remove],
                ),
              ],
            ),
    );

    Widget? detail;
    switch (draft.effect) {
      case GroupEffect.swaps:
        final err = errors[GroupField.optionSwap(i)];
        detail = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.xs,
          children: [
            _SmallLabel(t('menu.groups.editor.usesIngredient')),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _Metrics.swapPicker),
              child: DashSelect<String>(
                options: swapOptions,
                value: o.swapIngredientId.isEmpty ? null : o.swapIngredientId,
                enabled: enabled,
                searchable: true,
                invalid: err != null,
                semanticLabel: t('menu.groups.editor.usesIngredient'),
                searchPlaceholder: t('common.search'),
                emptyText: t('common.noResults'),
                onChanged: (id) => onEdit(() => o.swapIngredientId = id),
              ),
            ),
            if (err != null) _FieldError(err),
          ],
        );
      case GroupEffect.adds:
        detail = _AddsBlock(
          keyFor: keyFor,
          index: i,
          option: o,
          enabled: enabled,
          errors: errors,
          catalogById: catalogById,
          ingredientOptions: ingredientOptions,
          itemSizeLabels: itemSizeLabels,
          cost: optionLinesCost(o.lines, (id) {
            final ing = catalogById[id];
            return ing == null
                ? null
                : (costPerUnit: ing.costPerUnit, unit: ing.unit);
          }),
          fmt: fmt,
          onEdit: onEdit,
          onSubmit: onSubmit,
        );
      case GroupEffect.none:
        detail = null;
    }

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        border: Border.all(color: c.hairline),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [head, ?detail],
      ),
    );
  }
}

/// An "Adds ingredients" option's deductions: the per-size switch, then the
/// plain line list or the per-size grid.
class _AddsBlock extends ConsumerWidget {
  const _AddsBlock({
    required this.keyFor,
    required this.index,
    required this.option,
    required this.enabled,
    required this.errors,
    required this.catalogById,
    required this.ingredientOptions,
    required this.itemSizeLabels,
    required this.cost,
    required this.fmt,
    required this.onEdit,
    required this.onSubmit,
  });

  final GlobalKey Function(String path) keyFor;
  final int index;
  final OptionDraft option;
  final bool enabled;
  final Map<String, String> errors;
  final Map<String, OrgIngredient> catalogById;
  final List<DashOption<String>> ingredientOptions;
  final List<String> itemSizeLabels;
  final double? cost;
  final DashFormat fmt;
  final void Function(VoidCallback change) onEdit;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final o = option;
    final i = index;
    final allLabel = t('modeling.grid.allSizes');

    final Widget body;
    if (o.perSize) {
      final blocks = o.currentBlocks(itemSizeLabels, allLabel);
      final gridError = errors[GroupField.optionGrid(i)];
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          LabelGridEditor(
            blocks: blocks,
            enabled: enabled,
            catalogById: catalogById,
            ingredientOptions: ingredientOptions,
            onChanged: (next) => onEdit(() => o.setBlocks(next)),
            onAddColumn: (label) =>
                onEdit(() => o.setBlocks(addLabelColumn(blocks, label))),
            removableKeys: {
              for (final b in blocks)
                if (b.key != allSizes) b.key,
            },
            onRemoveColumn: (key) =>
                onEdit(() => o.setBlocks(removeLabelColumn(blocks, key))),
            onSubmit: onSubmit,
          ),
          if (gridError != null) _FieldError(gridError),
          Text(
            t('modeling.options.perSizeHint'),
            style: DashType.small.copyWith(color: c.textMuted),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          for (final (j, l) in o.lines.indexed)
            KeyedSubtree(
              key: keyFor('options.$i.lines.$j'),
              child: _LineRow(
                key: ObjectKey(l),
                line: l,
                enabled: enabled,
                ingredientError: errors[GroupField.lineIngredient(i, j)],
                quantityError: errors[GroupField.lineQuantity(i, j)],
                ingredientOptions: ingredientOptions,
                onIngredient: (id) => onEdit(() {
                  o.lines[j] = OptionLineDraft(
                    ingredientId: id,
                    quantity: l.quantity,
                    unit: catalogById[id]?.unit ?? l.unit,
                    sizeLabel: l.sizeLabel,
                  );
                }),
                onQuantity: (v) =>
                    onEdit(() => o.lines[j] = o.lines[j].copyWith(quantity: v)),
                onRemove: () => onEdit(() => o.lines.removeAt(j)),
                onSubmit: onSubmit,
              ),
            ),
          Wrap(
            spacing: Space.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DashButton(
                label: t('menu.groups.editor.addLine'),
                icon: 'plus',
                variant: DashButtonVariant.ghost,
                size: DashButtonSize.compact,
                onPressed: enabled
                    ? () => onEdit(
                        () => o.lines.add(
                          const OptionLineDraft(
                            ingredientId: '',
                            quantity: '',
                            unit: 'g',
                          ),
                        ),
                      )
                    : null,
              ),
              if (cost != null)
                Text(
                  '${t('menu.groups.editor.cost')} ${fmt.fmtMoney(cost)}',
                  style: DashType.small.copyWith(color: c.textMuted),
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
        _SmallLabel(t('menu.groups.editor.deducts'), strong: true),
        _LabelledSwitch(
          label: t('modeling.options.perSize'),
          value: o.perSize,
          enabled: enabled,
          onChanged: (on) =>
              onEdit(() => o.togglePerSize(on, itemSizeLabels, allLabel)),
        ),
        body,
      ],
    );
  }
}

/// One deducted line: the ingredient, the amount and its unit, remove.
class _LineRow extends ConsumerWidget {
  const _LineRow({
    required this.line,
    required this.enabled,
    required this.ingredientError,
    required this.quantityError,
    required this.ingredientOptions,
    required this.onIngredient,
    required this.onQuantity,
    required this.onRemove,
    required this.onSubmit,
    super.key,
  });

  final OptionLineDraft line;
  final bool enabled;
  final String? ingredientError;
  final String? quantityError;
  final List<DashOption<String>> ingredientOptions;
  final ValueChanged<String> onIngredient;
  final ValueChanged<String> onQuantity;
  final VoidCallback onRemove;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final picker = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DashSelect<String>(
          options: ingredientOptions,
          value: line.ingredientId.isEmpty ? null : line.ingredientId,
          enabled: enabled,
          searchable: true,
          invalid: ingredientError != null,
          semanticLabel: t('recipes.ingredient'),
          searchPlaceholder: t('common.search'),
          emptyText: t('common.noResults'),
          onChanged: onIngredient,
        ),
        if (ingredientError != null) _FieldError(ingredientError!),
      ],
    );
    final rest = [
      SizedBox(
        width: _Metrics.amount,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            DashTextInput(
              value: line.quantity,
              enabled: enabled,
              mono: true,
              invalid: quantityError != null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [_decimalInput(null)],
              semanticLabel: t('menu.groups.editor.amount'),
              onChanged: onQuantity,
              onSubmitted: (_) => onSubmit(),
            ),
            if (quantityError != null) _FieldError(quantityError!),
          ],
        ),
      ),
      SizedBox(
        width: _Metrics.unit,
        height: DashMetrics.control,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            unitWord(t, line.unit),
            style: DashType.small.copyWith(color: c.textMuted),
          ),
        ),
      ),
      DashIconButton(
        icon: 'trash-2',
        semanticLabel: t('menu.groups.editor.removeLine'),
        onPressed: enabled ? onRemove : null,
      ),
    ];
    // The web's `flex-wrap` with a `min-w-48` picker: below that the amount
    // goes under the picker.
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= _Metrics.lineOneLine
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.sm,
              children: [
                Expanded(child: picker),
                ...rest,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.sm,
              children: [
                picker,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.sm,
                  children: rest,
                ),
              ],
            ),
    );
  }
}

/// Keeps digits and one dot (a comma reads as a dot), at most [decimals]
/// after it: what the web's `type=number` inputs let through (no minus).
TextInputFormatter _decimalInput(int? decimals) =>
    TextInputFormatter.withFunction((old, next) {
      final clean = cleanDecimal(next.text);
      final dot = clean.indexOf('.');
      if (decimals != null && dot != -1 && clean.length - dot - 1 > decimals) {
        return old;
      }
      return clean == next.text
          ? next
          : TextEditingValue(
              text: clean,
              selection: TextSelection.collapsed(offset: clean.length),
            );
    });

/// The two name inputs, side by side once there is room (the web's
/// `BilingualField`).
class _Pair extends StatelessWidget {
  const _Pair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => box.maxWidth >= _Metrics.pairSideBySide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(child: first),
              Expanded(child: second),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [first, second],
          ),
  );
}

/// The switch, then its words (a tap on the words toggles it too).
class _LabelledSwitch extends StatelessWidget {
  const _LabelledSwitch({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DashSwitch(
        value: value,
        enabled: enabled,
        semanticLabel: label,
        onChanged: onChanged,
      ),
      GestureDetector(
        onTap: enabled ? () => onChanged(!value) : null,
        child: ExcludeSemantics(
          child: Text(
            label,
            style: DashType.small.copyWith(
              color: context.madarColors.textSecondary,
            ),
          ),
        ),
      ),
    ],
  );
}

class _SmallLabel extends StatelessWidget {
  const _SmallLabel(this.text, {this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: (strong ? DashType.smallMedium : DashType.small).copyWith(
      color: context.madarColors.textSecondary,
    ),
  );
}

/// An info glyph and a muted line.
class _Info extends StatelessWidget {
  const _Info(this.text, {this.small = true});

  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: DashMetrics.hair),
          child: DashIcon('info', size: IconSize.sm, color: c.textMuted),
        ),
        Expanded(
          child: Text(
            text,
            style: (small ? DashType.small : DashType.body).copyWith(
              color: c.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: DashType.small.copyWith(color: context.madarColors.textSecondary),
  );
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.xs),
    child: Text(
      text,
      style: DashType.small.copyWith(color: context.madarColors.danger),
    ),
  );
}

/// The web's fixed widths: `w-48` category picker, `w-20` count, `7rem`
/// price, `sm:w-72` swap picker, `w-24` amount, `w-8` unit; the `sm:` grid
/// of an option row and the `sm:` side-by-side names.
abstract final class _Metrics {
  static const double categoryPicker = Space.xxl * 6;
  static const double upTo = Space.xxl * 2.5;
  static const double price = Space.xxl * 3.5;
  static const double swapPicker = Space.xxl * 9;
  static const double amount = Space.xxl * 3;
  static const double unit = Space.xl + Space.sm;
  static const double optionOneLine = Space.xxl * 17;
  static const double lineOneLine = Space.xxl * 12;
  static const double pairSideBySide = Space.xxl * 14;
}
