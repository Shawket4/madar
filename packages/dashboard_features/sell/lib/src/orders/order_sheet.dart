/// One order's detail sheet (the web's `features/orders/order-detail-sheet.tsx`,
/// SELL-ORD-035 … SELL-ORD-062, SELL-ORD-087, SELL-ORD-090).
///
/// A PUBLIC piece of the area: the Orders page opens it, so do a customer's
/// sheet (Customers page, and the read-only one behind every customer link on
/// Floor and Bookings), and later the reports area's staff-pool report.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        DeliveryOrder,
        OrderDeal,
        OrderFull,
        OrderItemAddon,
        OrderItemFull,
        OrgIngredient;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show linkOpenerProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../customers/customer_sheet.dart';
import '../shared/customer_link.dart';
import '../shared/phone.dart';
import 'order_lines.dart';
import 'orders_providers.dart';

/// The sheet's width from `sm` (`sm:max-w-md`).
const double orderSheetWidth = 448;

/// Opens [orderId]'s sheet from the end side (full screen on a phone) and
/// resolves when it closes.
///
/// - [onVoid]: only the Orders page passes it (SELL-ORD-090); the sheet then
///   offers "Void order" on a completed order, closes, and hands the order
///   back to open the void dialog (SELL-ORD-038).
/// - [onSwitchOrder]: choosing another of the member's orders from the member
///   sheet opened inside this one (SELL-ORD-060).
Future<void> showOrderSheet(
  BuildContext context, {
  required String orderId,
  ValueChanged<OrderFull>? onVoid,
  ValueChanged<String>? onSwitchOrder,
}) => showDashSidePanel<void>(
  context,
  width: orderSheetWidth,
  builder: (context) => OrderSheet(
    orderId: orderId,
    onVoid: onVoid,
    onSwitchOrder: onSwitchOrder,
  ),
);

/// The sheet's content.
class OrderSheet extends ConsumerWidget {
  const OrderSheet({
    required this.orderId,
    this.onVoid,
    this.onSwitchOrder,
    super.key,
  });

  final String orderId;
  final ValueChanged<OrderFull>? onVoid;
  final ValueChanged<String>? onSwitchOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final authz = ref.watch(authzProvider);
    final canViewCustomers = authz.can(Cap.customersView);
    // A member is a customer under the same id: open for someone who may
    // read either side of them (`canOpenPerson`).
    final canViewMember = authz.canAny(const [
      Cap.customersView,
      Cap.loyaltyMembersList,
      Cap.loyaltyRead,
    ]);
    final order = ref.watch(orderDetailProvider(orderId)).value;
    final orgId = ref.watch(orgIdProvider);
    final catalog = watchIfOrders(
      ref,
      orgId != null,
      () => orderCatalogProvider(orgId!),
    ).value;
    final deliveryId = order?.deliveryOrderId;
    final deliveryOrder = watchIfOrders(
      ref,
      order?.orderType == 'delivery' && deliveryId != null,
      () => orderDeliveryProvider(deliveryId!),
    ).value;
    final customerId = order?.customerId;
    final owner = watchIfOrders(
      ref,
      customerId != null &&
          deliveryOrder?.contactOverride == true &&
          canViewCustomers,
      () => orderOwnerProvider(customerId!),
    ).value;

    void openMember(String id) => showCustomerSheet(
      context,
      customerId: id,
      readOnly: true,
      // The member sheet closes itself first; another of their orders
      // replaces this one, this same order just comes back.
      onOpenOrder: (picked) {
        if (picked != orderId) onSwitchOrder?.call(picked);
      },
    );

