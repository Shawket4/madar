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

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, ApiRequest, ApiResponse, ApiTransport;
import 'package:dashboard_core/src/data/offline.dart' show offlineProvider;
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
  ///
  /// [staleTime] is the query's own `staleTime` where the web sets one.
  void webCache({Duration staleTime = kQueryStaleTime}) {
    watch(orgIdProvider);
    // Back online after data came from disk: read again.
    watch(offlineProvider.select((s) => s.recoveries));
    final now = read(clockProvider);
    final gc = read(queryCacheProvider);
    final builtAt = now();
    final link = keepAlive();
    gc._kept.add(link);
    gc._reads[link] = this;
    // A warmed read may never be watched: it starts idle.
    gc.idle(link, now);
    // flutter_riverpod closes a widget's `ref.listen` subscriptions before
    // each build and adds them back during it, while its `ref.watch` stays:
    // a listener added in the same turn as a removal, with the read still
    // watched, is that rebuild re-listening, not a new mount.
    var listeners = 0;
    var removedThisTurn = false;
    onRemoveListener(() {
      listeners--;
      removedThisTurn = true;
      scheduleMicrotask(() => removedThisTurn = false);
    });
    // A page opening on stale data refetches it (`refetchOnMount`); not
    // inside the listener's own build, on the next turn.
    onAddListener(() {
      gc.busy(link);
      final relisten = removedThisTurn && listeners > 0;
      listeners++;
      if (relisten) return;
      if (now().difference(builtAt) < staleTime) return;
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
      gc._reads.remove(link);
    });
  }
}

/// Every kept read. Unwatched ones are swept once older than [kQueryGcTime];
/// no timer: a sweep runs whenever a read is built or let go, so nothing is
/// left pending (the widget tests' rule) and memory stays bounded by use.
class QueryCache {
  final _kept = <KeepAliveLink>{};
  final _idle = <KeepAliveLink, DateTime>{};

  /// Each read's current build, to fetch it again by hand.
  final _reads = <KeepAliveLink, Ref>{};

  /// Runs as [refetchActive] starts: the offline seam forgets the live
  /// answers it would narrow, so everything comes from the server.
  void Function()? onRefetch;

  int _reading = 0;
  Completer<void>? _quiet;
  List<Object>? _failures;

  /// The web's `refetchQueries({type: 'active'})`, by hand (pull to refresh,
  /// Cmd/Ctrl+R, back online): every read a shown page watches is fetched
  /// again, fresh or not, its data on screen meanwhile; a read nobody shows
  /// is left alone. Resolves once the reads it set off (and any they chain)
  /// have landed, with the first failure, or null.
  Future<Object?> refetchActive() async {
    final active = [
      for (final r in _reads.values)
        if (r.mounted && !r.isPaused) r,
    ];
    if (active.isEmpty) return null;
    onRefetch?.call();
    final failures = _failures = [];
    try {
      final container = active.first.container;
      for (final r in active) {
        r.invalidateSelf();
      }
      await container.pump();
      // A read that awaits another starts its request a turn later.
      do {
        while (_reading > 0) {
          await (_quiet ??= Completer<void>()).future;
        }
        await Future<void>.delayed(Duration.zero);
      } while (_reading > 0);
      return failures.firstOrNull;
    } finally {
      if (identical(_failures, failures)) _failures = null;
    }
  }

  /// [inner] with its reads counted, so [refetchActive] knows when the
  /// reads it set off have landed (the boot's transport, `dashTransport`).
  ApiTransport track(ApiTransport inner) => _CountedReads(inner, this);

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

class _CountedReads implements ApiTransport {
  _CountedReads(this.inner, this.cache);

  final ApiTransport inner;
  final QueryCache cache;

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    if (request.method.toUpperCase() != 'GET') return inner.send(request);
    cache._reading++;
    try {
      return await inner.send(request);
    } on Object catch (e) {
      cache._failures?.add(e);
      rethrow;
    } finally {
      if (--cache._reading == 0) {
        cache._quiet?.complete();
        cache._quiet = null;
      }
    }
  }

  @override
  Stream<String> stream(ApiRequest request) => inner.stream(request);
}

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

/// Warming a read from a control's intent hook (`onIntent`, `onRowIntent`,
/// `onPageIntent`…): the read the press will make, with its exact key, so
/// the press answers from the cache.
///
/// ```dart
/// onRowIntent: (o) => ref.warm(orderDetailProvider(o.id)),
/// ```
extension DashWarm on WidgetRef {
  void warm<T>(FutureProvider<T> provider) => DashPrefetcher(
    ProviderScope.containerOf(context, listen: false),
  )(provider);
}
