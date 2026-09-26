// Renders Settings, Sync and Me to PNG so they can be LOOKED at.
//
// There is no simulator on the machines this repo is usually worked on, and a
// refused outbox row is not something you review by reading its widget tree.
// Set MADAR_RENDER=true and the test writes `build/render/*.png`: Settings on
// the iPad (light and dark) and on a phone, the Sync screen with waiting,
// stuck and blocked rows, and the waiter's Me tab on both, the phone in
// Arabic so the mirroring is visible. Left unset it still builds every board
// and fails on any layout exception, which is the part CI cares about.
//
// The strings in here are fixture text, not app strings; the app's own words
// come through `bridge.tr`.

import 'dart:io';
import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

/// The iPad, landscape — the primary target.
const Size _ipad = Size(1194, 834);

/// A phone — the real fallback.
const Size _phone = Size(390, 844);

// ── The core's words ───────────────────────────────────────────────────
//
// Read from the core's own tables (`i18n.rs`), so the pictures carry the
// words a device shows and a key the core lacks shows up as a raw key.

late final Map<String, String> _en;
late final Map<String, String> _ar;

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
  final src = File(
    '../../../rust-core/crates/madar-core/src/i18n.rs',
  ).readAsStringSync();
  _en = _words(src, "fn en(key: &str) -> Option<&'static str> {");
  _ar = _words(src, "fn ar(key: &str) -> Option<&'static str> {");
}

const _session = SessionSnapshot(
  userId: 'u1',
  displayName: 'Sara',
  role: 'teller',
  currencyCode: 'EGP',
  taxRate: 0.14,
  taxInclusive: true,
  serviceChargeRate: 0.12,
  serviceChargeTaxable: false,
  requireTableForOrders: true,
  online: true,
  permissionsLoaded: true,
);

const _manager = SessionSnapshot(
  userId: 'u3',
  displayName: 'Mona',
  role: 'branch_manager',
  currencyCode: 'EGP',
  taxRate: 0.14,
  taxInclusive: true,
  serviceChargeRate: 0.12,
  serviceChargeTaxable: false,
  requireTableForOrders: true,
  online: true,
  permissionsLoaded: true,
);

const _waiter = SessionSnapshot(
  userId: 'u2',
  displayName: 'Ahmed',
  role: 'waiter',
  currencyCode: 'EGP',
  taxRate: 0.14,
  taxInclusive: true,
  serviceChargeRate: 0.12,
  serviceChargeTaxable: false,
  requireTableForOrders: true,
  online: true,
  permissionsLoaded: true,
);

const _config = DeviceConfigView(
  branchId: 'b1',
  branchName: 'Rue Zamalek',
  printerHost: '192.168.1.50',
  printerPort: 9100,
  printerBrand: 'epson',
  printerTransport: 'lan',
  reconfiguring: false,
  configured: true,
);

/// A teller's queue: two sales waiting, a cash-out mid-send, a charge the
/// server refused, and one sale stranded behind a dead till opening.
const _tellerOutbox = [
  OutboxItemView(
    blocked: false,
    id: 'o1',
    opType: 'create_order',
    status: 'pending',
    attempts: 2,
    eventAt: '2026-09-11T19:38:00Z',
  ),
  OutboxItemView(
    blocked: false,
    id: 'o2',
    opType: 'cash_movement',
    status: 'inflight',
    attempts: 0,
    eventAt: '2026-09-11T19:40:00Z',
  ),
  OutboxItemView(
    blocked: false,
    id: 'o3',
    opType: 'settle_open_ticket',
    status: 'dead',
    attempts: 3,
    lastError: 'Ticket T-0410 is already settled',
    eventAt: '2026-09-11T19:12:00Z',
  ),
];

/// The drawer that will not close: the shift opening was refused, so every
/// later op of that till is HELD — a sale, the drawer money, and the close
/// itself. The sync center used to count the sale alone, so the teller saw
/// "1 blocked" and no hint that the drawer could not finish.
const _wedgedTillOutbox = [
  OutboxItemView(
    blocked: false,
    id: 'sh1:open',
    opType: 'open_till',
    status: 'dead',
    attempts: 3,
    lastError: 'That drawer is already open on another device',
    eventAt: '2026-09-11T18:00:00Z',
  ),
  OutboxItemView(
    blocked: true,
    id: 'o9',
    opType: 'create_order',
    status: 'pending',
    attempts: 0,
    eventAt: '2026-09-11T18:20:00Z',
  ),
  OutboxItemView(
    blocked: true,
    id: 'c9',
    opType: 'cash_movement',
    status: 'pending',
    attempts: 0,
    eventAt: '2026-09-11T18:40:00Z',
  ),
  OutboxItemView(
    blocked: true,
    id: 'sh1:close',
    opType: 'close_till',
    status: 'pending',
    attempts: 0,
    eventAt: '2026-09-11T22:00:00Z',
  ),
];

