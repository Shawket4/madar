// Fast mode's Extras step (owner, 2026-09-26): the Extras group is a row in
// Fast mode that opens every extra on a page of its own, A–Z with a
// contacts-style index rail. The standard sheet keeps its card.
//
// `MADAR_RENDER=true` writes `build/render/extras-*.png` for the owner.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/extras_page.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

/// Drops' Extras on prod (2026-09-26), in EN, with the Arabic the shop uses.
const _extrasEn = <(String, String, int)>[
  ('shot', 'Extra Shot', 5000),
  ('condensed', 'Condensed Milk', 6000),
  ('honey', 'Honey', 2500),
  ('vanilla', 'Vanilla Syrup', 3500),
  ('caramel', 'Caramel Syrup', 3500),
  ('hazelnut', 'Hazelnut Syrup', 3500),
  ('vanilla-sf', 'Vanilla Syrup (Sugar Free)', 3500),
  ('caramel-sf', 'Caramel Syrup (Sugar Free)', 3500),
  ('salted-sf', 'Salted Caramel Syrup (Sugar Free)', 3500),
  ('hazelnut-sf', 'Hazelnut Syrup (Sugar Free)', 3500),
  ('cream', 'Whipped Cream', 2000),
  ('cinnamon', 'Cinnamon', 0),
  ('choc-sauce', 'Chocolate Sauce', 2500),
  ('white-choc', 'White Chocolate Sauce', 2500),
  ('pistachio', 'Pistachio Sauce', 4000),
  ('lotus', 'Lotus Sauce', 3000),
  ('oreo', 'Oreo Crumbs', 2500),
  ('ice-cream', 'Ice Cream Scoop', 4000),
  ('boba', 'Boba', 3000),
  ('mint', 'Fresh Mint', 1000),
  ('2x', '2x Espresso', 5000),
];

const _extrasAr = <String, String>{
  'shot': 'شوت إضافي',
  'condensed': 'حليب مكثف',
  'honey': 'عسل',
  'vanilla': 'سيرب فانيليا',
  'caramel': 'سيرب كراميل',
  'hazelnut': 'سيرب بندق',
  'vanilla-sf': 'سيرب فانيليا (بدون سكر)',
  'caramel-sf': 'سيرب كراميل (بدون سكر)',
  'salted-sf': 'سيرب كراميل مملح (بدون سكر)',
  'hazelnut-sf': 'سيرب بندق (بدون سكر)',
  'cream': 'كريمة مخفوقة',
  'cinnamon': 'قرفة',
  'choc-sauce': 'صوص شوكولاتة',
  'white-choc': 'صوص شوكولاتة بيضاء',
  'pistachio': 'صوص فستق',
  'lotus': 'صوص لوتس',
  'oreo': 'أوريو',
  'ice-cream': 'بولة آيس كريم',
  'boba': 'بوبا',
  'mint': 'نعناع فريش',
  '2x': '2x إسبريسو',
};

/// More extras, spread over the alphabet: a menu long enough to scroll.
const _more = <(String, String, int)>[
  ('more-0', 'Almond Flakes', 1000),
  ('more-1', 'Almond Milk Foam', 1100),
  ('more-2', 'Banana Slices', 1200),
  ('more-3', 'Blueberry Syrup', 1300),
  ('more-4', 'Dark Chocolate Chips', 1400),
  ('more-5', 'Dulce de Leche', 1500),
  ('more-6', 'Gingerbread Syrup', 1600),
  ('more-7', 'Golden Syrup', 1700),
  ('more-8', 'Jelly Cubes', 1800),
  ('more-9', 'Kinder Sauce', 1900),
  ('more-10', 'Kiwi Slices', 2000),
  ('more-11', 'Maple Syrup', 2100),
  ('more-12', 'Marshmallows', 2200),
  ('more-13', 'Nutella', 2300),
  ('more-14', 'Nuts Mix', 2400),
  ('more-15', 'Quince Jam', 2500),
  ('more-16', 'Raspberry Syrup', 2600),
  ('more-17', 'Rose Water', 2700),
  ('more-18', 'Toffee Syrup', 2800),
  ('more-19', 'Turmeric', 2900),
  ('more-20', 'Ube Syrup', 3000),
  ('more-21', 'Yogurt Topping', 3100),
  ('more-22', 'Yuzu Syrup', 3200),
  ('more-23', 'Zesty Lemon Peel', 3300),
];

