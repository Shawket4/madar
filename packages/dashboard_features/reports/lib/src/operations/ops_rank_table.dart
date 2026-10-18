/// A ranked table for the report kit (`ops_report_kit.dart`): a real table on
/// every width, with motion.
///
/// - The header stays put while the rows scroll under it (the body scrolls on
///   its own past [OpsRankTable.maxVisibleRows]); headers sort, with their
///   state said to a screen reader.
/// - The lead column (rank and name) stays at the start edge; the figures
///   scroll sideways inside the card when they do not fit, so the page never
///   does. Start and end follow the reading direction.
/// - Rows rise and fade in, one after another, when the table first shows
///   them (a tab switch remounts it); a re-sort slides every row to its new
///   place. Each starts fully invisible, never at a partial opacity, and
///   everything is instant under reduced motion.
library;

import 'dart:math' as math;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// One column of an [OpsRankTable].
@immutable
class OpsRankColumn<T> {
  const OpsRankColumn({
    required this.id,
    required this.label,
    required this.width,
    required this.cell,
    this.sortValue,
    this.numeric = false,
  });

  final String id;
  final String label;

  /// The column's width; the lead column's is its least (it takes the rest).
  final double width;
  final Widget Function(BuildContext context, T row) cell;

  /// What the column sorts by; null = not sortable.
  final Comparable<Object> Function(T row)? sortValue;

  /// Figures: end-aligned, sorted largest first on the first press.
  final bool numeric;
}

/// The sort in force: a column and a direction.
typedef OpsRankSort = ({String columnId, bool descending});

class OpsRankTable<T> extends StatefulWidget {
  const OpsRankTable({
    required this.rows,
    required this.rowKey,
    required this.lead,
    required this.columns,
    required this.initialSort,
    required this.sortedAscendingLabel,
    required this.sortedDescendingLabel,
    this.loading = false,
    this.empty,
    this.maxVisibleRows = 10,
    this.phoneLeadWidth = 184,
    super.key,
  });

  /// The rows in rank order (ties keep this order under any sort).
  final List<T> rows;
  final Object Function(T row) rowKey;

  /// The column that stays at the start edge.
  final OpsRankColumn<T> lead;

  /// The figures after it, scrolled sideways when they do not fit.
  final List<OpsRankColumn<T>> columns;
  final OpsRankSort initialSort;

  /// "Sorted ascending" / "descending", read after a sorted header's label.
  final String sortedAscendingLabel;
  final String sortedDescendingLabel;

  /// Skeleton rows instead of [rows].
  final bool loading;

  /// Shown for no rows (and not loading).
  final Widget? empty;

  /// The body scrolls past this many rows; the header stays.
  final int maxVisibleRows;

  /// The lead column's width on a phone.
  final double phoneLeadWidth;

  /// A row's height.
  static const double rowHeight = 56;

  @override
  State<OpsRankTable<T>> createState() => _OpsRankTableState<T>();
}

class _OpsRankTableState<T> extends State<OpsRankTable<T>> {
  late OpsRankSort _sort = widget.initialSort;
  final ScrollController _body = ScrollController();
  final ScrollController _head = ScrollController();

  /// The skeleton's row count.
  static const int _skeletonRows = 6;

  @override
  void initState() {
    super.initState();
    _body.addListener(_follow);
  }

