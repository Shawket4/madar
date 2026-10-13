// A page's kit widgets keep their state in the page's PageStorage bucket
// (the shell gives every page one that outlives it, `DashListMemory`): the
// page scroll and a table's sort, search, page and hidden columns come back
// when the page is built again.
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Row {
  const _Row(this.id, this.name, this.total);
  final String id;
  final String name;
  final int total;
}

final _rows = [
  for (var i = 0; i < 23; i++) _Row('r$i', 'Row $i', (i * 37) % 100),
];

List<DashColumn<_Row>> _cols() => [
  DashColumn<_Row>(
    id: 'name',
    label: 'Name',
    text: (o) => o.name,
    sortValue: (o) => o.name,
  ),
  DashColumn<_Row>(
    id: 'total',
    label: 'Total',
    text: (o) => '${o.total}',
    sortValue: (o) => o.total,
    numeric: true,
  ),
];

Widget _table(PageStorageBucket bucket, {List<_Row>? rows}) => PageStorage(
  bucket: bucket,
  child: Scaffold(
    body: SingleChildScrollView(
      child: DashDataTable<_Row>(
        columns: _cols(),
        rows: rows ?? _rows,
        rowKey: (o) => o.id,
        searchPlaceholder: 'Search',
      ),
    ),
  ),
);

Widget _page(PageStorageBucket bucket, {int count = 60}) => PageStorage(
  bucket: bucket,
  child: DashPageScaffold(
    title: 'Long page',
    body: Column(
      children: [
        for (var i = 0; i < count; i++)
          SizedBox(height: 48, child: Text('Line $i')),
      ],
    ),
  ),
);

ScrollPosition _pagePosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(DashPageScaffold),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  testWidgets('a table gets its sort and page back with its page', (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    await pumpDashApp(tester, _table(bucket));
    await tester.tap(find.bySemanticsLabel('Total'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);

    // Away (the page is gone) and back.
    await pumpDashApp(tester, const SizedBox.shrink());
    await pumpDashApp(tester, _table(bucket));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
    // Sorted by total, second page: the 11th smallest is on it.
    final asc = [..._rows]..sort((a, b) => a.total.compareTo(b.total));
    expect(find.text(asc[10].name), findsOneWidget);
    expect(find.text(asc.first.name), findsNothing);
  });

  testWidgets('a table restores its page once the rows arrive', (tester) async {
    final bucket = PageStorageBucket();
    await pumpDashApp(tester, _table(bucket));
    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pumpAndSettle();
    await pumpDashApp(tester, const SizedBox.shrink());
    // Back while the list is still loading: no rows yet.
    await pumpDashApp(tester, _table(bucket, rows: const []));
    await pumpDashApp(tester, _table(bucket));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
  });

  testWidgets('a table gets its search back', (tester) async {
    final bucket = PageStorageBucket();
    await pumpDashApp(tester, _table(bucket));
    await tester.enterText(find.byType(EditableText).first, 'Row 2');
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Row 5'), findsNothing);
    await pumpDashApp(tester, const SizedBox.shrink());
    await pumpDashApp(tester, _table(bucket));
    await tester.pumpAndSettle();
    expect(find.text('Row 5'), findsNothing);
    expect(find.text('Row 20'), findsOneWidget);
  });

  testWidgets('the page scroll comes back', (tester) async {
    final bucket = PageStorageBucket();
    await pumpDashApp(tester, _page(bucket));
    await tester.pumpAndSettle();
    _pagePosition(tester).jumpTo(900);
    await tester.pumpAndSettle();
    await pumpDashApp(tester, const SizedBox.shrink());
    await pumpDashApp(tester, _page(bucket));
    await tester.pumpAndSettle();
    expect(_pagePosition(tester).pixels, 900);
  });

  testWidgets('the page scroll waits for the content to grow back', (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    await pumpDashApp(tester, _page(bucket));
    await tester.pumpAndSettle();
    _pagePosition(tester).jumpTo(900);
    await tester.pumpAndSettle();
    await pumpDashApp(tester, const SizedBox.shrink());
    // Back while the list is loading (short), then the rows land.
    await pumpDashApp(tester, _page(bucket, count: 2));
    await tester.pumpAndSettle();
    expect(_pagePosition(tester).pixels, 0);
    await pumpDashApp(tester, _page(bucket));
    await tester.pumpAndSettle();
    expect(_pagePosition(tester).pixels, 900);
  });

  testWidgets('a page with no memory starts at the top', (tester) async {
    await pumpDashApp(tester, _page(PageStorageBucket()));
    await tester.pumpAndSettle();
    expect(_pagePosition(tester).pixels, 0);
  });
}
