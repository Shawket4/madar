/// The dashboard's router (the web's TanStack route tree): sign-in outside
/// the frame, `/onboarding` full screen, every area's pages inside the frame
/// ([DashShell]), the legacy redirects, and the guards the web runs before a
/// page loads (`requireAuth`, the onboarding gate, a Dawam-only org's home).
library;

import 'dart:async';

import 'package:dashboard_core/src/authz/authz_providers.dart';
import 'package:dashboard_core/src/memory/list_memory.dart';
import 'package:dashboard_core/src/routes/nav.dart';
import 'package:dashboard_core/src/routes/route.dart';
import 'package:dashboard_core/src/scope/scope.dart';
import 'package:dashboard_core/src/session/session.dart';
import 'package:dashboard_core/src/shell/frame.dart';
import 'package:dashboard_core/src/shell/leave_guard.dart';
import 'package:dashboard_core/src/shell/pages.dart';
import 'package:dashboard_core/src/shell/sign_in.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashMotion;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The areas the app is built from (the app and the harness override it).
final dashAreasProvider = Provider<List<DashArea>>((ref) => const []);

/// Where the router starts (the harness opens a page directly).
final dashInitialLocationProvider = Provider<String>((ref) => '/');

/// The one router.
final dashRouterProvider = Provider<GoRouter>((ref) {
  final router = buildDashRouter(
    ref,
    areas: ref.watch(dashAreasProvider),
    initialLocation: ref.read(dashInitialLocationProvider),
  );
  ref.onDispose(router.dispose);
  return router;
});

/// The sign-in page's path.
const String signInPath = '/login';

/// Pages that are signed in but drawn without the frame (the web's
/// `routes/onboarding.tsx`).
const Set<String> fullScreenPaths = {'/onboarding'};

/// Whether the session is known yet.
enum SessionStatus { loading, signedOut, signedIn }

/// The redirect for [uri], the way the web decides before a page loads;
/// null = stay. Pure, so it is tested directly.
///
/// 1. A legacy path lands on the page that replaced it (with the query each
///    one keeps).
/// 2. Signed in, `/login` goes on to its `redirect` (else home).
/// 3. Nothing is decided while the session is still being restored.
/// 4. Signed out, every other page goes to `/login?redirect=<where>` (a
///    bare `/login` after the person signed out themselves).
/// 5. An owner whose POS set-up is unfinished goes to `/onboarding`.
/// 6. A Dawam-only org's home is its team (`/staff/team`).
String? dashRedirect({
  required Uri uri,
  required SessionStatus session,
  SignOutReason? signedOutBecause,
  bool toOnboarding = false,
  OrgModulesState modules = const OrgModulesState(),
}) {
  final legacy = resolveLegacyRedirect(uri);
  if (legacy != null) return legacy.toString();
  final path = normalizePath(uri.path);
  if (path == signInPath) {
    if (session != SessionStatus.signedIn) return null;
    return safeReturnPath(uri.queryParameters['redirect']) ?? '/';
  }
  if (session == SessionStatus.loading) return null;
  if (session == SessionStatus.signedOut) {
    // Signing out on purpose opens a bare sign-in (the web's user menu);
    // an expired or refused session keeps the page to come back to.
    if (signedOutBecause == SignOutReason.requested) return signInPath;
    return Uri(
      path: signInPath,
      queryParameters: {'redirect': uri.toString()},
    ).toString();
  }
  if (toOnboarding && !fullScreenPaths.contains(path)) return '/onboarding';
  if (path == '/' &&
      modules.known &&
      !modules.has('pos') &&
      modules.has('dawam')) {
    return '/staff/team';
  }
  return null;
}

/// A `redirect` value that is a page of this app (never another origin, never
/// the sign-in page itself).
String? safeReturnPath(String? value) {
  if (value == null || value.isEmpty) return null;
  if (!value.startsWith('/') || value.startsWith('//')) return null;
  final path = normalizePath(Uri.tryParse(value)?.path ?? '');
  if (path.isEmpty || path == signInPath) return null;
  return value;
}

/// The redirect that keeps a page's URL-held filters ([DashRoute.rememberQuery])
/// through navigation; null = stay. Pure over [memory], so it is tested
/// directly.
///
/// - Opened bare from another page ([from] is elsewhere): the filters it
///   last had come back (its branch-bound ones only in the same branch).
/// - On the page, with the branch changed under it: the branch-bound
///   filters go.
/// - Otherwise the filters shown are remembered (a Clear on the page is
///   remembered as no filter).
String? rememberedQueryRedirect({
  required DashListMemory memory,
  required DashRoute route,
  required Uri uri,
  Uri? from,
}) {
  final keys = route.rememberQuery;
  if (keys.isEmpty) return null;
  final path = normalizePath(uri.path);
  final shown = {
    for (final k in keys)
      if (uri.queryParameters[k] case final v? when v.isNotEmpty) k: v,
  };
  final entering = from == null || normalizePath(from.path) != path;
  final saved = memory.recallQuery(path);
  Uri withQuery(Map<String, String> q) =>
      Uri(path: uri.path, queryParameters: q.isEmpty ? null : q);
  if (entering && shown.isEmpty && saved != null) {
    final restore = {
      for (final e in saved.query.entries)
        if (saved.sameBranch || !route.branchQuery.contains(e.key))
          e.key: e.value,
    };
    if (restore.isNotEmpty) {
      return withQuery({...uri.queryParameters, ...restore}).toString();
    }
  }
  if (!entering && saved != null && !saved.sameBranch) {
    final stale = shown.keys.where(route.branchQuery.contains).toSet();
    if (stale.isNotEmpty) {
      return withQuery({
        for (final e in uri.queryParameters.entries)
          if (!stale.contains(e.key)) e.key: e.value,
      }).toString();
    }
  }
  memory.rememberQuery(path, shown);
  return null;
}

