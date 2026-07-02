/// The brand half of the wide (tablet / desktop) split — shared by Login and
/// Open-Shift on the natives so the two screens read as one continuous
/// onboarding act (BrandPanel.kt / SwiftUI BrandPanel). Native metrics that
/// fall between the token steps are kept verbatim as documented constants.
library;

import 'package:design_system/design_system.dart';
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

class BrandPanel extends StatelessWidget {
  const BrandPanel({required this.tr, this.arabic = false, super.key});

  /// Core-backed localizer (`bridge.tr`) — the panel's headline/tagline are
  /// core strings, and this widget stays bridge-agnostic.
  final String Function(String key) tr;

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
          const PositionedDirectional(
            start: _watermarkOffset,
            top: _watermarkOffset,
            child: Opacity(
              opacity: _watermarkAlpha,
              child: MadarSymbol(size: _watermarkSize),
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
                    child: MadarLockup(arabic: arabic),
                  ),
                ),
                const Spacer(),
                Text(
                  tr('brand.headline'),
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
                    tr('brand.tagline'),
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
