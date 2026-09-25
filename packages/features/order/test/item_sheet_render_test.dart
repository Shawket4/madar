// The item detail sheet: modifier groups (size, a milk swap family
// preselected on full-fat, extras) and recipe steps (one animated, one still,
// one typed) — iPad landscape and phone, EN/AR, light/dark.
//
// `MADAR_RENDER=true` writes `build/render/sheet-<scene>-<tag>.png`.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

final String _lottie = File(
  '../../design_system/assets/lottie/empty_cart.json',
).absolute.path;

const _addons = [
  ItemAddonView(
    addonItemId: 'full',
    name: 'Full fat',
    addonType: 'milk_type',
    chargedPriceMinor: 0,
  ),
  ItemAddonView(
    addonItemId: 'oat',
    name: 'Oat',
    addonType: 'milk_type',
    chargedPriceMinor: 500,
  ),
  ItemAddonView(
    addonItemId: 'almond',
    name: 'Almond',
    addonType: 'milk_type',
    chargedPriceMinor: 700,
  ),
  ItemAddonView(
    addonItemId: 'shot',
    name: 'Extra shot',
    addonType: 'extra',
    chargedPriceMinor: 800,
  ),
  ItemAddonView(
    addonItemId: 'syrup',
    name: 'Vanilla syrup',
    addonType: 'extra',
    chargedPriceMinor: 600,
  ),
];

ModifierOptionView _opt(String id, String name, int price) =>
    ModifierOptionView(id: id, name: name, chargedPriceMinor: price);

final _groups = [
  ModifierGroupView(
    groupId: 'g-milk',
    name: 'Milk',
    kind: ModifierGroupKind.addon,
    addonType: 'milk_type',
    isRequired: true,
    minSelections: 1,
    maxSelections: 1,
    options: [
      _opt('full', 'Full fat', 0),
      _opt('oat', 'Oat', 500),
      _opt('almond', 'Almond', 700),
    ],
  ),
  ModifierGroupView(
    groupId: 'g-extra',
    name: 'Extras',
    kind: ModifierGroupKind.addon,
    addonType: 'extra',
    isRequired: false,
    minSelections: 0,
    maxSelections: 3,
    options: [
      _opt('shot', 'Extra shot', 800),
      _opt('syrup', 'Vanilla syrup', 600),
    ],
  ),
];

MenuItemView _latte() => MenuItemView(
  kind: 'item',
  id: 'latte',
  name: 'Spanish latte',
  basePriceMinor: 4500,
  isActive: true,
  defaultMilkAddonId: 'full',
  allowedAddonIds: const [],
  sizes: const [
    ItemSizeView(id: 's', label: 'Small', priceMinor: 4500, isActive: true),
    ItemSizeView(id: 'm', label: 'Medium', priceMinor: 5500, isActive: true),
    ItemSizeView(id: 'l', label: 'Large', priceMinor: 6500, isActive: true),
  ],
  addonSlots: const [],
  optionalFields: const [],
  recipes: const [],
  recipeSteps: [
    RecipeStepView(name: 'Pull a double shot', localAnimationPath: _lottie),
    RecipeStepView(name: 'Steam the milk', localAnimationPath: _lottie),
    const RecipeStepView(name: 'Pour over condensed milk', note: '30 ml'),
  ],
);

class _Fake implements MadarBridge {
  _Fake({this.rtl = false});
  final bool rtl;

  @override
  dynamic noSuchMethod(Invocation i) {
    final can = fakeCanInvocation(i, () => currentSession()?.role);
    if (can != null) return can;
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
    if (n == #previewConfiguredLine) {
      final qty = (a[#qty] as int?) ?? 1;
      return Future.value(
        LinePreviewView(
          unitTotalMinor: 6000,
          extrasMinor: 500,
          lineTotalMinor: 6000 * qty,
        ),
      );
    }
    if (n == #listItemAddons) return Future.value(_addons);
    if (n == #listItemModifierGroups) return Future.value(_groups);
    // The one owner's sync read: this person's OWN open till, or none.
    if (n == #ownOpenTill) return null;
    if (n == #currentTill || n == #refreshTill) {
      return Future<TillView?>.value();
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

Future<void> _open(
  WidgetTester tester, {
  required Size size,
  required bool ar,
  required bool dark,
  required WidgetBuilder sheet,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [bridgeProvider.overrideWithValue(_Fake(rtl: ar))],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? MadarTheme.dark() : MadarTheme.light(),
          locale: Locale(ar ? 'ar' : 'en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => Directionality(
            textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showMadarSheet<void>(
                    context,
                    size: SheetSize.hug,
                    builder: sheet,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // Real IO for the Lottie file, then let the sheet settle.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump(const Duration(milliseconds: 120));
}

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');
  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    return await image.toByteData(format: ui.ImageByteFormat.png);
  });
  final dir = Directory('build/render')..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  setUpAll(_loadFonts);

  const devices = <(String, Size)>[
    ('ipad', Size(1194, 834)),
    // The iPad 9th generation, landscape and portrait, and an 8" Android.
    ('ipad9', Size(1080, 810)),
    ('ipad9p', Size(810, 1080)),
    ('tab8', Size(800, 1280)),
    ('lenovo', Size(1280, 800)),
    ('phone', Size(390, 844)),
  ];
  for (final (device, size) in devices) {
    for (final ar in [false, true]) {
      for (final dark in [false, true]) {
        final tag = '$device-${ar ? 'ar' : 'en'}-${dark ? 'dark' : 'light'}';

        testWidgets('item sheet $tag', (tester) async {
          await _open(
            tester,
            size: size,
            ar: ar,
            dark: dark,
            sheet: (_) => ItemDetailSheet(
              item: _latte(),
              addons: _addons,
              groups: _groups,
            ),
          );
          expect(find.byType(ItemDetailSheet), findsOneWidget);
          await _capture(tester, 'sheet-item-$tag');
        });
      }
    }
  }
}
