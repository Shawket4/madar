import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/home/home_screen.dart';
import '../features/manager/approvals_screen.dart';
import '../features/manager/payroll_screen.dart';
import '../features/manager/roster_screen.dart';
import '../features/manager/team_screen.dart';
import '../features/payslips/payslips_screen.dart';
import '../features/requests/requests_screen.dart';
import '../features/shifts/shifts_screen.dart';
import '../features/timesheet/timesheet_screen.dart';
import 'providers.dart';
import 'shell.dart';

/// The app router. Auth-gated: unauthenticated → `/login`; the whole
/// authenticated area is wrapped in [AppShell]. Rebuilds redirect whenever the
/// session or the manager toggle changes.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.listen(managerModeProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  /// The manager's four routes. Reachable only while the toggle is on AND the
  /// permission is held — but the SERVER is the real gate, and every one of
  /// these screens shows what it is allowed to show and nothing more.
  const managerRoutes = {'/team', '/approvals', '/roster', '/payroll'};

  return GoRouter(
    refreshListenable: refresh,
    initialLocation: '/',
    redirect: (context, state) {
      final signedIn = ref.read(sessionProvider) != null;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn) return atLogin ? null : '/login';
      if (atLogin) return '/';

      // Switching sides moves you to that side's first tab rather than
      // leaving you on a screen the other bar cannot navigate back to.
      final managing = ref.read(managerModeProvider);
      final onManagerRoute = managerRoutes.contains(state.matchedLocation);
      if (managing && !onManagerRoute) return '/team';
      if (!managing && onManagerRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          // Employee.
          GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
          GoRoute(
            path: '/timesheet',
            builder: (_, _) => const TimesheetScreen(),
          ),
          GoRoute(path: '/shifts', builder: (_, _) => const ShiftsScreen()),
          GoRoute(path: '/requests', builder: (_, _) => const RequestsScreen()),
          GoRoute(path: '/payslips', builder: (_, _) => const PayslipsScreen()),
          // Manager.
          GoRoute(path: '/team', builder: (_, _) => const TeamScreen()),
          GoRoute(
            path: '/approvals',
            builder: (_, _) => const ApprovalsScreen(),
          ),
          GoRoute(path: '/roster', builder: (_, _) => const RosterScreen()),
          GoRoute(path: '/payroll', builder: (_, _) => const PayrollScreen()),
        ],
      ),
    ],
  );
});
