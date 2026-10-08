/// The admin area's pages (`/orgs`, `/branches`, `/devices`, `/access/users`,
/// `/access/roles`, `/access/review`, `/onboarding`) with the web's
/// capabilities (any-of, from the generated nav and settings nav) and module. A
/// route without a builder shows the shell's placeholder until its page lands.
library;

import 'package:dashboard_core/dashboard_core.dart';

const List<DashRoute> adminRoutes = [
  DashRoute(
    path: '/orgs',
    titleKey: 'nav.orgs',
    titleFallback: 'Organizations',
    platformOnly: true,
  ),
  DashRoute(
    path: '/branches',
    titleKey: 'nav.branches',
    titleFallback: 'Branches',
    caps: [Cap.branchesRead],
  ),
  DashRoute(
    path: '/devices',
    titleKey: 'nav.devices',
    titleFallback: 'Devices',
    caps: [Cap.branchesEdit, Cap.tillOpen],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/access/users',
    titleKey: 'nav.users',
    titleFallback: 'Users',
    caps: [Cap.staffUsersRead, Cap.staffPermissionsRead],
  ),
  DashRoute(
    path: '/access/roles',
    titleKey: 'nav.rolesPermissions',
    titleFallback: 'Roles & Permissions',
    caps: [Cap.staffPermissionsRead, Cap.staffRolesManage],
  ),
  DashRoute(
    path: '/access/review',
    titleKey: 'access.review.title',
    titleFallback: 'Review',
    caps: [Cap.approvalsReview],
  ),
  DashRoute(
    path: '/onboarding',
    titleKey: 'onboarding.title',
    titleFallback: 'Let\'s open your café',
    module: OrgModule.pos,
  ),
];
