/// The words for a failed call (the web's `getErrorMessage`,
/// `data/api/errors.ts`; SELL-ALL-017), behind every error toast and dialog
/// line on the bookings page:
///
/// - a `code` the tables know (`errors.codes.<code>`) reads in the person's
///   language (`EXPORT_RATE_LIMITED` …);
/// - an uncoded 429 → `errors.tooManyRequests`;
/// - an uncoded 403 — every capability refusal, the backend's `Forbidden`
///   carries no code — → `errors.unauthorized`, never the server's English;
/// - otherwise the server's `error` with its "Kind: " prefix stripped, or its
///   `message`;
/// - no envelope at all: by status, else the exception's own words.
library;

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_core/dashboard_core.dart';

final RegExp _kindPrefix = RegExp(
  '^(?:Unauthorized|Forbidden|Not found|Bad request|Conflict|'
  'Service unavailable|Database error): ',
);

/// [error] in words, in [t]'s language.
String bookingErrorText(Object? error, Translator t) {
  if (error is! ApiException) {
    return t('errors.unknown', defaultValue: 'An unexpected error occurred.');
  }
  final details = error.details;
  final envelope = details is Map ? details : null;
  final code =
      error.code ??
      (envelope?['code'] is String ? envelope!['code'] as String : null);
  if (code != null && t.exists('errors.codes.$code')) {
    final vars = envelope?['vars'];
    return t(
      'errors.codes.$code',
      args: vars is Map ? vars.cast<String, Object?>() : null,
    );
  }
  final status = error.status;
  if (status == 429 && code == null) return t('errors.tooManyRequests');
  if (status == 403 && code == null) return t('errors.unauthorized');
  final raw = envelope?['error'];
  if (raw is String) return raw.replaceFirst(_kindPrefix, '');
  final message = envelope?['message'];
  if (message is String) return message;
  if (status == 0) return t('errors.networkError');
  if (envelope == null && error.message.isNotEmpty) {
    // Real mode: the core has already worded it in this language.
    return error.message.replaceFirst(_kindPrefix, '');
  }
  return switch (status) {
    401 => t('errors.sessionExpired'),
    404 => t('errors.notFound'),
    409 => t('errors.conflict'),
    422 => t('errors.validation'),
    >= 500 => t('errors.server'),
    _ => error.message,
  };
}
