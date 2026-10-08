/// Every shown capability, grouped with plain names (the web's
/// `features/access/capability-groups.tsx`), shared by the person access
/// sheet (ADM-USR-045/046) and the Roles & Permissions page (ADM-ROL-013/014).
/// [CapabilityGroupsList.control] draws the end side of a row (a switch, the
/// three-way control, "Always on"); each group's advanced tier sits behind
/// one collapsed "Advanced (N)" section.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capability_catalog.dart';

/// The "Always on" marker of a core capability: locked, never a toggle.
class AlwaysOnBadge extends ConsumerWidget {
  const AlwaysOnBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs / 2,
      ),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          DashIcon('lock', size: IconSize.xs, color: c.textSecondary),
          Text(
            ref.t('access.alwaysOn'),
            style: DashType.smallMedium.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class CapabilityGroupsList extends ConsumerStatefulWidget {
  const CapabilityGroupsList({required this.control, this.filter, super.key});

  /// The end side of [meta]'s row.
  final Widget Function(BuildContext context, CapabilityMeta meta) control;

  /// Which capabilities to show (all non-legacy when null).
  final bool Function(CapabilityMeta meta)? filter;

  @override
  ConsumerState<CapabilityGroupsList> createState() =>
      _CapabilityGroupsListState();
}

class _CapabilityGroupsListState extends ConsumerState<CapabilityGroupsList> {
  bool _showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider);
    final filter = widget.filter;
    final groups = [
      for (final g in catalogGroups())
        if (filter == null) g else g.where(filter),
    ].where((g) => !g.isEmpty).toList();
    final advancedCount = groups.fold<int>(0, (n, g) => n + g.advanced.length);

    Widget section(CatalogGroup g, List<CapabilityMeta> caps) => _GroupCard(
      title: g.label(lang),
      children: [
        for (final meta in caps)
          _CapabilityRow(
            label: meta.label(lang),
            hint: meta.hint(lang),
            control: widget.control(context, meta),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        for (final g in groups)
          if (g.main.isNotEmpty) section(g, g.main),
        if (advancedCount > 0)
          _AdvancedToggle(
            label: ref.t('access.advanced'),
            count: advancedCount,
            open: _showAdvanced,
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          ),
        if (advancedCount > 0 && _showAdvanced)
          for (final g in groups)
            if (g.advanced.isNotEmpty) section(g, g.advanced),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: c.muted,
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.md,
            ),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
            ),
          ),
          for (final (i, row) in children.indexed) ...[
            if (i > 0) const MadarHairline(light: true),
            row,
          ],
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.label,
    required this.hint,
    required this.control,
  });

  final String label;
  final String? hint;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: DashMetrics.listRow),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm,
        ),
        child: Row(
          spacing: Space.lg,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                  if (hint != null && hint!.isNotEmpty)
                    Text(
                      hint!,
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                ],
              ),
            ),
            control,
          ],
        ),
      ),
    );
  }
}

class _AdvancedToggle extends StatelessWidget {
  const _AdvancedToggle({
    required this.label,
    required this.count,
    required this.open,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onTap,
      semanticLabel: '$label ($count)',
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        decoration: BoxDecoration(
          color: s.highlighted ? c.hover : c.card,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: c.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$label '),
                    TextSpan(
                      text: '($count)',
                      style: DashType.body.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
            ),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: DashMotion.of(context, DashMotion.base),
              child: DashIcon(
                'chevron-down',
                size: IconSize.sm,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
