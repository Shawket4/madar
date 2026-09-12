// Renders the three shells to PNG so they can be LOOKED at — the teller's
// and the waiter's, on the iPad they are built for and the phone a waiter
// carries, light and dark, and mirrored in Arabic.
//
// `MADAR_RENDER=true` writes `build/render/shell-*.png`. Without the flag the
// test still mounts every shell at both sizes through the real route host
// and fails on any layout exception, which is the part CI cares about.
//
// The fake bridge's `tr` reads the CORE's own tables (`i18n.rs`), so the
// pictures carry the words a device would show and the test can insist that
// no raw key reaches the screen.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar/app/shell.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

/// The iPad, landscape — the primary target.
const Size _ipad = Size(1194, 834);

/// A phone — the real fallback.
const Size _phone = Size(390, 844);

/// The workspace root, from this package's test working directory.
const _root = '../..';

// ── The core's words ───────────────────────────────────────────────────────

late final Map<String, String> _en;
late final Map<String, String> _ar;

/// The `"key" => "value"` arms of one `fn` in `i18n.rs`, the multi-line
/// `{ "value" }` form included — the same slice the core's own coverage test
/// takes, so the words here are the words a device shows.
Map<String, String> _words(String src, String fnSig) {
  final start = src.indexOf(fnSig);
  if (start < 0) return const {};
  var body = src.substring(start + fnSig.length);
  final end = body.indexOf('\nfn ');
  if (end >= 0) body = body.substring(0, end);
  final arm = RegExp(r'"([a-z0-9_.]+)"\s*=>\s*(?:\{\s*)?"((?:[^"\\]|\\.)*)"');
  return {
    for (final m in arm.allMatches(body))
      m.group(1)!: m.group(2)!.replaceAll(r'\"', '"').replaceAll(r'\n', '\n'),
  };
}

void _loadWords() {
  final file = File('$_root/rust-core/crates/madar-core/src/i18n.rs');
  final src = file.existsSync() ? file.readAsStringSync() : '';
  _en = _words(src, "fn en(key: &str) -> Option<&'static str> {");
  _ar = _words(src, "fn ar(key: &str) -> Option<&'static str> {");
}

// ── Fixtures ───────────────────────────────────────────────────────────────

String _ago(int minutes) => DateTime.now()
    .toUtc()
    .subtract(Duration(minutes: minutes))
    .toIso8601String();

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
    _table(id: 't9', label: 'T9', x: 520, y: 210),
  ],
);

const _emptyLayout = FloorLayoutView(sections: [], tables: []);

DeliveryOrderView _online({
  required String id,
  required String ref,
  required String status,
  required String channel,
  required String name,
  required List<TicketLineView> lines,
  required String at,
}) {
  final subtotal = lines.fold<int>(0, (s, l) => s + l.lineTotalMinor);
  return DeliveryOrderView(
    id: id,
    orderRef: ref,
    channel: channel,
    status: status,
    customerName: name,
    customerPhone: '0100 123 4567',
    address: 'Tower B, 4th floor, unit 12',
    subtotalMinor: subtotal,
    discountMinor: 0,
    deliveryFeeMinor: 1500,
    totalMinor: subtotal + 1500,
    itemCount: lines.fold<int>(0, (s, l) => s + l.qty),
    lines: lines,
    createdAt: at,
    extraPrepMinutes: 0,
    isTerminal: false,
  );
}

final _onlineOrders = <DeliveryOrderView>[
  _online(
    id: 'd-118',
    ref: '#D-118',
    status: 'received',
    channel: 'in_mall',
    name: 'Mona',
    at: _ago(4),
    lines: [
      _line('Halloumi sandwich', 1, 7000, 1, _ago(4)),
      _line('Mint lemonade', 1, 4000, 1, _ago(4)),
    ],
  ),
  _online(
    id: 'd-117',
    ref: '#D-117',
    status: 'preparing',
    channel: 'outside',
    name: 'Karim',
    at: _ago(13),
    lines: [_line('Beef burger', 2, 9000, 1, _ago(13))],
  ),
];

