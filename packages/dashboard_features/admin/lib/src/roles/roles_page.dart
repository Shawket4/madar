/// `/access/roles` Roles & Permissions (ADM-ROL-001..024): the roles list
/// beside the selected role (`?role=<id>`; `?user=` from old links accepted
/// and ignored), its capability grants and limits, the role dialog and the
/// ask-a-manager policy card. Web: `features/access/{roles-page,role-dialog,
/// ask-manager-card}.tsx`.
///
/// The page gates itself, as the web's does: once the person's permissions
/// are known and hold neither `staff.permissions.read` nor
/// `staff.roles.manage`, it shows the Access tabs over "Not available on this
/// account" (ADM-ROL-001) and reads nothing.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/access_tabs.dart';
import '../shared/pending_body.dart';

/// What opens the page (`canRead` on the web).
const List<String> rolesReadCaps = [
  Cap.staffPermissionsRead,
  Cap.staffRolesManage,
];

class RolesPage extends ConsumerWidget {
  const RolesPage({super.key});

  static const String path = AccessPaths.roles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authz = ref.watch(authzProvider);
    final title = ref.t('nav.rolesPermissions');
    if (authz.ready && !authz.canAny(rolesReadCaps)) {
      return DashPageScaffold(
        title: title,
        tabs: const AccessSectionTabs(),
        body: DashEmptyState(
          icon: 'lock',
          title: ref.t('common.restrictedTitle'),
          description: ref.t('access.noAccess'),
        ),
      );
    }
    return DashPageScaffold(
      title: title,
      subtitle: ref.t('access.rolesSubtitle'),
      tabs: const AccessSectionTabs(),
      body: const AdminPendingBody(icon: 'shield'),
    );
  }
}
