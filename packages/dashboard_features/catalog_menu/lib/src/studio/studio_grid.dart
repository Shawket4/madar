/// Studio section 2, Sizes, price & recipe (the web's `recipe/recipe-grid.tsx`,
/// `base-picker.tsx`, `recipe-link-bar.tsx`, `studio/fix-cost-popover.tsx`):
/// rows = ingredients, columns = sizes, a Price row on top, a Cost · margin
/// footer. Lines a base, a packaging rule or a linked item put there are
/// greyed and read-only; the save only sends own lines.
///
/// The base picker, Unlink and a cost fix apply at once, outside the
/// batched save.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show OrgIngredient, PutSizeBaseRequest, RecipeBaseOut, RecipeLinkInfo, StudioAggregate, UpdateCatalogItemRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/grid_model.dart';
import '../shared/ingredient_options.dart';
import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';
import 'studio_model.dart';
import 'studio_providers.dart';
import 'studio_widgets.dart';

/// A size column (label box + its ⋯), the ingredient column's floor
/// (`min-w-40`) and the actions column (room for "+ Size").
const double _colWidth = Space.xxl * 5 + Space.sm;
const double _ingredientMin = Space.xxl * 5 + Space.lg;
const double _actionsWidth = Space.xxl * 3 + Space.sm;
const double _actionsReadOnly = Space.sm;

/// The whole section: toolbar (base picker, link state), the follows
/// banner, the grid and its hint.
class StudioSizesSection extends ConsumerWidget {
  const StudioSizesSection({
    required this.itemId,
    required this.orgId,
    required this.studio,
    required this.blocks,
    required this.recipeDirtyKeys,
    required this.catalog,
    required this.sizesSectionDirty,
    required this.onChanged,
    super.key,
  });

  final String itemId;
  final String? orgId;
  final StudioAggregate studio;
  final List<SizeBlock> blocks;
  final Set<String> recipeDirtyKeys;
  final List<OrgIngredient> catalog;
  final bool sizesSectionDirty;
  final ValueChanged<List<SizeBlock>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final org = orgId;
    final sourceId = studio.recipeSourceItemId;
    final copies = studio.linkedCopyIds ?? const <String>[];
    final bases = org == null
        ? const <RecipeBaseOut>[]
        : ref.watch(recipeBasesProvider(org)).value ?? const <RecipeBaseOut>[];
    final link = sourceId != null || copies.isNotEmpty
        ? ref.watch(recipeLinkProvider(itemId)).value
        : null;
    final followsName = sourceId == null
        ? null
        : (link?.recipeSourceItemName ?? '…');
    final swapGroups = <SwapGroupInfo>[
      for (final g in studio.modifierGroups)
        (
          name: g.name,
          ingredientIds: [
            for (final o in g.options) ...[
              for (final r in o.recipe) r.ingredientId,
              ?o.replacesIngredientId,
            ],
          ],
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.md,
          runSpacing: Space.sm,
          children: [
            if (sourceId == null)
              StudioBasePicker(
                itemId: itemId,
                sizes: [
                  for (final b in blocks)
                    if (b.id != null) (id: b.id!, baseId: b.baseId),
                ],
                bases: bases,
                disabled: sizesSectionDirty,
              )
            else
              const SizedBox.shrink(),
            StudioRecipeLinkBar(
              itemId: itemId,
              sourceItemId: sourceId,
              linkedCopyIds: copies,
              link: link,
            ),
          ],
        ),
        if (followsName != null)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm,
            ),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: c.hairline),
            ),
            child: Text(
              t('modeling.grid.followsReadOnly', args: {'name': followsName}),
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
          ),
        StudioRecipeGrid(
          itemId: itemId,
          orgId: org,
          blocks: blocks,
          recipeDirtyKeys: recipeDirtyKeys,
          catalog: catalog,
          swapGroups: swapGroups,
          baseNames: {for (final b in bases) b.id: b.name},
          followsName: followsName,
          onChanged: onChanged,
        ),
        StudioHint(t('modeling.grid.hint')),
      ],
    );
  }
}