const _deliverySettings = DeliverySettingsView(
  inMallEnabled: true,
  inMallOverride: 'auto',
  inMallFeeMinor: 1500,
  outsideEnabled: true,
  outsideOverride: 'closed',
  prepTimeMinutes: 20,
);

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

ShiftReportView _report({required bool fromServer}) => ShiftReportView(
  tellerName: 'Sara',
  openedAt: _openedAt,
  printedAt: '2026-09-12T19:40:00Z',
  isOpen: true,
  expectedCashMinor: 238000,
  openingCashMinor: 85000,
  openingCashWasEdited: false,
  totalPaymentsMinor: 623000,
  netPaymentsMinor: 623000,
  voidedAmountMinor: 0,
  refundsIssuedMinor: 0,
  refundsIssuedCashMinor: 0,
  refundsIssuedCount: 0,
  cashInRefundedSalesMinor: 0,
  cashMovementsNetMinor: 11000,
  cashInMinor: 20000,
  cashOutMinor: 9000,
  paymentLines: const [
    ShiftReportPaymentLine(
      method: 'Cash',
      isCash: true,
      orderCount: 18,
      totalMinor: 142000,
    ),
    ShiftReportPaymentLine(
      method: 'Card',
      isCash: false,
      orderCount: 24,
      totalMinor: 481000,
    ),
  ],
  cashMovements: const [],
  fromServer: fromServer,
);

const _movements = <CashMovementView>[
  CashMovementView(
    id: 'cm-2',
    amountMinor: 20000,
    note: 'Float top-up',
    movedByName: 'Sara',
    createdAt: '2026-09-12T16:05:00Z',
  ),
  CashMovementView(
    id: 'cm-1',
    amountMinor: -9000,
    note: 'Milk, Seoudi',
    movedByName: 'Sara',
    createdAt: '2026-09-12T15:40:00Z',
  ),
];

List<OrderSummaryView> _orders({required int queued}) => [
  for (var i = 0; i < 42; i++)
    OrderSummaryView(
      id: 'o-$i',
      orderNumber: i < queued ? null : 1000 + i,
      subtotalMinor: 14000,
      taxMinor: 2000,
      totalMinor: 16000,
      paymentLabel: i.isEven ? 'Cash' : 'Card',
      status: i < queued ? 'queued' : 'completed',
      createdAt: _openedAt,
      queued: i < queued,
      tellerName: 'Sara',
      orderType: 'dine_in',
    ),
];

const _outbox = <OutboxItemView>[
  OutboxItemView(
    id: 'ob-1',
    opType: 'ticket_add_round',
    status: 'pending',
    attempts: 1,
    eventAt: '2026-09-12T19:20:00Z',
  ),
  OutboxItemView(
    id: 'ob-2',
    opType: 'open_ticket',
    status: 'pending',
    attempts: 2,
    eventAt: '2026-09-12T19:24:00Z',
  ),
];

// ── The bridge ─────────────────────────────────────────────────────────────

/// Answers what every tab of every shell asks, from the fixtures above.
/// Unknown members answer null, which the screens treat as "nothing".
class _FakeBridge implements MadarBridge {
  _FakeBridge({
    this.role = 'teller',
    this.rtl = false,
    this.shiftOpen = true,
    this.hasFloor = true,
    this.requireTable = false,
    this.online = true,
    this.pending = 0,
    this.failed = 0,
    this.authPaused = false,
    this.clockSkew = 0,
  });

  final String role;
  final bool rtl;
  final bool shiftOpen;
  final bool hasFloor;
  final bool requireTable;
  final bool online;
  final int pending;
  final int failed;
  final bool authPaused;
  final int clockSkew;

