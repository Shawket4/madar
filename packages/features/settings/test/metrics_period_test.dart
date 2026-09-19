// The Metrics screen's period control: one date-range picker, the way the
// dashboard's period filter works.
//
// Renders it open at the four tablet sizes the responsive work introduced, in
// English and Arabic (and dark, on the size the shops actually run), so the
// calendar's own RTL layout — the week starting in the reading-first column,
// Arabic month and weekday names — can be LOOKED at rather than reasoned
// about. Set MADAR_RENDER=true for `build/render/period-*.png`; left unset the
// same tests still build every board and fail on a layout exception.
//
// Then the behaviour: a preset pill answers on its own, two taps draw a window
// with the second day previewing before it lands, the branch's tomorrow is
// dead, Apply is what reaches the core, and the trigger says which of the two
// kinds of window is in effect.

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

/// The four tablet windows the responsive work pinned. Metrics is a reading
/// page, so the picker has to sit well in the narrow ones too.
const _sizes = <String, Size>{
  'ipad9-landscape': Size(1080, 810),
  'ipad9-portrait': Size(810, 1080),
  'tablet8': Size(800, 1280),
  'lenovo': Size(1280, 800),
};

/// Saturday 19 September 2026 in the branch — so the grid's first column is
/// today's, and the 20th is the branch's tomorrow.
const _today = '2026-09-19';  // the default `fakeDatePickerChrome` carries

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

/// One window the core answered, as the screen asked for it.
typedef _Ask = ({String preset, String? from, String? to});

/// A bridge that answers the Metrics screen and REMEMBERS every window asked
/// for, which is the only thing these tests need from the core.
class _FakeBridge implements MadarBridge {
  _FakeBridge({this.lang = 'en'});

  final String lang;

  /// Every `posMetrics` call, in order.
  final List<_Ask> asks = [];