/// A waiter's queue: two rounds waiting and one the server refused.
const _waiterOutbox = [
  OutboxItemView(
    blocked: false,
    id: 'w1',
    opType: 'ticket_add_round',
    status: 'pending',
    attempts: 0,
    eventAt: '2026-09-11T19:20:00Z',
  ),
  OutboxItemView(
    blocked: false,
    id: 'w2',
    opType: 'open_ticket',
    status: 'pending',
    attempts: 1,
    eventAt: '2026-09-11T18:47:00Z',
  ),
  OutboxItemView(
    blocked: false,
    id: 'w3',
    opType: 'ticket_add_round',
    status: 'dead',
    attempts: 2,
    lastError: 'Table T5 has no open ticket',
    eventAt: '2026-09-11T18:30:00Z',
  ),
];

TicketLineView _line(String name, int qty, int minor, int round) =>
    TicketLineView(
      isCombo: false,
      id: '$name-$round',
      name: name,
      qty: qty,
      modifiers: const [],
      lineTotalMinor: minor,
      voided: false,
      roundNumber: round,
      roundFiredAt: '2026-09-11T19:02:00Z',
    );

final _bills = <TicketView>[
  TicketView(
    ready: true,
    id: 'tk-1',
    ticketRef: 'T-0412',
    tableId: 't5',
    status: 'ready',
    customerName: 'Omar',
    guestCount: 4,
    waiterName: 'Ahmed',
    subtotalMinor: 23500,
    openedAt: '2026-09-11T18:40:00Z',
    queuedOffline: false,
    lines: [_line('Coke', 2, 5000, 1), _line('Grill', 2, 18500, 3)],
  ),
  TicketView(
    ready: false,
    id: 'tk-2',
    ticketRef: 'T-0415',
    tableId: 't8',
    status: 'open',
    guestCount: 2,
    waiterName: 'Ahmed',
    subtotalMinor: 14500,
    openedAt: '2026-09-11T19:05:00Z',
    queuedOffline: true,
    lines: [_line('Tea', 2, 3000, 1), _line('Cake', 1, 11500, 2)],
  ),
  TicketView(
    ready: false,
    id: 'tk-3',
    ticketRef: 'T-0409',
    tableId: 't2',
    status: 'open',
    guestCount: 3,
    waiterName: 'Hany',
    subtotalMinor: 41000,
    openedAt: '2026-09-11T18:10:00Z',
    queuedOffline: false,
    lines: [_line('Pizza', 3, 41000, 1)],
  ),
];

