// Renders the kitchen board to PNG so it can be LOOKED at — on the iPad on
// the pass, on the phone a cook might carry, and mirrored in Arabic — and
// checks the behaviour the board exists for: Bump all bumps each open line
// in order, a refused bump is SAID, and two readers of the same core stay in
// step.
//
// `MADAR_RENDER=true` writes `build/render/kds-<board>.png`. Without the flag
// the test still builds every board and fails on any layout exception, which
// is the part CI cares about. The strings here are fixture words for the
// picture; the app's own come through `bridge.tr`.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_kds/feature_kds.dart';
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

String _ago(int minutes) => DateTime.now()
    .toUtc()
    .subtract(Duration(minutes: minutes))
    .toIso8601String();

KdsLineView _line(
  String id,
  String name, {
  int qty = 1,
  String? size,
  List<String> mods = const [],
  String? notes,
  String? station,
  bool bumped = false,
}) => KdsLineView(
  id: id,
  name: name,
  qty: qty,
  sizeLabel: size,
  modifiers: mods,
  notes: notes,
  stationId: station == null ? null : 'st-${station.toLowerCase()}',
  stationName: station,
  bumped: bumped,
);

/// A pass mid-service: a fresh round, one going amber, one gone red with a
/// pastry line for another station, a counter order with a note, a card
/// that is all done, and a six-line party — so one picture shows every
/// state the board has.
List<KdsTicketView> _tickets({bool arabic = false}) => [
  KdsTicketView(
    id: 'k-1',
    tableLabel: arabic ? 'ط٥' : 'T5',
    roundNumber: 3,
    sourceType: 'open_ticket',
    status: 'firing',
    createdAt: _ago(7),
    items: [
      _line('l-1', arabic ? 'إسبريسو' : 'Espresso'),
      _line(
        'l-2',
        arabic ? 'فلات وايت' : 'Flat white',
        mods: arabic ? ['شوفان', 'بدون رغوة'] : ['oat', 'no foam'],
      ),
    ],
  ),
  KdsTicketView(
    id: 'k-2',
    tableLabel: arabic ? 'ط٣' : 'T3',
    roundNumber: 2,
    sourceType: 'open_ticket',
    status: 'firing',
    createdAt: _ago(14),
    items: [
      _line('l-3', arabic ? 'برجر' : 'Burger', bumped: true),
      _line('l-4', arabic ? 'بطاطس' : 'Fries', qty: 2, bumped: true),
      _line(
        'l-5',
        arabic ? 'كيك' : 'Cake',
        station: arabic ? 'حلويات' : 'Pastry',
      ),
    ],
  ),
  KdsTicketView(
    id: 'k-3',
    kitchenRef: '#1041',
    roundNumber: 1,
    sourceType: 'order',
    status: 'firing',
    createdAt: _ago(2),
    items: [
      _line(
        'l-6',
        arabic ? 'كرواسون' : 'Croissant',
        notes: arabic ? 'ساخن' : 'warm it',
      ),
    ],
  ),
  KdsTicketView(
    id: 'k-4',
    tableLabel: arabic ? 'ط٨' : 'T8',
    roundNumber: 1,
    sourceType: 'open_ticket',
    status: 'ready',
    createdAt: _ago(22),
    items: [
      _line('l-7', arabic ? 'سلطة' : 'Caesar salad', bumped: true),
      _line('l-8', arabic ? 'ليمونادة' : 'Lemonade', qty: 2, bumped: true),
    ],
  ),
  KdsTicketView(
    id: 'k-5',
    tableLabel: arabic ? 'ط١' : 'T1',
    roundNumber: 1,
    sourceType: 'open_ticket',
    status: 'firing',
    createdAt: _ago(0),
    items: [
      _line(
        'l-9',
        arabic ? 'دجاج مشوي' : 'Grilled chicken',
        qty: 2,
        size: arabic ? 'كبير' : 'Large',
      ),
      _line('l-10', arabic ? 'أرز' : 'Rice', qty: 2),
      _line('l-11', arabic ? 'شوربة' : 'Soup'),
      _line('l-12', arabic ? 'خبز' : 'Bread', qty: 3),
      _line('l-13', arabic ? 'كولا' : 'Coke', qty: 2),
      _line('l-14', arabic ? 'ماء' : 'Water'),
    ],
  ),
];

