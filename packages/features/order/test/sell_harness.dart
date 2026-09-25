// A copy of redesign_render_test.dart's fixtures and harness, for the Sell
// redesign matrix (sell_render_test.dart) — with the app's Locale installed so
// money and dates format in Arabic exactly as they do on a device.
part of 'sell_render_test.dart';

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
  _FakeBridge({this.rtl = false, this.tillOpen = true})
    : role = 'teller',
      drafts = _drafts;

  final String role;

  /// The parked orders the strip lists.
  final List<DraftView> drafts;

  /// Mutable: `setLocale` flips it, so a test can switch language mid-flight.
  bool rtl;
  final bool tillOpen;

  /// The table each park landed on, in order — null means the counter.
  final List<String?> parked = [];

  /// How many times the menu was read from the core.
  int menuReads = 0;

  /// The tables parked orders were moved to.
  final List<String?> assigned = [];

  /// The parked orders discarded, by id.
  final List<String> discarded = [];

  /// How many times a cart was emptied.
  int cleared = 0;

  /// The core's carts, one per context (`null` = takeaway) — the fake keeps
  /// them apart exactly the way the core does. There is no active context:
  /// every call names its own.
  final Map<String?, List<CartLineView>> carts = {null: List.of(_cart)};

  /// Each context's meta, as the core persists it.
  final Map<String?, CartMeta> metas = {};

  /// Tables seated during the test — the floor reads them back seated.
  final Set<String> seated = {};

  /// The cart lines a kitchen chit was built for, by line key.
  final List<String> chitsBuilt = [];

  /// Chits sent to a printer, as (host, bytes).
  final List<(String, List<int>)> chitsSent = [];

  /// Each context's per-line kitchen notes, by line key — mirrors the
  /// core's kv-joined [CartLineView.kitchenNote].
  final Map<String?, Map<String, String>> lineKitchenNotes = {};

  /// Each context's cart-level kitchen note.
  final Map<String?, String> cartKitchenNotes = {};

  /// How many times the whole cart was printed to the kitchen.
  int cartKitchenChitsBuilt = 0;

  /// Bytes sent for a whole-cart kitchen print, via the till transport.
  final List<List<int>> cartChitsSent = [];

  List<CartLineView> _cartOf(Invocation i) =>
      carts[i.namedArguments[#tableId] as String?] ??= [];

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
    if (name == #cartNote) {
      return Future<String?>.value('Birthday — bring the cake last');
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
    if (name == #assignDraftTable) {
      assigned.add(invocation.namedArguments[#tableId] as String?);
      return Future<void>.value();
    }
    if (name == #discardDraft) {
      discarded.add(invocation.namedArguments[#id] as String);
      return Future<void>.value();
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
    // No printer configured: a fired round prints nothing.
    if (name == #deviceConfig) {
      return const DeviceConfigView(reconfiguring: false, configured: true);
    }
    if (name == #cartAdd) {
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
      _cartOf(invocation).clear();
      return Future<TicketFiredView>.value(
        const TicketFiredView(ticketId: 'tk-new', queuedOffline: false),
      );
    }
    // One cart line's chit: the core routes it to the Grill's printer, so a
    // print lands in `sendToPrinter` where the test can count it.
    if (name == #cartLineChit) {
      final key = invocation.namedArguments[#lineKey] as String;
      chitsBuilt.add(key);
      return Future<CartLineChit>.value(
        CartLineChit(
          chit: KitchenSlip(
            at: '13:05',
            topNotes: const [],
            items: [KitchenSlipItem(item: key, qty: 1, modifiers: const [])],
          ),
          preview: [
            const ChitLineView(
              text: 'KITCHEN',
              centered: true,
              bold: true,
              large: false,
            ),
            ChitLineView(
              text: '1x $key',
              centered: false,
              bold: true,
              large: true,
            ),
          ],
          bytes: Uint8List.fromList(const [0x1b, 0x40]),
          target: const ChitPrinterTarget(
            stationName: 'Grill',
            host: '10.0.0.5',
            port: 9100,
          ),
        ),
      );
    }
    if (name == #sendToPrinter) {
      chitsSent.add((
        invocation.namedArguments[#host] as String,
        invocation.namedArguments[#bytes] as List<int>,
      ));
      return Future<void>.value();
    }
    if (name == #cartLines) {
      final tableId = invocation.namedArguments[#tableId] as String?;
      final notes = lineKitchenNotes[tableId] ?? const {};
      CartLineView withNote(CartLineView l) {
        final note = notes[l.key];
        if (note == null) return l;
        return CartLineView(
          dealCutMinor: 0,
          kind: 'item',
          parts: const [],
          key: l.key,
          itemId: l.itemId,
          name: l.name,
          sizeLabel: l.sizeLabel,
          addons: l.addons,
          optionals: l.optionals,
          notes: l.notes,
          unitPriceMinor: l.unitPriceMinor,
          qty: l.qty,
          lineTotalMinor: l.lineTotalMinor,
          kitchenNote: note,
        );
      }

      return Future<List<CartLineView>>.value([
        for (final l in _cartOf(invocation)) withNote(l),
      ]);
    }
    if (name == #cartSetLineKitchenNote) {
      final tableId = invocation.namedArguments[#tableId] as String?;
      final lineKey = invocation.namedArguments[#lineKey] as String;
      final note = invocation.namedArguments[#note] as String?;
      final map = lineKitchenNotes[tableId] ??= {};
      if (note == null) {
        map.remove(lineKey);
      } else {
        map[lineKey] = note;
      }
      return Future<void>.value();
    }
    if (name == #cartClearLineKitchenNote) {
      final tableId = invocation.namedArguments[#tableId] as String?;
      final lineKey = invocation.namedArguments[#lineKey] as String;
      lineKitchenNotes[tableId]?.remove(lineKey);
      return Future<void>.value();
    }
    if (name == #cartSetKitchenNote) {
      final tableId = invocation.namedArguments[#tableId] as String?;
      final note = invocation.namedArguments[#note] as String?;
      if (note == null) {
        cartKitchenNotes.remove(tableId);
      } else {
        cartKitchenNotes[tableId] = note;
      }
      return Future<void>.value();
    }
    if (name == #cartKitchenNote) {
      return Future<String?>.value(
        cartKitchenNotes[invocation.namedArguments[#tableId] as String?],
      );
    }
    if (name == #cartClearKitchenNote) {
      cartKitchenNotes.remove(invocation.namedArguments[#tableId] as String?);
      return Future<void>.value();
    }
    if (name == #cartClearAllKitchenNotes) {
      final tableId = invocation.namedArguments[#tableId] as String?;
      cartKitchenNotes.remove(tableId);
      lineKitchenNotes[tableId]?.clear();
      return Future<void>.value();
    }
    // The whole cart as one kitchen chit — always the till printer, so the
    // test only checks it was asked to build one (never routed by station).
    if (name == #cartKitchenChit) {
      cartKitchenChitsBuilt += 1;
      final lines = _cartOf(invocation);
      final tableId = invocation.namedArguments[#tableId] as String?;
      final cartNote = cartKitchenNotes[tableId];
      return Future<CartKitchenChit>.value(
        CartKitchenChit(
          slip: KitchenSlip(
            at: '13:05',
            topNotes: cartNote == null ? const [] : [cartNote],
            items: [
              for (final l in lines)
                KitchenSlipItem(item: l.name, qty: l.qty, modifiers: const []),
            ],
          ),
          cartNote: cartNote,
          bytes: Uint8List.fromList(const [0x1b, 0x40]),
          preview: [
            for (final l in lines)
              ChitLineView(
                text: '${l.qty}x ${l.name}',
                centered: false,
                bold: true,
                large: true,
              ),
          ],
        ),
      );
    }
    if (name == #cartTotals) return Future<CartTotals>.value(_totals);
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
          locale: Locale(fake.rtl ? 'ar' : 'en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
  final error = tester.takeException();
  // Rendering: the picture is written BEFORE the layout check, so a frame
  // that overflowed can be looked at (the stripe says where).
  if (_render) await _writeFrame(tester, name);
  expect(error, isNull, reason: '$name laid out cleanly');
}

Future<void> _writeFrame(WidgetTester tester, String name) async {
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
