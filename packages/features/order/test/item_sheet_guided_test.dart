// The item sheet, guided and on a keyboard.
//
// (2) Fast mode only: answering a pick-one required group scrolls to and
// flashes the next unanswered one; once every required group is answered Add
// is emphasised; a tap on the disabled "Choose X" scrolls to and flashes X.
// The standard sheet does none of it.
//
// (9) A hardware keyboard (an iPad's): 1–9 set the quantity, + and − step
// it, Enter adds when Add would, Esc closes. The keys are the note field's
// while it is being typed in. Sheet and panel, EN and AR.

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const Size _ipad = Size(1194, 834);

ModifierOptionView _opt(String id) =>
    ModifierOptionView(id: id, name: id, chargedPriceMinor: 0);

/// A required pick-one group of twelve choices: three rows of tiles, so the
/// third group starts below the fold of the iPad's panel.
ModifierGroupView _required(String id, String name, String prefix) =>
    ModifierGroupView(
      groupId: id,
      name: name,
      kind: ModifierGroupKind.addon,
      addonType: id,
      isRequired: true,
      minSelections: 1,
      maxSelections: 1,
      options: [for (var i = 1; i <= 12; i++) _opt('$prefix$i')],
    );

/// The sandwich: its bread, its sauce and its cheese must be chosen (none has
/// a default), then any extras.
final List<ModifierGroupView> _sandwichGroups = [
  _required('g-bread', 'Bread', 'bread'),
  _required('g-sauce', 'Sauce', 'sauce'),
  _required('g-cheese', 'Cheese', 'cheese'),
  ModifierGroupView(
    groupId: 'g-extra',
    name: 'Extras',
    kind: ModifierGroupKind.addon,
    addonType: 'extra',
    isRequired: false,
    minSelections: 0,
    maxSelections: 3,
    options: [_opt('bacon'), _opt('egg')],
  ),
];

List<ItemAddonView> _addonsOf(List<ModifierGroupView> groups) => [
  for (final g in groups)
    for (final o in g.options)
      ItemAddonView(
        addonItemId: o.id,
        name: o.name,
        addonType: g.addonType ?? '',
        chargedPriceMinor: o.chargedPriceMinor,
      ),
];

MenuItemView _item(String id, String name) => MenuItemView(
  kind: 'item',
  id: id,
  name: name,
  basePriceMinor: 8500,
  isActive: true,
  allowedAddonIds: const [],
  sizes: const [],
  addonSlots: const [],
  optionalFields: const [],
  recipes: const [],
  recipeSteps: const [],
);

/// A latte: nothing required, so Add works from the start.
final MenuItemView _latte = _item('latte', 'Latte');
final MenuItemView _sandwich = _item('sandwich', 'Club sandwich');

CartLineView _line(String itemId, int qty) => CartLineView(
  dealCutMinor: 0,
  kind: 'item',
  parts: const [],
  key: 'k-$itemId',
  itemId: itemId,
  name: itemId,
  addons: const [],
  optionals: const [],
  unitPriceMinor: 8500,
  qty: qty,
  lineTotalMinor: 8500 * qty,
);

class _Fake implements MadarBridge {
  _Fake({required this.rtl});
  final bool rtl;

