/// The staff app's screen furniture, assembled from `package:design_system`.
///
/// Nothing here invents a colour, a radius, or a duration — every value comes
/// from the shared tokens, which is what keeps this app looking like the POS
/// rather than like a different product that happens to share a backend. What
/// this file DOES own is the handful of compositions the attendance screens
/// repeat: the paper-background scaffold, the white r16 card, the stat tile,
/// the section label, and the mono number.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Resolve an elevation against the ambient theme. Every shadow in this app
/// goes through here so light and dark get the radii the natives use.
List<BoxShadow> shadowsOf(BuildContext context, MadarElevation level) =>
    level.shadows(
      context.madarColors,
      dark: Theme.of(context).brightness == Brightness.dark,
    );

/// Card corner radius used across every screen in the handoff.
const double kCardRadius = Radii.md;

/// The signature card: white, r16, one soft shadow. Everything on a screen sits
/// in one of these or is a bare label between them.
class MadarCard extends StatelessWidget {
  const MadarCard({
    required this.child,
    this.padding = const EdgeInsets.all(Space.md),
    this.radius = kCardRadius,
    this.color,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Overrides the surface — used by the ink payslip hero and tinted rows.
  final Color? color;

  /// When set the whole card presses with the house tactile scale.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadowsOf(context, MadarElevation.card),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return TactileScale(onTap: onTap, child: card);
  }
}

/// A number — time, duration, money, ID. Always Plex Mono, always LTR even
/// inside Arabic text, because `09:00–17:00` reads backwards otherwise.
class Num extends StatelessWidget {
  const Num(this.text, {this.style, this.color, super.key});

  final String text;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        text,
        style: (style ?? MadarType.num).copyWith(
          color: color ?? colors.textPrimary,
        ),
      ),
    );
  }
}

/// The muted uppercase-in-English label that sits above a value or a section.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    // Tracking and uppercasing are ENGLISH-only: Arabic letterforms join, and
    // spacing them apart breaks the word.
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    return Text(
      isArabic ? text : text.toUpperCase(),
      style: MadarType.labelSm.copyWith(
        color: color ?? colors.textMuted,
        letterSpacing: isArabic ? null : MadarType.tracking,
      ),
    );
  }
}

/// Screen title — the 22/700 line every frame opens with.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: MadarType.h2.copyWith(color: colors.textPrimary),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// One of the 2×2 / 1×3 stat cards: a muted caption over a mono figure.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueStyle,
    this.leading,
    super.key,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final TextStyle? valueStyle;

  /// e.g. the pulsing live dot on "present".
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return MadarCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm + 2,
      ),
      radius: Radii.sm + 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 5)],
              Flexible(child: FieldLabel(label)),
            ],
          ),
          const SizedBox(height: 2),
          Num(value, style: valueStyle ?? MadarType.numLg, color: valueColor),
        ],
      ),
    );
  }
}

/// The pulsing dot that marks a live figure.
class LiveDot extends StatefulWidget {
  const LiveDot({this.color, this.size = 8, super.key});

