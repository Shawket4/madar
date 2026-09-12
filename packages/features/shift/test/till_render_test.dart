// Renders the Till to PNG so it can be LOOKED at.
//
// The Till is where a teller reconciles a drawer, and a figure that sits
// wrong on the page is a figure that gets misread at 11pm. There is no
// simulator here; `MADAR_RENDER=true` writes `build/render/till-*.png` — the
// iPad Till in light, the same offline and in the dark, a manager's Till,
// the no-shift home, the close screen with a short count, and the phone in
// Arabic, mirrored. Without the flag it still builds every board and fails
// on any layout exception, which is the part CI cares about.
//
// The words in here are fixture text so the pictures read like the app; the
// app's own words come through `bridge.tr`.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_shift/feature_shift.dart';
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

// ── Fixture words ──────────────────────────────────────────────────────

const _en = <String, String>{
  'till.title': 'Till',
  'till.open_since': 'open since',
  'till.sales': 'Sales',
  'till.cash_in_till': 'Cash in till',
  'till.this_shift': 'This shift',
  'till.orders_this_shift': 'Orders this shift',
  'till.print_x': 'Print X report',
  'till.drawers': 'Drawers',
  'till.force_close_unavailable':
      'Force-close is not available from the till yet — use the dashboard.',
  'cash.title': 'Cash in / out',
  'cash.pay_out': 'Pay out',
  'cash.pay_in': 'Pay in',
  'cash.note_hint': 'Note · what was it for',
  'cash.note_required': 'required',
  'cash.record_pay_out': 'Record pay-out',
  'cash.record_pay_in': 'Record pay-in',
  'cash.net': 'net',
  'cash.empty': 'No cash movements this shift.',
  'shift.close_title': 'Close shift',
  'shift.expected_cash': 'Expected cash',
  'shift.opening_float': 'Opening float',
  'shift.cash_sales': 'Cash sales',
  'shift.paid_in': 'Paid in',
  'shift.paid_out': 'Paid out',
  'shift.z_preview': 'Z report preview',
  'shift.counted_cash': 'Counted cash',
  'shift.cash_note': 'Note (optional)',
  'shift.why_short': 'Why is it short?',
  'shift.why_over': 'Why is it over?',
  'shift.close_hint': 'Closing locks Sell and Charge on this till.',
  'shift.reason_required': 'reason required',
  'shift.drawer_matches': 'Drawer matches',
  'shift.drawer_over': 'Over by',
  'shift.drawer_short': 'Short by',
  'shift.orders': 'sales',
  'shift.opened_at': 'opened',
  'shift.welcome': 'Welcome back',
  'shift.opening_cash': 'Opening cash',
  'shift.open_button': 'Open shift',
  'shift.switch_teller': 'Switch teller',
  'shift.suggested_from_close': 'From last close',
  'shift.opening_hint':
      'Count the cash already in the drawer before you start.',
  'shifts.title': 'Past shifts',
  'shifts.open_now': 'Open',
  'shifts.closed': 'Closed',
  'shifts.force_closed': 'Force-closed',
  'shifts.empty': 'No shifts yet.',
  'chrome.queued': 'queued',
  'chrome.offline': 'Offline',
  'chrome.view': 'View',
  'history.voided': 'Voided',
};

const _ar = <String, String>{
  'till.title': 'الصندوق',
  'till.open_since': 'مفتوحة منذ',
  'till.sales': 'المبيعات',
  'till.cash_in_till': 'النقد في الدرج',
  'till.this_shift': 'هذه الوردية',
  'till.orders_this_shift': 'طلبات هذه الوردية',
  'till.print_x': 'طباعة تقرير X',
  'till.drawers': 'الأدراج',
  'till.force_close_unavailable':
      'الإغلاق الإجباري غير متاح من الصندوق بعد — استخدم لوحة التحكم.',
  'cash.title': 'إيداع / سحب',
  'cash.pay_out': 'سحب',
  'cash.pay_in': 'إيداع',
  'cash.note_hint': 'ملاحظة · لأي غرض',
  'cash.note_required': 'مطلوب',
  'cash.record_pay_out': 'تسجيل السحب',
  'cash.record_pay_in': 'تسجيل الإيداع',
  'cash.net': 'الصافي',
  'cash.empty': 'لا توجد حركات نقدية في هذه الوردية.',
  'shift.close_title': 'إغلاق الوردية',
  'shift.expected_cash': 'النقد المتوقع',
  'shift.opening_float': 'الرصيد الافتتاحي',
  'shift.cash_sales': 'المبيعات النقدية',
  'shift.paid_in': 'المودع',
  'shift.paid_out': 'المسحوب',
  'shift.z_preview': 'معاينة تقرير Z',
  'shift.counted_cash': 'النقد المحسوب',
  'shift.cash_note': 'ملاحظة (اختياري)',
  'shift.why_short': 'ما سبب النقص؟',
  'shift.why_over': 'ما سبب الزيادة؟',
  'shift.close_hint': 'الإغلاق يوقف البيع والتحصيل على هذا الصندوق.',
  'shift.reason_required': 'السبب مطلوب',
  'shift.drawer_matches': 'الدرج مطابق',
  'shift.drawer_over': 'زيادة',
  'shift.drawer_short': 'نقص',
  'shift.orders': 'مبيعات',
  'shift.opened_at': 'فُتحت',
  'shifts.title': 'الورديات السابقة',
  'shifts.open_now': 'مفتوحة',
  'shifts.closed': 'أُغلقت',
  'shifts.force_closed': 'أُغلقت إجبارياً',
  'shifts.empty': 'لا توجد ورديات بعد.',
  'chrome.queued': 'في الانتظار',
  'chrome.offline': 'غير متصل',
  'chrome.view': 'عرض',
  'history.voided': 'ملغاة',
};

