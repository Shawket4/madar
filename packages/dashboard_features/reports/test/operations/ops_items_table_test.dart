// Operations › Items as a ranked table (OpsRankTable): sorting, search and
// the category filter, the sticky lead column on a phone, Arabic, and the
// motion (rows rise in from fully invisible; a re-sort slides them).
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/operations/ops_analytics.dart';
import 'package:dashboard_reports/src/operations/ops_rank_table.dart';
import 'package:dashboard_reports/src/operations/ops_report_kit.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder get _table => inPage(find.byKey(const ValueKey('ops-items-table')));
Finder get _lead => find.descendant(
  of: _table,
  matching: find.byKey(const ValueKey('ops-rank-lead')),
);

OpsRankTable<OpsItemRow> _widget(WidgetTester tester) =>
    tester.widget<OpsRankTable<OpsItemRow>>(_table);

/// The row ids top to bottom, as placed on screen.
List<String> _order(WidgetTester tester) {
  final placed =
      tester
          .widgetList<AnimatedPositioned>(
            find.descendant(
              of: _lead,
              matching: find.byType(AnimatedPositioned),
            ),
          )
          .toList()
        ..sort((a, b) => a.top!.compareTo(b.top!));
  return [for (final p in placed) (p.key! as ValueKey<Object>).value as String];
}

Finder _header(String id) => find.descendant(
  of: _table,
  matching: find.byKey(ValueKey('ops-rank-sort-$id')),
);

Future<DashHarness> _items(
  WidgetTester tester, {
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  bool reducedMotion = true,
}) async {
  final h = await pumpOps(
    tester,
    size: size,
    locale: locale,
    dark: dark,
    reducedMotion: reducedMotion,
  );
  await openTab(h, h.t('reports.operations.tabs.items'));
  return h;
}

