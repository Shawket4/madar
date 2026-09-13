// Renders the Floor to PNG so it can be LOOKED at: iPad landscape and
// portrait, desktop and phone, English and Arabic, light and dark, over a
// realistic room — the production shape (six round four-tops) with every
// state on it, and a terrace of mixed tables.
//
// `--dart-define=MADAR_RENDER=true` writes `build/render/floor2-*.png`.
// Without the flag every scene still builds and fails on a layout exception.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/feature_order.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

String _ago(int minutes) => DateTime.now()
    .toUtc()
    .subtract(Duration(minutes: minutes))
    .toIso8601String();

FloorTableStateView _t(
  String id,
  String section,
  double x,
  double y, {
  String status = 'free',
  int seats = 4,
  String shape = 'circle',
  double w = 90,
  double h = 90,
  int? seatedMins,
  int? covers,
  String? booking,
}) => FloorTableStateView(
  id: id,
  sectionId: section,
  label: id.toUpperCase(),
  seats: seats,
  shape: shape,
  status: status,
  posX: x,
  posY: y,
  width: w,
  height: h,
  rotation: 0,
  heldLockedByOther: false,
  seatedAt: seatedMins == null ? null : _ago(seatedMins),
  covers: covers,
  bookingId: booking == null ? null : 'b-$id',
  bookingGuest: booking,
  bookingParty: booking == null ? null : 4,
  bookingStatus: booking == null ? null : 'confirmed',
  bookingStartsAt: booking == null ? null : _ago(-20),
  bookingHeldFrom: booking == null ? null : _ago(10),
);

final _layout = FloorLayoutView(
  sections: const [
    FloorSectionInfo(
      id: 'in',
      name: 'Inside',
      ordering: 0,
      canvasW: 1000,
      canvasH: 700,
    ),
    FloorSectionInfo(
      id: 'out',
      name: 'Terrace',
      ordering: 1,
      canvasW: 1000,
      canvasH: 700,
    ),
  ],
  tables: [
    // The production room: six round four-tops, three by two.
    _t('t1', 'in', 60, 60, status: 'seated', seatedMins: 52, covers: 4),
    _t('t2', 'in', 260, 60, status: 'seated', seatedMins: 8, covers: 2),
    _t('t3', 'in', 460, 60, status: 'seated', seatedMins: 38, covers: 3),
    _t('t4', 'in', 60, 240),
    _t('t5', 'in', 260, 240, status: 'dirty'),
    _t('t6', 'in', 460, 240, booking: 'Omar'),
    _t(
      't7',
      'out',
      40,
      40,
      shape: 'rect',
      w: 160,
      seats: 6,
      status: 'seated',
      seatedMins: 95,
      covers: 6,
    ),
    _t('t8', 'out', 260, 40, shape: 'rect', w: 80, h: 80, seats: 2),
    _t(
      't9',
      'out',
      400,
      40,
      shape: 'rect',
      status: 'seated',
      seatedMins: 14,
      covers: 2,
    ),
    _t('t10', 'out', 40, 200, shape: 'rect', w: 160, seats: 6),
    _t(
      't11',
      'out',
      260,
      200,
      shape: 'rect',
      w: 80,
      h: 80,
      seats: 2,
      status: 'dirty',
    ),
  ],
);

TicketLineView _line(String name, int qty, int minor, int round, int ago) =>
    TicketLineView(
      id: '$name-$round',
      menuItemId: name,
      name: name,
      qty: qty,
      modifiers: const [],
      lineTotalMinor: minor,
      voided: false,
      roundNumber: round,
      roundFiredAt: _ago(ago),
    );

TicketView _ticket(
  String id,
  String table,
  int minor, {
  bool ready = false,
  bool offline = false,
  int ago = 30,
  String? waiter,
  int? guests,
}) => TicketView(
  id: id,
  ticketRef: 'T-${id.substring(3)}',
  tableId: table,
  status: offline ? 'queued' : 'open',
  ready: ready,
  waiterName: waiter,
  guestCount: guests,
  subtotalMinor: minor,
  // Priced by the server (a queued fire is not yet), so the preview reads
  // Total — the figure Charge carries.
  bill: offline
      ? null
      : TicketBillView(
          subtotalMinor: minor,
          discountMinor: 0,
          serviceChargeMinor: 0,
          taxMinor: minor * 14 ~/ 100,
          totalMinor: minor + minor * 14 ~/ 100,
          taxRate: 0.14,
          serviceChargeRate: 0,
          taxInclusive: false,
        ),
  openedAt: _ago(ago),
  queuedOffline: offline,
  lines: [
    _line('Flat white', 2, 10000, 1, ago),
    _line('Club sandwich', 1, 8500, 1, ago),
    _line('Cheesecake', 1, minor - 18500, 2, ago ~/ 2),
  ],
);

