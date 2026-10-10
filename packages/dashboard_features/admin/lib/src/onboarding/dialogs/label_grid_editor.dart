/// The small ingredients-by-label grid (the web's
/// `features/menu/recipe/label-grid-editor.tsx`) behind recipe bases
/// (MENU-BAS-013), packaging rules (MENU-PKG-015, one fixed column) and
/// per-size option amounts in the group editor (MENU-GRP-040). A blank cell
/// is no line for that column.
///
/// Owner after scaffolding: the `bases` unit; the `groups` unit uses it.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart' show OrgIngredient;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'grid_model.dart';
import 'menu_text.dart';

/// A size column (the web's `w-20` input + its unit word), the row-actions
/// column, the `w-64` picker and the `w-44` label box.
const double _columnWidth = 136;
const double _actionsWidth = DashMetrics.target + 2 * Space.xs;
const double _pickerWidth = 256;
const double _labelWidth = 176;

class LabelGridEditor extends ConsumerStatefulWidget {
  const LabelGridEditor({
    required this.blocks,
    required this.onChanged,
    required this.catalogById,
    required this.ingredientOptions,
    this.onAddColumn,
    this.removableKeys = const {},
    this.onRemoveColumn,
    this.onSubmit,
    this.enabled = true,
    super.key,
  });

  /// One block per column; its label is the column header.
  final List<GridBlock> blocks;
  final ValueChanged<List<GridBlock>> onChanged;
  final Map<String, OrgIngredient> catalogById;

  /// The picker's options (see `ingredientOptions`); rows already in the grid
  /// are left out here.
  final List<DashOption<String>> ingredientOptions;

  /// Offers "Size label, e.g. Cup" + "Size column" (bases, option amounts).
  /// Null = a single fixed column (packaging rules).
  final ValueChanged<String>? onAddColumn;

  /// Columns that may be removed (never the All sizes one).
  final Set<String> removableKeys;
  final ValueChanged<String>? onRemoveColumn;

  /// Enter in the last row's cell (no cell below): the host dialog's submit
  /// (the browser's implicit form submission, MENU-AREA-013).
  final VoidCallback? onSubmit;

  /// Read-only when false (a person without the capability).
  final bool enabled;

  @override
  ConsumerState<LabelGridEditor> createState() => _LabelGridEditorState();
}

class _LabelGridEditorState extends ConsumerState<LabelGridEditor> {
  final Map<String, FocusNode> _nodes = {};
  String _newLabel = '';

