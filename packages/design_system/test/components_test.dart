// Behaviour and geometry of the spec components: the page header's fixed
// title rect, MadarDataTable's required states, its phone collapse and its
// right-to-left layout, and the list rows. docs/design/SPEC.md §2, §7, §8.

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _ipadLandscape = Size(1194, 834);
const Size _ipadPortrait = Size(834, 1194);
const Size _desktop = Size(1440, 900);
const Size _phone = Size(390, 844);

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _app(Widget home, {TextDirection dir = TextDirection.ltr}) =>
    MaterialApp(
      theme: MadarTheme.light(),
      home: Directionality(textDirection: dir, child: home),
    );

/// A page on the spec grid, optionally pushed over a root page so it can pop.
Widget _page({
  required bool pushed,
  String? subtitle,
  List<Widget> actions = const [],
  MadarContentWidth width = MadarContentWidth.full,
}) {
  Widget page(BuildContext _) => MadarPageScaffold(
    title: 'Past shifts',
    subtitle: subtitle,
    width: width,
    actions: actions,
    body: const SizedBox.expand(),
  );
  return Navigator(
    onGenerateInitialRoutes: (_, _) => [
      MaterialPageRoute<void>(builder: (_) => const SizedBox.expand()),
      if (pushed) MaterialPageRoute<void>(builder: page),
    ],
    onGenerateRoute: (_) => MaterialPageRoute<void>(builder: page),
  )._orRoot(pushed, page);
}

extension on Navigator {
  Widget _orRoot(bool pushed, WidgetBuilder page) =>
      pushed ? this : Builder(builder: page);
}

class _Row {
  const _Row(this.ref, this.time, this.type, this.total, this.status);
  final String ref;
  final String time;
  final String type;
  final int total;
  final MadarStatus status;
}

const _rows = [
  _Row(
    '1042',
    '18:02',
    'Dine-in',
    19000,
    MadarStatus('Paid', tone: MadarTone.success),
  ),
  _Row(
    '1041',
    '17:48',
    'Takeaway',
    -5000,
    MadarStatus('Refunded', tone: MadarTone.danger),
  ),
  _Row(
    '1040',
    '17:30',
    'Delivery',
    123450,
    MadarStatus('Paid', tone: MadarTone.success),
  ),
];

final _columns = <MadarColumn<_Row>>[
  MadarColumn(
    id: 'ref',
    label: '#',
    text: (r) => r.ref,
    width: 72,
    mono: true,
    emphasis: true,
  ),
  MadarColumn(
    id: 'time',
    label: 'Time',
    text: (r) => r.time,
    width: 72,
    mono: true,
  ),
  MadarColumn(
    id: 'type',
    label: 'Type',
    text: (r) => r.type,
    flex: 2,
    priority: 2,
  ),
  MadarColumn.money(
    id: 'total',
    label: 'Total',
    minor: (r) => r.total,
    currency: 'EGP',
    width: 140,
  ),
  MadarColumn.status(
    id: 'status',
    label: 'Status',
    status: (r) => r.status,
    width: 130,
    priority: 1,
  ),
];

const _empty = MadarEmptyContent(title: 'No orders yet');

Widget _table(
  MadarTableState<_Row> state, {
  ValueChanged<_Row>? onTap,
  bool? collapse,
  Widget? Function(BuildContext, _Row)? expanded,
}) => Padding(
  padding: const EdgeInsets.all(24),
  child: MadarDataTable<_Row>(
    columns: _columns,
    state: state,
    rowKey: (r) => r.ref,
    empty: _empty,
    onTap: onTap,
    collapse: collapse,
    expandedBuilder: expanded,
    loadMoreLabel: 'Load more',
    rail: (r) => r.status.tone,
  ),
);

