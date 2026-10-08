/// Small pieces the customers unit draws in several places: the "Member"
/// pill, a phone (mono, left-to-right), the muted dash, a stat box, a
/// section heading, the muted status box and the quiet inline failure.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../shared/phone.dart';

/// The accent "Member" pill with its star (`StatusPill tone="accent"
/// size="sm" icon={Star}`).
class MemberPill extends StatelessWidget {
  const MemberPill({super.key});

  @override
  Widget build(BuildContext context) => DashStatusPill(
    label: context.t('customers.member'),
    tone: DashTone.accent,
    icon: 'star',
    small: true,
  );
}

/// A stored phone for reading: `+20 100 123 4567`, mono, always LTR
/// (`<bdi dir="ltr" className="font-mono">`).
class PhoneText extends StatelessWidget {
  const PhoneText(this.phone, {this.style, this.raw = false, super.key});

  final String phone;
  final TextStyle? style;

  /// As stored, unformatted (the merge picker shows it so).
  final bool raw;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Text(
      raw ? phone : formatPhoneDisplay(phone),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      softWrap: false,
      style:
          style ?? DashType.mono.copyWith(fontSize: 14, color: c.textPrimary),
    );
  }
}

/// The muted "—" of an empty cell.
class MutedDash extends StatelessWidget {
  const MutedDash({super.key});

  @override
  Widget build(BuildContext context) => Text(
    '—',
    style: DashType.body.copyWith(color: context.madarColors.textSecondary),
  );
}

/// A bordered stat (`rounded-lg border p-3`: a small label over a mono
/// semibold figure).
class StatBox extends StatelessWidget {
  const StatBox({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: DashMetrics.hair,
        children: [
          MadarClippedText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              dashFigure(value),
              maxLines: 1,
              style: DashType.statFigure(18).copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A grid of [StatBox]es: two columns, four from the web's `sm` (640).
class StatGrid extends StatelessWidget {
  const StatGrid({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cols = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm ? 4 : 2;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              for (var j = i; j < i + cols; j++)
                Expanded(
                  child: j < children.length
                      ? children[j]
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: rows,
    );
  }
}

/// A section of the sheet: a 14/600 heading over its content.
class PeopleSection extends StatelessWidget {
  const PeopleSection({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.md,
    children: [
      Semantics(
        header: true,
        child: Text(
          title,
          style: DashType.bodyStrong.copyWith(
            color: context.madarColors.textPrimary,
          ),
        ),
      ),
      child,
    ],
  );
}

/// The muted, bordered status box (`role="status"`, `bg-muted/40`).
class StatusNote extends StatelessWidget {
  const StatusNote({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: children,
        ),
      ),
    );
  }
}

/// A plain sentence in a [StatusNote].
class NoteText extends StatelessWidget {
  const NoteText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: DashType.body.copyWith(color: context.madarColors.textPrimary),
  );
}

/// A section's empty line (`rounded-lg border border-dashed p-3`).
class DashedNote extends StatelessWidget {
  const DashedNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return CustomPaint(
      foregroundPainter: _DashedBorder(c.border),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Text(
          text,
          style: DashType.body.copyWith(color: c.textSecondary),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(Radii.sm),
    );
    final path = Path()..addRRect(r.deflate(0.5));
    const dash = Space.xs;
    const gap = Space.xs;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// A section that failed to load (`rounded-lg border p-3`): the reason and
/// an outline Retry.
class InlineFailure extends StatelessWidget {
  const InlineFailure({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.hairline),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          Text(message, style: DashType.body.copyWith(color: c.textSecondary)),
          DashButton(
            label: context.t('common.retry'),
            variant: DashButtonVariant.outline,
            size: DashButtonSize.compact,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// A bordered card of rows with hairlines between them (`divide-y
/// rounded-lg border`).
class RuledBox extends StatelessWidget {
  const RuledBox({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
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

/// A link-style text button (`variant="link"`): the web's order ref, a
/// booking's date, "View order". At least 44 tall for a finger.
class LinkText extends StatelessWidget {
  const LinkText({
    required this.label,
    required this.onTap,
    this.mono = false,
    this.icon,
    this.small = false,
    this.strong = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final bool mono;
  final String? icon;
  final bool small;
  final bool strong;

  @override
  Widget build(BuildContext context) => DashPressable(
    onTap: onTap,
    semanticLabel: label,
    excludeChildSemantics: true,
    pressScale: false,
    builder: (context, s) {
      final fg = dashButtonColors(
        context,
        DashButtonVariant.link,
        s,
        enabled: true,
      ).fg;
      final base = small
          ? DashType.small
          : (mono ? DashType.mono.copyWith(fontSize: 14) : DashType.body);
      final style = base.copyWith(
        color: fg,
        fontWeight: strong || small ? FontWeight.w500 : null,
        decoration: s.highlighted || small ? TextDecoration.underline : null,
        decorationColor: fg,
      );
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              if (icon != null) DashIcon(icon!, size: IconSize.xs, color: fg),
              Flexible(
                child: MadarClippedText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: mono ? TextDirection.ltr : null,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