    final full =
        DashSurfaceScope.maybeOf(context) == DashSurfaceMode.fullScreen;
    final close = DashIconButton(
      icon: 'x',
      semanticLabel: t('common.close'),
      onPressed: () => Navigator.of(context).maybePop(),
      color: c.textSecondary,
    );
    final isDelivery = order?.orderType == 'delivery';
    final channel = order?.delivery?.channel;
    final header = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.lg,
        Space.md,
        Space.sm,
        Space.md,
      ),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        spacing: Space.sm,
        children: [
          if (full) close,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        order == null
                            ? t('orders.order')
                            : orderDisplayRef(
                                orderRef: order.orderRef,
                                displayNumber: order.displayNumber,
                                orderNumber: order.orderNumber,
                              ),
                        style: (order == null
                                ? DashType.sectionTitle
                                : DashType.monoStrong.copyWith(
                                    fontSize: DashType.sectionTitle.fontSize,
                                  ))
                            .copyWith(color: c.textPrimary),
                      ),
                    ),
                    if (order != null) OrderStatusPill(status: order.status),
                    if (isDelivery)
                      DeliveryChannelBadge(
                        channel: channel,
                        label: channel == null
                            ? t('orders.delivery')
                            : channelLabel(t, channel),
                      ),
                  ],
                ),
                Text(
                  order == null
                      ? t('common.loading')
                      : fmt.fmtDateTimeFull(order.createdAt),
                  style: DashType.body.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          if (order != null && order.status == 'completed' && onVoid != null)
            DashButton(
              key: const ValueKey('order-sheet-void'),
              label: t('orders.void'),
              icon: 'ban',
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              onPressed: () {
                Navigator.of(context).maybePop();
                onVoid!(order);
              },
            ),
          if (!full) close,
        ],
      ),
    );

    final Widget body;
    if (order == null) {
      // While loading — and, as on the web, when the read fails (a bad or
      // foreign `?order=`): only Close works (SELL-ORD-087).
      body = const Column(
        key: ValueKey('order-sheet-skeleton'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          DashSkeleton(height: Space.xxl * 2.5),
          DashSkeleton(height: Space.xxl * 2.5),
          DashSkeleton(height: Space.xxl * 2.5),
          DashSkeleton(height: Space.xxl * 2.5),
        ],
      );
    } else {
      body = _OrderBody(
        order: order,
        catalog: catalog,
        deliveryOrder: deliveryOrder,
        ownerName: owner?.customer.name,
        canViewCustomers: canViewCustomers,
        canViewMember: canViewMember,
        openMember: openMember,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.lg),
            child: body,
          ),
        ),
      ],
    );
  }
}

/// "In-mall" / "Outside" (the order's own words for its channel).
String channelLabel(Translator t, String channel) => channel == 'in_mall'
    ? t('delivery.channelInMall')
    : t('orders.deliveryOutside');

/// A translated key, or [raw] when the tables have none (the web's
/// `t(key, raw)`).
String orTranslated(Translator t, String key, String raw) =>
    t.exists(key) ? t(key) : raw;

/// The order's status pill: success for completed, danger for voided.
class OrderStatusPill extends ConsumerWidget {
  const OrderStatusPill({required this.status, this.small = false, super.key});

  final String status;
  final bool small;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashStatusPill(
      small: small,
      tone: orderStatusTone(status),
      label: orTranslated(t, 'orderStatus.$status', status),
    );
  }
}

/// The web's `toneFor(status, "success")`.
DashTone orderStatusTone(String status) => switch (status) {
  'voided' || 'cancelled' || 'rejected' || 'refunded' => DashTone.danger,
  'pending' => DashTone.warning,
  _ => DashTone.success,
};

/// A delivery order's channel: a muted badge with the store / bike glyph.
class DeliveryChannelBadge extends StatelessWidget {
  const DeliveryChannelBadge({
    required this.channel,
    required this.label,
    super.key,
  });

  final String? channel;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm - DashMetrics.hair,
        vertical: DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          DashIcon(
            channel == 'in_mall' ? 'store' : 'bike',
            size: IconSize.xs,
            color: c.textSecondary,
          ),
          Text(
            label,
            style: DashType.smallMedium.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _OrderBody extends ConsumerWidget {
  const _OrderBody({
    required this.order,
    required this.catalog,
    required this.deliveryOrder,
    required this.ownerName,
    required this.canViewCustomers,
    required this.canViewMember,
    required this.openMember,
  });

  final OrderFull order;
  final List<OrgIngredient>? catalog;
  final DeliveryOrder? deliveryOrder;
  final String? ownerName;
  final bool canViewCustomers;
  final bool canViewMember;
  final ValueChanged<String> openMember;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final o = order;
    final voided = o.status == 'voided';
    final rewards = orderRewards(o);
    final legs = o.paymentLegs;
    final delivery = o.delivery;
    final muted = DashType.body.copyWith(color: c.textSecondary);

    Widget payment() => legs.length > 1
        ? Wrap(
            alignment: WrapAlignment.end,
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final l in legs)
                DashBadge(
                  '${orTranslated(t, 'payments.${l.method}', l.method)} '
                  '${fmt.fmtMoney(l.amount)}',
                ),
            ],
          )
        : DashBadge(
            orTranslated(t, 'payments.${o.paymentMethod}', o.paymentMethod),
          );

