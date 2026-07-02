import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:flutter/widgets.dart';

/// Money formatting — minor units to a display string. Identical to the
/// Kotlin/Swift `Money` natives so totals read the same on every platform.
abstract final class Money {
  /// Formats [minor] units as `"EGP 12.50"` — two decimals, the uppercased
  /// [currency] code before the amount, and a leading `-` for negatives
  /// (cash-out). An empty [currency] yields just the amount (`"12.50"`).
  static String format(int minor, {String currency = ''}) {
    final neg = minor < 0;
    final cents = minor.abs();
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    final amount = '${neg ? '-' : ''}$whole.$frac';
    final code = currency.toUpperCase();
    return code.isEmpty ? amount : '$code $amount';
  }
}

/// An amount rendered with [Money.format] in the Madar money type scale.
///
/// Defaults to [MadarType.money] (tabular figures so columns align) in the
/// theme's accent teal — money is bold teal per the design direction. Pass
/// [color] or a [style] carrying a color to override.
class MoneyText extends StatelessWidget {
  /// Creates a money display for [minor] units of [currency].
  const MoneyText(
    this.minor, {
    this.currency = '',
    this.style,
    this.color,
    super.key,
  });

  /// The amount in minor units (e.g. piastres/cents). May be negative.
  final int minor;

  /// The currency code shown uppercased before the amount; empty hides it.
  final String currency;

  /// The text style; defaults to [MadarType.money]. Its color, when set,
  /// wins over the default accent (but an explicit [color] wins over both).
  final TextStyle? style;

  /// The text color; defaults to `context.madarColors.accent`.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = style ?? MadarType.money;
    final resolved = color ?? base.color ?? context.madarColors.accent;
    return Text(
      Money.format(minor, currency: currency),
      style: base.copyWith(color: resolved),
      textDirection: TextDirection.ltr,
    );
  }
}
