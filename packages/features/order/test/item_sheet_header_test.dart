// The item sheet's header area: the "Last: Large · Oat milk" chip (the item as
// this device last sold it, one tap to apply), long-press on Add (add and
// keep the sheet open on the same picks), and the slim "Make it a meal"
// banner with the core's saving for the item as configured. EN and AR, phone
// and iPad.
import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const Size _phone = Size(390, 844);
const Size _ipad = Size(1194, 834);

const _session = SessionSnapshot(
  userId: 'u1',
  displayName: 'Sara',
  role: 'teller',
  currencyCode: 'EGP',
  taxRate: 0,
  taxInclusive: true,
  serviceChargeRate: 0,
  serviceChargeTaxable: false,
  requireTableForOrders: false,
  online: true,
  permissionsLoaded: true,
);

const _oat = AddonSelection(addonItemId: 'oat', qty: 1);

MenuItemView _latte() => const MenuItemView(
  kind: 'item',
  id: 'latte',
  name: 'Latte',
  basePriceMinor: 5000,
  isActive: true,
  allowedAddonIds: [],
  sizes: [
    ItemSizeView(id: 'r', label: 'Regular', priceMinor: 5000, isActive: true),
    ItemSizeView(id: 'l', label: 'Large', priceMinor: 6000, isActive: true),
  ],
  addonSlots: [],
  optionalFields: [],
  recipes: [],
  recipeSteps: [],
);

const _addons = [
  ItemAddonView(
    addonItemId: 'oat',
    name: 'Oat milk',
    addonType: 'milk_type',
    chargedPriceMinor: 1500,
  ),
];

class _Fake implements MadarBridge {
  _Fake({this.arabic = false});

  final bool arabic;

  /// The core's "Last: …" answer (null = never sold here).
  LastItemConfig? last;

  MealOffer? meal = const MealOffer(
    comboId: 'lunch',
    slotId: 's-drink',
    name: 'Lunch deal',
    deltaMinor: 10000,
    savingMinor: 6000,
    slotHint: 'with Main + Side',
  );

  /// Every selection the banner asked the core to quote, as (size, addons).
  final List<(String?, List<AddonSelection>)> mealAsks = [];

  /// Every line added, as (size, addons, qty).
  final List<(String?, List<AddonSelection>, int)> added = [];
  final List<String> mealDrafts = [];

