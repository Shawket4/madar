/// The recipe-base editor (MENU-BAS-010..018), a 768 wide dialog on a wide
/// screen and a full-screen form on a phone. Web: `BaseEditorDialog` in
/// `features/menu/recipe/bases-page.tsx`.
///
/// - Every open starts from the base as listed (a new widget each time).
/// - Name (English) is required once trimmed; Name (Arabic) is optional.
/// - The lines grid has an "All sizes" column (lines with no size label) and
///   one column per size label; a blank cell is no line.
/// - Create: one POST with the lines. Edit: a PATCH only when the name, the
///   Arabic name or Active changed, a PUT of the lines only when the cleaned
///   lines changed; the toast counts the sizes both re-expanded. Nothing
///   changed sends nothing and still says "0 sizes updated" (MENU-BAS-018).
/// - A cleared Arabic name is sent as `""` (the backend's "clear"), not as
///   `null`, which the backend reads as "leave it" (see the divergence log).
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart'
    show
        CreateRecipeBaseRequest,
        OrgIngredient,
        PatchRecipeBaseRequest,
        PutRecipeBaseLinesRequest,
        RecipeBaseLineInput,
        RecipeBaseLineOut,
        RecipeBaseOut;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/grid_model.dart';
import '../shared/ingredient_options.dart';
import '../shared/label_grid_editor.dart';
import '../shared/label_model.dart';
import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';
import 'bases_providers.dart';
import 'bases_widgets.dart';

/// The web's `sm:max-w-3xl`.
const double _editorWidth = 768;

/// Opens the editor: a new base when [base] is null.
Future<void> showBaseEditor(
  BuildContext context, {
  required String? orgId,
  required RecipeBaseOut? base,
}) => showDashDialog<void>(
  context,
  width: _editorWidth,
  builder: (_) => BaseEditorDialog(orgId: orgId, base: base),
);

class BaseEditorDialog extends ConsumerStatefulWidget {
  const BaseEditorDialog({required this.orgId, this.base, super.key});

  /// Null when no org is in scope (the catalog is then empty).
  final String? orgId;

  /// Null = a new base.
  final RecipeBaseOut? base;

  @override
  ConsumerState<BaseEditorDialog> createState() => _BaseEditorDialogState();
}

/// The lines as compared for "did they change": the cleaned wire lines
/// without their sort.
String _linesSig(List<WireLabelledLine> lines) => jsonEncode([
  for (final l in lines) [l.sizeLabel, l.ingredientId, l.quantity, l.unit],
]);

class _BaseEditorDialogState extends ConsumerState<BaseEditorDialog> {
  late String _name = widget.base?.name ?? '';
  late String _nameAr = widget.base?.nameAr ?? '';
  late bool _active = widget.base?.isActive ?? true;
  late List<GridBlock> _blocks;
  late String _pristine;
  bool _submitted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final t = ref.read(tProvider);
    _blocks = toLabelBlocks(
      [
        for (final l in widget.base?.lines ?? const <RecipeBaseLineOut>[])
          (
            sizeLabel: l.sizeLabel,
            ingredientId: l.ingredientId,
            quantity: l.quantity,
            unit: l.unit,
          ),
      ],
      const [],
      t('modeling.grid.allSizes'),
    );
    _pristine = _linesSig(fromLabelBlocks(_blocks));
  }

  String? _nameError(Translator t) =>
      _submitted && _name.trim().isEmpty ? t('common.requiredField') : null;

  Future<void> _save() async {
    if (_busy) return;
    final t = ref.read(tProvider);
    setState(() => _submitted = true);
    final name = _name.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final wire = fromLabelBlocks(_blocks);
    final lines = [
      for (final (i, l) in wire.indexed)
        RecipeBaseLineInput(
          sizeLabel: l.sizeLabel,
          ingredientId: l.ingredientId,
          quantity: l.quantity,
          unit: l.unit,
          sort: i,
          explicitNulls: l.sizeLabel == null ? const {'size_label'} : const {},
        ),
    ];
    final nameAr = _nameAr.trim();
    final api = ref.read(apiProvider).menu;
    final invalidate = ref.menuInvalidate;
    try {
      final base = widget.base;
      final String message;
      if (base == null) {
        await api.createBase(
          body: CreateRecipeBaseRequest(
            name: name,
            nameAr: nameAr.isEmpty ? null : nameAr,
            isActive: _active,
            lines: lines,
            explicitNulls: nameAr.isEmpty ? const {'name_ar'} : const {},
          ),
        );
        message = t('modeling.bases.created');
      } else {
        var changed = 0;
        if (name != base.name ||
            (nameAr.isEmpty ? null : nameAr) != base.nameAr ||
            _active != base.isActive) {
          final r = await api.patchBase(
            id: base.id,
            body: PatchRecipeBaseRequest(
              name: name,
              nameAr: nameAr,
              isActive: _active,
            ),
          );
          changed += r.sizesChanged;
        }
        if (_linesSig(wire) != _pristine) {
          final r = await api.putBaseLines(
            id: base.id,
            body: PutRecipeBaseLinesRequest(lines: lines),
          );
          changed += r.sizesChanged;
        }
        message = t('modeling.bases.saved', count: changed);
      }
      invalidate
        ..paths(const [MenuPaths.recipeBases])
        ..catalog();
      if (!mounted) return;
      DashToast.success(context, message);
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
    final c = context.madarColors;
    final base = widget.base;
    final orgId = widget.orgId;
    final usage = base == null
        ? null
        : ref.watch(baseUsageProvider(base.id)).value;
    final catalog = orgId == null
        ? const <OrgIngredient>[]
        : ref.watch(ingredientCatalogProvider(orgId)).value ??
              const <OrgIngredient>[];

    return DashSurface(
      title: base == null ? t('modeling.bases.new') : t('modeling.bases.edit'),
      description: usage != null
          ? t(
              'modeling.bases.affects',
              args: {'items': usage.itemCount, 'sizes': usage.sizeCount},
            )
          : t('modeling.bases.editorDesc'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          ModelingBilingualName(
            label: t('common.name'),
            en: _name,
            ar: _nameAr,
            enError: _nameError(t),
            onEnChanged: (v) => setState(() => _name = v),
            onArChanged: (v) => setState(() => _nameAr = v),
            onSubmitted: _save,
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
            onAddColumn: (label) =>
                setState(() => _blocks = addLabelColumn(_blocks, label)),
            removableKeys: {
              for (final b in _blocks)
                if (b.key != allSizes) b.key,
            },
            onRemoveColumn: (key) =>
                setState(() => _blocks = removeLabelColumn(_blocks, key)),
            onSubmit: _save,
          ),
          if (usage != null && usage.sizes.isNotEmpty)
            ModelingDisclosure(
              summary: t('modeling.bases.usedBy'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DashMetrics.hair,
                children: [
                  for (final s in usage.sizes)
                    Text.rich(
                      TextSpan(
                        text: s.menuItemName,
                        children: [
                          // A one-price item's size is the `one_size`
                          // sentinel: never shown (divergence MENU-BAS-014).
                          if (s.sizeLabel != oneSize) ...[
                            const TextSpan(text: ' · '),
                            TextSpan(
                              text: s.sizeLabel,
                              style: TextStyle(color: c.textSecondary),
                            ),
                          ],
                        ],
                      ),
                      key: ValueKey('usage-${s.sizeId}'),
                      style: DashType.body.copyWith(color: c.textPrimary),
                    ),
                ],
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
        DashButton(label: t('common.save'), loading: _busy, onPressed: _save),
      ],
    );
  }
}
