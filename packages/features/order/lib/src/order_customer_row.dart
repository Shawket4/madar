import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart'
    show CustomerSheet, showCustomerCard;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The customer an order is for — a cart before it is fired, or an open bill
/// — as the one row the charge sheet and the order history already use.
///
/// Nobody yet: the row picks one, for someone holding `customers.attach`.
/// Somebody: the row is their name and member badge, it opens their card,
/// and (with the permission) its close takes them off. Read from the till's
/// own list, so it works offline; a customer this till does not hold reads as
/// nobody. Without the permission and with nobody on the order it is nothing.
class OrderCustomerRow extends ConsumerWidget {
  const OrderCustomerRow({
    required this.customerId,
    required this.onChanged,
    super.key,
  });

  final String? customerId;

  /// The pick, or null when the customer was taken off.
  final ValueChanged<CustomerView?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final customer = customerOf(bridge, customerId);
    final may = bridge.can(cap: Cap.customersAttach);
    if (customer == null && !may) return const SizedBox.shrink();
    final phone = customer?.phone ?? customer?.phoneHint;
    return MadarListRow.nav(
      key: const ValueKey('order.customer'),
      title: bridge.tr(key: 'customers.attach'),
      valueText: customer == null
          ? bridge.tr(key: 'customers.search_hint')
          : customer.isMember
          ? '${customer.name} · ${bridge.tr(key: 'customers.member')}'
          : customer.name,
      meta: phone == null ? null : MadarFormat.ltr(phone),
      onTap: customer != null
          ? () => unawaited(showCustomerCard(context, customer))
          : () => unawaited(
              showMadarSheet<void>(
                context,
                size: SheetSize.hug,
                maxWidth: Responsive.sheetCompactMaxWidth,
                builder: (_) => CustomerSheet(
                  title: bridge.tr(key: 'customers.history_title'),
                  onPicked: onChanged,
                ),
              ),
            ),
      trailing: may && customer != null
          ? MadarGlyphTile(
              glyph: MadarGlyph.close,
              semanticLabel: bridge.tr(key: 'customers.remove'),
              onTap: () => onChanged(null),
            )
          : null,
    );
  }
}

/// The till's own row for [id]; null when there is none or it is not held.
CustomerView? customerOf(MadarBridge bridge, String? id) {
  if (id == null) return null;
  try {
    return bridge.customerById(id: id);
  } on MadarError {
    return null;
  }
}

/// Who a bill is for, as one piece of a list row's meta line: the linked
/// customer with their member badge, else the free-text name the bill was
/// opened under. [nameIsTitle] is a table-less bill, whose title is already
/// that name — then only what the title does not say is returned.
String? billCustomerLabel(
  MadarBridge bridge,
  TicketView t, {
  required bool nameIsTitle,
}) {
  final typed = t.customerName?.trim();
  final snapshot = (typed?.isEmpty ?? true) ? null : typed;
  final linked = customerOf(bridge, t.customerId);
  if (linked == null) return nameIsTitle ? null : snapshot;
  final member = linked.isMember ? bridge.tr(key: 'customers.member') : null;
  if (nameIsTitle && linked.name.trim() == snapshot) return member;
  return member == null ? linked.name : '${linked.name} · $member';
}
