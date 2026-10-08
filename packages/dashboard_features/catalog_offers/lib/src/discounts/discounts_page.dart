/// `/discounts`: the discounts list, its export and the discount dialog
/// (inventory OFFR-DSC rows); `?edit=<id>|new` opens the dialog. The web
/// gates nothing on this page (OFFR-DSC-003): the server refuses.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DiscountsPage extends ConsumerWidget {
  const DiscountsPage({this.edit, super.key});

  /// The `edit` search param: a discount id, `new`, or null.
  final String? edit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('discounts.title'),
      subtitle: t('discounts.subtitle'),
      body: DashEmptyState(
        icon: 'badge-percent',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
