import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'buttons.dart';
import 'controls.dart';
import 'display.dart';
import 'foundation/l10n.dart';
import 'foundation/popover.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';

/// Horizontal alignment of a column's header and cells.
enum DashAlign { start, center, end }

/// What a column becomes on the phone card.
enum DashPhoneRole {
  /// The first visible column leads the card, the rest go in its grid.
  auto,

  /// This column leads the card.
  title,

  /// Dropped from the card.
  hidden,
}

/// A sort: which column, which way.
@immutable
class DashSort {
  const DashSort(this.columnId, {this.descending = false});
  final String columnId;
  final bool descending;

  /// The next sort after a header tap: none → ascending → descending →
  /// ascending (the web's `toggleSorting(sorted === "asc")`).
  static DashSort next(DashSort? current, String columnId) =>
      current?.columnId == columnId && !current!.descending
      ? DashSort(columnId, descending: true)
      : DashSort(columnId);

  @override
  bool operator ==(Object other) =>
      other is DashSort &&
      other.columnId == columnId &&
      other.descending == descending;

  @override
  int get hashCode => Object.hash(columnId, descending);
}

/// One column of a [DashDataTable] (a tanstack column def + the web's meta).
@immutable
class DashColumn<T> {
  const DashColumn({
    required this.id,
    required this.label,
    this.text,
    this.cell,
    this.sortValue,
    this.sortable,
    this.numeric = false,
    this.align,
    this.width,
    this.flex = 1,
    this.minWidth = 120,
    this.hideable = true,
    this.initiallyHidden = false,
    this.phone = DashPhoneRole.auto,
    this.searchable = true,
  });

  /// Stable id (sort key, visibility, tests).
  final String id;

  /// Header label; also the column menu's and the phone card's label.
  final String label;

  /// The cell as text: the default cell, the search haystack, the sort key
  /// when [sortValue] is not given.
  final String Function(T row)? text;

  /// A custom cell.
  final Widget Function(BuildContext context, T row)? cell;

  /// The value to sort by (numbers, dates, strings).
  final Comparable<Object?>? Function(T row)? sortValue;

  /// Sortable: defaults to true when [sortValue] is given.
  final bool? sortable;

  /// Money, counts, refs, times: Plex Mono, tabular, end-aligned, LTR.
  final bool numeric;
  final DashAlign? align;

  /// A fixed width (padding included).
  final double? width;

  /// Share of the flexible width.
  final int flex;

  /// A flexible column's floor before the table scrolls sideways.
  final double minWidth;

  /// Listed in the Columns menu.
  final bool hideable;
  final bool initiallyHidden;
  final DashPhoneRole phone;
  final bool searchable;

  bool get canSort => sortable ?? (sortValue != null);

  DashAlign get resolvedAlign =>
      align ?? (numeric ? DashAlign.end : DashAlign.start);

  Comparable<Object?>? _sortKey(T row) =>
      sortValue?.call(row) ?? text?.call(row);
}

/// A cursor-style "Load more" footer instead of pages.
@immutable
class DashLoadMore {
  const DashLoadMore({
    required this.hasMore,
    required this.onLoadMore,
    this.loading = false,
  });
  final bool hasMore;
  final bool loading;
  final VoidCallback onLoadMore;
}

