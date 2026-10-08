/// A table's history in a side panel (REP-OPS-023…033):
/// `tables-page.tsx:204-225` and `features/floor/table-history.tsx`.
///
/// The panel turns the ledger's label into a table id through the floor's
/// tables (one branch only), then shows the table's figures and its bills
/// for the scope's period. A sitting's customer opens a read-only customer
/// panel ([OpsCustomerSheet]) for whoever holds `customers.view`; one of the
/// customer's orders opens a read-only order panel.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show CustomerDetail, CustomerOrder, OrderFull, TableHistory, TableSitting;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart';
import 'ops_data.dart';
import 'ops_support.dart';
import 'ops_tables.dart';

/// The panel for one ledger row.
class OpsTableSheet extends ConsumerWidget {
  const OpsTableSheet({required this.row, super.key});

  final OpsTableRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    final note = DashType.body.copyWith(color: c.textSecondary);
    Widget body;
    final branchId = scope.branchId;
    if (branchId == null) {
      body = Text(t('tablesInsights.pickBranch'), style: note);
    } else {
      final floor = ref.watch(opsFloorTablesProvider(branchId));
      if (floor.firstLoad) {
        body = const DashSkeleton(height: Space.xxl * 4);
      } else {
        // A failed lookup reads the same as a table that is gone: the web
        // has no error state here (REP-OPS-026).
        final id = floor.value
            ?.where((ft) => ft.label == row.table)
            .firstOrNull
            ?.id;
        body = id == null
            ? Text(t('tablesInsights.tableGone'), style: note)
            : OpsTableHistory(tableId: id, from: scope.from, to: scope.to);
      }
    }
    return DashSurface(
      title: t('tablesInsights.historyTitle', args: {'label': row.table}),
      description: row.section,
      body: body,
    );
  }
}

/// A table's figures, then what happened.
class OpsTableHistory extends ConsumerWidget {
  const OpsTableHistory({
    required this.tableId,
    required this.from,
    required this.to,
    super.key,
  });

