/// `/settings/kitchen-routing` Order routing (`features/kitchen-stations/routing-page.tsx`, SET-KRT rows).
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane: a section heading, no page gutter.
/// Placeholder body until the unit's page lands.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class KitchenRoutingPage extends ConsumerWidget {
  const KitchenRoutingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('kitchen.routingTitle'),
      subtitle: t('kitchen.routingSubtitle'),
      width: DashPageWidth.reading,
      body: DashEmptyState(
        icon: 'layers',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
