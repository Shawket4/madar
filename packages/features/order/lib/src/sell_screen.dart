// Sell — the counter screen and, when entered from a table or a bill, the
// round builder. The header says which.
//
// The one big saving in the redesign lives here: QUICK-ADD. A tap on a tile
// adds one; the item sheet opens only when the item has a required choice
// (more than one size, or a modifier group that must be answered), on a
// long-press, or to edit a line. A counter sale is tile → Charge → Exact.
//
// On an iPad the cart is a column beside the catalog; on a phone it is a bar
// at the bottom whose ▲ opens it as a sheet. Both draw `SellCart`.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_order/src/bundle_detail_sheet.dart';
import 'package:feature_order/src/cart_anchor.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/sell_cart.dart';
import 'package:feature_order/src/table_clear_prompt.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:feature_order/src/words.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Synthetic category id for the Combos chip (bundles are not a category).
const String _kCombos = '__combos__';

/// Tile geometry.
///
/// A WIDTH BAND and a ratio, never a fixed height. It used to be 168 x 108
/// pinned, which is right at exactly one window size and wrong at every other
/// — the proportions drifted as the column changed, names truncated at two
/// lines, and "EGP" wrapped off its own amount. The grid picks a column count
/// from the width it is actually handed and derives the height from that, so
/// a phone gets two across, an 11" three, a 13" four or five, and the card
/// keeps its shape at all of them.
const double _kTileMinWidth = 190;
const double _kTileMaxWidth = 250;

/// Card height as a fraction of its width. The image block is square and
/// flush to the leading edge, so this is what leaves the text two comfortable
/// lines beside it.
const double _kTileAspect = 0.62;

/// Sell.
class SellScreen extends ConsumerStatefulWidget {
  /// The SELL TAB — the counter, and only the counter.
  ///
  /// It aims the cart at takeaway every time it is shown, which is the fix
  /// for two reports at once: a teller who tapped a table, changed their
  /// mind and came back to Sell used to still be ringing up for that table
  /// with no sign of it, and a cart half-built at the counter used to follow
  /// them onto it. Retargeting parks whatever is in hand first, so nothing
  /// is lost either way.
  const SellScreen({super.key}) : forTable = false;

  /// Taking an order FOR A TABLE — a pushed screen of its own, with its own
  /// back, reached from the floor or from a bill. Same menu, different
  /// errand: it keeps whatever target the caller already set instead of
  /// resetting to the counter.
  const SellScreen.forTable({super.key}) : forTable = true;

