// Combos on the till (COMBOS_CONTRACT §6): the combo sheet and its slot
// picker, "Make it a meal +X" on the item sheet, the combo line and the deal
// suggestion banner in the cart. In English and Arabic, at phone and tablet
// sizes, with no layout overflow. Every figure is the fake core's; the widgets
// only show them and hand the teller's picks back.

import 'dart:io';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/feature_order.dart';
import 'package:feature_order/src/combo_sheet.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:feature_order/src/sell_cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const Size _phone = Size(390, 844);
const Size _tablet = Size(1194, 834);

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

// ── the worked example: Burger 12000, Fries 4000, Latte (Regular 5000
// included, Large 6000 = +10.00), P = 150.00 ───────────────────────────────

ComboChoiceDetail _choice(
  String id,
  String name,
  int base, {
  List<ComboSizeOption> sizes = const [],
  String? included,
  int surcharge = 0,
  bool isDefault = false,
  bool customisable = false,
}) => ComboChoiceDetail(
  itemId: id,
  name: name,
  basePriceMinor: base,
  includedSizeLabel: included,
  surchargeMinor: surcharge,
  sizes: sizes,
  isDefault: isDefault,
  customisable: customisable,
);

ComboDetail _detail({required bool arabic, bool available = true}) {
  String rule(int n) => coreWord(
    n == 1 ? 'combo.pick_n_one' : 'combo.pick_n',
    arabic: arabic,
  ).replaceAll('{count}', '$n');
  return ComboDetail(
    id: 'lunch',
    name: arabic ? 'وجبة الغداء' : 'Lunch deal',
    priceMinor: 15000,
    isFixed: false,
    availableNow: available,
    whyUnavailable: available
        ? null
        : coreWord('combo.unavailable', arabic: arabic),
    slots: [
      ComboSlotDetail(
        id: 's-main',
        name: arabic ? 'الطبق الرئيسي' : 'Main',
        min: 1,
        max: 1,
        ruleLabel: rule(1),
        defaultItemId: 'burger',
        choices: [
          _choice('burger', arabic ? 'برجر' : 'Burger', 12000, isDefault: true),
          _choice(
            'chicken',
            arabic ? 'دجاج مشوي' : 'Grilled chicken',
            13000,
            surcharge: 1500,
          ),
        ],
      ),
      ComboSlotDetail(
        id: 's-side',
        name: arabic ? 'الطبق الجانبي' : 'Side',
        min: 1,
        max: 1,
        ruleLabel: rule(1),
        defaultItemId: 'fries',
        choices: [
          _choice('fries', arabic ? 'بطاطس' : 'Fries', 4000, isDefault: true),
        ],
      ),
      ComboSlotDetail(
        id: 's-drink',
        name: arabic ? 'المشروب' : 'Drink',
        min: 1,
        max: 1,
        ruleLabel: rule(1),
        defaultItemId: 'latte',
        defaultSizeLabel: 'Regular',
        choices: [
          _choice(
            'latte',
            arabic ? 'لاتيه' : 'Latte',
            5000,
            included: 'Regular',
            isDefault: true,
            customisable: true,
            sizes: const [
              ComboSizeOption(
                label: 'Regular',
                priceMinor: 5000,
                extraMinor: 0,
                isIncluded: true,
              ),
              ComboSizeOption(
                label: 'Large',
                priceMinor: 6000,
                extraMinor: 1000,
                isIncluded: false,
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

ComboPickInput _pick(String slot, String item, {String? size}) =>
    ComboPickInput(
      slotId: slot,
      itemId: item,
      sizeLabel: size,
      qty: 1,
      addons: const [],
      optionalFieldIds: const [],
    );

final List<ComboPickInput> _defaults = [
  _pick('s-main', 'burger'),
  _pick('s-side', 'fries'),
  _pick('s-drink', 'latte'),
];

CartLineView _comboLine({int dealCut = 0}) => CartLineView(
  key: 'combo:lunch',
  itemId: 'lunch',
  name: 'Lunch deal',
  kind: 'combo',
  unitPriceMinor: 15000,
  qty: 1,
  lineTotalMinor: 17500,
  addons: const [],
  optionals: const [],
  dealCutMinor: dealCut,
  parts: const [
    CartPartView(
      slotId: 's-main',
      slotName: 'Main',
      itemId: 'burger',
      itemName: 'Burger',
      qty: 1,
      unitPriceMinor: 12000,
      shareMinor: 8571,
      surchargeMinor: 0,
      addons: [],
      optionals: [],
    ),
    CartPartView(
      slotId: 's-side',
      slotName: 'Side',
      itemId: 'fries',
      itemName: 'Fries',
      qty: 1,
      unitPriceMinor: 4000,
      shareMinor: 2858,
      surchargeMinor: 0,
      addons: [],
      optionals: [],
    ),
    CartPartView(
      slotId: 's-drink',
      slotName: 'Drink',
      itemId: 'latte',
      itemName: 'Latte',
      sizeLabel: 'Large',
      qty: 1,
      unitPriceMinor: 6000,
      shareMinor: 3571,
      surchargeMinor: 1000,
      addons: [
        CartAddonView(
          addonItemId: 'oat',
          name: 'Oat milk',
          qty: 1,
          priceModifierMinor: 1500,
        ),
      ],
      optionals: [],
    ),
  ],
);

CartLineView _croissants({int dealCut = 0, String? dealName}) => CartLineView(
  key: 'k-croissant',
  itemId: 'croissant',
  name: 'Croissant',
  kind: 'item',
  unitPriceMinor: 5500,
  qty: 2,
  lineTotalMinor: 11000,
  addons: const [],
  optionals: const [],
  parts: const [],
  dealCutMinor: dealCut,
  dealName: dealName,
);

MenuItemView _latteItem() => const MenuItemView(
  kind: 'item',
  id: 'latte',
  name: 'Latte',
  categoryId: 'hot',
  basePriceMinor: 5000,
  isActive: true,
  allowedAddonIds: [],
  sizes: [],
  addonSlots: [],
  optionalFields: [],
  recipes: [],
  recipeSteps: [],
);

class _Fake implements MadarBridge {
  _Fake({this.arabic = false});

  final bool arabic;

  /// Every picks list the sheet asked the core to price.
  final List<List<ComboPickInput>> quoted = [];

  /// What the sheet saved (add or replace), as (lineKey, picks, qty).
  final List<(String?, List<ComboPickInput>, int)> saved = [];

  /// The core refuses the next save with this.
  MadarError? refuseSave;

  bool available = true;
  MealOffer? meal = const MealOffer(
    comboId: 'lunch',
    slotId: 's-drink',
    name: 'Lunch deal',
    deltaMinor: 12500,
  );
  final List<String> mealDrafts = [];

  List<CartLineView> lines = [];
  List<DealSuggestion> suggestions = [];
  List<AppliedDealView> applied = [];
  List<String> notices = [];
  final List<String> appliedIds = [];
  final List<String> removedIds = [];

  int _surcharge(List<ComboPickInput> picks) =>
      (picks.any((p) => p.itemId == 'latte' && p.sizeLabel == 'Large')
          ? 1000
          : 0) +
      (picks.any((p) => p.itemId == 'chicken') ? 1500 : 0);

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
    if (name == #formatTime) return '13:05';
    if (name == #isRtl) return arabic;
    if (name == #locale) return arabic ? 'ar' : 'en';
    if (name == #currentSession) return _session;
    if (name == #appRoute) return const AppRoute.order();
    if (name == #deviceConfig) {
      return const DeviceConfigView(reconfiguring: false, configured: true);
    }
    if (name == #comboDetail) {
      return _detail(arabic: arabic, available: available);
    }
    if (name == #comboNewDraft) {
      return ComboDraft(comboId: 'lunch', qty: 1, picks: _defaults);
    }
    if (name == #comboQuote) {
      final picks = List.of(a[#picks] as List<ComboPickInput>);
      final qty = a[#qty] as int;
      quoted.add(picks);
      final complete = {
        's-main',
        's-side',
        's-drink',
      }.every((s) => picks.any((p) => p.slotId == s));
      final unit = 15000 + _surcharge(picks);
      return Future<ComboQuoteView>.value(
        ComboQuoteView(
          priceMinor: 15000,
          unitTotalMinor: unit,
          lineTotalMinor: unit * qty,
          surchargeMinor: _surcharge(picks) * qty,
          extrasMinor: 0,
          listMinor: 21000 * qty,
          savingMinor: (21000 - unit) * qty,
          complete: complete,
          refusal: complete ? null : 'COMBO_SLOT_TOO_FEW',
          refusalText: complete
              ? null
              : coreWord(
                  'combo.slot_too_few',
                  arabic: arabic,
                ).replaceAll('{min}', '1').replaceAll('{slot}', 'Main'),
        ),
      );
    }
    if (name == #cartAddCombo || name == #cartReplaceCombo) {
      final refuse = refuseSave;
      if (refuse != null) return Future<List<CartLineView>>.error(refuse);
      saved.add((
        a[#lineKey] as String?,
        List.of(a[#picks] as List<ComboPickInput>),
        a[#qty] as int,
      ));
      lines = [_comboLine()];
      return Future<List<CartLineView>>.value(lines);
    }
    if (name == #mealOffer) return meal;
    if (name == #itemMealDraft || name == #cartMakeItAMeal) {
      mealDrafts.add(name == #itemMealDraft ? 'item' : 'line');
      return Future<ComboDraft>.value(
        ComboDraft(
          comboId: 'lunch',
          lineKey: name == #cartMakeItAMeal ? a[#lineKey] as String : null,
          qty: 1,
          picks: [
            _pick('s-main', 'burger'),
            _pick('s-side', 'fries'),
            _pick('s-drink', 'latte', size: 'Large'),
          ],
        ),
      );
    }
    if (name == #cartLines) return Future<List<CartLineView>>.value(lines);
    if (name == #cartTotals) {
      return Future<CartTotals>.value(
        const CartTotals(
          itemCount: 1,
          subtotalMinor: 17500,
          discountMinor: 0,
          taxMinor: 0,
          serviceChargeMinor: 0,
          totalMinor: 17500,
        ),
      );
    }
    if (name == #cartMeta) {
      return Future<CartMeta>.value(const CartMeta(name: ''));
    }
    if (name == #cartSetMeta) return Future<void>.value();
    if (name == #takeStaffDrinkNotices) return const <String>[];
    if (name == #cartDealSuggestions) return suggestions;
    if (name == #cartAppliedDeals) return applied;
    if (name == #takeDealNotices) {
      final out = List.of(notices);
      notices = [];
      return Future<List<String>>.value(out);
    }
    if (name == #cartApplyDeal) {
      appliedIds.add(a[#dealId] as String);
      suggestions = [];
      applied = [
        const AppliedDealView(
          id: 'app-1',
          dealId: 'two-bites',
          name: 'Two bites',
          times: 1,
          discountMinor: 2000,
          lineKeys: ['k-croissant'],
        ),
      ];
      lines = [_croissants(dealCut: 2000, dealName: 'Two bites')];
      return Future<List<CartLineView>>.value(lines);
    }
    if (name == #cartRemoveDeal) {
      removedIds.add(a[#applicationId] as String);
      applied = [];
      lines = [_croissants()];
      return Future<List<CartLineView>>.value(lines);
    }
    if (name == #listItemAddons) {
      return Future<List<ItemAddonView>>.value(const [
        ItemAddonView(
          addonItemId: 'oat',
          name: 'Oat milk',
          addonType: 'milk_type',
          chargedPriceMinor: 1500,
        ),
      ]);
    }
    if (name == #listItemModifierGroups) {
      return Future<List<ModifierGroupView>>.value(const []);
    }
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

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Fake fake, {
  required Size size,
  required Widget Function(BuildContext context, WidgetRef ref) body,
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
            body: Consumer(builder: (context, ref, _) => body(context, ref)),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// A host with one button that opens the combo sheet.
Widget _opener(BuildContext context, WidgetRef ref, {ComboDraft? draft}) =>
    Center(
      child: TextButton(
        key: const ValueKey('open'),
        onPressed: () => showComboSheet(
          context,
          ref,
          comboId: 'lunch',
          tableId: null,
          draft: draft,
        ),
        child: const Text('open'),
      ),
    );

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

/// A figure as the till shows it: in the session's currency, in the
/// language's number style.
String _money(int minor, {bool arabic = false}) =>
    Money.format(minor, currency: 'EGP', locale: arabic ? 'ar' : 'en');

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
  setUpAll(_loadFonts);

  for (final arabic in [false, true]) {
    final lang = arabic ? 'ar' : 'en';
    for (final (device, size) in [('phone', _phone), ('tablet', _tablet)]) {
      testWidgets('combo sheet lays out ($device, $lang)', (tester) async {
        final fake = _Fake(arabic: arabic);
        await _mount(tester, fake, size: size, body: _opener);
        await _open(tester);

        expect(find.byType(ComboSheet), findsOneWidget);
        expect(find.text(arabic ? 'وجبة الغداء' : 'Lunch deal'), findsWidgets);
        expect(find.text(arabic ? 'المشروب' : 'DRINK'), findsWidgets);
        // The rule, in the core's counted words.
        expect(
          find.text(
            coreWord(
              'combo.pick_n_one',
              arabic: arabic,
            ).replaceAll('{count}', '1'),
          ),
          findsNWidgets(3),
        );
        // The bigger size says what it adds; the included one adds nothing.
        expect(
          find.text('Large +${_money(1000, arabic: arabic)}'),
          findsOneWidget,
        );
        expect(find.text('Regular'), findsOneWidget);
        // The choice that costs more says so.
        expect(find.text('+${_money(1500, arabic: arabic)}'), findsOneWidget);
        // The core's live figures: the total and the saving.
        expect(find.text(_money(15000, arabic: arabic)), findsWidgets);
        expect(
          find.text(
            coreWord(
              'combo.you_save',
              arabic: arabic,
            ).replaceAll('{amount}', _money(6000, arabic: arabic)),
          ),
          findsOneWidget,
        );
        expect(
          find.text(coreWord('combo.add', arabic: arabic)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('picking a bigger size and another main re-prices and saves', (
    tester,
  ) async {
    final fake = _Fake();
    final c = await _mount(tester, fake, size: _tablet, body: _opener);
    await _open(tester);

    await tester.tap(find.byKey(const ValueKey('size-latte-Large')));
    await tester.pumpAndSettle();
    expect(
      fake.quoted.last.firstWhere((p) => p.itemId == 'latte').sizeLabel,
      'Large',
    );
    await tester.tap(find.byKey(const ValueKey('choice-s-main-chicken')));
    await tester.pumpAndSettle();
    final picks = fake.quoted.last;
    expect(picks.where((p) => p.slotId == 's-main').map((p) => p.itemId), [
      'chicken',
    ], reason: 'a one-pick slot swaps, never adds');
    // 150 + 10 (Large) + 15 (chicken).
    expect(find.text(_money(17500)), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('combo-save')));
    await tester.pumpAndSettle();
    expect(fake.saved, hasLength(1));
    final (lineKey, savedPicks, qty) = fake.saved.single;
    expect(lineKey, isNull);
    expect(qty, 1);
    expect(savedPicks.map((p) => (p.itemId, p.sizeLabel)), [
      ('fries', null),
      ('latte', 'Large'),
      ('chicken', null),
    ]);
    expect(find.byType(ComboSheet), findsNothing, reason: 'saved: it closes');
    expect(c.read(cartProvider(null)).lines.single.kind, 'combo');
  });

  testWidgets(
    'an optional-less slot left empty blocks saving with the reason',
    (tester) async {
      final fake = _Fake();
      await _mount(
        tester,
        fake,
        size: _phone,
        body: (context, ref) => _opener(
          context,
          ref,
          draft: ComboDraft(
            comboId: 'lunch',
            qty: 1,
            picks: [_pick('s-side', 'fries'), _pick('s-drink', 'latte')],
          ),
        ),
      );
      await _open(tester);
      final reason = coreWord(
        'combo.slot_too_few',
      ).replaceAll('{min}', '1').replaceAll('{slot}', 'Main');
      expect(find.text(reason), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('combo-save')));
      await tester.pumpAndSettle();
      expect(fake.saved, isEmpty);
    },
  );

  for (final arabic in [false, true]) {
    testWidgets(
      'a refused save stays open and toasts why (${arabic ? 'ar' : 'en'})',
      (tester) async {
        final fake = _Fake(arabic: arabic)
          // The core refuses in the teller's words, the whole sentence.
          ..refuseSave = MadarError.validation(
            field: '',
            detail: coreWord('combo.picks_required', arabic: arabic),
          );
        final c = await _mount(tester, fake, size: _phone, body: _opener);
        await _open(tester);
        await tester.tap(find.byKey(const ValueKey('combo-save')));
        await tester.pumpAndSettle();
        expect(find.byType(ComboSheet), findsOneWidget);
        expect(
          c.read(appToastProvider)?.text,
          coreWord('combo.picks_required', arabic: arabic),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a combo not on sale now says why and cannot be added', (
    tester,
  ) async {
    final fake = _Fake()..available = false;
    await _mount(tester, fake, size: _phone, body: _opener);
    await _open(tester);
    expect(find.text(coreWord('combo.unavailable')), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('combo-save')));
    await tester.pumpAndSettle();
    expect(fake.saved, isEmpty);
  });

  testWidgets('editing a combo line saves over that line', (tester) async {
    final fake = _Fake();
    await _mount(
      tester,
      fake,
      size: _tablet,
      body: (context, ref) => _opener(
        context,
        ref,
        draft: ComboDraft(
          comboId: 'lunch',
          lineKey: 'combo:lunch',
          qty: 2,
          picks: _defaults,
        ),
      ),
    );
    await _open(tester);
    expect(find.text(coreWord('combo.update')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('combo-save')));
    await tester.pumpAndSettle();
    expect(fake.saved.single.$1, 'combo:lunch');
    expect(fake.saved.single.$3, 2);
  });

  // ── make it a meal ─────────────────────────────────────────────────────
  for (final arabic in [false, true]) {
    for (final (device, size) in [('phone', _phone), ('tablet', _tablet)]) {
      testWidgets(
        'the item sheet offers "Make it a meal +X" ($device, ${arabic ? 'ar' : 'en'})',
        (tester) async {
          final fake = _Fake(arabic: arabic);
          Object? result;
          await _mount(
            tester,
            fake,
            size: size,
            body: (context, ref) => Center(
              child: TextButton(
                key: const ValueKey('open'),
                onPressed: () async {
                  result = await showMadarSheet<Object?>(
                    context,
                    size: SheetSize.hug,
                    builder: (_) =>
                        ItemDetailSheet(item: _latteItem(), addons: const []),
                  );
                },
                child: const Text('open'),
              ),
            ),
          );
          await _open(tester);
          final label = coreWord(
            'meal.make_it_plus',
            arabic: arabic,
          ).replaceAll('{amount}', _money(12500, arabic: arabic));
          expect(find.text(label), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('make-it-a-meal')));
          await tester.pumpAndSettle();
          expect(fake.mealDrafts, ['item']);
          expect(result, isA<ComboDraft>());
          expect((result! as ComboDraft).picks.last.sizeLabel, 'Large');
        },
      );
    }
  }

  testWidgets('no meal on sale: no meal button', (tester) async {
    final fake = _Fake()..meal = null;
    await _mount(
      tester,
      fake,
      size: _phone,
      body: (context, ref) =>
          ItemDetailSheet(item: _latteItem(), addons: const []),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('make-it-a-meal')), findsNothing);
  });

  testWidgets('customising a pick hands its add-ons back, never to the cart', (
    tester,
  ) async {
    final fake = _Fake();
    ComboPickInput? back;
    await _mount(
      tester,
      fake,
      size: _tablet,
      body: (context, ref) => Center(
        child: TextButton(
          key: const ValueKey('open'),
          onPressed: () async {
            back = await showMadarSheet<ComboPickInput>(
              context,
              size: SheetSize.hug,
              builder: (_) => ItemDetailSheet(
                item: _latteItem(),
                addons: const [
                  ItemAddonView(
                    addonItemId: 'shot',
                    name: 'Extra shot',
                    addonType: 'extra',
                    chargedPriceMinor: 800,
                  ),
                ],
                pick: _pick('s-drink', 'latte', size: 'Large'),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    );
    await _open(tester);
    expect(find.byKey(const ValueKey('make-it-a-meal')), findsNothing);
    // The extras card opens on a tap, then the add-on is picked.
    await tester.tap(find.text('EXTRAS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extra shot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(coreWord('combo.done')));
    await tester.pumpAndSettle();
    expect(back?.slotId, 's-drink');
    expect(back?.sizeLabel, 'Large', reason: 'the combo sheet owns the size');
    expect(back?.addons.map((a) => a.addonItemId), ['shot']);
    expect(fake.saved, isEmpty);
  });

  // ── the cart: the combo line, and deals ─────────────────────────────────
  for (final arabic in [false, true]) {
    for (final (device, size) in [('phone', _phone), ('tablet', _tablet)]) {
      testWidgets(
        'the cart shows a combo with its items, and a deal to apply ($device, ${arabic ? 'ar' : 'en'})',
        (tester) async {
          final fake = _Fake(arabic: arabic)
            ..lines = [_comboLine(), _croissants()]
            ..suggestions = const [
              DealSuggestion(
                dealId: 'two-bites',
                name: 'Two bites',
                times: 1,
                timesLabel: 'Applies once',
                savingMinor: 2000,
                lineKeys: ['k-croissant'],
              ),
            ];
          final c = await _mount(
            tester,
            fake,
            size: size,
            body: (context, ref) =>
                SellCart(tableId: null, onTerminal: () {}, onEditLine: (_) {}),
          );
          await c.read(cartProvider(null).notifier).load();
          await tester.pumpAndSettle();

          // The combo's items, indented under it; the bigger size's extra.
          expect(find.byType(CartPartRow), findsNWidgets(3));
          expect(
            find.text('Latte · Large  +${_money(1000, arabic: arabic)}'),
            findsOneWidget,
          );
          expect(find.text('+ Oat milk'), findsOneWidget);
          expect(
            find.text(coreWord('combo.badge', arabic: arabic).toUpperCase()),
            findsWidgets,
          );
          // The suggestion, in the core's words, never applied by itself.
          expect(
            find.text(
              coreWord(
                'deal.qualifies',
                arabic: arabic,
              ).replaceAll('{deal}', 'Two bites'),
            ),
            findsOneWidget,
          );
          expect(fake.appliedIds, isEmpty);
          expect(tester.takeException(), isNull);

          await tester.tap(find.byKey(const ValueKey('deal-apply-two-bites')));
          await tester.pumpAndSettle();
          expect(fake.appliedIds, ['two-bites']);
          expect(find.byType(DealSuggestionBanner), findsNothing);
          expect(
            find.text(
              coreWord(
                'deal.applied',
                arabic: arabic,
              ).replaceAll('{deal}', 'Two bites'),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('deal-cut-k-croissant')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets("a deal the cart broke comes off with the core's reason", (
    tester,
  ) async {
    final fake = _Fake()
      ..lines = [_croissants()]
      ..notices = ['Two bites no longer applies to the cart, so it came off.'];
    final c = await _mount(
      tester,
      fake,
      size: _tablet,
      body: (context, ref) =>
          SellCart(tableId: null, onTerminal: () {}, onEditLine: (_) {}),
    );
    await c.read(cartProvider(null).notifier).load();
    await tester.pump();
    expect(
      c.read(appToastProvider)?.text,
      'Two bites no longer applies to the cart, so it came off.',
    );
  });

  testWidgets('removing an applied deal asks the core', (tester) async {
    final fake = _Fake()
      ..lines = [_croissants(dealCut: 2000, dealName: 'Two bites')]
      ..applied = const [
        AppliedDealView(
          id: 'app-1',
          dealId: 'two-bites',
          name: 'Two bites',
          times: 1,
          discountMinor: 2000,
          lineKeys: ['k-croissant'],
        ),
      ];
    final c = await _mount(
      tester,
      fake,
      size: _tablet,
      body: (context, ref) =>
          SellCart(tableId: null, onTerminal: () {}, onEditLine: (_) {}),
    );
    await c.read(cartProvider(null).notifier).load();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deal-remove-app-1')));
    await tester.pumpAndSettle();
    expect(fake.removedIds, ['app-1']);
  });
}
