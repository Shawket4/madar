/// The overview area's pages (`/`, `/setup`, and `/onboarding` from old
/// links landing on Setup) with the web's capabilities (any-of, from the
/// generated nav and settings nav) and module.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'home/home_page.dart';
import 'home/home_providers.dart';
import 'setup/checks.dart';
import 'setup/setup_page.dart';

const List<DashRoute> overviewRoutes = [
  DashRoute(
    path: '/',
    builder: _home,
    titleKey: 'nav.dashboard',
    titleFallback: 'Dashboard',
    module: OrgModule.pos,
    prefetch: _prefetchHome,
  ),
  // No module: a Dawam-only org is told there is nothing to set up for the
  // till.
  DashRoute(
    path: SetupPage.path,
    builder: _setup,
    titleKey: 'setup.title',
    titleFallback: 'Set up your shop',
    caps: [Cap.orgSettingsRead],
    prefetch: _prefetchSetup,
  ),
  // The full-screen wizard is gone; its old links open Setup.
  DashRoute(path: '/onboarding', redirect: _toSetup),
];

Widget _setup(BuildContext context, GoRouterState state) => const SetupPage();

String? _toSetup(BuildContext context, GoRouterState state) => SetupPage.path;

void _prefetchSetup(DashPrefetcher warm, Scope s) {
  if (s.orgId case final org?) warm(readinessProvider(org));
}

Widget _home(BuildContext context, GoRouterState state) => const HomeRoute();

/// The web's `prefetchRoute('/')`: the branch's sales and open tills when
/// one is picked; the org's trend, branch comparison, margin watch and
/// delivery sales when an org is in scope (`HomeData` and the cards'
/// own reads, with the keys they watch).
void _prefetchHome(DashPrefetcher warm, Scope s) {
  final b = s.branchId;
  if (b != null) {
    warm(homeBranchSalesProvider(s.branchRange));
    warm(homeOpenTillsProvider(b));
  }
  if (s.orgId != null) {
    warm(homeTimeseriesProvider(s.series));
    warm(homeComparisonProvider(s.orgRange));
    warm(homeMarginWatchProvider(s.scopeRange));
    warm(homeDeliveryProvider(s.scopeRange));
    if (warm.read(authzProvider).can(Cap.orgSettingsEdit)) {
      warm(readinessProvider(s.orgId!));
    }
  }
}
