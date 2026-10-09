/// Small pieces the bookings page draws that the kit has no widget for yet
/// (kit candidates): the web's `Alert`, an outline `Badge`, an equal-cell
/// grid, and the page's fixed web sizes.
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

/// The web's fixed sizes on this page.
abstract final class BookingMetrics {
  /// The day picker (`min-w-40`, room for "08 Oct 2026").
  static const double datePicker = Space.xxl * 5 + Space.xl;

  /// The timeline's Table column (`w-32`).
  static const double timelineLabel = Space.xxl * 4;

  /// The timeline's hour strip (`h-7`) and a table row (`h-11`).
  static const double timelineHeader = Space.xl + Space.xs;
  static const double timelineRow = DashMetrics.target;

  /// A booking block (`h-8`, `top-1.5`).
  static const double timelineBlock = Space.xxl;
  static const double timelineBlockTop = Space.xs + DashMetrics.hair;

  /// Below this the timeline scrolls sideways (`min-w-[720px]`).
  static const double timelineMinWidth = 720;

  /// The narrowest an hour may be, so "09:00 AM" labels never overlap.
  static const double timelineHour = Space.xxl * 2;
}

/// The web's `Alert`: a bordered card with a glyph, a title and its body.
class BookingNotice extends StatelessWidget {
  const BookingNotice({
    required this.icon,
    required this.title,
    required this.body,
    this.tone = DashTone.neutral,
    super.key,
  });

  final String icon;
  final String title;
  final Widget body;

  /// `warning` draws the warning border and glyph (`border-warning/50`).
  final DashTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final warn = tone == DashTone.warning;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(
          color: warn ? c.warning.withValues(alpha: 0.5) : c.hairline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: DashMetrics.hair),
            child: DashIcon(
              icon,
              size: IconSize.sm,
              color: warn ? tone.foreground(c) : c.textPrimary,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.xs,
              children: [
                Text(
                  title,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                body,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The web's `<Badge variant="outline">`.
class BookingOutlineBadge extends StatelessWidget {
  const BookingOutlineBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: c.hairline),
      ),
      child: Text(
        label,
        style: DashType.smallMedium.copyWith(color: c.textPrimary),
      ),
    );
  }
}

/// Equal cells, [columns] to a row (`grid grid-cols-N gap-…`).
class BookingGrid extends StatelessWidget {
  const BookingGrid({
    required this.columns,
    required this.children,
    this.spacing = Space.sm,
    super.key,
  });

  final int columns;
  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    spacing: spacing,
    children: [
      for (var i = 0; i < children.length; i += columns)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: spacing,
          children: [
            for (var j = i; j < i + columns; j++)
              Expanded(
                child: j < children.length
                    ? children[j]
                    : const SizedBox.shrink(),
              ),
          ],
        ),
    ],
  );
}