const _en = {
  'kds.title': 'Kitchen',
  'kds.reconnecting': 'Reconnecting…',
  'kds.all_clear': 'All caught up',
  'kds.waiter': 'WAITER',
  'common.done': 'Done',
  'delivery.status.ready': 'Ready',
  'chrome.online': 'Online',
  'chrome.offline': 'Offline',
  'chrome.offline_banner': 'Offline — work is queued',
  'sync.queued': 'Queued',
  'sync.failed': 'Failed',
  'sync.retry': 'Retry failed',
  'sync.discard': 'Discard',
  'settings.title': 'Settings',
};

const _ar = {
  'kds.title': 'المطبخ',
  'kds.reconnecting': 'جارٍ إعادة الاتصال…',
  'kds.all_clear': 'لا طلبات معلّقة',
  'kds.waiter': 'نادل',
  'common.done': 'تم',
  'delivery.status.ready': 'جاهز',
  'chrome.online': 'متصل',
  'chrome.offline': 'غير متصل',
  'chrome.offline_banner': 'غير متصل — العمل في الانتظار',
  'sync.queued': 'في الانتظار',
  'sync.failed': 'فشل',
  'sync.retry': 'إعادة محاولة الفاشلة',
  'sync.discard': 'تجاهل',
  'settings.title': 'الإعدادات',
};

class _FakeBridge implements MadarBridge {
  _FakeBridge({
    this.rtl = false,
    List<KdsTicketView>? tickets,
    this.outbox = const [],
    this.online = true,
    this.bumpError,
  }) : tickets = tickets ?? _tickets(arabic: rtl);

  final bool rtl;
  List<KdsTicketView> tickets;
  final List<OutboxItemView> outbox;
  final bool online;

  /// When set, every bump throws it — the refused-bump path.
  final MadarError? bumpError;

  /// Every line id bumped, in order.
  final List<String> bumped = [];
  final List<String> unbumped = [];

