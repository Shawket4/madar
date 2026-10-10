/// The pricing page's own reads, one provider per web hook, keyed by exactly
/// the request's params (the web's query keys):
///
/// | provider | web hook | path |
/// |---|---|---|
/// | [pricingAddonCatalogProvider] | `useListAddonCatalog` | `GET /addon-items/catalog` |
/// | [channelAddonOverridesProvider] | `useListChannelAddonOverrides` | `GET /delivery/channel-addon-overrides` |
///
/// Reads the web shares with other pages share their provider (and so their
/// cache) here too: the catalog pages (`menuCatalogProvider`) and the branch
/// add-on rows (`branchAddonOverridesProvider`) with the items page, an
/// item's studio (`menuStudioProvider`) with the studio, and the branches
/// with the shell's picker.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../items/items_providers.dart';
import '../shared/menu_queries.dart';
import 'pricing_model.dart';

/// `{org_id, search, page, per_page: 24}` (search null when blank).
typedef PricingPageKey = ({String orgId, String? search, int page});

/// `GET /addon-items/catalog`: one page of the org's add-ons.
final pricingAddonCatalogProvider = FutureProvider.autoDispose
    .family<PaginatedAddonItems, PricingPageKey>((ref, k) {
      ref.webCache();
      watchMenuPath(ref, MenuPaths.addonCatalog);
      return ref
          .watch(apiProvider)
          .menu
          .listAddonCatalog(
            orgId: k.orgId,
            search: k.search,
            page: k.page,
            perPage: pricingPerPage,
          );
    });

/// `{branch_id, channel}`.
typedef ChannelKey = ({String branchId, String channel});

/// `GET /delivery/channel-addon-overrides?branch_id&channel`.
final channelAddonOverridesProvider = FutureProvider.autoDispose
    .family<List<ChannelAddonOverride>, ChannelKey>((ref, k) {
      ref.webCache();
      watchMenuPath(ref, MenuPaths.channelAddonOverrides);
      return ref
          .watch(apiProvider)
          .delivery
          .listChannelAddonOverrides(branchId: k.branchId, channel: k.channel);
    });

/// The catalog key of a pricing page: the items page's key with no
/// category or recipe filter (the web's query keys drop undefined params).
CatalogQuery pricingCatalogKey(String orgId, String? search, int page) => (
  orgId: orgId,
  categoryId: null,
  search: search,
  hasRecipe: null,
  page: page,
);

/// The add-on page key.
PricingPageKey pricingAddonKey(String orgId, String? search, int page) =>
    (orgId: orgId, search: search, page: page);

/// The web's `prefetchRoute` for the retired `/menu/overrides`, aimed at the
/// merged page: every read the page fires on mount with one branch scoped.
void prefetchPricing(DashPrefetcher warm, Scope s) {
  final org = s.orgId, branch = s.branchId;
  if (org == null || branch == null) return;
  warm(menuCatalogProvider(pricingCatalogKey(org, null, 1)));
  warm(pricingAddonCatalogProvider(pricingAddonKey(org, null, 1)));
  warm(branchAddonOverridesProvider(branch));
  for (final ch in pricingChannels) {
    warm(channelAddonOverridesProvider((branchId: branch, channel: ch)));
  }
}
