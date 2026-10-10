/// The ingredient dialog (INV-ING-014…032, -050, -055; web
/// `item-dialog.tsx`): New ingredient (with optional reorder levels per
/// active branch) or Edit ingredient. Opening stock is never typed here; it
/// comes from the first count or a delivery.
///
/// No zod schema: Save is off while the name (or a new category's name) is
/// blank; numbers are read like `parseFloat` (blank → null).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        Branch,
        CreateCatalogItemRequest,
        CreateIngredientCategoryRequest,
        IngredientCategory,
        OrgIngredient,
        SetParRequest,
        UpdateCatalogItemRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

import '../shared/inventory_data.dart';
import '../shared/inventory_labels.dart';
import '../shared/inventory_lib.dart';
import 'ingredients_data.dart';

/// Opens the dialog: [item] null = create. True once saved (inventory
/// invalidated, toast shown).
Future<bool?> showIngredientDialog(
  BuildContext context, {
  required String orgId,
  required List<Branch> branches,
  OrgIngredient? item,
}) => showDashDialog<bool>(
  context,
  builder: (_) =>
      IngredientDialog(orgId: orgId, branches: branches, item: item),
);

/// The "New category…" choice of the category select.
const String newCategoryValue = '__new__';

/// What an `<input type="number">` takes: digits (Latin or Arabic-Indic),
/// a decimal sign and a minus (`min="0"` is not enforced while typing; the
/// server refuses a negative level).
final TextInputFormatter ingredientNumberChars =
    FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩.٫−-]'));

/// A labelled `<input type="number" min="0">`: mono, the figure left to
/// right but on the line's start side (right in Arabic), "—" when empty.
class IngredientNumberField extends StatelessWidget {
  const IngredientNumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.placeholder = '—',
    super.key,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String placeholder;

  @override
  Widget build(BuildContext context) => DashFormField<String>(
    label: label,
    value: value,
    builder: (context, invalid) => IngredientNumberInput(
      value: value,
      onChanged: onChanged,
      placeholder: placeholder,
      semanticLabel: label,
      invalid: invalid,
    ),
  );
}