    final info = <Widget>[
      if (rewards.memberId != null && rewards.memberName != null && canViewMember)
        _Row(
          label: t('orders.loyaltyMember'),
          child: CustomerLink(
            key: const ValueKey('order-sheet-member'),
            name: rewards.memberName!,
            customerId: rewards.memberId,
            control: CustomerLinkControl(canOpen: true, open: openMember),
            style: DashType.bodyMedium,
          ),
        )
      else if (rewards.memberId != null)
        _Row.text(
          label: t('orders.loyaltyMember'),
          value: rewards.memberName ?? t('orders.loyaltyMemberForgotten'),
        ),
      _Row.text(label: t('common.date'), value: fmt.fmtDateTimeFull(o.createdAt)),
      _Row.text(label: t('tills.teller'), value: o.tellerName),
      if (o.startedByName != null && o.startedBy != o.tellerId)
        _Row.text(label: t('orders.startedBy'), value: o.startedByName!),
      if ((o.waiterName ?? '').isNotEmpty)
        _Row.text(label: t('tills.waiter'), value: o.waiterName!),
      if ((o.customerName ?? '').isNotEmpty)
        _Row(
          label: t('orders.customer'),
          child: CustomerLink(
            key: const ValueKey('order-sheet-customer'),
            name: o.customerName!,
            customerId: o.customerId,
            control: CustomerLinkControl(
              canOpen: canViewCustomers,
              open: openMember,
            ),
            style: DashType.bodyMedium,
          ),
        ),
      _Row(label: t('orders.payment'), child: payment()),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        if (voided && o.voidReason != null)
          _ToneCard(
            key: const ValueKey('order-sheet-voided'),
            tone: DashTone.danger,
            icon: 'ban',
            title: t('orderStatus.voided'),
            body: orTranslated(t, 'orders.voidReasons.${o.voidReason}', o.voidReason!),
          ),
        if (rewards.refused != null)
          Semantics(
            liveRegion: true,
            child: _ToneCard(
              key: const ValueKey('order-sheet-reward-refused'),
              tone: DashTone.warning,
              icon: 'info',
              title: t('orders.rewardRefusedTitle'),
              body: t('orders.rewardRefusedBody'),
              quote: '“${rewards.refused}”',
            ),
          ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: info,
          ),
        ),
        if (delivery != null)
          _Card(
            key: const ValueKey('order-sheet-delivery'),
            child: _DeliveryInfo(
              order: o,
              deliveryOrder: deliveryOrder,
              ownerName: ownerName,
            ),
          ),
        if (deliveryOrder != null) _DeliveryTimeline(order: deliveryOrder!),
        if (o.items.isNotEmpty)
          _Card(
            key: const ValueKey('order-sheet-items'),
            child: _Items(order: o, rewards: rewards, catalog: catalog),
          ),
        _Card(
          key: const ValueKey('order-sheet-summary'),
          child: _Summary(order: o, rewards: rewards, muted: muted),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      DashCard(padding: const EdgeInsets.all(Space.lg), child: child);
}

/// A label on the start side, its value at the end.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  _Row.text({required this.label, required String value})
    : child = _EndText(value);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: Space.sm,
      children: [
        Text(label, style: DashType.body.copyWith(color: c.textSecondary)),
        Expanded(
          child: Align(alignment: AlignmentDirectional.centerEnd, child: child),
        ),
      ],
    );
  }
}

class _EndText extends StatelessWidget {
  const _EndText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) => Text(
    value,
    textAlign: TextAlign.end,
    textDirection: textDirectionOf(value),
    style: DashType.body.copyWith(color: context.madarColors.textPrimary),
  );
}

/// `dir="auto"`: the direction of the first strong character.
TextDirection? textDirectionOf(String s) {
  for (final r in s.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFEFF)) {
      return TextDirection.rtl;
    }
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
      return TextDirection.ltr;
    }
  }
  return null;
}

/// A tinted card: a glyph, a bold title, a muted line (and a quote).
class _ToneCard extends StatelessWidget {
  const _ToneCard({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    this.quote,
    super.key,
  });

