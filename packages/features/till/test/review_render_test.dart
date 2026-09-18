// Renders Waste and the manager-actions batch ("N actions need a manager",
// its list and the one PIN sheet) to PNG so they can be LOOKED at on the
// small tablets — `MADAR_RENDER=true` writes `build/render/review-*.png`.
// Without the flag every frame still lays out and fails on any exception,
// which is the part CI cares about.
//
// The words come from the core's own tables (`i18n.rs`), as in
// till_render_test.dart, so the pictures carry what a device shows.

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

/// The small tablets the owner ships on, and the 13" for reference.
const _devices = <(String, Size)>[
  ('ipad', Size(1194, 834)),
  ('ipad9', Size(1080, 810)),
  ('ipad9p', Size(810, 1080)),
  ('tab8', Size(800, 1280)),
  ('lenovo', Size(1280, 800)),
];

// ── The core's words ───────────────────────────────────────────────────

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

const _refusedVoid = ManagerActionView(
  id: 'op:7',
  kind: 'refused',
  what: 'Void',
  why: 'The server would not accept it without a manager.',
  capability: 'orders.void',
  personName: 'Sara',
  personId: 'u-teller',
  occurredAt: '2026-09-17T10:00:00Z',
  amountMinor: 500,
);
const _flaggedDiscount = ManagerActionView(
  id: 'flag:3',
  kind: 'flagged',
  what: 'Discount over the cap',
  why: 'It went through, but without the permission.',
  capability: 'orders.discount.manual_amount',
  personName: 'Sara',
  personId: 'u-teller',
  occurredAt: '2026-09-17T09:00:00Z',
);
const _refusedRefund = ManagerActionView(
  id: 'op:9',
  kind: 'refused',
  what: 'Refund · #1002',
  why: 'Refunds need a manager on this till.',
  capability: 'refunds.create',
  personName: 'Hany',
  personId: 'u-teller-2',
  occurredAt: '2026-09-17T11:30:00Z',
  amountMinor: 16000,
);

ManagerActionsView _list(List<ManagerActionView> items) => ManagerActionsView(
  count: items.length,
  items: items,
  headline: '${items.length} actions need a manager',
  canAuthorize: true,
  blockedReason: '',
);

class _FakeBridge implements MadarBridge {
  _FakeBridge({this.arabic = false, this.wasteOutcome = 'allow'});

  final bool arabic;

  /// What the core decides for the waste ('allow' or 'needs_approval').
  final String wasteOutcome;

