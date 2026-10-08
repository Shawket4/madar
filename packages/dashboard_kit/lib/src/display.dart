import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'buttons.dart';
import 'foundation/l10n.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';

/// A card: white face, hairline edge, 16 corners, no shadow (the web's
/// `rounded-2xl border bg-card`).
class DashCard extends StatelessWidget {
  const DashCard({
    required this.child,
    this.padding = const EdgeInsets.all(Space.card),
    this.onTap,
    this.selected = false,
    this.semanticLabel,
    this.clip = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// The open record (accent wash, stronger edge).
  final bool selected;
  final String? semanticLabel;

  /// Clip the content to the corners (a card of flush rows).
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final radius = BorderRadius.circular(Radii.card);
    Widget face(DashPressState s) => Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      foregroundDecoration: dashFocusRing(context, s, radius),
      decoration: BoxDecoration(
        color: selected
            ? c.hover
            : s.highlighted
            ? Color.lerp(c.card, c.hover, 0.3)
            : c.card,
        borderRadius: radius,
        border: Border.all(
          color: selected || s.highlighted
              ? Color.lerp(c.hairline, c.textPrimary, 0.2)!
              : c.hairline,
        ),
      ),
      child: child,
    );
    if (onTap == null) return face(const DashPressState());
    return DashPressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: semanticLabel,
      builder: (context, s) => face(s),
    );
  }
}

/// Empty content (the web's `EmptyState`): a glyph disc, a 16/600 sentence
/// that says what will appear here, a 14 message, an optional action.
class DashEmptyState extends StatelessWidget {
  const DashEmptyState({
    required this.title,
    this.description,
    this.icon,
    this.action,
    this.framed = true,
    super.key,
  });

  final String title;
  final String? description;

  /// A glyph name (`search`, `inbox`).
  final String? icon;
  final Widget? action;

  /// Draw the card frame (off inside another card).
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return _StateFrame(
      framed: framed,
      children: [
        if (icon != null)
          _Disc(
            color: c.muted,
            child: DashIcon(icon!, size: IconSize.lg, color: c.textSecondary),
          ),
        _StateText(title: title, message: description),
        if (action != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: action,
          ),
      ],
    );
  }
}

/// A failed load — never shown as empty (the web's `ErrorState`): a danger
/// disc, what failed, why, and a primary Retry.
class DashErrorState extends StatelessWidget {
  const DashErrorState({
    this.title,
    this.message,
    this.onRetry,
    this.retrying = false,
    this.retryLabel,
    this.framed = true,
    super.key,
  });

  /// Defaults to "Couldn't load this".
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final bool retrying;
  final String? retryLabel;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    return Semantics(
      liveRegion: true,
      child: _StateFrame(
        framed: framed,
        children: [
          _Disc(
            color: DashTone.danger.wash(c),
            child: DashIcon(
              'alert-triangle',
              size: IconSize.lg,
              color: DashTone.danger.foreground(c),
            ),
          ),
          _StateText(title: title ?? t.loadFailed, message: message),
          if (onRetry != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: DashButton(
                label: retryLabel ?? t.retry,
                icon: 'rotate-cw',
                loading: retrying,
                onPressed: onRetry,
              ),
            ),
        ],
      ),
    );
  }
}

class _StateFrame extends StatelessWidget {
  const _StateFrame({required this.children, required this.framed});
  final List<Widget> children;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.xl,
        vertical: Space.xxl + Space.lg,
      ),
      decoration: framed
          ? BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: c.hairline),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: children,
      ),
    );
  }
}

class _StateText extends StatelessWidget {
  const _StateText({required this.title, this.message});
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: DashMetrics.prose),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: DashType.sectionTitle.copyWith(color: c.textPrimary),
          ),
          if (message != null && message!.isNotEmpty)
            Text(
              message!,
              textAlign: TextAlign.center,
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: DashMetrics.badgeDisc,
    height: DashMetrics.badgeDisc,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: child,
  );
}

/// A status — glyph + label, never colour alone (the web's `StatusPill`).
class DashStatusPill extends StatelessWidget {
  const DashStatusPill({
    required this.label,
    this.tone = DashTone.neutral,
    this.icon,
    this.small = false,
    super.key,
  });

  final String label;
  final DashTone tone;

  /// Overrides the tone's glyph.
  final String? icon;
  final bool small;

  /// The tone's default glyph.
  static String glyphFor(DashTone tone) => switch (tone) {
    DashTone.neutral => 'circle-dot',
    DashTone.accent => 'circle-dashed',
    DashTone.success => 'check-circle-2',
    DashTone.warning => 'alert-triangle',
    DashTone.danger => 'x-circle',
    DashTone.info => 'info',
  };

