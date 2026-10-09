/// The combos list's reads (the web's `useCombos(params)` and
/// `useListCategories({org_id})` in `features/combos/combos-page.tsx`), each
/// keyed by exactly the arguments its request sends.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// C2 `GET /categories?org_id`: the Category filter's options and the
/// Category column's names.
final comboCategoriesProvider = FutureProvider.autoDispose
    .family<List<Category>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(OffersPaths.categories));
      return ref.watch(apiProvider).menu.listCategories(orgId: orgId);
    });