/// The bare number input of [IngredientNumberField] (the per-branch grid).
class IngredientNumberInput extends StatelessWidget {
  const IngredientNumberInput({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.placeholder = '—',
    this.invalid = false,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String semanticLabel;
  final String placeholder;
  final bool invalid;

  @override
  Widget build(BuildContext context) => DashTextInput(
    value: value,
    onChanged: onChanged,
    placeholder: placeholder,
    semanticLabel: semanticLabel,
    invalid: invalid,
    mono: true,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textDirection: TextDirection.ltr,
    textAlign: Directionality.of(context) == TextDirection.rtl
        ? TextAlign.right
        : TextAlign.left,
    inputFormatters: [ingredientNumberChars],
  );
}

/// Warms the dialog's own reads (categories, suppliers) on a press's intent.
void warmIngredientDialog(WidgetRef ref, String orgId) {
  ref.warm(ingredientCategoriesProvider(orgId));
  ref.warm(inventorySuppliersProvider(orgId));
}

class IngredientDialog extends ConsumerStatefulWidget {
  const IngredientDialog({
    required this.orgId,
    required this.branches,
    this.item,
    super.key,
  });

  final String orgId;

  /// The org's ACTIVE branches (a reorder-levels row each, create only).
  final List<Branch> branches;
  final OrgIngredient? item;

  @override
  ConsumerState<IngredientDialog> createState() => _IngredientDialogState();
}

class _IngredientDialogState extends ConsumerState<IngredientDialog> {
  late OrgIngredient? _item = widget.item;
  late String _name;
  late String? _categoryId;
  String _newCategory = '';
  late String _unit;
  late String _cost;
  late String? _supplierId;
  late String _description;
  late String _packUnit;
  late String _packSize;
  late String _yieldPct;
  late String _density;

  /// Set by the person's first change: until then a fresher catalog row
  /// fills the fields again (a background refresh lands).
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _seed(_item);
  }

  void _seed(OrgIngredient? it) {
    _name = it?.name ?? '';
    _categoryId = it?.categoryId;
    _unit = it?.unit ?? 'g';
    _cost = costFieldText(it?.costPerUnit);
    _supplierId = it?.supplierId;
    _description = it?.description ?? '';
    _packUnit = it?.packUnit ?? '';
    _packSize = numberFieldText(it?.packSize);
    _yieldPct = numberFieldText(it?.yieldPct);
    _density = numberFieldText(it?.densityGPerMl);
  }

  void _edit(VoidCallback change) => setState(() {
    _edited = true;
    change();
  });
  bool _advanced = false;
  final Map<String, ({String min, String max})> _pars = {};
  bool _busy = false;

  // What an earlier Save of this dialog already created, so pressing Save
  // again after a failure does not create it twice (divergence INV-ING-055).
  ({String id, String name})? _createdCategory;
  OrgIngredient? _created;

  bool get _editing => _item != null;
  bool get _isNewCategory => _categoryId == newCategoryValue;
  bool get _unitChanged => _editing && _unit != _item!.unit;
  bool get _canSave =>
      _name.trim().isNotEmpty &&
      (!_isNewCategory || _newCategory.trim().isNotEmpty);

  String? _orNull(String v) => v.trim().isEmpty ? null : v.trim();

  /// The category a new ingredient starts on once the list is in: `general`,
  /// else the first (INV-ING-014).
  String? _effectiveCategory(List<IngredientCategory> cats) {
    if (_categoryId != null || _editing) return _categoryId;
    final general = cats.where((c) => c.slug == 'general').firstOrNull;
    return (general ?? cats.firstOrNull)?.id;
  }

  Future<void> _submit(String? categoryId) async {
    if (!_canSave) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).inventory;
    // Captured now: the lists refresh even if the dialog closes mid-save.
    final bus = ref.read(realtimeBusProvider);
    // An untouched field keeps the stored figure exactly (INV-ING-020).
    final cost = _cost == costFieldText(_item?.costPerUnit)
        ? _item?.costPerUnit
        : costInputToPiastres(_cost);
    final packUnit = _orNull(_packUnit);
    final packSize = parseNumberInput(_packSize);
    final yieldPct = parseNumberInput(_yieldPct);
    final density = parseNumberInput(_density);
    final description = _orNull(_description);
    setState(() => _busy = true);
    try {
      var category = categoryId;
      if (_isNewCategory) {
        final name = _newCategory.trim();
        if (_createdCategory?.name != name) {
          final made = await api.createIngredientCategory(
            orgId: widget.orgId,
            body: CreateIngredientCategoryRequest(name: name),
          );
          _createdCategory = (id: made.id, name: name);
        }
        category = _createdCategory!.id;
      }
      // The web sends these as explicit nulls when blank.
      final nulls = {
        if (category == null) 'category_id',
        if (description == null) 'description',
        if (packUnit == null) 'pack_unit',
        if (packSize == null) 'pack_size',
        if (yieldPct == null) 'yield_pct',
        if (density == null) 'density_g_per_ml',
      };

      /// PATCHes [target] with the form. The server converts the cost when
      /// the unit changes and refuses both in one request: the unit first,
      /// then the cost alone, only when it differs.
      Future<OrgIngredient> update(OrgIngredient target) async {
        final unitChanged = _unit != target.unit;
        var out = await api.updateCatalogItem(
          orgId: widget.orgId,
          id: target.id,
          body: UpdateCatalogItemRequest(
            name: _name.trim(),
            categoryId: category,
            unit: _unit,
            costPerUnit: unitChanged ? null : cost,
            description: description,
            supplierId: _supplierId,
            packUnit: packUnit,
            packSize: packSize,
            yieldPct: yieldPct,
            densityGPerMl: density,
            explicitNulls: {
              ...nulls,
              if (!unitChanged && cost == null) 'cost_per_unit',
            },
          ),
        );
        if (unitChanged && cost != target.costPerUnit) {
          out = await api.updateCatalogItem(
            orgId: widget.orgId,
            id: target.id,
            body: UpdateCatalogItemRequest(
              costPerUnit: cost,
              explicitNulls: {if (cost == null) 'cost_per_unit'},
            ),
          );
        }
        return out;
      }

      if (_editing) {
        await update(_item!);
      } else {
        // A retry after a failed reorder level updates the ingredient this
        // dialog already created, with whatever was edited since.
        final done = _created;
        _created = done != null
            ? await update(done)
            : await api.createCatalogItem(
                orgId: widget.orgId,
                body: CreateCatalogItemRequest(
                  name: _name.trim(),
                  categoryId: category,
                  unit: _unit,
                  costPerUnit: cost,
                  description: description,
                  supplierId: _supplierId,
                  packUnit: packUnit,
                  packSize: packSize,
                  yieldPct: yieldPct,
                  densityGPerMl: density,
                  explicitNulls: {...nulls, if (cost == null) 'cost_per_unit'},
                ),
              );
        final created = _created!;
        for (final b in widget.branches) {
          final row = _pars[b.id];
          if (row == null) continue;
          final lo = parseNumberInput(row.min);
          final hi = parseNumberInput(row.max);
          if (lo == null && hi == null) continue;
          await api.setParLevels(
            branchId: b.id,
            orgIngredientId: created.id,
            body: SetParRequest(
              parMin: lo,
              parMax: hi,
              explicitNulls: {
                if (lo == null) 'par_min',
                if (hi == null) 'par_max',
              },
            ),
          );
        }
      }
      bus.invalidate(inventoryPathFamilies);
      if (!mounted) return;
      DashToast.success(context, t('common.savedChanges'));
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      // Something this Save created is real now: show it in the lists.
      if (_created != null || _createdCategory != null) {
        bus.invalidate(inventoryPathFamilies);
      }
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final orgId = widget.orgId;
    if (_item != null) {
      final fresh = ref
          .watch(inventoryCatalogProvider(orgId))
          .value
          ?.where((i) => i.id == _item!.id)
          .firstOrNull;
      if (fresh != null && !_edited && !identical(fresh, _item)) {
        _item = fresh;
        _seed(fresh);
      }
    }
    final cats = ref.watch(ingredientCategoriesProvider(orgId)).value ?? [];
    final suppliers = ref.watch(inventorySuppliersProvider(orgId)).value ?? [];
    final category = _effectiveCategory(cats);
    final unitOptions = _editing
        ? rules.unitsOf(base: _item!.unit)
        : inventoryUnits;

    Widget pair(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.md,
      children: [
        Expanded(child: a),
        Expanded(child: b),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        DashTextField(
          key: const ValueKey('ingredient-name'),
          label: t('inventory.catalog.name'),
          value: _name,
          autofocus: true,
          onChanged: (v) => _edit(() => _name = v),
        ),
        pair(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs + DashMetrics.hair,
            children: [
              DashSelectField<String>(
                key: const ValueKey('ingredient-category'),
                label: t('inventory.catalog.category'),
                placeholder: t('inventory.catalog.category'),
                value: category,
                options: [
                  for (final x in cats) DashOption(value: x.id, label: x.name),
                  DashOption(
                    value: newCategoryValue,
                    label: t('inventory.catalog.newCategory'),
                    icon: 'plus',
                  ),
                ],
                onChanged: (v) => _edit(() => _categoryId = v),
              ),
              if (_isNewCategory)
                DashTextInput(
                  key: const ValueKey('ingredient-new-category'),
                  value: _newCategory,
                  placeholder: t('inventory.catalog.newCategoryName'),
                  semanticLabel: t('inventory.catalog.newCategoryName'),
                  autofocus: true,
                  onChanged: (v) => _edit(() => _newCategory = v),
                ),
            ],
          ),
          DashSelectField<String>(
            key: const ValueKey('ingredient-unit'),
            label: t('inventory.catalog.unit'),
            value: _unit,
            enabled: unitOptions.length > 1,
            options: [
              for (final u in unitOptions)
                DashOption(value: u, label: unitOptionLabel(t, u)),
            ],
            onChanged: (v) => _edit(() => _unit = v),
          ),
        ),
        if (_unitChanged)
          Container(
            key: const ValueKey('ingredient-unit-notice'),
            padding: const EdgeInsets.all(Space.sm + DashMetrics.hair),
            decoration: BoxDecoration(
              color: DashTone.warning.wash(c),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Text(
              t('inventory.catalog.unitChangeNotice'),
              style: DashType.small.copyWith(
                color: DashTone.warning.foreground(c),
              ),
            ),
          ),
        pair(
          IngredientNumberField(
            key: const ValueKey('ingredient-cost'),
            label: t('inventory.catalog.standardCost'),
            value: _cost,
            onChanged: (v) => _edit(() => _cost = v),
          ),
          DashSelectField<String>(
            key: const ValueKey('ingredient-supplier'),
            label: t('inventory.catalog.supplier'),
            placeholder: t('inventory.catalog.noSupplier'),
            searchable: true,
            searchPlaceholder: t('common.search'),
            emptyText: t('common.noResults'),
            value: _supplierId,
            options: [
              for (final s in activeSuppliers(suppliers))
                DashOption(value: s.id, label: s.name),
            ],
            onChanged: (v) => _edit(() => _supplierId = v),
          ),
        ),
        _AdvancedToggle(
          open: _advanced,
          label: t('inventory.catalog.advanced'),
          onTap: () => setState(() => _advanced = !_advanced),
        ),
        if (_advanced) ...[
          DashTextAreaField(
            key: const ValueKey('ingredient-description'),
            label: t('inventory.catalog.description'),
            value: _description,
            minLines: 2,
            maxLines: 4,
            onChanged: (v) => _edit(() => _description = v),
          ),
          pair(
            DashTextField(
              key: const ValueKey('ingredient-pack-unit'),
              label: t('inventory.catalog.packUnit'),
              placeholder: t('inventory.catalog.packUnitPlaceholder'),
              value: _packUnit,
              onChanged: (v) => _edit(() => _packUnit = v),
            ),
            IngredientNumberField(
              key: const ValueKey('ingredient-pack-size'),
              label: t('inventory.catalog.packSize'),
              value: _packSize,
              onChanged: (v) => _edit(() => _packSize = v),
            ),
          ),
          pair(
            IngredientNumberField(
              key: const ValueKey('ingredient-yield'),
              label: t('inventory.catalog.yieldPct'),
              placeholder: '100',
              value: _yieldPct,
              onChanged: (v) => _edit(() => _yieldPct = v),
            ),
            IngredientNumberField(
              key: const ValueKey('ingredient-density'),
              label: t('inventory.catalog.density'),
              value: _density,
              onChanged: (v) => _edit(() => _density = v),
            ),
          ),
        ],
        if (!_editing && widget.branches.isNotEmpty)
          _BranchPars(
            branches: widget.branches,
            unit: _unit,
            pars: _pars,
            onChanged: (id, v) => _edit(() => _pars[id] = v),
          ),
      ],
    );

    return DashSurface(
      title: _editing
          ? t('inventory.catalog.editTitle')
          : t('inventory.catalog.newItem'),
      description: t('inventory.catalog.title'),
      body: body,
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DashButton(
          key: const ValueKey('ingredient-save'),
          label: t('common.save'),
          loading: _busy,
          onPressed: _canSave
              ? () => _submit(_isNewCategory ? null : category)
              : null,
        ),
      ],
    );
  }
}

