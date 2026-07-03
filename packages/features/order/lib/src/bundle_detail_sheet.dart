import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/cart_anchor.dart';
import 'package:feature_order/src/cart_panel.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The DATA one bundle-configuration presentation is seeded from. Identity
/// equality on purpose — each sheet instance creates its own args once, so
/// its [bundleConfigProvider] member auto-disposes with it.
class BundleSheetArgs {
  BundleSheetArgs({required this.bundle});

  final BundleView bundle;
}

/// Per-component config, keyed by the component's index (handles a bundle
/// that lists the same item twice), plus the add-to-cart in-flight latch.
@immutable
class BundleConfigState {
  const BundleConfigState({
    this.drafts = const {},
    this.adding = false,
  });

  final Map<int, BundleComponentDraft> drafts;

  /// Latches the footer while add-to-cart is in flight so a double-tap
  /// can't record the bundle line twice.
  final bool adding;

  BundleConfigState copyWith({
    Map<int, BundleComponentDraft>? drafts,
    bool? adding,
  }) => BundleConfigState(
    drafts: drafts ?? this.drafts,
    adding: adding ?? this.adding,
  );
}

/// Selection notifier for one bundle sheet presentation.
class BundleConfigNotifier
    extends AutoDisposeFamilyNotifier<BundleConfigState, BundleSheetArgs> {
  @override
  BundleConfigState build(BundleSheetArgs arg) => const BundleConfigState();

  void setDraft(int index, BundleComponentDraft draft) =>
      state = state.copyWith(drafts: {...state.drafts, index: draft});

  /// Record the configured bundle. Returns false when an add is already in
  /// flight (the double-tap guard) — the sheet pops only on true.
  Future<bool> addToCart() async {
    if (state.adding) return false;
    state = state.copyWith(adding: true);
    final bundle = arg.bundle;
    final order = ref.read(orderProvider);
    final components = <BundleComponentSelection>[];
    for (var i = 0; i < bundle.components.length; i++) {
      final comp = bundle.components[i];
      final draft = state.drafts[i];
      final defaultSize = order
          .menuItemById(comp.itemId)
          ?.sizes
          .firstOrNull
          ?.label;
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
    await ref.read(orderProvider.notifier).addBundle(bundle.id, components);
    return true;
  }
}

/// One bundle sheet presentation's state, keyed by its (identity) args.
final AutoDisposeNotifierProviderFamily<
  BundleConfigNotifier,
  BundleConfigState,
  BundleSheetArgs
>
bundleConfigProvider = NotifierProvider.autoDispose
    .family<BundleConfigNotifier, BundleConfigState, BundleSheetArgs>(
      BundleConfigNotifier.new,
    );

/// Bundle (combo) configuration sheet. A bundle is a fixed price covering a
/// set of component items; each configurable component opens the SAME
/// item-customization sheet in configure mode, which pops the selection
/// instead of writing to the cart. "Add to cart" records one bundle line
/// via the core (cart_add_bundle), where component up-charges are resolved.
class BundleDetailSheet extends ConsumerStatefulWidget {
  const BundleDetailSheet({required this.bundle, super.key});

  final BundleView bundle;

  @override
  ConsumerState<BundleDetailSheet> createState() => _BundleDetailSheetState();
}

class _BundleDetailSheetState extends ConsumerState<BundleDetailSheet> {
  /// Created once per presentation — the identity key that gives this sheet
  /// its own [bundleConfigProvider] member.
  late final BundleSheetArgs _args = BundleSheetArgs(bundle: widget.bundle);

  /// Anchors the footer CTA — the add-to-cart flight launches from here.
  final GlobalKey _footerKey = GlobalKey();

  /// A component needs configuring when it has a size choice, addon slots,
  /// or active optionals.
  bool _needsConfig(MenuItemView item) =>
      item.sizes.length > 1 ||
      item.addonSlots.isNotEmpty ||
      item.optionalFields.any((f) => f.isActive);

  MenuItemView? _itemFor(BundleComponentView comp) =>
      ref.read(orderProvider).menuItemById(comp.itemId);

  Future<void> _configure(int index, MenuItemView item) async {
    // Load the component's addons, then open the per-component customization
    // sheet on top of this one; the draft pops back.
    final addons = await ref
        .read(orderProvider.notifier)
        .loadItemAddons(item.id);
    final groups = await ref
        .read(orderProvider.notifier)
        .loadItemModifierGroups(item.id);
    if (!mounted) return;
    final seed = ref.read(bundleConfigProvider(_args)).drafts[index];
    final draft = await showMadarSheet<BundleComponentDraft>(
      context,
      size: SheetSize.hug,
      builder: (_) => ItemDetailSheet(
        item: item,
        addons: addons,
        groups: groups,
        configureSeed: seed,
        isConfiguring: true,
      ),
    );
    if (draft == null || !mounted) return;
    ref.read(bundleConfigProvider(_args).notifier).setDraft(index, draft);
  }

  Future<void> _add() async {
    final added = await ref
        .read(bundleConfigProvider(_args).notifier)
        .addToCart();
    if (added && mounted) {
      _flyToCart();
      await Navigator.of(context).maybePop();
    }
  }

  /// Fly the add-to-cart dot from the footer CTA to the mounted cart anchor
  /// — pure chrome on top of the already-committed add; skipped when either
  /// end is missing.
  void _flyToCart() {
    final render = _footerKey.currentContext?.findRenderObject();
    final to = cartAnchorCenter();
    if (render is! RenderBox || !render.hasSize || to == null) return;
    playCartFlight(
      context,
      from: render.localToGlobal(render.size.center(Offset.zero)),
      to: to,
      onArrive: () => cartCatchTick.value++,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final currency = ref.watch(orderProvider.select((s) => s.currency));
    final config = ref.watch(bundleConfigProvider(_args));
    final bundle = widget.bundle;

    // All configurable components must be configured before adding.
    var canAdd = true;
    for (var i = 0; i < bundle.components.length; i++) {
      final item = _itemFor(bundle.components[i]);
      if (item != null && _needsConfig(item) && config.drafts[i] == null) {
        canAdd = false;
        break;
      }
    }
    final extrasTotal = config.drafts.values.fold(
      0,
      (sum, d) => sum + d.extrasMinor,
    );
    final liveTotal = bundle.priceMinor + extrasTotal;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BundleHeader(bundle: bundle, currency: currency),
        Flexible(
          child: ColoredBox(
            color: colors.surfaceAlt,
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.all(Space.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(bridge.tr(key: 'order.bundle_includes')),
                  const SizedBox(height: Space.md),
                  for (var i = 0; i < bundle.components.length; i++) ...[
                    Builder(
                      builder: (context) {
                        final comp = bundle.components[i];
                        final item = _itemFor(comp);
                        final configurable = item != null && _needsConfig(item);
                        return _ComponentTile(
                          comp: comp,
                          currency: currency,
                          configurable: configurable,
                          draft: config.drafts[i],
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
        KeyedSubtree(
          key: _footerKey,
          child: _BundleFooter(
            bundlePriceMinor: bundle.priceMinor,
            extrasMinor: extrasTotal,
            liveTotalMinor: liveTotal,
            currency: currency,
            canAdd: canAdd,
            loading: config.adding,
            onAdd: () => unawaited(_add()),
          ),
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

class _BundleFooter extends ConsumerWidget {
  const _BundleFooter({
    required this.bundlePriceMinor,
    required this.extrasMinor,
    required this.liveTotalMinor,
    required this.currency,
    required this.canAdd,
    required this.loading,
    required this.onAdd,
  });

  final int bundlePriceMinor;
  final int extrasMinor;
  final int liveTotalMinor;
  final String currency;
  final bool canAdd;

  /// Add-to-cart in flight — spinner on, taps blocked (double-tap guard).
  final bool loading;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
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
                  label: bridge.tr(key: 'order.subtotal'),
                  value: Money.format(bundlePriceMinor, currency: currency),
                ),
                if (extrasMinor > 0) ...[
                  const SizedBox(height: Space.sm),
                  _FooterRow(
                    label: bridge.tr(key: 'order.addon_extra'),
                    value: '+${Money.format(extrasMinor, currency: currency)}',
                  ),
                ],
                const SizedBox(height: Space.sm),
                GrandTotalBlock(
                  label: bridge.tr(key: 'order.total'),
                  totalMinor: liveTotalMinor,
                  currency: currency,
                ),
                const SizedBox(height: Space.md),
                ActionButton(
                  label: bridge.tr(
                    key: canAdd ? 'order.add_to_cart' : 'order.configure',
                  ),
                  enabled: canAdd,
                  loading: loading,
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
class _ComponentTile extends ConsumerWidget {
  const _ComponentTile({
    required this.comp,
    required this.currency,
    required this.configurable,
    required this.draft,
    required this.onTap,
  });

  final BundleComponentView comp;
  final String currency;
  final bool configurable;
  final BundleComponentDraft? draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bridge = ref.watch(bridgeProvider);
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
        subtitle = bridge.tr(key: 'order.configure');
      } else {
        final extras = draft.addons.length + draft.optionalIds.length;
        final parts = <String>[
          ?draft.sizeLabel,
          if (extras > 0) '+$extras',
        ];
        subtitle = parts.isEmpty
            ? bridge.tr(key: 'order.configure')
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