// ── the grid ────────────────────────────────────────────────────────────────

class StudioRecipeGrid extends ConsumerStatefulWidget {
  const StudioRecipeGrid({
    required this.itemId,
    required this.orgId,
    required this.blocks,
    required this.recipeDirtyKeys,
    required this.catalog,
    required this.swapGroups,
    required this.baseNames,
    required this.followsName,
    required this.onChanged,
    super.key,
  });

  final String itemId;
  final String? orgId;
  final List<SizeBlock> blocks;
  final Set<String> recipeDirtyKeys;
  final List<OrgIngredient> catalog;
  final List<SwapGroupInfo> swapGroups;
  final Map<String, String> baseNames;

  /// The item this recipe follows: set = the recipe is read-only.
  final String? followsName;
  final ValueChanged<List<SizeBlock>> onChanged;

  @override
  ConsumerState<StudioRecipeGrid> createState() => _StudioRecipeGridState();
}

class _StudioRecipeGridState extends ConsumerState<StudioRecipeGrid> {
  final Map<String, FocusNode> _nodes = {};

  /// The cells that hold an input this frame (`row|column`; row -1 = Price).
  final Set<String> _inputs = {};

  FocusNode _node(int row, String col) =>
      _nodes.putIfAbsent('$row|$col', FocusNode.new);

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// Enter / ↓ moves down a column, Shift+Enter / ↑ up; the Price row is
  /// row −1. A cell with no input there (a greyed row) stops the move.
  KeyEventResult _onKey(int row, String col, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final enter =
        e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter;
    final dr = e.logicalKey == LogicalKeyboardKey.arrowDown || (enter && !shift)
        ? 1
        : e.logicalKey == LogicalKeyboardKey.arrowUp || (enter && shift)
        ? -1
        : 0;
    if (dr == 0) return KeyEventResult.ignored;
    final next = '${row + dr}|$col';
    if (!_inputs.contains(next)) return KeyEventResult.ignored;
    _nodes[next]?.requestFocus();
    return KeyEventResult.handled;
  }

  void _set(List<SizeBlock> next) => widget.onChanged(next);

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final locked = !ref.watch(
      authzProvider.select((a) => a.can(Cap.menuItemsEdit)),
    );
    final readOnly = widget.followsName != null || locked;
    final blocks = widget.blocks;
    final catalogById = ingredientsById(widget.catalog);
    final rows = buildGridRows(blocks);
    final ownIds = {
      for (final r in rows)
        if (r.source == LineSource.own) r.ingredientId,
    };
    String? slugOf(String id) => catalogById[id]?.categorySlug;
    _inputs.clear();

    String? tagOf(GridRow r) => switch (r.source) {
      LineSource.base => t(
        'modeling.grid.tagBase',
        args: {
          'name':
              widget.baseNames[blocks
                  .where((b) => b.key == r.blockKeys.first)
                  .firstOrNull
                  ?.baseId] ??
              '—',
        },
      ),
      LineSource.rule => t('modeling.grid.tagRule'),
      LineSource.linked => t(
        'modeling.grid.tagLinked',
        args: {'name': widget.followsName ?? '—'},
      ),
      LineSource.own => null,
    };

