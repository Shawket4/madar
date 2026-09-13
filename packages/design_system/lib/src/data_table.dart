/// THE data table — docs/design/SPEC.md §8. Orders, Past shifts, a shift's
/// orders, the Z / X report lines: every record list that has columns.
///
/// ```text
/// ┌────────────────────────────────────────────────────────────────────────┐
/// │ #      TIME          TYPE         PAYMENT          TOTAL   STATUS   ⋯ › │ 44 header, sticky
/// ├────────────────────────────────────────────────────────────────────────┤
/// ▌1042   18:02         Dine-in      Cash         EGP 190.00  ✓ Paid  ⋯ › │ 64 row, hairline
/// │ …                                                                      │
/// │                            Load more                                   │ 56 footer
/// └────────────────────────────────────────────────────────────────────────┘
/// ```
///
/// * Columns are `flex` or fixed `width`, aligned start or end; figures are
///   mono and isolated LTR. When the table is too narrow, columns with the
///   highest `priority` number hide first (0 never hides).
/// * On a phone (or below 600 wide) the header goes and each row collapses to
///   a two-line [MadarListRow.bill]: title / meta on the start side, value /
///   pill on the end — derived from the columns' [MadarPhoneRole]s.
/// * No zebra. Hairlines between rows. An optional 4px status rail, a
///   selected row (a split view's open record), a 44 trailing action, a
///   chevron when rows go somewhere, and rows that expand to nested content.
/// * `state` is REQUIRED: loading draws skeleton rows in the table's own
///   geometry, an empty data list draws `empty`, an error draws the error
///   state with a retry. A table can never silently show nothing.
library;

import 'package:design_system/src/controls.dart';
import 'package:design_system/src/format.dart';
import 'package:design_system/src/glyphs.dart';
import 'package:design_system/src/list_row.dart';
import 'package:design_system/src/money.dart';
import 'package:design_system/src/responsive.dart';
import 'package:design_system/src/skeleton.dart';
import 'package:design_system/src/states.dart';
import 'package:design_system/src/status.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/motion.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:design_system/src/touch.dart';
import 'package:flutter/material.dart';

/// Geometry every table shares — what the tests pin.
abstract final class MadarTableMetrics {
  static const double headerHeight = 44;
  static const double rowHeight = Metrics.rowHeight;
  static const double footerHeight = 56;

  /// Row inset at the start and end edges.
  static const double inset = Space.card;

  /// Gap between two columns.
  static const double columnGap = Space.lg;

  /// The trailing action slot: a 44 tile.
  static const double actionSlot = Metrics.glyphTile;

  /// The chevron slot.
  static const double chevronSlot = 20;

  /// A flex column's floor before it forces a lower-priority column out.
  static const double minFlexWidth = 88;

  /// Below this width a table collapses to rows even on a tablet.
  static const double collapseBelow = Responsive.tablet;

  /// Height of the empty / error area.
  static const double stateHeight = 300;
}

enum MadarColumnAlign { start, end }

/// What a column becomes when the table collapses to rows on a phone.
enum MadarPhoneRole {
  /// Derived: the first text column is the title, a status column the pill,
  /// the last end-aligned figure the value, every other text column meta.
  auto,
  title,
  meta,
  value,
  status,
  hidden,
}

/// One column of a [MadarDataTable]. Give exactly one of [text], [minor],
/// [status] or [cell]; prefer the first three — they format themselves,
/// collapse onto a phone row, and read to a screen reader.
@immutable
class MadarColumn<T> {
  const MadarColumn({
    required this.id,
    required this.label,
    this.text,
    this.cell,
    this.flex = 1,
    this.width,
    this.align = MadarColumnAlign.start,
    this.mono = false,
    this.emphasis = false,
    this.muted = false,
    this.priority = 0,
    this.phone = MadarPhoneRole.auto,
  }) : minor = null,
       currency = '',
       status = null;

