// Renders Sell, the Floor, the Bill and the Bills tab to PNG so they can be
// LOOKED at — on the iPad they are built for, on the phone a waiter carries,
// and mirrored in Arabic.
//
// `MADAR_RENDER=true` writes `build/render/<screen>-<device>.png`. Without the
// flag the test still builds every screen at both sizes and fails on any
// layout exception, which is the part CI cares about. The strings here are
// fixture words for the picture; the app's own come through `bridge.tr`.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/feature_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

/// The iPad, landscape — the primary target.
const Size _ipad = Size(1194, 834);

/// A phone — the real fallback.
const Size _phone = Size(390, 844);

// ── fixtures ───────────────────────────────────────────────────────────────

MenuItemView _item(String id, String name, int price, {String cat = 'hot'}) =>
    MenuItemView(
      id: id,
      name: name,
      categoryId: cat,
      basePriceMinor: price,
      isActive: true,
      allowedAddonIds: const [],
      sizes: const [],
      addonSlots: const [],
      optionalFields: const [],
      recipes: const [],
      recipeSteps: const [],
    );

final _items = <MenuItemView>[
  _item('espresso', 'Espresso', 3500),
  _item('latte', 'Latte', 4500),
  _item('flat', 'Flat white', 5000),
  _item('mocha', 'Mocha', 5500),
  _item('cappuccino', 'Cappuccino', 4800),
  _item('americano', 'Americano', 4000),
  _item('iced-latte', 'Iced latte', 5000, cat: 'cold'),
  _item('lemonade', 'Fresh lemonade', 4000, cat: 'cold'),
  _item('cake', 'Chocolate cake', 6000, cat: 'food'),
  _item('croissant', 'Croissant', 3000, cat: 'food'),
  _item('sandwich', 'Club sandwich', 8500, cat: 'food'),
  _item('salad', 'Caesar salad', 7500, cat: 'food'),
];

const _categories = <CategoryView>[
  CategoryView(id: 'hot', name: 'Hot', isActive: true),
  CategoryView(id: 'cold', name: 'Cold', isActive: true),
  CategoryView(id: 'food', name: 'Food', isActive: true),
];

CartLineView _cartLine(String id, String name, int price, int qty) =>
    CartLineView(
      key: 'k-$id',
      itemId: id,
      name: name,
      addons: const [],
      optionals: const [],
      unitPriceMinor: price,
      qty: qty,
      lineTotalMinor: price * qty,
      bundleComponents: const [],
    );

final _cart = <CartLineView>[
  _cartLine('espresso', 'Espresso', 3500, 1),
  _cartLine('flat', 'Flat white', 5000, 2),
];

const _totals = CartTotals(
  itemCount: 3,
  subtotalMinor: 13500,
  discountMinor: 0,
  taxMinor: 1890,
  serviceChargeMinor: 0,
  totalMinor: 15390,
);

TicketLineView _line(
  String name,
  int qty,
  int minor,
  int round,
  String at, {
  bool voided = false,
  List<String> mods = const [],
}) => TicketLineView(
  id: '$name-$round',
  menuItemId: name.toLowerCase(),
  name: name,
  qty: qty,
  modifiers: mods,
  lineTotalMinor: minor,
  voided: voided,
  roundNumber: round,
  roundFiredAt: at,
);

String _ago(int minutes) => DateTime.now()
    .toUtc()
    .subtract(Duration(minutes: minutes))
    .toIso8601String();

final _tickets = <TicketView>[
  TicketView(
    id: 'tk-1',
    ticketRef: 'T-0412',
    tableId: 't2',
    status: 'ready',
    guestCount: 4,
    customerName: 'Omar',
    waiterName: 'Sara',
    subtotalMinor: 17500,
    openedAt: _ago(42),
    queuedOffline: false,
    lines: [
      _line('Latte', 2, 9000, 1, _ago(42), mods: const ['Oat milk']),
      _line('Cake', 1, 6000, 1, _ago(42), voided: true),
      _line('Espresso', 1, 3500, 2, _ago(24)),
      _line('Flat white', 1, 5000, 2, _ago(24)),
    ],
  ),
  TicketView(
    id: 'tk-2',
    ticketRef: 'T-0413',
    tableId: 't5',
    status: 'open',
    guestCount: 2,
    waiterName: 'Hany',
    subtotalMinor: 14500,
    openedAt: _ago(18),
    queuedOffline: false,
    lines: [
      _line('Club sandwich', 1, 8500, 1, _ago(18)),
      _line('Iced latte', 1, 5000, 1, _ago(18)),
      _line('Croissant', 1, 1000, 1, _ago(18)),
    ],
  ),
  TicketView(
    id: 'tk-3',
    ticketRef: 'T-0414',
    status: 'queued',
    customerName: 'Karim',
    waiterName: 'Sara',
    subtotalMinor: 6000,
    openedAt: _ago(5),
    queuedOffline: true,
    lines: const [],
  ),
];

