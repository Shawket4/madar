// Renders the Till to PNG so it can be LOOKED at.
//
// The Till is where a teller reconciles a drawer, and a figure that sits
// wrong on the page is a figure that gets misread at 11pm. There is no
// simulator here; `MADAR_RENDER=true` writes `build/render/till-*.png` — the
// iPad Till in light, the same offline and in the dark, a manager's Till,
// the no-till home, the close screen with a short count, and the phone in
// Arabic, mirrored. Without the flag it still builds every board and fails
// on any layout exception, which is the part CI cares about.
//
// The words in here are fixture text so the pictures read like the app; the
// app's own words come through `bridge.tr`.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_till/feature_till.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

// ── Fixture data ───────────────────────────────────────────────────────

const _methods = [
  CloseTillMethodView(
    method: 'Cash',
    label: 'Cash',
    isCash: true,
    systemTotalMinor: 238000,
    orderCount: 18,
  ),
  CloseTillMethodView(
    method: 'CIB – counter',
    label: 'CIB – counter',
    isCash: false,
    systemTotalMinor: 481000,
    orderCount: 24,
  ),
  CloseTillMethodView(
    method: 'InstaPay',
    label: 'InstaPay',
    isCash: false,
    systemTotalMinor: 62000,
    orderCount: 3,
  ),
];

const _branchTills = [
  BranchOpenTillView(
    tillId: 'sh-1',
    tellerId: 'u-1',
    tellerName: 'Sara',
    deviceCode: '36B',
    openedAt: '2026-09-12T15:02:00Z',
    isThisDevice: true,
    source: 'both',
  ),
  BranchOpenTillView(
    tillId: 'sh-2',
    tellerId: 'u-2',
    tellerName: 'Hany',
    deviceCode: '12A',
    deviceLabel: 'Terrace iPad',
    openedAt: '2026-09-12T14:30:00Z',
    isThisDevice: false,
    source: 'server',
  ),
];

const _elsewhere = TillElsewhereView(
  tillId: 'sh-9',
  deviceCode: '12A',
  deviceLabel: 'Terrace iPad',
  openedAt: '2026-09-12T09:10:00Z',
  source: 'server',
);

const _notice = OpenBillsNoticeView(
  openBillsCount: 4,
  openBillsAmountMinor: 128000,
  oldestOpenedAt: '2026-09-11T20:05:00Z',
  oldBillsCount: 2,
  oldBillHours: 3,
  seatedTablesCount: 3,
  since: '2026-09-11T23:40:00Z',
);

const _lastTill = LastTillWarningView(
  openBillsCount: 4,
  openBillsAmountMinor: 128000,
  seatedTablesCount: 3,
);

const _syncDone = TillOpenSyncView(
  state: 'done',
  tillId: 'sh-1',
  startedAt: '2026-09-12T15:02:00Z',
  finishedAt: '2026-09-12T15:02:04Z',
  changesApplied: 12,
  pendingOutbox: 0,
);

const _syncRunning = TillOpenSyncView(
  state: 'running',
  tillId: 'sh-1',
  startedAt: '2026-09-12T15:02:00Z',
  changesApplied: 0,
  pendingOutbox: 2,
);

