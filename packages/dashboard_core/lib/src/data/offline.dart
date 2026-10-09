/// Working with no network (the owner's requirement): even fully closed and
/// relaunched offline, the dashboard shows the latest data it has, says it
/// is offline and that the data may be out of date; with a network,
/// everything goes to the server as before.
///
/// All of it sits at the transport ([OfflineTransport]), so no page changes:
/// - every successful GET body is saved ([OfflineStore]), keyed by the person,
///   the org and branch in scope and the request ([offlineKey]);
/// - online, a saved body is never shown in place of a live answer. The one
///   local answer online is a narrower date range derived exactly
///   (`derivers.dart`) from a wider answer read live less than
///   [kQueryStaleTime] ago, as a fresh cache hit;
/// - offline (the request never reached the server: [isOfflineError]), the
///   saved body for that request, or one derived from a saved wider range,
///   whichever was saved later, answers it, and the shell's banner shows
///   ([offlineProvider]); with nothing saved the offline error stands;
/// - a write offline fails at once, in words that say so; nothing is queued;
/// - the next answer from the server clears the banner and reads again
///   everything that was built on saved data.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/src/data/derivers.dart';
import 'package:dashboard_core/src/data/offline_store.dart';
import 'package:dashboard_core/src/data/query_cache.dart' show kQueryStaleTime;
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/scope/scope.dart';
import 'package:dashboard_core/src/session/session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The saved answers; null = nothing is saved and nothing is served from
/// disk (tests that do not ask for it). The boots open one.
final offlineStoreProvider = Provider<OfflineStore?>((ref) => null);

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

/// Who is asking, as far as the server's answer depends on it.
class OfflineScope {
  const OfflineScope(this.user, {this.org, this.branch});

  final String user;
  final String? org;

  /// The branch picked in the scope bar (null: every branch). The header the
  /// server reads is a function of it and the person, so this is never
  /// coarser.
  final String? branch;

  String get key => '$user|${org ?? ''}|${branch ?? ''}';
}

/// What [OfflineTransport] needs from the app.
abstract interface class OfflineHost {
  /// Null when nobody is signed in: nothing is saved or served.
  OfflineScope? get scope;

  DateTime now();

  /// The zone the server cuts days in for [branchId] (null: every branch,
  /// the org's); null when not known for certain.
  String? zoneFor(String? branchId);

  /// "You're offline, so this can't be saved."
  String get cantSaveWords;

  void showedSaved(DateTime savedAt);

  void reachedServer();
}

/// [OfflineHost] over the provider container.
class RefOfflineHost implements OfflineHost {
  const RefOfflineHost(this.ref);

  final Ref ref;

  @override
  OfflineScope? get scope {
    final session = ref.read(currentSessionProvider);
    if (session == null) return null;
    return OfflineScope(
      session.user.id,
      org: ref.read(orgIdProvider),
      branch: ref.read(scopeProvider).branchId,
    );
  }

  @override
  DateTime now() => ref.read(clockProvider)();

  @override
  String? zoneFor(String? branchId) {
    if (branchId == null) return ref.read(currentOrgProvider).value?.timezone;
    for (final b in ref.read(branchesProvider).value ?? const <Branch>[]) {
      // `Branch.timezone` is the effective zone (branch → org → Cairo), the
      // one the server buckets in.
      if (b.id == branchId) return b.timezone;
    }
    return null;
  }

  @override
  String get cantSaveWords => ref.read(tProvider)('shell.offlineCantSave');

  @override
  void showedSaved(DateTime savedAt) =>
      ref.read(offlineProvider.notifier).showedSaved(savedAt);

  @override
  void reachedServer() => ref.read(offlineProvider.notifier).reachedServer();
}

/// A failure that never reached the Madar server: no network (the core's
/// `Offline`, status 0), a captive portal, or a 403 without the backend's
/// `{"error": …}` envelope (a firewall answering in its place).
bool isOfflineError(Object e) =>
    e is ApiException &&
    (e.status == 0 || (e.status == 403 && !_hasEnvelope(e.details)));

bool _hasEnvelope(Object? details) =>
    details is Map && details['error'] is String;

