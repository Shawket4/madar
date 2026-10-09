/// The links page editor's reads, each keyed by exactly what it sends:
///
/// - [linksPageProvider]: `GET /orgs/{id}/links-page` (`getLinksPage`).
/// - [linksQrProvider]: `GET /orgs/{id}/links-qr` with no render options
///   (the "QR code" button; warmed on intent).
/// - [publicLinksProvider]: `GET /public/orgs/links?org_id=` (the preview,
///   the web's `staleTime: 60_000`).
///
/// A save invalidates the first and the last, and the Brand page's org read
/// ([linksSavedPaths]).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show LinksPageSettings, PublicLinksPage, QrResponse;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand_appearance/brand_data.dart' show orgBrandKey;

String linksPagePath(String orgId) => '/orgs/$orgId/links-page';
const String publicLinksPath = '/public/orgs/links';

/// What the web's save invalidates: `getGetLinksPageQueryKey(orgId)` and
/// `getPublicOrgLinksQueryKey({org_id})`; plus the Brand page's org read
/// (divergence: the save also writes the org's social links, LNK-021).
List<String> linksSavedPaths(String orgId) => [
  linksPagePath(orgId),
  publicLinksPath,
  orgBrandKey,
];

final linksPageProvider = FutureProvider.autoDispose
    .family<LinksPageSettings, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(linksPagePath(orgId)));
      return ref.watch(apiProvider).orgs.getLinksPage(id: orgId);
    });

final linksQrProvider = FutureProvider.autoDispose.family<QrResponse, String>((
  ref,
  orgId,
) {
  ref.webCache();
  return ref.watch(apiProvider).qr.orgLinksQr(id: orgId);
});

final publicLinksProvider = FutureProvider.autoDispose
    .family<PublicLinksPage, String>((ref, orgId) {
      ref.webCache(staleTime: const Duration(minutes: 1));
      ref.watch(realtimeEpochProvider(publicLinksPath));
      return ref.watch(apiProvider).orgs.publicOrgLinks(orgId: orgId);
    });
