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
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/feature_order.dart';
import 'package:feature_order/src/cart_anchor.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:feature_order/src/sell_cart.dart';
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
      kind: 'item',
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
  CategoryView(id: 'hot', name: 'Hot', isActive: true, displayOrder: 0),
  CategoryView(id: 'cold', name: 'Cold', isActive: true, displayOrder: 0),
  CategoryView(id: 'food', name: 'Food', isActive: true, displayOrder: 0),
];

CartLineView _cartLine(String id, String name, int price, int qty) =>
    CartLineView(
      dealCutMinor: 0,
      kind: 'item',
      parts: const [],
      key: 'k-$id',
      itemId: id,
      name: name,
      addons: const [],
      optionals: const [],
      unitPriceMinor: price,
      qty: qty,
      lineTotalMinor: price * qty,
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
  isCombo: false,
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
    ready: true,
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
      serviceChargeTaxable: true,
      serviceChargeWaivedMinor: 0,
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
    ready: false,
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
    ready: false,
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
    byOther: false,
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
  'sell.takeaway': 'Pickup',
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
  'sell.takeaway': 'استلام',
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
    this.tillOpen = true,
    this.drafts = _drafts,
  });

  final String role;

  /// The parked orders the strip lists.
  final List<DraftView> drafts;

  /// Mutable: `setLocale` flips it, so a test can switch language mid-flight.
  bool rtl;
  bool tillOpen;

  /// The table each park landed on, in order — null means the counter.
  final List<String?> parked = [];

  /// How many times the menu was read from the core.
  int menuReads = 0;

  /// Items whose options now include a required pick (a sync can add one).
  final Set<String> requiredFor = {};

  /// How many quick adds reached the core's cart.
  int cartAdds = 0;

  /// The open bills as the local store holds them now.
  List<TicketView> tickets = _tickets;

  /// Manual syncs asked for (a person's pull), and what landing one does to
  /// the local rows.
  int syncs = 0;
  void Function()? onSync;

  /// How many times a cart was emptied.
  int cleared = 0;

  /// The core's carts, one per context (`null` = takeaway) — the fake keeps
  /// them apart exactly the way the core does. Nothing is ever active.
  final Map<String?, List<CartLineView>> carts = {null: List.of(_cart)};

  /// Each context's persisted meta.
  final Map<String?, CartMeta> metas = {};

  /// The signed-in person; a teller swap changes it.
  String userId = 'u-1';

  /// Every fire, as (context, booking) — which cart went to the kitchen.
  final List<(String?, String?)> fired = [];

  /// Rounds added, as (context, ticket).
  final List<(String?, String)> rounds = [];

  /// Table statuses written to the local mirror, as (table, status).
  final List<(String, String)> statuses = [];

  /// Tables seated during the test — the floor reads them back seated.
  final Set<String> seated = {};

  List<CartLineView> _cartOf(Invocation i) =>
      carts[i.namedArguments[#tableId] as String?] ??= [];

  /// A sign-out: the core parks every non-empty cart under its author
  /// (queue.rs, tested there) and leaves every context empty for the next
  /// person; the fake only needs the empty contexts.
  void signOut(String nextUser) {
    carts.clear();
    metas.clear();
    userId = nextUser;
  }

  TillView? get _till => tillOpen
      ? const TillView(
          id: 'sh-1',
          branchId: 'br-1',
          tellerId: 'u-1',
          tellerName: 'Sara',
          openingCashMinor: 85000,
          openedAt: '2026-09-12T15:02:00Z',
          status: 'open',
          isOpen: true,
          verification: 'server',
          openedWhileAnotherOpen: false,
        )
      : null;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final name = invocation.memberName;
    if (name == #tr) {
      final key = invocation.namedArguments[#key] as String? ?? '';
      // The core's REAL tables first (read out of i18n.rs), so the PNGs show
      // the words that ship; the fixtures only cover a key the core lacks.
      // A missing key comes back as the key, exactly as the core does.
      final real = coreWord(key, arabic: rtl);
      if (real != key) return real;
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
        userId: userId,
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
    // The one owner's sync read: this person's OWN open till, or none.
    if (name == #ownOpenTill) {
      final t = _till;
      return (t?.isOpen ?? false) ? t : null;
    }
    if (name == #currentTill || name == #refreshTill) {
      return Future<TillView?>.value(_till);
    }
    if (name == #listCategories) {
      return Future<List<CategoryView>>.value(_categories);
    }
    if (name == #listMenuItems) {
      menuReads++;
      return Future<List<MenuItemView>>.value(_items);
    }
    // Retargeting the cart parks whatever is in it first and may clear it —
    // both are bridge calls the fake has to answer or the whole flow throws.
    // Recorded, because the ORDER of them is the fix: park, clear, adopt.
    if (name == #holdCartOnTable) {
      parked.add(invocation.namedArguments[#ontoTableId] as String?);
      _cartOf(invocation).clear();
      return Future<bool>.value(false);
    }
    if (name == #cartClear) {
      cleared += 1;
      _cartOf(invocation).clear();
      return Future<void>.value();
    }
    if (name == #cartMeta) {
      return Future<CartMeta>.value(
        metas[invocation.namedArguments[#tableId] as String?] ??
            const CartMeta(name: ''),
      );
    }
    if (name == #cartSetMeta) {
      metas[invocation.namedArguments[#tableId] as String?] =
          invocation.namedArguments[#meta]! as CartMeta;
      return Future<void>.value();
    }
    if (name == #seatBooking || name == #completeDraft) {
      return Future<void>.value();
    }
    if (name == #mirrorTableStatus) {
      statuses.add((
        invocation.namedArguments[#tableId]! as String,
        invocation.namedArguments[#status]! as String,
      ));
      return Future<void>.value();
    }
    if (name == #addTicketRound) {
      rounds.add((
        invocation.namedArguments[#tableId] as String?,
        invocation.namedArguments[#ticketId]! as String,
      ));
      _cartOf(invocation).clear();
      metas.remove(invocation.namedArguments[#tableId]);
      return Future<TicketFiredView>.value(
        const TicketFiredView(ticketId: 'tk-1', queuedOffline: false),
      );
    }
    // No printer configured: a fired round prints nothing.
    if (name == #deviceConfig) {
      return const DeviceConfigView(reconfiguring: false, configured: true);
    }
    if (name == #cartAdd) {
      cartAdds++;
      final id = invocation.namedArguments[#itemId] as String;
      final label = invocation.namedArguments[#name] as String;
      final minor = invocation.namedArguments[#unitPriceMinor] as int;
      final i = _cartOf(invocation).indexWhere((l) => l.itemId == id);
      if (i < 0) {
        _cartOf(invocation).add(_cartLine(id, label, minor, 1));
      } else {
        final l = _cartOf(invocation)[i];
        _cartOf(invocation)[i] = _cartLine(id, label, minor, l.qty + 1);
      }
      return Future<List<CartLineView>>.value(List.of(_cartOf(invocation)));
    }
    if (name == #validateItemSelections) {
      return Future<List<GroupViolationView>>.value(const []);
    }
    if (name == #cartAddConfigured) {
      final id = invocation.namedArguments[#itemId] as String;
      final item = _items.firstWhere((i) => i.id == id);
      _cartOf(invocation).add(_cartLine(id, item.name, item.basePriceMinor, 1));
      return Future<List<CartLineView>>.value(List.of(_cartOf(invocation)));
    }
    if (name == #fireTicket) {
      fired.add((
        invocation.namedArguments[#tableId] as String?,
        invocation.namedArguments[#bookingId] as String?,
      ));
      _cartOf(invocation).clear();
      metas.remove(invocation.namedArguments[#tableId]);
      return Future<TicketFiredView>.value(
        const TicketFiredView(ticketId: 'tk-new', queuedOffline: false),
      );
    }
    if (name == #cartLines) {
      return Future<List<CartLineView>>.value(List.of(_cartOf(invocation)));
    }
    if (name == #cartTotals) {
      // An emptied cart counts nothing — the phone bar hides on zero.
      final lines = _cartOf(invocation);
      return Future<CartTotals>.value(
        lines.isEmpty
            ? const CartTotals(
                itemCount: 0,
                subtotalMinor: 0,
                discountMinor: 0,
                taxMinor: 0,
                serviceChargeMinor: 0,
                totalMinor: 0,
              )
            : _totals,
      );
    }
    if (name == #decideDraftAct) {
      return const ActDecisionView(outcome: 'allow', reason: '');
    }
    if (name == #listDrafts) return Future<List<DraftView>>.value(drafts);
    if (name == #switchToDraft) {
      // What the one core call does: park the cart in hand if asked, then
      // bring the draft in.
      final from = invocation.namedArguments[#fromTableId] as String?;
      final inHand = carts[from] ??= [];
      if (invocation.namedArguments[#parkInHand] != null && inHand.isNotEmpty) {
        parked.add(from);
        inHand.clear();
      }
      final id = invocation.namedArguments[#id] as String;
      final draft = drafts.where((d) => d.id == id).firstOrNull;
      // Into the DRAFT's own context — never over another cart.
      final target = (carts[draft?.tableId] ??= [])
        ..clear()
        ..add(_cartLine('latte', 'Latte', 4500, 1));
      metas[draft?.tableId] = CartMeta(
        name: draft?.name ?? '',
        draftId: id,
        tableLabel: draft?.tableLabel,
      );
      return Future<DraftSwitchView>.value(
        DraftSwitchView(
          lines: List.of(target),
          tableId: draft?.tableId,
          tableLabel: draft?.tableLabel,
          name: draft?.name ?? '',
          createdAt: draft?.createdAt ?? '',
          tableTaken: false,
        ),
      );
    }
    if (name == #previewConfiguredLine) {
      final id = invocation.namedArguments[#itemId] as String;
      final qty = invocation.namedArguments[#qty] as int;
      final item = _items.firstWhere((i) => i.id == id);
      return Future<LinePreviewView>.value(
        LinePreviewView(
          unitTotalMinor: item.basePriceMinor,
          extrasMinor: 0,
          lineTotalMinor: item.basePriceMinor * qty,
        ),
      );
    }
    if (name == #cartBillSoFarMinor) {
      final ticket = invocation.namedArguments[#ticketSubtotalMinor] as int;
      return Future<int>.value(ticket + _totals.subtotalMinor);
    }
    if (name == #restoreDraft) {
      _cartOf(invocation)
        ..clear()
        ..add(_cartLine('latte', 'Latte', 4500, 1));
      return Future<List<CartLineView>>.value(List.of(_cartOf(invocation)));
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
      return Future<List<TicketView>>.value(tickets);
    }
    if (name == #syncNow) {
      syncs++;
      onSync?.call();
      return Future<SyncStatusView>.value(syncStatus());
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
      return SyncStatusView(
        repairedTypes: const [],
        catalogFreshness: const FreshnessView(state: 'fresh'),
        blockedClose: false,
        pendingOutbox: 0,
        deadOutbox: 0,
        blocked: 0,
        freshness: const FreshnessView(state: 'fresh'),
        online: true,
        authPaused: false,
        phase: 'idle',
        assets: AssetSyncView(
          needed: 0,
          missing: 0,
          downloading: false,
          bytesDone: BigInt.zero,
          bytesTotal: BigInt.zero,
        ),
      );
    }
    if (name == #listTillOrders) {
      return Future<List<OrderSummaryView>>.value(const []);
    }
    if (name == #tillStats || name == #tillStatsChecked) {
      return Future<TillStatsView>.value(
        const TillStatsView(salesMinor: 623000, orderCount: 42),
      );
    }
    if (name == #listItemModifierGroups) {
      final id = invocation.namedArguments[#itemId] as String;
      return Future<List<ModifierGroupView>>.value(
        requiredFor.contains(id)
            ? const [
                ModifierGroupView(
                  groupId: 'bread',
                  name: 'Bread',
                  kind: ModifierGroupKind.addon,
                  isRequired: true,
                  minSelections: 1,
                  maxSelections: 1,
                  options: [
                    ModifierOptionView(
                      id: 'white',
                      name: 'White Bread',
                      chargedPriceMinor: 0,
                    ),
                  ],
                ),
              ]
            : const [],
      );
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
  bool shell = false,
  bool reduced = false,
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Directionality(
            textDirection: fake.rtl ? TextDirection.rtl : TextDirection.ltr,
            child: shell
                ? _FakeShell(wide: size == _ipad, screen: screen)
                : screen,
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

    // Floor → the table's Bill: a pushed route over the floor. (The first
    // T2 is the table; the inspector's worklist names it too.)
    await tester.tap(find.text('T2').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // The table's sheet leads to its bill.
    await tester.tap(find.text('Open bill'));
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
    await tester.tap(find.text('T2').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('افتح الفاتورة'));
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
      await _mount(tester, screen: const TakeawaySellScreen(), size: _ipad);
      expect(find.text('Espresso'), findsWidgets);
      expect(find.text('Pickup'), findsWidgets);
      await _capture(tester, 'sell-ipad');
    });

    testWidgets('the counter on a phone: tiles and the bottom bar', (
      tester,
    ) async {
      await _mount(tester, screen: const TakeawaySellScreen(), size: _phone);
      expect(find.text('3 items'), findsOneWidget);
      await _capture(tester, 'sell-phone');
    });

    testWidgets('a round on a bill: on the bill, this round, Fire', (
      tester,
    ) async {
      // The table's OWN screen over the table's own cart; it finds T2's bill
      // by the table.
      final bridge = _FakeBridge();
      bridge.carts['t2'] = [_cartLine('latte', 'Latte', 4500, 1)];
      await _mount(
        tester,
        screen: const TableOrderScreen(tableId: 't2'),
        size: _ipad,
        bridge: bridge,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('T2 · 4 guests'), findsWidgets);
      expect(find.text('Round 3'), findsWidgets);
      await _capture(tester, 'sell-round-ipad');
    });

    testWidgets("a table's screen pushed over the Sell tab: no duplicate "
        'cart anchors, the flight lands on the visible cart', (tester) async {
      await _mount(tester, screen: const TakeawaySellScreen(), size: _ipad);
      final tab = tester.element(find.byType(TakeawaySellScreen));
      Navigator.of(tab).push(
        MaterialPageRoute<void>(
          builder: (_) => const TableOrderScreen(tableId: 't1'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      final screens = find.byType(OrderScreen, skipOffstage: false);
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
        screen: const TakeawaySellScreen(),
        size: _phone,
        bridge: _FakeBridge(tillOpen: false),
      );
      expect(find.text(coreWord('sell.no_shift')), findsOneWidget);
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
      // Free tables are the last band of the phone's worklist.
      await tester.ensureVisible(find.text('T6'));
      await tester.pump();
      await tester.tap(find.text('T6'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('PARTY SIZE'), findsOneWidget);
      expect(find.text('Seat'), findsOneWidget);
      await _capture(tester, 'floor-phone-seat');
    });

    testWidgets('a table with a bill opens the Bill from its sheet', (
      tester,
    ) async {
      await _mount(tester, screen: const FloorScreen(), size: _ipad);
      await tester.tap(find.text('T2').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      // The sheet shows the bill's doors, then the bill.
      expect(find.text('Charge'), findsOneWidget);
      expect(find.text('Table history'), findsOneWidget);
      await tester.tap(find.text('Open bill'));
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

    // Pull to refresh, from the empty state: the manual sync, then the open
    // bills re-read, so a bill fired on another till shows without a tick.
    testWidgets('a pull syncs and shows the bills, even from empty', (
      tester,
    ) async {
      final bridge = _FakeBridge(role: 'waiter')..tickets = const [];
      await _mount(
        tester,
        screen: const BillsScreen(canCharge: false),
        size: _phone,
        bridge: bridge,
      );
      expect(find.text('MINE'), findsNothing);
      bridge.onSync = () => bridge.tickets = _tickets;

      final box = tester.getRect(find.byType(RefreshIndicator).first);
      await tester.flingFrom(
        Offset(box.center.dx, box.top + 24),
        const Offset(0, 400),
        1200,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(bridge.syncs, 1, reason: 'one manual sync per pull');
      expect(find.text('MINE'), findsOneWidget, reason: 'the bills show');
    });
  });
}

/// THE owner decision: takeaway and every table are SEPARATE screens over
/// SEPARATE carts. The Sell tab never shows a table — on launch, on a
/// sign-in, on a tab change, however fast the tabs are switched — and a
/// table's screen never shows takeaway or another table. Nothing is ever
/// "in hand", so nothing can be aimed at the wrong cart.
void _cartContextTests() {
  List<String> linesOf(ProviderContainer c, String? table) => [
    for (final l in c.read(cartProvider(table)).lines) '${l.name}x${l.qty}',
  ];
  int qty(_FakeBridge b, String? table) =>
      (b.carts[table] ?? const []).fold(0, (n, l) => n + l.qty);
  final takeaway = [for (final l in _cart) '${l.name}x${l.qty}'];

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  String? titleOf(WidgetTester tester, Finder screen) => tester
      .widget<MadarPageScaffold>(
        find.descendant(
          of: screen,
          matching: find.byType(MadarPageScaffold, skipOffstage: false),
          skipOffstage: false,
        ),
      )
      .title;

  _FakeBridge withSavedTable() => _FakeBridge()
    ..carts['t2'] = [_cartLine('latte', 'Latte', 4500, 2)]
    ..metas['t2'] = const CartMeta(name: 'Nour', tableLabel: 'T2');

  group('separate carts', () {
    for (final empty in [false, true]) {
      testWidgets('a launch with saved table carts: the Sell tab is takeaway '
          '(${empty ? 'empty' : 'its own lines'})', (tester) async {
        final bridge = withSavedTable();
        if (empty) bridge.carts[null] = [];
        final c = await _mount(
          tester,
          screen: const TakeawaySellScreen(),
          size: _ipad,
          bridge: bridge,
        );
        await settle(tester);
        expect(titleOf(tester, find.byType(OrderScreen)), 'Pickup');
        expect(linesOf(c, null), empty ? isEmpty : takeaway);
        expect(find.textContaining('T2'), findsNothing);
        expect(find.text('Latte'), findsWidgets, reason: 'the menu tile only');
        expect(c.read(cartProvider(null)).name, isNull);
      });
    }

    testWidgets('a launch on the Floor opens no table', (tester) async {
      final bridge = withSavedTable();
      await _mount(
        tester,
        screen: const FloorScreen(),
        size: _ipad,
        bridge: bridge,
      );
      await settle(tester);
      expect(find.byType(OrderScreen), findsNothing);
      expect(qty(bridge, 't2'), 2, reason: "T2's cart is where it was");
    });

    testWidgets('a shift opened after launch moves no cart', (tester) async {
      final bridge = withSavedTable()..tillOpen = false;
      final c = await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      await settle(tester);
      expect(find.byType(SellNoTillNotice), findsOneWidget);
      await c.read(cartProvider('t2').notifier).load();
      bridge.tillOpen = true;
      await c.read(shellProvider.notifier).reconcileTill();
      await settle(tester);
      expect(find.byType(SellNoTillNotice), findsNothing);
      expect(titleOf(tester, find.byType(OrderScreen)), 'Pickup');
      expect(linesOf(c, null), takeaway);
      expect(linesOf(c, 't2'), ['Lattex2']);
    });

    testWidgets('rapid tab switching with a table screen open, x10: titles '
        'and lines hold, and each screen adds to its own cart', (tester) async {
      final bridge = withSavedTable();
      final tabs = GlobalKey<_TwoTabsState>();
      final c = await _mount(
        tester,
        screen: _TwoTabs(key: tabs),
        size: _ipad,
        bridge: bridge,
      );
      await settle(tester);
      for (var i = 0; i < 10; i++) {
        tabs.currentState!.show(i.isEven ? 1 : 0);
        await tester.pump();
      }
      await settle(tester);
      final sell = find.byType(TakeawaySellScreen, skipOffstage: false);
      final table = find.byType(TableOrderScreen, skipOffstage: false);
      expect(titleOf(tester, sell), 'Pickup');
      expect(titleOf(tester, table), 'T2 · 4 guests');
      expect(linesOf(c, null), takeaway);
      expect(linesOf(c, 't2'), ['Lattex2']);

      final before = (qty(bridge, null), qty(bridge, 't2'));
      tabs.currentState!.show(0);
      await settle(tester);
      await tester.tap(find.widgetWithText(SellTile, 'Mocha').hitTestable());
      await settle(tester);
      expect(qty(bridge, null), before.$1 + 1, reason: 'Sell adds to takeaway');
      expect(qty(bridge, 't2'), before.$2);

      tabs.currentState!.show(1);
      await settle(tester);
      await tester.tap(find.widgetWithText(SellTile, 'Mocha').hitTestable());
      await settle(tester);
      expect(qty(bridge, 't2'), before.$2 + 1, reason: 'T2 adds to T2');
      expect(qty(bridge, null), before.$1 + 1);
      expect(titleOf(tester, sell), 'Pickup');
      expect(titleOf(tester, table), 'T2 · 4 guests');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets("a table's parked order resumed from the Sell strip opens "
        "that table's screen; takeaway is untouched", (tester) async {
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
            byOther: false,
          ),
        ],
      );
      final c = await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      await settle(tester);
      await tester.tap(find.text('T5'));
      await settle(tester);
      final pushed = find.byType(TableOrderScreen);
      expect(pushed, findsOneWidget);
      expect(tester.widget<TableOrderScreen>(pushed).tableId, 't5');
      expect(linesOf(c, 't5'), ['Lattex1']);
      expect(bridge.parked, isEmpty, reason: 'the takeaway cart is not parked');
      expect(linesOf(c, null), takeaway);

      Navigator.of(tester.element(pushed)).pop();
      await settle(tester);
      expect(find.byType(TableOrderScreen), findsNothing);
      expect(titleOf(tester, find.byType(OrderScreen)), 'Pickup');
      expect(linesOf(c, null), takeaway);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a counter draft resumed from the strip fills takeaway only', (
      tester,
    ) async {
      final bridge = _FakeBridge();
      final c = await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      await settle(tester);
      await c.read(orderProvider.notifier).resumeDraft('d1', parkInHand: true);
      await settle(tester);
      expect(bridge.parked, [null], reason: 'the order in hand parks first');
      expect(linesOf(c, null), ['Lattex1']);
      expect(c.read(cartProvider(null)).draftId, 'd1');
      expect(find.byType(TableOrderScreen), findsNothing);
    });

    testWidgets('seating a booking puts it on the table cart; its screen '
        'fires it', (tester) async {
      final bridge = _FakeBridge();
      final c = await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      await settle(tester);
      await c
          .read(orderProvider.notifier)
          .seatBooking(
            _table(
              id: 't6',
              label: 'T6',
              x: 0,
              y: 0,
              bookingId: 'bk-1',
              bookingGuest: 'Nour',
            ),
          );
      expect(c.read(cartProvider('t6')).bookingId, 'bk-1');
      expect(c.read(cartProvider('t6')).meta.guestName, 'Nour');
      expect(c.read(cartProvider(null)).bookingId, isNull);

      Navigator.of(tester.element(find.byType(TakeawaySellScreen))).push(
        MaterialPageRoute<void>(
          builder: (_) => const TableOrderScreen(tableId: 't6'),
        ),
      );
      await settle(tester);
      await tester.tap(find.widgetWithText(SellTile, 'Mocha').hitTestable());
      await settle(tester);
      expect(await c.read(cartProvider('t6').notifier).fireOrAddRound(), true);
      await settle(tester);
      expect(bridge.fired, [('t6', 'bk-1')]);
      expect(find.byType(TableOrderScreen), findsNothing, reason: 'it returns');
      expect(linesOf(c, null), takeaway);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('firing a table clears only that table', (tester) async {
      final bridge = _FakeBridge();
      final c = await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      await settle(tester);
      final t1 = c.read(cartProvider('t1').notifier);
      await t1.add(_items.first);
      await t1.add(_items.first);
      expect(linesOf(c, 't1'), ['${_items.first.name}x2']);
      expect(await t1.fireOrAddRound(), isTrue);
      expect(linesOf(c, 't1'), isEmpty);
      expect(linesOf(c, null), takeaway);
      expect(bridge.fired, [('t1', null)]);

      // T2 has a bill: its cart adds a round to it, still alone.
      final t2 = c.read(cartProvider('t2').notifier);
      await t2.add(_items.first);
      expect(await t2.fireOrAddRound(), isTrue);
      expect(bridge.rounds, [('t2', 'tk-1')]);
      expect(linesOf(c, null), takeaway);
      expect(bridge.cleared, 0);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('settling a table sale leaves the table dirty, takeaway as '
        'it was', (tester) async {
      final bridge = _FakeBridge();
      final c = await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      await settle(tester);
      final t1 = c.read(cartProvider('t1').notifier);
      await t1.add(_items.first);
      await t1.onOrderSettled(null);
      expect(bridge.statuses, [('t1', 'dirty')]);
      expect(c.read(orderProvider).pendingTableClear?.tableId, 't1');
      expect(linesOf(c, null), takeaway);
    });

    testWidgets('a realtime tick during the push changes nothing', (
      tester,
    ) async {
      final bridge = withSavedTable();
      final c = await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      await settle(tester);
      Navigator.of(tester.element(find.byType(TakeawaySellScreen))).push(
        MaterialPageRoute<void>(
          builder: (_) => const TableOrderScreen(tableId: 't2'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      c.read(ticketTickProvider.notifier).bump();
      c.read(connectivityPulseProvider.notifier).pulse();
      await settle(tester);
      final sell = find.byType(TakeawaySellScreen, skipOffstage: false);
      expect(titleOf(tester, sell), 'Pickup');
      expect(titleOf(tester, find.byType(TableOrderScreen)), 'T2 · 4 guests');
      expect(linesOf(c, null), takeaway);
      expect(linesOf(c, 't2'), ['Lattex2']);
    });

    test('a restart restores both carts and their meta', () async {
      final bridge = _FakeBridge();
      final first = ProviderContainer(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
      );
      final t1 = first.read(cartProvider('t1').notifier);
      await t1.add(_items.first);
      await t1.updateMeta((m) => cartMetaWith(m, bookingId: 'bk-9', covers: 3));
      await t1.setName('Nour');
      await first.read(cartProvider(null).notifier).setName('Ali');
      first.dispose();

      final again = ProviderContainer(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
      );
      addTearDown(again.dispose);
      await again.read(cartProvider('t1').notifier).load();
      await again.read(cartProvider(null).notifier).load();
      final table = again.read(cartProvider('t1'));
      expect(linesOf(again, 't1'), ['${_items.first.name}x1']);
      expect(table.name, 'Nour');
      expect(table.bookingId, 'bk-9');
      expect(table.meta.covers, 3);
      expect(table.startedAt, isNotNull);
      expect(again.read(cartProvider(null)).name, 'Ali');
      expect(linesOf(again, null), takeaway);
    });

    testWidgets(
      'a teller swap leaves every cart empty in hand; the tab is takeaway',
      (tester) async {
        final bridge = withSavedTable();
        final c = await _mount(
          tester,
          screen: const TakeawaySellScreen(),
          size: _ipad,
          bridge: bridge,
        );
        await settle(tester);
        await c.read(orderProvider.notifier).ensureInit();
        await c.read(cartProvider('t2').notifier).load();
        expect(linesOf(c, 't2'), ['Lattex2']);

        bridge.signOut('u-2');
        await c.read(orderProvider.notifier).ensureInit();
        await settle(tester);
        expect(linesOf(c, null), isEmpty);
        expect(linesOf(c, 't2'), isEmpty);
        expect(c.read(cartProvider('t2')).name, isNull);
        expect(titleOf(tester, find.byType(OrderScreen)), 'Pickup');
      },
    );
  });
}

/// Two tab stacks in an IndexedStack — the shell's shape, without the shell:
/// the Sell tab's root, and a table's order screen standing on another tab.
class _TwoTabs extends StatefulWidget {
  const _TwoTabs({super.key});

  @override
  State<_TwoTabs> createState() => _TwoTabsState();
}

class _TwoTabsState extends State<_TwoTabs> {
  int _index = 0;

  void show(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) => IndexedStack(
    index: _index,
    children: [
      Navigator(
        onGenerateRoute: (_) =>
            MaterialPageRoute<void>(builder: (_) => const TakeawaySellScreen()),
      ),
      Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => const TableOrderScreen(tableId: 't2'),
        ),
      ),
    ],
  );
}

/// THE freeze: "pressing a table, seating a party, then Add order routes to
/// the menu and instantly freezes." The seated sheet's button asks the sheet
/// to close and pushes the table's Sell screen at once; the sheet's delayed
/// pop then took down the screen ON TOP of it, not itself — leaving the card
/// off-screen under a full-bleed scrim that had already dismissed, so no tap
/// ever reached anything again.
void _tableOrderTests() {
  bool pushedForTable(Widget w) => w is OrderScreen && w.tableId != null;

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
      await tester.ensureVisible(find.text('T6').first);
      await tester.pump();
      await tester.tap(find.text('T6').first);
      await settle(tester);
      await tester.tap(find.text('Seat'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      // The table (first); an iPad's inspector names it too.
      await tester.ensureVisible(find.text('T6').first);
      await tester.pump();
      await tester.tap(find.text('T6').first);
      await settle(tester);
      await tester.tap(find.text('Take an order'));
      await settle(tester);
      await expectLiveTableSell(tester, bridge);
    });
  }
}

// ── the add-to-cart flight ─────────────────────────────────────────────────

/// A stand-in for the app shell's chrome around a tab: a top bar, a side rail
/// (wide) or a bottom tab bar (narrow), and the tab's own nested navigator in
/// between — the content area a flight must stay inside.
class _FakeShell extends StatelessWidget {
  const _FakeShell({required this.wide, required this.screen});

  final bool wide;
  final Widget screen;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(key: ValueKey('shellTop'), height: 56),
      Expanded(
        child: Row(
          children: [
            if (wide) const SizedBox(key: ValueKey('shellRail'), width: 80),
            Expanded(
              child: Navigator(
                key: const ValueKey('shellContent'),
                onGenerateRoute: (_) =>
                    MaterialPageRoute<void>(builder: (_) => screen),
              ),
            ),
          ],
        ),
      ),
      if (!wide) const SizedBox(key: ValueKey('shellTabs'), height: 64),
    ],
  );
}

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
  bool inShell = false,
}) async {
  final dot = find.byKey(cartFlightDotKey);
  for (var i = 0; i < 40 && dot.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 5));
  }
  expect(dot, findsOneWidget, reason: 'the flight OverlayEntry is inserted');
  final anchors = _visibleAnchors(tester);
  final caught = anchors.catchTick.value;
  final to = anchors.center()!;
  final start = tester.getCenter(dot);
  if (from != null) {
    expect((start - from).distance, lessThan(6), reason: 'launched at origin');
  }
  var last = start;
  var mid = false;
  final root = tester.state<OverlayState>(find.byType(Overlay).first);
  while (dot.evaluate().isNotEmpty) {
    last = tester.getCenter(dot);
    final overlay = Overlay.of(tester.element(dot));
    expect(overlay, isNot(same(root)), reason: 'the screen overlay, not root');
    if (inShell) {
      final content = tester.getRect(
        find.byKey(const ValueKey('shellContent')),
      );
      final layer = overlay.context.findRenderObject()! as RenderBox;
      final clip = layer.localToGlobal(Offset.zero) & layer.size;
      expect(
        content.expandToInclude(clip),
        content,
        reason: 'the flight is clipped inside the content area',
      );
      for (final chrome in ['shellTop', 'shellRail', 'shellTabs']) {
        final f = find.byKey(ValueKey(chrome));
        if (f.evaluate().isEmpty) continue;
        expect(
          clip.intersect(tester.getRect(f)).isEmpty ||
              clip.intersect(tester.getRect(f)).width <= 0 ||
              clip.intersect(tester.getRect(f)).height <= 0,
          isTrue,
          reason: 'never over the $chrome chrome',
        );
      }
      expect(clip.contains(last), isTrue, reason: 'the dot is on screen');
    }
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

/// [_expectFlight] in a shell, or — reduced motion — the pulse: inserted in
/// the screen's overlay (never root), ON the visible anchor, inside the
/// content area, then the cart's catch. Nothing is replayed afterwards.
Future<void> _expectFlightOrPulse(
  WidgetTester tester, {
  required bool reduced,
  Offset? from,
  String? capture,
}) async {
  if (!reduced) {
    await _expectFlight(tester, from: from, capture: capture, inShell: true);
  } else {
    final dot = find.byKey(cartFlightDotKey);
    for (var i = 0; i < 40 && dot.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(dot, findsOneWidget, reason: 'the pulse OverlayEntry is inserted');
    final anchors = _visibleAnchors(tester);
    final caught = anchors.catchTick.value;
    final root = tester.state<OverlayState>(find.byType(Overlay).first);
    expect(Overlay.of(tester.element(dot)), isNot(same(root)));
    expect((tester.getCenter(dot) - anchors.center()!).distance, lessThan(1));
    final content = tester.getRect(find.byKey(const ValueKey('shellContent')));
    expect(content.contains(tester.getCenter(dot)), isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    expect(dot, findsNothing);
    expect(anchors.catchTick.value, caught + 1);
  }
  await tester.pump(const Duration(milliseconds: 600));
  expect(find.byKey(cartFlightDotKey), findsNothing, reason: 'no replay');
  expect(tester.takeException(), isNull);
}

void _cartFlightTests() {
  group('the add-to-cart flight', () {
    setUpAll(_loadFonts);
    for (final (device, size) in [('ipad', _ipad), ('phone', _phone)]) {
      for (final forTable in [false, true]) {
        final where = forTable ? 'a table Sell' : 'the Sell tab';
        Future<void> open(WidgetTester tester) async {
          await _mount(tester, screen: const TakeawaySellScreen(), size: size);
          if (!forTable) return;
          Navigator.of(tester.element(find.byType(TakeawaySellScreen))).push(
            MaterialPageRoute<void>(
              builder: (_) => const TableOrderScreen(tableId: 't1'),
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
      }
    }

    // The FIRST add to an empty cart: a phone's bar (the landing pad) only
    // mounts once the cart has a line, so the flight used to find no target
    // and fly nothing. Inside a shell, the dot stays in the content area.
    for (final (device, size) in [('ipad', _ipad), ('phone', _phone)]) {
      for (final reduced in [false, true]) {
        final how = reduced ? ', reduced motion' : '';
        _FakeBridge empty() => _FakeBridge()..carts[null] = [];

        testWidgets('empty cart, first tile quick-add flies, $device$how', (
          tester,
        ) async {
          await _mount(
            tester,
            screen: const TakeawaySellScreen(),
            size: size,
            bridge: empty(),
            shell: true,
            reduced: reduced,
          );
          expect(
            find.byType(CartAnchorPad),
            findsNWidgets(size == _ipad ? 1 : 0),
          );
          final tile = find.widgetWithText(SellTile, 'Mocha');
          final origin = tester.getCenter(tile);
          await tester.tap(tile);
          await _expectFlightOrPulse(
            tester,
            reduced: reduced,
            from: origin,
            capture: reduced ? null : 'sell-flight-first-$device',
          );
        });

        testWidgets('empty cart, first item sheet Add flies, $device$how', (
          tester,
        ) async {
          await _mount(
            tester,
            screen: const TakeawaySellScreen(),
            size: size,
            bridge: empty(),
            shell: true,
            reduced: reduced,
          );
          await tester.longPress(find.widgetWithText(SellTile, 'Mocha'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          final sheet = find.byType(ItemDetailSheet);
          await tester.tap(
            find.descendant(of: sheet, matching: find.byType(MadarButton)).last,
          );
          await _expectFlightOrPulse(tester, reduced: reduced);
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.byType(ItemDetailSheet), findsNothing);
        });
      }
    }

    testWidgets('a manual sync re-reads the menu the Sell screen holds', (
      tester,
    ) async {
      final fake = _FakeBridge();
      final container = await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: fake,
      );
      final before = fake.menuReads;
      container.read(catalogTickProvider.notifier).bump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(fake.menuReads, greaterThan(before));
    });

    testWidgets('an item that gains a required pick in a sync opens its sheet '
        'on the next tap, not a stale quick add', (tester) async {
      final fake = _FakeBridge();
      final container = await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: fake,
      );
      // Before the sync: no options, so a tap adds straight to the cart.
      await tester.tap(find.text('Latte').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(fake.cartAdds, 1);
      expect(find.byType(ItemDetailSheet), findsNothing);

      // A sync lands a required Bread pick on the same item.
      fake.requiredFor.add('latte');
      container.read(catalogTickProvider.notifier).bump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The next tap must ask, not reuse the remembered "no sheet".
      await tester.tap(find.text('Latte').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(ItemDetailSheet), findsOneWidget);
      expect(fake.cartAdds, 1, reason: 'no bread picked, nothing added');
    });

    for (final (device, size) in [('ipad', _ipad), ('phone', _phone)]) {
      testWidgets('selected cards in the dark, $device', (tester) async {
        await _mount(
          tester,
          screen: const TakeawaySellScreen(),
          size: size,
          dark: true,
        );
        await _capture(tester, 'sell-$device-dark');
      });
    }
  });
}
