// The spec component board — renders the page grid, MadarDataTable, the list
// rows, stat cards, pills and the three states so they can be LOOKED at.
//
//   flutter test test/components_render_test.dart --dart-define=MADAR_RENDER=true
//
// writes build/render/spec-<board>-<device>-<lang>-<theme>.png. Unset, every
// board still lays out and fails on any exception. Fixture text only; the
// app's words come through the core's i18n.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

const Size _ipad = Size(1194, 834);
const Size _phone = Size(390, 844);
const Size _desktop = Size(1440, 900);

// ── Fixture copy ──────────────────────────────────────────────────────────

class _L {
  const _L({required this.ar});
  final bool ar;
  String get locale => ar ? 'ar' : 'en';
  String s(String en, String arabic) => ar ? arabic : en;

  String get orders => s('Orders', 'الطلبات');
  String get pastShifts => s('Past shifts', 'الورديات السابقة');
  String get branch => s('Rue Zamalek', 'شارع الزمالك');
  String get search => s('Search by order number', 'ابحث برقم الطلب');
  String get thisShift => s('This shift', 'هذه الوردية');
  String get all => s('All', 'الكل');
  String get loadMore => s('Load more', 'تحميل المزيد');
}

class _Order {
  const _Order(this.ref, this.at, this.type, this.pay, this.total, this.st);
  final String ref;
  final DateTime at;
  final int type;
  final int pay;
  final int total;
  final int st;
}

final _now = DateTime(2026, 9, 13, 19, 40);

final _orders = [
  _Order('1042', DateTime(2026, 9, 13, 18, 2), 0, 0, 19000, 0),
  _Order('1041', DateTime(2026, 9, 13, 17, 48), 1, 1, 42850, 0),
  _Order('1040', DateTime(2026, 9, 13, 17, 30), 2, 2, 123450, 1),
  _Order('1039', DateTime(2026, 9, 13, 16, 55), 0, 0, -5000, 2),
  _Order('1038', DateTime(2026, 9, 12, 23, 10), 0, 1, 8600, 0),
  _Order('1037', DateTime(2026, 9, 12, 22, 41), 1, 0, 31200, 0),
  _Order('1036', DateTime(2026, 9, 12, 21, 5), 2, 2, 256000, 3),
  _Order('1035', DateTime(2026, 9, 12, 20, 18), 0, 0, 14500, 0),
  _Order('1034', DateTime(2026, 9, 12, 19, 52), 1, 1, 9900, 0),
  _Order('1033', DateTime(2026, 9, 12, 19, 7), 0, 0, 61000, 0),
];

String _type(_L l, int t) => [
  l.s('Dine-in', 'في المطعم'),
  l.s('Takeaway', 'تيك أواي'),
  l.s('Delivery', 'توصيل'),
][t];

String _pay(_L l, int p) =>
    [l.s('Cash', 'نقدي'), l.s('Card', 'بطاقة'), l.s('Wallet', 'محفظة')][p];

MadarStatus _status(_L l, int s) => [
  MadarStatus(l.s('Paid', 'مدفوع'), tone: MadarTone.success),
  MadarStatus(l.s('Partly refunded', 'مسترد جزئيًا'), tone: MadarTone.warning),
  MadarStatus(l.s('Refunded', 'مسترد'), tone: MadarTone.danger),
  MadarStatus(l.s('Voided', 'ملغي'), glyph: MadarGlyph.close),
][s];

List<MadarColumn<_Order>> _orderColumns(_L l, {bool nested = false}) => [
  MadarColumn(
    id: 'ref',
    label: '#',
    text: (o) => o.ref,
    width: 64,
    mono: true,
    emphasis: true,
  ),
  MadarColumn(
    id: 'time',
    label: l.s('Time', 'الوقت'),
    text: (o) => MadarFormat.stamp(o.at, _now, locale: l.locale),
    flex: 2,
    mono: true,
    muted: true,
  ),
  MadarColumn(
    id: 'type',
    label: l.s('Type', 'النوع'),
    text: (o) => _type(l, o.type),
    flex: 2,
    priority: 2,
  ),
  MadarColumn(
    id: 'pay',
    label: l.s('Payment', 'الدفع'),
    text: (o) => _pay(l, o.pay),
    flex: 2,
    priority: 3,
  ),
  MadarColumn.money(
    id: 'total',
    label: l.s('Total', 'الإجمالي'),
    minor: (o) => o.total,
    currency: 'EGP',
    width: 150,
  ),
  if (!nested)
    MadarColumn.status(
      id: 'status',
      label: l.s('Status', 'الحالة'),
      status: (o) => _status(l, o.st),
      width: 168,
      priority: 1,
    ),
];