  // The header's figures follow the body's sideways scroll.
  void _follow() {
    if (_head.hasClients && _head.offset != _body.offset) {
      _head.jumpTo(_body.offset.clamp(0, _head.position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    _body
      ..removeListener(_follow)
      ..dispose();
    _head.dispose();
    super.dispose();
  }

  OpsRankColumn<T>? _column(String id) =>
      [widget.lead, ...widget.columns].where((c) => c.id == id).firstOrNull;

  void _press(OpsRankColumn<T> col) => setState(() {
    _sort = _sort.columnId == col.id
        ? (columnId: col.id, descending: !_sort.descending)
        : (columnId: col.id, descending: col.numeric);
  });

  List<T> _sorted() {
    final col = _column(_sort.columnId);
    final by = col?.sortValue;
    if (by == null) return widget.rows;
    final indexed = widget.rows.indexed.toList()
      ..sort((a, b) {
        final c = by(a.$2).compareTo(by(b.$2));
        if (c != 0) return _sort.descending ? -c : c;
        return a.$1.compareTo(b.$1);
      });
    return [for (final (_, r) in indexed) r];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final phone = DashBreakpoints.isPhone(context);
    final edge = phone ? Space.sm : Space.card;
    final restWidth =
        widget.columns.fold<double>(0, (s, col) => s + col.width) + edge;
    final showRows = !widget.loading && widget.rows.isNotEmpty;
    if (!widget.loading && widget.rows.isEmpty) {
      return widget.empty ?? const SizedBox.shrink();
    }
    final rows = showRows ? _sorted() : <T>[];
    final count = showRows ? rows.length : _skeletonRows;
    final bodyHeight =
        math.min(count, widget.maxVisibleRows) * OpsRankTable.rowHeight;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final leadMin = phone
            ? math.min(widget.phoneLeadWidth, width * 0.55)
            : widget.lead.width;
        // Room for everything: the lead column takes what is left.
        final fits = leadMin + restWidth <= width;
        final leadWidth = fits ? width - restWidth : leadMin;
        final hairline = BorderSide(color: c.hairline);

        Widget headerCell(
          OpsRankColumn<T> col, {
          double? width,
          EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
            horizontal: Space.md,
          ),
        }) => SizedBox(
          width: width ?? col.width,
          child: _SortHeader(
            key: ValueKey('ops-rank-sort-${col.id}'),
            padding: padding,
            label: col.label,
            numeric: col.numeric,
            sorted: _sort.columnId == col.id ? _sort : null,
            sortedAscendingLabel: widget.sortedAscendingLabel,
            sortedDescendingLabel: widget.sortedDescendingLabel,
            onPressed: col.sortValue == null ? null : () => _press(col),
          ),
        );

        Widget cellBox(OpsRankColumn<T> col, Widget child) => SizedBox(
          width: col.width,
          height: OpsRankTable.rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Align(
              alignment: col.numeric
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: child,
            ),
          ),
        );

        // The two halves of row [i]: the lead (start) and the figures.
        Widget leadOf(int i) {
          final child = showRows
              ? widget.lead.cell(context, rows[i])
              : const DashSkeleton(height: Space.lg, width: Space.xxl * 4);
          return Padding(
            padding: EdgeInsetsDirectional.only(start: edge, end: Space.md),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: child,
            ),
          );
        }

        Widget restOf(int i) => Row(
          children: [
            for (final col in widget.columns)
              cellBox(
                col,
                showRows
                    ? col.cell(context, rows[i])
                    : const DashSkeleton(height: Space.lg, width: Space.xxl),
              ),
            SizedBox(width: edge),
          ],
        );

        Widget placed(int i, Widget child) {
          final key = showRows ? widget.rowKey(rows[i]) : 'skeleton-$i';
          return AnimatedPositioned(
            key: ValueKey(key),
            top: i * OpsRankTable.rowHeight,
            left: 0,
            right: 0,
            height: OpsRankTable.rowHeight,
            duration: DashMotion.of(context, DashMotion.slow),
            curve: DashMotion.ease,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: i == count - 1 ? null : Border(bottom: hairline),
              ),
              child: showRows ? _RiseIn(index: i, child: child) : child,
            ),
          );
        }

        final fullHeight = count * OpsRankTable.rowHeight;
        final leadHeader = headerCell(
          widget.lead,
          width: leadWidth,
          padding: EdgeInsetsDirectional.only(start: edge, end: Space.md),
        );
        final stickyEdge = fits
            ? null
            : BoxDecoration(border: BorderDirectional(end: hairline));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The header: outside the body's scroll, so it stays.
            DecoratedBox(
              decoration: BoxDecoration(border: Border(bottom: hairline)),
              child: SizedBox(
                height: DashMetrics.tableHeader,
                child: Row(
                  children: [
                    Container(
                      width: leadWidth,
                      decoration: stickyEdge,
                      child: leadHeader,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _head,
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: Row(
                          children: [
                            for (final col in widget.columns) headerCell(col),
                            SizedBox(width: edge),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: bodyHeight,
              child: SingleChildScrollView(
                key: const ValueKey('ops-rank-body'),
                physics: count > widget.maxVisibleRows
                    ? null
                    : const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  height: fullHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        key: const ValueKey('ops-rank-lead'),
                        width: leadWidth,
                        height: fullHeight,
                        decoration: stickyEdge,
                        child: Stack(
                          children: [
                            for (var i = 0; i < count; i++)
                              placed(i, leadOf(i)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          key: const ValueKey('ops-rank-figures'),
                          controller: _body,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: restWidth,
                            height: fullHeight,
                            child: Stack(
                              children: [
                                for (var i = 0; i < count; i++)
                                  placed(i, restOf(i)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A header: its label, and for a sortable column a button with the sort's
/// arrow, read as "Revenue, sorted descending".
class _SortHeader extends StatelessWidget {
  const _SortHeader({
    required this.padding,
    required this.label,
    required this.numeric,
    required this.sorted,
    required this.sortedAscendingLabel,
    required this.sortedDescendingLabel,
    required this.onPressed,
    super.key,
  });

  final EdgeInsetsGeometry padding;
  final String label;
  final bool numeric;
  final OpsRankSort? sorted;
  final String sortedAscendingLabel;
  final String sortedDescendingLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final align = numeric
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart;
    final text = MadarClippedText(
      label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: DashType.tableHeader.copyWith(
        color: sorted != null ? c.textPrimary : c.textSecondary,
      ),
    );
    if (onPressed == null) {
      return Padding(
        padding: padding,
        child: Align(alignment: align, child: text),
      );
    }
    final s = sorted;
    final state = s == null
        ? ''
        : ', ${s.descending ? sortedDescendingLabel : sortedAscendingLabel}';
    return DashPressable(
      onTap: onPressed,
      pressScale: false,
      selected: s != null,
      semanticLabel: '$label$state',
      excludeChildSemantics: true,
      builder: (context, st) => Container(
        height: DashMetrics.tableHeader,
        padding: padding,
        alignment: align,
        foregroundDecoration: dashFocusRing(
          context,
          st,
          BorderRadius.circular(Radii.xs),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            Flexible(child: text),
            DashIcon(
              s == null
                  ? 'chevrons-up-down'
                  : s.descending
                  ? 'arrow-down'
                  : 'arrow-up',
              size: IconSize.xs,
              color: s != null || st.hovered ? c.textPrimary : c.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// A row's entrance: invisible and a few pixels low on its first frame,
/// rising and fading in after a stagger of [index]; at rest at once under
/// reduced motion. Plays once per row: a re-sort moves it, never replays it.
class _RiseIn extends StatefulWidget {
  const _RiseIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<_RiseIn> with SingleTickerProviderStateMixin {
  static const Duration _step = Duration(milliseconds: 30);
  static const int _maxStagger = 10;
  static const double _rise = Space.sm;

  late final Duration _delay = _step * math.min(widget.index, _maxStagger);
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: DashMotion.slow + _delay,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _ctl,
    curve: Interval(
      _delay.inMicroseconds / _ctl.duration!.inMicroseconds,
      1,
      curve: DashMotion.ease,
    ),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Decided before the first frame, so a reduced-motion row is never faint.
    if (DashMotion.reduced(context)) {
      _ctl.value = 1;
    } else {
      _ctl.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _curve;
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, _rise * (1 - curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
