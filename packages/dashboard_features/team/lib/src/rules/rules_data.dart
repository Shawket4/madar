/// The Rules page's reads and the words for its refusals
/// (`staff/attendance-rules-page.tsx`, `data/api/errors.ts`).
///
/// - `GET /staff/attendance/settings/branches` (`listBranchRules`): the
///   person's branches and which rules each sets itself.
/// - `GET /staff/attendance/settings[?branch_id]` (`getAttendanceSettings`):
///   the business's rules, or a branch's effective ones with `overridden`.
///
/// Both are keyed by their endpoint path, so a save's `invalidateAttendance`
/// (every `/staff/attendance…` read) and the Refresh button reach them.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/staff_query.dart';

/// `GET /staff/attendance/settings/branches`.
final rulesBranchesProvider = FutureProvider.autoDispose<List<BranchRules>>((
  ref,
) {
  ref.webCache();
  watchStaffPath(ref, '/staff/attendance/settings/branches');
  return ref.watch(apiProvider).staff.listBranchRules();
});

/// `GET /staff/attendance/settings[?branch_id]`: null is the business.
final rulesSettingsProvider = FutureProvider.autoDispose
    .family<AttendanceSettings, String?>((ref, branchId) {
      ref.webCache();
      watchStaffPath(ref, '/staff/attendance/settings');
      return ref
          .watch(apiProvider)
          .staff
          .getAttendanceSettings(branchId: branchId);
    });

/// The server's "Kind: " before its sentence (`SERVER_KIND_PREFIX`).
final RegExp _serverKind = RegExp(
  r'^(?:Unauthorized|Forbidden|Not found|Bad request|Conflict|Service unavailable|Database error): ',
);

/// `SETTING_OUT_OF_RANGE` comes in four shapes: a list of allowed values, or
/// a range whose ends may be open (`settingKey`).
String _settingKey(Map<String, Object?> vars) {
  if (vars['allowed'] is List) return 'SETTING_OUT_OF_RANGE_choice';
  if (vars['min_inclusive'] == false) return 'SETTING_OUT_OF_RANGE_above';
  if (vars['max_inclusive'] == false) return 'SETTING_OUT_OF_RANGE_below';
  return 'SETTING_OUT_OF_RANGE';
}

/// The words for a failed rules request, as the web's `getErrorMessage`
/// gives them: a coded refusal in the person's language (a refused rule
/// named by its page label through [fieldLabel], TEAM-ALL-019); an uncoded
/// 429 / 403 as "too many requests" / "no permission"; else the server's
/// sentence without its "Kind: " prefix; else by status.
String rulesErrorMessage(
  Object? error,
  Translator t, {
  String Function(String field)? fieldLabel,
}) {
  if (error is! ApiException) return errorMessage(error, t);
  final details = error.details;
  final envelope = details is Map ? details : const {};
  final rawVars = envelope['vars'];
  final vars = <String, Object?>{
    if (rawVars is Map)
      for (final e in rawVars.entries) '${e.key}': e.value,
  };
  final field = vars['field'];
  if (field is String && fieldLabel != null) vars['field'] = fieldLabel(field);
  final code = error.code;
  if (code != null) {
    final key = code == 'SETTING_OUT_OF_RANGE' ? _settingKey(vars) : code;
    if (t.exists('errors.codes.$key')) {
      return t('errors.codes.$key', args: vars);
    }
  }
  if (code == null && error.status == 429) return t('errors.tooManyRequests');
  if (code == null && error.status == 403) return t('errors.unauthorized');
  final said = envelope['error'] is String
      ? envelope['error'] as String
      : envelope['message'] is String
      ? envelope['message'] as String
      : error.message;
  if (error.status != 0 && said.isNotEmpty) {
    return said.replaceFirst(_serverKind, '');
  }
  return switch (error.status) {
    0 => t('errors.networkError'),
    401 => t('errors.sessionExpired'),
    403 => t('errors.unauthorized'),
    404 => t('errors.notFound'),
    409 => t('errors.conflict'),
    422 => t('errors.validation'),
    >= 500 => t('errors.server'),
    _ => errorMessage(error, t),
  };
}