  /// `kdsList` calls by station arg — the agreement test counts them.
  final Map<String?, int> listCalls = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #tr) {
      final key = invocation.namedArguments[#key] as String? ?? '';
      // A missing key comes back as the key — exactly what the core does.
      return (rtl ? _ar : _en)[key] ?? key;
    }
    if (name == #isRtl) return rtl;
    if (name == #kdsList) {
      final station = invocation.namedArguments[#stationId] as String?;
      listCalls[station] = (listCalls[station] ?? 0) + 1;
      return Future<List<KdsTicketView>>.value(tickets);
    }
    if (name == #kdsListStations) {
      return Future<List<KdsStationView>>.value([
        KdsStationView(
          id: 'st-grill',
          name: rtl ? 'الشواية' : 'Grill',
          isDefault: true,
          isActive: true,
        ),
      ]);
    }
    if (name == #kdsBump) {
      final id = invocation.namedArguments[#itemId] as String;
      final error = bumpError;
      if (error != null) return Future<void>.error(error);
      bumped.add(id);
      // The core's pending-bump overlay: the next list shows the tap.
      tickets = [
        for (final t in tickets)
          KdsTicketView(
            id: t.id,
            kitchenRef: t.kitchenRef,
            tableLabel: t.tableLabel,
            roundNumber: t.roundNumber,
            sourceType: t.sourceType,
            status: t.status,
            createdAt: t.createdAt,
            items: [
              for (final l in t.items)
                if (l.id == id)
                  KdsLineView(
                    id: l.id,
                    name: l.name,
                    qty: l.qty,
                    sizeLabel: l.sizeLabel,
                    modifiers: l.modifiers,
                    notes: l.notes,
                    stationId: l.stationId,
                    stationName: l.stationName,
                    bumped: true,
                  )
                else
                  l,
            ],
          ),
      ];
      return Future<void>.value();
    }
    if (name == #kdsUnbump) {
      unbumped.add(invocation.namedArguments[#itemId] as String);
      return Future<void>.value();
    }
    if (name == #syncStatus) {
      return Future<SyncStatusView>.value(
        SyncStatusView(
          pending: outbox.where((o) => o.status != 'dead').length,
          failed: outbox.where((o) => o.status == 'dead').length,
          blocked: 0,
          online: online,
          authPaused: false,
        ),
      );
    }
    if (name == #listOutbox) return Future<List<OutboxItemView>>.value(outbox);
    if (name == #retryOutbox) return Future<void>.value();
    if (name == #discardOutboxItem) return Future<bool>.value(true);
    if (name == #humanMessage) {
      final e = invocation.positionalArguments.first as MadarError;
      return switch (e) {
        MadarError_Server(:final detail) => detail,
        MadarError_Offline(:final detail) => detail,
        _ => 'error',
      };
    }
    if (name == #deviceConfig) {
      return DeviceConfigView(
        branchName: rtl ? 'الزمالك' : 'Zamalek',
        stationId: 'st-grill',
        reconfiguring: false,
        configured: true,
      );
    }
    if (name == #clockSkewMinutes) return 0;
    if (name == #currentSession) return null;
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
  required Size size,
  _FakeBridge? bridge,
  bool dark = false,
  bool connected = true,
  Widget? screen,
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
  if (!connected) {
    container.read(realtimeConnectedProvider.notifier).update(false);
  }
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
            child: screen ?? const KitchenDisplayScreen(stationId: 'st-grill'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

Future<void> _snap(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');
  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  // Real async (the engine rasterises off the fake clock) — run it as such,
  // or the test's fake zone is left waiting on a future it cannot see.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/render')..createSync(recursive: true);
    File(
      '${dir.path}/kds-$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

OutboxItemView _op(String id, String status, {String? error}) => OutboxItemView(
  id: id,
  opType: 'bump_kitchen',
  status: status,
  attempts: status == 'dead' ? 5 : 0,
  lastError: error,
  eventAt: _ago(1),
);

void main() {
  setUpAll(_loadFonts);

  // ── the pictures ────────────────────────────────────────────────────────

  testWidgets('the board on an iPad', (tester) async {
    await _mount(tester, size: _ipad);
    expect(find.text('Grill'), findsOneWidget);
    expect(find.text('T5'), findsOneWidget);
    expect(find.text('#1041'), findsOneWidget);
    // Four cards still cooking, one done.
    expect(find.text('Done'), findsNWidgets(4));
    expect(find.text('READY'), findsOneWidget);
    await _snap(tester, 'ipad');
  });

  testWidgets('the board in the dark, with queued and refused taps', (
    tester,
  ) async {
    await _mount(
      tester,
      size: _ipad,
      dark: true,
      bridge: _FakeBridge(
        outbox: [
          _op('o-1', 'pending'),
          _op('o-2', 'pending'),
          _op('o-3', 'dead', error: 'ticket voided'),
        ],
      ),
    );
    // Refused work outranks queued work in the pill and gets a banner.
    expect(find.text('1 · Failed'), findsOneWidget);
    expect(find.text('Retry failed'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    await _snap(tester, 'ipad-dark');
  });

  testWidgets('the board on a phone, offline', (tester) async {
    await _mount(
      tester,
      size: _phone,
      connected: false,
      bridge: _FakeBridge(online: false, outbox: [_op('o-1', 'pending')]),
    );
    // Offline outranks "reconnecting": one banner, not two.
    expect(find.text('Offline — work is queued'), findsOneWidget);
    expect(find.text('Reconnecting…'), findsNothing);
    await _snap(tester, 'phone');
  });

  testWidgets('the board in Arabic, mirrored', (tester) async {
    await _mount(tester, size: _ipad, bridge: _FakeBridge(rtl: true));
    expect(find.text('الشواية'), findsOneWidget);
    // The age figure stays an LTR island inside the Arabic card.
    final age = tester.widget<Text>(find.text('7').first);
    expect(age.textDirection, TextDirection.ltr);
    await _snap(tester, 'ipad-ar');
  });

  testWidgets('the all-clear board', (tester) async {
    await _mount(
      tester,
      size: _ipad,
      bridge: _FakeBridge(tickets: const []),
    );
    expect(find.text('All caught up'), findsOneWidget);
    await _snap(tester, 'ipad-empty');
  });

  // ── the behaviour ───────────────────────────────────────────────────────

  testWidgets('Bump all bumps each open line in order, and only those', (
    tester,
  ) async {
    final fake = _FakeBridge();
    await _mount(tester, size: _ipad, bridge: fake);
    // T3 has two bumped lines and one open (the pastry). Its Bump all is the
    // second "Done" on the board (T5 is first).
    await tester.tap(find.text('Done').at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(fake.bumped, ['l-5']);
    // The card is now done and the board re-read the core to show it.
    expect(find.text('READY'), findsNWidgets(2));
    expect(find.text('Done'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bump all on a six-line party sends six ops, oldest first', (
    tester,
  ) async {
    final fake = _FakeBridge();
    await _mount(tester, size: _ipad, bridge: fake);
    await tester.tap(find.text('Done').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(fake.bumped, ['l-9', 'l-10', 'l-11', 'l-12', 'l-13', 'l-14']);
  });

  testWidgets('a tap on a line bumps it; a tap on a bumped line recalls it', (
    tester,
  ) async {
    final fake = _FakeBridge();
    await _mount(tester, size: _ipad, bridge: fake);
    await tester.tap(find.textContaining('Espresso'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(fake.bumped, ['l-1']);
    await tester.tap(find.textContaining('Burger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(fake.unbumped, ['l-3']);
  });

  testWidgets('a refused bump is said, not swallowed', (tester) async {
    final fake = _FakeBridge(
      bumpError: const MadarError.server(
        status: 409,
        code: 'ticket_voided',
        detail: 'Ticket was voided',
      ),
    );
    await _mount(tester, size: _ipad, bridge: fake);
    await tester.tap(find.textContaining('Espresso'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ticket was voided'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the board and the till read the same core and stay in step', (
    tester,
  ) async {
    // The board is bound to the grill; Queue's Kitchen segment reads every
    // station. A bump from the board must reload the till's view too.
    final fake = _FakeBridge();
    final container = await _mount(tester, size: _ipad, bridge: fake);
    final till = container.read(kdsProvider(null).notifier);
    await till.load();
    final before = fake.listCalls[null] ?? 0;
    expect(before, greaterThan(0));

    await tester.tap(find.textContaining('Espresso'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(fake.listCalls[null], greaterThan(before));
    // And the till sees the bumped line, from the core, not from the board.
    final tillState = container.read(kdsProvider(null));
    final espresso = tillState.tickets
        .expand((t) => t.items)
        .firstWhere((l) => l.id == 'l-1');
    expect(espresso.bumped, isTrue);
  });

  test("ages are the server's ages, never negative", () {
    const ticket = KdsTicketView(
      id: 'k',
      roundNumber: 1,
      sourceType: 'order',
      status: 'firing',
      createdAt: '2026-09-12T12:00:00Z',
      items: [],
    );
    final now = DateTime.utc(2026, 9, 12, 12, 7);
    expect(const KdsState().ageMinutes(ticket, now), 7);
    // The device runs three minutes slow: the server says it is 12:10.
    expect(const KdsState(clockSkewMinutes: 3).ageMinutes(ticket, now), 10);
    // A stamp from the future (a fast device, a fired-offline round) is fresh.
    expect(const KdsState(clockSkewMinutes: -20).ageMinutes(ticket, now), 0);
  });

  test('the pill: refused outranks offline outranks queued', () {
    final dead = _op('d', 'dead');
    expect(
      KdsState(deadBumps: [dead], online: false, queuedBumps: 3).outboxState,
      OutboxState.stuck,
    );
    expect(
      const KdsState(online: false, queuedBumps: 3).outboxState,
      OutboxState.offline,
    );
    expect(const KdsState(queuedBumps: 3).outboxState, OutboxState.queued);
    expect(const KdsState().outboxState, OutboxState.synced);
  });
}
