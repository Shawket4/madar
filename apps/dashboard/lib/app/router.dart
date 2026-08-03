import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/nav.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/placeholder/coming_soon_screen.dart';
import 'providers.dart';
import 'shell.dart';

/// The app router. Auth-gated: unauthenticated → `/login`; the whole
/// authenticated area is wrapped in [AppShell]. Rebuilds redirect whenever the
/// session changes.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    refreshListenable: refresh,
    initialLocation: '/',
    redirect: (context, state) {
      final signedIn = ref.read(sessionProvider) != null;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn) return atLogin ? null : '/login';
      if (atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
          // Phase 2+: every other nav destination resolves to a placeholder so
          // the sidebar is fully navigable today.
          ..._placeholderRoutes(),
        ],
      ),
    ],
  );
});

/// One `ComingSoonScreen` route per nav leaf that isn't the dashboard root.
List<GoRoute> _placeholderRoutes() {
  final routes = <GoRoute>[];
  for (final group in kNav) {
    for (final entry in group.entries) {
      switch (entry) {
        case NavLeaf(:final path, :final labelKey, :final fallback):
          if (path == '/') continue;
          routes.add(
            GoRoute(
              path: path,
              builder: (_, _) =>
                  ComingSoonScreen(titleKey: labelKey, fallback: fallback),
            ),
          );
        case NavParent(:final children):
          for (final leaf in children) {
            routes.add(
              GoRoute(
                path: leaf.path,
                builder: (_, _) => ComingSoonScreen(
                  titleKey: leaf.labelKey,
                  fallback: leaf.fallback,
                ),
              ),
            );
          }
      }
    }
  }
  return routes;
}
