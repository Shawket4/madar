/// Working with no network (the owner's requirement): even fully closed and
/// relaunched offline, the dashboard shows the latest data it has, says it
/// is offline and that the data may be out of date; with a network,
/// everything goes to the server as before.
///
/// All of it sits at the transport ([OfflineTransport]), so no page changes.
/// What is kept, under which key, and what a narrower range is are the
/// core's (madar-core `api_cache`, in its SQLite store, through
/// [OfflineCache]); this file only routes:
/// - every successful GET body is offered to the core, which keeps the ones
///   it may (keyed by the person, the org and branch in scope and the
///   request);
/// - online, a saved body is never shown in place of a live answer. The one
///   local answer online is a narrower date range the core derives exactly
///   from a wider answer read live less than [kQueryStaleTime] ago, as a
///   fresh cache hit;
/// - offline (the request never reached the server: [isOfflineError]), the
///   saved body for that request, or one derived from a saved wider range,
///   whichever was saved later, answers it, and the shell's banner shows
///   ([offlineProvider]); with nothing saved the offline error stands;
/// - a write offline fails at once, in words that say so; nothing is queued;
/// - the next answer from the server clears the banner and reads again
///   everything that was built on saved data.
library;

import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/src/data/query_cache.dart' show kQueryStaleTime;
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/scope/scope.dart';
import 'package:dashboard_core/src/session/session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart'
    show ApiPair, CacheRequest, CacheScope, CachedAnswer, OfflineCache;

export 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart'
    show CacheScope, OfflineCache;

/// The saved answers; null = nothing is saved and nothing is served from
/// disk (tests that do not ask for it). The boots open one: the core's own
/// store in real mode, one in memory in mock mode.
final offlineCacheProvider = Provider<OfflineCache?>((ref) => null);

/// [OfflineCache.inMemory] with the dashboard's stale time.
OfflineCache memoryOfflineCache() =>
    OfflineCache.inMemory(freshMs: kQueryStaleTime.inMilliseconds);

/// What the shell's banner reads.
class OfflineState {
  const OfflineState({this.savedAt, this.recoveries = 0});

  /// The oldest saved-at among the answers shown from disk since the server
  /// last answered; null while everything shown is live.
  final DateTime? savedAt;

  /// Bumps each time the server answers again after data came from disk:
  /// every read built on saved data is read again (`webCache` watches it).
  final int recoveries;

  bool get showing => savedAt != null;
}

class OfflineNotifier extends Notifier<OfflineState> {
  @override
  OfflineState build() {
    // A new person starts with nothing shown from disk.
    ref.watch(currentSessionProvider.select((s) => s?.user.id));
    return const OfflineState();
  }

  /// An answer from disk saved at [at] is being shown.
  void showedSaved(DateTime at) {
    final s = state.savedAt;
    if (s != null && !at.isBefore(s)) return;
    state = OfflineState(savedAt: at, recoveries: state.recoveries);
  }

  /// The server answered.
  void reachedServer() {
    if (!state.showing) return;
    state = OfflineState(recoveries: state.recoveries + 1);
  }
}

final offlineProvider = NotifierProvider<OfflineNotifier, OfflineState>(
  OfflineNotifier.new,
);

/// What [OfflineTransport] needs from the app.
abstract interface class OfflineHost {
  /// Who is asking, as far as the server's answer depends on it: the
  /// person, the org and the branch picked in the scope bar (null: every
  /// branch; the header the server reads is a function of it and the
  /// person, so this is never coarser). Null when nobody is signed in:
  /// nothing is saved or served.
  CacheScope? get scope;

  DateTime now();

  /// The zone the server cuts days in for [branchId] (null: every branch,
  /// the org's); null when not known for certain.
  String? zoneFor(String? branchId);

  /// "You're offline, so this can't be saved."
  String get cantSaveWords;

  void showedSaved(DateTime savedAt);

  void reachedServer();
}

/// [OfflineHost] over the provider container. It reads through
/// `ref.container`: the scope and branches are built on the transport, so a
/// `ref.read` from the transport's own ref is a circular dependency.
class RefOfflineHost implements OfflineHost {
  const RefOfflineHost(this.ref);

  final Ref ref;

  @override
  CacheScope? get scope {
    final session = ref.container.read(currentSessionProvider);
    if (session == null) return null;
    return CacheScope(
      user: session.user.id,
      org: ref.container.read(orgIdProvider),
      branch: ref.container.read(scopeProvider).branchId,
    );
  }

  @override
  DateTime now() => ref.container.read(clockProvider)();