FloorTableStateView _table({
  required String id,
  required String label,
  required double x,
  required double y,
  String status = 'free',
  int seats = 4,
  String shape = 'rect',
  String? bookingId,
  String? bookingGuest,
}) => FloorTableStateView(
  id: id,
  sectionId: 'sec-in',
  label: label,
  seats: seats,
  shape: shape,
  status: status,
  posX: x,
  posY: y,
  width: 90,
  height: 90,
  rotation: 0,
  heldLockedByOther: false,
  heldSince: status == 'seated' ? _ago(12) : null,
  bookingId: bookingId,
  bookingGuest: bookingGuest,
  bookingParty: bookingId == null ? null : 4,
  bookingStatus: bookingId == null ? null : 'confirmed',
  bookingStartsAt: bookingId == null ? null : _ago(-30),
  bookingHeldFrom: bookingId == null ? null : _ago(5),
);

final _layout = FloorLayoutView(
  sections: const [
    FloorSectionInfo(
      id: 'sec-in',
      name: 'Inside',
      ordering: 0,
      canvasW: 900,
      canvasH: 620,
    ),
    FloorSectionInfo(
      id: 'sec-out',
      name: 'Terrace',
      ordering: 1,
      canvasW: 600,
      canvasH: 400,
    ),
  ],
  tables: [
    _table(id: 't1', label: 'T1', x: 40, y: 40, status: 'seated'),
    _table(id: 't2', label: 'T2', x: 200, y: 40, status: 'seated'),
    _table(id: 't3', label: 'T3', x: 360, y: 40, status: 'dirty'),
    _table(id: 't4', label: 'T4', x: 520, y: 40, seats: 2, shape: 'circle'),
    _table(id: 't5', label: 'T5', x: 40, y: 210, status: 'seated', seats: 6),
    _table(id: 't6', label: 'T6', x: 200, y: 210),
    _table(id: 't7', label: 'T7', x: 360, y: 210, seats: 2, shape: 'circle'),
    _table(
      id: 't9',
      label: 'T9',
      x: 520,
      y: 210,
      bookingId: 'b1',
      bookingGuest: 'Omar',
    ),
  ],
);

const _drafts = <DraftView>[
  DraftView(
    id: 'd1',
    name: 'Ahmed',
    itemCount: 2,
    totalMinor: 9000,
    createdAt: '2026-09-12T18:40:00Z',
    lockedByOther: false,
  ),
];

/// Fixture words for the keys the fake bridge is asked for. English for the
/// core's existing keys; the new vocabulary comes through the package's own
/// fallback table, which is what a real device would show today too.
const _en = {
  'tables.title': 'Tables',
  'tables.seated': 'Seated',
  'tables.free': 'Free',
  'tables.needs_clearing': 'Needs clearing',
  'tables.reserved': 'Reserved',
  'tables.arrivals': 'Arrivals',
  'tables.waitlist': 'Waitlist',
  'tables.view_list': 'List',
  'tables.view_plan': 'Plan',
  'tables.seats': 'seats',
  'tables.guests': 'guests',
  'tables.round': 'Round',
  'tables.add_round': 'Add a round',
  'tables.move': 'Move to another table',
  'tables.bill_pending': 'The first round has not synced yet',
  'tables.no_section': 'No section',
  'tables.swap_pick': 'Tap the other table',
  'ticket.status.ready': 'Ready',
  'order.all': 'All',
  'order.search': 'Search items',
  'order.combos': 'Combos',
  'order.configure': 'Configure',
  'order.subtotal': 'Subtotal',
  'order.clear': 'Clear',
  'order.cart_empty': 'Your cart is empty.',
  'waiter.items': 'items',
  'waiter.need_shift': 'Open a shift to settle',
  'waiter.no_tickets': 'No open tickets',
  'chrome.more': 'More',
  'setup.continue': 'Continue',
};

const _ar = {
  'tables.seated': 'مشغولة',
  'tables.free': 'متاحة',
  'tables.needs_clearing': 'تحتاج تنظيفًا',
  'tables.reserved': 'محجوزة',
  'tables.seats': 'مقاعد',
  'tables.guests': 'ضيوف',
  'tables.round': 'جولة',
  'tables.add_round': 'إضافة جولة',
  'tables.move': 'نقل إلى طاولة أخرى',
  'order.subtotal': 'المجموع الفرعي',
  'order.all': 'الكل',
  'order.search': 'ابحث عن صنف',
  'waiter.items': 'أصناف',
  'waiter.need_shift': 'افتح وردية للتحصيل',
  'chrome.more': 'المزيد',
};

class _FakeBridge implements MadarBridge {
  _FakeBridge({this.role = 'teller', this.rtl = false, this.shiftOpen = true});

