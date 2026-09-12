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
import 'package:feature_order/src/bundle_detail_sheet.dart';
import 'package:feature_order/src/cart_anchor.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:feature_order/src/sell_screen.dart';
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
    // The server's own figures: 175 of food, 14% on top.
    bill: const TicketBillView(
      subtotalMinor: 17500,
      discountMinor: 0,
      serviceChargeMinor: 0,
      taxMinor: 2450,
      totalMinor: 19950,
      taxRate: 0.14,
      serviceChargeRate: 0,
      taxInclusive: false,
    ),
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
  'order.total': 'Total',
  'order.tax': 'Tax',
  'order.discount': 'Discount',
  'order.service_charge': 'Service',
  'charge.vat_included': 'VAT included',
  'order.clear': 'Clear',
  'order.cart_empty': 'Your cart is empty.',
  'waiter.items': 'items',
  'waiter.need_shift': 'Open a shift to settle',
  'waiter.no_tickets': 'No open tickets',
  'chrome.more': 'More',
  'setup.continue': 'Continue',
  // The Sell / Floor / Bill vocabulary — once served by the package's
  // own fallback table, which is gone; the core carries these keys now.
  'sell.takeaway': 'Takeaway',
  'sell.parked': 'Parked',
  'sell.park': 'Park',
  'sell.parked_empty': 'Nothing parked',
  'sell.this_round': 'This round',
  'sell.on_the_bill': 'On the bill',
  'sell.round_total': 'Round',
  'sell.bill_so_far': 'Bill so far (before tax)',
  'sell.charge': 'Charge',
  'sell.fire': 'Fire',
  'sell.table_required': 'Seat a table first',
  'sell.guest_name': 'Guest name',
  'sell.round_n': 'Round',
  'floor.title': 'Floor',
  'floor.seat': 'Seat',
  'floor.party_size': 'Party size',
  'floor.take_order': 'Take an order',
  'floor.unseat': 'Unseat (party left)',
  'floor.cleared': 'Cleared',
  'floor.seat_booking_here': 'Seat a booking here',
  'floor.walk_in_here': 'Walk-in here',
  'floor.no_bill_yet': 'No bill yet',
  'bill.title': 'Bill',
  'bill.void_bill': 'Void bill',
  'bill.gone': 'This bill was closed on another till',
  'bill.ready': 'Ready',
  'bill.queued': 'Queued',
  'bill.voided': 'Voided',
  'bills.title': 'Bills',
  'bills.mine': 'Mine',
  'bills.others': 'Others',
  'bills.new_bill': 'New bill',
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
  'order.total': 'الإجمالي',
  'order.tax': 'الضريبة',
  'order.discount': 'الخصم',
  'order.service_charge': 'الخدمة',
  'charge.vat_included': 'شامل ضريبة القيمة المضافة',
  'order.all': 'الكل',
  'order.search': 'ابحث عن صنف',
  'waiter.items': 'أصناف',
  'waiter.need_shift': 'افتح وردية للتحصيل',
  'chrome.more': 'المزيد',
  'sell.takeaway': 'تيك أواي',
  'sell.parked': 'مركونة',
  'sell.park': 'اركن الطلب',
  'sell.parked_empty': 'لا طلبات مركونة',
  'sell.this_round': 'هذه الجولة',
  'sell.on_the_bill': 'على الفاتورة',
  'sell.round_total': 'الجولة',
  'sell.bill_so_far': 'الفاتورة حتى الآن (قبل الضريبة)',
  'sell.charge': 'تحصيل',
  'sell.fire': 'أرسل',
  'sell.table_required': 'أجلس على طاولة أولًا',
  'sell.guest_name': 'اسم الضيف',
  'sell.round_n': 'جولة',
  'floor.title': 'الصالة',
  'floor.seat': 'إجلاس',
  'floor.party_size': 'عدد الأفراد',
  'floor.take_order': 'خذ الطلب',
  'floor.unseat': 'إلغاء الإجلاس (غادروا)',
  'floor.cleared': 'تم التنظيف',
  'floor.seat_booking_here': 'أجلس حجزًا هنا',
  'floor.walk_in_here': 'زبون عابر هنا',
  'floor.no_bill_yet': 'لا فاتورة بعد',
  'bill.title': 'الفاتورة',
  'bill.void_bill': 'إلغاء الفاتورة',
  'bill.gone': 'أُغلقت هذه الفاتورة على جهاز آخر',
  'bill.ready': 'جاهز',
  'bill.queued': 'في الانتظار',
  'bill.voided': 'ملغى',
  'bills.title': 'الفواتير',
  'bills.mine': 'فواتيري',
  'bills.others': 'الآخرون',
  'bills.new_bill': 'فاتورة جديدة',
};

