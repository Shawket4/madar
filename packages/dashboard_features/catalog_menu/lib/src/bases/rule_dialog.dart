/// The packaging-rule dialog (MENU-PKG-009..016), 672 wide on a wide screen
/// and a full-screen form on a phone. Web: `RuleDialog` in
/// `features/menu/recipe/packaging-rules-page.tsx`.
///
/// - Every open starts from the rule as listed (a new widget each time).
/// - Name is required once trimmed. A match left on "Any" (or a blank size
///   label) is sent as null; the three matches sit side by side from 640
///   wide and stack below.
/// - The lines grid has one fixed "Quantity" column; blank cells are no line.
/// - Save: POST (new) or PATCH (edit) with the whole rule, toast, refresh the
///   rules (not the catalog: a rule takes effect on "Apply rules").
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        CreatePackagingRuleRequest,
        OrgIngredient,
        PackagingRuleLineInput,
        PackagingRuleLineOut,
        PackagingRuleOut,
        PatchPackagingRuleRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/grid_model.dart';
import '../shared/ingredient_options.dart';
import '../shared/label_grid_editor.dart';
import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';
import 'bases_providers.dart';
import 'bases_widgets.dart';

/// The "Any" option's value (the web's `ANY = ""`).
const String _any = '';

/// The single lines column's key (the web's `RULE_COL`).
const String _ruleCol = 'qty';

/// The menu categories as match options: id, translated name, POS order.
List<DashOption<String>> ruleCategoryOptions(
  WidgetRef ref,
  String? orgId,
  Translator t,
) => orgId == null
    ? const []
    : [
        for (final c
            in ref.watch(menuCategoriesProvider(orgId)).value ?? const [])
          DashOption<String>(
            value: c.id,
            label: translatedName(c.name, c.nameTranslations, t.lang),
          ),
      ];

/// The first 500 menu items as match options: id, name (not translated, as
/// the web shows them).
List<DashOption<String>> ruleItemOptions(WidgetRef ref, String? orgId) =>
    orgId == null
    ? const []
    : [
        for (final m
            in ref.watch(packagingItemOptionsProvider(orgId)).value ?? const [])
          DashOption<String>(value: m.id, label: m.name),
      ];

/// Opens the dialog: a new rule when [rule] is null.
Future<void> showRuleDialog(
  BuildContext context, {
  required String? orgId,
  required PackagingRuleOut? rule,
}) => showDashDialog<void>(
  context,
  width: DashMetrics.dialogWide,
  builder: (_) => RuleDialog(orgId: orgId, rule: rule),
);

class RuleDialog extends ConsumerStatefulWidget {
  const RuleDialog({required this.orgId, this.rule, super.key});

  /// Null when no org is in scope (the pickers and the catalog are empty).
  final String? orgId;

  /// Null = a new rule.
  final PackagingRuleOut? rule;

  @override
  ConsumerState<RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends ConsumerState<RuleDialog> {
  late String _name = widget.rule?.name ?? '';
  late String _category = widget.rule?.matchCategoryId ?? _any;
  late String _sizeLabel = widget.rule?.matchSizeLabel ?? '';
  late String _item = widget.rule?.matchItemId ?? _any;
  late bool _active = widget.rule?.isActive ?? true;
  late List<GridBlock> _blocks;
  bool _submitted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final t = ref.read(tProvider);
    _blocks = [
      GridBlock(
        key: _ruleCol,
        label: t('common.quantity'),
        lines: [
          for (final l in widget.rule?.lines ?? const <PackagingRuleLineOut>[])
            GridLine(
              ingredientId: l.ingredientId,
              quantity: jsNumberText(jsNumber(l.quantity)),
              unit: l.unit,
            ),
        ],
      ),
    ];
  }

  Future<void> _save() async {
    if (_busy) return;
    final t = ref.read(tProvider);
    setState(() => _submitted = true);
    final name = _name.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final category = _category.isEmpty ? null : _category;
    final label = _sizeLabel.trim().isEmpty ? null : _sizeLabel.trim();
    final item = _item.isEmpty ? null : _item;
    final nulls = {
      if (category == null) 'match_category_id',
      if (label == null) 'match_size_label',
      if (item == null) 'match_item_id',
    };
    final lines = [
      for (final l in ownPayload(_blocks.firstOrNull?.lines ?? const []))
        PackagingRuleLineInput(
          ingredientId: l.ingredientId,
          quantity: l.quantity,
          unit: l.unit,
        ),
    ];
    final api = ref.read(apiProvider).menu;
    final invalidate = ref.menuInvalidate;
    try {
      final rule = widget.rule;
      if (rule != null) {
        await api.patchRule(
          id: rule.id,
          body: PatchPackagingRuleRequest(
            name: name,
            matchCategoryId: category,
            matchSizeLabel: label,
            matchItemId: item,
            isActive: _active,
            lines: lines,
            explicitNulls: nulls,
          ),
        );
      } else {
        await api.createRule(
          body: CreatePackagingRuleRequest(
            name: name,
            matchCategoryId: category,
            matchSizeLabel: label,
            matchItemId: item,
            isActive: _active,
            lines: lines,
            explicitNulls: nulls,
          ),
        );
      }
      invalidate.paths(const [MenuPaths.packagingRules]);
      if (!mounted) return;
      DashToast.success(context, t('modeling.packaging.saved'));
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final orgId = widget.orgId;
    final catalog = orgId == null
        ? const <OrgIngredient>[]
        : ref.watch(ingredientCatalogProvider(orgId)).value ??
              const <OrgIngredient>[];
    final any = DashOption<String>(
      value: _any,
      label: t('modeling.packaging.any'),
    );

    final matches = [
      DashSelectField<String>(
        label: t('modeling.packaging.matchCategory'),
        options: [any, ...ruleCategoryOptions(ref, orgId, t)],
        value: _category,
        searchable: true,
        searchPlaceholder: t('common.search'),
        emptyText: t('common.noResults'),
        onChanged: (v) => setState(() => _category = v),
      ),
      DashTextField(
        label: t('modeling.packaging.matchSize'),
        placeholder: t('modeling.packaging.any'),
        value: _sizeLabel,
        onChanged: (v) => setState(() => _sizeLabel = v),
        onSubmitted: (_) => _save(),
      ),
      DashSelectField<String>(
        label: t('modeling.packaging.matchItem'),
        options: [any, ...ruleItemOptions(ref, orgId)],
        value: _item,
        searchable: true,
        searchPlaceholder: t('common.search'),
        emptyText: t('common.noResults'),
        onChanged: (v) => setState(() => _item = v),
      ),
    ];

    return DashSurface(
      title: widget.rule == null
          ? t('modeling.packaging.new')
          : t('modeling.packaging.edit'),
      description: t('modeling.packaging.matchHelp'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          DashTextField(
            label: t('common.name'),
            value: _name,
            errorText: _submitted && _name.trim().isEmpty
                ? t('common.requiredField')
                : null,
            onChanged: (v) => setState(() => _name = v),
            onSubmitted: (_) => _save(),
          ),
          if (MediaQuery.sizeOf(context).width >= DashBreakpoints.sm)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [for (final m in matches) Expanded(child: m)],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: matches,
            ),
          ModelingSwitch(
            label: t('common.active'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          LabelGridEditor(
            blocks: _blocks,
            onChanged: (b) => setState(() => _blocks = b),
            catalogById: ingredientsById(catalog),
            ingredientOptions: ingredientOptions(catalog, t),
            onSubmit: _save,
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