/// THE record table (the web's `DataTable`, POS SPEC §8):
///
/// * header — 11/600 tracked muted labels, 44 tall, a hairline under it,
///   sticky while the rows scroll (with [expand]);
/// * rows — 56 tall, hairlines, no zebra; the open row ([selectedRowKey]) is
///   an accent wash with an ink start rail;
/// * figures — `numeric` columns are mono, tabular, end-aligned, LTR;
/// * state is REQUIRED — [loading] draws skeleton rows in the table's own
///   grid, [errorMessage] the error state with Retry (a failed load is never
///   empty), no rows the [empty] state;
/// * sorting (client, or the server's through [onSortChanged]), pages (10 a
///   page, client or server), Load more, a global search, a Columns menu,
///   row selection with a bulk bar, expandable rows, trailing row actions;
/// * narrower than its columns it scrolls sideways; below 760 each row is a
///   card ([rowCardBuilder], or a stacked title + label/value grid).
class DashDataTable<T> extends StatefulWidget {
  const DashDataTable({
    required this.columns,
    required this.rows,
    required this.rowKey,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.empty,
    this.onRowTap,
    this.selectedRowKey,
    this.expandedBuilder,
    this.rowActions,
    this.rowActionsWidth = DashMetrics.target + Space.lg,
    this.toolbar,
    this.searchPlaceholder,
    this.rowCardBuilder,
    this.pageSize = 10,
    this.pageIndex,
    this.pageCount,
    this.onPageChanged,
    this.loadMore,
    this.initialSort,
    this.sort,
    this.onSortChanged,
    this.selectable = false,
    this.selectedKeys,
    this.onSelectionChanged,
    this.bulkActions,
    this.hideViewOptions = false,
    this.framed = true,
    this.expand = false,
    this.phone,
    this.rowSemanticLabel,
    super.key,
  });

  final List<DashColumn<T>> columns;
  final List<T> rows;

  /// A stable identity per row: keeps selection and expansion on the right
  /// record across a refresh.
  final Object Function(T row) rowKey;

  final bool loading;

  /// A failed load, already in words (`ApiException.message`).
  final String? errorMessage;
  final VoidCallback? onRetry;

  /// Shown for an empty list; defaults to "No results found".
  final Widget? empty;
  final ValueChanged<T>? onRowTap;

  /// The record open beside the table (split view, the open side panel).
  final Object? selectedRowKey;

  /// Content under an expanded row; null rows do not expand.
  final Widget? Function(BuildContext context, T row)? expandedBuilder;

  /// Trailing per-row actions (icon buttons, a ⋯ menu). Taps never open the row.
  final Widget Function(BuildContext context, T row)? rowActions;
  final double rowActionsWidth;

  /// Extra toolbar controls (filters) between the search and Columns.
  final Widget? toolbar;

  /// A client-side search over the columns' text, with this placeholder.
  final String? searchPlaceholder;

  /// The phone card for a row (overrides the stacked card).
  final Widget Function(BuildContext context, T row)? rowCardBuilder;

  final int pageSize;

  /// Server paging: the page shown (0-based), how many there are, and the
  /// callback. With [onPageChanged] the table does not slice [rows].
  final int? pageIndex;
  final int? pageCount;
  final ValueChanged<int>? onPageChanged;

  /// "Load more" instead of pages.
  final DashLoadMore? loadMore;

  final DashSort? initialSort;

  /// Server sorting: the sort in force and the callback. With
  /// [onSortChanged] the table does not reorder [rows].
  final DashSort? sort;
  final ValueChanged<DashSort>? onSortChanged;

  /// A checkbox column, a select-all in the header, a bulk bar.
  final bool selectable;

  /// Controlled selection (keys from [rowKey]).
  final Set<Object>? selectedKeys;
  final ValueChanged<Set<Object>>? onSelectionChanged;

  /// The bulk bar's actions for the selected rows.
  final Widget Function(
    BuildContext context,
    List<T> selected,
    VoidCallback clear,
  )?
  bulkActions;

  /// Hide the Columns menu.
  final bool hideViewOptions;

  /// Inside another card: no frame of its own.
  final bool framed;

  /// Fill the height and scroll the rows under a sticky header.
  final bool expand;

  /// Force the phone cards on or off; null decides by window width.
  final bool? phone;

  /// What a screen reader calls a tappable row (defaults to its first text).
  final String Function(T row)? rowSemanticLabel;

  @override
  State<DashDataTable<T>> createState() => _DashDataTableState<T>();
}

class _DashDataTableState<T> extends State<DashDataTable<T>> {
  late DashSort? _sort = widget.initialSort;
  late final Set<String> _hidden = {
    for (final c in widget.columns)
      if (c.initiallyHidden) c.id,
  };
  String _query = '';
  int _page = 0;
  final Set<Object> _expanded = {};
  final Set<Object> _ownSelection = {};

