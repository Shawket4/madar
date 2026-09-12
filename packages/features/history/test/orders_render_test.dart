// Renders Orders to PNG so it can be LOOKED at.
//
// Orders is where a teller finds a sale to reprint or correct, and a row
// whose figures sit wrong is a row that gets misread. There is no simulator
// here; `MADAR_RENDER=true` writes `build/render/orders-*.png` — the iPad
// list with the sale beside it, the same in the dark under All, All when
// offline, the ⋯ and void sheets, and the phone in Arabic (list and sale),
// mirrored. Without the flag it still builds every board and fails on any
// layout exception, which is the part CI cares about.
//
// The words in here are fixture text so the pictures read like the app;
// the app's own words come through `bridge.tr`, with the redesign's new
// keys falling back to `historyFallbackStrings` until the core learns them.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_history/feature_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

/// The iPad, landscape — the primary target.
const Size _ipad = Size(1194, 834);

/// A phone — the real fallback.
const Size _phone = Size(390, 844);

// ── Fixture words (the core's own keys; the new ones come from the
// package's fallback table) ─────────────────────────────────────────────

const _en = <String, String>{
  'history.title': 'Orders',
  'history.empty': 'No orders this shift yet.',
  'history.queued': 'Queued',
  'history.failed': 'Failed',
  'history.voided': 'Voided',
  'history.order': 'Order',
  'history.no_match': 'No matching orders',
  'history.show_more': 'Show {count} more',
  'history.type.all': 'All',
  'history.type.dine_in': 'Dine-in',
  'search.load_more': 'Load more',
  'order.all': 'All',
  'order.subtotal': 'Subtotal',
  'order.tax': 'VAT',
  'order.total': 'Total',
  'order.discount': 'Discount',
  'loyalty.add_points': 'Add points',
  'void.title': 'Void order',
  'void.reason': 'Reason',
  'void.reason_mistake': 'Order mistake',
  'void.reason_customer': 'Customer changed their mind',
  'void.reason_quality': 'Quality issue',
  'void.reason_other': 'Other',
  'void.note': 'Note (optional)',
  'void.restock': 'Restock ingredients',
  'void.confirm': 'Void order',
  'void.cancel': 'Cancel',
};

const _ar = <String, String>{
  'history.title': 'الطلبات',
  'history.empty': 'لا توجد طلبات في هذه الوردية بعد.',
  'history.queued': 'في الانتظار',
  'history.failed': 'فشل',
  'history.voided': 'ملغى',
  'history.order': 'طلب',
  'history.no_match': 'لا توجد طلبات مطابقة',
  'history.show_more': 'عرض {count} إضافية',
  'history.type.all': 'الكل',
  'history.type.dine_in': 'محلي',
  'search.load_more': 'تحميل المزيد',
  'order.all': 'الكل',
  'order.subtotal': 'المجموع الفرعي',
  'order.tax': 'الضريبة',
  'order.total': 'الإجمالي',
  'order.discount': 'خصم',
  'loyalty.add_points': 'إضافة نقاط',
  'void.title': 'إبطال الطلب',
  'void.reason': 'السبب',
  'void.reason_mistake': 'خطأ في الطلب',
  'void.reason_customer': 'تغيّر رأي العميل',
  'void.reason_quality': 'مشكلة في الجودة',
  'void.reason_other': 'أخرى',
  'void.note': 'ملاحظة (اختياري)',
  'void.restock': 'إعادة المكونات للمخزون',
  'void.confirm': 'إبطال الطلب',
  'void.cancel': 'إلغاء',
};

// ── Fixture data ───────────────────────────────────────────────────────

const _openedAt = '2026-09-12T15:02:00Z';

const _shift = ShiftView(
  id: 'sh-1',
  branchId: 'br-1',
  tellerId: 'u-1',
  tellerName: 'Sara',
  openingCashMinor: 85000,
  openedAt: _openedAt,
  status: 'open',
  isOpen: true,
);

OrderSummaryView _order(
  int n, {
  required String at,
  int total = 19600,
  String payment = 'Cash',
  String status = 'completed',
  bool queued = false,
  String type = 'dine_in',
  String? customer,
  String? ref,
}) => OrderSummaryView(
  id: queued ? 'local-$n' : 'o-$n',
  orderNumber: queued ? null : n,
  subtotalMinor: total * 100 ~/ 114,
  taxMinor: total - total * 100 ~/ 114,
  totalMinor: total,
  paymentLabel: payment,
  status: status,
  createdAt: at,
  queued: queued,
  tellerName: queued ? null : 'Sara',
  orderType: type,
  customerName: customer,
  orderRef: ref,
);

