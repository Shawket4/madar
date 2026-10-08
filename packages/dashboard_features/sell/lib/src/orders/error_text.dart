/// The words behind every error toast and error state on Orders: the web's
/// `getErrorMessage` (`data/api/errors.ts`, SELL-ALL-017), for the cases this
/// unit meets.
///
/// - A coded refusal whose `errors.codes.<code>` exists reads that
///   translation (`EXPORT_RATE_LIMITED` → "Too many exports just now…").
/// - An uncoded 429 → `errors.tooManyRequests`; an uncoded 403 (every
///   capability refusal: the backend's `Forbidden` carries no code) →
///   `errors.unauthorized`, never the server's English sentence.
/// - Otherwise the server's sentence with its "Kind: " prefix stripped
///   ("Conflict: Till already open" → "Till already open").
/// - Nothing reached the server → `errors.networkError`; then by status.
library;

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_core/dashboard_core.dart' show Translator;

final RegExp _kindPrefix = RegExp(
  '^(?:Unauthorized|Forbidden|Not found|Bad request|Conflict|'
  'Service unavailable|Database error): ',
);

/// What a person reads for [error].
String ordersErrorText(Object? error, Translator t) {
  if (error is ApiException) {
    final status = error.status;
    final code = error.code;
    if (code != null && t.exists('errors.codes.$code')) {
      final vars = switch (error.details) {
        final Map<Object?, Object?> m when m['vars'] is Map => {
          for (final e in (m['vars']! as Map).entries)
            e.key.toString(): e.value,
        },
        _ => const <String, Object?>{},
      };
      return t('errors.codes.$code', args: vars);
    }
    if (status == 429 && code == null) return t('errors.tooManyRequests');
    if (status == 403 && code == null) return t('errors.unauthorized');
    // A transport that never reached the server answers with status 0.
    if (status == 0) return t('errors.networkError');
    final msg = error.message;
    final envelope = error.details;
    final hasEnvelope = envelope is Map && envelope['error'] is String;
    if (hasEnvelope || (msg.isNotEmpty && !msg.startsWith('HTTP '))) {
      return msg.replaceFirst(_kindPrefix, '');
    }
    return switch (status) {
      401 => t('errors.sessionExpired'),
      403 => t('errors.unauthorized'),
      404 => t('errors.notFound'),
      409 => t('errors.conflict'),
      422 => t('errors.validation'),
      >= 500 => t('errors.server'),
      _ => msg,
    };
  }
  return t('errors.unknown');
}
