/// The Orders page's pieces: the delivery block (`orders/delivery-channels.tsx`,
/// SELL-ORD-016/017) and the exclude-items control on Items Sold
/// (`components/app/exclude-items-control.tsx`, SELL-ORD-013 … SELL-ORD-015).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show DeliveryChannelSales, DeliverySalesReport, MenuItem;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'order_lines.dart';
import 'orders_providers.dart';

// ── the delivery block ───────────────────────────────────────────────────

/// The two channels the card names; any other shows its raw code under a
/// store glyph (`CHANNEL_META`).
const Map<String, (String, String)> _channelMeta = {
  'in_mall': ('delivery.inMall', 'store'),
  'outside': ('delivery.outside', 'bike'),
};

/// Four totals, then one card per channel.
class OrdersDeliveryChannels extends ConsumerWidget {
  const OrdersDeliveryChannels({
    required this.data,
    this.loading = false,
    super.key,
  });

  final DeliverySalesReport? data;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final d = data;
    final channels = d?.channels ?? const <DeliveryChannelSales>[];
    var maxRev = 1;
    for (final ch in channels) {
      if (ch.revenue > maxRev) maxRev = ch.revenue;
    }
    final cards = loading
        ? [for (var i = 0; i < 2; i++) const _ChannelSkeleton()]
        : [
            for (final ch in channels)
              _ChannelCard(
                channel: ch,
                total: d?.totalRevenue ?? 0,
                maxRevenue: maxRev,
              ),
          ];
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final gap = wide ? Space.lg : Space.md;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashLedgerStrip(
          items: [
            DashLedgerItem(
              key: 'rev',
              label: t('delivery.revenue'),
              icon: 'coins',
              value: d?.totalRevenue ?? 0,
              format: DashStatFormat.money,
              loading: loading,
            ),
            DashLedgerItem(
              key: 'orders',
              label: t('delivery.deliveredOrders'),
              icon: 'receipt',
              value: d?.totalOrders ?? 0,
              format: DashStatFormat.number,
              loading: loading,
            ),
            DashLedgerItem(
              key: 'avg',
              label: t('dashboard.avgTicket'),
              icon: 'trending-up',
              value: d?.avgOrderValue ?? 0,
              format: DashStatFormat.money,
              loading: loading,
            ),
            DashLedgerItem(
              key: 'fees',
              label: t('delivery.fees'),
              icon: 'truck',
              value: d?.totalDeliveryFees ?? 0,
              format: DashStatFormat.money,
              loading: loading,
            ),
          ],
        ),
        if (!wide)
          ...cards
        else
          for (var i = 0; i < cards.length; i += 2)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: gap,
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

class _ChannelSkeleton extends StatelessWidget {
  const _ChannelSkeleton();

  @override
  Widget build(BuildContext context) => const DashCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.md,
      children: [
        DashSkeleton(width: Space.xxl * 4),
        DashSkeleton(width: Space.xxl * 3.5, height: Space.xl + Space.xs),
        DashSkeleton(width: double.infinity, height: DashMetrics.progress),
      ],
    ),
  );
}

class _ChannelCard extends ConsumerWidget {
  const _ChannelCard({
    required this.channel,
    required this.total,
    required this.maxRevenue,
  });

