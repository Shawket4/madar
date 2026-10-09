/// `/orders` (the web's `features/orders/orders-page.tsx`, SELL-ORD rows):
/// the list, filters, KPI strip, delivery block, the order sheet, the void
/// dialog and the export sheet.
///
/// No in-page guard (SELL-ALL-004): someone without `orders.read` who types
/// the URL sees the table's error state from the refused read.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Order, OrderFull, PaginatedOrders;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/customer_link.dart';
import '../shared/sheets.dart';
import 'export_data.dart';
import 'export_sheet.dart';
import 'order_lines.dart';
import 'order_sheet.dart';
import 'orders_parts.dart';
import 'orders_providers.dart';
import 'void_dialog.dart';

/// `PAYMENT_METHODS` (`data/config/constants.ts`).
const List<String> orderPaymentMethods = [
  'cash',
  'card',
  'digital_wallet',
  'mixed',
  'talabat_online',
  'talabat_cash',
];

/// `ORDER_STATUSES`.
const List<String> orderStatuses = ['completed', 'voided'];

/// The teller / waiter search delay (`useDebounced(…, 350)`).
const Duration ordersSearchDelay = Duration(milliseconds: 350);

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({this.orderId, this.tillId, super.key});

  /// The route's builder (routes.dart points here; the search params are
  /// this unit's to read).
  static Widget route(BuildContext context, GoRouterState state) {
    final q = state.uri.queryParameters;
    String? nonEmpty(String? v) => v == null || v.isEmpty ? null : v;
    return OrdersPage(
      orderId: nonEmpty(q['order']),
      tillId:
          nonEmpty(q['till']) ??
          nonEmpty(q['till_id']) ??
          nonEmpty(q['shift_id']),
    );
  }

  /// The web's `prefetchRoute('/orders')`: the list's first page, unfiltered,
  /// once a branch or an org is in scope.
  static void prefetch(DashPrefetcher warm, Scope s) {
    if (s.ordersEnabled) warm(ordersListProvider(s.ordersFirstPage));
  }

  /// `?order=`: that order's sheet opens on load (SELL-ORD-011).
  final String? orderId;

  /// `?till=` (`?till_id=`, legacy `?shift_id=`): one till (SELL-ORD-010).
  final String? tillId;

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  String _teller = '';
  String _waiter = '';
  String? _status;
  String? _payment;
  String? _type;
  String? _channel;

  /// The page asked for, and the filters it was asked under: any change to
  /// those filters is page 1 again (SELL-ORD-003).
  int _page = 0;
  String? _pageSig;

  /// The rows on screen while the next key loads (`keepPreviousData`).
  PaginatedOrders? _shown;

  final VoidDraft _voidDraft = VoidDraft();

  /// The order whose sheet is up.
  String? _sheet;

  @override
  void initState() {
    super.initState();
    _syncSheet(widget.orderId);
  }

  @override
  void didUpdateWidget(OrdersPage old) {
    super.didUpdateWidget(old);
    if (old.orderId != widget.orderId) _syncSheet(widget.orderId);
  }

  Uri get _location =>
      GoRouter.of(context).routerDelegate.currentConfiguration.uri;

  /// `?order=` in place (shareable; closing removes it).
  void _setOrder(String? id) {
    final uri = _location;
    final q = Map<String, String>.of(uri.queryParameters);
    if (id == null) {
      q.remove('order');
    } else {
      q['order'] = id;
    }
    GoRouter.of(
      context,
    ).go(Uri(path: uri.path, queryParameters: q.isEmpty ? null : q).toString());
  }

  /// Opens the sheet `?order=` names; another id closes the one up first.
  void _syncSheet(String? id) {
    if (id == _sheet) return;
    final previous = _sheet;
    _sheet = id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (previous != null) {
        await Navigator.of(context, rootNavigator: true).maybePop();
      }
      if (id == null || !mounted || _sheet != id) return;
      await showOrderSheet(
        context,
        orderId: id,
        onVoid: (o) => _openVoid(o.id, _plainRefFull(o)),
        onSwitchOrder: _setOrder,
      );
      if (!mounted || _sheet != id) return;
      _sheet = null;
      if (_location.queryParameters['order'] == id) _setOrder(null);
    });
  }

  static String _plainRefFull(OrderFull o) =>
      orderPlainRef(orderRef: o.orderRef, orderNumber: o.orderNumber);

  /// What the order sheet reads on open, warmed on a row's intent.
  void _warmSheet(Order o) {
    ref.warm(orderDetailProvider(o.id));
    final orgId = ref.read(orgIdProvider);
    if (orgId != null) ref.warm(orderCatalogProvider(orgId));
    final delivery = o.deliveryOrderId;
    if (o.orderType == 'delivery' && delivery != null) {
      ref.warm(orderDeliveryProvider(delivery));
    }
  }

  void _openVoid(String id, String ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showVoidDialog(context, orderId: id, ref: ref, draft: _voidDraft);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    final excluded = ref.watch(excludedItemsProvider(scope.orgId));
    final enabled = scope.ordersEnabled;
    final phone = DashBreakpoints.isPhone(context);

    final sig = [
      scope.branchId,
      scope.from,
      scope.to,
      _status,
      _payment,
      _teller,
      _waiter,
      _type,
      _channel,
    ].join('|');
    // Another filter set is page 1 again; changing it back does not bring
    // the old page back (the web resets on every change).
    if (sig != _pageSig) {
      _pageSig = sig;
      _page = 0;
    }
    final page = _page;
    OrdersKey keyAt(int p) => (
      branchId: scope.branchId,
      from: scope.from,
      to: scope.to,
      status: _status,
      payment: _payment,
      teller: _teller.isEmpty ? null : _teller,
      waiter: _waiter.isEmpty ? null : _waiter,
      type: _type,
      // Channel only narrows delivery orders.
      channel: _type == 'delivery' ? _channel : null,
      exclude: excludeItemsParam(excluded),
      till: widget.tillId,
      page: p,
    );
    final key = keyAt(page + 1);
    final q = watchIfOrders(ref, enabled, () => ordersListProvider(key));
    if (q.value != null) _shown = q.value;
    final data = q.value ?? (q.isLoading ? _shown : null);
    final loading = data == null && q.awaitingFirst;
    // The web's table shows the error once React Query's retries are spent.
    final failed = q.hasError && !q.retrying;
    final summary = data?.summary;

    final delivery = watchIfOrders(
      ref,
      enabled,
      () => ordersDeliveryProvider(scope.deliveryRange),
    );

    final control = customerSheetControl(context, ref, onOpenOrder: _setOrder);

    final kpis = DashLedgerStrip(
      items: [
        DashLedgerItem(
          key: 'revenue',
          label: t('dashboard.revenue'),
          value: summary?.revenue ?? 0,
          format: DashStatFormat.money,
          icon: 'coins',
          loading: loading,
        ),
        DashLedgerItem(
          key: 'completed',
          label: t('orders.completed'),
          value: summary?.completed ?? 0,
          format: DashStatFormat.number,
          icon: 'receipt',
          loading: loading,
        ),
        DashLedgerItem(
          key: 'line_items',
          label: t('orders.itemsSold'),
          value: summary?.lineItems ?? 0,
          format: DashStatFormat.number,
          icon: 'shopping-basket',
          loading: loading,
          hint: excluded.isEmpty
              ? null
              : t('analytics.nExcluded', count: excluded.length),
          action: OrdersExcludeItemsControl(orgId: scope.orgId),
        ),
        DashLedgerItem(
          key: 'voided',
          label: t('dashboard.voided'),
          value: summary?.voided ?? 0,
          format: DashStatFormat.number,
          icon: 'ban',
          tone: (summary?.voided ?? 0) > 0 ? DashTone.danger : DashTone.neutral,
          loading: loading,
        ),
        DashLedgerItem(
          key: 'discounts',
          label: t('orders.discounts'),
          value: summary?.discounts ?? 0,
          format: DashStatFormat.money,
          icon: 'percent',
          loading: loading,
        ),
      ],
    );

    final deliveryData = delivery.value;
    final deliveryBlock = (deliveryData?.totalOrders ?? 0) > 0
        ? Column(
            key: const ValueKey('orders-delivery'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              DashSectionHeader(
                title: t('delivery.kpisTitle'),
                description: t('delivery.byChannel'),
              ),
              DeliveryChannels(
                data: deliveryData,
                loading: delivery.awaitingFirst,
              ),
            ],
          )
        : null;

    final table = DashDataTable<Order>(
      key: const ValueKey('orders-table'),
      columns: _columns(t, fmt, c, control),
      rows: data?.data ?? const [],
      rowKey: (o) => o.id,
      loading: loading,
      errorMessage: failed ? errorMessage(q.error, t) : null,
      onRetry: () => ref.invalidate(ordersListProvider(key)),
      retrying: q.isLoading,
      empty: DashEmptyState(
        icon: 'receipt',
        title: t('orders.emptyTitle'),
        description: t('orders.emptyBody'),
      ),
      onRowTap: (o) => _setOrder(o.id),
      onRowIntent: _warmSheet,
      selectedRowKey: widget.orderId,
      rowActions: (context, o) => _RowActions(
        order: o,
        onDetails: () => _setOrder(o.id),
        onDetailsIntent: () => _warmSheet(o),
        onVoid: () => _openVoid(
          o.id,
          orderPlainRef(orderRef: o.orderRef, orderNumber: o.orderNumber),
        ),
      ),
      pageSize: ordersPerPage,
      pageIndex: page,
      pageCount: failed ? 0 : (data?.totalPages ?? 0),
      onPageChanged: (n) => setState(() {
        _page = n;
      }),
      onPageIntent: (n) => ref.warm(ordersListProvider(keyAt(n + 1))),
      rowSemanticLabel: (o) => orderDisplayRef(
        orderRef: o.orderRef,
        displayNumber: o.displayNumber,
        orderNumber: o.orderNumber,
      ),
    );

    DashOption<String> opt(String v, String label) =>
        DashOption(value: v, label: label);
    // An option about to be picked warms the first page it will show.
    void warmPick(void Function() pick) {
      if (!enabled) return;
      final (status, payment, type, channel) = (
        _status,
        _payment,
        _type,
        _channel,
      );
      pick();
      final k = keyAt(1);
      _status = status;
      _payment = payment;
      _type = type;
      _channel = channel;
      ref.warm(ordersListProvider(k));
    }

    final filters = Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _sized(
          phone,
          DashSearchInput(
            key: const ValueKey('orders-teller'),
            value: _teller,
            placeholder: t('orders.searchTeller'),
            debounce: ordersSearchDelay,
            onChanged: (v) => setState(() => _teller = v),
          ),
        ),
        _sized(
          phone,
          DashSearchInput(
            key: const ValueKey('orders-waiter'),
            value: _waiter,
            placeholder: t('orders.searchWaiter'),
            debounce: ordersSearchDelay,
            onChanged: (v) => setState(() => _waiter = v),
          ),
        ),
        DashFilterSelect<String>(
          key: const ValueKey('orders-status'),
          label: t('common.status'),
          allLabel: t('orders.allStatuses'),
          value: _status,
          minWidth: Space.xxl * 3.5,
          options: [for (final s in orderStatuses) opt(s, t('orderStatus.$s'))],
          onChanged: (v) => setState(() => _status = v),
          onOptionIntent: (v) => warmPick(() => _status = v),
        ),
        DashFilterSelect<String>(
          key: const ValueKey('orders-payment'),
          label: t('orders.payment'),
          allLabel: t('orders.allPayments'),
          value: _payment,
          minWidth: Space.xxl * 4,
          options: [
            for (final m in orderPaymentMethods) opt(m, t('payments.$m')),
          ],
          onChanged: (v) => setState(() => _payment = v),
          onOptionIntent: (v) => warmPick(() => _payment = v),
        ),
        DashFilterSelect<String>(
          key: const ValueKey('orders-type'),
          label: t('orders.type'),
          allLabel: t('orders.allTypes'),
          value: _type,
          minWidth: Space.xxl * 3.5,
          options: [
            opt('dine_in', t('orders.dineIn')),
            opt('delivery', t('orders.delivery')),
          ],
          onChanged: (v) => setState(() {
            _type = v;
            if (v != 'delivery') _channel = null;
          }),
          onOptionIntent: (v) => warmPick(() {
            _type = v;
            if (v != 'delivery') _channel = null;
          }),
        ),
        if (_type == 'delivery')
          DashFilterSelect<String>(
            key: const ValueKey('orders-channel'),
            label: t('orders.channel'),
            allLabel: t('orders.allChannels'),
            value: _channel,
            minWidth: Space.xxl * 3.5,
            options: [
              opt('in_mall', t('delivery.channelInMall')),
              opt('outside', t('orders.deliveryOutside')),
            ],
            onChanged: (v) => setState(() => _channel = v),
            onOptionIntent: (v) => warmPick(() => _channel = v),
          ),
      ],
    );

    return DashPageScaffold(
      title: t('nav.orders'),
      subtitle: t('orders.subtitle'),
      actions: [
        // The export sheet's branch read (its name in the file).
        DashIntent(
          onIntent: scope.branchId == null || !enabled
              ? null
              : () => ref.warm(ordersExportBranchProvider(scope.branchId!)),
          child: DashExportButton(
            key: const ValueKey('orders-export'),
            enabled: enabled,
            onExport: () => showOrdersExport(
              context,
              listKey: key,
              filters: OrdersExportFilters(
                branchId: scope.branchId,
                from: scope.from,
                to: scope.to,
                status: _status,
                payment: _payment,
                teller: key.teller,
                waiter: key.waiter,
                till: widget.tillId,
              ),
            ),
          ),
        ),
      ],
      filters: filters,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [kpis, ?deliveryBlock, table],
      ),
    );
  }

  /// Full width on a phone, 192 from `sm` (`w-full sm:w-48`).
  Widget _sized(bool phone, Widget child) =>
      SizedBox(width: phone ? double.infinity : Space.xxl * 6, child: child);

  List<DashColumn<Order>> _columns(
    Translator t,
    DashFormat fmt,
    MadarColors c,
    CustomerLinkControl control,
  ) {
    String payments(Order o) => o.paymentLegs.length <= 1
        ? orTranslated(t, 'payments.${o.paymentMethod}', o.paymentMethod)
        : o.paymentLegs
              .map(
                (l) =>
                    '${orTranslated(t, 'payments.${l.method}', l.method)} ${fmt.fmtMoney(l.amount)}',
              )
              .join(' ');
    return [
      DashColumn<Order>(
        id: 'ref',
        label: '#',
        numeric: true,
        align: DashAlign.start,
        phone: DashPhoneRole.title,
        text: (o) => orderDisplayRef(
          orderRef: o.orderRef,
          displayNumber: o.displayNumber,
          orderNumber: o.orderNumber,
        ),
        cell: (context, o) => Wrap(
          spacing: Space.sm,
          runSpacing: DashMetrics.hair,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            MadarClippedText(
              orderDisplayRef(
                orderRef: o.orderRef,
                displayNumber: o.displayNumber,
                orderNumber: o.orderNumber,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.monoMedium.copyWith(color: c.textPrimary),
            ),
            if (o.orderType == 'delivery')
              DeliveryChannelBadge(
                channel: o.deliveryChannel,
                label: o.deliveryChannel == 'in_mall'
                    ? t('delivery.channelInMall')
                    : t('orders.deliveryOutside'),
              ),
          ],
        ),
        minWidth: Space.xxl * 5 + Space.xs,
      ),
      DashColumn<Order>(
        id: 'date',
        label: t('common.date'),
        numeric: true,
        align: DashAlign.start,
        text: (o) => fmt.fmtDateTime(o.createdAt),
        cell: (context, o) => Text(
          fmt.fmtDateTime(o.createdAt),
          maxLines: 1,
          softWrap: false,
          style: DashType.mono.copyWith(color: c.textSecondary),
        ),
        minWidth: Space.xxl * 5 - Space.xs,
      ),
      DashColumn<Order>(
        id: 'customer',
        label: t('orders.customer'),
        text: (o) => o.customerName ?? '—',
        cell: (context, o) => (o.customerName ?? '').isEmpty
            ? Text('—', style: DashType.body.copyWith(color: c.textPrimary))
            : CustomerLink(
                name: o.customerName!,
                customerId: o.customerId,
                control: control,
              ),
        // The floors fit every column at 1440 (the web's content-sized
        // table); a longer name is cut and reads whole on a hold.
        minWidth: Space.xxl * 3,
        flex: 2,
      ),
      DashColumn<Order>(
        id: 'teller',
        label: t('tills.teller'),
        text: (o) => o.tellerName,
        minWidth: Space.xxl * 3,
        flex: 2,
      ),
      DashColumn<Order>(
        id: 'waiter',
        label: t('tills.waiter'),
        text: (o) => (o.waiterName ?? '').isEmpty ? '—' : o.waiterName!,
        // Mostly "—": the narrowest name column.
        minWidth: Space.xxl * 2 + Space.sm,
      ),
      DashColumn<Order>(
        id: 'status',
        label: t('common.status'),
        text: (o) => orTranslated(t, 'orderStatus.${o.status}', o.status),
        cell: (context, o) => Wrap(
          spacing: Space.xs + DashMetrics.hair,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OrderStatusPill(status: o.status),
            if (o.priceFlagged ?? false) _PriceFlagBadge(order: o),
          ],
        ),
        minWidth: Space.xxl * 4 - Space.xs,
      ),
      DashColumn<Order>(
        id: 'payment',
        label: t('orders.payment'),
        text: payments,
        cell: (context, o) => o.paymentLegs.length <= 1
            ? Text(
                payments(o),
                style: DashType.body.copyWith(color: c.textPrimary),
              )
            : Wrap(
                spacing: Space.xs,
                runSpacing: DashMetrics.hair,
                children: [
                  for (final l in o.paymentLegs)
                    Text.rich(
                      TextSpan(
                        style: DashType.small.copyWith(color: c.textPrimary),
                        children: [
                          TextSpan(
                            text: orTranslated(
                              t,
                              'payments.${l.method}',
                              l.method,
                            ),
                          ),
                          TextSpan(
                            text: ' ${fmt.fmtMoney(l.amount)}',
                            style: DashType.mono.copyWith(
                              fontSize: DashType.small.fontSize,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
        minWidth: Space.xxl * 3.5,
      ),
      DashColumn<Order>(
        id: 'tax',
        label: t('orders.tax'),
        numeric: true,
        text: (o) => fmt.fmtMoney(o.taxAmount),
        cell: (context, o) => Text(
          fmt.fmtMoney(o.taxAmount),
          maxLines: 1,
          softWrap: false,
          style: DashType.mono.copyWith(color: c.textSecondary),
        ),
        minWidth: Space.xxl * 3,
      ),
      DashColumn<Order>(
        id: 'total',
        label: t('common.total'),
        numeric: true,
        text: (o) => fmt.fmtMoney(o.totalAmount),
        cell: (context, o) => Text(
          fmt.fmtMoney(o.totalAmount),
          maxLines: 1,
          softWrap: false,
          style: DashType.monoStrong.copyWith(color: c.textPrimary),
        ),
        minWidth: Space.xxl * 3.5 + Space.xs,
      ),
    ];
  }
}

/// "…" on a row: Details, and Void order on a completed one (SELL-ORD-028).
class _RowActions extends ConsumerWidget {
  const _RowActions({
    required this.order,
    required this.onDetails,
    required this.onDetailsIntent,
    required this.onVoid,
  });

  final Order order;
  final VoidCallback onDetails;
  final VoidCallback onDetailsIntent;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashMenu(
      items: [
        DashMenuItem(
          label: t('common.details'),
          icon: 'eye',
          onSelected: onDetails,
          onIntent: onDetailsIntent,
        ),
        if (order.status == 'completed')
          DashMenuItem(
            label: t('orders.void'),
            icon: 'ban',
            destructive: true,
            onSelected: onVoid,
          ),
      ],
      builder: (context, ctl) => DashIconButton(
        key: ValueKey('order-actions-${order.id}'),
        icon: 'more-horizontal',
        semanticLabel: t('common.actions'),
        onPressed: ctl.toggle,
      ),
    );
  }
}

/// "Offline price" (SELL-ORD-023): the sale was rung offline against an
/// older menu; the tooltip says by how much.
class _PriceFlagBadge extends ConsumerWidget {
  const _PriceFlagBadge({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final expected = order.priceExpectedTotal;
    final hint = [
      t('orders.offlinePriceHint'),
      if (expected != null && expected != order.totalAmount)
        t(
          'orders.offlinePriceExpected',
          args: {'amount': fmt.fmtMoney(expected)},
        ),
    ].join(' ');
    return DashPressable(
      key: ValueKey('price-flag-${order.id}'),
      tooltip: hint,
      semanticLabel: '${t('orders.offlinePrice')}. $hint',
      excludeChildSemantics: true,
      pressScale: false,
      onTap: () {},
      builder: (context, s) => DashStatusPill(
        small: true,
        tone: DashTone.warning,
        icon: 'triangle-alert',
        label: t('orders.offlinePrice'),
      ),
    );
  }
}
