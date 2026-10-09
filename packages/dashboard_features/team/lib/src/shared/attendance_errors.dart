/// The words behind every error toast and error state on the Attendance page:
/// the web's `getErrorMessage` (`data/api/errors.ts`, TEAM-ALL-014/019) for
/// the refusals this unit meets.
///
/// - A coded refusal whose `errors.codes.<code>` exists reads that sentence,
///   its figures made readable first (`codedVars`: a `date` as a date, an
///   `…_at` as a time, a request `status` as a word). `PERIOD_*` names its
///   phases; `PERIOD_CLOSED {paid: true}` reads `PERIOD_CLOSED_paid`.
/// - An uncoded 429 → `errors.tooManyRequests`; an uncoded 403 (every
///   capability refusal) → `errors.unauthorized`, never the server's English.
/// - Otherwise the server's own sentence without its "Kind: " prefix.
/// - Nothing reached the server → `errors.networkError`; then by status.
library;

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_core/dashboard_core.dart' show DashFormat, Translator;

final RegExp _kindPrefix = RegExp(
  '^(?:Unauthorized|Forbidden|Not found|Bad request|Conflict|'
  'Service unavailable|Database error): ',
);

const List<String> _weekdayKeys = [
  'sun',
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
];

const Map<String, String> _periodStatusKeys = {
  'draft': 'dawam.phase_open',
  'generated': 'dawam.phase_approved',
  'paid': 'dawam.phase_paid',
  'closed': 'dawam.phase_closed',
};

/// The refusal's `vars`, as sent.
Map<String, Object?> _rawVars(ApiException e) {
  final d = e.details;
  if (d is Map && d['vars'] is Map) {
    return {
      for (final entry in (d['vars']! as Map).entries)
        entry.key.toString(): entry.value,
    };
  }
  return const {};
}

/// `codedVars`: the figures ready for their sentence.
Map<String, Object?> _codedVars(
  Map<String, Object?> raw,
  Translator t,
  DashFormat f,
) {
  final sep = t('common.listSeparator');
  final out = <String, Object?>{};
  raw.forEach((k, v) {
    if (k == 'date' && v is String) {
      out[k] = f.fmtDate(v);
    } else if (k == 'days' && v is List) {
      out[k] = v
          .map((d) {
            final i = d is num ? d.toInt() : int.tryParse('$d') ?? -1;
            return i >= 0 && i < 7
                ? t('staff.${_weekdayKeys[i]}', defaultValue: '$d')
                : '$d';
          })
          .join(sep);
    } else if (k == 'day_of_week' && v is num) {
      final i = v.toInt();
      out[k] = i >= 0 && i < 7
          ? t('staff.${_weekdayKeys[i]}', defaultValue: '$v')
          : '$v';
    } else if (k == 'status' && v is String) {
      out[k] = t.exists('staff.req_$v') ? t('staff.req_$v') : v;
    } else if (k == 'names' && v is List) {
      out[k] = v.join(sep);
    } else if (k == 'at' && v is String) {
      out[k] = f.fmtDateTimeFull(v);
    } else if (k.endsWith('_at') && v is String) {
      out[k] = f.fmtTime(v);
    } else {
      out[k] = v;
    }
  });
  return out;
}

/// What a person reads for [error] (`getErrorMessage(err)`).
String attendanceErrorText(Object? error, Translator t, DashFormat f) {
  if (error is ApiException) {
    final status = error.status;
    final code = error.code;
    final raw = _rawVars(error);
    final vars = _codedVars(raw, t, f);
    if (code != null && code.startsWith('PERIOD_')) {
      for (final k in const ['status', 'from', 'to']) {
        final key = raw[k] is String ? _periodStatusKeys[raw[k]] : null;
        if (key != null) vars[k] = t(key);
      }
    }
    final key = code == 'PERIOD_CLOSED' && vars['paid'] == true
        ? 'PERIOD_CLOSED_paid'
        : code;
    if (key != null && t.exists('errors.codes.$key')) {
      return t('errors.codes.$key', args: vars);
    }
    if (status == 429 && code == null) return t('errors.tooManyRequests');
    if (status == 403 && code == null) return t('errors.unauthorized');
    final envelope = error.details;
    final hasEnvelope = envelope is Map && envelope['error'] is String;
    if (status == 0) return t('errors.networkError');
    if (hasEnvelope) return error.message.replaceFirst(_kindPrefix, '');
    return switch (status) {
      401 => t('errors.sessionExpired'),
      403 => t('errors.unauthorized'),
      404 => t('errors.notFound'),
      409 => t('errors.conflict'),
      422 => t('errors.validation'),
      >= 500 => t('errors.server'),
      _ =>
        error.message.isEmpty
            ? t('errors.unknown')
            : error.message.replaceFirst(_kindPrefix, ''),
    };
  }
  return t('errors.unknown');
}
