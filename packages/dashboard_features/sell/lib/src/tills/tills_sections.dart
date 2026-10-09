/// The parts of `/tills` (the web's `tills-page.tsx` `kpis`, `OpenNowStrip`,
/// `OpenBillsLine`, `TillFilters`, `TillsTable`): SELL-TIL-003–026.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show OpenBillsNotice, PaginatedTills, Till;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'till_badges.dart';
import 'tills_data.dart';

/// The four KPIs (SELL-TIL-009), a branch selected only.
class TillsKpis extends ConsumerWidget {
  const TillsKpis({
    required this.openNow,
    required this.notice,
    required this.rows,
    required this.listLoading,
    super.key,
  });

  final AsyncValue<List<Till>> openNow;
  final AsyncValue<OpenBillsNotice> notice;
  final List<Till> rows;
  final bool listLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final open = openNow.value?.length ?? 0;
    final n = notice.value;
    final bills = n?.openBillsCount ?? 0;
    final old = n?.oldBillsCount ?? 0;
    final flagged = rows.where(isFlaggedTill).length;
    return DashLedgerStrip(
      key: const ValueKey('tills-kpis'),
      items: [
        DashLedgerItem(
          key: 'open',
          label: t('tills.openNow'),
          value: open,
          icon: 'clock',
          tone: open > 0 ? DashTone.success : DashTone.neutral,
          loading: openNow.firstLoad,
        ),
        DashLedgerItem(
          key: 'bills',
          label: t('tills.openBills'),
          value: bills,
          icon: 'receipt-text',
          hint: n != null && bills > 0 ? fmt.fmtMoney(n.openBillsAmount) : null,
          loading: notice.firstLoad,
        ),
        DashLedgerItem(
          key: 'old',
          label: t('tills.oldBillsKpi', args: {'hours': n?.oldBillHours ?? 3}),
          value: old,
          icon: 'alert-triangle',
          tone: old > 0 ? DashTone.warning : DashTone.neutral,
          loading: notice.firstLoad,
        ),
        DashLedgerItem(
          key: 'flagged',
          label: t('tills.flaggedKpi'),
          value: flagged,
          tone: flagged > 0 ? DashTone.warning : DashTone.neutral,
          loading: listLoading,
        ),
      ],
    );
  }
}

/// "Open now" (SELL-TIL-010–012, -060): the branch's open tills, live.
class OpenNowSection extends ConsumerWidget {
  const OpenNowSection({
    required this.openNow,
    required this.notice,
    required this.onOpen,
    required this.onRetry,
    super.key,
  });

  final AsyncValue<List<Till>> openNow;
  final OpenBillsNotice? notice;
  final ValueChanged<String> onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final tills = openNow.value ?? const <Till>[];
    final n = notice;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    Widget content;
    if (openNow.firstLoad) {
      content = const DashSkeleton(
        key: ValueKey('open-now-loading'),
        height: DashMetrics.listRow * 2,
        radius: Radii.card,
      );
    } else if (openNow.hasError && !openNow.hasValue) {
      content = DashErrorState(
        key: const ValueKey('open-now-error'),
        message: tillsErrorMessage(openNow.error, t),
        onRetry: onRetry,
        retrying: openNow.isLoading,
      );
    } else if (tills.isEmpty) {
      content = DashEmptyState(
        key: const ValueKey('open-now-empty'),
        icon: 'wallet',
        title: t('dashboard.noOpenTill'),
        description: t('tills.noOpenHint'),
      );
    } else {
      content = DashListCard(
        key: const ValueKey('open-now-list'),
        children: [
          for (final s in tills)
            DashListRow(
              key: ValueKey('open-now-${s.id}'),
              leading: _OpenGlyph(color: c),
              title: s.tellerName,
              meta: [
                s.deviceCode,
                s.deviceLabel,
                fmt.fmtDuration(s.openedAt),
              ].where((p) => p != null && p.isNotEmpty).join(' · '),
              // Wide: the badges, then the float last so the figures line
              // up down the list; a phone has no room for the badges.
              trailing: wide
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: Space.md,
                      children: [
                        Wrap(
                          spacing: Space.xs + DashMetrics.hair,
                          runSpacing: Space.xs,
                          alignment: WrapAlignment.end,
                          children: [
                            if (VerificationBadge.shows(s.verification))
                              VerificationBadge(verification: s.verification),
                            // No link to the other till here (SELL-TIL-011).
                            if (s.openedWhileAnotherOpen) FlagBadge(till: s),
                          ],
                        ),
                        Text(
                          dashFigure(fmt.fmtMoney(s.openingCash)),
                          maxLines: 1,
                          softWrap: false,
                          style: DashType.monoStrong.copyWith(
                            fontSize: 14,
                            color: c.textPrimary,
                          ),
                        ),
                      ],
                    )
                  : null,
              value: wide ? null : fmt.fmtMoney(s.openingCash),
              numericValue: true,
              onTap: () => onOpen(s.id),
            ),
        ],
      );
    }
    return Column(
      key: const ValueKey('open-now'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DashSectionHeader(
              title: t('tills.openNow'),
              count: tills.length,
              countTone: tills.isNotEmpty ? DashTone.success : null,
            ),
            if (n != null && n.openBillsCount > 0) OpenBillsLine(notice: n),
          ],
        ),
        content,
      ],
    );
  }
}

