/// The delivery block: four totals as quiet stat cards, then one card per
/// channel the server sends. The Orders page's (`orders/delivery-channels.tsx`,
/// SELL-ORD-016/017) and the Home page's Delivery section
/// (`components/app/delivery-kpis.tsx`) are the same block.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show DeliveryChannelSales, DeliverySalesReport;
import 'package:dashboard_core/src/format/format.dart' show ltr;
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/scope/scope.dart' show formatProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two channels the card names; any other shows its raw code under a
/// store glyph (`CHANNEL_META`).
const Map<String, (String, String)> _channelMeta = {
  'in_mall': ('delivery.inMall', 'store'),
  'outside': ('delivery.outside', 'bike'),
};

/// Four totals, then one card per channel.
class DeliveryChannels extends ConsumerWidget {
  const DeliveryChannels({
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
        ? [for (var i = 0; i < 2; i++) const DeliveryChannelSkeleton()]
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

/// A channel card while the report loads.
class DeliveryChannelSkeleton extends StatelessWidget {
  const DeliveryChannelSkeleton({super.key});

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