  final String tableId;
  final String from;
  final String to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final q = ref.watch(opsTableHistoryProvider((tableId, from, to)));
    final small = DashType.small.copyWith(color: c.textSecondary);
    if (q.firstLoad) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          DashSkeleton(height: Space.xxl * 2),
          DashSkeleton(height: Space.xxl * 2),
        ],
      );
    }
    final data = q.value;
    if (q.hasError || data == null) {
      return Text(t('floor.history.failed'), style: small);
    }
    if (data.sittings.isEmpty) {
      // This page always passes a period (REP-OPS-029).
      return Text(t('floor.history.emptyPeriod'), style: small);
    }
    final turns = fmtNum(f, data.turnsPerDayX100 / 100, minDp: 1, maxDp: 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            OpsEqualRow(
              gap: Space.sm,
              children: [
                _Figure(
                  t('floor.history.takings'),
                  f.fmtMoney(data.totalMinor),
                ),
                _Figure(
                  t('floor.history.avgBill'),
                  f.fmtMoney(data.averageBillMinor),
                ),
              ],
            ),
            OpsEqualRow(
              gap: Space.sm,
              children: [
                _Figure(
                  t('floor.history.avgStay'),
                  fmtStay(f, data.averageMinutes),
                ),
                _Figure(t('floor.history.turns'), turns),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Text(
                t('floor.history.bills'),
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
            ),
            for (final (i, s) in data.sittings.indexed)
              _SittingRow(sitting: s, last: i == data.sittings.length - 1),
          ],
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          Text(label, style: DashType.small.copyWith(color: c.textSecondary)),
          MadarClippedText(
            dashFigure(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashType.monoStrong.copyWith(
              fontSize: 18,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SittingRow extends ConsumerWidget {
  const _SittingRow({required this.sitting, required this.last});

  final TableSitting sitting;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final s = sitting;
    final name = s.customerName?.trim();
    final who = (name != null && name.isNotEmpty)
        ? name
        : (s.ticketRef ?? '—');
    final covers = s.guestCount ?? 0;
    final canOpen = ref.watch(
      authzProvider.select((a) => a.can(Cap.customersView)),
    );
    final customerId = s.customerId;
    final Widget whoWidget = name != null &&
            name.isNotEmpty &&
            customerId != null &&
            canOpen
        ? Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashButton(
              key: ValueKey('ops-customer-$customerId-${s.openTicketId}'),
              label: name,
              variant: DashButtonVariant.link,
              size: DashButtonSize.compact,
              onPressed: () => showDashSidePanel<void>(
                context,
                width: DashMetrics.dialogWide,
                builder: (_) => OpsCustomerSheet(customerId: customerId),
              ),
            ),
          )
        : MadarClippedText(
            who,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashType.body.copyWith(color: c.textPrimary),
          );
    final sub = [
      fmtStay(f, s.minutes),
      if (covers > 0) t('floor.history.covers', count: covers),
    ].join(' · ');
    final Widget end = s.totalAmount == null
        ? DashStatusPill(
            small: true,
            tone: s.status == 'open' ? DashTone.accent : DashTone.danger,
            label: s.status == 'open'
                ? t('floor.history.stillOpen')
                : t('floor.history.voided'),
          )
        : Text(
            dashFigure(f.fmtMoney(s.totalAmount)),
            style: DashType.mono.copyWith(color: c.textPrimary),
          );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: Space.md,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                whoWidget,
                Text(sub, style: DashType.small.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
          end,
        ],
      ),
    );
  }
}

// ── the read-only customer and order panels (REP-OPS-032) ────────────────

final _customerProvider = FutureProvider.autoDispose
    .family<CustomerDetail, String>(
      (ref, id) => ref.watch(apiProvider).customers.getCustomer(id: id),
    );

final _orderProvider = FutureProvider.autoDispose.family<OrderFull, String>(
  (ref, id) => ref.watch(apiProvider).orders.getOrder(orderId: id),
);

/// The customer a sitting belongs to, read-only (the web's
/// `CustomerDetailSheet readOnly`): who they are, what they have spent and
/// their recent orders; an order opens [OpsOrderSheet].
class OpsCustomerSheet extends ConsumerWidget {
  const OpsCustomerSheet({required this.customerId, super.key});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final q = ref.watch(_customerProvider(customerId));
    final d = q.value;
    final customer = d?.customer;
    Widget body;
    if (q.firstLoad) {
      body = const DashSkeleton(height: Space.xxl * 8);
    } else if (q.hasError || d == null || customer == null) {
      body = DashEmptyState(
        title: t('customers.loadFailed'),
        description: q.hasError ? opsErrorText(q.error, t) : null,
        action: DashButton(
          label: t('common.retry'),
          variant: DashButtonVariant.outline,
          onPressed: () => ref.invalidate(_customerProvider(customerId)),
        ),
      );
    } else {
      Widget stat(String label, String value) => Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: DashType.small.copyWith(color: c.textSecondary)),
            Text(
              dashFigure(value),
              style: DashType.monoStrong.copyWith(
                fontSize: 18,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      );
      final unknown = t('customers.notGiven');
      Widget line(String label, String value, {bool mono = false}) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.lg,
          children: [
            Text(label, style: DashType.body.copyWith(color: c.textSecondary)),
            Expanded(
              child: Text(
                mono ? dashFigure(value) : value,
                textAlign: TextAlign.end,
                style: (mono ? DashType.mono : DashType.body).copyWith(
                  color: c.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
      final source = customer.source;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          if (d.resolvedFrom != null)
            Text(t('customers.resolvedFrom'), style: DashType.body),
          LayoutBuilder(
            builder: (context, box) {
              final cols = box.maxWidth >= DashBreakpoints.sm ? 4 : 2;
              final w = (box.maxWidth - Space.sm * (cols - 1)) / cols;
              return Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final s in [
                    stat(t('customers.orders'), fmtNum(f, customer.ordersCount)),
                    stat(t('customers.totalSpent'), f.fmtMoney(customer.totalSpent)),
                    stat(
                      t('customers.lastVisit'),
                      customer.lastOrderAt == null
                          ? '—'
                          : f.fmtDate(customer.lastOrderAt!.toIso8601String()),
                    ),
                    stat(
                      t('customers.since'),
                      f.fmtDate(customer.createdAt.toIso8601String()),
                    ),
                  ])
                    SizedBox(width: w, child: s),
                ],
              );
            },
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              Text(
                t('customers.details'),
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.control),
                  border: Border.all(color: c.hairline),
                ),
                child: Column(
                  children: [
                    line(
                      t('customers.phone'),
                      customer.phone ?? unknown,
                      mono: customer.phone != null,
                    ),
                    line(
                      t('customers.language'),
                      customer.locale == 'ar'
                          ? t('customers.languageAr')
                          : customer.locale == 'en'
                          ? t('customers.languageEn')
                          : unknown,
                    ),
                    line(
                      t('customers.source.label'),
                      source != null && t.exists('customers.source.$source')
                          ? t('customers.source.$source')
                          : unknown,
                    ),
                    line(
                      t('customers.marketing'),
                      customer.marketingOptOut ?? false
                          ? t('customers.marketingOff')
                          : t('customers.marketingOn'),
                    ),
                  ],
                ),
              ),
              Text(
                t('customers.marketingNote'),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
              if (customer.notes != null && customer.notes!.isNotEmpty)
                Text(customer.notes!, style: DashType.body),
              if (d.mergedFrom.isNotEmpty)
                Text(
                  t('customers.mergedFrom', args: {'n': d.mergedFrom.length}),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
            ],
          ),
          _RecentOrders(orders: d.recentOrders),
        ],
      );
    }
    return DashSurface(
      title: customer?.name ?? t('customers.customer'),
      description: customer?.phone,
      headerTrailing: customer?.isMember == true
          ? DashStatusPill(
              small: true,
              tone: DashTone.accent,
              icon: 'star',
              label: t('customers.member'),
            )
          : null,
      body: body,
    );
  }
}

