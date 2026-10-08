import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'buttons.dart';
import 'controls.dart';
import 'display.dart';
import 'fields.dart';
import 'foundation/l10n.dart';
import 'foundation/popover.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';
import 'misc.dart';
import 'overlays.dart';
import 'select.dart';
import 'table.dart';

/// How an [DashEditableField] edits.
enum DashEditableType { text, number, money, select, boolean }

/// One editable field of a card (the web's `EditableField`).
@immutable
class DashEditableField<T> {
  const DashEditableField({
    required this.key,
    required this.label,
    required this.getValue,
    this.type = DashEditableType.text,
    this.options = const [],
    this.display,
    this.editable = true,
  });

  final String key;
  final String label;

  /// String, num (money in minor units), bool or null.
  final Object? Function(T row) getValue;
  final DashEditableType type;
  final List<DashOption<String>> options;

  /// A custom read-only face.
  final Widget Function(BuildContext context, T row)? display;
  final bool editable;
}

/// A column a paste can fill.
@immutable
class DashPasteColumn {
  const DashPasteColumn({required this.key, required this.header});
  final String key;
  final String header;
}

/// A grid of cards edited in place (the web's `EditableCardGrid`): tap a
/// value to edit it (Enter or leaving commits, Escape cancels), a search, a
/// toolbar, Export / Paste / Add, a selection with bulk actions, client or
/// server paging, and a two-step paste of spreadsheet rows.
class DashEditableCardGrid<T> extends StatefulWidget {
  const DashEditableCardGrid({
    required this.rows,
    required this.rowKey,
    required this.titleField,
    required this.fields,
    required this.onCommit,
    this.image,
    this.footer,
    this.actions,
    this.searchText,
    this.searchPlaceholder,
    this.toolbar,
    this.onAdd,
    this.addLabel,
    this.onExport,
    this.bulkActions,
    this.onPasteRows,
    this.pasteValidate,
    this.pasteColumns,
    this.loading = false,
    this.empty,
    this.pageSize = 24,
    this.page,
    this.pageCount,
    this.onPageChanged,
    this.searchValue,
    this.onSearchChanged,
    super.key,
  });

  final List<T> rows;
  final String Function(T row) rowKey;
  final DashEditableField<T> titleField;
  final List<DashEditableField<T>> fields;

  /// Saves one changed field: `{key: value}`.
  final Future<void> Function(T row, Map<String, Object?> patch) onCommit;
  final Widget Function(BuildContext context, T row)? image;
  final Widget Function(BuildContext context, T row)? footer;

  /// The card's ⋯ menu.
  final List<DashMenuItem> Function(T row)? actions;
  final String Function(T row)? searchText;
  final String? searchPlaceholder;
  final Widget? toolbar;
  final VoidCallback? onAdd;
  final String? addLabel;
  final VoidCallback? onExport;
  final Widget Function(
    BuildContext context,
    List<T> selected,
    VoidCallback clear,
  )?
  bulkActions;
  final Future<void> Function(List<Map<String, String>> rows)? onPasteRows;
  final String? Function(Map<String, String> row)? pasteValidate;
  final List<DashPasteColumn>? pasteColumns;
  final bool loading;
  final Widget? empty;
  final int pageSize;

  /// Server paging (0-based); with [onPageChanged] the grid does not slice.
  final int? page;
  final int? pageCount;
  final ValueChanged<int>? onPageChanged;

  /// Server search; with [onSearchChanged] the grid does not filter.
  final String? searchValue;
  final ValueChanged<String>? onSearchChanged;

  @override
  State<DashEditableCardGrid<T>> createState() =>
      _DashEditableCardGridState<T>();
}

class _DashEditableCardGridState<T> extends State<DashEditableCardGrid<T>> {
  final Set<String> _selected = {};
  String _search = '';
  int _page = 0;

  bool get _serverPaging => widget.onPageChanged != null;
  bool get _serverSearch => widget.onSearchChanged != null;