    Widget pad(Widget child, {Color? tint}) => TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Container(
        color: tint,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.xs,
          vertical: Space.xs,
        ),
        alignment: AlignmentDirectional.centerStart,
        child: child,
      ),
    );

    final dirtyTint = c.accent.withValues(alpha: 0.08);
    Widget headerLabel(String text) => Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.sm),
      child: Text(
        text,
        style: DashType.tableHeader.copyWith(color: c.textMuted),
      ),
    );

    Widget sizeHeader(int idx, SizeBlock b) {
      final label = b.label == oneSize
          ? SizedBox(
              height: DashMetrics.control,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  t('menu.priceSection'),
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
              ),
            )
          : DashTextInput(
              value: b.label,
              enabled: !locked,
              placeholder: t('menu.studio.sizes.labelPh'),
              semanticLabel: t('menu.sizeLabel'),
              onChanged: (v) => _set([
                for (final x in blocks) x.key == b.key ? x.copyWith(label: v) : x,
              ]),
            );
      return Row(
        children: [
          Expanded(child: label),
          if (!locked)
            _ColumnMenu(
              block: b,
              index: idx,
              blocks: blocks,
              readOnly: readOnly,
              onChanged: _set,
            ),
        ],
      );
    }

    Widget ingredientCell(GridRow r) {
      final ing = catalogById[r.ingredientId];
      final tag = tagOf(r);
      final swap = r.source == LineSource.rule
          ? null
          : swapGroupFor(ing?.categorySlug, widget.swapGroups, slugOf);
      final uncosted = ing != null && positiveUnitCost(ing) == null;
      final badges = [
        if (tag != null) _Tag(label: tag, icon: 'lock'),
        if (swap != null)
          DashBadge(t('modeling.grid.swappable', args: {'group': swap})),
        if (uncosted && !readOnly)
          FixCostButton(
            ingredient: ing,
            orgId: widget.orgId,
            itemId: widget.itemId,
          ),
      ];
      return Padding(
        padding: const EdgeInsetsDirectional.only(start: Space.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.xs,
          children: [
            Text(
              ing?.name ?? t('modeling.grid.unknownIngredient'),
              style: DashType.bodyMedium.copyWith(
                color: r.source == LineSource.own
                    ? c.textPrimary
                    : c.textSecondary,
              ),
            ),
            if (badges.isNotEmpty)
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: badges,
              ),
          ],
        ),
      );
    }

    Widget quantityCell(int rowIndex, GridRow r, SizeBlock b) {
      final value = r.cells[b.key];
      final unit = unitWord(t, r.unit);
      final editable = r.source == LineSource.own && !readOnly;
      if (!editable) {
        return SizedBox(
          width: double.infinity,
          child: Text(
            value != null ? '${ltr(value)} $unit' : '—',
            textAlign: TextAlign.end,
            style: DashType.mono.copyWith(color: c.textSecondary),
          ),
        );
      }
      _inputs.add('$rowIndex|${b.key}');
      return DashTextInput(
        value: value ?? '',
        placeholder: '—',
        mono: true,
        textAlign: TextAlign.end,
        selectAllOnFocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        semanticLabel: t(
          'modeling.grid.cellAria',
          args: {'ingredient': catalogById[r.ingredientId]?.name ?? '', 'size': b.label},
        ),
        focusNode: _node(rowIndex, b.key),
        onKeyEvent: (_, e) => _onKey(rowIndex, b.key, e),
        trailing: Padding(
          padding: const EdgeInsetsDirectional.only(end: Space.sm),
          child: Text(unit, style: DashType.small.copyWith(color: c.textMuted)),
        ),
        onChanged: (v) => _set(
          setCell(blocks, b.key, r.ingredientId, cleanDecimal(v), r.unit),
        ),
      );
    }

    Widget priceCell(SizeBlock b) {
      _inputs.add('-1|${b.key}');
      return DashTextInput(
        value: b.price,
        enabled: !locked,
        mono: true,
        textAlign: TextAlign.end,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        semanticLabel: t('modeling.grid.priceAria', args: {'size': b.label}),
        focusNode: _node(-1, b.key),
        onKeyEvent: (_, e) => _onKey(-1, b.key, e),
        onChanged: (v) => _set([
          for (final x in blocks)
            x.key == b.key ? x.copyWith(price: cleanDecimal(v)) : x,
        ]),
      );
    }

    Widget costCell(SizeBlock b) {
      final cost = columnCost(
        b,
        catalogById,
        recipeDirty: widget.recipeDirtyKeys.contains(b.key),
      );
      final text = switch (cost) {
        NoLines() => '—',
        CostIncomplete() => t('menu.studio.recipe.incomplete'),
        CostKnown(:final piastres, :final estimated, :final margin) =>
          '${estimated ? '≈ ' : ''}${fmt.fmtMoney(piastres)}'
              '${margin == null ? '' : ' · ${fmt.fmtPercent(margin)}'}',
      };
      return SizedBox(
        width: double.infinity,
        child: Text(
          text,
          textAlign: TextAlign.end,
          style: (cost is CostKnown ? DashType.mono : DashType.small).copyWith(
            color: c.textSecondary,
            fontSize: DashType.small.fontSize,
          ),
        ),
      );
    }

    final actionsWidth = readOnly ? _actionsReadOnly : _actionsWidth;
    Widget table(double width) => Table(
      columnWidths: {
        0: MaxColumnWidth(
          const FixedColumnWidth(_ingredientMin),
          FixedColumnWidth(width - blocks.length * _colWidth - actionsWidth),
        ),
        for (var i = 0; i < blocks.length; i++)
          i + 1: const FixedColumnWidth(_colWidth),
        blocks.length + 1: FixedColumnWidth(actionsWidth),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        // Size headers.
        TableRow(
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.4),
            border: Border(bottom: BorderSide(color: c.hairline)),
          ),
          children: [
            pad(headerLabel(t('recipes.ingredient'))),
            for (final (i, b) in blocks.indexed)
              pad(
                sizeHeader(i, b),
                tint:
                    widget.recipeDirtyKeys.contains(b.key) ||
                        b.id == null ||
                        b.label != (b.seededLabel ?? '')
                    ? dirtyTint
                    : null,
              ),
            pad(
              readOnly
                  ? const SizedBox.shrink()
                  : DashButton(
                      label: t('modeling.grid.addSize'),
                      icon: 'plus',
                      variant: DashButtonVariant.ghost,
                      size: DashButtonSize.compact,
                      onPressed: () => _set(addSizeBlock(blocks)),
                    ),
            ),
          ],
        ),
        // Price row.
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.hairline)),
          ),
          children: [
            pad(
              headerLabel(
                '${t('common.price')} (${fmt.currencyLabel()})',
              ),
            ),
            for (final b in blocks)
              pad(
                priceCell(b),
                tint: b.price != (b.seededPrice ?? '') ? dirtyTint : null,
              ),
            const SizedBox.shrink(),
          ],
        ),
        for (final (i, r) in rows.indexed)
          TableRow(
            decoration: BoxDecoration(
              color: r.source == LineSource.own
                  ? null
                  : c.muted.withValues(alpha: 0.25),
              border: Border(bottom: BorderSide(color: c.hairline)),
            ),
            // Every cell is keyed `studio-row-<row>…` (a row is no widget).
            children: [
              pad(
                KeyedSubtree(
                  key: ValueKey('studio-row-${r.key}'),
                  child: ingredientCell(r),
                ),
              ),
              for (final b in blocks)
                pad(
                  KeyedSubtree(
                    key: ValueKey('studio-row-${r.key}|${b.key}'),
                    child: quantityCell(i, r, b),
                  ),
                ),
              KeyedSubtree(
                key: ValueKey('studio-row-${r.key}|actions'),
                child: r.source == LineSource.own && !readOnly
                    ? DashIconButton(
                        icon: 'trash-2',
                        color: c.danger,
                        semanticLabel: t('recipes.builder.removeIngredient'),
                        onPressed: () =>
                            _set(removeRow(blocks, r.ingredientId)),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        // Cost · margin.
        TableRow(
          decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.2)),
          children: [
            pad(headerLabel(t('modeling.grid.cost'))),
            for (final b in blocks) pad(costCell(b)),
            const SizedBox.shrink(),
          ],
        ),
      ],
    );

    final addable = ingredientOptions(widget.catalog, t, exclude: ownIds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: c.hairline),
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.control),
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: table(box.maxWidth),
              ),
            ),
          ),
        ),
        if (!readOnly)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: DashMetrics.searchWidth,
              child: DashSelect<String>(
                key: const ValueKey('studio-add-ingredient'),
                options: addable,
                value: null,
                searchable: true,
                placeholder: t('modeling.grid.addIngredient'),
                semanticLabel: t('modeling.grid.addIngredient'),
                searchPlaceholder: t('common.search'),
                emptyText: t('common.noResults'),
                onChanged: (id) {
                  _set(addRow(blocks, id, catalogById[id]?.unit ?? 'g'));
                  final first = blocks.firstOrNull?.key;
                  if (first == null) return;
                  // Focus the new row's cell in the first size.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    var last = -2;
                    for (final k in _inputs) {
                      final parts = k.split('|');
                      final row = int.parse(parts.first);
                      if (parts.last == first && row > last) last = row;
                    }
                    if (last >= 0) _nodes['$last|$first']?.requestFocus();
                  });
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// A greyed row's source tag ("Base: Espresso shot", "Packaging rule").
class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.icon});

  final String label;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          if (icon != null)
            DashIcon(icon!, size: IconSize.xs - 2, color: c.textMuted),
          Flexible(
            child: MadarClippedText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A size column's ⋯ menu: move, copy from another size, scale, remove.
class _ColumnMenu extends ConsumerStatefulWidget {
  const _ColumnMenu({
    required this.block,
    required this.index,
    required this.blocks,
    required this.readOnly,
    required this.onChanged,
  });

  final SizeBlock block;
  final int index;
  final List<SizeBlock> blocks;
  final bool readOnly;
  final ValueChanged<List<SizeBlock>> onChanged;

  @override
  ConsumerState<_ColumnMenu> createState() => _ColumnMenuState();
}

class _ColumnMenuState extends ConsumerState<_ColumnMenu> {
  final _copyMenu = DashPopoverController();

  @override
  void dispose() {
    _copyMenu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final b = widget.block;
    final blocks = widget.blocks;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final others = [
      for (final o in blocks)
        if (o.key != b.key) o,
    ];
    final items = [
      DashMenuItem(
        label: t('modeling.grid.moveLeft'),
        icon: rtl ? 'arrow-right' : 'arrow-left',
        enabled: widget.index > 0,
        onSelected: () => widget.onChanged(moveSizeBlock(blocks, b.key, -1)),
      ),
      DashMenuItem(
        label: t('modeling.grid.moveRight'),
        icon: rtl ? 'arrow-left' : 'arrow-right',
        enabled: widget.index < blocks.length - 1,
        onSelected: () => widget.onChanged(moveSizeBlock(blocks, b.key, 1)),
      ),
      if (!widget.readOnly) ...[
        const DashMenuItem.divider(),
        DashMenuItem(
          label: t('modeling.grid.copyFrom'),
          icon: 'copy',
          hint: '›',
          enabled: blocks.length >= 2,
          onSelected: () => WidgetsBinding.instance.addPostFrameCallback(
            (_) => _copyMenu.open(),
          ),
        ),
        DashMenuItem(
          label: t('modeling.grid.scale'),
          icon: 'scaling',
          onSelected: () => WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showScaleDialog(context, target: b, blocks: blocks).then((r) {
              if (r == null) return;
              final (fromKey, factor) = r;
              widget.onChanged(
                fromKey == b.key
                    ? scaleColumn(widget.blocks, b.key, factor)
                    : copyColumn(widget.blocks, fromKey, b.key, factor),
              );
            });
          }),
        ),
      ],
      const DashMenuItem.divider(),
      DashMenuItem(
        label: t('menu.removeSize'),
        icon: 'trash-2',
        destructive: true,
        onSelected: () => widget.onChanged([
          for (final x in blocks)
            if (x.key != b.key) x,
        ]),
      ),
    ];
    // "Copy from ▸" opens a second menu on the same trigger (the kit has no
    // submenus).
    return DashMenu(
      controller: _copyMenu,
      items: [
        for (final o in others)
          DashMenuItem(
            label: o.label.isEmpty ? t('modeling.grid.untitledSize') : o.label,
            onSelected: () =>
                widget.onChanged(copyColumn(widget.blocks, o.key, b.key)),
          ),
      ],
      builder: (context, _) => DashMenu(
        items: items,
        builder: (context, c) => DashIconButton(
          icon: 'more-horizontal',
          semanticLabel: t('modeling.grid.columnActions'),
          onPressed: c.toggle,
        ),
      ),
    );
  }
}

