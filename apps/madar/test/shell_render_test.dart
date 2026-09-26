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

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_history/feature_history.dart';
import 'package:feature_order/feature_order.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:feature_till/feature_till.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar/app/shell.dart';
import 'package:rust_bridge/rust_bridge.dart';

part 'shell_order_messages.dart';
part 'shell_till_state.dart';
part 'shell_meal_tile.dart';

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

final _tickets = <TicketView>[
  TicketView(
    ready: true,
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
    ready: false,
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
    ready: false,
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
    contactOverride: false,
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

const _till = TillView(
  id: 'sh-1',
  branchId: 'br-1',
  tellerId: 'u-1',
  tellerName: 'Sara',
  openingCashMinor: 85000,
  openedAt: _openedAt,
  status: 'open',
  isOpen: true,
  verification: 'server',
  openedWhileAnotherOpen: false,
);

/// The [n]th till opened on the fake device — `sh-1` is [_till].
TillView _tillNo(int n) => n == 1
    ? _till
    : TillView(
        id: 'sh-$n',
        branchId: _till.branchId,
        tellerId: _till.tellerId,
        tellerName: _till.tellerName,
        openingCashMinor: _till.openingCashMinor,
        openedAt: _till.openedAt,
        status: 'open',
        isOpen: true,
        verification: 'server',
        openedWhileAnotherOpen: false,
      );

TillReportView _report({required bool fromServer}) => TillReportView(
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
    TillReportPaymentLine(
      method: 'Cash',
      isCash: true,
      orderCount: 18,
      totalMinor: 142000,
    ),
    TillReportPaymentLine(
      method: 'Card',
      isCash: false,
      orderCount: 24,
      totalMinor: 481000,
    ),
  ],
  cashMovements: const [],
  fromServer: fromServer,
  reconciliation: const [],
  verification: 'server',
  spotViews: const [],
  openedWhileAnotherOpen: false,
  serviceChargeWaivedCount: 0,
  serviceChargeWaivedMinor: 0,
  totalServiceChargeMinor: 0,
  totalTaxMinor: 0,
);

const _movements = <CashMovementView>[
  CashMovementView(
    id: 'cm-2',
    kind: 'pay_in',
    amountMinor: 20000,
    note: 'Float top-up',
    movedByName: 'Sara',
    createdAt: '2026-09-12T16:05:00Z',
  ),
  CashMovementView(
    id: 'cm-1',
    kind: 'pay_out',
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
      priceFlagged: false,
      displayNumber: '',
      orderType: 'dine_in',
    ),
];

/// Past tills: a short one (with a rail), balanced ones, an over.
List<TillSummaryView> _pastTills(bool ar) {
  String n(String en, String a) => ar ? a : en;
  TillSummaryView s(
    String id,
    String teller,
    int daysAgo,
    int hours,
    int declared,
    int delta,
  ) {
    final open = DateTime.now().toUtc().subtract(
      Duration(days: daysAgo, hours: hours + 1),
    );
    return TillSummaryView(
      id: id,
      tellerName: teller,
      openedAt: open.toIso8601String(),
      closedAt: open.add(Duration(hours: hours, minutes: 22)).toIso8601String(),
      openingCashMinor: 85000,
      closingDeclaredMinor: declared,
      closingSystemMinor: declared - delta,
      discrepancyMinor: delta,
      status: 'closed',
      isOpen: false,
      verification: 'server',
      openedWhileAnotherOpen: false,
    );
  }

  return [
    s('sh-9', n('Omar', 'عمر'), 1, 8, 623000, -12000),
    s('sh-8', n('Sara', 'سارة'), 1, 7, 418500, 0),
    s('sh-7', n('Mona', 'منى'), 2, 7, 702250, 2500),
    s('sh-6', n('Omar', 'عمر'), 3, 8, 911000, 0),
  ];
}

List<OrderSummaryView> _historyOrders() => [
  for (var i = 0; i < 14; i++)
    OrderSummaryView(
      id: 'h-$i',
      orderNumber: 1042 - i,
      subtotalMinor: 14000 + i * 3150,
      taxMinor: 2000,
      totalMinor: 16000 + i * 3150,
      paymentLabel: ['cash', 'card', 'digital_wallet'][i % 3],
      status: i == 3 ? 'voided' : 'completed',
      createdAt: _ago(38 + i * 23),
      queued: false,
      tellerName: 'Sara',
      priceFlagged: false,
      displayNumber: '',
      orderType: ['dine_in', 'takeaway', 'delivery'][i % 3],
    ),
];

OrderDetailView _detail(String id) => OrderDetailView(
  id: id,
  orderNumber: 1042,
  status: 'completed',
  paymentLabel: 'cash',
  subtotalMinor: 14000,
  grossSubtotalMinor: 14000,
  discountMinor: 0,
  taxMinor: 2000,
  totalMinor: 16000,
  createdAt: _ago(38),
  deals: const [],
  lines: const [
    OrderDetailLineView(
      kind: 'item',
      name: 'Flat white',
      qty: 2,
      lineTotalMinor: 10000,
      addons: [ReceiptModifierView(name: 'Oat milk', priceMinor: 0)],
      optionals: [],
    ),
    OrderDetailLineView(
      kind: 'item',
      name: 'Croissant',
      qty: 1,
      lineTotalMinor: 4000,
      addons: [],
      optionals: [],
    ),
  ],
);

const _outbox = <OutboxItemView>[
  OutboxItemView(
    blocked: false,
    id: 'ob-1',
    opType: 'ticket_add_round',
    status: 'pending',
    attempts: 1,
    eventAt: '2026-09-12T19:20:00Z',
  ),
  OutboxItemView(
    blocked: false,
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
    this.tillOpen = true,
    this.hasFloor = true,
    this.requireTable = false,
    this.online = true,
    this.pending = 0,
    this.failed = 0,
    this.authPaused = false,
    this.clockSkew = 0,
    this.route,
    this.lockReason = 'no_till',
  });

  /// Why the core would lock this device when no till is open — `no_till`
  /// (the ordinary start of the day) or a refusal it cannot satisfy
  /// (`not_permitted`, `open_elsewhere`).
  final String lockReason;

  /// `login` or `station`: a device before the shell (sign-in, a kitchen
  /// screen picking its station).
  final String? route;

  final String role;
  final bool rtl;

  /// The core's till, in miniature: open or not, and which one. Mutable so a
  /// test can walk the owner's steps (open, close, open again) through the
  /// real screens; `openTill` flips it the way the core does.
  bool tillOpen;

  /// Bumped on every open, so a second till is a DIFFERENT till (`sh-2`).
  int tillSeq = 1;

  /// How many times the open-till action reached the core.
  int opens = 0;

  /// False: the core cannot answer the lock (a bridge hiccup). The shell then
  /// fails OPEN, which is the one way a teller sees Sell with no till.
  bool lockAnswers = true;
  final bool hasFloor;
  final bool requireTable;
  final bool online;
  final int pending;

  /// The cart context the shell last switched the core to.
  /// Each cart context's lines beyond takeaway's, and every context's meta.
  final Map<String, List<CartLineView>> tableCarts = {};
  final Map<String?, CartMeta> metas = {};
  final int failed;
  final bool authPaused;
  final int clockSkew;

  /// The room, when a test needs one the fixtures do not draw (a table whose
  /// parked order another till is editing). Null: the fixtures' room.
  FloorLayoutView? layout;

  /// The open bills, when a test moves them (a bill settled on another
  /// till). Null: the fixtures' bills.
  List<TicketView>? tickets;

  /// What the core answers a fire with: this failure, or a fired ticket.
  MadarError? fireError;

  /// The sentences the core keeps for the Till to say once (a queued
  /// pay-out recorded without its advance tag) — drained by the read.
  List<String> payOutNotices = [];

  bool get _waiter => role == 'waiter';
  // A waiter's device has no drawer; the till is the till's, not theirs.
  TillView? get _openTill => tillOpen && !_waiter ? _tillNo(tillSeq) : null;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final review = fakeManagerActionsInvocation(invocation);
    if (review != null) return review;
    final name = invocation.memberName;
    // The core's drawer and Orders decisions (till_views), in miniature.
    if (name == #paymentMethodLabel) {
      final code = invocation.namedArguments[#code] as String;
      const ar = {
        'cash': 'نقدًا',
        'card': 'بطاقة',
        'digital_wallet': 'محفظة إلكترونية',
      };
      const en = {'digital_wallet': 'Wallet'};
      final key = code.toLowerCase();
      if (rtl && ar[key] != null) return ar[key];
      if (en[key] != null) return en[key];
      return code.isEmpty ? code : code[0].toUpperCase() + code.substring(1);
    }
    if (name == #tillCashSalesMinor) {
      final r = invocation.namedArguments[#report] as TillReportView;
      return r.expectedCashMinor -
          r.openingCashMinor -
          r.cashInMinor +
          r.cashOutMinor;
    }
    if (name == #closeCountCheck) {
      final expected = invocation.namedArguments[#expectedMinor] as int;
      final counted = invocation.namedArguments[#countedMinor] as int?;
      final v = counted == null ? 0 : counted - expected;
      return CloseCountCheck(
        entered: counted != null,
        varianceMinor: v,
        verdict: counted == null
            ? 'pending'
            : v == 0
            ? 'matches'
            : v > 0
            ? 'over'
            : 'short',
        needsReason: counted != null && v != 0,
      );
    }
    if (name == #saleTaxInclusive) {
      final a = invocation.namedArguments;
      final before =
          (a[#subtotalMinor] as int) -
          (a[#discountMinor] as int) +
          (a[#serviceMinor] as int) +
          (a[#deliveryMinor] as int);
      return (a[#taxMinor] as int) > 0 && a[#totalMinor] == before;
    }
    if (name == #refundMethodPlan) {
      final method = invocation.namedArguments[#orderPaymentMethod] as String;
      const options = [
        PaymentMethodChoice(code: 'cash', label: 'Cash', isCash: true),
        PaymentMethodChoice(code: 'card', label: 'Card', isCash: false),
      ];
      return RefundMethodPlan(
        options: options,
        defaultCode: options
            .where((o) => o.code == method.toLowerCase())
            .firstOrNull
            ?.code,
        crossesTill: false,
      );
    }
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
    // The core's display formats (display.rs), through the kit's mirror.
    final lang = rtl ? 'ar' : 'en';
    if (name == #formatMoney) {
      final a = invocation.namedArguments;
      return MadarFormat.money(
        a[#minor] as int,
        currency: a[#currency] as String,
        signed: a[#signed] as bool,
        locale: lang,
      );
    }
    if (name == #currencyLabel) {
      return MadarFormat.currencyLabel(
        invocation.namedArguments[#code] as String,
        locale: lang,
      );
    }
    if (name == #formatStamp) {
      final raw = invocation.namedArguments[#rfc3339] as String;
      final at = DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
      return MadarFormat.stamp(at, DateTime.now(), locale: lang);
    }
    if (name == #formatElapsed) {
      final secs = invocation.namedArguments[#secs] as int;
      return MadarFormat.elapsed(Duration(seconds: secs), locale: lang);
    }
    if (name == #formatElapsedSince) {
      final raw = invocation.namedArguments[#rfc3339] as String;
      final at = DateTime.tryParse(raw) ?? DateTime.now();
      return MadarFormat.elapsed(DateTime.now().difference(at), locale: lang);
    }
    if (name == #clockSkewMinutes) return clockSkew;
    if (name == #humanMessage) return 'Something went wrong';
    if (name == #loyaltySettings) {
      return Future.value(
        const LoyaltyProgrammeView(
          enabled: false,
          mode: 'points',
          programName: '',
          balanceLabel: '',
        ),
      );
    }
    // ── session, route, device ─────────────────────────────────────────────
    // The core's ONE lock answer, in miniature: a cashier device with no
    // open drawer is locked; waiters and the kitchen hold no drawer and are
    // never locked (`till_lock()` in till_ops.rs).
    if (name == #tillLock) {
      if (!lockAnswers) throw const MadarError.internal(detail: 'lock');
      final holdsDrawer = !_waiter && role != 'kitchen';
      final locked = holdsDrawer && !tillOpen && route == null;
      String word(String key) => (rtl ? _ar[key] : null) ?? _en[key] ?? key;
      final titles = {
        'no_till': 'till.lock_title',
        'not_permitted': 'till.lock_not_permitted_title',
        'open_elsewhere': 'till.lock_elsewhere_title',
      };
      final bodies = {
        'no_till': 'till.lock_body',
        'not_permitted': 'till.lock_not_permitted_body',
        'open_elsewhere': 'till.lock_elsewhere_body',
      };
      return TillLockView(
        locked: locked,
        reason: locked ? lockReason : '',
        title: locked ? word(titles[lockReason]!) : '',
        body: locked ? word(bodies[lockReason]!) : '',
        canOpen: locked && lockReason == 'no_till',
        holdsDrawer: holdsDrawer,
      );
    }
    if (name == #appRoute && route == 'login') return const AppRoute.login();
    if (name == #appRoute && route == 'station') {
      return const AppRoute.deviceSetup();
    }
    if (name == #appRoute) {
      if (_waiter) return const AppRoute.waiterTickets();
      return tillOpen ? const AppRoute.order() : const AppRoute.openTill();
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
        reconfiguring: false,
        configured: true,
      );
    }
    if (name == #deviceCode) return 'T1';
    if (name == #baseUrl) return 'https://api.madar-pos.cloud';
    if (name == #version) return '0.5.1';
    if (name == #environment) return 'prod';
    if (name == #kdsListStations) {
      return Future<List<KdsStationView>>.value(const []);
    }
    // ── connectivity, sync ─────────────────────────────────────────────────
    if (name == #syncStatus) {
      return SyncStatusView(
        repairedTypes: const [],
        catalogFreshness: const FreshnessView(state: 'fresh'),
        blockedClose: false,
        pendingOutbox: pending,
        deadOutbox: failed,
        blocked: 0,
        freshness: const FreshnessView(state: 'fresh'),
        online: online,
        authPaused: authPaused,
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
    if (name == #lanStatus) {
      return const LanStatusView(
        peerSkewMinutes: 0,
        running: true,
        peerCount: 2,
        manualHubCount: 0,
        tcpPort: 47600,
        beaconActive: true,
        mdnsActive: true,
        nativeDiscoveryActive: true,
      );
    }
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
    if (name == #listItemModifierGroups) {
      return Future<List<ModifierGroupView>>.value(const []);
    }
    if (name == #listItemAddons) {
      return Future<List<ItemAddonView>>.value(const []);
    }
    // One cart per context (null = takeaway); nothing is ever active.
    final cartTable = invocation.namedArguments[#tableId] as String?;
    if (name == #cartLines) {
      return Future<List<CartLineView>>.value(
        _waiter
            ? const []
            : cartTable == null
            ? _cart
            : tableCarts[cartTable] ?? const [],
      );
    }
    if (name == #cartMeta) {
      return Future<CartMeta>.value(
        metas[cartTable] ?? const CartMeta(name: ''),
      );
    }
    if (name == #cartSetMeta) {
      metas[cartTable] = invocation.namedArguments[#meta]! as CartMeta;
      return Future<void>.value();
    }
    if (name == #cartTotals) {
      return Future<CartTotals>.value(
        _waiter || (cartTable != null && tableCarts[cartTable] == null)
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
      return Future<FloorLayoutView>.value(
        layout ?? (hasFloor ? _layout : _emptyLayout),
      );
    }
    if (name == #listOpenTickets) {
      return Future<List<TicketView>>.value(tickets ?? _tickets);
    }
    if (name == #fireTicket) {
      final e = fireError;
      if (e != null) return Future<TicketFiredView>.error(e);
      return Future<TicketFiredView>.value(
        const TicketFiredView(ticketId: 'tk-new', queuedOffline: false),
      );
    }
    if (name == #takePayOutNotices) {
      final said = List<String>.of(payOutNotices);
      payOutNotices = [];
      return said;
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
    // The one owner's sync read: this person's OWN open till, or none.
    if (name == #ownOpenTill) {
      final t = _openTill;
      return (t?.isOpen ?? false) ? t : null;
    }
    if (name == #currentTill || name == #refreshTill) {
      return Future<TillView?>.value(_openTill);
    }
    // The core's open: this person's till on this device already open is
    // answered with that till (never a second one); otherwise a new till.
    if (name == #openTill) {
      opens += 1;
      final already = tillOpen;
      tillOpen = true;
      return Future<OpenTillOutcome>.value(
        OpenTillOutcome(
          till: _openTill,
          verification: 'server',
          alreadyOpen: already,
        ),
      );
    }
    if (name == #tillReport || name == #tillReportFor) {
      return Future<TillReportView>.value(_report(fromServer: online));
    }
    if (name == #listTillOrders) {
      return Future<List<OrderSummaryView>>.value(
        _orders(queued: online ? 0 : pending),
      );
    }
    if (name == #tillStats || name == #tillStatsChecked) {
      return Future<TillStatsView>.value(
        const TillStatsView(salesMinor: 623000, orderCount: 42),
      );
    }
    if (name == #listCashMovements) {
      return Future<List<CashMovementView>>.value(_movements);
    }
    if (name == #listTills) {
      return Future<List<TillSummaryView>>.value(_pastTills(rtl));
    }
    if (name == #listOrdersForTill) {
      return Future<List<OrderSummaryView>>.value(
        _historyOrders().sublist(4, 8),
      );
    }
    if (name == #searchOrders) {
      return Future<OrderSearchPage>.value(
        OrderSearchPage(
          orders: _historyOrders(),
          page: 1,
          total: 318,
          hasMore: true,
        ),
      );
    }
    if (name == #orderDetail) {
      final id = invocation.namedArguments[#orderId] as String;
      return Future<OrderDetailView>.value(_detail(id));
    }
    if (name == #orderReceiptView || name == #listOrderRefunds) {
      return Future<Never>.error(
        const MadarError.offline(detail: 'not in the fixture'),
      );
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
    File('build/render/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
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

// ── The chrome stands around every page ────────────────────────────────────

/// The navigator a page is pushed on — the stack of the tab in front, found
/// the way the app finds it.
NavigatorState _pageStack(WidgetTester tester) =>
    MadarPages.navigatorOf(tester.element(find.byType(MadarShellScaffold)));

/// The ROOT navigator — surfaces only; a page never lands here.
NavigatorState _rootNavigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator).first);

/// Whatever page is showing, the top bar and the tabs (the rail on a
/// tablet, the bottom bar on a phone) stand around it, and the page itself
/// sits in the content area between them — never over them.
void _expectChromeStands(WidgetTester tester, String name, Size size) {
  expect(
    _rootNavigator(tester).canPop(),
    isFalse,
    reason: '$name: no page is pushed over the shell on the root navigator',
  );
  final bar = find.byType(MadarTopBar);
  expect(bar, findsOneWidget, reason: '$name: the top bar stands');
  final tabs = size == _phone
      ? find.byType(MadarTabBar)
      : find.byType(MadarRail);
  final other = size == _phone
      ? find.byType(MadarRail)
      : find.byType(MadarTabBar);
  expect(tabs, findsOneWidget, reason: '$name: the tabs stand');
  expect(other, findsNothing, reason: '$name: one kind of tabs');
  final barRect = tester.getRect(bar);
  final tabsRect = tester.getRect(tabs);
  expect(barRect.height, greaterThan(0), reason: '$name: top bar laid out');
  expect(tabsRect.height, greaterThan(0), reason: '$name: tabs laid out');
  // The page in front: the one header's own Scaffold.
  final headers = find.byKey(MadarPageScaffold.headerKey);
  if (headers.evaluate().isEmpty) return;
  final page = tester.getRect(
    find.ancestor(of: headers.first, matching: find.byType(Scaffold)).first,
  );
  expect(
    page.top,
    closeTo(barRect.bottom, 0.5),
    reason: '$name: under the bar',
  );
  if (size == _phone) {
    expect(
      page.bottom,
      lessThanOrEqualTo(tabsRect.top + 0.5),
      reason: '$name: above the tab bar',
    );
  } else {
    expect(
      page.left,
      greaterThanOrEqualTo(tabsRect.right - 0.5),
      reason: '$name: beside the rail',
    );
  }
}

// ── Safe area ──────────────────────────────────────────────────────────────

/// A notched phone's status bar: the band no content may sit in.
const double _statusBar = 47;

void _notch(WidgetTester tester) {
  tester.view.padding = const FakeViewPadding(top: _statusBar);
  tester.view.viewPadding = const FakeViewPadding(top: _statusBar);
  addTearDown(() {
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}

/// The top route is framed by the page shell, and nothing a person reads or
/// taps starts inside the status bar.
void _expectShellClearOfInset(WidgetTester tester, String name) {
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');
  expect(
    find.byType(MadarPageScaffold),
    findsWidgets,
    reason: '$name is framed by MadarPageScaffold',
  );
  final intruders = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final box = e.renderObject;
    if (box is! RenderBox || !box.hasSize || !box.attached) continue;
    final top = box.localToGlobal(Offset.zero).dy;
    if (box.size.height > 0 && top < _statusBar - 0.5) {
      intruders.add('"${(e.widget as Text).data}" @ ${top.toStringAsFixed(1)}');
    }
  }
  expect(intruders, isEmpty, reason: '$name puts text under the status bar');
}

void main() {
  setUpAll(() async {
    _loadWords();
    await _loadFonts();
  });

  group('one page shell', pageShellMain);
  group('spec board', specBoardMain);
  group('one till owner', tillStateMain);
  group('order messages reach the screen', orderMessagesMain);
  group('the sell tile after a meal', mealTileMain);

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

  testWidgets('the Sell tab is always takeaway: a launch, a re-select, and '
      'ten rapid switches with a table screen on the Floor stack', (
    tester,
  ) async {
    final bridge = _FakeBridge()
      ..tableCarts['t1'] = [_cartLine('latte', 'Latte', 4500, 2)]
      ..metas['t1'] = const CartMeta(name: 'Nour', tableLabel: 'T1');
    final container = await _mount(tester, bridge: bridge, size: _ipad);
    String? sellTitle() => tester
        .widget<MadarPageScaffold>(
          find.descendant(
            of: find.byType(TakeawaySellScreen, skipOffstage: false),
            matching: find.byType(MadarPageScaffold, skipOffstage: false),
            skipOffstage: false,
          ),
        )
        .title;
    expect(sellTitle(), 'Pickup', reason: 'a launch opens takeaway');
    container.read(orderProvider.notifier).setPendingCovers('t1', 4);

    await _tab(tester, 'floor');
    _pageStack(tester).push(
      MaterialPageRoute<void>(
        builder: (_) => const TableOrderScreen(tableId: 't1'),
      ),
    );
    await _settle(tester);
    expect(find.text('T1 · 4 guests'), findsWidgets);
    for (var i = 0; i < 10; i++) {
      await _tab(tester, i.isEven ? 'sell' : 'floor');
    }
    await _tab(tester, 'sell');
    await _tab(tester, 'sell');
    await _settle(tester);
    expect(sellTitle(), 'Pickup');
    expect(container.read(cartProvider(null)).lines, _cart);
    await _tab(tester, 'floor');
    await _settle(tester);
    expect(find.byType(TableOrderScreen), findsOneWidget);
    expect(find.text('T1 · 4 guests'), findsWidgets);
    expect(container.read(cartProvider('t1')).lines, hasLength(1));
    expect(container.read(cartProvider('t1')).name, 'Nour');
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
      bridge: _FakeBridge(tillOpen: false, online: false, pending: 2),
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

  // ── The lock: no drawer, no shop ────────────────────────────────────────
  //
  // Owner decision 2026-09-19: a cashier device with no open till is walled
  // to the open-till screen. Everything reachable while locked and everything
  // hidden is pinned here, at the sizes the tills actually ship on, in both
  // languages. The core decides `locked`; these tests prove the SHELL obeys.

  /// Every rail tab key currently on screen.
  Set<String> railKeys(WidgetTester tester) => tester
      .widgetList<MadarRailTab>(find.byType(MadarRailTab))
      .map((t) => t.tab.key ?? '')
      .toSet();

  const lockSizes = <String, Size>{
    'ipad9': _ipad9,
    'ipad9-portrait': _ipad9Portrait,
    'tab8': _tab8,
    'lenovo': _lenovo,
  };

  for (final MapEntry(key: label, value: size) in lockSizes.entries) {
    for (final rtl in [false, true]) {
      final tag = rtl ? '$label-ar' : label;
      testWidgets('locked to the till, and only the till · $tag', (
        tester,
      ) async {
        await _mount(
          tester,
          bridge: _FakeBridge(tillOpen: false, rtl: rtl),
          size: size,
        );
        // The rail carries the Till alone: nothing sells, nothing browses.
        expect(railKeys(tester), {
          'till',
        }, reason: 'locked: only the Till is on the rail');
        for (final gone in ['sell', 'floor', 'queue', 'orders', 'bills']) {
          expect(
            find.byWidgetPredicate(
              (w) => w is MadarRailTab && w.tab.key == gone,
            ),
            findsNothing,
            reason: 'locked: $gone must not be reachable',
          );
        }
        // And nothing from those screens is mounted behind the lock.
        expect(find.byType(TakeawaySellScreen), findsNothing);
        expect(find.byType(FloorScreen), findsNothing);
        expect(find.byType(OrderHistoryScreen), findsNothing);

        // What stays: the open-till screen with the core's own words, the
        // manager-actions list, the sync pill and the person button.
        expect(find.byType(OpenTillScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('till.lock_notice')), findsOneWidget);
        expect(
          find.text(coreWord('till.lock_title', arabic: rtl)),
          findsOneWidget,
          reason: 'the reason, in the language on screen',
        );
        expect(find.byType(ManagerActionsBanner), findsOneWidget);
        expect(find.byType(MadarOutboxPill), findsOneWidget);
        expect(find.byType(MadarAvatar), findsWidgets);

        await _shot(tester, 'shell-locked-$tag');
      });
    }
  }

  testWidgets('locked: Settings, Sync and sign out are still reachable', (
    tester,
  ) async {
    await _mount(tester, bridge: _FakeBridge(tillOpen: false), size: _lenovo);
    // Sync, from the outbox pill — its own off-rail page, not a tab.
    await tester.tap(find.byType(MadarOutboxPill));
    await _settle(tester);
    expect(find.byType(SyncScreen), findsOneWidget);

    // Settings and Sign out, from the person button.
    await tester.tap(find.byType(MadarAvatar).first);
    await _settle(tester);
    expect(find.text(coreWord('settings.title')), findsWidgets);
    expect(find.text(coreWord('settings.sign_out')), findsOneWidget);
    await tester.tap(find.text(coreWord('settings.title')).last);
    await _settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await _shot(tester, 'shell-locked-settings-lenovo');
  });

  testWidgets('opening a till unlocks the shell with no restart', (
    tester,
  ) async {
    final container = await _mount(
      tester,
      bridge: _FakeBridge(tillOpen: false),
      size: _lenovo,
    );
    expect(railKeys(tester), {'till'});
    // The core's answer changes; the shell re-reads it on the same refresh
    // every state-changing bridge call already makes.
    container.updateOverrides([
      bridgeProvider.overrideWithValue(_FakeBridge()),
      themeChoiceProvider.overrideWith(ThemeChoiceNotifier.new),
    ]);
    container.read(shellProvider.notifier).refresh();
    await _settle(tester);
    expect(
      railKeys(tester),
      containsAll(<String>['sell', 'floor', 'queue', 'orders', 'till']),
      reason: 'the shop is back the moment a drawer is open',
    );
  });

  testWidgets('a refusal it cannot satisfy is the same screen, with the '
      'reason and a way out', (tester) async {
    await _mount(
      tester,
      bridge: _FakeBridge(tillOpen: false, lockReason: 'not_permitted'),
      size: _lenovo,
    );
    expect(railKeys(tester), {'till'});
    expect(find.byKey(const ValueKey('till.lock_notice')), findsOneWidget);
    expect(
      find.text(coreWord('till.lock_not_permitted_title')),
      findsOneWidget,
    );
    // No counting field for someone who may never submit it — the way out
    // is to let the right person in.
    expect(find.byType(MadarAmountField), findsNothing);
    expect(find.text(coreWord('till.switch_teller')), findsOneWidget);
    await _shot(tester, 'shell-locked-not-permitted-lenovo');
  });

  testWidgets('a waiter and a kitchen device are never locked', (tester) async {
    await _mount(
      tester,
      bridge: _FakeBridge(role: 'waiter', tillOpen: false),
      size: _lenovo,
    );
    expect(
      railKeys(tester),
      containsAll(<String>['floor', 'bills', 'me']),
      reason: 'a waiter holds no drawer — locking them stops table service',
    );
    expect(find.byType(OpenTillScreen), findsNothing);
  });

  // ── The status bar and the shared signal must never contradict ──────────
  //
  // The owner's bug: a screen saying offline over a top bar saying online, on
  // a device that was online. These pin that both sides of the app read the
  // SAME fact, and that "there is queued work" is never worded as "offline".

  testWidgets('a queued backlog on a reachable server is queued, NOT offline', (
    tester,
  ) async {
    final container = await _mount(
      tester,
      bridge: _FakeBridge(pending: 7),
      size: _ipad,
    );
    // The pill says queued and shows the count...
    final pill = tester.widget<MadarOutboxPill>(find.byType(MadarOutboxPill));
    expect(pill.state, OutboxState.queued);
    expect(pill.count, 7);
    // ...and the shared signal agrees: reachable, with work waiting. A screen
    // that only needs "is there queued work" reads `hasQueuedWork` and has no
    // business saying offline.
    final signal = container.read(connectivityProvider);
    expect(signal.reachable, isTrue);
    expect(signal.hasQueuedWork, isTrue);
    expect(signal.queued, 7);
  });

  testWidgets('online: the pill and the shared signal agree', (tester) async {
    final container = await _mount(
      tester,
      bridge: _FakeBridge(pending: 2),
      size: _ipad,
    );
    final pill = tester.widget<MadarOutboxPill>(find.byType(MadarOutboxPill));
    final signal = container.read(connectivityProvider);
    // One fact, two readers — the word on the bar and the flag every screen
    // gates on are derived from the same `syncStatus().online`.
    expect(signal.reachable, isTrue);
    expect(pill.state, OutboxState.queued);
    expect(
      pill.state == OutboxState.offline,
      !signal.reachable,
      reason: 'the bar may only say offline when the signal says unreachable',
    );
  });

  testWidgets('offline: the pill and the shared signal agree', (tester) async {
    final container = await _mount(
      tester,
      bridge: _FakeBridge(online: false, pending: 2),
      size: _ipad,
    );
    final pill = tester.widget<MadarOutboxPill>(find.byType(MadarOutboxPill));
    final signal = container.read(connectivityProvider);
    expect(signal.reachable, isFalse);
    expect(pill.state, OutboxState.offline);
    expect(pill.state == OutboxState.offline, !signal.reachable);
  });

  testWidgets('LAN peers are their own fact, not a reachability one', (
    tester,
  ) async {
    // Offline to the server, but on a LAN with peers — the two must not be
    // fused, or a LAN-only tablet loses features that need no internet.
    final container = await _mount(
      tester,
      bridge: _FakeBridge(online: false),
      size: _ipad,
    );
    final signal = container.read(connectivityProvider);
    expect(signal.reachable, isFalse);
    expect(signal.lanPeers, 2, reason: 'peers survive an unreachable server');
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

  group('each tab keeps its own page stack', () {
    testWidgets('switching tabs keeps each stack; re-tapping pops to root', (
      tester,
    ) async {
      await _mount(tester, bridge: _FakeBridge(), size: _ipad);
      await _tab(tester, 'floor');
      _pageStack(tester).push(
        MaterialPageRoute<void>(
          builder: (_) => const BillScreen(ticketId: 'tk-1', canCharge: true),
        ),
      );
      await _settle(tester);
      await _tab(tester, 'queue');
      _pageStack(
        tester,
      ).push(MaterialPageRoute<void>(builder: (_) => const SyncScreen()));
      await _settle(tester);
      expect(find.byType(SyncScreen), findsOneWidget);
      expect(find.byType(BillScreen), findsNothing, reason: 'Floor is behind');
      _expectChromeStands(tester, 'queue › sync', _ipad);

      await _tab(tester, 'floor');
      expect(find.byType(BillScreen), findsOneWidget, reason: 'bill kept');
      expect(find.byType(SyncScreen), findsNothing);
      _expectChromeStands(tester, 'floor › bill', _ipad);

      await _tab(tester, 'queue');
      expect(find.byType(SyncScreen), findsOneWidget, reason: 'sync kept');

      // Re-tap the tab in front: its stack goes back to its root.
      await _tab(tester, 'queue');
      expect(find.byType(SyncScreen), findsNothing);
      expect(_pageStack(tester).canPop(), isFalse);
      // …and only its own: Floor still has the bill.
      await _tab(tester, 'floor');
      expect(find.byType(BillScreen), findsOneWidget);
      await _shot(tester, 'shell-floor-bill-kept-ipad');
    });

    testWidgets('system back and Escape pop the tab stack first', (
      tester,
    ) async {
      await _mount(tester, bridge: _FakeBridge(), size: _phone);
      await _tab(tester, 'till');
      _pageStack(tester).push(
        MaterialPageRoute<void>(builder: (_) => const TillHistoryScreen()),
      );
      await _settle(tester);
      _pageStack(
        tester,
      ).push(MaterialPageRoute<void>(builder: (_) => const SyncScreen()));
      await _settle(tester);
      expect(find.byType(SyncScreen), findsOneWidget);

      // Android back.
      final handled = await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(handled, isTrue);
      expect(find.byType(SyncScreen), findsNothing);
      expect(find.byType(TillHistoryScreen), findsOneWidget);
      _expectChromeStands(tester, 'back', _phone);

      // Escape.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(find.byType(TillHistoryScreen), findsNothing);
      expect(find.byType(TillScreen), findsOneWidget);
      expect(_pageStack(tester).canPop(), isFalse);
    });

    testWidgets("a table's Sell on the Floor stack keeps its table across "
        'a visit to the Sell tab', (tester) async {
      final bridge = _FakeBridge();
      final container = await _mount(tester, bridge: bridge, size: _ipad);
      await _tab(tester, 'floor');
      _pageStack(tester).push(
        MaterialPageRoute<void>(
          builder: (_) => const TableOrderScreen(tableId: 't1'),
        ),
      );
      await _settle(tester);
      expect(find.text('T1'), findsWidgets);
      expect(find.text('Round 1'), findsWidgets);

      // The Sell tab is the counter.
      await _tab(tester, 'sell');
      await _settle(tester);
      expect(find.text('Pickup'), findsWidgets);

      // Back on Floor: the table's screen is still there, still for T1.
      await _tab(tester, 'floor');
      await _settle(tester);
      final table = find.byType(TableOrderScreen);
      expect(table, findsOneWidget);
      expect(tester.widget<TableOrderScreen>(table).tableId, 't1');
      expect(find.text('Round 1'), findsWidgets);
      expect(container.read(cartProvider(null)).lines, _cart);
      _expectChromeStands(tester, 'floor › sell for T2', _ipad);
    });
  });

  group('a global page opens in the tab that owns it', () {
    List<MadarRailTab> railTabs(WidgetTester tester) =>
        tester.widgetList<MadarRailTab>(find.byType(MadarRailTab)).toList();

    testWidgets('Sync from the pill: no rail tab claims it, a second tap '
        'does not stack it, and Sell is still the counter', (tester) async {
      final bridge = _FakeBridge();
      final container = await _mount(tester, bridge: bridge, size: _ipad);
      expect(railTabs(tester).singleWhere((t) => t.selected).tab.key, 'sell');
      final pill = find.byType(MadarOutboxPill);
      await tester.tap(pill.first);
      await _settle(tester);
      expect(find.byType(SyncScreen), findsOneWidget);
      expect(
        railTabs(tester).where((t) => t.selected),
        isEmpty,
        reason: 'Sell must not be lit over Sync',
      );

      await tester.tap(pill.first);
      await _settle(tester);
      expect(find.byType(SyncScreen), findsOneWidget, reason: 'deduped');
      final stack = _pageStack(tester)..pop();
      await _settle(tester);
      expect(stack.canPop(), isFalse, reason: 'only one Sync was pushed');

      // Back to Sell: the counter, not a page left over from elsewhere.
      await _tab(tester, 'sell');
      expect(find.byType(SyncScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(_pageStack(tester).canPop(), isFalse);
      expect(find.text('Pickup'), findsWidgets);
      expect(container.read(cartProvider(null)).lines, _cart);
      expect(railTabs(tester).singleWhere((t) => t.selected).tab.key, 'sell');
    });
  });

  group('every page pays the status-bar inset through the page shell', () {
    testWidgets('teller tabs on a notched phone', (tester) async {
      _notch(tester);
      await _mount(tester, bridge: _FakeBridge(), size: _phone);
      _expectShellClearOfInset(tester, 'sell tab');
      for (final tab in ['floor', 'queue', 'till']) {
        await _tab(tester, tab);
        _expectShellClearOfInset(tester, '$tab tab');
      }
    });

    testWidgets('waiter tabs on a notched phone', (tester) async {
      _notch(tester);
      await _mount(
        tester,
        bridge: _FakeBridge(role: 'waiter'),
        size: _phone,
      );
      _expectShellClearOfInset(tester, 'waiter home');
      for (final tab in ['bills', 'me']) {
        await _tab(tester, tab);
        _expectShellClearOfInset(tester, '$tab tab');
      }
    });

    testWidgets('a teller with no shift: the open-shift page', (tester) async {
      _notch(tester);
      await _mount(tester, bridge: _FakeBridge(tillOpen: false), size: _phone);
      _expectShellClearOfInset(tester, 'open shift');
    });

    // Every page pushed over the shell, the way the app pushes it. A table's
    // Sell is pushed over a waiter's shell (no Sell tab of its own) AND over
    // a teller's, whose Sell tab stays mounted underneath it.
    final pushed = <String, (bool, Widget Function())>{
      'sell for a table': (true, () => const TableOrderScreen(tableId: 't1')),
      'sell for a table over the Sell tab': (
        false,
        () => const TableOrderScreen(tableId: 't1'),
      ),
      'bill': (
        false,
        () => const BillScreen(ticketId: 'tk-1', canCharge: true),
      ),
      'sync': (false, SyncScreen.new),
      'settings': (false, SettingsScreen.new),
      'order history': (false, OrderHistoryScreen.new),
      'sale': (false, SaleScreen.new),
      'close shift': (false, CloseTillScreen.new),
      'shift history': (false, TillHistoryScreen.new),
      'cash movements': (false, CashMovementsScreen.new),
    };
    for (final MapEntry(key: name, value: (waiter, page)) in pushed.entries) {
      testWidgets('pushed: $name', (tester) async {
        _notch(tester);
        await _mount(
          tester,
          bridge: _FakeBridge(role: waiter ? 'waiter' : 'teller'),
          size: _phone,
        );
        _pageStack(
          tester,
        ).push(MaterialPageRoute<void>(builder: (_) => page()));
        await _settle(tester);
        _expectShellClearOfInset(tester, name);
        _expectChromeStands(tester, name, _phone);
      });
    }
  });
}

// ── One page shell ─────────────────────────────────────────────────────────

/// Every page the POS shows as a page, by the name its picture is filed
/// under: `(waiter, tillOpen, tab, pushed)`. A tab entry is reached through
/// the rail or the bar; a pushed one is pushed over the teller's Sell tab.
final _pages = <String, (bool, bool, String?, Widget Function()?)>{
  'sell': (false, true, 'sell', null),
  'floor': (false, true, 'floor', null),
  'queue': (false, true, 'queue', null),
  'till': (false, true, 'till', null),
  'till-noshift': (false, false, 'till', null),
  'waiter-bills': (true, true, 'bills', null),
  'waiter-me': (true, true, 'me', null),
  'sell-for-table': (
    false,
    true,
    null,
    () => const TableOrderScreen(tableId: 't1'),
  ),
  'bill': (
    false,
    true,
    null,
    () => const BillScreen(ticketId: 'tk-1', canCharge: true),
  ),
  'sync': (false, true, null, SyncScreen.new),
  'settings': (false, true, null, SettingsScreen.new),
  'past-orders': (false, true, null, OrderHistoryScreen.new),
  'sale': (false, true, null, SaleScreen.new),
  'close-shift': (false, true, null, CloseTillScreen.new),
  'shift-history': (false, true, null, TillHistoryScreen.new),
  'cash-in-out': (false, true, null, CashMovementsScreen.new),
};

Future<void> _openPage(
  WidgetTester tester,
  (bool, bool, String?, Widget Function()?) page,
  Size size,
) async {
  final (waiter, tillOpen, tab, pushed) = page;
  await _mount(
    tester,
    bridge: _FakeBridge(role: waiter ? 'waiter' : 'teller', tillOpen: tillOpen),
    size: size,
  );
  if (tab != null) await _tab(tester, tab);
  if (pushed != null) {
    // A table's Sell is only ever pushed with a table in hand — seated with
    // its party — so the picture shows what a teller sees, not takeaway.
    if (pushed() is TableOrderScreen) {
      ProviderScope.containerOf(
        tester.element(find.byType(Navigator).first),
      ).read(orderProvider.notifier).setPendingCovers('t1', 4);
    }
    // Where the app pushes a page: the stack of the tab in front.
    _pageStack(tester).push(MaterialPageRoute<void>(builder: (_) => pushed()));
    await _settle(tester);
    if (pushed() is TableOrderScreen) {
      // The page title names the table and its party, not takeaway.
      expect(find.text('T1 · 4 guests'), findsWidgets);
      expect(find.text('Round 1'), findsWidgets);
    }
  }
}

/// The pages on the spec grid (`MadarPageScaffold(width: …)`).
const _specPages = <String>{
  'till',
  'till-noshift',
  'past-orders',
  'sale',
  'close-shift',
  'shift-history',
  'cash-in-out',
  'settings',
  'sync',
  'waiter-me',
};

/// Each migrated page's content width, from SPEC §3 / §15.
const _specWidths = <String, MadarContentWidth>{
  'till': MadarContentWidth.full,
  'till-noshift': MadarContentWidth.form,
  'past-orders': MadarContentWidth.full,
  'sale': MadarContentWidth.form,
  'close-shift': MadarContentWidth.full,
  'shift-history': MadarContentWidth.reading,
  'cash-in-out': MadarContentWidth.form,
  'settings': MadarContentWidth.reading,
  'sync': MadarContentWidth.reading,
  'waiter-me': MadarContentWidth.reading,
};

/// Pages still drawing the kit header by hand rather than through the
/// shell's slot. Their geometry is held to the same numbers below; the key
/// is what they lack. Empty: every page's header is the shell's own.
const _headerByHand = <String>{};

/// Where the one header's title sits: its left edge, its top, and whether a
/// back tile stands before it.
({double left, double top, double headerLeft, bool back}) _headerGeometry(
  WidgetTester tester,
  String name,
) {
  // Offstage routes (the tab shell under a pushed page) are not the page.
  final headers = find.byType(MadarHeader);
  final visible = headers.evaluate().where((e) {
    final box = e.renderObject;
    return box is RenderBox && box.attached && box.hasSize;
  }).toList();
  expect(visible, hasLength(1), reason: '$name has exactly one page header');
  final header = visible.single;
  if (!_headerByHand.contains(name)) {
    expect(
      header.widget.key,
      MadarPageScaffold.headerKey,
      reason: '$name: the header is the page shell own',
    );
  }
  expect(
    find.byType(AppBar),
    findsNothing,
    reason: '$name: no Material AppBar',
  );
  final title = find
      .descendant(of: find.byWidget(header.widget), matching: find.byType(Text))
      .first;
  final back = find.descendant(
    of: find.byWidget(header.widget),
    matching: find.byWidgetPredicate(
      (w) => w is MadarGlyphTile && w.glyph == MadarGlyph.chevronBack,
    ),
  );
  // Measured from the page's own Scaffold, so the tab shell's top bar and
  // rail (which only tab bodies sit beside) do not count against a page.
  final page = find
      .ancestor(
        of: find.byWidget(header.widget),
        matching: find.byType(Scaffold),
      )
      .first;
  final origin = tester.getTopLeft(page);
  final headerAt = tester.getTopLeft(find.byWidget(header.widget)) - origin;
  final start = tester.getTopLeft(title) - origin;
  return (
    left: start.dx,
    top: headerAt.dy,
    headerLeft: headerAt.dx,
    back: back.evaluate().isNotEmpty,
  );
}

void pageShellMain() {
  for (final (label, size) in [
    ('ipad', _ipad),
    ('ipad9', _ipad9),
    ('ipad9-portrait', _ipad9Portrait),
    ('tab8', _tab8),
    ('lenovo', _lenovo),
    ('phone', _phone),
  ]) {
    for (final MapEntry(key: name, value: page) in _pages.entries) {
      testWidgets('page board: $name on the $label', (tester) async {
        await _openPage(tester, page, size);
        await _shot(tester, 'page-$name-$label');
      });
    }

    testWidgets('one header, one geometry, every page on the $label', (
      tester,
    ) async {
      final seen =
          <String, ({double left, double top, double headerLeft, bool back})>{};
      for (final MapEntry(key: name, value: page) in _pages.entries) {
        await _openPage(tester, page, size);
        seen[name] = _headerGeometry(tester, name);
        if (_specWidths[name] case final want?) {
          final page = tester.widget<MadarPageScaffold>(
            find
                .ancestor(
                  of: find.byKey(MadarPageScaffold.headerKey).last,
                  matching: find.byType(MadarPageScaffold),
                )
                .first,
          );
          expect(page.width, want, reason: '$name: content width (SPEC §3)');
        }
        _expectChromeStands(tester, name, size);
        // A pushed page carries the back tile; a tab body never does.
        expect(
          seen[name]!.back,
          page.$4 != null,
          reason: '$name: back tile exactly when pushed',
        );
        await tester.pumpWidget(const SizedBox());
      }
      // Pages on the spec grid (SPEC §2): every header at one height; a tab
      // page's title on the gutter (no page-title icon), a pushed page's
      // after its back tile.
      final gutter = size == _phone ? 16.0 : 24.0;
      final spec = {
        for (final n in _specPages)
          if (seen[n] != null) n: seen[n]!,
      };
      expect(spec, isNotEmpty);
      final till = spec['till']!;
      for (final MapEntry(key: name, value: g) in spec.entries) {
        final msg = '$name vs till on the $label (spec grid)';
        expect(g.top, closeTo(till.top, 0.5), reason: '$msg: header top');
        expect(
          g.left,
          closeTo(gutter + (g.back ? MadarHeaderMetrics.titleInset : 0), 0.5),
          reason: '$msg: title x is gutter (+ back tile)',
        );
      }
      // Pages not yet migrated (other screens' owners move them) are held
      // only to the header's top edge until they join the grid.
      for (final MapEntry(key: name, value: g) in seen.entries) {
        expect(
          g.top,
          closeTo(till.top, 0.5),
          reason: '$name on the $label: header top',
        );
      }
    });
  }
}

// ── The spec board ─────────────────────────────────────────────────────────
//
// Every screen this migration touched, at the four size classes of
// docs/design/SPEC.md §1, in English and Arabic, light and dark — so the
// screens can be laid side by side and against the spec's own renders
// (packages/design_system/build/render/spec-*.png). Written under
// build/render/board/<screen>-<device>-<lang>-<theme>.png with the render
// flag; without it the English light board and the Arabic dark iPad still lay
// out every screen and fail on any exception or raw key.

const Size _ipadPortrait = Size(834, 1194);
const Size _desktop = Size(1440, 900);

/// The iPad 9th generation (10.2", 4:3, home button): the smallest iPad the
/// till ships on, landscape and portrait.
const Size _ipad9 = Size(1080, 810);
const Size _ipad9Portrait = Size(810, 1080);

/// An 8" Android tablet, portrait.
const Size _tab8 = Size(800, 1280);

/// A Lenovo Tab (M8 rotated, M10/M11 natural) in landscape.
const Size _lenovo = Size(1280, 800);

const _boardSizes = <String, Size>{
  'ipad': _ipad,
  'ipad-portrait': _ipadPortrait,
  'ipad9': _ipad9,
  'ipad9-portrait': _ipad9Portrait,
  'tab8': _tab8,
  'lenovo': _lenovo,
  'desktop': _desktop,
  'phone': _phone,
};

/// One screen on the board: who is signed in, whether a drawer is open, the
/// tab it lives in, what is pushed or opened over it, and what is done to it
/// before the picture.
class _BoardScreen {
  const _BoardScreen({
    this.waiter = false,
    this.tillOpen = true,
    this.tab,
    this.pushed,
    this.sheet,
    this.then,
    this.route,
  });

  final String? route;
  final bool waiter;
  final bool tillOpen;
  final String? tab;
  final Widget Function()? pushed;
  final Widget Function()? sheet;
  final Future<void> Function(WidgetTester tester)? then;
}

Future<void> _tapFirst(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) return;
  await tester.tap(finder.first, warnIfMissed: false);
  await _settle(tester);
}

final _board = <String, _BoardScreen>{
  'till': const _BoardScreen(tab: 'till'),
  'till-noshift': const _BoardScreen(tab: 'till', tillOpen: false),
  'cash-in-out': const _BoardScreen(
    tab: 'till',
    pushed: CashMovementsScreen.new,
  ),
  'close-shift': const _BoardScreen(tab: 'till', pushed: CloseTillScreen.new),
  'close-shift-counted': _BoardScreen(
    tab: 'till',
    pushed: CloseTillScreen.new,
    then: (tester) async {
      final field = find.byType(TextField);
      if (field.evaluate().isEmpty) return;
      await tester.enterText(field.first, '2260');
      await _settle(tester);
    },
  ),
  'z-report': _BoardScreen(
    tab: 'till',
    sheet: () => const TillReportSheet(tillId: 'sh-1', closed: true),
  ),
  'x-report': const _BoardScreen(tab: 'till', sheet: TillReportSheet.new),
  'past-shifts': const _BoardScreen(tab: 'till', pushed: TillHistoryScreen.new),
  'past-shifts-open': _BoardScreen(
    tab: 'till',
    pushed: TillHistoryScreen.new,
    then: (tester) => _tapFirst(tester, find.text('Omar')),
  ),
  'orders': const _BoardScreen(tab: 'till', pushed: OrderHistoryScreen.new),
  'orders-selected': _BoardScreen(
    tab: 'till',
    pushed: OrderHistoryScreen.new,
    then: (tester) => _tapFirst(tester, find.textContaining('1002')),
  ),
  'settings': const _BoardScreen(tab: 'till', pushed: SettingsScreen.new),
  'sync': const _BoardScreen(tab: 'till', pushed: SyncScreen.new),
  'me': const _BoardScreen(waiter: true, tab: 'me'),
  'login': const _BoardScreen(route: 'login'),
  'station-picker': const _BoardScreen(route: 'station'),
};

Future<void> _openBoard(
  WidgetTester tester,
  _BoardScreen screen, {
  required Size size,
  required bool ar,
  required bool dark,
}) async {
  await _mount(
    tester,
    bridge: _FakeBridge(
      role: screen.route == 'station'
          ? 'kitchen'
          : screen.waiter
          ? 'waiter'
          : 'teller',
      tillOpen: screen.tillOpen,
      rtl: ar,
      route: screen.route,
    ),
    size: size,
    dark: dark,
  );
  if (screen.tab != null) await _tab(tester, screen.tab!);
  if (screen.pushed case final page?) {
    _pageStack(tester).push(MaterialPageRoute<void>(builder: (_) => page()));
    await _settle(tester);
  }
  if (screen.sheet case final sheet?) {
    unawaited(
      showMadarSheet<void>(
        tester.element(find.byType(MadarShellScaffold)),
        size: SheetSize.large,
        builder: (_) => sheet(),
      ),
    );
    await _settle(tester);
  }
  await screen.then?.call(tester);
}

void specBoardMain() {
  for (final MapEntry(key: device, value: size) in _boardSizes.entries) {
    for (final ar in [false, true]) {
      for (final dark in [false, true]) {
        final tag = '${ar ? 'ar' : 'en'}-${dark ? 'dark' : 'light'}';
        // Unrendered, one light English pass per size and the Arabic dark
        // iPad keep the matrix honest without laying out all 16 each run.
        final cheap =
            (!ar && !dark) ||
            (device == 'ipad' && ar && dark) ||
            (device == 'ipad9' && ar && !dark) ||
            (device == 'ipad9-portrait' && ar && !dark) ||
            (device == 'lenovo' && ar && !dark);
        if (!_render && !cheap) continue;
        for (final MapEntry(key: name, value: screen) in _board.entries) {
          testWidgets('board: $name · $device · $tag', (tester) async {
            await _openBoard(tester, screen, size: size, ar: ar, dark: dark);
            await _shot(tester, 'board/$name-$device-$tag');
          });
        }
      }
    }
  }
}