/// The success-tinted wallet tile of an open till.
class _OpenGlyph extends StatelessWidget {
  const _OpenGlyph({required this.color});

  final MadarColors color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: Space.xxl + Space.xs,
      height: Space.xxl + Space.xs,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DashTone.success.wash(color),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: DashIcon(
        'wallet',
        size: IconSize.sm,
        color: DashTone.success.foreground(color),
      ),
    ),
  );
}

/// "N bills left open since …" + (amount) + the old-bill pill (SELL-TIL-010).
class OpenBillsLine extends ConsumerWidget {
  const OpenBillsLine({required this.notice, super.key});

  final OpenBillsNotice notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final n = notice;
    final words = n.since != null
        ? t(
            'tills.openBillsNotice',
            args: {
              'count': n.openBillsCount,
              'since': fmt.fmtDateTime(n.since),
            },
          )
        : t('tills.openBillsCount', args: {'count': n.openBillsCount});
    return Padding(
      key: const ValueKey('open-bills-notice'),
      padding: const EdgeInsets.only(top: DashMetrics.hair),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text.rich(
            TextSpan(
              text: words,
              children: [
                TextSpan(
                  text: ' ${MadarFormat.isolate('(${fmt.fmtMoney(n.openBillsAmount)})')}',
                  style: DashType.mono.copyWith(
                    fontSize: 13,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
            style: DashType.body.copyWith(color: c.textSecondary),
          ),
          if (n.oldBillsCount > 0)
            DashStatusPill(
              key: const ValueKey('old-bills'),
              label: t(
                'tills.oldBills',
                args: {'count': n.oldBillsCount, 'hours': n.oldBillHours},
              ),
              tone: DashTone.warning,
              small: true,
            ),
        ],
      ),
    );
  }
}

/// The filter row (SELL-TIL-003–007, -064). Teller and device options come
/// from the rows on screen.
class TillFilters extends ConsumerWidget {
  const TillFilters({
    required this.search,
    required this.rows,
    required this.onChange,
    super.key,
  });

  final TillsSearch search;
  final List<Till> rows;
  final ValueChanged<Map<String, String?>> onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final tellers = <String, String>{};
    final devices = <String, String>{};
    for (final r in rows) {
      tellers.putIfAbsent(r.tellerId, () => r.tellerName);
      final d = r.deviceId;
      if (d == null) continue;
      devices.putIfAbsent(d, () {
        final label = r.deviceLabel;
        final code = r.deviceCode;
        if (label != null && label.isNotEmpty) return label;
        if (code != null && code.isNotEmpty) return code;
        return '—';
      });
    }
    return DashFilterBar(
      key: const ValueKey('tills-filters'),
      filters: [
        DashFilterSelect<String>(
          key: const ValueKey('filter-status'),
          label: t('common.status'),
          allLabel: t('tills.allStatuses'),
          minWidth: 128,
          options: [
            for (final s in TillsSearch.statuses)
              DashOption(value: s, label: tillStatusLabel(t, s)),
          ],
          value: search.status,
          onChanged: (v) => onChange({'status': v}),
        ),
        DashFilterSelect<String>(
          key: const ValueKey('filter-teller'),
          label: t('tills.teller'),
          allLabel: t('tills.allTellers'),
          minWidth: 144,
          options: [
            for (final e in tellers.entries)
              DashOption(value: e.key, label: e.value),
          ],
          value: search.teller,
          onChanged: (v) => onChange({'teller': v}),
        ),
        DashFilterSelect<String>(
          key: const ValueKey('filter-device'),
          label: t('tills.device'),
          allLabel: t('tills.allDevices'),
          minWidth: 144,
          options: [
            for (final e in devices.entries)
              DashOption(value: e.key, label: e.value),
          ],
          value: search.device,
          onChanged: (v) => onChange({'device': v}),
        ),
        DashFilterToggle(
          key: const ValueKey('filter-today'),
          label: t('tills.filters.today'),
          value: search.today,
          onChanged: (v) => onChange({'today': v ? 'true' : null}),
        ),
        DashFilterToggle(
          key: const ValueKey('filter-flagged'),
          label: t('tills.filters.flagged'),
          value: search.flagged,
          onChanged: (v) => onChange({'flagged': v ? 'true' : null}),
        ),
      ],
    );
  }
}

/// "All tills" and its table (SELL-TIL-013–026).
class AllTillsSection extends ConsumerWidget {
  const AllTillsSection({
    required this.list,
    required this.rows,
    required this.showBranch,
    required this.onOpenReport,
    required this.onRetry,
    required this.menu,
    super.key,
  });

  final AsyncValue<PaginatedTills> list;
  final List<Till> rows;
  final bool showBranch;
  final ValueChanged<String> onOpenReport;
  final VoidCallback onRetry;
  final List<DashMenuItem> Function(Till till) menu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final muted = DashType.body.copyWith(color: c.textSecondary);

