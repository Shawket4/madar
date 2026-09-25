/// THE list row, in the four shapes the app's lists actually need —
/// docs/design/SPEC.md §7. Every one is 64 tall, sits flush inside a card
/// with [MadarHairline.row]s between siblings, and shares one frame:
///
/// ```text
/// ▌rail │20│ leading │16│ title ………………………… value │12│ trailing │12│ › │20│
///                      meta ……………………………… pill
/// ```
///
/// * [MadarListRow.nav] — goes somewhere: glyph, title, optional meta and a
///   value word, chevron. Settings, Me, the Till's links.
/// * [MadarListRow.ledger] — money in or out: a sign disc (+ / −, never
///   colour alone), title, meta, the SIGNED amount. Cash in/out, a Z report.
/// * [MadarListRow.bill] — a record with a state: status rail, title, meta,
///   amount, status pill, optional CTA, chevron. Bills, Queue, Me's bills,
///   and every `MadarDataTable` row on a phone.
/// * [MadarListRow.pick] — one of several: title, meta, a radio/check.
///   Printer, till, language pickers.
///
/// `MadarRow` stays for callers that need its free-form slots; new lists use
/// these.
library;

import 'package:design_system/src/controls.dart';
import 'package:design_system/src/format.dart';
import 'package:design_system/src/glyphs.dart';
import 'package:design_system/src/money.dart';
import 'package:design_system/src/status.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:design_system/src/touch.dart';
import 'package:flutter/material.dart';

/// The shape of a [MadarListRow].
enum MadarListRowVariant { nav, ledger, bill, pick }

/// The status rail's width.
const double kMadarRailWidth = 4;

/// A pressed row's scale — shallower than a card's.
const double _pressScale = 0.985;

/// Diameter of a ledger row's sign disc.
const double _signDisc = 32;

class MadarListRow extends StatelessWidget {
  /// A row that navigates.
  const MadarListRow.nav({
    required this.title,
    this.meta,
    this.glyph,
    this.valueText,
    this.onTap,
    this.trailing,
    this.titleLines = 1,
    this.metaLines = 1,
    super.key,
  }) : variant = MadarListRowVariant.nav,
       chevron = true,
       minor = null,
       currency = '',
       status = null,
       rail = null,
       railColor = null,
       selected = false,
       ctaLabel = null,
       onCta = null,
       value = null;

  /// A money movement. [minor] is signed: positive is in, negative out.
  const MadarListRow.ledger({
    required this.title,
    required int this.minor,
    this.currency = '',
    this.meta,
    this.onTap,
    this.trailing,
    super.key,
  }) : variant = MadarListRowVariant.ledger,
       titleLines = 1,
       metaLines = 1,
       chevron = true,
       glyph = null,
       valueText = null,
       status = null,
       rail = null,
       railColor = null,
       selected = false,
       ctaLabel = null,
       onCta = null,
       value = null;

  /// A record with a state.
  const MadarListRow.bill({
    required this.title,
    this.meta,
    this.minor,
    this.currency = '',
    this.valueText,
    this.value,
    this.status,
    this.rail,
    this.railColor,
    this.ctaLabel,
    this.onCta,
    this.onTap,
    this.selected = false,
    this.trailing,
    this.chevron = true,
    this.titleLines = 1,
    this.metaLines = 1,
    super.key,
  }) : variant = MadarListRowVariant.bill,
       glyph = null;

  /// One choice of several.
  const MadarListRow.pick({
    required this.title,
    required this.selected,
    required VoidCallback this.onTap,
    this.meta,
    this.glyph,
    super.key,
  }) : variant = MadarListRowVariant.pick,
       titleLines = 1,
       metaLines = 1,
       chevron = true,
       minor = null,
       currency = '',
       valueText = null,
       status = null,
       rail = null,
       railColor = null,
       ctaLabel = null,
       onCta = null,
       trailing = null,
       value = null;

  final MadarListRowVariant variant;

  /// Localised; one line, ellipsised (a bill may allow [titleLines]).
  final String title;

