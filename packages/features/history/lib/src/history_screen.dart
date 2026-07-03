/// Order history — the current shift's orders: still-queued sales
/// (Queued/Failed chip) plus the server's synced orders. Responsive: a
/// sortable data TABLE at container width ≥ [Responsive.wideTable],
/// stacked expandable CARDS below it. Tap a row to expand line detail
/// (totals + Print + Void). The full shift stays in memory; only
/// `visibleLimit` rows paint (client-side "show more"). A
/// pixel-and-behavior port of the Kotlin OrderHistoryScreen.kt (+ its
/// VoidOverlay) over the shared Rust core; state lives in [historyProvider],
/// reprints reuse feature_checkout's ReceiptSheet.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_history/src/history_provider.dart';
import 'package:feature_history/src/widgets.dart';
import 'package:flutter/material.dart'
    show CircularProgressIndicator, Scaffold, Theme;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (OrderHistoryScreen.kt) that fall between the 4-pt Space
// steps — kept verbatim so the Flutter chrome measures identically.

/// Content column cap (natives: widthIn(max = 960.dp)).
const double _contentMaxWidth = 960;

/// Table column widths (natives: 104 / 110 / 44.dp) and sort arrow (9.dp).
const double _numberColWidth = 104;
const double _amountColWidth = 110;
const double _disclosureColWidth = 44;
const double _sortArrowSize = 9;

/// Header/inline spinner diameters (natives: 18 / 16.dp).
const double _headerSpinner = 18;
const double _rowSpinner = 16;

/// Stat divider height (natives: 28.dp) and orderRef size (9.sp).
const double _statDividerHeight = 28;
const double _orderRefSize = 9;

/// Voided rows dim to 55% (natives: alpha 0.55).
const double _voidedAlpha = 0.55;

/// Void sheet width cap (natives: maxWidth = 520.dp).
const double _voidSheetMaxWidth = 520;

/// Restock switch track (44×26) and thumb (20) — a tokens-only stand-in
/// for the natives' material Switch.
const Size _switchTrack = Size(44, 26);
const double _switchThumb = 20;

/// The current shift's order history (full-screen over the order screen).
class OrderHistoryScreen extends ConsumerStatefulWidget {
  /// Creates the history screen.
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  final TextEditingController _searchField = TextEditingController();

  @override
  void dispose() {
    _searchField.dispose();
    super.dispose();
  }

  /// Reprint entry — project the past order to a ReceiptView (cached,
  /// offline-durable) and present the shared checkout ReceiptSheet
  /// (paper preview + Print), the natives' openOrderReceiptPreview →
  /// ReceiptPreviewScreen flow.
  Future<void> _openReceipt(OrderSummaryView o) async {
    ReceiptView receipt;
    try {
      receipt = await ref.read(bridgeProvider).orderReceiptView(orderId: o.id);
    } on MadarError catch (e) {
      ref.read(historyProvider.notifier).surfaceError(e);
      return;
    }
    if (!mounted) return;
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => ReceiptSheet(receipt: receipt),
    );
  }

  /// Void flow — the natives' VoidOverlay as a Madar sheet. On success the
  /// history reloads (the row flips to Voided); the shell refresh happens
  /// inside the sheet's confirm.
  Future<void> _openVoid(OrderSummaryView o) async {
    final voided = await showMadarSheet<bool>(
      context,
      size: SheetSize.hug,
      maxWidth: _voidSheetMaxWidth,
      builder: (_) => _VoidSheet(order: o),
    );
    if (voided ?? false) await ref.read(historyProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final hasShift = ref.watch(historyProvider.select((s) => s.hasShift));
    final historyEmpty = ref.watch(
      historyProvider.select((s) => s.history.isEmpty),
    );
    return Scaffold(
      backgroundColor: colors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              MadarHeader(
                title: bridge.tr(key: 'history.title'),
                subtitle: hasShift
                    ? bridge.tr(key: 'history.current_shift')
                    : null,
                onBack: () => Navigator.maybePop(context),
                actions: const [_HeaderSpinner()],
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      if (!historyEmpty) _FilterBar(controller: _searchField),
                      Expanded(
                        child: _HistoryContent(
                          onPrint: (o) => unawaited(_openReceipt(o)),
                          onVoid: (o) => unawaited(_openVoid(o)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const _HistoryToastHost(),
        ],
      ),
    );
  }
}

/// The header's trailing refresh spinner — shown only while a reload runs
/// over an already-populated list.
class _HeaderSpinner extends ConsumerWidget {
  const _HeaderSpinner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final show = ref.watch(
      historyProvider.select((s) => s.loading && s.history.isNotEmpty),
    );
    if (!show) return const SizedBox.shrink();
    return SizedBox.square(
      dimension: _headerSpinner,
      child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2),
    );
  }
}