class _RecentOrders extends ConsumerWidget {
  const _RecentOrders({required this.orders});

  final List<CustomerOrder> orders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    if (orders.isEmpty) {
      return DashEmptyState(icon: 'receipt', title: t('customers.noOrders'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        Text(
          t('customers.recentOrders'),
          style: DashType.bodyStrong.copyWith(color: c.textPrimary),
        ),
        DashDataTable<CustomerOrder>(
          rows: orders,
          rowKey: (o) => o.id,
          hideViewOptions: true,
          columns: [
            DashColumn<CustomerOrder>(
              id: 'order',
              label: t('customers.order'),
              phone: DashPhoneRole.title,
              text: (o) => o.orderRef ?? o.id.substring(0, 8),
              cell: (context, o) => DashButton(
                label: o.orderRef ?? o.id.substring(0, 8),
                variant: DashButtonVariant.link,
                size: DashButtonSize.compact,
                onPressed: () => showDashSidePanel<void>(
                  context,
                  width: DashMetrics.dialogWide,
                  builder: (_) => OpsOrderSheet(orderId: o.id),
                ),
              ),
            ),
            DashColumn<CustomerOrder>(
              id: 'branch',
              label: t('customers.branch'),
              text: (o) => o.branchName ?? '—',
            ),
            DashColumn<CustomerOrder>(
              id: 'status',
              label: t('common.status'),
              text: (o) => t('orderStatus.${o.status}', defaultValue: o.status),
            ),
            DashColumn<CustomerOrder>(
              id: 'total',
              label: t('common.total'),
              numeric: true,
              text: (o) => f.fmtMoney(o.totalAmount),
            ),
            DashColumn<CustomerOrder>(
              id: 'date',
              label: t('common.date'),
              numeric: true,
              text: (o) => f.fmtDateTime(o.createdAt.toIso8601String()),
            ),
          ],
        ),
      ],
    );
  }
}

/// One order, read-only: its lines and what it came to.
class OpsOrderSheet extends ConsumerWidget {
  const OpsOrderSheet({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final q = ref.watch(_orderProvider(orderId));
    final o = q.value;
    Widget body;
    if (q.firstLoad) {
      body = const DashSkeleton(height: Space.xxl * 6);
    } else if (q.hasError || o == null) {
      body = DashErrorState(
        message: opsErrorText(q.error, t),
        onRetry: () => ref.invalidate(_orderProvider(orderId)),
      );
    } else {
      Widget money(String label, num v, {bool strong = false}) =>
          DashSummaryLine(
            label: label,
            value: f.fmtMoney(v),
            emphasis: strong,
          );
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              DashStatusPill(
                small: true,
                tone: DashStatusPill.toneFor(o.status),
                label: t('orderStatus.${o.status}', defaultValue: o.status),
              ),
              DashBadge(channelLabel(t, o.orderType)),
            ],
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.control),
              border: Border.all(color: c.hairline),
            ),
            child: Column(
              children: [
                for (final (i, l) in o.items.indexed)
                  Container(
                    padding: const EdgeInsets.all(Space.md),
                    decoration: BoxDecoration(
                      border: i == o.items.length - 1
                          ? null
                          : Border(bottom: BorderSide(color: c.hairline)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Space.md,
                      children: [
                        Text(
                          dashFigure('${l.quantity}×'),
                          style: DashType.mono.copyWith(color: c.textSecondary),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [
                                  translatedName(
                                    l.itemName,
                                    l.nameTranslations,
                                    lang,
                                  ),
                                  ?l.sizeLabel,
                                ].join(' · '),
                                style: DashType.bodyMedium.copyWith(
                                  color: c.textPrimary,
                                ),
                              ),
                              for (final a in l.addons)
                                Text(
                                  '+ ${translatedName(a.addonName, a.nameTranslations, lang)}',
                                  style: DashType.small.copyWith(
                                    color: c.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          dashFigure(f.fmtMoney(l.lineTotal)),
                          style: DashType.mono.copyWith(color: c.textPrimary),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Column(
            spacing: Space.xs,
            children: [
              money(t('orders.subtotal'), o.subtotal),
              if (o.discountAmount > 0)
                money(t('orders.discount'), -o.discountAmount),
              money(t('orders.tax'), o.taxAmount),
              money(t('orders.total'), o.totalAmount, strong: true),
            ],
          ),
          DashSummaryLine(
            label: t('orders.payment'),
            value: [
              for (final l in o.paymentLegs) paymentMethodLabel(t, l.method),
            ].join(' + '),
          ),
          DashSummaryLine(label: t('tills.teller'), value: o.tellerName),
        ],
      );
    }
    return DashSurface(
      title: o == null
          ? t('orders.order')
          : (o.orderRef ?? '#${o.displayNumber ?? o.orderNumber}'),
      description: o == null
          ? t('common.loading')
          : f.fmtDateTimeFull(o.createdAt.toIso8601String()),
      body: body,
    );
  }
}
