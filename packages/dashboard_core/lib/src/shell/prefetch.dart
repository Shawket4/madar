/// Warming a page before it opens: the web's `useRoutePrefetch`, fired by a
/// sidebar or palette row's `onMouseEnter` / `onFocus`.
library;

import 'package:dashboard_core/src/data/query_cache.dart';
import 'package:dashboard_core/src/routes/nav.dart';
import 'package:dashboard_core/src/routes/route.dart';
import 'package:dashboard_core/src/scope/scope.dart';
import 'package:dashboard_core/src/shell/router.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashIntent;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every route's [DashRoute.prefetch], by its full path.
final routePrefetchesProvider = Provider<Map<String, DashPrefetch>>(
  (ref) => {
    for (final (path, r) in flattenRoutes(ref.watch(dashAreasProvider)))
      path: ?r.prefetch,
  },
);

extension DashRoutePrefetch on WidgetRef {
  /// Warms the page at [to] (its route's [DashRoute.prefetch]) for the scope
  /// in force: a link, a card, a tab that opens another page, on intent
  /// (`onIntent: () => ref.prefetchRoute('/orders')`). A legacy path warms
  /// the page it lands on.
  void prefetchRoute(String to) {
    final uri = Uri.parse(to);
    final path = normalizePath((resolveLegacyRedirect(uri) ?? uri).path);
    final prefetch = read(routePrefetchesProvider)[path];
    if (prefetch == null) return;
    prefetch(
      DashPrefetcher(ProviderScope.containerOf(context, listen: false)),
      read(currentScopeProvider),
    );
  }
}

/// Warms [to]'s page when someone is about to open it ([DashIntent]: the
/// pointer resting on [child], focus landing in it, a touch going down).
class PrefetchOnIntent extends ConsumerWidget {
  const PrefetchOnIntent({required this.to, required this.child, super.key});

  final String to;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      DashIntent(onIntent: () => ref.prefetchRoute(to), child: child);
}
