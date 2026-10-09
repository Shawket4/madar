/// Financial's reads and what the web computes in the browser (REP-FIN):
/// one autoDispose read per endpoint, keyed by exactly the params the
/// request sends (the web's React Query key), each refetched by the
/// realtime prefixes of its path (`till.*` → `/reports`, `resync` → all;
/// `/insights` only on `resync` or after a decision / target save).
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── keys ────────────────────────────────────────────────────────────────

/// `GET /insights/branches/{id}/menu-margin?from&to[&cost_basis=current]`.
typedef FinLedgerKey = ({
  String branchId,
  String from,
  String to,
  bool current,
});

/// A branch- or org-scoped read over the period.
typedef FinRange = ({String id, String from, String to});

/// The Revenue tab's timeseries (`granularity` = daily | monthly).
typedef FinSeriesKey = ({String id, String from, String to, String gran});

/// `GET /insights/decisions?org_id[&branch_id]`.
typedef FinDecisionsKey = ({String orgId, String? branchId});

extension FinScopeKeys on Scope {
  /// The ledger the page (and the prefetch) reads first: Snapshot basis.
  FinLedgerKey finLedger({bool current = false}) =>
      (branchId: scopeBranchId, from: from, to: to, current: current);

  /// The analytics reads' key: the scope branch (or the sentinel).
  FinRange get finSales => (id: scopeBranchId, from: from, to: to);

  FinSeriesKey finSeries(String gran) =>
      (id: scopeBranchId, from: from, to: to, gran: gran);
}

DateTime _at(String iso) => DateTime.parse(iso);

// ── insights ────────────────────────────────────────────────────────────

/// REP-FIN-007 the margin ledger, one report for the whole period.
final finLedgerProvider = FutureProvider.autoDispose
    .family<MarginLedgerReport, FinLedgerKey>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/insights/branches/${k.branchId}/menu-margin'),
      );
      return ref
          .watch(apiProvider)
          .insights
          .menuMarginLedger(
            branchId: k.branchId,
            from: _at(k.from),
            to: _at(k.to),
            costBasis: k.current ? 'current' : null,
          );
    });

/// REP-FIN-037 the org's margin targets, read when the editor opens.
final finTargetsProvider = FutureProvider.autoDispose
    .family<MarginTargets, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/insights/margin-target'));
      return ref.watch(apiProvider).insights.getMarginTargets(orgId: orgId);
    });

/// REP-FIN-046 repricing suggestions (no period, no basis: REP-FIN-074).
final finRepricingProvider = FutureProvider.autoDispose
    .family<RepricingReport, String>((ref, branchId) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/insights/branches/$branchId/repricing'),
      );
      return ref.watch(apiProvider).insights.repricing(branchId: branchId);
    });

/// One logged decision; [measuring] while the server has no after-window
/// yet (`impact: null`).
typedef FinDecision = ({DecisionOut d, bool measuring});

/// REP-FIN-050 the decision log. Read through the transport: the generated
/// `DecisionOut.impact` is non-nullable while the backend sends `null`
/// until a day of after-data exists, so the generated decoder would fail
/// the whole tab on any fresh decision (api candidate: make it nullable).
final finDecisionsProvider = FutureProvider.autoDispose
    .family<List<FinDecision>, FinDecisionsKey>((ref, k) async {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/insights/decisions'));
      final res = await ref
          .watch(transportProvider)
          .send(
            ApiRequest(
              method: 'GET',
              path: '/insights/decisions',
              query: {
                'org_id': [k.orgId],
                if (k.branchId != null) 'branch_id': [k.branchId!],
              },
            ),
          );
      final list = jsonDecode(utf8.decode(res.bodyBytes));
      return [
        for (final e in (list as List).cast<Map<String, Object?>>())
          (
            d: DecisionOut.fromJson({
              ...e,
              'impact': e['impact'] ?? const <String, Object?>{},
            }),
            measuring: e['impact'] == null,
          ),
      ];
    });

