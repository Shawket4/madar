/// A refusal worded the way real mode words it, for the mock backend (the
/// mock app's boot and the test harness): the core's `answer_words`
/// (madar-core `api_raw.rs`) and the app's coded table on top of it
/// (`errors.codes.<CODE>`, `CoreTransport.refusalWords`). So the mock shows
/// what a person reads: no "Conflict: " prefix, words for an uncoded 403 or
/// 429, and never the server's English on an Arabic screen.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, ApiRequest, ApiResponse, ApiTransport;
import 'package:dashboard_core/src/i18n/i18n_providers.dart';

/// The kinds the backend's `AppError` writes before its sentence
/// (`SERVER_KIND_PREFIXES`).
const List<String> _kindPrefixes = [
  'Unauthorized: ',
  'Forbidden: ',
  'Not found: ',
  'Bad request: ',
  'Conflict: ',
  'Service unavailable: ',
  'Database error: ',
];

/// [e] with the words real mode would show in [t]'s language. A failure
/// that never reached the server (status 0) is left as it is.
ApiException wordRefusal(ApiException e, Translator t) {
  if (e.status == 0) return e;
  final details = e.details;
  final code = e.code;
  if (code != null && t.exists('errors.codes.$code')) {
    final vars = details is Map ? details['vars'] : null;
    return _worded(
      e,
      t(
        'errors.codes.$code',
        args: vars is Map ? vars.cast<String, Object?>() : const {},
      ),
    );
  }
  String? said;
  if (code == null && e.status == 429) {
    said = t('errors.tooManyRequests');
  } else if (code == null && e.status == 403) {
    said = t('errors.unauthorized');
  } else if (t.lang != 'ar') {
    said = _sentence(e.message);
  }
  said ??= t(switch (e.status) {
    401 => 'errors.sessionExpired',
    403 => 'errors.unauthorized',
    404 => 'errors.notFound',
    409 => 'errors.conflict',
    400 || 422 => 'errors.validation',
    429 => 'errors.tooManyRequests',
    >= 500 => 'errors.server',
    _ => 'errors.unknown',
  });
  return _worded(e, said);
}

/// The server's sentence without its kind; null when nothing but a status
/// is left (the mock's `HTTP 502` for an answer without an envelope).
String? _sentence(String message) {
  var said = message.trim();
  for (final p in _kindPrefixes) {
    if (said.startsWith(p)) {
      said = said.substring(p.length).trim();
      break;
    }
  }
  return said.isEmpty || RegExp(r'^HTTP \d{3}$').hasMatch(said) ? null : said;
}

ApiException _worded(ApiException e, String message) => ApiException(
  status: e.status,
  code: e.code,
  message: message,
  details: e.details,
);

/// [inner] with every refusal worded by [wordRefusal] in the language
/// [translator] reads at the time.
class RefusalWordingTransport implements ApiTransport {
  RefusalWordingTransport(this.inner, this.translator);

  final ApiTransport inner;
  final Translator Function() translator;

  ApiException _word(ApiException e) => wordRefusal(e, translator());

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    try {
      return await inner.send(request);
    } on ApiException catch (e) {
      throw _word(e);
    }
  }

  @override
  Stream<String> stream(ApiRequest request) => inner
      .stream(request)
      .handleError(
        (Object e) => throw _word(e as ApiException),
        test: (e) => e is ApiException,
      );
}
