/// `/menu/combos/:comboId`: the combo editor (inventory OFFR-CED rows);
/// `new` creates one.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/offers_page_gate.dart';

class ComboEditorPage extends ConsumerWidget {
  const ComboEditorPage({required this.comboId, super.key});

  /// The combo's id, or `new`.
  final String comboId;

  bool get isNew => comboId == 'new';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final title = isNew ? t('combos.new') : t('combos.title');
    return OffersPageGate(
      title: title,
      caps: const [Cap.menuItemsRead],
      child: DashPageScaffold(
        title: title,
        onBack: () => context.go('/menu/combos'),
        body: DashEmptyState(
          icon: 'sandwich',
          title: t('shell.pendingTitle'),
          description: t('shell.pendingBody'),
        ),
      ),
    );
  }
}