  @override
  void didUpdateWidget(DashEditableCardGrid<T> old) {
    super.didUpdateWidget(old);
    final ids = {for (final r in widget.rows) widget.rowKey(r)};
    _selected.removeWhere((k) => !ids.contains(k));
  }

  void _clear() => setState(_selected.clear);

  Future<void> _openPaste() async {
    final cols =
        widget.pasteColumns ??
        [
          for (final f in [widget.titleField, ...widget.fields])
            DashPasteColumn(key: f.key, header: f.label),
        ];
    await showDashDialog<void>(
      context,
      width: DashMetrics.dialogWide,
      builder: (context) => _PasteDialog(
        columns: cols,
        onPasteRows: widget.onPasteRows,
        validate: widget.pasteValidate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final phone = DashBreakpoints.isPhone(context);
    final q = (_serverSearch ? widget.searchValue ?? '' : _search)
        .trim()
        .toLowerCase();
    final filtered = _serverSearch || q.isEmpty || widget.searchText == null
        ? widget.rows
        : [
            for (final r in widget.rows)
              if (widget.searchText!(r).toLowerCase().contains(q)) r,
          ];
    final pageCount = _serverPaging
        ? math.max(1, widget.pageCount ?? 1)
        : math.max(1, (filtered.length / widget.pageSize).ceil());
    final page = _serverPaging
        ? math.max(0, widget.page ?? 0)
        : math.min(_page, pageCount - 1);
    final paged = _serverPaging
        ? widget.rows
        : filtered.skip(page * widget.pageSize).take(widget.pageSize).toList();
    final selectedRows = [
      for (final r in widget.rows)
        if (_selected.contains(widget.rowKey(r))) r,
    ];

    final actions = [
      if (widget.onExport != null) DashExportButton(onExport: widget.onExport!),
      if (widget.onPasteRows != null)
        DashButton(
          label: t.pasteRows,
          icon: 'clipboard-paste',
          variant: DashButtonVariant.outline,
          onPressed: _openPaste,
        ),
      if (widget.onAdd != null)
        DashButton(
          label: widget.addLabel ?? t.add,
          icon: 'plus',
          onPressed: widget.onAdd,
        ),
    ];
    final filters = Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.searchText != null || _serverSearch)
          DashSearchInput(
            value: _serverSearch ? widget.searchValue ?? '' : _search,
            width: phone ? null : DashMetrics.searchWidth - Space.xxl,
            placeholder: widget.searchPlaceholder ?? t.searchPlaceholder,
            debounce: _serverSearch ? DashSearchInput.listDelay : null,
            onChanged: (v) {
              if (_serverSearch) {
                widget.onSearchChanged!(v);
              } else {
                setState(() {
                  _search = v;
                  _page = 0;
                });
              }
            },
          ),
        ?widget.toolbar,
      ],
    );
    final toolbar = phone || actions.isEmpty
        ? Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [filters, ...actions],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.sm,
            children: [
              Expanded(child: filters),
              Wrap(spacing: Space.sm, runSpacing: Space.sm, children: actions),
            ],
          );

    Widget grid;
    if (widget.loading) {
      grid = _GridLayout(
        children: [
          for (var i = 0; i < 8; i++)
            const DashSkeleton(height: 112, radius: Radii.card),
        ],
      );
    } else if (filtered.isEmpty) {
      grid = widget.empty ?? DashEmptyState(title: t.noResults);
    } else {
      grid = _GridLayout(
        children: [
          for (final r in paged)
            _EditableCard<T>(
              row: r,
              grid: widget,
              selected: _selected.contains(widget.rowKey(r)),
              onToggle: () => setState(() {
                final k = widget.rowKey(r);
                if (!_selected.remove(k)) _selected.add(k);
              }),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        toolbar,
        if (widget.bulkActions != null && _selected.isNotEmpty)
          Container(
            padding: const EdgeInsetsDirectional.only(
              start: Space.md,
              end: Space.xs,
            ),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(Radii.control),
              border: Border.all(color: c.hairline),
            ),
            child: Row(
              spacing: Space.md,
              children: [
                DashBadge(t.selectedCount(_selected.length)),
                Expanded(
                  child: Wrap(
                    spacing: Space.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      widget.bulkActions!(context, selectedRows, _clear),
                    ],
                  ),
                ),
                DashIconButton(
                  icon: 'x',
                  semanticLabel: t.clearAll,
                  onPressed: _clear,
                  iconSize: IconSize.xs,
                ),
              ],
            ),
          ),
        grid,
        if (!widget.loading && pageCount > 1)
          DashPagination(
            pageIndex: page,
            pageCount: pageCount,
            onChanged: (p) => _serverPaging
                ? widget.onPageChanged!(p)
                : setState(() => _page = p),
          ),
      ],
    );
  }
}