class _Shift {
  const _Shift(this.teller, this.open, this.close, this.declared, this.delta);
  final String teller;
  final DateTime open;
  final DateTime? close;
  final int declared;
  final int delta;
}

final _shifts = [
  _Shift('Sara', DateTime(2026, 9, 13, 9), null, 0, 0),
  _Shift(
    'Omar',
    DateTime(2026, 9, 12, 16),
    DateTime(2026, 9, 13, 0, 22),
    623000,
    -2380,
  ),
  _Shift(
    'Sara',
    DateTime(2026, 9, 12, 9),
    DateTime(2026, 9, 12, 16, 4),
    418500,
    0,
  ),
  _Shift(
    'Mona',
    DateTime(2026, 9, 11, 16),
    DateTime(2026, 9, 11, 23, 58),
    702250,
    1500,
  ),
  _Shift(
    'Omar',
    DateTime(2025, 12, 31, 16),
    DateTime(2026, 1, 1, 0, 30),
    911000,
    0,
  ),
];

MadarStatus _shiftStatus(_L l, _Shift s) => s.close == null
    ? MadarStatus(l.s('Open', 'مفتوحة'), tone: MadarTone.accent)
    : s.delta < 0
    ? MadarStatus(l.s('Short', 'عجز'), tone: MadarTone.danger)
    : s.delta > 0
    ? MadarStatus(l.s('Over', 'زيادة'), tone: MadarTone.warning)
    : MadarStatus(l.s('Balanced', 'مطابقة'), tone: MadarTone.success);

// ── Pages ────────────────────────────────────────────────────────────────

