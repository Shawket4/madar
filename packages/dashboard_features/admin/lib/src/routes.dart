/// The admin area's pages (`/orgs`, `/branches`, `/devices`, `/access/users`,
/// `/access/roles`, `/access/review`, `/onboarding`).
///
/// Page gates are the web's own, which are NOT its nav gates: none of these
/// web routes has a route guard or a `<Restricted>` wrapper, so whoever
/// reaches the URL sees the page frame and the server refuses what they may
/// not read (Organizations ADM-ORG-004, Review ADM-REV-004, …); the nav's
/// leaf rules (platform only, `branches.read`, …) live in the generated nav.
/// The one page that gates itself, Roles & Permissions (ADM-ROL-001), does it
/// inside the page so the Access tabs stay above the refusal. `/devices` is a
/// POS page (the module gate also derives it from the path); `/onboarding`
/// is full screen, outside the shell and never module-gated.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'branch_setup/branch_setup_page.dart';
import 'branches/branches_page.dart';
import 'devices/devices_page.dart';
import 'onboarding/onboarding_page.dart';
import 'orgs/orgs_page.dart';
import 'orgs/orgs_providers.dart';
import 'review/review_data.dart' show reviewFlagsProvider;
import 'review/review_page.dart';
import 'roles/roles_data.dart' show prefetchRoles;
import 'roles/roles_page.dart';
import 'users/users_data.dart' show prefetchUsers;
import 'users/users_page.dart';

Widget _orgs(BuildContext context, GoRouterState state) => const OrgsPage();

Widget _branches(BuildContext context, GoRouterState state) =>
    const BranchesPage();

Widget _branchSetup(BuildContext context, GoRouterState state) =>
    const BranchSetupPage();

Widget _devices(BuildContext context, GoRouterState state) =>
    const DevicesPage();

Widget _users(BuildContext context, GoRouterState state) => const UsersPage();

Widget _roles(BuildContext context, GoRouterState state) => const RolesPage();

Widget _review(BuildContext context, GoRouterState state) => const ReviewPage();

Widget _onboarding(BuildContext context, GoRouterState state) =>
    const OnboardingPage();

const List<DashRoute> adminRoutes = [
  DashRoute(
    path: OrgsPage.path,
    builder: _orgs,
    titleKey: 'nav.orgs',
    titleFallback: 'Organizations',
    // The web only hides it from the nav; a deep link loads a page whose
    // every call the server refuses. Restricted instead (shell contract).
    platformOnly: true,
    prefetch: _prefetchOrgs,
  ),
  DashRoute(
    path: BranchesPage.path,
    builder: _branches,
    titleKey: 'nav.branches',
    titleFallback: 'Branches',
    prefetch: _prefetchBranches,
  ),
  // The branch builder (web `routes/_app/branch-setup.tsx`, ADM-BSU): no
  // route guard; the nav shows it for `kitchen.stations.edit`. No
  // `prefetchRoute` case on the web.
  DashRoute(
    path: BranchSetupPage.path,
    builder: _branchSetup,
    titleKey: 'nav.branchSetup',
    titleFallback: 'Branch setup',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: DevicesPage.path,
    builder: _devices,
    titleKey: 'nav.devices',
    titleFallback: 'Devices',
    module: OrgModule.pos,
    // The page's view and the clients window live in the URL.
    rememberQuery: ['view', 'days', 'all'],
  ),
  DashRoute(
    path: UsersPage.path,
    builder: _users,
    titleKey: 'nav.users',
    titleFallback: 'Users',
    prefetch: prefetchUsers,
  ),
  DashRoute(
    path: RolesPage.path,
    builder: _roles,
    titleKey: 'nav.rolesPermissions',
    titleFallback: 'Roles & Permissions',
    prefetch: prefetchRoles,
  ),
  DashRoute(
    path: ReviewPage.path,
    builder: _review,
    titleKey: 'access.review.title',
    titleFallback: 'Review',
    prefetch: _prefetchReview,
  ),
  DashRoute(
    path: OnboardingPage.path,
    builder: _onboarding,
    titleKey: 'onboarding.title',
    titleFallback: 'Let\'s open your café',
  ),
];

/// No web `prefetchRoute` case: resting on the Access "Review" tab warms the
/// open flags the page mounts with (ADM-REV-001 intent).
void _prefetchReview(DashPrefetcher warm, Scope s) =>
    warm(reviewFlagsProvider(false));

/// The web's `prefetchRoute('/orgs')`.
void _prefetchOrgs(DashPrefetcher warm, Scope s) => warm(orgsListProvider);

/// The web's `prefetchRoute('/branches')`: the org's branches (core's
/// `branchesProvider`, the page's read).
void _prefetchBranches(DashPrefetcher warm, Scope s) {
  if (s.orgId != null) warm(branchesProvider);
}
