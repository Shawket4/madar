import 'package:design_system/src/format.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/motion.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:flutter/widgets.dart';

/// Money formatting — minor units to a display string. A thin front for
/// [MadarFormat.money], which mirrors the core's `display::format_money`.
abstract final class Money {
  /// Formats [minor] units as `"EGP 1,234.50"` — thousands grouped, two
  /// decimals, the uppercased [currency] code before the amount, a U+2212
  /// minus for negatives (`"−EGP 50.00"`), `+` when [signed]. An empty
  /// [currency] yields just the amount (`"1,234.50"`).
  ///
  /// [locale] `ar` gives the Arabic shape (`"<LRI>1,234.50<PDI> ج.م"`). It defaults to
  /// English so a string built OUTSIDE a widget keeps one predictable shape;
  /// [MoneyText] passes the app's language itself.
  static String format(
    int minor, {
    String currency = '',
    String locale = 'en',
    bool signed = false,
  }) => MadarFormat.money(
    minor,
    currency: currency,
    locale: locale,
    signed: signed,
  );

  /// A tax or service-charge rate as a percentage, for a receipt or a bill
  /// line: `0.14` → `"14"`, `0.125` → `"12.5"`.
  ///
  /// Rounded to a tenth FIRST, because `0.14 * 100` is `14.000000000000002`
  /// in a double and "14.0%" on a receipt looks like a rate nobody set. The
  /// trailing `.0` is then dropped, so a whole rate reads whole.
  ///
  /// The rate is a fraction, never a percentage — the same convention the
  /// core and the backend use for every `*_rate` on the wire.
  static String ratePercent(double rate) {
    final pct = (rate * 1000).round() / 10;
    return pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(1);
  }
}

/// An amount rendered with [Money.format] in the Madar money type scale.
///
/// Defaults to [MadarType.money] (tabular figures so columns align) in the
/// theme's accent. Pass [color] or a [style] carrying a color to override.
///
/// Localised: in Arabic the currency reads `ج.م` after an LTR-isolated
/// figure, laid out in the ambient direction; in English the string is laid
/// out LTR. Pass [locale] only to pin a language (a receipt preview).
class MoneyText extends StatelessWidget {
  /// Creates a money display for [minor] units of [currency].
  const MoneyText(
    this.minor, {
    this.currency = '',
    this.style,
    this.color,
    this.signed = false,
    this.locale,
    this.textAlign,
    super.key,
  });

  /// The amount in minor units (e.g. piastres/cents). May be negative.
  final int minor;

  /// The ISO currency code; empty hides the label.
  final String currency;

  /// The text style; defaults to [MadarType.money]. Its color, when set,
  /// wins over the default accent (but an explicit [color] wins over both).
  final TextStyle? style;

  /// The text color; defaults to `context.madarColors.accent`.
  final Color? color;

  /// Prefix `+` on a positive amount — a ledger line.
  final bool signed;

  /// Language override; null follows the app.
  final String? locale;

  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final base = style ?? MadarType.money;
    final resolved = color ?? base.color ?? context.madarColors.accent;
    final lang = locale ?? MadarFormat.localeOf(context);
    final ar = MadarFormat.isArabic(lang);
    return Text(
      Money.format(minor, currency: currency, locale: lang, signed: signed),
      style: base.copyWith(color: resolved),
      textAlign: textAlign,
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
    );
  }
}

/// A [MoneyText] whose figure cross-fades and lifts a few pixels when the
/// amount changes — the pre-rebuild cart total. Reduced motion swaps the
/// figure in place.
class AnimatedMoneyText extends StatelessWidget {
  /// Creates the animated figure; the arguments are [MoneyText]'s.
  const AnimatedMoneyText(
    this.minor, {
    this.currency = '',
    this.style,
    this.color,
    super.key,
  });

  final int minor;
  final String currency;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : MotionSpec.standardDuration,
      switchInCurve: MotionSpec.standardCurve,
      switchOutCurve: MotionSpec.standardCurve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: MoneyText(
        minor,
        key: ValueKey<String>('$currency$minor'),
        currency: currency,
        style: style,
        color: color,
      ),
    );
  }
}
