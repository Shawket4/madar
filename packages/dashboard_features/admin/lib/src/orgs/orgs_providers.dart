/// The Organizations page's reads (the web's `useListOrgs`,
/// `useListTemplates`, `useListTimezones`) and its one invalidation rule
/// (`features/orgs/util.ts` `invalidateOrgs`: every query whose key starts
/// with `/orgs`).
library;

import 'package:dashboard_api/dashboard_api.dart' show Org, OrgTemplate;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `GET /orgs` (listOrgs): every organization, active and inactive,
/// unpaginated (ADM-ORG-003). The web keeps no realtime subscription here;
/// a `resync` (which invalidates everything) refetches it.
final orgsListProvider = FutureProvider.autoDispose<List<Org>>((ref) {
  ref.watch(realtimeEpochProvider('/orgs'));
  return ref.watch(apiProvider).orgs.listOrgs();
});

/// `GET /orgs/templates` (listTemplates), read only while the provision
/// wizard is open (ADM-ORG-025, ADM-ORG-029).
final orgTemplatesProvider = FutureProvider.autoDispose<List<OrgTemplate>>((
  ref,
) {
  ref.watch(realtimeEpochProvider('/orgs/templates'));
  return ref.watch(apiProvider).orgs.listTemplates();
});

/// `GET /timezones` (listTimezones): the options of the timezone selects
/// (ADM-ORG-032, ADM-ORG-049).
final orgTimezonesProvider = FutureProvider.autoDispose<List<String>>((ref) {
  ref.watch(realtimeEpochProvider('/timezones'));
  return ref.watch(apiProvider).branches.listTimezones();
});

/// `invalidateOrgs()`: every read keyed under `/orgs` asks again — this
/// page's list, the org picker's list, the current org, its modules, its
/// onboarding status and anything else that watches an `/orgs…` epoch.
void invalidateOrgs(WidgetRef ref) {
  // The bus bumps every `/orgs…` epoch (this page's reads among them).
  ref.read(realtimeBusProvider).invalidate(const ['/orgs']);
  ref
    ..invalidate(orgsProvider)
    ..invalidate(currentOrgProvider)
    ..invalidate(orgModulesQueryProvider);
}
