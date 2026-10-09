/// The Branches unit's reads and the rules its screens share: the branch list
/// (`useListBranches`), the timezone list (`useListTimezones`), the web's
/// `invalidateBranches()`, the printer cell's words and the web's
/// `getErrorMessage` wording for a failed call.
library;

import 'package:dashboard_api/dashboard_api.dart' show Branch, PrinterBrand;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../orgs/org_errors.dart' show orgErrorWords;

/// `GET /branches?org_id=<org>&include_warehouses=true` (listBranches) for
/// [orgId]: every branch and warehouse, inactive included, unpaginated. The
/// page reads core's `branchesProvider` (the scope bar's same request); this
/// forwards to it for the scope's own org, so the Users dialogs share that
/// one request, and asks on its own for another org. A
/// `branch.settings_changed` nudge (or [invalidateBranches]) asks again, as
/// the web's `/branches` prefix invalidation does.
final adminBranchesProvider = FutureProvider.autoDispose
    .family<List<Branch>, String>((ref, orgId) async {
      ref.webCache();
      if (ref.watch(orgIdProvider) == orgId) {
        return await ref.watch(branchesProvider.future) ?? const <Branch>[];
      }
      ref.watch(realtimeEpochProvider('/branches?org_id=$orgId'));
      return ref
          .watch(apiProvider)
          .branches
          .listBranches(orgId: orgId, includeWarehouses: true);
    });

/// `GET /timezones` (listTimezones) for the timezone select.
final branchTimezonesProvider = FutureProvider.autoDispose<List<String>>((ref) {
  ref.webCache();
  return ref.watch(apiProvider).branches.listTimezones();
});

/// The web's `invalidateBranches()`: every read whose key starts with
/// `/branches` (this page's list, the scope bar's branch picker). Pass the
/// bus read before the await, so a page or dialog closed mid-save still
/// refreshes.
void invalidateBranches(RealtimeBus bus) => bus.invalidate(const ['/branches']);

/// What a failed call says: the web's `getErrorMessage` ladder (ADM-APP-117),
/// shared with the orgs page.
String branchErrorText(Object? error, Translator t) => orgErrorWords(error, t);

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
