/// `/reports/staff` Staff discipline (REP-STF rows): staff ranked within
/// their department by attendance (fewest absences, then lates, then late
/// minutes), one card per department
/// (`features/reports/staff/staff-discipline-page.tsx`).
///
/// A Dawam page: the module gate shows the Dawam-off words when it is off
/// (REP-STF-001), the read refetches when the app comes back after 30 s
/// (`dawamQuery`), and the header's Refresh fetches the page's `/staff`
/// reads again (REP-STF-004/005).
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart';
import 'lis_providers.dart';
import 'lis_support.dart';

/// The route's page (`DashRoute.builder`).
Widget staffDisciplinePageBuilder(BuildContext context, GoRouterState state) =>
    const StaffDisciplinePage();

/// One department's card: its rows in the server's order.
typedef DisciplineGroup = ({String? id, String name, List<DisciplineRow> rows});

/// `groupByDepartment`: by department id in first-appearance order; the
/// rows with none go to one group (its card is titled "Unassigned").
List<DisciplineGroup> groupByDepartment(List<DisciplineRow> rows) {
  final order = <String?>[];
  final groups = <String?, DisciplineGroup>{};
  for (final r in rows) {
    final key = r.departmentId;
    final g = groups[key] ??= () {
      order.add(key);
      return (id: key, name: r.departmentName ?? '', rows: <DisciplineRow>[]);
    }();
    g.rows.add(r);
  }
  return [for (final k in order) groups[k]!];
}

class StaffDisciplinePage extends ConsumerStatefulWidget {
  const StaffDisciplinePage({super.key});

  @override
  ConsumerState<StaffDisciplinePage> createState() =>
      _StaffDisciplinePageState();
}