  /// Lines replaced (edit mode), by key.
  final List<String> replaced = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => _session.role);
    if (can != null) return can;
    final name = invocation.memberName;
    final a = invocation.namedArguments;
    if (name == #tr) return coreWord(a[#key] as String, arabic: arabic);
    if (name == #trChecked) {
      return coreWord(invocation.positionalArguments.first as String);
    }
    if (name == #isRtl) return arabic;
    if (name == #locale) return arabic ? 'ar' : 'en';
    if (name == #currentSession) return _session;
    if (name == #appRoute) return const AppRoute.order();
    if (name == #deviceConfig) {
      return const DeviceConfigView(reconfiguring: false, configured: true);
    }
    if (name == #lastItemConfig) return last;
    if (name == #mealOffer) return meal;
    if (name == #mealOfferFor) {
      mealAsks.add((
        a[#sizeLabel] as String?,
        List.of(a[#addons] as List<AddonSelection>),
      ));
      return meal;
    }
    if (name == #itemMealDraft) {
      mealDrafts.add(a[#sizeLabel] as String? ?? '');
      return Future<ComboDraft>.value(
        const ComboDraft(comboId: 'lunch', qty: 1, picks: []),
      );
    }
    if (name == #cartAddConfigured) {
      added.add((
        a[#sizeLabel] as String?,
        List.of(a[#addons] as List<AddonSelection>),
        a[#qty] as int,
      ));
      return Future<List<CartLineView>>.value(const []);
    }
    if (name == #cartReplaceConfigured) {
      replaced.add(a[#lineKey] as String);
      return Future<List<CartLineView>>.value(const []);
    }
    if (name == #cartLines) {
      return Future<List<CartLineView>>.value(const []);
    }
    if (name == #cartTotals) {
      return Future<CartTotals>.value(
        const CartTotals(
          itemCount: 0,
          subtotalMinor: 0,
          discountMinor: 0,
          taxMinor: 0,
          serviceChargeMinor: 0,
          totalMinor: 0,
        ),
      );
    }
    if (name == #cartMeta) {
      return Future<CartMeta>.value(const CartMeta(name: ''));
    }
    if (name == #takeStaffDrinkNotices) return const <String>[];
    if (name == #takeDealNotices) return Future<List<String>>.value(const []);
    if (name == #cartDealSuggestions) return const <DealSuggestion>[];
    if (name == #cartAppliedDeals) return const <AppliedDealView>[];
    if (name == #previewConfiguredLine) {
      return Future<LinePreviewView>.value(
        const LinePreviewView(
          unitTotalMinor: 5000,
          extrasMinor: 0,
          lineTotalMinor: 5000,
        ),
      );
    }
    if (name == #validateItemSelections) {
      return Future<List<GroupViolationView>>.value(const []);
    }
    return null;
  }
}

/// A host with one button that opens the latte's sheet; returns the
/// container and a holder for what the sheet popped with.
Future<(ProviderContainer, List<Object?>)> _mount(
  WidgetTester tester,
  _Fake fake, {
  required Size size,
  CartLineView? editLine,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final container = ProviderContainer(
    overrides: [bridgeProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  final popped = <Object?>[];
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: MadarTheme.light(),
        locale: Locale(fake.arabic ? 'ar' : 'en'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Directionality(
          textDirection: fake.arabic ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  key: const ValueKey('open'),
                  onPressed: () async {
                    popped.add(
                      await showMadarSheet<Object?>(
                        context,
                        size: SheetSize.hug,
                        builder: (_) => ItemDetailSheet(
                          item: _latte(),
                          addons: _addons,
                          editLine: editLine,
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
  return (container, popped);
}

String _money(int minor, {bool arabic = false}) =>
    Money.format(minor, currency: 'EGP', locale: arabic ? 'ar' : 'en');

Finder get _add => find.text(coreWord('order.add_to_cart'));

Finder _addIn(bool arabic) =>
    find.text(coreWord('order.add_to_cart', arabic: arabic));

void main() {
  for (final arabic in [false, true]) {
    final lang = arabic ? 'ar' : 'en';
    for (final (device, size) in [('phone', _phone), ('iPad', _ipad)]) {
      testWidgets(
        'the Last chip applies the config sold here ($device, $lang)',
        (tester) async {
          final text = coreWord(
            'order.last_config',
            arabic: arabic,
          ).replaceAll('{config}', 'Large · Oat milk');
          final fake = _Fake(arabic: arabic)
            ..last = LastItemConfig(
              sizeLabel: 'Large',
              addons: const [_oat],
              optionalFieldIds: const [],
              words: 'Large · Oat milk',
              text: text,
            );
          await _mount(tester, fake, size: size);
          final chip = find.byKey(const ValueKey('item-last-config'));
          expect(chip, findsOneWidget);
          expect(find.text(text), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.tap(chip);
          await tester.pumpAndSettle();
          // The banner re-quotes the applied config.
          expect(fake.mealAsks.last.$1, 'Large');
          expect(fake.mealAsks.last.$2, [_oat]);
          await tester.tap(_addIn(arabic));
          await tester.pumpAndSettle();
          final line = fake.added.single;
          expect((line.$1, line.$3), ('Large', 1));
          expect(line.$2, [_oat]);
          expect(find.byType(ItemDetailSheet), findsNothing);
        },
      );

      testWidgets('the meal banner: hint, +X and the saving ($device, $lang)', (
        tester,
      ) async {
        final fake = _Fake(arabic: arabic);
        final (_, popped) = await _mount(tester, fake, size: size);
        final banner = find.byKey(const ValueKey('make-it-a-meal'));
        expect(banner, findsOneWidget);
        expect(
          find.descendant(
            of: banner,
            matching: find.text(coreWord('meal.make_it', arabic: arabic)),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: banner, matching: find.text('with Main + Side')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: banner,
            matching: find.text('+${_money(10000, arabic: arabic)}'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: banner,
            matching: find.text(
              coreWord(
                'meal.save',
                arabic: arabic,
              ).replaceAll('{amount}', _money(6000, arabic: arabic)),
            ),
          ),
          findsOneWidget,
        );
        // The old big button is gone.
        expect(
          find.textContaining(
            coreWord(
              'meal.make_it_plus',
              arabic: arabic,
            ).replaceAll('{amount}', ''),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);

        // It quotes the sheet's current config, and follows a change.
        expect(fake.mealAsks.last.$1, 'Regular');
        await tester.tap(find.text('Large'));
        await tester.pumpAndSettle();
        expect(fake.mealAsks.last.$1, 'Large');

        // A tap does what the button did: the draft goes back to the screen.
        await tester.tap(banner);
        await tester.pumpAndSettle();
        expect(fake.mealDrafts, ['Large']);
        expect(popped.single, isA<ComboDraft>());
      });
    }

    testWidgets(
      'long-press Add adds and keeps the sheet on the picks ($lang)',
      (tester) async {
        final fake = _Fake(arabic: arabic);
        final (container, _) = await _mount(tester, fake, size: _ipad);
        await tester.tap(find.text('Large'));
        await tester.pumpAndSettle();

        await tester.longPress(_addIn(arabic));
        await tester.pumpAndSettle();
        expect(fake.added, hasLength(1));
        expect((fake.added.single.$1, fake.added.single.$3), ('Large', 1));
        expect(find.byType(ItemDetailSheet), findsOneWidget, reason: 'stays');
        expect(
          container.read(appToastProvider)?.text,
          coreWord('order.added_add_another', arabic: arabic),
        );

        // Again, the same picks; then a plain tap adds and closes.
        await tester.longPress(_addIn(arabic));
        await tester.pumpAndSettle();
        expect(fake.added, hasLength(2));
        expect(fake.added.last.$1, 'Large');
        expect(fake.added.last.$2, isEmpty);
        await tester.tap(_addIn(arabic));
        await tester.pumpAndSettle();
        expect(fake.added, hasLength(3));
        expect(find.byType(ItemDetailSheet), findsNothing);
      },
    );
  }

  testWidgets('no sale here, no meal: neither the chip nor the banner', (
    tester,
  ) async {
    final fake = _Fake()..meal = null;
    await _mount(tester, fake, size: _ipad);
    expect(find.byKey(const ValueKey('item-last-config')), findsNothing);
    expect(find.byKey(const ValueKey('make-it-a-meal')), findsNothing);
    expect(_add, findsOneWidget);
  });

  testWidgets('no saving: the banner shows no "save"', (tester) async {
    final fake = _Fake()
      ..meal = const MealOffer(
        comboId: 'lunch',
        slotId: 's-drink',
        name: 'Lunch deal',
        deltaMinor: 2000,
        savingMinor: 0,
        slotHint: '',
      );
    await _mount(tester, fake, size: _ipad);
    expect(find.byKey(const ValueKey('make-it-a-meal')), findsOneWidget);
    expect(find.text('+${_money(2000)}'), findsOneWidget);
    expect(
      find.textContaining(coreWord('meal.save').split(' ').first),
      findsNothing,
    );
  });

  testWidgets('editing a line: no Last chip; a long press only updates', (
    tester,
  ) async {
    final fake = _Fake()
      ..last = const LastItemConfig(
        sizeLabel: 'Large',
        addons: [_oat],
        optionalFieldIds: [],
        words: 'Large · Oat milk',
        text: 'Last: Large · Oat milk',
      );
    await _mount(
      tester,
      fake,
      size: _ipad,
      editLine: const CartLineView(
        key: 'k1',
        itemId: 'latte',
        name: 'Latte',
        sizeLabel: 'Regular',
        addons: [],
        optionals: [],
        unitPriceMinor: 5000,
        qty: 1,
        lineTotalMinor: 5000,
        kind: 'item',
        parts: [],
        dealCutMinor: 0,
      ),
    );
    expect(find.byKey(const ValueKey('item-last-config')), findsNothing);
    await tester.longPress(find.text(coreWord('order.update_item')));
    await tester.pumpAndSettle();
    expect(fake.added, isEmpty, reason: 'never a second line');
    expect(fake.replaced, ['k1']);
  });
}
