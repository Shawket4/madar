// The item sheet's footer: a live summary line in the core's words (the words
// the cart line and the receipt print) and, behind the total, the core's price
// breakdown. The sheet computes neither: the fake core below answers both, and
// the tests pin that the sheet shows them verbatim, in EN and AR.
//
// - a chip scrolls the sheet to its group;
// - ✕ takes an OPTIONAL choice off (an extra, an optional field), never a
//   required one (the milk) and never the size;
// - tapping the total opens base + size + each paid option = each, × qty.

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

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
    addonItemId: 'shot',
    name: 'Extra shot',
    addonType: 'extra',
    chargedPriceMinor: 800,
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
    options: [_opt('full', 'Full fat', 0), _opt('oat', 'Oat', 500)],
  ),
  ModifierGroupView(
    groupId: 'g-extra',
    name: 'Extras',
    kind: ModifierGroupKind.addon,
    addonType: 'extra',
    isRequired: false,
    minSelections: 0,
    maxSelections: 3,
    options: [_opt('shot', 'Extra shot', 800)],
  ),
];

MenuItemView _latte() => const MenuItemView(
  kind: 'item',
  id: 'latte',
  name: 'Latte',
  basePriceMinor: 4500,
  isActive: true,
  defaultMilkAddonId: 'full',
  allowedAddonIds: [],
  sizes: [
    ItemSizeView(id: 's', label: 'Small', priceMinor: 4500, isActive: true),
    ItemSizeView(id: 'l', label: 'Large', priceMinor: 5500, isActive: true),
  ],
  addonSlots: [],
  optionalFields: [
    OptionalFieldView(
      id: 'ice',
      name: 'Less ice',
      priceMinor: 0,
      isActive: true,
    ),
  ],
  recipes: [],
  recipeSteps: [],
);

/// A stand-in core. Its words and figures are CANNED from the request — the
/// sheet must show them verbatim. The `×2` and the odd figures are there so a
/// sheet that re-derived either would be caught.
class _Fake implements MadarBridge {
  _Fake({required this.rtl});

  final bool rtl;

  /// Every preview asked for: the addon ids it carried.
  final previews = <List<String>>[];

  static const _names = {
    'full': 'Full fat',
    'oat': 'Oat',
    'shot': 'Extra shot',
  };

