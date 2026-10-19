/// The Organizations page's reads (the web's `useListOrgs`,
/// `useListTemplates`, `useListTimezones`) and its one invalidation rule
/// (`features/orgs/util.ts` `invalidateOrgs`: every query whose key starts
/// with `/orgs`).
library;

import 'package:dashboard_api/dashboard_api.dart' show Org, OrgTemplate;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/widgets.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `GET /orgs` (listOrgs): every organization, active and inactive,
/// unpaginated (ADM-ORG-003). One cache entry with the shell's org picker,
/// as the web's: this read forwards to core's [orgsProvider] (which keeps the
/// web's fetch time and stale refetch, so a mutation refetches it once), and
/// refreshes it on a `resync` (the web keeps no other
/// realtime subscription here).
final orgsListProvider = FutureProvider.autoDispose<List<Org>>((ref) {
  ref.webCache();
  ref.listen(
    realtimeEpochProvider('/orgs'),
    (_, _) => ref.invalidate(orgsProvider),
  );
  return ref.watch(orgsProvider.future);
}, retry: (_, _) => null);

/// `GET /orgs/templates` (listTemplates), read only while the provision
/// wizard is open (ADM-ORG-025, ADM-ORG-029).
final orgTemplatesProvider = FutureProvider.autoDispose<List<OrgTemplate>>((
  ref,
) {
  ref.webCache();
  ref.watch(realtimeEpochProvider('/orgs/templates'));
  return ref.watch(apiProvider).orgs.listTemplates();
});

/// `GET /timezones` (listTimezones): the options of the timezone selects
/// (ADM-ORG-032, ADM-ORG-049).
final orgTimezonesProvider = FutureProvider.autoDispose<List<String>>((ref) {
  ref.webCache();
  ref.watch(realtimeEpochProvider('/timezones'));
  return ref.watch(apiProvider).branches.listTimezones();
});

/// `invalidateOrgs()`: every read keyed under `/orgs` asks again — this
/// page's list, the org picker's list, the current org, its modules, its
/// readiness and anything else that watches an `/orgs…` epoch.
///
/// Captured BEFORE the await and run after it, always: the dialog or page
/// may close mid-save and the web's query client refetches regardless.
VoidCallback orgsInvalidator(WidgetRef ref) {
  final bus = ref.read(realtimeBusProvider);
  final container = ProviderScope.containerOf(ref.context, listen: false);
  return () {
    // The bus bumps every `/orgs…` epoch (this page's reads among them).
    bus.invalidate(const ['/orgs']);
    container
      ..invalidate(orgsProvider)
      ..invalidate(currentOrgProvider)
      ..invalidate(orgModulesQueryProvider);
  };
}
