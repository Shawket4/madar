/// The combos list's own read (the web's `useCombos(params)` in
/// `features/combos/combos-page.tsx`), keyed by exactly the arguments its
/// request sends. Its categories are the area's shared
/// `offersCategoriesProvider` (the web's one `["/categories", {org_id}]`
/// entry, which the editor and the deal dialog read too).
library;

import 'package:dashboard_api/dashboard_api.dart' show PaginatedCombos;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_options.dart';
import '../shared/offers_cache.dart';

/// Combos a page (`PER_PAGE`).
const int combosPerPage = 25;

/// What `GET /combos` is asked with (the web's key `["/combos", params]`;
/// `per_page` is always [combosPerPage]). Null = not sent.
typedef CombosQuery = ({
  String? q,
  String? categoryId,
  bool? isActive,
  int page,
});

/// C1 `GET /combos`: one page of the org's combos, by name. Refetched by
/// `invalidateCombos()` (any combo or deal write) and a `resync`.
final combosListProvider = FutureProvider.autoDispose
    .family<PaginatedCombos, CombosQuery>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(OffersPaths.combos));
      return ref
          .watch(apiProvider)
          .menu
          .listCombos(
            q: k.q,
            categoryId: k.categoryId,
            isActive: k.isActive,
            page: k.page,
            perPage: combosPerPage,
          );
    });

/// The route's prefetch (`/menu/combos`): the list as it opens (no search,
/// no filter, page 1) and its categories, warmed from any link to it (the
/// editor's Back, the sidebar).
void prefetchCombosList(DashPrefetcher warm, Scope s) {
  if (s.orgId == null) return;
  warm(
    combosListProvider((q: null, categoryId: null, isActive: null, page: 1)),
  );
  warm(offersCategoriesProvider);
}
