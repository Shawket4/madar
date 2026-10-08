/// The web's 401 funnel (`data/api/client.ts` + `auth.store.ts`): a 401 on an
/// authenticated request while signed in ends the session — exactly once,
/// however many requests failed together — and the router then sends the
/// person to sign-in with the page to come back to.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart';

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
