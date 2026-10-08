/// Warming a page before it opens: the web's `useRoutePrefetch`, fired by a
/// sidebar or palette row's `onMouseEnter` / `onFocus`.
library;

import 'package:dashboard_core/src/data/query_cache.dart';
import 'package:dashboard_core/src/routes/route.dart';
import 'package:dashboard_core/src/scope/scope.dart';
import 'package:dashboard_core/src/shell/router.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every route's [DashRoute.prefetch], by its full path.
final routePrefetchesProvider = Provider<Map<String, DashPrefetch>>(
  (ref) => {
    for (final (path, r) in flattenRoutes(ref.watch(dashAreasProvider)))
      path: ?r.prefetch,
  },
);

/// Warms [to]'s page when the pointer enters [child] or focus lands in it.
class PrefetchOnIntent extends ConsumerWidget {
  const PrefetchOnIntent({required this.to, required this.child, super.key});

  final String to;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void warm() {
      final prefetch = ref.read(routePrefetchesProvider)[to];
      if (prefetch == null) return;
      prefetch(
        DashPrefetcher(ProviderScope.containerOf(context, listen: false)),
        ref.read(currentScopeProvider),
      );
    }

    return MouseRegion(
      onEnter: (_) => warm(),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          if (focused) warm();
        },
        child: child,
      ),
    );
  }
}
