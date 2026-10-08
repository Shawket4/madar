/// A failed money call in the reader's words: the port of the web's
/// `getErrorMessage(e, { reasonFor, monthForm })` (`data/api/errors.ts`,
/// TEAM-ALL-014 / TEAM-ALL-019). A coded refusal reads from
/// `errors.codes.<CODE>` with its figures worded (a date as a date, a status
/// as a phase), and the client-side variants the forms need:
///
/// - `REASON_REQUIRED` worded for the situation ([ReasonFor]);
/// - `PERIOD_CLOSED` on a month form → `_month` / `_paid_month`, a paid
///   month alone → `_paid`;
/// - `ADVANCE_OVER_CAP` with no amount → `_owner`; `ALREADY_ROSTERED`,
///   `SHIFT_DAYS_IN_USE`, `SHIFTS_OVERLAP` with a name → `_named`;
/// - a 429 or a 403 the server did not code → `errors.tooManyRequests` /
///   `errors.unauthorized`;
/// - otherwise the server's sentence without its kind prefix.
library;

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_core/dashboard_core.dart';

/// What a `REASON_REQUIRED` refusal was about (the server sends no vars).
enum ReasonFor { payLine, stopLine, punchFor, decline, correctAdvance }

const List<String> _weekdayKeys = [
  'sun',
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
];

/// The kinds the backend's AppError writes before its sentence.
final RegExp _serverKindPrefix = RegExp(
  r'^(?:Unauthorized|Forbidden|Not found|Bad request|Conflict|Service unavailable|Database error): ',
);

const Map<String, String> _shiftFieldLabels = {
  'grace_minutes': 'staff.graceMinutes',
  'break_minutes': 'staff.breakMinutes',
  'overtime_threshold_minutes': 'staff.otThreshold',
  'checkin_window_minutes': 'staff.checkinWindow',
  'half_day_threshold_minutes': 'staff.halfDayThreshold',
  'overtime_multiplier': 'staff.otMultiplier',
  'ot_day_multiplier': 'staff.otDayMultiplier',
  'ot_night_multiplier': 'staff.otNightMultiplier',
};

const Map<String, String> _periodStatusKeys = {
  'draft': 'dawam.phase_open',
  'generated': 'dawam.phase_approved',
  'paid': 'dawam.phase_paid',
  'closed': 'dawam.phase_closed',
};

const Map<String, List<String>> _statusVariants = {
  'CANCEL_REASON_REQUIRED': ['approved'],
  'OPEN_SHIFT_CLOSED': ['filled', 'cancelled'],
};

Map<String, Object?> _rawVars(ApiException e) {
  final d = e.details;
  if (d is Map && d['vars'] is Map) {
    return (d['vars'] as Map).map((k, v) => MapEntry(k.toString(), v));
  }
  return const {};
}

/// A coded refusal's figures ready for its sentence (`codedVars`).
Map<String, Object?> _codedVars(
  Map<String, Object?> raw,
  Translator t,
  DashFormat f,
) {
  final out = <String, Object?>{};
  for (final e in raw.entries) {
    final k = e.key;
    final v = e.value;
    if (k == 'date' && v is String) {
      out[k] = f.fmtDate(v);
    } else if (k == 'days' && v is List) {
      out[k] = v
          .map((d) {
            final i = d is num ? d.toInt() : int.tryParse('$d') ?? -1;
            return i >= 0 && i < 7 ? t('staff.${_weekdayKeys[i]}') : '$d';
          })
          .join(t('common.listSeparator'));
    } else if (k == 'day_of_week' && v is num && v >= 0 && v < 7) {
      out[k] = t('staff.${_weekdayKeys[v.toInt()]}');
    } else if (k == 'status' && v is String) {
      out[k] = t('staff.req_$v', defaultValue: v);
    } else if (k == 'names' && v is List) {
      out[k] = v.join(t('common.listSeparator'));
    } else if (k == 'at' && v is String) {
      out[k] = f.fmtDateTimeFull(v);
    } else if (k.endsWith('_at') && v is String) {
      out[k] = f.fmtTime(v);
    } else {
      out[k] = v;
    }
  }
  return out;
}

String _settingKey(Map<String, Object?> vars) {
  if (vars['allowed'] is List) return 'SETTING_OUT_OF_RANGE_choice';
  if (vars['min_inclusive'] == false) return 'SETTING_OUT_OF_RANGE_above';
  if (vars['max_inclusive'] == false) return 'SETTING_OUT_OF_RANGE_below';
  return 'SETTING_OUT_OF_RANGE';
}

/// [error] in the reader's words (see the library comment).
String dawamErrorMessage(
  Object? error,
  Translator t,
  DashFormat f, {
  ReasonFor? reasonFor,
  bool monthForm = false,
  String Function(String field)? fieldLabel,
}) {
  if (error is! ApiException) return errorMessage(error, t);
  final code = error.code;
  final raw = _rawVars(error);
  final vars = _codedVars(raw, t, f);
  if (code == 'STATUS_UNKNOWN') vars['status'] = raw['status'];
  if (code != null && code.startsWith('PERIOD_')) {
    for (final k in const ['status', 'from', 'to']) {
      final w = raw[k] is String ? _periodStatusKeys[raw[k]] : null;
      if (w != null) vars[k] = t(w);
    }
  }
  final shiftField = code == 'SHIFT_SETTING_INVALID' && vars['field'] is String
      ? _shiftFieldLabels[vars['field']]
      : null;
  if (vars['field'] is String) {
    final field = vars['field']! as String;
    vars['field'] =
        fieldLabel?.call(field) ?? (shiftField != null ? t(shiftField) : field);
  }
  final variant =
      code != null &&
          raw['status'] is String &&
          (_statusVariants[code]?.contains(raw['status']) ?? false)
      ? '${code}_${raw['status']}'
      : null;
  final reasonKey = code == 'REASON_REQUIRED' && reasonFor != null
      ? 'REASON_REQUIRED_${reasonFor.name}'
      : code == 'PERIOD_CLOSED' && monthForm
      ? (vars['paid'] == true
            ? 'PERIOD_CLOSED_paid_month'
            : 'PERIOD_CLOSED_month')
      : null;
  final key =
      reasonKey ??
      variant ??
      (code == 'PERIOD_CLOSED' && vars['paid'] == true
          ? 'PERIOD_CLOSED_paid'
          : code == 'SETTING_OUT_OF_RANGE'
          ? _settingKey(vars)
          : (code == 'ALREADY_ROSTERED' || code == 'SHIFT_DAYS_IN_USE') &&
                vars['name'] is String
          ? '${code}_named'
          : code == 'SHIFTS_OVERLAP' && vars['a'] is String
          ? 'SHIFTS_OVERLAP_named'
          : code == 'ADVANCE_OVER_CAP' &&
                vars['more_egp'] == null &&
                vars['over_cap'] == true
          ? 'ADVANCE_OVER_CAP_owner'
          : code);
  if (key != null && t.exists('errors.codes.$key')) {
    return t('errors.codes.$key', args: vars);
  }
  if (error.status == 429 && code == null) return t('errors.tooManyRequests');
  if (error.status == 403 && code == null) return t('errors.unauthorized');
  // The transport's words (the core's, in the active language, in real
  // mode), without the kind the server writes before its sentence.
  final said = error.message;
  if (said.isNotEmpty) return said.replaceFirst(_serverKindPrefix, '');
  return errorMessage(error, t);
}