  FocusNode _node(int row, String col) =>
      _nodes.putIfAbsent('$row|$col', FocusNode.new);

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  KeyEventResult _onKey(int row, String col, int rows, KeyEvent e) {
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
    final next = row + dr;
    if (next >= 0 && next < rows) {
      _node(next, col).requestFocus();
      return KeyEventResult.handled;
    }
    if (enter && !shift && widget.onSubmit != null) {
      widget.onSubmit!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _addColumn() {
    final label = _newLabel.trim();
    if (label.isEmpty) return;
    widget.onAddColumn?.call(label);
    setState(() => _newLabel = '');
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final blocks = widget.blocks;
    final rows = buildGridRows(blocks);
    final used = {for (final r in rows) r.ingredientId};
    String nameOf(String id) =>
        widget.catalogById[id]?.name ?? t('modeling.grid.unknownIngredient');

    Widget headerCell(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.sm,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          Flexible(
            child: MadarClippedText(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.tableHeader.copyWith(color: c.textMuted),
            ),
          ),
          ?trailing,
        ],
      ),
    );

    // Size columns and the actions column are fixed; the ingredient column
    // takes the rest of the box (the web's full-width table) and scrolls
    // sideways when the columns do not fit.
    Widget table(double width) => Table(
      columnWidths: {
        0: MaxColumnWidth(
          const IntrinsicColumnWidth(),
          FixedColumnWidth(
            math.max(0, width - blocks.length * _columnWidth - _actionsWidth),
          ),
        ),
        for (var i = 0; i < blocks.length; i++)
          i + 1: const FixedColumnWidth(_columnWidth),
        blocks.length + 1: const FixedColumnWidth(_actionsWidth),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: c.muted,
            border: Border(bottom: BorderSide(color: c.hairline)),
          ),
          children: [
            headerCell(t('recipes.ingredient')),
            for (final b in blocks)
              headerCell(
                b.label,
                trailing:
                    widget.enabled &&
                        widget.onRemoveColumn != null &&
                        widget.removableKeys.contains(b.key)
                    ? DashIconButton(
                        icon: 'x',
                        iconSize: IconSize.xs,
                        semanticLabel: t('modeling.grid.removeColumn'),
                        onPressed: () => widget.onRemoveColumn!(b.key),
                      )
                    : null,
              ),
            const SizedBox.shrink(),
          ],
        ),
        for (final (i, r) in rows.indexed)
          TableRow(
            decoration: i == rows.length - 1
                ? null
                : BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.hairline)),
                  ),
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: Space.md,
                  vertical: Space.xs,
                ),
                child: Text(
                  nameOf(r.ingredientId),
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
              ),
              for (final b in blocks)
                Padding(
                  padding: const EdgeInsetsDirectional.all(Space.xs),
                  child: SizedBox(
                    width: _columnWidth - 2 * Space.xs,
                    child: DashTextInput(
                      value: r.cells[b.key] ?? '',
                      enabled: widget.enabled,
                      placeholder: '—',
                      mono: true,
                      textAlign: TextAlign.end,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      semanticLabel: t(
                        'modeling.grid.cellAria',
                        args: {
                          'ingredient':
                              widget.catalogById[r.ingredientId]?.name ?? '',
                          'size': b.label,
                        },
                      ),
                      focusNode: _node(i, b.key),
                      onKeyEvent: (_, e) => _onKey(i, b.key, rows.length, e),
                      trailing: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: Space.sm,
                        ),
                        child: Text(
                          unitWord(t, r.unit),
                          style: DashType.small.copyWith(color: c.textMuted),
                        ),
                      ),
                      onChanged: (v) => widget.onChanged(
                        setCell(
                          blocks,
                          b.key,
                          r.ingredientId,
                          cleanDecimal(v),
                          r.unit,
                        ),
                      ),
                    ),
                  ),
                ),
              widget.enabled
                  ? DashIconButton(
                      icon: 'trash-2',
                      color: c.danger,
                      semanticLabel: t('recipes.builder.removeIngredient'),
                      onPressed: () =>
                          widget.onChanged(removeRow(blocks, r.ingredientId)),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
      ],
    );

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: table(box.maxWidth),
                  ),
                ),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: Text(
                      t('modeling.grid.noLines'),
                      textAlign: TextAlign.center,
                      style: DashType.body.copyWith(color: c.textMuted),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (widget.enabled)
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: _pickerWidth,
                child: DashSelect<String>(
                  options: [
                    for (final o in widget.ingredientOptions)
                      if (!used.contains(o.value)) o,
                  ],
                  value: null,
                  searchable: true,
                  placeholder: t('modeling.grid.addIngredient'),
                  semanticLabel: t('modeling.grid.addIngredient'),
                  searchPlaceholder: t('common.search'),
                  emptyText: t('common.noResults'),
                  onChanged: (id) => widget.onChanged(
                    addRow(blocks, id, widget.catalogById[id]?.unit ?? 'g'),
                  ),
                ),
              ),
              if (widget.onAddColumn != null) ...[
                SizedBox(
                  width: _labelWidth,
                  child: DashTextInput(
                    value: _newLabel,
                    placeholder: t('modeling.grid.sizeLabelPh'),
                    semanticLabel: t('modeling.grid.sizeLabelPh'),
                    onChanged: (v) => setState(() => _newLabel = v),
                    // Enter adds the column; on a blank box it is the
                    // dialog's implicit submit (MENU-AREA-013).
                    onSubmitted: (_) => _newLabel.trim().isEmpty
                        ? widget.onSubmit?.call()
                        : _addColumn(),
                  ),
                ),
                DashButton(
                  label: t('modeling.grid.addLabel'),
                  icon: 'plus',
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  onPressed:
                      _newLabel.trim().isEmpty ||
                          blocks.any((b) => b.label == _newLabel.trim())
                      ? null
                      : _addColumn,
                ),
              ],
            ],
          ),
      ],
    );
  }
}