  bool get _waiter => role == 'waiter';
  // A waiter's device has no drawer; the shift is the till's, not theirs.
  ShiftView? get _openShift => shiftOpen && !_waiter ? _shift : null;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    // ── words, locale, time ────────────────────────────────────────────────
    if (name == #tr) {
      final key = invocation.namedArguments[#key] as String? ?? '';
      return (rtl ? _ar[key] : null) ?? _en[key] ?? key;
    }
    if (name == #isRtl) return rtl;
    if (name == #locale) return rtl ? 'ar' : 'en';
    if (name == #setLocale) return null;
    if (name == #formatTime) {
      final raw = invocation.namedArguments[#rfc3339] as String? ?? '';
      final style = invocation.namedArguments[#style];
      final at = DateTime.tryParse(raw)?.toLocal();
      if (at == null) return '19:17';
      final hm =
          '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}';
      return style == TimeStyle.time ? hm : 'Sep ${at.day} · $hm';
    }
    if (name == #clockSkewMinutes) return clockSkew;
    if (name == #humanMessage) return 'Something went wrong';
    // ── session, route, device ─────────────────────────────────────────────
    if (name == #appRoute) {
      if (_waiter) return const AppRoute.waiterTickets();
      return shiftOpen ? const AppRoute.order() : const AppRoute.openShift();
    }
    if (name == #currentSession) {
      return SessionSnapshot(
        userId: _waiter ? 'u-2' : 'u-1',
        displayName: _waiter ? (rtl ? 'أحمد' : 'Ahmed') : 'Sara',
        role: role,
        branchId: 'br-1',
        currencyCode: 'EGP',
        taxRate: 0.14,
        taxInclusive: false,
        serviceChargeRate: 0.12,
        serviceChargeTaxable: false,
        requireTableForOrders: requireTable,
        online: online,
        permissionsLoaded: true,
      );
    }
    if (name == #deviceConfig) {
      return DeviceConfigView(
        branchName: rtl ? 'شارع الزمالك' : 'Rue Zamalek',
        tillId: _waiter ? null : 't-1',
        reconfiguring: false,
        configured: true,
      );
    }
    if (name == #deviceCode) return 'T1';
    if (name == #baseUrl) return 'https://api.madar-pos.cloud';
    if (name == #version) return '0.5.1';
    if (name == #environment) return 'prod';
    if (name == #listTills) {
      return Future<List<TillView>>.value(const [
        TillView(id: 't-1', name: 'Till 1', isDefault: true, isActive: true),
      ]);
    }
    if (name == #kdsListStations) {
      return Future<List<KdsStationView>>.value(const []);
    }
    // ── connectivity, sync ─────────────────────────────────────────────────
    if (name == #syncStatus) {
      return Future<SyncStatusView>.value(
        SyncStatusView(
          pending: pending,
          failed: failed,
          blocked: 0,
          online: online,
          authPaused: authPaused,
        ),
      );
    }
    if (name == #listOutbox) {
      return Future<List<OutboxItemView>>.value(
        pending > 0 ? _outbox : const [],
      );
    }
    if (name == #pendingOutboxCount) return Future<int>.value(pending);
    if (name == #refreshConnectivity) return Future<bool>.value(online);
    if (name == #isRealtimeSubscribed) return online;
    // A kitchen screen owns the board here, so the Queue offers no Kitchen
    // segment — the shell's tab set is unchanged by it either way.
    if (name == #kitchenRoutingMode) return Future<String?>.value('kds');
    if (name == #lanActive) return true;
    if (name == #lanPeerCount) return 2;
    if (name == #recentLogs) return Future<List<DiagLogView>>.value(const []);
    if (name == #refreshFloor || name == #refreshCatalog) {
      return Future<void>.value();
    }
    if (name == #lanStop || name == #logout || name == #lanStart) {
      return Future<void>.value();
    }
    // ── catalog, cart, drafts ──────────────────────────────────────────────
    if (name == #listCategories) {
      return Future<List<CategoryView>>.value(_categories);
    }
    if (name == #listMenuItems) return Future<List<MenuItemView>>.value(_items);
    if (name == #availableBundles) {
      return Future<List<BundleView>>.value(const []);
    }
    if (name == #listItemModifierGroups) {
      return Future<List<ModifierGroupView>>.value(const []);
    }
    if (name == #listItemAddons) {
      return Future<List<ItemAddonView>>.value(const []);
    }
    if (name == #cartLines) {
      return Future<List<CartLineView>>.value(_waiter ? const [] : _cart);
    }
    if (name == #cartTotals) {
      return Future<CartTotals>.value(
        _waiter
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
    if (name == #listDrafts) return Future<List<DraftView>>.value(const []);
    if (name == #categoryStyle) {
      return const CatStyleView(
        icon: 'cafe',
        bgTop: '#8B5A2B',
        bgBottom: '#8B5A2B',
        iconColor: '#8B5A2B',
        accent: '#8B5A2B',
      );
    }
    // ── floor, bills, bookings ─────────────────────────────────────────────
    if (name == #floorLayout) {
      return Future<FloorLayoutView>.value(hasFloor ? _layout : _emptyLayout);
    }
    if (name == #listOpenTickets) {
      return Future<List<TicketView>>.value(_tickets);
    }
    if (name == #listTransferQueue) {
      return Future<List<TransferQueueView>>.value(const []);
    }
    if (name == #listArrivals) return Future<List<BookingView>>.value(const []);
    if (name == #lanBranchHasOpenTill) return true;
    // ── online orders ──────────────────────────────────────────────────────
    if (name == #listDeliveryOrders) {
      return Future<List<DeliveryOrderView>>.value(_onlineOrders);
    }
    if (name == #deliverySettings) {
      return Future<DeliverySettingsView>.value(_deliverySettings);
    }
    // ── the drawer ─────────────────────────────────────────────────────────
    if (name == #currentShift || name == #refreshShift) {
      return Future<ShiftView?>.value(_openShift);
    }
    if (name == #shiftReport || name == #shiftReportFor) {
      return Future<ShiftReportView>.value(_report(fromServer: online));
    }
    if (name == #listShiftOrders) {
      return Future<List<OrderSummaryView>>.value(
        _orders(queued: online ? 0 : pending),
      );
    }
    if (name == #shiftStats) {
      return Future<ShiftStatsView>.value(
        const ShiftStatsView(salesMinor: 623000, orderCount: 42),
      );
    }
    if (name == #listCashMovements) {
      return Future<List<CashMovementView>>.value(_movements);
    }
    if (name == #listShifts) {
      return Future<List<ShiftSummaryView>>.value(const []);
    }
    if (name == #suggestedOpeningCashMinor) return Future<int>.value(85000);
    if (name == #listPaymentMethods) {
      return Future<List<PaymentMethodView>>.value(const []);
    }
    if (name == #listDiscounts) {
      return Future<List<DiscountView>>.value(const []);
    }
    return null;
  }
}

// ── Harness ────────────────────────────────────────────────────────────────

Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  const dir = '$_root/packages/design_system/assets/fonts';
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      final file = File('$dir/$family-$cut.ttf');
      if (!file.existsSync()) return;
      loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
  await _loadLucide();
}

/// The legacy `MadarIcon('sf.name')` names that the duotone set does not
/// cover fall through to the Lucide icon font. A test host loads no icon
/// fonts, so without this every such icon is a tofu box in the picture and
/// a reviewer reads a bug that is not there. Best-effort: the font lives in
/// the pub cache, and a machine without it just shows the boxes.
Future<void> _loadLucide() async {
  final home = Platform.environment['HOME'] ?? '';
  final hosted = Directory('$home/.pub-cache/hosted/pub.dev');
  if (!hosted.existsSync()) return;
  final pkg = hosted
      .listSync()
      .whereType<Directory>()
      .where((d) => d.path.split('/').last.startsWith('lucide_icons_flutter-'))
      .firstOrNull;
  if (pkg == null) return;
  final file = File('${pkg.path}/assets/lucide.ttf');
  if (!file.existsSync()) return;
  final loader = FontLoader('packages/lucide_icons_flutter/Lucide')
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

/// Mounts the REAL shell — the route host, the role shell, the tabs — over
/// [bridge] at [size], and lets the first loads land.
Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required _FakeBridge bridge,
  required Size size,
  bool dark = false,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final container = ProviderContainer(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      themeChoiceProvider.overrideWith(
        () => ThemeChoiceNotifier(
          initial: dark ? ThemeChoice.dark : ThemeChoice.light,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: UncontrolledProviderScope(
        container: container,
        child: const MadarShell(),
      ),
    ),
  );
  await _settle(tester);
  return container;
}

/// Not pumpAndSettle: the screens keep clocks and the kit keeps a spinner
/// or two alive. A handful of frames lets every fixture future land and
/// every entrance animation finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Switches to the tab with [key] through the rail or the bar, the way a
/// person would.
Future<void> _tab(WidgetTester tester, String key) async {
  final finder = find.byWidgetPredicate(
    (w) => w is MadarRailTab && w.tab.key == key,
  );
  if (finder.evaluate().isNotEmpty) {
    await tester.tap(finder.first);
  } else {
    // The phone's bar has no exposed tab type; tap by its label.
    final bar = find.byType(MadarTabBar);
    final label = _en.entries.firstWhere((e) => e.key == 'nav.$key').value;
    final ar = _ar['nav.$key'];
    final text = find.descendant(
      of: bar,
      matching: find.byWidgetPredicate(
        (w) => w is Text && (w.data == label || w.data == ar),
      ),
    );
    await tester.tap(text.first);
  }
  await _settle(tester);
}

/// Writes the current frame to `build/render/<name>.png` when rendering,
/// and always insists the frame laid out cleanly and shows no raw key.
Future<void> _shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');
  _expectNoRawKeys(tester, name);
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
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// A raw `namespace.key` on screen means a word the core does not have.
void _expectNoRawKeys(WidgetTester tester, String name) {
  final key = RegExp(r'^[a-z]+(\.[a-z0-9_]+)+$');
  final raw = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where(key.hasMatch)
      .toSet();
  expect(raw, isEmpty, reason: '$name shows raw i18n keys');
}

void main() {
  setUpAll(() async {
    _loadWords();
    await _loadFonts();
  });

  testWidgets('the teller shell on an iPad: Sell, Floor, Queue, Till', (
    tester,
  ) async {
    await _mount(tester, bridge: _FakeBridge(), size: _ipad);
    expect(find.byType(MadarRail), findsOneWidget);
    expect(find.byType(MadarTabBar), findsNothing);
    await _shot(tester, 'shell-teller-sell-ipad');
    await _tab(tester, 'floor');
    await _shot(tester, 'shell-teller-floor-ipad');
    await _tab(tester, 'queue');
    await _shot(tester, 'shell-teller-queue-ipad');
    await _tab(tester, 'till');
    await _shot(tester, 'shell-teller-till-ipad');
  });

  testWidgets('every sale on a table: Floor is home; dark; queued pill', (
    tester,
  ) async {
    await _mount(
      tester,
      bridge: _FakeBridge(requireTable: true, pending: 3),
      size: _ipad,
      dark: true,
    );
    // The home tab is the room, and the rail says so.
    final floor = tester.widget<MadarRailTab>(
      find.byWidgetPredicate((w) => w is MadarRailTab && w.tab.key == 'floor'),
    );
    expect(floor.selected, isTrue);
    await _shot(tester, 'shell-teller-floor-ipad-dark');
    await _tab(tester, 'sell');
    await _shot(tester, 'shell-teller-sell-ipad-dark');
  });

  testWidgets('a teller with no shift lands on Till, offline', (tester) async {
    await _mount(
      tester,
      bridge: _FakeBridge(shiftOpen: false, online: false, pending: 2),
      size: _ipad,
    );
    final till = tester.widget<MadarRailTab>(
      find.byWidgetPredicate((w) => w is MadarRailTab && w.tab.key == 'till'),
    );
    expect(till.selected, isTrue);
    expect(
      find.byWidgetPredicate(
        (w) => w is MadarOutboxPill && w.state == OutboxState.offline,
      ),
      findsOneWidget,
    );
    await _shot(tester, 'shell-teller-noshift-ipad-offline');
  });

  testWidgets('stuck work and a paused session are said under the bar', (
    tester,
  ) async {
    await _mount(
      tester,
      bridge: _FakeBridge(failed: 1, authPaused: true, clockSkew: 7),
      size: _ipad,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is MadarOutboxPill && w.state == OutboxState.stuck,
      ),
      findsOneWidget,
    );
    expect(find.byType(NoticeBanner), findsNWidgets(2));
    await _shot(tester, 'shell-teller-banners-ipad');
  });

  testWidgets('the teller shell on a phone: bottom tabs', (tester) async {
    await _mount(tester, bridge: _FakeBridge(), size: _phone);
    expect(find.byType(MadarTabBar), findsOneWidget);
    expect(find.byType(MadarRail), findsNothing);
    await _shot(tester, 'shell-teller-sell-phone');
    await _tab(tester, 'queue');
    await _shot(tester, 'shell-teller-queue-phone');
    await _tab(tester, 'till');
    await _shot(tester, 'shell-teller-till-phone');
  });

  testWidgets('the waiter shell on an iPad: Floor, Bills, Me', (tester) async {
    await _mount(
      tester,
      bridge: _FakeBridge(role: 'waiter'),
      size: _ipad,
    );
    final keys = tester
        .widgetList<MadarRailTab>(find.byType(MadarRailTab))
        .map((t) => t.tab.key)
        .toList();
    expect(keys, ['floor', 'bills', 'me']);
    await _shot(tester, 'shell-waiter-floor-ipad');
    await _tab(tester, 'bills');
    await _shot(tester, 'shell-waiter-bills-ipad');
    await _tab(tester, 'me');
    await _shot(tester, 'shell-waiter-me-ipad');
  });

  testWidgets('a waiter on a phone in Arabic, mirrored', (tester) async {
    await _mount(
      tester,
      bridge: _FakeBridge(role: 'waiter', rtl: true, pending: 2),
      size: _phone,
    );
    expect(find.byType(MadarTabBar), findsOneWidget);
    await _shot(tester, 'shell-waiter-floor-phone-ar');
    await _tab(tester, 'bills');
    await _shot(tester, 'shell-waiter-bills-phone-ar');
    await _tab(tester, 'me');
    await _shot(tester, 'shell-waiter-me-phone-ar');
  });

  testWidgets('a waiter with no floor: Bills is home', (tester) async {
    await _mount(
      tester,
      bridge: _FakeBridge(role: 'waiter', hasFloor: false),
      size: _phone,
    );
    final keys = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(MadarTabBar),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        // The Bills badge is a Text too; the tab words are what is asked.
        .where((d) => d != null && int.tryParse(d) == null)
        .toList();
    expect(keys, [_en['nav.bills'], _en['nav.me']]);
    await _shot(tester, 'shell-waiter-nofloor-phone');
  });

  testWidgets('the teller shell in Arabic on an iPad puts the rail at the '
      'start edge, which is the right', (tester) async {
    await _mount(
      tester,
      bridge: _FakeBridge(rtl: true, pending: 1),
      size: _ipad,
    );
    final rail = tester.getTopLeft(find.byType(MadarRail));
    expect(rail.dx, greaterThan(_ipad.width / 2));
    await _shot(tester, 'shell-teller-sell-ipad-ar');
    await _tab(tester, 'till');
    await _shot(tester, 'shell-teller-till-ipad-ar');
  });
}
