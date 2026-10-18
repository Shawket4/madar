// DashIntent: the moment before a press (a resting pointer, focus, a touch
// going down), when a page warms the read the press will make.
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<TestGesture> _mouse(WidgetTester tester) async {
  final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await m.addPointer(location: Offset.zero);
  addTearDown(m.removePointer);
  return m;
}

void main() {
  testWidgets('a resting pointer fires once, after the dwell', (tester) async {
    var n = 0;
    await pumpDashApp(
      tester,
      Center(
        child: DashButton(label: 'Open', onPressed: () {}, onIntent: () => n++),
      ),
    );
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.text('Open')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(n, 0, reason: 'still within the dwell');
    await tester.pump(kDashIntentDwell);
    expect(n, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(n, 1, reason: 'resting longer does not fire again');
  });

  testWidgets('a pointer sweeping across rows warms none of them', (
    tester,
  ) async {
    final warmed = <int>[];
    await pumpDashApp(
      tester,
      Column(
        children: [
          for (var i = 0; i < 4; i++)
            DashListRow(
              title: 'Row $i',
              onTap: () {},
              onIntent: () => warmed.add(i),
            ),
        ],
      ),
    );
    final mouse = await _mouse(tester);
    for (var i = 0; i < 4; i++) {
      await mouse.moveTo(tester.getCenter(find.text('Row $i')));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await mouse.moveTo(const Offset(5, 790));
    await tester.pump(const Duration(seconds: 1));
    expect(warmed, isEmpty);

    // Resting on one warms that one only.
    await mouse.moveTo(tester.getCenter(find.text('Row 2')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(warmed, [2]);
  });

  testWidgets('keyboard focus fires at once', (tester) async {
    var n = 0;
    await pumpDashApp(
      tester,
      Center(
        child: DashButton(label: 'Open', onPressed: () {}, onIntent: () => n++),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(n, 1);
  });

  testWidgets('a touch fires when it goes down, before the tap ends', (
    tester,
  ) async {
    final log = <String>[];
    await pumpDashApp(
      tester,
      Center(
        child: DashCard(
          onTap: () => log.add('tap'),
          onIntent: () => log.add('intent'),
          child: const Text('Card'),
        ),
      ),
      size: DashSize.phone,
    );
    final touch = await tester.startGesture(
      tester.getCenter(find.text('Card')),
    );
    await tester.pump();
    expect(log, ['intent']);
    await touch.up();
    await tester.pump();
    expect(log, ['intent', 'tap']);
  });

  testWidgets('a disabled control warms nothing', (tester) async {
    var n = 0;
    await pumpDashApp(
      tester,
      Center(
        child: DashButton(label: 'Open', onPressed: null, onIntent: () => n++),
      ),
    );
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.text('Open')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Open'), warnIfMissed: false);
    await tester.pump();
    expect(n, 0);
  });

  testWidgets('the table: a row warms that row, the pager its target page', (
    tester,
  ) async {
    final rows = <String>[];
    final pages = <int>[];
    await pumpDashApp(
      tester,
      SingleChildScrollView(
        child: DashDataTable<String>(
          columns: [
            DashColumn<String>(id: 'name', label: 'Name', text: (s) => s),
          ],
          rows: const ['Alpha', 'Beta'],
          rowKey: (s) => s,
          onRowTap: (_) {},
          onRowIntent: rows.add,
          pageIndex: 0,
          pageCount: 3,
          onPageChanged: (_) {},
          onPageIntent: pages.add,
        ),
      ),
    );
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.text('Beta')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(rows, ['Beta']);

    await mouse.moveTo(tester.getCenter(find.bySemanticsLabel('Next')));
    await tester.pump(const Duration(milliseconds: 200));
    await mouse.moveTo(tester.getCenter(find.bySemanticsLabel('Previous')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(pages, [1], reason: 'page 1 has no previous page to warm');
  });

  testWidgets('tabs, segments and menu items pass their own value', (
    tester,
  ) async {
    final warmed = <String>[];
    await pumpDashApp(
      tester,
      Column(
        children: [
          DashTabStrip<String>(
            tabs: const [
              DashTab(value: 'a', label: 'Tab A'),
              DashTab(value: 'b', label: 'Tab B'),
            ],
            value: 'a',
            onChanged: (_) {},
            onIntent: (v) => warmed.add('tab:$v'),
          ),
          DashSegmentedControl<String>(
            options: const [
              DashOption(value: 'x', label: 'Seg X'),
              DashOption(value: 'y', label: 'Seg Y'),
            ],
            value: 'x',
            onChanged: (_) {},
            onIntent: (v) => warmed.add('seg:$v'),
          ),
          DashMenu(
            items: [
              DashMenuItem(
                label: 'Details',
                onSelected: () {},
                onIntent: () => warmed.add('menu'),
              ),
            ],
            builder: (context, c) =>
                DashButton(label: 'More', onPressed: c.toggle),
          ),
        ],
      ),
    );
    final mouse = await _mouse(tester);
    Future<void> rest(String text) async {
      await mouse.moveTo(tester.getCenter(find.text(text)));
      await tester.pump(const Duration(milliseconds: 200));
    }

    await rest('Tab B');
    await rest('Seg Y');
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await rest('Details');
    expect(warmed, ['tab:b', 'seg:y', 'menu']);
  });

  testWidgets('batch 1 hooks: load more, back, add, date, quick range, '
      'select field option', (tester) async {
    final warmed = <String>[];
    await pumpDashApp(
      tester,
      Scaffold(
        body: DashPageScaffold(
          title: 'Requests',
          onBack: () {},
          onBackIntent: () => warmed.add('back'),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashDataTable<String>(
                columns: [
                  DashColumn<String>(id: 'n', label: 'Name', text: (s) => s),
                ],
                rows: const ['Alpha'],
                rowKey: (s) => s,
                loadMore: DashLoadMore(
                  hasMore: true,
                  onLoadMore: () {},
                  onIntent: () => warmed.add('more'),
                ),
              ),
              DashEditableCardGrid<String>(
                rows: const [],
                rowKey: (r) => r,
                titleField: DashEditableField(
                  key: 'name',
                  label: 'Name',
                  getValue: (r) => r,
                ),
                fields: const [],
                onCommit: (row, patch) async {},
                onAdd: () {},
                addLabel: 'Add item',
                onAddIntent: () => warmed.add('add'),
              ),
              SizedBox(
                width: 300,
                child: DashDateField(
                  value: DateTime(2026, 10, 9),
                  semanticLabel: 'Day',
                  onChanged: (_) {},
                  onIntent: () => warmed.add('date'),
                ),
              ),
              SizedBox(
                width: 500,
                child: DashDateRangeField(
                  from: null,
                  to: null,
                  today: DateTime(2026, 10, 9),
                  onChanged: (_, _) {},
                  onQuickIntent: (from, to) =>
                      warmed.add('quick:${from.month}/${from.day}'),
                ),
              ),
              SizedBox(
                width: 300,
                child: DashSelectField<String>(
                  label: 'Branch',
                  options: const [
                    DashOption(value: 'z', label: 'Zamalek'),
                    DashOption(value: 'm', label: 'Maadi'),
                  ],
                  value: 'z',
                  onChanged: (_) {},
                  onOptionIntent: (v) => warmed.add('option:$v'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final mouse = await _mouse(tester);
    Future<void> rest(Finder f) async {
      await mouse.moveTo(tester.getCenter(f));
      await tester.pump(const Duration(milliseconds: 200));
    }

    await rest(find.bySemanticsLabel('Back'));
    await rest(find.text('Load more'));
    await rest(find.text('Add item'));
    await rest(find.bySemanticsLabel(RegExp('^Day')));
    await rest(find.text('This month'));
    await tester.tap(find.text('Zamalek'));
    await tester.pumpAndSettle();
    await rest(find.text('Maadi'));
    expect(warmed, ['back', 'more', 'add', 'date', 'quick:10/1', 'option:m']);
  });

  group('to: the page a press opens, through DashRouteIntent', () {
    Widget scope(List<String> log, Widget child) =>
        DashRouteIntent(onRoute: log.add, child: child);

    testWidgets('a card, a row, a button, a tab and back warm their page', (
      tester,
    ) async {
      final log = <String>[];
      await pumpDashApp(
        tester,
        scope(
          log,
          Scaffold(
            body: DashPageScaffold(
              title: 'Detail',
              onBack: () {},
              backTo: '/list',
              body: Column(
                children: [
                  DashCard(
                    onTap: () {},
                    to: '/card',
                    child: const Text('Card'),
                  ),
                  DashListRow(title: 'Row', onTap: () {}, to: '/row'),
                  DashButton(label: 'View all', onPressed: () {}, to: '/all'),
                  DashTabStrip<String>(
                    tabs: const [
                      DashTab(value: 'a', label: 'Tab A', to: '/a'),
                      DashTab(value: 'b', label: 'Tab B', to: '/b'),
                    ],
                    value: 'a',
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final mouse = await _mouse(tester);
      Future<void> rest(Finder f) async {
        await mouse.moveTo(tester.getCenter(f));
        await tester.pump(const Duration(milliseconds: 200));
      }

      await rest(find.bySemanticsLabel('Back'));
      await rest(find.text('Card'));
      await rest(find.text('Row'));
      await rest(find.text('View all'));
      await rest(find.text('Tab A'));
      await rest(find.text('Tab B'));
      expect(log, ['/list', '/card', '/row', '/all', '/b']);
    });

    testWidgets('the table: rowTo warms each row its own detail page', (
      tester,
    ) async {
      final log = <String>[];
      await pumpDashApp(
        tester,
        scope(
          log,
          SingleChildScrollView(
            child: DashDataTable<String>(
              columns: [
                DashColumn<String>(id: 'name', label: 'Name', text: (s) => s),
              ],
              rows: const ['Alpha', 'Beta'],
              rowKey: (s) => s,
              onRowTap: (_) {},
              rowTo: (s) => '/things/$s',
            ),
          ),
        ),
      );
      final touch = await tester.startGesture(
        tester.getCenter(find.text('Beta')),
      );
      await tester.pump();
      expect(log, ['/things/Beta'], reason: 'a touch warms on pointer down');
      await touch.up();
      await tester.pump();
    });

    testWidgets('rapid hover over a long list fires no burst', (tester) async {
      final log = <String>[];
      await pumpDashApp(
        tester,
        scope(
          log,
          SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < 12; i++)
                  DashListRow(title: 'Row $i', onTap: () {}, to: '/r/$i'),
              ],
            ),
          ),
        ),
      );
      final mouse = await _mouse(tester);
      // Down the list and back up, 20 ms a row: faster than the dwell.
      for (final i in [...List.generate(12, (i) => i), 10, 8, 6, 4, 2, 0]) {
        await mouse.moveTo(tester.getCenter(find.text('Row $i')));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 20));
      expect(log, isEmpty, reason: 'nothing rested long enough');
      // Stopping on the last row warms that one only, once.
      await tester.pump(kDashIntentDwell);
      await tester.pump(const Duration(seconds: 1));
      expect(log, ['/r/0']);
    });

    testWidgets('without a scope above, to: does nothing', (tester) async {
      await pumpDashApp(
        tester,
        Center(
          child: DashButton(label: 'Open', onPressed: () {}, to: '/x'),
        ),
      );
      final mouse = await _mouse(tester);
      await mouse.moveTo(tester.getCenter(find.text('Open')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });
  });
}
