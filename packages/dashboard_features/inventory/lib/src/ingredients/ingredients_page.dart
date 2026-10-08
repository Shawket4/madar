/// The INV-ING (+ INV-ALL) rows' page (web `src/features/inventory/items-page.tsx (+ item-dialog.tsx, item-drawer.tsx)`).
///
/// Scaffold placeholder: the unit's builder replaces the body.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class IngredientsPage extends ConsumerWidget {
  const IngredientsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('inventory.catalog.title'),
      subtitle: t('inventory.catalog.subtitle'),
      body: DashEmptyState(
        icon: 'layers',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