  /// See the two constructors. False = the Sell tab = takeaway.
  final bool forTable;

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen>
    with RealtimeGatedPoll<SellScreen> {
  final _search = TextEditingController();
  bool _searching = false;
  String? _categoryId;

  /// Whether an item needs its sheet, remembered per item. The answer needs
  /// the item's modifier groups from the core, which is a bridge call — once
  /// per item per screen life is plenty; per tap would put a round-trip
  /// between the finger and the cart.
  final _needsSheet = <String, bool>{};

  OrderNotifier get _notifier => ref.read(orderProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(() async {
        await _notifier.ensureInit();
        // The TAB is the counter. Aiming the cart back at takeaway parks
        // anything still pointed at a table, so returning here from a table
        // you never fired lands you where the tab says you are.
        if (!widget.forTable && mounted) {
          await _notifier.pointCartAtTakeaway();
        }
      }());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ── quick-add ──────────────────────────────────────────────────────────────

  /// The rule: a sheet iff the item has more than one size, or any modifier
  /// group that is required (or wants at least one pick). Everything else is
  /// one tap.
  Future<bool> _itemNeedsSheet(MenuItemView item) async {
    final known = _needsSheet[item.id];
    if (known != null) return known;
    var needs = item.sizes.length > 1;
    if (!needs) {
      final groups = await _notifier.loadItemModifierGroups(item.id);
      needs = groups.any((g) => g.isRequired || g.minSelections > 0);
    }
    _needsSheet[item.id] = needs;
    return needs;
  }

  Future<void> _onTileTap(MenuItemView item, Offset origin) async {
    if (await _itemNeedsSheet(item)) {
      await _openItemSheet(item);
      return;
    }
    await _quickAdd(item);
    if (!mounted) return;
    _flyToCart(origin);
  }

  /// The quick-add path skips the sheet, but a recipe's base modifier — full
  /// -fat milk under a latte — must still land on the line: the owner's
  /// report was that skipping the sheet silently skipped the default too.
  /// `addConfigured` (not `addToCart`) is what carries an addon selection,
  /// so an item with a default rides the exact same commit path — and so the
  /// exact same "selected" chip / recipe BASE flag — a manual pick gets in
  /// [ItemDetailSheet]; plain items keep the cheaper `addToCart`.
  Future<void> _quickAdd(MenuItemView item) {
    final milk = item.defaultMilkAddonId;
    if (milk == null) return _notifier.addToCart(item);
    return _notifier.addConfigured(
      itemId: item.id,
      addons: [AddonSelection(addonItemId: milk, qty: 1)],
      optionalIds: const [],
      qty: 1,
      sizeLabel: item.sizes.firstOrNull?.label,
    );
  }

  /// Mirrors `ItemDetailSheet._flyToCart` — the same dot arcing into the cart
  /// anchor, just launched from the tapped tile instead of a sheet footer,
  /// since quick-add skips the sheet the flight used to live behind entirely
  /// (the reported bug: tapping a tile added the item with no motion at all).
  void _flyToCart(Offset origin) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    final to = cartAnchorCenter();
    if (to == null) return;
    playCartFlight(
      context,
      from: origin,
      to: to,
      onArrive: () => cartCatchTick.value++,
    );
  }

  Future<void> _openItemSheet(MenuItemView item, {CartLineView? edit}) async {
    final addons = await _notifier.loadItemAddons(item.id);
    final groups = await _notifier.loadItemModifierGroups(item.id);
    if (!mounted) return;
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      builder: (_) => ItemDetailSheet(
        item: item,
        addons: addons,
        groups: groups,
        editLine: edit,
      ),
    );
  }

  Future<void> _editLine(CartLineView line) async {
    final item = ref.read(orderProvider).menuItemById(line.itemId);
    if (item == null) return;
    await _openItemSheet(item, edit: line);
  }

