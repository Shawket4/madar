// Renders the Queue to PNG so it can be LOOKED at.
//
// There is no simulator on the machines this repo is usually worked on, and
// an inbox is judged by how it reads across a counter, not by its widget
// tree. `MADAR_RENDER=true` writes `build/render/queue-*.png`: the Online
// and Bills segments on an iPad in light and dark, and the same two on a
// phone in Arabic, mirrored. Without the flag it still builds every board at
// both sizes and fails on any layout exception, which is what CI needs.
//
// The fixture words below stand in for `bridge.tr`; the app's own words come
// from the core.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_incoming/feature_incoming.dart';
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

// ── fixtures ─────────────────────────────────────────────────────────────

TicketLineView _line(
  String name,
  int qty,
  int minor, {
  int round = 1,
  String? size,
  List<String> mods = const [],
}) => TicketLineView(
  id: '$name-$round',
  name: name,
  qty: qty,
  sizeLabel: size,
  modifiers: mods,
  lineTotalMinor: minor,
  voided: false,
  roundNumber: round,
  roundFiredAt: '2026-09-10T19:02:00Z',
);

DeliveryOrderView _order({
  required String id,
  required String ref,
  required String status,
  required String channel,
  required String name,
  required String phone,
  required List<TicketLineView> lines,
  required String at,
  String? address,
  String? notes,
  String? hint,
  int fee = 1500,
  String? promisedReadyAt,
  String? readyAt,
}) {
  final subtotal = lines.fold<int>(0, (s, l) => s + l.lineTotalMinor);
  return DeliveryOrderView(
    id: id,
    orderRef: ref,
    channel: channel,
    status: status,
    customerName: name,
    customerPhone: phone,
    address: address,
    deliveryNotes: notes,
    paymentHint: hint,
    subtotalMinor: subtotal,
    discountMinor: 0,
    deliveryFeeMinor: fee,
    totalMinor: subtotal + fee,
    itemCount: lines.fold<int>(0, (s, l) => s + l.qty),
    lines: lines,
    createdAt: at,
    extraPrepMinutes: 0,
    promisedReadyAt: promisedReadyAt,
    readyAt: readyAt,
    isTerminal: false,
  );
}

/// A board with one card in every live state, so one picture shows the
/// whole vocabulary: new (accept + chips), preparing, ready (pickup), out.
final _orders = <DeliveryOrderView>[
  _order(
    id: 'd-118',
    ref: '#D-118',
    status: 'received',
    channel: 'in_mall',
    name: 'Mona',
    phone: '0100 123 4567',
    address: 'Tower B, 4th floor, unit 12',
    notes: 'no onions',
    hint: 'cash on delivery',
    at: '2026-09-10T19:40:00Z',
    lines: [
      _line('Halloumi Sandwich', 1, 7000),
      _line('Chicken Wrap', 1, 8500, mods: ['extra sauce']),
      _line('Mint Lemonade', 1, 4000, size: 'Large'),
    ],
  ),
  _order(
    id: 'd-117',
    ref: '#D-117',
    status: 'preparing',
    channel: 'outside',
    name: 'Karim',
    phone: '0111 555 0199',
    at: '2026-09-10T19:31:00Z',
    // Accepted at 19:33 with a 15-minute base and two added.
    promisedReadyAt: '2026-09-10T19:50:00Z',
    lines: [_line('Beef Burger', 2, 9000)],
  ),
  _order(
    id: 'd-116',
    ref: '#D-116',
    status: 'ready',
    channel: 'pickup',
    name: 'Dina',
    phone: '0122 000 7788',
    hint: 'paid by card',
    fee: 0,
    at: '2026-09-10T19:18:00Z',
    // The kitchen beat the promise; the fact is what shows.
    readyAt: '2026-09-10T19:29:00Z',
    lines: [_line('Flat White', 1, 5500)],
  ),
  _order(
    id: 'd-115',
    ref: '#D-115',
    status: 'out_for_delivery',
    channel: 'in_mall',
    name: 'Omar',
    phone: '0100 777 1234',
    at: '2026-09-10T19:05:00Z',
    lines: [_line('Pasta', 1, 12000), _line('Coke', 2, 5000)],
  ),
];

