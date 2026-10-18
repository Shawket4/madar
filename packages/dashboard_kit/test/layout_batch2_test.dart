// Kit batch 2, figures and layout: a whole-figure Text in a FittedBox,
// concise figures at the web's md, the table's page reset, tab glyphs, the
// ledger stagger, the section header's trailing control, DashSurface slots,
// the page fade and gutter, the skeleton's width, the progress track.
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Row {
  const _Row(this.id, this.name);
  final String id;
  final String name;
}

final _rows = [for (var i = 0; i < 25; i++) _Row('r$i', 'Row $i')];

void _window(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900) * DashSize.pixelRatio;
}

/// The opacity [of] is drawn at: every [Opacity] and [FadeTransition] over
/// it (an entrance fades with the latter).
double _opacity(WidgetTester tester, Finder of) =>
    tester
        .widgetList<Opacity>(
          find.ancestor(of: of, matching: find.byType(Opacity)),
        )
        .fold(1.0, (o, w) => o * w.opacity) *
    tester
        .widgetList<FadeTransition>(
          find.ancestor(of: of, matching: find.byType(FadeTransition)),
        )
        .fold(1.0, (o, w) => o * w.opacity.value);

void main() {
  // Real faces: whether a figure or label is cut depends on its real width.
  setUpAll(loadDashFonts);

  group('figures', () {
    testWidgets('Arabic: a whole-figure Text in a FittedBox keeps its last '
        'digit with dashFigureDirection', (tester) async {
      for (final s in ['32', '128', '1,284']) {
        await pumpDashApp(
          tester,
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    s,
                    maxLines: 1,
                    textDirection: dashFigureDirection(s),
                    style: DashType.statFigure(18),
                  ),
                ),
              ),
            ),
          ),
          lang: 'ar',
        );
        final p = tester.renderObject<RenderParagraph>(find.text(s));
        expect(p.didExceedMaxLines, isFalse, reason: '"$s" shown whole');
      }
      expect(dashFigureDirection('−50.00'), TextDirection.ltr);
      expect(dashFigureDirection('1,234.50 ج.م'), isNull);
    });

    testWidgets('concise figures switch at 768 (the web md), not 760', (
      tester,
    ) async {
      const value = DashConciseValue(full: 'EGP 12,345.00', compact: '12.3K');
      await pumpDashApp(tester, const Scaffold(body: Center(child: value)));
      _window(tester, 765);
      await tester.pump();
      expect(find.text('12.3K'), findsOneWidget);
      _window(tester, 770);
      await tester.pump();
      expect(find.text('EGP 12,345.00'), findsOneWidget);
      expect(find.text('12.3K'), findsNothing);
    });
  });

  group('DashDataTable', () {
    Widget table(List<_Row> rows) => Scaffold(
      body: SingleChildScrollView(
        child: DashDataTable<_Row>(
          columns: [
            DashColumn<_Row>(id: 'name', label: 'Name', text: (r) => r.name),
          ],
          rows: rows,
          rowKey: (r) => r.id,
          searchPlaceholder: 'Search rows',
        ),
      ),
    );

    testWidgets('other rows (a filter) go back to page 1; the same rows '
        'refreshed keep the page', (tester) async {
      var rows = _rows;
      late StateSetter set;
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, s) {
            set = s;
            return table(rows);
          },
        ),
      );
      await tester.tap(find.bySemanticsLabel('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 3'), findsOneWidget);

      // A refetch: a new list, the same rows.
      set(() => rows = [..._rows]);
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 3'), findsOneWidget);

      // A filter: other rows.
      set(() => rows = _rows.where((r) => r.id != 'r3').toList());
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(find.text('Row 0'), findsOneWidget);
    });

    testWidgets('the search is trimmed and Escape clears it', (tester) async {
      await pumpDashApp(tester, table(_rows));
      await tester.enterText(find.byType(EditableText), '  Row 12  ');
      await tester.pumpAndSettle();
      expect(find.text('Row 12'), findsOneWidget);
      expect(find.text('Row 0'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Row 0'), findsOneWidget);
    });
  });

  testWidgets('a DashTab glyph sits before its label, in its colour', (
    tester,
  ) async {
    var picked = 'orders';
    await pumpDashApp(
      tester,
      Scaffold(
        body: DashTabStrip<String>(
          tabs: const [
            DashTab(value: 'orders', label: 'Purchase orders', icon: 'truck'),
            DashTab(value: 'suppliers', label: 'Suppliers', icon: 'users'),
          ],
          value: picked,
          onChanged: (v) => picked = v,
        ),
      ),
    );
    final glyph = find.byWidgetPredicate(
      (w) => w is DashIcon && w.name == 'users',
    );
    expect(glyph, findsOneWidget);
    expect(tester.widget<DashIcon>(glyph).size, 16);
    expect(
      tester.getCenter(glyph).dx,
      lessThan(tester.getCenter(find.text('Suppliers')).dx),
    );
    expect(
      tester.widget<DashIcon>(glyph).color,
      tester.widget<Text>(find.text('Suppliers')).style!.color,
    );
    await tester.tap(find.bySemanticsLabel('Suppliers'));
    expect(picked, 'suppliers');
  });

  group('DashLedgerStrip', () {
    List<DashLedgerItem> items({Widget? action, String lang = 'en'}) => [
      DashLedgerItem(
        key: 'a',
        label: lang == 'ar' ? 'الإيرادات' : 'Revenue',
        value: 4528,
      ),
      DashLedgerItem(
        key: 'b',
        label: lang == 'ar' ? 'الأصناف المباعة' : 'Items sold',
        icon: 'shopping-basket',
        value: 1284,
        action: action,
      ),
      DashLedgerItem(
        key: 'c',
        label: lang == 'ar' ? 'الضريبة' : 'Tax',
        value: 63,
      ),
      DashLedgerItem(
        key: 'd',
        label: lang == 'ar' ? 'الملغاة' : 'Voided',
        value: 3,
      ),
      // Five, as on Orders: dense, the web's p-4.
      DashLedgerItem(
        key: 'e',
        label: lang == 'ar' ? 'الخصومات' : 'Discounts',
        value: 12,
      ),
    ];

    testWidgets('the cards fade in 50 ms apart; at once under reduced '
        'motion', (tester) async {
      await pumpDashApp(
        tester,
        Scaffold(body: DashLedgerStrip(items: items())),
      );
      double card(String k) => _opacity(tester, find.byKey(ValueKey(k)));
      expect(card('a'), 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(card('a'), greaterThan(0));
      expect(card('c'), 0, reason: 'starts at 100 ms');
      expect(card('d'), 0, reason: 'starts at 150 ms');
      await tester.pump(const Duration(milliseconds: 100));
      expect(card('d'), greaterThan(0));
      await tester.pumpAndSettle();
      expect(
        [
          for (final k in ['a', 'b', 'c', 'd']) card(k),
        ],
        [1, 1, 1, 1],
      );
      expect(find.bySemanticsLabel('Revenue'), findsOneWidget);

      await pumpDashApp(
        tester,
        Scaffold(body: DashLedgerStrip(items: items())),
        reducedMotion: true,
      );
      expect(card('d'), 1);
    });

    testWidgets('Arabic phone: a 44 pt action keeps the cards one height and '
        'the label whole', (tester) async {
      await pumpDashApp(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: DashLedgerStrip(
              items: items(
                lang: 'ar',
                action: DashIconButton(
                  icon: 'list-filter',
                  semanticLabel: 'استبعاد أصناف',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
        size: DashSize.phone,
        lang: 'ar',
      );
      await tester.pumpAndSettle();
      final a = tester.getRect(find.byKey(const ValueKey('a')));
      final b = tester.getRect(find.byKey(const ValueKey('b')));
      expect(b.top, a.top, reason: 'two across');
      expect(b.height, a.height);
      final label = tester.renderObject<RenderParagraph>(
        find.text('الأصناف المباعة'),
      );
      expect(label.didExceedMaxLines, isFalse);
      expect(
        tester.getSize(find.byType(DashIconButton)),
        const Size.square(DashMetrics.target),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('DashSectionHeader centres a 44 pt trailing control on the '
      'title line', (tester) async {
    await pumpDashApp(
      tester,
      Scaffold(
        body: DashSectionHeader(
          title: 'Recent orders',
          trailing: DashIconButton(
            icon: 'refresh-cw',
            semanticLabel: 'Refresh',
            onPressed: () {},
          ),
        ),
      ),
    );
    final button = tester.getRect(find.byType(DashIconButton));
    expect(button.height, DashMetrics.target);
    expect(
      tester.getCenter(find.text('Recent orders')).dy,
      moreOrLessEquals(button.center.dy, epsilon: 0.5),
    );
  });

  group('DashSurface', () {
    Widget surface({
      DashSurfaceMode mode = DashSurfaceMode.dialog,
      bool wrapActions = false,
    }) => Scaffold(
      body: DashSurfaceScope(
        mode: mode,
        child: DashSurface(
          title: 'Milk',
          titleTrailing: const DashBadge('Dairy'),
          body: const Text('body'),
          footerLeading: DashButton(
            label: 'Download again',
            variant: DashButtonVariant.outline,
            onPressed: () {},
          ),
          wrapActions: wrapActions,
          actions: [
            DashButton(
              label: 'Edit',
              variant: DashButtonVariant.outline,
              onPressed: () {},
            ),
            DashButton(label: 'Done', onPressed: () {}),
          ],
        ),
      ),
    );

    testWidgets('a title-trailing badge on the title line; the footer '
        'leading at the start, the actions at the end', (tester) async {
      await pumpDashApp(tester, surface());
      final title = tester.getRect(find.text('Milk'));
      final badge = tester.getRect(find.byType(DashBadge));
      expect(badge.left, greaterThan(title.right));
      expect(badge.center.dy, moreOrLessEquals(title.center.dy, epsilon: 1));
      final lead = tester.getRect(find.text('Download again'));
      final done = tester.getRect(find.text('Done'));
      expect(lead.center.dy, moreOrLessEquals(done.center.dy, epsilon: 1));
      expect(lead.left, lessThan(100), reason: 'at the start');
      expect(done.right, greaterThan(1300), reason: 'at the end');
    });

    testWidgets('phone: stacked actions with the leading under them, or one '
        'wrapping row with wrapActions', (tester) async {
      await pumpDashApp(
        tester,
        surface(mode: DashSurfaceMode.fullScreen),
        size: DashSize.phone,
      );
      double top(String s) => tester.getRect(find.text(s)).top;
      expect(top('Done'), lessThan(top('Edit')), reason: 'primary on top');
      expect(top('Download again'), greaterThan(top('Edit')));

      await pumpDashApp(
        tester,
        surface(mode: DashSurfaceMode.fullScreen, wrapActions: true),
        size: DashSize.phone,
      );
      expect(top('Done'), top('Edit'), reason: 'one row');
      expect(tester.takeException(), isNull);
    });
  });

  group('DashPageScaffold', () {
    Widget page() =>
        const DashPageScaffold(title: 'Purchasing', body: Text('page body'));

    testWidgets('fades in (its words read from the first frame); at once '
        'under reduced motion', (tester) async {
      await pumpDashApp(tester, Scaffold(body: page()));
      expect(_opacity(tester, find.text('page body')), lessThan(1));
      expect(find.bySemanticsLabel('Purchasing'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(_opacity(tester, find.text('page body')), 1);

      await pumpDashApp(tester, Scaffold(body: page()), reducedMotion: true);
      expect(_opacity(tester, find.text('page body')), 1);
    });

    testWidgets('the gutter follows the window: 32 from 1024, 24 below, '
        'whatever the pane', (tester) async {
      // A 768 pane beside a sidebar.
      Widget framed() => Scaffold(
        body: Row(
          children: [
            const SizedBox(width: 256),
            Expanded(child: page()),
          ],
        ),
      );
      await pumpDashApp(tester, framed(), size: DashSize.tablet);
      expect(tester.getRect(find.text('page body')).left, 256 + 32);
      _window(tester, 900);
      await tester.pump();
      expect(tester.getRect(find.text('page body')).left, 256 + 24);
    });

    testWidgets('a page that fills the body keeps its panels\' scrolls: the '
        'shell reads only a page that scrolls', (tester) async {
      final heard = <Notification>[];
      Widget shell(bool fill) => Scaffold(
        body: NotificationListener<Notification>(
          onNotification: (n) {
            if (n is ScrollNotification || n is ScrollMetricsNotification) {
              heard.add(n);
            }
            return false;
          },
          child: DashPageScaffold(
            title: 'Branch setup',
            fillBody: fill,
            body: fill
                ? const SingleChildScrollView(
                    child: SizedBox(height: 4000, child: Text('panel')),
                  )
                : const SizedBox(height: 4000, child: Text('page body')),
          ),
        ),
      );
      await pumpDashApp(tester, shell(true));
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(heard, isEmpty);

      await pumpDashApp(tester, shell(false));
      heard.clear();
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(heard, isNotEmpty);
    });
  });

  testWidgets('a DashSkeleton with no width fills its column; none in a '
      'row', (tester) async {
    await pumpDashApp(
      tester,
      const Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DashSkeleton(key: ValueKey('fill')),
                Row(children: [DashSkeleton(key: ValueKey('row'))]),
                DashSkeleton(key: ValueKey('fixed'), width: 80),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const ValueKey('fill'))).width, 300);
    expect(tester.getSize(find.byKey(const ValueKey('row'))).width, 0);
    expect(tester.getSize(find.byKey(const ValueKey('fixed'))).width, 80);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DashProgressBar: the web h-1.5 track, h-2 where asked', (
    tester,
  ) async {
    await pumpDashApp(
      tester,
      const Scaffold(
        body: Column(
          children: [
            DashProgressBar(
              key: ValueKey('six'),
              value: 40,
              semanticLabel: 'Cups',
            ),
            DashProgressBar(
              key: ValueKey('eight'),
              value: 40,
              semanticLabel: 'Lids',
              height: 8,
            ),
          ],
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const ValueKey('six'))).height, 6);
    expect(tester.getSize(find.byKey(const ValueKey('eight'))).height, 8);
  });

  test('28 a summary of several names reads by its first strong letter', () {
    // The transfers Items cell: pass the joined summary to
    // dashTextDirectionOf, or give the column `text:` (which does).
    expect(dashTextDirectionOf('Milk, حليب, سكر'), TextDirection.ltr);
    expect(dashTextDirectionOf('حليب، Milk'), TextDirection.rtl);
    expect(dashTextDirectionOf('7Up · 2 كجم'), TextDirection.ltr);
    expect(dashTextDirectionOf('— · 2'), isNull);
  });
}
