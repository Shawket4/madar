/// The web's 401 funnel (`data/api/client.ts` + `auth.store.ts`): a 401 on an
/// authenticated request while signed in ends the session — exactly once,
/// however many requests failed together — and the router then sends the
/// person to sign-in with the page to come back to.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/src/authz/authz_providers.dart';
import 'package:dashboard_core/src/data/offline.dart';
import 'package:dashboard_core/src/data/query_cache.dart';
import 'package:dashboard_core/src/providers.dart';
import 'package:dashboard_core/src/scope/scope.dart';
import 'package:dashboard_core/src/session/session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The transport every boot puts over the network one (the core's in real
/// mode, the mock server's otherwise): the offline seam ([OfflineTransport],
/// when [offlineStoreProvider] holds a store) inside the 401 funnel, its
/// reads counted for a manual refresh ([QueryCache.refetchActive]).
///
/// ```dart
/// transportProvider.overrideWith((ref) => dashTransport(ref, network)),
/// ```
ApiTransport dashTransport(Ref ref, ApiTransport network) {
  final store = ref.watch(offlineStoreProvider);
  final cache = ref.read(queryCacheProvider);
  var inner = network;
  if (store != null) {
    final offline = OfflineTransport(
      network,
      store: store,
      host: RefOfflineHost(ref),
    );
    inner = offline;
    // A realtime nudge: what was read live may have changed.
    final sub = ref
        .read(realtimeBusProvider)
        .invalidations
        .listen((_) => offline.forgetRecent());
    ref.onDispose(sub.cancel);
    // A refresh by hand reads everything live.
    cache.onRefetch = offline.forgetRecent;
    // Back online: the shell's own reads built on saved data are read again
    // (a page's reads follow `webCache`).
    ref.listen(offlineProvider.select((s) => s.recoveries), (_, _) {
      // Through the container: these are built on this transport.
      ref.container
        ..invalidate(branchesProvider)
        ..invalidate(currentOrgProvider)
        ..invalidate(orgsProvider)
        ..invalidate(orgModulesQueryProvider)
        ..invalidate(onboardingCompletedProvider);
      unawaited(ref.container.read(authzProvider.notifier).refresh());
      ref.container.read(realtimeBusProvider).invalidate(const ['/']);
    });
  }
  return cache.track(
    SessionGuardTransport(
      inner,
      onUnauthorized: () =>
          ref.read(sessionProvider.notifier).handleUnauthorized(),
      signedIn: () => ref.read(currentSessionProvider) != null,
    ),
  );
}

/// Wraps [inner]; calls [onUnauthorized] for a 401 the session should end on.
class SessionGuardTransport implements ApiTransport {
  SessionGuardTransport(
    this.inner, {
    required this.onUnauthorized,
    required this.signedIn,
  });

  final ApiTransport inner;
  final void Function() onUnauthorized;

  /// Whether a session is held (a tokenless request's 401 is not ours).
  final bool Function() signedIn;

  /// Only a request that carried the session, to an authenticated endpoint:
  /// a public page's 401 (a guest token) never signs the operator out, and a
  /// refused sign-in is the sign-in form's to word.
  static bool endsSession(ApiRequest r, Object error) =>
      error is ApiException &&
      error.status == 401 &&
      !r.path.contains('/public/') &&
      !r.path.startsWith('/auth/login');

  void _check(ApiRequest r, Object e) {
    if (endsSession(r, e) && signedIn()) onUnauthorized();
  }

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    try {
      return await inner.send(request);
    } on Object catch (e) {
      _check(request, e);
      rethrow;
    }
  }

  @override
  Stream<String> stream(ApiRequest request) => inner
      .stream(request)
      .transform(
        StreamTransformer<String, String>.fromHandlers(
          handleError: (e, st, sink) {
            _check(request, e);
            sink.addError(e, st);
          },
        ),
      );
}