  Future<void> _openBundle(BundleView bundle) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => BundleDetailSheet(bundle: bundle),
    );
  }

  // ── terminal ───────────────────────────────────────────────────────────────

  /// Charge a counter cart through the tender drawer, or fire the round.
  Future<void> _terminal() async {
    final state = ref.read(orderProvider);
    final cta = sellCtaFor(state, ref.read(bridgeProvider));
    if (!cta.enabled) return;
    if (cta.sendsToKitchen) {
      // A round on an existing bill, or the first round on a table (or on a
      // table-less bill at a floorless branch). The notifier reads the target
      // from state; the covers picked at seating ride along.
      await _notifier.fireOrAddRound(tableId: state.cartTableId);
      return;
    }
    // Captured BEFORE the drawer: settling clears the cart (and with it the
    // draft identity) — this is the parked order the sale completes.
    final settledDraftId = state.cartDraftId;
    final outcome = await showCharge(
      context,
      const ChargeTarget.cart(),
      // "Not printed — no printer ›" on the Done card lands on the printer
      // sheet, not on a dead end.
      onPrinterSettings: () => unawaited(showPrinterSheet(context)),
    );
    if (!mounted) return;
    if (outcome != null) {
      await _notifier.onOrderSettled(settledDraftId);
      return;
    }
    // Closed without taking money: the cart is as it was, but the drawer
    // may have applied a discount to it on the way.
    await _notifier.loadCart();
  }

  Future<void> _openCartSheet() async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (sheetContext) => SellCart(
        onTerminal: () {
          Navigator.of(sheetContext).maybePop();
          unawaited(_terminal());
        },
        onEditLine: (line) => unawaited(_editLine(line)),
        onClose: () => Navigator.of(sheetContext).maybePop(),
      ),
    );
  }

  /// Parked carts — counter only, narrow layout only (see the header chip
  /// below): opens the cart sheet, which now leads with `TellerHeldStrip` —
  /// every parked draft, one tap to switch, × to discard, a pencil to
  /// rename the live one. `DraftsScreen` would have been the obvious reach
  /// here, but `feature_order.dart` is explicit that it — like `OrderScreen`
  /// — is a screen the redesign REPLACED and "nothing new should reach for":
  /// the strip is the redesign's own answer to the same list.
  Future<void> _openParked() => _openCartSheet();

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    listenForTableClear(context, ref);
    // Back to where the round came from once it is in — only when this
    // screen was PUSHED (from a table, from a bill). As a tab it stays.
    ref
      ..listen(orderProvider.select((s) => s.firedSeq), (prev, next) {
        if (prev == null || next == prev) return;
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      })
      ..listen(ticketTickProvider, (_, _) {
        unawaited(_notifier.loadOpenTickets());
      })
      ..listen(connectivityPulseProvider, (_, _) {
        unawaited(_notifier.syncFromStatus());
      })
      ..listen(localeProvider.select((s) => s.locale), (_, _) {
        unawaited(_notifier.loadCatalog());
      });
    realtimeGatedPoll(
      interval: const Duration(seconds: 20),
      onPoll: () => unawaited(_notifier.loadOpenTickets()),
    );

    final layout = MadarLayout.of(context);
    final isWaiter = ref.watch(orderProvider.select((s) => s.isWaiter));
    final drafts = ref.watch(orderProvider.select((s) => s.drafts.length));
    final title = ref.watch(orderProvider.select(_headerTitleOf));
    final counter =
        !isWaiter &&
        ref.watch(
          orderProvider.select(
            (s) => s.cartTableId == null && s.activeTicketId == null,
          ),
        );

    final header = MadarHeader(
      title: title == null ? orderWord(bridge, 'sell.takeaway') : title(bridge),
      onBack: Navigator.of(context).canPop()
          ? () => Navigator.of(context).maybePop()
          : null,
      actions: [
        MadarGlyphTile(
          glyph: _searching ? MadarGlyph.close : MadarGlyph.search,
          semanticLabel: bridge.tr(key: 'order.search'),
          onTap: () => setState(() {
            _searching = !_searching;
            if (!_searching) _search.clear();
          }),
        ),
        // Wide layout keeps the cart column on-screen — its own
        // `TellerHeldStrip` already shows every parked draft, so a second
        // entry point here would just be a shortcut to something already
        // visible. Narrow hides the cart behind a sheet, so this is that
        // sheet's only door.
        if (counter && !layout.isTablet)
          // An ACTION, not a filter — so it is the kit's button, like every
          // other action. A chip says "this is one of a set you choose
          // between"; this opens a sheet.
          MadarButton(
            label: drafts == 0
                ? orderWord(bridge, 'sell.parked')
                : '${orderWord(bridge, 'sell.parked')} $drafts',
            glyph: MadarGlyph.bag,
            variant: MadarButtonVariant.secondary,
            size: MadarButtonSize.compact,
            onTap: () => unawaited(_openParked()),
          ),
      ],
      // The search field belongs to the whole screen; the CATEGORY strip does
      // not — see below, where it sits inside the catalog column.
      below: _searching
          ? MadarField(
              controller: _search,
              placeholder: bridge.tr(key: 'order.search'),
              glyph: MadarGlyph.search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            )
          : null,
    );

    // INSIDE the catalog side of the split, not above it.
    //
    // The header spans the window, so a strip hung under it ran straight
    // across the divider and over the cart — on an iPad the categories
    // finished somewhere in the middle of the Takeaway column. It is the
    // catalog's own filter and it belongs to the catalog's width; it already
    // scrolls horizontally, so once it is bounded correctly the scrolling
    // does what it was always meant to do.
    final categories = _searching
        ? null
        : _CategoryChips(
            selected: _categoryId,
            onSelect: (id) => setState(() => _categoryId = id),
          );

    final catalog = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (categories != null)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              layout.gutter,
              Space.md,
              layout.gutter,
              0,
            ),
            child: categories,
          ),
        Expanded(
          child: _Catalog(
            categoryId: _categoryId,
            query: _search.text,
            onItemTap: (item, origin) => unawaited(_onTileTap(item, origin)),
            onItemLongPress: (item) => unawaited(_openItemSheet(item)),
            onBundleTap: (b) => unawaited(_openBundle(b)),
          ),
        ),
      ],
    );

    // A tab body — the shell's top bar above it already paid the top inset.
    return MadarPageScaffold(
      safeTop: false,
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                layout.gutter,
                Space.md,
                layout.gutter,
                0,
              ),
              child: header,
            ),
            Expanded(
              child: layout.isTablet
                  ? Row(
                      children: [
                        Expanded(child: catalog),
                        const VerticalDivider(width: 1, thickness: 1),
                        SizedBox(
                          width: Responsive.cartColumnWidth,
                          child: SellCart(
                            onTerminal: () => unawaited(_terminal()),
                            onEditLine: (line) => unawaited(_editLine(line)),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: catalog),
                        SellBar(
                          onOpen: () => unawaited(_openCartSheet()),
                          onTerminal: () => unawaited(_terminal()),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// The header's title, or null for the plain counter — a function of the
  /// slice so the header rebuilds only when the target changes.
  static String Function(MadarBridge)? _headerTitleOf(OrderState s) {
    final ticket = s.activeTicket;
    final tableId = ticket?.tableId ?? s.cartTableId;
    final tableLabel = tableId == null
        ? null
        : s.floorLayout?.tables
                  .where((t) => t.id == tableId)
                  .firstOrNull
                  ?.label ??
              s.cartTableLabel;
    if (ticket != null) {
      final rounds = ticket.lines.isEmpty
          ? 0
          : ticket.lines
                .map((l) => l.roundNumber)
                .reduce((a, b) => a > b ? a : b);
      final who = tableLabel ?? ticket.customerName ?? ticket.ticketRef ?? '';
      return (b) => '$who · ${b.tr(key: 'tables.round')} ${rounds + 1}';
    }
    if (tableLabel != null) {
      return (b) => '$tableLabel · ${b.tr(key: 'tables.round')} 1';
    }
    if (s.isWaiter) {
      final name = s.cartName;
      return (b) => name == null
          ? orderWord(b, 'bills.new_bill')
          : '${orderWord(b, 'bills.new_bill')} · $name';
    }
    return null;
  }
}

/// All · the categories · Combos, as chips in a horizontal strip.
class _CategoryChips extends ConsumerWidget {
  const _CategoryChips({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final categories = ref.watch(orderProvider.select((s) => s.categories));
    final hasBundles = ref.watch(
      orderProvider.select((s) => s.bundles.isNotEmpty),
    );
    return SizedBox(
      height: Metrics.chipHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          MadarChip(
            label: bridge.tr(key: 'order.all'),
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final c in categories.where((c) => c.isActive)) ...[
            const SizedBox(width: Space.sm),
            MadarChip(
              label: c.name,
              selected: selected == c.id,
              onTap: () => onSelect(c.id),
            ),
          ],
          if (hasBundles) ...[
            const SizedBox(width: Space.sm),
            MadarChip(
              label: bridge.tr(key: 'order.combos'),
              selected: selected == _kCombos,
              onTap: () => onSelect(_kCombos),
            ),
          ],
        ],
      ),
    );
  }
}

/// The tile grid, filtered by category and search.
class _Catalog extends ConsumerWidget {
  const _Catalog({
    required this.categoryId,
    required this.query,
    required this.onItemTap,
    required this.onItemLongPress,
    required this.onBundleTap,
  });

  final String? categoryId;
  final String query;

  /// `origin` is the tapped tile's on-screen center — the add-to-cart
  /// flight's launch point, so it has to come from whichever tile was
  /// actually hit, not a fixed spot on the screen.
  final void Function(MenuItemView item, Offset origin) onItemTap;
  final ValueChanged<MenuItemView> onItemLongPress;
  final ValueChanged<BundleView> onBundleTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final notifier = ref.read(orderProvider.notifier);
    final loading = ref.watch(orderProvider.select((s) => s.isLoadingCatalog));
    final currency = ref.watch(orderProvider.select((s) => s.currency));
    final layout = MadarLayout.of(context);
    final padding = EdgeInsetsDirectional.all(layout.gutter);
    // Derived from the width this column ACTUALLY has — which on a tablet is
    // the window minus the rail minus the cart, not the window — so the same
    // rule holds on a phone, a split iPad and a 13".
    SliverGridDelegate delegateFor(double width) {
      final usable = width - layout.gutter * 2;
      // As many columns as fit at the minimum, then one more for as long as
      // the tiles would otherwise grow past the maximum. Both ends matter: a
      // 13" with four 300px cards looks as wrong as a phone with five 70px
      // ones, and a single band cannot say that on its own.
      var columns = math.max(1, (usable / _kTileMinWidth).floor());
      double widthAt(int n) => (usable - Space.md * (n - 1)) / n;
      while (widthAt(columns) > _kTileMaxWidth) {
        columns += 1;
      }
      return SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: 1 / _kTileAspect,
        mainAxisSpacing: Space.md,
        crossAxisSpacing: Space.md,
      );
    }

    if (loading) return const SkeletonList();

    if (categoryId == _kCombos) {
      final bundles = ref.watch(orderProvider.select((s) => s.bundles));
      return LayoutBuilder(
        builder: (context, c) => GridView.builder(
          key: const PageStorageKey('sell-combos'),
          padding: padding,
          gridDelegate: delegateFor(c.maxWidth),
          itemCount: bundles.length,
          itemBuilder: (context, i) => _BundleTile(
            bundle: bundles[i],
            currency: currency,
            label: bridge.tr(key: 'order.configure'),
            onTap: () => onBundleTap(bundles[i]),
          ),
        ),
      );
    }

    final items = ref.watch(orderProvider.select((s) => s.menuItems));
    final cartLines = ref.watch(orderProvider.select((s) => s.cartLines));
    final categories = ref.watch(orderProvider.select((s) => s.categories));
    final q = query.trim().toLowerCase();
    final visible = items
        .where(
          (i) =>
              i.isActive &&
              (categoryId == null || i.categoryId == categoryId) &&
              (q.isEmpty ||
                  i.name.toLowerCase().contains(q) ||
                  (i.description?.toLowerCase().contains(q) ?? false)),
        )
        .toList(growable: false);
    if (visible.isEmpty) {
      if (q.isNotEmpty) {
        return EmptyState(
          icon: 'magnifyingglass',
          lottieAsset: 'no_results',
          title: bridge.tr(key: 'order.empty_search'),
        );
      }
      return EmptyState(
        icon: 'tray',
        title: bridge.tr(key: 'order.empty'),
        message: bridge.tr(key: 'order.empty_desc'),
        actionLabel: bridge.tr(key: 'order.sync_menu'),
        onAction: () => unawaited(notifier.refreshServerData()),
      );
    }
    int inCart(String id) =>
        cartLines.where((l) => l.itemId == id).fold(0, (n, l) => n + l.qty);
    String categoryName(String? id) =>
        categories.where((c) => c.id == id).firstOrNull?.name ?? '';
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, c) => GridView.builder(
        key: PageStorageKey('sell-${categoryId ?? 'all'}'),
        padding: padding,
        gridDelegate: delegateFor(c.maxWidth),
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final item = visible[i];
          final cat = categoryName(item.categoryId);
          return SellTile(
            item: item,
            currency: currency,
            inCart: inCart(item.id),
            accent: hexColor(
              notifier
                  .categoryStyle(cat.isEmpty ? item.name : cat, dark: dark)
                  .accent,
            ),
            onTap: (origin) => onItemTap(item, origin),
            onLongPress: () => onItemLongPress(item),
          );
        },
      ),
    );
  }
}