  bool get _manualPaging => widget.onPageChanged != null;
  bool get _usePages => widget.loadMore == null;
  Set<Object> get _selection => widget.selectedKeys ?? _ownSelection;

  List<DashColumn<T>> get _visible => [
    for (final c in widget.columns)
      if (!_hidden.contains(c.id)) c,
  ];

  DashSort? get _activeSort =>
      widget.onSortChanged != null ? widget.sort : _sort;

  List<T> get _processed {
    var rows = widget.rows;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      rows = [
        for (final r in rows)
          if (widget.columns.any(
            (c) =>
                c.searchable &&
                (c.text?.call(r).toLowerCase().contains(q) ?? false),
          ))
            r,
      ];
    }
    final s = _sort;
    if (widget.onSortChanged == null && s != null) {
      final col = widget.columns.firstWhereOrNull((c) => c.id == s.columnId);
      if (col != null) {
        rows = [...rows]
          ..sort(
            (a, b) => _compare(col._sortKey(a), col._sortKey(b), s.descending),
          );
      }
    }
    return rows;
  }

  static int _compare(
    Comparable<Object?>? a,
    Comparable<Object?>? b,
    bool desc,
  ) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final r = a is String && b is String
        ? compareAsciiLowerCaseNatural(a, b)
        : a.compareTo(b);
    return desc ? -r : r;
  }

  int _totalPages(int count) {
    if (!_usePages) return 0;
    if (_manualPaging) return widget.pageCount ?? 1;
    return math.max(1, (count / widget.pageSize).ceil());
  }

  void _setSort(String columnId) {
    final next = DashSort.next(_activeSort, columnId);
    if (widget.onSortChanged != null) {
      widget.onSortChanged!(next);
    } else {
      setState(() {
        _sort = next;
        _page = 0;
      });
    }
  }

  void _setSelection(Set<Object> next) {
    if (widget.selectedKeys == null) {
      setState(() {
        _ownSelection
          ..clear()
          ..addAll(next);
      });
    }
    widget.onSelectionChanged?.call(next);
  }

  void _goPage(int p) {
    if (_manualPaging) {
      widget.onPageChanged!(p);
    } else {
      setState(() => _page = p);
    }
  }

  @override
  void didUpdateWidget(DashDataTable<T> old) {
    super.didUpdateWidget(old);
    // Drop selected keys whose rows are gone.
    if (widget.selectedKeys == null && _ownSelection.isNotEmpty) {
      final keys = {for (final r in widget.rows) widget.rowKey(r)};
      _ownSelection.removeWhere((k) => !keys.contains(k));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.dashStrings;
    final phone = widget.phone ?? DashBreakpoints.isPhone(context);
    final processed = _processed;
    final totalPages = _totalPages(processed.length);
    final pageIndex = _manualPaging
        ? (widget.pageIndex ?? 0)
        : math.min(_page, math.max(0, totalPages - 1));
    final shown = _usePages && !_manualPaging
        ? processed
              .skip(pageIndex * widget.pageSize)
              .take(widget.pageSize)
              .toList()
        : processed;

    final hideable = [
      for (final c in widget.columns)
        if (c.hideable && c.label.isNotEmpty) c,
    ];
    final showColumns =
        hideable.isNotEmpty && !phone && !widget.hideViewOptions;
    final hasToolbar =
        widget.searchPlaceholder != null ||
        widget.toolbar != null ||
        showColumns;

    Widget body;
    if (widget.errorMessage != null && !widget.loading) {
      body = DashErrorState(
        message: widget.errorMessage,
        onRetry: widget.onRetry,
        framed: widget.framed,
      );
    } else if (!widget.loading && shown.isEmpty) {
      body =
          widget.empty ??
          DashEmptyState(
            icon: 'search',
            title: t.noResults,
            framed: widget.framed,
          );
    } else if (phone) {
      body = _phoneList(context, shown);
    } else {
      body = _grid(context, shown);
    }
    if (widget.expand &&
        !phone &&
        widget.errorMessage == null &&
        (widget.loading || shown.isNotEmpty)) {
      body = Expanded(child: body);
    }

    final selectedRows = [
      for (final r in widget.rows)
        if (_selection.contains(widget.rowKey(r))) r,
    ];

    final children = <Widget>[
      if (hasToolbar)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.sm,
          children: [
            Expanded(
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (widget.searchPlaceholder != null)
                    DashSearchInput(
                      value: _query,
                      width: phone ? double.infinity : DashMetrics.searchWidth,
                      placeholder: widget.searchPlaceholder!,
                      onChanged: (v) => setState(() {
                        _query = v;
                        _page = 0;
                      }),
                    ),
                  ?widget.toolbar,
                ],
              ),
            ),
            if (showColumns) _columnsMenu(context, hideable),
          ],
        ),
      if (widget.selectable &&
          widget.bulkActions != null &&
          selectedRows.isNotEmpty)
        _BulkBar(
          count: selectedRows.length,
          onClear: () => _setSelection({}),
          child: widget.bulkActions!(
            context,
            selectedRows,
            () => _setSelection({}),
          ),
        ),
      body,
      if (widget.loadMore case final lm?
          when widget.errorMessage == null && shown.isNotEmpty && lm.hasMore)
        Center(
          child: DashButton(
            label: t.loadMore,
            variant: DashButtonVariant.ghost,
            loading: lm.loading,
            onPressed: lm.onLoadMore,
          ),
        ),
      if (_usePages && totalPages > 1 && widget.errorMessage == null)
        DashPagination(
          pageIndex: pageIndex,
          pageCount: totalPages,
          onChanged: _goPage,
        ),
    ];
    return Semantics(
      container: true,
      liveRegion: widget.loading ? false : null,
      child: Column(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: children,
      ),
    );
  }

  Widget _columnsMenu(BuildContext context, List<DashColumn<T>> hideable) {
    final t = context.dashStrings;
    return DashMenu(
      align: DashPopoverAlign.end,
      width: DashMetrics.menu - Space.xxl,
      items: [
        for (final c in hideable)
          DashMenuItem(
            label: c.label,
            checked: !_hidden.contains(c.id),
            keepOpen: true,
            onSelected: () => setState(() {
              if (!_hidden.remove(c.id)) _hidden.add(c.id);
            }),
          ),
      ],
      builder: (context, ctl) => DashButton(
        label: t.columns,
        icon: 'sliders-horizontal',
        variant: DashButtonVariant.outline,
        size: DashButtonSize.compact,
        onPressed: ctl.toggle,
      ),
    );
  }

  // ── Wide: the grid ───────────────────────────────────────────────────

  static const double _rowPad = Space.sm;
  static const double _cellPad = Space.md;
  static const double _selectWidth = DashMetrics.target;
  static const double _expandWidth = DashMetrics.target + Space.xs;

  /// Column widths for [available]; the sum may exceed it (then it scrolls).
  List<double> _widths(List<DashColumn<T>> cols, double available) {
    var fixed = _rowPad * 2;
    if (widget.selectable) fixed += _selectWidth;
    if (widget.rowActions != null) fixed += widget.rowActionsWidth;
    if (widget.expandedBuilder != null) fixed += _expandWidth;
    for (final c in cols) {
      if (c.width != null) fixed += c.width!;
    }
    final flexCols = [
      for (final c in cols)
        if (c.width == null) c,
    ];
    final widths = <String, double>{
      for (final c in cols)
        if (c.width != null) c.id: c.width!,
    };
    var remaining = available - fixed;
    var pool = [...flexCols];
    // Give each flexible column its share; one that falls under its floor
    // takes the floor and the rest share what is left.
    while (pool.isNotEmpty) {
      final totalFlex = pool.fold<int>(0, (a, c) => a + c.flex);
      final under = pool
          .where((c) => remaining * c.flex / totalFlex < c.minWidth)
          .toList();
      if (under.isEmpty) {
        for (final c in pool) {
          widths[c.id] = remaining * c.flex / totalFlex;
        }
        break;
      }
      for (final c in under) {
        widths[c.id] = c.minWidth;
        remaining -= c.minWidth;
      }
      pool = pool.where((c) => !under.contains(c)).toList();
    }
    return [for (final c in cols) widths[c.id]!];
  }

  Widget _grid(BuildContext context, List<T> shown) {
    final c = context.madarColors;
    final cols = _visible;
    return Container(
      clipBehavior: widget.framed ? Clip.antiAlias : Clip.none,
      decoration: widget.framed
          ? BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: c.hairline),
            )
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final avail = constraints.maxWidth;
          final widths = _widths(cols, avail);
          var extras = _rowPad * 2;
          if (widget.selectable) extras += _selectWidth;
          if (widget.rowActions != null) extras += widget.rowActionsWidth;
          if (widget.expandedBuilder != null) extras += _expandWidth;
          final total = widths.fold<double>(0, (a, w) => a + w) + extras;
          final overflows = total > avail + 0.5;
          final tableWidth = overflows ? total : avail;

          final header = _HeaderRow<T>(
            columns: cols,
            widths: widths,
            sort: _activeSort,
            onSort: _setSort,
            selectable: widget.selectable,
            selectAll: _pageSelectState(shown),
            onSelectAll: (v) {
              final keys = {for (final r in shown) widget.rowKey(r)};
              _setSelection(
                v
                    ? {..._selection, ...keys}
                    : ({..._selection}..removeAll(keys)),
              );
            },
            actionsWidth: widget.rowActions != null
                ? widget.rowActionsWidth
                : null,
            expandable: widget.expandedBuilder != null,
          );
          final rowWidgets = widget.loading
              ? [
                  for (var i = 0; i < math.min(widget.pageSize, 6); i++)
                    _SkeletonRow(
                      widths: widths,
                      extras: extras,
                      last: i == math.min(widget.pageSize, 6) - 1,
                    ),
                ]
              : [
                  for (var i = 0; i < shown.length; i++)
                    _row(
                      context,
                      shown[i],
                      cols,
                      widths,
                      i == shown.length - 1,
                    ),
                ];

          Widget table;
          if (widget.expand && constraints.hasBoundedHeight) {
            table = SizedBox(
              width: tableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: rowWidgets,
                    ),
                  ),
                ],
              ),
            );
          } else {
            table = SizedBox(
              width: tableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [header, ...rowWidgets],
              ),
            );
          }
          if (overflows) {
            table = Scrollbar(
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: table,
              ),
            );
          }
          return table;
        },
      ),
    );
  }

  bool? _pageSelectState(List<T> shown) {
    if (shown.isEmpty) return false;
    final n = shown.where((r) => _selection.contains(widget.rowKey(r))).length;
    if (n == 0) return false;
    if (n == shown.length) return true;
    return null;
  }

  Widget _row(
    BuildContext context,
    T row,
    List<DashColumn<T>> cols,
    List<double> widths,
    bool last,
  ) {
    final c = context.madarColors;
    final key = widget.rowKey(row);
    final selected =
        widget.selectedRowKey != null && widget.selectedRowKey == key;
    final expandedContent = widget.expandedBuilder?.call(context, row);
    final open =
        widget.expandedBuilder != null &&
        _expanded.contains(key) &&
        expandedContent != null;
    final checked = _selection.contains(key);
    final t = context.dashStrings;

    Widget rowFace(DashPressState s) => Container(
      constraints: const BoxConstraints(minHeight: DashMetrics.tableRow),
      padding: const EdgeInsets.symmetric(horizontal: _rowPad),
      // The rail is drawn over the row, so it never takes the cells' width.
      foregroundDecoration: selected
          ? BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: c.accent, width: kMadarRailWidth),
              ),
            )
          : null,
      decoration: BoxDecoration(
        color: selected
            ? c.hover
            : (s.highlighted || s.focused) && widget.onRowTap != null
            ? c.hover.withValues(alpha: 0.5)
            : null,
      ),
      child: Row(
        children: [
          if (widget.selectable)
            SizedBox(
              width: _selectWidth,
              child: DashCheckbox(
                value: checked,
                semanticLabel: t.selectRow,
                onChanged: (v) => _setSelection(
                  v ? {..._selection, key} : ({..._selection}..remove(key)),
                ),
              ),
            ),
          for (var i = 0; i < cols.length; i++)
            SizedBox(
              width: widths[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _cellPad,
                  vertical: Space.sm,
                ),
                child: _Cell<T>(column: cols[i], row: row),
              ),
            ),
          if (widget.rowActions != null)
            SizedBox(
              width: widget.rowActionsWidth,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: widget.rowActions!(context, row),
              ),
            ),
          if (widget.expandedBuilder != null)
            SizedBox(
              width: _expandWidth,
              child: expandedContent == null
                  ? null
                  : Center(
                      child: _ExpandButton(
                        open: open,
                        label: t.details,
                        onTap: () => setState(
                          () =>
                              open ? _expanded.remove(key) : _expanded.add(key),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );

    Widget face = widget.onRowTap == null
        ? rowFace(const DashPressState())
        : DashPressable(
            onTap: () => widget.onRowTap!(row),
            selected: selected,
            pressScale: false,
            semanticLabel:
                widget.rowSemanticLabel?.call(row) ?? _firstText(row),
            builder: (context, s) => rowFace(s),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        face,
        if (open)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.card,
              vertical: Space.lg,
            ),
            decoration: BoxDecoration(
              color: c.bg.withValues(alpha: 0.6),
              border: Border(top: BorderSide(color: c.hairline)),
            ),
            child: expandedContent,
          ),
        if (!last) Divider(height: 1, thickness: 1, color: c.hairline),
      ],
    );
  }

  String? _firstText(T row) {
    for (final col in widget.columns) {
      final v = col.text?.call(row);
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  // ── Phone: cards ─────────────────────────────────────────────────────

  Widget _phoneList(BuildContext context, List<T> shown) {
    if (widget.loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          for (var i = 0; i < 4; i++)
            const DashSkeleton(height: Space.xxl * 3, radius: Radii.card),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [for (final r in shown) _phoneCard(context, r)],
    );
  }

  Widget _phoneCard(BuildContext context, T row) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final key = widget.rowKey(row);
    final selected =
        widget.selectedRowKey != null && widget.selectedRowKey == key;
    if (widget.rowCardBuilder != null) {
      final card = widget.rowCardBuilder!(context, row);
      if (widget.onRowTap == null) return card;
      return DashPressable(
        onTap: () => widget.onRowTap!(row),
        selected: selected,
        semanticLabel: widget.rowSemanticLabel?.call(row) ?? _firstText(row),
        builder: (context, s) => card,
      );
    }
    final cols = [
      for (final col in _visible)
        if (col.phone != DashPhoneRole.hidden) col,
    ];
    final titleCol =
        cols.firstWhereOrNull((col) => col.phone == DashPhoneRole.title) ??
        cols.firstOrNull;
    final rest = [
      for (final col in cols)
        if (col != titleCol) col,
    ];
    final expandedContent = widget.expandedBuilder?.call(context, row);
    final open = expandedContent != null && _expanded.contains(key);

    final card = DashCard(
      selected: selected,
      onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
      semanticLabel: widget.rowSemanticLabel?.call(row) ?? _firstText(row),
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            spacing: Space.sm,
            children: [
              if (widget.selectable)
                SizedBox(
                  width: DashMetrics.checkbox + Space.xs,
                  height: DashMetrics.target,
                  child: OverflowBox(
                    maxWidth: DashMetrics.target,
                    maxHeight: DashMetrics.target,
                    alignment: AlignmentDirectional.centerStart,
                    child: DashCheckbox(
                      value: _selection.contains(key),
                      semanticLabel: t.selectRow,
                      alignStart: true,
                      onChanged: (v) => _setSelection(
                        v
                            ? {..._selection, key}
                            : ({..._selection}..remove(key)),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: titleCol == null
                    ? const SizedBox.shrink()
                    : DefaultTextStyle.merge(
                        style: DashType.sectionTitle.copyWith(
                          color: c.textPrimary,
                        ),
                        child: _Cell<T>(
                          column: titleCol,
                          row: row,
                          title: true,
                        ),
                      ),
              ),
              if (widget.rowActions != null) widget.rowActions!(context, row),
              if (expandedContent != null)
                _ExpandButton(
                  open: open,
                  label: t.details,
                  onTap: () => setState(
                    () => open ? _expanded.remove(key) : _expanded.add(key),
                  ),
                ),
            ],
          ),
          if (rest.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = (constraints.maxWidth - Space.lg) / 2;
                  return Wrap(
                    spacing: Space.lg,
                    runSpacing: Space.sm,
                    children: [
                      for (final col in rest)
                        SizedBox(
                          width: w,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                col.label,
                                style: DashType.small.copyWith(
                                  color: c.textSecondary,
                                ),
                              ),
                              const SizedBox(height: DashMetrics.hair),
                              _Cell<T>(column: col, row: row, phone: true),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          if (open)
            Container(
              margin: const EdgeInsets.only(top: Space.md),
              padding: const EdgeInsets.only(top: Space.md),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: expandedContent,
            ),
        ],
      ),
    );
    return card;
  }
}

class _Cell<T> extends StatelessWidget {
  const _Cell({
    required this.column,
    required this.row,
    this.title = false,
    this.phone = false,
  });
  final DashColumn<T> column;
  final T row;
  final bool title;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final align = phone || title ? DashAlign.start : column.resolvedAlign;
    final alignment = switch (align) {
      DashAlign.start => AlignmentDirectional.centerStart,
      DashAlign.center => AlignmentDirectional.center,
      DashAlign.end => AlignmentDirectional.centerEnd,
    };
    final style = title
        ? DashType.sectionTitle.copyWith(color: c.textPrimary)
        : column.numeric
        ? DashType.mono.copyWith(color: c.textPrimary)
        : DashType.body.copyWith(color: c.textPrimary);
    Widget child;
    if (column.cell != null) {
      child = DefaultTextStyle.merge(
        style: style,
        child: column.cell!(context, row),
      );
    } else {
      final v = column.text?.call(row) ?? '';
      child = MadarClippedText(
        column.numeric ? dashFigure(v) : v,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
        textAlign: switch (align) {
          DashAlign.start => TextAlign.start,
          DashAlign.center => TextAlign.center,
          DashAlign.end => TextAlign.end,
        },
      );
    }
    return Align(
      alignment: alignment,
      widthFactor: phone || title ? 1 : null,
      child: child,
    );
  }
}

class _HeaderRow<T> extends StatelessWidget {
  const _HeaderRow({
    required this.columns,
    required this.widths,
    required this.sort,
    required this.onSort,
    required this.selectable,
    required this.selectAll,
    required this.onSelectAll,
    required this.actionsWidth,
    required this.expandable,
  });

  final List<DashColumn<T>> columns;
  final List<double> widths;
  final DashSort? sort;
  final ValueChanged<String> onSort;
  final bool selectable;
  final bool? selectAll;
  final ValueChanged<bool> onSelectAll;
  final double? actionsWidth;
  final bool expandable;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    return Container(
      height: DashMetrics.tableHeader,
      padding: const EdgeInsets.symmetric(
        horizontal: _DashDataTableState._rowPad,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          if (selectable)
            SizedBox(
              width: _DashDataTableState._selectWidth,
              child: DashCheckbox(
                value: selectAll,
                semanticLabel: t.selectAll,
                onChanged: (v) => onSelectAll(selectAll != true),
              ),
            ),
          for (var i = 0; i < columns.length; i++)
            SizedBox(
              width: widths[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _DashDataTableState._cellPad,
                ),
                child: _HeaderCell<T>(
                  column: columns[i],
                  sorted: sort?.columnId == columns[i].id ? sort : null,
                  onSort: () => onSort(columns[i].id),
                ),
              ),
            ),
          if (actionsWidth != null)
            SizedBox(
              width: actionsWidth,
              child: Semantics(
                label: t.actions,
                child: const SizedBox.shrink(),
              ),
            ),
          if (expandable)
            const SizedBox(width: _DashDataTableState._expandWidth),
        ],
      ),
    );
  }
}