  /// A money column: mono, end-aligned, localised.
  const MadarColumn.money({
    required this.id,
    required this.label,
    required int Function(T row) this.minor,
    this.currency = '',
    this.flex = 1,
    this.width,
    this.priority = 0,
    this.phone = MadarPhoneRole.auto,
  }) : text = null,
       cell = null,
       align = MadarColumnAlign.end,
       mono = true,
       emphasis = false,
       muted = false,
       status = null;

  /// A status pill column.
  const MadarColumn.status({
    required this.id,
    required this.label,
    required MadarStatus Function(T row) this.status,
    this.flex = 1,
    this.width,
    this.align = MadarColumnAlign.start,
    this.priority = 0,
    this.phone = MadarPhoneRole.auto,
  }) : text = null,
       cell = null,
       minor = null,
       currency = '',
       mono = false,
       emphasis = false,
       muted = false;

  /// Stable id (analytics, tests, a sort key later).
  final String id;

  /// Localised header label; drawn uppercase and tracked.
  final String label;

  /// The cell as a string.
  final String Function(T row)? text;

  /// A custom cell. Not shown on a phone row unless it is also [text].
  final Widget Function(BuildContext context, T row)? cell;

  /// Money in minor units.
  final int Function(T row)? minor;
  final String currency;

  /// A status pill.
  final MadarStatus Function(T row)? status;

  /// Share of the flexible width. Ignored when [width] is set.
  final int flex;

  /// A fixed width.
  final double? width;

  final MadarColumnAlign align;

  /// Figures: Plex Mono, tabular, LTR-isolated.
  final bool mono;

  /// The row's name (a ref, a teller): the title weight.
  final bool emphasis;

  /// Secondary text colour.
  final bool muted;

  /// 0 never hides; higher numbers hide first when the table is narrow.
  final int priority;

  final MadarPhoneRole phone;

  double get _minWidth => width ?? MadarTableMetrics.minFlexWidth;

  bool get _hasText => text != null || minor != null;
}