    // Pointing at a row warms its report (`onRowPrefetch`).
    Widget hover(Till s, Widget child) => MouseRegion(
      onEnter: (_) => prefetchTillReport(ref, s.id),
      child: child,
    );

    final columns = <DashColumn<Till>>[
      DashColumn(
        id: 'teller',
        label: t('tills.teller'),
        phone: DashPhoneRole.title,
        flex: 3,
        minWidth: 150,
        text: (s) => s.tellerName,
        cell: (context, s) => hover(
          s,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MadarClippedText(
                s.tellerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
              MadarClippedText(
                // Each stamp in its own direction (`<bdi>`).
                s.closedAt == null
                    ? MadarFormat.isolate(fmt.fmtDateTime(s.openedAt))
                    : '${MadarFormat.isolate(fmt.fmtDateTime(s.openedAt))} → '
                          '${MadarFormat.isolate(fmt.fmtDateTime(s.closedAt))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.mono.copyWith(
                  fontSize: 12,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
      if (showBranch)
        DashColumn(
          id: 'branch',
          label: t('tills.branch'),
          flex: 2,
          text: (s) => s.branchName ?? '—',
          cell: (context, s) => hover(
            s,
            MadarClippedText(
              s.branchName ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.body.copyWith(color: c.textPrimary),
            ),
          ),
        ),
      DashColumn(
        id: 'device',
        label: t('tills.device'),
        flex: 2,
        minWidth: 110,
        text: (s) => s.deviceCode ?? s.deviceLabel ?? '—',
        cell: (context, s) {
          final code = s.deviceCode;
          final label = s.deviceLabel;
          if ((code == null || code.isEmpty) &&
              (label == null || label.isEmpty)) {
            return hover(s, Text('—', style: muted));
          }
          return hover(
            s,
            Text.rich(
              TextSpan(
                children: [
                  if (code != null && code.isNotEmpty)
                    TextSpan(
                      text: code,
                      style: DashType.monoMedium.copyWith(
                        fontSize: 14,
                        color: c.textPrimary,
                      ),
                    ),
                  if (label != null && label.isNotEmpty)
                    TextSpan(
                      text: code != null && code.isNotEmpty
                          ? '  $label'
                          : label,
                      style: muted,
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
      DashColumn(
        id: 'status',
        label: t('common.status'),
        flex: 3,
        minWidth: 140,
        text: (s) => tillStatusLabel(t, s.status.value),
        cell: (context, s) => hover(
          s,
          Wrap(
            key: ValueKey('till-badges-${s.id}'),
            spacing: Space.xs + DashMetrics.hair,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: tillBadges(s, onOpenOther: onOpenReport),
          ),
        ),
      ),
      DashColumn(
        id: 'opening',
        label: t('tills.openingCash'),
        numeric: true,
        minWidth: 130,
        text: (s) => fmt.fmtMoney(s.openingCash),
        cell: (context, s) => hover(
          s,
          Text(
            dashFigure(fmt.fmtMoney(s.openingCash)),
            maxLines: 1,
            softWrap: false,
            style: DashType.mono.copyWith(fontSize: 14, color: c.textPrimary),
          ),
        ),
      ),
      DashColumn(
        id: 'discrepancy',
        label: t('tills.discrepancy'),
        numeric: true,
        minWidth: 130,
        text: (s) => discrepancyText(fmt, s.cashDiscrepancy),
        cell: (context, s) {
          final d = s.cashDiscrepancy;
          final strong = d != null && d != 0;
          return hover(
            s,
            Text(
              d == null ? '—' : dashFigure(discrepancyText(fmt, d)),
              key: ValueKey('discrepancy-${s.id}'),
              maxLines: 1,
              softWrap: false,
              style: strong
                  ? DashType.monoStrong.copyWith(
                      fontSize: 14,
                      color: DashTone.danger.foreground(c),
                    )
                  : DashType.mono.copyWith(
                      fontSize: 14,
                      color: c.textSecondary,
                    ),
            ),
          );
        },
      ),
    ];

    return Column(
      key: const ValueKey('all-tills'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashSectionHeader(
          title: t('tills.history'),
          count: list.value?.total ?? rows.length,
        ),
        DashDataTable<Till>(
          key: const ValueKey('tills-table'),
          columns: columns,
          rows: rows,
          rowKey: (s) => s.id,
          loading: list.firstLoad,
          errorMessage: list.hasError ? tillsErrorMessage(list.error, t) : null,
          onRetry: onRetry,
          onRowTap: (s) => onOpenReport(s.id),
          rowSemanticLabel: (s) => s.tellerName,
          pageSize: 20,
          hideViewOptions: true,
          rowActions: (context, s) => DashMenu(
            items: menu(s),
            builder: (context, ctl) => DashIconButton(
              key: ValueKey('till-actions-${s.id}'),
              icon: 'more-horizontal',
              semanticLabel: t('common.actions'),
              onPressed: ctl.toggle,
            ),
          ),
          empty: DashEmptyState(
            key: const ValueKey('tills-empty'),
            icon: 'clock',
            title: t('tills.empty'),
            description: t('tills.emptyHint'),
          ),
        ),
      ],
    );
  }
}
