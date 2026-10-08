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

import 'branches/branches_page.dart';
import 'devices/devices_page.dart';
import 'onboarding/onboarding_page.dart';
import 'orgs/orgs_page.dart';
import 'review/review_page.dart';
import 'roles/roles_page.dart';
import 'users/users_page.dart';

Widget _orgs(BuildContext context, GoRouterState state) => const OrgsPage();

Widget _branches(BuildContext context, GoRouterState state) =>
    const BranchesPage();

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
  ),
  DashRoute(
    path: BranchesPage.path,
    builder: _branches,
    titleKey: 'nav.branches',
    titleFallback: 'Branches',
  ),
  DashRoute(
    path: DevicesPage.path,
    builder: _devices,
    titleKey: 'nav.devices',
    titleFallback: 'Devices',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: UsersPage.path,
    builder: _users,
    titleKey: 'nav.users',
    titleFallback: 'Users',
  ),
  DashRoute(
    path: RolesPage.path,
    builder: _roles,
    titleKey: 'nav.rolesPermissions',
    titleFallback: 'Roles & Permissions',
  ),
  DashRoute(
    path: ReviewPage.path,
    builder: _review,
    titleKey: 'access.review.title',
    titleFallback: 'Review',
  ),
  DashRoute(
    path: OnboardingPage.path,
    builder: _onboarding,
    titleKey: 'onboarding.title',
    titleFallback: 'Let\'s open your café',
  ),
];
