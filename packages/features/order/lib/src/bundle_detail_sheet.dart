import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_order/src/cart_panel.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:feature_order/src/order_controller.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Bundle (combo) configuration sheet. A bundle is a fixed price covering a
/// set of component items; each configurable component opens the SAME
/// item-customization sheet in configure mode, which pops the selection
/// instead of writing to the cart. "Add to cart" records one bundle line
/// via the core (cart_add_bundle), where component up-charges are resolved.
class BundleDetailSheet extends StatefulWidget {
  const BundleDetailSheet({
    required this.model,
    required this.bundle,
    super.key,
  });

  final OrderController model;
  final BundleView bundle;

  @override
  State<BundleDetailSheet> createState() => _BundleDetailSheetState();
}

class _BundleDetailSheetState extends State<BundleDetailSheet> {
  /// Per-component config, keyed by the component's index (handles a bundle
  /// that lists the same item twice).
  final Map<int, BundleComponentDraft> _drafts = {};

  /// A component needs configuring when it has a size choice, addon slots,
  /// or active optionals.
  bool _needsConfig(MenuItemView item) =>
      item.sizes.length > 1 ||
      item.addonSlots.isNotEmpty ||
      item.optionalFields.any((f) => f.isActive);

  MenuItemView? _itemFor(BundleComponentView comp) =>
      widget.model.menuItemById(comp.itemId);

  Future<void> _configure(int index, MenuItemView item) async {
    // Load the component's addons, then open the per-component customization
    // sheet on top of this one; the draft pops back.
    final addons = await widget.model.loadItemAddons(item.id);
    if (!mounted) return;
    final draft = await showMadarSheet<BundleComponentDraft>(
      context,
      size: SheetSize.hug,
      builder: (_) => ItemDetailSheet(
        model: widget.model,
        item: item,
        addons: addons,
        configureSeed: _drafts[index],
        isConfiguring: true,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() => _drafts[index] = draft);
  }

  Future<void> _add() async {
    final components = <BundleComponentSelection>[];
    for (var i = 0; i < widget.bundle.components.length; i++) {
      final comp = widget.bundle.components[i];
      final draft = _drafts[i];
      final defaultSize = _itemFor(comp)?.sizes.firstOrNull?.label;
      components.add(
        BundleComponentSelection(
          itemId: comp.itemId,
          sizeLabel: draft?.sizeLabel ?? defaultSize,
          qty: comp.quantity,
          addons: draft?.addons ?? const [],
          optionalFieldIds: draft?.optionalIds ?? const [],
        ),
      );
    }
    await widget.model.addBundle(widget.bundle.id, components);
    if (mounted) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final colors = context.madarColors;
    final bundle = widget.bundle;

    // All configurable components must be configured before adding.
    var canAdd = true;
    for (var i = 0; i < bundle.components.length; i++) {
      final item = _itemFor(bundle.components[i]);
      if (item != null && _needsConfig(item) && _drafts[i] == null) {
        canAdd = false;
        break;
      }
    }
    final extrasTotal = _drafts.values.fold(0, (sum, d) => sum + d.extrasMinor);
    final liveTotal = bundle.priceMinor + extrasTotal;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BundleHeader(bundle: bundle, currency: model.currency),
        Flexible(
          child: ColoredBox(
            color: colors.surfaceAlt,
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.all(Space.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(model.tr('order.bundle_includes')),
                  const SizedBox(height: Space.md),
                  for (var i = 0; i < bundle.components.length; i++) ...[
                    Builder(
                      builder: (context) {
                        final comp = bundle.components[i];
                        final item = _itemFor(comp);
                        final configurable = item != null && _needsConfig(item);
                        return _ComponentTile(
                          model: model,
                          comp: comp,
                          currency: model.currency,
                          configurable: configurable,
                          draft: _drafts[i],
                          onTap: () {
                            if (item != null && configurable) {
                              unawaited(_configure(i, item));
                            }
                          },
                        );
                      },
                    ),
                    const SizedBox(height: Space.md),
                  ],
                ],
              ),
            ),
          ),
        ),
        _BundleFooter(
          model: model,
          bundlePriceMinor: bundle.priceMinor,
          extrasMinor: extrasTotal,
          liveTotalMinor: liveTotal,
          currency: model.currency,
          canAdd: canAdd,
          onAdd: () => unawaited(_add()),
        ),
      ],
    );
  }
}

// ── Header (name + description · price badge · close) ─────────────────────────

class _BundleHeader extends StatelessWidget {
  const _BundleHeader({required this.bundle, required this.currency});

  final BundleView bundle;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final description = bundle.description;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
              vertical: Space.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bundle.name,
                        style: MadarType.h3.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (description != null && description.isNotEmpty)
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: MadarType.label.copyWith(
                            fontWeight: FontWeight.w400,
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                Container(
                  height: Metrics.closeButton,
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 10,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.navyBg,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: MoneyText(
                    bundle.priceMinor,
                    currency: currency,
                    color: colors.navy,
                  ),
                ),
                const SizedBox(width: Space.sm),
                TactileScale(
                  onTap: () => unawaited(Navigator.of(context).maybePop()),
                  child: Container(
                    width: Metrics.closeButton,
                    height: Metrics.closeButton,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: colors.border),
                    ),
                    child: MadarIcon(
                      'xmark',
                      tint: colors.textMuted,
                      size: IconSize.sm,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: colors.border),
        ],
      ),
    );
  }
}