  final String role;
  final bool rtl;
  final bool shiftOpen;

  ShiftView? get _shift => shiftOpen
      ? const ShiftView(
          id: 'sh-1',
          branchId: 'br-1',
          tellerId: 'u-1',
          tellerName: 'Sara',
          openingCashMinor: 85000,
          openedAt: '2026-09-12T15:02:00Z',
          status: 'open',
          isOpen: true,
        )
      : null;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #tr) {
      final key = invocation.namedArguments[#key] as String? ?? '';
      // A missing key comes back as the key, exactly as the core does — so
      // the package's fallback table is exercised for the new vocabulary.
      return (rtl ? _ar[key] : null) ?? _en[key] ?? key;
    }
    if (name == #isRtl) return rtl;
    if (name == #locale) return rtl ? 'ar' : 'en';
    if (name == #currentSession) {
      return SessionSnapshot(
        userId: 'u-1',
        displayName: 'Sara',
        role: role,
        currencyCode: 'EGP',
        taxRate: 0.14,
        taxInclusive: false,
        serviceChargeRate: 0.12,
        serviceChargeTaxable: false,
        requireTableForOrders: false,
        online: true,
        permissionsLoaded: true,
      );
    }
    if (name == #currentShift || name == #refreshShift) {
      return Future<ShiftView?>.value(_shift);
    }
    if (name == #listCategories) {
      return Future<List<CategoryView>>.value(_categories);
    }
    if (name == #listMenuItems) return Future<List<MenuItemView>>.value(_items);
    if (name == #availableBundles) {
      return Future<List<BundleView>>.value(const []);
    }
    if (name == #cartLines) return Future<List<CartLineView>>.value(_cart);
    if (name == #cartTotals) return Future<CartTotals>.value(_totals);
    if (name == #listDrafts) return Future<List<DraftView>>.value(_drafts);
    if (name == #floorLayout) return Future<FloorLayoutView>.value(_layout);
    if (name == #listOpenTickets) {
      return Future<List<TicketView>>.value(_tickets);
    }
    if (name == #listTransferQueue) {
      return Future<List<TransferQueueView>>.value(const []);
    }
    if (name == #listArrivals) return Future<List<BookingView>>.value(const []);
    if (name == #refreshFloor || name == #refreshCatalog) {
      return Future<void>.value();
    }
    if (name == #refreshConnectivity) return Future<bool>.value(true);
    if (name == #syncStatus) {
      return Future<SyncStatusView>.value(
        const SyncStatusView(
          pending: 0,
          failed: 0,
          blocked: 0,
          online: true,
          authPaused: false,
        ),
      );
    }
    if (name == #listShiftOrders) {
      return Future<List<OrderSummaryView>>.value(const []);
    }
    if (name == #shiftStats) {
      return Future<ShiftStatsView>.value(
        const ShiftStatsView(salesMinor: 623000, orderCount: 42),
      );
    }
    if (name == #listItemModifierGroups) {
      return Future<List<ModifierGroupView>>.value(const []);
    }
    if (name == #listItemAddons) {
      return Future<List<ItemAddonView>>.value(const []);
    }
    if (name == #categoryStyle) {
      final cat = invocation.namedArguments[#name] as String? ?? '';
      final accent = switch (cat) {
        'Cold' => '#2F80ED',
        'Food' => '#D98E04',
        _ => '#8B5A2B',
      };
      return CatStyleView(
        icon: 'cafe',
        bgTop: accent,
        bgBottom: accent,
        iconColor: accent,
        accent: accent,
      );
    }
    if (name == #formatTime) {
      final iso = invocation.namedArguments[#rfc3339] as String? ?? '';
      final t = DateTime.tryParse(iso)?.toLocal();
      if (t == null) return '19:17';
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(t.hour)}:${two(t.minute)}';
    }
    if (name == #clockSkewMinutes) return 0;
    if (name == #appRoute) return const AppRoute.order();
    if (name == #isRealtimeSubscribed) return false;
    return null;
  }
}

// ── harness ────────────────────────────────────────────────────────────────

Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  const dir = '../../design_system/assets/fonts';
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      final file = File('$dir/$family-$cut.ttf');
      if (!file.existsSync()) return;
      loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required Widget screen,
  required Size size,
  _FakeBridge? bridge,
  bool dark = false,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final fake = bridge ?? _FakeBridge();
  final container = ProviderContainer(
    overrides: [bridgeProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? MadarTheme.dark() : MadarTheme.light(),
          home: Directionality(
            textDirection: fake.rtl ? TextDirection.rtl : TextDirection.ltr,
            child: screen,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');
  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  // Real async under the test binding's fake clock: the screens keep
  // periodic timers (a minute clock, the gated poll), and awaiting an engine
  // future outside `runAsync` leaves the fake clock spinning them forever.
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    return await image.toByteData(format: ui.ImageByteFormat.png);
  });
  final dir = Directory('build/render')..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  setUpAll(_loadFonts);

  group('Sell', () {
    testWidgets('the counter on an iPad: tiles, cart column, Charge', (
      tester,
    ) async {
      await _mount(tester, screen: const SellScreen(), size: _ipad);
      expect(find.text('Espresso'), findsWidgets);
      expect(find.text('Takeaway'), findsWidgets);
      await _capture(tester, 'sell-ipad');
    });

    testWidgets('the counter on a phone: tiles and the bottom bar', (
      tester,
    ) async {
      await _mount(tester, screen: const SellScreen(), size: _phone);
      expect(find.text('3 items'), findsOneWidget);
      await _capture(tester, 'sell-phone');
    });

    testWidgets('a round on a bill: on the bill, this round, Fire', (
      tester,
    ) async {
      final container = await _mount(
        tester,
        screen: const SellScreen(),
        size: _ipad,
      );
      container.read(orderProvider.notifier)
        ..pointCartAtTable('t2', 'T2')
        ..selectTicket('tk-1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('T2 · Round 3'), findsWidgets);
      await _capture(tester, 'sell-round-ipad');
    });

    testWidgets('a phone with no shift says why it cannot charge', (
      tester,
    ) async {
      await _mount(
        tester,
        screen: const SellScreen(),
        size: _phone,
        bridge: _FakeBridge(shiftOpen: false),
      );
      expect(find.text('Open a shift to settle'), findsOneWidget);
      await _capture(tester, 'sell-phone-noshift');
    });
  });

  group('Floor', () {
    testWidgets('plan-first on an iPad', (tester) async {
      await _mount(tester, screen: const FloorScreen(), size: _ipad);
      expect(find.text('T5'), findsOneWidget);
      await _capture(tester, 'floor-ipad');
    });

    testWidgets('list-first on a phone', (tester) async {
      await _mount(tester, screen: const FloorScreen(), size: _phone);
      // The worklist: the dirty table leads.
      expect(find.text('T3'), findsOneWidget);
      await _capture(tester, 'floor-phone');
    });

    testWidgets('a free table asks for a party size and seats', (tester) async {
      await _mount(tester, screen: const FloorScreen(), size: _phone);
      await tester.tap(find.text('T6'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('PARTY SIZE'), findsOneWidget);
      expect(find.text('Seat'), findsOneWidget);
      await _capture(tester, 'floor-phone-seat');
    });

    testWidgets('a table with a bill opens the Bill', (tester) async {
      await _mount(tester, screen: const FloorScreen(), size: _ipad);
      await tester.tap(find.text('T2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('ROUND 1'), findsOneWidget);
      expect(find.text('ROUND 2'), findsOneWidget);
    });
  });

  group('Bill', () {
    testWidgets('a 640 column on an iPad', (tester) async {
      await _mount(
        tester,
        screen: const BillScreen(ticketId: 'tk-1'),
        size: _ipad,
      );
      expect(find.text('2× Latte'), findsOneWidget);
      expect(find.text('Subtotal'), findsOneWidget);
      await _capture(tester, 'bill-ipad');
    });

    testWidgets('the width on a phone', (tester) async {
      await _mount(
        tester,
        screen: const BillScreen(ticketId: 'tk-1'),
        size: _phone,
      );
      await _capture(tester, 'bill-phone');
    });

    testWidgets('a waiter sees Add round only', (tester) async {
      await _mount(
        tester,
        screen: const BillScreen(ticketId: 'tk-1', canCharge: false),
        size: _phone,
      );
      expect(find.text('Charge'), findsNothing);
      await _capture(tester, 'bill-phone-waiter');
    });

    testWidgets('mirrors in Arabic; figures stay LTR', (tester) async {
      await _mount(
        tester,
        screen: const BillScreen(ticketId: 'tk-1'),
        size: _ipad,
        bridge: _FakeBridge(rtl: true),
      );
      expect(find.text('المجموع الفرعي'), findsOneWidget);
      await _capture(tester, 'bill-ipad-ar');
    });

    testWidgets('in the dark', (tester) async {
      await _mount(
        tester,
        screen: const BillScreen(ticketId: 'tk-1'),
        size: _ipad,
        dark: true,
      );
      await _capture(tester, 'bill-ipad-dark');
    });
  });

  group('Bills', () {
    testWidgets("the waiter's tab: mine first", (tester) async {
      await _mount(
        tester,
        screen: const BillsScreen(canCharge: false),
        size: _phone,
        bridge: _FakeBridge(role: 'waiter'),
      );
      expect(find.text('MINE'), findsOneWidget);
      expect(find.text('OTHERS'), findsOneWidget);
      await _capture(tester, 'bills-phone');
    });
  });
}
