/// One order's detail sheet (the web's `features/orders/order-detail-sheet.tsx`,
/// SELL-ORD-035 … SELL-ORD-062, SELL-ORD-087, SELL-ORD-090).
///
/// A PUBLIC piece of the area: the Orders page opens it, so do a customer's
/// sheet (Customers page, and the read-only one behind every customer link on
/// Floor and Bookings), and later the reports area's staff-pool report.
/// Keep [showOrderSheet]'s signature; the body is the orders unit's.
library;

import 'package:dashboard_api/dashboard_api.dart' show OrderFull;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

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
  builder: (context) => OrderSheet(
    orderId: orderId,
    onVoid: onVoid,
    onSwitchOrder: onSwitchOrder,
  ),
);

/// The sheet's content (a [DashSurface]).
class OrderSheet extends StatelessWidget {
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
  Widget build(BuildContext context) => DashSurface(
    // While the order loads the web titles it "Order" over "Loading…" and
    // shows four skeleton blocks (SELL-ORD-036/037).
    title: context.t('orders.order'),
    description: context.t('common.loading'),
    body: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashSkeleton(height: Space.xxl * 2),
        DashSkeleton(height: Space.xxl * 2),
        DashSkeleton(height: Space.xxl * 2),
        DashSkeleton(height: Space.xxl * 2),
      ],
    ),
  );
}