class _FakeBridge implements MadarBridge {
  _FakeBridge({
    this.role = 'teller',
    this.rtl = false,
    this.shiftOpen = true,
    this.drafts = _drafts,
    this.bundles = const [],
  });

  /// The combos the catalog offers — none unless a test needs the chip.
  final List<BundleView> bundles;

  final String role;

  /// The parked orders the strip lists.
  final List<DraftView> drafts;

  /// Mutable: `setLocale` flips it, so a test can switch language mid-flight.
  bool rtl;
  final bool shiftOpen;

  /// The table each park landed on, in order — null means the counter.
  final List<String?> parked = [];

  /// How many times the menu was read from the core.
  int menuReads = 0;

  /// How many times a cart was emptied.
  int cleared = 0;

  /// The core's carts, one per context (`null` = takeaway), and the active
  /// context — the fake keeps them apart exactly the way the core does.
  final Map<String?, List<CartLineView>> carts = {null: List.of(_cart)};
  String? context;

  /// Tables seated during the test — the floor reads them back seated.
  final Set<String> seated = {};

  List<CartLineView> get _inHand => carts[context] ??= [];

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
      // A missing key comes back as the key, exactly as the core does.
      return (rtl ? _ar[key] : null) ?? _en[key] ?? key;
    }
    if (name == #isRtl) return rtl;
    if (name == #locale) return rtl ? 'ar' : 'en';
    if (name == #setLocale) {
      rtl = invocation.namedArguments[#locale] == 'ar';
      return null;
    }
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
    if (name == #listMenuItems) {
      menuReads++;
      return Future<List<MenuItemView>>.value(_items);
    }
    if (name == #availableBundles) {
      return Future<List<BundleView>>.value(bundles);
    }
    // Retargeting the cart parks whatever is in it first and may clear it —
    // both are bridge calls the fake has to answer or the whole flow throws.
    // Recorded, because the ORDER of them is the fix: park, clear, adopt.
    if (name == #holdCartOnTable) {
      parked.add(invocation.namedArguments[#tableId] as String?);
      _inHand.clear();
      return Future<bool>.value(false);
    }
    if (name == #cartClear) {
      cleared += 1;
      _inHand.clear();
      return Future<void>.value();
    }
    if (name == #cartSetContext) {
      context = invocation.namedArguments[#tableId] as String?;
      return Future<List<CartLineView>>.value(List.of(_inHand));
    }
    if (name == #cartContext) return Future<String?>.value(context);
    // No printer configured: a fired round prints nothing.
    if (name == #deviceConfig) {
      return const DeviceConfigView(reconfiguring: false, configured: true);
    }
    if (name == #cartAdd) {
      final id = invocation.namedArguments[#itemId] as String;
      final label = invocation.namedArguments[#name] as String;
      final minor = invocation.namedArguments[#unitPriceMinor] as int;
      final i = _inHand.indexWhere((l) => l.itemId == id);
      if (i < 0) {
        _inHand.add(_cartLine(id, label, minor, 1));
      } else {
        final l = _inHand[i];
        _inHand[i] = _cartLine(id, label, minor, l.qty + 1);
      }
      return Future<List<CartLineView>>.value(List.of(_inHand));
    }
    if (name == #validateItemSelections) {
      return Future<List<GroupViolationView>>.value(const []);
    }
    if (name == #cartAddConfigured) {
      final id = invocation.namedArguments[#itemId] as String;
      final item = _items.firstWhere((i) => i.id == id);
      _inHand.add(_cartLine(id, item.name, item.basePriceMinor, 1));
      return Future<List<CartLineView>>.value(List.of(_inHand));
    }
    if (name == #cartAddBundle) {
      final id = invocation.namedArguments[#bundleId] as String;
      _inHand.add(_cartLine(id, 'Combo', 9000, 1));
      return Future<List<CartLineView>>.value(List.of(_inHand));
    }
    if (name == #fireTicket) {
      _inHand.clear();
      return Future<TicketFiredView>.value(
        const TicketFiredView(ticketId: 'tk-new', queuedOffline: false),
      );
    }
    if (name == #cartLines) {
      return Future<List<CartLineView>>.value(List.of(_inHand));
    }
    if (name == #cartTotals) return Future<CartTotals>.value(_totals);
    if (name == #listDrafts) return Future<List<DraftView>>.value(drafts);
    if (name == #restoreDraft) {
      _inHand
        ..clear()
        ..add(_cartLine('latte', 'Latte', 4500, 1));
      return Future<List<CartLineView>>.value(List.of(_inHand));
    }
    if (name == #seatTable) {
      seated.add(invocation.namedArguments[#tableId]! as String);
      return Future<void>.value();
    }
    if (name == #floorLayout) {
      if (seated.isEmpty) return Future<FloorLayoutView>.value(_layout);
      return Future<FloorLayoutView>.value(
        FloorLayoutView(
          sections: _layout.sections,
          tables: [
            for (final t in _layout.tables)
              if (seated.contains(t.id))
                _table(
                  id: t.id,
                  label: t.label,
                  x: t.posX,
                  y: t.posY,
                  status: 'seated',
                  seats: t.seats,
                  shape: t.shape,
                )
              else
                t,
          ],
        ),
      );
    }
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
  _cartContextTests();
  _cartFlightTests();
  _tableOrderTests();
  setUpAll(_loadFonts);

  // A language switch reaches a screen pushed two routes deep — its words AND
  // its direction — with no restart and no navigation. The Settings sheet is
  // where a teller switches, and it sits on top of exactly this kind of stack.
  testWidgets('switching language re-words and mirrors a deep pushed route', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = _ipad;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final fake = _FakeBridge();
    final container = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            final rtl = ref.watch(localeProvider.select((s) => s.rtl));
            return MaterialApp(
              theme: MadarTheme.light(),
              // The shell's own arrangement: direction ABOVE the navigator.
              builder: (context, child) => Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: child!,
              ),
              home: const FloorScreen(),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Floor → the table's Bill: a pushed route over the floor.
    await tester.tap(find.text('T2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Subtotal'), findsOneWidget);
    BuildContext billContext() => tester.element(find.text('Subtotal').first);
    expect(Directionality.of(billContext()), TextDirection.ltr);
    expect(find.text('Floor', skipOffstage: false), findsWidgets);

    container.read(localeProvider.notifier).set('ar');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Subtotal'), findsNothing);
    final subtotal = find.text('المجموع الفرعي');
    expect(subtotal, findsOneWidget, reason: 'the pushed Bill re-worded');
    expect(
      Directionality.of(tester.element(subtotal)),
      TextDirection.rtl,
      reason: 'the pushed Bill mirrored',
    );
    // And the floor under it, not only the route in front.

    // And the floor UNDER it, once it is shown again. (Riverpod pauses a
    // route's watches while it is covered, so the floor re-words as it is
    // revealed rather than while hidden — nobody can see the difference.)
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Floor'), findsNothing);
    expect(find.text('الصالة'), findsWidgets);
    await tester.tap(find.text('T2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    container.read(localeProvider.notifier).set('en');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Subtotal'), findsOneWidget);
    expect(Directionality.of(billContext()), TextDirection.ltr);
  });

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
      // `SellScreen.forTable`, not the TAB. The tab is the counter and aims
      // the cart back at takeaway every time it is shown — which is the
      // whole point of the split: a teller who tapped a table, thought
      // better of it and came back to Sell is no longer silently ringing up
      // for that table.
      final container = await _mount(
        tester,
        screen: const SellScreen.forTable(),
        size: _ipad,
      );
      await container.read(orderProvider.notifier).pointCartAtTable('t2', 'T2');
      container.read(orderProvider.notifier).selectTicket('tk-1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('T2 · Round 3'), findsWidgets);
      await _capture(tester, 'sell-round-ipad');
    });

    testWidgets('the Sell TAB always comes back to takeaway', (tester) async {
      // The report: tap a table, leave without firing, return to Sell — and
      // you are still on that table with nothing saying so. The table keeps
      // its own cart in the core, so nothing is lost either.
      final container = await _mount(
        tester,
        screen: const SellScreen(),
        size: _ipad,
      );
      await container.read(orderProvider.notifier).pointCartAtTable('t2', 'T2');
      await tester.pump();
      expect(container.read(orderProvider).cartTableId, 't2');

      // What the tab does on every entry.
      await container.read(orderProvider.notifier).pointCartAtTakeaway();
      await tester.pump();
      expect(
        container.read(orderProvider).cartTableId,
        isNull,
        reason: 'the Sell tab is takeaway and only takeaway',
      );
      expect(container.read(orderProvider).cartTableLabel, isNull);

      // And the two constructors really are two different errands.
      expect(const SellScreen().forTable, isFalse);
      expect(const SellScreen.forTable().forTable, isTrue);
    });

    testWidgets("a table's Sell pushed over the Sell tab: no duplicate "
        'cart anchors, the flight lands on the visible cart', (tester) async {
      await _mount(tester, screen: const SellScreen(), size: _ipad);
      final tab = tester.element(find.byType(SellScreen));
      Navigator.of(tab).push(
        MaterialPageRoute<void>(builder: (_) => const SellScreen.forTable()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      final screens = find.byType(SellScreen, skipOffstage: false);
      expect(screens, findsNWidgets(2));
      final pads = find.byType(CartAnchorPad, skipOffstage: false);
      final anchors = {for (final e in pads.evaluate()) CartAnchors.maybeOf(e)};
      expect(anchors.length, 2, reason: 'one set per screen');
      final visible = CartAnchors.maybeOf(
        tester.element(find.byType(CartAnchorPad)),
      );
      expect(visible!.center(), isNotNull);
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
      // The bill's own breakdown, with the TOTAL as the hero — the figure the
      // drawer collects. The screen used to show the subtotal as though it
      // were the total, and Charge to say the same wrong number.
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('Tax 14%'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('EGP 199.50'), findsWidgets);
      await _capture(tester, 'bill-ipad');
    });

    testWidgets('tapping a live line offers to take it off the bill', (
      tester,
    ) async {
      await _mount(
        tester,
        screen: const BillScreen(ticketId: 'tk-1'),
        size: _ipad,
      );
      // A voided line is history — nothing to tap.
      final voided = find.ancestor(
        of: find.text('1× Cake'),
        matching: find.byType(MadarRow),
      );
      expect(tester.widget<MadarRow>(voided).onTap, isNull);

      await tester.tap(find.text('2× Latte'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // The bill's own void sheet, saying which plate is coming off.
      expect(find.text('2× Latte'), findsWidgets);
      expect(find.textContaining('T-0412 · 2× Latte'), findsOneWidget);
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

/// THE report: "seating parties is fundamentally broken — if you have a cart
/// with items already and you open a new table, it's already there. It's
/// shared between them."
///
/// The core keeps one cart per context (takeaway, or a table) and the host
/// only switches which one is in hand. Nothing is parked, cleared or copied
/// to fake the isolation any more.
void _cartContextTests() {
  List<String> inHand(ProviderContainer c) => [
    for (final l in c.read(orderProvider).cartLines) '${l.name}x${l.qty}',
  ];

  testWidgets('every table and the counter keep their own cart', (
    tester,
  ) async {
    final bridge = _FakeBridge();
    final container = await _mount(
      tester,
      screen: const SellScreen.forTable(),
      size: _ipad,
      bridge: bridge,
    );
    final notifier = container.read(orderProvider.notifier);
    await tester.pump();
    final takeaway = inHand(container);
    expect(takeaway, isNotEmpty, reason: 'the counter has unfired work');

    // Add to T1.
    await notifier.pointCartAtTable('t1', 'T1');
    expect(inHand(container), isEmpty, reason: 'T1 starts with its own cart');
    await notifier.addToCart(_items.first);
    await notifier.addToCart(_items.first);
    final t1 = inHand(container);
    expect(t1, ['${_items.first.name}x2']);

    // T2 is empty.
    await notifier.pointCartAtTable('t2', 'T2');
    expect(container.read(orderProvider).cartTableId, 't2');
    expect(inHand(container), isEmpty);

    // Takeaway is its own, untouched.
    await notifier.pointCartAtTakeaway();
    expect(container.read(orderProvider).cartTableId, isNull);
    expect(inHand(container), takeaway);

    // Back to T1: its items are there.
    await notifier.pointCartAtTable('t1', 'T1');
    expect(inHand(container), t1);

    // Fire T1: T1 starts fresh, takeaway untouched.
    expect(await notifier.fireOrAddRound(tableId: 't1'), isTrue);
    expect(inHand(container), isEmpty);
    expect(container.read(orderProvider).cartTableId, 't1');
    await notifier.pointCartAtTakeaway();
    expect(inHand(container), takeaway);

    expect(bridge.parked, isEmpty, reason: 'switching never parks');
    expect(bridge.cleared, 0, reason: 'switching never clears');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets("a table's parked order resumed from the Sell tab opens that "
      "table's own screen; the tab stays takeaway", (tester) async {
    final bridge = _FakeBridge(
      drafts: const [
        DraftView(
          id: 'd-t5',
          name: '',
          itemCount: 1,
          totalMinor: 4500,
          createdAt: '2026-09-12T18:40:00Z',
          tableId: 't5',
          tableLabel: 'T5',
          lockedByOther: false,
        ),
      ],
    );
    final container = await _mount(
      tester,
      screen: const SellScreen(),
      size: _ipad,
      bridge: bridge,
    );
    await tester.pump();
    final takeaway = inHand(container);
    bool pushedForTable(Widget w) => w is SellScreen && w.forTable;

    await tester.tap(find.text('T5'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byWidgetPredicate(pushedForTable), findsOneWidget);
    expect(container.read(orderProvider).cartTableId, 't5');
    expect(bridge.parked, isEmpty, reason: 'the takeaway cart is not parked');
    expect(bridge.carts[null], isNotEmpty);

    Navigator.of(tester.element(find.byWidgetPredicate(pushedForTable))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byWidgetPredicate(pushedForTable), findsNothing);
    expect(
      container.read(orderProvider).cartTableId,
      isNull,
      reason: 'the Sell tab is takeaway and only takeaway',
    );
    expect(inHand(container), takeaway);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('seating a booking and picking a table go through the switch', (
    tester,
  ) async {
    final bridge = _FakeBridge();
    final container = await _mount(
      tester,
      screen: const SellScreen.forTable(),
      size: _ipad,
      bridge: bridge,
    );
    final notifier = container.read(orderProvider.notifier);
    await tester.pump();
    final takeaway = inHand(container);

    await notifier.setCartTable('t3', 'T3');
    expect(bridge.context, 't3');
    expect(inHand(container), isEmpty, reason: 'no takeaway lines leak in');

    await notifier.setCartTable(null, null);
    expect(inHand(container), takeaway);
  });

  testWidgets('re-tapping the same table does not churn the cart', (
    tester,
  ) async {
    final bridge = _FakeBridge();
    final container = await _mount(
      tester,
      screen: const SellScreen.forTable(),
      size: _ipad,
      bridge: bridge,
    );
    final notifier = container.read(orderProvider.notifier);
    await tester.pump();

    await notifier.pointCartAtTable('t2', 'T2');
    await notifier.addToCart(_items.first);
    await notifier.pointCartAtTable('t2', 'T2');

    expect(bridge.parked, isEmpty);
    expect(bridge.cleared, 0);
    expect(inHand(container), ['${_items.first.name}x1']);
    expect(container.read(orderProvider).cartTableId, 't2');
  });
}

/// THE freeze: "pressing a table, seating a party, then Add order routes to
/// the menu and instantly freezes." The seated sheet's button asks the sheet
/// to close and pushes the table's Sell screen at once; the sheet's delayed
/// pop then took down the screen ON TOP of it, not itself — leaving the card
/// off-screen under a full-bleed scrim that had already dismissed, so no tap
/// ever reached anything again.
void _tableOrderTests() {
  bool pushedForTable(Widget w) => w is SellScreen && w.forTable;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> expectLiveTableSell(
    WidgetTester tester,
    _FakeBridge bridge,
  ) async {
    int lines() => bridge.carts.values.fold(0, (n, l) => n + l.length);
    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate(pushedForTable), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('_MadarSheetPage'),
        skipOffstage: false,
      ),
      findsNothing,
      reason: 'no sheet lingers under or over the table screen',
    );
    final before = lines();
    await tester.tap(find.text('Latte').first);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(lines(), greaterThan(before), reason: 'the table screen takes taps');
    await tester.pump(const Duration(seconds: 5));
  }

  for (final (name, size) in [('iPad', _ipad), ('phone', _phone)]) {
    testWidgets('a seated table: Take an order opens a live table screen '
        'on $name', (tester) async {
      final bridge = _FakeBridge();
      await _mount(
        tester,
        screen: const FloorScreen(),
        size: size,
        bridge: bridge,
      );
      await tester.tap(find.text('T1'));
      await settle(tester);
      await tester.tap(find.text('Take an order'));
      await settle(tester);
      await expectLiveTableSell(tester, bridge);
    });

    testWidgets('a free table: Seat, then Take an order on $name', (
      tester,
    ) async {
      final bridge = _FakeBridge();
      await _mount(
        tester,
        screen: const FloorScreen(),
        size: size,
        bridge: bridge,
      );
      await tester.tap(find.text('T6'));
      await settle(tester);
      await tester.tap(find.text('Seat'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('T6'));
      await settle(tester);
      await tester.tap(find.text('Take an order'));
      await settle(tester);
      await expectLiveTableSell(tester, bridge);
    });
  }
}

// ── the add-to-cart flight ─────────────────────────────────────────────────

const _combo = BundleView(
  id: 'combo',
  name: 'Breakfast combo',
  priceMinor: 9000,
  isAvailable: true,
  components: [
    BundleComponentView(
      itemId: 'croissant',
      itemName: 'Croissant',
      quantity: 1,
    ),
  ],
);

/// The anchors of the cart actually on screen (a pushed table Sell hides the
/// tab's underneath it).
CartAnchors _visibleAnchors(WidgetTester tester) =>
    CartAnchors.maybeOf(tester.element(find.byType(CartAnchorPad).first))!;

/// Pumps until the flight's dot is in the overlay, follows it to the end and
/// asserts it LEFT [from] (when given), travelled, finished on the anchor,
/// left the overlay and made the cart catch it.
Future<void> _expectFlight(
  WidgetTester tester, {
  Offset? from,
  String? capture,
}) async {
  final anchors = _visibleAnchors(tester);
  final caught = anchors.catchTick.value;
  final dot = find.byKey(cartFlightDotKey);
  for (var i = 0; i < 40 && dot.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 5));
  }
  expect(dot, findsOneWidget, reason: 'the flight OverlayEntry is inserted');
  final to = anchors.center()!;
  final start = tester.getCenter(dot);
  if (from != null) {
    expect((start - from).distance, lessThan(6), reason: 'launched at origin');
  }
  var last = start;
  var mid = false;
  while (dot.evaluate().isNotEmpty) {
    last = tester.getCenter(dot);
    await tester.pump(const Duration(milliseconds: 10));
    if (!mid && capture != null && dot.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 200));
      mid = true;
      await _capture(tester, capture);
    }
  }
  final span = (to - start).distance;
  expect(span, greaterThan(40), reason: 'it flies somewhere, not in place');
  expect(
    (last - to).distance,
    lessThan(span * 0.03 + 3),
    reason: 'the dot ends on the cart anchor',
  );
  expect(anchors.catchTick.value, caught + 1, reason: 'the cart catches it');
}

void _cartFlightTests() {
  group('the add-to-cart flight', () {
    setUpAll(_loadFonts);
    for (final (device, size) in [('ipad', _ipad), ('phone', _phone)]) {
      for (final forTable in [false, true]) {
        final where = forTable ? 'a table Sell' : 'the Sell tab';
        Future<void> open(WidgetTester tester, {_FakeBridge? bridge}) async {
          await _mount(
            tester,
            screen: const SellScreen(),
            size: size,
            bridge: bridge,
          );
          if (!forTable) return;
          Navigator.of(tester.element(find.byType(SellScreen))).push(
            MaterialPageRoute<void>(
              builder: (_) => const SellScreen.forTable(),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
        }

        testWidgets('tile quick-add on $where, $device', (tester) async {
          await open(tester);
          final tile = find.widgetWithText(SellTile, 'Mocha');
          final origin = tester.getCenter(tile);
          await tester.tap(tile);
          await _expectFlight(
            tester,
            from: origin,
            capture: forTable ? null : 'sell-flight-$device',
          );
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
        });

        testWidgets('item sheet Add on $where, $device', (tester) async {
          await open(tester);
          await tester.longPress(find.widgetWithText(SellTile, 'Mocha'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          final sheet = find.byType(ItemDetailSheet);
          expect(sheet, findsOneWidget);
          await tester.tap(
            find.descendant(of: sheet, matching: find.byType(MadarButton)).last,
          );
          await _expectFlight(tester);
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.byType(ItemDetailSheet), findsNothing);
        });

        testWidgets('bundle sheet Add on $where, $device', (tester) async {
          await open(tester, bridge: _FakeBridge(bundles: const [_combo]));
          await tester.tap(find.byType(MadarChip).last);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.text('Breakfast combo').last);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          final sheet = find.byType(BundleDetailSheet);
          expect(sheet, findsOneWidget);
          await tester.tap(
            find.descendant(of: sheet, matching: find.byType(MadarButton)).last,
          );
          await _expectFlight(tester);
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.byType(BundleDetailSheet), findsNothing);
        });
      }
    }

    testWidgets('a manual sync re-reads the menu the Sell screen holds', (
      tester,
    ) async {
      final fake = _FakeBridge();
      final container = await _mount(
        tester,
        screen: const SellScreen(),
        size: _ipad,
        bridge: fake,
      );
      final before = fake.menuReads;
      container.read(catalogTickProvider.notifier).bump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(fake.menuReads, greaterThan(before));
    });

    for (final (device, size) in [('ipad', _ipad), ('phone', _phone)]) {
      testWidgets('selected cards in the dark, $device', (tester) async {
        await _mount(
          tester,
          screen: const SellScreen(),
          size: size,
          dark: true,
        );
        await _capture(tester, 'sell-$device-dark');
      });
    }
  });
}
