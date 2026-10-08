/// `/menu/pricing`: the pricing and availability matrix (MENU-PRC rows).
/// Web: `features/menu/pricing/pricing-availability-page.tsx`.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PricingAvailabilityPage extends ConsumerWidget {
  const PricingAvailabilityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('menu.pricing.title'),
      subtitle: t('menu.pricing.matrixSubtitle'),
      body: const SizedBox.shrink(),
    );
  }
}
