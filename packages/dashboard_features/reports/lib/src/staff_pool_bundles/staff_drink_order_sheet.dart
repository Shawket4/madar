/// The sale a staff drink was rung on (REP-SPL-019), read-only, from the end
/// side (full screen on a phone).
///
/// The web opens the orders area's `OrderDetailSheet` here. The Flutter one
/// (`dashboard_sell`'s `showOrderSheet`) is not a dependency of this package,
/// so this is a local port of the parts of that sheet a staff-drink sale uses
/// (`features/orders/order-detail-sheet.tsx`): the header, who and how it
/// was paid, each line with its staff-drink breakdown, and the totals with
/// the comp put back on one line and taken off under it. See the divergence
/// log for what it leaves to the orders area.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show OrderFull, OrderItemAddon, OrderItemFull;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart';
import 'staff_pool_providers.dart';

/// Opens [orderId]'s sheet and resolves when it closes.
Future<void> showStaffDrinkOrderSheet(
  BuildContext context, {
  required String orderId,
}) => showDashSidePanel<void>(
  context,
  width: StaffDrinkOrderSheet.width,
  builder: (context) => StaffDrinkOrderSheet(orderId: orderId),
);

/// The single-size label a combo part carries; never shown as a size.
const String _oneSize = 'one_size';

/// What a staff-drink line normally rings at, what the pool gave free and
/// what was still charged (`staffDrinkLine`); null on an ordinary line.
({int normal, int comp, int charged})? staffDrinkLine(OrderItemFull it) {
  final isStaff = (it.staffCompMinor ?? 0) > 0 || it.staffDrinkId != null;
  if (!isStaff) return null;
  final comp = (it.staffCompMinor ?? 0) < 0 ? 0 : (it.staffCompMinor ?? 0);
  final addons = it.addons.fold<int>(0, (s, a) => s + a.lineTotal);
  final optionals =
      it.optionals.fold<int>(0, (s, o) => s + o.price) * it.quantity;
  final charged = it.lineTotal + addons + optionals;
  return (normal: charged + comp, comp: comp, charged: charged);
}

/// An add-on's normal price: its stored total with its comp put back.
int addonNormalTotal(OrderItemAddon a) =>
    a.lineTotal + ((a.staffCompMinor ?? 0) < 0 ? 0 : (a.staffCompMinor ?? 0));

class StaffDrinkOrderSheet extends ConsumerWidget {
  const StaffDrinkOrderSheet({required this.orderId, super.key});

  /// `sm:max-w-md`.
  static const double width = 448;

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final q = ref.watch(staffDrinkOrderProvider(orderId));
    final order = q.value;
    if (order == null || q.hasError) {
      return DashSurface(
        title: t('orders.order'),
        description: q.hasError ? null : t('common.loading'),
        body: q.hasError
            ? DashErrorState(
                message: errorMessage(q.error, t),
                retryLabel: t('common.retry'),
                onRetry: () => ref.invalidate(staffDrinkOrderProvider(orderId)),
                framed: false,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.md,
                children: [
                  for (var i = 0; i < 4; i++)
                    const DashSkeleton(
                      height: Space.xxl * 2.5,
                      radius: Radii.control,
                    ),
                ],
              ),
      );
    }
    final ref0 =
        order.orderRef ?? '#${order.displayNumber ?? order.orderNumber}';
    return DashSurface(
      title: ref0,
      description: f.fmtDateTimeFull(order.createdAt.toIso8601String()),
      headerTrailing: Padding(
        padding: const EdgeInsets.only(top: Space.xs),
        child: DashStatusPill(
          label: t('orderStatus.${order.status}', defaultValue: order.status),
          tone: DashStatusPill.toneFor(
            order.status,
            fallback: DashTone.success,
          ),
        ),
      ),
      body: _OrderBody(order: order),
    );
  }
}

class _OrderBody extends ConsumerWidget {
  const _OrderBody({required this.order});

  final OrderFull order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final items = order.items;
    final staffComp = items.fold<int>(
      0,
      (s, it) =>
          s + ((it.staffCompMinor ?? 0) < 0 ? 0 : (it.staffCompMinor ?? 0)),
    );
    final knownCogs = items.fold<int>(0, (s, it) => s + (it.lineCost ?? 0));
    final anyMissing = items.any((it) => it.costMissing || it.lineCost == null);
    final profit = order.totalAmount - knownCogs;
    final profitPct = order.totalAmount > 0 ? profit / order.totalAmount : null;
    final voided = order.status == 'voided';
    final legs = order.paymentLegs;

