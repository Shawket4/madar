/// The Metrics screen (capability `reports.pos_metrics`): the branch's sales,
/// orders, average ticket, payments by method, refunds and voids, top items
/// and sales by hour for a window of branch-local days.
///
/// Every figure, window, share and note comes from the core
/// (`bridge.posMetrics`); this file sequences the call and lays the view out.
/// The call may reach the server, so it runs when a person opens the screen or
/// picks a window, never on a tick.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// What the screen holds: the window asked for and the answer to it.
class MetricsState {
  /// Creates a metrics state.
  const MetricsState({
    this.preset = 'today',
    this.customFrom = '',
    this.customTo = '',
    this.view,
    this.loading = false,
    this.error,
  });

  /// The preset key (`today` … `custom`).
  final String preset;

  /// The custom window's days, as typed (`YYYY-MM-DD`).
  final String customFrom;
  final String customTo;

  /// The last answer, kept while a new one loads.
  final PosMetricsView? view;
  final bool loading;
  final UiText? error;
}

/// Loads the metrics for the chosen window.
class MetricsNotifier extends Notifier<MetricsState> {
  MadarBridge get _bridge => ref.read(bridgeProvider);

  @override
  MetricsState build() => const MetricsState();

  /// Pick the custom window without asking yet: the days are typed first.
  void chooseCustom() {
    state = MetricsState(
      preset: 'custom',
      customFrom: state.customFrom,
      customTo: state.customTo,
      view: state.view,
    );
  }

  /// Ask for [preset] (for `custom`, the two typed days).
  Future<void> load({
    String? preset,
    String? customFrom,
    String? customTo,
  }) async {
    final next = MetricsState(
      preset: preset ?? state.preset,
      customFrom: customFrom ?? state.customFrom,
      customTo: customTo ?? state.customTo,
      view: state.view,
      loading: true,
    );
    state = next;
    final custom = next.preset == 'custom';
    try {
      final view = await _bridge.posMetrics(
        preset: next.preset,
        customFrom: custom ? next.customFrom : null,
        customTo: custom ? next.customTo : null,
      );
      if (!ref.mounted) return;
      state = MetricsState(
        preset: next.preset,
        customFrom: next.customFrom,
        customTo: next.customTo,
        view: view,
      );
    } on MadarError catch (e) {
      if (!ref.mounted) return;
      state = MetricsState(
        preset: next.preset,
        customFrom: next.customFrom,
        customTo: next.customTo,
        view: state.view,
        error: UiText.error(e),
      );
    }
  }
}

/// The Metrics screen's state; dropped when the screen closes.
final NotifierProvider<MetricsNotifier, MetricsState> metricsProvider =
    NotifierProvider.autoDispose<MetricsNotifier, MetricsState>(
      MetricsNotifier.new,
    );

/// The Metrics screen. Pushed from Settings when the person holds
/// `reports.pos_metrics`.
class MetricsScreen extends ConsumerStatefulWidget {
  /// Creates the metrics screen.
  const MetricsScreen({super.key});

