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

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_order/src/bundle_detail_sheet.dart';
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

/// Tile geometry: compact enough for a real menu on an iPad (six across at
/// 1194 minus the rail and the cart), still a thumb target on a phone.
const double _kTileMaxWidth = 168;
const double _kTileHeight = 108;

/// Sell.
class SellScreen extends ConsumerStatefulWidget {
  const SellScreen({super.key});

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
      if (mounted) unawaited(_notifier.ensureInit());
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

  Future<void> _onTileTap(MenuItemView item) async {
    if (await _itemNeedsSheet(item)) {
      await _openItemSheet(item);
      return;
    }
    await _notifier.addToCart(item);
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

  /// Parked carts — counter only. Tap one to pick it up (the current cart
  /// parks first), × to discard it.
  Future<void> _openParked() async {
    final bridge = ref.read(bridgeProvider);
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final drafts = sheetRef.watch(orderProvider.select((s) => s.drafts));
          final currency = sheetRef.watch(
            orderProvider.select((s) => s.currency),
          );
          final colors = context.madarColors;
          return Padding(
            padding: const EdgeInsetsDirectional.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  orderWord(bridge, 'sell.parked'),
                  style: MadarType.h2.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: Space.lg),
                if (drafts.isEmpty)
                  Text(
                    orderWord(bridge, 'sell.parked_empty'),
                    style: MadarType.body.copyWith(color: colors.textMuted),
                  )
                else
                  Flexible(
                    child: MadarCard(
                      flush: true,
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: drafts.length,
                        separatorBuilder: (_, _) =>
                            const MadarHairline(light: true),
                        itemBuilder: (context, i) {
                          final d = drafts[i];
                          final name = d.name.trim();
                          return MadarRow(
                            title: name.isEmpty
                                ? formatHHMM(d.createdAt)
                                : name,
                            subtitle:
                                '${d.itemCount} ${bridge.tr(key: 'waiter.items')}',
                            glyph: MadarGlyph.bag,
                            value: MoneyText(d.totalMinor, currency: currency),
                            trailing: MadarGlyphTile(
                              glyph: MadarGlyph.close,
                              semanticLabel: bridge.tr(key: 'sync.discard'),
                              onTap: () =>
                                  unawaited(_notifier.discardDraft(d.id)),
                            ),
                            chevron: false,
                            onTap: () {
                              Navigator.of(sheetContext).maybePop();
                              unawaited(_notifier.switchToHeldOrder(d.id));
                            },
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
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
        if (counter)
          MadarChip(
            label: orderWord(bridge, 'sell.parked'),
            glyph: MadarGlyph.bag,
            count: drafts == 0 ? null : drafts,
            onTap: () => unawaited(_openParked()),
          ),
      ],
      below: _searching
          ? MadarField(
              controller: _search,
              placeholder: bridge.tr(key: 'order.search'),
              glyph: MadarGlyph.search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            )
          : _CategoryChips(
              selected: _categoryId,
              onSelect: (id) => setState(() => _categoryId = id),
            ),
    );

    final catalog = _Catalog(
      categoryId: _categoryId,
      query: _search.text,
      onItemTap: (item) => unawaited(_onTileTap(item)),
      onItemLongPress: (item) => unawaited(_openItemSheet(item)),
      onBundleTap: (b) => unawaited(_openBundle(b)),
    );

    return Scaffold(
      backgroundColor: colors.bg,
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
    final bridge = ref.watch(bridgeProvider);
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
  final ValueChanged<MenuItemView> onItemTap;
  final ValueChanged<MenuItemView> onItemLongPress;
  final ValueChanged<BundleView> onBundleTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final notifier = ref.read(orderProvider.notifier);
    final loading = ref.watch(orderProvider.select((s) => s.isLoadingCatalog));
    final currency = ref.watch(orderProvider.select((s) => s.currency));
    final layout = MadarLayout.of(context);
    final padding = EdgeInsetsDirectional.all(layout.gutter);
    const delegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: _kTileMaxWidth,
      mainAxisExtent: _kTileHeight,
      mainAxisSpacing: Space.md,
      crossAxisSpacing: Space.md,
    );

    if (loading) return const SkeletonList();

    if (categoryId == _kCombos) {
      final bundles = ref.watch(orderProvider.select((s) => s.bundles));
      return GridView.builder(
        key: const PageStorageKey('sell-combos'),
        padding: padding,
        gridDelegate: delegate,
        itemCount: bundles.length,
        itemBuilder: (context, i) => _BundleTile(
          bundle: bundles[i],
          currency: currency,
          label: bridge.tr(key: 'order.configure'),
          onTap: () => onBundleTap(bundles[i]),
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
    return GridView.builder(
      key: PageStorageKey('sell-${categoryId ?? 'all'}'),
      padding: padding,
      gridDelegate: delegate,
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
          onTap: () => onItemTap(item),
          onLongPress: () => onItemLongPress(item),
        );
      },
    );
  }
}

/// One item tile: flat surface, 16px corners, the name and a mono price, a
/// teal count disc once the item is in the cart. A photo when the core has
/// one on disk; otherwise a quiet wash in the category's colour.
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
  final VoidCallback onTap;
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
          onTap: onTap,
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
                // The category's colour as a flat band across the top — the
                // eye finds the hot drinks before it reads a word.
                PositionedDirectional(
                  top: 0,
                  start: 0,
                  end: 0,
                  height: 6,
                  child: ColoredBox(color: accent.withValues(alpha: 0.9)),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    Space.md,
                    Space.lg,
                    Space.md,
                    Space.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: MadarType.title.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      MoneyText(
                        item.basePriceMinor,
                        currency: currency,
                        color: colors.textPrimary,
                      ),
                    ],
                  ),
                ),
                if (inCart > 0)
                  PositionedDirectional(
                    top: Space.md,
                    end: Space.md,
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
