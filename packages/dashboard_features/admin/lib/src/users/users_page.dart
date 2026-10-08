/// `/access/users` Users (ADM-USR-001..058): the org's accounts with the
/// Access section tabs, stats, search, Excel export, the user dialog
/// (`?edit=<id>|new`), branch access (`?branches=<id>`) and the person's
/// access sheet (`?access=<id>`). A platform admin with no shop picked sees
/// "Select an organization" (ADM-USR-004). Web: `features/users/*`,
/// `features/access/{person-access-sheet,capability-groups,limits-button}.tsx`.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/access_tabs.dart';
import '../shared/pending_body.dart';
import '../shared/pick_org_state.dart';

class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  static const String path = AccessPaths.users;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.t('users.title');
    if (ref.watch(orgIdProvider) == null) {
      return PickOrgPage(
        title: title,
        icon: 'users',
        message: ref.t('users.pickOrg'),
        tabs: const AccessSectionTabs(),
      );
    }
    return DashPageScaffold(
      title: title,
      subtitle: ref.t('users.subtitle'),
      tabs: const AccessSectionTabs(),
      body: const AdminPendingBody(icon: 'users'),
    );
  }
}
