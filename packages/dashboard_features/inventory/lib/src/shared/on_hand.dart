/// An on-hand figure (the web's `on-hand.tsx`). Below zero is allowed (waste
/// or a sale recorded by a till that could not see the book stock), so it is
/// never hidden or clamped: the negative number is tinted, semibold, and
/// carries a "Below zero" pill.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'inventory_labels.dart';
import 'inventory_lib.dart';

class OnHand extends ConsumerWidget {
  const OnHand({
    required this.qty,
    this.unit,
    this.pill = true,
    this.style,
    super.key,
  });

  final num qty;
  final String? unit;

  /// Show the "Below zero" pill beside a negative figure.
  final bool pill;

  /// The figure's style (defaults to the body text).
  final TextStyle? style;

  /// The tint of a below-zero figure (`belowZeroClass`): danger pulled toward
  /// the foreground, as the web's 60% colour-mix.
  static Color negativeColor(BuildContext context) =>
      DashTone.danger.foreground(context.madarColors);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(formatProvider);
    final below = isBelowZero(qty);
    final base = style ?? DashType.body;
    final text = Text(
      qtyWithUnit(f, qty, unit),
      textDirection: TextDirection.ltr,
      style: below
          ? base.copyWith(
              color: negativeColor(context),
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            )
          : base.copyWith(
              color: base.color ?? context.madarColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
    );
    if (!below || !pill) return text;
    return Wrap(
      spacing: Space.xs + DashMetrics.hair,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        text,
        DashStatusPill(
          label: context.t('inventory.catalog.belowZero'),
          tone: DashTone.danger,
          small: true,
        ),
      ],
    );
  }
}