void main() {
  group('header geometry', () {
    for (final (name, size) in [
      ('iPad landscape', _ipadLandscape),
      ('iPad portrait', _ipadPortrait),
      ('desktop', _desktop),
      ('phone', _phone),
    ]) {
      testWidgets('title rect is identical with/without subtitle and back — '
          '$name', (tester) async {
        _size(tester, size);
        Future<Rect> titleRect(Widget w) async {
          await tester.pumpWidget(_app(w));
          await tester.pumpAndSettle();
          return tester.getRect(find.byKey(MadarHeader.titleKey));
        }

        final bare = await titleRect(_page(pushed: false));
        final withSubtitle = await titleRect(
          _page(pushed: false, subtitle: 'Rue Zamalek · 12 shifts'),
        );
        final pushed = await titleRect(_page(pushed: true));
        final pushedSubtitle = await titleRect(
          _page(pushed: true, subtitle: 'Rue Zamalek · 12 shifts'),
        );
        final withActions = await titleRect(
          _page(
            pushed: true,
            actions: [
              MadarHeaderAction(glyph: MadarGlyph.printer, onTap: () {}),
            ],
          ),
        );
        final reading = await titleRect(
          _page(pushed: false, width: MadarContentWidth.reading),
        );
        const back = Offset(MadarHeaderMetrics.titleInset, 0);
        expect(withSubtitle.topLeft, bare.topLeft);
        expect(pushed.topLeft, bare.topLeft + back);
        expect(pushedSubtitle.topLeft, pushed.topLeft);
        expect(withActions.topLeft, pushed.topLeft);
        expect(reading.topLeft, bare.topLeft);
        expect(pushed.height, bare.height);
        // A tab page's title sits on the gutter — no page-title icon, no
        // empty slot; a pushed page's back tile takes the 56 before it.
        final gutter = MadarLayout.fromSize(size).gutter;
        expect(bare.left, gutter);
      });
    }

    testWidgets('RTL mirrors the title onto the right gutter', (tester) async {
      _size(tester, _ipadLandscape);
      await tester.pumpWidget(
        _app(_page(pushed: true), dir: TextDirection.rtl),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(MadarHeader.titleKey));
      expect(
        rect.right,
        _ipadLandscape.width - 24 - MadarHeaderMetrics.titleInset,
      );
    });

    testWidgets('legacy header still collapses the slot', (tester) async {
      _size(tester, _ipadLandscape);
      await tester.pumpWidget(_app(const MadarHeader(title: 'Till')));
      expect(tester.getRect(find.byKey(MadarHeader.titleKey)).left, 0);
    });

    testWidgets('content widths align to the leading edge', (tester) async {
      _size(tester, _ipadLandscape);
      const probe = Key('probe');
      await tester.pumpWidget(
        _app(
          const MadarPageScaffold(
            title: 'Cash in / out',
            width: MadarContentWidth.form,
            body: SizedBox.expand(key: probe),
          ),
        ),
      );
      final r = tester.getRect(find.byKey(probe));
      expect(r.left, 24);
      expect(r.width, MadarContentWidth.form.maxWidth);
    });
  });

  group('MadarDataTable', () {
    testWidgets('loading shows skeleton rows, not a spinner', (tester) async {
      _size(tester, _ipadLandscape);
      await tester.pumpWidget(
        _app(Scaffold(body: _table(const MadarTableState.loading(rows: 4)))),
      );
      await tester.pump();
      expect(find.byType(SkeletonBlock), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('TIME'), findsOneWidget, reason: 'header stands');
    });

    testWidgets('empty data shows the empty content', (tester) async {
      _size(tester, _ipadLandscape);
      await tester.pumpWidget(
        _app(Scaffold(body: _table(const MadarTableState.data([])))),
      );
      expect(find.text('No orders yet'), findsOneWidget);
    });

    testWidgets('error shows the error state and retries', (tester) async {
      _size(tester, _ipadLandscape);
      var retried = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: _table(
              MadarTableState.error(
                message: 'Could not load orders',
                retryLabel: 'Retry',
                onRetry: () => retried++,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Could not load orders'), findsOneWidget);
      expect(find.text('No orders yet'), findsNothing);
      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });

    testWidgets('data rows: header, cells, 64 rows, tap, load more', (
      tester,
    ) async {
      _size(tester, _ipadLandscape);
      _Row? tapped;
      var more = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: _table(
              MadarTableState.data(
                _rows,
                hasMore: true,
                onLoadMore: () => more++,
              ),
              onTap: (r) => tapped = r,
            ),
          ),
        ),
      );
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text('EGP 1,234.50'), findsOneWidget);
      expect(find.text('−EGP 50.00'), findsOneWidget);
      expect(find.text('Refunded'), findsOneWidget);
      final row = tester.getRect(
        find
            .ancestor(
              of: find.text('Takeaway'),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(row.height, MadarTableMetrics.rowHeight);
      await tester.tap(find.text('Takeaway'));
      expect(tapped?.ref, '1041');
      await tester.tap(find.text('Load more'));
      expect(more, 1);
    });

    testWidgets('header labels and cells share one grid', (tester) async {
      _size(tester, _ipadLandscape);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: _table(const MadarTableState.data(_rows), onTap: (_) {}),
          ),
        ),
      );
      final header = tester.getRect(find.text('TYPE'));
      final cell = tester.getRect(find.text('Dine-in'));
      expect(cell.left, header.left);
    });

    testWidgets('narrow tables hide the highest priority first', (
      tester,
    ) async {
      _size(tester, const Size(560, 800));
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: _table(const MadarTableState.data(_rows), collapse: false),
          ),
        ),
      );
      // 512 wide: type (priority 2) goes first, status (1) survives.
      expect(find.text('TYPE'), findsNothing);
      expect(find.text('STATUS'), findsOneWidget);
    });

    testWidgets('a phone collapses to two-line rows with no header', (
      tester,
    ) async {
      _size(tester, _phone);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: _table(const MadarTableState.data(_rows), onTap: (_) {}),
          ),
        ),
      );
      expect(find.text('TIME'), findsNothing);
      expect(find.byType(MadarListRow), findsNWidgets(3));
      expect(find.text('1042'), findsOneWidget, reason: 'title');
      expect(
        find.text('\u206618:02\u2069 · Dine-in'),
        findsOneWidget,
        reason: 'meta',
      );
      expect(find.text('EGP 190.00'), findsOneWidget, reason: 'value');
      expect(tester.takeException(), isNull);
    });

    testWidgets('rows expand to nested content', (tester) async {
      _size(tester, _ipadLandscape);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: _table(
              const MadarTableState.data(_rows),
              expanded: (_, r) => Text('nested ${r.ref}'),
            ),
          ),
        ),
      );
      expect(find.text('nested 1042'), findsNothing);
      await tester.tap(find.text('Dine-in'));
      await tester.pumpAndSettle();
      expect(find.text('nested 1042'), findsOneWidget);
      await tester.tap(find.text('Dine-in'));
      await tester.pumpAndSettle();
      expect(find.text('nested 1042'), findsNothing);
    });

    testWidgets('RTL: columns mirror, figures stay LTR', (tester) async {
      _size(tester, _ipadLandscape);
      await tester.pumpWidget(
        _app(
          Scaffold(body: _table(const MadarTableState.data(_rows))),
          dir: TextDirection.rtl,
        ),
      );
      final ref = tester.getRect(find.text('\u20661042\u2069'));
      final total = tester.getRect(find.text('EGP 190.00'));
      expect(
        ref.left,
        greaterThan(total.left),
        reason: 'first column on the right',
      );
      final refText = tester.widget<Text>(find.text('\u20661042\u2069'));
      expect(refText.data, startsWith(MadarFormat.lri));
      expect(tester.takeException(), isNull);
    });
  });

  group('list rows and pills', () {
    testWidgets('ledger signs money and never by colour alone', (tester) async {
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: Column(
              children: [
                MadarListRow.ledger(
                  title: 'Pay in',
                  minor: 2000,
                  currency: 'EGP',
                ),
                MadarListRow.ledger(
                  title: 'Pay out',
                  minor: -5000,
                  currency: 'EGP',
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('+EGP 20.00'), findsOneWidget);
      expect(find.text('−EGP 50.00'), findsOneWidget);
      final glyphs = tester
          .widgetList<MadarGlyphIcon>(find.byType(MadarGlyphIcon))
          .map((g) => g.glyph);
      expect(glyphs, containsAll([MadarGlyph.plus, MadarGlyph.minus]));
      expect(
        tester.getSize(find.byType(MadarListRow).first).height,
        Metrics.rowHeight,
      );
    });

    // D8 (FINAL device check): a declined request's reason sat in the one
    // meta line and was cut ("… · R…"); a bill may let its meta wrap.
    testWidgets("a bill's meta wraps to metaLines, one line by default", (
      tester,
    ) async {
      const long =
          'EGP 4,000.00 · next payslip · Reason: over the cap, not this month · '
          'my own note that is also rather long';
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: Column(
              children: [
                MadarListRow.bill(title: 'Salary advance', meta: long),
                MadarListRow.bill(
                  title: 'Salary advance',
                  meta: long,
                  metaLines: 3,
                ),
              ],
            ),
          ),
        ),
      );
      final metas = tester
          .widgetList<Text>(find.text(long))
          .map((t) => t.maxLines)
          .toList();
      expect(metas, [1, 3]);
    });

    testWidgets('a status pill always carries a glyph', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Center(
              child: MadarStatusPill.of('Short', tone: MadarTone.danger),
            ),
          ),
        ),
      );
      expect(find.byType(MadarGlyphIcon), findsOneWidget);
      expect(find.text('Short'), findsOneWidget);
    });

    test('size classes', () {
      expect(MadarSizeClass.fromSize(_phone), MadarSizeClass.phone);
      expect(
        MadarSizeClass.fromSize(_ipadLandscape),
        MadarSizeClass.tabletLandscape,
      );
      expect(
        MadarSizeClass.fromSize(_ipadPortrait),
        MadarSizeClass.tabletPortrait,
      );
      expect(
        MadarSizeClass.fromSize(_desktop, platform: TargetPlatform.macOS),
        MadarSizeClass.desktop,
      );
      expect(MadarSizeClass.phone.gutter, 16);
      expect(MadarSizeClass.desktop.gutter, 24);
    });

    test(
      'room: the small iPad is snug in height landscape, in width portrait',
      () {
        const ipad9 = Size(1080, 810);
        const ipad9Portrait = Size(810, 1080);
        const tab8 = Size(800, 1280);
        const phoneLandscape = Size(844, 390);

        // Every landscape iPad is height-snug: the footer of a stacked screen
        // takes its dense variant on the 13" too, not only on the 10.2".
        expect(MadarRoom.fromSize(_ipadLandscape).height, MadarSpan.snug);
        expect(MadarRoom.fromSize(_ipadLandscape).width, MadarSpan.roomy);
        expect(MadarRoom.fromSize(ipad9).height, MadarSpan.snug);
        expect(MadarRoom.fromSize(ipad9).width, MadarSpan.roomy);
        // Portrait: tall enough, but a 300 cart column, not 340.
        expect(MadarRoom.fromSize(ipad9Portrait).height, MadarSpan.roomy);
        expect(MadarRoom.fromSize(ipad9Portrait).width, MadarSpan.snug);
        expect(MadarRoom.fromSize(ipad9Portrait).cartColumnWidth, 300);
        expect(MadarRoom.fromSize(_ipadPortrait).cartColumnWidth, 300);
        expect(MadarRoom.fromSize(tab8).width, MadarSpan.snug);
        expect(MadarRoom.fromSize(ipad9).cartColumnWidth, 340);
        expect(
          MadarRoom.fromSize(_desktop),
          const MadarRoom(width: MadarSpan.roomy, height: MadarSpan.roomy),
        );
        // A phone is tight in width; sideways it is tight in height too.
        expect(MadarRoom.fromSize(_phone).width, MadarSpan.tight);
        expect(MadarRoom.fromSize(_phone).height, MadarSpan.snug);
        expect(MadarRoom.fromSize(phoneLandscape).height, MadarSpan.tight);
        expect(MadarSpan.tight.isDense, isTrue);
        expect(MadarSpan.snug.isDense, isTrue);
        expect(MadarSpan.roomy.isDense, isFalse);
      },
    );

    testWidgets('MadarKeyboardInset keeps its child above the keyboard', (
      tester,
    ) async {
      _size(tester, _ipadLandscape);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        _app(
          const MadarKeyboardInset(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(key: Key('bar'), width: 100, height: 56),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.byKey(const Key('bar'))).dy,
        lessThanOrEqualTo(834 - 320),
        reason: 'the bar sits above the keyboard, not under it',
      );
      // The child no longer sees the inset (it would otherwise pad twice).
      final inner = tester.element(find.byKey(const Key('bar')));
      expect(MediaQuery.viewInsetsOf(inner).bottom, 0);
    });
  });

  group('totals and empty pages', () {
    testWidgets('a summary line sets its figure in the app language', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              MadarSummaryLine(label: 'Total', minor: 123450, currency: 'EGP'),
              MadarSummaryLine(label: 'Paid out', minor: -9000, signed: true),
            ],
          ),
        ),
      );
      expect(find.text('EGP 1,234.50'), findsOneWidget);
      expect(find.text('\u221290.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty page that has more still offers Load more', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MadarDataTable<int>(
            columns: [MadarColumn(id: 'n', label: 'N', text: (i) => '$i')],
            state: MadarTableState.data(
              const [],
              hasMore: true,
              onLoadMore: () {},
            ),
            rowKey: (i) => i,
            empty: const MadarEmptyContent(title: 'Nothing matched'),
            loadMoreLabel: 'Load more',
            scrollable: false,
          ),
        ),
      );
      expect(find.text('Nothing matched'), findsOneWidget);
      expect(find.text('Load more'), findsOneWidget);
    });
  });
}