String _name(String id, bool ar) => id.startsWith('more-')
    ? _more.firstWhere((e) => e.$1 == id).$2
    : ar
    ? _extrasAr[id]!
    : _extrasEn.firstWhere((e) => e.$1 == id).$2;

List<ItemAddonView> _addons(bool ar, {bool long = false}) => [
  const ItemAddonView(
    addonItemId: 'full',
    name: 'Full fat',
    addonType: 'milk_type',
    chargedPriceMinor: 0,
  ),
  const ItemAddonView(
    addonItemId: 'oat',
    name: 'Oat',
    addonType: 'milk_type',
    chargedPriceMinor: 4000,
  ),
  for (final (id, _, price) in [..._extrasEn, if (long) ..._more])
    ItemAddonView(
      addonItemId: id,
      name: _name(id, ar),
      addonType: 'extra',
      chargedPriceMinor: price,
    ),
];

List<ModifierGroupView> _groups(bool ar, {int? max, bool long = false}) => [
  const ModifierGroupView(
    groupId: 'g-milk',
    name: 'Milk',
    kind: ModifierGroupKind.addon,
    addonType: 'milk_type',
    isRequired: true,
    minSelections: 1,
    maxSelections: 1,
    options: [
      ModifierOptionView(id: 'full', name: 'Full fat', chargedPriceMinor: 0),
      ModifierOptionView(id: 'oat', name: 'Oat', chargedPriceMinor: 4000),
    ],
  ),
  ModifierGroupView(
    groupId: 'g-extra',
    name: ar ? 'الإضافات' : 'Extras',
    kind: ModifierGroupKind.addon,
    addonType: 'extra',
    isRequired: false,
    minSelections: 0,
    maxSelections: max,
    options: [
      for (final (id, _, price) in [..._extrasEn, if (long) ..._more])
        ModifierOptionView(
          id: id,
          name: _name(id, ar),
          chargedPriceMinor: price,
        ),
    ],
  ),
];

MenuItemView _latte() => const MenuItemView(
  kind: 'item',
  id: 'latte',
  name: 'Spanish Latte',
  basePriceMinor: 12500,
  isActive: true,
  defaultMilkAddonId: 'full',
  allowedAddonIds: [],
  sizes: [],
  addonSlots: [],
  optionalFields: [],
  recipes: [],
  recipeSteps: [],
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
          unitTotalMinor: 12500,
          extrasMinor: 0,
          lineTotalMinor: 12500 * qty,
          qty: qty,
          baseMinor: 12500,
          sizeDeltaMinor: 0,
          paid: const [],
          summary: const [],
        ),
      );
    }
    if (n == #validateItemSelections) {
      return Future<List<GroupViolationView>>.value(const []);
    }
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

const Size _ipad = Size(1180, 820);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The item's choices opened as Fast mode opens them (in a panel beside a
/// cart stub), or as the standard sheet when [fast] is false.
Future<ProviderContainer> _open(
  WidgetTester tester, {
  bool ar = false,
  bool dark = false,
  bool fast = true,
  int? max,
  bool long = false,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = _ipad;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [bridgeProvider.overrideWithValue(_Fake(rtl: ar))],
  );
  addTearDown(container.dispose);
  final nav = GlobalKey<NavigatorState>();
  Widget sheet(BuildContext _) => ItemDetailSheet(
    item: _latte(),
    addons: _addons(ar, long: long),
    groups: _groups(ar, max: max, long: long),
  );
  Widget opener(BuildContext context) => Center(
    child: TextButton(
      onPressed: () =>
          showMadarSheet<void>(context, size: SheetSize.hug, builder: sheet),
      child: const Text('open'),
    ),
  );
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
          home: Scaffold(
            body: fast
                ? MadarPanelHost(
                    navigatorKey: nav,
                    child: Row(
                      children: [
                        SizedBox(width: 390, child: Builder(builder: opener)),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: Navigator(
                            key: nav,
                            pages: const [
                              MaterialPage<void>(
                                child: Center(child: Text('menu')),
                              ),
                            ],
                            onDidRemovePage: (_) {},
                          ),
                        ),
                      ],
                    ),
                  )
                : Builder(builder: opener),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester);
  return container;
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