class _GridLayout extends StatelessWidget {
  const _GridLayout({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= DashBreakpoints.xl - Space.xxl * 4
            ? 4
            : w >= DashBreakpoints.lg - Space.xxl * 4
            ? 3
            : w >= DashBreakpoints.sm - Space.xxl
            ? 2
            : 1;
        final cell = (w - Space.md * (cols - 1)) / cols;
        return Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            for (final ch in children) SizedBox(width: cell, child: ch),
          ],
        );
      },
    );
  }
}

class _EditableCard<T> extends StatelessWidget {
  const _EditableCard({
    required this.row,
    required this.grid,
    required this.selected,
    required this.onToggle,
  });
  final T row;
  final DashEditableCardGrid<T> grid;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    Future<void> commit(Map<String, Object?> patch) =>
        grid.onCommit(row, patch);
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(
          color: selected ? c.accent : c.hairline,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.sm,
            children: [
              if (grid.bulkActions != null)
                SizedBox(
                  width: Space.xl,
                  height: Space.xxl,
                  child: OverflowBox(
                    maxWidth: DashMetrics.target,
                    maxHeight: DashMetrics.target,
                    child: DashCheckbox(
                      value: selected,
                      onChanged: (_) => onToggle(),
                      semanticLabel: t.selectRow,
                    ),
                  ),
                ),
              if (grid.image != null) grid.image!(context, row),
              Expanded(
                child: DefaultTextStyle.merge(
                  style: DashType.bodyStrong,
                  child: _InlineCell<T>(
                    row: row,
                    field: grid.titleField,
                    onCommit: commit,
                    title: true,
                  ),
                ),
              ),
              if (grid.actions != null)
                DashMenu(
                  items: grid.actions!(row),
                  builder: (context, ctl) => DashIconButton(
                    icon: 'more-horizontal',
                    semanticLabel: t.moreActions,
                    onPressed: ctl.toggle,
                  ),
                ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = (constraints.maxWidth - Space.md) / 2;
              return Wrap(
                spacing: Space.md,
                runSpacing: Space.xs + DashMetrics.hair,
                children: [
                  for (final f in grid.fields)
                    SizedBox(
                      width: w,
                      child: f.type == DashEditableType.boolean
                          ? Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    f.label,
                                    style: DashType.small.copyWith(
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ),
                                _InlineCell<T>(
                                  row: row,
                                  field: f,
                                  onCommit: commit,
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  f.label,
                                  style: DashType.small.copyWith(
                                    color: c.textSecondary,
                                  ),
                                ),
                                _InlineCell<T>(
                                  row: row,
                                  field: f,
                                  onCommit: commit,
                                ),
                              ],
                            ),
                    ),
                ],
              );
            },
          ),
          if (grid.footer != null)
            Container(
              padding: const EdgeInsets.only(top: Space.sm),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: grid.footer!(context, row),
            ),
        ],
      ),
    );
  }
}

/// Tap to edit; Enter or leaving commits, Escape cancels (the web's
/// `InlineCell`).
class _InlineCell<T> extends StatefulWidget {
  const _InlineCell({
    required this.row,
    required this.field,
    required this.onCommit,
    this.title = false,
  });
  final T row;
  final DashEditableField<T> field;
  final Future<void> Function(Map<String, Object?> patch) onCommit;
  final bool title;

