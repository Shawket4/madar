/// Order details — the "what's actually in this order" sheet for a history
/// row: order ref + status, context chips (teller / customer / time), the
/// fetched line items with modifiers, and the money breakdown ending in the
/// tinted-teal grand total. The layout mirrors the natives' shared
/// OrderDetailsSheet.kt surfaces (lines card + totals block) over the
/// history projection (`orderDetail`). Present via `showMadarSheet`
/// (SheetSize.hug). Read-only — Print/Void live on the history rows.
library;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Qty-badge vertical inset (natives: 3.dp).
const double _qtyBadgeVPad = 3;

/// Context-chip vertical inset (natives: 6.dp).
const double _contextChipVPad = 6;

/// Grand-total money size (natives: 20.sp Black; Cairo tops out at w800).
const double _totalMoneySize = 20;

/// Best-effort line fetch — the natives' `loadOrderDetail` swallows
/// failures and the panel falls back to the summary totals.
final AutoDisposeFutureProviderFamily<OrderDetailView?, String>
_orderDetailProvider = FutureProvider.autoDispose
    .family<OrderDetailView?, String>((ref, orderId) async {
      final bridge = ref.watch(bridgeProvider);
      try {
        return await bridge.orderDetail(orderId: orderId);
      } on MadarError {
        return null;
      }
    });

/// Full line breakdown of one history order. Fetches the synced order's
/// lines via `orderDetail` (offline-durable for any order seen online);
/// a still-queued order shows its summary totals only.
class OrderDetailsSheet extends ConsumerWidget {
  /// Creates the details sheet for [order].
  const OrderDetailsSheet({required this.order, super.key});

  /// The history row being expanded.
  final OrderSummaryView order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final o = order;
    // Queued orders aren't on the server yet — no lines to fetch.
    final detailAsync = o.queued
        ? const AsyncValue<OrderDetailView?>.data(null)
        : ref.watch(_orderDetailProvider(o.id));
    final loading = detailAsync.isLoading;
    final detail = detailAsync.valueOrNull;
    final voided = o.status == 'voided';
    String t(String key) => bridge.tr(key: key);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                // Title row — order number + status chip(s).
                Row(
                  spacing: Space.sm,
                  children: [
                    MadarIcon(
                      'receipt',
                      tint: colors.accent,
                      size: IconSize.lg,
                    ),
                    Flexible(
                      child: Text(
                        o.orderNumber != null
                            ? '#${o.orderNumber}'
                            : t('history.order'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.h2.copyWith(color: colors.textPrimary),
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
                        icon: 'icloud.and.arrow.up',
                      )
                    else
                      StatusChip(
                        label: t('history.synced'),
                        tone: ChipTone.success,
                        icon: 'checkmark.icloud',
                      ),
                  ],
                ),

                // Context chips — teller / customer / rung time, when known.
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    if (o.tellerName case final teller?)
                      _ContextChip(icon: 'person', label: teller),
                    if (o.customerName case final customer?)
                      _ContextChip(icon: 'person.fill', label: customer),
                    _ContextChip(
                      icon: 'clock',
                      label: bridge.formatTime(
                        rfc3339: o.createdAt,
                        style: TimeStyle.dateTime,
                      ),
                    ),
                    _ContextChip(icon: 'creditcard', label: o.paymentLabel),
                  ],
                ),

                // Line items — the fetched breakdown (synced orders only).
                if (loading)
                  const SkeletonList(count: 3)
                else if (detail != null)
                  _LinesCard(
                    lines: detail.lines,
                    currency: currency,
                    title: t('order.items'),
                  ),

                // Money breakdown — detail figures when fetched, else the
                // summary's (queued/offline orders).
                _TotalsBlock(
                  totalLabel: t('order.total'),
                  rows: [
                    (
                      t('order.subtotal'),
                      detail?.subtotalMinor ?? o.subtotalMinor,
                      false,
                    ),
                    if ((detail?.discountMinor ?? 0) > 0)
                      (t('order.discount'), -detail!.discountMinor, true),
                    (t('order.tax'), detail?.taxMinor ?? o.taxMinor, false),
                  ],
                  totalMinor: o.totalMinor,
                  currency: currency,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A pill of context (teller / customer / time) with a leading icon.
class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.icon, required this.label});

  final String icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.md,
          vertical: _contextChipVPad,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            MadarIcon(icon, tint: colors.textSecondary, size: IconSize.sm),
            Text(
              label,
              style: MadarType.label.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Line-items card — one row per fetched line: teal qty badge, `name`,
/// size + modifiers under it, and the per-line price on the trailing edge
/// (the natives' OrderLinesCard).
class _LinesCard extends StatelessWidget {
  const _LinesCard({
    required this.lines,
    required this.currency,
    required this.title,
  });

  final List<OrderDetailLineView> lines;
  final String currency;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.borderLight),
        boxShadow: MadarElevation.card.shadows(
          colors,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Text(
            title.toUpperCase(),
            style: MadarType.label.copyWith(color: colors.textMuted),
          ),
          for (final line in lines) _LineRow(line: line, currency: currency),
        ],
      ),
    );
  }
}

/// A single order line — qty badge + name (+ size / modifiers) + total.
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
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.accentBg,
            borderRadius: BorderRadius.circular(Radii.xs),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.sm,
              vertical: _qtyBadgeVPad,
            ),
            child: Text(
              '${line.qty}×',
              style: MadarType.bodySm.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.accent,
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                line.name,
                style: MadarType.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              if (mods.isNotEmpty)
                Text(
                  mods.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.label.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        MoneyText(
          line.lineTotalMinor,
          currency: currency,
          style: MadarType.money,
          color: colors.textPrimary,
        ),
      ],
    );
  }
}

/// Totals block — light muted breakdown rows above a tinted-teal grand
/// total (the hero figure), matching the CheckoutDrawer / CartFooter block.
/// A row's `negative` flag renders it in success green with a minus.
class _TotalsBlock extends StatelessWidget {
  const _TotalsBlock({
    required this.rows,
    required this.totalMinor,
    required this.currency,
    required this.totalLabel,
  });

  final List<(String, int, bool)> rows;
  final int totalMinor;
  final String currency;
  final String totalLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.borderLight),
        boxShadow: MadarElevation.card.shadows(
          colors,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xs,
        children: [
          for (final (label, minor, negative) in rows)
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: MadarType.bodySm.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                MoneyText(
                  minor,
                  currency: currency,
                  style: MadarType.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  color: negative ? colors.success : colors.textSecondary,
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsetsDirectional.only(top: Space.xs),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.accentBg,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.all(Space.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        totalLabel,
                        style: MadarType.body.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.accent,
                        ),
                      ),
                    ),
                    MoneyText(
                      totalMinor,
                      currency: currency,
                      style: MadarType.money.copyWith(
                        fontSize: _totalMoneySize,
                        fontWeight: FontWeight.w800,
                      ),
                      color: colors.accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