/// REP-FIN-030…032 `POST /insights/decisions?org_id`. Through the
/// transport too: the answer's `impact` is null for a fresh decision, which
/// the generated decoder refuses (see [finDecisionsProvider]); the page
/// never reads the answer.
Future<void> finCreateDecision(
  ApiTransport transport,
  String orgId,
  CreateDecisionRequest body,
) => transport.send(
  ApiRequest(
    method: 'POST',
    path: '/insights/decisions',
    query: {
      'org_id': [orgId],
    },
    body: body.toJson(),
  ),
);

/// REP-FIN-050 the org's users (who made each decision).
final finUsersProvider = FutureProvider.autoDispose
    .family<List<UserPublic>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/users'));
      return ref.watch(apiProvider).users.listUsers(orgId: orgId);
    });

// ── revenue / channel ───────────────────────────────────────────────────

/// REP-FIN-055/056 `…/sales/timeseries?granularity=daily|monthly`.
final finSeriesProvider = FutureProvider.autoDispose
    .family<List<TimeseriesPoint>, FinSeriesKey>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/${k.id}/sales/timeseries'),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchSalesTimeseries(
            branchId: k.id,
            from: _at(k.from),
            to: _at(k.to),
            granularity: k.gran,
          );
    });

/// REP-FIN-057 `…/sales/peak-hours`.
final finPeakHoursProvider = FutureProvider.autoDispose
    .family<List<PeakHourPoint>, FinRange>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/${k.id}/sales/peak-hours'),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchSalesPeakHours(
            branchId: k.id,
            from: _at(k.from),
            to: _at(k.to),
          );
    });

/// REP-FIN-058 `…/sales/peak-days`.
final finPeakDaysProvider = FutureProvider.autoDispose
    .family<List<PeakDayPoint>, FinRange>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/${k.id}/sales/peak-days'),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchSalesPeakDays(
            branchId: k.id,
            from: _at(k.from),
            to: _at(k.to),
          );
    });

/// REP-FIN-064 `…/channel-breakdown`.
final finChannelsProvider = FutureProvider.autoDispose
    .family<List<ChannelBreakdownRow>, FinRange>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/${k.id}/channel-breakdown'),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchChannelBreakdown(
            branchId: k.id,
            from: _at(k.from),
            to: _at(k.to),
          );
    });

// ── inventory-backed tabs ───────────────────────────────────────────────

/// REP-FIN-066 the branch's stock value now (no period).
final finBranchValuationProvider = FutureProvider.autoDispose
    .family<InventoryValuationReport, String>((ref, id) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/$id/inventory-valuation'),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchInventoryValuation(branchId: id);
    });

/// REP-FIN-066 the org's stock value now.
final finOrgValuationProvider = FutureProvider.autoDispose
    .family<InventoryValuationReport, String>((ref, id) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/reports/orgs/$id/inventory-valuation'));
      return ref.watch(apiProvider).reports.orgInventoryValuation(orgId: id);
    });

/// REP-FIN-066 the org catalog (ingredient → category name).
final finCatalogProvider = FutureProvider.autoDispose
    .family<List<OrgIngredient>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/inventory/orgs/$orgId/catalog'));
      return ref.watch(apiProvider).inventory.listCatalog(orgId: orgId);
    });

/// REP-FIN-068 branch supplier spend.
final finBranchSpendProvider = FutureProvider.autoDispose
    .family<List<SupplierSpendRow>, FinRange>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/${k.id}/supplier-spend'),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchSupplierSpend(
            branchId: k.id,
            from: _at(k.from),
            to: _at(k.to),
          );
    });

/// REP-FIN-068 org supplier spend.
final finOrgSpendProvider = FutureProvider.autoDispose
    .family<List<SupplierSpendRow>, FinRange>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/reports/orgs/${k.id}/supplier-spend'));
      return ref
          .watch(apiProvider)
          .reports
          .orgSupplierSpend(orgId: k.id, from: _at(k.from), to: _at(k.to));
    });

