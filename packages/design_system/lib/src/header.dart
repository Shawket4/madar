import 'package:design_system/src/icons.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:design_system/src/touch.dart';
import 'package:flutter/material.dart';

/// Content height of the bar, below the status-bar inset.
const double _headerHeight = 60;

/// THE screen header. One look everywhere: a surface bar that paints all
/// the way up under the notification bar (content inset by the status-bar
/// height), a mirrored back tile, a bold title with an optional subtitle,
/// trailing actions, and a hairline base.
///
/// Screens place it as the FIRST child of their Scaffold body column and
/// do NOT wrap it in SafeArea — the header owns the top inset:
///
/// ```dart
/// Scaffold(
///   body: Column(children: [
///     MadarHeader(title: tr('cash.title'), onBack: () => Navigator.maybePop(context)),
///     Expanded(child: SafeArea(top: false, child: content)),
///   ]),
/// )
/// ```
class MadarHeader extends StatelessWidget {
  const MadarHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.tinted = false,
  });

  /// Screen title — [MadarType.h3] weight-boosted, single line.
  final String title;

  /// Muted second line (e.g. the branch, a count, a date range).
  final String? subtitle;

  /// Shows the mirrored back tile when set. Use `Navigator.maybePop`.
  final VoidCallback? onBack;

  /// Trailing widgets, laid end-aligned with [Space.sm] gaps.
  final List<Widget> actions;

  /// Accent-washed variant for hero surfaces (e.g. KDS station header).
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return Container(
      padding: EdgeInsetsDirectional.only(
        top: topInset,
        start: Space.lg,
        end: Space.lg,
      ),
      decoration: BoxDecoration(
        color: tinted ? colors.accentBg : colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.borderLight),
        ),
      ),
      child: SizedBox(
        height: _headerHeight,
        child: Row(
          children: [
            if (onBack != null) ...[
              TactileScale(
                onTap: onBack,
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: MadarIcon(
                    'chevron.backward',
                    tint: colors.textPrimary,
                    size: IconSize.lg,
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.h3.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.labelSm.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            for (final action in actions) ...[
              const SizedBox(width: Space.sm),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

/// A round header action tile — pair with [MadarHeader.actions] so every
/// screen's trailing affordances share one look.
class MadarHeaderAction extends StatelessWidget {
  const MadarHeaderAction({
    required this.icon,
    required this.onTap,
    super.key,
    this.tint,
    this.tooltip,
  });

  final String icon;
  final VoidCallback onTap;
  final Color? tint;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final tile = TactileScale(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: MadarIcon(
          icon,
          tint: tint ?? colors.textSecondary,
          size: IconSize.lg,
        ),
      ),
    );
    final tip = tooltip;
    if (tip == null) return tile;
    return Tooltip(message: tip, child: tile);
  }
}