/// The "Advanced" collapsible's trigger: a chevron that turns (not under
/// reduced motion) and the muted label.
class _AdvancedToggle extends StatelessWidget {
  const _AdvancedToggle({
    required this.open,
    required this.label,
    required this.onTap,
  });

  final bool open;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        expanded: open,
        child: DashPressable(
          key: const ValueKey('ingredient-advanced'),
          onTap: onTap,
          pressScale: false,
          semanticLabel: label,
          excludeChildSemantics: true,
          builder: (context, s) {
            final fg = s.hovered ? c.textPrimary : c.textSecondary;
            return SizedBox(
              height: DashMetrics.target,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xs,
                children: [
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: DashMotion.of(context, DashMotion.base),
                    child: DashIcon(
                      'chevron-down',
                      size: IconSize.sm,
                      color: fg,
                    ),
                  ),
                  Text(label, style: DashType.bodyMedium.copyWith(color: fg)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Reorder levels per active branch (create only, INV-ING-026): a row per
/// branch with "Reorder point" and "Order up to", the unit under the rows.
class _BranchPars extends ConsumerWidget {
  const _BranchPars({
    required this.branches,
    required this.unit,
    required this.pars,
    required this.onChanged,
  });

  final List<Branch> branches;
  final String unit;
  final Map<String, ({String min, String max})> pars;
  final void Function(String branchId, ({String min, String max}) v) onChanged;

  /// `w-24`.
  static const double inputWidth = Space.xxl * 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final muted = DashType.small.copyWith(color: c.textSecondary);

    Widget input(Branch b, bool isMin) {
      final row = pars[b.id] ?? (min: '', max: '');
      final label = isMin
          ? t('inventory.catalog.parMin')
          : t('inventory.catalog.parMax');
      return SizedBox(
        width: inputWidth,
        child: IngredientNumberInput(
          key: ValueKey('ingredient-par-${isMin ? 'min' : 'max'}-${b.id}'),
          value: isMin ? row.min : row.max,
          semanticLabel: '${b.name} · $label',
          onChanged: (v) => onChanged(
            b.id,
            isMin ? (min: v, max: row.max) : (min: row.min, max: v),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('ingredient-pars'),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          Text(
            t('inventory.catalog.perBranchPar'),
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
          Text(t('inventory.catalog.perBranchParHint'), style: muted),
          Row(
            spacing: Space.sm,
            children: [
              const Spacer(),
              for (final k in ['parMin', 'parMax'])
                SizedBox(
                  width: inputWidth,
                  child: Text(
                    t('inventory.catalog.$k'),
                    style: muted,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
          for (final b in branches)
            Row(
              spacing: Space.sm,
              children: [
                Expanded(
                  child: MadarClippedText(
                    b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.body.copyWith(color: c.textPrimary),
                  ),
                ),
                input(b, true),
                input(b, false),
              ],
            ),
          Text(fmtUnit(unit), style: muted),
        ],
      ),
    );
  }
}
