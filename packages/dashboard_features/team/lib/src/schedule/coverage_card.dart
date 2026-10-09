/// Coverage needs (`dawam/coverage-editor.tsx`, TEAM-SCH-055…058): how many
/// people each hour of each weekday needs at one branch, typed as an hour
/// grid and saved as the whole list (the server replaces it). Empty is no
/// typed need; when the engine runs on POS sales, what sales suggest shows
/// greyed in the empty cells. A need tied to a department is not on the
/// grid and is kept as it is.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show CoverageView, PutCoverage;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/attendance_errors.dart';
import '../shared/refresh_toast.dart';
import '../shared/staff_query.dart';
import '../shared/week.dart';
import 'schedule_data.dart';
import 'schedule_providers.dart';

/// The hour column (`w-16`).
const double _hourWidth = 64;

/// A day column at its narrowest (`min-w-[40rem]` less the hours, / 7).
const double _cellWidth = 82;

/// The card's skeleton (`h-64`).
const double _skeleton = Space.xxl * 8;

class CoverageCard extends ConsumerStatefulWidget {
  const CoverageCard({required this.branchId, super.key});

  final String branchId;

  @override
  ConsumerState<CoverageCard> createState() => _CoverageCardState();
}

class _CoverageCardState extends ConsumerState<CoverageCard> {
  CoverageGrid _grid = {};
  CoverageView? _seeded;
  bool _dirty = false;
  bool _busy = false;

  @override
  void didUpdateWidget(CoverageCard old) {
    super.didUpdateWidget(old);
    if (old.branchId != widget.branchId) {
      _seeded = null;
      _dirty = false;
    }
  }

  void _set(int dow, int hour, String v) {
    final n = readCoverageCell(v);
    setState(() {
      _dirty = true;
      _grid = {..._grid};
      if (n == null) {
        _grid.remove(coverageKey(dow, hour));
      } else {
        _grid[coverageKey(dow, hour)] = n;
      }
    });
  }

  Future<void> _save(CoverageView view) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final api = ref.read(apiProvider);
    final staff = ref.read(staffRevisionsProvider.notifier);
    setState(() => _busy = true);
    try {
      await api.staff.putCoverage(
        body: PutCoverage(
          branchId: widget.branchId,
          needs: [
            for (final n in view.needs)
              if (n.departmentId != null) n,
            ...fromGrid(_grid),
          ],
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(context, attendanceErrorText(e, t, f));
        setState(() => _busy = false);
      }
      return;
    }
    // The suggestions read the grid too, not only this card (H2-D5).
    staff.invalidateStaff();
    if (!mounted) return;
    DashToast.success(context, t('dawam.coverageSaved'));
    setState(() {
      _busy = false;
      _dirty = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final provider = scheduleCoverageProvider(widget.branchId);
    final q = ref.watch(provider);
    listenStaffRefreshFailure(ref, context, provider);
    final view = q.value;
    // Seeded from the server until edited; a refresh that lands re-seeds
    // an untouched grid.
    if (view != null && !identical(view, _seeded) && !_dirty) {
      _seeded = view;
      _grid = toGrid(view.needs);
    }

    if (q.failedFirst) {
      // A failed read says so, never a skeleton for ever (H2-D4).
      return DashErrorState(
        title: t('dawam.coverageLoadError'),
        message: attendanceErrorText(q.error, t, ref.watch(formatProvider)),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(provider),
      );
    }
    if (view == null) {
      return const DashSkeleton(
        key: Key('coverage-skeleton'),
        height: _skeleton,
        radius: Radii.card,
      );
    }

    final derived = view.source == 'pos'
        ? toGrid(view.derived)
        : const <String, int>{};
    final hours = coverageHours([..._grid.keys, ...derived.keys]);
    String day(int dow) => t(weekdayKeys[dow]);
    final head = DashType.smallStrong.copyWith(color: c.textSecondary);

    final description = switch (view.source) {
      'pos' => t('dawam.coveragePos', args: {'n': view.ordersPerStaff}),
      'pattern' => t('dawam.coveragePattern'),
      _ => t('dawam.coverageGrid'),
    };

    final header = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.start,
      spacing: Space.md,
      runSpacing: Space.md,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: DashMetrics.proseWide),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs + 2,
            children: [
              Semantics(
                header: true,
                child: Text(
                  t('dawam.coverageTitle'),
                  style: DashType.sectionTitle.copyWith(color: c.textPrimary),
                ),
              ),
              Text(
                description,
                style: DashType.body.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
        DashButton(
          key: const Key('coverage-save'),
          label: t('common.save'),
          icon: 'save',
          loading: _busy,
          onPressed: _busy ? null : () => _save(view),
        ),
      ],
    );

    return DashCard(
      key: const Key('coverage-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          header,
          LayoutBuilder(
            builder: (context, box) {
              final fit = (box.maxWidth - _hourWidth) / 7;
              final cellW = fit > _cellWidth ? fit : _cellWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: _hourWidth + cellW * 7,
                  child: Column(
                    spacing: Space.xs,
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: _hourWidth),
                          for (final d in coverageDayOrder)
                            SizedBox(
                              width: cellW,
                              child: Text(
                                day(d),
                                textAlign: TextAlign.center,
                                style: head,
                              ),
                            ),
                        ],
                      ),
                      for (final h in hours)
                        Row(
                          children: [
                            SizedBox(
                              width: _hourWidth,
                              child: Text(
                                ltr(hourLabel(h)),
                                style: DashType.mono.copyWith(
                                  fontSize: DashType.small.fontSize,
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                            for (final d in coverageDayOrder)
                              SizedBox(
                                width: cellW,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Space.xs / 2,
                                  ),
                                  child: DashTextInput(
                                    key: ValueKey('coverage-$d-$h'),
                                    value: _grid[coverageKey(d, h)]?.toString() ?? '',
                                    placeholder: derived[coverageKey(d, h)]
                                        ?.toString(),
                                    semanticLabel: '${day(d)} ${hourLabel(h)}',
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    textDirection: TextDirection.ltr,
                                    mono: true,
                                    onChanged: (v) => _set(d, h, v),
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
