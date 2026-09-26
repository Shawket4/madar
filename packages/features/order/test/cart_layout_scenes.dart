// The cart column, look A ("Soft"): one header row, the lines on paper as
// white cards, the notes as text under them, the thumb-zone toolbar, and Park
// beside Charge — pinned at the widths the till ships on, in English and
// Arabic.
//
// `MADAR_RENDER=true` writes `build/render/cart2-<scene>-<device>-<lang>.png`.
part of 'sell_render_test.dart';

CartLineView _lookLine(
  String id,
  String name,
  int price,
  int qty, {
  List<String> addons = const [],
}) => CartLineView(
  dealCutMinor: 0,
  kind: 'item',
  parts: const [],
  key: 'k-$id',
  itemId: id,
  name: name,
  addons: [
    for (final a in addons)
      CartAddonView(addonItemId: a, name: a, qty: 1, priceModifierMinor: 0),
  ],
  optionals: const [],
  unitPriceMinor: price,
  qty: qty,
  lineTotalMinor: price * qty,
);

/// Four lines: five items, a discount, a customer, both notes, two parked
/// orders. The Flat white is a staff drink with a recipe (the widest line);
/// the cake is food with a recipe.
final _busyCart = <CartLineView>[
  _lookLine('espresso', 'Espresso', 3500, 1),
  _lookLine('flat', 'Flat white', 5000, 2, addons: ['Oat milk', 'Extra shot']),
  _lookLine('cake', 'Chocolate cake', 6000, 1),
  _lookLine('iced-latte', 'Iced latte', 5000, 1, addons: ['Less ice']),
];

/// 24,500 less 10% (2,450), plus 14% tax on the rest.
const _busyTotals = CartTotals(
  itemCount: 5,
  subtotalMinor: 24500,
  discountMinor: 2450,
  taxMinor: 3087,
  serviceChargeMinor: 0,
  totalMinor: 25137,
);

const _emptyTotals = CartTotals(
  itemCount: 0,
  subtotalMinor: 0,
  discountMinor: 0,
  taxMinor: 0,
  serviceChargeMinor: 0,
  totalMinor: 0,
);

const _twoParked = <DraftView>[
  DraftView(
    id: 'd1',
    name: 'Ahmed',
    itemCount: 2,
    totalMinor: 9000,
    createdAt: '2026-09-12T18:40:00Z',
    lockedByOther: false,
    byOther: false,
  ),
  DraftView(
    id: 'd2',
    name: '',
    itemCount: 3,
    totalMinor: 13500,
    createdAt: '2026-09-12T18:52:00Z',
    lockedByOther: false,
    byOther: false,
  ),
];

/// The busy counter: the staff pool offers the Flat white, and the Flat white
/// and the cake carry recipe steps.
class _LookBridge extends _FakeBridge {
  _LookBridge({super.rtl, bool empty = false})
    : super(
        drafts: _twoParked,
        totals: empty ? _emptyTotals : _busyTotals,
        discount: empty
            ? const CartDiscountView(kind: '', offMinor: 0)
            : const CartDiscountView(
                kind: 'manual_percent',
                percentBps: 1000,
                offMinor: 2450,
              ),
      ) {
    carts[null] = empty ? <CartLineView>[] : List.of(_busyCart);
    if (empty) {
      orderNote = null;
    } else {
      metas[null] = const CartMeta(name: 'Mona Adel');
      cartKitchenNotes[null] = 'No nuts on the cake';
    }
  }

  static const _withRecipe = {'flat', 'cake'};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #listMenuItems) {
      return Future<List<MenuItemView>>.value([
        for (final i in _items)
          if (_withRecipe.contains(i.id))
            MenuItemView(
              kind: i.kind,
              id: i.id,
              name: i.name,
              categoryId: i.categoryId,
              basePriceMinor: i.basePriceMinor,
              isActive: true,
              allowedAddonIds: const [],
              sizes: const [],
              addonSlots: const [],
              optionalFields: const [],
              recipes: const [],
              recipeSteps: const [RecipeStepView(name: 'Steam the milk')],
            )
          else
            i,
      ]);
    }
    if (name == #previewStaffDrink) {
      final input = invocation.namedArguments[#input]! as StaffDrinkInput;
      return StaffDrinkPreviewView(
        offered: input.menuItemId == 'flat',
        access: const ActDecisionView(outcome: 'allow', reason: ''),
        decision: const StaffDrinkDecision(
          allowed: false,
          refusal: StaffDrinkRefusal.noteRequired,
          overspent: false,
          pool: StaffPoolDay(
            businessDate: '2026-09-26',
            allowance: 10,
            used: 0,
            remaining: 10,
            over: 0,
          ),
        ),
        reason: '',
        overWarning: '',
        poolLabel: '',
      );
    }
    if (name == #takeStaffDrinkNotices) return <String>[];
    return super.noSuchMethod(invocation);
  }
}

