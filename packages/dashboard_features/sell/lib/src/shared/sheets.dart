/// The read-only customer sheet behind every customer link on a surface (the
/// web's `features/customers/use-customer-sheet.tsx`, SELL-ALL-016): the
/// seam between the units, so Orders, Floor and Bookings open the customers
/// unit's sheet and the orders unit's order sheet without owning either.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../customers/customer_sheet.dart';
import '../customers/customers_data.dart' show customerDetailProvider;
import '../orders/order_sheet.dart';
import 'customer_link.dart';

/// The [CustomerLinkControl] of one surface: links open when the viewer holds
/// `customers.view`, into a READ-ONLY customer sheet (no edit, merge, erase
/// or loyalty actions). Choosing one of the customer's orders closes that
/// sheet first, then:
/// - with [onOpenOrder] (the Orders page: `?order=` and its own sheet, with
///   Void) that order goes there;
/// - otherwise it opens in an order sheet of its own, with NO Void button
///   (Floor, Bookings); another of the member's orders chosen from inside it
///   replaces it ([singleOrderSheet]).
///
/// Call it in a build: it watches the person's capabilities.
CustomerLinkControl customerSheetControl(
  BuildContext context,
  WidgetRef ref, {
  ValueChanged<String>? onOpenOrder,
}) {
  final canOpen = ref.watch(authzProvider).can(Cap.customersView);
  return CustomerLinkControl(
    canOpen: canOpen,
    open: (customerId) {
      if (!canOpen) return;
      showCustomerSheet(
        context,
        customerId: customerId,
        readOnly: true,
        onOpenOrder: onOpenOrder ?? singleOrderSheet(context),
      );
    },
    warm: (customerId) => ref.warm(customerDetailProvider(customerId)),
  );
}

/// One order sheet at a time, without Void (the web's single
/// `OrderDetailSheet` whose `orderId` is state, `onSwitchOrder` setting it):
/// another order chosen from inside it (through its member's sheet, which
/// closes itself first) replaces it rather than stacking a second.
ValueChanged<String> singleOrderSheet(BuildContext context) {
  String? open;
  late final ValueChanged<String> show;
  show = (orderId) {
    final replacing = open != null;
    open = orderId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) return;
      if (replacing) {
        await Navigator.of(context, rootNavigator: true).maybePop();
      }
      if (!context.mounted || open != orderId) return;
      await showOrderSheet(context, orderId: orderId, onSwitchOrder: show);
      if (open == orderId) open = null;
    });
  };
  return show;
}
