/// The words behind every error toast, dialog line and error state in the
/// sell area: the web's `getErrorMessage` (`data/api/errors.ts`,
/// SELL-ALL-017).
///
/// - A coded refusal whose `errors.codes.<code>` exists reads that
///   translation, with the envelope's `vars` (`EXPORT_RATE_LIMITED` →
///   "Too many exports just now…").
/// - An uncoded 429 → `errors.tooManyRequests`; an uncoded 403 (every
///   capability refusal: the backend's `Forbidden` carries no code) →
///   `errors.unauthorized`, never the server's English sentence.
/// - Nothing reached the server (status 0) → `errors.networkError`.
/// - Otherwise the server's sentence with its "Kind: " prefix stripped
///   ("Conflict: Till already open" → "Till already open"); in the real app
///   the transport has already worded it in the person's language.
/// - No sentence at all: by status.
library;

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_core/dashboard_core.dart'
    show ExportTooLargeError, Translator;

/// The kinds the backend's `AppError` writes before its sentence.
final RegExp _kindPrefix = RegExp(
  '^(?:Unauthorized|Forbidden|Not found|Bad request|Conflict|'
  'Service unavailable|Database error): ',
);

/// What a person reads for [error], in [t]'s language.
String sellErrorText(Object? error, Translator t) {
  if (error is ExportTooLargeError) return error.message(t);
  if (error is! ApiException) return t('errors.unknown');
  final code = error.code;
  final details = error.details;
  if (code != null && t.exists('errors.codes.$code')) {
    final vars = details is Map ? details['vars'] : null;
    return t(
      'errors.codes.$code',
      args: vars is Map ? vars.cast<String, Object?>() : null,
    );
  }
  final status = error.status;
  if (code == null && status == 429) return t('errors.tooManyRequests');
  if (code == null && status == 403) return t('errors.unauthorized');
  if (status <= 0) return t('errors.networkError');
  final sentence = error.message.replaceFirst(_kindPrefix, '');
  // The mock's bare `HTTP <status>` (no envelope) is no sentence.
  if (sentence.isNotEmpty && sentence != 'HTTP $status') return sentence;
  return switch (status) {
    401 => t('errors.sessionExpired'),
    403 => t('errors.unauthorized'),
    404 => t('errors.notFound'),
    409 => t('errors.conflict'),
    400 || 422 => t('errors.validation'),
    >= 500 => t('errors.server'),
    _ => error.message,
  };
}