/// What the table shows when [MadarTableState.data] is empty.
@immutable
class MadarEmptyContent {
  const MadarEmptyContent({
    required this.title,
    this.message,
    this.icon = 'tray',
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;

  /// A `MadarIcon` catalog name.
  final String icon;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// The one thing a table must be told: what it is showing.
sealed class MadarTableState<T> {
  const MadarTableState();

  /// Waiting for the first page: skeleton rows.
  const factory MadarTableState.loading({int rows}) = MadarTableLoading<T>;

  /// The load failed: the error state with a retry. Never an empty list.
  const factory MadarTableState.error({
    required String message,
    required String retryLabel,
    required VoidCallback onRetry,
  }) = MadarTableError<T>;

  /// Rows. Empty draws the table's `empty`. [hasMore] adds the load-more
  /// footer; [loadingMore] turns it into a spinner.
  const factory MadarTableState.data(
    List<T> rows, {
    bool hasMore,
    bool loadingMore,
    VoidCallback? onLoadMore,
  }) = MadarTableData<T>;
}

final class MadarTableLoading<T> extends MadarTableState<T> {
  const MadarTableLoading({this.rows = 6});
  final int rows;
}

final class MadarTableError<T> extends MadarTableState<T> {
  const MadarTableError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;
}

final class MadarTableData<T> extends MadarTableState<T> {
  const MadarTableData(
    this.rows, {
    this.hasMore = false,
    this.loadingMore = false,
    this.onLoadMore,
  });
  final List<T> rows;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback? onLoadMore;
}

class MadarDataTable<T> extends StatefulWidget {
  const MadarDataTable({
    required this.columns,
    required this.state,
    required this.rowKey,
    required this.empty,
    this.onTap,
    this.selected,
    this.rail,
    this.trailing,
    this.expandedBuilder,
    this.onExpansionChanged,
    this.loadMoreLabel,
    this.framed = true,
    this.scrollable = true,
    this.controller,
    this.collapse,
    this.chevron = true,
    super.key,
  });

  final List<MadarColumn<T>> columns;

  /// REQUIRED — see [MadarTableState].
  final MadarTableState<T> state;

  /// A stable identity per row: keeps expansion and selection on the right
  /// record across a refresh.
  final Object Function(T row) rowKey;

  final MadarEmptyContent empty;

  /// Opens the record. Draws a chevron.
  final ValueChanged<T>? onTap;

  /// The record open beside the table (a split view).
  final bool Function(T row)? selected;

  /// The 4px state rail's tone; null for none.
  final MadarTone? Function(T row)? rail;

  /// A 44 action at the row's end (a print tile). The slot is reserved in
  /// the header and in every row whenever this is set, so columns line up.
  final Widget? Function(BuildContext context, T row)? trailing;

  /// Nested content under an expanded row (a shift's orders). Rows for which
  /// it returns null do not expand. Tapping an expandable row toggles it;
  /// when [onTap] is also set, the chevron toggles and the row opens.
  final Widget? Function(BuildContext context, T row)? expandedBuilder;

  /// Told when a row opens or closes — to load its nested content lazily.
  final void Function(T row, {required bool expanded})? onExpansionChanged;

  /// Localised "Load more". Required when a data state `hasMore`.
  final String? loadMoreLabel;

  /// Draw the card around the table. Off for a table nested in another.
  final bool framed;

  /// Scroll inside the table with a sticky header. Off (or any unbounded
  /// height) lays every row in a column — for a table inside another scroll.
  final bool scrollable;

  final ScrollController? controller;

  /// Force the phone collapse on or off; null decides by layout and width.
  final bool? collapse;

  /// Draw the chevron that [onTap] implies. Off for a split view whose row
  /// tap selects into a pane beside it (a chevron says "goes somewhere") or a
  /// row whose trailing action already is the affordance.
  final bool chevron;

  @override
  State<MadarDataTable<T>> createState() => _MadarDataTableState<T>();
}

class _MadarDataTableState<T> extends State<MadarDataTable<T>> {
  final Set<Object> _expanded = {};

  void _toggle(T row) {
    final key = widget.rowKey(row);
    final open = !_expanded.contains(key);
    setState(() => open ? _expanded.add(key) : _expanded.remove(key));
    widget.onExpansionChanged?.call(row, expanded: open);
  }

  /// The columns that fit [width], lowest priority numbers kept.
  List<MadarColumn<T>> _fit(double width) {
    final kept = [...widget.columns];
    double need() =>
        kept.fold<double>(0, (sum, c) => sum + c._minWidth) +
        MadarTableMetrics.columnGap * (kept.length - 1);
    final avail = width - _fixedChrome();
    while (kept.length > 1 && need() > avail) {
      var drop = -1;
      for (var i = kept.length - 1; i >= 0; i--) {
        if (kept[i].priority > 0 &&
            (drop < 0 || kept[i].priority > kept[drop].priority)) {
          drop = i;
        }
      }
      if (drop < 0) break;
      kept.removeAt(drop);
    }
    return kept;
  }

  bool get _hasChevron =>
      (widget.onTap != null && widget.chevron) ||
      widget.expandedBuilder != null;

  double _fixedChrome() =>
      MadarTableMetrics.inset * 2 +
      (widget.trailing != null ? MadarTableMetrics.actionSlot + Space.md : 0) +
      (_hasChevron ? MadarTableMetrics.chevronSlot + Space.md : 0);

  @override
  Widget build(BuildContext context) {
    final layout = MadarLayout.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final collapse =
            widget.collapse ??
            (layout.isPhone || width < MadarTableMetrics.collapseBelow);
        final columns = collapse ? widget.columns : _fit(width);
        final bounded = widget.scrollable && constraints.maxHeight.isFinite;
        return _frame(
          context,
          _content(context, columns, collapse, bounded, constraints),
        );
      },
    );
  }

  Widget _frame(BuildContext context, Widget child) {
    if (!widget.framed) return child;
    final colors = context.madarColors;
    final radius = BorderRadius.circular(Radii.card);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: radius,
        border: Border.all(color: colors.borderLight),
      ),
      child: Padding(
        // Inside the 1px border, so the rows' hairlines stop at it.
        padding: const EdgeInsets.all(1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.card - 1),
          child: child,
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    List<MadarColumn<T>> columns,
    bool collapse,
    bool bounded,
    BoxConstraints constraints,
  ) {
    final header = collapse
        ? null
        : _HeaderRow<T>(table: this, columns: columns);
    final state = widget.state;

    Widget stateBox(Widget child) =>
        SizedBox(height: MadarTableMetrics.stateHeight, child: child);

    final List<Widget> body;
    Widget? footer;
    switch (state) {
      case MadarTableLoading<T>(:final rows):
        body = [
          SkeletonScope(
            child: Column(
              children: [
                for (var i = 0; i < rows; i++) ...[
                  if (i > 0) const MadarHairline.row(),
                  _SkeletonTableRow<T>(
                    table: this,
                    columns: columns,
                    collapse: collapse,
                    seed: i,
                  ),
                ],
              ],
            ),
          ),
        ];
      case MadarTableError<T>(
        :final message,
        :final retryLabel,
        :final onRetry,
      ):
        body = [
          stateBox(
            ErrorState(
              message: message,
              retryLabel: retryLabel,
              onRetry: onRetry,
            ),
          ),
        ];
      case MadarTableData<T>(
            :final rows,
            :final hasMore,
            :final loadingMore,
            :final onLoadMore,
          )
          when rows.isEmpty:
        final e = widget.empty;
        body = [
          stateBox(
            EmptyState(
              icon: e.icon,
              title: e.title,
              message: e.message,
              actionLabel: e.actionLabel,
              onAction: e.onAction,
            ),
          ),
          // "Load more" stays under an empty page: a search that matched
          // nothing in the rows loaded so far may match on the next page.
          if (hasMore) ...[
            const MadarHairline.row(),
            _LoadMoreFooter(
              label: widget.loadMoreLabel ?? '',
              loading: loadingMore,
              onTap: onLoadMore,
            ),
          ],
        ];
      case MadarTableData<T>(
        :final rows,
        :final hasMore,
        :final loadingMore,
        :final onLoadMore,
      ):
        body = const [];
        if (hasMore) {
          assert(widget.loadMoreLabel != null, 'hasMore needs loadMoreLabel');
          footer = _LoadMoreFooter(
            label: widget.loadMoreLabel ?? '',
            loading: loadingMore,
            onTap: onLoadMore,
          );
        }
        if (bounded) {
          return _scrolling(context, header, rows, columns, collapse, footer);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?header,
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const MadarHairline.row(),
              _row(context, rows[i], columns, collapse),
            ],
            if (footer != null) ...[const MadarHairline.row(), footer],
          ],
        );
    }

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [?header, ...body],
    );
    if (!bounded) return column;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: constraints.maxHeight),
      child: SingleChildScrollView(
        controller: widget.controller,
        child: column,
      ),
    );
  }

  Widget _scrolling(
    BuildContext context,
    Widget? header,
    List<T> rows,
    List<MadarColumn<T>> columns,
    bool collapse,
    Widget? footer,
  ) {
    return CustomScrollView(
      controller: widget.controller,
      shrinkWrap: true,
      slivers: [
        if (header != null)
          SliverPersistentHeader(pinned: true, delegate: _PinnedHeader(header)),
        SliverList.separated(
          itemCount: rows.length,
          itemBuilder: (context, i) =>
              _row(context, rows[i], columns, collapse),
          separatorBuilder: (_, _) => const MadarHairline.row(),
        ),
        if (footer != null)
          SliverToBoxAdapter(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [const MadarHairline.row(), footer],
            ),
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    T row,
    List<MadarColumn<T>> columns,
    bool collapse,
  ) {
    final key = widget.rowKey(row);
    final nested = widget.expandedBuilder?.call(context, row);
    final expandable =
        nested != null ||
        (widget.expandedBuilder != null && _expanded.contains(key));
    final open = _expanded.contains(key);
    final line = collapse
        ? _PhoneRow<T>(
            table: this,
            row: row,
            expandable: expandable,
            open: open,
          )
        : _TableRow<T>(
            table: this,
            row: row,
            columns: columns,
            expandable: expandable,
            open: open,
          );
    return KeyedSubtree(
      key: ValueKey<Object>(key),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line,
          _Expansion(
            open: open && nested != null,
            child: nested == null
                ? const SizedBox.shrink()
                : _NestedPanel(child: nested),
          ),
        ],
      ),
    );
  }
}