Map<String, int> _chosen(ProviderContainer c, WidgetTester tester) {
  // The page and the row read and write the sheet's own selection.
  final page = find.byType(ExtrasPage);
  final args = page.evaluate().isNotEmpty
      ? tester.widget<ExtrasPage>(page).args
      : tester.widget<ExtrasStepRow>(find.byType(ExtrasStepRow)).args;
  return c.read(itemConfigProvider(args)).multi['g-extra'] ?? const {};
}

/// Scroll the page to the extra [id], then tap it (or its minus).
Future<void> _tapExtra(
  WidgetTester tester,
  String id, {
  bool less = false,
}) async {
  final f = find.byKey(ValueKey(less ? 'extra-less-$id' : 'extra-$id'));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester);
}

void main() {
  setUpAll(_loadFonts);

  group('the index', () {
    test('Latin names file under their capital, anything else under #', () {
      expect(extrasIndexLetter('vanilla syrup'), 'V');
      expect(extrasIndexLetter('  Oreo'), 'O');
      expect(extrasIndexLetter('2x Espresso'), '#');
      expect(extrasIndexLetter(''), '#');
    });

    test('Arabic alef forms file under ا, like a dictionary', () {
      expect(extrasIndexLetter('أوريو'), 'ا');
      expect(extrasIndexLetter('إضافة'), 'ا');
      expect(extrasIndexLetter('آيس'), 'ا');
      expect(extrasIndexLetter('عسل'), 'ع');
    });

    test('sections run A–Z, # first, names sorted inside each', () {
      final sections = extrasSections(_addons(false).sublist(2));
      expect(sections.map((s) => s.$1).toList(), [
        '#',
        'B',
        'C',
        'E',
        'F',
        'H',
        'I',
        'L',
        'O',
        'P',
        'S',
        'V',
        'W',
      ]);
      final c = sections.firstWhere((s) => s.$1 == 'C').$2.map((a) => a.name);
      expect(c, [
        'Caramel Syrup',
        'Caramel Syrup (Sugar Free)',
        'Chocolate Sauce',
        'Cinnamon',
        'Condensed Milk',
      ]);
    });

    test('Arabic sections follow the Arabic alphabet', () {
      final letters = extrasSections(
        _addons(true).sublist(2),
      ).map((s) => s.$1).toList();
      expect(letters.first, '#');
      // ا before ب before ح before س before ش before ص before ع before ق before ك before ن
      final arabic = letters.skip(1).toList();
      final sorted = [...arabic]..sort();
      expect(arabic, sorted);
      expect(arabic, contains('ا'));
    });
  });

  group('Fast mode', () {
    testWidgets('Extras is a step row; the milk stays a card', (tester) async {
      await _open(tester);
      expect(find.byType(ExtrasStepRow), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is ItemSheetGroupCard && w.group.id == 'g-extra',
        ),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is ItemSheetGroupCard && w.group.id == 'g-milk',
        ),
        findsOneWidget,
      );
      await _capture(tester, 'extras-row-en-light');
    });

    testWidgets(
      'the row opens every extra on a page stacked in the panel, A–Z',
      (tester) async {
        await _open(tester);
        await tester.tap(find.byType(ExtrasStepRow));
        await _settle(tester);
        final page = find.byType(ExtrasPage);
        expect(page, findsOneWidget);
        expect(
          ModalRoute.of(tester.element(page)),
          isA<MadarPanelRoute<void>>(),
        );
        // Every extra is a cell; the letters head their runs.
        for (final (id, _, _) in _extrasEn) {
          expect(find.byKey(ValueKey('extra-$id')), findsOneWidget);
        }
        expect(find.byKey(const ValueKey('extras-index')), findsOneWidget);
        // Caramel comes before Vanilla on the page.
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('extra-caramel'))).dy,
          lessThan(
            tester.getTopLeft(find.byKey(const ValueKey('extra-vanilla'))).dy,
          ),
        );
        await _capture(tester, 'extras-page-en-light');
      },
    );

    testWidgets('a tap adds, another adds one more, the minus takes one off', (
      tester,
    ) async {
      final c = await _open(tester);
      await tester.tap(find.byType(ExtrasStepRow));
      await _settle(tester);
      await _tapExtra(tester, 'honey');
      expect(_chosen(c, tester), {'honey': 1});
      expect(find.byKey(const ValueKey('extra-qty-honey')), findsOneWidget);
      await _tapExtra(tester, 'honey');
      expect(_chosen(c, tester), {'honey': 2});
      await _tapExtra(tester, 'honey', less: true);
      expect(_chosen(c, tester), {'honey': 1});
      await _tapExtra(tester, 'honey', less: true);
      expect(_chosen(c, tester), isEmpty);
      expect(find.byKey(const ValueKey('extra-qty-honey')), findsNothing);
    });

    testWidgets("the group's maximum still holds", (tester) async {
      final c = await _open(tester, max: 2);
      await tester.tap(find.byType(ExtrasStepRow));
      await _settle(tester);
      for (final id in ['honey', 'boba', 'cinnamon']) {
        await _tapExtra(tester, id);
      }
      expect(_chosen(c, tester).keys, unorderedEquals(['honey', 'boba']));
    });

    testWidgets('the rail jumps to a letter', (tester) async {
      await _open(tester, long: true);
      await tester.tap(find.byType(ExtrasStepRow));
      await _settle(tester);
      final scroll = find.byKey(const ValueKey('extras-scroll'));
      final view = tester.getRect(scroll);
      final pistachio = find.byKey(const ValueKey('extra-pistachio'));
      expect(tester.getTopLeft(pistachio).dy, greaterThan(view.bottom));
      await tester.tap(find.byKey(const ValueKey('extras-index-P')));
      await _settle(tester);
      // P's run is now in view (as near the top as the list can scroll).
      final cell = tester.getRect(pistachio);
      expect(cell.top, greaterThanOrEqualTo(view.top));
      expect(cell.bottom, lessThanOrEqualTo(view.bottom));
      // And a letter early in the alphabet jumps back up.
      final boba = find.byKey(const ValueKey('extra-boba'));
      expect(tester.getTopLeft(boba).dy, lessThan(view.top));
      await tester.tap(find.byKey(const ValueKey('extras-index-B')));
      await _settle(tester);
      expect(tester.getRect(boba).top, greaterThanOrEqualTo(view.top));
      expect(tester.getRect(boba).top, lessThan(view.top + 160));
      await _capture(tester, 'extras-page-jumped-en-light');
    });

    testWidgets('Done returns to the item, whose row names what was chosen', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(find.byType(ExtrasStepRow));
      await _settle(tester);
      await _tapExtra(tester, 'vanilla');
      await _tapExtra(tester, 'shot');
      await _capture(tester, 'extras-page-chosen-en-light');
      await tester.tap(find.byKey(const ValueKey('extras-done')));
      await _settle(tester);
      expect(find.byType(ExtrasPage), findsNothing);
      expect(find.byType(ItemDetailSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ExtrasStepRow),
          matching: find.text('Extra Shot, Vanilla Syrup'),
        ),
        findsOneWidget,
      );
      await _capture(tester, 'extras-row-chosen-en-light');
    });

    testWidgets('Arabic: the rail sits on the end edge (the left)', (
      tester,
    ) async {
      await _open(tester, ar: true);
      await tester.tap(find.byType(ExtrasStepRow));
      await _settle(tester);
      final rail = tester.getRect(find.byKey(const ValueKey('extras-index')));
      final page = tester.getRect(find.byType(ExtrasPage));
      expect(rail.left - page.left, lessThan(page.right - rail.right));
      expect(find.byKey(const ValueKey('extras-index-ا')), findsOneWidget);
      await _capture(tester, 'extras-page-ar-light');
    });

    for (final ar in [false, true]) {
      testWidgets('dark, ${ar ? 'ar' : 'en'}', (tester) async {
        await _open(tester, ar: ar, dark: true);
        await tester.tap(find.byType(ExtrasStepRow));
        await _settle(tester);
        await _tapExtra(tester, 'honey');
        await _capture(tester, 'extras-page-${ar ? 'ar' : 'en'}-dark');
      });
    }
  });

  testWidgets('the standard sheet keeps the Extras card', (tester) async {
    await _open(tester, fast: false);
    expect(find.byType(ExtrasStepRow), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is ItemSheetGroupCard && w.group.id == 'g-extra',
      ),
      findsOneWidget,
    );
  });
}
