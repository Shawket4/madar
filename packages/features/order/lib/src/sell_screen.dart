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
//
// FAST MODE (a per-till setting, `sellLayoutProvider`, tablets only): the
// cart comes first and the menu sits at the end, in a panel that hosts the
// screen's sheets (`MadarPanelHost`). An item's choices, a combo, Charge, a
// note: each replaces the menu in place and gives it back when it closes.
// The sheets are the same widgets with the same rules; only where they are
// drawn changes.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_order/src/cart_anchor.dart';
import 'package:feature_order/src/combo_sheet.dart';
import 'package:feature_order/src/floor_list.dart' show groupBillByRound;
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/sell_cart.dart';
import 'package:feature_order/src/table_clear_prompt.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:feature_order/src/words.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:feature_till/feature_till.dart' show TillSyncStrip;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Tile geometry — a VERTICAL card: the picture on top, the name and the
/// price under it, full width.
///
/// The card it replaces was horizontal: a square photo the card's height,
/// flush to the leading edge, and the text squeezed into what was left. On an
/// iPad column the photo took ~60% of the card, so "Affogato" broke as
/// "Affogat/o" and the price was crammed beside it. Stacked, the name gets
/// the card's whole width, like the pre-rebuild catalog card and the natives.
///
/// A WIDTH BAND, never a fixed size: the grid picks a column count from the
/// width it is actually handed ([sellGridColumns]) and the height follows the
/// width and the text scale ([sellTileExtent]).
const double kSellTileMinWidth = 150;
const double kSellTileMaxWidth = 210;

/// The compact band — a catalog column narrower than
/// [Responsive.sellGridCompact] on a tablet (the 10.2" iPad in portrait with
/// the cart beside it): three columns of smaller tiles rather than two
/// oversized ones, and every tile still well past a 44pt target.
const double kSellTileMinWidthCompact = 112;
const double kSellTileMaxWidthCompact = 160;

/// The gap between tiles.
const double kSellTileGap = Space.md;

/// The picture's height as a fraction of the card's width (4:3).
const double _kTileImageAspect = 0.75;

/// The text block under the picture, before text scaling: top/bottom padding,
/// two lines of name, the gap, one line of price.
const double _kTileTextPad = Space.sm + 2;
const double _kTileNameSize = 15;
const double _kTileNameLineHeight = 1.25;
const double _kTilePriceSize = 16;
const double _kTileTextBlock =
    _kTileTextPad * 2 +
    _kTileNameSize * _kTileNameLineHeight * 2 +
    Space.xs +
    _kTilePriceSize * 1.3;

/// Columns for a catalog [usable] pixels wide (gutters already removed): as
/// many as fit at the minimum, then one more for as long as the tiles would
/// otherwise grow past the maximum. Both ends matter — a 13" of four 300px
/// cards looks as wrong as a phone of five 70px ones.
///
/// [compact] picks the compact band ([kSellTileMinWidthCompact]) — the
/// caller says so for a tablet's narrow column, never for a phone, whose
/// two wide tiles are the right shape for a thumb.
int sellGridColumns(double usable, {bool compact = false}) {
  final minWidth = compact ? kSellTileMinWidthCompact : kSellTileMinWidth;
  final maxWidth = compact ? kSellTileMaxWidthCompact : kSellTileMaxWidth;
  var columns = math.max(1, (usable / minWidth).floor());
  double widthAt(int n) => (usable - kSellTileGap * (n - 1)) / n;
  while (widthAt(columns) > maxWidth) {
    columns += 1;
  }
  return columns;
}

/// A tile's height for a tile [width] wide under [textScaler].
double sellTileExtent(double width, TextScaler textScaler) =>
    width * _kTileImageAspect +
    textScaler.scale(_kTileTextBlock) +
    // The selected state's 2px border, so choosing a tile never reflows it.
    2;

/// The SELL TAB — the counter's takeaway cart, and only that cart.
///
/// It reads `cartProvider(null)` and nothing else, so a launch, a sign-in, a
/// tab change or a table screen standing on another tab can never make it
/// show a table. [pushed] is the waiter's "+ New bill" at a floorless branch,
/// which opens the same counter cart as a page of its own.
class TakeawaySellScreen extends StatelessWidget {
  const TakeawaySellScreen({this.pushed = false, super.key});

  /// Pushed as a page (pays the top inset) rather than a tab body.
  final bool pushed;

  @override
  Widget build(BuildContext context) =>
      OrderScreen(tableId: null, pushed: pushed);
}

/// Taking an order FOR ONE TABLE — a pushed page with its own back, bound to
/// `cartProvider(tableId)` for its whole life. Same menu, different cart.
class TableOrderScreen extends StatelessWidget {
  const TableOrderScreen({required this.tableId, super.key});

  final String tableId;

  @override
  Widget build(BuildContext context) =>
      OrderScreen(tableId: tableId, pushed: true);
}