TicketView _ticket({
  required String id,
  required String ref,
  required String status,
  required int subtotal,
  required String at,
  String? tableId,
  String? guest,
  String? waiter,
  int? covers,
  bool queued = false,
}) => TicketView(
  id: id,
  ticketRef: ref,
  tableId: tableId,
  status: status,
  customerName: guest,
  waiterName: waiter,
  guestCount: covers,
  subtotalMinor: subtotal,
  openedAt: at,
  queuedOffline: queued,
  lines: [_line('Coke', 1, 2500), _line('Grilled chicken', 2, 9000, round: 2)],
);

final _tickets = <TicketView>[
  _ticket(
    id: 'tk-5',
    ref: 'T-105',
    tableId: 't5',
    status: 'open',
    waiter: 'Sara',
    covers: 2,
    subtotal: 14500,
    at: '2026-09-10T19:22:00Z',
  ),
  _ticket(
    id: 'tk-3',
    ref: 'T-103',
    tableId: 't3',
    status: 'ready',
    waiter: 'Sara',
    covers: 4,
    subtotal: 23500,
    at: '2026-09-10T19:02:00Z',
  ),
  _ticket(
    id: 'tk-9',
    ref: 'T-109',
    status: 'open',
    guest: 'Karim',
    waiter: 'Hany',
    subtotal: 6000,
    at: '2026-09-10T19:35:00Z',
    queued: true,
  ),
];

/// One fired round, as the cook's board sees it — the same view the KDS
/// renders, because the Queue's Kitchen segment mounts the same widget.
final _kitchen = <KdsTicketView>[
  const KdsTicketView(
    id: 'kt-1',
    kitchenRef: 'K-41',
    tableLabel: 'T5',
    roundNumber: 1,
    sourceType: 'open_ticket',
    status: 'firing',
    createdAt: '2026-09-10T19:24:00Z',
    items: [
      KdsLineView(
        id: 'kl-1',
        name: 'Flat White',
        qty: 2,
        modifiers: ['Oat'],
        bumped: false,
      ),
      KdsLineView(
        id: 'kl-2',
        name: 'Grilled chicken',
        qty: 1,
        modifiers: [],
        bumped: false,
      ),
    ],
  ),
];

FloorTableStateView _table(String id, String label) => FloorTableStateView(
  id: id,
  sectionId: 'sec',
  label: label,
  seats: 4,
  shape: 'rect',
  status: 'seated',
  posX: 0,
  posY: 0,
  width: 90,
  height: 90,
  rotation: 0,
  heldLockedByOther: false,
);

final _layout = FloorLayoutView(
  sections: const [
    FloorSectionInfo(
      id: 'sec',
      name: 'Inside',
      ordering: 0,
      canvasW: 900,
      canvasH: 600,
    ),
  ],
  tables: [_table('t3', 'T3'), _table('t5', 'T5')],
);

const _settings = DeliverySettingsView(
  inMallEnabled: true,
  inMallOverride: 'auto',
  inMallFeeMinor: 1500,
  outsideEnabled: true,
  outsideOverride: 'closed',
  prepTimeMinutes: 20,
);

const _en = <String, String>{
  'queue.title': 'Queue',
  'queue.bills': 'Bills',
  'queue.online': 'Online',
  'queue.accept': 'Accept',
  'queue.decline': 'Decline',
  'queue.ready_in': 'Ready in',
  'queue.minutes': 'minutes',
  'queue.charge': 'Charge',
  'queue.picked_up': 'Picked up',
  'queue.view': 'View',
  'queue.empty': 'Nothing waiting.',
  'queue.offline_notice': 'Offline — showing the last list',
  'queue.need_shift': 'Open the shift first',
  'delivery.status.received': 'New',
  'delivery.status.preparing': 'Preparing',
  'delivery.status.ready': 'Ready',
  'delivery.status.out_for_delivery': 'Out for delivery',
  'delivery.action.preparing': 'Start preparing',
  'delivery.action.ready': 'Mark ready',
  'delivery.action.out_for_delivery': 'Out for delivery',
  'delivery.in_mall': 'in-mall',
  'delivery.outside': 'outside',
  'delivery.pickup': 'pickup',
  'delivery.items': 'items',
  'delivery.accepting': 'Accepting',
  'delivery.mode_auto': 'auto',
  'delivery.mode_open': 'open',
  'delivery.mode_closed': 'closed',
  'queue.ready_by': 'Ready by',
  'receipt.delivery_fee': 'fee',
  'kds.title': 'Kitchen',
  'ticket.status.open': 'Open',
  'ticket.status.ready': 'Ready',
  'waiter.covers': 'covers',
  'waiter.queued': 'Queued',
  'waiter.ticket': 'Ticket',
};

