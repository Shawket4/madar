/// The Delivery section (`components/app/delivery-kpis.tsx` under a
/// section header): dashboard_core's [DeliveryChannels], four totals and one
/// card per channel the server sends.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home_providers.dart';

class HomeDeliverySection extends ConsumerWidget {
  const HomeDeliverySection({required this.scope, super.key});

  final Scope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final q = watchIf(
      ref,
      scope.orgId != null,
      () => homeDeliveryProvider(scope.scopeRange),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashSectionHeader(
          title: t('delivery.kpisTitle'),
          description: t('delivery.byChannel'),
        ),
        if (q.hasError && !q.retrying)
          DashErrorState(
            title: t('dashboard.deliveryFailed'),
            retryLabel: t('common.retry'),
            onRetry: () =>
                ref.invalidate(homeDeliveryProvider(scope.scopeRange)),
          )
        else
          DeliveryChannels(data: q.value, loading: q.awaitingFirst),
      ],
    );
  }
}
