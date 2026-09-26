import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Under the item sheet's title: the "Last: Large · Oat milk" chip, then the
/// slim "Make it a meal" banner. Either may be absent; with neither, nothing.
class ItemSheetHeaderExtras extends StatelessWidget {
  const ItemSheetHeaderExtras({
    required this.currency,
    this.last,
    this.onApplyLast,
    this.meal,
    this.onMeal,
    super.key,
  });

  final String currency;

  /// The item as this device last sold it (the core's words); null hides
  /// the chip.
  final LastItemConfig? last;
  final VoidCallback? onApplyLast;

  /// The meal the item upgrades to, quoted for the sheet's current picks;
  /// null hides the banner.
  final MealOffer? meal;
  final VoidCallback? onMeal;

  bool get isEmpty => last == null && meal == null;

  @override
  Widget build(BuildContext context) {
    final last = this.last;
    final meal = this.meal;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (last != null)
          MadarChip(
            key: const ValueKey('item-last-config'),
            label: last.text,
            glyph: MadarGlyph.refresh,
            onTap: onApplyLast ?? () {},
          ),
        if (last != null && meal != null) const SizedBox(height: Space.sm),
        if (meal != null)
          ItemSheetMealBanner(
            key: const ValueKey('make-it-a-meal'),
            offer: meal,
            currency: currency,
            onTap: onMeal ?? () {},
          ),
      ],
    );
  }
}

/// "Make it a meal with Side + Drink  +EGP 100 · save EGP 60": one slim
/// pressable row (two short lines on a phone). Every figure is the core's —
/// the delta and the saving come from its combo quote for the item as it is
/// configured on the sheet; this only formats them.
class ItemSheetMealBanner extends ConsumerWidget {
  const ItemSheetMealBanner({
    required this.offer,
    required this.currency,
    required this.onTap,
    super.key,
  });

  final MealOffer offer;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final locale = MadarFormat.localeOf(context);
    String money(int minor) =>
        Money.format(minor, currency: currency, locale: locale);

    final title = bridge.tr(key: 'meal.make_it');
    final hint = offer.slotHint.trim();
    final plus = '+${money(offer.deltaMinor)}';
    final save = offer.savingMinor > 0
        ? bridge
              .tr(key: 'meal.save')
              .replaceAll('{amount}', money(offer.savingMinor))
        : null;

    final titleRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          style: MadarType.bodySm.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.accent,
          ),
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(width: Space.xs),
          Flexible(
            child: MadarClippedText(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ],
    );
    // Each figure wraps on its own, so a narrow sheet never overflows.
    final figures = <Widget>[
      Text(
        plus,
        maxLines: 1,
        style: MadarType.bodySm.copyWith(
          fontWeight: FontWeight.w700,
          color: colors.accent,
        ),
      ),
      if (save != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '·',
              style: MadarType.bodySm.copyWith(color: colors.textMuted),
            ),
            const SizedBox(width: Space.sm),
            Flexible(
              child: MadarClippedText(
                save,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.success,
                ),
              ),
            ),
          ],
        ),
    ];

    return Semantics(
      button: true,
      label: [title, hint, plus, ?save].where((s) => s.isNotEmpty).join(' '),
      excludeSemantics: true,
      child: TactileScale(
        onTap: () {
          MadarHaptics.impact();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: Metrics.closeButton),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          decoration: BoxDecoration(
            color: colors.accentBg,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: colors.accent.withValues(alpha: Opacities.border),
            ),
          ),
          // The figures follow the title on one line when they fit (an
          // iPad) and wrap under it when they do not (a phone).
          child: Row(
            children: [
              MadarIcon('fork.knife', tint: colors.accent),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: Space.sm,
                  runSpacing: 2,
                  children: [titleRow, ...figures],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