void main() {
  testWidgets('starts by units sold, largest first; a header press sorts by '
      'it (largest first), a second press flips it; rank stays the item\'s', (
    tester,
  ) async {
    final h = await _items(tester);
    final rows = _widget(tester).rows;
    expect(rows.length, greaterThan(3));
    expect(_order(tester), [for (final r in rows) r.id]);
    await h.tap(_header('revenue'));
    final byRevenue = [...rows]..sort((a, b) => b.revenue.compareTo(a.revenue));
    expect(_order(tester), [for (final r in byRevenue) r.id]);
    await h.tap(_header('revenue'));
    expect(_order(tester), [for (final r in byRevenue.reversed) r.id]);
    // The name sorts A–Z first.
    await h.tap(_header('item'));
    final byName = [...rows]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    expect(_order(tester), [for (final r in byName) r.id]);
    // Average price: an item never sold on its own sorts last.
    await h.tap(_header('avg_price'));
    final order = _order(tester);
    final byId = {for (final r in rows) r.id: r};
    final prices = [for (final id in order) byId[id]!.avgPrice ?? -1];
    expect(prices, [...prices]..sort((a, b) => b.compareTo(a)));
  });

  testWidgets('headers are buttons that say their sort to a screen reader', (
    tester,
  ) async {
    final h = await _items(tester);
    final semantics = tester.ensureSemantics();
    final sold = tester.getSemantics(_header('quantity'));
    expect(sold.label, 'Sold, sorted descending');
    expect(sold.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(sold.flagsCollection.isButton, isTrue);
    await h.tap(_header('revenue'));
    await h.tap(_header('revenue'));
    expect(
      tester.getSemantics(_header('revenue')).label,
      'Revenue, sorted ascending',
    );
    expect(tester.getSemantics(_header('quantity')).label, 'Sold');
    semantics.dispose();
  });

  testWidgets('search narrows by name; the category filter by category; '
      'both together; nothing → the empty words', (tester) async {
    final h = await _items(tester);
    final all = _widget(tester).rows;
    final first = all.first;
    await h.enterText(
      find.descendant(
        of: inPage(find.byKey(const ValueKey('ops-items-search'))),
        matching: find.byType(EditableText),
      ),
      first.name.substring(0, 3),
    );
    final searched = _widget(tester).rows;
    expect(searched, isNotEmpty);
    expect(searched.length, lessThanOrEqualTo(all.length));
    expect(
      searched.every(
        (r) => r.name.toLowerCase().contains(
          first.name.substring(0, 3).toLowerCase(),
        ),
      ),
      isTrue,
    );
    await h.enterText(
      find.descendant(
        of: inPage(find.byKey(const ValueKey('ops-items-search'))),
        matching: find.byType(EditableText),
      ),
      '',
    );
    final categories = {for (final r in all) ?r.category}.toList()..sort();
    expect(categories.length, greaterThan(1));
    final select = inPage(find.byKey(const ValueKey('ops-items-category')));
    expect(
      [
        for (final o in tester.widget<DashSelect<String>>(select).options)
          o.label,
      ],
      ['All categories', ...categories],
    );
    await pickOption(h, select, categories.first);
    final narrowed = _widget(tester).rows;
    expect(narrowed, isNotEmpty);
    expect(narrowed.every((r) => r.category == categories.first), isTrue);
    expect(narrowed.length, lessThan(all.length));
    // Rank is the item's place over all items, not the filtered list's.
    expect(
      [for (final r in narrowed) r.rank],
      [
        for (final r in all)
          if (r.category == categories.first) r.rank,
      ],
    );
    await h.enterText(
      find.descendant(
        of: inPage(find.byKey(const ValueKey('ops-items-search'))),
        matching: find.byType(EditableText),
      ),
      'zzzz-no-such-item',
    );
    expect(
      find.descendant(
        of: inPage(find.byType(OpsItemsView)),
        matching: find.text('No data for this period'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('motion: a row\'s first frame is fully invisible (no ghost '
      'frame), rows stagger in, share bars grow from 0; a re-sort slides '
      'rows to their place', (tester) async {
    final h = await _items(tester, reducedMotion: false);
    // The tab switched: the table remounted.
    await openTab(h, 'Overview');
    await tester.tap(
      find.descendant(
        of: find.byType(DashPageTabs<String>),
        matching: find.text('Items'),
      ),
    );
    await tester.pump();
    Iterable<double> opacities() => tester
        .widgetList<Opacity>(
          find.descendant(of: _lead, matching: find.byType(Opacity)),
        )
        .map((o) => o.opacity);
    // The first frame: every row at exactly 0.
    expect(opacities(), isNotEmpty);
    expect(opacities().every((o) => o == 0), isTrue);
    Iterable<double?> bars() => tester
        .widgetList<FractionallySizedBox>(
          find.descendant(
            of: find.byType(OpsShareBar),
            matching: find.byType(FractionallySizedBox),
          ),
        )
        .map((b) => b.widthFactor);
    // The share bars start at 0.
    expect(bars(), isNotEmpty);
    expect(bars().every((w) => w == 0), isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    final mid = opacities().toList();
    // The first rows are on their way; the later ones still wait.
    expect(mid.first, greaterThan(0));
    expect(mid.first, greaterThan(mid.last));
    await tester.pump(const Duration(milliseconds: 800));
    expect(opacities().every((o) => o == 1), isTrue);
    // The bars grew to their share (the top one fills its track).
    expect(bars().reduce((a, b) => a! > b! ? a : b), 1);

    final before = _order(tester);
    final lastId = before.last;
    double topOf(String id) => tester
        .widget<AnimatedPositioned>(
          find.descendant(
            of: _lead,
            matching: find.byKey(ValueKey<Object>(id)),
          ),
        )
        .top!;
    final rowBox = find.descendant(
      of: _lead,
      matching: find.byKey(ValueKey<Object>(lastId)),
    );
    final startY = tester.getTopLeft(rowBox).dy;
    await tester.tap(_header('quantity'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final midY = tester.getTopLeft(rowBox).dy;
    await tester.pump(const Duration(milliseconds: 800));
    final endY = tester.getTopLeft(rowBox).dy;
    // Ascending now: the last row is first, and it slid there.
    expect(_order(tester).first, lastId);
    expect(topOf(lastId), 0);
    expect(midY, lessThan(startY));
    expect(midY, greaterThan(endY));
    // A re-sort never replays the entrance.
    expect(opacities().every((o) => o == 1), isTrue);
  });

  testWidgets('reduced motion: rows are there at once, never faint', (
    tester,
  ) async {
    await _items(tester);
    final ops = tester.widgetList<Opacity>(
      find.descendant(of: _lead, matching: find.byType(Opacity)),
    );
    expect(ops.every((o) => o.opacity == 1), isTrue);
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('phone ($lang): still a table; the item column stays at the '
        'start edge, the figures scroll sideways inside the card, the page '
        'never does', (tester) async {
      final h = await _items(tester, size: DashSize.phone, locale: lang);
      expect(_lead, findsOneWidget);
      final figures = find.descendant(
        of: _table,
        matching: find.byKey(const ValueKey('ops-rank-figures')),
      );
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: figures, matching: find.byType(Scrollable)),
      );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      final leadBox = tester.getRect(_lead);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      // Inside the screen, at the start edge of the card.
      expect(leadBox.left, greaterThanOrEqualTo(0));
      expect(leadBox.right, lessThanOrEqualTo(screen.width));
      final figuresBox = tester.getRect(figures);
      if (lang == 'ar') {
        expect(leadBox.left, greaterThan(figuresBox.left));
      } else {
        expect(leadBox.left, lessThan(figuresBox.left));
      }
      // Scrolling the figures leaves the item column where it was.
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await h.settle();
      expect(tester.getRect(_lead), leadBox);
      // The card fits the screen: the page never scrolls sideways.
      final card = find.ancestor(
        of: _table,
        matching: find.byType(OpsTableCard),
      );
      expect(tester.getRect(card).right, lessThanOrEqualTo(screen.width));
      expect(tester.getRect(card).left, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
      // The Arabic header and figures.
      if (lang == 'ar') {
        expect(
          find.descendant(of: _table, matching: find.text('الصنف')),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets('desktop: no sideways scroll, the item column takes the room', (
    tester,
  ) async {
    await _items(tester);
    final figures = find.descendant(
      of: _table,
      matching: find.byKey(const ValueKey('ops-rank-figures')),
    );
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: figures, matching: find.byType(Scrollable)),
    );
    expect(scroll.position.maxScrollExtent, 0);
    expect(tester.getSize(_lead).width, greaterThan(280));
  });
}