  @override
  State<_InlineCell<T>> createState() => _InlineCellState<T>();
}

class _InlineCellState<T> extends State<_InlineCell<T>> {
  bool _editing = false;
  String _draft = '';
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Object? get _value => widget.field.getValue(widget.row);

  String _initial() {
    final v = _value;
    if (widget.field.type == DashEditableType.money && v is num) {
      return (v / 100).toString().replaceFirst(RegExp(r'\.0$'), '');
    }
    return v == null ? '' : '$v';
  }

  void _start() {
    if (!widget.field.editable) return;
    setState(() {
      _draft = _initial();
      _editing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    setState(() => _editing = false);
    final trimmed = _draft.trim();
    if (trimmed == _initial().trim()) return;
    final key = widget.field.key;
    switch (widget.field.type) {
      case DashEditableType.money:
        final major = dashParseNumber(trimmed);
        if (major == null || major < 0) return;
        widget.onCommit({key: (major * 100).round()});
      case DashEditableType.number:
        final n = dashParseNumber(trimmed);
        if (n == null) return;
        widget.onCommit({key: n});
      default:
        widget.onCommit({key: trimmed});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final f = widget.field;
    final v = _value;
    if (f.type == DashEditableType.boolean) {
      return DashSwitch(
        value: v == true,
        semanticLabel: f.label,
        enabled: f.editable,
        onChanged: (on) => widget.onCommit({f.key: on}),
      );
    }
    if (f.type == DashEditableType.select) {
      return DashSelect<String>(
        options: f.options,
        value: v?.toString(),
        semanticLabel: f.label,
        enabled: f.editable,
        onChanged: (s) {
          if (s != v?.toString()) widget.onCommit({f.key: s});
        },
      );
    }
    if (_editing) {
      return DashTextInput(
        value: _draft,
        focusNode: _focus,
        semanticLabel: f.label,
        keyboardType: f.type == DashEditableType.text
            ? null
            : const TextInputType.numberWithOptions(decimal: true),
        onChanged: (s) => _draft = s,
        onSubmitted: (_) => _commit(),
        onKeyEvent: (node, e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
            setState(() => _editing = false);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
      );
    }
    final fmt = context.dashFormats;
    final Widget face = f.display != null
        ? f.display!(context, widget.row)
        : Text(
            f.type == DashEditableType.money
                ? fmt.money(v is num ? v.round() : null)
                : (v == null || '$v'.isEmpty ? '—' : '$v'),
            maxLines: widget.title ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: (widget.title ? DashType.bodyStrong : DashType.body)
                .copyWith(
                  color: c.textPrimary,
                  fontFeatures: f.type == DashEditableType.text
                      ? null
                      : const [FontFeature.tabularFigures()],
                ),
          );
    return DashPressable(
      onTap: f.editable ? _start : null,
      enabled: f.editable,
      semanticLabel: '${f.label}: ${v ?? '—'}',
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(minHeight: Space.xxl),
        alignment: AlignmentDirectional.centerStart,
        decoration: BoxDecoration(
          color: s.hovered && f.editable ? c.muted : null,
          borderRadius: BorderRadius.circular(Space.xs),
        ),
        child: face,
      ),
    );
  }
}

const String _ignore = '__ignore__';

class _PasteDialog extends StatefulWidget {
  const _PasteDialog({
    required this.columns,
    required this.onPasteRows,
    required this.validate,
  });
  final List<DashPasteColumn> columns;
  final Future<void> Function(List<Map<String, String>> rows)? onPasteRows;
  final String? Function(Map<String, String> row)? validate;

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  String _raw = '';
  bool _mapping = false;
  List<String> _map = [];
  bool _creating = false;

  /// Tab- or comma-separated rows.
  static List<List<String>> parse(String text) {
    final lines = text
        .replaceAll('\r', '')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final delim = lines.any((l) => l.contains('\t')) ? '\t' : ',';
    return [
      for (final l in lines) [for (final cell in l.split(delim)) cell.trim()],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final table = parse(_raw);
    final colCount = table.isEmpty ? 0 : table.first.length;
    final mapped = _mapping
        ? [
            for (final cells in table)
              {
                for (var i = 0; i < _map.length; i++)
                  if (_map[i] != _ignore && i < cells.length) _map[i]: cells[i],
              },
          ]
        : <Map<String, String>>[];
    final errors = [for (final r in mapped) widget.validate?.call(r)];
    final valid = errors.where((e) => e == null).length;

    Future<void> create() async {
      setState(() => _creating = true);
      try {
        await widget.onPasteRows?.call([
          for (var i = 0; i < mapped.length; i++)
            if (errors[i] == null) mapped[i],
        ]);
        if (context.mounted) Navigator.of(context).pop();
      } finally {
        if (mounted) setState(() => _creating = false);
      }
    }

    return DashSurface(
      title: t.pasteTitle,
      description: t.pasteHint,
      actions: [
        DashButton(
          label: t.cancel,
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (!_mapping)
          DashButton(
            label: t.next,
            onPressed: table.isEmpty
                ? null
                : () => setState(() {
                    _map = [
                      for (var i = 0; i < colCount; i++)
                        i < widget.columns.length
                            ? widget.columns[i].key
                            : _ignore,
                    ];
                    _mapping = true;
                  }),
          )
        else
          DashButton(
            label: t.createN(valid),
            loading: _creating,
            onPressed: valid == 0 ? null : create,
          ),
      ],
      body: !_mapping
          ? DashTextInput(
              value: _raw,
              onChanged: (v) => setState(() => _raw = v),
              minLines: 8,
              maxLines: 12,
              mono: true,
              semanticLabel: t.pasteTitle,
              placeholder: 'Latte\t45\nCappuccino\t40',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.md,
              children: [
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (var i = 0; i < colCount; i++)
                      SizedBox(
                        width: 160,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: Space.xs,
                          children: [
                            Text(
                              t.pasteColumn(i + 1),
                              style: DashType.small.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                            DashSelect<String>(
                              options: [
                                DashOption(
                                  value: _ignore,
                                  label: t.pasteIgnore,
                                ),
                                for (final col in widget.columns)
                                  DashOption(value: col.key, label: col.header),
                              ],
                              value: i < _map.length ? _map[i] : _ignore,
                              semanticLabel: t.pasteColumn(i + 1),
                              onChanged: (v) => setState(() => _map[i] = v),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                Container(
                  constraints: const BoxConstraints(maxHeight: 256),
                  decoration: BoxDecoration(
                    border: Border.all(color: c.hairline),
                    borderRadius: BorderRadius.circular(Radii.control),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var r = 0; r < table.length; r++)
                          Container(
                            color: errors[r] != null
                                ? DashTone.danger.wash(c).withValues(alpha: 0.4)
                                : null,
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.sm,
                              vertical: Space.xs,
                            ),
                            child: Row(
                              spacing: Space.sm,
                              children: [
                                SizedBox(
                                  width: Space.xl,
                                  child: Text(
                                    '${r + 1}',
                                    style: DashType.mono.copyWith(
                                      fontSize: 12,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ),
                                for (var ci = 0; ci < table[r].length; ci++)
                                  Expanded(
                                    child: Text(
                                      table[r][ci],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: DashType.small.copyWith(
                                        color:
                                            ci < _map.length &&
                                                _map[ci] == _ignore
                                            ? c.textMuted
                                            : c.textPrimary,
                                        decoration:
                                            ci < _map.length &&
                                                _map[ci] == _ignore
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                if (errors[r] != null)
                                  Expanded(
                                    child: Text(
                                      errors[r]!,
                                      style: DashType.small.copyWith(
                                        color: c.errorText,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Text(
                  t.pasteSummary(valid, table.length),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              ],
            ),
    );
  }
}