const _ar = <String, String>{
  'queue.title': 'الوارد',
  'queue.bills': 'الفواتير',
  'queue.online': 'أونلاين',
  'queue.accept': 'قبول',
  'queue.decline': 'رفض',
  'queue.ready_in': 'جاهز خلال',
  'queue.minutes': 'دقيقة',
  'queue.charge': 'تحصيل',
  'queue.picked_up': 'تم الاستلام',
  'queue.view': 'عرض',
  'queue.empty': 'لا شيء بالانتظار.',
  'queue.offline_notice': 'غير متصل — تُعرض آخر قائمة',
  'queue.need_shift': 'افتح الوردية أولاً',
  'delivery.status.received': 'جديد',
  'delivery.status.preparing': 'قيد التحضير',
  'delivery.status.ready': 'جاهز',
  'delivery.status.out_for_delivery': 'خرج للتوصيل',
  'delivery.action.preparing': 'بدء التحضير',
  'delivery.action.ready': 'تحديد جاهز',
  'delivery.action.out_for_delivery': 'خرج للتوصيل',
  'delivery.in_mall': 'داخل المول',
  'delivery.outside': 'خارجي',
  'delivery.pickup': 'استلام',
  'delivery.items': 'أصناف',
  'delivery.accepting': 'قبول الطلبات',
  'delivery.mode_auto': 'تلقائي',
  'delivery.mode_open': 'مفتوح',
  'delivery.mode_closed': 'مغلق',
  'queue.ready_by': 'جاهز بحلول',
  'receipt.delivery_fee': 'رسوم التوصيل',
  'kds.title': 'المطبخ',
  'ticket.status.open': 'مفتوحة',
  'ticket.status.ready': 'جاهزة',
  'waiter.covers': 'ضيوف',
  'waiter.queued': 'بالانتظار',
  'waiter.ticket': 'تذكرة',
};

/// The bridge the picture needs: the two feeds, the settings, a floor for
/// table labels, an open shift, and real words in both scripts.
class _FakeBridge implements MadarBridge {
  _FakeBridge({
    this.arabic = false,
    this.orders = const [],
    this.tickets = const [],
    this.routingMode,
    this.kitchen = const [],
  });

  final bool arabic;
  final List<DeliveryOrderView> orders;
  final List<TicketView> tickets;

