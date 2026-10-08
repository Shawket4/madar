/// The deals page's reads and the words of its refusals (the web's
/// `useDeals({})` and `getErrorMessage(e, {fieldLabel})`).
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart' show ApiException, DealRule;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/offers_cache.dart';
import 'deal_form.dart';

/// `GET /deals` (key `["/deals", {}]`): every deal of the org, refetched
/// after any combo or deal write (`invalidateCombos`) or a `resync`.
final dealsProvider = FutureProvider<List<DealRule>>((ref) async {
  ref.watch(realtimeEpochProvider(OffersPaths.deals));
  return ref.watch(apiProvider).menu.listDeals();
});

/// The list as the page shows it: by `sort`, then by name A→Z.
List<DealRule> sortedDeals(Iterable<DealRule> deals) => deals.sorted((a, b) {
  final s = a.sort.compareTo(b.sort);
  if (s != 0) return s;
  final n = compareAsciiLowerCase(a.name, b.name);
  return n != 0 ? n : a.name.compareTo(b.name);
});

/// A failed deal write in words. A `DEAL_INVALID {field}` refusal names the
/// field in the dialog's own words ("Check the deal's "Percent off"."); any
/// other failure reads as the transport words it ([errorMessage]).
String dealErrorText(Object? error, Translator t) {
  if (error is ApiException && error.code == 'DEAL_INVALID') {
    final details = error.details;
    final vars = details is Map ? details['vars'] : null;
    final field = vars is Map ? vars['field'] : null;
    if (field is String) {
      final key = dealFieldKeys[field];
      return t(
        'errors.codes.DEAL_INVALID',
        args: {'field': key == null ? field : t(key)},
      );
    }
  }
  return errorMessage(error, t);
}
