/// A failed money call in the reader's words: the web's
/// `getErrorMessage(e, { reasonFor, monthForm })` (`data/api/errors.ts`,
/// TEAM-ALL-014 / TEAM-ALL-019). The area's [attendanceErrorText] words every
/// coded refusal; the money forms add the client-side variants they need:
///
/// - `REASON_REQUIRED` worded for the situation ([ReasonFor]);
/// - `PERIOD_CLOSED` on a month form → `_month` / `_paid_month`;
/// - `ADVANCE_OVER_CAP` without the figures (a caller who may not see the
///   salary they reveal) → `_owner`.
library;

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_core/dashboard_core.dart';

import '../shared/attendance_errors.dart';

/// What a `REASON_REQUIRED` refusal was about (the server sends no vars).
enum ReasonFor { payLine, stopLine, punchFor, decline, correctAdvance }

/// [error] in the reader's words (see the library comment).
String dawamErrorMessage(
  Object? error,
  Translator t,
  DashFormat f, {
  ReasonFor? reasonFor,
  bool monthForm = false,
}) {
  if (error is ApiException) {
    final d = error.details;
    final vars = d is Map && d['vars'] is Map ? d['vars'] as Map : const {};
    final key = switch (error.code) {
      'REASON_REQUIRED' when reasonFor != null =>
        'REASON_REQUIRED_${reasonFor.name}',
      'PERIOD_CLOSED' when monthForm =>
        vars['paid'] == true ? 'PERIOD_CLOSED_paid_month' : 'PERIOD_CLOSED_month',
      'ADVANCE_OVER_CAP'
          when vars['more_egp'] == null && vars['over_cap'] == true =>
        'ADVANCE_OVER_CAP_owner',
      _ => null,
    };
    if (key != null && t.exists('errors.codes.$key')) {
      return t('errors.codes.$key');
    }
  }
  return attendanceErrorText(error, t, f);
}