Widget _ordersPage(_L l, {required MadarTableState<_Order> state}) {
  return Builder(
    builder: (context) {
      final layout = MadarLayout.of(context);
      return MadarPageScaffold(
        title: l.orders,
        subtitle:
            '${l.thisShift} · ${MadarFormat.ltr('42')} ${l.s('sales', 'مبيعات')} · '
            '${Money.format(623000, currency: 'EGP', locale: l.locale)}',
        width: MadarContentWidth.full,
        glyph: MadarGlyph.receipt,
        actions: [MadarHeaderAction(glyph: MadarGlyph.refresh, onTap: () {})],
        below: Row(
          spacing: Space.md,
          children: [
            Expanded(
              child: MadarField(
                controller: TextEditingController(),
                placeholder: l.search,
                glyph: MadarGlyph.search,
              ),
            ),
            if (layout.isTablet)
              SizedBox(
                width: 280,
                child: MadarSegmented<int>(
                  items: [
                    MadarSegmentItem(0, l.thisShift),
                    MadarSegmentItem(1, l.all),
                  ],
                  value: 0,
                  onChanged: (_) {},
                ),
              ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
          child: MadarDataTable<_Order>(
            columns: _orderColumns(l),
            state: state,
            rowKey: (o) => o.ref,
            empty: MadarEmptyContent(
              title: l.s('No orders this shift', 'لا طلبات في هذه الوردية'),
              message: l.s(
                'Sales you ring up appear here.',
                'تظهر هنا المبيعات التي تسجلها.',
              ),
            ),
            rail: (o) => _status(l, o.st).tone == MadarTone.success
                ? null
                : _status(l, o.st).tone,
            selected: (o) => o.ref == '1041',
            onTap: (_) {},
            loadMoreLabel: l.loadMore,
          ),
        ),
      );
    },
  );
}

Widget _shiftsPage(_L l) {
  Widget page(BuildContext context) => MadarPageScaffold(
    title: l.pastShifts,
    subtitle: l.branch,
    width: MadarContentWidth.reading,
    actions: [MadarHeaderAction(glyph: MadarGlyph.calendar, onTap: () {})],
    body: SingleChildScrollView(
      padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
      child: MadarDataTable<_Shift>(
        scrollable: false,
        columns: [
          MadarColumn(
            id: 'teller',
            label: l.s('Teller', 'الكاشير'),
            text: (s) => l.s(
              s.teller,
              {'Sara': 'سارة', 'Omar': 'عمر', 'Mona': 'منى'}[s.teller]!,
            ),
            flex: 2,
            emphasis: true,
          ),
          MadarColumn(
            id: 'open',
            label: l.s('Opened', 'الفتح'),
            text: (s) => MadarFormat.stamp(s.open, _now, locale: l.locale),
            flex: 4,
            mono: true,
            muted: true,
          ),
          MadarColumn(
            id: 'dur',
            label: l.s('Length', 'المدة'),
            text: (s) => MadarFormat.elapsed(
              (s.close ?? _now).difference(s.open),
              locale: l.locale,
            ),
            width: 96,
            mono: true,
            priority: 2,
          ),
          MadarColumn.money(
            id: 'declared',
            label: l.s('Declared', 'المُعلن'),
            minor: (s) => s.declared,
            currency: 'EGP',
            width: 136,
            priority: 3,
          ),
          MadarColumn.status(
            id: 'status',
            label: l.s('Status', 'الحالة'),
            status: (s) => _shiftStatus(l, s),
            width: 120,
          ),
        ],
        state: MadarTableState.data(_shifts, hasMore: true, onLoadMore: () {}),
        rowKey: (s) => s.open,
        empty: MadarEmptyContent(title: l.s('No shifts', 'لا ورديات')),
        rail: (s) => s.delta < 0 ? MadarTone.danger : null,
        trailing: (context, s) => s.close == null
            ? null
            : MadarGlyphTile(glyph: MadarGlyph.printer, onTap: () {}),
        expandedBuilder: (context, s) => s.teller == 'Omar' && s.delta < 0
            ? MadarDataTable<_Order>(
                framed: false,
                scrollable: false,
                columns: _orderColumns(l, nested: true),
                state: MadarTableState.data(_orders.sublist(4, 7)),
                rowKey: (o) => o.ref,
                empty: MadarEmptyContent(title: l.s('No orders', 'لا طلبات')),
              )
            : null,
        loadMoreLabel: l.loadMore,
      ),
    ),
  );
  return Navigator(
    onGenerateInitialRoutes: (_, _) => [
      MaterialPageRoute<void>(builder: (_) => const SizedBox.expand()),
      MaterialPageRoute<void>(builder: page),
    ],
  );
}

Widget _kit(_L l) {
  return Builder(
    builder: (context) {
      final colors = context.madarColors;
      final phone = MadarLayout.of(context).isPhone;
      Widget section(String label, Widget child, {Widget? trailing}) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MadarSectionHeader(text: label, trailing: trailing),
            const SizedBox(height: Space.md),
            child,
          ],
        ),
      );
      final stats = [
        MadarStatCard(
          label: l.s('Sales', 'المبيعات'),
          minor: 623000,
          currency: 'EGP',
          glyph: MadarGlyph.banknote,
          meta: l.s('42 orders', 'عدد الطلبات: 42'),
        ),
        MadarStatCard(
          label: l.s('Cash expected', 'النقد المتوقع'),
          minor: 418550,
          currency: 'EGP',
          glyph: MadarGlyph.wallet,
          meta: l.s(
            'Opening 500.00 + cash sales',
            'الافتتاح + المبيعات النقدية',
          ),
        ),
        MadarStatCard(
          label: l.s('Difference', 'الفرق'),
          minor: -2380,
          currency: 'EGP',
          tone: MadarTone.danger,
          status: MadarStatus(l.s('Short', 'عجز'), tone: MadarTone.danger),
        ),
        MadarStatCard(
          label: l.s('Open for', 'مفتوحة منذ'),
          value: MadarFormat.elapsed(
            const Duration(hours: 10, minutes: 40),
            locale: l.locale,
          ),
          glyph: MadarGlyph.clock,
          meta: l.s('Since 09:00', 'منذ 09:00'),
        ),
      ];
      return ColoredBox(
        color: colors.bg,
        child: SingleChildScrollView(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: MadarLayout.of(context).gutter,
            vertical: Space.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              section(
                l.s('Stat cards', 'بطاقات الأرقام'),
                phone
                    ? Column(
                        spacing: Space.md,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: stats,
                      )
                    : Row(
                        spacing: Space.lg,
                        children: [for (final s in stats) Expanded(child: s)],
                      ),
              ),
              section(
                l.s('List rows', 'الصفوف'),
                MadarCard.column(
                  flush: true,
                  children: [
                    MadarListRow.nav(
                      title: l.s('Printer', 'الطابعة'),
                      meta: l.s(
                        'Epson TM-m30 · Bluetooth',
                        'Epson TM-m30 · بلوتوث',
                      ),
                      glyph: MadarGlyph.printer,
                      valueText: l.s('Connected', 'متصلة'),
                      onTap: () {},
                    ),
                    const MadarHairline.row(),
                    MadarListRow.ledger(
                      title: l.s('Pay in · Change float', 'إيداع · فكة'),
                      meta: l.s('Sara · 14:20', 'سارة · 14:20'),
                      minor: 50000,
                      currency: 'EGP',
                    ),
                    const MadarHairline.row(),
                    MadarListRow.ledger(
                      title: l.s('Pay out · Supplier', 'صرف · مورد'),
                      meta: l.s('Omar · 16:02', 'عمر · 16:02'),
                      minor: -125075,
                      currency: 'EGP',
                    ),
                    const MadarHairline.row(),
                    MadarListRow.bill(
                      title: l.s('T5 · Terrace', 'ط5 · التراس'),
                      meta:
                          '${l.s('4 guests', 'الضيوف: 4')} · ${MadarFormat.elapsed(const Duration(minutes: 42), locale: l.locale)}',
                      minor: 84500,
                      currency: 'EGP',
                      status: MadarStatus(
                        l.s('Ordered', 'تم الطلب'),
                        tone: MadarTone.accent,
                      ),
                      rail: MadarTone.warning,
                      ctaLabel: phone ? null : l.s('Settle', 'تسوية'),
                      onCta: () {},
                      onTap: () {},
                    ),
                    const MadarHairline.row(),
                    MadarListRow.pick(
                      title: l.s('Arabic', 'العربية'),
                      meta: 'العربية',
                      glyph: MadarGlyph.globe,
                      selected: l.ar,
                      onTap: () {},
                    ),
                    const MadarHairline.row(),
                    MadarListRow.pick(
                      title: l.s('English', 'الإنجليزية'),
                      meta: 'English',
                      glyph: MadarGlyph.globe,
                      selected: !l.ar,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              section(
                l.s('Status pills', 'شارات الحالة'),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (var i = 0; i < 4; i++) MadarStatusPill(_status(l, i)),
                    MadarStatusPill(
                      MadarStatus(
                        l.s('Open', 'مفتوحة'),
                        tone: MadarTone.accent,
                      ),
                    ),
                  ],
                ),
              ),
              section(
                l.s('Loading', 'جارٍ التحميل'),
                MadarDataTable<_Order>(
                  scrollable: false,
                  columns: _orderColumns(l),
                  state: const MadarTableState.loading(rows: 3),
                  rowKey: (o) => o.ref,
                  empty: const MadarEmptyContent(title: ''),
                ),
              ),
              section(
                l.s('Empty', 'فارغ'),
                MadarDataTable<_Order>(
                  scrollable: false,
                  columns: _orderColumns(l),
                  state: const MadarTableState.data([]),
                  rowKey: (o) => o.ref,
                  empty: MadarEmptyContent(
                    title: l.s(
                      'No orders this shift',
                      'لا طلبات في هذه الوردية',
                    ),
                    message: l.s(
                      'Sales you ring up appear here.',
                      'تظهر هنا المبيعات التي تسجلها.',
                    ),
                  ),
                ),
              ),
              section(
                l.s('Error', 'خطأ'),
                MadarDataTable<_Order>(
                  scrollable: false,
                  columns: _orderColumns(l),
                  state: MadarTableState.error(
                    message: l.s(
                      "Couldn't load orders. Check the connection.",
                      'تعذر تحميل الطلبات. تحقق من الاتصال.',
                    ),
                    retryLabel: l.s('Retry', 'إعادة المحاولة'),
                    onRetry: () {},
                  ),
                  rowKey: (o) => o.ref,
                  empty: const MadarEmptyContent(title: ''),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

// ── Harness ──────────────────────────────────────────────────────────────

Widget _shell(_L l, Widget body) => MadarShellScaffold(
  tabs: [
    MadarTab(label: l.s('Sell', 'البيع'), glyph: MadarGlyph.bag),
    MadarTab(label: l.s('Floor', 'الصالة'), glyph: MadarGlyph.table),
    MadarTab(label: l.orders, glyph: MadarGlyph.receipt, badge: 2),
    MadarTab(label: l.s('Till', 'الخزينة'), glyph: MadarGlyph.wallet),
  ],
  selectedIndex: 2,
  onSelect: (_) {},
  person: MadarPerson(name: l.s('Sara', 'سارة'), initial: l.s('S', 'س')),
  topBar: MadarTopBar(
    title: l.branch,
    subtitle: l.s('Till 1', 'الخزينة 1'),
    pill: MadarOutboxPill(
      state: OutboxState.synced,
      label: l.s('Synced', 'متزامن'),
    ),
  ),
  body: body,
);

Future<void> _shot(
  WidgetTester tester, {
  required String name,
  required Size size,
  required bool ar,
  required bool dark,
  required Widget child,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? MadarTheme.dark() : MadarTheme.light(),
        locale: Locale(ar ? 'ar' : 'en'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');
  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: size.width < 500 ? 3 : 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/render')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      loader.addFont(
        File(
          'assets/fonts/$family-$cut.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  for (final ar in [false, true]) {
    for (final dark in [false, true]) {
      final tag = '${ar ? 'ar' : 'en'}-${dark ? 'dark' : 'light'}';
      final l = _L(ar: ar);
      for (final (device, size) in [
        ('ipad', _ipad),
        ('phone', _phone),
        ('desktop', _desktop),
      ]) {
        testWidgets('orders page · $device · $tag', (tester) async {
          await _shot(
            tester,
            name: 'spec-orders-$device-$tag',
            size: size,
            ar: ar,
            dark: dark,
            child: Scaffold(
              body: _shell(
                l,
                _ordersPage(
                  l,
                  state: MadarTableState.data(
                    _orders,
                    hasMore: true,
                    onLoadMore: () {},
                  ),
                ),
              ),
            ),
          );
        });

        testWidgets('past shifts page · $device · $tag', (tester) async {
          await _shot(
            tester,
            name: 'spec-shifts-$device-$tag',
            size: size,
            ar: ar,
            dark: dark,
            child: Scaffold(body: _shell(l, _shiftsPage(l))),
          );
          // Open the short shift to show its nested orders.
          final omar = find.text(l.s('Omar', 'عمر'));
          await tester.tap(omar.first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await _shot(
            tester,
            name: 'spec-shifts-open-$device-$tag',
            size: size,
            ar: ar,
            dark: dark,
            child: Scaffold(body: _shell(l, _shiftsPage(l))),
          );
        });
      }

      for (final (device, size) in [
        ('ipad', const Size(1106, 1720)),
        ('phone', const Size(390, 2700)),
      ]) {
        testWidgets('kit board · $device · $tag', (tester) async {
          await _shot(
            tester,
            name: 'spec-kit-$device-$tag',
            size: size,
            ar: ar,
            dark: dark,
            child: Scaffold(body: _kit(l)),
          );
        });
      }
    }
  }
}
