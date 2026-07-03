import 'package:design_system/src/icons.dart';
import 'package:design_system/src/responsive.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:design_system/src/touch.dart';
import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

/// Icon side length inside the state badge circle.
const double _stateIconSize = 44;

/// Centered icon + title (+optional message) for empty grids and lists —
/// the natives' `EmptyState` (SharedComponents.kt), dressed with the badge
/// circle so it reads as calm, not broken.
///
/// ```dart
/// EmptyState(
///   icon: 'tray',
///   title: t('drafts.empty'),
/// )
/// ```
class EmptyState extends StatelessWidget {
  /// Creates a centered empty-state placeholder.
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.lottieAsset,
    this.lottieSize = 140,
    super.key,
  });

  /// [MadarIcon] catalog name (e.g. `'tray'`, `'doc.text'`) — the fallback
  /// visual when [lottieAsset] is null.
  final String icon;

  /// Short localized headline (e.g. "No drafts yet").
  final String title;

  /// Optional supporting line under the title.
  final String? message;

  /// Optional Lottie asset name under `design_system`'s `assets/lottie/`
  /// (e.g. `'no_results'`, `'empty_cart'`). When set it loops in place of the
  /// icon badge — the cart + search use this, everywhere else the [icon].
  final String? lottieAsset;

  /// Rendered side length of the Lottie animation.
  final double lottieSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return _CenteredStateColumn(
      children: [
        if (lottieAsset case final asset?)
          SizedBox(
            width: lottieSize,
            height: lottieSize,
            child: Lottie.asset(
              'assets/lottie/$asset.json',
              package: 'design_system',
              fit: BoxFit.contain,
              repeat: true,
            ),
          )
        else
          _StateBadge(
            icon: icon,
            iconTint: colors.textMuted,
            background: colors.surfaceAlt,
          ),
        const SizedBox(height: Space.md),
        Text(
          title,
          style: MadarType.title.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        if (message case final message?) ...[
          const SizedBox(height: Space.xs),
          Text(
            message,
            style: MadarType.bodySm.copyWith(color: colors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// Centered failure state with a prominent retry button — visually
/// distinct from [EmptyState] (danger badge + accent action) so a broken
/// screen never masquerades as merely empty.
///
/// ```dart
/// ErrorState(
///   message: t('history.load_failed'),
///   retryLabel: t('common.retry'),
///   onRetry: reload,
/// )
/// ```
class ErrorState extends StatelessWidget {
  /// Creates a centered error state with a retry action.
  const ErrorState({
    required this.message,
    required this.onRetry,
    required this.retryLabel,
    super.key,
  });

  /// Localized failure description.
  final String message;

  /// Invoked when the retry button is tapped.
  final VoidCallback onRetry;

  /// Localized label for the retry button.
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return _CenteredStateColumn(
      children: [
        _StateBadge(
          icon: 'exclamationmark.triangle',
          iconTint: colors.danger,
          background: colors.dangerBg,
        ),
        const SizedBox(height: Space.md),
        Text(
          message,
          style: MadarType.body.copyWith(color: colors.textPrimary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.xl),
        TactileScale(
          onTap: onRetry,
          child: Container(
            height: Metrics.buttonHeight,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.xxl,
            ),
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MadarIcon(
                  'arrow.clockwise',
                  tint: colors.textOnAccent,
                  size: IconSize.lg,
                ),
                const SizedBox(width: Space.sm),
                Text(
                  retryLabel,
                  style: MadarType.title.copyWith(color: colors.textOnAccent),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared centered scaffold: fills its parent, caps content at
/// [Responsive.formMaxWidth], and stacks [children] vertically centered.
class _CenteredStateColumn extends StatelessWidget {
  const _CenteredStateColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Scrollable so an oversized message (e.g. a boot-failure stack trace)
    // never overflows — small content still centers.
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Responsive.formMaxWidth),
          child: Padding(
            padding: const EdgeInsetsDirectional.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// The circular icon badge shared by both states.
class _StateBadge extends StatelessWidget {
  const _StateBadge({
    required this.icon,
    required this.iconTint,
    required this.background,
  });

  final String icon;
  final Color iconTint;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: MadarIcon(icon, tint: iconTint, size: _stateIconSize),
    );
  }
}
