// Operations › Items as a ranked table (OpsRankTable): sorting, search and
// the category filter, the sticky lead column on a phone, Arabic, and the
// motion (rows rise in from fully invisible; a re-sort slides them).
import 'package:dashboard_api/dashboard_api.dart'
    show BranchSalesReport, CombinedItemSalesRow, MenuItemFull;
import 'package:dashboard_core/dashboard_core.dart' show formatProvider;
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
    // Price and average extra: largest first, then flipped; an item
    // without the figure ("—") sorts last both ways.
    final byId = {for (final r in rows) r.id: r};
    for (final (col, value) in [
      ('price', (OpsItemRow r) => r.priceMin),
      ('avg_extra', (OpsItemRow r) => r.avgExtra),
    ]) {
      for (final descending in [true, false]) {
        await h.tap(_header(col));
        final got = [for (final id in _order(tester)) value(byId[id]!)];
        final known = got.whereType<int>().toList();
        expect(
          known,
          [...known]..sort((a, b) => descending ? b - a : a - b),
          reason: '$col ${descending ? 'desc' : 'asc'}',
        );
        expect(
          got.skipWhile((v) => v != null).every((v) => v == null),
          isTrue,
          reason: '$col: "—" last',
        );
      }
    }
  });

  test('avg extra: an item renamed mid-window sums its report rows; an older '
      'server (no extras_total) or an item the report does not list is "—"; '
      'price is the menu\'s active sizes as a range, else its base price', () {
    MenuItemFull menuItem(String id, int base, List<(int, bool)> sizes) =>
        MenuItemFull.fromJson({
          'id': id,
          'org_id': 'o',
          'name': id,
          'name_translations': <String, Object?>{},
          'description_translations': <String, Object?>{},
          'base_price': base,
          'is_active': true,
          'created_at': '2026-10-18T00:00:00Z',
          'updated_at': '2026-10-18T00:00:00Z',
          'addon_slots': const <Object?>[],
          'allowed_addon_ids': const <Object?>[],
          'optional_fields': const <Object?>[],
          'recipes': const <Object?>[],
          'sizes': const <Object?>[],
          'all_sizes': [
            for (final (i, (p, on)) in sizes.indexed)
              {
                'id': '$id-$i',
                'menu_item_id': id,
                'label': 'S$i',
                'price_override': p,
                'is_active': on,
              },
          ],
        });
    Map<String, Object?> sold(String id, String name, int q, int? extras) => {
      'menu_item_id': id,
      'item_name': name,
      'item_name_translations': <String, Object?>{},
      'quantity_sold': q,
      'revenue': q * 1000,
      'menu_total': ?(extras == null ? null : q * 1000),
      'extras_total': ?extras,
    };
    final sales = BranchSalesReport.fromJson({
      'branch_id': 'b',
      'branch_name': 'B',
      'total_orders': 1,
      'voided_orders': 0,
      'subtotal': 0,
      'total_discount': 0,
      'total_tax': 0,
      'total_revenue': 0,
      'gross_sales': 0,
      'refunded_amount': 0,
      'total_service_charge': 0,
      'service_charge_waived_count': 0,
      'service_charge_waived_amount': 0,
      'total_delivery_fees': 0,
      'total_line_items': 0,
      'revenue_by_method': <String, Object?>{},
      'total_tips': 0,
      'cash_tips': 0,
      'top_items': const <Object?>[],
      'by_service_mode': const <Object?>[],
      'by_category': [
        {
          'category_id': 'c',
          'category_name': 'Coffee',
          'category_name_translations': <String, Object?>{},
          'item_count': 3,
          'quantity_sold': 10,
          'revenue': 10000,
          'items': [
            sold('latte', 'Latte', 3, 500),
            sold('latte', 'Caffe latte', 1, 100),
            sold('mocha', 'Mocha', 2, null),
            sold('tea', 'Tea', 4, 0),
          ],
        },
      ],
    });
    CombinedItemSalesRow unit(String id) => CombinedItemSalesRow.fromJson({
      'item_id': id,
      'item_name': id,
      'item_name_translations': <String, Object?>{},
      'standalone_qty': 1,
      'total_qty': 1,
    });
    final rows = {
      for (final r in opsItemRows(
        items: [unit('latte'), unit('mocha'), unit('tea'), unit('scone')],
        sales: sales,
        menu: [
          menuItem('latte', 5500, [(7500, true), (5500, true), (9900, false)]),
          menuItem('tea', 3000, []),
          menuItem('mocha', 6000, [(6000, true)]),
        ],
        lang: 'en',
      ))
        r.id: r,
    };
    // 600 piastres over 4 units = 150.
    expect(rows['latte']!.avgExtra, 150);
    expect((rows['latte']!.priceMin, rows['latte']!.priceMax), (5500, 7500));
    expect(rows['mocha']!.avgExtra, isNull);
    expect((rows['mocha']!.priceMin, rows['mocha']!.priceMax), (6000, 6000));
    expect(rows['tea']!.avgExtra, 0);
    expect((rows['tea']!.priceMin, rows['tea']!.priceMax), (3000, 3000));
    expect(rows['scone']!.avgExtra, isNull);
    expect(rows['scone']!.priceMin, isNull);
    // Rounded half away from zero, like the server.
    expect(opsRoundedDiv(5, 2), 3);
    expect(opsRoundedDiv(1000, 3), 333);
    expect(opsRoundedDiv(2000, 3), 667);
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

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.desktop, 'ar'),
    (DashSize.phone, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    testWidgets('price and avg extra (${size.name} $lang): the headers in the '
        'reader\'s language, a range for several sizes, money figures', (
      tester,
    ) async {
      final h = await _items(tester, size: size, locale: lang);
      final heads = lang == 'ar'
          ? ['السعر', 'متوسط الإضافات']
          : ['Price', 'Avg extra'];
      final columns = _widget(tester).columns;
      expect([for (final c in columns.skip(3)) c.label], heads);
      for (final id in ['price', 'avg_extra']) {
        expect(_header(id), findsOneWidget);
      }
      final f = h.container.read(formatProvider);
      final ranged = _widget(
        tester,
      ).rows.firstWhere((r) => r.priceMin != r.priceMax);
      expect(
        find.descendant(
          of: _table,
          matching: find.text(
            dashFigure(opsPriceRangeText(f, ranged.priceMin, ranged.priceMax)),
          ),
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await h.shot('operations/items-price-extra');
      if (size == DashSize.phone) {
        // The figures scrolled to their end: the two new columns in view.
        final scroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.descendant(
              of: _table,
              matching: find.byKey(const ValueKey('ops-rank-figures')),
            ),
            matching: find.byType(Scrollable),
          ),
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await h.settle();
        await h.shot('operations/items-price-extra-scrolled');
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
