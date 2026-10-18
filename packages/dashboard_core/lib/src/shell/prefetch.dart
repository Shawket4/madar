/// Warming a page before it opens: the web's `useRoutePrefetch`, fired on
/// intent (a resting pointer, focus, a touch going down) by every kit control
/// given a destination (`to:` on a tab, card, row, button or back arrow,
/// through [DashRouteIntent]) and by the sidebar and palette rows.
library;

import 'package:dashboard_core/src/data/query_cache.dart';
import 'package:dashboard_core/src/memory/list_memory.dart';
import 'package:dashboard_core/src/routes/nav.dart';
import 'package:dashboard_core/src/routes/route.dart';
import 'package:dashboard_core/src/scope/scope.dart';
import 'package:dashboard_core/src/session/session.dart' show clockProvider;
import 'package:dashboard_core/src/shell/router.dart';
import 'package:dashboard_kit/dashboard_kit.dart'
    show DashIntent, DashRouteIntent;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The same location (path, query, scope) is warmed at most once in this
/// window. A warm of fresh data makes no request anyway
/// ([DashPrefetcher]: the cache answers until [kQueryStaleTime]); this only
/// spares running the route's prefetch again for every hover and focus.
const kRoutePrefetchThrottle = Duration(seconds: 2);

/// One route's prefetch, matched by its full path ([flattenRoutes]): a
/// static path exactly, a templated one (`/orders/:orderId`) by segment.
@immutable
class RoutePrefetchEntry {
  RoutePrefetchEntry(this.path, this.route)
    : prefetch = route.prefetch!,
      _segments = _split(path),
      templated = path.contains(':');

  final String path;
  final DashRoute route;
  final DashPrefetch prefetch;
  final bool templated;
  final List<String> _segments;

  static List<String> _split(String p) => [
    for (final s in p.split('/'))
      if (s.isNotEmpty) s,
  ];

  /// [location]'s path parameters when it is this route, else null.
  Map<String, String>? match(String location) {
    final parts = _split(location);
    if (parts.length != _segments.length) return null;
    final params = <String, String>{};
    for (var i = 0; i < parts.length; i++) {
      final want = _segments[i];
      if (want.startsWith(':')) {
        params[want.substring(1)] = Uri.decodeComponent(parts[i]);
      } else if (want != parts[i]) {
        return null;
      }
    }
    return params;
  }
}

/// Every route's [DashRoute.prefetch], by its full path.
final routePrefetchesProvider = Provider<Map<String, DashPrefetch>>(
  (ref) => {
    for (final (path, r) in flattenRoutes(ref.watch(dashAreasProvider)))
      path: ?r.prefetch,
  },
);

/// The routes with a prefetch, static paths first (so `/menu/items/new`
/// wins over `/menu/items/:itemId`).
final _routePrefetchTableProvider = Provider<List<RoutePrefetchEntry>>((ref) {
  final all = [
    for (final (path, r) in flattenRoutes(ref.watch(dashAreasProvider)))
      if (r.prefetch != null) RoutePrefetchEntry(path, r),
  ];
  return [
    for (final e in all)
      if (!e.templated) e,
    for (final e in all)
      if (e.templated) e,
  ];
});

/// The query [uri] opens with: a page whose filters live in the URL
/// ([DashRoute.rememberQuery]), opened bare from elsewhere, gets back the
/// ones it last had (the router's [rememberedQueryRedirect]), so the warm
/// reads the key the page will. Nothing is remembered here.
Map<String, String> landingQuery(
  DashListMemory memory,
  DashRoute route,
  Uri uri, {
  Uri? from,
}) {
  final q = uri.queryParameters;
  final keys = route.rememberQuery;
  if (keys.isEmpty) return q;
  final path = normalizePath(uri.path);
  if (from != null && normalizePath(from.path) == path) return q;
  if (keys.any((k) => q[k]?.isNotEmpty ?? false)) return q;
  final saved = memory.recallQuery(path);
  if (saved == null) return q;
  return {
    ...q,
    for (final e in saved.query.entries)
      if (saved.sameBranch || !route.branchQuery.contains(e.key))
        e.key: e.value,
  };
}

/// The route prefetch for [location] (a legacy path resolved to the page it
/// lands on) with its path parameters, or null when it warms nothing.
(RoutePrefetchEntry, Map<String, String>)? matchRoutePrefetch(
  List<RoutePrefetchEntry> table,
  String path,
) {
  for (final e in table) {
    final params = e.match(path);
    if (params != null) return (e, params);
  }
  return null;
}

/// Warms the page at [to] for [scope] in [container]: its route's
/// [DashRoute.prefetch], with the location's path parameters and query.
/// Throttled per location and scope ([kRoutePrefetchThrottle]).
void prefetchRouteIn(ProviderContainer container, String to) {
  final uri = Uri.parse(to);
  final landed = resolveLegacyRedirect(uri) ?? uri;
  final path = normalizePath(landed.path);
  final hit = matchRoutePrefetch(
    container.read(_routePrefetchTableProvider),
    path,
  );
  if (hit == null) return;
  final (entry, params) = hit;
  var query = landed.queryParameters;
  if (entry.route.rememberQuery.isNotEmpty) {
    final config = container.read(dashRouterProvider).routerDelegate;
    query = landingQuery(
      container.read(dashListMemoryProvider),
      entry.route,
      landed,
      from: config.currentConfiguration.isEmpty
          ? null
          : config.currentConfiguration.uri,
    );
  }
  final scope = container.read(currentScopeProvider);
  final key = '$path?${Uri(queryParameters: query).query}|${scope.hashCode}';
  final now = container.read(clockProvider)();
  final cache = container.read(queryCacheProvider);
  if (!cache.admitWarm(key, now, kRoutePrefetchThrottle)) return;
  entry.prefetch(
    DashPrefetcher(container, params: params, query: query),
    scope,
  );
}

extension DashRoutePrefetch on WidgetRef {
  /// Warms the page at [to] (its route's [DashRoute.prefetch]) for the scope
  /// in force. A kit control given `to:` does this by itself on intent;
  /// call it by hand only where no kit control fits. A legacy path warms
  /// the page it lands on; a detail path (`/orders/abc`) its record.
  void prefetchRoute(String to) =>
      prefetchRouteIn(ProviderScope.containerOf(context, listen: false), to);
}

/// The shell's [DashRouteIntent]: every kit control with a destination warms
/// it through the route registry. [DashApp] installs it above the router.
class DashRoutePrefetchScope extends ConsumerWidget {
  const DashRoutePrefetchScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      DashRouteIntent(onRoute: ref.prefetchRoute, child: child);
}

/// Warms [to]'s page when someone is about to open it ([DashIntent]: the
/// pointer resting on [child], focus landing in it, a touch going down).
/// For a surface that is not a kit control (the sidebar's rows).
class PrefetchOnIntent extends StatelessWidget {
  const PrefetchOnIntent({required this.to, required this.child, super.key});

  final String to;
  final Widget child;

  @override
  Widget build(BuildContext context) => DashIntent(to: to, child: child);
}