// ── Footer (base + extras · tinted teal total · Add to cart) ───────────────────

class _BundleFooter extends StatelessWidget {
  const _BundleFooter({
    required this.model,
    required this.bundlePriceMinor,
    required this.extrasMinor,
    required this.liveTotalMinor,
    required this.currency,
    required this.canAdd,
    required this.onAdd,
  });

  final OrderController model;
  final int bundlePriceMinor;
  final int extrasMinor;
  final int liveTotalMinor;
  final String currency;
  final bool canAdd;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        children: [
          Container(height: 1, color: colors.border),
          Padding(
            padding: const EdgeInsetsDirectional.all(Space.lg),
            child: Column(
              children: [
                // Base + extras — light sub-rows so the total carries weight.
                _FooterRow(
                  label: model.tr('order.subtotal'),
                  value: Money.format(bundlePriceMinor, currency: currency),
                ),
                if (extrasMinor > 0) ...[
                  const SizedBox(height: Space.sm),
                  _FooterRow(
                    label: model.tr('order.addon_extra'),
                    value: '+${Money.format(extrasMinor, currency: currency)}',
                  ),
                ],
                const SizedBox(height: Space.sm),
                GrandTotalBlock(
                  label: model.tr('order.total'),
                  totalMinor: liveTotalMinor,
                  currency: currency,
                ),
                const SizedBox(height: Space.md),
                ActionButton(
                  label: model.tr(
                    canAdd ? 'order.add_to_cart' : 'order.configure',
                  ),
                  enabled: canAdd,
                  onTap: onAdd,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterRow extends StatelessWidget {
  const _FooterRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      children: [
        Text(
          label,
          style: MadarType.bodySm.copyWith(
            fontWeight: FontWeight.w500,
            color: colors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: MadarType.bodySm.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ── Component row ──────────────────────────────────────────────────────────────

/// A bundle component row — status tile, qty× name + a config summary, the
/// chosen extras up-charge, and a chevron when configurable.
class _ComponentTile extends StatelessWidget {
  const _ComponentTile({
    required this.model,
    required this.comp,
    required this.currency,
    required this.configurable,
    required this.draft,
    required this.onTap,
  });

  final OrderController model;
  final BundleComponentView comp;
  final String currency;
  final bool configurable;
  final BundleComponentDraft? draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final draft = this.draft;
    final configured = draft != null;

    // Leading status tile — navy "included" ✓ when fixed, success ✓ once
    // configured, an accent slider glyph while it still needs configuring.
    final (String glyph, Color glyphColor, Color tileBg) = switch ((
      configurable,
      configured,
    )) {
      (false, _) => ('checkmark.circle.fill', colors.navy, colors.navyBg),
      (true, true) => (
        'checkmark.circle.fill',
        colors.success,
        colors.successBg,
      ),
      (true, false) => (
        'slider.horizontal.3',
        colors.accent,
        colors.accentBg,
      ),
    };

    // Subtitle for configurable rows only: a "Configure" prompt, or the
    // chosen size · +N once configured.
    String? subtitle;
    if (configurable) {
      if (!configured) {
        subtitle = model.tr('order.configure');
      } else {
        final extras = draft.addons.length + draft.optionalIds.length;
        final parts = <String>[
          ?draft.sizeLabel,
          if (extras > 0) '+$extras',
        ];
        subtitle = parts.isEmpty
            ? model.tr('order.configure')
            : parts.join(' · ');
      }
    }

    Widget tile = Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.md,
        vertical: Space.md,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: configured
              ? colors.accent.withValues(alpha: 0.4)
              : colors.borderLight,
        ),
        boxShadow: MadarElevation.card.shadows(colors, dark: dark),
      ),
      child: Row(
        children: [
          Container(
            width: Metrics.iconTile,
            height: Metrics.iconTile,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tileBg,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: MadarIcon(glyph, tint: glyphColor),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${comp.quantity}× ${comp.itemName}',
                  style: MadarType.title.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 2),
                    child: Text(
                      subtitle,
                      style: MadarType.label.copyWith(
                        fontWeight: configured
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: configured
                            ? colors.accent
                            : colors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (configured && draft.extrasMinor > 0) ...[
            const SizedBox(width: Space.sm),
            Text(
              '+${Money.format(draft.extrasMinor, currency: currency)}',
              textDirection: TextDirection.ltr,
              style: MadarType.label.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (configurable) ...[
            const SizedBox(width: Space.sm),
            MadarIcon(
              'chevron.forward',
              tint: colors.textMuted,
              size: IconSize.sm,
            ),
          ],
        ],
      ),
    );
    if (configurable) {
      tile = TactileScale(
        scale: 0.99,
        onTap: () {
          MadarHaptics.selection();
          onTap();
        },
        child: tile,
      );
    }
    return tile;
  }
}
