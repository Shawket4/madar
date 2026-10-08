/// The INV-CNT rows' page (web `src/features/inventory/counts-page.tsx (+ count-editor.tsx, variance-report-dialog.tsx)`).
///
/// Scaffold placeholder: the unit's builder replaces the body.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CountsPage extends ConsumerWidget {
  const CountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('inventory.stocktakes.title'),
      subtitle: t('inventory.stocktakes.subtitle'),
      body: DashEmptyState(
        icon: 'layers',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