// ── Pieces ───────────────────────────────────────────────────────────────

class _PinnedHeader extends SliverPersistentHeaderDelegate {
  _PinnedHeader(this.child);

  final Widget child;

  @override
  double get minExtent => MadarTableMetrics.headerHeight + 1;

  @override
  double get maxExtent => MadarTableMetrics.headerHeight + 1;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      child;

  @override
  bool shouldRebuild(_PinnedHeader oldDelegate) => oldDelegate.child != child;
}

/// Lays one line of cells on the table's grid — the header, a row and a
/// skeleton row all go through this, so they cannot disagree about where a
/// column is (the Past-shifts misalignment).
class _Grid<T> extends StatelessWidget {
  const _Grid({
    required this.table,
    required this.columns,
    required this.cell,
    this.trailing,
    this.chevron,
  });

  final _MadarDataTableState<T> table;
  final List<MadarColumn<T>> columns;
  final Widget Function(MadarColumn<T> column) cell;
  final Widget? trailing;
  final Widget? chevron;

  @override
  Widget build(BuildContext context) {
    final w = table.widget;
    final children = <Widget>[const SizedBox(width: MadarTableMetrics.inset)];
    for (var i = 0; i < columns.length; i++) {
      final c = columns[i];
      if (i > 0) {
        children.add(const SizedBox(width: MadarTableMetrics.columnGap));
      }
      final aligned = Align(
        alignment: c.align == MadarColumnAlign.end
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: cell(c),
      );
      children.add(
        c.width != null
            ? SizedBox(width: c.width, child: aligned)
            : Expanded(flex: c.flex, child: aligned),
      );
    }
    if (w.trailing != null) {
      children
        ..add(const SizedBox(width: Space.md))
        ..add(
          SizedBox(
            width: MadarTableMetrics.actionSlot,
            child: Center(child: trailing),
          ),
        );
    }
    if (table._hasChevron) {
      children
        ..add(const SizedBox(width: Space.md))
        ..add(
          SizedBox(
            width: MadarTableMetrics.chevronSlot,
            child: Center(child: chevron),
          ),
        );
    }
    children.add(const SizedBox(width: MadarTableMetrics.inset));
    return Row(children: children);
  }
}