  @override
  ConsumerState<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends ConsumerState<MetricsScreen> {
  final _from = TextEditingController();
  final _to = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() => ref.read(metricsProvider.notifier).load()),
    );
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final rtl = ref.watch(localeProvider.select((s) => s.rtl));
    final s = ref.watch(metricsProvider);
    final notifier = ref.read(metricsProvider.notifier);
    final view = s.view;

    final body = <Widget>[
      Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final p in bridge.posMetricsPresets())
            MadarChip(
              label: p.label,
              selected: s.preset == p.key,
              onTap: () => p.key == 'custom'
                  ? notifier.chooseCustom()
                  : unawaited(notifier.load(preset: p.key)),
            ),
        ],
      ),
      if (s.preset == 'custom') ...[
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: MadarField(
                controller: _from,
                placeholder: '${t('metrics.custom_from')} (YYYY-MM-DD)',
                kind: MadarFieldKind.date,
                glyph: MadarGlyph.calendar,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: MadarField(
                controller: _to,
                placeholder: '${t('metrics.custom_to')} (YYYY-MM-DD)',
                kind: MadarFieldKind.date,
                glyph: MadarGlyph.calendar,
              ),
            ),
            const SizedBox(width: Space.sm),
            MadarButton(
              label: t('metrics.show'),
              size: MadarButtonSize.compact,
              onTap: () => unawaited(
                notifier.load(
                  preset: 'custom',
                  customFrom: _from.text,
                  customTo: _to.text,
                ),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: Space.lg),
      if (s.error case final error?) ...[
        NoticeBanner(text: error.of(bridge), tone: ChipTone.danger),
        const SizedBox(height: Space.md),
      ],
      if (view == null && s.loading)
        const Center(child: MadarSpinner())
      else if (view == null)
        ErrorState(
          message: t('metrics.error'),
          retryLabel: t('metrics.retry'),
          onRetry: () => unawaited(notifier.load()),
        )
      else
        ..._figures(context, bridge, view, loading: s.loading),
    ];

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: MadarPageScaffold(
        title: t('metrics.title'),
        subtitle: view?.rangeLabel,
        width: MadarContentWidth.reading,
        actions: [
          MadarHeaderAction(
            glyph: MadarGlyph.refresh,
            tooltip: t('metrics.retry'),
            onTap: () => unawaited(notifier.load()),
          ),
        ],
        body: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: body,
          ),
        ),
      ),
    );
  }

  List<Widget> _figures(
    BuildContext context,
    MadarBridge bridge,
    PosMetricsView v, {
    required bool loading,
  }) {
    String t(String key) => bridge.tr(key: key);
    String money(int minor) => bridge.formatMoney(
      minor: minor,
      currency: v.currencyCode,
      signed: false,
    );
    final colors = context.madarColors;
    final hasSales =
        v.orderCount > 0 || v.voidedCount > 0 || v.refundsIssuedCount > 0;
    return [
      if (v.offlineNote case final note?) ...[
        NoticeBanner(text: note, icon: 'wifi.slash'),
        const SizedBox(height: Space.md),
      ],
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: MadarStatCard(
              label: t('metrics.net_sales'),
              minor: v.netSalesMinor,
              currency: v.currencyCode,
              compact: true,
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: MadarStatCard(
              label: t('metrics.orders'),
              value: '${v.orderCount}',
              compact: true,
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: MadarStatCard(
              label: t('metrics.average_ticket'),
              minor: v.averageTicketMinor,
              currency: v.currencyCode,
              compact: true,
            ),
          ),
        ],
      ),
      if (loading) ...[
        const SizedBox(height: Space.sm),
        const Center(child: MadarSpinner()),
      ],
      if (!hasSales) ...[
        const SizedBox(height: Space.xl),
        EmptyState(icon: 'tray', title: t('metrics.empty')),
      ] else ...[
        const SizedBox(height: Space.lg),
        MadarSectionHeader(text: t('metrics.tenders')),
        MadarCard(
          child: Column(
            children: [
              for (final tender in v.tenders)
                _ShareBar(
                  label: tender.label,
                  value: money(tender.amountMinor),
                  meta: '${tender.orderCount}',
                  share: tender.share,
                  color: colors.accent,
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        MadarSectionHeader(text: t('metrics.refunds_voids')),
        MadarCard(
          flush: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MadarSummaryLine(
                label: t('metrics.gross_sales'),
                value: money(v.grossSalesMinor),
              ),
              MadarSummaryLine(
                label: t('metrics.refunded'),
                value: money(v.refundedAmountMinor),
              ),
              MadarSummaryLine(
                label:
                    '${t('metrics.refunds_issued')} · ${v.refundsIssuedCount}',
                value: money(v.refundsIssuedAmountMinor),
              ),
              MadarSummaryLine(
                label: '${t('metrics.voided')} · ${v.voidedCount}',
                value: money(v.voidedAmountMinor),
              ),
              MadarSummaryLine(
                label: t('metrics.refunded_in_full'),
                value: '${v.refundedOrdersCount}',
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        MadarSectionHeader(text: t('metrics.top_items')),
        if (v.itemsNote case final note?) ...[
          NoticeBanner(text: note, tone: ChipTone.info),
          const SizedBox(height: Space.sm),
        ],
        MadarCard(
          child: Column(
            children: [
              for (final item in v.topItems)
                _ShareBar(
                  label: item.name,
                  value: '${item.quantity}',
                  meta: money(item.revenueMinor),
                  share: item.share,
                  color: colors.navy,
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        MadarSectionHeader(text: t('metrics.hourly')),
        MadarCard(
          child: _HourBars(hours: v.hourly, money: money),
        ),
      ],
    ];
  }
}

/// A labelled horizontal bar: name, figure, a muted figure, the bar.
class _ShareBar extends StatelessWidget {
  const _ShareBar({
    required this.label,
    required this.value,
    required this.meta,
    required this.share,
    required this.color,
  });

  final String label;
  final String value;
  final String meta;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Semantics(
      label: '$label $value $meta',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: Space.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: MadarType.body.copyWith(color: colors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  meta,
                  style: MadarType.num.copyWith(color: colors.textMuted),
                ),
                const SizedBox(width: Space.md),
                Text(
                  value,
                  style: MadarType.money.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.xs),
              child: SizedBox(
                height: Space.sm,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(color: colors.surfaceAlt),
                    ),
                    FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: share,
                      heightFactor: 1,
                      child: ColoredBox(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Twenty-four vertical bars, one per local hour, labelled every third hour.
class _HourBars extends StatelessWidget {
  const _HourBars({required this.hours, required this.money});

  final List<MetricsHourView> hours;
  final String Function(int minor) money;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return SizedBox(
      height: Space.xxl * 4,
      // Hours read left to right in every language, like a clock.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final h in hours)
              Expanded(
                child: Semantics(
                  label:
                      '${h.label} ${money(h.netSalesMinor)} · ${h.orderCount}',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 1,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: h.share,
                              widthFactor: 1,
                              child: ColoredBox(
                                color: h.share > 0
                                    ? colors.accent
                                    : colors.surfaceAlt,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          h.hour % 3 == 0 ? h.label : '',
                          style: MadarType.labelSm.copyWith(
                            color: colors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
