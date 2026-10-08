/// The Legal page's reads (REP-LEG-007): the org tax report and the nine
/// audit reports, one provider family each, keyed by the org and the
/// scope's day-bounded instants (the web's React Query keys `[path,
/// {from, to}]`). The endpoints are org-wide; the server narrows a manager
/// to their own branches.
///
/// Each read watches `realtimeEpochProvider(<its path>)`, so a `till.*`
/// event (which invalidates `/reports`) or a `resync` refetches the active
/// tab, as the web's prefix invalidation does.
library;

import 'package:dashboard_api/dashboard_api.dart' show AuditReport, TaxReport;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'legal_words.dart';

/// Which org and period a Legal read covers.
typedef LegalQuery = ({String orgId, String from, String to});

/// The query for [scope] (null while no org is in scope: nothing is asked).
LegalQuery? legalQueryOf(Scope scope) {
  final org = scope.orgId;
  if (org == null) return null;
  return (orgId: org, from: scope.from, to: scope.to);
}

/// The API path a tab reads (also its realtime key).
String legalPath(LegalTab tab, String orgId) =>
    '/reports/orgs/$orgId/${tab.segment}';

/// `GET /reports/orgs/{orgId}/tax` (orgTaxReport).
final legalTaxProvider = FutureProvider.autoDispose
    .family<TaxReport, LegalQuery>((ref, q) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(legalPath(LegalTab.tax, q.orgId)));
      return ref
          .watch(apiProvider)
          .reports
          .orgTaxReport(
            orgId: q.orgId,
            from: DateTime.parse(q.from),
            to: DateTime.parse(q.to),
          );
    });

/// One audit tab's report (every tab but Tax).
final legalAuditProvider = FutureProvider.autoDispose
    .family<AuditReport, (LegalTab, LegalQuery)>((ref, key) {
      ref.webCache();
      final (tab, q) = key;
      ref.watch(realtimeEpochProvider(legalPath(tab, q.orgId)));
      final api = ref.watch(apiProvider).reports;
      final from = DateTime.parse(q.from);
      final to = DateTime.parse(q.to);
      final org = q.orgId;
      return switch (tab) {
        LegalTab.refunds => api.refundsAudit(orgId: org, from: from, to: to),
        LegalTab.voids => api.voidsAudit(orgId: org, from: from, to: to),
        LegalTab.discounts => api.discountsAudit(
          orgId: org,
          from: from,
          to: to,
        ),
        LegalTab.waivers => api.waiversAudit(orgId: org, from: from, to: to),
        LegalTab.priceOverrides => api.priceOverrides(
          orgId: org,
          from: from,
          to: to,
        ),
        LegalTab.manualDeductions => api.manualDeductionsAudit(
          orgId: org,
          from: from,
          to: to,
        ),
        LegalTab.deductionOverrides => api.deductionOverridesAudit(
          orgId: org,
          from: from,
          to: to,
        ),
        LegalTab.loyaltyAdjustments => api.loyaltyAdjustmentsAudit(
          orgId: org,
          from: from,
          to: to,
        ),
        LegalTab.attendanceCorrections => api.attendanceCorrectionsAudit(
          orgId: org,
          from: from,
          to: to,
        ),
        LegalTab.tax => throw ArgumentError('Tax is not an audit report'),
      };
    });

/// React Query's `isLoading`: the first load, with nothing to show yet.
extension LegalAsync<T> on AsyncValue<T> {
  bool get firstLoad => isLoading && !hasValue && !hasError;
}
