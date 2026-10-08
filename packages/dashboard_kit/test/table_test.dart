import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Order {
  const _Order(this.id, this.name, this.total);
  final String id;
  final String name;
  final int total;
}

final _rows = [
  for (var i = 0; i < 23; i++)
    _Order(
      'o$i',
      'Order ${String.fromCharCode(65 + (i * 7) % 26)}$i',
      (i * 37) % 100,
    ),
];

List<DashColumn<_Order>> _cols() => [
  DashColumn<_Order>(
    id: 'name',
    label: 'Name',
    text: (o) => o.name,
    sortValue: (o) => o.name,
  ),
  DashColumn<_Order>(
    id: 'total',
    label: 'Total',
    text: (o) => '${o.total}',
    sortValue: (o) => o.total,
    numeric: true,
  ),
];

Widget _table({
  List<_Order>? rows,
  ValueChanged<_Order>? onTap,
  bool selectable = false,
  bool loading = false,
  String? error,
  VoidCallback? onRetry,
  String? search,
  ValueChanged<Set<Object>>? onSelection,
  Widget Function(BuildContext, List<_Order>, VoidCallback)? bulk,
}) => Scaffold(
  body: SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: DashDataTable<_Order>(
      columns: _cols(),
      rows: rows ?? _rows,
      rowKey: (o) => o.id,
      onRowTap: onTap,
      selectable: selectable,
      loading: loading,
      errorMessage: error,
      onRetry: onRetry,
      searchPlaceholder: search,
      onSelectionChanged: onSelection,
      bulkActions: bulk,
    ),
  ),
);