const _syncStale = TillOpenSyncView(
  state: 'stale',
  tillId: 'sh-1',
  startedAt: '2026-09-12T15:02:00Z',
  finishedAt: '2026-09-12T15:02:09Z',
  staleReason: 'offline',
  changesApplied: 0,
  pendingOutbox: 3,
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

TillReportView _report({required bool fromServer}) => TillReportView(
  tellerName: 'Sara',
  openedAt: _openedAt,
  printedAt: '2026-09-12T19:40:00Z',
  isOpen: true,
  // float 850 + cash sales 1,420 + paid in 200 − paid out 90
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
  openedWhileAnotherOpen: false,
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

const _drawers = <TillSummaryView>[
  TillSummaryView(
    id: 'sh-1',
    tellerName: 'Sara',
    openedAt: _openedAt,
    openingCashMinor: 85000,
    status: 'open',
    isOpen: true,
    verification: 'server',
    openedWhileAnotherOpen: false,
  ),
  TillSummaryView(
    id: 'sh-2',
    tellerName: 'Hany',
    openedAt: '2026-09-12T14:30:00Z',
    openingCashMinor: 85000,
    status: 'open',
    isOpen: true,
    verification: 'server',
    openedWhileAnotherOpen: false,
  ),
  TillSummaryView(
    id: 'sh-0',
    tellerName: 'Mona',
    openedAt: '2026-09-11T15:00:00Z',
    closedAt: '2026-09-11T23:10:00Z',
    openingCashMinor: 85000,
    closingDeclaredMinor: 91000,
    closingSystemMinor: 91000,
    discrepancyMinor: 0,
    status: 'closed',
    isOpen: false,
    verification: 'server',
    openedWhileAnotherOpen: false,
  ),
];

/// A bridge that answers what the Till asks, from fixtures. [till] null is
/// a till with no drawer open; [online] false drives the honest tags.
class _FakeBridge implements MadarBridge {
  _FakeBridge({
    this.till = _till,
    this.role = 'teller',
    this.online = true,
    this.arabic = false,
    this.elsewhere,
    this.notice,
    this.lastTill,
    this.sync,
    this.methods = _methods,
  });

  /// The person's till is open on another device.
  final TillElsewhereView? elsewhere;

  /// Bills left open at the branch.
  final OpenBillsNoticeView? notice;

  /// Closing this till leaves the branch with none open.
  final LastTillWarningView? lastTill;

  /// The sync opening a till started.
  final TillOpenSyncView? sync;

  final List<BranchOpenTillView> branchTills = _branchTills;
  final List<CloseTillMethodView> methods;

  /// What reached the core.
  final List<List<ReconciliationInput>> closes = [];
  final List<String> forceClosed = [];
  int opens = 0;
  int syncNows = 0;

  final TillView? till;
  final String role;
  final bool online;
  final bool arabic;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    // The core's drawer and Orders decisions (till_views), in miniature.
    if (name == #paymentMethodLabel) {
      final code = invocation.namedArguments[#code] as String;
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
    final open = till?.isOpen ?? false;
    if (name == #tr) {
      final key = invocation.namedArguments[#key] as String? ?? '';
      return (arabic ? _ar[key] : _en[key]) ?? key;
    }
    if (name == #locale) return arabic ? 'ar' : 'en';
    final lang = arabic ? 'ar' : 'en';
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
    if (name == #formatElapsedSince || name == #formatElapsed) {
      return MadarFormat.elapsed(
        const Duration(hours: 4, minutes: 38),
        locale: lang,
      );
    }
    if (name == #isRtl) return arabic;
    if (name == #appRoute) {
      return open ? const AppRoute.order() : const AppRoute.openTill();
    }
    if (name == #currentSession) {
      return SessionSnapshot(
        userId: 'u-1',
        displayName: 'Sara',
        role: role,
        currencyCode: 'EGP',
        taxRate: 0.14,
        taxInclusive: true,
        serviceChargeRate: 0,
        serviceChargeTaxable: false,
        requireTableForOrders: true,
        online: online,
        permissionsLoaded: true,
      );
    }
    if (name == #deviceConfig) {
      return const DeviceConfigView(
        branchName: 'Rue Zamalek',
        reconfiguring: false,
        configured: true,
      );
    }
    if (name == #formatTime) {
      final raw = invocation.namedArguments[#rfc3339] as String;
      final style = invocation.namedArguments[#style] as TimeStyle;
      final at = DateTime.parse(raw);
      final hm =
          '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}';
      return style == TimeStyle.time ? hm : 'Sep ${at.day} · $hm';
    }
    if (name == #humanMessage) return 'Something went wrong';
    if (name == #clockSkewMinutes) return 0;
    if (name == #currentTill || name == #refreshTill) {
      return Future<TillView?>.value(till);
    }
    if (name == #tillReport) {
      return Future<TillReportView>.value(_report(fromServer: online));
    }
    if (name == #tillReportFor) {
      return Future<TillReportView>.value(_report(fromServer: true));
    }
    if (name == #listTillOrders) {
      return Future<List<OrderSummaryView>>.value(
        _orders(queued: online ? 0 : 3),
      );
    }
    if (name == #tillStats) {
      return Future<TillStatsView>.value(
        const TillStatsView(salesMinor: 623000, orderCount: 42),
      );
    }
    if (name == #listCashMovements) {
      return Future<List<CashMovementView>>.value(_movements);
    }
    if (name == #listTills) {
      return Future<List<TillSummaryView>>.value(_drawers);
    }
    if (name == #syncStatus) {
      return SyncStatusView(
        pendingOutbox: online ? 0 : 3,
        deadOutbox: 0,
        blocked: 0,
        online: online,
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
    if (name == #suggestedOpeningCashMinor) return Future<int>.value(85000);
    if (name == #refreshConnectivity) return Future<bool>.value(online);
    if (name == #lanStop || name == #logout) return Future<void>.value();
    if (name == #pendingOutboxCount) return Future<int>.value(0);
    if (name == #checkTillElsewhere) {
      return Future<TillElsewhereView?>.value(elsewhere);
    }
    if (name == #openBillsNotice) {
      return Future<OpenBillsNoticeView?>.value(notice);
    }
    if (name == #branchOpenTills) {
      return Future<List<BranchOpenTillView>>.value(branchTills);
    }
    if (name == #syncOnTillOpenStatus) return sync ?? _syncDone;
    if (name == #syncNow) {
      syncNows += 1;
      return Future<SyncStatusView>.error(const MadarError.offline(detail: ''));
    }
    if (name == #openTill) {
      opens += 1;
      return Future<OpenTillOutcome>.value(
        OpenTillOutcome(
          till: elsewhere == null ? _till : null,
          verification: 'server',
          openElsewhere: elsewhere,
        ),
      );
    }
    if (name == #forceCloseTill) {
      forceClosed.add(invocation.namedArguments[#tillId] as String);
      return Future<void>.value();
    }
    if (name == #closeTillPreview) {
      return Future<CloseTillPreviewView>.value(
        CloseTillPreviewView(
          till: _till,
          expectedCashMinor: 238000,
          methods: methods,
          lastTillWarning: lastTill,
          fromServer: online,
        ),
      );
    }
    if (name == #closeTill) {
      closes.add(
        invocation.namedArguments[#reconciliation] as List<ReconciliationInput>,
      );
      return Future<CloseTillOutcomeView>.value(
        const CloseTillOutcomeView(queued: false, reconciliation: []),
      );
    }
    return null;
  }
}

// ── Harness ────────────────────────────────────────────────────────────

Future<void> _shoot(
  WidgetTester tester, {
  required Widget screen,
  required _FakeBridge bridge,
  required Size size,
  required ThemeData theme,
  required String name,
  Future<void> Function(WidgetTester tester)? then,
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
          theme: theme,
          locale: Locale(bridge.arabic ? 'ar' : 'en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Directionality(
            textDirection: bridge.arabic
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: screen,
          ),
        ),
      ),
    ),
  );
  // The notifiers load on a microtask and the skeletons animate, so this is
  // a few frames rather than a pumpAndSettle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
  if (then != null) await then(tester);
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');
  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/render')..createSync(recursive: true);
    File(
      '${dir.path}/till-$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Loads the design system's Plex faces so the boards render real type —
/// without them the test binding's block font hides everything the picture
/// is for. The family name carries the package prefix because the styles do.
Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      final file = File('../../design_system/assets/fonts/$family-$cut.ttf');
      loader.addFont(file.readAsBytes().then<ByteData>(ByteData.sublistView));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(() async {
    _loadWords();
    await _loadFonts();
  });

  testWidgets('the Till on an iPad, mid-shift', (tester) async {
    await _shoot(
      tester,
      screen: TillScreen(onOpenOrders: () {}),
      bridge: _FakeBridge(),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'ipad',
    );
    // The screen's name, never the till's: that is data, in the top bar.
    expect(find.text('Till'), findsOneWidget);
    expect(find.text('Till 1'), findsNothing);
    expect(find.text('EGP 2,380.00'), findsOneWidget);
    // The pay-out form is its own page now; the Till shows the ledger.
    expect(find.byType(CashInOutPanel), findsNothing);
    expect(find.byType(CashLedger), findsOneWidget);
    expect(find.text('Preview X report'), findsOneWidget);
  });

  testWidgets('the Till offline, in the dark', (tester) async {
    await _shoot(
      tester,
      screen: TillScreen(onOpenOrders: () {}),
      bridge: _FakeBridge(online: false),
      size: _ipad,
      theme: MadarTheme.dark(),
      name: 'ipad-dark-offline',
    );
    // Both cards say where their figures stand.
    expect(find.text('\u20663\u2069 queued'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets("a manager's Till lists every drawer", (tester) async {
    await _shoot(
      tester,
      screen: TillScreen(onOpenOrders: () {}),
      bridge: _FakeBridge(role: 'branch_manager'),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'ipad-manager',
    );
    expect(find.text('Hany'), findsWidgets);
    expect(find.text('Mona'), findsOneWidget);
    expect(find.text('DRAWERS'), findsOneWidget);
  });

  testWidgets('a teller does not see the drawers', (tester) async {
    await _shoot(
      tester,
      screen: const TillScreen(),
      bridge: _FakeBridge(),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'ipad-teller-unwired',
    );
    expect(find.byType(DrawersCard), findsNothing);
    // Unwired Orders row: the count is there, the chevron is not.
    expect(find.text(_en['till.orders_this_shift']!), findsOneWidget);
  });

  testWidgets('no shift: the Till is the open-shift card', (tester) async {
    await _shoot(
      tester,
      screen: const TillScreen(),
      bridge: _FakeBridge(till: null),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'ipad-no-shift',
    );
    expect(
      find.widgetWithText(MadarButton, _en['till.open_button']!),
      findsOneWidget,
    );
    expect(find.byType(CashInOutPanel), findsNothing);
    // The carry-over from the last close is the count until edited.
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, '850');
  });

  testWidgets('no shift, a manager still sees the drawers', (tester) async {
    await _shoot(
      tester,
      screen: const TillScreen(),
      bridge: _FakeBridge(till: null, role: 'branch_manager'),
      size: _phone,
      theme: MadarTheme.light(),
      name: 'phone-no-shift-manager',
    );
    expect(
      find.widgetWithText(MadarButton, _en['till.open_button']!),
      findsOneWidget,
    );
    expect(find.byType(DrawersCard), findsOneWidget);
  });

  testWidgets('the Till on a phone, in Arabic', (tester) async {
    await _shoot(
      tester,
      screen: TillScreen(onOpenOrders: () {}),
      bridge: _FakeBridge(arabic: true),
      size: _phone,
      theme: MadarTheme.light(),
      name: 'phone-ar',
    );
    expect(find.byType(CashInOutPanel), findsNothing);
    expect(find.text(_ar['till.title']!), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(MadarButton, _ar['till.close_title']!),
      300,
    );
  });

  testWidgets('close shift on an iPad, short by 20', (tester) async {
    await _shoot(
      tester,
      screen: const CloseTillScreen(),
      bridge: _FakeBridge(),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'close-ipad',
      then: (tester) async {
        await tester.enterText(find.byType(TextField).first, '2360');
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
    expect(find.text('Short by'), findsOneWidget);
    expect(find.text('EGP 20.00'), findsOneWidget);
    expect(find.text('reason required'), findsOneWidget);
    expect(find.text('Why is it short?'), findsOneWidget);
    // The arithmetic closes on the expected figure.
    expect(find.text('+EGP 1,420.00'), findsOneWidget);
  });

  testWidgets('close shift on a phone, drawer matches', (tester) async {
    await _shoot(
      tester,
      screen: const CloseTillScreen(),
      bridge: _FakeBridge(),
      size: _phone,
      theme: MadarTheme.light(),
      name: 'close-phone',
      then: (tester) async {
        await tester.enterText(find.byType(TextField).first, '2380');
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
    expect(find.text('Drawer matches'), findsOneWidget);
    expect(find.text('reason required'), findsNothing);
  });

  testWidgets('cash in / out on a phone, in Arabic', (tester) async {
    await _shoot(
      tester,
      screen: const CashMovementsScreen(),
      bridge: _FakeBridge(arabic: true),
      size: _phone,
      theme: MadarTheme.light(),
      name: 'cash-phone-ar',
    );
    // Record is disabled until there is an amount AND a note.
    final record = tester.widget<MadarButton>(
      find.widgetWithText(MadarButton, 'تسجيل السحب'),
    );
    expect(record.enabled, isFalse);
  });

  // ── Tills rework flows ────────────────────────────────────────────────

  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.widgetWithText(MadarButton, label).last;
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> typeInto(WidgetTester tester, Key key, String text) async {
    final field = find.descendant(
      of: find.byKey(key),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.enterText(field, text);
    await tester.pump(const Duration(milliseconds: 100));
  }

  for (final (label, size, arabic, dark) in [
    ('ipad', _ipad, false, false),
    ('ipad-ar-dark', _ipad, true, true),
    ('phone', _phone, false, true),
    ('phone-ar', _phone, true, false),
  ]) {
    testWidgets('open till, blocked elsewhere + bills left open, $label', (
      tester,
    ) async {
      await _shoot(
        tester,
        screen: const TillScreen(),
        bridge: _FakeBridge(
          till: null,
          arabic: arabic,
          role: 'branch_manager',
          elsewhere: _elsewhere,
          notice: _notice,
          sync: _syncStale,
        ),
        size: size,
        theme: dark ? MadarTheme.dark() : MadarTheme.light(),
        name: 'open-blocked-$label',
      );
      expect(find.byType(TillElsewherePanel), findsOneWidget);
      expect(find.byType(OpenBillsNoticeBanner), findsOneWidget);
    });

    testWidgets('close till with payment checks, $label', (tester) async {
      await _shoot(
        tester,
        screen: const CloseTillScreen(),
        bridge: _FakeBridge(arabic: arabic),
        size: size,
        theme: dark ? MadarTheme.dark() : MadarTheme.light(),
        name: 'close-checks-$label',
        then: (tester) async {
          await tester.enterText(find.byType(TextField).first, '2380');
          await tester.pump(const Duration(milliseconds: 100));
          final words = arabic ? _ar : _en;
          final disagree = find
              .widgetWithText(MadarButton, words['till.reconcile_disagree']!)
              .first;
          await tester.ensureVisible(disagree);
          await tester.pump();
          await tester.tap(disagree);
          await tester.pump(const Duration(milliseconds: 300));
          await typeInto(
            tester,
            const ValueKey('declared-CIB – counter'),
            '4700',
          );
          await tester.pump(const Duration(milliseconds: 100));
          await tester.ensureVisible(
            find.byKey(const ValueKey('declared-CIB – counter')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );
      expect(find.byType(MadarSegmented<String>), findsNWidgets(2));
    });

    testWidgets('the Till with the branch open tills, $label', (tester) async {
      await _shoot(
        tester,
        screen: TillScreen(onOpenOrders: () {}),
        bridge: _FakeBridge(arabic: arabic, notice: _notice),
        size: size,
        theme: dark ? MadarTheme.dark() : MadarTheme.light(),
        name: 'branch-tills-$label',
        then: (tester) async {
          await tester.scrollUntilVisible(
            find.text('Hany'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump(const Duration(milliseconds: 300));
        },
      );
      expect(find.text('Hany'), findsOneWidget);
    });
  }

  testWidgets('open_till_screen_shows_open_elsewhere_panel', (tester) async {
    final teller = _FakeBridge(till: null, elsewhere: _elsewhere);
    await _shoot(
      tester,
      screen: const TillScreen(),
      bridge: teller,
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'flow-elsewhere-teller',
    );
    expect(find.text(_en['till.open_elsewhere_title']!), findsOneWidget);
    expect(find.textContaining('Terrace iPad'), findsOneWidget);
    // Opening here is off, and a teller gets no force close.
    final open = tester.widget<MadarButton>(
      find.widgetWithText(MadarButton, _en['till.open_button']!),
    );
    expect(open.enabled, isFalse);
    expect(
      find.widgetWithText(MadarButton, _en['till.force_close_elsewhere']!),
      findsNothing,
    );
  });

  testWidgets('a manager force-closes the till open elsewhere', (tester) async {
    final manager = _FakeBridge(
      till: null,
      elsewhere: _elsewhere,
      role: 'branch_manager',
    );
    await _shoot(
      tester,
      screen: const TillScreen(),
      bridge: manager,
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'flow-elsewhere-manager',
    );
    await tapButton(tester, _en['till.force_close_elsewhere']!);
    // A confirm first; nothing is closed until it is answered.
    expect(manager.forceClosed, isEmpty);
    await tapButton(tester, _en['till.force_close_elsewhere']!);
    expect(manager.forceClosed, ['sh-9']);
  });

  testWidgets('open_till_screen_shows_open_bills_banner', (tester) async {
    await _shoot(
      tester,
      screen: const TillScreen(),
      bridge: _FakeBridge(till: null, notice: _notice),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'flow-bills-banner',
    );
    expect(find.byType(OpenBillsNoticeBanner), findsOneWidget);
    // The count, and the old ones against the branch's hours.
    final banner = tester.widget<NoticeBanner>(
      find.descendant(
        of: find.byType(OpenBillsNoticeBanner),
        matching: find.byType(NoticeBanner),
      ),
    );
    expect(banner.text, contains(MadarFormat.ltr('4')));
    expect(banner.text, contains(MadarFormat.ltr('2')));
    expect(banner.tone, ChipTone.warning);
    // Bills never block opening.
    final open = tester.widget<MadarButton>(
      find.widgetWithText(MadarButton, _en['till.open_button']!),
    );
    expect(open.enabled, isTrue);
  });

  for (final (view, key) in [
    (_syncRunning, 'sync.running'),
    (_syncDone, 'sync.done'),
  ]) {
    testWidgets('open_till_sync_strip_states: ${view.state}', (tester) async {
      await _shoot(
        tester,
        screen: const TillScreen(),
        bridge: _FakeBridge(till: null, sync: view),
        size: _ipad,
        theme: MadarTheme.light(),
        name: 'flow-sync-${view.state}',
      );
      expect(find.text(_en[key]!), findsOneWidget);
    });
  }

  testWidgets('open_till_sync_strip_states: stale', (tester) async {
    final stale = _FakeBridge(till: null, sync: _syncStale);
    await _shoot(
      tester,
      screen: const TillScreen(),
      bridge: stale,
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'flow-sync-stale',
    );
    expect(
      find.textContaining(_en['sync.stale_offline']!.split('{')[0]),
      findsOneWidget,
    );
    await tapButton(tester, _en['sync.retry']!);
    expect(stale.syncNows, 1);
  });

  testWidgets('sync_strip_never_blocks_selling', (tester) async {
    final bridge = _FakeBridge(till: null, sync: _syncRunning);
    await _shoot(
      tester,
      screen: const TillScreen(),
      bridge: bridge,
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'flow-sync-open',
    );
    expect(find.text(_en['sync.running']!), findsOneWidget);
    await tapButton(tester, _en['till.open_button']!);
    expect(bridge.opens, 1);
    // The sell header shows it too, for its first minute, and then lets go.
    final started = DateTime.parse('2026-09-12T15:02:04Z');
    expect(tillSyncShowsInHeader(_syncRunning, started), isTrue);
    expect(
      tillSyncShowsInHeader(
        _syncDone,
        started.add(const Duration(seconds: 30)),
      ),
      isTrue,
    );
    expect(
      tillSyncShowsInHeader(_syncDone, started.add(const Duration(minutes: 2))),
      isFalse,
    );
  });

  testWidgets('close_till_screen_requires_note_on_disagree', (tester) async {
    final bridge = _FakeBridge();
    await _shoot(
      tester,
      screen: const CloseTillScreen(),
      bridge: bridge,
      size: _phone,
      theme: MadarTheme.light(),
      name: 'flow-close-note',
    );
    await tester.enterText(find.byType(TextField).first, '2380');
    await tester.pump(const Duration(milliseconds: 100));
    Finder choice(String key) => find.widgetWithText(MadarButton, _en[key]!);
    // CIB does not match; InstaPay is checked.
    await tester.ensureVisible(choice('till.reconcile_disagree').first);
    await tester.pump();
    await tester.tap(choice('till.reconcile_disagree').first);
    await tester.pump(const Duration(milliseconds: 200));
    await typeInto(tester, const ValueKey('declared-CIB – counter'), '4700');
    await tester.ensureVisible(choice('till.reconcile_checked').last);
    await tester.pump();
    await tester.tap(choice('till.reconcile_checked').last);
    await tester.pump(const Duration(milliseconds: 200));
    await tapButton(tester, _en['till.close_title']!);
    expect(bridge.closes, isEmpty);
    expect(find.text(_en['till.reconcile_note_required']!), findsWidgets);
    await typeInto(
      tester,
      const ValueKey('note-CIB – counter'),
      'Machine batch cut early',
    );
    await tapButton(tester, _en['till.close_title']!);
    expect(bridge.closes, hasLength(1));
    final sent = bridge.closes.single;
    expect(sent.map((r) => r.method), ['CIB – counter', 'InstaPay']);
    expect(sent.first.status, 'disagreed');
    expect(sent.first.declaredAmountMinor, 470000);
    expect(sent.first.note, 'Machine batch cut early');
    expect(sent.last.status, 'checked');
    expect(sent.last.declaredAmountMinor, isNull);
  });

  testWidgets('close_till_last_till_warning_is_non_blocking', (tester) async {
    final bridge = _FakeBridge(methods: [_methods.first], lastTill: _lastTill);
    await _shoot(
      tester,
      screen: const CloseTillScreen(),
      bridge: bridge,
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'flow-close-last',
    );
    await tester.enterText(find.byType(TextField).first, '2380');
    await tester.pump(const Duration(milliseconds: 100));
    await tapButton(tester, _en['till.close_title']!);
    expect(find.text(_en['till.last_till_title']!), findsOneWidget);
    expect(bridge.closes, isEmpty);
    await _capture(tester, 'flow-close-last-dialog');
    await tapButton(tester, _en['till.close_anyway']!);
    expect(bridge.closes, hasLength(1));
  });
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/render')..createSync(recursive: true);
    File(
      '${dir.path}/till-$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