class _HeaderRow<T> extends StatelessWidget {
  const _HeaderRow({required this.table, required this.columns});

  final _MadarDataTableState<T> table;
  final List<MadarColumn<T>> columns;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: MadarTableMetrics.headerHeight,
            child: _Grid<T>(
              table: table,
              columns: columns,
              cell: (c) => Text(
                c.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.label.copyWith(
                  color: colors.textMuted,
                  letterSpacing: MadarType.tracking,
                ),
              ),
            ),
          ),
          const MadarHairline(),
        ],
      ),
    );
  }
}

final RegExp _arabic = RegExp('[؀-ۿ]');

/// A figure string as a cell shows it: isolated LTR unless it carries words
/// in Arabic (an elapsed "42 د" must lay out RTL).
String _figure(String s) => _arabic.hasMatch(s) ? s : MadarFormat.ltr(s);

class _TableRow<T> extends StatelessWidget {
  const _TableRow({
    required this.table,
    required this.row,
    required this.columns,
    required this.expandable,
    required this.open,
  });

  final _MadarDataTableState<T> table;
  final T row;
  final List<MadarColumn<T>> columns;
  final bool expandable;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final w = table.widget;
    final selected = w.selected?.call(row) ?? false;
    final railTone = w.rail?.call(row);
    final railColor =
        railTone?.color(colors) ?? (selected ? colors.accent : null);