  String _w(String key) => coreWord(key, arabic: lang == 'ar');

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => _manager.role);
    if (can != null) return can;
    final name = invocation.memberName;
    if (name == #tr) {
      return _w(invocation.namedArguments[#key] as String? ?? '');
    }
    if (name == #locale) return lang;
    if (name == #isRtl) return lang == 'ar';
    if (name == #currentSession) return _manager;
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
          MetricsPresetView(key: k, label: _w('metrics.preset.$k')),
      ];
    }
    if (name == #posMetrics) {
      final a = invocation.namedArguments;
      asks.add((
        preset: a[#preset] as String,
        from: a[#customFrom] as String?,
        to: a[#customTo] as String?,
      ));
      return Future<PosMetricsView>.value(_metrics());
    }
    if (name == #formatMoney) {
      final a = invocation.namedArguments;
      return MadarFormat.money(
        a[#minor] as int,
        currency: a[#currency] as String,
        signed: a[#signed] as bool,
        locale: lang,
      );
    }
    return null;
  }

  PosMetricsView _metrics() => PosMetricsView(
    preset: 'today',
    fromDate: _today,
    toDate: _today,
    rangeLabel: lang == 'ar' ? 'سبتمبر 19' : 'Sep 19',
    source: 'server',
    currencyCode: 'EGP',
    netSalesMinor: 486500,
    grossSalesMinor: 512000,
    refundedAmountMinor: 25500,
    orderCount: 63,
    averageTicketMinor: 7722,
    tenders: const [
      MetricsTenderView(
        method: 'cash',
        label: 'Cash',
        amountMinor: 301000,
        orderCount: 41,
        share: 1,
      ),
      MetricsTenderView(
        method: 'card',
        label: 'Card',
        amountMinor: 185500,
        orderCount: 22,
        share: 0.62,
      ),
    ],
    voidedCount: 2,
    voidedAmountMinor: 9000,
    refundedOrdersCount: 1,
    refundsIssuedCount: 3,
    refundsIssuedAmountMinor: 25500,
    topItems: const [
      MetricsItemView(
        name: 'Latte',
        quantity: 14,
        revenueMinor: 91000,
        share: 1,
      ),
      MetricsItemView(
        name: 'Iced tea',
        quantity: 9,
        revenueMinor: 49500,
        share: 0.64,
      ),
    ],
    hourly: [
      for (var h = 0; h < 24; h++)
        MetricsHourView(
          hour: h,
          label: h.toString().padLeft(2, '0'),
          orderCount: h >= 9 && h <= 22 ? (h % 7) + 1 : 0,
          netSalesMinor: h >= 9 && h <= 22 ? ((h % 7) + 1) * 7000 : 0,
          share: h >= 9 && h <= 22 ? ((h % 7) + 1) / 7 : 0,
        ),
    ],
  );
}

/// Pump the Metrics screen at [size] and return the fake it runs on.
Future<_FakeBridge> _pump(
  WidgetTester tester, {
  required Size size,
  String lang = 'en',
  bool dark = false,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final bridge = _FakeBridge(lang: lang);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? MadarTheme.dark() : MadarTheme.light(),
          locale: Locale(lang),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const MetricsScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return bridge;
}

/// Open the picker sheet and let it settle.
Future<void> _openPicker(WidgetTester tester, {required String label}) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Let the sheet finish sliding out and the reload land. The screen keeps a
/// spinner up while it loads, so `pumpAndSettle` would never return.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A day square, by the `YYYY-MM-DD` it announces itself as.
Finder _day(String iso) => find.bySemanticsLabel(iso);

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

/// The real Plex faces, so the Arabic pictures are readable words.
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
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  // ── The pictures ──────────────────────────────────────────────────────

  for (final entry in _sizes.entries) {
    for (final lang in ['en', 'ar']) {
      testWidgets('the picker at ${entry.key} in $lang', (tester) async {
        await _pump(tester, size: entry.value, lang: lang);
        await _openPicker(
          tester,
          label: coreWord('metrics.preset.today', arabic: lang == 'ar'),
        );
        // The sheet is up, whole: the pills, the month, the grid, Apply.
        expect(
          find.text(coreWord('period.title', arabic: lang == 'ar')),
          findsOneWidget,
        );
        expect(_day('2026-09-19'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _save(tester, 'period-${entry.key}-$lang');
      });
    }
  }

  // A window half-drawn: the band between the two taps, and the second day
  // previewing under a finger that has not lifted.
  for (final lang in ['en', 'ar']) {
    testWidgets('a window being drawn, in $lang', (tester) async {
      await _pump(tester, size: _sizes['ipad9-landscape']!, lang: lang);
      await _openPicker(
        tester,
        label: coreWord('metrics.preset.today', arabic: lang == 'ar'),
      );
      await tester.tap(_day('2026-09-07'));
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(_day('2026-09-16')),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _save(tester, 'period-range-$lang');
      await gesture.up();
      await tester.pump();
    });
  }

  testWidgets('the picker in the dark, on the iPad', (tester) async {
    await _pump(tester, size: _sizes['ipad9-landscape']!, dark: true);
    await _openPicker(tester, label: 'Today');
    expect(tester.takeException(), isNull);
    await _save(tester, 'period-ipad9-landscape-dark');
  });

  testWidgets('the picker in the dark, in Arabic', (tester) async {
    await _pump(tester, size: _sizes['ipad9-landscape']!, lang: 'ar', dark: true);
    await _openPicker(tester, label: coreWord('metrics.preset.today', arabic: true));
    expect(tester.takeException(), isNull);
    await _save(tester, 'period-ipad9-landscape-ar-dark');
  });

  // ── The behaviour ─────────────────────────────────────────────────────

  testWidgets('the trigger says which window is in effect', (tester) async {
    final bridge = await _pump(tester, size: _sizes['lenovo']!);
    // The screen opens on the default preset, and the trigger says so.
    expect(find.text('Today'), findsOneWidget);
    expect(bridge.asks.single.preset, 'today');

    await _openPicker(tester, label: 'Today');
    await tester.tap(_day('2026-09-07'));
    await tester.pump();
    await tester.tap(_day('2026-09-10'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await _settle(tester);

    // Hand-picked: the trigger drops the preset name for the literal range.
    expect(find.text('Sep 7 – Sep 10'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
  });

  testWidgets('a preset pill is the whole answer', (tester) async {
    final bridge = await _pump(tester, size: _sizes['ipad9-portrait']!);
    await _openPicker(tester, label: 'Today');
    await tester.tap(find.text('This week'));
    await _settle(tester);

    // One tap: the sheet is gone and the core has been asked, with no days —
    // the window's maths stays in the core.
    expect(find.text('Apply'), findsNothing);
    expect(bridge.asks.last.preset, 'this_week');
    expect(bridge.asks.last.from, isNull);
    expect(find.text('This week'), findsOneWidget);
  });

  testWidgets('two taps draw a window, and the second previews first', (
    tester,
  ) async {
    await _pump(tester, size: _sizes['tablet8']!);
    await _openPicker(tester, label: 'Today');

    // Nothing picked yet: the screen asks for the first day.
    expect(find.text('Pick the first day'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));

    await tester.tap(_day('2026-09-07'));
    await tester.pump();
    expect(find.text('Pick the last day'), findsOneWidget);
    expect(find.text('Sep 7'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);

    // A finger DOWN on the 10th, not yet lifted: the window is previewed.
    final gesture = await tester.startGesture(
      tester.getCenter(_day('2026-09-10')),
    );
    await tester.pump();
    expect(find.text('Sep 10'), findsOneWidget);
    expect(find.text('—'), findsNothing);

    await gesture.up();
    await tester.pump();
    expect(find.text('Period picked'), findsOneWidget);
    expect(find.text('Sep 10'), findsOneWidget);
  });

  testWidgets('tapping before the start reverses the window', (tester) async {
    final bridge = await _pump(tester, size: _sizes['lenovo']!);
    await _openPicker(tester, label: 'Today');
    await tester.tap(_day('2026-09-10'));
    await tester.pump();
    await tester.tap(_day('2026-09-07'));
    await tester.pump();
    // Not refused, and not backwards: the earlier day became the start.
    expect(find.text('Sep 7'), findsOneWidget);
    expect(find.text('Sep 10'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await _settle(tester);
    expect(bridge.asks.last, (
      preset: 'custom',
      from: '2026-09-07',
      to: '2026-09-10',
    ));
  });

  testWidgets("the branch's tomorrow is dead", (tester) async {
    await _pump(tester, size: _sizes['ipad9-landscape']!);
    await _openPicker(tester, label: 'Today');

    // Today is selectable; the day after it is drawn but answers nothing.
    await tester.tap(_day('2026-09-20'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Pick the first day'), findsOneWidget);
    expect(find.text('Sep 20'), findsNothing);

    await tester.tap(_day('2026-09-19'));
    await tester.pump();
    // Also the page's own range label, under the title.
    expect(find.text('Sep 19'), findsWidgets);

    // And October is out of reach entirely — forward stops at today's month.
    expect(find.text('September 2026'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Next month'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('September 2026'), findsOneWidget);

    // Backwards still works.
    await tester.tap(find.bySemanticsLabel('Previous month'));
    await tester.pump();
    expect(find.text('August 2026'), findsOneWidget);
  });

  testWidgets('one day is one tap and Apply', (tester) async {
    final bridge = await _pump(tester, size: _sizes['tablet8']!);
    await _openPicker(tester, label: 'Today');
    await tester.tap(_day('2026-09-11'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await _settle(tester);
    expect(bridge.asks.last, (
      preset: 'custom',
      from: '2026-09-11',
      to: '2026-09-11',
    ));
    // The summary in the sheet, and the trigger now saying the same day.
    expect(find.text('Sep 11'), findsWidgets);
  });

  testWidgets('Arabic names the month and starts the week on Saturday', (
    tester,
  ) async {
    await _pump(tester, size: _sizes['ipad9-portrait']!, lang: 'ar');
    await _openPicker(tester, label: coreWord('metrics.preset.today', arabic: true));
    expect(find.text('سبتمبر 2026'), findsOneWidget);

    // The week's first column is Saturday's, and in Arabic it is the RIGHTMOST
    // one — the calendar mirrors, unlike a floor plan.
    final sat = tester.getCenter(find.text('سبت'));
    final fri = tester.getCenter(find.text('جمعة'));
    expect(sat.dx, greaterThan(fri.dx));

    // And Saturday's column holds the Saturdays.
    expect(tester.getCenter(_day('2026-09-19')).dx, closeTo(sat.dx, 1));
    expect(tester.getCenter(_day('2026-09-12')).dx, closeTo(sat.dx, 1));
  });
}