  ManagerActionsView view = _list(const [
    _refusedVoid,
    _flaggedDiscount,
    _refusedRefund,
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final args = invocation.namedArguments;
    final lang = arabic ? 'ar' : 'en';
    if (name == #tr) {
      final key = args[#key] as String? ?? '';
      return (arabic ? _ar[key] : _en[key]) ?? key;
    }
    if (name == #locale) return lang;
    if (name == #isRtl) return arabic;
    if (name == #currentSession) return null;
    if (name == #formatMoney) {
      return MadarFormat.money(
        args[#minor] as int,
        currency: args[#currency] as String,
        signed: args[#signed] as bool,
        locale: lang,
      );
    }
    if (name == #formatStamp) {
      final at = DateTime.parse(args[#rfc3339] as String);
      return MadarFormat.stamp(
        at,
        DateTime(at.year, at.month, at.day),
        locale: lang,
      );
    }
    // Manager actions.
    if (name == #pendingManagerActions) return view;
    if (name == #refreshReviewFlags) return Future<int>.value(0);
    if (name == #authorizeManagerActions) {
      return Future<BatchAuthorizeView>.value(
        const BatchAuthorizeView(
          authorized: ['op:7', 'flag:3', 'op:9'],
          left: [],
          summary: '3 of 3',
        ),
      );
    }
    // Waste.
    if (name == #wasteItems) {
      return const [
        WasteItemView(id: 'latte', name: 'Latte', sizes: ['Small', 'Large']),
        WasteItemView(id: 'cake', name: 'Chocolate cake', sizes: []),
      ];
    }
    if (name == #wasteIngredients) {
      return const [
        WasteIngredientView(
          id: 'milk',
          name: 'Milk',
          unit: 'ml',
          units: ['ml', 'l'],
        ),
      ];
    }
    if (name == #wasteReasons) {
      return const [
        WasteReasonView(key: 'spoiled', label: 'Spoiled'),
        WasteReasonView(key: 'dropped', label: 'Dropped'),
        WasteReasonView(key: 'other', label: 'Other'),
      ];
    }
    if (name == #previewWaste) {
      return WastePreviewView(
        lines: const [
          WasteLineView(name: 'Beans', quantity: 18, unit: 'g'),
          WasteLineView(name: 'Milk', quantity: 220, unit: 'ml'),
        ],
        valueMinor: 1200,
        valuePartial: false,
        decision: ActDecisionView(
          outcome: wasteOutcome,
          reason: wasteOutcome == 'allow' ? '' : 'over your limit',
        ),
      );
    }
    if (name == #approveWaste) {
      return Future<ApprovalView>.value(
        const ApprovalView(
          id: 'ap-1',
          capability: 'inventory.waste.record',
          approverId: 'm-1',
          approverName: 'Mona',
          valueMinor: 1200,
        ),
      );
    }
    if (name == #recordWaste) {
      return Future<WasteRecordedView>.value(
        const WasteRecordedView(
          id: 'w-1',
          subjectName: 'Latte',
          quantity: 2,
          unit: 'pcs',
          valueMinor: 1200,
        ),
      );
    }
    return super.noSuchMethod(invocation);
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
          debugShowCheckedModeBanner: false,
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
  if (then != null) await then(tester);
  final error = tester.takeException();
  // The picture is written BEFORE the layout check, so a frame that
  // overflowed can be looked at (the stripe says where).
  if (_render) {
    final boundary =
        tester.renderObject(find.byKey(const ValueKey('shot')))
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/render')..createSync(recursive: true);
      File(
        '${dir.path}/review-$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }
  expect(error, isNull, reason: '$name laid out cleanly');
  // No raw key on screen: every word the screen asks for exists in the core.
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    final s = t.data ?? '';
    expect(
      RegExp(r'^[a-z]+\.[a-z_.]+$').hasMatch(s),
      isFalse,
      reason: '$name shows the raw key "$s"',
    );
  }
}

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

/// Fill the waste form the way a teller does: an item, its size, a
/// quantity and a reason — so the preview and the Record bar are on screen.
Future<void> _fillWaste(WidgetTester tester) async {
  await tester.tap(find.text('Latte'));
  await tester.pump();
  await tester.tap(find.text('Large'));
  await tester.enterText(
    find
        .byWidgetPredicate(
          (w) => w is EditableText && w.controller.text.isEmpty,
        )
        .at(1),
    '2',
  );
  await tester.pump();
  await tester.tap(find.text('Spoiled'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    _loadWords();
    await _loadFonts();
  });

  for (final (device, size) in _devices) {
    for (final arabic in [false, true]) {
      for (final dark in [false, true]) {
        final tag =
            '$device-${arabic ? 'ar' : 'en'}-${dark ? 'dark' : 'light'}';
        final theme = dark ? MadarTheme.dark() : MadarTheme.light();

        testWidgets('waste, filled in, $tag', (tester) async {
          await _shoot(
            tester,
            screen: const WasteScreen(),
            bridge: _FakeBridge(arabic: arabic),
            size: size,
            theme: theme,
            name: 'waste-$tag',
            then: _fillWaste,
          );
          expect(find.text('Beans'), findsOneWidget, reason: 'the preview');
        });

        testWidgets('manager actions, the list, $tag', (tester) async {
          await _shoot(
            tester,
            screen: const ManagerActionsScreen(),
            bridge: _FakeBridge(arabic: arabic),
            size: size,
            theme: theme,
            name: 'actions-$tag',
          );
          expect(find.text('Void'), findsWidgets);
        });

        // The PIN sheet: dark only on the one device where dark is in the
        // sibling matrices' cheap pass; every device in light.
        if (dark && device != 'ipad9') continue;

        testWidgets('manager actions, the PIN sheet, $tag', (tester) async {
          await _shoot(
            tester,
            screen: const ManagerActionsScreen(),
            bridge: _FakeBridge(arabic: arabic),
            size: size,
            theme: theme,
            name: 'actions-pin-$tag',
            then: (tester) async {
              final word = (arabic ? _ar : _en)['review.title']!;
              await tester.tap(find.widgetWithText(MadarButton, word).last);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 400));
              await tester.enterText(find.byType(EditableText).last, '99');
              await tester.pump();
            },
          );
          expect(find.byType(EditableText), findsWidgets);
        });

        testWidgets('waste over the limit asks for a manager, $tag', (
          tester,
        ) async {
          await _shoot(
            tester,
            screen: const WasteScreen(),
            bridge: _FakeBridge(arabic: arabic, wasteOutcome: 'needs_approval'),
            size: size,
            theme: theme,
            name: 'waste-approval-$tag',
            then: (tester) async {
              await _fillWaste(tester);
              final word = (arabic ? _ar : _en)['waste.record']!;
              await tester.tap(find.text(word).last);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 400));
            },
          );
        });
      }
    }
  }
}
