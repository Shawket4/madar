import 'package:design_system/src/brand.dart';
import 'package:design_system/src/responsive.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:flutter/widgets.dart';

/// Panel inset (natives: 48.dp).
const double _panelPad = 48;

/// Faded watermark mark: size / offset / alpha (natives: 360.dp, 80.dp, 0.05).
const double _watermarkSize = 360;
const double _watermarkOffset = 80;
const double _watermarkAlpha = 0.05;

/// Lockup height (natives: 28.dp).
const double _lockupHeight = 28;

/// Headline type (natives: 44.sp black, 50.sp line height).
const double _headlineSize = 44;
const double _headlineLineHeight = 50;

/// Tagline width cap (natives: 300.dp).
const double _taglineMaxWidth = 300;

/// Footer accent dot (natives: 6.dp).
const double _footerDot = 6;

/// Footer copyright line — a literal on the natives too (not localized).
const String _copyright = '© 2026 Madar';

/// The brand half of a wide (tablet / desktop) sign-in split: watermark,
/// lockup, headline, tagline. One panel for every Madar surface — the POS
/// login and open-till, and Dawam — so they read as one onboarding act.
/// Strings arrive localised (the core's `brand.*`, or a product's own).
class MadarBrandPanel extends StatelessWidget {
  const MadarBrandPanel({
    required this.headline,
    required this.tagline,
    this.arabic = false,
    this.lockup,
    this.watermark,
    super.key,
  });

  final String headline;
  final String tagline;

  /// The product's lockup at the top (default: Madar's).
  final Widget? lockup;

  /// The faded mark behind the panel (default: Madar's symbol).
  final Widget? watermark;

  /// Render the Arabic lockup variant (the natives pick by core locale).
  final bool arabic;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ColoredBox(
      color: colors.surfaceAlt,
      child: Stack(
        children: [
          // Faded watermark mark — offset like the natives, start-anchored so
          // it mirrors in RTL.
          PositionedDirectional(
            start: _watermarkOffset,
            top: _watermarkOffset,
            child:
                watermark ??
                const MadarSymbol(
                  size: _watermarkSize,
                  opacity: _watermarkAlpha,
                ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.all(_panelPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: _lockupHeight,
                  child: FittedBox(
                    alignment: AlignmentDirectional.centerStart,
                    child: lockup ?? MadarLockup(arabic: arabic),
                  ),
                ),
                const Spacer(),
                Text(
                  headline,
                  style: MadarType.display.copyWith(
                    fontSize: _headlineSize,
                    height: _headlineLineHeight / _headlineSize,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: Space.lg),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _taglineMaxWidth),
                  child: Text(
                    tagline,
                    style: MadarType.title.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                const Spacer(),
                Row(
                  spacing: Space.sm,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(dimension: _footerDot),
                    ),
                    Text(
                      _copyright,
                      style: MadarType.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The sign-in scaffold: on a wide container the brand panel beside the
/// form (at [Responsive.brandPanelRatio]); on a phone the form alone,
/// centred, with [compactHeader] (a lockup) above it.
class MadarBrandSplit extends StatelessWidget {
  const MadarBrandSplit({
    required this.brand,
    required this.form,
    this.compactHeader,
    this.brandRatio = Responsive.brandPanelRatio,
    this.formMaxWidth = 400,
    super.key,
  });

  final Widget brand;
  final Widget form;
  final Widget? compactHeader;
  final double brandRatio;
  final double formMaxWidth;

  Widget _form({required bool wide}) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: Space.xxl, vertical: 48),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: formMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!wide && compactHeader != null) ...[
              compactHeader!,
              const SizedBox(height: Space.xxl),
            ],
            form,
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ResponsiveBuilder(
    builder: (context, info) {
      if (!info.isWide) return SafeArea(child: _form(wide: false));
      final flex = (brandRatio * 100).round();
      return Row(
        children: [
          Expanded(flex: flex, child: brand),
          Expanded(
            flex: 100 - flex,
            child: SafeArea(child: _form(wide: true)),
          ),
        ],
      );
    },
  );
}
