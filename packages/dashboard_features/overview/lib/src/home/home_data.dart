/// What the home computes in the client from its reads (inventory §3.2):
/// the KPI source and figures, the payment map, the ranked branches, the
/// scope's labels. Pure, so each rule is tested on its own.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show BranchComparison, BranchSalesReport, OrgComparisonReport;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home_providers.dart';

/// The headline figures (piastres for money).
class HomeKpis {
  const HomeKpis({
    this.revenue = 0,
    this.orders = 0,
    this.voided = 0,
    this.tips = 0,
  });

  final int revenue;
  final int orders;
  final int voided;
  final int tips;

  /// `orders ? Math.round(revenue / orders) : 0`, in the browser (not the
  /// server's `avg_order_value`).
  int get avgTicket => orders == 0 ? 0 : (revenue / orders).round();
}

/// One payment method's slice: its key and its money.
typedef HomePayment = ({String method, int value});

/// A branch ranked by revenue, with its share of the top branch's.
typedef HomeRankedBranch = ({BranchComparison row, double pct});

/// `sumMethodMaps`: the per-method sums of [maps] (`Number(v) || 0`).
Map<String, int> sumMethodMaps(Iterable<Object?> maps) {
  final out = <String, int>{};
  for (final m in maps) {
    if (m is! Map) continue;
    for (final e in m.entries) {
      final v = e.value;
      out['${e.key}'] =
          (out['${e.key}'] ?? 0) + (v is num && v.isFinite ? v.round() : 0);
    }
  }
  return out;
}

/// Methods with money, largest first.
List<HomePayment> paymentSlices(Map<String, int> map) {
  final out = [
    for (final e in map.entries)
      if (e.value > 0) (method: e.key, value: e.value),
  ]..sort((a, b) => b.value.compareTo(a.value));
  return out;
}

/// The top six branches by revenue, each with `revenue / max(1, top)`.
List<HomeRankedBranch> rankBranches(List<BranchComparison> rows) {
  var top = 1;
  for (final b in rows) {
    if (b.totalRevenue > top) top = b.totalRevenue;
  }
  final sorted = [...rows]
    ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
  return [for (final b in sorted.take(6)) (row: b, pct: b.totalRevenue / top)];
}

/// "Cairo time", or `<city> time` for another zone (`America/New_York` →
/// `New York`).
String timezoneLabel(String zone, Translator t) {
  if (zone == appTimezone) return t('common.cairoTime');
  final city = zone.split('/').last.replaceAll('_', ' ');
  return t('common.timezoneLabel', args: {'city': city});
}

/// The reads the KPI strip, payment mix, branch performance and subtitle
/// share, and what the client derives from them.
class HomeData {
  const HomeData({
    required this.scope,
    required this.branchSales,
    required this.comparison,
  });

  /// Watches E1 (branch picked) and E3 (org in scope) for [scope].
  factory HomeData.watch(WidgetRef ref, Scope scope) => HomeData(
    scope: scope,
    branchSales: watchIf(
      ref,
      scope.branchId != null,
      homeBranchSalesProvider(scope),
    ),
    comparison: watchIf(
      ref,
      scope.orgId != null,
      homeComparisonProvider(scope),
    ),
  );

  final Scope scope;
  final AsyncValue<BranchSalesReport?> branchSales;
  final AsyncValue<OrgComparisonReport?> comparison;

  bool get branchPicked => scope.branchId != null;

  List<BranchComparison> get branches => comparison.value?.branches ?? const [];

  /// Branch sales when a branch is picked and they loaded; otherwise the
  /// comparison's sums (also when branch sales failed: the web's fallback).
  HomeKpis get kpis {
    final d = branchSales.value;
    if (branchPicked && d != null) {
      return HomeKpis(
        revenue: d.totalRevenue,
        orders: d.totalOrders,
        voided: d.voidedOrders,
        tips: d.totalTips ?? 0,
      );
    }
    var k = const HomeKpis();
    for (final b in branches) {
      k = HomeKpis(
        revenue: k.revenue + b.totalRevenue,
        orders: k.orders + b.totalOrders,
        voided: k.voided + b.voidedOrders,
        tips: k.tips + (b.totalTips ?? 0),
      );
    }
    return k;
  }

  bool get kpiLoading =>
      branchPicked ? branchSales.firstLoad : comparison.firstLoad;

  /// The payment mix's read failed (branch sales, or the comparison).
  bool get paymentsFailed =>
      branchPicked ? branchSales.hasError : comparison.hasError;

  List<HomePayment> get payments => paymentSlices(
    branchPicked
        ? sumMethodMaps([branchSales.value?.revenueByMethod])
        : sumMethodMaps(branches.map((b) => b.revenueByMethod)),
  );

  List<HomeRankedBranch> get rankedBranches => rankBranches(branches);

  /// "All branches", the picked branch's name from the comparison, else
  /// "Branch".
  String branchLabel(Translator t) {
    final id = scope.branchId;
    if (id == null) return t('scope.allBranches');
    for (final b in branches) {
      if (b.branchId == id) return b.branchName;
    }
    return t('scope.branch');
  }
}