  /// Bill and nav: the lines the title may wrap to before it is ellipsised —
  /// a record read in full (the staff app's inbox notice, the Payroll
  /// banner naming a month not fully paid). One elsewhere.
  final int titleLines;

  /// The second line — who, when, how. One line, ellipsised. Build it with
  /// `' · '` between facts; isolate figures with `MadarFormat.ltr`.
  final String? meta;

  /// Bill and nav: the lines [meta] may wrap to before it is ellipsised — a
  /// line that must be read in full (why a request was declined, how much a
  /// month still owes). One elsewhere.
  final int metaLines;

  /// A leading glyph (nav, pick).
  final MadarGlyph? glyph;

  /// Money in minor units (ledger: signed; bill: as is).
  final int? minor;
  final String currency;

  /// A non-money value at the end ("On", "12 min", "T5"). Mono when it is a
  /// figure — pass [value] for anything richer.
  final String? valueText;

  /// A custom value widget (bill). Wins over [valueText] and [minor].
  final Widget? value;

  /// The bill's state pill, under the value.
  final MadarStatus? status;

  /// The 4px state rail at the start edge; null draws none.
  final MadarTone? rail;

  /// A rail in a colour outside the five tones — the floor's occupied blue,
  /// so a row and the table it describes agree. Wins over [rail].
  final Color? railColor;

  /// A compact call to action before the chevron ("Settle").
  final String? ctaLabel;
  final VoidCallback? onCta;

  final VoidCallback? onTap;

  /// Bill: the row open in a split view's detail. Pick: the chosen one.
  final bool selected;

  /// Anything else at the end, before the chevron (a 44 glyph tile).
  final Widget? trailing;

  /// Bill: draw the disclosure chevron when tappable. Off for a row whose
  /// tap expands it in place (its trailing carries the expand glyph).
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final isPick = variant == MadarListRowVariant.pick;
    final showChevron = !isPick && onTap != null && chevron;

    Widget? leading;
    switch (variant) {
      case MadarListRowVariant.nav:
      case MadarListRowVariant.pick:
        if (glyph != null) {
          leading = MadarGlyphIcon(
            glyph!,
            size: IconSize.xl,
            color: colors.textSecondary,
          );
        }
      case MadarListRowVariant.ledger:
        final m = minor ?? 0;
        final tone = m < 0 ? MadarTone.danger : MadarTone.success;
        leading = ExcludeSemantics(
          child: Container(
            width: _signDisc,
            height: _signDisc,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.tint(colors),
              shape: BoxShape.circle,
            ),
            child: MadarGlyphIcon(
              m < 0 ? MadarGlyph.minus : MadarGlyph.plus,
              size: IconSize.sm,
              color: tone.color(colors),
            ),
          ),
        );
      case MadarListRowVariant.bill:
        leading = null;
    }

    Widget? end;
    switch (variant) {
      case MadarListRowVariant.nav:
        if (valueText != null) {
          end = Text(
            valueText!,
            maxLines: 1,
            style: MadarType.body.copyWith(color: colors.textSecondary),
          );
        }
      case MadarListRowVariant.ledger:
        final m = minor ?? 0;
        end = MoneyText(
          m,
          currency: currency,
          signed: true,
          style: MadarType.money,
          color: m < 0 ? colors.danger : colors.success,
        );
      case MadarListRowVariant.bill:
        final figure =
            value ??
            (minor != null
                ? MoneyText(
                    minor!,
                    currency: currency,
                    style: MadarType.money,
                    color: colors.textPrimary,
                  )
                : valueText != null
                ? Text(
                    valueText!,
                    maxLines: 1,
                    style: MadarType.numMd.copyWith(color: colors.textPrimary),
                  )
                : null);
        if (figure != null || status != null) {
          end = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: Space.xs,
            children: [?figure, if (status != null) MadarStatusPill(status!)],
          );
        }
      case MadarListRowVariant.pick:
        end = MadarGlyphIcon(
          selected ? MadarGlyph.checkCircle : MadarGlyph.radio,
          size: IconSize.xl,
          color: selected ? colors.accent : colors.textMuted,
        );
    }

    final railColor =
        this.railColor ??
        rail?.color(colors) ??
        (variant == MadarListRowVariant.bill && selected
            ? colors.accent
            : null);

    Widget row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Metrics.rowHeight),
      child: Row(
        children: [
          const SizedBox(width: Space.card),
          if (leading != null) ...[leading, const SizedBox(width: Space.lg)],
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                vertical: Space.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    title,
                    maxLines: titleLines,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.title.copyWith(color: colors.textPrimary),
                  ),
                  if (meta != null)
                    Text(
                      meta!,
                      maxLines: metaLines,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (end != null) ...[const SizedBox(width: Space.lg), end],
          if (ctaLabel != null) ...[
            const SizedBox(width: Space.md),
            MadarButton(
              label: ctaLabel!,
              size: MadarButtonSize.compact,
              variant: MadarButtonVariant.secondary,
              enabled: onCta != null,
              onTap: onCta ?? () {},
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: Space.md), trailing!],
          if (showChevron) ...[
            const SizedBox(width: Space.md),
            MadarGlyphIcon(
              MadarGlyph.chevronForward,
              size: IconSize.md,
              color: colors.textMuted,
            ),
          ],
          const SizedBox(width: Space.card),
        ],
      ),
    );

    if (selected && variant == MadarListRowVariant.bill) {
      row = ColoredBox(color: colors.accentBg, child: row);
    }
    if (railColor != null) {
      row = Stack(
        children: [
          row,
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: kMadarRailWidth,
            child: ColoredBox(color: railColor),
          ),
        ],
      );
    }
    if (onTap == null) return row;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          MadarHaptics.selection();
          onTap!();
        },
        child: TactileScale(scale: _pressScale, haptic: false, child: row),
      ),
    );
  }
}

