/// The words a failed organization call shows (the web's `getErrorMessage`,
/// ADM-APP-117), and where a provisioning conflict belongs (`provision.ts`
/// `conflictTarget`, ADM-ORG-040).
///
/// In real mode the core has already worded a refusal (`ApiException.message`
/// is human, in the active language, without the server's "Conflict: " kind);
/// these rules then change nothing. The mock answers like the backend itself
/// (`{"error": "Forbidden: …"}`), so the same ladder the web and the core
/// run is applied here: a coded refusal reads in its own words, an uncoded
/// 403 / 429 is "no permission" / "too many requests", a server sentence
/// loses its kind, and an Arabic reader never reads the server's English
/// (the core's rule; the web shows it — docs/fdash/divergences/admin-orgs.md).
library;

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_core/dashboard_core.dart';

/// The kinds the backend's `AppError` writes before its sentence (the web's
/// `SERVER_KIND_PREFIX`).
const List<String> serverKindPrefixes = [
  'Unauthorized: ',
  'Forbidden: ',
  'Not found: ',
  'Bad request: ',
  'Conflict: ',
  'Service unavailable: ',
  'Database error: ',
];

/// A failure already in words (thrown to the image uploader, which shows the
/// thrown object's text under the box).
class OrgFailure implements Exception {
  const OrgFailure(this.words);

  final String words;

  @override
  String toString() => words;
}

String _statusWords(int status, Translator t) => switch (status) {
  401 => t('errors.sessionExpired'),
  403 => t('errors.unauthorized'),
  404 => t('errors.notFound'),
  409 => t('errors.conflict'),
  400 || 422 => t('errors.validation'),
  429 => t('errors.tooManyRequests'),
  0 => t('errors.networkError'),
  >= 500 => t('errors.server'),
  _ => t('errors.unknown'),
};

/// The words for [error] in [t]'s language.
String orgErrorWords(Object? error, Translator t) {
  if (error is OrgFailure) return error.words;
  if (error is! ApiException) return t('errors.unknown');
  final code = error.code;
  if (code != null) {
    final key = 'errors.codes.$code';
    if (t.exists(key)) {
      final details = error.details;
      final vars = details is Map ? details['vars'] : null;
      return t(
        key,
        args: vars is Map ? vars.map((k, v) => MapEntry('$k', v)) : null,
      );
    }
  }
  if (code == null && error.status == 429) return t('errors.tooManyRequests');
  if (code == null && error.status == 403) return t('errors.unauthorized');
  final raw = error.message.trim();
  String? kind;
  for (final p in serverKindPrefixes) {
    if (raw.startsWith(p)) kind = p;
  }
  final sentence = kind == null ? raw : raw.substring(kind.length).trim();
  // An Arabic reader never reads the server's English; the core's words in
  // real mode are Arabic already and pass.
  if (sentence.isEmpty || (t.isRtl && _looksEnglish(sentence))) {
    return _statusWords(error.status, t);
  }
  return sentence;
}

bool _looksEnglish(String s) => RegExp('^[\\x00-\\x7F]+\$').hasMatch(s);

/// The server's own sentence of [error] (the envelope's `error`), kind and
/// all: what `conflictTarget` matches on.
String rawServerSentence(ApiException error) {
  final details = error.details;
  if (details is Map) {
    final e = details['error'];
    if (e is String) return e;
    final m = details['message'];
    if (m is String) return m;
  }
  return error.message;
}

/// Where a 409 from `POST /orgs/provision` belongs: a message naming the
/// slug → step 1's Slug; naming the email → step 3's Email (the backend
/// sends no code for these, so the web matches the text). Null for anything
/// else (an error toast).
({int step, String field, String message})? provisionConflictTarget(
  Object? error,
  Translator t,
) {
  if (error is! ApiException || error.status != 409) return null;
  final raw = rawServerSentence(error);
  final words = orgErrorWords(error, t);
  if (RegExp('slug', caseSensitive: false).hasMatch(raw)) {
    return (step: 0, field: 'slug', message: words);
  }
  if (RegExp('email', caseSensitive: false).hasMatch(raw)) {
    return (step: 2, field: 'email', message: words);
  }
  return null;
}