void _cartLayoutMain() {
  Finder inCart(Finder f) =>
      find.descendant(of: find.byType(SellCart), matching: f);

  /// The phone's cart is a sheet behind the bottom bar: open it.
  Future<void> openPhoneSheet(WidgetTester tester) async {
    await tester.tap(
      find
          .descendant(of: find.byType(SellBar), matching: find.byType(Nudge))
          .last,
    );
    await _settle(tester);
  }

  Future<void> mount(
    WidgetTester tester,
    Size size, {
    bool ar = false,
    _FakeBridge? bridge,
  }) async {
    await _mount(
      tester,
      screen: const TakeawaySellScreen(),
      size: size,
      bridge: bridge ?? _LookBridge(rtl: ar),
    );
    await _settle(tester);
    if (size == _phone) await openPhoneSheet(tester);
  }

  // ── the header ─────────────────────────────────────────────────────────

  for (final (device, size) in const [
    ('ipad', _ipad),
    ('ipadp', _ipadPortrait),
    ('lenovo', _lenovo),
    ('tab8', _tab8),
    ('phone', _phone),
  ]) {
    testWidgets('the header says "Order" at every width · $device', (
      tester,
    ) async {
      await mount(tester, size);
      expect(inCart(find.text(coreWord('sell.order_title'))), findsOneWidget);
    });
  }

  // ── Park and Charge ────────────────────────────────────────────────────

  for (final ar in [false, true]) {
    final lang = ar ? 'ar' : 'en';
    testWidgets('Park sits beside Charge under 320 · $lang', (tester) async {
      await mount(tester, _tab8, ar: ar);
      expect(tester.getSize(find.byType(SellCart)).width, lessThan(320));
      final park = tester.getRect(find.byKey(const ValueKey('cart-park')));
      final charge = tester.getRect(find.byKey(const ValueKey('cart-charge')));
      expect(park.center.dy, closeTo(charge.center.dy, 0.5));
      expect(park.height, closeTo(charge.height, 0.5));
      // At the START edge: left in English, right in Arabic.
      if (ar) {
        expect(park.left, greaterThanOrEqualTo(charge.right));
      } else {
        expect(park.right, lessThanOrEqualTo(charge.left));
      }
    });
  }

  // ── notes as text ──────────────────────────────────────────────────────

  testWidgets('notes show as text under the lines when set', (tester) async {
    await mount(tester, _ipad);
    final order = find.byKey(const ValueKey('cart-note-order-text'));
    final kitchen = find.byKey(const ValueKey('cart-note-kitchen-text'));
    expect(order, findsOneWidget);
    expect(kitchen, findsOneWidget);
    expect(
      find.descendant(
        of: order,
        matching: find.textContaining(
          'Birthday — bring the cake last',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: kitchen,
        matching: find.textContaining(
          'No nuts on the cake',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
    // Under the last line, in the list.
    final lastLine = tester.getRect(
      find.byKey(const ValueKey('round-k-iced-latte')),
    );
    expect(tester.getRect(order).top, greaterThanOrEqualTo(lastLine.bottom));

    // A tap opens its editor.
    await tester.tap(order);
    await _settle(tester);
    expect(find.text(coreWord('sell.note_title')), findsOneWidget);
  });

  testWidgets('notes are hidden when empty', (tester) async {
    final bridge = _LookBridge()..orderNote = null;
    bridge.cartKitchenNotes.clear();
    await mount(tester, _ipad, bridge: bridge);
    expect(find.byKey(const ValueKey('cart-note-order-text')), findsNothing);
    expect(find.byKey(const ValueKey('cart-note-kitchen-text')), findsNothing);
  });

  // ── hold to read ───────────────────────────────────────────────────────

  for (final ar in [false, true]) {
    final lang = ar ? 'ar' : 'en';
    String w(String key) => coreWord(key, arabic: ar);
    testWidgets('a long press on an icon-only control shows its word · $lang', (
      tester,
    ) async {
      await mount(tester, _tab8, ar: ar);
      final dineIn = find.byKey(const ValueKey('cart-mode-dine-in'));
      expect(
        find.descendant(of: dineIn, matching: find.text(w('charge.dine_in'))),
        findsNothing,
        reason: 'under 320 the toggle is glyphs only',
      );
      await tester.longPress(dineIn);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(w('charge.dine_in')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);

      await tester.longPress(find.byKey(const ValueKey('cart-order-note')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining(w('sell.note_title')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);
    });
  }

  // ── renders for the owner ──────────────────────────────────────────────

  for (final (device, size, ar) in const [
    ('ipad', _ipad, false),
    ('ipad', _ipad, true),
    ('tab8', _tab8, false),
    ('tab8', _tab8, true),
    ('phone', _phone, false),
  ]) {
    final tag = '$device-${ar ? 'ar' : 'en'}';
    testWidgets('render: busy $tag', (tester) async {
      await mount(tester, size, ar: ar);
      await _capture(
        tester,
        'cart2-busy${size == _phone ? '-sheet' : ''}-$tag',
      );
    });
  }

  testWidgets('render: empty ipad-en', (tester) async {
    await mount(tester, _ipad, bridge: _LookBridge(empty: true));
    await _capture(tester, 'cart2-empty-ipad-en');
  });

  testWidgets('render: dine in ipad-en', (tester) async {
    final c = await _mount(
      tester,
      screen: const TakeawaySellScreen(),
      size: _ipad,
      bridge: _LookBridge(),
    );
    c.read(dineInProvider(null).notifier).set(dineIn: true);
    await _settle(tester);
    await _capture(tester, 'cart2-dinein-ipad-en');
  });
}