/// Paths whose answers are never saved: sign-in and identity, the public
/// pages (guest tokens), the till sync and stream, a device's own grants,
/// the offline sign-in bundle (PIN hashes, the LAN secret) and a suggested
/// PIN.
const List<String> _neverSavedPrefixes = [
  '/auth/',
  '/public/',
  '/sync/',
  '/realtime/',
  '/devices/me/',
];

final RegExp _neverSavedPath = RegExp(
  r'^(/users/pin-suggestion|/orgs/[^/]+/offline-auth-bundle)$',
);

/// Whether [r]'s answer may be saved: a GET, not an export (the web's
/// `X-Madar-Export`: counted and rate-limited, never from a cache), not a
/// secret.
bool offlineKeepable(ApiRequest r) {
  if (r.method.toUpperCase() != 'GET') return false;
  if (r.headers.keys.any((h) => h.toLowerCase() == 'x-madar-export')) {
    return false;
  }
  if (_neverSavedPrefixes.any(r.path.startsWith)) return false;
  return !_neverSavedPath.hasMatch(r.path);
}

/// The query, sorted by name (a name's values keep their order).
String canonicalQuery(Map<String, List<String>> query) {
  final names = query.keys.toList()..sort();
  return [
    for (final n in names)
      for (final v in query[n]!)
        '${Uri.encodeQueryComponent(n)}=${Uri.encodeQueryComponent(v)}',
  ].join('&');
}

/// [canonicalQuery] read back.
Map<String, List<String>> parseCanonicalQuery(String q) {
  final out = <String, List<String>>{};
  if (q.isEmpty) return out;
  for (final pair in q.split('&')) {
    final i = pair.indexOf('=');
    final n = Uri.decodeQueryComponent(i < 0 ? pair : pair.substring(0, i));
    final v = i < 0 ? '' : Uri.decodeQueryComponent(pair.substring(i + 1));
    (out[n] ??= []).add(v);
  }
  return out;
}

String _prefix(OfflineScope scope, String method, String path) =>
    '${scope.key}|$method $path?';

/// The key [r]'s answer is saved under. The language is not in it: no GET
/// body depends on it (the backend reads no language header; a body that
/// does takes it as a query parameter, which is in the key).
String offlineKey(OfflineScope scope, ApiRequest r) =>
    '${_prefix(scope, r.method.toUpperCase(), r.path)}${canonicalQuery(r.query)}';

class _Live {
  _Live(this.query, this.body, this.at);

  final Map<String, List<String>> query;
  final List<int> body;
  final DateTime at;
}

/// The offline seam over the network transport; see the library comment.
class OfflineTransport implements ApiTransport {
  OfflineTransport(
    this.inner, {
    required this.store,
    required this.host,
    List<RangeDeriver>? derivers,
  }) : derivers = derivers ?? rangeDerivers;

  final ApiTransport inner;

  /// Null: a plain pass-through.
  final OfflineStore? store;
  final OfflineHost host;
  final List<RangeDeriver> derivers;

  /// Answers read live in the last [kQueryStaleTime] that a deriver can
  /// narrow, by key.
  final Map<String, _Live> _recent = {};

  /// Keys answered by a deriver online, and when: asked again within
  /// [kQueryStaleTime] it is a refetch, which goes to the server.
  final Map<String, DateTime> _derivedAt = {};

  /// What was read may have changed (a write, a realtime nudge): nothing
  /// held so far answers for another range.
  void forgetRecent() => _recent.clear();