    Widget cellOf(MadarColumn<T> c) {
      if (c.cell != null) return c.cell!(context, row);
      if (c.status != null) return MadarStatusPill(c.status!(row));
      if (c.minor != null) {
        return MoneyText(
          c.minor!(row),
          currency: c.currency,
          style: MadarType.numMd,
          color: colors.textPrimary,
        );
      }
      final s = c.text?.call(row) ?? '';
      final color = c.muted ? colors.textSecondary : colors.textPrimary;
      final style = c.mono
          ? MadarType.numMd.copyWith(color: color)
          : c.emphasis
          ? MadarType.title.copyWith(color: color)
          : MadarType.body.copyWith(color: color);
      return Text(
        c.mono ? _figure(s) : s,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: style,
      );
    }

    final toggleOnly = expandable && w.onTap != null;
    Widget? chevron;
    if (expandable) {
      chevron = AnimatedRotation(
        turns: open ? 0.5 : 0,
        duration: _motion(context),
        child: MadarGlyphIcon(
          MadarGlyph.chevronDown,
          size: IconSize.md,
          color: colors.textMuted,
        ),
      );
      if (toggleOnly) {
        chevron = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => table._toggle(row),
          child: SizedBox(
            width: Metrics.glyphTile,
            height: Metrics.glyphTile,
            child: Center(child: chevron),
          ),
        );
      }
    } else if (w.onTap != null && w.chevron) {
      chevron = MadarGlyphIcon(
        MadarGlyph.chevronForward,
        size: IconSize.md,
        color: colors.textMuted,
      );
    }

    Widget line = SizedBox(
      height: MadarTableMetrics.rowHeight,
      child: _Grid<T>(
        table: table,
        columns: columns,
        cell: cellOf,
        trailing: w.trailing?.call(context, row),
        chevron: chevron == null
            ? null
            : OverflowBox(
                maxWidth: Metrics.glyphTile,
                maxHeight: Metrics.glyphTile,
                child: chevron,
              ),
      ),
    );
    if (selected || open) {
      line = ColoredBox(
        color: selected ? colors.accentBg : colors.surface,
        child: line,
      );
    }
    if (railColor != null) {
      line = Stack(
        children: [
          line,
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: kMadarRailWidth,
            child: ColoredBox(color: railColor),
          ),
        ],
      );
    }
    final tap = w.onTap != null
        ? () => w.onTap!(row)
        : expandable
        ? () => table._toggle(row)
        : null;
    if (tap == null) return line;
    return Semantics(
      button: true,
      selected: selected,
      expanded: expandable ? open : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          MadarHaptics.selection();
          tap();
        },
        child: line,
      ),
    );
  }
}

class _PhoneRow<T> extends StatelessWidget {
  const _PhoneRow({
    required this.table,
    required this.row,
    required this.expandable,
    required this.open,
  });

  final _MadarDataTableState<T> table;
  final T row;
  final bool expandable;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final w = table.widget;
    final cols = w.columns;

    MadarColumn<T>? pick(
      MadarPhoneRole role,
      bool Function(MadarColumn<T>) auto,
    ) {
      for (final c in cols) {
        if (c.phone == role) return c;
      }
      for (final c in cols) {
        if (c.phone == MadarPhoneRole.auto && auto(c)) return c;
      }
      return null;
    }

    final titleCol = pick(MadarPhoneRole.title, (c) => c.text != null);
    final statusCol = pick(MadarPhoneRole.status, (c) => c.status != null);
    MadarColumn<T>? valueCol;
    for (final c in cols) {
      if (c.phone == MadarPhoneRole.value) valueCol = c;
    }
    if (valueCol == null) {
      for (final c in cols.reversed) {
        if (c.phone == MadarPhoneRole.auto &&
            c != titleCol &&
            c.align == MadarColumnAlign.end &&
            c._hasText) {
          valueCol = c;
          break;
        }
      }
    }
    final metaCols = [
      for (final c in cols)
        if (c != titleCol &&
            c != valueCol &&
            c != statusCol &&
            c.text != null &&
            (c.phone == MadarPhoneRole.meta ||
                (c.phone == MadarPhoneRole.auto && c.priority <= 2)))
          c,
    ];
    final meta = [
      for (final c in metaCols)
        if (c.text!(row) case final s when s.isNotEmpty)
          if (c.mono) _figure(s) else s,
    ].join(' · ');