  /// `kds` · `till` · `both` · `off`, or null for a device that has never
  /// reached the server. Only `till` and `both` may show a Kitchen segment.
  final String? routingMode;
  final List<KdsTicketView> kitchen;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #tr) {
      final key = invocation.namedArguments[#key] as String? ?? '';
      final words = arabic ? _ar : _en;
      return words[key] ?? key;
    }
    if (name == #isRtl) return arabic;
    if (name == #locale) return arabic ? 'ar' : 'en';
    if (name == #listDeliveryOrders) {
      return Future<List<DeliveryOrderView>>.value(orders);
    }
    if (name == #deliverySettings) {
      return Future<DeliverySettingsView>.value(_settings);
    }
    if (name == #listOpenTickets) {
      return Future<List<TicketView>>.value(tickets);
    }
    if (name == #floorLayout) return Future<FloorLayoutView>.value(_layout);
    if (name == #currentShift) {
      return Future<ShiftView?>.value(
        const ShiftView(
          id: 'sh-1',
          branchId: 'b',
          tellerId: 'u',
          tellerName: 'Sara',
          openingCashMinor: 85000,
          openedAt: '2026-09-10T17:00:00Z',
          status: 'open',
          isOpen: true,
        ),
      );
    }
    if (name == #formatTime) {
      // The core formats in the branch's zone; here the minutes of the
      // fixture stand in so each card shows a different clock.
      final at = invocation.namedArguments[#rfc3339] as String? ?? '';
      return at.length >= 16 ? at.substring(11, 16) : '19:02';
    }
    if (name == #appRoute) return const AppRoute.order();
    if (name == #currentSession) {
      return const SessionSnapshot(
        userId: 'u',
        displayName: 'Sara',
        role: 'teller',
        currencyCode: 'EGP',
        taxRate: 0.14,
        taxInclusive: true,
        serviceChargeRate: 0,
        serviceChargeTaxable: false,
        requireTableForOrders: false,
        online: true,
        permissionsLoaded: true,
      );
    }
    if (name == #kitchenRoutingMode) {
      return Future<String?>.value(routingMode);
    }
    if (name == #kdsList) return Future<List<KdsTicketView>>.value(kitchen);
    if (name == #kdsListStations) {
      return Future<List<KdsStationView>>.value(const []);
    }
    if (name == #syncStatus) {
      return Future<SyncStatusView>.value(
        const SyncStatusView(
          online: true,
          pending: 0,
          failed: 0,
          blocked: 0,
          authPaused: false,
        ),
      );
    }
    if (name == #listOutbox) {
      return Future<List<OutboxItemView>>.value(const []);
    }
    if (name == #isRealtimeSubscribed) return true;
    if (name == #clockSkewMinutes) return 0;
    return null;
  }
}

/// Realtime "connected", so the gated fallback poll never starts a periodic
/// timer inside the test binding.
class _Connected extends ConnectedNotifier {
  @override
  bool build() => true;
}

Future<void> _shoot(
  WidgetTester tester, {
  required Size size,
  required ThemeData theme,
  required String name,
  required _FakeBridge bridge,
  required QueueSegment segment,
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
        overrides: [
          bridgeProvider.overrideWithValue(bridge),
          realtimeConnectedProvider.overrideWith(_Connected.new),
        ],
        child: MaterialApp(
          theme: theme,
          debugShowCheckedModeBanner: false,
          home: Directionality(
            textDirection: bridge.arabic
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: QueueScreen(initialSegment: segment),
          ),
        ),
      ),
    ),
  );
  // The feeds resolve on microtasks; the segment's own reload runs after
  // the first frame. A few pumps land everything, and the tactile scales
  // have nothing in flight.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(MotionSpec.standardDuration);
  await tester.pump(MotionSpec.gentleDuration);
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');
  // An overflow stripe is painted, not always thrown — look for it.
  final overflowing = tester.allRenderObjects
      .whereType<RenderFlex>()
      .where((f) => f.toStringShort().contains('OVERFLOWING'))
      .map((f) => f.debugCreator)
      .toList();
  expect(overflowing, isEmpty, reason: '$name has no overflowing flex');

  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/render')..createSync(recursive: true);
    File(
      '${dir.path}/queue-$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Loads the design system's Plex faces so the boards render real type —
/// without them the binding's block font hides everything the picture is
/// for. The family name carries the package prefix because the styles do.
Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      final file = File('../../design_system/assets/fonts/$family-$cut.ttf');
      loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('Online on an iPad, light: every live state on one board', (
    tester,
  ) async {
    await _shoot(
      tester,
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'online-ipad-light',
      bridge: _FakeBridge(orders: _orders, tickets: _tickets),
      segment: QueueSegment.online,
    );
    // The NEW card offers the ready-in chips on the branch base and Accept.
    expect(find.text('20'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    // The pickup channel's READY card says Picked up, not Out for delivery.
    expect(find.text('Picked up'), findsOneWidget);
    // The last step charges.
    expect(find.widgetWithText(MadarButton, 'Charge'), findsOneWidget);
    // The promise the shop made when it accepted, on the card that is still
    // cooking; the fact, on the one the kitchen already called.
    expect(find.textContaining('Ready by 19:50'), findsOneWidget);
    expect(find.textContaining('Ready 19:29'), findsOneWidget);
    // Never both on one card.
    expect(find.textContaining('Ready by 19:29'), findsNothing);
  });

  testWidgets('Online on an iPad, dark', (tester) async {
    await _shoot(
      tester,
      size: _ipad,
      theme: MadarTheme.dark(),
      name: 'online-ipad-dark',
      bridge: _FakeBridge(orders: _orders, tickets: _tickets),
      segment: QueueSegment.online,
    );
  });

  testWidgets('Bills on an iPad, light: ready first, Charge on the row', (
    tester,
  ) async {
    await _shoot(
      tester,
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'bills-ipad-light',
      bridge: _FakeBridge(orders: _orders, tickets: _tickets),
      segment: QueueSegment.bills,
    );
    // Table labels come from the floor mirror; a table-less bill leads
    // with its guest.
    expect(find.text('T3'), findsOneWidget);
    expect(find.text('T5'), findsOneWidget);
    expect(find.text('Karim'), findsOneWidget);
    // Ready first: T3 (ready) sits above T5 (open, older is not ready).
    final t3 = tester.getTopLeft(find.text('T3'));
    final t5 = tester.getTopLeft(find.text('T5'));
    expect(t3.dy, lessThan(t5.dy));
    expect(find.widgetWithText(MadarButton, 'Charge'), findsNWidgets(3));
  });

  testWidgets('Online on a phone in Arabic, mirrored', (tester) async {
    await _shoot(
      tester,
      size: _phone,
      theme: MadarTheme.light(),
      name: 'online-phone-ar',
      bridge: _FakeBridge(arabic: true, orders: _orders, tickets: _tickets),
      segment: QueueSegment.online,
    );
    expect(find.text('قبول'), findsOneWidget);
    // A figure stays an LTR island: the ref reads left-to-right.
    final ref = tester.widget<Text>(find.text('#D-118'));
    expect(ref.textDirection, TextDirection.ltr);
  });

  testWidgets('Bills on a phone in Arabic', (tester) async {
    await _shoot(
      tester,
      size: _phone,
      theme: MadarTheme.light(),
      name: 'bills-phone-ar',
      bridge: _FakeBridge(arabic: true, orders: _orders, tickets: _tickets),
      segment: QueueSegment.bills,
    );
  });

  testWidgets('an empty queue says so in one line', (tester) async {
    await _shoot(
      tester,
      size: _phone,
      theme: MadarTheme.light(),
      name: 'online-phone-empty',
      bridge: _FakeBridge(),
      segment: QueueSegment.online,
    );
    expect(find.text('Nothing waiting.'), findsOneWidget);
  });

  testWidgets(
    'routing to a kitchen screen offers the till no Kitchen segment',
    (tester) async {
      await _shoot(
        tester,
        size: _ipad,
        theme: MadarTheme.light(),
        name: 'bills-ipad-kds-mode',
        bridge: _FakeBridge(
          orders: _orders,
          tickets: _tickets,
          routingMode: 'kds',
        ),
        segment: QueueSegment.bills,
      );
      // Bumping from here would clear a line off a screen a cook is working
      // from. The segment is not offered at all.
      expect(find.text('Kitchen'), findsNothing);
    },
  );

  testWidgets('a device that has never synced does not guess a mode', (
    tester,
  ) async {
    await _shoot(
      tester,
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'bills-ipad-no-mode',
      bridge: _FakeBridge(orders: _orders, tickets: _tickets),
      segment: QueueSegment.bills,
    );
    expect(find.text('Kitchen'), findsNothing);
  });

  testWidgets('routing to the till shows the board inside the Queue', (
    tester,
  ) async {
    await _shoot(
      tester,
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'kitchen-ipad-light',
      bridge: _FakeBridge(
        orders: _orders,
        tickets: _tickets,
        routingMode: 'till',
        kitchen: _kitchen,
      ),
      segment: QueueSegment.kitchen,
    );
    expect(find.text('Kitchen'), findsOneWidget);
    // The cook's own card, in the cashier's inbox: same widget, same feed.
    // The line is a rich span (qty × name), so match on the span's text.
    expect(
      find.textContaining('Flat White', findRichText: true),
      findsOneWidget,
    );
    // And the table it belongs to, so the cashier knows whose food it is.
    expect(find.text('T5'), findsOneWidget);
  });

  testWidgets('the segment falls back when the mode changes under it', (
    tester,
  ) async {
    await _shoot(
      tester,
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'kitchen-ipad-revoked',
      bridge: _FakeBridge(
        orders: _orders,
        tickets: _tickets,
        routingMode: 'kds',
        kitchen: _kitchen,
      ),
      // A teller standing on Kitchen when the shop moved onto a KDS.
      segment: QueueSegment.kitchen,
    );
    expect(find.text('Kitchen'), findsNothing);
    // Bills, not a blank pane pointing at a segment that no longer exists.
    expect(find.text('T3'), findsOneWidget);
  });
}