  /// The web's shared status-word → tone map (`STATUS_TONES`).
  static const Map<String, DashTone> statusTones = {
    'active': DashTone.success,
    'completed': DashTone.success,
    'paid': DashTone.success,
    'finalized': DashTone.success,
    'received': DashTone.success,
    'approved': DashTone.success,
    'open': DashTone.accent,
    'ordered': DashTone.accent,
    'pending': DashTone.warning,
    'partially_received': DashTone.warning,
    'draft': DashTone.neutral,
    'inactive': DashTone.neutral,
    'archived': DashTone.neutral,
    'closed': DashTone.neutral,
    'voided': DashTone.danger,
    'cancelled': DashTone.danger,
    'canceled': DashTone.danger,
    'rejected': DashTone.danger,
    'refunded': DashTone.danger,
    'force_closed': DashTone.warning,
    'no_show': DashTone.danger,
  };

  /// The tone for a status word (`toneFor`).
  static DashTone toneFor(
    String? status, {
    DashTone fallback = DashTone.neutral,
  }) => (status == null ? null : statusTones[status.toLowerCase()]) ?? fallback;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final fg = tone.foreground(c);
    final style = (small ? DashType.tableHeader : DashType.smallStrong)
        .copyWith(color: fg, letterSpacing: 0);
    return Container(
      height: small ? DashMetrics.pillSmall : DashMetrics.pill,
      padding: EdgeInsetsDirectional.only(
        start: small ? Space.xs + DashMetrics.hair : Space.sm,
        end: small ? Space.sm : Space.sm + DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        color: tone.wash(c),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          DashIcon(
            icon ?? glyphFor(tone),
            size: small ? 12 : IconSize.xs,
            color: fg,
          ),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small counted or labelled badge (the web's `Badge`).
class DashBadge extends StatelessWidget {
  const DashBadge(
    this.label, {
    this.tone = DashTone.neutral,
    this.mono = false,
    super.key,
  });

  final String label;
  final DashTone tone;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        color: tone.wash(c),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        mono ? dashFigure(label) : label,
        style:
            (mono
                    ? DashType.monoMedium.copyWith(fontSize: 12)
                    : DashType.smallMedium)
                .copyWith(color: tone.foreground(c)),
      ),
    );
  }
}

/// A section's label (the web's `SectionHeader`): 16/600, optional glyph and
/// count chip, a quiet description, a trailing slot.
class DashSectionHeader extends StatelessWidget {
  const DashSectionHeader({
    required this.title,
    this.description,
    this.icon,
    this.count,
    this.countTone,
    this.trailing,
    super.key,
  });

  final String title;
  final String? description;
  final String? icon;
  final int? count;