    Widget? value;
    if (valueCol != null) {
      value = valueCol.minor != null
          ? MoneyText(
              valueCol.minor!(row),
              currency: valueCol.currency,
              style: MadarType.money,
              color: colors.textPrimary,
            )
          : Text(
              _figure(valueCol.text!(row)),
              maxLines: 1,
              style: MadarType.numMd.copyWith(color: colors.textPrimary),
            );
    }

    final trailing = w.trailing?.call(context, row);
    final toggle = expandable
        ? AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: _motion(context),
            child: MadarGlyphIcon(
              MadarGlyph.chevronDown,
              size: IconSize.md,
              color: colors.textMuted,
            ),
          )
        : null;

    return MadarListRow.bill(
      title: titleCol?.text?.call(row) ?? '',
      meta: meta.isEmpty ? null : meta,
      value: value,
      status: statusCol?.status?.call(row),
      rail: w.rail?.call(row),
      selected: w.selected?.call(row) ?? false,
      chevron: w.onTap != null && w.chevron,
      trailing: (trailing == null && toggle == null)
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.sm,
              children: [?trailing, ?toggle],
            ),
      onTap: w.onTap != null
          ? () => w.onTap!(row)
          : expandable
          ? () => table._toggle(row)
          : null,
    );
  }
}

class _SkeletonTableRow<T> extends StatelessWidget {
  const _SkeletonTableRow({
    required this.table,
    required this.columns,
    required this.collapse,
    required this.seed,
  });

  final _MadarDataTableState<T> table;
  final List<MadarColumn<T>> columns;
  final bool collapse;
  final int seed;

  @override
  Widget build(BuildContext context) {
    // Varied, deterministic bar lengths: identical bars read as a pattern,
    // not as rows about to arrive.
    final f = 0.45 + ((seed * 37) % 40) / 100;
    if (collapse) {
      return SizedBox(
        height: MadarTableMetrics.rowHeight,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: MadarTableMetrics.inset,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.sm,
                  children: [
                    FractionallySizedBox(
                      widthFactor: f,
                      child: const SkeletonBlock(height: 14),
                    ),
                    FractionallySizedBox(
                      widthFactor: f * 0.7,
                      child: const SkeletonBlock(height: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.lg),
              const SkeletonBlock(width: 72, height: 14),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: MadarTableMetrics.rowHeight,
      child: _Grid<T>(
        table: table,
        columns: columns,
        cell: (c) => FractionallySizedBox(
          widthFactor: c.align == MadarColumnAlign.end ? 0.7 : f,
          child: const SkeletonBlock(),
        ),
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MadarTableMetrics.footerHeight,
      child: Center(
        child: loading
            ? const MadarSpinner()
            : MadarButton(
                label: label,
                variant: MadarButtonVariant.ghost,
                size: MadarButtonSize.compact,
                enabled: onTap != null,
                onTap: onTap ?? () {},
              ),
      ),
    );
  }
}

class _NestedPanel extends StatelessWidget {
  const _NestedPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(top: BorderSide(color: colors.borderLight)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          MadarTableMetrics.inset,
          Space.md,
          MadarTableMetrics.inset,
          Space.lg,
        ),
        child: child,
      ),
    );
  }
}

class _Expansion extends StatelessWidget {
  const _Expansion({required this.open, required this.child});

  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _motion(context),
      curve: MotionSpec.standardCurve,
      alignment: AlignmentDirectional.topStart,
      child: open ? child : const SizedBox(width: double.infinity),
    );
  }
}

Duration _motion(BuildContext context) =>
    (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
    ? Duration.zero
    : MotionSpec.standardDuration;
