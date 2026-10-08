/// `/menu/items`: the menu (Items / Add-ons / Categories tabs), their dialogs,
/// paste rows and the export (MENU-ITEMS rows and the area-wide MENU-AREA
/// rows). Web: `features/menu/menu-items-page.tsx`.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MenuItemsPage extends ConsumerWidget {
  const MenuItemsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('nav.menu'),
      subtitle: t('menu.subtitle'),
      body: const SizedBox.shrink(),
    );
  }
}