SyncStatusView _status() => SyncStatusView(
  repairedTypes: const [],
  catalogFreshness: const FreshnessView(state: 'fresh'),
  blockedClose: false,
  pendingOutbox: 2,
  deadOutbox: 1,
  blocked: 1,
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

class _FakeBridge implements MadarBridge {
  _FakeBridge({
    this.lang = 'en',
    this.session = _session,
    this.outbox = _tellerOutbox,
    SyncStatusView? status,
    this.tillOpen = true,
  }) : status = status ?? _status();

  /// Recorded full re-downloads (long-press Sync).
  int fullSyncs = 0;

  /// Metrics loads.
  int metricsCalls = 0;

  /// The open bills as the local store holds them now; manual syncs asked
  /// for (a person's pull) and what landing one does to the local rows.
  List<TicketView> bills = _bills;
  int syncs = 0;
  void Function()? onSync;

  final String lang;
  final SessionSnapshot session;
  final List<OutboxItemView> outbox;
  final SyncStatusView status;
  final bool tillOpen;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final name = invocation.memberName;
    if (name == #tr) {
      final key = invocation.namedArguments[#key] as String? ?? '';
      return (lang == 'ar' ? _ar[key] : _en[key]) ?? key;
    }
    if (name == #locale) return lang;
    if (name == #formatMoney) {
      final a = invocation.namedArguments;
      return MadarFormat.money(
        a[#minor] as int,
        currency: a[#currency] as String,
        signed: a[#signed] as bool,
        locale: lang,
      );
    }
    if (name == #formatStamp) {
      final at = DateTime.parse(invocation.namedArguments[#rfc3339] as String);
      return MadarFormat.stamp(
        at,
        DateTime(at.year, at.month, at.day),
        locale: lang,
      );
    }
    if (name == #datePickerChrome) {
      return fakeDatePickerChrome(arabic: lang == 'ar');
    }
    if (name == #posMetricsPresets) {
      return [
        for (final k in [
          'today',
          'yesterday',
          'this_week',
          'this_month',
          'last_7_days',
          'custom',
        ])
          MetricsPresetView(
            key: k,
            label: (lang == 'ar' ? _ar : _en)['metrics.preset.$k'] ?? k,
          ),
      ];
    }
    if (name == #posMetrics) {
      metricsCalls += 1;
      return Future<PosMetricsView>.value(_metrics(lang));
    }
    if (name == #isRtl) return lang == 'ar';
    if (name == #currentSession) return session;
    if (name == #appRoute) return const AppRoute.order();
    if (name == #deviceConfig) return _config;
    if (name == #deviceCode) return 'T1';
    if (name == #refreshConnectivity) return Future<bool>.value(true);
    if (name == #refreshCatalog) return Future<void>.value();
    if (name == #syncNow) {
      syncs++;
      onSync?.call();
      return Future<SyncStatusView>.value(status);
    }
    if (name == #syncFull) {
      fullSyncs += 1;
      return Future<SyncStatusView>.value(status);
    }
    // The one owner's sync read: this person's OWN open till, or none.
    if (name == #ownOpenTill) {
      final t = tillOpen
          ? const TillView(
              id: 's1',
              branchId: 'b1',
              tellerId: 'u1',
              tellerName: 'Sara',
              openingCashMinor: 50000,
              openedAt: '2026-09-11T09:00:00Z',
              status: 'open',
              isOpen: true,
              verification: 'server',
              openedWhileAnotherOpen: false,
            )
          : null;
      return (t?.isOpen ?? false) ? t : null;
    }
    if (name == #currentTill) {
      return Future<TillView?>.value(
        tillOpen
            ? const TillView(
                id: 's1',
                branchId: 'b1',
                tellerId: 'u1',
                tellerName: 'Sara',
                openingCashMinor: 50000,
                openedAt: '2026-09-11T09:00:00Z',
                status: 'open',
                isOpen: true,
                verification: 'server',
                openedWhileAnotherOpen: false,
              )
            : null,
      );
    }
    if (name == #kdsListStations) {
      return Future<List<KdsStationView>>.value(const []);
    }
    if (name == #pendingOutboxCount) return Future<int>.value(outbox.length);
    if (name == #recentLogs) {
      return Future<List<DiagLogView>>.value(const [
        DiagLogView(
          at: '2026-09-11T19:12:04Z',
          level: 'warn',
          message: 'settle_open_ticket refused: already settled',
        ),
      ]);
    }
    if (name == #floorLayout) {
      return Future<FloorLayoutView>.value(
        const FloorLayoutView(sections: [], tables: []),
      );
    }
    if (name == #listOutbox) return Future<List<OutboxItemView>>.value(outbox);
    if (name == #syncStatus) return status;
    if (name == #formatTime) {
      final at = invocation.namedArguments[#rfc3339] as String? ?? '';
      return at.length >= 16 ? at.substring(11, 16) : at;
    }
    if (name == #isRealtimeSubscribed) return true;
    // The branch routes to the till, so Diagnostics names the mode.
    if (name == #kitchenRoutingMode) return Future<String?>.value('till');
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
    if (name == #clockSkewMinutes) return 0;
    if (name == #baseUrl) return 'https://api.madar-pos.cloud';
    if (name == #version) return '0.5.1';
    if (name == #environment) return 'prod';
    if (name == #listOpenTickets) return Future<List<TicketView>>.value(bills);
    if (name == #setLocale) return null;
    return null;
  }
}

Future<void> _shoot(
  WidgetTester tester, {
  required Size size,
  required ThemeData theme,
  required Widget home,
  required _FakeBridge bridge,
  required String name,
  bool rtl = false,
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
          debugShowCheckedModeBanner: false,
          theme: theme,
          locale: Locale(rtl ? 'ar' : 'en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: home,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');

  await _save(tester, name);
}

/// Rasterise the shot boundary to `build/render/<name>.png`. The engine
/// completes `toImage` on a real thread, so it runs under `runAsync` — the
/// fake-async test clock never advances a real future on its own.
Future<void> _save(WidgetTester tester, String name) async {
  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = Directory('build/render')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// The real Plex faces, so the picture shows what a person would read.
/// Without this the test binding substitutes its block font.
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

/// An offline day's metrics, as the core would answer.
PosMetricsView _metrics(String lang) => PosMetricsView(
  preset: 'today',
  fromDate: '2026-09-17',
  toDate: '2026-09-17',
  rangeLabel: 'Sep 17',
  source: 'device',
  offlineNote: (lang == 'ar' ? _ar : _en)['metrics.offline_note']!
      .replaceAll('{days}', '2')
      .replaceAll('{since}', 'Sep 15, 11:00 AM'),
  itemsNote: (lang == 'ar' ? _ar : _en)['metrics.items_missing']!.replaceAll(
    '{count}',
    '1',
  ),
  currencyCode: 'EGP',
  netSalesMinor: 254000,
  grossSalesMinor: 260000,
  refundedAmountMinor: 6000,
  orderCount: 23,
  averageTicketMinor: 11043,
  tenders: const [
    MetricsTenderView(
      method: 'cash',
      label: 'Cash',
      amountMinor: 180000,
      orderCount: 17,
      share: 0.69,
    ),
    MetricsTenderView(
      method: 'card',
      label: 'Card',
      amountMinor: 80000,
      orderCount: 6,
      share: 0.31,
    ),
  ],
  voidedCount: 1,
  voidedAmountMinor: 4500,
  refundedOrdersCount: 0,
  refundsIssuedCount: 2,
  refundsIssuedAmountMinor: 6000,
  topItems: const [
    MetricsItemView(name: 'Latte', quantity: 14, revenueMinor: 91000, share: 1),
    MetricsItemView(
      name: 'Croissant with a very long name indeed',
      quantity: 9,
      revenueMinor: 40500,
      share: 0.64,
    ),
  ],
  hourly: [
    for (var h = 0; h < 24; h++)
      MetricsHourView(
        hour: h,
        label: h.toString().padLeft(2, '0'),
        orderCount: h >= 8 && h <= 20 ? 2 : 0,
        netSalesMinor: h >= 8 && h <= 20 ? 20000 : 0,
        share: h >= 8 && h <= 20 ? (h == 13 ? 1 : 0.5) : 0,
      ),
  ],
);

void main() {
  setUpAll(() async {
    _loadWords();
    await _loadFonts();
  });

  testWidgets('settings on the iPad', (tester) async {
    await _shoot(
      tester,
      size: _ipad,
      theme: MadarTheme.light(),
      home: const SettingsScreen(),
      bridge: _FakeBridge(),
      name: 'settings-tablet',
    );
    // The refusal is on the page, in the server's words, with its answer.
    expect(find.text('Ticket T-0410 is already settled'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Retry all'), findsOneWidget);
    // Sign out is on the page but says why it is off.
    expect(find.text(_en['settings.sign_out_shift_open']!), findsOneWidget);
  });

  testWidgets('the Animations setting switches and persists', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = _ipad;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final saved = <MotionChoice>[];
    final container = ProviderContainer(
      overrides: [
        bridgeProvider.overrideWithValue(_FakeBridge()),
        motionChoicePersisterProvider.overrideWithValue(saved.add),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: MadarTheme.light(),
          home: const Scaffold(body: Center(child: MotionSegment())),
        ),
      ),
    );
    expect(container.read(motionChoiceProvider), MotionChoice.full);
    await tester.tap(find.text('Reduced'));
    await tester.pump();
    expect(container.read(motionChoiceProvider), MotionChoice.reduced);
    await tester.tap(find.text('System'));
    await tester.pump();
    expect(saved, [MotionChoice.reduced, MotionChoice.system]);
    expect(MotionChoice.parse('nonsense'), MotionChoice.full);
  });

  group('the Sell layout setting', () {
    Future<(ProviderContainer, List<SellLayout>)> pump(
      WidgetTester tester,
      Size size,
      Widget home,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final saved = <SellLayout>[];
      final container = ProviderContainer(
        overrides: [
          bridgeProvider.overrideWithValue(_FakeBridge()),
          sellLayoutPersisterProvider.overrideWithValue(saved.add),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: MadarTheme.light(), home: home),
        ),
      );
      await tester.pump();
      return (container, saved);
    }

    testWidgets('switches to Fast mode and back, and persists each pick', (
      tester,
    ) async {
      final (container, saved) = await pump(
        tester,
        _ipad,
        const Scaffold(body: Center(child: SellLayoutSection())),
      );
      expect(container.read(sellLayoutProvider), SellLayout.standard);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is MadarSectionHeader && w.text == _en['settings.sell_layout'],
        ),
        findsOneWidget,
      );
      expect(find.text(_en['settings.sell_layout_body']!), findsOneWidget);
      // The Fast mode note shows only while it is on.
      expect(find.text(_en['settings.sell_layout_hint']!), findsNothing);
      await tester.tap(find.text(_en['settings.sell_layout_fast']!));
      await tester.pump();
      expect(container.read(sellLayoutProvider), SellLayout.fast);
      expect(find.text(_en['settings.sell_layout_hint']!), findsOneWidget);
      await tester.tap(find.text(_en['settings.sell_layout_standard']!));
      await tester.pump();
      expect(saved, [SellLayout.fast, SellLayout.standard]);
      expect(SellLayout.parse('nonsense'), SellLayout.standard);
      expect(SellLayout.parse('fast'), SellLayout.fast);
      expect(SellLayout.parse('legacy'), SellLayout.fast);
    });

    testWidgets('is offered on the iPad settings page, to anyone', (
      tester,
    ) async {
      await pump(tester, _ipad, const SettingsScreen());
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SellLayoutSection), findsOneWidget);
      expect(find.byKey(const ValueKey('sell-layout')), findsOneWidget);
    });

    testWidgets('is not offered on a phone, which always sells standard', (
      tester,
    ) async {
      await pump(
        tester,
        _phone,
        const Scaffold(body: Center(child: SellLayoutSection())),
      );
      expect(find.byKey(const ValueKey('sell-layout')), findsNothing);
    });
  });

  testWidgets('settings on the iPad, dark', (tester) async {
    await _shoot(
      tester,
      size: _ipad,
      theme: MadarTheme.dark(),
      home: const SettingsScreen(),
      bridge: _FakeBridge(),
      name: 'settings-dark',
    );
  });

  testWidgets('settings on a phone', (tester) async {
    await _shoot(
      tester,
      size: _phone,
      theme: MadarTheme.light(),
      home: const SettingsScreen(),
      bridge: _FakeBridge(),
      name: 'settings-phone',
    );
    expect(find.textContaining('Epson'), findsOneWidget);
  });

  testWidgets('sync on a phone', (tester) async {
    await _shoot(
      tester,
      size: _phone,
      theme: MadarTheme.light(),
      home: const SyncScreen(),
      bridge: _FakeBridge(),
      name: 'sync-phone',
    );
    // A refused settle holds nothing, so there is no stranded-sales recovery
    // to offer here — the row above is the whole story.
    expect(find.text('Recover stranded sales'), findsNothing);
  });

  /// Everything held behind a dead shift opening is named, the drawer's own
  /// close included, and the section says what to do about it.
  testWidgets('sync when a dead shift opening wedged the drawer', (
    tester,
  ) async {
    await _shoot(
      tester,
      size: _phone,
      theme: MadarTheme.light(),
      home: const SyncScreen(),
      bridge: _FakeBridge(outbox: _wedgedTillOutbox),
      name: 'sync-wedged-till',
    );
    expect(find.text('HELD UP'), findsOneWidget);
    // The count is every held op, not the sale alone.
    expect(find.text('3'), findsWidgets);
    // Each one is named — including the close, which used to be invisible.
    expect(find.text('Sale'), findsWidgets);
    expect(find.text('Close till'), findsWidgets);
    expect(
      find.textContaining('its close is waiting'),
      findsOneWidget,
      reason: 'the drawer cannot finish, and the section says so',
    );
    expect(find.text('Recover stranded sales'), findsOneWidget);
  });

  testWidgets('sync when everything is clear', (tester) async {
    await _shoot(
      tester,
      size: _phone,
      theme: MadarTheme.light(),
      home: const SyncScreen(),
      bridge: _FakeBridge(
        outbox: const [],
        status: SyncStatusView(
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
        ),
      ),
      name: 'sync-clear',
    );
    expect(find.text("Everything's synced."), findsOneWidget);
    expect(find.text('Waiting'), findsNothing);
  });

  testWidgets('me on the iPad', (tester) async {
    await _shoot(
      tester,
      size: _ipad,
      theme: MadarTheme.light(),
      home: const MeScreen(),
      bridge: _FakeBridge(
        session: _waiter,
        outbox: _waiterOutbox,
        tillOpen: false,
        status: SyncStatusView(
          repairedTypes: const [],
          catalogFreshness: const FreshnessView(state: 'fresh'),
          blockedClose: false,
          pendingOutbox: 2,
          deadOutbox: 1,
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
        ),
      ),
      name: 'me-tablet',
    );
    // MINE only: Hany's bill is not on Ahmed's tab.
    expect(find.text('Omar'), findsOneWidget);
    expect(find.text('T-0415'), findsOneWidget);
    expect(find.text('T-0409'), findsNothing);
    expect(find.text('Table T5 has no open ticket'), findsOneWidget);
  });

  // Pull to refresh: the manual sync, then my bills re-read, so a bill I
  // opened on another tablet shows without waiting for a tick.
  testWidgets('a pull on Me syncs and shows my bills', (tester) async {
    final bridge = _FakeBridge(
      session: _waiter,
      outbox: _waiterOutbox,
      tillOpen: false,
    )..bills = const [];
    await _shoot(
      tester,
      size: _phone,
      theme: MadarTheme.light(),
      home: const MeScreen(),
      bridge: bridge,
      name: 'me-pull',
    );
    expect(find.text('T-0415'), findsNothing);
    bridge.onSync = () => bridge.bills = _bills;

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
    expect(find.text('T-0415'), findsOneWidget, reason: 'my bill shows');
  });

  testWidgets('me on a phone, in Arabic', (tester) async {
    await _shoot(
      tester,
      size: _phone,
      theme: MadarTheme.light(),
      home: const MeScreen(),
      bridge: _FakeBridge(
        lang: 'ar',
        session: _waiter,
        outbox: _waiterOutbox,
        tillOpen: false,
        status: SyncStatusView(
          repairedTypes: const [],
          catalogFreshness: const FreshnessView(state: 'fresh'),
          blockedClose: false,
          pendingOutbox: 2,
          deadOutbox: 1,
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
        ),
      ),
      name: 'me-phone-ar',
      rtl: true,
    );
  });

  testWidgets('the sheets a settings row opens', (tester) async {
    await _shoot(
      tester,
      size: _ipad,
      theme: MadarTheme.light(),
      home: const SettingsScreen(),
      bridge: _FakeBridge(),
      name: 'settings-sheets-base',
    );
    Future<void> open(String row, String expectText, String shot) async {
      // The device rows sit under the Sell layout and Appearance cards now.
      await tester.ensureVisible(find.text(row));
      await tester.pump();
      await tester.tap(find.text(row));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull, reason: '$row sheet laid out');
      expect(find.text(expectText), findsOneWidget);
      await _save(tester, shot);
      await tester.tap(find.byType(MadarGlyphTile).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull, reason: '$row sheet closed');
    }

    await open('Printer', 'Test print', 'sheet-printer');
    await open('Diagnostics', 'Environment', 'sheet-diagnostics');
    await open('Device', 'Reconfigure device', 'sheet-device');
    await open('Legal', 'Privacy Policy', 'sheet-legal');
  });

  testWidgets('settings_has_no_till_picker', (tester) async {
    // A till is a person's session now, not a drawer the device is bound
    // to: Settings offers no till to pick.
    await _shoot(
      tester,
      size: _ipad,
      theme: MadarTheme.light(),
      home: const SettingsScreen(),
      bridge: _FakeBridge(),
      name: 'settings-no-till-picker',
    );
    expect(find.text(_en['settings.till'] ?? 'settings.till'), findsNothing);
    expect(find.text('Printer'), findsOneWidget);
  });

  testWidgets('settings_long_press_full_sync_confirms', (tester) async {
    final bridge = _FakeBridge(session: _manager);
    await _shoot(
      tester,
      size: _phone,
      theme: MadarTheme.light(),
      home: const SyncScreen(),
      bridge: bridge,
      name: 'sync-full-confirm-base',
    );
    final button = find.widgetWithText(MadarButton, _en['sync.push']!);
    await tester.longPress(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_en['sync.full_confirm_title']!), findsOneWidget);
    expect(find.text(_en['sync.full_confirm_body']!), findsOneWidget);
    await _save(tester, 'sync-full-confirm');
    // Nothing downloads until the manager says yes.
    expect(bridge.fullSyncs, 0);
    await tester.tap(find.text(_en['sync.push']!).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(bridge.fullSyncs, 1);
  });

  // Nobody signs in to the POS with a manager role (managers only set the
  // device up), so the full download must reach a teller too — the old role
  // gate left the long press dead for everyone. The confirm still guards it.
  testWidgets('a teller long-pressing Sync is asked, then downloads', (
    tester,
  ) async {
    final bridge = _FakeBridge();
    await _shoot(
      tester,
      size: _phone,
      theme: MadarTheme.light(),
      home: const SyncScreen(),
      bridge: bridge,
      name: 'sync-teller-longpress',
    );
    await tester.longPress(find.widgetWithText(MadarButton, _en['sync.push']!));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(_en['sync.full_confirm_title']!), findsOneWidget);
    expect(bridge.fullSyncs, 0);
    await tester.tap(find.text(_en['sync.push']!).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(bridge.fullSyncs, 1);
  });

  testWidgets('discarding a refused action asks first', (tester) async {
    await _shoot(
      tester,
      size: _phone,
      theme: MadarTheme.light(),
      home: const SyncScreen(),
      bridge: _FakeBridge(),
      name: 'sync-discard-base',
    );
    await tester.tap(find.text('Discard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('Discard this action?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await _save(tester, 'sync-discard');
  });

  testWidgets('metrics offline on a phone, in Arabic', (tester) async {
    final ar = _FakeBridge(lang: 'ar');
    await _shoot(
      tester,
      size: _phone,
      theme: MadarTheme.light(),
      home: const MetricsScreen(),
      bridge: ar,
      name: 'metrics_phone_ar',
      rtl: true,
    );
    expect(ar.metricsCalls, 1, reason: 'one load when the screen opens');
  });

  testWidgets('metrics on the small iPad, both ways, in Arabic', (
    tester,
  ) async {
    for (final (name, size) in const [
      ('metrics_ipad9_ar', Size(1080, 810)),
      ('metrics_ipad9p_ar', Size(810, 1080)),
      ('metrics_lenovo_ar', Size(1280, 800)),
    ]) {
      await _shoot(
        tester,
        size: size,
        theme: MadarTheme.light(),
        home: const MetricsScreen(),
        bridge: _FakeBridge(lang: 'ar'),
        name: name,
        rtl: true,
      );
      expect(find.text('Latte'), findsOneWidget);
    }
  });

  testWidgets('metrics offline on the iPad', (tester) async {
    final en = _FakeBridge();
    await _shoot(
      tester,
      size: _ipad,
      theme: MadarTheme.light(),
      home: const MetricsScreen(),
      bridge: en,
      name: 'metrics_ipad',
    );
    expect(
      find.textContaining(
        'Offline: showing the last 2 days',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('Latte'), findsOneWidget);
  });

  testWidgets('the Metrics row shows only with reports.pos_metrics', (
    tester,
  ) async {
    await _shoot(
      tester,
      size: _ipad,
      theme: MadarTheme.light(),
      home: const SettingsScreen(),
      bridge: _FakeBridge(),
      name: 'settings_teller_no_metrics',
    );
    expect(
      find.text('Metrics'),
      findsNothing,
      reason: 'a teller does not hold it',
    );
  });

  testWidgets('a manager sees the Metrics row', (tester) async {
    const manager = SessionSnapshot(
      userId: 'u2',
      displayName: 'Mona',
      role: 'branch_manager',
      currencyCode: 'EGP',
      taxRate: 0.14,
      taxInclusive: true,
      serviceChargeRate: 0.12,
      serviceChargeTaxable: false,
      requireTableForOrders: true,
      online: true,
      permissionsLoaded: true,
    );
    await _shoot(
      tester,
      size: _ipad,
      theme: MadarTheme.light(),
      home: const SettingsScreen(),
      bridge: _FakeBridge(session: manager),
      name: 'settings_manager_metrics',
    );
    expect(find.text('Metrics'), findsOneWidget);
  });
}