/// This shift, newest first, the way the mirror hands them back.
final _shiftOrders = <OrderSummaryView>[
  _order(1043, at: '2026-09-12T19:40:00Z', total: 4500, queued: true),
  _order(1042, at: '2026-09-12T19:31:00Z', customer: 'Omar'),
  _order(1041, at: '2026-09-12T19:28:00Z', total: 4500, payment: 'Card'),
  _order(
    1040,
    at: '2026-09-12T19:20:00Z',
    total: 21000,
    type: 'delivery',
    ref: '#D-118',
  ),
  _order(1039, at: '2026-09-12T19:12:00Z', total: 6000, status: 'voided'),
  _order(1038, at: '2026-09-12T19:05:00Z', total: 31000, payment: 'Card'),
  _order(1037, at: '2026-09-12T18:58:00Z', total: 8500, payment: 'Wallet'),
  _order(1036, at: '2026-09-12T18:51:00Z', total: 12000),
  _order(1035, at: '2026-09-12T18:44:00Z', total: 3500),
  _order(1034, at: '2026-09-12T18:30:00Z', total: 9000, payment: 'Card'),
  _order(1033, at: '2026-09-12T18:12:00Z', total: 15500),
  _order(1032, at: '2026-09-12T17:58:00Z', total: 27000, payment: 'Card'),
];

/// Yesterday's page under All.
final _pastOrders = <OrderSummaryView>[
  for (var i = 0; i < 12; i++)
    _order(
      990 - i,
      at: '2026-09-11T${(20 - i).toString().padLeft(2, '0')}:14:00Z',
      total: 4500 + i * 1700,
      payment: i.isEven ? 'Cash' : 'Card',
      status: i == 4 ? 'voided' : 'completed',
    ),
];

/// The one sale in the fixture that has money already given back on it.
const _partlyRefundedOrderId = 'o-1042';

const _detail1042 = OrderDetailView(
  id: 'o-1042',
  orderNumber: 1042,
  status: 'completed',
  paymentLabel: 'Cash',
  subtotalMinor: 17500,
  discountMinor: 0,
  taxMinor: 2407,
  totalMinor: 19600,
  createdAt: '2026-09-12T19:31:00Z',
  lines: [
    OrderDetailLineView(
      name: 'Latte',
      qty: 2,
      sizeLabel: 'Large',
      lineTotalMinor: 9000,
      addons: ['Oat milk'],
      optionals: [],
    ),
    OrderDetailLineView(
      name: 'Espresso',
      qty: 1,
      lineTotalMinor: 3500,
      addons: [],
      optionals: [],
    ),
    OrderDetailLineView(
      name: 'Flat white',
      qty: 1,
      lineTotalMinor: 5000,
      addons: [],
      optionals: [],
    ),
  ],
);

const _receipt1042 = ReceiptView(
  localOrderId: 'o-1042',
  orderNumber: 1042,
  isVoided: false,
  lines: [],
  paymentLabel: 'Cash',
  subtotalMinor: 17500,
  discountMinor: 0,
  taxMinor: 2407,
  serviceChargeMinor: 2100,
  deliveryFeeMinor: 0,
  totalMinor: 19600,
  tipMinor: 0,
  amountTenderedMinor: 20000,
  changeMinor: 400,
  isCash: true,
  tellerName: 'Sara',
  isDelivery: false,
  queuedOffline: false,
  createdAt: '2026-09-12T19:31:00Z',
);

/// A bridge that answers what Orders asks, from fixtures. [online] false is
/// a till with no network; [arabic] mirrors the screen.
class _FakeBridge implements MadarBridge {
  _FakeBridge({
    this.online = true,
    this.arabic = false,
    this.fullyRefunded = false,
  });

  final bool online;
  final bool arabic;