/// The order screen over ONE cart context: the shared [MenuGrid] beside (or
/// above) that context's own cart. Use [TakeawaySellScreen] or
/// [TableOrderScreen].
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({required this.tableId, required this.pushed, super.key});

  /// The context — null = takeaway. Fixed for the life of the screen.
  final String? tableId;

  /// Pushed as a page rather than mounted as a tab body.
  final bool pushed;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  final _search = TextEditingController();
  bool _searching = false;

  /// Whether an item needs its sheet, remembered per item. The answer needs
  /// the item's modifier groups from the core, which is a bridge call — once
  /// per item per menu read is plenty; per tap would put a round-trip
  /// between the finger and the cart. Cleared whenever the catalogue changes,
  /// or a synced required pick would keep being skipped by a quick add.
  final _needsSheet = <String, bool>{};

  /// This screen's cart landing pads — its own, so a table's screen never
  /// shares a GlobalKey with the Sell tab mounted underneath it.
  final _anchors = CartAnchors();

  // ── fast mode ──────────────────────────────────────────────────────────────

  /// The menu panel's navigator (Fast mode): the menu is its first page,
  /// and the sheets this screen opens are pushed over it, in place.
  final _panelNav = GlobalKey<NavigatorState>();

  /// A context UNDER the panel host: sheets opened from here land in the
  /// panel. This State's own context sits above the host its build provides.
  final GlobalKey _hostKey = GlobalKey();

  /// Charge is up in the panel. The cart beside it takes no taps meanwhile:
  /// the modal it replaces kept the cart out of reach under its scrim, and a
  /// line changed while money is being taken would charge the old cart.
  bool _chargingInPanel = false;

  /// Whether this screen sells in Fast mode right now. Kept while a
  /// charge is up in the panel, so switching the setting mid-charge cannot
  /// tear the panel (and the charge in it) away.
  bool _fastNow(BuildContext context) =>
      _chargingInPanel ||
      (MadarLayout.of(context).isTablet &&
          ref.watch(sellLayoutProvider) == SellLayout.fast);

  bool get _fast =>
      _chargingInPanel ||
      (MadarLayout.of(context).isTablet &&
          ref.read(sellLayoutProvider) == SellLayout.fast);

  /// Where this screen's sheets open: the panel in Fast mode, the
  /// window otherwise.
  BuildContext get _sheetContext =>
      _fast ? (_hostKey.currentContext ?? context) : context;

  String? get _tableId => widget.tableId;

  OrderNotifier get _notifier => ref.read(orderProvider.notifier);
  CartNotifier get _cart => ref.read(cartProvider(_tableId).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_notifier.ensureInit());
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  // ── quick-add ──────────────────────────────────────────────────────────────

  /// The rule: a sheet iff the item has a modifier group that is required
  /// (or wants at least one pick). Everything else is one tap — an item with
  /// sizes too: it lands at its base size ([baseSizeLabel]), and a tap on the
  /// line changes it (owner decision, 2026-09-26).
  ///
  /// Null when the options could not be read: nothing is added then (the
  /// notifier says why), and nothing is remembered, so the next tap asks
  /// again. A failed read used to count as "no options" and put an item with
  /// a required pick straight into the cart.
  Future<bool?> _itemNeedsSheet(MenuItemView item) async {
    final known = _needsSheet[item.id];
    if (known != null) return known;
    final groups = await _notifier.tryLoadItemModifierGroups(item.id);
    if (groups == null) return null;
    final needs = groups.any((g) => g.isRequired || g.minSelections > 0);
    _needsSheet[item.id] = needs;
    return needs;
  }

  /// A tile tap, a line edit or Charge already on its way. A second tap
  /// while one is opening used to stack two sheets (or two drawers).
  bool _opening = false;

  /// The tap holding [_opening] has outlasted a double tap.
  bool _openingSlow = false;
  Timer? _slowTimer;

  /// A second tap this soon after the first is a double tap: dropped without
  /// a word, the first one's result is about to show. Later than this, the
  /// teller is waiting on something slow (a round on its way to the kitchen)
  /// and is TOLD so — a tap is never answered with nothing.
  static const _doubleTap = Duration(milliseconds: 1500);

  /// Run [op] for one tap, once at a time. Whatever goes wrong in it is said
  /// on the toast — the core's sentence for a refusal, else [failed] — and
  /// never dies quietly in an unawaited future (T2 B3: a tap on the menu
  /// that did nothing at all).
  Future<void> _once(
    Future<void> Function() op, {
    String Function()? failed,
  }) async {
    if (_opening) {
      if (_openingSlow) {
        _notifier.showToast(
          ref.read(bridgeProvider).tr(key: 'order.still_busy'),
          icon: 'clock',
        );
      }
      return;
    }
    _opening = true;
    _slowTimer = Timer(_doubleTap, () => _openingSlow = true);
    try {
      await _saying(op, failed: failed);
    } finally {
      _slowTimer?.cancel();
      _slowTimer = null;
      _openingSlow = false;
      if (mounted) _opening = false;
    }
  }

  /// [op], with any failure said on the toast rather than lost: a refusal in
  /// the core's words, anything else as [failed] (or the generic sentence).
  /// The unexpected ones are still reported, as an uncaught error would be.
  Future<void> _saying(
    Future<void> Function() op, {
    String Function()? failed,
  }) async {
    try {
      await op();
    } on MadarError catch (e) {
      if (mounted) {
        _notifier.showToast(
          ref.read(bridgeProvider).humanMessage(e),
          tone: ChipTone.danger,
          icon: 'xmark.circle',
        );
      }
    } on Object catch (e, st) {
      if (mounted) {
        _notifier.showToast(
          failed?.call() ?? ref.read(bridgeProvider).tr(key: 'err.generic'),
          tone: ChipTone.danger,
          icon: 'xmark.circle',
        );
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'feature_order',
          context: ErrorDescription('while answering a tap on the Sell screen'),
        ),
      );
    }
  }

  /// "Couldn't add Latte. Try again." / "Couldn't open Latte. Try again."
  String _failedOn(String key, String name) =>
      ref.read(bridgeProvider).tr(key: key).replaceAll('{item}', name);

  Future<void> _onTileTap(MenuItemView item, Offset origin) =>
      _once(failed: () => _failedOn('order.add_failed', item.name), () async {
        // A combo always opens its sheet: its slots are the choice to make.
        if (item.kind == 'combo') {
          await _openComboSheet(item.id);
          return;
        }
        final needs = await _itemNeedsSheet(item);
        if (needs == null || !mounted) return;
        if (needs) {
          await _openItemSheet(item);
          return;
        }
        await _quickAdd(item);
        if (!mounted) return;
        _flyToCart(origin);
      });

  /// A long press: the item's sheet, whatever its options — its failures
  /// said like a tap's.
  Future<void> _onTileLongPress(MenuItemView item) => _saying(
    failed: () => _failedOn('order.add_failed', item.name),
    () => _openItemSheet(item),
  );

  /// The quick-add path skips the sheet, but a recipe's base modifier — full
  /// -fat milk under a latte — must still land on the line. `addConfigured`
  /// is what carries an addon selection, so an item with a default rides the
  /// exact same commit path a manual pick gets in [ItemDetailSheet]; plain
  /// items keep the cheaper `add`.
  Future<void> _quickAdd(MenuItemView item) {
    final milk = item.defaultMilkAddonId;
    final size = baseSizeLabel(item);
    if (milk == null && size == null) return _cart.add(item);
    return _cart.addConfigured(
      itemId: item.id,
      addons: [if (milk != null) AddonSelection(addonItemId: milk, qty: 1)],
      optionalIds: const [],
      qty: 1,
      sizeLabel: size,
    );
  }

  /// The dot arcing into THIS screen's cart anchor from the tapped tile.
  void _flyToCart(Offset origin) {
    // `_anchors` directly, NOT `CartAnchors.maybeOf(context)`: this State's
    // context sits ABOVE the `CartAnchorScope` its own build() provides.
    unawaited(_anchors.fly(origin));
  }

  Future<void> _openItemSheet(MenuItemView item, {CartLineView? edit}) async {
    if (item.kind == 'combo') {
      await _openComboSheet(item.id);
      return;
    }
    final addons = await _notifier.loadItemAddons(item.id);
    final groups = await _notifier.loadItemModifierGroups(item.id);
    if (!mounted) return;
    // The sheet closes with a combo draft when the teller chose "Make it a
    // meal": the combo sheet takes over from there, on that draft.
    final pending = showMadarSheet<Object?>(
      _sheetContext,
      size: SheetSize.hug,
      builder: (_) => CartAnchorScope(
        anchors: _anchors,
        child: ItemDetailSheet(
          item: item,
          addons: addons,
          groups: groups,
          editLine: edit,
          tableId: _tableId,
        ),
      ),
    );
    // In Fast mode the choices stay up beside a cart that is still
    // in reach: the tap is done once they are shown, so the next tile or
    // line tap is taken (and replaces them) instead of waiting behind them.
    if (_fast) {
      unawaited(pending.then(_afterItemSheet));
      return;
    }
    await _afterItemSheet(await pending);
  }

  Future<void> _afterItemSheet(Object? result) async {
    if (result is ComboDraft && mounted) {
      await _openComboSheet(result.comboId, draft: result);
    }
  }

  /// The combo sheet: a fresh combo, or [draft] (a combo line to edit, or a
  /// meal made from an item).
  Future<void> _openComboSheet(String comboId, {ComboDraft? draft}) async {
    final shown = showComboSheet(
      _sheetContext,
      ref,
      comboId: comboId,
      tableId: _tableId,
      draft: draft,
      anchors: _anchors,
    );
    // Fast mode: shown in the panel is done (see [_openItemSheet]).
    if (_fast) {
      unawaited(shown);
      return;
    }
    await shown;
  }

  Future<void> _editLine(CartLineView line) =>
      _once(failed: () => _failedOn('order.edit_failed', line.name), () async {
        if (line.kind == 'combo') {
          // A refusal (the line is gone) is the core's sentence, on the toast.
          final draft = await ref
              .read(bridgeProvider)
              .cartComboDraft(tableId: _tableId, lineKey: line.key);
          if (!mounted) return;
          await _openComboSheet(line.itemId, draft: draft);
          return;
        }
        final item = ref.read(orderProvider).menuItemById(line.itemId);
        if (item == null) {
          // Off the menu since it was added: say so, never a dead tap.
          _notifier.showToast(
            _failedOn('order.edit_failed', line.name),
            tone: ChipTone.warning,
            icon: 'exclamationmark.triangle',
          );
          return;
        }
        await _openItemSheet(item, edit: line);
      });

  // ── terminal ───────────────────────────────────────────────────────────────

  /// Charge this cart through the tender drawer, or fire its round — once
  /// per tap: a double tap opened two drawers over one cart.
  Future<void> _terminal() => _once(_terminalOnce);

  Future<void> _terminalOnce() async {
    final state = ref.read(orderProvider);
    final cart = ref.read(cartProvider(_tableId));
    final cta = sellCtaFor(
      state,
      cart,
      ref.read(bridgeProvider),
      tillOpen: ref.read(shellProvider).tillOpen,
    );
    if (!cta.enabled) return;
    if (cta.sendsToKitchen) {
      // A round on this cart's bill, or its first round. The covers picked
      // at seating and the booking ride along from the cart's own meta.
      await _cart.fireOrAddRound();
      return;
    }
    // Captured BEFORE the drawer: settling clears the cart (and with it the
    // draft identity) — this is the parked order the sale completes.
    final settledDraftId = cart.draftId;
    final inPanel = _fast;
    if (inPanel) setState(() => _chargingInPanel = true);
    final ChargeOutcome? outcome;
    try {
      outcome = await showCharge(
        _sheetContext,
        ChargeTarget.cart(
          tableId: _tableId,
          customerId: ref.read(cartProvider(_tableId)).meta.customerId,
        ),
        // "Not printed — no printer ›" on the Done card lands on the printer
        // sheet, not on a dead end.
        onPrinterSettings: () => unawaited(showPrinterSheet(context)),
      );
    } finally {
      if (inPanel && mounted) setState(() => _chargingInPanel = false);
    }
    if (!mounted) return;
    if (outcome != null) {
      await _cart.onOrderSettled(settledDraftId);
      return;
    }
    // Closed without taking money: the cart is as it was, but the drawer
    // may have applied a discount to it on the way.
    await _cart.load();
  }

  Future<void> _openCartSheet() async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      // The cart paints the page ground; the handle strip must match it.
      tone: MadarSheetTone.ground,
      builder: (sheetContext) => CartAnchorScope(
        anchors: _anchors,
        child: SellCart(
          tableId: _tableId,
          onTerminal: () {
            // Not maybePop: Charge is pushed in this same tick, and maybePop
            // drops its pop when that happens (the cart sheet stayed up
            // under Charge). See MadarSheet.close.
            MadarSheet.close<void>(sheetContext);
            unawaited(_terminal());
          },
          onEditLine: (line) => unawaited(_editLine(line)),
          onClose: () => Navigator.of(sheetContext).maybePop(),
        ),
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    listenForTableClear(context, ref);
    // Back to where the round came from once it is in — only when this
    // screen was PUSHED (from a table, from a bill). As a tab it stays.
    ref
      ..listen(cartProvider(_tableId).select((c) => c.firedSeq), (prev, next) {
        if (prev == null || next == prev || !widget.pushed) return;
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      })
      ..listen(ticketTickProvider, (_, _) {
        unawaited(_notifier.loadOpenTickets());
      })
      ..listen(connectivityPulseProvider, (_, _) {
        unawaited(_notifier.syncFromStatus());
      })
      // A sync (manual or a background pull) changed the catalogue: re-read the
      // menu so paths the sync just cached (step animations, photos) reach the
      // item sheet, and forget which items needed a sheet — a synced required
      // pick (say, a bread) must open the sheet on the very next tap.
      ..listen(catalogTickProvider, (_, _) {
        _needsSheet.clear();
        unawaited(_notifier.loadCatalog());
      })
      // Any new menu read (sync, language, re-init) invalidates the answers too.
      ..listen(orderProvider.select((s) => s.menuItems), (_, _) {
        _needsSheet.clear();
      })
      ..listen(localeProvider.select((s) => s.locale), (_, _) {
        unawaited(_notifier.loadCatalog());
      });

    final layout = MadarLayout.of(context);
    final fast = _fastNow(context);
    final order = ref.watch(orderProvider);
    final cart = ref.watch(cartProvider(_tableId));
    final header = orderHeaderFor(
      bridge,
      order,
      cart,
      dineIn: ref.watch(dineInProvider(_tableId)),
    );
    final counter =
        !order.isWaiter && _tableId == null && cartTicket(order, cart) == null;
    final drafts = order.drafts.length;

    final headerActions = <Widget>[
      MadarGlyphTile(
        glyph: _searching ? MadarGlyph.close : MadarGlyph.search,
        semanticLabel: bridge.tr(key: 'order.search'),
        onTap: () => setState(() {
          _searching = !_searching;
          if (!_searching) _search.clear();
        }),
      ),
      // Narrow hides the cart (and its parked strip) behind a sheet, so this
      // is that sheet's door — only with something parked.
      if (counter && !layout.isTablet && drafts > 0)
        MadarButton(
          label: '$drafts',
          tooltip: orderWord(bridge, 'sell.parked'),
          glyph: MadarGlyph.bag,
          variant: MadarButtonVariant.secondary,
          size: MadarButtonSize.compact,
          onTap: () => unawaited(_openCartSheet()),
        ),
    ];
    final headerBelow = _searching
        ? MadarField(
            controller: _search,
            placeholder: bridge.tr(key: 'order.search'),
            kind: MadarFieldKind.search,
            glyph: MadarGlyph.search,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          )
        // The sync opening a till started, for its first minute: one line,
        // never in the way of selling.
        : const TillSyncStrip(headerOnly: true);

    final catalog = MenuGrid(
      tableId: _tableId,
      query: _searching ? _search.text : null,
      onItemTap: (item, origin) => unawaited(_onTileTap(item, origin)),
      onItemLongPress: (item) => unawaited(_onTileLongPress(item)),
      categoryBoxes: _fastNow(context),
    );

    // As a tab body the shell's top bar above it already paid the top inset;
    // pushed it is the topmost thing and pays the inset itself.
    return CartAnchorScope(
      anchors: _anchors,
      // The flight's own overlay, clipped to this screen: the dot never
      // crosses the shell's top bar, rail or tab bar.
      child: CartFlightLayer(
        overlayKey: _anchors.flightOverlay,
        child: MadarPageScaffold(
          safeTop: widget.pushed,
          width: MadarContentWidth.full,
          bodyInset: false,
          title: header.title,
          subtitle: header.subtitle,
          actions: headerActions,
          below: headerBelow,
          body: SafeArea(
            top: false,
            child: fast
                ? _FastSellBody(
                    panelNav: _panelNav,
                    hostKey: _hostKey,
                    cartWidth: MadarRoom.of(context).cartColumnWidth,
                    cartLocked: _chargingInPanel,
                    backLabel: orderWord(ref.bridge, 'sell.back_to_menu'),
                    catalog: catalog,
                    cart: SellCart(
                      tableId: _tableId,
                      onTerminal: () => unawaited(_terminal()),
                      onEditLine: (line) => unawaited(_editLine(line)),
                      editOnSelect: true,
                    ),
                  )
                : layout.isTablet
                ? Row(
                    children: [
                      Expanded(child: catalog),
                      const VerticalDivider(width: 1, thickness: 1),
                      SizedBox(
                        // 340 with the width to spare, 300 on a portrait or
                        // small tablet — the catalog keeps three columns.
                        width: MadarRoom.of(context).cartColumnWidth,
                        child: SellCart(
                          tableId: _tableId,
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
                        tableId: _tableId,
                        onOpen: () => unawaited(_openCartSheet()),
                        onTerminal: () => unawaited(_terminal()),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Fast mode's body: the cart on the start edge, then the menu in a
/// panel that hosts this screen's sheets in place ([MadarPanelHost]). The
/// menu is the panel's first page; whatever opens over it (an item's
/// choices, a combo, Charge, a note from the cart) is pushed on top and
/// popped back to it.
class _FastSellBody extends StatelessWidget {
  const _FastSellBody({
    required this.panelNav,
    required this.hostKey,
    required this.cartWidth,
    required this.cartLocked,
    required this.catalog,
    required this.cart,
    required this.backLabel,
  });

  final GlobalKey<NavigatorState> panelNav;

  /// The bar over whatever opens in the panel ("Back to menu").
  final String backLabel;

  /// Keys a context under the host, for the screen's own sheet calls.
  final GlobalKey hostKey;
  final double cartWidth;

  /// Charge is up in the panel: the cart stays in view but takes no taps.
  final bool cartLocked;
  final Widget catalog;
  final Widget cart;

  @override
  Widget build(BuildContext context) {
    return MadarPanelHost(
      navigatorKey: panelNav,
      backLabel: backLabel,
      child: Row(
        key: hostKey,
        children: [
          SizedBox(
            width: cartWidth,
            child: _LockableCart(locked: cartLocked, cart: cart),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: ClipRect(
              // The system back closes what the panel shows before it ever
              // leaves the screen: the panel's navigator is nested, and the
              // root one would otherwise take the gesture.
              child: NavigatorPopHandler(
                onPopWithResult: (_) => panelNav.currentState?.maybePop(),
                child: Navigator(
                  key: panelNav,
                  // A page, not an initial route: the menu rebuilds with the
                  // screen (search, the cart's badges) under whatever is open.
                  pages: [
                    MaterialPage<void>(
                      key: const ValueKey('sell-menu'),
                      child: catalog,
                    ),
                  ],
                  onDidRemovePage: (_) {},
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The cart beside Charge: it stays in view (it is what is being charged)
/// but takes no taps, and SAYS so — a lock line on top and the lines dimmed.
/// A cart that only ignored taps looked live and swallowed them silently
/// (T2, LG4).
class _LockableCart extends ConsumerWidget {
  const _LockableCart({required this.locked, required this.cart});

  final bool locked;
  final Widget cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (locked)
          Semantics(
            liveRegion: true,
            child: Container(
              key: const ValueKey('cart-locked'),
              color: colors.surfaceAlt,
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              child: Row(
                spacing: Space.sm,
                children: [
                  MadarIcon(
                    'lock',
                    tint: colors.textSecondary,
                    size: IconSize.sm,
                  ),
                  Expanded(
                    child: Text(
                      ref.bridge.tr(key: 'sell.cart_locked'),
                      style: MadarType.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: AbsorbPointer(
            absorbing: locked,
            child: Opacity(opacity: locked ? 0.5 : 1, child: cart),
          ),
        ),
      ],
    );
  }
}

/// The page header over one cart: "Takeaway" at the counter; "T5 · 4 guests"
/// with the round under it for a table; "New bill · Sara" for a waiter's
/// table-less bill.
///
/// A counter cart says what the cart's toggle says: "Pickup" or "Dine in".
({String title, String? subtitle}) orderHeaderFor(
  MadarBridge bridge,
  OrderState s,
  CartState c, {
  bool dineIn = false,
}) {
  final ticket = cartTicket(s, c);
  final label = cartTableLabel(s, c);
  final round = ticket == null ? 1 : groupBillByRound(ticket.lines).length + 1;
  final roundWord = '${bridge.tr(key: 'tables.round')} $round';
  if (label != null) {
    final guests = cartGuests(s, c);
    return (
      title: guests == null
          ? label
          : '$label · $guests ${bridge.tr(key: 'tables.guests')}',
      subtitle: roundWord,
    );
  }
  if (ticket != null) {
    final who = ticket.customerName ?? ticket.ticketRef ?? '';
    return (title: who, subtitle: roundWord);
  }
  if (s.isWaiter) {
    final name = c.name;
    return (
      title: name == null
          ? orderWord(bridge, 'bills.new_bill')
          : '${orderWord(bridge, 'bills.new_bill')} · $name',
      subtitle: null,
    );
  }
  return (
    title: dineIn
        ? bridge.tr(key: 'charge.dine_in')
        : orderWord(bridge, 'sell.takeaway'),
    subtitle: null,
  );
}

/// The menu both order screens share: category chips over the tile grid,
/// filtered by the chip and the search. The in-cart badges count [tableId]'s
/// cart — the screen's own, never another's.
class MenuGrid extends ConsumerStatefulWidget {
  const MenuGrid({
    required this.tableId,
    required this.onItemTap,
    required this.onItemLongPress,
    this.query,
    this.categoryBoxes = false,
    super.key,
  });

  final String? tableId;

  /// Fast mode: the categories as whole boxes that open into their items,
  /// with a back bar over the items, instead of the chip strip over every
  /// item. Search still reaches every item from either.
  final bool categoryBoxes;

  /// The search text while searching (null = not searching: chips shown).
  final String? query;
  final void Function(MenuItemView item, Offset origin) onItemTap;
  final ValueChanged<MenuItemView> onItemLongPress;

  @override
  ConsumerState<MenuGrid> createState() => _MenuGridState();
}

class _MenuGridState extends ConsumerState<MenuGrid> {
  String? _categoryId;

  @override
  Widget build(BuildContext context) {
    final layout = MadarLayout.of(context);
    final searching = widget.query != null;
    if (widget.categoryBoxes && !searching) {
      final open = _categoryId;
      if (open == null) {
        return _CategoryBoxes(onOpen: (id) => setState(() => _categoryId = id));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CategoryBar(
            categoryId: open,
            onBack: () => setState(() => _categoryId = null),
          ),
          const MadarHairline(light: true),
          Expanded(
            child: _Catalog(
              tableId: widget.tableId,
              categoryId: open,
              query: '',
              onItemTap: widget.onItemTap,
              onItemLongPress: widget.onItemLongPress,
            ),
          ),
        ],
      );
    }
    // The strip belongs to the catalog's width, not the window's: hung under
    // the page header it ran across the divider and over the cart.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!searching)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              layout.gutter,
              Space.md,
              layout.gutter,
              0,
            ),
            child: _CategoryChips(
              selected: _categoryId,
              onSelect: (id) => setState(() => _categoryId = id),
            ),
          ),
        Expanded(
          child: _Catalog(
            tableId: widget.tableId,
            categoryId: searching ? null : _categoryId,
            query: widget.query ?? '',
            onItemTap: widget.onItemTap,
            onItemLongPress: widget.onItemLongPress,
          ),
        ),
      ],
    );
  }
}

/// All · the categories, as chips in a horizontal strip.
class _CategoryChips extends ConsumerWidget {
  const _CategoryChips({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final categories = ref.watch(orderProvider.select((s) => s.categories));
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
        ],
      ),
    );
  }
}

/// Fast mode's front page: every active category as a box — its monogram on
/// a wash of its colour, its name, how many items it holds. A tap opens it.
class _CategoryBoxes extends ConsumerWidget {
  const _CategoryBoxes({required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final notifier = ref.read(orderProvider.notifier);
    final layout = MadarLayout.of(context);
    final loading = ref.watch(orderProvider.select((s) => s.isLoadingCatalog));
    final categories = ref.watch(
      orderProvider.select(
        (s) => s.categories.where((c) => c.isActive).toList(growable: false),
      ),
    );
    final items = ref.watch(orderProvider.select((s) => s.menuItems));
    if (!loading && categories.isEmpty) {
      return EmptyState(
        icon: 'tray',
        title: bridge.tr(key: 'order.empty'),
        message: bridge.tr(key: 'order.empty_desc'),
        actionLabel: bridge.tr(key: 'order.sync_menu'),
        onAction: () => unawaited(notifier.refreshServerData()),
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final itemsWord = bridge.tr(key: 'order.items');
    return GridView.builder(
      key: const PageStorageKey('sell-category-boxes'),
      padding: EdgeInsetsDirectional.all(layout.gutter),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: kCategoryBoxMaxWidth,
        mainAxisExtent:
            kCategoryBoxHeight *
            MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4),
        mainAxisSpacing: kSellTileGap,
        crossAxisSpacing: kSellTileGap,
      ),
      itemCount: categories.length,
      itemBuilder: (context, i) {
        final c = categories[i];
        final count = items
            .where((it) => it.isActive && it.categoryId == c.id)
            .length;
        return _CategoryBox(
          key: ValueKey('category-box-${c.id}'),
          name: c.name,
          count: '$count $itemsWord',
          accent: hexColor(notifier.categoryStyle(c.name, dark: dark).accent),
          onTap: () => onOpen(c.id),
        );
      },
    );
  }
}

/// A category box's widest column and its height: three across a landscape
/// tablet's menu panel, two on a portrait one.
const double kCategoryBoxMaxWidth = 240;
const double kCategoryBoxHeight = 132;

class _CategoryBox extends StatelessWidget {
  const _CategoryBox({
    required this.name,
    required this.count,
    required this.accent,
    required this.onTap,
    super.key,
  });

  final String name;
  final String count;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final wash = accent.withValues(alpha: dark ? 0.2 : 0.14);
    return Semantics(
      button: true,
      label: '$name, $count',
      excludeSemantics: true,
      child: TactileScale(
        onTap: () {
          MadarHaptics.selection();
          onTap();
        },
        child: Container(
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsetsDirectional.all(Space.lg),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: colors.borderLight),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The soft disc bleeding off the top corner, the design's.
              PositionedDirectional(
                top: -64,
                end: -54,
                width: 140,
                height: 140,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: wash,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: wash,
                      borderRadius: BorderRadius.circular(Radii.control),
                    ),
                    child: Text(
                      monogram(name),
                      style: MadarType.title.copyWith(
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.title.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        count,
                        maxLines: 1,
                        style: MadarType.bodySm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Over an open category's items: back to the boxes, and which one is open.
class _CategoryBar extends ConsumerWidget {
  const _CategoryBar({required this.categoryId, required this.onBack});

  final String categoryId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final layout = MadarLayout.of(context);
    final name = ref.watch(
      orderProvider.select(
        (s) => s.categories.where((c) => c.id == categoryId).firstOrNull?.name,
      ),
    );
    final count = ref.watch(
      orderProvider.select(
        (s) => s.menuItems
            .where((i) => i.isActive && i.categoryId == categoryId)
            .length,
      ),
    );
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        layout.gutter,
        Space.sm,
        layout.gutter,
        Space.sm,
      ),
      child: Row(
        spacing: Space.md,
        children: [
          MadarGlyphTile(
            key: const ValueKey('category-back'),
            glyph: MadarGlyph.chevronBack,
            semanticLabel: orderWord(bridge, 'sell.back_to_categories'),
            onTap: onBack,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.h3.copyWith(color: colors.textPrimary),
                ),
                Text(
                  '$count ${bridge.tr(key: 'order.items')}',
                  style: MadarType.bodySm.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The tile grid, filtered by category and search.
class _Catalog extends ConsumerWidget {
  const _Catalog({
    required this.tableId,
    required this.categoryId,
    required this.query,
    required this.onItemTap,
    required this.onItemLongPress,
  });

  final String? tableId;
  final String? categoryId;
  final String query;

  /// `origin` is the tapped tile's on-screen center — the add-to-cart
  /// flight's launch point, so it has to come from whichever tile was
  /// actually hit, not a fixed spot on the screen.
  final void Function(MenuItemView item, Offset origin) onItemTap;
  final ValueChanged<MenuItemView> onItemLongPress;

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
    final textScaler = MediaQuery.textScalerOf(context);
    SliverGridDelegate delegateFor(double width) {
      final usable = width - layout.gutter * 2;
      final columns = sellGridColumns(
        usable,
        compact: layout.isTablet && usable < Responsive.sellGridCompact,
      );
      final tileWidth = (usable - kSellTileGap * (columns - 1)) / columns;
      return SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        // Height from the width AND the text scale: a larger type setting
        // grows the card instead of clipping its second line.
        mainAxisExtent: sellTileExtent(tileWidth, textScaler),
        mainAxisSpacing: kSellTileGap,
        crossAxisSpacing: kSellTileGap,
      );
    }

    // Card-shaped placeholders in the grid the cards will land in (the
    // pre-rebuild catalog's skeleton), not a list of rows.
    if (loading) {
      return LayoutBuilder(
        builder: (context, c) => SkeletonScope(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: padding,
            gridDelegate: delegateFor(c.maxWidth),
            itemCount: 12,
            itemBuilder: (context, _) => const SellTileSkeleton(),
          ),
        ),
      );
    }

    final items = ref.watch(orderProvider.select((s) => s.menuItems));
    final cartLines = ref.watch(cartProvider(tableId).select((c) => c.lines));
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
            badge: item.kind == 'combo' ? bridge.tr(key: 'combo.badge') : null,
            onTap: (origin) => onItemTap(item, origin),
            onLongPress: () => onItemLongPress(item),
          );
        },
      ),
    );
  }
}

/// One item tile — a vertical card: the photo (or the item's initials on a
/// wash of its category colour) across the top, the name in up to two lines
/// under it, the price in the body face with tabular figures beneath.
///
/// Tap is QUICK-ADD and reports the tile's centre for the add-to-cart
/// flight; long-press opens the item. Once the item is in the cart the card
/// takes an accent border and a count disc that pops as the count rises.
/// RTL-safe: everything is start/end, and the price is an LTR island.
class SellTile extends StatelessWidget {
  const SellTile({
    required this.item,
    required this.currency,
    required this.inCart,
    required this.accent,
    required this.onTap,
    required this.onLongPress,
    this.badge,
    super.key,
  });

  final MenuItemView item;
  final String currency;
  final int inCart;
  final Color accent;

  /// A word on the photo — "Combo" on a combo — already localized.
  final String? badge;

  /// Called with the tile's on-screen center, for the add-to-cart flight.
  final void Function(Offset origin) onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final selected = inCart > 0;
    return Semantics(
      button: true,
      selected: selected,
      label: [
        item.name,
        ?badge,
        Money.format(item.basePriceMinor, currency: currency),
      ].join(', '),
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
            // The card clips its photo to the rounded shape; the BORDER is a
            // foreground painted over the whole card, photo included. As a
            // background border it sat UNDER the edge-to-edge photo, so a
            // selected card showed its accent only around the text strip —
            // a thin, broken outline. No padding either way: selecting
            // never moves the picture.
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(
                color: selected ? colors.accent : colors.borderLight,
                width: selected ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _TileThumb(item: item, accent: accent),
                      if (badge case final b?)
                        PositionedDirectional(
                          top: Space.sm,
                          start: Space.sm,
                          end: selected ? Space.xxl : Space.sm,
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: MadarTag(label: b, tone: MadarTone.accent),
                          ),
                        ),
                      if (selected)
                        PositionedDirectional(
                          top: Space.sm,
                          end: Space.sm,
                          child: Nudge(
                            trigger: inCart,
                            child: _CountDisc(count: inCart),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: Space.md,
                    vertical: _kTileTextPad,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.xs,
                    children: [
                      SellTileName(item.name, color: colors.textPrimary),
                      _TilePrice(
                        minor: item.basePriceMinor,
                        currency: currency,
                      ),
                    ],
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

/// A tile's name: two lines at most, broken BETWEEN words only.
///
/// Flutter breaks a word that is wider than its line mid-word — that is how
/// "Americano" became "Americ/ano". So before laying out, the longest single
/// word is measured; if it cannot fit the line at the tile's size, the size
/// steps down until it does (never below a legible floor). Past the floor the
/// word keeps its letters together and ellipsizes instead of splitting.
/// The box is always two lines tall, so prices align across a row.
class SellTileName extends StatelessWidget {
  const SellTileName(this.name, {required this.color, super.key});

  final String name;
  final Color color;

  /// The smallest size a tile name steps down to.
  static const double minSize = 12;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final base = MadarType.title.copyWith(
      fontSize: _kTileNameSize,
      height: _kTileNameLineHeight,
      color: color,
    );
    return LayoutBuilder(
      builder: (context, c) {
        var style = base;
        final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
        double widest(TextStyle st) {
          var w = 0.0;
          for (final word in words) {
            final painter = TextPainter(
              text: TextSpan(text: word, style: st),
              textDirection: direction,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            w = math.max(w, painter.width);
            painter.dispose();
          }
          return w;
        }

        // A point of slack: a word measured a hair under the box still
        // broke mid-word on a 116-wide tile once the paragraph laid it out
        // ("Cappuccin/o"), so "fits" means fits with room to spare.
        final maxW = c.maxWidth - 1;
        var longest = maxW.isFinite ? widest(style) : 0.0;
        var wordFits = longest <= maxW;
        if (!wordFits) {
          final size = math.max(minSize, _kTileNameSize * maxW / longest);
          style = base.copyWith(fontSize: size.floorToDouble());
          longest = widest(style);
          wordFits = longest <= maxW;
        }
        final lineBox = scaler.scale(_kTileNameSize * _kTileNameLineHeight);
        return SizedBox(
          height: lineBox * 2,
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: Text(
              name,
              // A word that still cannot fit its line stays ONE line, whole
              // letters and an ellipsis — never broken across two.
              maxLines: wordFits ? 2 : 1,
              softWrap: wordFits,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        );
      },
    );
  }
}

/// The tile's price in the body face with tabular figures — the currency
/// code quiet and small, the amount bold — one LTR line that scales down
/// rather than wrapping "EGP" away from its own amount.
class _TilePrice extends StatelessWidget {
  const _TilePrice({required this.minor, required this.currency});

  final int minor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    // The one money display (SPEC §9): the same figure, label and Arabic
    // order as the cart, Charge and the Queue — it used to be a sans figure
    // with a small grey code here and mono everywhere else.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: MoneyText(
        minor,
        currency: currency,
        style: MadarType.money.copyWith(
          fontSize: _kTilePriceSize,
          fontWeight: FontWeight.w600,
        ),
        color: context.madarColors.textPrimary,
      ),
    );
  }
}

/// The in-cart count on a tile's picture: a teal pill with a surface ring so
/// it reads on a white product shot as well as on the wash.
class _CountDisc extends StatelessWidget {
  const _CountDisc({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      height: 26,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.sm),
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: colors.surface, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        textDirection: TextDirection.ltr,
        style: MadarType.title.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: colors.textOnAccent,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// The card's picture — the full width of the card, cover-fit, under the
/// card's rounded top corners.
///
/// The core-cached local file when one has synced, else the item's initials
/// over a quiet wash of the category's accent with a soft ring bleeding off
/// the corner (the pre-rebuild catalog card). LOCAL-ONLY (the core downloads
/// and caches during `refresh_catalog`; this never fetches), and a decode
/// failure falls back to the initials rather than showing a broken-image
/// glyph to a customer.
class _TileThumb extends StatelessWidget {
  const _TileThumb({required this.item, required this.accent});

  final MenuItemView item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final path = item.localImagePath;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth.isFinite ? c.maxWidth : _fallbackSide;
        final height = c.maxHeight.isFinite ? c.maxHeight : _fallbackSide;
        final ring = math.min(width, height) * 0.9;
        final fallback = Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [
                    accent.withValues(alpha: dark ? 0.22 : 0.12),
                    accent.withValues(alpha: dark ? 0.12 : 0.22),
                  ],
                ),
              ),
            ),
            PositionedDirectional(
              bottom: -ring * 0.35,
              end: -ring * 0.35,
              width: ring,
              height: ring,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.18),
                    width: 2,
                  ),
                ),
              ),
            ),
            Center(
              child: Text(
                monogram(item.name),
                textDirection: Directionality.of(context),
                style: MadarType.h1.copyWith(
                  fontSize: math.min(34, height * 0.34),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: accent.withValues(alpha: dark ? 0.8 : 0.7),
                ),
              ),
            ),
          ],
        );
        return ColoredBox(
          color: context.madarColors.surfaceAlt,
          child: path == null
              ? fallback
              : Image(
                  image: ResizeImage(
                    FileImage(File(path)),
                    width: (width * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                  ),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
        );
      },
    );
  }

  /// Only reached under unbounded constraints, which the grid never gives.
  static const double _fallbackSide = 120;
}

/// The loading stand-in for a [SellTile]: the same card, its picture and its
/// two text lines pulsing (under a [SkeletonScope], one shared pulse).
class SellTileSkeleton extends StatelessWidget {
  const SellTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final pulse = SkeletonScope.maybePulseOf(context);
    Widget hero = ColoredBox(
      color: colors.surfaceAlt,
      child: const SizedBox.expand(),
    );
    if (pulse != null) hero = FadeTransition(opacity: pulse, child: hero);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: colors.borderLight),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: hero),
            const Padding(
              padding: EdgeInsetsDirectional.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.sm,
                children: [
                  SkeletonBlock(width: 96),
                  SkeletonBlock(width: 56, height: 15),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