class _StaffDisciplinePageState extends ConsumerState<StaffDisciplinePage> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _loadedAt;

  /// The last failed refresh's toast, by kind (`dawam-refresh-429` /
  /// `-failed`): a new one of the same kind replaces it.
  final Map<String, DashToastHandle> _toasts = {};

  DisciplineKey get _key =>
      disciplineKeyOf(ref.read(currentScopeProvider), ref.read(formatProvider));

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// `refetchOnWindowFocus` (`dawamQuery`): back after the data went stale
  /// (30 s) asks again; sooner does nothing.
  void _onResume() {
    final at = _loadedAt;
    if (at == null || !mounted) return;
    final now = ref.read(clockProvider)();
    if (now.difference(at) < kQueryStaleTime) return;
    ref.invalidate(disciplineProvider(_key));
  }

  /// The Refresh button: every mounted read under `/staff` (segment
  /// bounded: `/staff-pool` is not `/staff`).
  void _refresh() =>
      ref.read(realtimeBusProvider).invalidate(const ['/staff/']);

  /// A refresh that fails while the report is on screen: the query
  /// cache's toast, once per kind (`data/api/query.ts`), the cards kept.
  void _refreshFailed(Object? error) {
    final id = error is ApiException && error.status == 429
        ? 'dawam-refresh-429'
        : 'dawam-refresh-failed';
    _toasts.remove(id)?.dismiss();
    _toasts[id] = DashToast.error(
      context,
      errorMessage(error, ref.read(tProvider)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final title = t('reports.staff.title');
    final gate = lisGate(
      ref,
      title: title,
      canSee: (a) => a.can(Cap.hrAttendanceRead),
    );
    if (gate != null) return gate;
    final key = disciplineKeyOf(
      ref.watch(currentScopeProvider),
      ref.watch(formatProvider),
    );
    final read = disciplineProvider(key);
    final q = ref.watch(read);
    // Opened on cached data: the listener below never sees that value.
    if (q.hasValue) _loadedAt ??= ref.read(clockProvider)();
    ref.listen(read, (prev, next) {
      if (next.hasValue && !next.isLoading && !next.hasError) {
        _loadedAt = ref.read(clockProvider)();
      }
      if (next.hasError && next.hasValue && !next.isLoading) {
        if (prev != null &&
            prev.hasError &&
            identical(prev.error, next.error)) {
          return;
        }
        _refreshFailed(next.error);
      }
    });
    final groups = groupByDepartment(q.value?.rows ?? const []);
    final Widget body;
    if (q.awaitingFirst) {
      body = const Column(
        spacing: Space.md,
        children: [
          DashSkeleton(height: Space.xxl * 5),
          DashSkeleton(height: Space.xxl * 5),
        ],
      );
    } else if (q.failedFirst) {
      body = DashErrorState(
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(read),
      );
    } else if (groups.isEmpty) {
      body = DashEmptyState(title: t('reports.staff.empty'));
    } else {
      body = _DepartmentGrid(groups: groups);
    }
    return DashPageScaffold(
      title: title,
      subtitleWidget: const ReportPeriodSubtitle(),
      actions: [StaffRefreshButton(busy: q.isLoading, onRefresh: _refresh)],
      body: body,
    );
  }
}

/// REP-STF-010: two card columns from 1024 px, one below.
class _DepartmentGrid extends StatelessWidget {
  const _DepartmentGrid({required this.groups});

  final List<DisciplineGroup> groups;

  @override
  Widget build(BuildContext context) {
    final two = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;
    final cards = [for (final g in groups) DepartmentCard(group: g)];
    if (!two) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: cards,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        for (var i = 0; i < cards.length; i += 2)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.lg,
              children: [
                Expanded(child: cards[i]),
                Expanded(
                  child: i + 1 < cards.length
                      ? cards[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One department: its title and its people, ranked.
class DepartmentCard extends ConsumerWidget {
  const DepartmentCard({required this.group, super.key});

  final DisciplineGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return DashCard(
      key: ValueKey('dept-${group.id ?? 'unassigned'}'),
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          Semantics(
            header: true,
            child: Text(
              group.id == null ? t('reports.staff.unassigned') : group.name,
              style: DashType.sectionTitle.copyWith(color: c.textPrimary),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, r) in group.rows.indexed) ...[
                if (i > 0) const MadarHairline.row(),
                DisciplineRowTile(row: r),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// REP-STF-008/009: `#rank`, the name, and on the end side the summary and
/// any cover lines.
class DisciplineRowTile extends ConsumerWidget {
  const DisciplineRowTile({required this.row, super.key});

  final DisciplineRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final small = DashType.small.copyWith(color: c.textSecondary);
    final given = row.coversGiven ?? 0;
    final coveredBy = row.coveredByOthers ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: Space.sm + DashMetrics.hair,
      ),
      child: Row(
        spacing: Space.md,
        children: [
          Expanded(
            child: Row(
              spacing: Space.sm + DashMetrics.hair,
              children: [
                _RankBadge('#${row.rankInDepartment}'),
                Flexible(
                  child: MadarClippedText(
                    row.employeeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                t(
                  'reports.staff.rowSummary',
                  args: {
                    'late': f.fmtNumber(row.lateDays),
                    'absent': f.fmtNumber(row.absentDays),
                    'minutes': f.fmtNumber(row.totalLateMinutes),
                  },
                ),
                textAlign: TextAlign.end,
                style: small,
              ),
              // A cover shows for both people (CV-7).
              if (given > 0)
                Text(
                  t(
                    'reports.staff.coversGiven',
                    count: given,
                    args: {'n': f.fmtNumber(given)},
                  ),
                  textAlign: TextAlign.end,
                  style: small,
                ),
              if (coveredBy > 0)
                Text(
                  t(
                    'reports.staff.coveredByOthers',
                    count: coveredBy,
                    args: {'n': f.fmtNumber(coveredBy)},
                  ),
                  textAlign: TextAlign.end,
                  style: small,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The outline mono badge (`Badge variant="outline"`).
class _RankBadge extends StatelessWidget {
  const _RankBadge(this.label);

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
        dashFigure(label),
        style: DashType.monoMedium.copyWith(
          fontSize: DashType.small.fontSize,
          color: c.textPrimary,
        ),
      ),
    );
  }
}

/// The Refresh button in a Dawam page header (`dawam/refresh-button.tsx`):
/// an outline icon button whose tooltip and label read "Refresh", or
/// "Refreshing…" while the page's read is fetching; the glyph spins
/// meanwhile (reduced motion: it dims instead). A tap while busy joins the
/// fetch in flight (`cancelRefetch: false`).
class StaffRefreshButton extends ConsumerStatefulWidget {
  const StaffRefreshButton({
    required this.busy,
    required this.onRefresh,
    super.key,
  });

  final bool busy;
  final VoidCallback onRefresh;

  @override
  ConsumerState<StaffRefreshButton> createState() => _StaffRefreshButtonState();
}

class _StaffRefreshButtonState extends ConsumerState<StaffRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final busy = widget.busy;
    if (busy && !reduce) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin
        ..stop()
        ..value = 0;
    }
    final label = busy ? t('common.refreshing') : t('common.refresh');
    final radius = BorderRadius.circular(Radii.sm);
    return DashPressable(
      onTap: busy ? () {} : widget.onRefresh,
      semanticLabel: label,
      tooltip: label,
      excludeChildSemantics: true,
      builder: (context, s) {
        final colors = dashButtonColors(
          context,
          DashButtonVariant.outline,
          s,
          enabled: true,
        );
        Widget glyph = DashIcon('refresh-cw', color: colors.fg);
        if (busy) {
          glyph = reduce
              ? Opacity(opacity: 0.5, child: glyph)
              : RotationTransition(turns: _spin, child: glyph);
        }
        return Container(
          width: DashMetrics.target,
          height: DashMetrics.target,
          alignment: Alignment.center,
          foregroundDecoration: dashFocusRing(context, s, radius),
          decoration: BoxDecoration(
            color: colors.fill,
            borderRadius: radius,
            border: colors.edge == null
                ? null
                : Border.all(color: colors.edge!),
          ),
          child: glyph,
        );
      },
    );
  }
}
