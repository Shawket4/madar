part of 'shell_render_test.dart';

// ── T2 B3: the dead Latte tile ───────────────────────────────────────────────

/// The shell's fake, with a takeaway cart that really changes, the Latte's
/// meal and its combo — every bridge answer a beat late, like a device's.
///
/// T2 B3: after "Make it a meal" and a Clear, a tap on the Latte tile did
/// nothing at all. The cart's ⋯ sheet closed itself with `maybePop()` and
/// raised the confirm in the same tick; `maybePop` drops its pop when the
/// history changes before it runs, so the ⋯ sheet stayed up after "Clear
/// cart" and its scrim took the tap (sheet_close_rule_test.dart).
class _MealShellBridge extends _FakeBridge {
  _MealShellBridge({super.rtl});

  final List<CartLineView> lines = [];
  final List<String> configuredAdds = [];

  Future<T> _later<T>(T v) =>
      Future<T>.delayed(const Duration(milliseconds: 40), () => v);

  static const _pick = ComboPickInput(
    slotId: 's-coffee',
    itemId: 'latte',
    qty: 1,
    addons: [],
    optionalFieldIds: [],
  );

  CartLineView _line(String id, String name, int price, {String? kind}) =>
      CartLineView(
        dealCutMinor: 0,
        kind: kind ?? 'item',
        parts: const [],
        key: 'k-$id',
        itemId: id,
        name: name,
        addons: const [],
        optionals: const [],
        unitPriceMinor: price,
        qty: 1,
        lineTotalMinor: price,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final a = invocation.namedArguments;
    final takeaway = a.containsKey(#tableId) && a[#tableId] == null;
    if (name == #listMenuItems) {
      return Future<List<MenuItemView>>.value([
        for (final i in _items)
          if (i.id == 'latte')
            const MenuItemView(
              kind: 'item',
              id: 'latte',
              name: 'Latte',
              categoryId: 'hot',
              basePriceMinor: 4500,
              isActive: true,
              allowedAddonIds: [],
              sizes: [],
              addonSlots: [],
              optionalFields: [],
              recipes: [],
              recipeSteps: [],
              defaultMilkAddonId: 'full',
            )
          else
            i,
      ]);
    }
    if (name == #listItemAddons) {
      return _later<List<ItemAddonView>>(const []);
    }
    if (name == #listItemModifierGroups) {
      return _later<List<ModifierGroupView>>(const []);
    }
    if (name == #previewConfiguredLine) {
      return _later<LinePreviewView>(
        const LinePreviewView(
          unitTotalMinor: 4500,
          extrasMinor: 0,
          lineTotalMinor: 4500,
        ),
      );
    }
    if (name == #validateItemSelections) {
      return _later<List<GroupViolationView>>(const []);
    }
    if (name == #mealOffer) {
      return a[#itemId] == 'latte'
          ? const MealOffer(
              comboId: 'meal',
              slotId: 's-coffee',
              name: 'Coffee & Treat',
              deltaMinor: 2000,
            )
          : null;
    }
    if (name == #itemMealDraft) {
      return _later<ComboDraft>(
        const ComboDraft(comboId: 'meal', qty: 1, picks: [_pick]),
      );
    }
    if (name == #comboDetail) {
      return const ComboDetail(
        id: 'meal',
        name: 'Coffee & Treat',
        priceMinor: 6500,
        isFixed: false,
        availableNow: true,
        slots: [
          ComboSlotDetail(
            id: 's-coffee',
            name: 'Coffee',
            min: 1,
            max: 1,
            ruleLabel: 'Pick 1',
            defaultItemId: 'latte',
            choices: [
              ComboChoiceDetail(
                itemId: 'latte',
                name: 'Latte',
                basePriceMinor: 4500,
                surchargeMinor: 0,
                sizes: [],
                isDefault: true,
                customisable: false,
                mustCustomise: false,
              ),
            ],
          ),
        ],
      );
    }
    if (name == #comboQuote) {
      return _later<ComboQuoteView>(
        const ComboQuoteView(
          priceMinor: 6500,
          unitTotalMinor: 6500,
          lineTotalMinor: 6500,
          surchargeMinor: 0,
          extrasMinor: 0,
          listMinor: 6500,
          savingMinor: 0,
          complete: true,
          pickNeeds: [],
        ),
      );
    }
    if (takeaway) {
      if (name == #cartLines) return _later<List<CartLineView>>(List.of(lines));
      if (name == #cartAddCombo) {
        lines.add(_line('meal', 'Coffee & Treat', 6500, kind: 'combo'));
        return _later<List<CartLineView>>(List.of(lines));
      }
      if (name == #cartAddConfigured) {
        configuredAdds.add(a[#itemId] as String);
        lines.add(_line(a[#itemId] as String, 'Latte', 4500));
        return _later<List<CartLineView>>(List.of(lines));
      }
      if (name == #cartAdd) {
        lines.add(_line(a[#itemId] as String, a[#name] as String, 4000));
        return _later<List<CartLineView>>(List.of(lines));
      }
      if (name == #cartClear) {
        lines.clear();
        return _later<void>(null);
      }
      if (name == #cartTotals) {
        final n = lines.length;
        return _later<CartTotals>(
          CartTotals(
            itemCount: n,
            subtotalMinor: n * 4500,
            discountMinor: 0,
            taxMinor: 0,
            serviceChargeMinor: 0,
            totalMinor: n * 4500,
          ),
        );
      }
    }
    return super.noSuchMethod(invocation);
  }
}

void mealTileMain() {
  for (final ar in [false, true]) {
    final lang = ar ? 'ar' : 'en';
    testWidgets('after a meal and Clear, the Latte tile still sells · $lang', (
      tester,
    ) async {
      final words = ar ? _ar : _en;
      final bridge = _MealShellBridge(rtl: ar);
      await _mount(tester, bridge: bridge, size: _ipad);
      await _tab(tester, 'sell');
      Finder latte() => find
          .descendant(of: find.byType(MenuGrid), matching: find.text('Latte'))
          .hitTestable();

      // Long press → the item sheet → "Make it a meal" → the combo → Add.
      await tester.longPress(latte().first);
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('make-it-a-meal')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('combo-save')));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(bridge.lines.map((l) => l.itemId), ['meal']);

      // Clear, the teller's way: the cart's ⋯, Clear, and the confirm.
      await tester.tap(
        find
            .byWidgetPredicate(
              (w) => w is MadarGlyphTile && w.glyph == MadarGlyph.more,
            )
            .hitTestable()
            .first,
      );
      await _settle(tester);
      await tester.tap(find.text(words['order.clear']!).last);
      await _settle(tester);
      await tester.tap(find.text(words['order.clear_cart']!).last);
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(bridge.lines, isEmpty);
      expect(
        _rootNavigator(tester).canPop(),
        isFalse,
        reason: 'no sheet or dialog is left over the Sell screen',
      );

      await tester.tap(latte().first);
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(bridge.configuredAdds, ['latte'], reason: 'the tap sold a Latte');
      await _shot(tester, 'shell-sell-after-meal-and-clear-$lang');
    });
  }
}