    Widget card(List<Widget> children) => DashCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: children,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        if (voided && order.voidReason != null)
          card([
            Text(
              t('orderStatus.voided'),
              style: DashType.bodyStrong.copyWith(color: c.textPrimary),
            ),
            Text(
              t(
                'orders.voidReasons.${order.voidReason}',
                defaultValue: order.voidReason,
              ),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ]),
        card([
          _Row(
            t('common.date'),
            f.fmtDateTimeFull(order.createdAt.toIso8601String()),
          ),
          _Row(t('tills.teller'), order.tellerName),
          if (order.startedByName != null && order.startedBy != order.tellerId)
            _Row(t('orders.startedBy'), order.startedByName!),
          if (order.waiterName != null)
            _Row(t('tills.waiter'), order.waiterName!),
          if (order.customerName != null)
            _Row(t('orders.customer'), order.customerName!),
          _RowWidget(
            t('orders.payment'),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: legs.length > 1
                  ? [
                      for (final leg in legs)
                        DashBadge(
                          '${paymentMethodLabel(t, leg.method)} '
                          '${f.fmtMoney(leg.amount)}',
                        ),
                    ]
                  : [DashBadge(paymentMethodLabel(t, order.paymentMethod))],
            ),
          ),
        ]),
        if (items.isNotEmpty)
          card([
            Text(
              t('menu.items'),
              style: DashType.bodyStrong.copyWith(color: c.textPrimary),
            ),
            for (final (i, it) in items.indexed)
              _Line(item: it, last: i == items.length - 1),
          ]),
        card([
          if (staffComp > 0) ...[
            // The subtotal is stored net of the comp: put it back for one line
            // and take it off under it, so the sheet adds up.
            _Row(
              t('orders.beforeStaffDrinks'),
              f.fmtMoney(order.subtotal + staffComp),
              mono: true,
            ),
            _Row(
              t('orders.staffDrinksGiven'),
              f.fmtMoney(-staffComp),
              mono: true,
            ),
          ],
          _Row(t('common.subtotal'), f.fmtMoney(order.subtotal), mono: true),
          if (order.discountAmount > 0)
            _Row(
              t('orders.discount'),
              f.fmtMoney(-order.discountAmount),
              mono: true,
            ),
          if (order.taxAmount > 0)
            _Row(t('orders.tax'), f.fmtMoney(order.taxAmount), mono: true),
          if ((order.tipAmount ?? 0) != 0)
            _Row(t('orders.tip'), f.fmtMoney(order.tipAmount), mono: true),
          if (order.deliveryFee > 0)
            _Row(
              t('orders.deliveryFee'),
              f.fmtMoney(order.deliveryFee),
              mono: true,
            ),
          Container(
            padding: const EdgeInsets.only(top: Space.xs),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.hairline)),
            ),
            child: _Row(
              t('common.total'),
              f.fmtMoney(order.totalAmount),
              mono: true,
              strong: true,
              struck: voided,
            ),
          ),
          if (items.isNotEmpty)
            Container(
              padding: const EdgeInsets.only(top: Space.sm),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  Text(
                    '${t('orders.cogs')}: '
                    '${dashFigure('${anyMissing ? '≥ ' : ''}${f.fmtMoney(knownCogs)}')}',
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                  Text(
                    '${t('orders.grossProfit')}: '
                    '${dashFigure('${anyMissing ? '≤ ' : ''}${f.fmtMoney(profit)}'
                    '${profitPct != null ? ' (${f.fmtPercent(profitPct)})' : ''}')}',
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
        ]),
      ],
    );
  }
}

/// One line: its name (and size), the staff-drink pill, quantity × unit
/// price, add-ons, the line total and cost, and the comp as a line discount.
class _Line extends ConsumerWidget {
  const _Line({required this.item, required this.last});

