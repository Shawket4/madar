/// `/menu/items/:itemId`: the Menu Studio, one page with one batched save
/// (MENU-STUDIO rows). Web: `features/menu/studio/menu-studio-page.tsx`.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MenuStudioPage extends ConsumerWidget {
  const MenuStudioPage({required this.itemId, this.tab, super.key});

  final String itemId;

  /// `?tab=` (old deep links): the section to scroll to once loaded.
  final String? tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('menu.studio.itemTitle'),
      width: DashPageWidth.reading,
      onBack: () => context.go('/menu/items'),
      body: const SizedBox.shrink(),
    );
  }
}