  /// The one sale with refunds on it has had ALL of its money given back.
  final bool fullyRefunded;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #tr) {
      final key = invocation.namedArguments[#key] as String? ?? '';
      // Unknown keys come back as the key, exactly like the core, so the
      // package's fallback table is what the picture exercises.
      return (arabic ? _ar[key] : null) ?? _en[key] ?? key;
    }
    if (name == #locale) return arabic ? 'ar' : 'en';
    if (name == #isRtl) return arabic;
    if (name == #appRoute) return const AppRoute.order();
    if (name == #currentSession) {
      return SessionSnapshot(
        userId: 'u-1',
        displayName: 'Sara',
        role: 'teller',
        currencyCode: 'EGP',
        taxRate: 0.14,
        taxInclusive: true,
        serviceChargeRate: 0.12,
        serviceChargeTaxable: false,
        requireTableForOrders: true,
        online: online,
        permissionsLoaded: true,
      );
    }
    if (name == #deviceConfig) {
      return const DeviceConfigView(
        branchName: 'Rue Zamalek',
        tillId: 't-1',
        reconfiguring: false,
        configured: true,
      );
    }
    if (name == #formatTime) {
      final raw = invocation.namedArguments[#rfc3339] as String;
      final style = invocation.namedArguments[#style] as TimeStyle;
      final at = DateTime.parse(raw);
      final hm =
          '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}';
      return switch (style) {
        TimeStyle.time => hm,
        TimeStyle.dateShort => 'Sep ${at.day}',
        _ => 'Sep ${at.day} · $hm',
      };
    }
    if (name == #humanMessage) return 'Something went wrong';
    if (name == #clockSkewMinutes) return 0;
    if (name == #listOrderRefunds) {
      final id = invocation.namedArguments[#orderId] as String? ?? '';
      // One sale carries a part refund; everything else is untouched, so the
      // panel shows the block on exactly one row.
      final refunded = id != _partlyRefundedOrderId
          ? 0
          : fullyRefunded
          ? 24000
          : 5000;
      return Future<OrderRefundsView>.value(
        OrderRefundsView(
          orderId: id,
          orderStatus: 'completed',
          totalMinor: 24000,
          refundedMinor: refunded,
          refundedCashMinor: refunded,
          refundableRemainingMinor: 24000 - refunded,
          refunds: refunded == 0
              ? const []
              : [
                  RefundView(
                    id: 'rf-1',
                    orderId: _partlyRefundedOrderId,
                    amountMinor: refunded,
                    method: 'Cash',
                    isCash: true,
                    reason: 'quality_issue',
                    issuedAt: '2026-09-12T19:40:00Z',
                    issuedByName: 'Sara',
                    lines: const [],
                    queued: false,
                  ),
                ],
        ),
      );
    }
    if (name == #loyaltySettings) {
      // The branch runs a points programme, so *Add points* is offered.
      return Future<LoyaltyProgrammeView>.value(
        const LoyaltyProgrammeView(
          enabled: true,
          mode: 'points',
          programName: 'Rue Rewards',
          balanceLabel: 'points',
        ),
      );
    }
    if (name == #loyaltyAwardWindowOpen) {
      final at = invocation.namedArguments[#orderCreatedAt] as String;
      // The fixture clock is 12 Sep 2026, 20:00 — this shift is inside the
      // window, yesterday's sales are not.
      return DateTime.parse(at).isAfter(DateTime.utc(2026, 9, 11, 20));
    }
    if (name == #currentShift || name == #refreshShift) {
      return Future<ShiftView?>.value(_shift);
    }
    if (name == #listShiftOrders) {
      return Future<List<OrderSummaryView>>.value(_shiftOrders);
    }
    if (name == #shiftStats) {
      return Future<ShiftStatsView>.value(
        const ShiftStatsView(salesMinor: 623000, orderCount: 42),
      );
    }
    if (name == #syncStatus) {
      return Future<SyncStatusView>.value(
        SyncStatusView(
          pending: online ? 0 : 1,
          failed: 0,
          blocked: 0,
          online: online,
          authPaused: false,
        ),
      );
    }
    if (name == #searchOrders) {
      final page = invocation.namedArguments[#page] as int;
      final status = invocation.namedArguments[#status] as String?;
      final rows = status == 'voided'
          ? _pastOrders.where((o) => o.status == 'voided').toList()
          : _pastOrders;
      return Future<OrderSearchPage>.value(
        OrderSearchPage(
          orders: page == 1 ? rows : const [],
          page: page,
          total: 318,
          hasMore: page == 1,
        ),
      );
    }
    if (name == #orderDetail) {
      return Future<OrderDetailView>.value(_detail1042);
    }
    if (name == #orderReceiptView) {
      return Future<ReceiptView>.value(_receipt1042);
    }
    if (name == #refreshConnectivity) return Future<bool>.value(online);
    if (name == #pendingOutboxCount) return Future<int>.value(0);
    return null;
  }
}

// ── Harness ────────────────────────────────────────────────────────────

Future<void> _shoot(
  WidgetTester tester, {
  required Widget screen,
  required _FakeBridge bridge,
  required Size size,
  required ThemeData theme,
  required String name,
  Future<void> Function(WidgetTester tester)? then,
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
      child: ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: MaterialApp(
          theme: theme,
          home: Directionality(
            textDirection: bridge.arabic
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: screen,
          ),
        ),
      ),
    ),
  );
  // The notifier loads on a microtask and the skeletons animate, so this is
  // a few frames rather than a pumpAndSettle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
  if (then != null) await then(tester);
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');
  await _capture(tester, name);
}

/// Writes the current frame to `build/render/orders-<name>.png` when
/// rendering.
Future<void> _capture(WidgetTester tester, String name) async {
  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  // `toImage` completes on the real event loop; inside the binding's fake
  // async zone a later `pump` can wedge behind it. `runAsync` is the door.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/render')..createSync(recursive: true);
    File(
      '${dir.path}/orders-$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Taps the row for order [number] and lets the detail land.
Future<void> _open(WidgetTester tester, int number) async {
  await tester.tap(find.text('#$number'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Opens the ⋯ sheet on the selected sale.
Future<void> _more(WidgetTester tester) async {
  await tester.tap(find.byType(MoreTile));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Loads the design system's Plex faces so the boards render real type —
/// without them the test binding's block font hides everything the picture
/// is for. The family name carries the package prefix because the styles do.
Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      final file = File('../../design_system/assets/fonts/$family-$cut.ttf');
      loader.addFont(file.readAsBytes().then<ByteData>(ByteData.sublistView));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('the iPad: this shift beside the selected sale', (tester) async {
    await _shoot(
      tester,
      screen: const OrderHistoryScreen(),
      bridge: _FakeBridge(),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'ipad',
      then: (t) => _open(t, 1042),
    );
    // The header counts the shift in the core's words and figures.
    expect(
      find.text('This shift · \u206642\u2069 sales · EGP 6230.00'),
      findsOneWidget,
    );
    // The list: a queued sale carries no number, a voided one is tagged.
    expect(find.text('#1043'), findsNothing);
    expect(find.text('QUEUED'), findsOneWidget);
    expect(find.text('VOIDED'), findsOneWidget);
    // The sale beside it: lines, service from the receipt, VAT under the
    // total because the policy is inclusive.
    expect(find.text('Latte'), findsOneWidget);
    expect(find.text('Large · Oat milk'), findsOneWidget);
    expect(find.text('Service'), findsOneWidget);
    expect(find.text('VAT included \u206614%\u2069'), findsOneWidget);
    expect(find.text('Reprint'), findsOneWidget);
    expect(find.text('Add points'), findsOneWidget);
    // What has already gone back on this sale, before anything is offered
    // about giving back more.
    expect(find.text('Refunded'), findsOneWidget);
    expect(find.text('− EGP 50.00'), findsOneWidget);
    expect(find.text('Sara · Cash'), findsOneWidget);
    expect(find.text('EGP 190.00 left to refund'), findsOneWidget);
    expect(find.textContaining('Void removes a mistaken sale'), findsOneWidget);
  });

  testWidgets('a sale refunded in full is not offered another refund', (
    tester,
  ) async {
    await _shoot(
      tester,
      screen: const OrderHistoryScreen(),
      bridge: _FakeBridge(fullyRefunded: true),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'ipad-refunded-full',
      then: (t) async {
        await _open(t, 1042);
        await _more(t);
      },
    );
    // The row is still there, saying why it does nothing — a missing row
    // reads as a missing feature.
    expect(find.text('Refund'), findsOneWidget);
    expect(find.text('Already refunded in full.'), findsWidgets);
  });

  testWidgets('the ⋯ sheet offers Void and Refund, each saying what it does', (
    tester,
  ) async {
    await _shoot(
      tester,
      screen: const OrderHistoryScreen(),
      bridge: _FakeBridge(),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'ipad-more',
      then: (t) async {
        await _open(t, 1042);
        await _more(t);
      },
    );
    expect(find.text('Void sale'), findsOneWidget);
    expect(
      find.textContaining('Paid \u2066Sep 12 · 19:31\u2069'),
      findsOneWidget,
    );
    // BOTH acts are offered now. The sheet used to carry a sentence about the
    // refund it could not do, because the core had a void and no refund; it
    // has one, so the sentence is a row.
    expect(find.text('Refund'), findsOneWidget);
    // Twice: the panel teaches the difference between the two acts, and the
    // sheet's Refund row repeats what it does under its own title.
    expect(
      find.textContaining('Refund returns money on a sale that stands'),
      findsNWidgets(2),
    );
  });

  testWidgets('the void sheet: reason chips, restock, one danger button', (
    tester,
  ) async {
    await _shoot(
      tester,
      screen: const OrderHistoryScreen(),
      bridge: _FakeBridge(),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'ipad-void',
      then: (t) async {
        await _open(t, 1042);
        await _more(t);
        await t.tap(find.text('Void sale'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
        await t.pump(const Duration(milliseconds: 600));
      },
    );
    expect(find.text('Quality issue'), findsOneWidget);
    expect(find.text('Restock ingredients'), findsOneWidget);
    final confirm = tester.widget<MadarButton>(
      find.widgetWithText(MadarButton, 'Void order'),
    );
    expect(confirm.variant, MadarButtonVariant.danger);
  });

  testWidgets('a queued sale says why Void does not apply', (tester) async {
    await _shoot(
      tester,
      screen: const OrderHistoryScreen(),
      bridge: _FakeBridge(),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'ipad-queued',
      then: (t) async {
        // The queued row has no number; its tag is the handle.
        await t.tap(find.text('QUEUED'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await _more(t);
      },
    );
    // Twice: a sale the server has never seen can be neither voided nor
    // refunded, and each row says so in its own place rather than one of them
    // sitting there enabled and failing.
    expect(find.textContaining('cannot be voided'), findsNWidgets(2));
    expect(find.text('Reprint'), findsNothing);
  });

  testWidgets('All, in the dark: every shift, dated, Load more', (
    tester,
  ) async {
    await _shoot(
      tester,
      screen: const OrderSearchScreen(),
      bridge: _FakeBridge(),
      size: _ipad,
      theme: MadarTheme.dark(),
      name: 'ipad-dark-all',
      then: (t) => _open(t, 989),
    );
    expect(find.text('All · \u2066318\u2069 found'), findsOneWidget);
    // The next-page row is the last in a lazy list: scroll it in.
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pump();
    expect(find.text('Load more'), findsOneWidget);
    expect(find.textContaining('Sep 11'), findsWidgets);
    // Yesterday's sale is past the award window: no Add points.
    expect(find.text('Add points'), findsNothing);
  });

  testWidgets('All, offline: says so in words', (tester) async {
    await _shoot(
      tester,
      screen: const OrderSearchScreen(),
      bridge: _FakeBridge(online: false),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'ipad-all-offline',
    );
    expect(
      find.text('Searching past shifts needs a connection.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('the Voided chip narrows the list', (tester) async {
    await _shoot(
      tester,
      screen: const OrderHistoryScreen(),
      bridge: _FakeBridge(),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'ipad-voided-chip',
      then: (t) async {
        await t.tap(find.widgetWithText(MadarChip, 'Voided'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
      },
    );
    expect(find.text('#1039'), findsOneWidget);
    expect(find.text('#1042'), findsNothing);
  });

  testWidgets('search finds a sale by number, customer or amount', (
    tester,
  ) async {
    await _shoot(
      tester,
      screen: const OrderHistoryScreen(),
      bridge: _FakeBridge(),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'ipad-search',
      then: (t) async {
        await t.enterText(find.byType(TextField), 'omar');
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
      },
    );
    expect(find.text('#1042'), findsOneWidget);
    expect(find.text('#1041'), findsNothing);
  });

  testWidgets('the phone in Arabic: the list, mirrored', (tester) async {
    await _shoot(
      tester,
      screen: const OrderHistoryScreen(),
      bridge: _FakeBridge(arabic: true),
      size: _phone,
      theme: MadarTheme.light(),
      name: 'phone-ar',
    );
    expect(find.text('الطلبات'), findsOneWidget);
    expect(
      find.text('هذه الوردية · \u206642\u2069 مبيعات · EGP 6230.00'),
      findsOneWidget,
    );
    // Figures stay LTR islands inside the Arabic row.
    final number = tester.widget<Text>(find.text('#1042'));
    expect(number.textDirection, TextDirection.ltr);
    // No sale is drawn beside the list on a phone.
    expect(find.byType(SalePanel), findsNothing);
  });

  testWidgets('the phone: a row pushes the sale', (tester) async {
    await _shoot(
      tester,
      screen: const OrderHistoryScreen(),
      bridge: _FakeBridge(arabic: true),
      size: _phone,
      theme: MadarTheme.light(),
      name: 'phone-ar-sale',
      then: (t) async {
        await _open(t, 1042);
        await t.pump(const Duration(milliseconds: 400));
      },
    );
    expect(find.byType(SaleScreen), findsOneWidget);
    expect(find.text('بيع \u2066#1042\u2069'), findsOneWidget);
    expect(find.text('إعادة طباعة'), findsOneWidget);
    expect(find.byType(MoreTile), findsOneWidget);
  });
}
