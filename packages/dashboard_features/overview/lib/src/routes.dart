/// The overview area's pages (`/`) with the web's capabilities (any-of, from
/// the generated nav and settings nav) and module.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'home/home_page.dart';
import 'home/home_providers.dart';

const List<DashRoute> overviewRoutes = [
  DashRoute(
    path: '/',
    builder: _home,
    titleKey: 'nav.dashboard',
    titleFallback: 'Dashboard',
    module: OrgModule.pos,
    prefetch: _prefetchHome,
  ),
];

Widget _home(BuildContext context, GoRouterState state) => const HomeRoute();

/// The web's `prefetchRoute('/')`: the branch's sales when one is picked, the
/// org's trend and branch comparison when an org is in scope (`HomeData`).
void _prefetchHome(DashPrefetcher warm, Scope s) {
  if (s.branchId != null) warm(homeBranchSalesProvider(s));
  if (s.orgId != null) {
    warm(homeTimeseriesProvider(s));
    warm(homeComparisonProvider(s));
  }
}
