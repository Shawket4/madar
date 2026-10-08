/// `/orders` (the web's `features/orders/orders-page.tsx`, SELL-ORD rows):
/// the list, filters, KPI strip, delivery block, the order sheet, the void
/// dialog and the export sheet.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class OrdersPage extends ConsumerWidget {
  const OrdersPage({this.orderId, this.tillId, super.key});

  /// The route's builder (routes.dart points here; the search params are
  /// this unit's to read).
  static Widget route(BuildContext context, GoRouterState state) {
    final q = state.uri.queryParameters;
    return OrdersPage(
      orderId: q['order'],
      tillId: q['till'] ?? q['till_id'] ?? q['shift_id'],
    );
  }

  /// `?order=`: that order's sheet opens on load (SELL-ORD-011).
  final String? orderId;

  /// `?till=` (`?till_id=`, legacy `?shift_id=`): one till (SELL-ORD-010).
  final String? tillId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('nav.orders'),
      subtitle: t('orders.subtitle'),
      body: DashEmptyState(
        icon: 'layers',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
