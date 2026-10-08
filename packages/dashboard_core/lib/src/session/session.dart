/// The signed-in session (`src/data/stores/auth.store.ts`, `src/lib/auth-guard.ts`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:dashboard_core/src/data/models.dart';
import 'package:dashboard_core/src/gateways/preferences.dart';
import 'package:dashboard_core/src/scope/scope.dart' show ScopePrefKeys;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Signing in and out, and telling the transport which org and branch the
/// next requests are for (the web's `apiContext.setOrg` / `setBranch`, i.e.
/// the `X-Org-Id` / `X-Branch-Id` headers). Real mode: the core over the
/// bridge (it holds the token and refreshes it). Tests: `MockSessionGateway`.
abstract interface class SessionGateway {
  /// The session kept from last time, or null.
  Future<SessionInfo?> restore();

  /// Email + password sign-in (admins, managers, platform admins). Throws the
  /// transport's `ApiException` on a refusal, worded for the person.
  Future<SessionInfo> signIn({
    required String email,
    required String password,
    String? orgId,
  });

  /// Forgets the session (token, org, branch).
  Future<void> signOut();

  /// The org and branch the next requests carry. A platform admin switching
  /// org goes through here too.
  Future<void> applyScope({required String? orgId, required String? branchId});
}

final sessionGatewayProvider = Provider<SessionGateway>(
  (ref) =>
      throw StateError('sessionGatewayProvider must be overridden at boot'),
);

/// The token is treated as expired only this far past `exp` (clock skew).
const Duration tokenExpirySkew = Duration(seconds: 30);

/// A JWT's `exp` as an instant, or null when it has none / is unreadable.
DateTime? jwtExpiry(String token) {
  try {
    final parts = token.split('.');
    if (parts.length < 2 || parts[1].isEmpty) return null;
    final payload = json.decode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final exp = payload is Map ? payload['exp'] : null;
    return exp is num
        ? DateTime.fromMillisecondsSinceEpoch((exp * 1000).round(), isUtc: true)
        : null;
  } on Object {
    return null;
  }
}

/// Whether [token] is past its `exp` (+ [tokenExpirySkew]) at [now].
bool tokenExpired(String token, DateTime now) {
  final exp = jwtExpiry(token);
  return exp != null && now.isAfter(exp.add(tokenExpirySkew));
}

/// The clock the session and scope read (overridden in tests).
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Why the last sign-out happened.
enum SignOutReason { requested, expired, unauthorized }

/// The session: null when signed out.
class SessionNotifier extends AsyncNotifier<SessionInfo?> {
  bool _tearingDown = false;
  SignOutReason? _lastReason;

  /// Why the session last ended (the shell sends `expired`/`unauthorized`
  /// to the sign-in page with the page to come back to).
  SignOutReason? get lastSignOutReason => _lastReason;

  SessionGateway get _gateway => ref.read(sessionGatewayProvider);

  @override
  Future<SessionInfo?> build() async {
    final restored = await ref.watch(sessionGatewayProvider).restore();
    final token = restored?.token;
    // A present-but-expired token would pass and then 401 on the first
    // query: sign out before anything fires (`requireAuth`).
    if (token != null && tokenExpired(token, ref.read(clockProvider)())) {
      await _gateway.signOut();
      _lastReason = SignOutReason.expired;
      return null;
    }
    return restored;
  }

  /// Signs in; the refusal (an `ApiException`) propagates to the caller and
  /// the session stays as it was.
  Future<SessionInfo> signIn({
    required String email,
    required String password,
    String? orgId,
  }) async {
    final info = await _gateway.signIn(
      email: email,
      password: password,
      orgId: orgId,
    );
    _tearingDown = false;
    _lastReason = null;
    state = AsyncData(info);
    return info;
  }

  /// Signs out and forgets the scope (`signOut`).
  Future<void> signOut([SignOutReason reason = SignOutReason.requested]) async {
    _lastReason = reason;
    await _gateway.signOut();
    // Reset the persisted app context (org, branch), as the web does.
    final prefs = ref.read(preferencesProvider);
    await prefs.setString(ScopePrefKeys.org, null);
    await prefs.setString(ScopePrefKeys.branch, null);
    state = const AsyncData(null);
  }

  /// A 401 from any request: sign out exactly once, however many requests
  /// failed together.
  Future<void> handleUnauthorized() async {
    if (_tearingDown || state.value == null) return;
    _tearingDown = true;
    await signOut(SignOutReason.unauthorized);
  }
}

final sessionProvider = AsyncNotifierProvider<SessionNotifier, SessionInfo?>(
  SessionNotifier.new,
  retry: (_, _) => null,
);

/// The session once known (null while restoring or signed out).
final currentSessionProvider = Provider<SessionInfo?>(
  (ref) => ref.watch(sessionProvider).value,
);
