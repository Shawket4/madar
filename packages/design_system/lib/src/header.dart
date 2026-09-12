import 'package:design_system/src/controls.dart';
import 'package:design_system/src/glyphs.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:flutter/material.dart';

/// THE in-page header — system v2. A 48px row ON the paper (not a bar): a
/// 44 back tile when the screen was pushed, the title at 28 bold, an
/// optional muted subtitle, and end-aligned actions. Sits under the chrome's
/// top bar, so it paints no status-bar inset of its own unless [safeTop] is
/// set (a full-screen route with no shell above it).
///
/// ```dart
/// MadarHeader(title: tr('till.title'), onBack: () => Navigator.maybePop(context))
/// ```
class MadarHeader extends StatelessWidget {
  const MadarHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.below,
    this.tinted = false,
    this.safeTop = false,
    this.backLabel,
  });

  /// Screen title — [MadarType.h1], single line.
  final String title;

  /// Muted second line (the branch, a count, a date range).
  final String? subtitle;

  /// Shows the mirrored back tile when set. Use `Navigator.maybePop`.
  final VoidCallback? onBack;

  /// Trailing widgets, laid end-aligned with [Space.md] gaps.
  final List<Widget> actions;

  /// A full-width row under the title — a screen's at-a-glance summary that
  /// wants the whole width rather than what is left beside the actions.
  final Widget? below;

  /// Kept for callers; the v2 header has one look. Ignored.
  final bool tinted;

  /// Pads the status-bar inset — only for a route with no top bar above it.
  final bool safeTop;

  /// What the back tile does, for a screen reader.
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final topInset = safeTop ? MediaQuery.viewPaddingOf(context).top : 0.0;
    return Padding(
      padding: EdgeInsetsDirectional.only(top: topInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Metrics.headerHeight),
            child: Row(
              spacing: Space.lg,
              children: [
                if (onBack != null)
                  MadarGlyphTile(
                    glyph: MadarGlyph.chevronBack,
                    onTap: onBack!,
                    semanticLabel: backLabel,
                  ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.h1.copyWith(color: colors.textPrimary),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            top: Space.xs,
                          ),
                          child: Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MadarType.bodySm.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          if (below != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: Space.md),
              child: below,
            ),
        ],
      ),
    );
  }
}

/// A header action — a 44 glyph tile. Pair with [MadarHeader.actions] so
/// every screen's trailing affordances share one look.
class MadarHeaderAction extends StatelessWidget {
  const MadarHeaderAction({
    required this.onTap,
    super.key,
    this.glyph,
    this.icon,
    this.tint,
    this.tooltip,
  }) : assert(glyph != null || icon != null, 'an action needs a glyph');

  final MadarGlyph? glyph;

  /// Legacy SF-Symbol name. Prefer [glyph].
  final String? icon;
  final VoidCallback onTap;
  final Color? tint;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tile = MadarGlyphTile(
      glyph: glyph,
      icon: icon,
      onTap: onTap,
      tint: tint,
      semanticLabel: tooltip,
    );
    final tip = tooltip;
    if (tip == null) return tile;
    return Tooltip(message: tip, child: tile);
  }
}
