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
  tillId: 't1',
  printerHost: '192.168.1.50',
  printerPort: 9100,
  printerBrand: 'epson',
  printerTransport: 'lan',
  reconfiguring: false,
  configured: true,
);

const _tills = [
  TillView(id: 't1', name: 'Till 1', isDefault: true, isActive: true),
  TillView(id: 't2', name: 'Till 2', isDefault: false, isActive: true),
];

/// A teller's queue: two sales waiting, a cash-out mid-send, a charge the
/// server refused, and one sale stranded behind a dead till opening.
const _tellerOutbox = [
  OutboxItemView(
    id: 'o1',
    opType: 'create_order',
    status: 'pending',
    attempts: 2,
    eventAt: '2026-09-11T19:38:00Z',
  ),
  OutboxItemView(
    id: 'o2',
    opType: 'cash_movement',
    status: 'inflight',
    attempts: 0,
    eventAt: '2026-09-11T19:40:00Z',
  ),
  OutboxItemView(
    id: 'o3',
    opType: 'settle_open_ticket',
    status: 'dead',
    attempts: 3,
    lastError: 'Ticket T-0410 is already settled',
    eventAt: '2026-09-11T19:12:00Z',
  ),
];

/// A waiter's queue: two rounds waiting and one the server refused.
const _waiterOutbox = [
  OutboxItemView(
    id: 'w1',
    opType: 'ticket_add_round',
    status: 'pending',
    attempts: 0,
    eventAt: '2026-09-11T19:20:00Z',
  ),
  OutboxItemView(
    id: 'w2',
    opType: 'open_ticket',
    status: 'pending',
    attempts: 1,
    eventAt: '2026-09-11T18:47:00Z',
  ),
  OutboxItemView(
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

class _FakeBridge implements MadarBridge {
  _FakeBridge({
    this.lang = 'en',
    this.session = _session,
    this.outbox = _tellerOutbox,
    this.status = const SyncStatusView(
      pending: 2,
      failed: 1,
      blocked: 1,
      online: true,
      authPaused: false,
    ),
    this.tillOpen = true,
  });

  final String lang;
  final SessionSnapshot session;
  final List<OutboxItemView> outbox;
  final SyncStatusView status;
  final bool tillOpen;

  @override
  dynamic noSuchMethod(Invocation invocation) {
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
    if (name == #isRtl) return lang == 'ar';
    if (name == #currentSession) return session;
    if (name == #appRoute) return const AppRoute.order();
    if (name == #deviceConfig) return _config;
    if (name == #deviceCode) return 'T1';
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
              )
            : null,
      );
    }
    if (name == #listTills) return Future<List<TillView>>.value(_tills);
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
    if (name == #syncStatus) return Future<SyncStatusView>.value(status);
    if (name == #formatTime) {
      final at = invocation.namedArguments[#rfc3339] as String? ?? '';
      return at.length >= 16 ? at.substring(11, 16) : at;
    }
    if (name == #isRealtimeSubscribed) return true;
    // The branch routes to the till, so Diagnostics names the mode.
    if (name == #kitchenRoutingMode) return Future<String?>.value('till');
    if (name == #lanActive) return true;
    if (name == #lanPeerCount) return 2;
    if (name == #clockSkewMinutes) return 0;
    if (name == #baseUrl) return 'https://api.madar-pos.cloud';
    if (name == #version) return '0.5.1';
    if (name == #environment) return 'prod';
    if (name == #listOpenTickets) return Future<List<TicketView>>.value(_bills);
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
    expect(find.text('Close your shift before signing out.'), findsOneWidget);
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
        status: const SyncStatusView(
          pending: 0,
          failed: 0,
          blocked: 0,
          online: true,
          authPaused: false,
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
        status: const SyncStatusView(
          pending: 2,
          failed: 1,
          blocked: 0,
          online: true,
          authPaused: false,
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
        status: const SyncStatusView(
          pending: 2,
          failed: 1,
          blocked: 0,
          online: true,
          authPaused: false,
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
    await open('Till', 'Till 2', 'sheet-till');
    await open('Legal', 'Privacy Policy', 'sheet-legal');
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
}