  final Color? color;
  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.madarColors.success;
    return FadeTransition(
      // 0.45 → 1.0, matching the prototype's `mdPulse`.
      opacity: Tween<double>(begin: 0.45, end: 1).animate(_controller),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// A segmented control — week/month, branch filter, request kind.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    required this.value,
    required this.segments,
    required this.onChanged,
    this.scrollable = false,
    super.key,
  });

  final T value;
  final List<({T value, String label})> segments;
  final ValueChanged<T> onChanged;

  /// Branch filters can outgrow the width; week/month never does.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final row = Row(
      mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
      children: [
        for (final segment in segments) _buildSegment(context, colors, segment),
      ],
    );

    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: scrollable
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: row)
          : row,
    );
  }

  Widget _buildSegment(
    BuildContext context,
    MadarColors colors,
    ({T value, String label}) segment,
  ) {
    final selected = segment.value == value;
    final child = AnimatedContainer(
      duration: MotionSpec.standardDuration,
      curve: MotionSpec.standardCurve,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      decoration: BoxDecoration(
        color: selected ? colors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.xs + 1),
        boxShadow: selected ? shadowsOf(context, MadarElevation.card) : null,
      ),
      child: Text(
        segment.label,
        style: MadarType.labelSm.copyWith(
          color: selected ? colors.textPrimary : colors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final tappable = TactileScale(
      onTap: () => onChanged(segment.value),
      child: child,
    );
    return scrollable ? tappable : Expanded(child: tappable);
  }
}

/// A filled primary action — the 50/54px pill-cornered button in the lower
/// third of most frames.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 50,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final double height;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : Opacities.disabled,
      child: TactileScale(
        onTap: enabled ? onPressed : null,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: colors.accent,
            borderRadius: BorderRadius.circular(kCardRadius),
            boxShadow: shadowsOf(context, MadarElevation.card),
          ),
          alignment: Alignment.center,
          child: busy
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.textOnAccent,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      MadarIcon(
                        icon,
                        tint: colors.textOnAccent,
                        size: IconSize.lg,
                      ),
                      const SizedBox(width: Space.sm),
                    ],
                    Text(
                      label,
                      style: MadarType.title.copyWith(
                        color: colors.textOnAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The white bordered counterpart to [PrimaryButton].
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 50,
    this.tone,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final double height;

  /// Colours the border and label — `danger` for a reject action.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = tone ?? colors.textPrimary;
    return Opacity(
      opacity: onPressed == null ? Opacities.disabled : 1,
      child: TactileScale(
        onTap: onPressed,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(kCardRadius),
            border: Border.all(color: tone ?? colors.border),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                MadarIcon(icon, tint: fg, size: IconSize.lg),
                const SizedBox(width: Space.sm),
              ],
              Text(
                label,
                style: MadarType.title.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A square icon tile — the 38/46/54px rounded square that leads most rows.
class IconTile extends StatelessWidget {
  const IconTile({
    required this.icon,
    this.size = 38,
    this.background,
    this.tint,
    super.key,
  });

  final String icon;
  final double size;
  final Color? background;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? colors.surfaceAlt,
        borderRadius: BorderRadius.circular(size / 3.4),
      ),
      alignment: Alignment.center,
      child: MadarIcon(
        icon,
        tint: tint ?? colors.textSecondary,
        size: size * 0.47,
      ),
    );
  }
}

/// Initials in a rounded square — the roster and team rows lead with one.
class InitialsTile extends StatelessWidget {
  const InitialsTile({
    required this.name,
    this.size = 36,
    this.background,
    this.tint,
    super.key,
  });

  final String name;
  final double size;
  final Color? background;
  final Color? tint;

  /// First letters of the first two words. Works the same in both scripts.
  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p.characters.first).join();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? colors.accentBg,
        borderRadius: BorderRadius.circular(size / 3.2),
      ),
      alignment: Alignment.center,
      child: Text(
        initialsOf(name),
        style: MadarType.labelSm.copyWith(
          color: tint ?? colors.accent,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

/// A thin progress bar — elapsed-vs-shift, labour-vs-plan.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    required this.fraction,
    this.height = 8,
    this.color,
    super.key,
  });

  final double fraction;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: colors.surfaceAlt,
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: fraction.clamp(0, 1),
          child: Container(color: color ?? colors.accent),
        ),
      ),
    );
  }
}

/// The paper-background page every screen is built in: a title, then content.
class StaffPage extends StatelessWidget {
  const StaffPage({
    required this.title,
    required this.children,
    this.titleTrailing,
    this.onRefresh,
    this.floating,
    this.padding = const EdgeInsets.fromLTRB(
      Space.lg,
      Space.md,
      Space.lg,
      Space.xl,
    ),
    super.key,
  });

  final String title;
  final Widget? titleTrailing;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  /// Pinned to the bottom, outside the scroll area — where the handoff puts
  /// every primary action.
  final Widget? floating;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final list = ListView(
      padding: padding,
      children: [
        ScreenTitle(title, trailing: titleTrailing),
        const SizedBox(height: Space.md),
        ...children,
      ],
    );

    return ColoredBox(
      color: colors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: onRefresh == null
                  ? list
                  : RefreshIndicator(
                      onRefresh: onRefresh!,
                      color: colors.accent,
                      child: list,
                    ),
            ),
            if (floating != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.sm,
                  Space.lg,
                  Space.md,
                ),
                child: floating,
              ),
          ],
        ),
      ),
    );
  }
}

/// `7:25` / `+1:02` — the handoff writes durations as hours:minutes, never
/// "7h 25m", because they sit in columns beside clock times.
String formatHm(int minutes, {bool signed = false}) {
  final negative = minutes < 0;
  final abs = minutes.abs();
  final text = '${abs ~/ 60}:${(abs % 60).toString().padLeft(2, '0')}';
  if (negative) return '−$text';
  return signed ? '+$text' : text;
}

/// `H:MM:SS` for the live elapsed counter.
String formatHms(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}
