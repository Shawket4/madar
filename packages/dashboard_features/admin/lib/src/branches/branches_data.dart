/// The Branches unit's reads and the rules its screens share: the branch list
/// (`useListBranches`), the timezone list (`useListTimezones`), the web's
/// `invalidateBranches()`, the printer cell's words and the web's
/// `getErrorMessage` wording for a failed call.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, Branch, PrinterBrand;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `GET /branches?org_id=<org>` (listBranches): every branch of the org,
/// inactive included, unpaginated. A `branch.settings_changed` nudge (or
/// [invalidateBranches]) asks again, as the web's `/branches` prefix
/// invalidation does.
final adminBranchesProvider = FutureProvider.autoDispose
    .family<List<Branch>, String>((ref, orgId) {
      ref.watch(realtimeEpochProvider('/branches?org_id=$orgId'));
      return ref.watch(apiProvider).branches.listBranches(orgId: orgId);
    });

/// `GET /timezones` (listTimezones) for the timezone select.
final branchTimezonesProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(apiProvider).branches.listTimezones(),
);

/// The web's `invalidateBranches()`: every read whose key starts with
/// `/branches` — this page's list, the scope bar's branch picker, the
/// timezone the frame resolves from the branch.
void invalidateBranches(WidgetRef ref) {
  ref.read(realtimeBusProvider).invalidate(const ['/branches']);
  ref.invalidate(branchesProvider);
}

/// The kinds the backend's AppError writes before its sentence.
final RegExp _serverKindPrefix = RegExp(
  r'^(?:Unauthorized|Forbidden|Not found|Bad request|Conflict|'
  r'Service unavailable|Database error): ',
);

/// What a failed call says (the web's `getErrorMessage`, ADM-APP-117): a
/// known `code` → its `errors.codes.*` sentence; an uncoded 403 → "You
/// don't have permission to perform this action." in the active language;
/// else the server's sentence without its kind prefix ("Conflict: …").
String branchErrorText(Object? error, Translator t) {
  if (error is ApiException) {
    final code = error.code;
    if (code != null && t.exists('errors.codes.$code')) {
      final details = error.details;
      final vars = details is Map && details['vars'] is Map
          ? (details['vars'] as Map).cast<String, Object?>()
          : const <String, Object?>{};
      return t('errors.codes.$code', args: vars);
    }
    if (error.status == 429 && code == null) return t('errors.tooManyRequests');
    if (error.status == 403 && code == null) return t('errors.unauthorized');
    final text = error.message.replaceFirst(_serverKindPrefix, '');
    if (text.isNotEmpty) return text;
  }
  return errorMessage(error, t);
}

/// A string that is null or blank reads as absent (the web's `||` and
/// truthiness checks).
bool hasText(String? s) => s != null && s.isNotEmpty;

/// The printer's brand as the table shows it (CSS `capitalize`).
String printerBrandLabel(PrinterBrand brand) {
  final raw = brand.toJson();
  return raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1);
}

/// The printer's address as the table shows it, `<ip>:<port>`; a part that
/// is not set reads empty (a model with no IP reads ":9100", as on the web).
String printerAddress(Branch b) =>
    '${b.printerIp ?? ''}:${b.printerPort ?? ''}';

/// The export's printer cell: `<brand> @ <ip>:<port>`, or "—". A part that is
/// not set is left empty (the web writes the word `null` there).
String printerExportCell(Branch b) {
  final brand = b.printerBrand;
  if (brand == null) return '—';
  return '${brand.toJson()} @ ${printerAddress(b)}';
}