/// One item tile: flat surface, 16px corners, a leading thumbnail, the name
/// and a mono price, a teal count disc once the item is in the cart. A photo
/// when the core has one on disk; otherwise the thumbnail falls back to a
/// quiet wash in the category's colour (never a network fetch either way —
/// see [_TileThumb]).
class SellTile extends StatelessWidget {
  const SellTile({
    required this.item,
    required this.currency,
    required this.inCart,
    required this.accent,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final MenuItemView item;
  final String currency;
  final int inCart;
  final Color accent;

  /// Called with the tile's on-screen center, for the add-to-cart flight.
  final void Function(Offset origin) onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Semantics(
      button: true,
      label:
          '${item.name}, ${Money.format(item.basePriceMinor, currency: currency)}',
      child: GestureDetector(
        onLongPress: () {
          MadarHaptics.impact();
          onLongPress();
        },
        child: TactileScale(
          onTap: () {
            final box = context.findRenderObject();
            final origin = box is RenderBox && box.hasSize
                ? box.localToGlobal(box.size.center(Offset.zero))
                : Offset.zero;
            onTap(origin);
          },
          child: AnimatedContainer(
            duration: MotionSpec.standardDuration,
            curve: MotionSpec.standardCurve,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(
                color: inCart > 0 ? colors.accent : colors.borderLight,
                width: inCart > 0 ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Flush to the card's leading and vertical edges, clipped
                    // by the card's own radius. Inset inside the padding it
                    // read as a stamp floating on white — these product shots
                    // are mostly white themselves, so a small contained image
                    // is barely an image at all.
                    _TileThumb(item: item, accent: accent),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: Space.md,
                          vertical: Space.sm,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Text(
                                item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: MadarType.title.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(height: Space.xs),
                            // One line, always. The amount used to wrap under
                            // its own currency — "EGP" on one row and
                            // "160.00" on the next — which is not a price.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: MoneyText(
                                item.basePriceMinor,
                                currency: currency,
                                color: colors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (inCart > 0)
                  PositionedDirectional(
                    top: Space.sm,
                    end: Space.sm,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 26),
                      height: 26,
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: Space.sm,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$inCart',
                        textDirection: TextDirection.ltr,
                        style: MadarType.numMd.copyWith(
                          color: colors.textOnAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The card's image block — a SQUARE the full height of the card, flush to
/// its leading edge, filled edge to edge by the photo.
///
/// The core-cached local file when one has synced, else the item's monogram
/// over a quiet wash of the category's accent. LOCAL-ONLY (the core downloads
/// and caches during `refresh_catalog`; this never fetches), and a decode
/// failure falls back to the monogram rather than showing a broken-image
/// glyph to a customer.
class _TileThumb extends StatelessWidget {
  const _TileThumb({required this.item, required this.accent});

  final MenuItemView item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final path = item.localImagePath;
    return LayoutBuilder(
      builder: (context, c) {
        // Square on the card's own height, whatever the grid handed it.
        final side = c.maxHeight.isFinite ? c.maxHeight : _fallbackSide;
        final fallback = Center(
          child: Text(
            monogram(item.name),
            style: MadarType.h1.copyWith(
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        );
        return SizedBox(
          width: side,
          child: ColoredBox(
            color: accent.withValues(alpha: 0.14),
            child: path == null
                ? fallback
                : Image(
                    image: ResizeImage(
                      FileImage(File(path)),
                      width: (side * MediaQuery.devicePixelRatioOf(context))
                          .round(),
                    ),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => fallback,
                  ),
          ),
        );
      },
    );
  }

  /// Only reached under an unbounded height, which the grid never gives.
  static const double _fallbackSide = 88;
}

/// A combo's tile: name, fixed price, and a "+ Configure" face, because a
/// bundle is never one tap.
class _BundleTile extends StatelessWidget {
  const _BundleTile({
    required this.bundle,
    required this.currency,
    required this.label,
    required this.onTap,
  });

  final BundleView bundle;
  final String currency;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.all(Space.md),
        decoration: BoxDecoration(
          color: colors.accentBg,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: colors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                bundle.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MadarType.title.copyWith(color: colors.textPrimary),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '+ $label',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.bodySm.copyWith(color: colors.accent),
                  ),
                ),
                MoneyText(bundle.priceMinor, currency: currency),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
