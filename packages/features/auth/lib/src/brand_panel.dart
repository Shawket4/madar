import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Panel inner padding (natives: 48.dp).
const double _panelPad = 48;

/// Faded watermark mark — size / inset / alpha (natives: 360.dp @ 80.dp,
/// alpha 0.05).
const double _watermarkSize = 360;
const double _watermarkInset = 80;
const double _watermarkAlpha = 0.05;

/// Lockup height (natives: 28.dp).
const double _lockupHeight = 28;

/// Headline metrics (natives: 44.sp Black, 50.sp line height).
const double _headlineSize = 44;
const double _headlineLineHeight = 50;

/// Tagline width cap (natives: 300.dp).
const double _taglineMaxWidth = 300;

/// Footer accent dot diameter (natives: 6.dp).
const double _footerDot = 6;

/// The brand half of the wide (tablet / desktop) split — shared by the auth
/// screens so setup, login, and station commissioning read as one continuous
/// onboarding act. Mirror of the natives' `BrandPanel`.
class BrandPanel extends StatelessWidget {
  /// Creates the brand panel.
  const BrandPanel({required this.core, super.key});

  /// The core handle — used only for localized brand copy.
  final MadarCore core;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    String t(String key) => core.bridge.tr(key: key);

    return ColoredBox(
      color: colors.surfaceAlt,
      child: Stack(
        children: [
          // Faded watermark mark — inset from the top/leading edge like the
          // natives, mirrored under RTL.
          const PositionedDirectional(
            start: _watermarkInset,
            top: _watermarkInset,
            child: Opacity(
              opacity: _watermarkAlpha,
              child: MadarSymbol(size: _watermarkSize),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(_panelPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  height: _lockupHeight,
                  child: FittedBox(
                    alignment: AlignmentDirectional.centerStart,
                    child: MadarLockup(),
                  ),
                ),
                const Spacer(),
                Text(
                  t('brand.headline'),
                  style: MadarType.display.copyWith(
                    fontSize: _headlineSize,
                    height: _headlineLineHeight / _headlineSize,
                    letterSpacing: 0,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: Space.lg),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _taglineMaxWidth,
                  ),
                  child: Text(
                    t('brand.tagline'),
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
                    Container(
                      width: _footerDot,
                      height: _footerDot,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.accent,
                      ),
                    ),
                    // Literal in the natives too — no i18n key exists.
                    Text(
                      '© 2026 Madar',
                      style: MadarType.label.copyWith(
                        fontWeight: FontWeight.w500,
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
