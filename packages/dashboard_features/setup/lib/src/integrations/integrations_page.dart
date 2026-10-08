/// `/settings/integrations` Integrations (`features/integrations/integrations-page.tsx`, SET-INT rows).
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane: a section heading, no page gutter.
/// Placeholder body until the unit's page lands.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class IntegrationsPage extends ConsumerWidget {
  const IntegrationsPage({this.edit, super.key});

  /// `?edit=new` (SET-SHL-012, SET-INT-014): the issue dialog, platform
  /// admins only.
  final String? edit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('integrations.title'),
      subtitle: t(
        ref.watch(authzProvider).platform
            ? 'integrations.hint'
            : 'integrations.hintReadOnly',
      ),
      width: DashPageWidth.reading,
      body: DashEmptyState(
        icon: 'layers',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
