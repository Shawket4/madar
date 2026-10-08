/// `/settings/combos` Combos and deals (`features/combos/combo-settings-page.tsx`, SET-CMB rows).
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane: a section heading, no page gutter.
/// Placeholder body until the unit's page lands.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ComboSettingsPage extends ConsumerWidget {
  const ComboSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('combos.settings.title'),
      subtitle: t('combos.settings.subtitle'),
      width: DashPageWidth.reading,
      body: DashEmptyState(
        icon: 'layers',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