// ── Fixture data ───────────────────────────────────────────────────────

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
      priceFlagged: false,
      orderType: 'dine_in',
    ),
];

const _drawers = <ShiftSummaryView>[
  ShiftSummaryView(
    id: 'sh-1',
    tellerName: 'Sara',
    openedAt: _openedAt,
    openingCashMinor: 85000,
    status: 'open',
    isOpen: true,
  ),
  ShiftSummaryView(
    id: 'sh-2',
    tellerName: 'Hany',
    openedAt: '2026-09-12T14:30:00Z',
    openingCashMinor: 85000,
    status: 'open',
    isOpen: true,
  ),
  ShiftSummaryView(
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
  ),
];

/// A bridge that answers what the Till asks, from fixtures. [shift] null is
/// a till with no drawer open; [online] false drives the honest tags.
class _FakeBridge implements MadarBridge {
  _FakeBridge({
    this.shift = _shift,
    this.role = 'teller',
    this.online = true,
    this.arabic = false,
  });

  final ShiftView? shift;
  final String role;
  final bool online;
  final bool arabic;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final open = shift?.isOpen ?? false;
    if (name == #tr) {
      final key = invocation.namedArguments[#key] as String? ?? '';
      return (arabic ? _ar[key] : null) ??
          _en[key] ??
          key.split('.').last.replaceAll('_', ' ');
    }
    if (name == #locale) return arabic ? 'ar' : 'en';
    if (name == #isRtl) return arabic;
    if (name == #appRoute) {
      return open ? const AppRoute.order() : const AppRoute.openShift();
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
        tillId: 't-1',
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
    if (name == #currentShift || name == #refreshShift) {
      return Future<ShiftView?>.value(shift);
    }
    if (name == #shiftReport) {
      return Future<ShiftReportView>.value(_report(fromServer: online));
    }
    if (name == #shiftReportFor) {
      return Future<ShiftReportView>.value(_report(fromServer: true));
    }
    if (name == #listShiftOrders) {
      return Future<List<OrderSummaryView>>.value(
        _orders(queued: online ? 0 : 3),
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
    if (name == #listTills) {
      return Future<List<TillView>>.value(const [
        TillView(id: 't-1', name: 'Till 1', isDefault: true, isActive: true),
      ]);
    }
    if (name == #listShifts) {
      return Future<List<ShiftSummaryView>>.value(_drawers);
    }
    if (name == #syncStatus) {
      return Future<SyncStatusView>.value(
        SyncStatusView(
          pending: online ? 0 : 3,
          failed: 0,
          blocked: 0,
          online: online,
          authPaused: false,
        ),
      );
    }
    if (name == #suggestedOpeningCashMinor) return Future<int>.value(85000);
    if (name == #refreshConnectivity) return Future<bool>.value(online);
    if (name == #lanStop || name == #logout) return Future<void>.value();
    if (name == #pendingOutboxCount) return Future<int>.value(0);
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
  setUpAll(_loadFonts);

  testWidgets('the Till on an iPad, mid-shift', (tester) async {
    await _shoot(
      tester,
      screen: TillScreen(onOpenOrders: () {}),
      bridge: _FakeBridge(),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'ipad',
    );
    expect(find.text('Till 1'), findsOneWidget);
    expect(find.text('EGP 2380.00'), findsOneWidget);
    expect(find.text('Record pay-out'), findsOneWidget);
    // Pay out leads and is the selected kind.
    final payOut = tester.widget<MadarChip>(
      find.widgetWithText(MadarChip, 'Pay out'),
    );
    expect(payOut.selected, isTrue);
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
    // Both cards say where their figures stand (tags are uppercased).
    expect(find.text('3 QUEUED'), findsOneWidget);
    expect(find.text('OFFLINE'), findsOneWidget);
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
    expect(find.text('Hany'), findsOneWidget);
    expect(find.text('Mona'), findsOneWidget);
    expect(find.text('DRAWERS · RUE ZAMALEK'), findsOneWidget);
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
    expect(find.text('Orders this shift'), findsOneWidget);
  });

  testWidgets('no shift: the Till is the open-shift card', (tester) async {
    await _shoot(
      tester,
      screen: const TillScreen(),
      bridge: _FakeBridge(shift: null),
      size: _ipad,
      theme: MadarTheme.light(),
      name: 'ipad-no-shift',
    );
    expect(find.text('Open shift'), findsOneWidget);
    expect(find.byType(CashInOutPanel), findsNothing);
    // The carry-over from the last close is the count until edited.
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, '850');
  });

  testWidgets('no shift, a manager still sees the drawers', (tester) async {
    await _shoot(
      tester,
      screen: const TillScreen(),
      bridge: _FakeBridge(shift: null, role: 'branch_manager'),
      size: _phone,
      theme: MadarTheme.light(),
      name: 'phone-no-shift-manager',
    );
    expect(find.text('Open shift'), findsOneWidget);
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
    // The phone carries the ledger as a row, not inline.
    expect(find.byType(CashInOutPanel), findsNothing);
    expect(find.text('إغلاق الوردية'), findsOneWidget);
  });

  testWidgets('close shift on an iPad, short by 20', (tester) async {
    await _shoot(
      tester,
      screen: const CloseShiftScreen(),
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
    expect(find.text('+EGP 1420.00'), findsOneWidget);
  });

  testWidgets('close shift on a phone, drawer matches', (tester) async {
    await _shoot(
      tester,
      screen: const CloseShiftScreen(),
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
}