/// One line of a totals block — label at the start, figure at the end — for
/// the arithmetic under a list: a sale's subtotal / tax / total, a drawer's
/// expected cash. Not a row: 36 tall, no inset of its own, no hairline, not
/// tappable. It lives inside a card's inset (or a row's), directly under the
/// rows it sums. docs/design/SPEC.md §7.
///
/// Give [minor] for money (mono, localised, [signed] for a ledger figure) or
/// [value] for anything else. [emphasis] is the line the block adds up to.
class MadarSummaryLine extends StatelessWidget {
  const MadarSummaryLine({
    required this.label,
    this.minor,
    this.currency = '',
    this.value,
    this.signed = false,
    this.tone,
    this.emphasis = false,
    this.muted = false,
    this.strike = false,
    super.key,
  });

  final String label;
  final int? minor;
  final String currency;

  /// A non-money figure, set mono.
  final String? value;

  /// `+` on a positive figure.
  final bool signed;

  /// Colours the figure (danger for a shortfall). Null is primary text.
  final MadarTone? tone;

  /// The total: title weight, `moneyMd` figure, a taller line.
  final bool emphasis;

  /// Shown for the record, not part of the sum.
  final bool muted;

  /// The figure no longer stands (a voided sale's total).
  final bool strike;

  /// The line's height; the emphasised total's.
  static const double height = 36;
  static const double emphasisHeight = 48;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = muted
        ? colors.textMuted
        : tone?.color(colors) ?? colors.textPrimary;
    final figureStyle = (emphasis ? MadarType.moneyMd : MadarType.money)
        .copyWith(
          color: strike ? colors.textMuted : fg,
          decoration: strike ? TextDecoration.lineThrough : null,
        );
    final figure = minor != null
        ? MoneyText(
            minor!,
            currency: currency,
            signed: signed,
            style: figureStyle,
          )
        : Text(MadarFormat.ltr(value ?? ''), maxLines: 1, style: figureStyle);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: emphasis ? emphasisHeight : height,
      ),
      child: Row(
        spacing: Space.lg,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: emphasis
                  ? MadarType.title.copyWith(color: colors.textPrimary)
                  : MadarType.body.copyWith(
                      color: muted ? colors.textMuted : colors.textSecondary,
                    ),
            ),
          ),
          figure,
        ],
      ),
    );
  }
}