/// Re-runs the redirect when the session, the onboarding gate or the org's
/// modules change — after the change has settled (a redirect that read
/// providers while Riverpod was still rebuilding them would re-enter them).
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref
      ..listen(sessionProvider, (_, _) => _soon())
      ..listen(sendsToOnboardingProvider, (_, _) => _soon())
      ..listen(
        orgModulesProvider.select((m) => (m.known, m.modules.join(','))),
        (_, _) => _soon(),
      )
      // A page's branch-bound URL filters go with the branch.
      ..listen(scopeProvider.select((s) => s.branchId), (_, _) => _soon());
  }

  bool _queued = false;
  bool _disposed = false;

  void _soon() {
    if (_queued) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The router over [areas]' pages.
GoRouter buildDashRouter(
  Ref ref, {
  required List<DashArea> areas,
  String initialLocation = '/',
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  SessionStatus status() {
    final s = ref.read(sessionProvider);
    if (s.isLoading && !s.hasValue) return SessionStatus.loading;
    return s.value == null ? SessionStatus.signedOut : SessionStatus.signedIn;
  }

  // A page's "leave?" ([DashLeaveGuard]); signing out never asks.
  FutureOr<bool> leave(BuildContext _, GoRouterState state) =>
      status() == SessionStatus.signedIn
      ? ref.read(dashLeaveGuardsProvider).leave(state.pageKey)
      : true;

  late final GoRouter router;
  // Where the person is (before the navigation being decided).
  String? remember(DashRoute r, GoRouterState state) =>
      status() == SessionStatus.signedIn
      ? rememberedQueryRedirect(
          memory: ref.read(dashListMemoryProvider),
          route: r,
          uri: state.uri,
          from: router.routerDelegate.currentConfiguration.isEmpty
              ? null
              : router.routerDelegate.currentConfiguration.uri,
        )
      : null;

  final framed = <RouteBase>[];
  final fullScreen = <RouteBase>[];
  for (final area in areas) {
    for (final r in area.routes) {
      (fullScreenPaths.contains(r.path) ? fullScreen : framed).add(
        _goRoute(
          r,
          framed: !fullScreenPaths.contains(r.path),
          onExit: leave,
          remember: remember,
        ),
      );
    }
  }

  return router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: initialLocation,
    refreshListenable: refresh,
    redirect: (context, state) => dashRedirect(
      uri: state.uri,
      session: status(),
      signedOutBecause: ref.read(sessionProvider.notifier).lastSignOutReason,
      toOnboarding: ref.read(sendsToOnboardingProvider),
      modules: ref.read(orgModulesProvider),
    ),
    errorPageBuilder: (context, state) => _fadePage(
      context,
      state,
      DashShell(state: state, child: const DashNotFoundPage()),
    ),
    routes: [
      GoRoute(
        path: signInPath,
        pageBuilder: (context, state) =>
            _fadePage(context, state, const DashSignInPage()),
      ),
      ...fullScreen,
      if (framed.isNotEmpty)
        ShellRoute(
          builder: (context, state, child) =>
              DashShell(state: state, child: child),
          routes: framed,
        ),
    ],
  );
}

GoRoute _goRoute(
  DashRoute r, {
  required bool framed,
  required ExitCallback onExit,
  required String? Function(DashRoute r, GoRouterState state) remember,
}) {
  final redirect = r.redirect;
  return GoRoute(
    path: r.path,
    redirect: redirect == null && r.rememberQuery.isEmpty
        ? null
        : (c, s) => redirect?.call(c, s) ?? remember(r, s),
    onExit: onExit,
    pageBuilder: (context, state) => _fadePage(
      context,
      state,
      DashRouteHost(route: r, state: state, framed: framed),
    ),
    routes: [
      for (final c in r.children)
        _goRoute(c, framed: framed, onExit: onExit, remember: remember),
    ],
  );
}

/// A page that cross-fades with the one it replaces (the web's view
/// transition); instant under reduced motion.
Page<void> _fadePage(BuildContext context, GoRouterState state, Widget child) {
  final d = DashMotion.of(context, DashMotion.base);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: d,
    reverseTransitionDuration: d,
    transitionsBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    child: child,
  );
}
