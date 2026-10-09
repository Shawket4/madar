/// The plain bordered table the count editor and the variance report share
/// (the web's `Table` inside `overflow-x-auto rounded-lg border`): fixed
/// columns, the first one taking the rest, sideways scrolling when the room
/// is narrower than the columns (also on a phone: there are no cards).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_labels.dart';
import 'counts_data.dart';

/// Column widths (cell padding included).
abstract final class CountWidths {
  /// The ingredient column's floor before the table scrolls sideways.
  static const double name = Space.xxl * 7;
  static const double book = Space.xxl * 5;

  /// `w-28` input plus padding.
  static const double input = Space.xxl * 4 + Space.lg;
  static const double figure = Space.xxl * 4;
  static const double value = Space.xxl * 4 + Space.sm;

  /// `w-44` select plus padding.
  static const double reason = Space.xxl * 6 + Space.sm;

  /// The variance report's read-only columns (they fit its 896 wide
  /// dialog).
  static const double reportBook = Space.xxl * 4 + Space.sm;
  static const double reportFigure = Space.xxl * 3 + Space.sm;
  static const double reportReason = Space.xxl * 4 + Space.lg;
}

class CountColumn {
  const CountColumn(this.label, {this.width, this.end = false});

  final String label;

  /// Null: takes the free width (at least [CountWidths.name]).
  final double? width;

  /// Figures sit at the end.
  final bool end;
}

class CountTableRow {
  const CountTableRow({required this.cells, this.wash, this.key});

  final List<Widget> cells;

  /// A flagged row's warning wash.
  final Color? wash;
  final Key? key;
}

class CountTable extends StatelessWidget {
  const CountTable({
    required this.columns,
    required this.rows,
    this.footer,
    super.key,
  });

  final List<CountColumn> columns;
  final List<CountTableRow> rows;

  /// A full-width row after the rows ("No results found").
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final fixed = columns.fold<double>(0, (s, col) => s + (col.width ?? 0));
    final line = BorderSide(color: c.hairline);
    final frame = LayoutBuilder(
      builder: (context, box) {
        final total = box.maxWidth < fixed + CountWidths.name
            ? fixed + CountWidths.name
            : box.maxWidth;
        final free = total - fixed;
        Widget cell(CountColumn col, Widget child) => SizedBox(
          width: col.width ?? free,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm,
            ),
            child: Align(
              alignment: col.end
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: child,
            ),
          ),
        );
        final header = Container(
          constraints: const BoxConstraints(minHeight: DashMetrics.tableHeader),
          decoration: BoxDecoration(border: Border(bottom: line)),
          child: Row(
            children: [
              for (final col in columns)
                cell(
                  col,
                  Text(
                    col.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.tableHeader.copyWith(color: c.textMuted),
                  ),
                ),
            ],
          ),
        );
        final table = SizedBox(
          width: total,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              for (var i = 0; i < rows.length; i++)
                Container(
                  key: rows[i].key,
                  constraints: const BoxConstraints(
                    minHeight: DashMetrics.tableRow,
                  ),
                  decoration: BoxDecoration(
                    color: rows[i].wash,
                    border: i == rows.length - 1 && footer == null
                        ? null
                        : Border(bottom: line),
                  ),
                  child: Row(
                    children: [
                      for (var k = 0; k < columns.length; k++)
                        cell(columns[k], rows[i].cells[k]),
                    ],
                  ),
                ),
              ?footer,
            ],
          ),
        );
        return total > box.maxWidth
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: table,
              )
            : table;
      },
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: c.hairline),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: frame,
    );
  }
}

/// A figure cell: mono, tabular, left-to-right.
class CountFigure extends StatelessWidget {
  const CountFigure(this.text, {this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textDirection: TextDirection.ltr,
    maxLines: 1,
    style: DashType.mono.copyWith(
      color: color ?? context.madarColors.textPrimary,
    ),
  );
}

/// A difference's colour: danger below zero, success above, else none.
Color? countDifferenceColor(MadarColors c, num? diff) => diff == null
    ? null
    : diff < 0
    ? DashTone.danger.foreground(c)
    : diff > 0
    ? DashTone.success.foreground(c)
    : null;

/// The ingredient cell: the name, its pills, the category under it.
class CountNameCell extends StatelessWidget {
  const CountNameCell({
    required this.name,
    required this.category,
    this.pills = const [],
    super.key,
  });

  final String name;
  final String category;
  final List<Widget> pills;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs / 2,
      children: [
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              name,
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
            ...pills,
          ],
        ),
        Text(category, style: DashType.small.copyWith(color: c.textSecondary)),
      ],
    );
  }
}

/// Book stock with its unit, and "was X at start" when it moved since the
/// count opened.
class CountBookCell extends ConsumerWidget {
  const CountBookCell({
    required this.book,
    required this.opening,
    required this.unit,
    super.key,
  });

  final num book;
  final num opening;
  final String unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        CountFigure(qtyWithUnit(f, book, unit)),
        if (movedSinceStart(book, opening))
          Text(
            t(
              'inventory.stocktakes.atStart',
              args: {'qty': ltr(f.fmtNumber(opening))},
            ),
            textAlign: TextAlign.end,
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }
}