  final OrderItemFull item;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final it = item;
    final staff = staffDrinkLine(it);
    final size = it.sizeLabel;
    final muted = DashType.small.copyWith(color: c.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: c.hairline)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xs,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.sm,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DashMetrics.hair,
                  children: [
                    Wrap(
                      spacing: Space.xs,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          translatedName(
                            it.itemName,
                            it.nameTranslations,
                            t.lang,
                          ),
                          style: DashType.bodyStrong.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                        if (size != null && size != _oneSize)
                          Text(
                            '($size)',
                            style: DashType.body.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        if (staff != null)
                          DashStatusPill(
                            label: t('orders.staffDrink'),
                            tone: DashTone.info,
                            icon: 'cup-soda',
                            small: true,
                          ),
                      ],
                    ),
                    Text(
                      dashFigure(
                        '× ${f.fmtNumber(it.quantity)} · ${f.fmtMoney(it.unitPrice)}',
                      ),
                      style: muted,
                    ),
                    for (final a in it.addons)
                      Text.rich(
                        TextSpan(
                          text:
                              '+ ${translatedName(a.addonName, a.nameTranslations, t.lang)}'
                              '${a.quantity > 1 ? ' ×${a.quantity}' : ''}',
                          children: [
                            if ((a.staffCompMinor ?? 0) > 0)
                              TextSpan(
                                text:
                                    ' (${dashFigure(f.fmtMoney(addonNormalTotal(a)))}) '
                                    '${t('orders.staffCompAddon', args: {'amount': f.fmtMoney(-(a.staffCompMinor ?? 0))})}',
                                style: TextStyle(color: c.textSecondary),
                              )
                            else if (a.lineTotal > 0)
                              TextSpan(
                                text:
                                    ' (${dashFigure(f.fmtMoney(a.lineTotal))})',
                                style: TextStyle(color: c.textSecondary),
                              ),
                          ],
                        ),
                        style: DashType.small.copyWith(color: c.textPrimary),
                      ),
                    if (it.notes != null && it.notes!.isNotEmpty)
                      Text(
                        it.notes!,
                        style: muted.copyWith(fontStyle: FontStyle.italic),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    dashFigure(f.fmtMoney(it.lineTotal)),
                    style: DashType.monoStrong.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    '${t('orders.cost')}: ${dashFigure(f.fmtMoney(it.lineCost))}'
                    '${it.costMissing ? ' · ${t('orders.costMissing')}' : ''}',
                    style: muted,
                  ),
                ],
              ),
            ],
          ),
          if (staff != null && staff.comp > 0)
            // The comp as a line discount, the way the receipt prints it.
            Container(
              key: const Key('staff-line'),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DashMetrics.hair,
                children: [
                  _Row(
                    t('orders.staffLineNormal'),
                    f.fmtMoney(staff.normal),
                    mono: true,
                    small: true,
                  ),
                  _Row(
                    t('orders.staffLineComp'),
                    f.fmtMoney(-staff.comp),
                    mono: true,
                    small: true,
                  ),
                  _Row(
                    t('orders.staffLineCharged'),
                    f.fmtMoney(staff.charged),
                    mono: true,
                    small: true,
                    strong: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A label at the start, its value at the end.
class _Row extends StatelessWidget {
  const _Row(
    this.label,
    this.value, {
    this.mono = false,
    this.strong = false,
    this.small = false,
    this.struck = false,
  });

  final String label;
  final String value;
  final bool mono;
  final bool strong;
  final bool small;
  final bool struck;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final base = small ? DashType.small : DashType.body;
    final valueStyle = (mono ? DashType.mono : base).copyWith(
      color: struck ? c.textSecondary : c.textPrimary,
      fontWeight: strong ? FontWeight.w600 : null,
      decoration: struck ? TextDecoration.lineThrough : null,
    );
    return _RowWidget(
      label,
      Text(
        mono ? dashFigure(value) : value,
        textAlign: TextAlign.end,
        style: valueStyle,
      ),
      strong: strong,
      small: small,
    );
  }
}

class _RowWidget extends StatelessWidget {
  const _RowWidget(
    this.label,
    this.value, {
    this.strong = false,
    this.small = false,
  });

  final String label;
  final Widget value;
  final bool strong;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final base = small ? DashType.small : DashType.body;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.md,
      children: [
        Text(
          label,
          style: base.copyWith(
            color: strong ? c.textPrimary : c.textSecondary,
            fontWeight: strong ? FontWeight.w600 : null,
          ),
        ),
        Expanded(
          child: Align(alignment: AlignmentDirectional.centerEnd, child: value),
        ),
      ],
    );
  }
}