  /// Every configured add, as (item, qty).
  final List<(String, int)> added = [];
  final List<CartLineView> _lines = [];

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
          unitTotalMinor: 8500,
          extrasMinor: 0,
          lineTotalMinor: 8500 * qty,
        ),
      );
    }
    if (n == #validateItemSelections) {
      return Future<List<GroupViolationView>>.value(const []);
    }
    if (n == #cartAddConfigured) {
      final qty = a[#qty] as int;
      added.add((a[#itemId] as String, qty));
      _lines.add(_line(a[#itemId] as String, qty));
      return Future<List<CartLineView>>.value(List.of(_lines));
    }
    if (n == #cartLines) {
      return Future<List<CartLineView>>.value(List.of(_lines));
    }
    if (n == #cartTotals) {
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
    if (n == #cartMeta) {
      return Future<CartMeta>.value(const CartMeta(name: ''));
    }
    if (n == #cartSetMeta) return Future<void>.value();
    if (n == #ownOpenTill) return null;
    if (n == #currentTill || n == #refreshTill) {
      return Future<TillView?>.value();
    }
    return null;
  }
}

/// The sheet as the Sell screen shows it: over the window (the standard
/// layout), or as a page of the menu panel (Fast mode), beside a cart column.
Future<_Fake> _open(
  WidgetTester tester, {
  required bool ar,
  required bool panel,
  required MenuItemView item,
  List<ModifierGroupView> groups = const [],
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = _ipad;
  addTearDown(tester.view.reset);
  final fake = _Fake(rtl: ar);
  final container = ProviderContainer(
    overrides: [bridgeProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  Widget sheet(BuildContext _) =>
      ItemDetailSheet(item: item, addons: _addonsOf(groups), groups: groups);
  final opener = Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () =>
            showMadarSheet<void>(context, size: SheetSize.hug, builder: sheet),
        child: const Text('open'),
      ),
    ),
  );
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: MadarTheme.light(),
        locale: Locale(ar ? 'ar' : 'en'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => Directionality(
          textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
        home: Scaffold(
          body: panel
              ? MadarPanelHost(
                  navigatorKey: nav,
                  backLabel: 'Back to menu',
                  child: Row(
                    children: [
                      const SizedBox(width: 340),
                      Expanded(
                        child: Navigator(
                          key: nav,
                          pages: [MaterialPage<void>(child: opener)],
                          onDidRemovePage: (_) {},
                        ),
                      ),
                    ],
                  ),
                )
              : opener,
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester);
  expect(find.byType(ItemDetailSheet), findsOneWidget);
  return fake;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Let every flash fade: a test ends with no timer pending.
Future<void> _fade(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 3));

ItemSheetGroupCard _card(WidgetTester tester, String id) =>
    tester.widget<ItemSheetGroupCard>(find.byKey(ValueKey(id)));

ItemSheetFooter _footer(WidgetTester tester) =>
    tester.widget<ItemSheetFooter>(find.byType(ItemSheetFooter));

/// The sheet's scrolling body.
Rect _viewport(WidgetTester tester) => tester.getRect(
  find
      .descendant(
        of: find.byType(ItemDetailSheet),
        matching: find.byType(SingleChildScrollView),
      )
      .first,
);

/// Whether the top of [id]'s card is in view.
bool _inView(WidgetTester tester, String id) {
  final top = tester.getTopLeft(find.byKey(ValueKey(id))).dy;
  final view = _viewport(tester);
  return top >= view.top - 1 && top < view.bottom - 40;
}

Future<void> _tapOption(WidgetTester tester, String name) async {
  await tester.ensureVisible(find.text(name));
  await tester.pump();
  await tester.tap(find.text(name));
  await tester.pump();
  await _settle(tester);
}

/// A latte with its sizes, its milk (pick one) and its extras (pick many),
/// for the choices' own look.
const MenuItemView _sizedLatte = MenuItemView(
  kind: 'item',
  id: 'latte',
  name: 'Latte',
  basePriceMinor: 4500,
  isActive: true,
  allowedAddonIds: [],
  sizes: [
    ItemSizeView(id: 's', label: 'Small', priceMinor: 4500, isActive: true),
    ItemSizeView(id: 'l', label: 'Large', priceMinor: 6500, isActive: true),
  ],
  addonSlots: [],
  optionalFields: [],
  recipes: [],
  recipeSteps: [],
);

final List<ModifierGroupView> _latteGroups = [
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
      ModifierOptionView(id: 'oat', name: 'Oat', chargedPriceMinor: 500),
    ],
  ),
  const ModifierGroupView(
    groupId: 'g-extra',
    name: 'Extras',
    kind: ModifierGroupKind.addon,
    addonType: 'extra',
    isRequired: false,
    minSelections: 0,
    maxSelections: 3,
    options: [
      ModifierOptionView(
        id: 'shot',
        name: 'Extra shot',
        chargedPriceMinor: 800,
      ),
    ],
  ),
];

/// The rendered height of the chip [text] sits in.
double _chipHeight(WidgetTester tester, String text) => tester
    .getSize(
      find
          .ancestor(of: find.text(text), matching: find.byType(TactileScale))
          .first,
    )
    .height;

void main() {
  for (final ar in [false, true]) {
    final lang = ar ? 'ar' : 'en';

    // The owner's call on 0.11.0's tiles: back to the chips, a size up.
    testWidgets('the choices are chips, at least 56pt tall · $lang', (
      tester,
    ) async {
      await _open(
        tester,
        ar: ar,
        panel: false,
        item: _sizedLatte,
        groups: _latteGroups,
      );
      for (final text in ['Small', 'Large', 'Full fat', 'Oat']) {
        expect(
          _chipHeight(tester, text),
          greaterThanOrEqualTo(kOptionChipMinHeight),
          reason: text,
        );
      }
      // A chip hugs its words: not 0.11.0's grid of equal tiles.
      double width(String text) => tester
          .getSize(
            find
                .ancestor(
                  of: find.text(text),
                  matching: find.byType(TactileScale),
                )
                .first,
          )
          .width;
      expect(width('Full fat'), isNot(width('Oat')));
      // Options flow as chips (a Wrap), sizes sit in a row.
      expect(
        find.ancestor(of: find.text('Oat'), matching: find.byType(Wrap)),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: find.text('Large'), matching: find.byType(Row)),
        findsWidgets,
      );
      // The price rides the chip as a "+EGP" pill.
      expect(find.textContaining('5.00'), findsWidgets);
      // An optional group opens folded; unfolded, its extra is a chip too,
      // and once picked a chip with its own stepper.
      await tester.ensureVisible(find.text('EXTRAS'));
      await tester.pump();
      await tester.tap(find.text('EXTRAS'));
      await _settle(tester);
      expect(
        _chipHeight(tester, 'Extra shot'),
        greaterThanOrEqualTo(kOptionChipMinHeight),
      );
      await tester.tap(find.text('Extra shot'));
      await _settle(tester);
      expect(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('Extra shot'),
                matching: find.byType(Container),
              )
              .first,
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    group('Fast mode guides the required picks · $lang', () {
      testWidgets('an answer scrolls to and flashes the next open group', (
        tester,
      ) async {
        await _open(
          tester,
          ar: ar,
          panel: true,
          item: _sandwich,
          groups: _sandwichGroups,
        );
        expect(_inView(tester, 'g-cheese'), isFalse, reason: 'below the fold');
        expect(_card(tester, 'g-sauce').highlighted, isFalse);

        await _tapOption(tester, 'bread2');
        expect(_card(tester, 'g-sauce').highlighted, isTrue);
        expect(_card(tester, 'g-bread').highlighted, isFalse);
        expect(_inView(tester, 'g-sauce'), isTrue);

        await _tapOption(tester, 'sauce5');
        expect(_card(tester, 'g-cheese').highlighted, isTrue);
        expect(_card(tester, 'g-sauce').highlighted, isFalse);
        expect(_inView(tester, 'g-cheese'), isTrue, reason: 'scrolled to it');

        await _fade(tester);
        expect(
          _card(tester, 'g-cheese').highlighted,
          isFalse,
          reason: 'a flash, not a state',
        );
      });

      testWidgets('Add is emphasised once every required group is answered', (
        tester,
      ) async {
        await _open(
          tester,
          ar: ar,
          panel: true,
          item: _sandwich,
          groups: _sandwichGroups,
        );
        expect(_footer(tester).canAdd, isFalse);
        expect(_footer(tester).emphasize, isFalse);
        await _tapOption(tester, 'bread1');
        await _tapOption(tester, 'sauce1');
        expect(_footer(tester).emphasize, isFalse, reason: 'cheese is open');
        await _tapOption(tester, 'cheese3');
        expect(_footer(tester).canAdd, isTrue);
        expect(_footer(tester).emphasize, isTrue);
        await _fade(tester);
      });

      testWidgets(
        'the disabled Choose button scrolls to and flashes its group',
        (tester) async {
          await _open(
            tester,
            ar: ar,
            panel: true,
            item: _sandwich,
            groups: _sandwichGroups,
          );
          // Scroll the bread away, as a teller reading the extras would.
          await tester.drag(
            find
                .descendant(
                  of: find.byType(ItemDetailSheet),
                  matching: find.byType(SingleChildScrollView),
                )
                .first,
            const Offset(0, -500),
          );
          await _settle(tester);
          expect(_inView(tester, 'g-bread'), isFalse);

          final choose = '${coreWord('order.select_prefix', arabic: ar)} Bread';
          await tester.tap(find.text(choose));
          await tester.pump();
          await _settle(tester);
          expect(_card(tester, 'g-bread').highlighted, isTrue);
          expect(_inView(tester, 'g-bread'), isTrue);
          await _fade(tester);
          expect(_card(tester, 'g-bread').highlighted, isFalse);
        },
      );
    });

    group('the standard sheet is not guided · $lang', () {
      testWidgets('no scroll, no flash, no emphasis', (tester) async {
        await _open(
          tester,
          ar: ar,
          panel: false,
          item: _sandwich,
          groups: _sandwichGroups,
        );
        final before = _viewport(tester);
        final cheeseTop = tester.getTopLeft(
          find.byKey(const ValueKey('g-cheese')),
        );
        await tester.tap(find.text('bread2'));
        await _settle(tester);
        for (final id in ['g-bread', 'g-sauce', 'g-cheese']) {
          expect(_card(tester, id).highlighted, isFalse);
        }
        expect(_viewport(tester), before);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('g-cheese'))),
          cheeseTop,
          reason: 'nothing scrolled',
        );
        final choose = '${coreWord('order.select_prefix', arabic: ar)} Sauce';
        await tester.tap(find.text(choose), warnIfMissed: false);
        await _settle(tester);
        expect(_card(tester, 'g-sauce').highlighted, isFalse);
        expect(_footer(tester).emphasize, isFalse);
      });
    });

    for (final panel in [false, true]) {
      final where = panel ? 'Fast mode panel' : 'sheet';
      group('a hardware keyboard in the $where · $lang', () {
        testWidgets('digits set the quantity, + and − step it', (tester) async {
          await _open(tester, ar: ar, panel: panel, item: _latte);
          expect(_footer(tester).qty, 1);
          await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
          await tester.pump();
          expect(_footer(tester).qty, 3);
          await tester.sendKeyEvent(LogicalKeyboardKey.numpad7);
          await tester.pump();
          expect(_footer(tester).qty, 7);
          await tester.sendKeyEvent(LogicalKeyboardKey.numpadAdd);
          await tester.pump();
          expect(_footer(tester).qty, 8);
          await tester.sendKeyEvent(LogicalKeyboardKey.minus);
          await tester.pump();
          expect(_footer(tester).qty, 7);
          // Shift+= on a hardware keyboard types "+".
          await tester.sendKeyDownEvent(
            LogicalKeyboardKey.equal,
            character: '+',
          );
          await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);
          await tester.pump();
          expect(_footer(tester).qty, 8);
          if (ar) {
            // An Arabic layout types Arabic-Indic digits.
            await tester.sendKeyDownEvent(
              LogicalKeyboardKey.digit2,
              character: '٢',
            );
            await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
            await tester.pump();
            expect(_footer(tester).qty, 2);
          }
        });

        testWidgets('Enter adds the line and closes', (tester) async {
          final fake = await _open(tester, ar: ar, panel: panel, item: _latte);
          await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await _settle(tester);
          expect(fake.added, [('latte', 2)]);
          expect(find.byType(ItemDetailSheet), findsNothing);
        });

        testWidgets('Enter adds nothing while a required group is open', (
          tester,
        ) async {
          final fake = await _open(
            tester,
            ar: ar,
            panel: panel,
            item: _sandwich,
            groups: _sandwichGroups,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
          await _settle(tester);
          expect(fake.added, isEmpty);
          expect(find.byType(ItemDetailSheet), findsOneWidget);
          await _fade(tester);
        });

        testWidgets('Esc closes and adds nothing', (tester) async {
          final fake = await _open(tester, ar: ar, panel: panel, item: _latte);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _settle(tester);
          expect(find.byType(ItemDetailSheet), findsNothing);
          expect(fake.added, isEmpty);
        });

        testWidgets('the note field keeps its keys', (tester) async {
          final fake = await _open(tester, ar: ar, panel: panel, item: _latte);
          final note = find.descendant(
            of: find.byType(ItemDetailSheet),
            matching: find.byType(EditableText),
          );
          await tester.ensureVisible(note.last);
          await tester.tap(note.last);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(_footer(tester).qty, 1, reason: 'typed, not a quantity');
          expect(fake.added, isEmpty, reason: 'Enter in the note adds nothing');
          expect(find.byType(ItemDetailSheet), findsOneWidget);
        });
      });
    }
  }
}
