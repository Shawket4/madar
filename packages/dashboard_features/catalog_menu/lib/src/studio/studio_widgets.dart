/// Small pieces the studio's sections share: the section shell (heading,
/// "Unsaved" pill, description), the loading skeleton, the fixed sizes the
/// web gives in Tailwind units, and the item image's address.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        AssetGroupRefProcessingGroupRef,
        AssetGroupRefReadyGroupRef,
        StudioAggregate;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The web's fixed sizes, named.
abstract final class StudioMetrics {
  /// The loading title (`w-56`).
  static const double titleSkeleton = Space.xxl * 7;

  /// The three loading sections (`h-44`, `h-72`, `h-40`).
  static const List<double> loadingBlocks = [
    Space.xxl * 5.5,
    Space.xxl * 9,
    Space.xxl * 5,
  ];

  /// Room under the last section for the floating save bar (`pb-16`).
  static const double saveBarRoom = Space.xxl * 2;

  /// The item image box (`ImageUploader`'s default width).
  static const double imageBox = Space.xxl * 5.5;

  /// The web's `sm` breakpoint (640): side by side from here.
  static const double sm = DashBreakpoints.sm;

  /// A step's still frame in its row and its tile in the library picker.
  static const double stepFrame = DashMetrics.target;
  static const double stepTile = Space.xxl * 2 + Space.sm;
}

/// One editor section: heading (with an amber "Unsaved" pill while dirty),
/// a description, the body. Flat on the page, divided by hairlines.
class StudioSection extends StatelessWidget {
  const StudioSection({
    required this.title,
    required this.dirty,
    required this.child,
    this.description,
    this.first = false,
    super.key,
  });

  final String title;
  final String? description;
  final bool dirty;
  final bool first;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Padding(
      padding: EdgeInsets.only(
        top: first ? Space.xl : Space.xxl,
        bottom: Space.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  title,
                  style: DashType.sectionTitle.copyWith(color: c.textPrimary),
                ),
                if (dirty)
                  DashStatusPill(
                    label: context.t('menu.studio.unsaved'),
                    tone: DashTone.warning,
                    small: true,
                  ),
              ],
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs / 2),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DashMetrics.proseWide,
                ),
                child: Text(
                  description!,
                  style: DashType.body.copyWith(color: c.textSecondary),
                ),
              ),
            ),
          const SizedBox(height: Space.lg),
          child,
        ],
      ),
    );
  }
}

/// The hairline between sections.
class StudioDivider extends StatelessWidget {
  const StudioDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: context.madarColors.hairline);
}

/// The first load: three section-sized blocks.
class StudioLoadingSkeleton extends StatelessWidget {
  const StudioLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.xxl,
    children: [
      for (final h in StudioMetrics.loadingBlocks)
        DashSkeleton(height: h, radius: Radii.card),
    ],
  );
}

/// The picture the item shows: its asset's tile (else thumb, else full),
/// else the legacy `image_url`.
String? studioImageUrl(StudioAggregate s) {
  final img = s.image;
  if (img is AssetGroupRefReadyGroupRef) {
    final v = img.value.variants;
    final chosen = v.tile ?? v.thumb ?? v.full;
    if (chosen != null) return chosen.url;
  }
  final legacy = s.imageUrl;
  return legacy == null || legacy.isEmpty ? null : legacy;
}

/// Whether the item's asset is still being converted.
bool studioImageProcessing(StudioAggregate s) =>
    s.image is AssetGroupRefProcessingGroupRef;

/// A muted line of small text.
class StudioHint extends StatelessWidget {
  const StudioHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: DashType.small.copyWith(color: context.madarColors.textSecondary),
  );
}

/// A dashed, full-width "+ Add …" button (the web's dashed add rows).
class StudioDashedAdd extends StatelessWidget {
  const StudioDashedAdd({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onTap,
      enabled: onTap != null,
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => CustomPaint(
        foregroundPainter: DashedRRectPainter(
          color: s.hovered ? c.textSecondary : c.hairline,
          radius: Radii.control,
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: DashMetrics.target),
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              DashIcon(
                'plus',
                size: IconSize.sm,
                color: s.hovered ? c.textPrimary : c.textSecondary,
              ),
              Flexible(
                child: Text(
                  label,
                  style: DashType.body.copyWith(
                    color: s.hovered ? c.textPrimary : c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed box with words (the steps' empty state, the meal's notes).
class StudioDashedBox extends StatelessWidget {
  const StudioDashedBox({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: DashedRRectPainter(
      color: context.madarColors.hairline,
      radius: Radii.control,
    ),
    child: Padding(padding: const EdgeInsets.all(Space.lg), child: child),
  );
}

/// A dashed rounded-rectangle outline.
class DashedRRectPainter extends CustomPainter {
  const DashedRRectPainter({required this.color, required this.radius});

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
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.5),
      );
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

/// The web's outline `Badge`.
class StudioOutlineBadge extends StatelessWidget {
  const StudioOutlineBadge(this.label, {super.key});

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
        style: DashType.smallMedium.copyWith(color: c.textSecondary),
      ),
    );
  }
}
