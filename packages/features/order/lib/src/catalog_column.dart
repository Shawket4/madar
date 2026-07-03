import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Synthetic category id for the Combos tab (bundles aren't a real category).
const String kCombosCategory = '__combos__';

/// The catalog's selected category tab (null = All, [kCombosCategory] =
/// Combos). Auto-disposed so a fresh session starts back on All; the order
/// screen's GlobalKey keeps the column (and so this provider) alive across
/// wide↔narrow layout flips.
class CatalogTabNotifier extends AutoDisposeNotifier<String?> {
  @override
  String? build() => null;

  /// Not a setter — Notifier state writes are method-guarded.
  // ignore: use_setters_to_change_properties
  void select(String? id) => state = id;
}

/// The selected catalog category id.
final AutoDisposeNotifierProvider<CatalogTabNotifier, String?>
catalogTabProvider = NotifierProvider.autoDispose<CatalogTabNotifier, String?>(
  CatalogTabNotifier.new,
);

/// Catalog column — category tab strip on top, then search + the adaptive
/// item grid (or the combo grid when the Combos tab is active). Mirror of
/// the natives' CatalogColumn.
///
/// The selected category lives in [catalogTabProvider]; the search text
/// stays on a widget-local [TextEditingController], and the grid re-filters
/// through a [ValueListenableBuilder] on it — keeping keystrokes scoped to
/// the field + grid alone, never the cart panel or top-bar chrome.
class CatalogColumn extends ConsumerStatefulWidget {
  const CatalogColumn({
    required this.onItemTap,
    required this.onBundleTap,
    super.key,
  });

  final ValueChanged<MenuItemView> onItemTap;
  final ValueChanged<BundleView> onBundleTap;

  @override
  ConsumerState<CatalogColumn> createState() => _CatalogColumnState();
}

class _CatalogColumnState extends ConsumerState<CatalogColumn> {
  final _searchField = TextEditingController();

  @override
  void dispose() {
    _searchField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(bridgeProvider);
    final selectedCategory = ref.watch(catalogTabProvider);
    final isLoadingCatalog = ref.watch(
      orderProvider.select((s) => s.isLoadingCatalog),
    );
    // Watched HERE (not inside the ValueListenableBuilder closure, which
    // rebuilds outside this widget's build phase).
    final menuItems = ref.watch(orderProvider.select((s) => s.menuItems));
    final combos = selectedCategory == kCombosCategory;

    return Column(
      children: [
        _CategoryTabs(
          selected: selectedCategory,
          onSelect: (id) => ref.read(catalogTabProvider.notifier).select(id),
        ),
        if (combos)
          Expanded(child: _BundleGrid(onBundleTap: widget.onBundleTap))
        else ...[
          Padding(
            padding: const EdgeInsetsDirectional.all(Space.lg),
            // Rebuilds the field chrome (clear affordance) per keystroke.
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchField,
              builder: (context, search, _) => _SearchField(
                controller: _searchField,
                placeholder: bridge.tr(key: 'order.search'),
                value: search.text,
              ),
            ),
          ),
          Expanded(
            child: isLoadingCatalog
                ? const _CatalogSkeleton()
                : ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchField,
                    builder: (context, search, _) {
                      // One pass, no intermediate lists — the natives'
                      // memoized filter.
                      final query = search.text.trim().toLowerCase();
                      final visible = menuItems
                          .where(
                            (item) =>
                                item.isActive &&
                                (selectedCategory == null ||
                                    item.categoryId == selectedCategory) &&
                                (query.isEmpty ||
                                    item.name.toLowerCase().contains(query) ||
                                    (item.description?.toLowerCase().contains(
                                          query,
                                        ) ??
                                        false)),
                          )
                          .toList(growable: false);
                      return _ItemGridOrEmpty(
                        items: visible,
                        searching: query.isNotEmpty,
                        gridKey: selectedCategory,
                        onItemTap: widget.onItemTap,
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }
}

// ── Category tab strip ─────────────────────────────────────────────────────────

class _CategoryTabs extends ConsumerWidget {
  const _CategoryTabs({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bridge = ref.watch(bridgeProvider);
    final notifier = ref.read(orderProvider.notifier);
    final categories = ref.watch(orderProvider.select((s) => s.categories));
    final showCombos = ref.watch(
      orderProvider.select((s) => s.bundles.isNotEmpty),
    );
    return ColoredBox(
      color: colors.surface,
      child: Column(
        children: [
          SizedBox(
            height: kCategoryTabsHeight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Space.md,
              ),
              child: Row(
                children: [
                  _CategoryTab(
                    label: bridge.tr(key: 'order.all'),
                    icon: 'square.grid.2x2.fill',
                    active: selected == null,
                    onTap: () => onSelect(null),
                  ),
                  if (showCombos) ...[
                    const SizedBox(width: Space.lg),
                    _CategoryTab(
                      label: bridge.tr(key: 'order.combos'),
                      icon: 'square.stack.3d.up.fill',
                      active: selected == kCombosCategory,
                      onTap: () => onSelect(kCombosCategory),
                    ),
                  ],
                  for (final cat in categories.where((c) => c.isActive)) ...[
                    const SizedBox(width: Space.lg),
                    _CategoryTab(
                      label: cat.name,
                      icon: categoryIconName(
                        notifier.categoryStyle(cat.name, dark: dark).icon,
                      ),
                      active: selected == cat.id,
                      onTap: () => onSelect(cat.id),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(height: 1, color: colors.border),
        ],
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final String? icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = active ? colors.accent : colors.textMuted;
    return TactileScale(
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: SizedBox(
        height: kCategoryTabsHeight,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  if (icon != null) ...[
                    MadarIcon(icon, tint: fg, size: IconSize.sm),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    label,
                    style: MadarType.bodySm.copyWith(
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
            // Active-tab underline.
            Container(
              height: 2,
              color: active ? colors.accent : const Color(0x00000000),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search field ───────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.placeholder,
    required this.value,
  });

  final TextEditingController controller;
  final String placeholder;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: kSearchFieldHeight,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.md),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: colors.borderLight),
        boxShadow: MadarElevation.card.shadows(colors, dark: dark),
      ),
      child: Row(
        children: [
          MadarIcon('magnifyingglass', tint: colors.textMuted),
          const SizedBox(width: Space.sm),
          Expanded(
            child: TextField(
              controller: controller,
              cursorColor: colors.accent,
              style: MadarType.title.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration.collapsed(
                hintText: placeholder,
                hintStyle: MadarType.title.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.textMuted,
                ),
              ),
            ),
          ),
          if (value.isNotEmpty)
            GestureDetector(
              onTap: controller.clear,
              behavior: HitTestBehavior.opaque,
              child: MadarIcon(
                'xmark',
                tint: colors.textMuted,
                size: IconSize.sm,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Item grid ──────────────────────────────────────────────────────────────────

SliverGridDelegateWithMaxCrossAxisExtent _gridDelegate() =>
    const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: Grid.cellMax,
      mainAxisSpacing: Grid.gutter,
      crossAxisSpacing: Grid.gutter,
      childAspectRatio: kMenuCardAspect,
    );

class _ItemGridOrEmpty extends ConsumerWidget {
  const _ItemGridOrEmpty({
    required this.items,
    required this.searching,
    required this.gridKey,
    required this.onItemTap,
  });

  final List<MenuItemView> items;
  final bool searching;
  final String? gridKey;
  final ValueChanged<MenuItemView> onItemTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final notifier = ref.read(orderProvider.notifier);
    if (items.isEmpty) {
      return EmptyState(
        icon: searching ? 'magnifyingglass' : 'tray',
        title: bridge.tr(
          key: searching ? 'order.empty_search' : 'order.empty',
        ),
      );
    }
    // The grid re-renders on catalog/cart-badge changes only — sync chrome
    // and toast churn never reaches this hot path.
    final currency = ref.watch(orderProvider.select((s) => s.currency));
    final categories = ref.watch(orderProvider.select((s) => s.categories));
    final cartLines = ref.watch(orderProvider.select((s) => s.cartLines));
    String categoryName(String? id) =>
        categories.where((c) => c.id == id).firstOrNull?.name ?? '';
    int cartQtyForItem(String itemId) => cartLines
        .where((l) => l.itemId == itemId)
        .fold(0, (sum, l) => sum + l.qty);
    return GridView.builder(
      // One storage slot per category — switching back restores the scroll
      // position (the data never reloads; it's an in-memory filter).
      key: PageStorageKey('catalog-${gridKey ?? 'all'}'),
      padding: const EdgeInsetsDirectional.all(Grid.padding),
      gridDelegate: _gridDelegate(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final name = categoryName(item.categoryId);
        return MenuItemCard(
          item: item,
          categoryName: name,
          currency: currency,
          inCartQty: cartQtyForItem(item.id),
          style: notifier.categoryStyle(
            name.isEmpty ? item.name : name,
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
          onTap: () => onItemTap(item),
        );
      },
    );
  }
}

/// Card-shaped pulsing placeholders while the catalog projection loads.
class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.all(Grid.padding),
        gridDelegate: _gridDelegate(),
        itemCount: 8,
        itemBuilder: (context, _) => const _SkeletonCard(),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.borderLight),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _PulseFill()),
          Padding(
            padding: EdgeInsetsDirectional.all(Space.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SkeletonBlock(width: 84),
                SkeletonBlock(width: 44),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An expand-filling [SkeletonBlock]-alike for the card hero (the shared
/// block takes a fixed height; the hero must fill its grid cell).
class _PulseFill extends StatelessWidget {
  const _PulseFill();

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final pulse = SkeletonScope.maybePulseOf(context);
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: const BorderRadiusDirectional.only(
          topStart: Radius.circular(Radii.md),
          topEnd: Radius.circular(Radii.md),
        ),
      ),
      child: const SizedBox.expand(),
    );
    if (pulse == null) return box;
    return FadeTransition(opacity: pulse, child: box);
  }
}

// ── Menu item card ─────────────────────────────────────────────────────────────

/// The catalog's product card — category-hued gradient hero (monogram + a
/// soft decorative ring), a live in-cart quantity badge, and a fixed footer
/// (name · bold teal price). Mirror of the natives' MenuItemCard.
class MenuItemCard extends StatelessWidget {
  const MenuItemCard({
    required this.item,
    required this.categoryName,
    required this.currency,
    required this.inCartQty,
    required this.style,
    required this.onTap,
    super.key,
  });

  final MenuItemView item;
  final String categoryName;
  final String currency;
  final int inCartQty;

  /// Core-derived gradient palette for the item's category.
  final CatStyleView style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = hexColor(style.accent);
    final url = item.imageUrl;

    return TactileScale(
      scale: 0.98,
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.borderLight),
          boxShadow: MadarElevation.card.shadows(colors, dark: dark),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.md),
          child: Column(
            children: [
              // ── Hero (gradient + ring + monogram + photo + badge) ──────
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            hexColor(style.bgTop),
                            hexColor(style.bgBottom),
                          ],
                        ),
                      ),
                    ),
                    // Decorative ring bleeding off the bottom-end corner.
                    PositionedDirectional(
                      bottom: -_ringBleed,
                      end: -_ringBleed,
                      child: Container(
                        width: _ringSize,
                        height: _ringSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accent.withValues(alpha: 0.16),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        monogram(item.name),
                        style: MadarType.display.copyWith(
                          fontSize: 42,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                          color: accent.withValues(alpha: dark ? 0.7 : 0.55),
                        ),
                      ),
                    ),
                    // Real photo (when present) covers the gradient once
                    // loaded; while loading / on failure nothing draws, so
                    // the gradient + monogram show through. Decode is
                    // bounded to the displayed cell size (a full-res menu
                    // photo would otherwise jank the first paint and bloat
                    // the image cache).
                    if (url != null && url.isNotEmpty)
                      Image.network(
                        url,
                        fit: BoxFit.cover,
                        cacheWidth:
                            (Grid.cellMax *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    if (inCartQty > 0)
                      PositionedDirectional(
                        top: _badgeInset,
                        end: _badgeInset,
                        child: Container(
                          padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colors.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.surface,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            '$inCartQty',
                            style: MadarType.label.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colors.textOnAccent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // ── Footer (name · bold teal price) ─────────────────────────
              Container(
                height: _footerHeight,
                color: colors.surface,
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: Space.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.bodySm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    MoneyText(
                      item.basePriceMinor,
                      currency: currency,
                      style: MadarType.money.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card footer height (natives: 48.dp).
const double _footerHeight = 48;

/// Decorative ring diameter / bleed (natives: 130.dp circle offset 46.dp).
const double _ringSize = 130;
const double _ringBleed = 46;

/// In-cart badge inset from the hero corner (natives: 7.dp).
const double _badgeInset = 7;

// ── Bundle (combo) grid + card ─────────────────────────────────────────────────

class _BundleGrid extends ConsumerWidget {
  const _BundleGrid({required this.onBundleTap});

  final ValueChanged<BundleView> onBundleTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final bundles = ref.watch(orderProvider.select((s) => s.bundles));
    final currency = ref.watch(orderProvider.select((s) => s.currency));
    return GridView.builder(
      key: const PageStorageKey('catalog-combos'),
      padding: const EdgeInsetsDirectional.all(Grid.padding),
      gridDelegate: _gridDelegate(),
      itemCount: bundles.length,
      itemBuilder: (context, index) {
        final bundle = bundles[index];
        return BundleCard(
          bundle: bundle,
          currency: currency,
          comboLabel: bridge.tr(key: 'order.combos'),
          includesLabel: bridge.tr(key: 'order.bundle_includes'),
          onTap: () => onBundleTap(bundle),
        );
      },
    );
  }
}

/// A combo card in the catalog grid — an accent-gradient hero with a Combo
/// chip, the bundle name, component count, and fixed price. Matches the
/// MenuItemCard style.
class BundleCard extends StatelessWidget {
  const BundleCard({
    required this.bundle,
    required this.currency,
    required this.comboLabel,
    required this.includesLabel,
    required this.onTap,
    super.key,
  });

  final BundleView bundle;
  final String currency;
  final String comboLabel;
  final String includesLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final url = bundle.imageUrl;
    return TactileScale(
      scale: 0.98,
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero (accent gradient + optional photo + Combo chip) ────
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colors.accent,
                            colors.accent.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                    ),
                    // Image's own opacity param modulates alpha during
                    // rasterization — an Opacity widget would force a
                    // saveLayer on every paint of the card.
                    if (url != null && url.isNotEmpty)
                      Image.network(
                        url,
                        fit: BoxFit.cover,
                        opacity: const AlwaysStoppedAnimation(0.55),
                        cacheWidth:
                            (Grid.cellMax *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    PositionedDirectional(
                      top: Space.sm,
                      start: Space.sm,
                      child: StatusChip(
                        label: comboLabel,
                        tone: ChipTone.accent,
                        icon: 'bag.fill',
                      ),
                    ),
                  ],
                ),
              ),
              // ── Footer (name · component count · price) ─────────────────
              Container(
                color: colors.surface,
                padding: const EdgeInsetsDirectional.all(Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bundle.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      '${bundle.components.length} $includesLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.labelSm.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    MoneyText(
                      bundle.priceMinor,
                      currency: currency,
                      style: MadarType.money.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