/// The scale dialog: start from a size (this one by default), multiply by a
/// number above 0. Resolves with (start column key, factor), or null.
Future<(String, double)?> showScaleDialog(
  BuildContext context, {
  required SizeBlock target,
  required List<SizeBlock> blocks,
}) => showDashDialog<(String, double)>(
  context,
  builder: (_) => _ScaleDialog(target: target, blocks: blocks),
);

class _ScaleDialog extends ConsumerStatefulWidget {
  const _ScaleDialog({required this.target, required this.blocks});

  final SizeBlock target;
  final List<SizeBlock> blocks;

  @override
  ConsumerState<_ScaleDialog> createState() => _ScaleDialogState();
}

class _ScaleDialogState extends ConsumerState<_ScaleDialog> {
  late String _from = widget.target.key;
  String _factor = '1';
  String? _error;

  void _apply() {
    final f = jsNumber(_factor);
    if (!f.isFinite || f <= 0) {
      setState(() => _error = ref.read(tProvider)('modeling.grid.factorInvalid'));
      return;
    }
    Navigator.of(context).pop((_from, f));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return DashSurface(
      title: t('modeling.grid.scaleTitle', args: {'size': widget.target.label}),
      description: t('modeling.grid.scaleDesc'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          DashSelectField<String>(
            label: t('modeling.grid.scaleFrom'),
            options: [
              for (final b in widget.blocks)
                DashOption(
                  value: b.key,
                  label: b.label.isEmpty
                      ? t('modeling.grid.untitledSize')
                      : b.label,
                ),
            ],
            value: _from,
            onChanged: (v) => setState(() => _from = v),
          ),
          DashFormField<String>(
            label: t('modeling.grid.factor'),
            errorText: _error,
            builder: (context, invalid) => DashTextInput(
              value: _factor,
              invalid: invalid,
              semanticLabel: t('modeling.grid.factor'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (v) => setState(() {
                _factor = v;
                _error = null;
              }),
              // Enter submits, as the web's form does (MENU-AREA-013).
              onSubmitted: (_) => _apply(),
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
        DashButton(label: t('modeling.grid.apply'), onPressed: _apply),
      ],
    );
  }
}

/// The amber "Set cost" chip on an ingredient with no unit cost, and its
/// popover: the cost per unit in EGP, Enter or Save submits.
class FixCostButton extends ConsumerStatefulWidget {
  const FixCostButton({
    required this.ingredient,
    required this.orgId,
    required this.itemId,
    super.key,
  });

  final OrgIngredient ingredient;
  final String? orgId;
  final String itemId;

  @override
  ConsumerState<FixCostButton> createState() => _FixCostButtonState();
}

class _FixCostButtonState extends ConsumerState<FixCostButton> {
  final _popover = DashPopoverController();
  String _value = '';
  bool _saving = false;

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final org = widget.orgId;
    if (org == null) return;
    final t = ref.read(tProvider);
    final n = jsParseFloat(_value);
    if (!n.isFinite || n < 0) {
      DashToast.error(context, t('menu.studio.recipe.invalidCost'));
      return;
    }
    final invalidate = ref.menuInvalidate;
    setState(() => _saving = true);
    try {
      await ref
          .read(apiProvider)
          .inventory
          .updateCatalogItem(
            orgId: org,
            id: widget.ingredient.id,
            body: UpdateCatalogItemRequest(
              costPerUnit: egpToPiastres(n).toDouble(),
            ),
          );
      invalidate.ingredientCosts(org, widget.itemId);
      if (!mounted) return;
      DashToast.success(context, t('menu.studio.recipe.costSet'));
      _popover.close();
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final warn = DashTone.warning.foreground(c);
    final unit = unitWord(t, widget.ingredient.unit);
    return DashPopover(
      controller: _popover,
      align: DashPopoverAlign.end,
      width: Space.xxl * 8,
      anchor: (context, p) => DashPressable(
        onTap: p.toggle,
        semanticLabel: t('menu.studio.recipe.setCost'),
        excludeChildSemantics: true,
        pressScale: false,
        builder: (context, s) => Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm,
            vertical: DashMetrics.hair,
          ),
          decoration: BoxDecoration(
            color: s.hovered ? DashTone.warning.wash(c) : null,
            borderRadius: BorderRadius.circular(Radii.xs),
            border: Border.all(color: warn.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              DashIcon('coins', size: IconSize.xs - 2, color: warn),
              Text(
                t('menu.studio.recipe.setCost'),
                style: DashType.smallMedium.copyWith(color: warn),
              ),
            ],
          ),
        ),
      ),
      content: (context, p) => Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.sm,
          children: [
            Text(
              widget.ingredient.name,
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
            StudioHint(
              t('menu.studio.recipe.costPerUnit', args: {'unit': unit}),
            ),
            Row(
              spacing: Space.sm,
              children: [
                Expanded(
                  child: DashTextInput(
                    value: _value,
                    autofocus: true,
                    mono: true,
                    placeholder: '0.00',
                    semanticLabel: t(
                      'menu.studio.recipe.costPerUnit',
                      args: {'unit': unit},
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (v) => setState(() => _value = v),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                DashButton(
                  label: t('common.save'),
                  size: DashButtonSize.compact,
                  loading: _saving,
                  onPressed: _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── toolbar ─────────────────────────────────────────────────────────────────

const String _none = '__none';
const String _mixed = '__mixed';

/// "Base: [None ▾]": one recipe base on every saved size of the item.
class StudioBasePicker extends ConsumerStatefulWidget {
  const StudioBasePicker({
    required this.itemId,
    required this.sizes,
    required this.bases,
    required this.disabled,
    super.key,
  });

  final String itemId;

  /// Saved sizes only: a new one cannot take a base yet.
  final List<({String id, String? baseId})> sizes;
  final List<RecipeBaseOut> bases;

  /// The sizes section has unsaved edits (a base re-expands server-side).
  final bool disabled;

  @override
  ConsumerState<StudioBasePicker> createState() => _StudioBasePickerState();
}

class _StudioBasePickerState extends ConsumerState<StudioBasePicker> {
  bool _busy = false;

  Future<void> _apply(String next, String current) async {
    if (next == _mixed || next == current) return;
    final t = ref.read(tProvider);
    final baseId = next == _none ? null : next;
    final invalidate = ref.menuInvalidate;
    final api = ref.read(apiProvider);
    setState(() => _busy = true);
    try {
      for (final s in widget.sizes) {
        await api.menu.putSizeBase(
              sizeId: s.id,
              body: PutSizeBaseRequest(
                baseId: baseId,
                explicitNulls: const {'base_id'},
              ),
            );
      }
      if (mounted) {
        DashToast.success(
          context,
          baseId != null
              ? t('modeling.base.applied', count: widget.sizes.length)
              : t('modeling.base.cleared'),
        );
      }
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      invalidate.studio(widget.itemId);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final canEdit = ref.watch(
      authzProvider.select((a) => a.can(Cap.menuItemsEdit)),
    );
    final value = switch (baseValueOf(widget.sizes)) {
      BaseNone() => _none,
      BaseMixed() => _mixed,
      BaseOne(:final id) => id,
    };
    final used = {for (final s in widget.sizes) s.baseId};
    final options = [
      DashOption(value: _none, label: t('modeling.base.none')),
      if (value == _mixed)
        DashOption(
          value: _mixed,
          label: t('modeling.base.mixed'),
          enabled: false,
        ),
      for (final b in widget.bases)
        if (b.isActive || used.contains(b.id))
          DashOption(value: b.id, label: b.name),
    ];
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          t('modeling.base.label'),
          style: DashType.body.copyWith(
            color: context.madarColors.textSecondary,
          ),
        ),
        SizedBox(
          width: Space.xxl * 6,
          child: DashSelect<String>(
            key: const ValueKey('studio-base-picker'),
            options: options,
            value: value,
            semanticLabel: t('modeling.base.label'),
            enabled:
                canEdit &&
                !widget.disabled &&
                !_busy &&
                widget.sizes.isNotEmpty,
            onChanged: (v) => _apply(v, value),
          ),
        ),
        DashButton(
          label: t('modeling.base.manage'),
          variant: DashButtonVariant.link,
          size: DashButtonSize.compact,
          onIntent: () => ref.prefetchRoute('/menu/bases'),
          onPressed: () => context.go('/menu/bases'),
        ),
        if (widget.disabled) StudioHint(t('modeling.base.saveFirst')),
      ],
    );
  }
}

/// "Recipe follows (item) [Unlink]" on a linked copy, or "Linked copies: …"
/// on a source.
class StudioRecipeLinkBar extends ConsumerWidget {
  const StudioRecipeLinkBar({
    required this.itemId,
    required this.sourceItemId,
    required this.linkedCopyIds,
    required this.link,
    super.key,
  });

  final String itemId;
  final String? sourceItemId;
  final List<String> linkedCopyIds;
  final RecipeLinkInfo? link;

  Future<void> _unlink(BuildContext context, WidgetRef ref, String name) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('modeling.linked.unlinkTitle'),
      description: t('modeling.linked.unlinkDesc', args: {'name': name}),
      confirmLabel: t('modeling.linked.unlink'),
    );
    if (!ok || !context.mounted) return;
    final invalidate = ref.menuInvalidate;
    try {
      await ref.read(apiProvider).menu.deleteRecipeLink(id: itemId);
      // invalidateStudio + the link's own key (both under /menu-items).
      invalidate.studio(itemId);
      if (!context.mounted) return;
      DashToast.success(context, t('modeling.linked.unlinked'));
    } on Object catch (e) {
      if (context.mounted) DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final canEdit = ref.watch(
      authzProvider.select((a) => a.can(Cap.menuItemsEdit)),
    );
    final glyph = DashIcon('link-2', size: IconSize.sm, color: c.textSecondary);
    final style = DashType.body.copyWith(color: c.textPrimary);
    Widget itemLink(String id, String label) => DashButton(
      label: label,
      variant: DashButtonVariant.link,
      size: DashButtonSize.compact,
      // Opening the other item reads its aggregate, its link and its row
      // (both ends of a link read the link).
      onIntent: () => ref
        ..warm(menuStudioProvider(id))
        ..warm(recipeLinkProvider(id))
        ..warm(studioMenuItemProvider(id)),
      onPressed: () => context.go('/menu/items/$id'),
    );

    final source = sourceItemId;
    if (source != null) {
      final name = link?.recipeSourceItemName ?? '—';
      return Wrap(
        spacing: Space.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          glyph,
          Text(t('modeling.linked.follows'), style: style),
          itemLink(source, name),
          if (link?.inSync == false)
            StudioOutlineBadge(t('modeling.linked.outOfSync')),
          if (canEdit)
            DashButton(
              label: t('modeling.linked.unlink'),
              icon: 'unlink',
              variant: DashButtonVariant.ghost,
              size: DashButtonSize.compact,
              onPressed: () => _unlink(context, ref, name),
            ),
        ],
      );
    }
    if (linkedCopyIds.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        glyph,
        Text(t('modeling.linked.copies'), style: style),
        for (final (i, id) in linkedCopyIds.indexed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              itemLink(
                id,
                ref.watch(studioMenuItemProvider(id)).value?.name ??
                    t('modeling.linked.copyN', args: {'n': i + 1}),
              ),
              if (i < linkedCopyIds.length - 1) Text(',', style: style),
            ],
          ),
      ],
    );
  }
}
