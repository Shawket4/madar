/// Small pieces the purchasing page and dialogs need that the kit does not
/// have yet (reported as kit candidates):
///
/// - [PurchasingTabStrip]: the kit's underline tab strip with a glyph before
///   each label (the web's `PageTabsTrigger` with its lucide icon);
/// - [DashedFrame]: the dashed edge of the locked unit-cost box;
/// - [LabelValueGrid]: the phone card's two-column label/value grid.
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

export '../shared/number_input.dart';

/// One tab of a [PurchasingTabStrip].
@immutable
class PurchasingTab<T> {
  const PurchasingTab({
    required this.value,
    required this.label,
    required this.icon,
    this.enabled = true,
  });

  final T value;
  final String label;
  final String icon;
  final bool enabled;
}

/// The page tabs: 44 tall, 14/500 labels after a 16 glyph, the active tab
/// inked with a 2px underline over a hairline track, scrolling sideways
/// when narrow; a disabled tab is dimmed and takes no tap.
class PurchasingTabStrip<T> extends StatelessWidget {
  const PurchasingTabStrip({
    required this.tabs,
    required this.value,
    required this.onChanged,
    this.onIntent,
    super.key,
  });

  final List<PurchasingTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  /// A tab is about to be picked ([DashIntent]): warm the read it makes.
  final ValueChanged<T>? onIntent;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              _TabButton<T>(
                tab: tabs[i],
                first: i == 0,
                active: tabs[i].value == value,
                onTap: () => onChanged(tabs[i].value),
                onIntent: onIntent == null
                    ? null
                    : () => onIntent!(tabs[i].value),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton<T> extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.first,
    required this.active,
    required this.onTap,
    this.onIntent,
  });

  final PurchasingTab<T> tab;
  final bool first;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onIntent;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: tab.enabled ? onTap : null,
      onIntent: tab.enabled ? onIntent : null,
      enabled: tab.enabled,
      selected: active,
      pressScale: false,
      semanticLabel: tab.label,
      excludeChildSemantics: true,
      builder: (context, s) {
        final fg = !tab.enabled
            ? c.disabledText
            : active || s.hovered
            ? c.textPrimary
            : c.textSecondary;
        return AnimatedContainer(
          duration: DashMotion.of(context, DashMotion.base),
          height: DashMetrics.tab,
          padding: EdgeInsetsDirectional.only(
            start: first ? 0 : Space.md,
            end: Space.md,
          ),
          foregroundDecoration: dashFocusRing(
            context,
            s,
            BorderRadius.circular(Radii.xs),
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? c.textPrimary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs + DashMetrics.hair,
            children: [
              DashIcon(tab.icon, size: IconSize.sm, color: fg),
              Text(tab.label, style: DashType.bodyMedium.copyWith(color: fg)),
            ],
          ),
        );
      },
    );
  }
}

/// A box with a dashed edge (the web's `border-dashed`).
class DashedFrame extends StatelessWidget {
  const DashedFrame({
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: Space.md,
      vertical: Space.sm,
    ),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return CustomPaint(
      painter: _DashedEdge(color: c.border, radius: Radii.xs),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: child,
      ),
    );
  }
}

class _DashedEdge extends CustomPainter {
  _DashedEdge({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          Radius.circular(radius),
        ),
      );
    const dash = Space.xs;
    const gap = Space.xs - 1;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedEdge old) =>
      old.color != color || old.radius != radius;
}

/// The phone card's grid: each entry a 12 muted label over its value, two to
/// a row.
class LabelValueGrid extends StatelessWidget {
  const LabelValueGrid({required this.entries, super.key});

  final List<(String label, Widget value)> entries;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = (constraints.maxWidth - Space.lg) / 2;
        return Wrap(
          spacing: Space.lg,
          runSpacing: Space.sm,
          children: [
            for (final (label, value) in entries)
              SizedBox(
                width: w,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                    const SizedBox(height: DashMetrics.hair),
                    DefaultTextStyle.merge(
                      style: DashType.body.copyWith(color: c.textPrimary),
                      child: value,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