/// REP-FIN-069 branch material cost trend.
final finBranchTrendProvider = FutureProvider.autoDispose
    .family<List<MaterialCostTrendRow>, FinRange>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/${k.id}/material-cost-trend'),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchMaterialCostTrend(
            branchId: k.id,
            from: _at(k.from),
            to: _at(k.to),
          );
    });

/// REP-FIN-069 org material cost trend.
final finOrgTrendProvider = FutureProvider.autoDispose
    .family<List<MaterialCostTrendRow>, FinRange>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/orgs/${k.id}/material-cost-trend'),
      );
      return ref
          .watch(apiProvider)
          .reports
          .orgMaterialCostTrend(orgId: k.id, from: _at(k.from), to: _at(k.to));
    });

/// `invalidateInsights()`: every `/insights*` read (ledger, repricing,
/// decisions, targets, the home margin watch).
void invalidateInsights(RealtimeBus bus) => bus.invalidate(const ['/insights']);

// ── what the web computes ───────────────────────────────────────────────

/// REP-FIN-011/012 the trend pill's ratio; none when prev is 0 or missing.
double? finTrend(num? cur, num? prev) =>
    cur != null && prev != null && prev > 0 ? (cur - prev) / prev : null;

/// The Kasavana–Smith classes, in the legend's and the filter's order.
const List<String> finClasses = ['star', 'workhorse', 'challenge', 'dog'];

/// REP-FIN-020/021/022 the ledger rows the table (and its export) shows.
List<MarginLedgerRow> finFilterRows(
  List<MarginLedgerRow> rows, {
  String? klass,
  bool flaggedOnly = false,
}) => [
  for (final r in rows)
    if ((!flaggedOnly || r.flags.isNotEmpty) &&
        (klass == null || r.class_ == klass))
      r,
];

/// REP-FIN-034 a signal's chip tone.
DashTone finSignalTone(String kind) => switch (kind) {
  'below_cost' => DashTone.danger,
  'below_target' || 'cost_spike' => DashTone.warning,
  'price_candidate' => DashTone.info,
  _ => DashTone.neutral,
};

/// REP-FIN-034 a signal's chip label; an unknown kind shows its code.
String finSignalLabel(Translator t, String kind) {
  final key = 'insights.signals.label.$kind';
  return t.exists(key) ? t(key) : kind;
}

/// REP-FIN-035 the plain-language reason (money params in piastres,
/// percents on 0-100, shown with at most 1 dp).
String finSignalReason(Translator t, DashFormat f, Signal s) {
  final p = s.params;
  double numOf(String k) {
    final v = p[k];
    return v is num ? v.toDouble() : double.tryParse('${v ?? 0}') ?? 0;
  }

  String pct1(double v) =>
      f.fmtNumber(v, const NumberOptions(maximumFractionDigits: 1));
  switch (s.kind) {
    case 'below_cost':
      return t(
        'insights.signals.reason.below_cost',
        args: {'margin': f.fmtMoney(numOf('margin'))},
      );
    case 'below_target':
      final base = t(
        'insights.signals.reason.below_target',
        args: {
          'marginPct': pct1(numOf('margin_pct')),
          'targetPct': pct1(numOf('target_pct')),
        },
      );
      if (numOf('adaptive_bar') > 0) {
        return '$base ${t('insights.signals.reason.adaptive_note', args: {'pts': pct1(numOf('adaptive_bar'))})}';
      }
      return base;
    case 'cost_spike':
      return t(
        'insights.signals.reason.cost_spike',
        args: {
          'ingredient': '${p['ingredient'] ?? ''}',
          'pct': pct1(numOf('pct')),
        },
      );
    case 'price_candidate':
      if (p['caution'] == true) {
        return t(
          'insights.signals.reason.price_candidate_caution',
          args: {'delta': f.fmtMoney(numOf('last_margin_per_day_delta').abs())},
        );
      }
      if (p['elasticity'] is num) {
        final forecast = numOf('expected_margin_per_day_delta');
        return t(
          'insights.signals.reason.price_candidate_learned',
          args: {
            'price': f.fmtMoney(numOf('suggested_price')),
            'forecast': f.fmtMoney(forecast < 0 ? 0 : forecast),
          },
        );
      }
      return t(
        'insights.signals.reason.price_candidate',
        args: {'price': f.fmtMoney(numOf('suggested_price'))},
      );
    case 'removal_candidate':
      return t('insights.signals.reason.removal_candidate');
    case 'recipe_incomplete':
      return t('insights.signals.reason.recipe_incomplete');
    default:
      return s.kind;
  }
}