  @override
  String? zoneFor(String? branchId) {
    if (branchId == null) {
      return ref.container.read(currentOrgProvider).value?.timezone;
    }
    for (final b
        in ref.container.read(branchesProvider).value ?? const <Branch>[]) {
      // `Branch.timezone` is the effective zone (branch → org → Cairo), the
      // one the server buckets in.
      if (b.id == branchId) return b.timezone;
    }
    return null;
  }

  @override
  String get cantSaveWords =>
      ref.container.read(tProvider)('shell.offlineCantSave');

  @override
  void showedSaved(DateTime savedAt) =>
      ref.container.read(offlineProvider.notifier).showedSaved(savedAt);

  @override
  void reachedServer() =>
      ref.container.read(offlineProvider.notifier).reachedServer();
}

/// A failure that never reached the Madar server: no network (the core's
/// `Offline`, status 0), a captive portal, or a 403 without the backend's
/// `{"error": …}` envelope (a firewall answering in its place).
bool isOfflineError(Object e) =>
    e is ApiException &&
    (e.status == 0 || (e.status == 403 && !_hasEnvelope(e.details)));

bool _hasEnvelope(Object? details) =>
    details is Map && details['error'] is String;

/// The offline seam over the network transport; see the library comment.
class OfflineTransport implements ApiTransport {
  OfflineTransport(this.inner, {required this.cache, required this.host});

  final ApiTransport inner;

  /// Null: a plain pass-through.
  final OfflineCache? cache;
  final OfflineHost host;

  /// What was read may have changed (a write, a realtime nudge): nothing
  /// held so far answers for another range.
  void forgetRecent() => cache?.forgetRecent();

  @override
  Stream<String> stream(ApiRequest request) => inner.stream(request);

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    final cache = this.cache;
    if (cache == null) return inner.send(request);
    // Never inside a provider's synchronous build: the host reads providers.
    await null;
    if (request.method.toUpperCase() != 'GET') return _write(request);
    final scope = host.scope;
    if (scope == null) return _plain(request);
    final call = _call(request);
    final derived = cache.recent(
      scope: scope,
      request: call,
      nowMs: host.now().millisecondsSinceEpoch,
      zone: _zone(request.path),
    );
    if (derived != null) return _json(derived);
    try {
      final res = await inner.send(request);
      host.reachedServer();
      if (res.ok) {
        try {
          cache.save(
            scope: scope,
            request: call,
            headers: _pairs(res.headers),
            body: Uint8List.fromList(res.bodyBytes),
            atMs: host.now().millisecondsSinceEpoch,
          );
        } on Object {
          // Not kept: the answer itself is fine.
        }
      }
      return res;
    } on Object catch (e) {
      if (!isOfflineError(e)) {
        if (e is ApiException) host.reachedServer();
        rethrow;
      }
      CachedAnswer? saved;
      try {
        saved = cache.saved(
          scope: scope,
          request: call,
          zone: _zone(request.path),
        );
      } on Object {
        saved = null; // An unreadable cache: the offline error stands.
      }
      if (saved == null) rethrow;
      host.showedSaved(
        DateTime.fromMillisecondsSinceEpoch(saved.savedAtMs, isUtc: true),
      );
      return _json(saved.body);
    }
  }

  Future<ApiResponse> _plain(ApiRequest request) async {
    try {
      final res = await inner.send(request);
      host.reachedServer();
      return res;
    } on ApiException catch (e) {
      if (!isOfflineError(e)) host.reachedServer();
      rethrow;
    }
  }

  Future<ApiResponse> _write(ApiRequest request) async {
    forgetRecent();
    try {
      final res = await inner.send(request);
      host.reachedServer();
      return res;
    } on ApiException catch (e) {
      if (!isOfflineError(e)) {
        host.reachedServer();
        rethrow;
      }
      throw ApiException(
        status: 0,
        code: e.code ?? 'offline',
        message: host.cantSaveWords,
        details: e.details,
      );
    }
  }

  /// The zone the core asks for to cut [path]'s days (null: none needed or
  /// not known for certain).
  String? _zone(String path) {
    final need = OfflineCache.zoneOf(path: path);
    return need == null ? null : host.zoneFor(need.branchId);
  }

  static List<ApiPair> _pairs(Map<String, String> m) => [
    for (final e in m.entries) ApiPair(key: e.key, value: e.value),
  ];

  static CacheRequest _call(ApiRequest r) => CacheRequest(
    method: r.method.toUpperCase(),
    path: r.path,
    query: [
      for (final e in r.query.entries)
        for (final v in e.value) ApiPair(key: e.key, value: v),
    ],
    headers: _pairs(r.headers),
  );

  static ApiResponse _json(List<int> body) => ApiResponse(
    status: 200,
    headers: const {'content-type': 'application/json'},
    bodyBytes: body,
  );
}
