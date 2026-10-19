/// `/menu/import`: bring the menu over from Foodics (the Setup page's
/// "Import from Foodics" opens it). The card adds into an empty menu and
/// replaces any other; what the menu holds is read from the categories and
/// the first catalog page (its `total`).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../items/items_providers.dart';
import '../shared/menu_no_org.dart';
import '../shared/menu_providers.dart';
import 'foodics_import.dart';

class MenuImportPage extends ConsumerWidget {
  const MenuImportPage({super.key});

  static const String path = '/menu/import';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final orgId = ref.watch(orgIdProvider);
    Widget body;
    if (orgId == null) {
      body = const MenuNoOrgState();
    } else {
      final categories = ref.watch(menuCategoriesProvider(orgId));
      final items = ref.watch(menuCatalogProvider(firstCatalogPage(orgId)));
      if (categories.hasError || items.hasError) {
        body = DashErrorState(
          onRetry: () => ref
            ..invalidate(menuCategoriesProvider(orgId))
            ..invalidate(menuCatalogProvider(firstCatalogPage(orgId))),
        );
      } else if (!categories.hasValue || !items.hasValue) {
        body = const DashSkeleton(height: Space.xxl * 3);
      } else {
        body = FoodicsImportCard(
          orgId: orgId,
          categories: categories.requireValue.length,
          items: items.requireValue.total,
        );
      }
    }
    return DashPageScaffold(
      title: t('menuImport.title'),
      width: DashPageWidth.reading,
      backTo: '/setup',
      body: body,
    );
  }
}