class _HeaderCell<T> extends StatelessWidget {
  const _HeaderCell({
    required this.column,
    required this.sorted,
    required this.onSort,
  });
  final DashColumn<T> column;
  final DashSort? sorted;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final alignment = switch (column.resolvedAlign) {
      DashAlign.start => AlignmentDirectional.centerStart,
      DashAlign.center => AlignmentDirectional.center,
      DashAlign.end => AlignmentDirectional.centerEnd,
    };
    final label = column.label.toUpperCase();
    if (!column.canSort) {
      return Align(
        alignment: alignment,
        child: MadarClippedText(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashType.tableHeader.copyWith(color: c.textSecondary),
        ),
      );
    }
    final icon = sorted == null
        ? 'chevrons-up-down'
        : sorted!.descending
        ? 'arrow-down'
        : 'arrow-up';
    return Align(
      alignment: alignment,
      child: DashPressable(
        onTap: onSort,
        pressScale: false,
        semanticLabel: column.label,
        excludeChildSemantics: true,
        selected: sorted != null,
        builder: (context, s) {
          final fg = sorted != null || s.hovered
              ? c.textPrimary
              : c.textSecondary;
          return Container(
            height: DashMetrics.tableHeader,
            foregroundDecoration: dashFocusRing(
              context,
              s,
              BorderRadius.circular(Radii.xs),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                Flexible(
                  child: MadarClippedText(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.tableHeader.copyWith(color: fg),
                  ),
                ),
                Opacity(
                  opacity: sorted == null ? 0.5 : 1,
                  child: DashIcon(icon, size: IconSize.xs, color: fg),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({
    required this.widths,
    required this.extras,
    required this.last,
  });
  final List<double> widths;
  final double extras;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      height: DashMetrics.tableRow,
      padding: const EdgeInsets.symmetric(
        horizontal: _DashDataTableState._rowPad,
      ),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < widths.length; i++)
              SizedBox(
                width: widths[i],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _DashDataTableState._cellPad,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: DashSkeleton(
                      width: math.min(
                        160,
                        (widths[i] - _DashDataTableState._cellPad * 2) *
                            (i == 0 ? 0.75 : 0.5),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExpandButton extends StatelessWidget {
  const _ExpandButton({
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
    return DashPressable(
      onTap: onTap,
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Container(
        width: DashMetrics.target,
        height: DashMetrics.target,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: s.highlighted ? c.hover : null,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: AnimatedRotation(
          turns: open ? 0.5 : 0,
          duration: DashMotion.of(context, DashMotion.base),
          child: DashIcon(
            'chevron-down',
            size: IconSize.sm,
            color: c.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.count,
    required this.onClear,
    required this.child,
  });
  final int count;
  final VoidCallback onClear;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    return Container(
      padding: const EdgeInsetsDirectional.only(start: Space.md, end: Space.xs),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        spacing: Space.md,
        children: [
          DashBadge(t.selectedCount(count)),
          Expanded(
            child: Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [child],
            ),
          ),
          DashIconButton(
            icon: 'x',
            semanticLabel: t.clearAll,
            onPressed: onClear,
            iconSize: IconSize.xs,
          ),
        ],
      ),
    );
  }
}

/// The pager under a table (the web's footer): "Page 2 of 5" at the start,
/// previous / next at the end. Arrows point the reading way in both
/// languages.
class DashPagination extends StatelessWidget {
  const DashPagination({
    required this.pageIndex,
    required this.pageCount,
    required this.onChanged,
    super.key,
  });

  /// 0-based.
  final int pageIndex;
  final int pageCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    return Row(
      children: [
        Expanded(
          child: Text(
            t.page(pageIndex + 1, pageCount),
            style: DashType.body.copyWith(
              color: c.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        DashIconButton(
          icon: DashIcon.backward(context),
          semanticLabel: t.previous,
          variant: DashButtonVariant.outline,
          onPressed: pageIndex > 0 ? () => onChanged(pageIndex - 1) : null,
        ),
        const SizedBox(width: Space.sm),
        DashIconButton(
          icon: DashIcon.forward(context),
          semanticLabel: t.next,
          variant: DashButtonVariant.outline,
          onPressed: pageIndex < pageCount - 1
              ? () => onChanged(pageIndex + 1)
              : null,
        ),
      ],
    );
  }
}