/// REP-FIN-051 an action's words; an unknown action shows its code.
String finActionLabel(Translator t, String action) => switch (action) {
  'acted' || 'dismissed' || 'snoozed' => t('insights.actions.$action'),
  _ => action,
};

/// REP-FIN-036 the margin-target trigger's words.
String finTargetText(Translator t, DashFormat f, double? pct, String? source) {
  final label = f.fmtNumber(
    pct ?? 0,
    const NumberOptions(maximumFractionDigits: 1),
  );
  return switch (source) {
    'branch' => t('insights.target.branchSource', args: {'pct': label}),
    'org' => t('insights.target.orgSource', args: {'pct': label}),
    _ => t('insights.target.defaultSource', args: {'pct': label}),
  };
}

/// REP-FIN-038 a target field: empty (= unchanged) or a finite 0 < v < 100.
bool finPctValid(String s) {
  if (s.trim().isEmpty) return true;
  final v = double.tryParse(s.trim());
  return v != null && v.isFinite && v > 0 && v < 100;
}

/// JavaScript's `String(n)` for a stored target (60 → "60", 55.5 → "55.5").
String finPctString(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// One dot of the quadrant: x = share of units (%), y = margin per unit
/// (piastres).
typedef FinDot = ({double x, double y, MarginLedgerRow row});

/// REP-FIN-043 the quadrant model (`quadrant.ts`): the server's classes,
/// placed from units, with the two split lines rebuilt over the WHOLE
/// classified set (sold, known margin): 70/n % and Σmargin / Σunits.
class FinQuadrant {
  FinQuadrant(List<MarginLedgerRow> rows) {
    final classified = [
      for (final r in rows)
        if (r.quantitySold > 0 && r.margin != null) r,
    ];
    var units = 0;
    var margin = 0;
    for (final r in classified) {
      units += r.quantitySold;
      margin += r.margin!;
    }
    for (final r in classified) {
      final c = r.class_;
      if (c == null || !finClasses.contains(c)) continue;
      dots[c]!.add((
        x: r.quantitySold / units * 100,
        y: r.margin! / r.quantitySold,
        row: r,
      ));
      plotted++;
    }
    popularityThresholdPct = classified.isEmpty ? 0 : 70 / classified.length;
    unitMarginThreshold = units > 0 ? margin / units : 0;
  }

  final Map<String, List<FinDot>> dots = {for (final c in finClasses) c: []};
  int plotted = 0;
  late final double popularityThresholdPct;
  late final double unitMarginThreshold;

  int count(String c) => dots[c]!.length;
}

/// REP-FIN-066 the valuation by catalog category: item values summed per
/// category name ("Uncategorized" when not in the catalog; null values
/// skipped), largest first.
List<(String, int)> finByCategory(
  InventoryValuationReport? valuation,
  List<OrgIngredient>? catalog,
  String uncategorized,
) {
  final cat = {
    for (final c in catalog ?? const <OrgIngredient>[]) c.id: c.categoryName,
  };
  final sums = <String, int>{};
  for (final it in valuation?.items ?? const <ValuationRow>[]) {
    final v = it.value;
    if (v == null) continue;
    final key = cat[it.orgIngredientId] ?? uncategorized;
    sums[key] = (sums[key] ?? 0) + v;
  }
  final out = [for (final e in sums.entries) (e.key, e.value)];
  out.sort((a, b) => b.$2.compareTo(a.$2));
  return out;
}