/// The screen toast, driven by [HistoryState.toast].
class _HistoryToastHost extends ConsumerWidget {
  const _HistoryToastHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(historyProvider.select((s) => s.toast));
    return ToastHost(
      toast,
      onDismiss: (id) => ref.read(historyProvider.notifier).dismissToast(id),
    );
  }
}

// ── Filter bar (search + two filter-chip rows with counts) ──────────────────
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final notifier = ref.read(historyProvider.notifier);
    final type = ref.watch(historyProvider.select((s) => s.type));
    final sync = ref.watch(historyProvider.select((s) => s.sync));
    final typeCounts = ref.watch(historyProvider.select((s) => s.typeCounts));
    final syncCounts = ref.watch(historyProvider.select((s) => s.syncCounts));
    String t(String key) => bridge.tr(key: key);

    Widget typeChip(HistoryTypeFilter f, String glyph, String label) {
      return HistoryFilterChip(
        glyph: glyph,
        label: '$label · ${typeCounts[f] ?? 0}',
        active: type == f,
        onTap: () => notifier.setType(f),
      );
    }

    Widget syncChip(
      HistorySyncFilter f,
      String glyph,
      String label,
      ChipTone tone,
    ) {
      return HistoryFilterChip(
        glyph: glyph,
        label: '$label · ${syncCounts[f] ?? 0}',
        active: sync == f,
        tone: tone,
        onTap: () => notifier.setSync(f),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: colors.surface,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
              vertical: Space.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.sm,
              children: [
                HistoryTextField(
                  controller: controller,
                  placeholder: t('history.search'),
                  icon: 'magnifyingglass',
                  onChanged: notifier.setSearch,
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: Space.sm,
                    children: [
                      typeChip(
                        HistoryTypeFilter.all,
                        'slider.horizontal.3',
                        t('history.type.all'),
                      ),
                      typeChip(
                        HistoryTypeFilter.dineIn,
                        'fork.knife',
                        t('history.type.dine_in'),
                      ),
                      typeChip(
                        HistoryTypeFilter.delivery,
                        'shippingbox',
                        t('history.type.delivery'),
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: Space.sm,
                    children: [
                      syncChip(
                        HistorySyncFilter.all,
                        'list.bullet',
                        t('order.all'),
                        ChipTone.accent,
                      ),
                      syncChip(
                        HistorySyncFilter.synced,
                        'checkmark.icloud',
                        t('history.synced'),
                        ChipTone.success,
                      ),
                      syncChip(
                        HistorySyncFilter.pending,
                        'icloud.and.arrow.up',
                        t('history.queued'),
                        ChipTone.warning,
                      ),
                      syncChip(
                        HistorySyncFilter.voided,
                        'xmark.circle',
                        t('history.voided'),
                        ChipTone.danger,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Hairline(light: true),
      ],
    );
  }
}

// ── Content ──────────────────────────────────────────────────────────────────
class _HistoryContent extends ConsumerWidget {
  const _HistoryContent({required this.onPrint, required this.onVoid});

  final void Function(OrderSummaryView) onPrint;
  final void Function(OrderSummaryView) onVoid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final notifier = ref.read(historyProvider.notifier);
    final loading = ref.watch(historyProvider.select((s) => s.loading));
    final history = ref.watch(historyProvider.select((s) => s.history));
    final filtered = ref.watch(historyProvider.select((s) => s.filtered));
    final visibleLimit = ref.watch(
      historyProvider.select((s) => s.visibleLimit),
    );
    final report = ref.watch(historyProvider.select((s) => s.report));
    final expandedId = ref.watch(historyProvider.select((s) => s.expandedId));
    final detail = ref.watch(historyProvider.select((s) => s.detail));
    final sortCol = ref.watch(historyProvider.select((s) => s.sortCol));
    final sortAscending = ref.watch(
      historyProvider.select((s) => s.sortAscending),
    );
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    String t(String key) => bridge.tr(key: key);

    if (loading && history.isEmpty) {
      return const Align(alignment: Alignment.topCenter, child: SkeletonList());
    }
    if (filtered.isEmpty) {
      return EmptyState(
        icon: history.isEmpty ? 'tray' : 'line.3.horizontal.decrease.circle',
        title: history.isEmpty ? t('history.empty') : t('history.no_match'),
      );
    }
    final visible = filtered.take(visibleLimit).toList();
    return ResponsiveBuilder(
      builder: (context, info) {
        final wide = info.isWideTable;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            // Slivers so only on-screen rows are built — 'show more' grows
            // `visible` without bound, so the card path must stay lazy.
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsetsDirectional.all(Space.lg),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            bottom: Space.lg,
                          ),
                          child: _StatsHeader(
                            history: history,
                            report: report,
                            currency: currency,
                            tr: t,
                          ),
                        ),
                      ),
                      if (wide)
                        SliverToBoxAdapter(
                          child: _OrderTable(
                            visible: visible,
                            currency: currency,
                            expandedId: expandedId,
                            detail: detail,
                            sortCol: sortCol,
                            sortAscending: sortAscending,
                            bridge: bridge,
                            onSort: notifier.setSort,
                            onToggle: notifier.toggle,
                            onPrint: onPrint,
                            onVoid: onVoid,
                          ),
                        )
                      else
                        SliverList.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final o = visible[index];
                            return Padding(
                              padding: const EdgeInsetsDirectional.only(
                                bottom: Space.lg,
                              ),
                              child: _OrderCard(
                                order: o,
                                currency: currency,
                                expanded: expandedId == o.id,
                                detail: detail,
                                bridge: bridge,
                                onToggle: () => notifier.toggle(o),
                                onPrint: () => onPrint(o),
                                onVoid: () => onVoid(o),
                              ),
                            );
                          },
                        ),
                      SliverToBoxAdapter(
                        child: _ShowMoreFooter(
                          remaining: filtered.length - visible.length,
                          label: t('history.show_more'),
                          onShowMore: notifier.showMore,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Stats header ─────────────────────────────────────────────────────────────
// `[orders count] | [Total (success)] [· one chip per payment method]`.
// Prefers the live shift report; folds over local (non-voided) history
// otherwise.
class _StatsHeader extends StatelessWidget {
  const _StatsHeader({
    required this.history,
    required this.report,
    required this.currency,
    required this.tr,
  });

  final List<OrderSummaryView> history;
  final ShiftReportView? report;
  final String currency;
  final String Function(String) tr;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final nonVoided = history.where((o) => o.status != 'voided').toList();
    final total =
        report?.netPaymentsMinor ??
        nonVoided.fold<int>(0, (sum, o) => sum + o.totalMinor);
    final denom = total > 1 ? total : 1;

    final breakdown = <(String, int, ChipTone)>[];
    final lines = report?.paymentLines;
    if (lines != null && lines.isNotEmpty) {
      for (final l in lines) {
        breakdown.add((
          l.method,
          l.totalMinor,
          l.isCash ? ChipTone.success : ChipTone.info,
        ));
      }
    } else {
      final sums = <String, int>{};
      for (final o in nonVoided) {
        sums[o.paymentLabel] = (sums[o.paymentLabel] ?? 0) + o.totalMinor;
      }
      for (final MapEntry(key: label, value: amount) in sums.entries) {
        breakdown.add((
          label,
          amount,
          label.toLowerCase().contains('cash')
              ? ChipTone.success
              : ChipTone.info,
        ));
      }
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          spacing: Space.md,
          children: [
            _StatCell(
              label: tr('history.stat.orders'),
              value: '${nonVoided.length}',
              color: colors.textPrimary,
            ),
            Container(
              width: 1,
              height: _statDividerHeight,
              color: colors.border,
            ),
            _StatCell(
              label: tr('order.total'),
              value: Money.format(total, currency: currency),
              color: colors.success,
            ),
            for (final (label, amount, tone) in breakdown)
              StatusChip(
                label:
                    '$label · ${Money.format(amount, currency: currency)}'
                    ' · ${amount * 100 ~/ denom}%',
                tone: tone,
              ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          label.toUpperCase(),
          style: MadarType.labelSm.copyWith(color: colors.textMuted),
        ),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: MadarType.money.copyWith(fontSize: 16, color: color),
        ),
      ],
    );
  }
}

// ── Wide TABLE ───────────────────────────────────────────────────────────────
class _OrderTable extends StatelessWidget {
  const _OrderTable({
    required this.visible,
    required this.currency,
    required this.expandedId,
    required this.detail,
    required this.sortCol,
    required this.sortAscending,
    required this.bridge,
    required this.onSort,
    required this.onToggle,
    required this.onPrint,
    required this.onVoid,
  });

  final List<OrderSummaryView> visible;
  final String currency;
  final String? expandedId;
  final OrderDetailView? detail;
  final HistorySortCol sortCol;
  final bool sortAscending;
  final MadarBridge bridge;
  final void Function(HistorySortCol) onSort;
  final void Function(OrderSummaryView) onToggle;
  final void Function(OrderSummaryView) onPrint;
  final void Function(OrderSummaryView) onVoid;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    String t(String key) => bridge.tr(key: key);
    Widget headerCell(
      String label,
      HistorySortCol col, {
      double? width,
      bool trailing = false,
    }) {
      final cell = _HeaderCell(
        label: label,
        active: sortCol == col,
        ascending: sortAscending,
        trailing: trailing,
        onTap: () => onSort(col),
      );
      return width != null
          ? SizedBox(width: width, child: cell)
          : Expanded(child: cell);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          children: [
            ColoredBox(
              color: colors.surfaceAlt,
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                child: Row(
                  spacing: Space.md,
                  children: [
                    headerCell(
                      '#',
                      HistorySortCol.number,
                      width: _numberColWidth,
                    ),
                    headerCell(t('order.payment'), HistorySortCol.payment),
                    headerCell(t('history.col.time'), HistorySortCol.time),
                    headerCell(t('history.col.teller'), HistorySortCol.teller),
                    headerCell(
                      t('history.col.amount'),
                      HistorySortCol.amount,
                      width: _amountColWidth,
                      trailing: true,
                    ),
                    const SizedBox(width: _disclosureColWidth),
                  ],
                ),
              ),
            ),
            const Hairline(),
            for (final (idx, o) in visible.indexed) ...[
              _TableRow(
                order: o,
                currency: currency,
                zebra: idx.isOdd,
                expanded: expandedId == o.id,
                detail: detail,
                bridge: bridge,
                onToggle: () => onToggle(o),
                onPrint: () => onPrint(o),
                onVoid: () => onVoid(o),
              ),
              if (idx < visible.length - 1) const Hairline(light: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.active,
    required this.ascending,
    required this.trailing,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool ascending;
  final bool trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = active ? colors.accent : colors.textMuted;
    final arrow = active
        ? MadarIcon(
            ascending ? 'arrow.up' : 'arrow.down',
            tint: fg,
            size: _sortArrowSize,
          )
        : null;
    return Semantics(
      button: true,
      child: TactileScale(
        onTap: onTap,
        child: Row(
          mainAxisAlignment: trailing
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          spacing: 3,
          children: [
            if (trailing && arrow != null) arrow,
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.labelSm.copyWith(
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            if (!trailing && arrow != null) arrow,
          ],
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.order,
    required this.currency,
    required this.zebra,
    required this.expanded,
    required this.detail,
    required this.bridge,
    required this.onToggle,
    required this.onPrint,
    required this.onVoid,
  });

  final OrderSummaryView order;
  final String currency;
  final bool zebra;
  final bool expanded;
  final OrderDetailView? detail;
  final MadarBridge bridge;
  final VoidCallback onToggle;
  final VoidCallback onPrint;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final o = order;
    final voided = o.status == 'voided';
    final rowDetail = detail?.id == o.id ? detail : null;
    final loadingDetail = expanded && !o.queued && rowDetail == null;
    final rowBg = expanded
        ? colors.navyBg
        : zebra
        ? colors.surfaceAlt
        : const Color(0x00000000);
    return ColoredBox(
      color: rowBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Opacity(
              opacity: voided ? _voidedAlpha : 1,
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: Metrics.tableRowHeight,
                ),
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: Space.md,
                ),
                child: Row(
                  spacing: Space.md,
                  children: [
                    // # cell — queued cloud icon, else number (+ optional ref).
                    SizedBox(
                      width: _numberColWidth,
                      child: o.queued
                          ? Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: MadarIcon(
                                'icloud.and.arrow.up',
                                tint: colors.warning,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              spacing: 1,
                              children: [
                                Text(
                                  o.orderNumber != null
                                      ? '#${o.orderNumber}'
                                      : bridge.tr(key: 'history.order'),
                                  style: MadarType.body.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colors.navy,
                                  ),
                                ),
                                if (o.orderRef case final ref?)
                                  Text(
                                    ref,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MadarType.labelSm.copyWith(
                                      fontSize: _orderRefSize,
                                      fontWeight: FontWeight.w400,
                                      color: colors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    Expanded(
                      child: _PaymentCell(
                        order: o,
                        voided: voided,
                        bridge: bridge,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        bridge.formatTime(
                          rfc3339: o.createdAt,
                          style: TimeStyle.time,
                        ),
                        style: MadarType.bodySm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(child: _TellerCell(order: o, fontSize: 12)),
                    SizedBox(
                      width: _amountColWidth,
                      child: Text(
                        Money.format(o.totalMinor, currency: currency),
                        textDirection: TextDirection.ltr,
                        style: MadarType.money.copyWith(
                          fontWeight: FontWeight.w600,
                          color: voided ? colors.textMuted : colors.textPrimary,
                          decoration: voided
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: _disclosureColWidth,
                      child: Center(
                        child: _DisclosureIndicator(
                          expanded: expanded,
                          loading: loadingDetail,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: Space.md,
                end: Space.md,
                bottom: Space.md,
              ),
              child: _OrderDetailPanel(
                order: o,
                detail: rowDetail,
                currency: currency,
                bridge: bridge,
                onPrint: onPrint,
                onVoid: onVoid,
              ),
            ),
        ],
      ),
    );
  }
}

/// The trailing chevron that rotates open, or the row's detail spinner.
class _DisclosureIndicator extends StatelessWidget {
  const _DisclosureIndicator({required this.expanded, required this.loading});

  final bool expanded;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    if (loading) {
      return SizedBox.square(
        dimension: _rowSpinner,
        child: CircularProgressIndicator(
          color: colors.textMuted,
          strokeWidth: 2,
        ),
      );
    }
    return AnimatedRotation(
      turns: expanded ? 0.5 : 0,
      duration: MotionSpec.standardDuration,
      curve: MotionSpec.standardCurve,
      child: MadarIcon('chevron.down', tint: colors.textMuted, size: 13),
    );
  }
}

class _PaymentCell extends StatelessWidget {
  const _PaymentCell({
    required this.order,
    required this.voided,
    required this.bridge,
  });

  final OrderSummaryView order;
  final bool voided;
  final MadarBridge bridge;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final o = order;
    String t(String key) => bridge.tr(key: key);
    return Row(
      spacing: 6,
      children: [
        Flexible(
          child: PaymentBadge(label: o.paymentLabel, voided: voided),
        ),
        if (voided)
          StatusChip(label: t('history.voided'), tone: ChipTone.danger)
        else if (o.status == 'failed')
          StatusChip(label: t('history.failed'), tone: ChipTone.danger)
        else if (o.queued)
          StatusChip(
            label: t('history.queued'),
            tone: ChipTone.warning,
            icon: 'arrow.triangle.2.circlepath',
          ),
        if (o.customerName case final customer?)
          Flexible(
            child: Text(
              customer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MadarType.label.copyWith(
                fontWeight: FontWeight.w400,
                color: colors.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}

class _TellerCell extends StatelessWidget {
  const _TellerCell({required this.order, required this.fontSize});

  final OrderSummaryView order;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      spacing: Space.xs,
      children: [
        MadarIcon('person', tint: colors.textMuted, size: IconSize.xs),
        Flexible(
          child: Text(
            order.tellerName ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MadarType.label.copyWith(
              fontSize: fontSize,
              fontWeight: FontWeight.w400,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Narrow CARD ──────────────────────────────────────────────────────────────
class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.currency,
    required this.expanded,
    required this.detail,
    required this.bridge,
    required this.onToggle,
    required this.onPrint,
    required this.onVoid,
  });

  final OrderSummaryView order;
  final String currency;
  final bool expanded;
  final OrderDetailView? detail;
  final MadarBridge bridge;
  final VoidCallback onToggle;
  final VoidCallback onPrint;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final o = order;
    final voided = o.status == 'voided';
    final rowDetail = detail?.id == o.id ? detail : null;
    final loadingDetail = expanded && !o.queued && rowDetail == null;
    String t(String key) => bridge.tr(key: key);
    return Container(
      decoration: BoxDecoration(
        color: expanded ? colors.navyBg : colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Opacity(
              opacity: voided ? _voidedAlpha : 1,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.sm,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Space.xs,
                      children: [
                        Row(
                          spacing: 6,
                          children: [
                            if (o.queued)
                              MadarIcon(
                                'icloud.and.arrow.up',
                                tint: colors.warning,
                                size: IconSize.sm,
                              ),
                            Text(
                              o.orderNumber != null
                                  ? '#${o.orderNumber}'
                                  : t('history.order'),
                              style: MadarType.body.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.navy,
                              ),
                            ),
                            Text(
                              bridge.formatTime(
                                rfc3339: o.createdAt,
                                style: TimeStyle.time,
                              ),
                              style: MadarType.labelSm.copyWith(
                                fontWeight: FontWeight.w400,
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          spacing: 6,
                          children: [
                            Flexible(
                              child: PaymentBadge(
                                label: o.paymentLabel,
                                voided: voided,
                              ),
                            ),
                            if (voided)
                              StatusChip(
                                label: t('history.voided'),
                                tone: ChipTone.danger,
                              )
                            else if (o.status == 'failed')
                              StatusChip(
                                label: t('history.failed'),
                                tone: ChipTone.danger,
                              )
                            else if (o.queued)
                              StatusChip(
                                label: t('history.queued'),
                                tone: ChipTone.warning,
                              ),
                          ],
                        ),
                        if (o.customerName case final customer?)
                          Text(
                            customer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MadarType.label.copyWith(
                              fontWeight: FontWeight.w400,
                              color: colors.textMuted,
                            ),
                          ),
                        _TellerCell(order: o, fontSize: 11),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    spacing: Space.xs,
                    children: [
                      Text(
                        Money.format(o.totalMinor, currency: currency),
                        textDirection: TextDirection.ltr,
                        style: MadarType.money.copyWith(
                          fontSize: 15,
                          color: voided ? colors.textMuted : colors.textPrimary,
                          decoration: voided
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      _DisclosureIndicator(
                        expanded: expanded,
                        loading: loadingDetail,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Hairline(),
            _OrderDetailPanel(
              order: o,
              detail: rowDetail,
              currency: currency,
              bridge: bridge,
              onPrint: onPrint,
              onVoid: onVoid,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Shared expanded detail (line items + totals + Print/Void) ────────────────
class _OrderDetailPanel extends StatelessWidget {
  const _OrderDetailPanel({
    required this.order,
    required this.detail,
    required this.currency,
    required this.bridge,
    required this.onPrint,
    required this.onVoid,
  });

  final OrderSummaryView order;
  final OrderDetailView? detail;
  final String currency;
  final MadarBridge bridge;
  final VoidCallback onPrint;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final o = order;
    final d = detail;
    final canAct = !o.queued && o.status != 'voided';
    String t(String key) => bridge.tr(key: key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        if (d != null) ...[
          for (final line in d.lines) _LineRow(line: line, currency: currency),
          const Hairline(light: true),
          _DetailRow(
            label: t('order.subtotal'),
            value: Money.format(d.subtotalMinor, currency: currency),
          ),
          if (d.discountMinor > 0)
            _DetailRow(
              label: t('order.discount'),
              value: '− ${Money.format(d.discountMinor, currency: currency)}',
              color: colors.success,
            ),
          _DetailRow(
            label: t('order.tax'),
            value: Money.format(d.taxMinor, currency: currency),
          ),
        ] else ...[
          // Queued/offline order, or detail not yet loaded — summary totals.
          _DetailRow(
            label: t('order.subtotal'),
            value: Money.format(o.subtotalMinor, currency: currency),
          ),
          _DetailRow(
            label: t('order.tax'),
            value: Money.format(o.taxMinor, currency: currency),
          ),
        ],
        // Grand-total block — tinted teal, money as the hero (mirrors the
        // cart's CartFooter total).
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.accentBg,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.md,
              vertical: Space.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t('order.total'),
                    style: MadarType.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.accent,
                    ),
                  ),
                ),
                MoneyText(
                  o.totalMinor,
                  currency: currency,
                  style: MadarType.money.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        Row(
          spacing: Space.md,
          children: [
            Expanded(
              child: Text(
                o.paymentLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.label.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colors.textSecondary,
                ),
              ),
            ),
            if (canAct) ...[
              _DetailAction(
                label: t('receipt.print'),
                glyph: 'printer',
                color: colors.accent,
                onTap: onPrint,
              ),
              _DetailAction(
                label: t('void.action'),
                glyph: 'trash',
                color: colors.danger,
                onTap: onVoid,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A leading-icon text action in the expanded detail panel (Print / Void).
class _DetailAction extends StatelessWidget {
  const _DetailAction({
    required this.label,
    required this.glyph,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String glyph;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: TactileScale(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            MadarIcon(glyph, tint: color, size: IconSize.xs),
            Text(label, style: MadarType.label.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
        ),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: MadarType.money.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color ?? colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// One fetched order line — "qty× name" + its modifiers on the left, the
/// line total on the right.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.currency});

  final OrderDetailLineView line;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final mods = <String>[
      ?line.sizeLabel,
      ...line.addons,
      ...line.optionals,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 1,
            children: [
              Text(
                '${line.qty}× ${line.name}',
                style: MadarType.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              if (mods.isNotEmpty)
                Text(
                  mods.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.labelSm.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.textMuted,
                  ),
                ),
            ],
          ),
        ),
        MoneyText(
          line.lineTotalMinor,
          currency: currency,
          style: MadarType.money.copyWith(fontSize: 13),
        ),
      ],
    );
  }
}

// ── Pagination footer ────────────────────────────────────────────────────────
class _ShowMoreFooter extends StatelessWidget {
  const _ShowMoreFooter({
    required this.remaining,
    required this.label,
    required this.onShowMore,
  });

  final int remaining;

  /// The `history.show_more` template carrying a `{count}` placeholder.
  final String label;
  final VoidCallback onShowMore;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    if (remaining <= 0) return const SizedBox.shrink();
    final count = remaining < kHistoryPageSize ? remaining : kHistoryPageSize;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: Space.lg),
      child: Semantics(
        button: true,
        child: TactileScale(
          scale: 0.98,
          onTap: onShowMore,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: colors.border),
            ),
            padding: const EdgeInsetsDirectional.symmetric(
              vertical: Space.md,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 6,
              children: [
                MadarIcon(
                  'chevron.down',
                  tint: colors.accent,
                  size: IconSize.xs,
                ),
                Text(
                  label.replaceAll('{count}', '$count'),
                  style: MadarType.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Void sheet ───────────────────────────────────────────────────────────────

/// The void form's state (reason radios / restock toggle / busy / error).
class _VoidFormState {
  const _VoidFormState({
    this.reason = 'mistake',
    this.restock = true,
    this.busy = false,
    this.error,
  });

  final String reason;
  final bool restock;
  final bool busy;
  final String? error;

  static const Object _unset = Object();

  _VoidFormState copyWith({
    String? reason,
    bool? restock,
    bool? busy,
    Object? error = _unset,
  }) {
    return _VoidFormState(
      reason: reason ?? this.reason,
      restock: restock ?? this.restock,
      busy: busy ?? this.busy,
      error: error == _unset ? this.error : error as String?,
    );
  }
}

class _VoidFormNotifier extends Notifier<_VoidFormState> {
  bool _alive = true;

  @override
  _VoidFormState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    return const _VoidFormState();
  }

  void selectReason(String reason) => state = state.copyWith(reason: reason);

  void toggleRestock({required bool on}) => state = state.copyWith(restock: on);

  /// Void the order — true on success (the sheet pops). A void moves the
  /// shift stats, so the shell refreshes here; failures land in
  /// [_VoidFormState.error].
  Future<bool> confirm({required String orderId, required String note}) async {
    final bridge = ref.read(bridgeProvider);
    state = state.copyWith(busy: true, error: null);
    try {
      await bridge.voidOrder(
        orderId: orderId,
        reason: state.reason,
        note: note.isEmpty ? null : note,
        restoreInventory: state.restock,
      );
      ref.read(shellProvider.notifier).refresh();
      return true;
    } on MadarError catch (e) {
      if (e is MadarError_Unauthenticated &&
          ref.read(shellProvider).session != null) {
        ref.read(reauthRequestProvider.notifier).request();
      }
      if (_alive) {
        state = state.copyWith(busy: false, error: bridge.humanMessage(e));
      }
      return false;
    }
  }
}

final NotifierProvider<_VoidFormNotifier, _VoidFormState> _voidFormProvider =
    NotifierProvider.autoDispose<_VoidFormNotifier, _VoidFormState>(
      _VoidFormNotifier.new,
    );

/// The natives' VoidOverlay: reason radios, an optional note, the restock
/// toggle, and one danger CTA. Pops `true` after a successful void.
class _VoidSheet extends ConsumerStatefulWidget {
  const _VoidSheet({required this.order});

  final OrderSummaryView order;

  @override
  ConsumerState<_VoidSheet> createState() => _VoidSheetState();
}

class _VoidSheetState extends ConsumerState<_VoidSheet> {
  final TextEditingController _note = TextEditingController();

  static const List<(String, String)> _reasons = [
    ('mistake', 'void.reason_mistake'),
    ('customer', 'void.reason_customer'),
    ('quality', 'void.reason_quality'),
    ('other', 'void.reason_other'),
  ];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final ok = await ref
        .read(_voidFormProvider.notifier)
        .confirm(orderId: widget.order.id, note: _note.text.trim());
    if (ok && mounted) await Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final form = ref.watch(_voidFormProvider);
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final o = widget.order;
    String t(String key) => bridge.tr(key: key);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.lg,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('void.title'),
                        style: MadarType.h2.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    TactileScale(
                      onTap: () =>
                          unawaited(Navigator.of(context).maybePop(false)),
                      child: MadarIcon('xmark', tint: colors.textMuted),
                    ),
                  ],
                ),
                // The order being voided — number + total.
                Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: colors.borderLight),
                    boxShadow: MadarElevation.card.shadows(
                      colors,
                      dark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                  padding: const EdgeInsetsDirectional.all(Space.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          o.orderNumber != null
                              ? '#${o.orderNumber}'
                              : t('history.order'),
                          style: MadarType.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      MoneyText(
                        o.totalMinor,
                        currency: currency,
                        style: MadarType.money.copyWith(fontSize: 15),
                        color: colors.textPrimary,
                      ),
                    ],
                  ),
                ),
                Text(
                  t('void.reason'),
                  style: MadarType.label.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: MadarType.tracking,
                    color: colors.textMuted,
                  ),
                ),
                for (final (key, label) in _reasons)
                  _ReasonRow(
                    label: t(label),
                    active: form.reason == key,
                    onTap: () =>
                        ref.read(_voidFormProvider.notifier).selectReason(key),
                  ),
                HistoryTextField(
                  controller: _note,
                  placeholder: t('void.note'),
                  icon: 'note.text',
                  enabled: !form.busy,
                ),
                const Hairline(),
                Row(
                  spacing: Space.sm,
                  children: [
                    Expanded(
                      child: Text(
                        t('void.restock'),
                        style: MadarType.body.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    _RestockSwitch(
                      value: form.restock,
                      onChanged: (v) => ref
                          .read(_voidFormProvider.notifier)
                          .toggleRestock(on: v),
                    ),
                  ],
                ),
                if (form.error case final error?)
                  NoticeBanner(text: error, tone: ChipTone.danger),
                Row(
                  spacing: Space.md,
                  children: [
                    Expanded(
                      child: HistoryButton(
                        label: t('void.cancel'),
                        variant: HistoryButtonVariant.outline,
                        onTap: () =>
                            unawaited(Navigator.of(context).maybePop(false)),
                      ),
                    ),
                    Expanded(
                      child: HistoryButton(
                        label: t('void.confirm'),
                        variant: HistoryButtonVariant.danger,
                        icon: 'trash',
                        loading: form.busy,
                        onTap: () => unawaited(_confirm()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Semantics(
      button: true,
      selected: active,
      child: TactileScale(
        scale: 0.99,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: active ? colors.dangerBg : colors.surface,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: active
                  ? colors.danger.withValues(alpha: Opacities.disabled)
                  : colors.border,
            ),
          ),
          padding: const EdgeInsetsDirectional.all(Space.md),
          child: Row(
            spacing: Space.md,
            children: [
              MadarIcon(
                active ? 'largecircle.fill.circle' : 'circle',
                tint: active ? colors.danger : colors.textMuted,
                size: IconSize.lg,
              ),
              Expanded(
                child: Text(
                  label,
                  style: MadarType.body.copyWith(
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: colors.textPrimary,
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

/// A tokens-only toggle standing in for the natives' material Switch —
/// accent track when on, bordered surfaceAlt when off, animated thumb.
class _RestockSwitch extends StatelessWidget {
  const _RestockSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Semantics(
      toggled: value,
      child: TactileScale(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: MotionSpec.standardDuration,
          curve: MotionSpec.standardCurve,
          width: _switchTrack.width,
          height: _switchTrack.height,
          padding: const EdgeInsetsDirectional.all(
            (26 - _switchThumb) / 2,
          ),
          decoration: BoxDecoration(
            color: value ? colors.accent : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: value ? null : Border.all(color: colors.border),
          ),
          child: AnimatedAlign(
            duration: MotionSpec.standardDuration,
            curve: MotionSpec.standardCurve,
            alignment: value
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: value ? colors.textOnAccent : colors.textMuted,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: _switchThumb),
            ),
          ),
        ),
      ),
    );
  }
}
