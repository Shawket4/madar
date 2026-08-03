import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

/// A KPI-card-shaped skeleton (label bar over a value bar).
class SkeletonStatCard extends StatelessWidget {
  const SkeletonStatCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonBlock(width: 84, height: 11),
          SizedBox(height: Space.md),
          SkeletonBlock(width: 120, height: 22),
        ],
      ),
    );
  }
}

/// A chart-card-shaped skeleton (title bar over a block).
class SkeletonChartCard extends StatelessWidget {
  const SkeletonChartCard({this.height = 180, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBlock(width: 140, height: 16),
          const SizedBox(height: Space.lg),
          SkeletonBlock(height: height, corner: Radii.sm),
        ],
      ),
    );
  }
}

/// The dashboard loading state — mirrors the real layout so content doesn't
/// jump when it arrives. All blocks pulse off one shared ticker.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final wide = w >= 760;
                final cols = w >= 1000
                    ? 4
                    : w >= 720
                    ? 3
                    : w >= 460
                    ? 2
                    : 1;
                const gap = Space.md;
                final cardW = (w - (cols - 1) * gap) / cols;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (var i = 0; i < 4; i++)
                          SizedBox(
                            width: cardW,
                            child: const SkeletonStatCard(),
                          ),
                      ],
                    ),
                    const SizedBox(height: Space.lg),
                    const SkeletonChartCard(height: 180),
                    const SizedBox(height: Space.lg),
                    if (wide)
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: SkeletonChartCard(height: 120)),
                          SizedBox(width: Space.lg),
                          Expanded(child: SkeletonChartCard(height: 120)),
                        ],
                      )
                    else
                      const Column(
                        children: [
                          SkeletonChartCard(height: 120),
                          SizedBox(height: Space.lg),
                          SkeletonChartCard(height: 120),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
