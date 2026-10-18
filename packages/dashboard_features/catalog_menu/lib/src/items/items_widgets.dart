/// The items page's small parts: the tab switch with counts, the price-tax
/// hint, the card image tile, the cost footers, the branch availability
/// switches, and the dialogs' bilingual and price boxes.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        AddonCost,
        AssetGroupRef,
        AssetGroupRefReadyGroupRef,
        BranchAddonOverride,
        BranchMenuOverride,
        DashboardApi,
        MenuItemWithCosts,
        PriceOverrideRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/menu_queries.dart';
import 'items_data.dart';

/// The card image tile's side (`size-11`).
const double menuTileSize = 44;

// ── tabs ───────────────────────────────────────────────────────────────────

/// One tab of [MenuTabsBar].
typedef MenuTabSpec = ({MenuTab tab, String label, int count});

/// The page's segmented tabs (the web's `SegmentedControl` in the header's
/// `below`): each label with its count (mono, quieter). A tab about to be
/// pressed warms the reads it shows ([onIntent]).
class MenuTabsBar extends StatelessWidget {
  const MenuTabsBar({
    required this.tabs,
    required this.value,
    required this.onChanged,
    this.onIntent,
    super.key,
  });

  final List<MenuTabSpec> tabs;
  final MenuTab value;
  final ValueChanged<MenuTab> onChanged;
  final ValueChanged<MenuTab>? onIntent;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final fmt = context.dashFormats;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.all(DashMetrics.ring),
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in tabs)
                DashPressable(
                  key: ValueKey('menu-tab-${s.tab.name}'),
                  onTap: () => onChanged(s.tab),
                  onIntent: onIntent == null ? null : () => onIntent!(s.tab),
                  selected: s.tab == value,
                  checked: s.tab == value,
                  isButton: false,
                  semanticLabel: '${s.label} ${fmt.number(s.count)}',
                  excludeChildSemantics: true,
                  pressScale: false,
                  builder: (context, st) {
                    final on = s.tab == value;
                    final fg = on
                        ? c.textOnAccent
                        : st.hovered
                        ? c.textPrimary
                        : c.textSecondary;
                    return Container(
                      height: DashMetrics.target,
                      padding: const EdgeInsets.symmetric(horizontal: Space.md),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on
                            ? c.accent
                            : st.hovered
                            ? c.hover
                            : null,
                        borderRadius: BorderRadius.circular(Radii.xs),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: Space.xs + DashMetrics.hair,
                        children: [
                          Text(
                            s.label,
                            maxLines: 1,
                            style: DashType.bodyMedium.copyWith(color: fg),
                          ),
                          Text(
                            dashFigure(fmt.number(s.count)),
                            // `text-xs` in mono: the small token's size.
                            style: DashType.mono.copyWith(
                              fontSize: DashType.small.fontSize,
                              color: fg.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── price-tax hint ─────────────────────────────────────────────────────────

/// Whether a menu price already holds the tax (`PriceTaxHint`): nothing
/// when the org is not loaded or has no tax.
class PriceTaxHint extends ConsumerWidget {
  const PriceTaxHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final org = ref.watch(currentOrgProvider).value;
    if (org == null || !(org.taxRate > 0)) return const SizedBox.shrink();
    final rate = ltr(formatRate(org.taxRate));
    final main = org.taxInclusive
        ? t('menu.priceIncludesTax', args: {'rate': rate})
        : t('menu.priceExcludesTax', args: {'rate': rate});
    return Text(
      '$main · ${t('menu.priceTaxBranchNote')}',
      key: const ValueKey('price-tax-hint'),
      style: DashType.small.copyWith(color: context.madarColors.textSecondary),
    );
  }
}

// ── image tile ─────────────────────────────────────────────────────────────

/// The picture to show for a row: its ready asset's tile, else the legacy
/// URL.
String? menuImageUrl(AssetGroupRef? image, String? legacy) {
  if (image is AssetGroupRefReadyGroupRef) {
    final v = image.value.variants;
    final url = (v.tile ?? v.full ?? v.thumb)?.url;
    if (url != null && url.isNotEmpty) return url;
  }
  return legacy == null || legacy.isEmpty ? null : legacy;
}

/// The 44 px tile on a card (and 36 px in the reorder list): the picture,
/// else [icon].
class MenuImageTile extends StatelessWidget {
  const MenuImageTile({
    required this.url,
    required this.icon,
    this.size = menuTileSize,
    super.key,
  });

  final String? url;
  final String icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final glyph = Center(
      child: DashIcon(icon, size: IconSize.md, color: c.textSecondary),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: url == null
          ? glyph
          : Image.network(
              url!,
              fit: BoxFit.cover,
              cacheWidth: dashThumbDecodeWidth(context, size),
              errorBuilder: (_, _, _) => glyph,
            ),
    );
  }
}

// ── cost footers ───────────────────────────────────────────────────────────

/// The web's `CostMissingLink` target: the retired recipes page, which
/// redirects to `/menu/items`.
void openCostFix(BuildContext context, {String? itemId, String? addonId}) {
  final q = itemId != null ? '?item=$itemId' : '?addon=$addonId';
  context.go('/menu/recipes$q');
}

/// `ItemCostCell`: one line per size.
class ItemCostFooter extends StatelessWidget {
  const ItemCostFooter({required this.item, super.key});

  final MenuItemWithCosts item;

  @override
  Widget build(BuildContext context) => DashItemCostCell(
    skus: [
      for (final s in item.skuCosts)
        DashSkuCost(
          sizeLabel: s.sizeLabel,
          cost: s.cost,
          price: s.price,
          costMissing: s.costMissing,
        ),
    ],
    onFixMissing: () => openCostFix(context, itemId: item.id),
  );
}

/// `AddonCostCell`: "—" without a cost row.
class AddonCostFooter extends StatelessWidget {
  const AddonCostFooter({required this.addonId, required this.cost, super.key});

  final String addonId;
  final AddonCost? cost;

  @override
  Widget build(BuildContext context) {
    final c = cost;
    if (c == null) {
      return Text(
        '—',
        style: DashType.small.copyWith(
          color: context.madarColors.textSecondary,
        ),
      );
    }
    return DashAddonCostCell(
      cost: c.cost,
      price: c.price,
      costMissing: c.costMissing,
      onFixMissing: () => openCostFix(context, addonId: addonId),
    );
  }
}

// ── branch availability ────────────────────────────────────────────────────

/// "Available at this branch" with its switch (`AvailabilityRow`).
class _AvailabilityRow extends StatelessWidget {
  const _AvailabilityRow({
    required this.checked,
    required this.busy,
    required this.onChanged,
  });

  final bool checked;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = context.t('menu.overrides.available');
    return Row(
      spacing: Space.sm,
      children: [
        Expanded(
          child: Text(
            label,
            style: DashType.small.copyWith(
              color: context.madarColors.textSecondary,
            ),
          ),
        ),
        DashSwitch(
          value: checked,
          semanticLabel: label,
          enabled: !busy,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// The branch scope of an override row.
PriceOverrideRequest _branchRow(
  String branchId,
  String type,
  String target, {
  bool write = false,
  int? price,
  bool? available,
}) => PriceOverrideRequest(
  scope: 'branch',
  branchId: branchId,
  targetType: type,
  targetId: target,
  price: price,
  isAvailable: available,
  explicitNulls: write ? const {'price', 'is_available'} : const {},
);

mixin _ToggleRun<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool busy = false;

  Future<void> run(Future<void> Function(DashboardApi api) writes) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final invalidate = ref.menuInvalidate;
    setState(() => busy = true);
    try {
      await writes(api);
      invalidate.catalog();
      if (mounted) DashToast.success(context, t('common.savedChanges'));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

/// An item's switch: availability is per size, so a change reads the item's
/// studio and writes one branch row per size (`BranchMenuItemAvailabilitySwitch`).
class ItemBranchSwitch extends ConsumerStatefulWidget {
  const ItemBranchSwitch({
    required this.branchId,
    required this.itemId,
    required this.row,
    super.key,
  });

  final String branchId;
  final String itemId;
  final BranchMenuOverride? row;

  @override
  ConsumerState<ItemBranchSwitch> createState() => _ItemBranchSwitchState();
}

class _ItemBranchSwitchState extends ConsumerState<ItemBranchSwitch>
    with _ToggleRun {
  Future<void> _change(bool on) => run((api) async {
    final studio = await api.menu.getStudio(id: widget.itemId);
    final rows = {
      for (final b in studio.availability.branches)
        if (b.branchId == widget.branchId)
          for (final s in b.sizes) s.sizeId: s,
    };
    for (final size in studio.sizes) {
      final row = rows[size.id];
      if (on && row?.price == null) {
        if (row != null) {
          await api.menu.deletePriceOverride(
            body: _branchRow(widget.branchId, 'menu_item_size', size.id),
          );
        }
      } else {
        await api.menu.putPriceOverride(
          body: _branchRow(
            widget.branchId,
            'menu_item_size',
            size.id,
            write: true,
            price: row?.price,
            available: on ? null : false,
          ),
        );
      }
    }
  });

  @override
  Widget build(BuildContext context) => _AvailabilityRow(
    checked: widget.row?.isAvailable ?? true,
    busy: busy,
    onChanged: _change,
  );
}

/// An add-on's switch: one branch row on its option
/// (`BranchAddonAvailabilitySwitch`).
class AddonBranchSwitch extends ConsumerStatefulWidget {
  const AddonBranchSwitch({
    required this.branchId,
    required this.addonId,
    required this.row,
    super.key,
  });

  final String branchId;
  final String addonId;
  final BranchAddonOverride? row;

  @override
  ConsumerState<AddonBranchSwitch> createState() => _AddonBranchSwitchState();
}

class _AddonBranchSwitchState extends ConsumerState<AddonBranchSwitch>
    with _ToggleRun {
  Future<void> _change(bool on) => run((api) async {
    final price = widget.row?.priceOverride;
    if (on && price == null) {
      await api.menu.deletePriceOverride(
        body: _branchRow(widget.branchId, 'modifier_option', widget.addonId),
      );
    } else {
      await api.menu.putPriceOverride(
        body: _branchRow(
          widget.branchId,
          'modifier_option',
          widget.addonId,
          write: true,
          price: price,
          available: on ? null : false,
        ),
      );
    }
  });

  @override
  Widget build(BuildContext context) => _AvailabilityRow(
    checked: widget.row?.isAvailable ?? true,
    busy: busy,
    onChanged: _change,
  );
}

// ── dialog fields ──────────────────────────────────────────────────────────

/// Keeps a money box to what `<input type=number step=0.01 min=0>` lets a
/// form submit: digits and one point, two decimals at most.
final List<TextInputFormatter> priceInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
  TextInputFormatter.withFunction((old, next) {
    final v = next.text.replaceAll(',', '.');
    final ok = RegExp(r'^\d*(\.\d{0,2})?$').hasMatch(v);
    return ok ? next.copyWith(text: v) : old;
  }),
];

/// A price box in pounds: "Price (EGP)" (the currency in the active
/// language).
class MenuPriceField extends StatelessWidget {
  const MenuPriceField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.onSubmit,
    this.description,
    super.key,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final VoidCallback? onSubmit;
  final String? description;

  @override
  Widget build(BuildContext context) => DashTextField(
    label: label,
    value: value,
    errorText: errorText,
    description: description,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: priceInputFormatters,
    textDirection: TextDirection.ltr,
    onChanged: onChanged,
    onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
  );
}
