/// `/menu/combos`: the combos list (inventory OFFR-CMB rows and the
/// area-wide OFFR-ALL rows).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/offers_page_gate.dart';

class CombosPage extends ConsumerWidget {
  const CombosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return OffersPageGate(
      title: t('combos.title'),
      caps: const [Cap.menuItemsRead],
      who: t('combos.noAccess'),
      child: DashPageScaffold(
        title: t('combos.title'),
        subtitle: t('combos.subtitle'),
        body: DashEmptyState(
          icon: 'sandwich',
          title: t('shell.pendingTitle'),
          description: t('shell.pendingBody'),
        ),
      ),
    );
  }
}