  @override
  Stream<String> stream(ApiRequest request) => inner.stream(request);

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    final store = this.store;
    if (store == null) return inner.send(request);
    // Never inside a provider's synchronous build: the host reads providers.
    await null;
    if (request.method.toUpperCase() != 'GET') return _write(request);
    final scope = offlineKeepable(request) ? host.scope : null;
    if (scope == null) return _plain(request);
    final key = offlineKey(scope, request);
    final derived = _fromRecent(scope, key, request);
    if (derived != null) return derived;
    try {
      final res = await inner.send(request);
      host.reachedServer();
      if (res.ok && res.bodyBytes.isNotEmpty && _isJson(res)) {
        final at = host.now();
        if (_isSource(request.path)) {
          _recent[key] = _Live(request.query, res.bodyBytes, at);
        }
        unawaited(
          store
              .write(scope.user, key, res.bodyBytes, at)
              .catchError((Object _) {}),
        );
      }
      return res;
    } on Object catch (e) {
      if (!isOfflineError(e)) {
        if (e is ApiException) host.reachedServer();
        rethrow;
      }
      final saved = await _saved(store, scope, key, request);
      if (saved == null) rethrow;
      host.showedSaved(saved.savedAt);
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

  // ponytail: a deriver reading another endpoint (the drinks summary reads
  // the drinks list) needs that endpoint to have a deriver of its own, so
  // its live answers are held; add a `sources` list if one ever does not.
  bool _isSource(String path) => derivers.any((d) => d.path.hasMatch(path));

  ({RangeDeriver deriver, DeriveRequest want})? _want(ApiRequest request) {
    for (final d in derivers) {
      final m = d.path.firstMatch(request.path);
      if (m == null) continue;
      final r = d.rangeOf(request.query);
      if (r == null) return null;
      return (
        deriver: d,
        want: DeriveRequest(
          path: request.path,
          match: m,
          query: request.query,
          from: r.from,
          to: r.to,
          zoneFor: host.zoneFor,
        ),
      );
    }
    return null;
  }

  ApiResponse? _fromRecent(
    OfflineScope scope,
    String key,
    ApiRequest request,
  ) {
    final w = _want(request);
    if (w == null) return null;
    final now = host.now();
    bool fresh(DateTime at) => now.difference(at) < kQueryStaleTime;
    _recent.removeWhere((_, v) => !fresh(v.at));
    _derivedAt.removeWhere((_, at) => !fresh(at));
    if (_derivedAt.containsKey(key)) return null;
    final prefix = _prefix(scope, 'GET', w.deriver.sourceOf(request.path));
    for (final e in _recent.entries) {
      if (e.key == key || !e.key.startsWith(prefix)) continue;
      if (!w.deriver.covers(e.value.query, w.want)) continue;
      final out = _derive(w.deriver, e.value.body, w.want);
      if (out == null) continue;
      _derivedAt[key] = now;
      return _json(out);
    }
    return null;
  }

  /// Offline: the saved answer for [key] or one derived from a saved wider
  /// range, whichever was saved later.
  Future<SavedAnswer?> _saved(
    OfflineStore store,
    OfflineScope scope,
    String key,
    ApiRequest request,
  ) async {
    var best = await store.read(key);
    final w = _want(request);
    if (w == null) return best;
    final prefix = _prefix(scope, 'GET', w.deriver.sourceOf(request.path));
    final candidates = [
      for (final k in store.keysWithPrefix(prefix))
        if (k != key) (key: k, at: store.savedAt(k)!),
    ]..sort((a, b) => b.at.compareTo(a.at));
    for (final c in candidates) {
      if (best != null && !c.at.isAfter(best.savedAt)) break;
      final query = parseCanonicalQuery(c.key.substring(prefix.length));
      if (!w.deriver.covers(query, w.want)) continue;
      final saved = await store.read(c.key);
      if (saved == null) continue;
      final out = _derive(w.deriver, saved.body, w.want);
      if (out == null) continue;
      best = SavedAnswer(out, saved.savedAt);
      break;
    }
    return best;
  }

  static List<int>? _derive(
    RangeDeriver d,
    List<int> body,
    DeriveRequest want,
  ) {
    try {
      final out = d.derive(jsonDecode(utf8.decode(body)), want);
      return out == null ? null : utf8.encode(jsonEncode(out));
    } on Object {
      return null;
    }
  }

  static bool _isJson(ApiResponse r) {
    for (final e in r.headers.entries) {
      if (e.key.toLowerCase() == 'content-type') {
        return e.value.toLowerCase().contains('json');
      }
    }
    return false;
  }

  static ApiResponse _json(List<int> body) => ApiResponse(
    status: 200,
    headers: const {'content-type': 'application/json'},
    bodyBytes: body,
  );
}
