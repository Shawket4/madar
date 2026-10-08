/// The Access section's tabs (the web's `routes/_app/access/route.tsx`),
/// under the title of the Users, Roles & Permissions and Review pages and on
/// their refusal screens (ADM-USR-001, ADM-ROL-001, ADM-REV-001): Users,
/// Roles & Permissions, and Review only for whoever holds
/// `approvals.review`. Switching keeps only the scope params.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'url_params.dart';

/// The Access section's paths, in tab order.
abstract final class AccessPaths {
  static const String users = '/access/users';
  static const String roles = '/access/roles';
  static const String review = '/access/review';
}

/// The tabs this person sees.
List<DashSectionTab> accessTabs(Translator t, Authz authz) => [
  DashSectionTab(path: AccessPaths.users, label: t('nav.users')),
  DashSectionTab(path: AccessPaths.roles, label: t('nav.rolesPermissions')),
  if (authz.can(Cap.approvalsReview))
    DashSectionTab(path: AccessPaths.review, label: t('access.review.title')),
];

class AccessSectionTabs extends ConsumerWidget {
  const AccessSectionTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final authz = ref.watch(authzProvider);
    final uri = context.pageUri;
    return DashSectionTabs(
      tabs: accessTabs(t, authz),
      currentPath: uri.path,
      onNavigate: (path) {
        if (path == uri.path) return;
        GoRouter.of(context).go(scopedLocation(path, uri));
      },
    );
  }
}