  final DeliveryChannelSales channel;
  final int total;
  final int maxRevenue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final ch = channel;
    final meta = _channelMeta[ch.channel];
    final muted = DashType.meta.copyWith(color: c.textSecondary);
    final figure = DashType.mono.copyWith(
      fontSize: DashType.meta.fontSize,
      color: c.textPrimary,
    );
    return DashCard(
      key: ValueKey('delivery-channel-${ch.channel}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Row(
            spacing: Space.sm,
            children: [
              DashIcon(meta?.$2 ?? 'store', color: c.textSecondary),
              Expanded(
                child: MadarClippedText(
                  meta == null ? ch.channel : t(meta.$1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyMedium.copyWith(color: c.textSecondary),
                ),
              ),
              Text(
                fmt.fmtShare(ch.revenue, total),
                style: DashType.mono.copyWith(
                  fontSize: DashType.small.fontSize,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
          DashConciseValue(
            full: fmt.fmtMoney(ch.revenue),
            compact: fmt.fmtMoneyCompact(ch.revenue),
            style: DashType.statFigure(24).copyWith(color: c.textPrimary),
          ),
          DashProgressBar(
            value: ch.revenue < maxRevenue * 0.02
                ? maxRevenue * 0.02
                : ch.revenue.toDouble(),
            max: maxRevenue.toDouble(),
            semanticLabel: t('delivery.revenueShare'),
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              Wrap(
                spacing: Space.md,
                runSpacing: Space.xs,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${t('delivery.deliveredOrders')} '),
                        TextSpan(text: ltr(fmt.fmtNumber(ch.orders)), style: figure),
                      ],
                    ),
                    style: muted,
                  ),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${t('delivery.fees')} '),
                        TextSpan(text: fmt.fmtMoney(ch.deliveryFees), style: figure),
                      ],
                    ),
                    style: muted,
                  ),
                ],
              ),
              if (ch.cancelledOrders > 0)
                DashStatusPill(
                  small: true,
                  tone: DashTone.warning,
                  label:
                      '${ltr(fmt.fmtNumber(ch.cancelledOrders))} ${t('delivery.cancelled')}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── the exclude control ──────────────────────────────────────────────────

/// A funnel on the Items Sold tile: a searchable list of the org's menu
/// where a tap leaves an item out of the count (and puts it back), kept per
/// org on this device. The menu loads only once the list opens.
class OrdersExcludeItemsControl extends ConsumerWidget {
  const OrdersExcludeItemsControl({required this.orgId, super.key});

  final String? orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final excluded = ref.watch(ordersExcludedProvider(orgId));
    final any = excluded.isNotEmpty;
    return DashPopover(
      width: Space.xxl * 8,
      align: DashPopoverAlign.end,
      anchor: (context, ctl) => DashPressable(
        key: const ValueKey('orders-exclude-trigger'),
        onTap: ctl.toggle,
        onIntent: orgId == null
            ? null
            : () => ref.warm(ordersMenuItemsProvider(orgId!)),
        pressScale: false,
        tooltip: t('analytics.excludeItems'),
        semanticLabel: t('analytics.excludeItems'),
        excludeChildSemantics: true,
        builder: (context, s) => SizedBox.square(
          dimension: DashMetrics.target,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                DashIcon(
                  'list-filter',
                  size: IconSize.xs,
                  color: any ? c.info : c.textSecondary,
                ),
                if (any)
                  PositionedDirectional(
                    end: -Space.sm,
                    top: -Space.sm,
                    child: Container(
                      key: const ValueKey('orders-exclude-count'),
                      width: Space.md + DashMetrics.hair,
                      height: Space.md + DashMetrics.hair,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.info,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${excluded.length}',
                        style: DashType.smallStrong.copyWith(
                          fontSize: 9,
                          height: 1,
                          color: c.textOnAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      content: (context, ctl) => _ExcludeList(orgId: orgId),
    );
  }
}

class _ExcludeList extends ConsumerStatefulWidget {
  const _ExcludeList({required this.orgId});

  final String? orgId;

  @override
  ConsumerState<_ExcludeList> createState() => _ExcludeListState();
}

class _ExcludeListState extends ConsumerState<_ExcludeList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final org = widget.orgId;
    final excluded = ref.watch(ordersExcludedProvider(org));
    final notifier = ref.read(ordersExcludedProvider(org).notifier);
    final AsyncValue<List<MenuItem>> menu = org == null
        ? const AsyncData(<MenuItem>[])
        : ref.watch(ordersMenuItemsProvider(org));
    final options = [
      for (final m in menu.value ?? const <MenuItem>[])
        (m.id, translatedName(m.name, m.nameTranslations, lang)),
    ];
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final o in options)
        if (q.isEmpty || o.$2.toLowerCase().contains(q)) o,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.4),
            border: Border(bottom: BorderSide(color: c.hairline)),
          ),
          child: Text(
            t('analytics.excludeScopeNote'),
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Space.sm),
          child: DashSearchInput(
            key: const ValueKey('orders-exclude-search'),
            value: _query,
            placeholder: t('common.search'),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Flexible(
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Text(
                    menu.awaitingFirst ? t('common.loading') : t('common.noResults'),
                    textAlign: TextAlign.center,
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.md,
                        vertical: Space.xs,
                      ),
                      child: Text(
                        t('analytics.excludedFromCount'),
                        style: DashType.smallMedium.copyWith(color: c.textSecondary),
                      ),
                    ),
                    for (final (id, label) in shown)
                      DashPressable(
                        key: ValueKey('orders-exclude-$id'),
                        onTap: () => notifier.toggle(id),
                        pressScale: false,
                        selected: excluded.contains(id),
                        semanticLabel: label,
                        excludeChildSemantics: true,
                        builder: (context, s) => Container(
                          constraints: const BoxConstraints(minHeight: DashMetrics.target),
                          padding: const EdgeInsets.symmetric(horizontal: Space.md),
                          color: s.highlighted ? c.hover : null,
                          child: Row(
                            spacing: Space.sm,
                            children: [
                              Opacity(
                                opacity: excluded.contains(id) ? 1 : 0,
                                child: DashIcon('check', size: IconSize.sm, color: c.textPrimary),
                              ),
                              Expanded(
                                child: MadarClippedText(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DashType.body.copyWith(color: c.textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        if (excluded.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(Space.xs),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.hairline))),
            child: DashButton(
              key: const ValueKey('orders-exclude-clear'),
              label: t('common.clear'),
              variant: DashButtonVariant.ghost,
              size: DashButtonSize.compact,
              expand: true,
              onPressed: () => notifier.set(const []),
            ),
          ),
      ],
    );
  }
}
