/// `/menu/groups`: choice groups, the usage dialog and the group editor
/// (MENU-GRP rows). Web: `features/menu/groups/groups-page.tsx`.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GroupsPage extends ConsumerWidget {
  const GroupsPage({this.edit, super.key});

  /// `?edit=<groupId>|new`: the editor to open.
  final String? edit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('menu.groups.title'),
      subtitle: t('menu.groups.subtitle'),
      body: const SizedBox.shrink(),
    );
  }
}
