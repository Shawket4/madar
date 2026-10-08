/// The page a platform admin with no organization picked sees on Today,
/// Ingredients, Purchasing and Settings (INV-ALL-009): the page title and
/// "Select an organization to manage inventory".
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class InventoryNoOrgPage extends ConsumerWidget {
  const InventoryNoOrgPage({
    required this.title,
    this.icon = 'boxes',
    this.width = DashPageWidth.full,
    super.key,
  });

  final String title;

  /// `boxes`; Settings uses `settings-2`.
  final String icon;
  final DashPageWidth width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: title,
      width: width,
      body: DashEmptyState(icon: icon, title: t('inventory.pickOrg')),
    );
  }
}
