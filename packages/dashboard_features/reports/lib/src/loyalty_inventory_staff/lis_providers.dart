/// The reads behind Loyalty, Inventory reports and Staff discipline, one
/// autoDispose provider per endpoint, keyed by exactly the params its
/// request sends (the web's query key), and the key builders the pages,
/// the Retry buttons, the prefetch and the tests share.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart';

// ── loyalty ──────────────────────────────────────────────────────────────

/// `{branch_id?, from, to}`: branch_id only with a branch picked
/// (REP-LOY-003).
typedef LoyaltyKey = ({String? branchId, String from, String to});

extension LoyaltyKeys on Scope {
  LoyaltyKey get loyaltyKey => (branchId: branchId, from: from, to: to);
}

/// REP-LOY-003 `GET /loyalty/behavior`.
final loyaltyBehaviorProvider = FutureProvider.autoDispose
    .family<LoyaltyBehavior, LoyaltyKey>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/loyalty/behavior'));
      return ref
          .watch(apiProvider)
          .loyalty
          .getLoyaltyBehavior(
            branchId: k.branchId,
            from: DateTime.parse(k.from),
            to: DateTime.parse(k.to),
          );
    });

/// REP-LOY-010 `GET /loyalty/campaign-effectiveness`.
final loyaltyCampaignsProvider = FutureProvider.autoDispose
    .family<CampaignEffectiveness, LoyaltyKey>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/loyalty/campaign-effectiveness'));
      return ref
          .watch(apiProvider)
          .loyalty
          .getLoyaltyCampaignEffectiveness(
            branchId: k.branchId,
            from: DateTime.parse(k.from),
            to: DateTime.parse(k.to),
          );
    });

/// REP-LOY-013 `GET /loyalty/liability-trend`.
final loyaltyLiabilityProvider = FutureProvider.autoDispose
    .family<LiabilityTrend, LoyaltyKey>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/loyalty/liability-trend'));
      return ref
          .watch(apiProvider)
          .loyalty
          .getLoyaltyLiabilityTrend(
            branchId: k.branchId,
            from: DateTime.parse(k.from),
            to: DateTime.parse(k.to),
          );
    });

// ── inventory reports ────────────────────────────────────────────────────

/// A report read from the branch endpoint (`org: false`, [id] the branch)
/// or the org one (`org: true`, [id] the org), with `from`/`to`.
typedef InvKey = ({bool org, String id, String from, String to});

/// The low-stock read: the branch's list or the org's, no period.
typedef LowStockKey = ({bool org, String id});

extension InventoryKeys on Scope {
  /// The key [value] reads, or null when it has nothing to ask about (This
  /// branch with All branches selected; no org).
  InvKey? invKey(InventoryScope value) {
    final id = value == InventoryScope.branch ? branchId : orgId;
    if (id == null) return null;
    return (org: value == InventoryScope.org, id: id, from: from, to: to);
  }

  /// Low stock follows the scope bar, not the toggle (REP-INV-015).
  LowStockKey? get lowStockKey {
    final b = branchId;
    if (b != null) return (org: false, id: b);
    final o = orgId;
    return o == null ? null : (org: true, id: o);
  }
}

/// The request path of [report] for [k] (the realtime prefix it answers to).
String invPath(({bool org, String id}) k, String report) => k.org
    ? '/reports/orgs/${k.id}/$report'
    : '/reports/branches/${k.id}/$report';

ReportsApi _reports(Ref ref) => ref.watch(apiProvider).reports;

/// REP-INV-008 `GET …/consumption`.
final invConsumptionProvider = FutureProvider.autoDispose
    .family<List<ConsumptionRow>, InvKey>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider(invPath((org: k.org, id: k.id), 'consumption')),
      );
      final from = DateTime.parse(k.from), to = DateTime.parse(k.to);
      return k.org
          ? _reports(ref).orgConsumption(orgId: k.id, from: from, to: to)
          : _reports(ref).branchConsumption(branchId: k.id, from: from, to: to);
    });

/// REP-INV-009 `GET …/shrinkage`.
final invShrinkageProvider = FutureProvider.autoDispose
    .family<List<ShrinkageRow>, InvKey>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider(invPath((org: k.org, id: k.id), 'shrinkage')),
      );
      final from = DateTime.parse(k.from), to = DateTime.parse(k.to);
      return k.org
          ? _reports(ref).orgShrinkage(orgId: k.id, from: from, to: to)
          : _reports(ref).branchShrinkage(branchId: k.id, from: from, to: to);
    });

/// REP-INV-010 `GET …/waste-report`.
final invWasteProvider = FutureProvider.autoDispose
    .family<List<WasteReportRow>, InvKey>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider(invPath((org: k.org, id: k.id), 'waste-report')),
      );
      final from = DateTime.parse(k.from), to = DateTime.parse(k.to);
      return k.org
          ? _reports(ref).orgWasteReport(orgId: k.id, from: from, to: to)
          : _reports(ref).branchWasteReport(branchId: k.id, from: from, to: to);
    });

/// REP-INV-011 `GET …/po-lead-time`.
final invLeadTimeProvider = FutureProvider.autoDispose
    .family<PoLeadTimeReport, InvKey>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider(invPath((org: k.org, id: k.id), 'po-lead-time')),
      );
      final from = DateTime.parse(k.from), to = DateTime.parse(k.to);
      return k.org
          ? _reports(ref).orgPoLeadTime(orgId: k.id, from: from, to: to)
          : _reports(ref).branchPoLeadTime(branchId: k.id, from: from, to: to);
    });

/// REP-INV-015 `GET …/low-stock`.
final invLowStockProvider = FutureProvider.autoDispose
    .family<List<LowStockRow>, LowStockKey>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(invPath(k, 'low-stock')));
      return k.org
          ? _reports(ref).orgLowStock(orgId: k.id)
          : _reports(ref).branchLowStock(branchId: k.id);
    });

/// The web's `prefetchRoute('/reports/inventory')`: the default tab
/// (Consumption) from the branch endpoint when a branch is picked, else
/// the org's — the key the page opens on (REP-ALL-029).
void prefetchInventoryReports(DashPrefetcher warm, Scope s) {
  final k =
      s.invKey(InventoryScope.branch) ?? s.invKey(InventoryScope.org);
  if (k != null) warm(invConsumptionProvider(k));
}

// ── staff discipline ─────────────────────────────────────────────────────

/// `{from, to, branch_id?}` with local `YYYY-MM-DD` dates (REP-STF-005).
typedef DisciplineKey = ({String from, String to, String? branchId});

/// The key the page reads for [s] (dates in the active zone, [f]'s).
DisciplineKey disciplineKeyOf(Scope s, DashFormat f) => (
  from: localDateParam(f, s.from),
  to: localDateParam(f, s.to),
  branchId: s.branchId,
);

/// The report's request path (its key prefix: under `/staff`).
const String disciplinePath = '/staff/discipline-report';

/// REP-STF-005 `GET /staff/discipline-report`.
final disciplineProvider = FutureProvider.autoDispose
    .family<DisciplineReport, DisciplineKey>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(disciplinePath));
      return ref
          .watch(apiProvider)
          .staff
          .disciplineReport(from: k.from, to: k.to, branchId: k.branchId);
    });