void main() {
  testWidgets('pages ten at a time with Page X of Y, previous and next', (
    tester,
  ) async {
    await pumpDashApp(tester, _table());
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(find.text(_rows[0].name), findsOneWidget);
    expect(find.text(_rows[10].name), findsNothing);
    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(find.text(_rows[10].name), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 3 of 3'), findsOneWidget);
    expect(find.text(_rows[22].name), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Previous'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
  });

  testWidgets('no pager for a single page', (tester) async {
    await pumpDashApp(tester, _table(rows: _rows.take(4).toList()));
    expect(find.textContaining('Page '), findsNothing);
  });

  testWidgets('a header tap sorts ascending, then descending, then ascending', (
    tester,
  ) async {
    await pumpDashApp(tester, _table());
    List<int> totalsOnPage() => [
      for (final o in _rows)
        if (find.text(o.name).evaluate().isNotEmpty) o.total,
    ];
    await tester.tap(find.bySemanticsLabel('Total'));
    await tester.pumpAndSettle();
    final asc = [..._rows]..sort((a, b) => a.total.compareTo(b.total));
    expect(find.text(asc.first.name), findsOneWidget);
    expect(totalsOnPage().length, 10);
    expect(totalsOnPage().every((t) => t <= asc[9].total), isTrue);

    await tester.tap(find.bySemanticsLabel('Total'));
    await tester.pumpAndSettle();
    expect(find.text(asc.last.name), findsOneWidget);
    expect(
      totalsOnPage().every((t) => t >= asc[asc.length - 10].total),
      isTrue,
    );

    await tester.tap(find.bySemanticsLabel('Total'));
    await tester.pumpAndSettle();
    expect(find.text(asc.first.name), findsOneWidget);
  });

  testWidgets('server sort is reported, not applied', (tester) async {
    DashSort? got;
    await pumpDashApp(
      tester,
      Scaffold(
        body: DashDataTable<_Order>(
          columns: _cols(),
          rows: _rows.take(5).toList(),
          rowKey: (o) => o.id,
          sort: const DashSort('name'),
          onSortChanged: (s) => got = s,
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Name'));
    expect(got, const DashSort('name', descending: true));
    await tester.tap(find.bySemanticsLabel('Total'));
    expect(got, const DashSort('total'));
  });

  testWidgets('server paging hands the page to the caller', (tester) async {
    var page = 0;
    await pumpDashApp(
      tester,
      StatefulBuilder(
        builder: (context, set) => Scaffold(
          body: DashDataTable<_Order>(
            columns: _cols(),
            rows: _rows.skip(page * 10).take(10).toList(),
            rowKey: (o) => o.id,
            pageIndex: page,
            pageCount: 3,
            onPageChanged: (p) => set(() => page = p),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pumpAndSettle();
    expect(page, 1);
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(find.text(_rows[10].name), findsOneWidget);
  });

  testWidgets('row tap opens the record; Load more only while there is more', (
    tester,
  ) async {
    _Order? opened;
    var more = 0;
    await pumpDashApp(
      tester,
      Scaffold(
        body: DashDataTable<_Order>(
          columns: _cols(),
          rows: _rows.take(3).toList(),
          rowKey: (o) => o.id,
          onRowTap: (o) => opened = o,
          loadMore: DashLoadMore(hasMore: true, onLoadMore: () => more++),
        ),
      ),
    );
    await tester.tap(find.text(_rows[1].name));
    expect(opened, _rows[1]);
    await tester.tap(find.text('Load more'));
    expect(more, 1);
    await pumpDashApp(
      tester,
      Scaffold(
        body: DashDataTable<_Order>(
          columns: _cols(),
          rows: _rows.take(3).toList(),
          rowKey: (o) => o.id,
          loadMore: DashLoadMore(hasMore: false, onLoadMore: () => more++),
        ),
      ),
    );
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('selection: a row, select all, the bulk bar, clear', (
    tester,
  ) async {
    Set<Object> sel = {};
    List<_Order> bulkGot = [];
    await pumpDashApp(
      tester,
      _table(
        selectable: true,
        onSelection: (s) => sel = s,
        bulk: (context, selected, clear) {
          bulkGot = selected;
          return DashButton(label: 'Approve', onPressed: clear);
        },
      ),
    );
    expect(find.text('Approve'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Select row').at(1));
    await tester.pumpAndSettle();
    expect(sel, {'o1'});
    expect(find.text('1 selected'), findsOneWidget);
    expect(bulkGot.map((o) => o.id), ['o1']);

    await tester.tap(find.bySemanticsLabel('Select all'));
    await tester.pumpAndSettle();
    expect(sel.length, 10);
    expect(find.text('10 selected'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(sel, isEmpty);
    expect(find.text('Approve'), findsNothing);
  });

  testWidgets('a row checkbox never opens the row', (tester) async {
    _Order? opened;
    await pumpDashApp(
      tester,
      _table(selectable: true, onTap: (o) => opened = o),
    );
    await tester.tap(find.bySemanticsLabel('Select row').first);
    await tester.pumpAndSettle();
    expect(opened, isNull);
  });

  testWidgets('the Columns menu hides and shows a column', (tester) async {
    await pumpDashApp(tester, _table());
    expect(find.text('TOTAL'), findsOneWidget);
    await tester.tap(find.text('Columns'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Total').first);
    await tester.pumpAndSettle();
    expect(find.text('TOTAL'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Total').first);
    await tester.pumpAndSettle();
    expect(find.text('TOTAL'), findsOneWidget);
  });

  testWidgets('search filters the rows on their text', (tester) async {
    await pumpDashApp(tester, _table(search: 'Search orders'));
    await tester.enterText(find.byType(TextField), _rows[13].name);
    await tester.pumpAndSettle();
    expect(find.text(_rows[13].name), findsNWidgets(2));
    expect(find.text(_rows[0].name), findsNothing);
    expect(find.textContaining('Page '), findsNothing);
  });

  testWidgets('loading draws skeleton rows, never the empty state', (
    tester,
  ) async {
    await pumpDashApp(tester, _table(rows: const [], loading: true));
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('No results found'), findsNothing);
  });

  testWidgets('an error shows its words and Retry instead of an empty table', (
    tester,
  ) async {
    var retried = 0;
    await pumpDashApp(
      tester,
      _table(rows: const [], error: 'Network down', onRetry: () => retried++),
    );
    expect(find.text('Network down'), findsOneWidget);
    expect(find.text("Couldn't load this"), findsOneWidget);
    expect(find.text('No results found'), findsNothing);
    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('an empty list draws the empty state', (tester) async {
    await pumpDashApp(tester, _table(rows: const []));
    expect(find.text('No results found'), findsOneWidget);
  });

  testWidgets('a phone draws a card per row with label/value pairs', (
    tester,
  ) async {
    _Order? opened;
    await pumpDashApp(
      tester,
      _table(rows: _rows.take(3).toList(), onTap: (o) => opened = o),
      size: DashSize.phone,
    );
    expect(find.text('NAME'), findsNothing);
    expect(find.text('Total'), findsNWidgets(3));
    await tester.tap(find.text(_rows[2].name));
    expect(opened, _rows[2]);
  });

  testWidgets('Arabic: the pager reads in Arabic and next still goes forward', (
    tester,
  ) async {
    await pumpDashApp(tester, _table(), lang: 'ar');
    expect(find.text('صفحة 1 من 3'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('التالي'));
    await tester.pumpAndSettle();
    expect(find.text('صفحة 2 من 3'), findsOneWidget);
  });

  testWidgets(
    'narrower than its columns, the table scrolls sideways instead of overflowing',
    (tester) async {
      await pumpDashApp(
        tester,
        Scaffold(
          body: DashDataTable<_Order>(
            columns: [
              for (var i = 0; i < 9; i++)
                DashColumn<_Order>(
                  id: 'c$i',
                  label: 'Column $i',
                  text: (o) => o.name,
                  width: 160,
                ),
            ],
            rows: _rows.take(3).toList(),
            rowKey: (o) => o.id,
          ),
        ),
        size: DashSize.tablet,
      );
      expect(tester.takeException(), isNull);
      final scroll = find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(scroll, findsOneWidget);
      expect(find.text('COLUMN 8'), findsOneWidget);
      await tester.drag(scroll, const Offset(-600, 0));
      await tester.pump();
      expect(
        tester.getRect(find.text('COLUMN 8')).right,
        lessThan(DashSize.tablet.size.width),
      );
    },
  );

  testWidgets('with expand, the header stays while the rows scroll under it', (
    tester,
  ) async {
    await pumpDashApp(
      tester,
      Scaffold(
        body: SizedBox(
          height: 400,
          child: DashDataTable<_Order>(
            columns: _cols(),
            rows: _rows,
            rowKey: (o) => o.id,
            pageSize: 50,
            expand: true,
          ),
        ),
      ),
    );
    final headerTop = tester.getRect(find.text('NAME')).top;
    await tester.drag(find.text(_rows[3].name), const Offset(0, -300));
    await tester.pump();
    expect(tester.getRect(find.text('NAME')).top, headerTop);
    expect(find.text(_rows[0].name), findsNothing);
  });
}