  LinePreviewView _preview(Map<Symbol, dynamic> a) {
    final addons = (a[#addons] as List<AddonSelection>)
        .map((s) => s.addonItemId)
        .toList();
    final optionals = a[#optionalFieldIds] as List<String>;
    final size = a[#sizeLabel] as String?;
    final qty = a[#qty] as int;
    previews.add(addons);
    return LinePreviewView(
      unitTotalMinor: 7123,
      extrasMinor: 1623,
      lineTotalMinor: 7123 * qty,
      qty: qty,
      baseMinor: 4500,
      sizeLabel: size,
      sizeDeltaMinor: 1000,
      paid: [
        for (final id in addons)
          if (id == 'shot')
            const LinePriceRowView(text: 'Extra shot ×2', amountMinor: 1623),
      ],
      summary: [
        if (size != null)
          LineSummaryPartView(kind: 'size', refId: size, text: size),
        for (final id in addons)
          LineSummaryPartView(
            kind: 'addon',
            refId: id,
            text: id == 'shot' ? 'Extra shot ×2' : _names[id]!,
          ),
        for (final id in optionals)
          LineSummaryPartView(kind: 'optional', refId: id, text: 'Less ice'),
      ],
    );
  }

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
    if (n == #previewConfiguredLine) return Future.value(_preview(a));
    if (n == #ownOpenTill) return null;
    if (n == #currentTill || n == #refreshTill) {
      return Future<TillView?>.value();
    }
    return null;
  }
}

Future<_Fake> _open(
  WidgetTester tester, {
  required bool ar,
  Size size = const Size(1194, 834),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final fake = _Fake(rtl: ar);
  final container = ProviderContainer(
    overrides: [bridgeProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: MadarTheme.light(),
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
                  builder: (_) => ItemDetailSheet(
                    item: _latte(),
                    addons: _addons,
                    groups: _groups,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester);
  return fake;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Extras is optional, so its card opens folded: unfold it, pick the shot.
Future<void> _pickShot(WidgetTester tester) async {
  await tester.tap(find.text('EXTRAS').first);
  await _settle(tester);
  await _tapOption(tester, 'Extra shot');
}

/// Tap an option in the sheet's body, scrolling it into view first.
Future<void> _tapOption(WidgetTester tester, String name) async {
  await tester.ensureVisible(find.text(name).first);
  await _settle(tester);
  await tester.tap(find.text(name).first);
  await _settle(tester);
}

Finder _summary() => find.byKey(const ValueKey('item-summary'));

Finder _inSummary(String text) =>
    find.descendant(of: _summary(), matching: find.text(text));

String _money(int minor, {required bool ar, bool signed = false}) =>
    Money.format(
      minor,
      currency: 'EGP',
      locale: ar ? 'ar' : 'en',
      signed: signed,
    );

void main() {
  for (final ar in [false, true]) {
    final lang = ar ? 'AR' : 'EN';

    testWidgets('$lang: the summary shows the core words, in order', (
      tester,
    ) async {
      await _open(tester, ar: ar);
      // Opened on the defaults: the size and the recipe's milk.
      expect(_inSummary('Small'), findsOneWidget);
      expect(_inSummary('Full fat'), findsOneWidget);

      await _tapOption(tester, 'Oat');
      await _pickShot(tester);
      await _tapOption(tester, 'Less ice');
      await _settle(tester);

      final words = tester
          .widgetList<Text>(
            find.descendant(of: _summary(), matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .toList();
      // Verbatim: the core's `×2`, not the sheet's own count.
      expect(words, ['Small', 'Oat', 'Extra shot ×2', 'Less ice']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$lang: ✕ takes an optional choice off, never a required one', (
      tester,
    ) async {
      final fake = await _open(tester, ar: ar);
      await _pickShot(tester);
      await _tapOption(tester, 'Less ice');
      await _settle(tester);

      // The size and the milk (a required group) have no ✕.
      expect(
        find.byKey(const ValueKey('item-summary-remove-Small')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('item-summary-remove-full')),
        findsNothing,
      );
      final remove = find.byKey(const ValueKey('item-summary-remove-shot'));
      expect(remove, findsOneWidget);
      expect(
        tester.getSemantics(remove).label,
        coreWord(
          'order.summary_remove',
          arabic: ar,
        ).replaceAll('{name}', 'Extra shot ×2'),
      );

      await tester.tap(remove);
      await _settle(tester);
      expect(fake.previews.last, ['full']);
      expect(_inSummary('Extra shot ×2'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('item-summary-remove-ice')));
      await _settle(tester);
      expect(_inSummary('Less ice'), findsNothing);
      expect(_inSummary('Full fat'), findsOneWidget);
    });

    testWidgets('$lang: a chip scrolls the sheet to its group', (tester) async {
      // A phone: the options overflow, so the body scrolls.
      await _open(tester, ar: ar, size: const Size(390, 640));
      final body = find
          .descendant(
            of: find.byType(ItemDetailSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      double offset() => tester.state<ScrollableState>(body).position.pixels;

      await _tapOption(tester, 'Less ice');
      final low = offset();
      expect(low, greaterThan(0), reason: 'the optional fields are low down');

      await tester.tap(find.byKey(const ValueKey('item-summary-size-Small')));
      await _settle(tester);
      final up = offset();
      expect(up, lessThan(low), reason: 'back up to the sizes');

      await tester.tap(find.byKey(const ValueKey('item-summary-optional-ice')));
      await _settle(tester);
      expect(offset(), greaterThan(up), reason: 'down to the optional fields');
      expect(tester.takeException(), isNull);
    });

    testWidgets('$lang: the total opens the core breakdown', (tester) async {
      await _open(tester, ar: ar);
      await _pickShot(tester);
      await _settle(tester);
      // Two of the line: the popover multiplies nothing itself.
      await tester.tap(find.byType(StepButton).last);
      await _settle(tester);

      final popover = find.byKey(const ValueKey('item-price-breakdown'));
      expect(popover, findsNothing);
      await tester.tap(find.byKey(const ValueKey('item-total')));
      await _settle(tester);
      expect(popover, findsOneWidget);

      Finder inPop(String s) =>
          find.descendant(of: popover, matching: find.text(s));
      expect(inPop(coreWord('order.price_base', arabic: ar)), findsOneWidget);
      expect(inPop(_money(4500, ar: ar)), findsOneWidget);
      expect(inPop('Small'), findsOneWidget);
      expect(inPop(_money(1000, ar: ar, signed: true)), findsOneWidget);
      expect(inPop('Extra shot ×2'), findsOneWidget);
      expect(inPop(_money(1623, ar: ar, signed: true)), findsOneWidget);
      expect(inPop(coreWord('order.price_each', arabic: ar)), findsOneWidget);
      expect(inPop(_money(7123, ar: ar)), findsOneWidget);
      expect(
        inPop(
          coreWord('order.price_times', arabic: ar).replaceAll('{count}', '2'),
        ),
        findsOneWidget,
      );
      expect(inPop(_money(14246, ar: ar)), findsOneWidget);
      expect(tester.takeException(), isNull);

      // A tap anywhere else puts it away.
      await tester.tap(find.text('Latte').first);
      await _settle(tester);
      expect(popover, findsNothing);
    });
  }
}