  /// A live/open count reads in a tone.
  final DashTone? countTone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Space.xxl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: Space.md,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Row(
                    spacing: Space.sm,
                    children: [
                      if (icon != null)
                        DashIcon(
                          icon!,
                          size: IconSize.sm,
                          color: c.textSecondary,
                        ),
                      Flexible(
                        child: MadarClippedText(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DashType.sectionTitle.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      if (count != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.xs + DashMetrics.hair,
                          ),
                          decoration: BoxDecoration(
                            color: countTone?.wash(c) ?? c.muted,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                          child: Text(
                            '$count',
                            style: DashType.monoMedium.copyWith(
                              fontSize: 12,
                              color:
                                  countTone?.foreground(c) ?? c.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (description != null)
                  Padding(
                    padding: const EdgeInsets.only(top: DashMetrics.hair),
                    child: Text(
                      description!,
                      style: DashType.body.copyWith(color: c.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// An accessible progress bar (the web's `ProgressBar`): a muted track and a
/// toned fill that eases to its value.
class DashProgressBar extends StatelessWidget {
  const DashProgressBar({
    required this.value,
    required this.semanticLabel,
    this.max = 100,
    this.tone = DashTone.accent,
    super.key,
  });

  final double value;
  final double max;

  /// What the bar measures, for a screen reader.
  final String semanticLabel;
  final DashTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final safeMax = max > 0 ? max : 1.0;
    final frac = (value.clamp(0, safeMax) / safeMax).toDouble();
    return Semantics(
      label: semanticLabel,
      value: '${(frac * 100).round()}%',
      child: Container(
        height: DashMetrics.progress,
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        clipBehavior: Clip.antiAlias,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: frac),
            duration: DashMotion.of(context, DashMotion.slow),
            curve: Curves.easeOut,
            builder: (context, f, _) => FractionallySizedBox(
              widthFactor: f,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tone.solid(c),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The variants of a [DashListRow] (the web's `ListRow`).
enum DashListRowVariant {
  /// Glyph · title / meta · value · chevron — settings links.
  nav,

  /// ± disc · title / meta · signed figure — movements.
  ledger,

  /// Glyph/avatar · title / meta · trailing — people, records.
  item,

  /// Glyph · title / meta · control — choices.
  pick,
}

/// One list row: 56 min tall, 16/20 inset, hairlines between siblings in a
/// [DashListCard].
class DashListRow extends StatelessWidget {
  const DashListRow({
    required this.title,
    this.variant = DashListRowVariant.item,
    this.meta,
    this.wrapMeta = false,
    this.icon,
    this.leading,
    this.signIn,
    this.value,
    this.numericValue = false,
    this.trailing,
    this.selected = false,
    this.onTap,
    this.enabled = true,
    super.key,
  });

  final String title;
  final DashListRowVariant variant;
  final String? meta;
  final bool wrapMeta;
  final String? icon;

  /// Replaces the glyph (an avatar, an image).
  final Widget? leading;

  /// ledger: true for money in (+), false for out (−).
  final bool? signIn;

  /// A value word or figure on the end side.
  final String? value;
  final bool numericValue;

  /// Controls, a pill, a menu.
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final interactive = onTap != null && enabled;
    Widget? lead = leading;
    if (lead == null &&
        variant == DashListRowVariant.ledger &&
        signIn != null) {
      final tone = signIn! ? DashTone.success : DashTone.danger;
      lead = Container(
        width: Space.xxl + Space.xs,
        height: Space.xxl + Space.xs,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tone.wash(c), shape: BoxShape.circle),
        child: DashIcon(
          signIn! ? 'plus' : 'minus',
          size: IconSize.sm,
          color: tone.foreground(c),
        ),
      );
    } else if (lead == null && icon != null) {
      lead = Container(
        width: Space.xxl + Space.xs,
        height: Space.xxl + Space.xs,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: DashIcon(icon!, size: IconSize.sm, color: c.textSecondary),
      );
    }
    final titleColor = enabled ? c.textPrimary : c.disabledText;
    Widget body(DashPressState s) => Container(
      constraints: const BoxConstraints(minHeight: DashMetrics.listRow),
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: MediaQuery.sizeOf(context).width >= DashBreakpoints.sm
            ? Space.card
            : Space.lg,
        vertical: Space.sm + DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        color: selected
            ? c.hover
            : s.highlighted || s.focused
            ? c.hover.withValues(alpha: 0.5)
            : null,
      ),
      foregroundDecoration: selected
          ? BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: c.accent, width: kMadarRailWidth),
              ),
            )
          : null,
      child: Row(
        spacing: Space.md,
        children: [
          ?lead,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MadarClippedText(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyStrong.copyWith(color: titleColor),
                ),
                if (meta != null)
                  Padding(
                    padding: const EdgeInsets.only(top: DashMetrics.hair),
                    child: wrapMeta
                        ? Text(
                            meta!,
                            style: DashType.meta.copyWith(
                              color: c.textSecondary,
                            ),
                          )
                        : MadarClippedText(
                            meta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DashType.meta.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                  ),
              ],
            ),
          ),
          if (value != null)
            Text(
              numericValue ? dashFigure(value!) : value!,
              maxLines: 1,
              softWrap: false,
              style: numericValue
                  ? DashType.monoStrong.copyWith(
                      fontSize: 14,
                      color: c.textPrimary,
                    )
                  : DashType.body.copyWith(color: c.textSecondary),
            ),
          ?trailing,
          if (variant == DashListRowVariant.nav)
            DashIcon(
              DashIcon.forward(context),
              size: IconSize.sm,
              color: c.textSecondary,
            ),
        ],
      ),
    );
    if (!interactive) return body(const DashPressState());
    return DashPressable(
      onTap: onTap,
      selected: selected,
      pressScale: false,
      builder: (context, s) => body(s),
    );
  }
}

/// A flush card of rows with hairlines between them (the web's `ListCard`).
class DashListCard extends StatelessWidget {
  const DashListCard({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.hairline),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Arithmetic under a list: label at the start, figure at the end.
class DashSummaryLine extends StatelessWidget {
  const DashSummaryLine({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.muted = false,
    super.key,
  });

  final String label;
  final String value;
  final bool emphasis;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final fg = muted ? c.textSecondary : c.textPrimary;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: emphasis ? Metrics.headerHeight : Space.xxl + Space.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: (emphasis ? DashType.sectionTitle : DashType.body)
                  .copyWith(color: emphasis ? fg : c.textSecondary),
            ),
          ),
          Text(
            dashFigure(value),
            maxLines: 1,
            softWrap: false,
            style:
                (emphasis
                        ? DashType.statFigure(18)
                        : DashType.monoMedium.copyWith(fontSize: 14))
                    .copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

/// A loading placeholder bar (the web's `Skeleton`).
class DashSkeleton extends StatelessWidget {
  const DashSkeleton({
    this.width,
    this.height = Space.lg,
    this.radius = Radii.xs,
    super.key,
  });
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) =>
      SkeletonBlock(width: width, height: height, corner: radius);
}
