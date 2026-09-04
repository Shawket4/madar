import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';

import '../../app/providers.dart';
import '../../format.dart';
import '../../ui/kit.dart';
import '../home/home_screen.dart' show showAccountSheet;

/// Who is on the floor right now.
///
/// A manager opens this to answer one question before anything else: is the
/// shift covered? So the three counts come first, the labour-against-plan bar
/// second, and only then the names — and every figure is computed by the
/// SERVER from today's punches against the roster, not assembled here.
class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
  /// Rows visible before the "+N others" cut. Keeps the screen glanceable.
  static const _visibleRows = 5;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final presence = ref.watch(teamPresenceProvider(null));
    final name = ref.watch(sessionProvider)?.displayName ?? '';

    return StaffPage(
      title: t('team.title'),
      titleTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Back to your own working life — a manager still clocks in.
          TactileScale(
            onTap: () => ref.read(managerModeProvider.notifier).set(false),
            child: IconTile(
              icon: 'house',
              size: 40,
              background: colors.accentBg,
              tint: colors.accent,
            ),
          ),
          const SizedBox(width: Space.sm),
          TactileScale(
            onTap: () => showAccountSheet(context, ref),
            child: InitialsTile(
              name: name,
              size: 40,
              background: colors.textPrimary,
              tint: colors.bg,
            ),
          ),
        ],
      ),
      onRefresh: () async => ref.invalidate(teamPresenceProvider(null)),
      children: [
        presence.when(
          loading: () => const SkeletonList(count: 5),
          error: (e, _) => ErrorState(
            message: '$e',
            retryLabel: t('common.retry'),
            onRetry: () => ref.invalidate(teamPresenceProvider(null)),
          ),
          data: (data) {
            final shown = _expanded
                ? data.rows.length
                : data.rows.length.clamp(0, _visibleRows);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: t('team.present'),
                        value: '${data.present}',
                        leading: const LiveDot(),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: StatCard(
                        label: t('team.late'),
                        value: '${data.lateCount}',
                        valueColor: data.lateCount > 0 ? colors.warning : null,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: StatCard(
                        label: t('team.absent'),
                        value: '${data.absent}',
                        valueColor: data.absent > 0 ? colors.danger : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.md),
                _LabourCard(data: data),
                const SizedBox(height: Space.md),
                if (data.rows.isEmpty)
                  EmptyState(icon: 'person.2', title: t('team.empty'))
                else
                  MadarCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < shown; i++)
                          _PersonRow(
                            row: data.rows[i],
                            last: i == shown - 1,
                          ),
                        if (!_expanded && data.rows.length > _visibleRows)
                          TactileScale(
                            onTap: () => setState(() => _expanded = true),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: Space.md,
                              ),
                              child: Text(
                                t('team.more', {
                                  'count': '${data.rows.length - _visibleRows}',
                                }),
                                textAlign: TextAlign.center,
                                style: MadarType.labelSm.copyWith(
                                  color: colors.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LabourCard extends ConsumerWidget {
  const _LabourCard({required this.data});

  final TeamPresenceView data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final fraction = data.plannedMinutes == 0
        ? 0.0
        : data.workedMinutes / data.plannedMinutes;
    final percent = (fraction * 100).round();

    return MadarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: FieldLabel(t('team.labor'))),
              Num(
                '${formatHm(data.workedMinutes)} / '
                '${formatHm(data.plannedMinutes)}',
                style: MadarType.num.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: Space.sm + 2),
          ProgressBar(fraction: fraction, height: 10, color: colors.navy),
          const SizedBox(height: Space.sm),
          Text(
            t('team.ofPlan', {'percent': '$percent'}),
            style: MadarType.labelSm.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends ConsumerWidget {
  const _PersonRow({required this.row, required this.last});

  final PresenceRowView row;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;

    // The chip carries the state; the time carries the evidence for it.
    final (label, tone) = switch (row.state) {
      'late' => (
        t('ts.lateBy', {'minutes': '${row.lateMinutes}'}),
        ChipTone.warning,
      ),
      'absent' => (t('team.absent'), ChipTone.danger),
      'on_leave' => (t('team.onLeave'), ChipTone.info),
      'done' => (t('team.done'), ChipTone.neutral),
      'off' => (t('team.notDue'), ChipTone.neutral),
      _ => (t('team.present'), ChipTone.success),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm + 2,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: colors.borderLight)),
      ),
      child: Row(
        children: [
          InitialsTile(name: row.name),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.body.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    row.jobTitle,
                    row.branchName,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.labelSm.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          if (row.checkInAt.isNotEmpty) ...[
            Num(formatClock(row.checkInAt), color: colors.textSecondary),
            const SizedBox(width: Space.sm),
          ],
          StatusChip(label: label, tone: tone),
        ],
      ),
    );
  }
}