  final DashTone tone;
  final String icon;
  final String title;
  final String body;
  final String? quote;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final (fg, bg) = switch (tone) {
      DashTone.danger => (c.danger, c.dangerBg),
      DashTone.warning => (c.warning, c.warningBg),
      _ => (c.info, c.infoBg),
    };
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: DashMetrics.hair),
            child: DashIcon(icon, size: IconSize.sm, color: fg),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DashMetrics.hair,
              children: [
                Text(title, style: DashType.bodyStrong.copyWith(color: c.textPrimary)),
                Text(body, style: DashType.small.copyWith(color: c.textSecondary)),
                if (quote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(
                      quote!,
                      textDirection: textDirectionOf(quote!),
                      style: DashType.small.copyWith(color: c.textPrimary),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── delivery ─────────────────────────────────────────────────────────────

class _DeliveryInfo extends ConsumerWidget {
  const _DeliveryInfo({
    required this.order,
    required this.deliveryOrder,
    required this.ownerName,
  });

  final OrderFull order;
  final DeliveryOrder? deliveryOrder;
  final String? ownerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final d = order.delivery!;
    final address = [
      d.placeName,
      d.addressLine,
      d.landmark,
      if ((d.floor ?? '').isNotEmpty) '${t('orders.floor')} ${d.floor}',
      if ((d.unitNumber ?? '').isNotEmpty) '${t('orders.unit')} ${d.unitNumber}',
    ].whereType<String>().where((p) => p.trim().isNotEmpty).toList();
    final lat = order.deliveryLat, lng = order.deliveryLng;
    final maps = lat != null && lng != null
        ? Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
          )
        : null;
    final dOrder = deliveryOrder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        Row(
          spacing: Space.sm,
          children: [
            Text(
              t('orders.deliveryInfo'),
              style: DashType.bodyStrong.copyWith(color: c.textPrimary),
            ),
            DashBadge(channelLabel(t, d.channel)),
          ],
        ),
        if (dOrder != null && dOrder.contactOverride == true)
          _ContactNote(
            customerName: ownerName,
            name: dOrder.customerName,
            phone: dOrder.customerPhone,
          ),
        _Row.text(label: t('orders.phone'), value: d.customerPhone),
        if (address.isNotEmpty)
          _Row.text(label: t('orders.address'), value: address.join(' · ')),
        if ((d.deliveryNotes ?? '').isNotEmpty)
          _Row.text(label: t('orders.deliveryNotes'), value: d.deliveryNotes!),
        if ((d.zoneName ?? '').isNotEmpty)
          _Row.text(label: t('orders.zone'), value: d.zoneName!),
        if (d.roadDistanceMeters != null)
          _Row.text(
            label: t('orders.distance'),
            value:
                '${fmt.fmtNumber(d.roadDistanceMeters! / 1000, const NumberOptions(minimumFractionDigits: 1, maximumFractionDigits: 1))} '
                '${t('delivery.kmUnit')}',
          ),
        if ((d.deliveryRef ?? '').isNotEmpty)
          _Row.text(label: t('orders.deliveryRef'), value: d.deliveryRef!),
        if (maps != null)
          _Row(
            label: t('orders.location'),
            child: DashPressable(
              key: const ValueKey('order-sheet-maps'),
              onTap: () => ref.read(linkOpenerProvider)(maps),
              semanticLabel: t('orders.openInMaps'),
              excludeChildSemantics: true,
              pressScale: false,
              builder: (context, s) => ConstrainedBox(
                constraints: const BoxConstraints(minHeight: DashMetrics.target),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.xs,
                  children: [
                    DashIcon('map-pin', size: IconSize.xs, color: c.textPrimary),
                    Text(
                      t('orders.openInMaps'),
                      style: DashType.bodyMedium.copyWith(
                        color: s.highlighted ? c.textSecondary : c.textPrimary,
                        decoration: TextDecoration.underline,
                        decorationColor: c.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "Ordered by X for Y" (`ContactOverrideNote`).
class _ContactNote extends ConsumerWidget {
  const _ContactNote({
    required this.customerName,
    required this.name,
    required this.phone,
  });

  final String? customerName;
  final String name;
  final String? phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final strong = DashType.smallMedium.copyWith(color: c.textPrimary);
    final contact = [
      TextSpan(text: name),
      if ((phone ?? '').isNotEmpty) ...[
        const TextSpan(text: ' · '),
        TextSpan(
          // One unbreakable figure: a number never wraps mid-way.
          text: ltr(formatPhoneDisplay(phone).replaceAll(' ', '\u00A0')),
          style: DashType.mono.copyWith(
            fontSize: DashType.small.fontSize,
            color: c.textPrimary,
          ),
        ),
      ],
    ];
    final owner = customerName;
    return Semantics(
      container: true,
      child: Container(
        key: const ValueKey('order-sheet-contact-note'),
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: c.hairline),
        ),
        child: Text.rich(
          TextSpan(
            style: DashType.small.copyWith(color: c.textSecondary),
            children: owner != null && owner.isNotEmpty
                ? [
                    TextSpan(text: '${t('customers.orderedBy')} '),
                    TextSpan(text: owner, style: strong),
                    TextSpan(text: ' ${t('customers.orderedFor')} '),
                    TextSpan(style: strong, children: contact),
                  ]
                : [
                    TextSpan(text: '${t('customers.orderedForSomeoneElse')} '),
                    TextSpan(style: strong, children: contact),
                  ],
          ),
        ),
      ),
    );
  }
}

const List<(String, String)> _steps = [
  ('received', 'deliveryTimeline.received'),
  ('confirmed', 'deliveryTimeline.confirmed'),
  ('preparing', 'deliveryTimeline.preparing'),
  ('ready', 'deliveryTimeline.ready'),
  ('out_for_delivery', 'deliveryTimeline.outForDelivery'),
  ('delivered', 'deliveryTimeline.delivered'),
];

class _DeliveryTimeline extends ConsumerWidget {
  const _DeliveryTimeline({required this.order});

  final DeliveryOrder order;

  DateTime? _stamp(String step) => switch (step) {
    'received' => order.createdAt,
    'confirmed' => order.confirmedAt,
    'preparing' => order.preparingAt,
    'ready' => order.readyAt,
    'out_for_delivery' => order.outForDeliveryAt,
    'delivered' => order.deliveredAt,
    _ => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final current = _steps.indexWhere((s) => s.$1 == order.status);
    final off = order.status == 'cancelled' || order.status == 'rejected';
    return _Card(
      key: const ValueKey('order-sheet-timeline'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: Space.xs,
            children: [
              Text(
                t('deliveryTimeline.title'),
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
              DashPressable(
                tooltip: t('deliveryTimeline.hint'),
                semanticLabel: t('deliveryTimeline.hint'),
                excludeChildSemantics: true,
                pressScale: false,
                onTap: () {},
                builder: (context, s) => SizedBox.square(
                  dimension: DashMetrics.target,
                  child: Center(
                    child: DashIcon('info', size: IconSize.xs, color: c.textSecondary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          if (off)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DashStatusPill(
                tone: DashTone.danger,
                label: orTranslated(t, 'orderStatus.${order.status}', order.status),
              ),
            )
          else
            for (final (i, (key, label)) in _steps.indexed)
              _Step(
                label: t(label),
                stamp: _stamp(key) == null ? null : fmt.fmtDateTimeFull(_stamp(key)),
                reached: current >= 0 && i <= current,
                lineFilled: i < current,
                last: i == _steps.length - 1,
              ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.stamp,
    required this.reached,
    required this.lineFilled,
    required this.last,
  });

  final String label;
  final String? stamp;
  final bool reached;
  final bool lineFilled;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    const dot = Space.lg + Space.xs;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Column(
            children: [
              Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: reached ? c.accent : c.bg,
                  border: Border.all(
                    color: reached ? c.accent : c.muted,
                    width: DashMetrics.hair,
                  ),
                ),
                child: reached
                    ? Center(
                        child: DashIcon(
                          'check',
                          size: IconSize.xs,
                          color: c.textOnAccent,
                        ),
                      )
                    : null,
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: DashMetrics.hair,
                    constraints: const BoxConstraints(minHeight: Space.lg),
                    color: lineFilled ? c.accent : c.muted,
                  ),
                ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: (reached ? DashType.bodyMedium : DashType.body)
                        .copyWith(color: reached ? c.textPrimary : c.textSecondary),
                  ),
                  if (stamp != null)
                    Text(
                      stamp!,
                      style: DashType.mono.copyWith(
                        fontSize: DashType.small.fontSize,
                        color: c.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── items ────────────────────────────────────────────────────────────────

class _Items extends ConsumerWidget {
  const _Items({
    required this.order,
    required this.rewards,
    required this.catalog,
  });

  final OrderFull order;
  final OrderRewards rewards;
  final List<OrgIngredient>? catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final costPerUnit = {
      for (final i in catalog ?? const <OrgIngredient>[])
        if (i.costPerUnit != null) i.id: i.costPerUnit!,
    };
    final rows = orderRows(order.items);
    final deals = dealsOf(order);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        Text(
          t('menu.items'),
          style: DashType.bodyStrong.copyWith(color: c.textPrimary),
        ),
        for (final (i, row) in rows.indexed)
          switch (row) {
            ComboRow() => _ComboHeader(row: row),
            LineRow() => _Line(
              line: row.line,
              part: row.part,
              last: i == rows.length - 1,
              reward: rewards.lines[row.line.id],
              deals: deals,
              costPerUnit: costPerUnit,
            ),
          },
      ],
    );
  }
}

class _ComboHeader extends ConsumerWidget {
  const _ComboHeader({required this.row});

  final ComboRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final l = row.line;
    return Padding(
      key: ValueKey('combo-header-${l.id}'),
      padding: const EdgeInsets.only(top: Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.sm,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DashMetrics.hair,
              children: [
                Wrap(
                  spacing: Space.xs + DashMetrics.hair,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${ltr('${fmt.fmtNumber(l.quantity)} ×')} '
                      '${translatedName(l.itemName, l.nameTranslations, lang)}',
                      style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                    ),
                    DashStatusPill(
                      small: true,
                      tone: DashTone.info,
                      icon: 'layers',
                      label: t('combos.order.combo'),
                    ),
                  ],
                ),
                if (l.comboUnitPrice != null)
                  Text(
                    t('combos.order.each', args: {'price': fmt.fmtMoney(l.comboUnitPrice)}),
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                if ((l.notes ?? '').isNotEmpty)
                  Text(
                    l.notes!,
                    style: DashType.small.copyWith(
                      color: c.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            fmt.fmtMoney(row.total),
            style: DashType.monoStrong.copyWith(
              fontSize: DashType.body.fontSize,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends ConsumerStatefulWidget {
  const _Line({
    required this.line,
    required this.part,
    required this.last,
    required this.reward,
    required this.deals,
    required this.costPerUnit,
  });

  final OrderItemFull line;
  final bool part;
  final bool last;
  final RewardLine? reward;
  final List<OrderDeal> deals;
  final Map<String, double> costPerUnit;

  @override
  ConsumerState<_Line> createState() => _LineState();
}

class _LineState extends ConsumerState<_Line> {
  /// The ingredients list is closed until asked for (`<details>`).
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final it = widget.line;
    final small = DashType.small.copyWith(color: c.textSecondary);
    final staff = staffDrinkLine(it);
    final reward = widget.reward;
    final deductions = deductionsOf(it);
    final size = it.sizeLabel;

    final notes = <Widget>[
      if (reward != null)
        Text(
          // en.json's template carries its own minus: the amount goes in
          // unsigned (the web's double "−−" is a bug; divergence log).
          t(
            'orders.rewardCovers',
            args: {
              'units': reward.units?.toString() ?? '—',
              'amount': fmt.fmtMoney(reward.covered),
            },
          ),
          style: small,
        ),
      Text(
        '× ${fmt.fmtNumber(it.quantity)} · ${fmt.fmtMoney(it.unitPrice)}',
        style: small,
      ),
      if (widget.part) ?_partNote(t, fmt, lang, it, small)
      else ?_dealNote(t, fmt, lang, it, small),
      if (it.addons.isNotEmpty)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: Space.sm, top: Space.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DashMetrics.hair,
            children: [for (final a in it.addons) _addon(t, fmt, lang, a, small)],
          ),
        ),
      if (it.optionals.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final o in it.optionals)
                if (translatedName(o.fieldName, o.nameTranslations, lang).isNotEmpty)
                  DashBadge(
                    '${translatedName(o.fieldName, o.nameTranslations, lang)}'
                    '${o.price > 0 ? ' +${fmt.fmtMoney(o.price)}' : ''}',
                  ),
            ],
          ),
        ),
      if ((it.notes ?? '').isNotEmpty)
        Text(it.notes!, style: small.copyWith(fontStyle: FontStyle.italic)),
    ];

    final content = Column(
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
                        translatedName(it.itemName, it.nameTranslations, lang),
                        style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                      ),
                      // A combo part of a single-size item carries
                      // "one_size": not a size anyone chose.
                      if (size != null && size != oneSize)
                        Text(
                          '($size)',
                          style: DashType.body.copyWith(color: c.textSecondary),
                        ),
                      if (reward != null)
                        DashStatusPill(
                          small: true,
                          tone: DashTone.success,
                          label: t('orders.reward'),
                        ),
                      if (staff != null)
                        DashStatusPill(
                          small: true,
                          tone: DashTone.info,
                          icon: 'cup-soda',
                          label: t('orders.staffDrink'),
                        ),
                    ],
                  ),
                  ...notes,
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  fmt.fmtMoney(it.lineTotal),
                  style: (widget.part ? DashType.mono : DashType.monoStrong).copyWith(
                    fontSize: DashType.body.fontSize,
                    color: widget.part ? c.textSecondary : c.textPrimary,
                  ),
                ),
                Text(
                  '${t('orders.cost')}: ${fmt.fmtMoney(it.lineCost)}'
                  '${it.costMissing ? ' · ${t('orders.costMissing')}' : ''}',
                  style: small,
                ),
              ],
            ),
          ],
        ),
        if (staff != null && staff.comp > 0)
          Container(
            key: ValueKey('staff-line-${it.id}'),
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: Column(
              children: [
                _staffRow(t('orders.staffLineNormal'), fmt.fmtMoney(staff.normal), false),
                _staffRow(t('orders.staffLineComp'), fmt.fmtMoney(-staff.comp), false),
                _staffRow(t('orders.staffLineCharged'), fmt.fmtMoney(staff.charged), true),
              ],
            ),
          ),
        if (deductions.isNotEmpty) _ingredients(t, fmt, deductions, small),
      ],
    );

    return Container(
      key: ValueKey('order-line-${it.id}'),
      margin: widget.part ? const EdgeInsetsDirectional.only(start: Space.md) : null,
      padding: EdgeInsetsDirectional.only(
        start: widget.part ? Space.md : 0,
        top: Space.sm,
        bottom: Space.sm,
      ),
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: widget.part
              ? BorderSide(color: c.hairline)
              : BorderSide.none,
          bottom: widget.last ? BorderSide.none : BorderSide(color: c.hairline),
        ),
      ),
      child: content,
    );
  }

  Widget _staffRow(String label, String value, bool strong) {
    final c = context.madarColors;
    final style = (strong ? DashType.smallStrong : DashType.small).copyWith(
      color: strong ? c.textPrimary : c.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DashMetrics.hair),
      child: Row(
        spacing: Space.md,
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            value,
            style: (strong ? DashType.monoStrong : DashType.mono).copyWith(
              fontSize: DashType.small.fontSize,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget? _partNote(
    Translator t,
    DashFormat fmt,
    String lang,
    OrderItemFull it,
    TextStyle style,
  ) {
    final surcharge = it.comboSurcharge ?? 0;
    final slotName = it.comboSlotName;
    final slot = slotName == null || slotName.isEmpty
        ? ''
        : translatedName(slotName, it.comboSlotNameTranslations, lang);
    final parts = [
      if (slot.isNotEmpty) slot,
      if (surcharge > 0)
        t('combos.order.upgrade', args: {'amount': fmt.fmtMoney(surcharge)}),
    ];
    if (parts.isEmpty) return null;
    return Text(parts.join(' · '), style: style);
  }

  Widget? _dealNote(
    Translator t,
    DashFormat fmt,
    String lang,
    OrderItemFull it,
    TextStyle style,
  ) {
    final cut = it.dealMinor ?? 0;
    if (cut <= 0) return null;
    final deal = dealOfLine(widget.deals, it.id);
    final name = deal == null
        ? t('combos.order.aDeal')
        : translatedName(deal.name, deal.nameTranslations, lang);
    return Text(
      t('combos.order.dealCut', args: {'deal': name, 'amount': fmt.fmtMoney(-cut)}),
      style: style,
    );
  }

  Widget _addon(
    Translator t,
    DashFormat fmt,
    String lang,
    OrderItemAddon a,
    TextStyle muted,
  ) {
    final c = context.madarColors;
    final name = translatedName(a.addonName, a.nameTranslations, lang);
    final comp = a.staffCompMinor ?? 0;
    return Text.rich(
      TextSpan(
        style: DashType.small.copyWith(color: c.textPrimary),
        children: [
          TextSpan(text: '+ $name${a.quantity > 1 ? ' ×${a.quantity}' : ''}'),
          if (comp > 0)
            TextSpan(
              // A pick the pool covered: its normal price and what came off.
              text:
                  ' (${fmt.fmtMoney(addonNormalTotal(a))}) '
                  '${t('orders.staffCompAddon', args: {'amount': fmt.fmtMoney(-comp)})}',
              style: muted,
            )
          else if (a.lineTotal > 0)
            TextSpan(text: ' (${fmt.fmtMoney(a.lineTotal)})', style: muted),
        ],
      ),
    );
  }

  Widget _ingredients(
    Translator t,
    DashFormat fmt,
    List<Deduction> deductions,
    TextStyle small,
  ) {
    final c = context.madarColors;
    return Container(
      margin: const EdgeInsets.only(top: Space.xs),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.hairline))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashPressable(
            key: ValueKey('ingredients-${widget.line.id}'),
            onTap: () => setState(() => _open = !_open),
            pressScale: false,
            semanticLabel: '${t('orders.ingredientsUsed')} (${deductions.length})',
            excludeChildSemantics: true,
            expanded: _open,
            builder: (context, s) => ConstrainedBox(
              constraints: const BoxConstraints(minHeight: DashMetrics.target),
              child: Row(
                spacing: Space.xs,
                children: [
                  DashIcon(
                    _open ? 'chevron-down' : DashIcon.forward(context),
                    size: IconSize.xs,
                    color: c.textSecondary,
                  ),
                  Text(
                    '${t('orders.ingredientsUsed')} (${deductions.length})',
                    style: DashType.smallMedium.copyWith(
                      color: s.highlighted ? c.textPrimary : c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: Space.md, bottom: Space.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DashMetrics.hair,
                children: [
                  for (final d in deductions)
                    Row(
                      spacing: Space.sm,
                      children: [
                        Expanded(
                          child: Text(
                            '${d.ingredientName}: ${ltr('${fmt.fmtNumber(d.quantity, const NumberOptions(maximumFractionDigits: 3))} ${fmtUnit(d.unit)}')}',
                            style: small,
                          ),
                        ),
                        if (d.costWith(widget.costPerUnit) != null)
                          Text(fmt.fmtMoney(d.costWith(widget.costPerUnit)), style: small),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── summary ──────────────────────────────────────────────────────────────

class _Summary extends ConsumerWidget {
  const _Summary({
    required this.order,
    required this.rewards,
    required this.muted,
  });

  final OrderFull order;
  final OrderRewards rewards;
  final TextStyle muted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final o = order;
    final staffComp = orderStaffComp(o.items);
    final deals = dealsOf(o);
    final dealsTotal = orderDealsTotal(deals);
    final attribution = o.discountAmount > 0 ? discountAttribution(t, o) : null;
    final cogs = orderCogs(o);
    final small = DashType.small.copyWith(color: c.textSecondary);
    final figure = DashType.mono.copyWith(
      fontSize: DashType.small.fontSize,
      color: c.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (staffComp > 0 || dealsTotal > 0) ...[
          // The subtotal is stored net of the comp and every deal: put them
          // back for one line and take each off under it.
          DashSummaryLine(
            label: t('orders.beforeStaffDrinks'),
            value: fmt.fmtMoney(o.subtotal + staffComp + dealsTotal),
          ),
          if (staffComp > 0)
            DashSummaryLine(
              label: t('orders.staffDrinksGiven'),
              value: fmt.fmtMoney(-staffComp),
            ),
          for (final d in deals)
            DashSummaryLine(
              label: translatedName(d.name, d.nameTranslations, lang),
              value: fmt.fmtMoney(-d.discount),
            ),
        ],
        DashSummaryLine(label: t('common.subtotal'), value: fmt.fmtMoney(o.subtotal)),
        if (rewards.totalCovered > 0 || rewards.memberId != null)
          DashSummaryLine(
            label: rewards.memberName != null
                ? t('orders.loyaltyRewardsFor', args: {'name': rewards.memberName})
                : t('orders.loyaltyRewards'),
            value: rewards.totalCovered > 0
                ? fmt.fmtMoney(-rewards.totalCovered)
                : '—',
          ),
        if (o.discountAmount > 0) ...[
          DashSummaryLine(label: t('orders.discount'), value: fmt.fmtMoney(-o.discountAmount)),
          if (attribution != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Text(attribution, style: small),
            ),
        ],
        if (o.taxAmount > 0)
          DashSummaryLine(label: t('orders.tax'), value: fmt.fmtMoney(o.taxAmount)),
        if ((o.tipAmount ?? 0) != 0)
          DashSummaryLine(label: t('orders.tip'), value: fmt.fmtMoney(o.tipAmount)),
        if (o.deliveryFee > 0)
          DashSummaryLine(label: t('orders.deliveryFee'), value: fmt.fmtMoney(o.deliveryFee)),
        Container(
          margin: const EdgeInsets.only(top: Space.xs),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.hairline))),
          child: _TotalLine(
            label: t('common.total'),
            value: fmt.fmtMoney(o.totalAmount),
            struck: o.status == 'voided',
          ),
        ),
        if (o.items.isNotEmpty)
          Container(
            key: const ValueKey('order-sheet-cogs'),
            margin: const EdgeInsets.only(top: Space.sm),
            padding: const EdgeInsets.only(top: Space.sm),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.hairline))),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: Space.sm,
              runSpacing: Space.xs,
              children: [
                Text.rich(
                  TextSpan(
                    style: small,
                    children: [
                      TextSpan(text: '${t('orders.cogs')}: '),
                      TextSpan(
                        text: '${cogs.anyMissing ? '≥ ' : ''}${fmt.fmtMoney(cogs.known)}',
                        style: figure,
                      ),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(
                    style: small,
                    children: [
                      TextSpan(text: '${t('orders.grossProfit')}: '),
                      TextSpan(
                        text:
                            '${cogs.anyMissing ? '≤ ' : ''}${fmt.fmtMoney(cogs.profit)}'
                            '${cogs.profitShare == null ? '' : ' (${fmt.fmtPercent(cogs.profitShare!)})'}',
                        style: figure,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The emphasised Total; struck through on a voided order.
class _TotalLine extends StatelessWidget {
  const _TotalLine({required this.label, required this.value, required this.struck});

  final String label;
  final String value;
  final bool struck;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final fg = struck ? c.textSecondary : c.textPrimary;
    final deco = struck ? TextDecoration.lineThrough : null;
    return ConstrainedBox(
      key: const ValueKey('order-sheet-total'),
      constraints: const BoxConstraints(minHeight: Metrics.headerHeight),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: DashType.bodyStrong.copyWith(color: fg, decoration: deco),
            ),
          ),
          Text(
            value,
            style: DashType.monoStrong.copyWith(
              fontSize: DashType.sectionTitle.fontSize,
              color: fg,
              decoration: deco,
              decorationColor: fg,
            ),
          ),
        ],
      ),
    );
  }
}