final List<TicketView> _tickets = [
  _ticket('tk-0101', 't1', 48500, ready: true, ago: 50, waiter: 'Sara'),
  _ticket('tk-0102', 't3', 31250, ago: 35, waiter: 'Hany'),
  _ticket('tk-0103', 't7', 126000, ago: 90, waiter: 'Sara'),
  _ticket('tk-0104', 't9', 22000, offline: true, ago: 12, waiter: 'Hany'),
];

final _arrivals = [
  BookingView(
    id: 'b-t6',
    guestName: 'Omar',
    partySize: 4,
    startsAt: _ago(-20),
    status: 'confirmed',
    endsAt: _ago(-110),
    heldFrom: _ago(10),
    guestPhone: '',
    tableLabels: const ['T6'],
    tableIds: const ['t6'],
    needsTable: false,
    source: 'pos',
  ),
];

class _Fake implements MadarBridge {
  _Fake({this.rtl = false, this.empty = false});

  final bool rtl;
  final bool empty;

  @override
  dynamic noSuchMethod(Invocation i) {
    final n = i.memberName;
    final a = i.namedArguments;
    if (n == #tr || n == #trChecked) {
      final key = (a[#key] ?? i.positionalArguments.firstOrNull) as String;
      return coreWord(key, arabic: rtl);
    }
    if (n == #isRtl) return rtl;
    if (n == #locale) return rtl ? 'ar' : 'en';
    if (n == #currentSession) {
      return const SessionSnapshot(
        userId: 'u',
        displayName: 'Sara',
        role: 'teller',
        currencyCode: 'EGP',
        taxRate: 0.14,
        taxInclusive: false,
        serviceChargeRate: 0,
        serviceChargeTaxable: false,
        requireTableForOrders: false,
        online: true,
        permissionsLoaded: true,
      );
    }
    if (n == #currentShift || n == #refreshShift) {
      return Future<ShiftView?>.value();
    }
    if (n == #floorLayout) {
      return Future<FloorLayoutView>.value(
        empty ? const FloorLayoutView(sections: [], tables: []) : _layout,
      );
    }
    if (n == #listOpenTickets) {
      return Future<List<TicketView>>.value(empty ? const [] : _tickets);
    }
    if (n == #listArrivals) {
      return Future<List<BookingView>>.value(empty ? const [] : _arrivals);
    }
    if (n == #listTransferQueue) {
      return Future<List<TransferQueueView>>.value(const []);
    }
    if (n == #listCategories) return Future<List<CategoryView>>.value([]);
    if (n == #listMenuItems) return Future<List<MenuItemView>>.value([]);
    if (n == #availableBundles) return Future<List<BundleView>>.value([]);
    if (n == #listDrafts) return Future<List<DraftView>>.value([]);
    if (n == #cartSetContext || n == #cartLines) {
      return Future<List<CartLineView>>.value([]);
    }
    if (n == #cartContext) return Future<String?>.value();
    if (n == #cartTotals) {
      return Future<CartTotals>.value(
        const CartTotals(
          itemCount: 0,
          subtotalMinor: 0,
          discountMinor: 0,
          taxMinor: 0,
          serviceChargeMinor: 0,
          totalMinor: 0,
        ),
      );
    }
    if (n == #deviceConfig) {
      return const DeviceConfigView(reconfiguring: false, configured: true);
    }
    if (n == #refreshConnectivity) return Future<bool>.value(true);
    if (n == #syncStatus) {
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
    if (n == #formatTime) {
      final iso = a[#rfc3339] as String? ?? '';
      final t = DateTime.tryParse(iso)?.toLocal();
      if (t == null) return '19:30';
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(t.hour)}:${two(t.minute)}';
    }
    if (n == #listShiftOrders) {
      return Future<List<OrderSummaryView>>.value([]);
    }
    if (n == #shiftStats) {
      return Future<ShiftStatsView>.value(
        const ShiftStatsView(salesMinor: 0, orderCount: 0),
      );
    }
    if (n == #listItemModifierGroups) {
      return Future<List<ModifierGroupView>>.value([]);
    }
    if (n == #listItemAddons) return Future<List<ItemAddonView>>.value([]);
    if (n == #clockSkewMinutes) return 0;
    if (n == #appRoute) return const AppRoute.order();
    if (n == #isRealtimeSubscribed) return false;
    if (n.toString().contains('"refresh') || n.toString().contains('"cart')) {
      return Future<void>.value();
    }
    return null;
  }
}

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

enum _Device {
  ipad(Size(1194, 834)),
  portrait(Size(834, 1194)),
  desktop(Size(1440, 900)),
  phone(Size(390, 844));

  const _Device(this.size);
  final Size size;
}

Future<void> _mount(
  WidgetTester tester, {
  required _Device device,
  bool rtl = false,
  bool dark = false,
  bool empty = false,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = device.size;
  addTearDown(tester.view.reset);
  if (device == _Device.desktop) {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  }
  final c = ProviderContainer(
    overrides: [
      bridgeProvider.overrideWithValue(_Fake(rtl: rtl, empty: empty)),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? MadarTheme.dark() : MadarTheme.light(),
          locale: Locale(rtl ? 'ar' : 'en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: const FloorScreen(),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');
  if (_render) {
    final boundary =
        tester.renderObject(find.byKey(const ValueKey('shot')))
            as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      return await image.toByteData(format: ui.ImageByteFormat.png);
    });
    final dir = Directory('build/render')..createSync(recursive: true);
    File(
      '${dir.path}/floor2-$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  }
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  setUpAll(_loadFonts);

  for (final device in _Device.values) {
    for (final rtl in [false, true]) {
      for (final dark in [false, true]) {
        final tag =
            '${device.name}-${rtl ? 'ar' : 'en'}-${dark ? 'dark' : 'light'}';
        testWidgets('floor $tag', (tester) async {
          await _mount(tester, device: device, rtl: rtl, dark: dark);
          await _capture(tester, tag);
        });
      }
    }
  }

  // One table of every state, selected, on the iPad.
  for (final (id, state) in [
    ('T1', 'ready'),
    ('T2', 'seated'),
    ('T3', 'bill'),
    ('T4', 'free'),
    ('T5', 'dirty'),
    ('T6', 'reserved'),
  ]) {
    testWidgets('floor selected $state', (tester) async {
      await _mount(tester, device: _Device.ipad);
      await tester.tap(find.text(id).first);
      await _settle(tester);
      await _capture(tester, 'ipad-selected-$state');
    });
  }

  testWidgets('floor selected bill, Arabic dark, portrait', (tester) async {
    await _mount(tester, device: _Device.portrait, rtl: true, dark: true);
    await tester.tap(find.text('T3').first);
    await _settle(tester);
    await _capture(tester, 'portrait-selected-ar-dark');
  });

  testWidgets('floor phone sheet', (tester) async {
    await _mount(tester, device: _Device.phone);
    await tester.tap(find.text('T3').first);
    await _settle(tester);
    await _capture(tester, 'phone-sheet');
  });

  testWidgets('floor terrace', (tester) async {
    await _mount(tester, device: _Device.ipad);
    await tester.tap(find.text('Terrace'));
    await _settle(tester);
    await _capture(tester, 'ipad-terrace');
  });

  testWidgets('floor list on iPad, a table selected', (tester) async {
    await _mount(tester, device: _Device.ipad);
    await tester.tap(find.text(coreWord('tables.view_list')));
    await _settle(tester);
    await tester.tap(find.text('T3').first);
    await _settle(tester);
    await _capture(tester, 'ipad-list');
  });

  testWidgets('floor move mode', (tester) async {
    await _mount(tester, device: _Device.ipad);
    await tester.tap(find.text('T3').first);
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('floor.action.move')));
    await _settle(tester);
    await _capture(tester, 'ipad-move');
  });

  testWidgets('floor empty', (tester) async {
    await _mount(tester, device: _Device.ipad, empty: true);
    await _capture(tester, 'ipad-empty');
  });
}
