/// The web's React Query defaults (MadarDashboard `src/data/api/query.ts`) for
/// the Riverpod reads every page is built on.
///
/// The cache key is the provider and its family argument (the scope, the
/// period, the filters), as the web's is the request's URL and params; one
/// argument's data is never shown for another. The org in scope is part of it
/// too: the server reads a platform admin's org from the `X-Org-Id` header,
/// so a read with no org in its argument would otherwise outlive an org
/// switch (on the web it does, until stale: see the divergence log).
library;

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_core/src/scope/scope.dart' show orgIdProvider;
import 'package:dashboard_core/src/session/session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

/// The web's `staleTime`: younger data is shown as it is, older data is shown
/// and refetched in the background.
const kQueryStaleTime = Duration(seconds: 30);

/// The web's `gcTime`: how long a read nobody watches is kept.
const kQueryGcTime = Duration(minutes: 5);

extension WebQueryCache on Ref {
  /// Call first in an autoDispose read. The read then behaves like a web
  /// query:
  /// - kept [kQueryGcTime] after its last listener leaves, so a page opened
  ///   again (or warmed by [DashPrefetcher]) shows its data at once;
  /// - a page opening on it after [kQueryStaleTime] refreshes it in the
  ///   background, the old data on screen meanwhile;
  /// - signing out drops it ([QueryCache.clear], the web's
  ///   `queryClient.clear()` in `signOut`).
  void webCache() {
    watch(orgIdProvider);
    final now = read(clockProvider);
    final gc = read(queryCacheProvider);
    final builtAt = now();
    final link = keepAlive();
    gc._kept.add(link);
    // A warmed read may never be watched: it starts idle.
    gc.idle(link, now);
    // A page opening on stale data refetches it (`refetchOnMount`); not
    // inside the listener's own build, on the next turn.
    onAddListener(() {
      gc.busy(link);
      if (now().difference(builtAt) < kQueryStaleTime) return;
      Future.microtask(() {
        if (mounted) invalidateSelf();
      });
    });
    onCancel(() {
      if (gc._kept.contains(link)) gc.idle(link, now);
    });
    onDispose(() {
      gc.busy(link);
      gc._kept.remove(link);
    });
  }
}

/// Every kept read. Unwatched ones are swept once older than [kQueryGcTime];
/// no timer: a sweep runs whenever a read is built or let go, so nothing is
/// left pending (the widget tests' rule) and memory stays bounded by use.
class QueryCache {
  final _kept = <KeepAliveLink>{};
  final _idle = <KeepAliveLink, DateTime>{};

  /// Let every kept read go: an unwatched one is gone at once, a watched
  /// one when its page closes (a sign-out closes them all). Never reloaded
  /// in place, which would show the last person's data meanwhile.
  void clear() {
    final links = [..._kept];
    _kept.clear();
    _idle.clear();
    for (final l in links) {
      l.close();
    }
  }

  void idle(KeepAliveLink link, DateTime Function() now) {
    final at = now();
    _idle[link] = at;
    final cutoff = at.subtract(kQueryGcTime);
    final expired = [
      for (final e in _idle.entries)
        if (!e.value.isAfter(cutoff)) e.key,
    ];
    for (final l in expired) {
      _idle.remove(l);
      _kept.remove(l);
      l.close();
    }
  }

  void busy(KeepAliveLink link) => _idle.remove(link);
}

final queryCacheProvider = Provider<QueryCache>((ref) => QueryCache());

/// The web's retry policy (`queryRetry` / `queryRetryDelay`): never an auth or
/// client refusal; a 429 up to three times (2 s, 4 s, 8 s); anything else once.
Duration? webRetry(int retryCount, Object error) {
  if (error is ApiException) {
    final s = error.status;
    if (s == 401 || s == 403 || s == 404 || s == 422) return null;
    if (s == 429) {
      return retryCount < 3 ? Duration(seconds: 2 << retryCount) : null;
    }
  }
  if (retryCount >= 1) return null;
  final ms = 1000 << retryCount;
  return Duration(milliseconds: ms > 30000 ? 30000 : ms);
}

/// Warms the reads a page fires on mount (the web's `prefetchRoute`), from a
/// sidebar or palette row under the pointer or in focus.
class DashPrefetcher {
  DashPrefetcher(this._container);

  final ProviderContainer _container;

  /// Start [provider] (a read using [WebQueryCache.webCache], with the exact
  /// argument the page passes). A failure leaves nothing cached, so the page
  /// fetches again when it opens.
  void call<T>(FutureProvider<T> provider) {
    _container
        .read(provider.future)
        .then<void>(
          (_) {},
          onError: (Object _) => _container.invalidate(provider),
        );
  }
}
