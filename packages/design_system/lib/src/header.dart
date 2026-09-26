import 'package:design_system/src/clipped_text.dart';
import 'package:design_system/src/controls.dart';
import 'package:design_system/src/glyphs.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:flutter/material.dart';

/// Fixed header geometry — docs/design/SPEC.md §2. Every number a test pins.
abstract final class MadarHeaderMetrics {
  /// The title row. The title is centred in it, so its baseline is fixed no
  /// matter what else the header carries.
  static const double titleRow = Metrics.headerHeight;

  /// The leading slot: a 44 back tile and the gap after it.
  static const double leadingSlot = Metrics.glyphTile;
  static const double leadingGap = Space.md;

  /// Where the title starts, measured from the header's leading edge, when
  /// a back tile is shown: 44 + 12 = 56. With no back tile the title starts
  /// at the leading edge — a page title carries no icon.
  static const double titleInset = leadingSlot + leadingGap;

  /// Gap from the title row to the subtitle line.
  static const double subtitleGap = 2;

  /// Gap from the title block to the [MadarHeader.below] slot.
  static const double belowGap = Space.md;

  /// Space between trailing actions.
  static const double actionGap = Space.sm;
}

/// THE in-page header — system v2, spec geometry.
///
/// ```text
/// ┌ leading slot 44 ┐12┌ title (h1 28/700, centred in a 48 row) ─┐ actions ┐
/// │  ‹ (if pushed)  │  │ subtitle (13/500) — BELOW, never shifts │  44 44   │
/// └─────────────────┘  └─────────────────────────────────────────┘          ┘
///                       below slot (full width, 12 under)
/// ```
///
/// * The title's rect depends on nothing but the header's width: not on the
///   subtitle (which grows the header downward), not on actions (they
///   centre on the title row).
/// * Sits under the chrome's top bar, so it pads no status-bar inset unless
///   [safeTop] is set (a full-screen route with no shell above it).
///
/// Prefer `MadarPageScaffold` with a `width:` — it builds this header on the
/// spec grid. Use it directly only for a sheet or a split view's pane.
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

  /// Screen title — [MadarType.h1], single line, ellipsised.
  final String title;

  /// Muted second line (the branch, a count, a date range). Laid BELOW the
  /// title row; the title does not move when it appears.
  final String? subtitle;

  /// Shows the mirrored back tile in the leading slot when set.
  final VoidCallback? onBack;

  /// Trailing widgets — [MadarHeaderAction]s or compact buttons — centred on
  /// the title row, [MadarHeaderMetrics.actionGap] apart.
  final List<Widget> actions;

  /// A full-width row under the title block — a search field, a segment
  /// strip, a summary.
  final Widget? below;

  /// Ignored.
  final bool tinted;

  /// Pads the status-bar inset — only for a route with no top bar above it.
  final bool safeTop;

  /// What the back tile does, for a screen reader.
  final String? backLabel;

  /// The key on the title [Text] — what geometry tests measure.
  static const titleKey = ValueKey<String>('madar.header.title');

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final topInset = safeTop ? MediaQuery.viewPaddingOf(context).top : 0.0;
    final slot = onBack != null
        ? MadarGlyphTile(
            glyph: MadarGlyph.chevronBack,
            onTap: onBack!,
            semanticLabel: backLabel,
          )
        : null;
    final showSlot = slot != null;

    return Padding(
      padding: EdgeInsetsDirectional.only(top: topInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A FLOOR, not a clamp: the spec's actions are 44 tiles and compact
          // controls, which centre inside 48 and leave the title where it is.
          // A taller control (a 52 search field — which belongs in [below])
          // grows the row rather than being squeezed; that is the one case
          // the title moves, and the spec forbids it.
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: MadarHeaderMetrics.titleRow,
            ),
            child: Row(
              children: [
                if (showSlot) ...[
                  SizedBox(
                    width: MadarHeaderMetrics.leadingSlot,
                    height: MadarHeaderMetrics.leadingSlot,
                    child: slot,
                  ),
                  const SizedBox(width: MadarHeaderMetrics.leadingGap),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: MadarClippedText(
                      title,
                      key: titleKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.h1.copyWith(color: colors.textPrimary),
                    ),
                  ),
                ),
                for (final action in actions) ...[
                  const SizedBox(width: MadarHeaderMetrics.actionGap),
                  action,
                ],
              ],
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: EdgeInsetsDirectional.only(
                top: MadarHeaderMetrics.subtitleGap,
                start: showSlot ? MadarHeaderMetrics.titleInset : 0,
              ),
              child: MadarClippedText(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.bodySm.copyWith(color: colors.textSecondary),
              ),
            ),
          if (below != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                top: MadarHeaderMetrics.belowGap,
              ),
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

  /// What the action does: read out, and shown on a long press by the tile
  /// itself — the word the glyph has no room for.
  final String? tooltip;

  @override
  Widget build(BuildContext context) => MadarGlyphTile(
    glyph: glyph,
    icon: icon,
    onTap: onTap,
    tint: tint,
    semanticLabel: tooltip,
  );
}
