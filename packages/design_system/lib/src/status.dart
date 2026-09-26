/// State words and headline figures: [MadarStatus] / [MadarStatusPill],
/// [MadarStatCard], and [MadarSpinner] — the kit's one loading indicator.
/// docs/design/SPEC.md §6 (cards), §10 (pills), §11 (loading).
library;

import 'package:design_system/src/clipped_text.dart';
import 'package:design_system/src/controls.dart';
import 'package:design_system/src/glyphs.dart';
import 'package:design_system/src/money.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:flutter/material.dart';

/// A state as the UI names it: a localised word, a tone and a glyph. The
/// GLYPH IS NOT OPTIONAL in effect — state never rests on colour alone, so a
/// status with no glyph borrows its tone's ([MadarStatus.glyphFor]).
///
/// The core decides WHAT the state is; a screen maps the core's status to one
/// of these and nothing else.
@immutable
class MadarStatus {
  const MadarStatus(this.label, {this.tone = MadarTone.neutral, this.glyph});

  /// Already localised ("Closed", "مغلقة").
  final String label;
  final MadarTone tone;
  final MadarGlyph? glyph;

  /// The glyph drawn: [glyph], or the tone's default.
  MadarGlyph get resolvedGlyph => glyph ?? glyphFor(tone);

  /// Each tone's default glyph — distinguishable in greyscale.
  static MadarGlyph glyphFor(MadarTone tone) => switch (tone) {
    MadarTone.neutral => MadarGlyph.hollow,
    MadarTone.accent => MadarGlyph.half,
    MadarTone.success => MadarGlyph.checkCircle,
    MadarTone.warning => MadarGlyph.alertTriangle,
    MadarTone.danger => MadarGlyph.xCircle,
  };

  @override
  bool operator ==(Object other) =>
      other is MadarStatus &&
      other.label == label &&
      other.tone == tone &&
      other.glyph == glyph;

  @override
  int get hashCode => Object.hash(label, tone, glyph);
}

/// Height of a [MadarStatusPill].
const double _pillHeight = 26;

/// THE status pill: glyph + word on the tone's wash, fully rounded, sentence
/// case. Where [MadarTag] SHOUTS a transient state on a card ("NEW"), the pill
/// states a record's standing in a row or a table cell ("Closed", "Short").
class MadarStatusPill extends StatelessWidget {
  const MadarStatusPill(this.status, {super.key});

  /// Convenience for a one-off pill.
  MadarStatusPill.of(
    String label, {
    MadarTone tone = MadarTone.neutral,
    MadarGlyph? glyph,
    Key? key,
  }) : this(
         MadarStatus(label, tone: tone, glyph: glyph),
         key: key,
       );

  final MadarStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = status.tone.color(colors);
    return Semantics(
      label: status.label,
      excludeSemantics: true,
      child: Container(
        height: _pillHeight,
        padding: const EdgeInsetsDirectional.only(start: 8, end: 10),
        decoration: BoxDecoration(
          color: status.tone.tint(colors),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            MadarGlyphIcon(status.resolvedGlyph, size: IconSize.xs, color: fg),
            Flexible(
              child: MadarClippedText(
                status.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: MadarType.bodySm.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// THE loading indicator — a 20 ring, 2.5 stroke. The policy (SPEC §11): a
/// SPINNER lives only inside a control that is working (a button, a pill, a
/// table's load-more footer). Anything that is waiting for CONTENT shows
/// skeletons. No screen builds a raw `CircularProgressIndicator`.
class MadarSpinner extends StatelessWidget {
  const MadarSpinner({this.size = 20, this.color, super.key});

  final double size;

  /// Defaults to the secondary text colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(
        color: color ?? context.madarColors.textSecondary,
        strokeWidth: size >= 20 ? 2.5 : 2,
      ),
    );
  }
}

/// THE stat card: a tracked label, one headline figure in mono, an optional
/// meta line and an optional pill. A Till's "Cash expected", a Z report's
/// "Orders". Set [minor] for money (localised, grouped) or [value] for any
/// other figure.
///
/// ```dart
/// MadarStatCard(label: t('till.sales'), minor: 623000, currency: 'EGP',
///   meta: t('till.orders_count'))
/// ```
class MadarStatCard extends StatelessWidget {
  const MadarStatCard({
    required this.label,
    this.value,
    this.minor,
    this.currency = '',
    this.meta,
    this.glyph,
    this.status,
    this.tone,
    this.onTap,
    this.compact = false,
    super.key,
  }) : assert(
         (value == null) != (minor == null),
         'a stat card shows exactly one of value or minor',
       );

  /// Localised; drawn uppercase and tracked like a section label.
  final String label;

  /// A non-money figure, set as given ("42", "1h 05m").
  final String? value;

  /// A money figure in minor units.
  final int? minor;
  final String currency;

  /// A muted line under the figure.
  final String? meta;

  /// A glyph ahead of the label.
  final MadarGlyph? glyph;

  /// A pill at the card's trailing top corner ("Short").
  final MadarStatus? status;

  /// Colours the figure (danger for a shortfall). Null is primary text.
  final MadarTone? tone;

  final VoidCallback? onTap;

  /// 20 figure instead of 30 — a row of four on a phone.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final figureColor = tone == null ? colors.textPrimary : tone!.color(colors);
    final figureStyle = (compact ? MadarType.moneyMd : MadarType.numXl)
        .copyWith(color: figureColor, height: 1.1);
    return MadarCard(
      onTap: onTap,
      padding: EdgeInsetsDirectional.all(compact ? Space.lg : Space.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (glyph != null) ...[
                MadarGlyphIcon(
                  glyph!,
                  size: IconSize.sm,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: Space.sm),
              ],
              Expanded(
                child: MadarClippedText(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.label.copyWith(
                    color: colors.textSecondary,
                    letterSpacing: MadarType.tracking,
                  ),
                ),
              ),
              if (status != null) MadarStatusPill(status!),
            ],
          ),
          SizedBox(height: compact ? Space.sm : Space.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: minor != null
                ? MoneyText(
                    minor!,
                    currency: currency,
                    style: figureStyle,
                    color: figureColor,
                  )
                : Text(value!, maxLines: 1, style: figureStyle),
          ),
          if (meta != null) ...[
            const SizedBox(height: Space.xs),
            Text(
              // Wraps, never ellipsizes: the meta is a breakdown the
              // figure is the sum of, and a cut term hides where cash went.
              meta!,
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
